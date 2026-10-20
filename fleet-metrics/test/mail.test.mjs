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
import { summaryLine, mailLine } from '../collect.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const CLI = path.join(here, '..', 'cli.mjs');
const FROM = 'af37' + '0'.repeat(28);
const FROM2 = 'be11' + '0'.repeat(28);
// A believable stamp: an hour ago (inside the plausibility window and inside latency's default 7 days).
const T0 = Date.now() - 3600000;

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
  r.put({ from: FROM, channel: 'chat', seq: 11, ts: T0 + 1000, recordedAt: T0 + 1500 });
  const c = r.collect();
  assert.deepEqual([c.added, c.skipped], [2, 0]);
  const rows = all(r.store, 'SELECT * FROM mail_hops ORDER BY at');
  assert.equal(rows.length, 2);
  const id = 's-' + FROM + '/c-chat/11';
  assert.deepEqual(rows.map((x) => [x.message_id, x.hop, x.at, x.clock, x.source, x.from_session, x.to_session]),
    [[id, 'phone_sent', T0 + 1000, 'phone', 'mail', FROM, ''], [id, 'pc_journal', T0 + 1500, 'pc', 'mail', FROM, '']]);
  r.done();
});

test('a second pass adds nothing; a new record is picked up alone', () => {
  const r = rig();
  r.put({ from: FROM, channel: 'chat', seq: 1, ts: T0 + 10, recordedAt: T0 + 20 });
  r.collect();
  const again = r.collect();
  assert.equal(again.added, 0);
  r.put({ from: FROM, channel: 'chat', seq: 2, ts: T0 + 30, recordedAt: T0 + 45 });
  assert.equal(r.collect().added, 2);
  assert.equal(all(r.store, 'SELECT COUNT(*) AS n FROM mail_hops').at(0).n, 4);
  r.done();
});

test('a malformed header is skipped and counted, and the records after it are still read', () => {
  const r = rig();
  r.put({ from: FROM, channel: 'chat', seq: 1, ts: T0 + 1, recordedAt: T0 + 2 }, { body: 'this is not json\nENVELOPE' });
  r.put({ from: FROM, channel: 'chat', seq: 2, ts: T0 + 1, recordedAt: T0 + 2 }, { body: '{"v":1,"direction":"in"' }); // cut short, no newline
  r.put({ from: FROM, channel: 'chat', seq: 3, ts: 'soon', recordedAt: 2 });
  r.put({ from: FROM, channel: 'chat', seq: 4, ts: 1, recordedAt: -5 });
  r.put({ from: FROM, channel: 'chat', seq: 5, ts: T0 + 1, recordedAt: T0 + 2 }, { body: header({ from: FROM, channel: 'chat', seq: 99, ts: T0 + 1, recordedAt: T0 + 2 }) + '\nE' }); // says it is another seq
  r.put({ from: FROM, channel: 'chat', seq: 6, ts: T0 + 100, recordedAt: T0 + 140 });
  const c = r.collect();
  assert.equal(c.skipped, 5);
  assert.equal(c.added, 2);
  assert.deepEqual(all(r.store, 'SELECT DISTINCT message_id FROM mail_hops').map((x) => x.message_id), ['s-' + FROM + '/c-chat/6']);
  r.done();
});

test('outgoing records, lock files, temporary files and foreign folders are not read', () => {
  const r = rig();
  r.put({ from: FROM, channel: 'chat', seq: 1, ts: T0 + 1, recordedAt: T0 + 2 }, { direction: 'out' });
  r.put({ from: FROM, channel: 'chat', seq: 2, ts: T0 + 1, recordedAt: T0 + 2 }, { name: 'lock' });
  r.put({ from: FROM, channel: 'chat', seq: 3, ts: T0 + 1, recordedAt: T0 + 2 }, { name: 'writing-' + 'f'.repeat(32) + '.part' });
  r.put({ from: FROM, channel: 'chat', seq: 4, ts: T0 + 1, recordedAt: T0 + 2 }, { name: '0000000000000004.done' });
  fs.mkdirSync(path.join(r.journal, 'in', 'not-a-stream'), { recursive: true });
  const c = r.collect();
  assert.deepEqual([c.added, c.skipped, c.seen], [0, 0, 0]);
  r.done();
});

test('the journal is only read: every file is byte for byte as it was, and a missing journal is no error', () => {
  const r = rig();
  r.put({ from: FROM, channel: 'chat', seq: 1, ts: T0 + 1, recordedAt: T0 + 2 });
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
  fs.writeFileSync(path.join(underHome, '0000000000000007.rec'), header({ from: FROM, channel: 'chat', seq: 7, ts: T0 + 5, recordedAt: T0 + 9 }) + '\nE');
  const res = await runCollect({ store: r.store, opts: { home: r.home }, readers: [] });
  assert.equal(res.mail.added, 2);
  r.done();
});

test('parseHeader insists on the folder and file name agreeing with the header', () => {
  const line = header({ from: FROM, channel: 'chat', seq: 3, ts: T0 + 1, recordedAt: T0 + 2 });
  const s3 = '0000000000000003';
  assert.ok(parseHeader(line, FROM, 'chat', s3));
  assert.equal(parseHeader(line, FROM2, 'chat', s3), null);
  assert.equal(parseHeader(line, FROM, 'other', s3), null);
  assert.equal(parseHeader(line, FROM, 'chat', '0000000000000004'), null);
  assert.equal(parseHeader(null, FROM, 'chat', s3), null);
  assert.equal(parseHeader(line.replace('"direction":"in"', '"direction":"out"'), FROM, 'chat', s3), null);
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
  hops.push({ message_id: 'back', hop: 'pc_journal', at: 5000, clock: 'pc' });
  hops.push({ message_id: 'back', hop: 'mailed', at: 4000, clock: 'pc' }); // one clock that stepped back
  const pairs = latencyPairs(hops);
  assert.equal(pairs.length, 2);
  const [a, b] = pairs;
  assert.deepEqual([a.from, a.to, a.n, a.crossClock, a.negative, a.lacking], ['phone_sent', 'pc_journal', 11, true, 1, 1]); // 'back' has no phone_sent
  assert.equal(a.p50, 500);
  assert.equal(a.p95, 1000);
  assert.deepEqual([b.from, b.to, b.n, b.crossClock, b.p50, b.negative, b.lacking], ['pc_journal', 'mailed', 5, false, 50, 1, 7]);
  const lines = latencyLines(pairs);
  assert.match(lines[0], /^phone_sent -> pc_journal: n=11 p50=500 ms p95=1000 ms lacking_a_hop=1 CROSSES CLOCKS \(phone vs pc\).* negative=1$/);
  assert.match(lines[1], /^pc_journal -> mailed: n=5 p50=50 ms p95=50 ms lacking_a_hop=7 negative=1$/);
  assert.deepEqual(latencyLines([]), ['latency: no message has two hops yet']);
});

test('command line: collect reads a journal, latency prints the pairs', () => {
  const r = rig();
  r.put({ from: FROM, channel: 'chat', seq: 1, ts: T0 + 1000, recordedAt: T0 + 1400 });
  r.put({ from: FROM, channel: 'chat', seq: 2, ts: T0 + 2000, recordedAt: T0 + 2600 });
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
  assert.match(l.stdout, /phone_sent -> pc_journal: n=2 p50=400 ms p95=600 ms lacking_a_hop=0 CROSSES CLOCKS/);
  const s = spawnSync(process.execPath, [CLI, 'status'], { env, encoding: 'utf8' });
  assert.match(s.stdout, /mail_hops: 4 rows/);
  assert.match(s.stdout, /tokens_usage: 0 rows/);
  r.done();
});

test('mail_hops orc_id stays NULL until fleet.db links sessions to Orcs', () => {
  const r = rig();
  r.put({ from: FROM, channel: 'chat', seq: 1, ts: T0 + 1, recordedAt: T0 + 2 });
  r.collect();
  assert.deepEqual(all(r.store, 'SELECT DISTINCT orc_id FROM mail_hops').map((x) => x.orc_id), [null]);
  r.done();
});

test('a stamp outside 2020-01-01 .. a day from now is skipped and counted, not stored', () => {
  const r = rig();
  const now = Date.now();
  r.put({ from: FROM, channel: 'chat', seq: 1, ts: 0, recordedAt: now });
  r.put({ from: FROM, channel: 'chat', seq: 2, ts: Date.parse('2019-12-31T23:59:59Z'), recordedAt: now });
  r.put({ from: FROM, channel: 'chat', seq: 3, ts: now, recordedAt: now + 2 * 86400000 });
  r.put({ from: FROM, channel: 'chat', seq: 4, ts: 9e15, recordedAt: now });
  r.put({ from: FROM, channel: 'chat', seq: 5, ts: Date.parse('2020-01-01T00:00:00Z'), recordedAt: now + 86400000 - 1000 }); // both edges are inside
  const c = r.collect();
  assert.deepEqual([c.added, c.skipped], [2, 4]);
  assert.deepEqual(all(r.store, 'SELECT DISTINCT message_id FROM mail_hops').map((x) => x.message_id), ['s-' + FROM + '/c-chat/5']);
  r.done();
});

test('the journal seq stays a string: one past 2^53 is refused, never rounded onto a neighbour', () => {
  const r = rig();
  r.put({ from: FROM, channel: 'chat', seq: 9007199254740993, ts: T0, recordedAt: T0 + 5 }, { name: '9007199254740993.rec' });
  r.put({ from: FROM, channel: 'chat', seq: 9007199254740992, ts: T0, recordedAt: T0 + 5 }, { name: '9007199254740992.rec' });
  const c = r.collect();
  assert.equal(c.added, 0);
  assert.equal(c.skipped, 2);
  assert.equal(parseHeader(header({ from: FROM, channel: 'chat', seq: 12, ts: T0, recordedAt: T0 }), FROM, 'chat', '0000000000000012').seq, '0000000000000012');
  r.done();
});

test('a skipped record is not opened again until its size or mtime changes', () => {
  const r = rig();
  const o = { from: FROM, channel: 'chat', seq: 1, ts: T0, recordedAt: T0 + 5 };
  const good = header(o) + '\nENVELOPE';
  r.put(o, { body: 'x'.repeat(good.length) });
  const file = path.join(r.journal, 'in', 's-' + FROM, 'c-chat', '0000000000000001.rec');
  const when = fs.statSync(file).mtime;
  assert.deepEqual([r.collect().skipped, r.collect().added], [1, 0]);
  fs.writeFileSync(file, good); // a good header under the SAME size and mtime: proof that it is not read again
  fs.utimesSync(file, when, when);
  const same = r.collect();
  assert.deepEqual([same.added, same.skipped], [0, 1]);
  const later = new Date(when.getTime() + 5000);
  fs.utimesSync(file, later, later);
  const changed = r.collect();
  assert.deepEqual([changed.added, changed.skipped], [2, 0]);
  r.done();
});

test('both hops of a message are stored together or not at all', () => {
  const r = rig();
  assert.throws(() => r.store.addHops([
    { at: T0, message_id: 'm', hop: 'pc_journal', from_session: FROM, to_session: '', clock: 'pc' },
    { at: T0, message_id: 'm', hop: 'not-a-hop', from_session: FROM, to_session: '', clock: 'phone' },
  ]));
  assert.equal(all(r.store, 'SELECT COUNT(*) AS n FROM mail_hops').at(0).n, 0);
  r.done();
});

test('a journal that cannot be read does not fail the transcript collect: counted, shown, exit stays 0', async () => {
  const r = rig();
  const broken = Object.create(r.store);
  broken.knownMessages = () => { throw new Error('journal went away'); };
  const res = await runCollect({ store: broken, opts: { home: r.home }, readers: [] });
  assert.equal(res.errors, 0);
  assert.equal(res.mail.errors, 1);
  assert.match(mailLine(res), /mail_errors=1$/);
  assert.match(summaryLine(res), /errors=0$/);
  const ok = await runCollect({ store: r.store, opts: { home: r.home }, readers: [] });
  assert.match(mailLine(ok), /mail_errors=0$/);
  r.done();
});

test('latency reads only messages with a hop inside the window, whole', () => {
  const r = rig();
  const day = 86400000;
  const now = Date.now();
  const hop = (id, h, at, clock) => r.store.addHop({ at, message_id: id, hop: h, from_session: FROM, to_session: '', clock });
  hop('old', 'phone_sent', now - 30 * day, 'phone'); hop('old', 'pc_journal', now - 30 * day + 500, 'pc');
  hop('edge', 'phone_sent', now - 8 * day, 'phone'); hop('edge', 'pc_journal', now - 6 * day, 'pc'); // straddles the 7-day line
  const ids = (since) => [...new Set(r.store.hopsSince(since).map((x) => x.message_id))].sort();
  assert.deepEqual(ids(now - 7 * day), ['edge']);
  assert.equal(r.store.hopsSince(now - 7 * day).length, 2); // the message is never cut in half
  assert.deepEqual(ids(now - 60 * day), ['edge', 'old']);
  r.done();
});

test('command line: --session must look like a session id (exit 2); latency takes --since-days', () => {
  const r = rig();
  const env = { PATH: process.env.PATH, SystemRoot: process.env.SystemRoot, HORDE_HOME: r.home };
  for (const bad of ['..\\x', 'abc', 'g'.repeat(10), 'a'.repeat(65), '']) {
    const l = spawnSync(process.execPath, [CLI, 'live', '--session', bad], { env, encoding: 'utf8' });
    assert.equal(l.status, 2, JSON.stringify(bad) + ' ' + l.stderr);
    assert.match(l.stderr, /--session must be a session id/);
  }
  const d = new Date(Date.now() - 20 * 86400000).toISOString();
  r.store.addHop({ at: Date.parse(d), message_id: 'old', hop: 'phone_sent', from_session: FROM, to_session: '', clock: 'phone' });
  r.store.addHop({ at: Date.parse(d) + 9, message_id: 'old', hop: 'pc_journal', from_session: FROM, to_session: '', clock: 'pc' });
  r.store.close();
  assert.match(spawnSync(process.execPath, [CLI, 'latency'], { env, encoding: 'utf8' }).stdout, /no message has two hops yet/);
  assert.match(spawnSync(process.execPath, [CLI, 'latency', '--since-days', '30'], { env, encoding: 'utf8' }).stdout, /n=1 p50=9 ms/);
  fs.rmSync(r.dir, { recursive: true, force: true });
});
