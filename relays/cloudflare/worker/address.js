// relays/cloudflare/worker/address.js - ONE CLIENT ADDRESS: a Durable Object per IP address
// (client-address.js), holding the limits that are an address's rather than an account's (limits.js):
// sign-ins started, accounts made, machine signatures refused, and join requests (join.js). It is asked
// only on those rare paths - never on an ordinary request - so a phone or a machine that behaves costs
// it nothing.
//
// STATE: the sign-in and refused-signature rates are buckets in memory (throttle.js): an eviction - the
// object idle for a while - only refills them, which is what the time idle would have done. The rest is
// in storage, because it must outlive an eviction: accounts made in a UTC day, a count kept until the day
// ends; the join-request bucket, an hour's, kept until it would be full again; and a join block (a
// rejected join request's address, join.js), kept until it lifts. ONE ALARM, at the earliest of those
// times, deletes what is past and moves on to the next: an address that did any of these once leaves
// nothing behind.
import { DurableObject } from "cloudflare:workers";
import { takeToken, countInDay, DAY_MS } from "./throttle.js";

const MINUTE_MS = 60000;
const HOUR_MS = 3600000;
const MADE = "made";
const JOINS = "joins";
const JOIN_BLOCK = "joinBlock";

// When each stored entry may be deleted: it then says no more than its absence would.
const UNTIL = {
  [MADE]: (m) => (m.day + 1) * DAY_MS,
  [JOINS]: (b) => b.fullAt,
  [JOIN_BLOCK]: (u) => u
};

export class Address extends DurableObject {
  constructor(ctx, env) { super(ctx, env); this.signIns = undefined; this.refusals = undefined; }

  // The alarm at the earliest of at and the one already set.
  async keepUntil(at) {
    const set = await this.ctx.storage.getAlarm();
    if (set === null || at < set) await this.ctx.storage.setAlarm(at);
  }

  // A sign-in started from here: { ok, retryAfterMs }.
  async signInStart({ now, limits }) {
    const t = takeToken(this.signIns, now, limits.signInStartsPerMinute, MINUTE_MS, limits.signInStartsPerMinute);
    this.signIns = t.state;
    return { ok: t.ok, retryAfterMs: t.retryAfterMs };
  }

  // An account about to be made from here: { ok, retryAfterMs } - counted only when ok.
  async newAccount({ now, limits }) {
    const storage = this.ctx.storage;
    const c = countInDay(await storage.get(MADE), now, limits.newAccountsPerDay);
    if (!c.ok) return { ok: false, retryAfterMs: c.retryAfterMs };
    await storage.put(MADE, c.state);
    await this.keepUntil(UNTIL[MADE](c.state));
    return { ok: true, retryAfterMs: 0 };
  }

  // A machine signature from here was refused: { ok } while this address is under its rate, else
  // { ok: false, retryAfterMs } - the Worker then refuses this address's machine requests at once.
  async refusedSignature({ now, limits }) {
    const r = takeToken(this.refusals, now, limits.refusedSignaturesPerMinutePerAddress, MINUTE_MS, limits.refusedSignaturesPerMinutePerAddress);
    this.refusals = r.state;
    return { ok: r.ok, retryAfterMs: r.retryAfterMs };
  }

  // A join request from here (join.js, checks (a) and (d)): { blocked: true, retryAfterMs } while a
  // rejected request's block holds, and then nothing is taken; else { blocked: false, taken,
  // retryAfterMs } - taken when one of this address's join tokens was spent on it.
  async joinAdmit({ now, limits }) {
    const storage = this.ctx.storage;
    const until = await storage.get(JOIN_BLOCK);
    if (until !== undefined && until > now) return { blocked: true, taken: false, retryAfterMs: until - now };
    const per = limits.joinRequestsPerHourPerAddress;
    const t = takeToken(await storage.get(JOINS), now, per, HOUR_MS, per);
    if (!t.ok) return { blocked: false, taken: false, retryAfterMs: t.retryAfterMs };
    const b = { ...t.state, fullAt: t.state.at + Math.ceil((per - t.state.tokens) * HOUR_MS / per) };
    await storage.put(JOINS, b);
    await this.keepUntil(b.fullAt);
    return { blocked: false, taken: true, retryAfterMs: 0 };
  }

  // The token joinAdmit took, given back: the request it was taken for was refused after it (join.js),
  // and a refused request spends nothing. The take left b.tokens at b.at, so one more at that same time
  // is the bucket as it was before it.
  async joinRefund({ limits }) {
    const storage = this.ctx.storage;
    const b = await storage.get(JOINS);
    if (b === undefined) return false;
    const per = limits.joinRequestsPerHourPerAddress;
    const tokens = Math.min(per, b.tokens + 1);
    await storage.put(JOINS, { tokens, at: b.at, fullAt: b.at + Math.ceil((per - tokens) * HOUR_MS / per) });
    return true;
  }

  // A join request from here was rejected (join.js): no join request is taken from here for joinBlockMs.
  async joinBlock({ now, limits }) {
    const until = now + limits.joinBlockMs;
    await this.ctx.storage.put(JOIN_BLOCK, until);
    await this.keepUntil(until);
    return true;
  }

  async alarm() {
    const storage = this.ctx.storage;
    const now = Date.now();
    let next = Infinity;
    for (const name of Object.keys(UNTIL)) {
      const v = await storage.get(name);
      if (v === undefined) continue;
      const at = UNTIL[name](v);
      if (!(at > now)) await storage.delete(name);
      else next = Math.min(next, at);
    }
    if (next !== Infinity) await storage.setAlarm(next);
  }
}

export function addressOf(env, address) { return env.ADDRESS.get(env.ADDRESS.idFromName("address/" + address)); }
