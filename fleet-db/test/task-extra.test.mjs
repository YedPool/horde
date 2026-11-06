// task_event_extra and what reads it (migration 10; T-0416, T-0417). Temp files only.
import './own-profile.mjs';
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { openStore, inWrite } from '../store.mjs';
import { MIGRATIONS } from '../schema.mjs';
import { appendHistory, newId } from '../write.mjs';

const dirs = [];
const handles = [];
after(() => {
  for (const db of handles) { try { db.close(); } catch { /* closed by the test */ } }
  for (const d of dirs) fs.rmSync(d, { recursive: true, force: true });
});
function tempFile() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-db-extra-'));
  dirs.push(dir);
  return path.join(dir, 'fleet.db');
}

const T0 = 1760000000000;
const MIN = 60000;
let keyNo = 1;
function world() {
  const db = openStore(tempFile());
  handles.push(db);
  const orc = db.prepare("INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES (?, ?, ?, ?, 'orc', ?)");
  const w = { db, f: newId(), k: newId() };
  orc.run(w.f, 'F', 'lane-f', 'F', T0);
  orc.run(w.k, 'K', 'lane-k', 'K', T0);
  return w;
}
function newTask(w) {
  const id = newId();
  const key = 'T-' + String(keyNo++).padStart(4, '0');
  w.db.prepare("INSERT INTO task (id, key, title, source, created_at) VALUES (?, ?, 'a task', 'orc', ?)").run(id, key, T0);
  return id;
}
// Events in the order written. [kind, minutes, extra]. A kind ending in * goes to task_event_extra. Promises are numbered as written.
function task(w, events) {
  const id = newTask(w);
  let no = 0;
  inWrite(w.db, () => {
    appendHistory(w.db, 'task_event', { task_id: id, at: T0, kind: 'opened', prio: 2, to_orc_id: w.f });
    for (const [kind, min, more] of events) {
      const extra = kind.endsWith('*');
      const row = { task_id: id, at: T0 + min * MIN, kind: kind.replace('*', ''), ...(more ?? {}) };
      if (row.kind === 'promise') row.promise_no = ++no;
      appendHistory(w.db, extra ? 'task_event_extra' : 'task_event', row);
    }
  });
  return w.db.prepare('SELECT state, owner_orc_id FROM task_now WHERE id = ?').get(id);
}
const VOICE = { to_text: 'voiceovers', backfill: 1 };

test('a hand-over to no Orc row: nobody has begun, and the owner is no Orc', () => {
  const w = world();
  assert.deepEqual({ ...task(w, [['started', 1], ['handed*', 2, VOICE]]) }, { state: 'opened', owner_orc_id: null });
});

test('progress after it means the new owner began; progress before it does not count', () => {
  const w = world();
  assert.equal(task(w, [['handed*', 1, VOICE], ['progress', 2]]).state, 'started');
  assert.equal(task(w, [['progress', 1], ['handed*', 2, VOICE]]).state, 'opened');
});

test('a later move beats it, and the owner stays no Orc', () => {
  const w = world();
  assert.deepEqual({ ...task(w, [['handed*', 1, VOICE], ['done', 2]]) }, { state: 'done', owner_orc_id: null });
  assert.deepEqual({ ...task(w, [['handed*', 1, VOICE], ['waiting', 2, { on_kind: 'other', on_text: 'x' }]]) }, { state: 'waiting', owner_orc_id: null });
});

test('it beats an earlier move, and of two the newer is read', () => {
  const w = world();
  assert.equal(task(w, [['done', 1], ['handed*', 2, VOICE]]).state, 'opened');
  assert.equal(task(w, [['handed*', 1, VOICE], ['started', 2], ['handed*', 3, { to_text: 'formfill', backfill: 1 }]]).state, 'opened');
});

test('the newest of two decides when a move sits between them: the older one does not hide it', () => {
  const w = world();
  assert.equal(task(w, [['handed*', 1, VOICE], ['started', 2]]).state, 'started');
  assert.equal(task(w, [['handed*', 1, VOICE], ['done', 2], ['handed*', 3, { to_text: 'formfill', backfill: 1 }], ['started', 4]]).state, 'started');
});

test('a later hand-over to an Orc gives the owner back; an earlier one does not', () => {
  const w = world();
  assert.deepEqual({ ...task(w, [['handed*', 1, VOICE], ['handed', 2, { to_orc_id: w.k }]]) }, { state: 'opened', owner_orc_id: w.k });
  assert.deepEqual({ ...task(w, [['handed', 1, { to_orc_id: w.k }], ['handed*', 2, VOICE]]) }, { state: 'opened', owner_orc_id: null });
});

test('a hand-over naming nobody moves the state and leaves the owner', () => {
  const w = world();
  assert.deepEqual({ ...task(w, [['started', 1], ['handed*', 2, { backfill: 1 }]]) }, { state: 'opened', owner_orc_id: w.f });
  assert.deepEqual({ ...task(w, [['handed', 1, { to_orc_id: w.k }], ['started', 2], ['handed*', 3, { backfill: 1 }]]) }, { state: 'opened', owner_orc_id: w.k });
});

test('promise and kept move neither state nor owner', () => {
  const w = world();
  const due = { due_at: T0 + 99 * MIN, reason: 'r' };
  assert.deepEqual({ ...task(w, [['started', 1], ['promise*', 2, due], ['kept*', 3, { proof: 'p' }]]) }, { state: 'started', owner_orc_id: w.f });
  assert.deepEqual({ ...task(w, [['promise*', 1, due]]) }, { state: 'opened', owner_orc_id: w.f });
});

test('the list goes to no Orc when a task is handed there', () => {
  const w = world();
  task(w, [['handed*', 1, VOICE]]);
  assert.deepEqual(w.db.prepare('SELECT owner_orc_id, path FROM task_tree').all().map((r) => ({ ...r })), [{ owner_orc_id: null, path: '1' }]);
});

// --- open promises ---

const openKeys = (w) => w.db.prepare('SELECT reason FROM task_promise_open ORDER BY at, id').all().map((r) => r.reason);
const P = (min, reason, more) => ['promise*', min, { due_at: T0, reason, ...(more ?? {}) }];
const K = (min, more) => ['kept*', min, { proof: 'p' + min, ...(more ?? {}) }];

test('a promise is open until a kept follows it on the same task', () => {
  const w = world();
  task(w, [P(1, 'open one')]);
  task(w, [P(1, 'kept one'), K(2)]);
  assert.deepEqual(openKeys(w), ['open one']);
});

test('a kept naming nothing closes one promise, the oldest still open, and no later one', () => {
  const w = world();
  task(w, [P(1, 'a'), P(2, 'b'), K(3), P(4, 'c')]);
  assert.deepEqual(openKeys(w), ['b', 'c']);
});

test('two kept close two, in order', () => {
  const w = world();
  task(w, [P(1, 'a'), P(2, 'b'), P(3, 'c'), K(4), K(5)]);
  assert.deepEqual(openKeys(w), ['c']);
});

test('a kept with nothing open closes nothing: it is not saved up for a later promise', () => {
  const w = world();
  task(w, [K(1), P(2, 'a')]);
  assert.deepEqual(openKeys(w), ['a']);
  const v = world();
  task(v, [P(1, 'x'), K(2), K(3), P(4, 'y')]);
  assert.deepEqual(openKeys(v), ['y']);
});

test('time decides the fallback\'s order, not the order written', () => {
  const w = world();
  task(w, [P(5, 'late'), P(1, 'early'), K(9)]);
  assert.deepEqual(openKeys(w), ['late']);
  const v = world();
  task(v, [K(5), P(9, 'after the kept'), P(1, 'before the kept')]);
  assert.deepEqual(openKeys(v), ['after the kept']);
});

test('at one time, the line written first is the older', () => {
  const w = world();
  task(w, [P(1, 'first'), P(1, 'second'), K(2)]);
  assert.deepEqual(openKeys(w), ['second']);
});

test('a promise and a kept at one time: the one written first is the older, so the kept closes it', () => {
  const w = world();
  task(w, [P(1, 'a'), K(1)]);
  assert.deepEqual(openKeys(w), []);
});

test('a named promise is out of the fallback\'s count: a kept with only that one behind it closes nothing, and is not saved up', () => {
  const w = world();
  task(w, [P(1, 'named'), K(2, { closes_no: 1 }), K(3), P(4, 'later')]);
  assert.deepEqual(openKeys(w), ['later']);
});

test('a kept on one task leaves another task\'s promise open', () => {
  const w = world();
  task(w, [P(1, 'a')]);
  task(w, [K(2)]);
  assert.deepEqual(openKeys(w), ['a']);
});

test('--closes: the kept closes the promise it names, and the older one stays open', () => {
  const w = world();
  task(w, [P(1, 'older, only tonight can prove it'), P(2, 'finished'), K(3, { closes_no: 2 })]);
  assert.deepEqual(openKeys(w), ['older, only tonight can prove it']);
});

test('a kept naming a promise is not also a fallback: it closes that one and no other', () => {
  const w = world();
  task(w, [P(1, 'a'), P(2, 'b'), P(3, 'c'), K(4, { closes_no: 3 })]);
  assert.deepEqual(openKeys(w), ['a', 'b']);
});

test('the fallback passes over a promise somebody named', () => {
  const w = world();
  task(w, [P(1, 'a'), P(2, 'b'), P(3, 'c'), K(4, { closes_no: 1 }), K(5)]);
  assert.deepEqual(openKeys(w), ['c']);
});

test('--closes reaches one task only', () => {
  const w = world();
  task(w, [P(1, 'other task, also P1')]);
  task(w, [P(1, 'closed'), K(2, { closes_no: 1 })]);
  assert.deepEqual(openKeys(w), ['other task, also P1']);
});

test('--replaces: a replaced promise reads closed, and the new one stands', () => {
  const w = world();
  task(w, [P(1, 'old'), P(2, 'new', { replaces_no: 1 })]);
  assert.deepEqual(openKeys(w), ['new']);
});

test('a replaced promise takes no fallback kept: the kept goes to the oldest that stands', () => {
  const w = world();
  task(w, [P(1, 'old'), P(2, 'new', { replaces_no: 1 }), P(3, 'other'), K(4)]);
  assert.deepEqual(openKeys(w), ['other']);
});

test('a chain of re-dates leaves only the last', () => {
  const w = world();
  task(w, [P(1, 'a'), P(2, 'b', { replaces_no: 1 }), P(3, 'c', { replaces_no: 2 })]);
  assert.deepEqual(openKeys(w), ['c']);
});

test('--replaces reaches one task only', () => {
  const w = world();
  task(w, [P(1, 'other task, also P1')]);
  task(w, [P(1, 'old'), P(2, 'new', { replaces_no: 1 })]);
  assert.deepEqual(openKeys(w), ['other task, also P1', 'new']);
});

test('the view names the task, its state, the number, the due time and how many later promises stand', () => {
  const w = world();
  const id = newTask(w);
  appendHistory(w.db, 'task_event', { task_id: id, at: T0, kind: 'opened', prio: 2, to_orc_id: w.f });
  appendHistory(w.db, 'task_event', { task_id: id, at: T0 + 1, kind: 'verified' });
  for (const [no, reason] of [[1, 'a'], [2, 'b'], [3, 'c']]) appendHistory(w.db, 'task_event_extra', { task_id: id, at: T0 + no * MIN, kind: 'promise', promise_no: no, due_at: T0 + 5, reason, by_text: 'N1' });
  const rows = w.db.prepare('SELECT key, title, task_state, promise_no, due_at, reason, by_text, later_promises FROM task_promise_open ORDER BY at').all().map((r) => ({ ...r }));
  assert.equal(rows.length, 3);
  assert.match(rows[0].key, /^T-\d+$/);
  assert.deepEqual([rows[0].title, rows[0].task_state, rows[0].due_at, rows[0].reason, rows[0].by_text], ['a task', 'verified', T0 + 5, 'a', 'N1']);
  assert.deepEqual(rows.map((r) => r.promise_no), [1, 2, 3]);
  assert.deepEqual(rows.map((r) => r.later_promises), [2, 1, 0]);
});

test('a hand-over line is no promise and no kept: it neither lists nor closes', () => {
  const w = world();
  task(w, [P(1, 'a'), ['handed*', 2, VOICE]]);
  assert.deepEqual(openKeys(w), ['a']);
});

// --- the table's rules ---

test('the table refuses what its rules exist to stop', () => {
  const w = world();
  const id = newTask(w);
  const put = (row) => appendHistory(w.db, 'task_event_extra', { task_id: id, at: T0 + (keyNo++), ...row });
  assert.throws(() => put({ kind: 'started' }), /CHECK/);
  assert.throws(() => put({ kind: 'kept', due_at: T0 }), /CHECK/, 'only a promise has a due time');
  assert.throws(() => put({ kind: 'promise', promise_no: 1, reason: 'r' }), /CHECK/, 'a promise written by hand has a due time');
  assert.throws(() => put({ kind: 'promise', due_at: T0, reason: 'r' }), /CHECK/, 'a promise has its number');
  assert.throws(() => put({ kind: 'promise', promise_no: 0, due_at: T0, reason: 'r' }), /CHECK/, 'numbers start at 1');
  assert.throws(() => put({ kind: 'kept', promise_no: 1 }), /CHECK/, 'only a promise has a number');
  assert.throws(() => put({ kind: 'kept', to_text: 'x' }), /CHECK/, 'only a hand-over names someone');
  assert.throws(() => put({ kind: 'kept', replaces_no: 1 }), /CHECK/, 'only a promise replaces');
  assert.throws(() => put({ kind: 'promise', promise_no: 9, due_at: T0, closes_no: 1 }), /CHECK/, 'only a kept closes');
  assert.throws(() => put({ kind: 'kept', closes_no: 0 }), /CHECK/, 'numbers start at 1');
  put({ kind: 'promise', promise_no: 1, reason: 'imported', backfill: 1 });
  assert.throws(() => put({ kind: 'promise', promise_no: 1, reason: 'second P1', backfill: 1 }), /UNIQUE/, 'a number is one promise of its task');
  const other = newTask(w);
  appendHistory(w.db, 'task_event_extra', { task_id: other, at: T0, kind: 'promise', promise_no: 1, reason: 'another task has its own P1', backfill: 1 });
});

test('a line cannot be changed or deleted, and an event of the same words is one row', () => {
  const w = world();
  const id = newTask(w);
  const row = { task_id: id, at: T0, kind: 'kept', proof: 'p' };
  const first = appendHistory(w.db, 'task_event_extra', row);
  assert.equal(appendHistory(w.db, 'task_event_extra', row).inserted, false);
  assert.throws(() => w.db.prepare("UPDATE task_event_extra SET proof = 'q' WHERE id = ?").run(first.id), /append|history|never|changed/i);
  assert.throws(() => w.db.prepare('DELETE FROM task_event_extra WHERE id = ?').run(first.id), /append|history|never|deleted|changed/i);
});

// --- the migration ---

test('a version 9 file with rows comes to this version: no event moves, no hash changes, and the view still reads them', () => {
  const file = tempFile();
  const raw = new DatabaseSync(file);
  raw.exec('PRAGMA recursive_triggers = ON');
  for (let v = 0; v < 9; v++) raw.exec(MIGRATIONS[v]);
  raw.exec('PRAGMA user_version = 9');
  const id = newId();
  raw.prepare("INSERT INTO task (id, key, title, source, created_at) VALUES (?, 'T-0001', 'a task', 'orc', ?)").run(id, T0);
  appendHistory(raw, 'task_event', { task_id: id, at: T0, kind: 'opened', prio: 2, backfill: 1 });
  appendHistory(raw, 'task_event', { task_id: id, at: T0 + 1, kind: 'started' });
  const before = raw.prepare('SELECT id, sha256 FROM task_event ORDER BY id').all().map((r) => ({ ...r }));
  raw.close();
  const db = openStore(file);
  handles.push(db);
  assert.equal(db.prepare('PRAGMA user_version').get().user_version, MIGRATIONS.length);
  assert.deepEqual(db.prepare('SELECT id, sha256 FROM task_event ORDER BY id').all().map((r) => ({ ...r })), before);
  assert.equal(db.prepare('SELECT state FROM task_now').get().state, 'started');
  assert.equal(db.prepare('SELECT count(*) AS n FROM task_event_extra').get().n, 0);
  // The same line written again hashes the same: task_event's columns did not change, so a sync adds nothing.
  assert.equal(appendHistory(db, 'task_event', { task_id: id, at: T0 + 1, kind: 'started' }).inserted, false);
});
