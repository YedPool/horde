// Work units as `horde work` uses them (design: planning/fleet-db-design.md "Work units (migration 6)"):
//   node work-cli.mjs start --kind agent|warg --parent-session <uuid> (--agent-id <id> [--agent-type <t>] | --session <uuid>)
//                           --work-type <t> [--task T-NNNN] [--domain <lane>] [--model <m>] [--at <ms or ISO>]
//   node work-cli.mjs end   (--parent-session <uuid> --agent-id <id> | --session <uuid>) --outcome done|failed|stopped|abandoned [--at ...]
//   node work-cli.mjs list  [--orc <letter or folder>] [--running] [--json]
// Called from hooks, so: one short transaction, ASCII output, one line per outcome.
// EXIT CODES: 0 done (an idempotent repeat is 0 and says "already started" / "already ended"),
//             1 refused or failed (one line, the reason), 2 no home, 3 "fleet.db busy" (the lock was not
//             free within HORDE_WORK_BUSY_MS, default 3000: a hook never hangs on a locked database).
// THE HOME comes from HORDE_HOME, as every fleet.db command (store.mjs dbPathFor).
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dbPathFor, openStore } from './store.mjs';
import { startWork, endWork, listWork, refuse } from './work.mjs';
import { parseTime } from './import.mjs';

export const VERBS = ['start', 'end', 'list'];
const BUSY_MS_DEFAULT = 3000;

// Flags that take a value, and flags that stand alone, per verb. An unknown flag or one given twice is refused.
const FLAGS = {
  start: { value: ['--kind', '--parent-session', '--agent-id', '--agent-type', '--session', '--work-type', '--task', '--domain', '--model', '--at'], bare: [] },
  end: { value: ['--parent-session', '--agent-id', '--session', '--outcome', '--at'], bare: [] },
  list: { value: ['--orc'], bare: ['--running', '--json'] },
};

export function parseFlags(verb, args) {
  const spec = FLAGS[verb];
  const got = {};
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    const isValue = spec.value.includes(a);
    if (!isValue && !spec.bare.includes(a)) throw refuse(verb + ': unknown argument ' + String(a).slice(0, 40));
    if (a in got) throw refuse(verb + ': ' + a + ' given twice');
    if (isValue) {
      // The value is the next word whatever it looks like: an agent id may begin with a dash.
      if (i + 1 >= args.length) throw refuse(verb + ': ' + a + ' needs a value');
      got[a] = args[++i];
    } else got[a] = true;
  }
  return got;
}

function timeFlag(v) {
  if (v === undefined) return undefined;
  if (/^\d{1,15}$/.test(v)) return Number(v);
  const t = parseTime(v);
  if (t === null) throw refuse('--at must be UTC milliseconds or a time like 2026-10-21T09:00:00Z');
  return t;
}

const ascii = (s) => String(s).replace(/[^\x20-\x7E]/g, (c) => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0'));

function isBusy(e) {
  return /database is locked|database table is locked|SQLITE_BUSY/i.test(String(e && e.message));
}

function openForReading(file, busyMs) {
  if (!fs.existsSync(file)) throw refuse('fleet.db does not exist yet at ' + file + '; run horde db init');
  try {
    return openStore(file, { readOnly: true, busyMs });
  } catch (e) {
    throw isBusy(e) ? e : refuse(String(e.message).replace('open it for writing once', 'run horde db init'));
  }
}

export function main(argv, env = process.env, out = (s) => process.stdout.write(s + '\n'), err = (s) => process.stderr.write(s + '\n')) {
  const verb = argv[0];
  if (!VERBS.includes(verb)) {
    err('usage: work-cli.mjs start | end | list (see horde work)');
    return 1;
  }
  let flags;
  try {
    flags = parseFlags(verb, argv.slice(1));
  } catch (e) {
    err('refused: ' + ascii(e.message));
    return 1;
  }
  let file;
  try {
    file = dbPathFor(env.HORDE_HOME);
  } catch (e) {
    err('fleet.db: ' + ascii(e.message));
    return 2;
  }
  const busyMs = /^\d+$/.test(env.HORDE_WORK_BUSY_MS ?? '') ? Number(env.HORDE_WORK_BUSY_MS) : BUSY_MS_DEFAULT;
  let db;
  try {
    db = verb === 'list' ? openForReading(file, busyMs) : openStore(file, { busyMs });
    if (verb === 'start') {
      const r = startWork(db, {
        kind: flags['--kind'], parentSession: flags['--parent-session'], agentId: flags['--agent-id'], agentType: flags['--agent-type'],
        session: flags['--session'], workType: flags['--work-type'], task: flags['--task'], domain: flags['--domain'], model: flags['--model'], at: timeFlag(flags['--at']),
      });
      for (const w of r.warnings) out(ascii(w));
      out((r.action === 'started' ? 'started ' : 'already started ') + flags['--kind'] + ' ' + r.id);
      return 0;
    }
    if (verb === 'end') {
      const r = endWork(db, { parentSession: flags['--parent-session'], agentId: flags['--agent-id'], session: flags['--session'], outcome: flags['--outcome'], at: timeFlag(flags['--at']) });
      out((r.action === 'ended' ? 'ended ' : 'already ended ') + r.id + ' as ' + r.outcome);
      return 0;
    }
    const rows = listWork(db, { orc: flags['--orc'] ?? null, running: flags['--running'] === true });
    if (flags['--json']) {
      const units = rows.map((r) => ({ ...r, started: new Date(r.started_at).toISOString(), ended: r.ended_at === null ? null : new Date(r.ended_at).toISOString() }));
      out(ascii(JSON.stringify({ units })));
      return 0;
    }
    if (rows.length === 0) { out('no work units'); return 0; }
    for (const r of rows) {
      out(ascii([new Date(r.started_at).toISOString(), r.kind, r.outcome, r.orc ?? '-', r.task ?? r.task_flag, r.work_type,
        r.kind === 'agent' ? r.agent_id : r.session_id, r.id].join(' ')));
    }
    return 0;
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
