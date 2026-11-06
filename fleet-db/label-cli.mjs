// The next T-number, for task.py open (T-0299; Orc M's order of 2026-11-06: one allocator):
//   node label-cli.mjs take-task --above <n>
// task.py gave max+1 from its own file while fleet.db saw that file minutes later, so two allocators could give one number
// to two sessions. Now every number comes from label_seq, under the write lock. The counter is raised in the same
// transaction past the highest number anywhere: the task rows here, and --above, the highest in the caller's ledger (the sync
// can be minutes behind that file). A number taken and then not used is a gap, which is harmless; a duplicate is not.
// It never makes the database and never migrates it (opened read-only first, as orc-cli.mjs).
// STDOUT: the number, T-0415. EXIT CODES: 0 done, 1 refused or failed (one line, the reason), 2 no home, 3 "fleet.db busy" (the
// lock was not free within HORDE_LABEL_BUSY_MS, default 3000; the caller decides how long to retry), 4 no fleet.db yet.
// THE HOME comes from HORDE_HOME, else the home pointer, as every fleet.db command (store.mjs homeFromEnv).
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dbPathFor, homeFromEnv, inWrite, openStore, takeLabel } from './store.mjs';

const BUSY_MS_DEFAULT = 3000;
const ascii = (s) => String(s).replace(/[^\x20-\x7E]/g, (c) => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0'));
const isBusy = (e) => /database is locked|database table is locked|SQLITE_BUSY/i.test(String(e && e.message));

// Call inside inWrite. Raises the counter past above and past every task row, never lowers it, then takes one.
export function takeTaskNumber(db, above) {
  const top = db.prepare('SELECT coalesce(max(CAST(substr(key, 3) AS INTEGER)), 0) AS n FROM task').get().n;
  db.prepare("UPDATE label_seq SET next = max(next, ?) WHERE kind = 'task'").run(Math.max(top, above) + 1);
  return takeLabel(db, 'task');
}

export function main(argv, env = process.env, out = (s) => process.stdout.write(s + '\n'), err = (s) => process.stderr.write(s + '\n')) {
  if (argv.length !== 3 || argv[0] !== 'take-task' || argv[1] !== '--above') {
    err('usage: label-cli.mjs take-task --above <highest number in the ledger, 0 if none>');
    return 1;
  }
  if (!/^\d{1,9}$/.test(argv[2])) { err('refused: --above is a whole number, 0 or more'); return 1; }
  let file;
  try {
    file = dbPathFor(homeFromEnv(env));
  } catch (e) {
    err('fleet.db: ' + ascii(e.message));
    return 2;
  }
  if (!fs.existsSync(file)) { err('fleet.db does not exist yet (run horde db init)'); return 4; }
  const busyMs = /^\d+$/.test(env.HORDE_LABEL_BUSY_MS ?? '') ? Number(env.HORDE_LABEL_BUSY_MS) : BUSY_MS_DEFAULT;
  let db;
  try {
    try {
      openStore(file, { readOnly: true, busyMs }).close();
    } catch (e) {
      if (isBusy(e)) throw e;
      err('fleet.db: ' + ascii(String(e.message).replace('open it for writing once', 'run horde db init')));
      return 1;
    }
    db = openStore(file, { busyMs });
    out(inWrite(db, () => takeTaskNumber(db, Number(argv[2]))));
    return 0;
  } catch (e) {
    if (isBusy(e)) { err('fleet.db busy'); return 3; }
    err('fleet.db: ' + ascii(e.message));
    return 1;
  } finally {
    if (db) db.close();
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  process.exitCode = main(process.argv.slice(2));
}
