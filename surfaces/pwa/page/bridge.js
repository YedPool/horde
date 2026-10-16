// surfaces/pwa/page/bridge.js - the page's side of the bridge, for the phone app (served as
// surface/bridge.js, as every surface serves its own: surfaces/Port.ps1, WHERE A PAGE FINDS A FILE).
//
// THE SAME THREE MEMBERS as the window surface's own page/bridge.js, so the decisions
// document (decisions/page/list.js) and the frame around it are written against one contract:
//   HordeBridge.request(name, args)  ->  a promise of the value; rejected with the reason in words
//   HordeBridge.on(name, fn)             fn(value) each time the event of that name is pushed
//   HordeBridge.live                     true: something is behind the page (here, the phone itself)
// WHAT IS BEHIND IT is not Horde on this machine but the phone's own logic (phone-core.js): the
// window's list and kinds become the newest DECRYPTED SNAPSHOT of the picked horde, and say becomes a
// founder's answer SIGNED WITH THE PASSKEY and put into that machine's relay mailbox. The requests are
// a closed list (REQUESTS below); any other name is refused, as the window's composer refuses it.
//
// REQUESTS
//   setup                 the letters and the parked groups, as the window's composer answers it
//   kinds                 the question kinds (decisions/question-kinds.json, served beside list.js)
//   list                  the picked horde's snapshot as the list operation's answer
//                         { state, value: { outcome, questions, counts, unreadable, notUnderstood } },
//                         and notShown: the one line for what that snapshot leaves out, "" for nothing;
//                         a locked or empty horde answers unknown with the reason
//   say {number, text, wording, id, part}   the answer, signed and sent: { ok, sequence } or { ok: false,
//                         reason }; part, when given, is the letter of the one part of the question the
//                         words answer (the document sends each part by itself: list.js, sayPart)
//   act {number, act, wording, id}    park or unpark: KEPT ON THIS PHONE ONLY for the session (the
//                         decisions channel takes answers, not acts: an open question in the PR)
//   hordes                every horde on this phone, as phone-core's summaries
//   pick {id}             the horde the list shows
//   pair {offer, label}   answer a pairing offer, and send the response through the relay:
//                         { id, fingerprint, response, recoveryCode, prf, pairMailbox, relayed }
//   sendPairing {id}      send that response through the relay again: { relayed }
//   announce {id}         ONE passkey prompt that announces the phone: the pairing screen's Finish pairing
//                         (phone-core.js, THE ANNOUNCEMENT IS NO BUTTON); unlock carries it by itself
//   pairConfirmed {id, waitMs}  has the machine said the founder confirmed this phone: { confirmed }
//   join {horde, machine, label, agent}  this phone asks to join that machine: { request, expiresAt }
//   joinOffer {request, waitMs}  the machine's answer, opened: { offerText, expired } ("" while none)
//   joinRequests          the picked horde's open requests from new phones (never a number)
//   approveJoin {request, number}  rejectJoin {request}  the passkey's approval or reject
//   unlock {id}  recover {id, code}  lock {id}  forget {id}  refresh {}
//   chat                  the picked horde's chat with its Thrall: { state, value: { session, items,
//                         mode } } as phone-core's chat answers it; a locked or empty horde answers
//                         unknown with the reason
//   chat-send {text, id}  one line to the Thrall, signed and sent: { ok } or { ok: false, reason }; id is
//                         the page's id for the words (32 hex), so the same words sent again are one line
//   progress {of}         the picked horde's progress log: { state, value } as phone-core's progress
//                         answers it (the entries in the order they were written, how many are unread,
//                         where he read to, and the area-to-lane map as areas); a locked or empty horde
//                         answers unknown with the reason. of: another pairing of the same horde, whose
//                         log a card of that machine opens (phone-core.js, THE CARDS)
//   cards                 the cards of the picked horde, every unlocked machine of it merged by name:
//                         { state, value } as phone-core's cards answers it
//   progress-read {id}    he has read as far as that entry - or, with all: true, to the newest - kept on
//                         this phone: the same record as progress, with the new count
//   notices               the notices of the picked horde, every unlocked machine of it, newest first,
//                         with read or unread and each machine's follow switches: { state, value } as
//                         phone-core's notices answers it
//   notices-read {ids}    he has read those notices (ids), or with all: true every one: kept on this phone,
//                         the same record as notices
//   follow {entry, lane, on}  the follow switch of a lane of the card of that pairing's machine, signed
//                         with the passkey and sent: { ok } or { ok: false, reason }
//   sessions              the unlocked session of every unlocked horde (phone-core.js, THE UNLOCKED
//                         SESSION): [{ id, horde, machine, open, until, idleMs, keeps, words }];
//                         asking at the moment one's time is up ends it then
//   session-end {why}     end the unlocked session of every unlocked horde, keeping them open to read:
//                         why "away" (the app in the background past its setting) or "closed" (the page
//                         hidden for good); answers the same list as sessions
// EVENTS: list-changed (the list record), chat-changed (the chat record), session-changed (the sessions
// list, after an unlock, a lock, a refresh, a send or an end), progress-changed (the progress
// record), cards-changed (the cards record), notices-changed (the notices record), hordes-changed (the
// summaries), notice (a sentence), read-changed (how the last read of the mailbox went:
// { locked, relayDown, said, lastGoodAt } - said the relay's words, lastGoodAt the time of the last read
// that worked for the picked horde, 0 for none; the page's banner is read-banner.js's).
//
// "SAVED" MEANS SENT AND SIGNED. say answers ok once the relay has taken the signed envelope; the
// machine stores it when its runner next turns, and the next snapshot shows it under the question. The
// sequence handed back is one past the highest message sequence in the snapshot on screen, so the
// document keeps the words as the standing answer until a snapshot that holds them arrives (list.js,
// standingOf). The same words sent again carry the same id, which is the answerId: the machine stores
// them once (channels/decisions, Get-HordeDecisionsChannelAnswerId).
//
// AN ANSWER THE PC HAS NOT APPLIED STANDS ANSWERED (the founder, 2026-10-14): the list handed to the
// document is the snapshot with the answers this phone keeps drawn in (relay/js/protocol.js,
// withAnswers) - his words under the question, local, with what became of them: sent, received by PC,
// applied, refused, and the warning when one waits too long. So a reload, or a snapshot from before
// the answer, never shows the question as an empty slot while his answer is on its way. After every
// refresh the phone sends again what the PC reports missing (phone-core.js, resend), and says in its
// own words what it could not send.
import { withAnswers } from "../relay/protocol.js";

const REQUESTS = ["setup", "kinds", "list", "say", "act", "hordes", "pick", "pair", "sendPairing", "announce", "pairConfirmed", "join", "joinOffer", "joinRequests", "approveJoin", "rejectJoin", "unlock", "recover", "lock", "forget", "refresh", "chat", "chat-send", "progress", "progress-read", "cards", "notices", "notices-read", "follow", "sessions", "session-end"];
// A line's id when the page gave none: 16 random bytes as hex.
function newLineId() { return Array.from(globalThis.crypto.getRandomValues(new Uint8Array(16)), (b) => (b < 16 ? "0" : "") + b.toString(16)).join(""); }
// A local act stays standing: no snapshot carries a later act of his for it (list.js, lastActOf).
const LOCAL_ACT_SEQUENCE = Number.MAX_SAFE_INTEGER;

// The bridge over a phone (phone-core.js). options: { loadKinds() -> promise of the kinds table,
// look: the letters, waitMs: the long-poll of the live refresh (0: none), visible() -> boolean,
// now() -> ms: the clock of lastGoodAt (Date.now) }.
export function createBridge(phone, options = {}) {
  const listeners = Object.create(null);
  let picked = "";
  let view = null;
  let viewError = "";
  let polling = false;
  let lastGoodAt = 0;
  const now = typeof options.now === "function" ? options.now : () => Date.now();
  // The lock one window of the app holds while it sends answers again: options.lock(name, fn), where fn
  // is handed true when the lock is held; by default the browser's navigator.locks, asked not to wait,
  // and with no such thing (the suites under Node) the one window there is holds it.
  function withSendLock(id, fn) {
    if (typeof options.lock === "function") return options.lock("horde-answer-resend-" + id, fn);
    const locks = globalThis.navigator && globalThis.navigator.locks;
    if (locks && typeof locks.request === "function") return locks.request("horde-answer-resend-" + id, { ifAvailable: true }, (lock) => fn(!!lock));
    return fn(true);
  }
  // What became of the answers this phone keeps (phone-core.js, answers), drawn into the list.
  let answers = [];
  async function loadAnswers() {
    if (!picked || locked) { answers = []; return; }
    // A READ THAT FAILS KEEPS WHAT WAS LAST READ (review of PR 262, S3): emptied, every question he
    // answered would show as an empty slot until the next read.
    try { answers = await phone.answers(picked); } catch (e) { /* the answers last read stand */ }
  }
  const look = options.look || { fontFamily: "system-ui, sans-serif", textPx: 16, linePx: 24, smallTextPx: 14, smallLinePx: 20 };

  function emit(name, value) {
    for (const fn of listeners[name] || []) { try { fn(value); } catch (e) { /* one listener's fault must not stop the rest */ } }
  }
  function listRecord() {
    if (!picked) return { state: "unknown", value: null, reason: "No horde is picked: pair this phone with a machine first." };
    if (!view) return { state: "unknown", value: null, reason: viewError || "This horde is locked." };
    // notShown: the one line for what the snapshot on screen leaves out, "" for nothing (phone-core.js).
    // It is a member the document does not read (list.js): the page shows it above the list (app.js).
    return { state: "known", reason: "", value: { outcome: "done", questions: withAnswers(view.questions, answers), notShown: typeof view.notShown === "string" ? view.notShown : "", counts: view.counts || {}, unreadable: new Array(view.unreadable || 0).fill(""), notUnderstood: new Array(view.notUnderstood || 0).fill("") } };
  }
  async function chatRecord() {
    if (!picked) return { state: "unknown", value: null, reason: "No horde is picked: pair this phone with a machine first." };
    try { return { state: "known", reason: "", value: await phone.chat(picked) }; }
    catch (e) { return { state: "unknown", value: null, reason: e && e.message ? e.message : String(e) }; }
  }
  async function progressRecord(read = null, of = "") {
    if (!picked) return { state: "unknown", value: null, reason: "No horde is picked: pair this phone with a machine first." };
    try { return { state: "known", reason: "", value: read ? await read() : await phone.progress(of || picked) }; }
    catch (e) { return { state: "unknown", value: null, reason: e && e.message ? e.message : String(e) }; }
  }
  async function cardsRecord() {
    if (!picked) return { state: "unknown", value: null, reason: "No horde is picked: pair this phone with a machine first." };
    try { return { state: "known", reason: "", value: await phone.cards(picked) }; }
    catch (e) { return { state: "unknown", value: null, reason: e && e.message ? e.message : String(e) }; }
  }
  async function noticesRecord(read = null) {
    if (!picked) return { state: "unknown", value: null, reason: "No horde is picked: pair this phone with a machine first." };
    try { return { state: "known", reason: "", value: read ? await read() : await phone.notices(picked) }; }
    catch (e) { return { state: "unknown", value: null, reason: e && e.message ? e.message : String(e) }; }
  }
  async function hordes() { const h = await phone.hordes(); emit("hordes-changed", h); return h; }
  // The unlocked session of every unlocked horde (sessions, in the header), pushed as session-changed.
  async function sessionsRecord() {
    const out = [];
    for (const h of await phone.hordes()) if (h.unlocked) out.push({ id: h.id, horde: h.horde, machine: h.machine, ...(await phone.session(h.id)) });
    emit("session-changed", out);
    return out;
  }
  let locked = true;
  let relayDown = false;
  async function refresh(waitMs = 0) {
    if (!picked) { view = null; emit("list-changed", listRecord()); return listRecord(); }
    try {
      const r = await phone.refresh(picked, { waitMs });
      locked = false;
      relayDown = r.relayDown === true;
      // Said every time, "" when clean: a notice stands until a refresh comes back without one (read-banner.js, WHY).
      emit("notice", r.anomalies.join(" "));
      // A READ THAT FAILED IS SAID UNTIL ONE WORKS (read-banner.js): the old snapshot below is kept, so the
      // page must be told it is old.
      if (!relayDown) lastGoodAt = now();
      emit("read-changed", { locked: false, relayDown, said: relayDown ? r.diagnostics.slice() : [], lastGoodAt });
      view = r.snapshot ? r : null;
      viewError = r.snapshot ? "" : "No snapshot has come from the machine yet. Once the machine trusts this phone and its runner turns, the questions appear here; if none come, the phone is announced again at its next unlock.";
    } catch (e) {
      view = null; locked = e && e.code === "locked"; relayDown = !locked; viewError = e && e.message ? e.message : String(e);
      emit("read-changed", { locked, relayDown, said: locked ? [] : [viewError], lastGoodAt });
    }
    if (view && !locked) {
      try {
        // A NEW SIGNATURE ONLY WHILE HE CAN SEE THE PAGE, AND FROM ONE WINDOW OF THE APP AT A TIME (review
        // of PR 262, S4): hidden, or another window holding the lock, only what needs no signature goes.
        const shown = !options.visible || options.visible();
        const again = await withSendLock(picked, (held) => phone.resend(picked, { sign: shown && held }));
        if (again.problems.length) emit("notice", again.problems.join(" "));
      } catch (e) { /* the next refresh asks again; the answers stay kept */ }
    }
    await loadAnswers();
    await sessionsRecord();
    const rec = listRecord();
    emit("list-changed", rec);
    emit("chat-changed", await chatRecord());
    emit("progress-changed", await progressRecord());
    emit("cards-changed", await cardsRecord());
    emit("notices-changed", await noticesRecord());
    return rec;
  }
  // The live refresh: one long-poll at a time, for whichever horde is picked, while it is unlocked and
  // the page is visible; a lock or a locked pick ends it, an unlock or a pick starts it again. A relay
  // that cannot be read, or a refresh that failed, is asked again after a pause, not in a busy loop.
  async function poll() {
    if (polling || !options.waitMs) return;
    polling = true;
    const pause = (ms) => new Promise((r) => setTimeout(r, ms));
    try {
      while (picked && !locked) {
        if (options.visible && !options.visible()) { await pause(2000); continue; }
        await refresh(options.waitMs);
        if (relayDown) await pause(5000);
      }
    } finally { polling = false; }
  }
  function highestSequence() {
    let top = 0;
    for (const q of (view && view.questions) || []) for (const m of (q.thread && q.thread.messages) || []) { const n = Number(m.sequence); if (n > top) top = n; }
    return top;
  }

  const handlers = {
    setup: async () => ({ look, foldedGroups: [], findings: [], view: null }),
    kinds: async () => {
      try { return { state: "known", reason: "", value: { kinds: await options.loadKinds() } }; }
      catch (e) { return { state: "unknown", value: null, reason: "the question kinds could not be loaded" }; }
    },
    list: async () => listRecord(),
    say: async (a) => {
      try {
        await phone.answer(picked, { number: Number(a.number), wordingVersion: Number(a.wording), text: String(a.text), answerId: String(a.id), part: typeof a.part === "string" ? a.part : "" });
        // DRAWN AT ONCE: the list with his answer in it, marked sent, before any snapshot comes.
        await loadAnswers();
        emit("list-changed", listRecord());
        await sessionsRecord();
        return { ok: true, sequence: highestSequence() + 1 };
      } catch (e) { return { ok: false, reason: e && e.message ? e.message : String(e) }; }
    },
    act: async () => ({ ok: true, sequence: LOCAL_ACT_SEQUENCE, local: true }),
    hordes: async () => hordes(),
    pick: async (a) => { if (String(a.id || "") !== picked) lastGoodAt = 0; picked = String(a.id || ""); view = null; viewError = ""; const rec = await refresh(); poll(); return rec; },
    pair: async (a) => { const r = await phone.pair({ offerText: String(a.offer || ""), label: String(a.label || ""), joined: a.joined === true }); await hordes(); return r; },
    sendPairing: async (a) => ({ relayed: await phone.sendPairing(String(a.id || "")) }),
    announce: async (a) => { const r = await phone.announce(String(a.id)); await hordes(); return r; },
    // ADD THIS PHONE and A NEW PHONE ASKS TO JOIN (phone-core.js): the new phone's request and the
    // machine's answer; the picked horde's open requests, and its passkey's approval or reject.
    join: async (a) => phone.join({ horde: String(a.horde || ""), machine: String(a.machine || ""), label: String(a.label || ""), agent: String(a.agent || "") }),
    joinOffer: async (a) => phone.joinOffer(String(a.request || ""), { waitMs: Math.max(0, Math.min(Number(a.waitMs) || 0, 25000)) }),
    joinRequests: async () => (picked ? phone.joinRequests(picked) : []),
    approveJoin: async (a) => phone.approveJoin(picked, { request: String(a.request || ""), number: String(a.number || "") }),
    rejectJoin: async (a) => phone.rejectJoin(picked, { request: String(a.request || "") }),
    pairConfirmed: async (a) => phone.pairConfirmed(String(a.id || ""), { waitMs: Math.max(0, Math.min(Number(a.waitMs) || 0, 25000)) }),
    unlock: async (a) => { const r = await phone.unlock(String(a.id)); await hordes(); await sessionsRecord(); if (String(a.id) === picked) { await refresh(); poll(); } return r; },
    recover: async (a) => { const r = await phone.recover(String(a.id), String(a.code || "")); await hordes(); if (String(a.id) === picked) { await refresh(); poll(); } return r; },
    // The summaries are pushed BEFORE the list: a frame that hears list-changed already knows the horde
    // is locked, and draws the locked screen, not an empty list.
    lock: async (a) => { phone.lock(String(a.id)); const h = await hordes(); await sessionsRecord(); if (String(a.id) === picked) { locked = true; view = null; viewError = "This horde is locked."; emit("list-changed", listRecord()); } return h; },
    forget: async (a) => { await phone.forget(String(a.id)); if (String(a.id) === picked) { picked = ""; view = null; emit("list-changed", listRecord()); } return hordes(); },
    refresh: async () => refresh(),
    chat: async () => chatRecord(),
    progress: async (a) => progressRecord(null, typeof a.of === "string" ? a.of : ""),
    cards: async () => cardsRecord(),
    notices: async () => noticesRecord(),
    "notices-read": async (a) => noticesRecord(() => phone.markNoticesRead(picked, a.all === true ? null : (Array.isArray(a.ids) ? a.ids.map(String) : []))),
    follow: async (a) => {
      try { await phone.follow(picked, { entry: String(a.entry || picked), lane: String(a.lane || ""), on: a.on === true }); return { ok: true }; }
      catch (e) { return { ok: false, reason: e && e.message ? e.message : String(e) }; }
    },
    sessions: async () => sessionsRecord(),
    "session-end": async (a) => {
      const why = a.why === "closed" ? "closed" : "away";
      for (const h of await phone.hordes()) if (h.unlocked) phone.endSession(h.id, why);
      return sessionsRecord();
    },
    "progress-read": async (a) => progressRecord(() => phone.markProgressRead(picked, a.all === true ? "" : String(a.id || "-"))),
    "chat-send": async (a) => {
      try {
        const id = /^[0-9a-f]{32}$/.test(String(a.id || "")) ? String(a.id) : newLineId();
        await phone.sendLine(picked, { text: String(a.text || ""), messageId: id });
        emit("chat-changed", await chatRecord());
        await sessionsRecord();
        return { ok: true, id };
      } catch (e) { return { ok: false, reason: e && e.message ? e.message : String(e) }; }
    }
  };

  return {
    request(name, args) {
      if (REQUESTS.indexOf(name) < 0) return Promise.reject(new Error("'" + String(name) + "' is not a request this page may make"));
      return handlers[name](args || {});
    },
    on(name, fn) { (listeners[name] = listeners[name] || []).push(fn); },
    live: true
  };
}

// IN A BROWSER this file puts window.HordeBridge on the page at once, as the window's bridge does; its
// requests wait until the phone behind it is made from the deployment's config (app/config.json: which
// relay transport) and the browser's own passkeys and storage. Under Node (the suites) nothing runs
// here: they call createBridge with a phone of their own.
export function deferredBridge(made) {
  const early = [];
  let real = null;
  made.then((b) => { real = b; for (const [n, f] of early) b.on(n, f); early.length = 0; }, () => {});
  return {
    request(name, args) { return made.then((b) => b.request(name, args)); },
    on(name, fn) { if (real) real.on(name, fn); else early.push([name, fn]); },
    live: true
  };
}
