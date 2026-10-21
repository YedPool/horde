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

// A stamp is believable between 2020-01-01 and a day from now: anything else (0, a year-3000 clock, a
// microsecond count) would poison every percentile, so the record is skipped and counted instead.
export const PLAUSIBLE_FROM = Date.parse('2020-01-01T00:00:00Z');
const DAY_MS = 86400000;
const stamp = (v, now) => Number.isSafeInteger(v) && v >= PLAUSIBLE_FROM && v <= now + DAY_MS;

// One header line -> { from, channel, seq, ts, recordedAt } or null when it is not a record's header
// for exactly this place (from, channel, seq come from the folder and file names).
// `seq` is the file name's 16 digits AS A STRING (a Number could lose digits past 2^53); the header's own
// number must be a safe integer that prints as exactly the same digits without their leading zeros.
export function parseHeader(line, from, channel, seq, now = Date.now()) {
  if (line == null) return null;
  let o;
  try { o = JSON.parse(line); } catch { return null; }
  if (!o || typeof o !== 'object' || o.v !== 1 || o.direction !== 'in') return null;
  if (o.from !== from || o.channel !== channel) return null;
  if (!Number.isSafeInteger(o.seq) || String(o.seq) !== seq.replace(/^0+(?=\d)/, '')) return null;
  if (!stamp(o.ts, now) || !stamp(o.recordedAt, now)) return null;
  return { from, channel, seq, ts: o.ts, recordedAt: o.recordedAt };
}

const list = (dir) => { try { return fs.readdirSync(dir); } catch { return []; } };

// A record that was skipped is remembered by (path, size, mtime) in meter_offsets (ident 'skip', offset 0),
// so the next pass does not open it again unless it changed. The journal is append-only: a header does not
// change under an unchanged size and mtime.
const SKIP = 'skip';

export function collectMailHops({ store, home, journal, now = Date.now() }) {
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
        const seq = m[1];
        const id = sDir + '/' + cDir + '/' + seq.replace(/^0+(?=\d)/, '');
        out.seen++;
        if (known.has(id)) continue;
        const file = path.join(dir, name);
        let st = null;
        try { st = fs.statSync(file); } catch { st = null; }
        const mtime = st ? Math.round(st.mtimeMs) : 0;
        const was = st ? store.getOffset(file) : null;
        if (was && was.ident === SKIP && was.size === st.size && was.mtime === mtime) { out.skipped++; continue; }
        let h = null;
        try { h = parseHeader(firstLine(file), from, channel, seq, now); } catch { h = null; }
        if (!h) {
          out.skipped++;
          if (st) store.markOffset({ path: file, size: st.size, mtime, offset: 0, ident: SKIP });
          continue;
        }
        // Both hops of one message or neither: a crash between the two inserts must not leave a message
        // with only one of them. phone_sent is what marks a message as already read, so it goes last.
        out.added += store.addHops([
          { at: h.recordedAt, message_id: id, hop: 'pc_journal', from_session: from, to_session: '', clock: 'pc' },
          { at: h.ts, message_id: id, hop: 'phone_sent', from_session: from, to_session: '', clock: 'phone' },
        ]);
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

// Per adjacent pair of the hop kinds the store holds at all (in HOPS order): { from, to, n, p50, p95, min,
// negative, crossClock, lacking }. A pair is measured over the messages that have BOTH its hops;
// `lacking` is how many messages have one of the two but not the other (so n + lacking is every message
// that reached either). crossClock is true when the two hops were stamped by different clocks, so the
// delta includes whatever the clocks disagree by. `negative` counts deltas below zero for EVERY pair: across
// clocks that is skew, on one clock it is a clock that stepped back; both are shown.
export function latencyPairs(hops) {
  const byMsg = new Map();
  for (const h of hops) {
    if (!byMsg.has(h.message_id)) byMsg.set(h.message_id, new Map());
    byMsg.get(h.message_id).set(h.hop, h);
  }
  const kinds = HOPS.filter((n) => hops.some((h) => h.hop === n));
  const out = [];
  for (let i = 0; i + 1 < kinds.length; i++) {
    const deltas = [];
    let lacking = 0;
    let crossClock = false;
    for (const m of byMsg.values()) {
      const a = m.get(kinds[i]);
      const b = m.get(kinds[i + 1]);
      if (a && b) { deltas.push(b.at - a.at); if (a.clock !== b.clock) crossClock = true; } else if (a || b) lacking++;
    }
    const d = deltas.sort((x, y) => x - y);
    out.push({ from: kinds[i], to: kinds[i + 1], crossClock, n: d.length, lacking, p50: percentile(d, 50), p95: percentile(d, 95), min: d[0], negative: d.filter((x) => x < 0).length });
  }
  return out;
}

export function latencyLines(pairs) {
  if (pairs.length === 0 || pairs.every((p) => p.n === 0)) return ['latency: no message has two hops yet'];
  const out = [];
  for (const p of pairs) {
    out.push(p.from + ' -> ' + p.to + ': n=' + p.n + ' p50=' + p.p50 + ' ms p95=' + p.p95 + ' ms lacking_a_hop=' + p.lacking +
      (p.crossClock ? ' CROSSES CLOCKS (phone vs pc): includes clock skew' : '') + ' negative=' + p.negative);
  }
  return out;
}
