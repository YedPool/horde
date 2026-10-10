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
// EVERY TEXT IS SET AS TEXT (textContent, or a field's value).
import { createPhone } from "./phone-core.js";
import { createBridge, deferredBridge } from "../surface/bridge.js";
import { createRelayClient, transportFromConfig } from "./relay-client.js";
import { openStore } from "./store.js";
import { browserAuthenticator } from "./webauthn.js";
import { canScan, scanQr } from "./scan.js";

const $ = (id) => document.getElementById(id);
const LOOK = { fontFamily: "system-ui, sans-serif", textPx: 16, linePx: 24, smallTextPx: 14, smallLinePx: 20 };
const WATCH_MS = 25000;
const notices = { boot: "", relay: "", action: "" };

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
async function makeBridge() {
  config = await fetch("config.json", { cache: "no-store" }).then((r) => { if (!r.ok) throw new Error("this deployment has no config.json"); return r.json(); });
  const transport = transportFromConfig(config, window);
  if (!transport) throw new Error("this deployment names no relay transport this app knows ('" + String(config.transport) + "')");
  const phone = createPhone({ store: await openStore(), authenticator: browserAuthenticator(), relay: createRelayClient(transport), origin: window.location.origin });
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

// --- the screens ---

const VIEWS = ["pairView", "pairedView", "lockedView", "emptyView", "doc"];
function show(view) { for (const v of VIEWS) $(v).hidden = v !== view; $("keys").hidden = view !== "doc"; }

let hordes = [];
let current = "";
const docs = Object.create(null);

function memoryStorage() {
  const m = new Map();
  return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => { m.set(k, String(v)); }, removeItem: (k) => { m.delete(k); } };
}
function docOf(id) {
  if (docs[id]) return docs[id];
  const box = document.createElement("div");
  box.className = "horde-list";
  $("lists").appendChild(box);
  const doc = window.HordeDecisionsDocument.mount(box, {
    topInset: () => $("top").getBoundingClientRect().bottom,
    onChange: showCounts,
    storage: memoryStorage(),
    say: (number, text, wording, answerId) => bridge.request("say", { number, text, wording, id: answerId }),
    act: (number, what, wording, answerId) => bridge.request("act", { number, act: what, wording, id: answerId })
  });
  docs[id] = { box, doc, kinds: false };
  return docs[id];
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
  for (const k of Object.keys(docs)) docs[k].box.hidden = k !== id;
  const rec = await bridge.request("pick", { id });
  render(h, rec);
}

function render(h, rec) {
  if (!h || h.id !== current) return;
  if (!h.unlocked) {
    $("lockedTitle").textContent = h.horde + " is locked";
    $("lockedHint").textContent = h.announced ? "Unlock with your passkey to read and answer." : "This phone has not announced its key to the machine yet: unlock, then announce it.";
    show("lockedView");
    // The locked screen says it is locked: a notice saying so again is dropped.
    say("relay", "");
    showCounts();
    return;
  }
  const d = docOf(h.id);
  d.box.hidden = false;
  show("doc");
  const banners = {
    recovery: "Read only: unlocked with the recovery code. Lock and unlock with the passkey to answer.",
    "read-only": "Read only: this passkey gives no PRF, so answers are never sent from this phone for this horde. Answer at the machine, or pair again with a passkey that has PRF."
  };
  $("mode").hidden = !banners[h.mode];
  $("mode").textContent = banners[h.mode] || "";
  if (!d.kinds) { d.kinds = true; bridge.request("kinds").then((k) => d.doc.setKinds(k)); }
  const did = d.doc.setList(rec);
  say("relay", did === "unread" ? (rec && rec.reason ? rec.reason : "") : "");
  showCounts();
}

bridge.on("list-changed", (rec) => { const h = hordes.find((x) => x.id === current); if (h) render(h, rec); });
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
    $("wroteCode").checked = false;
    $("announceBtn").disabled = true;
    show("pairedView");
    await loadHordes();
  } catch (e) { say("action", messageOf(e)); } finally { $("pairBtn").disabled = false; }
});
$("copyResponse").addEventListener("click", () => { if (navigator.clipboard) navigator.clipboard.writeText($("responseText").value).catch(() => say("action", "Could not copy: select the text and copy it.")); });
$("shareResponse").addEventListener("click", () => { navigator.share({ text: $("responseText").value }).catch(() => {}); });
$("wroteCode").addEventListener("change", () => { $("announceBtn").disabled = !$("wroteCode").checked; });
$("announceBtn").addEventListener("click", async () => {
  say("action", "");
  try {
    await bridge.request("announce", { id: paired.id });
    // The recovery code leaves the screen for good.
    $("recoveryCode").textContent = "";
    $("responseText").value = "";
    const id = paired.id;
    paired = null;
    await loadHordes();
    await pick(id);
  } catch (e) { say("action", messageOf(e)); }
});

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
function dropDoc(id) { if (docs[id]) { docs[id].box.remove(); delete docs[id]; } }
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
  clearTimeout(lockTimer);
  const expired = hiddenAt && Date.now() - hiddenAt >= lockAfterMs();
  hiddenAt = 0;
  (expired ? lockAll() : Promise.resolve()).then(() => pick(current));
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

if ("serviceWorker" in navigator) navigator.serviceWorker.register("sw.js").catch((e) => say("boot", "Offline start is not available: " + messageOf(e)));
made.then(async () => {
  await loadHordes();
  if (!hordes.length) { show("emptyView"); return; }
  await pick(hordes[0].id);
}).catch(() => { /* said above */ });
