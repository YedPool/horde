// surfaces/webview2/test/pages/probe/probe.js - the page half of the surface's own real-window suite
// (surfaces/webview2/test/test-webview2-window.ps1).
//
// IT BEHAVES AS A HOSTILE PAGE WOULD: it tries to leave, to open frames and windows, to save a file,
// to load from outside in every way a page can, to climb out of its mounts, to ask for what is not
// on the list and to reach the engine behind the bridge's back. It also does what a page MAY do: use
// its own files and another mount's by relative address (surfaces/Port.ps1, WHERE A PAGE FINDS A
// FILE); nothing here names where the surface serves it. After each
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
  function blocked(e) { return "blocked " + (e && e.name); }
  function status(r) { return "status " + r.status; }
  function element(tag, attributes) {
    return new Promise(function (resolve) {
      var e = document.createElement(tag);
      for (var a in attributes) { if (Object.prototype.hasOwnProperty.call(attributes, a)) { e[a] = attributes[a]; } }
      e.onload = function () { resolve("LOADED"); };
      e.onerror = function () { resolve("blocked"); };
      document.body.appendChild(e);
    });
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
      ["failed-request", function () { return B.request("breaks", {}).then(function () { return "ANSWERED"; }, function (e) { return "rejected: " + e.message; }); }],
      ["host-objects", function () {
        try { var h = raw.hostObjects; var v = (h && h.sync) ? h.sync.horde : undefined; return Promise.resolve((v === undefined || v === null) ? "none" : "AN OBJECT"); }
        catch (e) { return Promise.resolve("none (" + e.name + ")"); }
      }],
      ["raw-message", function () { raw.postMessage("text that is no request"); return wait(200).then(function () { return "sent"; }); }],
      // --- its own files, and another mount's, by relative address
      ["own-fetch", function () { return fetch("probe.css").then(function (r) { return r.text().then(function (t) { return "status " + r.status + " " + r.headers.get("content-type") + " " + t.length + " characters"; }); }, blocked); }],
      ["other-script", function () { return element("script", { src: "../other/other.js" }).then(function (seen) { return seen + " " + window.hordeProbeOther; }); }],
      ["other-fetch", function () { return fetch("../other/data.json").then(function (r) { return r.text().then(function (t) { return "status " + r.status + " " + t.trim(); }); }, blocked); }],
      ["definition-fetch", function () { return fetch("../surface/bridge-messages.json").then(function (r) { return r.json().then(function (d) { return "status " + r.status + " protocol " + d.protocol; }); }, blocked); }],
      // --- what is not a file of a mount
      ["in-missing", function () { return fetch("nothing-here.js").then(status, blocked); }],
      ["in-kind", function () { return fetch("notes.xml").then(status, blocked); }],
      ["in-above", function () { return fetch("../../secret.txt").then(status, blocked); }],
      ["in-escaped", function () { return fetch("..%2f..%2fsecret.txt").then(status, blocked); }],
      ["in-dots", function () { return fetch("/probe/%2e%2e/%2e%2e/secret.txt").then(status, blocked); }],
      ["in-backslash", function () { return fetch("..%5c..%5csecret.txt").then(status, blocked); }],
      ["in-port-file", function () { return fetch("../surface/Port.ps1").then(status, blocked); }],
      // --- outside: every way a page has of loading something
      ["out-script", function () { return element("script", { src: setup.outside + "/out-script.js" }); }],
      ["out-style", function () { return element("link", { rel: "stylesheet", href: setup.outside + "/out-style.css" }); }],
      ["out-image", function () { return element("img", { src: setup.outside + "/out-image.png" }); }],
      ["out-fetch", function () { return fetch(setup.outside + "/out-fetch").then(function (r) { return r.status === 200 ? "LOADED" : "status " + r.status; }, blocked); }],
      ["out-fetch-blind", function () { return fetch(setup.outside + "/out-fetch-blind", { mode: "no-cors" }).then(function (r) { return "answered " + r.type; }, blocked); }],
      ["out-xhr", function () { return new Promise(function (resolve) { var x = new XMLHttpRequest(); x.open("GET", setup.outside + "/out-xhr"); x.onload = function () { resolve(x.status === 200 ? "LOADED" : "status " + x.status); }; x.onerror = function () { resolve("blocked"); }; x.send(); }); }],
      ["out-beacon", function () { navigator.sendBeacon(setup.outside + "/out-beacon", "x"); return wait(300).then(function () { return "sent"; }); }],
      ["out-events", function () { return new Promise(function (resolve) { var s = new EventSource(setup.outside + "/out-events"); s.onopen = function () { s.close(); resolve("LOADED"); }; s.onerror = function () { s.close(); resolve("blocked"); }; }); }],
      ["out-font", function () { return new FontFace("probe-font", "url(" + setup.outside + "/out-font.woff2)").load().then(function () { return "LOADED"; }, blocked); }],
      ["out-socket", function () { return new Promise(function (resolve) { var w = new WebSocket(setup.socket + "/out-socket"); w.onopen = function () { w.close(); resolve("OPEN"); }; w.onerror = function () { resolve("blocked"); }; }); }],
      ["out-worker", function () { return new Promise(function (resolve) { var w = new Worker("worker.js"); w.onmessage = function (m) { resolve(String(m.data)); }; w.onerror = function () { resolve("the worker did not start"); }; w.postMessage({ outside: setup.outside, socket: setup.socket }); }); }],
      ["nav-out", function () { return go(setup.outside + "/nav-out"); }],
      ["nav-lookalike", function () { return go("https://" + window.location.host + ".example.com/x"); }],
      ["nav-other-mount", function () { return go("../other/other.js"); }],
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
      }],
      // --- what a page may ask the person's machine for: nothing
      ["ask-place", function () { return new Promise(function (resolve) { navigator.geolocation.getCurrentPosition(function () { resolve("GIVEN A PLACE"); }, function (e) { resolve("denied code " + e.code); }, { timeout: 4000 }); }); }],
      ["ask-notify", function () { return Notification.requestPermission().then(function (answer) { return "answered " + answer; }, blocked); }]
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
