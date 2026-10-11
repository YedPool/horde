// Makes test/fixtures/relay/registration/registrations.json: WebAuthn registration responses
// (attestation "none") and the COSE keys inside them, built with WebCrypto - the SubtleCrypto API a PWA
// has - and a CBOR encoder written here, so the PowerShell reader (relay/Cbor.ps1, relay/Cose.ps1,
// relay/Registration.ps1) is checked against bytes it did not make itself.
//
// Run from the repository root:  node test/fixtures/relay/registration/make-fixtures.mjs
// Each run makes fresh key pairs and keeps only their public halves: no private key is ever written, so
// the committed file cannot be used to sign anything new. The cases are the same every run; the bytes
// differ (new keys, new credential ids, randomised ECDSA).
//
// WHAT IS IN A REGISTRATION (WebAuthn Level 3, 6.1 and 6.5): attestationObject is a CBOR map
// {fmt, attStmt, authData}; with attestation "none", fmt is "none", attStmt is the empty map and
// NOTHING IS SIGNED. authData is rpIdHash (32) || flags (1) || signCount (4) || aaguid (16) ||
// credentialIdLength (2, big-endian) || credentialId || credentialPublicKey (a COSE_Key, CBOR) ||
// [extensions (CBOR map), when the ED flag is set]. A COSE EC2 key for ES256 is the map
// {1: 2 (kty EC2), 3: -7 (alg ES256), -1: 1 (crv P-256), -2: x (32 bytes), -3: y (32 bytes)}.
//
// clientDataJSON is not here: with attestation "none" it is bound to nothing but its own hash, so the
// suites write it themselves around each challenge they need. Each case's credential also signs one
// assertion over a fixed challenge, which a suite verifies under the key it imported: the proof that the
// import produced the right key, not merely a valid one.
//
// Every case is built properly unless its name says what is wrong, so each refusal is reached for its
// own reason and no other.
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const s = globalThis.crypto.subtle;
const enc = new TextEncoder();
const b64u = (b) => Buffer.from(b).toString("base64url");
const cat = (...a) => { const n = a.reduce((x, y) => x + y.length, 0); const o = new Uint8Array(n); let i = 0; for (const p of a) { o.set(p, i); i += p.length; } return o; };
const sha256 = async (b) => new Uint8Array(await s.digest("SHA-256", b));
const rnd = (n) => globalThis.crypto.getRandomValues(new Uint8Array(n));
function derInt(b) { let i = 0; while (i < b.length - 1 && b[i] === 0) i++; let v = b.slice(i); if (v[0] & 0x80) v = cat(new Uint8Array([0]), v); return cat(new Uint8Array([2, v.length]), v); }
function toDer(sig) { const r = derInt(sig.slice(0, 32)), q = derInt(sig.slice(32)); return cat(new Uint8Array([0x30, r.length + q.length]), r, q); }

// --- a CBOR encoder (RFC 8949), definite lengths, shortest form unless a case asks otherwise ---
function head(major, n) {
  if (n < 24) return new Uint8Array([(major << 5) | n]);
  if (n < 0x100) return new Uint8Array([(major << 5) | 24, n]);
  if (n < 0x10000) return new Uint8Array([(major << 5) | 25, n >> 8, n & 255]);
  return new Uint8Array([(major << 5) | 26, (n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255]);
}
// A value: a number (integer), Uint8Array (bytes), string (text), boolean, null, {map: [[k, v], ...]}
// (a map in the order given), {array: [...]}, or {raw: Uint8Array} (bytes spliced in as they are).
function cbor(v) {
  if (v === null) return new Uint8Array([0xf6]);
  if (v === true) return new Uint8Array([0xf5]);
  if (v === false) return new Uint8Array([0xf4]);
  if (typeof v === "number") return v >= 0 ? head(0, v) : head(1, -1 - v);
  if (typeof v === "string") { const b = enc.encode(v); return cat(head(3, b.length), b); }
  if (v instanceof Uint8Array) return cat(head(2, v.length), v);
  if (v.raw) return v.raw;
  if (v.array) return cat(head(4, v.array.length), ...v.array.map(cbor));
  if (v.map) return cat(head(5, v.map.length), ...v.map.flatMap(([k, x]) => [cbor(k), cbor(x)]));
  throw new Error("cannot encode " + v);
}

const RP_ID = "relay.example.test";
const ORIGIN = "https://relay.example.test";
const UP = 0x01, UV = 0x04, BE = 0x08, BS = 0x10, AT = 0x40, ED = 0x80;
const AAGUID = new Uint8Array([0xea, 0x9b, 0x8d, 0x66, 0x4d, 0x01, 0x1d, 0x21, 0x3c, 0xe4, 0xb6, 0xb4, 0x8c, 0xb5, 0x75, 0xd4]);
const P = Buffer.from("ffffffff00000001000000000000000000000000ffffffffffffffffffffffff", "hex");
const ASSERT_CHALLENGE = new Uint8Array(32).fill(0x5a);

async function newKey() {
  const kp = await s.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const raw = new Uint8Array(await s.exportKey("raw", kp.publicKey));
  return { kp, raw, x: raw.slice(1, 33), y: raw.slice(33, 65) };
}
// The usual COSE key; o.entries replaces its entries, o.raw replaces its bytes.
function coseOf(k, o = {}) {
  if (o.coseRaw) return o.coseRaw(k);
  const entries = o.coseEntries ? o.coseEntries(k) : [[1, 2], [3, -7], [-1, 1], [-2, k.x], [-3, k.y]];
  return cbor({ map: entries });
}
async function assertionFor(k, rpIdHash) {
  const ad = cat(rpIdHash, new Uint8Array([UP | UV]), new Uint8Array([0, 0, 0, 1]));
  const cdj = enc.encode(JSON.stringify({ type: "webauthn.get", challenge: b64u(ASSERT_CHALLENGE), origin: ORIGIN, crossOrigin: false }));
  const p1363 = new Uint8Array(await s.sign({ name: "ECDSA", hash: "SHA-256" }, k.kp.privateKey, cat(ad, await sha256(cdj))));
  return { challenge: b64u(ASSERT_CHALLENGE), authenticatorData: b64u(ad), clientDataJSON: b64u(cdj), signature: b64u(toDer(p1363)) };
}

// One registration case: o says what differs from a valid one.
async function reg(name, expect, o = {}) {
  const k = await newKey();
  const rpIdHash = await sha256(enc.encode(o.rpId ?? RP_ID));
  const credId = o.credId ?? rnd(o.credIdLength ?? 32);
  const flags = o.flags ?? (UP | UV | AT | BE | BS);
  const count = o.count ?? 0;
  const lenBytes = o.credIdLenField ?? new Uint8Array([(credId.length >> 8) & 255, credId.length & 255]);
  let ad = cat(rpIdHash, new Uint8Array([flags]), new Uint8Array([(count >>> 24) & 255, (count >>> 16) & 255, (count >>> 8) & 255, count & 255]),
    o.aaguid ?? AAGUID, lenBytes, credId, coseOf(k, o), o.extra ?? new Uint8Array(0));
  if (o.authDataRaw) ad = o.authDataRaw(ad);
  const att = o.attRaw ? o.attRaw(ad) : cbor({ map: o.attEntries ? o.attEntries(ad) : [["fmt", o.fmt ?? "none"], ["attStmt", o.attStmt ?? { map: [] }], ["authData", ad]] });
  const out = { name, expect, rawId: b64u(o.rawId ?? credId), attestationObject: b64u(att) };
  if (expect === "accepted") {
    out.publicKey = b64u(k.raw);
    out.credentialId = b64u(credId);
    out.assertion = await assertionFor(k, rpIdHash);
  }
  return out;
}

async function makeAll() {
  return [
    await reg("valid: synced passkey (BE and BS), counter 0", "accepted"),
    await reg("valid: device-bound passkey, counter 5", "accepted", { flags: UP | UV | AT, count: 5 }),
    await reg("valid: PRF asked at create, hmac-secret in the extensions", "accepted", { flags: UP | UV | AT | ED, extra: cbor({ map: [["hmac-secret", true]] }) }),
    await reg("valid: a 16-byte credential id", "accepted", { credIdLength: 16 }),
    await reg("valid: COSE members in another order", "accepted", { coseEntries: (k) => [[-3, k.y], [-2, k.x], [-1, 1], [3, -7], [1, 2]] }),
    await reg("valid: attestationObject members in another order", "accepted", { attEntries: (ad) => [["authData", ad], ["fmt", "none"], ["attStmt", { map: [] }]] }),
    await reg("refused: packed attestation", "attestation format", { fmt: "packed", attStmt: { map: [["alg", -7], ["sig", new Uint8Array(70)]] } }),
    await reg("refused: none with a statement", "attStmt", { attStmt: { map: [["x5c", { array: [] }]] } }),
    await reg("refused: an extra attestationObject member", "attestationObject", { attEntries: (ad) => [["fmt", "none"], ["attStmt", { map: [] }], ["authData", ad], ["extra", 1]] }),
    await reg("refused: attestationObject member twice", "more than once", { attEntries: (ad) => [["fmt", "none"], ["fmt", "none"], ["attStmt", { map: [] }], ["authData", ad]] }),
    await reg("refused: bytes after the attestationObject", "after", { attRaw: (ad) => cat(cbor({ map: [["fmt", "none"], ["attStmt", { map: [] }], ["authData", ad]] }), new Uint8Array([0])) }),
    await reg("refused: an indefinite-length map", "indefinite", { attRaw: (ad) => cat(new Uint8Array([0xbf]), cbor("fmt"), cbor("none"), cbor("attStmt"), cbor({ map: [] }), cbor("authData"), cbor(ad), new Uint8Array([0xff])) }),
    await reg("refused: a length not in its shortest form", "shortest", { attRaw: (ad) => cat(new Uint8Array([0xa3]), new Uint8Array([0x78, 3]), enc.encode("fmt"), cbor("none"), cbor("attStmt"), cbor({ map: [] }), cbor("authData"), cbor(ad)) }),
    await reg("refused: a tagged value", "tag", { attRaw: (ad) => cat(new Uint8Array([0xa3]), cbor("fmt"), new Uint8Array([0xc0]), cbor("none"), cbor("attStmt"), cbor({ map: [] }), cbor("authData"), cbor(ad)) }),
    await reg("refused: authData that is text, not bytes", "authData", { attEntries: () => [["fmt", "none"], ["attStmt", { map: [] }], ["authData", "abc"]] }),
    await reg("refused: no attested credential data (AT clear)", "attested credential data", { flags: UP | UV | BE | BS }),
    await reg("refused: user not verified", "user verification", { flags: UP | AT }),
    await reg("refused: user not present", "user presence", { flags: UV | AT }),
    await reg("refused: backed up but not backup eligible", "backup", { flags: UP | UV | AT | BS }),
    await reg("refused: registered for another relying party", "rpIdHash", { rpId: "evil.example.test" }),
    await reg("refused: extension flag with no extensions", "no extensions follow", { flags: UP | UV | AT | ED }),
    await reg("refused: bytes after the key with no extension flag", "after the credential public key", { extra: new Uint8Array([0xa0]) }),
    await reg("refused: extensions that are not a map", "extensions", { flags: UP | UV | AT | ED, extra: cbor(1) }),
    await reg("refused: a credential id longer than 1023 bytes", "credential id", { credIdLength: 1024 }),
    await reg("refused: a credential id length past the end", "credential id", { credIdLenField: new Uint8Array([0x7f, 0xff]) }),
    await reg("refused: rawId is not the credential id", "rawId", { rawId: rnd(32) }),
    await reg("refused: an EdDSA (OKP) key", "EC2", { coseEntries: (k) => [[1, 1], [3, -8], [-1, 6], [-2, k.x]] }),
    await reg("refused: an RS256 key", "EC2", { coseEntries: (k) => [[1, 3], [3, -257], [-1, k.x], [-2, new Uint8Array([1, 0, 1])]] }),
    await reg("refused: an EC2 key for ES384", "ES256", { coseEntries: (k) => [[1, 2], [3, -35], [-1, 1], [-2, k.x], [-3, k.y]] }),
    await reg("refused: an EC2 key on P-384", "P-256", { coseEntries: (k) => [[1, 2], [3, -7], [-1, 2], [-2, k.x], [-3, k.y]] }),
    await reg("refused: a COSE label twice", "more than once", { coseEntries: (k) => [[1, 2], [3, -7], [3, -7], [-1, 1], [-2, k.x], [-3, k.y]] }),
    await reg("refused: a COSE key with a private part (d)", "member", { coseEntries: (k) => [[1, 2], [3, -7], [-1, 1], [-2, k.x], [-3, k.y], [-4, rnd(32)]] }),
    await reg("refused: x of 31 bytes", "32 bytes", { coseEntries: (k) => [[1, 2], [3, -7], [-1, 1], [-2, k.x.slice(1)], [-3, k.y]] }),
    await reg("refused: a point not on the curve", "not a point on P-256", { coseEntries: (k) => { const y = k.y.slice(); y[31] ^= 1; return [[1, 2], [3, -7], [-1, 1], [-2, k.x], [-3, y]]; } }),
    await reg("refused: compressed y (a boolean)", "y", { coseEntries: (k) => [[1, 2], [3, -7], [-1, 1], [-2, k.x], [-3, true]] }),
    await reg("refused: no alg member", "alg", { coseEntries: (k) => [[1, 2], [-1, 1], [-2, k.x], [-3, k.y]] }),
  ];
}

// An x of p + 1: 32 bytes still, but not a field element. A reader that reduces it modulo p reads x = 1,
// another key than the bytes say, so it must be refused before any import.
async function fieldCase() {
  const k = await newKey();
  const xp = Uint8Array.from(Buffer.from((1n + BigInt("0x" + P.toString("hex"))).toString(16).padStart(64, "0"), "hex"));
  return await reg("refused: x not below the field prime", "field", { coseEntries: () => [[1, 2], [3, -7], [-1, 1], [-2, xp], [-3, k.y]] });
}

// RANDOM BYTES CAN SPELL A PORT'S NAME. test/test-host-names.ps1 fails any file outside a port's folder
// that holds one of that port's names as a case-insensitive substring, and base64url of random bytes
// spelled one (measured 2026-10-09: the first run spelled a terminal host's name). So the whole
// file is made again, with new keys, until it holds no name from any port's names.txt.
const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..", "..", "..", "..");
const portNames = [];
for (const family of ["hosts", "agents", "transports", "messengers", "surfaces", "relays"]) {
  const dir = join(repo, family);
  if (!existsSync(dir)) continue;
  for (const port of readdirSync(dir, { withFileTypes: true })) {
    const f = join(dir, port.name, "names.txt");
    if (!port.isDirectory() || !existsSync(f)) continue;
    for (const line of readFileSync(f, "utf8").split(/\r?\n/)) {
      if (line.startsWith("#") || !line.includes("|")) continue;
      const name = line.split("|")[0].trim().toLowerCase();
      if (name) portNames.push(name);
    }
  }
}
if (portNames.length < 10) throw new Error("CONTROL: the ports' names were not found (" + portNames.length + ")");

let text = "", count = 0, tries = 0;
for (;;) {
  tries++;
  const registrations = [...(await makeAll()), await fieldCase()];
  count = registrations.length;
  const out = {
    about: "WebAuthn registrations (attestation none) built with WebCrypto and a CBOR encoder (Node " + process.version + ") by test/fixtures/relay/registration/make-fixtures.mjs. Only public keys are kept. expect is 'accepted' or a word the refusal reason must contain. clientDataJSON is written by the suites.",
    rpId: RP_ID,
    origin: ORIGIN,
    registrations,
  };
  text = JSON.stringify(out, null, 2) + "\n";
  if (!portNames.some((n) => text.toLowerCase().includes(n))) break;
  if (tries >= 50) throw new Error("50 tries, and every one spelled a port's name");
}
writeFileSync(join(here, "registrations.json"), text);
console.log("wrote " + count + " registrations to registrations.json (" + tries + " tries; " + portNames.length + " port names avoided)");
