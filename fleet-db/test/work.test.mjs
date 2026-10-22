// Migration 6 (work_unit) and the write verb (work.mjs, work-cli.mjs), each attacked: a row the rule exists to
// stop is written and must be refused, and the row it must still allow is written too. Databases of their own
// under the temp folder; nothing real is read or written.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { openStore } from '../store.mjs';
import { MIGRATIONS, SCHEMA_VERSION } from '../schema.mjs';
import { ulid } from '../ids.mjs';
import { startWork, endWork, listWork } from '../work.mjs';
import { main as workMain, parseFlags } from '../work-cli.mjs';
import { findProblems } from '../cli.mjs';
import { importFleet } from '../import.mjs';

const T0 = Date.UTC(2026, 9, 21, 12, 0, 0);
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

function tempDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-db-wu-'));
  dirs.push(dir);
  return dir;
}

// One PC, Orc F, a task T-0001, a parent session of F (uuid 1) and two more sessions (2 and 3).
function world() {
  const dir = tempDir();
  const file = path.join(dir, 'fleet.db');
  const db = openStore(file);
  handles.push(db);
  const w = { dir, file, db, node: id(), f: id(), task: id() };
  db.prepare('INSERT INTO node (id, name, is_authority, created_at) VALUES (?, ?, 1, ?)').run(w.node, 'pc-1', T0);
  db.prepare("INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES (?, 'F', 'decisions-page', 'Decisions', 'orc', ?)").run(w.f, T0);
  db.prepare("INSERT INTO task (id, key, title, source, created_at) VALUES (?, 'T-0001', 'a task', 'founder', ?)").run(w.task, T0);
  const s = db.prepare('INSERT INTO session (id, node_id, orc_id, rank, first_seen, last_seen) VALUES (?, ?, ?, ?, ?, ?)');
  s.run(uuid(1), w.node, w.f, 'orc', T0, T0);
  s.run(uuid(2), w.node, null, 'warg', T0, T0);
  s.run(uuid(3), w.node, null, 'warg', T0, T0);
  return w;
}

// A raw work_unit row; any column can be overridden, null included.
function put(db, over = {}) {
  const r = { id: id(), kind: 'agent', parent_session_id: uuid(1), orc_id: null, agent_id: 'a' + seq, agent_type: 'general-purpose', session_id: null,
    task_id: null, task_flag: 'no_task', work_type: 'build', domain: null, model: null, started_at: T0, ended_at: null, outcome: 'running', ...over };
  const cols = Object.keys(r);
  db.prepare('INSERT INTO work_unit (' + cols.join(', ') + ') VALUES (' + cols.map(() => '?').join(', ') + ')').run(...cols.map((c) => r[c]));
  return r;
}
const warg = (over = {}) => ({ kind: 'warg', agent_id: null, agent_type: null, session_id: uuid(2), ...over });

// ---------------------------------------------------------------------------------------------------------
// the migration

test('work_unit: the schema is version 6 and the table, its three indexes and its four triggers are there', () => {
  const w = world();
  assert.equal(SCHEMA_VERSION, 6);
  assert.equal(w.db.prepare('PRAGMA user_version').get().user_version, 6);
  const idx = w.db.prepare("SELECT name FROM sqlite_schema WHERE type = 'index' AND tbl_name = 'work_unit' AND name LIKE 'work_unit_%' ORDER BY name").all().map((r) => r.name);
  assert.deepEqual(idx, ['work_unit_orc', 'work_unit_running', 'work_unit_task']);
  const trg = w.db.prepare("SELECT name FROM sqlite_schema WHERE type = 'trigger' AND tbl_name = 'work_unit' ORDER BY name").all().map((r) => r.name);
  assert.deepEqual(trg, ['work_unit_end_is_final', 'work_unit_identity_fixed', 'work_unit_no_delete', 'work_unit_task_fill_only']);
  assert.match(w.db.prepare("SELECT sql FROM sqlite_schema WHERE name = 'work_unit_orc'").get().sql, /orc_id, started_at/);
  assert.match(w.db.prepare("SELECT sql FROM sqlite_schema WHERE name = 'work_unit_running'").get().sql, /WHERE outcome = 'running'/);
});

test('work_unit: a good agent row and a good warg row are written', () => {
  const w = world();
  put(w.db);
  put(w.db, warg());
  put(w.db, { task_id: w.task, task_flag: null, work_type: 'review', domain: 'decisions-page', model: 'sonnet' });
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM work_unit').get().n, 3);
  assert.deepEqual(findProblems(w.db), []);
});

test('work_unit: every CHECK refuses the row it exists to stop', () => {
  const w = world();
  const bad = (over, re, why) => assert.throws(() => put(w.db, over), re, why);
  bad({ id: 'not-a-ulid' }, /CHECK/, 'id must be a ULID');
  bad({ kind: 'bot' }, /CHECK/, 'kind');
  bad({ agent_id: null }, /CHECK/, 'an agent needs its agent_id');
  bad({ session_id: uuid(2) }, /CHECK/, 'an agent has no session');
  bad(warg({ session_id: null }), /CHECK|NOT NULL/, 'a warg needs its session');
  bad(warg({ agent_id: 'x1' }), /CHECK/, 'a warg has no agent_id');
  bad(warg({ agent_type: 'general-purpose' }), /CHECK/, 'a warg has no agent_type');
  bad(warg({ session_id: uuid(1) }), /CHECK/, 'a warg is not its own parent');
  bad({ task_id: w.task, task_flag: 'no_task' }, /CHECK/, 'a task and a flag together');
  bad({ task_id: null, task_flag: null }, /CHECK/, 'neither a task nor a flag');
  bad({ task_flag: 'later' }, /CHECK/, 'flag value');
  bad({ work_type: 'nap' }, /CHECK/, 'work type');
  bad({ outcome: 'lost', ended_at: T0 }, /CHECK/, 'outcome');
  bad({ outcome: 'running', ended_at: T0 + 1 }, /CHECK/, 'running with an end');
  bad({ outcome: 'done', ended_at: null }, /CHECK/, 'ended with no end time');
  bad({ outcome: 'done', ended_at: T0 - 1 }, /CHECK/, 'ended before it started');
  bad({ started_at: -1 }, /CHECK/, 'negative start');
  bad({ domain: '' }, /CHECK/, 'empty domain');
  bad({ domain: 'd'.repeat(121) }, /CHECK/, 'long domain');
  bad({ model: '' }, /CHECK/, 'empty model');
  bad({ model: 'm'.repeat(81) }, /CHECK/, 'long model');
  bad({ agent_id: '' }, /CHECK/, 'empty agent_id');
  bad({ agent_id: 'a'.repeat(201) }, /CHECK/, 'long agent_id');
  bad({ agent_id: 'has space' }, /CHECK/, 'agent_id with a space');
  bad({ agent_id: 'caf\u00e9' }, /CHECK/, 'agent_id not ASCII');
  bad({ agent_id: 'tab\there' }, /CHECK/, 'agent_id with a control character');
  bad({ agent_type: 'two words' }, /CHECK/, 'agent_type with a space');
  bad({ agent_type: '' }, /CHECK/, 'empty agent_type');
  bad({ agent_type: 't'.repeat(81) }, /CHECK/, 'long agent_type');
  bad({ parent_session_id: uuid(99) }, /FOREIGN KEY/, 'parent must be a session');
  bad({ parent_session_id: null }, /NOT NULL/, 'parent is required');
  bad({ orc_id: id() }, /FOREIGN KEY/, 'orc must exist');
  bad({ task_id: id(), task_flag: null }, /FOREIGN KEY/, 'task must exist');
  bad(warg({ session_id: uuid(98) }), /FOREIGN KEY/, 'the warg session must exist');
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM work_unit').get().n, 0);
  // the edges that must still be allowed
  put(w.db, { agent_id: 'a'.repeat(200), model: 'm'.repeat(80), domain: 'd'.repeat(120), agent_type: 't'.repeat(80) });
  put(w.db, { outcome: 'done', ended_at: T0 });
});

test('work_unit: one agent id per parent and one unit per session', () => {
  const w = world();
  put(w.db, { agent_id: 'same' });
  assert.throws(() => put(w.db, { agent_id: 'same' }), /UNIQUE/);
  put(w.db, { agent_id: 'same', parent_session_id: uuid(2) }); // another parent may reuse the id
  put(w.db, warg());
  assert.throws(() => put(w.db, warg()), /UNIQUE/);
});

test('work_unit: id, kind, parent, agent_id, session_id and started_at never change', () => {
  const w = world();
  const a = put(w.db, { agent_id: 'fixed1' });
  const g = put(w.db, warg());
  const set = (sql, ...args) => w.db.prepare(sql).run(...args);
  assert.throws(() => set('UPDATE work_unit SET id = ? WHERE id = ?', id(), a.id), /never change/);
  assert.throws(() => set("UPDATE work_unit SET kind = 'warg' WHERE id = ?", a.id), /never change/);
  assert.throws(() => set('UPDATE work_unit SET parent_session_id = ? WHERE id = ?', uuid(2), a.id), /never change/);
  assert.throws(() => set("UPDATE work_unit SET agent_id = 'other' WHERE id = ?", a.id), /never change/);
  assert.throws(() => set('UPDATE work_unit SET session_id = ? WHERE id = ?', uuid(3), g.id), /never change/);
  assert.throws(() => set('UPDATE work_unit SET started_at = started_at + 1 WHERE id = ?', a.id), /never change/);
  // what may change: the model, the domain and the type of a running unit
  set("UPDATE work_unit SET model = 'opus', domain = 'form-fill', work_type = 'verify' WHERE id = ?", a.id);
  assert.equal(w.db.prepare('SELECT model FROM work_unit WHERE id = ?').get(a.id).model, 'opus');
});

test('work_unit: a unit leaves running once and an ended unit keeps its end and its outcome', () => {
  const w = world();
  const a = put(w.db, { agent_id: 'life1' });
  w.db.prepare("UPDATE work_unit SET outcome = 'done', ended_at = ? WHERE id = ?").run(T0 + 5, a.id);
  assert.throws(() => w.db.prepare("UPDATE work_unit SET outcome = 'failed' WHERE id = ?").run(a.id), /keeps its end/);
  assert.throws(() => w.db.prepare('UPDATE work_unit SET ended_at = ended_at + 1 WHERE id = ?').run(a.id), /keeps its end/);
  assert.throws(() => w.db.prepare("UPDATE work_unit SET outcome = 'running', ended_at = NULL WHERE id = ?").run(a.id), /keeps its end/);
  // a no-op rewrite of the same values is allowed
  w.db.prepare("UPDATE work_unit SET outcome = 'done', ended_at = ? WHERE id = ?").run(T0 + 5, a.id);
  const row = w.db.prepare('SELECT outcome, ended_at FROM work_unit WHERE id = ?').get(a.id);
  assert.deepEqual({ ...row }, { outcome: 'done', ended_at: T0 + 5 });
});

test('work_unit: a unit is never deleted, running or ended', () => {
  const w = world();
  const a = put(w.db, { agent_id: 'del1' });
  const b = put(w.db, { agent_id: 'del2', outcome: 'stopped', ended_at: T0 });
  assert.throws(() => w.db.prepare('DELETE FROM work_unit WHERE id = ?').run(a.id), /never deleted/);
  assert.throws(() => w.db.prepare('DELETE FROM work_unit WHERE id = ?').run(b.id), /never deleted/);
  assert.throws(() => w.db.prepare('INSERT OR REPLACE INTO work_unit (id, kind, parent_session_id, agent_id, task_flag, work_type, started_at, outcome) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
    .run(a.id, 'agent', uuid(1), 'del1', 'no_task', 'build', T0, 'running'), /never deleted|UNIQUE|constraint/);
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM work_unit').get().n, 2);
});

test('work_unit: a task is filled only into a no_task unit, then never changes', () => {
  const w = world();
  const other = id();
  w.db.prepare("INSERT INTO task (id, key, title, source, created_at) VALUES (?, 'T-0002', 'b', 'founder', ?)").run(other, T0);
  const n = put(w.db, { agent_id: 'nt1' });
  const bf = put(w.db, { agent_id: 'bf1', task_flag: 'backfill' });
  const t = put(w.db, { agent_id: 'tk1', task_id: w.task, task_flag: null });
  const upd = (sql, ...a) => w.db.prepare(sql).run(...a);
  assert.throws(() => upd("UPDATE work_unit SET task_flag = 'backfill' WHERE id = ?", n.id), /filled only/, 'no_task is not turned into backfill');
  assert.throws(() => upd('UPDATE work_unit SET task_id = ?, task_flag = NULL WHERE id = ?', w.task, bf.id), /filled only/, 'backfill stays');
  assert.throws(() => upd("UPDATE work_unit SET task_flag = 'no_task' WHERE id = ?", bf.id), /filled only/, 'backfill is not turned into no_task');
  assert.throws(() => upd('UPDATE work_unit SET task_id = ? WHERE id = ?', other, t.id), /filled only/, 'a set task does not change');
  assert.throws(() => upd("UPDATE work_unit SET task_id = NULL, task_flag = 'no_task' WHERE id = ?", t.id), /filled only/, 'a set task is not cleared');
  assert.throws(() => upd('UPDATE work_unit SET task_id = ? WHERE id = ?', w.task, n.id), /CHECK/, 'a task with the flag still set is refused by the CHECK');
  upd('UPDATE work_unit SET task_id = ?, task_flag = NULL WHERE id = ?', w.task, n.id);
  assert.equal(w.db.prepare('SELECT task_id FROM work_unit WHERE id = ?').get(n.id).task_id, w.task);
  assert.throws(() => upd('UPDATE work_unit SET task_id = ? WHERE id = ?', other, n.id), /filled only/, 'once filled it is fixed');
});

test('horde db check: a warg whose session has another parent, and a unit whose Orc is not its parent Orc, are problems', () => {
  const w = world();
  put(w.db, warg({ orc_id: w.f }));
  assert.deepEqual(findProblems(w.db), []);
  w.db.prepare('UPDATE session SET parent_session_id = ? WHERE id = ?').run(uuid(3), uuid(2));
  assert.deepEqual(findProblems(w.db).map((p) => p.replace(/work unit \w+/, 'work unit X')), ['work unit X: its session has a different parent than the unit names']);
  w.db.prepare('UPDATE session SET parent_session_id = NULL WHERE id = ?').run(uuid(2));
  assert.deepEqual(findProblems(w.db), []);
  const g = id();
  w.db.prepare("INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES (?, 'G', 'g', 'G', 'orc', ?)").run(g, T0);
  put(w.db, { agent_id: 'wrongorc', orc_id: g });
  assert.deepEqual(findProblems(w.db).map((p) => p.replace(/work unit \w+/, 'work unit X')), ['work unit X: its Orc is not the Orc of its parent session']);
});

test('a schema 5 file keeps every row, gains work_unit, and checks ok', () => {
  const dir = tempDir();
  const file = path.join(dir, 'fleet.db');
  const raw = new DatabaseSync(file);
  for (let i = 0; i < 5; i++) raw.exec(MIGRATIONS[i]);
  raw.exec('PRAGMA user_version = 5');
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
  assert.equal(db.prepare('PRAGMA user_version').get().user_version, 6);
  assert.equal(db.prepare('SELECT count(*) AS n FROM session').get().n, 1);
  assert.equal(db.prepare('SELECT count(*) AS n FROM task').get().n, 1);
  assert.equal(db.prepare('SELECT count(*) AS n FROM work_unit').get().n, 0);
  assert.deepEqual(findProblems(db), []);
  const r = startWork(db, { kind: 'agent', parentSession: uuid(9), agentId: 'mig1', workType: 'build', task: 'T-0001' });
  assert.equal(r.action, 'started');
  assert.equal(db.prepare('SELECT orc_id FROM work_unit').get().orc_id, orc);
  assert.deepEqual(findProblems(db), []);
});

// ---------------------------------------------------------------------------------------------------------
// the write verb

test('start and end an agent: running, ended, the repeat of each changes nothing', () => {
  const w = world();
  const s = startWork(w.db, { kind: 'agent', parentSession: uuid(1), agentId: 'ag-1', agentType: 'general-purpose', workType: 'research', task: 'T-0001', domain: 'decisions-page', model: 'sonnet', at: T0 + 10 });
  assert.equal(s.action, 'started');
  assert.deepEqual(s.warnings, []);
  const again = startWork(w.db, { kind: 'agent', parentSession: uuid(1), agentId: 'ag-1', workType: 'build', at: T0 + 99 });
  assert.deepEqual({ action: again.action, id: again.id }, { action: 'already', id: s.id });
  const row = { ...w.db.prepare('SELECT * FROM work_unit').get() };
  assert.deepEqual(row, { id: s.id, kind: 'agent', parent_session_id: uuid(1), orc_id: w.f, agent_id: 'ag-1', agent_type: 'general-purpose', session_id: null,
    task_id: w.task, task_flag: null, work_type: 'research', domain: 'decisions-page', model: 'sonnet', started_at: T0 + 10, ended_at: null, outcome: 'running' });
  const e = endWork(w.db, { parentSession: uuid(1), agentId: 'ag-1', outcome: 'done', at: T0 + 20 });
  assert.deepEqual(e, { action: 'ended', id: s.id, outcome: 'done' });
  assert.deepEqual(endWork(w.db, { parentSession: uuid(1), agentId: 'ag-1', outcome: 'done', at: T0 + 30 }), { action: 'already', id: s.id, outcome: 'done' });
  assert.throws(() => endWork(w.db, { parentSession: uuid(1), agentId: 'ag-1', outcome: 'failed' }), /already ended as done/);
  const after = w.db.prepare('SELECT ended_at, outcome FROM work_unit').get();
  assert.deepEqual({ ...after }, { ended_at: T0 + 20, outcome: 'done' });
  assert.equal(startWork(w.db, { kind: 'agent', parentSession: uuid(1), agentId: 'ag-1', workType: 'build' }).action, 'already', 'a start repeated after the end is still a repeat');
});

test('start and end a warg by its own session', () => {
  const w = world();
  const s = startWork(w.db, { kind: 'warg', parentSession: uuid(1), session: uuid(2), workType: 'build', task: 'T-0001', at: T0 + 1 });
  assert.equal(s.action, 'started');
  const row = w.db.prepare('SELECT kind, agent_id, agent_type, session_id, orc_id FROM work_unit').get();
  assert.deepEqual({ ...row }, { kind: 'warg', agent_id: null, agent_type: null, session_id: uuid(2), orc_id: w.f });
  assert.equal(startWork(w.db, { kind: 'warg', parentSession: uuid(1), session: uuid(2), workType: 'build' }).action, 'already');
  assert.throws(() => startWork(w.db, { kind: 'warg', parentSession: uuid(3), session: uuid(2), workType: 'build' }), /another parent/);
  assert.equal(endWork(w.db, { session: uuid(2), outcome: 'abandoned', at: T0 + 5 }).action, 'ended');
  assert.equal(endWork(w.db, { session: uuid(2), outcome: 'abandoned' }).action, 'already');
  assert.throws(() => endWork(w.db, { session: uuid(2), outcome: 'done' }), /already ended as abandoned/);
});

test('a parent or warg session fleet.db has not seen gets a stub row', () => {
  const w = world();
  startWork(w.db, { kind: 'agent', parentSession: uuid(50), agentId: 'stub1', workType: 'other', at: T0 + 7 });
  const p = w.db.prepare('SELECT node_id, orc_id, rank, first_seen, last_seen FROM session WHERE id = ?').get(uuid(50));
  assert.deepEqual({ ...p }, { node_id: w.node, orc_id: null, rank: 'unknown', first_seen: T0 + 7, last_seen: T0 + 7 });
  assert.equal(w.db.prepare('SELECT orc_id FROM work_unit').get().orc_id, null);
  startWork(w.db, { kind: 'warg', parentSession: uuid(1), session: uuid(60), workType: 'build', at: T0 + 8 });
  const g = w.db.prepare('SELECT node_id, orc_id, rank, parent_session_id FROM session WHERE id = ?').get(uuid(60));
  assert.deepEqual({ ...g }, { node_id: w.node, orc_id: w.f, rank: 'warg', parent_session_id: uuid(1) });
  assert.deepEqual(findProblems(w.db), []);
});

test('a fresh file with no node gets one', () => {
  const dir = tempDir();
  const db = openStore(path.join(dir, 'fleet.db'));
  handles.push(db);
  startWork(db, { kind: 'agent', parentSession: uuid(1), agentId: 'first', workType: 'other' });
  assert.equal(db.prepare('SELECT count(*) AS n FROM node').get().n, 1);
  assert.equal(db.prepare('SELECT count(*) AS n FROM session').get().n, 1);
  assert.deepEqual(findProblems(db), []);
});

test('a warg session with a different parent already in fleet.db is refused', () => {
  const w = world();
  w.db.prepare('UPDATE session SET parent_session_id = ? WHERE id = ?').run(uuid(3), uuid(2));
  assert.throws(() => startWork(w.db, { kind: 'warg', parentSession: uuid(1), session: uuid(2), workType: 'build' }), /different parent/);
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM work_unit').get().n, 0);
});

test('no task is no_task; a task fleet.db does not know is no_task with a warning naming it; a known one links', () => {
  const w = world();
  const none = startWork(w.db, { kind: 'agent', parentSession: uuid(1), agentId: 'n1', workType: 'build' });
  assert.deepEqual(none.warnings, []);
  const unknown = startWork(w.db, { kind: 'agent', parentSession: uuid(1), agentId: 'n2', workType: 'build', task: 'T-0777' });
  assert.equal(unknown.warnings.length, 1);
  assert.match(unknown.warnings[0], /T-0777/);
  startWork(w.db, { kind: 'agent', parentSession: uuid(1), agentId: 'n3', workType: 'build', task: 'T-0001' });
  const rows = w.db.prepare('SELECT agent_id, task_id, task_flag FROM work_unit ORDER BY agent_id').all().map((r) => ({ ...r }));
  assert.deepEqual(rows, [{ agent_id: 'n1', task_id: null, task_flag: 'no_task' }, { agent_id: 'n2', task_id: null, task_flag: 'no_task' },
    { agent_id: 'n3', task_id: w.task, task_flag: null }]);
});

test('agent_id is stored exactly as given: a typical harness id and odd valid ones round-trip byte for byte', () => {
  const w = world();
  const ids = ['a3f9c01b7d2e4f5a6', 'AbC-123_xyz.0', '-leading-dash', 'a'.repeat(200), 'MiXeD:Case/Path~ok'];
  for (const a of ids) startWork(w.db, { kind: 'agent', parentSession: uuid(1), agentId: a, workType: 'other' });
  const back = w.db.prepare('SELECT agent_id FROM work_unit').all().map((r) => r.agent_id);
  assert.deepEqual([...back].sort(), [...ids].sort());
  for (const a of ids) assert.ok(Buffer.from(back.find((x) => x === a)).equals(Buffer.from(a)));
  // never trimmed or re-cased: a padded id is refused, not repaired, and no row for the trimmed one appears
  for (const bad of [' a3f9c01b', 'a3f9c01b ', 'a3f9\tc01b', '', 'a'.repeat(201), 'caf\u00e9']) {
    assert.throws(() => startWork(w.db, { kind: 'agent', parentSession: uuid(1), agentId: bad, workType: 'other' }), /AgentId/, JSON.stringify(bad));
  }
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM work_unit').get().n, ids.length);
  // the id differing only by case is another id (it is not lower-cased)
  startWork(w.db, { kind: 'agent', parentSession: uuid(1), agentId: 'A3F9C01B7D2E4F5A6', workType: 'other' });
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM work_unit').get().n, ids.length + 1);
});

test('a session uuid in capitals is accepted and stored in lower case, as the importer does', () => {
  const w = world();
  const up = uuid(1).toUpperCase();
  const lowerHex = '00000000-0000-4000-8000-00000000000A';
  startWork(w.db, { kind: 'agent', parentSession: lowerHex, agentId: 'up1', workType: 'other' });
  assert.equal(w.db.prepare('SELECT parent_session_id FROM work_unit').get().parent_session_id, lowerHex.toLowerCase());
  assert.equal(startWork(w.db, { kind: 'agent', parentSession: up, agentId: 'up2', workType: 'other' }).action, 'started');
  assert.equal(w.db.prepare("SELECT parent_session_id FROM work_unit WHERE agent_id = 'up2'").get().parent_session_id, uuid(1));
});

test('start refuses a bad request in one line and writes nothing', () => {
  const w = world();
  const base = { kind: 'agent', parentSession: uuid(1), agentId: 'ok1', workType: 'build' };
  const cases = [
    [{ kind: 'bot' }, /kind/], [{ kind: undefined }, /kind/], [{ parentSession: 'nope' }, /ParentSession/], [{ parentSession: undefined }, /ParentSession/],
    [{ workType: 'nap' }, /work type/], [{ workType: undefined }, /work type/], [{ agentId: undefined }, /AgentId/], [{ session: uuid(2) }, /no session/],
    [{ agentType: 'two words' }, /AgentType/], [{ task: 'T-1' }, /Task/], [{ task: 'task 1' }, /Task/], [{ domain: '' }, /Domain/],
    [{ domain: 'd'.repeat(121) }, /Domain/], [{ model: 'm'.repeat(81) }, /Model/], [{ at: -5 }, /At/], [{ at: 1.5 }, /At/],
    [{ kind: 'warg', agentId: undefined, session: undefined }, /needs its Session/], [{ kind: 'warg', session: uuid(2) }, /no AgentId/],
    [{ kind: 'warg', agentId: undefined, session: uuid(2), agentType: 'x' }, /no AgentType/], [{ kind: 'warg', agentId: undefined, session: uuid(1) }, /own parent/],
    [{ kind: 'warg', agentId: undefined, session: 'zzz' }, /Session/],
  ];
  for (const [over, re] of cases) {
    assert.throws(() => startWork(w.db, { ...base, ...over }), (e) => e.refusal === true && re.test(e.message), JSON.stringify(over));
  }
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM work_unit').get().n, 0);
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM session').get().n, 3, 'a refused start leaves no stub session');
});

test('end refuses what it cannot find or understand', () => {
  const w = world();
  startWork(w.db, { kind: 'agent', parentSession: uuid(1), agentId: 'e1', workType: 'build', at: T0 + 100 });
  const end = (o) => endWork(w.db, o);
  assert.throws(() => end({ parentSession: uuid(1), agentId: 'never', outcome: 'done' }), /no work unit was started for agent never/);
  assert.throws(() => end({ session: uuid(3), outcome: 'done' }), /no work unit was started for session/);
  assert.throws(() => end({ parentSession: uuid(2), agentId: 'e1', outcome: 'done' }), /no work unit/, 'another parent');
  assert.throws(() => end({ parentSession: uuid(1), agentId: 'e1', outcome: 'running' }), /Outcome/);
  assert.throws(() => end({ parentSession: uuid(1), agentId: 'e1', outcome: 'lost' }), /Outcome/);
  assert.throws(() => end({ parentSession: uuid(1), agentId: 'e1' }), /Outcome/);
  assert.throws(() => end({ outcome: 'done' }), /name the unit/);
  assert.throws(() => end({ parentSession: uuid(1), agentId: 'e1', session: uuid(2), outcome: 'done' }), /name the unit/);
  assert.throws(() => end({ parentSession: uuid(1), session: uuid(2), outcome: 'done' }), /drop ParentSession/);
  assert.throws(() => end({ parentSession: uuid(1), agentId: 'e1', outcome: 'done', at: T0 + 50 }), /before the unit started/);
  assert.equal(w.db.prepare('SELECT outcome FROM work_unit').get().outcome, 'running');
  // no end time named: a clock behind the start does not strand the unit, it ends at the start
  const e = endWork(w.db, { parentSession: uuid(1), agentId: 'e1', outcome: 'stopped' }, { now: () => T0 + 1 });
  assert.equal(e.action, 'ended');
  assert.equal(w.db.prepare('SELECT ended_at FROM work_unit').get().ended_at, T0 + 100);
});

test('list: newest first, by Orc, running only; an unknown Orc is refused', () => {
  const w = world();
  startWork(w.db, { kind: 'agent', parentSession: uuid(1), agentId: 'l1', workType: 'build', at: T0 + 1 });
  startWork(w.db, { kind: 'agent', parentSession: uuid(1), agentId: 'l2', workType: 'review', at: T0 + 2, task: 'T-0001' });
  startWork(w.db, { kind: 'agent', parentSession: uuid(70), agentId: 'l3', workType: 'other', at: T0 + 3 }); // parent with no Orc
  endWork(w.db, { parentSession: uuid(1), agentId: 'l1', outcome: 'done', at: T0 + 4 });
  assert.deepEqual(listWork(w.db).map((r) => r.agent_id), ['l3', 'l2', 'l1']);
  assert.deepEqual(listWork(w.db, { orc: 'F' }).map((r) => r.agent_id), ['l2', 'l1']);
  assert.deepEqual(listWork(w.db, { orc: 'decisions-page' }).map((r) => r.agent_id), ['l2', 'l1']);
  assert.deepEqual(listWork(w.db, { running: true }).map((r) => r.agent_id), ['l3', 'l2']);
  assert.deepEqual(listWork(w.db, { orc: 'F', running: true }).map((r) => r.agent_id), ['l2']);
  assert.throws(() => listWork(w.db, { orc: 'Z' }), /no Orc is called Z/);
  const row = listWork(w.db, { orc: 'F', running: true })[0];
  assert.equal(row.task, 'T-0001');
  assert.equal(row.orc, 'F');
});

// ---------------------------------------------------------------------------------------------------------
// the command line

function run(env, ...argv) {
  const out = [];
  const err = [];
  const code = workMain(argv, env, (s) => out.push(s), (s) => err.push(s));
  return { code, out, err };
}

test('work-cli: start, repeat, end, repeat, list through main, with the exit codes', () => {
  const w = world();
  const env = { HORDE_HOME: w.dir };
  const a = ['--kind', 'agent', '--parent-session', uuid(1), '--agent-id', 'cli-1', '--agent-type', 'general-purpose', '--work-type', 'research', '--task', 'T-0001'];
  const s = run(env, 'start', ...a);
  assert.equal(s.code, 0);
  assert.match(s.out[0], /^started agent [0-9A-Z]{26}$/);
  const s2 = run(env, 'start', ...a);
  assert.equal(s2.code, 0);
  assert.match(s2.out[0], /^already started agent [0-9A-Z]{26}$/);
  const e = run(env, 'end', '--parent-session', uuid(1), '--agent-id', 'cli-1', '--outcome', 'done');
  assert.equal(e.code, 0);
  assert.match(e.out[0], /^ended [0-9A-Z]{26} as done$/);
  assert.match(run(env, 'end', '--parent-session', uuid(1), '--agent-id', 'cli-1', '--outcome', 'done').out[0], /^already ended /);
  const bad = run(env, 'end', '--parent-session', uuid(1), '--agent-id', 'cli-1', '--outcome', 'failed');
  assert.equal(bad.code, 1);
  assert.match(bad.err[0], /^refused: already ended as done/);
  assert.equal(bad.err.length, 1);
  const l = run(env, 'list');
  assert.equal(l.code, 0);
  assert.match(l.out[0], /^2026-\d\d-\d\dT[\d:.]+Z agent done F T-0001 research cli-1 [0-9A-Z]{26}$/);
  const j = run(env, 'list', '--json');
  const parsed = JSON.parse(j.out[0]);
  assert.equal(parsed.units.length, 1);
  assert.equal(parsed.units[0].agent_id, 'cli-1');
  assert.match(parsed.units[0].started, /^20\d\d-/);
  const none = run(env, 'list', '--running');
  assert.equal(none.code, 0);
  assert.equal(none.out[0], 'no work units');
  assert.equal(run(env, 'list', '--orc', 'Z').code, 1);
  assert.equal(run(env, 'list', '--orc', 'F', '--json').code, 0);
});

test('work-cli: a warg by its session, the time as ISO or milliseconds, a task the ledger lacks warned', () => {
  const w = world();
  const env = { HORDE_HOME: w.dir };
  const s = run(env, 'start', '--kind', 'warg', '--parent-session', uuid(1), '--session', uuid(2), '--work-type', 'build', '--task', 'T-0555', '--at', '2026-10-21T09:00:00Z');
  assert.equal(s.code, 0);
  assert.equal(s.out.length, 2);
  assert.match(s.out[0], /^warning: task T-0555 /);
  assert.equal(w.db.prepare('SELECT started_at FROM work_unit').get().started_at, Date.UTC(2026, 9, 21, 9, 0, 0));
  assert.equal(run(env, 'end', '--session', uuid(2), '--outcome', 'done', '--at', String(Date.UTC(2026, 9, 21, 9, 30, 0))).code, 0);
  assert.equal(w.db.prepare('SELECT ended_at FROM work_unit').get().ended_at, Date.UTC(2026, 9, 21, 9, 30, 0));
  const badAt = run(env, 'start', '--kind', 'agent', '--parent-session', uuid(1), '--agent-id', 'at1', '--work-type', 'build', '--at', 'yesterday');
  assert.equal(badAt.code, 1);
  assert.match(badAt.err[0], /--at must be UTC milliseconds/);
  assert.equal(w.db.prepare("SELECT count(*) AS n FROM work_unit WHERE agent_id = 'at1'").get().n, 0);
});

test('work-cli: refusals are one ASCII line and exit 1; no home is exit 2; flags are strict', () => {
  const w = world();
  const env = { HORDE_HOME: w.dir };
  assert.equal(run({}, 'list').code, 2);
  assert.equal(run({ HORDE_HOME: 'relative/dir' }, 'list').code, 2);
  assert.equal(run(env).code, 1);
  assert.equal(run(env, 'nap').code, 1);
  for (const [argv, re] of [[['start', '--bogus', 'x'], /unknown argument --bogus/], [['start', '--kind'], /needs a value/],
    [['start', '--kind', 'agent', '--kind', 'agent'], /given twice/], [['list', '--agent-id', 'x'], /unknown argument --agent-id/], [['end', 'extra'], /unknown argument extra/],
    [['list', '--caf\u00e9'], /unknown argument --caf\\u00e9/]]) {
    const r = run(env, ...argv);
    assert.equal(r.code, 1, argv.join(' '));
    assert.equal(r.err.length, 1);
    assert.match(r.err[0], re);
    assert.ok(!/[^ -~]/.test(r.err[0]));
  }
  const noOrc = run(env, 'list', '--orc', 'caf\u00e9');
  assert.equal(noOrc.code, 1);
  assert.match(noOrc.err[0], /^refused: no Orc is called caf\\u00e9$/);
  const r = run(env, 'start', '--kind', 'agent', '--parent-session', uuid(1), '--agent-id', 'x1', '--work-type', 'build', '--domain', 'caf\u00e9');
  assert.equal(r.code, 0);
  const listed = run(env, 'list', '--json');
  assert.ok(!/[^\x20-\x7e]/.test(listed.out[0]), 'json output is ASCII');
  assert.equal(JSON.parse(listed.out[0]).units[0].domain, 'caf\u00e9');
  const refusedText = run(env, 'start', '--kind', 'agent', '--parent-session', 'caf\u00e9', '--agent-id', 'x2', '--work-type', 'build');
  assert.equal(refusedText.code, 1);
  assert.ok(!/[^\x20-\x7e]/.test(refusedText.err[0]));
  // a value is the next word whatever it looks like: an agent id may begin with a dash
  assert.equal(run(env, 'start', '--kind', 'agent', '--parent-session', uuid(1), '--agent-id', '--dashy', '--work-type', 'build').code, 0);
  assert.deepEqual(parseFlags('list', ['--running']), { '--running': true });
  // list on a home with no database says so and makes nothing
  const empty = tempDir();
  const l = run({ HORDE_HOME: empty }, 'list');
  assert.equal(l.code, 1);
  assert.match(l.err[0], /run horde db init/);
  assert.equal(fs.existsSync(path.join(empty, 'fleet.db')), false);
});

test('work-cli: a locked database ends in "fleet.db busy" (exit 3) inside a few seconds, and nothing is written', () => {
  const w = world();
  const holder = new DatabaseSync(w.file);
  handles.push(holder);
  holder.exec('PRAGMA busy_timeout = 0');
  holder.exec('BEGIN IMMEDIATE');
  try {
    const t = Date.now();
    const r = run({ HORDE_HOME: w.dir, HORDE_WORK_BUSY_MS: '300' }, 'start', '--kind', 'agent', '--parent-session', uuid(1), '--agent-id', 'busy1', '--work-type', 'build');
    assert.equal(r.code, 3);
    assert.deepEqual(r.err, ['fleet.db busy']);
    assert.ok(Date.now() - t < 2000, 'it waited the 300 ms asked for, not the default');
    const e = run({ HORDE_HOME: w.dir, HORDE_WORK_BUSY_MS: '300' }, 'end', '--session', uuid(2), '--outcome', 'done');
    assert.equal(e.code, 3, 'end is busy too');
  } finally {
    holder.exec('ROLLBACK');
  }
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM work_unit').get().n, 0);
  // and once the lock is gone the same call goes through
  assert.equal(run({ HORDE_HOME: w.dir }, 'start', '--kind', 'agent', '--parent-session', uuid(1), '--agent-id', 'busy1', '--work-type', 'build').code, 0);
});

// ---------------------------------------------------------------------------------------------------------
// the registry importer reads a record's kind into session.rank

function registryOf(records) {
  const dir = tempDir();
  const reg = path.join(dir, 'sessions');
  fs.mkdirSync(reg);
  for (const [sid, rec] of Object.entries(records)) fs.writeFileSync(path.join(reg, sid + '.json'), JSON.stringify({ firstSeen: '2026-10-21T08:00:00Z', lastSeen: '2026-10-21T09:00:00Z', ...rec }));
  return reg;
}
const rankOfSession = (db, n) => db.prepare('SELECT rank FROM session WHERE id = ?').get(uuid(n))?.rank;

test('importer: a record kind (thrall, orc, warg) becomes session.rank; no kind keeps the older rule', () => {
  const w = world();
  const f = (rep, text) => rep.unlinked.filter((u) => u.reason.includes(text));
  const reg = registryOf({
    [uuid(11)]: { kind: 'warg', owner: 'F' },
    [uuid(12)]: { kind: 'warg', role: 'orchestrator' }, // the kind wins over the older words
    [uuid(13)]: { role: 'warg' }, // no kind: today's rule
    [uuid(14)]: { kind: 'orc', label: 'F' }, // F already holds a live seat (uuid 1): the older seat rule still decides
    [uuid(15)]: { kind: 'orc', label: 'Q' }, // names no Orc row
    [uuid(16)]: { kind: 'analyst' }, // not one of the three: reported, the older rule decides
    [uuid(17)]: {}, // nothing at all
  });
  const rep = importFleet(w.db, { registry: reg });
  assert.equal(rankOfSession(w.db, 11), 'warg');
  assert.equal(rankOfSession(w.db, 12), 'warg');
  assert.equal(rankOfSession(w.db, 13), 'warg');
  assert.equal(rankOfSession(w.db, 14), 'unknown');
  assert.equal(rankOfSession(w.db, 15), 'unknown');
  assert.equal(rankOfSession(w.db, 16), 'unknown');
  assert.equal(rankOfSession(w.db, 17), 'unknown');
  assert.equal(f(rep, 'kind is not thrall, orc or warg').length, 1);
  assert.equal(f(rep, 'a second live seat').length, 1);
  assert.deepEqual(findProblems(w.db), []);
});

test('importer: a kind of orc with its Orc, and thrall with the Thrall, take the seat as rank', () => {
  const dir = tempDir();
  const db = openStore(path.join(dir, 'fleet.db'));
  handles.push(db);
  const node = id();
  db.prepare('INSERT INTO node (id, name, is_authority, created_at) VALUES (?, ?, 1, ?)').run(node, 'pc-1', T0);
  db.prepare("INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES (?, 'M', 'thrall', 'Thrall', 'thrall', ?)").run(id(), T0);
  db.prepare("INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES (?, 'N', 'fleet-db', 'N', 'orc', ?)").run(id(), T0);
  const reg = registryOf({ [uuid(21)]: { kind: 'orc', label: 'N' }, [uuid(22)]: { kind: 'thrall', label: 'M' }, [uuid(23)]: { kind: 'warg', owner: 'N' } });
  importFleet(db, { registry: reg });
  assert.equal(rankOfSession(db, 21), 'orc');
  assert.equal(rankOfSession(db, 22), 'thrall');
  assert.equal(rankOfSession(db, 23), 'warg');
  assert.equal(db.prepare('SELECT orc_id IS NOT NULL AS has FROM session WHERE id = ?').get(uuid(23)).has, 1);
});

test('importer: a kind that disagrees with a session already stored is reported and the rank is kept', () => {
  const w = world();
  // uuid(2) is a stored warg; uuid(1) a stored orc; uuid(3) a stored warg that the record agrees with
  const reg = registryOf({ [uuid(2)]: { kind: 'orc', label: 'F' }, [uuid(1)]: { kind: 'orc', label: 'F' }, [uuid(3)]: { kind: 'warg' } });
  const rep = importFleet(w.db, { registry: reg });
  assert.equal(rankOfSession(w.db, 2), 'warg', 'not overwritten');
  assert.equal(rankOfSession(w.db, 1), 'orc');
  assert.equal(rankOfSession(w.db, 3), 'warg');
  const hits = rep.unlinked.filter((u) => u.reason.includes('disagrees with the stored rank'));
  assert.equal(hits.length, 1);
  assert.equal(hits[0].count, 1);
  assert.deepEqual(hits[0].examples, [uuid(2)]);
  assert.match(hits[0].reason, /kind orc disagrees with the stored rank warg \(rank kept\)/);
  // the same import again reports it again and still writes nothing
  const again = importFleet(w.db, { registry: reg });
  assert.equal(again.unlinked.filter((u) => u.reason.includes('disagrees')).length, 1);
  assert.equal(rankOfSession(w.db, 2), 'warg');
});

test('importer: a stub made by work start is upgraded by the record, its units take the Orc, and a second import is silent', () => {
  const w = world();
  const g = id();
  w.db.prepare("INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES (?, 'G', 'g-lane', 'G', 'orc', ?)").run(g, T0);
  startWork(w.db, { kind: 'agent', parentSession: uuid(40), agentId: 'early1', workType: 'build', at: T0 + 1 });
  startWork(w.db, { kind: 'agent', parentSession: uuid(41), agentId: 'early2', workType: 'build', at: T0 + 2 });
  assert.equal(rankOfSession(w.db, 40), 'unknown');
  assert.deepEqual(listWork(w.db, { orc: 'F' }), []);
  const reg = registryOf({ [uuid(40)]: { kind: 'warg', owner: 'F' }, [uuid(41)]: { kind: 'orc', label: 'G' } });
  const rep = importFleet(w.db, { registry: reg });
  assert.equal(rep.unlinked.filter((u) => u.reason.includes('disagrees')).length, 0, 'a stub is not a disagreement');
  assert.equal(rankOfSession(w.db, 40), 'warg');
  assert.equal(rankOfSession(w.db, 41), 'orc');
  assert.equal(w.db.prepare('SELECT orc_id FROM session WHERE id = ?').get(uuid(40)).orc_id, w.f);
  assert.deepEqual(listWork(w.db, { orc: 'F' }).map((r) => r.agent_id), ['early1']);
  assert.deepEqual(listWork(w.db, { orc: 'G' }).map((r) => r.agent_id), ['early2']);
  assert.deepEqual(findProblems(w.db), []);
  const again = importFleet(w.db, { registry: reg });
  assert.equal(again.unlinked.filter((u) => u.reason.includes('disagrees')).length, 0, 'the second import is silent');
  // a row with a real rank that disagrees is still reported and kept
  const third = importFleet(w.db, { registry: registryOf({ [uuid(40)]: { kind: 'orc', label: 'F' } }) });
  assert.equal(third.unlinked.filter((u) => u.reason.includes('kind orc disagrees with the stored rank warg')).length, 1);
  assert.equal(rankOfSession(w.db, 40), 'warg');
});

test('importer: a stub whose record names no usable rank stays a stub and its units keep no Orc', () => {
  const w = world();
  startWork(w.db, { kind: 'agent', parentSession: uuid(42), agentId: 'early3', workType: 'build' });
  importFleet(w.db, { registry: registryOf({ [uuid(42)]: {} }) });
  assert.equal(rankOfSession(w.db, 42), 'unknown');
  assert.equal(w.db.prepare('SELECT orc_id FROM work_unit').get().orc_id, null);
});

test('a repeat start on a no_task unit fills the task when fleet.db knows it, and says so', () => {
  const w = world();
  const a = { kind: 'agent', parentSession: uuid(1), agentId: 'fill1', workType: 'build' };
  startWork(w.db, a);
  const unknown = startWork(w.db, { ...a, task: 'T-0888' });
  assert.equal(unknown.action, 'already');
  assert.equal(unknown.filled, false);
  assert.equal(unknown.warnings.length, 1);
  assert.equal(w.db.prepare('SELECT task_flag FROM work_unit').get().task_flag, 'no_task');
  const r = startWork(w.db, { ...a, task: 'T-0001' });
  assert.deepEqual({ action: r.action, filled: r.filled, note: r.note }, { action: 'already', filled: true, note: null });
  assert.deepEqual({ ...w.db.prepare('SELECT task_id, task_flag FROM work_unit').get() }, { task_id: w.task, task_flag: null });
  const cli = run({ HORDE_HOME: w.dir }, 'start', '--kind', 'agent', '--parent-session', uuid(1), '--agent-id', 'fill2', '--work-type', 'build');
  assert.equal(cli.code, 0);
  const cli2 = run({ HORDE_HOME: w.dir }, 'start', '--kind', 'agent', '--parent-session', uuid(1), '--agent-id', 'fill2', '--work-type', 'build', '--task', 'T-0001');
  assert.match(cli2.out[0], /^already started; task filled agent [0-9A-Z]{26}$/);
});

test('any other repeat with different fields keeps the first row and names the fields that differ', () => {
  const w = world();
  const a = { kind: 'agent', parentSession: uuid(1), agentId: 'diff1', agentType: 'general-purpose', workType: 'build', domain: 'one', model: 'sonnet', task: 'T-0001' };
  startWork(w.db, a);
  const same = startWork(w.db, a);
  assert.equal(same.note, null);
  const r = startWork(w.db, { ...a, workType: 'review', domain: 'two', model: 'opus', agentType: 'Explore', task: 'T-0777' });
  assert.equal(r.action, 'already');
  assert.equal(r.filled, false);
  assert.equal(r.note, 'note: the repeat differs from the first row in task, work type, domain, model, agent type; the first row is kept');
  const row = w.db.prepare('SELECT work_type, domain, model, agent_type, task_id FROM work_unit').get();
  assert.deepEqual({ ...row }, { work_type: 'build', domain: 'one', model: 'sonnet', agent_type: 'general-purpose', task_id: w.task });
  assert.equal(startWork(w.db, { kind: 'agent', parentSession: uuid(1), agentId: 'diff1', workType: 'build' }).note, null, 'omitted fields are not differences');
  const cli = run({ HORDE_HOME: w.dir }, 'start', '--kind', 'agent', '--parent-session', uuid(1), '--agent-id', 'diff1', '--work-type', 'verify');
  assert.equal(cli.code, 0);
  assert.match(cli.out[0], /^already started agent /);
  assert.equal(cli.out[1], 'note: the repeat differs from the first row in work type; the first row is kept');
});
