// surfaces/webview2/page/bridge.js - the page's side of the bridge, for a page shown by this surface.
//
// A PAGE NEVER TOUCHES THE ENGINE. It is written against window.HordeBridge and nothing else:
//   HordeBridge.request(name, args)  ->  a promise of the value Horde answers with; rejected with
//                                        Horde's reason when the request is refused or fails
//   HordeBridge.on(name, fn)             fn(value) each time Horde pushes the event of that name
//   HordeBridge.live                     false when the page is open somewhere Horde is not behind it
// Another surface - a file sent to a phone, a view across a link - serves its own bridge.js under the
// same mount name, giving the same three members, and the page does not change.
//
// THE MESSAGES are surfaces/Port.ps1's: { v, id, request, args } out, { v, reply, ok, value | reason }
// and { v, event, value } in. An id is this page's own counter; a reply to an id nobody is waiting
// on is dropped.
(function () {
  "use strict";
  var VERSION = 1;
  var nextId = 1;
  var waiting = {};
  var listeners = {};
  var port = (window.chrome && window.chrome.webview) ? window.chrome.webview : null;

  function request(name, args) {
    return new Promise(function (resolve, reject) {
      if (!port) { reject(new Error("this page is not being shown by Horde, so there is nothing to ask")); return; }
      var id = nextId;
      nextId += 1;
      waiting[id] = { resolve: resolve, reject: reject };
      port.postMessage({ v: VERSION, id: id, request: String(name), args: args || {} });
    });
  }

  function on(name, fn) {
    if (!listeners[name]) { listeners[name] = []; }
    listeners[name].push(fn);
  }

  if (port) {
    port.addEventListener("message", function (ev) {
      var m = ev.data;
      if (!m || typeof m !== "object" || m.v !== VERSION) { return; }
      if (typeof m.reply === "number") {
        var w = waiting[m.reply];
        if (!w) { return; }
        delete waiting[m.reply];
        if (m.ok === true) { w.resolve(m.value); } else { w.reject(new Error(String(m.reason || "refused"))); }
        return;
      }
      if (typeof m.event === "string") {
        var fns = listeners[m.event] || [];
        for (var i = 0; i < fns.length; i += 1) {
          // One listener that throws must not stop the others, or the next event.
          try { fns[i](m.value); } catch (e) { /* the listener's own problem */ }
        }
      }
    });
  }

  window.HordeBridge = { request: request, on: on, live: port !== null };
})();
