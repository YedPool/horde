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
//                         stay; any other field: as Enter. Shift+Tab: back one
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
  var WORDS = {
    you: "You", keeper: KEEPER, saving: "saving", saved: "saved", told: "told " + KEEPER, read: "read by " + KEEPER, draft: "draft",
    afterClosing: "the question is closed; kept, and it reopens nothing", earlierWording: "said to an earlier wording",
    marks: "this message holds direction or invisible characters"
  };
  var DRAFTS_KEY = "horde-decisions-drafts-v1";
  // How long after the caret arrives in an empty field an Enter is taken for the tail of a doubled
  // key press. Longer than a key bounce or an accidental double tap; shorter than reading a question.
  var ARRIVAL_MS = 350;
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
    function messagesOf(q) { return (q.thread && Array.isArray(q.thread.messages)) ? q.thread.messages : []; }
    // THE ANSWER THAT STANDS: the reader's own message when it is the last thing said under the
    // question; or what the host has just answered is saved, until a list arrives that holds it.
    function standingOf(q) {
      var msgs = messagesOf(q);
      var s = sent[q.number];
      if (s && s.saved) {
        var caught = msgs.some(function (m) { return Number(m.sequence) >= s.saved.sequence; });
        if (caught) { s.saved = null; } else { return s.saved; }
      }
      var last = msgs.length ? msgs[msgs.length - 1] : null;
      return (last && last.speaker === MINE) ? last : null;
    }
    // What stands above the field: everything said before the standing answer, a message of the
    // reader's that they replaced at once with another left out.
    function earlierOf(q) {
      var msgs = messagesOf(q);
      var standing = standingOf(q);
      var out = [];
      for (var i = 0; i < msgs.length; i += 1) {
        if (standing && msgs[i] === standing) { continue; }
        if (msgs[i].speaker === MINE && i + 1 < msgs.length && msgs[i + 1].speaker === MINE) { continue; }
        out.push(msgs[i]);
      }
      return out;
    }
    function valueOf(q) {
      if (drafts[q.number] !== undefined) { return drafts[q.number]; }
      var standing = standingOf(q);
      return standing ? textOf(standing.text) : "";
    }
    function recOf(q) { return textOf(q.recommendation); }
    function markOf(q, value) {
      var s = sent[q.number];
      if (s && s.pending > 0) { return WORDS.saving; }
      var standing = standingOf(q);
      if (standing && value === textOf(standing.text)) {
        var words = WORDS.saved;
        if (Array.isArray(standing.unreadBy)) { words = standing.unreadBy.length === 0 ? WORDS.read : (standing.told === true ? WORDS.told : WORDS.saved); }
        if (standing.arrivedAfterClosing === true) { words += " (" + WORDS.afterClosing + ")"; }
        if (standing.saidToEarlierWording === true) { words += " (" + WORDS.earlierWording + ")"; }
        return words;
      }
      return value !== "" ? WORDS.draft : "";
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

    function headingsOf() {
      // The headings in the order their first question comes, the listed state's groups first.
      var byKey = Object.create(null);
      var order = [];
      var i, q, listed, key, head;
      for (i = 0; i < questions.length; i += 1) {
        q = questions[i];
        listed = textOf(q.state) === LISTED_STATE;
        key = (listed ? "group:" : "state:") + (listed ? textOf(q.group) : textOf(q.state));
        head = byKey[key];
        if (!head) {
          head = { key: key, listed: listed, name: listed ? (textOf(q.group) || "No group") : capital(textOf(q.state)), note: "", qs: [] };
          byKey[key] = head;
          order.push(head);
        }
        if (listed && !head.note && textOf(q.groupNote)) { head.note = textOf(q.groupNote); }
        head.qs.push(q);
      }
      return order.filter(function (h) { return h.listed; }).concat(order.filter(function (h) { return !h.listed; }));
    }

    function isFolded(head) {
      return headFolded[head.key] === undefined ? !head.listed : headFolded[head.key];
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
      for (var i = 0; i < drawnLines.length; i += 1) { if (drawnLines[i].field === act) { return drawnLines[i]; } }
      return null;
    }

    // A FIELD IS AS TALL AS ITS WORDS, in whole lines: one when empty, unless the grey suggestion
    // needs more, which is measured by standing it in the field for the length of this function.
    function fit(field) {
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
      line.mark.textContent = markOf(line.q, line.field.value);
      line.refusal.textContent = (s && s.refusal) ? s.refusal : "";
      line.refusal.hidden = !(s && s.refusal);
    }

    function intoView(line) {
      var box = line.wrap.getBoundingClientRect();
      var inset = topInset();
      if (box.top < inset) { window.scrollBy(0, box.top - inset); }
      else if (box.bottom > window.innerHeight) { window.scrollBy(0, Math.min(box.top - inset, box.bottom - window.innerHeight + 8)); }
    }
    function enter(line) {
      line.field.focus({ preventScroll: true });
      var end = line.field.value.length;
      try { line.field.setSelectionRange(end, end); } catch (e) { /* a field not drawn has no caret */ }
      arrived = { number: line.q.number, at: Date.now() };
      intoView(line);
      onChange();
    }
    function move(line, step) {
      var shown = shownLines();
      var at = shown.indexOf(line);
      var next = shown[at + step];
      if (at >= 0 && next) { enter(next); return true; }
      return false;
    }
    function takeKeyboard() {
      var shown = shownLines();
      var first = null;
      for (var i = 0; i < shown.length; i += 1) {
        if (textOf(shown[i].q.state) === LISTED_STATE && !standingOf(shown[i].q)) { first = shown[i]; break; }
      }
      if (!first && shown.length) { first = shown[0]; }
      if (first) { enter(first); }
    }

    function typed(line) {
      // What stands in the field now: a draft unless it is the standing answer, word for word.
      var q = line.q;
      var value = line.field.value;
      var standing = standingOf(q);
      if (value === (standing ? textOf(standing.text) : "")) { delete drafts[q.number]; } else { drafts[q.number] = value; }
      keepDrafts();
      // Words changed after a refusal are not the words that were refused.
      var s = sent[q.number];
      if (s && s.refusal && value !== s.sentText) { s.refusal = ""; }
      fit(line.field);
      refresh(line);
      onChange();
    }
    function setValue(line, value) {
      line.field.value = value;
      try { line.field.setSelectionRange(value.length, value.length); } catch (e) { /* not drawn */ }
      typed(line);
    }
    function insert(line, text) {
      var f = line.field;
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
        s.saved = { text: text, sequence: Number(result.sequence), speaker: MINE, arrivedAfterClosing: result.arrivedAfterClosing === true, saidToEarlierWording: result.saidToEarlierWording === true };
        if (s.sentId === id) { s.refusal = ""; }
        // The draft is dropped only if it is still these very words.
        if (drafts[number] === text) { delete drafts[number]; keepDrafts(); }
      } else if (s.sentId === id) {
        s.refusal = textOf(result && result.reason) || "Not saved, and no reason was given.";
        // BACK TO THE WORDS THAT WERE NOT SAVED, unless the reader is typing somewhere else.
        var now = focusedLine();
        if (line && now !== line && (!now || now.field.value === "" || drafts[now.q.number] === undefined)) { enter(line); }
      }
      if (line) { refresh(line); }
      onChange();
    }
    function save(line) {
      // Send what stands in the field, if it says something and is not already the standing answer.
      // Returns whether there was anything to send.
      var q = line.q;
      var text = line.field.value;
      var standing = standingOf(q);
      if (text.trim() === "" || (standing && text === textOf(standing.text))) { return false; }
      var s = sentOf(q.number);
      if (s.pending > 0 && s.sentText === text) { return true; }
      var id = (s.sentText === text && s.sentId) ? s.sentId : newId();
      s.sentText = text; s.sentId = id; s.pending += 1; s.refusal = "";
      refresh(line);
      var number = q.number;
      Promise.resolve().then(function () { return say(number, text, Number(q.wordingVersion), id); }).then(
        function (result) { answered(number, id, text, result); },
        function (error) { answered(number, id, text, { ok: false, reason: "Not saved: " + ((error && error.message) ? error.message : error) }); });
      return true;
    }

    function toggleContext(q) {
      if (unfolded[q.number] === true) { delete unfolded[q.number]; } else { unfolded[q.number] = true; }
      draw();
    }

    function onKey(e, line) {
      if (e.isComposing) { return; }
      var q = line.q;
      var field = line.field;
      var key = e.key;
      var plain = !e.ctrlKey && !e.altKey && !e.metaKey;
      var blank = field.value.trim() === "";
      var rec = recOf(q);
      if ((key === "Enter" && e.shiftKey) || ((key === "j" || key === "J") && e.ctrlKey && !e.altKey)) { e.preventDefault(); insert(line, "\n"); return; }
      if (key === "Enter" && e.ctrlKey) {
        e.preventDefault();
        if (blank) { if (!rec) { return; } setValue(line, rec); }
        save(line); move(line, 1);
        return;
      }
      if (key === "Enter" && plain) {
        e.preventDefault();
        if (field.value === "" && arrived.number === q.number && Date.now() - arrived.at < ARRIVAL_MS) { return; }
        save(line); move(line, 1);
        return;
      }
      if (key === "Tab" && e.shiftKey) { e.preventDefault(); move(line, -1); return; }
      if (key === "Tab" && plain) {
        e.preventDefault();
        if (field.value === "" && rec) { setValue(line, rec); return; }
        save(line); move(line, 1);
        return;
      }
      if (key === "ArrowRight" && plain && !e.shiftKey && field.value === "" && rec) { e.preventDefault(); setValue(line, rec); return; }
      if (key === "F2" || ((key === " " || e.code === "Space") && e.ctrlKey)) { e.preventDefault(); toggleContext(q); }
    }

    function drawMessage(m) {
      var row = make("div", "hd-msg");
      row.appendChild(make("span", "hd-who", (m.speaker === MINE ? WORDS.you : WORDS.keeper) + ":"));
      var said = make("span", "hd-said", textOf(m.text));
      said.setAttribute("dir", "auto");
      row.appendChild(said);
      if (m.holdsDirectionOrInvisibleCharacters === true) { row.appendChild(make("span", "hd-flag", " (" + WORDS.marks + ")")); }
      return { row: row, said: said, who: m.speaker === MINE ? WORDS.you : WORDS.keeper };
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
      var said = [];
      earlierOf(q).forEach(function (m) { var drawn = drawMessage(m); ans.appendChild(drawn.row); said.push(drawn); });
      if (q.thread && textOf(q.thread.problem)) { ans.appendChild(make("div", "hd-refusal", q.thread.problem)); }
      var fl = make("div", "hd-fl");
      var field = make("textarea", "hd-field");
      field.rows = 1;
      field.setAttribute("dir", "auto");
      field.setAttribute("aria-label", "Your answer to question " + q.number);
      field.spellcheck = false;
      field.placeholder = recOf(q);
      field.value = valueOf(q);
      var mark = make("span", "hd-mark");
      fl.appendChild(field); fl.appendChild(mark);
      var refusal = make("div", "hd-refusal");
      refusal.hidden = true;
      ans.appendChild(fl); ans.appendChild(refusal);
      row.appendChild(qt); row.appendChild(ans);
      wrap.appendChild(row);
      var subs = [];
      if (open) {
        var kids = make("div", "hd-sub");
        var lines = subLinesOf(q);
        var i, line, subNum, subTxt, body;
        for (i = 0; i < lines.length; i += 1) {
          line = make("div", "hd-row hd-line");
          subNum = make("span", "hd-num", q.number + "." + (i + 1));
          line.appendChild(subNum);
          // The label and the words are one run of text, so a long line wraps under its label.
          body = make("span", "hd-body");
          if (lines[i].label) { body.appendChild(make("span", "hd-lab", lines[i].label + ":")); }
          subTxt = make("span", "hd-txt", lines[i].text);
          body.appendChild(subTxt);
          line.appendChild(body);
          kids.appendChild(line);
          subs.push({ num: subNum, label: lines[i].label, txt: subTxt });
        }
        wrap.appendChild(kids);
      }
      var drawn = { q: q, wrap: wrap, row: row, num: no, letter: letter, txt: txt, field: field, mark: mark, refusal: refusal, said: said, subs: subs };
      field.addEventListener("input", function () { typed(drawn); });
      field.addEventListener("keydown", function (e) { onKey(e, drawn); });
      field.addEventListener("focus", function () { onChange(); });
      refresh(drawn);
      drawnLines.push(drawn);
      return wrap;
    }

    function draw() {
      var before = place();
      // The caret, to be put back where it was: a redraw makes every field anew.
      var had = focusedLine();
      var caret = had ? { number: had.q.number, from: had.field.selectionStart, to: had.field.selectionEnd } : null;
      while (root.firstChild) { root.removeChild(root.firstChild); }
      drawnHeads = [];
      drawnLines = [];
      var heads = headingsOf();
      heads.forEach(function (head, index) {
        var folded = isFolded(head);
        var group = make("div", "hd-group" + (folded ? " folded" : "") + (head.note && noteShown[head.key] === true ? " note-open" : ""));
        var row = make("div", "hd-row hd-head");
        var tri = make("button", "hd-tri");
        tri.type = "button";
        tri.tabIndex = -1;
        tri.setAttribute("aria-expanded", folded ? "false" : "true");
        tri.setAttribute("aria-label", (folded ? "Unfold " : "Fold ") + head.name);
        var txt = make("span", "hd-txt", head.name);
        var suf = make("span", "hd-suf");
        suf.appendChild(make("span", "hd-count", " - " + head.qs.length + (head.qs.length === 1 ? " question" : " questions")));
        var note = null;
        if (head.note) {
          var more = make("span", "hd-more", " - ");
          var word = make("button", "hd-bg", "background");
          word.type = "button";
          word.tabIndex = -1;
          word.setAttribute("aria-expanded", noteShown[head.key] === true ? "true" : "false");
          word.setAttribute("aria-label", (noteShown[head.key] === true ? "Fold the background of " : "Unfold the background of ") + head.name);
          // The word is in the heading's row, and a click on the row folds the whole group.
          word.addEventListener("click", function (e) { e.stopPropagation(); noteShown[head.key] = noteShown[head.key] !== true; draw(); });
          more.appendChild(word);
          suf.appendChild(more);
          note = make("div", "hd-note", head.note);
        }
        row.appendChild(tri); row.appendChild(txt); row.appendChild(suf);
        row.addEventListener("click", function () { headFolded[head.key] = !isFolded(head); draw(); });
        group.appendChild(row);
        if (note) { group.appendChild(note); }
        var kids = make("div", "hd-kids");
        var first = drawnLines.length;
        head.qs.forEach(function (q) { kids.appendChild(drawQuestion(q)); });
        for (var i = first; i < drawnLines.length; i += 1) { drawnLines[i].head = index; }
        group.appendChild(kids);
        root.appendChild(group);
        drawnHeads.push({ head: head, txt: txt, folded: folded, group: group, note: note });
      });
      drawnLines.forEach(function (line) { fit(line.field); });
      if (before) {
        for (var j = 0; j < drawnLines.length; j += 1) {
          if (drawnLines[j].q.number === before.number) {
            var moved = drawnLines[j].row.getBoundingClientRect().top - before.top;
            if (moved !== 0) { window.scrollBy(0, moved); }
            break;
          }
        }
      }
      if (caret) {
        var again = lineOf(caret.number);
        if (again && again.field.offsetParent !== null) {
          again.field.focus({ preventScroll: true });
          try { again.field.setSelectionRange(Math.min(caret.from, again.field.value.length), Math.min(caret.to, again.field.value.length)); } catch (e) { /* not drawn */ }
        }
      }
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
    //   { do: "keyboard" }        the window is given the keyboard (what the page does then)
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
        else if (step.do === "type") { if (line) { insert(line, textOf(step.text)); } }
        else if (step.do === "key") {
          (line ? line.field : document.body).dispatchEvent(new KeyboardEvent("keydown", { key: textOf(step.key), shiftKey: step.shift === true, ctrlKey: step.ctrl === true, bubbles: true, cancelable: true }));
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
    window.addEventListener("resize", function () { drawnLines.forEach(function (line) { fit(line.field); }); });

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
        draw();
        return "drawn";
      },
      setDim: function (fn) {
        dim = (typeof fn === "function") ? fn : null;
        drawnLines.forEach(function (line) { line.wrap.classList.toggle("dim", !!(dim && dim(line.q))); });
        onDraw();
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
        headingsOf().forEach(function (head) { headFolded[head.key] = false; if (head.note) { noteShown[head.key] = true; } });
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
      counts: function () {
        var open = 0, waiting = 0, other = 0;
        questions.forEach(function (q) {
          if (textOf(q.state) === LISTED_STATE) { open += 1; if (listOf(q.waiting).length) { waiting += 1; } } else { other += 1; }
        });
        return { open: open, waiting: waiting, other: other };
      },
      // WHAT IS DRAWN, from the elements themselves and not from the data they were made of:
      //   headings  [{ t, count, folded, note }]  note is "" for a group with no note of background,
      //                                           "folded" or "shown" for one that has it
      //   lines     [{ n, l, t, s, g, open, dim,  n the number as text drawn, l the letter before it,
      //                rows, clip,                t the question's text, rows how many lines it takes,
      //                a, p, m, r, fh, th }]      clip whether anything shortens it; a what stands in
      //                                           the answer's field, p its grey suggestion, m its
      //                                           mark, r the refusal under it, fh its height in
      //                                           lines, th what was said before, as drawn. s is the
      //                                           suffix a folded line once carried: always "" now.
      //   sub       [{ n, t }]                    the sub-numbered lines of the unfolded questions
      //   answer    { fields, focus, pending,     how many fields can be typed in with no click, the
      //               drafts, storage }           number of the question whose field has the caret
      //                                           ("" for none), how many sends are unanswered, how
      //                                           many drafts are kept, and what is wrong with keeping
      //   left      { lines, sub }                how many were left out by the caller's limits
      // limits is { lines, subLines, lineChars }: the most of each, and the most characters of a text.
      snapshot: function (limits) {
        var out = { headings: [], lines: [], sub: [], left: { lines: 0, sub: 0 } };
        var linePx = drawnLines.length ? (parseFloat(window.getComputedStyle(drawnLines[0].txt).lineHeight) || 22) : 22;
        drawnHeads.forEach(function (h) { out.headings.push({ t: cut(h.txt.textContent, limits.lineChars), count: h.head.qs.length, folded: h.folded, note: !h.note ? "" : (h.group.classList.contains("note-open") ? "shown" : "folded") }); });
        drawnLines.forEach(function (line) {
          if (out.lines.length >= limits.lines) { out.left.lines += 1; return; }
          out.lines.push({
            n: line.num.textContent, l: line.letter.textContent, t: cut(line.txt.textContent, limits.lineChars), s: "", g: line.head,
            open: line.wrap.classList.contains("open"), dim: line.wrap.classList.contains("dim"),
            rows: Math.round(line.txt.getBoundingClientRect().height / linePx), clip: clipped(line.txt),
            a: cut(line.field.value, limits.lineChars), p: cut(line.field.placeholder, limits.lineChars), m: cut(line.mark.textContent, limits.lineChars),
            r: cut(line.refusal.textContent, limits.lineChars), fh: Math.round(line.field.getBoundingClientRect().height / linePx),
            th: line.said.slice(0, 8).map(function (s) { return cut(s.who + ": " + s.said.textContent, limits.lineChars); })
          });
          line.subs.forEach(function (sub) {
            if (out.sub.length >= limits.subLines) { out.left.sub += 1; return; }
            out.sub.push({ n: sub.num.textContent, t: cut((sub.label ? sub.label + ": " : "") + sub.txt.textContent, limits.lineChars) });
          });
        });
        var has = focusedLine();
        out.answer = { fields: shownLines().length, focus: has ? String(has.q.number) : "", pending: pending(), drafts: Object.keys(drafts).length, storage: storageProblem };
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
