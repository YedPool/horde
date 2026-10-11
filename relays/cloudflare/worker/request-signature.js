// relays/cloudflare/worker/request-signature.js - how a MACHINE proves each request is its own: no token
// and no session, a signature by the signing key a signed-in phone registered to its account (machines.js)
// - the very key relay/Identity.ps1 keeps non-exportable, in the TPM where it can.
//
// THE HEADER, one line, every part required and in this order:
//   Authorization: Horde-Machine key=<key id, 32 hex>,time=<ms since 1970>,nonce=<32 hex>,sig=<86 base64url>
// THE SIGNED BYTES, one field to a line:
//   "horde-relay/request/v1" LF origin LF METHOD LF path?query LF time LF nonce LF key id LF
//   base64url(SHA-256(body))
// The origin is the site's (site.js), so a signature made for one deployment is worthless at another;
// the method, path and query are the request's own, so a signed read cannot be replayed as an ack; the
// body's hash binds a put's key and text and an ack's cursor. The signature is ES256 over those bytes,
// 64 bytes r || s, LOW-S (relay/P256.ps1): its high-S twin is refused, so one request has one signature.
// relays/cloudflare/RequestSigner.ps1 writes the same, through the machine's own crypto backend.
//
// FRESH AND ONCE. time must be within MAX_SKEW_MS of the Worker's clock, either side, and a nonce is
// taken once per key: the key's object (machines.js) keeps every nonce it has seen for longer than the
// window, so a request copied off the wire is refused whether it is replayed at once or later.
// A machine's clock that is off by more than a minute is refused too - in words that say so.
import { b64u, sha256, utf8 } from "../../../relay/js/protocol.js";

export const SCHEME = "Horde-Machine";
export const REQUEST_DOMAIN = "horde-relay/request/v1\n";
export const MAX_SKEW_MS = 60000;
const HEADER = /^Horde-Machine key=([0-9a-f]{32}),time=(0|[1-9][0-9]{0,15}),nonce=([0-9a-f]{32}),sig=([A-Za-z0-9_-]{86})$/;

// The parts of a machine's Authorization header, or null when it is not one: { keyId, time, nonce, sig }.
export function readMachineAuthorization(header) {
  if (typeof header !== "string") return null;
  const m = HEADER.exec(header);
  if (!m) return null;
  const time = Number(m[2]);
  if (!Number.isSafeInteger(time)) return null;
  return { keyId: m[1], time, nonce: m[3], sig: m[4] };
}

export async function bodyHash(bytes) { return b64u(await sha256(bytes)); }

export function requestSignedBytes({ origin, method, target, time, nonce, keyId, hash }) {
  return utf8(REQUEST_DOMAIN + origin + "\n" + method + "\n" + target + "\n" + time + "\n" + nonce + "\n" + keyId + "\n" + hash);
}

export function isFresh(time, now) { return Math.abs(now - time) <= MAX_SKEW_MS; }
