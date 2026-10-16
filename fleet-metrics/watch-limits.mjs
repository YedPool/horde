// The limit watch: tells the master session when a session has been sitting at a usage limit.
//
// WHY IT IS ITS OWN SCRIPT AND NOT PART OF THE COLLECTOR. It runs every 2 minutes, the collector every
// 15, and a stuck Orc costs the fleet its idle hours: the earlier it is noticed the more is saved.
// So it must be cheap enough to run that often: it opens only the LAST 64 KB of each transcript
// changed in the last 6 hours, never a whole file, and the reader says what those bytes mean. A
// session counts as stuck when its last record is a limit hit, so a hit that was followed by more
// work is not reported at all.
//
// IT NEVER TYPES INTO A PANE OR A TERMINAL. It reads transcripts and sends one message through the
// fleet's mail (the `sender`, by default `horde meter tell`, which uses the Horde messenger port).
// A message typed into an input box could land in the middle of someone's sentence; mail cannot.
//
// DELIVERY IS AT LEAST ONCE, not exactly once. alerted_at is set after the message was taken, so a crash
// between the send and the mark makes the next run send that alert again: one repeated message, which
// is accepted over the opposite failure, a stop nobody was told about.
// ONE ALERT PER HIT. The hit's row carries alerted_at; it is set only after the message was taken,
// so a failed send is tried again two minutes later and a taken one never repeats. A hit is reported
// only after it has stood 5 minutes, so a limit that clears at once (a brief rejection) says nothing.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { openReaders } from './readers.mjs';

export const TAIL_BYTES = 64 * 1024;
export const RECENT_MS = 6 * 3600 * 1000;
export const ALERT_AFTER_MS = 5 * 60 * 1000;
// A hit older than this is history, not news: its session was either resumed in a way the tail does not
// show or abandoned, and telling the master about it now would only be noise.
export const STALE_HIT_MS = 12 * 3600 * 1000;
// On the very first run there is no record of what was already reported, so every stop that is already
// older than this is taken as known and recorded as alerted WITHOUT a message (alerted_silently = 1).
// Without it the first run would send one alert per old stop, a burst nobody can act on.
export const BASELINE_MS = 30 * 60 * 1000;
export const FIRST_RUN_KEY = 'watch_first_run_at';
const MAX_LINES = 10;

const LABELS = { seven_day: 'weekly', five_hour: '5-hour', seven_day_opus: 'weekly Opus', seven_day_sonnet: 'weekly Sonnet' };

const utc = (ms) => new Date(ms).toISOString().replace('T', ' ').slice(0, 16) + ' UTC';

export function alertText({ orc, session_id, agent_id, hit, now }) {
  const who = orc + ' (session ' + session_id.slice(0, 8) + (agent_id ? ', helper ' + String(agent_id).slice(0, 8) : '') + ')';
  const mins = Math.round((now - hit.at) / 60000);
  return (
    'Fleet meter: ' + who + ' has been stopped by its ' + (LABELS[hit.limit_type] || hit.limit_type) + ' usage limit since ' +
    utc(hit.at) + ' (' + mins + ' minutes ago) and has done nothing since. ' +
    (hit.resets_at ? 'The limit resets at ' + utc(hit.resets_at) + '. ' : 'The reset time is not known. ') +
    'Nothing was typed into it.'
  );
}

// ONE MESSAGE PER RUN: a run that finds several stopped sessions sends a single message that lists them
// (at most MAX_LINES lines, so it stays well under the tell's length limit), not one message each.
export function combinedText(items, now) {
  if (items.length === 1) return alertText({ ...items[0], now });
  const lines = items.slice(0, MAX_LINES).map((i) => '- ' + i.orc + ' (session ' + i.session_id.slice(0, 8) + (i.agent_id ? ', helper ' + String(i.agent_id).slice(0, 8) : '') + '): ' +
    (LABELS[i.hit.limit_type] || i.hit.limit_type) + ' limit since ' + utc(i.hit.at) + (i.hit.resets_at ? ', resets ' + utc(i.hit.resets_at) : ''));
  if (items.length > MAX_LINES) lines.push('- and ' + (items.length - MAX_LINES) + ' more');
  return 'Fleet meter: ' + items.length + ' sessions have been stopped by a usage limit for over 5 minutes and have done nothing since:\n' + lines.join('\n') + '\nNothing was typed into them.';
}

function readTail(file, size) {
  const len = Math.min(size, TAIL_BYTES);
  const fd = fs.openSync(file, 'r');
  try {
    const buf = Buffer.alloc(len);
    let got = 0;
    while (got < len) {
      const n = fs.readSync(fd, buf, got, len - got, size - len + got);
      if (n === 0) break;
      got += n;
    }
    return { text: buf.subarray(0, got).toString('utf8'), partialFirst: size > len };
  } finally {
    fs.closeSync(fd);
  }
}

// The default sender: `horde meter tell -File <text>` in a PowerShell of its own. The text goes through
// a file, never a command line (the fleet's rule: a tell carries no command and never rides one).
export function hordeSender(hordeScript, env = process.env) {
  return (text) => new Promise((resolve) => {
    if (!hordeScript) { resolve({ ok: false, detail: 'no way to reach the master session was given (--horde-script)' }); return; }
    const tmp = path.join(os.tmpdir(), 'fleet-meter-tell-' + process.pid + '-' + Date.now() + '.txt');
    fs.writeFileSync(tmp, text, 'ascii');
    execFile('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', hordeScript, 'meter', 'tell', '-File', tmp],
      { env, timeout: 90000, windowsHide: true }, (err, stdout, stderr) => {
        try { fs.unlinkSync(tmp); } catch { /* already gone */ }
        resolve({ ok: !err, detail: err ? String(stderr || stdout || err.message).trim().slice(0, 300) : String(stdout).trim() });
      });
  });
}

export async function runWatch({ store, opts = {}, readers = null, now = Date.now(), sender = null, dryRun = false, ctx = {} }) {
  const t0 = Date.now();
  const list = readers || (await openReaders(opts));
  const shared = { ...ctx, opts };
  const firstRun = store.getState(FIRST_RUN_KEY) == null;
  const out = { errors: 0, scanned: 0, alerts: 0, would: [], failed: 0, resumed: 0, silent: 0, messages: [], ms: 0, firstRun };
  const pending = [];
  for (const reader of list) {
    for (const root of reader.roots(opts)) {
      for (const file of reader.listFiles(root)) {
        // One unreadable transcript must not silence the watch for every other session.
        try {
          let st;
          try { st = fs.statSync(file); } catch { continue; }
          if (now - st.mtimeMs > RECENT_MS || st.size === 0) continue;
          out.scanned++;
          const tail = reader.inspectTail({ path: file, ...readTail(file, st.size), store, ctx: shared });
          if (!tail || tail.hits.length === 0) continue;
          for (const hit of tail.hits) {
            const row = {
              at: hit.at, session_id: tail.session_id, agent_id: tail.agent_id, orc: tail.orc, hit_uuid: hit.hit_uuid,
              limit_type: hit.limit_type, resets_at: hit.resets_at,
              stuck_until: hit.resumed_at, stuck_ms: hit.resumed_at == null ? null : hit.resumed_at - hit.at,
            };
            const before = store.limitByHit(hit.hit_uuid);
            if (hit.resumed_at != null && before && before.stuck_until == null) out.resumed++;
            if (!dryRun) store.apply({ tokens_limits: [row] }, null);
          }
          const last = tail.hits[tail.hits.length - 1];
          if (!tail.last_is_hit || last.resumed_at != null) continue;
          const age = now - last.at;
          if (age <= ALERT_AFTER_MS || age >= STALE_HIT_MS) continue;
          const existing = store.limitByHit(last.hit_uuid);
          if (existing && existing.alerted_at != null) continue;
          if (firstRun && age > BASELINE_MS) {
            if (!dryRun) store.markAlerted(last.hit_uuid, now, true);
            out.silent++;
            continue;
          }
          pending.push({ orc: tail.orc, session_id: tail.session_id, agent_id: tail.agent_id, hit: last });
        } catch { out.errors++; }
      }
    }
  }
  if (pending.length > 0) {
    const text = combinedText(pending, now);
    if (dryRun) out.would.push(text);
    else {
      const r = await sender(text);
      if (r.ok) {
        for (const i of pending) store.markAlerted(i.hit.hit_uuid, now);
        out.alerts = pending.length;
        out.messages.push(text);
      } else { out.failed = pending.length; out.lastError = r.detail; }
    }
  }
  if (!dryRun && firstRun) store.setState(FIRST_RUN_KEY, now);
  out.ms = Date.now() - t0;
  return out;
}

export function watchSummary(r, dryRun) {
  return 'watch-limits: scanned=' + r.scanned + (dryRun ? ' would_send=' + r.would.length : ' alerts=' + r.alerts + ' messages=' + r.messages.length) +
    ' silent=' + r.silent + ' resumed=' + r.resumed + ' failed=' + r.failed + ' errors=' + r.errors + ' ms=' + r.ms;
}
