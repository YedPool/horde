// relays/cloudflare/worker/api.js - the mailbox API: the four operations of the relay port
// (relays/Port.ps1) over HTTP, each checked here and carried out by the mailbox's Durable Object.
//
//   GET  /v1/mailboxes/<horde>/<reader>/items?since=<n>&max=<n>                  -> 200 { items }
//   POST /v1/mailboxes/<horde>/<reader>/items   { "key": "...", "text": "..." }   -> 200 { seq, duplicate }
//   POST /v1/mailboxes/<horde>/<reader>/items?keepFrom=<n>   the same put, by a machine, that also
//        deletes the older items of its own stream (below)        -> 200 { seq, duplicate, trimmed }
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
// for a rate, Retry-After (answers.js): 429, 507 mailbox-full, 410 mailbox-gone, 401 account-gone - and
// for the whole relay, every account together (budget.js), 429 relay-daily-limit and 507 relay-full.
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
//
// A SENDER TRIMS ITS OWN STREAM (relays/Port.ps1, the section of that name; mailbox.js does it). The
// phone's mailbox is acked by nobody - several phones read it - so it only ever grew, to the 2,000
// envelopes after which every put is refused (limits.js). A put may therefore say keepFrom=<n>: of the
// items in this mailbox whose KEY names the same sender and channel as the put's own key, delete those
// whose seq in that stream is before n. The relay reads keys for this and nothing else.
//   - IN THE QUERY, because a machine's signature covers the path and the query (request-signature.js)
//     and the body's members are held to exactly key and text (body.js): a deployment from before
//     this takes the put and ignores the query, and one from after it answers trimmed, so the machine
//     can tell which it is speaking to without a request to ask.
//   - ONLY A MACHINE, AND ONLY ITS OWN STREAM: the key's sender must be the very key id that signed the
//     request (auth.js), so one machine can never trim another's envelopes, even in its own horde's
//     mailbox, and no key it does not hold can be named. A PHONE MAY NEVER TRIM, whatever it sends: 403,
//     and the put is not made. (The test principal of a local dev, which has no key, may trim the
//     stream its key names: the conformance suite measures the mailbox's contract through it.)
//   - NEVER ITSELF: keepFrom is 1 to the key's own seq, or the request is refused, 400, and nothing is put.
//   - IT COSTS NO REQUEST: it is the put, counted once (limits.js, requestsPerDay).
import { authenticate, authorize } from "./auth.js";
import { answer, refuse, refusalOf } from "./answers.js";
import { readJson } from "./body.js";
import { handleAccountApi, isAccountPath } from "./account-api.js";
import { handleRotation, ROTATION_PATH } from "./rotation.js";
import { accountOf } from "./accounts.js";
import { mailboxOf } from "./mailbox.js";
import { limitsOf } from "./limits.js";
import { ownersOf } from "./budget.js";
import { mailboxProblem, keyProblem, itemTextProblem, wholeOf, streamOf, MAX_TEXT_CHARS, MAX_BATCH, MAX_WATCH_MS, SEQ_MAX, BODY_BYTES } from "./rules.js";

export const API_ROOT = "/v1/";
const ROUTE = /^\/v1\/mailboxes\/([^/]{1,63})\/([^/]{1,63})\/(items|watch|ack)$/;
const OPS = { "items GET": "get", "items POST": "put", "watch GET": "watch", "ack POST": "ack" };

export function isApiPath(pathname) {
  return pathname === "/v1" || pathname.startsWith(API_ROOT);
}

// May who trim the stream this key names (the header, A SENDER TRIMS ITS OWN STREAM)? A machine, its
// own; the test principal, any; a phone, none.
function mayTrim(who, stream) {
  if (who.kind === "machine") return stream.sender === who.keyId;
  return who.kind === "test";
}

async function put(request, url, box, limits, owner, who) {
  // THE TRIM IS JUDGED BEFORE THE BODY IS READ AS FAR AS IT CAN BE: who asks. A phone that names
  // keepFrom is refused whatever else it sent, so nothing of a phone's can ever reach the trim.
  const asked = url.searchParams.get("keepFrom");
  let keepFrom = 0;
  if (asked !== null) {
    if (who.kind !== "machine" && who.kind !== "test") return refuse(403, "only the machine that wrote a stream may trim it");
    const n = wholeOf(asked, SEQ_MAX);
    if (n === null || n < 1) return refuse(400, "keepFrom must be a whole number from 1 to 2^53-1");
    keepFrom = n;
  }
  const { body, refusal } = await readJson(request, ["key", "text"], BODY_BYTES);
  if (refusal) return refusal;
  if (keyProblem(body.key)) return refuse(400, "the key is not 1 to 160 of A-Z, a-z, 0-9 and . _ : / -");
  if (typeof body.text === "string" && body.text.length > MAX_TEXT_CHARS) return refuse(413, "the text is longer than the " + MAX_TEXT_CHARS + " characters this relay holds");
  if (itemTextProblem(body.text)) return refuse(400, "the text is not 1 to " + MAX_TEXT_CHARS + " printable ASCII characters");
  if (keepFrom > 0) {
    const stream = streamOf(body.key);
    if (!stream) return refuse(400, "a put that trims must have a key that names its stream: <sender>/<channel>/<seq>/<nonce>");
    if (!mayTrim(who, stream)) return refuse(403, "only the machine that wrote a stream may trim it");
    if (keepFrom > stream.seq) return refuse(400, "keepFrom is past the key's own seq: a put never trims itself");
  }
  const done = await box.put(body.key, body.text, { now: Date.now(), limits, owner, keepFrom });
  if (!done.ok) return done.code ? refusalOf(done) : refuse(400, "the mailbox refused the item");
  if (keepFrom > 0) return answer(200, { seq: done.seq, duplicate: done.duplicate, trimmed: done.trimmed });
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

// A PHONE'S WATCH REFUSED BY A RATE OR A DAY (429) is answered as an opened socket whose one message is
// the refusal { error, code } and which then closes, LIMITED - as the mailbox ends a watch it replaced
// (mailbox.js). A browser is never shown the status or the body of a refused WebSocket upgrade, only
// that it failed, so a phone would read a spent relay-wide day as "cannot reach the relay"; this way it
// reads the code, and says what it means in its own words (surfaces/pwa, relay-client.js and
// read-banner.js). A machine's
// adapter reads the status and Retry-After of a refused upgrade itself (relays/cloudflare/Relay.ps1),
// so its watch is refused as before. Not a WebSocket upgrade at all: refused as before, too.
export const LIMITED = 4003;
function refuseWatch(request, r) {
  if ((request.headers.get("Upgrade") || "").toLowerCase() !== "websocket") return refusalOf(r);
  const [client, server] = Object.values(new WebSocketPair());
  server.accept();
  server.send(JSON.stringify({ error: r.reason, code: r.code }));
  server.close(LIMITED, r.code);
  return new Response(null, { status: 101, webSocket: client });
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
    // The owners (budget.js): the account's own object decides its tier, by its id and the verified
    // email it keeps from its sign-in - nothing this request carries.
    const g = await accountOf(env, who.account).admit({ device: who.device, epoch: who.epoch, op, mailbox, now: Date.now(), limits, owners: ownersOf(env) });
    if (!g.ok) return op === "watch" && who.kind === "phone" && g.status === 429 ? refuseWatch(request, g) : refusalOf(g);
  }
  const box = mailboxOf(env, who.account, who.epoch, mailbox);
  if (op === "put") return put(request, url, box, limits, who.gated ? { account: who.account, epoch: who.epoch, mailbox } : null, who);
  if (op === "get") return get(url, box);
  if (op === "watch") return watch(request, url, box, who.device);
  return ack(request, box);
}
