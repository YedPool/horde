// The local relay's folders, from JavaScript: a relay transport for the phone app's suites (the
// transport contract of surfaces/pwa/page/relay-client.js) that reads and writes the mailboxes
// relays/local/Relay.ps1 keeps on disk, so a real `horde relay run` on that relay is the machine at
// the other end of the app under test.
//
// THE FOLDERS, as relays/local/Relay.ps1 keeps them (its header is the specification):
//   <root>/<horde>/<reader>/<seq, 16 digits>-<SHA-256 of the key>.item   key, LF, text (ASCII)
//   floor-<seq, 16 digits>    the highest seq ever acked
//   lock                      held while a put or an ack changes the mailbox
// A put here takes the lock by opening the lock file and holding it open: the machine opens it with no
// sharing, which fails while this handle is open, and this open fails (EBUSY) while the machine holds
// it - so the two never change one mailbox at once. Reads take no lock, as there. An item is written
// under a temporary name, flushed and renamed into place, so a reader never sees half of one.
import { readFileSync, writeFileSync, readdirSync, mkdirSync, openSync, closeSync, fsyncSync, renameSync, existsSync, unlinkSync } from "node:fs";
import { join } from "node:path";
import { createHash, randomUUID } from "node:crypto";

const ITEM = /^([0-9]{16})-([0-9a-f]{64})\.item$/;
const FLOOR = /^floor-([0-9]{16})$/;
const known = (value) => ({ state: "known", value, reason: "" });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const pad = (n) => String(n).padStart(16, "0");

function entries(dir) {
  const items = [];
  let floor = 0;
  if (existsSync(dir)) {
    for (const n of readdirSync(dir)) {
      let m = ITEM.exec(n);
      if (m) { items.push({ seq: Number(m[1]), hash: m[2], path: join(dir, n) }); continue; }
      m = FLOOR.exec(n);
      if (m && Number(m[1]) > floor) floor = Number(m[1]);
    }
  }
  items.sort((a, b) => a.seq - b.seq);
  const head = Math.max(floor, items.length ? items[items.length - 1].seq : 0);
  return { items, floor, head };
}
function read(dir, since, max) {
  const out = [];
  for (const e of entries(dir).items) {
    if (e.seq <= since) continue;
    if (out.length >= max) break;
    let raw;
    try { raw = readFileSync(e.path, "latin1"); } catch (x) { continue; }
    const cut = raw.indexOf("\n");
    out.push(cut < 0 ? { seq: e.seq, key: "", text: raw } : { seq: e.seq, key: raw.slice(0, cut), text: raw.slice(cut + 1) });
  }
  return out;
}
async function locked(dir, fn) {
  mkdirSync(dir, { recursive: true });
  const lockPath = join(dir, "lock");
  for (let waited = 0; ; waited += 20) {
    let fd;
    try { fd = openSync(lockPath, "a"); } catch (x) { if (waited > 10000) throw new Error("the mailbox stayed locked"); await sleep(20); continue; }
    try { return fn(); } finally { closeSync(fd); }
  }
}

export function folderTransport(relayRoot) {
  const dirOf = (mailbox) => join(relayRoot, ...mailbox.split("/"));
  return {
    async put(mailbox, key, text) {
      const dir = dirOf(mailbox);
      const hash = createHash("sha256").update(key, "ascii").digest("hex");
      return locked(dir, () => {
        const now = entries(dir);
        const held = now.items.find((i) => i.hash === hash);
        if (held) return known({ seq: held.seq, duplicate: true });
        const seq = now.head + 1;
        const tmp = join(dir, randomUUID().replace(/-/g, "") + ".tmp");
        const fd = openSync(tmp, "wx");
        try { writeFileSync(fd, key + "\n" + text, "latin1"); fsyncSync(fd); } finally { closeSync(fd); }
        renameSync(tmp, join(dir, pad(seq) + "-" + hash + ".item"));
        return known({ seq, duplicate: false });
      });
    },
    async get(mailbox, since, max) { return known({ items: read(dirOf(mailbox), since, max) }); },
    async watch(mailbox, since, max, timeoutMs) {
      const end = Date.now() + timeoutMs;
      for (;;) {
        const items = read(dirOf(mailbox), since, max);
        if (items.length || Date.now() >= end) return known({ items });
        await sleep(50);
      }
    },
    async ack(mailbox, through) {
      const dir = dirOf(mailbox);
      return locked(dir, () => {
        const now = entries(dir);
        if (through > now.head) return { state: "unknown", value: null, reason: "the mailbox " + mailbox + " ends at " + now.head };
        if (through > now.floor) { closeSync(openSync(join(dir, "floor-" + pad(through)), "a")); for (const e of now.items) if (e.seq <= through) unlinkSync(e.path); }
        return known({ through });
      });
    }
  };
}
