// The fleet meter's database: <HORDE_HOME>/metrics/fleet.sqlite.
//
// WHY ONE SQLITE FILE IN WAL MODE: the collector (every 15 min), the limit watch (every 2 min) and a
// person running `horde meter status` all touch it at once, and WAL lets readers go on while one
// writer writes. busy_timeout 5000 makes a second writer wait instead of failing: both writers
// hold a lock for milliseconds, so five seconds is far past any honest wait.
//
// RULES FOR EVERY METRIC TABLE (the design of the fleet meter, T-0257):
//   - STRICT, so a wrong type is an error here and not a surprise in a report next month;
//   - the name is <source>_<what>, and `source` is a column that must equal that prefix (a CHECK),
//     so a row can never be filed under the wrong source and a second source (a different harness's
//     numbers, the relay's) can share the file without a name clash;
//   - `at` is when the thing happened, UTC milliseconds, never the time it was collected;
//   - every write is an upsert on a natural key, so collecting the same bytes twice changes nothing.
// meter_offsets is bookkeeping, not a metric, so it carries neither source nor at.
//
// VERSIONING: PRAGMA user_version is the number of migrations applied. A migration only ever adds;
// a new one is appended to MIGRATIONS and never edits an old one, so a database made by any earlier
// version walks forward to the current shape and an old binary refuses a database from the future.
import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { dbPathFor } from './home.mjs';
import { contextLimitOf } from './prices.mjs';
import { loadOrcRegistry } from './orc-registry.mjs';

export const RANKS = ['thrall', 'orc', 'warg', 'analyst', 'unknown'];
export const HOPS = ['phone_sent', 'relay_recorded', 'pc_journal', 'mailed', 'taken']; // in the order a message passes them
export const CLOCKS = ['phone', 'pc'];
export const USAGE_STATES = ['running', 'done'];
// A session or agent with no record for this long is 'done' (no transcript carries an end record).
export const IDLE_DONE_MS = 10 * 60 * 1000;
export const TRIGGERS = ['founder', 'mail', 'task-notice', 'stop-hook', 'compaction', 'timer', 'other'];
const q = (list) => list.map((s) => "'" + s + "'").join(', ');

const MIGRATIONS = [
  // 1: the first shape (PR 1 of the meter: the tokens source).
  `
  CREATE TABLE tokens_requests (
    id INTEGER PRIMARY KEY,
    source TEXT NOT NULL CHECK (source = 'tokens'),
    at INTEGER NOT NULL,
    request_id TEXT NOT NULL UNIQUE,
    session_id TEXT NOT NULL,
    agent_id TEXT,
    turn_uuid TEXT,
    orc TEXT NOT NULL,
    rank TEXT NOT NULL CHECK (rank IN (${q(RANKS)})),
    model TEXT NOT NULL,
    family TEXT NOT NULL,
    input INTEGER NOT NULL,
    output INTEGER NOT NULL,
    cache_read INTEGER NOT NULL,
    cache_write_5m INTEGER NOT NULL,
    cache_write_1h INTEGER NOT NULL,
    context_tokens INTEGER NOT NULL,
    cost_usd REAL NOT NULL
  ) STRICT;
  CREATE INDEX tokens_requests_at ON tokens_requests (at);
  CREATE INDEX tokens_requests_session ON tokens_requests (session_id, at);
  CREATE INDEX tokens_requests_turn ON tokens_requests (turn_uuid);
  CREATE INDEX tokens_requests_orc ON tokens_requests (orc, at);

  CREATE TABLE tokens_turns (
    id INTEGER PRIMARY KEY,
    source TEXT NOT NULL CHECK (source = 'tokens'),
    at INTEGER NOT NULL,
    session_id TEXT NOT NULL,
    agent_id TEXT,
    turn_uuid TEXT NOT NULL UNIQUE,
    trigger TEXT NOT NULL CHECK (trigger IN (${q(TRIGGERS)})),
    requests INTEGER NOT NULL DEFAULT 0,
    duration_ms INTEGER NOT NULL DEFAULT 0,
    cost_usd REAL NOT NULL DEFAULT 0
  ) STRICT;
  CREATE INDEX tokens_turns_session ON tokens_turns (session_id, at);

  CREATE TABLE tokens_agents (
    id INTEGER PRIMARY KEY,
    source TEXT NOT NULL CHECK (source = 'tokens'),
    at INTEGER NOT NULL,
    tool_use_id TEXT NOT NULL UNIQUE,
    parent_session_id TEXT NOT NULL,
    agent_id TEXT,
    orc TEXT NOT NULL,
    agent_type TEXT,
    model_asked TEXT,
    model_used TEXT,
    description TEXT CHECK (description IS NULL OR length(description) <= 120),
    route_id TEXT
  ) STRICT;
  CREATE INDEX tokens_agents_parent ON tokens_agents (parent_session_id);

  CREATE TABLE tokens_limits (
    id INTEGER PRIMARY KEY,
    source TEXT NOT NULL CHECK (source = 'tokens'),
    at INTEGER NOT NULL,
    session_id TEXT NOT NULL,
    agent_id TEXT,
    orc TEXT NOT NULL,
    hit_uuid TEXT NOT NULL UNIQUE,
    limit_type TEXT NOT NULL,
    resets_at INTEGER,
    stuck_until INTEGER,
    stuck_ms INTEGER,
    alerted_at INTEGER
  ) STRICT;
  CREATE INDEX tokens_limits_session ON tokens_limits (session_id, at);

  CREATE TABLE meter_offsets (
    path TEXT PRIMARY KEY,
    size INTEGER NOT NULL,
    mtime INTEGER NOT NULL,
    offset INTEGER NOT NULL,
    ident TEXT NOT NULL DEFAULT ''
  ) STRICT;
  `,
  // 2: a limit hit recorded as alerted WITHOUT a message (the first watch run's silent baseline), and
  // a place for small facts about the meter itself (when the watch first ran).
  `
  ALTER TABLE tokens_limits ADD COLUMN alerted_silently INTEGER NOT NULL DEFAULT 0;
  CREATE TABLE meter_state (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  ) STRICT;
  `,
  // 3: PR 2a - the live view of every session and subagent (tokens_usage, one row per session or agent,
  // updated in place) and the hops of a phone message (mail_hops). tokens_agents.done_at is when the
  // parent's tool result for that agent's call came back.
  `
  ALTER TABLE tokens_agents ADD COLUMN done_at INTEGER;

  CREATE TABLE tokens_usage (
    id INTEGER PRIMARY KEY,
    source TEXT NOT NULL CHECK (source = 'tokens'),
    at INTEGER NOT NULL,
    session_id TEXT NOT NULL,
    agent_id TEXT NOT NULL DEFAULT '',
    orc_id TEXT,
    model TEXT NOT NULL,
    started_at INTEGER NOT NULL,
    last_seen_at INTEGER NOT NULL,
    minutes_running REAL NOT NULL,
    input_tokens INTEGER NOT NULL,
    output_tokens INTEGER NOT NULL,
    cache_read_tokens INTEGER NOT NULL,
    cache_write_tokens INTEGER NOT NULL,
    context_tokens INTEGER NOT NULL,
    context_limit INTEGER NOT NULL,
    state TEXT NOT NULL CHECK (state IN (${q(USAGE_STATES)})),
    UNIQUE (session_id, agent_id)
  ) STRICT;
  CREATE INDEX tokens_usage_seen ON tokens_usage (session_id, last_seen_at);

  CREATE TABLE mail_hops (
    id INTEGER PRIMARY KEY,
    source TEXT NOT NULL CHECK (source = 'mail'),
    at INTEGER NOT NULL,
    message_id TEXT NOT NULL,
    hop TEXT NOT NULL CHECK (hop IN (${q(HOPS)})),
    orc_id TEXT,
    from_session TEXT NOT NULL,
    to_session TEXT NOT NULL DEFAULT '',
    clock TEXT NOT NULL CHECK (clock IN (${q(CLOCKS)})),
    UNIQUE (message_id, hop)
  ) STRICT;
  CREATE INDEX mail_hops_at ON mail_hops (at);
  `,
];

export const SCHEMA_VERSION = MIGRATIONS.length;
export const METRIC_TABLES = ['tokens_requests', 'tokens_turns', 'tokens_agents', 'tokens_limits', 'tokens_usage'];
export const STAT_TABLES = [...METRIC_TABLES, 'mail_hops'];

const nz = (v) => (v === undefined ? null : v);

export function openStore(home) {
  const file = dbPathFor(home);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const db = new DatabaseSync(file);
  db.exec('PRAGMA busy_timeout = 5000');
  db.exec('PRAGMA journal_mode = WAL');
  db.exec('PRAGMA synchronous = NORMAL');
  const have = db.prepare('PRAGMA user_version').get().user_version;
  if (have > SCHEMA_VERSION) {
    db.close();
    throw new Error('the fleet meter database is version ' + have + ', newer than this program (' + SCHEMA_VERSION + '); update Horde.');
  }
  for (let v = have; v < SCHEMA_VERSION; v++) {
    // One transaction per migration: a crash leaves the database at a whole version.
    db.exec('BEGIN IMMEDIATE');
    try {
      db.exec(MIGRATIONS[v]);
      db.exec('PRAGMA user_version = ' + (v + 1));
      db.exec('COMMIT');
    } catch (e) {
      db.exec('ROLLBACK');
      throw e;
    }
  }
  return new Store(db, file, home);
}

class Store {
  constructor(db, file, home) {
    this.db = db;
    this.file = file;
    this.home = home;
    this.orcReg = null;
    const p = (sql) => db.prepare(sql);
    this.s = {
      req: p(`INSERT INTO tokens_requests (source, at, request_id, session_id, agent_id, turn_uuid, orc, rank, model, family,
          input, output, cache_read, cache_write_5m, cache_write_1h, context_tokens, cost_usd)
        VALUES ('tokens', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (request_id) DO UPDATE SET at = excluded.at, session_id = excluded.session_id, agent_id = excluded.agent_id,
          turn_uuid = excluded.turn_uuid, orc = excluded.orc, rank = excluded.rank, model = excluded.model, family = excluded.family,
          input = excluded.input, output = excluded.output, cache_read = excluded.cache_read, cache_write_5m = excluded.cache_write_5m,
          cache_write_1h = excluded.cache_write_1h, context_tokens = excluded.context_tokens, cost_usd = excluded.cost_usd`),
      turn: p(`INSERT INTO tokens_turns (source, at, session_id, agent_id, turn_uuid, trigger)
        VALUES ('tokens', ?, ?, ?, ?, ?)
        ON CONFLICT (turn_uuid) DO UPDATE SET at = excluded.at, trigger = excluded.trigger`),
      agent: p(`INSERT INTO tokens_agents (source, at, tool_use_id, parent_session_id, agent_id, orc, agent_type, model_asked, model_used, description, route_id)
        VALUES ('tokens', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (tool_use_id) DO UPDATE SET at = MIN(at, excluded.at), orc = excluded.orc,
          agent_id = COALESCE(excluded.agent_id, agent_id), agent_type = COALESCE(excluded.agent_type, agent_type),
          model_asked = COALESCE(excluded.model_asked, model_asked), model_used = COALESCE(excluded.model_used, model_used),
          description = COALESCE(excluded.description, description), route_id = COALESCE(excluded.route_id, route_id)`),
      limit: p(`INSERT INTO tokens_limits (source, at, session_id, agent_id, orc, hit_uuid, limit_type, resets_at, stuck_until, stuck_ms)
        VALUES ('tokens', ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (hit_uuid) DO UPDATE SET orc = excluded.orc, limit_type = excluded.limit_type, resets_at = excluded.resets_at,
          stuck_until = COALESCE(stuck_until, excluded.stuck_until), stuck_ms = COALESCE(stuck_ms, excluded.stuck_ms)`),
      // A later record frees every hit of that session still open before it. alerted_at is left alone.
      resume: p(`UPDATE tokens_limits SET stuck_until = ?, stuck_ms = ? - at
        WHERE session_id = ? AND agent_id IS ? AND stuck_until IS NULL AND at < ?`),
      recompute: p(`UPDATE tokens_turns SET
          requests = (SELECT COUNT(*) FROM tokens_requests r WHERE r.turn_uuid = tokens_turns.turn_uuid),
          cost_usd = (SELECT COALESCE(SUM(r.cost_usd), 0) FROM tokens_requests r WHERE r.turn_uuid = tokens_turns.turn_uuid),
          duration_ms = COALESCE((SELECT MAX(r.at) FROM tokens_requests r WHERE r.turn_uuid = tokens_turns.turn_uuid) - tokens_turns.at, 0)
        WHERE turn_uuid = ?`),
      usageAgg: p(`SELECT COALESCE(SUM(input), 0) AS i, COALESCE(SUM(output), 0) AS o, COALESCE(SUM(cache_read), 0) AS cr,
          COALESCE(SUM(cache_write_5m + cache_write_1h), 0) AS cw, COALESCE(MAX(context_tokens), 0) AS maxctx
        FROM tokens_requests WHERE session_id = ? AND agent_id IS ?`),
      usageLast: p('SELECT model, context_tokens FROM tokens_requests WHERE session_id = ? AND agent_id IS ? ORDER BY at DESC, id DESC LIMIT 1'),
      usageGet: p('SELECT * FROM tokens_usage WHERE session_id = ? AND agent_id = ?'),
      usageSet: p(`INSERT INTO tokens_usage (source, at, session_id, agent_id, orc_id, model, started_at, last_seen_at, minutes_running,
          input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, context_tokens, context_limit, state)
        VALUES ('tokens', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (session_id, agent_id) DO UPDATE SET at = excluded.at, orc_id = excluded.orc_id, model = excluded.model,
          started_at = excluded.started_at, last_seen_at = excluded.last_seen_at, minutes_running = excluded.minutes_running,
          input_tokens = excluded.input_tokens, output_tokens = excluded.output_tokens, cache_read_tokens = excluded.cache_read_tokens,
          cache_write_tokens = excluded.cache_write_tokens, context_tokens = excluded.context_tokens,
          context_limit = excluded.context_limit, state = excluded.state`),
      usageOfSession: p('SELECT * FROM tokens_usage WHERE session_id = ? ORDER BY agent_id'),
      usageRecent: p('SELECT * FROM tokens_usage WHERE last_seen_at >= ? ORDER BY session_id, agent_id'),
      agentDoneAt: p('SELECT done_at FROM tokens_agents WHERE parent_session_id = ? AND agent_id = ?'),
      agentReturn: p('UPDATE tokens_agents SET done_at = MIN(COALESCE(done_at, ?), ?) WHERE tool_use_id = ?'),
      agentByCall: p('SELECT parent_session_id, agent_id FROM tokens_agents WHERE tool_use_id = ? AND agent_id IS NOT NULL'),
      settle: p("UPDATE tokens_usage SET state = 'done' WHERE state = 'running' AND last_seen_at < ?"),
      hop: p(`INSERT INTO mail_hops (source, at, message_id, hop, orc_id, from_session, to_session, clock) VALUES ('mail', ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (message_id, hop) DO NOTHING`),
      hopKnown: p("SELECT message_id FROM mail_hops WHERE hop = 'phone_sent'"),
      hopAll: p('SELECT message_id, hop, at, clock FROM mail_hops ORDER BY message_id, at'),
      getOff: p('SELECT size, mtime, offset, ident FROM meter_offsets WHERE path = ?'),
      setOff: p(`INSERT INTO meter_offsets (path, size, mtime, offset, ident) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT (path) DO UPDATE SET size = excluded.size, mtime = excluded.mtime, offset = excluded.offset, ident = excluded.ident`),
      latestTurn: p('SELECT turn_uuid FROM tokens_turns WHERE session_id = ? AND agent_id IS ? ORDER BY at DESC, id DESC LIMIT 1'),
      openHit: p('SELECT 1 AS x FROM tokens_limits WHERE session_id = ? AND agent_id IS ? AND stuck_until IS NULL LIMIT 1'),
      limitByHit: p('SELECT * FROM tokens_limits WHERE hit_uuid = ?'),
      alerted: p('UPDATE tokens_limits SET alerted_at = ?, alerted_silently = ? WHERE hit_uuid = ? AND alerted_at IS NULL'),
      getState: p('SELECT value FROM meter_state WHERE key = ?'),
      setState: p('INSERT INTO meter_state (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value'),
    };
  }

  // The per-session / per-agent view, refreshed from the SAME rows the collector wrote (tokens_requests) plus
  // what the reader saw of the file (first and last record time). 'done' means: no record for IDLE_DONE_MS,
  // or (an agent) the parent's tool result for its call came back and the agent wrote nothing after it.
  refreshUsage(session, agent, mark, now) {
    const s = this.s;
    const ag = agent === '' ? null : agent;
    const old = s.usageGet.get(session, agent);
    if (!mark && !old) return false;
    const started = Math.min(mark ? mark.started_at : Infinity, old ? old.started_at : Infinity);
    const seen = Math.max(mark ? mark.last_seen_at : 0, old ? old.last_seen_at : 0);
    const orcId = this.orcIdOf(session);
    const a = s.usageAgg.get(session, ag);
    const last = s.usageLast.get(session, ag);
    const model = last ? last.model : (old ? old.model : '');
    let returned = null;
    if (ag) { const r = s.agentDoneAt.get(session, ag); returned = r ? r.done_at : null; }
    const done = (returned != null && seen <= returned) || now - seen > IDLE_DONE_MS;
    s.usageSet.run(seen, session, agent, orcId, model, started, seen, (seen - started) / 60000, a.i, a.o, a.cr, a.cw,
      last ? last.context_tokens : 0, contextLimitOf(model, a.maxctx), done ? 'done' : 'running');
    return true;
  }

  usageOf(session) { return this.s.usageOfSession.all(session); }
  usageSince(at) { return this.s.usageRecent.all(at); }

  // Marks every row quiet for IDLE_DONE_MS as done (a row is only ever opened again by a new record).
  settleUsage(now = Date.now()) { return Number(this.s.settle.run(now - IDLE_DONE_MS).changes); }

  // mail_hops
  addHop(h) {
    const orcId = this.orcIdOf(h.to_session || h.from_session);
    return this.s.hop.run(h.at, h.message_id, h.hop, orcId, h.from_session, h.to_session || '', h.clock).changes === 1;
  }

  // The Orc of a session, from the Orc registry only (orc-registry.mjs); null when it has no row for it.
  // The registry is read once per Store and again whenever reloadOrcRegistry() is called (each pass does).
  orcIdOf(sessionId) {
    if (!this.orcReg) this.reloadOrcRegistry();
    return this.orcReg.orcIdOf(sessionId);
  }
  reloadOrcRegistry() { this.orcReg = loadOrcRegistry(this.home); }
  knownMessages() { return new Set(this.s.hopKnown.all().map((r) => r.message_id)); }
  allHops() { return this.s.hopAll.all(); }

  getOffset(file) { return this.s.getOff.get(file) || null; }
  latestTurnUuid(session, agent) { const r = this.s.latestTurn.get(session, nz(agent)); return r ? r.turn_uuid : null; }
  hasOpenLimit(session, agent) { return !!this.s.openHit.get(session, nz(agent)); }
  limitByHit(hit) { return this.s.limitByHit.get(hit) || null; }
  markAlerted(hit, at, silently = false) { return this.s.alerted.run(at, silently ? 1 : 0, hit).changes === 1; }
  getState(key) { const r = this.s.getState.get(key); return r ? r.value : null; }
  setState(key, value) { this.s.setState.run(key, String(value)); }

  // Apply one reader batch and the file's new offset in ONE transaction, so a crash never leaves rows
  // without their offset (which would only be re-applied, harmlessly) or an offset without its rows
  // (which would lose them for good).
  // batch = { tokens_requests: [], tokens_turns: [], tokens_agents: [], tokens_limits: [], limit_resumes: [] }
  apply(batch, offsetRec, now = Date.now()) {
    // Counts are DISTINCT rows touched, so a request repeated on three records is one row, not three.
    const keys = { tokens_requests: new Set(), tokens_turns: new Set(), tokens_agents: new Set(), tokens_limits: new Set(), tokens_usage: new Set() };
    const s = this.s;
    this.db.exec('BEGIN IMMEDIATE');
    try {
      for (const r of batch.tokens_turns || []) { s.turn.run(r.at, r.session_id, nz(r.agent_id), r.turn_uuid, r.trigger); keys.tokens_turns.add(r.turn_uuid); }
      const touched = new Set((batch.tokens_turns || []).map((r) => r.turn_uuid));
      for (const r of batch.tokens_requests || []) {
        s.req.run(r.at, r.request_id, r.session_id, nz(r.agent_id), nz(r.turn_uuid), r.orc, r.rank, r.model, r.family,
          r.input, r.output, r.cache_read, r.cache_write_5m, r.cache_write_1h, r.context_tokens, r.cost_usd);
        if (r.turn_uuid) touched.add(r.turn_uuid);
        keys.tokens_requests.add(r.request_id);
      }
      for (const r of batch.tokens_agents || []) {
        s.agent.run(r.at, r.tool_use_id, r.parent_session_id, nz(r.agent_id), r.orc, nz(r.agent_type), nz(r.model_asked),
          nz(r.model_used), nz(r.description), nz(r.route_id));
        keys.tokens_agents.add(r.tool_use_id);
      }
      for (const r of batch.tokens_limits || []) {
        s.limit.run(r.at, r.session_id, nz(r.agent_id), r.orc, r.hit_uuid, r.limit_type, nz(r.resets_at), nz(r.stuck_until), nz(r.stuck_ms));
        keys.tokens_limits.add(r.hit_uuid);
      }
      for (const r of batch.limit_resumes || []) s.resume.run(r.at, r.at, r.session_id, nz(r.agent_id), r.at);
      for (const u of touched) s.recompute.run(u);
      // THE LIVE VIEW: every file the reader saw records of, plus every agent whose call just returned.
      const marks = new Map();
      for (const m of batch.tokens_usage || []) marks.set(m.session_id + '\u0000' + (m.agent_id || ''), m);
      const redo = new Set(marks.keys());
      for (const r of batch.agent_returns || []) {
        s.agentReturn.run(r.at, r.at, r.tool_use_id);
        const who = s.agentByCall.get(r.tool_use_id);
        if (who) redo.add(who.parent_session_id + '\u0000' + who.agent_id);
      }
      for (const key of redo) {
        const [sid, aid] = key.split('\u0000');
        if (this.refreshUsage(sid, aid, marks.get(key) || null, now)) keys.tokens_usage.add(key);
      }
      if (offsetRec) s.setOff.run(offsetRec.path, offsetRec.size, offsetRec.mtime, offsetRec.offset, offsetRec.ident);
      this.db.exec('COMMIT');
    } catch (e) {
      this.db.exec('ROLLBACK');
      throw e;
    }
    return Object.fromEntries(Object.entries(keys).map(([t, k]) => [t, k.size]));
  }

  tableStats() {
    const out = {};
    for (const t of STAT_TABLES) {
      const r = this.db.prepare('SELECT COUNT(*) AS n, MAX(at) AS newest FROM ' + t).get();
      out[t] = { rows: r.n, newest: r.newest };
    }
    return out;
  }

  close() { this.db.close(); }
}
