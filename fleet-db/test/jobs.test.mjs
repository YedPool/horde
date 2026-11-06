// Migration 8 (job and signal) and the verbs that write them (jobs.mjs, jobs-cli.mjs), each attacked: a row the rules exist
// to stop is written and must be refused, and the row it must still allow is written too. Databases of their own under the
// temp folder; nothing real is read or written.
import './own-profile.mjs';
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { openStore } from '../store.mjs';
import { MIGRATIONS, SCHEMA_VERSION } from '../schema.mjs';
import { upsertJob, doneJob, listJobs, raiseSignal, closeSignal, listSignals, pruneSignals, whenOf } from '../jobs.mjs';
import { main, parseFlags } from '../jobs-cli.mjs';
import { findProblems } from '../cli.mjs';

const NOW = Date.UTC(2026, 10, 6, 12, 0, 0);
const MIN = 60000;
const DAY = 24 * 60 * MIN;
const UUID1 = '00000000-0000-4000-8000-000000000001';

const dirs = [];
const handles = [];
after(() => {
  for (const db of handles) {
    try { db.close(); } catch { /* closed by the test */ }
  }
  for (const d of dirs) fs.rmSync(d, { recursive: true, force: true });
});

function world() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-db-jobs-'));
  dirs.push(dir);
  const file = path.join(dir, 'fleet.db');
  const db = openStore(file);
  handles.push(db);
  return { dir, file, db, now: NOW };
}

const clock = (w) => ({ now: () => w.now });
const refuses = (fn, re) => assert.throws(fn, (e) => e.refusal === true && re.test(e.message), String(re));
const sqlRefuses = (fn, re) => assert.throws(fn, re);

// The CLI as a caller sees it: { code, out, err } with the clock and the home fixed.
function cli(w, argv, env = {}) {
  const out = [];
  const err = [];
  const code = main(argv, { HORDE_HOME: w.dir, ...env }, (s) => out.push(s), (s) => err.push(s), { now: () => w.now });
  return { code, out, err };
}

const job = (w, over = {}) => upsertJob(w.db, { id: 'J-1', owner: 'R', job: 'review the PRs', by: 'S', ...over }, clock(w));
const sig = (w, over = {}) => raiseSignal(w.db, { key: 'ALARM:A', kind: 'alarm', text: 'something is stuck', ...over }, clock(w));
const row = (w, table, where, ...args) => ({ ...w.db.prepare('SELECT * FROM ' + table + ' WHERE ' + where).get(...args) });

// --- migration 8 -------------------------------------------------------------------------------------------------------

test('migration 8 on a schema 7 file: the tables and indexes come, every old row stays, check says ok', () => {
  assert.equal(SCHEMA_VERSION, 8);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-db-jobs-mig-'));
  dirs.push(dir);
  const file = path.join(dir, 'fleet.db');
  const raw = new DatabaseSync(file);
  raw.exec('PRAGMA foreign_keys = ON');
  for (let v = 0; v < 7; v++) raw.exec(MIGRATIONS[v]);
  raw.exec('PRAGMA user_version = 7');
  raw.exec("INSERT INTO node (id, name, is_authority, created_at) VALUES ('01JA0000000000000000000001', 'pc-1', 1, 5)");
  raw.close();
  const db = openStore(file);
  handles.push(db);
  assert.equal(db.prepare('PRAGMA user_version').get().user_version, 8);
  assert.equal(db.prepare('SELECT count(*) AS n FROM node').get().n, 1);
  const names = db.prepare("SELECT name FROM sqlite_master WHERE name IN ('job', 'signal', 'job_open_due', 'signal_open_last', 'signal_closed')").all().map((r) => r.name).sort();
  assert.deepEqual(names, ['job', 'job_open_due', 'signal', 'signal_closed', 'signal_open_last']);
  assert.deepEqual(findProblems(db), []);
});

test('job and signal are not entities: no entity row is made for either', () => {
  const w = world();
  job(w);
  sig(w);
  assert.equal(w.db.prepare("SELECT count(*) AS n FROM entity WHERE kind IN ('job', 'signal')").get().n, 0);
});

// --- the schema's own rules --------------------------------------------------------------------------------------------

function rawJob(db, over = {}) {
  const r = { id: 'J-9', owner: 'R', session_id: null, job: 'x', started_at: NOW, due_at: null, done_at: null, done_proof: null, created_by: 'S', ...over };
  const cols = Object.keys(r);
  return db.prepare('INSERT INTO job (' + cols.join(', ') + ') VALUES (' + cols.map(() => '?').join(', ') + ')').run(...cols.map((c) => r[c]));
}
function rawSignal(db, over = {}) {
  const r = { key: 'K-9', kind: 'alarm', owner: null, text: 'x', first_at: NOW, last_at: NOW, count: 1, woke_at: null, closed_at: null, closed_by: null, ...over };
  const cols = Object.keys(r);
  return db.prepare('INSERT INTO signal (' + cols.join(', ') + ') VALUES (' + cols.map(() => '?').join(', ') + ')').run(...cols.map((c) => r[c]));
}

test('job: the CHECKs refuse each bad row, and the good ones are written', () => {
  const { db } = world();
  rawJob(db, { id: 'ok-1', session_id: UUID1, due_at: NOW + 1, done_at: NOW + 5, done_proof: 'PR 5' });
  rawJob(db, { id: 'ok-2', done_at: NOW, done_proof: 'same instant' });
  for (const bad of [
    { id: '' }, { id: 'has space' }, { id: 'x'.repeat(121) }, { id: 'caf\u00e9' }, { owner: '' }, { owner: 'two words' }, { owner: 'o'.repeat(65) },
    { job: '' }, { job: 'j'.repeat(4001) }, { created_by: '' }, { created_by: 'a b' }, { started_at: -1 }, { due_at: -1 },
    { session_id: 'not-a-uuid' }, { session_id: 'AAAAAAAA-0000-4000-8000-000000000001' },
    { done_at: NOW - 1, done_proof: 'p' }, { done_at: NOW }, { done_proof: 'p' }, { done_at: NOW, done_proof: '' }, { done_at: NOW, done_proof: 'p'.repeat(4001) },
  ]) sqlRefuses(() => rawJob(db, bad), /CHECK|NOT NULL/);
  sqlRefuses(() => rawJob(db, { id: 'ok-1' }), /UNIQUE|PRIMARY/);
  assert.equal(db.prepare('SELECT count(*) AS n FROM job').get().n, 2);
});

test('job: its start, its maker and its id never change, and a done job is final', () => {
  const { db } = world();
  rawJob(db, { id: 'open' });
  rawJob(db, { id: 'closed', done_at: NOW + 1, done_proof: 'p' });
  sqlRefuses(() => db.prepare("UPDATE job SET started_at = started_at + 1 WHERE id = 'open'").run(), /never change/);
  sqlRefuses(() => db.prepare("UPDATE job SET created_by = 'other' WHERE id = 'open'").run(), /never change/);
  sqlRefuses(() => db.prepare("UPDATE job SET id = 'renamed' WHERE id = 'open'").run(), /never change/);
  sqlRefuses(() => db.prepare("UPDATE job SET done_proof = 'another' WHERE id = 'closed'").run(), /final/);
  sqlRefuses(() => db.prepare("UPDATE job SET done_at = NULL, done_proof = NULL WHERE id = 'closed'").run(), /final/);
  sqlRefuses(() => db.prepare("UPDATE job SET owner = 'X' WHERE id = 'closed'").run(), /final/);
  db.prepare("UPDATE job SET owner = 'X' WHERE id = 'open'").run();
});

test('signal: the CHECKs refuse each bad row, and the good ones are written', () => {
  const { db } = world();
  rawSignal(db, { key: 'ok-1', owner: 'O', woke_at: NOW, last_at: NOW + 1, count: 5, closed_at: NOW + 2, closed_by: 'S' });
  for (const bad of [
    { key: '' }, { key: 'has space' }, { key: 'k'.repeat(201) }, { key: 'caf\u00e9' }, { kind: '' }, { kind: 'two words' }, { owner: '' }, { owner: 'a b' },
    { text: '' }, { text: 't'.repeat(4001) }, { first_at: -1, last_at: 0 }, { last_at: NOW - 1 }, { count: 0 }, { count: -1 }, { woke_at: -1 },
    { closed_at: NOW }, { closed_by: 'S' }, { closed_at: NOW, closed_by: '' }, { closed_at: -1, closed_by: 'S' },
  ]) sqlRefuses(() => rawSignal(db, bad), /CHECK|NOT NULL/);
  sqlRefuses(() => rawSignal(db, { key: 'ok-1' }), /UNIQUE|PRIMARY/);
  assert.equal(db.prepare('SELECT count(*) AS n FROM signal').get().n, 1);
});

test('signal: key, kind and first_at never change; last_at and count never go back', () => {
  const { db } = world();
  rawSignal(db, { key: 'a', last_at: NOW + 10, count: 3 });
  sqlRefuses(() => db.prepare("UPDATE signal SET key = 'b' WHERE key = 'a'").run(), /never change/);
  sqlRefuses(() => db.prepare("UPDATE signal SET kind = 'other' WHERE key = 'a'").run(), /never change/);
  sqlRefuses(() => db.prepare("UPDATE signal SET first_at = first_at - 1 WHERE key = 'a'").run(), /never change/);
  sqlRefuses(() => db.prepare("UPDATE signal SET last_at = last_at - 1 WHERE key = 'a'").run(), /never go back/);
  sqlRefuses(() => db.prepare("UPDATE signal SET count = 2 WHERE key = 'a'").run(), /never go back/);
  db.prepare("UPDATE signal SET last_at = last_at + 1, count = 4 WHERE key = 'a'").run();
});

// --- times and text, refused in words ----------------------------------------------------------------------------------

test('times: milliseconds and ISO with a zone are read; a local time, a rolled date and a stray number are refused', () => {
  const o = { now: NOW };
  assert.equal(whenOf(String(NOW), 'At', o), NOW);
  assert.equal(whenOf(NOW, 'At', o), NOW);
  assert.equal(whenOf('2026-11-06T12:00:00Z', 'At', o), NOW);
  assert.equal(whenOf('2026-11-06T07:00:00-05:00', 'At', o), NOW);
  assert.equal(whenOf('2026-11-06T07:00:00-0500', 'At', o), NOW);
  assert.equal(whenOf('2026-11-06T12:00:00.250Z', 'At', o), NOW + 250);
  // The DST case: 01:30 on 2026-11-01 happened twice in New York. With no zone it is refused, with one it is exact.
  refuses(() => whenOf('2026-11-01T01:30:00', 'Due', o), /no time zone.*two instants/);
  refuses(() => whenOf('2026-11-01 01:30:00', 'Due', o), /no time zone/);
  refuses(() => whenOf('11/01/2026 01:30:00', 'Due', o), /ISO time with a zone/);
  assert.equal(whenOf('2026-11-01T01:30:00-04:00', 'Due', o), Date.UTC(2026, 10, 1, 5, 30));
  assert.equal(whenOf('2026-11-01T01:30:00-05:00', 'Due', o), Date.UTC(2026, 10, 1, 6, 30));
  refuses(() => whenOf('2026-02-31T00:00:00Z', 'At', o), /not a real time/);
  refuses(() => whenOf('2026-11-06T25:00:00Z', 'At', o), /not a real time/);
  refuses(() => whenOf('2026-11-06T12:00:00+25:00', 'At', o), /offset/);
  refuses(() => whenOf('1730000000', 'At', o), /13 digits/);
  refuses(() => whenOf('12', 'At', o), /13 digits/);
  refuses(() => whenOf('soon', 'At', o), /ISO time with a zone/);
  refuses(() => whenOf('1999-01-01T00:00:00Z', 'At', o), /before 2001/);
  refuses(() => whenOf('2026-11-08T12:00:00Z', 'At', { now: NOW, ahead: true }), /more than a day in the future/);
  assert.equal(whenOf('2026-11-08T12:00:00Z', 'Due', o), NOW + 2 * DAY);
});

test('text is ASCII: a non-ASCII character is named by its place and code, and nothing is written', () => {
  const w = world();
  refuses(() => job(w, { job: 'caf\u00e9 review' }), /Job must be ASCII \(character 4 is U\+00E9\)/);
  refuses(() => job(w, { id: 'J-\u00e9' }), /Id must be printable ASCII/);
  refuses(() => job(w, { id: 'has space' }), /Id must be printable ASCII with no spaces/);
  refuses(() => job(w, { id: '' }), /Id is required/);
  refuses(() => job(w, { job: '   \n ' }), /Job is empty/);
  refuses(() => job(w, { job: 'j'.repeat(4001) }), /4001 characters; the most is 4000/);
  refuses(() => job(w, { owner: 'o'.repeat(65) }), /Owner is 65 characters/);
  refuses(() => job(w, { session: 'nope' }), /session uuid/);
  refuses(() => sig(w, { text: 'smart \u2019 quote' }), /Text must be ASCII/);
  refuses(() => sig(w, { key: 'k\u00e9' }), /Key must be printable ASCII/);
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM job').get().n + w.db.prepare('SELECT count(*) AS n FROM signal').get().n, 0);
});

// --- job verbs ---------------------------------------------------------------------------------------------------------

test('job upsert: created, then kept; changed fields update; started_at never moves; a field left out stays', () => {
  const w = world();
  const t1 = NOW - 3 * DAY;
  assert.equal(job(w, { started: t1, due: NOW + DAY, session: UUID1 }).action, 'created');
  assert.deepEqual(row(w, 'job', "id = 'J-1'"), { id: 'J-1', owner: 'R', session_id: UUID1, job: 'review the PRs', started_at: t1, due_at: NOW + DAY, done_at: null, done_proof: null, created_by: 'S' });
  // The same call again, and the same call with another started time and another -By: kept, nothing changes.
  assert.equal(job(w, { started: t1, due: NOW + DAY, session: UUID1 }).action, 'kept');
  assert.equal(job(w, { started: NOW, by: 'someone-else', due: NOW + DAY, session: UUID1 }).action, 'kept');
  const same = row(w, 'job', "id = 'J-1'");
  assert.equal(same.started_at, t1);
  assert.equal(same.created_by, 'S');
  // A field left out is left as it was.
  assert.equal(job(w).action, 'kept');
  assert.equal(row(w, 'job', "id = 'J-1'").due_at, NOW + DAY);
  assert.equal(row(w, 'job', "id = 'J-1'").session_id, UUID1);
  const u = job(w, { owner: 'Q', job: 'review the PRs again', due: NOW + 2 * DAY, session: '00000000-0000-4000-8000-000000000002' });
  assert.deepEqual([u.action, u.changed], ['updated', ['owner', 'job', 'session', 'due']]);
  const after = row(w, 'job', "id = 'J-1'");
  assert.deepEqual([after.owner, after.job, after.due_at, after.started_at], ['Q', 'review the PRs again', NOW + 2 * DAY, t1]);
});

test('job upsert: a second job with the same default start is its own row; -Started defaults to now', () => {
  const w = world();
  job(w);
  job(w, { id: 'J-2' });
  assert.deepEqual(w.db.prepare('SELECT id, started_at FROM job ORDER BY id').all().map((r) => [r.id, r.started_at]), [['J-1', NOW], ['J-2', NOW]]);
});

test('job done: needs its proof, keeps the first time on a repeat, refuses another proof, and a done job cannot be upserted', () => {
  const w = world();
  job(w, { started: NOW - DAY });
  refuses(() => doneJob(w.db, { id: 'J-1', by: 'S', proof: '' }, clock(w)), /Proof is empty/);
  refuses(() => doneJob(w.db, { id: 'J-1', by: 'S' }, clock(w)), /Proof is required/);
  refuses(() => doneJob(w.db, { id: 'J-1', proof: 'p' }, clock(w)), /By is required/);
  refuses(() => doneJob(w.db, { id: 'nope', by: 'S', proof: 'p' }, clock(w)), /no job is called nope/);
  const d = doneJob(w.db, { id: 'J-1', by: 'S', proof: 'PR 77 merged' }, clock(w));
  assert.deepEqual([d.action, d.doneAt], ['done', NOW]);
  w.now = NOW + 5 * MIN;
  assert.equal(doneJob(w.db, { id: 'J-1', by: 'S', proof: 'PR 77 merged' }, clock(w)).action, 'kept');
  assert.equal(row(w, 'job', "id = 'J-1'").done_at, NOW, 'the first time stands');
  refuses(() => doneJob(w.db, { id: 'J-1', by: 'S', proof: 'PR 78 merged' }, clock(w)), /already done with another proof/);
  refuses(() => job(w, { job: 'new words' }), /job J-1 is done; a new piece of work takes a new id/);
  refuses(() => job(w), /is done/);
  assert.equal(row(w, 'job', "id = 'J-1'").done_proof, 'PR 77 merged');
});

test('job done: an explicit time before the start is refused; a clock behind the start is lifted to it; a time far ahead is refused', () => {
  const w = world();
  job(w, { started: NOW + 10 * MIN });
  refuses(() => doneJob(w.db, { id: 'J-1', by: 'S', proof: 'p', at: NOW }, clock(w)), /At is before the job started/);
  refuses(() => doneJob(w.db, { id: 'J-1', by: 'S', proof: 'p', at: NOW + 3 * DAY }, clock(w)), /more than a day in the future/);
  assert.equal(row(w, 'job', "id = 'J-1'").done_at, null);
  assert.equal(doneJob(w.db, { id: 'J-1', by: 'S', proof: 'p' }, clock(w)).doneAt, NOW + 10 * MIN);
});

test('job list: open first by due, then done; -Open, -Owner, -Overdue; overdue means open and due before now', () => {
  const w = world();
  job(w, { id: 'late', owner: 'A', due: NOW - MIN });
  job(w, { id: 'soon', owner: 'B', due: NOW + MIN });
  job(w, { id: 'nodue', owner: 'A' });
  job(w, { id: 'fin', owner: 'A', due: NOW - DAY });
  doneJob(w.db, { id: 'fin', by: 'S', proof: 'done' }, clock(w));
  const ids = (q) => listJobs(w.db, q, clock(w)).map((r) => r.id);
  assert.deepEqual(ids({}), ['late', 'soon', 'nodue', 'fin']);
  assert.deepEqual(ids({ open: true }), ['late', 'soon', 'nodue']);
  assert.deepEqual(ids({ owner: 'A' }), ['late', 'nodue', 'fin']);
  assert.deepEqual(ids({ overdue: true }), ['late']);
  assert.deepEqual(ids({ overdue: true, owner: 'B' }), []);
  assert.deepEqual(listJobs(w.db, {}, clock(w)).map((r) => [r.state, r.overdue]), [['open', true], ['open', false], ['open', false], ['done', false]]);
  refuses(() => listJobs(w.db, { owner: 'two words' }, clock(w)), /Owner must be printable ASCII/);
});

// --- signal verbs ------------------------------------------------------------------------------------------------------

test('signal raise: a new key is first_at = last_at and count 1; an open key moves forward and counts; text is updated', () => {
  const w = world();
  const t = NOW - 2 * MIN;
  assert.deepEqual(sig(w, { at: t, owner: 'O' }), { action: 'raised', count: 1 });
  assert.deepEqual(row(w, 'signal', "key = 'ALARM:A'"), { key: 'ALARM:A', kind: 'alarm', owner: 'O', text: 'something is stuck', first_at: t, last_at: t, count: 1, woke_at: null, closed_at: null, closed_by: null });
  assert.deepEqual(sig(w, { at: t + MIN, text: 'still stuck' }), { action: 'updated', count: 2 });
  const r = row(w, 'signal', "key = 'ALARM:A'");
  assert.deepEqual([r.first_at, r.last_at, r.count, r.text, r.owner], [t, t + MIN, 2, 'still stuck', 'O'], 'a raise without an owner keeps the owner');
  assert.equal(sig(w, { at: t + 2 * MIN, owner: 'P' }).action, 'updated');
  assert.equal(row(w, 'signal', "key = 'ALARM:A'").owner, 'P');
});

test('signal raise: the same key and the same -At is a retry and does not count twice; an older time changes nothing, last_at never goes back', () => {
  const w = world();
  sig(w, { at: NOW });
  sig(w, { at: NOW + MIN });
  const before = row(w, 'signal', "key = 'ALARM:A'");
  assert.equal(before.count, 2);
  assert.deepEqual(sig(w, { at: NOW + MIN }), { action: 'kept', count: 2 });
  assert.deepEqual(sig(w, { at: NOW + MIN, text: 'different words, same instant' }), { action: 'kept', count: 2 });
  assert.deepEqual(sig(w, { at: NOW - DAY }), { action: 'kept', count: 2 });
  assert.deepEqual(row(w, 'signal', "key = 'ALARM:A'"), before);
});

test('signal raise: a key is one kind; a time far ahead is refused', () => {
  const w = world();
  sig(w);
  refuses(() => sig(w, { kind: 'other', at: NOW + MIN }), /is of kind alarm, not other/);
  refuses(() => sig(w, { at: NOW + 3 * DAY }), /more than a day in the future/);
  assert.equal(row(w, 'signal', "key = 'ALARM:A'").count, 1);
});

test('signal close and reopen: close is kept when repeated, an unknown key is refused, a raise reopens and keeps counting', () => {
  const w = world();
  sig(w, { at: NOW - 10 * MIN });
  sig(w, { at: NOW - 5 * MIN });
  refuses(() => closeSignal(w.db, { key: 'nope', by: 'S' }, clock(w)), /no signal is called nope/);
  refuses(() => closeSignal(w.db, { key: 'ALARM:A' }, clock(w)), /By is required/);
  assert.equal(closeSignal(w.db, { key: 'ALARM:A', by: 'S' }, clock(w)).action, 'closed');
  assert.deepEqual([row(w, 'signal', "key = 'ALARM:A'").closed_at, row(w, 'signal', "key = 'ALARM:A'").closed_by], [NOW, 'S']);
  w.now = NOW + MIN;
  assert.equal(closeSignal(w.db, { key: 'ALARM:A', by: 'T' }, clock(w)).action, 'kept');
  assert.deepEqual([row(w, 'signal', "key = 'ALARM:A'").closed_at, row(w, 'signal', "key = 'ALARM:A'").closed_by], [NOW, 'S'], 'the first close stands');
  // A stale raise (not after the last time) does not reopen it.
  assert.equal(sig(w, { at: NOW - 5 * MIN }).action, 'kept');
  assert.notEqual(row(w, 'signal', "key = 'ALARM:A'").closed_at, null);
  // A later raise is the same problem come back.
  assert.deepEqual(sig(w, { at: NOW + 2 * MIN }), { action: 'reopened', count: 3 });
  const r = row(w, 'signal', "key = 'ALARM:A'");
  assert.deepEqual([r.closed_at, r.closed_by, r.first_at, r.last_at, r.count], [null, null, NOW - 10 * MIN, NOW + 2 * MIN, 3]);
  assert.equal(closeSignal(w.db, { key: 'ALARM:A', by: 'S' }, clock(w)).action, 'closed');
});

test('signal close: closed_at is never before the last time even when the clock is behind', () => {
  const w = world();
  sig(w, { at: NOW + 3 * MIN });
  closeSignal(w.db, { key: 'ALARM:A', by: 'S' }, clock(w));
  assert.equal(row(w, 'signal', "key = 'ALARM:A'").closed_at, NOW + 3 * MIN);
});

test('signal list: newest first; -Open, -Owner; -Unwoken; -MarkWoke marks exactly the rows it lists and needs -Open', () => {
  const w = world();
  sig(w, { key: 'a', at: NOW - 3 * MIN, owner: 'O' });
  sig(w, { key: 'b', at: NOW - 2 * MIN });
  sig(w, { key: 'c', at: NOW - MIN, owner: 'O' });
  closeSignal(w.db, { key: 'c', by: 'S' }, clock(w));
  const keys = (q) => listSignals(w.db, q, clock(w)).map((r) => r.key);
  assert.deepEqual(keys({}), ['c', 'b', 'a']);
  assert.deepEqual(keys({ open: true }), ['b', 'a']);
  assert.deepEqual(keys({ owner: 'O' }), ['c', 'a']);
  assert.deepEqual(keys({ open: true, unwoken: true }), ['b', 'a']);
  refuses(() => listSignals(w.db, { markWoke: true }, clock(w)), /MarkWoke needs Open/);
  refuses(() => listSignals(w.db, { open: true, at: NOW }, clock(w)), /needs MarkWoke/);
  // Mark only the owner O's open signals.
  const marked = listSignals(w.db, { open: true, owner: 'O', markWoke: true }, clock(w));
  assert.deepEqual(marked.map((r) => [r.key, r.woke_at]), [['a', NOW]]);
  assert.equal(row(w, 'signal', "key = 'a'").woke_at, NOW);
  assert.equal(row(w, 'signal', "key = 'b'").woke_at, null);
  assert.equal(row(w, 'signal', "key = 'c'").woke_at, null);
  assert.deepEqual(keys({ open: true, unwoken: true }), ['b']);
  // It happens again after the wake: it needs a wake again, which a reopened signal does too.
  w.now = NOW + 10 * MIN;
  sig(w, { key: 'a', at: NOW + 5 * MIN });
  assert.deepEqual(keys({ open: true, unwoken: true }), ['a', 'b']);
  sig(w, { key: 'c', at: NOW + 6 * MIN });
  assert.deepEqual(keys({ open: true, unwoken: true }), ['c', 'a', 'b']);
  const all = listSignals(w.db, { open: true, unwoken: true, markWoke: true, at: NOW + 7 * MIN }, clock(w));
  assert.deepEqual(all.map((r) => r.woke_at), [NOW + 7 * MIN, NOW + 7 * MIN, NOW + 7 * MIN]);
  assert.deepEqual(keys({ open: true, unwoken: true }), []);
});

test('signal prune: needs Days (1 or more), deletes only closed signals closed longer ago than that, never open ones, says how many', () => {
  const w = world();
  for (const bad of [undefined, null, '', '0', '-3', '1.5', 'x', '1 ', '100000']) refuses(() => pruneSignals(w.db, { days: bad }, clock(w)), /Days is required/);
  rawSignal(w.db, { key: 'old-closed', closed_at: NOW - 10 * DAY, closed_by: 'S' });
  rawSignal(w.db, { key: 'edge-closed', closed_at: NOW - 7 * DAY, closed_by: 'S' });
  rawSignal(w.db, { key: 'new-closed', closed_at: NOW - 6 * DAY, closed_by: 'S' });
  rawSignal(w.db, { key: 'old-open', first_at: NOW - 30 * DAY, last_at: NOW - 30 * DAY });
  assert.deepEqual(pruneSignals(w.db, { days: '7' }, clock(w)), { pruned: 1 });
  assert.deepEqual(w.db.prepare('SELECT key FROM signal ORDER BY key').all().map((r) => r.key), ['edge-closed', 'new-closed', 'old-open']);
  assert.deepEqual(pruneSignals(w.db, { days: 7 }, clock(w)), { pruned: 0 });
  assert.deepEqual(pruneSignals(w.db, { days: '1' }, clock(w)), { pruned: 2 });
  assert.deepEqual(w.db.prepare('SELECT key FROM signal').all().map((r) => r.key), ['old-open']);
});

test('prune does not touch jobs, done or open', () => {
  const w = world();
  rawJob(w.db, { id: 'old-done', started_at: NOW - 90 * DAY, done_at: NOW - 80 * DAY, done_proof: 'p' });
  pruneSignals(w.db, { days: '1' }, clock(w));
  assert.equal(w.db.prepare('SELECT count(*) AS n FROM job').get().n, 1);
});

// --- the command line --------------------------------------------------------------------------------------------------

test('cli: a full round through the verbs, one ASCII line each, exit 0 for repeats', () => {
  const w = world();
  w.db.close();
  const run = (...a) => cli(w, a);
  assert.deepEqual(run('job', 'upsert', '--id', 'J-1', '--owner', 'R', '--job', 'review the PRs', '--by', 'S', '--due', '2026-11-06T13:00:00Z'), { code: 0, out: ['created J-1'], err: [] });
  // 09:00 at -05:00 is 14:00Z: a different instant, so an update; the same instant spelt another way is kept.
  assert.deepEqual(run('job', 'upsert', '--id', 'J-1', '--owner', 'R', '--job', 'review the PRs', '--by', 'S', '--due', '2026-11-06T09:00:00-05:00').out, ['updated J-1 (due)']);
  assert.deepEqual(run('job', 'upsert', '--id', 'J-1', '--owner', 'R', '--job', 'review the PRs', '--by', 'S', '--due', '2026-11-06T14:00:00Z').out, ['kept J-1']);
  assert.deepEqual(run('job', 'list', '--open', '--overdue').out, ['no jobs']);
  assert.deepEqual(run('job', 'list', '--owner', 'NOBODY').out, ['no jobs']);
  w.now = NOW + 3 * 60 * MIN;
  const late = run('job', 'list', '--overdue');
  assert.match(late.out[0], /^J-1 R overdue started=2026-11-06T12:00:00.000Z due=2026-11-06T14:00:00.000Z done=- \| review the PRs$/);
  assert.equal(JSON.parse(run('job', 'list', '--json').out[0]).jobs[0].overdue, true);
  assert.deepEqual(run('job', 'done', '--id', 'J-1', '--proof', 'PR 5', '--by', 'S').out, ['done J-1']);
  assert.deepEqual(run('job', 'done', '--id', 'J-1', '--proof', 'PR 5', '--by', 'S').out, ['kept J-1']);
  const other = run('job', 'done', '--id', 'J-1', '--proof', 'PR 6', '--by', 'S');
  assert.deepEqual([other.code, other.err], [1, ['refused: job J-1 is already done with another proof; a done job is final']]);
  assert.deepEqual(run('signal', 'raise', '--key', 'K:1', '--kind', 'alarm', '--text', 'stuck', '--at', '2026-11-06T12:00:00Z').out, ['raised K:1 (count 1)']);
  assert.deepEqual(run('signal', 'raise', '--key', 'K:1', '--kind', 'alarm', '--text', 'stuck', '--at', '2026-11-06T12:00:00Z').out, ['kept K:1']);
  assert.deepEqual(run('signal', 'raise', '--key', 'K:1', '--kind', 'alarm', '--text', 'stuck', '--at', '2026-11-06T12:01:00Z').out, ['updated K:1 (count 2)']);
  assert.match(run('signal', 'list', '--open', '--mark-woke').out[0], /^K:1 alarm - open count=2 first=.* woke=2026-11-06T15:00:00.000Z \| stuck$/);
  assert.deepEqual(run('signal', 'list', '--open', '--unwoken').out, ['no signals']);
  assert.deepEqual(run('signal', 'close', '--key', 'K:1', '--by', 'S').out, ['closed K:1']);
  assert.deepEqual(run('signal', 'close', '--key', 'K:1', '--by', 'S').out, ['kept K:1']);
  assert.deepEqual(run('signal', 'raise', '--key', 'K:1', '--kind', 'alarm', '--text', 'back', '--at', '2026-11-06T14:30:00Z').out, ['reopened K:1 (count 3)']);
  assert.deepEqual(run('signal', 'close', '--key', 'K:1', '--by', 'S').out, ['closed K:1']);
  assert.deepEqual(run('signal', 'prune', '--days', '3').out, ['pruned 0 closed signals closed more than 3 days ago']);
  w.now += 4 * DAY;
  assert.deepEqual(run('signal', 'prune', '--days', '3').out, ['pruned 1 closed signal closed more than 3 days ago']);
  const refused = run('signal', 'prune');
  assert.deepEqual([refused.code, refused.err], [1, ['refused: signal prune: --days is required']]);
  for (const r of [run('job', 'list'), run('signal', 'list', '--json')]) assert.equal(/[^\x20-\x7E]/.test(r.out.join('')), false);
});

test('cli: a refusal is one line, exit 1, and nothing is written', () => {
  const w = world();
  w.db.close();
  const cases = [
    [['job', 'upsert', '--id', 'J-1', '--owner', 'R', '--job', 'caf\u00e9', '--by', 'S'], /^refused: Job must be ASCII \(character 4 is U\+00E9\)/],
    [['job', 'upsert', '--id', 'J-1', '--owner', 'R', '--job', 'x', '--by', 'S', '--due', '2026-11-01T01:30:00'], /^refused: Due has no time zone/],
    [['job', 'upsert', '--id', 'J-1', '--owner', 'R', '--job', 'x', '--by', 'S', '--started', 'yesterday'], /^refused: Started must be/],
    [['job', 'upsert', '--id', 'J-1', '--owner', 'R', '--by', 'S'], /^refused: job upsert: give exactly one of --job and --file$/],
    [['job', 'upsert', '--id', 'J-1', '--owner', 'R', '--job', 'x', '--file', 'C:\\x.txt', '--by', 'S'], /give exactly one of --job and --file/],
    [['job', 'upsert', '--id', 'J-1', '--job', 'x', '--by', 'S'], /^refused: job upsert: --owner is required$/],
    [['job', 'upsert', '--id', 'J-1', '--owner', 'R', '--job', 'x', '--by', 'S', '--bogus', '1'], /unknown argument --bogus/],
    [['job', 'upsert', '--id', 'J-1', '--id', 'J-2', '--owner', 'R', '--job', 'x', '--by', 'S'], /--id given twice/],
    [['job', 'upsert', '--id', 'J-1', '--owner', 'R', '--job'], /--job needs a value/],
    [['job', 'done', '--id', 'nope', '--proof', 'p', '--by', 'S'], /^refused: no job is called nope$/],
    [['signal', 'raise', '--key', 'k', '--kind', 'a', '--text', 'x', '--at', '2026-11-06T09:00:00'], /^refused: At has no time zone/],
    [['signal', 'close', '--key', 'nope', '--by', 'S'], /^refused: no signal is called nope$/],
    [['signal', 'prune', '--days', '0'], /^refused: Days is required and must be a whole number of 1 or more/],
    [['signal', 'list', '--mark-woke'], /^refused: MarkWoke needs Open/],
    [['job', 'list', '--caf\u00e9'], /^refused: job list: unknown argument --caf\\u00e9$/],
    [['signal'], /usage/],
    [['job', 'frob'], /usage/],
    [[], /usage/],
  ];
  for (const [argv, re] of cases) {
    const r = cli(w, argv);
    assert.equal(r.code, 1, argv.join(' '));
    assert.equal(r.err.length, 1, argv.join(' '));
    assert.match(r.err[0], re, argv.join(' '));
    assert.deepEqual(r.out, []);
  }
  const db = openStore(w.file);
  handles.push(db);
  assert.equal(db.prepare('SELECT count(*) AS n FROM job').get().n + db.prepare('SELECT count(*) AS n FROM signal').get().n, 0);
});

test('cli: long text comes from -File; a BOM, CRLF and trailing newlines are dropped; UTF-16, non-ASCII, a relative path and a huge file are refused in words', () => {
  const w = world();
  w.db.close();
  const f = (name, bytes) => { const p = path.join(w.dir, name); fs.writeFileSync(p, bytes); return p; };
  const good = f('job.txt', Buffer.from('\uFEFFfirst line\r\nsecond line\r\n\r\n', 'utf8'));
  assert.deepEqual(cli(w, ['job', 'upsert', '--id', 'J-1', '--owner', 'R', '--file', good, '--by', 'S']).out, ['created J-1']);
  const db = openStore(w.file);
  handles.push(db);
  assert.equal(db.prepare("SELECT job FROM job WHERE id = 'J-1'").get().job, 'first line\nsecond line');
  assert.deepEqual(cli(w, ['job', 'upsert', '--id', 'J-1', '--owner', 'R', '--job', 'first line\nsecond line', '--by', 'S']).out, ['kept J-1'], 'the same words from the command line are the same text');
  assert.deepEqual(cli(w, ['job', 'done', '--id', 'J-1', '--file', f('proof.txt', 'PR 5, merged'), '--by', 'S']).out, ['done J-1']);
  assert.deepEqual(cli(w, ['signal', 'raise', '--key', 'k', '--kind', 'a', '--file', f('sig.txt', 'a signal')]).out, ['raised k (count 1)']);
  const utf16 = cli(w, ['signal', 'raise', '--key', 'k2', '--kind', 'a', '--file', f('u16.txt', Buffer.from('\uFEFFhello', 'utf16le'))]);
  assert.deepEqual([utf16.code, utf16.err], [1, ['refused: --file is UTF-16 text; save it as ASCII or UTF-8']]);
  const accent = cli(w, ['signal', 'raise', '--key', 'k2', '--kind', 'a', '--file', f('acc.txt', 'caf\u00e9')]);
  assert.match(accent.err[0], /^refused: Text must be ASCII \(character 4 is U\+00E9\)/);
  const bad8 = cli(w, ['signal', 'raise', '--key', 'k2', '--kind', 'a', '--file', f('bad8.txt', Buffer.from([0x61, 0xff, 0xfe, 0x62]))]);
  assert.match(bad8.err[0], /^refused: --file is not UTF-8 text/);
  assert.match(cli(w, ['signal', 'raise', '--key', 'k2', '--kind', 'a', '--file', f('empty.txt', '  \n')]).err[0], /^refused: Text is empty/);
  assert.match(cli(w, ['signal', 'raise', '--key', 'k2', '--kind', 'a', '--file', f('big.txt', 'x'.repeat(65537))]).err[0], /^refused: --file is 65537 bytes; the most is 65536/);
  assert.match(cli(w, ['signal', 'raise', '--key', 'k2', '--kind', 'a', '--file', f('long.txt', 'x'.repeat(4001))]).err[0], /^refused: Text is 4001 characters/);
  assert.match(cli(w, ['signal', 'raise', '--key', 'k2', '--kind', 'a', '--file', 'rel.txt']).err[0], /^refused: --file must be an absolute path/);
  assert.match(cli(w, ['signal', 'raise', '--key', 'k2', '--kind', 'a', '--file', path.join(w.dir, 'missing.txt')]).err[0], /^refused: --file cannot be read: missing.txt/);
  assert.match(cli(w, ['signal', 'raise', '--key', 'k2', '--kind', 'a', '--file', w.dir]).err[0], /^refused: --file is not a file/);
  assert.equal(db.prepare("SELECT count(*) AS n FROM signal WHERE key = 'k2'").get().n, 0);
});

test('cli: no fleet.db is exit 4 and makes no file; no home is exit 2', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-db-jobs-none-'));
  dirs.push(dir);
  const w = { dir, now: NOW };
  const r = cli(w, ['job', 'list']);
  assert.deepEqual([r.code, r.err], [4, ['fleet.db does not exist yet (run horde db init)']]);
  for (const argv of [['signal', 'raise', '--key', 'k', '--kind', 'a', '--text', 'x'], ['job', 'upsert', '--id', 'j', '--owner', 'o', '--job', 'x', '--by', 'b'], ['signal', 'prune', '--days', '3']]) {
    assert.equal(cli(w, argv).code, 4);
  }
  assert.deepEqual(fs.readdirSync(dir), [], 'nothing was made, not even the empty file or a WAL');
  // An empty environment falls to the profile's pointer file, which own-profile.mjs made empty: no home, not a default one.
  const errs = [];
  assert.equal(main(['job', 'list'], {}, () => {}, (s) => errs.push(s), {}), 2);
  assert.match(errs[0], /^fleet\.db: HORDE_HOME is not set and there is no pointer file/);
});

test('cli: a relative home is exit 2', () => {
  const errs = [];
  assert.equal(main(['job', 'list'], { HORDE_HOME: 'relative\\home' }, () => {}, (s) => errs.push(s), {}), 2);
  assert.match(errs[0], /^fleet\.db: HORDE_HOME must be an absolute path/);
});

test('cli: a newer or an older schema is refused in words, not migrated and not written', () => {
  const w = world();
  w.db.exec('PRAGMA user_version = 9');
  w.db.close();
  const newer = cli(w, ['job', 'upsert', '--id', 'J-1', '--owner', 'R', '--job', 'x', '--by', 'S']);
  assert.deepEqual([newer.code, newer.err], [1, ['fleet.db: fleet.db is version 9, newer than this code (8): update Horde']]);
  const raw = new DatabaseSync(w.file);
  raw.exec('PRAGMA user_version = 7');
  raw.exec('DROP TABLE job; DROP TABLE signal');
  raw.close();
  for (const argv of [['job', 'upsert', '--id', 'J-1', '--owner', 'R', '--job', 'x', '--by', 'S'], ['signal', 'list'], ['signal', 'list', '--open', '--mark-woke']]) {
    const older = cli(w, argv);
    assert.deepEqual([older.code, older.err], [1, ['fleet.db: fleet.db is version 7 and needs migrating; run horde db init']], argv.join(' '));
  }
  const check = new DatabaseSync(w.file, { readOnly: true });
  assert.equal(check.prepare('PRAGMA user_version').get().user_version, 7);
  assert.equal(check.prepare("SELECT count(*) AS n FROM sqlite_master WHERE name = 'job'").get().n, 0);
  check.close();
});

test('cli: a locked database is exit 3, "fleet.db busy", after the short wait, never a hang', () => {
  const w = world();
  w.db.exec('BEGIN IMMEDIATE');
  const t0 = Date.now();
  const r = cli(w, ['job', 'upsert', '--id', 'J-1', '--owner', 'R', '--job', 'x', '--by', 'S'], { HORDE_JOBS_BUSY_MS: '100' });
  assert.deepEqual([r.code, r.err], [3, ['fleet.db busy']]);
  assert.ok(Date.now() - t0 < 2000, "the wait is the short one asked for, not the default");
  // A reader is not blocked by a writer in WAL mode.
  assert.equal(cli(w, ['job', 'list'], { HORDE_JOBS_BUSY_MS: '100' }).code, 0);
  w.db.exec('ROLLBACK');
  assert.equal(cli(w, ['job', 'upsert', '--id', 'J-1', '--owner', 'R', '--job', 'x', '--by', 'S'], { HORDE_JOBS_BUSY_MS: '100' }).code, 0);
});

test('cli: parseFlags takes a value that starts with a dash and refuses what it does not know', () => {
  assert.deepEqual(parseFlags('signal raise', ['--key', 'k', '--kind', 'a', '--text', '-- not a flag']), { '--key': 'k', '--kind': 'a', '--text': '-- not a flag' });
  assert.throws(() => parseFlags('signal list', ['--open', '--open']), /given twice/);
  assert.throws(() => parseFlags('job list', ['--mark-woke']), /unknown argument/);
});

test('db check still passes on a file with jobs and signals in every state', () => {
  const w = world();
  job(w);
  job(w, { id: 'J-2' });
  doneJob(w.db, { id: 'J-2', by: 'S', proof: 'p' }, clock(w));
  sig(w);
  sig(w, { key: 'K2', at: NOW + MIN });
  closeSignal(w.db, { key: 'K2', by: 'S' }, clock(w));
  assert.deepEqual(findProblems(w.db), []);
});
