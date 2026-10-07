// decisions/window/shell.js - where the list of questions and the fleet panel are put together.
//
// THE ONE PLACE THAT KNOWS BOTH. The list (decisions/page/list.js) draws questions and knows nothing
// of Orcs; the panel (fleet/panel/panel.js) shows Orcs and knows nothing of questions. This file asks
// Horde for both kinds of data through the bridge, hands each part its own, and joins them in two
// small ways: the panel is told how many open questions belong to each of its entries, and the list is
// filtered to the entry the reader picks.
//
// WHICH ENTRY A QUESTION BELONGS TO, so that every question can be reached from the panel:
//   - an Orc's entry, for each name in its "waiting" that the panel knows as an Orc's;
//   - "nobody", when nobody is waiting;
//   - "other", when it was asked by, or is waited on by, someone who is not an Orc.
//
// EVERYTHING COMES THROUGH window.HordeBridge, and through four requests: kinds, list, fleet and
// attachment. A fifth, rendered, tells Horde what is on screen, in numbers, after each draw: that is
// how a script can check the window without looking at it. Horde pushes list-changed, fleet-changed
// and attachment-changed, and the page redraws from what was pushed, never by reloading.
(function () {
  "use strict";

  var bridge = window.HordeBridge;
  var Panel = window.HordeFleetPanel;
  var listRoot = document.getElementById("list");
  var list = window.HordeDecisionsList.mount(listRoot, { scroller: document.getElementById("main") });
  var picked = null;
  // Under 700 pixels the open panel leaves too little of the list: it starts folded to its strip.
  var panel = Panel.mount(document.getElementById("fleet"), { onPick: pick, startFolded: window.innerWidth < 700 });
  var notice = document.getElementById("notice");
  var notices = { attachment: "", bridge: "", list: "" };

  function showNotices() {
    var words = [];
    for (var k in notices) { if (Object.prototype.hasOwnProperty.call(notices, k) && notices[k]) { words.push(notices[k]); } }
    notice.textContent = words.join("  |  ");
    notice.hidden = words.length === 0;
  }

  function keysOf(question) {
    var keys = [];
    var other = Panel.keyOf(question.askedBy) === null;
    for (var i = 0; i < question.waiting.length; i += 1) {
      var key = Panel.keyOf(question.waiting[i]);
      if (key === null) { other = true; } else if (keys.indexOf(key) < 0) { keys.push(key); }
    }
    if (question.waiting.length === 0) { keys.push(Panel.NOBODY); }
    if (other) { keys.push(Panel.OTHER); }
    return keys;
  }

  function pick(key) {
    picked = key;
    var only = document.getElementById("only");
    if (key === null) {
      list.setPredicate(null, "");
      only.hidden = true;
      only.textContent = "";
      return;
    }
    list.setPredicate(function (q) { return keysOf(q).indexOf(key) >= 0; }, "only the picked fleet entry");
    // In a narrow window the open panel covers the list (shell.css): fold it, so the answer to the click shows.
    if (window.innerWidth < 460) { panel.setFolded(true); }
    only.textContent = "Only the picked fleet entry - click it again for all";
    only.hidden = false;
  }

  function countsForPanel() {
    var counts = {};
    var all = list.questions();
    for (var i = 0; i < all.length; i += 1) {
      if (all[i].state !== "open") { continue; }
      var keys = keysOf(all[i]);
      for (var k = 0; k < keys.length; k += 1) { counts[keys[k]] = (counts[keys[k]] || 0) + 1; }
    }
    return counts;
  }

  function applyList(answer) {
    list.setList(answer);
    panel.setCounts(countsForPanel());
    var s = list.snapshot();
    document.getElementById("counts").textContent = s.open + " open, " + s.waiting + " waiting" + (s.closed ? ", " + s.closed + " closed" : "");
    report();
  }

  function applyAttachment(value) {
    notices.attachment = (value && value.attached === false && value.reason) ? "not attached: " + value.reason : "";
    showNotices();
  }

  var lastReport = "";
  function report() {
    if (!bridge || !bridge.live) { return; }
    var s = list.snapshot();
    var p = panel.snapshot();
    var args = { rows: s.rows, open: s.open, closed: s.closed, waiting: s.waiting, expanded: s.expanded, entries: p.entries, written: p.written, filter: s.filter, picked: picked === null ? "" : picked };
    var json = JSON.stringify(args);
    if (json === lastReport) { return; }
    lastReport = json;
    bridge.request("rendered", args).catch(function () { lastReport = ""; });
  }

  function failed(what) {
    return function (error) { notices.bridge = what + " could not be had: " + String(error && error.message ? error.message : error); showNotices(); };
  }

  // The filters, from the list's own table: a filter added there appears here.
  var filterBox = document.getElementById("filters");
  window.HordeDecisionsList.filters.forEach(function (f, index) {
    var b = document.createElement("button");
    b.type = "button";
    b.className = "sb";
    b.textContent = f.short;
    b.title = f.label;
    b.setAttribute("aria-pressed", index === 0 ? "true" : "false");
    b.addEventListener("click", function () {
      var all = filterBox.querySelectorAll("button");
      for (var i = 0; i < all.length; i += 1) { all[i].setAttribute("aria-pressed", all[i] === b ? "true" : "false"); }
      list.setFilter(f.name);
    });
    filterBox.appendChild(b);
  });

  // The panel folds itself; the frame gives it the room it then needs.
  var fleetRoot = document.getElementById("fleet");
  function fitFleet() { document.body.classList.toggle("fleet-folded", fleetRoot.classList.contains("fp-collapsed")); }
  new MutationObserver(fitFleet).observe(fleetRoot, { attributes: true, attributeFilter: ["class"] });
  fitFleet();

  list.onChange(report);

  if (!bridge || !bridge.live) {
    notices.bridge = "This page is not being shown by Horde, so there is no list to show. Open it with: horde decisions open";
    showNotices();
    return;
  }
  bridge.on("list-changed", applyList);
  bridge.on("fleet-changed", function (status) { panel.update(status); report(); });
  bridge.on("attachment-changed", applyAttachment);
  // SHOW: Horde says what the page should show - a filter, which rows are opened, which fleet entry is
  // picked, whether the panel is folded. Each member is optional; one that is absent changes nothing.
  bridge.on("show", function (v) {
    if (!v || typeof v !== "object") { return; }
    if (typeof v.filter === "string") {
      var buttons = filterBox.querySelectorAll("button");
      window.HordeDecisionsList.filters.forEach(function (f, i) { if (f.name === v.filter) { buttons[i].click(); } });
    }
    if (v.expanded && typeof v.expanded.length === "number") { list.setOpen(v.expanded); }
    if (typeof v.folded === "boolean") { panel.setFolded(v.folded); }
    if (typeof v.picked === "string") { var key = v.picked === "" ? null : v.picked; panel.setPicked(key); pick(key); }
    report();
  });
  bridge.request("kinds", {}).then(function (answer) { if (answer && answer.state === "known") { list.setKinds(answer.value); } }, failed("The kinds of question"));
  bridge.request("list", {}).then(applyList, failed("The list"));
  bridge.request("fleet", {}).then(function (status) { panel.update(status); report(); }, failed("The fleet's status"));
  bridge.request("attachment", {}).then(applyAttachment, failed("Where this window stands"));
})();
