// A worker of the probe page: a second place a load could be started from. It tries a call and a
// socket to the outside address it is handed, and says what it saw.
self.onmessage = function (m) {
  var seen = [];
  fetch(m.data.outside + "/worker-fetch").then(function (r) { seen.push(r.status === 200 ? "fetch LOADED" : "fetch status " + r.status); }, function () { seen.push("fetch blocked"); }).then(function () {
    var w;
    try { w = new WebSocket(m.data.socket + "/worker-socket"); } catch (e) { seen.push("socket threw"); self.postMessage(seen.join(", ")); return; }
    w.onopen = function () { w.close(); seen.push("socket OPEN"); self.postMessage(seen.join(", ")); };
    w.onerror = function () { seen.push("socket blocked"); self.postMessage(seen.join(", ")); };
  });
};
