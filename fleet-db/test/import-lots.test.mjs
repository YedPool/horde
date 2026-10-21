// The parking-lot importer (fleet-db/import.mjs, source `lots`; "Importer (phase 1c part 2b: parking lots)" in
// planning/fleet-db-design.md), attacked. Lane K keeps each lot as a folder of one-table JSON files
// ({"v":1,"table":...,"rows":[...]}, fleet/LotTables.ps1); every test writes such a folder under the temp
// folder: a lot with members and a wake, a legacy record, a file of the wrong table, a session fleet.db has
// never seen, a re-import with a member's state changed, a dry run, a failure part-way. Nothing real is read.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { openStore } from '../store.mjs';
import { importFleet } from '../import.mjs';
import { findProblems, main, parseImportArgs } from '../cli.mjs';

const dirs = [];
const handles = [];
after(() => {
  for (const db of handles) {
    try { db.close(); } catch { /* closed by the test */ }
  }
  for (const d of dirs) fs.rmSync(d, { recursive: true, force: true });
});

function tempDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-db-l-'));
  dirs.push(dir);
  return dir;
}

function fresh() {
  const file = path.join(tempDir(), 'fleet.db');
  const db = openStore(file);
  handles.push(db);
  return { db, file };
}

const rows = (db, sql, ...p) => db.prepare(sql).all(...p).map((r) => ({ ...r }));
const one = (db, sql, ...p) => { const r = db.prepare(sql).get(...p); return r ? { ...r } : undefined; };
const count = (db, table) => one(db, 'SELECT count(*) AS n FROM ' + table).n;
const LOT_TABLES = ['parking_lot', 'parking_lot_member', 'wake', 'wake_member'];
const addedOf = (report) => Object.fromEntries(Object.entries(report.tables).map(([k, v]) => [k, v.added]));
const lots = (report, reasonPart) => report.unlinked.find((u) => u.source === 'lots' && u.reason.includes(reasonPart));

// ---------------------------------------------------------------------------------------------------------
// Fixtures

const LOT_A = '01K8T0N2E0S6V7W8X9Y0Z1A2B3';
const LOT_B = '01K7XQ4M9R0P3D5F7H9J1K3M5N';
const WAKE_1 = '01K7XQ9T2B4C6D8E0F2G4H6J8K';
const S1 = '22222222-0000-4000-8000-000000000001';
const S2 = '22222222-0000-4000-8000-000000000002';
const S3 = '22222222-0000-4000-8000-000000000003';
const S4 = '22222222-0000-4000-8000-000000000004';
const S5 = '22222222-0000-4000-8000-000000000005';

function writeTable(file, table, tableRows, header = {}) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify({ v: 1, table, rows: tableRows, ...header }));
}

// One lot folder, shaped as Write-HordeFleetLot and Write-HordeFleetWake write it.
function writeLot(root, hid, { lot, members, wakes = [] }) {
  const dir = path.join(root, hid);
  writeTable(path.join(dir, 'parking_lot_member.json'), 'parking_lot_member', members);
  writeTable(path.join(dir, 'parking_lot.json'), 'parking_lot', [lot]);
  for (const w of wakes) {
    writeTable(path.join(dir, 'wakes', w.wake.id, 'wake_member.json'), 'wake_member', w.members);
    writeTable(path.join(dir, 'wakes', w.wake.id, 'wake.json'), 'wake', [w.wake]);
  }
  return dir;
}

function lotA() {
  return {
    lot: { id: LOT_A, created_at: '2026-10-19T20:20:00Z', reason: 'free memory', selection_kind: 'backfill', keep_visible: 0 },
    members: [
      { lot_id: LOT_A, session_id: S1, state: 'parked' },
      { lot_id: LOT_A, session_id: S2, state: 'parked', tier: 2, note: 'lanes/e/PARKED-E.md' },
    ],
  };
}

function lotB() {
  return {
    lot: { id: LOT_B, created_at: '2026-10-16T09:15:00Z', created_by_session_id: S5, created_by_orc_id: 'F', reason: 'hibernate tier 2', selection_kind: 'orcs', keep_visible: 1 },
    members: [
      { lot_id: LOT_B, session_id: S3, orc_id: 'F', tier: 1, state: 'woken', note: 'lanes/r/PARKED-R.md' },
      { lot_id: LOT_B, session_id: S4, state: 'dropped' },
    ],
    wakes: [{
      wake: { id: WAKE_1, lot_id: LOT_B, requested_at: '2026-10-16T11:00:00Z', requested_by_session_id: S5 },
      members: [
        { wake_id: WAKE_1, session_id: S3, outcome: 'woken' },
        { wake_id: WAKE_1, session_id: S4, new_session_id: S2, outcome: 'failed' },
      ],
    }],
  };
}

function root() {
  return path.join(tempDir(), 'hibernations');
}

// The Orc F, so created_by_orc_id 'F' can be mapped.
function withOrcF(db) {
  const card = path.join(tempDir(), 'orcs');
  fs.mkdirSync(path.join(card, 'decisions-page'), { recursive: true });
  fs.writeFileSync(path.join(card, 'decisions-page', 'status.txt'), ['horde-orc-status 1', 'orc: F', 'lane: Decisions page', 'doing: working', 'finished: a part', 'blocked: no'].join('\n') + '\n');
  importFleet(db, { cards: card });
  return one(db, "SELECT id FROM orc WHERE letter = 'F'").id;
}

// ---------------------------------------------------------------------------------------------------------

test('a lot with members and a wake becomes its four tables, ids kept, times in milliseconds', () => {
  const { db } = fresh();
  const orcF = withOrcF(db);
  const r = root();
  writeLot(r, '20261019-202000', lotA());
  writeLot(r, '20261016-091500', lotB());
  const rep = importFleet(db, { lots: r });
  assert.deepEqual(LOT_TABLES.map((t) => [t, rep.tables[t].added]), [['parking_lot', 2], ['parking_lot_member', 4], ['wake', 1], ['wake_member', 2]]);
  assert.deepEqual(one(db, 'SELECT * FROM parking_lot WHERE id = ?', LOT_A), {
    id: LOT_A, created_at: Date.UTC(2026, 9, 19, 20, 20, 0), created_by_session_id: null, created_by_orc_id: null,
    reason: 'free memory', selection_kind: 'backfill', legacy_id: null, keep_visible: 0,
  });
  const b = one(db, 'SELECT * FROM parking_lot WHERE id = ?', LOT_B);
  assert.equal(b.keep_visible, 1);
  assert.equal(b.created_by_orc_id, orcF, 'the letter F is mapped through the orc rows');
  assert.equal(b.created_by_session_id, S5);
  assert.deepEqual(one(db, 'SELECT * FROM parking_lot_member WHERE session_id = ?', S2), { lot_id: LOT_A, session_id: S2, orc_id: null, tier: 2, state: 'parked', note: 'lanes/e/PARKED-E.md' });
  assert.equal(one(db, 'SELECT orc_id FROM parking_lot_member WHERE session_id = ?', S3).orc_id, orcF);
  assert.deepEqual(one(db, 'SELECT * FROM wake'), { id: WAKE_1, lot_id: LOT_B, requested_at: Date.UTC(2026, 9, 16, 11, 0, 0), requested_by_session_id: S5 });
  assert.equal(one(db, 'SELECT new_session_id FROM wake_member WHERE session_id = ?', S4).new_session_id, S2);
  // The parked view sees what was imported as parked, with the lot's flag.
  assert.deepEqual(rows(db, 'SELECT session_id, keep_visible FROM parked_now ORDER BY session_id'), [{ session_id: S1, keep_visible: 0 }, { session_id: S2, keep_visible: 0 }]);
  assert.deepEqual(findProblems(db), []);
});

test('a session fleet.db does not know gets a stub row first, and one it knows is left alone', () => {
  const { db } = fresh();
  const reg = tempDir();
  fs.writeFileSync(path.join(reg, S1 + '.json'), JSON.stringify({ firstSeen: '2026-10-01T10:00:00.0000000Z', lastSeen: '2026-10-02T10:00:00.0000000Z', rank: 'warg' }));
  importFleet(db, { registry: reg });
  const r = root();
  writeLot(r, '20261019-202000', lotA());
  const rep = importFleet(db, { lots: r });
  assert.equal(rep.tables.session.added, 1, 'only S2 is new');
  assert.equal(one(db, 'SELECT rank FROM session WHERE id = ?', S1).rank, 'warg', 'the known session is not touched');
  assert.deepEqual(one(db, 'SELECT rank, first_seen, last_seen FROM session WHERE id = ?', S2), { rank: 'unknown', first_seen: Date.UTC(2026, 9, 19, 20, 20, 0), last_seen: Date.UTC(2026, 9, 19, 20, 20, 0) });
  assert.equal(lots(rep, 'stub row made').count, 1);
  assert.deepEqual(findProblems(db), []);
});

test('a second import adds 0 to every table', () => {
  const { db } = fresh();
  withOrcF(db);
  const r = root();
  writeLot(r, '20261019-202000', lotA());
  writeLot(r, '20261016-091500', lotB());
  importFleet(db, { lots: r });
  const before = Object.fromEntries(rows(db, "SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%'").map((t) => [t.name, count(db, t.name)]));
  const again = importFleet(db, { lots: r });
  for (const [t, c] of Object.entries(again.tables)) assert.equal(c.added, 0, t + ' added rows the second time');
  assert.deepEqual(addedOf(again).parking_lot, 0);
  assert.equal(again.tables.parking_lot.existing, 2);
  assert.equal(again.tables.parking_lot_member.existing, 4);
  assert.equal(again.tables.wake.existing, 1);
  assert.equal(again.tables.wake_member.existing, 2);
  assert.equal(again.tables.parking_lot_member.updated, 0);
  const after2 = Object.fromEntries(rows(db, "SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%'").map((t) => [t.name, count(db, t.name)]));
  assert.deepEqual(after2, before);
  assert.deepEqual(findProblems(db), []);
});

test('a legacy record (record.json, no parking_lot.json) is not imported and is named', () => {
  const { db } = fresh();
  const r = root();
  fs.mkdirSync(path.join(r, '20260101-000000'), { recursive: true });
  fs.writeFileSync(path.join(r, '20260101-000000', 'record.json'), JSON.stringify({ id: '20260101-000000' }));
  fs.mkdirSync(path.join(r, 'empty-folder'));
  writeLot(r, '20261019-202000', lotA());
  const rep = importFleet(db, { lots: r });
  const g = lots(rep, "legacy record, run K's lot backfill first");
  assert.deepEqual(g.examples, ['20260101-000000']);
  assert.equal(g.count, 1);
  assert.ok(lots(rep, 'neither parking_lot.json nor record.json'));
  assert.equal(count(db, 'parking_lot'), 1, 'the other lot still came in');
});

test('a file of the wrong table or version refuses its whole lot, and only that lot', () => {
  const { db } = fresh();
  const r = root();
  const dirA = writeLot(r, '20261019-202000', lotA());
  writeLot(r, '20261016-091500', lotB());
  // The members file says it is the wake table.
  writeTable(path.join(dirA, 'parking_lot_member.json'), 'wake', []);
  const rep = importFleet(db, { lots: r });
  const g = lots(rep, 'nothing imported from this lot');
  assert.equal(g.count, 1);
  assert.ok(g.examples[0].startsWith('20261019-202000: parking_lot_member.json is not version 1 of table parking_lot_member'));
  assert.equal(count(db, 'parking_lot'), 1);
  assert.equal(one(db, 'SELECT id FROM parking_lot').id, LOT_B);
  assert.equal(rows(db, 'SELECT 1 FROM session WHERE id = ?', S1).length, 0, 'not even a stub from the refused lot');
});

test('a wrong version, a file that is not JSON and a missing member file each refuse the lot', () => {
  for (const damage of ['version', 'json', 'missing', 'two-rows', 'wake-file']) {
    const { db } = fresh();
    const r = root();
    const dir = writeLot(r, '20261016-091500', lotB());
    if (damage === 'version') fs.writeFileSync(path.join(dir, 'parking_lot.json'), JSON.stringify({ v: 2, table: 'parking_lot', rows: [lotB().lot] }));
    if (damage === 'json') fs.writeFileSync(path.join(dir, 'parking_lot.json'), '{ not json');
    if (damage === 'missing') fs.rmSync(path.join(dir, 'parking_lot_member.json'));
    if (damage === 'two-rows') writeTable(path.join(dir, 'parking_lot.json'), 'parking_lot', [lotB().lot, lotA().lot]);
    if (damage === 'wake-file') writeTable(path.join(dir, 'wakes', WAKE_1, 'wake_member.json'), 'parking_lot', []);
    const rep = importFleet(db, { lots: r });
    assert.ok(lots(rep, 'nothing imported from this lot'), damage);
    for (const t of LOT_TABLES) assert.equal(count(db, t), 0, damage + ': ' + t);
    assert.equal(count(db, 'session'), 0, damage + ': no stub');
  }
});

test('a wake folder with no wake.json is an unfinished write: reported, not imported, the lot still comes in', () => {
  const { db } = fresh();
  const r = root();
  const dir = writeLot(r, '20261016-091500', lotB());
  fs.rmSync(path.join(dir, 'wakes', WAKE_1, 'wake.json'));
  const rep = importFleet(db, { lots: r });
  assert.ok(lots(rep, 'no wake.json'));
  assert.equal(count(db, 'parking_lot'), 1);
  assert.equal(count(db, 'wake'), 0);
  assert.equal(count(db, 'wake_member'), 0);
});

test('a member whose state moved forward is updated, never duplicated; one that moved back is kept as it was', () => {
  const { db } = fresh();
  const r = root();
  const dir = writeLot(r, '20261019-202000', lotA());
  importFleet(db, { lots: r });
  // K woke S1: the record is the authority and rewrites the member file.
  const woke = lotA();
  woke.members[0].state = 'woken';
  writeTable(path.join(dir, 'parking_lot_member.json'), 'parking_lot_member', woke.members);
  const rep = importFleet(db, { lots: r });
  assert.equal(rep.tables.parking_lot_member.added, 0);
  assert.equal(rep.tables.parking_lot_member.updated, 1);
  assert.equal(count(db, 'parking_lot_member'), 2);
  assert.equal(one(db, 'SELECT state FROM parking_lot_member WHERE session_id = ?', S1).state, 'woken');
  assert.equal(one(db, 'SELECT state FROM parking_lot_member WHERE session_id = ?', S2).state, 'parked');
  // An older copy of the file (parked again) does not take it back.
  writeTable(path.join(dir, 'parking_lot_member.json'), 'parking_lot_member', lotA().members);
  const back = importFleet(db, { lots: r });
  assert.equal(back.tables.parking_lot_member.updated, 0);
  assert.equal(one(db, 'SELECT state FROM parking_lot_member WHERE session_id = ?', S1).state, 'woken');
  assert.ok(lots(back, 'not further along'));
  // Woken and dropped are both ends: neither replaces the other.
  const drop = lotA();
  drop.members[0].state = 'dropped';
  writeTable(path.join(dir, 'parking_lot_member.json'), 'parking_lot_member', drop.members);
  const sideways = importFleet(db, { lots: r });
  assert.equal(sideways.tables.parking_lot_member.updated, 0);
  assert.equal(one(db, 'SELECT state FROM parking_lot_member WHERE session_id = ?', S1).state, 'woken');
  assert.deepEqual(findProblems(db), []);
});

test('the lot row is created once: a changed reason in the file does not rewrite it', () => {
  const { db } = fresh();
  const r = root();
  const dir = writeLot(r, '20261019-202000', lotA());
  importFleet(db, { lots: r });
  const changed = lotA();
  changed.lot.reason = 'another reason';
  writeTable(path.join(dir, 'parking_lot.json'), 'parking_lot', [changed.lot]);
  const rep = importFleet(db, { lots: r });
  assert.equal(rep.tables.parking_lot.added, 0);
  assert.equal(one(db, 'SELECT reason FROM parking_lot').reason, 'free memory');
});

test('a member added to a lot after its first import comes in on the next one', () => {
  const { db } = fresh();
  const r = root();
  const dir = writeLot(r, '20261019-202000', lotA());
  importFleet(db, { lots: r });
  const more = lotA();
  more.members.push({ lot_id: LOT_A, session_id: S3, state: 'parked' });
  writeTable(path.join(dir, 'parking_lot_member.json'), 'parking_lot_member', more.members);
  const rep = importFleet(db, { lots: r });
  assert.equal(rep.tables.parking_lot_member.added, 1);
  assert.equal(count(db, 'parking_lot_member'), 3);
});

test('a dry run reports what a real run adds and writes nothing', () => {
  const { db } = fresh();
  const r = root();
  writeLot(r, '20261019-202000', lotA());
  writeLot(r, '20261016-091500', lotB());
  const dry = importFleet(db, { lots: r }, { dryRun: true });
  assert.equal(dry.dryRun, true);
  for (const t of [...LOT_TABLES, 'session', 'node']) assert.equal(count(db, t), 0, t);
  const real = importFleet(db, { lots: r });
  assert.deepEqual(addedOf(real), addedOf(dry));
  assert.deepEqual(real.unlinked, dry.unlinked);
});

test('a failure after the lots leaves nothing of them', () => {
  const { db } = fresh();
  const r = root();
  writeLot(r, '20261019-202000', lotA());
  writeLot(r, '20261016-091500', lotB());
  assert.throws(() => importFleet(db, { lots: r }, { onStep: (s) => { if (s === 'lots') throw new Error('boom'); } }), /boom/);
  for (const t of [...LOT_TABLES, 'session', 'node']) assert.equal(count(db, t), 0, t);
  assert.deepEqual(findProblems(db), []);
});

test('a row the schema refuses rolls its lot back whole and is reported; the other lots go on', () => {
  const cases = {
    'a state that is not parked, woken or dropped': (l) => { l.members[1].state = 'asleep'; },
    'a ULID that is not one': (l) => { l.lot.id = 'not-a-ulid'; l.members.forEach((m) => { m.lot_id = 'not-a-ulid'; }); },
    'a member of another lot': (l) => { l.members[0].lot_id = LOT_B; },
    'a tier of 3': (l) => { l.members[0].tier = 3; },
    'a session id that is no uuid': (l) => { l.members[0].session_id = 'S-1'; },
    'a time that is not UTC seconds': (l) => { l.lot.created_at = '19/10/2026'; },
    'a selection kind outside the four': (l) => { l.lot.selection_kind = 'everything'; },
    'a reason of nothing': (l) => { l.lot.reason = ''; },
    'a keep_visible of 2': (l) => { l.lot.keep_visible = 2; },
    'a session twice in a lot': (l) => { l.members[1].session_id = S1; },
  };
  for (const [name, damage] of Object.entries(cases)) {
    const { db } = fresh();
    const r = root();
    const bad = lotA();
    damage(bad);
    writeLot(r, '20261019-202000', bad);
    writeLot(r, '20261016-091500', lotB());
    const rep = importFleet(db, { lots: r });
    const g = lots(rep, 'a row was refused');
    assert.ok(g, name);
    assert.deepEqual(g.examples, ['20261019-202000'], name);
    assert.equal(count(db, 'parking_lot'), 1, name);
    assert.equal(one(db, 'SELECT id FROM parking_lot').id, LOT_B, name);
    assert.equal(rows(db, 'SELECT 1 FROM session WHERE id = ?', S1).length, 0, name + ': no stub left by the refused lot');
    assert.equal(count(db, 'parking_lot_member'), 2, name + ': only the good lot has members');
    assert.deepEqual(findProblems(db), [], name);
  }
});

test('a broken wake row rolls back its lot, wakes and members with it', () => {
  const { db } = fresh();
  const r = root();
  const b = lotB();
  b.wakes[0].members[0].outcome = 'vanished';
  writeLot(r, '20261016-091500', b);
  const rep = importFleet(db, { lots: r });
  assert.ok(lots(rep, 'a row was refused'));
  for (const t of [...LOT_TABLES, 'session']) assert.equal(count(db, t), 0, t);
  assert.equal(rep.tables.parking_lot.added, 0, 'the report counts nothing of a rolled-back lot');
});

test('an Orc the orc rows do not know is left empty and reported; a lane folder and a sub-session label map', () => {
  const { db } = fresh();
  const orcF = withOrcF(db);
  const r = root();
  const l = lotB();
  l.lot.created_by_orc_id = 'Q';
  l.members[0].orc_id = 'decisions-page';
  l.members[1].orc_id = 'F3';
  writeLot(r, '20261016-091500', l);
  const rep = importFleet(db, { lots: r });
  assert.equal(one(db, 'SELECT created_by_orc_id AS o FROM parking_lot').o, null);
  assert.equal(one(db, 'SELECT orc_id FROM parking_lot_member WHERE session_id = ?', S3).orc_id, orcF);
  assert.equal(one(db, 'SELECT orc_id FROM parking_lot_member WHERE session_id = ?', S4).orc_id, orcF);
  assert.deepEqual(lots(rep, 'names no Orc row').examples, ['20261016-091500']);
});

test('a column left out is NULL and a column the schema does not know is reported, not stored', () => {
  const { db } = fresh();
  const r = root();
  const l = lotA();
  l.lot.mood = 'tired';
  l.members[0].label = 'B';
  writeLot(r, '20261019-202000', l);
  const rep = importFleet(db, { lots: r });
  const m = one(db, 'SELECT * FROM parking_lot_member WHERE session_id = ?', S1);
  assert.equal(m.orc_id, null);
  assert.equal(m.tier, null);
  assert.equal(m.note, null);
  assert.ok(lots(rep, 'parking_lot column mood is not known'));
  assert.ok(lots(rep, 'parking_lot_member column label is not known'));
  assert.equal(one(db, 'SELECT keep_visible FROM parking_lot').keep_visible, 0);
});

test('a lot written before the keep_visible flag is read as 0', () => {
  const { db } = fresh();
  const r = root();
  const l = lotA();
  delete l.lot.keep_visible;
  writeLot(r, '20261019-202000', l);
  importFleet(db, { lots: r });
  assert.equal(one(db, 'SELECT keep_visible FROM parking_lot').keep_visible, 0);
});

test('a BOM at the start of a file (PowerShell 5.1) is read', () => {
  const { db } = fresh();
  const r = root();
  const dir = writeLot(r, '20261019-202000', lotA());
  const file = path.join(dir, 'parking_lot.json');
  fs.writeFileSync(file, Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), fs.readFileSync(file)]));
  const rep = importFleet(db, { lots: r });
  assert.equal(rep.tables.parking_lot.added, 1);
});

test('the cli takes --lots, rejects it twice, and prints how many members moved forward', () => {
  assert.deepEqual(parseImportArgs(['--lots', 'x']).sources, { lots: 'x' });
  assert.throws(() => parseImportArgs(['--lots', 'a', '--lots', 'b']), /given twice/);
  assert.throws(() => parseImportArgs(['--lots']), /needs a path/);
  const { file } = fresh();
  const home = path.dirname(file);
  const r = root();
  const dir = writeLot(r, '20261019-202000', lotA());
  const lines = [];
  const env = { HORDE_HOME: home };
  assert.equal(main(['import', '--lots', r], env, (s) => lines.push(s), (s) => lines.push('ERR ' + s)), 0);
  assert.ok(lines.includes('parking_lot: 1 added, 0 already there'));
  assert.ok(lines.includes('parking_lot_member: 2 added, 0 already there, 0 moved forward'));
  const woke = lotA();
  woke.members[0].state = 'woken';
  writeTable(path.join(dir, 'parking_lot_member.json'), 'parking_lot_member', woke.members);
  const again = [];
  assert.equal(main(['import', '--lots', r, '--dry-run'], env, (s) => again.push(s), (s) => again.push('ERR ' + s)), 0);
  assert.ok(again.includes('parking_lot_member: 0 added, 2 already there, 1 moved forward'), again.join('\n'));
  assert.ok(again[0].includes('dry run'));
});

test('a lot time that is not UTC to the second is refused with that reason, not by a column error', () => {
  for (const bad of ['19/10/2026', '2026-10-19T20:20:00+02:00', '2026-10-19', 12345]) {
    const { db } = fresh();
    const r = root();
    const l = lotA();
    l.lot.created_at = bad;
    writeLot(r, '20261019-202000', l);
    const rep = importFleet(db, { lots: r });
    assert.ok(lots(rep, 'is not a UTC time like'), String(bad));
    assert.equal(count(db, 'parking_lot'), 0, String(bad));
  }
});

test('a tier that is not 1 or 2 refuses only its lot, whatever its type', () => {
  for (const tier of [true, {}, [1], 'x', 3, 1.5]) {
    const { db } = fresh();
    const r = root();
    const bad = lotA();
    bad.members[0].tier = tier;
    writeLot(r, '20261019-202000', bad);
    writeLot(r, '20261016-091500', lotB());
    const rep = importFleet(db, { lots: r });
    assert.ok(lots(rep, 'tier is not 1 or 2'), JSON.stringify(tier));
    assert.deepEqual(rows(db, 'SELECT id FROM parking_lot').map((x) => x.id), [LOT_B], JSON.stringify(tier));
    assert.deepEqual(findProblems(db), [], JSON.stringify(tier));
  }
});

test('a wake member that is not in the lot, or twice in a wake, refuses the lot', () => {
  const { db } = fresh();
  const r = root();
  const b = lotB();
  b.wakes[0].members.push({ wake_id: WAKE_1, session_id: S1, outcome: 'woken' });
  writeLot(r, '20261016-091500', b);
  assert.ok(lots(importFleet(db, { lots: r }), 'not a member of the lot'));
  assert.equal(count(db, 'parking_lot'), 0);
  assert.deepEqual(findProblems(db), []);
  const d = fresh().db;
  const r2 = root();
  const b2 = lotB();
  b2.wakes[0].members.push({ wake_id: WAKE_1, session_id: S3, outcome: 'woken' });
  writeLot(r2, '20261016-091500', b2);
  assert.ok(lots(importFleet(d, { lots: r2 }), 'in the wake twice'));
  assert.equal(count(d, 'wake_member'), 0);
  assert.deepEqual(findProblems(d), []);
});

test('a lot with no member is reported', () => {
  const { db } = fresh();
  const r = root();
  const a = lotA();
  a.members = [];
  writeLot(r, '20261019-202000', a);
  assert.ok(lots(importFleet(db, { lots: r }), 'holds no member'));
  assert.deepEqual(findProblems(db), []);
});

test('a lot, wake or wake member already there with other content is kept and reported', () => {
  const { db } = fresh();
  const r = root();
  const dir = writeLot(r, '20261016-091500', lotB());
  importFleet(db, { lots: r });
  const b = lotB();
  b.lot.reason = 'other';
  b.wakes[0].wake.requested_at = '2026-10-16T12:00:00Z';
  b.wakes[0].members[0].outcome = 'failed';
  writeTable(path.join(dir, 'parking_lot.json'), 'parking_lot', [b.lot]);
  writeTable(path.join(dir, 'wakes', WAKE_1, 'wake.json'), 'wake', [b.wakes[0].wake]);
  writeTable(path.join(dir, 'wakes', WAKE_1, 'wake_member.json'), 'wake_member', b.wakes[0].members);
  const rep = importFleet(db, { lots: r });
  assert.ok(lots(rep, 'lot already in fleet.db with other content'));
  assert.ok(lots(rep, 'wake already in fleet.db with other content'));
  assert.ok(lots(rep, 'wake member already in fleet.db with other content'));
  assert.equal(one(db, 'SELECT reason FROM parking_lot').reason, 'hibernate tier 2');
  assert.equal(one(db, 'SELECT outcome FROM wake_member WHERE session_id = ?', S3).outcome, 'woken');
  assert.equal(one(db, 'SELECT requested_at FROM wake').requested_at, Date.UTC(2026, 9, 16, 11, 0, 0), 'the wake time is kept');
  assert.deepEqual(findProblems(db), []);
});

test('a member already there with another orc_id, tier or note is kept and reported', () => {
  const { db } = fresh();
  const r = root();
  const dir = writeLot(r, '20261019-202000', lotA());
  importFleet(db, { lots: r });
  const a = lotA();
  a.members[1].tier = 1;
  a.members[1].note = 'elsewhere.md';
  writeTable(path.join(dir, 'parking_lot_member.json'), 'parking_lot_member', a.members);
  const rep = importFleet(db, { lots: r });
  assert.ok(lots(rep, 'member already in fleet.db with another orc_id, tier or note'));
  assert.deepEqual(one(db, 'SELECT tier, note FROM parking_lot_member WHERE session_id = ?', S2), { tier: 2, note: 'lanes/e/PARKED-E.md' });
  assert.deepEqual(findProblems(db), []);
});

test('a wake id already there under another lot refuses the lot, and its report lines are dropped with it', () => {
  const { db } = fresh();
  const r = root();
  writeLot(r, '20261016-091500', lotB());
  importFleet(db, { lots: r });
  const r2 = root();
  const a = lotA();
  // lot A claims the wake id that belongs to lot B, and has a lot whose content differs to make a mismatch line first.
  a.lot.reason = 'free memory';
  a.wakes = [{ wake: { id: WAKE_1, lot_id: LOT_A, requested_at: '2026-10-19T21:00:00Z' }, members: [{ wake_id: WAKE_1, session_id: S1, outcome: 'woken' }] }];
  writeLot(r2, '20261019-202000', a);
  const rep = importFleet(db, { lots: r2 });
  assert.ok(lots(rep, 'already in fleet.db under another lot'));
  assert.equal(count(db, 'parking_lot'), 1);
  assert.equal(count(db, 'wake_member'), 2, 'nothing was added to the other lot\'s wake');
  assert.equal(rep.tables.parking_lot.added, 0);
  assert.ok(!lots(rep, 'stub row made'), 'the refused lot leaves no report line of its own');
  assert.deepEqual(findProblems(db), []);
});
