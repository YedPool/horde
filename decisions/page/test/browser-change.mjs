// "CHANGE MY ANSWER" IN A REAL BROWSER, ON A PHONE (decisions/page/list.js, CHANGE MY ANSWER), for
// test/test-decisions-page-browser.ps1: headless Chrome on a 412 px screen with touch, through
// browser-harness.mjs, on the phone's page (cards first, its own style sheet); the button, the boxes and
// the keys are pressed by REAL TOUCH EVENTS and words are typed as a keyboard types them.
//
// T-0152, the founder on Q67 (2026-10-15): "On a phone it is easy to tap the wrong option." Checked here:
//   1. THE BUTTON is on an answered question that is not closed, big enough for a thumb (44 px), and on
//      no other: not on a closed question, not on one he has not answered.
//   2. THE STATUS LINES, in plain words and never silent: "answer changed - waiting for Orc F to confirm"
//      until the Orc replies, then "You changed your answer at <time>. Orc F had not acted yet and is
//      using the new answer." / "... had already acted on the first one and is undoing it." / "... says
//      it cannot undo: <why>."; and, under a closed question, "This question is closed - Orc F has acted
//      on it. To change course, ask a follow-up." with no button.
//   3. A TAP REOPENS THE ANSWER BOX with his current answer in it, selected, the caret in it, the label
//      "Your answer" over it and "Keep my answer" beside it; the question stands in his list again.
//   4. WHAT HE SENDS is the ordinary answer: the host is handed the question's number and his new words,
//      the box turns green, and the question goes back to the answered fold; a host that refuses leaves the
//      words in the box with the refusal under them, the question in his list.
//   5. KEEP MY ANSWER puts it back as it was and sends nothing.
//   6. NOTHING SCROLLS SIDEWAYS on the phone.
//
//   node browser-change.mjs <decisions/page folder> <chrome.exe> <profile folder>
//
// Prints one line per check, "[PASS] name" or "[FAIL] name: detail", then "[DONE] n".
import { openBrowser, check, question, sleep } from "./browser-harness.mjs";

const [, , pageDir, chromePath, profileDir] = process.argv;
const { evaluate, load, touch, type, settle, problems, finish } = await openBrowser(pageDir, chromePath, profileDir);

const AT = "2026-10-17T14:02:00.0000000Z";
const said = (seq, text) => ({ speaker: "founder", text, sequence: seq, at: "2026-10-17T13:00:00.0000000Z", asks: true, act: "", part: "" });
const change = (n, reply) => {
  const c = { answer: 20 + n, at: AT, from: 10 + n, oldText: "The first answer.", newText: "The second answer.", part: "", orcShown: "Orc F" };
  if (reply) c.reply = reply;
  return c;
};
// A question he has answered twice (the second is the change), asked by Orc F, with the change's reply.
const changed = (n, reply, more = {}) => question(n, { askedBy: "Orc F", thread: { messages: [said(10 + n, "The first answer."), { ...said(20 + n, "The second answer."), changedFrom: 10 + n, changedFromText: "The first answer." }] }, answerChanges: [change(n, reply)], ...more });
const reply = (word, shown, why = "") => ({ sequence: 99, at: AT, by: "F", reply: word, replyShown: shown, why });
const withWording = (q) => ({ wordingVersion: 1, ...q });
const LIST = () => [
  question(10, { askedBy: "Orc F", thread: { messages: [said(5, "Yes, go ahead.")] } }),
  changed(11, null),
  changed(12, reply("not-acted", "not acted yet, using the new answer")),
  changed(13, reply("undoing", "already acted, undoing")),
  changed(14, reply("cannot-undo", "already acted, cannot undo", "the deploy already went out")),
  question(15, { askedBy: "Orc F", state: "closed", closedAt: "2026-10-17T12:00:00Z", closedBy: "Orc F", actedBy: "Orc F", outcome: "Done.", thread: { messages: [said(6, "Yes.")] } }),
  question(16, { askedBy: "Orc F", state: "closed", closedAt: "2026-10-17T12:00:00Z", actedBy: "Orc F", outcome: "Dropped.", thread: { messages: [] } }),
  question(17, { askedBy: "Orc F", thread: { messages: [] } }),
  question(18, { askedBy: "Orc F", thread: { messages: [said(8, "Option two.")] } }),
  // Changed twice: the first change was replied to, the second is still waiting. The page tells the newest.
  changed(20, null, { answerChanges: [change(20, reply("not-acted", "not acted yet, using the new answer")), { ...change(20, null), answer: 41, from: 30, at: "2026-10-17T15:30:00.0000000Z" }] })
].map(withWording);
const hostList = (qs) => evaluate("window.hostList(" + JSON.stringify(qs) + "), true");
const ready = async () => { for (let i = 0; i < 50 && !(await evaluate("window.hostReady === true")); i++) await sleep(50); };
const FIND_ROW = (n) => `Array.from(document.querySelectorAll('#list .hd-q')).find((x) => new RegExp('Question ${n}:').test((x.querySelector('.hd-qt') || {}).textContent || ''))`;
const vis = "const vis = (el) => !!el && el.offsetParent !== null && el.getBoundingClientRect().height > 0;";
// What question n shows: where it stands (an answered row, or a line of his list), its status lines, the
// button, and the closed line.
const ROW = (n) => `(() => { ${vis}
  const w = ${FIND_ROW(n)};
  if (!w) return null;
  const btn = w.querySelector('.hd-changebtn');
  const b = btn ? btn.getBoundingClientRect() : null;
  const keep = w.querySelector('.hd-keep');
  const f = w.querySelector('.hd-box > textarea');
  return { done: w.classList.contains('hd-done'), shown: vis(w), lines: Array.from(w.querySelectorAll('.hd-change:not(.hd-closedline)')).filter(vis).map((x) => x.textContent),
    closed: Array.from(w.querySelectorAll('.hd-closedline')).filter(vis).map((x) => x.textContent), button: vis(btn) ? btn.textContent : '', buttonH: b ? b.height : 0, buttonW: b ? b.width : 0,
    keep: vis(keep) ? keep.textContent : '', field: vis(f), value: f ? f.value : null, selFrom: f ? f.selectionStart : -1, selTo: f ? f.selectionEnd : -1, focused: !!f && document.activeElement === f,
    label: vis(w.querySelector('.hd-anslab')) ? w.querySelector('.hd-anslab').textContent : '', refusal: Array.from(w.querySelectorAll('.hd-refusal')).filter(vis).map((x) => x.textContent).join('|'),
    green: w.classList.contains('saved-now'), folded: w.classList.contains('answered') }; })()`;
const row = (n) => evaluate(ROW(n));
async function tapIn(n, sel) {
  const p = await evaluate(`(() => { const w = ${FIND_ROW(n)}; const el = w && w.querySelector(${JSON.stringify(sel)}); if (!el) return null; el.scrollIntoView({ block: 'center' }); const r = el.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + Math.min(r.height / 2, 20) }; })()`);
  if (p) await touch(p.x, p.y);
  return p;
}
// The two answered folds opened by real taps on their headings, and the switch that shows them.
async function showAnswered() {
  const sw = await evaluate("(() => { const s = document.querySelector('#list .hd-showans'); s.scrollIntoView({ block: 'center' }); const r = s.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2, on: /: on/.test(s.textContent) }; })()");
  if (!sw.on) await touch(sw.x, sw.y);
  for (const word of ["With Thrall", "History"]) {
    const h = await evaluate(`(() => { const t = Array.from(document.querySelectorAll('#list .hd-head')).find((x) => x.textContent.indexOf(${JSON.stringify(word)}) === 0 || x.textContent.indexOf(${JSON.stringify(word)}) > -1); if (!t) return null; const g = t.parentElement; if (!g.classList.contains('folded')) return { open: true }; t.scrollIntoView({ block: 'center' }); const r = t.getBoundingClientRect(); return { x: r.left + 40, y: r.top + r.height / 2, open: false }; })()`);
    if (h && !h.open) await touch(h.x, h.y);
  }
}
const localTime = (iso) => evaluate(`(() => { const d = new Date(${JSON.stringify(iso)}); const t = (n) => (n < 10 ? '0' : '') + n; return t(d.getHours()) + ':' + t(d.getMinutes()); })()`);

try {
  await load("/cards.html?say=ok"); await ready();
  await evaluate("localStorage.clear(), true");
  await load("/cards.html?say=ok"); await ready();
  await hostList(LIST());
  await showAnswered();
  const clock = await localTime(AT);

  // ---------------- 1. THE BUTTON ----------------
  let r10 = await row(10);
  check(!!r10 && r10.done && r10.shown && r10.button === "Change my answer", "CONTROL: an answered question that is not closed shows 'Change my answer' in its row", JSON.stringify(r10));
  check(!!r10 && r10.buttonH >= 44 && r10.buttonW >= 44, "and it is big enough for a thumb: at least 44 px each way", r10 && (r10.buttonW + " x " + r10.buttonH));
  const r17 = await row(17);
  const r15 = await row(15);
  const r16 = await row(16);
  check(!r17 || (!r17.done && r17.button === ""), "a question he has not answered has no such button (it has its box)", JSON.stringify(r17));
  check(!!r15 && r15.done && r15.button === "" && r16 && r16.button === "", "a closed question has no such button", JSON.stringify({ r15: r15 && r15.button, r16: r16 && r16.button }));

  // ---------------- 2. THE STATUS LINES ----------------
  const r11 = await row(11), r12 = await row(12), r13 = await row(13), r14 = await row(14);
  check(!!r11 && r11.lines.length === 1 && r11.lines[0] === "answer changed - waiting for Orc F to confirm", "NO REPLY YET: 'answer changed - waiting for Orc F to confirm'", JSON.stringify(r11 && r11.lines));
  check(!!r12 && r12.lines.length === 1 && r12.lines[0] === "You changed your answer at " + clock + ". Orc F had not acted yet and is using the new answer.", "NOT ACTED: says so plainly, with the time he changed it", JSON.stringify(r12 && r12.lines));
  check(!!r13 && r13.lines.length === 1 && r13.lines[0] === "You changed your answer at " + clock + ". Orc F had already acted on the first one and is undoing it.", "UNDOING: says so plainly", JSON.stringify(r13 && r13.lines));
  check(!!r14 && r14.lines.length === 1 && r14.lines[0] === "You changed your answer at " + clock + ". Orc F had already acted on the first one and says it cannot undo: the deploy already went out.", "CANNOT UNDO: says so, and why, in the Orc's words", JSON.stringify(r14 && r14.lines));
  const r20 = await row(20);
  check(!!r20 && r20.lines.length === 1 && r20.lines[0] === "answer changed - waiting for Orc F to confirm", "CHANGED TWICE: the line tells the NEWEST change, still waiting, not the earlier one that was replied to", JSON.stringify(r20 && r20.lines));
  check(!!r11 && r11.button === "Change my answer" && !!r14 && r14.button === "Change my answer", "a changed answer that is still open can be changed again", JSON.stringify([r11 && r11.button, r14 && r14.button]));
  check(!!r15 && r15.closed.length === 1 && r15.closed[0] === "This question is closed - Orc F has acted on it. To change course, ask a follow-up.", "CLOSED: one plain line says why there is no button, and what to do instead", JSON.stringify(r15 && r15.closed));
  check(!!r16 && r16.closed.length === 0, "a closed question he never answered says nothing of changing", JSON.stringify(r16 && r16.closed));
  check(!!r10 && r10.lines.length === 0, "a question he never changed has no status line", JSON.stringify(r10 && r10.lines));

  // ---------------- 3. A TAP REOPENS THE ANSWER BOX ----------------
  await tapIn(10, ".hd-changebtn");
  await sleep(100); await settle();
  let o = await row(10);
  check(!!o && !o.done && o.field && o.value === "Yes, go ahead.", "A TAP brings the question back into his list with its answer box open and his current answer in it", JSON.stringify(o));
  check(!!o && o.focused && o.selFrom === 0 && o.selTo === "Yes, go ahead.".length, "the answer is SELECTED and the caret is in the box, so the next words replace it", JSON.stringify({ focused: o.focused, from: o.selFrom, to: o.selTo }));
  check(!!o && o.label.indexOf("Your answer") === 0 && o.keep === "Keep my answer", "the label 'Your answer' stands over the box, and 'Keep my answer' beside it", JSON.stringify({ label: o.label, keep: o.keep }));
  check(!!o && !o.folded && !o.green, "and it is not folded away to 'Answered' while he changes it", JSON.stringify(o));
  const gone = await evaluate("Array.from(document.querySelectorAll('#list .hd-done')).filter((x) => /Question 10:/.test(x.textContent)).length");
  check(gone === 0, "it has left the answered fold: it is in one place only", String(gone));

  // ---------------- 4. WHAT HE SENDS IS THE ORDINARY ANSWER ----------------
  await type("Option three.");
  const typed = await row(10);
  check(typed.value === "Option three.", "the first words typed replace the selected answer", JSON.stringify(typed.value));
  await tapIn(10, ".hd-send");
  await sleep(200); await settle();
  const sent = await evaluate("window.said");
  check(sent.length === 1 && sent[0].n === 10 && sent[0].t === "Option three." && sent[0].w === 1 && /^[0-9a-f]{32}$/.test(sent[0].id), "the host is handed question 10 and his new words, with the wording he saw and a fresh id: the ordinary save", JSON.stringify(sent));
  const saved = await row(10);
  check(saved.green || saved.folded, "and it turns green as any saved answer does", JSON.stringify({ green: saved.green, folded: saved.folded }));
  check(saved.keep === "", "and 'Keep my answer' is gone once it is saved", JSON.stringify(saved.keep));
  // The list that holds his change arrives: the question is in the answered fold with the status line.
  const arrived = changed(10, null, { askedBy: "Orc F" });
  arrived.answerChanges[0].newText = "Option three.";
  await hostList(LIST().map((q) => q.number === 10 ? withWording(arrived) : q));
  await sleep(4500);
  await hostList(LIST().map((q) => q.number === 10 ? withWording(arrived) : q));
  await settle();
  const after = await row(10);
  check(!!after && after.done && after.lines.length === 1 && after.lines[0] === "answer changed - waiting for Orc F to confirm", "when the list holds it, the question is back in the answered fold and says 'answer changed - waiting for Orc F to confirm'", JSON.stringify(after));

  // ---------------- 5. KEEP MY ANSWER ----------------
  await tapIn(18, ".hd-changebtn");
  await sleep(100); await settle();
  let k = await row(18);
  check(!!k && !k.done && k.value === "Option two." && k.keep === "Keep my answer", "a second question: the tap reopens it the same way", JSON.stringify(k));
  await type("Something I decide against");
  const sentBefore = (await evaluate("window.said")).length;
  await tapIn(18, ".hd-keep");
  await sleep(100); await settle();
  k = await row(18);
  check(!!k && k.done && k.button === "Change my answer" && k.field === false, "KEEP MY ANSWER puts it back in the answered fold with its button", JSON.stringify(k));
  check((await evaluate("window.said")).length === sentBefore, "and sends nothing", String((await evaluate("window.said")).length) + " vs " + sentBefore);
  await tapIn(18, ".hd-changebtn");
  await sleep(100); await settle();
  k = await row(18);
  check(!!k && k.value === "Option two.", "and the words he typed and dropped do not come back: the box holds his answer again", JSON.stringify(k && k.value));

  // ---------------- 5b. THE BUTTON ON THE FOLDED 'Answered' LINE ----------------
  // Right after a wrong tap, with the answered fold still OFF (the default): the question stands folded to
  // 'Answered' for a moment, and the button is beside it.
  await load("/cards.html?say=ok"); await ready();
  await evaluate("localStorage.clear(), true");
  await load("/cards.html?say=ok"); await ready();
  await hostList([withWording(question(30, { askedBy: "Orc F", thread: { messages: [] } }))]);
  await tapIn(30, ".hd-box > textarea");
  await type("The wrong option.");
  await tapIn(30, ".hd-send");
  await sleep(1800); await settle();
  let fl = await evaluate(`(() => { ${vis} const w = ${FIND_ROW(30)}; if (!w) return null; const b = w.querySelector('.hd-changebtn'); const d = w.querySelector('.hd-answered'); const r = b ? b.getBoundingClientRect() : null;
    return { folded: w.classList.contains('answered'), answered: vis(d) ? d.textContent : '', button: vis(b) ? b.textContent : '', h: r ? r.height : 0, switchText: document.querySelector('#list .hd-showans').textContent }; })()`);
  check(!!fl && fl.folded && fl.answered === "Answered" && fl.button === "Change my answer" && fl.h >= 44, "RIGHT AFTER A WRONG TAP, with the answered fold off, the folded 'Answered' line has 'Change my answer' beside it (44 px)", JSON.stringify(fl));
  check(!!fl && /: off/.test(fl.switchText), "and nothing had to be switched on to reach it", JSON.stringify(fl && fl.switchText));
  // WELL AFTER THE OLD 4 SECONDS (the page used to move the line to the hidden fold then), and with the list that
  // holds his answer arrived, the folded line and its button are still in his list: the Orc has not closed it.
  await sleep(6000);
  const held = withWording(question(30, { askedBy: "Orc F", thread: { messages: [said(77, "The wrong option.")] } }));
  await hostList([held]);
  await settle();
  const late = await evaluate(`(() => { ${vis} const w = ${FIND_ROW(30)}; if (!w) return null; const b = w.querySelector('.hd-changebtn'); const d = w.querySelector('.hd-answered'); const r = b ? b.getBoundingClientRect() : null;
    return { folded: w.classList.contains('answered'), inFold: w.classList.contains('hd-done'), answered: vis(d) ? d.textContent : '', button: vis(b) ? b.textContent : '', h: r ? r.height : 0, switchText: document.querySelector('#list .hd-showans').textContent }; })()`);
  check(!!late && late.folded && !late.inFold && late.answered === "Answered" && late.button === "Change my answer" && late.h >= 44 && /: off/.test(late.switchText), "WELL AFTER THE OLD 4 SECONDS (8 s after the tap), with the list that holds his answer arrived and the answered fold off, the folded 'Answered' line and its button are still in his list", JSON.stringify(late));
  // The Orc closes it: it leaves his list for the hidden fold, as before.
  await hostList([withWording(question(30, { askedBy: "Orc F", state: "closed", closedAt: "2026-10-17T12:00:00Z", closedBy: "Orc F", actedBy: "Orc F", outcome: "Done.", thread: { messages: [said(77, "The wrong option.")] } }))]);
  await settle();
  const shut = await row(30);
  const shutRows = await evaluate("document.querySelectorAll('#list .hd-q').length");
  check(shut === null && shutRows === 0, "WHEN THE ORC CLOSES IT, the line is gone from his list, into the hidden fold", JSON.stringify({ shut, shutRows }));
  await hostList([held]);
  await settle();
  await tapIn(30, ".hd-changebtn");
  await sleep(100); await settle();
  const again = await row(30);
  check(!!again && again.field && again.value === "The wrong option." && again.selFrom === 0 && again.selTo === "The wrong option.".length && again.focused && again.keep === "Keep my answer", "a tap on it reopens the box with the answer selected and the caret in it", JSON.stringify(again));

  // ---------------- 5c. A QUESTION OF PARTS: CHANGE PART b, PART a IS UNTOUCHED ----------------
  const partMsg = (seq, part, text) => ({ ...said(seq, text), part });
  await load("/cards.html?say=ok"); await ready();
  await hostList([withWording(question(40, { askedBy: "Orc F", kind: "parts", parts: ["(a) The first step", "(b) The second step"], thread: { messages: [partMsg(41, "a", "Yes to a."), partMsg(42, "b", "Yes to b.")] } }))]);
  await showAnswered();
  const pr = await row(40);
  check(!!pr && pr.done && pr.button === "Change my answer", "CONTROL: a question of parts, every part answered, shows the button in its answered row", JSON.stringify(pr));
  await tapIn(40, ".hd-changebtn");
  await sleep(100); await settle();
  const pf = await evaluate(`(() => { const w = ${FIND_ROW(40)}; const f = Array.from(w.querySelectorAll('.hd-partfield')); return { n: f.length, v: f.map((x) => x.value), done: w.classList.contains('hd-done') }; })()`);
  check(pf.n === 2 && pf.v[0] === "Yes to a." && pf.v[1] === "Yes to b." && !pf.done, "a tap reopens every part's box with its own answer in it", JSON.stringify(pf));
  const said0 = (await evaluate("window.said")).length;
  await evaluate(`(() => { const w = ${FIND_ROW(40)}; const f = w.querySelectorAll('.hd-partfield')[1]; f.scrollIntoView({ block: 'center' }); f.focus(); f.select(); return true; })()`);
  await type("No to b.");
  const sendB = await evaluate(`(() => { const w = ${FIND_ROW(40)}; const s = w.querySelectorAll('.hd-send')[1]; s.scrollIntoView({ block: 'center' }); const r = s.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; })()`);
  await touch(sendB.x, sendB.y);
  await sleep(300); await settle();
  const sentParts = (await evaluate("window.said")).slice(said0);
  check(sentParts.length === 1 && sentParts[0].n === 40 && sentParts[0].t === "(b) No to b.", "changing part b sends part b alone: one answer, for (b)", JSON.stringify(sentParts));
  const after2 = await evaluate(`(() => { const w = ${FIND_ROW(40)}; return Array.from(w.querySelectorAll('.hd-partfield')).map((x) => x.value); })()`);
  check(after2[0] === "Yes to a." && after2[1] === "No to b.", "and part a's answer is untouched", JSON.stringify(after2));

  // ---------------- 6. A HOST THAT REFUSES ----------------
  await load("/cards.html?say=refuse"); await ready();
  await hostList(LIST());
  await showAnswered();
  await tapIn(10, ".hd-changebtn");
  await sleep(100); await settle();
  await type("A change the host will refuse.");
  await tapIn(10, ".hd-send");
  await sleep(300); await settle();
  const refused = await row(10);
  check(!!refused && !refused.done && refused.value === "A change the host will refuse." && /refused by the stand-in host/.test(refused.refusal) && !refused.green, "A REFUSAL: the words stay in the box, the refusal stands under them, nothing turns green, the question stays in his list", JSON.stringify(refused));
  check(!!refused && refused.keep === "Keep my answer", "and he can still keep his answer", JSON.stringify(refused && refused.keep));

  // ---------------- 7. THE PHONE'S WIDTH ----------------
  const wide = await evaluate("({ sw: document.documentElement.scrollWidth, iw: innerWidth })");
  check(wide.sw <= wide.iw, "nothing scrolls sideways on the phone", JSON.stringify(wide));
  check(problems.length === 0, "the page threw nothing", problems.join(" | "));
} catch (e) {
  check(false, "the driver ran to its end", String(e && e.stack || e));
}
finish();
