// surfaces/webview2/test/pages/probe/echo.js - a page that only talks: one request, one refused
// request, whatever event it is pushed handed straight back, and a burst when it is told to make
// one. It names no member of any message:
// if the bridge under it and the port behind it did not read one definition, nothing here would cross.
(function () {
  "use strict";
  var B = window.HordeBridge;
  B.on("poke", function (value) { B.request("echo", { text: "pushed " + value }); });
  // The one hostile thing this page does: told to, it posts that many messages at once behind the
  // bridge's back, then asks one honest request a second and a half later.
  B.on("burst", function (count) {
    for (var k = 0; k < count; k += 1) { window.chrome.webview.postMessage({ junk: k }); }
    setTimeout(function () { B.request("echo", { text: "after the burst" }); }, 1500);
  });
  B.request("echo", { text: "hello" })
    .then(function (answer) { return B.request("not-on-the-list", {}).then(function () { return "ANSWERED"; }, function (e) { return "rejected: " + e.message; }).then(function (seen) { return B.request("echo", { text: answer + " | " + seen }); }); })
    .then(function () { document.getElementById("status").textContent = "talked"; return B.request("done", {}); });
})();
