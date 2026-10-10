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
// snapshot is reported as an anomaly, not drawn. That number is the ONLY thing freshness rests on.
// THE RELAY'S OWN NUMBERING IS NOT TRUSTED ACROSS A RELOAD (review of a8b732d, finding 1: a relay that
// served one item under a seq near 2^53 made a stored cursor skip every honest item after a reload,
// and the list stayed empty with no word said). So every session reads the mailbox from the start
// (the relay's retention bounds it), and within a session a read that finds nothing past the cursor
// asks for the first item again: if it is not the item this session read under that seq, the relay's
// numbering went backwards, which is said, and the mailbox is read again from the start.
//
// THE RELAY'S WORDS ARE NEVER SHOWN (finding 4): a relay that answers "your passkey expired, re-pair
// at ..." must not get that sentence onto the founder's screen. What it says is kept in diagnostics,
// labelled as the relay's and cut to 200 characters; the screen gets a fixed sentence.
//
// THE SEQUENCE OF WHAT THE PHONE SENDS is per channel, counted in the store with update() so two tabs
// cannot spend one seq (the machine's journal refuses a seq at or below the last, relay/Journal.ps1).
//
// THE CHAT (channels/chat) comes through the same mailbox and the same refresh: the Thrall's turns and
// the receipts of the founder's lines are opened with the same key, kept IN MEMORY ONLY for the session
// like the snapshot, and put together by relay/js/protocol.js's chatTimeline (a turn once by id, a long
// one only once all its parts are here, the phone's own line once). A line is a command-equivalent: it
// is sent only from a passkey session, signed by the passkey (user verification), bound to the horde,
// the machine and the Thrall's session the phone last heard of - the same keys rule as an answer: a
// recovery or a read-only session reads the chat and never writes to it.
import * as P from "../relay/protocol.js";
import { newPhoneKey, wipe, prfInput, newRecoveryCode, wrapWithPrf, wrapWithRecovery, unwrap } from "./keywrap.js";

const ENTRY = "horde/";
const RELAY_DOWN = "The relay could not be read just now; the phone will try again.";
const RELAY_REFUSED = "The relay did not take it just now.";
const relaySaid = (reason) => "the relay said: " + String(reason || "").slice(0, 200);
const NO_PRF = "Read only: this passkey gives no PRF, so this phone has nothing to keep this horde's key under, and a horde whose key the passkey does not hold is never answered from this phone. It can still be read: unlock with the recovery code. Answer at the machine, or pair again with a passkey that has PRF.";

function originHost(origin) { const m = /^[a-z]+:\/\/([^:/]+)(:[0-9]+)?$/.exec(origin || ""); return m ? m[1] : ""; }

export function createPhone({ store, authenticator, relay, origin, now = () => Date.now() }) {
  const sessions = new Map();
  // The relay's own words from puts, kept for the next refresh's diagnostics (THE RELAY'S WORDS).
  const diagnostics = [];
  const newSession = (privateKey, publicPoint, mode, pkcs8) => ({ privateKey, publicPoint, mode, pkcs8, pages: [], cursor: 0, seen: new Map(), view: null, chat: newChat() });
  const newChat = () => ({ turns: [], receipts: [], sent: [], session: "", sessionSeq: -1, ids: new Set() });
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

  // One opened chat envelope into the session's memory. The relay may repeat or replay one: an envelope
  // already taken (by its replay key) is skipped, and the timeline shows each turn and line once anyway.
  function takeChat(e, s, opened, item, anomalies) {
    const c = s.chat;
    if (c.ids.has(opened.key)) return;
    c.ids.add(opened.key);
    const h = opened.header;
    if (h.kind === "turns") {
      const r = P.readChatTurns(opened.body, e.horde, e.machine);
      if (!r.ok) { anomalies.push("item " + item.seq + ": " + r.reason); return; }
      if (r.value.dropped) anomalies.push("item " + item.seq + ": " + r.value.dropped + " turn(s) that do not hold together were left out");
      for (const t of r.value.turns) c.turns.push({ ...t, seq: h.seq });
      if (h.seq > c.sessionSeq) { c.session = r.value.session; c.sessionSeq = h.seq; }
    } else if (h.kind === "receipt") {
      const r = P.readChatReceipt(opened.body, e.horde, e.machine);
      if (!r.ok) { anomalies.push("item " + item.seq + ": " + r.reason); return; }
      c.receipts.push({ ...r.value, seq: h.seq, ts: h.ts });
    }
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
        seq: {}, announced: null, lastSnapshotSeq: -1, pairedAt: now()
      };
      await store.put(ENTRY + id, e);
      const s = newSession(pk.privateKey, pk.publicPoint, "read-only", pk.pkcs8);
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
      if (put.state !== "known") { diagnostics.push(relaySaid(put.reason)); throw fail(RELAY_REFUSED + " The announcement was not sent; try again."); }
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
      sessions.set(id, newSession(opened.value.privateKey, opened.value.publicPoint, "passkey", null));
      return summary(e);
    },

    // Unlock with the printed recovery code: READ ONLY. The key's bytes stay in the session so that the
    // next passkey unlock can wrap it again (a lost or changed PRF wrap is mended by the passkey, never
    // by the code).
    async recover(id, code) {
      const e = await entryOf(id);
      const opened = await unwrap(e.wraps.recovery, code, e.horde, e.phoneKeyId, P.unb64u(e.phonePublic), { keepBytes: true });
      if (!opened.ok) throw fail(opened.reason);
      sessions.set(id, newSession(opened.value.privateKey, opened.value.publicPoint, "recovery", opened.value.pkcs8));
      return summary(e);
    },

    lock(id) { const s = sessions.get(id); if (s) { wipe(s.pkcs8); sessions.delete(id); } },

    async forget(id) { this.lock(id); await store.delete(ENTRY + id); },

    // Read the horde's phone mailbox and return the newest complete snapshot this phone can open:
    // { snapshot, seq, questions, pageKeyByNumber, withheld, counts, anomalies, stale, diagnostics }:
    // anomalies are this phone's own sentences, for the screen; diagnostics hold what the relay said,
    // for a person diagnosing, never the screen. waitMs > 0
    // long-polls the relay first (a watch). Needs an unlocked session.
    async refresh(id, { waitMs = 0 } = {}) {
      const e = await entryOf(id);
      const s = sessions.get(id);
      if (!s) throw fail("This horde is locked.", "locked");
      const mailbox = e.horde + "/phone";
      const anomalies = [];
      const said = [];
      let first = true;
      let restarted = false;
      for (let round = 0; round < 64; round++) {
        const r = (first && waitMs > 0) ? await relay.watch(mailbox, s.cursor, 256, waitMs) : await relay.get(mailbox, s.cursor, 256);
        first = false;
        if (r.state !== "known") { anomalies.push(RELAY_DOWN); said.push(relaySaid(r.reason)); break; }
        anomalies.push(...r.value.anomalies);
        if (r.value.items.length === 0 && s.cursor > 0 && !restarted) {
          const head = await relay.get(mailbox, 0, 1);
          const one = head.state === "known" ? head.value.items[0] : null;
          if (one && s.seen.get(one.key) !== one.seq) {
            anomalies.push("the relay's numbering went backwards (its first item is not the one this phone read under that number); the mailbox is read again from the start");
            s.cursor = 0;
            s.seen.clear();
            s.chat.ids.clear();
            restarted = true;
            continue;
          }
        }
        for (const item of r.value.items) {
          s.seen.set(item.key, item.seq);
          const o = await P.openEnvelope(item.text, { keyId: e.machine, signPublic: P.unb64u(e.machineSignPublic) }, { privateKey: s.privateKey, publicPoint: s.publicPoint });
          // Another machine's envelope, or one sealed to another phone key, is not an anomaly: the
          // mailbox is the horde's. A forged or broken one from "this" machine is.
          if (!o.ok) { if (o.reason !== "not from the machine this phone paired with" && o.reason !== "not sealed to this phone") anomalies.push("item " + item.seq + ": " + o.reason); continue; }
          if (o.value.header.channel === "chat") { takeChat(e, s, o.value, item, anomalies); continue; }
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
        if (best.seq !== e.lastSnapshotSeq) await store.update(ENTRY + id, (x) => ({ ...x, lastSnapshotSeq: best.seq }));
      }
      const v = s.view;
      const pageKeyByNumber = {};
      if (v) for (const q of v.questions) pageKeyByNumber[q.question.number] = q.pageKey;
      return {
        snapshot: v ? v.snapshot : "", seq: v ? v.seq : -1, questions: v ? v.questions.map((q) => q.question) : [], pageKeyByNumber,
        withheld: v ? v.withheld : [], counts: v ? v.counts : null, unreadable: v ? v.unreadable : 0, notUnderstood: v ? v.notUnderstood : 0,
        anomalies, stale, mode: s.mode, relayDown: said.length > 0, diagnostics: said.concat(diagnostics.splice(0))
      };
    },

    // The chat of the horde as this session holds it (refresh reads it): { session, items, mode } -
    // items from relay/js/protocol.js's chatTimeline. Needs an unlocked session.
    async chat(id) {
      await entryOf(id);
      const s = sessions.get(id);
      if (!s) throw fail("This horde is locked.", "locked");
      return { session: s.chat.session, items: P.chatTimeline(s.chat), mode: s.mode };
    },

    // One line of the founder to the Thrall, signed with the passkey (user verification) and put into the
    // machine's mailbox, bound to the horde, the machine and the Thrall's session last heard of.
    // messageId is the page's id for these words: sent again, they are posted once. { key, seq }.
    async sendLine(id, { text, messageId }) {
      const e = await entryOf(id);
      const s = sessions.get(id);
      if (!s) throw fail("This horde is locked.", "locked");
      if (s.mode === "read-only") { throw fail(NO_PRF); }
      if (s.mode !== "passkey") { throw fail("Read only: this horde was unlocked with the recovery code, which cannot sign. Unlock with the passkey to write to the Thrall."); }
      if (typeof text !== "string" || !text.trim()) throw fail("There is nothing to send.");
      if (!s.chat.session) throw fail("Nothing has come from the Thrall yet, so there is no session to write to. Wait for its turns, then send.");
      // One id, one set of words (review of 3d837f0, finding 1): the same id is how a resend is known.
      if (s.chat.sent.some((x) => x.messageId === messageId && x.text !== text)) throw fail("These are other words than the line first sent under this id: send them as a new line.");
      const body = P.lineBody({ messageId, horde: e.horde, machine: e.machine, session: s.chat.session, text });
      const env = await sealAndSign(e, "line", "chat", body, assertWith(e));
      const put = await relay.put(e.machineMailbox, env.key, env.text);
      if (put.state !== "known") { diagnostics.push(relaySaid(put.reason)); throw fail("Not sent: " + RELAY_REFUSED + " Send it again; the same line is never delivered twice."); }
      if (!s.chat.sent.some((x) => x.messageId === messageId)) s.chat.sent.push({ messageId, text, at: now(), session: s.chat.session });
      return { key: env.key, seq: put.value.seq };
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
      // What is signed is the question on screen (review of a8b732d, finding 5): a wording the page did
      // not show is refused before the passkey is asked.
      if (Number(q.question.wordingVersion) !== wordingVersion) throw fail("question " + number + " is shown in wording " + q.question.wordingVersion + ", not " + wordingVersion + ": the answer was not sent. Read it again and answer.");
      const body = P.answerBody({ answerId, machine: e.machine, snapshot: q.pageKey, number, wordingVersion, text });
      const env = await sealAndSign(e, "answer", "decisions", body, assertWith(e));
      const put = await relay.put(e.machineMailbox, env.key, env.text);
      if (put.state !== "known") { diagnostics.push(relaySaid(put.reason)); throw fail("Not sent: " + RELAY_REFUSED + " Press Enter to try again; the same words are never saved twice."); }
      return { key: env.key, seq: put.value.seq };
    }
  };
}
