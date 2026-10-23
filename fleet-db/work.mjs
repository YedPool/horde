// Work units (migration 6): the one write path for the work_unit table, and its reader.
//
// AN AGENT is an Agent-tool subagent inside a session: no window of its own, named by the harness's
// subagent id. A WARG is its own agent session in its own pane. Both have a parent: the session that
// spawned them. C's hooks call start at SubagentStart / wezspawn and end at SubagentStop / session end;
// the fleet meter reads the table read-only by ATTACH and keeps every token figure in its own database.
//
// RULES HERE (the schema holds the rest):
//   - agent_id is stored EXACTLY as given. No trimming, no case change, no reformatting: the meter joins on
//     it. A bad one (empty, too long, not printable ASCII) is refused, never repaired;
//   - a repeat of a start or an end changes nothing and says "already started" / "already ended" (exit 0),
//     so a hook that fires twice is harmless;
//   - a task the ledger does not know yet is NOT a refusal: the ledger may be ahead of the last import. The
//     unit is recorded as no_task and a warning names the id;
//   - a parent or warg session fleet.db has not seen gets a stub session row, as the importer makes one.
import { newId } from './write.mjs';
import { inWrite } from './store.mjs';
import { WORK_KINDS, WORK_TYPES, WORK_OUTCOMES } from './schema.mjs';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const TASK_KEY = /^T-\d{4,}$/;

export function refuse(message) {
  const e = new Error(message);
  e.refusal = true;
  return e;
}

function uuidOf(v, what) {
  const s = typeof v === 'string' ? v.toLowerCase() : '';
  if (!UUID.test(s)) throw refuse(what + ' must be a session uuid');
  return s;
}

function textOf(v, what, max, asciiOnly) {
  if (typeof v !== 'string' || v.length < 1 || v.length > max) throw refuse(what + ' must be 1 to ' + max + ' characters');
  if (!v.isWellFormed()) throw refuse(what + ' holds a lone surrogate');
  if (asciiOnly && /[^!-~]/.test(v)) throw refuse(what + ' must be printable ASCII with no spaces');
  return v;
}

function timeOf(at, what) {
  if (!Number.isSafeInteger(at) || at < 0) throw refuse(what + ' must be UTC milliseconds');
  return at;
}

function ensureNode(db, at, mint) {
  const have = db.prepare('SELECT id FROM node ORDER BY is_authority DESC, created_at, id LIMIT 1').get();
  if (have) return have.id;
  const id = mint(at);
  db.prepare('INSERT INTO node (id, name, is_authority, created_at) VALUES (?, ?, 1, ?)').run(id, 'this-pc', at);
  return id;
}

// Start a unit. Returns { action: 'started' | 'already', id, warnings }.
export function startWork(db, req, { mint = newId, now = Date.now } = {}) {
  const kind = req.kind;
  if (!WORK_KINDS.includes(kind)) throw refuse('kind must be agent or warg');
  const parent = uuidOf(req.parentSession, 'ParentSession');
  if (!WORK_TYPES.includes(req.workType)) throw refuse('work type must be one of ' + WORK_TYPES.join(', '));
  let agentId = null;
  let agentType = null;
  let session = null;
  if (kind === 'agent') {
    if (req.session !== undefined && req.session !== null) throw refuse('an agent has no session of its own');
    if (req.agentId === undefined || req.agentId === null) throw refuse('an agent needs its AgentId');
    agentId = textOf(req.agentId, 'AgentId', 200, true);
    if (req.agentType !== undefined && req.agentType !== null) agentType = textOf(req.agentType, 'AgentType', 80, true);
  } else {
    if (req.agentId !== undefined && req.agentId !== null) throw refuse('a warg has no AgentId');
    if (req.agentType !== undefined && req.agentType !== null) throw refuse('a warg has no AgentType');
    if (req.session === undefined || req.session === null) throw refuse('a warg needs its Session');
    session = uuidOf(req.session, 'Session');
    if (session === parent) throw refuse('a warg is not its own parent');
  }
  const domain = req.domain === undefined || req.domain === null ? null : textOf(req.domain, 'Domain', 120, false);
  const model = req.model === undefined || req.model === null ? null : textOf(req.model, 'Model', 80, false);
  let taskKey = null;
  if (req.task !== undefined && req.task !== null) {
    if (typeof req.task !== 'string' || !TASK_KEY.test(req.task)) throw refuse('Task must look like T-0123');
    taskKey = req.task;
  }
  const at = timeOf(req.at ?? now(), 'At');

  return inWrite(db, () => {
    const find = kind === 'agent'
      ? db.prepare('SELECT id FROM work_unit WHERE parent_session_id = ? AND agent_id = ?').get(parent, agentId)
      : db.prepare('SELECT id, parent_session_id FROM work_unit WHERE session_id = ?').get(session);
    if (find) {
      if (kind === 'warg' && find.parent_session_id !== parent) throw refuse('session ' + session + ' is already recorded as a warg of another parent');
      return repeatOf(db, find.id, { workType: req.workType, domain, model, agentType, taskKey });
    }
    const nodeId = ensureNode(db, at, mint);
    let p = db.prepare('SELECT id, orc_id FROM session WHERE id = ?').get(parent);
    if (!p) {
      db.prepare("INSERT INTO session (id, node_id, rank, first_seen, last_seen) VALUES (?, ?, 'unknown', ?, ?)").run(parent, nodeId, at, at);
      p = { id: parent, orc_id: null };
    }
    if (kind === 'warg') {
      const w = db.prepare('SELECT parent_session_id FROM session WHERE id = ?').get(session);
      if (!w) {
        db.prepare("INSERT INTO session (id, node_id, orc_id, rank, parent_session_id, first_seen, last_seen) VALUES (?, ?, ?, 'warg', ?, ?, ?)")
          .run(session, nodeId, p.orc_id, parent, at, at);
      } else if (w.parent_session_id !== null && w.parent_session_id !== parent) {
        throw refuse('session ' + session + ' already has a different parent in fleet.db');
      }
    }
    const warnings = [];
    let taskId = null;
    if (taskKey !== null) {
      const t = db.prepare('SELECT id FROM task WHERE key = ?').get(taskKey);
      if (t) taskId = t.id;
      else warnings.push('warning: task ' + taskKey + ' is not in fleet.db yet (the ledger may be ahead of the last import); recorded as no_task');
    }
    const id = mint(at);
    db.prepare(`INSERT INTO work_unit (id, kind, parent_session_id, orc_id, agent_id, agent_type, session_id, task_id, task_flag,
      work_type, domain, model, started_at, ended_at, outcome) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, 'running')`)
      .run(id, kind, parent, p.orc_id, agentId, agentType, session, taskId, taskId === null ? 'no_task' : null, req.workType, domain, model, at);
    return { action: 'started', id, warnings };
  });
}

// A start that names a unit already there. The first row is kept. A no_task unit is given the task a repeat
// names when fleet.db knows it (the one change a repeat may make); any other field that differs is only noted.
function repeatOf(db, id, want) {
  const row = db.prepare('SELECT work_type, domain, model, agent_type, task_id, task_flag FROM work_unit WHERE id = ?').get(id);
  const warnings = [];
  const differs = [];
  let filled = false;
  if (want.taskKey !== null) {
    const t = db.prepare('SELECT id FROM task WHERE key = ?').get(want.taskKey);
    if (row.task_id === null) {
      if (t) {
        db.prepare('UPDATE work_unit SET task_id = ?, task_flag = NULL WHERE id = ?').run(t.id, id);
        filled = true;
      } else warnings.push('warning: task ' + want.taskKey + ' is not in fleet.db yet (the ledger may be ahead of the last import); the unit stays no_task');
    } else if (!t || t.id !== row.task_id) differs.push('task');
  }
  if (want.workType !== row.work_type) differs.push('work type');
  if (want.domain !== null && want.domain !== row.domain) differs.push('domain');
  if (want.model !== null && want.model !== row.model) differs.push('model');
  if (want.agentType !== null && want.agentType !== row.agent_type) differs.push('agent type');
  const note = differs.length ? 'note: the repeat differs from the first row in ' + differs.join(', ') + '; the first row is kept' : null;
  return { action: 'already', id, warnings, filled, note };
}

// End a unit. Returns { action: 'ended' | 'already', id, outcome }.
export function endWork(db, req, { now = Date.now } = {}) {
  if (!WORK_OUTCOMES.includes(req.outcome) || req.outcome === 'running') throw refuse('Outcome must be done, failed, stopped or abandoned');
  const byAgent = req.agentId !== undefined && req.agentId !== null;
  const bySession = req.session !== undefined && req.session !== null;
  if (byAgent === bySession) throw refuse('name the unit by ParentSession and AgentId, or by Session');
  let parent = null;
  let agentId = null;
  let session = null;
  if (byAgent) {
    parent = uuidOf(req.parentSession, 'ParentSession');
    agentId = textOf(req.agentId, 'AgentId', 200, true);
  } else {
    if (req.parentSession !== undefined && req.parentSession !== null) throw refuse('a Session names the unit alone; drop ParentSession');
    session = uuidOf(req.session, 'Session');
  }
  const explicit = req.at !== undefined && req.at !== null;
  const at = timeOf(explicit ? req.at : now(), 'At');
  return inWrite(db, () => {
    const u = byAgent
      ? db.prepare('SELECT id, started_at, outcome FROM work_unit WHERE parent_session_id = ? AND agent_id = ?').get(parent, agentId)
      : db.prepare('SELECT id, started_at, outcome FROM work_unit WHERE session_id = ?').get(session);
    if (!u) throw refuse('no work unit was started for ' + (byAgent ? 'agent ' + agentId : 'session ' + session));
    if (u.outcome !== 'running') {
      if (u.outcome === req.outcome) return { action: 'already', id: u.id, outcome: u.outcome };
      throw refuse('already ended as ' + u.outcome + '; it is not changed to ' + req.outcome);
    }
    // A clock that stepped back must not strand a unit; an end time named on purpose that is early is refused.
    if (at < u.started_at && explicit) throw refuse('At is before the unit started');
    const endedAt = Math.max(at, u.started_at);
    db.prepare('UPDATE work_unit SET ended_at = ?, outcome = ? WHERE id = ?').run(endedAt, req.outcome, u.id);
    return { action: 'ended', id: u.id, outcome: req.outcome };
  });
}

// The units, newest first, each with its Orc's letter and its task key. orc: a letter or lane folder.
export function listWork(db, { orc = null, running = false } = {}) {
  let orcId = null;
  if (orc !== null) {
    const o = db.prepare('SELECT id FROM orc WHERE letter = ? OR lane_dir = ?').get(orc, orc);
    if (!o) throw refuse('no Orc is called ' + orc);
    orcId = o.id;
  }
  return db.prepare(`SELECT w.id, w.kind, w.parent_session_id, o.letter AS orc, w.agent_id, w.agent_type, w.session_id,
      t.key AS task, w.task_flag, w.work_type, w.domain, w.model, w.started_at, w.ended_at, w.outcome
    FROM work_unit w LEFT JOIN orc o ON o.id = w.orc_id LEFT JOIN task t ON t.id = w.task_id
    WHERE (?1 IS NULL OR w.orc_id = ?1) AND (?2 = 0 OR w.outcome = 'running')
    ORDER BY w.started_at DESC, w.id DESC`).all(orcId, running ? 1 : 0).map((r) => ({ ...r }));
}
