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
//     account        the relay's accounts (account-client.js), or null when it has none
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
// A HOLE IN THIS MAILBOX IS NOT AN ANOMALY (2026-10-13). The horde's phone mailbox is read by every
// trusted phone and acked by none, so its senders keep it small themselves: a machine deletes its own
// older snapshots the moment a newer one is whole there, and its chat and progress past the history
// a phone is shown (relays/Port.ps1, A SENDER TRIMS ITS OWN STREAM). What is left has holes in the
// relay's numbering, by design, and a session that has read to item 40 may next be handed item 47.
// The relay client reports holes apart from its anomalies for exactly this (relay-client.js, gaps),
// and refresh() does not put them on the screen: until this was so, every trimmed snapshot was a
// "gap" notice on the founder's phone. NOTHING RESTED ON THEM: a relay that withholds a newer
// snapshot is caught by lastSnapshotSeq (FRESHNESS, above), and one that withholds the newest of
// anything leaves no hole to see at all. The check that the relay's numbering has not gone BACKWARDS
// is unchanged, and holds through a trim: the first item still in the mailbox is one this session
// read under that very number.
//
// THE RELAY'S WORDS ARE NEVER SHOWN (finding 4): a relay that answers "your passkey expired, re-pair
// at ..." must not get that sentence onto the founder's screen. What it says is kept in diagnostics,
// labelled as the relay's and cut to 200 characters; the screen gets a fixed sentence.
//
// THE PAIRING RESPONSE GOES THROUGH THE RELAY (relay/Pairing.ps1, THE RESPONSE THROUGH THE RELAY): pair()
// seals it to the machine's agreement key from the offer and puts it in the offer's own pairing
// mailbox, where `horde relay pair` waits. The sealed text is kept in this object's memory only, so
// sendPairing() can send it again until the horde is announced; the plain response is handed back too,
// for Copy and Share, the fallback when the relay cannot be reached.
//
// A RELAY WITH ACCOUNTS (account-client.js) knows a machine only by the signing key a signed-in phone
// registered to its account. So pair() registers the offer's machine - with the offer's ACCOUNT GRANT,
// relay/Pairing.ps1 - FIRST, before a passkey is made or anything is sent: a phone that is not signed in,
// or a machine the relay will not take (another account's, a spent grant), is told so in this file's own
// words, and nothing is left half made. Without accounts (a memory or binding relay) nothing changes.
//
// AN ANSWER IS KEPT UNTIL THE PC HAS APPLIED IT (the founder, 2026-10-14, relay fixes 3 and 4: the runner
// was down 2 h 38 min, twenty answers waited with nothing shown, and one envelope never arrived and
// nothing said so). A machine whose snapshot carries receipts (channels/decisions/Channel.ps1, WHAT
// BECAME OF EACH ANSWER) has every answer sent to it kept in this phone's OUTBOX (the store, outbox/<id>):
// the answer's ids, the seq of every envelope that carried it, that envelope whole (signed by the
// passkey and sealed to the machine), and his words SEALED TO THIS PHONE'S OWN KEY - so nothing
// decrypted is stored, and the words show again after a reload once the horde is unlocked. answers()
// says what became of each (relay/js/protocol.js, answerState): sent, received by PC, applied or
// refused; applied and refused leave the outbox. resend() sends again what the PC reports MISSING - as
// a NEW envelope under a new seq, because the journal refuses a late one for good - and what it never
// saw at the end of the stream - as the same envelope put again - each at most once in ten minutes. The
// machine applies by answerId, so a resend lands once. A machine without receipts keeps nothing here:
// there is nothing that would ever confirm it.
//
// THE SEQUENCE OF WHAT THE PHONE SENDS is per channel, counted in the store with update() so two tabs
// cannot spend one seq (the machine's journal refuses a seq at or below the last, relay/Journal.ps1).
//
// THE CHAT (channels/chat) comes through the same mailbox and the same refresh: the Thrall's turns and
// the receipts of the founder's lines are opened with the same key, kept IN MEMORY ONLY for the session
// like the snapshot, and put together by relay/js/protocol.js's chatTimeline (a turn once by id, a long
// one only once all its parts are here, the phone's own line once), each with the time it was said: a
// turn's own, and a line's as the passkey signed it - the time in the line's envelope, which is what
// this phone keeps for a line it sent, and what the machine's receipt hands back. A line is a command-equivalent: it
// is sent only from a passkey session, signed by the passkey (user verification), bound to the horde,
// the machine and the Thrall's session the phone last heard of - the same keys rule as an answer: a
// recovery or a read-only session reads the chat and never writes to it.
//
// THE PROGRESS LOG (channels/progress) comes through the same mailbox and the same refresh, machine to
// phone only: the phone sends nothing on that channel. Its entries are opened with the same key and kept
// IN MEMORY ONLY for the session, exactly as the chat's turns are - every session reads the mailbox from
// its start, and relay/js/protocol.js's progressLog puts them in the order they were written, each once
// by id. WHAT IS STORED of it is one thing: the READING POSITION, per horde entry on this device - the
// id and line number of the last entry read (progressRead) - so the log opens where he left it, with
// how many are new. An id and a number, never a word of the log; read back guarded (progressPosition),
// so a damaged record is no position. The position only ever moves forward.
//
// THE CARDS (channels/cards) come through the same mailbox and the same refresh, machine to phone only:
// one whole snapshot per machine, of which the session keeps the newest it opened (by its envelope's seq),
// in memory only. THE FOUNDER RUNS TWO MACHINES, and each is its own pairing here, opening only its own
// machine's envelopes. So a refresh also offers a cards envelope it cannot open to every other UNLOCKED
// pairing of the same horde, and cards() merges what all of them hold, by machine name
// (relay/js/protocol.js, mergeCards). A card's stream is its own pairing's progress log, filtered on the
// page to its lane with its own machine's map (progress() hands the map over as areas).
import * as P from "../relay/protocol.js";
import { newPhoneKey, wipe, prfInput, newRecoveryCode, wrapWithPrf, wrapWithRecovery, unwrap } from "./keywrap.js";

// THE NOTICES (channels/notices) come through the same mailbox and the same refresh: what the machine
// decided the founder should be told (notices/Decide.ps1 - a session's `horde notify` line, a followed
// lane's new progress entry, a session cut off for the hour), each with the FOLLOW SWITCHES that machine
// holds. The phone keeps the notices by id (one notice, however many envelopes carry it) and each
// machine's switches from its newest envelope: THE PHONE SHOWS WHAT THE MACHINE HOLDS, never a switch it
// only asked for. A cards envelope of another machine is opened by that machine's own pairing, and so is
// its notices envelope. Read or unread is this phone's own (noticesRead on the stored entry: ids, the
// newest 500), and goes nowhere. A SWITCH IS SENT LIKE AN ANSWER: the passkey signs it (user
// verification), it is sealed to the machine of the card, and only a passkey session sends one.
const ENTRY = "horde/";
// THE OUTBOX (the header, AN ANSWER IS KEPT UNTIL THE PC HAS APPLIED IT): one record per horde entry.
const OUTBOX = "outbox/";
const OUTBOX_INFO = "horde-phone/outbox/v1 answer";
const OUTBOX_MOST = 200;
const RELAY_DOWN = "The relay could not be read just now; the phone will try again.";
const RELAY_REFUSED = "The relay did not take it just now.";
const relaySaid = (reason) => "the relay said: " + String(reason || "").slice(0, 200);
const SIGN_IN_FIRST = "Sign in first: this relay lets in only a signed-in phone, and the machines it registers.";
const NOT_REGISTERED = "The relay did not register this machine with your account, so the machine could not reach it. Make a new offer at the machine and pair again.";
const NO_PRF = "Read only: this passkey gives no PRF, so this phone has nothing to keep this horde's key under, and a horde whose key the passkey does not hold is never answered from this phone. It can still be read: unlock with the recovery code. Answer at the machine, or pair again with a passkey that has PRF.";

// A passkey that did not sign (the founder cancelled the prompt, or it timed out): said in the phone's own
// words, with the browser's error NAME (NotAllowedError, a code word) and never its message, so the
// founder sees why an announcement was not sent (his first live use, 2026-10-11: it never went, and why
// was nowhere on the screen).
const PASSKEY_DID_NOT_SIGN = "The passkey did not sign the announcement (the prompt was cancelled, or it timed out), so nothing was sent. Tap announce again and confirm with your passkey.";
function passkeyDidNotSign(x) {
  const name = x && typeof x.name === "string" && /^[A-Za-z]{1,40}$/.test(x.name) ? x.name : "";
  return PASSKEY_DID_NOT_SIGN + (name && name !== "Error" ? " (" + name + ")" : "");
}

function originHost(origin) { const m = /^[a-z]+:\/\/([^:/]+)(:[0-9]+)?$/.exec(origin || ""); return m ? m[1] : ""; }

export function createPhone({ store, authenticator, relay, account = null, origin, now = () => Date.now() }) {
  const sessions = new Map();
  // Sealed pairing responses not yet known to have arrived, by horde id (THE PAIRING RESPONSE...).
  const pairings = new Map();
  // The relay's own words from puts, kept for the next refresh's diagnostics (THE RELAY'S WORDS).
  const diagnostics = [];
  const newSession = (privateKey, publicPoint, mode, pkcs8) => ({ privateKey, publicPoint, mode, pkcs8, pages: [], cursor: 0, seen: new Map(), view: null, chat: newChat(), progress: newProgress(), cards: null, cardsRefused: "", cardsUnpaired: false, notices: newNotices(), outboxText: new Map(), settled: new Map() });
  const newChat = () => ({ turns: [], receipts: [], sent: [], session: "", sessionSeq: -1, ids: new Set() });
  const newProgress = () => ({ entries: [], notices: [], ids: new Set() });
  const newNotices = () => ({ byId: new Map(), keys: new Set(), follows: {}, followsSeq: -1 });
  const fail = (reason, code = "refused") => { const e = new Error(reason); e.code = code; return e; };

  async function entryOf(id) {
    const e = await store.get(ENTRY + id);
    if (!e) throw fail("there is no such horde on this phone");
    return e;
  }
  // THE SEQ IS SPENT ONLY ONCE THE PASSKEY HAS SIGNED (review of PR 262, M1): it was spent before the
  // prompt, so every prompt cancelled or timed out left a hole the machine reported missing - and a hole
  // is noise that can push a real loss out of the receipt's list. So the next seq is read, the envelope
  // signed under it, and only then claimed, in one update that takes it only if no other tab has: one
  // that lost the race signs again under the next.
  async function claimSeq(id, channel, seq) {
    let won = false;
    await store.update(ENTRY + id, (e) => {
      if (!e) throw fail("there is no such horde on this phone");
      const counts = { ...(e.seq || {}) };
      if ((counts[channel] || 0) >= seq) return e;
      counts[channel] = seq;
      won = true;
      return { ...e, seq: counts };
    });
    return won;
  }
  function assertWith(e, prf = false) {
    // relay/js/protocol.js's passkey: user verification required by the authenticator adapter.
    return async (challenge) => authenticator.get({ rpId: e.rpId, credentialId: P.unb64u(e.credentialId), challenge, prfInput: prf ? prfInput(e.horde, e.machine) : null });
  }
  // ts: the envelope's own time, which the passkey signs with the rest: when the founder sent it - and,
  // for an answer signed again, when he FIRST sent it (A STALE ANSWER NEVER WINS, in the header).
  async function sealAndSign(e, kind, channel, body, assert, ts = null) {
    for (let tries = 0; tries < 3; tries++) {
      const held = await store.get(ENTRY + e.id);
      if (!held) throw fail("there is no such horde on this phone");
      const seq = ((held.seq && held.seq[channel]) || 0) + 1;
      const parts = await P.sealEnvelope({ kind, channel, from: e.deviceKeyId, seq, ts: ts === null ? now() : ts, recipientPublic: P.unb64u(e.machineAgreePublic), body });
      const text = await P.signEnvelope(parts, assert);
      if (await claimSeq(e.id, channel, seq)) return { text, key: P.replayKey(parts.header), ts: parts.header.ts, seq };
    }
    throw fail("Another window of this app sent at the same moment, three times over: nothing was sent. Send it again.");
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

  // One opened progress envelope into the session's memory (THE PROGRESS LOG, in the header). An envelope
  // already taken is skipped; a kind this phone does not know is left alone.
  function takeProgress(e, s, opened, item, anomalies) {
    const g = s.progress;
    if (g.ids.has(opened.key)) return;
    g.ids.add(opened.key);
    const h = opened.header;
    if (h.kind === "entries") {
      const r = P.readProgressEntries(opened.body, e.horde, e.machine);
      if (!r.ok) { anomalies.push("item " + item.seq + ": " + r.reason); return; }
      if (r.value.dropped) anomalies.push("item " + item.seq + ": " + r.value.dropped + " progress entr" + (r.value.dropped === 1 ? "y that does" : "ies that do") + " not hold together " + (r.value.dropped === 1 ? "was" : "were") + " left out");
      for (const x of r.value.entries) g.entries.push({ ...x, seq: h.seq });
    } else if (h.kind === "notice") {
      const r = P.readProgressNotice(opened.body, e.horde, e.machine);
      if (!r.ok) { anomalies.push("item " + item.seq + ": " + r.reason); return; }
      g.notices.push({ ...r.value, seq: h.seq });
    }
  }

  // One opened notices envelope into a session's memory (THE NOTICES, in the header): each notice once by
  // its id; the switches of the envelope of the highest seq stand.
  function takeNotices(e, s, opened, item, anomalies) {
    const g = s.notices;
    if (opened.header.kind !== "notices" || g.keys.has(opened.key)) return;
    g.keys.add(opened.key);
    const r = P.readNotices(opened.body, e.horde, e.machine);
    if (!r.ok) { anomalies.push("item " + item.seq + ": " + r.reason); return; }
    if (r.value.dropped) anomalies.push("item " + item.seq + ": " + r.value.dropped + " notice(s) that do not hold together were left out");
    for (const x of r.value.notices) if (!g.byId.has(x.id)) g.byId.set(x.id, x);
    if (opened.header.seq > g.followsSeq) { g.follows = r.value.follows; g.followsSeq = opened.header.seq; }
  }
  // One opened cards envelope into a session's memory (THE CARDS, in the header): the newest by seq stands.
  function takeCards(e, s, opened, item, anomalies) {
    if (opened.header.kind !== "snapshot") return;
    if (s.cards && s.cards.seq >= opened.header.seq) return;
    const r = P.readCardsSnapshot(opened.body, e.horde, e.machine);
    // A refusal is kept for the Progress tab's one line when no cards stand (cards-why.js); a good one clears it.
    if (!r.ok) { anomalies.push("item " + item.seq + ": " + r.reason); s.cardsRefused = r.reason; return; }
    if (r.value.dropped) anomalies.push("item " + item.seq + ": " + r.value.dropped + " card(s) that do not hold together were left out");
    s.cards = { entry: e.id, seq: opened.header.seq, value: r.value };
    s.cardsRefused = "";
  }
  // Whether an envelope that no pairing opened says it is cards from a PC of e's horde that this phone has
  // NO pairing for (locked or not): only the Progress tab's one line rests on it (cards-why.js), so its
  // unverified header is enough - a forged one can do no more than show that line.
  async function cardsFromUnpaired(e, text) {
    let h = null;
    try { h = JSON.parse(text).header; } catch (x) { return false; }
    if (!h || h.channel !== "cards" || typeof h.from !== "string") return false;
    for (const x of await store.list(ENTRY)) if (x.horde === e.horde && x.machine === h.from) return false;
    return true;
  }
  // The other unlocked pairings of e's horde, each with its session: who else may open a cards envelope.
  async function siblingsOf(e) {
    const out = [];
    for (const x of await store.list(ENTRY)) if (x.id !== e.id && x.horde === e.horde && sessions.has(x.id)) out.push({ e: x, s: sessions.get(x.id) });
    return out;
  }

  // Put a sealed pairing response in its offer's mailbox. true when the relay took it; what the relay
  // said otherwise goes to diagnostics, never the screen.
  async function sendSealed(id) {
    const p = pairings.get(id);
    if (!p) throw fail("there is no pairing response to send for this horde: it was announced, or the app was reloaded since. Pair again, or use Copy");
    const put = await relay.put(p.mailbox, p.key, p.sealed);
    if (put.state !== "known") { diagnostics.push(relaySaid(put.reason)); return false; }
    return true;
  }

  // THE OUTBOX (the header). Its record: { v: 1, items: [{ answerId, number, part, wordingVersion,
  // snapshot, sealed: { enc, box }, seqs, envelope: { key, text }, sentAt, lastSentAt, lastResendAt }] }.
  function slotOf(number, part) { return String(number) + ":" + (part || ""); }
  async function outboxOf(id) {
    const x = await store.get(OUTBOX + id);
    return x && Array.isArray(x.items) ? x.items : [];
  }
  function answerStateOf(s, item, receipt, at) { return P.answerState(item, receipt, s.view ? s.view.ts : 0, at); }
  // His words, opened with the session's key, or null when they cannot be (another key's, or damaged).
  async function openKept(s, item) {
    if (s.outboxText.has(item.answerId)) return s.outboxText.get(item.answerId);
    try {
      const text = P.fromUtf8(await P.hpkeOpen(s.privateKey, s.publicPoint, P.unb64u(item.sealed.enc), P.utf8(OUTBOX_INFO), P.utf8(item.answerId), P.unb64u(item.sealed.box)));
      s.outboxText.set(item.answerId, text);
      return text;
    } catch (x) { return null; }
  }
  // One answer into the outbox, or one more envelope of it: his words sealed to this phone's own key, the
  // envelope the relay took kept whole (signed, and sealed to the machine), and its seq added.
  // A NEW ANSWER TO A QUESTION AND PART TAKES THE PLACE OF EVERY OLDER ONE STILL WAITING THERE (review of
  // PR 262, M2): kept, an older answer lost on the way would be sent again after the newer one and
  // stand as his answer. stuck: this send was the one re-sign of an answer stuck at received (S1).
  async function keepAnswer(id, s, a, env, stuck = false) {
    const sealed = await P.hpkeSeal(s.publicPoint, P.utf8(OUTBOX_INFO), P.utf8(a.answerId), P.utf8(a.text));
    s.outboxText.set(a.answerId, a.text);
    const at = now();
    const slot = slotOf(a.number, a.part || "");
    await store.update(OUTBOX + id, (x) => {
      const items = ((x && x.items) || []).filter((y) => y.answerId === a.answerId || slotOf(y.number, y.part) !== slot);
      const i = items.findIndex((y) => y.answerId === a.answerId);
      if (i >= 0) items[i] = { ...items[i], seqs: items[i].seqs.concat([env.seq]), envelope: { key: env.key, text: env.text }, lastSentAt: at, stuckResent: items[i].stuckResent === true || stuck };
      else items.push({ answerId: a.answerId, number: a.number, part: a.part || "", wordingVersion: a.wordingVersion, snapshot: a.snapshot, sealed: { enc: P.b64u(sealed.enc), box: P.b64u(sealed.sealed) }, seqs: [env.seq], envelope: { key: env.key, text: env.text }, signedAt: env.ts, sentAt: at, lastSentAt: at, lastResendAt: 0 });
      return { v: 1, items };
    });
  }

  function summary(e) {
    const s = sessions.get(e.id);
    return {
      id: e.id, horde: e.horde, machine: e.machine, label: e.label, fingerprint: e.fingerprint, prf: e.prfEnabled,
      announced: !!e.announced, unlocked: !!s, mode: s ? s.mode : "", wraps: Object.keys(e.wraps || {}).sort(),
      // HEARD: a snapshot from the machine has been drawn on this phone (lastSnapshotSeq, stored), so the
      // machine took the announcement. Until then the app offers to announce again (app.js).
      heard: Number.isSafeInteger(e.lastSnapshotSeq) && e.lastSnapshotSeq >= 0
    };
  }

  return {
    async hordes() { return (await store.list(ENTRY)).map(summary).sort((a, b) => (a.horde + a.machine).localeCompare(b.horde + b.machine)); },

    // Answer a pairing offer: make the passkey (the founder's finger), the phone identity key and its
    // recovery wrap, and send the response to the machine through the relay, sealed. { id, fingerprint,
    // response, recoveryCode, prf, pairMailbox, relayed }: relayed says whether the relay took it, and
    // response is the plain text for Copy and Share. The recovery code is shown ONCE, to be written
    // down; it is not kept anywhere.
    async pair({ offerText, label }) {
      const read = await P.readOffer(offerText, now());
      if (!read.ok) throw fail(read.reason);
      const o = read.value;
      if (o.origins.indexOf(origin) < 0) throw fail("this offer is for " + o.origins.join(", ") + ", not this app at " + origin + ": open the app the offer names");
      const host = originHost(origin);
      if (host !== o.rpId && !host.endsWith("." + o.rpId)) throw fail("this app at " + origin + " cannot make passkeys for " + o.rpId);
      if (!P.validLabel(label)) throw fail("name this phone in 1 to 64 plain characters, with no quote or backslash");
      for (const e of await store.list(ENTRY)) { if (e.horde === o.horde && e.machine === o.machine) throw fail("this phone is already paired with that machine of " + o.horde + "; forget that pairing first"); }
      if (account) {
        const reg = await account.registerMachine(o);
        if (reg.state !== "known") { diagnostics.push(relaySaid(reg.reason)); throw fail(reg.status === 401 ? SIGN_IN_FIRST : NOT_REGISTERED); }
      }
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
      let sealed;
      try { sealed = await P.sealPairingResponse(o, response); } catch (x) { wipe(pk.pkcs8); throw fail("the response could not be sealed for the machine: " + x.message); }
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
      pairings.set(id, { mailbox: o.pairMailbox, key: P.pairingKey(o.offer), sealed });
      const relayed = await sendSealed(id);
      return { id, fingerprint, response, recoveryCode, prf: e.prfEnabled, pairMailbox: o.pairMailbox, relayed };
    },

    // Send the sealed pairing response again (the relay did not take it, or the machine is waiting
    // still): the relay keeps one copy under the offer's key. true when the relay took it.
    async sendPairing(id) { return sendSealed(id); },

    // Announce this horde's phone identity key to the machine, vouched for by the passkey (two
    // assertions: the vouch, which also asks for PRF, and the envelope's signature). Done once the
    // founder has confirmed the fingerprint at the machine; done again if no snapshot ever comes.
    async announce(id) {
      let e = await entryOf(id);
      const s = sessions.get(id);
      if (s && s.mode === "recovery") throw fail("unlocked with the recovery code, this phone reads only: unlock with the passkey to announce it");
      const phonePublic = P.unb64u(e.phonePublic);
      // Each passkey prompt, its refusal said as the phone's (PASSKEY_DID_NOT_SIGN).
      const signing = (prf) => async (challenge) => { try { return await assertWith(e, prf)(challenge); } catch (x) { throw fail(passkeyDidNotSign(x), "passkey"); } };
      const vouch = await signing(true)(await P.vouchChallenge(e.horde, phonePublic));
      e = await keepPasskeyWrap(e, s, vouch.prfFirst);
      const env = await sealAndSign(e, "phone-key", "trust", P.phoneKeyBody(phonePublic, vouch), signing(false));
      const put = await relay.put(e.machineMailbox, env.key, env.text);
      if (put.state !== "known") { diagnostics.push(relaySaid(put.reason)); throw fail(RELAY_REFUSED + " The announcement was not sent; try again."); }
      await store.update(ENTRY + id, (x) => ({ ...x, announced: { key: env.key, at: now() } }));
      pairings.delete(id);
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

    // The outbox first: an entry gone with its outbox left would leave words no session can open.
    async forget(id) { this.lock(id); pairings.delete(id); await store.delete(OUTBOX + id); await store.delete(ENTRY + id); },

    // Read the horde's phone mailbox and return the newest complete snapshot this phone can open:
    // { snapshot, seq, questions, pageKeyByNumber, withheld, notShown, counts, anomalies, stale, diagnostics }:
    // notShown is the one line for what the snapshot withholds, "" for nothing (relay/js/protocol.js,
    // withheldWords): this phone's own sentence, never the machine's words.
    //
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
      const siblings = await siblingsOf(e);
      for (let round = 0; round < 64; round++) {
        const r = (first && waitMs > 0) ? await relay.watch(mailbox, s.cursor, 256, waitMs) : await relay.get(mailbox, s.cursor, 256);
        first = false;
        if (r.state !== "known") { anomalies.push(RELAY_DOWN); said.push(relaySaid(r.reason)); break; }
        // The batch's anomalies, and not its gaps (the header, A HOLE IN THIS MAILBOX IS NOT AN ANOMALY).
        anomalies.push(...r.value.anomalies);
        if (r.value.items.length === 0 && s.cursor > 0 && !restarted) {
          const head = await relay.get(mailbox, 0, 1);
          const one = head.state === "known" ? head.value.items[0] : null;
          if (one && s.seen.get(one.key) !== one.seq) {
            anomalies.push("the relay's numbering went backwards (its first item is not the one this phone read under that number); the mailbox is read again from the start");
            s.cursor = 0;
            s.seen.clear();
            s.chat.ids.clear();
            s.progress.ids.clear();
            s.notices.keys.clear();
            restarted = true;
            continue;
          }
        }
        for (const item of r.value.items) {
          s.seen.set(item.key, item.seq);
          const o = await P.openEnvelope(item.text, { keyId: e.machine, signPublic: P.unb64u(e.machineSignPublic) }, { privateKey: s.privateKey, publicPoint: s.publicPoint });
          // Another machine's envelope, or one sealed to another phone key, is not an anomaly: the
          // mailbox is the horde's. A forged or broken one from "this" machine is.
          if (!o.ok) {
            if (o.reason !== "not from the machine this phone paired with" && o.reason !== "not sealed to this phone") { anomalies.push("item " + item.seq + ": " + o.reason); continue; }
            // ANOTHER MACHINE OF THIS HORDE: its cards, opened by its own pairing (THE CARDS, in the header).
            let took = false;
            for (const x of siblings) {
              const so = await P.openEnvelope(item.text, { keyId: x.e.machine, signPublic: P.unb64u(x.e.machineSignPublic) }, { privateKey: x.s.privateKey, publicPoint: x.s.publicPoint });
              if (so.ok && so.value.header.channel === "cards") { takeCards(x.e, x.s, so.value, item, anomalies); took = true; break; }
              if (so.ok && so.value.header.channel === "notices") { takeNotices(x.e, x.s, so.value, item, anomalies); took = true; break; }
            }
            if (!took && o.reason === "not from the machine this phone paired with" && await cardsFromUnpaired(e, item.text)) s.cardsUnpaired = true;
            continue;
          }
          if (o.value.header.channel === "cards") { takeCards(e, s, o.value, item, anomalies); continue; }
          if (o.value.header.channel === "notices") { takeNotices(e, s, o.value, item, anomalies); continue; }
          if (o.value.header.channel === "chat") { takeChat(e, s, o.value, item, anomalies); continue; }
          if (o.value.header.channel === "progress") { takeProgress(e, s, o.value, item, anomalies); continue; }
          if (o.value.header.channel !== "decisions" || o.value.header.kind !== "snapshot") continue;
          const page = P.readSnapshotPage(o.value.body, e.horde, e.machine);
          if (!page.ok) { anomalies.push("item " + item.seq + ": " + page.reason); continue; }
          s.pages.push({ key: o.value.key, seq: o.value.header.seq, relaySeq: item.seq, ts: o.value.header.ts, page: page.value });
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
        withheld: v ? v.withheld : [], notShown: v ? P.withheldWords(v.withheld) : "", counts: v ? v.counts : null, unreadable: v ? v.unreadable : 0, notUnderstood: v ? v.notUnderstood : 0,
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

    // The progress log of the horde as this session holds it (refresh reads it), with the reading position
    // this device keeps: relay/js/protocol.js's progressLog, and the session's mode. Needs an unlocked session.
    async progress(id) {
      const e = await entryOf(id);
      const s = sessions.get(id);
      if (!s) throw fail("This horde is locked.", "locked");
      return { ...P.progressLog({ ...s.progress, position: e.progressRead }), mode: s.mode, areas: s.cards ? s.cards.value.areas : [] };
    },

    // The cards of the horde (THE CARDS, in the header): this pairing's and every other unlocked pairing's
    // of the same horde, merged by machine name - relay/js/protocol.js's mergeCards. Needs an unlocked session.
    async cards(id) {
      const e = await entryOf(id);
      const s = sessions.get(id);
      if (!s) throw fail("This horde is locked.", "locked");
      const all = [s, ...(await siblingsOf(e)).map((x) => x.s)];
      const held = all.map((x) => x.cards).filter((x) => x);
      // Why there are none, when there are none (cards-why.js): a refused snapshot, or cards from a PC not paired.
      const refused = (all.find((x) => x.cardsRefused) || { cardsRefused: "" }).cardsRefused;
      return { ...P.mergeCards(held), mode: s.mode, refused, unpaired: all.some((x) => x.cardsUnpaired) };
    },

    // He has read as far as the entry entryId (or, with none, to the newest): kept on this device, an id
    // and a line number. Only an entry this session holds, and only forward - a position is never moved
    // back, and never to something the phone was not sent. The log, as progress() answers it.
    async markProgressRead(id, entryId = "") {
      const e = await entryOf(id);
      const s = sessions.get(id);
      if (!s) throw fail("This horde is locked.", "locked");
      const log = P.progressLog({ ...s.progress, position: e.progressRead });
      const index = entryId ? log.items.findIndex((it) => it.id === entryId) : log.items.length - 1;
      if (entryId && index < 0) throw fail("That entry is not in the progress log this phone holds.");
      if (index > log.readIndex) {
        const read = { id: log.items[index].id, n: log.items[index].n };
        await store.update(ENTRY + id, (x) => { if (!x) throw fail("there is no such horde on this phone"); return { ...x, progressRead: read }; });
        return { ...P.progressLog({ ...s.progress, position: read }), mode: s.mode, areas: s.cards ? s.cards.value.areas : [] };
      }
      return { ...log, mode: s.mode, areas: s.cards ? s.cards.value.areas : [] };
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
      if (!s.chat.sent.some((x) => x.messageId === messageId)) s.chat.sent.push({ messageId, text, at: env.ts, session: s.chat.session });
      return { key: env.key, seq: put.value.seq };
    },

    // The notices of the horde (THE NOTICES, in the header): this pairing's and every other unlocked pairing's
    // of the same horde, newest first, read or unread as this phone keeps it, and each machine's switches:
    // { items, unread, follows: { <pairing id>: { <lane>: true|false } } }. Needs an unlocked session.
    async notices(id) {
      const e = await entryOf(id);
      const s = sessions.get(id);
      if (!s) throw fail("This horde is locked.", "locked");
      const all = [{ e, s }, ...(await siblingsOf(e))];
      const read = new Set(e.noticesRead || []);
      const held = all.map((x) => ({ entry: x.e.id, machine: x.e.label || x.e.machine, notices: [...x.s.notices.byId.values()] }));
      const list = P.noticeList(held, read);
      const follows = {};
      for (const x of all) follows[x.e.id] = { ...x.s.notices.follows };
      return { ...list, follows };
    },

    // He has read these notices (ids), or with none given every notice the phone holds: kept on this phone
    // only, the newest 500 ids. The notices, as notices() answers them.
    async markNoticesRead(id, ids = null) {
      const now = await this.notices(id);
      const want = ids === null ? now.items.map((x) => x.id) : ids.filter((x) => typeof x === "string" && /^[0-9a-f]{32}$/.test(x));
      await store.update(ENTRY + id, (x) => {
        if (!x) throw fail("there is no such horde on this phone");
        const kept = (x.noticesRead || []).filter((k) => want.indexOf(k) < 0);
        return { ...x, noticesRead: kept.concat(want).slice(-500) };
      });
      return this.notices(id);
    },

    // The FOLLOW SWITCH of one lane of one machine's card (THE NOTICES, in the header): entry is the pairing
    // whose machine sent the card, lane its lane id or "thrall". Signed with the passkey and put into that
    // machine's mailbox; the switch shows as set once the machine's next notices envelope carries it. { key }.
    async follow(id, { entry = id, lane, on }) {
      const owner = await entryOf(id);
      const e = await entryOf(entry);
      if (e.horde !== owner.horde) throw fail("that card is of another horde");
      const s = sessions.get(e.id);
      if (!s) throw fail("This horde is locked.", "locked");
      if (s.mode !== "passkey") throw fail(s.mode === "read-only" ? NO_PRF : "Not sent: this horde was unlocked with the recovery code, which cannot sign. Unlock with the passkey to change what you follow.");
      const body = P.followBody({ setId: P.hex(P.randomBytes(16)), machine: e.machine, lane: String(lane), on: on === true });
      const env = await sealAndSign(e, "follow", "notices", body, assertWith(e));
      const put = await relay.put(e.machineMailbox, env.key, env.text);
      if (put.state !== "known") { diagnostics.push(relaySaid(put.reason)); throw fail("Not sent: " + RELAY_REFUSED + " Tap the switch again."); }
      return { key: env.key };
    },

    // The founder's answer to one question of the snapshot on screen, signed with the passkey (user
    // verification) and put into the machine's mailbox. answerId is the page's id for these words: the
    // same words sent again carry it, and the machine stores them once. { key, seq }.
    // part: the letter of the ONE PART of the question the words answer, or "" for the whole question.
    // A machine whose snapshot says it reads version 2 answers is sent the part as a member of the
    // answer; an earlier machine is sent the words with the letter before them, "(b) ...", as an
    // answer of the version it reads - which it keeps, and its window reads back into that part.
    async answer(id, { number, wordingVersion, text, answerId, part = "" }) {
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
      if (part !== "" && !/^[a-z]$/.test(part)) throw fail("the part answered is not one of the question's parts: the answer was not sent.");
      const takesParts = Number(v.answers) >= 2;
      // NOTHING UNCONFIRMED IS EVER DROPPED TO MAKE ROOM (review of PR 262): with the outbox full, the
      // answer is not sent, and he is told why. What this answer replaces does not count.
      if (Array.isArray(v.receipts)) {
        const slot = slotOf(number, takesParts ? part : "");
        const held = (await outboxOf(id)).filter((i) => i.answerId !== answerId && slotOf(i.number, i.part) !== slot);
        if (held.length >= OUTBOX_MOST) throw fail("Not sent: " + OUTBOX_MOST + " answers are still waiting for the PC to confirm them. Once it is running again they go, and this one can be sent.");
      }
      // To a machine that does not read a part's answer, the part's letter goes before the words.
      const words = (part !== "" && !takesParts) ? "(" + part + ") " + text : text;
      const body = P.answerBody({ answerId, machine: e.machine, snapshot: q.pageKey, number, wordingVersion, text: words, part: takesParts ? part : "" });
      const env = await sealAndSign(e, "answer", "decisions", body, assertWith(e));
      const put = await relay.put(e.machineMailbox, env.key, env.text);
      if (put.state !== "known") { diagnostics.push(relaySaid(put.reason)); throw fail("Not sent: " + RELAY_REFUSED + " Press Enter to try again; the same words are never saved twice."); }
      // KEPT UNTIL APPLIED, by a machine that says what became of its answers (its snapshot has receipts).
      if (Array.isArray(v.receipts)) await keepAnswer(id, s, { answerId, number, part: takesParts ? part : "", wordingVersion, snapshot: q.pageKey, text: words }, env);
      return { key: env.key, seq: put.value.seq };
    },

    // A CHANGE OF RANK of one question of the snapshot on screen - his tap on its Importance or Blocking
    // button (decisions/page/list.js) - SENT LIKE AN ANSWER: only from a passkey session, signed with the
    // passkey (user verification), sealed to the machine of the snapshot, bound to it and to the page
    // that carried the question (channels/decisions/Channel.ps1, A CHANGE OF RANK FROM THE PHONE). Only to
    // a machine whose snapshot says it takes one (ranks). Nothing is kept: the snapshot that shows the
    // new level is its confirmation, and rankState says what the PC said of it. { key, seq }.
    async rank(id, { number, which, level, rankId }) {
      const e = await entryOf(id);
      const s = sessions.get(id);
      if (!s) throw fail("This horde is locked.", "locked");
      if (s.mode !== "passkey") { throw fail(s.mode === "read-only" ? NO_PRF : "Read only: this horde was unlocked with the recovery code, which cannot sign. Unlock with the passkey to change how a question is ranked."); }
      const v = s.view;
      if (!v || v.ranks !== true) throw fail("Not changed: this PC does not take a change of rank from the phone yet. Change it at the PC.");
      const q = v.questions.find((x) => x.question.number === number);
      if (!q) throw fail("question " + number + " is not in the snapshot this phone holds");
      const body = P.rankBody({ rankId, machine: e.machine, snapshot: q.pageKey, number, which, level });
      const env = await sealAndSign(e, "rank", "decisions", body, assertWith(e));
      const put = await relay.put(e.machineMailbox, env.key, env.text);
      if (put.state !== "known") { diagnostics.push(relaySaid(put.reason)); throw fail("Not changed: " + RELAY_REFUSED + " Tap it again."); }
      return { key: env.key, seq: put.value.seq };
    },

    // What the PC said of a change of rank, from the receipt in the snapshot on screen: "applied",
    // "refused", or "sent" while it has said neither. Needs an unlocked session.
    async rankState(id, rankId) {
      const e = await entryOf(id);
      const s = sessions.get(id);
      if (!s) throw fail("This horde is locked.", "locked");
      const receipt = s.view ? P.receiptFor(s.view.receipts, e.deviceKeyId) : null;
      if (receipt && receipt.applied.has(rankId)) return "applied";
      if (receipt && receipt.refused.has(rankId)) return "refused";
      return "sent";
    },

    // The answers this phone keeps for the horde, each with what became of it (relay/js/protocol.js,
    // answerState): [{ answerId, number, part, text, state, warning, sentAt }], his words opened with the
    // session's key. An answer the snapshot on screen says is applied or refused leaves the store here, and is
    // still answered so for the rest of the session. Needs an unlocked session.
    async answers(id) {
      const e = await entryOf(id);
      const s = sessions.get(id);
      if (!s) throw fail("This horde is locked.", "locked");
      const receipt = s.view ? P.receiptFor(s.view.receipts, e.deviceKeyId) : null;
      const at = now();
      const out = [];
      const settled = [];
      for (const item of await outboxOf(id)) {
        const st = answerStateOf(s, item, receipt, at);
        // WORDS THAT CANNOT BE READ STILL STAND AS AN ANSWER (review of PR 262, S3): the question shows
        // answered, pending, with a line that says its words are not readable here - never empty.
        const text = await openKept(s, item);
        const a = { answerId: item.answerId, number: item.number, part: item.part, text, unreadable: text === null, state: st.state, warning: st.warning, sentAt: item.sentAt };
        out.push(a);
        if (st.state === "applied" || st.state === "refused") { settled.push(item.answerId); s.settled.set(item.answerId, a); }
      }
      if (settled.length) await store.update(OUTBOX + id, (x) => ({ v: 1, items: ((x && x.items) || []).filter((i) => settled.indexOf(i.answerId) < 0) }));
      for (const [answerId, a] of s.settled) if (!out.some((x) => x.answerId === answerId)) out.push(a);
      return out;
    },

    // Send again what the PC has not confirmed and is due (relay/js/protocol.js, answerState): a missing
    // answer as a NEW envelope signed by the passkey, one lost at the end of the stream as the same
    // envelope put again. Each at most once per ANSWER_RESEND_MS, whether it went or not. { resent,
    // problems }: how many went, and the phone's own words for each that did not. Needs an unlocked
    // session; one that cannot sign sends again only what needs no new signature.
    // sign: false sends again only what needs no new signature (the page is hidden, or another window
    // of the app holds the lock: bridge.js). AT MOST ONE ANSWER IS SIGNED AGAIN A CALL (review of PR 262,
    // S4): one passkey prompt a refresh, never a train of them; the rest wait for the next.
    async resend(id, { sign = true } = {}) {
      const e = await entryOf(id);
      const s = sessions.get(id);
      if (!s) throw fail("This horde is locked.", "locked");
      const receipt = s.view ? P.receiptFor(s.view.receipts, e.deviceKeyId) : null;
      let resent = 0;
      let signed = 0;
      let cannot = 0;
      const problems = [];
      const items = await outboxOf(id);
      for (const item of items) {
        const st = answerStateOf(s, item, receipt, now());
        if (!st.due) continue;
        // NEVER AN ANSWER THAT IS NOT HIS LATEST to its question and part (review of PR 262, M2).
        if (items.some((i) => i !== item && slotOf(i.number, i.part) === slotOf(item.number, item.part) && Number(i.signedAt || i.sentAt) > Number(item.signedAt || item.sentAt))) continue;
        if (st.resend === "resign" && s.mode !== "passkey") { cannot += 1; continue; }
        if (st.resend === "resign" && (!sign || signed >= 1)) continue;
        if (st.resend === "resign") signed += 1;
        // THE RATE LIMIT IS WRITTEN FIRST: a send that fails, or a page closed half way, is not tried
        // again before the interval is out.
        await store.update(OUTBOX + id, (x) => ({ v: 1, items: ((x && x.items) || []).map((i) => (i.answerId === item.answerId ? { ...i, lastResendAt: now() } : i)) }));
        const again = "The answer to question " + item.number + " could not be sent again just now; it will be tried again.";
        try {
          if (st.resend === "reput") {
            const put = await relay.put(e.machineMailbox, item.envelope.key, item.envelope.text);
            if (put.state !== "known") { diagnostics.push(relaySaid(put.reason)); problems.push(again); continue; }
            resent += 1;
            continue;
          }
          const text = await openKept(s, item);
          if (text === null) { problems.push("The answer to question " + item.number + " cannot be read back on this phone, so it cannot be sent again. Answer it again."); continue; }
          const body = P.answerBody({ answerId: item.answerId, machine: e.machine, snapshot: item.snapshot, number: item.number, wordingVersion: item.wordingVersion, text, part: item.part });
          // Signed under the time he FIRST sent it: an older answer stays the older one at the PC.
          const env = await sealAndSign(e, "answer", "decisions", body, assertWith(e), Number(item.signedAt || item.sentAt));
          const put = await relay.put(e.machineMailbox, env.key, env.text);
          if (put.state !== "known") { diagnostics.push(relaySaid(put.reason)); problems.push(again); continue; }
          await keepAnswer(id, s, { ...item, text }, env, st.stuck === true);
          resent += 1;
        } catch (x) { problems.push("The answer to question " + item.number + " was not sent again: the passkey did not sign it. It will be tried again."); }
      }
      if (cannot) problems.push("Unlocked by the recovery code, this phone cannot sign: " + cannot + " answer" + (cannot === 1 ? " the PC is missing waits" : "s the PC is missing wait") + " until you unlock with the passkey.");
      return { resent, problems };
    }
  };
}
