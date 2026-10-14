// relays/cloudflare/worker/metrics-request.js - RECORDING EACH ANSWERED REQUEST (metrics.js says what is
// counted and why). index.js hands every request through withMetrics; api.js tells it who the request
// was (noteWho) and, for a phone's watch refused as a socket, its refusal (noteOutcome); mailbox.js
// tells it when a watch ends (recordWatchEnd).
//
// NOTHING HERE MAY COST A USER'S REQUEST, so:
//   - the answer is returned FIRST, untouched: the counting - the account's hash, the answer's size,
//     the increment and any flush - runs after it, in ctx.waitUntil;
//   - every step of it is inside one catch that drops what failed: a bad test binding, a hash that
//     would not compute, a metrics object that throws, refuses or never answers. A failed flush is
//     dropped, never tried again (the design note: under-count, never cost);
//   - the metrics object is called by nothing else on the request's path, and it touches no account
//     and no relay-wide budget (metrics-store.js): it can never refuse anyone.
//   - THE SUMMARY ITSELF IS NOT COUNTED HERE: it is the metrics object's own call, counted on its own
//     line (metrics-store.js, summaryReads), so reading the counts never changes them.
import { Recorder, metricsSettingsOf, routeOf, kindOf, outcomeOf, attemptOf, lengthOf, accountHashOf, SALT_BINDING } from "./metrics.js";

// The summary's path (metrics-api.js imports it from here, which imports nothing of the API).
export const METRICS_SUMMARY_PATH = "/v1/metrics/summary";
// This isolate's counts (metrics.js, Recorder): one for every request this isolate answers.
export const recorder = new Recorder();
// What api.js learnt of a request: { who, code }. Weak, so nothing outlives the request.
const notes = new WeakMap();

export function noteWho(request, who) {
  const n = notes.get(request) || {};
  n.who = who;
  notes.set(request, n);
}
export function noteOutcome(request, code) {
  const n = notes.get(request) || {};
  n.code = code;
  notes.set(request, n);
}

export function metricsObjectOf(env) {
  if (!env || !env.METRICS) return null;
  return env.METRICS.get(env.METRICS.idFromName("relay/metrics"));
}

// Hand a batch to the metrics object; a failure of any kind is dropped here (the header).
export async function flush(env, batch, settings) {
  const m = metricsObjectOf(env);
  if (!m || !batch) return false;
  try { return (await m.add(batch, { failFlush: settings.failFlush })) === true; } catch (e) { return false; }
}

// What a copy of an answer's body says, read after the answer has gone: its size in bytes and, for a
// refusal, its code word ({ error, code }: answers.js) - or "" when it has none or is not JSON. A copy
// is taken only when it is needed (withMetrics): the body has no Content-Length, or the answer refuses.
async function readCopy(copy, wantCode) {
  if (!copy) return { bytes: 0, code: "" };
  const buf = new Uint8Array(await new Response(copy).arrayBuffer());
  if (!wantCode) return { bytes: buf.byteLength, code: "" };
  let code = "";
  try {
    const body = JSON.parse(new TextDecoder().decode(buf));
    code = body && typeof body.code === "string" ? body.code : "";
  } catch (e) { code = ""; }
  return { bytes: buf.byteLength, code };
}

// One answered request, counted (the header): runs after the answer, never throws.
async function count(request, env, url, response, started, ended, copy, settings) {
  const route = routeOf(request.method, url.pathname, env && env.HORDE_RELAY_GOOGLE_CALLBACK);
  const note = notes.get(request) || {};
  const status = response.status;
  const told = response.headers.get("Content-Length");
  const read = await readCopy(copy, status >= 400 && !note.code);
  const code = note.code || read.code;
  const who = note.who || null;
  const account = who && who.kind !== "test" && typeof who.account === "string" ? await accountHashOf(env && env[SALT_BINDING], who.account) : null;
  const entry = {
    now: ended, route, kind: kindOf(who, request), outcome: outcomeOf(status, code),
    bytesIn: lengthOf(request.headers.get("Content-Length")), bytesOut: status === 101 ? 0 : told !== null ? lengthOf(told) : read.bytes,
    latencyMs: ended - started, retry: attemptOf(request, url, route) > 1, account
  };
  const batch = recorder.record(entry, settings);
  if (batch) await flush(env, batch, settings);
}

// Answer request with handle(), and count it after (the header). handle answers the Response to send.
export async function withMetrics(request, env, ctx, url, handle) {
  const started = Date.now();
  const response = await handle();
  const ended = Date.now();
  if (url.pathname === METRICS_SUMMARY_PATH || !ctx || typeof ctx.waitUntil !== "function") return response;
  let settings;
  try { settings = metricsSettingsOf(env, url); } catch (e) { return response; }
  // ONE COPY of the body is taken, before the answer goes, when the counting needs to read it: a body
  // with no Content-Length (to measure it) or a refusal (to read its code). None for an opened WebSocket.
  let out = response;
  let copy = null;
  try {
    if (response.status !== 101 && response.body && (response.headers.get("Content-Length") === null || response.status >= 400)) {
      const [a, b] = response.body.tee();
      out = new Response(a, { status: response.status, statusText: response.statusText, headers: response.headers });
      copy = b;
    }
    ctx.waitUntil(count(request, env, url, response, started, ended, copy, settings).catch(() => {}));
  } catch (e) { /* the answer goes as it is; this request is not counted */ }
  return out;
}

// A watch's end, seen in its mailbox's object (mailbox.js): its emptiness and how long it was held, on
// the key of its hour, its kind and "ok", with no count (the request was counted when it was opened).
// device is the watch's device tag ("phone:...", "machine:...", or "" for the test principal). local is
// what the Worker said of the watch's request: made to this machine itself, where the test override of
// the settings is honoured (metrics.js, THE SETTINGS) - the object cannot see the request's host.
export function recordWatchEnd(env, ctx, { device, empty, heldMs, now, local }) {
  try {
    const kind = typeof device === "string" && device.startsWith("phone:") ? "phone" : typeof device === "string" && device.startsWith("machine:") ? "machine" : "anonymous";
    const settings = metricsSettingsOf(env, local ? new URL("http://127.0.0.1/") : null);
    const batch = recorder.record({ now, route: "watch", kind, outcome: "ok", counted: false, emptyWatch: empty, watchSeconds: Math.max(0, Math.round(heldMs / 1000)) }, settings);
    if (batch) {
      const p = flush(env, batch, settings).catch(() => {});
      if (ctx && typeof ctx.waitUntil === "function") ctx.waitUntil(p);
    }
  } catch (e) { /* metrics never cost the mailbox anything */ }
}
