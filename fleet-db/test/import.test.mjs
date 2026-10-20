// The importer (fleet-db/import.mjs), attacked. Every rule of "Importer (phase 1c part 1)" in
// planning/fleet-db-design.md gets a source file that breaks it, written into a folder of its own under the
// temp folder (CRLF lines, mixed Z and +00:00, lines out of time order, a line with no by, lane folder names,
// free-text waits, comma lanes, Thrall and fleet-wide, a task suffix, corrections, a BOM, a US-locale time, a
// parent session the registry lacks, an invalid card). Nothing real is read: the real files are never named.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { openStore } from '../store.mjs';
import { importFleet, parseTime, parseCard } from '../import.mjs';
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
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-db-i-'));
  dirs.push(dir); // before anything can throw: a mutant must not leak its folder
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
const added = (report) => Object.fromEntries(Object.entries(report.tables).map(([k, v]) => [k, v.added]));
const ms = (iso) => Date.parse(iso);
const jl = (objs, eol = '\n') => objs.map((o) => (typeof o === 'string' ? o : JSON.stringify(o))).join(eol) + eol;
const unlinked = (report, source, reasonPart) => report.unlinked.find((u) => u.source === source && u.reason.includes(reasonPart));

// ---------------------------------------------------------------------------------------------------------
// The fixtures

const CARD_TIME = new Date('2026-10-20T12:00:00Z');

function card({ orc, lane, doing = 'working on the list', finished = 'the first part', blocked = 'no', waiting = null, eol = '\n' }) {
  const lines = ['horde-orc-status 1', 'orc: ' + orc, 'lane: ' + lane, 'doing: ' + doing, 'finished: ' + finished, 'blocked: ' + blocked];
  if (waiting !== null) lines.push('waiting on: ' + waiting);
  return lines.join(eol) + eol;
}

function writeCard(dir, folder, text) {
  fs.mkdirSync(path.join(dir, folder), { recursive: true });
  const file = path.join(dir, folder, 'status.txt');
  fs.writeFileSync(file, text);
  fs.utimesSync(file, CARD_TIME, CARD_TIME);
  return file;
}

function makeCards(root) {
  const cards = path.join(root, 'orcs');
  writeCard(cards, 'decisions-page', card({ orc: 'F', lane: 'Decisions page' }));
  writeCard(cards, 'form-fill', card({ orc: 'C', lane: 'Form fill', blocked: 'No', eol: '\r\n' }));
  writeCard(cards, 'sleeping-sessions', card({ orc: 'K', lane: 'Sleeping sessions', blocked: 'none', waiting: 'lane F since 2026-10-20 20:40 UTC' }));
  writeCard(cards, 'research', card({ orc: 'E', lane: 'Research', blocked: 'waiting for the founder to pick a color' }));
  writeCard(cards, 'installer-devices', card({ orc: 'A', lane: 'Installer and devices' }));
  writeCard(cards, 'horde-merge-master', card({ orc: 'F1', lane: 'Merge master' }));
  fs.mkdirSync(path.join(cards, 'voice-model-board'), { recursive: true });
  const thrall = path.join(root, 'thrall-status.txt');
  fs.writeFileSync(thrall, card({ orc: 'M', lane: 'Thrall - the whole fleet', doing: 'running the fleet' }));
  fs.utimesSync(thrall, CARD_TIME, CARD_TIME);
  return { cards, thrall };
}

const L = (o) => o;
// Line numbers matter to the comments: 0-4 open the tasks, the rest are events. File order is NOT time order.
const LEDGER = [
  L({ ts: '2026-10-05T17:00:00+00:00', task: 'T-0001', event: 'opened', title: 'Root task', source: 'founder', lane: 'C', prio: 2, parent: null, by: 'analyst-backfill', backfill: false }),
  L({ ts: '2026-10-05T17:05:00Z', task: 'T-0002', event: 'opened', title: 'Child task', source: 'orc', lane: 'form-fill', prio: 1, parent: 'T-0001', by: 'C' }),
  L({ ts: '2026-10-06T09:00:00+00:00', task: 'T-0003', event: 'opened', title: 'Hand me over', source: 'decision', lane: 'decisions-page', prio: 0, parent: 'T-9999', by: 'F' }),
  L({ ts: '2026-10-06T09:10:00+00:00', task: 'T-0004', event: 'opened', title: 'Opened before its parent', source: 'finding', lane: 'zzz', prio: 3, parent: 'T-0005', by: 'F' }),
  L({ ts: '2026-10-06T09:20:00+00:00', task: 'T-0005', event: 'opened', title: 'The parent', source: 'finding', lane: 'M', prio: 2, parent: null, by: 'M' }),
  L({ ts: '2026-10-05T18:00:00+00:00', task: 'T-0001', event: 'started', by: 'C' }),
  L({ ts: '2026-10-05T19:00:00+00:00', task: 'T-0001', event: 'waiting', by: 'C', on: 'founder', reason: 'a question' }),
  L({ ts: '2026-10-05T19:10:00+00:00', task: 'T-0001', event: 'waiting', by: 'C', on: 'lane:F' }),
  L({ ts: '2026-10-05T19:20:00+00:00', task: 'T-0001', event: 'waiting', by: 'M', on: 'M' }),
  L({ ts: '2026-10-05T19:30:00+00:00', task: 'T-0001', event: 'waiting', by: 'C', on: 'device' }),
  L({ ts: '2026-10-05T19:40:00+00:00', task: 'T-0001', event: 'waiting', by: 'C', on: 'C3' }),
  L({ ts: '2026-10-05T19:50:00+00:00', task: 'T-0001', event: 'waiting', by: 'C', on: 'founder word for PRODUCTION rollout (question 50, via M)' }),
  L({ ts: '2026-10-05T20:00:00+00:00', task: 'T-0001', event: 'waiting', by: 'C', on: 'lane:ZZ' }),
  L({ ts: '2026-10-05T20:10:00+00:00', task: 'T-0001', event: 'progress', by: 'C', on: 'something', pr: 'OrahVision/horde#5', merged: true }),
  L({ ts: '2026-10-07T10:00:00Z', task: 'T-0002', event: 'done', pr: 'YedPool/horde#999', merged: true, proof: 'it works' }),
  L({ ts: '2026-10-07T10:00:00Z', task: 'T-0002', event: 'done', pr: 'YedPool/horde#999', merged: true, proof: 'it works' }),
  L({ ts: '2026-10-06T08:00:00+00:00', task: 'T-0002', event: 'started', by: 'C13', backfill: true }),
  L({ ts: '2026-10-07T11:00:00+00:00', task: 'T-0003', event: 'handed', by: 'F', to: 'sleeping-sessions' }),
  L({ ts: '2026-10-07T12:00:00+00:00', task: 'T-0003', event: 'handed', by: 'F', to: 'T-0036' }),
  L({ ts: '2026-10-07T12:30:00+00:00', task: 'T-0003', event: 'handed', by: 'F' }),
  L({ ts: '2026-10-08T09:00:00+00:00', task: 'T-0004', event: 'superseded', by: 'analyst', to: 'T-0005', reason: 'replaced' }),
  L({ ts: '2026-10-08T10:00:00+00:00', task: 'T-0001', event: 'priority', by: 'M', prio: 3 }),
  L({ ts: '2026-10-09T10:00:00+00:00', task: 'T-0001', event: 'verified', by: 'analyst-arrival', proof: 'arrived', pr: 'OrahVision/horde#5' }),
  L({ ts: '2026-10-09T10:00:00+00:00', task: 'T-0001', event: 'bogus', by: 'M' }),
  '{not json',
  L({ task: 'T-0001', event: 'progress' }),
  L({ ts: '2026-10-09T11:00:00+00:00', task: 'T-0009', event: 'progress', by: 'M', reason: 'no opened line' }),
];

const PR_CACHE = {
  'OrahVision/horde#5': { checked: '2026-10-15T19:49:05+00:00', mergedAt: '2026-10-14T10:00:00Z', state: 'MERGED' },
  'OrahVision/horde#6': { checked: '2026-10-15T19:49:05+00:00', mergedAt: null, state: 'OPEN' },
  'YedPool/horde#7': { checked: '2026-10-15T19:49:05+00:00', mergedAt: null, state: 'CLOSED' },
  'X/y#8': { checked: '2026-10-15T19:49:05+00:00', mergedAt: null, state: 'MERGED' },
  'OrahVision/horde#9': { checked: '2026-10-15T19:49:05+00:00', mergedAt: '2026-10-14T11:00:00Z', state: 'MERGED', mergeSha: 'a'.repeat(40) },
  'OrahVision/horde#10': { checked: '2026-10-15T19:49:05+00:00', mergedAt: '2026-10-14T12:00:00Z', state: 'MERGED', mergeSha: 'abc123' },
  'not a key': { checked: '2026-10-15T19:49:05+00:00', mergedAt: null, state: 'OPEN' },
};

const CHANGELOG = [
  { v: 1, id: '20261011T035700Z-01', ts: '2026-10-11T03:57:00Z', kind: 'progress', area: 'Lane C', title: 'first', text: 'Happened: a', lane: 'C', task: 'T-0001' },
  { v: 1, id: '20261011T040000Z-01', ts: '2026-10-11T04:00:00Z', kind: 'done', area: 'Lane C', title: 'two lanes', text: 'Happened: b', lane: 'C,F', task: 'T-0002 (form fill)' },
  { v: 1, id: '20261011T041000Z-01', ts: '2026-10-11T04:10:00Z', kind: 'decision', area: 'Whole fleet', title: 'thrall', text: 'Happened: c', lane: 'Thrall', task: 'T-0001' },
  { v: 1, id: '20261011T042000Z-01', ts: '2026-10-11T04:20:00Z', kind: 'note', area: 'Whole fleet', title: 'fleet wide', text: 'Happened: d', lane: 'fleet-wide' },
  { v: 1, id: '20261011T043000Z-01', ts: '2026-10-11T04:30:00Z', kind: 'result', area: 'Horde', title: 'no lane, unknown task', text: 'Happened: e', task: 'T-9999' },
  // The correction is listed (and timed) BEFORE the entry it corrects: the importer must still write the original first.
  { v: 1, id: '20261012T010000Z-01', ts: '2026-10-12T01:00:00Z', kind: 'note', area: 'Horde', title: 'the correction', text: 'Happened: fixed', lane: 'C', task: 'T-0001', corrects: '20261012T020000Z-01' },
  { v: 1, id: '20261012T020000Z-01', ts: '2026-10-12T02:00:00Z', kind: 'note', area: 'Horde', title: 'the original', text: 'Happened: wrong', lane: 'C', task: 'T-0001' },
  { v: 1, id: '20261012T030000Z-01', ts: '2026-10-12T03:00:00Z', kind: 'weird', area: 'Horde', title: 'unknown kind', text: 'Happened: g', lane: 'C', task: 'T-0001' },
  { v: 1, id: '20261012T040000Z-01', ts: '2026-10-12T04:00:00Z', kind: 'note', area: 'Horde', title: 'unknown letter', text: 'Happened: h', lane: 'Z' },
  { v: 1, id: '20261012T050000Z-01', ts: '2026-10-12T05:00:00Z', kind: 'note', area: 'Horde', title: 'three lanes', text: 'Happened: i', lane: 'D,E,F', task: 'T-0001' },
  { v: 1, id: '20261012T060000Z-01', ts: '2026-10-12T06:00:00Z', kind: 'note', area: 'Horde', title: 'corrects nothing', text: 'Happened: j', lane: 'C', task: 'T-0001', corrects: 'no-such-id' },
];

const U = (n) => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');
const SESSIONS = {
  thrall: { sid: U(1), origin: 'user', fleetSessionId: '', fleetRunDir: '', cwd: 'C:\\a', firstCwd: 'C:\\a', transcriptPath: '', owner: '', label: 'M', role: 'master', firstSeen: '2026-10-05T16:21:39.1234567Z', lastSeen: '2026-10-20T23:16:58.0000000Z' },
  orcF: { sid: U(2).toUpperCase(), origin: 'fleet', fleetSessionId: 'spawn-r4', fleetRunDir: 'C:\\run', cwd: 'C:\\b', firstCwd: 'C:\\b', transcriptPath: 'C:\\t.jsonl', owner: 'M', label: 'F', role: 'orchestrator', parent: U(1), firstSeen: '2026-10-06T10:00:00.0000000Z', lastSeen: '2026-10-20T10:00:00.0000000Z', pid: 4242, processStartedAt: '2026-10-06T10:00:05Z' },
  // A second live orchestrator for F: only one live seat per Orc and PC is allowed.
  orcF2: { sid: U(3), origin: 'fleet', owner: 'M', label: 'F', role: 'orchestrator', parent: U(1), firstSeen: '2026-10-07T10:00:00.0000000Z', lastSeen: '2026-10-08T10:00:00.0000000Z' },
  wargC3: { sid: U(4), origin: 'fleet', owner: 'C', label: 'C3', parent: U(2), firstSeen: '10/17/2026 01:49:32', lastSeen: '2026-10-18T10:00:00.0000000Z' },
  orphanChild: { sid: U(5), origin: 'fleet', owner: 'E', label: 'E1', parent: U(99), firstSeen: '2026-10-09T10:00:00.0000000Z', lastSeen: '2026-10-09T11:00:00.0000000Z' },
  retired: { sid: U(6), origin: 'fleet', owner: 'K', label: 'K', role: 'orchestrator', firstSeen: '2026-10-06T10:00:00.0000000Z', lastSeen: '2026-10-06T12:00:00.0000000Z', retired: true, retiredAt: '2026-10-06T12:30:00.0000000Z' },
  adhoc: { sid: U(7), origin: 'user', owner: '', firstSeen: '2026-10-10T10:00:00.0000000Z', lastSeen: '2026-10-10T10:00:00.0000000Z', pid: 12 },
  unknownOwner: { sid: U(8), origin: 'fleet', owner: 'Q', label: 'Q1', firstSeen: '2026-10-10T10:00:00.0000000Z', lastSeen: '2026-10-10T10:00:00.0000000Z' },
};

// All the source files of the fixture world, in a folder of their own.
function world() {
  const root = tempDir();
  const { cards, thrall } = makeCards(root);
  const ledger = path.join(root, 'tasks.jsonl');
  fs.writeFileSync(ledger, jl(LEDGER, '\r\n')); // CRLF, as the real file has
  const prCache = path.join(root, 'pr-cache.json');
  fs.writeFileSync(prCache, JSON.stringify(PR_CACHE));
  const changelog = path.join(root, 'changelog.jsonl');
  fs.writeFileSync(changelog, jl(CHANGELOG));
  const registry = path.join(root, 'sessions');
  fs.mkdirSync(registry);
  for (const [name, rec] of Object.entries(SESSIONS)) {
    // PowerShell's way: a UTF-8 byte order mark and a pretty-printed body.
    const { sid, ...body } = rec; // the registry's file name is the id
    fs.writeFileSync(path.join(registry, sid + '.json'), Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(JSON.stringify(body, null, 4))]));
    void name;
  }
  return { root, sources: { ledger, prCache, changelog, cards, thrallCard: thrall, registry } };
}

function imported() {
  const w = world();
  const { db } = fresh();
  const report = importFleet(db, w.sources);
  return { ...w, db, report };
}

// ---------------------------------------------------------------------------------------------------------
// Reading helpers

test('parseTime reads Z, an offset, seven fraction digits and the US-locale form, and refuses a non-time', () => {
  assert.equal(parseTime('2026-10-05T17:00:00+00:00'), ms('2026-10-05T17:00:00Z'));
  assert.equal(parseTime('2026-10-05T17:00:00Z'), ms('2026-10-05T17:00:00Z'));
  assert.equal(parseTime('2026-10-05T17:00:00.1234567Z'), ms('2026-10-05T17:00:00Z') + 123);
  assert.equal(parseTime('2026-10-05T19:00:00+02:00'), ms('2026-10-05T17:00:00Z'));
  assert.equal(parseTime('2026-10-05T17:00:00-0130'), ms('2026-10-05T18:30:00Z'));
  assert.equal(parseTime('10/17/2026 01:49:32'), ms('2026-10-17T01:49:32Z'));
  for (const bad of ['2026-02-31T00:00:00Z', '2026-10-05', '2026-10-05T25:00:00Z', '13/40/2026 00:00:00', '', null, 5, '2026-10-05T17:00:00']) {
    assert.equal(parseTime(bad), null, String(bad));
  }
});

test('a card is read by the reader rules: 6 or 7 lines, keys in order, one capital letter, ASCII, no BOM', () => {
  const ok = parseCard(Buffer.from(card({ orc: 'D', lane: 'Accounts', waiting: 'x' })));
  assert.equal(ok.orc, 'D');
  assert.equal(ok.lane, 'Accounts');
  assert.equal(ok.blocked, 'no');
  assert.equal(parseCard(Buffer.from(card({ orc: 'D', lane: 'x', eol: '\r\n' }))).orc, 'D');
  assert.match(parseCard(Buffer.from(card({ orc: 'F1', lane: 'x' }))).error, /'F1' is not one capital letter/);
  assert.match(parseCard(Buffer.from(card({ orc: 'f', lane: 'x' }))).error, /not one capital letter/);
  assert.match(parseCard(Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(card({ orc: 'D', lane: 'x' }))])).error, /byte order mark/);
  assert.match(parseCard(Buffer.from(card({ orc: 'D', lane: 'caf\u00e9' }), 'latin1')).error, /non-ASCII/);
  assert.match(parseCard(Buffer.from('horde-orc-status 1\norc: D\n')).error, /lines/);
  assert.match(parseCard(Buffer.from(card({ orc: 'D', lane: 'x' }).replace('horde-orc-status 1', 'horde-orc-status 2'))).error, /does not start/);
  assert.match(parseCard(Buffer.from(card({ orc: 'D', lane: 'x' }).replace('lane:', 'name:'))).error, /line 3 is not lane:/);
  assert.match(parseCard(Buffer.from(card({ orc: 'D', lane: 'x', waiting: 'y' }).replace('waiting on:', 'other:'))).error, /line 7/);
});

// ---------------------------------------------------------------------------------------------------------
// The whole world

test('node: one row for this PC when there is none, and none added when there is one', () => {
  const { db, report } = imported();
  assert.equal(count(db, 'node'), 1);
  const n = one(db, 'SELECT name, is_authority FROM node');
  assert.equal(n.name, os.hostname().slice(0, 64));
  assert.equal(n.is_authority, 1);
  assert.deepEqual(report.tables.node, { added: 1, existing: 0 });
  const again = importFleet(db, {});
  assert.deepEqual(again.tables.node, { added: 0, existing: 1 });
  // A database that already has another PC's node keeps it and uses it for the sessions.
  const other = fresh().db;
  other.prepare("INSERT INTO node (id, name, is_authority, created_at) VALUES ('01J0000000000000000000000N', 'other-pc', 1, 1)").run();
  const w = world();
  importFleet(other, { registry: w.sources.registry });
  assert.equal(count(other, 'node'), 1);
  assert.equal(one(other, 'SELECT count(*) AS n FROM session WHERE node_id = ?', '01J0000000000000000000000N').n, count(other, 'session'));
});

test('orc: a valid card makes an Orc, the Thrall card makes the Thrall, the invalid F1 card makes nothing but a report line', () => {
  const { db, report } = imported();
  const orcs = rows(db, 'SELECT letter, lane_dir, name, rank, created_at FROM orc ORDER BY letter');
  assert.deepEqual(orcs.map((o) => o.letter), ['A', 'C', 'E', 'F', 'K', 'M']);
  assert.deepEqual(one(db, "SELECT lane_dir, name, rank FROM orc WHERE letter = 'F'"), { lane_dir: 'decisions-page', name: 'Decisions page', rank: 'orc' });
  assert.deepEqual(one(db, "SELECT lane_dir, name, rank FROM orc WHERE letter = 'M'"), { lane_dir: 'thrall', name: 'Thrall - the whole fleet', rank: 'thrall' });
  assert.equal(one(db, "SELECT count(*) AS n FROM orc WHERE lane_dir = 'horde-merge-master'").n, 0);
  assert.equal(count(db, 'orc'), 6);
  assert.equal(unlinked(report, 'cards', "'F1' is not one capital letter").examples[0], 'horde-merge-master');
  assert.equal(unlinked(report, 'cards', 'folder has no status.txt').examples[0], 'voice-model-board');
  assert.deepEqual(report.tables.orc, { added: 6, existing: 0 });
});

test('orc: an existing row is kept by lane folder or by letter, never duplicated, never renamed', () => {
  const { db } = fresh();
  db.prepare("INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES ('01J0000000000000000000000F', 'F', 'decisions-page', 'Old name', 'orc', 1)").run();
  db.prepare("INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES ('01J0000000000000000000000C', 'C', 'old-folder', 'Old C', 'orc', 1)").run();
  db.prepare("INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES ('01J0000000000000000000000T', 'T', 'the-thrall', 'Old thrall', 'thrall', 1)").run();
  const w = world();
  const r = importFleet(db, { cards: w.sources.cards, thrallCard: w.sources.thrallCard });
  assert.equal(count(db, 'orc'), 6, 'F, C and the Thrall were there: A, E and K are new');
  assert.deepEqual(r.tables.orc, { added: 3, existing: 3 });
  assert.equal(one(db, "SELECT name FROM orc WHERE letter = 'F'").name, 'Old name');
  assert.equal(one(db, "SELECT lane_dir FROM orc WHERE letter = 'C'").lane_dir, 'old-folder');
  assert.equal(one(db, "SELECT count(*) AS n FROM orc WHERE rank = 'thrall'").n, 1);
  // The old Thrall's row got the Thrall's status.
  assert.equal(one(db, "SELECT count(*) AS n FROM orc_status WHERE orc_id = '01J0000000000000000000000T'").n, 1);
  assert.deepEqual(findProblems(db), []);
});

test('orc_status: one backfill row per card, no and No mean not blocked, none and a sentence are kept as words, at is the file time', () => {
  const { db, report } = imported();
  const st = Object.fromEntries(rows(db, 'SELECT o.letter, s.doing, s.blocked, s.at, s.backfill, s.session_id FROM orc_status s JOIN orc o ON o.id = s.orc_id').map((r) => [r.letter, r]));
  assert.deepEqual(Object.keys(st).sort(), ['A', 'C', 'E', 'F', 'K', 'M']);
  assert.equal(st.F.blocked, null, 'no');
  assert.equal(st.C.blocked, null, 'No, on a CRLF card');
  assert.equal(st.K.blocked, 'none');
  assert.equal(st.E.blocked, 'waiting for the founder to pick a color');
  assert.equal(st.M.doing, 'running the fleet');
  assert.equal(st.F.at, CARD_TIME.getTime());
  assert.equal(st.F.backfill, 1);
  assert.equal(st.F.session_id, null);
  assert.deepEqual(report.tables.orc_status, { added: 6, existing: 0 });
  assert.equal(count(db, 'status_now'), 6);
});

test('session: BOM stripped, id lower-cased, rank from the file, US-locale time, stub for a missing parent, one live seat per Orc', () => {
  const { db, report } = imported();
  const s = Object.fromEntries(rows(db, 'SELECT s.*, o.letter AS orc_letter FROM session s LEFT JOIN orc o ON o.id = s.orc_id').map((r) => [r.id, r]));
  assert.equal(count(db, 'session'), 9, '8 files and 1 stub');
  assert.equal(s[U(1)].rank, 'thrall');
  assert.equal(s[U(1)].orc_letter, 'M');
  assert.equal(s[U(1)].first_seen, ms('2026-10-05T16:21:39.123Z'));
  assert.equal(s[U(1)].transcript_path, null, 'an empty transcriptPath is no path');
  assert.equal(s[U(1)].fleet_session_id, null);
  assert.equal(s[U(2)].rank, 'orc', 'the id was upper case in the file');
  assert.equal(s[U(2)].orc_letter, 'F', 'an Orc session is owned by M but labelled F');
  assert.equal(s[U(2)].parent_session_id, U(1));
  assert.equal(s[U(2)].fleet_session_id, 'spawn-r4');
  assert.equal(s[U(2)].start_cwd, 'C:\\b');
  assert.equal(s[U(2)].pid, 4242);
  assert.equal(s[U(2)].process_started_at, ms('2026-10-06T10:00:05Z'));
  assert.equal(s[U(3)].rank, 'unknown', 'a second live seat for F');
  assert.equal(s[U(3)].orc_letter, 'F');
  assert.equal(s[U(4)].orc_letter, 'C', 'a Warg is owned by its Orc');
  assert.equal(s[U(4)].rank, 'unknown');
  assert.equal(s[U(4)].first_seen, ms('2026-10-17T01:49:32Z'), 'MM/DD/YYYY, UTC');
  assert.equal(s[U(5)].parent_session_id, U(99));
  assert.deepEqual({ rank: s[U(99)].rank, orc: s[U(99)].orc_id, first: s[U(99)].first_seen, last: s[U(99)].last_seen }, { rank: 'unknown', orc: null, first: s[U(5)].first_seen, last: s[U(5)].first_seen });
  assert.equal(s[U(6)].retired_at, ms('2026-10-06T12:30:00Z'));
  assert.equal(s[U(6)].rank, 'orc');
  assert.equal(s[U(7)].pid, null, 'a pid with no process start time is not kept');
  assert.equal(s[U(7)].process_started_at, null);
  assert.equal(s[U(7)].orc_id, null);
  assert.equal(s[U(8)].orc_id, null);
  assert.equal(one(db, "SELECT count(*) AS n FROM session WHERE rank = 'orc' AND retired_at IS NULL AND orc_id = ?", s[U(2)].orc_id).n, 1);
  assert.equal(unlinked(report, 'registry', 'parent is not in the registry').examples[0], U(99));
  assert.ok(unlinked(report, 'registry', 'US-locale'));
  assert.ok(unlinked(report, 'registry', 'a second live seat'));
  assert.ok(unlinked(report, 'registry', 'owner/label Q names no Orc row'));
  assert.deepEqual(report.tables.session, { added: 9, existing: 0 });
});

test('session: the freshest session takes the seat, a parent comes before its child, a self-parent and a loop are dropped', () => {
  const { db } = fresh();
  const dir = tempDir();
  const put = ({ sid, ...body }) => fs.writeFileSync(path.join(dir, sid + '.json'), JSON.stringify(body));
  const base = { origin: 'fleet', firstSeen: '2026-10-06T10:00:00Z' };
  put({ ...base, sid: U(10), owner: 'M', label: 'F', role: 'orchestrator', lastSeen: '2026-10-07T10:00:00Z' });
  put({ ...base, sid: U(11), owner: 'M', label: 'F', role: 'orchestrator', lastSeen: '2026-10-09T10:00:00Z' });
  put({ ...base, sid: U(12), parent: U(13), lastSeen: '2026-10-07T10:00:00Z' });
  put({ ...base, sid: U(13), parent: U(12), lastSeen: '2026-10-07T10:00:00Z' });
  put({ ...base, sid: U(14), parent: U(14), lastSeen: '2026-10-07T10:00:00Z' });
  put({ ...base, sid: U(15), parent: 'not-a-uuid', lastSeen: '2026-10-07T10:00:00Z' });
  put({ ...base, sid: U(16), lastSeen: '2026-10-05T10:00:00Z' });
  put({ ...base, sid: 'zzz', lastSeen: '2026-10-05T10:00:00Z' });
  fs.writeFileSync(path.join(dir, 'notes.txt'), 'not a session');
  fs.writeFileSync(path.join(dir, 'broken.json'), '{nope');
  const w = world();
  const r = importFleet(db, { cards: w.sources.cards, registry: dir });
  assert.equal(one(db, 'SELECT rank FROM session WHERE id = ?', U(11)).rank, 'orc', 'the freshest takes the seat');
  assert.equal(one(db, 'SELECT rank FROM session WHERE id = ?', U(10)).rank, 'unknown');
  const loop = rows(db, 'SELECT id, parent_session_id FROM session WHERE id IN (?, ?) ORDER BY id', U(12), U(13));
  assert.equal(loop.filter((x) => x.parent_session_id !== null).length, 1, 'exactly one edge of the loop was cut');
  assert.equal(one(db, 'SELECT parent_session_id AS p FROM session WHERE id = ?', U(14)).p, null);
  assert.equal(one(db, 'SELECT parent_session_id AS p FROM session WHERE id = ?', U(15)).p, null);
  assert.ok(unlinked(r, 'registry', 'parent makes a loop'));
  assert.ok(unlinked(r, 'registry', 'parent is the session itself'));
  assert.ok(unlinked(r, 'registry', 'parent is not a uuid'));
  assert.ok(unlinked(r, 'registry', 'session id is not a uuid'));
  assert.ok(unlinked(r, 'registry', 'file is not a JSON object'));
  assert.deepEqual(findProblems(db), []);
});

test('session: a record whose lastSeen precedes firstSeen is repaired and reported, one with no time is refused', () => {
  const { db } = fresh();
  const dir = tempDir();
  fs.writeFileSync(path.join(dir, U(20) + '.json'), JSON.stringify({ firstSeen: '2026-10-06T10:00:00Z', lastSeen: '2026-10-05T10:00:00Z' }));
  fs.writeFileSync(path.join(dir, U(21) + '.json'), JSON.stringify({}));
  fs.writeFileSync(path.join(dir, U(22) + '.json'), JSON.stringify({ firstSeen: 'garbage', lastSeen: '2026-10-05T10:00:00Z' }));
  const r = importFleet(db, { registry: dir });
  const s = one(db, 'SELECT first_seen, last_seen FROM session WHERE id = ?', U(20));
  assert.equal(s.first_seen, s.last_seen);
  assert.equal(one(db, 'SELECT first_seen FROM session WHERE id = ?', U(22)).first_seen, ms('2026-10-05T10:00:00Z'));
  assert.equal(one(db, 'SELECT count(*) AS n FROM session WHERE id = ?', U(21)).n, 0);
  assert.ok(unlinked(r, 'registry', 'lastSeen is before firstSeen'));
  assert.ok(unlinked(r, 'registry', 'are not times'));
});

test('pr: every cache row becomes a PR (state, merge time, a 40-hex merge sha), a bad row is reported, a stale one is never inferred from merged', () => {
  const { db, report } = imported();
  const pr = Object.fromEntries(rows(db, 'SELECT repo, number, state, merged_at, merge_sha, checked_at, title FROM pr').map((r) => [r.repo + '#' + r.number, r]));
  assert.equal(pr['OrahVision/horde#5'].state, 'merged');
  assert.equal(pr['OrahVision/horde#5'].merged_at, ms('2026-10-14T10:00:00Z'));
  assert.equal(pr['OrahVision/horde#5'].checked_at, ms('2026-10-15T19:49:05Z'));
  assert.equal(pr['OrahVision/horde#5'].merge_sha, null);
  assert.equal(pr['OrahVision/horde#9'].merge_sha, 'a'.repeat(40));
  assert.equal(pr['OrahVision/horde#6'].state, 'open');
  assert.equal(pr['YedPool/horde#7'].state, 'closed');
  assert.equal(pr['X/y#8'].state, 'open', 'merged with no time cannot be merged');
  assert.equal(pr['YedPool/horde#999'].state, 'open', 'the ledger said merged: true; only the cache can say merged');
  assert.equal(pr['YedPool/horde#999'].merged_at, null);
  assert.equal(pr['OrahVision/horde#10'].merge_sha, null, 'a merge sha that is not 40 hex is not kept');
  assert.equal(count(db, 'pr'), 7);
  assert.ok(unlinked(report, 'pr-cache', 'key is not OWNER/REPO#N'));
  assert.ok(unlinked(report, 'pr-cache', 'merged with no mergedAt'));
  assert.equal(unlinked(report, 'ledger', 'pr is not in the PR cache').examples[0], 'YedPool/horde#999');
});

test('pr: an existing row is kept as it is, even when the cache has moved on', () => {
  const { db } = fresh();
  const w = world();
  importFleet(db, { prCache: w.sources.prCache });
  const before = rows(db, 'SELECT * FROM pr ORDER BY id');
  const cache = JSON.parse(fs.readFileSync(w.sources.prCache, 'utf8'));
  cache['OrahVision/horde#6'] = { checked: '2026-10-19T00:00:00+00:00', mergedAt: '2026-10-18T00:00:00Z', state: 'MERGED' };
  fs.writeFileSync(w.sources.prCache, JSON.stringify(cache));
  const r = importFleet(db, { prCache: w.sources.prCache });
  assert.deepEqual(rows(db, 'SELECT * FROM pr ORDER BY id'), before);
  assert.equal(r.tables.pr.added, 0);
});

test('task: key, title, source, parent from the opened line; a parent opened later comes first; a missing parent is reported; a task with no opened line is made and reported', () => {
  const { db, report } = imported();
  const t = Object.fromEntries(rows(db, 'SELECT t.key, t.title, t.source, t.created_at, p.key AS parent FROM task t LEFT JOIN task p ON p.id = t.parent_id').map((r) => [r.key, r]));
  assert.deepEqual(Object.keys(t).sort(), ['T-0001', 'T-0002', 'T-0003', 'T-0004', 'T-0005', 'T-0009']);
  assert.deepEqual({ title: t['T-0001'].title, source: t['T-0001'].source, parent: t['T-0001'].parent, created_at: t['T-0001'].created_at }, { title: 'Root task', source: 'founder', parent: null, created_at: ms('2026-10-05T17:00:00Z') });
  assert.equal(t['T-0002'].parent, 'T-0001');
  assert.equal(t['T-0003'].parent, null);
  assert.equal(t['T-0004'].parent, 'T-0005', 'T-0004 was opened before the parent it names');
  assert.equal(t['T-0009'].title, 'T-0009 (no opened line)');
  assert.equal(t['T-0009'].created_at, ms('2026-10-09T11:00:00Z'));
  assert.equal(unlinked(report, 'ledger', 'parent T-9999 is not a task').examples[0], 'T-0003');
  assert.equal(unlinked(report, 'ledger', 'task has no opened line').examples[0], 'T-0009');
  assert.deepEqual(report.tables.task, { added: 6, existing: 0 });
});

test('task_event: one event per line, sorted by time not file order, CRLF and mixed Z/+00:00 read, ids minted from the event time', () => {
  const { db, report } = imported();
  assert.equal(count(db, 'task_event'), 21);
  assert.equal(one(db, 'SELECT count(*) AS n FROM task_event WHERE backfill = 1').n, 21);
  assert.equal(one(db, "SELECT state FROM task_now WHERE key = 'T-0002'").state, 'done', 'the later done wins over the started that is last in the file');
  assert.equal(one(db, "SELECT state FROM task_now WHERE key = 'T-0001'").state, 'verified');
  assert.equal(one(db, "SELECT prio FROM task_now WHERE key = 'T-0001'").prio, 3, 'priority event');
  assert.equal(one(db, "SELECT state FROM task_now WHERE key = 'T-0004'").state, 'superseded');
  const ordered = rows(db, 'SELECT id, at FROM task_event ORDER BY id');
  for (let i = 1; i < ordered.length; i++) assert.ok(ordered[i].at >= ordered[i - 1].at, 'ids sort by event time');
  const e = one(db, "SELECT e.at, e.id FROM task_event e JOIN task t ON t.id = e.task_id WHERE t.key = 'T-0002' AND e.kind = 'started'");
  assert.equal(e.at, ms('2026-10-06T08:00:00Z'));
  assert.deepEqual(report.tables.task_event, { added: 21, existing: 0 });
  assert.equal(unlinked(report, 'ledger', 'line is identical to an earlier line').count, 1);
  assert.equal(unlinked(report, 'ledger', 'event kind bogus').count, 1);
  assert.equal(unlinked(report, 'ledger', 'line lacks a usable ts').count, 1);
  assert.equal(unlinked(report, 'ledger', 'line is not a JSON object').count, 1);
});

test('task_event: by is an Orc row for a known letter, else by_text; a line with no by is kept and reported (the repeated line too)', () => {
  const { db, report } = imported();
  const ev = (key, kind, n = 0) => one(db, `SELECT e.by_orc_id, e.by_text, o.letter FROM task_event e JOIN task t ON t.id = e.task_id LEFT JOIN orc o ON o.id = e.by_orc_id
    WHERE t.key = ? AND e.kind = ? ORDER BY e.at LIMIT 1 OFFSET ?`, key, kind, n);
  assert.deepEqual(ev('T-0001', 'started'), { by_orc_id: one(db, "SELECT id FROM orc WHERE letter = 'C'").id, by_text: null, letter: 'C' });
  assert.deepEqual(ev('T-0002', 'started'), { by_orc_id: null, by_text: 'C13', letter: null });
  assert.deepEqual(ev('T-0001', 'opened'), { by_orc_id: null, by_text: 'analyst-backfill', letter: null });
  assert.deepEqual(ev('T-0002', 'done'), { by_orc_id: null, by_text: null, letter: null });
  assert.equal(ev('T-0005', 'opened').letter, 'M');
  assert.equal(unlinked(report, 'ledger', 'by C13 names no Orc row (kept as by_text)').count, 1);
  assert.equal(unlinked(report, 'ledger', 'by analyst names no Orc row').count, 1);
  assert.equal(unlinked(report, 'ledger', 'line has no by').count, 2);
});

test('task_event: opened takes prio and owner from its lane (a letter or a lane folder), an unknown lane is reported', () => {
  const { db, report } = imported();
  const own = (key) => one(db, "SELECT n.owner_orc_id, o.letter, n.prio FROM task_now n LEFT JOIN orc o ON o.id = n.owner_orc_id WHERE n.key = ?", key);
  assert.deepEqual(own('T-0002'), { owner_orc_id: own('T-0002').owner_orc_id, letter: 'C', prio: 1 }, 'form-fill is C');
  assert.equal(own('T-0001').letter, 'C');
  assert.equal(own('T-0005').letter, 'M');
  assert.equal(own('T-0004').letter, null);
  assert.equal(own('T-0004').prio, 3);
  assert.equal(unlinked(report, 'ledger', 'lane zzz names no Orc row').examples[0], 'T-0004');
});

test('task_event: handed takes the Orc named by a lane folder; one with no known target is reported, not imported', () => {
  const { db, report } = imported();
  assert.equal(one(db, "SELECT o.letter FROM task_now n JOIN orc o ON o.id = n.owner_orc_id WHERE n.key = 'T-0003'").letter, 'K', 'sleeping-sessions is K');
  assert.equal(one(db, "SELECT count(*) AS n FROM task_event e JOIN task t ON t.id = e.task_id WHERE t.key = 'T-0003' AND e.kind = 'handed'").n, 1);
  assert.equal(unlinked(report, 'ledger', 'handed to T-0036 names no Orc row (event not imported)').count, 1);
  assert.equal(unlinked(report, 'ledger', 'handed has no to').count, 1);
});

test('task_event: waiting on keeps the words as on_text and the class as on_kind', () => {
  const { db, report } = imported();
  const waits = Object.fromEntries(rows(db, `SELECT e.on_text, e.on_kind, o.letter AS on_letter FROM task_event e LEFT JOIN orc o ON o.id = e.on_orc_id WHERE e.kind = 'waiting' ORDER BY e.at`).map((r) => [r.on_text, r]));
  assert.deepEqual(waits.founder, { on_text: 'founder', on_kind: 'founder', on_letter: null });
  assert.deepEqual(waits['lane:F'], { on_text: 'lane:F', on_kind: 'orc', on_letter: 'F' });
  assert.deepEqual(waits.M, { on_text: 'M', on_kind: 'orc', on_letter: 'M' }, 'the Thrall');
  assert.deepEqual(waits.device, { on_text: 'device', on_kind: 'external', on_letter: null });
  assert.deepEqual(waits.C3, { on_text: 'C3', on_kind: 'orc', on_letter: null }, 'a session label names no Orc row');
  assert.equal(waits['founder word for PRODUCTION rollout (question 50, via M)'].on_kind, 'other');
  assert.deepEqual(waits['lane:ZZ'], { on_text: 'lane:ZZ', on_kind: 'orc', on_letter: null });
  assert.equal(unlinked(report, 'ledger', 'on C3 names no Orc row').count, 1);
  assert.equal(unlinked(report, 'ledger', 'on lane:ZZ names no Orc row').count, 1);
  // A non-waiting line's `on` is words only: a class on anything but a wait is refused by the schema.
  const prog = one(db, "SELECT on_text, on_kind FROM task_event WHERE kind = 'progress' AND on_text IS NOT NULL");
  assert.deepEqual(prog, { on_text: 'something', on_kind: null });
});

test('task_event: proof and reason are kept; superseded points at its replacement task', () => {
  const { db, report } = imported();
  assert.equal(one(db, "SELECT proof FROM task_event WHERE kind = 'done'").proof, 'it works');
  assert.equal(one(db, "SELECT reason FROM task_event WHERE kind = 'waiting' AND on_text = 'founder'").reason, 'a question');
  const sup = one(db, "SELECT t.key FROM task_event e JOIN task t ON t.id = e.superseded_by_id WHERE e.kind = 'superseded'");
  assert.equal(sup.key, 'T-0005');
  assert.equal(one(db, "SELECT count(*) AS n FROM task_event WHERE superseded_by_id IS NOT NULL").n, 1);
  assert.equal(report.tables.task_event.added, 21);
});

test('task_pr: a PR named by a line is linked to the task once, by backfill, at the line time; merged is not copied', () => {
  const { db, report } = imported();
  const links = rows(db, "SELECT t.key, p.repo, p.number, l.linked_by, l.linked_at FROM task_pr l JOIN task t ON t.id = l.task_id JOIN pr p ON p.id = l.pr_id ORDER BY t.key");
  assert.deepEqual(links.map((l) => l.key + ' ' + l.repo + '#' + l.number), ['T-0001 OrahVision/horde#5', 'T-0002 YedPool/horde#999']);
  assert.ok(links.every((l) => l.linked_by === 'backfill'));
  assert.equal(links[0].linked_at, ms('2026-10-05T20:10:00Z'), 'the first line that names it');
  assert.deepEqual(report.tables.task_pr, { added: 2, existing: 0 });
  const ev = one(db, "SELECT p.number FROM task_event e JOIN pr p ON p.id = e.pr_id WHERE e.kind = 'verified'");
  assert.equal(ev.number, 5);
  assert.equal(rows(db, "SELECT * FROM task_event").some((e) => 'merged' in e), false);
});

test('changelog_entry: lanes, Thrall, fleet-wide, task suffix, corrections, unknown kind, backfill, legacy id', () => {
  const { db, report } = imported();
  assert.equal(count(db, 'changelog_entry'), 11);
  const e = Object.fromEntries(rows(db, `SELECT c.legacy_id, c.at, c.kind, c.fleet_wide, c.backfill, c.title, c.text, o.letter, o.rank, t.key AS task, c.corrects_id, c.id
    FROM changelog_entry c LEFT JOIN orc o ON o.id = c.orc_id LEFT JOIN task t ON t.id = c.task_id`).map((r) => [r.legacy_id, r]));
  assert.ok(Object.values(e).every((r) => r.backfill === 1));
  assert.deepEqual({ at: e['20261011T035700Z-01'].at, kind: e['20261011T035700Z-01'].kind, letter: e['20261011T035700Z-01'].letter, task: e['20261011T035700Z-01'].task, text: e['20261011T035700Z-01'].text },
    { at: ms('2026-10-11T03:57:00Z'), kind: 'progress', letter: 'C', task: 'T-0001', text: 'Happened: a' });
  assert.equal(e['20261011T040000Z-01'].letter, 'C', 'the first of C,F');
  assert.equal(e['20261011T040000Z-01'].task, 'T-0002', 'the suffix after the key is dropped');
  assert.equal(e['20261011T041000Z-01'].rank, 'thrall');
  assert.equal(e['20261011T042000Z-01'].fleet_wide, 1);
  assert.equal(e['20261011T042000Z-01'].letter, null);
  assert.equal(e['20261011T043000Z-01'].task, null);
  assert.equal(e['20261012T030000Z-01'].kind, 'note');
  assert.equal(e['20261012T010000Z-01'].corrects_id, e['20261012T020000Z-01'].id, 'a correction points at the original, written first');
  assert.equal(e['20261012T060000Z-01'].corrects_id, null);
  assert.equal(e['20261012T040000Z-01'].letter, null, 'Z is no Orc');
  assert.equal(e['20261012T050000Z-01'].letter, null, 'D has no row, so the first letter links nothing');
  assert.deepEqual(report.tables.changelog_entry, { added: 11, existing: 0 });
  assert.equal(unlinked(report, 'changelog', 'entry has no lane').count, 1);
  assert.equal(unlinked(report, 'changelog', 'task T-9999 is not an imported task').count, 1);
  assert.equal(unlinked(report, 'changelog', 'kind weird').count, 1);
  assert.equal(unlinked(report, 'changelog', 'corrects no-such-id').count, 1);
  assert.equal(unlinked(report, 'changelog', 'lane Z names no Orc row').count, 1);
  assert.equal(unlinked(report, 'changelog', 'lane D names no Orc row').count, 1);
});

test('changelog_entry: a comma list of lanes tags every lane, a single lane tags nothing', () => {
  const { db, report } = imported();
  const tags = (legacy) => rows(db, `SELECT g.name FROM entity_tag et JOIN tag g ON g.id = et.tag_id JOIN changelog_entry c ON c.id = et.entity_id WHERE c.legacy_id = ? ORDER BY g.name`, legacy).map((r) => r.name);
  assert.deepEqual(tags('20261011T040000Z-01'), ['lane:c', 'lane:f']);
  assert.deepEqual(tags('20261012T050000Z-01'), ['lane:d', 'lane:e', 'lane:f']);
  assert.deepEqual(tags('20261011T035700Z-01'), []);
  assert.deepEqual(rows(db, 'SELECT name FROM tag ORDER BY name').map((r) => r.name), ['lane:c', 'lane:d', 'lane:e', 'lane:f']);
  assert.deepEqual(report.tables.tag, { added: 4, existing: 0 });
  assert.deepEqual(report.tables.entity_tag, { added: 5, existing: 0 });
});

test('changelog_entry: an entry already imported by its legacy id is kept as it is, even when the line changed', () => {
  const { db, sources } = imported();
  const first = one(db, "SELECT id, title FROM changelog_entry WHERE legacy_id = '20261011T035700Z-01'");
  const edited = CHANGELOG.map((c) => (c.id === '20261011T035700Z-01' ? { ...c, title: 'edited later' } : c));
  fs.writeFileSync(sources.changelog, jl(edited));
  const r = importFleet(db, { changelog: sources.changelog });
  assert.equal(r.tables.changelog_entry.added, 0);
  assert.deepEqual(one(db, "SELECT id, title FROM changelog_entry WHERE legacy_id = '20261011T035700Z-01'"), first);
});

test('changelog_entry: two lines with one id keep the first and say so; a line with no id or time is refused', () => {
  const { db } = fresh();
  const file = path.join(tempDir(), 'c.jsonl');
  const a = { v: 1, id: 'X-1', ts: '2026-10-11T03:57:00Z', kind: 'note', title: 'one', text: 't', lane: 'fleet-wide' };
  fs.writeFileSync(file, jl([a, { ...a, title: 'two' }, { ...a, id: undefined }, { ...a, id: 'X-2', ts: 'later' }, { ...a, id: 'X-3', title: '   ' }]));
  const r = importFleet(db, { changelog: file });
  assert.equal(count(db, 'changelog_entry'), 2);
  assert.equal(one(db, "SELECT title FROM changelog_entry WHERE legacy_id = 'X-1'").title, 'one');
  assert.equal(one(db, "SELECT title FROM changelog_entry WHERE legacy_id = 'X-3'").title, '(no title)');
  assert.equal(unlinked(r, 'changelog', 'two lines share one id').count, 1);
  assert.equal(unlinked(r, 'changelog', 'lacks a usable id or ts').count, 2);
  assert.ok(unlinked(r, 'changelog', 'no title'));
});

test('every unlinked row is in the report, with its source, its reason and a count; nothing is dropped silently', () => {
  const { report } = imported();
  assert.ok(report.unlinked.length >= 20);
  for (const u of report.unlinked) {
    assert.ok(['cards', 'registry', 'ledger', 'changelog', 'pr-cache'].includes(u.source), u.source);
    assert.ok(u.reason.length > 5 && u.count >= 1 && Array.isArray(u.examples) && u.examples.length <= 5);
  }
  const sorted = [...report.unlinked].map((u) => u.source + u.reason);
  assert.deepEqual(sorted, [...sorted].sort());
});

// ---------------------------------------------------------------------------------------------------------
// The guarantees

test('importing the same sources twice adds 0 rows to every table the second time, and findProblems is empty', () => {
  const { db, sources, report } = imported();
  assert.ok(report.tables.task_event.added > 0);
  const before = Object.fromEntries(['node', 'orc', 'session', 'task', 'task_event', 'pr', 'task_pr', 'changelog_entry', 'tag', 'entity_tag', 'orc_status', 'entity'].map((t) => [t, count(db, t)]));
  const again = importFleet(db, sources);
  for (const [t, c] of Object.entries(again.tables)) assert.equal(c.added, 0, t + ' grew on the second import');
  for (const [t, n] of Object.entries(before)) assert.equal(count(db, t), n, t);
  assert.equal(again.tables.orc.existing, 6);
  assert.equal(again.tables.session.existing, 9 - 1, 'the stub is not in the registry: it was found as a parent, not a file');
  assert.equal(again.tables.task_event.existing, 21);
  assert.equal(again.tables.changelog_entry.existing, 11);
  assert.deepEqual(findProblems(db), []);
});

test('a third import in another order of sources adds nothing either', () => {
  const { db, sources } = imported();
  const reversed = { registry: sources.registry, changelog: sources.changelog, cards: sources.cards, prCache: sources.prCache, ledger: sources.ledger };
  const again = importFleet(db, reversed);
  assert.deepEqual(Object.values(added(again)).reduce((a, b) => a + b, 0), 0);
});

test('only the sources given are read', () => {
  const w = world();
  const { db } = fresh();
  const r = importFleet(db, { prCache: w.sources.prCache });
  assert.equal(count(db, 'pr'), 6);
  for (const t of ['orc', 'session', 'task', 'task_event', 'changelog_entry', 'orc_status']) assert.equal(count(db, t), 0, t);
  assert.equal(r.unlinked.filter((u) => u.source !== 'pr-cache').length, 0);
  // The ledger without cards: every lane is unlinked, and still nothing fails.
  const { db: db2 } = fresh();
  const r2 = importFleet(db2, { ledger: w.sources.ledger });
  assert.equal(count(db2, 'task'), 6);
  assert.ok(unlinked(r2, 'ledger', 'lane C names no Orc row'));
  assert.deepEqual(findProblems(db2), []);
});

test('a dry run reports what a real run adds and changes nothing, node included', () => {
  const w = world();
  const { db } = fresh();
  const dry = importFleet(db, w.sources, { dryRun: true });
  assert.equal(dry.dryRun, true);
  const tables = rows(db, "SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%'").map((r) => r.name);
  for (const t of tables) {
    if (t === 'label_seq') continue;
    assert.equal(count(db, t), 0, t + ' changed in a dry run');
  }
  assert.equal(db.isTransaction, false);
  const real = importFleet(db, w.sources);
  assert.equal(real.dryRun, false);
  assert.deepEqual(real.tables, dry.tables);
  assert.deepEqual(real.unlinked, dry.unlinked);
  for (const t of Object.keys(real.tables)) assert.equal(count(db, t), real.tables[t].added, t);
});

test('a failure in the middle of an import leaves the database as it was', () => {
  const w = world();
  const { db } = fresh();
  for (const step of ['node', 'orcs', 'sessions', 'tasks', 'changelog']) {
    assert.throws(() => importFleet(db, w.sources, { onStep: (s) => { if (s === step) throw new Error('boom at ' + s); } }), /boom at/);
    for (const t of ['node', 'orc', 'session', 'task', 'task_event', 'pr', 'task_pr', 'changelog_entry', 'tag', 'entity_tag', 'orc_status', 'entity']) {
      assert.equal(count(db, t), 0, t + ' kept rows after a failure at ' + step);
    }
    assert.equal(db.isTransaction, false);
  }
  // And the same import still works afterwards.
  const ok = importFleet(db, w.sources);
  assert.ok(ok.tables.task_event.added > 0);
  assert.deepEqual(findProblems(db), []);
});

test('a source file that is missing fails before anything is written', () => {
  const w = world();
  const { db } = fresh();
  assert.throws(() => importFleet(db, { ...w.sources, changelog: path.join(w.root, 'nope.jsonl') }), /ENOENT/);
  assert.equal(count(db, 'node'), 0);
  assert.throws(() => importFleet(db, { prCache: w.sources.ledger }), /JSON|Unexpected/);
  fs.writeFileSync(path.join(w.root, 'array.json'), '[]');
  assert.throws(() => importFleet(db, { prCache: path.join(w.root, 'array.json') }), /not a JSON object/);
  assert.equal(count(db, 'node'), 0);
});

test('the history rows are hashed so a replay is a no-op, and the database refuses to change them', () => {
  const { db } = imported();
  const e = one(db, 'SELECT id FROM task_event LIMIT 1');
  assert.throws(() => db.prepare('UPDATE task_event SET reason = ? WHERE id = ?').run('x', e.id), /append-only/);
  assert.throws(() => db.prepare('DELETE FROM changelog_entry').run(), /append-only/);
  assert.throws(() => db.prepare('UPDATE orc_status SET doing = ?').run('x'), /append-only/);
});

test('a ledger line with a very long reason is cut to what the table allows; a missing prio is reported', () => {
  const { db } = fresh();
  const file = path.join(tempDir(), 'l.jsonl');
  fs.writeFileSync(file, jl([
    { ts: '2026-10-05T17:00:00Z', task: 'T-0001', event: 'opened', title: 'x'.repeat(500), source: 's'.repeat(80), lane: 'C', by: 'C' },
    { ts: '2026-10-05T17:01:00Z', task: 'T-0001', event: 'progress', by: 'C', reason: 'r'.repeat(5000), on: 'o'.repeat(900), pr: 'bad pr' },
    { ts: '2026-10-05T17:02:00Z', task: 'T-0001', event: 'priority', by: 'C' },
    { ts: '2026-10-05T17:03:00Z', task: 'T-0001', event: 'waiting', by: 'C' },
  ]));
  const r = importFleet(db, { ledger: file });
  assert.equal(one(db, 'SELECT length(title) AS n FROM task').n, 400);
  assert.equal(one(db, 'SELECT length(source) AS n FROM task').n, 40);
  assert.equal(one(db, "SELECT length(reason) AS a, length(on_text) AS b FROM task_event WHERE kind = 'progress'").a, 4000);
  assert.equal(one(db, "SELECT length(on_text) AS b FROM task_event WHERE kind = 'progress'").b, 400);
  assert.equal(one(db, "SELECT prio FROM task_event WHERE kind = 'opened'").prio, 2);
  assert.equal(count(db, 'task_event'), 3, 'the priority line with no prio is not imported');
  assert.ok(unlinked(r, 'ledger', 'opened has no usable prio'));
  assert.ok(unlinked(r, 'ledger', 'priority line has no usable prio'));
  assert.ok(unlinked(r, 'ledger', 'pr value is not OWNER/REPO#N'));
  assert.ok(unlinked(r, 'ledger', 'waiting has no on'));
  assert.deepEqual(findProblems(db), []);
});

// ---------------------------------------------------------------------------------------------------------
// The verb

function run(argv, env) {
  const out = [];
  const err = [];
  const code = main(argv, env, (s) => out.push(s), (s) => err.push(s));
  return { code, out: out.join('\n'), err: err.join('\n') };
}

test('parseImportArgs: every source flag, --dry-run, and a refusal for an unknown flag, a missing path, a repeated flag, or no source', () => {
  const ok = parseImportArgs(['--ledger', 'a', '--pr-cache', 'b', '--changelog', 'c', '--cards', 'd', '--thrall-card', 'e', '--registry', 'f', '--dry-run']);
  assert.deepEqual(ok, { sources: { ledger: 'a', prCache: 'b', changelog: 'c', cards: 'd', thrallCard: 'e', registry: 'f' }, dryRun: true });
  assert.equal(parseImportArgs(['--ledger', 'a']).dryRun, false);
  assert.throws(() => parseImportArgs(['--ledger', 'a', '--bogus']), /unknown argument --bogus/);
  assert.throws(() => parseImportArgs(['--ledger']), /needs a path/);
  assert.throws(() => parseImportArgs(['--ledger', '--dry-run']), /needs a path/);
  assert.throws(() => parseImportArgs(['--ledger', '']), /needs a path/);
  assert.throws(() => parseImportArgs(['--ledger', 'a', '--ledger', 'b']), /given twice/);
  assert.throws(() => parseImportArgs(['--dry-run']), /at least one source/);
  assert.throws(() => parseImportArgs([]), /at least one source/);
});

test('horde db import: one line per table and the unlinked report, exit 0; the second run adds nothing; --dry-run writes nothing', () => {
  const w = world();
  const home = tempDir();
  const env = { HORDE_HOME: home };
  assert.equal(run(['init'], env).code, 0);
  const flags = ['--ledger', w.sources.ledger, '--pr-cache', w.sources.prCache, '--changelog', w.sources.changelog, '--cards', w.sources.cards, '--thrall-card', w.sources.thrallCard, '--registry', w.sources.registry];
  const dry = run(['import', ...flags, '--dry-run'], env);
  assert.equal(dry.code, 0, dry.err);
  assert.match(dry.out, /^import: dry run, nothing was written/);
  assert.match(dry.out, /^task_event: 21 added, 0 already there$/m);
  assert.match(run(['status'], env).out, /^task_event: 0 rows$/m);
  const first = run(['import', ...flags], env);
  assert.equal(first.code, 0, first.err);
  assert.match(first.out, /^import: done/);
  assert.match(first.out, /^orc: 6 added, 0 already there$/m);
  assert.match(first.out, /^ledger: by C13 names no Orc row \(kept as by_text\): 1 \(e\.g\. T-0002\)$/m);
  assert.match(first.out, /^cards: card is not valid, no Orc row made: orc line 'F1' is not one capital letter: 1 \(e\.g\. horde-merge-master\)$/m);
  assert.match(run(['status'], env).out, /^task_event: 21 rows$/m);
  const second = run(['import', ...flags], env);
  assert.equal(second.code, 0, second.err);
  assert.match(second.out, /^task_event: 0 added, 21 already there$/m);
  assert.match(second.out, /^changelog_entry: 0 added, 11 already there$/m);
  assert.equal(run(['check'], env).code, 0);
});

test('horde db import: refused without a source, with a bad flag, with no database, with no home, and with a file that is not there', () => {
  const home = tempDir();
  const env = { HORDE_HOME: home };
  const w = world();
  assert.match(run(['import'], env).err, /at least one source/);
  assert.equal(run(['import'], env).code, 1);
  assert.match(run(['import', '--nope'], env).err, /unknown argument/);
  const noDb = run(['import', '--ledger', w.sources.ledger], env);
  assert.equal(noDb.code, 1);
  assert.match(noDb.err, /does not exist yet.*run horde db init/);
  assert.equal(fs.existsSync(path.join(home, 'fleet.db')), false, 'import does not make the database');
  assert.equal(run(['import', '--ledger', w.sources.ledger], {}).code, 2);
  assert.equal(run(['init'], env).code, 0);
  const missing = run(['import', '--ledger', path.join(home, 'nope.jsonl')], env);
  assert.equal(missing.code, 1);
  assert.match(missing.err, /ENOENT/);
  // init, status and check still take nothing after the verb.
  for (const v of ['init', 'status', 'check']) {
    const r = run([v, '--ledger', 'x'], env);
    assert.equal(r.code, 1);
    assert.match(r.err, /nothing may follow init, status or check/);
  }
  assert.equal(run(['bogus'], env).code, 1);
});

test('task: when a task is opened twice, the earlier opening by time makes the task, whatever the file order', () => {
  const { db } = fresh();
  const file = path.join(tempDir(), 'l.jsonl');
  fs.writeFileSync(file, jl([
    { ts: '2026-10-06T10:00:00Z', task: 'T-0007', event: 'opened', title: 'late title', source: 'orc', lane: 'C', prio: 1, by: 'C' },
    { ts: '2026-10-05T10:00:00Z', task: 'T-0007', event: 'opened', title: 'early title', source: 'founder', lane: 'C', prio: 2, by: 'C' },
  ]));
  importFleet(db, { ledger: file });
  assert.deepEqual(one(db, 'SELECT title, source, created_at FROM task'), { title: 'early title', source: 'founder', created_at: ms('2026-10-05T10:00:00Z') });
  assert.equal(count(db, 'task_event'), 2);
});
