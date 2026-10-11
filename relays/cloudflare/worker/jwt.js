// relays/cloudflare/worker/jwt.js - an OpenID Connect id token, verified WHOLLY before one claim of it is
// believed: its RS256 signature against the provider's published keys, then who issued it, for whom,
// when, for which sign-in, and whether the provider vouches for the email.
//
// WHY ALL OF IT, when the token came straight from the provider's token endpoint over TLS (signin.js):
// the code it was exchanged for came through the browser, and the endpoint is only as sure as this
// Worker's fetch; a token whose signature is checked needs neither to be trusted. What is refused, each
// in its own words (test/units.mjs provokes every one):
//   - a token that is not three base64url parts, or is longer than any id token (8 KiB);
//   - an alg other than RS256 - "none", HS256 (a provider's public key used as an HMAC secret) or any
//     other - and a key id the provider does not publish;
//   - a signature that does not verify under that key;
//   - an issuer not the provider's; an audience not this client (a list must name it, and then azp must
//     be this client, as OpenID Connect Core 3.1.3.7 says);
//   - expired (exp at or before now, less the skew), issued in the future (iat after now, plus the skew),
//     or issued longer ago than a sign-in lasts (maxAgeMs): a replayed old token is refused even
//     unexpired;
//   - a nonce not the one this browser's sign-in sent (signin.js): a token minted for another sign-in;
//   - email_verified not exactly true;
//   - a subject that is not 1 to 255 printable characters.
// THE ACCOUNT IS THE SUBJECT, never the email: an address can change hands, Google's sub never does.
import { unb64u, utf8, fromUtf8 } from "../../../relay/js/protocol.js";

export const SKEW_MS = 60000;
const TOKEN_CHARS = 8192;
const PART = /^[A-Za-z0-9_-]+$/;
const SUB = /^[\x21-\x7e]{1,255}$/;

function partJson(text) {
  try { const v = JSON.parse(fromUtf8(unb64u(text))); return v && typeof v === "object" && !Array.isArray(v) ? v : null; } catch (e) { return null; }
}

// Verify token. keyFor(kid) answers the provider's JWK for that key id, or null (oidc.js, with its cache).
// expect: { issuers (array), audience, nonce, now (ms), maxAgeMs }.
// { ok: true, claims: { sub, email, name } } or { ok: false, reason }.
export async function verifyIdToken(token, keyFor, expect) {
  const no = (reason) => ({ ok: false, reason, claims: null });
  if (typeof token !== "string" || token.length > TOKEN_CHARS) return no("the id token is not a token");
  const parts = token.split(".");
  if (parts.length !== 3 || !parts.every((p) => PART.test(p))) return no("the id token is not three base64url parts");
  const header = partJson(parts[0]);
  if (!header) return no("the id token's header is not a JSON object");
  if (header.alg !== "RS256") return no("the id token is not signed RS256");
  if (typeof header.kid !== "string" || header.kid.length < 1 || header.kid.length > 128) return no("the id token names no key");
  const jwk = await keyFor(header.kid);
  if (!jwk || jwk.kty !== "RSA" || (jwk.alg !== undefined && jwk.alg !== "RS256") || (jwk.use !== undefined && jwk.use !== "sig") || typeof jwk.n !== "string" || typeof jwk.e !== "string") return no("the provider publishes no RS256 key under the id token's key id");
  let verified = false;
  try {
    const key = await crypto.subtle.importKey("jwk", { kty: "RSA", n: jwk.n, e: jwk.e, alg: "RS256", ext: true }, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
    verified = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, unb64u(parts[2]), utf8(parts[0] + "." + parts[1]));
  } catch (e) { verified = false; }
  if (!verified) return no("the id token's signature does not verify");
  const c = partJson(parts[1]);
  if (!c) return no("the id token's claims are not a JSON object");
  if (typeof c.iss !== "string" || !expect.issuers.includes(c.iss)) return no("the id token was not issued by the provider");
  const audOk = typeof c.aud === "string" ? c.aud === expect.audience : Array.isArray(c.aud) && c.aud.includes(expect.audience) && c.azp === expect.audience;
  if (!audOk) return no("the id token is not for this client");
  if (!Number.isFinite(c.exp) || c.exp * 1000 <= expect.now - SKEW_MS) return no("the id token has expired");
  if (!Number.isFinite(c.iat) || c.iat * 1000 > expect.now + SKEW_MS) return no("the id token was issued in the future");
  if (c.iat * 1000 < expect.now - expect.maxAgeMs - SKEW_MS) return no("the id token was issued too long ago");
  if (typeof c.nonce !== "string" || c.nonce !== expect.nonce) return no("the id token is not for this sign-in (its nonce)");
  if (c.email_verified !== true) return no("the provider does not vouch for the account's email");
  if (typeof c.sub !== "string" || !SUB.test(c.sub)) return no("the id token names no account");
  return { ok: true, reason: "", claims: { sub: c.sub, email: typeof c.email === "string" ? c.email : "", name: typeof c.name === "string" ? c.name : "" } };
}
