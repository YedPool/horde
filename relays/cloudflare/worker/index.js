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
// /auth/ IS RESERVED for sign-in (relay PR 8b): Google returns to /auth/google/callback (wrangler.json,
// HORDE_RELAY_GOOGLE_CALLBACK), the redirect address registered with Google. Until then every path under
// it is refused here, so no file of the app can ever be served there and take the address over.
//
// "/" is the site's own index.html (a redirect to app/index.html): the asset store is asked for exact
// paths only (wrangler.json, html_handling none), because its default rewriting would answer
// app/index.html with a redirect to app/, which the app's worker would then cache in place of the page.
import { handleApi, isApiPath } from "./api.js";
import { refuse } from "./answers.js";
import { withStrictHeaders } from "./headers.js";

export { Mailbox } from "./mailbox.js";

async function serveFile(request, env, url) {
  if (request.method !== "GET" && request.method !== "HEAD") return refuse(405, "the app's files are only read");
  if (url.pathname === "/") return env.ASSETS.fetch(new Request(new URL("/index.html", url).href, request));
  return env.ASSETS.fetch(request);
}

const AUTH_ROOT = "/auth/";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const reserved = url.pathname === "/auth" || url.pathname.startsWith(AUTH_ROOT);
    const api = reserved || isApiPath(url.pathname);
    let response;
    try {
      if (reserved) response = refuse(501, "sign-in is not served by this relay yet");
      else response = api ? await handleApi(request, env, url) : await serveFile(request, env, url);
    } catch (e) {
      response = refuse(500, "the relay failed this request");
    }
    return withStrictHeaders(response, api);
  }
};
