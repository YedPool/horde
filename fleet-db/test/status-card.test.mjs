// The live status row (T-0389): `orc-cli.mjs ensure --card <status.txt>` appends the card's orc_status row (backfill 0, at the
// card's mtime) in the same transaction as the Orc row, by the importer's own reader and rule; the importer's stepStatus
// skips a card whose Orc already has a row at that time, whatever its backfill, so the sync never doubles a live row (and
// the live path never doubles the sync's). A doing or blocked the table would refuse costs the status row only: the Orc row
// is still made and the output says why. Temp homes only.
import './own-profile.mjs';
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { openStore } from '../store.mjs';
import { main } from '../orc-cli.mjs';
import { importFleet, readStatusCard, statusRowFor } from '../import.mjs';

const dirs = [];
const handles = [];
after(() => {
  for (const db of handles) {
    try { db.close(); } catch { /* closed by the test */ }
  }
  for (const d of dirs) fs.rmSync(d, { recursive: true, force: true });
});

function tempDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-db-card-'));
  dirs.push(dir); // before anything can throw: a mutant must not leak its folder
  return dir;
}

const CARD_TIME = new Date('2026-11-02T10:00:00Z');

function cardText({ orc = 'C', lane = 'Form fill', doing = 'working on the list', blocked = 'no' }) {
  return ['horde-orc-status 1', 'orc: ' + orc, 'lane: ' + lane, 'doing: ' + doing, 'finished: a part', 'blocked: ' + blocked].join('\n') + '\n';
}

// A home with a migrated fleet.db, and a cards folder holding one lane's card at a fixed time.
function world(card = {}, when = CARD_TIME) {
  const home = tempDir();
  const file = path.join(home, 'fleet.db');
  openStore(file).close();
  const cards = path.join(tempDir(), 'orcs');
  fs.mkdirSync(path.join(cards, 'form-fill'), { recursive: true });
  const cardFile = path.join(cards, 'form-fill', 'status.txt');
  fs.writeFileSync(cardFile, cardText(card));
  fs.utimesSync(cardFile, when, when);
  return { home, file, cards, cardFile, env: { HORDE_HOME: home, HORDE_ORC_BUSY_MS: '300' } };
}

function run(env, args) {
  const out = [];
  const err = [];
  const code = main(args, env, (s) => out.push(s), (s) => err.push(s));
  return { code, out: out.join('\n'), err: err.join('\n') };
}

const ensure = (w, ...more) => run(w.env, ['ensure', '--folder', 'form-fill', '--letter', 'C', '--lane', 'Form fill', '--card', w.cardFile, ...more]);

function statusRows(w) {
  const db = new DatabaseSync(w.file, { readOnly: true });
  try {
    return db.prepare('SELECT doing, blocked, at, backfill FROM orc_status ORDER BY at, backfill').all().map((r) => ({ ...r }));
  } finally {
    db.close();
  }
}

const orcCount = (w) => {
  const db = new DatabaseSync(w.file, { readOnly: true });
  try {
    return db.prepare('SELECT count(*) AS n FROM orc').get().n;
  } finally {
    db.close();
  }
};

test('ensure --card adds the orc row and its live status row; a second call keeps both', () => {
  const w = world();
  const a = ensure(w);
  assert.deepEqual([a.code, a.out], [0, 'added; status row added']);
  assert.deepEqual(statusRows(w), [{ doing: 'working on the list', blocked: null, at: CARD_TIME.getTime(), backfill: 0 }]);
  const b = ensure(w);
  assert.deepEqual([b.code, b.out], [0, 'kept; status row kept']);
  assert.equal(statusRows(w).length, 1);
  assert.equal(orcCount(w), 1);
});

test('without --card the output and the rows are what they were: added / kept, no status row', () => {
  const w = world();
  const a = run(w.env, ['ensure', '--folder', 'form-fill', '--letter', 'C', '--lane', 'Form fill']);
  assert.deepEqual([a.code, a.out], [0, 'added']);
  assert.equal(statusRows(w).length, 0);
});

test('a blocked sentence is kept as the words it is, and "No" means not blocked (the importer rule)', () => {
  const w = world({ blocked: 'waiting on the relay deploy' });
  assert.equal(ensure(w).out, 'added; status row added');
  assert.equal(statusRows(w)[0].blocked, 'waiting on the relay deploy');
  const x = world({ blocked: 'No' });
  ensure(x);
  assert.equal(statusRows(x)[0].blocked, null);
});

test('a doing past 120 characters or empty refuses the status row only: the orc row is made and the reason is said', () => {
  for (const doing of ['x'.repeat(121), '']) {
    const w = world({ doing });
    const r = ensure(w);
    assert.equal(r.code, 0, r.err);
    assert.equal(r.out, 'added; no status row: doing is empty or over 120 characters (no status row)');
    assert.equal(orcCount(w), 1, 'the orc row is still made');
    assert.equal(statusRows(w).length, 0);
  }
  const b = world({ blocked: 'y'.repeat(201) });
  const r = ensure(b);
  assert.equal(r.out, 'added; no status row: blocked is over 200 characters (no status row)');
  assert.equal(orcCount(b), 1);
  assert.equal(statusRows(b).length, 0);
  // The edge that is allowed.
  const ok = world({ doing: 'x'.repeat(120), blocked: 'y'.repeat(200) });
  assert.equal(ensure(ok).out, 'added; status row added');
});

test('a card that cannot be read or is not valid costs the status row only', () => {
  const w = world();
  fs.rmSync(w.cardFile);
  const gone = ensure(w);
  assert.equal(gone.code, 0, gone.err);
  assert.match(gone.out, /^added; no status row: the card could not be read: /);
  assert.equal(orcCount(w), 1);
  const bad = world();
  fs.writeFileSync(bad.cardFile, 'not a card\n');
  const r = ensure(bad);
  assert.match(r.out, /^added; no status row: card is not valid: has 1 lines/);
  assert.equal(orcCount(bad), 1, 'status set decided the Orc row; the card reader only judges the status row');
});

test('--card must be an absolute path and needs a value; flags are checked as before', () => {
  const w = world();
  const rel = run(w.env, ['ensure', '--folder', 'form-fill', '--letter', 'C', '--lane', 'x', '--card', 'status.txt']);
  assert.deepEqual([rel.code, rel.err], [1, 'refused: --card must be an absolute path']);
  assert.equal(orcCount(w), 0, 'a refused call makes nothing');
  const none = run(w.env, ['ensure', '--folder', 'form-fill', '--letter', 'C', '--card']);
  assert.equal(none.code, 1);
  assert.match(none.err, /--card needs a value/);
  const twice = ensure(w, '--card', w.cardFile);
  assert.equal(twice.code, 1);
  assert.match(twice.err, /--card given twice/);
});

test('the importer skips a card whose Orc already has a status row at its time, whatever the row backfill', () => {
  const w = world();
  assert.equal(ensure(w).out, 'added; status row added');
  const db = openStore(w.file);
  handles.push(db);
  const report = importFleet(db, { cards: w.cards });
  assert.deepEqual(report.tables.orc_status, { added: 0, existing: 1 });
  assert.equal(statusRows(w).length, 1, 'the sync did not double the live row');
  assert.equal(statusRows(w)[0].backfill, 0);
});

test('the other way round: a card the sync imported first is kept by the live path, not doubled', () => {
  const w = world();
  const db = openStore(w.file);
  handles.push(db);
  const report = importFleet(db, { cards: w.cards });
  assert.deepEqual(report.tables.orc_status, { added: 1, existing: 0 });
  assert.deepEqual(statusRows(w).map((r) => r.backfill), [1]);
  const r = ensure(w);
  assert.deepEqual([r.code, r.out], [0, 'kept; status row kept']);
  assert.equal(statusRows(w).length, 1);
});

test('a card written again later (a new time) is a new status for both paths', () => {
  const w = world();
  ensure(w);
  const later = new Date('2026-11-02T11:00:00Z');
  fs.writeFileSync(w.cardFile, cardText({ doing: 'a new job' }));
  fs.utimesSync(w.cardFile, later, later);
  assert.equal(ensure(w).out, 'kept; status row added');
  const db = openStore(w.file);
  handles.push(db);
  assert.deepEqual(importFleet(db, { cards: w.cards }).tables.orc_status, { added: 0, existing: 1 });
  assert.deepEqual(statusRows(w).map((r) => [r.doing, r.backfill]), [['working on the list', 0], ['a new job', 0]]);
});

test('the importer still adds a card at a NEW time when the Orc has older live rows', () => {
  const w = world();
  ensure(w);
  const later = new Date('2026-11-02T11:00:00Z');
  fs.writeFileSync(w.cardFile, cardText({ doing: 'a job the sync saw first' }));
  fs.utimesSync(w.cardFile, later, later);
  const db = openStore(w.file);
  handles.push(db);
  assert.deepEqual(importFleet(db, { cards: w.cards }).tables.orc_status, { added: 1, existing: 0 });
  assert.deepEqual(statusRows(w).map((r) => [r.doing, r.backfill]), [['working on the list', 0], ['a job the sync saw first', 1]]);
});

test('the Thrall card: --thrall with --card writes its status row against the live Thrall row', () => {
  const w = world({ orc: 'M', lane: 'Thrall' });
  const thrallCard = path.join(tempDir(), 'status.txt');
  fs.writeFileSync(thrallCard, cardText({ orc: 'M', lane: 'Thrall', doing: 'running the fleet' }));
  fs.utimesSync(thrallCard, CARD_TIME, CARD_TIME);
  const r = run(w.env, ['ensure', '--folder', 'thrall', '--letter', 'M', '--lane', 'Thrall', '--thrall', '--card', thrallCard]);
  assert.deepEqual([r.code, r.out], [0, 'added; status row added']);
  assert.equal(statusRows(w)[0].doing, 'running the fleet');
});

test('readStatusCard and statusRowFor are the importer rules: bad folder name, time in whole milliseconds, "no" is not blocked', () => {
  const w = world();
  assert.match(readStatusCard(w.cardFile, 'Form Fill', false).error, /folder name cannot be a lane_dir/);
  const ok = readStatusCard(w.cardFile, 'form-fill', false);
  assert.equal(ok.card.mtime, CARD_TIME.getTime());
  assert.equal(ok.card.orc, 'C');
  assert.deepEqual(statusRowFor(ok.card), { row: { at: CARD_TIME.getTime(), doing: 'working on the list', blocked: null } });
  assert.deepEqual(statusRowFor({ ...ok.card, blocked: 'none' }).row.blocked, 'none');
  assert.deepEqual(statusRowFor({ ...ok.card, blocked: '' }).row.blocked, null);
});
