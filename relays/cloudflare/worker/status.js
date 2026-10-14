// relays/cloudflare/worker/status.js - WHAT THE RELAY SAYS OF ITSELF TO ANYONE: one read-only answer,
//   GET /status/owners   -> 200 { owners, reserve }   (budget.js, ownersSummary)
// how many owner accounts the deployed relay names and whether it holds a reserve back for them - never
// who they are.
//
// WHY IT ANSWERS WITHOUT A SIGN-IN, the one path under the API's rule of authentication first (api.js)
// that does. The deploy must learn whether the LIVE relay has owners before it deploys a version
// without any (relays/cloudflare/Owners.ps1: a home that never set relayOwnerAccounts must not clear
// the founder's owners), and the deploy - the supervisor's own from the runner's home included - has no
// session and may have no registered machine key. What it learns is a count and a yes or no: nothing an
// account id, an email or a request can be made of, and nothing a caller can change. `horde relay
// status` reads the same.
//
// Not under /v1/ (the API, authenticated) nor /auth/ (sign-in's), and not a path of the app's files
// (the site is app/, surface/, list/ and relay/: surfaces/pwa/Site.ps1), so no file can take it over.
// Its answer is never cached (index.js), so a deploy reads the version that runs now.
import { answer, refuse } from "./answers.js";
import { ownersOf, ownersSummary } from "./budget.js";

export const OWNERS_STATUS_PATH = "/status/owners";

export function isStatusPath(pathname) { return pathname === OWNERS_STATUS_PATH || pathname.startsWith("/status/"); }

export function handleStatus(request, env, url) {
  if (url.pathname !== OWNERS_STATUS_PATH) return refuse(404, "there is no such status");
  if (request.method !== "GET") return refuse(405, "the status is read with GET");
  return answer(200, ownersSummary(ownersOf(env)));
}
