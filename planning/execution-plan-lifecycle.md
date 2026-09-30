# Execution plan: goblin lifecycle, admission and live visibility

Proposed 2026-09-30, from designs whose decisions the founder settled the same day. This plan orders
the work that makes the fleet (1) admit work by measured resources in named tiers, (2) own every
process a goblin starts so nothing is orphaned, (3) close a finished goblin automatically once its
report is proven and its resume binding is current, (4) read every engine's transcript through one
port and one per-machine follower, and (5) show and push what every goblin is doing. It cuts across
Phase 3 (the read half) and Phase 5 (the writers) of `planning/migration-plan.html`, and carries three
wezfleet stopgaps that cannot wait for either.

Planning prose may name terminals and engines. Code may not: CONTRIBUTING 14 keeps terminal names in
`hosts/<name>/`, and the same ratchet extended to `agents/<name>/` (engine-settings design section 9)
keeps engine names there. Every path below respects that; where a step needs a name, the step's file
is under the right folder.

## Sources, and what is settled

The designs were written in a working session and are not yet committed; their measurement ids are
cited here as written there, and the rows this plan depends on are copied into "Measurements" below
so the plan stands alone.

| design | settled decisions this plan implements |
|---|---|
| lifecycle-admission design (2026-09-30) | Its "Decisions taken (founder, 2026-09-30)": 1 named admission tiers, the proposed values are "conservative", a bolder "standard" is the default, set through the engine-settings layers, tuned by metrics; 2 Horde prevents orphans (descendants tied to the goblin's lifetime, e.g. a Job Object with kill-on-close) and reclaims escapes only with proven ownership, reporting the rest; 3 automatic close after proof, on the precondition that the resume information is the single source of truth, current, and easy for an orc to read and use; 4 a transcript port with an adapter per engine under `agents/<name>/`, core naming none; 5 its recommendations 2, 3, 4, 5, 7, 8, 9, 10, 11, 12 and 13 stand (park with mandatory expiry, handle-based end, no shell around the agent, report-only for unproven orphans, reaper left on, pause-never-kill ladder, one follower as the only transcript reader, follower in PowerShell first, wake messages, `horde job run` for heavy work, the wezfleet stopgaps) |
| metrics design | Its "Decisions taken": no environment switch for metrics; the project layer may lower the level, never raise it; prompts only as a salted fingerprint; quota plus labelled notionalUsd on subscriptions; retention 30 days / 1 year / forever; scoring published; **decision 7 as changed by the founder: tokens and usage are counted only from local sources (transcripts, rollouts, harness logs), never from a provider's usage or billing API; cost is computed separately from token counts and a versioned price table; `reconcile` and the `metered` tier are dropped**; no backfill from before consent |
| engine-settings design | The layer model L0 to L5, selectors, the `engine` field and `modelObserved`, secrets as references, resume never re-resolving by default. Its section 12 questions were not answered in the file; where this plan depends on one, it is listed under "Still with the founder" |
| agent-engines research | Its "Decisions taken": every role resolves a named profile of harness + provider profile + model; GLM, Qwen models and DeepSeek run through the Claude Code harness on Anthropic-format endpoints first; Gemini CLI gets `agents/gemini-cli/`; the session-record key stops assuming a UUID; subscription credentials only on their own vendor's CLI; keys read from named environment variables, never stored |
| hosts research | Its "Decisions taken": Windows agents only for now; capability flags per host in `hosts/<name>/capabilities.json` with `state` yes, no, declined or unverified (unverified treated as no); mandatory `-Capabilities` on the host port; pid and cwd tagged with a namespace (`space`) |

## How every step is done

Worktree from a freshly fetched `origin/main`. Ledger first wherever a module replaces anything, in
`planning/ledger/<module>.md`, from the five sources, every entry disposed. Test-first: each step
below lists the assertions to write before the code, quoted so a ledger can cite them. Every new
check mutation-tested (restore the defect, watch it go red). Anything that spawns or kills runs only
in the isolated host instance of CONTRIBUTING 3, and a test of code that kills never lets that code
choose its victim (CONTRIBUTING 9). Verified from a fresh CRLF checkout. Every code PR gets an
independent adversarial review. `gh pr merge --merge`, never squash. Every count in a commit or PR is
copied from command output. Heavy suites run one at a time in one background job with a `DONE=`
marker, because memory is the constraint this whole plan is about.

## Measurements this plan rests on

From the lifecycle design's ledger (read-only, this machine, 2026-09-30 15:05 to 15:23 UTC), plus
four taken for this plan (J-1 to J-4).

| id | what | value |
|---|---|---|
| M-01 | memory at 15:05:15 | 1,176 MB available; committed 34,257 of 37,120 MB (92%) |
| M-02 | memory at 15:12:56 and 15:22:25 | available 2,018 then 2,431 MB; committed 31,411 then 30,431 MB; 6,793 pages/s at 15:22 |
| M-04..M-06 | claude.exe footprint | busy 608 to 1,004 MB private; idle 642 to 862 MB private, 158 to 316 MB working set; fresh goblin 608 to 659 MB private, 300 to 370 MB working set |
| M-07 | orphan claude.exe | 555 MB private, 21.9 h, parent dead, no pane, no control file |
| M-08 | node.exe ancestry | 9 of 9 descend from a dead root; 2,832 MB private; the largest a `next dev` at 1,965 MB; roots dead 14.9 to 36.8 h |
| M-10 | pane host shell | 58 to 66 MB private |
| M-11 | test processes | 62 to 80 MB each; one suite 417 MB; the mutation runner fans out to 4 to 6 at once |
| M-21 | closing 4 goblins | commit fell 2,846 MB; available rose 842 MB |
| M-22 | work after a report | a goblin ran a tool 43 s after `done`; its background task wrote until killed |
| M-26 | leftover panes | one goblin pane idle 18.4 h with close off; one bare shell 38.4 h old |
| M-30 | Claude Code reaper | acts only at pressure `critical`; skips a session with terminal input in the last 30 min, a running turn, or running delegated agents; on Windows memory is reported scarce unconditionally; the Windows threshold behind `critical` was NOT found |
| M-31..M-34 | reaps and waits | reaps 31.1 and 32.2 min after the only prompt; each reap notice woke its session in 1 to 3 s; 123 reap notices since 2026-09-09; "stalls" were waits on live background jobs |
| M-50 | transcript write latency | at most 0.53 s |
| M-51 | transcript growth | 44 to 68 KB/min per busy goblin |
| M-52 | instrument cost | CIM process table 315 ms; `Get-Process` 34 ms |
| J-1 | who is already in a job, about 15:40 UTC | `IsProcessInJob` true for 25 of 25 processes probed: the terminal GUI process, 3 pane shells, 11 claude.exe, 10 node.exe and the probing shell. Windows 10.0.26200 |
| J-2 | the probing shell's immediate job | `LimitFlags` 0x800: `JOB_OBJECT_LIMIT_BREAKAWAY_OK` only, no kill-on-close; 70 active processes, 658,145 created over its life. An ambient desktop-wide job, not a per-session one |
| J-3 | post-spawn assignment and kill-on-close, probe in the scratchpad (`jobtest.ps1`), acting only on processes it created | A new job with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`; `AssignProcessToJobObject` on two running cmd.exe that were already in the ambient job: **ok, ok** (the jobs nested). A ping that cmd A started 1.5 s **before** its assignment: **not in the job**, and **still alive** after the job's last handle closed. A ping that cmd B started about 2 s **after** its assignment: **in the job**, and **dead** after the close. Both cmd.exe dead after the close |
| J-4 | libuv, the runtime under node, `src/win/process.c` on its v1.x branch | Non-detached children go into libuv's own job (non-inheritable handle, kill-on-close, `BREAKAWAY_OK` and `SILENT_BREAKAWAY_OK`). Detached children get `DETACHED_PROCESS` and deliberately **not** `CREATE_BREAKAWAY_FROM_JOB`, "because CREATE_BREAKAWAY_FROM_JOB makes the CreateProcess call fail if we're under job control that doesn't allow breakaway" |

---

# Part 1 - Admission tiers

## 1.1 The rule, unchanged from the design

Admit a unit of kind `k` (`goblin:<harness>`, `job:<name>`, `agent`, `service`) when all hold:

```
A - R_ram(inflight)    - cost_ram(k)    >= ramReserveMb
(L - C) - R_commit(..) - cost_commit(k) >= commitReserveMb
P averaged over pagingWindowSec           <  pagingLimit
```

`A` available MB, `C` committed MB, `L` commit limit, `P` pages/s, `R` reservations held for
`reservationHoldSec` after an admission. The gate enters `constrained` when any reserve is breached
and returns to `open` only after both reserves are exceeded by `hysteresisMb` for `stableSec`. A read
that fails is unknown, and unknown queues, never admits. Only the numbers change by tier.

## 1.2 The tiers

| key | conservative | **standard (default)** | aggressive (opt-in) |
|---|---|---|---|
| `ramReserveMb` | 3,072 | **2,048** | 1,536 |
| `commitReserveMb` | 4,096 | **3,072** | 2,048 |
| `pagingLimit` (pages/s) | 2,000 | **3,000** | 4,000 |
| `pagingWindowSec` | 30 | **30** | 30 |
| `hysteresisMb` | 1,024 | **768** | 768 |
| `stableSec` | 60 | **60** | 60 |
| `reservationHoldSec` | 300 | **300** | 300 |
| backstop count here, `floor((L - commitReserveMb) / 730)` | 45 | **46** | 48 |

"Conservative" is the design's proposal verbatim. The other two are derived below, one number at a
time, with the risk each accepts.

### Standard, and why each number

- **`ramReserveMb` 2,048.** The lowest available memory at which reaping was seen is 1,176 MB (M-01,
  with four reaps from 15:04:19 to 15:05:35). 2,048 keeps the gate's floor 872 MB above it. 872 MB is
  about two goblin starts of working set (320 to 420 MB each, B1 of the design), so even if two
  admissions' reservations were both wrong by their whole RAM cost, the machine would still sit above
  where the reaper was seen. **Risk accepted:** one unwrapped heavy job (a mutation run is 350 to
  640 MB of working set, M-11) started by a goblin on top of a fresh admission can take the machine
  into the reaper's observed range. **On overshoot:** the gate goes `constrained` and admits nothing;
  the closer acts on everything `closable`; proven-owned orphans are reclaimed; orcs are asked about
  idle sessions. If the reaper still fires, it kills a background shell of a goblin whose terminal
  input is older than 30 minutes (M-30), the follower surfaces the reap within one poll (M-32), and
  the owning orc is woken. Horde itself ends no work. Because the reaper's Windows threshold is
  unproven (M-30), this number is a starting point for the tuner, not a derivation.
- **`commitReserveMb` 3,072.** Commit is what makes allocations fail; RAM only makes them slow
  (design finding 3). So this reserve moves least: 3,072 MB is 8.3 percent of the 37,120 MB limit and
  holds four fresh goblins' commit (4 x 730 = 2,920) before the limit. It still refuses at today's
  worst reading: at 15:05 headroom was 2,863 MB (M-01), below 3,072 before any cost is subtracted.
  **Risk accepted:** whether the pagefile is system-managed is unmeasured (design, "Unproven"). If it
  is, commit near the limit grows the pagefile under paging load; if it is fixed, an allocation can
  fail inside a running process. **On overshoot:** the same ladder; commit is only returned by ending
  processes, so the reclaim rungs (closable goblins, proven orphans: 2,846 MB from four goblins, M-21;
  2,832 MB of orphans, M-08) are what move it.
- **`pagingLimit` 3,000 pages/s.** The only measured paging figure is 6,793 pages/s, taken while
  sessions sat unresponsive (M-02, M-42). 3,000 is under half of it. Conservative's 2,000 has no
  measured baseline behind it, and ordinary compile and test bursts may pass 2,000 briefly; the 30 s
  average already smooths spikes. **Risk accepted:** if thrash begins between 3,000 and 6,793 on this
  machine, admitted work slows everything down. **On overshoot:** queue, and the `-Pausable` rung of
  the ladder (suspend declared-pausable jobs, which frees working set, never commit).
- **`hysteresisMb` 768.** Not a boldness knob but a correctness floor. The design's reason for
  hysteresis is that closing one goblin frees about 700 MB of commit and would otherwise re-admit at
  once. The margin must therefore exceed one goblin's commit (730 MB at the prior's top, B1), so one
  close can never re-open the gate on its own. 768 is the smallest round value above 730; closing one
  goblin also frees only about 210 MB of available memory (842 / 4, M-21), so the RAM side needs
  several closes. The checker refuses any tier whose `hysteresisMb` is below the current learned
  p90 commit cost of a goblin, whichever tier it is.
- **`stableSec`, `reservationHoldSec`, `pagingWindowSec`** are unchanged: a goblin reaches its steady
  footprint in 1 to 3 minutes (design B2.2), and nothing measured argues for other values.
- **Backstop count 46**: `floor((37,120 - 3,072) / 730)`. A runaway guard only; it should never bind.

Replayed against today: at 15:05 standard refuses (commit headroom 2,863 < 3,072). At 15:12:56
(available 2,018) standard refuses on RAM: 2,018 - 420 < 2,048. At 15:22:25 (available 2,431, 6,793
pages/s) it refuses on RAM (2,431 - 420 = 2,011) and on paging. Conservative refuses at all three.
These are the fixtures of step 12.

### Aggressive, clearly labelled

`aggressive` is for a founder who is watching the machine and prefers throughput to headroom.
`ramReserveMb` 1,536 is 360 MB above the lowest observed reap point, less than one goblin's working
set: **expect reaps**. `commitReserveMb` 2,048 is 5.5 percent of the limit. `pagingLimit` 4,000.
Hysteresis stays 768 for the correctness reason above. It still never kills: the ladder is the same
and every reap is surfaced. It can be selected only in the founder's user file (L1) or as a live rule
(L4) with an `until`; the checker refuses it anywhere else, and `horde watch` prints the tier in its
header whenever it is not `standard`.

## 1.3 Through the engine-settings layers

The tier is one more key in the layered configuration, the way metrics adds `metrics.*` (metrics
design 7.1): one resolver, one `explain`, no second configuration system.

- **Keys.** `admission.tier` names a tier. `admission.tiers[]` defines tiers: `{ name, rank, label,
  ramReserveMb, commitReserveMb, pagingLimit, pagingWindowSec, hysteresisMb, stableSec,
  reservationHoldSec }`. `rank` orders tiers from cautious (0) upward; the three built-ins are 0, 1, 2.
- **Where each may be set.** L0 ships `core/admission-tiers.json` with the three tiers and
  `admission.tier = standard`. L1 may select a tier and define custom tiers. L4 (live, `horde config
  set admission.tier conservative --scope live --until <t>`) lets the warchief tighten mid-work.
  **L2, L3 and L5 may not set it**: memory is a per-machine fact (design C3.4), so neither a cloned
  repository, a run spec nor a single spawn may change how full the whole machine gets. The checker
  (`Test-HordeEngineConfig`) refuses the key there, with the file and rule id.
- **Selectors.** A rule that sets `admission.*` must have an empty `match`; the gate resolves one tier
  per machine. Each machine resolves its own L1, so a remote machine can differ.
- **Checker findings**, all errors: a tier without every numeric key; a number below its floor
  (`hysteresisMb` below the goblin commit p90; any reserve below 0); two tiers with one name or one
  rank; an L4 rule selecting a higher rank than L1's resolved tier without an `until`.
- **`horde config explain --key admission.tier`** shows the tier, its layer and rule, every number,
  and, per number, whether the tuner has raised it (1.4).
- **Schema.** `schema/engine-config.v1` has `additionalProperties: false`; its `rule.set` gains an
  `admission` object. The engine-config schema has not shipped, so this lands in v1 before its first
  release (engine-settings Half A).

## 1.4 How the metrics system tunes the numbers

The gate's inputs come from the follower's operational stream (`obs.*`), which is content-free and
not gated by `metrics.level` (design B2.3); the tuner is the metrics module's (metrics design
section 12, Stage E).

- **Signals, per machine per day**: `obs.reap` events that happened while the gate was `open`, with
  the counters and tier at that moment; the minimum available memory and maximum paging seen while
  `open`; queue wait time and refusals per kind (the cost of caution); per-kind learned costs
  (p90 over the last 20 spans, floored at the design's priors).
- **Tightening is automatic.** A reap while `open` means the reserve was too small. The tuner writes an
  L4 rule raising `ramReserveMb` by 256 MB per such reap, with `until` seven days out and a `note`
  naming the reap events, capped at conservative's value plus 1,024 MB. `explain` shows it as the
  tuner's.
- **Loosening is a proposal.** After 14 days with no reap while `open`, `horde metrics tune --propose`
  prints a lower value with its evidence (minimum available seen, reaps, refusals); the founder
  applies it at L1 with `horde config set`. Nothing lowers a reserve on its own.
- **Costs are not tier values.** Learned per-kind costs change `cost(k)` in the rule, not the tier.
  They are measured by the follower's `obs.resources` samples and, for jobs, exactly by the job
  object's `PeakJobMemoryUsed` (Part 2).
- **Tokens and price stay out of admission.** Token counts are local-only and cost comes from the
  price table (metrics decision 7); neither feeds the gate.

---

# Part 2 - Process ownership: orphans prevented at spawn

## 2.1 What today's evidence requires

Every orphan class seen today must become impossible or reported.

| class | today | made impossible by | otherwise |
|---|---|---|---|
| O1 node dev servers and test runners outliving their goblin | 9 processes, 2,832 MB, 14 to 37 h (M-08) | the goblin's job, kill-on-close, held only by its anchor (2.2) | pre-Horde ones: reported |
| O2 a claude.exe with no pane and no control file | pid 5616, 555 MB, 21.9 h (M-07) | the harness is the anchor's child in the same job; when the pane dies the anchor dies and the job ends | reported |
| O3 a bare shell left in a pane | pane 26, 38.4 h (M-26) | the anchor is the pane's only program, no `-NoExit` shell (design decision 4) | old-style panes: closer fallback A3.3 |
| O4 a goblin's background job still running at close | M-22 | the closer refuses while a live job member is not a declared service; after the close the job ends it | - |
| O5 a process a goblin starts outside its job (WMI create, a scheduled task, an out-of-process COM server, a shell hand-off) | not seen today; documented escape | cannot be prevented by a job (2.4) | found by ancestry and job membership; reclaimed only with proof, else reported |
| O6 goblins spawned before Horde's spawn path, and the founder's own sessions | all of today's fleet | - | reported; W5 lists them in wezfleet now |

## 2.2 The anchor: how a job exists when the terminal, not Horde, is the parent

Horde asks the host to run an argv. The host creates the process, so its parent is the terminal
(measured: the pane shells' parent is the terminal GUI process, J-1), and Horde never holds a handle
from `CreateProcess` that it could assign before the child runs. The fix is to make the first program
in the pane assign **itself**:

1. The argv the host runs is the **anchor**, a small compiled helper (the design's CTRL_C helper,
   grown; the `wf-cmdlog.exe` precedent for a compiled tool). It is the pane's only program.
2. The anchor creates a job with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` and **no** breakaway flag, with
   a **non-inheritable** handle, named `Local\horde-<spawn token>` so the follower can open it by
   name.
3. It calls `AssignProcessToJobObject(job, GetCurrentProcess())` **before it creates any process**.
   Everything created afterwards through `CreateProcess` is in the job (J-3, and the docs below).
   J-3 also shows why the order is fixed: a child created before the assignment is not in the job and
   survives the close.
4. It runs Horde's launch stub (`horde launch --job <id>`, engine-settings section 9) as a child,
   which resolves the binding, the credential references and the environment scrub, and hands the
   anchor the final argv and environment over a pipe (secrets exist only in memory and in the
   harness's environment, never on disk). The stub exits; its PowerShell cost is transient.
5. It starts the harness, records `{ anchor pid+procStart, job name, harness pid+procStart }` in the
   containment record, and waits.
6. When the harness exits, the anchor writes the exit code and exits. Its handle was the only one, so
   the job closes and every remaining member dies (J-3). The pane's program has exited, so the pane
   closes (host flag `spawn.exitCloses`, 2.5).

The anchor also receives the closer's graceful-end request (a named event per spawn token), sends
CTRL_C twice to its console group, waits up to 12 s, then calls `TerminateJobObject`. That replaces
the design's separate console-attach helper: the anchor already shares the console.

**Who else holds the job handle.** The follower opens the job by name only to query it
(`JobObjectBasicProcessIdList`, `JobObjectExtendedLimitInformation` for `PeakJobMemoryUsed`) and
closes it in the same call. While it holds a handle, a close is deferred by at most that call's
duration, and then happens anyway, because kill-on-close fires on the last close. A test pins the
query's handle lifetime.

**Resident cost.** A native helper waiting on one process should be a few MB, against 58 to 66 MB
for today's `-NoExit` shell (M-10). That is a target, measured in step 15, not a claim.

## 2.3 What the Windows documentation says, and what was measured here

- **A running process can be assigned after spawn.** `AssignProcessToJobObject` takes any process
  handle with `PROCESS_SET_QUOTA` and `PROCESS_TERMINATE`. "If the process is already associated with
  a job, the job specified by hJob must be empty or it must be in the hierarchy of nested jobs to
  which the process already belongs, and it cannot have UI limits set." Before Windows 8 the call
  failed with `ERROR_ACCESS_DENIED` for a process already in a job.
  https://learn.microsoft.com/en-us/windows/win32/api/jobapi2/nf-jobapi2-assignprocesstojobobject
  Measured: J-3, two running processes already in the ambient job, assigned: ok.
- **Children created before assignment are not moved.** The docs say children are associated when
  created ("After a process is associated with a job, by default any child processes it creates using
  CreateProcess are also associated with the job"), and "the association cannot be broken".
  https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects
  Measured: J-3, the pre-assignment ping stayed outside and survived.
- **Nested jobs work on Windows 8 and later, so on Windows 10 and 11.** "Nested jobs were introduced in
  Windows 8 and Windows Server 2012." "If a process that is already in a job is added to another job,
  the jobs are nested by default if the system can form a valid job hierarchy and neither job sets UI
  limits." https://learn.microsoft.com/en-us/windows/win32/procthread/nested-jobs
  Measured: J-1 and J-2, every process here is already in an ambient job; J-3, nesting under it
  succeeded on 10.0.26200. Windows 10 was not measured; the documentation covers it.
- **Kill-on-close reaches nested jobs.** "Causes all processes associated with the job to terminate
  when the last handle to the job is closed."
  https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-jobobject_basic_limit_information
  "If a nested job has the JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE flag specified, closing the last job
  object handle terminates all processes associated with the job and its child jobs in the hierarchy."
  (job-objects page, above). "When a job in a job hierarchy is terminated, the system terminates
  processes in that job and all of its child jobs" (nested-jobs page).
- **Breakaway stops at a job that forbids it.** With `CREATE_BREAKAWAY_FROM_JOB`, "If the calling
  process is associated with a job, the job must set the JOB_OBJECT_LIMIT_BREAKAWAY_OK limit."
  https://learn.microsoft.com/en-us/windows/win32/procthread/process-creation-flags
  In a hierarchy, a child breaking away "moves up the hierarchy until it reaches a job that does not
  permit breakaway" (nested-jobs page). So node's own silent-breakaway job (J-4), nested inside the
  goblin's job, lets a node child leave node's job but not the goblin's. And libuv never asks for
  breakaway on detached children (J-4), so a detached `next dev` stays in the goblin's job.
- **One documented hole.** "Child processes created using Win32_Process.Create are not associated
  with the job." (job-objects page). Any process started by another process outside the job (WMI's
  provider host, the task scheduler, a COM server, the shell) is likewise outside it. That is class
  O5, handled by the backstop (2.6).
- **Accounting.** `JOBOBJECT_EXTENDED_LIMIT_INFORMATION.PeakJobMemoryUsed` gives a job's peak commit,
  and nested accounting aggregates into parent jobs (nested-jobs page), so a heavy job's own nested
  job measures it exactly while the goblin's job still counts it.

## 2.4 Escapes, each with its disposition

| escape | disposition |
|---|---|
| E1 a child created before the anchor assigns itself | impossible by construction: the anchor assigns itself before its first `CreateProcess` (J-3 is the control that shows the hole it closes) |
| E2 `CREATE_BREAKAWAY_FROM_JOB` | impossible: the goblin's job never sets a breakaway limit, so the create fails instead of escaping. That failure is honest and visible as a tool error. Whether the harness itself ever asks for breakaway is **unmeasured**; step 15 runs a real harness session inside such a job in the isolated instance and must pass |
| E3 WMI `Win32_Process.Create`, scheduled tasks, services, out-of-process COM, shell hand-off | cannot be prevented by a job. Found by the backstop; reclaimed only with proof (2.6), otherwise reported |
| E4 a goblin spawning another goblin through the host | not an escape: the new pane gets its own anchor and job, and its own record naming its parent |
| E5 the anchor killed or crashed | the handle closes and the job ends everything in it: the intended result |
| E6 a declared service that must outlive the goblin | never started inside the goblin's job, because a process cannot leave it. `horde job run -Service -Until <t>` asks Horde's actor to start it in a service job with no kill-on-close, recorded with its owner and expiry; the actor ends it at expiry. If the actor is down, the record still proves ownership for later reclaim |
| E7 assignment refused (a UI-limited ambient job, a changed Windows) | the anchor refuses to start the harness and reports `containment unknown: assign failed, <error>`. `horde install` runs the J-3 probe once per machine and records `contain.nest` |

## 2.5 Host capability flags

Added to the closed vocabulary of `schema/host-capabilities.v1` (hosts research 5.1), each `{ state,
evidence, minVersion?, space? }`, measured in the host's isolated instance by its conformance suite:

| flag | meaning | why the anchor needs it |
|---|---|---|
| `spawn.program` | the host runs the given argv as the pane's only program, with no shell around it | O3: no bare shell after exit |
| `spawn.exitCloses` | the pane closes when that program exits (and whether only on a clean exit) | the close path never needs a pane-id kill (design A3.1 step 4) |
| `spawn.parent` | `host` or `caller`: whose child the pane's program is | `host` means only self-assignment can contain it; `caller` would allow assign-before-resume |
| `spawn.env` (existing) | the host can pass environment | the spawn token reaches the anchor; with `no`, the token goes in the argv |
| `pid` with `space` (existing) | the anchor's pid and its namespace | containment is resolved in that space: a `win32` pid uses a job; a `wsl:` or `posix` pid uses the POSIX mechanism below |
| `contain.inherited` | the host's own pane processes already sit in a job or control group, and whether it allows breakaway | nesting is required; recorded so a change in the host is noticed (J-1, J-2) |

The containment mechanism itself is the operating system's, not the terminal's. It is a small port,
`core/Contain.ps1`, with adapters `platform/windows/` (job objects, above) and later
`platform/posix/`: a cgroup v2 per goblin where available, ended through `cgroup.kill` ("Writing '1'
to the file causes the cgroup and all descendant cgroups to be killed ... deal with concurrent forks
appropriately", https://docs.kernel.org/admin-guide/cgroup-v2.html); else the anchor as a
`PR_SET_CHILD_SUBREAPER` so orphans re-parent to it rather than to init (Linux 3.4,
https://man7.org/linux/man-pages/man2/PR_SET_CHILD_SUBREAPER.2const.html), plus its process group;
macOS declares `contain: partial` with that reason. The port reports `contain` as `job`, `cgroup`,
`subreaper`, `pgroup` or `none`, each a tristate with evidence. Windows agents only for now (hosts
decision 1), so only the Windows adapter is built in this plan.

## 2.6 The backstop: ancestry-based orphan finder

Windows does not re-parent orphans, and a dead parent's pid may already belong to another process
(design A3.5). So ownership is proven by evidence recorded while the owner was alive, in this order:

1. **Job membership.** The process is in a Horde goblin's job (queried by job handle). Strongest.
2. **Recorded descent.** Its pid and procStart appear in a follower `obs.resources` sample as a
   descendant of a Horde-spawned session (the design's "record descendant pids at each sample").
3. **Ancestry through a recorded session.** Walking `ParentProcessId`, each hop's parent was created
   before its child (a reused pid fails this), and the walk reaches a Horde session's recorded
   pid+procStart, live or tombstoned.

Anything else is `orphaned, owner unknown` in `horde status` and `horde watch`, with memory, age, image
name and cwd, for the founder to decide. Reclaim acts only on proof 1 to 3, never on a declared live
service, through the handle method (open by pid, compare the creation time read from the handle,
terminate through that handle), and writes `obs.orphan` with the proof used. The report is read-only
and ships in Phase 3's read half; the reclaim ships with the closer in Phase 5.

---

# Part 3 - Automatic close after proof, and the resume binding

## 3.1 The binding is the single source of truth

The founder's precondition for automatic close: the goblin's resume information lives in Horde's
session record, is current, and an orc can read and use it in one step. The binding is:

| binding part | record field | owner (`core/ownership.json` vocabulary) | notes |
|---|---|---|---|
| harness | `engine.harness` | `engine` | fixed at spawn; resume can never change it (engine-settings 7) |
| provider profile | `engine.providerProfile` | `engine` | a profile name, never an endpoint copy or a key |
| model | `engine.model` (concrete id), `engine.requested` | `engine` | pinned at spawn; `modelObserved` (owner `agent`, derived) is shown beside it, never merged |
| session id | `sessionId` | `agent` | set in advance where the harness allows it (`--session-id` for claude-code, local help); learned from the harness's files otherwise |
| cwd | `projectCwd` | `engine` | the launch directory, which names the transcript folder |
| argv | `launch.argv` | `engine` | the argv the AgentPort built, without the session-specific resume flag, which the AgentPort adds |
| environment block | `launch.env[]`: `{ name, value }` or `{ name, ref: { kind, ref } }` | `engine` | non-secret values literally; secrets only as references (engine-settings 6); the checker refuses a secret-shaped value |
| currency | `binding.revision`, `binding.verifiedAt`, `binding.previous[]` | `engine` | revision increments on every rebind |
| containment | `containment`: `{ mechanism, name, anchorPid, anchorProcStart, space }` | `engine` | Part 2 |
| close | `closeOn` (`proof`, `routed`), `park`: `{ reason, until }`, `closure`: `{ state, at, tombstone }` | `engine` | Part A of the design |

`resumeCommand` stays an `agent`-owned, **derived** field, but its derivation changes: the AgentPort
renders it from the binding above. wezfleet's `resume.txt`, the status snapshot's `resumeCommand`
(W5) and the layout saves' argv (R1) stay shadow-only reads, never answers. Nothing else stores a
resume path, which is what makes the binding the single source.

## 3.2 Kept current

- **Compaction keeps the session id** (measured: 12 compactions in 7 live processes and 51 in 265
  transcripts, no second id; `core/ownership.json`, `formerNames`). So compaction needs no rebind.
- **What does need one**: an orc re-resuming a goblin (`horde resume` writes the new revision itself),
  a harness that forks a new id on resume, and anything that starts a new conversation in the same
  process (whether `/clear` does is unmeasured). The follower watches the agent's control file for the
  goblin's pid+procStart; when the session id it carries changes, it emits `obs.rebind` with both
  ids. The follower never writes records; the record writer (migration-plan step 3.8, its one writer)
  subscribes and writes the new revision.
- **The file name is the session id** (step 3.8). A rebind that changes the id writes a new record and
  links the two (`predecessor`, `successor`); `horde goblin show` follows the chain to its head, so an
  orc's handle never goes stale.
- **Verified at close.** The closer's first step (design A3.1) re-reads the binding, confirms the
  transcript exists and records its byte length; a binding that cannot be verified makes the goblin
  `unknown`, and unknown never closes.

## 3.3 `horde goblin show` and `horde resume`

```
horde goblin show <label|fleetId|sessionId> [--json]
horde resume <label|fleetId|sessionId> [--model <alias|id> | --reresolve] [--dry-run] [--print]
```

`goblin show` prints, in one screen: the binding (every row of 3.1 with its revision and `verifiedAt`),
the current state and its evidence (the same answer as `horde why`), the closure record, the handoff
path, the transcript path with its recorded and current length, and the exact resume command. `--json`
gives the same as data, so an orc reads one object.

`resume` does the whole step for the orc: resolve the chain to its head; refuse if the transcript is
shorter than recorded (design A3.2); refuse a harness change; refuse if the provider profile or its
credential reference no longer resolves (never a fallback to the default profile); ask the gate for
admission at the `unblock` priority; spawn through the host with a fresh anchor; write the new
binding revision. `--print` prints the argv and environment references for a person to run by hand,
and does nothing. `--dry-run` shows what `resume` would do, with the gate's answer.

## 3.4 Schema and ownership changes

- `core/ownership.json`: new rows `engine`, `launch`, `binding`, `containment`, `closeOn`, `park`,
  `closure`, `predecessor`, `successor` (owner `engine`), and `modelObserved` (owner `agent`,
  derived); `resumeCommand`'s `derived` text changes as in 3.1. New stores, so provenance can name
  them: `H1` Horde session record (`<HordeHome>\store\sessions\<sessionId>.json`), `H2` the
  observation stream (`<HordeHome>\store\observe\<date>\<machineId>.jsonl`), `H3` closure tombstones,
  `H4` spawn claims (`runs\<id>\spawns\<fleetId>.claim`), `X7` the Codex rollout, `X8` the harness's
  background task output files, `X9` the loop-guard state file.
- `schema/session-record.v1`: `additionalProperties` is false, and
  `test/test-schema-session-record.ps1` computes the property list from the ownership table, so each
  row and its schema property land in one PR. The session-id pattern stops assuming a UUID (agent
  engines decision 6). Edit v1 or publish v2 is still open (engine-settings decision 5, below); it is
  safe as an edit only until step 3.8 writes the first record.
- `schema/observe-event.v1`: the metrics envelope (metrics design 4.2) with the `obs.*` kinds.
- `schema/host-capabilities.v1`: the flags of 2.5.

---

# Part 4 - The transcript port and the one follower

## 4.1 One abstraction in core, adapters per engine

`core/Transcript.ps1` defines the port and names no engine. Each adapter lives in
`agents/<name>/Transcript.ps1` and is registered by its `agent.json`. Order: `claude-code` and `codex`
first, then `gemini-cli`. GLM, Qwen and DeepSeek are not adapters: they are provider profiles driven
through the claude-code harness (agent-engines decision 2), so they are read by the claude-code
adapter, and their differences are capability flags on the (harness, provider) pair.

**Operations** (each returns `core/tristate` answers; an unreadable source is unknown with its reason):

| operation | input | output |
|---|---|---|
| `Get-TranscriptCapability` | harness, provider profile | the flags of 4.3, each `{ state: yes, no, unmeasured; evidence }` |
| `Find-Transcript` | a binding | the transcript file(s) and their identity (path, file id, creation time); the Claude rule is `transcriptPath`'s derivation in `core/ownership.json` |
| `Open-TranscriptCursor` | a file, a stored cursor or none | a cursor `{ fileId, offset, carry }`; a file shorter than the offset, or with another file id, yields `truncated` or `replaced`, never a silent restart |
| `Read-TranscriptEvents` | a cursor | the unified events (4.2) for the complete lines past the offset, and the new cursor; a partial last line is carried, not parsed |
| `Get-SessionSideSignals` | a binding | the harness's other files: control file status, background task outputs (size, mtime), loop-guard ring, where the harness has them |
| `Get-UsageFacts` | a cursor, the consent sentinel | per-turn token counts and model, only when the span's resolved `metrics.level` is `usage` or `full` (metrics 7.4); nothing otherwise |

## 4.2 The unified event

One line of `obs.transcript` body, content-free by construction (design C3.1 privacy rule):

```
t           ISO 8601 UTC, from the transcript line
sessionId   the harness's id
kind        turn.start | turn.end | assistant | thinking | tool.call | tool.result |
            task.start | task.done | task.killed | reap | compact | user.input |
            notification | queued | error | model
callId      pairs tool.call with tool.result, and task.start with task.done or task.killed
tool        { name, sigHash }        sigHash: salted hash of the normalised input (metrics salt)
result      { ok, errHash? }         errHash: salted hash of the normalised error text
task        { id, outputPath? }
model       the model id on the line, when the harness writes one
usage       { input, output, cacheRead, cacheWrite, reasoning }   only through Get-UsageFacts
bytes       the line's length
source      { store, file, offset }  in core/ownership.json's store vocabulary
confidence  reported | derived | estimated | unknown, with reason when unknown
```

No message text, no tool arguments, no file contents. A test feeds a transcript with planted marker
text and asserts the marker appears in no output line.

## 4.3 Capability flags each adapter declares

| flag | claude-code | codex | gemini-cli | via claude-code: GLM, Qwen, DeepSeek |
|---|---|---|---|---|
| `transcript.tail` (append-only, line-delimited, tailable by offset) | yes: M-50, M-51 | yes: rollout JSONL (metrics 2.5) | unmeasured: docs only | as claude-code |
| `turn.end` marker | yes: `system/turn_duration`, `stop_hook_summary` (design C1) | unmeasured | unmeasured | as claude-code |
| `tool.pairing` | yes: tool_use / tool_result ids | unmeasured | unmeasured | as claude-code |
| `task.background` start and completion | yes: task notifications | unmeasured | unmeasured | as claude-code |
| `reap.notice` | yes: `<status>killed</status>` user line (M-33) | no reaper known | unmeasured | as claude-code |
| `tokens.perTurn` | yes | no: cumulative only | unmeasured | **estimated** where the endpoint lacks token counting (agent-engines section 3) |
| `tokens.cumulative` | no | yes: `total_token_usage` (metrics 2.5) | unmeasured | no |
| `cache.fields` | yes | unmeasured | unmeasured | **no** for DeepSeek, which ignores `cache_control` (agent-engines section 3) |
| `model.perMessage` | yes | yes: session start `model` | unmeasured | yes, the provider's id |
| `compact.marker`, `sessionId.stableAcrossCompact` | yes, yes (ownership `formerNames`) | unmeasured | unmeasured | as claude-code |
| `status.file` | yes: control file (X2) | no native file (measured); Horde's hook-written file stands in | unmeasured | as claude-code |
| `loopGuard` | yes where the founder's hook is installed | no | no | as claude-code |

`unmeasured` never satisfies a requirement: the classifier answers `unknown: <flag> unmeasured for
<harness>` rather than guessing. A flag moves to `yes` only through a measurement recorded in that
agent's ledger (`planning/ledger/agent-<name>.md`), as agent-engines 6.4 requires.

## 4.4 The follower: one per machine, one reader

`horde follow` is one long-lived process per machine, installed by `horde install` as a per-user
scheduled task at logon (design C3.1). It is the **only** reader of transcripts:

- It tails every tracked session through the port (2 s poll, a file-system watcher to shorten it, the
  poll kept as the correctness path), samples processes (5 s CPU, 30 s CIM tree with parents, job
  queries for anchored goblins), and writes one stream, H2, one file per writer with a daily cap.
- **Two consumers, one input.** The watcher classifier (`core/Observe.ps1`: working, waiting on a job,
  waiting on a human, stalled, looping, dead, plus reported, closable, parked; design C2's evidence
  and thresholds) and the metrics collector both read H2. The metrics harvester reads transcripts
  directly only for spans the follower never saw and that have consent; there is no backfill from
  before consent (metrics decision 8). Token counts reach metrics only through `Get-UsageFacts`, from
  local files (metrics decision 7); cost is computed later from the versioned price table
  (`core/Price.ps1`).
- **It never acts.** The observer's files hold no spawn, kill or send verb, checked by the same
  tripwire as the Phase 3 read adapter. The actors (closer, gate pump, reclaimer, service keeper) are
  separate modules that subscribe to H2; they may share the process from Phase 5, but not the files.
- Footprint target under 100 MB private, measured in step 8 (design decision 10: PowerShell first,
  compiled only if the measurement exceeds the target).

---

# Part 5 - Seeing and being told: `horde watch`, `horde why`, wake messages

- **`horde watch [-Orc X] [-Goblin Y] [-Json]`**: a live table from H2, one row per goblin: state,
  the reason in one line, age of the newest evidence, RAM and commit (from the job when anchored),
  the running tool or job, and the gate's state and tier in the header. It tails the stream; it never
  opens a transcript. Orphans of unknown owner get their own section.
- **`horde why <goblin> [-Json]`**: the current state and every piece of evidence behind it, each with
  its source store, file, offset and time, in `core/ownership.json`'s vocabulary. The command an orc
  runs when a goblin looks idle. It is the same answer `horde goblin show` embeds.
- **Wake messages.** On a transition to `stalled`, `looping`, `reported`, `dead`, `park-expired`,
  `closed` or `reaped`, the alerter sends one message to the owning orc, keyed by (goblin, transition,
  evidence seq) so a restart never repeats one. Content: goblin, state, one-line reason, handoff path,
  and the next command (`horde why`, `horde goblin show`, `horde resume`). Delivery goes through the
  target resolution of Phase 3 step 3.6 and the platform's messaging path; until that lands,
  wezfleet's `tell`. Unreachable orc: the warchief. Unreachable warchief: a Windows notification to the
  founder. A message arrives as a new turn, which is what wakes an orc that ended its turn to wait.
  Rate limit: one per goblin per transition, and at most 10 per orc per minute with the rest folded
  into one summary.

---

# Part 6 - wezfleet stopgaps carried over

W1 (`status` stops pumping) and W2 (the roster written per spawn) are already being built. W3 to W5
are done in `YedPool/wezfleet`, under its own CONTRIBUTING (worktree in `wezfleet-worktrees`, never
test against the working terminal, `--merge`), because Horde's writers are phases away and these are
live defects.

| # | change | tests first | why now |
|---|---|---|---|
| W3 | `Close-WfOwnPane` (lib/Notify.ps1:178): re-verify identity at kill time; skip the kill while any descendant of the claude process is alive; go through Kill.ps1's ladder and its never-empty-a-window guard, not a raw `kill-pane` after a sleep | "closeOnDone spares a goblin with a live child"; "closeOnDone re-verifies the pane at kill time"; "closeOnDone never empties a window" - each mutation-tested, in the isolated instance only | issue #38 and M-22: a destructive path with a known pane-reuse hole that also kills work started after the report |
| W4 | `Test-WfPaneMatchesRoster` answers "cannot prove" for a roster pane of -1, and closeOnDone does not fire on it | "a roster pane of -1 cannot prove identity"; "closeOnDone does not fire without proven identity" | design A5.5: after an interrupted launch the check passed for any pane |
| W5 | census lists orphaned process trees with memory, read-only: roots dead, a claude with no control file, a bare shell in a spawned pane | "census lists a tree whose root is dead"; "census lists a claude with no control file"; a read-only tripwire over the new code | 2.8 GB was invisible to every command (M-08); this is O6's report until Horde's ships |

Not a stopgap: making reaped jobs visible in wezfleet. That belongs to the follower, and doing it twice
is what the one-reader rule forbids.

---

# Steps

Numbered through; the design's H-numbers in brackets for traceability. Phase gates follow the
migration plan: read-only steps sit beside Phase 3; anything that spawns, kills or writes a record
waits for Phase 5 (and step 3.8 for the record writer).

## A. Now, in wezfleet

1. **W3.** Tests first as in Part 6; ledger not required (wezfleet is not being replaced by this step).
2. **W4.**
3. **W5.**

## B. The read half (beside Phase 3; no writer, no act verb)

4. **`core/ProcessTree.ps1`** [H1]. One CIM snapshot to a tree with pid+procStart; the dead-root walk;
   descendants of a session; the three ownership proofs of 2.6 as pure functions over injected tables.
   Tests first: "a reused pid never extends an ancestry"; "a child older than its parent breaks the
   walk"; "an unreadable table reads as unknown"; "ownership needs one of three proofs". Ledger
   `planning/ledger/core-processtree.md`: wezfleet `lib/Mail.ps1` liveness, census, lesson L-019.
5. **`core/Transcript.ps1` and `schema/observe-event.v1`** [H5]. The port of 4.1, the event of 4.2,
   the stream writer (one file per writer, cap, `truncated` marker, `seq` from the writer's counter).
   Tests first: "a shorter file is truncated, never restarted"; "a partial last line is carried";
   "seq is strictly increasing within a file"; "core names no engine" (the port-names ratchet,
   engine-settings 9, extended to `agents/`). Ledger: none replaced.
6. **`agents/claude-code/Transcript.ps1`** [H3]. Tail by byte offset; control file; task outputs;
   loop-guard read; capability file with evidence. Tests first against copies of today's four goblin
   transcripts cut down: "a reap notice becomes a reap event"; "no message text reaches the output"
   (planted marker); "an unmatched tool call stays open". Ledger `planning/ledger/agent-claude-code.md`
   (transcript half): wezfleet `lib/Delivery.ps1` receipt reading, cmdlog hook, loop-guard hook.
7. **`agents/codex/Transcript.ps1`** [H4]. Rollout tail; cumulative tokens as `usage.snapshot`, never
   summed. Tests first from the one real rollout. Ledger: `lib/CodexStatus.ps1`.
8. **`core/Observe.ps1`, the classifier** [H2]. The pure function of design C2 over injected
   observations. Tests first, one fixture per state from today's transcripts (M-31 to M-34): "waiting
   on a live job is never stalled"; "a report with a live child is not closable"; "a reap then silence
   is stalled after two minutes"; "an unmeasured flag answers unknown, never a state".
9. **`horde follow`** [H6]. The loop, the scheduled-task install through `horde install`, the tripwire
   that finds no act verb in the observer's files, the job-handle lifetime test. Gate: one hour in the
   isolated harness, private bytes measured and reported against the 100 MB target.
10. **`horde watch` and `horde why`** [H7]. Read commands over H2, `-Json`, two end-to-end scenarios
    each (Phase 3 rule). Tests first: "watch never opens a transcript".
11. **Wake messages** [H8]. Tests first with a fake orc target in the isolated harness: "one message per
    goblin per transition"; "a restart does not repeat a message"; "an unreachable orc escalates to the
    warchief". Uses wezfleet's `tell` until step 3.6's target resolution is adopted.
12. **Orphan report** [H18, first half]. Read-only: classes O1 to O6 in `horde status` and `horde
    watch`. Tests first: "an orphan without proof is reported, never reclaimed"; "a planted kill verb
    turns the tripwire red".
13. **`effects` declarations** [H13]. Every command declares read, write, spawn or kill; a suite proves
    read commands reach no spawn or kill verb, with a planted-verb control. Early, because it guards
    every step after it.

## C. Admission, consulted then shadowed

14. **Tiers in configuration.** `core/admission-tiers.json` (L0), the `admission` keys in
    `schema/engine-config.v1`, the checker findings of 1.3, `explain` output. Tests first: "a project
    file may not set the admission tier"; "hysteresis below a goblin's commit is refused"; "aggressive
    needs an until at the live layer"; "no environment variable changes the tier" (with a control that
    the config file does).
15. **`core/Admission.ps1`** [H9]. Rule, reservations, hysteresis, priority queue, as a pure function;
    `horde admit --kind k --json` answers admit or queue with reasons and acts on nothing. Tests first:
    "standard refuses a goblin at 15:05 counters"; "standard refuses at 15:12 and 15:22 counters";
    "conservative refuses at all three"; "one close never reopens the gate". Ledger
    `planning/ledger/core-admission.md`: wezfleet `commands/pump.ps1` caps, `liveTotal + spawned`,
    "wezterm did not answer" queues.
16. **Per-kind costs** [H10]. `obs.resources` to p90 per kind over 20 spans, floored at the priors.
17. **Tier tuning.** The tighten-only L4 writer and `horde metrics tune --propose` of 1.4. Tests first:
    "a reap while open raises the reserve"; "nothing lowers a reserve without the founder". Shadowed:
    proposals logged for a working week before any L4 write.

## D. Containment

18. **`core/Contain.ps1` and `platform/windows/`**. Create, name, self-assign, query members and peak,
    terminate. Tests first, turning J-3 into a suite that acts only on processes it created: "a child
    created before assignment escapes" (the control); "a child created after assignment dies with the
    job"; "the job handle is not inherited by a child"; "assignment nests under an ambient job".
    Machine probe for `horde install`.
19. **The anchor**, compiled, plus the host flags of 2.5 in `hosts/wezterm/capabilities.json`, measured
    in the isolated instance. Tests first: "a pane whose program exits closes"; "closing the pane ends
    the harness and its children"; "a real harness session runs inside a no-breakaway job" (E2, the
    cheapest prompt that proves it, CONTRIBUTING 3); the anchor's resident memory measured.
20. **`horde job run`** [H11]. Admission request, a nested job per heavy job, `PeakJobMemoryUsed`
    recorded, the `DONE=` marker, `-Pausable`, `-Service -Until`. Tests first: "a job's peak equals the
    job object's figure"; "a service outlives its goblin only until its expiry". The pause mechanism is
    unmeasured and chosen in this step.

## E. The writers (Phase 5, and step 3.8 for the record)

21. **The binding in the record.** Ownership rows and schema of 3.4 in one PR; the record writer applies
    `obs.rebind`. Tests first: "a compaction keeps the binding revision"; "a new session id links
    predecessor and successor"; "a secret-shaped env value is refused".
22. **`horde goblin show` and `horde resume`.** Tests first: "resume refuses a shorter transcript";
    "resume refuses a harness change"; "resume never falls back to the default profile"; end-to-end in
    the isolated harness.
23. **Spawn claims** [H12]. `CreateNew` claims, spawn token, `spawn-unknown`, `launch --resume`. Tests
    first: "two pumps, one spawn"; "a killed pump leaves no duplicate". Ledger: `commands/pump.ps1`.
24. **Goblin spawn through the anchor** [H15]. The pane's program is the anchor, never a shell.
25. **The closer** [H14]. Design A1 states, A3 order, the handle-based end through the anchor, the
    tombstone, the orc notice. Isolated harness only; every refusal mutation-tested; the victim guard of
    CONTRIBUTING 9. Ledger `planning/ledger/core-closer.md`: `lib/Cleanup.ps1`, `lib/Kill.ps1`,
    `lib/Notify.ps1` `Close-WfOwnPane`, wezreport's closeOnDone and `resume.txt`.
26. **`horde route` and `horde park`** [H16]. Park requires a reason and an expiry capped at 24 h.
27. **Worktree reaper** [H17]. The design's four conditions on `work-merged`, each refusal tested.
28. **Orphan reclaim** [H18, second half]. Proven ownership only, handle method, `obs.orphan` with
    the proof. Tests first: "reclaim cannot choose its victim".
29. **The gate acting** [H19]. The actor pumps queued spawns on `open`; the ladder of design B2.6.
    Shadowed against wezfleet's pump for a working day before it acts.

Order: A now. B next, in the order given; it answers "what is every goblin doing, and what holds
memory" with no writer. C and D after B, consulted and shadowed before anything acts. E with Phase 5.

---

# Unproven, and written down

- The Windows threshold behind the reaper's `critical` level (M-30). The standard tier rests on where
  reaping was observed, not on that threshold.
- Whether the pagefile is system-managed, which decides what commit near its limit does.
- Whether the Claude Code harness, or any tool it runs, ever creates a process with
  `CREATE_BREAKAWAY_FROM_JOB`; if it does, that create fails inside a goblin's job (step 19 measures).
- Whether `/clear` gives a running session a new id (ownership `formerNames` is provisional on it).
- The anchor's resident memory, and the follower's (targets, not measurements).
- Windows 10 nesting: documented, not measured here (J-3 ran on 10.0.26200).
- Whether the terminal's default closes a pane only on a clean exit; a harness that exits non-zero
  might leave its pane open (step 19 measures `spawn.exitCloses`).
- Every `unmeasured` cell in 4.3.

# Still with the founder

1. Should the tuner raise admission reserves by itself after a reap while the gate was open (as a live
   rule that expires after 7 days, capped at the conservative value plus 1 GB), with any lowering only
   ever proposed to you, or should it only propose in both directions?
2. Adding the resume binding and the `engine` field changes the stored session record, whose schema
   refuses unknown properties: edit `session-record.v1` in place (safe only until the record writer of
   step 3.8 has written a first record) or publish `session-record.v2`?
3. Where should Horde's home folder default to when `HORDE_HOME` is not set: a `.horde` folder under the
   user profile (the unmerged Phase 3 plan already puts its shadow logs under `%USERPROFILE%\.horde`),
   or somewhere else?
4. May the anchor be a small compiled executable (like wezfleet's `wf-cmdlog.exe`), since a PowerShell
   anchor would stay resident at about the 58 to 66 MB a pane shell costs today for every goblin?
