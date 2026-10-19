// The hops of a phone message, read from the relay's journal (mail_hops), and their latency.
//
// READ-ONLY. The journal is the relay's evidence (relay/Journal.ps1); this file opens a record, reads the
// first line only and closes it. It never writes, renames or locks anything in the journal.
//
// WHERE: <HORDE_HOME>\relay\journal\in\s-<from>\c-<channel>\<seq as 16 digits>.rec (Get-HordeRelayJournalRoot
// and Get-HordeRelayJournalStreamDir). Only the "in" direction is read: those are messages that came from
// a device to this machine, and their ts is the SENDER's clock (the phone). An "out" record's ts is this
// machine's own clock, so it says nothing about the phone leg.
//
// THE FIRST LINE of a record is the canonical metadata
//   {"v":1,"direction":"in","key":"..","from":"<32 hex>","channel":"..","kind":"..","seq":41,"nonce":"..",
//    "ts":<sender ms>,"recordedAt":<journal ms>,"envelopeChars":<n>}
// and gives two hops now:
//   ts          -> hop 'phone_sent'  clock 'phone'  (when the sender says it sent it; the phone's clock)
//   recordedAt  -> hop 'pc_journal'  clock 'pc'     (when this machine journaled it; the PC's clock)
// message_id is "s-<from>/c-<channel>/<seq>": the journal's own address of the record, so a later hop
// (relay_recorded, mailed, taken) joins on the same string. from_session is the sender's id as the journal
// has it; to_session is '' until a hop that knows the receiving session is added (the header does not).
// The three later hops are NOT filled here: the relay's own record (relay_recorded) and the mail delivery
// (mailed, taken) are another owner's to hand over.
//
// A header that does not parse, or whose key, direction, folder or file name disagree, is SKIPPED AND
// COUNTED, never fatal and never guessed at. A message already holding its phone_sent hop is not read again.
import fs from 'node:fs';
import path from 'node:path';
import { HOPS } from './store.mjs';

const HEAD_BYTES = 2048; // a header is about 300 bytes; this is far past any honest one
const SEQ_FILE = /^(\d{16})\.rec$/;
const HEX32 = /^[0-9a-f]{32}$/;
const CHANNEL = /^[a-z][a-z0-9-]{0,31}$/;

export function journalFolder(home, journal) {
  if (journal) return journal;
  return home ? path.join(home, 'relay', 'journal') : null;
}

function firstLine(file) {
  const fd = fs.openSync(file, 'r');
  try {
    const buf = Buffer.alloc(HEAD_BYTES);
    const n = fs.readSync(fd, buf, 0, HEAD_BYTES, 0);
    const text = buf.subarray(0, n).toString('utf8');
    const cut = text.indexOf('\n');
    return cut < 0 ? null : text.slice(0, cut);
  } finally {
    fs.closeSync(fd);
  }
}

const ms = (v) => Number.isSafeInteger(v) && v >= 0;

// One header line -> { from, channel, seq, ts, recordedAt } or null when it is not a record's header
// for exactly this place (from, channel, seq come from the folder and file names).
export function parseHeader(line, from, channel, seq) {
  if (line == null) return null;
  let o;
  try { o = JSON.parse(line); } catch { return null; }
  if (!o || typeof o !== 'object' || o.v !== 1 || o.direction !== 'in') return null;
  if (o.from !== from || o.channel !== channel || o.seq !== seq) return null;
  if (!ms(o.ts) || !ms(o.recordedAt)) return null;
  return { from, channel, seq, ts: o.ts, recordedAt: o.recordedAt };
}

const list = (dir) => { try { return fs.readdirSync(dir); } catch { return []; } };

export function collectMailHops({ store, home, journal }) {
  const out = { added: 0, skipped: 0, seen: 0 };
  const root = journalFolder(home, journal);
  if (!root) return out;
  const inDir = path.join(root, 'in');
  const known = store.knownMessages();
  for (const sDir of list(inDir)) {
    if (!sDir.startsWith('s-') || !HEX32.test(sDir.slice(2))) continue;
    const from = sDir.slice(2);
    for (const cDir of list(path.join(inDir, sDir))) {
      if (!cDir.startsWith('c-') || !CHANNEL.test(cDir.slice(2))) continue;
      const channel = cDir.slice(2);
      const dir = path.join(inDir, sDir, cDir);
      for (const name of list(dir)) {
        const m = SEQ_FILE.exec(name);
        if (!m) continue; // lock, .part, .done: not records
        const seq = Number(m[1]);
        const id = sDir + '/' + cDir + '/' + seq;
        out.seen++;
        if (known.has(id)) continue;
        let h = null;
        try { h = parseHeader(firstLine(path.join(dir, name)), from, channel, seq); } catch { h = null; }
        if (!h) { out.skipped++; continue; }
        if (store.addHop({ at: h.ts, message_id: id, hop: 'phone_sent', from_session: from, to_session: '', clock: 'phone' })) out.added++;
        if (store.addHop({ at: h.recordedAt, message_id: id, hop: 'pc_journal', from_session: from, to_session: '', clock: 'pc' })) out.added++;
      }
    }
  }
  return out;
}

// Nearest-rank percentile of a sorted array.
export function percentile(sorted, p) {
  if (sorted.length === 0) return null;
  return sorted[Math.min(sorted.length - 1, Math.max(0, Math.ceil((p / 100) * sorted.length) - 1))];
}

// Per adjacent pair of hops that a message actually passed (in HOPS order, skipping hops it lacks):
// { from, to, n, p50, p95, min, negative, crossClock }. crossClock is true when the two hops were
// stamped by different clocks, so the delta includes whatever the clocks disagree by (a negative one
// is clock skew, not a message that arrived before it was sent).
export function latencyPairs(hops) {
  const byMsg = new Map();
  for (const h of hops) {
    if (!byMsg.has(h.message_id)) byMsg.set(h.message_id, new Map());
    byMsg.get(h.message_id).set(h.hop, h);
  }
  const pairs = new Map();
  for (const m of byMsg.values()) {
    const have = HOPS.filter((n) => m.has(n));
    for (let i = 0; i + 1 < have.length; i++) {
      const a = m.get(have[i]);
      const b = m.get(have[i + 1]);
      const key = a.hop + '>' + b.hop;
      if (!pairs.has(key)) pairs.set(key, { from: a.hop, to: b.hop, crossClock: a.clock !== b.clock, deltas: [] });
      pairs.get(key).deltas.push(b.at - a.at);
    }
  }
  return [...pairs.values()].map((p) => {
    const d = p.deltas.slice().sort((x, y) => x - y);
    return { from: p.from, to: p.to, crossClock: p.crossClock, n: d.length, p50: percentile(d, 50), p95: percentile(d, 95), min: d[0], negative: d.filter((x) => x < 0).length };
  }).sort((x, y) => HOPS.indexOf(x.from) - HOPS.indexOf(y.from));
}

export function latencyLines(pairs) {
  if (pairs.length === 0) return ['latency: no message has two hops yet'];
  const out = [];
  for (const p of pairs) {
    out.push(p.from + ' -> ' + p.to + ': n=' + p.n + ' p50=' + p.p50 + ' ms p95=' + p.p95 + ' ms' +
      (p.crossClock ? ' CROSSES CLOCKS (phone vs pc): includes clock skew, ' + p.negative + ' negative' : ''));
  }
  return out;
}
