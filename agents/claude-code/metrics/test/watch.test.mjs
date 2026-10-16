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

// ---- the first run's silent baseline, one message per run, and stale hits ----

const HOUR = 3600000;
const other = (r, n) => path.join(r.projects, 'p', '5555555' + n + '-eeee-4eee-8eee-00000000000' + n + '.jsonl');
const prime = (r) => r.watch(Date.now()); // a run that finds nothing: it only records that the watch has run

test('first ever run: stops older than 30 minutes are recorded as alerted silently and send nothing; a young one still alerts', async () => {
  const r = rig();
  const now = Date.now();
  fx.writeLines(r.file, [fx.limitHit('hit-old', now - 2 * HOUR)]);
  fx.writeLines(other(r, 1), [fx.limitHit('hit-older', now - 5 * HOUR)]);
  fx.writeLines(other(r, 2), [fx.limitHit('hit-young', now - 10 * MIN)]);
  const res = await r.watch(now);
  assert.equal(res.silent, 2);
  assert.equal(res.alerts, 1);
  assert.equal(r.sent.length, 1);
  assert.match(r.sent[0], /10 minutes ago/);
  const byHit = Object.fromEntries(limits(r.store).map((x) => [x.hit_uuid, x]));
  for (const h of ['hit-old', 'hit-older']) {
    assert.ok(byHit[h].alerted_at != null, h);
    assert.equal(byHit[h].alerted_silently, 1, h);
  }
  assert.equal(byHit['hit-young'].alerted_silently, 0);
  // Later runs repeat nothing.
  const again = await r.watch(now + 5 * MIN);
  assert.equal(again.silent, 0);
  assert.equal(again.alerts, 0);
  assert.equal(r.sent.length, 1);
  r.done();
});

test('after the first run, a stop older than 30 minutes is NOT silenced', async () => {
  const r = rig();
  await prime(r);
  const now = Date.now();
  fx.writeLines(r.file, [fx.limitHit('hit-1', now - 2 * HOUR)]);
  const res = await r.watch(now);
  assert.equal(res.silent, 0);
  assert.equal(res.alerts, 1);
  assert.equal(limits(r.store)[0].alerted_silently, 0);
  r.done();
});

test('several stopped sessions in one run are told in ONE message', async () => {
  const r = rig();
  await prime(r);
  const now = Date.now();
  fx.writeLines(r.file, [fx.limitHit('hit-1', now - 10 * MIN)]);
  fx.writeLines(other(r, 1), [fx.limitHit('hit-2', now - 20 * MIN, { type: 'seven_day' })]);
  fx.writeLines(other(r, 2), [fx.limitHit('hit-3', now - 30 * MIN)]);
  const res = await r.watch(now);
  assert.equal(res.alerts, 3);
  assert.equal(r.sent.length, 1);
  assert.match(r.sent[0], /3 sessions have been stopped/);
  assert.equal((r.sent[0].match(/\n- /g) || []).length, 3);
  assert.ok(r.sent[0].length < 1400);
  assert.ok(limits(r.store).every((x) => x.alerted_at != null));
  const again = await r.watch(now + 2 * MIN);
  assert.equal(r.sent.length, 1);
  assert.equal(again.alerts, 0);
  r.done();
});

test('a long list is cut to ten lines and says how many more', async () => {
  const r = rig();
  await prime(r);
  const now = Date.now();
  for (let i = 0; i < 13; i++) fx.writeLines(path.join(r.projects, 'p', 'aaaaaaa' + String(i).padStart(2, '0') + '-eeee-4eee-8eee-000000000000.jsonl'), [fx.limitHit('h' + i, now - 10 * MIN)]);
  await r.watch(now);
  assert.equal(r.sent.length, 1);
  assert.match(r.sent[0], /- and 3 more/);
  assert.ok(r.sent[0].length < 1500);
  r.done();
});

test('a stop 13 hours old sends nothing, even in a transcript touched just now', async () => {
  const r = rig();
  await prime(r);
  const now = Date.now();
  fx.writeLines(r.file, [fx.limitHit('hit-1', now - 13 * HOUR)]);
  const res = await r.watch(now);
  assert.equal(res.alerts, 0);
  assert.equal(r.sent.length, 0);
  // And just inside the limit it does speak.
  fx.writeLines(r.file, [fx.limitHit('hit-2', now - 11 * HOUR)]);
  assert.equal((await r.watch(now)).alerts, 1);
  r.done();
});
