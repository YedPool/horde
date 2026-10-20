// Entry point of fleet.db:  node cli.mjs init | status | check
// Run by `horde db ...` (cli/commands/db.ps1). Exit codes: 0 done, 1 failed or a problem found, 2 no home.
//
//   init    make fleet.db in HORDE_HOME, or bring it to this code's schema; safe to run any number of times
//   status  the file, its schema version and the rows in every table; changes no data and never creates the
//           database (SQLite may still make its -wal and -shm files beside it to read a WAL file)
//   check   SQLite's integrity and foreign-key checks, plus the rules a single row cannot hold by itself
//           (every decisions list has all its lines); each problem is one line, and any problem exits 1
//
// THE HOME IS NEVER DEFAULTED: fleet.db is the fleet's one database, and a copy made in some default folder
// would be a second one that nothing reads (dbPathFor refuses an empty or relative home).
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dbPathFor, openStore } from './store.mjs';
import { SCHEMA_VERSION } from './schema.mjs';
import { decisionsHash } from './write.mjs';

export const VERBS = ['init', 'status', 'check'];

function tableRows(db) {
  const names = db.prepare("SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name").all().map((r) => r.name);
  // The names come from the database's own catalogue, never from input.
  return names.map((n) => ({ name: n, rows: db.prepare('SELECT count(*) AS n FROM "' + n + '"').get().n }));
}

export function findProblems(db) {
  const problems = [];
  const integrity = db.prepare('PRAGMA integrity_check').all().map((r) => r.integrity_check);
  if (!(integrity.length === 1 && integrity[0] === 'ok')) for (const m of integrity) problems.push('integrity: ' + m);
  for (const r of db.prepare('PRAGMA foreign_key_check').all()) problems.push('foreign key: ' + r.table + ' row ' + r.rowid + ' points at a missing ' + r.parent);
  const short = db.prepare(`SELECT s.id, s.item_count, count(i.position) AS have FROM decisions_snapshot s
    LEFT JOIN decisions_snapshot_item i ON i.snapshot_id = s.id GROUP BY s.id HAVING have <> s.item_count`).all();
  for (const r of short) problems.push('decisions list ' + r.id + ' says ' + r.item_count + ' lines and holds ' + r.have);
  // A list's hash is recomputed from the lines it holds, so a line changed or added outside the write
  // module shows (the database cannot compare a hash with its rows).
  const lines = db.prepare('SELECT question_id, text, recommendation, importance, blocks FROM decisions_snapshot_item WHERE snapshot_id = ? ORDER BY position');
  for (const s of db.prepare('SELECT id, sha256 FROM decisions_snapshot ORDER BY id').all()) {
    if (decisionsHash(lines.all(s.id).map((r) => ({ ...r }))) !== s.sha256) problems.push('decisions list ' + s.id + ' does not hash to its sha256');
  }
  return problems;
}

function openForReading(file) {
  if (!fs.existsSync(file)) throw new Error('fleet.db does not exist yet at ' + file + '; run horde db init');
  try {
    return openStore(file, { readOnly: true });
  } catch (e) {
    throw new Error(e.message.replace('open it for writing once', 'run horde db init'));
  }
}

export function main(argv, env = process.env, out = (s) => process.stdout.write(s + '\n'), err = (s) => process.stderr.write(s + '\n')) {
  if (argv.length !== 1 || !VERBS.includes(argv[0])) {
    err('usage: cli.mjs init | status | check' + (argv.length > 1 ? ' (nothing may follow the verb)' : ''));
    return 1;
  }
  const verb = argv[0];
  let file;
  try {
    file = dbPathFor(env.HORDE_HOME);
  } catch (e) {
    err('fleet.db: ' + e.message);
    return 2;
  }
  let db;
  try {
    if (verb === 'init') {
      const existed = fs.existsSync(file);
      db = openStore(file);
      out('fleet.db: ' + file + ' (schema ' + SCHEMA_VERSION + ', ' + (existed ? 'already there, now current' : 'created') + ')');
      return 0;
    }
    db = openForReading(file);
    if (verb === 'status') {
      out('database: ' + file + ' (schema ' + db.prepare('PRAGMA user_version').get().user_version + ', ' + fs.statSync(file).size + ' bytes)');
      for (const t of tableRows(db)) out(t.name + ': ' + t.rows + ' rows');
      return 0;
    }
    const problems = findProblems(db);
    for (const p of problems) out('problem: ' + p);
    out('check: ' + (problems.length === 0 ? 'ok' : problems.length + ' problem' + (problems.length === 1 ? '' : 's')));
    return problems.length === 0 ? 0 : 1;
  } catch (e) {
    err('fleet.db: ' + e.message);
    return 1;
  } finally {
    if (db) db.close();
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  process.exitCode = main(process.argv.slice(2));
}
