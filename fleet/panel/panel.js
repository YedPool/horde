// fleet/panel/panel.js - the fleet panel: each Orc's own account of what it is doing, beside whatever
// page hosts it.
//
// ITS ONE JOB is to show the data fleet/StatusPanel.ps1 reads, and to say which entry the reader
// picked. It knows nothing of questions: the page that hosts it hands it a count per entry and is
// told the picked entry's key, and what a count counts is that page's business.
//
//   var panel = HordeFleetPanel.mount(element, { onPick: function (keyOrNull) { } });
//   panel.update(status)       the value of the fleet request: { state, reason, orcs: [...] }
//   panel.setCounts(counts)    { "<key>": number }: how many of the host's items belong to each entry
//   panel.setPicked(key)       which entry is picked, or null
//   panel.setFolded(bool)      folded to its strip, or open
//   panel.snapshot()           { entries, written }: what is on screen, as numbers
//   HordeFleetPanel.keyOf(name)  the key of the entry a name such as "Orc D (test deploy)" belongs to,
//                                or null when the name is not an Orc's
//   HordeFleetPanel.OTHER, HordeFleetPanel.NOBODY   the keys of the two entries that are not Orcs
//
// WHAT IT SHOWS IS ONLY WHAT THE STATUS FILES AND THE HOST'S COUNTS SAY. Working or idle comes from
// the fleet's activity, which this panel is not given yet, and it says so rather than guess. A folder
// with no record, or a record that broke a rule, is "no status written".
//
// A STATE IS NEVER SHOWN BY COLOUR ALONE: every entry carries a mark - ! blocked, ? something waits
// on the reader, - nothing waits, x no status written - and the words beside it.
//
// EVERY TEXT IS SET AS TEXT (textContent). Nothing a status file or a name holds is ever read as markup.
(function () {
  "use strict";

  var OTHER = "other";
  var NOBODY = "nobody";
  var ORC_NAME = /^Orc ([A-Z])(?![A-Za-z])/;

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
    if (seconds < 90) { return "written just now"; }
    if (seconds < 5400) { return "written " + Math.round(seconds / 60) + " min ago"; }
    if (seconds < 172800) { return "written " + Math.round(seconds / 3600) + " h ago"; }
    return "written " + Math.round(seconds / 86400) + " days ago";
  }

  function mount(root, options) {
    var onPick = (options && typeof options.onPick === "function") ? options.onPick : function () {};
    var state = { status: null, counts: {}, picked: null, collapsed: false, entries: 0, written: 0 };
    // FOLDED TO BEGIN WITH WHERE IT WOULD EAT THE PAGE (options.startFolded): beside a narrow list the
    // open panel took a third of the width and left the questions cut short (seen 2026-10-07, in a
    // picture of the window at 567 pixels wide). What the reader last chose, if anything, wins.
    state.collapsed = !!(options && options.startFolded);
    try {
      var kept = window.localStorage.getItem("horde.fleet.collapsed");
      if (kept === "1") { state.collapsed = true; } else if (kept === "0") { state.collapsed = false; }
    } catch (e) { /* nothing was remembered */ }

    function entriesOf() {
      var out = [];
      var seen = {};
      var orcs = (state.status && state.status.state === "read" && state.status.orcs) ? state.status.orcs : [];
      var i;
      for (i = 0; i < orcs.length; i += 1) {
        var o = orcs[i];
        var key = o.written ? "orc:" + o.orc : "folder:" + o.folder;
        seen[key] = true;
        out.push({ key: key, letter: o.written ? o.orc : "?", name: o.written ? o.lane : o.folder, record: o });
      }
      // An Orc the host counts something for and no folder speaks for still gets an entry, so that
      // everything the host counted can be reached.
      var keys = Object.keys(state.counts).sort();
      for (i = 0; i < keys.length; i += 1) {
        if (keys[i].indexOf("orc:") === 0 && !seen[keys[i]] && state.counts[keys[i]] > 0) {
          out.push({ key: keys[i], letter: keys[i].slice(4), name: "Orc " + keys[i].slice(4), record: null });
        }
      }
      out.push({ key: OTHER, letter: "W", name: "Warchief and others", record: null, fixed: "Asked by, or waited on by, a session that is not an Orc." });
      out.push({ key: NOBODY, letter: "0", name: "Nobody is waiting", record: null, fixed: "Questions nobody is blocked on." });
      return out;
    }

    function markOf(entry, count) {
      if (entry.fixed) { return count > 0 ? { mark: "?", words: count + " for you" } : { mark: "-", words: "none" }; }
      if (!entry.record || !entry.record.written) { return { mark: "x", words: "no status written" }; }
      if (entry.record.blocked) { return { mark: "!", words: "blocked" }; }
      if (count > 0) { return { mark: "?", words: count + " waiting on you" }; }
      return { mark: "-", words: "nothing waiting on you" };
    }

    function render() {
      while (root.firstChild) { root.removeChild(root.firstChild); }
      root.className = "fp" + (state.collapsed ? " fp-collapsed" : "");
      var head = make("div", "fp-head");
      var toggle = make("button", "fp-toggle", state.collapsed ? "<<" : ">>");
      toggle.type = "button";
      toggle.title = state.collapsed ? "Open the fleet panel" : "Fold the fleet panel to a strip";
      toggle.setAttribute("aria-expanded", state.collapsed ? "false" : "true");
      toggle.addEventListener("click", function () {
        state.collapsed = !state.collapsed;
        try { window.localStorage.setItem("horde.fleet.collapsed", state.collapsed ? "1" : "0"); } catch (e) { /* not remembered */ }
        render();
      });
      head.appendChild(toggle);
      if (!state.collapsed) { head.appendChild(make("span", "fp-title", "Fleet")); }
      root.appendChild(head);

      var status = state.status;
      if (!state.collapsed && status && status.state !== "read") {
        root.appendChild(make("div", "fp-note", status.state === "not-configured" ? "No folder of status records is set up on this machine, so no Orc is listed." : "The status records could not be read: " + String(status.reason || "")));
      }
      var entries = entriesOf();
      state.entries = entries.length;
      state.written = 0;
      var list = make("div", "fp-list");
      entries.forEach(function (entry) {
        var count = state.counts[entry.key] || 0;
        var m = markOf(entry, count);
        if (entry.record && entry.record.written) { state.written += 1; }
        var b = make("button", "fp-entry fp-" + (m.mark === "!" ? "blocked" : m.mark === "?" ? "waiting" : m.mark === "x" ? "none" : "quiet"));
        b.type = "button";
        b.setAttribute("aria-pressed", state.picked === entry.key ? "true" : "false");
        b.setAttribute("aria-label", entry.name + ": " + m.words + (count > 0 ? ", " + count + " question(s)" : ""));
        b.addEventListener("click", function () {
          state.picked = (state.picked === entry.key) ? null : entry.key;
          render();
          onPick(state.picked);
        });
        var line1 = make("span", "fp-l1");
        line1.appendChild(make("span", "fp-letter", entry.letter));
        line1.appendChild(make("span", "fp-mark", m.mark));
        if (state.collapsed) {
          line1.appendChild(make("span", "fp-count", count > 0 ? String(count) : ""));
          b.title = entry.name + ": " + m.words;
          b.appendChild(line1);
          list.appendChild(b);
          return;
        }
        line1.appendChild(make("span", "fp-name", entry.name));
        line1.appendChild(make("span", "fp-count", count > 0 ? count + " q" : ""));
        b.appendChild(line1);
        if (entry.fixed) {
          b.appendChild(make("span", "fp-l2", entry.fixed));
        } else if (!entry.record) {
          b.appendChild(make("span", "fp-l2", "no status written: no folder speaks for this Orc"));
        } else if (!entry.record.written) {
          b.appendChild(make("span", "fp-l2", "no status written"));
          var why = (entry.record.problems && entry.record.problems.length) ? entry.record.problems[0] : "";
          if (why) { b.appendChild(make("span", "fp-l3", "(" + why + ")")); }
        } else {
          if (entry.record.blocked) { b.appendChild(make("span", "fp-l2 fp-why", "blocked: " + entry.record.blockedBy)); }
          b.appendChild(make("span", "fp-l2", "doing: " + entry.record.doing));
          b.appendChild(make("span", "fp-l3", "finished: " + entry.record.finished));
          b.appendChild(make("span", "fp-l3", ageWords(entry.record.ageSeconds)));
        }
        list.appendChild(b);
      });
      root.appendChild(list);
      if (!state.collapsed) {
        root.appendChild(make("div", "fp-foot", "Only what each Orc's status file and this list say; working or idle is not shown yet. ! blocked, ? waiting on you, - nothing waiting, x no status written."));
      }
    }

    render();
    return {
      update: function (status) { state.status = status || null; render(); },
      setCounts: function (counts) { state.counts = counts || {}; render(); },
      setPicked: function (key) { state.picked = key || null; render(); },
      setFolded: function (folded) { state.collapsed = !!folded; render(); },
      snapshot: function () { return { entries: state.entries, written: state.written }; }
    };
  }

  window.HordeFleetPanel = { mount: mount, keyOf: keyOf, OTHER: OTHER, NOBODY: NOBODY };
})();
