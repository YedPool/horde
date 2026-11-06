// task_now follows task.py's rule (migration 9; T-0299). Temp files only.
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
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-db-state-'));
  dirs.push(dir);
  return path.join(dir, 'fleet.db');
}

const T0 = 1760000000000;
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
// A task and its events, each [kind, minutes after T0, extra columns].
function task(w, events) {
  const id = newId();
  const key = 'T-' + String(keyNo++).padStart(4, '0');
  inWrite(w.db, () => {
    w.db.prepare("INSERT INTO task (id, key, title, source, created_at) VALUES (?, ?, 'a task', 'orc', ?)").run(id, key, T0);
    for (const [kind, min, extra] of events) appendHistory(w.db, 'task_event', { task_id: id, at: T0 + min * 60000, kind, ...(extra ?? {}) });
  });
  return w.db.prepare('SELECT state, prio, owner_orc_id FROM task_now WHERE id = ?').get(id);
}
const state = (w, ...events) => task(w, events).state;
const opened = (w) => ['opened', 0, { prio: 2, to_orc_id: w.f }];

test('a task with only its opened line is opened', () => {
  const w = world();
  assert.equal(state(w, opened(w)), 'opened');
});

test('progress on an opened task means it began', () => {
  const w = world();
  assert.equal(state(w, opened(w), ['progress', 1]), 'started');
});

test('progress leaves any other state alone', () => {
  const w = world();
  assert.equal(state(w, opened(w), ['waiting', 1, { on_kind: 'other', on_text: 'x' }], ['progress', 2]), 'waiting');
  assert.equal(state(w, opened(w), ['done', 1], ['progress', 2]), 'done');
});

test('resumed and reopened read started', () => {
  const w = world();
  assert.equal(state(w, opened(w), ['waiting', 1, { on_kind: 'other', on_text: 'x' }], ['resumed', 2]), 'started');
  assert.equal(state(w, opened(w), ['done', 1], ['reopened', 2]), 'started');
});

test('handed reads opened: the new owner has not begun', () => {
  const w = world();
  assert.equal(state(w, opened(w), ['started', 1], ['handed', 2, { to_orc_id: w.k }]), 'opened');
});

test('progress after a hand-over means the new owner began; progress before it does not count', () => {
  const w = world();
  assert.equal(state(w, opened(w), ['progress', 1], ['handed', 2, { to_orc_id: w.k }]), 'opened');
  assert.equal(state(w, opened(w), ['handed', 1, { to_orc_id: w.k }], ['progress', 2]), 'started');
});

test('priority moves no state', () => {
  const w = world();
  assert.equal(state(w, opened(w), ['started', 1], ['handed', 2, { to_orc_id: w.k }], ['priority', 3, { prio: 1 }]), 'opened');
});

test('every other event gives its own word, newest first', () => {
  const w = world();
  assert.equal(state(w, opened(w), ['started', 1]), 'started');
  assert.equal(state(w, opened(w), ['started', 1], ['done', 2], ['verified', 3]), 'verified');
  assert.equal(state(w, opened(w), ['dropped', 1, { reason: 'r' }]), 'dropped');
  assert.equal(state(w, opened(w), ['done', 5], ['started', 2]), 'done', 'time decides, not the order written');
});

test('the opened line counts first, whatever its time: it never moves the state back', () => {
  const w = world();
  assert.equal(state(w, ['started', 1], ['opened', 9, { prio: 2, to_orc_id: w.f }]), 'started');
  assert.equal(state(w, ['progress', 1], ['opened', 9, { prio: 2, to_orc_id: w.f }]), 'started');
});

test('a late opened line takes neither priority nor owner from an earlier change', () => {
  const w = world();
  const t = task(w, [['priority', 1, { prio: 1 }], ['handed', 2, { to_orc_id: w.k }], ['opened', 9, { prio: 3, to_orc_id: w.f }]]);
  assert.deepEqual([t.prio, t.owner_orc_id], [1, w.k]);
});

test('with two opened lines the newer one stands, and a later priority or hand-over beats both', () => {
  const w = world();
  const two = [['opened', 0, { prio: 3, to_orc_id: w.f }], ['opened', 1, { prio: 2, to_orc_id: w.k }]];
  const a = task(w, two);
  assert.deepEqual([a.prio, a.owner_orc_id], [2, w.k]);
  const b = task(w, [...two.map(([k, m, e]) => [k, m, { ...e }]), ['priority', 2, { prio: 0 }], ['handed', 3, { to_orc_id: w.f }]]);
  assert.deepEqual([b.prio, b.owner_orc_id], [0, w.f]);
});

test('a same-minute tie goes to the event written later', () => {
  const w = world();
  assert.equal(state(w, opened(w), ['started', 1], ['done', 1]), 'done');
  assert.equal(state(w, opened(w), ['handed', 1, { to_orc_id: w.k }], ['progress', 1]), 'started');
});

test('a task with no events has no state', () => {
  const w = world();
  assert.equal(task(w, []).state, null);
});

test('the task tree reads the new state: a reopened task is back in it, a handed one moves to its new owner', () => {
  const w = world();
  task(w, [opened(w), ['done', 1], ['reopened', 2]]);
  task(w, [opened(w), ['handed', 1, { to_orc_id: w.k }]]);
  const rows = w.db.prepare('SELECT owner_orc_id, state FROM task_tree ORDER BY state').all().map((r) => [r.owner_orc_id, r.state]);
  assert.deepEqual(rows, [[w.k, 'opened'], [w.f, 'started']]);
});

test('a version 8 file with rows comes to this version: no row moves, and the old words now read by the rule', () => {
  const file = tempFile();
  const raw = new DatabaseSync(file);
  raw.exec('PRAGMA recursive_triggers = ON');
  for (let v = 0; v < 8; v++) raw.exec(MIGRATIONS[v]);
  raw.exec('PRAGMA user_version = 8');
  const id = newId();
  raw.prepare("INSERT INTO task (id, key, title, source, created_at) VALUES (?, 'T-0001', 'a task', 'orc', ?)").run(id, T0);
  appendHistory(raw, 'task_event', { task_id: id, at: T0, kind: 'opened', prio: 2, backfill: 1 });
  appendHistory(raw, 'task_event', { task_id: id, at: T0 + 1, kind: 'done' });
  appendHistory(raw, 'task_event', { task_id: id, at: T0 + 2, kind: 'reopened' });
  assert.equal(raw.prepare('SELECT state FROM task_now').get().state, 'reopened');
  const before = raw.prepare('SELECT count(*) AS n FROM task_event').get().n;
  raw.close();
  const db = openStore(file);
  handles.push(db);
  assert.equal(db.prepare('PRAGMA user_version').get().user_version, MIGRATIONS.length);
  assert.equal(db.prepare('SELECT count(*) AS n FROM task_event').get().n, before);
  assert.equal(db.prepare('SELECT state FROM task_now').get().state, 'started');
});
