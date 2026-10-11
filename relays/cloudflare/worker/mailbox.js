// relays/cloudflare/worker/mailbox.js - one mailbox: a Durable Object, one per account's "<horde>/<reader>",
// that keeps the items of that mailbox and numbers them (relays/Port.ps1, THE OPERATIONS).
//
// WHY ONE OBJECT PER MAILBOX. A Durable Object runs one request at a time and its storage is
// transactional, so a put's "read the head, write the item and the new head" cannot interleave with
// another put: two writers get contiguous seqs with none given twice, with no lock to hold or lose
// (the local relay needs a lock file for the same promise). And a mailbox is the unit the port
// addresses, so nothing ever needs two objects at once.
//
// ITS NAME (mailboxOf) is the account, the account's epoch and the mailbox, written as a JSON triple so
// no account id and mailbox can ever spell another: one account's "work/phone" is never another's, and
// an account deleted and made again (accounts.js, a new epoch) never meets its old mailboxes.
//
// STORAGE (the object's own key-value storage, SQLite-backed as the free plan requires):
//   head            the highest seq ever given; never lowered, so no seq is ever reused, even after
//                   every item is trimmed
//   floor           the highest seq ever acked
//   i:<16 digits>   one item, { key, text, exp }; 16 digits hold 2^53-1 and sort as numbers do, so a
//                   read is one ordered list from the cursor; exp is when retention deletes it
//   k:<key>         the seq held under a key, for idempotent puts; deleted with its item, so a key is
//                   remembered while its item is held, as the local relay remembers it
//   size            { count, chars }: the items held and the characters of their texts, kept with
//                   every put, ack and expiry, so the caps are checked without a list
//   gone            the mailbox was deleted with its account (wipe): every put is refused, 410
//   owner           { account, epoch, mailbox }: whose it is, kept with its first put, so its acks and
//                   expiries are credited back to the account's caps (accounts.js, credit)
// Writes made in one request with no other I/O between them are committed together (the platform's
// write coalescing): a put's writes, and an ack's deletes and its floor, land whole or not at all.
//
// THE CAPS (limits.js): a put that would take the mailbox past mailboxMaxItems held items or
// mailboxMaxChars characters is REFUSED, 507 mailbox-full - never taken by dropping an older item.
// Unacked mail leaves only by its ack or by retention. A put of a key already held is still the yes it
// always was (idempotent): it adds nothing, so it is taken even when the mailbox is full. A put is then
// charged to its account (accounts.js, charge: the account's own caps on mailboxes and characters),
// and every ack or expiry credited back. The account's call is made inside blockConcurrencyWhile: an
// object's other requests may otherwise run while it waits on another object, and a put's "read the
// head, write the item" must not interleave with another's.
//
// RETENTION BY ALARM, NOT BY A SCHEDULE. Each item carries exp (its put plus retentionMs, 30 days), and
// the object keeps ONE alarm, at the oldest held item's exp: when it fires, the items past their exp
// are deleted and the alarm moves to the next one's. When an ack leaves nothing, the alarm is cleared.
// So a mailbox whose reader keeps up never wakes for retention, an empty or idle one costs nothing,
// and the object wakes at most once for each item that went unacked for 30 days - traffic already
// paid for by its put. A cron instead would wake (and bill a request for) every mailbox on its
// schedule, busy or not, and could not even find them without an index of every mailbox. An item is
// never deleted before its exp: an alarm runs at or after its time. An acked item is deleted by the ack
// itself, at once (trim.on.ack), so there is nothing acked left for retention to keep.
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
// ONE LIVE WATCH PER DEVICE IN A MAILBOX (limits.js): a watch is tagged with its device - a phone's
// session, a machine's key - and a new watch of that device here first ENDS the old one: one message
// { error, code: "watch-replaced" }, then the close code REPLACED (4001). Both clients read either as a
// failed watch and so pause before the next, never as "nothing came" (two tabs of one phone would
// otherwise replace each other as fast as they could). The message is what they act on: a client sees
// it at once, where a close may reach a page's script only once the connection is down (measured
// 2026-10-11 against the local dev: Node's WebSocket fired close 10 s after the close frame). Per mailbox, not across mailboxes: a machine pairing a phone while its runner runs watches two
// mailboxes at once, rightly, and one slot for both would have them evict each other in turn.
//
// THE OBJECT NEVER OPENS A TEXT, and never logs anything.
import { DurableObject } from "cloudflare:workers";
import { keyProblem, itemTextProblem, BATCH_CHARS } from "./rules.js";
import { CODES } from "./answers.js";
import { accountOf } from "./accounts.js";

const HEAD = "head";
const FLOOR = "floor";
const ITEM = "i:";
const ITEM_END = "i;";
const KEY = "k:";
const SIZE = "size";
const GONE = "gone";
const OWNER = "owner";
// The storage API deletes at most 128 keys in one call.
const DELETE_BATCH = 128;
// How long past its own timeout a waiting socket is kept for a client that never closed it.
const GRACE_MS = 60000;
// How long a deleted mailbox's tombstone outlives it: longer than any request already past the
// account's gate (accounts.js) can take to arrive here. Then the object holds nothing at all.
const GONE_MS = 3600000;
export const REPLACED = 4001;
export const DELETED = 4002;

const pad = (n) => String(n).padStart(16, "0");

function shut(ws, code, reason) {
  try { ws.close(code, reason); } catch (e) { /* already closed: nothing more to do */ }
}

// End a waiting watch by the relay's own decision: its one message says why ({ error, code }), and the
// close code says it again (the header, ONE LIVE WATCH PER DEVICE).
function end(ws, closeCode, code, words) {
  ws.serializeAttachment(null);
  try { ws.send(JSON.stringify({ error: words, code })); } catch (e) { /* already closed */ }
  shut(ws, closeCode, words);
}

export class Mailbox extends DurableObject {
  // Put one text under a key: { ok, seq, duplicate }, or { ok: false, status, code, reason }. The
  // Worker has checked both already; the object checks again, because it is the relay's own cap
  // (relays/Port.ps1, ADAPTER CONTRACT: "an adapter refuses a text over its own maxTextChars by itself
  // too"). limits are the Worker's (limits.js), now the time of the put, owner { account, epoch,
  // mailbox } the account it is charged to (null for the test principal, which has no account).
  async put(key, text, { now, limits, owner }) {
    return this.ctx.blockConcurrencyWhile(() => this.putNow(key, text, now, limits, owner));
  }

  async putNow(key, text, now, limits, owner) {
    const why = keyProblem(key) || itemTextProblem(text);
    if (why) return { ok: false, status: 400, reason: why };
    const storage = this.ctx.storage;
    if (await storage.get(GONE)) return { ok: false, status: 410, code: CODES.mailboxGone, reason: "this mailbox was deleted with its account" };
    const held = await storage.get(KEY + key);
    if (held !== undefined) return { ok: true, seq: held, duplicate: true };
    const size = (await storage.get(SIZE)) || { count: 0, chars: 0 };
    if (size.count + 1 > limits.mailboxMaxItems) return { ok: false, status: 507, code: CODES.mailboxFull, reason: "this mailbox holds " + size.count + " envelopes its reader has not acked, its most: nothing more is taken until some are acked" };
    if (size.chars + text.length > limits.mailboxMaxChars) return { ok: false, status: 507, code: CODES.mailboxFull, reason: "this mailbox holds " + size.chars + " characters its reader has not acked; this text would take it past its most, " + limits.mailboxMaxChars };
    if (owner) {
      const charged = await accountOf(this.env, owner.account).charge({ mailbox: owner.mailbox, chars: text.length, epoch: owner.epoch, limits });
      if (!charged.ok) return { ok: false, status: charged.status, code: charged.code, reason: charged.reason };
      if ((await storage.get(OWNER)) === undefined) await storage.put(OWNER, owner);
    }
    const seq = ((await storage.get(HEAD)) || 0) + 1;
    const exp = now + limits.retentionMs;
    await storage.put({ [ITEM + pad(seq)]: { key, text, exp }, [KEY + key]: seq, [HEAD]: seq, [SIZE]: { count: size.count + 1, chars: size.chars + text.length } });
    if ((await storage.getAlarm()) === null) await storage.setAlarm(exp);
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

  // Delete the items listed ([name, item] pairs) with their keys, and take them off the size.
  async drop(listed) {
    const storage = this.ctx.storage;
    const names = [];
    let count = 0;
    let chars = 0;
    for (const [name, item] of listed) { names.push(name, KEY + item.key); count++; chars += item.text.length; }
    for (let i = 0; i < names.length; i += DELETE_BATCH) await storage.delete(names.slice(i, i + DELETE_BATCH));
    const size = (await storage.get(SIZE)) || { count: 0, chars: 0 };
    const left = { count: Math.max(0, size.count - count), chars: Math.max(0, size.chars - chars) };
    await storage.put(SIZE, left);
    const owner = await storage.get(OWNER);
    if (owner && count > 0) await accountOf(this.env, owner.account).credit({ mailbox: owner.mailbox, chars, emptied: left.count === 0, epoch: owner.epoch });
    return left;
  }

  // The reader has kept everything through `through`: { ok, through }, or { ok: false, head } when that
  // is past the head. An ack at or behind the floor changes nothing and is still a yes.
  async ack(through) { return this.ctx.blockConcurrencyWhile(() => this.ackNow(through)); }

  async ackNow(through) {
    const storage = this.ctx.storage;
    const head = (await storage.get(HEAD)) || 0;
    if (through > head) return { ok: false, head };
    const floor = (await storage.get(FLOOR)) || 0;
    if (through > floor) {
      const left = await this.drop(await storage.list({ start: ITEM + pad(floor + 1), end: ITEM + pad(through + 1) }));
      await storage.put(FLOOR, through);
      if (left.count === 0) await storage.deleteAlarm();
    }
    return { ok: true, through };
  }

  // Retention, or a deleted mailbox's tombstone ending (the header).
  async alarm() { return this.ctx.blockConcurrencyWhile(() => this.expire()); }

  async expire() {
    const storage = this.ctx.storage;
    if (await storage.get(GONE)) { await storage.deleteAll(); return; }
    const now = Date.now();
    for (;;) {
      const page = await storage.list({ start: ITEM, end: ITEM_END, limit: DELETE_BATCH / 2 });
      const due = [];
      let next = null;
      for (const [name, item] of page) {
        if (item.exp <= now) { due.push([name, item]); continue; }
        next = item.exp;
        break;
      }
      if (due.length > 0) await this.drop(due);
      if (next !== null) { await storage.setAlarm(next); return; }
      if (due.length < DELETE_BATCH / 2) return;
    }
  }

  // The account was deleted (accounts.js): every waiting socket closed, everything held deleted, and a
  // tombstone kept for GONE_MS, so a put already past the account's gate is refused, not kept.
  async wipe() {
    for (const ws of this.ctx.getWebSockets()) end(ws, DELETED, CODES.gone, "the account was deleted");
    const storage = this.ctx.storage;
    await storage.deleteAlarm();
    await storage.deleteAll(); // everything the mailbox held
    await storage.put(GONE, true);
    await storage.setAlarm(Date.now() + GONE_MS);
    return true;
  }

  // A watch: the Worker hands over the upgrade with since, max, timeoutMs and the device already
  // checked. Items already there are sent at once; otherwise the socket waits, hibernating, for the put
  // that fills it. The device's older watch here, if any, is closed first (REPLACED, the header).
  async fetch(request) {
    const url = new URL(request.url);
    const since = Number(url.searchParams.get("since"));
    const max = Number(url.searchParams.get("max"));
    const timeoutMs = Number(url.searchParams.get("timeoutMs"));
    const device = url.searchParams.get("device") || "";
    if (await this.ctx.storage.get(GONE)) return new Response(JSON.stringify({ error: "this mailbox was deleted with its account", code: CODES.mailboxGone }), { status: 410, headers: { "Content-Type": "application/json" } });
    if (device !== "") {
      for (const old of this.ctx.getWebSockets(device)) end(old, REPLACED, CODES.replaced, "replaced by a newer watch of this device");
    }
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.ctx.acceptWebSocket(server, device !== "" ? [device] : []);
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

// The account's mailbox (the header, ITS NAME). epoch is the account's (accounts.js); "" for the test
// principal, which has no account record (auth.js).
export function mailboxOf(env, account, epoch, mailbox) {
  return env.MAILBOX.get(env.MAILBOX.idFromName(JSON.stringify([account, epoch, mailbox])));
}
