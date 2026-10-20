// Migration 2 (what the Progress and Decisions pages show), the write layer (write.mjs) and the horde db
// verbs (cli.mjs), each attacked: a row the rule exists to stop is written and must be refused, and the
// row the rule must still allow is written too. Databases of their own under the temp folder; nothing
// real is read or written.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { openStore, inWrite } from '../store.mjs';
import { MIGRATIONS, SCHEMA_VERSION } from '../schema.mjs';
import { ulid, sha256 } from '../ids.mjs';
import { makeMinter, appendHistory, publishDecisions, decisionsHash, HASHED_HISTORY } from '../write.mjs';
import { main } from '../cli.mjs';

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

function tempDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-db-w-'));
  dirs.push(dir); // before anything can throw: a mutant must not leak its folder
  return dir;
}

function fresh() {
  const file = path.join(tempDir(), 'fleet.db');
  const db = openStore(file);
  handles.push(db);
  return { db, file };
}

// One PC, the Thrall, Orcs F and K, a task, question 1 on it, and a session for each Orc.
function world() {
  const { db, file } = fresh();
  const w = { db, file, node: id(), m: id(), f: id(), k: id(), task: id(), q: id(), sf: uuid(1), sk: uuid(2) };
  db.prepare('INSERT INTO node (id, name, is_authority, created_at) VALUES (?, ?, 1, ?)').run(w.node, 'pc-1', T0);
  const orc = db.prepare('INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES (?, ?, ?, ?, ?, ?)');
  orc.run(w.m, 'M', 'thrall', 'Thrall', 'thrall', T0);
  orc.run(w.f, 'F', 'decisions-page', 'Decisions page', 'orc', T0);
  orc.run(w.k, 'K', 'sleeping-sessions', 'Sleeping sessions', 'orc', T0);
  db.prepare("INSERT INTO task (id, key, title, source, created_at) VALUES (?, 'T-0001', 'a task', 'founder', ?)").run(w.task, T0);
  db.prepare("INSERT INTO question (id, number, task_id, kind, title, asked_at) VALUES (?, 1, ?, 'yes-no', 'ok?', ?)").run(w.q, w.task, T0);
  const s = db.prepare('INSERT INTO session (id, node_id, orc_id, rank, first_seen, last_seen) VALUES (?, ?, ?, ?, ?, ?)');
  s.run(w.sf, w.node, w.f, 'orc', T0, T0);
  s.run(w.sk, w.node, w.k, 'orc', T0, T0);
  return w;
}

const snapshot = (db, row) => {
  const r = { id: id(), published_at: T0 + seq++, item_count: 0, sha256: sha256('x' + seq), by_session_id: null, ...row };
  db.prepare('INSERT INTO decisions_snapshot (id, orc_id, published_at, by_session_id, item_count, sha256) VALUES (?, ?, ?, ?, ?, ?)')
    .run(r.id, r.orc_id, r.published_at, r.by_session_id, r.item_count, r.sha256);
  return r;
};
const item = (db, snapshotId, position, text = 'line') =>
  db.prepare('INSERT INTO decisions_snapshot_item (snapshot_id, position, text) VALUES (?, ?, ?)').run(snapshotId, position, text);

// --- migration 2 -------------------------------------------------------------------------------------

test('a version 1 file is brought to the current version and its lots are not kept visible', () => {
  const file = path.join(tempDir(), 'fleet.db');
  const raw = new DatabaseSync(file);
  raw.exec(MIGRATIONS[0]);
  raw.exec('PRAGMA user_version = 1');
  const lot = id();
  raw.prepare("INSERT INTO parking_lot (id, created_at, reason) VALUES (?, 1, 'night')").run(lot);
  raw.close();
  const db = openStore(file);
  handles.push(db);
  assert.equal(SCHEMA_VERSION, 2);
  assert.equal(db.prepare('PRAGMA user_version').get().user_version, 2);
  assert.equal(db.prepare('SELECT keep_visible FROM parking_lot WHERE id = ?').get(lot).keep_visible, 0);
});

test('keep_visible is 0 or 1 and nothing else', () => {
  const w = world();
  assert.throws(() => w.db.prepare("INSERT INTO parking_lot (id, created_at, reason, keep_visible) VALUES (?, 1, 'night', 2)").run(id()), /CHECK/);
  w.db.prepare("INSERT INTO parking_lot (id, created_at, reason, keep_visible) VALUES (?, 1, 'night', 1)").run(id());
});

test('parked_now lists only members still parked, with their lot keep_visible and an Orc for each', () => {
  const w = world();
  const lot = id();
  w.db.prepare("INSERT INTO parking_lot (id, created_at, reason, keep_visible) VALUES (?, 5, 'night', 1)").run(lot);
  const m = w.db.prepare('INSERT INTO parking_lot_member (lot_id, session_id, orc_id, state) VALUES (?, ?, ?, ?)');
  m.run(lot, w.sf, null, 'parked'); // no orc of its own: falls back to its session's
  m.run(lot, w.sk, w.k, 'woken');
  const rows = w.db.prepare('SELECT session_id, orc_id, keep_visible, parked_at FROM parked_now').all();
  assert.deepEqual(rows.map((r) => ({ ...r })), [{ session_id: w.sf, orc_id: w.f, keep_visible: 1, parked_at: 5 }]);
});

test('a snapshot equal to that Orc\'s live list is refused; A, B, A is three snapshots', () => {
  const w = world();
  const a = sha256('A');
  snapshot(w.db, { orc_id: w.f, sha256: a });
  assert.throws(() => snapshot(w.db, { orc_id: w.f, sha256: a }), /same as the live list/);
  snapshot(w.db, { orc_id: w.k, sha256: a }); // another Orc's list is not compared
  snapshot(w.db, { orc_id: w.f, sha256: sha256('B') });
  snapshot(w.db, { orc_id: w.f, sha256: a });
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM decisions_snapshot WHERE orc_id = ?').get(w.f).n, 3);
});

test('one Orc cannot publish twice in one millisecond', () => {
  const w = world();
  snapshot(w.db, { orc_id: w.f, published_at: 7 });
  assert.throws(() => snapshot(w.db, { orc_id: w.f, published_at: 7, sha256: sha256('other') }), /UNIQUE/);
  snapshot(w.db, { orc_id: w.k, published_at: 7 });
});

test('a snapshot names a real Orc', () => {
  const w = world();
  assert.throws(() => snapshot(w.db, { orc_id: id() }), /FOREIGN KEY/);
});

test('an item cannot sit past its list\'s item_count or before position 1', () => {
  const w = world();
  const s = snapshot(w.db, { orc_id: w.f, item_count: 2 });
  item(w.db, s.id, 1);
  item(w.db, s.id, 2);
  assert.throws(() => item(w.db, s.id, 3), /beyond the list/);
  const s0 = snapshot(w.db, { orc_id: w.k, item_count: 0 });
  assert.throws(() => item(w.db, s0.id, 1), /beyond the list/);
  assert.throws(() => item(w.db, s.id, 0), /CHECK/);
});

test('an item has text of 1 to 400 characters', () => {
  const w = world();
  const s = snapshot(w.db, { orc_id: w.f, item_count: 3 });
  assert.throws(() => item(w.db, s.id, 1, ''), /CHECK/);
  assert.throws(() => item(w.db, s.id, 1, 'x'.repeat(401)), /CHECK/);
  item(w.db, s.id, 1, 'x'.repeat(400));
});

test('snapshots and their items are append-only, REPLACE included', () => {
  const w = world();
  const s = snapshot(w.db, { orc_id: w.f, item_count: 1 });
  item(w.db, s.id, 1);
  assert.throws(() => w.db.prepare('UPDATE decisions_snapshot SET item_count = 5').run(), /append-only/);
  assert.throws(() => w.db.prepare('DELETE FROM decisions_snapshot').run(), /append-only/);
  assert.throws(() => w.db.prepare("UPDATE decisions_snapshot_item SET text = 'changed'").run(), /append-only/);
  assert.throws(() => w.db.prepare('DELETE FROM decisions_snapshot_item').run(), /append-only/);
  assert.throws(() => w.db.prepare("INSERT OR REPLACE INTO decisions_snapshot_item (snapshot_id, position, text) VALUES (?, 1, 'swap')").run(s.id), /append-only/);
});

test('a line cannot be added to an older list of its Orc, even one left short', () => {
  const w = world();
  const old = snapshot(w.db, { orc_id: w.f, item_count: 2 });
  item(w.db, old.id, 1);
  snapshot(w.db, { orc_id: w.f, item_count: 0 });
  assert.throws(() => item(w.db, old.id, 2), /newest list/);
});

test('decisions_live is the newest snapshot of each Orc, and decisions_live_item its lines', () => {
  const w = world();
  const old = snapshot(w.db, { orc_id: w.f, published_at: 100, item_count: 1 });
  item(w.db, old.id, 1, 'old line');
  const now = snapshot(w.db, { orc_id: w.f, published_at: 200, item_count: 1 });
  item(w.db, now.id, 1, 'new line');
  const k = snapshot(w.db, { orc_id: w.k, published_at: 50, item_count: 0 });
  const live = w.db.prepare('SELECT orc_id, id FROM decisions_live ORDER BY orc_id').all().map((r) => ({ ...r }));
  assert.deepEqual(live, [{ orc_id: w.f, id: now.id }, { orc_id: w.k, id: k.id }].sort((x, y) => (x.orc_id < y.orc_id ? -1 : 1)));
  assert.deepEqual(w.db.prepare('SELECT text FROM decisions_live_item').all().map((r) => r.text), ['new line']);
});

// --- ids ---------------------------------------------------------------------------------------------

test('ids minted in one millisecond sort in the order they were made', () => {
  const mint = makeMinter();
  const ids = [];
  for (let i = 0; i < 500; i++) ids.push(mint(T0));
  for (let i = 1; i < ids.length; i++) assert.ok(ids[i - 1] < ids[i], ids[i - 1] + ' then ' + ids[i]);
});

test('the next id in a millisecond is the last one plus one, carried across bytes', () => {
  const start = Buffer.from([0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff]);
  const mint = makeMinter(() => Buffer.from(start));
  assert.equal(mint(T0), ulid(T0, start));
  assert.equal(mint(T0), ulid(T0, Buffer.from([0, 0, 0, 0, 0, 0, 0, 0, 1, 0])));
});

test('another millisecond starts from fresh random bits', () => {
  let calls = 0;
  const mint = makeMinter(() => { calls++; return Buffer.alloc(10, calls); });
  mint(T0);
  mint(T0);
  assert.equal(calls, 1);
  assert.equal(mint(T0 + 1), ulid(T0 + 1, Buffer.alloc(10, 2)));
});

test('an id for a millisecond seen before sorts after the last one made in it, even after others', () => {
  const mint = makeMinter();
  const a = mint(T0);
  mint(T0 + 1);
  const b = mint(T0);
  assert.ok(a < b, a + ' then ' + b);
});

test('a millisecond whose 80 bits are used up is refused, not wrapped to a smaller id', () => {
  const mint = makeMinter(() => Buffer.alloc(10, 0xff));
  mint(T0);
  assert.throws(() => mint(T0), /80 bits/);
});

// --- appendHistory -----------------------------------------------------------------------------------

const opened = (w, extra = {}) => ({ task_id: w.task, at: T0, kind: 'opened', prio: 1, to_orc_id: w.f, ...extra });

test('the same history row twice is one row, and the second write hands back the first id', () => {
  const w = world();
  const a = appendHistory(w.db, 'task_event', opened(w));
  const b = appendHistory(w.db, 'task_event', opened(w));
  assert.deepEqual([a.inserted, b.inserted, b.id], [true, false, a.id]);
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM task_event').get().n, 1);
});

test('a column left out hashes as the value the database gives it', () => {
  const w = world();
  const a = appendHistory(w.db, 'task_event', opened(w));
  const b = appendHistory(w.db, 'task_event', opened(w, { backfill: 0, reason: null }));
  assert.equal(b.inserted, false);
  assert.equal(b.id, a.id);
});

test('the stored hash is the hash of the stored row', () => {
  const w = world();
  const a = appendHistory(w.db, 'task_event', opened(w));
  const row = { ...w.db.prepare('SELECT * FROM task_event WHERE id = ?').get(a.id) };
  const stored = row.sha256;
  delete row.id;
  delete row.sha256;
  assert.equal(stored, sha256(row));
});

test('different content is a new row', () => {
  const w = world();
  appendHistory(w.db, 'task_event', opened(w));
  assert.equal(appendHistory(w.db, 'task_event', opened(w, { prio: 2 })).inserted, true);
});

test('a row the rules refuse still fails: the conflict clause covers only the hash', () => {
  const w = world();
  assert.throws(() => appendHistory(w.db, 'task_event', opened(w, { kind: 'bogus' })), /CHECK/);
  assert.throws(() => appendHistory(w.db, 'task_event', opened(w, { prio: null })), /CHECK/);
  assert.throws(() => appendHistory(w.db, 'task_event', opened(w, { task_id: id() })), /FOREIGN KEY/);
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM task_event').get().n, 0);
});

test('another row that reuses a unique label is refused, not taken for a duplicate', () => {
  const w = world();
  const entry = (title) => ({ legacy_id: '20261020T120000Z-01', at: T0, kind: 'note', orc_id: w.f, fleet_wide: 1, title, text: 't' });
  appendHistory(w.db, 'changelog_entry', entry('first'));
  assert.throws(() => appendHistory(w.db, 'changelog_entry', entry('second')), /UNIQUE/);
});

test('a value of another type than its column is refused, so the hash is of what the row holds', () => {
  const w = world();
  const entry = { at: T0, kind: 'note', orc_id: w.f, fleet_wide: 1, title: 't', text: 't' };
  assert.throws(() => appendHistory(w.db, 'changelog_entry', { ...entry, text: 5 }), /text is text, not number/);
  assert.throws(() => appendHistory(w.db, 'changelog_entry', { ...entry, backfill: '1' }), /whole number/);
  assert.throws(() => appendHistory(w.db, 'changelog_entry', { ...entry, fleet_wide: true }), /whole number/);
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM changelog_entry').get().n, 0);
});

test('a misspelt column, an id or hash passed in, a table outside the list and a float are refused', () => {
  const w = world();
  assert.throws(() => appendHistory(w.db, 'task_event', opened(w, { priority: 1 })), /no column priority/);
  assert.throws(() => appendHistory(w.db, 'task_event', opened(w, { id: id() })), /made here/);
  assert.throws(() => appendHistory(w.db, 'task_event', opened(w, { sha256: sha256(1) })), /made here/);
  assert.throws(() => appendHistory(w.db, 'task', { at: T0 }), /not a hashed history table/);
  assert.throws(() => appendHistory(w.db, 'task_event', opened(w, { prio: 1.5 })), /whole number/);
  assert.throws(() => appendHistory(w.db, 'task_event', opened(w, { at: undefined })), /its time/);
});

test('every hashed history table reaches the database (its defaults are all read)', () => {
  const w = world();
  for (const t of HASHED_HISTORY) {
    // A bare row fails on the table's own NOT NULL or CHECK, never on the write layer.
    assert.throws(() => appendHistory(w.db, t, { at: T0 }), (e) => /constraint|FOREIGN KEY/i.test(e.message) && !/appendHistory/.test(e.message), t);
  }
});

test('inside a larger write, a history row rolls back with it', () => {
  const w = world();
  assert.throws(() => inWrite(w.db, () => {
    appendHistory(w.db, 'task_event', opened(w));
    throw new Error('later step failed');
  }), /later step/);
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM task_event').get().n, 0);
});

test('the id follows the event time, not the time of writing', () => {
  const w = world();
  const a = appendHistory(w.db, 'task_event', opened(w, { at: Date.UTC(2026, 0, 1) }));
  assert.equal(a.id.slice(0, 10), ulid(Date.UTC(2026, 0, 1), Buffer.alloc(10)).slice(0, 10));
});

// --- publishDecisions --------------------------------------------------------------------------------

const list = (w) => [{ text: 'Merge the relay?', question_id: w.q, recommendation: 'yes', importance: 'high' }, { text: 'Name the lot' }];

test('a published list is written whole, in order, with its hash', () => {
  const w = world();
  const r = publishDecisions(w.db, { orcId: w.f, sessionId: w.sf, publishedAt: T0, items: list(w) });
  assert.equal(r.unchanged, false);
  const s = w.db.prepare('SELECT * FROM decisions_snapshot WHERE id = ?').get(r.id);
  assert.deepEqual([s.orc_id, s.by_session_id, s.published_at, s.item_count, s.sha256], [w.f, w.sf, T0, 2, decisionsHash(list(w))]);
  const items = w.db.prepare('SELECT position, question_id, text, blocks FROM decisions_snapshot_item WHERE snapshot_id = ? ORDER BY position').all(r.id).map((x) => ({ ...x }));
  assert.deepEqual(items, [{ position: 1, question_id: w.q, text: 'Merge the relay?', blocks: null }, { position: 2, question_id: null, text: 'Name the lot', blocks: null }]);
});

test('publishing the live list again writes nothing and says unchanged', () => {
  const w = world();
  const a = publishDecisions(w.db, { orcId: w.f, publishedAt: T0, items: list(w) });
  const again = list(w).map((x) => ({ ...x, blocks: null })); // a missing field and a null one are the same list
  const b = publishDecisions(w.db, { orcId: w.f, publishedAt: T0 + 1, items: again });
  assert.deepEqual(b, { id: a.id, unchanged: true });
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM decisions_snapshot').get().n, 1);
});

test('A, B, A publishes three lists and the live one is the second A', () => {
  const w = world();
  publishDecisions(w.db, { orcId: w.f, publishedAt: T0, items: list(w) });
  publishDecisions(w.db, { orcId: w.f, publishedAt: T0 + 1, items: [{ text: 'other' }] });
  const third = publishDecisions(w.db, { orcId: w.f, publishedAt: T0 + 2, items: list(w) });
  assert.equal(third.unchanged, false);
  assert.equal(w.db.prepare('SELECT id FROM decisions_live WHERE orc_id = ?').get(w.f).id, third.id);
});

test('an empty list is a list: it empties the live one', () => {
  const w = world();
  publishDecisions(w.db, { orcId: w.f, publishedAt: T0, items: list(w) });
  const r = publishDecisions(w.db, { orcId: w.f, publishedAt: T0 + 1, items: [] });
  assert.equal(r.unchanged, false);
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM decisions_live_item WHERE orc_id = ?').get(w.f).n, 0);
});

test('a list item out of place, a non-text field or a missing list is refused before anything is written', () => {
  const w = world();
  assert.throws(() => publishDecisions(w.db, { orcId: w.f, items: [{ text: 'a', position: 2 }] }), /says position 2/);
  assert.throws(() => publishDecisions(w.db, { orcId: w.f, items: [{ text: 5 }] }), /must be text/);
  assert.throws(() => publishDecisions(w.db, { orcId: w.f, items: null }), /must be a list/);
  assert.throws(() => publishDecisions(w.db, { orcId: w.f, publishedAt: 1.5, items: [] }), /milliseconds/);
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM decisions_snapshot').get().n, 0);
});

test('a list published inside a larger write rolls back with it', () => {
  const w = world();
  assert.throws(() => inWrite(w.db, () => {
    publishDecisions(w.db, { orcId: w.f, publishedAt: T0, items: list(w) });
    throw new Error('later step failed');
  }), /later step/);
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM decisions_snapshot').get().n, 0);
});

test('a lone surrogate or a misspelt field is refused, so the hash is of what the row holds', () => {
  const w = world();
  assert.throws(() => publishDecisions(w.db, { orcId: w.f, publishedAt: T0, items: [{ text: 'a' + String.fromCharCode(0xd800) + 'b' }] }), /lone surrogate/);
  assert.throws(() => publishDecisions(w.db, { orcId: w.f, publishedAt: T0, items: [{ text: 'a', recomendation: 'yes' }] }), /no field recomendation/);
  const entry = { at: T0, kind: 'note', orc_id: w.f, fleet_wide: 1, title: 't', text: 'x' + String.fromCharCode(0xdc00) };
  assert.throws(() => appendHistory(w.db, 'changelog_entry', entry), /lone surrogate/);
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM decisions_snapshot').get().n, 0);
});

test('a list older than the live one, or in its millisecond, is refused in words', () => {
  const w = world();
  publishDecisions(w.db, { orcId: w.f, publishedAt: T0 + 10, items: list(w) });
  assert.throws(() => publishDecisions(w.db, { orcId: w.f, publishedAt: T0 + 10, items: [] }), /already has a list published at or after/);
  assert.throws(() => publishDecisions(w.db, { orcId: w.f, publishedAt: T0, items: [{ text: 'old' }] }), /already has a list published at or after/);
  assert.equal(publishDecisions(w.db, { orcId: w.k, publishedAt: T0, items: [] }).unchanged, false);
});

test('a list whose line breaks a rule leaves no snapshot behind', () => {
  const w = world();
  assert.throws(() => publishDecisions(w.db, { orcId: w.f, items: [{ text: 'ok' }, { text: '' }] }), /CHECK/);
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM decisions_snapshot').get().n, 0);
});

// --- the horde db verbs ------------------------------------------------------------------------------

function run(argv, env) {
  const out = [];
  const err = [];
  const code = main(argv, env, (s) => out.push(s), (s) => err.push(s));
  return { code, out: out.join('\n'), err: err.join('\n') };
}

// A relative home that a broken check would resolve lands in the current folder: give it a name of this
// run's own and remove it afterwards, so a mutant that makes it cannot break the next run.
const RELATIVE = 'fleet-db-relative-' + process.pid;
after(() => fs.rmSync(RELATIVE, { recursive: true, force: true }));

test('without a home, or with a relative one, every verb stops with exit 2 and makes nothing', () => {
  for (const verb of ['init', 'status', 'check']) {
    assert.equal(run([verb], {}).code, 2);
    const r = run([verb], { HORDE_HOME: path.join(RELATIVE, 'home') });
    assert.equal(r.code, 2);
    assert.match(r.err, /absolute path/);
  }
  assert.equal(fs.existsSync(RELATIVE), false);
});

test('status and check on a file that needs migrating say to run init, and change nothing', () => {
  const home = tempDir();
  const file = path.join(home, 'fleet.db');
  const raw = new DatabaseSync(file);
  raw.exec(MIGRATIONS[0]);
  raw.exec('PRAGMA user_version = 1');
  raw.close();
  for (const verb of ['status', 'check']) {
    const r = run([verb], { HORDE_HOME: home });
    assert.equal(r.code, 1);
    assert.match(r.err, /needs migrating; run horde db init/);
  }
  const back = new DatabaseSync(file, { readOnly: true });
  assert.equal(back.prepare('PRAGMA user_version').get().user_version, 1);
  back.close();
});

test('a wrong verb or anything after the verb is refused', () => {
  const home = tempDir();
  assert.equal(run(['drop'], { HORDE_HOME: home }).code, 1);
  assert.equal(run([], { HORDE_HOME: home }).code, 1);
  assert.match(run(['status', '--force'], { HORDE_HOME: home }).err, /nothing may follow/);
});

test('status and check before init say to run init, and create nothing', () => {
  const home = tempDir();
  for (const verb of ['status', 'check']) {
    const r = run([verb], { HORDE_HOME: home });
    assert.equal(r.code, 1);
    assert.match(r.err, /run horde db init/);
  }
  assert.equal(fs.existsSync(path.join(home, 'fleet.db')), false);
});

test('init creates the file, init again keeps it, status counts every table', () => {
  const home = tempDir();
  const a = run(['init'], { HORDE_HOME: home });
  assert.equal(a.code, 0);
  assert.match(a.out, /schema 2, created/);
  const b = run(['init'], { HORDE_HOME: home });
  assert.match(b.out, /already there, now current/);
  const s = run(['status'], { HORDE_HOME: home });
  assert.equal(s.code, 0);
  assert.match(s.out, /schema 2,/);
  assert.match(s.out, /^decisions_snapshot: 0 rows$/m);
  assert.match(s.out, /^task_event: 0 rows$/m);
});

test('check passes a sound file, published lists included', () => {
  const home = tempDir();
  run(['init'], { HORDE_HOME: home });
  assert.deepEqual([run(['check'], { HORDE_HOME: home }).code, run(['check'], { HORDE_HOME: home }).out], [0, 'check: ok']);
  const db = openStore(path.join(home, 'fleet.db'));
  db.prepare("INSERT INTO node (id, name, is_authority, created_at) VALUES (?, 'pc', 1, 1)").run(id());
  const o = id();
  db.prepare("INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES (?, 'F', 'f', 'F', 'orc', 1)").run(o);
  publishDecisions(db, { orcId: o, publishedAt: T0, items: [{ text: 'one', recommendation: 'yes' }, { text: 'two' }] });
  publishDecisions(db, { orcId: o, publishedAt: T0 + 1, items: [] });
  db.close();
  assert.deepEqual([run(['check'], { HORDE_HOME: home }).code, run(['check'], { HORDE_HOME: home }).out], [0, 'check: ok']);
});

test('check names a list missing a line, and a list whose lines do not hash to it', () => {
  const home = tempDir();
  run(['init'], { HORDE_HOME: home });
  const db = openStore(path.join(home, 'fleet.db'));
  db.prepare("INSERT INTO node (id, name, is_authority, created_at) VALUES (?, 'pc', 1, 1)").run(id());
  const o = id();
  db.prepare("INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES (?, 'F', 'f', 'F', 'orc', 1)").run(o);
  // Whole and hashed right, but short: written by hand, outside the write module.
  const s = snapshot(db, { orc_id: o, item_count: 2, sha256: decisionsHash([{ text: 'line' }]) });
  item(db, s.id, 1);
  const k = id();
  db.prepare("INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES (?, 'K', 'k', 'K', 'orc', 1)").run(k);
  const bad = snapshot(db, { orc_id: k, item_count: 1, sha256: decisionsHash([{ text: 'what was published' }]) });
  item(db, bad.id, 1, 'something else');
  db.close();
  const r = run(['check'], { HORDE_HOME: home });
  assert.equal(r.code, 1);
  assert.match(r.out, new RegExp('problem: decisions list ' + s.id + ' says 2 lines and holds 1'));
  assert.match(r.out, new RegExp('problem: decisions list ' + bad.id + ' does not hash to its sha256'));
  assert.doesNotMatch(r.out, new RegExp(s.id + ' does not hash'));
  assert.match(r.out, /check: 2 problems$/);
});

test('check names a row whose parent is missing', () => {
  const home = tempDir();
  run(['init'], { HORDE_HOME: home });
  const db = openStore(path.join(home, 'fleet.db'));
  db.exec('PRAGMA foreign_keys = OFF');
  db.prepare("INSERT INTO task (id, key, title, source, created_at, parent_id) VALUES (?, 'T-0001', 't', 'founder', 1, ?)").run(id(), id());
  db.close();
  const r = run(['check'], { HORDE_HOME: home });
  assert.equal(r.code, 1);
  assert.match(r.out, /problem: foreign key: task row \d+ points at a missing task/);
});
