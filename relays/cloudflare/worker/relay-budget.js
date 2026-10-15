// relays/cloudflare/worker/relay-budget.js - THE RELAY-WIDE COUNTS: ONE Durable Object for the whole
// relay, holding the day's mailbox requests of every account together and the unacked characters of
// every account together (limits.js, relayRequestsPerDay and relayMaxChars; budget.js, the arithmetic
// and the owners' reserve). Only accounts.js asks it, and only through a lease.
//
// STORAGE:
//   day     { day, used }: the requests leased to accounts this UTC day (budget.js, grantRequests)
//   chars   the characters leased to accounts - what their mailboxes hold, and each one's lease of room
//   pin:<email>  the account id an owner email is pinned to (THE PINS, below)
//
// ONE OBJECT WITH LEASES, NOT SHARDS, NOT PER-ISOLATE BATCHES (the design question of 2026-10-14: a
// single counter called on every request would be a hot spot, and a Durable Object request more on
// each of them). Weighed:
//   - ONE OBJECT ON EVERY REQUEST: exact, but every mailbox request of every account waits on one
//     object, one request at a time, and costs one more Durable Object request (a fourth).
//   - SHARDS - N objects each holding budget/N, an account hashed to one: spreads the load, but splits
//     everything with it. An owner hashed to a shard sees only reserve/N of the reserve; a hot shard
//     refuses its accounts while the others sit on room (an over-count, which is allowed, but a large
//     and arbitrary one); and the characters' cap would split the same way. And it still costs one
//     object request on every request.
//   - PER-ISOLATE BATCHES - each Worker isolate takes a block and spends it: isolates are many, short-
//     lived and not ours to count, so what an evicted isolate held is lost without a trace, and nothing
//     bounds how many hold a block at once.
//   - CHOSEN: ONE OBJECT, LEASED BY ACCOUNTS. The account's own object (accounts.js) is already on
//     every request's path - it is the gate - and it is ONE object an account, with storage that outlives
//     an eviction. So it takes relayRequestLease requests at a time from here and spends them in its
//     gate: this object hears from a busy account once in 50 requests (an account's whole day of
//     20,000 is 400 calls here), the reserve stays whole in one place, and what can go wrong is bounded:
//     an account's unspent lease at midnight, at most 49 requests, counted but not made. Over-count,
//     never under-count: a grant is written here before the account spends any of it.
//   The latency is one call in 50 for requests, and for characters one call each time an account's
//   room of relayCharsLease runs out or is given back.
//
// NOTHING IS EVER DROPPED HERE: a refusal is a grant of nothing, and the caller refuses its request.
import { DurableObject } from "cloudflare:workers";
import { grantRequests, grantChars, requestCapOf } from "./budget.js";

const DAY = "day";
const CHARS = "chars";
const PIN = "pin:";

// THE CALLS IT HAS TAKEN, in memory (an eviction starts them again): what it costs is calls, so a suite
// counts them - read only by the test principal of a local dev (api.js, TEST_BUDGET_PATH), never by a
// deployed relay's caller, and never written to storage.
export class RelayBudget extends DurableObject {
  constructor(ctx, env) { super(ctx, env); this.calls = { takeRequests: 0, takeChars: 0, giveChars: 0 }; }

  async counts() { return { ...this.calls }; }

  // THE PINS (review of PR 281): an owner named by EMAIL is an owner only as the ONE Google account that
  // first matched it - "pin:<email>" holds that account's id - so an address later given to another
  // account (a Workspace address reassigned) does not carry the reserve with it. A pin is dropped only
  // when the email leaves the owners (relayOwnerAccounts): every call here is handed the owner emails of
  // the version that runs, and the pins of any email not among them are deleted first. A deploy asks
  // /status/owners until its own version answers (status.js, Owners.ps1), so the version that names
  // the email no more has made that call before any later deploy can name it again. The ids never
  // leave this object.
  async prune(emails) {
    const keep = new Set(Array.isArray(emails) ? emails : []);
    const storage = this.ctx.storage;
    const gone = [];
    for (const name of (await storage.list({ prefix: PIN })).keys()) if (!keep.has(name.slice(PIN.length))) gone.push(name);
    if (gone.length > 0) await storage.delete(gone);
  }

  // Is account the owner email's own? The first account to ask is pinned to it.
  async pinned(email, account) {
    const storage = this.ctx.storage;
    const held = await storage.get(PIN + email);
    if (held === undefined) { await storage.put(PIN + email, account); return true; }
    return held === account;
  }

  // Is account already pinned to one of emails (the running version's owner emails)? READ ONLY: it pins
  // nothing, prunes nothing and is not one of the calls counted above - the request metrics' summary
  // (metrics-api.js) asks it to tell an owner by email, and metrics never move a budget.
  async pinnedOwner({ account, emails }) {
    if (typeof account !== "string" || !Array.isArray(emails)) return false;
    const storage = this.ctx.storage;
    for (const email of emails) if (typeof email === "string" && (await storage.get(PIN + email)) === account) return true;
    return false;
  }

  // The owners of the running version, and nothing else (status.js): the pins pruned to them.
  async syncOwners({ emails }) { await this.prune(emails); return true; }

  // Lease up to want of today's requests to an account of tier (budget.js): { granted, retryAfterMs }.
  // granted is 0 when the tier's part of the day is spent; retryAfterMs is to midnight UTC. pin, for a
  // public account whose verified email is an owner's ({ email, account }), makes it an owner when the
  // email is pinned to it, or not yet to anyone (THE PINS); emails are the running version's owner emails.
  async takeRequests({ now, want, tier, limits, pin = null, emails = [] }) {
    this.calls.takeRequests++;
    const storage = this.ctx.storage;
    await this.prune(emails);
    const as = pin && typeof pin.email === "string" && typeof pin.account === "string" && (await this.pinned(pin.email, pin.account)) ? "owner" : tier;
    const g = grantRequests(await storage.get(DAY), now, want, requestCapOf(limits, as));
    if (g.granted > 0) await storage.put(DAY, g.state);
    return { granted: g.granted, retryAfterMs: g.retryAfterMs };
  }

  // Lease need characters, and up to extra more as room: { ok, granted }. Refused when need does not fit
  // under relayMaxChars; then nothing is taken.
  async takeChars({ need, extra, limits }) {
    this.calls.takeChars++;
    const storage = this.ctx.storage;
    const g = grantChars(await storage.get(CHARS), need, extra, limits.relayMaxChars);
    if (g.ok) await storage.put(CHARS, g.total);
    return { ok: g.ok, granted: g.granted };
  }

  // An account gives back chars it leased: its mail was read, it expired, or the account was deleted.
  async giveChars({ chars }) {
    this.calls.giveChars++;
    if (!Number.isSafeInteger(chars) || chars <= 0) return true;
    const storage = this.ctx.storage;
    const total = (await storage.get(CHARS)) || 0;
    await storage.put(CHARS, Math.max(0, total - chars));
    return true;
  }
}

export function relayBudgetOf(env) { return env.RELAY_BUDGET.get(env.RELAY_BUDGET.idFromName("relay/budget")); }
