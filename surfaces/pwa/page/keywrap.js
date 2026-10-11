// surfaces/pwa/page/keywrap.js - how the phone keeps its identity key: never in the clear, only
// WRAPPED, under one or more keys it can get back (relay design 2026-10-09, Q7).
//
// THE PHONE IDENTITY KEY is a random P-256 key the phone makes once per horde. The machines seal every
// snapshot to it (channels/trust announces it), so whoever holds it can READ. It is never stored as it
// is: its PKCS#8 bytes are AES-256-GCM-wrapped, and only the wraps are kept (IndexedDB, store.js).
// THE WRAPS, each a record { v, kind, iv, ct, ... }:
//   prf        under HKDF-SHA256 of the passkey's PRF output (WebAuthn L3 10.1.4) for this horde's
//              credential. PRF is never the key itself: the HKDF binds the output to this purpose.
//              Unwrapping needs a passkey assertion with user verification - the founder's finger.
//   recovery   under PBKDF2-SHA256 of a printed recovery code: 120 random bits, written as six groups
//              of four Crockford base32 characters. It unwraps the key, so it can READ; it is not a
//              passkey, so it can never sign an answer nor enroll anything (the machine verifies every
//              answer against the passkey it pinned at pairing). The app shows a recovery unlock as
//              read only, but the guarantee is the machine's, not the screen's.
// THERE IS NO THIRD WRAP. A passkey without PRF gives the phone nothing to wrap under, and a key
// kept in the browser instead (a non-extractable AES key beside the wraps, the first version of this
// file) is usable by any script of this origin behind a gate that is the app's, not cryptography's.
// The founder's decision of 2026-10-10 (open question 3 of this PR): highest security wins - such a
// horde is READ ONLY on this phone (phone-core.js), read by the recovery code, and never answered.
// EVERY WRAP'S ADDITIONAL DATA names its kind, the horde and the key's id, so a wrap moved to another
// horde's record, or relabelled as another kind, does not open.
//
// PBKDF2 ITERATIONS: 600,000 (OWASP's 2023 figure for PBKDF2-HMAC-SHA256). The code carries 120 random
// bits, so the count is a second layer, not the defence. Kept in each record, so it can be raised for
// new wraps without breaking old ones. Measured 2026-10-09: about 0.3 s in Node 24 on the dev box.
import { utf8, b64u, unb64u, randomBytes, keyId } from "../relay/protocol.js";

const subtle = globalThis.crypto.subtle;
const WRAP_DOMAIN = "horde-relay/phone-key/v1 wrap\n";
const PRF_INFO = "horde-relay/phone-key/v1 prf wrap key";
const PRF_INPUT = "horde-relay/phone-key/v1 prf input\n";
export const RECOVERY_ITERATIONS = 600000;
const CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

function aadOf(kind, horde, agreeKeyId) { return utf8(WRAP_DOMAIN + kind + "\n" + horde + "\n" + agreeKeyId); }

// The PRF input for one horde's pairing: fixed by the horde and the machine, so nothing needs keeping
// to ask for the same output again, and it is known before the credential exists (a provider may
// evaluate PRF at creation). The output differs per credential all the same: PRF is the credential's.
export function prfInput(horde, machine) { return utf8(PRF_INPUT + horde + "\n" + machine); }

async function prfWrapKey(prfOutput) {
  const ikm = await subtle.importKey("raw", prfOutput, "HKDF", false, ["deriveKey"]);
  return subtle.deriveKey({ name: "HKDF", hash: "SHA-256", salt: new Uint8Array(0), info: utf8(PRF_INFO) }, ikm, { name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
}
async function recoveryWrapKey(code, salt, iterations) {
  const ikm = await subtle.importKey("raw", utf8(code), "PBKDF2", false, ["deriveKey"]);
  return subtle.deriveKey({ name: "PBKDF2", hash: "SHA-256", salt, iterations }, ikm, { name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
}

// A new recovery code: 15 random bytes as 24 Crockford characters in six groups of four.
export function newRecoveryCode() {
  const bytes = randomBytes(15);
  let bits = 0, acc = 0, out = "";
  for (const b of bytes) { acc = (acc << 8) | b; bits += 8; while (bits >= 5) { bits -= 5; out += CROCKFORD[(acc >> bits) & 31]; } acc &= (1 << bits) - 1; }
  return out.match(/.{4}/g).join("-");
}
// What the founder typed, as the code: case and separators ignored, and the letters Crockford reads as
// digits (O as 0, I and L as 1) taken so. "" when it cannot be a code.
export function normalizeRecoveryCode(typed) {
  if (typeof typed !== "string") return "";
  const t = typed.toUpperCase().replace(/[\s-]/g, "").replace(/O/g, "0").replace(/[IL]/g, "1");
  if (!/^[0-9A-HJKMNP-TV-Z]{24}$/.test(t)) return "";
  return t.match(/.{4}/g).join("-");
}

// A new phone identity key: { privateKey (non-extractable, ECDH), publicPoint, pkcs8 }. pkcs8 is the
// private key's bytes, to wrap; the caller wipes it (wipe) once every wrap is made.
export async function newPhoneKey() {
  const kp = await subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]);
  const pkcs8 = new Uint8Array(await subtle.exportKey("pkcs8", kp.privateKey));
  const publicPoint = new Uint8Array(await subtle.exportKey("raw", kp.publicKey));
  return { privateKey: await importPhoneKey(pkcs8), publicPoint, pkcs8 };
}
export function wipe(bytes) { if (bytes) bytes.fill(0); }
async function importPhoneKey(pkcs8) { return subtle.importKey("pkcs8", pkcs8, { name: "ECDH", namedCurve: "P-256" }, false, ["deriveBits"]); }

async function seal(kind, aesKey, pkcs8, horde, agreeKeyId, extra) {
  const iv = randomBytes(12);
  const ct = new Uint8Array(await subtle.encrypt({ name: "AES-GCM", iv, additionalData: aadOf(kind, horde, agreeKeyId) }, aesKey, pkcs8));
  return { v: 1, kind, iv: b64u(iv), ct: b64u(ct), ...extra };
}

export async function wrapWithPrf(pkcs8, prfOutput, horde, agreeKeyId) { return seal("prf", await prfWrapKey(prfOutput), pkcs8, horde, agreeKeyId, {}); }
export async function wrapWithRecovery(pkcs8, code, horde, agreeKeyId, iterations = RECOVERY_ITERATIONS) {
  const salt = randomBytes(16);
  return seal("recovery", await recoveryWrapKey(code, salt, iterations), pkcs8, horde, agreeKeyId, { salt: b64u(salt), iterations });
}

// Unwrap one record to the phone identity key: { ok, reason, value: { privateKey, publicPoint } }.
// secret is the PRF output (prf) or the typed code (recovery). The key
// unwrapped must be the one the record says, checked by agreeing with it. keepBytes also hands back
// the key's PKCS#8 bytes (value.pkcs8), to wrap again; the caller wipes them.
export async function unwrap(record, secret, horde, agreeKeyId, publicPoint, { keepBytes = false } = {}) {
  const no = (reason) => ({ ok: false, reason, value: null });
  if (!record || record.v !== 1) return no("there is no such key wrap");
  let aesKey;
  try {
    if (record.kind === "prf") aesKey = await prfWrapKey(secret);
    else if (record.kind === "recovery") {
      const code = normalizeRecoveryCode(secret);
      if (!code) return no("that is not a recovery code: six groups of four letters and digits");
      if (!Number.isSafeInteger(record.iterations) || record.iterations < 100000) return no("the recovery wrap's work factor is not one this app accepts");
      aesKey = await recoveryWrapKey(code, unb64u(record.salt), record.iterations);
    } else return no("an unknown kind of key wrap: " + record.kind);
  } catch (x) { return no("the wrapping key could not be made: " + x.message); }
  let pkcs8;
  try { pkcs8 = new Uint8Array(await subtle.decrypt({ name: "AES-GCM", iv: unb64u(record.iv), additionalData: aadOf(record.kind, horde, agreeKeyId) }, aesKey, unb64u(record.ct))); }
  catch (x) { return no(record.kind === "recovery" ? "the recovery code does not open this horde's key" : "the key wrap does not open"); }
  try {
    const privateKey = await importPhoneKey(pkcs8);
    // The private key alone does not give back its public point through WebCrypto; it is checked
    // instead by agreeing with it: an ECDH with a throwaway key must match from both sides.
    const probe = await subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, false, ["deriveBits"]);
    const probePub = new Uint8Array(await subtle.exportKey("raw", probe.publicKey));
    const pubKey = await subtle.importKey("raw", publicPoint, { name: "ECDH", namedCurve: "P-256" }, false, []);
    const a = new Uint8Array(await subtle.deriveBits({ name: "ECDH", public: await subtle.importKey("raw", probePub, { name: "ECDH", namedCurve: "P-256" }, false, []) }, privateKey, 256));
    const b = new Uint8Array(await subtle.deriveBits({ name: "ECDH", public: pubKey }, probe.privateKey, 256));
    if (await keyId(publicPoint) !== agreeKeyId || a.length !== b.length || !a.every((x, i) => x === b[i])) return no("the unwrapped key is not this horde's phone key");
    return { ok: true, reason: "", value: { privateKey, publicPoint, pkcs8: keepBytes ? pkcs8.slice() : null } };
  } finally { wipe(pkcs8); }
}
