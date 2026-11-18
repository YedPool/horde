// The sessions step of `horde db sync` (T-0409, piece 2 of T-0299): keeps session, pane and session_pane current from
// a SNAPSHOT that the port side produced (fleet/SessionSnapshot.ps1), and writes what the overseer and the analyst read
// instead of each judging every transcript on its own (migration 7 in schema.mjs; design: planning/fleet-db-design.md,
// "Keeping the file-fed tables current").
//
// THIS FILE KNOWS NO PORT BY NAME. The snapshot is plain JSON (SNAPSHOT_SHAPE below): the registry records of the
// sessions, the live panes of each terminal instance, and the processes that are running a session. Which terminal,
// which harness and which registry made it is the producer's business (CONTRIBUTING 14).
//
// WHAT ONE TICK WRITES, in ONE short transaction (the transcripts are read BEFORE it opens, so the write lock is never
// held across disk reads):
//   session        every record of the snapshot, by the importer's own rule (import.mjs importSessionRecords: reuse, not a
//                  copy), then only the columns that CHANGED (migration 7), and state_checked_at for every judged id
//   pane           one open row per live pane of a terminal instance that could be listed; a pane gone from its list closes
//   session_pane   a session moving panes CLOSES its old row and opens a new one (history, not an overwrite)
// A SECOND TICK WITH NOTHING NEW WRITES NOTHING BUT state_checked_at.
//
// LIVENESS, AND WHAT IT IS NOT. The registry is NOT a liveness source: about 115 of 155 records are never retired, and one
// stale record claimed a live pane. Two records can claim one pane; the owner is the one with the newest lastSeen (the
// record's own field, written by the hook - never a file's modified time; judgeLiveness says why not the process). A session with
// no live pane and no running process is 'dead' (retired_at is NOT touched: that stays someone else's). THE RULE IS
// ASYMMETRIC ON PURPOSE: a terminal that could not be listed, or a process list that could not be read, makes the session
// UNKNOWN - its state and state_checked_at are left alone, so a reader sees an old stamp rather than a false death.
//
// ACTIVITY comes from the transcript, by a STORED BYTE OFFSET (session.transcript_offset), so a 195 MB transcript is read
// once and then only its new bytes:
//   - only whole lines (a half-written line is read next tick); a file SMALLER than the offset was replaced, so it is read
//     again from 0; a first read takes at most the last FIRST_READ_BYTES, starting after the first newline;
//   - at most SESSION_READ_BYTES per session and STEP_READ_BYTES per tick, so catching up takes several ticks, never the
//     time limit; a session whose offset is already at the file's end costs one stat (a dead session is never read twice);
//   - the rules are the overseer's, ported from its transcript_state() and test cases (each rule has its test):
//       only timestamped user and assistant records and system records of subtype turn_duration or stop_hook_summary count;
//       isMeta and isCompactSummary records are skipped (an unanswered compaction summary looked like a turn open for 4 days);
//       a local slash command is not a prompt; an interrupt marker closes the turn;
//       an assistant record with stop_reason end_turn closes the turn, so does a text-only record with none (a subagent's
//       final answer); any other keeps it open; a turn whose last tool call is ExitPlanMode or AskUserQuestion waits for
//       a person;
//       THE TIMES ARE THE RECORDS' OWN, never the file's modified time (an mtime touch on an idle Warg fooled an audit).
//   - SUBAGENTS: a session inside a long foreground Agent call looks stalled while its subagent works, so while a session
//     is mid-turn the newest activity of its subagents is folded into last_activity_at. CHOICE: a bounded tail read
//     (SUBAGENT_TAIL_BYTES) of the SUBAGENT_FILES most recently modified files of <transcript>/subagents, not a stored
//     offset per file - there is no column per subagent, the folder is usually absent or old, and the work is bounded.
//     The file's mtime only PICKS which files to look at; the time that is folded in is still a record's.
//
// KNOWN GAP, ON PURPOSE: a tool permission prompt waiting for a person is invisible in the transcript. It reads as in_turn
// with no activity, exactly like a stall. This step does NOT read pane text. Readers must know: a long in_turn with no
// activity may be a permission prompt, not a stall. STALLS ARE NOT JUDGED HERE: no thresholds; readers compare
// last_activity_at with their own clock. 'waiting-job' is reserved for piece 3 and is never set here.
import fs from 'node:fs';
import path from 'node:path';
import { inWrite } from './store.mjs';
import { importSessionRecords, parseTime } from './import.mjs';
import { newId } from './write.mjs';

export const SNAPSHOT_VERSION = 1;
export const SESSION_STATES = ['live', 'idle', 'waiting-person', 'dead'];
export const FIRST_READ_BYTES = 2 * 1024 * 1024;
export const SESSION_READ_BYTES = 8 * 1024 * 1024;
export const STEP_READ_BYTES = 64 * 1024 * 1024;
export const SUBAGENT_TAIL_BYTES = 256 * 1024;
export const SUBAGENT_FILES = 3;
export const SUBAGENT_MAX_AGE_MS = 24 * 60 * 60 * 1000;
// The tools whose call ends a turn on a person, not on the model (case 88beff2f 11-02: a plan waiting for approval).
export const PERSON_TOOLS = ['ExitPlanMode', 'AskUserQuestion'];
const TURN_END_SUBTYPES = ['turn_duration', 'stop_hook_summary'];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const INSTANCE = /^[A-Za-z0-9._-]{1,120}$/;
const PANE_NO = /^[0-9]{1,9}$/;
const CHUNK = 400;

// ---------------------------------------------------------------------------------------------------------
// The snapshot

// SNAPSHOT_SHAPE, as the producer writes it (fleet/SessionSnapshot.ps1):
//   { v: 1, at: <ms>,
//     registry:  { complete: bool, reason: text, sessions: [ { id, rec } ] }       rec is the record as the registry holds it
//     panes:     { state: 'known' | 'unknown', reason, sockets: [ { instance, state: 'listed' | 'closed' | 'unknown', panes: [n], reason } ] }
//     processes: { state: 'known' | 'unknown', reason, running: [ { sessionId, pid } ] } }
// 'closed' means the terminal instance is not running at all (its panes are gone); 'unknown' means it runs but could not be
// listed. A list that is 'known' and does not name an instance says that instance is closed.
const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

export function parseSnapshot(raw) {
  const bad = (why) => { throw new Error('the session snapshot is not usable: ' + why); };
  if (!isObject(raw) || raw.v !== SNAPSHOT_VERSION) bad('it is not version ' + SNAPSHOT_VERSION);
  if (!Number.isSafeInteger(raw.at) || raw.at < 0) bad('at is not a time in ms');
  const reg = raw.registry;
  if (!isObject(reg) || typeof reg.complete !== 'boolean' || !Array.isArray(reg.sessions)) bad('registry is not { complete, sessions }');
  const sessions = [];
  for (const s of reg.sessions) {
    if (!isObject(s) || typeof s.id !== 'string' || !isObject(s.rec)) bad('a registry entry is not { id, rec }');
    sessions.push({ id: s.id.toLowerCase(), rec: s.rec });
  }
  const pn = raw.panes;
  if (!isObject(pn) || !['known', 'unknown'].includes(pn.state) || !Array.isArray(pn.sockets)) bad('panes is not { state, sockets }');
  const sockets = new Map();
  for (const k of pn.sockets) {
    if (!isObject(k) || typeof k.instance !== 'string' || !INSTANCE.test(k.instance) || !['listed', 'closed', 'unknown'].includes(k.state)) bad('a terminal instance is not { instance, state }');
    const nos = Array.isArray(k.panes) ? k.panes : [];
    if (!nos.every((n) => Number.isSafeInteger(n) && n >= 0)) bad('instance ' + k.instance + ' lists a pane that is not a number');
    sockets.set(k.instance, { state: k.state, panes: new Set(nos) });
  }
  const pr = raw.processes;
  if (!isObject(pr) || !['known', 'unknown'].includes(pr.state) || !Array.isArray(pr.running)) bad('processes is not { state, running }');
  const running = new Set();
  for (const p of pr.running) {
    if (!isObject(p) || typeof p.sessionId !== 'string') bad('a running process is not { sessionId, pid }');
    running.add(p.sessionId.toLowerCase());
  }
  return {
    at: raw.at,
    registry: { complete: reg.complete, sessions },
    panes: { known: pn.state === 'known', sockets },
    processes: { known: pr.state === 'known', running },
  };
}

// ---------------------------------------------------------------------------------------------------------
// Which pane a session owns, and whether it is alive

// The pane a record claims, as { instance, no } or null. A retired record claims nothing.
export function claimOf(rec) {
  if (rec.retired === true) return null;
  const inst = typeof rec.instance === 'string' ? rec.instance : null;
  const no = rec.pane === undefined || rec.pane === null ? null : String(rec.pane);
  if (inst === null || !INSTANCE.test(inst) || no === null || !PANE_NO.test(no)) return null;
  return { instance: inst, no: Number(no) };
}

// The state of one terminal instance for a pane claim: 'listed' (its panes are known), 'closed' (not running, so none of
// its panes is live), or 'unknown'. An instance a KNOWN list does not name is closed: a terminal that runs has a socket.
function instanceState(snap, instance) {
  if (!snap.panes.known) return 'unknown';
  const k = snap.panes.sockets.get(instance);
  return k === undefined ? 'closed' : k.state;
}

// entries: [{ id, rec }] -> { verdicts: Map id -> 'alive' | 'dead' | 'unknown', owners: Map 'instance\0no' -> id }.
// THE OWNER of a pane: the record claiming it with the newest lastSeen (the record's own field), ties by id so the answer never
// flips. The process list does NOT pick the owner: after a /clear the new id runs inside a process whose control file still
// names the old id, so letting the running id win took the pane from the healthy new session and called it dead. A running
// process only ever proves its own record alive, so that old id reads alive too: the wrong answer this rule accepts, because a
// false death raises an alarm on a healthy session and a false life only shows an old, quiet row.
export function judgeLiveness(entries, snap) {
  const claims = new Map();
  const lastSeen = new Map();
  for (const e of entries) {
    lastSeen.set(e.id, parseTime(e.rec.lastSeen) ?? parseTime(e.rec.firstSeen) ?? 0);
    const c = claimOf(e.rec);
    if (c === null) continue;
    const key = c.instance + '\0' + c.no;
    if (!claims.has(key)) claims.set(key, []);
    claims.get(key).push(e.id);
  }
  const owners = new Map();
  for (const [key, ids] of claims) {
    const pool = [...ids].sort((a, b) => (lastSeen.get(b) - lastSeen.get(a)) || (a < b ? -1 : 1));
    owners.set(key, pool[0]);
  }
  const verdicts = new Map();
  for (const e of entries) {
    const c = claimOf(e.rec);
    let pane = 'none';
    if (c !== null) {
      const st = instanceState(snap, c.instance);
      if (st === 'unknown') pane = 'unknown';
      else if (st === 'listed' && snap.panes.sockets.get(c.instance).panes.has(c.no) && owners.get(c.instance + '\0' + c.no) === e.id) pane = 'live';
      else pane = 'gone';
    }
    const proc = snap.processes.known ? (snap.processes.running.has(e.id) ? 'alive' : 'none') : 'unknown';
    let v = 'unknown';
    if (pane === 'live' || proc === 'alive') v = 'alive';
    else if ((pane === 'gone' || pane === 'none') && proc === 'none') v = 'dead';
    verdicts.set(e.id, v);
  }
  return { verdicts, owners };
}

// ---------------------------------------------------------------------------------------------------------
// The transcript

export const emptyActivity = () => ({ lastActivityAt: null, lastAssistantAt: null, inTurn: null, waitsPerson: false });

// The record the harness writes when a person interrupts a turn ('[Request interrupted by user...]'), in both shapes.
function isInterrupt(content) {
  const parts = typeof content === 'string' ? [content]
    : (Array.isArray(content) ? content.filter((c) => isObject(c) && c.type === 'text').map((c) => c.text) : []);
  return parts.some((p) => typeof p === 'string' && p.trimStart().startsWith('[Request interrupted by user'));
}

// Folds the whole lines of `text` into `act` (a copy is returned). Records are in time order, so the state after the last
// relevant record is the state of the session.
export function applyRecords(text, act) {
  const out = { ...act };
  for (const line of text.split('\n')) {
    if (line === '' || line === '\r') continue;
    let r;
    try { r = JSON.parse(line); } catch { continue; }
    if (!isObject(r) || typeof r.timestamp !== 'string') continue;
    const t = Date.parse(r.timestamp);
    if (!Number.isFinite(t) || t < 0) continue;
    if (r.isMeta || r.isCompactSummary) continue;
    const msg = isObject(r.message) ? r.message : {};
    const content = msg.content;
    if (r.type === 'user' && typeof content === 'string' && /^\s*(<command-name>|<local-command-)/.test(content)) continue;
    if (r.type === 'assistant') {
      out.lastActivityAt = Math.max(out.lastActivityAt ?? 0, t);
      out.lastAssistantAt = Math.max(out.lastAssistantAt ?? 0, t);
      const tools = Array.isArray(content) ? content.filter((c) => isObject(c) && c.type === 'tool_use').map((c) => c.name) : [];
      const stop = msg.stop_reason ?? null;
      // A text-only record with no stop_reason is a finished answer when nothing follows it (a subagent's last words
      // looked stalled for 51 min); mid-stream text is followed within seconds.
      out.inTurn = stop !== 'end_turn' && !(stop === null && tools.length === 0);
      out.waitsPerson = out.inTurn && tools.some((n) => PERSON_TOOLS.includes(n));
    } else if (r.type === 'user') {
      out.lastActivityAt = Math.max(out.lastActivityAt ?? 0, t);
      out.inTurn = !isInterrupt(content);
      out.waitsPerson = false;
    } else if (r.type === 'system' && TURN_END_SUBTYPES.includes(r.subtype)) {
      out.lastActivityAt = Math.max(out.lastActivityAt ?? 0, t);
      out.inTurn = false;
      out.waitsPerson = false;
    }
  }
  return out;
}

// One read of one transcript from its stored offset. `prior` is { offset: bytes | null, act }, `cap` the most bytes this
// call may read (`lineMax`: the longest line it will wait for). Returns { act, offset, bytes, status }; status: 'unchanged' (nothing new), 'read', 'replaced' (the file was
// shorter than the offset, so it was read again from 0), 'missing' (no such file) or 'error'. THE OFFSET ONLY EVER MOVES TO
// JUST AFTER A NEWLINE.
export function readTranscript(file, prior, cap, lineMax = SESSION_READ_BYTES) {
  let fd;
  try { fd = fs.openSync(file, 'r'); } catch (e) { return { act: prior.act, offset: prior.offset, bytes: 0, status: e.code === 'ENOENT' ? 'missing' : 'error' }; }
  try {
    const size = fs.fstatSync(fd).size;
    let offset = prior.offset;
    let act = prior.act;
    let status = 'read';
    if (offset !== null && size < offset) { offset = 0; act = emptyActivity(); status = 'replaced'; }
    if (offset !== null && size === offset) return { act, offset, bytes: 0, status: 'unchanged' };
    const first = offset === null;
    if (first) act = emptyActivity();
    const start = first ? Math.max(0, size - FIRST_READ_BYTES) : offset;
    const want = Math.min(size - start, cap);
    if (want <= 0) return { act, offset: prior.offset, bytes: 0, status: 'unchanged' };
    const buf = Buffer.alloc(want);
    const n = fs.readSync(fd, buf, 0, want, start);
    const got = buf.subarray(0, n);
    // A first read that started inside the file begins in the middle of a line: after its first newline.
    let base = 0;
    if (first && start > 0) {
      const nl = got.indexOf(10);
      base = nl < 0 ? n : nl + 1;
    }
    const last = got.lastIndexOf(10);
    if (last < base) {
      // No whole line yet. A half-written line waits for the next tick; a line longer than the largest read can never
      // fit, so it is stepped over rather than waited for forever.
      if (n >= lineMax) return { act, offset: start + n, bytes: n, status };
      return { act, offset: first ? start + base : offset, bytes: n, status };
    }
    act = applyRecords(got.subarray(base, last + 1).toString('utf8'), act);
    return { act, offset: start + last + 1, bytes: n, status };
  } catch {
    return { act: prior.act, offset: prior.offset, bytes: 0, status: 'error' };
  } finally {
    fs.closeSync(fd);
  }
}

// The newest record time among the most recently written files of <transcript>/subagents, or null. Each file is read from
// its tail only. A file not written since `sinceMs` cannot hold a record after it, and one older than a day is a finished
// agent, so neither is read.
export function subagentActivity(transcriptPath, sinceMs, nowMs) {
  const dir = transcriptPath.replace(/\.jsonl$/i, '') + path.sep + 'subagents';
  let names;
  try { names = fs.readdirSync(dir); } catch { return null; }
  const files = [];
  for (const n of names) {
    if (!/\.jsonl$/i.test(n)) continue;
    try {
      const st = fs.statSync(path.join(dir, n));
      if (st.mtimeMs >= sinceMs && nowMs - st.mtimeMs <= SUBAGENT_MAX_AGE_MS) files.push({ file: path.join(dir, n), mtime: st.mtimeMs, size: st.size });
    } catch { /* gone between listing and stat */ }
  }
  files.sort((a, b) => b.mtime - a.mtime);
  let newest = null;
  for (const f of files.slice(0, SUBAGENT_FILES)) {
    const r = readTail(f.file, f.size);
    const a = applyRecords(r, emptyActivity()).lastActivityAt;
    if (a !== null && (newest === null || a > newest)) newest = a;
  }
  return newest;
}

function readTail(file, size) {
  let fd;
  try { fd = fs.openSync(file, 'r'); } catch { return ''; }
  try {
    const start = Math.max(0, size - SUBAGENT_TAIL_BYTES);
    const buf = Buffer.alloc(size - start);
    const n = fs.readSync(fd, buf, 0, buf.length, start);
    let got = buf.subarray(0, n);
    if (start > 0) { const nl = got.indexOf(10); got = nl < 0 ? Buffer.alloc(0) : got.subarray(nl + 1); }
    const last = got.lastIndexOf(10);
    return last < 0 ? '' : got.subarray(0, last + 1).toString('utf8');
  } catch { return ''; } finally { fs.closeSync(fd); }
}

// The state a judged session is in. 'waiting-job' is piece 3's and is not set here.
export function stateOf(verdict, act) {
  if (verdict === 'dead') return 'dead';
  if (act.waitsPerson) return 'waiting-person';
  return act.inTurn ? 'live' : 'idle';
}

// ---------------------------------------------------------------------------------------------------------
// One tick

const flagOf = (v) => (v === null ? null : (v ? 1 : 0));

// Runs the step against an open, migrated database. `raw` is the parsed snapshot JSON. Returns a summary:
//   { sessions, added, counts: { live, idle, 'waiting-person', dead, unknown }, changed, paneOpened, paneClosed, moved, bytes, deferred }
export function runSessionsStep(db, raw, { now = Date.now(), stepBytes = STEP_READ_BYTES, sessionBytes = SESSION_READ_BYTES } = {}) {
  const snap = parseSnapshot(raw);
  const entries = snap.registry.sessions;
  const byId = new Map();
  for (const e of entries) if (!byId.has(e.id)) byId.set(e.id, e);
  const uniq = [...byId.values()];
  const { verdicts, owners } = judgeLiveness(uniq, snap);

  // The stored values, read before the transaction opens; this step is the only writer of these columns.
  const stored = new Map();
  for (const r of db.prepare('SELECT id, transcript_offset, last_activity_at, last_assistant_at, in_turn, waits_person, state FROM session').all()) stored.set(r.id, r);

  // READ ORDER: sessions that are alive first, then the freshest, so a small budget goes where it matters.
  const order = [...uniq].sort((a, b) => {
    const va = verdicts.get(a.id) === 'dead' ? 1 : 0;
    const vb = verdicts.get(b.id) === 'dead' ? 1 : 0;
    return (va - vb) || ((parseTime(b.rec.lastSeen) ?? 0) - (parseTime(a.rec.lastSeen) ?? 0)) || (a.id < b.id ? -1 : 1);
  });
  let budget = stepBytes;
  let bytes = 0;
  let deferred = 0;
  const next = new Map();
  for (const e of order) {
    const old = stored.get(e.id);
    const prior = {
      offset: old && old.transcript_offset !== null ? old.transcript_offset : null,
      act: old ? { lastActivityAt: old.last_activity_at, lastAssistantAt: old.last_assistant_at, inTurn: old.in_turn === null ? null : old.in_turn === 1, waitsPerson: old.waits_person === 1 } : emptyActivity(),
    };
    const tp = typeof e.rec.transcriptPath === 'string' && path.isAbsolute(e.rec.transcriptPath) && /\.jsonl$/i.test(e.rec.transcriptPath) ? e.rec.transcriptPath : null;
    let res = { act: prior.act, offset: prior.offset };
    if (tp !== null) {
      if (budget <= 0) { deferred++; } else {
        res = readTranscript(tp, prior, Math.min(sessionBytes, budget), sessionBytes);
        budget -= res.bytes;
        bytes += res.bytes;
      }
      // A session in a long foreground subagent call: its subagents' activity is the parent's.
      if (res.act.inTurn === true && verdicts.get(e.id) !== 'dead') {
        const sub = subagentActivity(tp, res.act.lastActivityAt ?? 0, now);
        if (sub !== null && sub > (res.act.lastActivityAt ?? 0)) res = { ...res, act: { ...res.act, lastActivityAt: sub } };
      }
    }
    next.set(e.id, res);
  }

  const counts = { live: 0, idle: 0, 'waiting-person': 0, dead: 0, unknown: 0 };
  const out = { sessions: uniq.length, added: 0, counts, changed: 0, paneOpened: 0, paneClosed: 0, moved: 0, bytes, deferred };
  inWrite(db, () => {
    const { nodeId, report } = importSessionRecords(db, uniq.map((e) => ({ file: e.id + '.json', rec: e.rec })));
    out.added = report.tables.session.added;
    const have = new Set(db.prepare('SELECT id FROM session').all().map((r) => r.id));

    // ---- state and activity: a row is written only when something in it changed
    const upd = db.prepare('UPDATE session SET last_activity_at = ?, last_assistant_at = ?, in_turn = ?, waits_person = ?, state = ?, transcript_offset = ? WHERE id = ?');
    // The importer does not refresh last_seen, so it would freeze at the first tick. It does carry a retirement and move the
    // seat to the freshest session on every tick (T-0410); this last_seen is what it compares a holder the registry left out by.
    const seenUpd = db.prepare('UPDATE session SET last_seen = ? WHERE id = ? AND last_seen < ?');
    const checked = [];
    for (const e of uniq) {
      if (!have.has(e.id)) continue;
      const seen = parseTime(e.rec.lastSeen);
      if (seen !== null) seenUpd.run(seen, e.id, seen);
      const res = next.get(e.id);
      const v = verdicts.get(e.id);
      const old = stored.get(e.id) ?? null;
      let state = old ? old.state : null;
      // Alive with no record read yet (a new transcript, or a first read put off by the budget) says nothing of its turn: not idle.
      if (v === 'unknown' || (v === 'alive' && res.act.inTurn === null)) counts.unknown++;
      else { state = stateOf(v, res.act); counts[state]++; checked.push(e.id); }
      const row = [res.act.lastActivityAt, res.act.lastAssistantAt, flagOf(res.act.inTurn), res.act.inTurn === null ? null : flagOf(res.act.waitsPerson), state, res.offset];
      // A row just inserted holds NULL everywhere, so a session with nothing to say yet is not written at all.
      const was = old ? [old.last_activity_at, old.last_assistant_at, old.in_turn, old.waits_person, old.state, old.transcript_offset] : [null, null, null, null, null, null];
      if (row.some((x, i) => x !== was[i])) {
        upd.run(...row, e.id);
        out.changed++;
      }
    }
    for (let i = 0; i < checked.length; i += CHUNK) {
      const part = checked.slice(i, i + CHUNK);
      db.prepare('UPDATE session SET state_checked_at = ? WHERE id IN (' + part.map(() => '?').join(', ') + ')').run(now, ...part);
    }

    // ---- panes: only terminal instances that could be listed are touched; an unknown one is left exactly as it was
    if (snap.panes.known) paneRows(db, snap, uniq, owners, have, nodeId, now, out);
  });
  return out;
}

function paneRows(db, snap, uniq, owners, have, nodeId, now, out) {
  const closePane = db.prepare('UPDATE pane SET closed_at = max(?, opened_at) WHERE id = ?');
  const closeLinks = db.prepare('UPDATE session_pane SET to_at = max(?, from_at) WHERE pane_id = ? AND to_at IS NULL');
  const closeLinkOf = db.prepare('UPDATE session_pane SET to_at = max(?, from_at) WHERE session_id = ? AND pane_id <> ? AND to_at IS NULL');
  const open = db.prepare('SELECT id, mux_instance, pane_no FROM pane WHERE node_id = ? AND closed_at IS NULL').all(nodeId);
  const live = new Map(); // 'instance\0no' -> pane row id
  for (const p of open) {
    const st = instanceState(snap, p.mux_instance);
    if (st === 'unknown') continue;
    const k = snap.panes.sockets.get(p.mux_instance);
    if (st === 'listed' && k.panes.has(p.pane_no)) { live.set(p.mux_instance + '\0' + p.pane_no, p.id); continue; }
    closeLinks.run(now, p.id);
    closePane.run(now, p.id);
    out.paneClosed++;
  }
  for (const [inst, k] of snap.panes.sockets) {
    if (k.state !== 'listed') continue;
    for (const no of [...k.panes].sort((a, b) => a - b)) {
      const key = inst + '\0' + no;
      if (live.has(key)) continue;
      const id = newId(now);
      db.prepare('INSERT INTO pane (id, node_id, mux_instance, pane_no, opened_at) VALUES (?, ?, ?, ?, ?)').run(id, nodeId, inst, no, now);
      live.set(key, id);
      out.paneOpened++;
    }
  }
  // Who sits in each live pane. A session that moved panes closes its old row and opens a new one.
  const openLink = db.prepare('SELECT session_id FROM session_pane WHERE pane_id = ? AND to_at IS NULL');
  const insertLink = db.prepare('INSERT INTO session_pane (session_id, pane_id, from_at) VALUES (?, ?, ?)');
  for (const [key, paneId] of live) {
    const owner = owners.get(key);
    const ownerOk = owner !== undefined && have.has(owner);
    const rows = openLink.all(paneId).map((r) => r.session_id);
    if (!ownerOk) {
      // Nobody claims it now. Only a registry read whole may say so; a partial one leaves the old seat as it is.
      if (snap.registry.complete && rows.length > 0) closeLinks.run(now, paneId);
      continue;
    }
    if (rows.length === 1 && rows[0] === owner) continue;
    closeLinks.run(now, paneId);
    insertLink.run(owner, paneId, now);
    out.moved++;
  }
  // A session now owning a pane leaves any other pane it sat in.
  for (const e of uniq) {
    const c = claimOf(e.rec);
    if (c === null || !have.has(e.id)) continue;
    const key = c.instance + '\0' + c.no;
    if (owners.get(key) === e.id && live.has(key)) closeLinkOf.run(now, e.id, live.get(key));
  }
}
