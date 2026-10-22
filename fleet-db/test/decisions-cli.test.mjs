// `horde decisions publish` and `published`, node side (fleet-db/decisions-cli.mjs): the Orc is found from the
// proven who, a question number becomes a question id, the list replaces the live one and the old one stays,
// the same list twice writes nothing, and the lists read back from the views. Databases of their own under
// the temp folder; nothing real is read or written.
import './own-profile.mjs';
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { openStore } from '../store.mjs';
import { ulid } from '../ids.mjs';
import { publishFromInput, readPublished, main } from '../decisions-cli.mjs';

const T0 = Date.UTC(2026, 9, 20, 12, 0, 0);
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

function world() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-db-dc-'));
  dirs.push(dir);
  const file = path.join(dir, 'fleet.db');
  const db = openStore(file);
  handles.push(db);
  const w = { db, dir, file, node: id(), m: id(), f: id(), k: id(), task: id(), q7: id(), q9: id(), sf: uuid(1) };
  db.prepare('INSERT INTO node (id, name, is_authority, created_at) VALUES (?, ?, 1, ?)').run(w.node, 'pc-1', T0);
  const orc = db.prepare('INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES (?, ?, ?, ?, ?, ?)');
  orc.run(w.m, 'M', 'thrall', 'Thrall', 'thrall', T0);
  orc.run(w.f, 'F', 'decisions-page', 'Decisions page', 'orc', T0);
  orc.run(w.k, 'K', 'sleeping-sessions', 'Sleeping sessions', 'orc', T0);
  db.prepare("INSERT INTO task (id, key, title, source, created_at) VALUES (?, 'T-0001', 'a task', 'founder', ?)").run(w.task, T0);
  const q = db.prepare("INSERT INTO question (id, number, task_id, kind, title, asked_at) VALUES (?, ?, ?, 'yes-no', 'ok?', ?)");
  q.run(w.q7, 7, w.task, T0);
  q.run(w.q9, 9, w.task, T0);
  db.prepare('INSERT INTO session (id, node_id, orc_id, rank, first_seen, last_seen) VALUES (?, ?, ?, ?, ?, ?)').run(w.sf, w.node, w.f, 'orc', T0, T0);
  return w;
}

const input = (who, items, sessionId = null) => ({ who, sessionId, items });
const lineA = { questionNumber: 7, text: 'Ship the page?', recommendation: 'yes', importance: 'high', blocks: 'all' };
const lineB = { questionNumber: null, text: 'Pick a colour' };

test('a list is published for the proven Orc, in order, with the question number turned into its id', () => {
  const w = world();
  const r = publishFromInput(w.db, input({ letter: 'F' }, [lineA, lineB], w.sf), T0);
  assert.equal(r.unchanged, false);
  assert.equal(r.count, 2);
  const live = w.db.prepare('SELECT orc_id, by_session_id, item_count FROM decisions_live').all().map((x) => ({ ...x }));
  assert.deepEqual(live, [{ orc_id: w.f, by_session_id: w.sf, item_count: 2 }]);
  const lines = w.db.prepare('SELECT position, question_id, text, importance, blocks FROM decisions_live_item ORDER BY position').all().map((x) => ({ ...x }));
  assert.deepEqual(lines, [
    { position: 1, question_id: w.q7, text: 'Ship the page?', importance: 'high', blocks: 'all' },
    { position: 2, question_id: null, text: 'Pick a colour', importance: null, blocks: null },
  ]);
});

test('the same list again is unchanged and writes no snapshot', () => {
  const w = world();
  const a = publishFromInput(w.db, input({ letter: 'F' }, [lineA, lineB]), T0);
  const b = publishFromInput(w.db, input({ letter: 'F' }, [lineA, lineB]), T0 + 5);
  assert.equal(b.unchanged, true);
  assert.equal(b.id, a.id);
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM decisions_snapshot').get().n, 1);
});

test('a changed list is a new snapshot and the old one stays as history with its time', () => {
  const w = world();
  const a = publishFromInput(w.db, input({ letter: 'F' }, [lineA]), T0);
  const b = publishFromInput(w.db, input({ letter: 'F' }, [lineA, lineB]), T0 + 10);
  assert.notEqual(a.id, b.id);
  const all = w.db.prepare('SELECT id, published_at, item_count FROM decisions_snapshot ORDER BY published_at').all().map((x) => ({ ...x }));
  assert.deepEqual(all, [{ id: a.id, published_at: T0, item_count: 1 }, { id: b.id, published_at: T0 + 10, item_count: 2 }]);
  assert.equal(w.db.prepare('SELECT id FROM decisions_live').get().id, b.id);
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM decisions_snapshot_item WHERE snapshot_id = ?').get(a.id).n, 1);
});

test('another Orc\'s list is its own: publishing F does not touch K', () => {
  const w = world();
  publishFromInput(w.db, input({ letter: 'F' }, [lineA]), T0);
  publishFromInput(w.db, input({ letter: 'K' }, [lineB]), T0 + 1);
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM decisions_live').get().n, 2);
});

test('the Thrall publishes as the standing Thrall', () => {
  const w = world();
  publishFromInput(w.db, input({ thrall: true }, [lineB]), T0);
  assert.equal(w.db.prepare('SELECT orc_id FROM decisions_live').get().orc_id, w.m);
});

test('an empty list is valid, and empty after a full one is a new snapshot', () => {
  const w = world();
  const a = publishFromInput(w.db, input({ letter: 'F' }, []), T0);
  assert.equal(a.count, 0);
  assert.equal(publishFromInput(w.db, input({ letter: 'F' }, []), T0 + 1).unchanged, true);
  publishFromInput(w.db, input({ letter: 'F' }, [lineB]), T0 + 2);
  const c = publishFromInput(w.db, input({ letter: 'F' }, []), T0 + 3);
  assert.equal(c.unchanged, false);
  assert.equal(w.db.prepare('SELECT item_count FROM decisions_live').get().item_count, 0);
});

test('an unknown question number is refused with the number named, and nothing is written', () => {
  const w = world();
  assert.throws(() => publishFromInput(w.db, input({ letter: 'F' }, [lineB, { questionNumber: 4242, text: 'x' }]), T0), /item 2 names question 4242, which is not in the decisions store/);
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM decisions_snapshot').get().n, 0);
});

test('a misspelt field is refused by name', () => {
  const w = world();
  assert.throws(() => publishFromInput(w.db, input({ letter: 'F' }, [{ txet: 'x' }]), T0), /item 1 has no field txet/);
  assert.throws(() => publishFromInput(w.db, { who: { letter: 'F' }, itemz: [] }, T0), /the input has no field itemz/);
});

test('a value that is not text is refused', () => {
  const w = world();
  assert.throws(() => publishFromInput(w.db, input({ letter: 'F' }, [{ text: 5 }]), T0), /item 1 text must be text/);
});

test('an Orc fleet.db does not know, or has retired, is refused in words', () => {
  const w = world();
  assert.throws(() => publishFromInput(w.db, input({ letter: 'Z' }, []), T0), /no row for Orc Z/);
  w.db.prepare("UPDATE orc SET retired_at = 1, retired_reason = 'hand' WHERE letter = 'K'").run();
  assert.throws(() => publishFromInput(w.db, input({ letter: 'K' }, []), T0), /Orc K is retired/);
});

test('a session fleet.db has not recorded is stored as no session', () => {
  const w = world();
  publishFromInput(w.db, input({ letter: 'F' }, [lineB], uuid(99)), T0);
  assert.equal(w.db.prepare('SELECT by_session_id FROM decisions_live').get().by_session_id, null);
});

test('a list older than the live one is refused in words', () => {
  const w = world();
  publishFromInput(w.db, input({ letter: 'F' }, [lineA]), T0 + 10);
  assert.throws(() => publishFromInput(w.db, input({ letter: 'F' }, [lineB]), T0), /already has a list published at or after/);
});

test('published --json: confirmedAt beside publishedAt, every old field unchanged, later after an equal publish', () => {
  const w = world();
  publishFromInput(w.db, input({ letter: 'F' }, [lineA]), T0);
  assert.deepEqual(Object.keys(readPublished(w.db)[0]), ['orc', 'snapshot', 'publishedAt', 'confirmedAt', 'count', 'items', 'rank']);
  assert.equal(readPublished(w.db)[0].rank, 'orc');
  assert.equal(readPublished(w.db)[0].confirmedAt, new Date(T0).toISOString());
  publishFromInput(w.db, input({ letter: 'F' }, [lineA]), T0 + 60000);
  const l = readPublished(w.db)[0];
  assert.equal(l.publishedAt, new Date(T0).toISOString());
  assert.equal(l.confirmedAt, new Date(T0 + 60000).toISOString());
  assert.deepEqual(Object.keys(l.items[0]), ['position', 'questionNumber', 'text', 'recommendation', 'importance', 'blocks']);
});

test('published carries each Orc rank, so the phone tells the Thrall from an Orc (T-0328)', () => {
  const w = world();
  publishFromInput(w.db, input({ thrall: true }, [lineB]), T0);
  publishFromInput(w.db, input({ letter: 'F' }, [lineA]), T0 + 1);
  const all = readPublished(w.db);
  assert.deepEqual(all.map((l) => [l.orc, l.rank]).sort(), [['F', 'orc'], ['M', 'thrall']]);
  assert.deepEqual(readPublished(w.db, 'M').map((l) => l.rank), ['thrall']);
  assert.ok(JSON.parse(JSON.stringify(all)).every((l) => l.rank === 'thrall' || l.rank === 'orc'));
});

test('the live lists read back from the views, with question numbers, one Orc or all', () => {
  const w = world();
  publishFromInput(w.db, input({ letter: 'F' }, [lineA, lineB]), T0);
  publishFromInput(w.db, input({ letter: 'K' }, []), T0 + 1);
  const all = readPublished(w.db);
  assert.deepEqual(all.map((l) => [l.orc, l.count]), [['F', 2], ['K', 0]]);
  assert.deepEqual(all[0].items.map((i) => [i.position, i.questionNumber, i.text]), [[1, 7, 'Ship the page?'], [2, null, 'Pick a colour']]);
  assert.deepEqual(readPublished(w.db, 'K').map((l) => l.orc), ['K']);
  assert.deepEqual(readPublished(w.db, 'Q'), []);
});

test('main: publish prints one line, publishes again as unchanged, and published reads it back', () => {
  const w = world();
  const inFile = path.join(w.dir, 'in.json');
  fs.writeFileSync(inFile, JSON.stringify(input({ letter: 'F' }, [lineA])));
  const run = (argv) => {
    const out = [];
    const err = [];
    const code = main(argv, { HORDE_HOME: w.dir }, (s) => out.push(s), (s) => err.push(s));
    return { code, out, err };
  };
  const a = run(['publish', inFile]);
  assert.equal(a.code, 0);
  assert.match(a.out[0], /^published 1 item \(snapshot [0-9A-Z]{26}\)$/);
  const before = Date.now();
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 20); // the second publish is a later millisecond
  const b = run(['publish', inFile]);
  assert.match(b.out[0], /^unchanged, confirmed \d{4}-\d\d-\d\dT[\d:.]+Z \(snapshot [0-9A-Z]{26}\)$/);
  const c = run(['published', '--orc', 'F', '--json']);
  assert.equal(c.code, 0);
  const jl = JSON.parse(c.out[0]).lists[0];
  assert.ok(Date.parse(jl.confirmedAt) > Date.parse(jl.publishedAt), 'confirmed is later than published after an equal publish');
  assert.ok(Date.parse(jl.confirmedAt) >= before + 15);
  assert.equal(b.out[0].split(' ')[2], jl.confirmedAt, 'the unchanged line names the confirm time');
  assert.equal(JSON.parse(c.out[0]).lists[0].items[0].questionNumber, 7);
  const d = run(['published']);
  assert.match(d.out[0], /^F: 1 item, published \S+, confirmed \S+ \(snapshot /);
  assert.ok(d.out[0].includes('published ' + jl.publishedAt + ', confirmed ' + jl.confirmedAt + ' '));
  fs.writeFileSync(inFile, JSON.stringify(input({ letter: 'F' }, [{ questionNumber: 4242, text: 'x' }])));
  const e = run(['publish', inFile]);
  assert.equal(e.code, 1);
  assert.match(e.err[0], /^refused: item 1 names question 4242/);
});

test('main: published before init says to run init, and no home is exit 2', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-db-dc-'));
  dirs.push(dir);
  const err = [];
  assert.equal(main(['published'], { HORDE_HOME: dir }, () => {}, (s) => err.push(s)), 1);
  assert.match(err[0], /run horde db init/);
  assert.equal(fs.existsSync(path.join(dir, 'fleet.db')), false);
  assert.equal(main(['published'], {}, () => {}, () => {}), 2);
});
