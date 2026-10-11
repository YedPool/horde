// relays/cloudflare/worker/site.js - where this Worker is: its one origin and the address Google sends a
// signed-in browser back to, both read from wrangler.json's vars (HORDE_RELAY_ORIGIN and
// HORDE_RELAY_GOOGLE_CALLBACK), the single source the deploy reads too (Wrangler.ps1,
// Get-HordeCloudflareRelayDeployment).
//
// THE ORIGIN IS WHAT EVERYTHING SAME-ORIGIN IS MEASURED AGAINST: the redirect address registered with
// Google, the Origin a signed-in phone's state-changing request must carry (auth.js), and the origin
// each machine signature covers (request-signature.js). It is https, or - for a local dev only, which
// the test launcher points at its own port (Wrangler.ps1, Start-HordeCloudflareRelayDev) - plain http
// to this machine. Anything else fails the Worker's sign-in rather than send a browser somewhere else.
const ORIGIN = /^(https:\/\/[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?|http:\/\/(?:localhost|127\.0\.0\.1))(?::[0-9]{1,5})?$/;
const CALLBACK = /^\/auth\/[a-z0-9/-]{1,64}$/;
export const LOOPBACK = new Set(["127.0.0.1", "localhost", "[::1]"]);

// { origin, callbackPath, callbackUrl }; throws on a config that does not hold one.
export function siteOf(env) {
  const origin = env && env.HORDE_RELAY_ORIGIN;
  const callbackPath = env && env.HORDE_RELAY_GOOGLE_CALLBACK;
  if (typeof origin !== "string" || !ORIGIN.test(origin)) throw new Error("HORDE_RELAY_ORIGIN is not an origin this Worker serves");
  if (typeof callbackPath !== "string" || !CALLBACK.test(callbackPath)) throw new Error("HORDE_RELAY_GOOGLE_CALLBACK is not a path under /auth/");
  return { origin, callbackPath, callbackUrl: origin + callbackPath };
}

// Was this request made to this machine itself? A deployed Worker is never reached under these names.
export function isLoopback(url) { return LOOPBACK.has(url.hostname); }

// Does the request carry the site's own origin in its Origin header? A browser sends Origin on every
// POST and DELETE, and on every WebSocket upgrade, same-origin included; one with no Origin, or another,
// did not come from the app's own page.
export function fromSite(request, site) { return request.headers.get("Origin") === site.origin; }
