// A FAKE OPENID CONNECT PROVIDER on this machine, for relays/cloudflare/test/test-cloudflare-accounts.ps1:
// Google cannot be contacted by a suite, so the Worker of a local dev is pointed here by the test-only
// binding HORDE_RELAY_TEST_OIDC (worker/oidc.js, THE TEST PROVIDER). It plays Google's part as the
// Worker sees it, and lets the suite make it lie.
//
//   node fake-oidc.mjs <client id> <client secret>
//     prints "PORT <n>" once it listens on 127.0.0.1, and exits when its standard input ends (as
//     dev-host.cjs does: a killed suite leaves nothing serving).
//
//   GET  /authorize   checks the request as Google would (response_type code, this client, scope openid
//                     email profile, S256 PKCE, state and nonce), keeps the code's nonce, challenge and
//                     redirect address, and redirects there with the code and the state
//   POST /token       the code, once, for this client with its secret, the same redirect address and a
//                     verifier whose SHA-256 is the challenge: an id token, RS256, under key "fake-1" -
//                     as the scenario says, which may be a lie
//   GET  /jwks        the public key, with Cache-Control max-age=3600; every fetch counted
//   POST /scenario    JSON: the next tokens' claims and lies - { sub, email, email_verified, aud, iss,
//                     expOffset, iatOffset, nonce, alg, kid, forge } - every one optional
//   GET  /stats       { jwksFetches, tokens, refusals, lastAuthorize }
import { createServer } from "node:http";
import { webcrypto, createHash, randomBytes } from "node:crypto";

const [, , CLIENT_ID, CLIENT_SECRET] = process.argv;
const subtle = webcrypto.subtle;
const params = { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" };
const good = await subtle.generateKey(params, true, ["sign", "verify"]);
const forger = await subtle.generateKey(params, true, ["sign", "verify"]);
const jwk = { ...(await subtle.exportKey("jwk", good.publicKey)), kid: "fake-1", alg: "RS256", use: "sig" };
delete jwk.key_ops; delete jwk.ext;
const b64u = (buf) => Buffer.from(buf).toString("base64url");
const codes = new Map();
const stats = { jwksFetches: 0, tokens: 0, refusals: 0, lastAuthorize: null };
let scenario = {};
let issuer = "";

function send(res, status, body, headers = {}) {
  res.writeHead(status, { "Content-Type": "application/json", ...headers });
  res.end(typeof body === "string" ? body : JSON.stringify(body));
}
function readBody(req) {
  return new Promise((resolve) => { const parts = []; req.on("data", (c) => parts.push(c)); req.on("end", () => resolve(Buffer.concat(parts).toString("utf8"))); });
}
async function idToken(entry) {
  const s = entry.scenario;
  const now = Math.floor(Date.now() / 1000);
  const claims = {
    iss: s.iss !== undefined ? s.iss : issuer, aud: s.aud !== undefined ? s.aud : CLIENT_ID, sub: s.sub !== undefined ? s.sub : "100000000000000000001",
    email: s.email !== undefined ? s.email : "founder@example.test", email_verified: s.email_verified !== undefined ? s.email_verified : true,
    nonce: s.nonce !== undefined ? s.nonce : entry.nonce, iat: now + (s.iatOffset || 0), exp: now + 3600 + (s.expOffset || 0), name: "Test Account"
  };
  const header = { alg: s.alg || "RS256", kid: s.kid || "fake-1", typ: "JWT" };
  const head = b64u(JSON.stringify(header)) + "." + b64u(JSON.stringify(claims));
  if (header.alg === "none") return head + ".";
  const sig = await subtle.sign("RSASSA-PKCS1-v1_5", s.forge ? forger.privateKey : good.privateKey, new TextEncoder().encode(head));
  return head + "." + b64u(sig);
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url, issuer);
  try {
    if (req.method === "GET" && url.pathname === "/authorize") {
      const q = url.searchParams;
      stats.lastAuthorize = Object.fromEntries(q.entries());
      const ok = q.get("response_type") === "code" && q.get("client_id") === CLIENT_ID && q.get("scope") === "openid email profile" &&
        q.get("code_challenge_method") === "S256" && /^[A-Za-z0-9_-]{43}$/.test(q.get("code_challenge") || "") && q.get("state") && q.get("nonce") && q.get("redirect_uri");
      if (!ok) { stats.refusals++; return send(res, 400, { error: "invalid_request" }); }
      const code = b64u(randomBytes(24));
      codes.set(code, { nonce: q.get("nonce"), challenge: q.get("code_challenge"), redirect: q.get("redirect_uri"), scenario: { ...scenario }, used: false });
      const to = new URL(q.get("redirect_uri"));
      to.searchParams.set("code", code);
      to.searchParams.set("state", q.get("state"));
      res.writeHead(302, { Location: to.href });
      return res.end();
    }
    if (req.method === "POST" && url.pathname === "/token") {
      const f = new URLSearchParams(await readBody(req));
      const entry = codes.get(f.get("code") || "");
      const verifier = f.get("code_verifier") || "";
      const ok = entry && !entry.used && f.get("grant_type") === "authorization_code" && f.get("client_id") === CLIENT_ID && f.get("client_secret") === CLIENT_SECRET &&
        f.get("redirect_uri") === entry.redirect && createHash("sha256").update(verifier).digest("base64url") === entry.challenge;
      if (!ok) { stats.refusals++; return send(res, 400, { error: "invalid_grant" }); }
      entry.used = true;
      stats.tokens++;
      return send(res, 200, { access_token: "fake-access", token_type: "Bearer", expires_in: 3599, id_token: await idToken(entry) });
    }
    if (req.method === "GET" && url.pathname === "/jwks") { stats.jwksFetches++; return send(res, 200, { keys: [jwk] }, { "Cache-Control": "public, max-age=3600" }); }
    if (req.method === "POST" && url.pathname === "/scenario") { scenario = JSON.parse((await readBody(req)) || "{}"); return send(res, 200, { ok: true }); }
    if (req.method === "GET" && url.pathname === "/stats") return send(res, 200, stats);
    return send(res, 404, { error: "not_found" });
  } catch (e) { return send(res, 500, { error: String(e && e.message) }); }
});

server.listen(0, "127.0.0.1", () => {
  issuer = "http://127.0.0.1:" + server.address().port;
  process.stdout.write("PORT " + server.address().port + "\n");
});
const quit = () => process.exit(0);
process.stdin.on("end", quit);
process.stdin.on("error", quit);
process.stdin.resume();
