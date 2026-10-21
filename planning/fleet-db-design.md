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
are the next part.

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
