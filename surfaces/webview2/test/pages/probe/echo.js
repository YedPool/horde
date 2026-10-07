// surfaces/webview2/test/pages/probe/echo.js - a page that only talks: one request, one refused
// request, and whatever event it is pushed handed straight back. It names no member of any message:
// if the bridge under it and the port behind it did not read one definition, nothing here would cross.
(function () {
  "use strict";
  var B = window.HordeBridge;
  B.on("poke", function (value) { B.request("echo", { text: "pushed " + value }); });
  B.request("echo", { text: "hello" })
    .then(function (answer) { return B.request("not-on-the-list", {}).then(function () { return "ANSWERED"; }, function (e) { return "rejected: " + e.message; }).then(function (seen) { return B.request("echo", { text: answer + " | " + seen }); }); })
    .then(function () { document.getElementById("status").textContent = "talked"; return B.request("done", {}); });
})();
