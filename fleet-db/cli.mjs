// Entry point of fleet.db:  node cli.mjs init | status | check | import [sources] [--dry-run]
// Run by `horde db ...` (cli/commands/db.ps1). Exit codes: 0 done, 1 failed or a problem found, 2 no home.
//
//   init    make fleet.db in HORDE_HOME, or bring it to this code's schema; safe to run any number of times
//   status  the file, its schema version and the rows in every table; changes no data and never creates the
//           database (SQLite may still make its -wal and -shm files beside it to read a WAL file)
//   import  read the old files named by --ledger, --pr-cache, --changelog, --cards, --thrall-card,
//           --registry, --decisions and --lots (every path explicit, none defaulted to the real files) into fleet.db, in one
//           transaction; prints one line per table (added / already there) and what could not be linked;
//           --dry-run does everything and rolls it back. fleet.db must exist (run init first)
//   check   SQLite's integrity and foreign-key checks, plus the rules a single row cannot hold by itself
//           (every decisions list has all its lines); each problem is one line, and any problem exits 1
//
// THE HOME IS NEVER DEFAULTED: fleet.db is the fleet's one database, and a copy made in some default folder
// would be a second one that nothing reads (dbPathFor refuses an empty or relative home).
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dbPathFor, homeFromEnv, openStore } from './store.mjs';
import { SCHEMA_VERSION, ENTITY_KINDS } from './schema.mjs';
import { decisionsHash } from './write.mjs';
import { importFleet } from './import.mjs';

export const VERBS = ['init', 'status', 'check', 'import'];

// import's flags, each with the source it names (importFleet's sources).
const SOURCE_FLAGS = { '--ledger': 'ledger', '--pr-cache': 'prCache', '--changelog': 'changelog', '--cards': 'cards', '--thrall-card': 'thrallCard', '--registry': 'registry', '--decisions': 'decisions', '--lots': 'lots' };

// The flags of import; an unknown flag, a flag with no path, or a flag given twice is refused, never ignored.
export function parseImportArgs(args) {
  const sources = {};
  let dryRun = false;
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--dry-run') { dryRun = true; continue; }
    const key = SOURCE_FLAGS[a];
    if (!key) throw new Error('import: unknown argument ' + a);
    if (key in sources) throw new Error('import: ' + a + ' given twice');
    const v = args[i + 1];
    if (v === undefined || v === '' || v.startsWith('--')) throw new Error('import: ' + a + ' needs a path');
    sources[key] = v;
    i++;
  }
  if (Object.keys(sources).length === 0) throw new Error('import needs at least one source: ' + Object.keys(SOURCE_FLAGS).join(', '));
  return { sources, dryRun };
}

function printImport(report, out) {
  out(report.dryRun ? 'import: dry run, nothing was written' : 'import: done');
  for (const [t, c] of Object.entries(report.tables)) out(t + ': ' + c.added + ' added, ' + c.existing + ' already there' + (c.updated === undefined ? '' : ', ' + c.updated + ' moved forward'));
  if (report.unlinked.length === 0) out('unlinked: none');
  for (const u of report.unlinked) out(u.source + ': ' + u.reason + ': ' + u.count + (u.examples.length ? ' (e.g. ' + u.examples.join(', ') + ')' : ''));
}

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
  // A confirm belongs to a snapshot of its own Orc and is never earlier than that snapshot (the triggers
  // hold both; a raw connection with triggers off could break them).
  for (const r of db.prepare(`SELECT c.id FROM decisions_confirm c JOIN decisions_snapshot s ON s.id = c.snapshot_id
    WHERE s.orc_id <> c.orc_id OR c.confirmed_at < s.published_at ORDER BY c.id`).all()) problems.push('decisions confirm ' + r.id + ' is not of its own Orc list or is before it was published');
  // A list's hash is recomputed from the lines it holds, so a line changed or added outside the write
  // module shows (the database cannot compare a hash with its rows).
  const lines = db.prepare('SELECT question_id, text, recommendation, importance, blocks FROM decisions_snapshot_item WHERE snapshot_id = ? ORDER BY position');
  for (const s of db.prepare('SELECT id, sha256 FROM decisions_snapshot ORDER BY id').all()) {
    if (decisionsHash(lines.all(s.id).map((r) => ({ ...r }))) !== s.sha256) problems.push('decisions list ' + s.id + ' does not hash to its sha256');
  }
  // The entity registry must match the tables exactly: an object with no entity row cannot be tagged or
  // linked, and an entity row with no object points at nothing. Table names come from schema.mjs.
  for (const t of ENTITY_KINDS) {
    const missing = db.prepare('SELECT count(*) AS n FROM ' + t + ' x WHERE NOT EXISTS (SELECT 1 FROM entity e WHERE e.id = x.id)').get().n;
    if (missing > 0) problems.push(t + ': ' + missing + ' rows have no entity row');
    const orphans = db.prepare('SELECT count(*) AS n FROM entity e WHERE e.kind = ? AND NOT EXISTS (SELECT 1 FROM ' + t + ' x WHERE x.id = e.id)').get(t).n;
    if (orphans > 0) problems.push('entity: ' + orphans + ' ' + t + ' rows point at nothing');
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
  const verb = argv[0];
  if (!VERBS.includes(verb) || (verb !== 'import' && argv.length !== 1)) {
    err('usage: cli.mjs init | status | check | import [--ledger f] [--pr-cache f] [--changelog f] [--cards dir] [--thrall-card f] [--registry dir] [--decisions dir] [--lots dir] [--dry-run]' + (VERBS.includes(verb) && argv.length > 1 ? ' (nothing may follow init, status or check)' : ''));
    return 1;
  }
  let request;
  if (verb === 'import') {
    try {
      request = parseImportArgs(argv.slice(1));
    } catch (e) {
      err('fleet.db: ' + e.message);
      return 1;
    }
  }
  let file;
  try {
    file = dbPathFor(homeFromEnv(env));
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
    if (verb === 'import') {
      if (!fs.existsSync(file)) throw new Error('fleet.db does not exist yet at ' + file + '; run horde db init');
      // A dry run must not migrate an older file as a side effect: it is refused, not upgraded.
      if (request.dryRun) openForReading(file).close();
      db = openStore(file);
      printImport(importFleet(db, request.sources, { dryRun: request.dryRun }), out);
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
