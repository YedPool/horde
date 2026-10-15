// THE ORDER BAR OF THE DECISIONS DOCUMENT IN A REAL BROWSER (decisions/page/list.js, THE ORDER IS HIS),
// for test/test-decisions-page-browser.ps1: headless Chrome, driven over its debugging protocol (CDP)
// with nothing installed - Node's own WebSocket and HTTP, as surfaces/pwa/test/browser-drive.mjs.
// The page is list.js and list.css exactly as shipped, mounted by a host page of a few lines served
// here, on a phone-sized screen with touch, and the order buttons are pressed by REAL TOUCH EVENTS
// (Input.dispatchTouchEvent), so what is checked is what a tap does - not what setOrder does when a
// script calls it, which is what the window scenario (test/e2e/e2e-decisions-order.ps1) drives.
//
//   node browser-order.mjs <decisions/page folder> <chrome.exe> <profile folder>
//
// Prints one line per check, "[PASS] name" or "[FAIL] name: detail", then "[DONE] n", as
// order-units.mjs; the suite turns each into a check of its own. Chrome runs --headless=new: no
// window is ever shown. Nothing is written outside the profile folder handed in.
import http from "node:http";
import { spawn, execFileSync } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";

const [, , pageDir, chromePath, profileDir] = process.argv;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const ascii = (s) => String(s).replace(/[^\x20-\x7e]/g, (ch) => "\\u" + ch.charCodeAt(0).toString(16).padStart(4, "0"));

let passed = 0;
let failures = 0;
function check(ok, name, detail = "") {
  if (ok) { passed += 1; process.stdout.write("[PASS] " + ascii(name) + "\n"); }
  else { failures += 1; process.stdout.write("[FAIL] " + ascii(name) + (detail ? ": " + ascii(detail) : "") + "\n"); }
}

// --- the host page: list.js mounted on a phone-sized page, its list handed in by window.hostList.
// ?prefs=throw hands it, for the order AND for drafts and what was seen, a store whose every call
// throws, as a page whose storage is refused. window.mountError is what mounting threw, if anything.
const HOST = [
  "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
  "<link rel=\"stylesheet\" href=\"/list.css\"></head><body><div id=\"list\"></div>",
  "<script src=\"/list.js\"></script><script>",
  "var refused = /prefs=throw/.test(location.search);",
  "var prefs = refused ? { getItem: function () { throw new Error('refused'); }, setItem: function () { throw new Error('refused'); } } : null;",
  "window.mountError = '';",
  // HIS LITTLE BUTTONS: every change of rank the page asks for is kept in window.rankCalls, and answered
  // when the scenario calls window.rankAnswer(result) - so it can look at the page while one is on its way.
  "window.rankCalls = []; window.rankAnswer = null;",
  "var rank = function (number, which, level, id) { window.rankCalls.push({ number: number, which: which, level: level, id: id }); return new Promise(function (r) { window.rankAnswer = r; }); };",
  "try { window.doc = window.HordeDecisionsDocument.mount(document.getElementById('list'), { prefs: prefs, storage: prefs, rank: rank }); } catch (e) { window.mountError = String(e && e.message || e); }",
  "window.hostList = function (qs) { return window.doc ? window.doc.setList({ state: 'known', value: { questions: qs } }) : 'not mounted: ' + window.mountError; };",
  "</script></body></html>"
].join("\n");
const FILES = { "/list.js": ["list.js", "text/javascript; charset=utf-8"], "/list.css": ["list.css", "text/css; charset=utf-8"] };
const server = http.createServer((req, res) => {
  const path = new URL(req.url, "http://localhost").pathname;
  if (path === "/host.html") { res.writeHead(200, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" }); res.end(HOST); return; }
  const f = FILES[path];
  if (!f) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { "content-type": f[1], "cache-control": "no-store" });
  res.end(readFileSync(join(pageDir, f[0])));
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const origin = "http://127.0.0.1:" + server.address().port;

// --- Chrome, headless: never a window on the desktop ---
const chrome = spawn(chromePath, ["--headless=new", "--remote-debugging-port=0", "--user-data-dir=" + profileDir, "--no-first-run", "--no-default-browser-check", "--disable-extensions",
  "--disable-background-networking", "--disable-sync", "--disable-component-update", "--window-size=412,915", "about:blank"], { stdio: "ignore" });
function finish(code) {
  try { if (chrome.exitCode === null) execFileSync("taskkill", ["/PID", String(chrome.pid), "/T", "/F"], { stdio: "ignore" }); } catch (e) { /* gone */ }
  server.close();
  process.exit(code);
}
const portFile = join(profileDir, "DevToolsActivePort");
for (let i = 0; i < 200 && !existsSync(portFile); i++) await sleep(100);
if (!existsSync(portFile)) { check(false, "CONTROL: headless Chrome opens its debugging port"); process.stdout.write("[DONE] " + passed + "\n"); finish(1); }
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
  await cdp("Page.navigate", { url });
  await loaded;
}
// Two frames: what a tap set going is drawn.
const settle = () => evaluate("new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(() => r(true))))");

// --- the list: questions as decisions/Operations.ps1 hands them, at minute m of one morning ---
const WORDS = "a question long enough to take a few lines on a phone, as the founder's questions do, with its context after it so the page is many screens tall";
const at = (m) => "2026-10-14T09:" + String(m).padStart(2, "0") + ":00.0000000Z";
const question = (n, more = {}) => ({ number: n, state: "open", title: "Question " + n + ": " + WORDS, kind: "free-text", group: "", addedAt: at(n), importance: "normal", blocks: "part", thread: { messages: [] }, ...more });
// 24 questions, asked in number order: by date 24 stands first. Two are of the most important
// tasks (7 and 3), and the newest ones are of the least important (20 to 24); one blocks all work (2).
function longList() {
  const qs = [];
  for (let n = 1; n <= 24; n++) qs.push(question(n, { importance: (n === 3 || n === 7) ? "high" : (n >= 20 ? "low" : "normal"), blocks: n === 2 ? "all" : (n >= 18 ? "none" : "part") }));
  return qs;
}

// What the page shows: each question line in the list, in page order, with where it stands on the
// screen; the order buttons as drawn; and how far the page is scrolled.
const READ = `(() => {
  const lines = Array.from(document.querySelectorAll('#list .hd-q')).map((w) => { const b = w.getBoundingClientRect(); const t = w.querySelector('.hd-qt'); const m = /Question (\\d+):/.exec(t ? t.textContent : ''); return { n: m ? Number(m[1]) : 0, top: b.top, bottom: b.bottom }; }).filter((l) => l.n > 0);
  const inView = lines.filter((l) => l.bottom > 0 && l.top < innerHeight);
  const bar = document.querySelector('#list .hd-order');
  const bb = bar ? bar.getBoundingClientRect() : null;
  const buttons = Array.from(document.querySelectorAll('#list .hd-order-btn')).map((b) => { const r = b.getBoundingClientRect(); return { text: b.textContent, label: b.getAttribute('aria-label'), pressed: b.getAttribute('aria-pressed'), x: r.left + r.width / 2, y: r.top + r.height / 2 }; });
  return { order: lines.map((l) => l.n).join(','), firstInView: inView.length ? inView[0].n : 0, barInView: !!bb && bb.bottom > 0 && bb.top < innerHeight, scrollY: scrollY, buttons: buttons, tall: document.documentElement.scrollHeight > innerHeight * 1.5 };
})()`;
const read = () => evaluate(READ);
// A real tap on the order button whose word is given: a touch down and up at its middle, as a finger.
async function tap(word) {
  const before = await read();
  const b = before.buttons.find((x) => x.text.indexOf(word) === 0);
  if (!b) return null;
  const point = [{ x: b.x, y: b.y, radiusX: 4, radiusY: 4, force: 1, id: 1 }];
  await cdp("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: point });
  await cdp("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  await sleep(150);
  await settle();
  return read();
}
const head = (r, k = 3) => r.order.split(",").slice(0, k).join(",");
const pressedOf = (r) => r.buttons.filter((b) => b.pressed === "true");
const DOWN = "\u25BC";
const UP = "\u25B2";

try {
  // ---------------- 1. THE BUG: a tap re-sorts the list, and the page scrolls away from it ----------------
  await load(origin + "/host.html");
  await evaluate("localStorage.clear(), true");
  await load(origin + "/host.html");
  await evaluate("window.hostList(" + JSON.stringify(longList()) + ")");
  await settle();
  let r = await read();
  check(r.tall && r.scrollY === 0 && r.firstInView === 24 && r.barInView, "CONTROL: the long list is drawn by date, the newest (24) at the top of the screen, the order bar in view, at the top of the page", JSON.stringify({ tall: r.tall, scrollY: r.scrollY, first: r.firstInView }));
  r = await tap("Task importance");
  check(!!r && head(r, 2) === "7,3", "a tap on Task importance re-sorts the list: the two most important questions (7, 3) lead it", r ? r.order : "no such button");
  check(!!r && r.firstInView === 7 && r.barInView && r.scrollY === 0,
    "AFTER THE TAP THE SCREEN SHOWS THE HEAD OF THE NEW ORDER: question 7 at the top and the order bar still in view - not the question that was at the top before, followed down the page",
    r ? "first in view " + r.firstInView + ", scrolled to " + r.scrollY + ", bar in view " + r.barInView : "");
  r = await tap("Blocking");
  check(!!r && head(r, 1) === "2" && r.firstInView === 2 && r.barInView, "and a tap on Blocking shows the question that blocks all work (2) at the top, the bar in view", r ? r.order + "; first in view " + r.firstInView + ", scrolled to " + r.scrollY : "");
  r = await tap("Date");
  check(!!r && head(r, 1) === "24" && r.firstInView === 24 && r.barInView, "and a tap on Date brings the newest (24) back to the top of the screen", r ? "first in view " + r.firstInView + ", scrolled to " + r.scrollY : "");
  // Scrolled a little, so the browser's own scroll anchoring is in play too (it does nothing at 0).
  const down = await evaluate("(() => { const b = document.querySelector('#list .hd-order').getBoundingClientRect(); const y = Math.max(1, Math.floor(b.top + scrollY + b.height / 4)); scrollTo(0, y); return scrollY; })()");
  r = await tap("Blocking");
  check(!!r && down > 0 && r.scrollY === down && r.barInView && r.firstInView === 2, "SCROLLED A LITTLE, a tap leaves the page where it was, the order line under the finger and the head of the new order (2) under it", r ? "scrolled from " + down + " to " + r.scrollY + ", first in view " + r.firstInView : "");
  await evaluate("scrollTo(0, 0), true");
  r = await tap("Date");

  // ---------------- 2. THE TOGGLE: the active order pressed again turns over ----------------
  r = await read();
  let on = pressedOf(r);
  check(on.length === 1 && on[0].text === "Date " + DOWN && /newest question first/.test(on[0].label), "the order in force shows its direction: Date with the arrow down, and says in words the newest first", JSON.stringify(on));
  check(r.buttons.filter((b) => b.pressed !== "true").every((b) => b.text.indexOf(DOWN) < 0 && b.text.indexOf(UP) < 0), "the orders not in force show no arrow", JSON.stringify(r.buttons.map((b) => b.text)));
  r = await tap("Date");
  on = pressedOf(r);
  check(!!r && head(r, 3) === "1,2,3" && r.firstInView === 1 && r.barInView, "DATE PRESSED AGAIN TURNS OVER: the oldest (1) first, at the top of the screen", r ? r.order : "");
  check(on.length === 1 && on[0].text === "Date " + UP && /oldest question first/.test(on[0].label), "and the arrow points up, and the words say the oldest first", JSON.stringify(on));
  r = await tap("Date");
  check(!!r && head(r, 1) === "24" && pressedOf(r)[0].text === "Date " + DOWN, "pressed a third time, back to the newest first, the arrow down", r ? r.order : "");
  r = await tap("Task importance");
  on = pressedOf(r);
  check(head(r, 2) === "7,3" && on.length === 1 && on[0].text === "Task importance " + DOWN && /most important first/.test(on[0].label), "a different order is chosen in its own first direction: the most important first, arrow down", r.order + " " + JSON.stringify(on));
  r = await tap("Task importance");
  on = pressedOf(r);
  check(head(r, 5) === "24,23,22,21,20" && r.firstInView === 24 && on[0].text === "Task importance " + UP && /least important first/.test(on[0].label), "TASK IMPORTANCE PRESSED AGAIN: the least important first (the low ones, newest first among them), arrow up, said in words", r.order + " " + JSON.stringify(on));
  check(r.order.split(",").slice(-2).join(",") === "7,3", "and the most important now stand last", r.order);

  // ---------------- 3. KEPT through a list that arrives, and through opening the page again ----------------
  const more = longList().concat([question(25, { importance: "low" })]);
  await evaluate("window.hostList(" + JSON.stringify(more) + ")");
  await settle();
  r = await read();
  on = pressedOf(r);
  check(head(r, 2) === "25,24" && on.length === 1 && on[0].text === "Task importance " + UP, "A LIST THAT ARRIVES (the background refresh) keeps the order and its direction: least important first, the new low one (25) leads", r.order + " " + JSON.stringify(on));
  await load(origin + "/host.html");
  await evaluate("window.hostList(" + JSON.stringify(more) + ")");
  await settle();
  r = await read();
  on = pressedOf(r);
  check(head(r, 2) === "25,24" && on.length === 1 && on[0].text === "Task importance " + UP, "OPENED AGAIN on this device, the page is in the order and direction he chose", r.order + " " + JSON.stringify(on));
  r = await tap("Blocking");
  on = pressedOf(r);
  check(head(r, 1) === "2" && on[0].text === "Blocking " + DOWN && /most blocking first/.test(on[0].label), "and Blocking chosen after a turned-over order starts in its own first direction: most blocking first", r.order + " " + JSON.stringify(on));
  r = await tap("Blocking");
  on = pressedOf(r);
  check(r.order.split(",").slice(-1)[0] === "2" && on[0].text === "Blocking " + UP && /least blocking first/.test(on[0].label), "pressed again, the least blocking first and the one that blocks all work last", r.order + " " + JSON.stringify(on));
  await load(origin + "/host.html");
  await evaluate("window.hostList(" + JSON.stringify(more) + ")");
  await settle();
  r = await read();
  check(r.order.split(",").slice(-1)[0] === "2" && pressedOf(r).map((b) => b.text).join() === "Blocking " + UP, "opened again, Blocking turned over is what he chose last", r.order + " " + JSON.stringify(pressedOf(r)));

  // ---------------- 4. A PAGE WHOSE STORAGE IS REFUSED still orders, for as long as it is open ----------------
  await load(origin + "/host.html?prefs=throw");
  const drawnRefused = await evaluate("window.hostList(" + JSON.stringify(longList()) + ")");
  await settle();
  r = await read();
  check(drawnRefused === "drawn" && r.order.split(",").length === 24 && r.buttons.length === 3 && r.barInView,
    "STORAGE THAT THROWS ON EVERY CALL (order, drafts, what was seen): the page mounts, draws all 24 questions and the order line", String(drawnRefused) + "; " + r.order.split(",").length + " lines, " + r.buttons.length + " buttons");
  check(head(r, 1) === "24" && pressedOf(r)[0].text === "Date " + DOWN, "storage that throws: the page opens by date, newest first, and nothing breaks", r.order);
  r = await tap("Date");
  check(head(r, 1) === "1" && pressedOf(r)[0].text === "Date " + UP, "and a tap still turns it over", r.order);

  // ---------------- 5. A SHORT LIST: what worked before and still does ----------------
  await load(origin + "/host.html?prefs=throw");
  await evaluate("window.hostList(" + JSON.stringify(longList().slice(0, 4)) + ")");
  await settle();
  r = await tap("Blocking");
  check(head(r, 1) === "2" && r.firstInView === 2, "CONTROL: a list shorter than the screen re-sorts in view, as it always did", r.order + "; first in view " + r.firstInView);

  // ---------------- 6. HIS LITTLE BUTTONS (the founder, 2026-10-14): importance and blocking, changed by a tap ----------------
  // The rank buttons of question n as drawn: { text, label, expanded, x, y } each, and the levels open under them.
  const rankOf = (n) => evaluate(`(() => {
    const w = Array.from(document.querySelectorAll('#list .hd-q')).find((x) => { const t = x.querySelector('.hd-qt'); return t && t.textContent.indexOf('Question ${n}:') >= 0; });
    if (!w) return null;
    const box = w.querySelector('.hd-rank');
    const at = (b) => { const r = b.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; };
    return { hidden: !box || box.hidden, buttons: Array.from(w.querySelectorAll('.hd-rank-btn')).map((b) => ({ which: b.getAttribute('data-rank'), text: b.textContent, label: b.getAttribute('aria-label'), expanded: b.getAttribute('aria-expanded'), pending: b.classList.contains('pending'), ...at(b) })),
      levels: Array.from(w.querySelectorAll('.hd-rank-opt')).map((b) => ({ level: b.getAttribute('data-level'), text: b.textContent, label: b.getAttribute('aria-label'), pressed: b.getAttribute('aria-pressed'), ...at(b) })) };
  })()`);
  async function touch(x, y) {
    await cdp("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x, y, radiusX: 4, radiusY: 4, force: 1, id: 1 }] });
    await cdp("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await sleep(150);
    await settle();
  }
  const calls = () => evaluate("window.rankCalls.length");
  // A list in which question n stands at the given words; the rest as longList has them.
  const listWith = (changes) => longList().map((q) => (changes[q.number] ? { ...q, ...changes[q.number] } : q));
  await load(origin + "/host.html");
  await evaluate("localStorage.clear(), true");
  await load(origin + "/host.html");
  await evaluate("window.hostList(" + JSON.stringify(longList()) + ")");
  await settle();
  r = await tap("Task importance");
  let k = await rankOf(7);
  check(head(r, 2) === "7,3" && !!k && !k.hidden && k.buttons.map((b) => b.text).join("|") === "Importance: High|Blocking: Part", "EACH QUESTION SHOWS TWO LITTLE BUTTONS saying its levels in words: Importance: High, Blocking: Part", JSON.stringify(k && k.buttons.map((b) => b.text)));
  check(!!k && /^Importance of question 7: High\. Press to change it\.$/.test(k.buttons[0].label) && k.buttons[0].expanded === "false", "and a screen reader is told what each is, for which question, and what a press does", k ? k.buttons[0].label : "");
  // A TAP OPENS THE THREE LEVELS - it changes nothing by itself.
  await touch(k.buttons[0].x, k.buttons[0].y);
  k = await rankOf(7);
  check(k.levels.map((l) => l.level).join(",") === "high,normal,low" && k.levels.filter((l) => l.pressed === "true").map((l) => l.level).join() === "high" && k.levels[0].text.indexOf("High") > 0 && k.buttons[0].expanded === "true" && (await calls()) === 0,
    "A TAP OPENS A PICKER of the three levels, the one in force ticked and pressed - and nothing is sent", JSON.stringify(k.levels.map((l) => [l.text, l.pressed])));
  check(/^Set importance of question 7 to Low$/.test(k.levels[2].label), "each level says in words what picking it does", k.levels[2].label);
  // A TAP ON THE LEVEL IN FORCE, OR ANYWHERE ELSE, CLOSES IT AND SENDS NOTHING.
  await touch(k.levels[0].x, k.levels[0].y);
  k = await rankOf(7);
  check(k.levels.length === 0 && (await calls()) === 0, "picking the level it already has closes the picker and sends nothing", String(k.levels.length));
  await touch(k.buttons[1].x, k.buttons[1].y);
  k = await rankOf(7);
  check(k.levels.length === 3 && k.levels.filter((l) => l.pressed === "true").map((l) => l.level).join() === "part", "CONTROL: the Blocking button opens its own three, Part ticked");
  // The empty margin at the left of the question's own row: nothing there takes a tap.
  await touch(3, k.buttons[1].y);
  k = await rankOf(7);
  check(k.levels.length === 0 && (await calls()) === 0, "A MIS-TAP: a tap anywhere else closes the picker, and nothing is sent");
  // PICKING ANOTHER LEVEL ASKS THE HOST, AND THE ORDER WAITS FOR ITS ANSWER.
  await touch(k.buttons[0].x, k.buttons[0].y);
  k = await rankOf(7);
  await touch(k.levels[2].x, k.levels[2].y);
  const sent = await evaluate("window.rankCalls[0]");
  k = await rankOf(7);
  r = await read();
  check((await calls()) === 1 && sent.number === 7 && sent.which === "importance" && sent.level === "low" && /^[0-9a-f]{32}$/.test(sent.id), "picking Low asks the host once: question 7, importance, low, with an id of its own", JSON.stringify(sent));
  check(k.buttons[0].text === "Importance: Low (sending)" && k.buttons[0].pending && head(r, 2) === "7,3", "WHILE IT IS ON ITS WAY the button says Low, sending, and the question stays where it stands", k.buttons[0].text + " / " + r.order);
  await evaluate("window.rankAnswer({ ok: true }), true");
  await settle();
  k = await rankOf(7);
  check(k.buttons[0].text === "Importance: Low (sending)", "CONTROL: the host's ok alone does not move it: the list that holds the change does", k.buttons[0].text);
  await evaluate("window.hostList(" + JSON.stringify(listWith({ 7: { importance: "low" } })) + ")");
  await settle();
  r = await read();
  k = await rankOf(7);
  check(head(r, 1) === "3" && r.order.split(",").indexOf("7") > r.order.split(",").indexOf("19") && k.buttons[0].text === "Importance: Low" && !k.buttons[0].pending, "THE LIST THAT HOLDS IT RE-SORTS: 3 leads alone, 7 stands among the low ones, and its button says Low", r.order + " / " + k.buttons[0].text);
  // A REFUSAL PUTS THE BUTTON BACK AND SAYS WHY.
  k = await rankOf(3);
  check(!!k && k.buttons.length === 2, "CONTROL: question 3 shows its two buttons", JSON.stringify(k) + " " + await evaluate("Array.from(document.querySelectorAll('#list .hd-q')).slice(0,3).map((w) => w.className + ' ' + w.textContent.slice(0, 60)).join(' || ')"));
  await touch(k.buttons[1].x, k.buttons[1].y);
  k = await rankOf(3);
  await touch(k.levels[0].x, k.levels[0].y);
  k = await rankOf(3);
  check(k.buttons[1].text === "Blocking: All (sending)", "CONTROL: Blocking All is on its way for question 3", k.buttons[1].text);
  await evaluate("window.rankAnswer({ ok: false, reason: 'superseded by a newer change' }), true");
  await sleep(100);
  await settle();
  k = await rankOf(3);
  const toast = await evaluate("(document.querySelector('.hd-toast') || {}).textContent || ''");
  r = await read();
  check(k.buttons[1].text === "Blocking: Part" && toast.indexOf("not changed: superseded by a newer change") >= 0 && head(r, 1) === "3", "A REFUSAL puts the button back at Part, says why, and moves nothing", k.buttons[1].text + " / " + toast);
  // THE ORDER LINE STILL WORKS AFTER: turned over, and a tap scrolled a little keeps the page where it was.
  r = await tap("Task importance");
  check(r.order.split(",").slice(-1)[0] === "3" && pressedOf(r)[0].text === "Task importance " + UP, "the order still turns over after a change of rank: the least important first, 3 last", r.order);
  const down2 = await evaluate("(() => { const b = document.querySelector('#list .hd-order').getBoundingClientRect(); const y = Math.max(1, Math.floor(b.top + scrollY + b.height / 4)); scrollTo(0, y); return scrollY; })()");
  r = await tap("Blocking");
  check(down2 > 0 && r.scrollY === down2 && r.barInView && r.firstInView === 2, "and scrolled a little, a tap on an order still leaves the order line under the finger, the head of the new order under it", "scrolled from " + down2 + " to " + r.scrollY + ", first in view " + r.firstInView);
  // NONE FOR A QUESTION NOT ON HIS LIST: one he has answered shows no buttons.
  await evaluate("scrollTo(0, 0), true");
  await evaluate("window.hostList(" + JSON.stringify(listWith({ 2: { thread: { count: 1, turn: "warchief", messages: [{ sequence: 40, speaker: "founder", route: "window", text: "Yes." }] } } })) + ")");
  await settle();
  const answered = await rankOf(2);
  check(answered === null || answered.hidden, "a question he has answered shows no buttons", JSON.stringify(answered));

  check(problems.length === 0, "no script error in the page", problems.join(" | "));
} catch (e) {
  check(false, "the scenario ran to its end", e.message);
}
process.stdout.write("[DONE] " + passed + "\n");
finish(failures ? 1 : 0);
