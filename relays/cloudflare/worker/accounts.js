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
//   b:<mailbox>    a mailbox it has put in, so deleting the account can find every one
//   day            { day, n }: its requests this UTC day (throttle.js)
//   pairing        its pairing bucket (throttle.js)
//   deleting       { account, epoch }: a deletion under way (remove, alarm)
// IN MEMORY: each device's put and read buckets. An eviction only refills them, as the idle time
// would have.
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
//   - a put's mailbox is indexed, the first time, for deletion.
// WHY ONE CALL A REQUEST. An account's day is counted across all its phones and machines, so it is
// counted in one place, exactly, and that place is this object. It costs one Durable Object request on
// each relay request (three in all with the principal's and the mailbox's; reckoned 2026-10-11 against
// the free plan's 100,000 a day). Spreading the count over the principals' objects (each taking a
// lease of the day's count from here now and then) would save most of those calls, but a lease one
// device holds is a request another cannot make, so near the cap a machine would be refused while a
// phone sat on unused requests; and the deletion fence and the mailbox index would then need calls
// of their own anyway.
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
import { b64u, randomBytes } from "../../../relay/js/protocol.js";

const PROFILE = "profile";
const MACHINE = "m:";
const PHONE = "p:";
const BOX = "b:";
const DAY = "day";
const PAIRING = "pairing";
const DELETING = "deleting";
const MINUTE_MS = 60000;
const HOUR_MS = 3600000;
// Mailboxes wiped in one alarm run: few enough that one run's calls stay well inside a Worker's
// subrequest budget, whatever the number of mailboxes.
const WIPE_BATCH = 20;
// The mailbox operations: the ones counted against requestsPerDay (THE GATE).
const MAILBOX_OPS = new Set(["get", "put", "watch", "ack"]);

const gone = () => ({ ok: false, status: 401, code: CODES.gone, reason: "this account was deleted" });

export class Account extends DurableObject {
  constructor(ctx, env) { super(ctx, env); this.devices = new Map(); }

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
  async admit({ device, epoch, op, mailbox, now, limits }) {
    const storage = this.ctx.storage;
    const p = await storage.get(PROFILE);
    if (!p || p.epoch !== epoch) return gone();
    if (op === "delete") return { ok: true };
    const put = op === "put";
    const held = this.devices.get(device) || {};
    const t = put ? takeToken(held.put, now, limits.putsPerMinute, MINUTE_MS, limits.putBurst) : takeToken(held.read, now, limits.readsPerMinute, MINUTE_MS, limits.readBurst);
    this.devices.set(device, put ? { ...held, put: t.state } : { ...held, read: t.state });
    if (!t.ok) return { ok: false, status: 429, code: CODES.rate, reason: "this " + (device.startsWith("phone:") ? "phone" : "machine") + " made more " + (put ? "puts" : "requests") + " than the relay takes in a minute: wait", retryAfterMs: t.retryAfterMs };
    if (MAILBOX_OPS.has(op)) {
      const c = countInDay(await storage.get(DAY), now, limits.requestsPerDay);
      if (!c.ok) return { ok: false, status: 429, code: CODES.daily, reason: "this account made " + limits.requestsPerDay + " requests today, its most for a day: the count starts again at midnight UTC", retryAfterMs: c.retryAfterMs };
      await storage.put(DAY, c.state);
    }
    if (put && (await storage.get(BOX + mailbox)) === undefined) await storage.put(BOX + mailbox, 1);
    return { ok: true };
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

  async unlistMachine(keyId) { return this.ctx.storage.delete(MACHINE + keyId); }

  // A rotation moved a machine's registration from one key to its successor (rotation.js).
  async moveMachine({ from, entry }) {
    const storage = this.ctx.storage;
    await storage.delete(MACHINE + from);
    await storage.put(MACHINE + entry.keyId, entry);
    return true;
  }

  // The Account screen's view: { email, machines, phones }, or null when there is no account.
  async view(now) {
    const p = await this.ctx.storage.get(PROFILE);
    if (!p) return null;
    const machines = [];
    for (const [, entry] of await this.ctx.storage.list({ prefix: MACHINE })) machines.push(entry);
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
    for (const [, ph] of phones) { const s = sessionByObjectId(this.env, ph.id); if (s) await s.end(); }
    for (const [, m] of machines) await machineKeyOf(this.env, m.keyId).release(account);
    await storage.delete([...phones.keys(), ...machines.keys(), DAY, PAIRING]);
    this.devices.clear();
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

export const ACCOUNT_PREFIX = "google:";
export function accountOf(env, account) { return env.ACCOUNT.get(env.ACCOUNT.idFromName("account/" + account)); }
