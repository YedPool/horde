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
   updated in place. `task_event`, `question_event`, `answer`, `answer_route`, `changelog_entry` and
   `deploy` are history: triggers refuse UPDATE and DELETE, and each row carries the sha256 of its
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
| `question`, `question_event`, `answer`, `answer_route` | F (decisions verbs; routing reads `orc_seat`) | decisions store writes the DB in the same call |
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

## Rules a writer must keep

- Open with `openStore` only; never `new DatabaseSync` on fleet.db in product code.
- Every multi-row write is one `inWrite` call. Take a label inside the write that uses it.
- History rows are inserted with their sha256; on a UNIQUE conflict on sha256 the write is a no-op.
- A new column or table is a new migration appended to `MIGRATIONS`; an old one is never edited.
