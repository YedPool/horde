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
//                         { state, value: { outcome, questions, counts, unreadable, notUnderstood } };
//                         a locked or empty horde answers unknown with the reason
//   say {number, text, wording, id}   the answer, signed and sent: { ok, sequence } or { ok: false, reason }
//   act {number, act, wording, id}    park or unpark: KEPT ON THIS PHONE ONLY for the session (the
//                         decisions channel takes answers, not acts: an open question in the PR)
//   hordes                every horde on this phone, as phone-core's summaries
//   pick {id}             the horde the list shows
//   pair {offer, label}   answer a pairing offer: { id, fingerprint, response, recoveryCode, prf }
//   announce {id}  unlock {id}  recover {id, code}  lock {id}  forget {id}  refresh {}
// EVENTS: list-changed (the list record), hordes-changed (the summaries), notice (a sentence).
//
// "SAVED" MEANS SENT AND SIGNED. say answers ok once the relay has taken the signed envelope; the
// machine stores it when its runner next turns, and the next snapshot shows it under the question. The
// sequence handed back is one past the highest message sequence in the snapshot on screen, so the
// document keeps the words as the standing answer until a snapshot that holds them arrives (list.js,
// standingOf). The same words sent again carry the same id, which is the answerId: the machine stores
// them once (channels/decisions, Get-HordeDecisionsChannelAnswerId).
const REQUESTS = ["setup", "kinds", "list", "say", "act", "hordes", "pick", "pair", "announce", "unlock", "recover", "lock", "forget", "refresh"];
// A local act stays standing: no snapshot carries a later act of his for it (list.js, lastActOf).
const LOCAL_ACT_SEQUENCE = Number.MAX_SAFE_INTEGER;

// The bridge over a phone (phone-core.js). options: { loadKinds() -> promise of the kinds table,
// look: the letters, waitMs: the long-poll of the live refresh (0: none), visible() -> boolean }.
export function createBridge(phone, options = {}) {
  const listeners = Object.create(null);
  let picked = "";
  let view = null;
  let viewError = "";
  let polling = false;
  const look = options.look || { fontFamily: "system-ui, sans-serif", textPx: 16, linePx: 24, smallTextPx: 14, smallLinePx: 20 };

  function emit(name, value) {
    for (const fn of listeners[name] || []) { try { fn(value); } catch (e) { /* one listener's fault must not stop the rest */ } }
  }
  function listRecord() {
    if (!picked) return { state: "unknown", value: null, reason: "No horde is picked: pair this phone with a machine first." };
    if (!view) return { state: "unknown", value: null, reason: viewError || "This horde is locked." };
    return { state: "known", reason: "", value: { outcome: "done", questions: view.questions, counts: view.counts || {}, unreadable: new Array(view.unreadable || 0).fill(""), notUnderstood: new Array(view.notUnderstood || 0).fill("") } };
  }
  async function hordes() { const h = await phone.hordes(); emit("hordes-changed", h); return h; }
  let locked = true;
  let relayDown = false;
  async function refresh(waitMs = 0) {
    if (!picked) { view = null; emit("list-changed", listRecord()); return listRecord(); }
    try {
      const r = await phone.refresh(picked, { waitMs });
      locked = false;
      relayDown = r.relayDown === true;
      if (r.anomalies.length) emit("notice", r.anomalies.join(" "));
      view = r.snapshot ? r : null;
      viewError = r.snapshot ? "" : "No snapshot has come from the machine yet. Once the machine trusts this phone and its runner turns, the questions appear here; if none come, announce this phone again.";
    } catch (e) { view = null; locked = e && e.code === "locked"; relayDown = !locked; viewError = e && e.message ? e.message : String(e); }
    const rec = listRecord();
    emit("list-changed", rec);
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
        await phone.answer(picked, { number: Number(a.number), wordingVersion: Number(a.wording), text: String(a.text), answerId: String(a.id) });
        return { ok: true, sequence: highestSequence() + 1 };
      } catch (e) { return { ok: false, reason: e && e.message ? e.message : String(e) }; }
    },
    act: async () => ({ ok: true, sequence: LOCAL_ACT_SEQUENCE, local: true }),
    hordes: async () => hordes(),
    pick: async (a) => { picked = String(a.id || ""); view = null; viewError = ""; const rec = await refresh(); poll(); return rec; },
    pair: async (a) => { const r = await phone.pair({ offerText: String(a.offer || ""), label: String(a.label || "") }); await hordes(); return r; },
    announce: async (a) => { const r = await phone.announce(String(a.id)); await hordes(); return r; },
    unlock: async (a) => { const r = await phone.unlock(String(a.id)); await hordes(); if (String(a.id) === picked) { await refresh(); poll(); } return r; },
    recover: async (a) => { const r = await phone.recover(String(a.id), String(a.code || "")); await hordes(); if (String(a.id) === picked) { await refresh(); poll(); } return r; },
    // The summaries are pushed BEFORE the list: a frame that hears list-changed already knows the horde
    // is locked, and draws the locked screen, not an empty list.
    lock: async (a) => { phone.lock(String(a.id)); const h = await hordes(); if (String(a.id) === picked) { locked = true; view = null; viewError = "This horde is locked."; emit("list-changed", listRecord()); } return h; },
    forget: async (a) => { await phone.forget(String(a.id)); if (String(a.id) === picked) { picked = ""; view = null; emit("list-changed", listRecord()); } return hordes(); },
    refresh: async () => refresh()
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
