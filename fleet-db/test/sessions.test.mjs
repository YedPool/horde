// The sessions step of `horde db sync` (fleet-db/sessions.mjs, migration 7), attacked. Each activity rule of the overseer's
// transcript reader has a case of its own (the reason for each is in sessions.mjs); the byte offset is attacked with a
// half-written line, a replaced file, the first-read cap, the per-session cap and a catch-up over two ticks; liveness with
// a terminal that cannot be listed (UNKNOWN, never dead), a closed one, a pane move, two records claiming one pane; and a
// second identical tick must write nothing but state_checked_at. Temp homes only: no real terminal, registry or
// transcript is named, and nothing here starts a process.
import './own-profile.mjs';
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { openStore } from '../store.mjs';
import { MIGRATIONS, SCHEMA_VERSION } from '../schema.mjs';
import {
  FIRST_READ_BYTES, SESSION_READ_BYTES, applyRecords, emptyActivity, judgeLiveness, parseSnapshot, readTranscript, runSessionsStep,
  stateOf, subagentActivity,
} from '../sessions.mjs';
import { describeSessions, parseSyncArgs, readState, saveSettings, syncMain } from '../sync.mjs';
import { main } from '../cli.mjs';

const dirs = [];
const handles = [];
after(() => {
  for (const db of handles) {
    try { db.close(); } catch { /* closed by the test */ }
  }
  for (const d of dirs) fs.rmSync(d, { recursive: true, force: true });
});

function tempDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-db-sessions-'));
  dirs.push(dir); // before anything can throw: a mutant must not leak its folder
  return dir;
}

const uuid = (n) => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');
const T0 = Date.parse('2026-11-02T12:00:00Z');
const MIN = 60 * 1000;
const iso = (ms) => new Date(ms).toISOString();
const ago = (ms) => iso(T0 - ms);
const HOUR = 60 * MIN;

// ---- transcript records, the shapes the harness writes (the overseer's test fixtures)
const user = (t, tool = false) => ({ type: 'user', timestamp: t, message: { role: 'user', content: tool ? [{ type: 'tool_result', content: 'x' }] : 'do it' } });
const asst = (t, stop = null, kind = 'text', name) => ({ type: 'assistant', timestamp: t, message: { role: 'assistant', stop_reason: stop, content: [name ? { type: kind, name } : { type: kind }] } });
const turnEnd = (t) => ({ type: 'system', subtype: 'turn_duration', timestamp: t });
const UNTIMED = { type: 'permission-mode', permissionMode: 'bypass' };
const lines = (recs) => recs.map((r) => JSON.stringify(r)).join('\n') + '\n';
const act = (recs, from = emptyActivity()) => applyRecords(lines(recs), from);

// ---- a database, a snapshot and the transcripts
function fresh() {
  const dir = tempDir();
  const db = openStore(path.join(dir, 'fleet.db'));
  handles.push(db);
  return { dir, db };
}

function write(file, text) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, text);
  return file;
}

function rec(w, n, extra = {}) {
  const tp = path.join(w.dir, 'tx', uuid(n) + '.jsonl');
  return { sid: uuid(n), instance: 'term-100', pane: String(n), cwd: w.dir, transcriptPath: tp, firstSeen: ago(5 * HOUR), lastSeen: ago(n * MIN), kind: 'warg', owner: 'F', ...extra };
}

function snapshot(recs, { sockets = [{ instance: 'term-100', state: 'listed', panes: [] }], running = [], procs = 'known', panes = 'known', complete = true, at = T0 } = {}) {
  return {
    v: 1,
    at,
    registry: { complete, reason: '', sessions: recs.map((r) => ({ id: r.sid, rec: r })) },
    panes: { state: panes, reason: '', sockets },
    processes: { state: procs, reason: '', running: running.map((id) => ({ sessionId: id, pid: 1 })) },
  };
}

const listed = (...nos) => [{ instance: 'term-100', state: 'listed', panes: nos }];
const sess = (db, n) => ({ ...db.prepare('SELECT * FROM session WHERE id = ?').get(uuid(n)) });
const all = (db, sql, ...p) => db.prepare(sql).all(...p).map((r) => ({ ...r }));

// ---------------------------------------------------------------------------------------------------------
// migration 7

test('migration 7 on an old database: the columns come, every row stays, the CHECKs hold', () => {
  const dir = tempDir();
  const file = path.join(dir, 'fleet.db');
  const raw = new DatabaseSync(file);
  for (let i = 0; i < 6; i++) raw.exec(MIGRATIONS[i]);
  raw.exec('PRAGMA user_version = 6');
  raw.prepare("INSERT INTO node (id, name, is_authority, created_at) VALUES ('01HZZZZZZZZZZZZZZZZZZZZZZZ', 'pc', 1, 11)").run();
  raw.prepare("INSERT INTO session (id, node_id, rank, first_seen, last_seen) VALUES (?, '01HZZZZZZZZZZZZZZZZZZZZZZZ', 'warg', 33, 34)").run(uuid(1));
  raw.close();
  const db = openStore(file);
  handles.push(db);
  assert.equal(SCHEMA_VERSION, 7);
  assert.equal(db.prepare('PRAGMA user_version').get().user_version, 7);
  const row = sess(db, 1);
  for (const c of ['last_activity_at', 'last_assistant_at', 'in_turn', 'waits_person', 'state', 'state_checked_at', 'transcript_offset']) assert.equal(row[c], null, c + ' starts NULL');
  assert.equal(row.first_seen, 33);
  const bad = (set) => assert.throws(() => db.prepare('UPDATE session SET ' + set + ' WHERE id = ?').run(uuid(1)), /CHECK/);
  bad('in_turn = 2');
  bad('waits_person = -1');
  bad("state = 'asleep'");
  bad('transcript_offset = -1');
  bad('last_activity_at = -5');
  db.prepare("UPDATE session SET state = 'dead', in_turn = 0, waits_person = 0, transcript_offset = 0 WHERE id = ?").run(uuid(1));
});

// ---------------------------------------------------------------------------------------------------------
// the activity rules (from the overseer's cases)

test('rule: a turn that ended is idle, and last_assistant_at is the assistant record', () => {
  const a = act([user(ago(3 * HOUR)), asst(ago(3 * HOUR - MIN), 'end_turn'), turnEnd(ago(3 * HOUR - 2 * MIN))]);
  assert.equal(a.inTurn, false);
  assert.equal(a.lastAssistantAt, T0 - 3 * HOUR + MIN);
  assert.equal(a.lastActivityAt, T0 - 3 * HOUR + 2 * MIN);
  assert.equal(stateOf('alive', a), 'idle');
});

test('rule: a tool result nobody has answered keeps the turn open', () => {
  const a = act([user(ago(2 * HOUR)), asst(ago(2 * HOUR), 'tool_use', 'tool_use'), user(ago(2 * HOUR), true)]);
  assert.equal(a.inTurn, true);
  assert.equal(stateOf('alive', a), 'live');
});

test('rule: records with no timestamp are not activity (mode lines touch the file and do no work)', () => {
  const a = act([asst(ago(4 * 24 * HOUR), 'end_turn'), turnEnd(ago(4 * 24 * HOUR)), UNTIMED, UNTIMED]);
  assert.equal(a.lastActivityAt, T0 - 4 * 24 * HOUR);
});

test('rule: types that are not user, assistant or a turn-end system record are not activity', () => {
  const a = act([asst(ago(5 * HOUR), 'end_turn'), { type: 'system', subtype: 'informational', timestamp: ago(MIN) }, { type: 'summary', timestamp: ago(MIN) }, { type: 'file-history-snapshot', timestamp: ago(MIN) }]);
  assert.equal(a.lastActivityAt, T0 - 5 * HOUR);
  const b = act([user(ago(5 * HOUR)), { type: 'system', subtype: 'stop_hook_summary', timestamp: ago(HOUR) }]);
  assert.equal(b.lastActivityAt, T0 - HOUR, 'stop_hook_summary counts');
  assert.equal(b.inTurn, false, 'and ends the turn');
});

test('rule: a compaction summary does not open a turn (an unanswered one looked mid-turn for 4 days)', () => {
  const summary = { ...user(ago(4 * 24 * HOUR)), isCompactSummary: true };
  const a = act([asst(ago(4 * 24 * HOUR + HOUR), 'end_turn'), turnEnd(ago(4 * 24 * HOUR + HOUR)), summary]);
  assert.equal(a.inTurn, false);
  assert.equal(a.lastActivityAt, T0 - 4 * 24 * HOUR - HOUR, 'and is no activity either');
});

test('rule: isMeta records (hook text, reminders) are skipped', () => {
  const a = act([asst(ago(3 * HOUR), 'end_turn'), { ...user(ago(MIN)), isMeta: true }]);
  assert.equal(a.inTurn, false);
  assert.equal(a.lastActivityAt, T0 - 3 * HOUR);
});

test('rule: end_turn closes the turn; any other stop_reason keeps it open', () => {
  assert.equal(act([user(ago(HOUR)), asst(ago(HOUR), 'end_turn')]).inTurn, false);
  assert.equal(act([user(ago(HOUR)), asst(ago(HOUR), 'tool_use', 'tool_use')]).inTurn, true);
  assert.equal(act([user(ago(HOUR)), asst(ago(HOUR), 'max_tokens')]).inTurn, true);
});

test('rule: a text-only record with no stop_reason is a finished answer (a subagent ended that way and looked stalled for 51 min)', () => {
  assert.equal(act([user(ago(HOUR)), asst(ago(HOUR))]).inTurn, false);
  assert.equal(act([user(ago(HOUR)), asst(ago(HOUR), null, 'tool_use')]).inTurn, true, 'but a tool call with no stop_reason is mid-stream');
});

test('rule: a turn whose last tool call is ExitPlanMode or AskUserQuestion waits for a person; a tool result ends the wait', () => {
  for (const name of ['ExitPlanMode', 'AskUserQuestion']) {
    const a = act([user(ago(HOUR)), asst(ago(HOUR), 'tool_use', 'tool_use', name)]);
    assert.equal(a.inTurn, true);
    assert.equal(a.waitsPerson, true, name);
    assert.equal(stateOf('alive', a), 'waiting-person');
    const answered = act([user(ago(MIN), true)], a);
    assert.equal(answered.waitsPerson, false, 'the answer ends the wait');
    assert.equal(stateOf('alive', answered), 'live');
  }
  assert.equal(act([user(ago(HOUR)), asst(ago(HOUR), 'tool_use', 'tool_use', 'Bash')]).waitsPerson, false, 'another tool does not');
});

test('rule: an interrupt marker closes the turn, in both record shapes; a plain prompt opens one', () => {
  for (const content of ['[Request interrupted by user for tool use]', [{ type: 'text', text: '[Request interrupted by user]' }]]) {
    const stop = { type: 'user', timestamp: ago(HOUR), message: { role: 'user', content } };
    assert.equal(act([user(ago(HOUR)), asst(ago(HOUR), 'tool_use', 'tool_use'), stop]).inTurn, false);
  }
  assert.equal(act([user(ago(HOUR))]).inTurn, true);
});

test('rule: a local slash command runs without the model and is no prompt (/exit looked like a prompt left open for 86 min)', () => {
  const exit = { type: 'user', timestamp: ago(MIN), message: { role: 'user', content: '<command-name>/exit</command-name>' } };
  const a = act([asst(ago(2 * HOUR), 'end_turn'), exit]);
  assert.equal(a.inTurn, false);
  assert.equal(a.lastActivityAt, T0 - 2 * HOUR);
});

test('rule: THE TIMES ARE THE RECORDS: a file touched now holds a session last active days ago', () => {
  const w = fresh();
  const file = write(path.join(w.dir, 'a.jsonl'), lines([asst(ago(4 * 24 * HOUR), 'end_turn'), UNTIMED]));
  fs.utimesSync(file, new Date(), new Date());
  const r = readTranscript(file, { offset: null, act: emptyActivity() }, SESSION_READ_BYTES);
  assert.equal(r.act.lastActivityAt, T0 - 4 * 24 * HOUR);
});

// ---------------------------------------------------------------------------------------------------------
// the byte offset

test('offset: a half-written line is left for the next read, and read whole then', () => {
  const w = fresh();
  const file = path.join(w.dir, 'h.jsonl');
  const whole = lines([user(ago(HOUR))]);
  const second = JSON.stringify(asst(ago(30 * MIN), 'end_turn'));
  write(file, whole + second.slice(0, 20));
  const r1 = readTranscript(file, { offset: null, act: emptyActivity() }, SESSION_READ_BYTES);
  assert.equal(r1.offset, Buffer.byteLength(whole), 'the offset stops after the last newline');
  assert.equal(r1.act.inTurn, true);
  fs.appendFileSync(file, second.slice(20) + '\n');
  const r2 = readTranscript(file, { offset: r1.offset, act: r1.act }, SESSION_READ_BYTES);
  assert.equal(r2.act.inTurn, false);
  assert.equal(r2.act.lastAssistantAt, T0 - 30 * MIN);
  assert.equal(r2.offset, fs.statSync(file).size);
  assert.equal(readTranscript(file, { offset: r2.offset, act: r2.act }, SESSION_READ_BYTES).status, 'unchanged');
});

test('offset: a file smaller than the offset was replaced and is read again from 0', () => {
  const w = fresh();
  const file = path.join(w.dir, 'r.jsonl');
  write(file, lines([user(ago(3 * HOUR)), asst(ago(3 * HOUR), 'end_turn'), user(ago(2 * HOUR)), asst(ago(2 * HOUR), 'end_turn')]));
  const r1 = readTranscript(file, { offset: null, act: emptyActivity() }, SESSION_READ_BYTES);
  write(file, lines([user(ago(HOUR))]));
  const r2 = readTranscript(file, { offset: r1.offset, act: r1.act }, SESSION_READ_BYTES);
  assert.equal(r2.status, 'replaced');
  assert.equal(r2.act.inTurn, true, 'the old state is not carried into the new file');
  assert.equal(r2.act.lastActivityAt, T0 - HOUR);
  assert.equal(r2.act.lastAssistantAt, null);
});

test('offset: a first read takes at most the last 2 MB, starting after the first newline', () => {
  const w = fresh();
  const file = path.join(w.dir, 'big.jsonl');
  const pad = 'x'.repeat(1000);
  const old = { ...asst(ago(30 * 24 * HOUR), 'end_turn'), pad };
  const body = [];
  for (let i = 0; i < 3500; i++) body.push(JSON.stringify({ type: 'attachment', pad }));
  const tail = asst(ago(MIN), 'end_turn');
  write(file, JSON.stringify(old) + '\n' + body.join('\n') + '\n' + JSON.stringify(tail) + '\n');
  const size = fs.statSync(file).size;
  assert.ok(size > 3 * 1024 * 1024, 'CONTROL: the file is over 3 MB');
  const r = readTranscript(file, { offset: null, act: emptyActivity() }, SESSION_READ_BYTES);
  assert.ok(r.bytes <= FIRST_READ_BYTES, 'read ' + r.bytes);
  assert.equal(r.act.lastAssistantAt, T0 - MIN, 'the tail was read');
  assert.notEqual(r.act.lastAssistantAt, T0 - 30 * 24 * HOUR, 'and the head was not');
  assert.equal(r.offset, size);
});

test('offset: a read stops at the per-session cap, at a line end, and goes on from there', () => {
  const w = fresh();
  const file = path.join(w.dir, 'cap.jsonl');
  const recs = [];
  for (let i = 0; i < 40; i++) recs.push(i % 2 === 0 ? user(iso(T0 - (100 - i) * MIN)) : asst(iso(T0 - (100 - i) * MIN), 'end_turn'));
  write(file, lines(recs));
  const size = fs.statSync(file).size;
  const cap = Math.floor(size / 3);
  const r1 = readTranscript(file, { offset: 0, act: emptyActivity() }, cap);
  assert.ok(r1.bytes <= cap && r1.offset < size && r1.offset > 0);
  assert.equal(fs.readFileSync(file).subarray(r1.offset - 1, r1.offset).toString(), '\n', 'the offset is just after a newline');
  // A TWO-TICK (here three) CATCH-UP: each read moves on, the last one reaches the end, and the state is the whole file's.
  const r2 = readTranscript(file, { offset: r1.offset, act: r1.act }, cap);
  assert.ok(r2.offset > r1.offset);
  const r3 = readTranscript(file, { offset: r2.offset, act: r2.act }, cap);
  const r4 = r3.offset < size ? readTranscript(file, { offset: r3.offset, act: r3.act }, cap) : r3;
  assert.equal(r4.offset, size);
  assert.deepEqual(r4.act, act(recs));
});

test('offset: a line longer than the largest read is stepped over, not waited for forever', () => {
  const w = fresh();
  const file = path.join(w.dir, 'long.jsonl');
  write(file, 'y'.repeat(5000));
  const r = readTranscript(file, { offset: 0, act: emptyActivity() }, 1000, 1000);
  assert.equal(r.offset, 1000);
});

test('step: a read stops at what is left of the budget, even when the session could read more', () => {
  const w = fresh();
  const r = rec(w, 1, { pane: '1' });
  write(r.transcriptPath, lines([user(ago(HOUR)), asst(ago(HOUR), 'end_turn')]));
  const size = fs.statSync(r.transcriptPath).size;
  const out = runSessionsStep(w.db, snapshot([r], { sockets: listed(1), running: [r.sid] }), { now: T0, stepBytes: 10, sessionBytes: size + 5 });
  assert.ok(size > 10, 'CONTROL: the transcript is larger than the budget');
  assert.equal(out.bytes, 10);
});

test('step: the budget of a tick is shared, so catching up takes several ticks and every session gets there', () => {
  const w = fresh();
  const recs = [1, 2, 3].map((n) => rec(w, n, { pane: String(n) }));
  for (const r of recs) write(r.transcriptPath, lines([user(ago(HOUR)), asst(ago(HOUR), 'end_turn')]));
  const size = fs.statSync(recs[0].transcriptPath).size;
  const opts = { now: T0, stepBytes: size, sessionBytes: size + 5 };
  const snap = snapshot(recs, { sockets: listed(1, 2, 3), running: recs.map((r) => r.sid) });
  const first = runSessionsStep(w.db, snap, opts);
  assert.equal(first.deferred, 2, 'one session fitted the budget');
  assert.equal(first.bytes, size);
  const second = runSessionsStep(w.db, snap, { ...opts, now: T0 + MIN });
  const third = runSessionsStep(w.db, snap, { ...opts, now: T0 + 2 * MIN });
  assert.equal(second.deferred + third.deferred, 1);
  const done = all(w.db, 'SELECT count(*) AS n FROM session WHERE transcript_offset = ?', size)[0].n;
  assert.equal(done, 3);
  assert.equal(runSessionsStep(w.db, snap, { ...opts, now: T0 + 3 * MIN }).bytes, 0, 'nothing is read twice');
});

// ---------------------------------------------------------------------------------------------------------
// subagents

test('subagents: a session mid-turn in a long foreground call takes its newest subagent record as its activity', () => {
  const w = fresh();
  const r = rec(w, 1);
  write(r.transcriptPath, lines([user(ago(2 * HOUR)), asst(ago(2 * HOUR), 'tool_use', 'tool_use', 'Task')]));
  const subDir = r.transcriptPath.replace(/\.jsonl$/, '') + path.sep + 'subagents';
  write(path.join(subDir, 'agent-a.jsonl'), lines([user(ago(2 * HOUR)), asst(ago(10 * MIN), 'tool_use', 'tool_use')]));
  write(path.join(subDir, 'agent-b.jsonl'), lines([user(ago(2 * HOUR)), asst(ago(3 * MIN), 'tool_use', 'tool_use')]));
  const out = runSessionsStep(w.db, snapshot([r], { sockets: listed(1), running: [r.sid] }), { now: T0 });
  assert.equal(out.counts.live, 1);
  assert.equal(sess(w.db, 1).last_activity_at, T0 - 3 * MIN, 'the newer subagent');
  assert.equal(sess(w.db, 1).last_assistant_at, T0 - 2 * HOUR, 'the parent keeps its own assistant time');
});

test('subagents: a parent whose turn ended is not folded, and the file time is never the time', () => {
  const w = fresh();
  const r = rec(w, 1);
  write(r.transcriptPath, lines([user(ago(2 * HOUR)), asst(ago(2 * HOUR), 'end_turn')]));
  const subDir = r.transcriptPath.replace(/\.jsonl$/, '') + path.sep + 'subagents';
  write(path.join(subDir, 'agent-a.jsonl'), lines([asst(ago(MIN), 'tool_use', 'tool_use')]));
  runSessionsStep(w.db, snapshot([r], { sockets: listed(1), running: [r.sid] }), { now: T0 });
  assert.equal(sess(w.db, 1).last_activity_at, T0 - 2 * HOUR);
  // subagentActivity directly: a touched file holding old records gives the records' time.
  const touched = write(path.join(subDir, 'agent-old.jsonl'), lines([asst(ago(20 * HOUR), 'end_turn')]));
  fs.utimesSync(touched, new Date(T0), new Date(T0));
  assert.equal(subagentActivity(r.transcriptPath, 0, T0 + MIN), T0 - MIN, 'agent-a is newer than the touched file records');
  fs.rmSync(path.join(subDir, 'agent-a.jsonl'));
  assert.equal(subagentActivity(r.transcriptPath, 0, T0 + MIN), T0 - 20 * HOUR);
  assert.equal(subagentActivity(path.join(w.dir, 'nothing.jsonl'), 0, T0), null);
});

// ---------------------------------------------------------------------------------------------------------
// liveness

test('liveness: a pane that is gone and no process is dead; retired_at is left alone', () => {
  const w = fresh();
  const r = rec(w, 1);
  write(r.transcriptPath, lines([user(ago(HOUR)), asst(ago(HOUR), 'end_turn')]));
  const out = runSessionsStep(w.db, snapshot([r], { sockets: listed(7) }), { now: T0 });
  assert.equal(out.counts.dead, 1);
  const s = sess(w.db, 1);
  assert.equal(s.state, 'dead');
  assert.equal(s.state_checked_at, T0);
  assert.equal(s.retired_at, null);
});

test('liveness: a terminal that cannot be listed makes its sessions UNKNOWN, never dead (state and stamp untouched)', () => {
  const w = fresh();
  const r = rec(w, 1);
  write(r.transcriptPath, lines([user(ago(HOUR)), asst(ago(HOUR), 'end_turn')]));
  runSessionsStep(w.db, snapshot([r], { sockets: listed(1) }), { now: T0 });
  assert.equal(sess(w.db, 1).state, 'idle');
  const out = runSessionsStep(w.db, snapshot([r], { sockets: [{ instance: 'term-100', state: 'unknown', panes: [], reason: 'timed out' }] }), { now: T0 + MIN });
  assert.equal(out.counts.unknown, 1);
  assert.equal(out.counts.dead, 0);
  const s = sess(w.db, 1);
  assert.equal(s.state, 'idle', 'the old state stays');
  assert.equal(s.state_checked_at, T0, 'and the old stamp tells a reader the sync was blind');
  // The whole pane list unknown is the same.
  const out2 = runSessionsStep(w.db, snapshot([r], { panes: 'unknown', sockets: [] }), { now: T0 + 2 * MIN });
  assert.equal(out2.counts.unknown, 1);
  assert.equal(sess(w.db, 1).state_checked_at, T0);
});

test('liveness: a terminal instance that is not running, or that the list does not name, closes its panes: dead without a process', () => {
  const w = fresh();
  const r = rec(w, 1);
  runSessionsStep(w.db, snapshot([r], { sockets: listed(1) }), { now: T0 });
  assert.equal(all(w.db, 'SELECT * FROM pane WHERE closed_at IS NULL').length, 1);
  const gone = runSessionsStep(w.db, snapshot([r], { sockets: [{ instance: 'term-100', state: 'closed', panes: [] }] }), { now: T0 + MIN });
  assert.equal(gone.counts.dead, 1);
  assert.equal(all(w.db, 'SELECT * FROM pane WHERE closed_at IS NULL').length, 0, 'its pane row closed');
  assert.equal(all(w.db, 'SELECT * FROM session_pane WHERE to_at IS NULL').length, 0, 'and its session_pane with it');
  const unnamed = judgeLiveness([{ id: r.sid, rec: r }], parseSnapshot(snapshot([r], { sockets: [] })));
  assert.equal(unnamed.verdicts.get(r.sid), 'dead');
});

test('liveness: a running process keeps a session alive when its pane is gone; an unreadable process list leaves it unknown', () => {
  const w = fresh();
  const r = rec(w, 1);
  const alive = judgeLiveness([{ id: r.sid, rec: r }], parseSnapshot(snapshot([r], { sockets: listed(), running: [r.sid] })));
  assert.equal(alive.verdicts.get(r.sid), 'alive');
  const blind = judgeLiveness([{ id: r.sid, rec: r }], parseSnapshot(snapshot([r], { sockets: listed(), procs: 'unknown' })));
  assert.equal(blind.verdicts.get(r.sid), 'unknown');
  const noPane = rec(w, 2, { pane: undefined, instance: undefined });
  const headless = judgeLiveness([{ id: noPane.sid, rec: noPane }], parseSnapshot(snapshot([noPane])));
  assert.equal(headless.verdicts.get(noPane.sid), 'dead', 'no pane and no process');
});

test('liveness: a /clear pair - the new id holds the pane and is alive though the process still names the old id', () => {
  const w = fresh();
  const oldId = rec(w, 1, { pane: '5', lastSeen: ago(3 * HOUR) });
  const newId = rec(w, 2, { pane: '5', lastSeen: ago(MIN) });
  const entries = [oldId, newId].map((r) => ({ id: r.sid, rec: r }));
  const j = judgeLiveness(entries, parseSnapshot(snapshot([oldId, newId], { sockets: listed(5), running: [uuid(1)] })));
  assert.equal(j.owners.get('term-100\u00005'), uuid(2), 'the newest lastSeen owns the pane, whichever id the process names');
  assert.equal(j.verdicts.get(uuid(2)), 'alive', 'never a false death for the session really in the pane');
  assert.equal(j.verdicts.get(uuid(1)), 'alive', 'its running process still proves the old id alive: the accepted wrong answer');
});

test('an alive session with no record read yet is not called idle, and its stamp stays old', () => {
  const w = fresh();
  const r = rec(w, 1, { pane: '5', lastSeen: ago(MIN), transcriptPath: path.join(w.dir, 'no-such-transcript.jsonl') });
  const out = runSessionsStep(w.db, snapshot([r], { sockets: listed(5) }), { now: T0 });
  assert.equal(out.counts.unknown, 1);
  assert.equal(out.counts.idle, 0);
  assert.equal(sess(w.db, 1).state, null);
  assert.equal(sess(w.db, 1).state_checked_at, null);
});

test('last_seen follows the record, and an older record never moves it back', () => {
  const w = fresh();
  const r = rec(w, 1, { pane: '5', lastSeen: ago(HOUR) });
  runSessionsStep(w.db, snapshot([r], { sockets: listed(5) }), { now: T0 });
  const first = sess(w.db, 1).last_seen;
  runSessionsStep(w.db, snapshot([{ ...r, lastSeen: ago(MIN) }], { sockets: listed(5) }), { now: T0 });
  const moved = sess(w.db, 1).last_seen;
  assert.ok(moved > first);
  runSessionsStep(w.db, snapshot([{ ...r, lastSeen: ago(2 * HOUR) }], { sockets: listed(5) }), { now: T0 });
  assert.equal(sess(w.db, 1).last_seen, moved);
});

test('liveness: two records claim one pane - the owner has the newest lastSeen', () => {
  const w = fresh();
  const stale = rec(w, 1, { pane: '5', lastSeen: ago(3 * HOUR) });
  const fresher = rec(w, 2, { pane: '5', lastSeen: ago(MIN) });
  const entries = [stale, fresher].map((r) => ({ id: r.sid, rec: r }));
  const byTime = judgeLiveness(entries, parseSnapshot(snapshot([stale, fresher], { sockets: listed(5) })));
  assert.equal(byTime.owners.get('term-100\u00005'), uuid(2));
  assert.equal(byTime.verdicts.get(uuid(1)), 'dead', 'the other one does not hold the pane');
  assert.equal(byTime.verdicts.get(uuid(2)), 'alive');
  // In the database: one open session_pane for the pane, and it is the owner's.
  runSessionsStep(w.db, snapshot([stale, fresher], { sockets: listed(5) }), { now: T0 });
  assert.deepEqual(all(w.db, 'SELECT session_id FROM session_pane WHERE to_at IS NULL'), [{ session_id: uuid(2) }]);
});

test('liveness: a retired record claims no pane, even with the newest lastSeen', () => {
  const w = fresh();
  const live = rec(w, 1, { pane: '5', lastSeen: ago(HOUR) });
  const retired = rec(w, 2, { pane: '5', lastSeen: ago(MIN), retired: true, retiredAt: ago(MIN) });
  runSessionsStep(w.db, snapshot([live, retired], { sockets: listed(5) }), { now: T0 });
  assert.deepEqual(all(w.db, 'SELECT session_id FROM session_pane WHERE to_at IS NULL'), [{ session_id: uuid(1) }]);
  assert.equal(sess(w.db, 2).state, 'dead');
});

test('liveness: a record file time is never read - lastSeen is the record\'s own field', () => {
  const w = fresh();
  const a = rec(w, 1, { pane: '5', lastSeen: ago(2 * HOUR) });
  const b = rec(w, 2, { pane: '5', lastSeen: ago(HOUR) });
  const out = judgeLiveness([a, b].map((r) => ({ id: r.sid, rec: r })), parseSnapshot(snapshot([a, b], { sockets: listed(5) })));
  assert.equal(out.owners.get('term-100\u00005'), uuid(2));
});

// ---------------------------------------------------------------------------------------------------------
// the rows

test('a session the registry has and fleet.db lacks is added, by the importer\'s own rule', () => {
  const w = fresh();
  const missing = '8deca873-0000-4000-8000-000000000001';
  const r = { ...rec(w, 1), sid: missing, parent: uuid(9), kind: 'orc', owner: 'F' };
  const out = runSessionsStep(w.db, snapshot([r], { sockets: listed(1) }), { now: T0 });
  assert.ok(out.added >= 1);
  const s = w.db.prepare('SELECT id, rank, parent_session_id, first_seen, last_seen, transcript_path FROM session WHERE id = ?').get(missing);
  assert.equal(s.id, missing);
  assert.equal(s.rank, 'unknown', 'an orc record naming no Orc row is kept with the importer\'s rank rule');
  assert.equal(s.parent_session_id, uuid(9), 'the importer\'s stub for a parent the registry lacks');
  assert.equal(s.transcript_path, r.transcriptPath);
  assert.equal(s.first_seen, T0 - 5 * HOUR);
});

test('a session moving panes closes its old session_pane and opens a new one: two rows, history not an overwrite', () => {
  const w = fresh();
  const r = rec(w, 1, { pane: '3' });
  runSessionsStep(w.db, snapshot([r], { sockets: listed(3, 4) }), { now: T0 });
  const moved = { ...r, pane: '4' };
  const out = runSessionsStep(w.db, snapshot([moved], { sockets: listed(3, 4) }), { now: T0 + MIN });
  assert.equal(out.moved, 1);
  const rows = all(w.db, 'SELECT sp.session_id, p.pane_no, sp.from_at, sp.to_at FROM session_pane sp JOIN pane p ON p.id = sp.pane_id ORDER BY sp.from_at');
  assert.deepEqual(rows, [
    { session_id: uuid(1), pane_no: 3, from_at: T0, to_at: T0 + MIN },
    { session_id: uuid(1), pane_no: 4, from_at: T0 + MIN, to_at: null },
  ]);
});

test('a pane gone from its list closes its pane row and its session_pane; a number that comes back is a new pane', () => {
  const w = fresh();
  const r = rec(w, 1, { pane: '3' });
  runSessionsStep(w.db, snapshot([r], { sockets: listed(3) }), { now: T0 });
  runSessionsStep(w.db, snapshot([r], { sockets: listed() }), { now: T0 + MIN });
  assert.deepEqual(all(w.db, 'SELECT pane_no, opened_at, closed_at FROM pane'), [{ pane_no: 3, opened_at: T0, closed_at: T0 + MIN }]);
  assert.deepEqual(all(w.db, 'SELECT from_at, to_at FROM session_pane'), [{ from_at: T0, to_at: T0 + MIN }]);
  runSessionsStep(w.db, snapshot([r], { sockets: listed(3) }), { now: T0 + 2 * MIN });
  assert.equal(all(w.db, 'SELECT * FROM pane').length, 2);
  assert.equal(all(w.db, 'SELECT * FROM pane WHERE closed_at IS NULL').length, 1);
});

test('panes of a terminal that could not be listed are left exactly as they were', () => {
  const w = fresh();
  const r = rec(w, 1, { pane: '3' });
  runSessionsStep(w.db, snapshot([r], { sockets: listed(3) }), { now: T0 });
  runSessionsStep(w.db, snapshot([r], { sockets: [{ instance: 'term-100', state: 'unknown', panes: [] }] }), { now: T0 + MIN });
  assert.equal(all(w.db, 'SELECT * FROM pane WHERE closed_at IS NULL').length, 1);
  assert.equal(all(w.db, 'SELECT * FROM session_pane WHERE to_at IS NULL').length, 1);
});

test('state: waiting-person, live and idle come from the transcript of an alive session; waiting-job is never set', () => {
  const w = fresh();
  const [a, b, c] = [1, 2, 3].map((n) => rec(w, n));
  write(a.transcriptPath, lines([user(ago(HOUR)), asst(ago(HOUR), 'tool_use', 'tool_use', 'ExitPlanMode')]));
  write(b.transcriptPath, lines([user(ago(HOUR))]));
  write(c.transcriptPath, lines([user(ago(HOUR)), asst(ago(HOUR), 'end_turn')]));
  const out = runSessionsStep(w.db, snapshot([a, b, c], { sockets: listed(1, 2, 3) }), { now: T0 });
  assert.deepEqual([sess(w.db, 1).state, sess(w.db, 2).state, sess(w.db, 3).state], ['waiting-person', 'live', 'idle']);
  assert.equal(sess(w.db, 1).waits_person, 1);
  assert.equal(sess(w.db, 2).in_turn, 1);
  assert.equal(sess(w.db, 3).in_turn, 0);
  assert.deepEqual([out.counts['waiting-person'], out.counts.live, out.counts.idle], [1, 1, 1]);
  assert.equal(all(w.db, "SELECT count(*) AS n FROM session WHERE state = 'waiting-job'")[0].n, 0);
});

test('a second identical tick writes nothing but state_checked_at; a dead session is not read twice', () => {
  const w = fresh();
  const [a, b] = [1, 2].map((n) => rec(w, n));
  write(a.transcriptPath, lines([user(ago(HOUR)), asst(ago(HOUR), 'end_turn')]));
  write(b.transcriptPath, lines([user(ago(2 * HOUR)), asst(ago(2 * HOUR), 'end_turn')]));
  const snap = snapshot([a, b], { sockets: listed(1) }); // pane 2 is not listed: b is dead
  const dump = () => ({
    session: all(w.db, 'SELECT id, last_activity_at, last_assistant_at, in_turn, waits_person, state, transcript_offset, retired_at, rank, first_seen, last_seen FROM session ORDER BY id'),
    pane: all(w.db, 'SELECT * FROM pane ORDER BY id'),
    link: all(w.db, 'SELECT * FROM session_pane ORDER BY session_id, from_at'),
  });
  const first = runSessionsStep(w.db, snap, { now: T0 });
  assert.ok(first.bytes > 0 && first.changed === 2);
  const before = dump();
  assert.equal(sess(w.db, 2).state, 'dead');
  const second = runSessionsStep(w.db, snap, { now: T0 + MIN });
  assert.deepEqual(dump(), before, 'rows are identical');
  assert.equal(second.changed, 0);
  assert.equal(second.bytes, 0, 'no byte is read again');
  assert.equal(second.added, 0);
  assert.equal(sess(w.db, 1).state_checked_at, T0 + MIN, 'the stamp moved');
  assert.equal(sess(w.db, 2).state_checked_at, T0 + MIN);
});

test('a snapshot that is not the shape is refused with the reason, before any write', () => {
  const w = fresh();
  const good = snapshot([rec(w, 1)]);
  for (const bad of [null, { ...good, v: 2 }, { ...good, at: 'now' }, { ...good, registry: { complete: true } }, { ...good, panes: { state: 'maybe', sockets: [] } },
    { ...good, panes: { state: 'known', sockets: [{ instance: 'term-1', state: 'listed', panes: ['x'] }] } }, { ...good, processes: { state: 'known' } }]) {
    assert.throws(() => runSessionsStep(w.db, bad, { now: T0 }), /session snapshot is not usable/);
  }
  assert.equal(all(w.db, 'SELECT count(*) AS n FROM session')[0].n, 0);
});

// ---------------------------------------------------------------------------------------------------------
// the step inside `horde db sync`

function syncWorld() {
  const w = fresh();
  const files = tempDir();
  const ledger = path.join(files, 'tasks.jsonl');
  write(ledger, JSON.stringify({ ts: '2026-11-01T10:00:00Z', task: 'T-0001', event: 'opened', title: 'First', source: 'founder', lane: 'C', prio: 2, parent: null, by: 'C' }) + '\n');
  const cards = path.join(files, 'orcs');
  write(path.join(cards, 'form-fill', 'status.txt'), ['horde-orc-status 1', 'orc: C', 'lane: Form fill', 'doing: x', 'finished: a part', 'blocked: no'].join('\n') + '\n');
  const home = w.dir;
  saveSettings(home, { ledger, cards });
  const r = rec(w, 1);
  write(r.transcriptPath, lines([user(ago(HOUR)), asst(ago(HOUR), 'end_turn')]));
  const snapFile = path.join(files, 'snap.json');
  write(snapFile, JSON.stringify(snapshot([r], { sockets: listed(1) })));
  w.db.close();
  return { home, ledger, snapFile, env: { HORDE_HOME: home } };
}

function sync(world, args, at = T0) {
  const out = [];
  const err = [];
  const code = syncMain(args, world.env, (s) => out.push(s), (s) => err.push(s), { now: () => at });
  return { code, out: out.join('\n'), err: err.join('\n') };
}

test('sync: the sessions step runs on every tick, also when the files step is skipped, and the line names both', () => {
  const w = syncWorld();
  const first = sync(w, ['--snapshot', w.snapFile], T0);
  assert.equal(first.code, 0, first.err);
  assert.match(first.out, /^sync: files ran, .*; sessions ran, 1 sessions \(0 live, 1 idle, 0 waiting-person, 0 dead, 0 unknown\)/);
  const second = sync(w, ['--snapshot', w.snapFile], T0 + MIN);
  assert.equal(second.code, 0, second.err);
  assert.match(second.out, /^sync: files skipped \(last ok 60 s ago, runs every 5 min\); sessions ran, 1 sessions/);
  const st = readState(w.home);
  assert.deepEqual([st.sessions.lastOkAt, st.sessions.lastResult, st.files.lastOkAt], [T0 + MIN, 'ok', T0]);
  assert.equal(st.sessions.counts.idle, 1);
});

test('sync: a files failure does not stop the sessions step, and each records its own result', () => {
  const w = syncWorld();
  sync(w, ['--snapshot', w.snapFile], T0);
  fs.rmSync(w.ledger);
  const r = sync(w, ['--snapshot', w.snapFile], T0 + 5 * MIN);
  assert.equal(r.code, 1);
  assert.match(r.err, /^fleet\.db: sync: files failed: .*; sessions ran, /);
  const st = readState(w.home);
  assert.deepEqual([st.files.lastResult, st.files.lastOkAt], ['failed', T0]);
  assert.deepEqual([st.sessions.lastResult, st.sessions.lastOkAt], ['ok', T0 + 5 * MIN]);
});

test('sync: a sessions failure does not lose the files step, and the other way round it is recorded as failed', () => {
  const w = syncWorld();
  const r = sync(w, ['--snapshot', path.join(w.home, 'nothing.json')], T0);
  assert.equal(r.code, 1);
  assert.match(r.err, /^fleet\.db: sync: files ran, .*; sessions failed: the session snapshot .* could not be read/);
  const st = readState(w.home);
  assert.deepEqual([st.files.lastResult, st.files.lastOkAt], ['ok', T0]);
  assert.deepEqual([st.sessions.lastResult, st.sessions.lastOkAt], ['failed', null]);
  const check = openStore(path.join(w.home, 'fleet.db'));
  handles.push(check);
  assert.equal(all(check, 'SELECT count(*) AS n FROM task_event')[0].n, 1, 'the files rows are in');
  const none = sync(w, ['--snapshot-error', 'the producer timed out'], T0 + MIN);
  assert.equal(none.code, 1);
  assert.match(none.err, /sessions failed: no session snapshot this tick: the producer timed out/);
  const ok = sync(w, ['--snapshot', w.snapFile], T0 + 2 * MIN);
  assert.equal(ok.code, 0, ok.err);
  assert.equal(readState(w.home).sessions.lastResult, 'ok');
});

test('sync: with neither a snapshot nor an error the run is the files step alone, as before', () => {
  const w = syncWorld();
  const r = sync(w, [], T0);
  assert.equal(r.code, 0, r.err);
  assert.match(r.out, /^sync: files ran, [^;]*$/);
  assert.equal(readState(w.home).sessions.lastResult, null);
});

test('sync: --snapshot and --snapshot-error are one or the other, and each needs its value', () => {
  assert.throws(() => parseSyncArgs(['--snapshot', 'a', '--snapshot-error', 'b']), /one or the other/);
  assert.throws(() => parseSyncArgs(['--snapshot']), /needs a path/);
  assert.throws(() => parseSyncArgs(['--snapshot-error']), /needs the reason/);
  assert.throws(() => parseSyncArgs(['--snapshot', 'a', '--snapshot', 'b']), /given twice/);
});

test('--note-timeout marks the sessions step too, without moving either lastOkAt', () => {
  const w = syncWorld();
  sync(w, ['--snapshot', w.snapFile], T0);
  const r = sync(w, ['--note-timeout', '50123'], T0 + MIN);
  assert.equal(r.code, 0, r.err);
  const st = readState(w.home);
  assert.deepEqual([st.sessions.lastOkAt, st.sessions.lastResult, st.sessions.lastMs], [T0, 'timeout', 50123]);
  assert.deepEqual([st.files.lastOkAt, st.files.lastResult], [T0, 'timeout']);
});

test('db status says the sessions step: never synced, then the last run and the sessions by state', () => {
  const w = syncWorld();
  const s0 = [];
  assert.equal(main(['status'], w.env, (l) => s0.push(l), () => {}), 0);
  assert.ok(s0.includes('sessions: never synced'));
  sync(w, ['--snapshot', w.snapFile], T0);
  const s1 = [];
  main(['status'], w.env, (l) => s1.push(l), () => {});
  const line = 'sessions: last ok 2026-11-02T12:00:00.000Z, last run ok at 2026-11-02T12:00:00.000Z, live 0, idle 1, waiting-person 0, dead 0, unknown 0';
  assert.ok(s1.includes(line), s1.join('\n'));
  assert.equal(describeSessions(w.home), line);
  assert.match(s1[s1.length - 1], /^sync: /, 'the files line is still the last');
});
