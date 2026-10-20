// ONE TAP SHOWS A QUESTION WHOLE, AND THE BOX TO ANSWER IN IS PLAIN TO SEE, IN A REAL BROWSER
// (decisions/page/list.js, ONE STAGE, AND A BOX TO ANSWER IN), for test/test-decisions-page-browser.ps1:
// headless Chrome on a phone-sized screen with touch, through browser-harness.mjs; questions, fields
// and the Send key are pressed by REAL TOUCH EVENTS and words are typed as a keyboard types them.
//
// The founder, 2026-10-15: "Clicking on a decision to get more info now seems to have two stages of
// info showing - either make it one stage or make it more evident to the user. Also, the input box for
// where to type the decision answer needs to be more clearly delineated." Checked here, on the phone's
// page (its own style sheet, light and dark): one tap on a folded question shows every one of its
// details - what was said, whole; its options, what it is, the recommendation, files and references -
// in one run that ends with the label and the box, and nothing is left to a second press; the box has
// an edge of at least 4.5 to 1 against the page in both themes, a label tied to its field, a least
// height of three lines that grows with the words up to twelve, a ring while the caret is in it, and
// its Send key inside its edge, which sends what is typed and keeps the caret; folding, Collapse all
// and Expand all still work, and the window's host (folded) still shows every box.
//
//   node browser-details.mjs <decisions/page folder> <chrome.exe> <profile folder>
//
// Prints one line per check, "[PASS] name" or "[FAIL] name: detail", then "[DONE] n".
import { openBrowser, check, question, sleep } from "./browser-harness.mjs";

const [, , pageDir, chromePath, profileDir] = process.argv;
const { cdp, evaluate, load, touch, type, settle, problems, finish } = await openBrowser(pageDir, chromePath, profileDir);

// Three questions, each with every kind of detail: what was said (two earlier messages long enough to
// be cut to one line, then the one he has to answer), options, what it is, a recommendation, files
// and references.
const LONG = "a message long enough that a phone cuts it to one line with an ellipsis when it is not the one to answer";
const full = (n) => question(n, { askedBy: "orc-f", whatItIs: "What question " + n + " is about.", recommendation: "the first thing", options: ["the first thing", "the second thing"], files: ["decisions/page/list.js"], references: ["PR 296"],
  thread: { messages: [{ speaker: "orc-f", text: "Thrall said " + LONG }, { speaker: "founder", text: "He said " + LONG }, { speaker: "orc-f", text: "Which of the two for " + n + "?" }] } });
const LIST = [full(1), full(2), full(3)];
const hostList = (qs) => evaluate("window.hostList(" + JSON.stringify(qs) + "), true");
const WANT_LABELS = ["Option", "Option", "What it is", "Recommended", "Asked by", "Files", "References", "Answered with"];

const FIND = (n) => `Array.from(document.querySelectorAll('#list .hd-q')).find((x) => /Question ${n}:/.test((x.querySelector('.hd-qt') || {}).textContent || ''))`;
// What question n shows: its details as drawn and seen, where each stands, and whether any press is
// left that would show more.
const DETAILS = (n) => `(() => {
  const w = ${FIND(n)};
  if (!w) return null;
  const vis = (el) => !!el && el.offsetParent !== null && el.getBoundingClientRect().height > 0;
  const subs = Array.from(w.querySelectorAll('.hd-sub .hd-line')).filter(vis);
  const msgs = Array.from(w.querySelectorAll('.hd-talk .hd-msg')).filter(vis);
  const lab = w.querySelector('.hd-anslab'), box = w.querySelector('.hd-box');
  const rect = (el) => el ? el.getBoundingClientRect() : null;
  return { open: w.classList.contains('open'), subs: subs.length, labels: subs.map((s) => ((s.querySelector('.hd-lab') || {}).textContent || '').replace(/:$/, '')),
    msgs: msgs.length, cut: msgs.filter((m) => m.scrollWidth > m.clientWidth + 1).length, label: vis(lab) ? lab.textContent : '', box: vis(box), field: vis(w.querySelector('.hd-box > textarea')),
    lastMsg: msgs.length ? rect(msgs[msgs.length - 1]).bottom : null, firstSub: subs.length ? rect(subs[0]).top : null, lastSub: subs.length ? rect(subs[subs.length - 1]).bottom : null,
    labelTop: lab ? rect(lab).top : null, labelBottom: lab ? rect(lab).bottom : null, boxTop: box ? rect(box).top : null,
    more: Array.from(w.querySelectorAll('button')).filter((b) => vis(b) && /more|context|details/i.test(b.textContent)).map((b) => b.textContent) };
})()`;
// Question n's box, as computed: its edge (colour, width, contrast against the page), its label and
// how it is tied, its field's height in lines, and where the Send key stands.
const BOX = (n) => `(() => {
  const w = ${FIND(n)};
  const box = w.querySelector('.hd-box'), f = box.querySelector('textarea'), s = box.querySelector('.hd-send'), lab = w.querySelector('.hd-anslab');
  const cs = getComputedStyle(box);
  const rgb = (t) => { const m = /rgba?\\((\\d+), (\\d+), (\\d+)/.exec(t || ''); return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : null; };
  const lum = (c) => { const a = c.map((v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }); return 0.2126 * a[0] + 0.7152 * a[1] + 0.0722 * a[2]; };
  const ratio = (a, b) => (a && b) ? (Math.max(lum(a), lum(b)) + 0.05) / (Math.min(lum(a), lum(b)) + 0.05) : 0;
  const edge = rgb(cs.boxShadow), page = rgb(getComputedStyle(document.body).backgroundColor);
  const br = box.getBoundingClientRect(), sr = s.getBoundingClientRect();
  return { shadow: cs.boxShadow, width: Number((/([0-9.]+)px inset/.exec(cs.boxShadow) || [])[1] || 0), ratio: Math.round(ratio(edge, page) * 100) / 100,
    labelTag: lab ? lab.tagName : '', labelFor: lab ? lab.htmlFor : '', fieldId: f.id, labelText: lab ? lab.textContent : '', tied: f.labels ? Array.from(f.labels).indexOf(lab) >= 0 : false,
    height: f.getBoundingClientRect().height, line: parseFloat(getComputedStyle(f).lineHeight), focused: document.activeElement === f,
    sendText: s.textContent, sendParent: s.parentElement === box, sendInside: sr.left >= br.left && sr.right <= br.right + 0.5 && sr.top >= br.top && sr.bottom <= br.bottom + 0.5, sendSeen: sr.height > 0,
    sendX: sr.left + sr.width / 2, sendY: sr.top + sr.height / 2 };
})()`;
const details = (n) => evaluate(DETAILS(n));
const boxOf = (n) => evaluate(BOX(n));
// A real tap on question n's words, or in its field; each brought into the middle of the screen first.
async function tapAt(n, sel) {
  const p = await evaluate(`(() => { const w = ${FIND(n)}; const el = w && w.querySelector(${JSON.stringify(sel)}); if (!el) return null; el.scrollIntoView({ block: 'center' }); const r = el.getBoundingClientRect(); return { x: r.left + 12, y: r.top + 10 }; })()`);
  if (p) await touch(p.x, p.y);
  return p;
}
async function tapSend(n) { const b = await boxOf(n); await touch(b.sendX, b.sendY); await sleep(100); await settle(); }
async function tapFold() { const p = await evaluate("(() => { scrollTo(0, 0); const r = document.querySelector('#list .hd-foldall').getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; })()"); await touch(p.x, p.y); }
const ready = async () => { for (let i = 0; i < 50 && !(await evaluate("window.hostReady === true")); i++) await sleep(50); };
const dark = (on) => cdp("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: on ? "dark" : "light" }] });
const inOrder = (d) => d.lastMsg !== null && d.firstSub !== null && d.lastMsg <= d.firstSub + 0.5 && d.lastSub <= d.labelTop + 0.5 && d.labelBottom <= d.boxTop + 0.5;

try {
  // ---------------- 1. ONE TAP SHOWS EVERYTHING, IN ONE RUN ENDING WITH THE BOX ----------------
  await load("/cards.html"); await ready();
  await evaluate("localStorage.clear(), true");
  await load("/cards.html"); await ready();
  await hostList(LIST);
  let d = await details(2);
  check(!!d && d.open && d.subs === WANT_LABELS.length && d.msgs === 3 && d.cut === 0 && d.box, "CONTROL: on the phone a question starts unfolded, every detail shown and the box with it", JSON.stringify(d));
  check(!!d && inOrder(d), "unfolded, the details are one run: what was said, then the context, then the label, then the box last - nothing of it under the box", JSON.stringify(d));
  await tapFold();
  d = await details(2);
  check(!!d && !d.open && d.subs === 0 && d.cut >= 1 && d.box, "CONTROL: Collapse all folds it - its context gone, what was said before cut to one line - and the box stays", JSON.stringify(d));
  await tapAt(2, ".hd-qt .hd-txt");
  d = await details(2);
  check(!!d && d.open && d.subs === WANT_LABELS.length && JSON.stringify(d.labels) === JSON.stringify(WANT_LABELS), "ONE TAP on its words shows every detail: options, what it is, the recommendation, who asked, files, references, how it is answered", JSON.stringify(d && d.labels));
  check(!!d && d.msgs === 3 && d.cut === 0, "and what was said, every message whole, none cut", JSON.stringify(d));
  check(!!d && d.label.indexOf("Your answer") === 0 && d.box && d.field && inOrder(d), "and the label and the box last, in the same one run", JSON.stringify(d));
  check(!!d && d.more.length === 0, "NO SECOND STAGE: nothing is left on it to press for more", JSON.stringify(d && d.more));
  const other = await details(1);
  check(!!other && !other.open && other.subs === 0, "CONTROL: the tap unfolded that question only", JSON.stringify(other));
  await tapAt(2, ".hd-qt .hd-txt");
  d = await details(2);
  check(!!d && !d.open && d.subs === 0 && d.box, "a second tap on its words folds it again: the details go, the box stays (the window answers in every box with nothing unfolded)", JSON.stringify(d));
  await tapFold();
  const all = await Promise.all([1, 2, 3].map(details));
  check(all.every((x) => x && x.open && x.subs === WANT_LABELS.length && x.cut === 0), "Expand all unfolds every question whole, in one press", JSON.stringify(all.map((x) => x && [x.open, x.subs, x.cut])));

  // ---------------- 2. THE BOX: EDGE, LABEL, HEIGHT, RING, SEND ----------------
  let b = await boxOf(3);
  check(b.width >= 1 && /inset/.test(b.shadow), "THE BOX HAS AN EDGE: a visible line all round it (a shadow inside, so the letters stay sharp)", b.shadow);
  check(b.ratio >= 4.5, "its edge stands at least 4.5 to 1 against the page, light", String(b.ratio));
  await dark(true); await settle();
  const bd = await boxOf(3);
  check(bd.ratio >= 4.5 && bd.width >= 1, "and at least 4.5 to 1 in the dark", String(bd.ratio) + " " + bd.shadow);
  await dark(false); await settle();
  check(b.labelTag === "LABEL" && b.labelText.indexOf("Your answer") === 0 && b.fieldId !== "" && b.labelFor === b.fieldId && b.tied, "A LABEL IN WORDS, 'Your answer', stands over it, tied to its field (for and id)", JSON.stringify({ tag: b.labelTag, text: b.labelText, for: b.labelFor, id: b.fieldId, tied: b.tied }));
  check(b.height >= 3 * b.line - 1, "on a phone the empty box is at least three lines tall", b.height + " px, line " + b.line);
  check(b.sendText === "Send" && b.sendParent && b.sendInside && b.sendSeen, "THE SEND KEY IS ATTACHED: inside the box's edge, saying Send", JSON.stringify(b));
  await tapAt(3, ".hd-box > textarea");
  const ringed = await boxOf(3);
  check(ringed.focused && ringed.width >= 2 && ringed.shadow !== b.shadow, "THE CARET IN IT, the box has a clear ring: wider, and in another colour", ringed.shadow + " was " + b.shadow);
  await type("one\ntwo\nthree\nfour\nfive");
  const grown = await boxOf(3);
  check(grown.height >= 5 * grown.line - 1, "TYPING GROWS IT: five lines typed, five lines tall", grown.height + " px");
  await type("\n" + Array.from({ length: 30 }, (_, i) => "more " + i).join("\n"));
  const capped = await boxOf(3);
  check(capped.height <= 12 * capped.line + 1 && capped.height >= 11 * capped.line, "and only up to twelve lines; past them it scrolls", capped.height + " px, line " + capped.line);

  // ---------------- 3. SEND SENDS, AND KEEPS THE CARET ----------------
  // The words typed above are a draft kept in this origin's storage: cleared, so the boxes start empty.
  await evaluate("localStorage.clear(), true");
  await load("/host.html?say=ok");
  await hostList(LIST);
  await tapAt(3, ".hd-box > textarea");
  await tapSend(3);
  check((await evaluate("window.said.length")) === 0, "CONTROL: Send on an empty box sends nothing", JSON.stringify(await evaluate("window.said")));
  await type("the second thing");
  await tapSend(3);
  await sleep(200);
  const said = await evaluate("window.said");
  check(said.length === 1 && said[0].n === 3 && said[0].t === "the second thing", "A TAP ON SEND sends what is typed in that box, as Enter does", JSON.stringify(said));
  const after = await evaluate("(() => { const a = document.activeElement; const w = a && a.closest && a.closest('.hd-q'); const m = w ? /Question (\\d+):/.exec(w.querySelector('.hd-qt').textContent) : null; return { tag: a ? a.tagName : '', n: m ? Number(m[1]) : 0 }; })()");
  check(after.tag === "TEXTAREA" && after.n !== 3 && after.n > 0, "and the caret goes on to the next question's box, never lost to the key", JSON.stringify(after));

  // ---------------- 4. THE WINDOW'S HOST: FOLDED, EVERY BOX STILL THERE ----------------
  await load("/host.html?expanded=0");
  await hostList(LIST);
  const win = await Promise.all([1, 2, 3].map(details));
  check(win.every((x) => x && !x.open && x.subs === 0 && x.box && x.label.indexOf("Your answer") === 0), "the window's host opens folded, and every question still shows its label and box, nothing unfolded to reach them", JSON.stringify(win.map((x) => x && [x.open, x.subs, x.box, x.label])));

  // ---------------- 5. THE ANSWERED ARE HIDDEN UNTIL ASKED FOR ----------------
  // Twelve to answer (taller than the screen), two answered (With Thrall) and one closed (History).
  const answered = (n) => question(n, { importance: "low", thread: { messages: [{ speaker: "founder", text: "Yes.", sequence: n }] } });
  const SWITCH_LIST = () => { const qs = []; for (let n = 1; n <= 12; n++) qs.push(full(n + 20)); return qs.concat([answered(40), answered(41), question(42, { state: "closed", closedAt: "2026-10-14T10:00:00Z" })]); };
  const TOP = `(() => {
    const sw = document.querySelector('#list .hd-showans'), fa = document.querySelector('#list .hd-foldall');
    const s = sw ? sw.getBoundingClientRect() : null, f = fa ? fa.getBoundingClientRect() : null;
    const tops = Array.from(document.querySelectorAll('#list .hd-order-btn')).map((b) => Math.round(b.getBoundingClientRect().top));
    const lines = Array.from(document.querySelectorAll('#list .hd-q:not(.hd-done):not(.answered)')).map((w) => { const m = /Question (\\d+):/.exec((w.querySelector('.hd-qt') || {}).textContent || ''); const r = w.getBoundingClientRect(); return { n: m ? Number(m[1]) : 0, top: r.top, bottom: r.bottom, open: w.classList.contains('open') }; });
    const inView = lines.filter((l) => l.bottom > 0 && l.top < innerHeight);
    return { text: sw ? sw.textContent : '', role: sw ? sw.getAttribute('role') : '', checked: sw ? sw.getAttribute('aria-checked') : '', says: sw ? sw.getAttribute('aria-label') : '',
      x: s ? s.left + s.width / 2 : 0, y: s ? s.top + s.height / 2 : 0, swTop: s ? Math.round(s.top) : null, faTop: f ? Math.round(f.top) : null, swLeft: s ? s.left : 0, faLeft: f ? f.left : 0,
      orderOneLine: tops.length === 3 && new Set(tops).size === 1,
      folded: Array.from(document.querySelectorAll('#list .hd-q.answered:not(.hd-done)')).map((w) => { const m = /Question (\\d+):/.exec((w.querySelector('.hd-qt') || {}).textContent || ''); return m ? Number(m[1]) : 0; }).join(','),
      done: document.querySelectorAll('#list .hd-done').length, heads: Array.from(document.querySelectorAll('#list .hd-head .hd-txt')).map((t) => t.textContent).filter((t) => /With Thrall|History/.test(t)),
      main: lines.map((l) => l.n).join(','), open: lines.filter((l) => l.open).map((l) => l.n).join(','), first: inView.length ? { n: inView[0].n, top: Math.round(inView[0].top) } : null, scrollY: Math.round(scrollY), order: window.doc.order() };
  })()`;
  const top = () => evaluate(TOP);
  const openCards = async () => { await load("/cards.html"); await ready(); };
  await openCards();
  await evaluate("localStorage.clear(), true");
  await openCards();
  await hostList(SWITCH_LIST());
  let t = await top();
  check(t.done === 0 && t.heads.length === 0 && t.main.split(",").length === 12 && t.folded.split(",").sort().join(",") === "40,41", "BY DEFAULT THE ANSWERED ARE HIDDEN: no With Thrall, no History, the twelve to answer shown (and the two answered, not closed, stand in his list as folded lines, T-0152)", JSON.stringify(t));
  check(t.text === "Show answered and closed: off" && t.role === "switch" && t.checked === "false" && /hidden/i.test(t.says), "a switch says so in words - 'Show answered and closed: off' - and to a screen reader (role switch, not checked)", JSON.stringify({ text: t.text, role: t.role, checked: t.checked, says: t.says }));
  check(t.swTop !== null && t.swTop === t.faTop && t.swLeft < t.faLeft && t.orderOneLine, "it stands at the head of the page across from Collapse all, and the order line stays one line on a phone", JSON.stringify({ sw: t.swTop, fa: t.faTop, oneLine: t.orderOneLine }));
  // His order and a fold of his own, then the page scrolled so the switch is still on the screen.
  const imp = await evaluate("(() => { const b = Array.from(document.querySelectorAll('#list .hd-order-btn')).find((x) => x.textContent.indexOf('Task importance') === 0); const r = b.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; })()");
  await touch(imp.x, imp.y);
  await tapAt(25, ".hd-qt .hd-txt");
  await evaluate("(() => { scrollTo(0, 0); const r = document.querySelector('#list .hd-showans').getBoundingClientRect(); scrollTo(0, Math.max(0, r.top - 120)); return true; })()");
  await settle();
  const was = await top();
  check(was.order === "importance" && was.open.split(",").indexOf("25") < 0 && was.scrollY > 0, "CONTROL: his order is Task importance, question 25 folded by his tap, the page scrolled", JSON.stringify({ order: was.order, open: was.open, scrollY: was.scrollY }));
  await touch(was.x, was.y);
  t = await top();
  check(t.text === "Show answered and closed: on" && t.checked === "true" && t.done === 3 && t.folded === "" && t.heads.some((h) => /^With Thrall \(2\)/.test(h)) && t.heads.some((h) => /^History \(1\)/.test(h)), "A TAP SHOWS THEM: the switch says on, With Thrall (2) and History (1) stand below the list as before", JSON.stringify({ text: t.text, heads: t.heads, done: t.done }));
  check(t.order === was.order && t.main === was.main && t.open === was.open, "and it touches neither the order nor what is folded", JSON.stringify({ was: [was.order, was.open], now: [t.order, t.open] }));
  check(!!t.first && !!was.first && t.first.n === was.first.n && Math.abs(t.first.top - was.first.top) <= 1 && t.scrollY === was.scrollY, "nor his place: the same question at the same pixel, the page scrolled as it was", JSON.stringify({ was: was.first, now: t.first, y: [was.scrollY, t.scrollY] }));
  await openCards();
  await hostList(SWITCH_LIST());
  t = await top();
  check(t.text === "Show answered and closed: on" && t.done === 3, "KEPT ON THIS DEVICE: opened again, they are still shown", JSON.stringify({ text: t.text, done: t.done }));
  await evaluate("scrollTo(0, 0), true"); await settle();
  t = await top();
  await touch(t.x, t.y);
  await openCards();
  await hostList(SWITCH_LIST());
  t = await top();
  check(t.text === "Show answered and closed: off" && t.done === 0, "and hidden again, kept hidden through opening again", JSON.stringify({ text: t.text, done: t.done }));
  // THE SWITCH IS REACHED BY KEYS, never by Tab (review of PR 311): real key presses from a field.
  // Ctrl+Down with no fold drawn comes to it; Space turns it on; Down goes to the first fold and Up
  // comes back; Enter turns it off; Shift+Tab goes back to the list. A ring shows where the keyboard is.
  const press = async (k, code, vk, modifiers = 0, text = undefined) => {
    await cdp("Input.dispatchKeyEvent", { type: text ? "keyDown" : "rawKeyDown", key: k, code, windowsVirtualKeyCode: vk, modifiers, text });
    await cdp("Input.dispatchKeyEvent", { type: "keyUp", key: k, code, windowsVirtualKeyCode: vk, modifiers });
    await sleep(80);
    await settle();
  };
  const AT = `(() => {
    const a = document.activeElement, sw = document.querySelector('#list .hd-showans'), cs = getComputedStyle(sw);
    return { onSwitch: a === sw, tri: (a && a.classList.contains('hd-tri')) ? (a.getAttribute('aria-label') || '') : '', field: !!a && a.tagName === 'TEXTAREA',
      ring: a === sw ? cs.outlineStyle + ' ' + cs.outlineWidth : '', tab: sw.tabIndex, checked: sw.getAttribute('aria-checked'), done: document.querySelectorAll('#list .hd-done').length };
  })()`;
  await evaluate("scrollTo(0, 0), document.querySelector('#list .hd-q:not(.hd-done):not(.answered) .hd-box > textarea').focus(), true");
  await settle();
  let k = await evaluate(AT);
  check(k.field && !k.onSwitch && k.tab === -1, "CONTROL: the caret in the first question's field, and the switch out of the Tab run (tabIndex -1)", JSON.stringify(k));
  await press("ArrowDown", "ArrowDown", 40, 2);
  k = await evaluate(AT);
  check(k.onSwitch && k.ring === "solid 1px", "Ctrl+Down with no fold drawn brings the keyboard to the switch, with a ring around it", JSON.stringify(k));
  await press(" ", "Space", 32, 0, " ");
  k = await evaluate(AT);
  check(k.onSwitch && k.checked === "true" && k.done === 3, "Space turns it on: the answered and closed are shown, and the keyboard stays on the switch", JSON.stringify(k));
  await press("ArrowDown", "ArrowDown", 40);
  k = await evaluate(AT);
  check(/With Thrall/.test(k.tri), "Down goes to the first fold, With Thrall", JSON.stringify(k));
  await press("ArrowUp", "ArrowUp", 38);
  k = await evaluate(AT);
  check(k.onSwitch, "Up from the first fold comes back to the switch", JSON.stringify(k));
  await press("Enter", "Enter", 13, 0, "\r");
  k = await evaluate(AT);
  check(k.onSwitch && k.checked === "false" && k.done === 0, "Enter turns it off again", JSON.stringify(k));
  await press("Tab", "Tab", 9, 8);
  k = await evaluate(AT);
  check(k.field && !k.onSwitch, "Shift+Tab goes back to the list, into a question's field", JSON.stringify(k));
  await evaluate("document.activeElement.blur(), true");
  // A question answered while he reads, one above the view and one in it: each leaves, and the
  // question at the top of the view does not move.
  await evaluate("(() => { const w = " + FIND(27) + "; scrollTo(0, 0); scrollTo(0, w.getBoundingClientRect().top - 60); return true; })()");
  await settle();
  const before = await top();
  const shown = before.main.split(",").map(Number);
  const above = shown[shown.indexOf(before.first.n) - 1];
  const below = shown[shown.indexOf(before.first.n) + 1];
  await hostList(SWITCH_LIST().map((q) => (q.number === above || q.number === below) ? { ...q, thread: { messages: q.thread.messages.concat([{ speaker: "founder", text: "Done.", sequence: 90 + q.number }]) } } : q));
  await settle();
  const after2 = await top();
  check(above > 0 && below > 0 && after2.main.split(",").indexOf(String(above)) < 0 && after2.main.split(",").indexOf(String(below)) < 0 && after2.done === 0, "A QUESTION ANSWERED leaves the list and is not shown (one above the view, one in it)", JSON.stringify({ above, below, main: after2.main, done: after2.done }));
  check(!!after2.first && after2.first.n === before.first.n && Math.abs(after2.first.top - before.first.top) <= 1, "and nothing jumps: the question at the top of the view stays at its pixel", JSON.stringify({ before: before.first, after: after2.first }));

  check(problems.length === 0, "the page threw nothing", problems.join(" | "));
} catch (e) {
  check(false, "the driver ran to its end", String(e && e.stack || e));
}
finish();
