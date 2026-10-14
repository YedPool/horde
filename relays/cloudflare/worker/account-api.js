// relays/cloudflare/worker/account-api.js - a signed-in account: the account API, behind the same
// authentication as the mailboxes (api.js asks auth.js first, and hands over only a principal).
//
//   GET    /v1/account                     -> 200 { account: { email }, machines: [{ keyId, horde, label, registeredAt, lastSeenAt }],
//                                                   phones: [{ id, signedInAt, expiresAt, current }], now }
//   POST   /v1/account/machines            { horde, offer, machine, label, signPublic, expiresAt, grant }
//                                          -> 200 { keyId, horde, duplicate }
//   DELETE /v1/account/machines/<key id>   -> 200 { removed: <key id> }
//   DELETE /v1/account/phones/<phone id>   -> 200 { signedOut: <phone id> }
//   DELETE /v1/account                     { confirm: "delete this account" } -> 200 { deleted: true }
// A phone may do all of these (auth.js); a machine may only remove its own key, and see nothing.
//
// WHEN EACH MACHINE WAS LAST HEARD FROM rides on the account's own answer (presence.js): lastSeenAt, to
// the second, or null for a machine not heard from yet; and now, THE RELAY'S OWN CLOCK at the answer, so
// the phone measures "two minutes without the PC" between two times of this one clock, and a phone whose
// clock is wrong cannot make a machine look offline or online (account-client.js, presenceOf). No new
// route: the phone reads this answer on a timer while it is open, held to the same read bucket as every
// other request of that phone (limits.js, readsPerMinute), and, as the Account screen, not counted in the
// account's day.
//
// REGISTERING is how a machine gets in at all, and it needs the machine's consent: the phone, while it
// pairs, hands over the offer's fields and its ACCOUNT GRANT (relay/Pairing.ps1), and the key is taken
// into the phone's account only when
//   - the horde is a horde name, the offer an offer id, the label a label, and signPublic a P-256 point
//     whose key id is the machine the offer names;
//   - the offer has not expired, and expires no later than an offer can live (900 s) from now: a grant
//     is never good for longer than its offer was;
//   - the grant verifies, low-S, under that very key over its horde, offer, key id, expiry and label -
//     so a public key alone, which every offer and card shows, registers nothing, and the name the
//     Account screen shows is the machine's own;
//   - and the key's own object (machines.js) has not spent that offer's grant, and the key is no other
//     account's. A phone that sends the same registration again is told it is already there.
// THE LIMITS (limits.js): every attempt counts against the account's pairingsPerHour, before anything
// else is asked of it; and a machine past the account's machinesPerAccount is refused 409 machines-cap,
// its claim released again - the cap is checked where the list is, in the account's object, so two
// registrations at once cannot both take the last place.
// REMOVING releases the key first - from that moment it signs nothing this relay takes - and then takes
// it off the account's list. SIGNING A PHONE OUT ends its session at the relay at once, from any of the
// account's phones. DELETING THE ACCOUNT (accounts.js, remove) takes every mailbox, machine
// registration and session with it; its body must say so in words, so no request does it by accident.
import { answer, refuse, refusalOf } from "./answers.js";
import { readJson } from "./body.js";
import { authorize } from "./auth.js";
import { machineKeyOf } from "./machines.js";
import { accountOf } from "./accounts.js";
import { PHONE_ID } from "./sessions.js";
import { clearedCookieHeader, SESSION_COOKIE } from "./cookies.js";
import { mailboxProblem } from "./rules.js";
import { ownersOf, ownersSummary } from "./budget.js";
// The words a deletion must carry: the phone's account client's, the one copy of them (SSOT).
import { DELETE_CONFIRM } from "../../../surfaces/pwa/page/account-client.js";
import { keyId as keyIdOf, unb64u, accountGrantBytes, verifyMachineSignature, validLabel, PAIRING_LIMITS } from "../../../relay/js/protocol.js";

export const ACCOUNT_ROOT = "/v1/account";
const MACHINES = /^\/v1\/account\/machines(?:\/([0-9a-f]{32}))?$/;
const PHONES = /^\/v1\/account\/phones\/([0-9a-f]{64})$/;
const KEY_ID = /^[0-9a-f]{32}$/;
const OFFER = /^[0-9a-f]{32}$/;
const REGISTRATION_BYTES = 4096;
const REGISTRATION = ["horde", "offer", "machine", "label", "signPublic", "expiresAt", "grant"];

export function isAccountPath(pathname) { return pathname === ACCOUNT_ROOT || pathname.startsWith(ACCOUNT_ROOT + "/"); }

async function register(request, env, who, limits) {
  const { body, refusal } = await readJson(request, REGISTRATION, REGISTRATION_BYTES);
  if (refusal) return refusal;
  const account = accountOf(env, who.account);
  const now = Date.now();
  const charged = await account.chargePairing({ now, limits });
  if (!charged.ok) return refusalOf(charged);
  if (typeof body.horde !== "string" || mailboxProblem(body.horde + "/x")) return refuse(400, "the horde is not a horde name");
  if (typeof body.offer !== "string" || !OFFER.test(body.offer)) return refuse(400, "the offer is not an offer id");
  if (typeof body.machine !== "string" || !KEY_ID.test(body.machine)) return refuse(400, "the machine is not a key id");
  if (!validLabel(body.label)) return refuse(400, "the label is not 1 to 64 printable ASCII characters, no quote or backslash, no space at either end");
  let point, grant;
  try { point = unb64u(body.signPublic); grant = unb64u(body.grant); } catch (e) { return refuse(400, "signPublic and grant are base64url"); }
  let id = "";
  try { id = await keyIdOf(point); } catch (e) { id = ""; }
  if (id !== body.machine) return refuse(400, "signPublic is not the key of the machine named");
  if (!Number.isSafeInteger(body.expiresAt) || body.expiresAt <= now) return refuse(400, "the offer has expired: make a new one at the machine");
  if (body.expiresAt > now + PAIRING_LIMITS.maxTtlSeconds * 1000) return refuse(400, "the offer outlives any offer a machine makes");
  if (!(await verifyMachineSignature(point, accountGrantBytes(body), grant))) return refuse(403, "the account grant does not verify under the machine's key");
  const key = machineKeyOf(env, id);
  const claimed = await key.claim({ account: who.account, epoch: charged.epoch, publicKey: body.signPublic, horde: body.horde, label: body.label, offer: body.offer, offerExpiresAt: body.expiresAt, now });
  if (!claimed.ok) return refuse(claimed.status, claimed.reason);
  let listed;
  try {
    listed = await account.listMachine({ entry: { keyId: id, horde: body.horde, label: body.label, registeredAt: now }, epoch: charged.epoch, limits });
  } catch (e) {
    if (claimed.duplicate !== true) await key.release(who.account);
    throw e;
  }
  if (!listed.ok) {
    if (!claimed.duplicate) await key.release(who.account);
    return refusalOf(listed);
  }
  return answer(200, { keyId: id, horde: body.horde, duplicate: claimed.duplicate });
}

async function remove(env, who, keyId) {
  const released = await machineKeyOf(env, keyId).release(who.account);
  await accountOf(env, who.account).unlistMachine(keyId);
  if (!released) return refuse(404, "no such machine on this account");
  return answer(200, { removed: keyId });
}

async function endPhone(env, who, phoneId) {
  if (!(await accountOf(env, who.account).endPhone(phoneId))) return refuse(404, "no such phone is signed in to this account");
  return answer(200, { signedOut: phoneId });
}

async function deleteAccount(request, env, who) {
  const { body, refusal } = await readJson(request, ["confirm"], REGISTRATION_BYTES);
  if (refusal) return refusal;
  if (body.confirm !== DELETE_CONFIRM) return refuse(400, "to delete the account, confirm with the words: " + DELETE_CONFIRM);
  const r = await accountOf(env, who.account).remove({ account: who.account });
  if (!r.ok) return refuse(404, "there is no account to delete");
  // The phone that deleted it holds a session that is over: its cookie is cleared, as sign-out clears it.
  const done = answer(200, { deleted: true });
  done.headers.append("Set-Cookie", clearedCookieHeader(SESSION_COOKIE));
  return done;
}

// The account's gate (accounts.js, admit) for one account operation: null to go on, or the refusal.
async function gate(env, who, op, limits) {
  if (!who.gated) return null;
  const g = await accountOf(env, who.account).admit({ device: who.device, epoch: who.epoch, op, mailbox: "", now: Date.now(), limits });
  return g.ok ? null : refusalOf(g);
}

export async function handleAccountApi(request, env, url, who, limits) {
  if (url.pathname === ACCOUNT_ROOT) {
    if (request.method === "DELETE") {
      if (!authorize(who, "delete", "")) return refuse(403, "you may not delete this account");
      return (await gate(env, who, "delete", limits)) || deleteAccount(request, env, who);
    }
    if (request.method !== "GET") return refuse(405, "the account is read with GET, and deleted with DELETE");
    if (!authorize(who, "account", "")) return refuse(403, "you may not read this account");
    const held = await gate(env, who, "account", limits);
    if (held) return held;
    const now = Date.now();
    const v = await accountOf(env, who.account).view(now);
    if (!v) return refuse(401, "this account was deleted");
    const phones = v.phones.map((p) => ({ id: p.id, signedInAt: p.signedInAt, expiresAt: p.expiresAt, current: p.id === who.phone }));
    // relay: the relay's owners in number and whether a reserve is kept (budget.js, ownersSummary), never
    // who: the Account screen says when the whole day is shared (surfaces/pwa, account-client.js).
    return answer(200, { account: { email: who.email || "" }, machines: v.machines, phones, now, relay: ownersSummary(ownersOf(env)) });
  }
  const ph = PHONES.exec(url.pathname);
  if (ph) {
    if (request.method !== "DELETE") return refuse(405, "a phone is signed out with DELETE");
    if (!authorize(who, "end-phone", ph[1]) || !PHONE_ID.test(ph[1])) return refuse(403, "you may not sign out that phone");
    return (await gate(env, who, "end-phone", limits)) || endPhone(env, who, ph[1]);
  }
  const m = MACHINES.exec(url.pathname);
  if (!m) return refuse(404, "there is no such account operation");
  if (m[1] === undefined) {
    if (request.method !== "POST") return refuse(405, "a machine is registered with POST");
    if (!authorize(who, "register", "")) return refuse(403, "you may not register machines");
    return register(request, env, who, limits);
  }
  if (request.method !== "DELETE") return refuse(405, "a machine is removed with DELETE");
  if (!authorize(who, "remove", m[1])) return refuse(403, "you may not remove that machine");
  return (await gate(env, who, "remove", limits)) || remove(env, who, m[1]);
}
