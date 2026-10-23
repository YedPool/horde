// The Orc row `horde status set` makes (orc-cli.mjs ensure over orc-row.mjs), attacked: the row is made when
// there is none, an existing row is kept by folder or by letter and never doubled, the Thrall matches the live
// Thrall row, a second call adds nothing, a locked database answers "busy" at once instead of hanging, a newer
// schema is refused cleanly, and the importer after an ensure makes no second row. Databases of their own under
// the temp folder; nothing real is read or written.
import './own-profile.mjs';
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { openStore } from '../store.mjs';
import { SCHEMA_VERSION } from '../schema.mjs';
import { ensureOrcRow } from '../orc-row.mjs';
import { main, parseFlags } from '../orc-cli.mjs';
import { importFleet } from '../import.mjs';

const dirs = [];
const handles = [];
after(() => {
  for (const db of handles) {
    try { db.close(); } catch { /* closed by the test */ }
  }
  for (const d of dirs) fs.rmSync(d, { recursive: true, force: true });
});

function tempDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-db-orcrow-'));
  dirs.push(dir); // before anything can throw: a mutant must not leak its folder
  return dir;
}

// A home with a fleet.db that exists (opened once, so migrated), as `horde db init` leaves it.
function home() {
  const dir = tempDir();
  const file = path.join(dir, 'fleet.db');
  openStore(file).close();
  return { dir, file, env: { HORDE_HOME: dir, HORDE_ORC_BUSY_MS: '300' } };
}

// Runs the verb and returns { code, out, err }.
function run(env, args) {
  const out = [];
  const err = [];
  const code = main(args, env, (s) => out.push(s), (s) => err.push(s));
  return { code, out: out.join('\n'), err: err.join('\n') };
}

const ensure = (env, folder, letter, lane, ...more) => run(env, ['ensure', '--folder', folder, '--letter', letter, '--lane', lane, ...more]);

function orcs(file) {
  const db = new DatabaseSync(file, { readOnly: true });
  try {
    return db.prepare('SELECT id, letter, lane_dir, name, rank, created_at FROM orc ORDER BY lane_dir').all().map((r) => ({ ...r }));
  } finally {
    db.close();
  }
}

test('adds a row when the Orc has none: letter, folder, lane text, rank orc', () => {
  const h = home();
  const before = Date.now();
  const r = ensure(h.env, 'form-fill', 'F', 'form fill lane');
  assert.deepEqual([r.code, r.out], [0, 'added']);
  const rows = orcs(h.file);
  assert.equal(rows.length, 1);
  assert.deepEqual([rows[0].letter, rows[0].lane_dir, rows[0].name, rows[0].rank], ['F', 'form-fill', 'form fill lane', 'orc']);
  assert.ok(rows[0].created_at >= before && rows[0].created_at <= Date.now());
});

test('a card with no lane text names the row for its folder; a long one is cut to the column', () => {
  const h = home();
  assert.equal(ensure(h.env, 'sleeper', 'S', '').out, 'added');
  assert.equal(ensure(h.env, 'longlane', 'L', 'x'.repeat(300)).out, 'added');
  const by = Object.fromEntries(orcs(h.file).map((r) => [r.lane_dir, r.name]));
  assert.equal(by.sleeper, 'sleeper');
  assert.equal(by.longlane, 'x'.repeat(120));
});

test('keeps an existing row found by lane folder, even when the card now says another letter', () => {
  const h = home();
  ensure(h.env, 'form-fill', 'F', 'form fill lane');
  const first = orcs(h.file)[0];
  const r = ensure(h.env, 'form-fill', 'G', 'renamed lane');
  assert.deepEqual([r.code, r.out], [0, 'kept']);
  const rows = orcs(h.file);
  assert.equal(rows.length, 1);
  assert.deepEqual(rows[0], first);
});

test('keeps an existing row found by letter, even when the card sits in another folder', () => {
  const h = home();
  ensure(h.env, 'form-fill', 'F', 'form fill lane');
  const r = ensure(h.env, 'moved-lane', 'F', 'form fill lane');
  assert.deepEqual([r.code, r.out], [0, 'kept']);
  const rows = orcs(h.file);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].lane_dir, 'form-fill');
});

test('a Thrall card makes a thrall row, and later matches the live Thrall row whatever its folder and letter', () => {
  const h = home();
  assert.equal(ensure(h.env, 'thrall', 'M', 'the master', '--thrall').out, 'added');
  assert.deepEqual(orcs(h.file).map((r) => [r.letter, r.lane_dir, r.rank]), [['M', 'thrall', 'thrall']]);
  // Another folder and letter, still the Thrall's card: the live thrall row is the match, not a second thrall.
  const r = ensure(h.env, 'thrall-copy', 'T', 'the master', '--thrall');
  assert.deepEqual([r.code, r.out], [0, 'kept']);
  assert.equal(orcs(h.file).length, 1);
  // Without --thrall the same folder is an ordinary Orc card, found by its folder.
  assert.equal(ensure(h.env, 'thrall', 'M', 'the master').out, 'kept');
});

test('a second call adds nothing and changes nothing', () => {
  const h = home();
  assert.equal(ensure(h.env, 'status-lane', 'N', 'status lane').out, 'added');
  const once = orcs(h.file);
  for (let i = 0; i < 3; i++) assert.equal(ensure(h.env, 'status-lane', 'N', 'status lane').out, 'kept');
  assert.deepEqual(orcs(h.file), once);
});

test('a database another writer holds locked answers busy (exit 3) within the wait, never a hang', () => {
  const h = home();
  const holder = new DatabaseSync(h.file);
  handles.push(holder);
  holder.exec('PRAGMA busy_timeout = 0');
  holder.exec('BEGIN IMMEDIATE');
  const t0 = Date.now();
  const r = ensure(h.env, 'busy-lane', 'B', 'busy lane');
  const took = Date.now() - t0;
  assert.deepEqual([r.code, r.err], [3, 'fleet.db busy']);
  assert.ok(took < 3000, 'waited ' + took + ' ms');
  holder.exec('ROLLBACK');
  assert.equal(orcs(h.file).length, 0);
  // CONTROL: once the lock is gone the same call works, so the busy answer was the lock's doing.
  assert.equal(ensure(h.env, 'busy-lane', 'B', 'busy lane').out, 'added');
});

test('a database of a newer schema is refused cleanly (exit 1) and left alone', () => {
  const h = home();
  const raw = new DatabaseSync(h.file);
  raw.exec('PRAGMA user_version = ' + (SCHEMA_VERSION + 1));
  raw.close();
  const r = ensure(h.env, 'new-lane', 'W', 'new lane');
  assert.equal(r.code, 1);
  assert.match(r.err, /newer than this code/);
  const check = new DatabaseSync(h.file, { readOnly: true });
  assert.equal(check.prepare('PRAGMA user_version').get().user_version, SCHEMA_VERSION + 1);
  assert.equal(check.prepare('SELECT count(*) AS n FROM orc').get().n, 0);
  check.close();
});

test('a database of an older schema is refused (exit 1, run horde db init) and never migrated from here', () => {
  const dir = tempDir();
  const file = path.join(dir, 'fleet.db');
  new DatabaseSync(file).close(); // a file at version 0: older than the code
  const r = ensure({ HORDE_HOME: dir, HORDE_ORC_BUSY_MS: '300' }, 'old-lane', 'O', 'old lane');
  assert.equal(r.code, 1);
  assert.match(r.err, /needs migrating; run horde db init/);
  const check = new DatabaseSync(file, { readOnly: true });
  assert.equal(check.prepare('PRAGMA user_version').get().user_version, 0);
  assert.equal(check.prepare("SELECT count(*) AS n FROM sqlite_master WHERE name = 'orc'").get().n, 0);
  check.close();
});

test('no fleet.db yet (exit 4) and no home (exit 2) are refusals; the database is never made here', () => {
  const dir = tempDir();
  const r = ensure({ HORDE_HOME: dir }, 'a-lane', 'A', 'a lane');
  assert.deepEqual([r.code, r.out], [4, '']);
  assert.match(r.err, /does not exist yet/);
  assert.equal(fs.existsSync(path.join(dir, 'fleet.db')), false);
  // An empty environment falls back to the profile pointer; own-profile.mjs made that profile empty and temporary.
  assert.equal(ensure({}, 'a-lane', 'A', 'a lane').code, 2);
  assert.equal(ensure({ HORDE_HOME: 'relative-home' }, 'a-lane', 'A', 'a lane').code, 2);
});

test('arguments the orc table cannot hold are refused in words, before any database is opened', () => {
  const h = home();
  assert.match(ensure(h.env, 'Bad Folder', 'A', 'x').err, /cannot be a lane_dir/);
  assert.match(ensure(h.env, 'ok-folder', 'AB', 'x').err, /one capital letter/);
  assert.match(ensure(h.env, 'ok-folder', 'a', 'x').err, /one capital letter/);
  assert.match(run(h.env, ['ensure', '--letter', 'A']).err, /--folder is required/);
  assert.match(run(h.env, ['ensure', '--folder', 'x', '--letter', 'A', '--bogus']).err, /unknown argument/);
  assert.match(run(h.env, ['ensure', '--folder', 'x', '--folder', 'y', '--letter', 'A']).err, /given twice/);
  assert.match(run(h.env, ['ensure', '--letter', 'A', '--folder']).err, /needs a value/);
  assert.equal(run(h.env, ['frobnicate']).code, 1);
  assert.equal(orcs(h.file).length, 0);
  // The lane text is optional, the folder and letter are not.
  assert.equal(parseFlags(['--folder', 'x', '--letter', 'A'])['--lane'], '');
});

test('a lane text outside ASCII is stored, and the lines printed are ASCII', () => {
  const h = home();
  const r = ensure(h.env, 'umlaut-lane', 'U', 'caf' + String.fromCharCode(233) + ' lane');
  assert.deepEqual([r.code, r.out], [0, 'added']);
  assert.ok(/^[\x20-\x7E]*$/.test(r.out + r.err));
});

function writeCard(cards, folder, letter, lane) {
  fs.mkdirSync(path.join(cards, folder), { recursive: true });
  fs.writeFileSync(path.join(cards, folder, 'status.txt'),
    ['horde-orc-status 1', 'orc: ' + letter, 'lane: ' + lane, 'doing: working on the list', 'finished: the first part', 'blocked: no'].join('\n') + '\n');
}

test('the importer after an ensure makes no second row, and ensure after the importer finds the imported row', () => {
  const h = home();
  ensure(h.env, 'form-fill', 'F', 'form fill lane');
  const cards = path.join(tempDir(), 'orcs');
  writeCard(cards, 'form-fill', 'F', 'form fill lane');
  const db = openStore(h.file);
  handles.push(db);
  assert.deepEqual(importFleet(db, { cards }).tables.orc, { added: 0, existing: 1 });
  assert.equal(orcs(h.file).length, 1);
  // The other order: the importer makes a row for a new card, then ensure finds it.
  writeCard(cards, 'ops', 'O', 'ops lane');
  assert.deepEqual(importFleet(db, { cards }).tables.orc, { added: 1, existing: 1 });
  assert.equal(ensure(h.env, 'ops', 'O', 'ops lane').out, 'kept');
  assert.equal(orcs(h.file).length, 2);
});

test('ensureOrcRow itself: the same call twice is one row, with the id and time the first call made', () => {
  const h = home();
  const db = openStore(h.file);
  handles.push(db);
  const a = ensureOrcRow(db, { folder: 'x-lane', letter: 'X', lane: 'x', createdAt: 1000 });
  const b = ensureOrcRow(db, { folder: 'x-lane', letter: 'X', lane: 'x', createdAt: 2000 });
  assert.deepEqual([a.added, b.added, a.id === b.id], [true, false, true]);
  assert.equal(db.prepare('SELECT created_at FROM orc').get().created_at, 1000);
});
