// relays/cloudflare/worker/throttle.js - HOW A RATE OR A DAILY COUNT IS KEPT, pure: no storage, no clock
// of its own. Each object that holds a limit (accounts.js, address.js, machines.js) keeps the state these
// return - in memory for a rate, in its storage for a count that must outlive the object's eviction -
// and hands in the time. Which limit is which number is limits.js's.
//
// WHY DURABLE OBJECT COUNTERS, AND NOT THE WORKERS RATE LIMITING BINDING (the founder's question of
// 2026-10-11). The binding costs no Durable Object request, but:
//   - it counts per Cloudflare location and is eventually consistent ("permissive" by design), so a
//     limit at the edge - the 21st put of a burst of 20 - is not reliably refused;
//   - its period is 10 or 60 seconds only, so pairings an hour, accounts a day per address and
//     requests a day per account cannot be written in it at all, and a second mechanism would be
//     needed beside it anyway;
//   - it has no burst: 60 a minute with 20 at once is not expressible as one limit.
// A Durable Object runs one request at a time, so a count kept in one is exact, of any period, with a
// burst. The cost is kept down by keeping each count IN AN OBJECT THE REQUEST ALREADY CALLS (a machine
// key's object for its refused signatures and nonces) or in ONE gate call a request (accounts.js), and
// an address's object is called only on the rare paths (a sign-in started, an account made, a
// signature refused) - never on an ordinary request.
//
// A BUCKET: { tokens, at }. It holds at most burst tokens, refills at perPeriod tokens every periodMs,
// and a request takes one. So burst requests may come at once, then one every periodMs / perPeriod.
// Absent (undefined) is a full bucket: a device or an address never seen has its whole burst.
// A DAY COUNT: { day, n } - day is the UTC day number (ms / 86400000), n the requests counted in it.
// A new day starts at 0.
export const DAY_MS = 86400000;

export function dayOf(now) { return Math.floor(now / DAY_MS); }

// Take one token at now: { ok, state, retryAfterMs } - state is the bucket to keep (whether or not one
// was taken), retryAfterMs how long until the next token when it was refused (0 when taken).
export function takeToken(state, now, perPeriod, periodMs, burst) {
  const rate = perPeriod / periodMs;
  let tokens = burst;
  if (state && Number.isFinite(state.tokens) && Number.isFinite(state.at)) tokens = Math.min(burst, state.tokens + Math.max(0, now - state.at) * rate);
  if (tokens >= 1) return { ok: true, state: { tokens: tokens - 1, at: now }, retryAfterMs: 0 };
  return { ok: false, state: { tokens, at: now }, retryAfterMs: Math.ceil((1 - tokens) / rate) };
}

// Count one at now against max a UTC day: { ok, state, retryAfterMs } - refused, and not counted, once
// max are already counted today; retryAfterMs is until the next UTC midnight.
export function countInDay(state, now, max) {
  const day = dayOf(now);
  const n = state && state.day === day && Number.isFinite(state.n) ? state.n : 0;
  if (n >= max) return { ok: false, state: { day, n }, retryAfterMs: (day + 1) * DAY_MS - now };
  return { ok: true, state: { day, n: n + 1 }, retryAfterMs: 0 };
}
