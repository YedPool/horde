// relays/cloudflare/worker/mailbox.js - one mailbox: a Durable Object, one per "<horde>/<reader>", that
// keeps the items of that mailbox and numbers them (relays/Port.ps1, THE OPERATIONS).
//
// WHY ONE OBJECT PER MAILBOX. A Durable Object runs one request at a time and its storage is
// transactional, so a put's "read the head, write the item and the new head" cannot interleave with
// another put: two writers get contiguous seqs with none given twice, with no lock to hold or lose
// (the local relay needs a lock file for the same promise). And a mailbox is the unit the port
// addresses, so nothing ever needs two objects at once.
//
// STORAGE (the object's own key-value storage, SQLite-backed as the free plan requires):
//   head            the highest seq ever given; never lowered, so no seq is ever reused, even after
//                   every item is trimmed
//   floor           the highest seq ever acked
//   i:<16 digits>   one item, { key, text }; 16 digits hold 2^53-1 and sort as numbers do, so a read
//                   is one ordered list from the cursor
//   k:<key>         the seq held under a key, for idempotent puts; deleted with its item on a trim, so
//                   a key is remembered while its item is held, as the local relay remembers it
// Writes made in one request with no other I/O between them are committed together (the platform's
// write coalescing): a put's three writes, and an ack's deletes and its floor, land whole or not at all.
//
// WATCH IS A HIBERNATING WEBSOCKET, NOT A HELD REQUEST. Chosen over a long-poll because of what a wait
// costs: a request held open keeps the object in memory and billed by wall-clock duration for every
// second of it, and four readers each always waiting is about 44,000 GB-s a day at 128 MB - three times
// the free plan's 13,000 (reckoned from the plan's published allowance, 2026-10-11). A WebSocket the
// object has accepted through the hibernation API costs nothing while it waits: the object may be
// evicted and is woken only by a put. So the watch's socket is answered in the put that fills it, with
// one message of items, and closed. The waiting is the client's: it closes the socket when its timeout
// ends (relays/cloudflare/Relay.ps1, Watch), and the object sheds any socket whose client never closed
// it, at its next put, once the watch's time and a minute's grace are past.
//
// THE OBJECT NEVER OPENS A TEXT, and never logs anything.
import { DurableObject } from "cloudflare:workers";
import { keyProblem, itemTextProblem, BATCH_CHARS } from "./rules.js";

const HEAD = "head";
const FLOOR = "floor";
const ITEM = "i:";
const ITEM_END = "i;";
const KEY = "k:";
// The storage API deletes at most 128 keys in one call.
const DELETE_BATCH = 128;
// How long past its own timeout a waiting socket is kept for a client that never closed it.
const GRACE_MS = 60000;

const pad = (n) => String(n).padStart(16, "0");

function shut(ws, code, reason) {
  try { ws.close(code, reason); } catch (e) { /* already closed: nothing more to do */ }
}

export class Mailbox extends DurableObject {
  // Put one text under a key: { ok, seq, duplicate }, or { ok: false, reason }. The Worker has checked
  // both already; the object checks again, because it is the relay's own cap (relays/Port.ps1, ADAPTER
  // CONTRACT: "an adapter refuses a text over its own maxTextChars by itself too").
  async put(key, text) {
    const why = keyProblem(key) || itemTextProblem(text);
    if (why) return { ok: false, reason: why };
    const storage = this.ctx.storage;
    const held = await storage.get(KEY + key);
    if (held !== undefined) return { ok: true, seq: held, duplicate: true };
    const seq = ((await storage.get(HEAD)) || 0) + 1;
    await storage.put({ [ITEM + pad(seq)]: { key, text }, [KEY + key]: seq, [HEAD]: seq });
    await this.wake();
    return { ok: true, seq, duplicate: false };
  }

  // The items after since, at most max of them and at most BATCH_CHARS of text: { items }.
  async read(since, max) {
    const listed = await this.ctx.storage.list({ start: ITEM + pad(since + 1), end: ITEM_END, limit: max });
    const items = [];
    let chars = 0;
    for (const [name, item] of listed) {
      if (items.length > 0 && chars + item.text.length > BATCH_CHARS) break;
      chars += item.text.length;
      items.push({ seq: Number(name.slice(ITEM.length)), key: item.key, text: item.text });
    }
    return { items };
  }

  // The reader has kept everything through `through`: { ok, through }, or { ok: false, head } when that
  // is past the head. An ack at or behind the floor changes nothing and is still a yes.
  async ack(through) {
    const storage = this.ctx.storage;
    const head = (await storage.get(HEAD)) || 0;
    if (through > head) return { ok: false, head };
    const floor = (await storage.get(FLOOR)) || 0;
    if (through > floor) {
      const doomed = await storage.list({ start: ITEM + pad(floor + 1), end: ITEM + pad(through + 1) });
      const names = [];
      for (const [name, item] of doomed) names.push(name, KEY + item.key);
      for (let i = 0; i < names.length; i += DELETE_BATCH) await storage.delete(names.slice(i, i + DELETE_BATCH));
      await storage.put(FLOOR, through);
    }
    return { ok: true, through };
  }

  // A watch: the Worker hands over the upgrade with since, max and timeoutMs already checked. Items
  // already there are sent at once; otherwise the socket waits, hibernating, for the put that fills it.
  async fetch(request) {
    const url = new URL(request.url);
    const since = Number(url.searchParams.get("since"));
    const max = Number(url.searchParams.get("max"));
    const timeoutMs = Number(url.searchParams.get("timeoutMs"));
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.ctx.acceptWebSocket(server);
    const now = await this.read(since, max);
    if (now.items.length > 0) {
      server.send(JSON.stringify(now));
      shut(server, 1000, "items");
    } else {
      server.serializeAttachment({ since, max, until: Date.now() + timeoutMs + GRACE_MS });
    }
    return new Response(null, { status: 101, webSocket: client });
  }

  // After a put: every waiting socket that now has something after its cursor gets it and is closed;
  // a socket past its time is closed with nothing.
  async wake() {
    for (const ws of this.ctx.getWebSockets()) {
      const w = ws.deserializeAttachment();
      if (!w) continue;
      if (Date.now() > w.until) { ws.serializeAttachment(null); shut(ws, 1000, "expired"); continue; }
      const now = await this.read(w.since, w.max);
      if (now.items.length === 0) continue;
      ws.serializeAttachment(null);
      ws.send(JSON.stringify(now));
      shut(ws, 1000, "items");
    }
  }

  // A watch takes no messages: the client only waits.
  async webSocketMessage(ws) { shut(ws, 1008, "a watch takes no messages"); }
  async webSocketClose(ws, code) { shut(ws, 1000, "closed"); }
  async webSocketError(ws) { shut(ws, 1011, "error"); }
}
