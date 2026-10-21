// The phone app in a REAL BROWSER, for surfaces/pwa/test/test-pwa-browser.ps1: headless Chrome, driven
// over its debugging protocol (CDP) with nothing installed - no Playwright, no package: Node's own
// WebSocket and HTTP. What the suites under Node stand in for is real here:
//   - WebAuthn is Chrome's, answered by CDP's VIRTUAL AUTHENTICATOR (WebAuthn.addVirtualAuthenticator:
//     ctap2, internal, user verification, resident keys, and the PRF extension), so the passkey the
//     machine enrolls and every assertion it verifies are made by the browser's own code;
//   - IndexedDB, the service worker, the page's policy line and the module loader are Chrome's;
//   - the keys are real key events (Input.dispatchKeyEvent) and the answering row is pressed by real
//     touch events (Input.dispatchTouchEvent), so list.js's key handling runs as on a phone.
// THE RELAY is the local test transport (relay-client.js, bindingTransport): the page hands each
// operation to a binding this driver adds (Runtime.addBinding), and the driver carries it to the local
// relay's folders (folder-relay.mjs), where a real `horde relay run` is the machine.
// THE SITE is served by a small HTTP server here, on 127.0.0.1, under the origin http://localhost:<port>
// (a secure context, so WebAuthn and the service worker run; Chrome is told localhost is 127.0.0.1).
//
//   node browser-drive.mjs <site folder> <relay root> <browser debugging port>
//
// The first line printed is { ok, value: { origin } }; then one JSON command per line on stdin, one
// JSON answer per line on stdout, as app-phone.mjs. The server ends with the "exit" command or when
// stdin closes.
//
// THE BROWSER IS NOT THIS SCRIPT'S. The suite starts it (test/lib/Browser.ps1, in a kill-on-close job
// of the suite's own, with --host-resolver-rules=MAP localhost 127.0.0.1) and ends it, with its
// profile, in its finally, however this script ends. Until 2026-10-14 this script spawned Chrome and
// ended it in shutdown(), and a script killed first left the browser running (test/lib/Browser.ps1 has
// the measurement). So there is nothing here to clean up on exit or on a signal.
import http from "node:http";
import { readFileSync, existsSync, statSync, writeFileSync, readdirSync } from "node:fs";
import { join, normalize, extname, sep } from "node:path";
import { createInterface } from "node:readline";
import { folderTransport } from "./folder-relay.mjs";

const [, , siteDir, relayRoot, debugPort] = process.argv;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const ascii = (v) => JSON.stringify(v).replace(/[^\x20-\x7e]/g, (ch) => "\\u" + ch.charCodeAt(0).toString(16).padStart(4, "0"));
const say = (v) => process.stdout.write(ascii(v) + "\n");

// --- the site, served ---
const TYPES = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".json": "application/json; charset=utf-8", ".svg": "image/svg+xml", ".png": "image/png" };
const sockets = new Set();
let serving = true;
const server = http.createServer((req, res) => {
  if (!serving) { req.socket.destroy(); return; }
  const url = new URL(req.url, "http://localhost");
  let rel = decodeURIComponent(url.pathname);
  if (rel.endsWith("/")) rel += "index.html";
  const full = normalize(join(siteDir, rel));
  if (!full.startsWith(normalize(siteDir) + sep) || !existsSync(full) || !statSync(full).isFile() || !TYPES[extname(full)]) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { "content-type": TYPES[extname(full)], "cache-control": "no-cache" });
  res.end(readFileSync(full));
});
server.on("connection", (s) => { sockets.add(s); s.on("close", () => sockets.delete(s)); });
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const origin = "http://localhost:" + server.address().port;

// --- Chrome: the suite's, reached on its debugging port (header) ---
if (!/^[0-9]{1,5}$/.test(String(debugPort))) { say({ ok: false, reason: "no browser debugging port was given" }); process.exit(1); }
let targets = [];
for (let i = 0; i < 50 && !targets.some((t) => t.type === "page"); i++) { try { targets = await (await fetch("http://127.0.0.1:" + debugPort + "/json/list")).json(); } catch (e) { /* not yet */ } if (!targets.some((t) => t.type === "page")) await sleep(100); }
const page = targets.find((t) => t.type === "page");
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
let nextId = 1;
const waiting = new Map();
const handlers = new Map();
ws.onmessage = (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && waiting.has(m.id)) { const w = waiting.get(m.id); waiting.delete(m.id); if (m.error) w.reject(new Error(m.error.message)); else w.resolve(m.result); return; }
  for (const fn of handlers.get(m.method) || []) fn(m.params);
};
const cdp = (method, params = {}) => new Promise((resolve, reject) => { const id = nextId++; waiting.set(id, { resolve, reject }); ws.send(JSON.stringify({ id, method, params })); });
const on = (method, fn) => { if (!handlers.has(method)) handlers.set(method, []); handlers.get(method).push(fn); };

const problems = [];
on("Runtime.exceptionThrown", (p) => problems.push("exception: " + (p.exceptionDetails.exception ? p.exceptionDetails.exception.description : p.exceptionDetails.text)));
on("Runtime.consoleAPICalled", (p) => { if (p.type === "error") problems.push("console: " + p.args.map((a) => a.value || a.description || "").join(" ")); });
on("Log.entryAdded", (p) => { if (p.entry.level === "error" || /Content Security Policy/i.test(p.entry.text)) problems.push("log: " + p.entry.text); });

// The binding: the page's relay operations, carried to the local relay's folders.
const relay = folderTransport(relayRoot);
// The relayFail command: every put refused, as a relay that will not take one (the announcement's failure).
let failPuts = false;
// The readFail command: every read and watch refused with the reason given, as a relay that answers 401
// to a phone whose sign-in it no longer takes; "" reads again.
let failReads = "";
on("Runtime.bindingCalled", async (p) => {
  if (p.name !== "hordeRelayBinding") return;
  let answer;
  try {
    const c = JSON.parse(p.payload);
    if (c.op === "put") answer = failPuts ? { state: "unknown", value: null, reason: "the relay is down (a stand-in)" } : await relay.put(c.mailbox, c.key, c.text);
    else if (failReads && (c.op === "get" || c.op === "watch")) answer = { state: "unknown", value: null, reason: failReads };
    else if (c.op === "get") answer = await relay.get(c.mailbox, c.since, c.max);
    else if (c.op === "watch") answer = await relay.watch(c.mailbox, c.since, c.max, Math.min(c.timeoutMs, 3000));
    else if (c.op === "ack") answer = await relay.ack(c.mailbox, c.through);
    else answer = { state: "unknown", value: null, reason: "no such operation" };
    await cdp("Runtime.evaluate", { expression: "window.hordeRelayBindingReply(" + Number(c.id) + "," + JSON.stringify(JSON.stringify(answer)) + ")" });
  } catch (e) { problems.push("binding: " + e.message); }
});

await cdp("Page.enable");
// Every page load counted, so a suite can see that a new version reloads the page once and no more.
let loads = 0;
on("Page.loadEventFired", () => { loads++; });
await cdp("Runtime.enable");
await cdp("Log.enable");
await cdp("Emulation.setDeviceMetricsOverride", { width: 412, height: 915, deviceScaleFactor: 2.625, mobile: true });
await cdp("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 5 });
await cdp("WebAuthn.enable", { enableUI: false });
const auth = await cdp("WebAuthn.addVirtualAuthenticator", { options: { protocol: "ctap2", ctap2Version: "ctap2_1", transport: "internal", hasResidentKey: true, hasUserVerification: true, isUserVerified: true, hasPrf: true, automaticPresenceSimulation: true } });
await cdp("Runtime.addBinding", { name: "hordeRelayBinding" });

async function evaluate(expression, userGesture = false) {
  const r = await cdp("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true, userGesture });
  if (r.exceptionDetails) throw new Error("in the page: " + (r.exceptionDetails.exception ? r.exceptionDetails.exception.description : r.exceptionDetails.text));
  return r.result.value;
}
async function until(expression, timeoutMs = 30000) {
  const end = Date.now() + timeoutMs;
  for (;;) {
    const v = await evaluate(expression).catch(() => null);
    if (v) return v;
    if (Date.now() > end) return null;
    await sleep(100);
  }
}
async function load(url) {
  const loaded = new Promise((r) => { const f = () => r(); on("Page.loadEventFired", f); });
  await cdp("Page.navigate", { url });
  await loaded;
}
// Another tab in front of the app's for ms, then the app's again: Chrome's own visibility, not a stand-in.
// during: the page's visibilityState while the other tab was in front.
async function awayTab(ms) {
  const base = "http://127.0.0.1:" + debugPort + "/json/";
  const other = await (await fetch(base + "new?about:blank", { method: "PUT" })).json();
  await fetch(base + "activate/" + other.id);
  await sleep(Math.min(ms, 300));
  const during = await evaluate("document.visibilityState");
  await sleep(Math.max(0, ms - 300));
  await fetch(base + "activate/" + page.id);
  await fetch(base + "close/" + other.id);
  await sleep(200);
  return { during };
}
// The answer field of the question whose row holds the words given (the first question's without).
const fieldOf = (question) => "(Array.from(document.querySelectorAll('#lists .horde-list:not([hidden]) .hd-qrow')).find((r) => r.textContent.indexOf(" + JSON.stringify(question || "") + ") >= 0).querySelector('textarea.hd-field'))";
// What the lists show: their text, and what stands in every field (a saved answer rests in its field).
const listed = "(document.getElementById('lists').innerText + ' ' + Array.from(document.querySelectorAll('#lists textarea')).map((f) => f.value).join(' '))";
// Everything the lists hold, shown or folded away.
const everything = "document.getElementById('lists').textContent";
// What a locked page still holds of the lists: their boxes, and the words standing in any field.
const leftovers = "({ boxes: document.querySelectorAll('#lists .horde-list').length, fields: Array.from(document.querySelectorAll('#lists textarea')).map((f) => f.value).join('|') })";
const shown = (id) => "(document.getElementById('" + id + "') && !document.getElementById('" + id + "').hidden)";
const notice = "document.getElementById('notice').textContent";
function headOf(mailbox) {
  const dir = join(relayRoot, ...mailbox.split("/"));
  if (!existsSync(dir)) return 0;
  let top = 0;
  for (const n of readdirSync(dir)) { const m = /^([0-9]{16})-|^floor-([0-9]{16})$/.exec(n); if (m) top = Math.max(top, Number(m[1] || m[2])); }
  return top;
}
async function centre(selector) {
  const r = await evaluate("(() => { const b = document.querySelector(" + JSON.stringify(selector) + ").getBoundingClientRect(); return { x: b.left + b.width / 2, y: b.top + b.height / 2 }; })()");
  return r;
}

const commands = {
  async open() { await load(origin + "/app/index.html"); return { empty: !!(await until(shown("emptyView") + " || " + shown("lockedView") + " || " + shown("doc"), 15000)) }; },
  async pair(c) {
    await evaluate("document.getElementById('firstPair').click()", true);
    await until(shown("pairView"));
    await evaluate("document.getElementById('offerText').value = " + JSON.stringify(c.offer) + "; document.getElementById('labelText').value = " + JSON.stringify(c.label) + "; document.getElementById('pairBtn').click()", true);
    const ok = await until(shown("pairedView") + " || (" + notice + ").length > 0", 30000);
    return await evaluate("({ paired: " + shown("pairedView") + ", fingerprint: document.getElementById('fingerprint').textContent, response: document.getElementById('responseText').value, recoveryCode: document.getElementById('recoveryCode').textContent, notice: " + notice + ", waited: " + JSON.stringify(!!ok) + " })");
  },
  // THE ANNOUNCEMENT IS NO BUTTON (2026-10-14): the pairing screen before the machine's word - Finish
  // pairing hidden, the screen waiting - and every button on the page whose words offer to announce.
  async finishState() {
    return await evaluate("({ finishShown: " + shown("finishBtn") + ", finishDisabled: document.getElementById('finishBtn').disabled, waiting: " + shown("confirmWait") + ", why: " + shown("finishWhy") +
      ", whyWords: document.getElementById('finishWhy').textContent, announceButtons: Array.from(document.querySelectorAll('button')).filter((b) => /announce/i.test(b.textContent)).map((b) => b.id || b.textContent) })");
  },
  // Once the machine's confirmed record is in the pairing mailbox: Finish pairing appears, shut while the
  // box is not ticked, and says why; ticked, it opens. The box is left ticked.
  async finishWhy() {
    const appeared = !!(await until(shown("finishBtn"), 30000));
    const before = await commands.finishState();
    await evaluate("document.getElementById('wroteCode').click()", true);
    return { appeared, before, after: await commands.finishState() };
  },
  // One tap on Finish pairing that is expected to fail: what the screen then says.
  async finishTry() {
    await evaluate("document.getElementById('finishStatus').textContent = ''; document.getElementById('finishBtn').click()", true);
    await until(shown("finishStatus") + " && document.getElementById('finishStatus').textContent.length > 0 || " + shown("doc"), 30000);
    return await evaluate("({ status: " + shown("finishStatus") + " ? document.getElementById('finishStatus').textContent : '', paired: " + shown("pairedView") + ", recovery: document.getElementById('recoveryCode').textContent.length > 0, notice: " + notice + " })");
  },
  // The passkey prompts this page has asked for since countPrompts: navigator.credentials.get counted.
  async countPrompts() {
    await evaluate("(() => { const c = navigator.credentials; if (c.__counted) { window.__prompts = 0; return; } const real = c.get.bind(c); window.__prompts = 0; c.get = function (o) { window.__prompts++; return real(o); }; c.__counted = true; })()");
    return { counting: true };
  },
  async prompts() { return await evaluate("window.__prompts === undefined ? -1 : window.__prompts"); },
  // Leave the pairing screen without finishing (Later).
  async pairLater() {
    await evaluate("document.getElementById('pairLater').click()", true);
    await until("!" + shown("pairedView"), 15000);
    return await evaluate("({ paired: " + shown("pairedView") + ", doc: " + shown("doc") + ", locked: " + shown("lockedView") + " })");
  },
  async relayFail(c) { failPuts = c.on === true; return { failPuts }; },
  async readFail(c) { failReads = String(c.reason || ""); return { failReads }; },
  // The notice line, once it holds c.text (or, with c.gone, once it does not); c.hold keeps watching after.
  async noticeHeld(c) {
    const has = "(" + notice + ").indexOf(" + JSON.stringify(c.text) + ") >= 0";
    const ok = await until(c.gone ? "!(" + has + ")" : has, c.ms || 20000);
    // c.hold: left so for that long first - refreshes and redraws meanwhile - to see that the words stay.
    if (ok && c.hold) await sleep(c.hold);
    return { ok: !!ok, notice: await evaluate(notice) };
  },
  // The next passkey prompt refused, as Chrome refuses one the founder cancels (a NotAllowedError), once.
  // In the page and not by the virtual authenticator: told that user verification fails and then that it
  // succeeds again, Chrome's virtual authenticator kept refusing every prompt after (measured 2026-10-11).
  async passkeyRefusesOnce() {
    await evaluate("(() => { const c = navigator.credentials; const real = c.get; c.get = function () { c.get = real; return Promise.reject(new DOMException('The operation either timed out or was not allowed.', 'NotAllowedError')); }; })()");
    return { armed: true };
  },
  // The horde's own view while the machine has not answered: what it says, and that it offers no button.
  async announceBox() { return await evaluate("({ shown: " + shown("announceBox") + ", words: document.getElementById('announceWords').textContent, buttons: document.querySelectorAll('#announceBox button').length })"); },
  // The head of a mailbox of the relay's folders, for a suite to see a put land.
  async head(c) { return headOf(c.mailbox); },
  // THE WAY BETWEEN THE VIEWS: with the page made long and scrolled to its end (as a long chat is), the
  // other view's tab is still on the screen, and a real touch at its centre opens that view.
  async navTouch(c) {
    const tab = c.to === "chat" ? "tabChat" : c.to === "progress" ? "tabProgress" : "tabDecisions";
    await evaluate("document.getElementById('chatLog').style.minHeight = '4000px'; document.getElementById('lists').style.minHeight = '4000px'; window.scrollTo(0, document.documentElement.scrollHeight)");
    await sleep(300);
    const r = await evaluate("(() => { const b = document.getElementById('" + tab + "').getBoundingClientRect(); return { top: b.top, bottom: b.bottom, x: b.left + b.width / 2, y: b.top + b.height / 2, scrolled: window.scrollY, h: window.innerHeight }; })()");
    const inView = r.top >= 0 && r.bottom <= r.h && r.bottom > r.top;
    if (inView) {
      await cdp("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: r.x, y: r.y }] });
      await cdp("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    }
    const opened = !!(await until(shown(c.to === "chat" ? "chat" : c.to === "progress" ? "progress" : "doc"), 10000));
    await evaluate("document.getElementById('chatLog').style.minHeight = ''; document.getElementById('lists').style.minHeight = ''");
    return { inView, opened, scrolled: r.scrolled, top: r.top, bottom: r.bottom };
  },
  // The phone's Back: which view is up after it.
  async back() {
    await evaluate("history.back()");
    await sleep(800);
    return await evaluate("({ chat: " + shown("chat") + ", doc: " + shown("doc") + ", progress: " + shown("progress") + " })");
  },
  // THE PROGRESS LOG: its tab, what it draws, and his place in it.
  async progressState() {
    return await evaluate(`(() => {
      const items = Array.from(document.querySelectorAll('#progressLog .progress-item'));
      const first = items[0], foot = document.getElementById('progressFoot').getBoundingClientRect(), newest = document.getElementById('progressNewest').getBoundingClientRect();
      const mark = document.getElementById('progressNew');
      const bar = document.getElementById('bar').getBoundingClientRect().bottom;
      const onScreen = items.filter((b) => { const r = b.getBoundingClientRect(); return r.bottom > bar && r.top < foot.top; }).map((b) => b.getAttribute('data-id'));
      return {
        shown: !document.getElementById('progress').hidden, doc: !document.getElementById('doc').hidden, chat: !document.getElementById('chat').hidden, keys: !document.getElementById('keys').hidden,
        tab: document.getElementById('tabProgress').textContent, selected: document.getElementById('tabProgress').getAttribute('aria-selected'), count: document.getElementById('progressCount').textContent,
        items: items.length, ids: items.map((b) => b.getAttribute('data-id')), onScreen,
        cardsWhy: document.getElementById('cardsWhy').hidden ? '' : document.getElementById('cardsWhy').textContent,
        firstChips: first ? Array.from(first.querySelectorAll('.progress-head .chip')).map((c) => c.textContent) : [],
        firstTime: first && first.querySelector('.stamp') ? first.querySelector('.stamp').textContent : '',
        firstTitle: first ? first.querySelector('.progress-title').textContent : '', titleWeight: first ? Number(getComputedStyle(first.querySelector('.progress-title')).fontWeight) : 0,
        firstLabels: first ? Array.from(first.querySelectorAll('.progress-text b')).map((b) => b.textContent) : [], firstParagraphs: first ? Array.from(first.querySelectorAll('.progress-text p')).map((p) => p.textContent) : [],
        corrections: items.filter((b) => b.querySelector('.progress-correction')).map((b) => b.getAttribute('data-id') + ' <- ' + b.querySelector('.progress-correction .progress-title').textContent),
        notes: Array.from(document.querySelectorAll('#progressLog .progress-item > .progress-note')).map((n) => n.textContent),
        mark: mark ? { top: Math.round(mark.getBoundingClientRect().top - bar), before: mark.nextElementSibling ? mark.nextElementSibling.getAttribute('data-id') : '' } : null,
        note: document.getElementById('progressNote').hidden ? '' : document.getElementById('progressNote').textContent, empty: !document.getElementById('progressEmpty').hidden,
        footBottom: Math.round(foot.bottom), newestInView: newest.top >= 0 && newest.bottom <= window.innerHeight && newest.width > 0, innerHeight: window.innerHeight, scrollWidth: document.documentElement.scrollWidth, innerWidth: window.innerWidth,
        atEnd: window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2, scrollY: Math.round(window.scrollY)
      };
    })()`);
  },
  async progressTab() {
    await evaluate("document.getElementById('tabProgress').click()", true);
    await until(shown("progress"), 15000);
    await sleep(900);
    return await commands.progressState();
  },
  async progressWait(c) {
    const found = await until("document.getElementById('progressLog').innerText.indexOf(" + JSON.stringify(c.text) + ") >= 0", c.timeoutMs || 30000);
    await sleep(900);
    return { found: !!found, ...(await commands.progressState()) };
  },
  // He reads on: the page scrolled down by screens, as a thumb does, each entry passing over the screen.
  async progressReadOn(c) {
    for (let i = 0; i < c.screens; i++) { await evaluate("window.scrollBy(0, Math.round(window.innerHeight * 0.5))"); await sleep(350); }
    await sleep(900);
    return await commands.progressState();
  },
  // THE CARDS of the Progress tab: which page stands (the cards, or a stream), the cards drawn, and the
  // stream's title and entries.
  async cardsState() {
    return await evaluate(`(() => {
      const $ = (id) => document.getElementById(id);
      const flat = (e) => e.innerText.replace(/\\s+/g, " ").trim();
      const cards = Array.from(document.querySelectorAll("#cardsList .card")).map((c) => ({ lane: c.getAttribute("data-lane"), thrall: c.classList.contains("thrall"), text: flat(c) }));
      // An entry's words whether it is folded or open (a folded entry hides its chips and text, and innerText
      // drops what is hidden): what the stream HOLDS. What can be SEEN is entriesState's.
      const items = Array.from(document.querySelectorAll("#progressLog .progress-item")).map((e) => e.textContent.replace(/\\s+/g, " ").trim());
      return { progress: !$("progress").hidden, cardsPage: !$("cardsPage").hidden, streamPage: !$("streamPage").hidden, title: $("streamTitle").textContent, cards, items: items.length, texts: items, notice: ${notice} };
    })()`);
  },
  // ENTRIES FOLDED AND OPEN (app.js, openEntries): for each entry of the stream, whether it is folded, its
  // line's role and aria-expanded, its height, and what of it can be SEEN - checkVisibility and a box of
  // some height, not only that the node is there (every part of a folded entry is still in the DOM).
  // tagged: the node is the one entriesTag marked, so a redraw that rebuilt the log can be told apart.
  async entriesState() {
    return await evaluate(`(() => {
      const seen = (e) => !!e && e.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true }) && e.getBoundingClientRect().height > 0;
      return Array.from(document.querySelectorAll('#progressLog .progress-item')).map((b) => {
        const line = b.querySelector(':scope > .progress-line'), title = line ? line.querySelector('.progress-title') : null, when = b.querySelector('.progress-when');
        const text = b.querySelector(':scope > .progress-text'), head = b.querySelector(':scope > .progress-head'), stamp = b.querySelector('.progress-head .stamp');
        return { id: b.getAttribute('data-id'), folded: b.classList.contains('collapsed'), role: line ? line.getAttribute('role') : null, expanded: line ? line.getAttribute('aria-expanded') : null,
          focusable: !!line && line.tabIndex === 0, height: Math.round(b.getBoundingClientRect().height), title: title ? title.textContent : '', titleSeen: seen(title),
          titleCut: !!title && title.scrollWidth > title.clientWidth, when: when ? when.textContent : '', whenSeen: seen(when), textSeen: seen(text), headSeen: seen(head),
          stamp: stamp ? stamp.textContent : '', tagged: b.hordeTag === true };
      });
    })()`);
  },
  async entriesTag() {
    return await evaluate("Array.from(document.querySelectorAll('#progressLog .progress-item')).map((b) => { b.hordeTag = true; return 1; }).length");
  },
  // A real touch on one part of one entry: "line" its title, "when" its folded line's time, "text" its body,
  // "head" a chip of its head, "stamp" its head's time stamp. The entry is first brought to the middle of
  // the screen, as a thumb would.
  async entryTouch(c) {
    const sel = "#progressLog .progress-item[data-id=" + JSON.stringify(c.id) + "]";
    const part = { line: " > .progress-line .progress-title", when: " .progress-when", text: " > .progress-text", head: " > .progress-head .chip", stamp: " .progress-head .stamp" }[c.part];
    await evaluate("document.querySelector(" + JSON.stringify(sel) + ").scrollIntoView({ block: 'center' })");
    await sleep(300);
    const at = await centre(sel + part);
    await cdp("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: at.x, y: at.y }] });
    await cdp("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await sleep(500);
    return await commands.entriesState();
  },
  // A real key on one entry's line, focused as the Tab key would: "Enter" or " ".
  async entryKey(c) {
    await evaluate("document.querySelector(" + JSON.stringify("#progressLog .progress-item[data-id=" + JSON.stringify(c.id) + "] > .progress-line") + ").focus()");
    const k = c.key === " " ? { key: " ", code: "Space", windowsVirtualKeyCode: 32, text: " " } : { key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, text: "\r" };
    await cdp("Input.dispatchKeyEvent", { type: "keyDown", ...k });
    await cdp("Input.dispatchKeyEvent", { type: "keyUp", key: k.key, code: k.code, windowsVirtualKeyCode: k.windowsVirtualKeyCode });
    await sleep(400);
    return { scrollY: Math.round(await evaluate("window.scrollY")), entries: await commands.entriesState() };
  },
  async cardsWait(c) {
    const found = await until("document.querySelectorAll('#cardsList .card').length >= " + Number(c.count), c.timeoutMs || 30000);
    await sleep(500);
    return { found: !!found, ...(await commands.cardsState()) };
  },
  // A real touch on a card's line, away from its follow switch: it opens that lane's stream.
  async cardTouch(c) {
    const at = await centre(c.thrall ? "#cardsList .card.thrall .card-line" : "#cardsList .card[data-lane=" + JSON.stringify(c.lane) + "] .card-line");
    await cdp("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: at.x, y: at.y }] });
    await cdp("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await until(shown("streamPage") + " && document.querySelectorAll('#progressLog .progress-item').length > 0", 10000);
    await sleep(900);
    return await commands.cardsState();
  },
  async streamBack() {
    await evaluate("document.getElementById('streamBack').click()", true);
    await until(shown("cardsPage"), 10000);
    await sleep(500);
    return await commands.cardsState();
  },
  // Whether the page says the words given anywhere a line about the relay stands (the notice), in time.
  async noticeWait(c) {
    const found = await until("(" + notice + ").indexOf(" + JSON.stringify(c.text) + ") >= 0 && !document.getElementById('notice').hidden", c.timeoutMs || 15000);
    return { found: !!found, notice: await evaluate(notice) };
  },
  // The instrument's control: words put in the notice as the page's say() puts them, found by noticeWait,
  // then the notice put back as it was.
  async noticeProbe(c) {
    await evaluate("(() => { const n = document.getElementById('notice'); n.dataset.was = n.textContent; n.textContent = " + JSON.stringify(c.text) + "; n.hidden = false; })()");
    const seen = await commands.noticeWait({ text: c.text, timeoutMs: 2000 });
    await evaluate("(() => { const n = document.getElementById('notice'); n.textContent = n.dataset.was || ''; n.hidden = !n.textContent; delete n.dataset.was; })()");
    return seen;
  },
  // A real touch on one of the foot's keys.
  async progressTouch(c) {
    const at = await centre(c.which === "all" ? "#progressAllRead" : "#progressNewest");
    await cdp("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: at.x, y: at.y }] });
    await cdp("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await sleep(1200);
    return await commands.progressState();
  },
  // The one Finish pairing tap that is the passkey prompt.
  async finish() {
    const ticked = await evaluate("document.getElementById('wroteCode').checked");
    if (!ticked) await evaluate("document.getElementById('wroteCode').click()", true);
    const enabled = await evaluate("!document.getElementById('finishBtn').disabled && " + shown("finishBtn"));
    await evaluate("document.getElementById('finishBtn').click()", true);
    await until(shown("doc") + " || (" + notice + ").length > 0 || " + shown("finishStatus"), 30000);
    return await evaluate("({ enabledAfterTick: " + enabled + ", doc: " + shown("doc") + ", notice: " + notice + " + ' ' + document.getElementById('finishStatus').textContent, recoveryCleared: document.getElementById('recoveryCode').textContent === '' })");
  },
  // folded: the words are looked for in everything the lists hold, what stands under a folded heading
  // included (an answered question is out of his list, under the folded "With Thrall"); without it,
  // only in what is shown. The answered are hidden until asked for (decisions/page/list.js, THE ANSWERED
  // ARE HIDDEN UNTIL ASKED FOR), so for folded the page's switch is turned on first, as he would.
  async waitText(c) {
    if (c.folded) await evaluate("(() => { const s = document.querySelector('#lists .horde-list:not([hidden]) .hd-showans'); if (s && s.getAttribute('aria-checked') !== 'true') s.click(); return true; })()");
    const where = c.folded ? everything : listed; const found = await until(where + ".indexOf(" + JSON.stringify(c.text) + ") >= 0", c.timeoutMs || 30000); return { found: !!found, text: await evaluate(where), shown: await evaluate(listed) }; },
  // EACH ORC'S PUBLISHED LIST (published-lists.js): the words the published-lists box of the horde shown holds, waited for
  // until c.text is in them. { found, text, listed }: listed is what the question list shows beside them.
  async waitPublished(c) {
    const box = "(document.querySelector('#lists .published-lists:not([hidden])') || { innerText: '' }).innerText";
    const found = await until(box + ".indexOf(" + JSON.stringify(c.text) + ") >= 0", c.timeoutMs || 30000);
    return { found: !!found, text: await evaluate(box), listed: await evaluate(listed) };
  },
  async answer(c) {
    const before = headOf(c.mailbox);
    await evaluate(fieldOf(c.question) + ".focus()", true);
    await cdp("Input.insertText", { text: c.text });
    if (c.via === "touch") {
      const at = await centre("#keys button[data-key=next]");
      await cdp("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: at.x, y: at.y }] });
      await cdp("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    } else {
      await cdp("Input.dispatchKeyEvent", { type: "keyDown", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, text: "\r" });
      await cdp("Input.dispatchKeyEvent", { type: "keyUp", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13 });
    }
    const end = Date.now() + 30000;
    while (headOf(c.mailbox) === before && Date.now() < end) await sleep(100);
    return { put: headOf(c.mailbox) > before, head: headOf(c.mailbox) };
  },
  // ONE PART of a question of parts, answered by itself: the caret into that part's field (c.part,
  // from 0), the words put in, and a real Enter. { put, head, focusPart }: whether an envelope reached
  // the machine's mailbox, and which part's field has the caret afterwards (-1 for none).
  async answerPart(c) {
    const before = headOf(c.mailbox);
    const row = "Array.from(document.querySelectorAll('#lists .horde-list:not([hidden]) .hd-qrow')).find((r) => r.textContent.indexOf(" + JSON.stringify(c.question || "") + ") >= 0)";
    await evaluate(row + ".querySelectorAll('textarea.hd-partfield')[" + Number(c.part) + "].focus()", true);
    await cdp("Input.insertText", { text: c.text });
    await cdp("Input.dispatchKeyEvent", { type: "keyDown", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, text: "\r" });
    await cdp("Input.dispatchKeyEvent", { type: "keyUp", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13 });
    const end = Date.now() + 30000;
    while (headOf(c.mailbox) === before && Date.now() < end) await sleep(100);
    const focusPart = await evaluate("(function () { var r = " + row + "; return r ? Array.from(r.querySelectorAll('textarea.hd-partfield')).indexOf(document.activeElement) : -1; }())");
    return { put: headOf(c.mailbox) > before, head: headOf(c.mailbox), focusPart };
  },
  // What a question of parts shows of each part: { marks, folded } as drawn, or null when it is not in the list shown.
  async parts(c) {
    return evaluate("(function () { var r = Array.from(document.querySelectorAll('#lists .horde-list:not([hidden]) .hd-group:not(.folded) .hd-qrow')).find((x) => x.textContent.indexOf(" + JSON.stringify(c.question || "") + ") >= 0); if (!r) { return null; } var rows = Array.from(r.querySelectorAll('.hd-part')); return { marks: rows.map((p) => p.querySelector('.hd-partmark').textContent), folded: rows.map((p) => p.classList.contains('answered')) }; }())");
  },
  async newline(c) {
    // Shift+Enter, pressed as real keys, then the answering row's New line pressed by touch: two lines added, nothing sent.
    const before = headOf(c.mailbox);
    await evaluate(fieldOf(c.question) + ".focus()", true);
    await cdp("Input.insertText", { text: "first" });
    await cdp("Input.dispatchKeyEvent", { type: "keyDown", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, modifiers: 8, text: "\r" });
    await cdp("Input.dispatchKeyEvent", { type: "keyUp", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, modifiers: 8 });
    await cdp("Input.insertText", { text: "second" });
    const at = await centre("#keys button[data-key=newline]");
    await cdp("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: at.x, y: at.y }] });
    await cdp("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await cdp("Input.insertText", { text: "third" });
    await sleep(500);
    const value = await evaluate("document.activeElement && document.activeElement.value");
    await evaluate("(() => { const f = document.activeElement; f.value = ''; f.dispatchEvent(new Event('input', { bubbles: true })); })()");
    return { value, sent: headOf(c.mailbox) !== before };
  },
  // The one line above the list for what the snapshot on screen leaves out (app.js): whether it is shown,
  // its words, and everything the page shows as text - so a suite can see that nothing withheld leaked.
  async notShown(c) {
    const want = c.shown ? "!document.getElementById('notShown').hidden" : "document.getElementById('notShown').hidden";
    await until(shown("doc") + " && " + want, c.ms || 20000);
    return await evaluate("({ shown: !document.getElementById('notShown').hidden, words: document.getElementById('notShown').textContent, page: document.body.innerText })");
  },
  // A NEW VERSION OF THE APP (app-update.js). firstInstall: the page marked, then left until its first
  // worker controls it - the mark must survive, as the first install never reloads. newWorker: sw.js
  // changed on the server, as a deployment changes it, and the page told to look (registration.update());
  // with c.draft, words are left in the chat composer first. { reloaded, loads, notice }.
  async firstInstall() {
    await evaluate("window.hordeMark = 1");
    const controlled = !!(await until("!!navigator.serviceWorker.controller", 15000));
    await sleep(1500);
    return { controlled, mark: await evaluate("window.hordeMark === 1"), loads };
  },
  async newWorker(c) {
    await evaluate("window.hordeMark = 1; document.getElementById('chatText').value = " + JSON.stringify(c.draft || ""));
    const before = loads;
    const sw = join(siteDir, "app", "sw.js");
    writeFileSync(sw, readFileSync(sw, "utf8") + "// deployment " + Date.now() + "\n");
    await evaluate("navigator.serviceWorker.getRegistration().then((r) => r.update()).then(() => true)");
    const reloaded = !!(await until("window.hordeMark !== 1", c.ms || 10000));
    if (reloaded) await until(shown("lockedView") + " || " + shown("doc") + " || " + shown("emptyView"), 15000);
    await sleep(2000);
    return { reloaded, loads: loads - before, notice: await evaluate(notice) };
  },
  // The words left by newWorker taken away, then the page hidden and shown: the safe moment.
  async finishDraft() {
    await evaluate("window.hordeMark = 1; document.getElementById('chatText').value = ''");
    const before = loads;
    await evaluate("(() => { for (const v of ['hidden', 'visible']) { Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => v }); Object.defineProperty(document, 'hidden', { configurable: true, get: () => v === 'hidden' }); document.dispatchEvent(new Event('visibilitychange')); } })()");
    const reloaded = !!(await until("window.hordeMark !== 1", 10000));
    if (reloaded) await until(shown("lockedView") + " || " + shown("doc"), 15000);
    await sleep(2000);
    return { reloaded, loads: loads - before, notice: await evaluate(notice) };
  },
  // The version the worker in control says it is (sw.js answers on a port).
  async workerVersion() {
    return await evaluate("new Promise((res) => { const ch = new MessageChannel(); ch.port1.onmessage = (e) => res(e.data.version); navigator.serviceWorker.controller.postMessage({ ask: 'version' }, [ch.port2]); setTimeout(() => res(''), 3000); })");
  },
  // THE PAGE'S CLOCK MOVED (test-pwa-browser.ps1 section 15): Date.now answers ms ahead of the real clock,
  // so the app's checks on return of how long it was hidden see minutes that were never waited. 0 puts the
  // real clock back. The page's own time of when it was hidden was taken by the real clock.
  async clock(c) {
    const ms = Number(c.ms) || 0;
    return await evaluate("(() => { if (!window.__realNow) window.__realNow = Date.now.bind(Date); const off = " + ms + "; Date.now = off ? () => window.__realNow() + off : window.__realNow; return off; })()");
  },
  // config.json as the site serves it now, fetched by the page past every cache.
  async servedConfig() { return await evaluate("fetch('config.json', { cache: 'no-store' }).then((r) => r.json())"); },
  async reload() { await load(origin + "/app/index.html"); return { locked: !!(await until(shown("lockedView"), 15000)), controlled: await evaluate("!!navigator.serviceWorker.controller") }; },
  async unlock() {
    const was = await evaluate(notice);
    await evaluate("document.getElementById('unlockBtn').click()", true);
    await until(shown("doc") + " || (" + notice + ") !== " + JSON.stringify(was), 30000);
    return { doc: await evaluate(shown("doc")), notice: await evaluate(notice) };
  },
  async recover(c) {
    const was = await evaluate(notice);
    await evaluate("document.querySelector('#lockedView details').open = true; document.getElementById('recoveryInput').value = " + JSON.stringify(c.code) + "; document.getElementById('recoverBtn').click()", true);
    await until(shown("doc") + " || (" + notice + ") !== " + JSON.stringify(was), 30000);
    return await evaluate("({ doc: " + shown("doc") + ", mode: document.getElementById('mode').hidden ? '' : document.getElementById('mode').textContent, notice: " + notice + " })");
  },
  // THE PROGRESS LOG IS COUNTED IN THE SAME TURN AS THE TOUCH, before and after it. Two places in the
  // page empty the log: the lock itself, at once, and the redraw that follows when the bridge answers
  // that the horde is locked. Counted only once the locked screen was up, the second hid the loss of
  // the first (mutant progress-left-on-a-locked-page survived, 2026-10-13). Nothing the bridge says
  // can be drawn before this expression returns, so logAtOnce is the lock's own doing.
  async lock() {
    const at = await evaluate("(() => { const n = () => document.querySelectorAll('#progressLog .progress-item').length; const before = n(); document.getElementById('lockBtn').click(); return { logBefore: before, logAtOnce: n() }; })()", true);
    return { locked: !!(await until(shown("lockedView"), 10000)), ...(await evaluate(leftovers)), ...at };
  },
  // The page told it is hidden (as a phone's screen going off or the app switched away does), then
  // left so for ms: what is still on it.
  async hide(c) {
    await evaluate("Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' }); Object.defineProperty(document, 'hidden', { configurable: true, get: () => true }); document.dispatchEvent(new Event('visibilitychange'))");
    await sleep(c.ms);
    return await evaluate("({ tabs: document.getElementById('tabs').textContent, " + leftovers.slice(2, -2) + " })");
  },
  // The page told it is visible again: whether the list was hidden in the same moment, before any
  // lock check could run.
  async show() {
    return await evaluate("(() => { Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'visible' }); Object.defineProperty(document, 'hidden', { configurable: true, get: () => false }); document.dispatchEvent(new Event('visibilitychange')); return { docHiddenAtOnce: document.getElementById('doc').hidden }; })()");
  },
  async screenshot(c) {
    const shot = await cdp("Page.captureScreenshot", { format: "png" });
    writeFileSync(c.path, Buffer.from(shot.data, "base64"));
    return await evaluate("({ scrollWidth: document.documentElement.scrollWidth, innerWidth: window.innerWidth, keysBottom: document.getElementById('keys').getBoundingClientRect().bottom, innerHeight: window.innerHeight })");
  },
  async dump() {
    return await evaluate("new Promise((res, rej) => { const o = indexedDB.open('horde-phone'); o.onerror = () => rej(o.error); o.onsuccess = () => { const t = o.result.transaction('kv').objectStore('kv').getAll(); t.onsuccess = () => res(JSON.stringify(t.result, (k, v) => (v instanceof CryptoKey ? { cryptoKey: v.type, extractable: v.extractable } : v))); t.onerror = () => rej(t.error); }; })");
  },
  async caches() { return await evaluate("(async () => { const out = {}; for (const n of await caches.keys()) { const c = await caches.open(n); out[n] = (await c.keys()).map((r) => new URL(r.url).pathname); } return out; })()"); },
  async serve(c) { serving = c.on === true; if (!serving) for (const s of sockets) s.destroy(); return { serving }; },
  async credentials() { const r = await cdp("WebAuthn.getCredentials", { authenticatorId: auth.authenticatorId }); return r.credentials.map((x) => ({ rpId: x.rpId, signCount: x.signCount, resident: x.isResidentCredential })); },
  // THE PASSKEY PROMPTS, COUNTED (the unlocked session, test-pwa-browser.ps1 section 14): the virtual
  // authenticator's signature counter, summed over its credentials, goes up by one with every assertion
  // Chrome's WebAuthn makes - each one a prompt on a real phone.
  async assertions() { const r = await cdp("WebAuthn.getCredentials", { authenticatorId: auth.authenticatorId }); return r.credentials.reduce((n, x) => n + x.signCount, 0); },
  // The page's unlocked sessions, as the bridge answers them (bridge.js, sessions), and the Account
  // screen's line and the notice as the page draws them.
  async sessions() { return await evaluate("(async () => ({ list: await window.HordeBridge.request('sessions'), account: document.getElementById('sessionWords').innerText, notice: " + notice + " }))()"); },
  // WHAT THE BROWSER GIVES when the app is left (the brief: measure it, and say it). Another tab brought to
  // the front is what Chrome has for another app or the screen going off; its lifecycle's frozen state is
  // what it does to a page in the background for long. Each event the page hears is recorded.
  async visibilityProbe() {
    await evaluate("(() => { window.__heard = []; document.addEventListener('visibilitychange', () => window.__heard.push('visibilitychange:' + document.visibilityState)); window.addEventListener('pagehide', (e) => window.__heard.push('pagehide:' + e.persisted)); document.addEventListener('freeze', () => window.__heard.push('freeze')); document.addEventListener('resume', () => window.__heard.push('resume')); })()");
    let frozen = "";
    try { await cdp("Page.setWebLifecycleState", { state: "frozen" }); await sleep(200); await cdp("Page.setWebLifecycleState", { state: "active" }); } catch (e) { frozen = e.message; }
    // Frozen leaves the page hidden (measured 2026-10-14: a visibilitychange to hidden before freeze, and
    // it stays hidden after resume), so the other tab comes second: its return brings the page to the front.
    const away = await awayTab(800);
    return { during: away.during, after: await evaluate("({ state: document.visibilityState, heard: window.__heard.slice() })"), frozenRefused: frozen };
  },
  // Away for ms by another tab in front (visibilityProbe), then back: what the page said while away.
  async away(c) { const a = await awayTab(Number(c.ms) || 1000); return { during: a.during, state: await evaluate("document.visibilityState") }; },
  async problems() { return problems.slice(); },
  // THE CHAT: its tab, its log, and its composer driven by real keys and a real touch.
  async chatTab(c) {
    await evaluate("document.getElementById('" + (c.which === "decisions" ? "tabDecisions" : "tabChat") + "').click()", true);
    await until(shown(c.which === "decisions" ? "doc" : "chat"), 15000);
    return await evaluate("({ chat: " + shown("chat") + ", doc: " + shown("doc") + ", keys: " + shown("keys") + ", log: document.getElementById('chatLog').innerText })");
  },
  async chatWait(c) {
    const found = await until("document.getElementById('chatLog').innerText.indexOf(" + JSON.stringify(c.text) + ") >= 0", c.timeoutMs || 30000);
    return { found: !!found, log: await evaluate("document.getElementById('chatLog').innerText") };
  },
  async chatState() {
    return await evaluate("({ mode: document.getElementById('chatMode').hidden ? '' : document.getElementById('chatMode').textContent, disabled: document.getElementById('chatText').disabled, items: document.querySelectorAll('#chatLog .chat-item').length, log: document.getElementById('chatLog').innerText })");
  },
  // WHEN IT WAS SAID: every item's stamp and the day dividers, as drawn; then a real touch on the first
  // stamp (the exact time opens), the log drawn again by a refresh meanwhile (it stays open), and a second
  // touch (the short time is back).
  async chatStamps() {
    const read = "({ items: document.querySelectorAll('#chatLog .chat-item').length, stamps: Array.from(document.querySelectorAll('#chatLog .chat-item .stamp')).map((s) => s.textContent), titles: Array.from(document.querySelectorAll('#chatLog .chat-item .stamp')).map((s) => s.title), days: Array.from(document.querySelectorAll('#chatLog .chat-day')).map((d) => d.textContent), first: document.getElementById('chatLog').firstElementChild ? document.getElementById('chatLog').firstElementChild.className : '' })";
    const before = await evaluate(read);
    const touch = async () => {
      const at = await centre("#chatLog .chat-item .stamp");
      await cdp("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: at.x, y: at.y }] });
      await cdp("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
      await sleep(400);
      return await evaluate("document.querySelector('#chatLog .chat-item .stamp').textContent");
    };
    const tapped = await touch();
    await evaluate("window.HordeBridge.request('refresh')");
    await sleep(400);
    const kept = await evaluate("document.querySelector('#chatLog .chat-item .stamp').textContent");
    const again = await touch();
    return { ...before, tapped, kept, again };
  },
  async chatNewline(c) {
    const before = headOf(c.mailbox);
    await evaluate("document.getElementById('chatText').focus()", true);
    await cdp("Input.insertText", { text: "one" });
    await cdp("Input.dispatchKeyEvent", { type: "keyDown", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, modifiers: 8, text: "\r" });
    await cdp("Input.dispatchKeyEvent", { type: "keyUp", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, modifiers: 8 });
    await cdp("Input.insertText", { text: "two" });
    const at = await centre("#chatNewline");
    await cdp("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: at.x, y: at.y }] });
    await cdp("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await cdp("Input.insertText", { text: "three" });
    await sleep(500);
    const value = await evaluate("document.getElementById('chatText').value");
    await evaluate("document.getElementById('chatText').value = ''");
    return { value, sent: headOf(c.mailbox) !== before };
  },
  async chatSend(c) {
    const before = headOf(c.mailbox);
    await evaluate("document.getElementById('chatText').focus()", true);
    await cdp("Input.insertText", { text: c.text });
    if (c.via === "touch") {
      const at = await centre("#chatSend");
      await cdp("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: at.x, y: at.y }] });
      await cdp("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    } else {
      await cdp("Input.dispatchKeyEvent", { type: "keyDown", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, text: "\r" });
      await cdp("Input.dispatchKeyEvent", { type: "keyUp", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13 });
    }
    const end = Date.now() + (c.expectNone ? 2000 : 30000);
    while (headOf(c.mailbox) === before && Date.now() < end) await sleep(100);
    return { put: headOf(c.mailbox) > before, left: await evaluate("document.getElementById('chatText').value"), notice: await evaluate(notice) };
  },
  // A PHOTO from the chat's Photo button: a real touch on it must open Chrome's file chooser (caught here,
  // never shown), and the file on disk at c.path is then given to the page's file field as a person's pick
  // would be (DOM.setFileInputFiles fires its change). Chrome decodes, draws and encodes it; Chrome's
  // passkey signs the manifest. { chooser, put, prompts, thumbs, notice }.
  async chatPhoto(c) {
    const before = headOf(c.mailbox);
    const signsBefore = (await cdp("WebAuthn.getCredentials", { authenticatorId: auth.authenticatorId })).credentials.reduce((s, x) => s + x.signCount, 0);
    await cdp("Page.setInterceptFileChooserDialog", { enabled: true });
    let chooser = false;
    on("Page.fileChooserOpened", () => { chooser = true; });
    const at = await centre("#chatPhoto");
    await cdp("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: at.x, y: at.y }] });
    await cdp("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    for (let i = 0; i < 50 && !chooser; i++) await sleep(100);
    await cdp("Page.setInterceptFileChooserDialog", { enabled: false });
    const field = await cdp("Runtime.evaluate", { expression: "document.getElementById('chatPhotoFile')" });
    await cdp("DOM.enable");
    await cdp("DOM.setFileInputFiles", { files: [c.path], objectId: field.result.objectId });
    const end = Date.now() + (c.expectNone ? 3000 : 60000);
    while (headOf(c.mailbox) < before + (c.parts || 2) && Date.now() < end) await sleep(100);
    await sleep(c.expectNone ? 0 : 500);
    const signsAfter = (await cdp("WebAuthn.getCredentials", { authenticatorId: auth.authenticatorId })).credentials.reduce((s, x) => s + x.signCount, 0);
    return { chooser, put: headOf(c.mailbox) - before, prompts: signsAfter - signsBefore, thumbs: await evaluate("document.querySelectorAll('#chatLog canvas.chat-photo').length"), notice: await evaluate(notice) };
  },
  // A PHOTO THAT ARRIVES IN THE CHAT WITHOUT HIS TOUCH HERE - as one sent from another window of the app
  // would: the JPEG at c.path handed straight to the bridge (bridge.js, chat-photo), so the page draws it
  // on the bridge's chat-changed and nothing of app.js's own send runs. Then where the chat stands.
  async chatPhotoBehind(c) {
    const before = headOf(c.mailbox);
    const bytes = Array.from(readFileSync(c.path));
    const r = await evaluate("window.HordeBridge.request('chat-photo', { bytes: new Uint8Array(" + JSON.stringify(bytes) + "), id: " + JSON.stringify(c.id) + " })");
    const end = Date.now() + 15000;
    while (headOf(c.mailbox) < before + 2 && Date.now() < end) await sleep(100);
    await sleep(500);
    return { sent: r, put: headOf(c.mailbox) - before, place: await commands.chatPlace() };
  },
  // SEND AGAIN on a photo the PC did not take in its hour: shown or not, then a real touch on it, and what
  // was put, and how many Send again are left. { shown, put, prompts, left, notice }.
  async chatSendAgain(c) {
    const shown = await evaluate("(() => { const b = document.querySelector('#chatLog .chat-again'); if (!b) return 0; b.scrollIntoView({ block: 'center' }); return document.querySelectorAll('#chatLog .chat-again').length; })()");
    if (!shown) return { shown: 0, put: 0, prompts: 0, notice: await evaluate(notice) };
    await sleep(300);
    const before = headOf(c.mailbox);
    const signsBefore = (await cdp("WebAuthn.getCredentials", { authenticatorId: auth.authenticatorId })).credentials.reduce((s, x) => s + x.signCount, 0);
    const at = await centre("#chatLog .chat-again");
    await cdp("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: at.x, y: at.y }] });
    await cdp("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    const end = Date.now() + 30000;
    while (headOf(c.mailbox) < before + 2 && Date.now() < end) await sleep(100);
    await sleep(500);
    const signsAfter = (await cdp("WebAuthn.getCredentials", { authenticatorId: auth.authenticatorId })).credentials.reduce((s, x) => s + x.signCount, 0);
    return { shown, put: headOf(c.mailbox) - before, prompts: signsAfter - signsBefore, left: await evaluate("document.querySelectorAll('#chatLog .chat-again').length"), notice: await evaluate(notice) };
  },
  // WHERE THE CHAT STANDS (chat-scroll.js; the founder, 2026-10-15): how far the window is from the bottom,
  // whether the newest message stands clear of the composer, the first message on his screen, and the
  // Jump to latest button - shown, its words, its size and where it stands - and what the live region says.
  async chatPlace() {
    return await evaluate(`(() => {
      const $ = (id) => document.getElementById(id);
      const root = document.documentElement;
      const items = Array.from(document.querySelectorAll('#chatLog .chat-item'));
      const top = $('bar').getBoundingClientRect().bottom;
      const first = items.find((el) => el.getBoundingClientRect().bottom > top);
      const last = items[items.length - 1];
      const j = $('chatJump'), jr = j.getBoundingClientRect(), tr = $('chatText').getBoundingClientRect(), cr = $('chatCompose').getBoundingClientRect();
      const a = document.activeElement;
      return { y: window.scrollY, dist: Math.round(root.scrollHeight - (window.scrollY + window.innerHeight)), items: items.length,
        lastBottom: last ? last.getBoundingClientRect().bottom : 0, lastText: last ? last.querySelector('.chat-text').textContent : '', composeTop: cr.top,
        firstKey: first ? first.dataset.key : '', firstTop: first ? first.getBoundingClientRect().top : 0,
        jumpShown: !j.hidden && jr.height > 0, jumpText: j.textContent, jumpName: j.getAttribute('aria-label') || j.textContent, jumpTag: j.tagName, jumpType: j.type,
        jumpTop: jr.top, jumpBottom: jr.bottom, jumpLeft: jr.left, jumpRight: jr.right, jumpH: jr.height, jumpW: jr.width, textTop: tr.top,
        news: $('chatNews').textContent, newsLive: $('chatNews').getAttribute('aria-live'), newsHidden: $('chatNews').hidden,
        focus: a ? a.id : '', focusVisible: !!(a && a.matches(':focus-visible')), outline: a ? getComputedStyle(a).outlineStyle + ' ' + getComputedStyle(a).outlineWidth : '' };
    })()`);
  },
  // The chat opened from the questions, with the window first put at the top of the page, or part way
  // down a long one: the window the chat inherits is all the old code looked at.
  async chatOpen(c) {
    await evaluate("document.getElementById('tabDecisions').click()", true);
    await until(shown("doc"), 15000);
    await evaluate("document.getElementById('lists').style.minHeight = '4000px'");
    await sleep(200);
    await evaluate(c.from === "middle" ? "window.scrollTo(0, 2000)" : "window.scrollTo(0, 0)");
    await sleep(300);
    const inherited = await evaluate("window.scrollY");
    await evaluate("document.getElementById('tabChat').click()", true);
    await until(shown("chat"), 15000);
    await until("document.querySelectorAll('#chatLog .chat-item').length > 0", 15000);
    await sleep(800);
    await evaluate("document.getElementById('lists').style.minHeight = ''");
    return { inherited, ...(await commands.chatPlace()) };
  },
  // The window put dist pixels above the bottom of the page (or at its top), as a finger leaves it.
  async chatScrollTo(c) {
    await evaluate(c.to === "top" ? "window.scrollTo(0, 0)" : "window.scrollTo(0, document.documentElement.scrollHeight - window.innerHeight - " + Number(c.dist) + ")");
    await sleep(400);
    return await commands.chatPlace();
  },
  // A refresh of everything (bridge.js refresh: the chat drawn again from its record), while he stays put.
  async chatRefresh() {
    await evaluate("window.HordeBridge.request('refresh')");
    await sleep(800);
    return await commands.chatPlace();
  },
  // A real touch on Jump to latest.
  async chatJumpTouch() {
    const at = await centre("#chatJump");
    await cdp("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: at.x, y: at.y }] });
    await cdp("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await sleep(500);
    return await commands.chatPlace();
  },
  // THE KEYBOARD: from the composer's field, a real Shift+Tab; where the focus lands and whether its ring
  // shows; then a real key (Enter or Space) on it.
  async chatJumpKey(c) {
    await evaluate("document.getElementById('chatText').focus()", true);
    await cdp("Input.dispatchKeyEvent", { type: "keyDown", key: "Tab", code: "Tab", windowsVirtualKeyCode: 9, modifiers: 8 });
    await cdp("Input.dispatchKeyEvent", { type: "keyUp", key: "Tab", code: "Tab", windowsVirtualKeyCode: 9, modifiers: 8 });
    await sleep(200);
    const focused = await commands.chatPlace();
    if (c.key === "Space") {
      await cdp("Input.dispatchKeyEvent", { type: "keyDown", key: " ", code: "Space", windowsVirtualKeyCode: 32, text: " " });
      await cdp("Input.dispatchKeyEvent", { type: "keyUp", key: " ", code: "Space", windowsVirtualKeyCode: 32 });
    } else {
      await cdp("Input.dispatchKeyEvent", { type: "keyDown", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, text: "\r" });
      await cdp("Input.dispatchKeyEvent", { type: "keyUp", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13 });
    }
    await sleep(500);
    return { focused, after: await commands.chatPlace() };
  },
  // The button's words against its face, light and dark (WCAG contrast ratio), with the page's own colours.
  async chatContrast() {
    const ratio = `(() => {
      const j = document.getElementById('chatJump');
      const was = j.hidden; j.hidden = false;
      const rgb = (s) => s.match(/[0-9.]+/g).slice(0, 3).map(Number);
      const lum = (c) => { const [r, g, b] = c.map((v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }); return 0.2126 * r + 0.7152 * g + 0.0722 * b; };
      const s = getComputedStyle(j);
      const a = lum(rgb(s.color)), b = lum(rgb(s.backgroundColor));
      j.hidden = was;
      return { color: s.color, background: s.backgroundColor, ratio: Math.round(100 * (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05)) / 100 };
    })()`;
    await cdp("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: "light" }] });
    const light = await evaluate(ratio);
    await cdp("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: "dark" }] });
    const dark = await evaluate(ratio);
    await cdp("Emulation.setEmulatedMedia", { features: [] });
    return { light, dark };
  },
  async chatShot(c) {
    const shot = await cdp("Page.captureScreenshot", { format: "png" });
    writeFileSync(c.path, Buffer.from(shot.data, "base64"));
    return await evaluate("({ scrollWidth: document.documentElement.scrollWidth, innerWidth: window.innerWidth, composeBottom: document.getElementById('chatCompose').getBoundingClientRect().bottom, innerHeight: window.innerHeight })");
  }
};

async function shutdown() {
  // The browser is the suite's to end (header); this script ends only what it started: its server.
  server.close();
}

say({ ok: true, value: { origin } });
const rl = createInterface({ input: process.stdin });
for await (const line of rl) {
  if (!line.trim()) continue;
  let c;
  // A leading U+FEFF: Windows PowerShell 5.1 under a UTF-8 console (code page 65001) writes a BOM
  // first on a redirected stdin, so the first command would not parse.
  try { c = JSON.parse(line.replace(/^\uFEFF/, "")); } catch (x) { say({ ok: false, reason: "not JSON" }); continue; }
  if (c.cmd === "exit") break;
  try {
    if (!commands[c.cmd]) throw new Error("no such command: " + c.cmd);
    say({ ok: true, value: await commands[c.cmd](c) });
  } catch (x) { say({ ok: false, reason: x && x.message ? x.message : String(x) }); }
}
await shutdown();
say({ ok: true, value: "closed" });
process.exit(0);
