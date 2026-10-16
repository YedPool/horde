// The collector: reads every registered reader's files from where it stopped last time.
//
// INCREMENTAL BY BYTE OFFSET. A transcript only ever grows by appended lines, so the collector keeps
// the offset it reached per file (meter_offsets) and reads from there. Measured on the reference
// report, a full read of the fleet's transcripts is what made a daily report slow; an offset pass
// reads only what is new.
//   - ONLY COMPLETE LINES ARE CONSUMED. A writer may be mid-line when we read; the bytes after the
//     last newline are left, and the offset stops at that newline, so the next pass starts at the
//     line's first byte and sees it whole.
//   - A FILE THAT SHRANK OR CHANGED IDENTITY IS READ FROM 0. Size below the stored offset, or a
//     different identity (inode and birth time), means it was rewritten or replaced, so the old
//     offset points into different bytes. Rows are upserts, so re-reading from 0 never duplicates.
//   - ROWS AND OFFSET ARE WRITTEN IN ONE TRANSACTION (store.apply).
// What a file means is the reader's business: this file knows lines, offsets and tables, not formats.
import fs from 'node:fs';
import { openReaders } from './readers.mjs';
import { METRIC_TABLES } from './store.mjs';

// A chunk is capped so one huge transcript cannot need its whole size in memory at once. If a single
// line is longer than the cap the chunk grows until it holds a newline.
const CHUNK = 32 * 1024 * 1024;

export function identOf(st) {
  return String(st.ino) + ':' + Math.round(st.birthtimeMs);
}

function readRange(fd, start, len) {
  const buf = Buffer.allocUnsafe(len);
  let got = 0;
  while (got < len) {
    const n = fs.readSync(fd, buf, got, len - got, start + got);
    if (n === 0) break;
    got += n;
  }
  return got === len ? buf : buf.subarray(0, got);
}

// Returns the number of new bytes consumed.
export function collectFile({ store, reader, file, rows, ctx }) {
  let st;
  try { st = fs.statSync(file); } catch { return 0; }
  const ident = identOf(st);
  const prev = store.getOffset(file);
  let offset = 0;
  if (prev && prev.ident === ident && st.size >= prev.offset) offset = prev.offset;
  if (offset === st.size && prev && prev.ident === ident) return 0;

  const fd = fs.openSync(file, 'r');
  let consumed = 0;
  try {
    let size = st.size;
    let cap = CHUNK;
    while (offset < size) {
      const want = Math.min(size - offset, cap);
      const buf = readRange(fd, offset, want);
      const nl = buf.lastIndexOf(0x0a);
      if (nl < 0) {
        if (offset + want < size) { cap *= 2; continue; }
        break; // only a partial line is left: next pass
      }
      cap = CHUNK;
      const text = buf.subarray(0, nl + 1).toString('utf8');
      const lines = text.split('\n').map((l) => (l.endsWith('\r') ? l.slice(0, -1) : l)).filter((l) => l.trim() !== '');
      const batch = reader.consume({ path: file, lines, store, ctx });
      const next = offset + nl + 1;
      const counts = store.apply(batch, { path: file, size, mtime: Math.round(st.mtimeMs), offset: next, ident });
      for (const t of METRIC_TABLES) rows[t] += counts[t];
      consumed += nl + 1;
      offset = next;
    }
    if (consumed === 0) {
      // Nothing complete to read, but record the identity so a later shrink is noticed.
      store.apply({}, { path: file, size, mtime: Math.round(st.mtimeMs), offset, ident });
    }
  } finally {
    fs.closeSync(fd);
  }
  return consumed;
}

export const DEFAULT_SINCE_DAYS = 14;
// Under the 4 minutes a scheduled run may take, so a first backfill over a large history is cut into
// passes instead of one run that overstays: each pass keeps what it finished and the next continues.
export const DEFAULT_MAX_MS = 240000;

export async function runCollect({ store, opts = {}, readers = null, ctx = {} }) {
  const clock = opts.clock || Date.now;
  const t0 = clock();
  const sinceDays = opts.sinceDays == null ? DEFAULT_SINCE_DAYS : Number(opts.sinceDays);
  const maxMs = opts.maxMs == null ? DEFAULT_MAX_MS : Number(opts.maxMs);
  const list = readers || (await openReaders(opts));
  const rows = Object.fromEntries(METRIC_TABLES.map((t) => [t, 0]));
  let files = 0;
  let bytes = 0;
  let skippedOld = 0;
  // One shared context per pass, so a reader can load its lookups (a registry) once and not per file.
  const shared = { ...ctx, opts };

  // FILES OLDER THAN THE WINDOW ARE SKIPPED AND GIVEN NO OFFSET, so a later run with a larger
  // --since-days still reads them from byte 0. Newest first, so a pass cut short by the time budget has
  // done the files that matter most.
  const cutoff = t0 - sinceDays * 86400000;
  const todo = [];
  for (const reader of list) {
    for (const root of reader.roots(opts)) {
      for (const file of reader.listFiles(root)) {
        let st;
        try { st = fs.statSync(file); } catch { continue; }
        if (st.mtimeMs < cutoff) { skippedOld++; continue; }
        todo.push({ reader, file, mtime: st.mtimeMs });
      }
    }
  }
  todo.sort((a, b) => b.mtime - a.mtime);

  // THE TIME BUDGET IS CHECKED BETWEEN FILES, never inside one: a file is read whole (its rows and offset
  // are one transaction), so stopping here leaves every offset truthful and the next pass picks up the rest.
  let left = 0;
  for (let i = 0; i < todo.length; i++) {
    if (clock() - t0 >= maxMs) { left = todo.length - i; break; }
    files++;
    bytes += collectFile({ store, reader: todo[i].reader, file: todo[i].file, rows, ctx: shared });
  }
  return { files, bytes, rows, ms: clock() - t0, skippedOld, partial: left > 0, left };
}

export function summaryLine(r) {
  const per = Object.keys(r.rows).map((t) => t + '=' + r.rows[t]).join(' ');
  return 'collect: ' + (r.partial ? 'partial (' + r.left + ' files left for the next pass) ' : '') + 'files=' + r.files + ' skipped_old=' + r.skippedOld +
    ' new_bytes=' + r.bytes + ' rows: ' + per + ' ms=' + r.ms;
}
