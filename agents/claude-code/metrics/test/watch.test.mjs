// Tests of the limit watch with this harness's reader, on synthetic transcripts.
// Run: node --test agents/claude-code/metrics/test/watch.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { openStore } from '../../../../fleet-metrics/store.mjs';
import { runCollect } from '../../../../fleet-metrics/collect.mjs';
import { runWatch, TAIL_BYTES } from '../../../../fleet-metrics/watch-limits.mjs';
import reader from '../reader.mjs';
import * as fx from './fixtures/make-projects.mjs';

const MIN = 60000;

function rig() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-meter-watch-'));
  const projects = path.join(dir, 'projects');
  const registry = path.join(dir, 'registry');
  fx.writeRegistry(registry);
  const store = openStore(path.join(dir, 'home'));
  const sent = [];
  const sender = async (text) => { sent.push(text); return { ok: true, detail: '' }; };
  const file = path.join(projects, 'p', fx.SID_STUCK + '.jsonl');
  const watch = (now, extra = {}) => runWatch({ store, opts: { projects, registry }, readers: [reader], now, sender, ...extra });
  return { dir, projects, store, sent, sender, file, watch, done: () => { store.close(); fs.rmSync(dir, { recursive: true, force: true }); } };
}
const limits = (s) => s.db.prepare('SELECT * FROM tokens_limits').all();

test('a hit that is the last record is reported once, after five minutes and not before', async () => {
  const r = rig();
  const hitAt = Date.now() - 10 * MIN;
  fx.writeLines(r.file, [fx.user('v1', hitAt - 5000, 'go'), fx.limitHit('hit-1', hitAt, { type: 'five_hour', resetsAtSec: Math.round(hitAt / 1000) + 7200 })]);

  const early = await r.watch(hitAt + 4 * MIN);
  assert.equal(early.alerts, 0);
  assert.equal(r.sent.length, 0);

  const due = await r.watch(hitAt + 6 * MIN);
  assert.equal(due.alerts, 1);
  assert.equal(r.sent.length, 1);
  assert.match(r.sent[0], /Q \(session 22222222\)/);
  assert.match(r.sent[0], /5-hour usage limit/);
  assert.match(r.sent[0], /resets at /);
  assert.match(r.sent[0], /Nothing was typed into it/);
  assert.ok(limits(r.store)[0].alerted_at != null);

  const again = await r.watch(hitAt + 20 * MIN);
  assert.equal(again.alerts, 0);
  assert.equal(r.sent.length, 1);
  r.done();
});

test('a send that fails is not marked as told and is tried again', async () => {
  const r = rig();
  const hitAt = Date.now() - 10 * MIN;
  fx.writeLines(r.file, [fx.limitHit('hit-1', hitAt)]);
  const failing = await r.watch(hitAt + 6 * MIN, { sender: async () => ({ ok: false, detail: 'no seat' }) });
  assert.equal(failing.alerts, 0);
  assert.equal(failing.failed, 1);
  assert.equal(limits(r.store)[0].alerted_at, null);
  const ok = await r.watch(hitAt + 8 * MIN);
  assert.equal(ok.alerts, 1);
  r.done();
});

test('work after a hit sends nothing and fills stuck_until and stuck_ms', async () => {
  const r = rig();
  const hitAt = Date.now() - 30 * MIN;
  fx.writeLines(r.file, [fx.limitHit('hit-1', hitAt), fx.user('v2', hitAt + 12 * MIN, 'continue')]);
  const res = await r.watch(Date.now());
  assert.equal(res.alerts, 0);
  assert.equal(r.sent.length, 0);
  const h = limits(r.store)[0];
  assert.equal(h.stuck_until, hitAt + 12 * MIN);
  assert.equal(h.stuck_ms, 12 * MIN);
  r.done();
});

test('a hit already alerted is filled in later when the session resumes, without a second message', async () => {
  const r = rig();
  const hitAt = Date.now() - 30 * MIN;
  fx.writeLines(r.file, [fx.limitHit('hit-1', hitAt)]);
  await r.watch(hitAt + 6 * MIN);
  assert.equal(r.sent.length, 1);
  fs.appendFileSync(r.file, fx.assistant('a9', hitAt + 20 * MIN, 'req_9') + '\n');
  await r.watch(Date.now());
  assert.equal(r.sent.length, 1);
  const h = limits(r.store)[0];
  assert.equal(h.stuck_ms, 20 * MIN);
  assert.ok(h.alerted_at != null);
  r.done();
});

test('--dry-run says what it would send and changes nothing', async () => {
  const r = rig();
  const hitAt = Date.now() - 10 * MIN;
  fx.writeLines(r.file, [fx.limitHit('hit-1', hitAt)]);
  const res = await r.watch(hitAt + 6 * MIN, { dryRun: true });
  assert.equal(res.would.length, 1);
  assert.equal(r.sent.length, 0);
  assert.equal(limits(r.store).length, 0);
  r.done();
});

test('a transcript untouched for over six hours is not even opened', async () => {
  const r = rig();
  const hitAt = Date.now() - 10 * MIN;
  fx.writeLines(r.file, [fx.limitHit('hit-1', hitAt)]);
  const old = new Date(Date.now() - 7 * 3600 * 1000);
  fs.utimesSync(r.file, old, old);
  const res = await r.watch(Date.now());
  assert.equal(res.scanned, 0);
  assert.equal(r.sent.length, 0);
  r.done();
});

test('only the last 64 KB is read: a hit at the end of a large file is found, a hit before the tail is not', async () => {
  const r = rig();
  const hitAt = Date.now() - 10 * MIN;
  const filler = [];
  for (let i = 0; i < 1000; i++) filler.push(fx.assistant('f' + i, hitAt - 3600000 + i, 'req_f' + i));
  assert.ok(filler.join('\n').length > 3 * TAIL_BYTES);
  fx.writeLines(r.file, [fx.limitHit('hit-old', hitAt - 7200000), ...filler, fx.limitHit('hit-new', hitAt)]);
  const res = await r.watch(hitAt + 6 * MIN);
  assert.equal(res.alerts, 1);
  const rows = limits(r.store);
  assert.deepEqual(rows.map((x) => x.hit_uuid), ['hit-new']); // hit-old lies far before the last 64 KB
  r.done();
});

test('the watch and the collector agree on the same hit', async () => {
  const r = rig();
  const hitAt = Date.now() - 10 * MIN;
  fx.writeLines(r.file, [fx.limitHit('hit-1', hitAt)]);
  await r.watch(hitAt + 6 * MIN);
  await runCollect({ store: r.store, opts: { projects: r.projects, registry: path.join(r.dir, 'registry') }, readers: [reader] });
  assert.equal(limits(r.store).length, 1);
  assert.ok(limits(r.store)[0].alerted_at != null);
  r.done();
});
