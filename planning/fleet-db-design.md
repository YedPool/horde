# fleet.db - one source of truth for the fleet's work data

Lane N, task T-0299, 2026-10-19. Input: the work-data SSOT audit of 2026-10-19
(`.wezfleet/_home/orcs/research/work-data-ssot-audit-2026-10-19.html`), which found about 15 stores
retyping each other. Founder: "Make sure that all of our data is stored in a properly hashed, SSOT db
with correct efficient and proper unique ids and relational structure." DDL: `fleet-db/schema.mjs`.

## Decisions

1. **One SQLite file, `<HORDE_HOME>\fleet.db`, through `node:sqlite`.** Every writer is a local process
   (hooks, CLIs, the analyst, tend); SQLite gives transactions and unique keys with no server and keeps
   working when the network is down. Node 24's built-in driver is what the fleet meter
   (`fleet-metrics/store.mjs`) chose, so the fleet has one engine, one set of pragmas (WAL,
   busy_timeout 5000, foreign_keys checked on every open) and one migration rule (`user_version`,
   append-only migrations). The relay was rejected as the source (it would put every hook behind a
   network call); per-record JSON folders were rejected (no uniqueness or foreign keys across files).
2. **Ids.** Every row has a ULID primary key (time-sortable, unique across PCs), except where the thing
   already has a globally unique id: a session is its harness session uuid. Human labels stay as UNIQUE
   columns, never keys: `task.key` T-NNNN, `question.number`, `orc.letter`, `orc.lane_dir`,
   `pr (repo, number)`. A label can then be corrected without touching the rows that point at it.
3. **Labels are allocated under a lock.** `label_seq` is incremented inside `BEGIN IMMEDIATE`, in the
   same transaction as the insert, so two sessions never take the same T-number and a failed insert
   hands its number back (audit E8: task.py's max+1 had no lock).
4. **State rows and history rows.** `orc`, `session`, `pane`, `pr`, `parking_lot_member` are state,
   updated in place. `task_event`, `question_event`, `answer`, `answer_route`, `answer_route_taken`,
   `changelog_entry` and `deploy` are history: triggers refuse UPDATE and DELETE (and, with
   `recursive_triggers` on for every connection, INSERT OR REPLACE, which would otherwise delete silently), and each row carries the sha256 of its
   canonical content (`fleet-db/ids.mjs`: sorted keys, ASCII, integers only) as a UNIQUE column, so an
   import replayed twice, or an event sent twice from another PC, is a no-op.
5. **Nothing derivable is stored.** A task's state, priority and owner are the `task_now` view over its
   events; a question's open/closed is `question_now`; an Orc's current seat is `orc_seat`. A status
   card can no longer disagree with the ledger, because it is rendered from the same rows (E7, E9).
6. **One live seat per Orc per PC is a constraint.** `session_one_live_seat` is a partial UNIQUE index
   on live thrall/orc sessions. A resume retires the old seat and binds the new one in one transaction;
   the 8 hours on 10-17 when two sessions claimed F (E1) cannot be written. The Thrall may hold one
   seat on each PC (a Horde is one Thrall across machines).
7. **Required links are CHECKs.** A new `waiting` on the founder names its question; a new question
   names its task; a new changelog entry names its task or says `fleet_wide`; an `opened` event names
   its owner; a `handed` event names who takes it; a merged PR has its merge time. Rows imported from
   the old files carry `backfill = 1` and are exempt, so the import reports gaps instead of failing
   (E10: 0 of 81 questions named a task).
8. **Times are INTEGER UTC milliseconds** (the meter's rule). Lane K's JSON row schemas use ISO text to
   the second; the access layer converts at the boundary, and K's files become rendered views.
9. **The meter stays its own file.** `metrics/fleet.sqlite` (lane L) is high-volume and pruned; it joins
   fleet.db with `ATTACH`. A foreign key cannot cross files, so the meter keeps `orc_id` and
   `session_id` as text equal to the ids here (today it keeps the letter in `orc`; L adds `orc_id`).
10. **One write path.** Lanes write their tables through `fleet-db` functions and `horde db` verbs, never
    with their own connection, so pragmas, transactions and hashing are the same for every writer.

## Who writes which table

| Tables | Writer | Through |
|---|---|---|
| `node`, `label_seq`, `task`, `task_event`, `task_pr`, `changelog_entry` | N (task.py and progress.py move onto the access layer) | `horde db task ...`, `horde db log ...` |
| `pr` | N, from gh (the pr-cache poll) | `horde db pr sync` |
| `orc` (registry: letter, name, domain, tier, order, retire) | F | `horde orcs` verbs calling the access layer |
| `session`, `pane`, `session_pane` | K (SessionStart/SessionEnd hooks, resume binding) | `horde db seat bind` (one transaction) |
| `parking_lot`, `parking_lot_member`, `wake`, `wake_member` | K | `horde fleet hibernate / wake` calling the access layer |
| `question`, `question_event`, `answer`, `answer_route`, `answer_route_taken` (TAKEN from the target's hook) | F (decisions verbs; routing reads `orc_seat`) | decisions store writes the DB in the same call |
| `decisions_snapshot`, `decisions_snapshot_item` (append-only; live list = newest per Orc) | F (the publish verb; until then an interim JSON per publish, imported by N) | `publishDecisions` in `fleet-db/write.mjs` |
| `service`, `deploy` | F (relay tend), L (router) | `horde db deploy add` after verify |
| `work_unit` (agents and wargs; migration 6) | N owns the verb; C places the hooks and the `wezspawn` call | `horde work start / end`; the meter reads it by ATTACH |
| meter tables (`tokens_*`, `mail_hops`) | L, in `metrics/fleet.sqlite` | ATTACH; ids from here |

Not in schema version 1, added by a later migration when their owner is agreed: `mail` (to_orc first,
session resolved at delivery: fixes E5), `device` (mirror of AWS TestDevices, needs lane A's knowledge).

## Phase plan

| Phase | What | Lanes | Done when |
|---|---|---|---|
| 0 | Schema and store (this PR). | N | Merged, suites and mutants green. |
| 1 | `horde db` verbs (init, status, check) and an idempotent importer from tasks.jsonl, pr-cache, changelog.jsonl, the decisions store, registry/sessions, hibernations and the status cards (seeds `orc`). An unlinked-rows report (for example lane `sleeping-sessions` -> K) for a one-time fix. The one Horde home is decided and moved. | N, with F (home move: relay and decisions live there) | fleet.db on this PC holds every row; the importer run twice adds nothing. |
| 2 | Seats: K's resume hook calls `horde db seat bind`; answer routing and `wezfleet tell` resolve through `orc_seat`; tiers set (M=1, J=1). | K, F | An answer to an Orc is routed after a resume with no label search. |
| 3 | Dual write: task.py, progress.py, decisions verbs and park/wake write the DB first, then their old file in the same call. A nightly diff alarms on any difference. | N, F, K | A week of clean diffs. |
| 4 | Views: status.txt facts, PROGRESS.md, PARKED-*.md, no-restore markers, a facts header in lane-state.md, and the jsonl files rendered from the DB, each marked "generated - do not edit". | N | No hand-typed copy of a DB fact left. |
| 5 | Relay replica (hashed events pushed to the relay, read-only there) and the meter's `orc_id`. | F, L | The phone reads the replica. |
| 6 | Retire hand copies: briefs and memory stop carrying state; the status-card format checker goes. | N | - |

## Rules the importer keeps (phase 1; from the review of PR 339 and the lanes' answers)

- Orc ids: K's parking JSON and the old registry name an Orc by lane folder or letter; the importer maps
  both to `orc.id` through `orc.lane_dir` / `orc.letter`, and reports any name it cannot map.
- Backfill ULIDs are minted from the event's own time (`ulid(atMs)`), so `task_now`'s same-millisecond
  tie-break follows event time, not import order.
- The ledger's free-text writer and waiting-on survive as `task_event.by_text` and `on_text`; `on_kind`
  is the class. Its `merged: true` flag is not copied: merge state is `pr`, filled from pr-cache.json's
  mergedAt (gh), never inferred.
- A session's parent or resumed-from that is not in the registry gets a stub row first (rank unknown,
  first_seen = the child's), so the immediate foreign key holds.
- Every hash is recomputed from the row's content on import and compared with the source's own hash
  where it has one (the decisions store's requestHash); the database cannot check a hash against its row.
- The decisions store's recorded arrivedAfterClosing is compared with `answer_now.open_at_arrival` for
  every answer; any difference is reported, never silently taken.

## Rules a writer must keep

- Open with `openStore` only; never `new DatabaseSync` on fleet.db in product code. The append-only
  triggers hold only with `recursive_triggers` on, which is per connection: `openStore` sets it and
  `inWrite` refuses to write when it is off, but a raw connection is outside both. SQLite cannot stop a
  process that opens the file itself; the one write path is the guard, and the phase 3 nightly diff
  (rows against their recomputed hashes) is the check.
- Every multi-row write is one `inWrite` call. Take a label inside the write that uses it.
- History rows are inserted with their sha256; on a UNIQUE conflict on sha256 the write is a no-op.
- A new column or table is a new migration appended to `MIGRATIONS`; an old one is never edited.
- History rows go in through `appendHistory` (`fleet-db/write.mjs`): the hash is of the whole stored row
  (every column but `id` and `sha256`, a column left out taking its default or null), so it can be
  recomputed from the row alone; the conflict clause names `sha256` only, so a row that breaks a CHECK,
  a NOT NULL or another UNIQUE still fails loudly (a plain INSERT OR IGNORE would drop it in silence).
- Ids come from one minter per process (`newId`): a second id in the same millisecond is the last one
  plus one, so rows written in one millisecond sort in the order they were written.

## Migration 2: what the Progress and Decisions pages show (M's orders of 2026-10-19 and 10-20)

- `parking_lot.keep_visible` (0/1, default 0, lot level, agreed with lane K): a parked Orc's card and
  questions leave the Progress and Decisions pages unless its park says keep-visible. `parked_now` is
  every member still parked, with its lot's `keep_visible` and an `orc_id` (the member's own, else its
  session's). Lane F's lists read it.
- `decisions_snapshot` and `decisions_snapshot_item` (founder, 10-20: the Decisions page showed stale
  lists): each Orc publishes its whole list; the live list is the newest snapshot per Orc
  (`decisions_live`, `decisions_live_item`) and every older one is the archive. No `superseded_by`
  column: "newest" is already a fact of `published_at`, and a pointer would be a second copy of it.
  `sha256` is of the canonical items and is not unique (A, B, A records the second A); a trigger
  refuses a snapshot equal to that Orc's newest, and `publishDecisions` answers "unchanged" instead of
  writing. Positions run 1..`item_count` (a trigger); that every position is present is checked by
  `horde db check`, since the items are written after their snapshot. An empty list is a list.
- Until lane F's publish verb calls the access layer, F writes one JSON per publish
  (`{orc, publishedAt, sessionId, items: [{position, questionNumber, text, recommendation, importance,
  blocks}]}`) and the phase 1 importer hashes it; F need not match the canonical form.

## Migration 3: the glue (founder, 2026-10-20: every object of the Horde in one database)

- `entity` is the registry of every object: one row per row of `horde`, `node`, `person`, `orc`,
  `session`, `pane`, `task`, `pr`, `question`, `answer`, `decisions_snapshot`, `changelog_entry`,
  `parking_lot`, `service`, `deploy` and `orc_status` (`ENTITY_TABLES` in `schema.mjs`), made, touched
  (`updated_at`) and removed with its object by triggers, so it can never drift. `kind` is the table;
  `created_by_id` is who made it (a person, an Orc or a session, itself an entity). An object's id never
  changes, an entity cannot be deleted from under its object, and `horde db check` lists any object
  missing from the registry and any entry whose object is gone. Existing rows are entered by the migration.
- `tag` + `entity_tag` tag any object (lower-case names; a colon makes a family, `area:relay`). `link`
  relates any two objects with a typed relation (`blocks`, `relates-to`, `answers`, `implements`,
  `duplicates`, `follows-up`, `caused-by`, `mentions`); a link is retired, not deleted, and live at most
  once. Fixed relations stay foreign keys (a task's parent, a question's task). Lane F's notification
  tables (event, subscription, delivery) point their subjects and owners at `entity` in a later migration.
- `horde` (one Thrall across machines, `node.horde_id`), `person` (one live founder; staff), and
  `session.model`.
- `orc_status`: the status of every Orc and of the Thrall, history kept, append-only and hashed;
  `status_now` is the newest per Orc. Only `doing` and `blocked` are typed (the card's limits); the card's
  finished and waiting-on lines are derived (phase 3 plan above).
- `task.position` and `task.due_at`; the view `task_tree` numbers every open task in its owner's list
  (top tasks by priority, then position, then age; subtasks by position under their parent: 3, 3.1,
  3.1.2), with a sort key that orders 1.10 after 1.9. `task_checkin` records each turn that looked at its
  list (the list's hash), for lane K's per-turn Stop hook.
- Writers never INSERT OR REPLACE an object (the replace deletes and re-makes it, so its entity row loses
  created_by and updated_at): UPDATE, or INSERT ... ON CONFLICT DO UPDATE. A tagged or linked object
  cannot be deleted until its tags and links are removed (their foreign keys hold its entity row). A task
  cannot be moved under its own subtask. updated_at is stamped on every UPDATE of an object, heartbeat
  columns included; if that ever costs, the trigger narrows to UPDATE OF the columns that matter.

## Confirm record (migration 5; T-0299, M's ruling)

- A publish with a list equal to the live one writes no snapshot (`decisions_snapshot_not_same`), so the
  turn-duty Stop hook could not tell an Orc whose list is unchanged from one that never looked at it.
  `decisions_confirm` (id, orc_id, snapshot_id, session_id, confirmed_at) is the record: append-only,
  one row per accepted publish, written in the same transaction as the publish. A new list gets its
  snapshot and a confirm at the same millisecond; an equal list gets a confirm for the live snapshot and
  nothing else. A refused publish writes nothing.
- Triggers: a confirm must be of its Orc's live snapshot at insert time, and never earlier than that
  snapshot's `published_at`. `horde db check` also flags a confirm whose snapshot belongs to another Orc or
  that is earlier than its snapshot (reachable only with the triggers off). Unique on (snapshot_id,
  confirmed_at): a second publish in the same millisecond adds nothing.
- `decisions_live` (recreated, every old column kept) gains `confirmed_at`: the latest confirm of the live
  snapshot, else `published_at`, so `confirmed_at >= published_at` always; snapshots made before migration
  5 read `confirmed_at = published_at`.
- FOR THE HOOK (lane K): the field is `confirmedAt` (ISO UTC) in each list of `horde decisions published
  --json`, beside `publishedAt`. The turn-duty check should use the later of the two (confirmedAt is never
  before publishedAt). `published` text prints `published <ISO>, confirmed <ISO>`; `publish` of an equal
  list prints `unchanged, confirmed <ISO> (snapshot ...)`.

## Work units (migration 6; T-0299, founder ruling 2026-10-21)

Delegated work is recorded as what it is, by a table and not by a habit.

**Definitions.** An AGENT is an Agent-tool subagent inside a session: no window of its own, named by the
harness's subagent id. A WARG is its own claude session in its own WezTerm pane (started by `wezspawn`). Either
has a PARENT, the session that spawned it. Nothing else is a work unit: the parent session itself is a row of
`session`, as before.

**Who writes.** Lane C places the hooks and the `wezspawn` call (T-0326): `SubagentStart` runs `horde work start
-Kind agent`, `SubagentStop` runs `horde work end`; `wezspawn` runs `horde work start -Kind warg` and the warg's
session-end hook runs `horde work end -Session`. Lane N owns the table and the one write verb (`fleet-db/work.mjs`,
`fleet-db/work-cli.mjs`, `cli/commands/work.ps1`); nobody writes `work_unit` with SQL of their own.

**Who reads.** Lane L's meter reads `work_unit` READ-ONLY by `ATTACH`, joining on `agent_id` (an agent) or
`session_id` (a warg). Every token figure stays in the meter's own database and is never copied here: a work unit
says WHO and WHEN and WHAT FOR; the meter says HOW MUCH.

**Columns.** `id` (ULID); `kind` (`agent` or `warg`); `parent_session_id` (the spawning session, required);
`orc_id` (the parent session's Orc, when known); `agent_id` and `agent_type` (agent only: the harness id, and a
type such as `general-purpose`); `session_id` (warg only: its own session); `task_id` or `task_flag` (exactly one);
`work_type` (`build`, `review`, `verify`, `research`, `mechanical`, `monitor`, `other`); `domain` (the parent Orc's
lane, short); `model`; `started_at`; `ended_at`; `outcome` (`running`, `done`, `failed`, `stopped`, `abandoned`).
Indexes for the readers: `(orc_id, started_at)`, `(task_id)`, and `(outcome)` for the running ones only.

**Rules the database holds.**
- An agent has an `agent_id` and no `session_id`; a warg has a `session_id` and no `agent_id` or `agent_type`; a warg
  is never its own parent. One agent id per parent (`UNIQUE (parent_session_id, agent_id)`), one unit per warg
  session (`UNIQUE (session_id)`).
- `agent_id` is stored EXACTLY as the harness gave it (the id in the subagent transcript's file name): no trimming,
  lower-casing or reformatting, because the meter joins on it. Only its length (1 to 200) and printable ASCII with
  no space are checked; a bad id is refused, never repaired.
- A unit names a task OR a flag, never both and never neither. `no_task` means the brief named no task (these are
  counted and nagged); `backfill` means recorded after the fact. They are kept apart. A task may be filled into a
  `no_task` unit later (the flag is then cleared); a task once set never changes, and a `backfill` unit stays so.
- `outcome = 'running'` exactly when `ended_at` is empty, and `ended_at >= started_at`.
- Triggers: `kind`, `parent_session_id`, `agent_id`, `session_id`, `started_at` and `id` never change; a unit leaves
  `running` once, and an ended unit's `ended_at` and `outcome` never change; a unit is never deleted.
- `horde db check` also flags a warg whose own session says it has another parent than the unit names, and a unit
  whose Orc is not its parent session's Orc (both reachable only by changing the session afterwards).

**The verb.** `horde work start -Kind agent|warg -ParentSession <uuid> (-AgentId <id> [-AgentType <t>] | -Session
<uuid>) -WorkType <t> [-Task T-NNNN] [-Domain <lane>] [-Model <m>] [-At <ms or ISO>]`; `horde work end
(-ParentSession <uuid> -AgentId <id> | -Session <uuid>) -Outcome done|failed|stopped|abandoned [-At ...]`; `horde work
list [-Orc <letter or lane folder>] [-Running] [-Json]`. The home comes from `HORDE_HOME`, as every fleet.db command.
Made for hooks: one short transaction, ASCII output, one line per outcome.
- Exit codes of `fleet-db/work-cli.mjs`: 0 done; 1 refused or failed (one line, `refused: <reason>`); 2 no home; 3
  `fleet.db busy` (the lock was not free within `HORDE_WORK_BUSY_MS`, default 3000, so a hook never hangs). Through
  `horde work` every nonzero is exit 1 with the same line.
- A repeat changes nothing and exits 0: `already started agent <id>`, `already ended <id> as <outcome>`. Ending an
  ended unit with a DIFFERENT outcome is refused (an end is final). Ending a unit that was never started is refused.
- No `-Task`: recorded as `no_task`. A task id fleet.db does not know is NOT refused: the ledger may be ahead of the
  last import, so the unit is recorded as `no_task` and a `warning: task T-NNNN is not in fleet.db yet` line names
  the id.
- A parent or warg session fleet.db has not seen gets a stub `session` row, as the importer makes one: the parent as
  rank `unknown` with no Orc, the warg as rank `warg`, parented to the unit's parent and in its Orc. An end time
  named with `-At` that is before the start is refused; with no `-At`, a clock behind the start ends the unit at its
  start rather than stranding it.

**The registry's `kind` (agreed with C).** C's session registry records gain a field `kind` (`thrall`, `orc` or
`warg`), written by `wezspawn` and the seats. The importer reads it into `session.rank` when the session is new
(`RANKS` already holds all three; migrations 1 to 5 are untouched). A record with no `kind` keeps the older rule
(`rank`, then `role`). A `kind` that is none of the three is reported and the older rule decides. A session already
in fleet.db keeps its rank: a `kind` that disagrees with it is reported (`kind X disagrees with the stored rank Y
(rank kept)`) and never written over it. The seat rules still apply on top: an `orc` or `thrall` kind with no Orc row,
or a second live seat for one Orc, is rank `unknown`, as before.

## Status cards become a generated view (plan for phase 3; M, 2026-10-19)

The status card (`status.txt`, read by one reader, `ConvertFrom-HordeFleetStatusBytes` in
`fleet/StatusPanel.ps1`) is rendered from fleet.db, not typed:

- a new `orc_status` table holds the only human words: `doing` and `blocked`, set through lane K's
  validating writer (`horde status set`), so the reader's rules (120 characters, plain words, no bare
  references) hold when the words are written;
- `finished` and `waiting on` are derived: from `task_now` (done and verified tasks), `pr` (merged
  work) and `question_now` (open founder questions of that Orc);
- the renderer writes `status.txt` through K's writer, and its tests read the result back with
  `ConvertFrom-HordeFleetStatusBytes`, so a rendered card that the reader refuses fails the build;
- lane F's Progress page lists cards only for registry Orcs today, and for live `orc` rows once
  fleet.db holds them.

## Importer (phase 1c part 1)

`fleet-db/import.mjs`, `importFleet(db, sources, { dryRun })`, run by `horde db import` with explicit paths
(`-Ledger`, `-PrCache`, `-Changelog`, `-Cards`, `-ThrallCard`, `-Registry`, `-DryRun`; no path is ever defaulted
to the real files). Each source is optional. All files are read first; then one `inWrite` transaction
runs node, orcs, sessions, PR cache, ledger, changelog and orc_status in that order, so a failure
leaves the database as it was and a dry run rolls the same work back. The decisions store is part 2a (below); the parking lots
are part 2b (below).

Idempotent: state rows (node, orc, session, task, pr) are found by their label and kept as they are
(never renamed, never refreshed); history rows go through `appendHistory` with `backfill = 1`, so the
second import of the same sources adds 0 rows to every table. Ids of history rows are minted from the
row's own time. The report counts, per table, rows added and rows already there.

| Source | Becomes | Mapping |
|---|---|---|
| node | one `node` row | this PC's hostname, `is_authority` 1, only if the database has no node; sessions use the existing authority node |
| cards (`<folder>/status.txt`) | `orc` + `orc_status` | letter = the `orc:` line, `lane_dir` = folder name, name = the `lane:` text, rank orc. Read by the reader's rules (6-7 lines, ASCII, no BOM, one capital letter): an invalid card (`orc: F1`) makes no Orc and is reported. Existing rows are found by lane_dir or letter and kept. One status row per card: doing; blocked `no` (any case) is NULL, `none` and any sentence stay as words; `at` = the file's mtime |
| thrall card | the Thrall's `orc` (rank thrall, lane_dir `thrall`) + its status | an existing live Thrall row is kept |
| registry (`<id>.json`) | `session` | BOM stripped; id lower-cased; rank from `rank`, else role (master = thrall, orchestrator = orc), else unknown; Orc from the label letter for an Orc's own seat, else the owner letter (a label like C3 gives C); times to UTC ms (seven fraction digits read, the US-locale `MM/DD/YYYY` firstSeen read as UTC and flagged); pid only with its start time; a parent or resumed-from missing from the registry gets a stub row (rank unknown, times = the child's first_seen); freshest session takes an Orc's one live seat, a second live one is kept with rank unknown and reported |
| pr-cache | `pr` | repo, number, state (OPEN/CLOSED/MERGED), merged_at from `mergedAt`, merge_sha only if 40 hex; MERGED with no time is kept open and reported |
| ledger | `task`, `task_event`, `task_pr`, `pr` | tasks by key, title/source/parent from the first `opened`, parents created first. Every line is one event, sorted by time (Z and +00:00 alike; file order breaks ties); `by` is `by_orc_id` for a known letter, else `by_text`; opened lane and handed `to` map letters or lane folders to Orcs; `waiting on` keeps the words in `on_text` with the class in `on_kind` (founder; `M`, a letter or `lane:X` = orc; device, merge, push, gate, service = external; anything else = other); superseded `to` = replacement task. The ledger's `merged` flag is not copied. A `pr` is linked through `task_pr` (linked_by backfill, at the line's time); a PR the cache lacks is made open and reported |
| changelog | `changelog_entry`, `tag`, `entity_tag` | legacy_id = the entry id; lane letter = orc_id, `Thrall` = the Thrall, `fleet-wide` = fleet_wide; a comma list gives the first letter as orc_id and a `lane:x` tag for every letter; task = the leading T-NNNN (suffix dropped); `corrects` = corrects_id, the original written first; an unknown kind is a note; `area` is not imported yet. An entry whose legacy id is there is kept |

WHERE ORC ROWS COME FROM (T-0299). Two paths make an `orc` row from a status card, and both call the one function in
`fleet-db/orc-row.mjs` (`ensureOrcRow`): the importer above, for every card it reads, and `horde status set`, for the card it
has just written and read back clean (`fleet-db/orc-cli.mjs ensure --folder <name> --letter <X> --lane <text> [--thrall]`,
called by `Invoke-HordeStatusOrcRow` in `fleet/StatusWrite.ps1`). The rule is the importer's: a row found by lane folder OR
letter is kept (a Thrall card matches the live Thrall row first), never a second one; only when none exists is one inserted
(lane_dir = the folder name, name = the lane text or else the folder, rank orc or thrall, created_at = now). So a new Orc has
its row from its first card and `horde decisions publish` no longer needs a hand `horde db import` first. `status set` prints
`fleet.db: row made for Orc X` only when it made the row, and nothing when it was there. It is FAIL-OPEN: the card is what
matters, so with no home, no node 24 or later, no fleet.db yet (the command never makes the database), a busy database (the
lock wait is `HORDE_ORC_BUSY_MS`, default 3000) or a newer schema, the card stays written, the command succeeds, and one line
says `card written; fleet.db row not made: <reason>`. Exit codes of `orc-cli.mjs`: 0 done (`added` or `kept`), 1 refused or
failed, 2 no home, 3 busy, 4 no fleet.db. `-DryRun` never reaches it. A folder named `thrall` is the Thrall's card.

Refused, whole, with nothing written: a ledger or a changelog in a run when the database has no `orc` rows and
the same run brings no usable cards. Event hashes hold Orc ids (`by_orc_id`, `to_orc_id`, `on_orc_id`), so a
ledger imported before the Orcs exist would be written again, as other rows, by the next import that has them.
A sub-session label (a letter and digits: C1, C13, M2) gives its lead letter's Orc for `by` (the label stays in
`by_text`), `handed to` and `waiting on`; `analyst*` writers stay `by_text`. A `handed` with no target at all
is reported as needing a person. Live seats are decided first, freshest session first, before any row is
written, so a parent inserted early for its child never takes the seat; a session that loses it is kept with rank
unknown. A time that does not parse is replaced and each replacement is reported. Two cards naming one Orc: only
the newer is imported. Text cut to its column is reported per field. PR repo names are lower-cased, and a PR
with no checked time takes the time of the first ledger line imported (see part 2a, three nits). `--dry-run` refuses a file that needs migrating.

Reported, never dropped in silence: `report.unlinked` lists, by source and reason, with a count and up to five
examples, every row that could not be linked or read (for example `ledger: by C13 names no Orc row (kept as
by_text): 12`). A `handed` line with no known target and a ledger line without a usable ts/task/event are the
only lines not imported (the schema requires a target for a handing); each is in the report.

## Importer (phase 1c part 2a: decisions store)

Why now: `horde decisions publish` links a list line to its question by number (`fleet-db/decisions-cli.mjs`
looks the number up in `question`), and that table was empty, so every list naming a question was refused.
This part fills `question` and its answers from the founder's real store. `horde db import -Decisions
<HORDE_HOME>\store\decisions` (`--decisions` on the node side; refused on any other verb).

**Reading.** The folder holds one record per file, `0000000001.json` upwards. All files are read and checked as
a whole before anything is written, and one fault refuses the SOURCE (nothing from it is imported; the other
sources go on, and the report says why in one line): a gap in the sequence, two records with one id, a file
whose name is not its record's sequence or not ten digits, a record that is not a JSON object, an id that is not
32 lower-case hex characters, a `schemaVersion` other than 1. A file that is not `.json` (a half-written
`.tmp`) is ignored and named. Times are the 7-digit-fraction `Z` form, read to UTC milliseconds.

**Mapping.**

| Record | Becomes |
|---|---|
| `question-added` | one `question` row per number (the founder-visible Q number): `title`, `kind`, `body` = whatItIs, `yes_means`, `recommendation`, `group_name`, `group_note`, `importance` and `blocks` (only when the record states them), `needs_passkey`, `asked_at`, `decisions_seq`, `backfill` 1; the lists (options, parts, waiting, files, references) and needsSecret are one canonical JSON text, `detail_json`. `followsUp` is `follows_up_id` (the earlier question). `askedBy` is `asked_by_orc_id` where it names one (`Orc C`, `M (Thrall)`, `Thrall`), else `asked_by_text` and a report line. `task_id` is empty (E10: the store never named a task) and every question says so in the report. |
| `message-said` | one `answer` row (speaker, route, text, part, wording_version, asks, signed_by, replaces_answer_id) and one `answer_extra` row (evidence_present, act, recorded_by). |
| `answer-routed` | one `answer_route` row (seat orc/warchief/analyst -> orc/thrall/analyst, session only when it is a `session` row, resolved only with that session) and one `answer_route_extra` row (purpose, label, notice, analyst, note, and the `resolved` the store said). |
| `question-closed`, `-reopened`, `-ranked`, `-updated`, `-acked`, `answer-change-replied` | one `question_event` row each (closed, reopened, ranked, updated, acked, change-reply), `data_json` the record's data without the number, plus `actor`. |
| `messages-read` | one `decisions_read` row (reader, up_to_seq). |
| any other kind, a record about a question never added, a route to a message not in the journal, a time that does not read | not imported, counted in the report by reason. |

**Signing material.** `evidence` and `signedBy` of a phone answer are never stored. `answer_extra.evidence_present`
says evidence was there; `answer.signed_by` holds the sha256 of the key id (so `answer_now.authorizes` still sees a
signed answer) and not the key id. A test scans every text column of every table, and the report, for the
fixture's values.

**requestHash.** Each record's hash is recomputed as the store makes it (`decisions/Operations.ps1`: sha256 of the
canonical text of `{operation, actor, number, body}`; the body is the data without the number, without `evidence`
and `signedBy` of a say, without the `closedBySeat` a close gets after hashing; an add hashes number 0 because its
request has none; a marking has no number and hashes `{upTo}`; strings are hashed as the characters themselves in
UTF-8, not the ASCII-escaped form `ids.mjs` uses). A record whose recomputed hash differs is imported as it
stands and reported by record. Known answers made by PowerShell's `Get-HordeDecisionHash` are in the test, and the
end-to-end scenario hashes its fixture with the store's own function. The source's hash is not stored (no column:
the row's own sha256 is of the row).

**The fold.** The journal is folded in order, as `decisions/Rules.ps1` folds it, to work out what the store never
writes: a question is open until its `question-closed` (open again after a reopen); a `question-updated` that
changes a wording field (title, options, parts, whatItIs, yesMeans) raises the question's wording version. Per
message that gives `arrivedAfterClosing` (the question was not open when it arrived), `saidToEarlierWording` (a
wording version below the question's) and his change of his own answer (`replaces_answer_id`: his answer that
counts - it asks, has no act, arrived while open, and is not chat words under a passkey question - replaces his
latest earlier answer that counts to the same part). After the write, every message is compared with
`answer_now`: arrival and authorization. Every difference is a line in the report. The differences that can arise
by construction: a message in the same millisecond as the close that follows it (the schema counts the close as
before); an unsigned phone answer under a passkey question (the schema calls it unauthorized, the rules do not). A message said
to an earlier wording has no flag in the schema: it is counted in the report and kept as an answer.

**Parts.** A parts question is answered part by part, one `message-said` per part. The schema keeps a part as one
capital letter and the store writes lower case (`a`), so the letter is stored upper case and the count of those is
in the report. A part the question's parts (as last worded) do not list is reported unless the message was said to
an earlier wording.

**Migration 4** (never edits 1-3): `question` gains `asked_by_text`, `yes_means`, `recommendation`, `group_name`,
`group_note`, `importance`, `blocks`, `detail_json`; new write-once, append-only tables `answer_extra`,
`answer_route_extra` and `decisions_read`. The extras are beside `answer` and `answer_route`, not columns of them,
because those are hashed history: the hash is of every column, so a new column would change how a row written
before it recomputes (the phase 3 diff). `question` is state, not history, so it takes plain columns. Current
importance, blocks and group are derived from the ranked and updated events; the question row keeps what was
first asked.

**Acknowledgements close.** `Step-HordeDecisionAcked` closes an open question when the Orc that asked has the
answer. Migration 4 therefore recreates `question_now` and `answer_now` so that an `acked` event closes a
question as a `closed` event does (a later `reopened` still opens it); no closed event is made up. The store
writes an ack only when the rules applied it, so the fold closes on every ack (an ack on a closed question is
reported). Messages after an ack are therefore `open_at_arrival` 0, as the rules say.

**A question imported before migration 4** (a version-3 database already holding it) gets the new columns that are
NULL filled from the journal, one `UPDATE ... WHERE column IS NULL` per column; a value that is there is never
overwritten. **Unknown keys**: every record's top-level, `data` and `data.question` keys are compared with the
known set, and an extra key is reported by kind and key with a count (`unknown key data.mood in message-said
records`); it is not stored.

**Idempotent and atomic** like part 1: the step runs inside the same transaction (a dry run rolls it back; a
refused row, such as a lone surrogate in a message, undoes every row before it); questions are found by number and
kept; history goes through `appendHistory` (the hash includes `decisions_seq`, so each record is one row) or
`ON CONFLICT DO NOTHING` on its unique `decisions_seq`/`answer_id`/`route_id`; a second import adds 0 rows to every
table, and `findProblems` is empty after.

**Three nits of the review of part 1.** (1) A wait on `lane:C1` resolves the label to its lead Orc, as a bare `C1`
already did. (2) A PR with no checked time is dated from the first ledger line that was imported (a line the
importer drops - unknown event, a handing with no target, a priority with no value - dates nothing). (3) With no
imported line and no merge time, the PR's `checked_at` is the time of the import, not 1970: the column is NOT NULL
and the entity registry reads it as the time the object came to be, so NULL would need a table rebuild; the time we
first saw it is true to what `checked_at` means for a row nobody checked, and the report says so for each such PR.

## Importer (phase 1c part 2b: parking lots)

Why now: the parking lots (T-0216, lane K) are the last file-kept source before the one-home move. K wrote them as
one JSON file per table so that a row moves into fleet.db as it is. `horde db import -Lots
<HORDE_HOME>\fleet\hibernations` (`--lots` on the node side; refused on any other verb).

**Reading.** For each `<hid>` folder: `parking_lot.json`, `parking_lot_member.json` and, for every
`wakes\<id>\`, `wake.json` and `wake_member.json`, each `{"v":1,"table":<name>,"rows":[...]}`. All files are read
before the transaction. A file that is not JSON, is not version 1, names another table, holds a row that is not an
object, is missing, or a `parking_lot.json`/`wake.json` that does not hold exactly one row, refuses its WHOLE lot:
nothing of it is imported (not even a stub session) and the report names the folder and the file. A wake folder
with no `wake.json` is an unfinished write (K writes the members first): it is reported and skipped, the lot goes
on. A folder with `record.json` and no `parking_lot.json` is a legacy record: it is NOT imported and is reported as
"legacy record, run K's lot backfill first" with its folder name (K's ULIDs for legacy records are made from the
park's time and a seed in `fleet/Lots.ps1`; the importer does not reimplement them). A folder with neither is
ignored and named.

**Mapping.** Rows go in as they are: K's ULIDs are kept, a column left out is NULL (`keep_visible` of a lot written
before the flag is 0), times (`created_at`, `requested_at`, which must be UTC seconds `...Z`) become UTC
milliseconds. A column the table does not have is reported by table and name and not stored. Sessions are the
harness's uuids: a lot, member, wake or `new_session_id` session that is not in `session` gets a stub row first
(rank unknown, first and last seen = the time of the lot or wake that names it), as part 1 does for a parent; the
report counts them. An Orc named in `created_by_orc_id` or a member's `orc_id` is mapped as part 1 maps one: the
`orc` table's own id, else a letter, a lane folder, or a sub-session label (`F3` gives F); a name that maps to no
row leaves the column empty and is reported. No migration: schema version 2 already holds `keep_visible`, and every
column K's files carry has a column (migration 6 is not needed).

**One savepoint per lot.** A row the schema refuses (a bad ULID, a state outside parked, woken and dropped, a tier
of 3, a lot id that is not the lot's, a session in a lot twice, a time that is not UTC seconds, a wake outcome
outside the five) rolls that lot back whole, to its savepoint, and is reported with the reason and the folder: a lot
is there whole or not at all, and the other lots go on. The counts of a rolled-back lot are not added to the
report. The whole step is inside the run's one transaction: a failure later undoes every lot, and a dry run rolls
them back.

**Idempotent.** `parking_lot`, `wake` and `wake_member` are created once, found by their key
(`ON CONFLICT DO NOTHING`): a lot already there is never rewritten, even if the file's reason has changed.
`parking_lot_member` is a state table. A re-import adds a member the lot did not yet hold, and moves an existing
member's state forward, never back. K's member rows carry NO time, so "newer" cannot be read from the row; it is
read from the lifecycle: parked is the start, woken and dropped (it never slept, so it left the park) are the ends.
A file may take a parked member to woken or dropped; it may not take a woken or dropped member back to parked, and
woken and dropped do not replace each other (a re-park is a new lot, never a member going back). A file that is not
further along than the database is kept as the database has it and reported ("member state in the file is not
further along ..."). `parking_lot_member` therefore reports a third number, rows moved forward. A second import of
unchanged files adds 0 to every table and moves 0, and `findProblems` is empty after.

**What is kept and what is refused (review rounds 1 and 2).** A tier outside the integers 1 and 2 refuses its lot (the
driver would otherwise throw outside the savepoint). A wake member must be a member of the lot and appear once per wake. A
lot with zero members IS imported and reported ("lot holds no member"): `findProblems` does not flag it and K never writes
one, so it is a sign of a damaged folder, not a reason to lose the lot row. A lot, wake, wake member or member already in
fleet.db with other content (members: another orc_id, tier or note) is kept as it is and the difference reported; a wake id
that already exists under another lot is not a difference but a clash, and refuses the whole lot. A lot's report lines
(mismatches, stubs, unknown columns) are collected in a report of its own and added to the run's only if the lot commits.

## One home (pointer file) (T-0299; M's ruling of 2026-10-21)

Where Horde's home is (fleet.db, metrics, turn-duty, notices, wake, lots) used to be worked out in several places, each its own
way: `core/Home.ps1` (HORDE_HOME, else `%USERPROFILE%\.horde`), `fleet-db/store.mjs` and `fleet-metrics/home.mjs` (HORDE_HOME or
refuse), `hooks/horde-turn-duty.mjs` (its own variables, config.json, and a state folder fixed under `%USERPROFILE%\.horde`). The
real home is a different folder from `%USERPROFILE%\.horde`, so some writers used one and some the other, and an environment
variable set at user level reaches only processes started afterwards, so running sessions, hooks and scheduled tasks would have
kept the old folder for days. The home now resolves the same way everywhere, from one source, so one step flips the whole fleet.

**The pointer file.** `%USERPROFILE%\.horde-home.json`, outside any home, exactly `{"v":1,"hordeHome":"<absolute path>"}`, ASCII.
It is a file and it is read on every call, so a running process sees a change at its next call.

**The order, the same in every resolver** (`core/Home.ps1`, and for node the one module `core/home.mjs`, which
`fleet-db/store.mjs`, `fleet-metrics/home.mjs` and the turn-duty hook import):

1. `HORDE_HOME`, if set (absolute, else refused, as before; the tests rely on it);
2. the pointer file, if there is one;
3. PowerShell only: `%USERPROFILE%\.horde`, as before. The node resolvers have no third step and refuse when neither (1) nor (2)
   names a home: a silent fallback would split the data.

**A bad pointer is refused, never skipped**, with a message that names the file: unreadable, not JSON, not ASCII (a byte-order mark
included), `v` not 1, no `hordeHome`, a relative `hordeHome`, or a folder that does not exist. Skipping it would send this program
to another folder than the ones that read the pointer, and nothing would say so. (The hook cannot refuse a stop; it logs the
refusal by name and passes, and does not fall through to config.json.)

**The turn-duty hook** keeps `HORDE_TURN_DUTY_HORDE_HOME` first and `config.json` `hordeHome` as the last fallback (K's), with
the rule above between them. Its state and config folders default to `<resolved home>\turn-duty` when a home resolves, else the old
`%USERPROFILE%\.horde\turn-duty`; the `HORDE_TURN_DUTY_STATE_DIR` and `_CONFIG_DIR` overrides stay.

**The verb.** `horde home` prints the home and which source gave it (HORDE_HOME, pointer, default). `horde home set -Path <abs>`
writes the pointer atomically (a temp file in the profile folder, then a rename over the pointer: a reader sees the old pointer or
the new one) and prints the old and the new home; it refuses a relative path, a folder that does not exist, a folder without
`fleet.db`, and a path the ASCII pointer cannot hold. `horde home clear` removes the pointer and prints what the home is now.
`horde db` and `horde decisions publish` still refuse to make fleet.db in a default folder: they need the source to be HORDE_HOME
or the pointer.

**Flip and rollback.** Flip: copy or move the data so the new home holds `fleet.db`, then `horde home set -Path <new home>`. Every
resolver follows at its next call; nothing is restarted. Rollback: `horde home set -Path <old home>`, or `horde home clear` to go
back to the default. There is no migration of data and `node.json` handling (`core/Device.ps1`) is unchanged. A machine whose
environment already sets HORDE_HOME keeps using it: the variable wins, so unset it (or set it to the same folder) for the pointer
to take effect in those processes.

**What bakes a home, and what was done about it (round-1 review).** HORDE_HOME outranks the pointer, so anything that
writes HORDE_HOME into a long-lived thing keeps the old folder after `horde home set`. Each writer, by what it outlives:

- *Scheduled tasks, all registered to run as the user who registers them* (logon type S4U or Interactive, so the user's
  profile and pointer are visible to them): the metrics collect job (`core/Schedule.ps1`), the supervisor's two jobs
  (`cli/ServicesTend.ps1`, which `cli/Setup.ps1`'s elevated command also registers) and the meter's two tasks
  (`fleet-metrics/register-schedule.ps1`) NO LONGER BAKE THE HOME. Each run resolves it like any command: HORDE_HOME, then
  the pointer, then the default. The job's description still records the home it was registered under (the marker), which is
  data for status, not what the run uses (the scheduler no longer refuses to replace a task over it).
  **A task that runs as a different account (SYSTEM, another profile) cannot see this user's pointer** and would need a home
  baked in or its own pointer; none of Horde's tasks is registered that way today, and the elevated command of
  `cli/Setup.ps1` (a prompt that may be another admin account) still passes the resolved home to that one short-lived
  command: if the prompt is another account, that account's profile must hold the pointer for the job it registers.
- *Short-lived children the command starts and waits for* (`cli/Setup.ps1` `Invoke-HordeSetupHorde`, `cli/ServicesAct.ps1`
  `Invoke-HordeServiceHordeCommand`, `cli/commands/db.ps1`, `meter.ps1`, `decisions/Publish.ps1`) keep receiving the home the
  command resolved at that moment; nothing of theirs outlives the command.
- *Long-lived services* (`cli/ServicesAct.ps1` start of a horde-kind service; the home is the definition's `hordeHome`,
  `core/Services.ps1`) take the home WHEN THEY START, and **`horde services stop` runs the stop command with the
  definition's `hordeHome`** (`cli/ServicesAct.ps1`). So the ORDER MATTERS: a service must be stopped while its definition
  still names the home it runs on. Editing the definition first sends the stop to the new home while the process runs on
  the old one (a relay running twice, or a stop that does nothing). `horde home set` therefore REFUSES while a
  horde-kind service of the current home has a fresh heartbeat (it names the service and the order), rather than guess:
  the heartbeat is the supervisor's own test for "running", and a refusal costs one stop, where a wrong set costs a double
  relay. The check reads the CURRENT home's definitions only; a definition already edited to the new home before the stop
  is not seen, which is why the order below is the rule.
- *Sessions through the SSH listener* (`transports/ssh/Listen.ps1`) get `SetEnv HORDE_HOME=<home>` from the sshd config
  that `horde listen` wrote, so an SSH session keeps the old home until `horde listen` is run again; `horde home` does
  not read that config (documented only).

**The flip, in full.** (1) Put `fleet.db` in the new home. (2) Stop each horde-kind service while its definition still
names the old home: `horde services stop <name>`. `horde services stop` leaves the heartbeat file, and "running" is a heartbeat younger than its stale time (the larger of 30 s and three ticks), so **wait for it to go stale before step 4**: `home set` and `home clear` refuse until then and say "stopped just now? its heartbeat clears in about N s" with N the wait. (3) Change the definitions' `hordeHome` (in the new home's
`settings\service-definitions.json`). (4) `horde home set -Path <new home>`: this process and every new or running reader
follow at their next call; it refuses if a service still runs. `horde home clear` moves the home back to the default just as `set` moves it, and has the same guard (target: the home it would leave). (5) Unset HORDE_HOME wherever it is set (`horde home`
warns while it is, in this process). (6) `horde services start <name>` for each service. (7) Re-run `horde listen` so the
SSH sessions get the new home. (8) Re-register each task that BAKES a home (those registered before this change; a task
only changes when re-registered): `horde metrics schedule remove` then `install`, `horde services unschedule` then
`schedule` (the supervisor's start-up job needs an elevated prompt; `horde setup` prints the line), and
`register-schedule.ps1` for the meter. A task registered since this change bakes none and needs nothing: it resolves the
home at each run, so it is correct even though its marker still names the home it was registered under (its marker is
informational: the scheduler no longer refuses to replace a Horde task whose marker names another home, because a task no longer
bakes a home in, so the one elevated re-register after the flip replaces the old task and writes the new marker). **The metrics task of lane L needs the
founder's elevated run; L files that.** (9) `horde home` lists every task under `\Horde\` that BAKES a home other than
the effective one (read only; if the scheduler refuses the query non-elevated it says so in one line and the verb goes
on); it should say none bakes in another home.

**What the service guard cannot see (it fails open, so these are the person's to check).** A service with no `alive` block has no heartbeat to read, so it is never counted. A definitions file that cannot be read (missing, refused, not UTF-8) gives no services. A heartbeat that cannot be read gives no running service. A pointer that is bad makes the current home unresolvable, so the guard is skipped and `set` is the way to mend it. In each case the guard says nothing rather than refuse on a guess.

**The user profile a task sees.** The tasks that no longer bake the home find the pointer through the user's profile
folder. A scheduled task run as S4U may have no loaded profile, hence possibly no USERPROFILE in its environment, so when
USERPROFILE is empty `core/Home.ps1` asks the system (`[Environment]::GetFolderPath('UserProfile')`) and `core/home.mjs`
asks `os.homedir()`, before refusing. ASSUMPTION: the system's answer for the account a task runs as is the profile folder
that holds that account's pointer (true for a task that runs as the user who registered it, which is all of Horde's).

**The rooted test.** Both languages refuse a HORDE_HOME that is not a drive path or a UNC path: `\x` and `C:x` (which .NET's
IsPathRooted accepts) are refused by `core/Home.ps1` through `Test-HordeHomeRooted`, as `core/home.mjs` refuses them.

**The hook's throttle state.** The turn-duty hook keeps its state under `<resolved home>\turn-duty`. When the home changes, or
the pointer is bad or cleared and the folder falls back to the profile's, the state is not carried over: the throttle resets
and the first stop after that checks again at once (a nudge a little early, never a lost one).

## Keeping the file-fed tables current (T-0389, Orc M's order 2026-11-02)

**Why.** Every row of `task_event`, `changelog_entry` and `orc_status` was `backfill = 1` from hand imports on 10-21 and 10-22: the importer was the only writer and nothing ran it. Phase 3's dual write is still the plan; until then one scheduled task keeps them at most about 5 minutes behind their files.

**`horde db sync`.** `\Horde\Fleet db sync` (`fleet-db/register-sync.ps1`) ticks every minute at below-normal priority, one instance, 2 minute limit. `fleet-db/Sync.ps1` holds `HORDE_HOME\fleet-db-sync.lock` open with no sharing for the whole run (the OS frees it if the process dies, so no lock goes stale), starts node at below-normal priority, and kills that child at its time limit (default 50 s). The import is one transaction, so a killed run changes nothing. One ASCII line per run goes to `HORDE_HOME\logs\fleet-db-sync.log`, because the task's own last result says nothing (conhost --headless exits 0).

**Settings and cadence.** Sources are never defaulted (the import rule): they live in `HORDE_HOME\settings\fleet-db-sync.json`, written by `horde db sync -Save`, and a sync without that file refuses. The files step runs when its last success is 5 minutes old or more, or with `-Force`; `HORDE_HOME\fleet-db-sync-state.json` holds one entry per step so the sessions step can run on every tick of the same task.

**Rows from the sync stay `backfill = 1`.** They still come from files, and the row hash includes `backfill`, so changing it would insert every old `task_event` a second time.

**`horde status set` writes its `orc_status` row live** (`orc-cli.mjs ensure --card`, `backfill = 0`, `at` = the card's mtime, in the same transaction as the orc row). The importer's `stepStatus` skips a card when that Orc already has a row at that time, whatever its backfill, or the sync would add a duplicate of every live status.

### The sessions step (T-0409, piece 2 of T-0299; Orc M's order 2026-11-02: fleet.db is the one central session registry)

**Why.** The overseer and the analyst each detected stalls from their own stores, each re-reading transcripts of up to 195 MB. Both now read the columns below. Orc N is the only writer: there is no verb for the overseer or the analyst. Stalls are NOT judged here: no thresholds are stored, and a reader compares `last_activity_at` with its own clock.

**Migration 7: `session` gains seven nullable columns** (NULL means not read yet). `last_activity_at` and `last_assistant_at` are UTC milliseconds taken from the transcript RECORDS (never a file's modified time). `in_turn` and `waits_person` are 0 or 1. `state` is `live`, `idle`, `waiting-person` or `dead`; the CHECK also allows `waiting-job`, which is RESERVED for piece 3 and is never set by this step. `state_checked_at` is when the sync last judged the state: a reader that sees an old stamp knows the sync was blind to that session. `transcript_offset` is the number of bytes of the transcript already read, always just after a newline.

**One tick, two halves (CONTRIBUTING 14).** The same scheduled task and the same 50 second limit carry both steps; the sessions step runs on every tick, beside the files step and whether or not it is due, with its own key in `fleet-db-sync-state.json` (`lastOkAt`, `lastRunAt`, `lastResult`, `lastMs` and the sessions by state). Neither step blocks the other: each runs in its own `try`, records its own result, and the log line and the output name both (`sync: files skipped (...); sessions ran, 41 sessions (...)`); a failure of either makes the run exit 1 after both have had their turn. The PORT SIDE (`fleet/SessionSnapshot.ps1`, run as a child process by `fleet-db/SessionSnapshotRun.ps1` with at most 40 percent of the limit and killed by its own pid past it) writes one plain JSON snapshot through the fleet ports: the registry records (`core/WezfleetState.ps1`), the live panes of every terminal instance (the host adapter's `Panes` block, `fleet/Port.ps1`; each `cli list` has a limit of its own and a budget shared by the pass), and the sessions whose harness process runs (the agent adapter's control files, one process-table read per tick). The CORE SIDE (`fleet-db/sessions.mjs`) names no port: it validates the snapshot and writes rows. A snapshot that fails or hangs fails only the sessions step, recorded and shown. `horde db status` has one `sessions:` line (last ok, last result, sessions by state).

**Rows, in one short transaction.** Every record in the snapshot is filed through the importer's own `stepSessions` (`importSessionRecords`: one rule for rank, Orc, seat, parent links and stubs, not a copy), so a session missing from fleet.db is added. `pane` and `session_pane` are history: a pane is (node, terminal instance, number, opened_at) and one is open at a time; a session moving panes CLOSES its old `session_pane` and opens a new one; a pane gone from its terminal's list closes its `pane` row and its `session_pane`. Only terminal instances that could be listed are touched. A session row is written only when something in it changed; `state_checked_at` is one UPDATE for all judged ids, so a second identical tick writes nothing else. Each `UPDATE` of a session also touches its entity row's `updated_at` (migration 3), as every update does.

**Liveness is not the registry.** About 115 of 155 registry records are never retired, and one stale record claimed a live pane, so a record only says which pane a session last claimed. When two records claim one pane, the owner is the one whose process is running (the control-file check: the process runs and started when the file says), else the one with the newest `lastSeen` (the record's own field, written by the hook; never a file's time). A retired record claims nothing. A session with no live pane and no running process is `dead`; `retired_at` is NOT set (it stays someone else's). IT IS ASYMMETRIC ON PURPOSE: a terminal that could not be listed, or a process list that was partly unreadable, makes the session UNKNOWN; its state and `state_checked_at` are left alone. A terminal whose gui is not running (its socket file stays behind) is closed, not unknown. Caveats: a session that took a new id inside a running process (a clear or a compaction) keeps the process's old control-file id until the harness rewrites the file, and a pane number reused between two ticks looks like the same pane.

**Activity, from the transcript, by stored byte offset.** Only whole lines are read (a half-written line waits for the next tick); a file smaller than the offset was replaced and is read again from 0; a first read takes at most the last 2 MB, starting after its first newline; each session reads at most 8 MB per tick and the whole step 64 MB, so catching up takes several ticks, never the time limit; a session whose offset is at the file's end costs one stat, so a dead session is never read twice. The rules are the overseer's (`transcript_state()` and its cases; each has a test): only timestamped `user` and `assistant` records and `system` records of subtype `turn_duration` or `stop_hook_summary` count; `isMeta` and `isCompactSummary` records are skipped (an unanswered compaction summary looked like a turn open for four days); a local slash command is no prompt; an interrupt marker closes the turn; an assistant record with `stop_reason` `end_turn` closes the turn, and so does a text-only one with none; any other keeps it open; a turn whose last tool call is `ExitPlanMode` or `AskUserQuestion` is `waits_person`. `state` is `dead` as above, else `waiting-person` when `waits_person`, else `live` when `in_turn`, else `idle`. SUBAGENTS: a session inside a long foreground Agent call looks stalled while its subagent works, so while a session is mid-turn the newest record time of its subagents is folded into `last_activity_at`. Chosen: a bounded tail read (256 KB) of the three most recently written files of `<transcript>/subagents`, not a stored offset per file, because there is no column per subagent, the folder is usually absent or old, and the work stays bounded; the file's modified time only picks which files to look at, and the time folded in is still a record's.

**Known gap, on purpose.** A tool permission prompt waiting for a person is invisible in the transcript: it reads as `in_turn` with no activity, exactly like a stall. This step does not read pane text. The overseer and the analyst must treat a long `in_turn` with no activity as possibly a permission prompt, not only a stall.
