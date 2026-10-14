// THE ORDER BAR OF THE DECISIONS DOCUMENT IN A REAL BROWSER (decisions/page/list.js, THE ORDER IS HIS),
// for test/test-decisions-page-browser.ps1: headless Chrome on a phone-sized screen with touch, through
// browser-harness.mjs, and the order buttons are pressed by REAL TOUCH EVENTS
// (Input.dispatchTouchEvent), so what is checked is what a tap does - not what setOrder does when a
// script calls it, which is what the window scenario (test/e2e/e2e-decisions-order.ps1) drives.
//
//   node browser-order.mjs <decisions/page folder> <chrome.exe> <profile folder>
//
// Prints one line per check, "[PASS] name" or "[FAIL] name: detail", then "[DONE] n", as
// order-units.mjs; the suite turns each into a check of its own. Chrome runs --headless=new: no
// window is ever shown. Nothing is written outside the profile folder handed in.
import { openBrowser, check, question } from "./browser-harness.mjs";

const [, , pageDir, chromePath, profileDir] = process.argv;
const { evaluate, load, settle, touch, problems, finish } = await openBrowser(pageDir, chromePath, profileDir);

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
  await touch(b.x, b.y);
  return read();
}
const head = (r, k = 3) => r.order.split(",").slice(0, k).join(",");
const pressedOf = (r) => r.buttons.filter((b) => b.pressed === "true");
const DOWN = "\u25BC";
const UP = "\u25B2";

try {
  // ---------------- 1. THE BUG: a tap re-sorts the list, and the page scrolls away from it ----------------
  await load("/host.html");
  await evaluate("localStorage.clear(), true");
  await load("/host.html");
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
  await load("/host.html");
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
  await load("/host.html");
  await evaluate("window.hostList(" + JSON.stringify(more) + ")");
  await settle();
  r = await read();
  check(r.order.split(",").slice(-1)[0] === "2" && pressedOf(r).map((b) => b.text).join() === "Blocking " + UP, "opened again, Blocking turned over is what he chose last", r.order + " " + JSON.stringify(pressedOf(r)));

  // ---------------- 4. A PAGE WHOSE STORAGE IS REFUSED still orders, for as long as it is open ----------------
  await load("/host.html?prefs=throw");
  const drawnRefused = await evaluate("window.hostList(" + JSON.stringify(longList()) + ")");
  await settle();
  r = await read();
  check(drawnRefused === "drawn" && r.order.split(",").length === 24 && r.buttons.length === 3 && r.barInView,
    "STORAGE THAT THROWS ON EVERY CALL (order, drafts, what was seen): the page mounts, draws all 24 questions and the order line", String(drawnRefused) + "; " + r.order.split(",").length + " lines, " + r.buttons.length + " buttons");
  check(head(r, 1) === "24" && pressedOf(r)[0].text === "Date " + DOWN, "storage that throws: the page opens by date, newest first, and nothing breaks", r.order);
  r = await tap("Date");
  check(head(r, 1) === "1" && pressedOf(r)[0].text === "Date " + UP, "and a tap still turns it over", r.order);

  // ---------------- 5. A SHORT LIST: what worked before and still does ----------------
  await load("/host.html?prefs=throw");
  await evaluate("window.hostList(" + JSON.stringify(longList().slice(0, 4)) + ")");
  await settle();
  r = await tap("Blocking");
  check(head(r, 1) === "2" && r.firstInView === 2, "CONTROL: a list shorter than the screen re-sorts in view, as it always did", r.order + "; first in view " + r.firstInView);

  // ---------------- 6. NEWEST IS LAST ASKED: each line says when it was last asked, and Date sorts by it ----------------
  // Question 2 was added second and asked again at minute 50: by date it leads; question 1, asked once,
  // stands last. Its unfolded context says when it was first asked.
  const askedList = [1, 2, 3, 4].map((n) => question(n, n === 2
    ? { lastAskedAt: at(50), askedCount: 2, asked: [{ at: at(2), how: "first", by: "Orc E", note: "" }, { at: at(50), how: "remind", by: "warchief", note: "raised again in chat" }] }
    : { lastAskedAt: at(n), askedCount: 1, asked: [{ at: at(n), how: "first", by: "Orc E", note: "" }] }));
  const ASKED = `(() => Array.from(document.querySelectorAll('#list .hd-q')).map((w) => { const t = w.querySelector('.hd-qt'); const m = /Question (\\d+):/.exec(t ? t.textContent : ''); const a = w.querySelector('.hd-asked'); const shown = !!a && a.offsetParent !== null; return { n: m ? Number(m[1]) : 0, asked: a ? a.textContent : '', shown: shown, context: w.textContent }; }).filter((l) => l.n > 0))()`;
  const words = (iso) => evaluate("window.HordeDecisionsDocument.asked.words(Date.parse(" + JSON.stringify(iso) + "))");
  await load(origin + "/host.html?prefs=throw");
  await evaluate("window.hostList(" + JSON.stringify(askedList.map((x) => ({ ...x, lastAskedAt: undefined, asked: undefined, askedCount: undefined }))) + ")");
  await settle();
  r = await read();
  check(head(r, 4) === "4,3,2,1", "CONTROL: the same four from an earlier version, with no last-asked time, stand by when they were added", r.order);
  await evaluate("window.hostList(" + JSON.stringify(askedList) + ")");
  await settle();
  r = await read();
  check(head(r, 4) === "2,4,3,1", "BY DATE THE QUESTION ASKED AGAIN STANDS FIRST: 2, asked again at minute 50, leads; then 4, 3 and 1 as they were asked", r.order);
  let lines = await evaluate(ASKED);
  const want50 = await words(at(50));
  const want4 = await words(at(4));
  check(lines.length === 4 && lines.every((l) => l.shown && /^Asked \d+ [A-Z][a-z]{2} \d\d:\d\d$/.test(l.asked)), "EVERY QUESTION SAYS, ON SCREEN, WHEN IT WAS LAST ASKED: \"Asked\", a day, a month and a time", JSON.stringify(lines.map((l) => [l.n, l.asked, l.shown])));
  check(lines[0].asked === "Asked " + want50 && lines[1].asked === "Asked " + want4, "and the time is the last asking: question 2 says minute 50, not when it was added", JSON.stringify(lines.map((l) => l.asked)));
  check(lines.every((l) => l.context.indexOf("First asked") < 0), "CONTROL: folded, no question shows when it was first asked", "");
  await evaluate("(() => { const w = Array.from(document.querySelectorAll('#list .hd-q')).find((x) => /Question 2:/.test(x.querySelector('.hd-qt').textContent)); w.querySelector('.hd-qt').click(); return true; })()");
  await settle();
  lines = await evaluate(ASKED);
  const two = lines.find((l) => l.n === 2);
  const want2 = await words(at(2));
  check(!!two && two.context.indexOf("First asked:" + want2) >= 0, "UNFOLDED, the question asked again says when it was first asked (minute 2)", two ? two.context.slice(-200) : "");
  await evaluate("(() => { const w = Array.from(document.querySelectorAll('#list .hd-q')).find((x) => /Question 3:/.test(x.querySelector('.hd-qt').textContent)); w.querySelector('.hd-qt').click(); return true; })()");
  await settle();
  lines = await evaluate(ASKED);
  check(lines.find((l) => l.n === 3).context.indexOf("First asked") < 0, "and one asked only once says nothing of a first asking: it is the same moment", "");
  r = await tap("Date");
  check(head(r, 4) === "1,3,4,2", "Date turned over: the one asked longest ago (1) first, the one asked again last (2) last", r.order);

  check(problems.length === 0, "no script error in the page", problems.join(" | "));
} catch (e) {
  check(false, "the scenario ran to its end", e.message);
}
finish();
