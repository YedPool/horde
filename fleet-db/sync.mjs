// `horde db sync` (T-0389, piece 1 of T-0299): keeps task_event, changelog_entry, orc and orc_status current from the
// fleet's files, from ONE scheduled task that ticks every minute (fleet-db/register-sync.ps1). Node side; the
// PowerShell side (fleet-db/Sync.ps1) holds the lock, the time limit, the priority and the run log.
//   node cli.mjs sync [--force] [--snapshot f | --snapshot-error text]
//   node cli.mjs sync --save [--ledger f] [--pr-cache f] [--changelog f] [--cards dir] [--thrall-card f]   (saves, then syncs)
//   node cli.mjs sync --note-timeout <ms>      (records that the PowerShell side killed a run; opens no database)
// --snapshot is the sessions step's input: a JSON file the port side wrote this tick (fleet/SessionSnapshot.ps1, shape in
// sessions.mjs). --snapshot-error says why there is none (the producer failed or timed out), so the step records a failure
// instead of silence. With neither, the sessions step is not part of the run (a hand `node cli.mjs sync`).
// STDOUT: one line "sync: ..." naming the step run or skipped and the rows added; the caller logs it.
// EXIT CODES: 0 done or nothing due, 1 refused or failed, 2 no home.
//
// THE SOURCES ARE NEVER DEFAULTED (the importer's rule): they are read from HORDE_HOME\settings\fleet-db-sync.json,
// written only by --save, every path absolute. No settings file is a refusal that names the --save form. The
// sync takes no registry, decisions or lots source: the sessions step is fed by a snapshot (below), and decisions are
// written live by publish.
//
// WHAT RUNS: the existing importFleet, unchanged in meaning (one inWrite transaction, idempotent), so a run that is
// killed part way leaves the database as it was. Rows stay backfill 1: they come from files, and the content hash
// holds backfill, so flipping it would write every old task_event again.
//
// CADENCE: the tick is every minute and each STEP has its own pace, kept in HORDE_HOME\fleet-db-sync-state.json:
//   { "schema": 1, "files": { "lastOkAt", "lastRunAt", "lastResult": "ok|failed|timeout", "lastMs" },
//                  "sessions": { the same four, and "counts": { live, idle, waiting-person, dead, unknown } } }
// The files step runs when its lastOkAt is FILES_EVERY_MS or more ago (or with --force). A failed or timed-out
// run does not move lastOkAt, so it is tried again on the next tick. The sessions step (T-0409, sessions.mjs) runs on
// EVERY tick that has a snapshot, whether or not the files step was due. A step is one key in the state and one block in
// syncMain; unknown keys are kept when the state is written.
// THE STEPS DO NOT BLOCK EACH OTHER: each runs in its own try, records its own result, and the one line says both
// ("sync: files skipped (...); sessions ran, ..."). A failure of either makes the run exit 1 after both have had their turn.
import fs from 'node:fs';
import path from 'node:path';
import { dbPathFor, homeFromEnv, openStore } from './store.mjs';
import { importFleet } from './import.mjs';
import { runSessionsStep } from './sessions.mjs';

export const SETTINGS_SCHEMA = 1;
export const STATE_SCHEMA = 1;
export const FILES_EVERY_MS = 5 * 60 * 1000;
export const SAVE_FORM = 'horde db sync -Save -Ledger <tasks.jsonl> -PrCache <pr-cache.json> -Changelog <changelog.jsonl> -Cards <orcs folder> -ThrallCard <status.txt>';

// importFleet's source names, and the flag of each.
const SOURCE_FLAGS = { '--ledger': 'ledger', '--pr-cache': 'prCache', '--changelog': 'changelog', '--cards': 'cards', '--thrall-card': 'thrallCard' };
export const SOURCE_KEYS = Object.values(SOURCE_FLAGS);

// A drive or UNC path on Windows (a path with no drive depends on the current drive), else any absolute path.
const rooted = (p) => (process.platform === 'win32' ? /^([A-Za-z]:[\\/]|\\\\[^\\/])/.test(p) : path.isAbsolute(p));

export const settingsFile = (home) => path.join(home, 'settings', 'fleet-db-sync.json');
export const stateFile = (home) => path.join(home, 'fleet-db-sync-state.json');

// A file whole or not at all: a temp file beside it, then one rename (which replaces on Windows and POSIX).
export function writeFileAtomic(file, text) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = file + '.tmp-' + process.pid + '-' + Math.random().toString(16).slice(2, 10);
  try {
    fs.writeFileSync(temp, text);
    fs.renameSync(temp, file);
  } finally {
    if (fs.existsSync(temp)) fs.rmSync(temp, { force: true });
  }
}

export function parseSyncArgs(args) {
  const out = { force: false, save: false, sources: {}, noteTimeoutMs: null, snapshot: null, snapshotError: null };
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--force') { out.force = true; continue; }
    if (a === '--save') { out.save = true; continue; }
    if (a === '--note-timeout') {
      const v = args[i + 1];
      if (v === undefined || !/^\d{1,9}$/.test(v)) throw new Error('sync: --note-timeout needs the milliseconds the run took');
      out.noteTimeoutMs = Number(v);
      i++;
      continue;
    }
    if (a === '--snapshot' || a === '--snapshot-error') {
      const v = args[i + 1];
      const field = a === '--snapshot' ? 'snapshot' : 'snapshotError';
      if (v === undefined || v === '' || (a === '--snapshot' && v.startsWith('--'))) throw new Error('sync: ' + a + ' needs ' + (a === '--snapshot' ? 'a path' : 'the reason'));
      if (out[field] !== null) throw new Error('sync: ' + a + ' given twice');
      out[field] = v;
      i++;
      continue;
    }
    const key = SOURCE_FLAGS[a];
    if (!key) throw new Error('sync: unknown argument ' + String(a).slice(0, 40));
    if (key in out.sources) throw new Error('sync: ' + a + ' given twice');
    const v = args[i + 1];
    if (v === undefined || v === '' || v.startsWith('--')) throw new Error('sync: ' + a + ' needs a path');
    out.sources[key] = v;
    i++;
  }
  if (out.snapshot !== null && out.snapshotError !== null) throw new Error('sync: --snapshot and --snapshot-error are one or the other');
  if (!out.save && Object.keys(out.sources).length > 0) throw new Error('sync: source paths are only taken with -Save (they are saved, not used once)');
  if (out.save && Object.keys(out.sources).length === 0) throw new Error('sync: -Save needs at least one of ' + Object.keys(SOURCE_FLAGS).join(', '));
  return out;
}

// The saved sources, or an Error whose message says what to do.
export function readSettings(home) {
  const file = settingsFile(home);
  if (!fs.existsSync(file)) throw new Error('sync: no sources are saved (' + file + '); save them once with ' + SAVE_FORM);
  let obj;
  try { obj = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '')); } catch { obj = null; }
  if (obj === null || typeof obj !== 'object' || Array.isArray(obj) || obj.schema !== SETTINGS_SCHEMA) {
    throw new Error('sync: ' + file + ' is not a schema ' + SETTINGS_SCHEMA + ' settings file; save the sources again with ' + SAVE_FORM);
  }
  const sources = {};
  for (const [k, v] of Object.entries(obj)) {
    if (k === 'schema') continue;
    if (!SOURCE_KEYS.includes(k)) throw new Error('sync: ' + file + ' names an unknown source ' + k.slice(0, 40));
    if (typeof v !== 'string' || !rooted(v)) throw new Error('sync: ' + file + ' source ' + k + ' is not an absolute path');
    sources[k] = v;
  }
  if (Object.keys(sources).length === 0) throw new Error('sync: ' + file + ' names no source; save them with ' + SAVE_FORM);
  return sources;
}

export function saveSettings(home, sources) {
  for (const [k, v] of Object.entries(sources)) if (!rooted(v)) throw new Error('sync: the ' + k + ' path must be absolute, not ' + String(v).slice(0, 80));
  const obj = { schema: SETTINGS_SCHEMA };
  for (const k of SOURCE_KEYS) if (k in sources) obj[k] = sources[k];
  writeFileAtomic(settingsFile(home), JSON.stringify(obj, null, 2) + '\n');
}

const COUNT_KEYS = ['live', 'idle', 'waiting-person', 'dead', 'unknown'];
const whole = (v) => (Number.isSafeInteger(v) && v >= 0 ? v : null);

// The state, with anything missing or unreadable as "never": a damaged state file costs one early run, never a refusal.
export function readState(home) {
  let obj = null;
  try { obj = JSON.parse(fs.readFileSync(stateFile(home), 'utf8').replace(/^\uFEFF/, '')); } catch { obj = null; }
  if (obj === null || typeof obj !== 'object' || Array.isArray(obj) || obj.schema !== STATE_SCHEMA) obj = { schema: STATE_SCHEMA };
  const f = obj.files !== null && typeof obj.files === 'object' && !Array.isArray(obj.files) ? obj.files : {};
  const step = (x) => ({ lastOkAt: whole(x.lastOkAt), lastRunAt: whole(x.lastRunAt), lastResult: ['ok', 'failed', 'timeout'].includes(x.lastResult) ? x.lastResult : null, lastMs: whole(x.lastMs) });
  const sv = obj.sessions !== null && typeof obj.sessions === 'object' && !Array.isArray(obj.sessions) ? obj.sessions : {};
  const counts = sv.counts !== null && typeof sv.counts === 'object' && !Array.isArray(sv.counts) ? sv.counts : null;
  return {
    ...obj,
    schema: STATE_SCHEMA,
    files: step(f),
    sessions: { ...step(sv), counts: counts === null ? null : Object.fromEntries(COUNT_KEYS.map((k) => [k, whole(counts[k]) ?? 0])) },
  };
}

export function writeState(home, state) {
  writeFileAtomic(stateFile(home), JSON.stringify(state, null, 2) + '\n');
}

// Due when never run OK, when FILES_EVERY_MS have passed since the last OK, or when the clock has gone back past it.
export function filesDue(state, now, force) {
  if (force) return true;
  const ok = state.files.lastOkAt;
  return ok === null || now - ok >= FILES_EVERY_MS || now < ok;
}

// The line `horde db status` adds.
export function describeSync(home) {
  const f = readState(home).files;
  if (f.lastOkAt === null && f.lastResult === null) return 'sync: never synced';
  const ok = f.lastOkAt === null ? 'never ok' : 'files last ok ' + new Date(f.lastOkAt).toISOString();
  return 'sync: ' + ok + ', last run ' + (f.lastResult ?? 'unknown') + (f.lastRunAt === null ? '' : ' at ' + new Date(f.lastRunAt).toISOString());
}

// The line `horde db status` adds for the sessions step: when it last ran well, how the last run ended, and the sessions by
// state ('unknown' are the ones the sync could not judge: their stamp is old on purpose).
export function describeSessions(home) {
  const s = readState(home).sessions;
  if (s.lastOkAt === null && s.lastResult === null) return 'sessions: never synced';
  const ok = s.lastOkAt === null ? 'never ok' : 'last ok ' + new Date(s.lastOkAt).toISOString();
  const by = s.counts === null ? '' : ', ' + COUNT_KEYS.map((k) => k + ' ' + s.counts[k]).join(', ');
  return 'sessions: ' + ok + ', last run ' + (s.lastResult ?? 'unknown') + (s.lastRunAt === null ? '' : ' at ' + new Date(s.lastRunAt).toISOString()) + by;
}

// How the sessions step says what it did: the sessions by state and what changed.
export function sessionsSummary(r) {
  const c = r.counts;
  return r.sessions + ' sessions (' + COUNT_KEYS.map((k) => c[k] + ' ' + k).join(', ') + '), ' + r.added + ' added, ' + r.changed + ' changed, panes +'
    + r.paneOpened + ' -' + r.paneClosed + ' moved ' + r.moved + (r.deferred > 0 ? ', ' + r.deferred + ' read later' : '');
}

// The rows added per table that changed, as "task_event +3, changelog_entry +1", or "no rows added".
export function addedSummary(report) {
  const parts = [];
  for (const [t, c] of Object.entries(report.tables)) if (c.added > 0) parts.push(t + ' +' + c.added);
  return parts.length === 0 ? 'no rows added' : parts.join(', ');
}

export function syncMain(argv, env = process.env, out = (s) => process.stdout.write(s + '\n'), err = (s) => process.stderr.write(s + '\n'), { now = () => Date.now() } = {}) {
  let req;
  try {
    req = parseSyncArgs(argv);
  } catch (e) {
    err('fleet.db: ' + e.message);
    return 1;
  }
  let home;
  let file;
  try {
    home = homeFromEnv(env);
    file = dbPathFor(home);
  } catch (e) {
    err('fleet.db: ' + e.message);
    return 2;
  }
  try {
    if (req.noteTimeoutMs !== null) {
      // The caller killed this run (its time limit), so nothing here ran to say so. lastOkAt is not moved. Which step was
      // running cannot be told, so both are marked: each was still due its next run, and each runs again next tick.
      const state = readState(home);
      state.files = { ...state.files, lastRunAt: now(), lastResult: 'timeout', lastMs: req.noteTimeoutMs };
      state.sessions = { ...state.sessions, lastRunAt: now(), lastResult: 'timeout', lastMs: req.noteTimeoutMs };
      writeState(home, state);
      out('sync: files timeout recorded');
      return 0;
    }
    if (req.save) saveSettings(home, req.sources);
    const state = readState(home);
    const start = now();
    const parts = [];
    const failures = [];
    let dirty = false;

    // ---- the files step. A refusal (no sources saved) is a failure of THIS step only, and leaves no state.
    try {
      const sources = readSettings(home);
      // A save always runs: new sources must not wait out the pace of the old ones.
      if (!filesDue(state, start, req.force || req.save)) {
        parts.push('files skipped (last ok ' + Math.floor((start - state.files.lastOkAt) / 1000) + ' s ago, runs every ' + FILES_EVERY_MS / 60000 + ' min)');
      } else {
        try {
          if (!fs.existsSync(file)) throw new Error('fleet.db does not exist yet at ' + file + '; run horde db init');
          const db = openStore(file);
          let report;
          try { report = importFleet(db, sources); } finally { db.close(); }
          state.files = { lastOkAt: now(), lastRunAt: start, lastResult: 'ok', lastMs: now() - start };
          parts.push('files ran, ' + addedSummary(report) + (report.unlinked.length > 0 ? ', ' + report.unlinked.reduce((n, u) => n + u.count, 0) + ' lines or cards not linked' : ''));
        } catch (e) {
          // A failed run is recorded; lastOkAt stays, so the next tick retries.
          state.files = { ...state.files, lastRunAt: start, lastResult: 'failed', lastMs: now() - start };
          throw e;
        } finally {
          dirty = true;
        }
      }
    } catch (e) {
      failures.push(e.message);
      parts.push('files failed: ' + e.message);
    }

    // ---- the sessions step: every tick that has a snapshot (or the reason it has none). Its own try: a files failure
    // above never stops it, and a failure here never loses the files result already in `state`.
    if (req.snapshot !== null || req.snapshotError !== null) {
      const t0 = now();
      try {
        if (req.snapshotError !== null) throw new Error('no session snapshot this tick: ' + req.snapshotError);
        let raw;
        try { raw = JSON.parse(fs.readFileSync(req.snapshot, 'utf8').replace(/^\uFEFF/, '')); } catch (e) { throw new Error('the session snapshot ' + req.snapshot + ' could not be read: ' + e.message); }
        if (!fs.existsSync(file)) throw new Error('sessions: fleet.db does not exist yet at ' + file + '; run horde db init');
        const db = openStore(file);
        let r;
        try { r = runSessionsStep(db, raw, { now: t0 }); } finally { db.close(); }
        state.sessions = { lastOkAt: now(), lastRunAt: t0, lastResult: 'ok', lastMs: now() - t0, counts: r.counts };
        parts.push('sessions ran, ' + sessionsSummary(r));
      } catch (e) {
        state.sessions = { ...state.sessions, lastRunAt: t0, lastResult: 'failed', lastMs: now() - t0 };
        failures.push(e.message);
        parts.push('sessions failed: ' + e.message);
      } finally {
        dirty = true;
      }
    }

    // A state that cannot be written must not hide why a step failed.
    if (dirty) {
      try { writeState(home, state); } catch (e) { if (failures.length === 0) throw e; }
    }
    if (failures.length > 0) {
      // One failed step and nothing else said: the plain reason, as before. Otherwise the line names both steps.
      err('fleet.db: ' + (parts.length === 1 ? failures[0] : 'sync: ' + parts.join('; ')));
      return 1;
    }
    out('sync: ' + parts.join('; '));
    return 0;
  } catch (e) {
    err('fleet.db: ' + e.message);
    return 1;
  }
}
