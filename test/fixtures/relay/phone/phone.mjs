// A simulated founder's phone, for the relay's end-to-end suite (test/test-relay-phone-e2e.ps1): a
// passkey and a phone identity key made with WebCrypto - the SubtleCrypto API a PWA has - and every byte
// the phone sends built here, from the specification in relay/Envelope.ps1, relay/Hpke.ps1,
// relay/Pairing.ps1 and relay/Trust.ps1. Nothing here is PowerShell's: the machine side is checked against
// bytes it did not make itself.
//
//   node test/fixtures/relay/phone/phone.mjs <command> <state.json> <in.json> <out.json>
//
// The state file holds this phone's PRIVATE keys between commands, as JWK. It is the suite's own, made
// under its temporary folder and deleted with it; nothing private is ever committed.
//
// COMMANDS (in.json and out.json are JSON objects):
//   register   in { offer, label }        -> out { response, fingerprint, deviceKeyId }
//              Answers a pairing offer with a passkey registration, attestation "none" (WebAuthn L3
//              6.5): rpIdHash, flags UP|UV|AT, counter 0, a zero aaguid, the credential id and its COSE
//              key. The fingerprint is relay/Pairing.ps1's, so the suite can type it at the "machine".
//   phone-key  in { }                     -> out { envelope, key }
//              Makes the phone identity key (ECDH P-256) and announces it: an envelope on channel
//              trust, kind phone-key, signed with the passkey, whose body carries the key and a SECOND
//              passkey assertion over relay/Trust.ps1's vouch challenge for it.
//   open       in { envelope }            -> out { ok, reason, body, header }
//              Verifies the machine's ES256 signature against the signing key the offer pinned, and
//              opens the body with the phone identity key.
//   answer     in { number, wordingVersion, text, answerId? }  -> out { envelope, key, answerId }
//              The founder's answer: an envelope on channel decisions, kind answer, sealed to the
//              machine's agreement key and signed with a passkey assertion over SHA-256 of its signed
//              bytes.
//   resign     in { envelope }            -> out { envelope }
//              The same signed content signed again (a new assertion): what a passkey may do, and what
//              the journal must still see as one envelope.
const [, , cmd, statePath, inPath, outPath] = process.argv;
import { readFileSync, writeFileSync, existsSync } from "node:fs";

const s = globalThis.crypto.subtle;
const enc = new TextEncoder();
const dec = new TextDecoder();
const b64u = (b) => Buffer.from(b).toString("base64url");
const unb64u = (t) => new Uint8Array(Buffer.from(t, "base64url"));
const hex = (b) => Buffer.from(b).toString("hex");
const unhex = (t) => new Uint8Array(Buffer.from(t, "hex"));
const cat = (...a) => { const n = a.reduce((x, y) => x + y.length, 0); const o = new Uint8Array(n); let i = 0; for (const p of a) { o.set(p, i); i += p.length; } return o; };
const sha256 = async (b) => new Uint8Array(await s.digest("SHA-256", b));
const rnd = (n) => globalThis.crypto.getRandomValues(new Uint8Array(n));
const keyId = async (pub) => hex((await sha256(pub)).slice(0, 16));

// --- DER for WebAuthn signatures (WebCrypto signs P1363) ---
function derInt(b) { let i = 0; while (i < b.length - 1 && b[i] === 0) i++; let v = b.slice(i); if (v[0] & 0x80) v = cat(new Uint8Array([0]), v); return cat(new Uint8Array([2, v.length]), v); }
function toDer(sig) { const r = derInt(sig.slice(0, 32)), q = derInt(sig.slice(32)); return cat(new Uint8Array([0x30, r.length + q.length]), r, q); }

// --- CBOR, only what a registration needs ---
function head(major, n) {
  if (n < 24) return new Uint8Array([(major << 5) | n]);
  if (n < 0x100) return new Uint8Array([(major << 5) | 24, n]);
  return new Uint8Array([(major << 5) | 25, n >> 8, n & 255]);
}
function cbor(v) {
  if (typeof v === "number") return v >= 0 ? head(0, v) : head(1, -1 - v);
  if (typeof v === "string") { const b = enc.encode(v); return cat(head(3, b.length), b); }
  if (v instanceof Uint8Array) return cat(head(2, v.length), v);
  if (v.map) return cat(head(5, v.map.length), ...v.map.flatMap(([k, x]) => [cbor(k), cbor(x)]));
  throw new Error("cannot encode");
}

// --- HKDF and HPKE (RFC 9180 base mode, DHKEM(P-256, HKDF-SHA256), HKDF-SHA256, AES-256-GCM) ---
async function hmac(key, data) { const k = await s.importKey("raw", key.length ? key : new Uint8Array(32), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]); return new Uint8Array(await s.sign("HMAC", k, data)); }
async function extract(salt, ikm) { return hmac(salt, ikm); }
async function expand(prk, info, len) { let t = new Uint8Array(0), out = new Uint8Array(0); for (let i = 1; out.length < len; i++) { t = await hmac(prk, cat(t, info, new Uint8Array([i]))); out = cat(out, t); } return out.slice(0, len); }
const KEM_ID = cat(enc.encode("KEM"), new Uint8Array([0x00, 0x10]));
const SUITE_ID = cat(enc.encode("HPKE"), new Uint8Array([0x00, 0x10, 0x00, 0x01, 0x00, 0x02]));
const label = (suite, l) => cat(enc.encode("HPKE-v1"), suite, enc.encode(l));
const labeledExtract = (salt, suite, l, ikm) => extract(salt, cat(label(suite, l), ikm));
const labeledExpand = (prk, suite, l, info, len) => expand(prk, cat(new Uint8Array([len >> 8, len & 255]), label(suite, l), info), len);
async function ecdh(priv, pubRaw) { const pub = await s.importKey("raw", pubRaw, { name: "ECDH", namedCurve: "P-256" }, false, []); return new Uint8Array(await s.deriveBits({ name: "ECDH", public: pub }, priv, 256)); }
async function sharedSecret(dh, encBytes, pkR) { const prk = await labeledExtract(new Uint8Array(0), KEM_ID, "eae_prk", dh); return labeledExpand(prk, KEM_ID, "shared_secret", cat(encBytes, pkR), 32); }
async function keySchedule(ss, info) {
  const e = new Uint8Array(0);
  const ksc = cat(new Uint8Array([0]), await labeledExtract(e, SUITE_ID, "psk_id_hash", e), await labeledExtract(e, SUITE_ID, "info_hash", info));
  const secret = await labeledExtract(ss, SUITE_ID, "secret", e);
  return { key: await labeledExpand(secret, SUITE_ID, "key", ksc, 32), nonce: await labeledExpand(secret, SUITE_ID, "base_nonce", ksc, 12) };
}
async function gcmSeal(key, nonce, aad, pt) { const k = await s.importKey("raw", key, "AES-GCM", false, ["encrypt"]); return new Uint8Array(await s.encrypt({ name: "AES-GCM", iv: nonce, additionalData: aad }, k, pt)); }
async function gcmOpen(key, nonce, aad, ct) { const k = await s.importKey("raw", key, "AES-GCM", false, ["decrypt"]); return new Uint8Array(await s.decrypt({ name: "AES-GCM", iv: nonce, additionalData: aad }, k, ct)); }
async function hpkeSeal(pkR, info, aad, pt) {
  const eph = await s.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]);
  const encBytes = new Uint8Array(await s.exportKey("raw", eph.publicKey));
  const ks = await keySchedule(await sharedSecret(await ecdh(eph.privateKey, pkR), encBytes, pkR), info);
  return { enc: encBytes, sealed: await gcmSeal(ks.key, ks.nonce, aad, pt) };
}
async function hpkeOpen(priv, pkR, encBytes, info, aad, sealed) {
  const ks = await keySchedule(await sharedSecret(await ecdh(priv, encBytes), encBytes, pkR), info);
  return gcmOpen(ks.key, ks.nonce, aad, sealed);
}

// --- the envelope (relay/Envelope.ps1: the strings below are its whole specification) ---
const AAD = "horde-relay/envelope/v1 aad\n";
const INFO = "horde-relay/envelope/v1 content-key";
const SIGNED = "horde-relay/envelope/v1 signed\n";
const headerText = (h) => '{"v":1,"kind":"' + h.kind + '","channel":"' + h.channel + '","from":"' + h.from + '","to":[' + h.to.map((t) => '"' + t + '"').join(",") + '],"seq":' + h.seq + ',"nonce":"' + h.nonce + '","ts":' + h.ts + "}";
const recipientsText = (rs) => "[" + rs.map((r) => '{"kid":"' + r.kid + '","enc":"' + r.enc + '","key":"' + r.key + '"}').join(",") + "]";
const signedBytes = (ht, rt, ct) => enc.encode(SIGNED + ht + "\n" + rt + "\n" + ct);

async function passkeyAssert(st, challenge) {
  // A WebAuthn get() with user verification: authenticatorData is rpIdHash, flags UP|UV, counter 0
  // (a synced passkey's), and the signature is over authenticatorData || SHA-256(clientDataJSON).
  const priv = await s.importKey("jwk", st.passkey, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const ad = cat(await sha256(enc.encode(st.rpId)), new Uint8Array([0x05, 0, 0, 0, 0]));
  const cdj = enc.encode(JSON.stringify({ type: "webauthn.get", challenge: b64u(challenge), origin: st.origin, crossOrigin: false }));
  const p1363 = new Uint8Array(await s.sign({ name: "ECDSA", hash: "SHA-256" }, priv, cat(ad, await sha256(cdj))));
  return { authenticatorData: ad, clientDataJSON: cdj, signature: toDer(p1363) };
}

function nextSeq(st, channel) { st.seq = st.seq || {}; st.seq[channel] = (st.seq[channel] || 0) + 1; return st.seq[channel]; }

async function sealEnvelope(st, kind, channel, bodyBytes) {
  const machineAgree = unb64u(st.offer.agreePublic);
  const h = { kind, channel, from: st.deviceKeyId, to: [await keyId(machineAgree)], seq: nextSeq(st, channel), nonce: hex(rnd(12)), ts: Date.now() };
  const ht = headerText(h);
  const aad = enc.encode(AAD + ht);
  const cek = rnd(32);
  const ct = await gcmSeal(cek, unhex(h.nonce), aad, bodyBytes);
  const box = await hpkeSeal(machineAgree, enc.encode(INFO), aad, cek);
  const rt = recipientsText([{ kid: h.to[0], enc: b64u(box.enc), key: b64u(box.sealed) }]);
  const ctText = b64u(ct);
  return { h, ht, rt, ctText };
}
async function signEnvelope(st, parts) {
  const a = await passkeyAssert(st, await sha256(signedBytes(parts.ht, parts.rt, parts.ctText)));
  const sig = '{"alg":"webauthn.get","authenticatorData":"' + b64u(a.authenticatorData) + '","clientDataJSON":"' + b64u(a.clientDataJSON) + '","signature":"' + b64u(a.signature) + '"}';
  return '{"header":' + parts.ht + ',"recipients":' + parts.rt + ',"ct":"' + parts.ctText + '","sig":' + sig + "}";
}
const replayKey = (h) => h.from + "/" + h.channel + "/" + h.seq + "/" + h.nonce;

async function register(st, input) {
  const offer = JSON.parse(input.offer);
  const kp = await s.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const pub = new Uint8Array(await s.exportKey("raw", kp.publicKey));
  const credId = rnd(32);
  const rpId = offer.rpId, origin = offer.origins[0];
  const challenge = await sha256(enc.encode("horde-relay/pairing/v1 challenge\n" + input.offer));
  const cose = cbor({ map: [[1, 2], [3, -7], [-1, 1], [-2, pub.slice(1, 33)], [-3, pub.slice(33, 65)]] });
  const ad = cat(await sha256(enc.encode(rpId)), new Uint8Array([0x45, 0, 0, 0, 0]), new Uint8Array(16), new Uint8Array([0, credId.length]), credId, cose);
  const att = cbor({ map: [["fmt", "none"], ["attStmt", { map: [] }], ["authData", ad]] });
  const cdj = enc.encode(JSON.stringify({ type: "webauthn.create", challenge: b64u(challenge), origin, crossOrigin: false }));
  const response = '{"v":1,"kind":"horde-relay-pairing-response","offer":"' + offer.offer + '","code":"' + offer.code + '","rawId":"' + b64u(credId) + '","clientDataJSON":"' + b64u(cdj) +
    '","attestationObject":"' + b64u(att) + '","label":"' + input.label + '","prf":false}';
  // relay/Pairing.ps1's fingerprint: SHA-256 of the domain, the challenge, the point, the credential id's
  // length (2 bytes) and the id, and the rpId; the first 8 bytes as a number modulo 10^12.
  const fh = await sha256(cat(enc.encode("horde-relay/pairing/v1 fingerprint\n"), challenge, pub, new Uint8Array([credId.length >> 8, credId.length & 255]), credId, enc.encode(rpId)));
  let n = 0n;
  for (let i = 0; i < 8; i++) n = (n * 256n + BigInt(fh[i])) % 1000000000000n;
  const d = n.toString().padStart(12, "0");
  st.passkey = await s.exportKey("jwk", kp.privateKey);
  st.devicePublic = b64u(pub);
  st.deviceKeyId = await keyId(pub);
  st.rpId = rpId; st.origin = origin; st.offer = offer; st.offerText = input.offer;
  return { response, fingerprint: d.slice(0, 4) + "-" + d.slice(4, 8) + "-" + d.slice(8, 12), deviceKeyId: st.deviceKeyId };
}

async function phoneKey(st) {
  const kp = await s.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]);
  const pub = new Uint8Array(await s.exportKey("raw", kp.publicKey));
  st.phoneKey = await s.exportKey("jwk", kp.privateKey);
  st.phonePublic = b64u(pub);
  // relay/Trust.ps1's vouch: SHA-256 of the domain, the horde and the key, each on its own line.
  const v = await passkeyAssert(st, await sha256(enc.encode("horde-relay/phone-key/v1 vouch\n" + st.offer.horde + "\n" + b64u(pub))));
  const body = '{"v":1,"agreePublic":"' + b64u(pub) + '","authenticatorData":"' + b64u(v.authenticatorData) + '","clientDataJSON":"' + b64u(v.clientDataJSON) + '","signature":"' + b64u(v.signature) + '"}';
  const parts = await sealEnvelope(st, "phone-key", "trust", enc.encode(body));
  return { envelope: await signEnvelope(st, parts), key: replayKey(parts.h), agreeKeyId: await keyId(pub) };
}

async function open(st, input) {
  const e = JSON.parse(input.envelope);
  const h = e.header;
  const ht = headerText(h);
  const rt = recipientsText(e.recipients);
  if ('{"header":' + ht + ',"recipients":' + rt + ',"ct":"' + e.ct + '","sig":{"alg":"ES256","value":"' + e.sig.value + '"}}' !== input.envelope) return { ok: false, reason: "not canonical, or not signed ES256" };
  const machineSign = unb64u(st.offer.signPublic);
  if (h.from !== st.offer.machine || h.from !== await keyId(machineSign)) return { ok: false, reason: "not from the machine this phone paired with" };
  const pub = await s.importKey("raw", machineSign, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
  if (!await s.verify({ name: "ECDSA", hash: "SHA-256" }, pub, unb64u(e.sig.value), signedBytes(ht, rt, e.ct))) return { ok: false, reason: "the machine's signature does not verify" };
  const mine = await keyId(unb64u(st.phonePublic));
  const r = e.recipients.find((x) => x.kid === mine);
  if (!r) return { ok: false, reason: "not sealed to this phone" };
  const priv = await s.importKey("jwk", st.phoneKey, { name: "ECDH", namedCurve: "P-256" }, false, ["deriveBits"]);
  const aad = enc.encode(AAD + ht);
  try {
    const cek = await hpkeOpen(priv, unb64u(st.phonePublic), unb64u(r.enc), enc.encode(INFO), aad, unb64u(r.key));
    const body = await gcmOpen(cek, unhex(h.nonce), aad, unb64u(e.ct));
    return { ok: true, reason: "", header: h, body: JSON.parse(dec.decode(body)) };
  } catch (x) { return { ok: false, reason: "it does not open: " + x.message }; }
}

async function answer(st, input) {
  const answerId = input.answerId || hex(rnd(16));
  // JSON.stringify escapes what JSON must and nothing else; the machine reads it with a JSON parser.
  const body = JSON.stringify({ v: 1, answerId, number: input.number, wordingVersion: input.wordingVersion, text: input.text });
  const parts = await sealEnvelope(st, "answer", "decisions", enc.encode(body));
  return { envelope: await signEnvelope(st, parts), key: replayKey(parts.h), answerId };
}

async function resign(st, input) {
  const e = JSON.parse(input.envelope);
  return { envelope: await signEnvelope(st, { ht: headerText(e.header), rt: recipientsText(e.recipients), ctText: e.ct }) };
}

const st = existsSync(statePath) ? JSON.parse(readFileSync(statePath, "utf8")) : {};
const input = existsSync(inPath) ? JSON.parse(readFileSync(inPath, "utf8")) : {};
const commands = { register, "phone-key": phoneKey, open, answer, resign };
if (!commands[cmd]) { console.error("no such command: " + cmd); process.exit(2); }
const out = await commands[cmd](st, input);
writeFileSync(statePath, JSON.stringify(st));
writeFileSync(outPath, JSON.stringify(out));
