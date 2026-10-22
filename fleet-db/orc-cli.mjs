// The Orc row `horde status set` makes (design: planning/fleet-db-design.md "Orc rows"):
//   node orc-cli.mjs ensure --folder <lane folder> --letter <X> --lane <text> [--thrall]
// Makes sure fleet.db has an orc row for the card just written: an existing row found by folder or letter is kept
// (orc-row.mjs, the importer's own rule), else one is inserted. One short transaction, ASCII output, one line.
// It never makes the database: a missing fleet.db is a refusal here, because `horde db init` and the importer own
// that, and the caller (status set) treats every non-zero exit as "card written, row not made".
// STDOUT: "added" or "kept". EXIT CODES: 0 done, 1 refused or failed (one line, the reason), 2 no home,
//   3 "fleet.db busy" (the lock was not free within HORDE_ORC_BUSY_MS, default 3000), 4 no fleet.db yet.
// THE HOME comes from HORDE_HOME, else the home pointer, as every fleet.db command (store.mjs homeFromEnv).
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dbPathFor, homeFromEnv, inWrite, openStore } from './store.mjs';
import { ensureOrcRow } from './orc-row.mjs';

const BUSY_MS_DEFAULT = 3000;
const VALUE = ['--folder', '--letter', '--lane'];
const BARE = ['--thrall'];

const ascii = (s) => String(s).replace(/[^\x20-\x7E]/g, (c) => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0'));
const isBusy = (e) => /database is locked|database table is locked|SQLITE_BUSY/i.test(String(e && e.message));

export function parseFlags(args) {
  const got = {};
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    const isValue = VALUE.includes(a);
    if (!isValue && !BARE.includes(a)) throw new Error('unknown argument ' + String(a).slice(0, 40));
    if (a in got) throw new Error(a + ' given twice');
    if (isValue) {
      if (i + 1 >= args.length) throw new Error(a + ' needs a value');
      got[a] = args[++i];
    } else got[a] = true;
  }
  // The lane text may be empty (the row is then named for its folder); the folder and letter may not.
  for (const f of ['--folder', '--letter']) if (!(f in got)) throw new Error(f + ' is required');
  if (!(typeof got['--lane'] === 'string')) got['--lane'] = '';
  // The rules of the orc table's own columns, so a refusal says why instead of a constraint error.
  if (!/^[a-z0-9-]{1,64}$/.test(got['--folder'])) throw new Error('the folder name cannot be a lane_dir (1 to 64 of a-z, 0-9, dash)');
  if (!/^[A-Z]$/.test(got['--letter'])) throw new Error('the letter is not one capital letter');
  return got;
}

export function main(argv, env = process.env, out = (s) => process.stdout.write(s + '\n'), err = (s) => process.stderr.write(s + '\n')) {
  if (argv[0] !== 'ensure') {
    err('usage: orc-cli.mjs ensure --folder <name> --letter <X> --lane <text> [--thrall]');
    return 1;
  }
  let flags;
  try {
    flags = parseFlags(argv.slice(1));
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
  const busyMs = /^\d+$/.test(env.HORDE_ORC_BUSY_MS ?? '') ? Number(env.HORDE_ORC_BUSY_MS) : BUSY_MS_DEFAULT;
  let db;
  try {
    db = openStore(file, { busyMs });
    const r = inWrite(db, () => ensureOrcRow(db, {
      folder: flags['--folder'], letter: flags['--letter'], lane: flags['--lane'], isThrall: flags['--thrall'] === true, createdAt: Date.now(),
    }));
    out(r.added ? 'added' : 'kept');
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
