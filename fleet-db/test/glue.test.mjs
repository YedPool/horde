// Migration 3 (the glue: entity registry, tags, links, people, Orc status, the task tree and the per-turn
// check-in), each rule attacked: the row the rule exists to stop is written and must be refused, and the
// row it must still allow is written too. Databases of their own under the temp folder; nothing real is
// read or written.
import './own-profile.mjs';
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { openStore } from '../store.mjs';
import { MIGRATIONS, SCHEMA_VERSION, ENTITY_KINDS } from '../schema.mjs';
import { ulid, sha256 } from '../ids.mjs';
import { appendHistory } from '../write.mjs';
import { findProblems } from '../cli.mjs';

const T0 = Date.UTC(2026, 9, 20, 18, 0, 0);
let seq = 0;
const id = () => ulid(T0 + seq++);
const uuid = (n) => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');

const dirs = [];
const handles = [];
after(() => {
  for (const db of handles) {
    try { db.close(); } catch { /* closed by the test */ }
  }
  for (const d of dirs) fs.rmSync(d, { recursive: true, force: true });
});

function tempFile() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-db-g-'));
  dirs.push(dir); // before anything can throw: a mutant must not leak its folder
  return path.join(dir, 'fleet.db');
}

function fresh() {
  const db = openStore(tempFile());
  handles.push(db);
  return db;
}

// One PC, the Thrall M, Orcs F and K, a session of F's.
function world() {
  const db = fresh();
  const w = { db, node: id(), m: id(), f: id(), k: id(), sf: uuid(1) };
  db.prepare('INSERT INTO node (id, name, is_authority, created_at) VALUES (?, ?, 1, ?)').run(w.node, 'pc-1', T0);
  const orc = db.prepare('INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES (?, ?, ?, ?, ?, ?)');
  orc.run(w.m, 'M', 'thrall', 'Thrall', 'thrall', T0);
  orc.run(w.f, 'F', 'decisions-page', 'Decisions page', 'orc', T0 + 1);
  orc.run(w.k, 'K', 'sleeping-sessions', 'Sleeping sessions', 'orc', T0 + 2);
  db.prepare('INSERT INTO session (id, node_id, orc_id, rank, first_seen, last_seen) VALUES (?, ?, ?, ?, ?, ?)').run(w.sf, w.node, w.f, 'orc', T0, T0);
  return w;
}

const count = (db, sql, ...a) => db.prepare(sql).get(...a).n;
const entityOf = (db, x) => db.prepare('SELECT kind, created_at, created_by_id, updated_at FROM entity WHERE id = ?').get(x);

let keyNo = 1;
// A task, opened for an owner at a priority (its owner and priority come from that event, task_now).
function task(w, { owner, prio = 5, parent = null, position = null, at = T0 + seq++ } = {}) {
  const t = id();
  const key = 'T-' + String(keyNo++).padStart(4, '0');
  w.db.prepare("INSERT INTO task (id, key, title, source, parent_id, position, created_at) VALUES (?, ?, ?, 'founder', ?, ?, ?)").run(t, key, 'task ' + key, parent, position, at);
  appendHistory(w.db, 'task_event', { task_id: t, at, kind: 'opened', prio, to_orc_id: owner });
  return { id: t, key };
}
const done = (w, t) => appendHistory(w.db, 'task_event', { task_id: t.id, at: T0 + seq++, kind: 'done' });

const status = (w, row) => {
  const r = { id: id(), session_id: null, blocked: null, backfill: 0, at: T0 + seq++, ...row };
  w.db.prepare('INSERT INTO orc_status (id, orc_id, session_id, at, doing, blocked, backfill, sha256) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
    .run(r.id, r.orc_id, r.session_id, r.at, r.doing, r.blocked, r.backfill, sha256({ ...r, id: undefined }));
  return r;
};

// --- migration 3 -------------------------------------------------------------------------------------

test('a version 2 file holding rows is brought to the current version, every row in the registry at its own time', () => {
  const file = tempFile();
  const raw = new DatabaseSync(file);
  raw.exec(MIGRATIONS[0]);
  raw.exec(MIGRATIONS[1]);
  raw.exec('PRAGMA user_version = 2');
  const node = id();
  const orc = id();
  const t = id();
  raw.prepare("INSERT INTO node (id, name, is_authority, created_at) VALUES (?, 'pc', 1, 11)").run(node);
  raw.prepare("INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES (?, 'F', 'f', 'F', 'orc', 22)").run(orc);
  raw.prepare("INSERT INTO session (id, node_id, orc_id, rank, first_seen, last_seen) VALUES (?, ?, ?, 'orc', 33, 34)").run(uuid(9), node, orc);
  raw.prepare("INSERT INTO task (id, key, title, source, created_at) VALUES (?, 'T-0001', 't', 'founder', 44)").run(t);
  raw.close();
  const db = openStore(file);
  handles.push(db);
  assert.equal(SCHEMA_VERSION, 8);
  assert.equal(db.prepare('PRAGMA user_version').get().user_version, SCHEMA_VERSION);
  const rows = db.prepare('SELECT id, kind, created_at FROM entity ORDER BY created_at').all().map((r) => ({ ...r }));
  assert.deepEqual(rows, [{ id: node, kind: 'node', created_at: 11 }, { id: orc, kind: 'orc', created_at: 22 },
    { id: uuid(9), kind: 'session', created_at: 33 }, { id: t, kind: 'task', created_at: 44 }]);
  assert.deepEqual(findProblems(db), []);
});

// --- the entity registry ----------------------------------------------------------------------------

test('every object gets its entity row when it is made, with its kind and its own time', () => {
  const w = world();
  assert.deepEqual({ ...entityOf(w.db, w.f) }, { kind: 'orc', created_at: T0 + 1, created_by_id: null, updated_at: null });
  assert.equal(entityOf(w.db, w.sf).kind, 'session');
  const t = task(w, { owner: w.f, at: 555 });
  assert.equal(entityOf(w.db, t.id).created_at, 555);
  // service keeps no time of its own: its entity takes the time of writing
  const s = id();
  w.db.prepare("INSERT INTO service (id, name, kind) VALUES (?, 'relay', 'relay')").run(s);
  assert.ok(Math.abs(entityOf(w.db, s).created_at - Date.now()) < 60000);
});

test('every main table has its triggers: each kind is made, touched and removed with its object', () => {
  const db = fresh();
  for (const t of ENTITY_KINDS) {
    for (const k of ['entity_add', 'entity_touch', 'entity_drop', 'id_fixed']) {
      assert.equal(count(db, "SELECT count(*) AS n FROM sqlite_schema WHERE type = 'trigger' AND name = ?", t + '_' + k), 1, t + '_' + k);
    }
    assert.equal(count(db, "SELECT count(*) AS n FROM sqlite_schema WHERE type = 'trigger' AND name = ?", 'entity_keeps_' + t), 1, t);
    assert.equal(count(db, "SELECT count(*) AS n FROM sqlite_schema WHERE type = 'trigger' AND name = ?", 'entity_needs_' + t), 1, t);
  }
});

test('changing an object stamps its entity updated_at; history rows stay as they were', () => {
  const w = world();
  w.db.prepare("UPDATE orc SET name = 'Decisions' WHERE id = ?").run(w.f);
  const u = entityOf(w.db, w.f).updated_at;
  assert.ok(Number.isSafeInteger(u) && Math.abs(u - Date.now()) < 60000);
  assert.equal(entityOf(w.db, w.k).updated_at, null);
});

test('an object\'s id never changes', () => {
  const w = world();
  assert.throws(() => w.db.prepare('UPDATE orc SET id = ? WHERE id = ?').run(id(), w.k), /an id never changes/);
});

test('an entity\'s id, kind and start are fixed; who made it may be set', () => {
  const w = world();
  assert.throws(() => w.db.prepare("UPDATE entity SET kind = 'task' WHERE id = ?").run(w.f), /never change/);
  assert.throws(() => w.db.prepare('UPDATE entity SET created_at = 1 WHERE id = ?').run(w.f), /never change/);
  w.db.prepare('UPDATE entity SET created_by_id = ? WHERE id = ?').run(w.m, w.f);
  assert.equal(entityOf(w.db, w.f).created_by_id, w.m);
  assert.throws(() => w.db.prepare('UPDATE entity SET created_by_id = ? WHERE id = ?').run(w.f, w.f), /CHECK/);
  assert.throws(() => w.db.prepare('UPDATE entity SET created_by_id = ? WHERE id = ?').run(id(), w.f), /FOREIGN KEY/);
});

test('an entity row cannot be removed while its object is there, and goes when the object goes', () => {
  const w = world();
  assert.throws(() => w.db.prepare('DELETE FROM entity WHERE id = ?').run(w.k), /still there/);
  w.db.prepare('DELETE FROM orc WHERE id = ?').run(w.k);
  assert.equal(entityOf(w.db, w.k), undefined);
});

test('an object that is tagged cannot be removed from under its tag', () => {
  const w = world();
  const tag = id();
  w.db.prepare("INSERT INTO tag (id, name, created_at) VALUES (?, 'area:relay', 1)").run(tag);
  w.db.prepare('INSERT INTO entity_tag (entity_id, tag_id, at) VALUES (?, ?, 1)').run(w.k, tag);
  assert.throws(() => w.db.prepare('DELETE FROM orc WHERE id = ?').run(w.k), /FOREIGN KEY/);
  assert.ok(entityOf(w.db, w.k));
});

test('an entity row for an object that does not exist is refused', () => {
  const w = world();
  assert.throws(() => w.db.prepare("INSERT INTO entity (id, kind, created_at) VALUES (?, 'task', 1)").run(id()), /no task row has this id/);
});

test('a task cannot be moved under its own subtask, and can be moved anywhere else', () => {
  const w = world();
  const a = task(w, { owner: w.f, prio: 1, at: 10 });
  const b = task(w, { owner: w.f, parent: a.id, at: 11 });
  const c = task(w, { owner: w.f, parent: b.id, at: 12 });
  assert.throws(() => w.db.prepare('UPDATE task SET parent_id = ? WHERE id = ?').run(c.id, a.id), /its own subtask/);
  assert.throws(() => w.db.prepare('UPDATE task SET parent_id = ? WHERE id = ?').run(b.id, a.id), /its own subtask/);
  w.db.prepare('UPDATE task SET parent_id = ? WHERE id = ?').run(a.id, c.id);
  assert.deepEqual(tree(w, w.f), ['1 ' + a.key, '1.1 ' + b.key, '1.2 ' + c.key]);
});

test('an entity of a kind no table holds is refused', () => {
  const w = world();
  assert.throws(() => w.db.prepare("INSERT INTO entity (id, kind, created_at) VALUES (?, 'mail', 1)").run(id()), /CHECK/);
});

// --- people and Hordes -------------------------------------------------------------------------------

test('one live founder; a handle is lower case and unique', () => {
  const w = world();
  const p = w.db.prepare('INSERT INTO person (id, name, role, handle, created_at, retired_at) VALUES (?, ?, ?, ?, 1, ?)');
  const founder = id();
  p.run(founder, 'Founder', 'founder', 'founder', null);
  assert.throws(() => p.run(id(), 'Other', 'founder', 'other', null), /UNIQUE/);
  p.run(id(), 'Earlier founder', 'founder', 'earlier', 5); // a retired one is history
  assert.throws(() => p.run(id(), 'Staff', 'staff', 'Has Caps', null), /CHECK/);
  assert.throws(() => p.run(id(), 'Staff', 'staff', 'founder', null), /UNIQUE/);
  assert.throws(() => p.run(id(), 'Bot', 'robot', 'bot', null), /CHECK/);
  assert.equal(entityOf(w.db, founder).kind, 'person');
});

test('a node belongs to a real Horde', () => {
  const w = world();
  const h = id();
  w.db.prepare("INSERT INTO horde (id, name, created_at) VALUES (?, 'main', 1)").run(h);
  w.db.prepare('UPDATE node SET horde_id = ? WHERE id = ?').run(h, w.node);
  assert.throws(() => w.db.prepare('UPDATE node SET horde_id = ? WHERE id = ?').run(id(), w.node), /FOREIGN KEY/);
});

// --- tags and links ----------------------------------------------------------------------------------

test('a tag name is lower case, unique, and tagging twice is one tag', () => {
  const w = world();
  const tag = w.db.prepare('INSERT INTO tag (id, name, created_at) VALUES (?, ?, 1)');
  const t1 = id();
  tag.run(t1, 'prio:urgent');
  assert.throws(() => tag.run(id(), 'prio:urgent'), /UNIQUE/);
  assert.throws(() => tag.run(id(), 'Urgent'), /CHECK/);
  assert.throws(() => tag.run(id(), 'has space'), /CHECK/);
  const on = w.db.prepare('INSERT INTO entity_tag (entity_id, tag_id, at) VALUES (?, ?, 1)');
  on.run(w.f, t1);
  assert.throws(() => on.run(w.f, t1), /UNIQUE|PRIMARY KEY/);
  assert.throws(() => on.run(id(), t1), /FOREIGN KEY/);
});

test('a link joins two real objects with a known relation, live at most once', () => {
  const w = world();
  const a = task(w, { owner: w.f });
  const b = task(w, { owner: w.f });
  const link = w.db.prepare('INSERT INTO link (id, subject_id, relation, object_id, at, retired_at) VALUES (?, ?, ?, ?, 10, ?)');
  const first = id();
  link.run(first, a.id, 'blocks', b.id, null);
  assert.throws(() => link.run(id(), a.id, 'blocks', b.id, null), /UNIQUE/);
  link.run(id(), a.id, 'relates-to', b.id, null); // another relation between the same two is its own link
  assert.throws(() => link.run(id(), a.id, 'loves', b.id, null), /CHECK/);
  assert.throws(() => link.run(id(), a.id, 'blocks', a.id, null), /CHECK/);
  assert.throws(() => link.run(id(), a.id, 'blocks', id(), null), /FOREIGN KEY/);
  assert.throws(() => link.run(id(), a.id, 'mentions', b.id, 5), /CHECK/); // retired before it began
  w.db.prepare('UPDATE link SET retired_at = 20 WHERE id = ?').run(first);
  link.run(id(), a.id, 'blocks', b.id, null); // once retired, the same link can be made again
});

test('a link reaches across kinds: a question answers a task, an Orc is linked to a PR', () => {
  const w = world();
  const t = task(w, { owner: w.f });
  const q = id();
  w.db.prepare("INSERT INTO question (id, number, task_id, kind, title, asked_at) VALUES (?, 1, ?, 'yes-no', 'ok?', 1)").run(q, t.id);
  w.db.prepare("INSERT INTO link (id, subject_id, relation, object_id, at) VALUES (?, ?, 'answers', ?, 1)").run(id(), q, t.id);
  const rows = w.db.prepare("SELECT e.kind FROM link l JOIN entity e ON e.id = l.object_id WHERE l.subject_id = ?").all(q);
  assert.deepEqual(rows.map((r) => r.kind), ['task']);
});

// --- status ------------------------------------------------------------------------------------------

test('the Thrall and every Orc have a status; the current one is the newest', () => {
  const w = world();
  status(w, { orc_id: w.m, doing: 'routing the founder\'s orders', at: 100 });
  status(w, { orc_id: w.f, doing: 'old words', at: 100 });
  const now = status(w, { orc_id: w.f, doing: 'publishing decisions lists', blocked: 'waiting on the relay deploy', at: 200 });
  const rows = w.db.prepare('SELECT orc_id, doing, blocked FROM status_now ORDER BY orc_id').all().map((r) => ({ ...r }));
  assert.deepEqual(rows, [
    { orc_id: w.m, doing: 'routing the founder\'s orders', blocked: null },
    { orc_id: w.f, doing: now.doing, blocked: now.blocked },
  ].sort((x, y) => (x.orc_id < y.orc_id ? -1 : 1)));
});

test('a status line fits the card: 1 to 120 characters doing, at most 200 blocked', () => {
  const w = world();
  assert.throws(() => status(w, { orc_id: w.f, doing: '' }), /CHECK/);
  assert.throws(() => status(w, { orc_id: w.f, doing: 'x'.repeat(121) }), /CHECK/);
  assert.throws(() => status(w, { orc_id: w.f, doing: 'ok', blocked: 'x'.repeat(201) }), /CHECK/);
  status(w, { orc_id: w.f, doing: 'x'.repeat(120), blocked: 'x'.repeat(200) });
});

test('status history and check-ins are append-only', () => {
  const w = world();
  const s = status(w, { orc_id: w.f, doing: 'a' });
  assert.throws(() => w.db.prepare("UPDATE orc_status SET doing = 'b' WHERE id = ?").run(s.id), /append-only/);
  assert.throws(() => w.db.prepare('DELETE FROM orc_status').run(), /append-only/);
  w.db.prepare('INSERT INTO task_checkin (id, session_id, orc_id, at, list_sha256, item_count) VALUES (?, ?, ?, 1, ?, 0)').run(id(), w.sf, w.f, sha256([]));
  assert.throws(() => w.db.prepare('UPDATE task_checkin SET item_count = 3').run(), /append-only/);
  assert.throws(() => w.db.prepare('DELETE FROM task_checkin').run(), /append-only/);
});

test('a status written through the write layer is hashed and written once', () => {
  const w = world();
  const row = { orc_id: w.f, at: 300, doing: 'importing the ledger' };
  const a = appendHistory(w.db, 'orc_status', row);
  const b = appendHistory(w.db, 'orc_status', row);
  assert.deepEqual([a.inserted, b.inserted, b.id], [true, false, a.id]);
});

test('a check-in names a real session and carries a list hash', () => {
  const w = world();
  const put = w.db.prepare('INSERT INTO task_checkin (id, session_id, orc_id, at, list_sha256, item_count) VALUES (?, ?, ?, 1, ?, ?)');
  assert.throws(() => put.run(id(), uuid(77), w.f, sha256([]), 0), /FOREIGN KEY/);
  assert.throws(() => put.run(id(), w.sf, w.f, 'not-a-hash', 0), /CHECK/);
  assert.throws(() => put.run(id(), w.sf, w.f, sha256([]), -1), /CHECK/);
});

// --- the task tree -----------------------------------------------------------------------------------

const tree = (w, orc) => w.db.prepare('SELECT path, key FROM task_tree WHERE owner_orc_id = ? ORDER BY sort').all(orc).map((r) => r.path + ' ' + r.key);

test('an Orc\'s tasks are numbered by priority, then position, then age; subtasks under their parent', () => {
  const w = world();
  const a = task(w, { owner: w.f, prio: 1, at: 10 });
  const b = task(w, { owner: w.f, prio: 2, at: 11 });
  const c = task(w, { owner: w.f, prio: 1, at: 12 });
  const a2 = task(w, { owner: w.f, parent: a.id, position: 2, at: 13 });
  const a1 = task(w, { owner: w.f, parent: a.id, position: 1, at: 14 });
  const a11 = task(w, { owner: w.f, parent: a1.id, at: 15 });
  assert.deepEqual(tree(w, w.f), ['1 ' + a.key, '1.1 ' + a1.key, '1.1.1 ' + a11.key, '1.2 ' + a2.key, '2 ' + c.key, '3 ' + b.key]);
});

test('each Orc\'s list starts at 1, and position orders tasks of one priority', () => {
  const w = world();
  const f1 = task(w, { owner: w.f, prio: 3, position: 2, at: 10 });
  const f2 = task(w, { owner: w.f, prio: 3, position: 1, at: 11 });
  const k1 = task(w, { owner: w.k, prio: 1, at: 12 });
  assert.deepEqual(tree(w, w.f), ['1 ' + f2.key, '2 ' + f1.key]);
  assert.deepEqual(tree(w, w.k), ['1 ' + k1.key]);
});

test('a finished task leaves the tree with its subtasks, and the rest close up', () => {
  const w = world();
  const a = task(w, { owner: w.f, prio: 1, at: 10 });
  task(w, { owner: w.f, parent: a.id, at: 11 });
  const b = task(w, { owner: w.f, prio: 2, at: 12 });
  done(w, a);
  assert.deepEqual(tree(w, w.f), ['1 ' + b.key]);
});

test('subtasks past ten sort as numbers, not as text', () => {
  const w = world();
  const a = task(w, { owner: w.f, prio: 1, at: 10 });
  const subs = [];
  for (let i = 1; i <= 11; i++) subs.push(task(w, { owner: w.f, parent: a.id, position: i, at: 10 + i }));
  const paths = tree(w, w.f).map((r) => r.split(' ')[0]);
  assert.deepEqual(paths.slice(-3), ['1.9', '1.10', '1.11']);
});

test('a task cannot be its own parent', () => {
  const w = world();
  const a = task(w, { owner: w.f });
  assert.throws(() => w.db.prepare('UPDATE task SET parent_id = id WHERE id = ?').run(a.id), /CHECK|its own subtask/);
});

// --- check -------------------------------------------------------------------------------------------

test('check names an object missing from the registry and an entry whose object is gone', () => {
  const w = world();
  w.db.exec('DROP TRIGGER entity_keeps_orc');
  w.db.prepare('DELETE FROM entity WHERE id = ?').run(w.k);
  w.db.exec('PRAGMA foreign_keys = OFF');
  w.db.exec('DROP TRIGGER task_entity_add');
  w.db.prepare("INSERT INTO task (id, key, title, source, created_at) VALUES (?, 'T-0900', 't', 'founder', 1)").run(id());
  w.db.exec('DROP TRIGGER entity_needs_pr');
  w.db.prepare("INSERT INTO entity (id, kind, created_at) VALUES (?, 'pr', 1)").run(id());
  const p = findProblems(w.db);
  assert.ok(p.includes('orc: 1 rows have no entity row'), p.join(' | '));
  assert.ok(p.includes('task: 1 rows have no entity row'), p.join(' | '));
  assert.ok(p.includes('entity: 1 pr rows point at nothing'), p.join(' | '));
});
