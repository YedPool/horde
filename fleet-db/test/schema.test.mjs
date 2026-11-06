// fleet.db's rules, each attacked: every test writes the row the rule exists to stop and requires the
// database to refuse it, and writes the row the rule must still allow. A database of their own under the
// temp folder; nothing real is read or written.
import './own-profile.mjs';
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { spawn } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { openStore, dbPathFor, inWrite, takeLabel, migrate } from '../store.mjs';
import { SCHEMA_VERSION } from '../schema.mjs';
import { ulid, canonical, sha256 } from '../ids.mjs';

const T0 = Date.UTC(2026, 9, 19, 12, 0, 0);
let seq = 0;
const id = () => ulid(T0 + seq++);
const uuid = (n) => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');

const opened = [];
after(() => {
  for (const { db } of opened) {
    try { db.close(); } catch { /* closed by the test */ }
  }
  for (const dir of new Set(opened.map((o) => o.dir))) fs.rmSync(dir, { recursive: true, force: true });
});

function fresh() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-db-'));
  const entry = { db: { close() {} }, dir };
  opened.push(entry); // before openStore: a store that throws (a mutant) must not leak its folder
  entry.db = openStore(path.join(dir, 'fleet.db'));
  return { db: entry.db, file: path.join(dir, 'fleet.db') };
}

// A small world: one PC, the Thrall, Orc F, one task, one question on that task.
function world() {
  const { db, file } = fresh();
  const w = { db, file, node: id(), node2: id(), m: id(), f: id(), task: id(), q: id() };
  db.prepare('INSERT INTO node (id, name, is_authority, created_at) VALUES (?, ?, 1, ?)').run(w.node, 'pc-1', T0);
  db.prepare('INSERT INTO node (id, name, is_authority, created_at) VALUES (?, ?, 0, ?)').run(w.node2, 'pc-2', T0);
  const orc = db.prepare('INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES (?, ?, ?, ?, ?, ?)');
  orc.run(w.m, 'M', 'thrall', 'Thrall', 'thrall', T0);
  orc.run(w.f, 'F', 'decisions-page', 'Decisions page', 'orc', T0);
  db.prepare("INSERT INTO task (id, key, title, source, created_at) VALUES (?, 'T-0001', 'a task', 'founder', ?)").run(w.task, T0);
  db.prepare("INSERT INTO question (id, number, task_id, kind, title, asked_at) VALUES (?, 1, ?, 'yes-no', 'ok?', ?)").run(w.q, w.task, T0);
  return w;
}

function seat(db, sid, orcId, nodeId, rank = 'orc') {
  db.prepare('INSERT INTO session (id, node_id, orc_id, rank, first_seen, last_seen) VALUES (?, ?, ?, ?, ?, ?)')
    .run(sid, nodeId, orcId, rank, T0, T0);
}

function event(db, row) {
  const r = { id: id(), at: T0 + seq++, backfill: 0, ...row };
  r.sha256 = sha256({ ...r, id: undefined });
  const cols = Object.keys(r);
  db.prepare('INSERT INTO task_event (' + cols.join(', ') + ') VALUES (' + cols.map(() => '?').join(', ') + ')')
    .run(...cols.map((c) => r[c]));
  return r;
}

const refuses = (fn, re) => assert.throws(fn, re);

// --- opening -----------------------------------------------------------------------------------------

test('a new file walks to the current schema version', () => {
  const { db } = fresh();
  assert.equal(db.prepare('PRAGMA user_version').get().user_version, SCHEMA_VERSION);
});

test('foreign keys are on for every connection', () => {
  const { db } = fresh();
  assert.equal(db.prepare('PRAGMA foreign_keys').get().foreign_keys, 1);
});

test('the file is in WAL mode', () => {
  const { db } = fresh();
  assert.equal(db.prepare('PRAGMA journal_mode').get().journal_mode, 'wal');
});

test('a database from a newer Horde is refused', () => {
  const { db, file } = fresh();
  db.exec('PRAGMA user_version = ' + (SCHEMA_VERSION + 1));
  db.close();
  refuses(() => openStore(file), /newer than this code/);
});

test('opening twice does not migrate twice', () => {
  const { db, file } = fresh();
  db.close();
  const again = openStore(file);
  opened.push({ db: again, dir: path.dirname(file) });
  assert.equal(again.prepare("SELECT count(*) AS n FROM label_seq").get().n, 2);
});

test('an empty or relative HORDE_HOME is refused', () => {
  refuses(() => dbPathFor(''), /not set/);
  refuses(() => dbPathFor('relative\\home'), /absolute/);
  assert.equal(path.basename(dbPathFor(os.tmpdir())), 'fleet.db');
});

// --- ids and hashes ----------------------------------------------------------------------------------

test('a ulid is 26 Crockford characters and sorts by time', () => {
  const a = ulid(T0, Buffer.alloc(10, 255));
  const b = ulid(T0 + 1, Buffer.alloc(10, 0));
  assert.match(a, /^[0-7][0-9A-HJKMNP-TV-Z]{25}$/);
  assert.ok(a < b);
});

test('a ulid with the same time and randomness is the same', () => {
  assert.equal(ulid(T0, Buffer.alloc(10, 7)), ulid(T0, Buffer.alloc(10, 7)));
});

test('canonical text does not depend on key order', () => {
  assert.equal(canonical({ b: 1, a: [true, null] }), canonical({ a: [true, null], b: 1 }));
  assert.equal(canonical({ b: 1, a: 2 }), '{"a":2,"b":1}');
});

test('canonical text is ASCII', () => {
  assert.equal(canonical('caf\u00e9 \u2014'), '"caf\\u00e9 \\u2014"');
});

test('canonical text refuses a float', () => {
  refuses(() => canonical({ x: 1.5 }), /safe integers/);
});

test('a row id that is not a ulid is refused', () => {
  const { db } = fresh();
  refuses(() => db.prepare("INSERT INTO node (id, name, created_at) VALUES ('not-a-ulid-at-all-xxxxxxxx', 'x', 1)").run(), /CHECK/);
  refuses(() => db.prepare("INSERT INTO node (id, name, created_at) VALUES (?, 'x', 1)").run(id().toLowerCase()), /CHECK/);
});

test('a session id must be a lower-case uuid', () => {
  const w = world();
  refuses(() => seat(w.db, uuid(1).toUpperCase().replace('0000-4000', 'AAAA-4000'), w.f, w.node), /CHECK/);
  refuses(() => seat(w.db, 'F', w.f, w.node), /CHECK/);
});

// --- one Orc, one live seat --------------------------------------------------------------------------

test('a second live seat for one Orc on one PC is refused', () => {
  const w = world();
  seat(w.db, uuid(1), w.f, w.node);
  refuses(() => seat(w.db, uuid(2), w.f, w.node), /UNIQUE/);
});

test('retiring the old seat and binding the new one in one write leaves one seat', () => {
  const w = world();
  seat(w.db, uuid(1), w.f, w.node);
  inWrite(w.db, () => {
    w.db.prepare("UPDATE session SET retired_at = ?, retired_reason = 'resumed' WHERE id = ?").run(T0 + 5, uuid(1));
    seat(w.db, uuid(2), w.f, w.node);
    w.db.prepare('UPDATE session SET resumed_from_id = ? WHERE id = ?').run(uuid(1), uuid(2));
  });
  const seats = w.db.prepare("SELECT session_id FROM orc_seat WHERE letter = 'F'").all();
  assert.deepEqual(seats.map((s) => s.session_id), [uuid(2)]);
});

test('a failed bind rolls back the retirement too', () => {
  const w = world();
  seat(w.db, uuid(1), w.f, w.node);
  refuses(() => inWrite(w.db, () => {
    w.db.prepare('UPDATE session SET retired_at = ? WHERE id = ?').run(T0 + 5, uuid(1));
    seat(w.db, 'broken', w.f, w.node);
  }), /CHECK/);
  assert.equal(w.db.prepare('SELECT retired_at FROM session WHERE id = ?').get(uuid(1)).retired_at, null);
});

test('one Thrall may hold a seat on each PC', () => {
  const w = world();
  seat(w.db, uuid(1), w.m, w.node, 'thrall');
  seat(w.db, uuid(2), w.m, w.node2, 'thrall');
  assert.equal(w.db.prepare("SELECT count(*) AS n FROM orc_seat WHERE letter = 'M'").get().n, 2);
});

test('an Orc may run any number of live Wargs', () => {
  const w = world();
  seat(w.db, uuid(1), w.f, w.node, 'warg');
  seat(w.db, uuid(2), w.f, w.node, 'warg');
  assert.equal(w.db.prepare("SELECT count(*) AS n FROM session WHERE rank = 'warg'").get().n, 2);
});

test('an orc-rank session must name its Orc', () => {
  const w = world();
  refuses(() => seat(w.db, uuid(1), null, w.node), /CHECK/);
});

test('a second authority PC is refused', () => {
  const w = world();
  refuses(() => w.db.prepare('UPDATE node SET is_authority = 1 WHERE id = ?').run(w.node2), /UNIQUE/);
});

test('two Orcs cannot share a letter', () => {
  const w = world();
  refuses(() => w.db.prepare("INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES (?, 'F', 'other', 'x', 'orc', 1)").run(id()), /UNIQUE/);
});

// --- required links ----------------------------------------------------------------------------------

test('waiting on the founder without its question is refused', () => {
  const w = world();
  refuses(() => event(w.db, { task_id: w.task, kind: 'waiting', on_kind: 'founder' }), /CHECK/);
  event(w.db, { task_id: w.task, kind: 'waiting', on_kind: 'founder', question_id: w.q });
});

test('an imported waiting-on-founder line without a question is kept as backfill', () => {
  const w = world();
  event(w.db, { task_id: w.task, kind: 'waiting', on_kind: 'founder', backfill: 1 });
});

test('waiting with no on-kind is refused', () => {
  const w = world();
  refuses(() => event(w.db, { task_id: w.task, kind: 'waiting' }), /CHECK/);
});

test('an on-kind on a non-waiting event is refused', () => {
  const w = world();
  refuses(() => event(w.db, { task_id: w.task, kind: 'progress', on_kind: 'founder', question_id: w.q }), /CHECK/);
});

test('opening a task without an owner or priority is refused', () => {
  const w = world();
  refuses(() => event(w.db, { task_id: w.task, kind: 'opened', prio: 1 }), /CHECK/);
  refuses(() => event(w.db, { task_id: w.task, kind: 'opened', to_orc_id: w.f }), /CHECK/);
});

test('a hand-over must name who takes it', () => {
  const w = world();
  refuses(() => event(w.db, { task_id: w.task, kind: 'handed' }), /CHECK/);
});

test('a question without its task is refused', () => {
  const w = world();
  refuses(() => w.db.prepare("INSERT INTO question (id, number, kind, title, asked_at) VALUES (?, 2, 'x', 'y', 1)").run(id()), /CHECK/);
  w.db.prepare("INSERT INTO question (id, number, kind, title, asked_at, backfill) VALUES (?, 2, 'x', 'y', 1, 1)").run(id());
});

test('a changelog entry names a task or says it is fleet-wide', () => {
  const w = world();
  const ins = (task, fleetWide) => w.db.prepare(
    "INSERT INTO changelog_entry (id, at, kind, orc_id, task_id, fleet_wide, title, text, sha256) VALUES (?, 1, 'note', ?, ?, ?, 't', 'x', ?)")
    .run(id(), w.f, task, fleetWide, sha256({ n: seq++ }));
  refuses(() => ins(null, 0), /CHECK/);
  ins(null, 1);
  ins(w.task, 0);
});

test('a row pointing at a task that does not exist is refused', () => {
  const w = world();
  refuses(() => event(w.db, { task_id: id(), kind: 'progress' }), /FOREIGN KEY/);
});

test('a merged PR without its merge time is refused', () => {
  const w = world();
  refuses(() => w.db.prepare("INSERT INTO pr (id, repo, number, state, checked_at) VALUES (?, 'YedPool/horde', 1, 'merged', 1)").run(id()), /CHECK/);
  refuses(() => w.db.prepare("INSERT INTO pr (id, repo, number, state, merged_at, checked_at) VALUES (?, 'YedPool/horde', 1, 'open', 5, 1)").run(id()), /CHECK/);
});

test('one PR number in one repo is one row', () => {
  const w = world();
  const ins = () => w.db.prepare("INSERT INTO pr (id, repo, number, state, checked_at) VALUES (?, 'YedPool/horde', 7, 'open', 1)").run(id());
  ins();
  refuses(ins, /UNIQUE/);
});

test('a woken wake member may keep its old session id', () => {
  const w = world();
  seat(w.db, uuid(1), w.f, w.node);
  const lot = id(), wk = id();
  w.db.prepare("INSERT INTO parking_lot (id, created_at, reason) VALUES (?, 1, 'night')").run(lot);
  w.db.prepare("INSERT INTO parking_lot_member (lot_id, session_id, orc_id, state) VALUES (?, ?, ?, 'parked')").run(lot, uuid(1), w.f);
  w.db.prepare('INSERT INTO wake (id, lot_id, requested_at) VALUES (?, ?, 2)').run(wk, lot);
  w.db.prepare("INSERT INTO wake_member (wake_id, session_id, outcome) VALUES (?, ?, 'woken')").run(wk, uuid(1));
  refuses(() => w.db.prepare("INSERT INTO wake_member (wake_id, session_id, outcome) VALUES (?, ?, 'snoozed')").run(id(), uuid(1)), /CHECK|FOREIGN/);
});

test('two open panes with one number on one mux are refused', () => {
  const w = world();
  const ins = (at) => w.db.prepare("INSERT INTO pane (id, node_id, mux_instance, pane_no, opened_at) VALUES (?, ?, 'gui-1', 35, ?)").run(id(), w.node, at);
  ins(1);
  refuses(() => ins(2), /UNIQUE/);
});

// --- history is append-only and de-duplicated --------------------------------------------------------

test('a task event cannot be changed', () => {
  const w = world();
  const e = event(w.db, { task_id: w.task, kind: 'progress', proof: 'x' });
  refuses(() => w.db.prepare("UPDATE task_event SET proof = 'y' WHERE id = ?").run(e.id), /append-only/);
});

test('a task event cannot be deleted', () => {
  const w = world();
  const e = event(w.db, { task_id: w.task, kind: 'progress' });
  refuses(() => w.db.prepare('DELETE FROM task_event WHERE id = ?').run(e.id), /append-only/);
});

test('the same content written twice is refused by its hash', () => {
  const w = world();
  const e = event(w.db, { task_id: w.task, kind: 'progress', proof: 'same' });
  refuses(() => w.db.prepare("INSERT INTO task_event (id, task_id, at, kind, sha256) VALUES (?, ?, 1, 'progress', ?)").run(id(), w.task, e.sha256), /UNIQUE/);
});

test('every history table refuses updates and deletes', () => {
  const { db } = fresh();
  const names = db.prepare("SELECT name FROM sqlite_master WHERE type = 'trigger'").all().map((r) => r.name).sort();
  for (const t of ['answer', 'answer_route', 'answer_route_taken', 'changelog_entry', 'deploy', 'question_event', 'task_event']) {
    assert.ok(names.includes(t + '_no_update') && names.includes(t + '_no_delete'), t);
  }
});

// --- labels ------------------------------------------------------------------------------------------

test('task labels are handed out in order with four digits', () => {
  const { db } = fresh();
  assert.equal(inWrite(db, () => takeLabel(db, 'task')), 'T-0001');
  assert.equal(inWrite(db, () => takeLabel(db, 'task')), 'T-0002');
  assert.equal(inWrite(db, () => takeLabel(db, 'question')), 1);
});

test('a label taken by a failed write is handed back', () => {
  const { db } = fresh();
  refuses(() => inWrite(db, () => { takeLabel(db, 'task'); throw new Error('insert failed'); }), /insert failed/);
  assert.equal(inWrite(db, () => takeLabel(db, 'task')), 'T-0001');
});

test('a second connection waits for the label lock instead of taking the same number', () => {
  const { db, file } = fresh();
  const other = new DatabaseSync(file);
  opened.push({ db: other, dir: path.dirname(file) });
  other.exec('PRAGMA busy_timeout = 0');
  db.exec('BEGIN IMMEDIATE');
  takeLabel(db, 'task');
  refuses(() => other.exec('BEGIN IMMEDIATE'), /locked|busy/i);
  db.exec('COMMIT');
  other.exec('BEGIN IMMEDIATE');
  assert.equal(takeLabel(other, 'task'), 'T-0002');
  other.exec('COMMIT');
});

test('an unknown label kind is refused', () => {
  const { db } = fresh();
  refuses(() => takeLabel(db, 'pr'), /unknown kind/);
});

// --- derived views -----------------------------------------------------------------------------------

test('task_now derives state, priority and owner from events', () => {
  const w = world();
  event(w.db, { task_id: w.task, kind: 'opened', prio: 2, to_orc_id: w.f });
  event(w.db, { task_id: w.task, kind: 'started' });
  event(w.db, { task_id: w.task, kind: 'progress' });
  event(w.db, { task_id: w.task, kind: 'priority', prio: 1 });
  event(w.db, { task_id: w.task, kind: 'handed', to_orc_id: w.m });
  const t = w.db.prepare('SELECT state, prio, owner_orc_id FROM task_now WHERE id = ?').get(w.task);
  assert.deepEqual({ ...t }, { state: 'opened', prio: 1, owner_orc_id: w.m }, 'just handed: the new owner has not begun, as task.py says');
});

test('task_now breaks a same-millisecond tie by row id', () => {
  const w = world();
  const at = T0 + 1000;
  event(w.db, { id: ulid(at, Buffer.alloc(10, 1)), at, task_id: w.task, kind: 'started' });
  event(w.db, { id: ulid(at, Buffer.alloc(10, 2)), at, task_id: w.task, kind: 'done' });
  assert.equal(w.db.prepare('SELECT state FROM task_now WHERE id = ?').get(w.task).state, 'done');
});

test('question_now reads a reopened question as open', () => {
  const w = world();
  const ev = (kind, at) => w.db.prepare('INSERT INTO question_event (id, question_id, at, kind, sha256) VALUES (?, ?, ?, ?, ?)')
    .run(id(), w.q, at, kind, sha256({ kind, at }));
  assert.equal(w.db.prepare('SELECT state FROM question_now').get().state, 'open');
  ev('closed', 1);
  assert.equal(w.db.prepare('SELECT state FROM question_now').get().state, 'closed');
  ev('reopened', 2);
  assert.equal(w.db.prepare('SELECT state FROM question_now').get().state, 'open');
});

test('a retired Orc has no seat', () => {
  const w = world();
  seat(w.db, uuid(1), w.f, w.node);
  w.db.prepare("UPDATE orc SET retired_at = 1, retired_reason = 'hand' WHERE id = ?").run(w.f);
  assert.equal(w.db.prepare("SELECT count(*) AS n FROM orc_seat WHERE letter = 'F'").get().n, 0);
});

// --- review of PR 339: holes found and closed --------------------------------------------------------

test('INSERT OR REPLACE on a history row is refused, not a silent overwrite', () => {
  const w = world();
  const e = event(w.db, { task_id: w.task, kind: 'progress', proof: 'kept' });
  refuses(() => w.db.prepare("INSERT OR REPLACE INTO task_event (id, task_id, at, kind, proof, sha256) VALUES (?, ?, 1, 'progress', 'gone', ?)")
    .run(id(), w.task, e.sha256), /append-only/);
  refuses(() => w.db.prepare("REPLACE INTO task_event (id, task_id, at, kind, proof, sha256) VALUES (?, ?, 1, 'progress', 'gone', ?)")
    .run(e.id, w.task, sha256({ other: 1 })), /append-only/);
  assert.equal(w.db.prepare('SELECT proof FROM task_event WHERE id = ?').get(e.id).proof, 'kept');
});

test('an upsert on a history row is refused', () => {
  const w = world();
  const e = event(w.db, { task_id: w.task, kind: 'progress', proof: 'kept' });
  refuses(() => w.db.prepare("INSERT INTO task_event (id, task_id, at, kind, sha256) VALUES (?, ?, 1, 'progress', ?) ON CONFLICT (sha256) DO UPDATE SET proof = 'gone'")
    .run(id(), w.task, e.sha256), /append-only/);
});

test('the same content written twice with INSERT OR IGNORE is a no-op', () => {
  const w = world();
  const e = event(w.db, { task_id: w.task, kind: 'progress', proof: 'once' });
  const r = w.db.prepare("INSERT OR IGNORE INTO task_event (id, task_id, at, kind, proof, sha256) VALUES (?, ?, ?, 'progress', 'once', ?)")
    .run(id(), w.task, e.at, e.sha256);
  assert.equal(r.changes, 0);
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM task_event').get().n, 1);
});

test('recursive triggers are on for every connection', () => {
  const { db } = fresh();
  assert.equal(db.prepare('PRAGMA recursive_triggers').get().recursive_triggers, 1);
});

test('six processes opening a new file at once all succeed and migrate it once', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-db-'));
  opened.push({ db: { close() {} }, dir });
  const file = path.join(dir, 'fleet.db');
  const store = pathToFileURL(path.join(import.meta.dirname, '..', 'store.mjs')).href;
  const code = 'import { openStore } from ' + JSON.stringify(store) + '; openStore(' + JSON.stringify(file) + ').close();';
  const one = () => new Promise((resolve) => {
    const p = spawn(process.execPath, ['--input-type=module', '-e', code], { stdio: ['ignore', 'ignore', 'pipe'] });
    let err = '';
    p.stderr.on('data', (d) => { err += d; });
    p.on('close', (c) => resolve({ c, err }));
  });
  const results = await Promise.all([1, 2, 3, 4, 5, 6].map(one));
  for (const r of results) assert.equal(r.c, 0, r.err.split('\n').find((l) => /Error/.test(l)) ?? r.err);
  const db = openStore(file);
  opened.push({ db, dir });
  assert.equal(db.prepare('PRAGMA user_version').get().user_version, SCHEMA_VERSION);
});

test('a session id with dashes in the wrong places is refused', () => {
  const w = world();
  refuses(() => seat(w.db, '--------------------------------0000', w.f, w.node), /CHECK/);
  refuses(() => seat(w.db, '000000000-000-4000-8000-000000000001', w.f, w.node), /CHECK/);
});

test('a home with no drive is refused on Windows', { skip: process.platform !== 'win32' }, () => {
  const bs = String.fromCharCode(92);
  refuses(() => dbPathFor(bs + 'horde'), /absolute/);
  assert.equal(path.basename(dbPathFor(bs + bs + 'server' + bs + 'share' + bs + 'horde')), 'fleet.db');
});

test('opening a missing file read-only says it does not exist', () => {
  refuses(() => openStore(path.join(os.tmpdir(), 'fleet-db-missing-' + process.pid, 'fleet.db'), { readOnly: true }), /does not exist yet/);
});

test('canonical text encodes a sparse array hole as null', () => {
  const sparse = [1];
  sparse[2] = 2;
  assert.equal(canonical(sparse), '[1,null,2]');
});

test('canonical text refuses an object that is not plain', () => {
  refuses(() => canonical({ d: new Date(0) }), /plain objects/);
  assert.equal(canonical(Object.assign(Object.create(null), { a: 1 })), '{"a":1}');
});

test('a second Thrall row is refused', () => {
  const w = world();
  refuses(() => w.db.prepare("INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES (?, 'T', 'thrall-2', 'x', 'thrall', 1)").run(id()), /UNIQUE/);
});

test('a session pid needs its process start time', () => {
  const w = world();
  refuses(() => w.db.prepare('INSERT INTO session (id, node_id, orc_id, rank, pid, first_seen, last_seen) VALUES (?, ?, ?, ?, 4242, 1, 1)')
    .run(uuid(9), w.node, w.f, 'warg'), /CHECK/);
});

test('a route is taken once, and the taken row cannot change', () => {
  const w = world();
  const a = id(), r = id();
  w.db.prepare("INSERT INTO answer (id, question_id, at, speaker, text, sha256) VALUES (?, ?, 5, 'founder', 'yes', ?)").run(a, w.q, sha256({ a }));
  w.db.prepare("INSERT INTO answer_route (id, answer_id, at, seat, resolved, sha256) VALUES (?, ?, 6, 'none', 0, ?)").run(r, a, sha256({ r }));
  w.db.prepare('INSERT INTO answer_route_taken (route_id, at) VALUES (?, 7)').run(r);
  refuses(() => w.db.prepare('INSERT INTO answer_route_taken (route_id, at) VALUES (?, 8)').run(r), /UNIQUE|PRIMARY/);
  refuses(() => w.db.prepare('UPDATE answer_route_taken SET at = 9 WHERE route_id = ?').run(r), /append-only/);
});

test('answer_now: an answer to a closed question does not authorize', () => {
  const w = world();
  w.db.prepare("INSERT INTO question_event (id, question_id, at, kind, sha256) VALUES (?, ?, 10, 'closed', ?)").run(id(), w.q, sha256({ c: 1 }));
  const before = id(), afterClose = id();
  w.db.prepare("INSERT INTO answer (id, question_id, at, speaker, text, sha256) VALUES (?, ?, 9, 'founder', 'yes', ?)").run(before, w.q, sha256({ before }));
  w.db.prepare("INSERT INTO answer (id, question_id, at, speaker, text, sha256) VALUES (?, ?, 10, 'founder', 'no', ?)").run(afterClose, w.q, sha256({ afterClose }));
  const get = (x) => ({ ...w.db.prepare('SELECT open_at_arrival, authorizes FROM answer_now WHERE id = ?').get(x) });
  assert.deepEqual(get(before), { open_at_arrival: 1, authorizes: 1 });
  assert.deepEqual(get(afterClose), { open_at_arrival: 0, authorizes: 0 });
});

test('answer_now: chat words never authorize a passkey question; a signed answer does', () => {
  const w = world();
  w.db.prepare('UPDATE question SET needs_passkey = 1 WHERE id = ?').run(w.q);
  const chat = id(), signed = id();
  w.db.prepare("INSERT INTO answer (id, question_id, at, speaker, text, sha256) VALUES (?, ?, 5, 'founder', 'yes', ?)").run(chat, w.q, sha256({ chat }));
  w.db.prepare("INSERT INTO answer (id, question_id, at, speaker, text, signed_by, sha256) VALUES (?, ?, 6, 'founder', 'yes', 'cred-1', ?)").run(signed, w.q, sha256({ signed }));
  const auth = (x) => w.db.prepare('SELECT authorizes FROM answer_now WHERE id = ?').get(x).authorizes;
  assert.equal(auth(chat), 0);
  assert.equal(auth(signed), 1);
});

test('a parts answer names one capital letter', () => {
  const w = world();
  refuses(() => w.db.prepare("INSERT INTO answer (id, question_id, at, speaker, text, part, sha256) VALUES (?, ?, 5, 'founder', 'x', 'ab', ?)").run(id(), w.q, sha256({ p: 1 })), /CHECK/);
});

test('a migration seen as due before the lock but applied by another writer is skipped', () => {
  const { db } = fresh();
  migrate(db, 0);
  assert.equal(db.prepare('PRAGMA user_version').get().user_version, SCHEMA_VERSION);
});

// --- review of PR 339, round 2 -----------------------------------------------------------------------

test('a new Thrall row may follow a retired one', () => {
  const w = world();
  w.db.prepare("UPDATE orc SET retired_at = 1, retired_reason = 'hand' WHERE id = ?").run(w.m);
  w.db.prepare("INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES (?, 'T', 'thrall-2', 'x', 'thrall', 2)").run(id());
});

test('a session with its pid and process start time is kept', () => {
  const w = world();
  w.db.prepare('INSERT INTO session (id, node_id, orc_id, rank, pid, process_started_at, first_seen, last_seen) VALUES (?, ?, ?, ?, 4242, 1000, 1, 1)')
    .run(uuid(10), w.node, w.f, 'warg');
  refuses(() => w.db.prepare('INSERT INTO session (id, node_id, orc_id, rank, pid, process_started_at, first_seen, last_seen) VALUES (?, ?, ?, ?, 4242, -5, 1, 1)')
    .run(uuid(11), w.node, w.f, 'warg'), /CHECK/);
});

test('an answer replaces only an answer to the same question', () => {
  const w = world();
  const other = id();
  w.db.prepare("INSERT INTO question (id, number, task_id, kind, title, asked_at) VALUES (?, 2, ?, 'yes-no', 'other?', 1)").run(other, w.task);
  const first = id();
  w.db.prepare("INSERT INTO answer (id, question_id, at, speaker, text, sha256) VALUES (?, ?, 5, 'founder', 'yes', ?)").run(first, w.q, sha256({ first }));
  refuses(() => w.db.prepare("INSERT INTO answer (id, question_id, at, speaker, text, replaces_answer_id, sha256) VALUES (?, ?, 6, 'founder', 'no', ?, ?)")
    .run(id(), other, first, sha256({ wrong: 1 })), /same question/);
  w.db.prepare("INSERT INTO answer (id, question_id, at, speaker, text, replaces_answer_id, sha256) VALUES (?, ?, 6, 'founder', 'no', ?, ?)")
    .run(id(), w.q, first, sha256({ right: 1 }));
});

function closeOpen(w, kind, at) {
  w.db.prepare('INSERT INTO question_event (id, question_id, at, kind, sha256) VALUES (?, ?, ?, ?, ?)').run(id(), w.q, at, kind, sha256({ kind, at }));
}
function answerAt(w, at, signedBy = null) {
  const a = id();
  w.db.prepare("INSERT INTO answer (id, question_id, at, speaker, text, signed_by, sha256) VALUES (?, ?, ?, 'founder', 'yes', ?, ?)").run(a, w.q, at, signedBy, sha256({ a }));
  return { ...w.db.prepare('SELECT open_at_arrival, authorizes FROM answer_now WHERE id = ?').get(a) };
}

test('answer_now: closed then reopened before the answer counts as open', () => {
  const w = world();
  closeOpen(w, 'closed', 10);
  closeOpen(w, 'reopened', 20);
  assert.deepEqual(answerAt(w, 30), { open_at_arrival: 1, authorizes: 1 });
});

test('answer_now: a reopen in the same millisecond as the answer counts as before it', () => {
  const w = world();
  closeOpen(w, 'closed', 10);
  closeOpen(w, 'reopened', 30);
  assert.deepEqual(answerAt(w, 30), { open_at_arrival: 1, authorizes: 1 });
});

test('answer_now: a signed answer to a closed passkey question does not authorize', () => {
  const w = world();
  w.db.prepare('UPDATE question SET needs_passkey = 1 WHERE id = ?').run(w.q);
  closeOpen(w, 'closed', 10);
  assert.deepEqual(answerAt(w, 20, 'cred-1'), { open_at_arrival: 0, authorizes: 0 });
});

test('a write is refused on a connection whose recursive triggers were turned off', () => {
  const { db } = fresh();
  db.exec('PRAGMA recursive_triggers = OFF');
  refuses(() => inWrite(db, () => takeLabel(db, 'task')), /recursive triggers are off/);
});
