// The hosted relay's pure modules, one behaviour at a time, under Node, for
// relays/cloudflare/test/test-cloudflare-accounts.ps1 (part 1): the id token's every check, the machine
// request's header and signed bytes, the cookies, the sign-in allowlist, the site's origin and the
// provider's keys - each refusal provoked on purpose, with keys made here, and no network.
//
//   node units.mjs <repository root>
//
// Prints one line per check, "[PASS] name" or "[FAIL] name: detail", then "[DONE] <failures>".
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [, , repoRoot] = process.argv;
const load = (p) => import(pathToFileURL(join(repoRoot, p)).href);
const P = await load("relay/js/protocol.js");
const J = await load("relays/cloudflare/worker/jwt.js");
const S = await load("relays/cloudflare/worker/request-signature.js");
const C = await load("relays/cloudflare/worker/cookies.js");
const A = await load("relays/cloudflare/worker/allowlist.js");
const O = await load("relays/cloudflare/worker/oidc.js");
const W = await load("relays/cloudflare/worker/site.js");
const subtle = globalThis.crypto.subtle;

let failures = 0;
function check(ok, name, detail = "") {
  if (ok) process.stdout.write("[PASS] " + name + "\n");
  else { failures++; process.stdout.write("[FAIL] " + name + (detail ? ": " + detail : "") + "\n"); }
}

// --- 1. the id token ---
const rsa = () => subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"]);
const good = await rsa();
const forger = await rsa();
const goodJwk = { ...(await subtle.exportKey("jwk", good.publicKey)), kid: "k1", alg: "RS256", use: "sig" };
const keyFor = async (kid) => (kid === "k1" ? goodJwk : null);
const enc = (o) => P.b64u(P.utf8(JSON.stringify(o)));
async function token(claims, { header = { alg: "RS256", kid: "k1", typ: "JWT" }, key = good.privateKey } = {}) {
  const head = enc(header) + "." + enc(claims);
  const sig = new Uint8Array(await subtle.sign("RSASSA-PKCS1-v1_5", key, P.utf8(head)));
  return head + "." + P.b64u(sig);
}
const now = 1760000000000;
const CLIENT = "123-abc.apps.googleusercontent.com";
const base = { iss: "https://accounts.google.com", aud: CLIENT, sub: "1098765432101234567890", email: "founder@example.com", email_verified: true, nonce: "n-1", iat: now / 1000 - 5, exp: now / 1000 + 3600, name: "F" };
const expect = { issuers: O.GOOGLE.issuers, audience: CLIENT, nonce: "n-1", now, maxAgeMs: 600000 };
const v = (t, e = expect) => J.verifyIdToken(t, keyFor, e);
{
  const ok = await v(await token(base));
  check(ok.ok && ok.claims.sub === base.sub && ok.claims.email === base.email, "a token signed by the provider's key, for this client and this sign-in, verifies; the account is its sub", ok.reason);
  check((await v(await token({ ...base, iss: "accounts.google.com" }))).ok, "both spellings of Google's issuer are taken");
  const cases = [
    ["a forged token (signed by another key under the provider's key id)", await token(base, { key: forger.privateKey }), "signature"],
    ["a token naming a key id the provider does not publish", await token(base, { header: { alg: "RS256", kid: "k9" } }), "no RS256 key"],
    ["alg none", enc({ alg: "none", kid: "k1" }) + "." + enc(base) + ".", "three base64url parts"],
    ["alg none with a signature part", enc({ alg: "none", kid: "k1" }) + "." + enc(base) + ".AAAA", "not signed RS256"],
    ["alg HS256", await token(base, { header: { alg: "HS256", kid: "k1" } }), "not signed RS256"],
    ["a wrong audience", await token({ ...base, aud: "456-other.apps.googleusercontent.com" }), "not for this client"],
    ["an audience list naming this client without azp", await token({ ...base, aud: [CLIENT, "x"] }), "not for this client"],
    ["another issuer", await token({ ...base, iss: "https://evil.example" }), "not issued by the provider"],
    ["an expired token", await token({ ...base, exp: now / 1000 - 61 }), "expired"],
    ["a token from the future", await token({ ...base, iat: now / 1000 + 61 }), "future"],
    ["a token issued too long ago, still unexpired", await token({ ...base, iat: now / 1000 - 700 }), "too long ago"],
    ["a wrong nonce", await token({ ...base, nonce: "n-2" }), "nonce"],
    ["no nonce", await token({ ...base, nonce: undefined }), "nonce"],
    ["email_verified false", await token({ ...base, email_verified: false }), "email"],
    ["email_verified as the string true", await token({ ...base, email_verified: "true" }), "email"],
    ["no subject", await token({ ...base, sub: "" }), "names no account"]
  ];
  for (const [what, t, words] of cases) {
    const r = await v(t);
    check(!r.ok && r.reason.indexOf(words) >= 0, what + " is refused (" + r.reason + ")", JSON.stringify(r));
  }
  const tampered = (await token(base)).split(".");
  tampered[1] = enc({ ...base, sub: "1" });
  check(!(await v(tampered.join("."))).ok, "a token whose claims were changed after signing is refused");
  check((await v(await token({ ...base, aud: [CLIENT, "x"], azp: CLIENT }))).ok, "CONTROL: an audience list naming this client, with azp this client, is taken");
  check((await v(await token({ ...base, exp: now / 1000 - 59 }))).ok && (await v(await token({ ...base, iat: now / 1000 + 59 }))).ok, "CONTROL: within the minute's skew either way, a token is taken");
  const long = await v("a".repeat(9000));
  check(!long.ok && long.reason === "the id token is not a token", "a text longer than any id token is refused unread", long.reason);
  const wrongUse = async () => ({ ...goodJwk, use: "enc" });
  check(!(await J.verifyIdToken(await token(base), wrongUse, expect)).ok, "a key the provider publishes for encryption, not signing, is not used");
}

// --- 2. the provider's keys, cached ---
{
  let fetches = 0;
  let clock = now;
  let published = [goodJwk];
  const fakeFetch = async () => { fetches++; return new Response(JSON.stringify({ keys: published }), { status: 200, headers: { "Cache-Control": "public, max-age=3600" } }); };
  const cache = O.keyCache(fakeFetch, () => clock);
  const prov = O.GOOGLE;
  await cache(prov, "k1"); await cache(prov, "k1");
  check(fetches === 1, "the provider's keys are fetched once and then served from the cache", String(fetches));
  await cache(prov, "nope");
  check(fetches === 1, "a key id the cache lacks, a moment after a fetch, does not fetch again", String(fetches));
  clock += 61000;
  await cache(prov, "nope");
  check(fetches === 2, "a minute on, it fetches the keys again (the provider rotated them)", String(fetches));
  await cache(prov, "nope2");
  check(fetches === 2, "but at most once a minute, so made-up key ids cannot make the Worker hammer the provider", String(fetches));
  clock += 3600001;
  published = [{ ...goodJwk, kid: "k2" }];
  check((await cache(prov, "k2")) !== null && fetches === 3, "once max-age has passed the keys are fetched again", String(fetches));
}

// --- 3. the provider: Google, or the test one only where it may be ---
{
  const local = new URL("http://127.0.0.1:8787/auth/google");
  const deployed = new URL("https://relay.example.test/auth/google");
  const t = { HORDE_RELAY_TEST_OIDC: "http://127.0.0.1:4000" };
  check(O.providerOf({}, local) === O.GOOGLE, "with no test binding, the provider is Google");
  check(O.providerOf(t, local).token === "http://127.0.0.1:4000/token", "with the test binding, a request to this machine signs in with the local fake provider");
  check(O.providerOf(t, deployed) === O.GOOGLE, "but a request to a deployed name never does, binding or not");
  check(O.providerOf({ HORDE_RELAY_TEST_OIDC: "https://evil.example" }, local) === O.GOOGLE, "and a test binding that is not plain http to 127.0.0.1 is ignored");
  const s = await O.newSignIn();
  check(s.challenge === P.b64u(await P.sha256(P.utf8(s.verifier))) && s.verifier.length === 43 && s.state !== s.nonce, "a sign-in's PKCE challenge is SHA-256 of its 256-bit verifier; state and nonce are fresh and apart");
  const u = new URL(O.authorizeUrl(O.GOOGLE, { clientId: CLIENT, redirectUri: "https://relay.example.test/auth/google/callback", ...s }));
  const q = u.searchParams;
  check(u.origin + u.pathname === O.GOOGLE.authorize && q.get("response_type") === "code" && q.get("scope") === "openid email profile" && q.get("code_challenge_method") === "S256" && q.get("code_challenge") === s.challenge && q.get("state") === s.state && q.get("nonce") === s.nonce && q.get("client_id") === CLIENT && !q.has("code_verifier"), "the authorization request asks for a code, openid email profile, PKCE S256, with state and nonce - and never carries the verifier");
  let sent = null;
  const ex = await O.exchangeCode(O.GOOGLE, { code: "c", clientId: CLIENT, clientSecret: "sec", redirectUri: "https://r/cb", verifier: "v" }, async (url, init) => { sent = { url, init }; return new Response(JSON.stringify({ id_token: "t" }), { status: 200 }); });
  const form = new URLSearchParams(sent.init.body);
  check(ex.ok && ex.idToken === "t" && sent.url === O.GOOGLE.token && sent.init.method === "POST" && form.get("code_verifier") === "v" && form.get("grant_type") === "authorization_code" && form.get("client_secret") === "sec", "the code is exchanged by POST with its verifier and the client's secret, in the body");
  const refused = await O.exchangeCode(O.GOOGLE, { code: "c", clientId: CLIENT, clientSecret: "sec", redirectUri: "r", verifier: "v" }, async () => new Response("{}", { status: 400 }));
  check(!refused.ok, "a provider that refuses the code is a refusal");
}

// --- 4. a machine's request ---
{
  const keyId = "0123456789abcdef0123456789abcdef";
  const sig = "A".repeat(86);
  const h = "Horde-Machine key=" + keyId + ",time=1760000000000,nonce=" + "f".repeat(32) + ",sig=" + sig;
  const r = S.readMachineAuthorization(h);
  check(r && r.keyId === keyId && r.time === 1760000000000 && r.nonce === "f".repeat(32) && r.sig === sig, "a machine's header is read into its key, time, nonce and signature");
  for (const [what, bad] of [["a bearer token", "Bearer abc"], ["another order", h.replace("key=" + keyId + ",time=1760000000000", "time=1760000000000,key=" + keyId)],
    ["a missing nonce", h.replace(",nonce=" + "f".repeat(32), "")], ["a time with a leading zero", h.replace("time=1", "time=01")], ["upper-case hex", h.replace(keyId, keyId.toUpperCase())],
    ["a short signature", h.slice(0, -1)], ["anything before the scheme", "Bearer x, " + h], ["a space more", h.replace(",time", ", time")]]) {
    check(S.readMachineAuthorization(bad) === null, what + " is not a machine's header");
  }
  const bytes = P.fromUtf8(S.requestSignedBytes({ origin: "https://relay.example.test", method: "POST", target: "/v1/mailboxes/work/phone/items", time: 5, nonce: "n", keyId: "k", hash: "h" }));
  check(bytes === "horde-relay/request/v1\nhttps://relay.example.test\nPOST\n/v1/mailboxes/work/phone/items\n5\nn\nk\nh", "the signed bytes are the domain, the origin, the method, the path, the time, the nonce, the key and the body's hash, one to a line");
  check(await S.bodyHash(new Uint8Array(0)) === "47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU", "an empty body hashes to SHA-256 of nothing");
  check(S.isFresh(now - 60000, now) && S.isFresh(now + 60000, now) && !S.isFresh(now - 60001, now) && !S.isFresh(now + 60001, now), "a request is fresh within a minute either side of the Worker's clock, and stale past it");
}

// --- 5. the cookies ---
{
  const req = (cookie) => new Request("https://relay.example.test/", { headers: cookie === null ? {} : { Cookie: cookie } });
  check(C.readCookie(req("__Host-horde-session=abc_DEF-1"), C.SESSION_COOKIE) === "abc_DEF-1", "the session cookie is read by its __Host- name");
  check(C.readCookie(req("horde-session=abc"), C.SESSION_COOKIE) === null, "a cookie without the __Host- prefix is not the session");
  check(C.readCookie(req("x=1; __Host-horde-session=a; __Host-horde-session=b"), C.SESSION_COOKIE) === null, "a session cookie given twice is no session");
  check(C.readCookie(req("__Host-horde-session=a b"), C.SESSION_COOKIE) === null && C.readCookie(req(null), C.SESSION_COOKIE) === null, "a value we never write, or no Cookie at all, is none");
  check(C.cookieHeader(C.SESSION_COOKIE, "abc", 60) === "__Host-horde-session=abc; Max-Age=60; Path=/; Secure; HttpOnly; SameSite=Lax", "a cookie is set with the prefix's Path=/ and Secure, no Domain, HttpOnly and SameSite=Lax");
  let thrown = false;
  try { C.cookieHeader("horde-session", "abc", 60); } catch (e) { thrown = true; }
  check(thrown, "and the Worker refuses to set one without the prefix");
  check(C.clearedCookieHeader(C.SIGNIN_COOKIE).indexOf("Max-Age=0;") > 0, "a cleared cookie lives 0 seconds");
}

// --- 6. the sign-in allowlist ---
{
  const claims = { sub: "111", email: "Founder@Example.com" };
  check(A.admits(A.readAllowlist(undefined), claims), "with no allowlist, signup is public: any account signs in");
  check(A.admits(A.readAllowlist('{"on":false,"emails":["x@y.z"],"subs":[]}'), claims), "a list that is off lets anyone in");
  const on = A.readAllowlist('{"on":true,"emails":["founder@example.com"],"subs":["222"]}');
  check(A.admits(on, claims), "switched on, a listed email signs in, compared in lower case");
  check(A.admits(on, { sub: "222", email: "" }), "and so does a listed account id");
  check(!A.admits(on, { sub: "333", email: "other@example.com" }), "an account on neither list does not");
  check(!A.admits(A.readAllowlist("{not json"), claims) && !A.admits(A.readAllowlist('{"on":true,"emails":["UP@x.y"],"subs":[]}'), claims) && !A.admits(A.readAllowlist('{"on":"yes","emails":[],"subs":[]}'), claims), "a broken list lets nobody in: it fails closed");
}

// --- 7. the site ---
{
  const env = { HORDE_RELAY_ORIGIN: "https://relay.example.test", HORDE_RELAY_GOOGLE_CALLBACK: "/auth/google/callback" };
  check(W.siteOf(env).callbackUrl === "https://relay.example.test/auth/google/callback", "the callback is the origin and the reserved path wrangler.json names");
  let refused = 0;
  for (const bad of ["http://relay.example.test", "https://relay.example.test/", "https://user@relay.example.test", "javascript:x"]) { try { W.siteOf({ ...env, HORDE_RELAY_ORIGIN: bad }); } catch (e) { refused++; } }
  check(refused === 4, "an origin that is not https (or http to this machine), or carries a path or a user, is refused", String(refused));
  const req = (o) => new Request("https://relay.example.test/v1/x", { method: "POST", headers: o ? { Origin: o } : {} });
  const site = W.siteOf(env);
  check(W.fromSite(req("https://relay.example.test"), site) && !W.fromSite(req("https://evil.example"), site) && !W.fromSite(req(null), site), "a request is from the site only when its Origin is the site's own");
}

process.stdout.write("[DONE] " + failures + "\n");
process.exit(failures === 0 ? 0 : 1);
