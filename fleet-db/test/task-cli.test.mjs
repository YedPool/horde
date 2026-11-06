// horde task list (fleet-db/task-cli.mjs): every live task is shown, and only reading happens. Temp homes only.
import './own-profile.mjs';
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { openStore, inWrite } from '../store.mjs';
import { SCHEMA_VERSION } from '../schema.mjs';
import { appendHistory, newId } from '../write.mjs';
import { main } from '../task-cli.mjs';

const dirs = [];
const handles = [];
after(() => {
  for (const db of handles) { try { db.close(); } catch { /* closed by the test */ } }
  for (const d of dirs) fs.rmSync(d, { recursive: true, force: true });
});

const T0 = 1760000000000;

function home({ make = true } = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-db-tasklist-'));
  dirs.push(dir);
  const file = path.join(dir, 'fleet.db');
  const w = { dir, file, env: { HORDE_HOME: dir, HORDE_TASK_BUSY_MS: '100' }, keyNo: 1 };
  if (!make) return w;
  w.db = openStore(file);
  handles.push(w.db);
  w.f = newId();
  w.k = newId();
  const orc = w.db.prepare("INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES (?, ?, ?, ?, 'orc', ?)");
  orc.run(w.f, 'F', 'lane-f', 'F', T0);
  orc.run(w.k, 'K', 'lane-k', 'K', T0);
  return w;
}

function task(w, { owner = null, prio = 2, parent = null, due = null, title = 'a task', state = null } = {}) {
  const id = newId();
  const key = 'T-' + String(w.keyNo++).padStart(4, '0');
  inWrite(w.db, () => {
    w.db.prepare("INSERT INTO task (id, key, title, source, parent_id, due_at, created_at) VALUES (?, ?, ?, 'orc', ?, ?, ?)").run(id, key, title, parent, due, T0);
    // Only an imported line may open a task with no owner: the ledger names lanes that are no Orc's folder.
    appendHistory(w.db, 'task_event', { task_id: id, at: T0, kind: 'opened', prio, to_orc_id: owner, backfill: owner === null ? 1 : 0 });
    if (state) appendHistory(w.db, 'task_event', { task_id: id, at: T0 + 1, kind: state, ...(state === 'waiting' ? { on_kind: 'other', on_text: 'x' } : {}) });
  });
  return { id, key };
}

function run(w, ...argv) {
  if (w.db) { w.db.close(); w.db = null; }
  const out = [];
  const err = [];
  const code = main(argv, w.env, (s) => out.push(s), (s) => err.push(s));
  return { code, out, err };
}

test('each Orc has a numbered list, subtasks indented under their parent, a last line of counts', () => {
  const w = home();
  const a = task(w, { owner: w.f, prio: 1, title: 'first' });
  const s = task(w, { owner: w.f, parent: a.id, state: 'started', title: 'sub' });
  const b = task(w, { owner: w.k, prio: 3, state: 'waiting', title: 'other' });
  const r = run(w, 'list');
  assert.equal(r.code, 0);
  assert.deepEqual(r.out, [
    'F:',
    `1 ${a.key} opened p1 | first`,
    `  1.1 ${s.key} started p2 | sub`,
    'K:',
    `1 ${b.key} waiting p3 | other`,
    '3 open, and 0 done, not yet verified, not listed',
  ]);
});

test('a task with no Orc comes out in a list of its own, last', () => {
  const w = home();
  const a = task(w, { title: 'nobody' });
  const b = task(w, { owner: w.k, title: 'somebody' });
  const r = run(w, 'list');
  assert.deepEqual(r.out, ['K:', `1 ${b.key} opened p2 | somebody`, 'no Orc:', `1 ${a.key} opened p2 | nobody`, '2 open, and 0 done, not yet verified, not listed']);
});

test('a live task under a closed parent is listed, and the closed parent is not', () => {
  const w = home();
  const a = task(w, { owner: w.f, prio: 1, title: 'closed', state: 'verified' });
  const s = task(w, { owner: w.f, parent: a.id, prio: 1, title: 'still open' });
  const r = run(w, 'list');
  assert.deepEqual(r.out, ['F:', `1 ${s.key} opened p1 | still open`, '1 open, and 0 done, not yet verified, not listed']);
});

test('-orc shows that Orc\'s list and what it owns inside another list, and leaves the rest out', () => {
  const w = home();
  const a = task(w, { owner: w.k, prio: 1, title: 'parent' });
  const s = task(w, { owner: w.f, parent: a.id, title: 'mine, under K' });
  const f = task(w, { owner: w.f, title: 'mine' });
  const other = task(w, { owner: w.k, prio: 3, title: 'not mine' });
  const r = run(w, 'list', '--orc', 'F');
  assert.deepEqual(r.out, ['F:', `1 ${f.key} opened p2 | mine`, 'K:', `  1.1 ${s.key} opened p2 owner=F | mine, under K`, '2 open, and 0 done, not yet verified, not listed']);
  assert.ok(!r.out.join('\n').includes(a.key) && !r.out.join('\n').includes(other.key));
});

test('-orc takes a lane folder as well as a letter, and refuses a name it does not know', () => {
  const w = home();
  task(w, { owner: w.f, title: 'mine' });
  const r = run(w, 'list', '--orc', 'lane-f');
  assert.equal(r.code, 0);
  assert.equal(r.out[0], 'F:');
  const bad = run(w, 'list', '--orc', 'nobody');
  assert.equal(bad.code, 1);
  assert.deepEqual(bad.err, ['refused: no Orc is called nobody']);
  assert.deepEqual(bad.out, []);
});

test('a task in a list that is not its owner\'s says whose it is, a task with no owner under a parent too', () => {
  const w = home();
  const a = task(w, { owner: w.f, prio: 1, title: 'parent' });
  const s = task(w, { owner: w.k, parent: a.id, title: 'K works this' });
  const n = task(w, { parent: a.id, title: 'nobody works this' });
  const r = run(w, 'list');
  assert.ok(r.out.includes(`  1.1 ${s.key} opened p2 owner=K | K works this`), r.out.join('\n'));
  assert.ok(r.out.includes(`  1.2 ${n.key} opened p2 owner=no-Orc | nobody works this`), r.out.join('\n'));
});

test('-orc keeps a subtask another Orc owns inside this Orc\'s list, so the numbers have no hole', () => {
  const w = home();
  const a = task(w, { owner: w.f, prio: 1, title: 'parent' });
  const s = task(w, { owner: w.k, parent: a.id, title: 'K works this' });
  const r = run(w, 'list', '--orc', 'F');
  assert.deepEqual(r.out, ['F:', `1 ${a.key} opened p1 | parent`, `  1.1 ${s.key} opened p2 owner=K | K works this`, '2 open, and 0 done, not yet verified, not listed']);
});

test('done tasks are counted, per Orc with -orc, and take no number', () => {
  const w = home();
  task(w, { owner: w.f, title: 'finished', state: 'done' });
  task(w, { owner: w.f, title: 'finished too', state: 'done' });
  task(w, { owner: w.k, title: 'K finished', state: 'done' });
  task(w, { owner: w.f, title: 'closed for good', state: 'verified' });
  assert.deepEqual(run(w, 'list').out, ['0 open, and 3 done, not yet verified, not listed']);
  assert.deepEqual(run(w, 'list', '--orc', 'F').out, ['0 open, and 2 done, not yet verified, not listed']);
});

test('a due time and a title that is not ASCII print safely', () => {
  const w = home();
  const a = task(w, { owner: w.f, due: Date.UTC(2026, 10, 6, 9), title: 'caf\u00e9' });
  const r = run(w, 'list');
  assert.equal(r.out[1], `1 ${a.key} opened p2 due=2026-11-06T09:00:00.000Z | caf\\u00e9`);
});

test('json is one line of data, the same tasks, ASCII', () => {
  const w = home();
  const a = task(w, { owner: w.f, prio: 1, due: Date.UTC(2026, 10, 6, 9), title: 'caf\u00e9' });
  const b = task(w, { owner: w.f, prio: 2 });
  task(w, { owner: w.f, state: 'done' });
  const r = run(w, 'list', '--json');
  assert.equal(r.out.length, 1);
  assert.ok(/^[\x20-\x7E]+$/.test(r.out[0]));
  const d = JSON.parse(r.out[0]);
  assert.equal(d.done_not_verified, 1);
  assert.deepEqual(d.tasks.map((t) => [t.list, t.path, t.task, t.state, t.prio, t.owner, t.depth]), [['F', '1', a.key, 'opened', 1, 'F', 0], ['F', '2', b.key, 'opened', 2, 'F', 0]]);
  assert.equal(d.tasks[0].due, '2026-11-06T09:00:00.000Z');
  assert.equal(d.tasks[1].due, null);
  assert.equal(d.tasks[0].title, 'caf\u00e9');
});

test('it never writes: a database at an older version is refused and left at that version', () => {
  const w = home();
  w.db.exec('PRAGMA user_version = 8');
  const r = run(w, 'list');
  assert.equal(r.code, 1);
  assert.match(r.err[0], /^fleet\.db: .*run horde db init/);
  const raw = new DatabaseSync(w.file, { readOnly: true });
  assert.equal(raw.prepare('PRAGMA user_version').get().user_version, 8);
  raw.close();
});

test('no fleet.db is exit 4, and it does not make one', () => {
  const w = home({ make: false });
  const r = run(w, 'list');
  assert.equal(r.code, 4);
  assert.deepEqual(r.err, ['fleet.db does not exist yet (run horde db init)']);
  assert.equal(fs.existsSync(w.file), false);
});

test('no home is exit 2', () => {
  const w = home({ make: false });
  w.env = {};
  const r = run(w, 'list');
  assert.equal(r.code, 2);
  assert.match(r.err[0], /^fleet\.db: /);
});

test('a database in the middle of a write can still be read', () => {
  const w = home();
  const a = task(w, { owner: w.f, title: 'visible' });
  w.db.exec('BEGIN IMMEDIATE');
  const out = [];
  const code = main(['list'], w.env, (s) => out.push(s), () => {});
  w.db.exec('COMMIT');
  w.db.close();
  w.db = null;
  assert.equal(code, 0);
  assert.equal(out[1], `1 ${a.key} opened p2 | visible`);
});

test('a database locked against readers is exit 3 and the words fleet.db busy', () => {
  const w = home();
  task(w, { owner: w.f });
  w.db.exec('PRAGMA locking_mode = EXCLUSIVE');
  w.db.exec('BEGIN EXCLUSIVE');
  w.db.exec("UPDATE task SET title = 'held'");
  const out = [];
  const err = [];
  const code = main(['list'], w.env, (s) => out.push(s), (s) => err.push(s));
  w.db.exec('COMMIT');
  assert.equal(code, 3);
  assert.deepEqual(err, ['fleet.db busy']);
  assert.deepEqual(out, []);
});

test('bad arguments are refused, nothing printed to the output', () => {
  const w = home();
  w.db.close();
  w.db = null;
  for (const [args, msg] of [
    [[], /^usage:/],
    [['add'], /^usage:/],
    [['list', '--nope'], /^refused: list: unknown argument --nope$/],
    [['list', '--orc'], /^refused: list: --orc needs a value$/],
    [['list', '--json', '--json'], /^refused: list: --json given twice$/],
    [['list', '--orc', 'F', '--orc', 'K'], /^refused: list: --orc given twice$/],
  ]) {
    const r = run(w, ...args);
    assert.equal(r.code, 1, args.join(' '));
    assert.match(r.err[0], msg);
    assert.deepEqual(r.out, []);
  }
});

test('the schema this was written for is the current one', () => {
  assert.equal(SCHEMA_VERSION, 9);
});
