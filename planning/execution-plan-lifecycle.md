# Execution plan: goblin lifecycle, admission and live visibility

Proposed 2026-09-30, from designs whose decisions the founder settled the same day. This plan orders
the work that makes the fleet (1) admit work by measured resources in named tiers, (2) own every
process a goblin starts so nothing is orphaned, (3) close a finished goblin automatically once its
report is proven and its resume binding is current, (4) read every engine's transcript through one
port and one per-machine follower, and (5) show and push what every goblin is doing, in a form that
does not flood an orc's context. It cuts across Phase 3 (the read half) and Phase 5 (the writers) of
`planning/migration-plan.html`, and carries three wezfleet stopgaps that cannot wait for either.

Planning prose may name terminals and engines. Code may not: CONTRIBUTING 14 keeps terminal names in
`hosts/<name>/`, and the same ratchet extended to `agents/<name>/` (engine-settings design section 9)
keeps engine names there. Every path below respects that; where a step needs a name, the step's file
is under the right folder.

## Sources, and what is settled

The designs were written in a working session and are not yet committed; their measurement ids are
cited here as written there, and the rows this plan depends on are copied into "Measurements" below
so the plan stands alone. Every decision below is settled; nothing in this plan is waiting on the
founder.

| design | settled decisions this plan implements |
|---|---|
| lifecycle-admission design (2026-09-30) | Its "Decisions taken (founder, 2026-09-30)": 1 named admission tiers, the proposed values are "conservative", a bolder "standard" is the default, set through the engine-settings layers, tuned by metrics; 2 Horde prevents orphans (descendants tied to the goblin's lifetime, e.g. a Job Object with kill-on-close) and reclaims escapes only with proven ownership, reporting the rest; 3 automatic close after proof, on the precondition that the resume information is the single source of truth, current, and easy for an orc to read and use; 4 a transcript port with an adapter per engine under `agents/<name>/`, core naming none; 5 its recommendations 2, 3, 4, 5, 7, 8, 9, 10, 11, 12 and 13 stand (park with mandatory expiry, handle-based end, no shell around the agent, report-only for unproven orphans, reaper left on, pause-never-kill ladder, one follower as the only transcript reader, follower in PowerShell first, wake messages, `horde job run` for heavy work, the wezfleet stopgaps) |
| engine-settings design | Its "Decisions taken": 1 no environment-variable layer for engine values; **2 `HORDE_HOME` defaults to `%USERPROFILE%\.horde`**; **3 the project engine file waits until a repo needs one, and may then only choose among user-defined providers and only lower the metrics and admission levels, never raise them**; 4 aliases pinned to a concrete id at spawn; **5 the engine and resume-binding fields are added by editing `session-record.v1` in place, safe because no writer exists until migration step 3.8; after that, any change needs a v2**; 6 resume uses the launched binding, and `/model` drift is shown in status and does not rebind; 7 the model ids; 8 selector ranks as designed; **9 the admission tuner may raise reserves automatically after a reap while the gate was open, as a live rule that expires after 7 days, capped at conservative + 1 GB; lowering is only ever proposed**; **10 the pane anchor is a small compiled executable, following `wf-cmdlog.exe`** |
| metrics design | Its "Decisions taken": no environment switch for metrics; the project layer may lower the level, never raise it; prompts only as a salted fingerprint; quota plus labelled notionalUsd on subscriptions; retention 30 days / 1 year / forever; scoring published; **decision 7 as changed by the founder: tokens and usage are counted only from local sources (transcripts, rollouts, harness logs), never from a provider's usage or billing API; cost is computed separately from token counts and a versioned price table; `reconcile` and the `metered` tier are dropped**; no backfill from before consent. Its "Founder direction": goblin-versus-agent is a central pillar; stalls, loops, missed communications and wasted tokens are first-class detectors that record their token and time cost and feed an improvement backlog; orc and warchief context is reserved for big-picture thinking, and context tokens per delivered result are measured |
| agent-engines research | Its "Decisions taken": every role resolves a named profile of harness + provider profile + model; GLM, Qwen models and DeepSeek run through the Claude Code harness on Anthropic-format endpoints first; Gemini CLI gets `agents/gemini-cli/`; the session-record key stops assuming a UUID; subscription credentials only on their own vendor's CLI; keys read from named environment variables, never stored |
| remote design, and the remote plan (in progress, branch `docs/remote-plan`) | Settled remote decision 3: the session record splits into a **fleet record**, written by the hub, and a **binding record**, written by the node, owner `node`. The resume binding and `engine` live in the binding record. Its step R10 makes the split as an in-place `session-record.v1` edit |
| the engines and hosts plans (PR #30, branch `docs/engines-hosts-plans`) | Engines E1 (the `agents/` port-names ratchet in `tools/HostNames.ps1`), K1 (the record key becomes harness plus id), R1 (the binding in the record: `engine`, `projectCwd`, `resume.argv`, `resume.envRefs`), E10 (the launch stub); hosts step 5 (a cross-host import in `tools/HostNames.ps1`). Engines' A1 to A3, a transcript port and adapters under other names, are not built there: this plan owns them (below) |
| hosts research | Its "Decisions taken": Windows agents only for now; capability flags per host in `hosts/<name>/capabilities.json` with `state` yes, no, declined or unverified (unverified treated as no); mandatory `-Capabilities` on the host port; pid and cwd tagged with a namespace (`space`) |

`<HordeHome>` below is `%USERPROFILE%\.horde` unless `HORDE_HOME` is set (engine-settings decision 2),
read through the one `Get-HordeHome` that Phase 3 plan step 1 adds when it renames `HORDE_ROOT`.

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

## Dependencies outside this plan

| this plan's steps | need first | why |
|---|---|---|
| 4, 5 | step 4 nothing; step 5 **engines E1** first. Both must land **before Phase 3's commands**: before `horde census`, the first command (Phase 3 plan steps 6 to 8, migration step 3.3), merges | they are the guards every later command is checked against: read commands reach no spawn or kill verb, and core names no engine. Landing them after the commands would mean retro-fitting the commands to pass |
| 17 (tiers), 25 (resume) | **engine-settings Half A**: `schema/engine-config.v1`, the layered resolver, `Test-HordeEngineConfig`, `horde config explain/set/validate` | the tier and the binding's `engine` field are resolved and checked by that machinery; this plan adds keys to it and builds none of it |
| 27 (spawn through the anchor) | **engines E10**, the launch stub `horde launch --job <id>` | the anchor runs the stub to resolve the binding, references and scrub. Step 22 does not wait: it builds and tests the anchor against a stand-in child (below) |
| 22, 33 (host flags) | **Phase 3 plan step 2**: `hosts/<name>/capabilities.json` and `schema/host-capabilities.v1.json`, and step 3's WezTerm declaration | the flags of 2.5 are added to that one file and schema, not to a second format |
| 14, 33 | **Phase 3 plan step 1**, `Get-HordeHome` | every store path here is under `<HordeHome>` |
| 24 | **remote R10, then engines K1, then engines R1**, merged in that order; step 24 must itself merge **before migration step 3.8** | the four in-place `session-record.v1` edits land as one ordered sequence before any record writer exists (below) |
| 3 (W5's adoption line) | **Phase 3 plan step 5** (migration step 3.2), `adoption/capabilities.txt` | the line W5 adds goes in that file |
| 15, 16, 20 | **metrics Stage A**: the event writer, the consent sentinel, the span model | detectors, the backlog and the tuner write metrics events |

## What this plan owns, and the order of shared edits

- **The transcript port and the follower are this plan's**, under this plan's names:
  `core/Transcript.ps1` (the port), `agents/<name>/Transcript.ps1` (the adapters), `core/Observe.ps1`
  (the classifier) and `horde follow` (steps 7 to 11). The engines plan no longer builds them; its A1 to
  A3 (`core/TranscriptPort.ps1`, `agents/<name>/Observe.ps1`) are superseded by these steps, and its
  consumers (engines R2's transcript length, for one) call `Find-Transcript` and the cursor of 4.1.
- **The anchor is this plan's** (step 22, with `core/Contain.ps1` and `platform/windows/` in step 21).
  It is built and tested against a **stand-in child**: a small test program that plays the launch
  stub's part, writing a fixed argv and environment to the anchor's pipe and exiting, so the anchor's
  job, pipe, graceful end and exit paths are proven without the real stub. Engines E10 builds the real
  launch stub afterwards, against the pipe contract step 22 defines and tests. The hosts plan's group F
  proves each host runs the anchor.
- **The primitive that hands a message to a live session is this plan's** (step 13):
  `Send-SessionMessage` in the engine port, implemented per engine as
  `agents/<name>/Message.ps1`, beside that engine's `Transcript.ps1`. It addresses a session by its
  binding (harness and session id) and its agent-owned `messagingAddress`, never by a host handle, and
  returns a receipt as a `core/tristate` answer: `known: delivered` when the follower sees the message's
  marker arrive as a user turn in the recipient's transcript, `known: refused` with the engine's
  reason, and `unknown` with its reason otherwise (no receipt yet, `message-inject` or
  `delivery-receipt` not `yes`, the address unreadable). Nothing else in any plan owns it. The remote
  plan's R21 (message delivery over the link) and the future delivery half of Phase 3's `tell` (after
  target naming, Phase 3 plan steps 15 to 18) both reuse it rather than building their own.
- **`tools/HostNames.ps1` is edited three times, one after another**, each rebased on the one before:
  engines E1 (generalise the ratchet to `agents/*`), then this plan's step 5 (the lifecycle's names
  under that ratchet), then hosts step 5 (the one allowlisted cross-host import). Never two at once.
- **`session-record.v1` is edited in place four times**, as one ordered sequence that ends before
  migration step 3.8 ships the first record writer (engine-settings decision 5):
  1. remote R10 (branch `docs/remote-plan`): the split into a fleet record (hub-written) and a binding
     record (node-written, owner `node`), settled remote decision 3;
  2. engines K1: the key becomes (harness, id);
  3. engines R1 (branch `docs/engines-hosts-plans`): `engine`, `projectCwd` and `resume.argv` /
     `resume.envRefs` in the binding record;
  4. this plan's step 24: the binding's currency, containment, chain and close fields (3.4).

  Each merges only after the one before it, and none after step 3.8; a change after 3.8 is a
  `session-record.v2`.

## Measurements this plan rests on

From the lifecycle design's ledger (read-only, this machine, 2026-09-30 15:05 to 15:23 UTC), four
taken for this plan (J-1 to J-4), one read from a committed file (O-1), and one derived row (P-1).
Numbers that no row backs are labelled **estimate** where they are used: each is a starting value the
metrics tune, not a measurement.

| id | what | value |
|---|---|---|
| M-01 | memory at 15:05:15 | 1,176 MB available; committed 34,257 of 37,120 MB (92%) |
| M-02 | memory at 15:12:56 and 15:22:25 | available 2,018 then 2,431 MB; committed 31,411 then 30,431 MB; 6,793 pages/s at 15:22 |
| M-03 | conhost.exe at 15:05 | 17 processes, 128 MB working set and 26 MB private in total: about 7.5 MB and 1.5 MB each |
| M-04..M-06 | claude.exe footprint | busy 608 to 1,004 MB private; idle 642 to 862 MB private, 158 to 316 MB working set; fresh goblin (0.3 to 0.5 h) 608 to 659 MB private, 300 to 370 MB working set |
| M-07 | orphan claude.exe | 555 MB private, 21.9 h, parent dead, no pane, no control file |
| M-08 | node.exe ancestry | 9 of 9 descend from a dead root; 2,832 MB private; the largest a `next dev` at 1,965 MB; roots dead 14.9 to 36.8 h |
| M-10 | pane host shell | 58 to 66 MB private, 5 to 38 MB working set |
| M-11 | test processes | 62 to 80 MB private and 77 to 106 MB working set each; one suite 417 MB; the mutation runner fans out to 4 to 6 at once (about 350 to 640 MB working set) |
| M-12 | terminal GUI process per pane | 1,274 MB private at 15 panes, 1,260 MB at 12: about 5 MB per pane, within noise |
| M-21 | closing 4 goblins | commit fell 2,846 MB; available rose 842 MB |
| M-22 | work after a report | a goblin ran a tool 43 s after `done`; its background task wrote until killed |
| M-26 | leftover panes | one goblin pane idle 18.4 h with close off; one bare shell 38.4 h old |
| M-30 | Claude Code reaper | acts only at pressure `critical`; skips a session with terminal input in the last 30 min, a running turn, or running delegated agents; on Windows memory is reported scarce unconditionally; the Windows threshold behind `critical` was NOT found |
| M-31..M-34 | reaps and waits | reaps 31.1 and 32.2 min after the only prompt; each reap notice woke its session in 1 to 3 s; 123 reap notices since 2026-09-09; "stalls" were waits on live background jobs |
| M-42 | a report call that hung | `wezreport start` called 14:36:30; its `started` event on disk 14:36:34; no return within 122 s; a second call under `timeout 60` returned DONE=124 |
| M-50 | transcript write latency | at most 0.53 s |
| M-51 | transcript growth | 44 to 68 KB/min per busy goblin |
| M-52 | instrument cost | CIM process table 315 ms; `Get-Process` 34 ms |
| J-1 | who is already in a job, about 15:40 UTC | `IsProcessInJob` true for 25 of 25 processes probed: the terminal GUI process, 3 pane shells, 11 claude.exe, 10 node.exe and the probing shell. Windows 10.0.26200 |
| J-2 | the probing shell's immediate job | `LimitFlags` 0x800: `JOB_OBJECT_LIMIT_BREAKAWAY_OK` only, no kill-on-close; 70 active processes, 658,145 created over its life. An ambient desktop-wide job, not a per-session one |
| J-3 | post-spawn assignment and kill-on-close, probe in the scratchpad (`jobtest.ps1`), acting only on processes it created | A new job with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`; `AssignProcessToJobObject` on two running cmd.exe that were already in the ambient job: **ok, ok** (the jobs nested). A ping that cmd A started 1.5 s **before** its assignment: **not in the job**, and **still alive** after the job's last handle closed. A ping that cmd B started about 2 s **after** its assignment: **in the job**, and **dead** after the close. Both cmd.exe dead after the close |
| J-4 | libuv, the runtime under node, `src/win/process.c` on its v1.x branch | Non-detached children go into libuv's own job (non-inheritable handle, kill-on-close, `BREAKAWAY_OK` and `SILENT_BREAKAWAY_OK`). Detached children get `DETACHED_PROCESS` and deliberately **not** `CREATE_BREAKAWAY_FROM_JOB`, "because CREATE_BREAKAWAY_FROM_JOB makes the CreateProcess call fail if we're under job control that doesn't allow breakaway" |
| O-1 | compaction keeps the session id | `core/ownership.json`, field `formerNames`, provisional text: 12 compactions inside 7 live processes, and 51 in 265 transcripts, with no second id (measured 2026-09-30) |
| P-1 | the goblin cost prior, **derived** from rows above | commit: claude.exe fresh 608 to 659 (M-06) + pane shell 58 to 66 (M-10) + conhost 1.5 (M-03) + terminal per pane about 5 (M-12) = **about 673 to 732 MB, used as 730**. Working set: 300 to 370 (M-06) + 5 to 38 (M-10) + 7.5 (M-03) + noise (M-12) = **about 313 to 416 MB, used as 420**. So a goblin's RAM is 300 to 370 MB for the claude process alone and about 320 to 420 MB with its shell and console; the design's "320 to 420" is the second. The anchor replaces the shell, so the prior should fall; step 22 measures it, and the learned cost replaces the prior after 20 spans |

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
`reservationHoldSec` after an admission. `cost(k)` starts at the prior (P-1 for a goblin) and becomes
the learned p90 after 20 spans. The gate enters `constrained` when any reserve is breached and returns
to `open` only after both reserves are exceeded by `hysteresisMb` for `stableSec`. A read that fails is
unknown, and unknown queues, never admits. Only the numbers change by tier.

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
  about two goblin starts of working set (420 MB each, P-1), so even if two admissions' reservations
  were both wrong by their whole RAM cost, the machine would still sit above where the reaper was
  seen. **Risk accepted:** one unwrapped heavy job (a mutation run is about 350 to 640 MB of working
  set, M-11) started by a goblin on top of a fresh admission can take the machine into the reaper's
  observed range. **On overshoot:** the gate goes `constrained` and admits nothing; the closer acts on
  everything `closable`; proven-owned orphans are reclaimed; orcs are asked about idle sessions. If the
  reaper still fires, it kills a background shell of a goblin whose terminal input is older than 30
  minutes (M-30), the follower surfaces the reap within one poll (M-32), and the owning orc is woken.
  Horde itself ends no work. Because the reaper's Windows threshold is unproven (M-30), this number is
  a starting point for the tuner, not a derivation.
- **`commitReserveMb` 3,072.** Commit is what makes allocations fail; RAM only makes them slow
  (design finding 3). So this reserve moves least: 3,072 MB is 8.3 percent of the 37,120 MB limit and
  holds four fresh goblins' commit (4 x 730 = 2,920, P-1) before the limit. It still refuses at
  today's worst reading: at 15:05 headroom was 2,863 MB (M-01), below 3,072 before any cost is
  subtracted. **Risk accepted:** whether the pagefile is system-managed is unmeasured (design,
  "Unproven"). If it is, commit near the limit grows the pagefile under paging load; if it is fixed, an
  allocation can fail inside a running process. **On overshoot:** the same ladder; commit is only
  returned by ending processes, so the reclaim rungs (closable goblins, proven orphans: 2,846 MB from
  four goblins, M-21; 2,832 MB of orphans, M-08) are what move it.
- **`pagingLimit` 3,000 pages/s.** The only measured paging figure is 6,793 pages/s, taken while
  sessions sat unresponsive (M-02; the hung report call of M-42 was in the same window). 3,000 is under
  half of it. Conservative's 2,000 has no measured baseline behind it, and ordinary compile and test
  bursts may pass 2,000 briefly; the 30 s average already smooths spikes. **Risk accepted:** if thrash
  begins between 3,000 and 6,793 on this machine, admitted work slows everything down. **On
  overshoot:** queue, and the `-Pausable` rung of the ladder (suspend declared-pausable jobs, which
  frees working set, never commit).
- **`hysteresisMb` 768.** Not a boldness knob but a correctness floor. The design's reason for
  hysteresis is that closing one goblin frees about 700 MB of commit and would otherwise re-admit at
  once. The margin must therefore exceed one goblin's commit (730 MB, P-1), so one close can never
  re-open the gate on its own. 768 is the smallest round value above 730; closing one goblin also frees
  only about 210 MB of available memory (842 / 4, M-21), so the RAM side needs several closes. The
  checker refuses any tier whose `hysteresisMb` is below the current goblin commit cost (prior or
  learned), whichever tier it is.
- **`stableSec`, `reservationHoldSec`, `pagingWindowSec`** are unchanged: a goblin reaches its steady
  footprint in 1 to 3 minutes (design B2.2), and nothing measured argues for other values.
- **Backstop count 46**: `floor((37,120 - 3,072) / 730)`. A runaway guard only; it should never bind.

Replayed against today: at 15:05 standard refuses (commit headroom 2,863 < 3,072). At 15:12:56
(available 2,018) standard refuses on RAM: 2,018 - 420 < 2,048. At 15:22:25 (available 2,431, 6,793
pages/s) it refuses on RAM (2,431 - 420 = 2,011) and on paging. Conservative refuses at all three.
These are the fixtures of step 18.

### Aggressive, clearly labelled

`aggressive` is for a founder who is watching the machine and prefers throughput to headroom; the
founder asked for tiers, and this is the bold end of them. `ramReserveMb` 1,536 is 360 MB above the
lowest observed reap point, less than one goblin's working set: **expect reaps**. `commitReserveMb`
2,048 is 5.5 percent of the limit. `pagingLimit` 4,000. Hysteresis stays 768 for the correctness reason
above. It still never kills: the ladder is the same and every reap is surfaced. It can be selected only
in the founder's user file (L1) or as a live rule (L4) with an `until`, and `horde watch` prints the
tier in its header whenever it is not `standard`.

## 1.3 Through the engine-settings layers

The tier is one more key in the layered configuration, the way metrics adds `metrics.*` (metrics
design 7.1): one resolver, one `explain`, no second configuration system. This needs engine-settings
Half A (Dependencies).

- **Keys.** `admission.tier` names a tier. `admission.tiers[]` defines tiers: `{ name, rank, label,
  ramReserveMb, commitReserveMb, pagingLimit, pagingWindowSec, hysteresisMb, stableSec,
  reservationHoldSec }`. `rank` orders tiers from cautious (0) upward; the three built-ins are 0, 1, 2.
- **Where each may be set.**
  - L0 ships `core/admission-tiers.json` with the three tiers and `admission.tier = standard`.
  - L1, the founder's file, may select any tier and define custom tiers.
  - **L2, a project's file, may lower the tier and never raise it** (engine-settings decision 3, the
    same rule metrics has): it may select a tier whose `rank` is at most the rank resolved from the
    layers below it, and may not define tiers. A repository that needs a quieter machine, for example
    a heavy build, can ask for `conservative`; a cloned repository can never make the machine bolder.
    The project file itself waits until a repository needs one (decision 3).
  - L3 (a run spec) and L5 (a spawn flag) may not set it: memory is a per-machine fact (design C3.4),
    and one run or one spawn choosing the reserve for the whole machine would let the boldest caller
    win.
  - L4 (live, `horde config set admission.tier conservative --scope live --until <t>`) lets the
    warchief change it mid-work, and is where the tuner writes (1.4).
- **Selectors.** A rule that sets `admission.*` must have an empty `match`; the gate resolves one tier
  per machine. Each machine resolves its own L1, so a remote machine can differ.
- **Checker findings**, all errors: a tier without every numeric key; a number below its floor
  (`hysteresisMb` below the goblin commit cost; any reserve below 0); two tiers with one name or one
  rank; an L2 rule selecting a higher rank than the layers below it resolve, or defining a tier; an L3
  or L5 rule that sets `admission.*`; an L4 rule selecting a higher rank than L1's resolved tier
  without an `until`.
- **`horde config explain --key admission.tier`** shows the tier, its layer and rule, every number,
  and, per number, whether the tuner has raised it (1.4).
- **Schema.** `schema/engine-config.v1` has `additionalProperties: false`; its `rule.set` gains an
  `admission` object. The engine-config schema has not shipped, so this lands in v1 before its first
  release.

## 1.4 How the metrics system tunes the numbers

The gate's inputs come from the follower's operational stream (`obs.*`), which is content-free and
not gated by `metrics.level` (design B2.3); the tuner is the metrics module's (metrics design
section 12, Stage E).

- **Signals, per machine per day**: `obs.reap` events that happened while the gate was `open`, with
  the counters and tier at that moment; the minimum available memory and maximum paging seen while
  `open`; queue wait time and refusals per kind (the cost of caution); per-kind learned costs
  (p90 over the last 20 spans, floored at the priors).
- **Raising is automatic** (engine-settings decision 9). A reap while `open` means the reserve was too
  small. The tuner writes an L4 rule raising `ramReserveMb`, with `until` seven days out and a `note`
  naming the reap events, capped at conservative's value plus 1,024 MB. The step is 256 MB per such
  reap, an **estimate**: about half of one goblin's RAM prior (P-1), small enough that a single reap
  does not flip standard to conservative. The tuner records the step's effect (reaps while open in
  the following week) so the step itself can be revised. `explain` shows each raise as the tuner's.
- **Lowering is only ever proposed** (decision 9). After a quiet period with no reap while `open`,
  `horde metrics tune --propose` prints a lower value with its evidence (minimum available seen, reaps,
  refusals); the founder applies it at L1 with `horde config set`. The quiet period starts at 14 days,
  an **estimate**: two working weeks, so that a proposal has seen at least two wave cycles. Nothing
  lowers a reserve on its own.
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
| O1 node dev servers and test runners outliving their goblin | 9 processes, 2,832 MB, 14 to 37 h (M-08) | the goblin's job, kill-on-close, held only by its anchor (2.2) | pre-Horde ones: reported by `horde orphans` (step 14) |
| O2 a harness process with no pane and no control file | pid 5616, 555 MB, 21.9 h (M-07) | the harness is the anchor's child in the same job; when the pane dies the anchor dies and the job ends | reported by `horde orphans` |
| O3 a bare shell left in a pane | pane 26, 38.4 h (M-26) | the anchor is the pane's only program, no `-NoExit` shell (design decision 4) | **deferred**: detecting it needs host reads Phase 3 keeps on wezfleet (2.6); reported by wezfleet until step 33 |
| O4 a goblin's background job still running at close | M-22 | the closer refuses while a live job member is not a declared service; after the close the job ends it | - |
| O5 a process a goblin starts outside its job (WMI create, a scheduled task, an out-of-process COM server, a shell hand-off) | not seen today; documented escape | cannot be prevented by a job (2.4) | found by ancestry and job membership; reclaimed only with proof, else reported |
| O6 goblins spawned before Horde's spawn path, and the founder's own sessions | all of today's fleet | - | reported; `wezfleet orphans` (W5) lists them now |

## 2.2 The anchor: how a job exists when the terminal, not Horde, is the parent

Horde asks the host to run an argv. The host creates the process, so its parent is the terminal
(measured: the pane shells' parent is the terminal GUI process, J-1), and Horde never holds a handle
from `CreateProcess` that it could assign before the child runs. The fix is to make the first program
in the pane assign **itself**:

1. The argv the host runs is the **anchor**, a small compiled executable (engine-settings decision 10,
   following `wf-cmdlog.exe`; it absorbs the design's CTRL_C helper). It is the pane's only program.
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
CTRL_C twice to its console group, waits up to 12 s (design A3.1), then calls `TerminateJobObject`.
That replaces the design's separate console-attach helper: the anchor already shares the console.

**Who else holds the job handle.** The follower opens the job by name only to query it
(`JobObjectBasicProcessIdList`, `JobObjectExtendedLimitInformation` for `PeakJobMemoryUsed`) and
closes it in the same call. While it holds a handle, a close is deferred by at most that call's
duration, and then happens anyway, because kill-on-close fires on the last close. A test pins the
query's handle lifetime.

**Resident cost.** Compiled because a PowerShell anchor would stay resident for the goblin's life at
about what a pane shell costs today, 58 to 66 MB private (M-10). A native helper waiting on one
process should be a few MB: a target, measured in step 22, not a claim.

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
| E2 `CREATE_BREAKAWAY_FROM_JOB` | impossible: the goblin's job never sets a breakaway limit, so the create fails instead of escaping. That failure is honest and visible as a tool error. Whether the harness itself ever asks for breakaway is **unmeasured**; step 22 runs a real harness session inside such a job in the isolated instance and must pass |
| E3 WMI `Win32_Process.Create`, scheduled tasks, services, out-of-process COM, shell hand-off | cannot be prevented by a job. Found by the backstop; reclaimed only with proof (2.6), otherwise reported |
| E4 a goblin spawning another goblin through the host | not an escape: the new pane gets its own anchor and job, and its own record naming its parent |
| E5 the anchor killed or crashed | the handle closes and the job ends everything in it: the intended result |
| E6 a declared service that must outlive the goblin | never started inside the goblin's job, because a process cannot leave it. `horde job run -Service -Until <t>` asks Horde's actor to start it in a service job with no kill-on-close, recorded with its owner and expiry; the actor ends it at expiry. If the actor is down, the record still proves ownership for later reclaim |
| E7 assignment refused (a UI-limited ambient job, a changed Windows) | the anchor refuses to start the harness and reports `containment unknown: assign failed, <error>`. `horde install` runs the J-3 probe once per machine and records `contain.nest` |

## 2.5 Host capability flags

Each host already declares itself in one file, `hosts/<name>/capabilities.json`, validated by
`schema/host-capabilities.v1.json` (Phase 3 plan step 2): its name, its capability table in the
HostPort vocabulary, and its session markers. The flags below are added to that same capability table
and to that schema's vocabulary; there is no second declaration format. They take the same states,
`yes`, `no`, `declined` or `unverified`, and core relies on one only when it is `yes`. Phase 3's
WezTerm read adapter (Phase 3 plan step 3) declares `spawn` and `kill` `declined`; step 22 of this plan,
in Phase 5, is where the WezTerm declaration first moves any acting verb to `yes`, each measured in the
isolated instance and each checked by `test/lib/HostReadConformance.ps1`'s rule that a capability not
`yes` is never called. Until then every flag below is `unverified`.

| flag | meaning | why the anchor needs it |
|---|---|---|
| `spawn.program` | the host runs the given argv as the pane's only program, with no shell around it | O3: no bare shell after exit |
| `spawn.exitCloses` | the pane closes when that program exits (and whether only on a clean exit) | the close path never needs a pane-id kill (design A3.1 step 4) |
| `spawn.parent` | `host` or `caller`: whose child the pane's program is | `host` means only self-assignment can contain it; `caller` would allow assign-before-resume |
| `spawn.env` | the host can pass environment | the spawn token reaches the anchor; with `no`, the token goes in the argv |
| `pid` with `space` (the rows' existing namespace tag) | the anchor's pid and its namespace | containment is resolved in that space: a `windows` pid uses a job; a `wsl:` or `posix` pid uses the POSIX mechanism below |
| `contain.inherited` | the host's own pane processes already sit in a job or control group, and whether it allows breakaway | nesting is required; recorded so a change in the host is noticed (J-1, J-2) |
| `pane.bareShell` | the host adapter can say whether a pane it spawned now holds only its own shell, from the pane's program pid and the shell images it knows | O3 detection without title reads (step 33); declared in the same `capabilities.json`, `unverified` until then |

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

Anything else is `orphaned, owner unknown` in `horde orphans`, `horde status` and `horde watch`, with
memory, age, image name and cwd, for the founder to decide. Reclaim acts only on proof 1 to 3, never on
a declared live service, through the handle method (open by pid, compare the creation time read from
the handle, terminate through that handle), and writes `obs.orphan` with the proof used. The report is
read-only and ships in the read half; the reclaim ships with the closer in Phase 5.

**Where process knowledge lives.** Core matches no image name. The classes are defined by structure:
O1 is "a process tree whose root is dead", whatever its image; the image name is carried as display
data only, never matched on. O2 needs to know which processes are harness processes and where their
control files are: that is each adapter's, `agents/<name>/agent.json` gaining `processImages` and the
control-file location, asked through the AgentPort (`Get-AgentProcessClaims`: which pids are this
harness's, and which of those have a live control file). O3 needs to know which images are a pane's
shell: that is each host's, in `hosts/<name>/`, answered by the `pane.bareShell` capability.

**O3 is deferred.** wezfleet detects bare shells by reading host tab titles, and the Phase 3 plan keeps
that feature on wezfleet until a host adapter provides it (its decision 5, the `census-bare-shell`
capability, and its G-01 allowance). Horde does not re-introduce title reads for it; the host adapter
that eventually provides it answers `pane.bareShell` instead. Until step 33, bare shells are reported by wezfleet census; after
the anchor ships (step 27) new goblins cannot leave one.

---

# Part 3 - Automatic close after proof, and the resume binding

## 3.1 The binding is the single source of truth

The founder's precondition for automatic close: the goblin's resume information lives in Horde's
session record, is current, and an orc can read and use it in one step. Under settled remote decision 3
the record has two parts: the **fleet record**, written by the hub, and the **binding record**, written
by the node the session runs on, owner `node` in `core/ownership.json`'s vocabulary (remote R10 adds
that owner). The resume binding and `engine` are in the binding record. The binding is:

| binding part | record field | record, owner | notes |
|---|---|---|---|
| harness | `engine.harness` | binding, `node` (engines R1) | fixed at spawn; resume can never change it (engine-settings 7). With engines K1 it is also half of the record's key |
| provider profile | `engine.provider`, `engine.profile` | binding, `node` (engines R1) | a profile name, never an endpoint copy or a key |
| model | `engine.model` (concrete id), `engine.requested` | binding, `node` (engines R1) | pinned at spawn (engine-settings decision 4); `modelObserved` (owner `agent`, derived) is shown beside it, never merged |
| session id | `sessionId` | the key (engines K1), owner `agent` | set in advance where the harness allows it (`--session-id` for claude-code, local help); learned from the harness's files otherwise |
| cwd | `projectCwd` | binding, `node` (engines R1) | the launch directory, which names the transcript folder |
| argv | `resume.argv` | binding, `node` (engines R1) | the argv the AgentPort built |
| environment block | `resume.envRefs` | binding, `node` (engines R1) | non-secret values literally; secrets only as references (engine-settings 6); the checker refuses a secret-shaped value |
| currency | `binding.revision`, `binding.verifiedAt`, `binding.previous[]` | binding, `node` (**step 24**) | revision increments on every rebind |
| containment | `containment`: `{ mechanism, name, anchorPid, anchorProcStart, space }` | binding, `node` (**step 24**) | written on the node, where the anchor runs; Part 2 |
| chain | `predecessor`, `successor` | binding, `node` (**step 24**) | 3.2 |
| close | `closure`: `{ state, at, tombstone }` | binding, `node` (**step 24**) | the closer runs on the node, against its own processes (design C3.4) |
| orc decisions | `closeOn` (`proof`, `routed`), `park`: `{ reason, until }` | fleet (**step 24**), where remote R10 puts hub-written fields | set by an orc on any machine through `horde route` and `horde park`; if R10 places them otherwise, R10 is the authority and this row follows it |

`resumeCommand` stays an `agent`-owned, **derived** field, but its derivation changes: the AgentPort
renders it from the binding above. wezfleet's `resume.txt`, the status snapshot's `resumeCommand`
(W5) and the layout saves' argv (R1) stay shadow-only reads, never answers. Nothing else stores a
resume path, which is what makes the binding the single source.

## 3.2 Kept current

- **Compaction keeps the session id** (O-1). So compaction needs no rebind.
- **`/model` drift does not rebind** (engine-settings decision 6). It is shown in status as
  `modelObserved` beside the launched `engine.model`, and resume uses the launched binding.
- **What does need a rebind**: an orc re-resuming a goblin (`horde resume` writes the new revision
  itself), a harness that forks a new id on resume, and anything that starts a new conversation in the
  same process (whether `/clear` does is unmeasured). The follower watches the agent's control file for
  the goblin's pid+procStart; when the session id it carries changes, it emits `obs.rebind` with both
  ids. The follower never writes records; the binding record's writer on the node subscribes and
  writes the new revision.
- **The record is keyed by (harness, session id)** (engines K1). A rebind that changes the id writes a new record and
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

- `core/ownership.json`: engines R1 adds `engine`, `resume` and `modelObserved` (owner `agent`,
  derived); this plan's step 24 adds `binding`, `containment`, `predecessor`, `successor` and `closure`
  (binding record, owner `node`) and `closeOn` and `park` (fleet record, as remote R10 places
  hub-written fields), and changes `resumeCommand`'s `derived` text as in 3.1. New stores, so
  provenance can name them: `H1` the Horde session record, fleet and binding parts (under
  `<HordeHome>\store\sessions\`, laid out by remote R10), `H2` the observation stream
  (`<HordeHome>\store\observe\<date>\<machineId>.jsonl`), `H3` closure tombstones, `H4` spawn claims
  (`runs\<id>\spawns\<fleetId>.claim`), `H5` orc mailboxes
  (`<HordeHome>\store\mailbox\<sessionId>\`), `X7` the Codex rollout, `X8` the harness's background
  task output files, `X9` the loop-guard state file.
- `schema/session-record.v1` is **edited in place** (engine-settings decision 5), and step 24 is the
  fourth and last of four in-place edits: remote R10 (the split), engines K1 (the key), engines R1 (the
  binding's engine and resume fields), then step 24. All four merge in that order before migration
  step 3.8 ships the first record writer; any change after that is a `session-record.v2`.
  `additionalProperties` is false and `test/test-schema-session-record.ps1` computes the property
  list from the ownership table, so each step's rows and schema properties land in one PR.
- `schema/observe-event.v1`: the metrics envelope (metrics design 4.2) with the `obs.*` kinds.
- `schema/host-capabilities.v1.json` (created by Phase 3 plan step 2): the flags of 2.5 join its vocabulary, and `hosts/wezterm/capabilities.json` declares them.

---

# Part 4 - The transcript port and the one follower

## 4.1 One abstraction in core, adapters per engine

This plan owns the port, its adapters, the classifier and the follower ("What this plan owns",
above). `core/Transcript.ps1` defines the port and names no engine. Each adapter lives in
`agents/<name>/Transcript.ps1` and is registered by its `agent.json`. Order: `claude-code` and `codex`
first, then `gemini-cli`. GLM, Qwen and DeepSeek are not adapters: they are provider profiles driven
through the claude-code harness (agent-engines decision 2), so they are read by the claude-code
adapter, and their differences are capability flags on the (harness, provider) pair.

**Operations** (each returns `core/tristate` answers; an unreadable source is unknown with its reason):

| operation | input | output |
|---|---|---|
| `Get-TranscriptCapability` | harness, provider profile | the flags of 4.3, each `{ state: yes, no, declined, unverified; evidence }` |
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
| `transcript.tail` (append-only, line-delimited, tailable by offset) | yes: M-50, M-51 | yes: rollout JSONL (metrics 2.5) | unverified: docs only | as claude-code |
| `turn.end` marker | yes: `system/turn_duration`, `stop_hook_summary` (design C1) | unverified | unverified | as claude-code |
| `tool.pairing` | yes: tool_use / tool_result ids | unverified | unverified | as claude-code |
| `task.background` start and completion | yes: task notifications | unverified | unverified | as claude-code |
| `reap.notice` | yes: `<status>killed</status>` user line (M-33) | no reaper known | unverified | as claude-code |
| `tokens.perTurn` | yes | no: cumulative only | unverified | **estimated** where the endpoint lacks token counting (agent-engines section 3) |
| `tokens.cumulative` | no | yes: `total_token_usage` (metrics 2.5) | unverified | no |
| `cache.fields` | yes | unverified | unverified | **no** for DeepSeek, which ignores `cache_control` (agent-engines section 3) |
| `model.perMessage` | yes | yes: session start `model` | unverified | yes, the provider's id |
| `compact.marker`, `sessionId.stableAcrossCompact` | yes, yes (O-1) | unverified | unverified | as claude-code |
| `status.file` | yes: control file (X2) | no native file (measured); Horde's hook-written file stands in | unverified | as claude-code |
| `loopGuard` | yes where the founder's hook is installed | no | no | as claude-code |

`unverified` never satisfies a requirement: the classifier answers `unknown: <flag> unverified for
The capability vocabulary is shared with the host capability files: `yes`, `no`, `declined`, `unverified`, and `unverified` counts as `no` (engines plan, one vocabulary everywhere).
<harness>` rather than guessing.

**How a flag becomes `yes`.** Only through a test. Each adapter keeps
`agents/<name>/measurements/<flag>.json` for every flag it declares `yes` or `no`: the instrument, the
date, the harness version, the fixture it ran against (a cut-down copy under
`agents/<name>/test/fixtures/`), and the result. `agents/<name>/test/test-capabilities.ps1` then, for
every flag in the capability file: fails if a `yes` or `no` has no measurement file or its result
disagrees; re-runs the adapter over the recorded fixture and asserts the behaviour the flag claims
(assertion text of the form "capability tokens.perTurn holds on its recorded fixture"); and fails if
the harness version in use is newer than the newest measured one, until that version is surveyed (the
`surveyedVersions` rule `core/ownership.json` already applies). The agent's ledger,
`planning/ledger/agent-<name>.md`, records each measurement as an entry with disposition `test`
and `where:` that suite and its assertion, which the ledger gate checks is a quoted string on a code
line. A flag with no measurement stays `unverified`, with no file.

## 4.4 The follower: one per machine, one reader

`horde follow` is one long-lived process per machine, installed by `horde install` as a per-user
scheduled task at logon (design C3.1). It is the **only** reader of transcripts:

- It tails every tracked session through the port (2 s poll, a file-system watcher to shorten it, the
  poll kept as the correctness path), samples processes (5 s CPU, 30 s CIM tree with parents, job
  queries for anchored goblins), and writes one stream, H2, one file per writer with a daily cap.
- **Two consumers, one input.** The watcher classifier (`core/Observe.ps1`: working, waiting on a job,
  waiting on a human, stalled, looping, dead, plus reported, closable, parked; design C2's evidence
  and thresholds; plus the detectors of 4.5) and the metrics collector both read H2. The metrics
  harvester reads transcripts directly only for spans the follower never saw and that have consent;
  there is no backfill from before consent (metrics decision 8). Token counts reach metrics only
  through `Get-UsageFacts`, from local files (metrics decision 7); cost is computed later from the
  versioned price table (`core/Price.ps1`).
- **It never acts.** The observer's files hold no spawn, kill or send verb, checked by the `effects`
  tripwire (step 4). The actors (closer, gate pump, reclaimer, service keeper, alerter) are separate
  modules that subscribe to H2; they may share the process from Phase 5, but not the files.
- Footprint target under 100 MB private, measured in step 11 (design decision 10: PowerShell first,
  compiled only if the measurement exceeds the target).

## 4.5 Detectors, the improvement backlog, and context purity

The founder asked to see where goblins stall, loop, miss communications and waste tokens, so they can
be improved, and to keep orc and warchief context for big-picture thinking (metrics design, "Founder
direction"). Each detector is a pure function over H2, emitting `obs.detect { pattern, spanId,
evidence[], tokens, seconds }`; tokens come from `Get-UsageFacts` only (local, metrics decision 7), and
are `unknown` when the span has no consent.

| detector | evidence | cost recorded |
|---|---|---|
| `stalled` | design C2 | seconds from the last activity to the wake or the report |
| `looping` | design C2 (repeated tool signature, repeated error hash, oscillating file hash) | tokens and seconds from the first repeat to the loop's end |
| `missed-communication` | a wake with no delivery receipt (Part 5); a goblin's `blocked` or question with no orc reply before the goblin moved on or stalled; a handoff the orc never opened (no read of the handoff path in the orc's transcript within its next N turns, N an **estimate** starting at 20); a message the orc sent that never arrived in the goblin's transcript | seconds the recipient waited; tokens the sender spent after the miss |
| `wasted-tokens` | tokens spent inside a `looping` span; tokens after a reap until the goblin reported or stalled; the same file read three or more times in one span with no edit between (by path hash); tokens of a span whose work was abandoned, reverted or duplicated by a second spawn of the same fleet id | the tokens themselves, by kind |

**The improvement backlog.** The metrics compactor folds `obs.detect` into
`<HordeHome>\store\metrics\backlog\<pattern>.json`: one item per pattern and cause key (for example
"loop on the same failing test command"), with count, total tokens, total seconds, first and last seen,
up to ten example span ids (ids only, never content), and a status (`open`, `accepted`, `fixed`,
`wontfix`, with a reason). `horde metrics backlog [--pattern p] [--json]` lists it, ranked by tokens
and seconds lost. An item marked `fixed` that recurs reopens itself.

**Context purity.** Per delivered result, the metrics record what it cost the orc's (and the
warchief's) context: the size of the inbound result in tokens (the orc's input-token growth on the turn
that received it); the orc's own follow-up reads caused by it (tool calls on the worker's files in the
orc's next N turns, N as above); and the ratio of those to the worker's own tokens. `horde metrics
report` shows it per orc and per routing choice (goblin versus agent, handoff format), beside cost and
speed, so routing and the handoff format are judged on purity too.

**Distilled, never raw.** Nothing from H2 reaches an orc's context as stream lines. An orc receives
wake messages (Part 5), each a distilled summary of at most three lines and 400 bytes (an
**estimate**, tuned by the context-purity measure) with pointers, and pulls detail on demand through
`horde why --brief` (at most five lines) or `horde goblin show`. `horde watch` is for the founder and
the warchief's terminal, not for an orc's prompt.

---

# Part 5 - Seeing and being told: `horde watch`, `horde why`, wake messages

- **`horde watch [-Orc X] [-Goblin Y] [-Json]`**: a live table from H2, one row per goblin: state,
  the reason in one line, age of the newest evidence, RAM and commit (from the job when anchored),
  the running tool or job, and the gate's state and tier in the header. It tails the stream; it never
  opens a transcript. Orphans of unknown owner get their own section.
- **`horde why <goblin> [--brief] [-Json]`**: the current state and every piece of evidence behind it,
  each with its source store, file, offset and time, in `core/ownership.json`'s vocabulary; `--brief`
  is the distilled form for an orc. It is the same answer `horde goblin show` embeds.

## Wake messages

On a transition to `stalled`, `looping`, `reported`, `dead`, `park-expired`, `closed` or `reaped`,
the alerter wakes the owning orc. Delivery does **not** go through Phase 3's target naming (migration step 3.6, Phase 3 plan steps 15 to 18), whose
first form refuses any session without a verified host handle, and does **not** use wezfleet's `tell`,
which types into a pane. It addresses the orc by session id, taken from the goblin's `parent` in the
engine's record, and uses two channels:

1. **The mailbox, always.** The alerter writes each wake as one file,
   `<HordeHome>\store\mailbox\<orcSessionId>\<utc>-<seq>.json`, created with `CreateNew` and never
   appended (one writer per file, as metrics 4.3 requires). It holds the distilled summary: goblin,
   state, one-line reason, and the next command (`horde why --brief`, `horde goblin show`, `horde
   resume`). Nothing is lost if every other channel fails, and `horde inbox [--unread]` (a read
   command) lists it. The mailbox alone does not wake a session that has ended its turn.
2. **The engine's own message channel, as the doorbell.** When the orc's harness declares
   `message-inject: yes` in `agents/<name>/agent.json` (claude-code: the peer socket named by the
   control file's `messagingSocketPath`, the `messagingAddress` field, owner `agent`), the alerter calls
   the session-message primitive (`Send-SessionMessage`, owned by this plan, step 13) to deliver a
   one-line doorbell carrying the mailbox entry's id. A message arrives as a
   new turn, which is what wakes an orc that ended its turn to wait. The receipt is tristate: the
   follower confirms delivery when that id appears as a user turn in the orc's transcript
   (`delivery-receipt`), and marks the entry delivered; until then it is `unknown`, never "sent" read
   as "delivered".

**Host unknown changes nothing**: neither channel needs a host handle, so an orc whose pane is unknown,
or which has no pane, is still reached. **What does change the path**: the orc's harness has
`message-inject` `no` or `unverified`, its messaging address is unknown, or no receipt arrives within
60 s (an **estimate**; the one measured wake latency is 1 to 3 s, M-32). Then the alerter escalates the
same entry to the warchief by the same two channels, and if the warchief cannot be reached either, to a
Windows notification to the founder through `platform/windows/`. Horde never types into a pane to
deliver a wake.

Each wake is keyed by (goblin, transition, evidence seq), so a restart never repeats one. **Rate
limit**: one per goblin per transition, and at most 10 per orc per minute with the rest folded into
one summary entry. The 10 is a **starting guess** with no measurement behind it; the metrics tune it
from the wakes per orc per minute seen during waves, the orc context tokens spent on wakes (4.5), and
the `missed-communication` detector.

---

# Part 6 - wezfleet stopgaps carried over

W1 (`status` stops pumping) and W2 (the roster written per spawn) are already being built. W3 to W5
are done in `YedPool/wezfleet`, under its own CONTRIBUTING (worktree in `wezfleet-worktrees`, never
test against the working terminal, `--merge`), because Horde's writers are phases away and these are
live defects.

**Timing against the Phase 3 shadow.** A qualifying working day in the Phase 3 census shadow needs
wezfleet's commit constant through the day, or each change logged (the Phase 3 plan's working-day
rule). So each stopgap merges between shadow days, never during one, and its merge is logged in the
shadow log with its commit.

| # | change | tests first | why now |
|---|---|---|---|
| W3 | `Close-WfOwnPane` (lib/Notify.ps1:178): re-verify identity at kill time; skip the kill while any descendant of the claude process is alive; go through Kill.ps1's ladder and its never-empty-a-window guard, not a raw `kill-pane` after a sleep | "closeOnDone spares a goblin with a live child"; "closeOnDone re-verifies the pane at kill time"; "closeOnDone never empties a window" - each mutation-tested, in the isolated instance only | issue #38 and M-22: a destructive path with a known pane-reuse hole that also kills work started after the report |
| W4 | `Test-WfPaneMatchesRoster` answers "cannot prove" for a roster pane of -1, and closeOnDone does not fire on it | "a roster pane of -1 cannot prove identity"; "closeOnDone does not fire without proven identity" | design A5.5: after an interrupted launch the check passed for any pane |
| W5 | **a separate verb, `wezfleet orphans`**, read-only: process trees whose root is dead, a claude with no control file, with memory and age. **census is not changed**, so the census shadow's output and its comparisons are untouched | "orphans lists a tree whose root is dead"; "orphans lists a claude with no control file"; "census output is unchanged by the orphans verb"; a read-only tripwire over the new code | 2.8 GB was invisible to every command (M-08); this is O6's report until Horde's ships |

W5 adds one line to `adoption/capabilities.txt` (created by Phase 3 plan step 5, migration step 3.2), in that file's format:

```
orphans            | wezfleet orphans                | horde orphans       | processes no live session owns, with their memory
```

If W5 merges before Phase 3 plan step 5, the step 5 PR seeds the line; otherwise W5's companion Horde PR adds
it. `horde orphans` (step 14) is its Horde form and is adopted through that ledger like any other
capability.

Not a stopgap: making reaped jobs visible in wezfleet. That belongs to the follower, and doing it twice
is what the one-reader rule forbids.

---

# Steps

Numbered through; the design's H-numbers in brackets for traceability. Phase gates follow the
migration plan: read-only steps sit beside Phase 3; anything that spawns, kills or writes a record
waits for Phase 5, except step 24, which must land before migration step 3.8. Dependencies on other plans are in the table
near the top.

## A. Now, in wezfleet

1. **W3.** Tests first as in Part 6; ledger not required (wezfleet is not being replaced by this step).
2. **W4.**
3. **W5**, as `wezfleet orphans`, merged between census shadow days.

## B. Guards, before Phase 3's commands

These two land before the first Phase 3 command PR merges (`horde census`, Phase 3 plan step 6,
migration step 3.3), because every later command, in this plan and in Phase 3, is checked against
them. They do not wait for Phase 3's groundwork (its steps 1 to 3) and do not block it.

4. **`effects` declarations** [H13]. Every command declares `read`, `write`, `spawn` or `kill`; a suite
   parses each `read` command's call graph from its entry point and fails on any spawn or kill verb,
   with a planted-verb control. Tests first: "a read command reaches no spawn verb"; "a read command
   reaches no kill verb"; "a planted spawn verb turns the check red". Ledger: none replaced; the PR
   cites wezfleet's `status`-pumps defect (issue #33) as the reason.
5. **The lifecycle's names under the `agents/` ratchet**, after engines E1 has generalised
   `tools/HostNames.ps1` to `agents/*`, and before hosts step 5 edits it again. This plan introduces
   engine knowledge core must never hold: each harness's process images (`processImages`, 2.6), its
   transcript and rollout path fragments, and its control-file and task-output locations. They are
   declared in `agents/<name>/names.txt`, so the ratchet catches any of them outside the adapter.
   Tests first: "a planted process image name in core is caught"; "a planted transcript path fragment
   in core is caught"; "core matches no process image name". "Core names no engine" is E1's own
   assertion and is not repeated here.

## C. The read half (beside Phase 3; no writer, no act verb)

6. **`core/ProcessTree.ps1`** [H1]. One CIM snapshot to a tree with pid+procStart; the dead-root walk;
   descendants of a session; the three ownership proofs of 2.6 as pure functions over injected tables.
   Tests first: "a reused pid never extends an ancestry"; "a child older than its parent breaks the
   walk"; "an unreadable table reads as unknown"; "ownership needs one of three proofs"; "core matches
   no process image name". Ledger `planning/ledger/core-processtree.md`: wezfleet `lib/Mail.ps1`
   liveness, census, lesson L-019.
7. **`core/Transcript.ps1` and `schema/observe-event.v1`** [H5]. The port of 4.1, the event of 4.2,
   the stream writer (one file per writer, cap, `truncated` marker, `seq` from the writer's counter).
   Tests first: "a shorter file is truncated, never restarted"; "a partial last line is carried";
   "seq is strictly increasing within a file". Ledger: none replaced.
8. **`agents/claude-code/Transcript.ps1`** [H3], with its `measurements/`, fixtures and
   `test-capabilities.ps1` (4.3), and `processImages` in `agent.json` (2.6). Tail by byte offset;
   control file; task outputs; loop-guard read. Tests first against copies of today's four goblin
   transcripts cut down: "a reap notice becomes a reap event"; "no message text reaches the output"
   (planted marker); "an unmatched tool call stays open"; one "capability ... holds on its recorded
   fixture" per declared flag. Ledger `planning/ledger/agent-claude-code.md` (transcript half):
   wezfleet `lib/Delivery.ps1` receipt reading, the cmdlog hook, the loop-guard hook, and one `test`
   entry per capability measurement.
9. **`agents/codex/Transcript.ps1`** [H4]. Rollout tail; cumulative tokens as `usage.snapshot`, never
   summed; its own measurements and capability suite. Tests first from the one real rollout. Ledger
   `planning/ledger/agent-codex.md`: `lib/CodexStatus.ps1`.
10. **`core/Observe.ps1`, the classifier** [H2], with the `stalled` and `looping` detectors of 4.5.
    The pure function of design C2 over injected observations. Tests first, one fixture per state from
    today's transcripts (M-31 to M-34): "waiting on a live job is never stalled"; "a report with a live
    child is not closable"; "a reap then silence is stalled after two minutes"; "an unverified flag
    answers unknown, never a state".
11. **`horde follow`** [H6]. The loop, the scheduled-task install through `horde install`, the
    job-handle lifetime test; the observer's files pass step 4's tripwire. Gate: one hour in the
    isolated harness, private bytes measured and reported against the 100 MB target.
12. **`horde watch` and `horde why`** [H7]. Read commands over H2, `-Json`, `why --brief`, two
    end-to-end scenarios each (Phase 3 rule). Tests first: "watch never opens a transcript"; "why brief
    is at most five lines".
13. **The session-message primitive and wake messages** [H8].
    - **The primitive, first.** `Send-SessionMessage` in the engine port, and
      `agents/claude-code/Message.ps1` (the peer socket named by the control file) behind it; codex and
      gemini-cli declare `message-inject` `unverified` until a measurement and its test flip it (4.3).
      It takes a binding and a text, addresses by `messagingAddress`, never by a host handle, and
      returns a tristate receipt: `known: delivered` only when the follower sees the text's marker
      arrive as a user turn in the recipient's transcript. Tests first: "a receipt is unknown until the
      marker is seen"; "a refused delivery is known refused with its reason"; "an unverified engine
      answers unknown, never delivered"; "the primitive never types into a pane". This is the primitive
      remote R21 and the future delivery half of `tell` reuse.
    - **Wake messages on top of it.** The alerter, the mailbox (H5), `horde inbox`, the doorbell,
      escalation. Tests first with a fake orc session in the isolated harness: "one wake per goblin per
      transition"; "a restart does not repeat a wake"; "a wake is in the mailbox before any doorbell";
      "a wake reaches an orc whose host handle is unknown"; "no receipt escalates to the warchief".
    - Ledger `planning/ledger/core-alerter.md` and the message half of
      `planning/ledger/agent-claude-code.md`: wezfleet `lib/Notify.ps1` notices, `lib/Mail.ps1` and
      `lib/Delivery.ps1` (their lessons on receipts and lost messages; the typed path itself stays
      unported, migration step 6.1).
14. **`horde orphans`** [H18, first half]. Read-only report of O1, O2 and O4 (O3 deferred to step 33),
    also shown in `horde status` and `horde watch`. Tests first: "an orphan without proof is reported,
    never reclaimed"; "harness processes are recognised only through the agent adapter"; "a planted kill
    verb turns the tripwire red". Adopted through the `orphans` line of `adoption/capabilities.txt`.

## D. Metrics: detectors, backlog, context (needs metrics Stage A)

15. **`missed-communication` and `wasted-tokens` detectors, and the backlog** (4.5). Tests first on
    fixtures cut from today's transcripts: "a wake with no receipt is a missed communication"; "tokens
    inside a loop are counted as wasted"; "the backlog stores ids, never content"; "a fixed item that
    recurs reopens". `horde metrics backlog`.
16. **Context purity per delivered result** (4.5), in `horde metrics report`. Tests first: "orc input
    growth on the receiving turn is attributed to the result"; "follow-up reads within N turns are
    counted"; "a span with no consent reports unknown, never zero".

## E. Admission, consulted then shadowed (needs engine-settings Half A)

17. **Tiers in configuration.** `core/admission-tiers.json` (L0), the `admission` keys in
    `schema/engine-config.v1`, the checker findings of 1.3, `explain` output. Tests first: "a project
    file may lower the admission tier"; "a project file may not raise the admission tier"; "a run spec
    may not set the admission tier"; "hysteresis below a goblin's commit is refused"; "aggressive needs
    an until at the live layer"; "no environment variable changes the tier" (with a control that the
    config file does).
18. **`core/Admission.ps1`** [H9]. Rule, reservations, hysteresis, priority queue, as a pure function;
    `horde admit --kind k --json` answers admit or queue with reasons and acts on nothing. Tests first:
    "standard refuses a goblin at 15:05 counters"; "standard refuses at 15:12 and 15:22 counters";
    "conservative refuses at all three"; "one close never reopens the gate". Ledger
    `planning/ledger/core-admission.md`: wezfleet `commands/pump.ps1` caps, `liveTotal + spawned`,
    "wezterm did not answer" queues.
19. **Per-kind costs** [H10]. `obs.resources` to p90 per kind over 20 spans, floored at the priors
    (P-1).
20. **Tier tuning** (1.4, engine-settings decision 9). The automatic raise as an expiring L4 rule and
    `horde metrics tune --propose` for lowering. Tests first: "a reap while open raises the reserve";
    "a raise expires after seven days"; "a raise never exceeds conservative plus one gigabyte";
    "nothing lowers a reserve without the founder". Shadowed: raises logged, not written, for a working
    week first.

## F. Containment (the anchor is built against a stand-in child; engines E10 supplies the real stub later)

21. **`core/Contain.ps1` and `platform/windows/`**. Create, name, self-assign, query members and peak,
    terminate. Tests first, turning J-3 into a suite that acts only on processes it created: "a child
    created before assignment escapes" (the control); "a child created after assignment dies with the
    job"; "the job handle is not inherited by a child"; "assignment nests under an ambient job".
    Machine probe for `horde install`.
22. **The anchor**, compiled, plus the host flags of 2.5 in `hosts/wezterm/capabilities.json`, measured
    in the isolated instance. It is built against a stand-in child that plays the launch stub (a fixed
    argv and environment over the pipe), and this step defines the pipe contract engines E10 later
    implements. Tests first: "the anchor starts what the stand-in stub hands it"; "a stub that exits
    without a handoff starts nothing"; "a pane whose program exits closes"; "closing the pane ends
    the harness and its children"; "a real harness session runs inside a no-breakaway job" (E2, the
    cheapest prompt that proves it, CONTRIBUTING 3); the anchor's resident memory measured and
    reported, and the goblin prior of P-1 re-measured without a shell.
23. **`horde job run`** [H11]. Admission request, a nested job per heavy job, `PeakJobMemoryUsed`
    recorded, the `DONE=` marker, `-Pausable`, `-Service -Until`. Tests first: "a job's peak equals the
    job object's figure"; "a service outlives its goblin only until its expiry". The pause mechanism is
    unmeasured and chosen in this step.

## G. The last in-place record edit, before migration step 3.8

24. **The binding's lifecycle fields in the record** (3.1, 3.4). The fourth of the four in-place
    `session-record.v1` edits: after remote R10 (branch `docs/remote-plan`: the fleet and binding
    split), engines K1 (the key) and engines R1 (branch `docs/engines-hosts-plans`: `engine` and
    `resume`), and before migration step 3.8 ships the first record writer. Rows and schema properties
    in one PR. The binding record's writer on the node applies `obs.rebind` once it exists. Tests first:
    "a compaction keeps the binding revision"; "model drift does not rebind"; "a new session id links
    predecessor and successor"; "containment and closure are node-owned fields"; "a secret-shaped env
    value is refused".

## H. The writers (Phase 5)

25. **`horde goblin show` and `horde resume`.** Tests first: "resume refuses a shorter transcript";
    "resume refuses a harness change"; "resume never falls back to the default profile"; end-to-end in
    the isolated harness.
26. **Spawn claims** [H12]. `CreateNew` claims, spawn token, `spawn-unknown`, `launch --resume`. Tests
    first: "two pumps, one spawn"; "a killed pump leaves no duplicate". Ledger: `commands/pump.ps1`.
27. **Goblin spawn through the anchor** [H15], after engines E10. The pane's program is the anchor,
    never a shell, and the anchor's child is the real launch stub.
28. **The closer** [H14]. Design A1 states, A3 order, the handle-based end through the anchor, the
    tombstone, the orc notice through the alerter. Isolated harness only; every refusal
    mutation-tested; the victim guard of CONTRIBUTING 9. Ledger `planning/ledger/core-closer.md`:
    `lib/Cleanup.ps1`, `lib/Kill.ps1`, `lib/Notify.ps1` `Close-WfOwnPane`, wezreport's closeOnDone and
    `resume.txt`.
29. **`horde route` and `horde park`** [H16]. Park requires a reason and an expiry capped at 24 h.
30. **Worktree reaper** [H17]. The design's four conditions on `work-merged`, each refusal tested.
31. **Orphan reclaim** [H18, second half]. Proven ownership only, handle method, `obs.orphan` with
    the proof. Tests first: "reclaim cannot choose its victim".
32. **The gate acting** [H19]. The actor pumps queued spawns on `open`; the ladder of design B2.6.
    Shadowed against wezfleet's pump for a working day before it acts.
33. **O3, bare-shell panes** (deferred). Only after Phase 3 has settled what Horde reads from hosts:
    the host adapter answers `pane.bareShell` from the pane's program pid and its own list of shell
    images, and core never reads a title. Until then wezfleet census reports them, and after step 27
    new goblins cannot leave one.

Order: A now. B before any Phase 3 command merges. C next, in the order given; it answers "what is
every goblin doing, and what holds memory" with no writer. D once metrics Stage A exists. E and F
after C, consulted and shadowed before anything acts. G in its place in the in-place edit sequence,
before migration step 3.8. H with Phase 5.

---

# Unproven, and written down

- The Windows threshold behind the reaper's `critical` level (M-30). The standard tier rests on where
  reaping was observed, not on that threshold.
- Whether the pagefile is system-managed, which decides what commit near its limit does.
- Whether the Claude Code harness, or any tool it runs, ever creates a process with
  `CREATE_BREAKAWAY_FROM_JOB`; if it does, that create fails inside a goblin's job (step 22 measures).
- Whether `/clear` gives a running session a new id (ownership `formerNames` is provisional on it).
- The anchor's resident memory, and the follower's (targets, not measurements).
- The goblin cost prior without a shell (P-1 includes one; step 22 re-measures).
- Windows 10 nesting: documented, not measured here (J-3 ran on 10.0.26200).
- Whether the terminal's default closes a pane only on a clean exit; a harness that exits non-zero
  might leave its pane open (step 22 measures `spawn.exitCloses`).
- Every `unverified` cell in 4.3.
- The estimates, each a starting value the metrics tune: the 256 MB raise step and the 14-day quiet
  period (1.4); the 20-turn follow-up window (4.5); the 400-byte, three-line wake size (4.5); the 60 s
  receipt timeout and the 10 wakes per orc per minute (Part 5).
