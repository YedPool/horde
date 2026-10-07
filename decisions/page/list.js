// decisions/page/list.js - the list of questions drawn as a document: group headings, one line per
// question with its permanent number, and each question unfolding into sub-numbered lines.
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

    function suffixOf(q) {
      var bits = [];
      var rec = textOf(q.recommendation).replace(/\.$/, "");
      if (textOf(q.state) !== LISTED_STATE) { bits.push(textOf(q.state) + (textOf(q.outcome) ? ": " + textOf(q.outcome) : "")); }
      else {
        if (rec) { bits.push("Recommended: " + rec); }
        if (listOf(q.waiting).length) { bits.push(listOf(q.waiting).join(", ") + " waiting"); }
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
        var group = make("div", "hd-group" + (folded ? " folded" : ""));
        var row = make("div", "hd-row hd-head");
        var tri = make("button", "hd-tri");
        tri.type = "button";
        tri.setAttribute("aria-expanded", folded ? "false" : "true");
        tri.setAttribute("aria-label", (folded ? "Unfold " : "Fold ") + head.name);
        var txt = make("span", "hd-txt", head.name);
        var suf = make("span", "hd-suf", " - " + head.qs.length + (head.qs.length === 1 ? " question" : " questions"));
        row.appendChild(tri); row.appendChild(txt); row.appendChild(suf);
        row.addEventListener("click", function () { headFolded[head.key] = !isFolded(head); draw(); });
        group.appendChild(row);
        if (head.note) { group.appendChild(make("div", "hd-note", head.note)); }
        var kids = make("div", "hd-kids");
        var first = drawnLines.length;
        head.qs.forEach(function (q) { kids.appendChild(drawQuestion(q)); });
        for (var i = first; i < drawnLines.length; i += 1) { drawnLines[i].head = index; }
        group.appendChild(kids);
        root.appendChild(group);
        drawnHeads.push({ head: head, txt: txt, folded: folded });
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
      unfoldAll: function () {
        questions.forEach(function (q) { unfolded[q.number] = true; });
        headingsOf().forEach(function (head) { headFolded[head.key] = false; });
        draw();
      },
      foldAll: function () {
        unfolded = Object.create(null);
        headFolded = Object.create(null);
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
      //   headings  [{ t, count, folded }]
      //   lines     [{ n, t, s, g, open, dim }]   n the number as text drawn, t the question's line,
      //                                           s its muted suffix, g which heading it is under
      //   sub       [{ n, t }]                    the sub-numbered lines of the unfolded questions
      //   left      { lines, sub }                how many were left out by the caller's limits
      // limits is { lines, subLines, lineChars }: the most of each, and the most characters of a text.
      snapshot: function (limits) {
        var out = { headings: [], lines: [], sub: [], left: { lines: 0, sub: 0 } };
        drawnHeads.forEach(function (h) { out.headings.push({ t: cut(h.txt.textContent, limits.lineChars), count: h.head.qs.length, folded: h.folded }); });
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
