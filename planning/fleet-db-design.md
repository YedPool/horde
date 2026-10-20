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
