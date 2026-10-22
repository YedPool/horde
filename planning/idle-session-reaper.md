# Design: the idle session reaper

Proposed 2026-10-04 (local), measured 2026-10-05 01:41 to 01:50 UTC. Design only: no code ships with
this document. The coordinator reviews it before any slice in section 9 starts.

**The request** (founder, 2026-10-04): "You need to develop a reliable way for horde to clean up idle
sessions all the time."

**Why now.** This machine keeps running short of memory. At 01:41:39 UTC available memory was
1,227 MB (I-01), below the standard admission tier's 2,048 MB reserve (lifecycle plan 1.2). When it
runs that low, Claude Code's harness kills background test runs ("system is running low on memory"),
and that has blocked merges several times. Most of that memory is held by idle sessions: Claude Code
or Codex running in terminal panes after their work is done, or while they wait. Today the founder
closes them by hand when asked, and that does not happen reliably. At the time measured, 7 idle
sessions held about 5 GB private (I-03).

Applied mechanically, the rules below close **one** of them today: D1, 634 MB (section 8). Most of
the rest are held by a Remote Control link (P11) or by the founder's ownership (P1). How much more the
reaper can reclaim depends on two founder decisions (section 11).

**Revised 2026-10-05** after review of PR #84 (`review-84.md`, findings F-1 to F-8). Changes from
that review:

- Remote Control is now modelled (S8, P11).
- Recurring crons are covered by P8.
- Background tasks get their own protection (P12).
- The turn boundary has a measured allowlist (1.5), and section 8 is now computed by a script.
- The version gate is per session (1.6).
- Sleep is handled (F6).
- Policy conflicts are listed (section 10).
- The resume evidence is archival (4.4).
- There is a shorter path to the first close (section 9).

**Revised 2026-10-13: the founder's rulings** (relayed by C, who holds Horde coordination by the
founder's word of the same day). They settle decisions (a) and (b) of section 11. They add two pieces:
the close offer (section 12) and the closed-session pool (section 13). In his words:

> "Cleaning up Orcs, and sessions with Remote Control open, is always brought to the founder - offer
> him an option to close each, never close them automatically. A closed session's info goes into a
> separate pool that shows closed Orcs by the last 7 days, last 30 days and last 3 months, with
> session handles to restart them easily, built as a clean, self-contained, organized, consumable
> module. Other idle sessions follow the design's leans (report-only first for a day, then closing)."

**Corrected the same day:** the founder narrowed the pool to closed **Orcs only**. A closed Warg
(a subsession or worker) leaves only its closure record (13.1).

Where this text and an older paragraph below disagree, this revision wins. The paragraphs it changes
say so in place.

Planning prose may name terminals and engines. Code may not (CONTRIBUTING 14). Every file path below
respects that.

## 0. What this builds on, and what it is not

This design adds one thing to Horde: a **policy** that decides which idle sessions to close, and
when. Every mechanism it needs is already planned somewhere else, and this design builds on those
plans rather than starting parallel ones:

| existing plan or code | what the reaper takes from it | what the reaper adds or pulls forward |
|---|---|---|
| lifecycle plan, Part 3 and step 28 (the closer) | close after proof: verify the binding, record the transcript length, write a tombstone, then end the session through its handle | the closer's **pre-anchor path** (section 4), built first, because none of today's sessions has an anchor. Step 28 later adds the anchor path to the same module |
| lifecycle step 10 (`core/Observe.ps1`, the classifier) | one pure function over observations, with an `unknown` answer that never closes | its first states, `working`, `waiting-on-human`, `idle` and `unknown`, plus the protections of section 2. Step 10 extends the same file; nothing is built twice |
| lifecycle 4.1 and 4.3 (the transcript port and per-engine capability flags) | per-engine adapters under `agents/<name>/`; `unverified` counts as `no` | four new flags (section 1.4) and an `Idle.ps1` per adapter |
| lifecycle 4.4 (the follower, the one transcript reader) | it will be the only transcript reader once it exists | until step 11 ships, the reaper reads one bounded tail per candidate through the port, the same interim exception that metrics collect has. Once the follower is installed, the reaper reads its stream (H2) instead, and a test enforces it (slice RG) |
| lifecycle 1.2 (admission tiers) | `ramReserveMb`, `commitReserveMb`, `pagingLimit`, `hysteresisMb`, one per machine through the configuration layers | memory-pressure levels derived from those same numbers (5.2), so the machine has one definition of "short of memory" |
| lifecycle 2.6 and step 31 (proof of ownership, the handle method) | end a process by opening it by pid, comparing the creation time read from the handle, and terminating through that handle | nothing new |
| lifecycle step 34 (names repair) | identity proven again before **every** keystroke; skip a busy pane, never wait on it in a loop | the same rule for the graceful exit keys |
| `core/Projection.ps1`, `core/Identity.ps1` | pid plus procStart verdicts (`Get-HordeProcessVerdict`), control files, the registry | a **narrow tick**: Identity plus a tail per candidate, never the whole projection on every tick (I-11) |
| metrics M2, merged as #70 (`horde metrics schedule`) | the scheduled-job seam (`core/Schedule.ps1`), the marker, Horde's folder, refusal without consent, install/status/remove | a second job: "Horde reaper tick" |
| metrics M3 (the event writer, not yet merged) | one file per writer, `seq`, the envelope | the `reaper.*` decision events (5.5) |
| `core/config-keys.json` and the engine-settings layers | `direction: lower-only`, L4 live rules with an `until` | the `reaper.*` keys (5.6) |
| wezfleet `lib/Kill.ps1`, `lib/Delivery.ps1`, `lib/CodexStatus.ps1`, `lib/Activity.ps1` | what the old code learned (section 1, section 4) | ported with a ledger, per CONTRIBUTING 5 |

**What it is not.**

- It does not reclaim orphans: processes with no session, such as pid 5616 (555 MB, no control
  file, I-14) or a `remote-control --help` left running since 2026-10-01 (233 MB). Those belong to
  lifecycle steps 14 (report) and 31 (reclaim).
- It does not close bare-shell panes with no harness in them (pane 26, 126 h, I-15). That is
  lifecycle step 33.
- It does not close sessions that have reported done. That is the lifecycle closer's "close after
  proof".

The reaper closes **live harness sessions that are provably idle and provably Horde's**, and nothing
else.

## Measurements

Every measurement was taken on this machine, read-only, between 01:41 and 02:10 UTC on 2026-10-05,
against WezTerm (instance `gui-sock-15476`). The live sessions run Claude Code 2.1.284 and 2.1.285;
the installed CLI is newer (I-20). Nothing was typed into, sent to or
closed in any pane. The pane screens were read with `get-text` through wezfleet's own reader. The
probe scripts were kept in the session scratchpad and are not shipped.

| id | what | value |
|---|---|---|
| I-01 | memory at 01:41:39 | available 1,227 MB (free 1,155); committed 31,767 of 43,599 MB (headroom 11,832); 1,472 pages/s |
| I-02 | process table | 345 processes, CIM read 263 ms; 10 `claude.exe` with 6,997 MB private in total; 6 `node.exe` with 4,046 MB; no Codex process running |
| I-03 | the live sessions, one row each | the table below |
| I-04 | transcript modification time against its newest timestamped line | for the 7 idle sessions, mtime was 35 to 54 min old, but the newest timestamped line was 2.5 to 5.2 days old. The last line of each was its turn-end line, so the mtime moved with no new event at the end (cause unmeasured). wezfleet census showed these sessions as "SEEN 36m" to "56m" |
| I-05 | control-file status while background agents run | session D's turn ended at 01:40:06.679 with `pendingBackgroundAgentCount` 1; its control file said `busy` (statusUpdatedAt 01:38:49) and still said `busy` at 01:42:45. The 7 other sessions said `idle` |
| I-06 | `pendingBackgroundAgentCount` | on 875 of D's 1,131 turn-end lines. Across the 8 transcripts written in the last 3 days, 1,427 lines carry it, and it is the only `pending*Count` field seen. The last turn-end of each of the 7 idle sessions lacks it (read as 0) |
| I-07 | a mid-turn control | the transcript of the agent writing this document: its last line, at 01:49:30, was an assistant `tool_use` (PowerShell) with no result yet, because that call was running |
| I-08 | descendants | D had 6 (the shells of its tool calls); the 7 idle sessions had 0. An in-process subagent adds no process: the agent writing this document ran inside D's process and showed up only as D's tool shells |
| I-09 | CPU over 10 s | idle sessions 31 to 219 ms; D 484 ms; the orphan 5616 0 ms |
| I-10 | input box, read through wezfleet's parser (`get-text --escapes`, 25 to 87 ms per read) | 8 harness panes: the box was found in all 8. 7 were empty with the cursor at the prompt start. Pane 27 (D) showed 16 characters on the prompt row with the cursor at the prompt start, which wezfleet's cursor rule reads as not typed (a suggestion or a queued line). Pane 26 (bare shell) had no box. **No typed-text control was taken**: planting text in a real pane is forbidden, so that control belongs to the isolated instance. wezfleet took one there on 2026-09-15, and RD re-runs it against the port |
| I-11 | cost of each reader | `Get-HordeProjection -Scope Current`: 31.6 s for 32 sessions, peak working set 285 MB. `core/Identity` (control files plus process table): 580 ms (table 352, files 228), peak working set 158 MB. Transcript tail of 256 KB: 18 to 105 ms per session; 64 KB: 1 to 41 ms. Finding a transcript by id across project folders: 1 to 82 ms |
| I-12 | wake and background tools in 249 transcripts over 6 days | `ScheduleWakeup` 84, `CronCreate` 14, `Monitor` 39, `TaskStop` 72; 2,052 lines with `run_in_background` true |
| I-13 | Codex | no live process. 4 rollouts on disk; the largest pairs every turn start with an end: `task_started` 5, `task_complete` 4, `turn_aborted` 1. The status hook's file is believed for 900 s only, and its Stop event does not fire on a failed or interrupted turn (wezfleet `lib/CodexStatus.ps1`) |
| I-14 | agent processes that are not sessions | pid 5616: no control file, 1 thread, 0 handles, 555 MB private, the same orphan as lifecycle M-07, still alive 5 days later. pid 34972: `claude remote-control --help`, running since 2026-10-01 01:57, 233 MB |
| I-15 | wezfleet census, 6.1 s | pane 18 (session d16b54b2) shown as "(unowned)" from a pane-sessions file, while wezfleet's registry record for that session says owner M. Pane 26: bare shell, 126 h |
| I-16 | Remote Control (review of #84, F-1; replay 02:06 UTC) | 6 of 8 live control files carry `bridgeSessionId`: M, D, I, E, B, J. D1 and imadi-7f do not, and D1's transcript has 0 `bridge_status` lines, so the field tells the two apart. Each `/remote-control` in I's transcript produced a new session URL (3 different ones) |
| I-17 | what follows a turn end (74 transcripts written in the last 8 days, 4,939 turn ends) | Timestamped lines that start no turn: `system/away_summary` 282, `system/local_command` 68, `system/informational` 37, `system/bridge_status` 14, `pr-link` 1,687, `frame-link` 353, `file-history-delta` 50. Untimestamped metadata lines (titles, modes, `bridge-session`, `last-prompt` and others) number in the thousands. Lines that do start or continue work: `user` prompts 4,347, `queue-operation` 9,523, `attachment` 3,296, `user` meta 1,155, `system/scheduled_task_fire` 952, `system/compact_boundary` 21 |
| I-18 | recurring crons and background tasks (review of #84, F-2 and F-4, plus the replay) | `CronCreate` is called with `"recurring":true` (for example `*/10 * * * *` while the founder is out). Monitor's result says "persistent - runs until TaskStop or session end". In 74 transcripts: 1,856 turn ends came while a background Bash, Monitor or agent task was still open, and on 1,625 of them `pendingBackgroundAgentCount` was 0 or absent. At 02:06 D had 2 background tasks open |
| I-19 | queued input | `queue-operation` lines `enqueue`, `dequeue` and `remove`. Counted over the whole file they never balance (B: 1,190 enqueues against 1,184 dequeues and removes), because a process can end with items still queued. Counted since the current process started, they balance for all 8 live sessions |
| I-20 | versions | the live sessions run Claude Code 2.1.284 and 2.1.285 (the control files' `version`); the installed CLI is 2.1.289 (review of #84, F-5). 28 of 224 transcripts from the last 30 days carry several harness versions under one session id, and 0 files mix session ids. M's spans 2.1.268, 2.1.272, 2.1.283 and 2.1.284 |
| I-21 | start-time precision | session D1's control file has procStart 134351746201632411; CIM gives 134351746201632410. That is 1 tick (100 ns) apart, so procStart is compared at the microsecond precision CIM reports (core/Identity), not at the file's own 100 ns |

**I-03, the live sessions.** Owner, role and parent come from wezfleet's registry. Idle age is the
newest timestamped transcript line.

| pid | label | registry origin / owner / role | private MB | WS MB | control status | descendants | newest event | pending agents | box |
|---|---|---|---|---|---|---|---|---|---|
| 8636 | M (Thrall) | user / founder / master | 769 | 367 | idle | 0 | 2.47 d | 0 | empty |
| 22192 | D (wezfleet orc) | user / M / orchestrator | 1,091 | 528 | busy | 6 | 164 s | 1 | not typed (I-10) |
| 2720 | D1 (codex-observability) | fleet / D / - | 633 | 275 | idle | 0 | 5.21 d | 0 | empty |
| 18056 | B (onboarding orc) | user / M / orchestrator | 815 | 340 | idle | 0 | 2.47 d | 0 | empty |
| 17948 | E (client search orc) | user / M / orchestrator | 817 | 361 | idle | 0 | 2.86 d | 0 | empty |
| 19728 | I (config audit orc) | user / M / - | 710 | 311 | idle | 0 | 4.00 d | 0 | empty |
| 17996 | imadi-7f | user / M / session; census says unowned (I-15) | 709 | 285 | idle | 0 | 4.00 d | 0 | empty |
| 33076 | J (bios memory training) | user / (none) / - | 691 | 295 | idle | 0 | 3.24 d | 0 | empty |

---

# 1. Idle, defined per engine adapter

## 1.1 The rule

A session is **idle** only when every one of the following is `known` and agrees. A single
`unknown` makes the session `unknown`, and an unknown session is never closed. This is the same rule
the lifecycle classifier uses (lifecycle 4.3: "unverified never satisfies a requirement").

1. **It is the process its record names.** The harness pid is running, and its creation time equals
   the recorded procStart. procStart is a FILETIME in 100 ns ticks, but CIM reports microseconds, so
   the two are compared at the microsecond (`Get-HordeProcessVerdict` gives `verified`; I-21).
2. **It has no live descendant.** No process in the harness's process tree is alive, apart from
   ones its adapter declares resident (section 1.3).
3. **It is not mid-turn and holds no live work.** All of the following:
   - the harness's own status is not busy;
   - the transcript is at a turn boundary (1.5);
   - no tool call is open;
   - no background agent is pending;
   - no background Bash, Monitor or Workflow task, or task of an unrecognised kind, is open (P12);
   - no queued input is waiting (I-19);
   - no one-shot wake is still due;
   - no recurring cron is live (P8).
4. **Nothing is waiting in its input box.** The box was read and found empty (not unreadable). Text
   in the box lives only in the process's memory, so ending the process loses it just as the exit
   keys would.
6. **It has no Remote Control link** (S8, P11), unless the founder decides otherwise (section 11,
   decision b).
7. **Its harness version has passed the automatic survey** (1.6).
5. **Its last event is older than the idle threshold** for the current memory-pressure level (5.2).
   The age is measured from the newest timestamped transcript line, **never** from the file's
   modification time (I-04).

`waiting` (the harness waits on a human: a permission prompt, a question) is **not idle**. It is
its own state, `waiting-on-human`. It is reported and never closed (settled by the coordinator,
section 11).

## 1.2 The signals, their cost, and the proof that each one tells live from idle

For each signal: how it is read, what it costs, how far it can be trusted, and its measurement on a
known-live and a known-idle session. The known-live session is D (pid 22192): it was holding the
agent writing this document and running its tools. The known-idle sessions are the 7 others in I-03.
Where no live control could be taken, the signal is marked so, and the slice that takes the control
is named.

| # | signal | read from | cost | reliability | live control | idle control |
|---|---|---|---|---|---|---|
| S1 | pid plus procStart | process table (CIM) and the control file | 263 to 352 ms for the whole table, once per tick (I-02, I-11) | exact. Windows reuses pids, so the start time is compared at microsecond precision (core/Identity) | D: verified | 7 of 7 verified. The orphan 5616 has no control file, so nothing ever names it |
| S2 | live descendants | the same table: a walk down `ParentProcessId`, each hop's child created after its parent (lifecycle 2.6) | about 0: same table | strong for children it can see. **Blind to work done inside the harness process**: an in-process subagent has no process (I-08), which is why S3 and S4 exist | D: 6 descendants | 7 of 7: 0 |
| S3 | harness status | the harness's control file (`status`: idle, busy, waiting) | one small file read | strong while S1 verifies the file. A stale file from a dead process once read busy forever (wezfleet issue #26), which S1 prevents. It **does** cover background agents (I-05) | D: `busy`, even after its turn ended, while an agent ran | 7 of 7: `idle` |
| S4 | turn state | the transcript, through the adapter: whether it is at a turn boundary (1.5), the last turn end's `pendingBackgroundAgentCount`, any `tool_use` with no `tool_result` after it, background tasks opened since this process started and not finished (P12), queued input since this process started (I-19), one-shot wakes still due, and recurring crons not deleted (P8). Tasks, crons and queues die with their process, so only lines written since procStart count. A tail is enough for the boundary; tasks, crons and the queue need every line since procStart, which the adapter keeps as a cursor between ticks (lifecycle 4.1) | 1 to 105 ms per candidate (I-11) | strong for what the transcript records. Partial last line: unknown. A pending count absent from the turn-end line is read as 0, which is what 1,427 lines show (I-06). Wakes are common: 84 plus 14 in 6 days (I-12) | D: last turn end has pending 1 (I-06), and 2 background tasks open (I-18). This agent's own transcript: open `tool_use` at 01:49:30 (I-07) | by the replay script (section 8): 6 of 7 at a boundary; I is not (a `user` meta line from its `/remote-control` command follows its last turn end); none has an open task, cron or queue |
| S5 | last-event age | the same tail: the newest line that carries a timestamp with a zone | included in S4 | strong. **Not the modification time**: 7 of 7 idle transcripts had an mtime 35 to 54 min old while their newest event was 2.5 to 5.2 days old (I-04), and wezfleet's SEEN column read those sessions as active 36 to 56 min ago | D: 164 s | 7 of 7: 2.47 to 5.21 d |
| S6 | input box | the host's `text.read` (screen with styles), parsed by the **agent's** adapter, read twice 250 ms apart, the cursor rule applied (wezfleet `lib/Delivery.ps1`) | 25 to 87 ms per read, two reads per candidate (I-10) | good on the screen shapes wezfleet measured. Known gaps: a theme that greys typed text; typing that starts between the last read and the key; stale frames. Unreadable counts as occupied | not taken on the live terminal (planting text is forbidden). wezfleet took it in the isolated instance on 2026-09-15 with a scripted typist; RD re-runs it against the port | 7 of 7: found, empty. Pane 27 shows why the cursor rule is needed (I-10) |
| S8 | Remote Control link | the control file's `bridgeSessionId`; the transcript's `bridge_status` and `bridge-session` lines confirm it | 0: the file S3 already read | strong: the harness writes it. It also answers the engines plan's open question of how to tell, before sending anything, whether a live session has Remote Control on, with no screen read | D: linked | 5 of 7 idle sessions linked (M, I, E, B, J). D1 and imadi-7f are not, and D1 has 0 `bridge_status` lines (I-16) |
| S7 | CPU | `Get-Process` total processor time, twice, 10 s apart | 34 ms per read (lifecycle M-52) | **weak**: idle sessions use 31 to 219 ms per 10 s, D used 484 (I-09). Recorded as evidence only, never a gate | D: 484 ms | 31 to 219 ms |

Signals S1, S2 and S3 come from one process-table read plus small files, so they are the
**pre-filter**: every live session pays for them on every tick, and S8 comes free with S3. S4, S5 and
S6 are paid only by
sessions that pass the pre-filter. A tick on today's fleet therefore costs about 0.6 s and 158 MB at
its peak, against 31.6 s and 285 MB for a full projection (I-11). At 1,227 MB available, that
difference is the difference between a reaper that helps and one that adds to the problem.

## 1.3 Adapter by adapter

**claude-code** (`agents/claude-code/Idle.ps1` and `agents/claude-code/InputBox.ps1`):

- S3 is the control file under the harness's sessions folder (already read by core/Identity).
- S4 and S5 come from the transcript's lines:
  - turn end: `system/turn_duration` and its `pendingBackgroundAgentCount`;
  - tool pairing: `tool_use.id` matched to `tool_result.tool_use_id`;
  - background tasks: a tool result that announces a task (patterns measured: "running in
    background with ID: x", "Monitor started (task x", "agentId: x"), closed by a
    task-notification with status `completed`, `failed` or `killed`, or by `TaskStop`. A
    task-notification that is not terminal, for an id with no recognised start (Workflow today, or
    any future kind), makes the turn state `unknown`;
  - queued input: `queue-operation` enqueues since procStart, not yet dequeued or removed;
  - wakes: `ScheduleWakeup` and one-shot `CronCreate` with their due time, and `CronCreate` with
    `recurring: true` until its `CronDelete`;
  - Remote Control (S8): the control file's `bridgeSessionId`.
- S6 is ported from wezfleet's `ConvertFrom-WfClaudeScreen`, `Split-WfStyledLine` and
  `Test-WfCursorAtPromptStart`, with a ledger.
- Resident children: none are declared today. 0 of 7 idle sessions had a child (I-08). A session
  with a stdio MCP server would have a permanent child and would read as not idle. That fails
  toward keeping it, which is the safe direction. The adapter may later declare such children
  through `Get-AgentProcessClaims` (lifecycle 2.6) once one is measured.

**codex** (`agents/codex/Idle.ps1`):

- S3 is the fleet's status hook file. It is believed for 900 s only, and Stop does not fire on a
  failed or interrupted turn (I-13). So S3 alone can never say "idle" for long enough to matter.
  The adapter answers S3 from the rollout's pairing instead: `task_started` against `task_complete`
  or `turn_aborted` (I-13).
- S4 and S5 come from the rollout tail.
- S6 has no parser yet: wezfleet's reader is Claude-specific.
- **No live Codex session existed to take the live control**, so every Codex idle flag stays
  `unverified`. Codex sessions are therefore reported but never closed, until slice RH measures
  them in the isolated instance.

**Others** (gemini-cli, and GLM, Qwen or DeepSeek through the claude-code harness):

- GLM, Qwen and DeepSeek run through the claude-code harness, so they are read by its adapter
  (lifecycle 4.1).
- gemini-cli gets its own `Idle.ps1` when it arrives. Until it measures its flags, it is
  report-only.

## 1.4 Capability flags

The four flags below join `core/capabilities.json`, port `agent`. Each adapter declares them in its
`agent.json` with evidence. Only a measurement plus a test can make a flag `yes` (lifecycle 4.3).

| flag | meaning | claude-code | codex |
|---|---|---|---|
| `idle.turnState` | the adapter can tell an ended turn from an open one, including pending background work and scheduled wakes | yes: I-05, I-06, I-07 | unverified (I-13: one rollout pairs; no live control) |
| `idle.lastEvent` | the newest event carries a time with a zone | yes: I-04 | unverified |
| `input.box` | the adapter can parse the host's screen text into an empty, typed or unreadable input box | **unverified** until RD re-runs the typed-text control on the port; then yes | unverified |
| `close.keys` | the adapter knows a key sequence that ends the harness cleanly at an empty prompt, and its effect on the transcript is measured | unverified until RF measures it (RE does not need it) | unverified |

A harness whose flags are not all `yes` is **report-only**. The reaper lists its idle sessions, with
the missing flag as the reason, and closes none of them. `close.keys` is needed only by the graceful
ladder of a later slice. The first act slice, RE, ends the process through its handle and sends no
key (section 9).

## 1.5 The turn boundary, measured

A transcript is **at a turn boundary** when its last `system/turn_duration` line is followed only by:

- untimestamped metadata lines, of any kind (titles, modes, `bridge-session`, `last-prompt`,
  `file-history-snapshot` and the rest; I-17), which never change the session's age; and
- timestamped lines from this allowlist: `system/away_summary`, `system/bridge_status`,
  `system/informational`, `system/local_command`, `pr-link`, `frame-link`, `file-history-delta`.

Every other line after the turn end means "not at a boundary", and the session is kept:

- a `user` prompt or `user` meta line;
- a `queue-operation`;
- an `attachment`;
- `system/scheduled_task_fire` (a cron fired, so a turn follows);
- `system/compact_boundary`;
- any kind the adapter has not seen before.

I is the measured example. A `user` meta line from its `/remote-control` command follows its last
turn end, so I is not at a boundary. Widening the allowlist needs a measurement and a test, like any
flag.

The allowlist only decides the boundary. The age is still taken from the newest timestamped line of
any kind (S5), which makes a session look younger, never older.

## 1.6 The harness version, checked automatically per session

The gate is the version **each session runs**, read from its control file's `version` (I-20: the
live sessions run 2.1.284 and 2.1.285, while the installed CLI is 2.1.289). It is not the installed
CLI's version, and not a version measured by hand.

The **survey** is automatic. Every transcript line carries the `version` that wrote it, so for each
version present in a candidate's lines since procStart the adapter checks three things:

- every line kind is one it recognises;
- every turn end is a recognised `turn_duration`;
- every `tool_use` it saw has paired or is still open.

A version that passes on a session's own lines counts as surveyed for that session. One that meets
an unrecognised kind is `unverified` for that session, which makes it report-only and names the
version. The adapter also records surveyed versions in `agents/claude-code/measurements/`, so a
fixture suite pins each one. An auto-update therefore parks only the sessions whose lines actually
changed shape, not every session.

---

# 2. What may never be closed

Each protection is a check in the classifier with its own test, and each test has a mutation that
removes the check and must turn the suite red. Every protection is checked twice: once when the
session is classified, and again just before each action (section 4.3).

| # | protection | how it is decided | test (assertion text) |
|---|---|---|---|
| P1 | **the founder's own sessions, unless he opts in** | the session's registry owner is `founder`, or it has no owner (wezfleet census: "sessions YOU opened and nobody owns"), or its role is `master`. Opt-in is per session: `horde reaper opt-in <session> [--until <t>]` writes an opt-in record keyed by (harness, session id) **and** pid plus procStart, so a new process for that session does not inherit it | "a founder session is kept without an opt-in"; "an unowned session counts as the founder's"; "an opt-in does not survive a new process" |
| P2 | **orchestrators holding running agents** | any of: S3 busy; S4 pending background agents above 0; or a **live child session**, meaning a session whose registry `parent` or `owner` is this one and which S1 verifies as running. Measured: D has pending 1 and a live child, D1 (I-03) | "an orchestrator with a pending background agent is kept"; "an orchestrator with a live child session is kept"; "a child session that is not running does not hold its parent" |
| P3 | **unsent input** | S6 is typed, or unreadable, or the two reads disagree | "a typed box is kept"; "an unreadable box is kept"; "two disagreeing reads are kept" |
| P4 | **a live child process** | S2 above 0 | "a session with a live descendant is kept"; "a descendant older than its parent is not counted as a descendant" (pid reuse) |
| P5 | **sessions Horde did not start** | there is no Horde **claim** (section 3) whose pid and procStart equal the live process. Never decided by name, title, label or pane | "a session with no claim is never eligible"; "a claim whose procStart differs from the live process is void"; "a session whose name matches a claimed one is not thereby claimed" |
| P6 | **conflicting ownership** | two stores give different owners for one session (I-15: pane-sessions says unowned, the registry says M) | "conflicting owners are unknown and kept" |
| P7 | **waiting on a human** | S3 `waiting` | "a waiting session is reported, never closed" |
| P8 | **a pending wake or a live recurring cron** | S4 finds either of these since procStart:<br>- a `ScheduleWakeup` or one-shot `CronCreate` whose time, plus one tick, has not passed;<br>- a `CronCreate` with `recurring: true` and no matching `CronDelete`.<br>A recurring cron has no single due time. A daily one leaves the session idle for 23 h between fires (I-18), so the age rule cannot protect it, and closing the process silently cancels the loop | "a session with a due wake is kept"; "a session with a recurring cron and no CronDelete is kept"; "a CronDelete releases its cron"; "a cron from before this process started does not hold it" |
| P9 | **not resumable** | the harness's `resume` capability is not `yes`, or the resume check of 4.1 fails | "a session that cannot be resumed is kept" |
| P10 | **an engine or host flag not `yes`**, or a version not surveyed | 1.4, 1.6, and section 6's host flags | "an unverified flag keeps the session and names the flag"; "an unsurveyed version keeps the session and names the version" |
| P11 | **a Remote Control link** | S8: the control file has a `bridgeSessionId`. Closing ends the founder's phone and web entry to the session. Resume does not restore the link: `--resume` and `--remote-control` are separate flags, whether they combine is unmeasured (engines E9), and each `/remote-control` issues a new URL (I-16). A draft on the phone is invisible to S6. **Never closed automatically** (founder, 2026-10-13, section 11 (b)). It is closed only on his answer to a close offer (section 12). The closure record then stores the bridge id and the remote name | "a session with a bridgeSessionId is kept"; "a session without one is not held by this rule" (the control is D1) |
| P12 | **a live background task** | S4 finds a background Bash, Monitor or agent task opened since procStart and not finished. Measured: on 1,625 of 1,856 turn ends with such a task open, `pendingBackgroundAgentCount` was 0 or absent (I-18), so P2's pending count does not cover them. A non-terminal task-notification of an unrecognised kind (Workflow today) is `unknown`, which also means kept. A task that never reports completion keeps its session forever: safe, and `horde reaper status` lists such sessions | "an unfinished background Bash task holds the session"; "an unfinished Monitor holds the session"; "a task-notification of an unrecognised kind is unknown"; "a completed task releases the session" |
| P13 | **queued input** | S4 finds a `queue-operation` enqueue since procStart with no dequeue or remove (I-19). It is held in memory and would be lost | "a queued message keeps the session" |
| P14 | **an Orc** (founder, 2026-10-13) | the session is an orchestrator. That holds if any of these is true:<br>- its registry role is an orchestrator role;<br>- its label is one the registry gives orchestrators;<br>- it is the registry `parent` or `owner` of any other session, live or not.<br>Missing or conflicting role facts count as an Orc (P6's rule: unknown is kept). Never closed automatically, at any pressure level. It is closed only on the founder's answer to a close offer (section 12) | "an orchestrator is never closed automatically"; "a session that owns another session counts as an Orc"; "an unknown role counts as an Orc"; "an accepted offer lifts P14 for that process only" |

---

# 3. Ownership: a claim by pid plus start time

Horde started none of today's sessions: wezfleet started all of them (lifecycle O6). If ownership
meant only "Horde spawned it", the reaper would have nothing to close until lifecycle step 27 ships.
So ownership is a **claim**: a Horde-owned record, `<HordeHome>\store\reaper\claims\<harness>-<sessionId>.json`,
created with `CreateNew` and holding:

- the harness, the session id, the harness pid and its procStart;
- the source: `spawn`, `adopt` or `opt-in`;
- who made it and when;
- for an adoption, the registry facts it relied on.

A claim is valid only while its pid plus procStart equals the live process (S1). A new process,
even one resuming the same session id, needs a new claim.

- **`spawn`** claims come from Horde's own spawn path once it exists (lifecycle step 27, from the
  anchor's containment record). They are the strongest.
- **`adopt`** claims are how today's fleet becomes Horde's. The first slices ship **manual adoption
  only**: `horde reaper adopt <session>`. It refuses unless all of these hold:
  - wezfleet's registry gives the session an owner that is an orchestrator label (not `founder`,
    not empty);
  - its control file verifies by pid plus procStart;
  - no other store contradicts its ownership (P6).

  Whether the reaper may adopt such sessions **automatically**, including the orchestrators M owns,
  is founder decision (a) (section 11). `reaper.adopt` is not added until he answers it.
- **`opt-in`** claims are the founder's opt-in for his own sessions (P1).

The claim store is a new Horde store. It gets a row in `core/ownership.json` (store `H6`) and a
schema, and is written only by the reaper's commands. Nothing reads a claim as identity: identity is
always the live pid plus procStart.

---

# 4. Closing: lossless, graceful first

## 4.1 Before anything is sent: the closure record

The closer writes a **closure record** first, with `CreateNew`:
`<HordeHome>\store\closures\<harness>-<sessionId>-<utc>.json`. This is lifecycle store H3, the
tombstone. If the write fails, nothing is closed. The record holds:

- **who**: harness, session id, pid, procStart, name, registry label, owner and parent, the claim it
  relied on;
- **where**: host, instance, handle;
- **what the close loses** (4.4): the Remote Control bridge id and remote name if the founder has
  allowed a linked session; the pane and its registry mapping;
- **how to resume**: the working directory, and the exact resume argv the agent adapter renders
  (claude-code: `claude --resume <id>`, run from the directory whose project key names the
  transcript's folder; codex: `codex resume <id>`). Lifecycle 3.1's binding replaces this field once
  it exists;
- **what was on disk**: the transcript path, file id, length, a hash of its last 4 KB, and the
  newest event's id and time;
- **why**: the decision id (5.5), the pressure level, the idle age, every signal with its source and
  age;
- **state**: `closing`, later `closed`, `close-failed` or `close-abandoned`.

**Resumable, checked before closing.** The agent adapter answers `Test-AgentResumable` from the
record:

- claude-code: the transcript exists in the folder that the working directory's project key names
  (core/Identity already derives that key). If the session was started from another directory,
  `--resume` from the recorded one would not find it, so the session is kept (P9);
- codex: the rollout named for the session id exists.

The adapter cannot prove more without starting a process, and it does not need to. The archival
evidence of 4.4 already shows that resume appends to the same file. A later slice's isolated round
trip proves only the exit mechanics.

**Flushed, checked before closing.** All of these must hold:

- the transcript ends with a newline;
- its length is unchanged across two reads 2 s apart. The worst measured write latency is 0.53 s
  (lifecycle M-50), so 2 s is nearly four times that;
- it is at a turn boundary (1.5), with no pending background work, no open task, no live recurring
  cron and no queued input.

Otherwise the session is not idle after all, and it is kept.

## 4.2 The ladder

At every step below, "re-verify" means all of the following, read fresh just before acting:

- S1 (identity);
- S2 (descendants);
- S3 (status);
- S6 (input box);
- the transcript length;
- the claim.

**Any change stops the close.** The state becomes `close-abandoned`, with the change as the reason.

1. **Graceful: the harness's own exit keys.** The host sends the adapter's `close.keys` sequence,
   re-verifying before **each** key (lifecycle step 34's rule). For claude-code this is Ctrl+C, a
   pause, then Ctrl+C again, as in wezfleet's `Stop-WfSessionPane` rung 1. Slice RF measures it, on
   the versions then running, before the flag goes `yes`. Why Ctrl+C is safe only after S6: **at a prompt that holds
   text, Ctrl+C clears the text.** That is exactly the loss P3 exists to prevent, so the box is
   re-read immediately before each key.
   - Then wait up to 12 s (wezfleet's value, lifecycle 2.2) for the **process** to exit, judged by
     pid plus procStart, never by the pane disappearing.
2. **Fallback: end the process through its handle.** If the process is still alive after 12 s,
   re-verify, then:
   - open the process by pid;
   - compare the creation time read **from the handle**;
   - terminate through that handle (lifecycle 2.6).

   Ending the process is safe here because the session is idle: its transcript is append-only and
   flushed (4.1), and it has no descendants. Its in-memory state outside the transcript (a pending
   wake, a queued prompt) is excluded by P8 and P3.
3. **The pane.** Once the harness has exited, the pane holds the shell that started it (lifecycle
   O3). The host closes the pane only when all of these hold:
   - the host's `kill` is `yes`;
   - the pane's program is no longer the harness;
   - the pane is not the last one in its window. wezfleet's guard: closing the last pane destroys
     the window, and window churn hung the GUI on 2026-08-16.

   Otherwise the pane is left open and reported. A 60 MB shell (lifecycle M-10) is not worth an
   unproven close.
4. **If the fallback fails too**, for example access is denied or the process is still alive:
   - the state becomes `close-failed`, with the reason;
   - the decision event records it;
   - that session is not tried again for 24 h (an **estimate**);
   - the failure is shown in `horde reaper status`.

   There is no third rung.

**The first act slice (RE, section 9) runs rung 2 only.** It sends no key and closes no pane, for
three reasons:

- Rung 1 is the one step that can destroy typed text.
- It buys nothing that a handle terminate does not: the transcript is append-only and flushed, and
  no SessionEnd hook is configured on this machine (review of #84), so no hook is skipped.
- It needs host write verbs (`keys.send`) and the socket question (5.1), which would put them on the
  critical path.

Rungs 1 and 3 arrive later as an improvement, not as a gate.

## 4.3 After the close: verified, not assumed

The closer:

- confirms that pid plus procStart is gone;
- confirms that the transcript has the same file id, a length at least the recorded one, and the
  same hash over the recorded last 4 KB, so nothing that was flushed has been lost;
- sets the record to `closed`;
- writes the decision event.

A transcript that came back shorter or replaced sets the record to `close-lossy`, raises an alert,
and **switches the reaper to report mode** (5.4). That should be impossible. If it happens, the
design is wrong, and nothing more should be closed.

**Telling the owner.** The owning orchestrator learns of the close from `horde reaper closed` and
the closure record until lifecycle step 13's mailbox exists. After that, it learns through that
mailbox. Nothing types into the owner's pane to tell it.

**Telling wezfleet.** wezfleet's registry still names the closed session's pane. wezfleet's delivery
refuses a pane with no input box, so mail to the reaped session will not be typed into the leftover
shell. It fails instead (review of #84, F-7). The closure record is the place wezfleet should read,
and section 10 asks for it.

## 4.4 What "lossless" covers, and what it does not

**Restored by resume: the conversation.** The evidence is archival, measured over real use rather
than staged. 28 of 224 transcripts from the last 30 days carry several harness versions under one
session id, and 0 files mix session ids (I-20). M's spans 2.1.268, 2.1.272, 2.1.283 and 2.1.284. A
process runs one version, so each of those files was resumed, and every resume appended to the same
file.

**Not restored, and therefore protected or recorded:**

| lost on close | why | how the design handles it |
|---|---|---|
| the Remote Control link and its URL | `--resume` does not re-enable the bridge, and each `/remote-control` issues a new URL (I-16) | P11 keeps linked sessions unless the founder accepts a close offer (section 12). Then the record, and for an Orc the pool entry (section 13), store the bridge id and the remote name, so a restart can ask for a new link under the same name |
| session crons, `ScheduleWakeup` and Monitors | they live inside the process | P8 and P12 keep any session that holds one |
| queued input and an unsent box | in memory only | P13 and P3 |
| the pane and wezfleet's registry mapping | the pane is the host's | recorded in the closure record; section 10 |

---

# 5. When it runs

## 5.1 Always on, as a scheduled tick

The tick is a second job through `core/Schedule.ps1`, called "Horde reaper tick". It follows the
precedent metrics M2 set:

- it lives in Horde's folder and carries the marker;
- it runs at low priority, with `IgnoreNew`;
- `horde reaper schedule install|remove|status` manages it;
- install is refused unless the mode (5.4) is `report` or `act`.

The schedule:

- every 5 min (an **estimate**);
- stopped after 4 min;
- one tick at a time: `IgnoreNew` at the scheduler, plus a machine lock (section 7, F5).

**Unproven, and measured in RE** (section 9). The question is narrow because RE only terminates
through a handle: can a task with S4U logon and a Limited token (no visible session, no window
flash, as metrics uses) call `OpenProcess(PROCESS_TERMINATE)` on a process of the same user in
another logon session? Measured on a stand-in process the test starts itself.

- If it can, RE runs under S4U.
- If it cannot, the act half runs as an interactive task. If every interactive form flashes a
  window every 5 minutes, that goes to the founder.

Two other questions are off the critical path:

- Whether S4U can reach the terminal host's socket matters only to the later graceful slice.
- The report half, and the input box read the report needs, use files, the process table and the
  host's `text.read`. RC measures that read under S4U.

## 5.2 Memory-pressure levels shorten the threshold

The levels come from the machine's resolved admission tier (lifecycle 1.2), so the machine has one
definition of "short of memory". The symbols:

- `A` is available MB;
- `H` is commit headroom (limit minus committed);
- `P` is pages/s averaged over the tier's `pagingWindowSec`;
- `R`, `Cr`, `h` and `PL` are the tier's `ramReserveMb`, `commitReserveMb`, `hysteresisMb` and
  `pagingLimit`.

The numbers in brackets are at `standard`.

| level | holds when | idle threshold (minutes, estimates) | what a tick does |
|---|---|---|---|
| `calm` | `A >= R + 2h` (3,584) and `H >= Cr + 2h` (4,608) | 120 | closes every eligible session over the threshold, up to the per-tick cap |
| `tight` | not calm, `A >= R` and `H >= Cr` | 60 | the same |
| `constrained` | `A < R` or `H < Cr` (the admission gate's own `constrained`) | 30 | closes in priority order (5.3) until `A >= R + h` (2,816) and `H >= Cr + h`, re-reading the counters after each close |
| `critical` | `A < R / 2` (1,024) or `H < Cr / 2` or `P > PL`, or a harness reap notice in the last 10 min | 15 | the same, with the cap raised by 2 |

Today's reading (I-01): available 1,227 MB, below 2,048, so `constrained` with a 30-min threshold.

Why these thresholds:

- 120 min at `calm` keeps "all the time" honest without closing an orchestrator that is waiting for
  a reply to a long message.
- 30 at `constrained` matches the window Claude Code's own reaper treats as recent terminal input
  (lifecycle M-30). The reaps observed happened 31 and 32 min after the last prompt (M-31).
- 15 at `critical` is the floor, because a close is lossless and resumable, while the alternative at
  that level is the harness killing background work.

The founder's sessions are excluded at every level (P1). Every threshold is a starting value (the
coordinator's decision), tuned by the regret measure in 5.4 and set through the configuration
layers (5.6). If the founder answers decision (a) with yes, orchestrators use twice the threshold.

**The first act slice (RE) adds a floor of 24 h of idleness at every level, and a cap of 2 closes
per tick.** These keep regret low while the regret measure gathers data. Lowering either is a
configuration change, made with that data.

## 5.3 Order: idlest and largest first

Under pressure, eligible sessions are sorted by idle age in whole hours, oldest first, then by
private bytes, largest first.

Why buckets rather than a product of age and size:

- a session idle for days goes before one idle for minutes, whatever their sizes;
- among sessions idle about as long, the largest frees the most;
- the order stays easy to explain in `horde reaper why`.

Per-tick cap: 2 closes in RE, 4 afterwards (an **estimate**; lifecycle M-21 closed 4 at once and freed 2,846 MB of
commit). Under pressure the closes run one at a time, with the counters re-read between them, so
the reaper stops as soon as the target is met.

## 5.4 Modes: off, report, act

| mode | what a tick does |
|---|---|
| `off` (the shipped default) | nothing; the scheduled job refuses to install |
| `report` | classifies and records every decision as `would-close` or `keep`. Its call graph reaches no acting verb, which the `effects` tripwire (lifecycle step 4) checks |
| `act` | closes what report would have closed |

**Report before act.** `horde reaper mode act` refuses unless all of these hold:

- report mode has run at least N ticks, with N = 288 to start (a day of 5-minute ticks, an
  **estimate**). The coordinator's decision: the gate is evidence, not days on a calendar;
- those ticks recorded at least 20 `would-close` decisions (an **estimate**), each followed by its
  10-min misread window;
- no misread was recorded in them.

`horde reaper status` shows progress against all three.

What counts against the reaper:

- **Misread.** A session the reaper marked `would-close` or `closed` writes a new non-user event
  within 10 min, with no new user prompt before it. It was working, and the reaper misread it.
- **Regret.** A user prompt reaches, or resumes, a session within 30 min of `would-close` or
  `closed`. It was idle, but someone still wanted it. Regret is not a misread. Regret raises that
  level's threshold by 25 percent as a live L4 rule with a 7-day `until`, the same pattern the
  admission tuner uses (lifecycle 1.4). Lowering a threshold is only ever proposed.
- **The circuit breaker.** In `act` mode, one misread or one `close-lossy` switches the mode back to
  `report` at L4 and alerts. Only the founder sets `act` again.

## 5.5 Every decision recorded

Each tick writes one `reaper.tick` event:

- the counters (`A`, `H`, `P`) and the level;
- the mode, the tier, and the reaper's version;
- the number of sessions seen, pre-filtered, classified and acted on;
- the tick's wall time and peak working set.

Each classified session gets one `reaper.decision` event:

- the session (harness, id), its label, and the claim;
- the verdict: `close`, `would-close`, `keep`, `waiting-on-human` or `unknown`;
- the reason codes (P1 to P13, plus `not-at-boundary`, `threshold-not-reached` and
  `version-unsurveyed`);
- every signal, with its source store, file, offset or field, and its age;
- the idle age, the private and working-set MB, and the order rank.

Each close also gets a `reaper.close` event with its outcome and the closure record's path.

These events are content-free (no message text, no paths inside a transcript beyond the file
itself) and operational. Like lifecycle's `obs.*` stream, they are written whatever `metrics.level`
says. They use the metrics event envelope through M3's writer, so `horde metrics report` sees them
next to the rest. **No act without its record**: if the writer cannot write, the tick acts on
nothing.

## 5.6 Configuration

New keys in `core/config-keys.json`, resolved through the existing layers:

| key | layers | direction | default (L0) |
|---|---|---|---|
| `reaper.mode` (`off`, `report`, `act`) | L0, L1, L2, L4 | L2 lower-only (towards `off`). L4 needs an `until` to go above L1. The breaker writes at L4 | `off` |
| `reaper.idleMinutes.calm`, `.tight`, `.constrained`, `.critical` | L0, L1, L2, L4 | L2 raise-only (a project may make the reaper more patient, never quicker) | 120, 60, 30, 15 |
| `reaper.orchestratorFactor` | L0, L1, L4 | any | 2 |
| `reaper.maxClosesPerTick` | L0, L1, L4 | any | 2 in RE, 4 later |
| `reaper.minIdleHours` | L0, L1, L2, L4 | L2 raise-only | 24 in RE |

The founder answered decisions (a) and (b) on 2026-10-13. These keys are added with them:

| key | layers | direction | default (L0) |
|---|---|---|---|
| `reaper.adopt` (`manual`, `auto`) | L0, L1, L4 | any | `manual` until RC's trial ends, then `auto`. An automatic adoption lets the reaper report and offer an Orc's workers. It never lifts P14 or P11 |
| `reaper.offer.enabled` | L0, L1, L4 | any | `true` once RO merges |
| `reaper.offer.minIdleMinutes` | L0, L1, L2, L4 | L2 raise-only | 120, an **estimate**. An Orc or linked session idle this long is offered |
| `reaper.offer.snoozeHours` | L0, L1, L4 | any | 24, an **estimate**. After "keep", the same process is not offered again for this long |
| `pool.retentionDays` | L0, L1 | raise-only | 92, the "last 3 months" window |

**There is deliberately no key that closes an Orc or a linked session without an offer.** The
founder's ruling is a rule, not a default. A key would let one settings file undo it.

L3 (a run spec) and L5 (a spawn flag) may not set any `reaper.*` key. Memory is a per-machine fact,
and one run must not change how patient the reaper is with everyone else's sessions (the admission
tier's rule, lifecycle 1.3). No environment variable changes any of them.

**Commands.** All are new under `cli/commands/reaper.ps1`, each with an end-to-end scenario:

| command | effect |
|---|---|
| `horde reaper run [--json]` | one tick in the configured mode. `--report` forces report |
| `horde reaper status` | mode, level, last tick, would-close and close counts, failures |
| `horde reaper why <session>` | that session's last decision and every signal behind it |
| `horde reaper closed [--json]` | the closure records |
| `horde reaper mode off\|report\|act` | sets the mode at L1, with act's refusals |
| `horde reaper adopt <session>` | writes an adopt claim |
| `horde reaper opt-in <session> [--until]` | writes an opt-in claim for a founder session |
| `horde reaper schedule install\|remove\|status` | manages the scheduled tick |
| `horde reaper offers [--json]` | the open close offers and their state (section 12) |
| `horde pool list [--window 7d\|30d\|3m] [--json]` | the closed-session pool (section 13) |
| `horde pool show <entry>` | one pool entry, with its restart handle |
| `horde pool restart <entry>` | resume a closed session from its pool entry (13.4) |

---

# 6. Host-agnostic and engine-agnostic

**Engines.** Core names no engine. Everything harness-specific goes through the AgentPort, and
`core/Idle.ps1` (the classifier, in `core/Observe.ps1` as lifecycle step 10 names it) only combines
answers:

- `agents/<name>/Idle.ps1`: S3, S4 and S5;
- `agents/<name>/InputBox.ps1`: S6, which turns the host's screen text into empty, typed or
  unreadable;
- `close.keys` in `agent.json`, as key names;
- `Test-AgentResumable` and the resume argv.

A harness with no adapter is `unknown: no idle adapter for <harness>`, and its sessions are counted
in `horde reaper status`, so the gap is visible rather than silent.

**Hosts.** Core names no terminal. The reaper needs these host capabilities, through the existing
HostPort vocabulary plus one new name:

| capability | used for | WezTerm now | tmux and psmux | VS Code |
|---|---|---|---|---|
| `list`, `instance.startedAt` | the pane holding a session, in the instance the record was written in | Phase 3 step 3 | `list-panes -a -F`, server pid in the instance id (`hosts/tmux/Dialect.ps1`) | through an extension |
| `pid` | the pane's program pid, to tell the harness from the shell after it exits | unverified; RF measures | `#{pane_pid}` | likely yes |
| `text.read` with styles | S6 | `get-text --escapes`, measured by wezfleet; RD measures it for Horde | `capture-pane -e -p` | **likely no**, which makes S6 unknown: report-only until an engine offers a non-screen input-box signal |
| **`keys.send`** (new) | the graceful exit keys: named control keys only, never text | `send-text` with control bytes, as wezfleet's ladder does; RF measures | `send-keys C-c` | extension |
| `kill` | closing the emptied pane, with the last-pane guard | `kill-pane`; RF measures | `kill-pane` | extension |

**Why a new `keys.send` and not `text.send`.** `text.send` can type anything, and lifecycle step 4's
tripwire treats it as an acting verb. The reaper needs a far smaller verb: a fixed vocabulary of key
names (`ctrl-c`, `escape`) that cannot carry text. A host declares `keys.send` separately, and a test
asserts the reaper's call graph reaches `keys.send` and never `text.send`.

**Which host instance to ask.** Phase 3 step 2 finds "this session's host" from the markers the
calling process carries. A scheduled tick carries no markers. So the reaper needs a second discovery
mode: every declared host's live instances, each pinned to its own socket. A pane is acted on only
in the instance that its stored handle was written in (the projection's rule P-17). This is a change
to Phase 3 step 2's contract, flagged in section 10.

---

# 7. Failure matrix (written before rollout, CONTRIBUTING 15.8)

Each row is a test, written before the code it guards. "Kept" means no keystroke, no terminate and
no pane close, plus a decision event that says why.

| # | failure | what could go wrong | what the design does | test |
|---|---|---|---|---|
| F1 | **misread idle: the session is working** | an in-process subagent with no child (I-08); a tool running without output; mtime-based age (I-04); a stale status file | S2, S3 and S4 must all agree; a pending count, an open tool or busy keeps it; age is never read from mtime; everything is re-verified before each key (4.2); report mode comes first, with the misread detector; the act-mode breaker; at most 2 closes per tick in RE, 4 later | "a session whose transcript mtime is fresh but whose last event is old is aged by the event"; "an open tool call keeps the session"; "a busy status keeps a session whose turn ended"; "activity arriving between classification and the first key abandons the close"; "a misread in act mode switches to report" |
| F2 | **pid reused** | a recorded pid now belongs to another process; a parent pid reused in the descendant walk | identity is pid plus procStart at microsecond precision; claims are void on a mismatch; the walk requires each child to start after its parent; terminate compares the creation time read **from the handle**; the test harness's killer acts only on what the test created (CONTRIBUTING 9) | "a reused pid is never terminated" (the fixture points the pid at a process the test owns and records, never kills); "a claim with another procStart is void"; "a reused parent pid does not make a descendant" |
| F3 | **the host has gone** | the terminal crashed or restarted; a handle now names another pane; the socket is dead | host unknown or not running means keep. A handle written before the instance started means keep. No call may auto-start a host (`--no-auto-start`, wezfleet `lib/Hosts.ps1`). Processes left without a host are orphans for lifecycle step 14, not the reaper's | "an unreachable host keeps every session"; "a handle from another instance is never acted on"; "the host is never started by a reaper call" |
| F4 | **the transcript adapter is missing** | a new harness, a moved store, a format change | no adapter, or a flag not `yes`, means `unknown` and kept, counted in status; a tail that does not parse is unknown; the version gate is the session's own version from its control file, surveyed automatically on that session's own lines (1.6) | "a harness with no idle adapter is report-only"; "an unparseable tail keeps the session"; "a session whose own lines carry an unrecognised kind is report-only"; "an installed CLI newer than the session's version does not park the session" |
| F5 | **two reapers at once** | the scheduled tick and a manual run; two machines' homes; wezfleet's own closers (`closeOnDone`, `cleanup -Apply`, `kill`); Claude Code's own reaper | `IgnoreNew` at the scheduler; a machine lock at `<HordeHome>\run\reaper.lock` (`CreateNew`, holding pid plus procStart, stale only when that process is gone by S1); a per-session close claim with `CreateNew` before the closure record; re-verify before each act, so a session another closer took is `gone-elsewhere` and is never a second target | "two ticks, one close"; "a stale lock from a dead reaper is taken over"; "a live lock is never taken over"; "a session closed by another tool between classify and act is recorded gone-elsewhere" |
| F6 | **the clock** | a wall-clock jump (correction, manual change); sleep or hibernate making every session look hours older; a timestamp in the future; a time with no zone | ages use UTC times with a zone only (`ConvertTo-HordeUtcTime`), and a future event (beyond 5 s, `HordeClockSkewSeconds`) is unknown. **Sleep**: idle age is measured from the later of the newest event and the machine's last resume from sleep or hibernate, so the first ticks after the lid opens cannot close sessions that "aged" while the machine slept. **Jumps**: each tick stores, in the reaper's state file, its wall time and `QueryUnbiasedInterruptTime` (which, unlike `GetTickCount64` and `Environment.TickCount64`, excludes time asleep). Each tick is a new process, so the value must persist between ticks. If the wall time moved more than 60 s further than the unbiased time since the last tick, **that tick runs in report mode** | "a future timestamp is unknown"; "a time without a zone is unknown"; "a tick after a wall-clock jump does not act"; "a session's age starts no earlier than the last resume from sleep"; "the jump check uses a counter that excludes sleep" (a fixture with a 2-h sleep: the tick-count reading shows no jump, the unbiased reading does) |
| F7 | the reaper is killed mid-close | the harness's own reaper, the time limit, a crash | the closure record is written as `closing` before the first key; the next tick reconciles: process gone means `closed` after the 4.3 checks; process alive means `close-abandoned`, then classified afresh | "a closing record with the process gone becomes closed after verification"; "a closing record with the process alive is abandoned, not resumed mid-ladder" |
| F8 | the decision cannot be recorded | the metrics writer is missing or the disk is full | no act without its record; the tick reports the failure and exits non-zero, so the scheduler's last result shows it | "a tick whose decision write fails acts on nothing" |
| F9 | the reaper itself adds memory pressure | a full projection takes 285 MB and 31.6 s (I-11) | the narrow tick: the identity pre-filter (158 MB, 0.6 s), a tail read only for candidates; the tick's own peak working set is recorded in `reaper.tick`, and a suite pins it within 120 MB of PowerShell's floor (the metrics M2 measure) | "a tick on 40 fixture sessions stays within its memory bound" |
| F10 | a lost close: the session cannot be resumed | the wrong directory, a moved transcript | the resume check before closing (P9); the record holds the exact argv; the archival evidence that resume appends to the same file (4.4); and what resume cannot restore is protected (P8, P11, P12, P13) | "a session whose transcript is not in its directory's project folder is kept"; the later graceful slice's e2e "a reaped session resumes into the same transcript" |

---

# 8. Replay against today, computed from the rules

The replay is the script in Appendix A, run read-only at 02:06:55 UTC on 2026-10-05. It applies
these rules from their written form:

- S1, S3 and P1;
- P2 (status, pending agents, live child sessions from the registry's `parent`);
- P4 (descendants, each child created after its parent);
- the turn boundary (1.5);
- P8 (crons since procStart);
- P11 (`bridgeSessionId`);
- P12 (background tasks since procStart);
- P13 (queue since procStart).

Two rules are applied by hand from the measurements: P3 from I-10 (every box empty) and P6 from I-15.
Memory was `constrained` (available 1,313 MB), so RE's 24-h floor is the binding threshold. Script
output, one line per session (labels shortened):

```
 125.3h pid=2720   D1        owner=D       v=2.1.284 privMB=634  -> ELIGIBLE once adopted
  96.4h pid=17996  imadi-7f  owner=M       v=2.1.285 privMB=706  -> ELIGIBLE once adopted
  96.3h pid=19728  I         owner=M       v=2.1.285 privMB=704  -> P11 Remote Control linked;
                                                                    not at a turn boundary: user/meta
  78.0h pid=33076  J         owner=(none)  v=2.1.285 privMB=695  -> P1 founder's own; P11
  69.0h pid=17948  E         owner=M       v=2.1.284 privMB=818  -> P11 Remote Control linked
  59.6h pid=8636   M         owner=founder v=2.1.284 privMB=785  -> P1; P2 live child sessions (5); P11
  59.6h pid=18056  B         owner=M       v=2.1.284 privMB=807  -> P11 Remote Control linked
   live pid=22192  D         owner=M       v=2.1.284 privMB=1084 -> P2 busy, pending 1, live child D1;
                                                                    P4 descendants 8; P11; P12; not at a boundary
```

| session | verdict | why |
|---|---|---|
| D1 (2720) | **would close** once adopted (634 MB) | Every rule passes. The trailing `system/away_summary` line is allowlisted (1.5), so the first draft's claim that D1 was "not at a turn end" was wrong about the rule, not about D1. Its owner D is live and busy; the decision event names that, and section 11 notes it |
| imadi-7f (17996) | keep | P6: the registry says owner M, a pane-sessions file says unowned (I-15) |
| I (19728) | keep | P11; also not at a turn boundary |
| E (17948), B (18056) | keep | P11 only. If the founder answers yes to both decision (a) and decision (b), they become eligible: 1,625 MB |
| J (33076), M (8636) | keep | P1, plus P11 |
| D (22192) | keep | working |

**So today the reaper closes D1 alone, 634 MB.** The first draft's "four closes, 2,975 MB" was not
computed from its own rules: it missed P11 for I, E and B, and it never applied the boundary rule
(review of #84, F-3). The rest depends on the founder's two open decisions. Until RD and RE land,
this table is the `would-close` report, and the founder can act on it by hand.

---

# 9. PR slicing

One concern per pull request, in order. Each pull request has:

- its tests written first;
- its mutation spec under the owning folder's `test/mutations/`;
- the CONTRIBUTING 15 levels: the touched suites plus `Mutate.ps1 -Changed` each review round, then
  the full suite and the changed-target specs once, on the merge result (every spec nightly).

Anything that terminates a process, sends a key or closes a pane is tested only on processes and
panes the test created, in the isolated host instance (CONTRIBUTING 3), with the guarded killer of
CONTRIBUTING 9.

**Five pull requests to the first automatic close** (the reviewer's path, adopted):

| # | pull request | depends on | tests first (assertion text) | mutation spec (each must turn red) |
|---|---|---|---|---|
| R0 | this design | - | - | - |
| **RA** | **the pure readers** (formerly R1, R2 and R3, merged). The flags `idle.turnState`, `idle.lastEvent`, `input.box` and `close.keys` in `core/capabilities.json`, plus the per-version survey (1.6). `agents/claude-code/Idle.ps1`: the turn boundary with its allowlist (1.5), pending agents, open tools, background tasks with unrecognised kinds as unknown (P12), queue (P13), one-shot wakes and recurring crons (P8), the bridge (S8), and newest-event age; lines since procStart for tasks, crons and the queue. `agents/codex/Idle.ps1`: rollout pairing, flags `unverified`. Fixtures cut from real transcripts with neutral content | - | "an open tool call is mid-turn"; "a pending background agent holds the turn"; "an unfinished background Bash task holds the session"; "an unfinished Monitor holds the session"; "a non-terminal task-notification of an unrecognised kind is unknown"; "a recurring cron with no CronDelete holds the session"; "a cron from an earlier process does not"; "a queued message holds the session"; "an away_summary after a turn end is still at the boundary"; "a scheduled_task_fire after a turn end is not"; "an unknown line kind after a turn end is not"; "age comes from the newest timestamp, never the mtime"; "a bridgeSessionId is reported"; "a version whose lines carry an unrecognised kind is unsurveyed"; "a partial last line is unknown"; "a time with no zone is unknown"; codex: "task_started without task_complete or turn_aborted is mid-turn"; "the status file alone never says idle" | read the mtime; treat a pending count above 0 as 0; drop task pairing; treat an unrecognised task kind as finished; treat a recurring cron as one-shot; count crons from before procStart; add `scheduled_task_fire` to the allowlist; gate on the installed CLI's version; codex: pair only on task_complete |
| **RB** | **the classifier, claims and pressure** (formerly R5, R6 and R7). `core/Observe.ps1` (lifecycle step 10's first states) with P1 to P13. Store H6 with its schema and ownership row; `horde reaper adopt` (manual only) and `opt-in`. `core/Pressure.ps1` from the counters and the resolved admission tier, with the order and the `reaper.*` keys | RA; lifecycle step 17 (the tier keys); engine-settings Half A | one assertion per row of section 2; "one unknown signal makes the session unknown"; "waiting is waiting-on-human, never idle"; "no claim, never eligible"; "a claim is void when procStart differs at the microsecond"; "an opt-in does not survive a new process"; "adoption refuses conflicting owners"; "standard at 1,227 MB available is constrained"; "a project file may raise a threshold and never lower one"; "a run spec may not set a reaper key"; "the order is idle hours then size" | remove each protection, one mutant per row; turn unknown into idle; accept a claim on pid alone; adopt an owner of founder; swap the sort keys; allow L2 lowering |
| **RC** | **report mode end to end** (formerly R8). `horde reaper run --report`, `status` and `why`; the decision events; `horde reaper schedule` with its consent refusal; the lock; the sleep and jump handling of F6. **The trial starts when this merges** | RB; metrics M3 (the writer); lifecycle step 4 (`effects`) | "report mode reaches no acting verb" (the `effects` tripwire, with a planted-verb control); "install is refused while the mode is off"; "two ticks, one lock"; "every classified session has a decision event"; "a failed decision write acts on nothing"; "a tick after sleep does not act"; e2e on fixture stores | skip the lock; write no event for keeps; let report reach a terminate; use a tick count that includes sleep |
| **RD** | **the input box** (formerly R4). `agents/claude-code/InputBox.ps1`, ported from wezfleet with ledger `planning/ledger/agent-claude-code-inputbox.md` (`lib/Delivery.ps1` 588-907, BUG-2026-09-15-unsent-input-box). The typed-text control already exists: wezfleet took it on 2026-09-15 with a scripted typist. This PR re-runs it against the port in the isolated instance and flips `input.box` to `yes`. Also measures the host's `text.read` under the scheduled task's logon | RA; Phase 3 step 3 | "typed text is typed"; "a grey suggestion is empty"; "the cursor at the prompt start overrules screen text"; "an unreadable screen is unreadable"; "two disagreeing reads are typed"; e2e "a scripted typist's text is seen as typed" | treat grey as typed; drop the cursor rule; treat unreadable as empty |
| **RE** | **narrow act** (the first close). `core/Close.ps1`, rung 2 only: the closure record, the resume and flush checks, the handle terminate with the creation time read from the handle, the post-close verification, reconciliation of `closing` records; `horde reaper mode act` with its evidence gate (5.4), the misread and regret detectors, and the breaker. **Scope**: adopted sessions only; not founder; not an Orc (P14); no Remote Control link; no recurring cron; every flag `yes`; idle at least 24 h; at most 2 per tick. Measures the S4U `OpenProcess(PROCESS_TERMINATE)` question (5.1) on a stand-in. Ledger `planning/ledger/core-closer.md` (shared with lifecycle step 28) | RC, RD, and the trial's evidence | "no record, no close"; "a growing transcript abandons the close"; "a reused pid is never terminated" (guarded killer); "a shorter transcript after close is close-lossy and switches to report"; "a closing record is reconciled"; "act is refused before the evidence gate"; "a misread in act switches to report"; "a session idle under 24 h is not closed in RE"; "no more than 2 closes per tick"; "RE sends no key and closes no pane" | write the record after the terminate; skip the flush check; terminate by pid without the handle's creation time; ignore the misread count; drop the 24-h floor; drop the cap |

**Added by the founder's rulings of 2026-10-13** (sections 12 and 13). The pool is its own module,
so PA can start as soon as this revision merges. It needs nothing from RA to RE:

| # | pull request | depends on | tests first (assertion text) | mutation spec (each must turn red) |
|---|---|---|---|---|
| **PA** | **the pool module**: `pool/` with its port (13.2), the entry schema in `schema/`, the store (H7), `horde pool list`, `show` and `sweep`, and the retention sweep. Orcs only. Entries are written by an injected source, so a fixture closure record drives every test | this design | "a closed Warg makes no pool entry"; "an unknown role is kept as an Orc"; "an entry is written once and never rewritten"; "a session closed twice gets two entries"; "the 7-day window holds an entry closed 6 days ago and not one closed 8 days ago"; "an entry older than the retention is swept, its closure record is not"; "an entry holds no transcript text"; "list reads no transcript" | admit a Warg; rewrite an entry in place; count windows from the start time; sweep the closure record; copy the last prompt into the entry |
| **PB** | **restart from the pool** (13.4): `horde pool restart`, the restart record, the live-session refusal and the resumable re-check. The resume itself goes through the agent adapter and the host adapter, tested only in the isolated host instance | PA; the host port's open-pane verb (Phase 3); lifecycle 3.1's binding, or the closure record's resume argv until then | "a restart re-checks the transcript before starting anything"; "a session already running is not started twice"; "a restart on another machine's entry is refused here and routed to that machine"; "a restart writes its record before it starts the process" | skip the re-check; skip the live check; write the record after the start |
| **RO** | **the close offer** (section 12): the offer builder, the decisions store as the founder's question surface, the accepted-offer claim, and the close through RE's closer | RC (the would-close facts); RE (the closer) | "an Orc is offered and never closed without an accepted offer"; "a linked session is offered and never closed without an accepted offer"; "an answer not signed by the founder's device does not close"; "an accepted offer lifts P1, P11 and P14 for that pid and procStart only"; "every other protection is re-checked at the moment of closing"; "a keep answer silences the same process for the snooze"; "a closed Orc's offer leaves a pool entry"; "a closed Warg's offer leaves none" | accept an unsigned answer; carry the acceptance to a new process; skip the re-check after acceptance; offer while mid-turn |
| **PC** | **the pool on the phone** (13.5): the `pool` relay channel, the PWA's Closed tab, and the restart request with its signature check on the machine | PA, PB; the relay's signed-answer path | "the snapshot holds the three windows and nothing older"; "a restart request with a bad signature does nothing"; "a restart request for another machine's entry is ignored here"; "a restart request is used once" | accept an unsigned request; let the relay pick the machine; accept a replayed nonce |

**Order with them:** PA can start at once. RA, RB and RC as before. RO after RE. PB after PA. PC
last. **Until RO merges, offers are made by hand.** RC's report names each Orc and linked session that
would be offered, and the coordinator adds it to the decisions list with `decisions add`.

**Later, off the critical path:**

| # | pull request | depends on |
|---|---|---|
| RF | the graceful ladder and pane close (formerly R9 to R11): `keys.send`, `kill` and `pid` in the WezTerm adapter, the all-instances discovery, rungs 1 and 3, the S4U-to-socket question, and the isolated close-then-resume round trip that measures `close.keys` | RE; Phase 3 steps 2 and 3 |
| RG | switch to the follower (formerly R12): the reaper reads H2 and opens no transcript | lifecycle step 11 |
| RH | Codex enablement (formerly R13) | RA, RF |
| - | the anchor path (lifecycle steps 22, 27, 28), tmux and psmux act verbs (hosts plan), gemini-cli | those plans |

**Order:**

1. RA.
2. RB.
3. RC, which starts the trial.
4. RD, built during the trial.
5. RE, which acts only once the trial's evidence passes the gate.

The first memory is reclaimed at RE. Until then, RC's report tells the founder which sessions to close
by hand, and why.

---

# 10. Changes this design asks of other plans, and the policies it changes

**Changes to other plans:**

1. **Lifecycle step 10:** `core/Observe.ps1` first ships the reaper's states (RB). Step 10 then adds
   stalled, looping and the rest to the same function.
2. **Lifecycle step 28:** the closer is built in steps:
   - the terminate-only path is RE, now;
   - the graceful ladder and pane close are RF;
   - the anchor path follows step 27.

   One module, one ledger.
3. **Lifecycle step 17:** pull it forward. RB needs the tier keys in configuration, though not the
   gate itself.
4. **Lifecycle 4.4:** the reaper is a second interim transcript reader beside metrics collect, until
   RG.
5. **Phase 3 step 2** (needed only by RF): add "every declared host's live instances" beside "this
   session's host", for callers that have no session (the scheduled tick).
6. **The host capability vocabulary** (needed only by RF): add `keys.send`.
7. **Metrics M3:** the writer must exist before RC. If it has not merged when RC is ready, M3 goes
   first. The reaper does not build a second writer.
8. **`core/ownership.json`:** add store H6 (claims). H3 (closures) is lifecycle's, and this design
   only fills it earlier.
9. **Engines plan, the open question of how Horde can tell whether a live session has Remote Control
   on before sending anything:** S8 answers it from the control file's `bridgeSessionId`, with no
   screen read (I-16).

**Policies this design changes.** Each is quoted, then the change stated:

10. **Lifecycle plan 1.2** (standard tier, "On overshoot"): "orcs are asked about idle sessions ...
    Horde itself ends no work." The reaper reverses that for reaper-eligible sessions: Horde itself
    ends idle work.
    - **Authority:** the founder's request of 2026-10-04, "a reliable way for horde to clean up idle
      sessions all the time".
    - **What stays true:** the gate's ladder never kills working sessions. The reaper ends only
      sessions every rule of section 1 calls idle, after the evidence gate of 5.4.
    - **The edit:** lifecycle 1.2's sentence gains "except through the idle reaper
      (`planning/idle-session-reaper.md`)" in the PR that ships RE.
11. **wezfleet `lib/Cleanup.ps1` header**, the founder on 2026-09-03: "it should only clean up
    sessions that it knows are done ... it's for whenever the user asks for it". The founder's
    request of 2026-10-04 ("all the time") **supersedes it for reaper-eligible sessions**, the
    coordinator's reading.
    - **What stays true:** wezfleet's `cleanup` is unchanged and still runs only on request.
    - **Why this is not a loosening of what 2026-09-03 protected:** it protected work that might not
      be done. Here a session counts as idle only when every signal says it is, and its conversation
      resumes.
12. **wezfleet's registry after a close.** The registry still names the closed session's pane.
    - **Today:** wezfleet's delivery refuses a pane with no input box, so mail is not typed into the
      leftover shell; it fails instead.
    - **Asked of wezfleet** (a stopgap issue, like lifecycle W3 to W5):
      - read Horde's closure records and mark the session `reaped` with its resume command;
      - answer mail to a reaped session with "reaped; resume with ..." rather than a delivery
        failure.
    - **Until that lands:** RC's report lists, for each would-close, the registry pane that would go
      stale.

---

# 11. Decisions

**Settled by the coordinator (2026-10-05)**, so not asked of the founder:

- the founder's own sessions (owner `founder`, no owner, or role master) are closed only by a
  per-session `horde reaper opt-in`, which ends with that process, and never by a global switch;
- the thresholds of 5.2 (120, 60, 30 and 15 min, plus RE's 24-h floor) are starting values, raised
  automatically by regret and lowered only by the founder;
- the report period is stated as evidence (5.4: N ticks and at least 20 would-close decisions with
  zero misreads), not as days;
- a session waiting on a human is never closed, only reported.

**Decided by the founder (2026-10-13)**, relayed by C:

- **(a) Orcs are never closed automatically.** The reaper may adopt them automatically, so that it can
  see them, report them and offer them (`reaper.adopt auto`). An Orc is closed only when the founder
  accepts a close offer for it (section 12, P14). The twice-the-threshold rule of 5.2 now decides only
  when an Orc is first **offered**, never when it is closed.
- **(b) Sessions with a Remote Control link are never closed automatically.** They are offered the
  same way (P11). This is the recommendation below, made firm.
- **Other idle sessions** (workers, meaning sessions owned by an Orc that are not Orcs themselves)
  follow this design's leans: report-only first (RC's trial, at least a day of ticks, 5.4), then
  closing (RE).
- **Every closed Orc goes into the pool** (section 13), whoever closed it. A closed Warg (a subsession
  or worker) does not. It leaves only its closure record (founder's correction, 2026-10-13).

The original wording of (a) and (b) is kept below for the record.

**Formerly open, for the founder** (each self-contained):

(a) **Adopt M's orchestrators.** Horde started none of today's sessions. Should the reaper adopt
automatically every session whose wezfleet registry owner is an orchestrator label (not "founder",
not empty), including the orchestrators M owns such as B, E and I, proven by pid plus process start
time, and close them at twice the worker idle threshold? Recommendation: yes. Without it, only
sessions someone adopts by hand with `horde reaper adopt` are ever closed.

(b) **Remote Control links.** May the reaper close a session that has a Remote Control link (a
`bridgeSessionId` in its control file), given three facts?
- closing it ends the founder's phone and web access to that session;
- `claude --resume` brings back the conversation but not the link;
- re-linking it issues a new URL.

Recommendation: not automatically. Report linked sessions with their idle time, and let him opt one
in, as with his own sessions. Today this decides about 2.3 GB: I, E and B, all linked.

Note for (a): D1 is a worker whose owner, D, is live and busy. No rule holds D1 for that reason,
because P2 protects a parent from its children, not a child from its parent. If the founder wants an
idle child of a busy owner to be asked about first, as lifecycle 1.2 words it, that becomes P15 (P14 is now the Orc rule).
RC's report shows the case.

---

# 12. The close offer (founder, 2026-10-13)

An Orc (P14), a session with a Remote Control link (P11) and the founder's own session (P1) are never
closed by a rule. When one is idle, the reaper **offers** it to the founder and acts only on his
answer. The offer is the per-session opt-in of P1, made easy to give from the phone.

## 12.1 Who is offered

A session is offered only when **all** of these hold:

- every rule of section 1 calls it idle;
- the only protections holding it are P1, P11 or P14;
- its idle age has reached the pressure level's threshold (5.2) times `reaper.orchestratorFactor`;
- that age is never below `reaper.offer.minIdleMinutes`.

If anything else holds it, it is **not offered**:

- P2: it holds running agents;
- P3 or P13: input is typed or queued;
- P7: it is waiting on a human;
- P8 or P12: it has a wake, a cron or a task.

Offering such a session would ask him to approve destroying work, and he could not tell from the
phone. Report mode (RC) lists these sessions, without offering them.

## 12.2 How it reaches him: the decisions list

The decisions list is already the founder's single place for questions. It reaches the phone through
the relay's decisions channel and the decisions window, so the reaper adds no new surface for asking.

- **One question per machine at a time**, kind `parts`, one part per offered session. Each part is
  answered with one of:
  - **Close**;
  - **Keep for a day** (`reaper.offer.snoozeHours`);
  - **Keep while it lives** (this process is never offered again).
- **Each part says, with no transcript text:**
  - the label and the name the session carries;
  - its role (Orc, linked, or his own);
  - the ledger task id, when the registry has one;
  - the machine;
  - how long it has been idle, and the memory it holds (private MB);
  - what closing loses. For a linked session: "the phone link ends; a restart asks for a new link".
  - for an Orc, that it lands in the pool and can be restarted from there. A Warg that is offered
    because of its link leaves only its closure record.
- **Importance:**
  - `-Importance normal -Blocks none` normally: nothing waits on it;
  - `-Importance high` when the pressure level is `constrained` or `critical` (5.2).
- **A session that stops being idle** before he answers gets its part withdrawn with `decisions
  update`. Once a question is answered, only `decisions reply -Note` is allowed (the decisions store's
  rule). New candidates wait for the next question, so an open question is never reshaped under him.
  The exception is `critical` pressure, when a second question may open.

## 12.3 An accepted part is a command, so its source is checked

Answers are effectively commands (the relay's founding rule). A **Close** acts only when the answer
record says it came from the founder's own device, by one of:

- the relay's signed answer (device key, single-use nonce, the 60 s skew window);
- the decisions window on his machine.

An answer an Orc writes down from chat with `decisions answer` is recorded but **does not close**.
The reaper replies under the question with a note asking him to tap Close himself. This is the same
line verified answers drew for notifications.

An accepted Close becomes an **offer claim** in H6 (section 3), with source `offer`. The claim names:

- the decision number and part;
- the session's pid and procStart;
- an expiry: 30 min after the answer, an **estimate**.

Its effects:

- **It lifts P1, P11 and P14 for that one process, and nothing else.**
- The closer (RE, rung 2) re-checks every other protection at the moment of acting, as 4.2 already
  requires. Any change abandons the close.

When the close finishes, the reaper replies under the question:

- "closed, in the pool as `<entry>`" for an Orc, or "closed, resume with `<argv>`" for a Warg; or
- "not closed: `<reason>`", for example "it started a new turn at 14:02".

A Keep answer writes nothing but a decision event and the snooze.

## 12.4 What is recorded

Each offer writes a `reaper.offer` event: the session, the question number and part, and the
protections that caused the offer. Each answer acted on writes `reaper.offer-answer` with the answer
record's id and its source. An answer whose source does not qualify is recorded with that reason. The
`reaper.close` of 5.5 names the offer claim it relied on.

---

# 13. The closed-session pool (founder, 2026-10-13)

## 13.1 What it is, and why it is its own module

**Orcs only** (the founder's correction of 2026-10-13, relayed by C). The pool holds closed Orcs and
never closed Wargs, meaning subsessions and workers. P14's definition decides who is an Orc, and an
unknown role counts as one. A closed Warg leaves only its closure record (H3), as before. Its
conversation can still be resumed from that record's resume argv, but it is not listed, shown or
offered for restart.

The pool remembers every Orc that has been closed and could come back. It shows them by **the
last 7 days, the last 30 days and the last 3 months**, each with the handle to restart it. It answers
one question: "what did I close, and how do I get it back?"

It is not the closure record (H3, 4.1):

- **the closure record** is the closer's operational tombstone. It is written before acting, it may
  end `close-failed` or `close-abandoned`, and it holds full paths and every signal;
- **a pool entry** exists only for a session that is really closed. It holds only what the founder
  and a restart need.

**Many writers, one owner.** Several paths can close a session:

- the reaper on its own (RE);
- the reaper on his answer (RO);
- the founder by hand;
- a crash.

All of them land in the one module. The module is self-contained:

- it depends on core (paths, configuration, schema validation, the metrics writer);
- it depends on the agent and host ports, and never on an adapter;
- it names no terminal and no harness.

## 13.2 The module

```
pool/
  Port.ps1        the contract: Add-HordePoolEntry, Get-HordePoolEntries, Get-HordePoolEntry,
                  Request-HordePoolRestart. Nothing else is public
  Store.ps1       write-once entries, restart records, the retention sweep
  Restart.ps1     13.4, through the agent port (resume argv, Test-AgentResumable) and the host port
  Snapshot.ps1    the phone's view (13.5): windows, newest first, content-free
  settings.json   defaults for the pool.* keys
  test/           suites and mutation specs
cli/commands/pool.ps1   horde pool list | show | restart
channels/pool/          the relay channel (PC)
```

Consumers read the pool **only through `Port.ps1`**: the reaper, the CLI, the relay channel, and
wezfleet's "reaped" marker (section 10, item 12). Another close path joins by calling
`Add-HordePoolEntry`. It never writes the store.

## 13.3 The entry

**Where it lives.**

- Entries: `<HordeHome>\store\pool\entries\<yyyy-MM>\<closedAtUtc>-<harness>-<sessionId>.json`,
  written with `CreateNew` and never rewritten.
- Restart records: `<HordeHome>\store\pool\restarts\<entryId>-<utc>.json`, also write-once.

The pool is a new store, **H7**, written only by the pool module, with a schema in `schema/`. It is
not a row in `core/ownership.json`: that table lists where each field of the session record comes
from, not Horde's own stores, and the files store is not in it either. This corrects the first
wording of this paragraph.

**What an entry holds** (`schemaVersion` 1):

| field | what |
|---|---|
| `entryId` | 32 hex characters, random |
| `machine` | the Horde machine id and its display name. A horde spans machines, and each machine's pool holds its own sessions |
| `harness`, `sessionId` | which conversation |
| `label`, `name`, `role`, `owner`, `parent` | as the registry had them at close. `role` is `orc`, `warg`, `founder` or `unknown`. Only `orc` and `unknown` make an entry. For `warg` or `founder`, `Add-HordePoolEntry` writes nothing and answers "not an Orc". It does not throw, because reconciliation offers it every close. The pool trusts the role it is given; deciding P14 is the classifier's job (RB) |
| `taskIds` | fleet ledger task ids from the registry, when it has them |
| `cwd` | the working directory. The full path stays on the machine, and the phone gets its last segment |
| `startedAt`, `lastActiveAt`, `closedAt` | procStart, the newest transcript event's time, and the verified close |
| `closedBy` | one of:<br>- `reaper` (RE);<br>- `offer`, with the decision number and part;<br>- `founder-manual`: he closed it himself;<br>- `ended`: the process is gone and has no closure record, such as a crash or a closed pane |
| `closureRecord` | the H3 record's path, when there is one |
| `resume` | the agent adapter's resume argv, plus the transcript's path, file id, length and tail hash, all as recorded at close |
| `remote` | for a linked session, the remote name. The bridge id is history only, because it cannot be reused (I-16) |
| `memoryMB` | private MB at close |

**No transcript text, no prompt and no file content** goes in an entry, the same rule as 5.5's
events. The pool is shown on a phone through a hosted relay.

**How entries are made.**

- The closer calls `Add-HordePoolEntry` after 4.3 verifies the close. The pool keeps it only if the
  session is an Orc.
- Each reaper tick then **reconciles**, for Orcs only:
  - a `closed` closure record of an Orc without an entry gets one;
  - an Orc the registry still lists, whose pid plus procStart is gone and which has no closure
    record, gets an entry with `closedBy = ended`. It gets `founder-manual` when the wezfleet registry
    recorded his close.

So **the pool can always be rebuilt** from H3 plus what the tick observes. A failed pool write never
loses a session: it is retried on the next tick.

**Retention.** The sweep removes entries older than `pool.retentionDays` (92). It never touches
closure records, which stay as lifecycle's long-term history.

## 13.4 Restarting

`horde pool restart <entry>` (and the phone's Restart button, 13.5) runs these steps in order. Any
refusal names its reason.

1. **The entry is this machine's.** Another machine's entry is refused here. The phone addresses
   restarts by machine.
2. **The session is not already running.** The agent port finds no live process for that session id.
   If one exists, the restart refuses with "already running as `<label>`", so the conversation is
   never started twice.
3. **The conversation is still there and unchanged.** `Test-AgentResumable`, plus the file id, a
   length at least the recorded one, and the recorded tail hash.
   - A transcript that grew since the close was resumed somewhere else, so the restart refuses and
     says where to look.
   - A missing transcript refuses.
4. **One restart at a time.** A lock file, `restarts\<entryId>.lock`, created with `CreateNew`. A
   second request while one runs is refused.
5. **Record before acting.** The restart record is written with state `starting`.
6. **Start it.** The host port opens a pane, then:
   - **where:** in the window of its parent or owner when that one is live (subsessions open in the
     parent's window), else in the fleet's window;
   - **what:** the recorded resume argv, from the recorded `cwd`.
7. **The link.** If the entry has a `remote` name, the restart asks for a new link under that name,
   once engines E9 measures that `--resume` combines with it. Until then the session restarts
   without a link, and the outcome says "re-link it from the session".
8. **Verify.** A live process with that session id appears within 60 s (an **estimate**). The
   record becomes `restarted` with the new pid and procStart, or `restart-failed` with the reason. The
   lock is released.
9. **Tell wezfleet.** It re-registers the label (section 10, item 12), so mail reaches the session
   again.

**The entry is not deleted** by a restart. The list shows "running again since `<time>`" from the
restart record, and a later close makes a new entry.

## 13.5 On the phone

**A new relay channel, `pool`,** beside decisions, chat and progress, under `channels/pool/` (PC).

- **Snapshot.** The runner publishes one whole snapshot whenever the pool changes, and when the
  runner starts. Each machine publishes its own; the phone merges them. A snapshot holds up to 200
  entries, newest first. Anything older is a count.
- **Mailbox.** The channel keeps its last 20 envelopes (an **estimate**), using the trim of PR 232.
- **The Closed tab** in the PWA has three filters, matching his words:
  - **7 days**;
  - **30 days**;
  - **3 months**.

  Each is cumulative: everything closed within that window.
- **Each row shows:**
  - the label and name;
  - the role;
  - the machine;
  - when it was closed, and by whom (the reaper, his answer, by hand, or by itself);
  - how long it ran;
  - a link badge if it had one;
  - a **Restart** button.

  A restarted row shows "running again since".
- **A restart request** is signed like an answer: the device key, a single-use nonce, the 60 s skew
  window. The machine checks, in order:
  - the signature;
  - that the entry is its own;
  - that the nonce is unused.

  It then runs 13.4 and posts the outcome to the progress channel. The relay never chooses the
  machine and never acts. It only carries the request.
- **The decisions page** links to the Closed tab from every close offer's reply.

## 13.6 Failure matrix

| # | failure | what happens |
|---|---|---|
| PF1 | the pool write fails after a verified close | the session is closed and its H3 record says so. The next tick's reconciliation writes the entry |
| PF2 | the phone's snapshot is stale and he restarts a session already running | step 2 refuses, and the outcome says where it runs |
| PF3 | two restart requests at once (phone and CLI) | the lock of step 4 lets one through |
| PF4 | a restart request reaches the wrong machine | step 1 ignores it. Only the machine named in the entry acts |
| PF5 | the transcript changed or moved since the close | step 3 refuses. Nothing is started over a conversation that went on elsewhere |
| PF6 | the pane opens but the process never appears | `restart-failed` after 60 s. The pane is reported, never killed by the pool |
| PF7 | a forged or replayed restart request | signature and nonce checks. Nothing runs |

---

# Unproven, and written down

- Whether the founder's own manual close can be told apart from a crash. It can only if the wezfleet
  registry records his close. Until then, both are `ended` (13.3).
- Whether the host port can open a pane from the scheduled tick's logon to run a phone restart (PB
  and PC; the same S4U question as 5.1). A restart from the CLI in his own logon does not need it.

- Why a transcript's modification time moves while no event is appended (I-04). The design does not
  depend on the answer: it never reads mtime as activity.
- Every Codex signal on a live session (RH).
- Whether Claude Code exits cleanly on Ctrl+C twice at an empty prompt (RF; not needed by RE).
- Whether an S4U task with a Limited token can terminate a same-user process in another logon
  session (RE), and whether it can reach the terminal host's socket (RF).
- Whether `--resume` combines with `--remote-control <name>` to restore a link under the old name
  (engines E9). The URL changes either way (I-16).
- The full set of task kinds that emit task-notifications. Any kind not recognised is unknown, so
  this gap fails toward keeping.
- The allowlist of 1.5 covers the kinds seen in 74 transcripts. A new kind is not allowlisted until
  measured.
- Whether a stdio MCP server child would make sessions permanently ineligible (P4). None of today's
  idle sessions had a child.
- Every **estimate**:
  - the thresholds and RE's 24-h floor (5.2);
  - the 5-min tick (5.1);
  - the caps of 2 and 4 (5.3);
  - the 10-min misread and 30-min regret windows (5.4);
  - the 25 percent regret raise (5.4);
  - the N = 288 ticks and 20 would-close decisions (5.4);
  - the 24-h retry hold (4.2);
  - the 2x orchestrator factor (5.2).
- The orphans this design leaves to lifecycle steps 14 and 31: 788 MB today (I-14). The review of
  #84 suggests killing those two once by hand now.

---

# Appendix A. The replay script

Read-only. It was run from the session scratchpad with two snapshots beside it:

- `procs.json`, the CIM process table: pid, parent, name, creation time as FILETIME, private and
  working-set bytes;
- `mem.json`, the memory counters.

It is kept here as prose rather than shipped, because a script under `planning/` would be scanned as
code (tools/HostNames.ps1).

```python
# Read-only replay of planning/idle-session-reaper.md section 8: applies the design's rules, as
# written, to this machine's live sessions. Inputs: control files, a process table snapshot
# (procs.json), a memory snapshot (mem.json), wezfleet's registry and the transcripts. Writes nothing.
import json, os, glob, re, datetime as dt
S = os.path.dirname(os.path.abspath(__file__))
H = os.path.expanduser("~")
procs = {p["pid"]: p for p in json.load(open(os.path.join(S, "procs.json"), encoding="utf-8-sig"))}
mem = json.load(open(os.path.join(S, "mem.json"), encoding="utf-8-sig"))
now = dt.datetime.fromisoformat(mem["at"][:26] + "+00:00")
REG = os.path.join(H, "Documents/Code/.wezfleet/registry/sessions")
# Timestamped kinds allowed after a turn end without starting a turn (measured by afterend.py).
# Untimestamped metadata lines of any kind are allowed and never age the session.
ALLOWED_TS = {"system/away_summary", "system/bridge_status", "system/informational", "system/local_command",
              "pr-link/", "frame-link/", "file-history-delta/"}
TERMINAL = {"completed", "failed", "killed"}
START_RES = [re.compile(r"running in background with ID: ([a-z0-9]+)"),
             re.compile(r"Monitor started \(task ([a-z0-9]+)"),
             re.compile(r"agentId: ([a-z0-9]+)")]


def kind(o):
    t = o.get("type"); st = o.get("subtype") or ""
    if t == "user":
        c = o.get("message", {}).get("content")
        if isinstance(c, list) and c and isinstance(c[0], dict) and c[0].get("type") == "tool_result":
            return "user/tool_result"
        return "user/meta" if o.get("isMeta") else "user/prompt"
    return "%s/%s" % (t, st)


def result_text(c):
    v = c.get("content", "")
    if isinstance(v, list):
        v = " ".join(y.get("text", "") for y in v if isinstance(y, dict))
    return str(v)


def turn_state(path, since):
    last_end = None; after = []; newest = None; pending = 0; open_tools = {}
    tasks = {}; crons = {}; queue = 0; unknown = []
    for line in open(path, encoding="utf-8", errors="replace"):
        try:
            o = json.loads(line)
        except Exception:
            unknown.append("unparsable line"); continue
        k = kind(o); ts = o.get("timestamp")
        t = dt.datetime.fromisoformat(ts.replace("Z", "+00:00")) if ts else None
        if t and (newest is None or t > newest):
            newest = t
        cur = t is None or t >= since  # this process's lines: tasks and crons die with the process
        if k == "queue-operation/" and cur:
            queue += 1 if o.get("operation") == "enqueue" else -1
        if k == "system/turn_duration":
            last_end = t; after = []; pending = int(o.get("pendingBackgroundAgentCount") or 0); open_tools = {}
            continue
        if last_end is not None and t is not None:
            after.append(k)
        if o.get("type") == "assistant":
            for c in o.get("message", {}).get("content") or []:
                if isinstance(c, dict) and c.get("type") == "tool_use":
                    open_tools[c["id"]] = c.get("name")
                    inp = c.get("input") or {}
                    if cur and c.get("name") == "CronCreate" and inp.get("recurring"):
                        crons[c["id"]] = None
                    if cur and c.get("name") == "CronDelete":
                        crons = {i: v for i, v in crons.items() if v != inp.get("id")}
                    if cur and c.get("name") == "TaskStop":
                        tasks.pop(inp.get("task_id") or inp.get("shell_id"), None)
        if k == "user/tool_result":
            for c in o.get("message", {}).get("content") or []:
                if isinstance(c, dict) and c.get("type") == "tool_result":
                    tid = c.get("tool_use_id"); open_tools.pop(tid, None)
                    body = result_text(c)
                    if tid in crons:
                        m = re.search(r"\b([0-9a-f]{8})\b", body); crons[tid] = m.group(1) if m else "?"
                    if cur:
                        for r in START_RES:
                            m = r.search(body)
                            if m:
                                tasks[m.group(1)] = "open"
        if k in ("user/prompt", "user/meta") or o.get("type") == "attachment":
            for m in re.finditer(r"<task-id>([a-z0-9]+)</task-id>.*?<status>([a-z_]+)</status>", line):
                tid, st = m.group(1), m.group(2)
                if tid in tasks:
                    if st in TERMINAL:
                        tasks.pop(tid)
                elif st not in TERMINAL and cur:
                    unknown.append("task " + tid + " of an unrecognised kind is " + st)
    bad = sorted(set(a for a in after if a not in ALLOWED_TS))
    return dict(last_end=last_end, newest=newest, pending=pending, tasks=len(tasks), crons=len(crons),
                queue=max(queue, 0), after=bad, unknown=unknown, ended=last_end is not None)


def descendants(pid):
    n = 0; stack = [pid]
    while stack:
        p = stack.pop()
        for q in procs.values():
            if q["ppid"] == p and q["created"] > procs[p]["created"]:
                n += 1; stack.append(q["pid"])
    return n


controls = [json.load(open(f, encoding="utf-8")) for f in glob.glob(os.path.join(H, ".claude/sessions/*.json"))]
# procStart is FILETIME (100 ns); CIM reports microseconds, so compare at microsecond precision.
live = {c["sessionId"] for c in controls if procs.get(int(c["pid"])) and procs[int(c["pid"])]["created"] // 10 == int(c.get("procStart")) // 10}
regs = {}
for s in glob.glob(os.path.join(REG, "*.json")):
    regs[os.path.basename(s)[:-5]] = json.load(open(s, encoding="utf-8-sig"))
rows = []
for c in controls:
    pid = int(c["pid"]); p = procs.get(pid)
    verified = c["sessionId"] in live
    reg = regs.get(c["sessionId"], {})
    tr = glob.glob(os.path.join(H, ".claude/projects/*/" + c["sessionId"] + ".jsonl"))
    since = dt.datetime.fromtimestamp((int(c["procStart"]) - 116444736000000000) / 1e7, dt.timezone.utc)
    ts = turn_state(tr[0], since)
    live_child = [sid[:8] for sid, r in regs.items() if (r.get("parent") == c["sessionId"]) and sid in live]
    keep = []
    owner = reg.get("owner") or ""
    if owner in ("", "founder") or reg.get("role") == "master":
        keep.append("P1 founder's own")
    if c.get("status") != "idle":
        keep.append("P2/P7 status " + str(c.get("status")))
    if ts["pending"]:
        keep.append("P2 pending agents %d" % ts["pending"])
    if live_child:
        keep.append("P2 live child session " + ",".join(live_child))
    d = descendants(pid)
    if d:
        keep.append("P4 descendants %d" % d)
    if not verified:
        keep.append("S1 not verified")
    if c.get("bridgeSessionId"):
        keep.append("P11 Remote Control linked")
    if ts["crons"]:
        keep.append("P8 recurring cron %d" % ts["crons"])
    if ts["tasks"]:
        keep.append("P12 background task %d" % ts["tasks"])
    if ts["queue"]:
        keep.append("P13 queued input")
    if not ts["ended"] or ts["after"]:
        keep.append("not at a turn boundary: " + ",".join(ts["after"]))
    if ts["unknown"]:
        keep.append("unknown: " + "; ".join(ts["unknown"][:2]))
    age_h = (now - ts["newest"]).total_seconds() / 3600
    rows.append((age_h, pid, (reg.get("label") or c.get("name", ""))[:22], owner, reg.get("role") or "",
                 c.get("version"), int(p["priv"] / 2 ** 20) if p else 0, keep))
print("at", mem["at"], "availMB", mem["availMB"], "headroomMB", mem["limitMB"] - mem["commitMB"])
for r in sorted(rows, reverse=True):
    print("%6.1fh pid=%-6d %-22s owner=%-8s role=%-12s v=%s privMB=%d -> %s"
          % (r[0], r[1], r[2], r[3], r[4], r[5], r[6], "; ".join(r[7]) or "ELIGIBLE once adopted"))
```
