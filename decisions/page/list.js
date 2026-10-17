// decisions/page/list.js - the list of questions drawn as a document the reader ANSWERS IN: group
// headings, and under each one line per question - the letter of who asked and the question's
// permanent number, the question in full, and a field for the answer that is always there.
//
// ITS JOB is to draw what the decisions operations answered (decisions/Operations.ps1: kinds, and
// list with each conversation in it), exactly as it was handed over, and to hand the reader's words
// to its host to be said (options.say). It knows no bridge and no fleet, and it never decides whether
// words were saved: the host answers that, and until it has, the words are a draft this page keeps.
//
//   var doc = HordeDecisionsDocument.mount(element, { topInset, onDraw, onChange, say, sayPart, storage, prefs });
//     say(number, text, wording, id)  ->  a promise of { ok: true, sequence, ... } or { ok: false, reason }
//     rank(number, which, level, id)  ->  a promise of { ok } or { ok: false, reason }: which is
//                                         "importance" or "blocks" (HIS LITTLE BUTTONS)
//     sayPart(number, letter, text, wording, id)   the same, for the answer to ONE PART of a question
//                                         of parts; a host that has none is handed the part through
//                                         say, as the words "(b) ..." (see A QUESTION OF SEVERAL PARTS)
//     storage                             where drafts are kept (default: this page's own localStorage)
//     prefs                               where the chosen order is kept (default: the same; a host
//                                         that keeps drafts in memory only still keeps the order)
//     expanded                            false: every question opens folded (the window); left out,
//                                         unfolded (header, EVERY QUESTION STARTS UNFOLDED)
//     answered                            true: the answered are shown until he chooses (the window);
//                                         left out, hidden (header, THE ANSWERED ARE HIDDEN UNTIL ASKED FOR)
//   doc.setKinds(record)     the answer of the kinds operation, as { state, value, reason }
//   doc.setList(record)      the answer of the list operation; says what it did: "drawn", "same"
//                            (the very answer already drawn: nothing is touched) or "unread" (the
//                            answer is not a list: what was drawn stays, and the caller says why)
//   doc.setDim(fnOrNull)     fn(question) is true for a question to draw dimmed. DIMMED, NEVER HIDDEN
//   doc.setParked(names)     the groups kept folded at the foot of the page, out of the run of answering
//   doc.setUnfolded(numbers) these questions' context unfolded as well; doc.unfoldAll(); doc.foldAll()
//   doc.reveal(number)       that question brought into view, if it is not wholly in it already
//   doc.takeKeyboard()       the caret into the first unanswered question's field
//   doc.order(), doc.setOrder(key)   the order chosen (date, importance or blocks), and choosing one
//   doc.expanded(), doc.setExpanded(open)   every question unfolded or folded, as the one button does
//   doc.lanes(), doc.lane(), doc.setLane(lane)   the cards' numbers, the lane chosen, choosing one
//                                         (header, ONE LANE AT A TIME)
//   doc.drive(steps)         a check's steps acted out on the page's own fields (see drive below)
//   doc.counts()             { open, waiting, other }
//   doc.snapshot(limits)     WHAT IS DRAWN, read back from the page's own elements; see snapshot below
//   doc.measure()            the computed letter size and line height of a question line, in CSS pixels
//
// THE QUESTION IS NEVER CUT. It wraps to as many lines as it needs, and everything else gives way to
// it: the answer's field stands to its right only when the whole question fits on one line with room
// to spare, and under it otherwise.
//
// THE KEYS, in a field (the owner's own list, 2026-10-07):
//   Enter                 save what is typed and go to the next question; on an empty field, just go
//   Tab                   an empty field that shows a grey suggestion: take it as editable text and
//                         stay; a field holding one character: move on and send nothing; any other
//                         field: as Enter. Shift+Tab: back one
//   Right arrow           in an empty field: take the suggestion, as Tab does
//   Ctrl+Enter            in an empty field: the suggestion IS the answer; save it and go on
//   Shift+Enter, Ctrl+J   a new line inside the answer
//   F2, Ctrl+Space        the question's context, unfolded and folded in place; the caret stays
//
// THE ORDER IS HIS (the founder, 2026-10-12): the questions he has still to answer stand NEWEST FIRST,
// and a small line at the head of the page lets him order them instead by how important the task is,
// or by how much the question blocks it - the two words the keeper states when it asks
// (decisions/Rules.ps1, HOW MUCH A QUESTION MATTERS); ties go to the newest. ONE FUNCTION SORTS
// (compareBy), for the window and for the phone alike, because this file is both. What he chose is
// remembered on this device. A question's group is still its heading: questions that stand together
// in the order and share a group share one heading, so a group may be named more than once down the
// page, and the order is never bent to keep a group in one piece.
// THE ORDER TURNS OVER (the founder, 2026-10-14: "Decisions page sorts should toggle between ascending
// and descending"): the order in force, pressed again, turns over - the oldest first, the least
// important first, the least blocking first - and pressed again turns back; another order is chosen
// in its own first direction. Only the order's own word turns: ties still go to the newest. The order
// in force shows an arrow (down: its first direction, up: turned over) and says it in words; which
// way it runs is remembered beside which order it is.
// A PRESS RE-SORTS WHAT HE IS LOOKING AT (the founder, 2026-10-14: "the three sort orders sometimes
// don't work"). A redraw keeps the question at the top of the view where it was (THE VIEW FOLLOWS
// HIM), which is right for a list that arrives and wrong for a press: in a real browser a tap on
// "Task importance" re-sorted the list and then scrolled 879 px down the page after the question that
// had been at the top, so the screen showed the same question and the order line was gone - it
// "worked" only when the list was too short to scroll (decisions/page/test/browser-order.mjs). A
// press keeps the order line where it was pressed instead, so the head of the new order is under it.
//
// ONCE HE HAS ANSWERED, THE QUESTION LEAVES HIS LIST (the same day: "once he answers a question it
// goes away from his list"). The words turn green when the host says they are saved; a moment later
// the question folds to one line that says Answered; and when a list arrives that holds the answer it
// moves to the folded With Thrall, below. It never comes back by itself: the keeper asks what is
// left as a NEW question, which shows the old one and his answer folded under it ("Follows up on
// question N"). An answer that was NOT saved never turns green: the field keeps the words and the
// reason stands under them.
//
// NOTHING TYPED IS LOST. Whatever stands in a field and is not the saved answer is a draft, kept by
// the question's number in the page's own storage on every keystroke: it survives a redraw, a new
// list and the window being closed and opened again. A draft is dropped only when the host has
// answered that those very words are saved.
//
// SAVING DOES NOT HOLD THE READER UP. Enter moves the caret on at once and the words are sent; the
// field says "saving" until the host answers. If the host refuses, the field keeps the words, shows
// the refusal's sentence under them, and the caret is brought back to it - unless the reader has
// already typed something in the field they went on to, which is never interrupted.
// The same words sent twice carry the same id, so they are one message. A second Enter that lands on
// the empty field the caret has only just arrived in is ignored (ARRIVAL_MS): a doubled key press
// must not skip a question unseen.
//
// A QUESTION IS NEVER LOST TO ITS GROUP'S NAME. Groups are kept in a map with no prototype: a group a
// session named "__proto__" or "constructor" is a key like any other (measured 2026-10-06 in a real
// window by the review of the earlier page). The same holds for every map here keyed by text or number.
//
// ROOM IS KEPT FOR THE QUESTIONS STILL TO ANSWER (seen 2026-10-07 in pictures of the real list: one
// question's conversation filled the whole first view of the narrow window, and one saved answer
// took eight lines). What was said before is one line each, cut with an ellipsis, EXCEPT the one thing
// the reader has to answer - the last thing said, when somebody else said it - which is whole. A
// saved answer the caret is not in rests at two lines, and says how many more it has; the caret in
// it, it is whole. Unfolding the question's context (the triangle, F2, or a press on a cut line)
// shows every message whole. THE QUESTION ITSELF IS NEVER CUT, and neither is a draft.
//
// EVERY QUESTION STARTS UNFOLDED (the founder, 2026-10-14: "I also want a collapse all button on the
// questions even though they should start expanded"): each question of his list opens with its
// context under it, and one button, on a short line just under the order line, folds them all
// ("Collapse all"), then says "Expand all" and unfolds them all again. A press drops what he chose for single questions
// and touches neither the order nor his place on the page (THE VIEW FOLLOWS HIM). What he folds or
// unfolds is kept, question by question, through every list that arrives; a question that arrives
// later opens as the button last left them. Rows that are only read (With Thrall, History) stay one
// line each until he unfolds one. A host may open folded instead (expanded: false - the window).
//
// ONE STAGE, AND A BOX TO ANSWER IN (the founder, 2026-10-15: "Clicking on a decision to get more info
// now seems to have two stages of info showing - either make it one stage or make it more evident to
// the user. Also, the input box for where to type the decision answer needs to be more clearly
// delineated"). Unfolded, a question's details are one run, in reading order: what stands out about
// it, what was said (whole), its context - parts, options, what it is, the recommendation, files and
// references - and LAST the label "Your answer" over the box. Before, the context was drawn under the
// field, so an unfolded question showed details, the field, then more details: two showings. One tap
// on a folded question shows the whole run at once. Folded, the details give way (the context goes,
// what was said before is one line each) but the box stays: the window's run of answering is the box
// of every question, with nothing unfolded to reach it (test/e2e/e2e-decisions-answering.ps1), and F2
// folds the context with the caret still in the box. The box has an edge drawn as a shadow inside it
// (never a border, for the sharp letters of list.css), a clear ring while the caret is in it, a least
// height of two lines (three on a phone) that grows with the words up to twelve, and its Send key
// attached at its foot, which does what Enter does there.
//
// THE ANSWERED ARE HIDDEN UNTIL ASKED FOR (the founder, 2026-10-15: "By default you need to not show
// questions that are answered - should be toggleable on top across from the sort by"). The folds of
// the answered - With Thrall (answered, the keeper's turn) and History (closed) - are not drawn until
// a switch at the head of the page, "Show answered and closed: off", is pressed; then they stand as
// they always have, and the switch says on. A keyboard reaches it as it reaches the folds, never by
// Tab: Ctrl+Down from a field when no fold is drawn, or Up from the first fold (THE SWITCH IS
// REACHED BY KEYS); Space or Enter turns it. It stands at the head of the line under the order line, across from
// Collapse all: on the order line itself a phone's 412 px wrapped it to two lines and a tap on an order
// missed (measured for Collapse all, EVERY QUESTION STARTS UNFOLDED). What he chose is kept on this
// device beside the order; a press touches neither the order, nor what is folded, nor his place. A
// question he answers still goes green and folds to Answered where it stands, then leaves for the
// hidden fold, and the view keeps the question at its top where it was (THE VIEW FOLLOWS HIM). A host
// may show them until he chooses (answered: true - the window, whose scenarios read With Thrall).
//
// ONE LANE AT A TIME (the founder's decision 74, 2026-10-14: cards first, one per lane with its open
// questions and a mark when one of them blocks all its work, and one for all the questions; a tap on
// a card shows that lane's questions). The cards are the host's to draw - the phone draws the same
// card its Progress tab does (surfaces/pwa/page/decision-cards.js) - from what this page counts
// (doc.lanes(): a lane is read from who asked, laneOf). A lane chosen shows only its questions, in the
// list and in every fold, in the order chosen; it is kept on this device beside the order, and a list
// that arrives keeps it.
//
// CHANGE MY ANSWER (T-0152; the founder, Q67, 2026-10-15: "On a phone it is easy to tap the wrong option"). An
// answered question that is not closed shows, in its row under With Thrall, a button: "Change my answer". A
// tap brings the question back into the list with its answer box open, his current answer in it and
// selected; "Keep my answer" puts it back as it was. What he sends is the ordinary save - the same signed
// answer through the same host, the newest standing - so a question that needs a passkey asks for one again,
// and the host's refusal stands under the box as for any answer. WHAT BECAME OF A CHANGE is drawn from the
// question's answerChanges (decisions/Rules.ps1), always in plain words and never silent:
//   no reply yet   "answer changed - waiting for Orc X to confirm"
//   a reply        "You changed your answer at 14:02. Orc X had not acted yet and is using the new answer."
//                  "... had already acted on the first one and is undoing it."
//                  "... had already acted on the first one and says it cannot undo: <why>."
// A question that is CLOSED has no button: "This question is closed - Orc X has acted on it. To change
// course, ask a follow-up." (the view's actedBy names who).
//
// A REDRAW KEEPS THE READER'S PLACE: what is unfolded stays unfolded, the line at the top of the view
// stays where it is, and the caret stays in its field at its place in the words.
//
// HIS LITTLE BUTTONS (the founder, 2026-10-14): beside each question still on his list, an Importance and
// a Blocking button saying its two words; a press opens the three levels, and picking one hands it to
// the host (options.rank). The list re-sorts when a list holding the new level arrives (drawRank).
//
// WHAT BECAME OF AN ANSWER, WHEN THE HOST KNOWS (the phone, 2026-10-14). A message may carry receipt:
// the host's own words for what became of it ("sent", "received by PC", "applied"), and receiptNote: a
// line to show under it (a warning that it waits too long, or a refusal). The mark beside a standing
// answer says the receipt in place of "saved", and the word a question folds to says it too while the
// answer is on its way ("Answered, sent"). A host that sends no receipt changes nothing here.
//
// EVERY TEXT IS SET AS TEXT (textContent, or a field's value). A question or a message may quote
// anything a session wrote, and none of it is ever read as markup. A message is drawn isolated from
// the line around it (dir auto), so that direction marks in it cannot reorder anything else.
(function () {
  "use strict";

  // The one state the document lists under its groups; a question in any other state is listed after
  // them, under a heading that is the state's own name, folded until the reader unfolds it.
  var LISTED_STATE = "open";
  // The label of decisions/Rules.ps1 for the one who types here.
  var MINE = "founder";
  // THE PAGE'S WORDS FOR THE ONE WHO KEEPS THE LIST, AND FOR WHAT BECAME OF AN ANSWER. In one place.
  var KEEPER = "Thrall";
  // Each mark has a short form, drawn where there is no room beside the field (list.css).
  var WORDS = {
    you: "You", keeper: KEEPER, saving: "saving", saved: "saved", told: "told " + KEEPER, read: "read by " + KEEPER, draft: "draft",
    toldShort: "told", readShort: "read", edited: "edited", earlier: "You, earlier", isNew: "new", answered: "Answered",
    afterClosing: "the question is closed; kept, and it reopens nothing", earlierWording: "said to an earlier wording",
    marks: "this message holds direction or invisible characters",
    change: "Change my answer", keep: "Keep my answer"
  };
  // The receipt that says an answer has arrived for good: folded, it is just Answered.
  var RECEIPT_DONE = "applied";
  var DRAFTS_KEY = "horde-decisions-drafts-v1";
  // THE ORDERS HE CAN CHOOSE (header, THE ORDER IS HIS): key, the word on its button, and what the
  // button says to a screen reader, in its first direction and turned over (THE ORDER TURNS OVER).
  // The first is the one he gets until he chooses. Which way it runs is kept under a key of its own,
  // so a page of an earlier version still reads the order it knows from ORDER_KEY.
  var ORDER_KEY = "horde-decisions-order-v1";
  var ORDER_TURN_KEY = "horde-decisions-order-turned-v1";
  var ORDERS = [
    { key: "date", label: "Date", says: "the newest question first", turned: "the oldest question first", what: "date" },
    { key: "importance", label: "Task importance", says: "the most important first", turned: "the least important first", what: "how important the task is" },
    { key: "blocks", label: "Blocking", says: "the most blocking first", turned: "the least blocking first", what: "how much the question blocks its task" }
  ];
  // The arrow beside the order in force: down in its first direction, up turned over. Escapes, so the
  // source stays ASCII.
  // THE ONE BUTTON THAT FOLDS OR UNFOLDS EVERY QUESTION (header, EVERY QUESTION STARTS UNFOLDED): its
  // word for what a press does, and what it says to a screen reader.
  var FOLD_WORDS = {
    collapse: "Collapse all", collapseSays: "Fold the context of every question",
    expand: "Expand all", expandSays: "Unfold the context of every question"
  };
  var ARROW_FIRST = "\u25BC";
  var ARROW_TURNED = "\u25B2";
  var DEFAULT_ORDER = "date";
  // THE TWO WORDS BESIDE A QUESTION, each list in the order it sorts in, and the word a question
  // reads as when it states none - or states one this page does not know. They are
  // decisions/Rules.ps1's lists, written again here because a page cannot ask the rules;
  // test/test-decisions-rules.ps1 holds these four lines to them, word for word.
  var IMPORTANCES = ["high", "normal", "low"];
  var BLOCKINGS = ["all", "part", "none"];
  var DEFAULT_IMPORTANCE = "normal";
  var DEFAULT_BLOCKS = "part";
  // AFTER A SAVE (header, ONCE HE HAS ANSWERED): how long the saved words stand green before the
  // question folds to "Answered", and how long from the save the folded line is kept in the list
  // even when the list that holds the answer has already arrived - so that what he did is seen to
  // have happened, and does not vanish under his eyes.
  var GREEN_MS = 1500;
  var LINGER_MS = 4000;
  // How long after the caret arrives in an empty field an Enter is taken for the tail of a doubled
  // key press. Longer than a key bounce or an accidental double tap; shorter than reading a question.
  var ARRIVAL_MS = 350;
  // AFTER A SAVE, LONGER (the owner, 2026-10-07: he sent one answer twice, a minute apart, because
  // the first Enter showed him nothing). An Enter that saved moves the caret on and the field it left
  // says "saving" at once; an Enter repeated within this long, on the empty field the save moved him
  // to, is the same press made again for want of a sign, and does nothing.
  var SAVE_ECHO_MS = 3000;
  // How many lines a saved answer rests at while the caret is not in it (header, ROOM IS KEPT).
  var REST_LINES = 2;
  // THE ANSWER BOX'S WORDS (header, ONE STAGE, AND A BOX TO ANSWER IN): the label above it, the label
  // above a question of parts, and its key.
  var BOX_WORDS = { label: "Your answer", parts: "Your answers, one for each part", send: "Send" };
  // Each page mounted takes its own prefix for the ids that tie a label to its field: the phone mounts
  // one page per horde, and two of them must never hold the same id.
  var mounts = 0;
  // The sub-lines of an unfolded question, in order: the field, the label before it ("" for none),
  // and how a list is shown - "each" a line per item, "joined" one line.
  var SUB_LINES = [
    { field: "parts", label: "", list: "each" },
    { field: "options", label: "Option", list: "each" },
    { field: "whatItIs", label: "What it is" },
    { field: "yesMeans", label: "Yes means" },
    { field: "recommendation", label: "Recommended" },
    { field: "waiting", label: "Waiting", list: "joined" },
    { field: "askedBy", label: "Asked by" },
    { field: "files", label: "Files", list: "joined" },
    { field: "references", label: "References", list: "joined" },
    { field: "outcome", label: "Outcome" },
    { field: "reopenReason", label: "Reopened because" }
  ];

  function make(tag, className, text) {
    var node = document.createElement(tag);
    if (className) { node.className = className; }
    if (text !== undefined && text !== null) { node.textContent = String(text); }
    return node;
  }
  function textOf(value) { return (value === null || value === undefined) ? "" : String(value); }
  function listOf(value) { return Array.isArray(value) ? value : []; }
  function capital(word) { return word ? word.charAt(0).toUpperCase() + word.slice(1) : word; }
  // WHERE A WORD STANDS IN ITS LIST; a word the list does not hold stands where the default does.
  function placeIn(words, word, fallback) {
    var at = words.indexOf(textOf(word));
    return at >= 0 ? at : words.indexOf(fallback);
  }
  // When a question was asked, as a number; 0 when the list does not say (then its number decides).
  function askedAt(q) {
    var t = Date.parse(textOf(q.addedAt));
    return isNaN(t) ? 0 : t;
  }
  // NEWEST FIRST: by when it was asked, and between two asked in the same instant - or with no time
  // stated - the higher number, which was asked later. It is also how every other order breaks a tie.
  // A number that is not a number counts as 0, so a comparison never answers NaN - an answer that
  // leaves the sort's result to the engine.
  function numberOf(q) { var n = Number(q.number); return isNaN(n) ? 0 : n; }
  function newestFirst(a, b) { return (askedAt(b) - askedAt(a)) || (numberOf(b) - numberOf(a)); }
  function orderOf(key) {
    for (var i = 0; i < ORDERS.length; i += 1) { if (ORDERS[i].key === key) { return key; } }
    return DEFAULT_ORDER;
  }
  // THE ONE COMPARISON of two questions for an order (header, THE ORDER IS HIS), turned over when
  // turned is true (header, THE ORDER TURNS OVER): only the order's own word turns, and a tie still
  // goes to the newest - except by date, where the newest IS the order, so the whole of it turns.
  function compareBy(key, turned) {
    var way = turned === true ? -1 : 1;
    if (key === "importance") { return function (a, b) { return way * (placeIn(IMPORTANCES, a.importance, DEFAULT_IMPORTANCE) - placeIn(IMPORTANCES, b.importance, DEFAULT_IMPORTANCE)) || newestFirst(a, b); }; }
    if (key === "blocks") { return function (a, b) { return way * (placeIn(BLOCKINGS, a.blocks, DEFAULT_BLOCKS) - placeIn(BLOCKINGS, b.blocks, DEFAULT_BLOCKS)) || newestFirst(a, b); }; }
    return function (a, b) { return way * newestFirst(a, b); };
  }
  // A list of questions in an order: a new list, the one handed in is not touched.
  function inOrder(list, key, turned) { return listOf(list).slice().sort(compareBy(orderOf(key), turned === true)); }
  function newId() {
    var bytes = new Uint8Array(16);
    window.crypto.getRandomValues(bytes);
    var out = "";
    for (var i = 0; i < bytes.length; i += 1) { out += (bytes[i] < 16 ? "0" : "") + bytes[i].toString(16); }
    return out;
  }

  // A QUESTION OF SEVERAL PARTS IS ANSWERED PART BY PART (the owner's question 28, 2026-10-07: five
  // parts, (a) to (e), and his stored answer was the one letter "a" - he began "a ..." and a key saved
  // it). Each part gets a small field of its own, labelled with its letter and its words; Enter and
  // Tab go from part to part. EACH PART IS SENT BY ITSELF, the moment he leaves it (the founder,
  // 2026-10-12: "answering one part sends that part at once; do not wait for all parts"): its words
  // turn green when they are saved and the part folds to one line that says Answered, while the parts
  // still to answer stay open; the question leaves his list when every part is answered. The host is
  // handed the part's letter with the words (sayPart); the store keeps each as a record of its own
  // (decisions/Rules.ps1, A QUESTION OF PARTS), so the keeper is told which part was answered. A host
  // that cannot say a part is handed the words as "(b) ...", which every earlier version reads back
  // into the part's field. The store keeps
  // parts as the question's list "parts" (decisions/Rules.ps1), each written by the keeper as
  // "(a) words" (seen in the real list that day: questions 6 and 28 to 31); a part that does not begin
  // so is given the next letter. ONE RECOMMENDATION FOR ALL PARTS, written "(a) approve; (b) approve;
  // ..." as the keeper writes it, gives each part its own grey suggestion; written any other way it is
  // shown once, above the fields.
  var PART_MARK = /^\s*\(([a-z])\)\s*/;
  function partsOf(q) {
    var list = Array.isArray(q.parts) ? q.parts : [];
    if (textOf(q.kind) !== "parts" || list.length < 2) { return null; }
    var out = [];
    for (var i = 0; i < list.length; i += 1) {
      var words = textOf(list[i]);
      var mark = PART_MARK.exec(words);
      // An unmarked part takes the letter of its place; there are twenty-six, and a part beyond
      // them has none, so the parts cannot all be told apart (decisions/Rules.ps1 reads them so too).
      var letter = mark ? mark[1] : (i < 26 ? String.fromCharCode(97 + i) : "");
      if (!letter) { return null; }
      out.push({ letter: letter, words: mark ? words.slice(mark[0].length) : words, rec: "" });
    }
    // Each letter once, or they are not parts that can be told apart: then one field, as before.
    var seen = Object.create(null);
    for (var j = 0; j < out.length; j += 1) { if (seen[out[j].letter]) { return null; } seen[out[j].letter] = true; }
    var rec = textOf(q.recommendation);
    var each = splitByParts(rec, out);
    if (each) { for (var k = 0; k < out.length; k += 1) { out[k].rec = each[k]; } }
    return { parts: out, recOnce: each ? "" : rec };
  }
  // A text written "(a) ...; (b) ..." cut at each part's letter, in the parts' order: the words of
  // each, or null when the text does not name every part, in order, at the start of a line or after a
  // separator. Used for the recommendation and for a saved answer alike.
  function splitByParts(text, parts) {
    if (!text) { return null; }
    var at = [];
    var from = 0;
    for (var i = 0; i < parts.length; i += 1) {
      var re = new RegExp("(^|[\\s;,.])\\(" + parts[i].letter + "\\)\\s*", "g");
      re.lastIndex = from;
      var hit = re.exec(text);
      if (!hit || (i === 0 && text.slice(0, hit.index + hit[1].length).trim() !== "")) { return null; }
      at.push({ start: hit.index + hit[1].length, body: hit.index + hit[0].length });
      from = hit.index + hit[0].length;
    }
    var out = [];
    for (var j = 0; j < at.length; j += 1) {
      var end = j + 1 < at.length ? at[j + 1].start : text.length;
      out.push(text.slice(at[j].body, end).replace(/[\s;,]+$/, "").replace(/\s+$/, ""));
    }
    return out;
  }
  // A message the parts made (joinParts), read back into the parts' fields: the words of each, "" for
  // a part it leaves out; or null when it is not such a message (an answer given before the parts had
  // fields, or by chat, is shown as what was said, never pulled apart by guesswork).
  function readParts(text, parts) {
    if (!text) { return null; }
    var values = parts.map(function () { return null; });
    var current = -1;
    var lines = text.split("\n");
    for (var i = 0; i < lines.length; i += 1) {
      var mark = /^\(([a-z])\) ?/.exec(lines[i]);
      var index = -1;
      if (mark) { for (var j = current + 1; j < parts.length; j += 1) { if (parts[j].letter === mark[1]) { index = j; break; } } }
      if (index >= 0) { current = index; values[index] = lines[i].slice(mark[0].length); }
      else if (current >= 0) { values[current] += "\n" + lines[i]; }
      else { return null; }
    }
    return values.map(function (v) { return v === null ? "" : v; });
  }
  // The one message the parts make: a line per answered part, "(a) words". A part left empty is left
  // out; nothing answered is no message.
  function joinParts(parts, values) {
    var lines = [];
    for (var i = 0; i < parts.length; i += 1) { if (textOf(values[i]).trim() !== "") { lines.push("(" + parts[i].letter + ") " + values[i]); } }
    return lines.join("\n");
  }

  // THE LETTER BEFORE THE NUMBER: who asked. "Orc D" is D; a name that begins with one capital
  // letter standing alone ("M (...)") is that letter; anybody else is the keeper of the list, M.
  function letterOf(askedBy) {
    var name = textOf(askedBy);
    var orc = /^Orc ([A-Z])(?![A-Za-z])/.exec(name);
    if (orc) { return orc[1]; }
    var alone = /^([A-Z])(?![A-Za-z])/.exec(name);
    return alone ? alone[1] : "M";
  }

  // THE LANE A QUESTION IS OF (the founder's decision 74, 2026-10-14: on the decisions page, cards
  // first - one per lane with its open questions, and one for all of them). A question names no lane
  // of its own (schema/decision-question.v1 has no such field; the live list's askedBy reads "Orc C",
  // "M (Thrall)", "Thrall"), so its lane is read from who asked, as its letter is (letterOf): an Orc's
  // lane as its lane file names it ("C", "F1"), and the keeper's - and anybody's the list cannot tell,
  // which letterOf gives M too - the Thrall's, "thrall" (surfaces/pwa/page/lane-card.js, THRALL_LANE).
  var KEEPER_LANE = "thrall";
  var LANE_WORD = /^(thrall|[A-Z][0-9]{0,3})$/;
  var LANE_KEY = "horde-decisions-lane-v1";
  // THE ANSWERED ARE HIDDEN UNTIL ASKED FOR: where the choice is kept ("1" shown, "0" hidden), the folds
  // it hides - With Thrall (answered, the keeper's turn) and History (closed) - and the switch's words.
  // The words name both: History also holds questions closed without his answer (review of PR 311).
  var ANSWERED_KEY = "horde-decisions-answered-shown-v1";
  var ANSWERED_FOLDS = { thrall: true, history: true };
  var ANSWERED_WORDS = { on: "Show answered and closed: on", off: "Show answered and closed: off",
    onSays: "Answered and closed questions are shown, under With Thrall and History. Press to hide them",
    offSays: "Answered and closed questions are hidden. Press to show them, under With Thrall and History" };
  function laneWord(word) { word = textOf(word); return LANE_WORD.test(word) ? word : ""; }
  function laneOf(q) {
    var name = textOf(q && q.askedBy);
    var orc = /^Orc ([A-Z][0-9]{0,3})(?![A-Za-z0-9])/.exec(name);
    if (orc) { return orc[1]; }
    var letter = letterOf(name);
    return letter === "M" ? KEEPER_LANE : letter;
  }
  // THE NUMBERS ON THE CARDS: for each lane that has a question he has still to answer (toAnswer(q)),
  // how many, and whether any of them blocks ALL of its task's work (the keeper's word "all",
  // decisions/Rules.ps1, HOW MUCH A QUESTION MATTERS). The Thrall's lane first, then the lanes by
  // name, as the Progress tab lists its cards. A new list each time; the questions are not touched.
  function lanesOf(list, toAnswer) {
    var by = Object.create(null);
    var out = [];
    listOf(list).forEach(function (q) {
      if (!q || !toAnswer(q)) { return; }
      var lane = laneOf(q);
      if (!by[lane]) { by[lane] = { lane: lane, open: 0, blocksAll: false }; out.push(by[lane]); }
      by[lane].open += 1;
      if (textOf(q.blocks) === BLOCKINGS[0]) { by[lane].blocksAll = true; }
    });
    return out.sort(function (a, b) {
      if (a.lane === b.lane) { return 0; }
      if (a.lane === KEEPER_LANE || b.lane === KEEPER_LANE) { return a.lane === KEEPER_LANE ? -1 : 1; }
      return a.lane < b.lane ? -1 : 1;
    });
  }

  function mount(root, options) {
    options = options || {};
    mounts += 1;
    var idPrefix = "hd" + mounts + "-";
    // Where the view begins: below whatever the host keeps fixed at the top, which only the host knows.
    var topInset = (typeof options.topInset === "function") ? options.topInset : function () { return 0; };
    var onDraw = (typeof options.onDraw === "function") ? options.onDraw : function () {};
    var onChange = (typeof options.onChange === "function") ? options.onChange : function () {};
    var say = (typeof options.say === "function") ? options.say : function () { return Promise.resolve({ ok: false, reason: "Not saved: this page has nobody to hand the words to." }); };
    // act(number, "park" or "unpark", wording, id): his act, recorded; answered as say is.
    var act = (typeof options.act === "function") ? options.act : function () { return Promise.resolve({ ok: false, reason: "this page has nobody to record it with." }); };
    // sayPart(number, letter, text, wording, id): his answer to one part. A host that has no such
    // request is handed the words through say with the part's letter before them, "(b) ...": one
    // message a part, which a store of any version keeps and an earlier page reads into the part.
    var sayPart = (typeof options.sayPart === "function") ? options.sayPart : function (number, letter, text, wording, id) { return say(number, "(" + letter + ") " + text, wording, id); };
    // rank(number, "importance" or "blocks", level, id): his little button (HIS LITTLE BUTTONS, at drawRank);
    // a promise of { ok } or { ok: false, reason }, as say.
    var rank = (typeof options.rank === "function") ? options.rank : function () { return Promise.resolve({ ok: false, reason: "this page has nobody to change it with." }); };
    var storage = options.storage || null;
    if (!storage) { try { storage = window.localStorage; } catch (e) { storage = null; } }
    // WHERE THE CHOSEN ORDER IS KEPT: its own place, because a host may keep drafts in memory only (the
    // phone: what he typed is never written to the phone's disk) and the order is not his words.
    // Asked for with care: a page with no storage, or one that refuses, keeps the order for as long
    // as it is open and says nothing.
    var prefs = options.prefs || null;
    if (!prefs) { try { prefs = window.localStorage; } catch (e) { prefs = null; } }
    var orderKey = DEFAULT_ORDER;
    var orderTurned = false;
    try { orderKey = orderOf(prefs ? prefs.getItem(ORDER_KEY) : ""); } catch (e) { orderKey = DEFAULT_ORDER; }
    try { orderTurned = !!prefs && prefs.getItem(ORDER_TURN_KEY) === "1"; } catch (e) { orderTurned = false; }
    // THE LANE HE CHOSE ON THE CARDS ("" for all of them), kept on this device beside the order, so a
    // list that arrives - or the page opened again - shows the lane he was reading. A word that is no
    // lane is all of them.
    var laneChosen = "";
    try { laneChosen = laneWord(prefs ? prefs.getItem(LANE_KEY) : ""); } catch (e) { laneChosen = ""; }
    // WHETHER THE ANSWERED ARE SHOWN (header, THE ANSWERED ARE HIDDEN UNTIL ASKED FOR): his choice on
    // this device first, kept beside the order; with none, the host's (answered: true - the window),
    // else hidden.
    var answeredShown = options.answered === true;
    try { var answeredKept = prefs ? prefs.getItem(ANSWERED_KEY) : null; if (answeredKept === "1" || answeredKept === "0") { answeredShown = answeredKept === "1"; } } catch (e) { /* the host's default stands */ }
    var kinds = Object.create(null);
    var questions = [];
    var lastJson = null;
    var dim = null;
    // Keyed by a question's number and by a heading's key: maps with no prototype (header).
    // unfolded: what he chose for ONE question, true (unfolded) or false (folded); a question he has
    // not chosen for follows openFirst (header, EVERY QUESTION STARTS UNFOLDED).
    var unfolded = Object.create(null);
    var openFirst = options.expanded !== false;
    // Is this question's context unfolded? His own choice for it first; else, for a question of his
    // list, the page's (openFirst); a row that is only read (With Thrall, History) stays one line
    // until he unfolds it, or Unfold all does.
    function isOpen(q, readOnly) {
      var mine = unfolded[q.number];
      if (mine === true || mine === false) { return mine; }
      return readOnly ? false : openFirst;
    }
    var headFolded = Object.create(null);
    // Which headings have their note of background shown. FOLDED UNTIL ASKED FOR (seen 2026-10-07 in
    // a picture of the real window: two notes took 13 of the 26 lines in view).
    var noteShown = Object.create(null);
    // PARKED: the groups whose questions stand at the foot of the page under one folded line. Folded,
    // their fields are not in the run of Enter and Tab, nor is one of them "the first unanswered".
    var parked = Object.create(null);
    var drawnHeads = [];
    var drawnLines = [];
    // What the reader has typed that is not saved, by question number; and, by question number, what
    // became of what was sent: { sentText, sentId, pending, refusal, saved: { text, sequence, ... } }.
    var drafts = Object.create(null);
    var sent = Object.create(null);
    var storageProblem = "";
    var arrived = { number: null, at: 0 };

    try {
      var kept = storage ? JSON.parse(storage.getItem(DRAFTS_KEY) || "{}") : {};
      Object.keys(kept || {}).forEach(function (k) { if (/^[0-9]{1,9}$/.test(k) && typeof kept[k] === "string") { drafts[k] = kept[k]; } });
    } catch (e) { storageProblem = "Drafts kept before could not be read back."; }
    function keepDrafts() {
      try { if (storage) { storage.setItem(DRAFTS_KEY, JSON.stringify(drafts)); storageProblem = ""; } else { storageProblem = "Drafts cannot be kept here: what is typed and not saved is lost when the window closes."; } }
      catch (e) { storageProblem = "Drafts could not be kept: what is typed and not saved is lost when the window closes."; }
    }

    // What became of what was sent is kept by the question's number, and for the answer to one part
    // by its number and the part's letter, "28:b".
    function sentKey(number, letter) { return letter ? (number + ":" + letter) : String(number); }
    function sentOf(key) {
      if (!sent[key]) { sent[key] = { sentText: null, sentId: null, pending: 0, refusal: "", saved: null }; }
      return sent[key];
    }
    // AFTER A SAVE (GREEN_MS and LINGER_MS, above): until when a saved answer stands green, by the
    // same key, and until when its question is kept in the list, by the question's number.
    var greenUntil = Object.create(null);
    var lingerUntil = Object.create(null);
    function isGreen(key) { return greenUntil[key] !== undefined && Date.now() < greenUntil[key]; }
    // Is something of this question still on its way to the host, or only just saved?
    function lingers(q) {
      if (lingerUntil[q.number] !== undefined && Date.now() < lingerUntil[q.number]) { return true; }
      var s = sent[q.number];
      if (s && s.pending > 0) { return true; }
      var info = partsOf(q);
      return !!info && info.parts.some(function (p) { var sp = sent[sentKey(q.number, p.letter)]; return !!sp && sp.pending > 0; });
    }
    function allMessagesOf(q) { return (q.thread && Array.isArray(q.thread.messages)) ? q.thread.messages : []; }
    // WHAT WAS SAID, his acts left out (park and unpark are records of what he did, not words; the
    // operation say keeps them so that the keeper sees them - decisions/Rules.ps1).
    function messagesOf(q) { return allMessagesOf(q).filter(function (m) { return !textOf(m.act); }); }
    // His last act under the question: "park", "unpark" or "" - and what he did here since, not yet in
    // a list (acted, below).
    var acted = Object.create(null);
    // CHANGE MY ANSWER: the questions he has asked to change, by number. Such a question stands in his list
    // with its answer box open until what he sends is saved, or he keeps his answer.
    var reopened = Object.create(null);
    function lastActOf(q) {
      var all = allMessagesOf(q);
      var mine = acted[q.number];
      // What he did here and the list does not hold yet (its record is not in it, or not yet known).
      if (mine && !all.some(function (m) { return Number(m.sequence) >= mine.sequence; })) { return mine.act; }
      for (var i = all.length - 1; i >= 0; i -= 1) { if (textOf(all[i].act)) { return textOf(all[i].act); } }
      return "";
    }
    // THE ANSWER THAT STANDS, to the question as a whole: the reader's own message when it is the
    // last thing said under the question - his answers to single parts, said after it, left aside -
    // or what the host has just answered is saved, until a list arrives that holds it.
    function standingOf(q) {
      var msgs = messagesOf(q);
      var s = sent[q.number];
      if (s && s.saved) {
        var caught = allMessagesOf(q).some(function (m) { return Number(m.sequence) >= s.saved.sequence; });
        if (caught) { s.saved = null; } else { return s.saved; }
      }
      for (var i = msgs.length - 1; i >= 0; i -= 1) {
        if (msgs[i].speaker !== MINE) { return null; }
        if (!textOf(msgs[i].part)) { return msgs[i]; }
      }
      return null;
    }
    // THE ANSWER THAT STANDS TO ONE PART: what the host has just answered is saved for it, until a
    // list arrives that holds it; else his last message that names the part.
    function partSavedOf(q, letter) {
      var s = sent[sentKey(q.number, letter)];
      if (s && s.saved) {
        var caught = allMessagesOf(q).some(function (m) { return m.speaker === MINE && !textOf(m.act) && Number(m.sequence) >= s.saved.sequence && (textOf(m.part) === letter || !textOf(m.part)); });
        if (caught) { s.saved = null; } else { return s.saved; }
      }
      var msgs = messagesOf(q);
      for (var i = msgs.length - 1; i >= 0; i -= 1) { if (msgs[i].speaker === MINE && textOf(msgs[i].part) === letter) { return msgs[i]; } }
      return null;
    }
    // HAS HE ANSWERED IT? { answered, local }: answered when an answer to the whole question stands,
    // or every one of its parts has one; local when any of that is known only from this page - saved,
    // and not yet in a list.
    function stateOf(q) {
      var standing = standingOf(q);
      if (standing) { return { answered: true, local: standing.local === true }; }
      var info = partsOf(q);
      if (!info) { return { answered: false, local: false }; }
      var local = false;
      for (var i = 0; i < info.parts.length; i += 1) {
        var a = partSavedOf(q, info.parts[i].letter);
        if (!a) { return { answered: false, local: false }; }
        if (a.local === true) { local = true; }
      }
      return { answered: true, local: local };
    }
    // WHAT HE ANSWERED, as one text: his words to the whole question, and a line for each part he
    // answered after them, "(a) words", in the parts' order.
    function answerOf(q) {
      var lines = [];
      var standing = standingOf(q);
      if (standing) { lines.push(textOf(standing.text)); }
      var info = partsOf(q);
      if (info) {
        info.parts.forEach(function (p) {
          var a = partSavedOf(q, p.letter);
          if (a && (!standing || Number(a.sequence) > Number(standing.sequence))) { lines.push("(" + p.letter + ") " + textOf(a.text)); }
        });
      }
      return lines.join("\n");
    }
    // What stands above the field: everything said before the standing answer. AN ANSWER HE REPLACED
    // (an edit: his words straight after his own) stays, as one line marked "earlier", folded with the
    // question's context (the owner, 2026-10-07: the earlier one kept under a fold).
    // His answer to a part that stands is drawn in the part's own row, never above the fields too.
    function earlierOf(q) {
      var msgs = messagesOf(q);
      var standing = standingOf(q);
      var out = [];
      for (var i = 0; i < msgs.length; i += 1) {
        if (standing && msgs[i] === standing) { continue; }
        if (msgs[i].speaker === MINE && textOf(msgs[i].part) && partSavedOf(q, textOf(msgs[i].part)) === msgs[i]) { continue; }
        out.push(msgs[i]);
      }
      return out;
    }
    function replacedLater(q, m) {
      var msgs = messagesOf(q);
      var at = msgs.indexOf(m);
      if (m.speaker !== MINE) { return false; }
      // An answer to one part is replaced only by a later answer to that part.
      if (textOf(m.part)) { var now = partSavedOf(q, textOf(m.part)); return !!now && now !== m; }
      if (at >= 0 && at + 1 < msgs.length) { return msgs[at + 1].speaker === MINE; }
      var standing = standingOf(q);
      return at === msgs.length - 1 && !!standing && standing !== m;
    }
    // WHAT STANDS IN EACH PART'S FIELD when the question is drawn: what he typed there and has not
    // sent (the draft, kept as the parts' one text); else his saved answer to the part; else, for an
    // answer given to all the parts in one message - as an earlier page sent it - that part of it.
    function partValuesOf(q, info) {
      var typedIn = (drafts[q.number] !== undefined) ? readParts(drafts[q.number], info.parts) : null;
      var standing = standingOf(q);
      var whole = standing ? readParts(textOf(standing.text), info.parts) : null;
      return info.parts.map(function (p, i) {
        if (typedIn && typedIn[i] !== "") { return typedIn[i]; }
        return partBaseOf(q, info, i, whole);
      });
    }
    // What a part's field holds when nothing unsent is typed in it.
    function partBaseOf(q, info, i, whole) {
      var a = partSavedOf(q, info.parts[i].letter);
      if (a) { return textOf(a.text); }
      if (whole === undefined) { var standing = standingOf(q); whole = standing ? readParts(textOf(standing.text), info.parts) : null; }
      return whole ? whole[i] : "";
    }
    function valueOf(q) {
      if (drafts[q.number] !== undefined) { return drafts[q.number]; }
      var standing = standingOf(q);
      return standing ? textOf(standing.text) : "";
    }
    function recOf(q) { return textOf(q.recommendation); }
    // What stands in a line's field, or in its parts' fields put together as the one message they make.
    function lineValue(line) {
      if (!line.parts) { return line.field.value; }
      return joinParts(line.parts, line.fields.map(function (f) { return f.value; }));
    }
    function fieldIndex(line, field) { return line.fields.indexOf(field); }
    // What became of what stands in a field: { full, short, note } - the mark in words, its short
    // form, and what else must be said of a saved answer, which goes on a line of its own under it.
    function markOf(q, value) {
      var s = sent[q.number];
      if (s && s.pending > 0) { return { full: WORDS.saving, short: WORDS.saving, note: "" }; }
      var standing = standingOf(q);
      if (standing && value === textOf(standing.text) && textOf(standing.receipt)) {
        return { full: textOf(standing.receipt), short: textOf(standing.receipt), note: textOf(standing.receiptNote) };
      }
      if (standing && value === textOf(standing.text)) {
        var mark = { full: WORDS.saved, short: WORDS.saved, note: "" };
        if (Array.isArray(standing.unreadBy)) {
          if (standing.unreadBy.length === 0) { mark.full = WORDS.read; mark.short = WORDS.readShort; }
          else if (standing.told === true) { mark.full = WORDS.told; mark.short = WORDS.toldShort; }
        }
        // AN EDIT says so beside the mark (the owner, 2026-10-07); the answer it replaced is kept above.
        if (standing.replaces === true) { mark.full += ", " + WORDS.edited; mark.short += "*"; }
        var notes = [];
        if (standing.arrivedAfterClosing === true) { notes.push(WORDS.afterClosing); }
        if (standing.saidToEarlierWording === true) { notes.push(WORDS.earlierWording); }
        mark.note = notes.join("; ");
        return mark;
      }
      return value !== "" ? { full: WORDS.draft, short: WORDS.draft, note: "" } : { full: "", short: "", note: "" };
    }

    function kindWords(q) {
      var kind = kinds[textOf(q.kind)];
      var words = kind ? textOf(kind.label) : textOf(q.kind);
      if (q.needsSecret === true) { words += " (answering needs a login or a key, which is never written in the list)"; }
      return words;
    }

    function subLinesOf(q) {
      var out = [];
      var i, j, entry, items, value;
      for (i = 0; i < SUB_LINES.length; i += 1) {
        entry = SUB_LINES[i];
        if (entry.list === "each") {
          items = listOf(q[entry.field]);
          for (j = 0; j < items.length; j += 1) { out.push({ label: entry.label, text: textOf(items[j]) }); }
        } else {
          value = entry.list === "joined" ? listOf(q[entry.field]).join("; ") : textOf(q[entry.field]);
          if (value !== "") { out.push({ label: entry.label, text: value }); }
        }
      }
      out.push({ label: "Answered with", text: kindWords(q) });
      return out;
    }

    // WHERE A QUESTION STANDS (the owner, 2026-10-07: "answers that have been picked up should be
    // moved out of the list"; the founder, 2026-10-12: "once he answers a question it goes away from
    // his list, even if there is a follow-up"). THE LIST IS WHAT HE HAS STILL TO ANSWER:
    //   main     open, not set aside, and not answered: no answer of his stands, or not every part
    //            has one. And for a moment a question he has JUST answered here: green, then folded
    //            to "Answered", until a list that holds the answer has come (header, ONCE HE HAS
    //            ANSWERED). A question in a store from before that rule, asked again under its
    //            number by a reply that asks, is in the list too, once, until he answers it.
    //   thrall   answered, or told something that asks nothing (a note), not closed: the keeper's
    //            turn. Nothing brings it back: what is left to ask comes as a new question.
    //   parked   set aside: by his own Ctrl+B (an act he recorded), or by the keeper, who puts it in a
    //            group the host names (foldedGroups). His unpark brings it back whatever the group.
    //   history  closed.
    // Below the list the last three are each one folded line; Enter and Tab never go into one.
    var FOLDS = ["thrall", "parked", "history"];
    function sectionOf(q) {
      if (textOf(q.state) !== LISTED_STATE) { return "history"; }
      var did = lastActOf(q);
      if (did === "park") { return "parked"; }
      if (did !== "unpark" && parked[textOf(q.group)] === true) { return "parked"; }
      if (reopened[q.number] === true) { return "main"; }
      var st = stateOf(q);
      if (st.answered) { return (st.local || lingers(q)) ? "main" : "thrall"; }
      var msgs = messagesOf(q);
      var last = msgs.length ? msgs[msgs.length - 1] : null;
      if (last && last.asks === false && msgs.some(function (m) { return m.speaker === MINE; })) { return "thrall"; }
      return "main";
    }
    // A QUESTION HE IS IN, OR HAS WORDS IN, STAYS WHERE IT WAS DRAWN until he leaves it: a list that
    // arrives meanwhile never moves the field he is typing in (placedAt: number -> heading key).
    var placedAt = Object.create(null);
    // A question he himself moved (Ctrl+B) is not held where it was, for the one draw that moves it.
    var release = Object.create(null);
    function held(q) {
      if (release[q.number]) { return false; }
      var line = lineOf(q.number);
      return !!line && (line === focusedLine() || drafts[q.number] !== undefined);
    }
    // NEW: asked since this page first ran here, and neither answered nor passed by him. The first
    // time the page runs, every question it is handed counts as seen, so that "new" means new.
    var SEEN_KEY = "horde-decisions-seen-v1";
    var seen = null;
    function loadSeen() {
      try { var s = storage ? JSON.parse(storage.getItem(SEEN_KEY) || "null") : null; if (s && Array.isArray(s.numbers)) { seen = Object.create(null); s.numbers.forEach(function (n) { seen[n] = true; }); } } catch (e) { seen = null; }
    }
    function keepSeen() { try { if (storage && seen) { storage.setItem(SEEN_KEY, JSON.stringify({ numbers: Object.keys(seen).map(Number) })); } } catch (e) { /* only "new" is lost */ } }
    function markSeen(number) { if (seen && !seen[number]) { seen[number] = true; keepSeen(); } }
    function isNew(q) { return !!seen && !seen[q.number] && !stateOf(q).answered; }

    function sectionsOf() {
      var heads = [];
      var byKey = Object.create(null);
      var folds = { thrall: [], parked: [], history: [] };
      var groupsInOrder = [];
      function head(key, kind, name) {
        if (!byKey[key]) { byKey[key] = { key: key, kind: kind, name: name, note: "", qs: [] }; if (kind === "group") { groupsInOrder.push(byKey[key]); } }
        return byKey[key];
      }
      var mine = [];
      questions.forEach(function (q) {
        // A LANE CHOSEN ON THE CARDS: that lane's questions alone, in the list and in every fold.
        if (laneChosen && laneOf(q) !== laneChosen) { return; }
        var section = sectionOf(q);
        var keyWas = placedAt[q.number];
        if (keyWas && held(q)) {
          var wasFold = keyWas.indexOf("fold:") === 0 ? keyWas.slice(5) : "main";
          if (wasFold !== section) { section = wasFold; }
        }
        if (section !== "main") { folds[section].push(q); return; }
        mine.push(q);
      });
      // THE LIST, IN HIS ORDER (header, THE ORDER IS HIS), under a heading for each run of questions
      // that share a group: the first run of a group is keyed by the group's name alone, a later
      // one by the name and which run it is, so that each keeps its own fold between draws.
      var runs = Object.create(null);
      var run = null;
      inOrder(mine, orderKey, orderTurned).forEach(function (q) {
        var name = textOf(q.group);
        if (!run || run.group !== name) {
          runs[name] = (runs[name] || 0) + 1;
          run = head("group:" + name + (runs[name] > 1 ? "#" + runs[name] : ""), "group", name || "No group");
          run.group = name;
        }
        if (!run.note && textOf(q.groupNote)) { run.note = textOf(q.groupNote); }
        run.qs.push(q);
      });
      heads = heads.concat(groupsInOrder);
      // What is with the keeper, and what is set aside, stand in the same order under their folds.
      folds.thrall = inOrder(folds.thrall, orderKey, orderTurned);
      folds.parked = inOrder(folds.parked, orderKey, orderTurned);
      var foldNames = { thrall: "With " + KEEPER, parked: "Parked", history: "History" };
      folds.history.sort(function (a, b) { return textOf(b.closedAt).localeCompare(textOf(a.closedAt)) || (b.number - a.number); });
      FOLDS.forEach(function (f) { if (folds[f].length && (answeredShown || ANSWERED_FOLDS[f] !== true)) { heads.push({ key: "fold:" + f, kind: f, name: foldNames[f], note: "", qs: folds[f] }); } });
      return heads;
    }

    function isFold(head) { return FOLDS.indexOf(head.kind) >= 0; }
    function isFolded(head) {
      return headFolded[head.key] === undefined ? isFold(head) : headFolded[head.key];
    }

    function place() {
      // The first question line that reaches below the top of the view, and where it is.
      var inset = topInset();
      var i, box;
      for (i = 0; i < drawnLines.length; i += 1) {
        box = drawnLines[i].row.getBoundingClientRect();
        if (box.height > 0 && box.bottom > inset) { return { number: drawnLines[i].q.number, top: box.top }; }
      }
      return null;
    }

    function lineOf(number) {
      for (var i = 0; i < drawnLines.length; i += 1) { if (drawnLines[i].q.number === number) { return drawnLines[i]; } }
      return null;
    }
    // The fields of a line that can be typed in now: a part that is answered and folded has none.
    function openFields(line) { return line.fields.filter(function (f) { return f.offsetParent !== null; }); }
    // The lines in the run of answering: those with a field to type in. A question folded to
    // "Answered" is passed over by Enter and Tab.
    function shownLines() { return drawnLines.filter(function (line) { return openFields(line).length > 0; }); }
    function focusedLine() {
      var act = document.activeElement;
      for (var i = 0; i < drawnLines.length; i += 1) { if (drawnLines[i].fields.indexOf(act) >= 0) { return drawnLines[i]; } }
      return null;
    }
    function focusedField() {
      var line = focusedLine();
      return line ? document.activeElement : null;
    }

    // A FIELD IS AS TALL AS ITS WORDS, in whole lines: one when empty, unless the grey suggestion
    // needs more, which is measured by standing it in the field for the length of this function.
    // A SAVED ANSWER THE CARET IS NOT IN RESTS AT REST_LINES, and the mark says how many more it has
    // (header, ROOM IS KEPT). Words that are not saved are never shortened.
    function fit(line) {
      if (line.parts) { line.fields.forEach(fitPart); return; }
      var field = line.field;
      if (field.offsetParent === null) { line.more.textContent = ""; return; }
      var linePx = parseFloat(window.getComputedStyle(field).lineHeight) || 22;
      var empty = field.value === "" && field.placeholder !== "";
      if (empty) { field.value = field.placeholder; }
      field.style.height = "auto";
      var lines = Math.max(1, Math.round(field.scrollHeight / linePx));
      if (empty) { field.value = ""; }
      var standing = standingOf(line.q);
      var resting = document.activeElement !== field && !!standing && field.value === textOf(standing.text);
      var shown = (resting && lines > REST_LINES) ? REST_LINES : lines;
      // The box is never shorter than its least height (list.css: two lines, three on a phone), so a
      // resting answer shows that many lines and says how many more it has past them.
      shown = Math.max(shown, Math.round((parseFloat(window.getComputedStyle(field).minHeight) || 0) / linePx));
      field.style.height = "calc(" + shown + " * var(--line-px))";
      line.more.textContent = shown < lines ? ("+" + (lines - shown) + (lines - shown === 1 ? " line" : " lines")) : "";
    }

    // A part's field: as tall as its words, never rested (its words are short, and they are the answer).
    function fitPart(field) {
      if (field.offsetParent === null) { return; }
      var linePx = parseFloat(window.getComputedStyle(field).lineHeight) || 22;
      var empty = field.value === "" && field.placeholder !== "";
      if (empty) { field.value = field.placeholder; }
      field.style.height = "auto";
      var lines = Math.max(1, Math.round(field.scrollHeight / linePx));
      if (empty) { field.value = ""; }
      field.style.height = "calc(" + lines + " * var(--line-px))";
    }

    // One part's row, from what is known now: its mark, the refusal under it, whether its words
    // stand green, and whether it is folded to its saved answer and the word Answered. A part is
    // never folded under the caret, nor while what stands in its field is not the saved answer.
    function refreshPart(line, i) {
      var q = line.q;
      var row = line.rows[i];
      var field = line.fields[i];
      var key = sentKey(q.number, line.parts[i].letter);
      var s = sent[key];
      var saved = partSavedOf(q, line.parts[i].letter);
      var isSaved = !!saved && field.value === textOf(saved.text);
      var words = "";
      if (s && s.pending > 0) { words = WORDS.saving; }
      else if (isSaved) { words = textOf(saved.receipt) || WORDS.saved; }
      else if (field.value !== "" && field.value !== partBaseOf(q, { parts: line.parts }, i)) { words = WORDS.draft; }
      var green = isSaved && isGreen(key);
      var folded = isSaved && !green && document.activeElement !== field && !(s && s.pending > 0) && reopened[q.number] !== true;
      row.mark.textContent = folded ? foldedWords(saved) : words;
      row.mark.hidden = row.mark.textContent === "";
      row.el.classList.toggle("saved-now", green);
      row.el.classList.toggle("answered", folded);
      row.done.textContent = folded ? textOf(saved.text) : "";
      row.done.hidden = !folded;
      row.refusal.textContent = (s && s.refusal) ? s.refusal : (isSaved ? textOf(saved.receiptNote) : "");
      row.refusal.hidden = row.refusal.textContent === "";
    }
    function refresh(line) {
      // The mark and the refusal of one line, from what is known now. No redraw.
      // AND WHERE IT IS ON THE WAY OUT OF THE LIST (header, ONCE HE HAS ANSWERED): green while its
      // saved words are fresh, then folded to the one word Answered - never under the caret, and
      // never while the field holds words that are not the saved answer.
      var q = line.q;
      var s = sent[q.number];
      if (line.parts) { line.parts.forEach(function (p, i) { refreshPart(line, i); }); }
      var mark = line.parts ? { full: "", short: "", note: "" } : markOf(q, lineValue(line));
      line.markFull.textContent = mark.full;
      line.markShort.textContent = mark.short;
      line.mark.hidden = mark.full === "";
      line.markNote.textContent = mark.note;
      line.markNote.hidden = mark.note === "";
      line.refusal.textContent = (s && s.refusal) ? s.refusal : "";
      line.refusal.hidden = !(s && s.refusal);
      var st = stateOf(q);
      var green = !line.parts && st.answered && isGreen(String(q.number));
      var partsBusy = !!line.parts && line.rows.some(function (r) { return !r.el.classList.contains("answered"); });
      var folded = st.answered && !green && !partsBusy && drafts[q.number] === undefined && focusedLine() !== line && !(s && s.pending > 0) && reopened[q.number] !== true;
      line.wrap.classList.toggle("saved-now", green);
      line.wrap.classList.toggle("answered", folded);
      line.done.hidden = !folded;
      line.done.textContent = line.parts ? WORDS.answered : foldedWords(standingOf(q));
      line.keep.hidden = reopened[q.number] !== true;
    }
    // The word an answered question or part folds to: Answered, and while the host says the answer is
    // still on its way, what became of it so far (header, WHAT BECAME OF AN ANSWER).
    function foldedWords(m) {
      var r = m ? textOf(m.receipt) : "";
      return (r && r !== RECEIPT_DONE) ? WORDS.answered + ", " + r : WORDS.answered;
    }
    // The caret into a line that is folded to Answered, or into one of its folded parts: unfolded
    // for as long as the caret stays, so that he can still change what he said before it leaves.
    function unfold(line, part) {
      var field = (part === undefined) ? line.field : line.fields[part];
      line.wrap.classList.remove("answered");
      line.done.hidden = true;
      if (line.parts) { var row = line.rows[part === undefined ? 0 : part]; row.el.classList.remove("answered"); row.done.hidden = true; }
      field.focus({ preventScroll: true });
      fit(line);
      refresh(line);
      onChange();
    }

    // THE VIEW FOLLOWS HIM (the owner, 2026-10-07: "when tabbing to a new question the question should
    // be moved to the top or almost the top of the page so it could be seen completely. When typing
    // goes off the page, the viewport must follow. Similar for when background info is expanded").
    // A question he moves to is brought up to just under the top of the view unless it already stands
    // in the top third of it, whole; the field he types in is kept in view as it grows; a question
    // whose context he unfolds is brought to the top, so that the most of the context shows.
    var NEAR_TOP_PX = 6;
    function toTop(line) {
      var box = line.wrap.getBoundingClientRect();
      var inset = topInset();
      window.scrollBy(0, box.top - inset - NEAR_TOP_PX);
    }
    function intoView(line) {
      var box = line.wrap.getBoundingClientRect();
      var inset = topInset();
      var third = inset + (window.innerHeight - inset) / 3;
      if (box.top < inset || box.top > third || box.bottom > window.innerHeight) { toTop(line); }
    }
    // A FIELD TALLER THAN THE VIEW keeps its foot in view, where the words are being typed: its top
    // is brought down only for a field that fits. Measured 2026-10-08 in the turns scenario, before
    // this rule: forty lines typed into one field, the view scrolled down to its foot 77 times and
    // back up to its top in between, and ended with the foot 936 px down a 470 px view.
    function keepInView(field) {
      if (!field || field.offsetParent === null) { return; }
      var box = field.getBoundingClientRect();
      var inset = topInset();
      timing.follows += 1;
      if (box.bottom > window.innerHeight) { window.scrollBy(0, box.bottom - window.innerHeight + 8); timing.followed += 1; }
      else if (box.top < inset && box.height <= window.innerHeight - inset) { window.scrollBy(0, box.top - inset - NEAR_TOP_PX); }
    }
    function enter(line, part) {
      // Into the part asked for; with none asked for, the first part still to answer. A part that is
      // folded has no field to stand in: the nearest open one after it, or before it, is taken.
      var open = openFields(line);
      if (!open.length) { return; }
      var want = part === undefined ? -1 : (part < 0 ? line.fields.length + part : part);
      var field = null;
      if (want < 0) { for (var u = 0; u < open.length && !field; u += 1) { if (!line.parts || !partSavedOf(line.q, line.parts[line.fields.indexOf(open[u])].letter)) { field = open[u]; } } }
      else if (part !== undefined && part < 0) { field = open[open.length - 1]; }
      else { for (var v = 0; v < open.length && !field; v += 1) { if (line.fields.indexOf(open[v]) >= want) { field = open[v]; } } }
      if (!field) { field = (part !== undefined && part >= 0) ? open[open.length - 1] : open[0]; }
      var sameQuestion = focusedLine() === line;
      field.focus({ preventScroll: true });
      var end = field.value.length;
      try { field.setSelectionRange(end, end); } catch (e) { /* a field not drawn has no caret */ }
      arrived = { number: line.q.number, part: line.fields.indexOf(field), at: Date.now(), bySave: false };
      // From part to part of one question only the field is kept in view; a new question comes up.
      if (sameQuestion) { keepInView(field); } else { intoView(line); keepInView(field); }
      onChange();
    }
    // ENTER AND TAB NEVER GO INTO A FOLD (header, WHERE A QUESTION STANDS): they move among the
    // fields of the list, or - once he has opened the Parked fold and is in it - among its fields.
    function move(line, step) {
      var shown = shownLines().filter(function (l) { return l.zone === line.zone; });
      var at = shown.indexOf(line);
      var next = shown[at + step];
      // Back into a question of parts: its last part, the one just above.
      if (at >= 0 && next) { enter(next, step < 0 ? -1 : 0); return true; }
      return false;
    }
    // ON FROM A FIELD WHOSE WORDS WERE JUST SENT. With a field to go on to, the caret goes there. With
    // none - it was the last question of the list - the caret lets go of the field: a question is
    // never folded under the caret, and the last one he answers must fold to Answered and leave like
    // any other (header, ONCE HE HAS ANSWERED). Nothing sent, the caret stays where it is.
    function onFrom(line, sentNow) {
      var moved = move(line, 1);
      if (sentNow) { arrived.bySave = true; }
      if (!moved && sentNow && document.activeElement && document.activeElement.blur) { document.activeElement.blur(); }
    }
    function mainLines() { return shownLines().filter(function (l) { return l.zone === "main"; }); }
    function takeKeyboard() {
      var shown = mainLines();
      var first = null;
      for (var i = 0; i < shown.length; i += 1) {
        if (!stateOf(shown[i].q).answered) { first = shown[i]; break; }
      }
      if (!first && shown.length) { first = shown[0]; }
      if (first) { enter(first); }
    }

    function typed(line) {
      // What stands in the field now: a draft unless it is the standing answer, word for word.
      var q = line.q;
      var value = lineValue(line);
      if (line.parts) {
        // PART BY PART: the draft is what stands in the parts' fields and is not their saved answer,
        // as the one text the parts make; a part whose field is its saved answer, or empty, is not in it.
        var info = { parts: line.parts };
        var unsent = joinParts(line.parts, line.fields.map(function (f, i) { return f.value === partBaseOf(q, info, i) ? "" : f.value; }));
        if (unsent === "") { delete drafts[q.number]; } else { drafts[q.number] = unsent; }
        line.parts.forEach(function (p, i) { var sp = sent[sentKey(q.number, p.letter)]; if (sp && sp.refusal && line.fields[i].value !== sp.sentText) { sp.refusal = ""; } });
      } else {
        var standing = standingOf(q);
        if (value === (standing ? textOf(standing.text) : "")) { delete drafts[q.number]; } else { drafts[q.number] = value; }
      }
      keepDrafts();
      // Words changed after a refusal are not the words that were refused.
      var s = sent[q.number];
      if (s && s.refusal && value !== s.sentText) { s.refusal = ""; }
      fit(line);
      refresh(line);
      if (focusedLine() === line) { keepInView(document.activeElement); }
      onChange();
    }
    function setValue(line, value, field) {
      field = field || line.field;
      field.value = value;
      try { field.setSelectionRange(value.length, value.length); } catch (e) { /* not drawn */ }
      typed(line);
    }
    function insert(line, text, field) {
      var f = field || line.field;
      var from = f.selectionStart, to = f.selectionEnd;
      f.value = f.value.slice(0, from) + text + f.value.slice(to);
      try { f.setSelectionRange(from + text.length, from + text.length); } catch (e) { /* not drawn */ }
      typed(line);
    }

    // The host has answered what became of words that were sent: -letter names the part they were
    // the answer to, or is "" for an answer to the whole question.
    function answered(number, id, text, result, letter) {
      var key = sentKey(number, letter);
      var s = sentOf(key);
      s.pending -= 1;
      var line = lineOf(number);
      var partAt = (line && line.parts && letter) ? line.parts.map(function (p) { return p.letter; }).indexOf(letter) : -1;
      // SAVED IS WHAT THE HOST SAYS IS SAVED, and nothing else: no answer, or one that is not ok, is not.
      var savedNow = !!result && result.ok === true;
      if (savedNow) {
        // local: known from this page only, until a list arrives that holds it (stateOf).
        s.saved = { text: text, sequence: Number(result.sequence), speaker: MINE, part: letter || "", local: true, arrivedAfterClosing: result.arrivedAfterClosing === true, saidToEarlierWording: result.saidToEarlierWording === true, replaces: s.replacing === true };
        if (s.sentId === id) { s.refusal = ""; }
        // The draft is dropped only if it is still these very words.
        if (!letter && drafts[number] === text) { delete drafts[number]; keepDrafts(); }
        // SAVED: GREEN NOW, FOLDED IN A MOMENT, OUT OF THE LIST WHEN A LIST HOLDS IT (header, ONCE HE
        // HAS ANSWERED). Only here: words that were not saved never turn green.
        greenUntil[key] = Date.now() + GREEN_MS;
        lingerUntil[number] = Date.now() + LINGER_MS;
        window.setTimeout(function () { var l = lineOf(number); if (l) { refresh(l); fit(l); onChange(); } }, GREEN_MS + 20);
        window.setTimeout(function () { if (lastJson !== null) { draw(); } }, LINGER_MS + 40);
      } else if (s.sentId === id) {
        s.refusal = textOf(result && result.reason) || "Not saved, and no reason was given.";
        // BACK TO THE WORDS THAT WERE NOT SAVED, unless the reader is typing somewhere else - which,
        // for a part, may be another part of the same question: there he is typing when its field
        // holds words.
        var now = focusedLine();
        var inField = now ? document.activeElement : null;
        var elsewhere = !!line && (now !== line || (partAt >= 0 && line.fields[partAt] !== inField));
        var typing = !!now && ((now === line && partAt >= 0) ? inField.value !== "" : (lineValue(now) !== "" && drafts[now.q.number] !== undefined));
        if (elsewhere && !typing) { enter(line, partAt >= 0 ? partAt : undefined); }
      }
      // A part's draft is what is typed and not saved: worked out again from the fields (typed).
      if (line && line.parts && letter && savedNow) {
        var info = { parts: line.parts };
        var unsent = joinParts(line.parts, line.fields.map(function (f, i) { return f.value === partBaseOf(line.q, info, i) ? "" : f.value; }));
        if (unsent === "") { delete drafts[number]; } else { drafts[number] = unsent; }
        keepDrafts();
      }
      // What was said above the field may have changed with it: an answer he replaced is now kept
      // there, marked earlier (an edit).
      if (line && savedNow) { line.said = drawTalk(line.q, line.talk, line.ans); }
      // A CHANGE SENT AND SAVED ends the reopening (CHANGE MY ANSWER): the question is answered again, and
      // leaves the list as any answered question does - unless words he typed are still unsent.
      if (savedNow && drafts[number] === undefined) { delete reopened[number]; }
      if (line) { refresh(line); fit(line); }
      onChange();
    }
    function save(line) {
      // Send what stands in the field, if it says something and is not already the standing answer.
      // Returns whether there was anything to send.
      var q = line.q;
      var text = lineValue(line);
      var standing = standingOf(q);
      if (text.trim() === "" || (standing && text === textOf(standing.text))) { return false; }
      var s = sentOf(q.number);
      if (s.pending > 0 && s.sentText === text) { return true; }
      var id = (s.sentText === text && s.sentId) ? s.sentId : newId();
      s.sentText = text; s.sentId = id; s.pending += 1; s.refusal = "";
      s.replacing = !!standing;
      refresh(line);
      var number = q.number;
      Promise.resolve().then(function () { return say(number, text, Number(q.wordingVersion), id); }).then(
        function (result) { answered(number, id, text, result, ""); },
        function (error) { answered(number, id, text, { ok: false, reason: "Not saved: " + ((error && error.message) ? error.message : error) }, ""); });
      return true;
    }
    // ONE PART, SENT BY ITSELF (header, A QUESTION OF SEVERAL PARTS): what stands in that part's
    // field, if it says something and is not already its saved answer. Returns whether there was
    // anything to send. The same words sent twice carry the same id, so they are one answer.
    function savePart(line, at) {
      var q = line.q;
      var letter = line.parts[at].letter;
      var text = line.fields[at].value;
      var saved = partSavedOf(q, letter);
      if (text.trim() === "" || (saved && text === textOf(saved.text))) { return false; }
      var s = sentOf(sentKey(q.number, letter));
      if (s.pending > 0 && s.sentText === text) { return true; }
      var id = (s.sentText === text && s.sentId) ? s.sentId : newId();
      s.sentText = text; s.sentId = id; s.pending += 1; s.refusal = "";
      s.replacing = !!saved;
      refresh(line);
      var number = q.number;
      Promise.resolve().then(function () { return sayPart(number, letter, text, Number(q.wordingVersion), id); }).then(
        function (result) { answered(number, id, text, result, letter); },
        function (error) { answered(number, id, text, { ok: false, reason: "Not saved: " + ((error && error.message) ? error.message : error) }, letter); });
      return true;
    }

    // THE BACK BURNER BY HIS OWN KEY (the owner, 2026-10-07: "there should be an ability to put a
    // question on the back burner"). Ctrl+B on a question of the list parks it: it goes to the Parked
    // fold, the caret goes on, and a short line offers Ctrl+Z to undo for UNDO_MS. Ctrl+B on a question
    // in the Parked fold brings it back. Each is HIS OWN ACT, recorded through the operation say with
    // act park or unpark (decisions/Rules.ps1), so that the keeper sees it; the question's group
    // is never changed, so unparking needs nothing remembered to put it back where it was.
    var UNDO_MS = 6000;
    var toast = null;
    function showToast(text, undo) {
      if (!toast) { toast = make("div", "hd-toast"); toast.setAttribute("role", "status"); document.body.appendChild(toast); }
      toast.textContent = text;
      toast.hidden = false;
      var shownAt = Date.now();
      toast.undo = undo ? { run: undo, until: shownAt + UNDO_MS } : null;
      window.setTimeout(function () { if (toast.undo === null || Date.now() >= shownAt + UNDO_MS) { if (toast.lastAt === shownAt) { toast.hidden = true; toast.undo = null; } } }, UNDO_MS + 20);
      toast.lastAt = shownAt;
      onChange();
    }
    function setParked(line, park) {
      var q = line.q;
      var number = q.number;
      var id = newId();
      var was = acted[number] || null;
      acted[number] = { act: park ? "park" : "unpark", sequence: Infinity };
      var next = null;
      if (park) {
        var zone = shownLines().filter(function (l) { return l.zone === line.zone; });
        var at = zone.indexOf(line);
        next = zone[at + 1] || zone[at - 1] || null;
      }
      markSeen(number);
      release[number] = true;
      draw();
      delete release[number];
      if (park) { if (next && lineOf(next.q.number)) { enter(lineOf(next.q.number)); } }
      else { var back = lineOf(number); if (back) { enter(back); } }
      showToast((park ? "Question " + number + " parked." : "Question " + number + " is back in the list.") + " Ctrl+Z to undo.", function () { var l = lineOf(number); if (l) { setParked(l, !park); } });
      Promise.resolve().then(function () { return act(number, park ? "park" : "unpark", Number(q.wordingVersion), id); }).then(function (result) {
        if (result && result.ok === true) { acted[number] = { act: park ? "park" : "unpark", sequence: Number(result.sequence) }; return; }
        acted[number] = was;
        draw();
        showToast("Not " + (park ? "parked" : "brought back") + ": " + textOf(result && result.reason), null);
      }, function (error) { acted[number] = was; draw(); showToast("Not " + (park ? "parked" : "brought back") + ": " + textOf(error && error.message ? error.message : error), null); });
    }
    // Ctrl+Z while the short line offers it: undo the park or the unpark.
    document.addEventListener("keydown", function (e) {
      if (!toast || !toast.undo || !(e.key === "z" || e.key === "Z") || !e.ctrlKey || e.altKey || e.shiftKey) { return; }
      if (Date.now() > toast.undo.until) { return; }
      e.preventDefault(); e.stopPropagation();
      var run = toast.undo.run;
      toast.undo = null;
      run();
    }, true);
    // Ctrl+Down: to the folded lines, where Enter or Space opens one and Up and Down go between them.
    // With no fold drawn (the answered hidden and nothing parked), to the switch for the answered
    // instead, so a press of Space can show them (THE SWITCH IS REACHED BY KEYS, at the switch).
    function toFolds() {
      for (var i = 0; i < drawnHeads.length; i += 1) { if (isFold(drawnHeads[i].head)) { drawnHeads[i].tri.focus(); onChange(); return; } }
      toSwitch();
    }

    function toggleContext(q) {
      var opening = !isOpen(q, !lineOf(q.number) && !!rowOf(q.number));
      unfolded[q.number] = opening;
      draw();
      // Unfolded, the question goes to the top of the view, so that the most of its context shows.
      var line = lineOf(q.number) || rowOf(q.number);
      if (opening && line) { toTop(line); }
    }

    // THE KEYS IN A PART'S FIELD (header, A QUESTION OF SEVERAL PARTS): Enter and Tab SEND THAT PART,
    // if it says something new, and go to the next part still open - from the last one, to the next
    // question; Shift+Tab goes back a part. A Tab on an empty part with a suggestion fills it and
    // stays; a Tab on a part of one character moves on and sends nothing (the owner's question 28:
    // one letter is the start of an answer, not an answer). Ctrl+Enter in an empty part takes its
    // suggestion and sends it; on the first part with every part empty it takes every part's, sends
    // each, and goes to the next question.
    function onPartKey(e, line, field) {
      var at = fieldIndex(line, field);
      var key = e.key;
      var plain = !e.ctrlKey && !e.altKey && !e.metaKey;
      var rec = line.parts[at].rec;
      // On from this part: the next open part of the question, else the next question.
      var onward = function (sentNow) {
        var open = openFields(line);
        for (var i = 0; i < open.length; i += 1) { if (fieldIndex(line, open[i]) > at) { enter(line, fieldIndex(line, open[i])); if (sentNow) { arrived.bySave = true; } return; } }
        onFrom(line, sentNow === true);
      };
      var back = function () {
        var open = openFields(line);
        for (var i = open.length - 1; i >= 0; i -= 1) { if (fieldIndex(line, open[i]) < at) { enter(line, fieldIndex(line, open[i])); return; } }
        move(line, -1);
      };
      var leave = function () { onward(savePart(line, at)); };
      if (key === "Enter" && e.ctrlKey) {
        e.preventDefault();
        var allEmpty = line.fields.every(function (f) { return f.value.trim() === ""; });
        if (at === 0 && allEmpty) {
          line.fields.forEach(function (f, i) { if (line.parts[i].rec) { f.value = line.parts[i].rec; } });
          typed(line);
          var any = false;
          line.parts.forEach(function (p, i) { if (savePart(line, i)) { any = true; } });
          onFrom(line, any);
          return true;
        }
        if (field.value.trim() === "" && rec) { setValue(line, rec, field); }
        leave();
        return true;
      }
      if (key === "Enter" && plain && !e.shiftKey) {
        e.preventDefault();
        // The tail of a doubled key press, on the empty part the caret has only just arrived in.
        if (field.value === "" && arrived.number === line.q.number && arrived.part === at && Date.now() - arrived.at < (arrived.bySave ? SAVE_ECHO_MS : ARRIVAL_MS)) { return true; }
        leave();
        return true;
      }
      if (key === "Tab" && e.shiftKey) { e.preventDefault(); back(); return true; }
      if (key === "Tab" && plain) {
        e.preventDefault();
        if (field.value === "" && rec) { setValue(line, rec, field); return true; }
        if (field.value.trim().length === 1) { onward(false); return true; }
        leave();
        return true;
      }
      if (key === "ArrowRight" && plain && !e.shiftKey && field.value === "" && rec) { e.preventDefault(); setValue(line, rec, field); return true; }
      return false;
    }

    function onKey(e, line, field) {
      if (e.isComposing) { return; }
      field = field || line.field;
      if ((e.key === "b" || e.key === "B") && e.ctrlKey && !e.altKey && !e.shiftKey) { e.preventDefault(); setParked(line, line.zone !== "parked"); return; }
      if (e.key === "ArrowDown" && e.ctrlKey && !e.altKey && !e.shiftKey) { e.preventDefault(); toFolds(); return; }
      if ((e.key === "Enter" && e.shiftKey) || ((e.key === "j" || e.key === "J") && e.ctrlKey && !e.altKey)) { e.preventDefault(); insert(line, "\n", field); return; }
      if (line.parts && onPartKey(e, line, field)) { return; }
      var q = line.q;
      var key = e.key;
      var plain = !e.ctrlKey && !e.altKey && !e.metaKey;
      var blank = field.value.trim() === "";
      var rec = recOf(q);
      if (key === "Enter" && e.ctrlKey) {
        e.preventDefault();
        if (blank) { if (!rec) { return; } setValue(line, rec); }
        onFrom(line, save(line));
        return;
      }
      if (key === "Enter" && plain) {
        e.preventDefault();
        if (field.value === "" && arrived.number === q.number && Date.now() - arrived.at < (arrived.bySave ? SAVE_ECHO_MS : ARRIVAL_MS)) { return; }
        onFrom(line, save(line));
        return;
      }
      if (key === "Tab" && e.shiftKey) { e.preventDefault(); move(line, -1); return; }
      if (key === "Tab" && plain) {
        e.preventDefault();
        if (field.value === "" && rec) { setValue(line, rec); return; }
        // ONE CHARACTER IS NOT AN ANSWER TO SEND ON A TAB (the owner's question 28, 2026-10-07: he
        // began "a ..." and a Tab stored the answer "a"). It stays, a draft, and the caret moves on.
        if (field.value.trim().length === 1) { move(line, 1); return; }
        onFrom(line, save(line));
        return;
      }
      if (key === "ArrowRight" && plain && !e.shiftKey && field.value === "" && rec) { e.preventDefault(); setValue(line, rec); return; }
      if (key === "F2" || ((key === " " || e.code === "Space") && e.ctrlKey)) { e.preventDefault(); toggleContext(q); }
    }
    // THE SEND KEY ATTACHED TO A BOX does what Enter does in that field, by the very same handler (one
    // path for a key and a tap): the words are sent and the caret goes on. An empty box sends nothing;
    // the tap only puts the caret in it.
    function sendFrom(line, field) {
      if (document.activeElement !== field) { field.focus({ preventScroll: true }); }
      if (field.value.trim() === "") { return; }
      arrived.at = 0;
      onKey({ key: "Enter", code: "Enter", ctrlKey: false, altKey: false, metaKey: false, shiftKey: false, isComposing: false, preventDefault: function () {} }, line, field);
    }
    // A field in its box, with its Send key attached at the box's foot. A press on the key keeps the
    // caret (and a phone's keyboard) where it is: the press itself takes no focus.
    function boxed(field, send, says) {
      var box = make("div", "hd-box");
      var key = make("button", "hd-send", BOX_WORDS.send);
      key.type = "button";
      key.tabIndex = -1;
      key.setAttribute("aria-label", says);
      key.addEventListener("pointerdown", function (e) { e.preventDefault(); });
      key.addEventListener("mousedown", function (e) { e.preventDefault(); });
      key.addEventListener("click", function (e) { e.stopPropagation(); send(); });
      // A press on the box's own edge or padding is a press in its field.
      box.addEventListener("click", function (e) { if (e.target === box) { field.focus(); } });
      box.appendChild(field); box.appendChild(key);
      return { box: box, key: key };
    }

    function drawMessage(m, who) {
      who = who || (m.speaker === MINE ? WORDS.you : WORDS.keeper);
      var row = make("div", "hd-msg");
      row.appendChild(make("span", "hd-who", who + ":"));
      var said = make("span", "hd-said", textOf(m.text));
      said.setAttribute("dir", "auto");
      row.appendChild(said);
      if (m.holdsDirectionOrInvisibleCharacters === true) { row.appendChild(make("span", "hd-flag", " (" + WORDS.marks + ")")); }
      return { row: row, said: said, who: who };
    }
    // WHAT WAS SAID UNDER A QUESTION, above its field, into -box (emptied first): each message one line
    // except the one he has to answer; an answer of his that he replaced, one line marked as earlier.
    // Returns the drawn messages. Used to draw a question and to bring one he is in up to date in place.
    function drawTalk(q, box, ans) {
      while (box.firstChild) { box.removeChild(box.firstChild); }
      ans.classList.remove("wide");
      var said = [];
      var earlier = earlierOf(q);
      var answered = stateOf(q).answered;
      earlier.forEach(function (m, i) {
        var drawn = drawMessage(m, replacedLater(q, m) ? WORDS.earlier : null);
        // Whole only when it is what the reader has to answer (header, ROOM IS KEPT); else one line,
        // and a press on it unfolds the question, which shows it whole.
        if (answered || i !== earlier.length - 1 || m.speaker === MINE) {
          drawn.row.classList.add("brief");
          drawn.row.addEventListener("click", function () {
            if (String(window.getSelection ? window.getSelection() : "") !== "") { return; }
            toggleContext(q);
          });
        } else {
          // What he has to answer is read like the question: in the page's own ink, and across the
          // whole row, never squeezed into the column beside a short question (seen 2026-10-07 in a
          // picture of the wide window: a reply of fifteen lines in a third of the width, the rest bare).
          drawn.row.classList.add("asks");
          ans.classList.add("wide");
        }
        box.appendChild(drawn.row);
        said.push(drawn);
      });
      if (q.thread && textOf(q.thread.problem)) { box.appendChild(make("div", "hd-refusal", q.thread.problem)); }
      var info = partsOf(q);
      if (info) {
        ans.classList.add("wide");
        var standingNow = standingOf(q);
        if (standingNow && !readParts(textOf(standingNow.text), info.parts)) {
          // His answer from before the parts had fields: shown as what he said, one line, never pulled apart.
          var earlierAnswer = drawMessage(standingNow);
          earlierAnswer.row.classList.add("brief");
          box.appendChild(earlierAnswer.row);
          said.push(earlierAnswer);
        }
        if (info.recOnce) { box.appendChild(make("div", "hd-partsrec", "Recommended: " + info.recOnce)); }
      }
      return said;
    }
    // WHAT STANDS OUT ABOUT A QUESTION, as one small line above what was said under it, into -box
    // (emptied first): the few plain words for how much it matters and how much it holds up, as the
    // list hands them out (importanceShown, blocksShown - nothing for the defaults, and nothing from
    // a list that has neither), and, for a follow-up, the question it follows: one pressable line,
    // "Follows up on question 7", that unfolds that question's words and what he answered. Returns
    // { badges, follow } as drawn. The line takes no room when there is nothing to say.
    var followShown = Object.create(null);
    function drawTags(q, box) {
      while (box.firstChild) { box.removeChild(box.firstChild); }
      var drawn = { badges: [], follow: null };
      [textOf(q.importanceShown), textOf(q.blocksShown)].forEach(function (words) {
        if (words === "") { return; }
        var badge = make("span", "hd-badge", words);
        box.appendChild(badge);
        drawn.badges.push(badge);
      });
      var old = (q.followsUp && typeof q.followsUp === "object") ? q.followsUp : null;
      if (old) {
        var shown = followShown[q.number] === true;
        var press = make("button", "hd-follow-btn", "Follows up on question " + textOf(old.number));
        press.type = "button";
        press.tabIndex = -1;
        press.setAttribute("aria-expanded", shown ? "true" : "false");
        press.addEventListener("click", function (e) { e.stopPropagation(); followShown[q.number] = followShown[q.number] !== true; draw(); });
        box.appendChild(press);
        var more = make("div", "hd-follow");
        more.hidden = !shown;
        if (textOf(old.title) === "") { more.appendChild(make("div", "hd-msg", "Question " + textOf(old.number) + " cannot be shown here.")); }
        else {
          var asked = make("div", "hd-msg");
          asked.appendChild(make("span", "hd-who", "Question " + textOf(old.number) + ":"));
          var words = make("span", "hd-said", textOf(old.title));
          words.setAttribute("dir", "auto");
          asked.appendChild(words);
          more.appendChild(asked);
          var was = make("div", "hd-msg");
          if (textOf(old.answer) === "") { was.textContent = "You had not answered it."; }
          else {
            was.appendChild(make("span", "hd-who", "You answered:"));
            var said = make("span", "hd-said", textOf(old.answer) + (old.answerCut === true ? " ..." : ""));
            said.setAttribute("dir", "auto");
            was.appendChild(said);
            if (old.answerCut === true) { was.appendChild(make("span", "hd-flag", " (the start of it; the rest is under question " + textOf(old.number) + ")")); }
          }
          more.appendChild(was);
          if (textOf(old.outcome) !== "") {
            var done = make("div", "hd-msg");
            done.appendChild(make("span", "hd-who", "What was done:"));
            done.appendChild(make("span", "hd-said", textOf(old.outcome)));
            more.appendChild(done);
          }
        }
        box.appendChild(more);
        drawn.follow = { press: press, more: more, shown: shown };
      }
      box.hidden = !box.firstChild;
      return drawn;
    }
    // HIS LITTLE BUTTONS (the founder, 2026-10-14: "I want to be able to change importance level and
    // blockingness level by clicking on a little button next to a decision to change it"). Above what
    // stands out about a question still on his list, two small buttons say its two words in plain
    // words - "Importance: High", "Blocking: Part". A press does not change anything by itself: it opens
    // the three levels under the button, the one in force ticked, so a press that missed changes nothing;
    // a press on another level asks the host (options.rank) and closes them, and on the one in force
    // just closes them. Escape, or a press anywhere else, closes them too.
    // THE ORDER MOVES WHEN THE HOST HAS MADE THE CHANGE, NOT BEFORE: until a list arrives that holds the
    // new level, the button says it with "(sending)" and the question stays where it stands, so what
    // he sees in place is never more than what is so. A refusal puts the button back and says why.
    var RANK_BUTTONS = [
      { key: "importance", label: "Importance", levels: IMPORTANCES, fallback: DEFAULT_IMPORTANCE, words: { high: "High", normal: "Normal", low: "Low" } },
      { key: "blocks", label: "Blocking", levels: BLOCKINGS, fallback: DEFAULT_BLOCKS, words: { all: "All", part: "Part", none: "None" } }
    ];
    // By "<number>:<key>": the change on its way, { level, id, ok }; and which button's levels are open.
    var rankPending = Object.create(null);
    var rankOpen = "";
    // The tick beside the level in force: a check mark, made from its code so the source stays ASCII.
    var RANK_TICK = String.fromCharCode(0x2713);
    function rankWordOf(q, b) { var w = textOf(q[b.key]); return w === "" ? b.fallback : w; }
    function rankShown(b, level) { return b.words[level] || capital(level); }
    function redrawRank(number) { var line = lineOf(number); if (line) { drawRank(line.q, line.rankBox); onChange(); } }
    // A change the list now holds - or one the host said is made, once a list has come since - is done.
    function settleRanks() {
      Object.keys(rankPending).forEach(function (k) {
        var p = rankPending[k];
        var at = k.indexOf(":");
        var number = Number(k.slice(0, at));
        var b = RANK_BUTTONS.filter(function (x) { return x.key === k.slice(at + 1); })[0];
        var q = questions.filter(function (x) { return x.number === number; })[0];
        if (!q || !b || rankWordOf(q, b) === p.level || p.ok === true) { delete rankPending[k]; }
      });
    }
    function pickRank(q, b, level) {
      var k = q.number + ":" + b.key;
      rankOpen = "";
      if (level === rankWordOf(q, b) && !rankPending[k]) { redrawRank(q.number); return; }
      var id = newId();
      rankPending[k] = { level: level, id: id, ok: false };
      redrawRank(q.number);
      Promise.resolve().then(function () { return rank(q.number, b.key, level, id); }).then(function (result) {
        var p = rankPending[k];
        if (!p || p.id !== id) { return; }
        if (result && result.ok === true) {
          var now = questions.filter(function (x) { return x.number === q.number; })[0];
          if (now && rankWordOf(now, b) === level) { delete rankPending[k]; } else { p.ok = true; }
        } else {
          delete rankPending[k];
          showToast(b.label + " of question " + q.number + " not changed: " + textOf(result && result.reason ? result.reason : "no reason was given"), null);
        }
        redrawRank(q.number);
      }, function (error) {
        var p = rankPending[k];
        if (p && p.id === id) { delete rankPending[k]; }
        showToast(b.label + " of question " + q.number + " not changed: " + textOf(error && error.message ? error.message : error), null);
        redrawRank(q.number);
      });
    }
    // The two buttons of -q into -box (emptied first), and the levels of the one that is open. Nothing for
    // a question that is not on his list: closed, or answered.
    function drawRank(q, box) {
      while (box.firstChild) { box.removeChild(box.firstChild); }
      box.hidden = textOf(q.state) !== LISTED_STATE || stateOf(q).answered;
      if (box.hidden) { return; }
      RANK_BUTTONS.forEach(function (b) {
        var k = q.number + ":" + b.key;
        var p = rankPending[k];
        var level = p ? p.level : rankWordOf(q, b);
        var open = rankOpen === k;
        var btn = make("button", "hd-rank-btn" + (p ? " pending" : ""), b.label + ": " + rankShown(b, level) + (p ? " (sending)" : ""));
        btn.type = "button";
        btn.tabIndex = -1;
        btn.setAttribute("data-rank", b.key);
        btn.setAttribute("aria-haspopup", "true");
        btn.setAttribute("aria-expanded", open ? "true" : "false");
        btn.setAttribute("aria-label", b.label + " of question " + q.number + ": " + rankShown(b, level) + (p ? ", being sent" : "") + ". Press to change it.");
        btn.addEventListener("click", function (e) {
          e.stopPropagation();
          // One button's levels open at a time: another question's that were open close.
          var was = rankOpen;
          rankOpen = was === k ? "" : k;
          drawRank(q, box);
          if (was !== "" && Number(was.slice(0, was.indexOf(":"))) !== q.number) { redrawRank(Number(was.slice(0, was.indexOf(":")))); }
          onChange();
        });
        box.appendChild(btn);
        if (!open) { return; }
        var pick = make("div", "hd-rank-pick");
        pick.setAttribute("role", "group");
        pick.setAttribute("aria-label", b.label + " of question " + q.number);
        b.levels.forEach(function (w) {
          var now = w === level;
          var opt = make("button", "hd-rank-opt" + (now ? " now" : ""), (now ? RANK_TICK + " " : "") + rankShown(b, w));
          opt.type = "button";
          opt.setAttribute("data-level", w);
          opt.setAttribute("aria-pressed", now ? "true" : "false");
          opt.setAttribute("aria-label", now ? (b.label + ": " + rankShown(b, w) + ", as it is now") : ("Set " + b.label.toLowerCase() + " of question " + q.number + " to " + rankShown(b, w)));
          opt.addEventListener("click", function (e) { e.stopPropagation(); pickRank(q, b, w); });
          pick.appendChild(opt);
        });
        // ESCAPE CLOSES THE LEVELS AND GOES NO FURTHER: the window's own Escape hands the keyboard back.
        pick.addEventListener("keydown", function (e) { if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); rankOpen = ""; drawRank(q, box); btn.focus(); onChange(); } });
        box.appendChild(pick);
      });
    }
    document.addEventListener("pointerdown", function (e) {
      if (rankOpen === "" || (e.target && e.target.closest && e.target.closest(".hd-rank"))) { return; }
      var number = Number(rankOpen.slice(0, rankOpen.indexOf(":")));
      rankOpen = "";
      redrawRank(number);
    });

    // The context of an unfolded question, its sub-numbered lines, into -box (emptied first).
    // readOnly: a row of With Thrall or History (isOpen).
    function drawSubs(q, box, readOnly) {
      while (box.firstChild) { box.removeChild(box.firstChild); }
      var subs = [];
      box.hidden = !isOpen(q, readOnly === true);
      if (box.hidden) { return subs; }
      var lines = subLinesOf(q);
      for (var i = 0; i < lines.length; i += 1) {
        var line = make("div", "hd-row hd-line");
        var subNum = make("span", "hd-num", q.number + "." + (i + 1));
        line.appendChild(subNum);
        // The label and the words are one run of text, so a long line wraps under its label.
        var body = make("span", "hd-body");
        if (lines[i].label) { body.appendChild(make("span", "hd-lab", lines[i].label + ":")); }
        var subTxt = make("span", "hd-txt", lines[i].text);
        body.appendChild(subTxt);
        line.appendChild(body);
        box.appendChild(line);
        subs.push({ num: subNum, label: lines[i].label, txt: subTxt });
      }
      return subs;
    }

    function drawQuestion(q) {
      var open = isOpen(q, false);
      var wrap = make("div", "hd-q" + (open ? " open" : "") + (dim && dim(q) ? " dim" : ""));
      var row = make("div", "hd-qrow");
      var qt = make("div", "hd-qt");
      var tri = make("button", "hd-tri");
      tri.type = "button";
      tri.tabIndex = -1;
      tri.setAttribute("aria-expanded", open ? "true" : "false");
      tri.setAttribute("aria-label", (open ? "Fold the context of question " : "Unfold the context of question ") + q.number);
      var num = make("span", "hd-num");
      var letter = make("span", "hd-let", letterOf(q.askedBy));
      var no = make("span", "hd-no", q.number);
      num.appendChild(letter); num.appendChild(no);
      var txt = make("span", "hd-txt", textOf(q.title));
      qt.appendChild(tri); qt.appendChild(num); qt.appendChild(txt);
      qt.addEventListener("click", function () {
        // Dragging across the words to copy them is not a wish to unfold the line.
        if (String(window.getSelection ? window.getSelection() : "") !== "") { return; }
        toggleContext(q);
      });
      var ans = make("div", "hd-ans");
      var rankBox = make("div", "hd-rank");
      ans.appendChild(rankBox);
      drawRank(q, rankBox);
      var tagBox = make("div", "hd-tags");
      ans.appendChild(tagBox);
      var tags = drawTags(q, tagBox);
      var talk = make("div", "hd-talk");
      ans.appendChild(talk);
      var said = drawTalk(q, talk, ans);
      var info = partsOf(q);
      var rows = [];
      var fl = make("div", "hd-fl");
      var mark = make("span", "hd-mark");
      var markFull = make("span", "hd-mark-full");
      var markShort = make("span", "hd-mark-short");
      var more = make("span", "hd-mark-more");
      mark.appendChild(markFull); mark.appendChild(markShort); mark.appendChild(more);
      var fields = [];
      var field;
      var ansLabel;
      if (info) {
        // A field per part (header, A QUESTION OF SEVERAL PARTS), across the whole row.
        var values = partValuesOf(q, info);
        var box = make("div", "hd-parts");
        info.parts.forEach(function (part, i) {
          var prow = make("div", "hd-part");
          var label = make("div", "hd-partlab");
          label.appendChild(make("span", "hd-partlet", "(" + part.letter + ")"));
          label.appendChild(make("span", "hd-partwords", part.words));
          var pf = make("textarea", "hd-field hd-partfield");
          pf.rows = 1;
          pf.setAttribute("dir", "auto");
          pf.setAttribute("aria-label", "Your answer to part " + part.letter + " of question " + q.number);
          pf.spellcheck = false;
          pf.placeholder = part.rec;
          pf.value = values[i];
          // EACH PART HAS ITS OWN MARK AND ITS OWN REFUSAL (it is sent by itself), and, once it is
          // answered, one line in place of its field: his words and the word Answered. A press on
          // that line brings the field back, for as long as the caret stays in it.
          var pmark = make("span", "hd-partmark");
          pmark.hidden = true;
          label.appendChild(pmark);
          var pdone = make("div", "hd-partdone");
          pdone.setAttribute("dir", "auto");
          pdone.hidden = true;
          var prefusal = make("div", "hd-refusal");
          prefusal.hidden = true;
          var pbox = boxed(pf, function () { sendFrom(drawn, pf); }, "Send the answer to part " + part.letter + " of question " + q.number);
          prow.appendChild(label); prow.appendChild(pbox.box); prow.appendChild(pdone); prow.appendChild(prefusal);
          box.appendChild(prow);
          fields.push(pf);
          rows.push({ el: prow, mark: pmark, done: pdone, refusal: prefusal });
        });
        fl.appendChild(box); fl.appendChild(mark);
        fl.classList.add("parts");
        field = fields[0];
        // Each part's field is named by its own words (its aria-label); this line says what they are.
        ansLabel = make("div", "hd-anslab", BOX_WORDS.parts);
      } else {
        field = make("textarea", "hd-field");
        field.rows = 1;
        field.id = idPrefix + "answer-" + q.number;
        field.setAttribute("dir", "auto");
        field.spellcheck = false;
        field.placeholder = recOf(q);
        field.value = valueOf(q);
        fields.push(field);
        // THE LABEL IS TIED TO ITS FIELD (for and id): what it says is what a screen reader names the
        // field, the question's number in words only a screen reader reads.
        ansLabel = make("label", "hd-anslab", BOX_WORDS.label);
        ansLabel.htmlFor = field.id;
        ansLabel.appendChild(make("span", "hd-sr", " to question " + q.number));
        var single = boxed(field, function () { sendFrom(drawn, field); }, "Send the answer to question " + q.number);
        fl.appendChild(single.box); fl.appendChild(mark);
      }
      var markNote = make("div", "hd-marknote");
      markNote.hidden = true;
      var refusal = make("div", "hd-refusal");
      refusal.hidden = true;
      // THE ONE WORD A QUESTION FOLDS TO once he has answered it (header, ONCE HE HAS ANSWERED), until
      // it leaves the list. A press on it brings the field back for as long as the caret stays.
      var done = make("button", "hd-answered", WORDS.answered);
      done.type = "button";
      done.tabIndex = -1;
      done.hidden = true;
      // "Keep my answer" (CHANGE MY ANSWER): shown only while the question is reopened; what he typed and
      // did not send is dropped with it, because it was a change he has decided against.
      var keep = make("button", "hd-keep", WORDS.keep);
      keep.type = "button";
      keep.hidden = true;
      // ONE STAGE (header): the context stands in the one run of details, after what was said and
      // before the label and the box - never under the box, where it read as a second showing.
      var subBox = make("div", "hd-sub");
      ans.appendChild(subBox);
      var subs = drawSubs(q, subBox);
      if (!subBox.hidden) { ans.classList.add("wide"); }
      ans.appendChild(ansLabel);
      ans.appendChild(fl); ans.appendChild(markNote); ans.appendChild(refusal); ans.appendChild(done); ans.appendChild(keep);
      row.appendChild(qt); row.appendChild(ans);
      wrap.appendChild(row);
      var drawn = { q: q, wrap: wrap, row: row, tri: tri, num: no, letter: letter, txt: txt, ans: ans, rankBox: rankBox, tagBox: tagBox, tags: tags, talk: talk, subBox: subBox, ansLabel: ansLabel, field: field, fields: fields, rows: rows, parts: info ? info.parts : null, mark: mark, markFull: markFull, markShort: markShort, more: more, markNote: markNote, refusal: refusal, done: done, keep: keep, said: said, subs: subs };
      keep.addEventListener("click", function (e) {
        e.stopPropagation();
        var n = drawn.q.number;
        delete reopened[n];
        delete drafts[n];
        keepDrafts();
        var sp = sent[sentKey(n, "")];
        if (sp) { sp.refusal = ""; }
        if (drawn.parts) { drawn.parts.forEach(function (p) { var spp = sent[sentKey(n, p.letter)]; if (spp) { spp.refusal = ""; } }); }
        draw();
      });
      done.addEventListener("click", function (e) { e.stopPropagation(); if (!drawn.parts) { unfold(drawn); } });
      rows.forEach(function (r, i) { r.done.addEventListener("click", function (e) { e.stopPropagation(); unfold(drawn, i); }); });
      fields.forEach(function (f) {
        f.addEventListener("input", function () { typed(drawn); });
        f.addEventListener("keydown", function (e) { onKey(e, drawn, f); });
        // The caret in it, an answer is whole; the caret gone, a saved one rests again - and an
        // answered one folds again. A question the caret has been in and left has been passed: it
        // is no longer new.
        f.addEventListener("focus", function () { fit(drawn); onChange(); });
        f.addEventListener("blur", function () { window.setTimeout(function () { refresh(drawn); fit(drawn); if (focusedLine() !== drawn) { markSeen(drawn.q.number); } onChange(); }, 0); });
      });
      refresh(drawn);
      return drawn;
    }

    // A QUESTION HE IS IN, OR HAS WORDS IN, IS BROUGHT UP TO DATE IN PLACE (the owner, 2026-10-07: "it
    // lags on text input"; the coordinator's rule: a refresh never replaces a field that has the caret
    // or holds a draft). Its words, what was said under it, its context and its mark are drawn again;
    // its fields and the caret in them are not touched.
    function update(line, q) {
      line.q = q;
      line.txt.textContent = textOf(q.title);
      line.letter.textContent = letterOf(q.askedBy);
      var open = isOpen(q, false);
      line.wrap.classList.toggle("open", open);
      line.wrap.classList.toggle("dim", !!(dim && dim(q)));
      line.tri.setAttribute("aria-expanded", open ? "true" : "false");
      line.tri.setAttribute("aria-label", (open ? "Fold the context of question " : "Unfold the context of question ") + q.number);
      drawRank(q, line.rankBox);
      line.tags = drawTags(q, line.tagBox);
      line.said = drawTalk(q, line.talk, line.ans);
      line.subs = drawSubs(q, line.subBox);
      if (!line.subBox.hidden) { line.ans.classList.add("wide"); }
      refresh(line);
    }

    // A ROW THAT IS ONLY READ (header, WHERE A QUESTION STANDS): a question with the keeper, or closed.
    // Its words, then his last answer (two lines at most) and the keeper's last words after it, or the
    // outcome it was closed with. A press on it unfolds its context.
    var drawnRows = [];
    function rowOf(number) { for (var i = 0; i < drawnRows.length; i += 1) { if (drawnRows[i].q.number === number) { return drawnRows[i]; } } return null; }
    // THE LOCAL TIME OF A STORED TIME, as 14:02, or "" when it is not one.
    function timeOf(at) {
      var d = new Date(textOf(at));
      if (isNaN(d.getTime())) { return ""; }
      function two(n) { return (n < 10 ? "0" : "") + n; }
      return two(d.getHours()) + ":" + two(d.getMinutes());
    }
    // WHAT BECAME OF HIS LAST CHANGE (CHANGE MY ANSWER), from the question's answerChanges - { status, lines,
    // button, closed }: status is "none", "waiting" or the Orc's reply word; lines the sentence(s) to draw,
    // button whether "Change my answer" is offered, closed the line that says why it is not. -Answered: he has
    // an answer that stands.
    function changeOf(q, answeredNow) {
      var out = { status: "none", lines: [], button: false, closed: "" };
      var list = listOf(q.answerChanges);
      var last = list.length ? list[list.length - 1] : null;
      if (last) {
        var when = timeOf(last.at);
        var told = "You changed your answer" + (when ? " at " + when : "") + ".";
        var reply = (last.reply && typeof last.reply === "object") ? last.reply : null;
        var orc = textOf(last.orcShown);
        if (reply) {
          var by = "Orc " + textOf(reply.by);
          var word = textOf(reply.reply);
          out.status = word;
          if (word === "not-acted") { out.lines.push(told + " " + by + " had not acted yet and is using the new answer."); }
          else if (word === "undoing") { out.lines.push(told + " " + by + " had already acted on the first one and is undoing it."); }
          else if (word === "cannot-undo") { out.lines.push(told + " " + by + " had already acted on the first one and says it cannot undo: " + textOf(reply.why) + "."); }
          else { out.lines.push(told + " " + by + " answered: " + textOf(reply.replyShown) + "."); }
        } else if (orc !== "" && textOf(q.state) === LISTED_STATE) {
          out.status = "waiting";
          out.lines.push("answer changed - waiting for " + orc + " to confirm");
        } else { out.lines.push(told); }
      }
      if (textOf(q.state) === LISTED_STATE) { out.button = !!answeredNow && !reopened[q.number]; }
      else if (answeredNow) { out.closed = "This question is closed - " + (textOf(q.actedBy) || "the warchief") + " has acted on it. To change course, ask a follow-up."; }
      return out;
    }
    // A TAP ON "Change my answer": the question comes back into the list with its answer box open, his
    // current answer in it and selected, the caret in it.
    function reopen(q) {
      reopened[q.number] = true;
      delete drafts[q.number];
      draw();
      var line = lineOf(q.number);
      if (!line) { return; }
      enter(line, line.parts ? 0 : undefined);
      var field = document.activeElement;
      if (field && line.fields.indexOf(field) >= 0 && typeof field.select === "function") { field.select(); }
      onChange();
    }
    function drawDone(q, kind) {
      var open = isOpen(q, true);
      var wrap = make("div", "hd-q hd-done" + (open ? " open" : ""));
      var row = make("div", "hd-qrow");
      var qt = make("div", "hd-qt");
      var tri = make("button", "hd-tri");
      tri.type = "button";
      tri.tabIndex = -1;
      tri.setAttribute("aria-expanded", open ? "true" : "false");
      var num = make("span", "hd-num");
      var letter = make("span", "hd-let", letterOf(q.askedBy));
      var no = make("span", "hd-no", q.number);
      num.appendChild(letter); num.appendChild(no);
      var txt = make("span", "hd-txt", textOf(q.title));
      qt.appendChild(tri); qt.appendChild(num); qt.appendChild(txt);
      qt.addEventListener("click", function () { if (String(window.getSelection ? window.getSelection() : "") !== "") { return; } toggleContext(q); });
      var ans = make("div", "hd-ans wide");
      var tagBox = make("div", "hd-tags");
      ans.appendChild(tagBox);
      var tags = drawTags(q, tagBox);
      var msgs = messagesOf(q);
      var mine = null, theirs = null;
      for (var i = msgs.length - 1; i >= 0; i -= 1) {
        if (!mine && msgs[i].speaker === MINE) { mine = msgs[i]; }
        if (!mine && !theirs && msgs[i].speaker !== MINE) { theirs = msgs[i]; }
      }
      var said = { mine: "", theirs: "", outcome: "" };
      // Answered part by part, his answer is every part's, as one text; else his last words.
      if (mine && textOf(mine.part)) { mine = { speaker: MINE, text: answerOf(q) || textOf(mine.text), holdsDirectionOrInvisibleCharacters: mine.holdsDirectionOrInvisibleCharacters }; }
      if (mine) { var a = drawMessage(mine); a.row.classList.add("rest"); ans.appendChild(a.row); said.mine = textOf(mine.text); }
      else { ans.appendChild(make("div", "hd-msg", "No answer of yours.")); }
      if (theirs) { var t = drawMessage(theirs); t.row.classList.add("brief"); ans.appendChild(t.row); said.theirs = textOf(theirs.text); }
      if (kind === "history") {
        said.outcome = textOf(q.outcome);
        var o = make("div", "hd-msg brief");
        o.appendChild(make("span", "hd-who", "Outcome:"));
        o.appendChild(make("span", "hd-said", said.outcome || "(none recorded)"));
        ans.appendChild(o);
      }
      // CHANGE MY ANSWER: what became of his last change, in plain words; the button while the question is
      // open and answered; and, once it is closed, why there is none.
      var change = changeOf(q, mine !== null && stateOf(q).answered);
      said.change = change.status;
      said.changeLines = change.lines;
      said.button = change.button ? WORDS.change : "";
      said.closed = change.closed;
      change.lines.forEach(function (words) { ans.appendChild(make("div", "hd-change", words)); });
      if (change.closed !== "") { ans.appendChild(make("div", "hd-change hd-closedline", change.closed)); }
      if (change.button) {
        var cb = make("button", "hd-changebtn", WORDS.change);
        cb.type = "button";
        cb.tabIndex = -1;
        cb.addEventListener("click", function (e) { e.stopPropagation(); reopen(q); });
        ans.appendChild(cb);
      }
      row.appendChild(qt); row.appendChild(ans);
      wrap.appendChild(row);
      var subBox = make("div", "hd-sub");
      wrap.appendChild(subBox);
      drawSubs(q, subBox, true);
      var drawn = { q: q, kind: kind, wrap: wrap, row: row, num: no, txt: txt, said: said, tags: tags };
      drawnRows.push(drawn);
      return drawn;
    }

    // THE PAGE, DRAWN AGAIN: headings and their questions, put in place without taking out what stays
    // (update, above). Each heading keeps its element between draws, by its key; its question rows are
    // put in order by moving the others around them, so a field that stays is never taken out of the
    // page - taken out, it would lose the caret and whatever the engine was doing with his keys.
    var headEls = Object.create(null);
    // THE LINE AT THE HEAD OF THE PAGE WHERE HE CHOOSES THE ORDER (header, THE ORDER IS HIS): the two
    // words "Order by" and a button for each order, the chosen one pressed. Its buttons are reached
    // by a press, never by Tab: the run of Enter and Tab is the fields'.
    var orderBar = make("div", "hd-order");
    orderBar.setAttribute("role", "group");
    orderBar.setAttribute("aria-label", "The order of the questions");
    orderBar.appendChild(make("span", "hd-order-lab", "Order by"));
    // Each button is its word and, on the order in force, the arrow after it (THE ORDER TURNS OVER).
    // The arrow is hidden from a screen reader, which is told the direction in words instead.
    var orderArrows = [];
    var orderButtons = ORDERS.map(function (o) {
      var b = make("button", "hd-order-btn", o.label);
      b.type = "button";
      b.tabIndex = -1;
      var arrow = make("span", "hd-order-dir");
      arrow.setAttribute("aria-hidden", "true");
      b.appendChild(arrow);
      orderArrows.push(arrow);
      b.addEventListener("click", function () { pressOrder(o.key); });
      orderBar.appendChild(b);
      return b;
    });
    // ONE BUTTON FOLDS OR UNFOLDS EVERY QUESTION (header, EVERY QUESTION STARTS UNFOLDED), on a short
    // line of its own just under the order line: its word says what a press does, and flips once it
    // is done. NOT ON THE ORDER LINE ITSELF: at a phone's 412 px that line then wrapped to two, and a
    // page scrolled 18 px put the order buttons above the screen (measured 2026-10-14 in
    // decisions/page/test/browser-order.mjs: the tap on Blocking missed).
    var foldLine = make("div", "hd-foldline");
    var foldButton = make("button", "hd-foldall");
    foldButton.type = "button";
    foldButton.tabIndex = -1;
    foldButton.addEventListener("click", function () { setExpanded(!openFirst); });
    // THE SWITCH FOR THE ANSWERED (header, THE ANSWERED ARE HIDDEN UNTIL ASKED FOR), at the head of
    // the same line, across from Collapse all: a switch that says its state in words.
    // THE SWITCH IS REACHED BY KEYS, but never by Tab: as the order's buttons, the run of Enter and Tab
    // is the fields' (a field takes Tab for its own: header, THE KEYS). It stands with the folds
    // instead, above the first of them: Ctrl+Down from a field comes to it when no fold is drawn, and
    // Up from the first fold's heading comes to it. There Space or Enter turns it (a button's own
    // press), Down goes to the first fold, and Shift+Tab or Ctrl+Up back to the list, as from a fold.
    var answeredButton = make("button", "hd-showans");
    answeredButton.type = "button";
    answeredButton.tabIndex = -1;
    answeredButton.setAttribute("role", "switch");
    answeredButton.addEventListener("click", function () { setAnsweredShown(!answeredShown); });
    answeredButton.addEventListener("keydown", function (e) {
      if (e.key === "ArrowDown" && !e.ctrlKey && !e.altKey) {
        e.preventDefault(); e.stopPropagation();
        for (var i = 0; i < drawnHeads.length; i += 1) { if (isFold(drawnHeads[i].head)) { drawnHeads[i].tri.focus(); onChange(); return; } }
      } else if ((e.key === "Tab" && e.shiftKey) || (e.key === "ArrowUp" && e.ctrlKey)) {
        e.preventDefault(); e.stopPropagation();
        var shown = mainLines();
        if (shown.length) { enter(shown[shown.length - 1]); }
      }
    });
    function toSwitch() {
      if (answeredButton.offsetParent === null) { return; }
      answeredButton.focus();
      onChange();
    }
    foldLine.appendChild(answeredButton);
    foldLine.appendChild(foldButton);
    drawFoldButton();
    drawAnsweredButton();
    function drawAnsweredButton() {
      answeredButton.textContent = answeredShown ? ANSWERED_WORDS.on : ANSWERED_WORDS.off;
      answeredButton.setAttribute("aria-checked", answeredShown ? "true" : "false");
      answeredButton.setAttribute("aria-label", answeredShown ? ANSWERED_WORDS.onSays : ANSWERED_WORDS.offSays);
    }
    // The answered shown or hidden: kept on this device, and the page drawn as any redraw is - the
    // question at the top of the view stays where it was (THE VIEW FOLLOWS HIM); the order and what is
    // folded are not touched.
    function setAnsweredShown(on) {
      answeredShown = on === true;
      try { if (prefs) { prefs.setItem(ANSWERED_KEY, answeredShown ? "1" : "0"); } } catch (e) { /* only the remembering is lost */ }
      if (lastJson === null) { drawAnsweredButton(); return; }
      draw();
    }
    function drawFoldButton() {
      foldButton.textContent = openFirst ? FOLD_WORDS.collapse : FOLD_WORDS.expand;
      foldButton.setAttribute("aria-label", openFirst ? FOLD_WORDS.collapseSays : FOLD_WORDS.expandSays);
    }
    // Every question folded (false) or unfolded (true), his choices for single questions dropped, and
    // the page drawn as any redraw is: THE VIEW FOLLOWS HIM keeps the question at the top of the view
    // where it was, and the order is not touched.
    function setExpanded(open) {
      openFirst = open === true;
      unfolded = Object.create(null);
      if (lastJson === null) { drawFoldButton(); return; }
      draw();
    }
    function drawOrderBar() {
      orderButtons.forEach(function (b, i) {
        var o = ORDERS[i];
        var on = o.key === orderKey;
        b.setAttribute("aria-pressed", on ? "true" : "false");
        b.classList.toggle("on", on);
        b.classList.toggle("turned", on && orderTurned);
        orderArrows[i].textContent = on ? " " + (orderTurned ? ARROW_TURNED : ARROW_FIRST) : "";
        b.setAttribute("aria-label", on
          ? "Ordered by " + o.what + ": " + (orderTurned ? o.turned : o.says) + ". Press to put " + (orderTurned ? o.says : o.turned)
          : "Order by " + o.what + ": " + o.says);
      });
    }
    // An order chosen, in its first direction or turned over: drawn at once, and kept for the next
    // time the page is opened here. The order line stays where it was on the screen (header, A PRESS
    // RE-SORTS WHAT HE IS LOOKING AT), so what is under it is the head of the new order.
    function setOrder(key, turned) {
      orderKey = orderOf(key);
      orderTurned = turned === true;
      try { if (prefs) { prefs.setItem(ORDER_KEY, orderKey); prefs.setItem(ORDER_TURN_KEY, orderTurned ? "1" : "0"); } } catch (e) { /* only the remembering is lost */ }
      if (lastJson === null) { drawOrderBar(); return; }
      var barWas = orderBar.parentNode === root ? orderBar.getBoundingClientRect().top : null;
      draw({ keepBar: true });
      if (barWas !== null) {
        var moved = orderBar.getBoundingClientRect().top - barWas;
        if (moved !== 0) { window.scrollBy(0, moved); }
      }
    }
    // A LANE CHOSEN ("" for all of them): drawn at once and kept for the next time. A tap on a card
    // SHOWS that lane's questions: the order line is brought to just under the top of the view, with
    // the head of the lane's questions under it - the cards above can be many screens of a phone, and
    // a list that changed below them unseen would look like a tap that did nothing. The order and
    // what is folded are not touched.
    function setLane(lane) {
      laneChosen = laneWord(lane);
      try { if (prefs) { prefs.setItem(LANE_KEY, laneChosen); } } catch (e) { /* only the remembering is lost */ }
      if (lastJson === null) { onDraw(); return; }
      draw({ keepBar: true, lane: true });
      if (orderBar.parentNode === root) { window.scrollBy(0, orderBar.getBoundingClientRect().top - topInset() - NEAR_TOP_PX); }
    }
    // A question he has still to answer: in his list, and no answer of his stands (the cards' count).
    function toAnswer(q) { return sectionOf(q) === "main" && !stateOf(q).answered; }
    // A press on an order's button: the order in force turns over; another is chosen in its first direction.
    function pressOrder(key) {
      key = orderOf(key);
      setOrder(key, key === orderKey ? !orderTurned : false);
    }
    function order(box, want) {
      var wanted = new Set(want);
      Array.prototype.slice.call(box.childNodes).forEach(function (n) { if (!wanted.has(n)) { box.removeChild(n); } });
      for (var i = 0; i < want.length; i += 1) { if (box.childNodes[i] !== want[i]) { box.insertBefore(want[i], box.childNodes[i] || null); } }
    }
    // how.keepBar: a press on an order - the view is not to follow the question at its top (setOrder).
    function draw(how) {
      var startedAt = window.performance.now();
      var before = (how && how.keepBar === true) ? null : place();
      var had = focusedLine();
      var hadField = had ? document.activeElement : null;
      var caret = had ? { number: had.q.number, part: had.fields.indexOf(hadField), from: hadField.selectionStart, to: hadField.selectionEnd } : null;
      var keep = Object.create(null);
      drawnLines.forEach(function (l) { if (l === had || drafts[l.q.number] !== undefined) { keep[l.q.number] = l; } });
      // A FOLD'S HEADING THAT HAS THE KEYBOARD KEEPS IT: a heading's row is made again on every draw,
      // and a list that arrived while he stood on "With Thrall" took the keyboard from under him
      // (seen 2026-10-12 in the turns scenario: Ctrl+Down, a redraw, and Down went nowhere).
      var headHad = null;
      drawnHeads.forEach(function (h) { if (h.tri === document.activeElement) { headHad = h.head.key; } });
      var heads = sectionsOf();
      drawnHeads = [];
      drawnLines = [];
      drawnRows = [];
      var groups = [];
      var used = Object.create(null);
      heads.forEach(function (head, index) {
        var folded = isFolded(head);
        var fold = isFold(head);
        var el = headEls[head.key];
        if (!el) { el = { group: make("div"), kids: make("div", "hd-kids"), row: null, note: null, tri: null }; el.group.appendChild(el.kids); headEls[head.key] = el; }
        used[head.key] = true;
        el.group.className = "hd-group" + (fold ? " hd-fold" : "") + (folded ? " folded" : "") + (head.note && noteShown[head.key] === true ? " note-open" : "");
        var row = make("div", "hd-row hd-head");
        var tri = make("button", "hd-tri");
        tri.type = "button";
        tri.tabIndex = fold ? 0 : -1;
        tri.setAttribute("aria-expanded", folded ? "false" : "true");
        tri.setAttribute("aria-label", (folded ? "Unfold " : "Fold ") + head.name);
        var howMany = head.qs.length + (head.qs.length === 1 ? " question" : " questions");
        var txt = make("span", "hd-txt", fold ? (head.name + " (" + head.qs.length + ")") : head.name);
        var suf = make("span", "hd-suf");
        if (!fold) { suf.appendChild(make("span", "hd-count", " - " + howMany)); }
        if (fold) {
          // A FOLD IS REACHED BY A KEY OR A CLICK, never by Enter or Tab from a field: Ctrl+Down from
          // a field comes here; Enter, Space or F2 opens or closes it; Up and Down go between folds;
          // Shift+Tab or Ctrl+Up goes back to the list. In an open Parked fold the caret goes into its
          // first field, where Ctrl+B brings a question back.
          tri.addEventListener("keydown", function (e) {
            var folds = drawnHeads.filter(function (h) { return isFold(h.head); });
            var at = -1;
            folds.forEach(function (h, i) { if (h.tri === tri) { at = i; } });
            if (e.key === "Enter" || e.key === " " || e.key === "F2") {
              e.preventDefault(); e.stopPropagation();
              headFolded[head.key] = !isFolded(head);
              draw();
              var mine = drawnLines.filter(function (l) { return l.zone === head.kind && l.field.offsetParent !== null; });
              if (mine.length) { enter(mine[0]); }
              else if (headEls[head.key] && headEls[head.key].tri) { headEls[head.key].tri.focus(); onChange(); }
            } else if ((e.key === "ArrowDown" || e.key === "ArrowUp") && !e.ctrlKey) {
              e.preventDefault(); e.stopPropagation();
              var to = folds[at + (e.key === "ArrowDown" ? 1 : -1)];
              if (to) { to.tri.focus(); onChange(); }
              else if (e.key === "ArrowUp" && at === 0) { toSwitch(); }
            } else if ((e.key === "Tab" && e.shiftKey) || (e.key === "ArrowUp" && e.ctrlKey)) {
              e.preventDefault(); e.stopPropagation();
              var shown = mainLines();
              if (shown.length) { enter(shown[shown.length - 1]); }
            }
          });
        }
        var note = null;
        if (head.note) {
          var more = make("span", "hd-more", " - ");
          var word = make("button", "hd-bg", "background");
          word.type = "button";
          word.tabIndex = -1;
          word.setAttribute("aria-expanded", noteShown[head.key] === true ? "true" : "false");
          word.setAttribute("aria-label", (noteShown[head.key] === true ? "Fold the background of " : "Unfold the background of ") + head.name);
          // The word is in the heading's row, and a click on the row folds the whole group.
          word.addEventListener("click", function (e) {
            e.stopPropagation();
            noteShown[head.key] = noteShown[head.key] !== true;
            draw();
            // Unfolded, the background is brought to the top of the view (THE VIEW FOLLOWS HIM).
            if (noteShown[head.key] === true && headEls[head.key]) { window.scrollBy(0, headEls[head.key].group.getBoundingClientRect().top - topInset() - NEAR_TOP_PX); }
          });
          more.appendChild(word);
          suf.appendChild(more);
          note = make("div", "hd-note", head.note);
        }
        row.appendChild(tri); row.appendChild(txt); row.appendChild(suf);
        row.addEventListener("click", function () { headFolded[head.key] = !isFolded(head); draw(); });
        // The heading's row and note are made again; its rows' box is the one it had.
        if (el.row) { el.group.removeChild(el.row); }
        if (el.note) { el.group.removeChild(el.note); }
        el.group.insertBefore(row, el.kids);
        if (note) { el.group.insertBefore(note, el.kids); }
        el.row = row; el.note = note; el.tri = tri;
        var want = [];
        var zone = (head.kind === "group") ? "main" : head.kind;
        head.qs.forEach(function (q) {
          placedAt[q.number] = head.key;
          if (zone === "thrall" || zone === "history") { want.push(drawDone(q, zone).wrap); return; }
          var line = keep[q.number];
          if (line) { update(line, q); } else { line = drawQuestion(q); }
          line.zone = zone;
          line.head = index;
          line.wrap.classList.toggle("new", zone === "main" && isNew(q));
          drawnLines.push(line);
          want.push(line.wrap);
        });
        order(el.kids, want);
        groups.push(el.group);
        drawnHeads.push({ head: head, txt: txt, tri: tri, folded: folded, group: el.group, note: note });
      });
      Object.keys(headEls).forEach(function (k) { if (!used[k]) { delete headEls[k]; } });
      drawOrderBar();
      drawFoldButton();
      drawAnsweredButton();
      order(root, [orderBar, foldLine].concat(groups));
      // In the page now, so what is folded can be told from what is shown: each line's state again.
      drawnLines.forEach(function (line) { refresh(line); fit(line); });
      if (before) {
        var stood = lineOf(before.number) || rowOf(before.number);
        if (stood) {
          var moved = stood.row.getBoundingClientRect().top - before.top;
          if (moved !== 0) { window.scrollBy(0, moved); }
        }
      }
      if (headHad && headEls[headHad] && headEls[headHad].tri && document.activeElement !== headEls[headHad].tri) { headEls[headHad].tri.focus({ preventScroll: true }); }
      if (caret) {
        var again = lineOf(caret.number);
        var back = again ? (again.fields[caret.part] || again.field) : null;
        if (back && back.offsetParent !== null && document.activeElement !== back) {
          back.focus({ preventScroll: true });
          fit(again);
          try { back.setSelectionRange(Math.min(caret.from, back.value.length), Math.min(caret.to, back.value.length)); } catch (e) { /* not drawn */ }
        }
      }
      timing.draws += 1;
      timing.drawLast = window.performance.now() - startedAt;
      timing.drawMax = Math.max(timing.drawMax, timing.drawLast);
      onDraw();
    }

    function cut(text, most) { text = textOf(text); return text.length > most ? text.slice(0, most) : text; }

    // Is a question's text shortened in any way a style sheet could shorten it? Read from the element.
    function clipped(txt) {
      var style = window.getComputedStyle(txt);
      return style.overflowX !== "visible" || style.overflowY !== "visible" || style.textOverflow !== "clip" || style.whiteSpace === "nowrap" ||
        (style.webkitLineClamp && style.webkitLineClamp !== "none") || style.maxHeight !== "none" ||
        txt.scrollWidth > txt.clientWidth + 1 || txt.scrollHeight > txt.clientHeight + 1;
    }

    function pending() {
      var n = 0;
      Object.keys(sent).forEach(function (k) { n += sent[k].pending; });
      return n;
    }

    // A CHECK'S STEPS, acted out on the page's own fields and nowhere else: a check cannot press a
    // key, so it hands the page these and the page's own handlers do the rest. Each step is
    //   { do: "focus", q, part }  the caret into that question's field (part: into that part's)
    //   { do: "order", key, turned }   that order chosen, in its first direction (turned: true, turned
    //                             over), as setOrder does; { do: "press-order", key } a press on its button
    //   { do: "press-fold" }      a press on the one button that folds or unfolds every question
    //   { do: "lane", lane }      that lane chosen, as a tap on its card does ("" for all)
    //   { do: "follow", q }       a press on that question's "Follows up on question N"
    //   { do: "keyboard" }        the caret taken to the first unanswered field, as doc.takeKeyboard does
    //   { do: "window-focus" }    the event a window given the keyboard sends its page, with no field focused
    //   { do: "blur" }            the caret taken out of whatever has it, and put nowhere
    //   { do: "type", text }      the text typed at the caret
    //   { do: "key", key, shift, ctrl }   that key pressed in the field that has the caret
    //   { do: "settle" }          wait until nothing sent is still unanswered
    //   { do: "sleep", ms }       wait (at most five seconds)
    function drive(steps) {
      var i = 0;
      steps = listOf(steps);
      function settle() {
        return new Promise(function (resolve) {
          var tries = 0;
          (function look() { tries += 1; if (pending() === 0 || tries > 1200) { resolve(); } else { window.setTimeout(look, 50); } }());
        });
      }
      function next() {
        if (i >= steps.length) { return Promise.resolve(i); }
        var step = steps[i] || {};
        i += 1;
        var line = focusedLine();
        var target;
        if (step.do === "focus") {
          // A question folded to Answered, or one of its folded parts, is unfolded, as a press on it does.
          target = lineOf(Number(step.q));
          var part = (typeof step.part === "number") ? step.part : undefined;
          if (target && (part !== undefined ? target.fields[part] && target.fields[part].offsetParent === null : !openFields(target).length)) { unfold(target, part); arrived.at = 0; }
          else if (target) { enter(target, part); arrived.at = 0; }
        }
        else if (step.do === "order") { setOrder(textOf(step.key), step.turned === true); }
        else if (step.do === "press-order") { pressOrder(textOf(step.key)); }
        else if (step.do === "press-fold") { foldButton.click(); }
        else if (step.do === "lane") { setLane(textOf(step.lane)); }
        else if (step.do === "follow") { target = lineOf(Number(step.q)); if (target && target.tags.follow) { target.tags.follow.press.click(); } }
        else if (step.do === "keyboard") { if (document.activeElement && document.activeElement.blur) { document.activeElement.blur(); } takeKeyboard(); arrived.at = 0; }
        else if (step.do === "window-focus") { if (document.activeElement && document.activeElement.blur) { document.activeElement.blur(); } window.dispatchEvent(new Event("focus")); }
        else if (step.do === "blur") { if (document.activeElement && document.activeElement.blur) { document.activeElement.blur(); } onChange(); }
        else if (step.do === "type") { if (line) { insert(line, textOf(step.text), focusedField()); } }
        else if (step.do === "key") {
          (line ? focusedField() : (document.activeElement || document.body)).dispatchEvent(new KeyboardEvent("keydown", { key: textOf(step.key), shiftKey: step.shift === true, ctrlKey: step.ctrl === true, bubbles: true, cancelable: true }));
        }
        else if (step.do === "settle") { return settle().then(next); }
        else if (step.do === "sleep") { return new Promise(function (resolve) { window.setTimeout(resolve, Math.max(0, Math.min(Number(step.ms) || 0, 5000))); }).then(next); }
        return Promise.resolve().then(next);
      }
      return next();
    }

    // The window was given the keyboard and no field has the caret: it goes to the first unanswered.
    // A moment later, and not at all when what brought the keyboard was a press on a heading, a fold
    // mark or a question's words: that press was for them, and the page must not jump away from it.
    var pressed = { at: 0, own: false };
    document.addEventListener("pointerdown", function (e) {
      var t = e.target;
      pressed = { at: Date.now(), own: !!(t && t.closest && t.closest(".hd-qt, .hd-head, button, textarea")) };
    }, true);
    // Nor when a key moved the keyboard in that moment (Ctrl+Down to the switch, then Space): the
    // keyboard is where he sent it, and the field taking it back undid the press (measured 2026-10-16,
    // browser-details.mjs: the switch turned on, and the caret was then in the first field).
    window.addEventListener("focus", function () {
      var had = document.activeElement;
      window.setTimeout(function () {
        if (focusedLine() || (pressed.own && Date.now() - pressed.at < 600)) { return; }
        var now = document.activeElement;
        if (now && now !== had && now !== document.body && now !== document.documentElement) { return; }
        takeKeyboard();
      }, 120);
    });
    // A key pressed with the caret nowhere: the same, and the key is not lost to the page's own Tab order.
    // A key a field has already acted on is not such a key, though the field may have let go of the
    // caret in acting on it (onFrom: the last question of the list, answered).
    document.addEventListener("keydown", function (e) {
      if (e.defaultPrevented || focusedLine() || e.ctrlKey || e.altKey || e.metaKey) { return; }
      var act = document.activeElement;
      if (act && act !== document.body && act !== document.documentElement) { return; }
      if (e.key === "Tab" || e.key === "Enter") { e.preventDefault(); takeKeyboard(); }
      else if (e.key.length === 1) { takeKeyboard(); }
    });
    // HOW MANY KEY PRESSES CAME FROM THE ENGINE ITSELF, and not from a script: a check that says it
    // pressed real keys holds this number against how many it pressed (snapshot, answer.realKeys).
    var realKeys = 0;
    // HOW LONG A KEY TAKES TO SHOW (the owner, 2026-10-07: "it lags on text input"). For each key the
    // engine vouches for: how long it waited before the page saw it (its own time stamp to now), and
    // how long from then until the next frame was drawn. And how long each redraw of the list took.
    // Read back by a check through the snapshot (answer.timing); nothing else uses them.
    var timing = { keys: 0, waitMax: 0, frames: [], draws: 0, drawMax: 0, drawLast: 0, follows: 0, followed: 0 };
    document.addEventListener("keydown", function (e) {
      if (!e.isTrusted) { return; }
      realKeys += 1;
      var seen = window.performance.now();
      timing.keys += 1;
      timing.waitMax = Math.max(timing.waitMax, Math.max(0, seen - e.timeStamp));
      window.requestAnimationFrame(function () { timing.frames.push(window.performance.now() - seen); if (timing.frames.length > 2000) { timing.frames.shift(); } });
    }, true);
    window.addEventListener("resize", function () { drawnLines.forEach(function (line) { fit(line); }); });

    return {
      setKinds: function (record) {
        kinds = Object.create(null);
        var table = (record && record.state === "known" && record.value && record.value.kinds) ? record.value.kinds : null;
        if (table) { Object.keys(table).forEach(function (name) { kinds[name] = table[name]; }); }
        if (lastJson !== null) { draw(); }
      },
      setList: function (record) {
        if (!record || record.state !== "known" || !record.value || !Array.isArray(record.value.questions)) { return "unread"; }
        var json = JSON.stringify(record);
        if (json === lastJson) { return "same"; }
        lastJson = json;
        questions = record.value.questions;
        // A change of rank the list now holds is done (HIS LITTLE BUTTONS), before the list is drawn.
        settleRanks();
        // The first list this page is ever handed: every question in it counts as seen (NEW, above).
        if (seen === null) { loadSeen(); }
        if (seen === null) { seen = Object.create(null); questions.forEach(function (q) { seen[q.number] = true; }); keepSeen(); }
        draw();
        return "drawn";
      },
      setDim: function (fn) {
        dim = (typeof fn === "function") ? fn : null;
        drawnLines.forEach(function (line) { line.wrap.classList.toggle("dim", !!(dim && dim(line.q))); });
        onDraw();
      },
      setParked: function (names) {
        parked = Object.create(null);
        listOf(names).forEach(function (name) { parked[textOf(name)] = true; });
        if (lastJson !== null) { draw(); }
      },
      setUnfolded: function (numbers) {
        listOf(numbers).forEach(function (n) { unfolded[n] = true; });
        draw();
      },
      // A QUESTION THE READER WAS POINTED AT MUST BE IN VIEW (seen 2026-10-07 in a picture of the
      // real window: opened to show question 15 of 22, the window showed 1 to 12). A question wholly
      // in view is left where it is; another is moved to the very top of the view.
      reveal: function (number) {
        var line = lineOf(number);
        if (!line) { return; }
        var box = line.wrap.getBoundingClientRect();
        if (box.height > 0 && (box.top < topInset() || box.bottom > window.innerHeight)) { window.scrollBy(0, box.top - topInset()); }
      },
      // The window's menu (decisions/window): every question, and every heading, unfolded or folded -
      // and the one button says so (openFirst).
      unfoldAll: function () {
        openFirst = true;
        questions.forEach(function (q) { unfolded[q.number] = true; });
        sectionsOf().forEach(function (head) { headFolded[head.key] = false; if (head.note) { noteShown[head.key] = true; } });
        draw();
      },
      foldAll: function () {
        openFirst = false;
        unfolded = Object.create(null);
        headFolded = Object.create(null);
        noteShown = Object.create(null);
        draw();
      },
      takeKeyboard: takeKeyboard,
      // The order chosen, by its key (date, importance or blocks), and whether it is turned over;
      // setOrder(key, turned) chooses one; pressOrder(key) is a press on its button (THE ORDER TURNS OVER).
      order: function () { return orderKey; },
      turned: function () { return orderTurned; },
      setOrder: setOrder,
      pressOrder: pressOrder,
      // Whether the questions are unfolded unless he chose otherwise for one, and choosing it, as the
      // one button does (header, EVERY QUESTION STARTS UNFOLDED).
      expanded: function () { return openFirst; },
      setExpanded: setExpanded,
      // Whether the answered are shown (With Thrall and History), and choosing it, as the switch does
      // (header, THE ANSWERED ARE HIDDEN UNTIL ASKED FOR).
      answeredShown: function () { return answeredShown; },
      setAnsweredShown: setAnsweredShown,
      // THE CARDS' NUMBERS AND THE LANE CHOSEN (decision 74): lanes() is, for each lane with a
      // question he has still to answer, { lane, open, blocksAll }, counted over the whole list
      // whatever lane is chosen; lane() the lane chosen, "" for all; setLane(lane) chooses one ("" or
      // anything that is no lane: all). The host draws the cards (surfaces/pwa/page/decision-cards.js)
      // and reads these again on each onDraw.
      lanes: function () { return lanesOf(questions, toAnswer); },
      lane: function () { return laneChosen; },
      setLane: setLane,
      drive: drive,
      // open, waiting (an Orc waits for it) and other are the list's own. run is how many open
      // questions are in the run of answering (not parked), toAnswer how many of those have no
      // answer of the reader's standing, parked how many open ones are set aside.
      // thrall how many wait on the keeper, history how many are closed, fresh how many are new;
      // toAnswer counts the list as drawn: questions of his turn that hold no answer of his yet.
      // thrall too counts what is drawn, so it reads 0 while the With Thrall fold is hidden (THE
      // ANSWERED ARE HIDDEN UNTIL ASKED FOR); history counts the list, drawn or not.
      counts: function () {
        var open = 0, waiting = 0, other = 0, run = 0, toAnswer = 0, aside = 0, thrall = 0, fresh = 0;
        questions.forEach(function (q) {
          if (textOf(q.state) !== LISTED_STATE) { other += 1; return; }
          open += 1;
          if (listOf(q.waiting).length) { waiting += 1; }
        });
        drawnLines.forEach(function (l) {
          if (l.zone === "parked") { aside += 1; return; }
          if (l.zone !== "main") { return; }
          run += 1;
          if (!stateOf(l.q).answered) { toAnswer += 1; }
          if (l.wrap.classList.contains("new")) { fresh += 1; }
        });
        drawnRows.forEach(function (r) { if (r.kind === "thrall") { thrall += 1; } });
        return { open: open, waiting: waiting, other: other, run: run, toAnswer: toAnswer, parked: aside, thrall: thrall, history: other, fresh: fresh };
      },
      // WHAT IS DRAWN, from the elements themselves and not from the data they were made of:
      //   headings  [{ t, count, folded, note }]  note is "" for a group with no note of background,
      //                                           "folded" or "shown" for one that has it
      //   lines     [{ n, l, t, s, g, open, dim,  n the number as text drawn, l the letter before it,
      //                rows, clip,                t the question's text, rows how many lines it takes,
      //                a, p, m, more, r, fh,      clip whether anything shortens it; a what stands in
      //                th }]                      the answer's field, p its grey suggestion, m its
      //                                           mark in full words, more what the mark says of a
      //                                           resting answer's further lines, r the refusal
      //                                           under it, fh the field's height in lines as it
      //                                           stands, th what was said before, in full, brief
      //                                           how many of those are drawn as one line. s is the
      //                                           suffix a folded line once carried: always "" now.
      //   sub       [{ n, t }]                    the sub-numbered lines of the unfolded questions
      //   answer    { fields, focus, pending,     how many fields can be typed in with no click, the
      //               drafts, storage,            number of the question whose field has the caret
      //               realKeys, hasFocus }        ("" for none), how many sends are unanswered, how
      //                                           many drafts are kept, what is wrong with keeping
      //                                           them, how many key presses came from the engine
      //                                           and not from a script, and whether the page has
      //                                           the keyboard
      //   left      { lines, sub }                how many were left out by the caller's limits
      // limits is { lines, subLines, lineChars }: the most of each, and the most characters of a text.
      snapshot: function (limits) {
        // order: the order chosen, by its key, whether it is turned over, the word on the button drawn
        // as pressed (its word alone: the arrow is arrow), and what that button says to a screen reader.
        var pressedAt = orderButtons.filter(function (b) { return b.getAttribute("aria-pressed") === "true"; }).map(function (b) { return orderButtons.indexOf(b); });
        var out = { headings: [], lines: [], sub: [], left: { lines: 0, sub: 0 }, lane: laneChosen, fold: { expanded: openFirst, word: foldButton.textContent, says: foldButton.getAttribute("aria-label") }, order: { key: orderKey, turned: orderTurned, pressed: pressedAt.map(function (i) { return ORDERS[i].label; }).join(","), arrow: pressedAt.map(function (i) { return orderArrows[i].textContent.trim(); }).join(","), says: pressedAt.map(function (i) { return orderButtons[i].getAttribute("aria-label"); }).join(","), shown: orderBar.parentNode === root, words: ORDERS.map(function (o) { return o.label; }) } };
        var linePx = drawnLines.length ? (parseFloat(window.getComputedStyle(drawnLines[0].txt).lineHeight) || 22) : 22;
        drawnHeads.forEach(function (h) { out.headings.push({ t: cut(h.txt.textContent, limits.lineChars), count: h.head.qs.length, folded: h.folded, parked: h.head.kind === "parked", kind: h.head.kind, note: !h.note ? "" : (h.group.classList.contains("note-open") ? "shown" : "folded") }); });
        drawnLines.forEach(function (line) {
          if (out.lines.length >= limits.lines) { out.left.lines += 1; return; }
          out.lines.push({
            n: line.num.textContent, l: line.letter.textContent, t: cut(line.txt.textContent, limits.lineChars), s: "", g: line.head,
            z: textOf(line.zone), nw: line.wrap.classList.contains("new"),
            // b the plain words that stand out about it, as drawn; fu the question it follows: its
            // line's words, whether it is unfolded, and what is unfolded; gn whether its saved words
            // stand green; ad whether it is folded to the one word Answered (and that word, as drawn);
            // pm each part's mark, pg and pd which parts stand green and which are folded, pt what a
            // folded part shows, pr each part's refusal.
            b: line.tags.badges.map(function (el) { return cut(el.textContent, limits.lineChars); }),
            fu: line.tags.follow ? { t: cut(line.tags.follow.press.textContent, limits.lineChars), open: !line.tags.follow.more.hidden, more: cut(line.tags.follow.more.textContent, limits.lineChars) } : null,
            gn: line.wrap.classList.contains("saved-now"), ad: line.wrap.classList.contains("answered") ? cut(line.done.textContent, limits.lineChars) : "",
            pm: line.rows.map(function (r) { return cut(r.mark.textContent, limits.lineChars); }),
            pg: line.rows.map(function (r) { return r.el.classList.contains("saved-now"); }),
            pd: line.rows.map(function (r) { return r.el.classList.contains("answered"); }),
            pt: line.rows.map(function (r) { return cut(r.done.textContent, limits.lineChars); }),
            pr: line.rows.map(function (r) { return cut(r.refusal.textContent, limits.lineChars); }),
            open: line.wrap.classList.contains("open"), dim: line.wrap.classList.contains("dim"),
            rows: Math.round(line.txt.getBoundingClientRect().height / linePx), clip: clipped(line.txt),
            a: cut(lineValue(line), limits.lineChars), p: cut(line.field.placeholder, limits.lineChars),
            pa: line.parts ? line.fields.map(function (f) { return cut(f.value, limits.lineChars); }) : [],
            pp: line.parts ? line.fields.map(function (f) { return cut(f.placeholder, limits.lineChars); }) : [], m: cut(line.markFull.textContent + (line.markNote.textContent ? " (" + line.markNote.textContent + ")" : ""), limits.lineChars), more: cut(line.more.textContent, limits.lineChars),
            r: cut(line.refusal.textContent, limits.lineChars), fh: Math.round(line.field.getBoundingClientRect().height / linePx),
            th: line.said.slice(0, 8).map(function (s) { return cut(s.who + ": " + s.said.textContent, limits.lineChars); }),
            brief: line.said.filter(function (s) { return s.row.classList.contains("brief"); }).length
          });
          line.subs.forEach(function (sub) {
            if (out.sub.length >= limits.subLines) { out.left.sub += 1; return; }
            out.sub.push({ n: sub.num.textContent, t: cut((sub.label ? sub.label + ": " : "") + sub.txt.textContent, limits.lineChars) });
          });
        });
        // The rows that are only read (With the keeper, History): number, text, which fold, and what
        // they show of his answer, the keeper's last words and the outcome.
        out.done = drawnRows.slice(0, limits.lines).map(function (r) {
          return { n: r.num.textContent, t: cut(r.txt.textContent, limits.lineChars), k: r.kind, a: cut(r.said.mine, limits.lineChars), r: cut(r.said.theirs, limits.lineChars), o: cut(r.said.outcome, limits.lineChars), b: r.tags.badges.map(function (el) { return cut(el.textContent, limits.lineChars); }), cs: textOf(r.said.change), cl: (r.said.changeLines || []).map(function (s) { return cut(s, limits.lineChars); }), cb: textOf(r.said.button), cx: cut(r.said.closed, limits.lineChars) };
        });
        out.toast = (toast && !toast.hidden) ? cut(toast.textContent, limits.lineChars) : "";
        var has = focusedLine();
        var onHead = "";
        drawnHeads.forEach(function (h) { if (h.tri === document.activeElement) { onHead = h.txt.textContent; } });
        var frames = timing.frames.slice().sort(function (a, b) { return a - b; });
        var at = function (share) { return frames.length ? Math.round(frames[Math.min(frames.length - 1, Math.floor(share * frames.length))]) : 0; };
        // Where the question with the caret stands in the view, in CSS pixels below the top of the view
        // (under what the host keeps fixed), and how far the caret's field reaches: THE VIEW FOLLOWS HIM.
        var view = null;
        if (has) {
          var wbox = has.wrap.getBoundingClientRect();
          var fbox = document.activeElement.getBoundingClientRect();
          view = { top: Math.round(wbox.top - topInset()), fieldBottom: Math.round(fbox.bottom), height: Math.round(window.innerHeight), scrolled: Math.round(window.scrollY), page: Math.round(document.documentElement.scrollHeight) };
        }
        out.answer = { view: view, fields: shownLines().length, focus: has ? String(has.q.number) : "", focusPart: has && has.parts ? has.fields.indexOf(document.activeElement) : -1, focusHead: cut(onHead, limits.lineChars), pending: pending(), drafts: Object.keys(drafts).length, storage: storageProblem, realKeys: realKeys, hasFocus: document.hasFocus(),
          timing: { keys: timing.keys, waitMaxMs: Math.round(timing.waitMax), frameP50Ms: at(0.5), frameP95Ms: at(0.95), frameMaxMs: frames.length ? Math.round(frames[frames.length - 1]) : 0, draws: timing.draws, drawMaxMs: Math.round(timing.drawMax), drawLastMs: Math.round(timing.drawLast), follows: timing.follows, followed: timing.followed } };
        return out;
      },
      measure: function () {
        if (!drawnLines.length) { return null; }
        var style = window.getComputedStyle(drawnLines[0].txt);
        return { fontPx: parseFloat(style.fontSize), linePx: parseFloat(style.lineHeight), weight: style.fontWeight };
      }
    };
  }

  // order: the one sorting of questions, for a check that holds it without a page (inOrder(list, key,
  // turned), and the orders there are).
  // lanes: the lane a question is of, and the cards' numbers for a list and a test of "still to answer"
  // (lanesOf), for a check that holds them without a page.
  window.HordeDecisionsDocument = { mount: mount, order: { orders: ORDERS.map(function (o) { return o.key; }), inOrder: inOrder }, lanes: { keeper: KEEPER_LANE, laneOf: laneOf, lanesOf: lanesOf } };
}());
