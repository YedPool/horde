// relays/cloudflare/worker/join.js - a new phone, signed in to the account, ASKS TO JOIN one machine of
// it ("Add this phone"): the account API's join routes (account-api.js routes them here, after the
// principal's authorization and the account's gate).
//
//   POST /v1/account/join                    { machine, request, label, agent, requestKey }
//                                            -> 200 { request, expiresAt }            a phone only
//   POST /v1/account/join/<request>/close    { outcome: approved | rejected | expired | ended }
//                                            -> 200 { freed: true | false }           a machine only
//
// JOIN REQUESTS (phone-started pairing)
//
// WHAT THE RELAY DOES WITH ONE: it checks it, holds it to the limits below, and puts it - one canonical
// item - into the mailbox of the machine it names, "<horde>/<machine>", under the key "join/<request>",
// where that machine's runner reads it. That is all. NOTHING THE RELAY DOES GRANTS TRUST: a join request
// is only a request. The machine answers it, and trust comes only when the person types, on a device he
// already trusts, the 12-digit number the new phone shows, and that device compares it with the number
// it computed itself. The relay holds no number and no key that could make an approval, so the limits
// here guard against a flood, never against a forgery - the number does that.
//
// THE LIMITS (limits.js; why: the design's threat of a flood of requests, from someone else signed in to
// the account or from a script). Each refusal is a refusal - answered with its status and code - never
// a request quietly dropped, and the relay NEVER RETRIES one: the person taps Add this phone again.
//   - ONE PENDING JOIN REQUEST AN ACCOUNT. A second, under another id, is refused 409 join-pending
//     while the first is pending; the same request again (its id, its machine) is answered 200 again,
//     as the first was, with nothing spent - so a phone whose answer was lost may ask again.
//   - A PENDING REQUEST LIVES joinRequestMs (10 minutes). Past it, it is not pending any more, and the
//     slot is free without anyone acting.
//   - joinRequestsPerHour PER ACCOUNT (6), and joinRequestsPerHourPerAddress PER CLIENT ADDRESS (6,
//     client-address.js) across accounts: each a bucket refilled at its number an hour; past either,
//     429 rate-limited, with Retry-After.
//   - A REJECT FREES THE SLOT AT ONCE AND BLOCKS THE ADDRESS (the design's slot squatting: someone in
//     the account keeping the one slot busy so the person cannot add his own phone). The machine
//     tells the relay every request's end through the close route; when the end is "rejected", the
//     address the request came from is refused join requests for joinBlockMs (an hour), 429
//     join-blocked, so one tap clears the slot and the same address cannot take it straight back.
//     Approved, expired and ended free the slot and block nothing.
//
// THE ORDER, AND WHAT A REFUSAL SPENDS. The fields are checked first (400, or 404 for a machine not on
// this account), then:
//   (a) the address is not blocked                      address.js   else 429 join-blocked
//   (b) no OTHER request of the account is pending      accounts.js  else 409 join-pending
//   (c) the account's bucket has a token                accounts.js  else 429 rate-limited
//   (d) the address's bucket has a token                address.js   else 429 rate-limited
// A REFUSAL SPENDS NOTHING. The address's object answers (a) and takes its token for (d) in one call;
// the account's object then answers (b), (c) and (d) in that order and, on a yes, spends its token and
// holds the slot together, in one call - so two requests at once can never both take the one slot.
// When the account refuses, or the request is a repeat, the address's token is given back; when the
// mailbox then refuses the item (its caps, or the request id was used before - a request is taken
// once), the slot is let go and both tokens are given back. Between the address's take and its giving
// back, a second request from the same address may find one token fewer: refused, never let through.
//
// THE ITEM is this ASCII JSON, members in this order, no spaces - the one spelling the machine reads
// (relay/Join.ps1):
//   {"v":1,"kind":"horde-relay-join-request","request":"<32 hex>","horde":"<horde>","machine":"<32 hex>",
//    "label":"<label>","agent":"<agent>","requestKey":"<base64url, 87>","country":"<country>",
//    "requestedAt":<ms>,"expiresAt":<ms>}
// country is Cloudflare's for the caller (request.cf.country) when it is two capital letters, else "".
// A local test (the test limits binding, a request to this machine itself: limits.js, THE TEST OVERRIDE)
// may name it with the header Horde-Test-Country, as it names its address (client-address.js).
//
// A JOIN REQUEST GOES INTO A MAILBOX ONLY THROUGH HERE: api.js refuses a phone's or a machine's put of
// a key starting "join/", so no limit above can be gone around.
import { answer, refuse, refuseWith, refusalOf, CODES } from "./answers.js";
import { readJson } from "./body.js";
import { accountOf } from "./accounts.js";
import { addressOf } from "./address.js";
import { mailboxOf } from "./mailbox.js";
import { clientAddressOf } from "./client-address.js";
import { mailboxProblem } from "./rules.js";
import { isLoopback } from "./site.js";
import { b64u, unb64u, validLabel } from "../../../relay/js/protocol.js";

export const JOIN_PATH = "/v1/account/join";
export const JOIN_KEY_PREFIX = "join/";
const CLOSE = /^\/v1\/account\/join\/([0-9a-f]{32})\/close$/;
const KEY_ID = /^[0-9a-f]{32}$/;
const REQUEST_ID = /^[0-9a-f]{32}$/;
// Printable ASCII without the quote and the backslash, so the item's JSON needs no escape; 0 to 200.
const AGENT = /^[\x20\x21\x23-\x5b\x5d-\x7e]{0,200}$/;
// A P-256 point, uncompressed, is 65 bytes: 87 base64url characters with no padding.
const REQUEST_KEY = /^[A-Za-z0-9_-]{87}$/;
const COUNTRY = /^[A-Z]{2}$/;
const MEMBERS = ["machine", "request", "label", "agent", "requestKey"];
// The longest body a join request can be is under 500 bytes; the cap leaves room and nothing more.
const JOIN_BYTES = 1024;
const CLOSE_BYTES = 256;
const OUTCOMES = new Set(["approved", "rejected", "expired", "ended"]);
const TEST_BINDING = "HORDE_RELAY_TEST_LIMITS";
const TEST_COUNTRY = "Horde-Test-Country";

export function isJoinPath(pathname) { return pathname === JOIN_PATH || CLOSE.test(pathname); }

// The request id a close path names, or null.
export function closedRequestOf(pathname) { const m = CLOSE.exec(pathname); return m ? m[1] : null; }

// Is text a P-256 public point, uncompressed, in base64url's one spelling, that WebCrypto takes?
async function isRequestKey(text) {
  if (typeof text !== "string" || !REQUEST_KEY.test(text)) return false;
  let bytes;
  try { bytes = unb64u(text); } catch (e) { return false; }
  if (bytes.length !== 65 || bytes[0] !== 4 || b64u(bytes) !== text) return false;
  try { await crypto.subtle.importKey("raw", bytes, { name: "ECDH", namedCurve: "P-256" }, true, []); return true; } catch (e) { return false; }
}

// The caller's country (the header, THE ITEM): two capital letters, or "".
export function countryOf(request, env, url) {
  if (typeof env[TEST_BINDING] === "string" && isLoopback(url)) {
    const t = request.headers.get(TEST_COUNTRY);
    if (t !== null) return COUNTRY.test(t) ? t : "";
  }
  const c = request.cf && request.cf.country;
  return typeof c === "string" && COUNTRY.test(c) ? c : "";
}

// THE ITEM's text (the header): every value was checked before, so JSON writes none with an escape.
export function joinItemText({ request, horde, machine, label, agent, requestKey, country, requestedAt, expiresAt }) {
  return JSON.stringify({ v: 1, kind: "horde-relay-join-request", request, horde, machine, label, agent, requestKey, country, requestedAt, expiresAt });
}

// POST /v1/account/join, from a phone whose authorization and gate are done (account-api.js).
export async function requestJoin(request, env, url, who, limits) {
  const { body, refusal } = await readJson(request, MEMBERS, JOIN_BYTES);
  if (refusal) return refusal;
  if (typeof body.machine !== "string" || !KEY_ID.test(body.machine)) return refuse(400, "the machine is not a key id");
  if (typeof body.request !== "string" || !REQUEST_ID.test(body.request)) return refuse(400, "the request is not a join request id: 32 lower-case hex");
  if (!validLabel(body.label)) return refuse(400, "the label is not 1 to 64 printable ASCII characters, no quote or backslash, no space at either end");
  if (typeof body.agent !== "string" || !AGENT.test(body.agent)) return refuse(400, "the agent is not 0 to 200 printable ASCII characters, no quote or backslash");
  if (!(await isRequestKey(body.requestKey))) return refuse(400, "the requestKey is not a P-256 public key, uncompressed, in base64url");
  const account = accountOf(env, who.account);
  const entry = await account.machineEntry(body.machine);
  if (!entry) return refuse(404, "no such machine on this account");
  const mailbox = entry.horde + "/" + body.machine;
  if (mailboxProblem(mailbox)) return refuse(400, "that machine's horde names no mailbox");
  const now = Date.now();
  const address = clientAddressOf(request, env, url);
  const place = addressOf(env, address);
  const a = await place.joinAdmit({ now, limits });
  if (a.blocked) return refuseWith(429, CODES.joinBlocked, "a join request from this address was rejected: it may make none for an hour", a.retryAfterMs);
  let r;
  try {
    r = await account.joinReserve({ request: body.request, machine: body.machine, address, epoch: who.epoch, addressOk: a.taken, addressRetryMs: a.retryAfterMs, now, limits });
  } catch (e) {
    if (a.taken) await place.joinRefund({ limits });
    throw e;
  }
  if (a.taken && (!r.ok || r.repeat)) await place.joinRefund({ limits });
  if (!r.ok) return refusalOf(r);
  if (r.repeat) return answer(200, { request: body.request, expiresAt: r.expiresAt });
  const text = joinItemText({ request: body.request, horde: entry.horde, machine: body.machine, label: body.label, agent: body.agent, requestKey: body.requestKey, country: countryOf(request, env, url), requestedAt: r.requestedAt, expiresAt: r.expiresAt });
  let done = null;
  let failure = null;
  try {
    done = await mailboxOf(env, who.account, who.epoch, mailbox).put(JOIN_KEY_PREFIX + body.request, text, { now, limits, owner: { account: who.account, epoch: who.epoch, mailbox } });
  } catch (e) { failure = e; }
  if (failure !== null || !done.ok || done.duplicate) {
    await account.joinRelease({ request: body.request, limits });
    if (a.taken) await place.joinRefund({ limits });
    if (failure !== null) throw failure;
    if (done.duplicate) return refuse(409, "that join request id was used before: a request is taken once, so make a new one");
    return done.code ? refusalOf(done) : refuse(400, "the mailbox refused the join request");
  }
  return answer(200, { request: body.request, expiresAt: r.expiresAt });
}

// POST /v1/account/join/<request>/close, from a machine whose authorization and gate are done.
export async function closeJoin(request, env, who, requestId, limits) {
  const { body, refusal } = await readJson(request, ["outcome"], CLOSE_BYTES);
  if (refusal) return refusal;
  if (typeof body.outcome !== "string" || !OUTCOMES.has(body.outcome)) return refuse(400, "a join request ends approved, rejected, expired or ended");
  const now = Date.now();
  const c = await accountOf(env, who.account).joinClose({ request: requestId, keyId: who.keyId, now });
  if (!c.ok) return refuse(c.status, c.reason);
  if (c.freed && body.outcome === "rejected" && c.address) await addressOf(env, c.address).joinBlock({ now, limits });
  return answer(200, { freed: c.freed === true });
}
