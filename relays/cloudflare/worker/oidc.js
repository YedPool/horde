// relays/cloudflare/worker/oidc.js - the identity provider's side of sign-in: where Google is, how a
// sign-in starts (PKCE, state and nonce), how its code is exchanged for an id token, and Google's
// signing keys, fetched and cached. The flow itself is signin.js's; the token's checks are jwt.js's.
//
// GOOGLE, from its discovery document (https://accounts.google.com/.well-known/openid-configuration,
// read 2026-10-11): the endpoints below, and both spellings of its issuer, which its id tokens use.
// Written here rather than discovered at run time: one fetch fewer per cold start, and a discovery
// document is one more thing a sign-in would have to trust.
//
// THE TEST PROVIDER. A suite cannot contact Google, so test-bindings.json's HORDE_RELAY_TEST_OIDC names a
// local fake one (relays/cloudflare/test/fake-oidc.mjs). It is honoured ONLY as the test authenticator
// is (auth.js): the binding is there - and only the test launcher merges it, the production config may
// never name a HORDE_RELAY_TEST_ binding (Wrangler.ps1) - AND it is plain http to 127.0.0.1 AND the
// request was made to this machine itself, which a deployed Worker never is. Otherwise: Google.
//
// THE KEYS ARE CACHED per provider, in the isolate, for as long as the answer's Cache-Control max-age
// says (Google's is some hours), between 5 minutes and a day. A token naming a key id the cache lacks
// fetches the keys again - Google rotates them - but at most once a minute, so a stream of tokens with
// made-up key ids cannot make this Worker hammer Google. Every fetch has a timeout: a provider that
// does not answer fails one sign-in, not the Worker. And none follows a redirect: a 3xx is not the 200
// asked for, so it is a refusal ("manual"; Workers offer no "error", measured 2026-10-11 against the
// local dev, which threw on it).
import { b64u, randomBytes, sha256, utf8 } from "../../../relay/js/protocol.js";
import { isLoopback } from "./site.js";

export const GOOGLE = Object.freeze({
  issuers: ["https://accounts.google.com", "accounts.google.com"],
  authorize: "https://accounts.google.com/o/oauth2/v2/auth",
  token: "https://oauth2.googleapis.com/token",
  jwks: "https://www.googleapis.com/oauth2/v3/certs"
});
export const SCOPES = "openid email profile";
const TEST_BINDING = "HORDE_RELAY_TEST_OIDC";
const TEST_ISSUER = /^http:\/\/127\.0\.0\.1:[0-9]{1,5}$/;
const FETCH_MS = 10000;
const KEYS_MIN_MS = 300000;
const KEYS_MAX_MS = 86400000;
const REFETCH_GAP_MS = 60000;
const ANSWER_BYTES = 65536;

// The provider this request signs in with (the header): GOOGLE, or the test one.
export function providerOf(env, url) {
  const t = env && env[TEST_BINDING];
  if (typeof t !== "string" || !TEST_ISSUER.test(t) || !isLoopback(url)) return GOOGLE;
  return { issuers: [t], authorize: t + "/authorize", token: t + "/token", jwks: t + "/jwks" };
}

// One sign-in's secrets: state (ties the callback to this browser), nonce (ties the token to this
// sign-in) and the PKCE verifier, with the challenge sent for it (S256, RFC 7636).
export async function newSignIn() {
  const verifier = b64u(randomBytes(32));
  return { state: b64u(randomBytes(32)), nonce: b64u(randomBytes(32)), verifier, challenge: b64u(await sha256(utf8(verifier))) };
}

export function authorizeUrl(provider, { clientId, redirectUri, state, nonce, challenge }) {
  const u = new URL(provider.authorize);
  const q = { response_type: "code", client_id: clientId, redirect_uri: redirectUri, scope: SCOPES, state, nonce, code_challenge: challenge, code_challenge_method: "S256", prompt: "select_account" };
  for (const k of Object.keys(q)) u.searchParams.set(k, q[k]);
  return u.href;
}

async function capped(response) {
  const text = await response.text();
  return text.length > ANSWER_BYTES ? null : text;
}

// The code exchanged for an id token: { ok, idToken } or { ok: false, reason }. The client secret goes
// in the form body, over TLS, to the provider only.
export async function exchangeCode(provider, { code, clientId, clientSecret, redirectUri, verifier }, fetchFn = fetch) {
  const body = new URLSearchParams({ grant_type: "authorization_code", code, client_id: clientId, client_secret: clientSecret, redirect_uri: redirectUri, code_verifier: verifier });
  let r;
  try {
    r = await fetchFn(provider.token, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json" }, body: body.toString(), redirect: "manual", signal: AbortSignal.timeout(FETCH_MS) });
  } catch (e) { return { ok: false, reason: "the provider's token endpoint could not be reached" }; }
  const text = await capped(r);
  if (r.status !== 200 || text === null) return { ok: false, reason: "the provider refused the code (" + r.status + ")" };
  let j;
  try { j = JSON.parse(text); } catch (e) { return { ok: false, reason: "the provider's token answer is not JSON" }; }
  if (!j || typeof j.id_token !== "string") return { ok: false, reason: "the provider's token answer holds no id token" };
  return { ok: true, idToken: j.id_token };
}

function maxAgeOf(response) {
  const m = /max-age=([0-9]{1,9})/.exec(response.headers.get("Cache-Control") || "");
  const ms = m ? Number(m[1]) * 1000 : KEYS_MIN_MS;
  return Math.min(KEYS_MAX_MS, Math.max(KEYS_MIN_MS, ms));
}

// A cache of providers' keys: keyFor(provider, kid) -> the JWK, or null. now and fetchFn are handed in,
// so a test can drive the clock; the Worker makes one cache for its isolate (signin.js).
export function keyCache(fetchFn = fetch, now = () => Date.now()) {
  const held = new Map();
  async function load(provider) {
    const was = held.get(provider.jwks);
    const t = now();
    if (was && t - was.fetchedAt < REFETCH_GAP_MS) return was;
    let keys = null;
    let until = t + KEYS_MIN_MS;
    try {
      const r = await fetchFn(provider.jwks, { headers: { Accept: "application/json" }, redirect: "manual", signal: AbortSignal.timeout(FETCH_MS) });
      const text = r.status === 200 ? await capped(r) : null;
      const j = text === null ? null : JSON.parse(text);
      if (j && Array.isArray(j.keys)) { keys = j.keys.filter((k) => k && typeof k === "object" && typeof k.kid === "string"); until = t + maxAgeOf(r); }
    } catch (e) { keys = null; }
    const next = keys ? { keys, fetchedAt: t, until } : { keys: was ? was.keys : [], fetchedAt: t, until: was ? was.until : t };
    held.set(provider.jwks, next);
    return next;
  }
  return async function keyFor(provider, kid) {
    let c = held.get(provider.jwks);
    if (!c || now() >= c.until) c = await load(provider);
    let k = c.keys.find((x) => x.kid === kid);
    if (!k) { c = await load(provider); k = c.keys.find((x) => x.kid === kid); }
    return k || null;
  };
}
