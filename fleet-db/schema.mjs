// The fleet's one source of truth for work data: <HORDE_HOME>/fleet.db (design: planning/fleet-db-design.md).
//
// WHY THIS SHAPE (the work-data SSOT audit of 2026-10-19 found about 15 stores that retype each other):
//   - every entity has ONE row with ONE id. A ULID (26 characters, sortable by time, unique across PCs)
//     unless the thing already has a globally unique id of its own: a session is keyed by the harness's
//     session uuid. Human labels (T-0284, question 67, Orc letter F) are UNIQUE columns, never keys, so a
//     label can be corrected without rewriting every row that points at it;
//   - STATE rows (orc, session, pr, parking_lot_member) are updated in place. HISTORY rows (task_event,
//     question_event, answer, answer_route, answer_route_taken, changelog_entry, deploy) are append-only: a trigger refuses
//     UPDATE and DELETE, and each carries the sha256 of its canonical content as a UNIQUE column, so
//     importing the same line twice, or a double send, is a no-op;
//   - nothing derivable is stored. A task's state, priority and owner come from its events through the
//     task_now view, so a status card and the ledger can never disagree again;
//   - the links the audit found missing are CHECK constraints, not habits: a new "waiting on the founder"
//     event must name its question, a new question must name its task, a new changelog entry must name a
//     task or say it is fleet-wide. Rows imported from the old files carry backfill = 1 and are exempt;
//   - one live seat per Orc per PC is a partial UNIQUE index, so two sessions claiming one Orc (the 10-17
//     misrouted answers) cannot be written at all. Binding a new seat retires the old one in the same
//     transaction;
//   - times are INTEGER UTC milliseconds, the rule of the fleet meter (fleet-metrics/store.mjs), so the two
//     files join under ATTACH. A foreign key cannot cross files: the meter keeps orc_id and session_id as
//     plain text that equals the ids here.
//
// VERSIONING: PRAGMA user_version is the number of migrations applied. A migration only ever adds; a new
// one is appended to MIGRATIONS and never edits an old one (the meter's rule).

// Every enum lives here once; the CHECKs below and the access layer both read it.
export const RANKS = ['thrall', 'orc', 'warg', 'analyst', 'unknown'];
export const TASK_EVENT_KINDS = ['opened', 'started', 'progress', 'waiting', 'resumed', 'handed', 'done',
  'verified', 'reopened', 'dropped', 'superseded', 'priority'];
export const WAITING_ON = ['founder', 'orc', 'external', 'other'];
export const PR_STATES = ['open', 'closed', 'merged'];
export const PR_LINKED_BY = ['branch', 'body', 'event', 'hand', 'backfill'];
// change-reply: an Orc's reply to a changed answer (not-acted / undoing / cannot-undo, and why, in data_json).
// A close carries closed_by_seat in data_json ('warchief' only when the seat was proven, decisions PR 335).
export const QUESTION_EVENT_KINDS = ['updated', 'closed', 'reopened', 'ranked', 'acked', 'change-reply'];
export const CHANGELOG_KINDS = ['decision', 'result', 'merged', 'blocked', 'waiting', 'started', 'progress',
  'done', 'note'];
export const LOT_SELECTIONS = ['all', 'labels', 'orcs', 'backfill'];
export const MEMBER_STATES = ['parked', 'woken', 'dropped'];
export const WAKE_OUTCOMES = ['woken', 'still-awake', 'failed', 'held', 'asleep'];
export const LABEL_KINDS = ['task', 'question'];
// The main tables whose rows are objects of the Horde (migration 3), each with the column that says when
// the object came to be; null where the table keeps no time, and the entity row takes the time of writing.
export const ENTITY_TABLES = {
  horde: 'created_at', node: 'created_at', person: 'created_at', orc: 'created_at', session: 'first_seen',
  pane: 'opened_at', task: 'created_at', pr: 'checked_at', question: 'asked_at', answer: 'at',
  decisions_snapshot: 'published_at', changelog_entry: 'at', parking_lot: 'created_at', service: null,
  deploy: 'at', orc_status: 'at',
};
export const ENTITY_KINDS = Object.keys(ENTITY_TABLES);
export const LINK_RELATIONS = ['blocks', 'relates-to', 'answers', 'implements', 'duplicates', 'follows-up',
  'caused-by', 'mentions'];
export const PERSON_ROLES = ['founder', 'staff', 'other'];
export const WORK_KINDS = ['agent', 'warg'];
export const WORK_TYPES = ['build', 'review', 'verify', 'research', 'mechanical', 'monitor', 'other'];
export const WORK_OUTCOMES = ['running', 'done', 'failed', 'stopped', 'abandoned'];
export const WORK_TASK_FLAGS = ['no_task', 'backfill'];

const q = (list) => list.map((s) => "'" + s + "'").join(', ');
// Crockford base32, 26 characters: the same pattern as schema/fleet-parking-lot.v1.json.
const ulid = (col) => `CHECK (length(${col}) = 26 AND ${col} NOT GLOB '*[^0-9A-HJKMNP-TV-Z]*' AND substr(${col}, 1, 1) <= '7')`;
// Dashes exactly at 9, 14, 19, 24 and lower-case hex everywhere else ('-----...0000' is not a uuid).
const uuid = (col) => `CHECK (length(${col}) = 36 AND ${col} NOT GLOB '*[^0-9a-f-]*' AND length(replace(${col}, '-', '')) = 32
    AND substr(${col}, 9, 1) = '-' AND substr(${col}, 14, 1) = '-' AND substr(${col}, 19, 1) = '-' AND substr(${col}, 24, 1) = '-')`;
const sha = (col) => `CHECK (length(${col}) = 64 AND ${col} NOT GLOB '*[^0-9a-f]*')`;
const flag = (col) => `CHECK (${col} IN (0, 1))`;
const appendOnly = (table) => `
  CREATE TRIGGER ${table}_no_update BEFORE UPDATE ON ${table} BEGIN SELECT RAISE(ABORT, '${table} is append-only'); END;
  CREATE TRIGGER ${table}_no_delete BEFORE DELETE ON ${table} BEGIN SELECT RAISE(ABORT, '${table} is append-only'); END;`;
const NOW_MS = "CAST(unixepoch('subsec') * 1000 AS INTEGER)";
// An object's entity row is made, touched and removed with it, so nothing can point at an object that is
// not there and no object is missing from the registry; an entity row cannot be made for an object that
// does not exist. Its id cannot change: every pointer is to it. NEVER INSERT OR REPLACE an object: the
// replace deletes it and makes it again, so its entity row comes back without created_by and updated_at
// (review of phase 1b); change it with UPDATE, or INSERT ... ON CONFLICT DO UPDATE.
const entityTriggers = (table) => `
  CREATE TRIGGER ${table}_entity_add AFTER INSERT ON ${table} BEGIN
    INSERT INTO entity (id, kind, created_at) VALUES (NEW.id, '${table}', ${ENTITY_TABLES[table] ? 'NEW.' + ENTITY_TABLES[table] : NOW_MS}); END;
  CREATE TRIGGER ${table}_entity_touch AFTER UPDATE ON ${table} BEGIN
    UPDATE entity SET updated_at = ${NOW_MS} WHERE id = NEW.id; END;
  CREATE TRIGGER ${table}_entity_drop AFTER DELETE ON ${table} BEGIN DELETE FROM entity WHERE id = OLD.id; END;
  CREATE TRIGGER ${table}_id_fixed BEFORE UPDATE OF id ON ${table} WHEN NEW.id IS NOT OLD.id
  BEGIN SELECT RAISE(ABORT, '${table}: an id never changes'); END;
  CREATE TRIGGER entity_keeps_${table} BEFORE DELETE ON entity
  WHEN OLD.kind = '${table}' AND EXISTS (SELECT 1 FROM ${table} x WHERE x.id = OLD.id)
  BEGIN SELECT RAISE(ABORT, 'entity: its ${table} row is still there'); END;
  CREATE TRIGGER entity_needs_${table} BEFORE INSERT ON entity
  WHEN NEW.kind = '${table}' AND NOT EXISTS (SELECT 1 FROM ${table} x WHERE x.id = NEW.id)
  BEGIN SELECT RAISE(ABORT, 'entity: no ${table} row has this id'); END;`;
const entityBackfill = (table) =>
  `INSERT INTO entity (id, kind, created_at) SELECT id, '${table}', ${ENTITY_TABLES[table] ?? NOW_MS} FROM ${table};`;

export const MIGRATIONS = [
  // 1: the first shape (phase 0 of planning/fleet-db-design.md).
  `
  -- IDENTITY -----------------------------------------------------------------------------------------

  -- One row per PC. Exactly one is the authority for fleet-wide rows (orc, task, question, lot).
  CREATE TABLE node (
    id TEXT PRIMARY KEY ${ulid('id')},
    name TEXT NOT NULL UNIQUE CHECK (length(name) BETWEEN 1 AND 64),
    is_authority INTEGER NOT NULL DEFAULT 0 ${flag('is_authority')},
    created_at INTEGER NOT NULL
  ) STRICT;
  CREATE UNIQUE INDEX node_one_authority ON node (is_authority) WHERE is_authority = 1;

  -- The Thrall (rank thrall, letter M) and every Orc. lane_dir is the folder under _home/orcs and the id
  -- the old Orc registry used; letter is what people type. Both are unique, neither is the key.
  CREATE TABLE orc (
    id TEXT PRIMARY KEY ${ulid('id')},
    letter TEXT UNIQUE CHECK (letter GLOB '[A-Z]*' AND length(letter) BETWEEN 1 AND 4 AND letter NOT GLOB '*[^A-Z0-9]*'),
    lane_dir TEXT NOT NULL UNIQUE CHECK (length(lane_dir) BETWEEN 1 AND 64 AND lane_dir NOT GLOB '*[^a-z0-9-]*'),
    name TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 120),
    domain TEXT CHECK (length(domain) <= 400),
    rank TEXT NOT NULL CHECK (rank IN ('thrall', 'orc')),
    tier INTEGER CHECK (tier IN (1, 2)),
    back_burner INTEGER NOT NULL DEFAULT 0 ${flag('back_burner')},
    sort_order INTEGER,
    created_at INTEGER NOT NULL,
    retired_at INTEGER,
    retired_reason TEXT CHECK (retired_reason IN ('hand', 'fleet')),
    CHECK ((retired_at IS NULL) = (retired_reason IS NULL))
  ) STRICT;
  CREATE UNIQUE INDEX orc_one_thrall ON orc (rank) WHERE rank = 'thrall' AND retired_at IS NULL;

  -- One row per harness session, keyed by its session uuid. The current seat of an Orc is not a pointer
  -- on orc: it is the one live session of rank thrall/orc for that Orc on that PC, and the index below
  -- makes a second one impossible.
  CREATE TABLE session (
    id TEXT PRIMARY KEY ${uuid('id')},
    node_id TEXT NOT NULL REFERENCES node (id),
    orc_id TEXT REFERENCES orc (id),
    rank TEXT NOT NULL CHECK (rank IN (${q(RANKS)})),
    parent_session_id TEXT REFERENCES session (id),
    resumed_from_id TEXT REFERENCES session (id),
    -- The process that holds the session. One process can hold several session ids over time (a /clear
    -- gives the same process a new id while its command line keeps the old --resume id), so seat binding
    -- matches on (node, pid, process_started_at); a pid alone is reused by the OS.
    pid INTEGER CHECK (pid > 0),
    process_started_at INTEGER CHECK (process_started_at >= 0),
    start_cwd TEXT,
    cwd TEXT,
    transcript_path TEXT,
    -- What a wake needs to resume the session the same way (permission mode, settings file, remote control).
    launch_flags_json TEXT CHECK (launch_flags_json IS NULL OR json_valid(launch_flags_json)),
    origin TEXT CHECK (length(origin) <= 40),
    fleet_session_id TEXT CHECK (length(fleet_session_id) <= 120),
    fleet_run_dir TEXT,
    first_seen INTEGER NOT NULL,
    last_seen INTEGER NOT NULL,
    retired_at INTEGER,
    retired_reason TEXT CHECK (length(retired_reason) <= 200),
    CHECK (last_seen >= first_seen),
    CHECK (rank NOT IN ('thrall', 'orc') OR orc_id IS NOT NULL),
    CHECK (resumed_from_id IS NULL OR resumed_from_id <> id),
    CHECK ((pid IS NULL) = (process_started_at IS NULL))
  ) STRICT;
  CREATE INDEX session_process ON session (node_id, pid, process_started_at) WHERE pid IS NOT NULL;
  CREATE UNIQUE INDEX session_one_live_seat ON session (orc_id, node_id)
    WHERE retired_at IS NULL AND rank IN ('thrall', 'orc');
  CREATE INDEX session_orc ON session (orc_id, first_seen);
  CREATE INDEX session_parent ON session (parent_session_id);

  -- A pane number is reused across sessions and multiplexer restarts, so a pane is (PC, mux instance,
  -- number, opened_at), and at most one pane with a number is open at a time.
  CREATE TABLE pane (
    id TEXT PRIMARY KEY ${ulid('id')},
    node_id TEXT NOT NULL REFERENCES node (id),
    mux_instance TEXT NOT NULL CHECK (length(mux_instance) BETWEEN 1 AND 120),
    pane_no INTEGER NOT NULL CHECK (pane_no >= 0),
    opened_at INTEGER NOT NULL,
    closed_at INTEGER,
    UNIQUE (node_id, mux_instance, pane_no, opened_at)
  ) STRICT;
  CREATE UNIQUE INDEX pane_one_open ON pane (node_id, mux_instance, pane_no) WHERE closed_at IS NULL;

  CREATE TABLE session_pane (
    session_id TEXT NOT NULL REFERENCES session (id),
    pane_id TEXT NOT NULL REFERENCES pane (id),
    from_at INTEGER NOT NULL,
    to_at INTEGER,
    PRIMARY KEY (session_id, pane_id, from_at),
    CHECK (to_at IS NULL OR to_at >= from_at)
  ) STRICT;

  -- Human labels (T-NNNN, question numbers) are handed out here, inside BEGIN IMMEDIATE, so two sessions
  -- opening a task at the same moment get two numbers (the old max+1 read had no lock).
  CREATE TABLE label_seq (
    kind TEXT PRIMARY KEY CHECK (kind IN (${q(LABEL_KINDS)})),
    next INTEGER NOT NULL CHECK (next >= 1)
  ) STRICT;
  INSERT INTO label_seq (kind, next) VALUES ('task', 1), ('question', 1);

  -- WORK ---------------------------------------------------------------------------------------------

  -- What never changes about a task. Owner, priority and state are events (see task_now).
  CREATE TABLE task (
    id TEXT PRIMARY KEY ${ulid('id')},
    key TEXT NOT NULL UNIQUE CHECK (key GLOB 'T-[0-9][0-9][0-9][0-9]*' AND key NOT GLOB 'T-*[^0-9]*'),
    title TEXT NOT NULL CHECK (length(title) BETWEEN 1 AND 400),
    source TEXT NOT NULL CHECK (length(source) BETWEEN 1 AND 40),
    parent_id TEXT REFERENCES task (id),
    created_at INTEGER NOT NULL,
    CHECK (parent_id IS NULL OR parent_id <> id)
  ) STRICT;

  -- GitHub is the truth for a pull request; this row is its mirror, written only by the gh poll.
  CREATE TABLE pr (
    id TEXT PRIMARY KEY ${ulid('id')},
    repo TEXT NOT NULL CHECK (repo GLOB '?*/?*' AND repo NOT GLOB '*/*/*'),
    number INTEGER NOT NULL CHECK (number > 0),
    title TEXT,
    head_ref TEXT,
    state TEXT NOT NULL CHECK (state IN (${q(PR_STATES)})),
    merged_at INTEGER,
    merge_sha TEXT CHECK (merge_sha IS NULL OR (length(merge_sha) = 40 AND merge_sha NOT GLOB '*[^0-9a-f]*')),
    checked_at INTEGER NOT NULL,
    UNIQUE (repo, number),
    CHECK ((state = 'merged') = (merged_at IS NOT NULL))
  ) STRICT;

  CREATE TABLE task_pr (
    task_id TEXT NOT NULL REFERENCES task (id),
    pr_id TEXT NOT NULL REFERENCES pr (id),
    linked_at INTEGER NOT NULL,
    linked_by TEXT NOT NULL CHECK (linked_by IN (${q(PR_LINKED_BY)})),
    PRIMARY KEY (task_id, pr_id)
  ) STRICT;
  CREATE INDEX task_pr_pr ON task_pr (pr_id);

  -- FOUNDER ------------------------------------------------------------------------------------------

  CREATE TABLE question (
    id TEXT PRIMARY KEY ${ulid('id')},
    number INTEGER NOT NULL UNIQUE CHECK (number > 0),
    task_id TEXT REFERENCES task (id),
    asked_by_orc_id TEXT REFERENCES orc (id),
    asked_by_session_id TEXT REFERENCES session (id),
    follows_up_id TEXT REFERENCES question (id),
    kind TEXT NOT NULL CHECK (length(kind) BETWEEN 1 AND 40),
    title TEXT NOT NULL CHECK (length(title) BETWEEN 1 AND 400),
    body TEXT,
    -- Set when the question is added: chat words are never his answer to a passkey question.
    needs_passkey INTEGER NOT NULL DEFAULT 0 ${flag('needs_passkey')},
    asked_at INTEGER NOT NULL,
    decisions_seq INTEGER UNIQUE,
    backfill INTEGER NOT NULL DEFAULT 0 ${flag('backfill')},
    CHECK (task_id IS NOT NULL OR backfill = 1),
    CHECK (follows_up_id IS NULL OR follows_up_id <> id)
  ) STRICT;
  CREATE INDEX question_task ON question (task_id);

  CREATE TABLE question_event (
    id TEXT PRIMARY KEY ${ulid('id')},
    question_id TEXT NOT NULL REFERENCES question (id),
    at INTEGER NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN (${q(QUESTION_EVENT_KINDS)})),
    by_session_id TEXT REFERENCES session (id),
    data_json TEXT CHECK (data_json IS NULL OR json_valid(data_json)),
    decisions_seq INTEGER UNIQUE,
    sha256 TEXT NOT NULL UNIQUE ${sha('sha256')}
  ) STRICT;
  CREATE INDEX question_event_question ON question_event (question_id, at);

  CREATE TABLE answer (
    id TEXT PRIMARY KEY ${ulid('id')},
    question_id TEXT NOT NULL REFERENCES question (id),
    at INTEGER NOT NULL,
    speaker TEXT NOT NULL CHECK (length(speaker) BETWEEN 1 AND 40),
    route TEXT CHECK (length(route) <= 40),
    text TEXT NOT NULL,
    -- A parts question is answered part by part.
    part TEXT CHECK (part GLOB '[A-Z]' AND length(part) = 1),
    -- The passkey credential id that signed it; NULL for chat words.
    signed_by TEXT CHECK (length(signed_by) BETWEEN 1 AND 200),
    wording_version INTEGER CHECK (wording_version >= 1),
    asks INTEGER NOT NULL DEFAULT 0 ${flag('asks')},
    -- Change my answer (decisions PR 335): this answer replaces an earlier one to the same question.
    replaces_answer_id TEXT REFERENCES answer (id),
    decisions_seq INTEGER UNIQUE,
    sha256 TEXT NOT NULL UNIQUE ${sha('sha256')},
    CHECK (replaces_answer_id IS NULL OR replaces_answer_id <> id)
  ) STRICT;
  CREATE INDEX answer_question ON answer (question_id, at);
  CREATE TRIGGER answer_replaces_same_question BEFORE INSERT ON answer
    WHEN NEW.replaces_answer_id IS NOT NULL
      AND (SELECT question_id FROM answer WHERE id = NEW.replaces_answer_id) IS NOT NEW.question_id
  BEGIN SELECT RAISE(ABORT, 'an answer replaces an answer to the same question'); END;

  -- Where an answer was delivered. The seat is resolved from session_one_live_seat, never by label search.
  CREATE TABLE answer_route (
    id TEXT PRIMARY KEY ${ulid('id')},
    answer_id TEXT NOT NULL REFERENCES answer (id),
    at INTEGER NOT NULL,
    seat TEXT NOT NULL CHECK (seat IN ('orc', 'thrall', 'analyst', 'none')),
    session_id TEXT REFERENCES session (id),
    resolved INTEGER NOT NULL ${flag('resolved')},
    reason TEXT CHECK (length(reason) <= 400),
    decisions_seq INTEGER UNIQUE,
    sha256 TEXT NOT NULL UNIQUE ${sha('sha256')},
    CHECK (resolved = 0 OR session_id IS NOT NULL)
  ) STRICT;

  -- Routed is not delivered: a route is taken when the target session's own hook confirms it (TAKEN).
  -- Its own write-once row, because answer_route is append-only; a route with no row here past its
  -- deadline is the alarm (decisions T-0281). When the mail table lands this moves to mail delivery, the
  -- one source for the meter's 'taken' hop too.
  CREATE TABLE answer_route_taken (
    route_id TEXT PRIMARY KEY REFERENCES answer_route (id),
    at INTEGER NOT NULL
  ) STRICT;

  -- The task's history. kind-specific columns are required by CHECKs so a row says everything it means.
  CREATE TABLE task_event (
    id TEXT PRIMARY KEY ${ulid('id')},
    task_id TEXT NOT NULL REFERENCES task (id),
    at INTEGER NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN (${q(TASK_EVENT_KINDS)})),
    by_orc_id TEXT REFERENCES orc (id),
    by_session_id TEXT REFERENCES session (id),
    -- The writer as the ledger spelled it (analyst, analyst-backfill, C13), kept when it names no Orc row.
    by_text TEXT CHECK (length(by_text) <= 64),
    prio INTEGER CHECK (prio BETWEEN 0 AND 9),
    to_orc_id TEXT REFERENCES orc (id),
    on_kind TEXT CHECK (on_kind IN (${q(WAITING_ON)})),
    on_orc_id TEXT REFERENCES orc (id),
    -- What it waits on in words (device, merge, B's usage limit); on_kind is the class.
    on_text TEXT CHECK (length(on_text) <= 400),
    question_id TEXT REFERENCES question (id),
    pr_id TEXT REFERENCES pr (id),
    superseded_by_id TEXT REFERENCES task (id),
    proof TEXT CHECK (length(proof) <= 4000),
    reason TEXT CHECK (length(reason) <= 4000),
    backfill INTEGER NOT NULL DEFAULT 0 ${flag('backfill')},
    sha256 TEXT NOT NULL UNIQUE ${sha('sha256')},
    CHECK (kind NOT IN ('opened', 'priority') OR prio IS NOT NULL),
    CHECK (kind <> 'opened' OR to_orc_id IS NOT NULL OR backfill = 1),
    CHECK (kind <> 'handed' OR to_orc_id IS NOT NULL),
    CHECK (kind <> 'waiting' OR on_kind IS NOT NULL OR backfill = 1),
    CHECK (on_kind IS NULL OR kind = 'waiting'),
    CHECK (on_kind <> 'orc' OR on_orc_id IS NOT NULL OR backfill = 1),
    CHECK (on_kind <> 'founder' OR question_id IS NOT NULL OR backfill = 1),
    CHECK (kind <> 'superseded' OR superseded_by_id IS NOT NULL OR backfill = 1)
  ) STRICT;
  CREATE INDEX task_event_task ON task_event (task_id, at);
  CREATE INDEX task_event_question ON task_event (question_id) WHERE question_id IS NOT NULL;
  CREATE INDEX task_event_pr ON task_event (pr_id) WHERE pr_id IS NOT NULL;

  -- The fleet changelog (PROGRESS.md is rendered from it). legacy_id is the old yyyymmddThhmmssZ-NN id.
  CREATE TABLE changelog_entry (
    id TEXT PRIMARY KEY ${ulid('id')},
    legacy_id TEXT UNIQUE,
    at INTEGER NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN (${q(CHANGELOG_KINDS)})),
    orc_id TEXT REFERENCES orc (id),
    task_id TEXT REFERENCES task (id),
    fleet_wide INTEGER NOT NULL DEFAULT 0 ${flag('fleet_wide')},
    title TEXT NOT NULL CHECK (length(title) BETWEEN 1 AND 400),
    text TEXT NOT NULL,
    corrects_id TEXT REFERENCES changelog_entry (id),
    backfill INTEGER NOT NULL DEFAULT 0 ${flag('backfill')},
    sha256 TEXT NOT NULL UNIQUE ${sha('sha256')},
    CHECK (task_id IS NOT NULL OR fleet_wide = 1 OR backfill = 1),
    CHECK (orc_id IS NOT NULL OR backfill = 1)
  ) STRICT;
  CREATE INDEX changelog_entry_at ON changelog_entry (at);
  CREATE INDEX changelog_entry_task ON changelog_entry (task_id) WHERE task_id IS NOT NULL;

  CREATE TABLE service (
    id TEXT PRIMARY KEY ${ulid('id')},
    name TEXT NOT NULL UNIQUE CHECK (length(name) BETWEEN 1 AND 80),
    kind TEXT NOT NULL CHECK (length(kind) BETWEEN 1 AND 40)
  ) STRICT;

  -- A deploy names the commit it shipped; the PR (and through task_pr the task) is resolved from it.
  CREATE TABLE deploy (
    id TEXT PRIMARY KEY ${ulid('id')},
    service_id TEXT NOT NULL REFERENCES service (id),
    commit_sha TEXT NOT NULL CHECK (length(commit_sha) = 40 AND commit_sha NOT GLOB '*[^0-9a-f]*'),
    pr_id TEXT REFERENCES pr (id),
    at INTEGER NOT NULL,
    verified_at INTEGER,
    sha256 TEXT NOT NULL UNIQUE ${sha('sha256')}
  ) STRICT;
  CREATE INDEX deploy_service ON deploy (service_id, at);

  -- PARKING (shape agreed with lane K, schema/fleet-parking-lot*.v1.json and fleet-wake*.v1.json) -----

  CREATE TABLE parking_lot (
    id TEXT PRIMARY KEY ${ulid('id')},
    created_at INTEGER NOT NULL,
    created_by_session_id TEXT REFERENCES session (id),
    created_by_orc_id TEXT REFERENCES orc (id),
    reason TEXT NOT NULL CHECK (length(reason) BETWEEN 1 AND 200),
    selection_kind TEXT CHECK (selection_kind IN (${q(LOT_SELECTIONS)})),
    legacy_id TEXT UNIQUE
  ) STRICT;

  CREATE TABLE parking_lot_member (
    lot_id TEXT NOT NULL REFERENCES parking_lot (id),
    session_id TEXT NOT NULL REFERENCES session (id),
    orc_id TEXT REFERENCES orc (id),
    tier INTEGER CHECK (tier IN (1, 2)),
    state TEXT NOT NULL CHECK (state IN (${q(MEMBER_STATES)})),
    note TEXT CHECK (length(note) <= 1024),
    PRIMARY KEY (lot_id, session_id)
  ) STRICT;
  CREATE INDEX parking_lot_member_parked ON parking_lot_member (session_id) WHERE state = 'parked';

  CREATE TABLE wake (
    id TEXT PRIMARY KEY ${ulid('id')},
    lot_id TEXT NOT NULL REFERENCES parking_lot (id),
    requested_at INTEGER NOT NULL,
    requested_by_session_id TEXT REFERENCES session (id)
  ) STRICT;

  CREATE TABLE wake_member (
    wake_id TEXT NOT NULL REFERENCES wake (id),
    session_id TEXT NOT NULL REFERENCES session (id),
    outcome TEXT NOT NULL CHECK (outcome IN (${q(WAKE_OUTCOMES)})),
    -- Only when the harness gave the resumed conversation a new id; a woken member may keep its old one.
    new_session_id TEXT REFERENCES session (id),
    PRIMARY KEY (wake_id, session_id)
  ) STRICT;

  -- HISTORY IS APPEND-ONLY --------------------------------------------------------------------------
  ${appendOnly('task_event')}
  ${appendOnly('question_event')}
  ${appendOnly('answer')}
  ${appendOnly('answer_route')}
  ${appendOnly('answer_route_taken')}
  ${appendOnly('changelog_entry')}
  ${appendOnly('deploy')}

  -- DERIVED VIEWS (read these; never store their columns) --------------------------------------------

  -- A task now: state from its last state-changing event, priority from its last opened/priority event,
  -- owner from its last opened/handed event. Ties at one millisecond break on the ULID, which sorts by time.
  CREATE VIEW task_now AS
  SELECT t.id, t.key, t.title, t.source, t.parent_id, t.created_at,
    (SELECT e.kind FROM task_event e WHERE e.task_id = t.id
       AND e.kind NOT IN ('progress', 'priority', 'handed')
       ORDER BY e.at DESC, e.id DESC LIMIT 1) AS state,
    (SELECT e.prio FROM task_event e WHERE e.task_id = t.id AND e.kind IN ('opened', 'priority')
       ORDER BY e.at DESC, e.id DESC LIMIT 1) AS prio,
    (SELECT e.to_orc_id FROM task_event e WHERE e.task_id = t.id AND e.kind IN ('opened', 'handed')
       ORDER BY e.at DESC, e.id DESC LIMIT 1) AS owner_orc_id,
    (SELECT max(e.at) FROM task_event e WHERE e.task_id = t.id) AS last_event_at
  FROM task t;

  -- Each Orc's live seat on each PC (answer routing and mail read this).
  CREATE VIEW orc_seat AS
  SELECT o.id AS orc_id, o.letter, o.lane_dir, s.node_id, s.id AS session_id, s.first_seen
  FROM orc o JOIN session s ON s.orc_id = o.id
  WHERE s.retired_at IS NULL AND s.rank IN ('thrall', 'orc') AND o.retired_at IS NULL;

  -- A question is open unless its last closed/reopened event is a close.
  CREATE VIEW question_now AS
  SELECT qn.id, qn.number, qn.task_id, qn.asked_by_orc_id, qn.title, qn.asked_at,
    CASE (SELECT e.kind FROM question_event e WHERE e.question_id = qn.id
       AND e.kind IN ('closed', 'reopened') ORDER BY e.at DESC, e.id DESC LIMIT 1)
      WHEN 'closed' THEN 'closed' ELSE 'open' END AS state
  FROM question qn;

  -- Whether an answer can be acted on (decisions/Rules.ps1 Test-HordeDecisionMessageAuthorizes): it is his
  -- ANSWER only if the question was open when it arrived, and on a passkey question only if it is signed.
  -- Open-at-arrival is derived, not stored: the close/reopen history is append-only, so it is a fixed fact
  -- as long as writers stamp at with the time they write (the access layer does; only the importer
  -- writes past times, from the source). A close in the same millisecond as the answer counts as before it;
  -- a close and a reopen in one millisecond order by id, which the access layer mints in order.
  CREATE VIEW answer_now AS
  SELECT a.id, a.question_id, a.at, a.part, a.signed_by, a.replaces_answer_id,
    CASE (SELECT e.kind FROM question_event e WHERE e.question_id = a.question_id
       AND e.kind IN ('closed', 'reopened') AND e.at <= a.at ORDER BY e.at DESC, e.id DESC LIMIT 1)
      WHEN 'closed' THEN 0 ELSE 1 END AS open_at_arrival,
    CASE WHEN (SELECT e.kind FROM question_event e WHERE e.question_id = a.question_id
       AND e.kind IN ('closed', 'reopened') AND e.at <= a.at ORDER BY e.at DESC, e.id DESC LIMIT 1) = 'closed' THEN 0
      WHEN qn.needs_passkey = 1 AND a.signed_by IS NULL THEN 0 ELSE 1 END AS authorizes
  FROM answer a JOIN question qn ON qn.id = a.question_id;
  `,

  // 2: what the Progress and Decisions pages show (M's orders of 2026-10-19 and 10-20).
  `
  -- A park that says keep-visible leaves its Orcs on the Progress and Decisions pages; any other park
  -- takes them off. Lot level (agreed with lane K, schema/fleet-parking-lot.v1.json).
  ALTER TABLE parking_lot ADD COLUMN keep_visible INTEGER NOT NULL DEFAULT 0 ${flag('keep_visible')};

  -- Every member still parked, with its lot's keep_visible. A member's own orc_id is the one the park
  -- recorded; a member that has none falls back to its session's.
  CREATE VIEW parked_now AS
  SELECT m.lot_id, m.session_id, coalesce(m.orc_id, s.orc_id) AS orc_id, m.tier, l.keep_visible,
    l.created_at AS parked_at, l.reason
  FROM parking_lot_member m JOIN parking_lot l ON l.id = m.lot_id JOIN session s ON s.id = m.session_id
  WHERE m.state = 'parked';

  -- DECISIONS LISTS ----------------------------------------------------------------------------------

  -- Each list an Orc (or the Thrall, through its orc row) publishes for the founder, whole, as it was.
  -- The live list is the newest snapshot of each Orc (decisions_live); every older one is the archive.
  -- There is no superseded_by column: which snapshot is newest is already a fact of published_at, and a
  -- stored pointer would be a second copy of it. sha256 is of the canonical items (fleet-db/write.mjs,
  -- publishDecisions) and is NOT unique: a list that goes A, B, A records the second A. A publish equal
  -- to the Orc's newest list is refused below, so "unchanged" writes nothing. An empty list is a list.
  CREATE TABLE decisions_snapshot (
    id TEXT PRIMARY KEY ${ulid('id')},
    orc_id TEXT NOT NULL REFERENCES orc (id),
    published_at INTEGER NOT NULL CHECK (published_at >= 0),
    by_session_id TEXT REFERENCES session (id),
    item_count INTEGER NOT NULL CHECK (item_count >= 0),
    sha256 TEXT NOT NULL ${sha('sha256')},
    -- One Orc cannot publish twice in one millisecond, and an import of the same file twice hits this.
    UNIQUE (orc_id, published_at)
  ) STRICT;

  CREATE TRIGGER decisions_snapshot_not_same BEFORE INSERT ON decisions_snapshot
  WHEN NEW.sha256 = (SELECT s.sha256 FROM decisions_snapshot s WHERE s.orc_id = NEW.orc_id
    ORDER BY s.published_at DESC, s.id DESC LIMIT 1)
  BEGIN SELECT RAISE(ABORT, 'decisions_snapshot: same as the live list'); END;

  -- One line of a list. question_id is NULL for an item that is not a numbered question yet.
  CREATE TABLE decisions_snapshot_item (
    snapshot_id TEXT NOT NULL REFERENCES decisions_snapshot (id),
    position INTEGER NOT NULL CHECK (position >= 1),
    question_id TEXT REFERENCES question (id),
    text TEXT NOT NULL CHECK (length(text) BETWEEN 1 AND 400),
    recommendation TEXT CHECK (length(recommendation) <= 400),
    importance TEXT CHECK (length(importance) BETWEEN 1 AND 40),
    blocks TEXT CHECK (length(blocks) <= 400),
    PRIMARY KEY (snapshot_id, position)
  ) STRICT;
  CREATE INDEX decisions_snapshot_item_question ON decisions_snapshot_item (question_id);

  -- Positions run 1..item_count: with the primary key, a list can hold no gap and no extra line. That
  -- every position is present, and that the lines still hash to the snapshot's sha256, is checked by
  -- horde db check, since the items come after their snapshot.
  CREATE TRIGGER decisions_snapshot_item_in_range BEFORE INSERT ON decisions_snapshot_item
  WHEN NEW.position > (SELECT s.item_count FROM decisions_snapshot s WHERE s.id = NEW.snapshot_id)
  BEGIN SELECT RAISE(ABORT, 'decisions_snapshot_item: position beyond the list''s item_count'); END;

  -- Lines go only into the Orc's newest list, as it is published: an older snapshot is the archive and is
  -- frozen, even one left short. An import therefore writes each Orc's lists in time order.
  CREATE TRIGGER decisions_snapshot_item_newest_only BEFORE INSERT ON decisions_snapshot_item
  WHEN NEW.snapshot_id <> (SELECT l.id FROM decisions_live l
    WHERE l.orc_id = (SELECT s.orc_id FROM decisions_snapshot s WHERE s.id = NEW.snapshot_id))
  BEGIN SELECT RAISE(ABORT, 'decisions_snapshot_item: lines go only into the newest list of its Orc'); END;

  ${appendOnly('decisions_snapshot')}
  ${appendOnly('decisions_snapshot_item')}

  -- The newest snapshot of each Orc: the list the Decisions page shows. "Same as the live list" above is
  -- against this one only, so a backdated import equal to an older list is written (the design's A, B, A).
  CREATE VIEW decisions_live AS
  SELECT id, orc_id, published_at, by_session_id, item_count, sha256 FROM (
    SELECT s.*, row_number() OVER (PARTITION BY s.orc_id ORDER BY s.published_at DESC, s.id DESC) AS rn
    FROM decisions_snapshot s)
  WHERE rn = 1;

  CREATE VIEW decisions_live_item AS
  SELECT l.orc_id, l.published_at, i.snapshot_id, i.position, i.question_id, i.text, i.recommendation,
    i.importance, i.blocks
  FROM decisions_live l JOIN decisions_snapshot_item i ON i.snapshot_id = l.id;
  `,

  // 3: the glue (founder, 2026-10-20: every object of the Horde in one database, tagged, linked and
  // sortable, the Thrall with a status of its own, every Orc's tasks a numbered tree).
  `
  -- WHO AND WHERE ----------------------------------------------------------------------------------

  -- A Horde: one Thrall across machines. Every node belongs to one (NULL on a file made before this).
  CREATE TABLE horde (
    id TEXT PRIMARY KEY ${ulid('id')},
    name TEXT NOT NULL UNIQUE CHECK (length(name) BETWEEN 1 AND 64),
    created_at INTEGER NOT NULL
  ) STRICT;
  ALTER TABLE node ADD COLUMN horde_id TEXT REFERENCES horde (id);

  -- A person: the founder and staff. Signs answers, owns subscriptions, asks for tasks.
  CREATE TABLE person (
    id TEXT PRIMARY KEY ${ulid('id')},
    name TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 120),
    role TEXT NOT NULL CHECK (role IN (${q(PERSON_ROLES)})),
    handle TEXT UNIQUE CHECK (length(handle) BETWEEN 1 AND 64 AND handle NOT GLOB '*[^a-z0-9._-]*'),
    created_at INTEGER NOT NULL,
    retired_at INTEGER
  ) STRICT;
  CREATE UNIQUE INDEX person_one_founder ON person (role) WHERE role = 'founder' AND retired_at IS NULL;

  -- The model a session runs (a Warg's is chosen per brief).
  ALTER TABLE session ADD COLUMN model TEXT CHECK (length(model) BETWEEN 1 AND 80);

  -- STATUS ------------------------------------------------------------------------------------------

  -- Each Orc's status, the Thrall's included, history kept. doing and blocked are the only typed words
  -- (the card's 120 characters, plain words); the card's finished and waiting-on lines are derived.
  CREATE TABLE orc_status (
    id TEXT PRIMARY KEY ${ulid('id')},
    orc_id TEXT NOT NULL REFERENCES orc (id),
    session_id TEXT REFERENCES session (id),
    at INTEGER NOT NULL,
    doing TEXT NOT NULL CHECK (length(doing) BETWEEN 1 AND 120),
    blocked TEXT CHECK (length(blocked) BETWEEN 1 AND 200),
    backfill INTEGER NOT NULL DEFAULT 0 ${flag('backfill')},
    sha256 TEXT NOT NULL UNIQUE ${sha('sha256')}
  ) STRICT;
  CREATE INDEX orc_status_orc ON orc_status (orc_id, at);

  -- THE ENTITY REGISTRY -------------------------------------------------------------------------------

  -- One row per object of every main table (ENTITY_TABLES), made, touched and removed with it by
  -- triggers. Tags, links, notifications and created_by point here, so they work for every kind of
  -- object and the database still refuses a pointer to nothing. kind is the table that holds the object.
  CREATE TABLE entity (
    id TEXT PRIMARY KEY,
    kind TEXT NOT NULL CHECK (kind IN (${q(ENTITY_KINDS)})),
    created_at INTEGER NOT NULL,
    created_by_id TEXT REFERENCES entity (id),
    updated_at INTEGER,
    CHECK (created_by_id IS NULL OR created_by_id <> id)
  ) STRICT;
  CREATE INDEX entity_kind ON entity (kind, created_at);
  CREATE INDEX entity_created_by ON entity (created_by_id);
  -- Only who made it and when it last changed may change; what it is and when it began are fixed.
  CREATE TRIGGER entity_fixed BEFORE UPDATE ON entity
  WHEN NEW.id IS NOT OLD.id OR NEW.kind IS NOT OLD.kind OR NEW.created_at IS NOT OLD.created_at
  BEGIN SELECT RAISE(ABORT, 'entity: id, kind and created_at never change'); END;
  ${ENTITY_KINDS.map(entityBackfill).join('\n  ')}
  ${ENTITY_KINDS.map(entityTriggers).join('\n')}

  -- TAGS AND LINKS ---------------------------------------------------------------------------------

  -- A tag is a row, never words inside a field. name is lower case; a colon makes a family (area:relay).
  CREATE TABLE tag (
    id TEXT PRIMARY KEY ${ulid('id')},
    name TEXT NOT NULL UNIQUE CHECK (length(name) BETWEEN 1 AND 64 AND name NOT GLOB '*[^a-z0-9:._-]*'),
    meaning TEXT CHECK (length(meaning) <= 400),
    created_at INTEGER NOT NULL
  ) STRICT;

  CREATE TABLE entity_tag (
    entity_id TEXT NOT NULL REFERENCES entity (id),
    tag_id TEXT NOT NULL REFERENCES tag (id),
    at INTEGER NOT NULL,
    by_entity_id TEXT REFERENCES entity (id),
    PRIMARY KEY (entity_id, tag_id)
  ) STRICT;
  CREATE INDEX entity_tag_tag ON entity_tag (tag_id);

  -- Loose relations between any two objects (task blocks task, question answers task, PR implements task).
  -- Fixed ones stay foreign keys on their tables (a task's parent, a question's task). A link is retired,
  -- not deleted, and one relation between two objects is live at most once.
  CREATE TABLE link (
    id TEXT PRIMARY KEY ${ulid('id')},
    subject_id TEXT NOT NULL REFERENCES entity (id),
    relation TEXT NOT NULL CHECK (relation IN (${q(LINK_RELATIONS)})),
    object_id TEXT NOT NULL REFERENCES entity (id),
    at INTEGER NOT NULL,
    by_entity_id TEXT REFERENCES entity (id),
    retired_at INTEGER,
    CHECK (subject_id <> object_id),
    CHECK (retired_at IS NULL OR retired_at >= at)
  ) STRICT;
  CREATE UNIQUE INDEX link_one_live ON link (subject_id, relation, object_id) WHERE retired_at IS NULL;
  CREATE INDEX link_object ON link (object_id, relation);

  -- THE TASK TREE AND THE PER-TURN CHECK-IN ---------------------------------------------------------

  -- position orders a task among its siblings, and breaks ties of priority in its owner's list; gaps are
  -- fine, since the number shown (3.2.1) is derived by task_tree. due_at: when the task is wanted by.
  ALTER TABLE task ADD COLUMN position INTEGER CHECK (position >= 1);
  ALTER TABLE task ADD COLUMN due_at INTEGER;
  CREATE INDEX task_parent ON task (parent_id, position);
  -- A task cannot sit under its own subtask: the tasks of a loop would have no top and would drop out of
  -- every list unseen. An insert cannot make a loop (nothing points at a new id yet); a move can.
  CREATE TRIGGER task_no_loop BEFORE UPDATE OF parent_id ON task
  WHEN NEW.parent_id IS NOT NULL AND NEW.id IN (
    WITH RECURSIVE up (x) AS (SELECT NEW.parent_id UNION SELECT p.parent_id FROM task p JOIN up ON p.id = up.x WHERE p.parent_id IS NOT NULL)
    SELECT x FROM up)
  BEGIN SELECT RAISE(ABORT, 'task: it cannot sit under its own subtask'); END;

  -- "I looked at my task list this turn": one row per turn that checked in, with the hash of the list it
  -- saw. Lane K's Stop hook reads the newest per session.
  CREATE TABLE task_checkin (
    id TEXT PRIMARY KEY ${ulid('id')},
    session_id TEXT NOT NULL REFERENCES session (id),
    orc_id TEXT REFERENCES orc (id),
    at INTEGER NOT NULL,
    list_sha256 TEXT NOT NULL ${sha('list_sha256')},
    item_count INTEGER NOT NULL CHECK (item_count >= 0)
  ) STRICT;
  CREATE INDEX task_checkin_session ON task_checkin (session_id, at);

  ${appendOnly('orc_status')}
  ${appendOnly('task_checkin')}

  -- Each Orc's current status: its newest row.
  CREATE VIEW status_now AS
  SELECT id, orc_id, session_id, at, doing, blocked FROM (
    SELECT st.*, row_number() OVER (PARTITION BY st.orc_id ORDER BY st.at DESC, st.id DESC) AS rn FROM orc_status st)
  WHERE rn = 1;

  -- Every open task with its number in its owner's list: top tasks by priority, then position, then age;
  -- subtasks by position under their parent, numbered within the parent. A subtask sits in the tree of its
  -- top task's owner; one whose parent is closed leaves the tree with it. sort orders the rows as shown.
  CREATE VIEW task_tree AS
  WITH RECURSIVE live AS (
    SELECT t.id, t.key, t.title, t.parent_id, t.position, t.due_at, t.created_at, n.state, n.prio, n.owner_orc_id
    FROM task t JOIN task_now n ON n.id = t.id
    WHERE n.state IS NULL OR n.state NOT IN ('done', 'verified', 'dropped', 'superseded')),
  sib AS (
    SELECT id, row_number() OVER (PARTITION BY parent_id ORDER BY position IS NULL, position, created_at, id) AS n
    FROM live WHERE parent_id IS NOT NULL),
  top AS (
    SELECT id, row_number() OVER (PARTITION BY owner_orc_id ORDER BY prio IS NULL, prio, position IS NULL, position, created_at, id) AS n
    FROM live WHERE parent_id IS NULL),
  tree (id, owner_orc_id, depth, path, sort) AS (
    SELECT top.id, l.owner_orc_id, 0, CAST(top.n AS TEXT), printf('%06d', top.n)
    FROM top JOIN live l ON l.id = top.id
    UNION ALL
    SELECT c.id, tree.owner_orc_id, tree.depth + 1, tree.path || '.' || sib.n, tree.sort || '.' || printf('%06d', sib.n)
    FROM live c JOIN sib ON sib.id = c.id JOIN tree ON tree.id = c.parent_id)
  SELECT tree.owner_orc_id, tree.path, tree.depth, tree.sort, l.id, l.key, l.title, l.state, l.prio, l.due_at
  FROM tree JOIN live l ON l.id = tree.id;
  `,

  // 4: what the decisions store holds that migrations 1-3 had no place for (phase 1c part 2a, the importer).
  // question: the words of a question beyond its title (body is its whatItIs), the asker as written when
  // it names no Orc, the group, and the two ranking words as first asked; the lists (options, parts,
  // waiting, files, references) stay one canonical JSON text, since nothing queries inside them.
  // The side tables are write-once rows beside the hashed history tables, as answer_route_taken is, so
  // answer and answer_route keep their columns and their hashes.
  `
  ALTER TABLE question ADD COLUMN asked_by_text TEXT CHECK (length(asked_by_text) <= 4000);
  ALTER TABLE question ADD COLUMN yes_means TEXT;
  ALTER TABLE question ADD COLUMN recommendation TEXT;
  ALTER TABLE question ADD COLUMN group_name TEXT CHECK (length(group_name) <= 400);
  ALTER TABLE question ADD COLUMN group_note TEXT;
  ALTER TABLE question ADD COLUMN importance TEXT CHECK (length(importance) <= 40);
  ALTER TABLE question ADD COLUMN blocks TEXT CHECK (length(blocks) <= 40);
  ALTER TABLE question ADD COLUMN detail_json TEXT CHECK (detail_json IS NULL OR json_valid(detail_json));

  -- What an answer carries besides its columns. The evidence and the passkey id are signing material:
  -- only that evidence was there is kept (answer.signed_by holds a sha256 of the key id, never the id).
  CREATE TABLE answer_extra (
    answer_id TEXT PRIMARY KEY REFERENCES answer (id),
    evidence_present INTEGER NOT NULL ${flag('evidence_present')},
    act TEXT CHECK (length(act) <= 200),
    recorded_by TEXT NOT NULL CHECK (length(recorded_by) BETWEEN 1 AND 40)
  ) STRICT;
  ${appendOnly('answer_extra')}

  -- What a route carries besides its columns. source_resolved is what the decisions store said; the route's
  -- own resolved is 1 only when its session is a row here (the CHECK on answer_route).
  CREATE TABLE answer_route_extra (
    route_id TEXT PRIMARY KEY REFERENCES answer_route (id),
    purpose TEXT NOT NULL CHECK (length(purpose) BETWEEN 1 AND 40),
    label TEXT CHECK (length(label) <= 40),
    notice TEXT CHECK (length(notice) <= 80),
    analyst TEXT CHECK (length(analyst) <= 4000),
    note TEXT CHECK (length(note) <= 4000),
    source_resolved INTEGER NOT NULL ${flag('source_resolved')}
  ) STRICT;
  ${appendOnly('answer_route_extra')}

  -- A reader has read the decisions store up to a record (messages-read). Keyed by the record's own
  -- sequence, so the same record imported twice is one row.
  CREATE TABLE decisions_read (
    id TEXT PRIMARY KEY ${ulid('id')},
    reader TEXT NOT NULL CHECK (length(reader) BETWEEN 1 AND 40),
    up_to_seq INTEGER NOT NULL CHECK (up_to_seq >= 1),
    at INTEGER NOT NULL,
    decisions_seq INTEGER NOT NULL UNIQUE
  ) STRICT;
  ${appendOnly('decisions_read')}

  -- An acknowledgement closes the question it names (decisions/Rules.ps1 Step-HordeDecisionAcked: the Orc that
  -- asked has the answer). So 'acked' counts with 'closed' in both views; no closed event is made up for it.
  DROP VIEW answer_now;
  DROP VIEW question_now;
  CREATE VIEW question_now AS
  SELECT qn.id, qn.number, qn.task_id, qn.asked_by_orc_id, qn.title, qn.asked_at,
    CASE (SELECT e.kind FROM question_event e WHERE e.question_id = qn.id
       AND e.kind IN ('closed', 'reopened', 'acked') ORDER BY e.at DESC, e.id DESC LIMIT 1)
      WHEN 'closed' THEN 'closed' WHEN 'acked' THEN 'closed' ELSE 'open' END AS state
  FROM question qn;
  CREATE VIEW answer_now AS
  SELECT a.id, a.question_id, a.at, a.part, a.signed_by, a.replaces_answer_id,
    CASE WHEN (SELECT e.kind FROM question_event e WHERE e.question_id = a.question_id
       AND e.kind IN ('closed', 'reopened', 'acked') AND e.at <= a.at ORDER BY e.at DESC, e.id DESC LIMIT 1) IN ('closed', 'acked') THEN 0 ELSE 1 END AS open_at_arrival,
    CASE WHEN (SELECT e.kind FROM question_event e WHERE e.question_id = a.question_id
       AND e.kind IN ('closed', 'reopened', 'acked') AND e.at <= a.at ORDER BY e.at DESC, e.id DESC LIMIT 1) IN ('closed', 'acked') THEN 0
      WHEN a.signed_by IS NULL AND qn.needs_passkey = 1 THEN 0 ELSE 1 END AS authorizes
  FROM answer a JOIN question qn ON qn.id = a.question_id;
  `,

  // 5: decisions_confirm (T-0299): an Orc that publishes a list equal to its live one still leaves a record.
  `
  -- A confirm: the Orc published its list again and it was still the same (or it was just published).
  -- decisions publish with a list equal to the live one writes no snapshot (decisions_snapshot_not_same),
  -- so this is the only record that the Orc looked at its list again. Append-only, like the snapshots.
  CREATE TABLE decisions_confirm (
    id TEXT PRIMARY KEY ${ulid('id')},
    orc_id TEXT NOT NULL REFERENCES orc (id),
    snapshot_id TEXT NOT NULL REFERENCES decisions_snapshot (id),
    session_id TEXT REFERENCES session (id),
    confirmed_at INTEGER NOT NULL CHECK (confirmed_at >= 0),
    UNIQUE (snapshot_id, confirmed_at)
  ) STRICT;
  CREATE INDEX decisions_confirm_orc_time ON decisions_confirm (orc_id, confirmed_at);

  -- A confirm is of the Orc's own live list, at insert time, and never before that list was published.
  CREATE TRIGGER decisions_confirm_own_live BEFORE INSERT ON decisions_confirm
  WHEN NEW.snapshot_id IS NOT (SELECT l.id FROM decisions_live l WHERE l.orc_id = NEW.orc_id)
  BEGIN SELECT RAISE(ABORT, 'decisions_confirm: not the live list of this Orc'); END;
  CREATE TRIGGER decisions_confirm_not_early BEFORE INSERT ON decisions_confirm
  WHEN NEW.confirmed_at < (SELECT s.published_at FROM decisions_snapshot s WHERE s.id = NEW.snapshot_id)
  BEGIN SELECT RAISE(ABORT, 'decisions_confirm: before the list was published'); END;
  ${appendOnly('decisions_confirm')}

  -- decisions_live gains confirmed_at: the latest confirm of the live list, else its published_at, so
  -- confirmed_at >= published_at always. Every old column stays.
  DROP VIEW decisions_live_item;
  DROP VIEW decisions_live;
  CREATE VIEW decisions_live AS
  SELECT id, orc_id, published_at, by_session_id, item_count, sha256,
    max(published_at, COALESCE((SELECT max(c.confirmed_at) FROM decisions_confirm c WHERE c.snapshot_id = t.id), 0)) AS confirmed_at
  FROM (
    SELECT x.*, row_number() OVER (PARTITION BY x.orc_id ORDER BY x.published_at DESC, x.id DESC) AS rn
    FROM decisions_snapshot x) t
  WHERE rn = 1;
  CREATE VIEW decisions_live_item AS
  SELECT l.orc_id, l.published_at, i.snapshot_id, i.position, i.question_id, i.text, i.recommendation,
    i.importance, i.blocks
  FROM decisions_live l JOIN decisions_snapshot_item i ON i.snapshot_id = l.id;
  `,

  // 6: work_unit (T-0299, founder ruling 2026-10-21): an AGENT (an Agent-tool subagent inside a session, no
  // window of its own) and a WARG (its own agent session in its own pane) recorded as what they are.
  `
  -- One row per unit of delegated work. The spawning session is the parent either way. An agent is named
  -- by the harness's subagent id, exactly as given (the id in its transcript's file name: the fleet meter
  -- joins on it, so it is never trimmed, lower-cased or reformatted: only its length and ASCII are
  -- checked); a warg is a session of its own. The meter reads this table by ATTACH, read-only, and keeps
  -- every token figure in its own database: nothing of the meter is copied here.
  CREATE TABLE work_unit (
    id TEXT PRIMARY KEY ${ulid('id')},
    kind TEXT NOT NULL CHECK (kind IN (${q(WORK_KINDS)})),
    parent_session_id TEXT NOT NULL REFERENCES session (id),
    orc_id TEXT REFERENCES orc (id),
    agent_id TEXT CHECK (length(agent_id) BETWEEN 1 AND 200 AND agent_id NOT GLOB '*[^!-~]*'),
    agent_type TEXT CHECK (length(agent_type) BETWEEN 1 AND 80 AND agent_type NOT GLOB '*[^!-~]*'),
    session_id TEXT REFERENCES session (id),
    -- Exactly one of a task and a flag. no_task: the brief named no task (counted and nagged); backfill:
    -- a unit recorded after the fact. They are kept apart on purpose.
    task_id TEXT REFERENCES task (id),
    task_flag TEXT CHECK (task_flag IN (${q(WORK_TASK_FLAGS)})),
    work_type TEXT NOT NULL CHECK (work_type IN (${q(WORK_TYPES)})),
    domain TEXT CHECK (length(domain) BETWEEN 1 AND 120),
    model TEXT CHECK (length(model) BETWEEN 1 AND 80),
    started_at INTEGER NOT NULL CHECK (started_at >= 0),
    ended_at INTEGER,
    outcome TEXT NOT NULL CHECK (outcome IN (${q(WORK_OUTCOMES)})),
    UNIQUE (parent_session_id, agent_id),
    UNIQUE (session_id),
    CHECK (kind <> 'agent' OR (agent_id IS NOT NULL AND session_id IS NULL)),
    CHECK (kind <> 'warg' OR (session_id IS NOT NULL AND agent_id IS NULL AND agent_type IS NULL)),
    CHECK (session_id IS NULL OR session_id <> parent_session_id),
    CHECK ((task_id IS NOT NULL) <> (task_flag IS NOT NULL)),
    CHECK ((outcome = 'running') = (ended_at IS NULL)),
    CHECK (ended_at IS NULL OR ended_at >= started_at)
  ) STRICT;
  CREATE INDEX work_unit_orc ON work_unit (orc_id, started_at);
  CREATE INDEX work_unit_task ON work_unit (task_id);
  CREATE INDEX work_unit_running ON work_unit (outcome) WHERE outcome = 'running';

  -- Who and when it began never change: every pointer to the unit, and the meter's join, rest on them.
  CREATE TRIGGER work_unit_identity_fixed BEFORE UPDATE ON work_unit
  WHEN NEW.id IS NOT OLD.id OR NEW.kind IS NOT OLD.kind OR NEW.parent_session_id IS NOT OLD.parent_session_id
    OR NEW.agent_id IS NOT OLD.agent_id OR NEW.session_id IS NOT OLD.session_id OR NEW.started_at IS NOT OLD.started_at
  BEGIN SELECT RAISE(ABORT, 'work_unit: id, kind, parent, agent_id, session_id and started_at never change'); END;

  -- A unit leaves running once. An ended unit keeps its end and its outcome, so it never goes back to
  -- running and never ends a second way.
  CREATE TRIGGER work_unit_end_is_final BEFORE UPDATE ON work_unit
  WHEN OLD.outcome <> 'running' AND (NEW.outcome IS NOT OLD.outcome OR NEW.ended_at IS NOT OLD.ended_at)
  BEGIN SELECT RAISE(ABORT, 'work_unit: an ended unit keeps its end and its outcome'); END;

  -- A unit that named no task may be given one later (the flag is then cleared). A task once set never
  -- changes, and a backfill unit stays as it is.
  CREATE TRIGGER work_unit_task_fill_only BEFORE UPDATE ON work_unit
  WHEN (NEW.task_id IS NOT OLD.task_id AND NOT (OLD.task_id IS NULL AND OLD.task_flag = 'no_task'))
    OR (NEW.task_id IS OLD.task_id AND NEW.task_flag IS NOT OLD.task_flag)
  BEGIN SELECT RAISE(ABORT, 'work_unit: a task is filled only into a no_task unit and never changes'); END;

  CREATE TRIGGER work_unit_no_delete BEFORE DELETE ON work_unit
  BEGIN SELECT RAISE(ABORT, 'work_unit: a unit is never deleted'); END;
  `,
  // 7: session state, kept current by the sessions step of `horde db sync` (T-0409, piece 2 of T-0299; design: planning/
  // fleet-db-design.md, "Keeping the file-fed tables current"). One writer (the sync), many readers: the overseer and the
  // analyst read these columns instead of each judging every transcript on its own. All nullable: NULL is "not read yet".
  // The times are the transcript RECORDS' own timestamps (UTC ms), never a file's modified time, which moves with mode and
  // hook lines and no work. No stall is judged here (no threshold): a reader compares last_activity_at with its own clock.
  //   last_activity_at   newest timestamped turn record of the session, its subagents' records folded in
  //   last_assistant_at  newest assistant record
  //   in_turn            1 while a turn is open (a prompt or tool result nobody has answered)
  //   waits_person       1 when the open turn's last tool call asks a person (a plan to approve, a question)
  //   state              live | idle | waiting-person | dead. 'waiting-job' is RESERVED for piece 3 and is never set here.
  //   state_checked_at   when the sync last judged the state: a reader that sees an old value knows the sync was blind
  //   transcript_offset  bytes of the transcript already read, always at a line end; the next read starts there
  `
  ALTER TABLE session ADD COLUMN last_activity_at INTEGER CHECK (last_activity_at >= 0);
  ALTER TABLE session ADD COLUMN last_assistant_at INTEGER CHECK (last_assistant_at >= 0);
  ALTER TABLE session ADD COLUMN in_turn INTEGER ${flag('in_turn')};
  ALTER TABLE session ADD COLUMN waits_person INTEGER ${flag('waits_person')};
  ALTER TABLE session ADD COLUMN state TEXT CHECK (state IN ('live', 'idle', 'waiting-person', 'waiting-job', 'dead'));
  ALTER TABLE session ADD COLUMN state_checked_at INTEGER CHECK (state_checked_at >= 0);
  ALTER TABLE session ADD COLUMN transcript_offset INTEGER CHECK (transcript_offset >= 0);
  `,
  // 8: job and signal (T-0412, piece 3 of T-0299; design: planning/fleet-db-design.md, "Jobs and signals"). What the overseer
  // kept in jobs.json and signals.jsonl moves here, so the overseer and the analyst detect a stall once, from one place. The
  // overseer writes only through `horde job` and `horde signal` (fleet-db/jobs.mjs); Orc N stays the only schema owner.
  // NO ENTITY ROW for either table, on purpose: an entity row is the registry of objects with a ULID or uuid of their own that
  // links and the phone's lists point at, and both tables are keyed by a text the overseer chose (a job id, a signal key) that
  // nothing else in the database points at. Registering them would need a made-up second id per row for no reader.
  // NO FOREIGN KEY from job.session_id to session: a job may name a session fleet.db has not seen yet (the importer and the
  // sync lag the live fleet), and a refused job would be a job nobody watches. The shape (a lower-case uuid) is still checked.
  // Neither table has a file behind it: fleet.db is their only home, so a backup of the file is their backup.
  `
  -- A piece of promised work somebody is on. Open while done_at is NULL. due_at is optional: a job with no due time is
  -- never overdue, but it is still listed. done_proof is what shows it is done (a PR, a path, a line) and done_by who closed it (both set
  -- exactly when done_at is); a job is never
  -- closed without one.
  CREATE TABLE job (
    id TEXT NOT NULL PRIMARY KEY CHECK (length(id) BETWEEN 1 AND 120 AND id NOT GLOB '*[^!-~]*'),
    owner TEXT NOT NULL CHECK (length(owner) BETWEEN 1 AND 64 AND owner NOT GLOB '*[^!-~]*'),
    session_id TEXT ${uuid('session_id')},
    job TEXT NOT NULL CHECK (length(job) BETWEEN 1 AND 4000),
    started_at INTEGER NOT NULL,
    due_at INTEGER CHECK (due_at >= 0),
    done_at INTEGER CHECK (done_at >= 0),
    done_proof TEXT CHECK (length(done_proof) BETWEEN 1 AND 4000),
    done_by TEXT CHECK (length(done_by) BETWEEN 1 AND 64 AND done_by NOT GLOB '*[^!-~]*'),
    -- Someone else is holding it up (the overseer does not nag an owner whose job waits on another: its IDLE-OPEN-JOB rule skips it).
    waiting_on TEXT CHECK (length(waiting_on) BETWEEN 1 AND 4000),
    created_by TEXT NOT NULL CHECK (length(created_by) BETWEEN 1 AND 64 AND created_by NOT GLOB '*[^!-~]*'),
    CHECK (started_at >= 0),
    CHECK (done_at IS NULL OR done_at >= started_at),
    CHECK ((done_at IS NULL) = (done_proof IS NULL)),
    CHECK ((done_at IS NULL) = (done_by IS NULL))
  ) STRICT;
  -- What the overseer reads: the open jobs, soonest due first (NULLs, which have no due time, sort first and are skipped).
  CREATE INDEX job_open_due ON job (due_at) WHERE done_at IS NULL;

  -- The first time a job was started, who made it, and what it is called never change; a done job keeps its time and proof.
  CREATE TRIGGER job_identity_fixed BEFORE UPDATE ON job
  WHEN NEW.id IS NOT OLD.id OR NEW.started_at IS NOT OLD.started_at OR NEW.created_by IS NOT OLD.created_by
  BEGIN SELECT RAISE(ABORT, 'job: id, started_at and created_by never change'); END;
  CREATE TRIGGER job_done_is_final BEFORE UPDATE ON job
  WHEN OLD.done_at IS NOT NULL
  BEGIN SELECT RAISE(ABORT, 'job: a done job is final'); END;

  -- A problem the overseer saw, one row per key. A key seen again is the same problem: last_at moves forward and count
  -- grows. A closed one raised again is reopened (closed_at and closed_by cleared), so a problem that came back wakes
  -- the overseer again. woke_at is the time the overseer last TRIED to wake someone about it (it backs off from it);
  -- woke_ok_at is the last wake the overseer CONFIRMED worked, so a wake that failed stays unwoken and is retried.
  -- urgent skips the overseer's one-hour gap between wakes; quiet logs the signal and wakes nobody. A reopen clears both
  -- wake times: a problem that came back needs a new wake. owner is a person or a path as the overseer writes it, so it
  -- may hold spaces (one printable ASCII line, up to 120).
  CREATE TABLE signal (
    key TEXT NOT NULL PRIMARY KEY CHECK (length(key) BETWEEN 1 AND 200 AND key NOT GLOB '*[^!-~]*'),
    kind TEXT NOT NULL CHECK (length(kind) BETWEEN 1 AND 64 AND kind NOT GLOB '*[^!-~]*'),
    owner TEXT CHECK (length(owner) BETWEEN 1 AND 120 AND owner NOT GLOB '*[^ -~]*'),
    text TEXT NOT NULL CHECK (length(text) BETWEEN 1 AND 4000),
    first_at INTEGER NOT NULL CHECK (first_at >= 0),
    last_at INTEGER NOT NULL,
    count INTEGER NOT NULL CHECK (count >= 1),
    woke_at INTEGER CHECK (woke_at >= 0),
    woke_ok_at INTEGER CHECK (woke_ok_at >= 0),
    urgent INTEGER NOT NULL DEFAULT 0 ${flag('urgent')},
    quiet INTEGER NOT NULL DEFAULT 0 ${flag('quiet')},
    closed_at INTEGER CHECK (closed_at >= 0),
    closed_by TEXT CHECK (length(closed_by) BETWEEN 1 AND 64 AND closed_by NOT GLOB '*[^!-~]*'),
    CHECK (last_at >= first_at),
    CHECK ((closed_at IS NULL) = (closed_by IS NULL))
  ) STRICT;
  -- What is read: the open signals by when they last happened, and the closed ones by when they closed (the prune).
  CREATE INDEX signal_open_last ON signal (last_at) WHERE closed_at IS NULL;
  CREATE INDEX signal_closed ON signal (closed_at) WHERE closed_at IS NOT NULL;

  -- A signal's key, kind and first time never change, and its last time and count never go back.
  CREATE TRIGGER signal_identity_fixed BEFORE UPDATE ON signal
  WHEN NEW.key IS NOT OLD.key OR NEW.kind IS NOT OLD.kind OR NEW.first_at IS NOT OLD.first_at
  BEGIN SELECT RAISE(ABORT, 'signal: key, kind and first_at never change'); END;
  CREATE TRIGGER signal_never_back BEFORE UPDATE ON signal
  WHEN NEW.last_at < OLD.last_at OR NEW.count < OLD.count
  BEGIN SELECT RAISE(ABORT, 'signal: last_at and count never go back'); END;
  `,

  // 9: task_now by the ledger's own rule (T-0299; design: planning/fleet-db-design.md, "Task state"). The view of migration 1 took
  // the newest event's word as the state, and disagreed with task.py on 31 of 415 real tasks: T-0299 itself read opened. Now: the
  // opened line counts first whatever its time, so a late one takes neither priority nor owner; resumed and reopened read started;
  // handed reads opened, since the new owner has not begun; progress on an opened task means it began. task_tree: a closed parent
  // took its live subtasks off the list with it, 21 of 128 live tasks on the real data, four at priority 1. A live task whose parent
  // is closed now stands at the top of its own owner's list. Only views change, so no row moves.
  `
  DROP VIEW task_now;
  CREATE VIEW task_now AS
  SELECT t.id, t.key, t.title, t.source, t.parent_id, t.created_at,
    CASE
      WHEN m.kind IN ('resumed', 'reopened') THEN 'started'
      WHEN m.kind IS NOT NULL AND m.kind <> 'handed' THEN m.kind
      WHEN NOT EXISTS (SELECT 1 FROM task_event e WHERE e.task_id = t.id) THEN NULL
      WHEN EXISTS (SELECT 1 FROM task_event p WHERE p.task_id = t.id AND p.kind = 'progress'
        AND (m.id IS NULL OR p.at > m.at OR (p.at = m.at AND p.id > m.id))) THEN 'started'
      ELSE 'opened'
    END AS state,
    (SELECT e.prio FROM task_event e WHERE e.task_id = t.id AND e.kind IN ('opened', 'priority')
       ORDER BY e.kind = 'opened', e.at DESC, e.id DESC LIMIT 1) AS prio,
    (SELECT e.to_orc_id FROM task_event e WHERE e.task_id = t.id AND e.kind IN ('opened', 'handed')
       ORDER BY e.kind = 'opened', e.at DESC, e.id DESC LIMIT 1) AS owner_orc_id,
    (SELECT max(e.at) FROM task_event e WHERE e.task_id = t.id) AS last_event_at
  FROM task t
  LEFT JOIN task_event m ON m.id = (SELECT e.id FROM task_event e WHERE e.task_id = t.id
    AND e.kind IN ('started', 'waiting', 'resumed', 'handed', 'done', 'verified', 'reopened', 'dropped', 'superseded')
    ORDER BY e.at DESC, e.id DESC LIMIT 1);
  DROP VIEW task_tree;
  CREATE VIEW task_tree AS
  WITH RECURSIVE live AS (
    SELECT t.id, t.key, t.title, t.parent_id, t.position, t.due_at, t.created_at, n.state, n.prio, n.owner_orc_id
    FROM task t JOIN task_now n ON n.id = t.id
    WHERE n.state NOT IN ('done', 'verified', 'dropped', 'superseded') OR n.state IS NULL),
  sib AS (
    SELECT x.id, row_number() OVER (PARTITION BY x.parent_id ORDER BY x.position IS NULL, x.position, x.created_at, x.id) AS n
    FROM live x WHERE x.parent_id IS NOT NULL),
  top AS (
    SELECT x.id, row_number() OVER (PARTITION BY x.owner_orc_id ORDER BY x.prio IS NULL, x.prio, x.position IS NULL, x.position, x.created_at, x.id) AS n
    FROM live x WHERE x.parent_id IS NULL OR x.parent_id NOT IN (SELECT id FROM live)),
  tree (id, owner_orc_id, depth, path, sort) AS (
    SELECT top.id, l.owner_orc_id, 0, CAST(top.n AS TEXT), printf('%06d', top.n)
    FROM top JOIN live l ON l.id = top.id
    UNION ALL
    SELECT c.id, tree.owner_orc_id, tree.depth + 1, tree.path || '.' || s.n, tree.sort || '.' || printf('%06d', s.n)
    FROM live c JOIN sib s ON s.id = c.id JOIN tree ON tree.id = c.parent_id)
  SELECT tree.owner_orc_id, tree.path, tree.depth, tree.sort, l.id, l.key, l.title, l.state, l.prio, l.due_at
  FROM tree JOIN live l ON l.id = tree.id;
  `,

  // 10: what task_event has no place for (T-0416, T-0417; design: planning/fleet-db-design.md, "Lines task_event has no place for").
  // A promise or a kept line: neither kind is allowed there. A hand-over to no Orc row: task_event requires an Orc. A side table and
  // not a new column, because appendHistory hashes every column of a table: a new column would change the hash of each line, and
  // the next sync would write every event again. task_now reads the table, so state and owner follow task.py: a hand-over to no Orc
  // row means nobody has begun, and the owner is no Orc, unless the line names nobody, which leaves the owner as it was.
  // task_promise_open (Orc M, 2026-11-06). A promise's id is its number on its task, P1, P2, counted by order in the ledger file:
  // short to type, and the file is append-only, so it never changes. A kept may name the promise it closes (closes_no) and a promise
  // the one it replaces (replaces_no); a promise so named reads closed. A kept naming nothing closes the oldest still open that
  // nobody named. A promise wrongly closed vanishes and nobody chases it; one wrongly left open is seen and costs a line. Old lines
  // name nothing and nothing is guessed, so an old re-date reads open: task_state and later_promises show that at a glance.
  `
  CREATE TABLE task_event_extra (
    id TEXT PRIMARY KEY ${ulid('id')},
    task_id TEXT NOT NULL REFERENCES task (id),
    at INTEGER NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('promise', 'kept', 'handed')),
    by_orc_id TEXT REFERENCES orc (id),
    by_text TEXT CHECK (length(by_text) <= 64),
    due_at INTEGER,
    promise_no INTEGER CHECK (promise_no >= 1),
    replaces_no INTEGER CHECK (replaces_no >= 1),
    closes_no INTEGER CHECK (closes_no >= 1),
    to_text TEXT CHECK (length(to_text) <= 120),
    proof TEXT CHECK (length(proof) <= 4000),
    reason TEXT CHECK (length(reason) <= 4000),
    backfill INTEGER NOT NULL DEFAULT 0 ${flag('backfill')},
    sha256 TEXT NOT NULL UNIQUE ${sha('sha256')},
    CHECK (due_at IS NULL OR kind = 'promise'),
    CHECK ((promise_no IS NOT NULL) = (kind = 'promise')),
    CHECK (replaces_no IS NULL OR kind = 'promise'),
    CHECK (closes_no IS NULL OR kind = 'kept'),
    CHECK (kind <> 'promise' OR due_at IS NOT NULL OR backfill = 1),
    CHECK (to_text IS NULL OR kind = 'handed')
  ) STRICT;
  CREATE INDEX task_event_extra_task ON task_event_extra (task_id, kind, at);
  CREATE UNIQUE INDEX task_event_extra_promise ON task_event_extra (task_id, promise_no) WHERE promise_no IS NOT NULL;
  ${appendOnly('task_event_extra')}

  CREATE VIEW task_promise_open AS
  WITH RECURSIVE named (task_id, no) AS (
    SELECT c.task_id, c.closes_no FROM task_event_extra c WHERE c.closes_no IS NOT NULL
    UNION SELECT r.task_id, r.replaces_no FROM task_event_extra r WHERE r.replaces_no IS NOT NULL),
  line AS (
    SELECT x.task_id, x.kind, row_number() OVER (PARTITION BY x.task_id ORDER BY x.at, x.id) AS n
    FROM task_event_extra x
    WHERE (x.kind = 'kept' AND x.closes_no IS NULL)
      OR (x.kind = 'promise' AND NOT EXISTS (SELECT 1 FROM named a WHERE a.task_id = x.task_id AND a.no = x.promise_no))),
  walk (task_id, n, promised, closed) AS (
    SELECT l.task_id, 1, l.kind = 'promise', 0 FROM line l WHERE l.n = 1
    UNION ALL
    SELECT w.task_id, l.n, w.promised + (l.kind = 'promise'), w.closed + (l.kind = 'kept' AND w.closed < w.promised)
    FROM walk w JOIN line l ON l.task_id = w.task_id AND l.n = w.n + 1),
  closed AS (SELECT task_id, max(closed) AS n FROM walk GROUP BY task_id),
  numbered AS (
    SELECT p.*, row_number() OVER (PARTITION BY p.task_id ORDER BY p.at, p.id) AS i, count(*) OVER (PARTITION BY p.task_id) AS total
    FROM task_event_extra p WHERE p.kind = 'promise'
      AND NOT EXISTS (SELECT 1 FROM named b WHERE b.task_id = p.task_id AND b.no = p.promise_no))
  SELECT p.id, p.task_id, t.key, t.title, s.state AS task_state, p.promise_no, p.at, p.due_at, p.by_orc_id, p.by_text, p.reason, p.total - p.i AS later_promises
  FROM numbered p JOIN closed c ON c.task_id = p.task_id JOIN task t ON t.id = p.task_id JOIN task_now s ON s.id = p.task_id
  WHERE p.i > c.n;

  DROP VIEW task_now;
  CREATE VIEW task_now AS
  SELECT t.id, t.key, t.title, t.source, t.parent_id, t.created_at,
    CASE
      WHEN hx.id IS NOT NULL AND EXISTS (SELECT 1 FROM task_event qg WHERE qg.task_id = t.id AND qg.kind = 'progress'
        AND (qg.at > hx.at OR (qg.at = hx.at AND qg.id > hx.id))) THEN 'started'
      WHEN hx.id IS NOT NULL THEN 'opened'
      WHEN mv.kind IN ('resumed', 'reopened') THEN 'started'
      WHEN mv.kind IS NOT NULL AND mv.kind <> 'handed' THEN mv.kind
      WHEN NOT EXISTS (SELECT 1 FROM task_event ev WHERE ev.task_id = t.id) THEN NULL
      WHEN EXISTS (SELECT 1 FROM task_event pg WHERE pg.task_id = t.id AND pg.kind = 'progress'
        AND (mv.id IS NULL OR pg.at > mv.at OR (pg.at = mv.at AND pg.id > mv.id))) THEN 'started'
      ELSE 'opened'
    END AS state,
    (SELECT ev.prio FROM task_event ev WHERE ev.task_id = t.id AND ev.kind IN ('opened', 'priority')
       ORDER BY ev.kind = 'opened', ev.at DESC, ev.id DESC LIMIT 1) AS prio,
    CASE WHEN EXISTS (SELECT 1 FROM task_event_extra ox WHERE ox.task_id = t.id AND ox.kind = 'handed' AND ox.to_text IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM task_event ol WHERE ol.task_id = t.id AND ol.kind = 'handed' AND (ol.at > ox.at OR (ol.at = ox.at AND ol.id > ox.id)))) THEN NULL
      ELSE (SELECT ev.to_orc_id FROM task_event ev WHERE ev.task_id = t.id AND ev.kind IN ('opened', 'handed')
       ORDER BY ev.kind = 'opened', ev.at DESC, ev.id DESC LIMIT 1) END AS owner_orc_id,
    (SELECT max(ev.at) FROM task_event ev WHERE ev.task_id = t.id) AS last_event_at
  FROM task t
  LEFT JOIN task_event mv ON mv.id = (SELECT ev.id FROM task_event ev WHERE ev.task_id = t.id
    AND ev.kind IN ('started', 'waiting', 'resumed', 'handed', 'done', 'verified', 'reopened', 'dropped', 'superseded')
    ORDER BY ev.at DESC, ev.id DESC LIMIT 1)
  LEFT JOIN task_event_extra hx ON hx.id = (SELECT y.id FROM task_event_extra y WHERE y.task_id = t.id AND y.kind = 'handed'
    ORDER BY y.at DESC, y.id DESC LIMIT 1)
    AND (mv.id IS NULL OR hx.at > mv.at OR (hx.at = mv.at AND hx.id > mv.id));
  `,
];

export const SCHEMA_VERSION = MIGRATIONS.length;
