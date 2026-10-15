// surfaces/pwa/page/app.js - the phone app's frame: where the phone (phone-core.js) is made from the
// browser's own parts, the bridge is put on the page, and the screens around the decisions document
// are drawn - the bar of hordes, pairing, unlocking, and the row of answering keys.
//
// THE ONE PLACE THAT KNOWS BOTH SIDES, as decisions/window/frame.js is for the window: it makes the
// phone from the deployment's config (config.json: which relay transport), IndexedDB (store.js) and
// the browser's passkeys (webauthn.js), and everything it draws comes through window.HordeBridge
// (bridge.js) by the bridge's closed list of requests.
//
// THE DOCUMENT IS THE WINDOW'S, UNCHANGED: decisions/page/list.js, mounted once per horde in its own
// box, so a horde's drafts and folds are its own and a question 3 of one horde is never another's.
// Its drafts are kept IN MEMORY ONLY (a storage object of this page's, not localStorage): what the
// founder types is about the questions, and nothing about them is ever written to the phone's disk.
//
// THE ANSWERING KEYS, ADAPTED FOR TOUCH. A soft keyboard has Enter and nothing else of the window's
// keys, so the row over it gives the rest: Send (Enter: save and go to the next question), Back
// (Shift+Tab), New line (Shift+Enter), Suggest (Tab: take the grey suggestion), Park (Ctrl+B). Each
// hands the very key to the field that has the caret, as the document's own check does (list.js,
// drive), so a touch does exactly what the key does at the desk. A key is pressed on pointerdown with
// the default prevented, so the field keeps the caret and the keyboard stays up.
//
// ACCOUNTS. A deployment whose relay is this very site has accounts (account-client.js): the app shows
// the sign-in screen until the browser is signed in - the relay's session lives in a cookie no script
// here can read, so the app only asks the relay whether there is one - and an Account screen with the
// machines registered to it, each removable, and Sign out. Pairing registers the machine (phone-core.js).
// A deployment with no accounts shows none of it.
//
// THE CHAT is the horde's second view, a tab beside its questions: the Thrall's turns and the founder's
// lines, as the bridge's chat request answers them, and a composer with the same keys as an answer -
// Enter sends, Shift+Enter or the New line key adds a line - over the soft keyboard. A line goes only
// from a passkey session; read only (recovery, or a passkey without PRF), the composer is shut and says
// why. The log, like the list, is taken off the page when the horde locks.
//
// THE ANNOUNCEMENT MUST NOT GO MISSING UNSEEN (the founder's first live use, 2026-10-11: he paired, the
// announcement never went, and why was nowhere on the screen). The pairing screen says why its announce
// button is shut; a failed announcement says why beside its button, in the phone's own words; and the
// horde's own view, while the machine has sent this phone nothing (the horde not heard from:
// phone-core.js), offers "Announce this phone" - not only the small link on the locked screen. Every
// announcement still waits for the founder's tap and his passkey; none is sent by itself.
//
// THE WAY BETWEEN DECISIONS, CHAT AND PROGRESS stays on screen (the bar is sticky, app.css), and the phone's Back
// goes back between them: each switch is a history entry, and going back to one shows that view again.
// ONE TABLE NAMES THE VIEWS (PANES): a tab, its view, its place in history and its Back all come from it.
//
// THE PROGRESS LOG is the horde's third view (the founder asked for it, 2026-10-12): the fleet's progress
// entries, oldest at the top, in the order they were written, to be read on from wherever he stopped.
// Each shows its time, its title in bold, its text as short paragraphs with their labels (Asked, Happened,
// Means, Next) in bold, and small chips: the area's plain name first, the kind, and the lane and task only
// when the entry names them. EACH STARTS FOLDED to one line, its title and its day and time, and a tap opens
// it to all of that (the founder asked, 2026-10-14; openEntries, below). HIS PLACE IS KEPT ON THIS PHONE (phone-core.js, markProgressRead): the log
// opens under the last entry he read, with a line where the new ones begin and their count on the tab;
// the place moves on as he reads down, entry by entry; Jump to newest and Mark all read stand at the foot
// of the screen always. A correction is shown on the entry it corrects, and in its own place. The log is
// taken off the page when the horde locks, like the list and the chat.
//
// THE PROGRESS TAB OPENS ON CARDS (the founder asked, 2026-10-13): one card per lane and one for the Thrall,
// from every unlocked machine of the horde merged by name (phone-core.js, THE CARDS). A lane's card says
// where it is from and how old its word is, what it is doing now, what it last finished, what it waits on,
// whether it is blocked, and its tasks open and done this week; the Thrall's says the fleet at large. A tap
// on a card opens its STREAM: the progress log of that card's machine, filtered to that lane
// (relay/js/protocol.js, laneStream) - the Thrall's is the whole log - with All cards, and the phone's
// Back, to return. The stream says in plain words that the phone holds only the newest part of the log.
// HIS PLACE MOVES ONLY IN THE WHOLE LOG: a lane's stream skips other lanes' entries, and reading on in it
// must not mark those read unseen. A machine that sends no cards yet (an older one) opens straight on the
// whole log, as before.
//
// THE NOTICES are the horde's fourth view (the founder asked, 2026-10-13 and 14): what a machine decided he
// should be told - a session's `horde notify` line, a new progress entry of a lane he follows, a session
// cut off for the hour - newest first, each with who it is from, when in plain words, and read or unread;
// the count of unread on the tab. EACH CARD ON THE PROGRESS TAB CARRIES A FOLLOW SWITCH in its one slot,
// off by default, showing what the machine holds (followSwitch, below). No buzz yet: that is Web Push,
// later, and it hooks in on the machine (notices/Decide.ps1, Invoke-HordeNoticeHook), not here.
//
// EVERY MESSAGE IN THE CHAT SAYS WHEN IT WAS SAID (the founder asked, 2026-10-12): the short local time
// beside who said it, the day on a line of its own where it changes, the exact time on a tap. The times
// are the turn's own and the line's signed one (relay/js/protocol.js, chatTimeline); what carries none
// shows none.
//
// THE PC OFFLINE BANNER (the founder, 2026-10-14, fix 2 of six): while the app is open and signed in to a
// relay with accounts, it reads the account's answer every PRESENCE_EVERY_MS, and for each machine the
// relay has not heard from for two minutes BY THE RELAY'S OWN CLOCK (account-client.js, presenceOf) the
// sticky bar holds one line, on every screen: "PC <name> offline since <local time>. Your answers are kept
// and will be applied when it is back." It goes by itself at the first read that has the machine heard
// again. A READ THAT FAILS CHANGES NOTHING (review of PR 252): the banner stands as of the last good
// read until a good read changes it. A phone waking from sleep often fails its first fetch, and a dead
// PC's banner vanishing then would read as "the PC is back" - a warning fails toward warning. A machine
// never heard from gets no banner, only "not heard from yet" on the Account screen.
// THE BOX IS NEVER HIDDEN: it is a live region (role=status), and a hidden node is not in the
// accessibility tree, so a line added in the same step it is shown may never be announced. It is
// always there, empty when nothing is offline (app.css: an empty box takes no space); only its lines
// come and go.
//
// EVERY TEXT IS SET AS TEXT (textContent, or a field's value).
import { createPhone } from "./phone-core.js";
import { createBridge, deferredBridge } from "../surface/bridge.js";
import { createRelayClient, transportFromConfig } from "./relay-client.js";
import { accountFromConfig, presenceOf, offlineWords } from "./account-client.js";
import { openStore } from "./store.js";
import { browserAuthenticator } from "./webauthn.js";
import { canScan, scanQr } from "./scan.js";
import { clockTime, exactTime, withDays, dayTime, PROGRESS_WORDS, laneStream, STREAM_LIMIT_WORDS, streamMovesPlace, sniffImage, PHOTO_NOT_IMAGE, PHOTO_PC_OLD } from "../relay/protocol.js";
import { shrinkInBrowser } from "./photo.js";
import { renderLaneCard, THRALL_LANE } from "./lane-card.js";
import { renderDecisionCards } from "./decision-cards.js";
import { renderFollowSwitch, renderNoticeItem, noticeTarget, noticesTabWords } from "./notices-view.js";
import { cardsFallbackLine } from "./cards-why.js";
import { readFailure, readBanner } from "./read-banner.js";
import { reloadDecision, draftsHeld, updateDue, versionWords, UPDATE_READY_WORDS, DRAFTS_KEY } from "./app-update.js";

const $ = (id) => document.getElementById(id);
const LOOK = { fontFamily: "system-ui, sans-serif", textPx: 16, linePx: 24, smallTextPx: 14, smallLinePx: 20 };
const WATCH_MS = 25000;
// relay: what the last refresh said of the relay (bridge.js "notice"), kept until a refresh comes back
// clean; view: why the picked view could not be drawn, the drawing's own; read: read-banner.js's banner.
const notices = { boot: "", relay: "", read: "", view: "", action: "", update: "" };

function showNotices() {
  const box = $("notice");
  const words = Object.keys(notices).map((k) => notices[k]).filter(Boolean);
  box.textContent = words.join(" ");
  box.hidden = words.length === 0;
}
function say(kind, words) { notices[kind] = words || ""; showNotices(); }
function messageOf(e) { return e && e.message ? e.message : String(e); }

// --- the phone and the bridge, made once ---

// The deployment's config.json, once read: the transport, and how long the app may stay hidden.
let config = null;
// The relay's accounts, or null when it has none (account-client.js).
let account = null;
async function makeBridge() {
  config = await fetch("config.json", { cache: "no-store" }).then((r) => { if (!r.ok) throw new Error("this deployment has no config.json"); return r.json(); });
  const transport = transportFromConfig(config, window);
  if (!transport) throw new Error("this deployment names no relay transport this app knows ('" + String(config.transport) + "')");
  account = accountFromConfig(config, window);
  const phone = createPhone({ store: await openStore(), authenticator: browserAuthenticator(), relay: createRelayClient(transport), account, origin: window.location.origin });
  return createBridge(phone, {
    look: LOOK,
    waitMs: WATCH_MS,
    visible: () => document.visibilityState === "visible",
    loadKinds: () => fetch("../list/question-kinds.json").then((r) => r.json()).then((j) => j.kinds)
  });
}
const made = makeBridge();
window.HordeBridge = deferredBridge(made);
const bridge = window.HordeBridge;
made.catch((e) => say("boot", "This app cannot start here: " + messageOf(e)));

// --- is the relay being read? (read-banner.js) ---
// While the reads of the mailbox fail, ONE banner says so, with the time of the last read that worked:
// the page keeps what it last read, and must not show it as current. A failed read asks the relay's
// session whether he is still signed in (a watch refused at its socket says nothing of why). On the
// locked screen the lock is said already, so the banner leaves it out.
let readLast = null;
let readSession = null;
const lastTime = (ms) => (new Date(ms).toDateString() === new Date().toDateString() ? clockTime(ms) : dayTime(ms));
function showReadBanner() {
  const kind = readFailure(readLast, readSession);
  say("read", kind === "locked" && !$("lockedView").hidden ? "" : readBanner(kind, readLast ? readLast.lastGoodAt : 0, lastTime));
}
bridge.on("read-changed", async (rec) => {
  readLast = rec;
  readSession = null;
  if (rec && rec.relayDown && account) {
    const s = await account.session();
    if (readLast !== rec) return; // a newer read has spoken meanwhile
    readSession = s;
  }
  showReadBanner();
});

// --- the screens ---

const VIEWS = ["signInView", "accountView", "pairView", "pairedView", "lockedView", "emptyView", "doc", "chat", "progress", "notices"];
// The views of an unlocked horde, each a tab of the bar: the pane's name, and the view and the tab it is.
const PANES = { decisions: { view: "doc", tab: "tabDecisions" }, chat: { view: "chat", tab: "tabChat" }, progress: { view: "progress", tab: "tabProgress" }, notices: { view: "notices", tab: "tabNotices" } };
function show(view) {
  for (const v of VIEWS) $(v).hidden = v !== view;
  $("keys").hidden = view !== "doc";
  $("viewTabs").hidden = !Object.keys(PANES).some((p) => PANES[p].view === view);
  // Shown again by render() for an unlocked horde the machine has not answered yet.
  $("announceBox").hidden = true;
  showReadBanner();
}
// Which view of an unlocked horde is up: its questions, its chat, or the progress log.
let pane = "decisions";

let hordes = [];
let current = "";
const docs = Object.create(null);

function memoryStorage() {
  const m = new Map();
  return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => { m.set(k, String(v)); }, removeItem: (k) => { m.delete(k); } };
}
function docOf(id) {
  if (docs[id]) return docs[id];
  // THE CARDS FIRST (decision-cards.js), in a box of their own above the list: the list's box is
  // list.js's, which keeps in it only what it draws.
  const cards = document.createElement("div");
  cards.className = "decision-cards";
  cards.setAttribute("role", "group");
  cards.setAttribute("aria-label", "Questions by lane");
  $("lists").appendChild(cards);
  const box = document.createElement("div");
  box.className = "horde-list";
  $("lists").appendChild(box);
  const storage = memoryStorage();
  const doc = window.HordeDecisionsDocument.mount(box, {
    topInset: () => $("bar").getBoundingClientRect().bottom,
    // Every draw - a list that arrives, a lane chosen, an answer saved - draws the cards' numbers again.
    onDraw: () => drawDecisionCards(id),
    onChange: showCounts,
    storage,
    say: (number, text, wording, answerId) => inFlight(bridge.request("say", { number, text, wording, id: answerId })),
    // One part's answer: the same request with the part's letter, signed and sent by itself.
    sayPart: (number, letter, text, wording, answerId) => inFlight(bridge.request("say", { number, text, wording, id: answerId, part: letter })),
    act: (number, what, wording, answerId) => inFlight(bridge.request("act", { number, act: what, wording, id: answerId }))
  });
  docs[id] = { box, cards, doc, kinds: false, storage };
  return docs[id];
}
// The cards of one horde's decisions page: its lanes' counts from its list, drawn as the Progress tab's cards
// when that horde is the one picked and its lanes document has come (cardsLast), and by name alone otherwise.
function drawDecisionCards(id) {
  const d = docs[id];
  if (!d) return;
  while (d.cards.firstChild) d.cards.removeChild(d.cards.firstChild);
  for (const card of renderDecisionCards(document, id === current ? cardsLast : null, d.doc.lanes(), { chosen: d.doc.lane(), onChoose: (lane) => d.doc.setLane(lane) })) d.cards.appendChild(card);
}
function showCounts() {
  const d = current && docs[current];
  $("counts").textContent = d && !$("doc").hidden ? d.doc.counts().toAnswer + " to answer" : "";
}

function drawTabs() {
  const tabs = $("tabs");
  while (tabs.firstChild) tabs.removeChild(tabs.firstChild);
  const names = Object.create(null);
  for (const h of hordes) names[h.horde] = (names[h.horde] || 0) + 1;
  for (const h of hordes) {
    const b = document.createElement("button");
    b.type = "button";
    b.setAttribute("role", "tab");
    b.setAttribute("aria-selected", h.id === current ? "true" : "false");
    // Two machines of one horde are told apart by the start of the machine's key id.
    b.textContent = h.horde + (names[h.horde] > 1 ? " " + h.machine.slice(0, 6) : "") + (h.unlocked ? "" : " (locked)");
    b.addEventListener("click", () => pick(h.id));
    tabs.appendChild(b);
  }
}

async function loadHordes() { hordes = await bridge.request("hordes"); drawTabs(); return hordes; }

async function pick(id) {
  current = id;
  drawTabs();
  const h = hordes.find((x) => x.id === id);
  if (!h) { show(hordes.length ? "lockedView" : "emptyView"); return; }
  for (const k of Object.keys(docs)) { docs[k].box.hidden = k !== id; docs[k].cards.hidden = k !== id; }
  const rec = await bridge.request("pick", { id });
  render(h, rec);
}

function render(h, rec) {
  if (!h || h.id !== current) return;
  if (!h.unlocked) {
    $("lockedTitle").textContent = h.horde + " is locked";
    $("lockedHint").textContent = h.announced ? "Unlock with your passkey to read and answer." : "This phone has not announced its key to the machine yet: unlock, then announce it.";
    show("lockedView");
    // The locked screen says it is locked: a notice saying so again is dropped, and nothing opened is shown
    // to be old, so what the relay said goes too.
    say("view", "");
    say("relay", "");
    showCounts();
    return;
  }
  const d = docOf(h.id);
  d.box.hidden = false;
  d.cards.hidden = false;
  show(PANES[pane].view);
  // The decisions page's cards are the Progress tab's (decision-cards.js): its lanes document, asked for once here
  // too; cards-changed brings every later one.
  if (pane === "decisions" && !cardsLast) bridge.request("cards").then(drawCards);
  showAnnounceBox(h, rec);
  if (pane === "chat") bridge.request("chat").then(drawChat);
  if (pane === "progress") { bridge.request("cards").then(drawCards); requestStream(); }
  if (pane === "notices") bridge.request("notices").then(drawNotices);
  const banners = {
    recovery: "Read only: unlocked with the recovery code. Lock and unlock with the passkey to answer.",
    "read-only": "Read only: this passkey gives no PRF, so answers are never sent from this phone for this horde. Answer at the machine, or pair again with a passkey that has PRF."
  };
  $("mode").hidden = !banners[h.mode];
  $("mode").textContent = banners[h.mode] || "";
  // THE LIST IS SHORTER THAN THE MACHINE'S, AND SAYS SO: one line above it whenever the snapshot on screen
  // leaves questions out, with how many and why (relay/js/protocol.js, withheldWords). It is the record's
  // own, so it goes when a snapshot with nothing left out arrives, and with the list when the horde locks.
  const notShown = rec && rec.state === "known" && rec.value && typeof rec.value.notShown === "string" ? rec.value.notShown : "";
  $("notShown").hidden = !notShown;
  $("notShown").textContent = notShown;
  if (!d.kinds) { d.kinds = true; bridge.request("kinds").then((k) => d.doc.setKinds(k)); }
  const did = d.doc.setList(rec);
  // NOT THE RELAY'S NOTICE (Orc E's reproduction, 2026-10-14): a failed read says so, and the list drawn
  // next - the old snapshot, kept - cleared those words at once, so a 401 left old content with no sign.
  say("view", did === "unread" ? (rec && rec.reason ? rec.reason : "") : "");
  showCounts();
}

bridge.on("list-changed", (rec) => { const h = hordes.find((x) => x.id === current); if (h) render(h, rec); });

// --- announcing, from the horde's own view ---

// The hordes a snapshot was drawn for in this page: heard from, even before the summary is read again.
const heard = new Set();
function showAnnounceBox(h, rec) {
  if (rec && rec.state === "known") heard.add(h.id);
  const waiting = !h.heard && !heard.has(h.id);
  $("announceBox").hidden = !waiting;
  if (!waiting) return;
  $("announceWords").textContent = h.announced
    ? "The machine has not answered this phone yet. Its runner sends the questions when it next turns; if none come, announce this phone again."
    : "This phone has not been announced to the machine yet, so the machine sends it nothing. Once you have typed its number at the machine, announce it.";
}
// What went wrong with an announcement, beside the button that sent it ("" hides it).
function announceSaid(el, words) { $(el).textContent = words || ""; $(el).hidden = !words; }
$("announceNow").addEventListener("click", async () => {
  say("action", "");
  announceSaid("announceNowStatus", "");
  $("announceNow").disabled = true;
  try {
    await bridge.request("announce", { id: current });
    announceSaid("announceNowStatus", "Announced. The questions appear here once the machine's runner turns.");
    await loadHordes();
    await pick(current);
  } catch (e) { announceSaid("announceNowStatus", messageOf(e)); } finally { $("announceNow").disabled = false; }
});
bridge.on("chat-changed", (rec) => drawChat(rec));

// --- the chat ---

const CHAT_BANNERS = {
  recovery: "Read only: unlocked with the recovery code, which cannot sign a line. Lock and unlock with the passkey to write to the Thrall.",
  "read-only": "Read only: this passkey gives no PRF, so no line is ever sent from this phone for this horde."
};
function pickPane(which, fromHistory = false) {
  // A switch is a history entry, so the phone's Back goes to the other view; Back itself is not one.
  if (!fromHistory && which !== pane) { try { history.pushState({ hordePane: which }, ""); } catch (e) { /* a page with no history keeps working */ } }
  // The tab opens on its cards, and a stream at his place each time it is opened, not only the first.
  if (which === "progress" && pane !== "progress") { progressDrawn = ""; stream = null; }
  pane = which;
  for (const p of Object.keys(PANES)) $(PANES[p].tab).setAttribute("aria-selected", which === p ? "true" : "false");
  if (current) pick(current);
}
for (const p of Object.keys(PANES)) $(PANES[p].tab).addEventListener("click", () => pickPane(p));
window.addEventListener("popstate", (e) => {
  const p = e.state && e.state.hordePane;
  // Back from a stream is the cards page again.
  if (p === "progress" && pane === "progress" && stream && !e.state.stream) { closeStream(); return; }
  pickPane(Object.prototype.hasOwnProperty.call(PANES, p) ? p : "decisions", true);
});
try { history.replaceState({ hordePane: "decisions" }, ""); } catch (e) { /* as above */ }
// WHEN IT WAS SAID, beside who said it: the short local time, and the exact one as its title and on a
// tap (a phone has no pointer to rest on it), tapped again for the short one. Nothing for a thing with
// no time: an old envelope that carries none is shown without, never with a guess.
// A stamp opened stays open while the log is drawn again (every refresh draws it anew): the keys of the
// open ones are kept here, and dropped when the horde locks.
const openStamps = new Set();
function timeStamp(ms, before, key, shortForm = clockTime) {
  const short = shortForm(ms);
  if (!short) return null;
  const exact = before + exactTime(ms);
  const t = document.createElement("button");
  t.type = "button";
  t.className = "stamp";
  const show = () => { t.textContent = openStamps.has(key) ? exact : short; };
  t.title = exact;
  t.setAttribute("aria-label", exact); show();
  t.addEventListener("click", () => {
    if (openStamps.has(key)) openStamps.delete(key); else openStamps.add(key);
    show();
  });
  return t;
}
function clearChat() { const log = $("chatLog"); while (log.firstChild) log.removeChild(log.firstChild); }
function drawChat(rec) {
  if ($("chat").hidden || !rec) return;
  if (rec.state !== "known") { clearChat(); $("chatEmpty").hidden = true; say("view", rec.reason || ""); return; }
  const v = rec.value;
  const log = $("chatLog");
  const atEnd = window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 40;
  clearChat();
  for (const it of withDays(v.items)) {
    // The day, on a line of its own, wherever it changes.
    if (it.kind === "day") { const day = document.createElement("div"); day.className = "chat-day"; day.textContent = it.label; log.appendChild(day); continue; }
    const box = document.createElement("div");
    const who = document.createElement("div");
    const text = document.createElement("div");
    const mine = it.kind === "line" || it.kind === "photo";
    box.className = "chat-item " + (mine ? "founder" : it.role);
    who.className = "chat-who";
    const name = document.createElement("span");
    name.textContent = mine ? "You" : it.role === "assistant" ? "Thrall" : it.role === "user" ? "At the machine" : "The machine";
    who.appendChild(name);
    const stamp = timeStamp(it.said, it.saidHow === "delivered" ? "Reached the Thrall " : "", "chat/" + (it.kind === "line" ? "line/" + it.messageId : it.kind === "photo" ? "photo/" + it.photoId : "turn/" + it.id));
    if (stamp) who.appendChild(stamp);
    text.className = "chat-text";
    box.appendChild(who);
    if (it.kind === "photo") {
      // A PHOTO: the small picture this page drew when it was sent (kept in memory only, like the chat);
      // from another phone, or after a reload, the words say what it is.
      const thumb = photoThumbs.get(it.photoId);
      if (thumb) { const c = document.createElement("canvas"); c.className = "chat-photo"; c.width = thumb.width; c.height = thumb.height; c.getContext("2d").drawImage(thumb, 0, 0); c.setAttribute("role", "img"); c.setAttribute("aria-label", "Your photo"); box.appendChild(c); }
      text.textContent = it.file ? "Photo " + it.file : "Photo";
    } else text.textContent = it.text;
    box.appendChild(text);
    const notes = [];
    if (it.kind === "line" || it.kind === "photo") notes.push(it.words);
    if (it.truncated) notes.push("Cut short at the machine: it was longer than a turn may be.");
    if (it.redactions) notes.push(it.redactions + " thing(s) that look like secrets were hidden at the machine.");
    for (const n of notes) { const d = document.createElement("div"); d.className = "chat-note"; d.textContent = n; box.appendChild(d); }
    log.appendChild(box);
  }
  $("chatEmpty").hidden = v.items.length > 0 || !!v.session;
  const banner = CHAT_BANNERS[v.mode] || "";
  $("chatMode").hidden = !banner;
  $("chatMode").textContent = banner;
  const canWrite = v.mode === "passkey";
  $("chatText").disabled = !canWrite;
  $("chatSend").disabled = !canWrite;
  $("chatNewline").disabled = !canWrite;
  $("chatPhoto").disabled = !canWrite;
  photoOffered = v.photoBytes || 0;
  if (atEnd) window.scrollTo(0, document.documentElement.scrollHeight);
}
// --- photos to the Thrall (photo.js shrinks; phone-core.js, sendPhoto, signs once and sends) ---
// What the machine said it takes (its newest turns body), and the small pictures this page drew, by id.
let photoOffered = 0;
const photoThumbs = new Map();
let photoSending = false;
$("chatPhoto").addEventListener("click", () => {
  if ($("chatPhoto").disabled || photoSending) return;
  // A MACHINE OLDER THAN PHOTOS never offered them: said in plain words, and nothing is picked or sent.
  if (!photoOffered) { say("action", PHOTO_PC_OLD); return; }
  $("chatPhotoFile").value = "";
  $("chatPhotoFile").click();
});
$("chatPhotoFile").addEventListener("change", async () => {
  const file = $("chatPhotoFile").files && $("chatPhotoFile").files[0];
  if (!file || photoSending) return;
  photoSending = true;
  say("action", "");
  try {
    // THE FIRST BYTES DECIDE, not the name or the type the browser guesses from it: an HTML page called
    // .jpg is refused here, before anything is drawn.
    const head = new Uint8Array(await file.slice(0, 16).arrayBuffer());
    if (!sniffImage(head)) { say("action", PHOTO_NOT_IMAGE); return; }
    let made;
    try { made = await shrinkInBrowser(file); } catch (e) { say("action", PHOTO_NOT_IMAGE + " (" + messageOf(e) + ")"); return; }
    const id = newDraftId();
    photoThumbs.set(id, made.thumb);
    const r = await bridge.request("chat-photo", { bytes: made.bytes, id });
    if (!r.ok) say("action", r.reason);
  } catch (e) { say("action", messageOf(e)); } finally { photoSending = false; settleUpdate(); }
});
// The page's id for the words in the composer: kept until they are sent, so a line sent again after a
// failure is the same line, posted once - but only the SAME words: words changed since the last try
// are a new line with a new id (review of 3d837f0, finding 1).
let draftId = "";
let draftTried = "";
function newDraftId() { return Array.from(crypto.getRandomValues(new Uint8Array(16)), (b) => (b < 16 ? "0" : "") + b.toString(16)).join(""); }
let sending = false;
async function sendLine() {
  const field = $("chatText");
  const text = field.value;
  if (sending || !text.trim() || field.disabled) return;
  if (!draftId || text !== draftTried) draftId = newDraftId();
  draftTried = text;
  sending = true;
  say("action", "");
  try {
    const r = await bridge.request("chat-send", { text, id: draftId });
    if (r.ok) { field.value = ""; draftId = ""; } else say("action", r.reason);
  } catch (e) { say("action", messageOf(e)); } finally { sending = false; settleUpdate(); }
}
$("chatText").addEventListener("input", () => { if (!$("chatText").value) draftId = ""; });
$("chatText").addEventListener("keydown", (e) => {
  if (e.key === "Enter" && !e.shiftKey && !e.ctrlKey && !e.altKey && !e.isComposing) { e.preventDefault(); sendLine(); }
});
// The keys are pressed on pointerdown with the default prevented, so the field keeps the caret and the
// soft keyboard stays up, as the answering row's keys are.
$("chatSend").addEventListener("pointerdown", (e) => { e.preventDefault(); sendLine(); });
$("chatSend").addEventListener("click", (e) => { if (e.detail === 0) sendLine(); });
$("chatNewline").addEventListener("pointerdown", (e) => {
  e.preventDefault();
  const f = $("chatText");
  if (f.disabled) return;
  const a = f.selectionStart, b = f.selectionEnd;
  f.value = f.value.slice(0, a) + "\n" + f.value.slice(b);
  f.selectionStart = f.selectionEnd = a + 1;
  f.focus();
});
// --- the progress log ---

// WHAT WAS LAST DRAWN, so a refresh that brings nothing new does not rebuild the page under his thumb:
// the horde, how many entries, the newest one, and the notices. "" draws anew, and goes to his place.
let progressDrawn = "";
// Where the "new since you last read" line stands, fixed when the log is opened: it does not creep down
// the page while he reads.
let progressMark = -1;
let progressLast = null;
// The entries that have been on his screen since the horde was unlocked (by id): what "seen" means below.
const seenEntries = new Set();
// EVERY ENTRY STARTS FOLDED to one line, its title and its day and time (the founder asked, 2026-10-14: "to
// be able to see a swath of progress at once without all the details"); a tap opens one. The ones he opened
// (by id) stay open while the stream is redrawn under him - a new entry rebuilds the whole log - and are
// forgotten when a stream is opened anew (drawProgress, opening). Kept in memory only: nothing stored, nothing sent.
const openEntries = new Set();
let watcher = null;
function clearCards() { const list = $("cardsList"); while (list.firstChild) list.removeChild(list.firstChild); cardsLast = null; stream = null; drawDecisionCards(current); }
function clearProgress() { const log = $("progressLog"); while (log.firstChild) log.removeChild(log.firstChild); progressDrawn = ""; progressLast = null; seenEntries.clear(); if (watcher) { watcher.disconnect(); watcher = null; } }
function showProgressCount(v) {
  const n = v ? v.unread : 0;
  $("tabProgress").textContent = "Progress" + (n > 0 ? " (" + n + ")" : "");
  $("progressCount").textContent = !v || v.items.length === 0 ? "" : n > 0 ? n + " new" : "All read";
  $("progressAllRead").disabled = n === 0;
}
function paragraphsInto(box, paragraphs) {
  for (const p of paragraphs) {
    const line = document.createElement("p");
    if (p.label) { const b = document.createElement("b"); b.textContent = p.label + ": "; line.appendChild(b); }
    line.appendChild(document.createTextNode(p.text));
    box.appendChild(line);
  }
}
// An entry folded or open: its class (app.css hides all but the one line) and its line's aria-expanded.
function foldEntry(box, open) {
  box.classList.toggle("collapsed", !open);
  box.querySelector(".progress-line").setAttribute("aria-expanded", open ? "true" : "false");
}
function toggleEntry(box) {
  const id = box.getAttribute("data-id");
  const open = !openEntries.has(id);
  if (open) openEntries.add(id); else openEntries.delete(id);
  foldEntry(box, open);
}
function chip(words, kind) { const c = document.createElement("span"); c.className = "chip " + kind; c.textContent = words; return c; }
// --- the cards ---

// The stream on screen: null for the cards page, else { entry, lane, title, fallback } - entry the pairing
// whose log it is, lane "" for the Thrall's (the whole log), fallback when no machine has sent cards yet.
let stream = null;
let cardsLast = null;
function streamKey() { return stream ? stream.entry + "/" + stream.lane : ""; }
function showProgressPage() {
  $("cardsPage").hidden = !!stream;
  $("streamPage").hidden = !stream;
  $("streamBack").hidden = !stream || stream.fallback;
  $("streamTitle").textContent = stream ? stream.title : "";
  $("streamLimit").textContent = STREAM_LIMIT_WORDS;
  $("streamLimit").hidden = !stream;
  $("cardsWhy").hidden = !stream || !stream.fallback;
}
function requestStream() {
  showProgressPage();
  if (!stream) return;
  const own = stream.entry === current;
  bridge.request("progress", own ? {} : { of: stream.entry }).then((rec) => drawProgress(rec, own));
}
function openStream(next) {
  try { history.pushState({ hordePane: "progress", stream: true }, ""); } catch (e) { /* a page with no history keeps working */ }
  stream = next;
  progressDrawn = "";
  requestStream();
}
function closeStream() { stream = null; progressDrawn = ""; showProgressPage(); if (cardsLast) drawCards({ state: "known", value: cardsLast }); window.scrollTo(0, 0); }
$("streamBack").addEventListener("click", () => { try { history.back(); } catch (e) { closeStream(); } });
function drawCards(rec) {
  if (!rec || rec.state !== "known") return;
  const v = rec.value;
  cardsLast = v;
  drawDecisionCards(current);
  if ($("progress").hidden) return;
  // NO MACHINE HAS SENT CARDS: the whole log, as before cards were, under one plain line saying why (cards-why.js).
  if (v.machines.length === 0) { $("cardsWhy").textContent = cardsFallbackLine(v); if (!stream) { stream = { entry: current, lane: "", title: "", fallback: true }; requestStream(); } return; }
  if (stream && stream.fallback) { stream = null; progressDrawn = ""; }
  showProgressPage();
  const list = $("cardsList");
  while (list.firstChild) list.removeChild(list.firstChild);
  const notes = [];
  for (const m of v.machines) if (m.cardsLeftOut) notes.push(m.cardsLeftOut + " card(s) of " + m.name + " did not fit and are not shown.");
  for (const m of v.machines) if (m.areasLeftOut) notes.push(m.areasLeftOut + " area(s) of " + m.name + "'s map did not fit, so their updates show only in the Thrall's stream.");
  $("cardsNote").textContent = notes.join(" ");
  $("cardsNote").hidden = notes.length === 0;
  // THE ONE CARD (lane-card.js), its one slot holding the FOLLOW SWITCH; a tap elsewhere opens the lane's stream.
  for (const t of v.thrall) { const box = renderLaneCard(document, v, THRALL_LANE, { machine: t.machine, badge: followSwitch(t.entry, THRALL_LANE), onOpen: openLane }); if (box) list.appendChild(box); }
  for (const c of v.cards) { const box = renderLaneCard(document, v, c.lane, { machine: c.machine, badge: followSwitch(c.entry, c.lane), onOpen: openLane }); if (box) list.appendChild(box); }
}
function openLane(o) { openStream({ entry: o.entry, lane: o.lane === THRALL_LANE ? "" : o.lane, title: (o.lane === THRALL_LANE ? "Thrall - the whole fleet" : o.lane) + (o.machine ? ", " + o.machine : ""), fallback: false }); }

// --- following a lane, and the notices ---

// THE FOLLOW SWITCH of a card (the founder, 2026-10-14: "notify me of progress postings for lane/orc x"),
// OFF BY DEFAULT. It shows WHAT THE MACHINE HOLDS (the newest notices envelope of that card's machine,
// phone-core.js, THE NOTICES); a tap signs the change with the passkey and sends it to that machine, and
// the switch says "Sending..." until the machine's next envelope carries it. It sits in the card's one slot
// (lane-card.js, badge), and a tap on it is ITS OWN: it never also opens the card.
let noticesLast = null;
const followWish = new Map();
function followSwitch(entry, lane) {
  const held = !!(noticesLast && noticesLast.follows && noticesLast.follows[entry] && noticesLast.follows[entry][lane] === true);
  const key = entry + "/" + lane;
  if (followWish.has(key) && followWish.get(key) === held) followWish.delete(key);
  return renderFollowSwitch(document, { held, sending: followWish.has(key), onToggle: (want) => {
    followWish.set(key, want);
    if (cardsLast) drawCards({ state: "known", value: cardsLast });
    bridge.request("follow", { entry, lane, on: want }).then((r) => {
      if (!r || !r.ok) { followWish.delete(key); say("action", (r && r.reason) || ""); }
      if (cardsLast) drawCards({ state: "known", value: cardsLast });
    });
  } });
}
function showNoticesCount(v) {
  const n = v ? v.unread : 0;
  $("tabNotices").textContent = noticesTabWords(n);
}
// THE NOTICES, NEWEST FIRST: who it is from, when in plain words (the exact time as its title), its words,
// and whether he has read it. A tap marks it read; a notice of a lane's progress also opens that lane's
// stream on the Progress tab.
function drawNotices(rec) {
  if (!rec) return;
  if (rec.state !== "known") { noticesLast = null; showNoticesCount(null); const l = $("noticesList"); while (l.firstChild) l.removeChild(l.firstChild); return; }
  const v = rec.value;
  const wasFollows = JSON.stringify(noticesLast ? noticesLast.follows : null);
  noticesLast = v;
  showNoticesCount(v);
  if (cardsLast && wasFollows !== JSON.stringify(v.follows) && !$("progress").hidden && !stream) drawCards({ state: "known", value: cardsLast });
  if ($("notices").hidden) return;
  $("noticesCount").textContent = v.items.length === 0 ? "" : v.unread > 0 ? v.unread + " unread" : "All read";
  $("noticesAllRead").disabled = v.unread === 0;
  $("noticesEmpty").hidden = v.items.length > 0;
  const list = $("noticesList");
  while (list.firstChild) list.removeChild(list.firstChild);
  const nowMs = Date.now();
  for (const it of v.items) {
    list.appendChild(renderNoticeItem(document, it, { nowMs, onOpen: (x) => {
      if (!x.read) bridge.request("notices-read", { ids: [x.id] }).then(drawNotices);
      const to = noticeTarget(x);
      if (to) { pickPane("progress"); openLane(to); }
    } }));
  }
}
$("noticesAllRead").addEventListener("click", () => { bridge.request("notices-read", { all: true }).then((rec) => { if (rec.state === "known") drawNotices(rec); else say("action", rec.reason || ""); }); });
bridge.on("notices-changed", (rec) => drawNotices(rec));
bridge.on("cards-changed", (rec) => drawCards(rec));

// --- a stream: the progress log, or a lane's part of it ---

function drawProgress(rec, own = true) {
  if (!rec) return;
  if (rec.state !== "known") { clearProgress(); if (own) showProgressCount(null); if (!$("progress").hidden) { $("progressEmpty").hidden = true; $("progressNote").hidden = true; say("view", rec.reason || ""); } return; }
  const full = rec.value;
  // The count on the tab is the picked horde's whole log, kept whichever view is up.
  if (own) showProgressCount(full);
  if ($("progress").hidden || !stream) return;
  // A LANE'S STREAM, with his place as the last of its entries written at or before the place he read to.
  const items = laneStream(full.items, stream.lane, full.areas || []);
  const readN = full.readIndex >= 0 ? full.items[full.readIndex].n : 0;
  let readIndex = -1;
  items.forEach((it, i) => { if (it.n <= readN) readIndex = i; });
  const v = { ...full, items, readIndex, unread: items.length - 1 - readIndex };
  progressLast = v;
  // Mark all read moves his place, so it is offered only where his place moves (review of PR 244).
  $("progressAllRead").hidden = !streamMovesPlace(stream, current);
  const notes = [];
  if (v.stopped) notes.push(PROGRESS_WORDS["file-replaced"]);
  if (v.skipped) notes.push(v.skipped + " " + PROGRESS_WORDS["lines-skipped"]);
  $("progressNote").textContent = notes.join(" ");
  $("progressNote").hidden = notes.length === 0;
  $("progressEmpty").hidden = v.items.length > 0;
  const sig = current + "/" + streamKey() + "/" + v.items.length + "/" + (v.newest ? v.newest.id : "") + "/" + v.items.reduce((n, it) => n + it.corrections.length, 0);
  if (sig === progressDrawn) return;
  const opening = progressDrawn === "";
  if (opening) { progressMark = v.readIndex; openEntries.clear(); }
  progressDrawn = sig;
  const log = $("progressLog");
  while (log.firstChild) log.removeChild(log.firstChild);
  v.items.forEach((it, i) => {
    if (i === progressMark + 1 && progressMark >= 0) { const line = document.createElement("div"); line.className = "progress-new"; line.id = "progressNew"; line.textContent = "New since you last read"; log.appendChild(line); }
    const box = document.createElement("div");
    box.className = "progress-item";
    box.setAttribute("data-id", it.id);
    const head = document.createElement("div");
    head.className = "progress-head";
    // The area's plain name first; the kind; the lane and the task only when the entry names them, small.
    if (it.area) head.appendChild(chip(it.area, "area"));
    head.appendChild(chip(it.kindWord, "kind-" + it.kind));
    if (it.lane) head.appendChild(chip("Lane " + it.lane, "lane"));
    if (it.task) head.appendChild(chip(it.task, "task"));
    const grow = document.createElement("span"); grow.className = "grow"; head.appendChild(grow);
    const stamp = timeStamp(it.said, "", "progress/" + it.id, dayTime);
    if (stamp) head.appendChild(stamp);
    box.appendChild(head);
    // THE ONE LINE: the title, and - shown only while folded (app.css), the head standing for it when open -
    // the same day and time the head's stamp shows. It is the entry's control: Enter or Space toggles it.
    const line = document.createElement("div"); line.className = "progress-line";
    line.setAttribute("role", "button"); line.tabIndex = 0;
    const title = document.createElement("div"); title.className = "progress-title"; title.textContent = it.title; line.appendChild(title);
    const when = dayTime(it.said);
    if (when) { const w = document.createElement("span"); w.className = "progress-when"; w.textContent = when; line.appendChild(w); }
    box.appendChild(line);
    line.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); toggleEntry(box); } });
    // Folded, a tap anywhere on it opens it. Open, a tap on its head or its title folds it; a button or a
    // link anywhere in it (the stamp, say) does its own thing only.
    box.addEventListener("click", (e) => {
      const t = e.target instanceof Element ? e.target : e.target.parentElement;
      if (!box.classList.contains("collapsed") && (!t || t.closest("button, a") || !t.closest(".progress-head, .progress-line"))) return;
      toggleEntry(box);
    });
    const text =document.createElement("div"); text.className = "progress-text"; paragraphsInto(text, it.paragraphs); box.appendChild(text);
    if (it.corrects) { const n = document.createElement("div"); n.className = "progress-note"; n.textContent = it.correctsTitle ? "This corrects: " + it.correctsTitle : "This corrects an earlier entry that is not on this phone."; box.appendChild(n); }
    // A CORRECTION IS SHOWN ON THE ENTRY IT CORRECTS, as well as in its own place further down.
    for (const c of it.corrections) {
      const cb = document.createElement("div"); cb.className = "progress-correction";
      const ch = document.createElement("div"); ch.className = "progress-note"; ch.textContent = "Corrected" + (dayTime(c.said) ? ", " + dayTime(c.said) : "") + ":"; cb.appendChild(ch);
      const ct = document.createElement("div"); ct.className = "progress-title"; ct.textContent = c.title; cb.appendChild(ct);
      const cx = document.createElement("div"); cx.className = "progress-text"; paragraphsInto(cx, c.paragraphs); cb.appendChild(cx);
      box.appendChild(cb);
    }
    foldEntry(box, openEntries.has(it.id));
    log.appendChild(box);
  });
  if (opening) {
    // BACK TO HIS PLACE: the line under the last entry he read, at the top of the screen; with nothing new
    // (or nothing read yet), the newest end, or the start.
    const mark = $("progressNew");
    if (mark) window.scrollTo(0, Math.max(0, window.scrollY + mark.getBoundingClientRect().top - $("bar").getBoundingClientRect().bottom - 8));
    else if (progressMark >= 0) window.scrollTo(0, document.documentElement.scrollHeight);
    else window.scrollTo(0, 0);
  }
  // Only now, with the page where it will stand, is what is on the screen taken as seen.
  watchEntries();
}
// HE HAS READ WHAT HE HAS SEEN, IN ORDER. An entry is seen once half of it - or, for one taller than the
// screen, half a screen of it - has stood between the bar and the foot; the browser tells the page so as
// entries pass (an IntersectionObserver), whether he reads slowly or scrolls on. His place moves on from
// the last entry read through every next entry seen, and stops at the first one not seen: entries he
// JUMPED past - Jump to newest lands on the end without passing them - were never on the screen, so a
// jump marks nothing between read and his place is kept.
let readTimer = null;
function isSeen(box) {
  const top = $("bar").getBoundingClientRect().bottom, bottom = $("progressFoot").getBoundingClientRect().top;
  const r = box.getBoundingClientRect();
  const shown = Math.min(r.bottom, bottom) - Math.max(r.top, top);
  return shown > 0 && shown >= Math.min(r.height, bottom - top) / 2;
}
function noteSeen() {
  if ($("progress").hidden) return;
  for (const box of $("progressLog").querySelectorAll(".progress-item")) { if (!seenEntries.has(box.getAttribute("data-id")) && isSeen(box)) seenEntries.add(box.getAttribute("data-id")); }
  clearTimeout(readTimer);
  readTimer = setTimeout(readAsSeen, 250);
}
function watchEntries() {
  if (watcher) { watcher.disconnect(); watcher = null; }
  // Told as entries cross the screen; the page then measures for itself (isSeen), so the rule is one.
  if (typeof IntersectionObserver === "function") {
    watcher = new IntersectionObserver(() => noteSeen(), { threshold: [0, 0.25, 0.5, 0.75, 1] });
    for (const box of $("progressLog").querySelectorAll(".progress-item")) watcher.observe(box);
  }
  noteSeen();
}
function readAsSeen() {
  const v = progressLast;
  // His place moves only in the whole log of the picked horde (THE PROGRESS TAB OPENS ON CARDS).
  if (!v || $("progress").hidden || v.unread === 0 || !streamMovesPlace(stream, current)) return;
  let upTo = "";
  for (let i = v.readIndex + 1; i < v.items.length; i++) {
    if (!seenEntries.has(v.items[i].id)) break;
    upTo = v.items[i].id;
  }
  if (upTo) bridge.request("progress-read", { id: upTo }).then((rec) => { if (rec.state === "known") { progressLast = rec.value; showProgressCount(rec.value); } });
}
// A browser with no such observer is told by the scroll itself.
window.addEventListener("scroll", () => { if (!watcher) noteSeen(); }, { passive: true });
$("progressNewest").addEventListener("click", () => window.scrollTo(0, document.documentElement.scrollHeight));
$("progressAllRead").addEventListener("click", () => { bridge.request("progress-read", { all: true }).then((rec) => { if (rec.state === "known") { progressLast = rec.value; showProgressCount(rec.value); } else say("action", rec.reason || ""); }); });
bridge.on("progress-changed", (rec) => {
  if (!stream || stream.entry === current) { drawProgress(rec, true); return; }
  // A stream of another machine: the tab's count from this record, the stream from its own log.
  if (rec && rec.state === "known") showProgressCount(rec.value);
  requestStream();
});
bridge.on("hordes-changed", (list) => { hordes = list; drawTabs(); });
bridge.on("notice", (words) => say("relay", words));

// --- pairing ---

let scanning = null;
async function openPair() {
  show("pairView");
  $("scanBtn").hidden = !(await canScan());
  $("offerText").value = "";
}
$("addBtn").addEventListener("click", openPair);
$("firstPair").addEventListener("click", openPair);
$("pairCancel").addEventListener("click", () => { if (scanning) scanning.stop(); pick(current || (hordes[0] && hordes[0].id) || ""); });
$("scanBtn").addEventListener("click", async () => {
  $("scanBox").hidden = false;
  scanning = scanQr($("scanVideo"));
  const r = await scanning.done;
  scanning = null;
  $("scanBox").hidden = true;
  if (r.text) $("offerText").value = r.text;
  else if (r.reason) say("action", r.reason);
});
$("scanStop").addEventListener("click", () => { if (scanning) scanning.stop(); });

let paired = null;
$("pairBtn").addEventListener("click", async () => {
  say("action", "");
  $("pairBtn").disabled = true;
  try {
    paired = await bridge.request("pair", { offer: $("offerText").value, label: $("labelText").value.trim() });
    $("offerText").value = "";
    $("fingerprint").textContent = paired.fingerprint;
    $("recoveryCode").textContent = paired.recoveryCode;
    $("responseText").value = paired.response;
    $("shareResponse").hidden = typeof navigator.share !== "function";
    showRelayed(paired.relayed);
    $("wroteCode").checked = false;
    $("announceBtn").disabled = true;
    $("announceWhy").hidden = false;
    announceSaid("announceStatus", "");
    show("pairedView");
    await loadHordes();
  } catch (e) { say("action", messageOf(e)); } finally { $("pairBtn").disabled = false; }
});
// Whether the response went through the relay; when it did not, Send again, Copy and Share are the way.
function showRelayed(relayed) {
  $("relayStatus").textContent = relayed ? "Sent to the machine through the relay. Type the number above at the machine." : "It could not be sent through the relay just now. Tap Send again, or copy it to the machine yourself.";
  $("resendResponse").hidden = relayed;
}
$("resendResponse").addEventListener("click", async () => {
  if (!paired) return;
  try { const r = await bridge.request("sendPairing", { id: paired.id }); showRelayed(r.relayed); } catch (e) { say("action", messageOf(e)); }
});
$("copyResponse").addEventListener("click", () => { if (navigator.clipboard) navigator.clipboard.writeText($("responseText").value).catch(() => say("action", "Could not copy: select the text and copy it.")); });
$("shareResponse").addEventListener("click", () => { navigator.share({ text: $("responseText").value }).catch(() => {}); });
// The button is shut until the box is ticked, and says so while it is (announceWhy).
$("wroteCode").addEventListener("change", () => { $("announceBtn").disabled = !$("wroteCode").checked; $("announceWhy").hidden = $("wroteCode").checked; });
$("announceBtn").addEventListener("click", async () => {
  say("action", "");
  announceSaid("announceStatus", "");
  try {
    await bridge.request("announce", { id: paired.id });
    // The recovery code leaves the screen for good.
    $("recoveryCode").textContent = "";
    $("responseText").value = "";
    $("relayStatus").textContent = "";
    const id = paired.id;
    paired = null;
    await loadHordes();
    await pick(id);
  } catch (e) { announceSaid("announceStatus", messageOf(e)); }
});

// --- the account ---

// A refused sign-in's words, by the code word the hosted relay's sign-in puts after #signin-refused
// (a limit says which); anything else is the plain refusal.
const SIGNIN_REFUSED = {
  "": "Sign-in was refused: this account may not use this relay, or the sign-in took too long. Try again.",
  ":busy": "Sign-in was refused: too many sign-ins were started from this network just now. Wait a minute and try again.",
  ":new-accounts": "Sign-in was refused: too many new accounts were made from this network today. Try again tomorrow.",
  ":phones": "Sign-in was refused: this account has the most phones signed in that it may. Sign one out on another phone's Account screen first.",
  ":deleting": "Sign-in was refused: this account is being deleted. Try again in a minute."
};
async function isSignedIn() {
  if (!account) return true;
  const s = await account.session();
  return s.state === "known" && s.value.signedIn === true;
}
function showSignIn() { $("accountBtn").hidden = true; stopPresence(); show("signInView"); }
$("signInBtn").addEventListener("click", () => { if (account) window.location.assign(account.signInUrl()); });
async function openAccount() {
  say("action", "");
  const a = await account.account();
  if (a.state !== "known") { if (a.status === 401) { showSignIn(); return; } say("action", "The account could not be read just now; try again."); return; }
  $("accountWho").textContent = "Signed in as " + (a.value.account.email || "your Google account") + ".";
  showVersion();
  presence = presenceOf(a.value);
  drawPresence();
  const list = $("machineList");
  while (list.firstChild) list.removeChild(list.firstChild);
  const machines = Array.isArray(a.value.machines) ? a.value.machines : [];
  for (const m of machines) {
    const li = document.createElement("li");
    const what = document.createElement("span");
    // The machine's own name, which its grant signed (relay/Pairing.ps1); the key id's start when a
    // registration carries none.
    what.textContent = String(m.horde) + " - " + (typeof m.label === "string" && m.label ? m.label : "machine " + String(m.keyId).slice(0, 12));
    // When the relay last heard from it, quietly; the banner is the bar's (drawPresence).
    const heardOf = presenceOf({ now: a.value.now, machines: [m] })[0];
    if (heardOf) {
      const seen = document.createElement("span");
      seen.className = "seen";
      seen.textContent = heardOf.state === "never" ? " - not heard from yet" : heardOf.state === "offline" ? " - offline since " + dayTime(heardOf.lastSeenAt) : " - heard from " + dayTime(heardOf.lastSeenAt);
      what.appendChild(seen);
    }
    const rm = document.createElement("button");
    rm.type = "button";
    rm.textContent = "Remove";
    rm.addEventListener("click", async () => {
      if (!window.confirm("Remove this machine of " + m.horde + " from your account? It reaches the relay no more until it is paired again.")) return;
      const r = await account.removeMachine(m.keyId);
      if (r.state !== "known") say("action", "The machine could not be removed just now; try again.");
      await openAccount();
    });
    li.appendChild(what);
    li.appendChild(rm);
    list.appendChild(li);
  }
  $("machineEmpty").hidden = machines.length > 0;
  const phoneList = $("phoneList");
  while (phoneList.firstChild) phoneList.removeChild(phoneList.firstChild);
  for (const p of Array.isArray(a.value.phones) ? a.value.phones : []) {
    const li = document.createElement("li");
    const what = document.createElement("span");
    what.textContent = (p.current ? "This phone" : "A phone") + ", signed in " + new Date(Number(p.signedInAt)).toLocaleDateString();
    li.appendChild(what);
    if (!p.current) {
      const out = document.createElement("button");
      out.type = "button";
      out.textContent = "Sign out";
      out.addEventListener("click", async () => {
        if (!window.confirm("Sign that phone out of your account? It reads nothing more until it signs in again.")) return;
        const r = await account.signOutPhone(p.id);
        if (r.state !== "known") say("action", "That phone could not be signed out just now; try again.");
        await openAccount();
      });
      li.appendChild(out);
    }
    phoneList.appendChild(li);
  }
  show("accountView");
}
$("accountBtn").addEventListener("click", openAccount);
$("accountBack").addEventListener("click", () => pick(current || (hordes[0] && hordes[0].id) || ""));
// DELETING THE ACCOUNT: asked twice in plain words, because nothing brings it back.
$("deleteAccountBtn").addEventListener("click", async () => {
  if (!window.confirm("Delete your account on this relay? Every mailbox and what is in it, every machine's registration and every phone's sign-in are deleted at once, for good.")) return;
  if (!window.confirm("Are you sure? This cannot be undone. Your machines must be paired again to use this relay.")) return;
  const r = await account.deleteAccount();
  if (r.state !== "known") { say("action", "The account could not be deleted just now; try again."); return; }
  await lockAll();
  say("action", "The account is deleted.");
  showSignIn();
});
$("signOutBtn").addEventListener("click", async () => {
  await lockAll();
  const r = await account.signOut();
  if (r.state !== "known") say("action", "The relay did not sign this phone out just now; try again.");
  else showSignIn();
});

// --- is the PC there? (the header, THE PC OFFLINE BANNER) ---

const PRESENCE_EVERY_MS = 30000;
let presence = [];
let presenceTimer = null;
// Each run of the loop has its number: a run started while another waits on the relay ends the older one,
// so there is never more than one timer.
let presenceRun = 0;
// The banner's lines as last drawn: a read that changes nothing redraws nothing, so a screen reader does
// not announce the same banner again every PRESENCE_EVERY_MS (the box is role=status).
let presenceDrawn = "";
function drawPresence() {
  const lines = [];
  for (const m of presence) {
    if (m.state !== "offline") continue;
    lines.push(offlineWords(m, dayTime));
  }
  const key = JSON.stringify(lines);
  if (key === presenceDrawn) return;
  presenceDrawn = key;
  const box = $("pcOffline");
  while (box.firstChild) box.removeChild(box.firstChild);
  for (const words of lines) {
    const line = document.createElement("p");
    line.textContent = words;
    box.appendChild(line);
  }
}
async function checkPresence() {
  const run = ++presenceRun;
  clearTimeout(presenceTimer);
  if (!account) return;
  if (document.visibilityState === "visible") {
    const a = await account.account();
    if (run !== presenceRun) return;
    // A failed read keeps the banner as it was (the header).
    if (a.state === "known") presence = presenceOf(a.value);
    drawPresence();
  }
  presenceTimer = setTimeout(checkPresence, PRESENCE_EVERY_MS);
}
function stopPresence() { presenceRun++; clearTimeout(presenceTimer); presence = []; drawPresence(); }

// --- unlocking ---

async function acted(request, args) {
  say("action", "");
  try { await bridge.request(request, args); await loadHordes(); await pick(current); }
  catch (e) { say("action", messageOf(e)); }
}
$("unlockBtn").addEventListener("click", () => acted("unlock", { id: current }));
$("recoverBtn").addEventListener("click", () => { const code = $("recoveryInput").value; $("recoveryInput").value = ""; acted("recover", { id: current, code }); });
$("announceAgain").addEventListener("click", () => acted("announce", { id: current }));
$("forgetBtn").addEventListener("click", () => {
  const h = hordes.find((x) => x.id === current);
  if (!h || !window.confirm("Forget " + h.horde + " on this phone? Its key leaves this phone; the recovery code still opens nothing without pairing again.")) return;
  const id = current;
  current = "";
  dropDoc(id);
  acted("forget", { id }).then(() => pick((hordes[0] && hordes[0].id) || ""));
});
// A LOCK TAKES THE OPENED WORDS OFF THE PAGE (review of a8b732d, finding 2): the horde's list box goes,
// and with it the document's drafts, which live in that box's memory storage - not only hidden behind
// the locked screen. Unlocked again, the list is drawn afresh from the snapshot.
function dropDoc(id) { if (docs[id]) { docs[id].box.remove(); docs[id].cards.remove(); delete docs[id]; } if (id === current) { clearChat(); clearProgress(); showProgressCount(null); clearCards(); openStamps.clear(); $("chatText").value = ""; draftId = ""; } }
async function lockAll() {
  const open = hordes.filter((h) => h.unlocked).map((h) => h.id);
  for (const id of open) { dropDoc(id); await bridge.request("lock", { id }); }
  await loadHordes();
}
$("lockBtn").addEventListener("click", () => { const id = current; dropDoc(id); acted("lock", { id }); });
// LEAVING THE APP FOR A WHILE LOCKS EVERY HORDE, the key and the opened list not left behind a closed
// screen: the timer starts when the page is hidden, so the lock happens while it is hidden (if the
// browser lets the timer run), and is checked again on return in case it did not. On return the list
// is hidden AT ONCE, before that check, so nothing opened shows for a moment on a phone picked up
// after the time. The time is the deployment's (config.json, lockAfterHiddenSeconds; 300 s).
let hiddenAt = 0;
let lockTimer = null;
const lockAfterMs = () => 1000 * ((config && Number.isSafeInteger(config.lockAfterHiddenSeconds) && config.lockAfterHiddenSeconds > 0) ? config.lockAfterHiddenSeconds : 300);
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "hidden") {
    hiddenAt = Date.now();
    clearTimeout(lockTimer);
    lockTimer = setTimeout(() => { lockAll().then(() => pick(current)); }, lockAfterMs());
    return;
  }
  $("doc").hidden = true;
  $("keys").hidden = true;
  $("chat").hidden = true;
  $("progress").hidden = true;
  clearTimeout(lockTimer);
  const expired = hiddenAt && Date.now() - hiddenAt >= lockAfterMs();
  hiddenAt = 0;
  checkForUpdate();
  (expired ? lockAll() : Promise.resolve()).then(resume).then(settleUpdate, settleUpdate);
});

// --- the answering keys ---

const KEYS = { next: { key: "Enter" }, back: { key: "Tab", shift: true }, newline: { key: "Enter", shift: true }, suggest: { key: "Tab" }, park: { key: "b", ctrl: true } };
for (const b of document.querySelectorAll("#keys button[data-key]")) {
  b.addEventListener("pointerdown", (e) => {
    e.preventDefault();
    const k = KEYS[b.getAttribute("data-key")];
    const field = document.activeElement;
    const d = current && docs[current];
    if (!d || !field || !d.box.contains(field)) { if (d) d.doc.takeKeyboard(); return; }
    field.dispatchEvent(new KeyboardEvent("keydown", { key: k.key, shiftKey: k.shift === true, ctrlKey: k.ctrl === true, bubbles: true, cancelable: true }));
  });
}
// The soft keyboard covers the bottom of the layout: the keys stand on top of it.
if (window.visualViewport) {
  const fit = () => { const vv = window.visualViewport; document.documentElement.style.setProperty("--kb", Math.max(0, window.innerHeight - vv.height - vv.offsetTop) + "px"); };
  window.visualViewport.addEventListener("resize", fit);
  window.visualViewport.addEventListener("scroll", fit);
}

// --- start ---

// --- a new version of the app (app-update.js) ---
// The worker takes over at once when a deployment changes it; the page in memory is reloaded ONCE then,
// never on the first install (no worker before) and never over his unsent words: those wait for the
// next safe moment - a send done, the page shown again - under UPDATE_READY_WORDS.
let registration = null;
let hadController = "serviceWorker" in navigator && !!navigator.serviceWorker.controller;
let reloaded = false;
let updateWaiting = false;
let lastUpdateAt = 0;
let sendsInFlight = 0;
function inFlight(p) {
  sendsInFlight++;
  const done = () => { sendsInFlight--; settleUpdate(); };
  p.then(done, done);
  return p;
}
// His unsent words: a send under way, a chat line, a draft the document keeps, a field outside the
// document with words in it, or the pairing screens (the recovery code is shown only once).
function unsentWords() {
  if (sending || photoSending || sendsInFlight > 0 || $("chatText").value.trim() !== "") return true;
  for (const id of Object.keys(docs)) if (draftsHeld(docs[id].storage.getItem(DRAFTS_KEY))) return true;
  const f = document.activeElement;
  if (f && (f.tagName === "TEXTAREA" || f.tagName === "INPUT") && f.type !== "checkbox" && f.value && !$("lists").contains(f)) return true;
  return !$("pairView").hidden || !$("pairedView").hidden;
}
function tryReload(had) {
  const d = reloadDecision({ hadController: had, reloaded, busy: unsentWords() });
  updateWaiting = d === "wait";
  say("update", updateWaiting ? UPDATE_READY_WORDS : "");
  if (d === "reload") { reloaded = true; window.location.reload(); }
}
function settleUpdate() { if (updateWaiting) tryReload(true); }
function checkForUpdate() {
  const now = Date.now();
  if (!registration || !updateDue(lastUpdateAt, now)) return;
  lastUpdateAt = now;
  registration.update().catch(() => { /* offline: asked again when next shown */ });
}
// The worker's own version, asked on a port (sw.js answers it); "" when it does not answer.
function workerVersion() {
  const w = (registration && registration.active) || ("serviceWorker" in navigator ? navigator.serviceWorker.controller : null);
  if (!w || typeof MessageChannel !== "function") return Promise.resolve("");
  return new Promise((resolve) => {
    const ch = new MessageChannel();
    const t = setTimeout(() => resolve(""), 1500);
    ch.port1.onmessage = (ev) => { clearTimeout(t); resolve(ev.data && typeof ev.data.version === "string" ? ev.data.version : ""); };
    w.postMessage({ ask: "version" }, [ch.port2]);
  });
}
function showVersion() {
  const own = config ? config.version : "";
  $("appVersion").textContent = versionWords(own, "");
  workerVersion().then((w) => { $("appVersion").textContent = versionWords(own, w); });
}
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.addEventListener("controllerchange", () => { const had = hadController; hadController = true; tryReload(had); });
  navigator.serviceWorker.register("sw.js").then((r) => { registration = r; lastUpdateAt = Date.now(); }).catch((e) => say("boot", "Offline start is not available: " + messageOf(e)));
}
// Back to the app: still signed in, the horde it was on; signed out at the relay meanwhile (the session
// ended, or another tab signed out), every horde locked and the sign-in screen.
async function resume() {
  if (!(await isSignedIn())) { await lockAll(); showSignIn(); return; }
  checkPresence(); // back to the app: read at once, not 30 s on
  await pick(current);
}
made.then(async () => {
  if (window.location.hash.startsWith("#signin-refused")) {
    say("action", SIGNIN_REFUSED[window.location.hash.slice("#signin-refused".length)] || SIGNIN_REFUSED[""]);
    window.history.replaceState(null, "", window.location.pathname + window.location.search);
  }
  if (!(await isSignedIn())) { showSignIn(); return; }
  $("accountBtn").hidden = !account;
  checkPresence(); // at start-up: the banner from the first moment
  await loadHordes();
  if (!hordes.length) { show("emptyView"); return; }
  await pick(hordes[0].id);
}).catch(() => { /* said above */ });
