// Jobs and signals (migration 8): the one write path for the job and signal tables, and their readers.
// Design: planning/fleet-db-design.md "Jobs and signals". The overseer kept these in jobs.json and signals.jsonl; they live
// here so the overseer and the analyst detect a stall ONCE, from one place. The overseer writes only through these functions
// (via `horde job` / `horde signal`, jobs-cli.mjs); Orc N is the only owner of the schema.
//
// EVERY VERB IS IDEMPOTENT, because the caller is a loop that runs every pass and a retry after a lost answer is normal:
//   - a repeat that would change nothing changes nothing and says "kept" (exit 0);
//   - the first time of a thing stands (a job's started_at, a signal's first_at); a done job and a closed signal are
//     never rewritten by a repeat of the call that made them;
//   - a call that would CONTRADICT a settled fact (a job done again with another proof, an upsert on a done job, a signal
//     key reused for another kind) is refused in one line, never merged.
//
// A SIGNAL RAISED AGAIN is the same problem: last_at moves forward and the count grows. A signal raised with a time that is
// not after its last_at is a retry (or an older report) and changes NOTHING, so "the same key and the same -At" never counts
// twice; the price is that two truly different raises in one millisecond count once. A CLOSED signal raised with a later time
// is REOPENED (closed_at and closed_by cleared, first_at and count kept going): a problem that came back is the same problem,
// and the overseer must see it wake.
//
// WHEN A SIGNAL WAKES SOMEONE: woke_at is the time of the last ATTEMPT, written by `signal list -Open -MarkWoke` (one
// transaction: the rows it returns are the rows it marks), never by raise. A signal needs a wake while woke_at is NULL or
// older than last_at (it happened again since). Marking at list time, not after the wake, is what makes two passes unable to
// wake the same signals twice; a failed wake is retried from woke_at with the caller's own back-off (audit gap 10).
//
// TIMES are UTC milliseconds in the tables. An argument is milliseconds (13 to 15 digits) or an ISO time WITH a zone; a time
// with no zone is refused, because the same clock text means two instants either side of a DST change (the clock change of 2026-11-01).
import { refuse } from './work.mjs';
import { inWrite } from './store.mjs';

export const LIMITS = { id: 120, key: 200, owner: 64, signalOwner: 120, kind: 64, by: 64, text: 4000, fileBytes: 65536 };
// A time named on purpose may not be more than this far ahead: a signal's last_at never goes back, so one typo'd
// millisecond count would otherwise freeze the signal's last_at in the future for good.
const MAX_AHEAD_MS = 24 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

// A word: printable ASCII with no space, the shape of every key and name column.
export function wordOf(v, what, max) {
  if (typeof v !== 'string' || v.length < 1) throw refuse(what + ' is required');
  if (v.length > max) throw refuse(what + ' is ' + v.length + ' characters; the most is ' + max);
  const bad = /[^!-~]/.exec(v);
  if (bad) throw refuse(what + ' must be printable ASCII with no spaces (character ' + (bad.index + 1) + ' is not)');
  return v;
}

// A signal's owner is a person or a path as the overseer writes it ('parent e9932755', 'founder via M only', a program's
// path), so it may hold single spaces: one printable ASCII line, not padded, 1 to 120. A job's owner stays a word.
export function signalOwnerOf(v, what = 'Owner') {
  if (typeof v !== 'string' || v.length < 1) throw refuse(what + ' is required');
  if (v.length > LIMITS.signalOwner) throw refuse(what + ' is ' + v.length + ' characters; the most is ' + LIMITS.signalOwner);
  const bad = /[^ -~]/.exec(v);
  if (bad) throw refuse(what + ' must be one line of printable ASCII (character ' + (bad.index + 1) + ' is not)');
  if (v !== v.trim()) throw refuse(what + ' may not start or end with a space');
  return v;
}

// Free text: printable ASCII, with line breaks and tabs allowed (it may come from a file). The whitespace at the end is
// dropped and CRLF becomes LF, so the same words saved by two editors are the same text (a --file's byte-order mark never
// gets here: the decoder in jobs-cli.mjs drops it).
export function textOf(v, what, max = LIMITS.text) {
  if (typeof v !== 'string') throw refuse(what + ' is required');
  const t = v.replace(/\r\n?/g, '\n').replace(/\s+$/, '');
  if (t.length < 1) throw refuse(what + ' is empty');
  if (t.length > max) throw refuse(what + ' is ' + t.length + ' characters; the most is ' + max);
  const bad = /[^\x20-\x7E\n\t]/.exec(t);
  if (bad) throw refuse(what + ' must be ASCII (character ' + (bad.index + 1) + ' is U+' + t.charCodeAt(bad.index).toString(16).toUpperCase().padStart(4, '0') + '); write it in plain ASCII');
  return t;
}

// A time argument -> UTC ms. now is the clock; ahead = true applies the future limit.
export function whenOf(v, what, { now, ahead = false } = {}) {
  let ms;
  if (typeof v === 'number') {
    if (!Number.isSafeInteger(v) || v < 1e12 || v >= 1e15) throw refuse(what + ' must be UTC milliseconds (13 digits) or an ISO time with a zone');
    ms = v;
  } else if (typeof v === 'string' && /^\d+$/.test(v)) {
    if (!/^\d{13,15}$/.test(v)) throw refuse(what + ' must be UTC milliseconds (13 digits) or an ISO time with a zone like 2026-11-06T09:00:00Z');
    ms = Number(v);
  } else if (typeof v === 'string') {
    const t = v.trim();
    const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|[+-]\d{2}:?\d{2})$/.exec(t);
    if (!m) {
      if (/^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?$/.test(t)) throw refuse(what + ' has no time zone, so it is a local time that means two instants at a clock change; add Z or an offset like -05:00, or give UTC milliseconds');
      throw refuse(what + ' must be UTC milliseconds or an ISO time with a zone like 2026-11-06T09:00:00Z');
    }
    const [y, mo, d, h, mi, s] = [m[1], m[2], m[3], m[4], m[5], m[6]].map(Number);
    let off = 0;
    if (m[8] !== 'Z') {
      const digits = m[8].replace(':', '');
      const oh = Number(digits.slice(1, 3));
      const om = Number(digits.slice(3, 5));
      if (oh > 23 || om > 59) throw refuse(what + ' has an offset that is not a real one');
      off = (m[8][0] === '-' ? -1 : 1) * (oh * 60 + om) * 60000;
    }
    const utc = Date.UTC(y, mo - 1, d, h, mi, s);
    const back = new Date(utc);
    // Date.UTC rolls 02-31 into March; a time that does not read back the same was not a real one.
    if (back.getUTCFullYear() !== y || back.getUTCMonth() !== mo - 1 || back.getUTCDate() !== d || h > 23 || mi > 59 || s > 59) throw refuse(what + ' is not a real time');
    ms = utc - off + (m[7] ? Number((m[7] + '000').slice(0, 3)) : 0);
  } else throw refuse(what + ' must be UTC milliseconds or an ISO time with a zone');
  if (ms < 1e12) throw refuse(what + ' is before 2001, which is not a time this fleet has');
  if (ahead && ms > now + MAX_AHEAD_MS) throw refuse(what + ' is more than a day in the future');
  return ms;
}

const iso = (ms) => (ms === null || ms === undefined ? null : new Date(ms).toISOString());
const given = (v) => v !== undefined && v !== null;

function sessionOf(v) {
  const s = typeof v === 'string' ? v.toLowerCase() : '';
  if (!UUID.test(s)) throw refuse('Session must be a session uuid');
  return s;
}

// --- jobs ----------------------------------------------------------------------------------------------------------

// Create a job, or change owner, job text, session, due and waiting_on on an OPEN one. started_at is never moved. A field left out is
// left as it is (a job's due time is not cleared by omitting it); waiting_on is cleared by notWaiting, and naming both is refused. Returns { action: 'created' | 'kept' | 'updated', changed }.
export function upsertJob(db, req, { now = Date.now } = {}) {
  const id = wordOf(req.id, 'Id', LIMITS.id);
  const owner = wordOf(req.owner, 'Owner', LIMITS.owner);
  const by = wordOf(req.by, 'By', LIMITS.by);
  const job = textOf(req.job, 'Job');
  const session = given(req.session) ? sessionOf(req.session) : null;
  const clock = now();
  const started = given(req.started) ? whenOf(req.started, 'Started', { now: clock }) : clock;
  const due = given(req.due) ? whenOf(req.due, 'Due', { now: clock }) : null;
  const notWaiting = req.notWaiting === true;
  if (notWaiting && given(req.waitingOn)) throw refuse('WaitingOn and NotWaiting contradict each other; give one');
  const waiting = given(req.waitingOn) ? textOf(req.waitingOn, 'WaitingOn') : null;
  return inWrite(db, () => {
    const row = db.prepare('SELECT owner, session_id, job, started_at, due_at, done_at, waiting_on FROM job WHERE id = ?').get(id);
    if (!row) {
      db.prepare('INSERT INTO job (id, owner, session_id, job, started_at, due_at, waiting_on, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
        .run(id, owner, session, job, started, due, waiting, by);
      return { action: 'created', changed: [] };
    }
    if (row.done_at !== null) throw refuse('job ' + id + ' is done; a new piece of work takes a new id');
    const changed = [];
    if (owner !== row.owner) changed.push('owner');
    if (job !== row.job) changed.push('job');
    if (session !== null && session !== row.session_id) changed.push('session');
    if (due !== null && due !== row.due_at) changed.push('due');
    const newWaiting = notWaiting ? null : (waiting ?? row.waiting_on);
    if (newWaiting !== row.waiting_on) changed.push('waiting_on');
    if (changed.length === 0) return { action: 'kept', changed };
    db.prepare('UPDATE job SET owner = ?, job = ?, session_id = ?, due_at = ?, waiting_on = ? WHERE id = ?')
      .run(owner, job, session ?? row.session_id, due ?? row.due_at, newWaiting, id);
    return { action: 'updated', changed };
  });
}

// Close a job with its proof. A repeat with the same proof keeps the first time; another proof is refused (done is final).
// An end time named on purpose that is before the start is refused; a clock that stepped back is lifted to the start.
// done_by is stored with the first close; a repeat with the same proof and another By stays 'kept' and keeps the first one.
// Returns { action: 'done' | 'kept', doneAt }.
export function doneJob(db, req, { now = Date.now } = {}) {
  const id = wordOf(req.id, 'Id', LIMITS.id);
  const by = wordOf(req.by, 'By', LIMITS.by);
  const proof = textOf(req.proof, 'Proof');
  const clock = now();
  const explicit = given(req.at);
  const at = explicit ? whenOf(req.at, 'At', { now: clock, ahead: true }) : clock;
  return inWrite(db, () => {
    const row = db.prepare('SELECT started_at, done_at, done_proof FROM job WHERE id = ?').get(id);
    if (!row) throw refuse('no job is called ' + id);
    if (row.done_at !== null) {
      if (row.done_proof === proof) return { action: 'kept', doneAt: row.done_at };
      throw refuse('job ' + id + ' is already done with another proof; a done job is final');
    }
    if (explicit && at < row.started_at) throw refuse('At is before the job started');
    const doneAt = Math.max(at, row.started_at);
    db.prepare('UPDATE job SET done_at = ?, done_proof = ?, done_by = ? WHERE id = ?').run(doneAt, proof, by, id);
    return { action: 'done', doneAt };
  });
}

// The jobs, open ones first (soonest due first, no due time last), then done ones newest first. overdue = open with a due
// time before now (it implies open). notWaiting keeps the jobs with no waiting_on, open or not (what the overseer's idle rule reads).
export function listJobs(db, { open = false, owner = null, overdue = false, notWaiting = false } = {}, { now = Date.now } = {}) {
  if (owner !== null) wordOf(owner, 'Owner', LIMITS.owner);
  const clock = now();
  return db.prepare(`SELECT id, owner, session_id, job, started_at, due_at, done_at, done_proof, done_by, waiting_on, created_by FROM job
    WHERE (?1 = 0 OR done_at IS NULL) AND (?2 IS NULL OR owner = ?2) AND (?3 = 0 OR (done_at IS NULL AND due_at IS NOT NULL AND due_at < ?4)) AND (?5 = 0 OR waiting_on IS NULL)
    ORDER BY (done_at IS NOT NULL), CASE WHEN done_at IS NULL THEN COALESCE(due_at, 9007199254740991) ELSE -done_at END, started_at, id`)
    .all(open ? 1 : 0, owner, overdue ? 1 : 0, clock, notWaiting ? 1 : 0).map((r) => ({
      ...r, started: iso(r.started_at), due: iso(r.due_at), done: iso(r.done_at),
      state: r.done_at === null ? 'open' : 'done', overdue: r.done_at === null && r.due_at !== null && r.due_at < clock,
    }));
}

// --- signals -------------------------------------------------------------------------------------------------------

// Raise a signal. urgent and quiet are set by every EFFECTIVE raise to what it was given (absent = 0); a raise that changes
// nothing leaves them alone. A CLOSED signal is reopened by any raise, even one with a time that is not after last_at (last_at
// then stays where it is): the problem is back, whatever the report's clock says. Every reopen clears both wake times.
// Returns { action: 'raised' | 'updated' | 'reopened' | 'kept', count }.
export function raiseSignal(db, req, { now = Date.now } = {}) {
  const key = wordOf(req.key, 'Key', LIMITS.key);
  const kind = wordOf(req.kind, 'Kind', LIMITS.kind);
  const owner = given(req.owner) ? signalOwnerOf(req.owner) : null;
  const text = textOf(req.text, 'Text');
  const urgent = req.urgent === true ? 1 : 0;
  const quiet = req.quiet === true ? 1 : 0;
  const clock = now();
  const at = given(req.at) ? whenOf(req.at, 'At', { now: clock, ahead: true }) : clock;
  return inWrite(db, () => {
    const row = db.prepare('SELECT kind, owner, last_at, count, closed_at FROM signal WHERE key = ?').get(key);
    if (!row) {
      db.prepare('INSERT INTO signal (key, kind, owner, text, first_at, last_at, count, urgent, quiet) VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)').run(key, kind, owner, text, at, at, urgent, quiet);
      return { action: 'raised', count: 1 };
    }
    if (row.kind !== kind) throw refuse('signal ' + key + ' is of kind ' + row.kind + ', not ' + kind + '; a key is one kind of problem');
    if (row.closed_at !== null) {
      db.prepare('UPDATE signal SET last_at = ?, count = count + 1, text = ?, owner = ?, urgent = ?, quiet = ?, woke_at = NULL, woke_ok_at = NULL, closed_at = NULL, closed_by = NULL WHERE key = ?')
        .run(Math.max(at, row.last_at), text, owner ?? row.owner, urgent, quiet, key);
      return { action: 'reopened', count: row.count + 1 };
    }
    // Not after the last time: a retry of a raise already counted (or an older report). Nothing changes.
    if (at <= row.last_at) return { action: 'kept', count: row.count };
    db.prepare('UPDATE signal SET last_at = ?, count = count + 1, text = ?, owner = ?, urgent = ?, quiet = ? WHERE key = ?')
      .run(at, text, owner ?? row.owner, urgent, quiet, key);
    return { action: 'updated', count: row.count + 1 };
  });
}

// Record that a wake WORKED (the overseer confirmed someone was reached): woke_ok_at, never moved back. A repeat at the same
// -At is kept (a retry); with no -At the time is now, so a later call records a later confirmation. An unknown key is refused.
// Until this is called a wake that was only attempted (signal list -MarkWoke) is still unwoken.
export function wokeSignal(db, req, { now = Date.now } = {}) {
  const key = wordOf(req.key, 'Key', LIMITS.key);
  const clock = now();
  const at = given(req.at) ? whenOf(req.at, 'At', { now: clock, ahead: true }) : clock;
  return inWrite(db, () => {
    const row = db.prepare('SELECT woke_ok_at FROM signal WHERE key = ?').get(key);
    if (!row) throw refuse('no signal is called ' + key);
    if (row.woke_ok_at !== null && at <= row.woke_ok_at) return { action: 'kept' };
    db.prepare('UPDATE signal SET woke_ok_at = ? WHERE key = ?').run(at, key);
    return { action: 'woke' };
  });
}

// Close a signal. Closing a closed one keeps the first close. An unknown key is refused. closed_at is never before last_at.
export function closeSignal(db, req, { now = Date.now } = {}) {
  const key = wordOf(req.key, 'Key', LIMITS.key);
  const by = wordOf(req.by, 'By', LIMITS.by);
  const clock = now();
  return inWrite(db, () => {
    const row = db.prepare('SELECT last_at, closed_at FROM signal WHERE key = ?').get(key);
    if (!row) throw refuse('no signal is called ' + key);
    if (row.closed_at !== null) return { action: 'kept' };
    db.prepare('UPDATE signal SET closed_at = ?, closed_by = ? WHERE key = ?').run(Math.max(clock, row.last_at), by, key);
    return { action: 'closed' };
  });
}

// The signals, newest first. unwoken = open, not quiet, and no CONFIRMED wake since it last happened (woke_ok_at NULL or older
// than last_at): a wake that was attempted and failed stays unwoken and is retried. markWoke implies unwoken: it records the
// attempt (woke_at = at, default now) on exactly the rows that need a wake, in the same transaction, and returns them as
// marked; it needs open, because a closed signal has nothing to wake.
export function listSignals(db, { open = false, owner = null, unwoken = false, markWoke = false, at = null } = {}, { now = Date.now } = {}) {
  if (owner !== null) signalOwnerOf(owner);
  if (markWoke && !open) throw refuse('MarkWoke needs Open: only an open signal is woken for');
  if (at !== null && !markWoke) throw refuse('At on signal list is the time MarkWoke records; it needs MarkWoke');
  const clock = now();
  const wokeAt = markWoke ? (at === null ? clock : whenOf(at, 'At', { now: clock, ahead: true })) : null;
  const need = unwoken || markWoke;
  const select = () => db.prepare(`SELECT key, kind, owner, text, first_at, last_at, count, woke_at, woke_ok_at, urgent, quiet, closed_at, closed_by FROM signal
    WHERE (?1 = 0 OR closed_at IS NULL) AND (?2 IS NULL OR owner = ?2) AND (?3 = 0 OR (closed_at IS NULL AND quiet = 0 AND (woke_ok_at IS NULL OR woke_ok_at < last_at)))
    ORDER BY last_at DESC, key`).all(open ? 1 : 0, owner, need ? 1 : 0).map((r) => ({ ...r }));
  const rows = markWoke
    ? inWrite(db, () => {
      const got = select();
      const mark = db.prepare('UPDATE signal SET woke_at = ? WHERE key = ?');
      for (const r of got) { mark.run(wokeAt, r.key); r.woke_at = wokeAt; }
      return got;
    })
    : select();
  return rows.map((r) => ({ ...r, first: iso(r.first_at), last: iso(r.last_at), woke: iso(r.woke_at), woke_ok: iso(r.woke_ok_at), closed: iso(r.closed_at), state: r.closed_at === null ? 'open' : 'closed' }));
}

// Delete the CLOSED signals closed more than days days ago. An open signal is never touched. days is required (1 or more):
// a prune that defaults is a prune that surprises (audit gap 11). Returns { pruned }.
export function pruneSignals(db, req, { now = Date.now } = {}) {
  const d = req.days;
  if (d === undefined || d === null || !/^\d{1,5}$/.test(String(d)) || Number(d) < 1) throw refuse('Days is required and must be a whole number of 1 or more (at most 99999)');
  const cutoff = now() - Number(d) * DAY_MS;
  return inWrite(db, () => ({ pruned: db.prepare('DELETE FROM signal WHERE closed_at IS NOT NULL AND closed_at < ?').run(cutoff).changes }));
}
