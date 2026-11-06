// `horde db sync` (fleet-db/sync.mjs), attacked: the saved sources are never defaulted and a sync without them
// refuses naming the -Save form; the files step runs only when its last good run is 5 minutes old (or with --force);
// a second sync adds nothing; a new ledger line, changelog line or card appears after one sync; a failed run keeps
// lastOkAt and records itself; a timeout noted by the caller is recorded without moving lastOkAt; the state keeps keys
// it does not know (piece 2's sessions step); `db status` says when the files were last synced. Temp homes only: the
// real files are never named and the real home is never read.
import './own-profile.mjs';
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { openStore } from '../store.mjs';
import { main } from '../cli.mjs';
import { FILES_EVERY_MS, SAVE_FORM, describeSync, filesDue, parseSyncArgs, readSettings, readState, saveSettings, settingsFile, stateFile, syncMain } from '../sync.mjs';

const dirs = [];
after(() => {
  for (const d of dirs) fs.rmSync(d, { recursive: true, force: true });
});

function tempDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-db-sync-'));
  dirs.push(dir); // before anything can throw: a mutant must not leak its folder
  return dir;
}

const T0 = Date.parse('2026-11-02T12:00:00Z');
const MIN = 60 * 1000;

function cardText(orc, lane, doing) {
  return ['horde-orc-status 1', 'orc: ' + orc, 'lane: ' + lane, 'doing: ' + doing, 'finished: a part', 'blocked: no'].join('\n') + '\n';
}

function writeCard(cards, folder, orc, lane, doing) {
  fs.mkdirSync(path.join(cards, folder), { recursive: true });
  const file = path.join(cards, folder, 'status.txt');
  fs.writeFileSync(file, cardText(orc, lane, doing));
  const when = new Date('2026-11-02T10:00:00Z');
  fs.utimesSync(file, when, when);
}

const ledgerLine = (o) => JSON.stringify(o) + '\n';
const OPENED = { ts: '2026-11-01T10:00:00Z', task: 'T-0001', event: 'opened', title: 'First', source: 'founder', lane: 'C', prio: 2, parent: null, by: 'C' };
const STARTED = { ts: '2026-11-01T11:00:00Z', task: 'T-0001', event: 'started', by: 'C' };
const CHANGE = { v: 1, id: '20261101T120000Z-01', ts: '2026-11-01T12:00:00Z', kind: 'note', area: 'Lane C', title: 'one', text: 'Happened: a', lane: 'C', task: 'T-0001' };

// A home with a migrated fleet.db and the sources of a small fleet, saved.
function world() {
  const home = tempDir();
  openStore(path.join(home, 'fleet.db')).close();
  const files = tempDir();
  const cards = path.join(files, 'orcs');
  writeCard(cards, 'form-fill', 'C', 'Form fill', 'working on the list');
  const ledger = path.join(files, 'tasks.jsonl');
  fs.writeFileSync(ledger, ledgerLine(OPENED) + ledgerLine(STARTED));
  const changelog = path.join(files, 'changelog.jsonl');
  fs.writeFileSync(changelog, JSON.stringify(CHANGE) + '\n');
  const sources = { ledger, changelog, cards };
  return { home, files, cards, ledger, changelog, sources, env: { HORDE_HOME: home } };
}

function run(env, args, at = T0) {
  const out = [];
  const err = [];
  const code = syncMain(args, env, (s) => out.push(s), (s) => err.push(s), { now: () => at });
  return { code, out: out.join('\n'), err: err.join('\n') };
}

function count(home, table) {
  const db = new DatabaseSync(path.join(home, 'fleet.db'), { readOnly: true });
  try {
    return db.prepare('SELECT count(*) AS n FROM ' + table).get().n;
  } finally {
    db.close();
  }
}

const counts = (home) => Object.fromEntries(['task_event', 'changelog_entry', 'orc', 'orc_status', 'task'].map((t) => [t, count(home, t)]));

test('a sync with no saved sources refuses and names the -Save form; nothing is made', () => {
  const w = world();
  const r = run(w.env, []);
  assert.equal(r.code, 1);
  assert.match(r.err, /no sources are saved/);
  assert.ok(r.err.includes(SAVE_FORM), 'the refusal names the -Save form');
  assert.equal(fs.existsSync(stateFile(w.home)), false, 'a refusal leaves no state');
  assert.equal(count(w.home, 'task_event'), 0);
});

test('no home at all is exit 2, as every fleet.db verb', () => {
  const r = run({}, ['--force']);
  assert.equal(r.code, 2);
  assert.match(r.err, /^fleet\.db: /);
});

test('--save writes the settings whole (schema 1, absolute paths) and then syncs', () => {
  const w = world();
  const r = run(w.env, ['--save', '--ledger', w.ledger, '--changelog', w.changelog, '--cards', w.cards]);
  assert.equal(r.code, 0, r.err);
  const saved = JSON.parse(fs.readFileSync(settingsFile(w.home), 'utf8'));
  assert.deepEqual(saved, { schema: 1, ledger: w.ledger, changelog: w.changelog, cards: w.cards });
  assert.deepEqual(readSettings(w.home), w.sources);
  assert.deepEqual(fs.readdirSync(path.dirname(settingsFile(w.home))).filter((n) => n.includes('.tmp-')), [], 'no temp file is left beside it');
  assert.match(r.out, /^sync: files ran, /);
  assert.ok(count(w.home, 'task_event') >= 2);
});

test('--save runs inside the 5 minutes too: new sources do not wait out the pace of the old ones', () => {
  const w = world();
  const first = run(w.env, ['--save', '--ledger', w.ledger, '--cards', w.cards]);
  assert.equal(first.code, 0, first.err);
  assert.equal(count(w.home, 'changelog_entry'), 0, 'CONTROL: the changelog is not a source yet');
  const r = run(w.env, ['--save', '--ledger', w.ledger, '--cards', w.cards, '--changelog', w.changelog]);
  assert.equal(r.code, 0, r.err);
  assert.match(r.out, /^sync: files ran, /);
  assert.ok(count(w.home, 'changelog_entry') >= 1);
});

test('the sources are never defaulted: a relative path is refused on save and in a hand-made file', () => {
  const w = world();
  assert.throws(() => saveSettings(w.home, { ledger: 'tasks.jsonl' }), /must be absolute/);
  const r = run(w.env, ['--save', '--ledger', 'tasks.jsonl']);
  assert.equal(r.code, 1);
  assert.match(r.err, /must be absolute/);
  assert.equal(fs.existsSync(settingsFile(w.home)), false);
  fs.mkdirSync(path.dirname(settingsFile(w.home)), { recursive: true });
  fs.writeFileSync(settingsFile(w.home), JSON.stringify({ schema: 1, ledger: 'tasks.jsonl' }));
  assert.throws(() => readSettings(w.home), /not an absolute path/);
  fs.writeFileSync(settingsFile(w.home), JSON.stringify({ schema: 1, registry: w.files }));
  assert.throws(() => readSettings(w.home), /unknown source registry/);
  fs.writeFileSync(settingsFile(w.home), JSON.stringify({ schema: 2, ledger: w.ledger }));
  assert.throws(() => readSettings(w.home), /not a schema 1 settings file/);
  fs.writeFileSync(settingsFile(w.home), '{ not json');
  assert.throws(() => readSettings(w.home), /not a schema 1 settings file/);
  fs.writeFileSync(settingsFile(w.home), JSON.stringify({ schema: 1 }));
  assert.throws(() => readSettings(w.home), /names no source/);
});

test('arguments: source flags only with --save, none twice, no registry, decisions or lots, nothing unknown', () => {
  assert.throws(() => parseSyncArgs(['--ledger', 'a']), /only taken with -Save/);
  assert.throws(() => parseSyncArgs(['--save']), /needs at least one of/);
  assert.throws(() => parseSyncArgs(['--save', '--ledger', 'a', '--ledger', 'b']), /given twice/);
  assert.throws(() => parseSyncArgs(['--save', '--ledger']), /needs a path/);
  assert.throws(() => parseSyncArgs(['--save', '--ledger', '--cards']), /needs a path/);
  for (const flag of ['--registry', '--decisions', '--lots', '--dry-run', '--bogus']) {
    assert.throws(() => parseSyncArgs(['--save', '--ledger', 'a', flag, 'x']), /unknown argument/, flag);
  }
  assert.throws(() => parseSyncArgs(['--note-timeout', 'soon']), /needs the milliseconds/);
  assert.deepEqual(parseSyncArgs(['--force']), { force: true, save: false, sources: {}, noteTimeoutMs: null });
});

test('cadence: the files step is skipped under 5 minutes, runs at 5, and always runs with --force', () => {
  const w = world();
  saveSettings(w.home, w.sources);
  const first = run(w.env, [], T0);
  assert.equal(first.code, 0, first.err);
  assert.match(first.out, /files ran/);
  const after1 = counts(w.home);
  // A new ledger line, so a run that wrongly happened would show.
  fs.appendFileSync(w.ledger, ledgerLine({ ts: '2026-11-01T12:00:00Z', task: 'T-0001', event: 'progress', by: 'C', on: 'something' }));
  const early = run(w.env, [], T0 + FILES_EVERY_MS - 1000);
  assert.equal(early.code, 0);
  assert.match(early.out, /^sync: files skipped \(last ok 299 s ago, runs every 5 min\)$/);
  assert.deepEqual(counts(w.home), after1, 'a skipped step writes nothing');
  const onTime = run(w.env, [], T0 + FILES_EVERY_MS);
  assert.match(onTime.out, /files ran, task_event \+1/);
  assert.equal(count(w.home, 'task_event'), after1.task_event + 1);
  fs.appendFileSync(w.ledger, ledgerLine({ ts: '2026-11-01T13:00:00Z', task: 'T-0001', event: 'progress', by: 'C', on: 'more' }));
  assert.match(run(w.env, [], T0 + FILES_EVERY_MS + 1000).out, /files skipped/);
  const forced = run(w.env, ['--force'], T0 + FILES_EVERY_MS + 2000);
  assert.match(forced.out, /files ran, task_event \+1/);
});

test('filesDue: never run, 5 minutes, a clock gone back, and force', () => {
  const never = readState(tempDir());
  assert.equal(filesDue(never, T0, false), true);
  const ran = { files: { lastOkAt: T0 } };
  assert.equal(filesDue(ran, T0 + FILES_EVERY_MS - 1, false), false);
  assert.equal(filesDue(ran, T0 + FILES_EVERY_MS, false), true);
  assert.equal(filesDue(ran, T0 - 1, false), true, 'a clock that went back must not park the sync for hours');
  assert.equal(filesDue(ran, T0 + 1, true), true);
});

test('a second sync adds nothing, and the rows stay backfill 1 (the hash holds it)', () => {
  const w = world();
  saveSettings(w.home, w.sources);
  assert.equal(run(w.env, [], T0).code, 0);
  const once = counts(w.home);
  assert.ok(once.task_event >= 2 && once.changelog_entry === 1 && once.orc === 1 && once.orc_status === 1, JSON.stringify(once));
  const again = run(w.env, ['--force'], T0 + MIN);
  assert.match(again.out, /^sync: files ran, no rows added$/);
  assert.deepEqual(counts(w.home), once);
  const db = new DatabaseSync(path.join(w.home, 'fleet.db'), { readOnly: true });
  try {
    for (const t of ['task_event', 'changelog_entry', 'orc_status']) {
      assert.deepEqual(db.prepare('SELECT DISTINCT backfill FROM ' + t).all().map((r) => r.backfill), [1], t);
    }
  } finally {
    db.close();
  }
});

test('a new ledger line, changelog line and card appear after one sync', () => {
  const w = world();
  saveSettings(w.home, w.sources);
  run(w.env, [], T0);
  const before = counts(w.home);
  fs.appendFileSync(w.ledger, ledgerLine({ ts: '2026-11-02T09:00:00Z', task: 'T-0001', event: 'progress', by: 'C', on: 'new work' }));
  fs.appendFileSync(w.changelog, JSON.stringify({ ...CHANGE, id: '20261102T090000Z-01', ts: '2026-11-02T09:00:00Z', title: 'two' }) + '\n');
  writeCard(w.cards, 'research', 'E', 'Research', 'reading the notes');
  const r = run(w.env, [], T0 + 5 * MIN);
  assert.equal(r.code, 0, r.err);
  assert.equal(count(w.home, 'task_event'), before.task_event + 1);
  assert.equal(count(w.home, 'changelog_entry'), before.changelog_entry + 1);
  assert.equal(count(w.home, 'orc'), before.orc + 1);
  assert.equal(count(w.home, 'orc_status'), before.orc_status + 1);
  assert.match(r.out, /task_event \+1/);
  assert.match(r.out, /changelog_entry \+1/);
  assert.match(r.out, /orc_status \+1/);
});

test('a failed run keeps lastOkAt, records itself and is tried again on the next tick; the database is unchanged', () => {
  const w = world();
  saveSettings(w.home, w.sources);
  run(w.env, [], T0);
  const good = counts(w.home);
  fs.rmSync(w.ledger);
  const r = run(w.env, [], T0 + 5 * MIN);
  assert.equal(r.code, 1);
  assert.match(r.err, /^fleet\.db: /);
  const st = readState(w.home).files;
  assert.deepEqual([st.lastOkAt, st.lastRunAt, st.lastResult], [T0, T0 + 5 * MIN, 'failed']);
  assert.deepEqual(counts(w.home), good);
  // Next tick: still due (lastOkAt did not move), and it recovers.
  fs.writeFileSync(w.ledger, ledgerLine(OPENED) + ledgerLine(STARTED));
  const next = run(w.env, [], T0 + 6 * MIN);
  assert.equal(next.code, 0, next.err);
  assert.equal(readState(w.home).files.lastResult, 'ok');
});

test('a missing fleet.db is a failed run that says to run horde db init, and makes no database', () => {
  const w = world();
  saveSettings(w.home, w.sources);
  fs.rmSync(path.join(w.home, 'fleet.db'));
  const r = run(w.env, [], T0);
  assert.equal(r.code, 1);
  assert.match(r.err, /run horde db init/);
  assert.equal(fs.existsSync(path.join(w.home, 'fleet.db')), false);
  assert.equal(readState(w.home).files.lastResult, 'failed');
});

test('--note-timeout records the kill without moving lastOkAt and without opening the database', () => {
  const w = world();
  saveSettings(w.home, w.sources);
  run(w.env, [], T0);
  fs.rmSync(path.join(w.home, 'fleet.db'));
  const r = run(w.env, ['--note-timeout', '50123'], T0 + 5 * MIN);
  assert.equal(r.code, 0, r.err);
  const st = readState(w.home).files;
  assert.deepEqual([st.lastOkAt, st.lastRunAt, st.lastResult, st.lastMs], [T0, T0 + 5 * MIN, 'timeout', 50123]);
  assert.equal(fs.existsSync(path.join(w.home, 'fleet.db')), false);
});

test('the state keeps keys it does not know, so a later step (sessions) is not wiped by the files step', () => {
  const w = world();
  saveSettings(w.home, w.sources);
  fs.writeFileSync(stateFile(w.home), JSON.stringify({ schema: 1, sessions: { lastOkAt: 7 }, files: {} }));
  run(w.env, [], T0);
  const raw = JSON.parse(fs.readFileSync(stateFile(w.home), 'utf8'));
  assert.deepEqual(raw.sessions, { lastOkAt: 7 });
  assert.equal(raw.files.lastResult, 'ok');
  assert.equal(raw.files.lastOkAt, T0);
  assert.equal(raw.schema, 1);
});

test('a damaged state file costs one early run, never a refusal', () => {
  const w = world();
  saveSettings(w.home, w.sources);
  fs.writeFileSync(stateFile(w.home), 'garbage{');
  assert.equal(run(w.env, [], T0).code, 0);
  assert.equal(readState(w.home).files.lastResult, 'ok');
});

test('db status ends with the last sync: never synced, then the time of the last good run', () => {
  const w = world();
  const s0 = [];
  assert.equal(main(['status'], w.env, (l) => s0.push(l), () => {}), 0);
  assert.equal(s0[s0.length - 1], 'sync: never synced');
  saveSettings(w.home, w.sources);
  run(w.env, [], T0);
  const s1 = [];
  main(['status'], w.env, (l) => s1.push(l), () => {});
  assert.equal(s1[s1.length - 1], 'sync: files last ok 2026-11-02T12:00:00.000Z, last run ok at 2026-11-02T12:00:00.000Z');
  assert.equal(describeSync(w.home), s1[s1.length - 1]);
});

test('db sync through the cli entry point runs the same step', () => {
  const w = world();
  saveSettings(w.home, w.sources);
  const out = [];
  const err = [];
  assert.equal(main(['sync', '--force'], w.env, (l) => out.push(l), (l) => err.push(l)), 0, err.join('\n'));
  assert.match(out.join('\n'), /^sync: files ran, /);
  const bad = [];
  assert.equal(main(['sync', 'extra'], w.env, () => {}, (l) => bad.push(l)), 1);
  assert.match(bad.join('\n'), /unknown argument extra/);
});
