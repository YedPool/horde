// relays/cloudflare/worker/account-api.js - a signed-in account's machines: the account API, behind the
// same authentication as the mailboxes (api.js asks auth.js first, and hands over only a principal).
//
//   GET    /v1/account                     -> 200 { account: { email }, machines: [{ keyId, horde, registeredAt }] }
//   POST   /v1/account/machines            { horde, offer, machine, signPublic, expiresAt, grant }
//                                          -> 200 { keyId, horde, duplicate }
//   DELETE /v1/account/machines/<key id>   -> 200 { removed: <key id> }
// A phone may do all three (auth.js); a machine may only remove its own key, and see nothing.
//
// REGISTERING is how a machine gets in at all, and it needs the machine's consent: the phone, while it
// pairs, hands over the offer's fields and its ACCOUNT GRANT (relay/Pairing.ps1), and the key is taken
// into the phone's account only when
//   - the horde is a horde name, the offer an offer id, and signPublic a P-256 point whose key id is
//     the machine the offer names;
//   - the offer has not expired, and expires no later than an offer can live (900 s) from now: a grant
//     is never good for longer than its offer was;
//   - the grant verifies, low-S, under that very key over its horde, offer, key id and expiry - so a
//     public key alone, which every offer and card shows, registers nothing;
//   - and the key's own object (machines.js) has not spent that offer's grant, and the key is no other
//     account's. A phone that sends the same registration again is told it is already there.
// REMOVING releases the key first - from that moment it signs nothing this relay takes - and then takes
// it off the account's list.
import { answer, refuse } from "./answers.js";
import { readJson } from "./body.js";
import { authorize } from "./auth.js";
import { machineKeyOf } from "./machines.js";
import { accountOf } from "./accounts.js";
import { mailboxProblem } from "./rules.js";
import { keyId as keyIdOf, unb64u, accountGrantBytes, verifyMachineSignature, PAIRING_LIMITS } from "../../../relay/js/protocol.js";

export const ACCOUNT_ROOT = "/v1/account";
const MACHINES = /^\/v1\/account\/machines(?:\/([0-9a-f]{32}))?$/;
const KEY_ID = /^[0-9a-f]{32}$/;
const OFFER = /^[0-9a-f]{32}$/;
const REGISTRATION_BYTES = 4096;
const REGISTRATION = ["horde", "offer", "machine", "signPublic", "expiresAt", "grant"];

export function isAccountPath(pathname) { return pathname === ACCOUNT_ROOT || pathname.startsWith(ACCOUNT_ROOT + "/"); }

async function register(request, env, who) {
  const { body, refusal } = await readJson(request, REGISTRATION, REGISTRATION_BYTES);
  if (refusal) return refusal;
  if (typeof body.horde !== "string" || mailboxProblem(body.horde + "/x")) return refuse(400, "the horde is not a horde name");
  if (typeof body.offer !== "string" || !OFFER.test(body.offer)) return refuse(400, "the offer is not an offer id");
  if (typeof body.machine !== "string" || !KEY_ID.test(body.machine)) return refuse(400, "the machine is not a key id");
  let point, grant;
  try { point = unb64u(body.signPublic); grant = unb64u(body.grant); } catch (e) { return refuse(400, "signPublic and grant are base64url"); }
  let id = "";
  try { id = await keyIdOf(point); } catch (e) { id = ""; }
  if (id !== body.machine) return refuse(400, "signPublic is not the key of the machine named");
  const now = Date.now();
  if (!Number.isSafeInteger(body.expiresAt) || body.expiresAt <= now) return refuse(400, "the offer has expired: make a new one at the machine");
  if (body.expiresAt > now + PAIRING_LIMITS.maxTtlSeconds * 1000) return refuse(400, "the offer outlives any offer a machine makes");
  if (!(await verifyMachineSignature(point, accountGrantBytes(body), grant))) return refuse(403, "the account grant does not verify under the machine's key");
  const claimed = await machineKeyOf(env, id).claim({ account: who.account, publicKey: body.signPublic, horde: body.horde, offer: body.offer, offerExpiresAt: body.expiresAt, now });
  if (!claimed.ok) return refuse(claimed.status, claimed.reason);
  try {
    await accountOf(env, who.account).listMachine({ keyId: id, horde: body.horde, registeredAt: now });
  } catch (e) {
    if (!claimed.duplicate) await machineKeyOf(env, id).release(who.account);
    throw e;
  }
  return answer(200, { keyId: id, horde: body.horde, duplicate: claimed.duplicate });
}

async function remove(env, who, keyId) {
  const released = await machineKeyOf(env, keyId).release(who.account);
  await accountOf(env, who.account).unlistMachine(keyId);
  if (!released) return refuse(404, "no such machine on this account");
  return answer(200, { removed: keyId });
}

export async function handleAccountApi(request, env, url, who) {
  if (url.pathname === ACCOUNT_ROOT) {
    if (request.method !== "GET") return refuse(405, "the account is read with GET");
    if (!authorize(who, "account", "")) return refuse(403, "you may not read this account");
    return answer(200, { account: { email: who.email || "" }, machines: await accountOf(env, who.account).machines() });
  }
  const m = MACHINES.exec(url.pathname);
  if (!m) return refuse(404, "there is no such account operation");
  if (m[1] === undefined) {
    if (request.method !== "POST") return refuse(405, "a machine is registered with POST");
    if (!authorize(who, "register", "")) return refuse(403, "you may not register machines");
    return register(request, env, who);
  }
  if (request.method !== "DELETE") return refuse(405, "a machine is removed with DELETE");
  if (!authorize(who, "remove", m[1])) return refuse(403, "you may not remove that machine");
  return remove(env, who, m[1]);
}
