// The one allocator of T-numbers (fleet-db/label-cli.mjs). Temp homes only.
import './own-profile.mjs';
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { DatabaseSync } from 'node:sqlite';
import { openStore, inWrite } from '../store.mjs';
import { MIGRATIONS } from '../schema.mjs';
import { newId } from '../write.mjs';
import { main } from '../label-cli.mjs';

const CLI = path.join(import.meta.dirname, '..', 'label-cli.mjs');
const dirs = [];
after(() => { for (const d of dirs) fs.rmSync(d, { recursive: true, force: true }); });

function home({ make = true } = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-db-label-'));
  dirs.push(dir);
  const file = path.join(dir, 'fleet.db');
  if (make) openStore(file).close();
  return { dir, file, env: { HORDE_HOME: dir, HORDE_LABEL_BUSY_MS: '100' } };
}

function run(env, ...argv) {
  const out = [];
  const err = [];
  const code = main(argv, env, (s) => out.push(s), (s) => err.push(s));
  return { code, out, err };
}

function addTask(file, key) {
  const db = openStore(file);
  inWrite(db, () => db.prepare('INSERT INTO task (id, key, title, source, created_at) VALUES (?, ?, ?, ?, 1)').run(newId(), key, 'a task', 'orc'));
  db.close();
}

const counter = (file) => {
  const db = new DatabaseSync(file, { readOnly: true });
  const n = db.prepare("SELECT next FROM label_seq WHERE kind = 'task'").get().next;
  db.close();
  return n;
};

test('the first number goes past the highest in the ledger', () => {
  const w = home();
  assert.deepEqual(run(w.env, 'take-task', '--above', '414').out, ['T-0415']);
  assert.equal(counter(w.file), 416);
});

test('the next number follows the counter, not a lower ledger', () => {
  const w = home();
  run(w.env, 'take-task', '--above', '414');
  assert.deepEqual(run(w.env, 'take-task', '--above', '10').out, ['T-0416']);
  assert.deepEqual(run(w.env, 'take-task', '--above', '0').out, ['T-0417']);
});

test('a ledger ahead of the counter raises it', () => {
  const w = home();
  run(w.env, 'take-task', '--above', '5');
  assert.deepEqual(run(w.env, 'take-task', '--above', '900').out, ['T-0901']);
});

test('the task rows raise it too, read as numbers and not as text', () => {
  const w = home();
  addTask(w.file, 'T-0999');
  addTask(w.file, 'T-1000');
  assert.deepEqual(run(w.env, 'take-task', '--above', '3').out, ['T-1001']);
});

test('eight processes at once get eight different numbers, in a row', async () => {
  const w = home();
  const one = () => new Promise((resolve) => {
    const p = spawn(process.execPath, ['--no-warnings', CLI, 'take-task', '--above', '414'], { env: { ...process.env, HORDE_HOME: w.dir, HORDE_LABEL_BUSY_MS: '20000' }, stdio: ['ignore', 'pipe', 'pipe'] });
    let o = '';
    let e = '';
    p.stdout.on('data', (d) => { o += d; });
    p.stderr.on('data', (d) => { e += d; });
    p.on('close', (c) => resolve({ c, o: o.trim(), e }));
  });
  const got = await Promise.all(Array.from({ length: 8 }, one));
  for (const r of got) assert.equal(r.c, 0, r.e);
  assert.deepEqual(got.map((r) => r.o).sort(), ['T-0415', 'T-0416', 'T-0417', 'T-0418', 'T-0419', 'T-0420', 'T-0421', 'T-0422']);
});

test('a held write lock is exit 3 and the words fleet.db busy, and takes no number', () => {
  const w = home();
  run(w.env, 'take-task', '--above', '1');
  const before = counter(w.file);
  const holder = openStore(w.file);
  holder.exec('BEGIN IMMEDIATE');
  try {
    assert.deepEqual((({ code, err }) => ({ code, err }))(run(w.env, 'take-task', '--above', '1')), { code: 3, err: ['fleet.db busy'] });
  } finally {
    holder.exec('ROLLBACK');
    holder.close();
  }
  assert.equal(counter(w.file), before);
});

test('no fleet.db is exit 4, in words, and makes no file', () => {
  const w = home({ make: false });
  const r = run(w.env, 'take-task', '--above', '1');
  assert.deepEqual([r.code, r.err], [4, ['fleet.db does not exist yet (run horde db init)']]);
  assert.equal(fs.existsSync(w.file), false);
});

test('no home is exit 2', () => {
  const r = run({ HORDE_HOME: 'not-absolute' }, 'take-task', '--above', '1');
  assert.equal(r.code, 2);
  assert.match(r.err[0], /^fleet\.db: HORDE_HOME must be an absolute path/);
});

test('an older database is refused in words and not migrated', () => {
  const w = home({ make: false });
  const raw = new DatabaseSync(w.file);
  for (let v = 0; v < MIGRATIONS.length - 1; v++) raw.exec(MIGRATIONS[v]);
  raw.exec('PRAGMA user_version = ' + (MIGRATIONS.length - 1));
  raw.close();
  const r = run(w.env, 'take-task', '--above', '1');
  assert.equal(r.code, 1);
  assert.match(r.err[0], /needs migrating; run horde db init/);
  const check = new DatabaseSync(w.file, { readOnly: true });
  assert.equal(check.prepare('PRAGMA user_version').get().user_version, MIGRATIONS.length - 1);
  check.close();
});

test('a bad call is refused and takes nothing', () => {
  const w = home();
  for (const argv of [[], ['take-task'], ['take-task', '--above'], ['take', '--above', '1'], ['take-task', '--below', '1'], ['take-task', '--above', '1', 'x']]) {
    assert.equal(run(w.env, ...argv).code, 1, argv.join(' '));
  }
  for (const v of ['-1', '1.5', 'x', '', '1234567890']) assert.match(run(w.env, 'take-task', '--above', v).err[0], /^refused: --above/);
  assert.equal(counter(w.file), 1);
});
