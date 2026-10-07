// decisions/page/list.js - the list of questions waiting for a person, as a page shows it.
//
// ITS ONE JOB is to draw what the decisions operations answered. It reads no file and asks nobody:
// whoever hosts it hands it the value of the kinds operation and the answer of the list operation
// (decisions/Operations.ps1), and it draws exactly those. It knows nothing of windows, of the bridge
// that fetched the data, or of the fleet panel that may stand beside it; a filter it is handed is a
// function over a question, whatever that function is about.
//
//   var list = HordeDecisionsList.mount(element, { scroller: elementThatScrolls });   // or the page itself
//   list.setKinds(value)        the kinds operation's value: { kinds: { <name>: { label, means, list } } }
//   list.setList(answer)        the list operation's answer: { state, value, reason }, asked for every state
//   list.setFilter(name)        open | waiting | free | closed
//   list.setPredicate(fn, why)  a further filter over a question, or null; why is words for the header
//   list.setOpen(numbers)       which questions are opened to their context, by number
//   list.onChange(fn)           fn(snapshot) after every draw
//   list.snapshot()             { rows, open, closed, waiting, expanded, filter }
//
// DENSE ON PURPOSE: one line per question - its number, the question, who is waiting, the
// recommendation in short - under thin group headers, so that many are in view at once. A row opens
// to its context when it is clicked.
//
// READ-ONLY. There is no answer field here: answering from the page is the next step, and a control
// that did nothing would be a lie.
//
// A REDRAW NEVER TAKES THE READER'S PLACE AWAY. Which rows are open is kept by question number, a
// number that never changes, and the scroll position is put back after every draw; an answer that is
// the same as the one already drawn is not drawn again.
//
// EVERY TEXT IS SET AS TEXT (textContent). A question's words may quote anything a session wrote,
// markup and script included, and none of it is ever read as markup.
(function () {
  "use strict";

  var FILTERS = {
    open: { label: "All open", short: "Open", test: function (q) { return q.state === "open"; } },
    waiting: { label: "Someone waiting", short: "Waiting", test: function (q) { return q.state === "open" && q.waiting.length > 0; } },
    free: { label: "Nobody blocked", short: "Unblocked", test: function (q) { return q.state === "open" && q.waiting.length === 0; } },
    closed: { label: "Closed", short: "Closed", test: function (q) { return q.state !== "open"; } }
  };

  function make(tag, className, text) {
    var node = document.createElement(tag);
    if (className) { node.className = className; }
    if (text !== undefined && text !== null) { node.textContent = String(text); }
    return node;
  }

  function firstLine(text, most) {
    var lines = String(text || "").split(/\r?\n/);
    var line = "";
    for (var i = 0; i < lines.length; i += 1) { if (lines[i].trim() !== "") { line = lines[i].trim(); break; } }
    if (line.length > most) { return line.slice(0, most) + " ..."; }
    return line;
  }

  function timeWords(at) {
    var m = /^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})/.exec(String(at || ""));
    return m ? m[1] + " " + m[2] + " UTC" : String(at || "");
  }

  function mount(root, options) {
    var scroller = (options && options.scroller) ? options.scroller : (document.scrollingElement || document.documentElement);
    var state = { kinds: {}, answer: null, drawnJson: null, filter: "open", predicate: null, predicateWhy: "", open: {}, listeners: [], rows: 0 };

    function questions() {
      var a = state.answer;
      if (!a || a.state !== "known" || !a.value || a.value.outcome !== "done" || !a.value.questions) { return []; }
      return a.value.questions;
    }

    function snapshot() {
      var all = questions();
      var open = 0, closed = 0, waiting = 0, expanded = 0;
      for (var i = 0; i < all.length; i += 1) {
        if (all[i].state === "open") { open += 1; if (all[i].waiting.length > 0) { waiting += 1; } } else { closed += 1; }
      }
      var nodes = root.querySelectorAll(".dq.dq-open");
      expanded = nodes.length;
      return { rows: state.rows, open: open, closed: closed, waiting: waiting, expanded: expanded, filter: state.filter };
    }

    function addField(dl, name, value) {
      if (value === undefined || value === null || String(value).trim() === "") { return; }
      dl.appendChild(make("dt", null, name));
      dl.appendChild(make("dd", null, value));
    }

    function addList(dl, name, items) {
      if (!items || !items.length) { return; }
      dl.appendChild(make("dt", null, name));
      var dd = make("dd");
      var ul = make("ul");
      for (var i = 0; i < items.length; i += 1) { ul.appendChild(make("li", null, items[i])); }
      dd.appendChild(ul);
      dl.appendChild(dd);
    }

    function detail(q) {
      var box = make("div", "dx");
      var dl = make("dl");
      var kind = state.kinds[q.kind];
      addField(dl, "Kind", kind ? kind.label + ". " + kind.means : q.kind);
      addList(dl, "Options", q.options);
      addList(dl, "Parts", q.parts);
      addField(dl, "What it is", q.whatItIs);
      addField(dl, "Yes means", q.yesMeans);
      addField(dl, "Recommended", q.recommendation === "" ? "none given" : q.recommendation);
      addField(dl, "Asked by", q.askedBy);
      addList(dl, "Waiting", q.waiting);
      if (!q.waiting.length) { addField(dl, "Waiting", "nobody"); }
      addList(dl, "Files", q.files);
      addList(dl, "References", q.references);
      if (q.needsSecret) { addField(dl, "Needs a secret", "Yes. The secret is never written into this list or into an answer; it is given outside."); }
      if (q.state !== "open") { addField(dl, "Closed", timeWords(q.closedAt) + (q.outcome ? ": " + q.outcome : "")); }
      addField(dl, "Reopened", q.reopenReason);
      addField(dl, "Wording", "version " + q.wordingVersion + ", asked " + timeWords(q.addedAt));
      box.appendChild(dl);
      return box;
    }

    function row(q) {
      var wrap = make("div", "dq" + (state.open[q.number] ? " dq-open" : ""));
      wrap.setAttribute("data-number", String(q.number));
      var line = make("div", "dr");
      line.tabIndex = 0;
      line.setAttribute("role", "button");
      line.setAttribute("aria-expanded", state.open[q.number] ? "true" : "false");
      line.appendChild(make("span", "dt-tw"));
      line.appendChild(make("span", "dt-n", q.number));
      line.appendChild(make("span", "dt-t", q.title));
      // The name alone, without what it is waiting to do: that is in the opened row, and a row has
      // no room for it (seen 2026-10-07: "Orc D (test..." took a third of a narrow row from the question).
      var who = q.state !== "open" ? "closed" : (q.waiting.length ? firstLine(q.waiting[0].split(" (")[0], 18) + (q.waiting.length > 1 ? " +" + (q.waiting.length - 1) : "") : "nobody");
      line.appendChild(make("span", "dt-w " + (q.state !== "open" ? "dt-done" : (q.waiting.length ? "dt-wait" : "dt-free")), who));
      line.appendChild(make("span", "dt-rc", q.state !== "open" ? firstLine(q.outcome, 90) : firstLine(q.recommendation, 90)));
      function toggle() {
        if (state.open[q.number]) { delete state.open[q.number]; } else { state.open[q.number] = true; }
        var isOpen = !!state.open[q.number];
        wrap.className = "dq" + (isOpen ? " dq-open" : "");
        line.setAttribute("aria-expanded", isOpen ? "true" : "false");
        var old = wrap.querySelector(".dx");
        if (old) { wrap.removeChild(old); }
        if (isOpen) { wrap.appendChild(detail(q)); }
        tell();
      }
      line.addEventListener("click", toggle);
      line.addEventListener("keydown", function (ev) { if (ev.key === "Enter" || ev.key === " ") { ev.preventDefault(); toggle(); } });
      wrap.appendChild(line);
      if (state.open[q.number]) { wrap.appendChild(detail(q)); }
      return wrap;
    }

    function problems(value) {
      var box = make("div", "dp");
      var kinds = [
        { key: "unreadable", words: " record(s) in the store could not be read. Everything else is shown; nothing was skipped silently." },
        { key: "ignored", words: " record(s) were read and changed nothing." },
        { key: "strays", words: " file(s) in the store folder are named like a record and are not part of the list." }
      ];
      for (var k = 0; k < kinds.length; k += 1) {
        var items = value[kinds[k].key] || [];
        if (!items.length) { continue; }
        box.appendChild(make("div", "dp-head", items.length + kinds[k].words));
        for (var i = 0; i < items.length; i += 1) {
          box.appendChild(make("div", "dp-item", (items[i].sequence ? "record " + items[i].sequence + " (" + items[i].file + ")" : items[i].file) + ": " + items[i].reason));
        }
      }
      return box.firstChild ? box : null;
    }

    function tell() {
      var s = snapshot();
      for (var i = 0; i < state.listeners.length; i += 1) { try { state.listeners[i](s); } catch (e) { /* the listener's own problem */ } }
    }

    function draw() {
      var keptTop = scroller.scrollTop;
      while (root.firstChild) { root.removeChild(root.firstChild); }
      state.rows = 0;
      var a = state.answer;
      if (!a) { root.appendChild(make("div", "de", "Reading the list ...")); tell(); return; }
      if (a.state !== "known") { root.appendChild(make("div", "de de-bad", "The list could not be read: " + String(a.reason || "no reason was given"))); tell(); return; }
      if (a.value.outcome !== "done") { root.appendChild(make("div", "de de-bad", "The list was not given: " + String(a.value.reason || ""))); tell(); return; }
      var warn = problems(a.value);
      if (warn) { root.appendChild(warn); }
      var test = FILTERS[state.filter].test;
      var shown = [];
      var all = questions();
      for (var i = 0; i < all.length; i += 1) {
        if (test(all[i]) && (!state.predicate || state.predicate(all[i]))) { shown.push(all[i]); }
      }
      if (!shown.length) {
        root.appendChild(make("div", "de", "No question to show here (" + FILTERS[state.filter].label.toLowerCase() + (state.predicateWhy ? ", " + state.predicateWhy : "") + ")."));
        tell();
        return;
      }
      // Groups in the order of the lowest-numbered question shown in each, as the command line lists them.
      var groups = [];
      var byGroup = {};
      for (i = 0; i < shown.length; i += 1) {
        var g = shown[i].group;
        if (!Object.prototype.hasOwnProperty.call(byGroup, g)) { byGroup[g] = []; groups.push(g); }
        byGroup[g].push(shown[i]);
      }
      for (var gi = 0; gi < groups.length; gi += 1) {
        var mine = byGroup[groups[gi]];
        var head = make("div", "dg");
        head.appendChild(make("span", "dg-t", groups[gi]));
        head.appendChild(make("span", "dg-c", mine.length + (mine.length === 1 ? " question" : " questions")));
        root.appendChild(head);
        var note = "";
        for (i = 0; i < mine.length; i += 1) { if (String(mine[i].groupNote || "").trim() !== "") { note = mine[i].groupNote; break; } }
        if (note) {
          // ONE LINE, opened by a click: a note of several sentences pushed every question under it
          // off a narrow window (seen 2026-10-07: seven lines of note above three questions).
          var noteBox = make("div", "dg-n", note);
          noteBox.title = "Click to read the whole note";
          noteBox.addEventListener("click", function () { this.classList.toggle("dg-n-open"); });
          root.appendChild(noteBox);
        }
        for (i = 0; i < mine.length; i += 1) { root.appendChild(row(mine[i])); state.rows += 1; }
      }
      scroller.scrollTop = keptTop;
      tell();
    }

    draw();
    return {
      setKinds: function (value) { state.kinds = (value && value.kinds) ? value.kinds : {}; draw(); },
      setList: function (answer) {
        // The same answer again is not a change: nothing is redrawn, so nothing the reader is doing is disturbed.
        var json = JSON.stringify(answer === undefined ? null : answer);
        if (json === state.drawnJson) { return; }
        state.drawnJson = json;
        state.answer = answer || null;
        draw();
      },
      setFilter: function (name) { if (FILTERS[name]) { state.filter = name; draw(); } },
      setPredicate: function (fn, why) { state.predicate = (typeof fn === "function") ? fn : null; state.predicateWhy = state.predicate ? String(why || "") : ""; draw(); },
      setOpen: function (numbers) { state.open = {}; for (var i = 0; numbers && i < numbers.length; i += 1) { state.open[numbers[i]] = true; } draw(); },
      onChange: function (fn) { state.listeners.push(fn); },
      snapshot: snapshot,
      questions: questions
    };
  }

  var names = [];
  for (var name in FILTERS) { if (Object.prototype.hasOwnProperty.call(FILTERS, name)) { names.push({ name: name, label: FILTERS[name].label, short: FILTERS[name].short }); } }
  window.HordeDecisionsList = { mount: mount, filters: names };
})();
