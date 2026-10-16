// relays/cloudflare/worker/signin.js - SIGN IN WITH GOOGLE, server side: the OAuth 2.0 authorization code
// flow with PKCE (RFC 7636), state and nonce, scopes openid email profile, and the session it ends in.
//
//   GET  /auth/google            start: a fresh state, nonce and PKCE verifier kept in the
//                                __Host-horde-signin cookie for ten minutes, and a redirect to Google
//   GET  /auth/google/callback   (wrangler.json's HORDE_RELAY_GOOGLE_CALLBACK, the address registered
//                                with Google) the code, exchanged and its id token verified, then a
//                                session and its __Host-horde-session cookie, and back to the app
//   POST /auth/signout           the session ended here and its cookie cleared; the site's own Origin only
//   GET  /auth/session           { signedIn, email }, for the app to know which screen to show
//
// THE CALLBACK REFUSES unless every one of these holds, and then makes no session and sets no cookie:
// the browser holds this sign-in's cookie (so the callback is the end of a sign-in THIS browser
// started: no login CSRF), the state Google returns is the cookie's (compared in constant time), the
// sign-in is under ten minutes old, the provider exchanges the code - with the client's secret and the
// PKCE verifier only this Worker and this browser's cookie knew - for an id token that verifies whole
// (jwt.js: signature, issuer, audience, times, the cookie's nonce, a verified email), and the allowlist
// admits the account (allowlist.js). A refusal sends the browser back to the app with #signin-refused,
// and says why in the Horde-Signin-Refused header - the Worker's own words, never the provider's.
//
// The client id and secret are Worker secrets the deploy stores (Deploy.ps1). A Worker without them -
// or with one that is not clean, a byte order mark in front above all (google-client.js) - refuses to
// start a sign-in at all, in words, and so never sends Google a marked id.
//
// THE LIMITS ON SIGNING IN (limits.js), each refused in the same way as a broken sign-in - back to the
// app, with a code word after #signin-refused: (the app says it in its own words) and the
// Horde-Signin-Refused header:
//   - a start from an address past signInStartsPerMinute (address.js)                #signin-refused:busy
//   - a NEW account from an address past newAccountsPerDay (address.js): an account
//     already made signs in from anywhere                                            #signin-refused:new-accounts
//   - an account with phonesPerAccount phones signed in already (accounts.js)        #signin-refused:phones
//   - an account being deleted (accounts.js)                                          #signin-refused:deleting
// The account is made, and the phone taken onto it, by the account's object (accounts.js, signIn),
// which hands back the account's epoch for the session.
import { siteOf, fromSite } from "./site.js";
import { readCookie, cookieHeader, clearedCookieHeader, SESSION_COOKIE, SIGNIN_COOKIE } from "./cookies.js";
import { providerOf, newSignIn, authorizeUrl, exchangeCode, keyCache } from "./oidc.js";
import { verifyIdToken } from "./jwt.js";
import { readAllowlist, admits } from "./allowlist.js";
import { googleClientOf } from "./google-client.js";
import { newSessionId, sessionOf, SESSION_MS } from "./sessions.js";
import { ACCOUNT_PREFIX, accountOf } from "./accounts.js";
import { addressOf } from "./address.js";
import { clientAddressOf } from "./client-address.js";
import { limitsOf } from "./limits.js";
import { answer, refuse, CODES } from "./answers.js";

export const AUTH_ROOT = "/auth/";
const START = "/auth/google";
const SIGNOUT = "/auth/signout";
const SESSION = "/auth/session";
const SIGNIN_MS = 600000;
const NOT_SET_UP = "sign-in is not set up on this relay: deploy it with the Google client";
const APP = "/app/index.html";
const PENDING = /^([A-Za-z0-9_-]{43})\.([A-Za-z0-9_-]{43})\.([A-Za-z0-9_-]{43})\.([0-9]{13})$/;
// The provider's keys, cached for this isolate (oidc.js).
const keys = keyCache();

function sameText(a, b) {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  return x.byteLength === y.byteLength && crypto.subtle.timingSafeEqual(x, y);
}

// The code word after #signin-refused: for each refusal by a limit (the header).
const LIMIT_WORDS = { busy: "busy", newAccounts: "new-accounts", [CODES.phones]: "phones", [CODES.deleting]: "deleting" };

function redirect(location, cookies, extra = {}) {
  const headers = new Headers({ Location: location, ...extra });
  for (const c of cookies) headers.append("Set-Cookie", c);
  return new Response(null, { status: 303, headers });
}

async function start(request, env, url) {
  const site = siteOf(env);
  const client = googleClientOf(env);
  if (!client) return refuse(503, NOT_SET_UP);
  const started = await addressOf(env, clientAddressOf(request, env, url)).signInStart({ now: Date.now(), limits: limitsOf(env, url) });
  if (!started.ok) return redirect(site.origin + APP + "#signin-refused:" + LIMIT_WORDS.busy, [], { "Horde-Signin-Refused": "too many sign-ins were started from this address: wait a minute", "Retry-After": String(Math.max(1, Math.ceil(started.retryAfterMs / 1000))) });
  const s = await newSignIn();
  const pending = s.state + "." + s.nonce + "." + s.verifier + "." + Date.now();
  const location = authorizeUrl(providerOf(env, url), { clientId: client.clientId, redirectUri: site.callbackUrl, state: s.state, nonce: s.nonce, challenge: s.challenge });
  return redirect(location, [cookieHeader(SIGNIN_COOKIE, pending, SIGNIN_MS / 1000)]);
}

async function callback(request, env, url) {
  const site = siteOf(env);
  const refused = (why, word = "") => redirect(site.origin + APP + "#signin-refused" + (word ? ":" + word : ""), [clearedCookieHeader(SIGNIN_COOKIE)], { "Horde-Signin-Refused": why });
  if (url.searchParams.has("error")) return refused("the provider did not sign this account in");
  const m = PENDING.exec(readCookie(request, SIGNIN_COOKIE) || "");
  if (!m) return refused("this browser started no sign-in here");
  const state = url.searchParams.get("state");
  const code = url.searchParams.get("code");
  if (typeof state !== "string" || !sameText(state, m[1])) return refused("the sign-in's state is not this browser's");
  const now = Date.now();
  if (now - Number(m[4]) > SIGNIN_MS || Number(m[4]) > now) return refused("the sign-in took longer than ten minutes");
  if (typeof code !== "string" || code.length < 1 || code.length > 2048) return refused("the provider sent no code");
  const client = googleClientOf(env);
  if (!client) return refused(NOT_SET_UP);
  const provider = providerOf(env, url);
  const ex = await exchangeCode(provider, { code, clientId: client.clientId, clientSecret: client.clientSecret, redirectUri: site.callbackUrl, verifier: m[3] });
  if (!ex.ok) return refused(ex.reason);
  const v = await verifyIdToken(ex.idToken, (kid) => keys(provider, kid), { issuers: provider.issuers, audience: client.clientId, nonce: m[2], now, maxAgeMs: SIGNIN_MS });
  if (!v.ok) return refused(v.reason);
  if (!admits(readAllowlist(env.HORDE_RELAY_SIGNIN_ALLOWLIST), v.claims)) return refused("this account is not on this relay's sign-in allowlist");
  const accountId = ACCOUNT_PREFIX + v.claims.sub;
  const account = accountOf(env, accountId);
  const limits = limitsOf(env, url);
  const st = await account.status();
  if (!st.exists && !st.deleting) {
    const made = await addressOf(env, clientAddressOf(request, env, url)).newAccount({ now, limits });
    if (!made.ok) return refused("too many accounts were made from this address today", LIMIT_WORDS.newAccounts);
  }
  const id = newSessionId();
  const session = sessionOf(env, id);
  const taken = await account.signIn({ account: accountId, email: v.claims.email, phone: { id: session.id.toString(), expiresAt: now + SESSION_MS }, now, limits });
  if (!taken.ok) return refused(taken.reason, LIMIT_WORDS[taken.code]);
  await session.begin({ account: accountId, epoch: taken.epoch, email: v.claims.email, createdAt: now, expiresAt: now + SESSION_MS });
  return redirect(site.origin + APP, [cookieHeader(SESSION_COOKIE, id, SESSION_MS / 1000), clearedCookieHeader(SIGNIN_COOKIE)]);
}

async function signOut(request, env) {
  if (request.method !== "POST") return refuse(405, "sign out with POST");
  if (!fromSite(request, siteOf(env))) return refuse(403, "sign out from the app's own page");
  const session = sessionOf(env, readCookie(request, SESSION_COOKIE));
  if (session) {
    const s = await session.read(Date.now());
    await session.end();
    if (s) await accountOf(env, s.account).signOut(session.id.toString());
  }
  const r = answer(200, { signedIn: false });
  r.headers.append("Set-Cookie", clearedCookieHeader(SESSION_COOKIE));
  return r;
}

async function whoIsSignedIn(request, env) {
  const session = sessionOf(env, readCookie(request, SESSION_COOKIE));
  const s = session ? await session.read(Date.now()) : null;
  return answer(200, s ? { signedIn: true, email: s.email } : { signedIn: false, email: "" });
}

export function isAuthPath(pathname) { return pathname === "/auth" || pathname.startsWith(AUTH_ROOT); }

export async function handleAuth(request, env, url) {
  const p = url.pathname;
  if (p === START || p === siteOf(env).callbackPath || p === SESSION) {
    if (request.method !== "GET") return refuse(405, "that is read with GET");
    if (p === START) return start(request, env, url);
    if (p === SESSION) return whoIsSignedIn(request, env);
    return callback(request, env, url);
  }
  if (p === SIGNOUT) return signOut(request, env);
  return refuse(404, "there is no such sign-in address");
}
