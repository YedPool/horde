// Opening fleet.db: <HORDE_HOME>/fleet.db, the fleet's one source of truth for work data.
//
// WHY THESE PRAGMAS: hooks, the analyst, `horde` verbs and the gh poll all touch the file at once. WAL lets
// readers go on while one writer writes; busy_timeout 5000 makes a second writer wait instead of failing
// (every write here holds the lock for milliseconds). foreign_keys is OFF by default in SQLite and per
// connection, so it is set on every open and checked: a connection without it would write orphan rows.
// recursive_triggers is set for the same reason: without it, INSERT OR REPLACE deletes the conflicting row
// WITHOUT firing its DELETE trigger, so an append-only history row could be silently overwritten (review
// of PR 339, blocker 1). With it on, the _no_delete trigger refuses the REPLACE.
//
// ONE WRITE PATH: other lanes write their tables through this module's functions, never with their own SQL
// connection, so the pragmas, the transaction rule and the hash rule are the same for every writer.
import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { MIGRATIONS, SCHEMA_VERSION } from './schema.mjs';
import { resolveHordeHome } from '../core/home.mjs';

export const DB_FILE = 'fleet.db';

// The Horde home from the environment: HORDE_HOME, else the pointer file (core/home.mjs, the one rule for every
// resolver). Throws with the reason when neither names a usable home; there is no default folder.
export function homeFromEnv(env = process.env) {
  const r = resolveHordeHome(env);
  if (!r.ok) throw new Error(r.message);
  return r.home;
}

// The file for a Horde home. A relative or empty home is refused, never resolved against the current
// folder: the same command run from two folders would write two databases (core/Home.ps1's rule).
export function dbPathFor(home) {
  const h = String(home ?? '').trim();
  if (h === '') throw new Error('HORDE_HOME is not set, so fleet.db has no home');
  // On Windows path.isAbsolute('\\foo') is true, but a path with no drive still depends on the current
  // drive; a home must name its drive or be a UNC path.
  const rooted = process.platform === 'win32' ? /^([A-Za-z]:[\\/]|\\\\[^\\/])/.test(h) : path.isAbsolute(h);
  if (!rooted) throw new Error("HORDE_HOME must be an absolute path, not '" + h + "'");
  return path.join(path.resolve(h), DB_FILE);
}

// Turning a new file to WAL can say "database is locked" at once, with busy_timeout unused, when another process is doing the
// same: measured 2026-11-06 (T-0408), 23 failures in 2108 rounds of six processes opening one new file, all on this pragma. So it
// is retried for as long as the caller would wait for a lock. On a file already in WAL it changes nothing and takes no such lock.
export function enterWal(db, busyMs, { now = Date.now, pause = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms) } = {}) {
  const giveUp = now() + Number(busyMs);
  for (;;) {
    try {
      db.exec('PRAGMA journal_mode = WAL');
      return;
    } catch (e) {
      if (!/database is locked/i.test(String(e && e.message)) || now() >= giveUp) throw e;
      pause(25);
    }
  }
}

export function openStore(file, { readOnly = false, busyMs = 5000 } = {}) {
  if (readOnly && !fs.existsSync(file)) throw new Error('fleet.db does not exist yet at ' + file + '; open it for writing once');
  if (!readOnly) fs.mkdirSync(path.dirname(file), { recursive: true });
  const db = new DatabaseSync(file, { readOnly, enableForeignKeyConstraints: true });
  db.exec('PRAGMA busy_timeout = ' + Number(busyMs));
  if (!readOnly) {
    enterWal(db, busyMs);
    db.exec('PRAGMA synchronous = NORMAL');
  }
  db.exec('PRAGMA foreign_keys = ON');
  db.exec('PRAGMA recursive_triggers = ON');
  const on = (p) => db.prepare('PRAGMA ' + p).get()[p] === 1;
  if (!on('foreign_keys') || !on('recursive_triggers')) {
    db.close();
    throw new Error('fleet.db: foreign keys and recursive triggers could not be turned on');
  }
  const have = db.prepare('PRAGMA user_version').get().user_version;
  if (have > SCHEMA_VERSION) {
    db.close();
    throw new Error('fleet.db is version ' + have + ', newer than this code (' + SCHEMA_VERSION + '): update Horde');
  }
  if (have < SCHEMA_VERSION) {
    if (readOnly) { db.close(); throw new Error('fleet.db is version ' + have + ' and needs migrating; open it for writing once'); }
    migrate(db, have);
  }
  return db;
}

// The version is read again inside the write lock: several hooks open a brand-new file at once, and each
// saw version 0 before taking the lock, so the second would re-run migration 1 (review of PR 339, 2).
export function migrate(db, from) {
  for (let v = from; v < MIGRATIONS.length; v++) {
    db.exec('BEGIN IMMEDIATE');
    try {
      if (db.prepare('PRAGMA user_version').get().user_version > v) { db.exec('COMMIT'); continue; }
      db.exec(MIGRATIONS[v]);
      db.exec('PRAGMA user_version = ' + (v + 1));
      db.exec('COMMIT');
    } catch (e) {
      db.exec('ROLLBACK');
      throw e;
    }
  }
}

// Run fn inside one write transaction. BEGIN IMMEDIATE takes the write lock at the start, so a read made
// inside fn (the next label, the live seat) cannot be changed by another writer before fn's writes land.
// The pragma is checked again on every write: SQLite lets any code holding the handle turn it off, and the
// append-only rule would then fail open (review of PR 339, round 2). A raw connection that never came
// through openStore is outside this guard; the one-write-path rule above is what keeps those out.
export function inWrite(db, fn) {
  if (db.prepare('PRAGMA recursive_triggers').get().recursive_triggers !== 1) throw new Error('fleet.db: recursive triggers are off on this connection; refusing to write');
  db.exec('BEGIN IMMEDIATE');
  try {
    const r = fn();
    db.exec('COMMIT');
    return r;
  } catch (e) {
    if (db.isTransaction) db.exec('ROLLBACK');
    throw e;
  }
}

// The next human label of a kind ('task' -> 'T-0285', 'question' -> 86). Call inside inWrite, in the same
// transaction as the insert that uses it, so a failed insert hands the number back.
export function takeLabel(db, kind) {
  const row = db.prepare('UPDATE label_seq SET next = next + 1 WHERE kind = ? RETURNING next - 1 AS n').get(kind);
  if (!row) throw new Error('takeLabel: unknown kind ' + kind);
  return kind === 'task' ? 'T-' + String(row.n).padStart(4, '0') : row.n;
}
