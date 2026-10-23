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
// THE ANNOUNCEMENT IS NO BUTTON (the founder, 2026-10-14: "that piece should happen automatically on
// login - I don't see why I should press a button"). AN IPHONE STARTS A PASSKEY PROMPT ONLY FROM A TAP,
// ONE PROMPT A TAP, so it cannot be silent; it can be one prompt the founder meets anyway:
//   1. after pairing, the phone watches the offer's pairing mailbox for the machine's CONFIRMED RECORD
//      (relay/Pairing.ps1: signed by the machine, so the relay cannot fake it), and while he is still on
//      the pairing screen it offers "Finish pairing" - that one tap IS the Face ID prompt, not a step
//      before it (pairConfirmed, then announce);
//   2. otherwise the announcement rides the NEXT passkey prompt the phone shows anyway: the unlock. While
//      the machine has not answered this phone (not heard), the unlock's PRF get() is asked over the
//      vouch's own challenge, so the one Face ID that unlocks also vouches, and the vouch is put
//      (unlock);
//   3. a machine that has not confirmed the passkey yet refuses the vouch (relay/Trust.ps1); the phone
//      tries again only at its next unlock - never a prompt in a loop, never a prompt by itself.
// ONE ASSERTION, NEVER NONE: the vouch is the passkey's signature (user verification) over
// SHA-256("horde-relay/phone-key/v1 vouch" LF horde LF key), sent as the PHONE VOUCH ITEM
// (relay/js/protocol.js, phoneVouchText). It needs no envelope around it: it is public, it verifies by
// itself under the trusted passkey, and a second copy is the same record (relay/Trust.ps1, THE VOUCH
// TRAVELS BY ITSELF, says why one assertion cannot be both the envelope's signature and the vouch).
//
// ADD THIS PHONE (phone-started pairing; relay/Join.ps1 has the protocol, design-phone-started-pairing.md
// its threats). A phone signed in to the account asks to join one machine of it (join): a request with a
// fresh request key, which trusts nothing. The machine answers at once with a pairing offer sealed to that
// key (joinOffer opens it); the founder taps once more and this phone pairs with it exactly as with a
// scanned offer (pair: the passkey prompt needs that tap), and shows the 12-digit number. He types it on a
// TRUSTED device - the PC, or a trusted phone (below) - which compares it with its own; only then is this
// passkey trusted, and the confirmed record brings Finish pairing. A request is never sent twice by itself.
//
// A NEW PHONE ASKS TO JOIN, on a TRUSTED phone: the machine sends the transcript (channel join, kind
// request) sealed to the trusted phones. joinRequests lists the open ones - who, browser, country, time,
// never a number. approveJoin takes the number the founder typed from the new phone, computes the number
// from the transcript ITSELF and compares; only on a match does the passkey sign (user verification) an
// approval of the request, the device and the transcript's hash - the number never leaves this phone.
// rejectJoin signs a reject the same way. A recovery or read-only session does neither.
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
//
// THE UNLOCKED SESSION: ONE PASSKEY PROMPT PER UNLOCK, NOT PER ANSWER (design note "Unlocked session",
// 2026-10-14; the wire is relay/Session.ps1, and relay/js/protocol.js holds its functions, used here and
// never copied). The founder had to give his passkey for every answer. Now the passkey UNLOCK makes a
// SESSION KEY (ECDSA P-256, extractable false) that lives in this object's memory only - never in the
// store, never sent - and the unlock's ONE assertion is the vouch for it: its challenge is the vouch's
// hash (P.openSession). Answers, changes of rank, chat lines and photo manifests (SESSION_SIGNED) are then signed by that
// key with no prompt; everything else (the announcement, a follow switch) is the passkey's as before.
//   WHEN THE KEY IS USED. Only toward a PC that says it keeps sessions: the snapshot's receipt for this
//     passkey carries a session member (P.sessionStatus). A PC from before sessions refuses every session
//     envelope, so with no status the phone signs each envelope with the passkey, as before, and says
//     once that the PC needs an update. A question flagged needsPasskey is ALWAYS answered with a fresh
//     passkey assertion, whatever the session. An envelope signed again under the time he first sent it
//     (A STALE ANSWER NEVER WINS) is the passkey's when that time is before the session began, because
//     the PC takes a session envelope only inside the vouch's window.
//   THE VOUCH TRAVELS until the PC lists it: on every session envelope while the PC's status does not
//     name it, or names it session-unknown, so no envelope waits on another to arrive first. Right after
//     the first snapshot that shows the PC keeps sessions, one opening envelope (channel trust, kind
//     session) carries it on its own, so the PC's idle clock starts with the unlock.
//   THE KEY IS DROPPED - the variable cleared, the PC's word not waited for - on: idle (the PC's limit,
//     idleMs in its status, 60 minutes until it says; measured from the key's last signature here, which
//     is before the PC sees it, so the phone always ends first); the PC naming the vouch expired, idle,
//     ended, stale or refused; endSession() (the page: away from the app, or the page hidden for good);
//     lock() (which the page does hidden no sooner than the away time, the founder's Q75 (c): app.js and
//     surfaces/pwa/Site.ps1); and the page closing, which takes this object with it. After every
//     end but those two the horde stays open to READ: the next answer then asks for the passkey ONCE, to
//     vouch for a new key, and goes signed by it.
//   NO LENGTH OF ITS OWN (C, 2026-10-15): the phone keeps no second copy of any session-length limit.
//     notAfter is what relay/js/protocol.js's openSession writes into the vouch; whether a session is past
//     it is the PC's to say (session-expired), and the phone ends it then, on the PC's word.
//   A REFUSAL IS ANSWERED BY THE PASSKEY. An answer the PC lists as needs-passkey, or one sent under a
//     vouch it has refused, is signed again with a fresh passkey assertion by resend() (one a call, as
//     every re-sign is), and is never taken for refused meanwhile.
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
const PASSKEY_DID_NOT_SIGN = "The passkey did not sign (the prompt was cancelled, or it timed out), so the phone was not announced. Tap Finish pairing again, or unlock later: the phone announces itself at its next unlock.";
function passkeyDidNotSign(x) {
  const name = x && typeof x.name === "string" && /^[A-Za-z]{1,40}$/.test(x.name) ? x.name : "";
  return PASSKEY_DID_NOT_SIGN + (name && name !== "Error" ? " (" + name + ")" : "");
}

// THE UNLOCKED SESSION (the header): what the session key signs, by "<channel> <kind>"; the vouch states
// that end a session (relay/js/protocol.js, SESSION_REFUSALS); and the words for each way one ends.
// A change of rank goes in session too (channels/decisions/Channel.ps1, A SESSION-SIGNED RANK, 2026-10-14).
const SESSION_SIGNED = ["decisions answer", "decisions rank", "chat line", "chat photo", "chat answer"];
const SESSION_DEAD = ["session-expired", "session-idle", "session-ended", "session-stale", "session-refused"];
const AGAIN = " The next answer asks for your passkey once, to open a new one.";
const SESSION_ENDED = {
  "session-expired": "Your PC says the unlocked session has expired." + AGAIN,
  "session-idle": "The unlocked session ended: it was not used for as long as your PC allows." + AGAIN,
  "session-ended": "Your PC ended this phone's unlocked session (every phone session was ended there, or this phone is no longer trusted)." + AGAIN,
  "session-stale": "Your PC did not take this phone's unlocked session: a newer one was opened." + AGAIN,
  "session-refused": "Your PC refused this phone's unlocked session." + AGAIN,
  away: "The unlocked session ended because the app was in the background too long." + AGAIN,
  closed: "The unlocked session ended with the page." + AGAIN
};
const OLD_PC = "Your PC needs an update to stop asking for the passkey on each answer: until it has one, each answer, chat line and photo asks.";

function originHost(origin) { const m = /^[a-z]+:\/\/([^:/]+)(:[0-9]+)?$/.exec(origin || ""); return m ? m[1] : ""; }

// THE PACE OF A PHOTO'S PUTS (sendPhoto): 18 at once leaves two of the relay's burst of 20 for a line or an
// answer sent beside it; then one each 1.1 s, a little slower than the relay's one a second refills.
const PHOTO_BURST = 18;
const PHOTO_PACE_MS = 1100;

export function createPhone({ store, authenticator, relay, account = null, origin, now = () => Date.now(), sleep = (ms) => new Promise((ok) => setTimeout(ok, ms)) }) {
  const sessions = new Map();
  // Sealed pairing responses not yet known to have arrived, by horde id (THE PAIRING RESPONSE...).
  const pairings = new Map();
  // This phone's own join requests (ADD THIS PHONE, in the header), by request id: the request key that
  // opens the machine's answer. In memory only: a page closed loses it, and he taps Add this phone again.
  const joining = new Map();
  // The relay's own words from puts, kept for the next refresh's diagnostics (THE RELAY'S WORDS).
  const diagnostics = [];
  const newSession = (privateKey, publicPoint, mode, pkcs8) => ({ privateKey, publicPoint, mode, pkcs8, pages: [], cursor: 0, seen: new Map(), view: null, chat: newChat(), progress: newProgress(), cards: null, cardsRefused: "", cardsUnpaired: false, notices: newNotices(), outboxText: new Map(), settled: new Map(), joins: new Map(), signer: null, sessionWords: "", oldPcSaid: false });
  const newChat = () => ({ turns: [], receipts: [], sent: [], session: "", sessionSeq: -1, ids: new Set(), photos: [], photoReceipts: [], photoBytes: 0, photoWindowMs: 0, answeredNow: [], itemSent: [], itemReceipts: [] });
  const newProgress = () => ({ entries: [], notices: [], ids: new Set() });
  const newNotices = () => ({ byId: new Map(), keys: new Set(), follows: {}, followsSeq: -1 });
  const fail = (reason, code = "refused") => { const e = new Error(reason); e.code = code; return e; };

  // The photos this phone has put at a machine and heard nothing of: the stored list and this session's, by id.
  function waitingOf(e, s) {
    const byId = new Map();
    // A stored entry that is not a photo id with a whole-number expiry is dropped, not counted for ever.
    for (const w of (e.photosWaiting || [])) { if (w && typeof w.photoId === "string" && /^[0-9a-f]{32}$/.test(w.photoId) && Number.isSafeInteger(w.expiresAt)) byId.set(w.photoId, { photoId: w.photoId, expiresAt: w.expiresAt }); }
    for (const p of s.chat.photos) byId.set(p.photoId, p);
    return [...byId.values()];
  }
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
  // sign(parts) -> the envelope's wire text; it runs again under the next seq if another tab took this one.
  // body may be a function of (seq, ts): a photo's manifest names its own envelope's seq (sendPhoto).
  async function sealWith(e, kind, channel, body, sign, ts = null) {
    for (let tries = 0; tries < 3; tries++) {
      const held = await store.get(ENTRY + e.id);
      if (!held) throw fail("there is no such horde on this phone");
      const seq = ((held.seq && held.seq[channel]) || 0) + 1;
      const at = ts === null ? now() : ts;
      const parts = await P.sealEnvelope({ kind, channel, from: e.deviceKeyId, seq, ts: at, recipientPublic: P.unb64u(e.machineAgreePublic), body: typeof body === "function" ? body(seq, at) : body });
      const signed = await sign(parts);
      if (await claimSeq(e.id, channel, seq)) return { text: signed.text, vouchId: signed.vouchId, key: P.replayKey(parts.header), ts: parts.header.ts, seq };
    }
    throw fail("Another window of this app sent at the same moment, three times over: nothing was sent. Send it again.");
  }
  // An envelope signed by the session key when THE UNLOCKED SESSION (the header) allows it, else by the
  // passkey through assert, as every envelope was before. passkey: true asks for the passkey whatever
  // the session (a question flagged needsPasskey, an answer the PC refused under a session).
  async function sealAndSign(e, kind, channel, body, assert, ts = null, { passkey = false } = {}) {
    const s = sessions.get(e.id);
    const byPasskey = async (parts) => ({ text: await P.signEnvelope(parts, assert), vouchId: "" });
    if (passkey || !s || s.mode !== "passkey" || SESSION_SIGNED.indexOf(channel + " " + kind) < 0) return sealWith(e, kind, channel, body, byPasskey, ts);
    const status = statusOf(e, s);
    if (!status) {
      // AN OLDER PC (or none heard yet): the passkey each time, and said once while a session is open.
      if (s.signer && s.view && !s.oldPcSaid) { s.oldPcSaid = true; s.sessionWords = OLD_PC; }
      return sealWith(e, kind, channel, body, byPasskey, ts);
    }
    let k = liveSigner(e, s, status);
    // Signed again under its first time, before any session of now began: the passkey's (the header).
    if (ts !== null && (!k || ts < k.notBefore)) return sealWith(e, kind, channel, body, byPasskey, ts);
    // The key was dropped: ONE prompt vouches for a new one, and this envelope goes signed by it.
    if (!k) k = await openSigner(e, s, false);
    const env = await sealWith(e, kind, channel, body, async (parts) => ({ text: await P.signSessionEnvelope(parts, k, vouchTravels(status, k)), vouchId: k.vouchId }), ts);
    k.lastUsedAt = now();
    return env;
  }

  // --- THE UNLOCKED SESSION (the header) ---
  // What the PC says of this passkey's sessions in the snapshot on screen, or null (an older PC, or none yet).
  function statusOf(e, s) { return s && s.view ? P.sessionStatus(s.view.receipts, e.deviceKeyId) : null; }
  // The vouch rides along until the PC names it, and again once it says it holds no such vouch.
  function vouchTravels(status, k) { return !status.vouches.has(k.vouchId) || status.vouches.get(k.vouchId) === "session-unknown"; }
  function idleOf(status) { return status ? status.idleMs : P.SESSION_IDLE_DEFAULT_MS; }
  // Drop the key, with the words for why (SESSION_ENDED). The variable is cleared; nothing else held it.
  function dropSigner(s, why) {
    if (!s || !s.signer) return;
    s.signer = null;
    s.sessionWords = SESSION_ENDED[why] || SESSION_ENDED["session-ended"];
  }
  // The key, if it may sign now; else null, and it is dropped for the reason the clock or the PC gives.
  function liveSigner(e, s, status = statusOf(e, s)) {
    const k = s && s.signer;
    if (!k) return null;
    const t = now();
    if (t - k.lastUsedAt >= idleOf(status)) { dropSigner(s, "session-idle"); return null; }
    const said = status ? status.vouches.get(k.vouchId) : undefined;
    if (said && SESSION_DEAD.indexOf(said) >= 0) { dropSigner(s, said); return null; }
    return k;
  }
  // The device's next vouch seq, taken before the prompt: a prompt cancelled leaves a number unused,
  // which costs nothing - the PC asks only that each new vouch be above the last (session-stale).
  async function nextVouchSeq(id) {
    let seq = 0;
    await store.update(ENTRY + id, (x) => {
      if (!x) throw fail("there is no such horde on this phone");
      seq = (Number.isSafeInteger(x.vouchSeq) ? x.vouchSeq : 0) + 1;
      return { ...x, vouchSeq: seq };
    });
    return seq;
  }
  // A new session key and the ONE passkey assertion that vouches for it (P.openSession), with PRF when
  // it is the unlock's. { signer, got }: got is the assertion, for its PRF output.
  async function newSigner(e, prf) {
    const seq = await nextVouchSeq(e.id);
    let got = null;
    const assert = async (challenge) => { got = await authenticator.get({ rpId: e.rpId, credentialId: P.unb64u(e.credentialId), challenge, prfInput: prf ? prfInput(e.horde, e.machine) : null }); return got; };
    const opened = await P.openSession({ assert, deviceKeyId: e.deviceKeyId, phoneKeyId: e.phoneKeyId, horde: e.horde, machine: e.machine, now: now(), seq });
    return { signer: { ...opened, lastUsedAt: now(), opened: false }, got };
  }
  // A key dropped while the horde stays open: one prompt, a new key, kept on the session.
  async function openSigner(e, s, prf) {
    let made;
    try { made = await newSigner(e, prf); } catch (x) { throw fail("Not sent: the passkey did not sign (the prompt was cancelled, or it timed out). Send it again and confirm with your passkey.", "passkey"); }
    s.signer = made.signer;
    s.sessionWords = "";
    return made.signer;
  }
  // The opening envelope, once a snapshot shows the PC keeps sessions and does not name this vouch yet.
  async function sendOpening(e, s, status) {
    const k = liveSigner(e, s, status);
    if (!k || k.opened || status.vouches.has(k.vouchId)) return;
    k.opened = true;
    try {
      const env = await sealWith(e, "session", "trust", P.sessionOpenBody(k.vouchId), async (parts) => ({ text: await P.signSessionEnvelope(parts, k, true), vouchId: k.vouchId }));
      const put = await relay.put(e.machineMailbox, env.key, env.text);
      if (put.state !== "known") { diagnostics.push(relaySaid(put.reason)); k.opened = false; return; }
      k.lastUsedAt = now();
    } catch (x) { k.opened = false; }
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
      // What the newest turns body says of photos is what the machine takes now (THE PHOTOS, sendPhoto).
      if (h.seq > c.sessionSeq) { c.session = r.value.session; c.sessionSeq = h.seq; c.photoBytes = r.value.photoBytes; c.photoWindowMs = r.value.photoWindowMs; }
    } else if (h.kind === "receipt") {
      const r = P.readChatReceipt(opened.body, e.horde, e.machine);
      if (!r.ok) { anomalies.push("item " + item.seq + ": " + r.reason); return; }
      c.receipts.push({ ...r.value, seq: h.seq, ts: h.ts });
    } else if (h.kind === "answer-receipt") {
      // The receipt of an answer to an item of a published list (channels/chat/Answer.ps1): shown under that item (itemAnswers), never in the chat.
      const r = P.readItemAnswerReceipt(opened.body, e.horde, e.machine);
      if (!r.ok) { anomalies.push("item " + item.seq + ": " + r.reason); return; }
      c.itemReceipts.push({ ...r.value, seq: h.seq, ts: h.ts });
    } else if (h.kind === "photo-receipt") {
      const r = P.readPhotoReceipt(opened.body, e.horde, e.machine);
      if (!r.ok) { anomalies.push("item " + item.seq + ": " + r.reason); return; }
      c.photoReceipts.push({ ...r.value, seq: h.seq, ts: h.ts });
      // A word from the machine ends the wait for good: the stored list forgets it (refresh), so a mailbox that later trims the receipt does not hand the place back.
      c.answeredNow.push(r.value.photoId);
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
  // One opened join envelope (A NEW PHONE ASKS TO JOIN, in the header): a transcript to approve, or the
  // word that a request ended. In memory only, like the rest of what a session opens.
  function takeJoin(e, s, opened, item, anomalies) {
    const h = opened.header;
    if (h.kind === "request") {
      const r = P.readJoinTranscript(P.fromUtf8(opened.body), e.horde, e.machine);
      if (!r.ok) { anomalies.push("item " + item.seq + ": " + r.reason); return; }
      const was = s.joins.get(r.value.request);
      if (!was || !was.closed) s.joins.set(r.value.request, { transcript: r.value, closed: "" });
    } else if (h.kind === "closed") {
      let b = null;
      try { b = JSON.parse(P.fromUtf8(opened.body)); } catch (x) { b = null; }
      if (!b || typeof b.request !== "string" || !/^[0-9a-f]{32}$/.test(b.request) || typeof b.outcome !== "string") { anomalies.push("item " + item.seq + ": a join request's end that does not hold together"); return; }
      const was = s.joins.get(b.request);
      s.joins.set(b.request, { transcript: was ? was.transcript : null, closed: b.outcome.slice(0, 16) });
    }
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

  // Put the vouch a passkey assertion just made (THE ANNOUNCEMENT IS NO BUTTON) into the machine's
  // mailbox as the phone vouch item, and mark the horde announced. { key, agreeKeyId }, or null when the
  // relay did not take it (what it said goes to diagnostics).
  async function putVouch(e, vouch) {
    const text = P.phoneVouchText({ horde: e.horde, by: e.deviceKeyId, agreePublic: P.unb64u(e.phonePublic), vouch });
    const key = P.phoneVouchKey(e.deviceKeyId, e.phoneKeyId);
    const put = await relay.put(e.machineMailbox, key, text);
    if (put.state !== "known") { diagnostics.push(relaySaid(put.reason)); return null; }
    await store.update(ENTRY + e.id, (x) => ({ ...x, announced: { key, at: now() } }));
    pairings.delete(e.id);
    return { key, agreeKeyId: e.phoneKeyId };
  }

  // THE OUTBOX (the header). Its record: { v: 1, items: [{ answerId, number, part, wordingVersion,
  // snapshot, sealed: { enc, box }, seqs, envelope: { key, text }, sentAt, lastSentAt, lastResendAt }] }.
  function slotOf(number, part) { return String(number) + ":" + (part || ""); }
  async function outboxOf(id) {
    const x = await store.get(OUTBOX + id);
    return x && Array.isArray(x.items) ? x.items : [];
  }
  // A REFUSAL IS ANSWERED BY THE PASSKEY (the header): an answer the PC lists as needs-passkey, or whose
  // newest envelope stands under a vouch the PC names dead, is signed again by the passkey - due at once
  // the first time, then once in ANSWER_RESEND_MS as every resend (a prompt he cancelled is not asked
  // again every refresh) - and never settled as refused while it waits. Once re-signed its vouchId is
  // "", and the rule is done.
  function answerStateOf(s, item, receipt, at, e = null) {
    const st = P.answerState(item, receipt, s.view ? s.view.ts : 0, at);
    const status = e && st.state !== "applied" ? statusOf(e, s) : null;
    if (!status) return st;
    const listed = status.needsPasskey.has(item.answerId);
    const dead = !!item.vouchId && SESSION_DEAD.indexOf(status.vouches.get(item.vouchId)) >= 0;
    if (!listed && !dead) return st;
    const waiting = { ...st, state: st.state === "refused" ? "sent" : st.state };
    // Signed again by the passkey already (its vouchId is ""): it waits for the PC's word on that envelope.
    if (!item.vouchId) return waiting;
    return { ...waiting, resend: "resign", due: at - (Number(item.lastResendAt) || 0) >= P.ANSWER_RESEND_MS, owed: true };
  }
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
      // vouchId: the session its newest envelope was signed under, "" for the passkey (THE UNLOCKED
      // SESSION, A REFUSAL IS ANSWERED BY THE PASSKEY) - an id, never a key.
      if (i >= 0) items[i] = { ...items[i], seqs: items[i].seqs.concat([env.seq]), envelope: { key: env.key, text: env.text }, lastSentAt: at, stuckResent: items[i].stuckResent === true || stuck, vouchId: env.vouchId || "" };
      else items.push({ answerId: a.answerId, number: a.number, part: a.part || "", wordingVersion: a.wordingVersion, snapshot: a.snapshot, sealed: { enc: P.b64u(sealed.enc), box: P.b64u(sealed.sealed) }, seqs: [env.seq], envelope: { key: env.key, text: env.text }, signedAt: env.ts, sentAt: at, lastSentAt: at, lastResendAt: 0, vouchId: env.vouchId || "" });
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
    // joined: the offer is a join request's answer (ADD THIS PHONE): its machine is on the account already,
    // so no registration is asked - nothing between the tap and the passkey prompt but local work.
    async pair({ offerText, label, joined = false }) {
      const read = await P.readOffer(offerText, now());
      if (!read.ok) throw fail(read.reason);
      const o = read.value;
      if (o.origins.indexOf(origin) < 0) throw fail("this offer is for " + o.origins.join(", ") + ", not this app at " + origin + ": open the app the offer names");
      const host = originHost(origin);
      if (host !== o.rpId && !host.endsWith("." + o.rpId)) throw fail("this app at " + origin + " cannot make passkeys for " + o.rpId);
      if (!P.validLabel(label)) throw fail("name this phone in 1 to 64 plain characters, with no quote or backslash");
      for (const e of await store.list(ENTRY)) { if (e.horde === o.horde && e.machine === o.machine) throw fail("this phone is already paired with that machine of " + o.horde + "; forget that pairing first"); }
      if (account && !joined) {
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
        seq: {}, announced: null, lastSnapshotSeq: -1, pairedAt: now(),
        // Where the machine's confirmed record comes (THE ANNOUNCEMENT IS NO BUTTON): public ids only.
        offer: o.offer, pairMailbox: o.pairMailbox, deviceId: await P.deviceIdOf(made.rawId)
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

    // Announce this horde's phone identity key to the machine (THE ANNOUNCEMENT IS NO BUTTON, in the
    // header): ONE passkey assertion, the vouch, which also asks for PRF, put as the phone vouch item.
    // For the pairing screen's one "Finish pairing" tap, once the machine said it is confirmed
    // (pairConfirmed); the unlock carries the same vouch by itself. { key, agreeKeyId }.
    async announce(id) {
      let e = await entryOf(id);
      const s = sessions.get(id);
      if (s && s.mode === "recovery") throw fail("unlocked with the recovery code, this phone reads only: unlock with the passkey to announce it");
      let vouch;
      try { vouch = await assertWith(e, true)(await P.vouchChallenge(e.horde, P.unb64u(e.phonePublic))); } catch (x) { throw fail(passkeyDidNotSign(x), "passkey"); }
      e = await keepPasskeyWrap(e, s, vouch.prfFirst);
      const put = await putVouch(e, vouch);
      if (!put) throw fail(RELAY_REFUSED + " The phone was not announced; it is announced at its next unlock.");
      return put;
    },

    // Has the machine said the founder confirmed this phone (relay/Pairing.ps1's confirmed record, in the
    // offer's pairing mailbox, signed by the machine)? waitMs > 0 watches for it first. { confirmed }.
    // For the pairing screen only: it shows "Finish pairing" once this is true.
    async pairConfirmed(id, { waitMs = 0 } = {}) {
      const e = await entryOf(id);
      if (!e.pairMailbox || !e.offer || !e.deviceId) return { confirmed: false };
      const p = pairings.get(id) || {};
      const since = Number.isSafeInteger(p.confirmCursor) ? p.confirmCursor : 0;
      const r = waitMs > 0 ? await relay.watch(e.pairMailbox, since, 64, waitMs) : await relay.get(e.pairMailbox, since, 64);
      if (r.state !== "known") { diagnostics.push(relaySaid(r.reason)); return { confirmed: false }; }
      for (const item of r.value.items) {
        if (item.key !== P.pairingConfirmedKey(e.offer)) continue;
        const c = await P.readPairingConfirmed(item.text, { horde: e.horde, offer: e.offer, device: e.deviceId, signPublic: P.unb64u(e.machineSignPublic) });
        if (c.ok) return { confirmed: true };
      }
      if (pairings.has(id)) p.confirmCursor = r.value.next;
      return { confirmed: false };
    },

    // ADD THIS PHONE (the header): ask to join the machine of a horde this phone's account holds. A request
    // only - it trusts nothing and is never sent again by itself. { request, expiresAt }. On a relay with
    // accounts the relay's join route takes it and holds the limits (one pending, so many an hour; its
    // refusal is said in this file's words); on one without, the item goes into the machine's mailbox.
    async join({ horde, machine, label, agent = "" }) {
      if (!P.validLabel(label)) throw fail("name this phone in 1 to 64 plain characters, with no quote or backslash");
      const kind = String(agent || "").replace(/[^\x20\x21\x23-\x5b\x5d-\x7e]/g, "").slice(0, 200);
      const key = await newPhoneKey();
      wipe(key.pkcs8);
      const request = P.hex(P.randomBytes(16));
      const requestKey = P.b64u(key.publicPoint);
      let expiresAt = now() + P.JOIN_TTL_MS;
      if (account) {
        const r = await account.requestJoin({ machine, request, label, agent: kind, requestKey });
        if (r.state !== "known") {
          diagnostics.push(relaySaid(r.reason));
          const words = { "join-pending": "Another phone's request to join is waiting: approve or reject it on a trusted device, or wait for it to expire (10 minutes).", "join-blocked": "A request from this network was rejected: no request is taken from it for an hour.", "rate-limited": "Too many requests to join this hour: try again later." };
          throw fail(words[r.code] || (r.status === 401 ? SIGN_IN_FIRST : "The relay did not take the request to join; nothing was sent. Try again."));
        }
        if (r.value && Number.isSafeInteger(r.value.expiresAt)) expiresAt = r.value.expiresAt;
      } else {
        const text = P.joinRequestText({ request, horde, machine, label, agent: kind, requestKey, country: "", requestedAt: now(), expiresAt });
        const put = await relay.put(horde + "/" + machine, P.joinKey(request), text);
        if (put.state !== "known") { diagnostics.push(relaySaid(put.reason)); throw fail(RELAY_REFUSED + " The request to join was not sent. Try again."); }
      }
      joining.set(request, { horde, machine, label, privateKey: key.privateKey, publicPoint: key.publicPoint, expiresAt, cursor: 0 });
      return { request, expiresAt };
    },

    // The machine's answer to a join request this phone made: the offer, opened with the request key, or
    // "" while none has come (or the request expired). waitMs > 0 watches first. Pair with it (pair()) on
    // the next tap: the passkey prompt needs one.
    async joinOffer(request, { waitMs = 0 } = {}) {
      const j = joining.get(request);
      if (!j) throw fail("this phone holds no such request to join: tap Add this phone again");
      if (now() > j.expiresAt) { joining.delete(request); return { offerText: "", expired: true }; }
      const mb = P.joinReplyMailbox(j.horde, request);
      const r = waitMs > 0 ? await relay.watch(mb, j.cursor, 16, waitMs) : await relay.get(mb, j.cursor, 16);
      if (r.state !== "known") { diagnostics.push(relaySaid(r.reason)); return { offerText: "", expired: false }; }
      for (const item of r.value.items) {
        const text = await P.openJoinOffer(item.text, { request, horde: j.horde, privateKey: j.privateKey, publicPoint: j.publicPoint });
        if (!text) continue;
        const o = await P.readOffer(text, now());
        // The answer must be the machine this phone asked, of the horde it asked: anything else is not it.
        if (!o.ok || o.value.machine !== j.machine || o.value.horde !== j.horde) continue;
        return { offerText: text, expired: false };
      }
      j.cursor = r.value.next;
      return { offerText: "", expired: false };
    },

    // A NEW PHONE ASKS TO JOIN (the header), as this unlocked horde's machine sent it to the trusted phones:
    // [{ request, label, agent, country, requestedAt, expiresAt }] still open. The number is never here:
    // the founder reads it on the new phone and types it in approveJoin.
    async joinRequests(id) {
      await entryOf(id);
      const s = sessions.get(id);
      if (!s) throw fail("This horde is locked.", "locked");
      const out = [];
      for (const [request, j] of s.joins) {
        if (j.closed || !j.transcript || j.transcript.expiresAt < now()) continue;
        const t = j.transcript;
        // THE BROWSER IS THE NEW PHONE'S OWN WORDS (review of PR 301): printable ASCII, cut to 80, and the page
        // says whose they are.
        const agent = String(t.agent || "").replace(/[^\x20-\x7e]/g, "");
        out.push({ request, label: t.label, agent: agent.length > 80 ? agent.slice(0, 77) + "..." : agent, country: t.country, requestedAt: t.requestedAt, expiresAt: t.expiresAt });
      }
      return out;
    },

    // APPROVE A NEW PHONE: number is what the founder typed from the NEW phone's screen. This phone computes
    // the number from the transcript itself and compares; only on a match does its passkey sign the
    // approval - the request, the device and the transcript's hash, never the number. { key }.
    async approveJoin(id, { request, number }) {
      const e = await entryOf(id);
      const s = sessions.get(id);
      if (!s) throw fail("This horde is locked.", "locked");
      if (s.mode !== "passkey") { throw fail(s.mode === "read-only" ? NO_PRF : "Not sent: this horde was unlocked with the recovery code, which cannot sign. Unlock with the passkey to approve a new phone."); }
      const j = s.joins.get(request);
      if (!j || !j.transcript || j.closed) throw fail("That request to join is not open on this phone.");
      if (j.transcript.expiresAt < now()) throw fail("That request to join has expired.");
      const typed = String(number || "").replace(/[ -]/g, "");
      const want = (await P.joinNumber(j.transcript)).replace(/-/g, "");
      if (!/^[0-9]{12}$/.test(typed) || !P.equalBytes(P.utf8(typed), P.utf8(want))) throw fail("That number does not match the new phone's. If the new phone shows another number, it is not the phone that asked: reject it.", "mismatch");
      const body = P.joinApproveBody({ request, device: j.transcript.device, transcript: await P.joinTranscriptHash(j.transcript.text) });
      const env = await sealAndSign(e, "approve", "join", body, assertWith(e));
      const put = await relay.put(e.machineMailbox, env.key, env.text);
      if (put.state !== "known") { diagnostics.push(relaySaid(put.reason)); throw fail("Not sent: " + RELAY_REFUSED + " Approve again."); }
      return { key: env.key };
    },

    // REJECT A NEW PHONE: signed with the passkey like an approval. { key }.
    async rejectJoin(id, { request }) {
      const e = await entryOf(id);
      const s = sessions.get(id);
      if (!s) throw fail("This horde is locked.", "locked");
      if (s.mode !== "passkey") { throw fail(s.mode === "read-only" ? NO_PRF : "Not sent: this horde was unlocked with the recovery code, which cannot sign. Unlock with the passkey to reject a new phone."); }
      if (!/^[0-9a-f]{32}$/.test(String(request || ""))) throw fail("That is not a request to join.");
      const env = await sealAndSign(e, "reject", "join", P.joinRejectBody({ request }), assertWith(e));
      const put = await relay.put(e.machineMailbox, env.key, env.text);
      if (put.state !== "known") { diagnostics.push(relaySaid(put.reason)); throw fail("Not sent: " + RELAY_REFUSED + " Reject again."); }
      return { key: env.key };
    },

    // Unlock with the passkey: its PRF output unwraps the phone key. A passkey that gives none unlocks
    // nothing (the horde is read only, by the recovery code). Still ONE prompt either way. WHILE THE
    // MACHINE HAS NOT ANSWERED THIS PHONE (not heard), it is asked over the vouch's challenge and the vouch
    // is put: one Face ID unlocks and announces (THE ANNOUNCEMENT IS NO BUTTON). A put the relay does not
    // take is said in diagnostics, never thrown: the unlock stands, and the next unlock tries again. No
    // session key then: with no snapshot there is no receipt, so nothing would let it sign, and the first
    // send once the PC keeps sessions vouches for one. ONCE HEARD, the assertion vouches for the session
    // key (THE UNLOCKED SESSION, in the header): its challenge is the vouch's hash, where it was random
    // bytes before - as fresh, since the vouch names a key made a moment ago.
    async unlock(id) {
      let e = await entryOf(id);
      const announcing = !summary(e).heard;
      let signer = null, got;
      if (announcing) got = await authenticator.get({ rpId: e.rpId, credentialId: P.unb64u(e.credentialId), challenge: await P.vouchChallenge(e.horde, P.unb64u(e.phonePublic)), prfInput: prfInput(e.horde, e.machine) });
      else ({ signer, got } = await newSigner(e, true));
      if (!got.prfFirst) throw fail(NO_PRF);
      const s = sessions.get(id);
      if (s && s.pkcs8) { e = await keepPasskeyWrap(e, s, got.prfFirst); s.signer = signer; s.sessionWords = ""; }
      else {
        if (!e.wraps.prf) throw fail("this horde's key is not wrapped under this passkey's PRF yet: unlock with the recovery code once, then with the passkey");
        const opened = await unwrap(e.wraps.prf, got.prfFirst, e.horde, e.phoneKeyId, P.unb64u(e.phonePublic));
        if (!opened.ok) throw fail(opened.reason + ": unlock with the recovery code");
        const fresh = newSession(opened.value.privateKey, opened.value.publicPoint, "passkey", null);
        fresh.signer = signer;
        sessions.set(id, fresh);
      }
      // Only once the passkey has unwrapped the key: the vouch is for a key this phone holds.
      if (announcing) { await putVouch(e, got); e = await entryOf(id); }
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

    lock(id) { const s = sessions.get(id); if (s) { s.signer = null; wipe(s.pkcs8); sessions.delete(id); } },

    // End the unlocked session of a horde and keep it open to read (THE UNLOCKED SESSION, in the header):
    // why is "away" (the app in the background past the setting) or "closed" (the page hidden for good).
    endSession(id, why) { dropSigner(sessions.get(id), why); },

    // The unlocked session of a horde, as the Account screen says it: { open, until, idleMs, keeps,
    // words } - until is when it ends unless used again (the PC's idle limit from its last use); keeps true when the PC says it keeps sessions, false when it says
    // nothing (an older PC: each envelope asks), null before a snapshot. Asking drops a key whose time
    // is up, so the page that asks at that moment ends it at the same moment as the PC.
    async session(id) {
      const e = await entryOf(id);
      const s = sessions.get(id);
      if (!s) return { open: false, until: 0, idleMs: 0, keeps: null, words: "" };
      const status = statusOf(e, s);
      const k = liveSigner(e, s, status);
      const idleMs = idleOf(status);
      // That the PC needs an update is said ONCE (the header): handed out here, then forgotten.
      const words = s.sessionWords;
      if (words === OLD_PC) s.sessionWords = "";
      return { open: !!k, until: k ? k.lastUsedAt + idleMs : 0, idleMs, keeps: s.view ? status !== null : null, words };
    },

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
          if (o.value.header.channel === "join") { takeJoin(e, s, o.value, item, anomalies); continue; }
          if (o.value.header.channel !== "decisions" || o.value.header.kind !== "snapshot") continue;
          const page = P.readSnapshotPage(o.value.body, e.horde, e.machine);
          if (!page.ok) { anomalies.push("item " + item.seq + ": " + page.reason); continue; }
          s.pages.push({ key: o.value.key, seq: o.value.header.seq, relaySeq: item.seq, ts: o.value.header.ts, page: page.value });
        }
        s.cursor = r.value.next;
        if (s.chat.answeredNow.length) {
          const gone = new Set(s.chat.answeredNow.splice(0));
          await store.update(ENTRY + id, (x) => (x && x.photosWaiting ? { ...x, photosWaiting: x.photosWaiting.filter((w) => !gone.has(w.photoId)) } : x));
        }
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
      // THE UNLOCKED SESSION (the header): what the PC now says of it ends it or opens it.
      const status = statusOf(e, s);
      if (liveSigner(e, s, status) && status) await sendOpening(e, s, status);
      const pageKeyByNumber = {};
      if (v) for (const q of v.questions) pageKeyByNumber[q.question.number] = q.pageKey;
      return {
        snapshot: v ? v.snapshot : "", seq: v ? v.seq : -1, questions: v ? v.questions.map((q) => q.question) : [], pageKeyByNumber,
        published: v ? v.published : null,
        itemAnswers: [...P.itemAnswerView({ sent: s.chat.itemSent, receipts: s.chat.itemReceipts })],
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
      return { session: s.chat.session, items: P.chatTimeline(s.chat, now()), mode: s.mode, photoBytes: s.chat.photoBytes };
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

    // THE FOUNDER'S ANSWER TO ONE ITEM OF A PUBLISHED LIST (relay/js/protocol.js, THE FOUNDER'S ANSWER TO AN ITEM; channels/chat/Answer.ps1):
    // signed like a chat line - a passkey session only, bound to the horde and the machine - and put into the machine's mailbox. It names the
    // list's lane and snapshot and the item's place, and only an item of a list this phone holds. The machine finds the Orc that owns the list;
    // the phone never names a recipient. messageId is the page's id for these words: sent again, they are posted once. { key, seq }.
    async answerItem(id, { lane, snapshot, index, text, messageId }) {
      const e = await entryOf(id);
      const s = sessions.get(id);
      if (!s) throw fail("This horde is locked.", "locked");
      if (s.mode === "read-only") { throw fail(NO_PRF); }
      if (s.mode !== "passkey") { throw fail("Read only: this horde was unlocked with the recovery code, which cannot sign. Unlock with the passkey to answer."); }
      if (typeof text !== "string" || !text.trim()) throw fail("There is nothing to send.");
      const lists = s.view && Array.isArray(s.view.published) ? s.view.published : [];
      const list = lists.find((l) => l.lane === lane && l.snapshot === snapshot);
      if (!list || !list.items.some((it) => it.position === index)) throw fail("That item is not in a list this phone holds. Wait for the lists to refresh, then answer it.");
      if (s.chat.itemSent.some((x) => x.messageId === messageId && (x.text !== text || x.snapshot !== snapshot || x.index !== index))) throw fail("These are other words than the answer first sent under this id: send them as a new answer.");
      const body = P.publishedItemAnswerBody({ messageId, horde: e.horde, machine: e.machine, lane, snapshot, index, text });
      const env = await sealAndSign(e, "answer", "chat", body, assertWith(e));
      const put = await relay.put(e.machineMailbox, env.key, env.text);
      if (put.state !== "known") { diagnostics.push(relaySaid(put.reason)); throw fail("Not sent: " + RELAY_REFUSED + " Send it again; the same answer is never delivered twice."); }
      if (!s.chat.itemSent.some((x) => x.messageId === messageId)) s.chat.itemSent.push({ messageId, lane, snapshot, index, text, at: env.ts });
      return { key: env.key, seq: put.value.seq };
    },

    // What the phone holds of the answers to published items: [[key, answers]] from relay/js/protocol.js's itemAnswerView, key "<snapshot>/<position>".
    itemAnswers(id) {
      const s = sessions.get(id);
      if (!s) return [];
      return [...P.itemAnswerView({ sent: s.chat.itemSent, receipts: s.chat.itemReceipts })];
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

    // THE PHOTOS (channels/chat/Photo.ps1; relay/js/protocol.js, ONE PASSKEY TAP A PHOTO): an image the
    // page has already shrunk to a JPEG, sent as ONE passkey-signed manifest - the same single prompt
    // as a line - and its sealed parts. Only to a machine whose newest turns body says it takes photos
    // (photoBytes), and no larger than it says. THE PACE: the hosted relay lets one phone put 20 at once
    // and then one a second (the hosted relay's limits, putBurst and putsPerMinute), so the
    // manifest and the first PHOTO_BURST - 1 parts go at once and the rest a little over a second apart:
    // a 1 MB photo (21 parts) waits about 4 s, the 2 MiB cap (44 parts) about 30 s, and none is refused
    // for its pace. A part the relay does not take is tried again twice, 1.5 s apart.
    // { photoId, parts, puts }.
    async sendPhoto(id, { bytes, photoId, resendOf = "" }) {
      const e = await entryOf(id);
      const s = sessions.get(id);
      if (!s) throw fail("This horde is locked.", "locked");
      if (s.mode !== "passkey") { throw fail(s.mode === "read-only" ? NO_PRF : "Read only: this horde was unlocked with the recovery code, which cannot sign. Unlock with the passkey to send a photo."); }
      if (s.chat.session === "") throw fail("Nothing has come from the Thrall yet, so there is no session to send to. Wait for its turns, then send.");
      if (!s.chat.photoBytes) throw fail(P.PHOTO_PC_OLD);
      if (!/^[0-9a-f]{32}$/.test(photoId)) throw fail("the photo's id is 32 lower-case hex");
      if (!P.sniffImage(bytes)) throw fail(P.PHOTO_NOT_IMAGE);
      if (bytes.length > s.chat.photoBytes) throw fail("This photo is " + bytes.length + " bytes, and the PC takes at most " + s.chat.photoBytes + ".");
      // The count survives a lock, an unlock and a restart: the unanswered set is kept on the stored entry (photosWaiting),
      // not only in this session, so reopening the app does not hand back a fresh three.
      if (P.photosUnanswered(waitingOf(e, s), s.chat.photoReceipts, now()) >= P.PHOTO_MOST_UNANSWERED) throw fail(P.PHOTO_TOO_MANY_UNANSWERED);
      const windowMs = P.photoWindowFor(s.chat.photoWindowMs);
      const sealed = await P.sealPhotoParts(bytes, { from: e.deviceKeyId, photoId });
      const session = s.chat.session;
      const body = (seq, ts) => P.photoManifestBody({ photoId, horde: e.horde, machine: e.machine, mailbox: e.machineMailbox, from: e.deviceKeyId, phoneKey: e.phoneKeyId, seq, session,
        expiresAt: ts + windowMs, bytes: bytes.length, sha256: sealed.sha256, key: sealed.key, parts: sealed.parts.map((p) => p.digest), resendOf });
      const env = await sealAndSign(e, "photo", "chat", body, assertWith(e));
      sealed.key.fill(0);
      const put = await relay.put(e.machineMailbox, env.key, env.text);
      if (put.state !== "known") { diagnostics.push(relaySaid(put.reason)); throw fail("Not sent: " + RELAY_REFUSED + " Send the photo again."); }
      // Kept with the window its manifest names, and marked sent once every part went (THE PHOTO WAITS
      // FOR THE PC: relay/js/protocol.js, photoItems).
      const mine = { photoId, at: env.ts, session, expiresAt: env.ts + windowMs, sent: false };
      s.chat.photos.push(mine);
      await store.update(ENTRY + id, (held) => {
        if (!held) return held;
        const at = now();
        const kept = (held.photosWaiting || []).filter((w) => w && w.photoId !== photoId && w.expiresAt > at);
        return { ...held, photosWaiting: kept.concat([{ photoId, expiresAt: mine.expiresAt }]).slice(-50) };
      });
      let puts = 1;
      for (const p of sealed.parts) {
        if (puts >= PHOTO_BURST) await sleep(PHOTO_PACE_MS);
        let done = false;
        for (let attempt = 0; attempt < 3 && !done; attempt++) {
          if (attempt > 0) await sleep(1500);
          const r = await relay.put(e.machineMailbox, p.key, p.text);
          puts++;
          if (r.state === "known") done = true; else diagnostics.push(relaySaid(r.reason));
        }
        if (!done) throw fail("Not all of the photo went: the relay did not take part " + p.n + " of " + sealed.parts.length + ". Send the photo again.");
      }
      mine.sent = true;
      return { photoId, parts: sealed.parts.length, puts };
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
      // A question flagged needsPasskey is answered with a fresh passkey assertion, whatever the session.
      const env = await sealAndSign(e, "answer", "decisions", body, assertWith(e), null, { passkey: q.question.needsPasskey === true });
      const put = await relay.put(e.machineMailbox, env.key, env.text);
      if (put.state !== "known") { diagnostics.push(relaySaid(put.reason)); throw fail("Not sent: " + RELAY_REFUSED + " Press Enter to try again; the same words are never saved twice."); }
      // KEPT UNTIL APPLIED, by a machine that says what became of its answers (its snapshot has receipts).
      if (Array.isArray(v.receipts)) await keepAnswer(id, s, { answerId, number, part: takesParts ? part : "", wordingVersion, snapshot: q.pageKey, text: words }, env);
      return { key: env.key, seq: put.value.seq };
    },

    // A CHANGE OF RANK of one question of the snapshot on screen - his tap on its Importance or Blocking
    // button (decisions/page/list.js) - SENT LIKE AN ANSWER: only from a passkey session, signed as an
    // answer is (by the unlocked session's key when it may, and always by the passkey on a question
    // flagged needsPasskey), sealed to the machine of the snapshot, bound to it and to the page
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
      const flagged = q.question.needsPasskey === true;
      const env = await sealAndSign(e, "rank", "decisions", body, assertWith(e), null, { passkey: flagged });
      const put = await relay.put(e.machineMailbox, env.key, env.text);
      if (put.state !== "known") { diagnostics.push(relaySaid(put.reason)); throw fail("Not changed: " + RELAY_REFUSED + " Tap it again."); }
      return { key: env.key, seq: put.value.seq };
    },

    // What the PC said of a change of rank, from the receipt in the snapshot on screen: "applied",
    // "refused", "needs-passkey" (signed in session for a question the PC holds as needsPasskey: tap it
    // again, and it goes with the passkey), or "sent" while it has said none. Needs an unlocked session.
    async rankState(id, rankId) {
      const e = await entryOf(id);
      const s = sessions.get(id);
      if (!s) throw fail("This horde is locked.", "locked");
      const receipt = s.view ? P.receiptFor(s.view.receipts, e.deviceKeyId) : null;
      if (receipt && receipt.applied.has(rankId)) return "applied";
      if (receipt && receipt.refused.has(rankId)) return "refused";
      const status = statusOf(e, s);
      if (status && status.needsPasskey.has(rankId)) return "needs-passkey";
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
        const st = answerStateOf(s, item, receipt, at, e);
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
        const st = answerStateOf(s, item, receipt, now(), e);
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
          const env = await sealAndSign(e, "answer", "decisions", body, assertWith(e), Number(item.signedAt || item.sentAt), { passkey: st.owed === true });
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
