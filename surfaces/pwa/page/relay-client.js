// surfaces/pwa/page/relay-client.js - the phone's relay client: the four operations of the relay
// port (relays/Port.ps1) - put, get, watch, ack - over a PLUGGABLE TRANSPORT, with the port's distrust
// of the far end written once here for every transport.
//
// WHY A PORT AND NOT A FETCH. The relay is untrusted, and which one serves a deployment is the
// deployment's choice. So the app names no host and speaks to no URL of its own: it is handed a
// transport, picked by name from the deployment's config.json, and every answer
// a transport gives is checked here as relays/Port.ps1 checks a relay's - the shape of each item,
// items at or before the cursor dropped, a second item under one seq dropped, the batch put in seq
// order, holes reported as gaps, and the cursor the caller gets is the last seq DELIVERED, never a
// number the relay chose. A HOLE IS REPORTED APART FROM THE ANOMALIES (gaps, beside anomalies): what
// one means is the caller's to say. In a mailbox its one reader acks, a hole is an item the relay
// lost. In the phone's mailbox it is what a mailbox that is kept small looks like - its senders trim
// their own streams there (relays/Port.ps1, A SENDER TRIMS ITS OWN STREAM), and an older snapshot
// deleted from between two chat envelopes leaves exactly such a hole - so the phone says nothing of it
// (phone-core.js). A transport that throws or answers nonsense comes back unknown with the
// reason; nothing here throws for the far end.
//
// A TRANSPORT is an object of four async functions, each answering { state, value, reason } in
// core/Tristate.ps1's words (known / unknown):
//   put(mailbox, key, text)                 -> known { seq, duplicate }
//   get(mailbox, since, max)                -> known { items: [{ seq, key, text }] }
//   watch(mailbox, since, max, timeoutMs)   -> known { items }  (returns early when there is any)
//   ack(mailbox, through)                   -> known { through }
// The ones made here:
//   memory    a relay in this page's memory, for a demonstration and for tests in one process;
//   binding   every operation handed, as JSON text, to a function the HOST put on the page under a
//             name (a test harness, through the browser's debugging protocol): the local test
//             transport. Nothing on a deployed page provides that function, so there it answers unknown.
//   http      the hosted relay's mailbox API (PR plan item 8): put, read and ack by fetch, a watch by a
//             WebSocket the relay answers with one message of items the moment there are any. At the
//             config's relayOrigin, or - the deployed case - at the page's own origin, because one host
//             serves the app and its relay: no cross-origin request, and connect-src 'self' covers it.
//
// THE RULES ARE relays/Port.ps1's, copied: a mailbox is "<horde>/<reader>", each part 1 to 63 of
// [a-z0-9-] starting with a letter or digit and never a Windows device name; a key 1 to 160 of
// [A-Za-z0-9._:/-]; a text 1 to 1,414,507 printable ASCII characters; seq at most 2^53-1; a batch at
// most 256; a watch at most 60 s. THIS IS THE ONE COPY OF THEM IN JAVASCRIPT: the hosted relay's Worker
// imports mailboxProblem, keyProblem and textProblem from here (with its own, lower, text limit) rather
// than keep a second copy that could drift.
const SEGMENT = /^[a-z0-9][a-z0-9-]{0,62}$/;
const DEVICE = /^(con|prn|aux|nul|com[0-9]|lpt[0-9])$/;
const KEY = /^[A-Za-z0-9._:/-]{1,160}$/;
const TEXT = /^[\x20-\x7e]+$/;
export const LIMITS = { textChars: 1414507, batch: 256, watchMs: 60000, seqMax: 9007199254740991 };

const known = (value) => ({ state: "known", value, reason: "" });
const unknown = (reason) => ({ state: "unknown", value: null, reason });

export function mailboxProblem(mailbox) {
  if (typeof mailbox !== "string") return "a mailbox is text";
  const parts = mailbox.split("/");
  if (parts.length !== 2) return "a mailbox is <horde>/<reader>";
  for (const p of parts) { if (!SEGMENT.test(p) || DEVICE.test(p)) return "'" + p + "' is not a mailbox part"; }
  return "";
}

// "" when key is one a relay holds, else why not.
export function keyProblem(key) {
  return typeof key === "string" && KEY.test(key) ? "" : "the key is not one a relay holds";
}

// "" when text is one a relay holding at most maxChars characters keeps, else why not.
export function textProblem(text, maxChars = LIMITS.textChars) {
  if (typeof text !== "string" || text.length === 0 || text.length > maxChars || !TEXT.test(text)) return "a relay holds printable ASCII texts of 1 to " + maxChars + " characters";
  return "";
}

function checkAnswer(a, what) {
  if (!a || typeof a !== "object" || (a.state !== "known" && a.state !== "unknown")) return unknown("the relay's answer to " + what + " is not an answer");
  if (a.state !== "known") return unknown(String(a.reason || "the relay could not " + what));
  if (!a.value || typeof a.value !== "object") return unknown("the relay's answer to " + what + " holds nothing");
  return null;
}

// Rebuild a batch as relays/Port.ps1 does: { items, next, anomalies, gaps }.
function rebuild(items, since, max) {
  const anomalies = [];
  const gaps = [];
  const bySeq = new Map();
  for (const it of Array.isArray(items) ? items : []) {
    if (!it || !Number.isSafeInteger(it.seq) || it.seq < 1 || it.seq > LIMITS.seqMax || typeof it.key !== "string" || typeof it.text !== "string") { anomalies.push("a malformed item was dropped"); continue; }
    if (keyProblem(it.key) || textProblem(it.text)) { anomalies.push("item " + it.seq + " was dropped: its key or text is not one a relay holds"); continue; }
    if (it.seq <= since) { anomalies.push("item " + it.seq + " was dropped: it is at or before the cursor " + since); continue; }
    if (bySeq.has(it.seq)) { anomalies.push("a second item under seq " + it.seq + " was dropped"); continue; }
    bySeq.set(it.seq, { seq: it.seq, key: it.key, text: it.text });
  }
  const sorted = [...bySeq.values()].sort((a, b) => a.seq - b.seq);
  if (sorted.length > max) { anomalies.push((sorted.length - max) + " item(s) past the batch asked for were dropped"); sorted.length = max; }
  let last = since;
  for (const it of sorted) { if (it.seq > last + 1) gaps.push("a gap: seq " + (last + 1) + " to " + (it.seq - 1) + " were not delivered"); last = it.seq; }
  return { items: sorted, next: last, anomalies, gaps };
}

export function createRelayClient(transport) {
  const call = async (what, fn) => {
    if (!transport || typeof transport[what] !== "function") return unknown("this relay transport cannot " + what);
    try { return await fn(); } catch (x) { return unknown("the relay transport failed to " + what + ": " + (x && x.message ? x.message : x)); }
  };
  return {
    async put(mailbox, key, text) {
      const why = mailboxProblem(mailbox);
      if (why) return unknown(why);
      const problem = keyProblem(key) || textProblem(text);
      if (problem) return unknown(problem);
      const a = await call("put", () => transport.put(mailbox, key, text));
      const bad = checkAnswer(a, "put");
      if (bad) return bad;
      if (!Number.isSafeInteger(a.value.seq) || a.value.seq < 1 || typeof a.value.duplicate !== "boolean") return unknown("the relay's receipt does not hold together");
      return known({ mailbox, key, seq: a.value.seq, duplicate: a.value.duplicate });
    },
    async get(mailbox, since, max = LIMITS.batch) { return this._read("get", mailbox, since, max, 0); },
    async watch(mailbox, since, max = LIMITS.batch, timeoutMs = 25000) { return this._read("watch", mailbox, since, max, timeoutMs); },
    async _read(what, mailbox, since, max, timeoutMs) {
      const why = mailboxProblem(mailbox);
      if (why) return unknown(why);
      if (!Number.isSafeInteger(since) || since < 0 || since > LIMITS.seqMax) return unknown("the cursor is a whole number from 0 to 2^53-1");
      if (!Number.isSafeInteger(max) || max < 1 || max > LIMITS.batch) return unknown("a batch is 1 to " + LIMITS.batch + " items");
      if (what === "watch" && (!Number.isSafeInteger(timeoutMs) || timeoutMs < 0 || timeoutMs > LIMITS.watchMs)) return unknown("a watch waits 0 to " + LIMITS.watchMs + " ms");
      const a = await call(what, () => (what === "watch" ? transport.watch(mailbox, since, max, timeoutMs) : transport.get(mailbox, since, max)));
      const bad = checkAnswer(a, what);
      if (bad) return bad;
      const r = rebuild(a.value.items, since, max);
      return known({ mailbox, since, next: r.next, items: r.items, anomalies: r.anomalies, gaps: r.gaps });
    },
    async ack(mailbox, through) {
      const why = mailboxProblem(mailbox);
      if (why) return unknown(why);
      if (!Number.isSafeInteger(through) || through < 0 || through > LIMITS.seqMax) return unknown("an ack is through a whole number from 0 to 2^53-1");
      const a = await call("ack", () => transport.ack(mailbox, through));
      const bad = checkAnswer(a, "ack");
      if (bad) return bad;
      if (a.value.through !== through) return unknown("the relay acked another seq than the one asked");
      return known({ mailbox, through });
    }
  };
}

// --- the transports made here ---

// A relay in memory: put is idempotent by key, seq contiguous from 1, ack trims (trim.on.ack).
export function memoryTransport() {
  const boxes = new Map();
  const box = (m) => { if (!boxes.has(m)) boxes.set(m, { items: [], head: 0 }); return boxes.get(m); };
  const after = (b, since, max) => b.items.filter((i) => i.seq > since).slice(0, max).map((i) => ({ ...i }));
  return {
    async put(mailbox, key, text) {
      const b = box(mailbox);
      const held = b.items.find((i) => i.key === key);
      if (held) return known({ seq: held.seq, duplicate: true });
      b.head += 1;
      b.items.push({ seq: b.head, key, text });
      return known({ seq: b.head, duplicate: false });
    },
    async get(mailbox, since, max) { return known({ items: after(box(mailbox), since, max) }); },
    async watch(mailbox, since, max, timeoutMs) {
      const end = Date.now() + timeoutMs;
      for (;;) {
        const items = after(box(mailbox), since, max);
        if (items.length || Date.now() >= end) return known({ items });
        await new Promise((r) => setTimeout(r, Math.min(50, Math.max(0, end - Date.now()))));
      }
    },
    async ack(mailbox, through) {
      const b = box(mailbox);
      if (through > b.head) return unknown("the mailbox " + mailbox + " ends at " + b.head + "; an ack through " + through + " is past it");
      b.items = b.items.filter((i) => i.seq > through);
      return known({ through });
    }
  };
}

// The local test transport: each operation as one JSON text { id, op, ...args } handed to
// host[name] (a binding the host added, which returns nothing), and answered by the host calling
// host[name + "Reply"](id, text) with the JSON text of a tristate answer. host is the page's global
// object. A reply to an id nobody waits on is dropped; an operation with no reply in timeoutMs plus
// 30 s is unknown, so a host that went away leaves no promise hanging.
export function bindingTransport(host, name) {
  let nextId = 1;
  const waiting = new Map();
  if (host) {
    host[name + "Reply"] = (id, text) => {
      const w = waiting.get(id);
      if (!w) return;
      waiting.delete(id);
      clearTimeout(w.timer);
      try { w.resolve(JSON.parse(String(text))); } catch (x) { w.resolve(unknown("the host's answer is not JSON")); }
    };
  }
  const send = (op, args, waitMs = 0) => new Promise((resolve) => {
    const fn = host && host[name];
    if (typeof fn !== "function") { resolve(unknown("no host carries this page's relay (the test transport '" + name + "' is not bound)")); return; }
    const id = nextId++;
    const timer = setTimeout(() => { waiting.delete(id); resolve(unknown("the host did not answer the relay operation " + op)); }, waitMs + 30000);
    waiting.set(id, { resolve, timer });
    fn(JSON.stringify({ id, op, ...args }));
  });
  return {
    put: (mailbox, key, text) => send("put", { mailbox, key, text }),
    get: (mailbox, since, max) => send("get", { mailbox, since, max }),
    watch: (mailbox, since, max, timeoutMs) => send("watch", { mailbox, since, max, timeoutMs }, timeoutMs),
    ack: (mailbox, through) => send("ack", { mailbox, through })
  };
}

// The hosted relay's transport. The paths are the hosted relay's (relays/Port.ps1's four operations
// under /v1/mailboxes/<horde>/<reader>/). Requests go with the page's own credentials and never from a
// cache: an envelope is fetched fresh, and kept by nothing but the phone's memory. A refusal's words
// are the relay's, cut to 200 characters, and only ever shown as text. A watch that has heard nothing
// when its time is up closes its socket and answers no items, as a relay's watch does. A watch the
// relay ended - its one message an { error } (replaced by a newer watch of this phone, or its account
// deleted: the hosted relay's mailbox says so), or a close with a code of its own (4000 and up) - is a
// failed watch, unknown, so the app pauses before it watches again instead of replacing the newer watch
// in its turn.
//
// EVERY FETCH HAS A TIME (REQUEST_MS). The founder's phone heard nothing new from 02:36 on 2026-10-14
// while the machine kept sending: a fetch with no timeout that never settles - iOS freezes a request in
// flight when the app goes to the background - held the live refresh (bridge.js, poll) for ever, and
// every later poll returned at once because one was still running. So the request AND the reading of its
// body race a timer: when it fires the request is aborted, so the browser lets it go, and the answer is
// unknown whether or not the fetch ever hears its abort. 20 s: the relay answers a put, a read and an
// ack at once (only a watch waits, and a watch keeps its own timer), so 20 s is room for a slow phone
// link, and under the 25 s a watch waits (app.js, WATCH_MS), so a frozen read costs the live refresh no
// more than one quiet watch would have.
export const REQUEST_MS = 20000;
const RELAY_CLOSED = { 4001: "the relay replaced this watch with a newer one of this phone", 4002: "the relay closed the watch: the account was deleted", 4003: "the relay refused the watch by one of its limits" };

// A REFUSAL KEEPS ITS CODE WORD. The hosted relay answers a refusal by a limit { error, code }: an
// account's day, its caps, a device's rate - and the RELAY'S OWN day and cap, every account's together.
// The code goes into the reason as " [<code>]" before the relay's words, so the page can tell such a
// refusal from a relay out of reach. The page then shows ITS OWN words for that code (read-banner.js,
// LIMIT_WORDS), as it does for a refused sign-in's code (app.js, SIGNIN_REFUSED): the relay's words stay
// in the diagnostics, never on the screen, so a relay can only pick one of the page's sentences, never
// write one. A phone's watch refused so arrives as the socket's one message, then a close of 4003: a
// browser is never shown the answer to a refused upgrade.
const CODE = /^[a-z][a-z-]{0,39}$/;
function refusalWords(body) {
  if (!body || typeof body.error !== "string") return "";
  return (typeof body.code === "string" && CODE.test(body.code) ? " [" + body.code + "]" : "") + ": " + body.error.slice(0, 200);
}
// The code word a reason carries (refusalWords above), or "" for none.
export function refusalCodeOf(reason) {
  const m = / \[([a-z][a-z-]{0,39})\]: /.exec(String(reason || ""));
  return m ? m[1] : "";
}

// WHICH ATTEMPT A REQUEST IS (the relay's request metrics: relays/cloudflare/worker/metrics.js, THE RETRY
// HEADER). Every request says it in x-horde-attempt: 1, plus the requests in a row before it that came
// back unknown - so the request after a failure says it is a retry, and the first after a success says
// 1 again. The relay only counts it. A browser cannot put a header on a WebSocket, so a watch carries the
// same number as attempt=<n> in its query. At most 999, the most the relay reads.
export const ATTEMPT_HEADER = "x-horde-attempt";
const ATTEMPT_MAX = 999;

export function httpTransport(origin, fetchFn, WebSocketCtor, { requestMs = REQUEST_MS } = {}) {
  const url = (mailbox, op) => origin + "/v1/mailboxes/" + mailbox + "/" + op;
  const words = refusalWords;
  let failedInARow = 0;
  const attempt = () => String(Math.min(ATTEMPT_MAX, failedInARow + 1));
  const settle = (a) => { failedInARow = a && a.state === "known" ? 0 : failedInARow + 1; return a; };
  const answerOf = async (response, what) => {
    let body = null;
    try { body = await response.json(); } catch (x) { body = null; }
    if (response.status !== 200) return unknown("the relay answered the " + what + " with " + response.status + words(body));
    if (!body || typeof body !== "object" || Array.isArray(body)) return unknown("the relay answered the " + what + " with something that is not a JSON object");
    return known(body);
  };
  const exchange = (method, address, body, what) => {
    const abort = new AbortController();
    let timer = null;
    const late = new Promise((resolve) => { timer = setTimeout(() => { abort.abort(); resolve(unknown("the relay did not answer the " + what + " in " + requestMs + " ms")); }, requestMs); });
    const asked = (async () => answerOf(await fetchFn(address, {
      method, credentials: "same-origin", cache: "no-store", redirect: "error", signal: abort.signal,
      headers: body === undefined ? { [ATTEMPT_HEADER]: attempt() } : { "Content-Type": "application/json", [ATTEMPT_HEADER]: attempt() },
      body: body === undefined ? undefined : JSON.stringify(body)
    }), what))();
    return Promise.race([asked, late]).finally(() => clearTimeout(timer)).then(settle);
  };
  const read = (mailbox, since, max, what) => exchange("GET", url(mailbox, "items") + "?since=" + since + "&max=" + max, undefined, what);
  return {
    put: (mailbox, key, text) => exchange("POST", url(mailbox, "items"), { key, text }, "put"),
    get: (mailbox, since, max) => read(mailbox, since, max, "read"),
    // A watch of 0 ms is a read: a socket shut before its first message would lose what is already there.
    watch: (mailbox, since, max, timeoutMs) => (timeoutMs <= 0 ? read(mailbox, since, max, "watch") : new Promise((resolve) => {
      let settled = false;
      let socket = null;
      const finish = (a) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        try { socket.close(); } catch (x) { /* already closed */ }
        resolve(settle(a));
      };
      const timer = setTimeout(() => finish(known({ items: [] })), timeoutMs);
      try { socket = new WebSocketCtor(url(mailbox, "watch").replace(/^http/, "ws") + "?since=" + since + "&max=" + max + "&timeoutMs=" + timeoutMs + "&attempt=" + attempt()); }
      catch (x) { finish(unknown("the relay's watch could not be opened")); return; }
      socket.onmessage = (event) => {
        let body = null;
        try { body = JSON.parse(String(event.data)); } catch (x) { body = null; }
        if (body && typeof body === "object" && !Array.isArray(body) && typeof body.error === "string") { finish(unknown("the relay ended the watch" + refusalWords(body))); return; }
        finish(body && typeof body === "object" && !Array.isArray(body) ? known(body) : unknown("the relay's watch message is not a JSON object"));
      };
      socket.onerror = () => finish(unknown("the relay's watch failed"));
      socket.onclose = (event) => finish(event && event.code >= 4000 && event.code <= 4999 ? unknown(RELAY_CLOSED[event.code] || "the relay closed the watch (" + event.code + ")") : known({ items: [] }));
    })),
    ack: (mailbox, through) => exchange("POST", url(mailbox, "ack"), { through }, "ack")
  };
}

// The transport a deployment's config names. config is app/config.json: { transport, relayOrigin }.
export function transportFromConfig(config, host) {
  const name = config && config.transport;
  if (name === "memory") return memoryTransport();
  if (name === "binding") return bindingTransport(host, "hordeRelayBinding");
  if (name === "http") {
    const origin = config.relayOrigin || (host && host.location ? host.location.origin : "");
    if (!origin || !host || typeof host.fetch !== "function" || typeof host.WebSocket !== "function") return null;
    return httpTransport(origin, host.fetch.bind(host), host.WebSocket);
  }
  return null;
}
