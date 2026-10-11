// relays/cloudflare/worker/machines.js - one machine's signing key, as this relay knows it: one Durable
// Object per key id, holding WHICH ACCOUNT it is registered to (by a signed-in phone, with the
// machine's own grant: account-api.js), its public point and its horde, the grants already spent, and
// the nonces its requests have used. It is where a machine's request is decided (auth.js), and since an
// object runs one request at a time, a key is claimed by one account only, and a nonce used once only,
// with no lock.
//
// STORAGE:
//   owner          { account, public (base64url point), horde, registeredAt }; absent: nobody's key
//   g:<offer>      a spent grant: its offer's expiry. Kept until then, so the grant of an offer whose
//                  key was registered and then removed cannot put it back (the founder's revoke holds)
//   n:<nonce>      a nonce this key has used, and t:<16 digits>:<nonce> beside it, when it was seen,
//                  so the old ones are deleted in order. Kept for twice the replay window
//                  (request-signature.js): a copy of a request is stale before its nonce is forgotten.
//
// REVOKE IS RELEASE: the owner record is deleted, and the key signs nothing this relay takes from that
// moment. The machine's keys themselves are its own (relay/Identity.ps1); nothing here can rotate them.
// 8c's caps (machines per account, requests per key) go in claim and verify.
import { DurableObject } from "cloudflare:workers";
import { unb64u, verifyMachineSignature } from "../../../relay/js/protocol.js";
import { MAX_SKEW_MS } from "./request-signature.js";

const OWNER = "owner";
const GRANT = "g:";
const SEEN = "n:";
const SEEN_AT = "t:";
const DELETE_BATCH = 128;
const pad = (n) => String(n).padStart(16, "0");

// Forget the nonces seen before cutoff (ms), each with its time record.
async function forgetNonces(storage, cutoff) {
  const old = await storage.list({ start: SEEN_AT, end: SEEN_AT + pad(cutoff) });
  const names = [];
  for (const [name, nonce] of old) names.push(name, SEEN + nonce);
  for (let i = 0; i < names.length; i += DELETE_BATCH) await storage.delete(names.slice(i, i + DELETE_BATCH));
}

export class MachineKey extends DurableObject {
  // Register this key to account: { ok, duplicate } or { ok: false, status, reason }. The grant was
  // verified by the Worker (account-api.js); here, that it is unspent and the key nobody else's.
  async claim({ account, publicKey, horde, offer, offerExpiresAt, now }) {
    const storage = this.ctx.storage;
    const owner = await storage.get(OWNER);
    if (owner && owner.account !== account) return { ok: false, status: 409, reason: "this machine's key is registered to another account" };
    const spent = await storage.get(GRANT + offer);
    if (spent !== undefined && !owner) return { ok: false, status: 409, reason: "this offer's grant was used already: make a new offer at the machine" };
    for (const [name, until] of await storage.list({ prefix: GRANT })) { if (until < now) await storage.delete(name); }
    if (owner) { await storage.put(GRANT + offer, offerExpiresAt); return { ok: true, duplicate: true }; }
    await storage.put({ [OWNER]: { account, public: publicKey, horde, registeredAt: now }, [GRANT + offer]: offerExpiresAt });
    return { ok: true, duplicate: false };
  }

  // Unregister it from account: true when it was that account's.
  async release(account) {
    const owner = await this.ctx.storage.get(OWNER);
    if (!owner || owner.account !== account) return false;
    await this.ctx.storage.delete(OWNER);
    return true;
  }

  // A request signed by this key: { account, horde } when the signature verifies under the registered
  // key and the nonce is new - the nonce is then spent - else { refused: why }. Its time was found
  // fresh by the Worker first (auth.js), which is what makes forgetting a nonce after twice the window
  // safe.
  async verify({ nonce, sig, signed, now }) {
    const storage = this.ctx.storage;
    const owner = await storage.get(OWNER);
    if (!owner) return { refused: "this key is not registered to any account" };
    let point, sigBytes;
    try { point = unb64u(owner.public); sigBytes = unb64u(sig); } catch (e) { return { refused: "the signature is not base64url" }; }
    if (!(await verifyMachineSignature(point, signed, sigBytes))) return { refused: "the signature does not verify under the registered key" };
    if ((await storage.get(SEEN + nonce)) !== undefined) return { refused: "the nonce was used already: a replay" };
    await storage.put({ [SEEN + nonce]: now, [SEEN_AT + pad(now) + ":" + nonce]: nonce });
    await forgetNonces(storage, now - 2 * MAX_SKEW_MS - 1000);
    return { account: owner.account, horde: owner.horde };
  }
}

export function machineKeyOf(env, keyId) { return env.MACHINE_KEY.get(env.MACHINE_KEY.idFromName("machine/" + keyId)); }
