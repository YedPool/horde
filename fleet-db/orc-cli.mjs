// The Orc row `horde status set` makes (design: planning/fleet-db-design.md "Orc rows"):
//   node orc-cli.mjs ensure --folder <lane folder> --letter <X> --lane <text> [--thrall] [--card <absolute path of status.txt>]
// Makes sure fleet.db has an orc row for the card just written: an existing row found by folder or letter is kept
// (orc-row.mjs, the importer's own rule), else one is inserted. One short transaction, ASCII output, one line.
// It never makes the database: a missing fleet.db is a refusal here, because `horde db init` and the importer own
// that, and the caller (status set) treats every non-zero exit as "card written, row not made".
// --card (T-0389): the card just written. After the orc row, in the SAME transaction, the card's orc_status row is
// appended with backfill 0 and `at` = the card's mtime, by the importer's own reader and rule (import.mjs
// readStatusCard / statusRowFor), so the live row and the sync's backfill row for the same card are one status. A
// card whose doing or blocked the table would refuse (empty or over 120, over 200) gets no status row, the reason is
// said, and the orc row is still made. An Orc that already has a status row at the card's time keeps it.
// STDOUT: "added" or "kept"; with --card, "<orc>; status row added", "<orc>; status row kept" or
//   "<orc>; no status row: <reason>". EXIT CODES: 0 done, 1 refused or failed (one line, the reason), 2 no home,
//   3 "fleet.db busy" (the lock was not free within HORDE_ORC_BUSY_MS, default 3000), 4 no fleet.db yet.
// THE HOME comes from HORDE_HOME, else the home pointer, as every fleet.db command (store.mjs homeFromEnv).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { dbPathFor, homeFromEnv, inWrite, openStore } from './store.mjs';
import { ensureOrcRow } from './orc-row.mjs';
import { readStatusCard, statusRowFor } from './import.mjs';
import { appendHistory } from './write.mjs';

const BUSY_MS_DEFAULT = 3000;
const VALUE = ['--folder', '--letter', '--lane', '--card'];
const BARE = ['--thrall'];

// A drive or UNC path on Windows (a path with no drive depends on the current drive), else any absolute path.
const isRooted = (p) => (process.platform === 'win32' ? /^([A-Za-z]:[\\/]|\\\\[^\\/])/.test(p) : path.isAbsolute(p));
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
  // An absolute path with a drive (or UNC), as dbPathFor holds a home: node starts in PowerShell's process folder.
  if ('--card' in got && !isRooted(got['--card'])) throw new Error('--card must be an absolute path');
  return got;
}

export function main(argv, env = process.env, out = (s) => process.stdout.write(s + '\n'), err = (s) => process.stderr.write(s + '\n')) {
  if (argv[0] !== 'ensure') {
    err('usage: orc-cli.mjs ensure --folder <name> --letter <X> --lane <text> [--thrall] [--card <status.txt>]');
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
    // Opened read-only first, which refuses a fleet.db older or newer than this code: a migration is never run from
    // inside a status set (its 3 s lock wait and its caller's 20 s net are not for that); `horde db init` owns it.
    try {
      openStore(file, { readOnly: true, busyMs }).close();
    } catch (e) {
      if (isBusy(e)) throw e;
      err('fleet.db: ' + ascii(String(e.message).replace('open it for writing once', 'run horde db init')));
      return 1;
    }
    db = openStore(file, { busyMs });
    // The card is read before the transaction opens (no file read under the write lock); a card that cannot be read
    // costs its status row only, never the orc row, which is what status set is waiting for.
    let cardRead = null;
    if ('--card' in flags) {
      try { cardRead = readStatusCard(flags['--card'], flags['--folder'], flags['--thrall'] === true); } catch (e) { cardRead = { error: 'the card could not be read: ' + e.message }; }
    }
    let status = null;
    const r = inWrite(db, () => {
      const orc = ensureOrcRow(db, {
        folder: flags['--folder'], letter: flags['--letter'], lane: flags['--lane'], isThrall: flags['--thrall'] === true, createdAt: Date.now(),
      });
      if (cardRead === null) return orc;
      // The reader's refusal is worded for the importer, where a bad card also costs the orc row; here the orc row is
      // made regardless, so that clause is dropped rather than told to the person.
      const s = cardRead.error ? { skip: cardRead.error.replace(/, no Orc row made|\s*\(no Orc row made\)/g, '') } : statusRowFor(cardRead.card);
      if (s.skip) { status = 'no status row: ' + s.skip; return orc; }
      // The same check as the importer's stepStatus (its comment says why): a row at this time is the card's already.
      if (db.prepare('SELECT 1 FROM orc_status WHERE orc_id = ? AND at = ? LIMIT 1').get(orc.id, s.row.at)) { status = 'status row kept'; return orc; }
      const put = appendHistory(db, 'orc_status', { orc_id: orc.id, at: s.row.at, doing: s.row.doing, blocked: s.row.blocked, backfill: 0 });
      status = put.inserted ? 'status row added' : 'status row kept';
      return orc;
    });
    out((r.added ? 'added' : 'kept') + (status === null ? '' : '; ' + ascii(status)));
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
