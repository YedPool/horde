// surfaces/pwa/page/phone-core.js - the founder's phone, as logic: pair with a machine, keep the
// phone identity key wrapped, announce it, read the newest snapshot of a horde's open questions, and
// answer them with a passkey signature. No DOM and no browser API of its own: everything outside is
// handed in, so the same code runs in the PWA and under Node in the suites
// (surfaces/pwa/test/test-pwa-phone-e2e.ps1 runs it against a real `horde relay run`).
//
//   const phone = createPhone({ store, authenticator, relay, origin, now });
//     store          async key-value: get(key), put(key, value), delete(key), list(prefix),
//                    update(key, fn) - fn(old) -> new, atomically (store.js: IndexedDB)
//     authenticator  create({ rpId, rpName, userId, userName, challenge, prfInput })
//                      -> { rawId, clientDataJSON, attestationObject, prfEnabled, prfFirst }
//                    get({ rpId, credentialId, challenge, prfInput })
//                      -> { authenticatorData, clientDataJSON, signature (DER), prfFirst }
//                    (webauthn.js: navigator's credentials; the suites: a software passkey)
//     relay          a relay client (relay-client.js) over the deployment's transport
//     origin         where this page is served (location.origin): the offer must name it
//
// ONE HORDE, ONE ENTRY. A horde is one Thrall's fleet; the app holds several (work, personal). Each
// entry is one pairing with one machine of a horde: its own passkey credential, its own phone identity
// key and its own wraps, so one horde's trust never leans on another's. Two machines of one horde are
// two entries reading the same phone mailbox, each opening only its own machine's envelopes.
//
// WHAT IS STORED, AND WHAT NEVER IS. An entry holds public keys, ids, counters, the fingerprint and the
// WRAPPED phone key (keywrap.js) - nothing that reads a snapshot without the founder. Nothing
// decrypted is ever stored: the opened snapshot, the unwrapped key and the pages live in this object's
// memory for the session and are gone when the page closes or the founder locks (design Q7; the
// service worker caches the shell only, sw.js).
//
// A SESSION is what an unlock opens: the phone key in memory, and its MODE - "passkey" (the key is held
// under the passkey's PRF: it may answer), "recovery" (opened by the printed code) or "read-only" (a
// passkey that gives no PRF). Only a passkey session answers; answer() refuses the others in words
// before any passkey is asked. The real guarantee for the recovery code is the machine's (it verifies
// every answer against the pinned passkey); this keeps the screen honest.
//
// A PASSKEY WITHOUT PRF MAKES ITS HORDE READ ONLY (founder decision 2026-10-10: highest security wins).
// With no PRF there is nothing to wrap the phone key under but the browser itself, so no such wrap is
// made: the key is kept under the recovery code only, the horde can be read (right after pairing, and
// by the recovery code after that), and it is never answered from this phone. The announcement still
// goes out - it is what lets the machine seal snapshots to the phone at all. Should the passkey give a
// PRF output later (a provider that only evaluates it on get), the PRF wrap is made then and the horde
// answers from that moment.
//
// FRESHNESS. The relay may replay an old snapshot. The phone keeps the highest envelope seq of a
// snapshot it has shown (lastSnapshotSeq, a number, stored) and never shows an older one: a stale
// snapshot is reported as an anomaly, not drawn.
//
// THE SEQUENCE OF WHAT THE PHONE SENDS is per channel, counted in the store with update() so two tabs
// cannot spend one seq (the machine's journal refuses a seq at or below the last, relay/Journal.ps1).
import * as P from "../relay/protocol.js";
import { newPhoneKey, wipe, prfInput, newRecoveryCode, wrapWithPrf, wrapWithRecovery, unwrap } from "./keywrap.js";

const ENTRY = "horde/";
const NO_PRF = "Read only: this passkey gives no PRF, so this phone has nothing to keep this horde's key under, and a horde whose key the passkey does not hold is never answered from this phone. It can still be read: unlock with the recovery code. Answer at the machine, or pair again with a passkey that has PRF.";

function originHost(origin) { const m = /^[a-z]+:\/\/([^:/]+)(:[0-9]+)?$/.exec(origin || ""); return m ? m[1] : ""; }

export function createPhone({ store, authenticator, relay, origin, now = () => Date.now() }) {
  const sessions = new Map();
  const fail = (reason, code = "refused") => { const e = new Error(reason); e.code = code; return e; };

  async function entryOf(id) {
    const e = await store.get(ENTRY + id);
    if (!e) throw fail("there is no such horde on this phone");
    return e;
  }
  async function nextSeq(id, channel) {
    let seq = 0;
    await store.update(ENTRY + id, (e) => {
      if (!e) throw fail("there is no such horde on this phone");
      const counts = { ...(e.seq || {}) };
      counts[channel] = (counts[channel] || 0) + 1;
      seq = counts[channel];
      return { ...e, seq: counts };
    });
    return seq;
  }
  function assertWith(e, prf = false) {
    // relay/js/protocol.js's passkey: user verification required by the authenticator adapter.
    return async (challenge) => authenticator.get({ rpId: e.rpId, credentialId: P.unb64u(e.credentialId), challenge, prfInput: prf ? prfInput(e.horde, e.machine) : null });
  }
  async function sealAndSign(e, kind, channel, body, assert) {
    const parts = await P.sealEnvelope({ kind, channel, from: e.deviceKeyId, seq: await nextSeq(e.id, channel), ts: now(), recipientPublic: P.unb64u(e.machineAgreePublic), body });
    return { text: await P.signEnvelope(parts, assert), key: P.replayKey(parts.header) };
  }

  // The PRF wrap from what a passkey get() just gave, while the session still holds the key's bytes
  // (right after pairing, or after a recovery unlock); then the bytes are wiped and the session may
  // answer. With no PRF output nothing is wrapped and nothing changes: the horde stays read only.
  async function keepPasskeyWrap(e, s, prfFirst) {
    if (!s || !s.pkcs8 || !prfFirst) return e;
    const next = { ...e, wraps: { ...e.wraps, prf: await wrapWithPrf(s.pkcs8, prfFirst, e.horde, e.phoneKeyId) } };
    await store.put(ENTRY + e.id, next);
    wipe(s.pkcs8);
    s.pkcs8 = null;
    s.mode = "passkey";
    return next;
  }

  function summary(e) {
    const s = sessions.get(e.id);
    return {
      id: e.id, horde: e.horde, machine: e.machine, label: e.label, fingerprint: e.fingerprint, prf: e.prfEnabled,
      announced: !!e.announced, unlocked: !!s, mode: s ? s.mode : "", wraps: Object.keys(e.wraps || {}).sort()
    };
  }

  return {
    async hordes() { return (await store.list(ENTRY)).map(summary).sort((a, b) => (a.horde + a.machine).localeCompare(b.horde + b.machine)); },

    // Answer a pairing offer: make the passkey (the founder's finger), the phone identity key and its
    // recovery wrap. { id, fingerprint, response, recoveryCode, prf }. The recovery code is shown ONCE,
    // to be written down; it is not kept anywhere.
    async pair({ offerText, label }) {
      const read = await P.readOffer(offerText, now());
      if (!read.ok) throw fail(read.reason);
      const o = read.value;
      if (o.origins.indexOf(origin) < 0) throw fail("this offer is for " + o.origins.join(", ") + ", not this app at " + origin + ": open the app the offer names");
      const host = originHost(origin);
      if (host !== o.rpId && !host.endsWith("." + o.rpId)) throw fail("this app at " + origin + " cannot make passkeys for " + o.rpId);
      if (!P.validLabel(label)) throw fail("name this phone in 1 to 64 plain characters, with no quote or backslash");
      for (const e of await store.list(ENTRY)) { if (e.horde === o.horde && e.machine === o.machine) throw fail("this phone is already paired with that machine of " + o.horde + "; forget that pairing first"); }
      const challenge = await P.pairingChallenge(o.text);
      const pk = await newPhoneKey();
      let made;
      try {
        made = await authenticator.create({ rpId: o.rpId, rpName: "Horde " + o.horde, userId: P.randomBytes(16), userName: label + " - " + o.horde, challenge, prfInput: prfInput(o.horde, o.machine) });
      } catch (x) { wipe(pk.pkcs8); throw fail("no passkey was made: " + (x && x.message ? x.message : x)); }
      const cred = P.credentialFromAttestation(made.attestationObject);
      if (!cred.ok) { wipe(pk.pkcs8); throw fail(cred.reason); }
      if (!P.equalBytes(cred.value.credentialId, made.rawId)) { wipe(pk.pkcs8); throw fail("the passkey's id and its attested credential differ"); }
      const fingerprint = await P.pairingFingerprint({ challenge, publicPoint: cred.value.publicPoint, credentialId: cred.value.credentialId, rpId: o.rpId });
      const response = P.pairingResponseText({ offer: o.offer, code: o.code, rawId: made.rawId, clientDataJSON: made.clientDataJSON, attestationObject: made.attestationObject, label, prf: made.prfEnabled === true });
      const phoneKeyId = await P.keyId(pk.publicPoint);
      const recoveryCode = newRecoveryCode();
      const id = P.hex(P.randomBytes(8));
      let e = {
        v: 1, id, horde: o.horde, machine: o.machine, machineSignPublic: o.signPublic, machineAgreePublic: o.agreePublic, machineMailbox: o.mailbox,
        rpId: o.rpId, origin, credentialId: P.b64u(made.rawId), deviceKeyId: await P.keyId(cred.value.publicPoint), devicePublic: P.b64u(cred.value.publicPoint),
        label, fingerprint, prfEnabled: made.prfEnabled === true, phonePublic: P.b64u(pk.publicPoint), phoneKeyId,
        wraps: { recovery: await wrapWithRecovery(pk.pkcs8, recoveryCode, o.horde, phoneKeyId) },
        seq: {}, announced: null, readFrom: 0, lastSnapshotSeq: -1, pairedAt: now()
      };
      await store.put(ENTRY + id, e);
      const s = { privateKey: pk.privateKey, publicPoint: pk.publicPoint, mode: "read-only", pkcs8: pk.pkcs8, pages: [], cursor: 0, view: null };
      sessions.set(id, s);
      if (made.prfFirst) e = await keepPasskeyWrap(e, s, made.prfFirst);
      return { id, fingerprint, response, recoveryCode, prf: e.prfEnabled };
    },

    // Announce this horde's phone identity key to the machine, vouched for by the passkey (two
    // assertions: the vouch, which also asks for PRF, and the envelope's signature). Done once the
    // founder has confirmed the fingerprint at the machine; done again if no snapshot ever comes.
    async announce(id) {
      let e = await entryOf(id);
      const s = sessions.get(id);
      if (s && s.mode === "recovery") throw fail("unlocked with the recovery code, this phone reads only: unlock with the passkey to announce it");
      const phonePublic = P.unb64u(e.phonePublic);
      const vouch = await assertWith(e, true)(await P.vouchChallenge(e.horde, phonePublic));
      e = await keepPasskeyWrap(e, s, vouch.prfFirst);
      const env = await sealAndSign(e, "phone-key", "trust", P.phoneKeyBody(phonePublic, vouch), assertWith(e));
      const put = await relay.put(e.machineMailbox, env.key, env.text);
      if (put.state !== "known") throw fail("the relay did not take the announcement: " + put.reason);
      await store.update(ENTRY + id, (x) => ({ ...x, announced: { key: env.key, at: now() } }));
      return { key: env.key, agreeKeyId: e.phoneKeyId };
    },

    // Unlock with the passkey: its PRF output unwraps the phone key. A passkey that gives none unlocks
    // nothing (the horde is read only, by the recovery code).
    async unlock(id) {
      let e = await entryOf(id);
      const got = await authenticator.get({ rpId: e.rpId, credentialId: P.unb64u(e.credentialId), challenge: P.randomBytes(32), prfInput: prfInput(e.horde, e.machine) });
      if (!got.prfFirst) throw fail(NO_PRF);
      const s = sessions.get(id);
      if (s && s.pkcs8) { e = await keepPasskeyWrap(e, s, got.prfFirst); return summary(e); }
      if (!e.wraps.prf) throw fail("this horde's key is not wrapped under this passkey's PRF yet: unlock with the recovery code once, then with the passkey");
      const opened = await unwrap(e.wraps.prf, got.prfFirst, e.horde, e.phoneKeyId, P.unb64u(e.phonePublic));
      if (!opened.ok) throw fail(opened.reason + ": unlock with the recovery code");
      sessions.set(id, { privateKey: opened.value.privateKey, publicPoint: opened.value.publicPoint, mode: "passkey", pkcs8: null, pages: [], cursor: e.readFrom, view: null });
      return summary(e);
    },

    // Unlock with the printed recovery code: READ ONLY. The key's bytes stay in the session so that the
    // next passkey unlock can wrap it again (a lost or changed PRF wrap is mended by the passkey, never
    // by the code).
    async recover(id, code) {
      const e = await entryOf(id);
      const opened = await unwrap(e.wraps.recovery, code, e.horde, e.phoneKeyId, P.unb64u(e.phonePublic), { keepBytes: true });
      if (!opened.ok) throw fail(opened.reason);
      sessions.set(id, { privateKey: opened.value.privateKey, publicPoint: opened.value.publicPoint, mode: "recovery", pkcs8: opened.value.pkcs8, pages: [], cursor: e.readFrom, view: null });
      return summary(e);
    },

    lock(id) { const s = sessions.get(id); if (s) { wipe(s.pkcs8); sessions.delete(id); } },

    async forget(id) { this.lock(id); await store.delete(ENTRY + id); },

    // Read the horde's phone mailbox and return the newest complete snapshot this phone can open:
    // { snapshot, seq, questions, pageKeyByNumber, withheld, counts, anomalies, stale }. waitMs > 0
    // long-polls the relay first (a watch). Needs an unlocked session.
    async refresh(id, { waitMs = 0 } = {}) {
      const e = await entryOf(id);
      const s = sessions.get(id);
      if (!s) throw fail("This horde is locked.", "locked");
      const mailbox = e.horde + "/phone";
      const anomalies = [];
      let first = true;
      for (let round = 0; round < 64; round++) {
        const r = (first && waitMs > 0) ? await relay.watch(mailbox, s.cursor, 256, waitMs) : await relay.get(mailbox, s.cursor, 256);
        first = false;
        if (r.state !== "known") { anomalies.push("the relay could not be read: " + r.reason); break; }
        anomalies.push(...r.value.anomalies);
        for (const item of r.value.items) {
          const o = await P.openEnvelope(item.text, { keyId: e.machine, signPublic: P.unb64u(e.machineSignPublic) }, { privateKey: s.privateKey, publicPoint: s.publicPoint });
          // Another machine's envelope, or one sealed to another phone key, is not an anomaly: the
          // mailbox is the horde's. A forged or broken one from "this" machine is.
          if (!o.ok) { if (o.reason !== "not from the machine this phone paired with" && o.reason !== "not sealed to this phone") anomalies.push("item " + item.seq + ": " + o.reason); continue; }
          if (o.value.header.channel !== "decisions" || o.value.header.kind !== "snapshot") continue;
          const page = P.readSnapshotPage(o.value.body, e.horde, e.machine);
          if (!page.ok) { anomalies.push("item " + item.seq + ": " + page.reason); continue; }
          s.pages.push({ key: o.value.key, seq: o.value.header.seq, relaySeq: item.seq, page: page.value });
        }
        s.cursor = r.value.next;
        if (r.value.items.length < 256) break;
      }
      const best = P.newestSnapshot(s.pages);
      let stale = false;
      if (best && best.seq < e.lastSnapshotSeq) { stale = true; anomalies.push("the relay served a snapshot older than one already shown; it is not drawn"); }
      else if (best) {
        s.view = best;
        s.pages = s.pages.filter((p) => p.relaySeq >= best.firstSeq);
        if (best.seq !== e.lastSnapshotSeq || best.firstSeq - 1 !== e.readFrom) await store.update(ENTRY + id, (x) => ({ ...x, lastSnapshotSeq: best.seq, readFrom: Math.max(0, best.firstSeq - 1) }));
      }
      const v = s.view;
      const pageKeyByNumber = {};
      if (v) for (const q of v.questions) pageKeyByNumber[q.question.number] = q.pageKey;
      return {
        snapshot: v ? v.snapshot : "", seq: v ? v.seq : -1, questions: v ? v.questions.map((q) => q.question) : [], pageKeyByNumber,
        withheld: v ? v.withheld : [], counts: v ? v.counts : null, unreadable: v ? v.unreadable : 0, notUnderstood: v ? v.notUnderstood : 0,
        anomalies, stale, mode: s.mode
      };
    },

    // The founder's answer to one question of the snapshot on screen, signed with the passkey (user
    // verification) and put into the machine's mailbox. answerId is the page's id for these words: the
    // same words sent again carry it, and the machine stores them once. { key, seq }.
    async answer(id, { number, wordingVersion, text, answerId }) {
      const e = await entryOf(id);
      const s = sessions.get(id);
      if (!s) throw fail("This horde is locked.", "locked");
      if (s.mode === "read-only") throw fail(NO_PRF);
      if (s.mode !== "passkey") throw fail("Read only: this horde was unlocked with the recovery code, which cannot sign. Unlock with the passkey to answer.");
      const v = s.view;
      const q = v && v.questions.find((x) => x.question.number === number);
      if (!q) throw fail("question " + number + " is not in the snapshot this phone holds");
      const body = P.answerBody({ answerId, machine: e.machine, snapshot: q.pageKey, number, wordingVersion, text });
      const env = await sealAndSign(e, "answer", "decisions", body, assertWith(e));
      const put = await relay.put(e.machineMailbox, env.key, env.text);
      if (put.state !== "known") throw fail("not sent: the relay did not take it (" + put.reason + "). Press Enter to try again; the same words are never saved twice.");
      return { key: env.key, seq: put.value.seq };
    }
  };
}
