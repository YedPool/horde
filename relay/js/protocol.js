// relay/js/protocol.js - the phone's side of the relay protocol, in JavaScript: every byte a phone
// sends or checks, written once and run by both the PWA (surfaces/pwa/) and the test phone
// (test/fixtures/relay/phone/phone.mjs), so the two can never speak two dialects.
//
// THE SPECIFICATION IS THE POWERSHELL. Each section names the machine-side file whose strings it
// copies: relay/Envelope.ps1, relay/Hpke.ps1, relay/Pairing.ps1, relay/Trust.ps1 and
// channels/decisions/Channel.ps1. A string here that differs from its twin there is a bug here; the
// end-to-end suites (test/test-relay-phone-e2e.ps1, surfaces/pwa/test/test-pwa-phone-e2e.ps1) put
// what this file makes through the real machine code.
//
// BROWSER-SAFE: WebCrypto (globalThis.crypto.subtle), TextEncoder and TextDecoder only - no Node
// module, no Buffer, no DOM. Nothing here holds a key between calls or keeps any state: a caller hands
// in what a step needs (a passkey to assert with, the phone identity key to open with) and gets bytes
// and text back.
//
// A PASSKEY IS A FUNCTION here: assert(challenge) -> { authenticatorData, clientDataJSON, signature }
// (Uint8Arrays; signature DER, as WebAuthn returns it). The PWA's is navigator's credential get; the
// test phone's is a software authenticator. This file never sees which.
//
// EVERY READER OF FAR-END INPUT ANSWERS { ok, reason, value } and never throws for the input itself.

const subtle = globalThis.crypto.subtle;
const encoder = new TextEncoder();
const strictDecoder = new TextDecoder("utf-8", { fatal: true });

// --- bytes ---

export function utf8(text) { return encoder.encode(text); }
export function fromUtf8(bytes) { return strictDecoder.decode(bytes); }
export function cat(...parts) {
  let n = 0;
  for (const p of parts) n += p.length;
  const out = new Uint8Array(n);
  let i = 0;
  for (const p of parts) { out.set(p, i); i += p.length; }
  return out;
}
export function equalBytes(a, b) {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a[i] ^ b[i];
  return d === 0;
}
export function randomBytes(n) { return globalThis.crypto.getRandomValues(new Uint8Array(n)); }
export async function sha256(bytes) { return new Uint8Array(await subtle.digest("SHA-256", bytes)); }

const B64U = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
const B64U_INDEX = (() => { const t = new Int16Array(128).fill(-1); for (let i = 0; i < 64; i++) t[B64U.charCodeAt(i)] = i; return t; })();
export function b64u(bytes) {
  let out = "";
  let i = 0;
  for (; i + 2 < bytes.length; i += 3) {
    const n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    out += B64U[n >> 18] + B64U[(n >> 12) & 63] + B64U[(n >> 6) & 63] + B64U[n & 63];
  }
  if (i + 1 === bytes.length) { const n = bytes[i] << 16; out += B64U[n >> 18] + B64U[(n >> 12) & 63]; }
  else if (i + 2 === bytes.length) { const n = (bytes[i] << 16) | (bytes[i + 1] << 8); out += B64U[n >> 18] + B64U[(n >> 12) & 63] + B64U[(n >> 6) & 63]; }
  return out;
}
// Strict, as relay/Bytes.ps1 reads it: the URL alphabet only, no padding, no length that is not a
// whole number of bytes, and no stray bits in the last character - so every byte string has ONE
// spelling. Throws: callers that read far-end input catch it and say which field.
export function unb64u(text) {
  if (typeof text !== "string" || text.length % 4 === 1) throw new Error("not base64url");
  const out = new Uint8Array(Math.floor(text.length * 3 / 4));
  let o = 0, acc = 0, bits = 0;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    const v = c < 128 ? B64U_INDEX[c] : -1;
    if (v < 0) throw new Error("not base64url");
    acc = ((acc << 6) | v) & 0xffff; bits += 6;
    if (bits >= 8) { bits -= 8; out[o++] = (acc >> bits) & 255; }
  }
  if (bits > 0 && (acc & ((1 << bits) - 1)) !== 0) throw new Error("not base64url: stray bits at the end");
  return out;
}
export function hex(bytes) { let s = ""; for (const b of bytes) s += (b < 16 ? "0" : "") + b.toString(16); return s; }
export function unhex(text) {
  if (typeof text !== "string" || !/^(?:[0-9a-f]{2})*$/.test(text)) throw new Error("not lower-case hex");
  const out = new Uint8Array(text.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(text.substr(i * 2, 2), 16);
  return out;
}
// relay/P256.ps1's Get-HordeRelayKeyId: the first 16 bytes of SHA-256 of the 65-byte point, as hex.
export async function keyId(point) {
  if (!(point instanceof Uint8Array) || point.length !== 65 || point[0] !== 4) throw new Error("a P-256 public key is 65 bytes, 0x04 then X then Y");
  return hex((await sha256(point)).slice(0, 16));
}

// --- HKDF and HPKE (relay/Hpke.ps1: RFC 9180 base mode, DHKEM(P-256, HKDF-SHA256), HKDF-SHA256, AES-256-GCM) ---

async function hmac(key, data) {
  const k = await subtle.importKey("raw", key.length ? key : new Uint8Array(32), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await subtle.sign("HMAC", k, data));
}
async function expand(prk, info, len) {
  let t = new Uint8Array(0), out = new Uint8Array(0);
  for (let i = 1; out.length < len; i++) { t = await hmac(prk, cat(t, info, new Uint8Array([i]))); out = cat(out, t); }
  return out.slice(0, len);
}
const KEM_ID = cat(utf8("KEM"), new Uint8Array([0x00, 0x10]));
const SUITE_ID = cat(utf8("HPKE"), new Uint8Array([0x00, 0x10, 0x00, 0x01, 0x00, 0x02]));
const hpkeLabel = (suite, l) => cat(utf8("HPKE-v1"), suite, utf8(l));
const labeledExtract = (salt, suite, l, ikm) => hmac(salt, cat(hpkeLabel(suite, l), ikm));
const labeledExpand = (prk, suite, l, info, len) => expand(prk, cat(new Uint8Array([len >> 8, len & 255]), hpkeLabel(suite, l), info), len);
export async function ecdh(privateKey, publicPoint) {
  const pub = await subtle.importKey("raw", publicPoint, { name: "ECDH", namedCurve: "P-256" }, false, []);
  return new Uint8Array(await subtle.deriveBits({ name: "ECDH", public: pub }, privateKey, 256));
}
async function sharedSecret(dh, encBytes, pkR) {
  const prk = await labeledExtract(new Uint8Array(0), KEM_ID, "eae_prk", dh);
  return labeledExpand(prk, KEM_ID, "shared_secret", cat(encBytes, pkR), 32);
}
async function keySchedule(ss, info) {
  const e = new Uint8Array(0);
  const ksc = cat(new Uint8Array([0]), await labeledExtract(e, SUITE_ID, "psk_id_hash", e), await labeledExtract(e, SUITE_ID, "info_hash", info));
  const secret = await labeledExtract(ss, SUITE_ID, "secret", e);
  return { key: await labeledExpand(secret, SUITE_ID, "key", ksc, 32), nonce: await labeledExpand(secret, SUITE_ID, "base_nonce", ksc, 12) };
}
export async function gcmSeal(key, nonce, aad, plaintext) {
  const k = await subtle.importKey("raw", key, "AES-GCM", false, ["encrypt"]);
  return new Uint8Array(await subtle.encrypt({ name: "AES-GCM", iv: nonce, additionalData: aad }, k, plaintext));
}
export async function gcmOpen(key, nonce, aad, sealed) {
  const k = await subtle.importKey("raw", key, "AES-GCM", false, ["decrypt"]);
  return new Uint8Array(await subtle.decrypt({ name: "AES-GCM", iv: nonce, additionalData: aad }, k, sealed));
}
// Single-shot Seal (sequence 0). ephemeral is for the RFC 9180 vectors only: an ECDH key pair
// { privateKey, publicPoint }; without it a fresh one is made, as it must be.
export async function hpkeSeal(pkR, info, aad, plaintext, ephemeral = null) {
  let eph = ephemeral;
  if (!eph) {
    const kp = await subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, false, ["deriveBits"]);
    eph = { privateKey: kp.privateKey, publicPoint: new Uint8Array(await subtle.exportKey("raw", kp.publicKey)) };
  }
  const ks = await keySchedule(await sharedSecret(await ecdh(eph.privateKey, pkR), eph.publicPoint, pkR), info);
  return { enc: eph.publicPoint, sealed: await gcmSeal(ks.key, ks.nonce, aad, plaintext) };
}
export async function hpkeOpen(privateKey, pkR, encBytes, info, aad, sealed) {
  const ks = await keySchedule(await sharedSecret(await ecdh(privateKey, encBytes), encBytes, pkR), info);
  return gcmOpen(ks.key, ks.nonce, aad, sealed);
}

// --- the envelope (relay/Envelope.ps1: the strings below are its whole specification) ---

const AAD = "horde-relay/envelope/v1 aad\n";
const INFO = "horde-relay/envelope/v1 content-key";
const SIGNED = "horde-relay/envelope/v1 signed\n";
const WORD = /^[a-z][a-z0-9-]{0,31}$/;
const KEY_ID = /^[0-9a-f]{32}$/;
const NONCE = /^[0-9a-f]{24}$/;
const B64U_TEXT = /^[A-Za-z0-9_-]*$/;
const MAX_INTEGER = 9007199254740991;

export function headerText(h) {
  return '{"v":1,"kind":"' + h.kind + '","channel":"' + h.channel + '","from":"' + h.from + '","to":[' + h.to.map((t) => '"' + t + '"').join(",") +
    '],"seq":' + h.seq + ',"nonce":"' + h.nonce + '","ts":' + h.ts + "}";
}
export function recipientsText(rs) { return "[" + rs.map((r) => '{"kid":"' + r.kid + '","enc":"' + r.enc + '","key":"' + r.key + '"}').join(",") + "]"; }
export function signedBytes(ht, rt, ct) { return utf8(SIGNED + ht + "\n" + rt + "\n" + ct); }
// relay/Envelope.ps1's Get-HordeRelayReplayKey: what identifies an envelope, never a hash of its text.
export function replayKey(h) { return h.from + "/" + h.channel + "/" + h.seq + "/" + h.nonce; }

// Seal a body to one recipient (a machine's agree key): { header, ht, rt, ctText }, unsigned.
export async function sealEnvelope({ kind, channel, from, seq, ts, recipientPublic, body }) {
  if (!WORD.test(kind) || !WORD.test(channel) || !KEY_ID.test(from)) throw new Error("the envelope's kind, channel or sender is not well formed");
  if (!Number.isSafeInteger(seq) || seq < 0 || !Number.isSafeInteger(ts) || ts < 0) throw new Error("the envelope's seq and ts are whole numbers from 0 to 2^53-1");
  const header = { kind, channel, from, to: [await keyId(recipientPublic)], seq, nonce: hex(randomBytes(12)), ts };
  const ht = headerText(header);
  const aad = utf8(AAD + ht);
  const cek = randomBytes(32);
  const ct = await gcmSeal(cek, unhex(header.nonce), aad, body);
  const box = await hpkeSeal(recipientPublic, utf8(INFO), aad, cek);
  cek.fill(0);
  const rt = recipientsText([{ kid: header.to[0], enc: b64u(box.enc), key: b64u(box.sealed) }]);
  return { header, ht, rt, ctText: b64u(ct) };
}
// Sign sealed parts with a passkey: the envelope's wire text. The challenge is SHA-256 of the signed
// bytes (relay/WebAuthn.ps1 checks exactly that).
export async function signEnvelope(parts, assert) {
  const a = await assert(await sha256(signedBytes(parts.ht, parts.rt, parts.ctText)));
  const sig = '{"alg":"webauthn.get","authenticatorData":"' + b64u(a.authenticatorData) + '","clientDataJSON":"' + b64u(a.clientDataJSON) + '","signature":"' + b64u(a.signature) + '"}';
  return '{"header":' + parts.ht + ',"recipients":' + parts.rt + ',"ct":"' + parts.ctText + '","sig":' + sig + "}";
}
// The signed parts of an envelope text, to sign the same content again (what a passkey may do).
export function envelopeParts(text) {
  const e = JSON.parse(text);
  return { header: e.header, ht: headerText(e.header), rt: recipientsText(e.recipients), ctText: e.ct };
}

// Open a machine's envelope: verify its ES256 signature under the signing key pinned at pairing, then
// open the body with the phone identity key. { ok, reason, value: { header, key, body (bytes) } }.
//   machine      { keyId, signPublic (65 bytes) }   from the pairing offer
//   phone        { privateKey (ECDH CryptoKey), publicPoint (65 bytes) }
export async function openEnvelope(text, machine, phone) {
  const no = (reason) => ({ ok: false, reason, value: null });
  if (typeof text !== "string" || text.length > 1414507 || !/^[\x20-\x7e]+$/.test(text)) return no("not an envelope text");
  let e;
  try { e = JSON.parse(text); } catch (x) { return no("not JSON"); }
  const h = e && e.header;
  if (!h || typeof h !== "object" || !Array.isArray(e.recipients) || typeof e.ct !== "string" || !e.sig || typeof e.sig.value !== "string") return no("not an envelope");
  if (typeof h.kind !== "string" || !WORD.test(h.kind) || typeof h.channel !== "string" || !WORD.test(h.channel) || typeof h.from !== "string" || !KEY_ID.test(h.from) ||
    !Array.isArray(h.to) || h.to.length < 1 || h.to.length > 8 || !h.to.every((t) => typeof t === "string" && KEY_ID.test(t)) ||
    !Number.isSafeInteger(h.seq) || h.seq < 0 || h.seq > MAX_INTEGER || !Number.isSafeInteger(h.ts) || h.ts < 0 || typeof h.nonce !== "string" || !NONCE.test(h.nonce)) return no("the header is not well formed");
  if (e.recipients.length !== h.to.length || !e.recipients.every((r, i) => r && r.kid === h.to[i] && typeof r.enc === "string" && B64U_TEXT.test(r.enc) && typeof r.key === "string" && B64U_TEXT.test(r.key))) return no("the recipients do not match the header");
  if (!B64U_TEXT.test(e.ct) || !B64U_TEXT.test(e.sig.value)) return no("a field is not base64url");
  const ht = headerText(h);
  const rt = recipientsText(e.recipients);
  if ('{"header":' + ht + ',"recipients":' + rt + ',"ct":"' + e.ct + '","sig":{"alg":"ES256","value":"' + e.sig.value + '"}}' !== text) return no("not canonical, or not signed ES256");
  if (h.from !== machine.keyId || h.from !== await keyId(machine.signPublic)) return no("not from the machine this phone paired with");
  let verified = false;
  try {
    const pub = await subtle.importKey("raw", machine.signPublic, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
    verified = await subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pub, unb64u(e.sig.value), signedBytes(ht, rt, e.ct));
  } catch (x) { verified = false; }
  if (!verified) return no("the machine's signature does not verify");
  const mine = await keyId(phone.publicPoint);
  const r = e.recipients.find((x) => x.kid === mine);
  if (!r) return no("not sealed to this phone");
  const aad = utf8(AAD + ht);
  try {
    const cek = await hpkeOpen(phone.privateKey, phone.publicPoint, unb64u(r.enc), utf8(INFO), aad, unb64u(r.key));
    const body = await gcmOpen(cek, unhex(h.nonce), aad, unb64u(e.ct));
    cek.fill(0);
    return { ok: true, reason: "", value: { header: h, key: replayKey(h), body } };
  } catch (x) { return no("it does not open: " + x.message); }
}

// --- CBOR, reading only: what a registration's attestationObject holds (relay/Cbor.ps1 reads it on the machine) ---

function cborRead(bytes, at, depth) {
  if (depth > 8) throw new Error("CBOR nested too deep");
  if (at >= bytes.length) throw new Error("CBOR ends early");
  const first = bytes[at];
  const major = first >> 5;
  const info = first & 31;
  let n, p = at + 1;
  if (info < 24) n = info;
  else if (info === 24) { n = bytes[p]; p += 1; }
  else if (info === 25) { n = (bytes[p] << 8) | bytes[p + 1]; p += 2; }
  else if (info === 26) { n = ((bytes[p] << 24) >>> 0) + (bytes[p + 1] << 16) + (bytes[p + 2] << 8) + bytes[p + 3]; p += 4; }
  else throw new Error("CBOR length form not supported here");
  if (p > bytes.length) throw new Error("CBOR ends early");
  if (major === 0) return { value: n, end: p };
  if (major === 1) return { value: -1 - n, end: p };
  if (major === 2 || major === 3) {
    if (p + n > bytes.length) throw new Error("CBOR ends early");
    const raw = bytes.slice(p, p + n);
    return { value: major === 2 ? raw : fromUtf8(raw), end: p + n };
  }
  if (major === 4) { const a = []; for (let i = 0; i < n; i++) { const r = cborRead(bytes, p, depth + 1); a.push(r.value); p = r.end; } return { value: a, end: p }; }
  if (major === 5) { const m = new Map(); for (let i = 0; i < n; i++) { const k = cborRead(bytes, p, depth + 1); const v = cborRead(bytes, k.end, depth + 1); if (m.has(k.value)) throw new Error("CBOR map repeats a key"); m.set(k.value, v.value); p = v.end; } return { value: m, end: p }; }
  if (major === 7 && (info === 20 || info === 21)) return { value: info === 21, end: p };
  throw new Error("CBOR item not supported here");
}
export function cborDecode(bytes, at = 0) { return cborRead(bytes, at, 0); }

// The credential a registration made, from its attestationObject: { credentialId, publicPoint, flags }.
// Read with the same rules the machine applies (relay/Registration.ps1), so a phone that shows a
// fingerprint shows the one the machine will compute.
export function credentialFromAttestation(attestationObject) {
  try {
    const top = cborDecode(attestationObject);
    if (top.end !== attestationObject.length || !(top.value instanceof Map)) return { ok: false, reason: "the attestationObject is not one CBOR map", value: null };
    const ad = top.value.get("authData");
    if (!(ad instanceof Uint8Array) || ad.length < 55) return { ok: false, reason: "the attestationObject has no authData with a credential", value: null };
    const flags = ad[32];
    if ((flags & 0x40) === 0) return { ok: false, reason: "authData carries no attested credential", value: null };
    const idLen = (ad[53] << 8) | ad[54];
    const credentialId = ad.slice(55, 55 + idLen);
    const cose = cborDecode(ad, 55 + idLen);
    const m = cose.value;
    if (!(m instanceof Map) || m.get(1) !== 2 || m.get(3) !== -7 || m.get(-1) !== 1) return { ok: false, reason: "the credential is not an ES256 P-256 key", value: null };
    const x = m.get(-2), y = m.get(-3);
    if (!(x instanceof Uint8Array) || !(y instanceof Uint8Array) || x.length !== 32 || y.length !== 32) return { ok: false, reason: "the credential's point is not 32 + 32 bytes", value: null };
    return { ok: true, reason: "", value: { credentialId, publicPoint: cat(new Uint8Array([4]), x, y), flags, rpIdHash: ad.slice(0, 32) } };
  } catch (x) { return { ok: false, reason: "the attestationObject does not read: " + x.message, value: null }; }
}

// --- pairing (relay/Pairing.ps1) ---

const OFFER_FIELDS = ["v", "kind", "horde", "offer", "code", "machine", "signPublic", "agreeKeyId", "agreePublic", "mailbox", "rpId", "origins", "issuedAt", "expiresAt"];
const LABEL = /^[\x21\x23-\x5b\x5d-\x7e](?:[\x20\x21\x23-\x5b\x5d-\x7e]{0,62}[\x21\x23-\x5b\x5d-\x7e])?$/;
export const PAIRING_CHALLENGE_DOMAIN = "horde-relay/pairing/v1 challenge\n";

// The offer's text, read: { ok, reason, value }. value holds the offer's fields (the keys as their
// base64url text), the signing and agreement points as bytes (signPoint, agreePoint), and text - the offer EXACTLY as given, which the challenge hashes.
// Checked as far as a phone can: the shape, the keys' ids, the mailbox, the expiry. Whether the
// machine made it is the machine's to say when the response comes back.
export async function readOffer(text, now = Date.now()) {
  const no = (reason) => ({ ok: false, reason, value: null });
  if (typeof text !== "string") return no("the pairing offer is not text");
  text = text.trim();
  if (text.length > 4096 || !/^[\x20-\x7e]+$/.test(text)) return no("the pairing offer is not a short ASCII text");
  let o;
  try { o = JSON.parse(text); } catch (x) { return no("the pairing offer is not JSON"); }
  if (!o || typeof o !== "object" || Array.isArray(o)) return no("the pairing offer is not a JSON object");
  const names = Object.keys(o);
  if (names.join(",") !== OFFER_FIELDS.join(",")) return no("the pairing offer's members are not " + OFFER_FIELDS.join(", "));
  if (o.v !== 1 || o.kind !== "horde-relay-pairing-offer") return no("this is not a version 1 pairing offer");
  if (typeof o.horde !== "string" || !/^[a-z0-9][a-z0-9-]{0,62}$/.test(o.horde)) return no("the offer's horde is not a horde name");
  if (typeof o.machine !== "string" || !KEY_ID.test(o.machine) || typeof o.agreeKeyId !== "string" || !KEY_ID.test(o.agreeKeyId)) return no("the offer's key ids are not key ids");
  if (typeof o.mailbox !== "string" || o.mailbox !== o.horde + "/" + o.machine) return no("the offer's mailbox is not its horde and machine");
  if (typeof o.rpId !== "string" || !/^[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$/.test(o.rpId)) return no("the offer's rpId is not a relying party id");
  if (!Array.isArray(o.origins) || o.origins.length < 1 || o.origins.length > 8 || !o.origins.every((x) => typeof x === "string")) return no("the offer's origins are not a list of origins");
  if (!Number.isSafeInteger(o.issuedAt) || !Number.isSafeInteger(o.expiresAt)) return no("the offer's times are not whole numbers");
  if (now >= o.expiresAt) return no("the pairing offer has expired: ask the machine for a new one");
  let signPoint, agreePoint;
  try { signPoint = unb64u(o.signPublic); agreePoint = unb64u(o.agreePublic); } catch (x) { return no("the offer's keys are not base64url"); }
  try {
    if (await keyId(signPoint) !== o.machine) return no("the offer's signing key is not the machine it names");
    if (await keyId(agreePoint) !== o.agreeKeyId) return no("the offer's agreement key is not the one it names");
  } catch (x) { return no("the offer's keys are not P-256 points"); }
  return { ok: true, reason: "", value: { ...o, text, signPoint, agreePoint } };
}
export async function pairingChallenge(offerText) { return sha256(utf8(PAIRING_CHALLENGE_DOMAIN + offerText)); }
// relay/Pairing.ps1's fingerprint: SHA-256 of the domain, the challenge, the point, the credential id's
// length (2 bytes) and the id, and the rpId; the first 8 bytes as a number modulo 10^12, as dddd-dddd-dddd.
export async function pairingFingerprint({ challenge, publicPoint, credentialId, rpId }) {
  const fh = await sha256(cat(utf8("horde-relay/pairing/v1 fingerprint\n"), challenge, publicPoint, new Uint8Array([credentialId.length >> 8, credentialId.length & 255]), credentialId, utf8(rpId)));
  let n = 0n;
  for (let i = 0; i < 8; i++) n = (n * 256n + BigInt(fh[i])) % 1000000000000n;
  const d = n.toString().padStart(12, "0");
  return d.slice(0, 4) + "-" + d.slice(4, 8) + "-" + d.slice(8, 12);
}
export function validLabel(label) { return typeof label === "string" && LABEL.test(label); }
// relay/Pairing.ps1's New-HordeRelayPairingResponseText, the one spelling Complete reads.
export function pairingResponseText({ offer, code, rawId, clientDataJSON, attestationObject, label, prf }) {
  if (!validLabel(label)) throw new Error("a device label is 1 to 64 printable characters, no quote or backslash, not starting or ending with a space");
  return '{"v":1,"kind":"horde-relay-pairing-response","offer":"' + offer + '","code":"' + code + '","rawId":"' + b64u(rawId) + '","clientDataJSON":"' + b64u(clientDataJSON) +
    '","attestationObject":"' + b64u(attestationObject) + '","label":"' + label + '","prf":' + (prf ? "true" : "false") + "}";
}

// --- the phone identity key (relay/Trust.ps1, PHONE KEYS; channels/trust/Channel.ps1) ---

// The vouch: SHA-256 of the domain, the horde and the key, each on its own line.
export async function vouchChallenge(horde, agreePublic) { return sha256(utf8("horde-relay/phone-key/v1 vouch\n" + horde + "\n" + b64u(agreePublic))); }
export function phoneKeyBody(agreePublic, vouch) {
  return utf8('{"v":1,"agreePublic":"' + b64u(agreePublic) + '","authenticatorData":"' + b64u(vouch.authenticatorData) + '","clientDataJSON":"' + b64u(vouch.clientDataJSON) + '","signature":"' + b64u(vouch.signature) + '"}');
}

// --- the decisions channel (channels/decisions/Channel.ps1) ---

// The answer body: JSON.stringify escapes what JSON must and nothing else; the machine reads it with a
// strict JSON parser that wants exactly these members.
export function answerBody({ answerId, machine, snapshot, number, wordingVersion, text }) {
  if (!/^[0-9a-f]{32}$/.test(answerId)) throw new Error("an answerId is 32 lower-case hex");
  if (!KEY_ID.test(machine)) throw new Error("the machine is a key id");
  if (typeof snapshot !== "string" || snapshot.length > 160 || snapshot.indexOf(machine + "/decisions/") !== 0) throw new Error("the snapshot is that machine's envelope's replay key");
  if (!Number.isSafeInteger(number) || number < 1 || !Number.isSafeInteger(wordingVersion) || wordingVersion < 1) throw new Error("number and wordingVersion are whole numbers from 1");
  if (typeof text !== "string") throw new Error("the answer is text");
  return utf8(JSON.stringify({ v: 1, answerId, machine, snapshot, number, wordingVersion, text }));
}

// A snapshot page, read: { ok, reason, value }. The page must be the decisions snapshot of the machine
// that signed its envelope, for the horde the phone paired with.
export function readSnapshotPage(bodyBytes, horde, machine) {
  const no = (reason) => ({ ok: false, reason, value: null });
  let p;
  try { p = JSON.parse(fromUtf8(bodyBytes)); } catch (x) { return no("the snapshot page is not JSON"); }
  if (!p || p.v !== 1 || p.kind !== "decisions-snapshot") return no("not a version 1 decisions snapshot");
  if (p.horde !== horde || p.machine !== machine) return no("the snapshot names another horde or machine");
  if (typeof p.snapshot !== "string" || !/^[0-9a-f]{64}$/.test(p.snapshot)) return no("the snapshot has no hash");
  if (!Number.isSafeInteger(p.page) || !Number.isSafeInteger(p.pages) || p.page < 1 || p.page > p.pages || p.pages > 10000) return no("the page numbers do not hold together");
  if (!Array.isArray(p.questions) || !Array.isArray(p.withheld)) return no("the snapshot has no questions list");
  return { ok: true, reason: "", value: p };
}

// The newest COMPLETE snapshot among opened pages: { snapshot, seq, pages, questions (each with the
// replay key of the page that carried it, as pageKey), withheld, counts } or null. pages is a list of
// { key, seq, page } from openEnvelope + readSnapshotPage. A snapshot is complete when every page
// 1..pages is there; the newest is the one whose last page has the highest envelope seq. A page
// repeated (the relay may repeat) counts once.
export function newestSnapshot(pages) {
  const groups = new Map();
  for (const p of pages) {
    const g = groups.get(p.page.snapshot) || { byNumber: new Map(), pages: p.page.pages, seq: -1 };
    if (g.pages !== p.page.pages) continue;
    if (!g.byNumber.has(p.page.page)) g.byNumber.set(p.page.page, p);
    if (p.seq > g.seq) g.seq = p.seq;
    groups.set(p.page.snapshot, g);
  }
  let best = null;
  for (const [hash, g] of groups) {
    if (g.byNumber.size !== g.pages) continue;
    if (best && best.seq >= g.seq) continue;
    const ordered = [...g.byNumber.keys()].sort((a, b) => a - b).map((n) => g.byNumber.get(n));
    const questions = [];
    for (const p of ordered) for (const q of p.page.questions) questions.push({ question: q, pageKey: p.key });
    const first = ordered[0].page;
    best = { snapshot: hash, seq: g.seq, firstSeq: Math.min(...ordered.map((p) => p.relaySeq || 0)), questions, withheld: first.withheld, counts: first.counts, unreadable: first.unreadable, notUnderstood: first.notUnderstood };
  }
  return best;
}
