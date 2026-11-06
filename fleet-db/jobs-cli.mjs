// Jobs and signals as `horde job` and `horde signal` use them (design: planning/fleet-db-design.md "Jobs and signals"):
//   node jobs-cli.mjs job upsert --id <id> --owner <o> (--job <text> | --file <path>) [--session <uuid>] [--started <ms or ISO>] [--due <ms or ISO>] [--waiting-on <text> | --not-waiting] --by <who>
//   node jobs-cli.mjs job done   --id <id> (--proof <text> | --file <path>) --by <who> [--at <ms or ISO>]
//   node jobs-cli.mjs job list   [--open] [--owner <o>] [--overdue] [--not-waiting] [--json]
//   node jobs-cli.mjs signal raise --key <k> --kind <kind> [--owner <o>] (--text <text> | --file <path>) [--at <ms or ISO>] [--urgent] [--quiet]
//   node jobs-cli.mjs signal woke  --key <k> [--at <ms or ISO>]
//   node jobs-cli.mjs signal close --key <k> --by <who>
//   node jobs-cli.mjs signal list  [--open] [--owner <o>] [--unwoken] [--mark-woke [--at <ms or ISO>]] [--json]   (--mark-woke implies --unwoken)
//   node jobs-cli.mjs signal prune --days <n>
// The overseer's write path: one short transaction per call, ASCII output, one line per outcome (the rules are in jobs.mjs).
// NEVER MAKES OR MIGRATES THE DATABASE, as orc-cli.mjs: a missing fleet.db is exit 4, and a file older or newer than this
// code is refused in words by the read-only open that comes first (`horde db init` owns the migration).
// EXIT CODES: 0 done (a repeat is 0 and says "kept"), 1 refused or failed (one line, the reason), 2 no home,
//   3 "fleet.db busy" (the lock was not free within HORDE_JOBS_BUSY_MS, default 3000), 4 no fleet.db yet.
// LONG TEXT comes from --file (a job's text, a signal's text, a proof): nobody has to quote it through two shells. The path
// must be absolute (PowerShell makes it so); a file over 64 KB, in UTF-16, or holding more than ASCII is refused in words.
// THE HOME comes from HORDE_HOME, else the home pointer, as every fleet.db command (store.mjs homeFromEnv).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { dbPathFor, homeFromEnv, openStore } from './store.mjs';
import { refuse } from './work.mjs';
import { LIMITS, upsertJob, doneJob, listJobs, raiseSignal, wokeSignal, closeSignal, listSignals, pruneSignals } from './jobs.mjs';

const BUSY_MS_DEFAULT = 3000;

// Flags that take a value, and flags that stand alone, per noun and verb. An unknown flag or one given twice is refused.
const FLAGS = {
  'job upsert': { value: ['--id', '--owner', '--job', '--file', '--session', '--started', '--due', '--waiting-on', '--by'], bare: ['--not-waiting'] },
  'job done': { value: ['--id', '--proof', '--file', '--by', '--at'], bare: [] },
  'job list': { value: ['--owner'], bare: ['--open', '--overdue', '--not-waiting', '--json'] },
  'signal raise': { value: ['--key', '--kind', '--owner', '--text', '--file', '--at'], bare: ['--urgent', '--quiet'] },
  'signal woke': { value: ['--key', '--at'], bare: [] },
  'signal close': { value: ['--key', '--by'], bare: [] },
  'signal list': { value: ['--owner', '--at'], bare: ['--open', '--unwoken', '--mark-woke', '--json'] },
  'signal prune': { value: ['--days'], bare: [] },
};
// Required flags per verb, and the pair of which exactly one is wanted (the text may come from the command line or a file).
const REQUIRED = {
  'job upsert': ['--id', '--owner', '--by'], 'job done': ['--id', '--by'], 'job list': [],
  'signal raise': ['--key', '--kind'], 'signal woke': ['--key'], 'signal close': ['--key', '--by'], 'signal list': [], 'signal prune': ['--days'],
};
const TEXT_FLAG = { 'job upsert': '--job', 'job done': '--proof', 'signal raise': '--text' };

const ascii = (s) => String(s).replace(/[^\x20-\x7E]/g, (c) => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0'));
const isBusy = (e) => /database is locked|database table is locked|SQLITE_BUSY/i.test(String(e && e.message));
const isRooted = (p) => (process.platform === 'win32' ? /^([A-Za-z]:[\\/]|\\\\[^\\/])/.test(p) : path.isAbsolute(p));

export function parseFlags(verb, args) {
  const spec = FLAGS[verb];
  const got = {};
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    const isValue = spec.value.includes(a);
    if (!isValue && !spec.bare.includes(a)) throw refuse(verb + ': unknown argument ' + String(a).slice(0, 40));
    if (a in got) throw refuse(verb + ': ' + a + ' given twice');
    if (isValue) {
      // The value is the next word whatever it looks like: a text may begin with a dash.
      if (i + 1 >= args.length) throw refuse(verb + ': ' + a + ' needs a value');
      got[a] = args[++i];
    } else got[a] = true;
  }
  for (const f of REQUIRED[verb]) if (!(f in got)) throw refuse(verb + ': ' + f + ' is required');
  const textFlag = TEXT_FLAG[verb];
  if (textFlag) {
    if ((textFlag in got) === ('--file' in got)) throw refuse(verb + ': give exactly one of ' + textFlag + ' and --file');
  }
  return got;
}

// The text of a --file, or the flag's own value. Read before the transaction opens (no file read under the write lock).
function textFrom(flags, verb) {
  const flag = TEXT_FLAG[verb];
  if (!('--file' in flags)) return flags[flag];
  const file = flags['--file'];
  if (!isRooted(file)) throw refuse('--file must be an absolute path');
  let st;
  try { st = fs.statSync(file); } catch { throw refuse('--file cannot be read: ' + ascii(path.basename(file))); }
  if (!st.isFile()) throw refuse('--file is not a file');
  if (st.size > LIMITS.fileBytes) throw refuse('--file is ' + st.size + ' bytes; the most is ' + LIMITS.fileBytes);
  const buf = fs.readFileSync(file);
  // PowerShell 5.1 writes UTF-16 for `>` and Out-File: said in words, not as 4000 mystery characters.
  if (buf.length >= 2 && ((buf[0] === 0xFF && buf[1] === 0xFE) || (buf[0] === 0xFE && buf[1] === 0xFF))) throw refuse('--file is UTF-16 text; save it as ASCII or UTF-8');
  try { return new TextDecoder('utf-8', { fatal: true }).decode(buf); } catch { throw refuse('--file is not UTF-8 text'); }
}

// A time shown on one plain line: the ISO time, or "-" when there is none.
const show = (v) => (v === null ? '-' : v);
const oneLine = (s) => s.replace(/\s+/g, ' ').slice(0, 100);

export function main(argv, env = process.env, out = (s) => process.stdout.write(s + '\n'), err = (s) => process.stderr.write(s + '\n'), { now = Date.now } = {}) {
  const verb = argv[0] + ' ' + argv[1];
  if (!(verb in FLAGS)) {
    err('usage: jobs-cli.mjs job upsert | done | list, or signal raise | close | list | prune (see horde job, horde signal)');
    return 1;
  }
  let flags;
  let text;
  try {
    flags = parseFlags(verb, argv.slice(2));
    if (TEXT_FLAG[verb]) text = textFrom(flags, verb);
  } catch (e) {
    err('refused: ' + ascii(e.message));
    return 1;
  }
  let file;
  try {
    file = dbPathFor(homeFromEnv(env));
  } catch (e) {
    err('fleet.db: ' + ascii(e.message));
    return 2;
  }
  if (!fs.existsSync(file)) { err('fleet.db does not exist yet (run horde db init)'); return 4; }
  const busyMs = /^\d+$/.test(env.HORDE_JOBS_BUSY_MS ?? '') ? Number(env.HORDE_JOBS_BUSY_MS) : BUSY_MS_DEFAULT;
  const writes = !verb.endsWith(' list') || flags['--mark-woke'] === true;
  let db;
  try {
    // Opened read-only first, which refuses a fleet.db older or newer than this code: a migration is never run from inside
    // one of these calls (its lock wait is short and its caller is a loop); `horde db init` owns it.
    try {
      db = openStore(file, { readOnly: true, busyMs });
    } catch (e) {
      if (isBusy(e)) throw e;
      err('fleet.db: ' + ascii(String(e.message).replace('open it for writing once', 'run horde db init')));
      return 1;
    }
    if (writes) { db.close(); db = openStore(file, { busyMs }); }
    const clock = { now };
    switch (verb) {
      case 'job upsert': {
        const r = upsertJob(db, { id: flags['--id'], owner: flags['--owner'], job: text, session: flags['--session'], started: flags['--started'], due: flags['--due'], waitingOn: flags['--waiting-on'], notWaiting: flags['--not-waiting'] === true, by: flags['--by'] }, clock);
        out(r.action + ' ' + ascii(flags['--id']) + (r.action === 'updated' ? ' (' + r.changed.join(', ') + ')' : ''));
        return 0;
      }
      case 'job done': {
        const r = doneJob(db, { id: flags['--id'], proof: text, by: flags['--by'], at: flags['--at'] }, clock);
        out(r.action + ' ' + ascii(flags['--id']));
        return 0;
      }
      case 'job list': {
        const rows = listJobs(db, { open: flags['--open'] === true, owner: flags['--owner'] ?? null, overdue: flags['--overdue'] === true, notWaiting: flags['--not-waiting'] === true }, clock);
        if (flags['--json']) { out(ascii(JSON.stringify({ jobs: rows }))); return 0; }
        if (rows.length === 0) { out('no jobs'); return 0; }
        for (const r of rows) {
          out(ascii([r.id, r.owner, r.overdue ? 'overdue' : r.state, 'started=' + r.started, 'due=' + show(r.due), 'done=' + show(r.done), ...(r.waiting_on === null ? [] : ['waiting=' + oneLine(r.waiting_on).replace(/ /g, '_')]), '|', oneLine(r.job)].join(' ')));
        }
        return 0;
      }
      case 'signal raise': {
        const r = raiseSignal(db, { key: flags['--key'], kind: flags['--kind'], owner: flags['--owner'], text, at: flags['--at'], urgent: flags['--urgent'] === true, quiet: flags['--quiet'] === true }, clock);
        out(r.action + ' ' + ascii(flags['--key']) + (r.action === 'kept' ? '' : ' (count ' + r.count + ')'));
        return 0;
      }
      case 'signal woke': {
        const r = wokeSignal(db, { key: flags['--key'], at: flags['--at'] }, clock);
        out(r.action + ' ' + ascii(flags['--key']));
        return 0;
      }
      case 'signal close': {
        const r = closeSignal(db, { key: flags['--key'], by: flags['--by'] }, clock);
        out(r.action + ' ' + ascii(flags['--key']));
        return 0;
      }
      case 'signal list': {
        const rows = listSignals(db, { open: flags['--open'] === true, owner: flags['--owner'] ?? null, unwoken: flags['--unwoken'] === true, markWoke: flags['--mark-woke'] === true, at: flags['--at'] ?? null }, clock);
        if (flags['--json']) { out(ascii(JSON.stringify({ signals: rows }))); return 0; }
        if (rows.length === 0) { out('no signals'); return 0; }
        for (const r of rows) {
          // The owner may hold spaces, so on this plain line they read as underscores (-Json carries it exactly).
          out(ascii([r.key, r.kind, r.owner === null ? '-' : r.owner.replace(/ /g, '_'), r.state, 'count=' + r.count, ...(r.urgent ? ['urgent'] : []), ...(r.quiet ? ['quiet'] : []),
            'first=' + r.first, 'last=' + r.last, 'woke=' + show(r.woke), 'ok=' + show(r.woke_ok), '|', oneLine(r.text)].join(' ')));
        }
        return 0;
      }
      default: {
        const r = pruneSignals(db, { days: flags['--days'] }, clock);
        out('pruned ' + r.pruned + ' closed signal' + (r.pruned === 1 ? '' : 's') + ' closed more than ' + flags['--days'] + ' days ago');
        return 0;
      }
    }
  } catch (e) {
    if (isBusy(e)) { err('fleet.db busy'); return 3; }
    err(e.refusal ? 'refused: ' + ascii(e.message) : 'fleet.db: ' + ascii(e.message));
    return 1;
  } finally {
    if (db) db.close();
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  process.exitCode = main(process.argv.slice(2));
}
