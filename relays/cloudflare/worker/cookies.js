// relays/cloudflare/worker/cookies.js - the Worker's two cookies, and nothing else it reads from a Cookie
// header.
//
//   __Host-horde-session   a signed-in phone's session: an opaque random id, nothing else (sessions.js
//                          keeps what it stands for, server side, with its expiry)
//   __Host-horde-signin    one sign-in in flight: its state, nonce and PKCE verifier (signin.js), for
//                          ten minutes, cleared by the callback whatever it answers
//
// THE __Host- PREFIX is the browser's promise that the cookie was set by this very origin over https,
// with Path=/ and no Domain: a sibling subdomain of workers.dev cannot set or shadow it. So the Worker
// reads ONLY the prefixed names - a cookie called horde-session, without the prefix, is somebody else's
// and is never looked at - and sets every cookie with exactly the attributes the prefix demands, plus
// HttpOnly (no script of the page ever holds a session id) and SameSite=Lax (a cross-site POST, a
// cross-site frame or fetch, carries no session; a top-level link to the app still signs in).
//
// A NAME GIVEN TWICE IS NO NAME: two values under one name mean someone set a second cookie past the
// browser's rules (or a proxy joined two headers); neither is trusted.
export const SESSION_COOKIE = "__Host-horde-session";
export const SIGNIN_COOKIE = "__Host-horde-signin";
const VALUE = /^[A-Za-z0-9._-]{1,512}$/;

// The value of the cookie called exactly name, or null: absent, given twice, or not a value we write.
export function readCookie(request, name) {
  const header = request.headers.get("Cookie");
  if (typeof header !== "string") return null;
  let found = null;
  for (const part of header.split(";")) {
    const at = part.indexOf("=");
    if (at < 0) continue;
    if (part.slice(0, at).trim() !== name) continue;
    if (found !== null) return null;
    found = part.slice(at + 1).trim();
  }
  return found !== null && VALUE.test(found) ? found : null;
}

// A Set-Cookie value for one of our cookies, living maxAgeSeconds (0 clears it).
export function cookieHeader(name, value, maxAgeSeconds) {
  if (!name.startsWith("__Host-") || !VALUE.test(value) || !Number.isSafeInteger(maxAgeSeconds) || maxAgeSeconds < 0) throw new Error("not a cookie this Worker sets");
  return name + "=" + value + "; Max-Age=" + maxAgeSeconds + "; Path=/; Secure; HttpOnly; SameSite=Lax";
}

export function clearedCookieHeader(name) { return cookieHeader(name, "x", 0); }
