// relays/cloudflare/worker/machines.js - one machine's signing key, as this relay knows it: one Durable
// Object per key id, holding WHICH ACCOUNT it is registered to (by a signed-in phone, with the
// machine's own grant: account-api.js), its public point, its horde and label, the grants already
// spent, and the nonces its requests have used. It is where a machine's request is decided (auth.js),
// and since an object runs one request at a time, a key is claimed by one account only, and a nonce
// used once only, with no lock.
//
// STORAGE:
//   owner          { account, epoch, public (base64url point), horde, label, registeredAt }; absent:
//                  nobody's key. epoch is the account's (accounts.js): a key of an account deleted and
//                  made again is not that new account's
//   g:<offer>      a spent grant: its offer's expiry. Kept until then, so the grant of an offer whose
//                  key was registered and then removed cannot put it back (the founder's revoke holds)
//   n:<nonce>      a nonce this key has used, and t:<16 digits>:<nonce> beside it, when it was seen,
//                  so the old ones are deleted in order. Kept for twice the replay window
//                  (request-signature.js): a copy of a request is stale before its nonce is forgotten.
//   moved          { to, at }: this key's registration was handed to its successor by a rotation
//                  (rotation.js); the key is nobody's from then on
//
// REVOKE IS RELEASE: the owner record is deleted, and the key signs nothing this relay takes from that
// moment. The machine's keys themselves are its own (relay/Identity.ps1); a ROTATION there carries the
// old key's vouch here (rotation.js), and handOver and adopt move the registration to the new key once.
//
// THE LIMITS HERE (limits.js), kept in the object every machine request already calls, so they cost no
// request of their own:
//   - REFUSED SIGNATURES: a bucket of refusedSignaturesPerMinutePerKey in memory FOR EACH CLIENT
//     ADDRESS the key's requests come from (address.js). A request refused here - a signature that does
//     not verify, a replayed nonce, a key nobody registered - takes a token from its address's bucket;
//     with none left, that address's next request under this key is refused at once, 429, without the
//     signature check. A request that verifies takes nothing. Per address and not for the key as a
//     whole, because a key id is no secret (it names the machine's mailbox): one bucket for the key
//     would let anyone who sends forged requests under it lock the real machine out. The buckets are
//     bounded (REFUSING_MAX addresses; the oldest is forgotten first).
//   - THE NONCE CACHE IS BOUNDED: at most noncesPerKey in the replay window. A request past it is
//     refused, 429, and its nonce is not kept - never an older nonce forgotten early to make room,
//     which would let that request be replayed.
import { DurableObject } from "cloudflare:workers";
import { unb64u, verifyMachineSignature } from "../../../relay/js/protocol.js";
import { MAX_SKEW_MS } from "./request-signature.js";
import { takeToken } from "./throttle.js";
import { CODES } from "./answers.js";

const OWNER = "owner";
const GRANT = "g:";
const SEEN = "n:";
const SEEN_AT = "t:";
const MOVED = "moved";
const DELETE_BATCH = 128;
const MINUTE_MS = 60000;
const REFUSING_MAX = 256;
const pad = (n) => String(n).padStart(16, "0");

// Forget the nonces seen before cutoff (ms), each with its time record: how many were forgotten.
async function forgetNonces(storage, cutoff) {
  const old = await storage.list({ start: SEEN_AT, end: SEEN_AT + pad(cutoff) });
  const names = [];
  for (const [name, nonce] of old) names.push(name, SEEN + nonce);
  for (let i = 0; i < names.length; i += DELETE_BATCH) await storage.delete(names.slice(i, i + DELETE_BATCH));
  return old.size;
}

export class MachineKey extends DurableObject {
  constructor(ctx, env) { super(ctx, env); this.refusals = new Map(); this.nonces = null; }

  // Register this key to account: { ok, duplicate } or { ok: false, status, reason }. The grant was
  // verified by the Worker (account-api.js); here, that it is unspent and the key nobody else's.
  async claim({ account, epoch, publicKey, horde, label, offer, offerExpiresAt, now }) {
    const storage = this.ctx.storage;
    const owner = await storage.get(OWNER);
    if (owner && owner.account !== account) return { ok: false, status: 409, reason: "this machine's key is registered to another account" };
    const same = Boolean(owner) && owner.epoch === epoch;
    const spent = await storage.get(GRANT + offer);
    if (spent !== undefined && !same) return { ok: false, status: 409, reason: "this offer's grant was used already: make a new offer at the machine" };
    for (const [name, until] of await storage.list({ prefix: GRANT })) { if (until < now) await storage.delete(name); }
    if (same) { await storage.put(GRANT + offer, offerExpiresAt); return { ok: true, duplicate: true }; }
    await storage.put({ [OWNER]: { account, epoch, public: publicKey, horde, label, registeredAt: now }, [GRANT + offer]: offerExpiresAt });
    await storage.delete(MOVED);
    return { ok: true, duplicate: false };
  }

  // Unregister it from account: true when it was that account's.
  async release(account) {
    const owner = await this.ctx.storage.get(OWNER);
    if (!owner || owner.account !== account) return false;
    await this.ctx.storage.delete(OWNER);
    return true;
  }

  // Who owns this key: the owner record, or null.
  async owner() { return (await this.ctx.storage.get(OWNER)) || null; }

  // A rotation (rotation.js): hand this key's registration to its successor `to`, once. The Worker has
  // verified the vouch under the public point it read here; the registration is handed over only if it
  // is still that very one. { ok, owner } - the record handed over - or { ok: false }.
  async handOver({ account, publicKey, to, now }) {
    const storage = this.ctx.storage;
    const owner = await storage.get(OWNER);
    if (!owner || owner.account !== account || owner.public !== publicKey) return { ok: false };
    await storage.delete(OWNER);
    await storage.put(MOVED, { to, at: now });
    return { ok: true, owner };
  }

  // A rotation's successor: take the registration handed over (handOver's owner) under this key, with
  // the rotation request's nonce spent here. { ok } or { ok: false, reason }.
  async adopt({ owner, publicKey, nonce, now }) {
    const storage = this.ctx.storage;
    const mine = await storage.get(OWNER);
    if (mine && mine.account !== owner.account) return { ok: false, reason: "the new key is registered to another account" };
    if ((await storage.get(SEEN + nonce)) !== undefined) return { ok: false, reason: "the nonce was used already: a replay" };
    await storage.put({ [OWNER]: { ...owner, public: publicKey, registeredAt: now }, [SEEN + nonce]: now, [SEEN_AT + pad(now) + ":" + nonce]: nonce });
    this.nonces = null;
    return { ok: true };
  }

  // Put back a registration handOver gave up, when its successor could not take it.
  async restore(owner) {
    const storage = this.ctx.storage;
    if (await storage.get(OWNER)) return false;
    await storage.put(OWNER, owner);
    await storage.delete(MOVED);
    return true;
  }

  // A request signed by this key, from a client address: { account, epoch, horde, label } when the
  // signature verifies under the registered key and the nonce is new - the nonce is then spent - else { refused: why }, with status
  // 429 and retryAfterMs when a limit refused it (the header). Its time was found fresh by the Worker
  // first (auth.js), which is what makes forgetting a nonce after twice the window safe.
  async verify({ nonce, sig, signed, now, limits, address }) {
    const storage = this.ctx.storage;
    // The bucket of this key's requests from this address (the header: never one for the whole key).
    const slot = address;
    const probe = takeToken(this.refusals.get(slot), now, limits.refusedSignaturesPerMinutePerKey, MINUTE_MS, limits.refusedSignaturesPerMinutePerKey);
    const keep = (state) => {
      this.refusals.delete(slot);
      if (this.refusals.size >= REFUSING_MAX) this.refusals.delete(this.refusals.keys().next().value);
      this.refusals.set(slot, state);
    };
    if (!probe.ok) { keep(probe.state); return { refused: "this key's requests from this address were refused too often: wait a minute", status: 429, code: CODES.rate, retryAfterMs: probe.retryAfterMs }; }
    const refused = (why) => { keep(probe.state); return { refused: why }; };
    const owner = await storage.get(OWNER);
    if (!owner) return refused("this key is not registered to any account");
    let point, sigBytes;
    try { point = unb64u(owner.public); sigBytes = unb64u(sig); } catch (e) { return refused("the signature is not base64url"); }
    if (!(await verifyMachineSignature(point, signed, sigBytes))) return refused("the signature does not verify under the registered key");
    if ((await storage.get(SEEN + nonce)) !== undefined) return refused("the nonce was used already: a replay");
    if (this.nonces === null) this.nonces = (await storage.list({ prefix: SEEN_AT })).size;
    this.nonces = Math.max(0, this.nonces - (await forgetNonces(storage, now - 2 * MAX_SKEW_MS - 1000)));
    if (this.nonces >= limits.noncesPerKey) return { refused: "this key has made " + this.nonces + " requests in the last two minutes, the most the relay keeps: wait", status: 429, code: CODES.rate, retryAfterMs: MAX_SKEW_MS };
    await storage.put({ [SEEN + nonce]: now, [SEEN_AT + pad(now) + ":" + nonce]: nonce });
    this.nonces++;
    return { account: owner.account, epoch: owner.epoch, horde: owner.horde, label: owner.label };
  }
}

export function machineKeyOf(env, keyId) { return env.MACHINE_KEY.get(env.MACHINE_KEY.idFromName("machine/" + keyId)); }
