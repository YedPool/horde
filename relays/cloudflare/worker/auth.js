// relays/cloudflare/worker/auth.js - THE AUTH SEAM: who may use the relay's API, and for what. DENY BY
// DEFAULT: a request no authenticator vouches for is refused before its route is even looked at.
//
// AN AUTHENTICATOR is a function (request, env, url, limits) that answers:
//   null                 - this request is not one of mine (no session cookie, no machine signature)
//   { refusal, status? } - it is one of mine, and it is refused, in words the caller may read: a
//                          machine whose clock is off (401), or - 429, with code and retryAfterMs - a
//                          key or an address whose signatures were refused too often, or a key past its
//                          nonces (limits.js); the next authenticator is still asked
//   a PRINCIPAL          - { name, kind, account, epoch, device, gated, may(op, target) }: who it is,
//                          which account's mailboxes it reaches (under the account's epoch: accounts.js),
//                          the device it is (the one its rates and its watch are counted by), whether
//                          the account's gate holds it to the limits, and what it may do there
// AUTHENTICATORS are tried in order and the first principal decides; authorize() then asks its may().
// The ops are the mailbox API's get, put, watch and ack (target: the mailbox), the account API's
// account, register and remove (account-api.js; target: the machine's key id), and a phone's end-phone
// (target: the phone's id) and delete (the account itself).
//
// AN ACCOUNT'S MAILBOXES ARE ITS OWN: the API addresses every mailbox under the principal's account
// (mailbox.js, mailboxOf), so no principal names another account's mailbox at all - there is no check to
// get wrong. What may() adds is what each kind may do inside its account:
//   PHONE    a Google sign-in's session (sessions.js), by its __Host- cookie (cookies.js): every op.
//            CSRF: a request that changes anything (any method but GET and HEAD) or opens a watch must
//            carry the site's own Origin (site.js), so a page elsewhere cannot use the phone's cookie;
//            SameSite=Lax keeps the cookie off cross-site posts besides, and there is no CORS at all.
//            Its device is its session's object id.
//   MACHINE  a request signed by a key registered to the account (request-signature.js, machines.js):
//            the mailboxes of the one horde its key was registered for, and removing its own key -
//            never another machine's, never the account's list. Its device is its key id.
//            REFUSED SIGNATURES ARE LIMITED (limits.js): per key and address in the key's own object
//            (machines.js: never for the key as a whole, which would let a forger lock it out), and per
//            address - each refusal is told to the address's object (address.js), and once that
//            says the address is over its rate, this isolate refuses the address's machine requests at
//            once, 429, with no signature checked and no object asked, until it refills.
//   TEST     the 8a test authenticator, unchanged: it vouches only when ALL of these hold:
//              - the binding HORDE_RELAY_TEST_AUTH is present and at least 32 characters. It is defined
//                only in test-bindings.json, which only the test launcher merges in
//                (relays/cloudflare/Wrangler.ps1), and there it holds a placeholder too short to count:
//                the launcher writes a fresh random token over it for each run. wrangler.json, the
//                production config, has no HORDE_RELAY_TEST_ binding, and the deploy refuses a config
//                that does (relays/cloudflare/Deploy.ps1); test-cloudflare-worker.ps1 checks both;
//              - the request was made to this machine itself (127.0.0.1, localhost or [::1]: site.js) -
//                a deployed Worker is never reached under those names, so even a deploy that carried
//                the binding would vouch for no one;
//              - it carries "Authorization: Bearer <that token>", compared in constant time.
//            Its account is "test", its own, with no account record: the gate does not hold it
//            (gated false), so the relays conformance suite measures the mailbox contract and not the
//            limits; a mailbox's own caps (mailbox.js) still hold it.
// The limits go after authorize(), in the account's gate (accounts.js, admit), which api.js asks.
import { readCookie, SESSION_COOKIE } from "./cookies.js";
import { sessionOf } from "./sessions.js";
import { machineKeyOf } from "./machines.js";
import { readMachineAuthorization, requestSignedBytes, bodyHash, isFresh, MAX_SKEW_MS } from "./request-signature.js";
import { readCappedBytes } from "./body.js";
import { BODY_BYTES } from "./rules.js";
import { siteOf, isLoopback, fromSite } from "./site.js";
import { addressOf } from "./address.js";
import { clientAddressOf } from "./client-address.js";
import { CODES } from "./answers.js";

const TEST_BINDING = "HORDE_RELAY_TEST_AUTH";
const TEST_TOKEN_MIN = 32;
const MAILBOX_OPS = new Set(["get", "put", "watch", "ack"]);
const PHONE_OPS = new Set(["get", "put", "watch", "ack", "account", "register", "remove", "end-phone", "delete"]);
// Addresses this isolate refuses machine requests from, and until when (ms): learned from the address's
// object (address.js) at a refusal, so a flood of forged signatures costs no object call once it is
// over the rate. Bounded: the oldest is forgotten first.
const blocked = new Map();
const BLOCKED_MAX = 4096;

function sameText(a, b) {
  const enc = new TextEncoder();
  const x = enc.encode(a);
  const y = enc.encode(b);
  if (x.byteLength !== y.byteLength) return false;
  return crypto.subtle.timingSafeEqual(x, y);
}

function testAuthenticator(request, env, url) {
  const token = env[TEST_BINDING];
  if (typeof token !== "string" || token.length < TEST_TOKEN_MIN) return null;
  if (!isLoopback(url)) return null;
  const given = request.headers.get("Authorization");
  if (typeof given !== "string" || !sameText(given, "Bearer " + token)) return null;
  return { name: "test", kind: "test", account: "test", epoch: "", device: "", gated: false, may: () => true };
}

async function phoneAuthenticator(request, env) {
  const id = readCookie(request, SESSION_COOKIE);
  if (id === null) return null;
  const changes = request.method !== "GET" && request.method !== "HEAD";
  const watch = (request.headers.get("Upgrade") || "").toLowerCase() === "websocket";
  if ((changes || watch) && !fromSite(request, siteOf(env))) return null;
  const session = sessionOf(env, id);
  if (!session) return null;
  const s = await session.read(Date.now());
  if (!s) return null;
  const phone = session.id.toString();
  return { name: "phone", kind: "phone", account: s.account, epoch: s.epoch, email: s.email, phone, device: "phone:" + phone, gated: true, may: (op) => PHONE_OPS.has(op) };
}

// The refusal of an address over its rate of refused signatures, or null.
function blockedRefusal(address, now) {
  const until = blocked.get(address);
  if (until === undefined) return null;
  if (until <= now) { blocked.delete(address); return null; }
  return { refusal: "too many refused machine signatures came from this address: wait a minute", status: 429, code: CODES.rate, retryAfterMs: until - now };
}

// A machine signature from address was refused: told to the address's object, and the address blocked
// here when that says it is over its rate. The refusal to answer, or null (the fixed 401).
export async function noteRefusedSignature(env, address, now, limits) {
  const r = await addressOf(env, address).refusedSignature({ now, limits });
  if (r.ok) return null;
  if (blocked.size >= BLOCKED_MAX) blocked.delete(blocked.keys().next().value);
  blocked.set(address, now + r.retryAfterMs);
  return blockedRefusal(address, now);
}

// Is address refused at once here (blocked)? The refusal, or null. For the rotation route too.
export function addressRefusal(address, now) { return blockedRefusal(address, now); }

async function machineAuthenticator(request, env, url, limits) {
  const a = readMachineAuthorization(request.headers.get("Authorization"));
  if (!a) return null;
  const now = Date.now();
  if (!isFresh(a.time, now)) return { refusal: "the request's time is more than " + (MAX_SKEW_MS / 1000) + " s from the relay's clock: set this machine's clock" };
  const address = clientAddressOf(request, env, url);
  const held = blockedRefusal(address, now);
  if (held) return held;
  const bytes = await readCappedBytes(request.clone(), BODY_BYTES);
  if (bytes === null) return null;
  const signed = requestSignedBytes({ origin: siteOf(env).origin, method: request.method, target: url.pathname + url.search, time: a.time, nonce: a.nonce, keyId: a.keyId, hash: await bodyHash(bytes) });
  const v = await machineKeyOf(env, a.keyId).verify({ nonce: a.nonce, sig: a.sig, signed, now, limits, address });
  if (v && v.status === 429) return { refusal: v.refused, status: 429, code: v.code, retryAfterMs: v.retryAfterMs };
  if (!v || typeof v.account !== "string") return noteRefusedSignature(env, address, now, limits);
  const keyId = a.keyId;
  const horde = v.horde;
  return {
    name: "machine " + keyId, kind: "machine", account: v.account, epoch: v.epoch, keyId, horde, label: v.label, device: "machine:" + keyId, gated: true,
    may: (op, target) => (MAILBOX_OPS.has(op) ? String(target).split("/")[0] === horde : op === "remove" && target === keyId)
  };
}

export const AUTHENTICATORS = [testAuthenticator, phoneAuthenticator, machineAuthenticator];

// Who the request is: a principal; or { refusal } when one authenticator refused it in words; or null.
// limits are the request's (limits.js).
export async function authenticate(request, env, url, limits) {
  let refused = null;
  for (const vouch of AUTHENTICATORS) {
    const who = await vouch(request, env, url, limits);
    if (who && typeof who.may === "function") return who;
    if (who && refused === null) refused = who;
  }
  return refused;
}

// May who do op on target? Only what its own authenticator allows.
export function authorize(who, op, target) {
  return Boolean(who) && typeof who.may === "function" && who.may(op, target) === true;
}
