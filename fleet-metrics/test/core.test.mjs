// Tests of the harness-neutral core (home, store, collector, command line) with a fake reader of the
// tests' own. Run: node --test fleet-metrics/test/core.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { openStore, SCHEMA_VERSION } from '../store.mjs';
import { runCollect } from '../collect.mjs';
import { resolveHome } from '../home.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const CLI = path.join(here, '..', 'cli.mjs');

// A reader of the tests' own: a file is lines of {"id","at"}, each one a request.
const READER_SRC = `
import fs from 'node:fs';
import path from 'node:path';
export default {
  id: 'fake',
  roots: (o) => [o.projects],
  listFiles: (root) => fs.readdirSync(root).filter((n) => n.endsWith('.log')).map((n) => path.join(root, n)),
  consume({ path: file, lines }) {
    if (file.includes('poison')) throw new Error('cannot be bound');
    const rows = [];
    for (const l of lines) {
      let o; try { o = JSON.parse(l); } catch { continue; }
      rows.push({ at: o.at, request_id: o.id, session_id: path.basename(file, '.log'), orc: 'T', rank: 'unknown', model: 'm', family: 'opus',
        input: 1, output: 1, cache_read: 0, cache_write_5m: 0, cache_write_1h: 0, context_tokens: 1, cost_usd: 0.5 });
    }
    return { tokens_requests: rows };
  },
  inspectTail({ path: file }) {
    if (!file.includes('stuck')) return null;
    return { session_id: 'stuck', agent_id: null, orc: 'T', last_is_hit: true, last_at: Date.now() - 600000,
      hits: [{ hit_uuid: 'h1', at: Date.now() - 600000, limit_type: 'five_hour', resets_at: null, resumed_at: null }] };
  },
};
`;

function rig() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-meter-core-'));
  const agents = path.join(dir, 'agents');
  fs.mkdirSync(path.join(agents, 'fake', 'metrics'), { recursive: true });
  fs.writeFileSync(path.join(agents, 'fake', 'metrics', 'reader.mjs'), READER_SRC);
  const projects = path.join(dir, 'projects');
  fs.mkdirSync(projects);
  const home = path.join(dir, 'home');
  const cli = (verb, ...more) => spawnSync(process.execPath, [CLI, verb, '--agents', agents, '--projects', projects, ...more],
    { env: { PATH: process.env.PATH, SystemRoot: process.env.SystemRoot, HORDE_HOME: home }, encoding: 'utf8' });
  return { dir, agents, projects, home, cli, done: () => fs.rmSync(dir, { recursive: true, force: true }) };
}
const line = (id, at) => JSON.stringify({ id, at }) + '\n';

test('HORDE_HOME unset or empty: one sentence on stderr, exit 2, and nothing is written', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-meter-nohome-'));
  for (const val of [undefined, '', '   ']) {
    const env = { PATH: process.env.PATH, SystemRoot: process.env.SystemRoot, USERPROFILE: dir, HOME: dir };
    if (val !== undefined) env.HORDE_HOME = val;
    const r = spawnSync(process.execPath, [CLI, 'status'], { env, cwd: dir, encoding: 'utf8' });
    assert.equal(r.status, 2, 'value ' + JSON.stringify(val));
    assert.match(r.stderr, /HORDE_HOME is not set/);
    assert.equal(r.stderr.trim().split('\n').length, 1);
    assert.equal(r.stdout, '');
  }
  assert.deepEqual(fs.readdirSync(dir), [], 'no file or folder was made, not even under the profile folder');
  fs.rmSync(dir, { recursive: true, force: true });
});

test('a relative HORDE_HOME is refused too', () => {
  assert.equal(resolveHome({ HORDE_HOME: 'relative/dir' }).ok, false);
  assert.equal(resolveHome({ HORDE_HOME: path.resolve('x') }).ok, true);
});

test('the schema is versioned, strict, WAL, and every metric row carries its source', () => {
  const r = rig();
  const s = openStore(r.home);
  assert.equal(s.db.prepare('PRAGMA user_version').get().user_version, SCHEMA_VERSION);
  assert.equal(s.db.prepare('PRAGMA journal_mode').get().journal_mode, 'wal');
  assert.equal(s.db.prepare('PRAGMA busy_timeout').get().timeout, 5000);
  for (const t of s.db.prepare("SELECT name, sql FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'").all()) {
    assert.match(t.sql, /STRICT/, t.name);
    assert.match(t.name, /^(tokens_[a-z]+|mail_[a-z]+|meter_offsets|meter_state)$/);
    if (t.name.startsWith('tokens_')) assert.match(t.sql, /source TEXT NOT NULL CHECK \(source = 'tokens'\)/, t.name);
  }
  // A row under the wrong source is refused by the database itself.
  assert.throws(() => s.db.exec("INSERT INTO tokens_turns (source, at, session_id, turn_uuid, trigger) VALUES ('other', 1, 's', 'u', 'founder')"));
  s.close();
  // Opening again is a no-op, not a second migration.
  const again = openStore(r.home);
  assert.equal(again.db.prepare('PRAGMA user_version').get().user_version, SCHEMA_VERSION);
  again.close();
  r.done();
});

test('a database from a newer version is refused, not damaged', () => {
  const r = rig();
  const s = openStore(r.home);
  s.db.exec('PRAGMA user_version = 99');
  s.close();
  assert.throws(() => openStore(r.home), /newer than this program/);
  r.done();
});

test('collector: partial line left, then consumed; rerun idempotent; shrink re-read', async () => {
  const r = rig();
  const reader = (await import('node:url')).pathToFileURL(path.join(r.agents, 'fake', 'metrics', 'reader.mjs')).href;
  const fake = (await import(reader)).default;
  const s = openStore(r.home);
  const run = () => runCollect({ store: s, opts: { projects: r.projects }, readers: [fake] });
  const n = () => s.db.prepare('SELECT COUNT(*) AS n FROM tokens_requests').get().n;
  const file = path.join(r.projects, 's1.log');

  fs.writeFileSync(file, line('a', 1) + '{"id":"b","at"');
  const p1 = await run();
  assert.equal(n(), 1);
  assert.equal(p1.bytes, Buffer.byteLength(line('a', 1)));
  fs.writeFileSync(file, line('a', 1) + line('b', 2));
  await run();
  assert.equal(n(), 2);

  const again = await run();
  assert.equal(again.bytes, 0);
  assert.equal(n(), 2);

  fs.writeFileSync(file, line('c', 3));
  const shrunk = await run();
  assert.equal(shrunk.bytes, Buffer.byteLength(line('c', 3)));
  assert.equal(n(), 3);
  s.close();
  r.done();
});

test('command line: collect then status against a temp home', () => {
  const r = rig();
  fs.writeFileSync(path.join(r.projects, 's1.log'), line('a', Date.now()) + line('b', Date.now()));
  const c = r.cli('collect');
  assert.equal(c.status, 0, c.stderr);
  assert.match(c.stdout, /^collect: files=1 skipped_old=0 new_bytes=\d+ rows: tokens_requests=2 tokens_turns=0 tokens_agents=0 tokens_limits=0 tokens_usage=0 ms=\d+/);
  const st = r.cli('status');
  assert.equal(st.status, 0, st.stderr);
  assert.match(st.stdout, /tokens_requests: 2 rows, newest 20/);
  assert.match(st.stdout, /database: .*fleet\.sqlite/);
  assert.match(st.stdout, /data age: /);
  assert.ok(fs.existsSync(path.join(r.home, 'metrics', 'fleet.sqlite')));
  const bad = r.cli('nonsense');
  assert.equal(bad.status, 1);
  r.done();
});

test('an alert is recorded once: a second markAlerted changes nothing and says so', () => {
  const r = rig();
  const s = openStore(r.home);
  s.apply({ tokens_limits: [{ at: 1, session_id: 's', orc: 'T', hit_uuid: 'h1', limit_type: 'five_hour', resets_at: null }] }, null);
  assert.equal(s.markAlerted('h1', 1000, true), true);
  assert.equal(s.markAlerted('h1', 2000, false), false);
  const row = s.limitByHit('h1');
  assert.equal(row.alerted_at, 1000);
  assert.equal(row.alerted_silently, 1);
  // Upserting the same hit again (as every watch run does) keeps both.
  s.apply({ tokens_limits: [{ at: 1, session_id: 's', orc: 'T', hit_uuid: 'h1', limit_type: 'five_hour', resets_at: null }] }, null);
  assert.equal(s.limitByHit('h1').alerted_at, 1000);
  s.close();
  r.done();
});

test('command line: a file that cannot be read is named, the rest is collected, and the exit is 1', () => {
  const r = rig();
  fs.writeFileSync(path.join(r.projects, 'poison.log'), line('p', Date.now()));
  fs.writeFileSync(path.join(r.projects, 'good.log'), line('g', Date.now() - 5000));
  const c = r.cli('collect');
  assert.equal(c.status, 1);
  assert.match(c.stdout, /tokens_requests=1 .* skipped=0 errors=1/);
  assert.match(c.stderr, /could not read .*poison.log: cannot be bound/);
  r.done();
});

test('command line: a watch whose message could not be delivered exits 1 and says so', () => {
  const r = rig();
  fs.writeFileSync(path.join(r.projects, 'stuck.log'), line('s', Date.now()));
  const w = r.cli('watch-limits'); // no --horde-script: there is no way to tell anyone
  assert.equal(w.status, 1);
  assert.match(w.stdout, /failed=1/);
  assert.match(w.stderr, /could not tell the master session/);
  r.done();
});
