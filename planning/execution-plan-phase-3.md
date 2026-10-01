# Execution plan: Phase 3, the fleet's read commands move onto Horde

Agreed 2026-09-30. The order of work for Phase 3 of `planning/migration-plan.html`. It covers
wezfleet's read commands - `census`, `sessions`, `tree`, and the naming half of `tell` - moving onto
Horde by shadowing and then adoption. It follows `planning/execution-plan-phases-0-2.md` and keeps its
conventions.

The research behind it was done read-only on 2026-09-30. It read YedPool/wezfleet `acda968`, Horde
`022c2f8`, the unmerged `feature/core-projection`, and the fleet's command logs (store W6: 89 loose
logs and 210 run-scoped ones). Its eleven decisions are settled:

1. The host pane-list read adapter is its own step, and it comes before anything else in Phase 3.
2. `horde install` writes the `horde.cmd` shim, as `wezfleet install` does.
3. Census is shadowed first: it has 47 recorded uses by 8 sessions (7 labelled, 1 unlabelled).
   Sessions comes next, and the Warchief adopts it in its status loop to reach the use gate, because
   sessions has 3 recorded uses ever, all by one orc.
4. `horde census` keeps wezfleet's text anchors - the `PANE` header, rows led by the handle, and
   `registry=N` - and also offers `-Json`.
5. Adoption is tracked per feature. Four census features stay on wezfleet until a host adapter
   provides them: `-Fix`, bare-shell detection, unsent input and the disk line.
6. When a name is both a lane fleet id in the caller's run and another session's label, it is
   ambiguous. This deliberately differs from wezfleet and is logged as an explained difference.
7. At first, Horde refuses a target that has no verified handle, as wezfleet does. Relaxing that
   comes later, in a separate PR, once the shadow logs are clean.
8. The working-day rule is accepted as drafted (below).
9. Shadow logs go to `<home>\shadow\<command>\<date>.jsonl`.
10. The two `tell` defects are filed as wezfleet issues, because Horde does not write to wezfleet.
11. Adoption data lives in a top-level `adoption/` folder.

**Horde's home** is one variable, `HORDE_HOME`, which defaults to `%USERPROFILE%\.horde`. This was
decided 2026-09-30 with the engine-settings design, whose decisions also say there is no
environment-variable layer for engine values. `<home>` below means that directory.

## How every step is done

- **Same as phases 0-2.** Each step:
  - starts from a worktree cut from a freshly fetched `origin/main`;
  - is written test-first, and every new check is mutation-tested;
  - is verified from a fresh CRLF checkout;
  - gets an independent adversarial review of every code PR before merge;
  - merges with `gh pr merge --merge`, never squash;
  - copies every count it quotes from command output.
- **A ledger lands with its tests.**
  - Drafts of the four command ledgers are in `planning/drafts/ledger-*.md`. They are not in
    `planning/ledger/`, because their `test` dispositions cite suites that do not exist yet, so
    `test/test-ledger.ps1` would fail on them.
  - Each command's first PR moves its draft into `planning/ledger/`, in the same PR as the suite that
    makes every disposition hold.
- **Ported commands write with `Write-Output`, return rather than exit, and have `-Json`.**
  - wezfleet prints with `Write-Host`, which cannot be captured in-process.
  - wezfleet's `sessions` ends with `exit 0`, which horde.ps1 reports as 1.
  - Exit codes are 0, 1 or 2.
  - The logic lives in `cli/<Name>.ps1`. `cli/commands/<name>.ps1` only declares the command, which
    is the pattern `horde install` set.
- **Two end-to-end scenarios per command.**
  - A host-neutral one in `test/e2e/` runs `horde` with no host attached.
  - A host-bound one in `hosts/wezterm/test/e2e/` runs it against real panes in an isolated instance.
- **Host neutrality.**
  - `test/test-host-names.ps1` passes in every PR.
  - The target is no new line in `hosts/wezterm/growth.txt`: anything that has to name the terminal
    is placed under `hosts/wezterm/` from the start.
- **Context stays big-picture.**
  - A Warchief or orc session reads a distilled result: a count, a one-line summary, or a `-Json`
    field it picks out. It never reads a full table every cycle.
  - The detail stays on disk, in the shadow log and the store, for whoever needs to look.
  - Every command below has a summary form for this reason. A shadow comparison always compares the
    full data, whatever the caller printed.

## Steps

The migration table's numbers stay as names: step 3.3 is census whenever it runs.

A. Before Phase 3
- The projection and `horde status --json` are merged (phases 0-2 plan, steps 13 and 14).
- `horde install` is merged and has been run on the fleet's machine. It is being built as
  `feature/install-shim` and is not re-planned here. Measured 2026-09-30: `Get-Command horde` found
  nothing, so no session could use Horde for real work. Step 6's PR quotes `Get-Command horde`
  resolving to the shim, run from a fleet session.

B. Groundwork (decision 1). Nothing in C to G starts until step 3 merges.

1. **Rename `HORDE_ROOT` to `HORDE_HOME`.**
   - The isolation harness already sets `HORDE_ROOT` on main: `hosts/wezterm/test/Isolation.ps1`
     (321-493), `e2e-isolation.ps1`, `test-isolation.ps1` and `test/e2e/e2e-cli.ps1`.
   - Rename every use to `HORDE_HOME`, and add one `Get-HordeHome` in core that reads it, defaulting
     to `%USERPROFILE%\.horde`.
   - Gate:
     - The harness's existing check, now on `HORDE_HOME`, proves that an isolated run points Horde's
       home at the throwaway store. From step 4 on, that means an isolated e2e never writes a shadow
       log into the real home.
     - A sweep finds 0 `HORDE_ROOT` in the tree. Its control finds the name planted at runtime.
2. **Host discovery in core, which names no host.**
   - Each host declares itself in data, `hosts/<name>/capabilities.json`. It is validated by
     `schema/host-capabilities.v1.json` and holds:
     - the host's name;
     - its capability table in the HostPort vocabulary (`yes`, `no`, `declined` or `unverified` per
       name);
     - the session markers that identify a session running inside it.
   - `hosts/<name>/HostRead.ps1` builds the port from that same file, so there is one declaration
     format, and discovery runs no host code.
   - `core/Hosts.ps1` returns **this session's host**: the one whose markers the calling process
     carries.
     - None gives an unavailable port with the reason.
     - A second installed host changes nothing, because only the session's own host is asked.
     - Nested hosts (a multiplexer inside a terminal) resolve to the innermost. If that cannot be
       decided, that one session gets an unavailable port with the reason.
   - The host-neutral e2e scenarios run `horde` in a child process with every declared host's markers
     removed. They read the marker names from the declarations, so no test names a host.
   - Tests first (`test/test-hosts.ps1`), all with fake declarations:
     - zero, one and two installed hosts;
     - the session in one of two hosts;
     - nesting;
     - a malformed declaration refused.
   - Control: `horde status` output is unchanged while no host is declared.
3. **`hosts/wezterm/HostRead.ps1`**, built on the HostPort at `feature/core-projection` `4eec8d9`.
   - The contract:
     - `New-HordeHostPort -Name -Capabilities -Handles -Instance`, where `-Capabilities` is
       mandatory and core relies on a capability only when it is `yes`.
     - Rows are `{ handle; window; tab; hostTitle }`, plus `{ pid; cwd; space }` when they are
       offered. A pid or cwd is tagged with its namespace (`windows`, `wsl:<distro>`, `posix`,
       `synthetic`), and core treats any space other than `windows` as unknown.
     - The instance is `{ id; startedAt; running; ambiguous }`.
   - Its `capabilities.json` declares:
     - `yes` for `list`, `cwd`, `title.read`, `selfHandle` and `instance.startedAt`, each measured in
       the PR;
     - `declined` for every verb that acts (`spawn`, `kill`, `text.send`, `title.set`, `focus`);
     - `unverified` for anything it has not measured.
   - A tripwire asserts the adapter's source calls none of the declined verbs. Its control finds one
     planted at runtime.
   - It honours the socket pin from CONTRIBUTING rule 3, so the instance it reads is the one the
     environment points at.
   - Tests first (`hosts/wezterm/test/test-host-read.ps1`, over captured list output):
     - an unreadable list is unknown, never zero;
     - zero handles is a known empty list;
     - handles pass through as opaque text;
     - the instance start time is placed in UTC;
     - two running instances with no pin is ambiguous;
     - every pid and cwd carries `windows`.
   - The same suite runs `test/lib/HostReadConformance.ps1`, which names no host. It checks:
     - that the capability table is complete and valid;
     - that no `declined` or `unverified` capability is ever called;
     - that each row's pid and cwd carry a space;
     - that the port answers the contract.

     A later tmux, psmux, Ghostty or VS Code adapter runs the same helper with its own fixtures.
   - The e2e (`hosts/wezterm/test/e2e/e2e-host-read.ps1`), pinned to the isolated instance, lists
     exactly the panes the harness spawned and none of the user's.
   - Ledger: `planning/ledger/hosts-wezterm-read.md`, harvested in the PR. Its known lessons:
     - an unreadable pane list became an empty map (wezfleet `lib/Common.ps1:497-503`), and census
       then printed "no live panes.";
     - a record written before the instance started names another instance's pane (`0e1c75a`);
     - `Get-WfCurrentInstance` held the four instance facts (`lib/Common.ps1:539-595`);
     - clearing the mux socket read as zero panes.
   - Gate: `horde status` in a fleet session shows known handles, and a re-run of the step 2.3 parity
     harness shows the P-27 rows gone. The PR quotes both counts.

C. Shared machinery

4. **The shadow harness (D6).**
   - The PR adds:
     - `cli/Shadow.ps1`, the harness;
     - `cli/shadow/Wezfleet.ps1`, the child helper;
     - `schema/shadow-log.v1.json`;
     - `tools/ShadowReport.ps1`;
     - `hosts/wezterm/Shadow.ps1`, the host hook;
     - `test/test-shadow.ps1`.
   - **Old side.** The shipped `wezfleet` found on PATH, run in a child PowerShell, because wezfleet
     code calls `exit`.
     - Each comparison records wezfleet's commit and whether its tree is dirty.
     - The child never runs `-Fix`, `status` (its pump writes), `Invoke-WfTell` or
       `Resolve-WfSessionRowOrFail`.
   - **New side.** The real `horde <command> -Json`.
   - **The A-H-A' sandwich.** wezfleet is read (A), then Horde (H), then wezfleet again (A').
     - A field that changed between A and A' is `volatile` (SH-01).
     - A different host instance makes the comparison `inconclusive` (SH-02).
     - Translating wezfleet's instance record into the adapter's instance id is host knowledge. It
       lives in `hosts/wezterm/Shadow.ps1`, reached through the host declaration.
   - **Classification is code.** There is one function per allowance id, and each re-checks its
     condition from the two inputs. A difference no classifier claims is `unexplained`.
   - **The log** (decision 9) is appended to `<home>\shadow\<command>\<YYYY-MM-DD>.jsonl`, dated in
     UTC. It is never under wezfleet's root or inside the repository, and it is never a session
     record. Each line validates against the schema and carries:
     - `at`, `command`, `args`, `trigger` (`use` or `sampler`) and `caller`;
     - `old` and `new`, each with its system, commit, exit code and read times;
     - `instance`;
     - `keys`;
     - `differences`, each with its key, field, old value, new value, class and volatility;
     - `counts`;
     - `verdict` (`clean`, `unexplained` or `inconclusive`).

     A log line that fails to write is reported on the error stream and never changes the result. A
     missing comparison can only make a day fail to qualify, never pass.
   - **Shadow mode.**
     - During a command's shadow, `horde <command>` prints wezfleet's result (D6), computes its own
       silently, and logs the comparison with `trigger: use`. `-New` shows Horde's result and logs
       nothing.
     - The mode is a constant in the command's logic file, so the switch is a one-line PR.
     - After the switch, `-Old` keeps wezfleet's result for one more phase.
     - If the old side cannot run, the command exits 1 with the reason, and the comparison is logged
       as `inconclusive`.
   - **`tools/ShadowReport.ps1 <command> [-Date]`** prints one working day's verdict, and every switch
     PR quotes it.
   - Tests first, over fixture logs and a stub old side:
     - the path honours `HORDE_HOME`;
     - every line validates against the schema;
     - SH-01, SH-02 and SH-03 each behave as described;
     - an unclaimed difference is unexplained;
     - the report's qualifying and clean rules each have a passing and a failing day.
   - No ledger, because the harness replaces nothing. It is retired with wezfleet (step 6.4). A
     machine with only another host has no old side, and its commands run in switched mode.
5. **The adoption ledger (step 3.2, decision 11).**
   - The PR adds `adoption/capabilities.txt`, `ledger.txt`, `evidence.txt`, `implementers.txt` and
     `growth.txt`, plus `test/test-adoption.ps1` and the harvest tool `tools/Adoption.ps1`.
   - It lives outside `planning/` because a non-prose file there fails the host-name ratchet.
     `adoption/` is scanned like any other folder, and capabilities are named by what they do.
   - The unit is a feature, not a command (decision 5). The capabilities are:

     | capability | what it covers |
     |---|---|
     | `census` | |
     | `census-fix` | tab titles |
     | `census-bare-shell` | |
     | `census-unsent` | |
     | `census-disk` | |
     | `sessions` | |
     | `tree` | |
     | `tell-target` | |
     | `status` | step 3.4 |
     | `warchief-loop` | step 3.7 |

     Each line of `capabilities.txt` reads `<capability> | <old form> | <new form> | <why one unit>`.
   - `ledger.txt` has one line per (role, capability): `<role> | <capability> | <system> | <since> |
     <evidence ids>`, with roles in `core/roles` words. It is seeded from the command logs, all
     `wezfleet`, and every line cites harvested evidence.
   - **The harvest.** `evidence.txt` is harvested read-only from W6 and the shadow logs. It holds
     tokens only (role, capability, session id, first and last UTC, count, store, asOf) and never
     command text, for three reasons:
     - the text can hold secrets;
     - it can name the terminal;
     - it is truncated at 160 characters.

     W6 prunes loose logs after 14 days, so evidence has to be captured into the repository while it
     exists.
   - **A recorded use** has all of the following:
     - the capability is invoked at a command position;
     - the session's role is known (an unknown role is harvested as `unknown`);
     - it is not a test session: no `WEZFLEET_ROOT` or `HORDE_HOME` override, no isolated instance,
       and no suite temp root;
     - it falls inside the harvest window.

     `sampler` comparisons, suites, implementers' sessions and the founder's own typing do not count.
     The last is not logged at all: a stated gap, not a zero.
   - **Rules** (`test/test-adoption.ps1`, built like wezfleet's `test_debug/test-ssot.ps1` and reusing
     `Test-HordeHostShrink`'s comparison with `origin/main`):
     1. The ledger is well-formed.
     2. No line claims adoption without recorded use: an entry claiming adoption with no recorded use
        fails.
     3. No evidence comes from an implementer.
     4. The old side only shrinks against `origin/main`, unless a line added to `growth.txt` says why.
     5. No line is fiction: an old-side line with no use in the newest harvest fails. This is judged
        against the harvest's `asOf`, never the clock.
     6. Controls, as in test-ssot.ps1:129-137.

D. `horde census` (step 3.3), first by decision 3

6. **The command, in shadow mode.**
   - The PR adds the `fleet` command group, `cli/Census.ps1`, `cli/shadow/census.ps1`,
     `planning/ledger/cli-census.md` (from `planning/drafts/ledger-cli-census.md`),
     `test/test-census.ps1` and both e2e scenarios.
   - Output (decision 4):
     - The header starts with `PANE`, each row starts with its handle, and the summary reads
       `registry=N   pane-sessions=N   none=N`.
     - Data rows come before any diagnostics, because callers grep `^PANE|^\d|registry=` and read with
       `Select-Object -First 14`.
     - `PANE` is D12's host-neutral word.
     - `-Json` emits the view's handles section, validated against `schema/session-view.v1.json`.
     - `-Summary` prints the summary line only.
   - Rows come from the view's handles, one per live handle. Handles sort numerically only when every
     one is a number, because a handle is opaque.
   - The comparer:
     - **Old:** the shipped `Get-WfFleetCensus`, `Get-WfUnclaimedUserSessions` and
       `Get-WfIdentityHealth`. The text command is not run, because it reads every pane's screen.
     - **Key:** the handle within the instance.
     - **Compared per handle:** session id, source class (registry is W1, pane-sessions is X1),
       owner, origin, window, title against `hostTitle`, and whether SEEN is known.
     - **Compared as sets:** the handles, the unowned sessions the founder opened, and the fault
       lists.
     - **Allowances:** P-04, P-08 to P-16, P-26, P-27 and SH-01 to SH-03.
7. **Shadow, then switch.**
   - The handoff says to use `horde census` wherever `wezfleet census` was used. It prints the same
     output during the shadow.
   - The switch PR quotes `ShadowReport` for a qualifying clean day.
   - A new kind of difference gets an allowance id, a classifier and a test in a PR of its own, and
     the day starts again.
8. **Adoption recorded.**
   - (role, `census`) lines with post-switch evidence move to `horde`.
   - `census-fix`, `census-bare-shell`, `census-unsent` and `census-disk` stay on `wezfleet`
     (decision 5). A caller that needs one of them keeps running `wezfleet census` for it, and the
     adoption ledger says so by name.
   - Title repair belongs with host decoration (step 7.2), the screen reads with a host adapter, and
     disk space with a later doctor command.

E. `horde sessions` (step 3.1)

9. **The command, in shadow mode.**
   - The PR adds `cli/Sessions.ps1`, `cli/shadow/sessions.ps1`, `planning/ledger/cli-sessions.md`,
     `test/test-sessions.ps1` and both e2e scenarios.
   - It may open once census is in shadow. A shadow is bound to the calendar, not to the previous
     switch.
   - "Running" is defined once, in `cli/Sessions.ps1`, and the S-01 classifier uses that same
     definition.
   - The filter is a literal substring over id, name and label.
   - `-Summary` prints the footer counts only: total, busy, and how many have no handle.
   - The comparer:
     - **Old:** the shipped command's text, because the pane map and labels are built inline. Each
       row round-trips through its own format string, or it is `parse-unknown` (SH-03).
     - **Key:** the 8-character SESSION column plus PID.
     - **Allowances:** P-01 to P-07, P-27, S-01 to S-03 and SH-01 to SH-03.
10. **Shadow, then switch, with the Warchief supplying the use** (decision 3).
    - The Warchief's status loop runs `horde sessions -Summary` each cycle, or reads the counts from
      `-Json`. It never reads the full table. The comparison behind each call is still complete, and
      its detail stays in the shadow log on disk.
    - The working-day rule needs two distinct sessions, so for the length of the shadow the handoff
      asks one orc to take its own roster count through `horde sessions -Summary`.
11. **Adoption recorded:** (warchief, sessions), plus each orc line that has evidence.

F. `horde tree` (step 3.5)

12. **The command, in shadow mode.**
    - The PR adds `cli/Tree.ps1`, `cli/shadow/tree.ps1`, `schema/fleet-tree.v1.json`,
      `planning/ledger/cli-tree.md`, `test/test-tree.ps1` and both e2e scenarios.
    - Every non-retired session is drawn exactly once. wezfleet never draws children of an unassigned
      node, members of a parent loop, or a session whose parent is gone.
    - Roles are mapped through `core/roles`. Fault kinds are mapped by one table of old and new names
      in `cli/Tree.ps1`:
      - no-master becomes no-warchief;
      - two-masters becomes two-warchiefs;
      - orchestrator-not-under-master becomes orc-not-under-warchief;
      - parent-missing becomes parent-missing or parent-retired.
    - The advice names no wezfleet command.
    - `-Summary` prints the fault list and the count of unassigned sessions.
    - The comparer:
      - **Old:** the shipped `Get-WfHierarchy`, `Get-WfHierarchyFindings` and `Format-WfRecordPane`,
        plus the tree text to count the drawn rows per depth. That count is what exposes T-03.
      - **Key:** claudeSessionId.
      - **Allowances:** P-23 to P-27, T-01 to T-03 and SH-01 to SH-03.
      - Tree calls no host verb.
13. **Shadow, then switch.**
    - The Warchief (11 recorded uses) and orc D (5) are the users.
    - The master handoff skill takes scope names from `wezfleet tree`. That line changes to
      `horde tree -Summary`, or `-Json`, when the shadow starts.
14. **Adoption recorded.**

G. Target naming, the naming half of `tell` (step 3.6)

15. **`core/Target.ps1` and `horde target <name>`, in shadow mode.**
    - The PR adds `core/Target.ps1`, `cli/Target.ps1`, `cli/shadow/target.ps1`,
      `schema/target-result.v1.json`, `planning/ledger/core-target.md`, `test/test-target.ps1` and
      both e2e scenarios.
    - What names a session:
      - a label, matched case-sensitively;
      - a full id;
      - a unique hex prefix of 8 or more characters, in any case;
      - a fleet id.
    - It returns a result and never exits. A refusal exits 1, and a malformed name exits 2.
    - **`Get-HordeSessionName`, the inverse: the one source of a session's name** (founder request,
      2026-10-01). A pure function from a fleet record to the name people see for that session:
      today its label, as M used for the web titles of 2026-10-01. Every place that shows a session's
      name calls it and formats none of its own: the target result's `name`, the remote-view name at
      birth (engines E9 and N1), `horde names` and its repair (lifecycle step 34), and host title
      decoration (migration step 7.2). Tests first:
      - "every name it returns resolves back to the same session through `horde target`", over every
        fixture record. So whatever a person reads off a web title or a terminal tab is a name Horde
        accepts. A mutation that appends the run title turns it red;
      - "a record with no label has no name, with the reason", never an empty string or the id.
    - Decision 6: a lane fleet id that is also a label elsewhere is ambiguous.
    - Decision 7: a session with no verified handle is refused. "Verified" means the view answers the
      handle as live in the current instance.
    - Horde does not deliver, and the delivery exit codes are not ported (step 6.1). Adopting it means
      resolving with `horde target`, then sending to the messaging address it returns.
    - The comparer:
      - **Old:** the shipped `Resolve-WfRunForSession`, then `Resolve-WfFleetTarget`. For a lane
        caller, `WEZFLEET_RUN_DIR` is set to that caller's run.
      - **Key:** (target, caller).
      - **Compared:** the outcome class, the resolved id, and the candidates.
      - **Not compared:**
        - the handle;
        - the warnings, while wezfleet#18 and wezfleet#19 are open.
      - One of wezfleet's refusal texts names the terminal, so the table that maps reason text to
        outcome class lives in `hosts/wezterm/Shadow.ps1`.
      - A real `horde target` call is `use`. The 623 real `wezfleet tell` targets are replayed as
        `sampler`, which never counts toward the minimum.
      - **Allowances:** P-07, P-22, P-27, G-01, G-02 and SH-01 to SH-03.
16. **Shadow, then switch.**
17. **Adoption recorded.**
18. **Later, in a separate PR: relax the verified-handle rule** (decision 7). This happens only after
    the target shadow is clean.
    - Draft L-013, L-014 and L-017 change back to the research's form: a session with no handle still
      resolves to its messaging address.
    - It is not part of step 3.6's gate.

H. Planned when reached
- **3.4 `status`.** wezfleet's `status` writes (its pump runs) before it reads, so a shadow must call
  `Get-WfRunSnapshot`. The step's first decision is what wezfleet's run-scoped output corresponds to
  in Horde's fleet-wide view.
- **3.7 the Warchief's loop.** Last, because the whole fleet depends on it.
- **Web session titles are not repaired here.** Repair changes a live session, so it is a write verb
  and fails the read-command tripwire (lifecycle step 4). It is lifecycle step 34,
  `horde names repair`; this plan owns only the name it uses (step 15).
- **3.8 the record writer.** Unchanged from the migration table, except that it has a gate. The first record writer must not merge until these four in-place
  `session-record.v1` edits have merged, in this order:
  1. remote R10, the fleet/binding split (`planning/execution-plan-remote.md`);
  2. engines K1, the (harness, id) key;
  3. engines R1, `engine` and `resume` in the binding record (`planning/execution-plan-engines.md`);
  4. lifecycle 24, the rest of the binding fields (`planning/execution-plan-lifecycle.md`).
  Once a writer exists, every later change is a v2. The 3.8 PR states in its body that all four have merged.

## The working-day rule (decision 8)

A working day is one America/New_York calendar date. This is `ShadowReport`'s default zone, and every
report prints the zone it used.

A day qualifies when all of these hold:
- at least 5 `trigger: use` comparisons from sessions that are not implementers;
- from at least 2 distinct sessions;
- the first and last comparisons at least 6 hours apart;
- none of the qualifying comparisons is `inconclusive`;
- wezfleet's commit stays constant through the day, or each change is logged.

A qualifying day is clean when none of its comparisons has an `unexplained` difference. If a new kind
of difference appears, the day starts again. `sampler` comparisons never count toward the minimum.
One clean qualifying day is each command's switch gate.

## Shadow allowances beyond P-01..P-27

The P-ids are in `planning/parity-2.3.md` (`feature/core-projection`). Each allowance below gets a
classifier and a test in its comparer's PR, before that command's shadow starts.

| id | difference | why it is explained |
|---|---|---|
| SH-01 | a field changed between wezfleet's two reads | timing; `volatile`, counted neither way |
| SH-02 | the host instance differs between the sides | they looked at different terminals; `inconclusive` |
| SH-03 | a wezfleet text row does not round-trip through its format | `parse-unknown`, reported, never skipped |
| S-01 | other engines' sessions, registry-only sessions and retired ones are in the view | wezfleet reads one engine's control files (`lib/MailPump.ps1:56-66`) |
| S-02 | the filter matches a label | wezfleet matches id and name only (`sessions.ps1:67`) |
| S-03 | a filter with `[ ] * ?`: wezfleet throws or wildcard-matches | wezfleet uses `-like`; Horde matches literally |
| T-01 | a parent loop is drawn and reported | wezfleet has no loop check |
| T-02 | the unassigned set | wezfleet's comment and code disagree; Horde states one rule |
| T-03 | sessions wezfleet never draws | only masters are recursed from (`tree.ps1:20-47`) |
| G-01 | wezfleet refuses a bare-shell pane; Horde resolves | bare-shell detection reads host titles and stays on wezfleet (decision 5) |
| G-02 | a lane fleet id that is also a label: wezfleet picks the run, Horde says ambiguous | decision 6 |

Decision 7 narrows the research's G-01 to the bare-shell case. Any other refusal because the handle
could not be verified must now agree on both sides.

## Filed on wezfleet, not fixed here (decision 10)

- **YedPool/wezfleet#18**: `tell`'s hierarchy warning reads `CLAUDE_SESSION_ID`, which nothing sets
  (`commands/tell.ps1:123`, measured 2026-09-30). In Horde this is draft core-target L-021.
- **YedPool/wezfleet#19**: the cross-owner warning compares a label with a fleet id
  (`lib/Registry.ps1:1070-1076`, read-found). In Horde this is draft L-022.

## Host neutrality (D12)

| step | what could name a terminal | where it lives |
|---|---|---|
| 1 home rename | nothing | core, and the harness under `hosts/wezterm/test/` |
| 2 discovery | nothing; hosts are declared as data | `core/Hosts.ps1`, `hosts/<name>/capabilities.json` |
| 3 read adapter | the list command, socket pin, fixtures, e2e | `hosts/wezterm/` |
| 4 shadow | the instance-id translation | `hosts/wezterm/Shadow.ps1` |
| 5 adoption | nothing; no command text is stored | `adoption/`, scanned |
| 6, 9, 12 commands | nothing (`PANE` is host-neutral); the real-pane e2e | `hosts/wezterm/test/e2e/` |
| 15 target | wezfleet's refusal text | `hosts/wezterm/Shadow.ps1` |
| 8 census extras | title repair and screen reads | a later `hosts/<name>/` adapter, never core |

A second host joins without an engine change. It needs:
- a `capabilities.json` and a `HostRead.ps1`;
- to pass `test/lib/HostReadConformance.ps1` with its own fixtures;
- its own isolated e2e (tmux: a private `-L` socket).

A host with no handles answers a known empty list, which every command already prints. Engine-specific
fixtures live under `agents/<name>/test/`, never in a core suite.

## Ledgers

The `core-projection` ledger keeps the data rules. The four command drafts carry what each command
shows and what callers rely on, and cite projection entries rather than repeating them:
- `planning/drafts/ledger-cli-census.md`
- `planning/drafts/ledger-cli-sessions.md`
- `planning/drafts/ledger-cli-tree.md`
- `planning/drafts/ledger-core-target.md`

Each draft's opening paragraph says what was adapted from the research.
