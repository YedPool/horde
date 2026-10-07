// surfaces/webview2/test/pages/probe/probe.js - the page half of the surface's own real-window suite
// (surfaces/webview2/test/test-webview2-window.ps1).
//
// IT BEHAVES AS A HOSTILE PAGE WOULD: it tries to leave, to open frames and windows, to save a file,
// to ask for what is not on the list and to reach the engine behind the bridge's back. After each
// try it reports, through the bridge, what it saw from inside; the suite holds that against what the
// surface recorded and against a listener of its own that stands for "outside". The page never
// decides whether a try passed.
(function () {
  "use strict";
  var B = window.HordeBridge;
  var raw = window.chrome.webview;
  var frameRan = false;

  function report(key, value) { return B.request("report", { key: key, value: String(value).slice(0, 1500) }); }
  function wait(ms) { return new Promise(function (resolve) { setTimeout(resolve, ms); }); }
  function within(promise, ms) { return Promise.race([promise, wait(ms).then(function () { return "nothing in " + ms + " ms"; })]); }
  function go(address) {
    try { window.location.href = address; } catch (e) { return Promise.resolve("threw " + e.name); }
    return wait(500).then(function () { return "still at " + window.location.href; });
  }
  function frame(address) {
    frameRan = false;
    var f = document.createElement("iframe");
    f.src = address;
    document.body.appendChild(f);
    return wait(700).then(function () { return frameRan ? "A FRAME RAN" : "no frame ran"; });
  }

  window.addEventListener("message", function (ev) { if (ev.data === "frame-ran") { frameRan = true; } });
  B.on("poke", function (value) { report("push", value); });

  function steps(setup) {
    return [
      ["where", function () { return Promise.resolve(window.location.href); }],
      ["bridge", function () { return Promise.resolve(typeof B.request + " " + typeof B.on + " live=" + B.live); }],
      ["unknown-request", function () { return B.request("open-file", { path: "C:\\Windows\\win.ini" }).then(function () { return "ANSWERED"; }, function (e) { return "rejected: " + e.message; }); }],
      ["host-objects", function () {
        try { var h = raw.hostObjects; var v = (h && h.sync) ? h.sync.horde : undefined; return Promise.resolve((v === undefined || v === null) ? "none" : "AN OBJECT"); }
        catch (e) { return Promise.resolve("none (" + e.name + ")"); }
      }],
      ["raw-message", function () { raw.postMessage("text that is no request"); return wait(200).then(function () { return "sent"; }); }],
      ["nav-out", function () { return go(setup.outside + "/nav-out"); }],
      ["nav-lookalike", function () { return go("https://" + window.location.host + ".example.com/x"); }],
      ["nav-other-mount", function () { return go("https://other.horde.invalid/other.js"); }],
      ["nav-scheme", function () { return go("horde-probe-nothing:x"); }],
      ["frame-own", function () { return frame("frame.html"); }],
      ["frame-out", function () { return frame(setup.outside + "/frame-out"); }],
      ["new-window", function () { var w = window.open("index.html"); return wait(300).then(function () { return w ? "A WINDOW OPENED" : "no window"; }); }],
      ["download", function () {
        var a = document.createElement("a");
        a.href = URL.createObjectURL(new Blob(["written by the surface probe"], { type: "text/plain" }));
        a.download = setup.stamp + ".txt";
        document.body.appendChild(a);
        a.click();
        return wait(700).then(function () { return "clicked"; });
      }]
    ];
  }

  function run(list, i) {
    if (i >= list.length) { document.getElementById("status").textContent = "probed"; return B.request("done", {}); }
    var step = list[i];
    var tried;
    try { tried = within(step[1](), 6000); } catch (e) { tried = Promise.resolve("threw " + e.name); }
    return tried.then(function (value) { return report(step[0], value); }, function (e) { return report(step[0], "failed " + (e && e.name)); })
      .then(function () { return run(list, i + 1); });
  }

  B.request("setup", {}).then(function (setup) { return run(steps(setup), 0); });
})();
