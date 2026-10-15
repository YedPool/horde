// THE CARDS AT THE HEAD OF THE DECISIONS PAGE, IN A REAL BROWSER (decisions/page/list.js, ONE LANE AT A
// TIME; surfaces/pwa/page/decision-cards.js), for test/test-decisions-page-browser.ps1: headless Chrome on
// a phone-sized screen with touch, through browser-harness.mjs's /cards.html - the phone's page put
// together as app.js puts it - and the cards and buttons pressed by REAL TOUCH EVENTS.
//
// The founder's decision 74 (2026-10-14): cards first, one per lane with its open-question count and a
// mark when one of its questions blocks all its work, plus one "All questions" card; a tap on a card shows
// that lane's questions. Checked here: what is counted (by the page's own rules of what he has still to
// answer: answered, closed, parts, follow-ups, no askedBy); the cards and the mark; a tap filters, All
// shows everything; a background refresh keeps the card and what is folded; sorting inside a card;
// the chosen card kept on this device; the lanes document's own cards when it has come.
//
//   node browser-cards.mjs <decisions/page folder> <chrome.exe> <profile folder>
//
// Prints one line per check, "[PASS] name" or "[FAIL] name: detail", then "[DONE] n".
import { openBrowser, check, question } from "./browser-harness.mjs";

const [, , pageDir, chromePath, profileDir] = process.argv;
const { evaluate, load, touch, problems, finish, sleep } = await openBrowser(pageDir, chromePath, profileDir);

const STOP = String.fromCharCode(0x26D4);
const said = (text, sequence, more = {}) => ({ speaker: "founder", text, sequence, ...more });
// THE LIST: who asked, and what became of each question.
function list(extra = []) {
  return [
    question(1, { askedBy: "Orc B", blocks: "all" }),                                                     // B, open, blocks all
    question(2, { askedBy: "Orc B", thread: { messages: [said("Yes.", 1)] } }),                          // B, answered: not open
    question(3, { askedBy: "Orc B", kind: "parts", parts: ["(a) the first", "(b) the second"], thread: { messages: [said("ok", 2, { part: "a" })] } }), // B, one part of two answered: open
    question(4, { askedBy: "Orc C", kind: "parts", parts: ["(a) the first", "(b) the second"], thread: { messages: [said("ok", 3, { part: "a" }), said("no", 4, { part: "b" })] } }), // C, every part answered: not open
    question(5, { askedBy: "Orc C", state: "closed" }),                                                   // C, closed: not open
    question(6, { askedBy: "M (Thrall)" }),                                                                // the Thrall's
    question(7, { askedBy: "" }),                                                                          // nobody named: the Thrall's
    question(8, {}),                                                                                       // no askedBy at all: the Thrall's
    question(9, { askedBy: "Orc E", followsUp: { number: 2, title: "Question 2", answer: "Yes." } }),      // E, a follow-up: open
    question(10, { askedBy: "Orc F1", blocks: "all", importance: "high" }),                               // F1, open, blocks all
    question(12, { askedBy: "Orc C", importance: "high" })                                                // C, open
  ].concat(extra);
}
const hostList = (qs) => evaluate("window.hostList(" + JSON.stringify(qs) + ")");
const lanesWords = (ls) => ls.map((l) => l.lane + ":" + l.open + (l.blocksAll ? "!" : "")).join(",");

// What the page shows: each card (its name, its slot's words, whether chosen, where it is); the question
// lines of the list and the rows of the folds, by number; the order bar; the fold button; scroll.
const READ = `(() => {
  const cards = Array.from(document.querySelectorAll('#cards .card')).map((c) => { const r = c.getBoundingClientRect(); const mark = c.querySelector('.dq-blocks'); return { name: c.querySelector('.card-name').textContent, slot: c.querySelector('.card-badge').textContent, mark: mark ? mark.textContent : '', markShown: !!mark && mark.getBoundingClientRect().width > 0, chosen: c.getAttribute('aria-pressed') === 'true', lines: c.querySelectorAll('.card-line').length, x: r.left + r.width / 2, y: r.top + Math.min(r.height / 2, 20) }; });
  const num = (w) => { const m = /Question (\\d+):/.exec((w.querySelector('.hd-qt') || {}).textContent || ''); return m ? Number(m[1]) : 0; };
  const main = Array.from(document.querySelectorAll('#list .hd-q:not(.hd-done)')).map(num).filter((n) => n > 0);
  const done = Array.from(document.querySelectorAll('#list .hd-done')).map(num).filter((n) => n > 0);
  const heads = Array.from(document.querySelectorAll('#list .hd-head .hd-txt')).map((t) => t.textContent);
  const bar = document.querySelector('#list .hd-order');
  const bb = bar ? bar.getBoundingClientRect() : null;
  const buttons = Array.from(document.querySelectorAll('#list .hd-order-btn')).map((b) => { const r = b.getBoundingClientRect(); return { text: b.textContent, x: r.left + r.width / 2, y: r.top + r.height / 2 }; });
  const f = document.querySelector('#list .hd-foldall');
  const fr = f ? f.getBoundingClientRect() : null;
  const open = Array.from(document.querySelectorAll('#list .hd-q.open:not(.hd-done)')).map(num);
  return { cards, main: main.join(','), done: done.join(','), heads, barTop: bb ? Math.round(bb.top) : null, buttons, fold: f ? { text: f.textContent, x: fr.left + fr.width / 2, y: fr.top + fr.height / 2 } : null, open: open.join(','), scrollY: Math.round(scrollY), lane: window.doc.lane() };
})()`;
const read = () => evaluate(READ);
const cardWords = (r) => r.cards.map((c) => c.name + " [" + c.slot + "]" + (c.chosen ? "*" : "")).join(" | ");
async function tapCard(name) {
  // The card is brought onto the screen first, as he would scroll to it.
  await evaluate(`(() => { const c = Array.from(document.querySelectorAll('#cards .card')).find((x) => x.querySelector('.card-name').textContent === ${JSON.stringify(name)}); if (c) c.scrollIntoView({ block: 'center' }); return true; })()`);
  const r = await read();
  const c = r.cards.find((x) => x.name === name);
  if (!c) return null;
  await touch(c.x, c.y);
  return read();
}
// The order line brought onto the screen first: the cards above it can push it off.
async function tapOrder(word) { await evaluate("document.querySelector('#list .hd-order').scrollIntoView({ block: 'center' }), true"); const r = await read(); const b = r.buttons.find((x) => x.text.indexOf(word) === 0); if (!b) return null; await touch(b.x, b.y); return read(); }
async function tapFold() { await evaluate("document.querySelector('#list .hd-foldall').scrollIntoView({ block: 'center' }), true"); const r = await read(); if (!r.fold) return null; await touch(r.fold.x, r.fold.y); return read(); }
const sorted = (s) => s.split(",").filter((x) => x).map(Number).sort((a, b) => a - b).join(",");

async function open(path) {
  await load(path);
  for (let i = 0; i < 50 && !(await evaluate("window.hostReady === true")); i++) await sleep(50);
}

try {
  await open("/cards.html");
  await evaluate("localStorage.clear(), true");
  await open("/cards.html");
  await hostList(list());

  // ---------------- 1. WHAT IS COUNTED: by the page's own rules of what he has still to answer ----------------
  const lanes = await evaluate("window.doc.lanes()");
  check(lanesWords(lanes) === "thrall:3,B:2!,C:1,E:1,F1:1!",
    "THE COUNTS: the Thrall's lane 3 (asked by M, by nobody named, with no askedBy at all), B 2 and blocks all (an answered one not counted, a question of parts counted once while a part is open), C 1 (every part answered, and closed, not counted), E 1 (a follow-up counts in its own lane), F1 1 and blocks all",
    lanesWords(lanes));
  // MUST-FAIL TWIN: the same reading, after he answers question 1 and the last part of question 3 - the
  // count must move, or the check above could pass on numbers that never change.
  await hostList(list().map((q) => q.number === 1 ? { ...q, thread: { messages: [said("Go.", 9)] } } : q.number === 3 ? { ...q, thread: { messages: [said("ok", 2, { part: "a" }), said("fine", 10, { part: "b" })] } } : q));
  const after = await evaluate("window.doc.lanes()");
  check(lanesWords(after) === "thrall:3,C:1,E:1,F1:1!" && lanesWords(after) !== lanesWords(lanes),
    "MUST-FAIL TWIN: answered, question 1 and the last part of question 3 leave B's count - B has no card's count, its blocks mark gone with it", lanesWords(after));
  await hostList(list());

  // ---------------- 2. THE CARDS, AND THE MARK IN WORDS AND A SIGN ----------------
  let r = await read();
  check(cardWords(r) === "All questions [8 open " + STOP + " blocks all work]* | Thrall [3 open] | Orc B [2 open " + STOP + " blocks all work] | Orc C [1 open] | Orc E [1 open] | Orc F1 [1 open " + STOP + " blocks all work]",
    "CARDS FIRST: All questions (chosen, with the sum and the mark), then the Thrall's, then each lane by name, each with its open count", cardWords(r));
  const marked = r.cards.filter((c) => c.mark);
  check(marked.length === 3 && marked.every((c) => c.markShown && c.mark.indexOf("blocks all work") >= 0 && c.mark.indexOf(STOP) >= 0), "THE BLOCKS MARK is drawn and seen, words and a sign together, on All, B and F1 alone", JSON.stringify(marked.map((c) => c.name + ": " + c.mark)));
  check(sorted(r.main) === "1,3,6,7,8,9,10,12" && sorted(r.done) === "2,4,5", "All questions shows every question he has to answer, and in the folds every other", r.main + " / " + r.done);

  // ---------------- 3. A TAP ON A CARD SHOWS THAT LANE'S QUESTIONS ----------------
  r = await tapCard("Orc B");
  check(!!r && sorted(r.main) === "1,3" && r.lane === "B" && r.cards.find((c) => c.name === "Orc B").chosen && r.cards.filter((c) => c.chosen).length === 1,
    "A TAP ON ORC B'S CARD shows B's questions alone (1 and 3), and its card alone is chosen", r ? r.main + " / " + cardWords(r) : "no card");
  check(!!r && r.heads.some((h) => /With Thrall \(1\)/.test(h)) && r.done === "2", "and B's answered question stands alone in its fold (With Thrall (1))", r ? r.heads.join(" | ") : "");
  check(!!r && r.barTop !== null && r.barTop >= 0 && r.barTop < 915, "and B's two questions, shorter than the screen, are on it with the order line above them", r ? "order line at " + r.barTop : "");
  r = await tapCard("All questions");
  check(!!r && sorted(r.main) === "1,3,6,7,8,9,10,12" && r.lane === "" && r.cards[0].chosen, "A TAP ON ALL QUESTIONS shows everything again", r ? r.main : "");
  r = await tapCard("Thrall");
  check(!!r && sorted(r.main) === "6,7,8" && r.lane === "thrall", "the Thrall's card shows the questions of M, of nobody named and of no askedBy", r ? r.main : "");
  // A LANE OF MANY QUESTIONS, longer than the screen: the tap must bring the head of its list up, or the
  // screen would still show the cards and the list would change below them unseen.
  const manyB = [];
  for (let n = 30; n < 42; n++) manyB.push(question(n, { askedBy: "Orc B" }));
  await hostList(list(manyB));
  await tapCard("All questions");
  r = await tapCard("Orc B");
  check(!!r && r.lane === "B" && r.main.split(",").length === 14 && r.barTop !== null && r.barTop >= 0 && r.barTop < 60, "A TAP ON A CARD WHOSE LANE IS LONGER THAN THE SCREEN brings the head of its questions up: the order line at the top of the view", r ? "order line at " + r.barTop + ", " + r.main.split(",").length + " questions" : "");
  await hostList(list());

  // ---------------- 4. A BACKGROUND REFRESH KEEPS THE CARD AND WHAT IS FOLDED ----------------
  r = await tapCard("Orc C");
  check(!!r && sorted(r.main) === "12" && r.open === "12", "CONTROL: Orc C's card shows 12, unfolded as every question starts", r ? r.main + " open " + r.open : "");
  r = await tapFold();
  check(!!r && r.open === "" && r.fold.text === "Expand all", "Collapse all inside the card folds C's question", r ? r.open : "");
  await hostList(list([question(13, { askedBy: "Orc C" })]));
  r = await read();
  check(r.lane === "C" && sorted(r.main) === "12,13" && r.cards.find((c) => c.name === "Orc C").chosen && r.cards.find((c) => c.name === "Orc C").slot === "2 open",
    "A LIST THAT ARRIVES (the background refresh) keeps Orc C's card chosen: its new question (13) joins it and its count reads 2", r.main + " / " + cardWords(r));
  check(r.open === "" && r.fold.text === "Expand all", "and keeps what is folded: 12 still folded, and 13, arriving after Collapse all, folded too", "open " + r.open);
  await open("/cards.html");
  await hostList(list([question(13, { askedBy: "Orc C" })]));
  r = await read();
  check(r.lane === "C" && sorted(r.main) === "12,13" && r.cards.find((c) => c.name === "Orc C").chosen, "OPENED AGAIN on this device, the card he chose is the one shown", r.lane + " / " + r.main);

  // ---------------- 5. SORTING INSIDE A CARD ----------------
  r = await tapCard("Orc B");
  r = await tapOrder("Blocking");
  check(!!r && r.main === "1,3" && r.lane === "B", "inside Orc B's card, Blocking puts the one that blocks all work (1) first", r ? r.main : "");
  r = await tapOrder("Blocking");
  check(!!r && r.main === "3,1", "and a second tap turns it over (3, then 1)", r ? r.main : "");
  r = await tapOrder("Date");
  check(!!r && r.main === "3,1" && r.lane === "B", "Date sorts B's questions newest first (3, then 1), the card still chosen", r ? r.main : "");

  // ---------------- 6. THE LANES DOCUMENT'S OWN CARDS, when it has come ----------------
  await evaluate(`(() => { window.lanesDoc = { machines: [{ name: "pc", made: 0 }], thrall: [], cards: [{ lane: "B", name: "lane B", machine: "pc", entry: "e", form: "standard", asOf: "", now: "building the cards", lastDone: "", waitingOn: "", blocked: "no", tasksOpen: 2, doneWeek: 1 }, { lane: "G", name: "G", machine: "pc", entry: "e", form: "standard", asOf: "", now: "idle", lastDone: "", waitingOn: "", blocked: "no", tasksOpen: 0, doneWeek: 0 }] }; window.redrawCards(); return true; })()`);
  r = await read();
  const b = r.cards.find((c) => c.name === "B - lane B");
  check(!!b && b.lines >= 1 && b.slot.indexOf("2 open") === 0 && b.chosen && r.cards.some((c) => c.name === "G" && c.slot === "0 open") && r.cards.some((c) => c.name === "Orc C"),
    "WITH THE LANES DOCUMENT, a lane's card is the Progress tab's own (B - lane B, its Now line) with the count in its slot; a lane with nothing to answer (G) reads 0; a lane it lacks (C) keeps its name card", cardWords(r));

  check(problems.length === 0, "no script error in the page", problems.join(" | "));
} catch (e) {
  check(false, "the scenario ran to its end", e.message);
}
finish();
