// surfaces/pwa/page/webauthn.js - the phone's passkey: phone-core.js's authenticator, made of the
// browser's WebAuthn (navigator.credentials), and nothing else.
//
// WHAT IS ASKED, and why (relay/Registration.ps1 and relay/WebAuthn.ps1 check the other side):
//   - ES256 only (alg -7): the machine imports nothing else, and P-256 is what every passkey provider
//     makes (design Q6).
//   - user verification REQUIRED, on create and on every get: the machine refuses an answer without
//     the UV flag, and an unlock without it would be a key handed to whoever holds the phone.
//   - attestation "none": the machine asks for none, and refuses any other format by name.
//   - hints "client-device": the founder's own phone's provider (Google Password Manager on Android
//     first), not a QR code to another device. A browser that does not know hints ignores them.
//   - the PRF extension (WebAuthn L3 10.1.4) with the horde's input, on create and on the gets that
//     unlock: keywrap.js turns its output into the key that unwraps the phone identity key. A
//     provider that evaluates PRF at creation hands the output at once; one that only reports
//     prf.enabled hands it on the first get. A browser that refuses the extension on create (an older
//     one) is asked again without it; a passkey that never gives PRF makes its horde read only
//     (phone-core.js).
//   - allowCredentials names the horde's one credential: each horde is its own pairing.
// Timeouts are two minutes: long enough for a fingerprint that fails twice, short enough that a prompt
// left open does not hang the app.
const TIMEOUT_MS = 120000;

function bytes(buffer) { return buffer ? new Uint8Array(buffer) : null; }
function prfFirstOf(credential) {
  const ext = credential.getClientExtensionResults ? credential.getClientExtensionResults() : {};
  const prf = ext && ext.prf;
  return { enabled: !!(prf && prf.enabled === true), first: prf && prf.results && prf.results.first ? bytes(prf.results.first) : null };
}

export function browserAuthenticator(credentials = globalThis.navigator && globalThis.navigator.credentials) {
  if (!credentials || typeof globalThis.PublicKeyCredential === "undefined") throw new Error("this browser has no passkeys (WebAuthn), so it cannot be the founder's phone");
  return {
    async create({ rpId, rpName, userId, userName, challenge, prfInput }) {
      const base = {
        rp: { id: rpId, name: rpName },
        user: { id: userId, name: userName, displayName: userName },
        challenge,
        pubKeyCredParams: [{ type: "public-key", alg: -7 }],
        authenticatorSelection: { residentKey: "preferred", userVerification: "required" },
        attestation: "none",
        hints: ["client-device"],
        timeout: TIMEOUT_MS
      };
      let credential;
      try { credential = await credentials.create({ publicKey: { ...base, extensions: { prf: prfInput ? { eval: { first: prfInput } } : {} } } }); }
      catch (e) {
        if (!e || (e.name !== "NotSupportedError" && e.name !== "TypeError")) throw e;
        credential = await credentials.create({ publicKey: { ...base, extensions: { prf: {} } } });
      }
      if (!credential) throw new Error("the browser made no passkey");
      const prf = prfFirstOf(credential);
      return {
        rawId: bytes(credential.rawId),
        clientDataJSON: bytes(credential.response.clientDataJSON),
        attestationObject: bytes(credential.response.attestationObject),
        prfEnabled: prf.enabled || prf.first !== null,
        prfFirst: prf.first
      };
    },
    async get({ rpId, credentialId, challenge, prfInput }) {
      const publicKey = {
        rpId, challenge, userVerification: "required", timeout: TIMEOUT_MS,
        allowCredentials: [{ type: "public-key", id: credentialId }]
      };
      if (prfInput) publicKey.extensions = { prf: { eval: { first: prfInput } } };
      const credential = await credentials.get({ publicKey });
      if (!credential) throw new Error("the passkey gave no answer");
      return {
        authenticatorData: bytes(credential.response.authenticatorData),
        clientDataJSON: bytes(credential.response.clientDataJSON),
        signature: bytes(credential.response.signature),
        prfFirst: prfFirstOf(credential).first
      };
    }
  };
}
