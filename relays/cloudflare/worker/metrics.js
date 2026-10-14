// relays/cloudflare/worker/metrics.js - THE RELAY'S REQUEST METRICS, the pure parts: what one request is
// counted as, how counts add up, how an isolate holds them until it flushes, and what a summary may say.
// No storage and no clock of its own: metrics-request.js records each answered request through the
// Recorder here, metrics-store.js keeps the flushed rows in one Durable Object, metrics-api.js answers
// the summary. The design note is Orc F's of 2026-10-14 (design-relay-request-metrics.md, approved by C).
//
// WHAT ONE REQUEST IS COUNTED AS - a key of four parts, each from a FIXED LIST, never anything the
// request carried:
//   hour     the UTC hour it was answered in, "2026-10-14T19"
//   route    ROUTES below, from the method and the shape of the path - NEVER THE PATH ITSELF (a path
//            holds mailbox names). The phone app's own files, sign-out and anything unknown are "other"
//   kind     phone, machine or anonymous: who the relay took the request to be (api.js tells it, noteWho),
//            or - when no one was vouched for - what the request claims to be by its credentials' shape
//            (a session cookie, a machine's signature header). Nothing else of the user agent is read
//   outcome  "ok" for any answer below 400 and an opened watch; otherwise the code word the relay
//            refused with (answers.js, CODES) or, for a refusal with no code, a word for its status
//            (OUTCOMES below). The words of a refusal are never read
// and each key holds COUNTERS: count, bytesIn (the request's Content-Length), bytesOut (the answer's
// body), a latency histogram (LATENCY), emptyWatch (a watch that ended with no item), retries (requests
// whose client said x-horde-attempt over 1) and watchSeconds (the seconds watches were held). A watch's
// end is seen where it ends, in its mailbox's object (mailbox.js): that adds emptyWatch and watchSeconds
// to the key of its hour, its kind and "ok", with a count of 0 - the watch's request was counted when it
// was opened.
//
// PER ACCOUNT, PER HOUR: count, bytesIn, bytesOut under the ACCOUNT HASH - the first 16 hex of
// HMAC-SHA-256(METRICS_SALT, account id). The salt is a Worker secret (relays/cloudflare/Deploy.ps1), so
// the hash cannot be reversed by trying known ids; with no salt there are no account rows at all, never
// an unsalted hash.
//
// THE RETRY HEADER. x-horde-attempt: <n>, 1 for a first try, from the phone's relay client
// (surfaces/pwa/page/relay-client.js) and the machine's (relays/cloudflare/Relay.ps1): n over 1 is a
// retry. A browser cannot put a header on a WebSocket, so the phone's watch carries the same number as
// the query's attempt=<n>, read for a watch only. Anything that is not 1 to 999 is read as no header.
//
// AN ISOLATE HOLDS ITS COUNTS IN MEMORY (Recorder) and hands them over in one batch at most every
// flushMs (5 minutes), or when it holds flushCount increments (500), whichever comes first. A batch
// whose flush fails is DROPPED: metrics may under-count, never cost a user's request.
import { DAY_MS } from "./throttle.js";

export const ROUTES = Object.freeze(["items.get", "items.put", "watch", "ack", "account.view", "account.machines", "account.phones", "pair.register", "rotation", "auth.start", "auth.callback", "auth.session", "other"]);
export const KINDS = Object.freeze(["phone", "machine", "anonymous"]);
// The refusal codes the relay answers with (answers.js, CODES; the watch-replaced message is not an
// answer), then a word for each status refused with no code.
export const OUTCOMES = Object.freeze(["ok", "rate-limited", "daily-limit", "mailbox-full", "machines-cap", "phones-cap", "mailboxes-cap", "account-full", "account-gone", "mailbox-gone", "account-deleting", "relay-daily-limit", "relay-full",
  "bad-request", "unauthenticated", "forbidden", "not-found", "bad-method", "conflict", "gone", "too-large", "not-websocket", "refused", "error"]);
const STATUS_WORDS = Object.freeze({ 400: "bad-request", 401: "unauthenticated", 403: "forbidden", 404: "not-found", 405: "bad-method", 409: "conflict", 410: "gone", 413: "too-large", 426: "not-websocket", 429: "rate-limited" });
// The latency histogram's buckets: under 50 ms, under 200 ms, under 1 s, under 5 s, more.
export const LATENCY = Object.freeze(["lt50ms", "lt200ms", "lt1s", "lt5s", "more"]);
const LATENCY_EDGES = [50, 200, 1000, 5000];
export const COUNTERS = Object.freeze(["count", "bytesIn", "bytesOut", "emptyWatch", "retries", "watchSeconds"]);
export const ACCOUNT_COUNTERS = Object.freeze(["count", "bytesIn", "bytesOut"]);
// The metrics object's own line (metrics-store.js): its own calls, counted where they happen.
export const OWN_COUNTERS = Object.freeze(["flushes", "increments", "alarms", "summaryReads", "rowsDeleted"]);

// THE SETTINGS, and the test override. A suite cannot wait five minutes for a flush, so - exactly as
// limits.js's HORDE_RELAY_TEST_LIMITS, and only where that is honoured (a request made to this machine
// itself, with the binding there) - HORDE_RELAY_TEST_METRICS may hold {"<name>": <whole number>} over
// these. failFlush 1 makes the metrics object refuse every flush, so a suite can show a failing metrics
// object costs a user nothing; it is 0, and cannot be anything else, outside a test.
export const METRICS = Object.freeze({
  flushMs: 5 * 60 * 1000,
  flushCount: 500,
  retentionDays: 30,
  // How often one machine key may read a summary from one isolate: the PC reads once a day.
  summaryEveryMs: 60 * 1000,
  failFlush: 0
});
const TEST_BINDING = "HORDE_RELAY_TEST_METRICS";
export const SALT_BINDING = "METRICS_SALT";
export const ATTEMPT_HEADER = "x-horde-attempt";
const ATTEMPT = /^[1-9][0-9]{0,2}$/;
const HOUR = /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}$/;
const DAY = /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/;
const HASH = /^[0-9a-f]{16}$/;
const LOOPBACK = new Set(["127.0.0.1", "localhost", "[::1]"]);

// The metrics settings this request is held to (the header, THE SETTINGS). Throws on a test binding it
// cannot read, as limits.js does: a suite that thinks it set one and did not would prove nothing.
export function metricsSettingsOf(env, url) {
  const t = env && env[TEST_BINDING];
  if (typeof t !== "string" || !url || !LOOPBACK.has(url.hostname)) return METRICS;
  let o;
  try { o = JSON.parse(t); } catch (e) { throw new Error(TEST_BINDING + " is not JSON"); }
  if (!o || typeof o !== "object" || Array.isArray(o)) throw new Error(TEST_BINDING + " is not a JSON object");
  const out = { ...METRICS };
  for (const name of Object.keys(o)) {
    if (!Object.prototype.hasOwnProperty.call(METRICS, name)) throw new Error(TEST_BINDING + " names no setting " + name);
    if (!Number.isSafeInteger(o[name]) || o[name] < (name === "failFlush" ? 0 : 1)) throw new Error(TEST_BINDING + "'s " + name + " is not a whole number");
    out[name] = o[name];
  }
  return Object.freeze(out);
}

const pad2 = (n) => String(n).padStart(2, "0");
// "2026-10-14T19", the UTC hour of now (ms).
export function hourOf(now) {
  const d = new Date(now);
  return d.getUTCFullYear() + "-" + pad2(d.getUTCMonth() + 1) + "-" + pad2(d.getUTCDate()) + "T" + pad2(d.getUTCHours());
}
// "2026-10-14", the UTC day of now (ms).
export function dayKeyOf(now) { return hourOf(now).slice(0, 10); }
export function isHour(s) { return typeof s === "string" && HOUR.test(s); }
export function isAccountHash(s) { return typeof s === "string" && HASH.test(s); }
// A day as the summary is asked for it: "YYYY-MM-DD" that is a real date, or null.
export function dayOrNull(s) {
  if (typeof s !== "string" || !DAY.test(s)) return null;
  const t = Date.parse(s + "T00:00:00Z");
  return Number.isFinite(t) && dayKeyOf(t) === s ? s : null;
}
// The first hour kept at now with retentionDays: every row of an hour before it is deleted.
export function cutoffHourOf(now, retentionDays) { return hourOf(now - retentionDays * DAY_MS); }

const MAILBOX = /^\/v1\/mailboxes\/[^/]{1,63}\/[^/]{1,63}\/(items|watch|ack)$/;
const ACCOUNT_MACHINE = /^\/v1\/account\/machines\/[^/]+$/;
const ACCOUNT_PHONE = /^\/v1\/account\/phones\/[^/]+$/;

// The route of a request, from ROUTES (the header). callbackPath is the site's (site.js).
export function routeOf(method, pathname, callbackPath) {
  const m = MAILBOX.exec(pathname);
  if (m) {
    if (m[1] === "items") return method === "POST" ? "items.put" : method === "GET" ? "items.get" : "other";
    return m[1] === "watch" ? (method === "GET" ? "watch" : "other") : method === "POST" ? "ack" : "other";
  }
  if (pathname === "/v1/account") return method === "GET" ? "account.view" : "other";
  if (pathname === "/v1/account/machines") return method === "POST" ? "pair.register" : "other";
  if (ACCOUNT_MACHINE.test(pathname)) return "account.machines";
  if (ACCOUNT_PHONE.test(pathname)) return "account.phones";
  if (pathname === "/v1/machines/rotation") return "rotation";
  if (pathname === "/auth/google") return "auth.start";
  if (typeof callbackPath === "string" && pathname === callbackPath) return "auth.callback";
  if (pathname === "/auth/session") return "auth.session";
  return "other";
}

// The kind a principal is (auth.js), or - with none - what the request claims by its credentials' shape.
export function kindOf(who, request) {
  if (who && who.kind === "phone") return "phone";
  if (who && who.kind === "machine") return "machine";
  if (who) return "anonymous";
  const h = request && request.headers;
  if (!h) return "anonymous";
  if (String(h.get("Authorization") || "").startsWith("Horde-Machine ")) return "machine";
  if (/(?:^|;\s*)__Host-horde-session=/.test(String(h.get("Cookie") || ""))) return "phone";
  return "anonymous";
}

// The outcome of an answer of status, refused with code (or none), from OUTCOMES.
export function outcomeOf(status, code) {
  if (status < 400) return "ok";
  if (typeof code === "string" && OUTCOMES.includes(code) && code !== "ok") return code;
  if (STATUS_WORDS[status]) return STATUS_WORDS[status];
  return status >= 500 ? "error" : "refused";
}

export function latencyBucketOf(ms) {
  for (let i = 0; i < LATENCY_EDGES.length; i++) if (ms < LATENCY_EDGES[i]) return LATENCY[i];
  return LATENCY[LATENCY.length - 1];
}

// The attempt a request says it is (the header, THE RETRY HEADER): 1 to 999, or 1 when it says none.
export function attemptOf(request, url, route) {
  const h = request && request.headers ? request.headers.get(ATTEMPT_HEADER) : null;
  if (typeof h === "string" && ATTEMPT.test(h)) return Number(h);
  if (route === "watch" && url) {
    const q = url.searchParams.get("attempt");
    if (typeof q === "string" && ATTEMPT.test(q)) return Number(q);
  }
  return 1;
}

// A whole number of bytes from a Content-Length, or 0.
export function lengthOf(text) {
  if (typeof text !== "string" || !/^[0-9]{1,15}$/.test(text)) return 0;
  return Number(text);
}

export function emptyCounters() {
  const c = { count: 0, bytesIn: 0, bytesOut: 0, emptyWatch: 0, retries: 0, watchSeconds: 0, latency: {} };
  for (const b of LATENCY) c.latency[b] = 0;
  return c;
}
export function emptyAccountCounters() { return { count: 0, bytesIn: 0, bytesOut: 0 }; }
export function emptyOwnCounters() { const o = {}; for (const n of OWN_COUNTERS) o[n] = 0; return o; }

const whole = (n) => (Number.isSafeInteger(n) && n >= 0 ? n : 0);
// into + add, counter by counter: only the named counters, each a whole number from 0 (anything else
// counts as 0), so a row can never carry anything but numbers.
export function addCounters(into, add) {
  const out = emptyCounters();
  for (const n of COUNTERS) out[n] = whole(into && into[n]) + whole(add && add[n]);
  for (const b of LATENCY) out.latency[b] = whole(into && into.latency && into.latency[b]) + whole(add && add.latency && add.latency[b]);
  return out;
}
export function addAccountCounters(into, add) {
  const out = emptyAccountCounters();
  for (const n of ACCOUNT_COUNTERS) out[n] = whole(into && into[n]) + whole(add && add[n]);
  return out;
}
export function addOwnCounters(into, add) {
  const out = emptyOwnCounters();
  for (const n of OWN_COUNTERS) out[n] = whole(into && into[n]) + whole(add && add[n]);
  return out;
}

// The key of a request's row: "<hour>|<route>|<kind>|<outcome>", every part checked against its list.
export function rowKeyOf(hour, route, kind, outcome) {
  if (!isHour(hour) || !ROUTES.includes(route) || !KINDS.includes(kind) || !OUTCOMES.includes(outcome)) return null;
  return hour + "|" + route + "|" + kind + "|" + outcome;
}
// A row key's parts { hour, route, kind, outcome }, or null when any is not from its list.
export function rowPartsOf(key) {
  const p = typeof key === "string" ? key.split("|") : [];
  if (p.length !== 4 || rowKeyOf(p[0], p[1], p[2], p[3]) !== key) return null;
  return { hour: p[0], route: p[1], kind: p[2], outcome: p[3] };
}
export function accountKeyOf(hour, hash) { return isHour(hour) && isAccountHash(hash) ? hour + "|" + hash : null; }
export function accountPartsOf(key) {
  const p = typeof key === "string" ? key.split("|") : [];
  if (p.length !== 2 || accountKeyOf(p[0], p[1]) !== key) return null;
  return { hour: p[0], account: p[1] };
}

// HMAC-SHA-256(salt, account) as hex, its first 16: the account hash (the header). null with no salt.
const saltKeys = new Map();
export async function accountHashOf(salt, account) {
  if (typeof salt !== "string" || salt.length === 0 || typeof account !== "string" || account.length === 0) return null;
  let key = saltKeys.get(salt);
  if (!key) {
    key = await crypto.subtle.importKey("raw", new TextEncoder().encode(salt), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
    saltKeys.clear();
    saltKeys.set(salt, key);
  }
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(account)));
  let hex = "";
  for (let i = 0; i < 8; i++) hex += mac[i].toString(16).padStart(2, "0");
  return hex;
}

// AN ISOLATE'S COUNTS (the header). record() adds one entry and answers the batch to flush now, or null;
// the caller hands that batch to the metrics object and forgets it, whatever the answer.
//   entry  { now, route, kind, outcome, bytesIn, bytesOut, latencyMs, retry, account (a hash or null),
//            emptyWatch, watchSeconds, counted (false for a watch's end: it adds no count) }
// A batch is { rows: [[key, counters]], accounts: [[key, counters]], increments }.
export class Recorder {
  constructor() { this.reset(null); }
  reset(now) { this.rows = new Map(); this.accounts = new Map(); this.increments = 0; this.since = now; }
  record(entry, settings) {
    const now = entry.now;
    if (this.since === null) this.since = now;
    const hour = hourOf(now);
    const key = rowKeyOf(hour, entry.route, entry.kind, entry.outcome);
    if (key === null) return null;
    const add = emptyCounters();
    if (entry.counted !== false) {
      add.count = 1;
      add.bytesIn = whole(entry.bytesIn);
      add.bytesOut = whole(entry.bytesOut);
      add.latency[latencyBucketOf(Number.isFinite(entry.latencyMs) ? entry.latencyMs : 0)] = 1;
      add.retries = entry.retry ? 1 : 0;
    }
    add.emptyWatch = entry.emptyWatch ? 1 : 0;
    add.watchSeconds = whole(entry.watchSeconds);
    this.rows.set(key, addCounters(this.rows.get(key), add));
    if (entry.counted !== false && isAccountHash(entry.account)) {
      const ak = accountKeyOf(hour, entry.account);
      this.accounts.set(ak, addAccountCounters(this.accounts.get(ak), { count: 1, bytesIn: add.bytesIn, bytesOut: add.bytesOut }));
    }
    this.increments++;
    if (this.increments < settings.flushCount && now - this.since < settings.flushMs) return null;
    const batch = { rows: [...this.rows.entries()], accounts: [...this.accounts.entries()], increments: this.increments };
    this.reset(now);
    return batch;
  }
}

// A batch as the metrics object takes it, every key and counter checked again (it is the object's own
// storage): { rows, accounts, increments }, or null when it is not one.
export const BATCH_MAX = 5000;
export function batchOrNull(b) {
  if (!b || typeof b !== "object" || !Array.isArray(b.rows) || !Array.isArray(b.accounts)) return null;
  if (b.rows.length + b.accounts.length > BATCH_MAX) return null;
  const rows = [];
  for (const r of b.rows) { if (!Array.isArray(r) || r.length !== 2 || rowPartsOf(r[0]) === null) return null; rows.push([r[0], addCounters(null, r[1])]); }
  const accounts = [];
  for (const a of b.accounts) { if (!Array.isArray(a) || a.length !== 2 || accountPartsOf(a[0]) === null) return null; accounts.push([a[0], addAccountCounters(null, a[1])]); }
  return { rows, accounts, increments: whole(b.increments) };
}
