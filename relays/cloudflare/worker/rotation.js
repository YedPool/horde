// relays/cloudflare/worker/rotation.js - A MACHINE'S IDENTITY ROTATION, carried to the relay: the old
// signing key's registration moves to its successor, once, without the phone pairing again (relay PR 8c;
// relay/Identity.ps1, ROTATION).
//
//   POST /v1/machines/rotation   { "record": "<the retirement record>" }   -> 200 { keyId, horde, from }
//
// A rotation makes new keys and deletes the old signing key at once, so the machine can no longer sign
// as the key this relay knows. What it keeps is the RETIREMENT RECORD, which the old key signed (its
// VOUCH) before it was deleted, naming its successor's keys. So this request is its own authentication,
// and it must prove both halves:
//   - the request is SIGNED BY THE NEW KEY, exactly as any machine request is (request-signature.js:
//     the origin, method, path, time, nonce, key id and the body's hash), fresh, under the successor
//     point the record names, and under the successor's key id (the record pairs the two: the old
//     key's vouch covers both) - so only the holder of the new key can present the record, a copy of
//     the record alone moves nothing, and the registration lands under no other key id;
//   - the record's VOUCH VERIFIES under the OLD key's point AS THIS RELAY REGISTERED IT, for the
//     record's horde - so only a rotation the registered key itself signed moves its registration.
// Then the old key's object hands its registration over (machines.js, handOver: only if it is still
// that very registration, and then never again - the old key is nobody's from that moment), the new
// key's object adopts it with this request's nonce spent, and the account's list follows. SINGLE USE:
// a second presentation of the record finds the old key registered to nobody; a replay of the request
// finds its nonce spent. A record with no vouch (a lost key's rotation) moves nothing: that machine
// pairs again.
//
// EVERY REFUSAL IS ONE FIXED SENTENCE, 401, as a machine's are (auth.js) - except a stale clock, which
// says so - so this route tells a caller nothing about which keys are registered. Each refusal counts
// against the address's refused signatures (address.js), as a forged machine request does.
import { answer, refuse, refusalOf } from "./answers.js";
import { readCappedBytes } from "./body.js";
import { readMachineAuthorization, requestSignedBytes, bodyHash, isFresh, MAX_SKEW_MS } from "./request-signature.js";
import { siteOf } from "./site.js";
import { machineKeyOf } from "./machines.js";
import { accountOf } from "./accounts.js";
import { clientAddressOf } from "./client-address.js";
import { noteRefusedSignature, addressRefusal } from "./auth.js";
import { unb64u, readRetirement, verifyMachineSignature } from "../../../relay/js/protocol.js";

export const ROTATION_PATH = "/v1/machines/rotation";
const BODY_BYTES = 16384;
const REFUSED = "the relay takes no such rotation";

function readBody(bytes) {
  try {
    const o = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
    if (!o || typeof o !== "object" || Array.isArray(o) || Object.keys(o).join(",") !== "record" || typeof o.record !== "string") return null;
    return o.record;
  } catch (e) { return null; }
}

export async function handleRotation(request, env, url, limits) {
  const a = readMachineAuthorization(request.headers.get("Authorization"));
  if (request.method !== "POST" || !a) return refuse(401, REFUSED);
  const now = Date.now();
  if (!isFresh(a.time, now)) return refuse(401, "the request's time is more than " + (MAX_SKEW_MS / 1000) + " s from the relay's clock: set this machine's clock");
  const address = clientAddressOf(request, env, url);
  const held = addressRefusal(address, now);
  if (held) return refusalOf({ status: 429, code: held.code, reason: held.refusal, retryAfterMs: held.retryAfterMs });
  const fail = async () => {
    const r = await noteRefusedSignature(env, address, now, limits);
    return r ? refusalOf({ status: 429, code: r.code, reason: r.refusal, retryAfterMs: r.retryAfterMs }) : refuse(401, REFUSED);
  };
  const bytes = await readCappedBytes(request, BODY_BYTES);
  if (bytes === null) return fail();
  const text = readBody(bytes);
  const rec = readRetirement(text);
  if (!rec.ok || rec.value.successorSignKeyId !== a.keyId) return fail();
  let newPoint, sig, vouch;
  try { newPoint = unb64u(rec.value.successorSignPublic); sig = unb64u(a.sig); vouch = unb64u(rec.value.vouch); } catch (e) { return fail(); }
  const signed = requestSignedBytes({ origin: siteOf(env).origin, method: request.method, target: url.pathname + url.search, time: a.time, nonce: a.nonce, keyId: a.keyId, hash: await bodyHash(bytes) });
  if (!(await verifyMachineSignature(newPoint, signed, sig))) return fail();
  const old = machineKeyOf(env, rec.value.signKeyId);
  const owner = await old.owner();
  if (!owner || owner.horde !== rec.value.horde) return fail();
  let oldPoint;
  try { oldPoint = unb64u(owner.public); } catch (e) { return fail(); }
  if (!(await verifyMachineSignature(oldPoint, rec.value.signed, vouch))) return fail();
  const handed = await old.handOver({ account: owner.account, publicKey: owner.public, to: a.keyId, now });
  if (!handed.ok) return fail();
  const adopted = await machineKeyOf(env, a.keyId).adopt({ owner: handed.owner, publicKey: rec.value.successorSignPublic, nonce: a.nonce, now });
  if (!adopted.ok) { await old.restore(handed.owner); return fail(); }
  await accountOf(env, owner.account).moveMachine({ from: rec.value.signKeyId, entry: { keyId: a.keyId, horde: owner.horde, label: owner.label, registeredAt: now } });
  return answer(200, { keyId: a.keyId, horde: owner.horde, from: rec.value.signKeyId });
}
