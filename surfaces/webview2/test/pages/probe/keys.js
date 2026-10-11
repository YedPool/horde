// surfaces/webview2/test/pages/probe/keys.js - the page a check presses real keys on. It counts every
// key press it sees, split by whether the engine vouches for it (isTrusted), and reports, when it is
// asked, the counts, what the field holds and whether the field has the keyboard. Before anything is
// pressed it makes one key press of its own, by script: the control that an event a script makes is
// counted as not trusted.
(function () {
  "use strict";
  var B = window.HordeBridge;
  var field = document.getElementById("field");
  var trusted = 0;
  var untrusted = 0;
  var keys = [];
  document.addEventListener("keydown", function (e) {
    if (e.isTrusted) { trusted += 1; keys.push(e.key); } else { untrusted += 1; }
  }, true);
  B.on("report", function () {
    B.request("seen", { trusted: trusted, untrusted: untrusted, pressed: keys.join(","), value: field.value, focused: document.hasFocus() && document.activeElement === field });
  });
  field.focus();
  document.dispatchEvent(new KeyboardEvent("keydown", { key: "x", bubbles: true }));
  B.request("ready", {});
})();
