// Turning a new file to WAL under contention (fleet-db/store.mjs enterWal; T-0408). No real database: the race took about 100
// rounds of six processes to appear, so the rule is tested with a stand-in that says locked on demand.
import './own-profile.mjs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { enterWal } from '../store.mjs';

function rig(failures, message = 'database is locked') {
  let clock = 1000;
  const r = {
    calls: 0,
    pauses: 0,
    db: { exec() { r.calls++; if (r.calls <= failures) throw new Error(message); } },
    opts: { now: () => clock, pause: (ms) => { r.pauses++; clock += ms; } },
  };
  return r;
}

test('a first try that works does not wait', () => {
  const r = rig(0);
  enterWal(r.db, 5000, r.opts);
  assert.deepEqual([r.calls, r.pauses], [1, 0]);
});

test('locked is retried until it works', () => {
  const r = rig(3);
  enterWal(r.db, 5000, r.opts);
  assert.deepEqual([r.calls, r.pauses], [4, 3]);
});

test('locked for longer than the wait is thrown, not swallowed, and the wait is the one given', () => {
  const r = rig(Infinity);
  assert.throws(() => enterWal(r.db, 100, r.opts), /database is locked/);
  assert.equal(r.pauses, 4);
});

test('any other error is thrown at once', () => {
  const r = rig(Infinity, 'disk I/O error');
  assert.throws(() => enterWal(r.db, 5000, r.opts), /disk I\/O error/);
  assert.deepEqual([r.calls, r.pauses], [1, 0]);
});
