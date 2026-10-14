// relays/cloudflare/worker/budget.js - THE RELAY-WIDE LIMITS, pure: who is an owner, which part of the
// day's requests an account may draw on, and the arithmetic of the relay-wide counts. No storage, no
// clock of its own: relay-budget.js keeps the counts in one Durable Object, accounts.js draws on them.
// The numbers are limits.js's (relayRequestsPerDay, relayOwnerReserve, relayRequestLease,
// relayMaxChars, relayCharsLease).
//
// THE OWNERS are named at deploy time (relays/cloudflare/Owners.ps1, from the relay's setting
// relayOwnerAccounts) in the secret HORDE_RELAY_OWNER_ACCOUNTS, in the allowlist's own shape and rules
// (allowlist.js, reused): {"emails":[...],"subs":[...]} - an email in lower case, or a Google account
// id, the id token's sub, which an account id carries as "google:<sub>" (accounts.js). A SECRET, as the
// allowlist is: the emails are a person's.
// AN OWNER BY EMAIL IS MATCHED ONLY WITH THE ACCOUNT'S VERIFIED EMAIL: the one its own object keeps
// from its last sign-in (accounts.js, the profile), taken from an id token whose email Google vouches
// for (jwt.js refuses one it does not) - never anything a request carries. An account with no email
// matches no owner email. The email is the way to name an owner a person can read (the phone's Account
// screen shows it); the sub is nowhere a person sees it.
//   absent, or both lists empty   NO OWNERS: no reserve is held back, the whole day is shared (tier
//                                 "everyone"); the deploy warns that this is so (Owners.ps1)
//   owners named                  those accounts are owners (tier "owner"); every other is "public"
//   anything else                 BROKEN, and it fails closed: no account is an owner, and the reserve is
//                                 still held back from everyone - a mistake costs requests, never the
//                                 plan's limit
// What anyone may know of them is how many, never who (ownersSummary: status.js, the Account screen).
//
// THE TIERS. A public account may draw while the day's count is under relayRequestsPerDay -
// relayOwnerReserve; an owner, and everyone when there are no owners, while it is under
// relayRequestsPerDay. ONE COUNT, TWO LINES: an owner's requests before the shared part ran out were
// counted in it like anyone's, and the reserve is only the last stretch, which public accounts never
// reach.
//
// THE LEASE (relay-budget.js says why one object and not shards). An account does not ask the relay-wide
// count on every request: it takes relayRequestLease at a time and spends them itself (accounts.js,
// admit), so the relay-wide object hears from a busy account once in fifty requests. A lease is
// granted whole or in part - the last of the day goes to whoever asks - and what an account has not
// spent by midnight UTC is lost: counted, never used. So the count can only run AHEAD of the requests
// made (refusing a little early), never behind them (letting the plan's limit be passed).
// Characters are leased the same way (grantChars): an account holds up to relayCharsLease beyond what
// its mailboxes use, and gives the rest back as its mail is read (accounts.js, credit).
import { DAY_MS, dayOf } from "./throttle.js";
import { EMAIL, SUB, listOf } from "./allowlist.js";

export const OWNERS_BINDING = "HORDE_RELAY_OWNER_ACCOUNTS";
export const ACCOUNT_PREFIX = "google:";
// Owners.ps1's twin: a relay has few owners.
export const MAX_OWNERS = 16;

// The relay-wide refusals' words: plain, for whoever reads the answer - a machine's log, a person at the
// API. The phone shows its own words for the code instead (surfaces/pwa, read-banner.js, LIMIT_WORDS),
// and keeps these, cut to 200 characters with its own before them, in its diagnostics: under 140 each.
export const RELAY_DAY_WORDS = "The relay has used its requests for today, for all accounts together. It takes more after midnight UTC; nothing sent is lost.";
export const RELAY_FULL_WORDS = "The relay holds all the unread mail it may, for all accounts together. Nothing more is taken until some is read; nothing held was lost.";

// { state: "none" } | { state: "set", emails, subs } | { state: "broken" } (the header, THE OWNERS).
// emails and subs are arrays, so the value crosses to the account's object as it is.
export function ownersOf(env) {
  const v = env ? env[OWNERS_BINDING] : undefined;
  if (v === undefined || v === null || v === "") return { state: "none" };
  if (typeof v !== "string") return { state: "broken" };
  let o;
  try { o = JSON.parse(v); } catch (e) { return { state: "broken" }; }
  if (!o || typeof o !== "object" || Array.isArray(o) || Object.keys(o).sort().join(",") !== "emails,subs") return { state: "broken" };
  const emails = listOf(o.emails, EMAIL);
  const subs = listOf(o.subs, SUB);
  if (!emails || !subs || emails.size + subs.size > MAX_OWNERS) return { state: "broken" };
  if (emails.size + subs.size === 0) return { state: "none" };
  return { state: "set", emails: [...emails], subs: [...subs] };
}

// What anyone may know of the owners: how many, and whether a reserve is held back - NEVER WHO
// (status.js, the Account screen's view). { owners, reserve }: none named, { 0, false } - the whole day
// shared; named, { n, true }; broken, { 0, true } - nobody may use the reserve, and it is held back.
export function ownersSummary(owners) {
  if (owners.state === "set") return { owners: owners.emails.length + owners.subs.length, reserve: true };
  return { owners: 0, reserve: owners.state !== "none" };
}

// The tier of an account: "owner", "public", or "everyone" when the relay names no owners. account is
// its id; email the VERIFIED email its own object keeps from its last sign-in (the header), or "". No
// owners value at all is public: a caller that forgot them gets the smaller part, never the reserve.
export function tierOf(owners, account, email = "") {
  if (!owners) return "public";
  if (owners.state === "none") return "everyone";
  if (owners.state !== "set") return "public";
  if (typeof account === "string" && account.startsWith(ACCOUNT_PREFIX) && owners.subs.includes(account.slice(ACCOUNT_PREFIX.length))) return "owner";
  if (typeof email === "string" && email !== "" && owners.emails.includes(email.toLowerCase())) return "owner";
  return "public";
}

// How far into the day's count a tier may draw. Anything but owner and everyone is public: a tier
// that is missing or misspelled gets the smaller share.
export function requestCapOf(limits, tier) {
  if (tier === "owner" || tier === "everyone") return limits.relayRequestsPerDay;
  return limits.relayRequestsPerDay - limits.relayOwnerReserve;
}

// Grant up to want requests at now against cap: { granted, state, retryAfterMs }. state { day, used } is
// the count to keep (a new UTC day starts at 0); retryAfterMs is to the next UTC midnight, for a refusal.
export function grantRequests(state, now, want, cap) {
  const day = dayOf(now);
  const used = state && state.day === day && Number.isSafeInteger(state.used) ? state.used : 0;
  const granted = Math.max(0, Math.min(want, cap - used));
  return { granted, state: { day, used: used + granted }, retryAfterMs: (day + 1) * DAY_MS - now };
}

// Grant need characters, and up to extra more as a lease, against max with total already held:
// { ok, granted, total }. Refused, and nothing taken, when need itself does not fit.
export function grantChars(total, need, extra, max) {
  const held = Number.isSafeInteger(total) && total > 0 ? total : 0;
  if (held + need > max) return { ok: false, granted: 0, total: held };
  const granted = need + Math.max(0, Math.min(extra, max - held - need));
  return { ok: true, granted, total: held + granted };
}

// What an account gives back after its use fell to usage while holding granted: all it holds past one
// lease of room (the header, THE LEASE). 0 when it holds no more than that.
export function charsToRelease(granted, usage, lease) {
  return Math.max(0, granted - usage - lease);
}
