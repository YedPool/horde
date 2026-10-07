// decisions/page/list.js - the list of questions drawn as a document: group headings, one line per
// question with its permanent number, and each question unfolding into sub-numbered lines. A group's
// note of background is folded behind the word "background" in its heading.
//
// ITS ONE JOB is to draw what the decisions operations answered (decisions/Operations.ps1: kinds and
// list), exactly as it was handed over. It asks nobody for anything, knows no bridge and no fleet,
// and changes nothing: READ-ONLY. There is no control here that does not work today.
//
//   var doc = HordeDecisionsDocument.mount(element, { topInset: function () { }, onDraw: function () { } });
//   doc.setKinds(record)     the answer of the kinds operation, as { state, value, reason }
//   doc.setList(record)      the answer of the list operation; says what it did: "drawn", "same"
//                            (the very answer already drawn: nothing is touched) or "unread" (the
//                            answer is not a list: what was drawn stays, and the caller says why)
//   doc.setDim(fnOrNull)     fn(question) is true for a question to draw dimmed. DIMMED, NEVER HIDDEN
//   doc.setUnfolded(numbers) these questions unfolded as well; doc.unfoldAll(); doc.foldAll()
//   doc.reveal(number)       that question brought into view, if it is not wholly in it already
//   doc.counts()             { open, waiting, other }
//   doc.snapshot(limits)     WHAT IS DRAWN, read back from the page's own elements: the headings, and
//                            every question line's number, text and suffix; see snapshot below
//   doc.measure()            the computed letter size and line height of a question line, in CSS pixels
//
// A QUESTION IS NEVER LOST TO ITS GROUP'S NAME. Groups are kept in a map with no prototype: a group a
// session named "__proto__" or "constructor" is a key like any other. In an ordinary object the first
// is the object's own prototype and the second a function it inherits, and two questions in such a
// group were drawn as one, twice (measured 2026-10-06 in a real window by the review of the earlier
// page). The same holds for every map here that is keyed by text or by a number.
//
// A REDRAW KEEPS THE READER'S PLACE. What the reader unfolded stays unfolded, by the question's
// permanent number, and the line at the top of the view stays where it is: its place is measured
// before the redraw and the page is scrolled by however far it moved.
//
// EVERY TEXT IS SET AS TEXT (textContent). A question may quote anything a session wrote, and none of
// it is ever read as markup.
(function () {
  "use strict";

  // The one state the document lists under its groups; a question in any other state is listed after
  // them, under a heading that is the state's own name, folded until the reader unfolds it.
  var LISTED_STATE = "open";
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

  function mount(root, options) {
    // Where the view begins: below whatever the host keeps fixed at the top, which only the host knows.
    var topInset = (options && typeof options.topInset === "function") ? options.topInset : function () { return 0; };
    var onDraw = (options && typeof options.onDraw === "function") ? options.onDraw : function () {};
    var kinds = Object.create(null);
    var questions = [];
    var lastJson = null;
    var dim = null;
    // Keyed by a question's number and by a heading's key: maps with no prototype (header).
    var unfolded = Object.create(null);
    var headFolded = Object.create(null);
    // Which headings have their note of background shown. FOLDED UNTIL ASKED FOR: a note is several
    // lines, and shown always it stood between the questions - at the width the window has beside a
    // terminal, two notes took 13 of the 26 lines in view and 8 questions were left (seen 2026-10-07
    // in a picture of the real window, 567 device pixels wide, on a list of 22 real questions). The
    // heading says there is one with the word "background", which unfolds it.
    var noteShown = Object.create(null);
    var drawnHeads = [];
    var drawnLines = [];

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

    // WHO, WITHOUT WHY. A name in the waiting list may carry its reason in brackets ("Orc D (test
    // deploy of email linking)"); the folded line's suffix names who and no more, and the unfolded
    // question's own Waiting line gives every word. With the reasons in it the suffix took its full
    // 46 percent of every line and cut the question's own words short (seen 2026-10-07 in pictures of
    // a real window 980 device pixels wide, on a list of 22 real questions).
    function whoOf(name) {
      var words = textOf(name);
      var at = words.indexOf(" (");
      return at > 0 ? words.slice(0, at) : words;
    }

    function suffixOf(q) {
      var bits = [];
      var rec = textOf(q.recommendation).replace(/\.$/, "");
      if (textOf(q.state) !== LISTED_STATE) { bits.push(textOf(q.state) + (textOf(q.outcome) ? ": " + textOf(q.outcome) : "")); }
      else {
        if (rec) { bits.push("Recommended: " + rec); }
        if (listOf(q.waiting).length) { bits.push(listOf(q.waiting).map(whoOf).join(", ") + " waiting"); }
      }
      return bits.length ? " - " + bits.join(" - ") : "";
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

    function drawQuestion(q) {
      var open = unfolded[q.number] === true;
      var wrap = make("div", "hd-q" + (open ? " open" : "") + (dim && dim(q) ? " dim" : ""));
      var row = make("div", "hd-row");
      var tri = make("button", "hd-tri");
      tri.type = "button";
      tri.setAttribute("aria-expanded", open ? "true" : "false");
      tri.setAttribute("aria-label", (open ? "Fold question " : "Unfold question ") + q.number);
      var num = make("span", "hd-num", q.number);
      var txt = make("span", "hd-txt", textOf(q.title));
      var suf = make("span", "hd-suf", suffixOf(q));
      row.appendChild(tri); row.appendChild(num); row.appendChild(txt); row.appendChild(suf);
      row.addEventListener("click", function () {
        // Dragging across the words to copy them is not a wish to fold the line.
        if (String(window.getSelection ? window.getSelection() : "") !== "") { return; }
        if (unfolded[q.number] === true) { delete unfolded[q.number]; } else { unfolded[q.number] = true; }
        draw();
      });
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
      drawnLines.push({ q: q, wrap: wrap, row: row, num: num, txt: txt, suf: suf, subs: subs });
      return wrap;
    }

    function draw() {
      var before = place();
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
      if (before) {
        for (var j = 0; j < drawnLines.length; j += 1) {
          if (drawnLines[j].q.number === before.number) {
            var moved = drawnLines[j].row.getBoundingClientRect().top - before.top;
            if (moved !== 0) { window.scrollBy(0, moved); }
            break;
          }
        }
      }
      onDraw();
    }

    function cut(text, most) { text = textOf(text); return text.length > most ? text.slice(0, most) : text; }

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
      // A QUESTION THE READER WAS POINTED AT MUST BE IN VIEW. A question unfolded far down the list
      // was unfolded where nobody saw it: opened to show question 15 of 22, the window showed 1 to 12
      // (seen 2026-10-07 in a picture of the real window). A question wholly in view is left where
      // it is; another is moved to the very top of the view, under whatever the host keeps fixed
      // there. To the very top, and not a line below it: what stands above a question is a line, a
      // heading of two lines or a gap, and a fixed step back left half a line or the tail of a
      // heading cut off under the bar (seen the same day, in the pictures of the first try).
      reveal: function (number) {
        var i, box;
        for (i = 0; i < drawnLines.length; i += 1) {
          if (drawnLines[i].q.number !== number) { continue; }
          box = drawnLines[i].wrap.getBoundingClientRect();
          if (box.height > 0 && (box.top < topInset() || box.bottom > window.innerHeight)) { window.scrollBy(0, box.top - topInset()); }
          return;
        }
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
      //   lines     [{ n, t, s, g, open, dim }]   n the number as text drawn, t the question's line,
      //                                           s its muted suffix, g which heading it is under
      //   sub       [{ n, t }]                    the sub-numbered lines of the unfolded questions
      //   left      { lines, sub }                how many were left out by the caller's limits
      // limits is { lines, subLines, lineChars }: the most of each, and the most characters of a text.
      snapshot: function (limits) {
        var out = { headings: [], lines: [], sub: [], left: { lines: 0, sub: 0 } };
        drawnHeads.forEach(function (h) { out.headings.push({ t: cut(h.txt.textContent, limits.lineChars), count: h.head.qs.length, folded: h.folded, note: !h.note ? "" : (h.group.classList.contains("note-open") ? "shown" : "folded") }); });
        drawnLines.forEach(function (line) {
          if (out.lines.length >= limits.lines) { out.left.lines += 1; return; }
          out.lines.push({ n: line.num.textContent, t: cut(line.txt.textContent, limits.lineChars), s: cut(line.suf.textContent, limits.lineChars), g: line.head, open: line.wrap.classList.contains("open"), dim: line.wrap.classList.contains("dim") });
          line.subs.forEach(function (sub) {
            if (out.sub.length >= limits.subLines) { out.left.sub += 1; return; }
            out.sub.push({ n: sub.num.textContent, t: cut((sub.label ? sub.label + ": " : "") + sub.txt.textContent, limits.lineChars) });
          });
        });
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
