// The collector: reads every registered reader's files from where it stopped last time.
//
// INCREMENTAL BY BYTE OFFSET. A transcript only ever grows by appended lines, so the collector keeps
// the offset it reached per file (meter_offsets) and reads from there. Measured on the reference
// report, a full read of the fleet's transcripts is what made a daily report slow; an offset pass
// reads only what is new.
//   - ONLY COMPLETE LINES ARE CONSUMED. A writer may be mid-line when we read; the bytes after the
//     last newline are left, and the offset stops at that newline, so the next pass starts at the
//     line's first byte and sees it whole.
//   - A FILE THAT SHRANK OR CHANGED IDENTITY IS READ FROM 0. Size below the stored offset, a
//     different identity (inode and birth time), or a different beginning (a hash of the first 4 KB
//     already consumed) means it was rewritten or replaced, so the old offset points into different
//     bytes. The hash is what catches an in-place rewrite that leaves the size unchanged. Rows are
//     upserts, so re-reading from 0 never duplicates.
//   - ONE BAD FILE NEVER STOPS THE PASS. runCollect catches per file, leaves that file's offset where
//     its last good chunk put it, counts it in errors, and goes on; the command then exits nonzero so a
//     scheduler's history shows it. (A single malformed record used to abort every pass for ever.)
//   - ROWS AND OFFSET ARE WRITTEN IN ONE TRANSACTION (store.apply).
// What a file means is the reader's business: this file knows lines, offsets and tables, not formats.
import fs from 'node:fs';
import crypto from 'node:crypto';
import { openReaders } from './readers.mjs';
import { METRIC_TABLES } from './store.mjs';
import { collectMailHops } from './mail.mjs';

// A chunk is capped so one huge transcript cannot need its whole size in memory at once. If a single
// line is longer than the cap the chunk grows until it holds a newline.
const CHUNK = 32 * 1024 * 1024;

export function identOf(st) {
  return String(st.ino) + ':' + Math.round(st.birthtimeMs);
}

const HEAD_BYTES = 4096;

// 'len:sha1' of the first min(HEAD_BYTES, n) bytes of the open file.
function headOf(fd, n) {
  const len = Math.min(HEAD_BYTES, n);
  const buf = len > 0 ? readRange(fd, 0, len) : Buffer.alloc(0);
  return buf.length + ':' + crypto.createHash('sha1').update(buf).digest('hex');
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

// Returns the number of new bytes consumed. `acc` collects { skipped } from the reader.
export function collectFile({ store, reader, file, rows, ctx, acc = { skipped: 0, usage: new Set() } }) {
  let st;
  try { st = fs.statSync(file); } catch { return 0; }
  const base = identOf(st);
  const prev = store.getOffset(file);

  const fd = fs.openSync(file, 'r');
  let consumed = 0;
  try {
    const identAt = (n) => base + '|' + headOf(fd, n);
    let offset = 0;
    if (prev) {
      const bar = prev.ident.indexOf('|');
      const sameBase = bar >= 0 && prev.ident.slice(0, bar) === base;
      // The beginning the stored offset was taken over must still be there, byte for byte.
      const wantHead = bar >= 0 ? prev.ident.slice(bar + 1) : '';
      const headLen = Number(wantHead.split(':')[0]);
      if (sameBase && st.size >= prev.offset && Number.isFinite(headLen) && headOf(fd, headLen) === wantHead) offset = prev.offset;
    }
    if (prev && offset === st.size && offset === prev.offset) return 0;

    const size = st.size;
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
      const counts = store.apply(batch, { path: file, size, mtime: Math.round(st.mtimeMs), offset: next, ident: identAt(next) }, ctx && ctx.now ? ctx.now() : Date.now());
      for (const t of METRIC_TABLES) rows[t] += counts[t];
      // Live rows are counted DISTINCT over the whole pass, so the number does not depend on which of a
      // subagent's file and its parent's file is read first.
      if (acc.usage) { for (const k of counts.usageKeys) acc.usage.add(k); rows.tokens_usage = acc.usage.size; }
      acc.skipped += batch.skipped || 0;
      consumed += nl + 1;
      offset = next;
    }
    if (consumed === 0) {
      // Nothing complete to read, but record the identity so a later shrink or rewrite is noticed.
      store.apply({}, { path: file, size, mtime: Math.round(st.mtimeMs), offset, ident: identAt(offset) });
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
  store.reloadOrcRegistry();
  const rows = Object.fromEntries(METRIC_TABLES.map((t) => [t, 0]));
  let files = 0;
  let bytes = 0;
  let skippedOld = 0;
  const acc = { skipped: 0, usage: new Set() };
  const failures = [];
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
    try {
      bytes += collectFile({ store, reader: todo[i].reader, file: todo[i].file, rows, ctx: shared, acc });
    } catch (e) {
      failures.push({ file: todo[i].file, message: e && e.message ? e.message : String(e) });
    }
  }
  // Rows that went quiet while nothing was written to them are closed here (a session that simply stopped).
  store.settleUsage(ctx.now ? ctx.now() : Date.now());
  // The relay journal's headers are read in the same pass (read-only; see mail.mjs).
  const mail = collectMailHops({ store, home: opts.home, journal: opts.journal });
  return { files, bytes, rows, ms: clock() - t0, skippedOld, partial: left > 0, left, skipped: acc.skipped, errors: failures.length, failures, mail };
}

// THE LIVE VIEW: refresh tokens_usage for one session (-Session) or for every session whose transcript
// changed in the last LIVE_WINDOW_MS. It is runCollect's own per-file step (collectFile, from the stored
// offset), so only the bytes written since the last pass are read and there is no second parser. A file
// never collected before is read whole, exactly as collect would. Measured: see the PR description.
export const LIVE_WINDOW_MS = 10 * 60 * 1000;

export async function runLive({ store, opts = {}, readers = null, ctx = {}, session = null }) {
  const clock = opts.clock || Date.now;
  const t0 = clock();
  const list = readers || (await openReaders(opts));
  store.reloadOrcRegistry();
  const rows = Object.fromEntries(METRIC_TABLES.map((t) => [t, 0]));
  const acc = { skipped: 0, usage: new Set() };
  const failures = [];
  const shared = { ...ctx, opts };
  const sessions = new Set();
  let files = 0;
  let bytes = 0;
  const now = shared.now ? shared.now() : Date.now();
  const todo = [];
  for (const reader of list) {
    for (const root of reader.roots(opts)) {
      if (session) {
        // A reader that cannot find one session's files cheaply is asked for all of them and filtered.
        const found = reader.sessionFiles ? reader.sessionFiles(root, session) : reader.listFiles(root).filter((f) => f.includes(session));
        for (const file of found) todo.push({ reader, file });
        continue;
      }
      for (const file of reader.listFiles(root)) {
        let st;
        try { st = fs.statSync(file); } catch { continue; }
        if (now - st.mtimeMs <= LIVE_WINDOW_MS) todo.push({ reader, file });
      }
    }
  }
  for (const t of todo) {
    files++;
    try {
      bytes += collectFile({ store, reader: t.reader, file: t.file, rows, ctx: shared, acc });
    } catch (e) {
      failures.push({ file: t.file, message: e && e.message ? e.message : String(e) });
    }
  }
  store.settleUsage(now);
  const usage = session ? store.usageOf(session) : store.usageSince(now - LIVE_WINDOW_MS);
  for (const u of usage) sessions.add(u.session_id);
  return { files, bytes, rows, ms: clock() - t0, errors: failures.length, failures, usage, sessions: sessions.size };
}

export function liveLines(r) {
  const out = [];
  const short = (id) => (id.length > 8 ? id.slice(0, 8) : id);
  for (const u of r.usage) {
    out.push((u.agent_id === '' ? 'session ' + short(u.session_id) : '  agent ' + short(u.agent_id) + ' of ' + short(u.session_id)) +
      ' [' + (u.orc_id || '-') + '] ' + u.state + ' ' + u.model + ' context ' + u.context_tokens + '/' + u.context_limit + ' out ' + u.output_tokens +
      ' minutes ' + u.minutes_running.toFixed(1));
  }
  out.push('live: sessions=' + r.sessions + ' files=' + r.files + ' new_bytes=' + r.bytes + ' usage_rows=' + r.rows.tokens_usage + ' ms=' + r.ms + ' errors=' + r.errors);
  return out;
}

export function summaryLine(r) {
  const per = Object.keys(r.rows).map((t) => t + '=' + r.rows[t]).join(' ');
  return 'collect: ' + (r.partial ? 'partial (' + r.left + ' files left for the next pass) ' : '') + 'files=' + r.files + ' skipped_old=' + r.skippedOld +
    ' new_bytes=' + r.bytes + ' rows: ' + per + ' ms=' + r.ms + ' skipped=' + r.skipped + ' errors=' + r.errors;
}

export function mailLine(r) {
  return 'mail: journal_records=' + r.mail.seen + ' hops_added=' + r.mail.added + ' skipped_headers=' + r.mail.skipped;
}
