// relays/cloudflare/worker/auth.js - THE AUTH SEAM: who may use the mailbox API, and for what. DENY BY
// DEFAULT: a request no authenticator vouches for is refused before its route is even looked at.
//
// WHY A SEAM AND NOT SIGN-IN. Sign-in is the next pull request (relay PR 8b): a phone signs in with
// Google and holds a session; a machine signs each request with the key it registered. Until then the
// hosted relay must already be safe to deploy, so it answers no one - the relay is untrusted for what it
// holds, but an open relay would still be anyone's free storage and anyone's way to fill a mailbox.
//
// THE INTERFACE 8b FILLS. An authenticator is a function (request, env, url) that answers:
//   null                     - this request is not one of mine (no session cookie, no signature)
//   { name, may(op, mailbox) } - who it is, and what it may do: op is get, put, watch or ack
// AUTHENTICATORS is tried in order and the first that vouches decides; authorize() then asks its may().
// 8b appends a Google-session authenticator and a machine-signature authenticator here, and nothing
// else in the Worker changes. 8c's rate limits and mailbox caps go after authorize(), in api.js.
//
// THE TEST AUTHENTICATOR, the only one in 8a, lets test/test-relay-conformance.ps1 drive a local
// `wrangler dev` of this very Worker. It vouches only when ALL of these hold:
//   - the binding HORDE_RELAY_TEST_AUTH is present and at least 32 characters. It is defined only in
//     test-bindings.json, which only the test launcher merges in (relays/cloudflare/Wrangler.ps1), and
//     there it holds a placeholder too short to count: the launcher writes a fresh random token over it
//     for each run. wrangler.json, the production config, has no such binding, and the deploy refuses a
//     config that does (relays/cloudflare/Deploy.ps1); test-cloudflare-worker.ps1 checks both;
//   - the request was made to this machine itself (127.0.0.1, localhost or [::1]) - a deployed Worker is
//     never reached under those names, so even a deploy that carried the binding would vouch for no one;
//   - it carries "Authorization: Bearer <that token>", compared in constant time.
const TEST_BINDING = "HORDE_RELAY_TEST_AUTH";
const TEST_TOKEN_MIN = 32;
const LOOPBACK = new Set(["127.0.0.1", "localhost", "[::1]"]);

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
  if (!LOOPBACK.has(url.hostname)) return null;
  const given = request.headers.get("Authorization");
  if (typeof given !== "string" || !sameText(given, "Bearer " + token)) return null;
  return { name: "test", may: () => true };
}

export const AUTHENTICATORS = [testAuthenticator];

// Who the request is, or null: nobody vouched.
export async function authenticate(request, env, url) {
  for (const vouch of AUTHENTICATORS) {
    const who = await vouch(request, env, url);
    if (who) return who;
  }
  return null;
}

// May who do op on mailbox? Only what its own authenticator allows.
export function authorize(who, op, mailbox) {
  return Boolean(who) && typeof who.may === "function" && who.may(op, mailbox) === true;
}
