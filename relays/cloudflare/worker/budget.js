// relays/cloudflare/worker/budget.js - THE RELAY-WIDE LIMITS, pure: who is an owner, which part of the
// day's requests an account may draw on, and the arithmetic of the relay-wide counts. No storage, no
// clock of its own: relay-budget.js keeps the counts in one Durable Object, accounts.js draws on them.
// The numbers are limits.js's (relayRequestsPerDay, relayOwnerReserve, relayRequestLease,
// relayMaxChars, relayCharsLease).
//
// THE OWNERS are named at deploy time (relays/cloudflare/Owners.ps1, from the relay's setting
// relayOwnerAccounts) in the binding HORDE_RELAY_OWNER_ACCOUNTS: Google account ids - the id token's
// sub, which an account id carries as "google:<sub>" (accounts.js) - separated by commas. A PLAIN VAR,
// NOT A SECRET: an account id is not a credential. It names an account; it opens nothing - a request is
// an owner's only when Google signed an id token with that sub and the relay made a session of it
// (signin.js), so knowing an owner's id gives no one the reserve. As a var it is shown by the deploy
// and in the dashboard, where it can be checked.
//   absent or empty   NO OWNERS: no reserve is held back, the whole day is shared (tier "everyone");
//                     the deploy warns that this is so (Deploy.ps1)
//   "<sub>,<sub>"     these accounts are owners (tier "owner"); every other is "public"
//   anything else     BROKEN, and it fails closed: no account is an owner, and the reserve is still
//                     held back from everyone - a mistake costs requests, never the plan's limit
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

export const OWNERS_BINDING = "HORDE_RELAY_OWNER_ACCOUNTS";
export const ACCOUNT_PREFIX = "google:";
// Owners.ps1's twin: a Google account id is digits, and a relay has few owners.
const SUB = /^[0-9]{1,255}$/;
export const MAX_OWNERS = 16;

// The relay-wide refusals' words: plain, for whoever reads the answer - a machine's log, a person at the
// API. The phone shows its own words for the code instead (surfaces/pwa, read-banner.js, LIMIT_WORDS),
// and keeps these, cut to 200 characters with its own before them, in its diagnostics: under 140 each.
export const RELAY_DAY_WORDS = "The relay has used its requests for today, for all accounts together. It takes more after midnight UTC; nothing sent is lost.";
export const RELAY_FULL_WORDS = "The relay holds all the unread mail it may, for all accounts together. Nothing more is taken until some is read; nothing held was lost.";

// { state: "none" } | { state: "set", subs } | { state: "broken" } (the header, THE OWNERS).
export function ownersOf(env) {
  const v = env ? env[OWNERS_BINDING] : undefined;
  if (v === undefined || v === null || v === "") return { state: "none" };
  if (typeof v !== "string") return { state: "broken" };
  const parts = v.split(",");
  if (parts.length > MAX_OWNERS || !parts.every((p) => SUB.test(p))) return { state: "broken" };
  return { state: "set", subs: new Set(parts) };
}

// The tier of an account id: "owner", "public", or "everyone" when the relay names no owners.
export function tierOf(owners, account) {
  if (owners.state === "none") return "everyone";
  if (owners.state !== "set" || typeof account !== "string" || !account.startsWith(ACCOUNT_PREFIX)) return "public";
  return owners.subs.has(account.slice(ACCOUNT_PREFIX.length)) ? "owner" : "public";
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
