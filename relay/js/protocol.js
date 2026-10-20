// relay/js/protocol.js - the phone's side of the relay protocol, in JavaScript: every byte a phone
// sends or checks, written once and run by both the PWA (surfaces/pwa/) and the test phone
// (test/fixtures/relay/phone/phone.mjs), so the two can never speak two dialects.
//
// THE SPECIFICATION IS THE POWERSHELL. Each section names the machine-side file whose strings it
// copies: relay/Envelope.ps1, relay/Hpke.ps1, relay/Pairing.ps1, relay/Trust.ps1 and
// channels/decisions/Channel.ps1, channels/chat/Channel.ps1, channels/progress/Channel.ps1 and channels/cards/Channel.ps1. A string here that differs from its twin there is a bug here; the
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

const OFFER_FIELDS = ["v", "kind", "horde", "offer", "code", "machine", "label", "signPublic", "agreeKeyId", "agreePublic", "mailbox", "pairMailbox", "rpId", "origins", "issuedAt", "expiresAt", "grant"];
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
  // The offer's id and code go back in the response (review of a8b732d, finding 3): read as
  // relay/Records.ps1 spells them, so nothing the offer carries can reshape the response.
  if (typeof o.offer !== "string" || !/^[0-9a-f]{32}$/.test(o.offer)) return no("the offer's id is not 32 lower-case hex");
  if (typeof o.code !== "string" || !/^[A-Za-z0-9_-]{16,128}$/.test(o.code)) return no("the offer's code is not base64url");
  if (typeof o.machine !== "string" || !KEY_ID.test(o.machine) || typeof o.agreeKeyId !== "string" || !KEY_ID.test(o.agreeKeyId)) return no("the offer's key ids are not key ids");
  // The machine's name, as its grant signs it (ACCOUNT GRANT, below): what the Account screen shows.
  if (!validLabel(o.label)) return no("the offer's machine label is not a label");
  if (typeof o.mailbox !== "string" || o.mailbox !== o.horde + "/" + o.machine) return no("the offer's mailbox is not its horde and machine");
  // relay/Pairing.ps1's Get-HordeRelayPairingMailbox: the offer's own mailbox, so nothing in an offer
  // can send the response anywhere else.
  if (typeof o.pairMailbox !== "string" || o.pairMailbox !== o.horde + "/pair-" + o.offer) return no("the offer's pairing mailbox is not its horde and offer");
  if (typeof o.rpId !== "string" || !/^[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$/.test(o.rpId)) return no("the offer's rpId is not a relying party id");
  if (!Array.isArray(o.origins) || o.origins.length < 1 || o.origins.length > 8 || !o.origins.every((x) => typeof x === "string")) return no("the offer's origins are not a list of origins");
  if (!Number.isSafeInteger(o.issuedAt) || !Number.isSafeInteger(o.expiresAt)) return no("the offer's times are not whole numbers");
  if (now >= o.expiresAt) return no("the pairing offer has expired: ask the machine for a new one");
  // The account grant (ACCOUNT GRANT, below): its shape here, 64 bytes; its signature below.
  if (typeof o.grant !== "string" || !/^[A-Za-z0-9_-]{86}$/.test(o.grant)) return no("the offer's account grant is not a signature");
  let signPoint, agreePoint;
  try { signPoint = unb64u(o.signPublic); agreePoint = unb64u(o.agreePublic); } catch (x) { return no("the offer's keys are not base64url"); }
  try {
    if (await keyId(signPoint) !== o.machine) return no("the offer's signing key is not the machine it names");
    if (await keyId(agreePoint) !== o.agreeKeyId) return no("the offer's agreement key is not the one it names");
  } catch (x) { return no("the offer's keys are not P-256 points"); }
  // THE GRANT IS VERIFIED HERE TOO, under the very key the offer names (review of PR 301, a must-fix): a
  // phone that asked to join gets its offer through the relay, and a relay could otherwise make an offer
  // naming a machine's key and name with no machine behind them. Only the holder of the signing key
  // signs its grant, so an offer whose grant does not verify is not that machine's.
  // WHAT THIS DOES NOT STOP, and it is narrower than it reads (Orc E's review, 2026-10-15): a grant
  // signs the horde, the offer, the key id, the expiry and the label, and NOTHING about the account - no
  // account id, no email. Registration (the relay's account route) checks only that the grant verifies
  // under the key it names, and the spent-grant record only stops a replay of the same offer. So anyone
  // signed in to the account - and the relay operator, who holds the code and the storage - can make a
  // fresh key, sign its own grant, and register a MADE-UP machine under any label. This check blocks
  // IMPERSONATING AN EXISTING MACHINE: putting forward a real PC's key id and name without holding that
  // PC's key. Against a made-up one what stands is that the founder picks the machine by its label, and
  // that an account member already holds his sign-in.
  let grantSig;
  try { grantSig = unb64u(o.grant); } catch (x) { return no("the offer's account grant is not a signature"); }
  if (!(await verifyMachineSignature(signPoint, accountGrantBytes(o), grantSig))) return no("the offer's account grant is not signed by the machine it names: it is not that machine's offer");
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
// relay/Pairing.ps1's New-HordeRelayPairingResponseText, the one spelling Complete reads: written by a
// JSON writer from an object whose members are in that order, every value checked first, so its text is
// the machine's canonical one and nothing in it can be read two ways.
export function pairingResponseText({ offer, code, rawId, clientDataJSON, attestationObject, label, prf }) {
  if (!validLabel(label)) throw new Error("a device label is 1 to 64 printable characters, no quote or backslash, not starting or ending with a space");
  if (typeof offer !== "string" || !/^[0-9a-f]{32}$/.test(offer)) throw new Error("the offer id is 32 lower-case hex");
  if (typeof code !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(code)) throw new Error("the offer code is base64url");
  return JSON.stringify({ v: 1, kind: "horde-relay-pairing-response", offer, code, rawId: b64u(rawId), clientDataJSON: b64u(clientDataJSON), attestationObject: b64u(attestationObject), label, prf: prf === true });
}

// relay/Pairing.ps1's THE RESPONSE THROUGH THE RELAY: the response sealed (HPKE) to the agreement key the
// offer names, the AAD binding the horde, the offer and that key, written as Get-HordeRelaySealedSpec
// spells it. The machine refuses a response over 6000 characters (Get-HordeRelayPairingLimits), so a
// longer one is refused here first. offer is readOffer's value.
export const PAIRING_LIMITS = { maxResponseChars: 6000, maxSealedChars: 8600, maxTtlSeconds: 900 };
export async function sealPairingResponse(offer, responseText) {
  if (typeof responseText !== "string" || !/^[\x20-\x7e]+$/.test(responseText) || responseText.length > PAIRING_LIMITS.maxResponseChars) throw new Error("a pairing response is 1 to 6000 printable ASCII characters");
  if (!offer || !(offer.agreePoint instanceof Uint8Array) || !/^[0-9a-f]{32}$/.test(offer.offer || "")) throw new Error("seal a response to an offer readOffer has read");
  const kid = await keyId(offer.agreePoint);
  const aad = utf8("horde-relay/pairing/v1 response aad\n" + offer.horde + "\n" + offer.offer + "\n" + kid);
  const box = await hpkeSeal(offer.agreePoint, utf8("horde-relay/pairing/v1 response-key"), aad, utf8(responseText));
  return '{"v":1,"kind":"horde-relay-pairing-sealed","offer":"' + offer.offer + '","agreeKeyId":"' + kid + '","enc":"' + b64u(box.enc) + '","ct":"' + b64u(box.sealed) + '"}';
}
// The relay key a sealed response is put under: one per offer, so a phone that sends again stores once.
export function pairingKey(offerId) { return "pairing/" + offerId; }

// relay/Pairing.ps1's ACCOUNT GRANT: the machine's ES256 signature, carried in the offer, over these
// lines. A hosted relay with accounts takes the machine's signing key into the signed-in phone's account
// only with a grant that verifies under that very key and has not expired, once per offer - so a key
// whose public half is known is still not anyone's to register without a live offer of its machine.
// The label is the machine's name (relay PR 8c), signed with the rest, so the name the Account screen
// shows is the one the machine gave.
export const ACCOUNT_GRANT_DOMAIN = "horde-relay/pairing/v1 account-grant\n";
export function accountGrantBytes({ horde, offer, machine, expiresAt, label }) { return utf8(ACCOUNT_GRANT_DOMAIN + horde + "\n" + offer + "\n" + machine + "\n" + expiresAt + "\n" + label); }

// relay/Identity.ps1's RETIREMENT RECORD, read as a relay reads it (relay PR 8c): a rotated machine
// hands the hosted relay the record its old signing key vouched for, and the relay moves the old key's
// registration to the successor named in it (the hosted relay's rotation route). Its one canonical
// form (relay/Records.ps1: these members, in this order, each of its kind; the vouch last), and the
// bytes the vouch signs: the domain, then the record with an empty vouch. { ok, reason, value } with
// value { horde, generation, signKeyId, successor, successorSignKeyId, successorSignPublic, vouch,
// signed }; never throws.
export const ROTATION_VOUCH_DOMAIN = "horde-relay/rotation/v1 vouch\n";
const RECORD_INT = "(0|[1-9][0-9]{0,15})";
const RETIRED = new RegExp("^\\{\"v\":1,\"kind\":\"horde-relay-machine-retired\",\"horde\":\"([a-z0-9][a-z0-9-]{0,62})\",\"generation\":" + RECORD_INT +
  ",\"signKeyId\":\"([0-9a-f]{32})\",\"agreeKeyId\":\"([0-9a-f]{32})\",\"successor\":" + RECORD_INT +
  ",\"successorSignKeyId\":\"([0-9a-f]{32})\",\"successorSignPublic\":\"([A-Za-z0-9_-]{87})\",\"successorAgreeKeyId\":\"([0-9a-f]{32})\",\"successorAgreePublic\":\"([A-Za-z0-9_-]{87})\"" +
  ",\"reason\":\"([\\x20\\x21\\x23-\\x5b\\x5d-\\x7e]{0,512})\",\"retiredAt\":" + RECORD_INT + ",\"agreeKeptUntil\":" + RECORD_INT + ",\"vouch\":\"([A-Za-z0-9_-]{0,8192})\"\\}$");
export function readRetirement(text) {
  const no = (reason) => ({ ok: false, reason, value: null });
  if (typeof text !== "string" || text.length > 16384) return no("the retirement record is not a short text");
  const m = RETIRED.exec(text);
  if (!m) return no("the retirement record is not in its canonical form");
  const vouch = m[13];
  if (vouch === "") return no("the retirement record carries no vouch: the old key was lost, so the machine must be paired again");
  const generation = Number(m[2]);
  const successor = Number(m[5]);
  if (!Number.isSafeInteger(generation) || !Number.isSafeInteger(successor) || successor <= generation) return no("the retirement record's successor does not come after it");
  const signed = utf8(ROTATION_VOUCH_DOMAIN + text.slice(0, text.length - vouch.length - 2) + "\"}");
  return { ok: true, reason: "", value: { horde: m[1], generation, signKeyId: m[3], successor, successorSignKeyId: m[6], successorSignPublic: m[7], vouch, signed } };
}

// relay/P256.ps1's Test-HordeRelayEs256Signature: does sig (64 bytes, r || s) verify over bytes under
// the 65-byte point, with s <= n/2 (LOW-S there: a high-S twin is refused, so one message has one
// signature)? Never throws: anything malformed is false.
const P256_HALF_ORDER = 0x7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a8n;
export async function verifyMachineSignature(point, bytes, sig) {
  try {
    if (!(point instanceof Uint8Array) || point.length !== 65 || !(sig instanceof Uint8Array) || sig.length !== 64) return false;
    if (BigInt("0x" + hex(sig.slice(32))) > P256_HALF_ORDER) return false;
    const pub = await subtle.importKey("raw", point, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
    return await subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pub, sig, bytes);
  } catch (x) { return false; }
}

// --- the phone identity key (relay/Trust.ps1, PHONE KEYS; channels/trust/Channel.ps1) ---

// The vouch: SHA-256 of the domain, the horde and the key, each on its own line.
export async function vouchChallenge(horde, agreePublic) { return sha256(utf8("horde-relay/phone-key/v1 vouch\n" + horde + "\n" + b64u(agreePublic))); }
export function phoneKeyBody(agreePublic, vouch) {
  return utf8('{"v":1,"agreePublic":"' + b64u(agreePublic) + '","authenticatorData":"' + b64u(vouch.authenticatorData) + '","clientDataJSON":"' + b64u(vouch.clientDataJSON) + '","signature":"' + b64u(vouch.signature) + '"}');
}
// relay/Trust.ps1's PHONE VOUCH ITEM (THE VOUCH TRAVELS BY ITSELF): the vouch, by itself, put into the
// machine's mailbox - ONE passkey assertion announces the phone, so it can ride the unlock's prompt.
// Its one canonical text (Get-HordeRelayPhoneVouchSpec: these members, in this order), and the relay
// key it goes under: one per passkey and phone key, so a put made again stores once.
export function phoneVouchText({ horde, by, agreePublic, vouch }) {
  if (typeof horde !== "string" || !/^[a-z0-9][a-z0-9-]{0,62}$/.test(horde)) throw new Error("the horde is a horde name");
  if (!KEY_ID.test(by)) throw new Error("the voucher is a key id");
  if (!(agreePublic instanceof Uint8Array) || agreePublic.length !== 65) throw new Error("the phone key is a 65-byte point");
  return '{"v":1,"kind":"horde-relay-phone-vouch","horde":"' + horde + '","by":"' + by + '","agreePublic":"' + b64u(agreePublic) + '","authenticatorData":"' + b64u(vouch.authenticatorData) +
    '","clientDataJSON":"' + b64u(vouch.clientDataJSON) + '","signature":"' + b64u(vouch.signature) + '"}';
}
export function phoneVouchKey(by, phoneKeyId) { return "vouch/" + by + "/" + phoneKeyId; }

// --- phone-started pairing (relay/Join.ps1) ---

// The join request item, in relay/Join.ps1's canonical form (Get-HordeRelayJoinRequestSpec). On the
// hosted relay its join route writes it (the phone sends the fields); a relay with no accounts takes it
// from the phone as written here, under the key joinKey(request).
const JOIN_TEXT = /^[\x20\x21\x23-\x5b\x5d-\x7e]{0,200}$/;
export function joinRequestText({ request, horde, machine, label, agent, requestKey, country = "", requestedAt, expiresAt }) {
  if (!/^[0-9a-f]{32}$/.test(request) || !KEY_ID.test(machine)) throw new Error("the request and the machine are ids");
  if (!/^[a-z0-9][a-z0-9-]{0,62}$/.test(horde)) throw new Error("the horde is a horde name");
  if (!validLabel(label)) throw new Error("name this phone in 1 to 64 plain characters, with no quote or backslash");
  if (!JOIN_TEXT.test(agent) || !/^[A-Z]{0,2}$/.test(country)) throw new Error("the browser and the country are plain short text");
  if (!/^[A-Za-z0-9_-]{87}$/.test(requestKey)) throw new Error("the request key is a P-256 point");
  return '{"v":1,"kind":"horde-relay-join-request","request":"' + request + '","horde":"' + horde + '","machine":"' + machine + '","label":"' + label + '","agent":"' + agent +
    '","requestKey":"' + requestKey + '","country":"' + country + '","requestedAt":' + requestedAt + ',"expiresAt":' + expiresAt + "}";
}
export function joinKey(request) { return "join/" + request; }
export function joinReplyMailbox(horde, request) { return horde + "/jr-" + request; }
export const JOIN_TTL_MS = 600000;
// The machine's answer (relay/Join.ps1, New-HordeRelayJoinOfferSealedText): the offer's text sealed to the
// request key. The offer text inside, or null when it does not open or is not for this request.
const JOIN_OFFER = /^\{"v":1,"kind":"horde-relay-join-offer","request":"([0-9a-f]{32})","requestKeyId":"([0-9a-f]{32})","enc":"([A-Za-z0-9_-]{87})","ct":"([A-Za-z0-9_-]{1,8192})"\}$/;
export async function openJoinOffer(text, { request, horde, privateKey, publicPoint }) {
  const m = typeof text === "string" ? JOIN_OFFER.exec(text) : null;
  if (!m || m[1] !== request) return null;
  const kid = await keyId(publicPoint);
  if (m[2] !== kid) return null;
  try {
    const plain = await hpkeOpen(privateKey, publicPoint, unb64u(m[3]), utf8("horde-relay/join/v1 offer-key"), utf8("horde-relay/join/v1 offer aad\n" + horde + "\n" + request + "\n" + kid), unb64u(m[4]));
    return fromUtf8(plain);
  } catch (x) { return null; }
}
// The transcript a trusted phone is sent (Get-HordeRelayJoinTranscriptSpec), read: { ok, reason, value }
// with value its members and text the exact text, which the approval's hash covers.
const TRANSCRIPT = new RegExp('^\\{"v":1,"kind":"horde-relay-join-transcript","request":"([0-9a-f]{32})","horde":"([a-z0-9][a-z0-9-]{0,62})","machine":"([0-9a-f]{32})","offer":"([0-9a-f]{32})",' +
  '"challenge":"([A-Za-z0-9_-]{43})","device":"([0-9a-f]{32})","credentialId":"([A-Za-z0-9_-]{1,8192})","publicKey":"([A-Za-z0-9_-]{87})","rpId":"([a-z0-9.-]{1,253})",' +
  '"label":"([\\x20\\x21\\x23-\\x5b\\x5d-\\x7e]{1,64})","agent":"([\\x20\\x21\\x23-\\x5b\\x5d-\\x7e]{0,512})","country":"([\\x20\\x21\\x23-\\x5b\\x5d-\\x7e]{0,512})","requestedAt":' + RECORD_INT + ',"expiresAt":' + RECORD_INT + '\\}$');
export function readJoinTranscript(text, horde, machine) {
  const m = typeof text === "string" ? TRANSCRIPT.exec(text) : null;
  if (!m) return { ok: false, reason: "a join request's transcript that is not in its canonical form", value: null };
  if (m[2] !== horde || m[3] !== machine) return { ok: false, reason: "a join transcript for another horde or machine", value: null };
  return { ok: true, reason: "", value: { text, request: m[1], horde: m[2], machine: m[3], offer: m[4], challenge: m[5], device: m[6], credentialId: m[7], publicKey: m[8], rpId: m[9], label: m[10], agent: m[11], country: m[12], requestedAt: Number(m[13]), expiresAt: Number(m[14]) } };
}
// What an approval carries of the transcript: SHA-256 of the domain and its text, base64url.
export async function joinTranscriptHash(text) { return b64u(await sha256(utf8("horde-relay/join/v1 transcript\n" + text))); }
// The number the new phone shows, as THIS phone computes it from the transcript (relay/Pairing.ps1's
// fingerprint over the offer's challenge, the passkey's point, its credential id and the rpId).
export async function joinNumber(t) { return pairingFingerprint({ challenge: unb64u(t.challenge), publicPoint: unb64u(t.publicKey), credentialId: unb64u(t.credentialId), rpId: t.rpId }); }
export function joinApproveBody({ request, device, transcript }) { return utf8(JSON.stringify({ v: 1, request, device, transcript })); }
export function joinRejectBody({ request }) { return utf8(JSON.stringify({ v: 1, request })); }

// relay/Trust.ps1's device id: the first 16 bytes of SHA-256 of the credential id, as hex.
export async function deviceIdOf(credentialId) { return hex((await sha256(credentialId)).slice(0, 16)); }

// relay/Pairing.ps1's CONFIRMED RECORD (TELLING THE PHONE IT IS CONFIRMED): the machine's word, in the
// offer's pairing mailbox, that the founder typed this phone's number there. It grants nothing; it only
// says a passkey prompt now is worth showing. { ok, reason, value: { confirmedAt } }; never throws.
export const CONFIRMED_DOMAIN = "horde-relay/pairing/v1 confirmed\n";
export function confirmedBytes({ horde, offer, device, confirmedAt }) { return utf8(CONFIRMED_DOMAIN + horde + "\n" + offer + "\n" + device + "\n" + confirmedAt); }
export function pairingConfirmedKey(offer) { return "confirmed/" + offer; }
const CONFIRMED = /^\{"v":1,"kind":"horde-relay-pairing-confirmed","horde":"([a-z0-9][a-z0-9-]{0,62})","offer":"([0-9a-f]{32})","device":"([0-9a-f]{32})","confirmedAt":(0|[1-9][0-9]{0,15}),"sig":"([A-Za-z0-9_-]{86})"\}$/;
export async function readPairingConfirmed(text, { horde, offer, device, signPublic }) {
  const no = (reason) => ({ ok: false, reason, value: null });
  const m = typeof text === "string" && text.length < 1024 ? CONFIRMED.exec(text) : null;
  if (!m) return no("not a confirmed record in its canonical form");
  if (m[1] !== horde || m[2] !== offer || m[3] !== device) return no("a confirmed record for another horde, offer or device");
  const confirmedAt = Number(m[4]);
  if (!Number.isSafeInteger(confirmedAt)) return no("its time is not a whole number");
  let sig;
  try { sig = unb64u(m[5]); } catch (x) { return no("its signature is not base64url"); }
  if (!(await verifyMachineSignature(signPublic, confirmedBytes({ horde, offer, device, confirmedAt }), sig))) return no("its signature is not the machine's");
  return { ok: true, reason: "", value: { confirmedAt } };
}

// --- the unlocked session (relay/Session.ps1 is the specification; relay/Sessions.ps1 what the PC takes) ---

// ONE PASSKEY PROMPT PER UNLOCK, NOT PER ANSWER. At unlock the page makes a SESSION KEY (ECDSA P-256,
// extractable: false, page memory only, never stored, never sent) and the unlock's one passkey
// assertion signs the VOUCH for it: its challenge is SHA-256 of the domain and the vouch text. The
// session key then signs answers, chat lines and photo manifests with no prompt. The PC decides
// whether the session is alive by its own clock and records; the phone acts on the refusal codes.
//
// THE WIRE, each byte as relay/Session.ps1 writes it:
//   vouch text   {"v":1,"kind":"horde-relay-session-vouch","sessionPublicKey":"<b64u point>","deviceKeyId":"<hex>",
//                 "phoneKeyId":"<hex>","horde":"<horde>","machine":"<hex>","mailbox":"<horde>/<machine>",
//                 "notBefore":<ms>,"notAfter":<ms>,"seq":<n>,"vouchId":"<hex>"}   (no spaces, this order)
//                vouchId = keyId(sessionPublicKey); notAfter after notBefore, with NO maximum (below); seq the
//                device's vouch counter, above its last (a new vouch at or below it is session-stale).
//   challenge    SHA-256("horde-relay/session/v1 vouch\n" + vouch text): the unlock assertion's challenge.
//   signed       "horde-relay/session/v1 envelope\n" + vouchId + "\n", then the envelope's signedBytes:
//                what the session key signs (ECDSA P-256 SHA-256, r || s as WebCrypto gives it).
//   sig          {"alg":"session","vouchId":"<hex>","value":"<b64u>"}, and on the FIRST envelope of a
//                session (and after session-unknown) {"alg":"session","vouchId":"<hex>","value":"<b64u>",
//                "vouch":"<b64u of the vouch text>","authenticatorData":"..","clientDataJSON":"..","signature":".."}.
//   header       unchanged: from is the PASSKEY's key id (deviceKeyId), seq the same per-channel stream.
//   opening      right after unlock the page sends ONE envelope on channel trust, kind session, body
//                sessionOpenBody(vouchId), carrying the vouch: the PC journals the vouch and starts its
//                idle clock. Any other envelope may carry the vouch too, so none waits for it.
// WHAT DOES NOT TRAVEL: the away lock (switching away or screen off, 10 minutes by default) is the
// page's own setting - the PC cannot see it. The idle limit is the PC's setting, enforced by the PC, and
// told to the phone in sessionStatus (idleMs) so the page can lock at the same moment.
// THERE IS NO MAXIMUM SESSION LENGTH (the founder, Q75 (b), "hard limit: no"). A session ends ONLY by the
// 60-minute idle rule (enforced by the PC), the 10-minute away lock (the phone), end-all, a revoke of
// the device or its passkey, or closing the page. notAfter stays in the vouch and the PC still refuses an
// envelope outside [notBefore, notAfter]; openSession puts it far ahead (SESSION_DEFAULT_LIFETIME_MS).
// The first pin of this wire (862287ad) had SESSION_MAX_MS, 8 hours: it is gone from both languages.
export const SESSION_VOUCH_DOMAIN = "horde-relay/session/v1 vouch\n";
export const SESSION_ENVELOPE_DOMAIN = "horde-relay/session/v1 envelope\n";
export const SESSION_DEFAULT_LIFETIME_MS = 365 * 24 * 60 * 60 * 1000;
export const SESSION_IDLE_DEFAULT_MS = 60 * 60 * 1000;
// The refusal codes (relay/Session.ps1, WHAT THE PC REFUSES): a PC's refusal of a session envelope
// starts with one of them, and a vouch's state in sessionStatus is "live" or one of them.
//   session-expired, session-idle, session-ended, session-stale  drop the key; the next send unlocks again
//   session-unknown   send the vouch with the next envelope
//   session-refused   never send under that vouch again; unlock again
//   needs-passkey     answer that question with a fresh passkey assertion (signEnvelope)
export const SESSION_REFUSALS = ["session-expired", "session-idle", "session-ended", "session-unknown", "session-stale", "session-refused", "needs-passkey"];
const HORDE_NAME = /^[a-z0-9][a-z0-9-]{0,62}$/;

// A fresh session key: { privateKey (CryptoKey, non-extractable, sign only), publicPoint (65 bytes) }.
// WebCrypto always lets the PUBLIC half of a key pair be exported; the private half here never can be.
export async function newSessionKey() {
  const kp = await subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  return { privateKey: kp.privateKey, publicPoint: new Uint8Array(await subtle.exportKey("raw", kp.publicKey)) };
}
// The canonical vouch text. Throws on a value that is not of its kind or a window the rules refuse.
export async function sessionVouchText({ sessionPublicKey, deviceKeyId, phoneKeyId, horde, machine, notBefore, notAfter, seq }) {
  if (!KEY_ID.test(deviceKeyId) || !KEY_ID.test(phoneKeyId) || !KEY_ID.test(machine)) throw new Error("the vouch's key ids are 32 lower-case hex");
  if (typeof horde !== "string" || !HORDE_NAME.test(horde)) throw new Error("the vouch's horde is not a horde name");
  for (const n of [notBefore, notAfter, seq]) if (!Number.isSafeInteger(n) || n < 0) throw new Error("the vouch's times and seq are whole numbers from 0 to 2^53-1");
  if (notAfter <= notBefore) throw new Error("a session's notAfter is after its notBefore");
  const vouchId = await keyId(sessionPublicKey);
  return '{"v":1,"kind":"horde-relay-session-vouch","sessionPublicKey":"' + b64u(sessionPublicKey) + '","deviceKeyId":"' + deviceKeyId + '","phoneKeyId":"' + phoneKeyId +
    '","horde":"' + horde + '","machine":"' + machine + '","mailbox":"' + horde + "/" + machine + '","notBefore":' + notBefore + ',"notAfter":' + notAfter +
    ',"seq":' + seq + ',"vouchId":"' + vouchId + '"}';
}
export async function sessionVouchChallenge(vouchText) { return sha256(utf8(SESSION_VOUCH_DOMAIN + vouchText)); }
export function sessionSignedBytes(vouchId, ht, rt, ct) { return cat(utf8(SESSION_ENVELOPE_DOMAIN + vouchId + "\n"), signedBytes(ht, rt, ct)); }
// The sig member's text: { vouchId, value (64 bytes) } and, to carry the vouch, vouch { text,
// authenticatorData, clientDataJSON, signature } (the assertion's three parts, as WebAuthn gave them).
export function sessionSigText({ vouchId, value, vouch = null }) {
  let t = '{"alg":"session","vouchId":"' + vouchId + '","value":"' + b64u(value) + '"';
  if (vouch) t += ',"vouch":"' + b64u(utf8(vouch.text)) + '","authenticatorData":"' + b64u(vouch.authenticatorData) + '","clientDataJSON":"' + b64u(vouch.clientDataJSON) + '","signature":"' + b64u(vouch.signature) + '"';
  return t + "}";
}
// Unlock: ONE passkey assertion (assert, as signEnvelope's) over the vouch for a new session key.
// { vouchId, privateKey, publicPoint, notBefore, notAfter, seq, vouch: { text, authenticatorData,
// clientDataJSON, signature } } - kept in page memory only. lifetimeMs is how far ahead notAfter is put:
// far by default, as the session ends by idle, the away lock, end-all, a revoke or the page closing.
export async function openSession({ assert, deviceKeyId, phoneKeyId, horde, machine, now, lifetimeMs = SESSION_DEFAULT_LIFETIME_MS, seq, key = null }) {
  const k = key || await newSessionKey();
  const notBefore = now, notAfter = now + lifetimeMs;
  const text = await sessionVouchText({ sessionPublicKey: k.publicPoint, deviceKeyId, phoneKeyId, horde, machine, notBefore, notAfter, seq });
  const a = await assert(await sessionVouchChallenge(text));
  return { vouchId: await keyId(k.publicPoint), privateKey: k.privateKey, publicPoint: k.publicPoint, notBefore, notAfter, seq,
    vouch: { text, authenticatorData: a.authenticatorData, clientDataJSON: a.clientDataJSON, signature: a.signature } };
}
// Sign sealed parts (sealEnvelope's) with the session key: the envelope's wire text, with the vouch
// when withVouch. No prompt. The envelope's ts must lie inside [notBefore, notAfter].
export async function signSessionEnvelope(parts, session, withVouch = false) {
  const value = new Uint8Array(await subtle.sign({ name: "ECDSA", hash: "SHA-256" }, session.privateKey, sessionSignedBytes(session.vouchId, parts.ht, parts.rt, parts.ctText)));
  return '{"header":' + parts.ht + ',"recipients":' + parts.rt + ',"ct":"' + parts.ctText + '","sig":' + sessionSigText({ vouchId: session.vouchId, value, vouch: withVouch ? session.vouch : null }) + "}";
}
// The body of the opening envelope (channel trust, kind session).
export function sessionOpenBody(vouchId) {
  if (!KEY_ID.test(vouchId)) throw new Error("a vouchId is 32 lower-case hex");
  return utf8('{"v":1,"vouchId":"' + vouchId + '"}');
}
// What the PC says of this phone's sessions, from a decisions snapshot's receipts (channels/decisions,
// WHAT BECAME OF EACH ANSWER): each passkey's receipt may carry
//   "session":{"idleMs":<the PC's idle limit>,"vouches":[{"vouchId":"<hex>","state":"live"|<a refusal code>}],
//              "needsPasskey":[<answerIds refused as needs-passkey: answer them again with the passkey>]}
// { idleMs, vouches (Map vouchId -> state), needsPasskey (Set) }, or null: no receipts, no receipt for
// this passkey, no session member (a PC from before sessions: it refuses every session envelope, by
// name, so the phone signs each with the passkey as before), or one that does not hold together.
const SESSION_STATES = ["live", ...SESSION_REFUSALS];
export function sessionStatus(receipts, from) {
  if (!Array.isArray(receipts)) return null;
  const r = receipts.find((x) => x && typeof x === "object" && x.from === from);
  const s = r && r.session;
  if (!s || typeof s !== "object" || !Number.isSafeInteger(s.idleMs) || s.idleMs < 1 || !Array.isArray(s.vouches) || s.vouches.length > 64 ||
    !Array.isArray(s.needsPasskey) || s.needsPasskey.length > 256) return null;
  const vouches = new Map();
  for (const v of s.vouches) {
    if (!v || typeof v.vouchId !== "string" || !KEY_ID.test(v.vouchId) || !SESSION_STATES.includes(v.state)) return null;
    vouches.set(v.vouchId, v.state);
  }
  if (!s.needsPasskey.every((i) => typeof i === "string" && KEY_ID.test(i))) return null;
  return { idleMs: s.idleMs, vouches, needsPasskey: new Set(s.needsPasskey) };
}

// --- the decisions channel (channels/decisions/Channel.ps1) ---

// The answer body: JSON.stringify escapes what JSON must and nothing else; the machine reads it with a
// strict JSON parser that wants exactly these members.
// AN ANSWER TO ONE PART of a question of parts is version 2: the same members and, last, part - the
// part's letter. With no part it is version 1, as it always was, which every machine reads.
export function answerBody({ answerId, machine, snapshot, number, wordingVersion, text, part = "" }) {
  if (!/^[0-9a-f]{32}$/.test(answerId)) throw new Error("an answerId is 32 lower-case hex");
  if (!KEY_ID.test(machine)) throw new Error("the machine is a key id");
  if (typeof snapshot !== "string" || snapshot.length > 160 || snapshot.indexOf(machine + "/decisions/") !== 0) throw new Error("the snapshot is that machine's envelope's replay key");
  if (!Number.isSafeInteger(number) || number < 1 || !Number.isSafeInteger(wordingVersion) || wordingVersion < 1) throw new Error("number and wordingVersion are whole numbers from 1");
  if (typeof text !== "string") throw new Error("the answer is text");
  if (part !== "" && !/^[a-z]$/.test(part)) throw new Error("a part is one lower-case letter");
  if (part !== "") return utf8(JSON.stringify({ v: 2, answerId, machine, snapshot, number, wordingVersion, text, part }));
  return utf8(JSON.stringify({ v: 1, answerId, machine, snapshot, number, wordingVersion, text }));
}

// A CHANGE OF RANK (channels/decisions/Channel.ps1, A CHANGE OF RANK FROM THE PHONE): the founder's tap
// on the Importance or the Blocking button of a question. Its own members - rankId, never answerId or
// text - so the machine can never read it as an answer, nor an answer as it. which is "importance" or
// "blocks", level a word of that one's list (the machine holds it to its rules again).
export const RANK_LEVELS = { importance: ["high", "normal", "low"], blocks: ["all", "part", "none"] };
export function rankBody({ rankId, machine, snapshot, number, which, level }) {
  if (!/^[0-9a-f]{32}$/.test(rankId)) throw new Error("a rankId is 32 lower-case hex");
  if (!KEY_ID.test(machine)) throw new Error("the machine is a key id");
  if (typeof snapshot !== "string" || snapshot.length > 160 || snapshot.indexOf(machine + "/decisions/") !== 0) throw new Error("the snapshot is that machine's envelope's replay key");
  if (!Number.isSafeInteger(number) || number < 1) throw new Error("number is a whole number from 1");
  if (!Object.prototype.hasOwnProperty.call(RANK_LEVELS, which) || RANK_LEVELS[which].indexOf(level) < 0) throw new Error("the change of rank is importance (high, normal or low) or blocks (all, part or none)");
  const body = { v: 1, rankId, machine, snapshot, number };
  body[which] = level;
  return utf8(JSON.stringify(body));
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
// replay key of the page that carried it, as pageKey), withheld, counts, answers } or null. pages is a list of
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
    best = { snapshot: hash, seq: g.seq, firstSeq: Math.min(...ordered.map((p) => p.relaySeq || 0)), questions, withheld: first.withheld, counts: first.counts, unreadable: first.unreadable, notUnderstood: first.notUnderstood,
      // The highest version of answer the machine says it reads; 1 for a machine whose snapshot says nothing.
      answers: Number.isSafeInteger(first.answers) && first.answers >= 1 ? first.answers : 1,
      // Whether the machine takes a change of rank from the phone (rankBody): false from one that does not say.
      ranks: first.ranks === 1,
      // What became of the founder's answers (receiptFor), as the machine said it; undefined from a
      // machine before receipts. ts: when the machine signed the snapshot's newest page, 0 if unknown.
      receipts: first.receipts, ts: Math.max(0, ...ordered.map((p) => (Number.isSafeInteger(p.ts) ? p.ts : 0))) };
  }
  return best;
}

// --- what a snapshot leaves out, as the phone says it ---

// A SNAPSHOT MAY SHOW LESS THAN THE LIST HOLDS, and says so: its withheld list names, by number, each
// open question it does not carry, with the machine's reason (channels/decisions/Channel.ps1). Until
// 2026-10-14 the phone never read it, so a shortened list looked like the whole one - and since a
// machine now sends ONE page first into a full mailbox, with every other question withheld, a list of
// forty could show as six with no word said, for as long as that mailbox stays full.
// THE REASON SHOWN IS THIS PHONE'S OWN SENTENCE, chosen by which of the machine's reasons it is: the
// machine's words are read only as far as telling the three apart, and are never put on the screen (as
// a progress notice's are not, PROGRESS_WORDS). A reason this phone does not know gets a sentence that
// says only that. NOTHING OF A WITHHELD QUESTION IS SHOWN, not even its number: a number is no help on
// a phone that cannot show the question, and the count is what tells him the list is short.
const WITHHELD_KINDS = [
  { opens: "it is in the snapshot that follows", one: "it comes in the snapshot that follows", many: "they come in the snapshot that follows" },
  { opens: "it holds what looks like a secret", one: "it holds what looks like a secret, so it is shown at the machine only", many: "they hold what looks like a secret, so they are shown at the machine only" },
  { opens: "it is too large to send to the phone", one: "it is too large to send to the phone, so it is shown at the machine only", many: "they are too large to send to the phone, so they are shown at the machine only" }
];
const WITHHELD_OTHER = { one: "it is shown at the machine only", many: "they are shown at the machine only" };
// The one line for a snapshot's withheld list: "" when nothing is withheld, else a sentence for each
// kind of reason there is, in the order above - "3 questions are not shown here: they come in the
// snapshot that follows." An entry that is not an object with a reason counts as one of no known kind.
export function withheldWords(withheld) {
  const list = Array.isArray(withheld) ? withheld : [];
  const counts = new Array(WITHHELD_KINDS.length + 1).fill(0);
  for (const w of list) {
    const reason = w && typeof w === "object" && typeof w.reason === "string" ? w.reason : "";
    const at = WITHHELD_KINDS.findIndex((k) => reason.startsWith(k.opens));
    counts[at < 0 ? WITHHELD_KINDS.length : at] += 1;
  }
  const out = [];
  counts.forEach((n, i) => {
    if (n === 0) return;
    const words = i < WITHHELD_KINDS.length ? WITHHELD_KINDS[i] : WITHHELD_OTHER;
    out.push(n + (n === 1 ? " question is" : " questions are") + " not shown here: " + (n === 1 ? words.one : words.many) + ".");
  });
  return out.join(" ");
}

// --- times, as the phone shows them ---

// WHEN A THING WAS SAID is shown in the phone's own local time, in a short form ("14:05"), with the day
// on a divider where the day changes and the exact time one tap away (the founder asked for the time
// of every message, 2026-10-12). Every function here takes a time in milliseconds and, for the suites,
// the zone as getTimezoneOffset gives it (minutes, positive WEST of UTC); with none it is the device's
// own zone at that moment. A time that is not one - 0, none, past what a date can hold - gives "" (or
// null): what has no time is shown with no time, never a guessed one. The words are fixed English and
// 24-hour, so one message reads the same on every phone.
const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const two = (n) => (n < 10 ? "0" : "") + n;
// An ISO 8601 time WITH A ZONE, as the conversation port writes a turn's (conversations/Port.ps1), in
// milliseconds; 0 for anything else. A time with no zone cannot be placed, so it is not one.
const ISO_TIME = /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?(Z|[+-][0-9]{2}:[0-9]{2})$/;
export function timeOf(text) {
  if (typeof text !== "string" || !ISO_TIME.test(text)) return 0;
  const ms = Date.parse(text);
  return Number.isSafeInteger(ms) && ms > 0 ? ms : 0;
}
export function localParts(ms, offsetMinutes) {
  if (!Number.isSafeInteger(ms) || ms <= 0) return null;
  const off = Number.isSafeInteger(offsetMinutes) ? offsetMinutes : new Date(ms).getTimezoneOffset();
  const d = new Date(ms - off * 60000);
  if (!Number.isSafeInteger(off) || Number.isNaN(d.getTime())) return null;
  return { year: d.getUTCFullYear(), month: d.getUTCMonth(), day: d.getUTCDate(), weekday: d.getUTCDay(), hour: d.getUTCHours(), minute: d.getUTCMinutes(), second: d.getUTCSeconds(), offsetMinutes: off };
}
// "14:05"
export function clockTime(ms, offsetMinutes) { const p = localParts(ms, offsetMinutes); return p ? two(p.hour) + ":" + two(p.minute) : ""; }
// "2026-10-12": the local day, to tell where the day changes.
export function dayKey(ms, offsetMinutes) { const p = localParts(ms, offsetMinutes); return p ? p.year + "-" + two(p.month + 1) + "-" + two(p.day) : ""; }
// "Mon 12 Oct 2026"
export function dayLabel(ms, offsetMinutes) { const p = localParts(ms, offsetMinutes); return p ? WEEKDAYS[p.weekday] + " " + p.day + " " + MONTHS[p.month] + " " + p.year : ""; }
// "Mon 12 Oct 2026, 14:05:09 (UTC+3)": the exact time, with the zone it is told in.
export function exactTime(ms, offsetMinutes) {
  const p = localParts(ms, offsetMinutes);
  if (!p) return "";
  const east = -p.offsetMinutes, a = Math.abs(east);
  const zone = "UTC" + (east === 0 ? "" : (east > 0 ? "+" : "-") + Math.floor(a / 60) + (a % 60 ? ":" + two(a % 60) : ""));
  return dayLabel(ms, p.offsetMinutes) + ", " + two(p.hour) + ":" + two(p.minute) + ":" + two(p.second) + " (" + zone + ")";
}
// A list of things that each carry said (milliseconds, or 0 for none), with a { kind: "day", key, label }
// put before the first of each local day, wherever the day is another than the last one named. What has
// no time gets no divider and changes none.
export function withDays(items, offsetMinutes) {
  const out = [];
  let last = "";
  for (const it of items) {
    const key = dayKey(it.said, offsetMinutes);
    if (key && key !== last) { out.push({ kind: "day", key, label: dayLabel(it.said, offsetMinutes) }); last = key; }
    out.push(it);
  }
  return out;
}

// --- what became of each answer (channels/decisions/Channel.ps1, WHAT BECAME OF EACH ANSWER) ---

// THE FOUNDER'S ANSWERS ARE KEPT ON THE PHONE UNTIL THE PC SAYS THEY ARE APPLIED (the founder, 2026-10-14,
// relay fixes 3 and 4: the runner was down 2 h 38 min, twenty answers waited, and one never arrived with
// nothing said). Each answer is in one of these states, shown beside it in these words:
//   sent       the relay took the put; nothing more is known yet;
//   received   the PC has journaled an envelope that carried it (its seq at or below the receipt's
//              through, and not among its missing);
//   applied    the decisions list wrote the record: the receipt lists its answerId as applied;
//   refused    the list refused it for good: never sent again.
// An answer held longer than ANSWER_WARN_MS without being applied or refused carries a warning line.
export const ANSWER_WORDS = { sent: "sent", received: "received by PC", applied: "applied", refused: "refused by the PC" };
export const ANSWER_WARNING = "Not confirmed by the PC for over an hour. It stays here, and is sent again until the PC confirms it.";
export const ANSWER_REFUSED_NOTE = "The PC refused this answer. Answer again if it still stands.";
// How long an answer may wait unconfirmed before the warning (the outage it answers was 2 h 38 min: an
// hour says so well inside it); how often one answer is sent again at most; and how long after the
// answer was last put a receipt from the PC must be before an answer it does not know of counts as
// lost at the end of the stream (the clocks of the phone and the PC may differ by minutes).
export const ANSWER_WARN_MS = 60 * 60 * 1000;
export const ANSWER_RESEND_MS = 10 * 60 * 1000;
export const ANSWER_TAIL_GRACE_MS = 10 * 60 * 1000;
// How long an answer may say received by PC before it is signed again once (answerState, S1).
export const ANSWER_STUCK_MS = 2 * 60 * 60 * 1000;
// What stands for his words when this phone cannot read them back (withAnswers): still answered.
export const ANSWER_UNREADABLE = "(Your answer is kept on this phone, but its words cannot be read here.)";
const RECEIPT_LIMITS = { streams: 64, ids: 256 };

// The receipt for one passkey (from, its key id) out of a snapshot's receipts member: { through, missing,
// applied, refused } - missing a Set of seqs, applied and refused Sets of answerIds - or null when the
// snapshot has no receipts member (a machine from before receipts) or the member does not hold together.
// A machine with receipts and none for this passkey yet is a receipt of nothing: through 0.
export function receiptFor(receipts, from) {
  if (!Array.isArray(receipts) || receipts.length > RECEIPT_LIMITS.streams) return null;
  const empty = { through: 0, checked: 0, missing: new Set(), applied: new Set(), refused: new Set() };
  for (const r of receipts) {
    if (!r || typeof r !== "object" || typeof r.from !== "string" || !KEY_ID.test(r.from)) return null;
    if (r.from !== from) continue;
    const seqs = Array.isArray(r.missing) ? r.missing : null;
    const ids = (x) => Array.isArray(x) && x.length <= RECEIPT_LIMITS.ids && x.every((i) => typeof i === "string" && KEY_ID.test(i));
    if (!Number.isSafeInteger(r.through) || r.through < 0 || !seqs || seqs.length > RECEIPT_LIMITS.ids || !seqs.every((s) => Number.isSafeInteger(s) && s > 0) || !ids(r.applied) || !ids(r.refused)) return null;
    // checked: the lowest seq the machine looked at for holes (channels/decisions, checked). A receipt
    // that does not say counts as one that looked at nothing below through: every seq under it unknown.
    const checked = Number.isSafeInteger(r.checked) && r.checked >= 0 && r.checked <= r.through ? r.checked : r.through;
    return { through: r.through, checked, missing: new Set(seqs), applied: new Set(r.applied), refused: new Set(r.refused) };
  }
  return empty;
}

// What became of one kept answer: { state, resend, due, warning }.
//   item     { answerId, seqs (the seqs of every envelope that carried it), sentAt, lastSentAt, lastResendAt }
//   receipt  receiptFor's answer for this phone's passkey
//   receiptTs  the time the PC signed the snapshot that carried the receipt (its envelope's ts), 0 for none
// resend says how it is to be sent again, "" for not at all: "resign" - its newest envelope is MISSING
// (the PC took a later one of this phone, so the journal refuses that seq for good: only a new envelope,
// signed again, carries it); "reput" - the PC has taken nothing as late as its newest envelope though it
// spoke well after it was put (lost at the end of the stream: the same envelope is put again, and the
// relay or the journal drops it if it was not lost after all). due: a resend is wanted and the last
// send of it is ANSWER_RESEND_MS behind.
export function answerState(item, receipt, receiptTs, now) {
  const r = receipt || { through: 0, checked: 0, missing: new Set(), applied: new Set(), refused: new Set() };
  const seqs = Array.isArray(item.seqs) ? item.seqs : [];
  // A SEQ IS KNOWN TO HAVE ARRIVED only between checked and through, and not missing (review of PR 262,
  // M1: below the cut of the missing list a hole used to read as received, and was never sent again).
  const arrived = (s) => s <= r.through && s >= r.checked && !r.missing.has(s);
  const lost = (s) => r.missing.has(s) || (s <= r.through && s < r.checked);
  let state = "sent";
  if (r.applied.has(item.answerId)) state = "applied";
  else if (r.refused.has(item.answerId)) state = "refused";
  else if (seqs.some(arrived)) state = "received";
  let resend = "";
  let stuck = false;
  if (state === "sent" && receipt && seqs.length) {
    const newest = Math.max(...seqs);
    if (lost(newest)) resend = "resign";
    else if (newest > r.through && Number(receiptTs) > Number(item.lastSentAt) + ANSWER_TAIL_GRACE_MS) resend = "reput";
  }
  // RECEIVED FOR HOURS AND NEVER LISTED (review of PR 262, S1): more applied in one turn than a receipt
  // lists, or a refusal pushed out of its list, would say received for ever. Signed again ONCE: the PC
  // answers the same id as the record it is, and lists it again.
  if (state === "received" && receipt && item.stuckResent !== true && now - Number(item.sentAt) > ANSWER_STUCK_MS) { resend = "resign"; stuck = true; }
  const last = Math.max(Number(item.lastSentAt) || 0, Number(item.lastResendAt) || 0);
  const due = resend !== "" && now - last >= ANSWER_RESEND_MS;
  const warning = (state === "sent" || state === "received") && now - Number(item.sentAt) > ANSWER_WARN_MS;
  return { state, resend, due, warning, stuck };
}

// The snapshot's questions with the answers this phone keeps drawn into them (the bridge's list): an
// answer not yet applied is HIS MESSAGE under its question - so the question shows as answered, with
// his words, and never as an empty slot (the founder's rule, 2026-10-14) - marked local, with its state
// in words (receipt) and the warning or the refusal under it (receiptNote). An applied answer is in
// the snapshot's own thread by then; his last message there with the same words and part is marked
// applied. answers: [{ number, part, text, state, warning, sentAt }]. Copies; nothing handed in changes.
export function withAnswers(questions, answers) {
  const list = Array.isArray(answers) ? answers : [];
  // Numbered past EVERY message of the list, as the bridge numbers a saved answer (bridge.js, say): the
  // document then takes a drawn answer for the one it was just told is saved.
  let top = 0;
  for (const q of questions || []) for (const m of (q.thread && Array.isArray(q.thread.messages)) ? q.thread.messages : []) { const n = Number(m.sequence); if (Number.isSafeInteger(n) && n > top) top = n; }
  return (questions || []).map((q) => {
    const mine = list.filter((a) => a.number === q.number);
    if (!mine.length) return q;
    const thread = q.thread && typeof q.thread === "object" ? q.thread : { count: 0, turn: "founder", messages: [] };
    const messages = (Array.isArray(thread.messages) ? thread.messages : []).map((m) => ({ ...m }));
    for (const a of mine.filter((x) => x.state === "applied" && !x.unreadable)) {
      for (let i = messages.length - 1; i >= 0; i--) {
        const m = messages[i];
        if (m.speaker === "founder" && m.text === a.text && (m.part || "") === (a.part || "")) { messages[i] = { ...m, receipt: ANSWER_WORDS.applied }; break; }
      }
    }
    let k = 0;
    for (const a of mine.filter((x) => x.state !== "applied").sort((x, y) => x.sentAt - y.sentAt)) {
      k += 1;
      const m = { sequence: top + k, speaker: "founder", route: "phone", text: a.unreadable || typeof a.text !== "string" ? ANSWER_UNREADABLE : a.text, at: new Date(Number(a.sentAt) || 0).toISOString(), local: true, receipt: ANSWER_WORDS[a.state] || ANSWER_WORDS.sent,
        receiptNote: a.state === "refused" ? ANSWER_REFUSED_NOTE : (a.warning ? ANSWER_WARNING : "") };
      if (a.part) m.part = a.part;
      messages.push(m);
    }
    return { ...q, thread: { ...thread, messages } };
  });
}

// --- the chat channel (channels/chat/Channel.ps1) ---

// The receipt's codes, by status, and the ONE sentence the phone shows for each: what a receipt says is
// a code from this list, never words of the machine's, the relay's or a messenger's.
export const CHAT_WORDS = {
  accepted: { queued: "Sent: the Thrall's mailbox has it.", delivered: "Delivered to the Thrall." },
  held: {
    "thrall-unknown": "Held: the machine cannot find the Thrall just now; it will try again.",
    "no-messenger": "Held: the machine has no way to deliver it yet; it will try again.",
    "not-now": "Held: delivery failed for now; it will try again.",
    "too-many": "Held: too many lines in a minute; it goes shortly.",
    "not-delivered": "Not delivered: the Thrall's mailbox holds it back.",
    expired: "Not delivered: it waited too long."
  },
  refused: {
    "wrong-machine": "Refused: it was sent to the wrong machine.",
    "wrong-horde": "Refused: it was sent to the wrong horde.",
    empty: "Refused: it has no words.",
    "too-long": "Refused: it is too long for one line.",
    "no-thrall": "Refused: no Thrall is running on that machine.",
    "session-ended": "Refused: the Thrall started a new session; send it again."
  }
};
export const CHAT_SENDING = "Sending...";
// founder: a line of his that the MACHINE found delivered to the Thrall word for word (channels/chat,
// A DELIVERED LINE COMES BACK AS THE FOUNDER'S TURN); it always names that line.
export const CHAT_ROLES = ["user", "assistant", "system", "founder"];
const SESSION = /^[A-Za-z0-9._:-]{1,128}$/;
const TURN_ID = /^[\x21-\x7e]{1,200}$/;

// The line body: JSON.stringify escapes what JSON must; the machine reads it strictly, exactly these members.
export function lineBody({ messageId, horde, machine, session, text }) {
  if (!/^[0-9a-f]{32}$/.test(messageId)) throw new Error("a messageId is 32 lower-case hex");
  if (typeof horde !== "string" || !/^[a-z0-9][a-z0-9-]{0,62}$/.test(horde)) throw new Error("the horde is a horde name");
  if (!KEY_ID.test(machine)) throw new Error("the machine is a key id");
  if (typeof session !== "string" || !SESSION.test(session)) throw new Error("the session is the Thrall's session id");
  if (typeof text !== "string") throw new Error("the line is text");
  return utf8(JSON.stringify({ v: 1, messageId, horde, machine, session, text }));
}

// What the Thrall reads begins with this, naming the line (channels/chat, THE BODY THE THRALL GETS).
// The phone never trusts it in a turn's text: anyone can quote it. Only the machine, which knows the
// words it posted, marks a turn as the founder's.
export function lineMarker(messageId) { return "(line " + messageId + ")"; }

function chatHead(bodyBytes, kind, horde, machine) {
  let b;
  try { b = JSON.parse(fromUtf8(bodyBytes)); } catch (x) { return { error: "the chat body is not JSON" }; }
  if (!b || b.v !== 1 || b.kind !== kind) return { error: "not a version 1 " + kind };
  if (b.horde !== horde || b.machine !== machine) return { error: "the chat body names another horde or machine" };
  if (typeof b.session !== "string" || !SESSION.test(b.session)) return { error: "the chat body names no session" };
  return { body: b };
}

// A turns body, read: { ok, reason, value } with value { session, backfill, turns }. Each turn is
// { id, role, session, text, time?, group?, part?, parts?, truncated?, redactions? }; a turn that does
// not hold together is dropped, and counted in value.dropped.
export function readChatTurns(bodyBytes, horde, machine) {
  const h = chatHead(bodyBytes, "chat-turns", horde, machine);
  if (h.error) return { ok: false, reason: h.error, value: null };
  const b = h.body;
  if (typeof b.backfill !== "boolean" || !Array.isArray(b.turns)) return { ok: false, reason: "the turns body has no turns list", value: null };
  const turns = [];
  let dropped = 0;
  for (const t of b.turns) {
    const ok = t && typeof t.id === "string" && TURN_ID.test(t.id) && CHAT_ROLES.indexOf(t.role) >= 0 && typeof t.text === "string" &&
      typeof t.session === "string" && SESSION.test(t.session) && (t.role !== "founder" || (typeof t.line === "string" && /^[0-9a-f]{32}$/.test(t.line))) &&
      (t.part === undefined || (Number.isSafeInteger(t.part) && Number.isSafeInteger(t.parts) && t.part >= 1 && t.part <= t.parts && t.parts <= 100000));
    if (!ok) { dropped++; continue; }
    turns.push({ id: t.id, role: t.role, session: t.session, text: t.text, time: typeof t.time === "string" ? t.time : "", group: typeof t.group === "string" ? t.group : "",
      part: t.part || 0, parts: t.parts || 0, truncated: t.truncated === true, redactions: Number.isSafeInteger(t.redactions) ? t.redactions : 0, line: t.role === "founder" ? t.line : "" });
  }
  // photoBytes: the machine takes photos up to that size (channels/chat/Photo.ps1); 0 from a machine
  // older than the member, which the phone offers no picture button.
  const photoBytes = Number.isSafeInteger(b.photoBytes) && b.photoBytes > 0 ? b.photoBytes : 0;
  // photoWindowMs: the longest window this machine lets a photo name (its photoWindowSeconds); 0 when it
  // says nothing, and the phone then names its own hour (photoWindowFor).
  const photoWindowMs = Number.isSafeInteger(b.photoWindowMs) && b.photoWindowMs > 0 ? b.photoWindowMs : 0;
  return { ok: true, reason: "", value: { session: b.session, backfill: b.backfill, turns, dropped, photoBytes, photoWindowMs } };
}

// A receipt body, read: { ok, reason, value } with value { session, messageId, status, code, text,
// sentAt }. A status or code off the list is refused: the phone never shows a word it did not choose.
// sentAt is when he sent the line, as his passkey signed it (channels/chat, THE RECEIPT), or 0 when the
// receipt carries none (a machine older than the member): then the line is shown with no time.
export function readChatReceipt(bodyBytes, horde, machine) {
  const h = chatHead(bodyBytes, "chat-receipt", horde, machine);
  if (h.error) return { ok: false, reason: h.error, value: null };
  const b = h.body;
  if (typeof b.messageId !== "string" || !/^[0-9a-f]{32}$/.test(b.messageId)) return { ok: false, reason: "the receipt names no line", value: null };
  if (!Object.prototype.hasOwnProperty.call(CHAT_WORDS, b.status) || !Object.prototype.hasOwnProperty.call(CHAT_WORDS[b.status], b.code)) return { ok: false, reason: "the receipt's status or code is not one this phone knows", value: null };
  if (typeof b.text !== "string") return { ok: false, reason: "the receipt has no words", value: null };
  return { ok: true, reason: "", value: { session: b.session, messageId: b.messageId, status: b.status, code: b.code, text: b.text, sentAt: Number.isSafeInteger(b.sentAt) && b.sentAt > 0 ? b.sentAt : 0 } };
}

// The chat as the phone shows it, from what it holds in memory:
//   turns     every turn entry read (parts and repeats included), each with seq (the envelope's)
//   receipts  every receipt read, each with seq and ts (the envelope's)
//   sent      the lines this phone sent this session: { messageId, text, at, session }
// -> { session, items } where items are, in order of time, { kind: "turn", id, role, text, time, session,
// truncated, redactions, said } and { kind: "line", messageId, text, at, status, code, words, said, saidHow }. A turn is shown
// once, by id, and only once all its parts are here; a line is shown once, its newest receipt's status
// on it, or "sending" when there is none yet. A founder turn (the machine found the line delivered) is
// that line: beside a send or a receipt it is not shown twice, and with neither - after a reload, once
// the relay dropped the receipt - it is shown as his line, delivered. A user turn that merely QUOTES a
// line's header is a user turn: nothing in a turn's text makes it the founder's.
// WHEN IT WAS SAID is each item's said, in milliseconds, or 0 when nothing says: a turn's own time from the
// conversation port; a line's time as his passkey signed it - this phone's own send, or the receipt's
// sentAt - and, where neither is left, the time of the machine's founder turn, which is when the line
// reached the Thrall (saidHow "delivered", so the screen can say which it is). A receipt's own envelope
// time is the machine's, later than the send by however long the line waited: it orders a line with no
// better time, and is never shown as when he said it.
// now: the phone's clock, in milliseconds, for a photo of this phone's that no receipt has named yet
// (photoItems, A PHOTO WAITS FOR THE PC); 0 leaves every such photo as sent.
export function chatTimeline({ turns = [], receipts = [], sent = [], photos = [], photoReceipts = [] }, now = 0) {
  const byId = new Map();
  for (const t of turns) {
    let g = byId.get(t.id);
    if (!g) { g = { first: t, parts: new Map(), seq: t.seq }; byId.set(t.id, g); }
    if (t.part) { if (!g.parts.has(t.part)) g.parts.set(t.part, t); }
    else g.whole = t;
  }
  const lines = new Map();
  for (const s of sent) lines.set(s.messageId, { kind: "line", messageId: s.messageId, text: s.text, at: s.at, said: Number.isSafeInteger(s.at) && s.at > 0 ? s.at : 0, saidHow: "sent", session: s.session, status: "sending", code: "", words: CHAT_SENDING, seq: -1 });
  for (const r of receipts) {
    const had = lines.get(r.messageId);
    if (had && had.seq > r.seq) continue;
    // The receipt's words are the words posted: what the line shows, whatever the phone kept.
    const said = r.sentAt || (had ? had.said : 0);
    lines.set(r.messageId, { kind: "line", messageId: r.messageId, text: r.text, at: had && had.at ? had.at : (r.sentAt || r.ts), said, saidHow: "sent", session: r.session, status: r.status, code: r.code, words: CHAT_WORDS[r.status][r.code], seq: r.seq });
  }
  const items = [];
  for (const [id, g] of byId) {
    let text;
    if (g.whole) text = g.whole.text;
    else {
      const n = g.first.parts;
      if (g.parts.size !== n) continue;
      text = "";
      for (let i = 1; i <= n; i++) text += g.parts.get(i).text;
    }
    const t = g.whole || g.first;
    if (t.role === "founder") {
      const had = lines.get(t.line);
      if (had) {
        if (had.status === "sending") { had.status = "accepted"; had.code = "delivered"; had.words = CHAT_WORDS.accepted.delivered; }
        if (!had.said) { had.said = timeOf(t.time); had.saidHow = "delivered"; }
      }
      // Kept as the line, by its id: a messenger that delivers at least once may hand it over twice.
      else lines.set(t.line, { kind: "line", messageId: t.line, text, at: Date.parse(t.time) || 0, said: timeOf(t.time), saidHow: "delivered", session: t.session, status: "accepted", code: "delivered", words: CHAT_WORDS.accepted.delivered, seq: -1, order: g.seq });
      continue;
    }
    items.push({ kind: "turn", id, role: t.role, text, time: t.time, session: t.session, truncated: t.truncated, redactions: t.redactions, at: Date.parse(t.time) || 0, said: timeOf(t.time), saidHow: "turn", order: g.seq });
  }
  for (const l of lines.values()) items.push({ ...l, order: l.order === undefined ? Number.MAX_SAFE_INTEGER : l.order });
  for (const p of photoItems(photos, photoReceipts, now)) items.push(p);
  items.sort((a, b) => (a.at - b.at) || (a.order - b.order));
  return items;
}

// --- photos in the chat (channels/chat/Photo.ps1) ---
//
// ONE PASSKEY TAP A PHOTO. Every envelope the phone sends is one passkey assertion, user verified, so a
// photo split over envelopes would be a prompt a part: 21 of them for 1 MB through the hosted relay's
// 65,536-character texts (measured 2026-10-14). So a photo is ONE envelope of kind photo - the manifest,
// signed like a line - and its parts are unsigned relay items, sealed under a key that only the sealed
// manifest carries, each vouched for by its SHA-256 listed in the manifest at its number. The machine
// takes a part only on that digest (Photo.ps1, THE PARTS).
//
// PHOTO_CHUNK: 48,000 bytes. Sealed (16-byte tag) and in base64url, 64,022 characters; with the part's
// frame, 64,132 - inside the hosted relay's 65,536. 1 MB is 21 parts, the 2 MiB cap 44.
export const PHOTO_CHUNK = 48000;
export const PHOTO_PARTS_MOST = 64;
// The window the manifest names: its parts must reach the machine within it (the machine allows at most
// its photoWindowSeconds, 3600 by default, after the signing time). AN HOUR (the founder's choice,
// 2026-10-16): a photo sent while the PC is off waits up to an hour for it, and the phone says so meanwhile
// (PHOTO_WAITING); past the hour with no word from the PC it says plainly it was not delivered
// (PHOTO_NOT_DELIVERED) and offers to send it again.
export const PHOTO_WINDOW_MS = 3600000;
// The window a photo names: the hour, or less when the machine says its own is shorter (a machine set to
// 600 s refuses a photo whose window ends more than 600 s after it was signed).
export function photoWindowFor(machineWindowMs) {
  return Number.isSafeInteger(machineWindowMs) && machineWindowMs > 0 ? Math.min(PHOTO_WINDOW_MS, machineWindowMs) : PHOTO_WINDOW_MS;
}
// How many photos a phone leaves unanswered at one machine: while the machine is off its mailbox fills
// (20 MiB), and a full mailbox refuses chat lines and decision answers too.
export const PHOTO_MOST_UNANSWERED = 3;
export const PHOTO_TOO_MANY_UNANSWERED = "Wait: 3 photos are still waiting for your PC. Send another when it has taken one.";
const PHOTO_PART_AAD = "horde-relay/chat/v1 photo part";

// The relay key a part is put under: the sender, the kind, the photo, the number and the first 16 hex of
// the part's digest. It names no stream (no seq and nonce), so no trim ever reaches it, and a part put
// twice is the same item. THE DIGEST IS IN IT because the relay keeps the FIRST text put under a key: by
// photo and number alone, junk put first under them squatted the real part's slot (review of PR 285).
// The kind is new with photos, so no older phone puts a part under the old form.
export function photoPartKey(from, photoId, n, digest) {
  if (typeof digest !== "string" || !/^[0-9a-f]{64}$/.test(digest)) throw new Error("a part's key names its digest, 64 lower-case hex");
  return from + "/photo-part/" + photoId + "/" + n + "/" + digest.slice(0, 16);
}

function photoNonce(n) { const b = new Uint8Array(12); b[8] = (n >>> 24) & 255; b[9] = (n >>> 16) & 255; b[10] = (n >>> 8) & 255; b[11] = n & 255; return b; }

// Seal an image's bytes as parts: { key (32 bytes), sha256 (hex of the whole), parts: [{ n, digest, key,
// text }] } - digest the SHA-256 of the sealed bytes, key the relay key, text the item as the machine
// reads it, in its one form (Photo.ps1, $HordeChatPhotoPartPattern).
export async function sealPhotoParts(bytes, { from, photoId }) {
  if (!KEY_ID.test(from) || !/^[0-9a-f]{32}$/.test(photoId)) throw new Error("a photo's sender and id are 32 lower-case hex");
  if (!(bytes instanceof Uint8Array) || bytes.length < 1) throw new Error("a photo is bytes");
  const count = Math.ceil(bytes.length / PHOTO_CHUNK);
  if (count > PHOTO_PARTS_MOST) throw new Error("a photo is at most " + PHOTO_PARTS_MOST + " parts");
  const key = randomBytes(32);
  const parts = [];
  for (let n = 1; n <= count; n++) {
    const chunk = bytes.subarray((n - 1) * PHOTO_CHUNK, Math.min(bytes.length, n * PHOTO_CHUNK));
    const ct = await gcmSeal(key, photoNonce(n), utf8(PHOTO_PART_AAD + "\n" + from + "\n" + photoId + "\n" + n), chunk);
    const digest = hex(await sha256(ct));
    parts.push({ n, digest, key: photoPartKey(from, photoId, n, digest), text: '{"v":1,"kind":"photo-part","from":"' + from + '","photo":"' + photoId + '","part":' + n + ',"ct":"' + b64u(ct) + '"}' });
  }
  return { key, sha256: hex(await sha256(bytes)), parts };
}

// The manifest body: exactly the members the machine reads strictly (Photo.ps1), in its order.
// resendOf: only when this photo is a Send again, the id of the photo it is sent again for - the machine treats a photo as the same
// one only when the phone says so, never because the image looks alike (a photo sent on purpose a second time is a new photo).
export function photoManifestBody({ photoId, horde, machine, mailbox, from, phoneKey, seq, session, expiresAt, bytes, sha256: whole, key, parts, resendOf = "" }) {
  if (![photoId, machine, from, phoneKey].every((x) => typeof x === "string" && /^[0-9a-f]{32}$/.test(x))) throw new Error("photoId, machine, from and phoneKey are 32 lower-case hex");
  if (typeof horde !== "string" || !/^[a-z0-9][a-z0-9-]{0,62}$/.test(horde)) throw new Error("the horde is a horde name");
  if (typeof session !== "string" || !SESSION.test(session)) throw new Error("the session is the Thrall's session id");
  if (![seq, expiresAt, bytes].every((x) => Number.isSafeInteger(x) && x >= 1)) throw new Error("seq, expiresAt and bytes are whole numbers from 1");
  if (!Array.isArray(parts) || parts.length < 1 || parts.length > PHOTO_PARTS_MOST || !parts.every((d) => /^[0-9a-f]{64}$/.test(d))) throw new Error("the parts are 1 to " + PHOTO_PARTS_MOST + " digests");
  if (resendOf !== "" && !(typeof resendOf === "string" && /^[0-9a-f]{32}$/.test(resendOf) && resendOf !== photoId)) throw new Error("resendOf is the 32 lower-case hex id of another photo");
  const body = { v: 1, photoId, horde, machine, mailbox, from, phoneKey, seq, session, expiresAt, bytes, sha256: whole, key: b64u(key), parts };
  if (resendOf !== "") body.resendOf = resendOf;
  return utf8(JSON.stringify(body));
}

// What the first bytes of a file say it is: "jpeg", "png", "webp", or "" for anything else - a script,
// a PDF, an HTML page called .jpg. The machine checks the same bytes again (Photo.ps1, magic).
export function sniffImage(bytes) {
  if (!(bytes instanceof Uint8Array)) return "";
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "jpeg";
  const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length >= 8 && png.every((b, i) => bytes[i] === b)) return "png";
  const at = (i, s) => [...s].every((c, k) => bytes[i + k] === c.charCodeAt(0));
  if (bytes.length >= 12 && at(0, "RIFF") && at(8, "WEBP")) return "webp";
  return "";
}

// The photo receipt's codes, by status, and the ONE sentence the phone shows for each (Photo.ps1).
export const PHOTO_WORDS = {
  accepted: { receiving: "Photo on its way to the PC.", delivered: "Photo saved on the PC, and the Thrall told.", saved: "Photo saved on the PC; the Thrall could not be told yet." },
  held: { "too-many": "Held: too many photos in a minute; it goes shortly." },
  refused: {
    "wrong-machine": "Refused: it was sent to the wrong machine.",
    "wrong-horde": "Refused: it was sent to the wrong horde.",
    "wrong-mailbox": "Refused: it was sent to the wrong mailbox.",
    "wrong-sender": "Refused: it does not say it is from the passkey that signed it.",
    expired: "Refused: it arrived too late. Send it again.",
    "too-large": "Refused: it is larger than the PC takes.",
    "over-budget": "Refused: the PC has taken as many photos as it takes in a day.",
    "no-phone-key": "Refused: the PC does not trust this phone's key.",
    incomplete: "Not saved: not all of it arrived in time. Send it again.",
    damaged: "Not saved: what arrived is not the photo that was signed. Send it again.",
    "not-image": "Not saved: it is not a picture.",
    revoked: "Not saved: the passkey or this phone was removed from the PC.",
    "not-here": "Refused: the PC cannot take photos as it runs now."
  }
};
export const PHOTO_SENDING = "Sending the photo...";
export const PHOTO_WAITING = "Sent: waiting for your PC to take it (it waits up to an hour).";
export const PHOTO_NOT_DELIVERED = "No receipt yet: your PC has not said it took the photo within an hour. If it is still off, Send again.";
// The receipt codes after which a photo can only arrive by being sent again: the page offers Send again
// for these, as for one that was not delivered in its hour.
export const PHOTO_SEND_AGAIN = ["expired", "incomplete"];
export const PHOTO_NOT_IMAGE = "That file is not a picture: choose a JPEG, PNG or WebP photo.";
export const PHOTO_PC_OLD = "Your PC does not take photos yet: it needs a Horde update.";

// A photo receipt, read: { ok, reason, value: { session, photoId, status, code, sentAt, file } }.
export function readPhotoReceipt(bodyBytes, horde, machine) {
  const h = chatHead(bodyBytes, "chat-photo-receipt", horde, machine);
  if (h.error) return { ok: false, reason: h.error, value: null };
  const b = h.body;
  if (typeof b.photoId !== "string" || !/^[0-9a-f]{32}$/.test(b.photoId)) return { ok: false, reason: "the photo receipt names no photo", value: null };
  if (!Object.prototype.hasOwnProperty.call(PHOTO_WORDS, b.status) || !Object.prototype.hasOwnProperty.call(PHOTO_WORDS[b.status], b.code)) return { ok: false, reason: "the photo receipt's status or code is not one this phone knows", value: null };
  const file = typeof b.file === "string" && /^[A-Za-z0-9._-]{0,80}$/.test(b.file) ? b.file : "";
  return { ok: true, reason: "", value: { session: b.session, photoId: b.photoId, status: b.status, code: b.code, sentAt: Number.isSafeInteger(b.sentAt) && b.sentAt > 0 ? b.sentAt : 0, file } };
}

// The photos of the chat: those this phone sent this session ({ photoId, at, session, expiresAt, sent }),
// and every one a receipt names (another phone's too), each once, with its newest receipt's words.
// A PHOTO WAITS FOR THE PC (the founder's choice, 2026-10-16): one of this phone's that no receipt names
// yet is sending while its parts go, then waiting (PHOTO_WAITING) - the PC may be off - and, once now
// is past the window its manifest names (expiresAt), not-delivered: the PC refuses it after that
// (Photo.ps1, expired), so it can only arrive by being sent again. sendAgain marks an item the page may
// offer to send again.
function photoItems(photos, photoReceipts, now = 0) {
  const byId = new Map();
  for (const p of photos) {
    const late = Number.isSafeInteger(p.expiresAt) && now >= p.expiresAt;
    const status = late ? "not-delivered" : p.sent ? "waiting" : "sending";
    byId.set(p.photoId, { kind: "photo", photoId: p.photoId, at: p.at, said: p.at, saidHow: "sent", session: p.session, status, code: "", words: late ? PHOTO_NOT_DELIVERED : p.sent ? PHOTO_WAITING : PHOTO_SENDING, file: "", seq: -1, mine: true, sendAgain: late, order: Number.MAX_SAFE_INTEGER });
  }
  for (const r of photoReceipts) {
    const had = byId.get(r.photoId);
    if (had && had.seq > r.seq) continue;
    const at = had ? had.at : (r.sentAt || r.ts);
    byId.set(r.photoId, { kind: "photo", photoId: r.photoId, at, said: r.sentAt || (had ? had.said : 0), saidHow: "sent", session: r.session, status: r.status, code: r.code, words: PHOTO_WORDS[r.status][r.code], file: r.file, seq: r.seq, mine: !!(had && had.mine), sendAgain: r.status === "refused" && PHOTO_SEND_AGAIN.indexOf(r.code) >= 0, order: Number.MAX_SAFE_INTEGER });
  }
  return [...byId.values()];
}

// How many of this phone's photos have no word from the machine and are still within their window.
export function photosUnanswered(photos, photoReceipts, now = 0) {
  const answered = new Set(photoReceipts.map((r) => r.photoId));
  return photos.filter((p) => !answered.has(p.photoId) && !(Number.isSafeInteger(p.expiresAt) && now >= p.expiresAt)).length;
}

// --- the progress channel (channels/progress/Channel.ps1) ---

// THE FLEET'S PROGRESS LOG, machine to phone only: entries of the changelog the machine follows, in the
// order they were WRITTEN (each carries its line number, n) - an entry's time is when the thing
// happened, so a later line may carry an earlier time, and the phone never reorders by it. The phone
// sends nothing on this channel.
// A kind's word on the screen. A kind this phone does not know is a note: the entry is still shown.
export const PROGRESS_KINDS = { decision: "Decision", result: "Result", merged: "Merged", blocked: "Blocked", waiting: "Waiting", started: "Started", progress: "Progress", done: "Done", note: "Note" };
// What a notice says is a code from this list, and the ONE sentence the phone shows for it: never words
// of the machine's or the relay's.
export const PROGRESS_WORDS = {
  "file-replaced": "The progress log at the machine was replaced or cut short, so the machine stopped following it. Nothing was sent again. It needs a look at the machine.",
  following: "The progress log at the machine is as it was again, and is being followed.",
  "lines-skipped": "line(s) of the progress log could not be read at the machine and were left out."
};
// The labels a text's lines may open with, in their order; a line with none of them is plain words.
export const PROGRESS_LABELS = ["Asked", "Happened", "Means", "Next"];
const ENTRY_ID = /^[\x21\x23-\x5b\x5d-\x7e]{1,128}$/;
const PLAIN = /^[^\x00-\x1f\x7f-\x9f]*$/;
const PROGRESS_LIMITS = { title: 100, text: 2000, area: 60, lane: 32, task: 64 };

function progressHead(bodyBytes, kind, horde, machine) {
  let b;
  try { b = JSON.parse(fromUtf8(bodyBytes)); } catch (x) { return { error: "the progress body is not JSON" }; }
  if (!b || b.v !== 1 || b.kind !== kind) return { error: "not a version 1 " + kind };
  if (b.horde !== horde || b.machine !== machine) return { error: "the progress body names another horde or machine" };
  return { body: b };
}
const label = (v, most) => (typeof v === "string" && v.length <= most && PLAIN.test(v) ? v : "");

// An entries body, read: { ok, reason, value } with value { backfill, entries, dropped }. Each entry is
// { id, n, at, kind, title, text, area, lane, task, corrects } - at its time in milliseconds, kind one of
// PROGRESS_KINDS' (a word off the list is "note"), the labels "" when it carries none. An entry that
// does not hold together is dropped, and counted in value.dropped.
export function readProgressEntries(bodyBytes, horde, machine) {
  const h = progressHead(bodyBytes, "progress-entries", horde, machine);
  if (h.error) return { ok: false, reason: h.error, value: null };
  const b = h.body;
  if (typeof b.backfill !== "boolean" || !Array.isArray(b.entries)) return { ok: false, reason: "the entries body has no entries list", value: null };
  const entries = [];
  let dropped = 0;
  for (const e of b.entries) {
    const ok = e && typeof e.id === "string" && ENTRY_ID.test(e.id) && Number.isSafeInteger(e.n) && e.n >= 1 && timeOf(e.ts) > 0 &&
      typeof e.title === "string" && e.title.trim() !== "" && e.title.length <= PROGRESS_LIMITS.title && PLAIN.test(e.title) &&
      typeof e.text === "string" && e.text.length <= PROGRESS_LIMITS.text && (e.corrects === undefined || (typeof e.corrects === "string" && ENTRY_ID.test(e.corrects)));
    if (!ok) { dropped++; continue; }
    entries.push({ id: e.id, n: e.n, at: timeOf(e.ts), kind: Object.prototype.hasOwnProperty.call(PROGRESS_KINDS, e.kind) ? e.kind : "note", title: e.title, text: e.text,
      area: label(e.area, PROGRESS_LIMITS.area), lane: label(e.lane, PROGRESS_LIMITS.lane), task: label(e.task, PROGRESS_LIMITS.task), corrects: e.corrects || "" });
  }
  return { ok: true, reason: "", value: { backfill: b.backfill, entries, dropped } };
}

// A notice body, read: { ok, reason, value } with value { code, count }. A code off the list is refused:
// the phone never shows a word it did not choose.
export function readProgressNotice(bodyBytes, horde, machine) {
  const h = progressHead(bodyBytes, "progress-notice", horde, machine);
  if (h.error) return { ok: false, reason: h.error, value: null };
  const b = h.body;
  if (!Object.prototype.hasOwnProperty.call(PROGRESS_WORDS, b.code)) return { ok: false, reason: "the notice's code is not one this phone knows", value: null };
  return { ok: true, reason: "", value: { code: b.code, count: Number.isSafeInteger(b.count) && b.count > 0 ? b.count : 0 } };
}

// A text as its paragraphs: one for each line that holds words, { label, text } - label one of
// PROGRESS_LABELS when the line opens with it and a colon, else "" and the line as it stands.
export function progressParagraphs(text) {
  const out = [];
  for (const line of String(text).split("\n")) {
    if (!line.trim()) continue;
    const at = line.indexOf(":");
    const name = at > 0 ? line.slice(0, at) : "";
    if (PROGRESS_LABELS.indexOf(name) >= 0) out.push({ label: name, text: line.slice(at + 1).trim() });
    else out.push({ label: "", text: line });
  }
  return out;
}

// A reading position as the store keeps it, read: { id, n } - the last entry read and its line number -
// or null for anything else, so a damaged record is no position and never a wrong one.
export function progressPosition(value) {
  if (!value || typeof value !== "object" || typeof value.id !== "string" || !ENTRY_ID.test(value.id) || !Number.isSafeInteger(value.n) || value.n < 1) return null;
  return { id: value.id, n: value.n };
}

// "12 Oct 14:05": the day and the time, for a log whose entries are not in the order of their times.
export function dayTime(ms, offsetMinutes) { const p = localParts(ms, offsetMinutes); return p ? p.day + " " + MONTHS[p.month] + " " + two(p.hour) + ":" + two(p.minute) : ""; }

// The log as the phone shows it, from what it holds in memory:
//   entries   every entry read (repeats included), each with seq (its envelope's)
//   notices   every notice read, each with seq
//   position  the reading position (progressPosition's), or null
// -> { items, unread, readIndex, newest, stopped, skipped }. items are the entries OLDEST TO NEWEST BY
// THE ORDER THEY WERE WRITTEN (n; never by time), each once by id - the first that came stands - as
// { id, n, said, kind, kindWord, title, text, paragraphs, area, lane, task, corrects, correctsTitle,
// corrections }. A CORRECTION (an entry that names another in corrects) is an entry of the log in its
// own place, and is ALSO shown on the entry it corrects: that entry's corrections lists it. corrects
// that names an entry this phone does not hold, or itself, attaches to nothing; correctsTitle is then "".
// readIndex is the place of the position among the items - by its id, or, when that entry is no longer
// held, the last one written at or before it - and -1 for none; unread how many items come after it.
// stopped: the newest word on the file is that the machine stopped following it; skipped: how many
// lines the machine said it left out.
export function progressLog({ entries = [], notices = [], position = null }) {
  const byId = new Map();
  for (const e of entries) { const had = byId.get(e.id); if (!had || e.seq < had.seq) byId.set(e.id, e); }
  const ordered = [...byId.values()].sort((a, b) => (a.n - b.n) || (a.seq - b.seq));
  const items = ordered.map((e) => ({ id: e.id, n: e.n, said: e.at, kind: e.kind, kindWord: PROGRESS_KINDS[e.kind], title: e.title, text: e.text, paragraphs: progressParagraphs(e.text),
    area: e.area, lane: e.lane, task: e.task, corrects: e.corrects, correctsTitle: "", corrections: [] }));
  const at = new Map(items.map((it) => [it.id, it]));
  for (const it of items) {
    const target = it.corrects && it.corrects !== it.id ? at.get(it.corrects) : null;
    if (!target) continue;
    it.correctsTitle = target.title;
    target.corrections.push({ id: it.id, said: it.said, title: it.title, paragraphs: it.paragraphs });
  }
  const pos = progressPosition(position);
  let readIndex = -1;
  if (pos) {
    readIndex = items.findIndex((it) => it.id === pos.id);
    if (readIndex < 0) for (let i = 0; i < items.length && items[i].n <= pos.n; i++) readIndex = i;
  }
  let stopped = false, stopSeq = -1, skipped = 0;
  for (const n of notices) {
    if (n.code === "lines-skipped") skipped += n.count;
    else if (n.seq > stopSeq) { stopSeq = n.seq; stopped = n.code === "file-replaced"; }
  }
  const last = items.length ? items[items.length - 1] : null;
  return { items, unread: items.length - 1 - readIndex, readIndex, newest: last ? { id: last.id, n: last.n } : null, stopped, skipped };
}

// --- the cards channel (channels/cards/Channel.ps1) ---

// THE FLEET AT A GLANCE, machine to phone only: one whole snapshot per machine - a card per lane and one
// for the Thrall, with the map of which lanes each area of the progress log belongs to. Only the latest
// is kept in the mailbox; the phone keeps the newest it opened, by its envelope's seq. A lane's card opens
// its STREAM: the progress log, filtered to that lane (entryLanes). The phone sends nothing on this channel.
const CARD_FORMS = ["standard", "other", "missing", "unreadable"];
const CARD_LANE = /^[A-Za-z0-9][A-Za-z0-9 ._-]{0,31}$/;
const CARD_TEXT = 400;
const cardText = (v) => (typeof v === "string" && v.length <= CARD_TEXT && PLAIN.test(v) ? v : "");
const cardCount = (v) => (Number.isSafeInteger(v) && v >= 0 ? v : null);
const cardList = (v, ok) => (Array.isArray(v) ? v.filter(ok) : []);
// What the phone says of a card's form, in its own words.
export const CARD_FORM_WORDS = {
  standard: "",
  other: "This lane's status is not in the standard form; it is shown as it stands.",
  missing: "This lane has no status file.",
  unreadable: "This lane's status file could not be read."
};
// What the phone says of a card's form: its own sentence, and for a status file not in the standard form
// the rules it breaks, as the machine's status reader words them (fleet/StatusPanel.ps1,
// ConvertFrom-HordeFleetStatusBytes; plain words, held to cardText like every text of a card).
export function cardFormNote(form, problems) {
  if (form === "other" && problems) return "This lane's status is not in the standard form. What the status reader says of it: " + problems + ". It is shown as it stands.";
  return CARD_FORM_WORDS[form] || "";
}
// The one sentence the stream page says of how far back it goes (channels/progress/Channel.ps1,
// keepEnvelopes: the phone holds the last 100 envelopes of the log).
export const STREAM_LIMIT_WORDS = "This phone holds only the newest part of the progress log (its last 100 sends), so a quiet lane may show few of its older updates here.";

// A cards body, read: { ok, reason, value } with value { snapshot, made, name, thrall, cards, cardsLeftOut,
// areas }. A card that does not hold together is dropped and counted in value.dropped; a text past its
// length or holding a control character is shown as none.
export function readCardsSnapshot(bodyBytes, horde, machine) {
  const no = (reason) => ({ ok: false, reason, value: null });
  let b;
  try { b = JSON.parse(fromUtf8(bodyBytes)); } catch (x) { return no("the cards body is not JSON"); }
  if (!b || b.v !== 1 || b.kind !== "cards-snapshot") return no("not a version 1 cards snapshot");
  if (b.horde !== horde || b.machine !== machine) return no("the cards body names another horde or machine");
  if (typeof b.snapshot !== "string" || !/^[0-9a-f]{64}$/.test(b.snapshot)) return no("the cards snapshot has no hash");
  if (!Array.isArray(b.cards) || !b.thrall || typeof b.thrall !== "object" || !Array.isArray(b.areas)) return no("the cards snapshot has no cards, Thrall or areas");
  const name = cardText(b.name).trim();
  if (!name) return no("the cards snapshot names no machine");
  let dropped = 0;
  const cards = [];
  // ONE ID IS ONE CARD, and "thrall" is the Thrall's (surfaces/pwa/page/lane-card.js, THRALL_LANE): a lane
  // card by that id never opened, and a second card of one id was drawn as the first (review of PR 244).
  const lanesSeen = new Set(["thrall"]);
  for (const c of b.cards) {
    if (!c || typeof c !== "object" || typeof c.lane !== "string" || !CARD_LANE.test(c.lane) || CARD_FORMS.indexOf(c.form) < 0 || lanesSeen.has(c.lane)) { dropped++; continue; }
    lanesSeen.add(c.lane);
    // The note is the form's sentence, then why the card has an id of its own when another lane folder
    // of the machine gives the same one (idNote; F, review of PR 244: a card named lane-5, never why).
    cards.push({ lane: c.lane, name: cardText(c.name) || c.lane, form: c.form, asOf: timeOf(c.asOf), now: cardText(c.now), lastDone: cardText(c.lastDone), waitingOn: cardText(c.waitingOn),
      blocked: c.blocked === "yes" || c.blocked === "no" ? c.blocked : "", blockedText: cardText(c.blockedText), note: [cardFormNote(c.form, cardText(c.problems)), cardText(c.idNote)].filter((x) => x).join(" "),
      tasksOpen: cardCount(c.tasksOpen), doneWeek: cardCount(c.doneWeek), refused: cardList(c.refused, (x) => typeof x === "string" && WORD.test(x.toLowerCase())) });
  }
  const t = b.thrall;
  const census = t.census && typeof t.census === "object" && cardCount(t.census.running) !== null && cardCount(t.census.waiting) !== null ? { running: t.census.running, waiting: t.census.waiting } : null;
  const thrall = { asOf: timeOf(t.asOf), now: cardText(t.now), hasStatus: t.hasStatus === true, orcs: cardCount(t.orcs) || 0, working: cardCount(t.working) || 0, waitingFounder: cardCount(t.waitingFounder) || 0,
    blocked: cardCount(t.blocked) || 0, unknown: cardCount(t.unknown) || 0, waitingFounderLanes: cardList(t.waitingFounderLanes, (x) => typeof x === "string" && CARD_LANE.test(x)), census };
  const areas = [];
  for (const a of b.areas) {
    if (!a || typeof a.area !== "string" || !a.area.trim() || a.area.length > 60 || !PLAIN.test(a.area) || !Array.isArray(a.lanes)) continue;
    const lanes = a.lanes.filter((x) => typeof x === "string" && CARD_LANE.test(x));
    if (lanes.length) areas.push({ area: a.area, lanes });
  }
  return { ok: true, reason: "", value: { snapshot: b.snapshot, made: timeOf(b.made), name, thrall, cards, cardsLeftOut: cardCount(b.cardsLeftOut) || 0, areas, areasLeftOut: cardCount(b.areasLeftOut) || 0, dropped } };
}

// The lanes a log entry belongs to: the lanes it names itself (lane, comma separated), which WIN over its
// area; else the lanes the map gives its area (compared with case and outer spaces set aside); else none -
// an entry of no lane is shown only in the Thrall's stream.
export function entryLanes(entry, areas) {
  const own = String(entry && entry.lane || "").split(",").map((x) => x.trim()).filter((x) => x);
  if (own.length) return own;
  const area = String(entry && entry.area || "").trim().toLowerCase();
  if (!area) return [];
  for (const a of areas || []) if (a.area.trim().toLowerCase() === area) return a.lanes.slice();
  return [];
}

// The cards of every machine the phone holds a snapshot of, MERGED BY MACHINE NAME: per name, the newest
// snapshot (by when it was made, then by its envelope's seq) stands; two pairings that report one name
// show it once. snapshots: [{ entry, seq, value }] (value readCardsSnapshot's). -> { machines, thrall,
// cards }: machines [{ name, entry, made, areas, cardsLeftOut, areasLeftOut }] by name; thrall one card per machine;
// cards every lane card, each with its machine's name and entry, ordered by lane, then machine.
export function mergeCards(snapshots) {
  const byName = new Map();
  for (const s of snapshots || []) {
    if (!s || !s.value) continue;
    const had = byName.get(s.value.name);
    if (!had || s.value.made > had.value.made || (s.value.made === had.value.made && s.seq > had.seq)) byName.set(s.value.name, s);
  }
  const names = [...byName.keys()].sort();
  const machines = [], thrall = [], cards = [];
  for (const name of names) {
    const s = byName.get(name);
    machines.push({ name, entry: s.entry, made: s.value.made, areas: s.value.areas, cardsLeftOut: s.value.cardsLeftOut, areasLeftOut: s.value.areasLeftOut || 0 });
    thrall.push({ ...s.value.thrall, machine: name, entry: s.entry });
    for (const c of s.value.cards) cards.push({ ...c, machine: name, entry: s.entry });
  }
  cards.sort((a, b) => (a.lane < b.lane ? -1 : a.lane > b.lane ? 1 : a.machine < b.machine ? -1 : a.machine > b.machine ? 1 : 0));
  return { machines, thrall, cards };
}

// A lane's stream: the items of a progress log (progressLog's) that belong to the lane, in their order.
// lane "" is the Thrall's: every item.
export function laneStream(items, lane, areas) {
  if (!lane) return items.slice();
  return items.filter((it) => entryLanes(it, areas).indexOf(lane) >= 0);
}

// HIS PLACE MOVES ONLY IN THE WHOLE LOG OF THE PICKED HORDE: true for the stream { entry, lane } only when it
// is the Thrall's (lane "", the whole log) of the picked pairing. A lane's stream skips other lanes'
// entries, so reading on in it, or "Mark all read" there, would mark those read unseen; another
// pairing's log keeps no place of the picked one's (surfaces/pwa/page/app.js, readAsSeen).
export function streamMovesPlace(stream, picked) {
  return !!stream && stream.lane === "" && stream.entry === picked;
}

// "4 min ago", "3 h ago", "2 days ago": how old a card's word is, from its time and now (milliseconds);
// "" for no time. A time ahead of now (a clock off by a little) is "just now".
export function ageWords(at, nowMs) {
  if (!(at > 0) || !(nowMs > 0)) return "";
  const min = Math.floor((nowMs - at) / 60000);
  if (min < 1) return "just now";
  if (min < 60) return min + " min ago";
  const h = Math.floor(min / 60);
  if (h < 48) return h + " h ago";
  return Math.floor(h / 24) + " days ago";
}

// --- the notices channel (channels/notices/Channel.ps1; notices/Decide.ps1 decides what is one) ---

// The follow switch of one lane, as the phone signs it with the passkey and seals it to that lane's machine:
// exactly these members, in this order, which the machine reads strictly (Read-HordeNoticesChannelFollow).
// lane: the card's lane id, or "thrall"; machine: the key id of the machine whose card it is.
const NOTICE_LANE = /^[A-Za-z0-9][A-Za-z0-9 ._-]{0,31}$/;
export function followBody({ setId, machine, lane, on }) {
  if (!/^[0-9a-f]{32}$/.test(setId)) throw new Error("a setId is 32 lower-case hex");
  if (!KEY_ID.test(machine)) throw new Error("the machine is a key id");
  if (typeof lane !== "string" || !NOTICE_LANE.test(lane)) throw new Error("the lane is a card's lane id");
  if (on !== true && on !== false) throw new Error("on is true or false");
  return utf8(JSON.stringify({ v: 1, setId, machine, lane, on }));
}

// A notices body, read: { ok, reason, value: { follows: { lane: true|false }, notices: [{ n, id, said (ms),
// kind, from, text, lane, entry }], dropped } }. A notice that does not hold together is dropped and
// counted; the switches are what the machine holds, as it sent them.
const NOTICE_KINDS = ["notify", "progress", "cutoff"];
export function readNotices(bodyBytes, horde, machine) {
  const no = (reason) => ({ ok: false, reason, value: null });
  let b;
  try { b = JSON.parse(fromUtf8(bodyBytes)); } catch (x) { return no("the notices body is not JSON"); }
  if (!b || b.v !== 1 || b.kind !== "notices") return no("not a version 1 notices body");
  if (b.horde !== horde || b.machine !== machine) return no("the notices body names another horde or machine");
  if (!b.follows || typeof b.follows !== "object" || Array.isArray(b.follows) || !Array.isArray(b.notices)) return no("the notices body has no switches or no notices");
  const follows = {};
  for (const k of Object.keys(b.follows)) if (NOTICE_LANE.test(k) && (b.follows[k] === true || b.follows[k] === false)) follows[k] = b.follows[k];
  const notices = [];
  let dropped = 0;
  for (const x of b.notices) {
    const ok = x && Number.isSafeInteger(x.n) && x.n > 0 && typeof x.id === "string" && /^[0-9a-f]{32}$/.test(x.id) && NOTICE_KINDS.indexOf(x.kind) >= 0 &&
      typeof x.from === "string" && x.from.length <= 60 && PLAIN.test(x.from) && typeof x.text === "string" && x.text.length <= 2000 && PLAIN.test(x.text) &&
      typeof x.lane === "string" && (x.lane === "" || NOTICE_LANE.test(x.lane)) && typeof x.entry === "string" && (x.entry === "" || ENTRY_ID.test(x.entry));
    if (!ok) { dropped++; continue; }
    notices.push({ n: x.n, id: x.id, said: timeOf(x.ts), kind: x.kind, from: x.from || "Horde", text: x.text, lane: x.lane, entry: x.entry });
  }
  return { ok: true, reason: "", value: { follows, notices, dropped } };
}

// The notices of every machine the phone holds, NEWEST FIRST, each once (by its id), with read or unread:
// held [{ entry (the pairing), machine (its name, for words), notices }], read a Set of the ids he has read.
// -> { items: [{ ...notice, entry, machine, read }], unread }. A notice of the same time is ordered by its
// machine's number for it, newest first.
export function noticeList(held, read) {
  const seen = new Set();
  const items = [];
  for (const h of held || []) for (const x of h.notices || []) {
    if (seen.has(x.id)) continue;
    seen.add(x.id);
    items.push({ ...x, entry: h.entry, machine: h.machine, read: !!(read && read.has(x.id)) });
  }
  items.sort((a, b) => (b.said - a.said) || (b.n - a.n));
  return { items, unread: items.filter((x) => !x.read).length };
}
