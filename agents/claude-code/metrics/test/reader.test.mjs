// Tests of this harness's reader through the meter's real collector and store, on synthetic
// transcripts only. Run: node --test "agents/claude-code/metrics/test/*.test.mjs"
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { openStore } from '../../../../fleet-metrics/store.mjs';
import { runCollect, summaryLine } from '../../../../fleet-metrics/collect.mjs';
import { costOf } from '../../../../fleet-metrics/prices.mjs';
import reader from '../reader.mjs';
import * as fx from './fixtures/make-projects.mjs';

const BASE = Date.parse('2026-10-16T10:00:00Z');

function rig() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-meter-reader-'));
  const projects = path.join(dir, 'projects');
  const registry = path.join(dir, 'registry');
  fx.writeRegistry(registry);
  const store = openStore(path.join(dir, 'home'));
  const opts = { projects, registry };
  const collect = () => runCollect({ store, opts, readers: [reader] });
  return { dir, projects, registry, store, opts, collect, done: () => { store.close(); fs.rmSync(dir, { recursive: true, force: true }); } };
}
const all = (s, sql, ...a) => s.db.prepare(sql).all(...a);

test('a request repeated on several records is counted once', async () => {
  const r = rig();
  fx.writeProjects(r.projects, BASE);
  await r.collect();
  const rows = all(r.store, "SELECT * FROM tokens_requests WHERE request_id = 'req_A'");
  assert.equal(rows.length, 1);
  assert.equal(all(r.store, 'SELECT COUNT(*) AS n FROM tokens_requests').at(0).n, 4); // A, B, SUB, C
  r.done();
});

test('cost math for one known usage block (sonnet and the opus fallback)', async () => {
  // sonnet 3/15: (1000*3 + 2000*15 + 4000*3*1.25 + 1000*3*2 + 10000*3*0.1) / 1e6 = 0.057
  const u = { input: 1000, output: 2000, cache_read: 10000, cache_write_5m: 4000, cache_write_1h: 1000 };
  assert.ok(Math.abs(costOf('sonnet', u) - 0.057) < 1e-12);
  assert.ok(Math.abs(costOf('opus', u) - 0.095) < 1e-12);
  assert.ok(Math.abs(costOf('no-such-family', u) - 0.095) < 1e-12);
  const r = rig();
  fx.writeProjects(r.projects, BASE);
  await r.collect();
  const row = all(r.store, "SELECT * FROM tokens_requests WHERE request_id = 'req_A'")[0];
  assert.equal(row.family, 'sonnet');
  assert.ok(Math.abs(row.cost_usd - 0.057) < 1e-12);
  assert.equal(row.context_tokens, 1000 + 10000 + 4000 + 1000);
  assert.equal(row.cache_write_5m, 4000);
  assert.equal(row.cache_write_1h, 1000);
  r.done();
});

test('a rerun over the same bytes changes nothing', async () => {
  const r = rig();
  fx.writeProjects(r.projects, BASE);
  await r.collect();
  const dump = () => JSON.stringify(['tokens_requests', 'tokens_turns', 'tokens_agents', 'tokens_limits'].map((t) => all(r.store, 'SELECT * FROM ' + t + ' ORDER BY id')));
  const before = dump();
  const second = await r.collect();
  assert.equal(second.bytes, 0);
  assert.equal(Object.values(second.rows).reduce((a, b) => a + b, 0), 0);
  assert.equal(dump(), before);
  r.done();
});

test('a trailing partial line is left, then consumed once it is complete', async () => {
  const r = rig();
  const file = path.join(r.projects, 'p', fx.SID_ORC + '.jsonl');
  const line1 = fx.assistant('a1', BASE, 'req_1');
  const line2 = fx.assistant('a2', BASE + 1000, 'req_2');
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, line1 + '\n' + line2.slice(0, 40));
  const first = await r.collect();
  assert.equal(all(r.store, 'SELECT COUNT(*) AS n FROM tokens_requests')[0].n, 1);
  assert.equal(first.bytes, Buffer.byteLength(line1) + 1);
  assert.equal(r.store.getOffset(file).offset, Buffer.byteLength(line1) + 1);
  fs.writeFileSync(file, line1 + '\n' + line2 + '\n');
  await r.collect();
  assert.equal(all(r.store, 'SELECT COUNT(*) AS n FROM tokens_requests')[0].n, 2);
  r.done();
});

test('a file that shrank is read again from the start', async () => {
  const r = rig();
  const file = path.join(r.projects, 'p', fx.SID_ORC + '.jsonl');
  fx.writeLines(file, [fx.assistant('a1', BASE, 'req_1'), fx.assistant('a2', BASE + 1000, 'req_2'), fx.assistant('a3', BASE + 2000, 'req_3')]);
  await r.collect();
  assert.equal(all(r.store, 'SELECT COUNT(*) AS n FROM tokens_requests')[0].n, 3);
  // Rewritten shorter, with a different request: the old offset points past the end.
  fx.writeLines(file, [fx.assistant('b1', BASE + 5000, 'req_9')]);
  const again = await r.collect();
  assert.ok(again.bytes > 0);
  assert.equal(all(r.store, "SELECT COUNT(*) AS n FROM tokens_requests WHERE request_id = 'req_9'")[0].n, 1);
  r.done();
});

test('a subagent is linked to its parent Agent call by the sidecar tool-use id, and the route id is parsed', async () => {
  const r = rig();
  fx.writeProjects(r.projects, BASE);
  await r.collect();
  const rows = all(r.store, 'SELECT * FROM tokens_agents');
  assert.equal(rows.length, 1); // the parent's call and the sidecar are one row
  const a = rows[0];
  assert.equal(a.tool_use_id, fx.TOOL_USE);
  assert.equal(a.parent_session_id, fx.SID_ORC);
  assert.equal(a.agent_id, fx.AGENT_ID);
  assert.equal(a.agent_type, 'general-purpose');
  assert.equal(a.model_asked, 'haiku');
  assert.equal(a.model_used, 'haiku');
  assert.equal(a.route_id, 'ab12');
  assert.equal(a.orc, 'Q');
  const sub = all(r.store, "SELECT * FROM tokens_requests WHERE request_id = 'req_SUB'")[0];
  assert.equal(sub.agent_id, fx.AGENT_ID);
  assert.equal(sub.session_id, fx.SID_ORC);
  assert.equal(sub.rank, 'warg');
  r.done();
});

test('a description is cut to 120 characters and a missing route id stays null', async () => {
  const r = rig();
  const file = path.join(r.projects, 'p', fx.SID_ORC + '.jsonl');
  fx.writeLines(file, [fx.assistant('a1', BASE, 'req_1', { tools: [fx.agentCall('toolu_X', { description: 'x'.repeat(300) })] })]);
  await r.collect();
  const a = all(r.store, 'SELECT * FROM tokens_agents')[0];
  assert.equal(a.description.length, 120);
  assert.equal(a.route_id, null);
  r.done();
});

test('turns are told by their first words and carry their requests and cost', async () => {
  const r = rig();
  fx.writeProjects(r.projects, BASE);
  await r.collect();
  const t = Object.fromEntries(all(r.store, "SELECT * FROM tokens_turns WHERE session_id = ?", fx.SID_ORC).map((x) => [x.turn_uuid, x]));
  assert.equal(t.u1.trigger, 'founder');
  assert.equal(t.u2.trigger, 'mail');
  assert.equal(t.u1.requests, 1); // req_A once, the tool result opens no turn
  assert.equal(t.u2.requests, 1);
  assert.equal(t.u1.duration_ms, 1100); // to the last record of req_A
  assert.ok(t.u1.cost_usd > 0.05);
  r.done();
});

test('a turn that spans two passes gets requests from both', async () => {
  const r = rig();
  const file = path.join(r.projects, 'p', fx.SID_ORC + '.jsonl');
  fx.writeLines(file, [fx.user('u1', BASE, 'hello'), fx.assistant('a1', BASE + 1000, 'req_1')]);
  await r.collect();
  fs.appendFileSync(file, fx.assistant('a2', BASE + 2000, 'req_2') + '\n');
  await r.collect();
  const t = all(r.store, 'SELECT * FROM tokens_turns')[0];
  assert.equal(t.requests, 2);
  assert.equal(t.duration_ms, 2000);
  r.done();
});

test('orc and rank come from the registry; a session the registry does not know is unknown', async () => {
  const r = rig();
  fx.writeProjects(r.projects, BASE);
  fx.writeLines(path.join(r.projects, 'p', '99999999-dddd-4ddd-8ddd-000000000009.jsonl'), [fx.assistant('z1', BASE, 'req_Z')]);
  await r.collect();
  const by = (id) => all(r.store, 'SELECT orc, rank FROM tokens_requests WHERE session_id = ? AND agent_id IS NULL', id)[0];
  assert.deepEqual({ ...by(fx.SID_ORC) }, { orc: 'Q', rank: 'orc' });
  assert.deepEqual({ ...by(fx.SID_STUCK) }, { orc: 'Q', rank: 'warg' });
  assert.deepEqual({ ...by('99999999-dddd-4ddd-8ddd-000000000009') }, { orc: 'unknown', rank: 'unknown' });
  r.done();
});

test('a usage-limit hit is stored with its type and reset time, and stuck is filled when work resumes', async () => {
  const r = rig();
  const file = path.join(r.projects, 'p', fx.SID_STUCK + '.jsonl');
  fx.writeLines(file, [fx.user('v1', BASE, 'go'), fx.limitHit('hit-1', BASE + 1000, { type: 'seven_day', resetsAtSec: 1791889200 })]);
  await r.collect();
  let h = all(r.store, 'SELECT * FROM tokens_limits')[0];
  assert.equal(h.limit_type, 'seven_day');
  assert.equal(h.resets_at, 1791889200000);
  assert.equal(h.at, BASE + 1000);
  assert.equal(h.stuck_until, null);
  fs.appendFileSync(file, fx.user('v2', BASE + 61000, 'try again') + '\n');
  await r.collect(); // a LATER pass: the hit is already stored
  h = all(r.store, 'SELECT * FROM tokens_limits')[0];
  assert.equal(h.stuck_until, BASE + 61000);
  assert.equal(h.stuck_ms, 60000);
  r.done();
});

// ---- the backfill bounds ----

test('files older than --since-days are skipped and given no offset, so a larger window reads them later', async () => {
  const r = rig();
  const oldFile = path.join(r.projects, 'p', fx.SID_STUCK + '.jsonl');
  const newFile = path.join(r.projects, 'p', fx.SID_ORC + '.jsonl');
  fx.writeLines(oldFile, [fx.assistant('o1', BASE, 'req_old')]);
  fx.writeLines(newFile, [fx.assistant('n1', BASE, 'req_new')]);
  const tenDays = new Date(Date.now() - 10 * 86400000);
  fs.utimesSync(oldFile, tenDays, tenDays);

  const narrow = await runCollect({ store: r.store, opts: { ...r.opts, sinceDays: 5 }, readers: [reader] });
  assert.equal(narrow.skippedOld, 1);
  assert.equal(narrow.files, 1);
  assert.equal(all(r.store, 'SELECT COUNT(*) AS n FROM tokens_requests')[0].n, 1);
  assert.equal(r.store.getOffset(oldFile), null, 'no offset was recorded for the skipped file');

  const wide = await runCollect({ store: r.store, opts: { ...r.opts, sinceDays: 30 }, readers: [reader] });
  assert.equal(wide.skippedOld, 0);
  assert.equal(all(r.store, "SELECT COUNT(*) AS n FROM tokens_requests WHERE request_id = 'req_old'")[0].n, 1);
  // The default window is 14 days.
  const dflt = await runCollect({ store: r.store, opts: r.opts, readers: [reader] });
  assert.equal(dflt.skippedOld, 0);
  r.done();
});

test('--max-ms stops cleanly between files, keeps offsets, says partial, and the next pass continues', async () => {
  const r = rig();
  for (let i = 0; i < 4; i++) fx.writeLines(path.join(r.projects, 'p', 'bbbbbbb' + i + '-eeee-4eee-8eee-000000000000.jsonl'), [fx.assistant('x' + i, BASE + i, 'req_x' + i)]);
  // A clock that spends 100 ms per reading; budget 250 ms: the pass can start three files at most.
  let t = 1000000000000;
  const clock = () => (t += 100);
  const first = await runCollect({ store: r.store, opts: { ...r.opts, clock, maxMs: 250 }, readers: [reader] });
  assert.equal(first.partial, true);
  assert.ok(first.files >= 1 && first.files < 4, 'files ' + first.files);
  assert.equal(first.left, 4 - first.files);
  assert.match(summaryLine(first), /^collect: partial \(\d+ files left for the next pass\) files=/);
  const done = all(r.store, 'SELECT COUNT(*) AS n FROM tokens_requests')[0].n;
  assert.equal(done, first.files);
  assert.equal(all(r.store, 'SELECT COUNT(*) AS n FROM meter_offsets')[0].n, first.files);
  // The next pass, with room, finishes the rest and is no longer partial.
  const second = await runCollect({ store: r.store, opts: r.opts, readers: [reader] });
  assert.equal(second.partial, false);
  assert.equal(all(r.store, 'SELECT COUNT(*) AS n FROM tokens_requests')[0].n, 4);
  assert.doesNotMatch(summaryLine(second), /partial/);
  r.done();
});
