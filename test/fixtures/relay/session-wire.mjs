// The phone's half of test/test-relay-session-wire.ps1: every session byte relay/js/protocol.js makes
// for fixed inputs, and one live unlock - a real non-extractable WebCrypto session key and the software
// passkey's one assertion over the vouch - so the suite can put what JavaScript made through
// PowerShell's own reader and verifier. Nothing here is PowerShell's.
//
//   node session-wire.mjs <in.json> <out.json>
//
// in   { vectors: { sessionPublicKey (hex), deviceKeyId, phoneKeyId, horde, machine, notBefore, notAfter,
//        seq, ht, rt, ct, value (hex, 64 bytes), authenticatorData (hex), clientDataJSON (hex),
//        signature (hex) }, live: { recipientPublic (hex), rpId, origin, horde, machine, phoneKeyId, now } }
// out  { vouchText, challenge, signed, sigBare, sigWithVouch, openBody, throws: {..}, live: {..} }
import { readFileSync, writeFileSync } from "node:fs";
import * as P from "../../../relay/js/protocol.js";
import { softAuthenticator } from "./phone/soft-passkey.mjs";

const [, , inPath, outPath] = process.argv;
const input = JSON.parse(readFileSync(inPath, "utf8"));
const v = input.vectors;
const out = {};

const vouchText = await P.sessionVouchText({ sessionPublicKey: P.unhex(v.sessionPublicKey), deviceKeyId: v.deviceKeyId, phoneKeyId: v.phoneKeyId,
  horde: v.horde, machine: v.machine, notBefore: v.notBefore, notAfter: v.notAfter, seq: v.seq });
out.vouchText = vouchText;
out.challenge = P.hex(await P.sessionVouchChallenge(vouchText));
const vouchId = await P.keyId(P.unhex(v.sessionPublicKey));
out.vouchId = vouchId;
out.signed = P.hex(P.sessionSignedBytes(vouchId, v.ht, v.rt, v.ct));
out.sigBare = P.sessionSigText({ vouchId, value: P.unhex(v.value) });
out.sigWithVouch = P.sessionSigText({ vouchId, value: P.unhex(v.value), vouch: { text: vouchText, authenticatorData: P.unhex(v.authenticatorData), clientDataJSON: P.unhex(v.clientDataJSON), signature: P.unhex(v.signature) } });
out.openBody = new TextDecoder().decode(P.sessionOpenBody(vouchId));
out.refusals = P.SESSION_REFUSALS;
out.maxMs = P.SESSION_MAX_MS;

// The writer refuses what the reader would: each must throw.
const base = { sessionPublicKey: P.unhex(v.sessionPublicKey), deviceKeyId: v.deviceKeyId, phoneKeyId: v.phoneKeyId, horde: v.horde, machine: v.machine, notBefore: v.notBefore, notAfter: v.notAfter, seq: v.seq };
const throwsOf = async (over) => { try { await P.sessionVouchText({ ...base, ...over }); return ""; } catch (e) { return e.message; } };
out.throws = {
  overCap: await throwsOf({ notAfter: v.notBefore + P.SESSION_MAX_MS + 1 }),
  atCap: await throwsOf({ notAfter: v.notBefore + P.SESSION_MAX_MS }),
  backwards: await throwsOf({ notAfter: v.notBefore }),
  badHorde: await throwsOf({ horde: "Bad Horde" }),
  badKeyId: await throwsOf({ deviceKeyId: "XYZ" })
};

// The live unlock: one passkey, one session key, two envelopes (the first with the vouch).
const L = input.live;
const auth = softAuthenticator({ origin: L.origin, prf: false });
const made = await auth.create({ rpId: L.rpId, challenge: P.randomBytes(32) });
const deviceKeyId = await P.keyId(made.publicPoint);
let prompts = 0;
const assert = async (challenge) => { prompts++; return auth.get({ rpId: L.rpId, credentialId: made.rawId, challenge }); };
const session = await P.openSession({ assert, deviceKeyId, phoneKeyId: L.phoneKeyId, horde: L.horde, machine: L.machine, now: L.now, seq: 1 });
let exportRefused = "";
try { await globalThis.crypto.subtle.exportKey("pkcs8", session.privateKey); } catch (e) { exportRefused = e.name || "refused"; }
const recipientPublic = P.unhex(L.recipientPublic);
const envelopes = [];
for (let i = 1; i <= 3; i++) {
  const parts = await P.sealEnvelope({ kind: "answer", channel: "decisions", from: deviceKeyId, seq: i, ts: L.now + i, recipientPublic, body: P.utf8("answer " + i) });
  envelopes.push(await P.signSessionEnvelope(parts, session, i === 1));
}
out.live = { devicePublic: P.hex(made.publicPoint), deviceKeyId, vouchId: session.vouchId, vouchText: session.vouch.text, notBefore: session.notBefore,
  notAfter: session.notAfter, envelopes, prompts, exportRefused, extractable: session.privateKey.extractable };
writeFileSync(outPath, JSON.stringify(out));
