// surfaces/webview2/page/bridge.js - the page's side of the bridge, for a page shown by this surface.
//
// A PAGE NEVER TOUCHES THE ENGINE. It loads this file by a relative address, ../surface/bridge.js
// (surfaces/Port.ps1, WHERE A PAGE FINDS A FILE), and is written against window.HordeBridge and
// nothing else:
//   HordeBridge.request(name, args)  ->  a promise of the value Horde answers with; rejected with
//                                        Horde's reason when the request is refused or fails
//   HordeBridge.on(name, fn)             fn(value) each time Horde pushes the event of that name
//   HordeBridge.live                     false when the page is open somewhere Horde is not behind it
// Another surface - a file sent to a phone, a view across a link - serves its own bridge.js under the
// same name, giving the same three members, and the page does not change.
//
// THE MESSAGES ARE DEFINED ONCE, in bridge-messages.json, which the surface serves beside this file
// (it is surfaces/bridge-messages.json, the file surfaces/Port.ps1 reads). This script asks for it
// once, before its first message, and takes the protocol number and every member name from it: it
// carries none of its own. In it, for each of the three shapes - a request, a reply, an event - the
// part a member plays is on the left and its name on the wire on the right.
// WHY ASKED FOR AND NOT WRITTEN IN BY THE SURFACE: the file is then served as it is, like any other,
// and no script is built from data. It costs one more load before the first request is sent:
// measured 2026-10-07 on a machine slowed on purpose, five runs each, the first request was answered
// 157 to 220 ms after the engine was up without it and 184 to 265 ms with it, about 30 ms. A request
// made before the definition has arrived simply waits for it; an event that arrives before it is
// handled when it has.
//
// An id is this page's own counter; a reply to an id nobody is waiting on is dropped, and so is a
// message of another protocol number.
(function () {
  "use strict";
  var nextId = 1;
  var waiting = {};
  var listeners = {};
  var port = (window.chrome && window.chrome.webview) ? window.chrome.webview : null;
  var here = document.currentScript ? document.currentScript.src : window.location.href;
  var shapes = fetch(new URL("bridge-messages.json", here)).then(function (answer) {
    if (!answer.ok) { throw new Error("the definition of the bridge's messages could not be loaded, so nothing can be asked"); }
    return answer.json();
  });

  function request(name, args) {
    return shapes.then(function (m) {
      return new Promise(function (resolve, reject) {
        if (!port) { reject(new Error("this page is not being shown by Horde, so there is nothing to ask")); return; }
        var id = nextId;
        nextId += 1;
        waiting[id] = { resolve: resolve, reject: reject };
        var message = {};
        message[m.request.version] = m.protocol;
        message[m.request.id] = id;
        message[m.request.name] = String(name);
        message[m.request.arguments] = args || {};
        port.postMessage(message);
      });
    });
  }

  function on(name, fn) {
    if (!listeners[name]) { listeners[name] = []; }
    listeners[name].push(fn);
  }

  function receive(m, data) {
    if (!data || typeof data !== "object") { return; }
    // A reply and an event are told apart by the one member each has that the other has not.
    if (typeof data[m.reply.id] === "number") {
      if (data[m.reply.version] !== m.protocol) { return; }
      var w = waiting[data[m.reply.id]];
      if (!w) { return; }
      delete waiting[data[m.reply.id]];
      if (data[m.reply.ok] === true) { w.resolve(data[m.reply.value]); } else { w.reject(new Error(String(data[m.reply.reason] || "refused"))); }
      return;
    }
    if (typeof data[m.event.name] === "string") {
      if (data[m.event.version] !== m.protocol) { return; }
      var fns = listeners[data[m.event.name]] || [];
      for (var i = 0; i < fns.length; i += 1) {
        // One listener that throws must not stop the others, or the next event.
        try { fns[i](data[m.event.value]); } catch (e) { /* the listener's own problem */ }
      }
    }
  }

  if (port) {
    port.addEventListener("message", function (ev) {
      var data = ev.data;
      // In the order they arrived: each waits on the same promise.
      shapes.then(function (m) { receive(m, data); }, function () { /* no definition: nothing can be read */ });
    });
  }

  window.HordeBridge = { request: request, on: on, live: port !== null };
})();
