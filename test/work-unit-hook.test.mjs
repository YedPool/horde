// hooks/horde-work-unit.mjs, driven as a real process with real JSON payloads on stdin, against a fleet.db of its
// own under the temp folder. Every test names its own profile folder first (the empty-environment trap of 10-21:
// a resolver that falls back to the real profile reaches the real pointer and the real fleet.db), so nothing real
// is read or written. Run by test/test-work-unit-hook.ps1.
import '../fleet-db/test/own-profile.mjs';
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { openStore, dbPathFor } from '../fleet-db/store.mjs';
import { listWork, startWork } from '../fleet-db/work.mjs';
import { ulid } from '../fleet-db/ids.mjs';
import { briefOf, taskOf, workTypeOf, kindOfRecord } from '../hooks/horde-work-unit.mjs';

const HOOK = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'hooks', 'horde-work-unit.mjs');
const T0 = Date.UTC(2026, 9, 22, 12, 0, 0);
const uuid = (n) => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');
const PARENT = uuid(1);
const WARG = uuid(2);
// The shape of a real harness agent id (seen in a subagent transcript's file name).
const AGENT = 'a16302f8c616026c8';

const dirs = [];
after(() => { for (const d of dirs) fs.rmSync(d, { recursive: true, force: true }); });

// One world: a home with fleet.db (Orc F, task T-0001, the parent session of F), a registry, a transcript root.
function world() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'work-hook-'));
  dirs.push(dir);
  const home = path.join(dir, 'home');
  fs.mkdirSync(home);
  const registry = path.join(dir, 'registry');
  fs.mkdirSync(registry);
  const db = openStore(dbPathFor(home));
  db.prepare('INSERT INTO node (id, name, is_authority, created_at) VALUES (?, ?, 1, ?)').run(ulid(T0), 'pc-1', T0);
  const orc = ulid(T0 + 1);
  db.prepare("INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES (?, 'F', 'decisions-page', 'Decisions', 'orc', ?)").run(orc, T0);
  db.prepare("INSERT INTO task (id, key, title, source, created_at) VALUES (?, 'T-0001', 'a task', 'founder', ?)").run(ulid(T0 + 2), T0);
  const node = db.prepare('SELECT id FROM node').get().id;
  db.prepare("INSERT INTO session (id, node_id, orc_id, rank, first_seen, last_seen) VALUES (?, ?, ?, 'orc', ?, ?)").run(PARENT, node, orc, T0, T0);
  db.close();
  const w = { dir, home, registry, log: path.join(dir, 'hook.log'), proj: path.join(dir, 'proj'), node, orc };
  putRegistry(w, PARENT, { cwd: 'C:\\fleet\\orcs\\decisions-page', label: 'F', role: 'orchestrator' });
  return w;
}
function putRegistry(w, sid, rec) { fs.writeFileSync(path.join(w.registry, sid + '.json'), '\uFEFF' + JSON.stringify(rec)); }

function subDir(w) { return path.join(w.proj, PARENT, 'subagents'); }
function putTranscript(w, id, brief, meta) {
  fs.mkdirSync(subDir(w), { recursive: true });
  const first = { parentUuid: null, isSidechain: true, agentId: id, type: 'user', message: { role: 'user', content: brief } };
  fs.writeFileSync(path.join(subDir(w), 'agent-' + id + '.jsonl'), JSON.stringify(first) + '\n');
  if (meta) fs.writeFileSync(path.join(subDir(w), 'agent-' + id + '.meta.json'), JSON.stringify(meta));
}

function run(w, payload, env = {}, raw = null) {
  const e = { ...process.env, HORDE_HOME: w.home, HORDE_WORK_HOOK_REGISTRY: w.registry, HORDE_WORK_HOOK_LOG: w.log, HORDE_WORK_HOOK_WAIT_MS: '0', ...env };
  for (const k of Object.keys(e)) if (e[k] === undefined) delete e[k];
  const t = Date.now();
  const r = spawnSync(process.execPath, [HOOK], { input: raw ?? JSON.stringify(payload), env: e, encoding: 'utf8', timeout: 20000 });
  return { code: r.status, out: r.stdout, err: r.stderr, ms: Date.now() - t };
}
const base = (w, ev, extra = {}) => ({ session_id: PARENT, transcript_path: path.join(w.proj, PARENT + '.jsonl'), cwd: w.dir, hook_event_name: ev, agent_id: AGENT, agent_type: 'general-purpose', ...extra });
const quiet = (r) => assert.deepEqual([r.code, r.out, r.err], [0, '', ''], 'exit 0, nothing printed: ' + JSON.stringify(r));

function units(w) {
  const db = openStore(dbPathFor(w.home), { readOnly: true });
  try { return listWork(db, {}); } finally { db.close(); }
}
const logText = (w) => (fs.existsSync(w.log) ? fs.readFileSync(w.log, 'utf8') : '');

// ---------------------------------------------------------------------------------------------------------
// an agent starts

test('SubagentStart: an agent is recorded with the harness id, its parent, task, work type, model and lane', () => {
  const w = world();
  putTranscript(w, AGENT, 'T-0001 review the diff\nwork: review\nmore', { agentType: 'general-purpose', model: 'sonnet' });
  quiet(run(w, base(w, 'SubagentStart'), { HORDE_WORK_HOOK_WAIT_MS: '500' }));
  const u = units(w);
  assert.equal(u.length, 1);
  assert.equal(u[0].kind, 'agent');
  assert.equal(u[0].agent_id, AGENT);
  assert.equal(u[0].parent_session_id, PARENT);
  assert.equal(u[0].task, 'T-0001');
  assert.equal(u[0].work_type, 'review');
  assert.equal(u[0].model, 'sonnet');
  assert.equal(u[0].domain, 'decisions-page');
  assert.equal(u[0].orc, 'F');
  assert.equal(u[0].outcome, 'running');
});

test('the agent id stored is EXACTLY the id in the subagent transcript file name', () => {
  const w = world();
  putTranscript(w, AGENT, 'T-0001 build it');
  quiet(run(w, base(w, 'SubagentStart'), { HORDE_WORK_HOOK_WAIT_MS: '500' }));
  const stem = fs.readdirSync(subDir(w)).find((n) => n.endsWith('.jsonl')).replace(/^agent-/, '').replace(/\.jsonl$/, '');
  assert.equal(units(w)[0].agent_id, stem);
  assert.equal(stem, AGENT);
});

test('an id the harness gives with capitals or a dash is stored as given, never repaired', () => {
  const w = world();
  const odd = 'aB-c9X';
  putTranscript(w, odd, 'T-0001 build');
  quiet(run(w, base(w, 'SubagentStart', { agent_id: odd }), { HORDE_WORK_HOOK_WAIT_MS: '500' }));
  assert.equal(units(w)[0].agent_id, odd);
});

test('the task is the first T-NNNN on the brief FIRST line only: one on a later line is no_task', () => {
  const w = world();
  putTranscript(w, AGENT, 'build the thing\nthis is T-0001 on the second line');
  quiet(run(w, base(w, 'SubagentStart'), { HORDE_WORK_HOOK_WAIT_MS: '500' }));
  assert.equal(units(w)[0].task_flag, 'no_task');
  assert.equal(units(w)[0].task, null);
});

test('a task fleet.db does not know yet is recorded no_task and the hook still exits 0', () => {
  const w = world();
  putTranscript(w, AGENT, 'T-9999 build');
  quiet(run(w, base(w, 'SubagentStart'), { HORDE_WORK_HOOK_WAIT_MS: '500' }));
  assert.equal(units(w)[0].task_flag, 'no_task');
  assert.match(logText(w), /T-9999 is not in fleet.db yet/);
});

test('work type: only an explicit marker sets it; words like review in the brief never do', () => {
  const w = world();
  putTranscript(w, AGENT, 'T-0001 please review and verify the research');
  quiet(run(w, base(w, 'SubagentStart'), { HORDE_WORK_HOOK_WAIT_MS: '500' }));
  assert.equal(units(w)[0].work_type, 'other');
  assert.equal(workTypeOf('x\ny\nwork-type: monitor', 'general-purpose'), 'monitor');
  assert.equal(workTypeOf('x\ny\nz\nwork: build', 'general-purpose'), 'other', 'a marker on the fourth line is not read');
  assert.equal(workTypeOf('Do the work: build the thing', 'general-purpose'), 'other', 'prose is not a marker');
  assert.equal(workTypeOf('  Work: Review  ', 'general-purpose'), 'review', 'a line that is only the marker is read');
  assert.equal(workTypeOf('work: nonsense', 'general-purpose'), 'other');
  assert.equal(workTypeOf('hello', 'Explore'), 'research');
  assert.equal(workTypeOf(null, 'Plan'), 'research');
});

test('with no transcript yet the unit still starts (no_task, other), and SubagentStop fills the task and ends it', () => {
  const w = world();
  quiet(run(w, base(w, 'SubagentStart')));
  assert.equal(units(w)[0].task_flag, 'no_task');
  putTranscript(w, AGENT, 'T-0001 mechanical sweep\nwork: mechanical');
  quiet(run(w, base(w, 'SubagentStop', { agent_transcript_path: path.join(subDir(w), 'agent-' + AGENT + '.jsonl') })));
  const u = units(w);
  assert.equal(u.length, 1, 'still one unit');
  assert.equal(u[0].task, 'T-0001');
  assert.equal(u[0].outcome, 'done');
});

test('SubagentStop ends the unit; repeating start and stop changes nothing and still exits 0', () => {
  const w = world();
  putTranscript(w, AGENT, 'T-0001 build');
  for (const ev of ['SubagentStart', 'SubagentStart', 'SubagentStop', 'SubagentStop']) quiet(run(w, base(w, ev), { HORDE_WORK_HOOK_WAIT_MS: '300' }));
  const u = units(w);
  assert.equal(u.length, 1);
  assert.equal(u[0].outcome, 'done');
});

test('a stop with no start still records the unit and ends it (the start was missed)', () => {
  const w = world();
  putTranscript(w, AGENT, 'T-0001 verify');
  quiet(run(w, base(w, 'SubagentStop')));
  assert.equal(units(w)[0].outcome, 'done');
});

// ---------------------------------------------------------------------------------------------------------
// never blocks, never fails

test('no home: exit 0, nothing printed, one logged line', () => {
  const w = world();
  const r = run(w, base(w, 'SubagentStart'), { HORDE_HOME: undefined });
  quiet(r);
  assert.match(logText(w), /fleet\.db/);
});

test('bad stdin, an empty payload, an unknown event and a payload with no agent id: exit 0, silent', () => {
  const w = world();
  quiet(run(w, null, {}, 'this is not json'));
  quiet(run(w, null, {}, ''));
  quiet(run(w, { hook_event_name: 'Stop', session_id: PARENT }));
  quiet(run(w, base(w, 'SubagentStart', { agent_id: undefined })));
  quiet(run(w, base(w, 'SubagentStart', { session_id: 'not-a-uuid' })));
  assert.equal(units(w).length, 0);
  assert.match(logText(w), /skipped: payload has no usable session_id or agent_id/);
});

test('a locked fleet.db costs a bounded wait, then exit 0 with fleet.db busy in the log', () => {
  const w = world();
  putTranscript(w, AGENT, 'T-0001 build');
  const db = openStore(dbPathFor(w.home));
  db.exec('BEGIN IMMEDIATE');
  try {
    const r = run(w, base(w, 'SubagentStart'), { HORDE_WORK_HOOK_WAIT_MS: '300' });
    quiet(r);
    assert.ok(r.ms < 7000, 'returned within the bound (' + r.ms + ' ms)');
    assert.match(logText(w), /fleet\.db busy/);
  } finally {
    db.exec('ROLLBACK');
    db.close();
  }
  assert.equal(units(w).length, 0);
});

test('a database that is not fleet.db at all: exit 0, silent, logged', () => {
  const w = world();
  fs.writeFileSync(dbPathFor(w.home), 'this is not a database');
  quiet(run(w, base(w, 'SubagentStart')));
  assert.ok(logText(w).length > 0);
});

// ---------------------------------------------------------------------------------------------------------
// a warg ends with its session

function seedWarg(w) {
  const db = openStore(dbPathFor(w.home));
  startWork(db, { kind: 'warg', parentSession: PARENT, session: WARG, workType: 'build', domain: 'decisions-page', at: T0 + 10 });
  db.close();
}

test('SessionEnd of a warg (a fleet record with a parent and no role) ends its work unit', () => {
  const w = world();
  seedWarg(w);
  putRegistry(w, WARG, { origin: 'fleet', parent: PARENT, owner: 'F' });
  quiet(run(w, { hook_event_name: 'SessionEnd', session_id: WARG, reason: 'other' }));
  const u = units(w).find((x) => x.kind === 'warg');
  assert.equal(u.outcome, 'done');
});

test('SessionEnd with reason clear or resume leaves the warg unit running; a real end reason ends it', () => {
  const w = world();
  seedWarg(w);
  putRegistry(w, WARG, { origin: 'fleet', parent: PARENT, owner: 'F' });
  quiet(run(w, { hook_event_name: 'SessionEnd', session_id: WARG, reason: 'clear' }));
  quiet(run(w, { hook_event_name: 'SessionEnd', session_id: WARG, reason: 'resume' }));
  assert.equal(units(w).find((x) => x.kind === 'warg').outcome, 'running');
  quiet(run(w, { hook_event_name: 'SessionEnd', session_id: WARG, reason: 'prompt_input_exit' }));
  assert.equal(units(w).find((x) => x.kind === 'warg').outcome, 'done');
});

test('SessionEnd of an Orc, an unregistered session or a stray record ends nothing', () => {
  const w = world();
  seedWarg(w);
  quiet(run(w, { hook_event_name: 'SessionEnd', session_id: PARENT }));
  quiet(run(w, { hook_event_name: 'SessionEnd', session_id: WARG }));
  putRegistry(w, WARG, { origin: 'user', owner: 'founder' });
  quiet(run(w, { hook_event_name: 'SessionEnd', session_id: WARG }));
  putRegistry(w, WARG, { origin: 'fleet', owner: 'F' });
  quiet(run(w, { hook_event_name: 'SessionEnd', session_id: WARG }));
  assert.equal(units(w).find((x) => x.kind === 'warg').outcome, 'running');
});

test('a registry kind decides over the older role: kind orc is not ended, kind warg is', () => {
  const w = world();
  seedWarg(w);
  putRegistry(w, WARG, { kind: 'orc', origin: 'fleet', parent: PARENT });
  quiet(run(w, { hook_event_name: 'SessionEnd', session_id: WARG }));
  assert.equal(units(w).find((x) => x.kind === 'warg').outcome, 'running');
  putRegistry(w, WARG, { kind: 'warg', role: 'orchestrator', parent: PARENT });
  quiet(run(w, { hook_event_name: 'SessionEnd', session_id: WARG }));
  assert.equal(units(w).find((x) => x.kind === 'warg').outcome, 'done');
});

test('a warg whose start never happened: its session end is refused quietly, exit 0, logged', () => {
  const w = world();
  putRegistry(w, WARG, { origin: 'fleet', parent: PARENT });
  quiet(run(w, { hook_event_name: 'SessionEnd', session_id: WARG }));
  assert.match(logText(w), /no work unit was started/);
});

// ---------------------------------------------------------------------------------------------------------
// the pure parts

test('kindOfRecord reads kind first, then role, then a fleet record with a parent', () => {
  assert.equal(kindOfRecord({ kind: 'thrall' }), 'thrall');
  assert.equal(kindOfRecord({ kind: 'warg', role: 'master' }), 'warg');
  assert.equal(kindOfRecord({ kind: 'nonsense', role: 'orchestrator' }), 'orc');
  assert.equal(kindOfRecord({ role: 'master' }), 'thrall');
  assert.equal(kindOfRecord({ origin: 'fleet', parent: 'x' }), 'warg');
  assert.equal(kindOfRecord({ origin: 'user', parent: 'x' }), null);
  assert.equal(kindOfRecord({ origin: 'fleet', parent: '' }), null);
  assert.equal(kindOfRecord(null), null);
});

test('taskOf and briefOf read the first line and the first user message', () => {
  assert.equal(taskOf('\n\nT-0326 do it T-0001'), 'T-0326');
  assert.equal(taskOf('no task here\nT-0001'), null);
  assert.equal(taskOf('XT-0001 or T-12 are not tasks'), null);
  const w = world();
  const f = path.join(w.dir, 'x.jsonl');
  fs.writeFileSync(f, JSON.stringify({ message: { content: [{ type: 'text', text: 'blocks one' }, { type: 'text', text: 'two' }] } }) + '\n');
  assert.equal(briefOf(f), 'blocks one\ntwo');
  assert.equal(briefOf(path.join(w.dir, 'missing.jsonl')), null);
});
