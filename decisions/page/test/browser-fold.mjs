// THE ONE BUTTON THAT FOLDS OR UNFOLDS EVERY QUESTION, IN A REAL BROWSER (decisions/page/list.js, EVERY
// QUESTION STARTS UNFOLDED), for test/test-decisions-page-browser.ps1: headless Chrome on a phone-sized
// screen with touch, through browser-harness.mjs; the button and the questions' words are pressed by
// REAL TOUCH EVENTS.
//
// The founder, 2026-10-14: "I also want a collapse all button on the questions even though they should
// start expanded." Checked here: the questions open unfolded (and folded where the host asks, as the
// window does); one tap folds them all and the button then says Expand all, a second unfolds them all;
// neither touches the order or his place on the page; what he folds or unfolds, question by question,
// is kept through a list that arrives (the background refresh); and an order chosen still sorts.
//
//   node browser-fold.mjs <decisions/page folder> <chrome.exe> <profile folder>
//
// Prints one line per check, "[PASS] name" or "[FAIL] name: detail", then "[DONE] n".
import { openBrowser, check, question } from "./browser-harness.mjs";

const [, , pageDir, chromePath, profileDir] = process.argv;
const { evaluate, load, touch, problems, finish } = await openBrowser(pageDir, chromePath, profileDir);

// 20 questions, each with context to unfold (what it is, a recommendation, two options), asked in
// number order: by date 20 stands first; 4 and 9 are of the most important tasks.
const withContext = (n, more = {}) => question(n, { whatItIs: "What question " + n + " is about, in a line or two.", recommendation: "Do the first thing for " + n, options: ["the first thing", "the second thing"], importance: (n === 4 || n === 9) ? "high" : "normal", ...more });
function list(extra = []) {
  const qs = [];
  for (let n = 1; n <= 20; n++) qs.push(withContext(n));
  return qs.concat(extra);
}
const hostList = (qs) => evaluate("window.hostList(" + JSON.stringify(qs) + ")");

// What the page shows: each question in page order, whether it is unfolded (its class and its context
// shown), where it stands; the fold button as drawn; the order in force; how far the page is scrolled.
const READ = `(() => {
  const lines = Array.from(document.querySelectorAll('#list .hd-q')).map((w) => { const b = w.getBoundingClientRect(); const t = w.querySelector('.hd-qt'); const m = /Question (\\d+):/.exec(t ? t.textContent : ''); const sub = w.querySelector('.hd-sub'); return { n: m ? Number(m[1]) : 0, open: w.classList.contains('open'), shown: !!sub && !sub.hidden && sub.childNodes.length > 0, top: b.top, bottom: b.bottom }; }).filter((l) => l.n > 0);
  const inView = lines.filter((l) => l.bottom > 0 && l.top < innerHeight);
  const f = document.querySelector('#list .hd-foldall');
  const fr = f ? f.getBoundingClientRect() : null;
  const on = document.querySelector('#list .hd-order-btn[aria-pressed="true"]');
  const buttons = Array.from(document.querySelectorAll('#list .hd-order-btn')).map((b) => { const r = b.getBoundingClientRect(); return { text: b.textContent, x: r.left + r.width / 2, y: r.top + r.height / 2 }; });
  return { order: lines.map((l) => l.n).join(','), open: lines.filter((l) => l.open).map((l) => l.n).join(','), shown: lines.filter((l) => l.shown).map((l) => l.n).join(','), count: lines.length,
    first: inView.length ? { n: inView[0].n, top: Math.round(inView[0].top) } : null, scrollY: Math.round(scrollY),
    fold: f ? { text: f.textContent, label: f.getAttribute('aria-label'), x: fr.left + fr.width / 2, y: fr.top + fr.height / 2, inView: fr.bottom > 0 && fr.top < innerHeight } : null,
    pressed: on ? on.textContent : '', buttons: buttons, tall: document.documentElement.scrollHeight > innerHeight * 1.5 };
})()`;
const read = () => evaluate(READ);
const all = (r) => r.order.split(",").sort((a, b) => a - b).join(",");
// A real tap on the fold button, or on an order button by its word, or on a question's words.
async function tapFold() { const r = await read(); if (!r.fold) return null; await touch(r.fold.x, r.fold.y); return read(); }
async function tapOrder(word) { const r = await read(); const b = r.buttons.find((x) => x.text.indexOf(word) === 0); if (!b) return null; await touch(b.x, b.y); return read(); }
async function tapQuestion(n) {
  const p = await evaluate(`(() => { const w = Array.from(document.querySelectorAll('#list .hd-q')).find((x) => (x.querySelector('.hd-qt') || {}).textContent && /Question ${n}:/.test(x.querySelector('.hd-qt').textContent)); if (!w) return null; w.scrollIntoView({ block: 'center' }); const r = w.querySelector('.hd-qt .hd-txt').getBoundingClientRect(); return { x: r.left + 20, y: r.top + 8 }; })()`);
  if (!p) return null;
  await touch(p.x, p.y);
  return read();
}
// The head of the page, where the order line and the fold button are, brought onto the screen (a
// question tapped before scrolled them away).
const toTop = () => evaluate("scrollTo(0, 0), true");
const ALL20 = Array.from({ length: 20 }, (_, i) => String(i + 1)).join(",");

try {
  // ---------------- 1. THEY START UNFOLDED; the window's host opens them folded ----------------
  await load("/host.html");
  await evaluate("localStorage.clear(), true");
  await load("/host.html");
  await hostList(list());
  let r = await read();
  check(r.count === 20 && r.tall, "CONTROL: twenty questions drawn, the page taller than the screen", JSON.stringify({ count: r.count, tall: r.tall }));
  check(all({ order: r.open }) === ALL20 && all({ order: r.shown }) === ALL20, "EVERY QUESTION STARTS UNFOLDED: each of the twenty is open, its context shown under it", "open " + r.open + "; shown " + r.shown);
  check(!!r.fold && r.fold.text === "Collapse all" && r.fold.inView && /Fold the context of every question/.test(r.fold.label), "one button on the order line says Collapse all, in view, and says what it does in words", JSON.stringify(r.fold));
  await load("/host.html?expanded=0");
  await hostList(list());
  r = await read();
  check(r.open === "" && r.shown === "" && !!r.fold && r.fold.text === "Expand all", "a host that asks for it (the window: expanded false) opens them folded, and the button says Expand all", "open " + r.open + "; " + JSON.stringify(r.fold));

  // ---------------- 2. COLLAPSE ALL keeps the order and his place ----------------
  await load("/host.html");
  await hostList(list());
  r = await tapOrder("Task importance");
  check(!!r && r.order.split(",").slice(0, 2).join(",") === "9,4" && /^Task importance/.test(r.pressed), "CONTROL: a tap on Task importance sorts the two most important first (9, 4)", r ? r.order : "no button");
  const orderBefore = r.order;
  // His place: scrolled into the list, the button still on the screen.
  await evaluate("(() => { const f = document.querySelector('#list .hd-foldall').getBoundingClientRect(); scrollTo(0, Math.max(1, Math.floor(f.top + scrollY - 10))); return true; })()");
  const placed = await read();
  r = await tapFold();
  check(!!r && r.open === "" && r.shown === "", "A TAP ON COLLAPSE ALL FOLDS EVERY QUESTION", r ? "open " + r.open : "no button");
  check(!!r && r.fold.text === "Expand all" && /Unfold the context of every question/.test(r.fold.label), "and the button then says Expand all, and says so in words", r ? JSON.stringify(r.fold) : "");
  check(!!r && r.order === orderBefore && /^Task importance/.test(r.pressed), "the order is not touched: the same questions in the same order, Task importance still pressed", r ? r.order + " / " + r.pressed : "");
  check(!!r && !!placed.first && !!r.first && r.first.n === placed.first.n && Math.abs(r.first.top - placed.first.top) <= 1 && r.fold.inView, "HIS PLACE IS KEPT: the question at the top of the screen is still there, where it was, and the button is still in view",
    r ? "before " + JSON.stringify(placed.first) + " at " + placed.scrollY + ", after " + JSON.stringify(r.first) + " at " + r.scrollY : "");
  r = await tapFold();
  check(!!r && all({ order: r.open }) === ALL20 && r.fold.text === "Collapse all" && r.order === orderBefore, "A SECOND TAP, EXPAND ALL, UNFOLDS EVERY QUESTION again; the button says Collapse all; the order is the same", r ? "open " + r.open + "; " + r.fold.text : "");
  check(!!r && !!r.first && r.first.n === placed.first.n && Math.abs(r.first.top - placed.first.top) <= 1, "and his place is still kept", r ? JSON.stringify(r.first) + " vs " + JSON.stringify(placed.first) : "");

  // ---------------- 3. WHAT HE CHOSE IS KEPT THROUGH A LIST THAT ARRIVES ----------------
  r = await tapFold();
  r = await tapQuestion(7);
  check(!!r && r.open === "7", "folded, a tap on question 7's words unfolds that one question alone", r ? r.open : "");
  await hostList(list([withContext(21)]));
  r = await read();
  check(r.count === 21 && r.open === "7" && r.fold.text === "Expand all", "A LIST THAT ARRIVES (the background refresh) keeps it: 7 alone unfolded, the new question 21 folded as the button left them", "count " + r.count + ", open " + r.open);
  check(r.order.split(",").slice(0, 2).join(",") === "9,4" && /^Task importance/.test(r.pressed), "and the order he chose still stands", r.order);
  await toTop();
  r = await tapFold();
  r = await tapQuestion(12);
  const open12 = r ? r.open.split(",") : [];
  check(!!r && open12.length === 20 && open12.indexOf("12") < 0, "expanded, a tap on question 12's words folds that one alone", r ? r.open : "");
  await hostList(list([withContext(21), withContext(22, { importance: "high" })]));
  r = await read();
  const openNow = r.open.split(",");
  check(r.count === 22 && openNow.length === 21 && openNow.indexOf("12") < 0 && openNow.indexOf("22") >= 0, "a list that arrives keeps 12 folded and the rest unfolded, and the new question 22 opens unfolded", "open " + r.open);

  // ---------------- 4. SORTING STILL WORKS, and keeps what is folded ----------------
  await toTop();
  r = await tapOrder("Date");
  check(!!r && r.order.split(",")[0] === "22" && /^Date/.test(r.pressed) && r.open.split(",").indexOf("12") < 0 && r.open.split(",").length === 21, "a tap on Date sorts the newest (22) first, and 12 is still the one folded", r ? r.order + " / open " + r.open : "");
  r = await tapOrder("Date");
  check(!!r && r.order.split(",")[0] === "1" && r.open.split(",").length === 21, "and a second tap turns it over (the oldest, 1, first), what is folded untouched", r ? r.order : "");

  check(problems.length === 0, "no script error in the page", problems.join(" | "));
} catch (e) {
  check(false, "the scenario ran to its end", e.message);
}
finish();
