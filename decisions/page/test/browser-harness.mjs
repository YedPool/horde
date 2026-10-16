// THE DECISIONS DOCUMENT IN A REAL BROWSER: the one harness the browser drivers of this folder share
// (browser-order.mjs, browser-fold.mjs), for test/test-decisions-page-browser.ps1. Headless Chrome,
// driven over its debugging protocol (CDP) with nothing installed - Node's own WebSocket and HTTP, as
// surfaces/pwa/test/browser-drive.mjs. The page is list.js and list.css exactly as shipped, mounted by
// a host page of a few lines served here, on a phone-sized screen with touch.
//
// The host page, /host.html, takes in its address:
//   ?prefs=throw     for the order AND for drafts and what was seen, a store whose every call
//                    throws, as a page whose storage is refused; window.mountError is what
//                    mounting threw, if anything
//   ?expanded=0      mounted with expanded: false, as the window mounts it
//   ?say=ok          a host whose say takes every answer: window.said holds { n, t } for each
// and hands a list in by window.hostList(questions). /cards.html is the phone's decisions page with its
// cards first (CARDS_HOST, below).
//
// Each driver prints one line per check, "[PASS] name" or "[FAIL] name: detail", then "[DONE] n"; the
// suite turns each into a check of its own. Chrome runs --headless=new: no window is ever shown.
// Nothing is written outside the profile folder handed in.
import http from "node:http";
import { spawn, execFileSync } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const ascii = (s) => String(s).replace(/[^\x20-\x7e]/g, (ch) => "\\u" + ch.charCodeAt(0).toString(16).padStart(4, "0"));

let passed = 0;
let failures = 0;
export function check(ok, name, detail = "") {
  if (ok) { passed += 1; process.stdout.write("[PASS] " + ascii(name) + "\n"); }
  else { failures += 1; process.stdout.write("[FAIL] " + ascii(name) + (detail ? ": " + ascii(detail) : "") + "\n"); }
}

const HOST = [
  "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
  "<link rel=\"stylesheet\" href=\"/list.css\"></head><body><div id=\"list\"></div>",
  "<script src=\"/list.js\"></script><script>",
  "var refused = /prefs=throw/.test(location.search);",
  "var prefs = refused ? { getItem: function () { throw new Error('refused'); }, setItem: function () { throw new Error('refused'); } } : null;",
  "var options = { prefs: prefs, storage: prefs };",
  "if (/expanded=0/.test(location.search)) { options.expanded = false; }",
  "window.said = [];",
  "if (/say=ok/.test(location.search)) { options.say = function (n, t) { window.said.push({ n: n, t: t }); return Promise.resolve({ ok: true, sequence: window.said.length }); }; }",
  "window.mountError = '';",
  "try { window.doc = window.HordeDecisionsDocument.mount(document.getElementById('list'), options); } catch (e) { window.mountError = String(e && e.message || e); }",
  "window.hostList = function (qs) { return window.doc ? window.doc.setList({ state: 'known', value: { questions: qs } }) : 'not mounted: ' + window.mountError; };",
  "</script></body></html>"
].join("\n");
// /cards.html: the phone's decisions page as app.js puts it together (surfaces/pwa/page/app.js, docOf and
// drawDecisionCards) - the cards first, drawn by decision-cards.js from doc.lanes() on every onDraw, a tap
// on a card is doc.setLane - under the phone's own style sheet. window.lanesDoc is the lanes document the
// cards are drawn from (null: none has come), window.redrawCards() draws them again after it is set.
const CARDS_HOST = [
  "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
  "<link rel=\"stylesheet\" href=\"/app/app.css\"><link rel=\"stylesheet\" href=\"/list.css\"></head><body><div id=\"lists\"><div id=\"cards\" class=\"decision-cards\"></div><div id=\"list\"></div></div>",
  "<script src=\"/list.js\"></script><script type=\"module\">",
  "import { renderDecisionCards } from '/app/decision-cards.js';",
  "const cards = document.getElementById('cards');",
  "window.lanesDoc = null;",
  "function drawCards() { if (!window.doc) return; while (cards.firstChild) cards.removeChild(cards.firstChild); for (const c of renderDecisionCards(document, window.lanesDoc, window.doc.lanes(), { chosen: window.doc.lane(), onChoose: (l) => window.doc.setLane(l) })) cards.appendChild(c); }",
  "window.doc = window.HordeDecisionsDocument.mount(document.getElementById('list'), { onDraw: drawCards });",
  "window.redrawCards = drawCards;",
  "window.hostList = function (qs) { return window.doc.setList({ state: 'known', value: { questions: qs } }); };",
  "window.hostReady = true;",
  "</script></body></html>"
].join("\n");
// Served path -> [file under decisions/page, or under the repository when it starts with "/", type].
const JS = "text/javascript; charset=utf-8";
const CSS = "text/css; charset=utf-8";
const FILES = { "/list.js": ["list.js", JS], "/list.css": ["list.css", CSS],
  "/app/app.css": ["/surfaces/pwa/page/app.css", CSS], "/app/decision-cards.js": ["/surfaces/pwa/page/decision-cards.js", JS],
  "/app/lane-card.js": ["/surfaces/pwa/page/lane-card.js", JS], "/relay/protocol.js": ["/relay/js/protocol.js", JS] };

// The page served, Chrome started on a phone-sized screen with touch, and the means to drive it.
export async function openBrowser(pageDir, chromePath, profileDir) {
  const server = http.createServer((req, res) => {
    const path = new URL(req.url, "http://localhost").pathname;
    if (path === "/host.html" || path === "/cards.html") { res.writeHead(200, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" }); res.end(path === "/host.html" ? HOST : CARDS_HOST); return; }
    const f = FILES[path];
    if (!f) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { "content-type": f[1], "cache-control": "no-store" });
    res.end(readFileSync(f[0].startsWith("/") ? join(pageDir, "..", "..", f[0]) : join(pageDir, f[0])));
  });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const origin = "http://127.0.0.1:" + server.address().port;

  // Chrome, headless: never a window on the desktop.
  const chrome = spawn(chromePath, ["--headless=new", "--remote-debugging-port=0", "--user-data-dir=" + profileDir, "--no-first-run", "--no-default-browser-check", "--disable-extensions",
    "--disable-background-networking", "--disable-sync", "--disable-component-update", "--window-size=412,915", "about:blank"], { stdio: "ignore" });
  // The run's end: Chrome's tree ended, the server closed, the closing line printed.
  function finish() {
    try { if (chrome.exitCode === null) execFileSync("taskkill", ["/PID", String(chrome.pid), "/T", "/F"], { stdio: "ignore" }); } catch (e) { /* gone */ }
    server.close();
    process.stdout.write("[DONE] " + passed + "\n");
    process.exit(failures ? 1 : 0);
  }
  const portFile = join(profileDir, "DevToolsActivePort");
  for (let i = 0; i < 200 && !existsSync(portFile); i++) await sleep(100);
  if (!existsSync(portFile)) { check(false, "CONTROL: headless Chrome opens its debugging port"); finish(); }
  const debugPort = readFileSync(portFile, "utf8").split(/\r?\n/)[0];
  let targets = [];
  for (let i = 0; i < 50 && !targets.some((t) => t.type === "page"); i++) { try { targets = await (await fetch("http://127.0.0.1:" + debugPort + "/json/list")).json(); } catch (e) { /* not yet */ } if (!targets.some((t) => t.type === "page")) await sleep(100); }
  const ws = new WebSocket(targets.find((t) => t.type === "page").webSocketDebuggerUrl);
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
  on("Runtime.exceptionThrown", (p) => problems.push(p.exceptionDetails.exception ? p.exceptionDetails.exception.description : p.exceptionDetails.text));

  await cdp("Page.enable");
  await cdp("Runtime.enable");
  await cdp("Emulation.setDeviceMetricsOverride", { width: 412, height: 915, deviceScaleFactor: 2.625, mobile: true });
  await cdp("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 5 });

  async function evaluate(expression) {
    const r = await cdp("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
    if (r.exceptionDetails) throw new Error("in the page: " + (r.exceptionDetails.exception ? r.exceptionDetails.exception.description : r.exceptionDetails.text));
    return r.result.value;
  }
  async function load(url) {
    const loaded = new Promise((r) => on("Page.loadEventFired", () => r()));
    await cdp("Page.navigate", { url: origin + url });
    await loaded;
  }
  // Two frames: what a tap set going is drawn.
  const settle = () => evaluate("new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(() => r(true))))");
  // A real tap at a point of the screen: a touch down and up, as a finger.
  async function touch(x, y) {
    await cdp("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x, y, radiusX: 4, radiusY: 4, force: 1, id: 1 }] });
    await cdp("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await sleep(150);
    await settle();
  }
  // Words typed at the caret as a keyboard types them (one input event per call).
  async function type(text) { await cdp("Input.insertText", { text }); await settle(); }
  return { cdp, evaluate, load, settle, touch, type, problems, finish };
}

// --- the questions, as decisions/Operations.ps1 hands them, at minute m of one morning ---
const WORDS = "a question long enough to take a few lines on a phone, as the founder's questions do, with its context after it so the page is many screens tall";
const at = (m) => "2026-10-14T09:" + String(m).padStart(2, "0") + ":00.0000000Z";
export const question = (n, more = {}) => ({ number: n, state: "open", title: "Question " + n + ": " + WORDS, kind: "free-text", group: "", addedAt: at(n), importance: "normal", blocks: "part", thread: { messages: [] }, ...more });
