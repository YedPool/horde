// The fleet's open tasks, read from fleet.db, as `horde task list` prints them (T-0299; design: planning/fleet-db-design.md, "Task state"):
//   node task-cli.mjs list [--orc <letter or lane folder>] [--json]
// Every live task is printed. A task an Orc owns inside another Orc's list comes out under that Orc too, or it would be numbered
// out of its owner's sight; a task with no Orc to name comes out in a list of its own. Done tasks wait for verification and take
// no number, so they are counted on the last line and not hidden without a word.
// It only reads: it never makes the database and never migrates it. The ledger stays the source of tasks for now, and reaches
// fleet.db by the sync every 5 minutes, so a task opened this minute can be missing here.
// EXIT CODES: 0 done, 1 refused or failed (one line, the reason), 2 no home, 3 "fleet.db busy" (the lock was not free within
// HORDE_TASK_BUSY_MS, default 3000), 4 no fleet.db yet.
// THE HOME comes from HORDE_HOME, else the home pointer, as every fleet.db command (store.mjs homeFromEnv).
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dbPathFor, homeFromEnv, openStore } from './store.mjs';

const BUSY_MS_DEFAULT = 3000;
const NO_ORC = 'no Orc';
const USAGE = 'usage: task-cli.mjs list [--orc <letter or lane folder>] [--json]';
const ascii = (s) => String(s).replace(/[^\x20-\x7E]/g, (c) => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0'));
const isBusy = (e) => /database is locked|database table is locked|SQLITE_BUSY/i.test(String(e && e.message));

function refusal(message) {
  const e = new Error(message);
  e.refusal = true;
  return e;
}

// orc: a letter or a lane folder, or null for every list. Rows come in list order, the lists by letter, the one with no Orc last.
export function listTasks(db, { orc = null } = {}) {
  let orcId = null;
  if (orc !== null) {
    const o = db.prepare('SELECT id FROM orc WHERE letter = ? OR lane_dir = ?').get(orc, orc);
    if (!o) throw refusal('no Orc is called ' + orc);
    orcId = o.id;
  }
  const tasks = db.prepare(`SELECT l.letter AS list, t.path, t.depth, t.key AS task, t.state, t.prio, t.due_at, o.letter AS owner, t.title
    FROM task_tree t JOIN task_now n ON n.id = t.id
    LEFT JOIN orc l ON l.id = t.owner_orc_id LEFT JOIN orc o ON o.id = n.owner_orc_id
    WHERE ?1 IS NULL OR t.owner_orc_id = ?1 OR n.owner_orc_id = ?1
    ORDER BY l.letter IS NULL, l.letter, t.sort`).all(orcId).map((r) => ({ ...r }));
  const unverified = db.prepare("SELECT count(*) AS n FROM task_now WHERE state = 'done' AND (?1 IS NULL OR owner_orc_id = ?1)").get(orcId).n;
  return { tasks, unverified };
}

// One line: the number, the task, its state and priority, who owns it when that is not whose list it is in, when it is due, its title.
function line(r) {
  const indent = '  '.repeat(r.depth);
  const words = [indent + r.path, r.task, r.state ?? 'no-state', 'p' + (r.prio ?? '-')];
  if (r.owner !== r.list) words.push('owner=' + (r.owner ?? NO_ORC.replace(' ', '-')));
  if (r.due_at !== null) words.push('due=' + new Date(r.due_at).toISOString());
  return words.join(' ') + ' | ' + r.title;
}

export function main(argv, env = process.env, out = (s) => process.stdout.write(s + '\n'), err = (s) => process.stderr.write(s + '\n')) {
  const flags = {};
  if (argv[0] !== 'list') { err(USAGE); return 1; }
  for (let i = 1; i < argv.length; i++) {
    const a = argv[i];
    if (a !== '--orc' && a !== '--json') { err('refused: list: unknown argument ' + ascii(a).slice(0, 40)); return 1; }
    if (a in flags) { err('refused: list: ' + a + ' given twice'); return 1; }
    if (a === '--orc' && i + 1 >= argv.length) { err('refused: list: --orc needs a value'); return 1; }
    flags[a] = a === '--orc' ? argv[++i] : true;
  }
  let file;
  try {
    file = dbPathFor(homeFromEnv(env));
  } catch (e) {
    err('fleet.db: ' + ascii(e.message));
    return 2;
  }
  if (!fs.existsSync(file)) { err('fleet.db does not exist yet (run horde db init)'); return 4; }
  const busyMs = /^\d+$/.test(env.HORDE_TASK_BUSY_MS ?? '') ? Number(env.HORDE_TASK_BUSY_MS) : BUSY_MS_DEFAULT;
  let db;
  try {
    db = openStore(file, { readOnly: true, busyMs });
    const { tasks, unverified } = listTasks(db, { orc: flags['--orc'] ?? null });
    if (flags['--json']) {
      out(ascii(JSON.stringify({ tasks: tasks.map((r) => ({ ...r, due: r.due_at === null ? null : new Date(r.due_at).toISOString() })), done_not_verified: unverified })));
      return 0;
    }
    let shown;
    for (const r of tasks) {
      const name = r.list ?? NO_ORC;
      if (name !== shown) { out(ascii(name + ':')); shown = name; }
      out(ascii(line(r)));
    }
    out(tasks.length + ' open, and ' + unverified + ' done, not yet verified, not listed');
    return 0;
  } catch (e) {
    if (isBusy(e)) { err('fleet.db busy'); return 3; }
    if (e.refusal) { err('refused: ' + ascii(e.message)); return 1; }
    err('fleet.db: ' + ascii(String(e.message).replace('open it for writing once', 'run horde db init')));
    return 1;
  } finally {
    if (db) db.close();
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  process.exitCode = main(process.argv.slice(2));
}
