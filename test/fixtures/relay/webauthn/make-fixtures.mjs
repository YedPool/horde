// Makes test/fixtures/relay/webauthn/assertions.json: WebAuthn ES256 assertions, signed with WebCrypto -
// the same SubtleCrypto API a PWA has - so the PowerShell verifier (relay/WebAuthn.ps1) is checked
// against bytes it did not make itself.
//
// Run from the repository root:  node test/fixtures/relay/webauthn/make-fixtures.mjs
// Each run makes a fresh key pair and keeps only its public half: no private key is ever written, so
// the committed file cannot be used to sign anything new. The cases are the same every run; the bytes
// differ (a new key, new challenges, randomised ECDSA).
//
// An authenticator signs authenticatorData || SHA-256(clientDataJSON) and returns the signature in
// DER (WebAuthn L3 6.3.3, COSE ES256). WebCrypto signs in IEEE P1363 (r || s), so it is converted to
// DER here, as spike S1 (2026-10-09) did. Every case is signed properly unless its name says the
// signature is the thing that is wrong, so each refusal is reached for its own reason and no other.
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const s = globalThis.crypto.subtle;
const enc = new TextEncoder();
const b64u = (b) => Buffer.from(b).toString("base64url");
const cat = (...a) => { const n = a.reduce((x, y) => x + y.length, 0); const o = new Uint8Array(n); let i = 0; for (const p of a) { o.set(p, i); i += p.length; } return o; };
const sha256 = async (b) => new Uint8Array(await s.digest("SHA-256", b));
function derInt(b) { let i = 0; while (i < b.length - 1 && b[i] === 0) i++; let v = b.slice(i); if (v[0] & 0x80) v = cat(new Uint8Array([0]), v); return cat(new Uint8Array([2, v.length]), v); }
function toDer(sig) { const r = derInt(sig.slice(0, 32)), q = derInt(sig.slice(32)); return cat(new Uint8Array([0x30, r.length + q.length]), r, q); }

const RP_ID = "relay.example.test";
const ORIGIN = "https://relay.example.test";
const UP = 0x01, UV = 0x04, BE = 0x08, BS = 0x10, AT = 0x40, ED = 0x80;

const kp = await s.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
const other = await s.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
const publicKey = new Uint8Array(await s.exportKey("raw", kp.publicKey));

function authData(rpIdHash, flags, count, extra = new Uint8Array(0)) {
  return cat(rpIdHash, new Uint8Array([flags]), new Uint8Array([(count >>> 24) & 255, (count >>> 16) & 255, (count >>> 8) & 255, count & 255]), extra);
}
async function sign(key, ad, cdj) { return new Uint8Array(await s.sign({ name: "ECDSA", hash: "SHA-256" }, key, cat(ad, await sha256(cdj)))); }

// One case: o says what differs from a valid assertion.
async function make(name, expect, o = {}) {
  const challenge = globalThis.crypto.getRandomValues(new Uint8Array(32));
  const rpIdHash = await sha256(enc.encode(o.rpId ?? RP_ID));
  const ad = authData(rpIdHash, o.flags ?? (UP | UV), o.count ?? 7, o.extra);
  const cd = o.clientData ?? { type: o.type ?? "webauthn.get", challenge: o.challengeText ?? b64u(o.signedChallenge ?? challenge), origin: o.origin ?? ORIGIN, crossOrigin: o.crossOrigin ?? false, ...(o.more ?? {}) };
  let cdj = o.clientDataBytes ?? enc.encode(o.clientDataText ? o.clientDataText(b64u(challenge)) : JSON.stringify(cd));
  let p1363 = await sign(o.signer ?? kp.privateKey, ad, cdj);
  if (o.signOther) p1363 = await sign(kp.privateKey, cat(ad, new Uint8Array([0])), cdj);
  let der = toDer(p1363);
  if (o.derTrailing) der = cat(der, new Uint8Array([0]));
  return { name, expect, requireUserVerification: o.requireUv ?? true, challenge: b64u(challenge), authenticatorData: b64u(ad), clientDataJSON: b64u(cdj), signature: b64u(der) };
}

const cases = [
  await make("valid: user present and verified", "accepted"),
  await make("valid: present only, verification not required", "accepted", { flags: UP, requireUv: false }),
  await make("refused: present only, verification required", "user verification", { flags: UP }),
  await make("valid: a synced passkey (backup eligible and backed up), counter 0", "accepted", { flags: UP | UV | BE | BS, count: 0 }),
  await make("valid: extension data present and flagged", "accepted", { flags: UP | UV | ED, extra: new Uint8Array([0xa0]) }),
  await make("valid: clientDataJSON members in another order", "accepted", { clientDataText: (c) => JSON.stringify({ origin: ORIGIN, crossOrigin: false, challenge: c, type: "webauthn.get" }) }),
  await make("refused: type is webauthn.create", "type", { type: "webauthn.create" }),
  await make("refused: the challenge is another one", "challenge", { signedChallenge: globalThis.crypto.getRandomValues(new Uint8Array(32)) }),
  await make("refused: the challenge is written with padding", "challenge", { clientDataText: (c) => JSON.stringify({ type: "webauthn.get", challenge: c + "=", origin: ORIGIN, crossOrigin: false }) }),
  await make("refused: another origin", "origin", { origin: "https://relay.example.test.evil.test" }),
  await make("refused: a cross-origin request", "crossOrigin", { crossOrigin: true }),
  await make("refused: a top origin is named", "topOrigin", { more: { topOrigin: "https://evil.example.test" } }),
  await make("refused: signed for another relying party", "rpIdHash", { rpId: "evil.example.test" }),
  await make("refused: user not present", "user presence", { flags: UV }),
  await make("refused: attested credential data in an assertion", "attested credential data", { flags: UP | UV | AT }),
  await make("refused: backed up but not backup eligible", "backup", { flags: UP | UV | BS }),
  await make("refused: bytes after the counter with no extension flag", "extension", { extra: new Uint8Array([0xa0]) }),
  await make("refused: extension flag with no extension bytes", "extension", { flags: UP | UV | ED }),
  await make("refused: the signature is over other bytes", "does not verify", { signOther: true }),
  await make("refused: signed by another key", "does not verify", { signer: other.privateKey }),
  await make("refused: DER with a byte after the signature", "DER", { derTrailing: true }),
  await make("refused: a member repeated in clientDataJSON", "more than once", { clientDataText: (c) => '{"type":"webauthn.get","challenge":"' + b64u(new Uint8Array(32)) + '","challenge":"' + c + '","origin":"' + ORIGIN + '","crossOrigin":false}' }),
  await make("refused: clientDataJSON that is not JSON", "not JSON", { clientDataBytes: enc.encode("type=webauthn.get") }),
  await make("refused: clientDataJSON that is not UTF-8", "UTF-8", { clientDataBytes: new Uint8Array([0x7b, 0x22, 0xff, 0x22, 0x3a, 0x31, 0x7d]) }),
  await make("refused: clientDataJSON that is an array", "object", { clientDataText: () => '["webauthn.get"]' }),
];

const out = {
  about: "WebAuthn ES256 assertions signed with WebCrypto (Node " + process.version + ") by test/fixtures/relay/webauthn/make-fixtures.mjs. Only the public key is kept. expect is 'accepted' or a word the refusal reason must contain.",
  rpId: RP_ID,
  origin: ORIGIN,
  publicKey: b64u(publicKey),
  cases,
};
const here = dirname(fileURLToPath(import.meta.url));
writeFileSync(join(here, "assertions.json"), JSON.stringify(out, null, 2) + "\n");
console.log("wrote " + cases.length + " cases to assertions.json");
