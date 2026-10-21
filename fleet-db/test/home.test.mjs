// core/home.mjs - the one home rule for node: HORDE_HOME, else the pointer file, else REFUSED (no default).
// Every test names USERPROFILE as a folder it made under the temp folder, so the real pointer is never read
// (CONTRIBUTING 9).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resolveHordeHome, pointerPath, POINTER_NAME } from '../../core/home.mjs';
import { homeFromEnv, openStore, dbPathFor } from '../store.mjs';
import { resolveHome as metricsHome } from '../../fleet-metrics/home.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

function rig() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'horde-home-node-'));
  const profile = path.join(dir, 'profile');
  const homeA = path.join(dir, 'homeA');
  const homeB = path.join(dir, 'homeB');
  for (const d of [profile, homeA, homeB]) fs.mkdirSync(d);
  const point = (text) => fs.writeFileSync(path.join(profile, POINTER_NAME), text);
  const pointAt = (home) => point(JSON.stringify({ v: 1, hordeHome: home }));
  return { dir, profile, homeA, homeB, point, pointAt, done: () => fs.rmSync(dir, { recursive: true, force: true }) };
}

test('the pointer file is <USERPROFILE>\\.horde-home.json', () => {
  assert.equal(pointerPath({ USERPROFILE: 'C:\\somebody' }), path.join('C:\\somebody', '.horde-home.json'));
});

test('HORDE_HOME wins over the pointer', () => {
  const r = rig();
  r.pointAt(r.homeB);
  const got = resolveHordeHome({ HORDE_HOME: r.homeA, USERPROFILE: r.profile });
  assert.equal(got.ok, true);
  assert.equal(got.home, path.resolve(r.homeA));
  assert.equal(got.source, 'HORDE_HOME');
  r.done();
});

test('HORDE_HOME wins even when the pointer is bad (it is never read)', () => {
  const r = rig();
  r.point('not json at all');
  const got = resolveHordeHome({ HORDE_HOME: r.homeA, USERPROFILE: r.profile });
  assert.equal(got.ok, true);
  assert.equal(got.source, 'HORDE_HOME');
  r.done();
});

test('a relative HORDE_HOME is refused, and does not fall through to the pointer', () => {
  const r = rig();
  r.pointAt(r.homeB);
  const got = resolveHordeHome({ HORDE_HOME: 'relative\\home', USERPROFILE: r.profile });
  assert.equal(got.ok, false);
  assert.equal(got.kind, 'refused');
  assert.match(got.message, /absolute/);
  r.done();
});

test('with HORDE_HOME unset (or blank) the pointer names the home', () => {
  const r = rig();
  r.pointAt(r.homeB);
  for (const v of [undefined, '', '   ']) {
    const env = { USERPROFILE: r.profile };
    if (v !== undefined) env.HORDE_HOME = v;
    const got = resolveHordeHome(env);
    assert.equal(got.ok, true, JSON.stringify(v));
    assert.equal(got.home, path.resolve(r.homeB));
    assert.equal(got.source, 'pointer');
  }
  r.done();
});

test('the pointer is read on every call: a change is seen at the next one', () => {
  const r = rig();
  r.pointAt(r.homeA);
  const env = { USERPROFILE: r.profile };
  assert.equal(resolveHordeHome(env).home, path.resolve(r.homeA));
  r.pointAt(r.homeB);
  assert.equal(resolveHordeHome(env).home, path.resolve(r.homeB));
  fs.unlinkSync(path.join(r.profile, POINTER_NAME));
  assert.equal(resolveHordeHome(env).ok, false);
  r.done();
});

test('no HORDE_HOME and no pointer: unset, with no default folder', () => {
  const r = rig();
  const got = resolveHordeHome({ USERPROFILE: r.profile });
  assert.equal(got.ok, false);
  assert.equal(got.kind, 'unset');
  assert.match(got.message, /HORDE_HOME is not set/);
  assert.deepEqual(fs.readdirSync(r.profile), [], 'reading made nothing');
  r.done();
});

test('every bad pointer is refused, and the message names the file', () => {
  const r = rig();
  const file = path.join(r.profile, POINTER_NAME);
  // Folders that EXIST, so only the rule under test can refuse them: a non-ASCII name, a path relative to this process's
  // folder, and a path with no drive.
  const accented = path.join(r.dir, 'h\u00e9me');
  fs.mkdirSync(accented);
  const relativeToHere = path.relative(process.cwd(), r.homeA);
  const noDrive = r.homeA.slice(2);
  assert.ok(fs.existsSync(accented) && fs.existsSync(noDrive), 'CONTROL: the folders the cases name are there');
  assert.ok(!path.isAbsolute(relativeToHere) && fs.existsSync(relativeToHere), 'CONTROL: the relative path reaches homeA from here');
  const cases = {
    'missing hordeHome': JSON.stringify({ v: 1 }),
    'blank hordeHome': JSON.stringify({ v: 1, hordeHome: '  ' }),
    'hordeHome not a string': JSON.stringify({ v: 1, hordeHome: 7 }),
    'v 2': JSON.stringify({ v: 2, hordeHome: r.homeA }),
    'v a string': JSON.stringify({ v: '1', hordeHome: r.homeA }),
    'no v': JSON.stringify({ hordeHome: r.homeA }),
    'relative path': JSON.stringify({ v: 1, hordeHome: 'some\\folder' }),
    'relative path to a folder that exists': JSON.stringify({ v: 1, hordeHome: relativeToHere }),
    'drive-less path': JSON.stringify({ v: 1, hordeHome: '\\some\\folder' }),
    'drive-less path to a folder that exists': JSON.stringify({ v: 1, hordeHome: noDrive }),
    'folder missing': JSON.stringify({ v: 1, hordeHome: path.join(r.dir, 'nope') }),
    'a file, not a folder': JSON.stringify({ v: 1, hordeHome: file }),
    'not JSON': '{"v":1,',
    'a JSON array': '[1]',
    'JSON null': 'null',
    'non-ASCII (an existing folder)': '{"v":1,"hordeHome":"' + accented.replace(/\\/g, '\\\\') + '"}',
    'empty file': '',
  };
  for (const [name, text] of Object.entries(cases)) {
    r.point(text);
    const got = resolveHordeHome({ USERPROFILE: r.profile });
    assert.equal(got.ok, false, name);
    assert.equal(got.kind, 'refused', name);
    assert.ok(got.message.includes(file), name + ': message names the file: ' + got.message);
  }
  // A byte-order mark is a character that is not ASCII, too.
  fs.writeFileSync(file, Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(JSON.stringify({ v: 1, hordeHome: r.homeA }))]));
  const bom = resolveHordeHome({ USERPROFILE: r.profile });
  assert.equal(bom.ok, false);
  assert.ok(bom.message.includes(file));
  r.done();
});

test('a pointer that is a folder cannot be read: refused, named', () => {
  const r = rig();
  fs.mkdirSync(path.join(r.profile, POINTER_NAME));
  const got = resolveHordeHome({ USERPROFILE: r.profile });
  assert.equal(got.ok, false);
  assert.equal(got.kind, 'refused');
  assert.ok(got.message.includes(POINTER_NAME));
  r.done();
});

test('store: homeFromEnv gives the pointer home and refuses a bad pointer with the file named', () => {
  const r = rig();
  r.pointAt(r.homeA);
  assert.equal(homeFromEnv({ USERPROFILE: r.profile }), path.resolve(r.homeA));
  assert.equal(path.basename(dbPathFor(homeFromEnv({ USERPROFILE: r.profile }))), 'fleet.db');
  r.point('{"v":3}');
  assert.throws(() => homeFromEnv({ USERPROFILE: r.profile }), (e) => e.message.includes(POINTER_NAME));
  fs.unlinkSync(path.join(r.profile, POINTER_NAME));
  assert.throws(() => homeFromEnv({ USERPROFILE: r.profile }), /HORDE_HOME is not set/);
  r.done();
});

test('metrics: resolveHome follows the same rule', () => {
  const r = rig();
  r.pointAt(r.homeA);
  assert.deepEqual(metricsHome({ USERPROFILE: r.profile }), { ok: true, home: path.resolve(r.homeA) });
  assert.equal(metricsHome({ USERPROFILE: r.profile, HORDE_HOME: r.homeB }).home, path.resolve(r.homeB));
  r.point('{"v":2,"hordeHome":"x"}');
  const bad = metricsHome({ USERPROFILE: r.profile });
  assert.equal(bad.ok, false);
  assert.ok(bad.message.includes(POINTER_NAME));
  fs.unlinkSync(path.join(r.profile, POINTER_NAME));
  const none = metricsHome({ USERPROFILE: r.profile });
  assert.equal(none.ok, false);
  assert.match(none.message, /HORDE_HOME is not set/);
  r.done();
});

test('fleet-db cli: with HORDE_HOME unset the pointer decides where fleet.db is made; a bad pointer is exit 2', () => {
  const r = rig();
  r.pointAt(r.homeA);
  const env = { PATH: process.env.PATH, SystemRoot: process.env.SystemRoot, USERPROFILE: r.profile };
  const run = () => spawnSync(process.execPath, [path.join(ROOT, 'fleet-db', 'cli.mjs'), 'init'], { env, encoding: 'utf8' });
  const ok = run();
  assert.equal(ok.status, 0, ok.stderr);
  assert.ok(fs.existsSync(path.join(r.homeA, 'fleet.db')), 'made in the pointer home');
  assert.ok(!fs.existsSync(path.join(r.homeB, 'fleet.db')));
  r.point('{"v":2,"hordeHome":"x"}');
  const bad = run();
  assert.equal(bad.status, 2);
  assert.ok(bad.stderr.includes(POINTER_NAME), bad.stderr);
  r.done();
});

test('decisions-cli: the pointer decides where the list is read; a bad pointer is exit 2', () => {
  const r = rig();
  r.pointAt(r.homeA);
  openStore(dbPathFor(r.homeA)).close();
  const env = { PATH: process.env.PATH, SystemRoot: process.env.SystemRoot, USERPROFILE: r.profile };
  const run = () => spawnSync(process.execPath, [path.join(ROOT, 'fleet-db', 'decisions-cli.mjs'), 'published', '--json'], { env, encoding: 'utf8' });
  const ok = run();
  assert.equal(ok.status, 0, ok.stderr);
  r.point('nonsense');
  const bad = run();
  assert.equal(bad.status, 2);
  assert.ok(bad.stderr.includes(POINTER_NAME), bad.stderr);
  r.done();
});
