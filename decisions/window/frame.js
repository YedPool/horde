// decisions/window/frame.js - where the list of questions and the fleet line are put together.
//
// THE ONE PLACE THAT KNOWS BOTH. The document (decisions/page/list.js) draws questions and knows
// nothing of Orcs; the fleet line (fleet/line/line.js) shows Orcs and knows nothing of questions. This
// file asks Horde for both kinds of data through the bridge, hands each part its own, and joins them
// in two small ways: the line is told how many open questions wait for each of its entries, and the
// document DIMS - never hides - the questions that are not the picked entry's.
//
// EVERYTHING DRAWN COMES THROUGH window.HordeBridge, by the closed list of requests the window's
// composer keeps (decisions/Window.ps1): setup, kinds, list, fleet, attachment, and say - the reader's
// words under a question, handed to Horde to be stored, answered with whether they were. A seventh, report,
// tells Horde WHAT THE PAGE DREW after each change - every question line's number and text as they
// stand in the page, the headings, what is unfolded, the fleet line, and the computed size of the
// letters - so that a script can hold the page to the list without looking at it. Horde pushes
// list-changed, fleet-changed and attachment-changed, and the page redraws from what was pushed,
// never by reloading.
//
// THIS FILE CARRIES NO NUMBER OF ITS OWN. The letters' family and sizes, and the bounds of a report,
// are the composer's and arrive in the answer to setup.
//
// EVERY TEXT IS SET AS TEXT (textContent).
(function () {
  "use strict";

  var bridge = window.HordeBridge;
  var Fleet = window.HordeFleetLine;
  var root = document.documentElement;
  var topBar = document.getElementById("top");
  var noticeBox = document.getElementById("notice");
  var foot = document.getElementById("foot");
  var menu = document.getElementById("menu");
  var menuBtn = document.getElementById("menuBtn");
  var setup = null;
  var draws = 0;
  var picked = null;
  var open = [];
  var reportTimer = null;
  var notices = { bridge: "", settings: "", attachment: "", list: "", drafts: "" };
  // The last set of a check's steps the page has acted out (decisions/Window.ps1, -Probe).
  var probed = 0;

  var doc = window.HordeDecisionsDocument.mount(document.getElementById("list"), {
    topInset: function () { return topBar.getBoundingClientRect().bottom; },
    onDraw: function () { draws += 1; report(); },
    onChange: function () { report(); },
    say: function (number, text, wording, id) { return bridge.request("say", { number: number, text: text, wording: wording, id: id }); }
  });
  var fleet = Fleet.mount(document.getElementById("fleet"), { countWords: "waiting on you", onPick: pick, onChange: report });

  function showNotices() {
    while (noticeBox.firstChild) { noticeBox.removeChild(noticeBox.firstChild); }
    var any = false;
    Object.keys(notices).forEach(function (k) {
      if (!notices[k]) { return; }
      var line = document.createElement("div");
      line.textContent = notices[k];
      noticeBox.appendChild(line);
      any = true;
    });
    noticeBox.hidden = !any;
  }

  // Which of the line's entries a question belongs to: each Orc that waits for it, and the Orc that
  // asked it.
  function keysOf(question) {
    var keys = [];
    (question.waiting || []).concat([question.askedBy]).forEach(function (name) {
      var key = Fleet.keyOf(name);
      if (key !== null && keys.indexOf(key) < 0) { keys.push(key); }
    });
    return keys;
  }

  function pick(key) {
    picked = key || null;
    doc.setDim(picked ? function (q) { return keysOf(q).indexOf(picked) < 0; } : null);
    report();
  }

  function countsOf() {
    // A map with no prototype: a key is made from a name a session wrote.
    var counts = Object.create(null);
    open.forEach(function (q) {
      (q.waiting || []).forEach(function (name) {
        var key = Fleet.keyOf(name);
        if (key !== null) { counts[key] = (counts[key] || 0) + 1; }
      });
    });
    return counts;
  }

  // THE LETTERS, IN WHOLE DEVICE PIXELS (frame.css says why). A CSS pixel is devicePixelRatio of the
  // screen's own; each size is moved to the nearest that is a whole number of those.
  function applyLook() {
    if (!setup) { return; }
    var ratio = window.devicePixelRatio || 1;
    function whole(px) { return (Math.round(px * ratio) / ratio) + "px"; }
    root.style.setProperty("--font", setup.look.fontFamily);
    root.style.setProperty("--text-px", whole(setup.look.textPx));
    root.style.setProperty("--line-px", whole(setup.look.linePx));
    root.style.setProperty("--small-px", whole(setup.look.smallTextPx));
    root.style.setProperty("--small-line-px", whole(setup.look.smallLinePx));
  }

  function showList(record) {
    if (record && record.state === "known" && record.value && record.value.outcome !== "done") { record = { state: "unknown", reason: record.value.reason }; }
    var did = doc.setList(record);
    if (did === "unread") { notices.list = "The list could not be read, so what is shown may be old: " + ((record && record.reason) ? record.reason : "no reason was given"); }
    else {
      var torn = (record.value.unreadable || []).length;
      notices.list = torn ? (torn + (torn === 1 ? " record" : " records") + " of the list could not be read; horde decisions list names " + (torn === 1 ? "it" : "them") + ".") : "";
    }
    if (did === "drawn") {
      open = record.value.questions.filter(function (q) { return q.state === "open"; });
      var counts = doc.counts();
      document.getElementById("counts").textContent = counts.open + " open, " + counts.waiting + " waiting";
      fleet.setCounts(countsOf());
    }
    showNotices();
    report();
  }

  function showAttachment(a) {
    notices.attachment = (a && a.attached) ? "" : ("Standing free: " + ((a && a.reason) ? a.reason : "no terminal window was found to stand beside"));
    showNotices();
    report();
  }

  // What the reader was asked to be shown at the start (the command's own flags): questions unfolded,
  // the fleet line unfolded, one Orc picked.
  function applyView(view) {
    if (!view) { return; }
    if (view.unfold && view.unfold.length) { doc.setUnfolded(view.unfold); }
    if (view.fleetOpen) { fleet.setOpen(true); }
    if (view.pick) { fleet.setPicked("orc:" + view.pick); pick("orc:" + view.pick); }
    // The first question asked for is the one the reader was pointed at: it is brought into view.
    if (view.unfold && view.unfold.length) { doc.reveal(view.unfold[0]); }
  }

  // WHAT THE PAGE DREW, a moment after the last change so that a burst of them is one report. It is
  // bounded by the composer's numbers: so many lines, so many characters of each, and so many
  // characters in all once it is written as the text of a message; what does not fit is left out
  // from the end and counted in "left".
  function report() {
    if (reportTimer !== null || !setup) { return; }
    reportTimer = window.setTimeout(function () { reportTimer = null; sendReport(); }, setup.report.quietMs);
  }
  function sendReport() {
    var bounds = setup.report;
    var snap = doc.snapshot({ lines: bounds.lines, subLines: bounds.subLines, lineChars: bounds.lineChars });
    var line = fleet.snapshot(bounds.fleetRows);
    var letters = doc.measure();
    var small = window.getComputedStyle(foot);
    snap.answer.probe = probed;
    if (notices.drafts !== snap.answer.storage) { notices.drafts = snap.answer.storage; showNotices(); }
    var value = {
      v: 1, draws: draws, counts: doc.counts(), headings: snap.headings, lines: snap.lines, sub: snap.sub, answer: snap.answer,
      fleet: { open: line.open, picked: line.picked, head: line.head.slice(0, bounds.textChars), rows: line.rows.map(function (r) { return r.slice(0, bounds.lineChars); }), entries: line.entries, written: line.written, notRead: line.notRead },
      notice: noticeBox.textContent.slice(0, bounds.textChars), foot: foot.textContent.slice(0, bounds.lineChars),
      text: {
        fontPx: letters ? letters.fontPx : null, linePx: letters ? letters.linePx : null, weight: letters ? letters.weight : "",
        smallFontPx: parseFloat(small.fontSize), smallLinePx: parseFloat(small.lineHeight),
        ratio: window.devicePixelRatio || 1, family: window.getComputedStyle(document.body).fontFamily.slice(0, bounds.lineChars)
      },
      left: { lines: snap.left.lines, sub: snap.left.sub, fleetRows: line.left }
    };
    var text = JSON.stringify(value);
    // As the text of a message every quote in it is two characters: measured as it will be sent.
    while (JSON.stringify(text).length > bounds.chars && (value.sub.length || value.lines.length || value.fleet.rows.length)) {
      if (value.sub.length) { value.sub.pop(); value.left.sub += 1; }
      else if (value.fleet.rows.length) { value.fleet.rows.pop(); value.left.fleetRows += 1; }
      else { value.lines.pop(); value.left.lines += 1; }
      text = JSON.stringify(value);
    }
    bridge.request("report", { text: text }).catch(function () { /* Horde keeps its own record of a refusal */ });
  }

  function setMenu(shown) {
    menu.hidden = !shown;
    menuBtn.setAttribute("aria-expanded", shown ? "true" : "false");
  }
  menuBtn.addEventListener("click", function (e) { e.stopPropagation(); setMenu(menu.hidden); });
  document.addEventListener("click", function (e) { if (!menu.hidden && !menu.contains(e.target)) { setMenu(false); } });
  document.addEventListener("keydown", function (e) { if (e.key === "Escape") { setMenu(false); } });
  document.getElementById("unfoldAll").addEventListener("click", function () { doc.unfoldAll(); setMenu(false); });
  document.getElementById("foldAll").addEventListener("click", function () { doc.foldAll(); setMenu(false); });
  // A window moved to a screen of another scale is resized by the system: the sizes are worked out again.
  window.addEventListener("resize", function () { applyLook(); report(); });

  if (!bridge) {
    notices.bridge = "This page is not being shown by Horde, so there is no list to show.";
    showNotices();
    return;
  }
  bridge.on("list-changed", showList);
  bridge.on("fleet-changed", function (status) { fleet.update(status); });
  bridge.on("attachment-changed", showAttachment);
  bridge.on("probe", function (probe) {
    if (!probe || typeof probe.n !== "number") { return; }
    doc.drive(probe.steps).then(function () { probed = probe.n; report(); });
  });
  bridge.request("setup").then(function (answer) {
    setup = answer;
    applyLook();
    doc.setParked(answer.foldedGroups);
    notices.settings = (answer.findings && answer.findings.length) ? ("Settings: " + answer.findings.join(" ")) : "";
    return Promise.all([bridge.request("kinds"), bridge.request("list"), bridge.request("fleet"), bridge.request("attachment")]);
  }).then(function (answers) {
    doc.setKinds(answers[0]);
    showList(answers[1]);
    fleet.update(answers[2]);
    showAttachment(answers[3]);
    applyView(setup.view);
    // Shown with the keyboard already its own: the caret goes where a window given it later puts it.
    if (document.hasFocus()) { doc.takeKeyboard(); }
    report();
  }).catch(function (e) {
    notices.bridge = "This page could not ask Horde for the list: " + (e && e.message ? e.message : e);
    showNotices();
  });
}());
