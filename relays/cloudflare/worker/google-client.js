// relays/cloudflare/worker/google-client.js - the Google client this Worker signs in with: the Worker
// secrets GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET, which the deploy stores (Deploy.ps1).
//
// A VALUE THAT IS NOT CLEAN IS NOT SET UP. Each is printable ASCII with nothing around it, as the deploy
// checks before it stores one (Test-HordeCloudflareRelaySecretValue, its twin). One that begins with a
// byte order mark (U+FEFF), holds any other character, or begins or ends with a space is taken as not
// there at all - sign-in answers "not set up" - and is never stripped: measured 2026-10-14, secrets
// stored with EF BB BF in front sent Google a marked client id, and Google answered invalid_client to
// every new sign-in. Refusing here means a marked id never reaches Google, and the deploy's own check
// (GET /auth/google) sees the refusal at once.
const PRINTABLE = /^[\x21-\x7E](?:[\x20-\x7E]*[\x21-\x7E])?$/;

// Is this a clean secret value: a non-empty string of printable ASCII, no space at either end?
export function cleanSecret(v) { return typeof v === "string" && PRINTABLE.test(v); }

// { clientId, clientSecret }, or null when either is absent or not clean.
export function googleClientOf(env) {
  const id = env && env.GOOGLE_CLIENT_ID;
  const secret = env && env.GOOGLE_CLIENT_SECRET;
  if (!cleanSecret(id) || !cleanSecret(secret)) return null;
  return { clientId: id, clientSecret: secret };
}
