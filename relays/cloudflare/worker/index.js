// relays/cloudflare/worker/index.js - the hosted relay: ONE Worker at ONE origin serving both the phone
// app (its static files, built by surfaces/pwa/Site.ps1) and the mailbox API (api.js), so the app talks
// to its relay as its own origin - no second host, no cross-origin requests, no CORS to get wrong, and
// the app's connect-src 'self' is enough.
//
// EVERY ANSWER GOES OUT THROUGH withStrictHeaders (headers.js): the app's files are served by the
// Worker first (wrangler.json, assets.run_worker_first), never straight from the asset store, so no
// answer can leave without them. A failure inside is answered 500 with words of the Worker's own, and
// nothing about the request is logged: the Worker has no console call at all.
//
// /auth/ IS SIGN-IN'S (signin.js): Sign in with Google, whose callback is /auth/google/callback
// (wrangler.json, HORDE_RELAY_GOOGLE_CALLBACK), the redirect address registered with Google. Every path
// under it is the Worker's own - an unknown one is 404 - so no file of the app can ever be served there
// and take the address over. Its answers are never cached, as the API's are not.
//
// "/" is the site's own index.html (a redirect to app/index.html): the asset store is asked for exact
// paths only (wrangler.json, html_handling none), because its default rewriting would answer
// app/index.html with a redirect to app/, which the app's worker would then cache in place of the page.
import { handleApi, isApiPath } from "./api.js";
import { handleAuth, isAuthPath } from "./signin.js";
import { refuse } from "./answers.js";
import { handleStatus, isStatusPath } from "./status.js";
import { withStrictHeaders } from "./headers.js";

export { Mailbox } from "./mailbox.js";
export { Session } from "./sessions.js";
export { Account } from "./accounts.js";
export { MachineKey } from "./machines.js";
export { Address } from "./address.js";
export { RelayBudget } from "./relay-budget.js";

// A write to a file is refused by the asset store itself (405, measured 2026-10-11 against the local
// dev): no check of the method is needed here.
async function serveFile(request, env, url) {
  if (url.pathname === "/") return env.ASSETS.fetch(new Request(new URL("/index.html", url).href, request));
  return env.ASSETS.fetch(request);
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const auth = isAuthPath(url.pathname);
    const status = isStatusPath(url.pathname);
    const api = auth || status || isApiPath(url.pathname);
    let response;
    try {
      if (auth) response = await handleAuth(request, env, url);
      else if (status) response = await handleStatus(request, env, url);
      else response = api ? await handleApi(request, env, url) : await serveFile(request, env, url);
    } catch (e) {
      response = refuse(500, "the relay failed this request");
    }
    return withStrictHeaders(response, api);
  }
};
