// surfaces/pwa/page/sw.js - the phone app's service worker: it keeps THE SHELL - the site's own static
// files - so the app starts with no network, and it keeps NOTHING ELSE.
//
// NEVER CACHED: anything that is not on the shell list. The relay's answers are fetched by the page
// from the relay's origin, carry sealed envelopes, and are opened in memory (phone-core.js); this
// worker does not answer for them, does not look at them and never puts them in a cache. The
// decrypted snapshot is never a response at all, so there is nothing of it to cache.
//
// THE LIST AND THE VERSION ARE WRITTEN IN BY THE SITE'S ASSEMBLER (surfaces/pwa/Site.ps1,
// New-HordePwaSite): VERSION is a hash of every shell file, so a new deployment is a new worker - the
// browser compares this file's bytes - and a new cache, and the old cache is deleted when the new
// worker takes over. The two placeholder lines below must stay exactly as they are; the assembler
// refuses to build when either is missing.
const VERSION = "unbuilt";
const SHELL = [];
const CACHE = "horde-shell-" + VERSION;

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL.map((p) => new URL(p, self.registration.scope + "../").href))).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(caches.keys().then((names) => Promise.all(names.filter((n) => n.indexOf("horde-shell-") === 0 && n !== CACHE).map((n) => caches.delete(n)))).then(() => self.clients.claim()));
});

// A shell file: the network first, so a deployment shows at once when online, and the cache when the
// network fails. Anything else: not touched - the browser fetches it as if this worker were not here.
self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  const root = new URL(self.registration.scope + "../").pathname;
  if (url.search || !url.pathname.startsWith(root)) return;
  const path = url.pathname.slice(root.length);
  if (SHELL.indexOf(path) < 0) return;
  event.respondWith(fetch(req).then((res) => {
    if (res.ok) { const copy = res.clone(); caches.open(CACHE).then((c) => c.put(req, copy)); }
    return res;
  }).catch(() => caches.match(req).then((hit) => hit || Response.error())));
});
