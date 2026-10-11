// relays/cloudflare/worker/api.js - the mailbox API: the four operations of the relay port
// (relays/Port.ps1) over HTTP, each checked here and carried out by the mailbox's Durable Object.
//
//   GET  /v1/mailboxes/<horde>/<reader>/items?since=<n>&max=<n>                  -> 200 { items }
//   POST /v1/mailboxes/<horde>/<reader>/items   { "key": "...", "text": "..." }   -> 200 { seq, duplicate }
//   GET  /v1/mailboxes/<horde>/<reader>/watch?since=<n>&max=<n>&timeoutMs=<n>
//        a WebSocket upgrade: one message { items } when there is anything after since, then closed;
//        or one message { error, code } when the relay ends it (mailbox.js: a newer watch of the same
//        device replaced it, or the account was deleted), then closed with a code of 4000 and up
//   POST /v1/mailboxes/<horde>/<reader>/ack     { "through": <n> }                -> 200 { through }
// Under /v1/account, the account API (account-api.js): a signed-in phone's account. And
//   POST /v1/machines/rotation                  a machine's identity rotation (rotation.js), which is
//                                               its own authentication: signed by the NEW key, carrying
//                                               the OLD key's vouch - no principal exists for it yet.
//
// EVERY MAILBOX IS THE CALLER'S ACCOUNT'S (auth.js): the object behind "<horde>/<reader>" is named by
// the principal's account, its epoch AND the mailbox (mailbox.js, mailboxOf), so one account's
// "work/phone" is never another's, and no request can even name a mailbox outside its own account.
//
// A refusal is { error } with its status: 401 nobody vouched (auth.js), 403 not allowed this, 404 no such
// operation, 405 the wrong method, 400 a malformed request, 413 a body or text over the cap, 409 an ack
// past the head, 426 a watch that is not a WebSocket upgrade. A refusal by a limit adds its code and,
// for a rate, Retry-After (answers.js): 429, 507 mailbox-full, 410 mailbox-gone, 401 account-gone.
//
// THE ORDER IS THE POINT. Authentication comes first, before the route is even matched, so a caller
// nobody vouched for learns nothing - not which paths exist, not which mailbox names are well formed.
// Then the route, the mailbox, the method, authorization, THE ACCOUNT'S GATE (accounts.js, admit: the
// account still there, the device's rate, the account's day), and only then the body, read under a cap.
// The mailbox's own caps are its object's (mailbox.js), checked in the put itself.
//
// WHAT IS READ OF A REQUEST: the path, the query numbers, and the outer JSON of a put or an ack - key,
// text and through, the fields relays/Port.ps1 already exposes. The text is checked as printable ASCII
// of the right length and stored as it came; it is never parsed, opened or logged.
import { authenticate, authorize } from "./auth.js";
import { answer, refuse, refusalOf } from "./answers.js";
import { readJson } from "./body.js";
import { handleAccountApi, isAccountPath } from "./account-api.js";
import { handleRotation, ROTATION_PATH } from "./rotation.js";
import { accountOf } from "./accounts.js";
import { mailboxOf } from "./mailbox.js";
import { limitsOf } from "./limits.js";
import { mailboxProblem, keyProblem, itemTextProblem, wholeOf, MAX_TEXT_CHARS, MAX_BATCH, MAX_WATCH_MS, SEQ_MAX, BODY_BYTES } from "./rules.js";

export const API_ROOT = "/v1/";
const ROUTE = /^\/v1\/mailboxes\/([^/]{1,63})\/([^/]{1,63})\/(items|watch|ack)$/;
const OPS = { "items GET": "get", "items POST": "put", "watch GET": "watch", "ack POST": "ack" };

export function isApiPath(pathname) {
  return pathname === "/v1" || pathname.startsWith(API_ROOT);
}

async function put(request, box, limits) {
  const { body, refusal } = await readJson(request, ["key", "text"], BODY_BYTES);
  if (refusal) return refusal;
  if (keyProblem(body.key)) return refuse(400, "the key is not 1 to 160 of A-Z, a-z, 0-9 and . _ : / -");
  if (typeof body.text === "string" && body.text.length > MAX_TEXT_CHARS) return refuse(413, "the text is longer than the " + MAX_TEXT_CHARS + " characters this relay holds");
  if (itemTextProblem(body.text)) return refuse(400, "the text is not 1 to " + MAX_TEXT_CHARS + " printable ASCII characters");
  const done = await box.put(body.key, body.text, { now: Date.now(), limits });
  if (!done.ok) return done.code ? refusalOf(done) : refuse(400, "the mailbox refused the item");
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

async function get(url, box) {
  const a = readArgs(url, false);
  if (a.refusal) return a.refusal;
  return answer(200, await box.read(a.since, a.max));
}

async function watch(request, url, box, device) {
  if ((request.headers.get("Upgrade") || "").toLowerCase() !== "websocket") return refuse(426, "a watch is a WebSocket upgrade");
  const a = readArgs(url, true);
  if (a.refusal) return a.refusal;
  const inner = new URL("https://mailbox/watch");
  inner.searchParams.set("since", String(a.since));
  inner.searchParams.set("max", String(a.max));
  inner.searchParams.set("timeoutMs", String(a.timeoutMs));
  inner.searchParams.set("device", device);
  return box.fetch(new Request(inner.href, { headers: { Upgrade: "websocket" } }));
}

async function ack(request, box) {
  const { body, refusal } = await readJson(request, ["through"], BODY_BYTES);
  if (refusal) return refusal;
  if (!Number.isSafeInteger(body.through) || body.through < 0) return refuse(400, "through must be a whole number from 0 to 2^53-1");
  const done = await box.ack(body.through);
  if (!done.ok) return refuse(409, "the mailbox ends at " + done.head + "; an ack through " + body.through + " is past it");
  return answer(200, { through: body.through });
}

export async function handleApi(request, env, url) {
  const limits = limitsOf(env, url);
  if (url.pathname === ROTATION_PATH) return handleRotation(request, env, url, limits);
  const who = await authenticate(request, env, url, limits);
  if (!who || typeof who.may !== "function") {
    if (who && who.status === 429) return refusalOf({ status: 429, code: who.code, reason: who.refusal, retryAfterMs: who.retryAfterMs });
    return refuse(401, who && who.refusal ? who.refusal : "this relay answers only a signed-in phone or a registered machine");
  }
  if (isAccountPath(url.pathname)) return handleAccountApi(request, env, url, who, limits);
  const m = ROUTE.exec(url.pathname);
  if (!m) return refuse(404, "there is no such relay operation");
  const mailbox = m[1] + "/" + m[2];
  if (mailboxProblem(mailbox)) return refuse(400, "a mailbox is <horde>/<reader>, each 1 to 63 of a-z, 0-9 and -, starting with a letter or digit, and no device name");
  const op = OPS[m[3] + " " + request.method];
  if (!op) return refuse(405, "that method does not apply to " + m[3]);
  if (!authorize(who, op, mailbox)) return refuse(403, "you may not " + op + " in this mailbox");
  if (who.gated) {
    const g = await accountOf(env, who.account).admit({ device: who.device, epoch: who.epoch, op, mailbox, now: Date.now(), limits });
    if (!g.ok) return refusalOf(g);
  }
  const box = mailboxOf(env, who.account, who.epoch, mailbox);
  if (op === "put") return put(request, box, limits);
  if (op === "get") return get(url, box);
  if (op === "watch") return watch(request, url, box, who.device);
  return ack(request, box);
}
