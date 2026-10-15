// The relay's request metrics, the parts that run without a Worker, one behaviour at a time, under Node,
// for relays/cloudflare/test/test-cloudflare-metrics.ps1 (part 1): what one request is counted as, an
// isolate's counts and when they are flushed, the metrics object's rows over a storage in memory - its
// own line, its summary, its 30-day retention - and the request wrapper with a metrics object that
// throws, refuses or never answers. No network, no Worker.
//
//   node metrics-units.mjs <repository root>
//
// Prints one line per check, "[PASS] name" or "[FAIL] name: detail", then "[DONE] <failures>".
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [, , repoRoot] = process.argv;
const load = (p) => import(pathToFileURL(join(repoRoot, p)).href);
const M = await load("relays/cloudflare/worker/metrics.js");
const B = await load("relays/cloudflare/worker/metrics-book.js");
const Q = await load("relays/cloudflare/worker/metrics-request.js");

let failures = 0;
function check(ok, name, detail = "") {
  if (ok) process.stdout.write("[PASS] " + name + "\n");
  else { failures++; process.stdout.write("[FAIL] " + name + (detail ? ": " + String(detail).replace(/[^\x20-\x7e]/g, "?").slice(0, 300) : "") + "\n"); }
}
const throws = (f) => { try { f(); return false; } catch (e) { return true; } };
const HOUR_MS = 3600000;
const DAY_MS = 86400000;
const T0 = Date.parse("2026-10-14T19:20:00Z");

// A storage in memory with the Durable Object storage API's shape, as metrics-book.js uses it. Every key
// written is remembered, so a check can say what the object touched.
function memoryStorage() {
  const m = new Map();
  let alarm = null;
  const written = new Set();
  return {
    map: m, written,
    async get(k) { if (Array.isArray(k)) { const out = new Map(); for (const x of k) if (m.has(x)) out.set(x, structuredClone(m.get(x))); return out; } return m.has(k) ? structuredClone(m.get(k)) : undefined; },
    async put(k, v) { if (typeof k === "string") { m.set(k, structuredClone(v)); written.add(k); return; } for (const [x, y] of Object.entries(k)) { m.set(x, structuredClone(y)); written.add(x); } },
    async list({ start = "", end = null, limit = Infinity } = {}) { const out = new Map(); for (const k of [...m.keys()].sort()) { if (out.size >= limit) break; if (k < start) continue; if (end !== null && k >= end) continue; out.set(k, structuredClone(m.get(k))); } return out; },
    async delete(keys) { let n = 0; for (const k of keys) if (m.delete(k)) n++; return n; },
    async getAlarm() { return alarm; },
    async setAlarm(t) { alarm = t; },
    alarmAt() { return alarm; }
  };
}

// --- 1. what a request is counted as: fixed lists, never the path ---
{
  check(M.routeOf("POST", "/v1/mailboxes/work/phone/items", "/auth/google/callback") === "items.put" && M.routeOf("GET", "/v1/mailboxes/work/phone/items", "") === "items.get" && M.routeOf("GET", "/v1/mailboxes/work/phone/watch", "") === "watch" && M.routeOf("POST", "/v1/mailboxes/work/phone/ack", "") === "ack", "the mailbox operations are their routes");
  check(M.routeOf("GET", "/v1/account", "") === "account.view" && M.routeOf("POST", "/v1/account/machines", "") === "pair.register" && M.routeOf("DELETE", "/v1/account/machines/" + "a".repeat(32), "") === "account.machines" && M.routeOf("DELETE", "/v1/account/phones/" + "b".repeat(64), "") === "account.phones" && M.routeOf("POST", "/v1/machines/rotation", "") === "rotation", "the account's and the machine's operations are theirs");
  check(M.routeOf("GET", "/auth/google", "/auth/google/callback") === "auth.start" && M.routeOf("GET", "/auth/google/callback", "/auth/google/callback") === "auth.callback" && M.routeOf("GET", "/auth/session", "") === "auth.session", "sign-in's three are theirs");
  check(M.routeOf("GET", "/app/index.html", "") === "other" && M.routeOf("GET", "/v1/mailboxes/secret-marker/x/items/more", "") === "other" && M.routeOf("PUT", "/v1/mailboxes/work/phone/items", "") === "other", "anything else is other: an app file, a path of no route, a method of none");
  const all = ["GET", "POST", "DELETE", "PUT"].flatMap((m) => ["/v1/mailboxes/marker-x/marker-y/items", "/v1/mailboxes/marker-x/marker-y/watch", "/v1/account/machines/marker", "/marker"].map((p) => M.routeOf(m, p, "")));
  check(all.every((r) => M.ROUTES.includes(r)) && !all.some((r) => r.indexOf("marker") >= 0), "whatever the path holds, the route is from the fixed list and holds nothing of it", all.join(","));
  const hdr = (h) => ({ headers: new Headers(h) });
  check(M.kindOf({ kind: "phone" }) === "phone" && M.kindOf({ kind: "machine" }) === "machine" && M.kindOf({ kind: "test" }) === "anonymous", "a principal's kind is the kind it was vouched as; the test principal is anonymous");
  check(M.kindOf(null, hdr({ Authorization: "Horde-Machine key=x" })) === "machine" && M.kindOf(null, hdr({ Cookie: "a=b; __Host-horde-session=zz" })) === "phone" && M.kindOf(null, hdr({ "User-Agent": "phone machine" })) === "anonymous", "with none, the shape of its credentials; nothing of the user agent");
  check(M.outcomeOf(200, "") === "ok" && M.outcomeOf(101, "") === "ok" && M.outcomeOf(303, "") === "ok" && M.outcomeOf(429, "relay-daily-limit") === "relay-daily-limit" && M.outcomeOf(507, "mailbox-full") === "mailbox-full", "an answer below 400 is ok, and a refusal with a code is its code");
  check(M.outcomeOf(101, "rate-limited", true) === "rate-limited" && M.outcomeOf(101, "relay-daily-limit", true) === "relay-daily-limit" && M.outcomeOf(101, "", true) === "refused", "A WATCH REFUSED AS A SOCKET (101, its refusal noted) is counted under its code, never ok");
  check(M.outcomeOf(101, "", false) === "ok" && M.outcomeOf(101, "rate-limited", false) === "ok", "TWIN: an opened watch with nothing noted is ok");
  check(M.outcomeOf(401, "") === "unauthenticated" && M.outcomeOf(404, "") === "not-found" && M.outcomeOf(429, "") === "rate-limited" && M.outcomeOf(418, "") === "refused" && M.outcomeOf(500, "") === "error" && M.outcomeOf(400, "marker-code") === "bad-request", "a refusal with no code, or a code not on the list, is a word for its status", M.outcomeOf(400, "marker-code"));
  check(M.latencyBucketOf(0) === "lt50ms" && M.latencyBucketOf(49) === "lt50ms" && M.latencyBucketOf(50) === "lt200ms" && M.latencyBucketOf(999) === "lt1s" && M.latencyBucketOf(4999) === "lt5s" && M.latencyBucketOf(5000) === "more", "the latency buckets at their edges");
  const req = (h) => ({ headers: new Headers(h) });
  const u = new URL("http://x/v1/mailboxes/w/p/watch?attempt=4");
  check(M.attemptOf(req({ "x-horde-attempt": "3" }), u, "items.get") === 3 && M.attemptOf(req({}), u, "watch") === 4 && M.attemptOf(req({}), u, "items.get") === 1 && M.attemptOf(req({ "x-horde-attempt": "0" }), null, "ack") === 1 && M.attemptOf(req({ "x-horde-attempt": "1000" }), null, "ack") === 1 && M.attemptOf(req({ "x-horde-attempt": "2x" }), null, "ack") === 1, "the attempt is the header's 1 to 999, the query's only for a watch, and 1 for anything else");
  check(M.rowKeyOf("2026-10-14T19", "watch", "phone", "ok") === "2026-10-14T19|watch|phone|ok" && M.rowKeyOf("2026-10-14T19", "watch|x", "phone", "ok") === null && M.rowKeyOf("marker", "watch", "phone", "ok") === null && M.rowKeyOf("2026-10-14T19", "watch", "marker", "ok") === null && M.rowKeyOf("2026-10-14T19", "watch", "phone", "marker") === null, "a row's key is built only from an hour and the three fixed lists");
  check(M.rowPartsOf("2026-10-14T19|watch|phone|ok").route === "watch" && M.rowPartsOf("2026-10-14T19|watch|phone|ok|marker") === null && M.accountPartsOf("2026-10-14T19|0123456789abcdef").account === "0123456789abcdef" && M.accountPartsOf("2026-10-14T19|marker") === null, "and read back only so");
  check(M.hourOf(T0) === "2026-10-14T19" && M.dayKeyOf(T0) === "2026-10-14" && M.dayOrNull("2026-10-14") === "2026-10-14" && M.dayOrNull("2026-02-30") === null && M.dayOrNull("2026-10-14x") === null && M.cutoffHourOf(T0, 30) === "2026-09-14T19", "hours, days and the retention's cutoff are UTC");
}

// --- 2. the account hash ---
{
  const a = await M.accountHashOf("salt-one-" + "x".repeat(30), "google:123");
  const b = await M.accountHashOf("salt-two-" + "x".repeat(30), "google:123");
  const c = await M.accountHashOf("salt-one-" + "x".repeat(30), "google:124");
  const again = await M.accountHashOf("salt-one-" + "x".repeat(30), "google:123");
  check(/^[0-9a-f]{16}$/.test(a) && a === again && a !== b && a !== c, "an account's hash is 16 hex, the same for the same salt and id, and another for another salt or id", [a, b, c].join(","));
  check((await M.accountHashOf("", "google:123")) === null && (await M.accountHashOf(undefined, "google:123")) === null, "with no salt there is no hash at all, never an unsalted one");
}

// --- 3. an isolate's counts and when they go (the Recorder) ---
const SET = { ...M.METRICS };
function entry(over = {}) { return { now: T0, route: "items.put", kind: "phone", outcome: "ok", bytesIn: 10, bytesOut: 20, latencyMs: 30, retry: false, account: "0123456789abcdef", ...over }; }
{
  const r = new M.Recorder();
  let flushed = null;
  for (let i = 0; i < 499; i++) flushed = r.record(entry(), SET) || flushed;
  check(flushed === null, "499 increments within five minutes are held");
  const b = r.record(entry(), SET);
  check(b !== null && b.increments === 500 && b.rows.length === 1 && b.rows[0][1].count === 500 && b.rows[0][1].bytesIn === 5000 && b.rows[0][1].latency.lt50ms === 500 && b.accounts[0][1].count === 500, "the 500th hands over one batch of all of them, counted exactly", JSON.stringify(b && b.rows[0]));
  check(r.record(entry({ now: T0 + 299999 }), SET) === null && r.record(entry({ now: T0 + 300000 }), SET) !== null, "after a flush, the next goes when five minutes have passed since it, whichever comes first");
  const s = new M.Recorder();
  s.record(entry({ route: "items.get", retry: true, latencyMs: 300 }), SET);
  s.record(entry({ route: "watch", counted: false, emptyWatch: true, watchSeconds: 59, account: null }), SET);
  const fb = s.record(entry({ route: "items.get", kind: "machine", outcome: "rate-limited", account: null }), { ...SET, flushCount: 3 });
  const rows = new Map(fb.rows);
  const g = rows.get("2026-10-14T19|items.get|phone|ok");
  const w = rows.get("2026-10-14T19|watch|phone|ok");
  check(g.count === 1 && g.retries === 1 && g.latency.lt1s === 1 && w.count === 0 && w.emptyWatch === 1 && w.watchSeconds === 59 && rows.get("2026-10-14T19|items.get|machine|rate-limited").count === 1 && fb.accounts.length === 1 && fb.accounts[0][1].count === 1, "a retry, a watch's end (no count of its own) and a refusal each land on their own key", JSON.stringify(fb));
  const ended = new M.Recorder().record(entry({ route: "watch", counted: false, emptyWatch: false, outcome: "watch-replaced", account: null }), { ...SET, flushCount: 1 });
  check(ended.rows.length === 1 && ended.rows[0][0] === "2026-10-14T19|watch|phone|watch-replaced" && ended.rows[0][1].count === 0 && ended.rows[0][1].emptyWatch === 0, "a watch the relay replaced is counted under watch-replaced, not as an empty watch", JSON.stringify(ended.rows));
  check(new M.Recorder().record(entry({ route: "marker-route" }), SET) === null && new M.Recorder().record(entry({ outcome: "marker" }), SET) === null, "an entry whose parts are not on the lists is not counted at all");
}

// --- 4. the metrics object's book: rows, its own line, the summary ---
{
  const st = memoryStorage();
  const book = new B.MetricsBook(st);
  const rec = new M.Recorder();
  for (let i = 0; i < 3; i++) rec.record(entry(), SET);
  const batch = rec.record(entry({ route: "ack", outcome: "conflict" }), { ...SET, flushCount: 4 });
  check((await book.add(batch, { now: T0 })) === true && (await book.add(batch, { now: T0 + 1000 })) === true, "the object takes a batch, and another");
  const s = await book.summary("2026-10-14", { now: T0 + 2000 });
  const put = s.requests.find((x) => x.route === "items.put");
  const own = s.own.find((x) => x.hour === "2026-10-14T19");
  check(put.count === 6 && put.bytesOut === 120 && s.requests.find((x) => x.route === "ack").count === 2 && s.accounts[0].count === 8, "two flushes add up exactly in its rows", JSON.stringify(s.requests));
  check(own && own.flushes === 2 && own.increments === 8 && own.summaryReads === 1 && own.alarms === 0, "ITS OWN CALLS ARE A LINE OF THEIR OWN: two flushes carrying eight increments, and this summary read", JSON.stringify(own));
  const twin = { ...own, flushes: own.flushes - 1 };
  check(!(twin.flushes === 2 && twin.increments === 8), "MUST-FAIL TWIN: one flush fewer is not what the line says");
  check(st.alarmAt() === T0 + DAY_MS, "the first flush sets the daily alarm, a day on");
  check([...st.written].every((k) => /^(r|a|o):/.test(k)), "and it writes nothing but its own rows: no account, no budget, nothing else", [...st.written].join(","));
  const mine = await book.summary("2026-10-14", { now: T0 + 3000, account: "0123456789abcdef" });
  const other = await book.summary("2026-10-14", { now: T0 + 3000, account: "fedcba9876543210" });
  check(mine.accounts.length === 1 && mine.requests === undefined && mine.own === undefined && other.accounts.length === 0, "one account's summary is its own hours and nothing else");
  check((await book.add({ rows: [["2026-10-14T19|items.put|phone|ok|marker", {}]], accounts: [] }, { now: T0 })) === false && (await book.add({ rows: [], accounts: [["2026-10-14T19|marker-not-hex", {}]] }, { now: T0 })) === false && (await book.add({ rows: [["2026-10-14T19|watch|phone|ok", { count: "marker", latency: { marker: 5 }, marker: "x" }]], accounts: [] }, { now: T0 })) === true, "a batch with a key off the lists is refused whole; a counter that is not a whole number counts 0 and an unknown name is dropped");
  const after = await book.summary("2026-10-14", { now: T0 + 4000 });
  check(JSON.stringify(after).indexOf("marker") < 0, "so nothing of what a batch carried beyond the lists reaches a summary", JSON.stringify(after).slice(0, 200));
  let failed = false;
  try { await book.add(batch, { now: T0, failFlush: 1 }); } catch (e) { failed = true; }
  check(failed && (await book.summary("2026-10-14", { now: T0 + 5000 })).requests.find((x) => x.route === "items.put").count === 6, "with failFlush a test's object refuses the flush and keeps nothing of it");
}

// --- 5. retention: the daily alarm deletes every row older than 30 days ---
{
  const st = memoryStorage();
  const book = new B.MetricsBook(st);
  const mk = (when) => { const r = new M.Recorder(); return r.record(entry({ now: when }), { ...SET, flushCount: 1 }); };
  const old = T0 - 31 * DAY_MS;
  const edge = T0 - 30 * DAY_MS;
  const young = T0 - 29 * DAY_MS;
  for (const t of [old, edge, young, T0]) await book.add(mk(t), { now: t });
  const before = [...st.map.keys()].filter((k) => k.startsWith("r:")).length;
  const n = await book.alarm({ now: T0 });
  const left = [...st.map.keys()];
  const rowsLeft = left.filter((k) => k.startsWith("r:")).map((k) => k.slice(2, 15)).sort();
  check(before === 4 && rowsLeft.join(",") === [M.hourOf(edge), M.hourOf(young), M.hourOf(T0)].join(","), "the alarm deletes the rows of an hour older than 30 days and keeps the 30th day and younger", rowsLeft.join(","));
  check(!left.some((k) => k.indexOf(M.hourOf(old)) >= 0), "the old hour's account row and own line go with it", left.join(","));
  const own = (await book.summary(M.dayKeyOf(T0), { now: T0 })).own.find((x) => x.hour === M.hourOf(T0));
  check(n === 3 && own.alarms === 1 && own.rowsDeleted === 3, "and counts itself on its own line: one alarm, three rows deleted (row, account, own line)", JSON.stringify(own) + " n=" + n);
  check(st.alarmAt() === T0 + DAY_MS, "and sets the next alarm a day on");
  // A BACKLOG IS DELETED A CAPPED RUN AT A TIME (review of PR 300).
  const big = memoryStorage();
  const bb = new B.MetricsBook(big);
  for (let h = 0; h < 5; h++) { const r = new M.Recorder(); await bb.add(r.record(entry({ now: old - h * HOUR_MS, account: null }), { ...SET, flushCount: 1 }), { now: old - h * HOUR_MS }); }
  // Five old hours: five request rows and five own lines, ten old rows in all; a cap of six a run.
  const oldKeys = () => [...big.map.keys()].filter((k) => k.slice(2, 15) < M.cutoffHourOf(T0, 30)).length;
  const n1 = await bb.alarm({ now: T0, maxDelete: 6 });
  const left1 = oldKeys();
  const soon = big.alarmAt();
  const n2 = await bb.alarm({ now: T0 + 60000, maxDelete: 6 });
  check(n1 === 6 && left1 === 4 && soon === T0 + 60000, "a run deletes at most its cap, and sets the next run a minute on to go on (" + n1 + " deleted, " + left1 + " old rows left)");
  check(n2 === 4 && oldKeys() === 0 && big.alarmAt() === T0 + 60000 + DAY_MS, "and the next run finishes the backlog and goes back to a day on (" + n2 + " deleted)");
  const twin = memoryStorage();
  const tb = new B.MetricsBook(twin);
  await tb.add(mk(young), { now: young });
  check((await tb.alarm({ now: T0 })) === 0 && [...twin.map.keys()].some((k) => k.startsWith("r:")), "CONTROL: a row 29 days old is not deleted");
}

// --- 6. the test override, only where a test is ---
{
  const env = { HORDE_RELAY_TEST_METRICS: '{"flushCount":1,"failFlush":1}' };
  check(M.metricsSettingsOf(env, new URL("http://127.0.0.1:1/x")).flushCount === 1 && M.metricsSettingsOf(env, new URL("https://relay.example.test/x")) === M.METRICS && M.metricsSettingsOf({}, new URL("http://127.0.0.1:1/x")) === M.METRICS, "the test override is honoured only for a request to this machine, with the binding there");
  check(throws(() => M.metricsSettingsOf({ HORDE_RELAY_TEST_METRICS: '{"marker":1}' }, new URL("http://127.0.0.1/"))) && throws(() => M.metricsSettingsOf({ HORDE_RELAY_TEST_METRICS: '{"flushCount":0}' }, new URL("http://127.0.0.1/"))), "and one it cannot read fails, as the limits' does");
  check(M.METRICS.flushMs === 300000 && M.METRICS.flushCount === 500 && M.METRICS.retentionDays === 30 && M.METRICS.failFlush === 0 && Object.isFrozen(M.METRICS), "the approved numbers: five minutes, 500 increments, 30 days; and no failing outside a test");
}

// --- 7. A FAILING METRICS OBJECT NEVER FAILS OR SLOWS A USER'S REQUEST ---
{
  const url = new URL("http://127.0.0.1:9/v1/mailboxes/work/phone/items");
  const forbidden = () => { throw new Error("a metrics call touched " + "a budget"); };
  const run = async (metricsObject, label) => {
    const env = {
      HORDE_RELAY_TEST_METRICS: '{"flushCount":1}', METRICS_SALT: "s".repeat(40),
      METRICS: { idFromName: () => "id", get: () => metricsObject },
      get ACCOUNT() { return forbidden(); }, get RELAY_BUDGET() { return forbidden(); }
    };
    const later = [];
    const ctx = { waitUntil: (p) => later.push(p) };
    const request = new Request(url.href, { method: "POST", body: '{"key":"k","text":"marker"}', headers: { "Content-Type": "application/json", "x-horde-attempt": "2" } });
    const started = Date.now();
    const res = await Q.withMetrics(request, env, ctx, url, async () => new Response('{"seq":1,"duplicate":false}', { status: 200, headers: { "Content-Type": "application/json" } }));
    const answered = Date.now() - started;
    const body = await res.text();
    const settled = await Promise.race([Promise.allSettled(later).then((r) => r.every((x) => x.status === "fulfilled")), new Promise((r) => setTimeout(() => r("pending"), 300))]);
    return { status: res.status, body, answered, settled, later: later.length };
  };
  const ok = await run({ add: async () => true }, "ok");
  check(ok.status === 200 && ok.body === '{"seq":1,"duplicate":false}' && ok.later === 1 && ok.settled === true, "CONTROL: with a working metrics object the answer is the handler's, byte for byte, and the counting runs after it", JSON.stringify(ok));
  const thrown = await run({ add: async () => { throw new Error("broken"); } }, "throws");
  check(thrown.status === 200 && thrown.body === ok.body && thrown.answered < 200 && thrown.settled === true, "a metrics object that THROWS: the same answer, at once, and the counting ends quietly - the batch dropped", JSON.stringify(thrown));
  const refused = await run({ add: async () => false }, "refuses");
  check(refused.status === 200 && refused.body === ok.body && refused.settled === true, "one that REFUSES the batch: the same", JSON.stringify(refused));
  const hung = await run({ add: () => new Promise(() => {}) }, "hangs");
  check(hung.status === 200 && hung.body === ok.body && hung.answered < 200, "one that NEVER ANSWERS: the answer still goes at once; only the counting, after it, waits", JSON.stringify(hung));
  const gone = await run(undefined, "absent");
  check(gone.status === 200 && gone.settled === true, "and a relay with no metrics object at all answers as ever");
  const broken = await Q.withMetrics(new Request(url.href), { HORDE_RELAY_TEST_METRICS: "not json" }, { waitUntil: () => {} }, url, async () => new Response("x", { status: 200 }));
  check(broken.status === 200 && (await broken.text()) === "x", "a test binding that does not read costs the request nothing either");
  check((await Q.flush({ METRICS: { idFromName: () => "id", get: () => ({ add: async () => { throw new Error("no"); } }) } }, { rows: [], accounts: [], increments: 0 }, SET)) === false, "a flush that fails is answered false, never thrown");
}

process.stdout.write("[DONE] " + failures + "\n");
process.exit(failures === 0 ? 0 : 1);
