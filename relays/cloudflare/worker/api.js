// relays/cloudflare/worker/api.js - the mailbox API: the four operations of the relay port
// (relays/Port.ps1) over HTTP, each checked here and carried out by the mailbox's Durable Object.
//
//   GET  /v1/mailboxes/<horde>/<reader>/items?since=<n>&max=<n>                  -> 200 { items }
//   POST /v1/mailboxes/<horde>/<reader>/items   { "key": "...", "text": "..." }   -> 200 { seq, duplicate }
//   GET  /v1/mailboxes/<horde>/<reader>/watch?since=<n>&max=<n>&timeoutMs=<n>
//        a WebSocket upgrade: one message { items } when there is anything after since, then closed
//   POST /v1/mailboxes/<horde>/<reader>/ack     { "through": <n> }                -> 200 { through }
// A refusal is { error } with its status: 401 nobody vouched (auth.js), 403 not allowed this, 404 no such
// operation, 405 the wrong method, 400 a malformed request, 413 a body or text over the cap, 409 an ack
// past the head, 426 a watch that is not a WebSocket upgrade.
//
// THE ORDER IS THE POINT. Authentication comes first, before the route is even matched, so a caller
// nobody vouched for learns nothing - not which paths exist, not which mailbox names are well formed.
// Then the route, the mailbox, the method, authorization, and only then the body, read under a cap.
// 8c's rate limits and mailbox caps go between authorization and the body (LIMITS, below).
//
// WHAT IS READ OF A REQUEST: the path, the query numbers, and the outer JSON of a put or an ack - key,
// text and through, the fields relays/Port.ps1 already exposes. The text is checked as printable ASCII
// of the right length and stored as it came; it is never parsed, opened or logged.
import { authenticate, authorize } from "./auth.js";
import { answer, refuse } from "./answers.js";
import { mailboxProblem, keyProblem, itemTextProblem, wholeOf, MAX_TEXT_CHARS, MAX_BATCH, MAX_WATCH_MS, SEQ_MAX } from "./rules.js";

export const API_ROOT = "/v1/";
const ROUTE = /^\/v1\/mailboxes\/([^/]{1,63})\/([^/]{1,63})\/(items|watch|ack)$/;
const OPS = { "items GET": "get", "items POST": "put", "watch GET": "watch", "ack POST": "ack" };
// THE BODY CAP: the longest put body there can be - a text of maxTextChars in which every character is
// a quote or a backslash, so JSON writes each as two - and 1024 for the key and the punctuation. A body
// past it is refused before it is all read.
const BODY_BYTES = 2 * MAX_TEXT_CHARS + 1024;

export function isApiPath(pathname) {
  return pathname === "/v1" || pathname.startsWith(API_ROOT);
}

// The body as text, or null when it is longer than cap: read chunk by chunk, so a body that says
// nothing of its length, or lies about it, is still never held past the cap.
async function readCapped(request, cap) {
  const declared = request.headers.get("Content-Length");
  if (declared !== null && !(Number(declared) <= cap)) return null;
  if (!request.body) return "";
  const reader = request.body.getReader();
  const parts = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > cap) { await reader.cancel(); return null; }
    parts.push(value);
  }
  const all = new Uint8Array(size);
  let at = 0;
  for (const p of parts) { all.set(p, at); at += p.byteLength; }
  return new TextDecoder("utf-8", { fatal: false }).decode(all);
}

// The body as an object with exactly the members named, or a refusal.
async function readJson(request, members) {
  const text = await readCapped(request, BODY_BYTES);
  if (text === null) return { refusal: refuse(413, "the body is longer than this relay takes") };
  let body;
  try { body = JSON.parse(text); } catch (e) { return { refusal: refuse(400, "the body is not JSON") }; }
  if (!body || typeof body !== "object" || Array.isArray(body)) return { refusal: refuse(400, "the body is not a JSON object") };
  const names = Object.keys(body).sort().join(",");
  if (names !== members.slice().sort().join(",")) return { refusal: refuse(400, "the body must hold exactly: " + members.join(", ")) };
  return { body };
}

function boxOf(env, mailbox) {
  return env.MAILBOX.get(env.MAILBOX.idFromName(mailbox));
}

async function put(request, env, mailbox) {
  const { body, refusal } = await readJson(request, ["key", "text"]);
  if (refusal) return refusal;
  if (keyProblem(body.key)) return refuse(400, "the key is not 1 to 160 of A-Z, a-z, 0-9 and . _ : / -");
  if (typeof body.text === "string" && body.text.length > MAX_TEXT_CHARS) return refuse(413, "the text is longer than the " + MAX_TEXT_CHARS + " characters this relay holds");
  if (itemTextProblem(body.text)) return refuse(400, "the text is not 1 to " + MAX_TEXT_CHARS + " printable ASCII characters");
  const done = await boxOf(env, mailbox).put(body.key, body.text);
  if (!done.ok) return refuse(400, "the mailbox refused the item");
  return answer(200, { seq: done.seq, duplicate: done.duplicate });
}

function readArgs(url, withTimeout) {
  const since = wholeOf(url.searchParams.get("since"), SEQ_MAX);
  const max = wholeOf(url.searchParams.get("max"), MAX_BATCH);
  if (since === null) return { refusal: refuse(400, "since must be a whole number from 0 to 2^53-1") };
  if (max === null || max < 1) return { refusal: refuse(400, "max must be a whole number from 1 to " + MAX_BATCH) };
  if (!withTimeout) return { since, max };
  const timeoutMs = wholeOf(url.searchParams.get("timeoutMs"), MAX_WATCH_MS);
  if (timeoutMs === null) return { refusal: refuse(400, "timeoutMs must be a whole number from 0 to " + MAX_WATCH_MS) };
  return { since, max, timeoutMs };
}

async function get(env, url, mailbox) {
  const a = readArgs(url, false);
  if (a.refusal) return a.refusal;
  return answer(200, await boxOf(env, mailbox).read(a.since, a.max));
}

async function watch(request, env, url, mailbox) {
  if ((request.headers.get("Upgrade") || "").toLowerCase() !== "websocket") return refuse(426, "a watch is a WebSocket upgrade");
  const a = readArgs(url, true);
  if (a.refusal) return a.refusal;
  const inner = new URL("https://mailbox/watch");
  inner.searchParams.set("since", String(a.since));
  inner.searchParams.set("max", String(a.max));
  inner.searchParams.set("timeoutMs", String(a.timeoutMs));
  return boxOf(env, mailbox).fetch(new Request(inner.href, { headers: { Upgrade: "websocket" } }));
}

async function ack(request, env, mailbox) {
  const { body, refusal } = await readJson(request, ["through"]);
  if (refusal) return refusal;
  if (!Number.isSafeInteger(body.through) || body.through < 0) return refuse(400, "through must be a whole number from 0 to 2^53-1");
  const done = await boxOf(env, mailbox).ack(body.through);
  if (!done.ok) return refuse(409, "the mailbox ends at " + done.head + "; an ack through " + body.through + " is past it");
  return answer(200, { through: body.through });
}

export async function handleApi(request, env, url) {
  const who = await authenticate(request, env, url);
  if (!who) return refuse(401, "this relay answers only a signed-in phone or a registered machine");
  const m = ROUTE.exec(url.pathname);
  if (!m) return refuse(404, "there is no such relay operation");
  const mailbox = m[1] + "/" + m[2];
  if (mailboxProblem(mailbox)) return refuse(400, "a mailbox is <horde>/<reader>, each 1 to 63 of a-z, 0-9 and -, starting with a letter or digit, and no device name");
  const op = OPS[m[3] + " " + request.method];
  if (!op) return refuse(405, "that method does not apply to " + m[3]);
  if (!authorize(who, op, mailbox)) return refuse(403, "you may not " + op + " in this mailbox");
  // LIMITS (8c): rate limits per caller, a cap on items and bytes per mailbox, and retention, go here.
  if (op === "put") return put(request, env, mailbox);
  if (op === "get") return get(env, url, mailbox);
  if (op === "watch") return watch(request, env, url, mailbox);
  return ack(request, env, mailbox);
}
