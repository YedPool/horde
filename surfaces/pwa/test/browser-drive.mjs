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
//   node browser-drive.mjs <site folder> <relay root> <chrome.exe> <profile folder>
//
// The first line printed is { ok, value: { origin } }; then one JSON command per line on stdin, one
// JSON answer per line on stdout, as app-phone.mjs. Chrome and the server end with the "exit" command
// or when stdin closes.
import http from "node:http";
import { spawn, execFileSync } from "node:child_process";
import { readFileSync, existsSync, statSync, writeFileSync, readdirSync } from "node:fs";
import { join, normalize, extname, sep } from "node:path";
import { createInterface } from "node:readline";
import { folderTransport } from "./folder-relay.mjs";

const [, , siteDir, relayRoot, chromePath, profileDir] = process.argv;
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

// --- Chrome ---
const chrome = spawn(chromePath, ["--headless=new", "--remote-debugging-port=0", "--user-data-dir=" + profileDir, "--no-first-run", "--no-default-browser-check", "--disable-extensions",
  "--disable-background-networking", "--disable-sync", "--disable-component-update", "--host-resolver-rules=MAP localhost 127.0.0.1", "--window-size=412,915", "about:blank"], { stdio: "ignore" });
let portFile = join(profileDir, "DevToolsActivePort");
for (let i = 0; i < 200 && !existsSync(portFile); i++) await sleep(100);
if (!existsSync(portFile)) { say({ ok: false, reason: "Chrome did not open its debugging port" }); process.exit(1); }
const debugPort = readFileSync(portFile, "utf8").split(/\r?\n/)[0];
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
on("Runtime.bindingCalled", async (p) => {
  if (p.name !== "hordeRelayBinding") return;
  let answer;
  try {
    const c = JSON.parse(p.payload);
    if (c.op === "put") answer = failPuts ? { state: "unknown", value: null, reason: "the relay is down (a stand-in)" } : await relay.put(c.mailbox, c.key, c.text);
    else if (c.op === "get") answer = await relay.get(c.mailbox, c.since, c.max);
    else if (c.op === "watch") answer = await relay.watch(c.mailbox, c.since, c.max, Math.min(c.timeoutMs, 3000));
    else if (c.op === "ack") answer = await relay.ack(c.mailbox, c.through);
    else answer = { state: "unknown", value: null, reason: "no such operation" };
    await cdp("Runtime.evaluate", { expression: "window.hordeRelayBindingReply(" + Number(c.id) + "," + JSON.stringify(JSON.stringify(answer)) + ")" });
  } catch (e) { problems.push("binding: " + e.message); }
});

await cdp("Page.enable");
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
// The answer field of the question whose row holds the words given (the first question's without).
const fieldOf = (question) => "(Array.from(document.querySelectorAll('#lists .horde-list:not([hidden]) .hd-qrow')).find((r) => r.textContent.indexOf(" + JSON.stringify(question || "") + ") >= 0).querySelector('textarea.hd-field'))";
// What the lists show: their text, and what stands in every field (a saved answer rests in its field).
const listed = "(document.getElementById('lists').innerText + ' ' + Array.from(document.querySelectorAll('#lists textarea')).map((f) => f.value).join(' '))";
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
  // THE ANNOUNCEMENT (the founder's first live use, 2026-10-11): why its button is shut, before and after
  // the box is ticked; then the box is left ticked.
  async announceWhy() {
    const read = "({ why: " + shown("announceWhy") + ", words: document.getElementById('announceWhy').textContent, disabled: document.getElementById('announceBtn').disabled })";
    const before = await evaluate(read);
    await evaluate("document.getElementById('wroteCode').click()", true);
    return { before, after: await evaluate(read) };
  },
  // One tap on the pairing screen's announce button that is expected to fail: what the screen then says.
  async announceTry() {
    const was = await evaluate("document.getElementById('announceStatus').textContent");
    await evaluate("document.getElementById('announceStatus').textContent = ''; document.getElementById('announceBtn').click()", true);
    await until(shown("announceStatus") + " && document.getElementById('announceStatus').textContent.length > 0 || " + shown("doc"), 30000);
    return await evaluate("({ status: " + shown("announceStatus") + " ? document.getElementById('announceStatus').textContent : '', paired: " + shown("pairedView") + ", recovery: document.getElementById('recoveryCode').textContent.length > 0, notice: " + notice + ", was: " + JSON.stringify(was) + " })");
  },
  async relayFail(c) { failPuts = c.on === true; return { failPuts }; },
  // The next passkey prompt refused, as Chrome refuses one the founder cancels (a NotAllowedError), once.
  // In the page and not by the virtual authenticator: told that user verification fails and then that it
  // succeeds again, Chrome's virtual authenticator kept refusing every prompt after (measured 2026-10-11).
  async passkeyRefusesOnce() {
    await evaluate("(() => { const c = navigator.credentials; const real = c.get; c.get = function () { c.get = real; return Promise.reject(new DOMException('The operation either timed out or was not allowed.', 'NotAllowedError')); }; })()");
    return { armed: true };
  },
  // The horde's own view while the machine has not answered: its offer to announce again.
  async announceBox() { return await evaluate("({ shown: " + shown("announceBox") + ", words: document.getElementById('announceWords').textContent, status: " + shown("announceNowStatus") + " ? document.getElementById('announceNowStatus').textContent : '' })"); },
  async announceNow(c) {
    const before = headOf(c.mailbox);
    await evaluate("document.getElementById('announceNow').click()", true);
    await until(shown("announceNowStatus"), 30000);
    const end = Date.now() + 10000;
    while (headOf(c.mailbox) === before && Date.now() < end) await sleep(100);
    return { put: headOf(c.mailbox) > before, status: await evaluate("document.getElementById('announceNowStatus').textContent") };
  },
  // THE WAY BETWEEN THE VIEWS: with the page made long and scrolled to its end (as a long chat is), the
  // other view's tab is still on the screen, and a real touch at its centre opens that view.
  async navTouch(c) {
    const tab = c.to === "chat" ? "tabChat" : "tabDecisions";
    await evaluate("document.getElementById('chatLog').style.minHeight = '4000px'; document.getElementById('lists').style.minHeight = '4000px'; window.scrollTo(0, document.documentElement.scrollHeight)");
    await sleep(300);
    const r = await evaluate("(() => { const b = document.getElementById('" + tab + "').getBoundingClientRect(); return { top: b.top, bottom: b.bottom, x: b.left + b.width / 2, y: b.top + b.height / 2, scrolled: window.scrollY, h: window.innerHeight }; })()");
    const inView = r.top >= 0 && r.bottom <= r.h && r.bottom > r.top;
    if (inView) {
      await cdp("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: r.x, y: r.y }] });
      await cdp("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    }
    const opened = !!(await until(shown(c.to === "chat" ? "chat" : "doc"), 10000));
    await evaluate("document.getElementById('chatLog').style.minHeight = ''; document.getElementById('lists').style.minHeight = ''");
    return { inView, opened, scrolled: r.scrolled, top: r.top, bottom: r.bottom };
  },
  // The phone's Back: which view is up after it.
  async back() {
    await evaluate("history.back()");
    await sleep(800);
    return await evaluate("({ chat: " + shown("chat") + ", doc: " + shown("doc") + " })");
  },
  async announce() {
    const ticked = await evaluate("document.getElementById('wroteCode').checked");
    if (!ticked) await evaluate("document.getElementById('wroteCode').click()", true);
    const enabled = await evaluate("!document.getElementById('announceBtn').disabled");
    await evaluate("document.getElementById('announceBtn').click()", true);
    await until(shown("doc") + " || (" + notice + ").length > 0 || " + shown("announceStatus"), 30000);
    return await evaluate("({ enabledAfterTick: " + enabled + ", doc: " + shown("doc") + ", notice: " + notice + " + ' ' + document.getElementById('announceStatus').textContent, recoveryCleared: document.getElementById('recoveryCode').textContent === '' })");
  },
  async waitText(c) { const found = await until(listed + ".indexOf(" + JSON.stringify(c.text) + ") >= 0", c.timeoutMs || 30000); return { found: !!found, text: await evaluate(listed) }; },
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
  async lock() { await evaluate("document.getElementById('lockBtn').click()", true); return { locked: !!(await until(shown("lockedView"), 10000)), ...(await evaluate(leftovers)) }; },
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
  async chatShot(c) {
    const shot = await cdp("Page.captureScreenshot", { format: "png" });
    writeFileSync(c.path, Buffer.from(shot.data, "base64"));
    return await evaluate("({ scrollWidth: document.documentElement.scrollWidth, innerWidth: window.innerWidth, composeBottom: document.getElementById('chatCompose').getBoundingClientRect().bottom, innerHeight: window.innerHeight })");
  }
};

async function shutdown() {
  try { await cdp("Browser.close"); } catch (e) { /* it may be gone */ }
  await sleep(500);
  try { if (chrome.exitCode === null) execFileSync("taskkill", ["/PID", String(chrome.pid), "/T", "/F"], { stdio: "ignore" }); } catch (e) { /* gone */ }
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
