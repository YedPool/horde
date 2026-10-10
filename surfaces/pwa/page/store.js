// surfaces/pwa/page/store.js - the phone's storage: one IndexedDB object store of key -> value, with
// the five operations phone-core.js asks for (get, put, delete, list by prefix, update atomically).
//
// WHAT GOES IN is phone-core's to say, and it is never anything decrypted: entries of public keys,
// ids, counters and WRAPPED keys, and the one non-extractable device key a passkey without PRF needs
// (keywrap.js). IndexedDB keeps a CryptoKey as it is - structured clone - so a non-extractable key
// stays non-extractable on disk: the browser can use it for this origin, nobody can read its bytes.
//
// UPDATE IS ATOMIC within one readwrite transaction: the function is synchronous and runs between the
// read and the write, so two tabs never both read the same counter (phone-core's envelope sequence).
const DB_NAME = "horde-phone";
const DB_VERSION = 1;
const STORE = "kv";

function promised(request) {
  return new Promise((resolve, reject) => { request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error); });
}

export async function openStore(factory = globalThis.indexedDB) {
  if (!factory) throw new Error("this browser keeps nothing for web apps (no indexedDB), so a horde cannot be kept here");
  const open = factory.open(DB_NAME, DB_VERSION);
  open.onupgradeneeded = () => { if (!open.result.objectStoreNames.contains(STORE)) open.result.createObjectStore(STORE); };
  const db = await promised(open);
  const tx = (mode) => db.transaction(STORE, mode).objectStore(STORE);
  return {
    get: (key) => promised(tx("readonly").get(key)),
    put: (key, value) => promised(tx("readwrite").put(value, key)).then(() => undefined),
    delete: (key) => promised(tx("readwrite").delete(key)).then(() => undefined),
    list: async (prefix) => {
      // Every key that starts with the prefix sorts between it and it followed by the last code unit.
      const range = IDBKeyRange.bound(prefix, prefix + String.fromCharCode(0xffff));
      return promised(tx("readonly").getAll(range));
    },
    update: (key, fn) => new Promise((resolve, reject) => {
      const t = db.transaction(STORE, "readwrite");
      const s = t.objectStore(STORE);
      let next;
      const r = s.get(key);
      r.onsuccess = () => {
        try { next = fn(r.result); } catch (e) { t.abort(); reject(e); return; }
        s.put(next, key);
      };
      t.oncomplete = () => resolve(next);
      t.onerror = () => reject(t.error);
    })
  };
}

// The same five operations in memory: for the suites, and nothing kept.
export function memoryStore() {
  const m = new Map();
  return {
    get: async (key) => m.get(key),
    put: async (key, value) => { m.set(key, value); },
    delete: async (key) => { m.delete(key); },
    list: async (prefix) => [...m.keys()].filter((k) => k.startsWith(prefix)).sort().map((k) => m.get(k)),
    update: async (key, fn) => { const next = fn(m.get(key)); m.set(key, next); return next; }
  };
}
