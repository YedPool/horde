// A simulated founder's phone, for the relay's end-to-end suite (test/test-relay-phone-e2e.ps1): a
// passkey and a phone identity key made with WebCrypto - the SubtleCrypto API a PWA has. EVERY BYTE THE
// PHONE SENDS OR CHECKS IS BUILT BY relay/js/protocol.js, the module the PWA (surfaces/pwa/) runs too,
// from the specification in relay/Envelope.ps1, relay/Hpke.ps1, relay/Pairing.ps1 and relay/Trust.ps1;
// the passkey is the software authenticator beside this file (soft-passkey.mjs). This file is only the
// command line around them. Nothing here is PowerShell's: the machine side is checked against bytes it
// did not make itself.
//
//   node test/fixtures/relay/phone/phone.mjs <command> <state.json> <in.json> <out.json>
//
// The state file holds this phone's PRIVATE keys between commands, as JWK. It is the suite's own, made
// under its temporary folder and deleted with it; nothing private is ever committed.
//
// COMMANDS (in.json and out.json are JSON objects):
//   register   in { offer, label }        -> out { response, sealed, pairMailbox, fingerprint, deviceKeyId }
//              Answers a pairing offer with a passkey registration, attestation "none" (WebAuthn L3
//              6.5): rpIdHash, flags UP|UV|AT, counter 0, a zero aaguid, the credential id and its COSE
//              key. The fingerprint is relay/Pairing.ps1's, so the suite can type it at the "machine".
//              sealed is the response sealed to the machine's agreement key, for the offer's pairing
//              mailbox (relay/Pairing.ps1, THE RESPONSE THROUGH THE RELAY).
//   send-pairing  in { relayRoot }        -> out { relayed, reason }
//              Puts the sealed response in the offer's pairing mailbox, on the local relay's folders
//              (relays/local), through the PWA's own relay client and folder transport.
//   phone-key  in { }                     -> out { envelope, key }
//              Makes the phone identity key (ECDH P-256) and announces it: an envelope on channel
//              trust, kind phone-key, signed with the passkey, whose body carries the key and a SECOND
//              passkey assertion over relay/Trust.ps1's vouch challenge for it.
//   open       in { envelope }            -> out { ok, reason, body, header }
//              Verifies the machine's ES256 signature against the signing key the offer pinned, and
//              opens the body with the phone identity key.
//   answer     in { number, wordingVersion, text, machine, snapshot, answerId? }  -> out { envelope, key, answerId }
//              The founder's answer: an envelope on channel decisions, kind answer, sealed to the
//              machine's agreement key and signed with a passkey assertion over SHA-256 of its signed
//              bytes. machine and snapshot name the snapshot it was made from: the key id of the
//              machine that sent it, and that envelope's replay key (open's key).
//   line       in { machine, session, text, messageId? }  -> out { envelope, key, messageId }
//              A founder's chat line to the Thrall: an envelope on channel chat, kind line, sealed to
//              the machine's agreement key and signed with a passkey assertion, its body bound to the
//              horde, the machine and the Thrall's session (channels/chat/Channel.ps1).
//   resign     in { envelope }            -> out { envelope }
//              The same signed content signed again (a new assertion): what a passkey may do, and what
//              the journal must still see as one envelope.
const [, , cmd, statePath, inPath, outPath] = process.argv;
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import * as P from "../../../../relay/js/protocol.js";
import { softAuthenticator } from "./soft-passkey.mjs";
import { createRelayClient } from "../../../../surfaces/pwa/page/relay-client.js";
import { folderTransport } from "../../../../surfaces/pwa/test/folder-relay.mjs";

const s = globalThis.crypto.subtle;

function authOf(st) { return softAuthenticator({ origin: st.origin, prf: false, state: st.auth }); }
function passkey(st) {
  // relay/js/protocol.js's passkey: a function of the challenge, here the software authenticator's get().
  return async (challenge) => { const a = authOf(st); const r = await a.get({ rpId: st.rpId, credentialId: P.unb64u(st.credentialId), challenge }); st.auth = a.toJSON(); return r; };
}
function nextSeq(st, channel) { st.seq = st.seq || {}; st.seq[channel] = (st.seq[channel] || 0) + 1; return st.seq[channel]; }
async function seal(st, kind, channel, body) {
  return P.sealEnvelope({ kind, channel, from: st.deviceKeyId, seq: nextSeq(st, channel), ts: Date.now(), recipientPublic: P.unb64u(st.offer.agreePublic), body });
}

async function register(st, input) {
  const read = await P.readOffer(input.offer);
  if (!read.ok) throw new Error(read.reason);
  const offer = read.value;
  const origin = offer.origins[0];
  const a = softAuthenticator({ origin, prf: false });
  const challenge = await P.pairingChallenge(offer.text);
  const made = await a.create({ rpId: offer.rpId, challenge });
  const cred = P.credentialFromAttestation(made.attestationObject);
  if (!cred.ok) throw new Error(cred.reason);
  const response = P.pairingResponseText({ offer: offer.offer, code: offer.code, rawId: made.rawId, clientDataJSON: made.clientDataJSON, attestationObject: made.attestationObject, label: input.label, prf: false });
  const fingerprint = await P.pairingFingerprint({ challenge, publicPoint: cred.value.publicPoint, credentialId: cred.value.credentialId, rpId: offer.rpId });
  st.auth = a.toJSON();
  st.credentialId = P.b64u(made.rawId);
  st.devicePublic = P.b64u(cred.value.publicPoint);
  st.deviceKeyId = await P.keyId(cred.value.publicPoint);
  st.rpId = offer.rpId; st.origin = origin; st.offerText = offer.text;
  st.offer = { horde: offer.horde, machine: offer.machine, signPublic: offer.signPublic, agreePublic: offer.agreePublic };
  st.sealed = await P.sealPairingResponse(offer, response);
  st.pairMailbox = offer.pairMailbox;
  st.pairingKey = P.pairingKey(offer.offer);
  return { response, sealed: st.sealed, pairMailbox: st.pairMailbox, fingerprint, deviceKeyId: st.deviceKeyId };
}

async function sendPairing(st, input) {
  const put = await createRelayClient(folderTransport(input.relayRoot)).put(st.pairMailbox, st.pairingKey, st.sealed);
  return { relayed: put.state === "known", reason: put.reason || "" };
}

async function phoneKey(st) {
  const kp = await s.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]);
  const pub = new Uint8Array(await s.exportKey("raw", kp.publicKey));
  st.phoneKey = await s.exportKey("jwk", kp.privateKey);
  st.phonePublic = P.b64u(pub);
  const vouch = await passkey(st)(await P.vouchChallenge(st.offer.horde, pub));
  const parts = await seal(st, "phone-key", "trust", P.phoneKeyBody(pub, vouch));
  return { envelope: await P.signEnvelope(parts, passkey(st)), key: P.replayKey(parts.header), agreeKeyId: await P.keyId(pub) };
}

async function open(st, input) {
  const priv = await s.importKey("jwk", st.phoneKey, { name: "ECDH", namedCurve: "P-256" }, false, ["deriveBits"]);
  const r = await P.openEnvelope(input.envelope, { keyId: st.offer.machine, signPublic: P.unb64u(st.offer.signPublic) }, { privateKey: priv, publicPoint: P.unb64u(st.phonePublic) });
  if (!r.ok) return { ok: false, reason: r.reason };
  return { ok: true, reason: "", header: r.value.header, key: r.value.key, body: JSON.parse(P.fromUtf8(r.value.body)) };
}

async function answer(st, input) {
  const answerId = input.answerId || P.hex(P.randomBytes(16));
  const body = P.answerBody({ answerId, machine: input.machine, snapshot: input.snapshot, number: input.number, wordingVersion: input.wordingVersion, text: input.text });
  const parts = await seal(st, "answer", "decisions", body);
  return { envelope: await P.signEnvelope(parts, passkey(st)), key: P.replayKey(parts.header), answerId };
}

async function line(st, input) {
  const messageId = input.messageId || P.hex(P.randomBytes(16));
  const body = P.lineBody({ messageId, horde: st.offer.horde, machine: input.machine, session: input.session, text: input.text });
  const parts = await seal(st, "line", "chat", body);
  return { envelope: await P.signEnvelope(parts, passkey(st)), key: P.replayKey(parts.header), messageId };
}

async function resign(st, input) {
  return { envelope: await P.signEnvelope(P.envelopeParts(input.envelope), passkey(st)) };
}

const st = existsSync(statePath) ? JSON.parse(readFileSync(statePath, "utf8")) : {};
const input = existsSync(inPath) ? JSON.parse(readFileSync(inPath, "utf8")) : {};
const commands = { register, "send-pairing": sendPairing, "phone-key": phoneKey, open, answer, line, resign };
if (!commands[cmd]) { console.error("no such command: " + cmd); process.exit(2); }
const out = await commands[cmd](st, input);
writeFileSync(statePath, JSON.stringify(st));
writeFileSync(outPath, JSON.stringify(out));
