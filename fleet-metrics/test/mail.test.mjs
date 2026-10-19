// Tests of the phone-message hops read from the relay journal, and of their latency report, on a
// synthetic journal. Run: node --test fleet-metrics/test/mail.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { openStore } from '../store.mjs';
import { runCollect } from '../collect.mjs';
import { collectMailHops, latencyPairs, latencyLines, percentile, parseHeader } from '../mail.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const CLI = path.join(here, '..', 'cli.mjs');
const FROM = 'af37' + '0'.repeat(28);
const FROM2 = 'be11' + '0'.repeat(28);

const header = (o) => JSON.stringify({ v: 1, direction: 'in', key: o.from + '/' + o.channel + '/' + o.seq + '/' + 'a'.repeat(24), from: o.from, channel: o.channel,
  kind: 'text', seq: o.seq, nonce: 'a'.repeat(24), ts: o.ts, recordedAt: o.recordedAt, envelopeChars: 5, ...(o.extra || {}) });

function rig() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-meter-mail-'));
  const journal = path.join(dir, 'journal');
  const store = openStore(path.join(dir, 'home'));
  const put = (o, { direction = 'in', body = header(o) + '\nENVELOPE', name } = {}) => {
    const d = path.join(journal, direction, 's-' + o.from, 'c-' + o.channel);
    fs.mkdirSync(d, { recursive: true });
    fs.writeFileSync(path.join(d, name || String(o.seq).padStart(16, '0') + '.rec'), body);
  };
  return { dir, journal, store, put, home: path.join(dir, 'home'), collect: () => collectMailHops({ store, journal }), done: () => { store.close(); fs.rmSync(dir, { recursive: true, force: true }); } };
}
const all = (s, sql, ...a) => s.db.prepare(sql).all(...a);

test('two hops per message, keyed by the journal address, on the right clocks', () => {
  const r = rig();
  r.put({ from: FROM, channel: 'chat', seq: 11, ts: 1000, recordedAt: 1500 });
  const c = r.collect();
  assert.deepEqual([c.added, c.skipped], [2, 0]);
  const rows = all(r.store, 'SELECT * FROM mail_hops ORDER BY at');
  assert.equal(rows.length, 2);
  const id = 's-' + FROM + '/c-chat/11';
  assert.deepEqual(rows.map((x) => [x.message_id, x.hop, x.at, x.clock, x.source, x.from_session, x.to_session]),
    [[id, 'phone_sent', 1000, 'phone', 'mail', FROM, ''], [id, 'pc_journal', 1500, 'pc', 'mail', FROM, '']]);
  r.done();
});

test('a second pass adds nothing; a new record is picked up alone', () => {
  const r = rig();
  r.put({ from: FROM, channel: 'chat', seq: 1, ts: 10, recordedAt: 20 });
  r.collect();
  const again = r.collect();
  assert.equal(again.added, 0);
  r.put({ from: FROM, channel: 'chat', seq: 2, ts: 30, recordedAt: 45 });
  assert.equal(r.collect().added, 2);
  assert.equal(all(r.store, 'SELECT COUNT(*) AS n FROM mail_hops').at(0).n, 4);
  r.done();
});

test('a malformed header is skipped and counted, and the records after it are still read', () => {
  const r = rig();
  r.put({ from: FROM, channel: 'chat', seq: 1, ts: 1, recordedAt: 2 }, { body: 'this is not json\nENVELOPE' });
  r.put({ from: FROM, channel: 'chat', seq: 2, ts: 1, recordedAt: 2 }, { body: '{"v":1,"direction":"in"' }); // cut short, no newline
  r.put({ from: FROM, channel: 'chat', seq: 3, ts: 'soon', recordedAt: 2 });
  r.put({ from: FROM, channel: 'chat', seq: 4, ts: 1, recordedAt: -5 });
  r.put({ from: FROM, channel: 'chat', seq: 5, ts: 1, recordedAt: 2 }, { body: header({ from: FROM, channel: 'chat', seq: 99, ts: 1, recordedAt: 2 }) + '\nE' }); // says it is another seq
  r.put({ from: FROM, channel: 'chat', seq: 6, ts: 100, recordedAt: 140 });
  const c = r.collect();
  assert.equal(c.skipped, 5);
  assert.equal(c.added, 2);
  assert.deepEqual(all(r.store, 'SELECT DISTINCT message_id FROM mail_hops').map((x) => x.message_id), ['s-' + FROM + '/c-chat/6']);
  r.done();
});

test('outgoing records, lock files, temporary files and foreign folders are not read', () => {
  const r = rig();
  r.put({ from: FROM, channel: 'chat', seq: 1, ts: 1, recordedAt: 2 }, { direction: 'out' });
  r.put({ from: FROM, channel: 'chat', seq: 2, ts: 1, recordedAt: 2 }, { name: 'lock' });
  r.put({ from: FROM, channel: 'chat', seq: 3, ts: 1, recordedAt: 2 }, { name: 'writing-' + 'f'.repeat(32) + '.part' });
  r.put({ from: FROM, channel: 'chat', seq: 4, ts: 1, recordedAt: 2 }, { name: '0000000000000004.done' });
  fs.mkdirSync(path.join(r.journal, 'in', 'not-a-stream'), { recursive: true });
  const c = r.collect();
  assert.deepEqual([c.added, c.skipped, c.seen], [0, 0, 0]);
  r.done();
});

test('the journal is only read: every file is byte for byte as it was, and a missing journal is no error', () => {
  const r = rig();
  r.put({ from: FROM, channel: 'chat', seq: 1, ts: 1, recordedAt: 2 });
  const file = path.join(r.journal, 'in', 's-' + FROM, 'c-chat', '0000000000000001.rec');
  const before = fs.readFileSync(file);
  const mtime = fs.statSync(file).mtimeMs;
  r.collect();
  assert.ok(before.equals(fs.readFileSync(file)));
  assert.equal(fs.statSync(file).mtimeMs, mtime);
  assert.deepEqual(fs.readdirSync(path.join(r.journal, 'in', 's-' + FROM, 'c-chat')), ['0000000000000001.rec']);
  assert.deepEqual(collectMailHops({ store: r.store, journal: path.join(r.dir, 'nowhere') }), { added: 0, skipped: 0, seen: 0 });
  assert.deepEqual(collectMailHops({ store: r.store }), { added: 0, skipped: 0, seen: 0 }); // no home, no journal: nothing to read
  r.done();
});

test('collect reads the journal under the home by default, and says what it found', async () => {
  const r = rig();
  const underHome = path.join(r.home, 'relay', 'journal', 'in', 's-' + FROM, 'c-chat');
  fs.mkdirSync(underHome, { recursive: true });
  fs.writeFileSync(path.join(underHome, '0000000000000007.rec'), header({ from: FROM, channel: 'chat', seq: 7, ts: 5, recordedAt: 9 }) + '\nE');
  const res = await runCollect({ store: r.store, opts: { home: r.home }, readers: [] });
  assert.equal(res.mail.added, 2);
  r.done();
});

test('parseHeader insists on the folder and file name agreeing with the header', () => {
  const line = header({ from: FROM, channel: 'chat', seq: 3, ts: 1, recordedAt: 2 });
  assert.ok(parseHeader(line, FROM, 'chat', 3));
  assert.equal(parseHeader(line, FROM2, 'chat', 3), null);
  assert.equal(parseHeader(line, FROM, 'other', 3), null);
  assert.equal(parseHeader(line, FROM, 'chat', 4), null);
  assert.equal(parseHeader(null, FROM, 'chat', 3), null);
  assert.equal(parseHeader(line.replace('"direction":"in"', '"direction":"out"'), FROM, 'chat', 3), null);
});

test('latency: p50 and p95 per adjacent pair, and a pair across two clocks is flagged', () => {
  assert.equal(percentile([], 50), null);
  assert.equal(percentile([5], 95), 5);
  assert.equal(percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 50), 5);
  assert.equal(percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 95), 10);
  const hops = [];
  for (let i = 1; i <= 10; i++) {
    hops.push({ message_id: 'm' + i, hop: 'phone_sent', at: 1000 * i, clock: 'phone' });
    hops.push({ message_id: 'm' + i, hop: 'pc_journal', at: 1000 * i + i * 100, clock: 'pc' });
    if (i <= 4) hops.push({ message_id: 'm' + i, hop: 'mailed', at: 1000 * i + i * 100 + 50, clock: 'pc' });
  }
  hops.push({ message_id: 'skew', hop: 'phone_sent', at: 90000, clock: 'phone' });
  hops.push({ message_id: 'skew', hop: 'pc_journal', at: 89000, clock: 'pc' }); // the phone's clock runs ahead
  const pairs = latencyPairs(hops);
  assert.equal(pairs.length, 2);
  const [a, b] = pairs;
  assert.deepEqual([a.from, a.to, a.n, a.crossClock, a.negative], ['phone_sent', 'pc_journal', 11, true, 1]);
  assert.equal(a.p50, 500);
  assert.equal(a.p95, 1000);
  assert.deepEqual([b.from, b.to, b.n, b.crossClock, b.p50], ['pc_journal', 'mailed', 4, false, 50]);
  const lines = latencyLines(pairs);
  assert.match(lines[0], /^phone_sent -> pc_journal: n=11 p50=500 ms p95=1000 ms CROSSES CLOCKS \(phone vs pc\).* 1 negative$/);
  assert.match(lines[1], /^pc_journal -> mailed: n=4 p50=50 ms p95=50 ms$/);
  assert.deepEqual(latencyLines([]), ['latency: no message has two hops yet']);
});

test('command line: collect reads a journal, latency prints the pairs', () => {
  const r = rig();
  r.put({ from: FROM, channel: 'chat', seq: 1, ts: 1000, recordedAt: 1400 });
  r.put({ from: FROM, channel: 'chat', seq: 2, ts: 2000, recordedAt: 2600 });
  const env = { PATH: process.env.PATH, SystemRoot: process.env.SystemRoot, HORDE_HOME: r.home };
  const projects = path.join(r.dir, 'projects');
  fs.mkdirSync(projects);
  const agents = path.join(r.dir, 'agents');
  fs.mkdirSync(agents);
  const c = spawnSync(process.execPath, [CLI, 'collect', '--agents', agents, '--projects', projects, '--journal', r.journal], { env, encoding: 'utf8' });
  assert.equal(c.status, 0, c.stderr);
  assert.match(c.stdout, /mail: journal_records=2 hops_added=4 skipped_headers=0/);
  const l = spawnSync(process.execPath, [CLI, 'latency'], { env, encoding: 'utf8' });
  assert.equal(l.status, 0, l.stderr);
  assert.match(l.stdout, /phone_sent -> pc_journal: n=2 p50=400 ms p95=600 ms CROSSES CLOCKS/);
  const s = spawnSync(process.execPath, [CLI, 'status'], { env, encoding: 'utf8' });
  assert.match(s.stdout, /mail_hops: 4 rows/);
  assert.match(s.stdout, /tokens_usage: 0 rows/);
  r.done();
});

test('mail_hops orc_id stays NULL until fleet.db links sessions to Orcs', () => {
  const r = rig();
  r.put({ from: FROM, channel: 'chat', seq: 1, ts: 1, recordedAt: 2 });
  r.collect();
  assert.deepEqual(all(r.store, 'SELECT DISTINCT orc_id FROM mail_hops').map((x) => x.orc_id), [null]);
  r.done();
});
