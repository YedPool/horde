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

export const RANKS = ['thrall', 'orc', 'warg', 'analyst', 'unknown'];
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
];

export const SCHEMA_VERSION = MIGRATIONS.length;
export const METRIC_TABLES = ['tokens_requests', 'tokens_turns', 'tokens_agents', 'tokens_limits'];

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
  return new Store(db, file);
}

class Store {
  constructor(db, file) {
    this.db = db;
    this.file = file;
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
      getOff: p('SELECT size, mtime, offset, ident FROM meter_offsets WHERE path = ?'),
      setOff: p(`INSERT INTO meter_offsets (path, size, mtime, offset, ident) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT (path) DO UPDATE SET size = excluded.size, mtime = excluded.mtime, offset = excluded.offset, ident = excluded.ident`),
      latestTurn: p('SELECT turn_uuid FROM tokens_turns WHERE session_id = ? AND agent_id IS ? ORDER BY at DESC, id DESC LIMIT 1'),
      openHit: p('SELECT 1 AS x FROM tokens_limits WHERE session_id = ? AND agent_id IS ? AND stuck_until IS NULL LIMIT 1'),
      limitByHit: p('SELECT * FROM tokens_limits WHERE hit_uuid = ?'),
      alerted: p('UPDATE tokens_limits SET alerted_at = ? WHERE hit_uuid = ? AND alerted_at IS NULL'),
    };
  }

  getOffset(file) { return this.s.getOff.get(file) || null; }
  latestTurnUuid(session, agent) { const r = this.s.latestTurn.get(session, nz(agent)); return r ? r.turn_uuid : null; }
  hasOpenLimit(session, agent) { return !!this.s.openHit.get(session, nz(agent)); }
  limitByHit(hit) { return this.s.limitByHit.get(hit) || null; }
  markAlerted(hit, at) { return this.s.alerted.run(at, hit).changes === 1; }

  // Apply one reader batch and the file's new offset in ONE transaction, so a crash never leaves rows
  // without their offset (which would only be re-applied, harmlessly) or an offset without its rows
  // (which would lose them for good).
  // batch = { tokens_requests: [], tokens_turns: [], tokens_agents: [], tokens_limits: [], limit_resumes: [] }
  apply(batch, offsetRec) {
    // Counts are DISTINCT rows touched, so a request repeated on three records is one row, not three.
    const keys = { tokens_requests: new Set(), tokens_turns: new Set(), tokens_agents: new Set(), tokens_limits: new Set() };
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
    for (const t of METRIC_TABLES) {
      const r = this.db.prepare('SELECT COUNT(*) AS n, MAX(at) AS newest FROM ' + t).get();
      out[t] = { rows: r.n, newest: r.newest };
    }
    return out;
  }

  close() { this.db.close(); }
}
