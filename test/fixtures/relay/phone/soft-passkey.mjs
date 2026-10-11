// A software passkey for the relay suites: what a phone's authenticator does for WebAuthn's create()
// and get(), made with WebCrypto, so the phone code above it (relay/js/protocol.js and the PWA's
// surfaces/pwa/page/phone-core.js) runs unchanged against it. TEST CODE ONLY: its private key is in
// memory and in the suite's state file, which a real passkey never allows.
//
// WHAT IT EMULATES, from WebAuthn Level 3:
//   create  attestation "none" (6.5): authData = rpIdHash, flags UP|UV|AT (0x45), counter 0, a zero
//           aaguid, the credential id and its COSE key; clientDataJSON type webauthn.create.
//   get     authData = rpIdHash, flags UP|UV (0x05), counter 0 (a synced passkey's), and the signature
//           over authData || SHA-256(clientDataJSON), DER, as an authenticator returns it.
//   prf     the PRF extension (L3 10.1.4) the way a client builds it on hmac-secret: the input is
//           hashed as SHA-256("WebAuthn PRF" || 0x00 || input) and HMAC-SHA256'd under a random
//           per-credential secret. So one credential and one input always give the same 32 bytes,
//           and another credential or input other bytes - all a phone relies on.
//
// The state is plain JSON (toJSON / fromJSON), so the test phone can keep it between commands.
import { cat, sha256, utf8, b64u, unb64u, randomBytes } from "../../../../relay/js/protocol.js";

const subtle = globalThis.crypto.subtle;

function derInt(b) { let i = 0; while (i < b.length - 1 && b[i] === 0) i++; let v = b.slice(i); if (v[0] & 0x80) v = cat(new Uint8Array([0]), v); return cat(new Uint8Array([2, v.length]), v); }
export function toDer(sig) { const r = derInt(sig.slice(0, 32)), s = derInt(sig.slice(32)); return cat(new Uint8Array([0x30, r.length + s.length]), r, s); }

function head(major, n) {
  if (n < 24) return new Uint8Array([(major << 5) | n]);
  if (n < 0x100) return new Uint8Array([(major << 5) | 24, n]);
  return new Uint8Array([(major << 5) | 25, n >> 8, n & 255]);
}
function cbor(v) {
  if (typeof v === "number") return v >= 0 ? head(0, v) : head(1, -1 - v);
  if (typeof v === "string") { const b = utf8(v); return cat(head(3, b.length), b); }
  if (v instanceof Uint8Array) return cat(head(2, v.length), v);
  if (v.map) return cat(head(5, v.map.length), ...v.map.flatMap(([k, x]) => [cbor(k), cbor(x)]));
  throw new Error("cannot encode");
}

async function prfOf(secret, input) {
  const salt = await sha256(cat(utf8("WebAuthn PRF"), new Uint8Array([0]), input));
  const k = await subtle.importKey("raw", secret, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await subtle.sign("HMAC", k, salt));
}

// One authenticator holding any number of credentials. origin is what its "browser" puts in
// clientDataJSON; prf says whether it supports the PRF extension.
export function softAuthenticator({ origin, prf = true, state = null } = {}) {
  const creds = state ? state.creds : {};
  return {
    origin,
    prf,
    toJSON() { return { origin, prf, creds }; },
    async create({ rpId, challenge, prfInput = null }) {
      const kp = await subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
      const pub = new Uint8Array(await subtle.exportKey("raw", kp.publicKey));
      const credId = randomBytes(32);
      const secret = randomBytes(32);
      const cose = cbor({ map: [[1, 2], [3, -7], [-1, 1], [-2, pub.slice(1, 33)], [-3, pub.slice(33, 65)]] });
      const ad = cat(await sha256(utf8(rpId)), new Uint8Array([0x45, 0, 0, 0, 0]), new Uint8Array(16), new Uint8Array([0, credId.length]), credId, cose);
      const attestationObject = cbor({ map: [["fmt", "none"], ["attStmt", { map: [] }], ["authData", ad]] });
      const clientDataJSON = utf8(JSON.stringify({ type: "webauthn.create", challenge: b64u(challenge), origin, crossOrigin: false }));
      creds[b64u(credId)] = { jwk: await subtle.exportKey("jwk", kp.privateKey), rpId, secret: b64u(secret) };
      const out = { rawId: credId, clientDataJSON, attestationObject, publicPoint: pub, prfEnabled: prf, prfFirst: null };
      // Like the newer passkey providers, it evaluates PRF at creation when asked.
      if (prf && prfInput) out.prfFirst = await prfOf(secret, prfInput);
      return out;
    },
    async get({ rpId, credentialId, challenge, prfInput = null }) {
      const c = creds[b64u(credentialId)];
      if (!c || c.rpId !== rpId) throw new Error("NotAllowedError: no such credential for this relying party");
      const priv = await subtle.importKey("jwk", c.jwk, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
      const authenticatorData = cat(await sha256(utf8(rpId)), new Uint8Array([0x05, 0, 0, 0, 0]));
      const clientDataJSON = utf8(JSON.stringify({ type: "webauthn.get", challenge: b64u(challenge), origin, crossOrigin: false }));
      const p1363 = new Uint8Array(await subtle.sign({ name: "ECDSA", hash: "SHA-256" }, priv, cat(authenticatorData, await sha256(clientDataJSON))));
      const out = { authenticatorData, clientDataJSON, signature: toDer(p1363), prfFirst: null };
      if (prf && prfInput) out.prfFirst = await prfOf(unb64u(c.secret), prfInput);
      return out;
    }
  };
}
