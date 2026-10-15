// relays/cloudflare/worker/accounts.js - one account: a Durable Object per account id, holding what is the
// account's as a whole - that it exists, its machines and phones, its mailboxes' names, and every limit
// that counts across them (limits.js) - and the GATE every request of its phones and machines passes.
//
// AN ACCOUNT ID is "google:" and the id token's sub (jwt.js): the provider's own id for the person,
// never the email. The account is MADE at its first sign-in (signIn) with a fresh random EPOCH, and
// ENDS when it is deleted; signed in again later, it is a new account with a new epoch. The epoch is in
// every session and machine registration made for it (sessions.js, machines.js) and names its
// mailboxes (mailbox.js, mailboxOf), so nothing of a deleted account - a session, a key, a mailbox -
// is ever the new one's.
//
// STORAGE:
//   profile        { account, email, createdAt, epoch }; absent: no account (never made, or deleted)
//   m:<key id>     a machine registered to it: { keyId, horde, label, registeredAt }
//   p:<phone id>   a phone signed in: { id, signedInAt, expiresAt }; the id is its session object's
//                  (sessions.js). An entry past its expiresAt is gone with its session, and is pruned
//   b:<mailbox>    a mailbox holding unacked mail, and the characters of it: so the account's caps
//                  on mailboxes and characters are counted here, and deleting the account finds every
//                  mailbox with something to wipe (one emptied by its acks or retention is dropped)
//   usage          the characters of unacked mail across all its mailboxes
//   day            { day, n, lease }: its requests this UTC day (throttle.js), and how many of the
//                  relay-wide day's it holds and has not spent (relay-budget.js, the lease)
//   granted        the characters it holds of the relay-wide cap (relay-budget.js): its usage and up
//                  to relayCharsLease of room
//   room           the relayCharsLease its last put was held to: what an ack or an expiry, which carry
//                  no limits, keeps of the room when it gives the rest back
//   pairing        its pairing bucket (throttle.js)
//   s:<key id>     when that machine was last heard from (presence.js): written at most once per 30 s
//   deleting       { account, epoch }: a deletion under way (remove, alarm)
// IN MEMORY: each device's put and read buckets. An eviction only refills them, as the idle time
// would have. And each machine's last heard time, exact; storage's s: is at most 30 s behind it.
//
// THE LISTS ARE INDEXES, the keys' and sessions' own objects are the truth: a request is decided by
// them (auth.js), so a list that missed one could only fail to show it, never let it in. The API claims
// a key before listing it, and releases it before unlisting it.
//
// THE GATE (admit), one call a request after its principal is known (api.js, account-api.js):
//   - the account must exist under the principal's epoch: a request of a deleted account's device that
//     was already past its session or key when the account went is refused, 401 account-gone;
//   - the device's bucket: puts, or everything else (limits.js) - but never the account's deletion,
//     which only needs the account to be there;
//   - the account's requests this UTC day - the mailbox operations only: its own Account screen, its
//     phones and machines are still its to manage, and its deletion still its to make, over the day;
//   - and THE RELAY'S DAY, every account's together (budget.js): the same mailbox operations, each
//     spent from the lease this account holds of it, a new lease taken from the relay-wide object
//     (relay-budget.js) when it is spent. Refused, 429 relay-daily-limit, when the account's tier
//     (an owner, or not: budget.js, THE TIERS) has nothing left today. A request refused there is not
//     counted against the account's own day either;
//   - and, first of all once the account is known to be there, A MACHINE IS HEARD (presence.js): its
//     signature was verified before the gate was asked, so this is where its lastSeenAt is kept;
// A PUT IS CHARGED, and an ack or an expiry credited, by the mailbox itself (mailbox.js, charge and
// credit), which knows the text's length: the account refuses a put that would make one mailbox too
// many (accountMaxMailboxes, 409 mailboxes-cap) or take its unacked characters past accountMaxChars
// (507 account-full) - refused, never by dropping anything already held. And past the RELAY'S cap on
// characters, every account's together (relayMaxChars, 507 relay-full): the account holds a lease of
// it (granted), and asks the relay-wide object for more only when a put would pass what it holds.
// WHY ONE CALL A REQUEST. An account's day is counted across all its phones and machines, so it is
// counted in one place, exactly, and that place is this object. It costs one Durable Object request on
// each relay request (three in all with the principal's and the mailbox's; reckoned 2026-10-11 against
// the free plan's 100,000 a day). Spreading the count over the principals' objects (each taking a
// lease of the day's count from here now and then) would save most of those calls, but a lease one
// device holds is a request another cannot make, so near the cap a machine would be refused while a
// phone sat on unused requests; and the deletion fence and the mailbox index would then need calls
// of their own anyway. A put costs one more (the mailbox charging the account), and so does an ack or
// an expiry that frees mail (its credit): the account-wide caps are counted where the lengths are known.
// THE RELAY'S DAY costs one call more in relayRequestLease (50) requests, and the relay's cap on
// characters one when an account's room runs out or is given back (relay-budget.js, why a lease).
// THE ROWS IT WRITES, beside those requests (reckoned 2026-10-14, for the PC offline banner): the day's
// count is one row written on each mailbox request, and a machine's last heard time (presence.js) one
// more on each of its requests at least 30 s after the last written. An idle runner asks once a minute:
// about 1,440 day rows and about 1,400 presence rows a day per machine, about 2,800 in all; for 10
// machines, the most an account may have, about 28,000 a day, and a busy machine's presence rows are
// held to 2,880 a day. Against what plan limit on rows written: UNVERIFIED - no figure for Durable
// Object storage writes is recorded in this repository; check Cloudflare's current limits before relying
// on the free plan for many machines.
//
// DELETION (remove) happens AT ONCE for everything that can reach the account: the profile goes first
// (from that moment the gate refuses every request), then every phone's session is ended and every
// machine's key released. Its mailboxes - any number - are then wiped by the object's own alarm, a few
// each run, back to back, so no request does an unbounded amount of work; each wiped mailbox refuses a
// put still in flight (mailbox.js, wipe). When the last is wiped the object deletes everything, and the
// account id may sign up again, as a new account.
import { DurableObject } from "cloudflare:workers";
import { takeToken, countInDay } from "./throttle.js";
import { CODES } from "./answers.js";
import { machineKeyOf } from "./machines.js";
import { mailboxOf } from "./mailbox.js";
import { sessionByObjectId } from "./sessions.js";
import { noteSeen, lastSeenOf } from "./presence.js";
import { charsToRelease, tierOf, ownerEmailOf, ownerEmailsOf, ACCOUNT_PREFIX, RELAY_DAY_WORDS, RELAY_FULL_WORDS } from "./budget.js";
import { relayBudgetOf } from "./relay-budget.js";
import { b64u, randomBytes } from "../../../relay/js/protocol.js";

const PROFILE = "profile";
const MACHINE = "m:";
const PHONE = "p:";
const BOX = "b:";
const DAY = "day";
const PAIRING = "pairing";
const DELETING = "deleting";
const USAGE = "usage";
const SEEN = "s:";
const GRANTED = "granted";
const ROOM = "room";
// A machine's device, as auth.js names it: "machine:" and its key id. Only a verified signature makes one.
const MACHINE_DEVICE = "machine:";
const MINUTE_MS = 60000;
const HOUR_MS = 3600000;
// Mailboxes wiped in one alarm run: few enough that one run's calls stay well inside a Worker's
// subrequest budget, whatever the number of mailboxes.
const WIPE_BATCH = 20;
// The mailbox operations: the ones counted against requestsPerDay (THE GATE).
const MAILBOX_OPS = new Set(["get", "put", "watch", "ack"]);

const gone = () => ({ ok: false, status: 401, code: CODES.gone, reason: "this account was deleted" });

export class Account extends DurableObject {
  constructor(ctx, env) { super(ctx, env); this.devices = new Map(); this.seen = new Map(); }

  // A machine of this account was heard at now (presence.js): kept in memory, written when due. After
  // an eviction the stored time is read once, so a write never moves it back.
  async heard(keyId, now) {
    const held = this.seen.get(keyId);
    const n = noteSeen(held, now, held ? undefined : await this.ctx.storage.get(SEEN + keyId));
    this.seen.set(keyId, n.held);
    if (n.write) await this.ctx.storage.put(SEEN + keyId, n.held.at);
  }

  // Is there an account? { exists, deleting }.
  async status() {
    return { exists: (await this.ctx.storage.get(PROFILE)) !== undefined, deleting: (await this.ctx.storage.get(DELETING)) !== undefined };
  }

  // The live phones' entries, the expired ones deleted.
  async livePhones(now) {
    const storage = this.ctx.storage;
    const out = [];
    for (const [name, p] of await storage.list({ prefix: PHONE })) {
      if (p.expiresAt <= now) await storage.delete(name);
      else out.push(p);
    }
    return out;
  }

  // A phone signs in: the account made if it is not, and the phone taken onto it. { ok, epoch, created }
  // or a refusal { ok: false, status, code, reason } - the account is being deleted, or it has its most
  // phones signed in.
  async signIn({ account, email, phone, now, limits }) {
    const storage = this.ctx.storage;
    if ((await storage.get(DELETING)) !== undefined) return { ok: false, status: 409, code: CODES.deleting, reason: "this account is being deleted; sign in again in a minute, as a new account" };
    let p = await storage.get(PROFILE);
    const created = p === undefined;
    p = created ? { account, email, createdAt: now, epoch: b64u(randomBytes(16)) } : { ...p, email };
    const live = await this.livePhones(now);
    if (live.length >= limits.phonesPerAccount && !live.some((x) => x.id === phone.id)) return { ok: false, status: 409, code: CODES.phones, reason: "this account has " + live.length + " phones signed in, its most: sign one out on the Account screen first" };
    await storage.put({ [PROFILE]: p, [PHONE + phone.id]: { id: phone.id, signedInAt: now, expiresAt: phone.expiresAt } });
    return { ok: true, epoch: p.epoch, created };
  }

  // A phone signed out (signin.js): off the list.
  async signOut(phoneId) { await this.ctx.storage.delete(PHONE + phoneId); return true; }

  // THE GATE (the header): { ok } or a refusal { ok: false, status, code, reason, retryAfterMs }.
  async admit({ device, epoch, op, mailbox, now, limits, owners }) {
    const storage = this.ctx.storage;
    const p = await storage.get(PROFILE);
    if (!p || p.epoch !== epoch) return gone();
    if (device.startsWith(MACHINE_DEVICE)) await this.heard(device.slice(MACHINE_DEVICE.length), now);
    if (op === "delete") return { ok: true };
    const put = op === "put";
    const held = this.devices.get(device) || {};
    const t = put ? takeToken(held.put, now, limits.putsPerMinute, MINUTE_MS, limits.putBurst) : takeToken(held.read, now, limits.readsPerMinute, MINUTE_MS, limits.readBurst);
    this.devices.set(device, put ? { ...held, put: t.state } : { ...held, read: t.state });
    if (!t.ok) return { ok: false, status: 429, code: CODES.rate, reason: "this " + (device.startsWith("phone:") ? "phone" : "machine") + " made more " + (put ? "puts" : "requests") + " than the relay takes in a minute: wait", retryAfterMs: t.retryAfterMs };
    if (MAILBOX_OPS.has(op)) {
      const dailyRefusal = (c) => ({ ok: false, status: 429, code: CODES.daily, reason: "this account made " + limits.requestsPerDay + " requests today, its most for a day: the count starts again at midnight UTC", retryAfterMs: c.retryAfterMs });
      const leaseOf = (held, day) => (held && held.day === day && Number.isSafeInteger(held.lease) ? held.lease : 0);
      let held = await storage.get(DAY);
      let c = countInDay(held, now, limits.requestsPerDay);
      if (!c.ok) return dailyRefusal(c);
      // THE RELAY'S DAY (the header): a lease of today's, or a new one.
      let lease = leaseOf(held, c.state.day);
      if (lease < 1) {
        // The tier by id; an owner email is asked of its pin in the same call (budget.js, THE PINS).
        const tier = tierOf(owners, p.account);
        const email = tier === "public" ? ownerEmailOf(owners, p.email) : "";
        const g = await relayBudgetOf(this.env).takeRequests({ now, want: limits.relayRequestLease, tier, limits, pin: email ? { email, account: p.account } : null, emails: ownerEmailsOf(owners) });
        if (!(g.granted >= 1)) return { ok: false, status: 429, code: CODES.relayDaily, reason: RELAY_DAY_WORDS, retryAfterMs: g.retryAfterMs };
        // THE GAP (review of PR 281): while the relay-wide object was asked, this object's input gate was
        // open, and another request of this account may have counted itself in the day or taken a lease.
        // So the day is READ AGAIN and this request counted on what is there now, the lease granted added
        // to what is there - never written from the value read before the call, which would lose the
        // other's count. Chosen over blockConcurrencyWhile, which would hold every request of the account
        // behind a call to another object. A request the day now refuses keeps its lease for the next.
        held = await storage.get(DAY);
        c = countInDay(held, now, limits.requestsPerDay);
        lease = leaseOf(held, c.state.day) + g.granted;
        if (!c.ok) { await storage.put(DAY, { ...c.state, lease }); return dailyRefusal(c); }
      }
      await storage.put(DAY, { ...c.state, lease: lease - 1 });
    }
    return { ok: true };
  }

  // A put of chars characters into mailbox (mailbox.js): { ok } or a refusal - the account is gone, it
  // would hold one mailbox too many, or too many characters. Counted only when ok.
  async charge({ mailbox, chars, epoch, limits }) {
    const storage = this.ctx.storage;
    for (let round = 0; ; round++) {
      const p = await storage.get(PROFILE);
      if (p === undefined || epoch !== p.epoch) return gone();
      const held = await storage.get(BOX + mailbox);
      if (held === undefined) {
        const n = (await storage.list({ prefix: BOX })).size;
        if (n >= limits.accountMaxMailboxes) return { ok: false, status: 409, code: CODES.mailboxes, reason: "this account has " + n + " mailboxes holding unacked mail, its most: nothing goes into another until one is read and acked" };
      }
      const usage = (await storage.get(USAGE)) || 0;
      if (usage + chars > limits.accountMaxChars) return { ok: false, status: 507, code: CODES.accountFull, reason: "this account's mailboxes hold " + usage + " characters their readers have not acked; this text would take them past their most, " + limits.accountMaxChars };
      // THE RELAY'S CAP (the header): more of it leased only when this put passes what the account holds.
      // An account from before the cap holds none for the mail it already has: that is leased with its
      // next put, whole.
      const granted = (await storage.get(GRANTED)) || 0;
      if (usage + chars <= granted) {
        await storage.put({ [BOX + mailbox]: (held || 0) + chars, [USAGE]: usage + chars, [ROOM]: limits.relayCharsLease });
        return { ok: true };
      }
      // Asked again and again, and another put of this account took the room each time: refused, as full.
      if (round >= 8) return { ok: false, status: 507, code: CODES.relayFull, reason: RELAY_FULL_WORDS };
      const r = await relayBudgetOf(this.env).takeChars({ need: usage + chars - granted, extra: limits.relayCharsLease, limits });
      if (!r.ok) return { ok: false, status: 507, code: CODES.relayFull, reason: RELAY_FULL_WORDS };
      // THE GAP (review of PR 281): while the relay-wide object was asked, this object's input gate was
      // open, and another put of this account (into another mailbox) may have charged itself. So what
      // was granted is ADDED TO WHAT IS STORED NOW, and every check above is made again on what is there
      // - never a write from the values read before the call, which would lose the other's charge.
      // Chosen over blockConcurrencyWhile, which would hold every request of the account behind a call
      // to another object. Kept even if the account is now gone: an over-count, never an under-count.
      await storage.put(GRANTED, ((await storage.get(GRANTED)) || 0) + r.granted);
    }
  }

  // Mail of chars characters left mailbox, by its ack or its expiry (mailbox.js); emptied when nothing
  // is left in it. Nothing to do for an account that is gone: its deletion wipes the rest.
  async credit({ mailbox, chars, emptied, epoch }) {
    const storage = this.ctx.storage;
    const p = await storage.get(PROFILE);
    if (p === undefined || p.epoch !== epoch) return true;
    const usage = (await storage.get(USAGE)) || 0;
    const held = (await storage.get(BOX + mailbox)) || 0;
    const left = Math.max(0, usage - chars);
    await storage.put(USAGE, left);
    if (emptied) await storage.delete(BOX + mailbox);
    else await storage.put(BOX + mailbox, Math.max(0, held - chars));
    // The relay's cap: what this account holds past one lease of room goes back (budget.js, THE LEASE).
    // The room is the one its last put was held to (ROOM): an ack or an expiry carries no limits.
    // Taken off here first, given back after: a give that is lost leaves the count ahead, never behind.
    const granted = (await storage.get(GRANTED)) || 0;
    const back = charsToRelease(granted, left, (await storage.get(ROOM)) || 0);
    if (back > 0) {
      await storage.put(GRANTED, granted - back);
      await relayBudgetOf(this.env).giveChars({ chars: back });
    }
    return true;
  }

  // A machine registration is attempted (account-api.js): counted against pairingsPerHour.
  // { ok, epoch } or a refusal.
  async chargePairing({ now, limits }) {
    const storage = this.ctx.storage;
    const p = await storage.get(PROFILE);
    if (!p) return gone();
    const t = takeToken(await storage.get(PAIRING), now, limits.pairingsPerHour, HOUR_MS, limits.pairingsPerHour);
    await storage.put(PAIRING, t.state);
    if (!t.ok) return { ok: false, status: 429, code: CODES.rate, reason: "this account tried to register " + limits.pairingsPerHour + " machines in the last hour, its most: wait", retryAfterMs: t.retryAfterMs };
    return { ok: true, epoch: p.epoch };
  }

  // List a machine whose key was claimed for this account: { ok } or a refusal - the account is gone,
  // or it has its most machines (a key already listed is listed again, whatever the count).
  async listMachine({ entry, epoch, limits }) {
    const storage = this.ctx.storage;
    const p = await storage.get(PROFILE);
    if (p === undefined || p.epoch !== epoch) return gone();
    if ((await storage.get(MACHINE + entry.keyId)) === undefined) {
      const n = (await storage.list({ prefix: MACHINE })).size;
      if (n >= limits.machinesPerAccount) return { ok: false, status: 409, code: CODES.machines, reason: "this account has " + n + " machines, its most: remove one on the Account screen first" };
    }
    await storage.put(MACHINE + entry.keyId, entry);
    return { ok: true };
  }

  async unlistMachine(keyId) { this.seen.delete(keyId); await this.ctx.storage.delete(SEEN + keyId); return this.ctx.storage.delete(MACHINE + keyId); }

  // A rotation moved a machine's registration from one key to its successor (rotation.js). The rotation
  // was itself a request the relay verified, signed by the successor: it is heard under the new key.
  async moveMachine({ from, entry, now }) {
    const storage = this.ctx.storage;
    await storage.delete(MACHINE + from);
    await storage.delete(SEEN + from);
    this.seen.delete(from);
    await storage.put(MACHINE + entry.keyId, entry);
    if (Number.isSafeInteger(now)) await this.heard(entry.keyId, now);
    return true;
  }

  // The Account screen's view: { email, machines, phones }, or null when there is no account. Each
  // machine carries lastSeenAt (presence.js): the second it was last heard from, or null for never.
  async view(now) {
    const p = await this.ctx.storage.get(PROFILE);
    if (!p) return null;
    const machines = [];
    const stored = await this.ctx.storage.list({ prefix: SEEN });
    for (const [, entry] of await this.ctx.storage.list({ prefix: MACHINE })) machines.push({ ...entry, lastSeenAt: lastSeenOf(this.seen.get(entry.keyId), stored.get(SEEN + entry.keyId)) });
    return { email: p.email, machines, phones: await this.livePhones(now) };
  }

  // Sign one of its phones out from another (or itself): true when it was one of its phones.
  async endPhone(phoneId) {
    const storage = this.ctx.storage;
    if ((await storage.get(PHONE + phoneId)) === undefined) return false;
    await storage.delete(PHONE + phoneId);
    const s = sessionByObjectId(this.env, phoneId);
    if (s !== null) await s.end();
    return true;
  }

  // DELETION (the header): { ok } - also when a deletion is already under way; { ok: false } when
  // there is no account.
  async remove({ account }) {
    const storage = this.ctx.storage;
    const p = await storage.get(PROFILE);
    if (!p) return { ok: (await storage.get(DELETING)) !== undefined };
    await storage.put(DELETING, { account, epoch: p.epoch });
    await storage.delete(PROFILE);
    const phones = await storage.list({ prefix: PHONE });
    const machines = await storage.list({ prefix: MACHINE });
    const seen = await storage.list({ prefix: SEEN });
    for (const [, ph] of phones) { const s = sessionByObjectId(this.env, ph.id); if (s) await s.end(); }
    for (const [, m] of machines) await machineKeyOf(this.env, m.keyId).release(account);
    const granted = (await storage.get(GRANTED)) || 0;
    await storage.delete([...phones.keys(), ...machines.keys(), ...seen.keys(), DAY, PAIRING, USAGE, GRANTED, ROOM]);
    // Its share of the relay's cap goes back with it: its mailboxes are wiped by the alarm, uncredited.
    if (granted > 0) await relayBudgetOf(this.env).giveChars({ chars: granted });
    this.devices.clear();
    this.seen.clear();
    await storage.setAlarm(Date.now());
    return { ok: true };
  }

  // A deletion's mailboxes, a batch a run (the header).
  async alarm() {
    const storage = this.ctx.storage;
    const d = await storage.get(DELETING);
    if (d === undefined) return;
    const boxes = await storage.list({ prefix: BOX, limit: WIPE_BATCH });
    for (const name of boxes.keys()) await mailboxOf(this.env, d.account, d.epoch, name.slice(BOX.length)).wipe();
    if (boxes.size > 0) await storage.delete([...boxes.keys()]);
    if (boxes.size === WIPE_BATCH) { await storage.setAlarm(Date.now()); return; }
    await storage.deleteAll();
  }
}

export { ACCOUNT_PREFIX };
export function accountOf(env, account) { return env.ACCOUNT.get(env.ACCOUNT.idFromName("account/" + account)); }
