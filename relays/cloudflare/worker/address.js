// relays/cloudflare/worker/address.js - ONE CLIENT ADDRESS: a Durable Object per IP address
// (client-address.js), holding the limits that are an address's rather than an account's (limits.js):
// sign-ins started, accounts made, and machine signatures refused. It is asked only on those rare paths -
// never on an ordinary request - so a phone or a machine that behaves costs it nothing.
//
// STATE: the sign-in and refused-signature rates are buckets in memory (throttle.js): an eviction - the
// object idle for a while - only refills them, which is what the time idle would have done. Accounts
// made in a UTC day are a count in storage, kept until the day ends, when an alarm deletes it: an
// address that made accounts once leaves nothing behind.
import { DurableObject } from "cloudflare:workers";
import { takeToken, countInDay, dayOf, DAY_MS } from "./throttle.js";

const MINUTE_MS = 60000;
const MADE = "made";

export class Address extends DurableObject {
  constructor(ctx, env) { super(ctx, env); this.signIns = undefined; this.refusals = undefined; }

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
    await storage.setAlarm((dayOf(now) + 1) * DAY_MS);
    return { ok: true, retryAfterMs: 0 };
  }

  // A machine signature from here was refused: { ok } while this address is under its rate, else
  // { ok: false, retryAfterMs } - the Worker then refuses this address's machine requests at once.
  async refusedSignature({ now, limits }) {
    const r = takeToken(this.refusals, now, limits.refusedSignaturesPerMinutePerAddress, MINUTE_MS, limits.refusedSignaturesPerMinutePerAddress);
    this.refusals = r.state;
    return { ok: r.ok, retryAfterMs: r.retryAfterMs };
  }

  async alarm() { await this.ctx.storage.deleteAll(); }
}

export function addressOf(env, address) { return env.ADDRESS.get(env.ADDRESS.idFromName("address/" + address)); }
