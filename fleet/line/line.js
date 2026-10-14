// fleet/line/line.js - the fleet line: each Orc's own account of what it is doing, as one folded line
// at the foot of whatever page hosts it, unfolding to a line per Orc.
//
// ITS ONE JOB is to show the data fleet/StatusPanel.ps1 reads, and to say which entry the reader
// picked. It knows nothing of what the page above it lists: the page hands it a count per entry and
// the words for that count, and is told the picked entry's key. What a count counts, and what the
// page does about a pick, are that page's business.
//
//   var line = HordeFleetLine.mount(element, { countWords: "waiting on you", onPick: function (keyOrNull) { },
//                                             onChange: function () { } });   onChange after every draw
//   line.update(status)        the value of the fleet request: { state, reason, orcs, notRead, findings }
//   line.setCounts(counts)     a map from an entry's key to how many of the host's items are its
//   line.setPicked(keyOrNull)  which entry is picked; line.setOpen(bool) folded or unfolded
//   line.snapshot(mostRows)    what is drawn, as text: { open, picked, head, rows, entries, written, notRead, left,
//                              headLines, headClipped, rowsLines }: how many lines the folded line and the
//                              rows are laid out on, and whether the folded line is cut short at its end
//   HordeFleetLine.keyOf(name) the key of the entry a name such as "Orc D (test deploy)" belongs to,
//                              or null when the name is not an Orc's
//
// WHAT IT SHOWS IS ONLY WHAT THE STATUS FILES AND THE HOST'S COUNTS SAY. Working or idle comes from
// the fleet's activity, which this part is not given, so it does not say either. A folder with no
// record, or a record that broke a rule, is "no status written" with what was wrong. Folders past the
// most that are read are counted and said.
//
// A STATE IS SAID IN WORDS, never by colour alone. PICKING AN ENTRY HIDES NOTHING HERE: every Orc's
// line stays; the picked one is underlined and its weight is 600.
//
// EVERY TEXT IS SET AS TEXT (textContent). Nothing a status file or a name holds is ever read as markup.
(function () {
  "use strict";

  // An Orc is named by one capital letter after the word, as the status record's own rule has it.
  var ORC_NAME = /^Orc ([A-Z])(?![A-Za-z])/;
  // HOW AN AGE IS WORDED. Named here and not settings: they choose between "just now", minutes, hours
  // and days, so that each number shown is a small one, and change nothing a person would tune. Under
  // a minute and a half is "just now"; under an hour and a half, minutes; under two days, hours.
  var AGE_JUST_NOW_BELOW_S = 90;
  var AGE_MINUTES_BELOW_S = 5400;
  var AGE_HOURS_BELOW_S = 172800;

  function keyOf(name) {
    var m = ORC_NAME.exec(String(name === null || name === undefined ? "" : name));
    return m ? "orc:" + m[1] : null;
  }

  function make(tag, className, text) {
    var node = document.createElement(tag);
    if (className) { node.className = className; }
    if (text !== undefined && text !== null) { node.textContent = String(text); }
    return node;
  }

  function ageWords(seconds) {
    if (typeof seconds !== "number" || seconds < 0) { return ""; }
    if (seconds < AGE_JUST_NOW_BELOW_S) { return "written just now"; }
    if (seconds < AGE_MINUTES_BELOW_S) { return "written " + Math.round(seconds / 60) + " min ago"; }
    if (seconds < AGE_HOURS_BELOW_S) { return "written " + Math.round(seconds / 3600) + " h ago"; }
    return "written " + Math.round(seconds / 86400) + " days ago";
  }

  // HOW MANY LINES A NODE'S TEXT IS LAID OUT ON, as the engine laid it out: the boxes of its text and
  // its buttons, grouped by their middles, a new line wherever a middle is more than half the smallest
  // box below the last. A node that is not shown (a row while the line is folded) is on none.
  function linesOf(node) {
    if (!node || !node.firstChild || node.getClientRects().length === 0) { return 0; }
    var range = document.createRange();
    range.selectNodeContents(node);
    var boxes = range.getClientRects();
    var mids = [], least = Infinity, i;
    for (i = 0; i < boxes.length; i += 1) {
      if (boxes[i].height > 0 && boxes[i].width > 0) { mids.push((boxes[i].top + boxes[i].bottom) / 2); least = Math.min(least, boxes[i].height); }
    }
    mids.sort(function (a, b) { return a - b; });
    var lines = 0, last = -Infinity;
    for (i = 0; i < mids.length; i += 1) { if (mids[i] - last > least / 2) { lines += 1; last = mids[i]; } }
    return lines;
  }

  function mount(root, options) {
    var onPick = (options && typeof options.onPick === "function") ? options.onPick : function () {};
    var countWords = (options && options.countWords) ? String(options.countWords) : "";
    var onChange = (options && typeof options.onChange === "function") ? options.onChange : function () {};
    // counts is a map with no prototype: a key is text from a name, and "constructor" is a name.
    var state = { status: null, counts: Object.create(null), picked: null, open: false };
    var drawn = { head: "", rows: [], entries: 0, written: 0, notRead: 0, headNode: null, rowNodes: [] };

    function entriesOf() {
      var out = [];
      var seen = Object.create(null);
      var orcs = (state.status && state.status.state === "read" && state.status.orcs) ? state.status.orcs : [];
      var i, key;
      for (i = 0; i < orcs.length; i += 1) {
        key = orcs[i].written ? "orc:" + orcs[i].orc : "folder:" + orcs[i].folder;
        seen[key] = true;
        out.push({ key: key, name: orcs[i].written ? orcs[i].orc : orcs[i].folder, record: orcs[i] });
      }
      // An Orc the host counts for and no status file speaks for still has an entry, saying so.
      var extra = [];
      for (key in state.counts) { if (!seen[key] && key.indexOf("orc:") === 0 && state.counts[key] > 0) { extra.push(key); } }
      extra.sort();
      for (i = 0; i < extra.length; i += 1) { out.push({ key: extra[i], name: extra[i].slice(4), record: null }); }
      return out;
    }

    // The folded line names only the Orcs whose record was read (draw), so an entry here always has one.
    function stateWords(entry) {
      var count = state.counts[entry.key] || 0;
      var words = [];
      if (entry.record.blocked) { words.push("blocked"); }
      if (count > 0 && countWords) { words.push(countWords + " (" + count + ")"); }
      return words.join(", ");
    }

    // A record's line may or may not end its own sentence. One of the eight real records read
    // 2026-10-07 did, and with a full stop always added a picture of the real window showed "every
    // installer branch.. Last finished:". A full stop is added only where the words have no end.
    function sentence(text) {
      var words = String(text);
      return /[.!?]$/.test(words) ? words : words + ".";
    }

    function rowWords(entry) {
      var r = entry.record;
      if (!r) { return ": no status written (no folder of status records is this Orc's)"; }
      if (!r.written) { return ": no status written (" + (r.problems || []).join("; ") + ")"; }
      var words = " (" + r.lane + "): " + sentence(r.doing) + " Last finished: " + sentence(r.finished);
      // THE OPTIONAL SEVENTH LINE of the record (fleet/StatusPanel.ps1): the field is absent when the
      // Orc wrote none, and then nothing is said of waiting.
      if (typeof r.waitingOn === "string" && r.waitingOn !== "") { words += " Waiting on: " + sentence(r.waitingOn); }
      if (r.blocked) { words += " Blocked: " + sentence(r.blockedBy); }
      var age = ageWords(r.ageSeconds);
      return words + (age ? " (" + age + ")" : "");
    }

    function nameButton(entry, label) {
      var on = state.picked === entry.key;
      var b = make("button", "fl-orc" + (on ? " on" : ""), label);
      b.type = "button";
      b.setAttribute("aria-pressed", on ? "true" : "false");
      b.addEventListener("click", function () { api.setPicked(on ? null : entry.key); onPick(state.picked); });
      return b;
    }

    function draw() {
      while (root.firstChild) { root.removeChild(root.firstChild); }
      root.className = "fl" + (state.open ? " open" : "");
      var status = state.status;
      var entries = entriesOf();
      var head = make("div", "fl-head");
      var lead = make("button", "fl-lead", "Fleet:");
      lead.type = "button";
      lead.setAttribute("aria-expanded", state.open ? "true" : "false");
      lead.addEventListener("click", function () { api.setOpen(!state.open); });
      head.appendChild(lead);
      var rows = [];
      var notRead = (status && typeof status.notRead === "number") ? status.notRead : 0;
      if (!status) { head.appendChild(document.createTextNode(" not read yet")); }
      else if (status.state !== "read" && entries.length === 0) { head.appendChild(document.createTextNode(" " + status.reason)); }
      // THE FOLDED LINE IS ONE LINE (the owner, 2026-10-07): it names each Orc whose record was read,
      // and only COUNTS the entries with none. Measured the same day in a picture of the real window,
      // 980 device pixels wide: eight folders with no status file and four Orcs the list names made the
      // line seven lines long, each "no status written". Unfolded, every entry still has its own row.
      var i, words, said = 0, without = 0;
      for (i = 0; i < entries.length; i += 1) {
        if (!entries[i].record || !entries[i].record.written) { without += 1; continue; }
        head.appendChild(document.createTextNode(said ? ", " : " "));
        head.appendChild(nameButton(entries[i], entries[i].name));
        words = stateWords(entries[i]);
        if (words) { head.appendChild(document.createTextNode(" " + words)); }
        said += 1;
      }
      if (without > 0) { head.appendChild(document.createTextNode((said ? ", " : " ") + without + " without status")); }
      if (notRead > 0) { head.appendChild(document.createTextNode((entries.length ? ", and " : " ") + notRead + " more not read")); }
      root.appendChild(head);
      var rowNodes = [];
      function addRow(node) { node.className = "fl-row"; root.appendChild(node); rows.push(node.textContent); rowNodes.push(node); }
      var row;
      for (i = 0; i < entries.length; i += 1) {
        row = make("div");
        row.appendChild(nameButton(entries[i], (entries[i].record && !entries[i].record.written ? "" : "Orc ") + entries[i].name));
        row.appendChild(document.createTextNode(rowWords(entries[i])));
        addRow(row);
      }
      if (status && status.state !== "read" && entries.length > 0) { addRow(make("div", "", status.reason)); }
      if (notRead > 0) { addRow(make("div", "", notRead + " more folders were not read: the most that are read is a setting of the fleet module.")); }
      var findings = (status && status.findings) ? status.findings : [];
      for (i = 0; i < findings.length; i += 1) { addRow(make("div", "", "Settings: " + findings[i])); }
      var written = 0;
      for (i = 0; i < entries.length; i += 1) { if (entries[i].record && entries[i].record.written) { written += 1; } }
      drawn = { head: head.textContent, rows: rows, entries: entries.length, written: written, notRead: notRead, headNode: head, rowNodes: rowNodes };
      onChange();
    }

    var api = {
      update: function (status) { state.status = status || null; draw(); },
      setCounts: function (counts) {
        state.counts = Object.create(null);
        for (var k in counts) { state.counts[k] = counts[k]; }
        draw();
      },
      setPicked: function (key) { state.picked = key || null; draw(); },
      setOpen: function (open) { state.open = !!open; draw(); },
      snapshot: function (mostRows) {
        var most = (typeof mostRows === "number") ? mostRows : drawn.rows.length;
        var rowsLines = 0;
        for (var i = 0; i < drawn.rowNodes.length; i += 1) { rowsLines += linesOf(drawn.rowNodes[i]); }
        var h = drawn.headNode;
        return { open: state.open, picked: state.picked || "", head: drawn.head, rows: drawn.rows.slice(0, most), entries: drawn.entries, written: drawn.written, notRead: drawn.notRead, left: Math.max(0, drawn.rows.length - most),
                 headLines: linesOf(h), headClipped: !!(h && h.scrollWidth > h.clientWidth + 1), rowsLines: rowsLines };
      }
    };
    draw();
    return api;
  }

  window.HordeFleetLine = { mount: mount, keyOf: keyOf };
}());
