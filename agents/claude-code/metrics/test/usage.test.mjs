// Tests of the live view (tokens_usage) as this harness's reader feeds it, on synthetic transcripts only.
// Run: node --test "agents/claude-code/metrics/test/*.test.mjs"
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { openStore, IDLE_DONE_MS } from '../../../../fleet-metrics/store.mjs';
import { runCollect, runLive } from '../../../../fleet-metrics/collect.mjs';
import { contextLimitOf } from '../../../../fleet-metrics/prices.mjs';
import reader from '../reader.mjs';
import * as fx from './fixtures/make-projects.mjs';

const BASE = Date.parse('2026-10-16T10:00:00Z');

function rig(now = BASE + 5000) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-meter-usage-'));
  const projects = path.join(dir, 'projects');
  const registry = path.join(dir, 'registry');
  fx.writeRegistry(registry);
  const store = openStore(path.join(dir, 'home'));
  const opts = { projects, registry };
  const clock = { now };
  const ctx = { now: () => clock.now };
  return {
    dir, projects, store, opts, clock,
    collect: () => runCollect({ store, opts, readers: [reader], ctx }),
    live: (session = null) => runLive({ store, opts, readers: [reader], ctx, session }),
    done: () => { store.close(); fs.rmSync(dir, { recursive: true, force: true }); },
  };
}
const all = (s, sql, ...a) => s.db.prepare(sql).all(...a);
const usageOf = (s, session, agent = '') => all(s, 'SELECT * FROM tokens_usage WHERE session_id = ? AND agent_id = ?', session, agent)[0];

test('one row per session and per subagent, with totals summed from the request rows', async () => {
  const r = rig();
  fx.writeProjects(r.projects, BASE);
  await r.collect();
  assert.equal(all(r.store, 'SELECT COUNT(*) AS n FROM tokens_usage').at(0).n, 3); // main, its subagent, the stuck session
  const m = usageOf(r.store, fx.SID_ORC);
  // req_A and req_B are the two requests of the main session (a repeat of req_A counts once).
  assert.equal(m.input_tokens, 2000);
  assert.equal(m.output_tokens, 4000);
  assert.equal(m.cache_read_tokens, 20000);
  assert.equal(m.cache_write_tokens, 10000); // 5-minute plus 1-hour
  assert.equal(m.context_tokens, 16000); // the LAST request: 1000 + 10000 + 4000 + 1000
  assert.equal(m.context_limit, 200000);
  assert.equal(m.model, 'claude-sonnet-4-5');
  assert.equal(m.orc_id, null); // the Orc registry has no row for this session, so nothing is guessed from its label
  assert.equal(m.source, 'tokens');
  assert.equal(m.started_at, BASE);
  assert.equal(m.last_seen_at, BASE + 4000);
  assert.equal(m.at, m.last_seen_at);
  assert.ok(Math.abs(m.minutes_running - 4 / 60) < 1e-9);
  const a = usageOf(r.store, fx.SID_ORC, fx.AGENT_ID);
  assert.equal(a.model, 'claude-haiku-4-5');
  assert.equal(a.started_at, BASE + 1200);
  assert.equal(a.last_seen_at, BASE + 1500);
  r.done();
});

test('a session is running while it is recent and done once it has been quiet for the idle time', async () => {
  const r = rig(BASE + 5000);
  fx.writeProjects(r.projects, BASE);
  await r.collect();
  assert.equal(usageOf(r.store, fx.SID_ORC).state, 'running');
  assert.equal(usageOf(r.store, fx.SID_STUCK).state, 'running');
  // Nothing new is written; time passes. The next pass reads nothing and still closes the quiet rows.
  r.clock.now = BASE + 60000 + IDLE_DONE_MS + 1;
  const c = await r.collect();
  assert.equal(c.bytes, 0);
  assert.equal(usageOf(r.store, fx.SID_ORC).state, 'done');
  assert.equal(usageOf(r.store, fx.SID_STUCK).state, 'done');
  // A record arriving later opens it again: done is not a one-way door for the same session.
  fs.appendFileSync(path.join(r.projects, 'proj-one', fx.SID_ORC + '.jsonl'), fx.user('u9', r.clock.now - 1000, 'back again') + '\n');
  await r.collect();
  assert.equal(usageOf(r.store, fx.SID_ORC).state, 'running');
  r.done();
});

test('an agent goes running -> done when its call returns to the parent', async () => {
  const r = rig(BASE + 3000);
  const proj = path.join(r.projects, 'p');
  const main = path.join(proj, fx.SID_ORC + '.jsonl');
  const sub = path.join(proj, fx.SID_ORC, 'subagents');
  fx.writeLines(main, [fx.user('u1', BASE, 'go'), fx.assistant('a1', BASE + 1000, 'req_A', { tools: [fx.agentCall(fx.TOOL_USE)] })]);
  fx.writeLines(path.join(sub, 'agent-' + fx.AGENT_ID + '.jsonl'), [fx.user('s1', BASE + 1200, 'work'), fx.assistant('s2', BASE + 1500, 'req_SUB', { model: 'claude-haiku-4-5' })]);
  fs.writeFileSync(path.join(sub, 'agent-' + fx.AGENT_ID + '.meta.json'), JSON.stringify({ agentType: 'general-purpose', description: 'x', toolUseId: fx.TOOL_USE, model: 'haiku' }));
  await r.collect();
  assert.equal(usageOf(r.store, fx.SID_ORC, fx.AGENT_ID).state, 'running'); // still working, nothing has come back
  fs.appendFileSync(main, fx.toolResult('r1', BASE + 2000, fx.TOOL_USE) + '\n');
  await r.collect();
  assert.equal(usageOf(r.store, fx.SID_ORC, fx.AGENT_ID).state, 'done');
  assert.equal(usageOf(r.store, fx.SID_ORC).state, 'running'); // the parent is not done because its helper is
  assert.equal(all(r.store, 'SELECT done_at FROM tokens_agents').at(0).done_at, BASE + 2000);
  r.done();
});

test('an agent that keeps writing after its call returned (a background agent) is still running', async () => {
  const r = rig(BASE + 4000);
  const proj = path.join(r.projects, 'p');
  fx.writeLines(path.join(proj, fx.SID_ORC + '.jsonl'), [
    fx.assistant('a1', BASE + 1000, 'req_A', { tools: [fx.agentCall(fx.TOOL_USE)] }),
    fx.toolResult('r1', BASE + 1100, fx.TOOL_USE), // the "started" acknowledgement
  ]);
  const sub = path.join(proj, fx.SID_ORC, 'subagents');
  fx.writeLines(path.join(sub, 'agent-' + fx.AGENT_ID + '.jsonl'), [fx.assistant('s2', BASE + 3000, 'req_SUB', { model: 'claude-haiku-4-5' })]);
  fs.writeFileSync(path.join(sub, 'agent-' + fx.AGENT_ID + '.meta.json'), JSON.stringify({ agentType: 'x', description: 'x', toolUseId: fx.TOOL_USE, model: 'haiku' }));
  await r.collect();
  assert.equal(usageOf(r.store, fx.SID_ORC, fx.AGENT_ID).state, 'running');
  r.done();
});

test('a rerun and later passes update the same row in place: never a second row for a session or agent', async () => {
  const r = rig();
  fx.writeProjects(r.projects, BASE);
  await r.collect();
  await r.collect();
  const idBefore = usageOf(r.store, fx.SID_ORC).id;
  fs.appendFileSync(path.join(r.projects, 'proj-one', fx.SID_ORC + '.jsonl'), fx.assistant('a9', BASE + 4500, 'req_D') + '\n');
  await r.collect();
  const rows = all(r.store, 'SELECT session_id, agent_id, COUNT(*) AS n FROM tokens_usage GROUP BY session_id, agent_id');
  assert.equal(rows.length, 3);
  assert.ok(rows.every((x) => x.n === 1));
  const m = usageOf(r.store, fx.SID_ORC);
  assert.equal(m.id, idBefore);
  assert.equal(m.output_tokens, 6000); // three requests now
  assert.equal(m.last_seen_at, BASE + 4500);
  assert.equal(m.started_at, BASE); // the start does not move when the file is read again from a later point
  r.done();
});

test('the context window: 200000 by default, 1000000 when marked [1m] or once a request has held more than 200000', async () => {
  assert.equal(contextLimitOf('claude-sonnet-4-5', 1000), 200000);
  assert.equal(contextLimitOf('claude-opus-4-5[1m]', 10), 1000000);
  assert.equal(contextLimitOf('claude-sonnet-4-5', 200000), 200000);
  assert.equal(contextLimitOf('claude-sonnet-4-5', 200001), 1000000);
  assert.equal(contextLimitOf('', 0), 200000);
  assert.equal(contextLimitOf('some-future-model', 0), 200000);
  const r = rig();
  const big = { ...fx.USAGE_KNOWN, cache_read_input_tokens: 300000 };
  fx.writeLines(path.join(r.projects, 'p', fx.SID_ORC + '.jsonl'), [fx.assistant('a1', BASE, 'req_BIG', { usage: big }), fx.assistant('a2', BASE + 1000, 'req_SMALL')]);
  await r.collect();
  const m = usageOf(r.store, fx.SID_ORC);
  assert.equal(m.context_tokens, 16000); // the last request is small, but the session has shown it holds the larger window
  assert.equal(m.context_limit, 1000000);
  r.done();
});

test('live: one session reads only the bytes written since the last pass, and touches no other session', async () => {
  const r = rig();
  fx.writeProjects(r.projects, BASE);
  await r.collect();
  const other = JSON.stringify(usageOf(r.store, fx.SID_STUCK));
  const main = path.join(r.projects, 'proj-one', fx.SID_ORC + '.jsonl');
  const add = fx.assistant('a9', BASE + 4500, 'req_D') + '\n';
  fs.appendFileSync(main, add);
  const l = await r.live(fx.SID_ORC);
  assert.equal(l.bytes, Buffer.byteLength(add));
  assert.equal(l.files, 2); // the session's own file and its one subagent's
  assert.equal(usageOf(r.store, fx.SID_ORC).last_seen_at, BASE + 4500);
  assert.equal(JSON.stringify(usageOf(r.store, fx.SID_STUCK)), other);
  const again = await r.live(fx.SID_ORC);
  assert.equal(again.bytes, 0);
  assert.equal(all(r.store, 'SELECT COUNT(*) AS n FROM tokens_usage').at(0).n, 3);
  const none = await r.live('99999999-no-such-session');
  assert.equal(none.files, 0);
  r.done();
});

test('live with no session: only transcripts changed in the last ten minutes', async () => {
  const r = rig(Date.now());
  fx.writeProjects(r.projects, Date.now() - 1000);
  const old = path.join(r.projects, 'proj-one', fx.SID_STUCK + '.jsonl');
  const longAgo = new Date(Date.now() - 3600000);
  fs.utimesSync(old, longAgo, longAgo);
  const l = await r.live();
  assert.equal(l.files, 2); // the Orc session and its subagent, not the hour-old one
  assert.equal(usageOf(r.store, fx.SID_STUCK), undefined);
  assert.ok(usageOf(r.store, fx.SID_ORC));
  assert.equal(l.sessions, 1);
  r.done();
});

test('a database made at schema 2 walks forward and keeps its rows', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-meter-migrate-'));
  const s = openStore(dir);
  s.db.exec('DROP TABLE tokens_usage; DROP TABLE mail_hops; ALTER TABLE tokens_agents DROP COLUMN done_at; PRAGMA user_version = 2');
  s.setState('k', 'v');
  s.close();
  const again = openStore(dir);
  assert.equal(again.getState('k'), 'v');
  assert.equal(all(again, 'SELECT COUNT(*) AS n FROM tokens_usage').at(0).n, 0);
  assert.equal(again.db.prepare('PRAGMA user_version').get().user_version, 3);
  again.close();
  fs.rmSync(dir, { recursive: true, force: true });
});

test('orc_id stays NULL until fleet.db links sessions: the registry folder name is a different kind of id', async () => {
  const r = rig();
  fx.writeProjects(r.projects, BASE);
  const reg = path.join(r.dir, 'home', 'orcs', 'registry');
  fs.mkdirSync(reg, { recursive: true });
  // An Orc-only record (what the registry holds today) says nothing about any session.
  fs.writeFileSync(path.join(reg, '0000000001.json'), JSON.stringify({ schemaVersion: 1, sequence: 1, kind: 'orc-registered', data: { id: 'orc-q', letter: 'Q', name: 'Orc Q' } }));
  fs.writeFileSync(path.join(reg, '0000000002.json'), '{ not json');
  fs.writeFileSync(path.join(reg, '0000000003.json'), JSON.stringify({ sequence: 3, kind: 'x', data: { id: 'orc-q', sessionId: fx.SID_ORC } }));
  await r.collect();
  // Even a registry record that names this session gives no orc_id: its id is a lane folder, not fleet.db's ULID.
  assert.equal(usageOf(r.store, fx.SID_ORC).orc_id, null);
  assert.equal(usageOf(r.store, fx.SID_ORC, fx.AGENT_ID).orc_id, null);
  assert.equal(usageOf(r.store, fx.SID_STUCK).orc_id, null); // a label in the old attribution file ('Q') is not used
  r.done();
});
