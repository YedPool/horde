// relays/cloudflare/worker/allowlist.js - who may sign in: anyone with a Google account (the default),
// or, once the founder switches the allowlist on, only the accounts it names.
//
// THE BINDING HORDE_RELAY_SIGNIN_ALLOWLIST is written by the deploy from the relay's settings
// signInAllowlistOn and signInAllowlist (Settings.ps1, SignInAllowlist.ps1), as a Worker secret, so the
// addresses in it are never in a command line or the dashboard's plain vars:
//   absent                                    off: signup is public
//   {"on":false,"emails":[...],"subs":[...]}  off, the list kept for the day it is switched on
//   {"on":true,"emails":[...],"subs":[...]}   only these may sign in: a Google email, compared in lower
//                                             case, or a Google account id (the token's sub)
// IT FAILS CLOSED: a binding that is there but is not exactly that shape lets NOBODY in. A broken list is
// a mistake to be seen at once, not a public relay nobody meant.
//
// It is checked at every sign-in, not only the first: switching it on shuts out an account already made
// as soon as its session ends. Its sessions can be ended sooner: each phone from another's Account
// screen, or all of them by deleting the account (accounts.js).
import { cleanSecret } from "./google-client.js";

// Written in lower case by the deploy (SignInAllowlist.ps1, its twin), so one address has one spelling.
const EMAIL = /^[a-z0-9._%+'-]{1,64}@[a-z0-9.-]{1,253}$/;
const SUB = /^[0-9]{1,255}$/;

function listOf(x, pattern) {
  if (!Array.isArray(x) || x.length > 256) return null;
  const out = new Set();
  for (const v of x) { if (typeof v !== "string" || !pattern.test(v)) return null; out.add(v); }
  return out;
}

// { state: "off" } | { state: "on", emails, subs } | { state: "broken" }.
// A binding that is not clean printable ASCII - a byte order mark in front (2026-10-14), a space around
// it - is broken, never mended: JSON.parse would take the space and quietly read the list (google-client.js).
export function readAllowlist(text) {
  if (text === undefined || text === null) return { state: "off" };
  if (!cleanSecret(text)) return { state: "broken" };
  let o;
  try { o = JSON.parse(text); } catch (e) { return { state: "broken" }; }
  if (!o || typeof o !== "object" || Array.isArray(o) || Object.keys(o).sort().join(",") !== "emails,on,subs" || typeof o.on !== "boolean") return { state: "broken" };
  const emails = listOf(o.emails, EMAIL);
  const subs = listOf(o.subs, SUB);
  if (!emails || !subs) return { state: "broken" };
  return o.on ? { state: "on", emails, subs } : { state: "off" };
}

// May the account a verified id token names sign in?
export function admits(list, claims) {
  if (list.state === "off") return true;
  if (list.state !== "on") return false;
  return list.subs.has(claims.sub) || (typeof claims.email === "string" && list.emails.has(claims.email.toLowerCase()));
}
