// decisions/page/list.js - the list of questions drawn as a document the reader ANSWERS IN: group
// headings, and under each one line per question - the letter of who asked and the question's
// permanent number, the question in full, and a field for the answer that is always there.
//
// ITS JOB is to draw what the decisions operations answered (decisions/Operations.ps1: kinds, and
// list with each conversation in it), exactly as it was handed over, and to hand the reader's words
// to its host to be said (options.say). It knows no bridge and no fleet, and it never decides whether
// words were saved: the host answers that, and until it has, the words are a draft this page keeps.
//
//   var doc = HordeDecisionsDocument.mount(element, { topInset, onDraw, onChange, say, storage });
//     say(number, text, wording, id)  ->  a promise of { ok: true, sequence, ... } or { ok: false, reason }
//     storage                             where drafts are kept (default: this page's own localStorage)
//   doc.setKinds(record)     the answer of the kinds operation, as { state, value, reason }
//   doc.setList(record)      the answer of the list operation; says what it did: "drawn", "same"
//                            (the very answer already drawn: nothing is touched) or "unread" (the
//                            answer is not a list: what was drawn stays, and the caller says why)
//   doc.setDim(fnOrNull)     fn(question) is true for a question to draw dimmed. DIMMED, NEVER HIDDEN
//   doc.setParked(names)     the groups kept folded at the foot of the page, out of the run of answering
//   doc.setUnfolded(numbers) these questions' context unfolded as well; doc.unfoldAll(); doc.foldAll()
//   doc.reveal(number)       that question brought into view, if it is not wholly in it already
//   doc.takeKeyboard()       the caret into the first unanswered question's field
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
// A REDRAW KEEPS THE READER'S PLACE: what is unfolded stays unfolded, the line at the top of the view
// stays where it is, and the caret stays in its field at its place in the words.
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
    toldShort: "told", readShort: "read", edited: "edited", earlier: "You, earlier", isNew: "new",
    afterClosing: "the question is closed; kept, and it reopens nothing", earlierWording: "said to an earlier wording",
    marks: "this message holds direction or invisible characters"
  };
  var DRAFTS_KEY = "horde-decisions-drafts-v1";
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
  // Tab go from part to part; the answer is sent ONCE, when the last part is left (or on Ctrl+Enter),
  // as one message with a line per part, "(a) ...", so that the keeper reads it whole. The store keeps
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
      var letter = mark ? mark[1] : String.fromCharCode(97 + i);
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

  function mount(root, options) {
    options = options || {};
    // Where the view begins: below whatever the host keeps fixed at the top, which only the host knows.
    var topInset = (typeof options.topInset === "function") ? options.topInset : function () { return 0; };
    var onDraw = (typeof options.onDraw === "function") ? options.onDraw : function () {};
    var onChange = (typeof options.onChange === "function") ? options.onChange : function () {};
    var say = (typeof options.say === "function") ? options.say : function () { return Promise.resolve({ ok: false, reason: "Not saved: this page has nobody to hand the words to." }); };
    // act(number, "park" or "unpark", wording, id): his act, recorded; answered as say is.
    var act = (typeof options.act === "function") ? options.act : function () { return Promise.resolve({ ok: false, reason: "this page has nobody to record it with." }); };
    var storage = options.storage || null;
    if (!storage) { try { storage = window.localStorage; } catch (e) { storage = null; } }
    var kinds = Object.create(null);
    var questions = [];
    var lastJson = null;
    var dim = null;
    // Keyed by a question's number and by a heading's key: maps with no prototype (header).
    var unfolded = Object.create(null);
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

    function sentOf(number) {
      if (!sent[number]) { sent[number] = { sentText: null, sentId: null, pending: 0, refusal: "", saved: null }; }
      return sent[number];
    }
    function allMessagesOf(q) { return (q.thread && Array.isArray(q.thread.messages)) ? q.thread.messages : []; }
    // WHAT WAS SAID, his acts left out (park and unpark are records of what he did, not words; the
    // operation say keeps them so that the keeper sees them - decisions/Rules.ps1, TRIAL).
    function messagesOf(q) { return allMessagesOf(q).filter(function (m) { return !textOf(m.act); }); }
    // His last act under the question: "park", "unpark" or "" - and what he did here since, not yet in
    // a list (acted, below).
    var acted = Object.create(null);
    function lastActOf(q) {
      var all = allMessagesOf(q);
      var mine = acted[q.number];
      // What he did here and the list does not hold yet (its record is not in it, or not yet known).
      if (mine && !all.some(function (m) { return Number(m.sequence) >= mine.sequence; })) { return mine.act; }
      for (var i = all.length - 1; i >= 0; i -= 1) { if (textOf(all[i].act)) { return textOf(all[i].act); } }
      return "";
    }
    // THE ANSWER THAT STANDS: the reader's own message when it is the last thing said under the
    // question; or what the host has just answered is saved, until a list arrives that holds it.
    function standingOf(q) {
      var msgs = messagesOf(q);
      var s = sent[q.number];
      if (s && s.saved) {
        var caught = allMessagesOf(q).some(function (m) { return Number(m.sequence) >= s.saved.sequence; });
        if (caught) { s.saved = null; } else { return s.saved; }
      }
      var last = msgs.length ? msgs[msgs.length - 1] : null;
      return (last && last.speaker === MINE) ? last : null;
    }
    // What stands above the field: everything said before the standing answer. AN ANSWER HE REPLACED
    // (an edit: his words straight after his own) stays, as one line marked "earlier", folded with the
    // question's context (the owner, 2026-10-07: the earlier one kept under a fold).
    function earlierOf(q) {
      var msgs = messagesOf(q);
      var standing = standingOf(q);
      var out = [];
      for (var i = 0; i < msgs.length; i += 1) {
        if (standing && msgs[i] === standing) { continue; }
        out.push(msgs[i]);
      }
      return out;
    }
    function replacedLater(q, m) {
      var msgs = messagesOf(q);
      var at = msgs.indexOf(m);
      if (m.speaker !== MINE) { return false; }
      if (at >= 0 && at + 1 < msgs.length) { return msgs[at + 1].speaker === MINE; }
      var standing = standingOf(q);
      return at === msgs.length - 1 && !!standing && standing !== m;
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
    // moved out of the list"; "new questions should appear at the top"). THE LIST IS HIS TURN:
    //   main     open, not set aside, and either never answered, or the keeper has said something to
    //            him that asks since his last answer. And his answer, saved, stays where it is - marked
    //            saved, still his to change - until the keeper has READ it; the next list after the
    //            keeper's read mark passes it moves it out.
    //   thrall   answered and read, or told something that asks nothing (a note), not closed: the
    //            keeper's turn. Back up by itself when the keeper asks him something.
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
      var standing = standingOf(q);
      if (standing) { return (Array.isArray(standing.unreadBy) && standing.unreadBy.length === 0) ? "thrall" : "main"; }
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
    function isNew(q) { return !!seen && !seen[q.number] && !standingOf(q); }

    function sectionsOf() {
      var heads = [];
      var byKey = Object.create(null);
      var folds = { thrall: [], parked: [], history: [] };
      var groupsInOrder = [];
      function head(key, kind, name) {
        if (!byKey[key]) { byKey[key] = { key: key, kind: kind, name: name, note: "", qs: [] }; if (kind === "group") { groupsInOrder.push(byKey[key]); } }
        return byKey[key];
      }
      var fresh = [];
      questions.forEach(function (q) {
        var section = sectionOf(q);
        var keyWas = placedAt[q.number];
        if (keyWas && held(q)) {
          var wasFold = keyWas.indexOf("fold:") === 0 ? keyWas.slice(5) : "main";
          if (wasFold !== section) { section = wasFold; }
        }
        if (section !== "main") { folds[section].push(q); return; }
        var stays = !!keyWas && held(q) && keyWas.indexOf("fold:") !== 0;
        if ((stays && keyWas === "new") || (!stays && isNew(q))) { fresh.push(q); return; }
        var h = head("group:" + textOf(q.group), "group", textOf(q.group) || "No group");
        if (!h.note && textOf(q.groupNote)) { h.note = textOf(q.groupNote); }
        h.qs.push(q);
      });
      if (fresh.length) { heads.push({ key: "new", kind: "new", name: "New", note: "", qs: fresh.sort(function (a, b) { return b.number - a.number; }) }); }
      heads = heads.concat(groupsInOrder);
      var foldNames = { thrall: "With " + KEEPER, parked: "Parked", history: "History" };
      folds.history.sort(function (a, b) { return textOf(b.closedAt).localeCompare(textOf(a.closedAt)) || (b.number - a.number); });
      FOLDS.forEach(function (f) { if (folds[f].length) { heads.push({ key: "fold:" + f, kind: f, name: foldNames[f], note: "", qs: folds[f] }); } });
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
    function shownLines() { return drawnLines.filter(function (line) { return line.field.offsetParent !== null; }); }
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
      if (field.offsetParent === null) { return; }
      var linePx = parseFloat(window.getComputedStyle(field).lineHeight) || 22;
      var empty = field.value === "" && field.placeholder !== "";
      if (empty) { field.value = field.placeholder; }
      field.style.height = "auto";
      var lines = Math.max(1, Math.round(field.scrollHeight / linePx));
      if (empty) { field.value = ""; }
      var standing = standingOf(line.q);
      var resting = document.activeElement !== field && !!standing && field.value === textOf(standing.text);
      var shown = (resting && lines > REST_LINES) ? REST_LINES : lines;
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

    function refresh(line) {
      // The mark and the refusal of one line, from what is known now. No redraw.
      var s = sent[line.q.number];
      var mark = markOf(line.q, lineValue(line));
      line.markFull.textContent = mark.full;
      line.markShort.textContent = mark.short;
      line.mark.hidden = mark.full === "";
      line.markNote.textContent = mark.note;
      line.markNote.hidden = mark.note === "";
      line.refusal.textContent = (s && s.refusal) ? s.refusal : "";
      line.refusal.hidden = !(s && s.refusal);
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
    function keepInView(field) {
      if (!field || field.offsetParent === null) { return; }
      var box = field.getBoundingClientRect();
      timing.follows += 1;
      if (box.bottom > window.innerHeight) { window.scrollBy(0, box.bottom - window.innerHeight + 8); timing.followed += 1; }
      else if (box.top < topInset()) { window.scrollBy(0, box.top - topInset() - NEAR_TOP_PX); }
    }
    function enter(line, part) {
      var field = line.fields[Math.max(0, Math.min(line.fields.length - 1, part === undefined ? 0 : (part < 0 ? line.fields.length + part : part)))];
      var sameQuestion = focusedLine() === line;
      field.focus({ preventScroll: true });
      var end = field.value.length;
      try { field.setSelectionRange(end, end); } catch (e) { /* a field not drawn has no caret */ }
      arrived = { number: line.q.number, at: Date.now(), bySave: false };
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
    function mainLines() { return shownLines().filter(function (l) { return l.zone === "main"; }); }
    function takeKeyboard() {
      var shown = mainLines();
      var first = null;
      for (var i = 0; i < shown.length; i += 1) {
        if (!standingOf(shown[i].q)) { first = shown[i]; break; }
      }
      if (!first && shown.length) { first = shown[0]; }
      if (first) { enter(first); }
    }

    function typed(line) {
      // What stands in the field now: a draft unless it is the standing answer, word for word.
      var q = line.q;
      var value = lineValue(line);
      var standing = standingOf(q);
      if (value === (standing ? textOf(standing.text) : "")) { delete drafts[q.number]; } else { drafts[q.number] = value; }
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

    function answered(number, id, text, result) {
      var s = sentOf(number);
      s.pending -= 1;
      var line = lineOf(number);
      if (result && result.ok === true) {
        s.saved = { text: text, sequence: Number(result.sequence), speaker: MINE, arrivedAfterClosing: result.arrivedAfterClosing === true, saidToEarlierWording: result.saidToEarlierWording === true, replaces: s.replacing === true };
        if (s.sentId === id) { s.refusal = ""; }
        // The draft is dropped only if it is still these very words.
        if (drafts[number] === text) { delete drafts[number]; keepDrafts(); }
      } else if (s.sentId === id) {
        s.refusal = textOf(result && result.reason) || "Not saved, and no reason was given.";
        // BACK TO THE WORDS THAT WERE NOT SAVED, unless the reader is typing somewhere else.
        var now = focusedLine();
        if (line && now !== line && (!now || lineValue(now) === "" || drafts[now.q.number] === undefined)) { enter(line); }
      }
      // What was said above the field may have changed with it: an answer he replaced is now kept
      // there, marked earlier (an edit).
      if (line && result && result.ok === true) { line.said = drawTalk(line.q, line.talk, line.ans); }
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
        function (result) { answered(number, id, text, result); },
        function (error) { answered(number, id, text, { ok: false, reason: "Not saved: " + ((error && error.message) ? error.message : error) }); });
      return true;
    }

    // THE BACK BURNER BY HIS OWN KEY (the owner, 2026-10-07: "there should be an ability to put a
    // question on the back burner"). Ctrl+B on a question of the list parks it: it goes to the Parked
    // fold, the caret goes on, and a short line offers Ctrl+Z to undo for UNDO_MS. Ctrl+B on a question
    // in the Parked fold brings it back. Each is HIS OWN ACT, recorded through the operation say with
    // act park or unpark (decisions/Rules.ps1, TRIAL), so that the keeper sees it; the question's group
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
    function toFolds() {
      for (var i = 0; i < drawnHeads.length; i += 1) { if (isFold(drawnHeads[i].head)) { drawnHeads[i].tri.focus(); onChange(); return; } }
    }

    function toggleContext(q) {
      var opening = unfolded[q.number] !== true;
      if (opening) { unfolded[q.number] = true; } else { delete unfolded[q.number]; }
      draw();
      // Unfolded, the question goes to the top of the view, so that the most of its context shows.
      var line = lineOf(q.number) || rowOf(q.number);
      if (opening && line) { toTop(line); }
    }

    // THE KEYS IN A PART'S FIELD (header, A QUESTION OF SEVERAL PARTS): Enter and Tab go to the next
    // part, and from the last part they send the whole answer once and go to the next question;
    // Shift+Tab goes back a part. A Tab on an empty part with a suggestion fills it and stays; a Tab
    // on a part of one character moves on. Ctrl+Enter in an empty part takes its suggestion; on the
    // first part with every part empty it takes every part's; then the answer is sent and the caret
    // goes to the next question.
    function onPartKey(e, line, field) {
      var at = fieldIndex(line, field);
      var last = at === line.fields.length - 1;
      var key = e.key;
      var plain = !e.ctrlKey && !e.altKey && !e.metaKey;
      var rec = line.parts[at].rec;
      var leave = function () { var sentNow = save(line); move(line, 1); if (sentNow) { arrived.bySave = true; } };
      if (key === "Enter" && e.ctrlKey) {
        e.preventDefault();
        var allEmpty = line.fields.every(function (f) { return f.value.trim() === ""; });
        if (at === 0 && allEmpty) { line.fields.forEach(function (f, i) { if (line.parts[i].rec) { f.value = line.parts[i].rec; } }); typed(line); }
        else if (field.value.trim() === "" && rec) { setValue(line, rec, field); }
        leave();
        return true;
      }
      if (key === "Enter" && plain && !e.shiftKey) {
        e.preventDefault();
        if (last) { leave(); } else { enter(line, at + 1); }
        return true;
      }
      if (key === "Tab" && e.shiftKey) { e.preventDefault(); if (at > 0) { enter(line, at - 1); } else { move(line, -1); } return true; }
      if (key === "Tab" && plain) {
        e.preventDefault();
        if (field.value === "" && rec) { setValue(line, rec, field); return true; }
        if (!last) { enter(line, at + 1); return true; }
        if (field.value.trim().length === 1) { move(line, 1); return true; }
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
        var accepted = save(line);
        move(line, 1);
        if (accepted) { arrived.bySave = true; }
        return;
      }
      if (key === "Enter" && plain) {
        e.preventDefault();
        if (field.value === "" && arrived.number === q.number && Date.now() - arrived.at < (arrived.bySave ? SAVE_ECHO_MS : ARRIVAL_MS)) { return; }
        var sentNow = save(line);
        move(line, 1);
        if (sentNow) { arrived.bySave = true; }
        return;
      }
      if (key === "Tab" && e.shiftKey) { e.preventDefault(); move(line, -1); return; }
      if (key === "Tab" && plain) {
        e.preventDefault();
        if (field.value === "" && rec) { setValue(line, rec); return; }
        // ONE CHARACTER IS NOT AN ANSWER TO SEND ON A TAB (the owner's question 28, 2026-10-07: he
        // began "a ..." and a Tab stored the answer "a"). It stays, a draft, and the caret moves on.
        if (field.value.trim().length === 1) { move(line, 1); return; }
        var tabbed = save(line);
        move(line, 1);
        if (tabbed) { arrived.bySave = true; }
        return;
      }
      if (key === "ArrowRight" && plain && !e.shiftKey && field.value === "" && rec) { e.preventDefault(); setValue(line, rec); return; }
      if (key === "F2" || ((key === " " || e.code === "Space") && e.ctrlKey)) { e.preventDefault(); toggleContext(q); }
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
      var answered = !!standingOf(q);
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
    // The context of an unfolded question, its sub-numbered lines, into -box (emptied first).
    function drawSubs(q, box) {
      while (box.firstChild) { box.removeChild(box.firstChild); }
      var subs = [];
      box.hidden = unfolded[q.number] !== true;
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
      var open = unfolded[q.number] === true;
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
      var talk = make("div", "hd-talk");
      ans.appendChild(talk);
      var said = drawTalk(q, talk, ans);
      var info = partsOf(q);
      var fl = make("div", "hd-fl");
      var mark = make("span", "hd-mark");
      var markFull = make("span", "hd-mark-full");
      var markShort = make("span", "hd-mark-short");
      var more = make("span", "hd-mark-more");
      mark.appendChild(markFull); mark.appendChild(markShort); mark.appendChild(more);
      var fields = [];
      var field;
      if (info) {
        // A field per part (header, A QUESTION OF SEVERAL PARTS), across the whole row.
        var values = readParts(valueOf(q), info.parts);
        if (!values) { values = info.parts.map(function () { return ""; }); }
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
          prow.appendChild(label); prow.appendChild(pf);
          box.appendChild(prow);
          fields.push(pf);
        });
        fl.appendChild(box); fl.appendChild(mark);
        fl.classList.add("parts");
        field = fields[0];
      } else {
        field = make("textarea", "hd-field");
        field.rows = 1;
        field.setAttribute("dir", "auto");
        field.setAttribute("aria-label", "Your answer to question " + q.number);
        field.spellcheck = false;
        field.placeholder = recOf(q);
        field.value = valueOf(q);
        fields.push(field);
        fl.appendChild(field); fl.appendChild(mark);
      }
      var markNote = make("div", "hd-marknote");
      markNote.hidden = true;
      var refusal = make("div", "hd-refusal");
      refusal.hidden = true;
      ans.appendChild(fl); ans.appendChild(markNote); ans.appendChild(refusal);
      row.appendChild(qt); row.appendChild(ans);
      wrap.appendChild(row);
      var subBox = make("div", "hd-sub");
      wrap.appendChild(subBox);
      var subs = drawSubs(q, subBox);
      var drawn = { q: q, wrap: wrap, row: row, tri: tri, num: no, letter: letter, txt: txt, ans: ans, talk: talk, subBox: subBox, field: field, fields: fields, parts: info ? info.parts : null, mark: mark, markFull: markFull, markShort: markShort, more: more, markNote: markNote, refusal: refusal, said: said, subs: subs };
      fields.forEach(function (f) {
        f.addEventListener("input", function () { typed(drawn); });
        f.addEventListener("keydown", function (e) { onKey(e, drawn, f); });
        // The caret in it, an answer is whole; the caret gone, a saved one rests again. A question
        // the caret has been in and left has been passed: it is no longer new.
        f.addEventListener("focus", function () { fit(drawn); onChange(); });
        f.addEventListener("blur", function () { fit(drawn); if (focusedLine() !== drawn) { markSeen(drawn.q.number); } onChange(); });
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
      var open = unfolded[q.number] === true;
      line.wrap.classList.toggle("open", open);
      line.wrap.classList.toggle("dim", !!(dim && dim(q)));
      line.tri.setAttribute("aria-expanded", open ? "true" : "false");
      line.said = drawTalk(q, line.talk, line.ans);
      line.subs = drawSubs(q, line.subBox);
      refresh(line);
    }

    // A ROW THAT IS ONLY READ (header, WHERE A QUESTION STANDS): a question with the keeper, or closed.
    // Its words, then his last answer (two lines at most) and the keeper's last words after it, or the
    // outcome it was closed with. A press on it unfolds its context.
    var drawnRows = [];
    function rowOf(number) { for (var i = 0; i < drawnRows.length; i += 1) { if (drawnRows[i].q.number === number) { return drawnRows[i]; } } return null; }
    function drawDone(q, kind) {
      var open = unfolded[q.number] === true;
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
      var msgs = messagesOf(q);
      var mine = null, theirs = null;
      for (var i = msgs.length - 1; i >= 0; i -= 1) {
        if (!mine && msgs[i].speaker === MINE) { mine = msgs[i]; }
        if (!mine && !theirs && msgs[i].speaker !== MINE) { theirs = msgs[i]; }
      }
      var said = { mine: "", theirs: "", outcome: "" };
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
      row.appendChild(qt); row.appendChild(ans);
      wrap.appendChild(row);
      var subBox = make("div", "hd-sub");
      wrap.appendChild(subBox);
      drawSubs(q, subBox);
      var drawn = { q: q, kind: kind, wrap: wrap, row: row, num: no, txt: txt, said: said };
      drawnRows.push(drawn);
      return drawn;
    }

    // THE PAGE, DRAWN AGAIN: headings and their questions, put in place without taking out what stays
    // (update, above). Each heading keeps its element between draws, by its key; its question rows are
    // put in order by moving the others around them, so a field that stays is never taken out of the
    // page - taken out, it would lose the caret and whatever the engine was doing with his keys.
    var headEls = Object.create(null);
    function order(box, want) {
      var wanted = new Set(want);
      Array.prototype.slice.call(box.childNodes).forEach(function (n) { if (!wanted.has(n)) { box.removeChild(n); } });
      for (var i = 0; i < want.length; i += 1) { if (box.childNodes[i] !== want[i]) { box.insertBefore(want[i], box.childNodes[i] || null); } }
    }
    function draw() {
      var startedAt = window.performance.now();
      var before = place();
      var had = focusedLine();
      var hadField = had ? document.activeElement : null;
      var caret = had ? { number: had.q.number, part: had.fields.indexOf(hadField), from: hadField.selectionStart, to: hadField.selectionEnd } : null;
      var keep = Object.create(null);
      drawnLines.forEach(function (l) { if (l === had || drafts[l.q.number] !== undefined) { keep[l.q.number] = l; } });
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
        var zone = (head.kind === "new" || head.kind === "group") ? "main" : head.kind;
        head.qs.forEach(function (q) {
          placedAt[q.number] = head.key;
          if (zone === "thrall" || zone === "history") { want.push(drawDone(q, zone).wrap); return; }
          var line = keep[q.number];
          if (line) { update(line, q); } else { line = drawQuestion(q); }
          line.zone = zone;
          line.head = index;
          line.wrap.classList.toggle("new", head.kind === "new");
          drawnLines.push(line);
          want.push(line.wrap);
        });
        order(el.kids, want);
        groups.push(el.group);
        drawnHeads.push({ head: head, txt: txt, tri: tri, folded: folded, group: el.group, note: note });
      });
      Object.keys(headEls).forEach(function (k) { if (!used[k]) { delete headEls[k]; } });
      order(root, groups);
      drawnLines.forEach(function (line) { fit(line); });
      if (before) {
        var stood = lineOf(before.number) || rowOf(before.number);
        if (stood) {
          var moved = stood.row.getBoundingClientRect().top - before.top;
          if (moved !== 0) { window.scrollBy(0, moved); }
        }
      }
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
    //   { do: "focus", q }        the caret into that question's field
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
        if (step.do === "focus") { target = lineOf(Number(step.q)); if (target) { enter(target); arrived.at = 0; } }
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
    window.addEventListener("focus", function () {
      window.setTimeout(function () {
        if (focusedLine() || (pressed.own && Date.now() - pressed.at < 600)) { return; }
        takeKeyboard();
      }, 120);
    });
    // A key pressed with the caret nowhere: the same, and the key is not lost to the page's own Tab order.
    document.addEventListener("keydown", function (e) {
      if (focusedLine() || e.ctrlKey || e.altKey || e.metaKey) { return; }
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
      unfoldAll: function () {
        questions.forEach(function (q) { unfolded[q.number] = true; });
        sectionsOf().forEach(function (head) { headFolded[head.key] = false; if (head.note) { noteShown[head.key] = true; } });
        draw();
      },
      foldAll: function () {
        unfolded = Object.create(null);
        headFolded = Object.create(null);
        noteShown = Object.create(null);
        draw();
      },
      takeKeyboard: takeKeyboard,
      drive: drive,
      // open, waiting (an Orc waits for it) and other are the list's own. run is how many open
      // questions are in the run of answering (not parked), toAnswer how many of those have no
      // answer of the reader's standing, parked how many open ones are set aside.
      // thrall how many wait on the keeper, history how many are closed, fresh how many are new;
      // toAnswer counts the list as drawn: questions of his turn that hold no answer of his yet.
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
          if (!standingOf(l.q)) { toAnswer += 1; }
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
        var out = { headings: [], lines: [], sub: [], left: { lines: 0, sub: 0 } };
        var linePx = drawnLines.length ? (parseFloat(window.getComputedStyle(drawnLines[0].txt).lineHeight) || 22) : 22;
        drawnHeads.forEach(function (h) { out.headings.push({ t: cut(h.txt.textContent, limits.lineChars), count: h.head.qs.length, folded: h.folded, parked: h.head.kind === "parked", kind: h.head.kind, note: !h.note ? "" : (h.group.classList.contains("note-open") ? "shown" : "folded") }); });
        drawnLines.forEach(function (line) {
          if (out.lines.length >= limits.lines) { out.left.lines += 1; return; }
          out.lines.push({
            n: line.num.textContent, l: line.letter.textContent, t: cut(line.txt.textContent, limits.lineChars), s: "", g: line.head,
            z: textOf(line.zone), nw: line.wrap.classList.contains("new"),
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
          return { n: r.num.textContent, t: cut(r.txt.textContent, limits.lineChars), k: r.kind, a: cut(r.said.mine, limits.lineChars), r: cut(r.said.theirs, limits.lineChars), o: cut(r.said.outcome, limits.lineChars) };
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

  window.HordeDecisionsDocument = { mount: mount };
}());
