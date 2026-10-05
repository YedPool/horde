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
closes them by hand when asked, and that does not happen reliably. At the time measured, four idle
sessions held 2,975 MB private (1,287 MB working set). The rules below would close all four (I-03,
section 8).

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
| lifecycle 4.4 (the follower, the one transcript reader) | it will be the only transcript reader once it exists | until step 11 ships, the reaper reads one bounded tail per candidate through the port, the same interim exception that metrics collect has. Once the follower is installed, the reaper reads its stream (H2) instead, and a test enforces it (slice R12) |
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

Every measurement was taken on this machine, read-only, between 01:41 and 01:50 UTC on 2026-10-05,
on Claude Code 2.1.287 and WezTerm (instance `gui-sock-15476`). Nothing was typed into, sent to or
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
| I-10 | input box, read through wezfleet's parser (`get-text --escapes`, 25 to 87 ms per read) | 8 harness panes: the box was found in all 8. 7 were empty with the cursor at the prompt start. Pane 27 (D) showed 16 characters on the prompt row with the cursor at the prompt start, which wezfleet's cursor rule reads as not typed (a suggestion or a queued line). Pane 26 (bare shell) had no box. **No typed-text control was taken**: planting text in a real pane is forbidden, so that control belongs to the isolated instance (slice R4) |
| I-11 | cost of each reader | `Get-HordeProjection -Scope Current`: 31.6 s for 32 sessions, peak working set 285 MB. `core/Identity` (control files plus process table): 580 ms (table 352, files 228), peak working set 158 MB. Transcript tail of 256 KB: 18 to 105 ms per session; 64 KB: 1 to 41 ms. Finding a transcript by id across project folders: 1 to 82 ms |
| I-12 | wake and background tools in 249 transcripts over 6 days | `ScheduleWakeup` 84, `CronCreate` 14, `Monitor` 39, `TaskStop` 72; 2,052 lines with `run_in_background` true |
| I-13 | Codex | no live process. 4 rollouts on disk; the largest pairs every turn start with an end: `task_started` 5, `task_complete` 4, `turn_aborted` 1. The status hook's file is believed for 900 s only, and its Stop event does not fire on a failed or interrupted turn (wezfleet `lib/CodexStatus.ps1`) |
| I-14 | agent processes that are not sessions | pid 5616: no control file, 1 thread, 0 handles, 555 MB private, the same orphan as lifecycle M-07, still alive 5 days later. pid 34972: `claude remote-control --help`, running since 2026-10-01 01:57, 233 MB |
| I-15 | wezfleet census, 6.1 s | pane 18 (session d16b54b2) shown as "(unowned)" from a pane-sessions file, while wezfleet's registry record for that session says owner M. Pane 26: bare shell, 126 h |

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
   the recorded procStart to the microsecond (`Get-HordeProcessVerdict` gives `verified`).
2. **It has no live descendant.** No process in the harness's process tree is alive, apart from
   ones its adapter declares resident (section 1.3).
3. **It is not mid-turn.** The harness's own status is not busy, and the transcript's last turn has
   ended: no tool call is open, no background agent is pending, no background task has started
   without finishing, and no scheduled wake is still due.
4. **Nothing is waiting in its input box.** The box was read and found empty (not unreadable).
5. **Its last event is older than the idle threshold** for the current memory-pressure level (5.2).
   The age is measured from the newest timestamped transcript line, **never** from the file's
   modification time (I-04).

`waiting` (the harness waits on a human: a permission prompt, a question) is **not idle**. It is
its own state, `waiting-on-human`. It is reported and never closed (founder decision 5).

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
| S4 | turn state | transcript tail, 64 to 256 KB, through the adapter: the last turn-end line, its `pendingBackgroundAgentCount`, any `tool_use` with no `tool_result` after it, any background task started without a completion, any `ScheduleWakeup` or `CronCreate` whose time has not passed | 1 to 105 ms per candidate (I-11) | strong for what the transcript records. Partial last line: unknown. A pending count absent from the turn-end line is read as 0, which is what 1,427 lines show (I-06). Wakes are common: 84 plus 14 in 6 days (I-12) | D: last turn end has pending 1 (I-06). This agent's own transcript: open `tool_use` at 01:49:30 (I-07) | 7 of 7: turn ended, pending 0, no open tool, no wake |
| S5 | last-event age | the same tail: the newest line that carries a timestamp with a zone | included in S4 | strong. **Not the modification time**: 7 of 7 idle transcripts had an mtime 35 to 54 min old while their newest event was 2.5 to 5.2 days old (I-04), and wezfleet's SEEN column read those sessions as active 36 to 56 min ago | D: 164 s | 7 of 7: 2.47 to 5.21 d |
| S6 | input box | the host's `text.read` (screen with styles), parsed by the **agent's** adapter, read twice 250 ms apart, the cursor rule applied (wezfleet `lib/Delivery.ps1`) | 25 to 87 ms per read, two reads per candidate (I-10) | good on the screen shapes wezfleet measured. Known gaps: a theme that greys typed text; typing that starts between the last read and the key; stale frames. Unreadable counts as occupied | not taken on the live terminal (planting text is forbidden). Slice R4 takes it in the isolated instance, as wezfleet did on 2026-09-15 with a scripted typist | 7 of 7: found, empty. Pane 27 shows why the cursor rule is needed (I-10) |
| S7 | CPU | `Get-Process` total processor time, twice, 10 s apart | 34 ms per read (lifecycle M-52) | **weak**: idle sessions use 31 to 219 ms per 10 s, D used 484 (I-09). Recorded as evidence only, never a gate | D: 484 ms | 31 to 219 ms |

Signals S1, S2 and S3 come from one process-table read plus small files, so they are the
**pre-filter**: every live session pays for them on every tick. S4, S5 and S6 are paid only by
sessions that pass the pre-filter. A tick on today's fleet therefore costs about 0.6 s and 158 MB at
its peak, against 31.6 s and 285 MB for a full projection (I-11). At 1,227 MB available, that
difference is the difference between a reaper that helps and one that adds to the problem.

## 1.3 Adapter by adapter

**claude-code** (`agents/claude-code/Idle.ps1` and `agents/claude-code/InputBox.ps1`):

- S3 is the control file under the harness's sessions folder (already read by core/Identity).
- S4 and S5 come from the transcript's lines:
  - turn end: `system/turn_duration` and its `pendingBackgroundAgentCount`;
  - tool pairing: `tool_use.id` matched to `tool_result.tool_use_id`;
  - background tasks: task-notification lines;
  - wakes: the `ScheduleWakeup` and `CronCreate` tool calls, with their delay.
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
  `unverified`. Codex sessions are therefore reported but never closed, until slice R13 measures
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
| `input.box` | the adapter can parse the host's screen text into an empty, typed or unreadable input box | **unverified** until R4's isolated typed-text control; then yes | unverified |
| `close.keys` | the adapter knows a key sequence that ends the harness cleanly at an empty prompt, and its effect on the transcript is measured | unverified until R11 measures it | unverified |

A harness whose four flags are not all `yes` is **report-only**. The reaper lists its idle sessions,
with the missing flag as the reason, and closes none of them.

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
| P8 | **a pending wake** | S4 finds a `ScheduleWakeup` or `CronCreate` whose time, plus one tick, has not passed. The timer lives inside the harness process, so closing the session would cancel it silently | "a session with a due wake is kept" |
| P9 | **not resumable** | the harness's `resume` capability is not `yes`, or the resume check of 4.1 fails | "a session that cannot be resumed is kept" |
| P10 | **an engine or host flag not `yes`** | 1.4, and section 6's host flags | "an unverified flag keeps the session and names the flag" |

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
- **`adopt`** claims are how today's fleet becomes Horde's. Whether the reaper may adopt sessions
  automatically, and which ones, is **founder decision 1**. The recommendation is to adopt, at first
  sight, a session that meets all of these:
  - wezfleet's registry gives it an owner that is an orchestrator label (not `founder`, not empty);
  - its control file verifies by pid plus procStart;
  - no other store contradicts its ownership (P6).

  `horde reaper adopt <session>` does the same by hand, and it is the only path while automatic
  adoption is off.
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

The adapter cannot prove more without starting a process. Slice R11's isolated end-to-end test
proves the whole round trip, close then resume, on a real harness.

**Flushed, checked before closing.** All of these must hold:

- the transcript ends with a newline;
- its length is unchanged across two reads 2 s apart. The worst measured write latency is 0.53 s
  (lifecycle M-50), so 2 s is nearly four times that;
- its last timestamped line is a turn end with no pending background work.

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
   pause, then Ctrl+C again, as in wezfleet's `Stop-WfSessionPane` rung 1. Slice R11 measures it on
   2.1.287 before the flag goes `yes`. Why Ctrl+C is safe only after S6: **at a prompt that holds
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

**Unproven, and measured first** (slice R8): whether a task that runs with S4U logon (no visible
session, no window flash, as metrics uses) can reach the terminal host's socket and the console. If
it cannot, the act half runs as an interactive task. If every interactive form flashes a window
every 5 minutes, that becomes a founder decision. The report half needs only files and the process
table, which S4U reaches.

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

The founder's sessions are excluded at every level (P1). Every threshold is a starting value, tuned
by the regret measure in 5.4, and set through the configuration layers (5.6). Orchestrators use
twice the threshold (founder decision 6).

## 5.3 Order: idlest and largest first

Under pressure, eligible sessions are sorted by idle age in whole hours, oldest first, then by
private bytes, largest first.

Why buckets rather than a product of age and size:

- a session idle for days goes before one idle for minutes, whatever their sizes;
- among sessions idle about as long, the largest frees the most;
- the order stays easy to explain in `horde reaper why`.

Per-tick cap: 4 closes (an **estimate**; lifecycle M-21 closed 4 at once and freed 2,846 MB of
commit). Under pressure the closes run one at a time, with the counters re-read between them, so
the reaper stops as soon as the target is met.

## 5.4 Modes: off, report, act

| mode | what a tick does |
|---|---|
| `off` (the shipped default) | nothing; the scheduled job refuses to install |
| `report` | classifies and records every decision as `would-close` or `keep`. Its call graph reaches no acting verb, which the `effects` tripwire (lifecycle step 4) checks |
| `act` | closes what report would have closed |

**Report before act.** `horde reaper mode act` refuses unless all of these hold:

- the mode has been `report` for at least 3 working days (founder decision 4);
- at least one `would-close` has been recorded;
- no misread has been recorded in that time.

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
- the reason codes (P1 to P10, plus `threshold-not-reached`);
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
| `reaper.maxClosesPerTick` | L0, L1, L4 | any | 4 |
| `reaper.adopt` (`off`, `fleet-owned`) | L0, L1 | any | per founder decision 1 |

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
| `pid` | the pane's program pid, to tell the harness from the shell after it exits | unverified; R9 measures | `#{pane_pid}` | likely yes |
| `text.read` with styles | S6 | `get-text --escapes`, measured by wezfleet; R4 measures it for Horde | `capture-pane -e -p` | **likely no**, which makes S6 unknown: report-only until an engine offers a non-screen input-box signal |
| **`keys.send`** (new) | the graceful exit keys: named control keys only, never text | `send-text` with control bytes, as wezfleet's ladder does; R9 measures | `send-keys C-c` | extension |
| `kill` | closing the emptied pane, with the last-pane guard | `kill-pane`; R9 measures | `kill-pane` | extension |

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
| F1 | **misread idle: the session is working** | an in-process subagent with no child (I-08); a tool running without output; mtime-based age (I-04); a stale status file | S2, S3 and S4 must all agree; a pending count, an open tool or busy keeps it; age is never read from mtime; everything is re-verified before each key (4.2); report mode comes first, with the misread detector; the act-mode breaker; at most 4 closes per tick | "a session whose transcript mtime is fresh but whose last event is old is aged by the event"; "an open tool call keeps the session"; "a busy status keeps a session whose turn ended"; "activity arriving between classification and the first key abandons the close"; "a misread in act mode switches to report" |
| F2 | **pid reused** | a recorded pid now belongs to another process; a parent pid reused in the descendant walk | identity is pid plus procStart at microsecond precision; claims are void on a mismatch; the walk requires each child to start after its parent; terminate compares the creation time read **from the handle**; the test harness's killer acts only on what the test created (CONTRIBUTING 9) | "a reused pid is never terminated" (the fixture points the pid at a process the test owns and records, never kills); "a claim with another procStart is void"; "a reused parent pid does not make a descendant" |
| F3 | **the host has gone** | the terminal crashed or restarted; a handle now names another pane; the socket is dead | host unknown or not running means keep. A handle written before the instance started means keep. No call may auto-start a host (`--no-auto-start`, wezfleet `lib/Hosts.ps1`). Processes left without a host are orphans for lifecycle step 14, not the reaper's | "an unreachable host keeps every session"; "a handle from another instance is never acted on"; "the host is never started by a reaper call" |
| F4 | **the transcript adapter is missing** | a new harness, a moved store, a format change | no adapter, or a flag not `yes`, means `unknown` and kept, counted in status; a tail that does not parse is unknown; a harness version newer than the newest measured one is `unverified` until surveyed (`surveyedVersions`, lifecycle 4.3) | "a harness with no idle adapter is report-only"; "an unparseable tail keeps the session"; "an unsurveyed harness version is report-only" |
| F5 | **two reapers at once** | the scheduled tick and a manual run; two machines' homes; wezfleet's own closers (`closeOnDone`, `cleanup -Apply`, `kill`); Claude Code's own reaper | `IgnoreNew` at the scheduler; a machine lock at `<HordeHome>\run\reaper.lock` (`CreateNew`, holding pid plus procStart, stale only when that process is gone by S1); a per-session close claim with `CreateNew` before the closure record; re-verify before each act, so a session another closer took is `gone-elsewhere` and is never a second target | "two ticks, one close"; "a stale lock from a dead reaper is taken over"; "a live lock is never taken over"; "a session closed by another tool between classify and act is recorded gone-elsewhere" |
| F6 | **the clock** | a wall-clock jump (correction, manual change); sleep or hibernate making every session look hours older; a timestamp in the future; a time with no zone | ages use UTC times with a zone only (`ConvertTo-HordeUtcTime`); a future event (beyond 5 s, `HordeClockSkewSeconds`) is unknown; each tick records its wall time and a monotonic count, and if the wall time moved more than 60 s further than the monotonic count since the last tick (a jump or a sleep), **that tick runs in report mode** | "a future timestamp is unknown"; "a time without a zone is unknown"; "a tick after a wall-clock jump does not act"; "a tick after sleep does not act" |
| F7 | the reaper is killed mid-close | the harness's own reaper, the time limit, a crash | the closure record is written as `closing` before the first key; the next tick reconciles: process gone means `closed` after the 4.3 checks; process alive means `close-abandoned`, then classified afresh | "a closing record with the process gone becomes closed after verification"; "a closing record with the process alive is abandoned, not resumed mid-ladder" |
| F8 | the decision cannot be recorded | the metrics writer is missing or the disk is full | no act without its record; the tick reports the failure and exits non-zero, so the scheduler's last result shows it | "a tick whose decision write fails acts on nothing" |
| F9 | the reaper itself adds memory pressure | a full projection takes 285 MB and 31.6 s (I-11) | the narrow tick: the identity pre-filter (158 MB, 0.6 s), a tail read only for candidates; the tick's own peak working set is recorded in `reaper.tick`, and a suite pins it within 120 MB of PowerShell's floor (the metrics M2 measure) | "a tick on 40 fixture sessions stays within its memory bound" |
| F10 | a lost close: the session cannot be resumed | the wrong directory, a moved transcript | the resume check before closing (P9); the record holds the exact argv; R11's isolated round trip (close, then resume, then check the transcript continues the same file) | "a session whose transcript is not in its directory's project folder is kept"; the e2e "a reaped session resumes into the same transcript" |

---

# 8. Replay against today (I-03), under the recommended answers to the founder decisions

The level is `constrained` (I-01), so the threshold is 30 min (60 min for orchestrators).

| pid | label | verdict | reason |
|---|---|---|---|
| 8636 | M | keep | P1, founder's own (owner founder, role master) |
| 22192 | D | keep | P2: busy, pending 1, live child session D1; P4: 6 descendants |
| 2720 | D1 | close, 1st | fleet-spawned, owner D; idle 125 h; all signals idle |
| 19728 | I | close, 2nd | owner M; idle 96 h |
| 17948 | E | close, 3rd | owner M, orchestrator; idle 68.7 h, no live child session |
| 18056 | B | close, 4th | owner M, orchestrator; idle 59.3 h, no live child session |
| 17996 | imadi-7f | keep | P6: the registry says owner M, a pane-sessions file says unowned (I-15) |
| 33076 | J | keep | P1: no owner, so the founder's own, unless he opts in |

Four closes, at the per-tick cap: 2,975 MB private and 1,287 MB working set, plus their shells,
which close only if the pane passes 4.2 step 3. Under `constrained`, the tick re-reads the counters
after each close and stops once `A >= 2,816`. All of this is still subject to the claude-code
`input.box` and `close.keys` flags, which are not `yes` yet. Until R4 and R11 make them `yes`, this
table is the `would-close` report, not an action.

---

# 9. PR slicing

One concern per pull request, in order. Each pull request has:

- its tests written first;
- its mutation spec under the owning folder's `test/mutations/`;
- the CONTRIBUTING 15 levels: the touched suites plus `Mutate.ps1 -Changed` each review round, then
  the full suite and the full specs once, on the merge result.

Anything that sends a key, terminates a process or closes a pane is tested only in the isolated host
instance (CONTRIBUTING 3), with the guarded killer of CONTRIBUTING 9.

| # | pull request | depends on | tests first (assertion text) | mutation spec (each must turn red) |
|---|---|---|---|---|
| R0 | this design | - | - | - |
| R1 | **flags**: `idle.turnState`, `idle.lastEvent`, `input.box`, `close.keys` in `core/capabilities.json`; claude-code declares the first two `yes` with I-04 to I-07 as evidence, the rest `unverified`; codex declares all four `unverified` | - | "an idle flag outside the vocabulary is refused"; "a yes without evidence is refused" | drop a flag from the vocabulary; accept a missing evidence |
| R2 | **`agents/claude-code/Idle.ps1`**: turn state, pending agents, open tools, background tasks, due wakes, newest-event age, from a tail, through the transcript port. Fixtures cut from real transcripts with neutral content | R1 | "an open tool call is mid-turn"; "a pending background agent holds the turn"; "a due wake holds the turn"; "age comes from the newest timestamp, never the mtime"; "a partial last line is unknown"; "a time with no zone is unknown"; "a future time is unknown" | read the mtime; treat a pending count above 0 as 0; skip tool pairing; accept a zone-less time |
| R3 | **`agents/codex/Idle.ps1`**: rollout pairing, newest event; flags stay `unverified` | R1 | "task_started without task_complete or turn_aborted is mid-turn"; "turn_aborted ends a turn"; "the status file alone never says idle" | pair only on task_complete; trust the status file past its TTL |
| R4 | **input box**: `agents/claude-code/InputBox.ps1`, ported from wezfleet with ledger `planning/ledger/agent-claude-code-inputbox.md` (`lib/Delivery.ps1` 588-907, BUG-2026-09-15-unsent-input-box); the WezTerm adapter's `text.read` measured to `yes`; **the typed-text control in the isolated instance** flips `input.box` to `yes` | R1; Phase 3 step 3 | "typed text is typed"; "a grey suggestion is empty"; "the cursor at the prompt start overrules screen text"; "an unreadable screen is unreadable"; "two disagreeing reads are typed"; e2e: "a scripted typist's text is seen as typed" | treat grey as typed; drop the cursor rule; treat unreadable as empty |
| R5 | **the classifier**: `core/Observe.ps1` (lifecycle step 10, its first states) with P1 to P10; pure, all inputs injected | R2, R4 | one assertion per row of section 2; "one unknown signal makes the session unknown"; "waiting is waiting-on-human, never idle" | remove each protection, one mutant per row; turn unknown into idle |
| R6 | **claims and adoption**: store H6, its schema and ownership row; `horde reaper adopt` and `opt-in`; automatic adoption behind `reaper.adopt` | R5; founder decision 1 | "no claim, never eligible"; "a claim is void when procStart differs"; "an opt-in does not survive a new process"; "adoption refuses conflicting owners" | accept a claim on pid alone; adopt an owner of founder |
| R7 | **pressure levels and order**: `core/Pressure.ps1`, pure, from the counters and the resolved admission tier; the `reaper.*` keys in `core/config-keys.json` | lifecycle step 17 (the tier keys); engine-settings Half A | "standard at 1,227 MB available is constrained"; "a project file may raise a threshold and never lower one"; "a run spec may not set a reaper key"; "the order is idle hours then size"; "constrained stops at R plus h" | swap the sort keys; lose the hysteresis; allow L2 lowering |
| R8 | **report mode end to end**: `horde reaper run --report`, `status`, `why`; the decision events; `horde reaper schedule` with consent refusal and the lock; **the S4U reachability measurement** | R5 to R7; metrics M3 (the writer); lifecycle step 4 (`effects`) | "report mode reaches no acting verb" (the `effects` tripwire, with a planted-verb control); "install is refused while the mode is off"; "two ticks, one lock"; "every classified session has a decision event"; "a failed decision write acts on nothing"; e2e on fixture stores | skip the lock; write no event for keeps; let report reach `keys.send` |
| - | **the report shadow**: report mode runs on the founder's machine for 3 working days (founder decision 4); the misread detector's results go into the act PR | R8 | - | - |
| R9 | **host act verbs**: `keys.send` (new vocabulary name), `kill` and `pid` in the WezTerm adapter, each measured in the isolated instance; the last-pane guard; identity re-proven before every key. Ledger from wezfleet `lib/Kill.ps1` | Phase 3 steps 2 and 3; the all-instances discovery of section 6 | "keys.send cannot carry text"; "the last pane in a window is never killed"; "a handle from another instance is never acted on"; "the identity check runs before every key" (the fixture swaps the process after the first key) | check identity once only; let a text string through `keys.send`; drop the last-pane guard |
| R10 | **the closer, pre-anchor path**: `core/Close.ps1`, with the closure record (H3), the resume and flush checks, the ladder, the handle terminate, the post-close verification, and reconciliation of `closing` records. Ledger `planning/ledger/core-closer.md` (shared with lifecycle step 28) | R6, R9 | "no record, no close"; "a growing transcript abandons the close"; "a reused pid is never terminated"; "a shorter transcript after close is close-lossy and switches to report"; "a closing record is reconciled" | write the record after the first key; skip the flush check; terminate by pid without the handle's creation time (run with the guarded killer) |
| R11 | **act mode**: `horde reaper mode act` with its refusals, the misread and regret detectors, the breaker, the per-tick cap. **The isolated round trip**: a real claude-code session with the cheapest prompt (CONTRIBUTING 3) is reaped, then resumed with `--resume`, and its transcript continues the same file. This measures `close.keys` on 2.1.287 and flips it to `yes` | R8, R10, the shadow | "act is refused without 3 days of report"; "act is refused after a misread"; "a misread in act switches to report"; "regret raises the threshold for 7 days"; e2e "a reaped session resumes into the same transcript" | ignore the misread count; never trip the breaker; skip the cap |
| R12 | **switch to the follower**: once lifecycle step 11 is installed, the reaper reads H2 and opens no transcript | lifecycle step 11 | "with the follower installed, the reaper opens no transcript" | read a transcript anyway |
| R13 | **Codex enablement**: a live Codex session in the isolated instance; `idle.*` and `close.keys` measured; an input-box parser for its screen | R3, R9 | one "capability ... holds on its recorded fixture" per flag | - |
| later | the anchor path (lifecycle steps 22, 27, 28), tmux and psmux act verbs (hosts plan), gemini-cli | those plans | - | - |

**Order:**

1. R1 to R3 can run in parallel.
2. Then R4 and R5, then R6 and R7, then R8, which starts the shadow.
3. R9 and R10 are built during the shadow.
4. R11 acts only after the shadow.
5. R12 and R13 come when their dependencies exist.

The first memory is reclaimed at R11. Until then, R8's report tells the founder exactly which
sessions to close by hand, and why.

---

# 10. Changes this design asks of other plans

1. **Lifecycle step 10:** `core/Observe.ps1` first ships the reaper's states (R5). Step 10 then adds
   stalled, looping and the rest to the same function.
2. **Lifecycle step 28:** the closer is built in two halves. The pre-anchor path is R10, now. The
   anchor path follows step 27. One module, one ledger.
3. **Lifecycle step 17:** pull it forward. R7 needs the tier keys in configuration, though not the
   gate itself.
4. **Lifecycle 4.4:** the reaper is a second interim transcript reader beside metrics collect, until
   R12.
5. **Phase 3 step 2:** add "every declared host's live instances" beside "this session's host", for
   callers that have no session (the scheduled tick).
6. **The host capability vocabulary:** add `keys.send`.
7. **Metrics M3:** the writer must exist before R8. If it has not merged when R8 is ready, M3 goes
   first. The reaper does not build a second writer.
8. **`core/ownership.json`:** add store H6 (claims). H3 (closures) is lifecycle's, and this design
   only fills it earlier.

---

# 11. Decisions only the founder can make

1. **Which of today's sessions may the reaper close, given that Horde started none of them?**
   Recommended: adopt automatically every session whose wezfleet registry owner is an orchestrator
   label (not `founder`, not empty), proven by pid plus procStart, and never one whose owner records
   disagree. Today that is D1, I, E and B, about 3 GB.
2. **Can the founder's own sessions ever be closed?** Recommended: only by a per-session
   `horde reaper opt-in`, which ends when that process ends, and never by a global switch. A session
   with no owner counts as his.
3. **The idle thresholds:** 120 min when memory is comfortable, 60 when tight, 30 when below the
   admission reserve, 15 when critical. Recommended: accept them as starting values that the regret
   measure tunes upward automatically, and that only he lowers.
4. **How long report mode runs before the reaper may act:** recommended 3 working days with zero
   misreads, after which he turns it on himself with `horde reaper mode act`.
5. **Should a session waiting on a human (a permission prompt or a question) ever be closed, even
   after days?** Recommended: never; report it so that someone answers it.
6. **Should idle orchestrators with no running agents and no live child sessions be closed like
   workers?** Recommended: yes, at twice the worker threshold. The two idle sessions whose registry
   role is orchestrator, B and E, held 1.6 GB of the 3 GB eligible today.

---

# Unproven, and written down

- Why a transcript's modification time moves while no event is appended (I-04). The design does not
  depend on the answer: it never reads mtime as activity.
- The live typed-text control for S6 (R4), and every Codex signal on a live session (R13).
- Whether Claude Code 2.1.287 exits cleanly on Ctrl+C twice at an empty prompt, and leaves the
  transcript intact (R11).
- Whether an S4U scheduled task can reach the terminal host's socket (R8).
- Whether a stdio MCP server child would make sessions permanently ineligible (P4). None of today's
  idle sessions had a child.
- Every **estimate**:
  - the thresholds (5.2);
  - the 5-min tick (5.1);
  - the cap of 4 (5.3);
  - the 10-min misread and 30-min regret windows (5.4);
  - the 25 percent regret raise (5.4);
  - the 24-h retry hold (4.2);
  - the 3 working days (5.4);
  - the 2x orchestrator factor (5.2).
- The orphans this design leaves to lifecycle steps 14 and 31: 788 MB today (I-14).
