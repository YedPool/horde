# Execution plan: Phase 3, the fleet's read commands move onto Horde

Agreed 2026-09-30. The order of work for Phase 3 of `planning/migration-plan.html`: wezfleet's read
commands - `census`, `sessions`, `tree`, and the naming half of `tell` - move onto Horde by shadowing
and then adoption. It follows the phases 0-2 plan (`planning/execution-plan-phases-0-2.md`) and uses
its conventions.

The research behind it was done read-only on 2026-09-30 against YedPool/wezfleet `acda968`, Horde
`022c2f8` and the unmerged `feature/core-projection` at `483dd63`, plus the fleet's command logs (store
W6: 89 loose and 210 run-scoped logs). Its findings are cited below as F1-F10. Its eleven decisions,
taken the same day, are settled and are cited as "decision N":

1. The host pane-list read adapter is its own step, before anything else in Phase 3.
2. `horde install` writes the `horde.cmd` shim, as `wezfleet install` does; nothing is hand-placed.
3. Census is shadowed first (47 recorded uses by 7 sessions). Sessions follows, and the Warchief
   adopts it in its status loop to reach the use gate (3 recorded uses ever, all by one orc).
4. `horde census` keeps wezfleet's text anchors - the `PANE` header, rows led by the handle,
   `registry=N` - and also offers `-Json`.
5. Adoption is tracked per feature. `-Fix`, bare-shell detection, unsent input and the disk line stay
   on wezfleet until a host adapter provides them.
6. A name that is both a lane fleet id in the caller's run and another session's label is ambiguous.
   A deliberate difference from wezfleet, logged as an explained shadow difference.
7. At first Horde refuses a target with no verified handle, as wezfleet does. Relaxing that is a later,
   separate PR once the shadow logs are clean.
8. The working-day rule is accepted as drafted (below, "The working-day rule").
9. Shadow logs go to `%USERPROFILE%\.horde\shadow\<command>\<date>.jsonl`, `HORDE_ROOT` overriding
   `%USERPROFILE%\.horde`.
10. The two `tell` defects are filed as wezfleet issues. Horde does not write to wezfleet.
11. Adoption data lives in a top-level `adoption/` folder.

## How every step is done

As in the phases 0-2 plan: a worktree from a freshly fetched `origin/main`; test-first; every new
check mutation-tested; verified from a fresh CRLF checkout; an independent adversarial review of every
code PR before merge; `gh pr merge --merge`, never squash; every count in a commit or PR copied from
command output. In addition, for Phase 3:

- **A step's ledger lands with its tests, in the same PR.** The four draft ledgers in the appendices
  cite tests that do not exist yet, so `test/test-ledger.ps1` would fail on them today. They are kept
  here as drafts and none is added under `planning/ledger/` by this plan's PR. Each command's first PR
  adds its ledger in the same PR as the suite that makes every `test` disposition resolve.
- **Every ported command writes data with `Write-Output`, returns rather than exits, and has
  `-Json`** (F7). wezfleet's versions print with `Write-Host`, which cannot be captured in-process,
  and `sessions` ends with `exit 0`, which horde.ps1 turns into exit 1. Exit codes follow horde.ps1's
  contract: 0, 1 or 2.
- **The logic lives beside the declaration.** `cli/commands/<name>.ps1` only declares the command
  (the registry refuses a file that does work at load time); the logic lives in `cli/<Name>.ps1`,
  the pattern `horde install` set with `cli/Install.ps1`.
- **Every user-facing command gets two end-to-end scenarios** (CLAUDE.md, "Done means the fleet runs
  on it"): a host-neutral one in `test/e2e/` that drives the real `horde` CLI against a throwaway store
  with no host attached (`HORDE_HOST=none`, see step 1), and a host-bound one in
  `hosts/wezterm/test/e2e/` that drives it against real panes in an isolated instance.
- **Host neutrality is checked in every PR.** `test/test-host-names.ps1` runs green, and the target
  for Phase 3 is **no new line in `hosts/wezterm/growth.txt` from any PR in this plan**: everything that
  must name the terminal is placed under `hosts/wezterm/` from the start. How each step keeps to that
  is stated in the step.

## Where each step sits in the migration table

| migration step | what | here |
|---|---|---|
| (new) | the host read adapter (decision 1) | B, steps 1-2 |
| (new) | shadow machinery shared by every command | C, step 3 |
| 3.2 | the adoption ledger | C, step 4 |
| 3.3 | `horde census` | D, steps 5-7 |
| 3.1 | `horde sessions` | E, steps 8-10 |
| 3.5 | `horde tree` | F, steps 11-13 |
| 3.6 | message target resolution, the naming half of `tell` | G, steps 14-17 |
| 3.4, 3.7, 3.8 | `horde status` as a wezfleet replacement, the Warchief's loop, the record writer | H, planned when reached |

The migration table's own numbers are kept as names, so a ledger or a PR can say "step 3.3" and mean
census whatever order it ran in. Census moves ahead of sessions by decision 3.

## Steps

A. Before Phase 3 starts (not steps of this plan)

- **The projection and `horde status --json` are merged** - phases 0-2 plan steps 13 and 14,
  `feature/core-projection` and its successor. Everything below reads the view the projection builds
  and `schema/session-view.v1.json`, which lands with it.
- **`horde install` is merged and has been run on the fleet's machine** (decision 2, F2). It is being
  built now as `feature/install-shim` (`cli/Install.ps1`, `cli/commands/install.ps1`) and is not
  re-planned here. Measured 2026-09-30: `Get-Command horde` found nothing, so no session could use
  Horde for real work and D11's gate could not be met. The census shadow-start PR (step 5) quotes
  `Get-Command horde` resolving to the installed shim, run in a fleet session.

B. The prerequisite: the host read adapter (decision 1, F1)

Nothing in C to G starts until step 2 merges. Today `Get-HordeProjection` defaults `-HostPort` to
`New-HordeUnavailableHostPort` ("no host adapter is attached", core/Projection.ps1:995 on
`feature/core-projection`), so under P-27 every handle is unknown: `horde sessions` would print `?` in
every pane column, `horde census` would have no rows at all, and the pane column of `tree` could not be
shadowed. A shadow run in that state could be "clean" and prove nothing.

1. **Host discovery, in core, naming no host.** PR: `core/Hosts.ps1`, its suite
   `test/test-hosts.ps1`, and the CLI change that passes the discovered port to every projection call.
   - A host declares its read port in `hosts/<name>/HostRead.ps1`, one statement
     `$HordeHostRead = @{ name = ...; detect = { ... }; port = { ... } }`, checked on the syntax tree
     before anything in it runs - the same rule `cli/Commands.ps1` applies to command files, for the
     same reason (a declaration that does work at load time is refused, not run).
   - Discovery enumerates `hosts/*/HostRead.ps1`; core never spells a host's name. `detect` answers
     whether the host is reachable from here, through `core/tristate`. Exactly one reachable host gives
     its port. None gives `New-HordeUnavailableHostPort` with the reason. More than one gives an
     unavailable port whose reason says so: combining hosts is Phase 7's question (D12), and
     guessing one of two would verify handles against the wrong terminal.
   - `HORDE_HOST=<name>` attaches that host only; `HORDE_HOST=none` attaches none. This is how the
     host-neutral end-to-end scenarios run on a machine where a host is reachable, and it is the
     operator's override when two are.
   - Tests first: a fake host declaration under the suite's temp root proves discovery, the zero,
     one and two host cases, the override, and a declaration that runs code at load time being
     refused. With no host declared yet, `horde status` output is unchanged; the suite's control
     asserts exactly that.
   - No ledger: it replaces nothing in wezfleet.

2. **`hosts/wezterm/HostRead.ps1`, against the projection's HostPort contract.** PR: the adapter, its
   ledger `planning/ledger/hosts-wezterm-read.md`, `hosts/wezterm/test/test-host-read.ps1`,
   `hosts/wezterm/test/e2e/e2e-host-read.ps1`, and a host-neutral conformance helper
   `test/lib/HostReadConformance.ps1`.
   - The contract is `core/HostPort.ps1` on `feature/core-projection`: `New-HordeHostPort -Name
     -Handles -Instance`, where `Handles` returns rows `{ handle; window; tab; hostTitle }` and
     `Instance` returns `{ id; startedAt; running; ambiguous }`. Core already turns a port that throws,
     writes an error, returns nothing, lists a malformed or repeated handle, or gives an unplaced start
     time into unknown with a reason. The adapter's job is only to answer truthfully, never to
     second-guess core.
   - Read verbs only: the adapter calls the host's list command and the instance facts, and nothing
     that spawns, kills, sends or retitles. A tripwire in the suite asserts the adapter's source holds
     none of those verbs, with a control that finds one planted at runtime.
   - It honours the socket pin CONTRIBUTING rule 3 describes: the instance it reads is the one the
     environment points at, which is what makes the isolated e2e possible and what makes "same
     instance on both sides" (step 3) checkable.
   - Tests first, in `hosts/wezterm/test/test-host-read.ps1` over captured list output under
     `hosts/wezterm/test/fixtures/`: an unreadable list is unknown, never zero; zero handles is a known
     empty list; a pane id is passed on as opaque text; the instance start time is placed in UTC; two
     running instances with no pin is ambiguous. The same file runs `test/lib/HostReadConformance.ps1`,
     which checks any port against the contract and names no host, so a tmux, psmux, Ghostty or VS Code
     adapter later runs the same conformance checks with its own fixtures.
   - End to end, in the isolated instance: the adapter pinned to the harness's socket lists exactly
     the panes the harness spawned (the control: the count equals what was spawned), and never one of
     the user's.
   - Ledger lessons to harvest (the full harvest is the PR's first commit): wezfleet turned an
     unreadable pane list into an empty map (`lib/Common.ps1:497-503`) and census then printed "no
     live panes." (`commands/census.ps1:10-11`); a record written before the instance started names
     another instance's pane (`0e1c75a`); `Get-WfCurrentInstance` held the same four instance facts
     (`lib/Common.ps1:539-595`); clearing the mux socket read as zero panes and printed `-` for every
     session (wezfleet `planning/wezfleet-ssot-multi-backend-2026-09-29.md:512-519`). Data rules the
     projection already carries (core-projection L-004, L-005, L-064) are cited, not repeated.
   - Gate: `horde status` in a live fleet session shows known handles, and a re-run of the step 2.3
     parity harness shows the P-27 rows gone; both counts quoted in the PR.
   - Host-neutral by construction: everything that names the terminal is in `hosts/wezterm/`; core
     and the conformance helper speak only of handles and instances.

C. Machinery every command shares

3. **The shadow harness (D6).** PR: `cli/Shadow.ps1`, `cli/shadow/Wezfleet.ps1`,
   `schema/shadow-log.v1.json`, `tools/ShadowReport.ps1`, the host hook `hosts/wezterm/Shadow.ps1`,
   and `test/test-shadow.ps1`. It adds no command; steps 5, 8, 11 and 14 each add their comparer.
   - **The old side** is the live wezfleet install, found through the `wezfleet` command on PATH (the
     shipped command, CONTRIBUTING 6), never an absolute path in code (CONTRIBUTING 11). It runs in a
     child PowerShell, because wezfleet's sessions and target code call `exit` (F7, core-target draft
     L-023) and because wezfleet must not be loaded into Horde's process. Every comparison records
     wezfleet's `git rev-parse HEAD` and whether its tree is dirty. The child never passes `-Fix`, never
     runs `status` (its pump writes, P-20), and never calls `Invoke-WfTell` or
     `Resolve-WfSessionRowOrFail`.
   - **The new side** is the real `horde <command> -Json` path, run in-process, which also proves the
     wiring (core-projection L-052).
   - **A-H-A' sandwich.** Read wezfleet (A), then Horde (H), then wezfleet again (A'). A field where A
     differs from A' changed between reads: it is `volatile` and counts toward neither clean nor
     unexplained (allowance SH-01). Busy and idle flip within seconds.
   - **Same host instance on both sides.** If the instance differs between A and H the comparison is
     `inconclusive` (SH-02). Translating wezfleet's instance record into the adapter's instance id is
     host knowledge, so it lives in `hosts/wezterm/Shadow.ps1`, reached through the host declaration
     from step 1, not named by core or cli.
   - **Classification is code.** One function per allowance id, each re-checking that allowance's
     condition from the two inputs (for example, P-01 needs a Horde pane read from W1 and a wezfleet
     pane of `-`). A difference no classifier claims is `unexplained`. Nobody types a label onto a
     difference.
   - **The log.** One JSON object per comparison, appended to
     `<root>\shadow\<command>\<YYYY-MM-DD>.jsonl`, where `<root>` is `HORDE_ROOT` when set and
     `%USERPROFILE%\.horde` otherwise, and the date is UTC (decision 9). Never under wezfleet's root,
     never inside the repository, and never a session record, so step 3.8's rule (no session record
     before its writer) is untouched. The writer is in `cli/`, never in `core/Projection.ps1`, whose
     suite asserts it holds no file-writing call (core-projection L-001). Every line validates against
     `schema/shadow-log.v1.json`:

     ```
     {"schemaVersion":1,"at":"2026-10-01T14:02:11Z","command":"census","args":[],
      "trigger":"use|sampler","caller":{"sessionId":"...","role":"orc","label":"A"},
      "old":{"system":"wezfleet","commit":"acda968","dirty":false,"exit":0,"readAt":["...Z","...Z"]},
      "new":{"system":"horde","commit":"...","exit":0,"readAt":"...Z"},
      "instance":{"old":"<id>","new":"<id>"},
      "keys":{"old":12,"new":12,"both":12},
      "differences":[{"key":"27","field":"session","old":"38d41f80","new":null,"newState":"unknown",
                      "class":"P-14","volatile":false}],
      "counts":{"explained":1,"unexplained":0,"volatile":0},
      "verdict":"clean|unexplained|inconclusive"}
     ```

     A log line that cannot be written is reported on the error stream and does not change the
     command's result or exit code; the comparison is simply missing from the day, which can only make
     a day fail to qualify, never make it pass. The logs are small (one line per call) and are not
     pruned in Phase 3.
   - **Shadow mode, per command** (research option 1, recommended and taken). During a command's
     shadow, `horde <command>` prints **wezfleet's** result (D6: the old result is the one used),
     computes its own silently, and logs the comparison with `trigger: use`. `-New` prints Horde's own
     result instead and logs nothing. The mode is a constant in the command's logic file, so the switch
     is a one-line, reviewable, revertible PR. After the switch, `horde <command>` prints Horde's result
     and `-Old` prints wezfleet's for one more phase. If the old side cannot run, shadow mode says why and
     exits 1, and the comparison is logged `inconclusive`. The alternative - a fleet instruction to run
     both commands - depends on memory, which D7 exists to replace.
   - **`tools/ShadowReport.ps1 <command> [-Date]`** prints the verdict for one working day from the log,
     by the rule below. Each switch PR quotes its output.
   - Tests first, in `test/test-shadow.ps1`, all against fixture logs and a stub old side under the
     suite's temp root: the log path honours `HORDE_ROOT`; each line validates against the schema; a
     field that differs between A and A' is volatile; a different instance is inconclusive; a difference
     no classifier claims is unexplained; a round-trip parse failure is `parse-unknown` and never
     skipped (SH-03); the report's qualifying and clean rules each with a passing and a failing fixture
     day.
   - No ledger of its own: it replaces nothing. The lessons it carries are cited in the command ledgers
     (cli-sessions draft L-018; core-projection L-053, "never a reconstruction").
   - Host-neutral: the one host-specific piece, the instance translation, is in `hosts/wezterm/`. The
     harness as a whole compares against wezfleet, which only exists beside the first host; with no
     wezfleet on PATH there is no old side, and a command on a machine with only another host runs in
     its switched mode. The harness is retired with wezfleet (step 6.4).

4. **The adoption ledger (step 3.2; decision 11).** PR: `adoption/capabilities.txt`,
   `adoption/ledger.txt`, `adoption/evidence.txt`, `adoption/implementers.txt`, `adoption/growth.txt`,
   `test/test-adoption.ps1`, and the harvest tool `tools/Adoption.ps1`.
   - **Why a top-level folder.** Any file under `planning/` other than `.md` or `.html` is itself a
     finding for the host-name ratchet (`tools/HostNames.ps1`, "WHAT IS NOT SCANNED"). `adoption/` is
     scanned like any other folder, so its data must not name a terminal either, and it does not need
     to: capabilities are named by what they do.
   - **The unit is a feature, not a command** (decision 5, F9). `adoption/capabilities.txt`, one line
     per capability, `<capability> | <old form> | <new form> | <why this is one unit>`:

     ```
     census             | wezfleet census                 | horde census        | who is in each live handle, and who owns them
     census-fix         | wezfleet census -Fix            | (none)              | repairs host tab titles; dropped from the projection (L-058)
     census-bare-shell  | wezfleet census, bare shell list | (none)             | reads host titles; dropped from the projection (L-058)
     census-unsent      | wezfleet census, UNSENT list    | (none)              | reads each handle's screen; dropped from the projection (L-059)
     census-disk        | wezfleet census, disk line      | (none)              | machine health, not a session fact (L-060)
     sessions           | wezfleet sessions               | horde sessions      | the running fleet, with or without a handle
     tree               | wezfleet tree                   | horde tree          | the hierarchy and its faults
     tell-target        | wezfleet tell <name>            | horde target <name> | turning a name into a session to message
     status             | wezfleet status                 | horde status        | step 3.4; what it maps to is decided there
     warchief-loop      | the Warchief's census and tree check | horde status loop | step 3.7
     ```

   - **`adoption/ledger.txt`**, one line per (role, capability): `<role> | <capability> | <system> |
     <since YYYY-MM-DD> | <evidence ids>`. Each role uses a capability from exactly one system. Roles
     are `core/roles` words; wezfleet's words are mapped on read. Seeded from the command logs (F3), all
     `wezfleet`: warchief census, tree and tell-target; orc census, sessions, tree and tell-target, and
     census-fix and census-unsent where the logs show them; goblin tell-target and status. Every seed
     line cites harvested evidence; a pair with no recorded use gets no line.
   - **`adoption/evidence.txt`**, harvested, normalized, never raw: `<id> | <role> | <capability> |
     <system> | <session id> | <first UTC> | <last UTC> | <uses> | <store> | <asOf>`. The harvest reads
     W6 read-only (`Read-HordeSharedText`) and the shadow logs, and stores tokens only, never command
     text: the text can hold secrets (wezfleet's `hooks/wf-cmdlog.cs:210` redacts only known key shapes),
     can name the terminal and would trip the ratchet, and is truncated at 160 characters anyway.
     Harvesting into the repository rather than reading W6 at test time is forced twice: loose logs are
     pruned after 14 days and capped at 512 KB (wezfleet `lib/Hooks.ps1:553-559`), and a test that reads
     the machine breaks core-projection L-051.
   - **What counts as a recorded use.** A W6 command-log line, or a shadow-log line with `trigger:
     use`, that (a) invokes the capability at a command position - start of command, or after `;`,
     `|`, `&&`, `(` or a newline, so a `grep` for the words or prose inside a `tell` message does not
     count; (b) was made by a session whose role is known in the projection (unknown is harvested as
     `unknown`, never guessed); (c) is not a test session - no `WEZFLEET_ROOT` or `HORDE_ROOT` override,
     not in an isolated host instance, not a Horde suite temp root; (d) falls inside the harvest window.
     Not a recorded use: a `sampler` comparison, a test suite, an implementer's own session, and the
     founder's own typing, which W6 does not log (a stated gap, not a zero).
   - **The rules, in `test/test-adoption.ps1`**, built the way wezfleet's `test_debug/test-ssot.ps1`
     is (a ratchet with names, failing on a new old-side entry and on a stale one, :17-23, :67-73) and
     reusing Horde's shrink-against-origin/main mechanism rather than inventing a third
     (`tools/HostNames.ps1` `Test-HordeHostShrink`, including its `[SKIP]` with a reason when there is
     no git or no `origin/main`):
     1. Well-formed: every role in `core/roles.json`, every capability in `capabilities.txt`, system
        `wezfleet` or `horde`, each (role, capability) once.
     2. No claim without recorded use (the 3.2 gate): every line cites an evidence id that exists and
        matches its role, capability and system; for a `horde` line the evidence's first use is on or
        after `since`. Assertion: "an entry claiming adoption with no recorded use fails".
     3. No evidence from the implementer: evidence whose session id is in `implementers.txt` does not
        count toward a `horde` line. D11 says "used by the Orcs for their real work", and
        self-attestation is the cheapest way to pass it.
     4. Old side shrink-only against `origin/main`: no new `wezfleet` line and no line moved from
        `horde` back to `wezfleet`, unless a line added to `adoption/growth.txt` since `origin/main`
        names that role, capability and date with a reason of four distinct words or more. Append-only,
        as `hosts/<name>/growth.txt` is.
     5. Not fiction: an old-side line whose role shows no use of that capability in the newest harvest
        window fails, judged against the committed harvest's `asOf`, never the clock, so the suite
        cannot go red overnight with no change.
     6. Controls, as at test-ssot.ps1:129-137: the parser finds a known line; a planted line with no
        evidence fails; a planted old-side addition fails the shrink check; an absent pattern is built at
        runtime.
   - What the gate cannot check, stated as `planning/ledger/README.md` does: that a harvested line is
     real. A reader can re-run the harvest against W6 and compare; an optional reality-check section
     re-harvests read-only when the stores exist and prints `[SKIP]` otherwise.
   - No ledger file: it ports the ratchet idea, not a wezfleet module; the PR cites test-ssot.ps1 at the
     lines above.

D. `horde census` (step 3.3) - first, by decision 3

5. **`horde census`, in shadow mode.** PR: the `fleet` command group (F8: `Get-HordeCommandGroups` lists
   only `about`, and a command naming an unlisted group is refused), `cli/commands/census.ps1`,
   `cli/Census.ps1`, `cli/shadow/census.ps1`, `planning/ledger/cli-census.md` (draft in Appendix B),
   `test/test-census.ps1`, `test/e2e/e2e-census.ps1`, `hosts/wezterm/test/e2e/e2e-census.ps1`.
   - The ledger's first commit is the adapted draft; the next commit is `test/test-census.ps1` with
     every assertion the ledger cites, red; then the implementation. The ledger gate goes green in the
     same PR, never before.
   - Output (decision 4, F4): the header starts `PANE`, each data row starts with its handle, the
     summary line reads `registry=N   pane-sessions=N   none=N` (source classes computed the way
     wezfleet's `census.ps1:26-27` does), and every data row comes before any diagnostic section,
     because callers read it through `Select-String '^PANE|^\d|registry='` and `Select-Object -First
     14` (measured in the command logs). `-Json` emits the view's handles section and validates against
     `schema/session-view.v1.json`; callers move to it when they choose. The word `PANE` is D12's
     host-neutral vocabulary (`hosts/wezterm/names.txt` excludes it on purpose), so keeping the anchor
     costs no host neutrality.
   - Rows come from the view's handles section, one per live handle, including handles no session
     answers (core-projection L-065). Handles sort numerically only when every handle is a number, and
     as text otherwise, because a handle is opaque (D12; draft L-014): a tmux or VS Code handle need not
     be an integer.
   - Tests that must exist first: every `test` entry of Appendix B, plus the two end-to-end scenarios.
     The host-neutral e2e runs `horde census` and `horde census -Json` with `HORDE_HOST=none` over a
     fixture store and asserts the unknown-handle output and exit 0. The host-bound e2e, in the isolated
     instance, spawns two panes, registers one session in a throwaway store, and asserts one row known,
     one row unknown, and the `registry=1` summary.
   - Shadow comparer (`cli/shadow/census.ps1`):
     - Old: the shipped `Get-WfFleetCensus`, `Get-WfUnclaimedUserSessions` and `Get-WfIdentityHealth` in
       the child; the command only prints what they return (`census.ps1:10, :31, :108`), and the text
       command is not run because its input-box scan reads every pane's screen. The `registry=N` line
       is computed once per comparison from those rows with `Group-Object source`, as `census.ps1:26-27`
       does.
     - Key: the handle as text, inside the recorded instance.
     - Compared per handle: claimed session (full id); source class (registry to W1, pane-sessions to
       X1, none to unknown or absent); owner; origin; window; title against `hostTitle`; SEEN as known or
       unknown only (P-10 gives three different age rules, so the value is not compared). Compared as
       sets: the handles; the founder-opened-and-unowned sessions; wezfleet duplicates against the
       `conversation-in-two-processes` fault; wezfleet's silent-hook flags against `registry-hook-silent`
       and the X1 completeness answer.
     - Allowances: P-04, P-08 to P-16, P-26, P-27. No census-specific id is needed beyond them and the
       shared SH-01 to SH-03.
     - Not compared (parity-2.3.md "Not compared"): title drift, bare shells, unsent text, disk space.
       They are the capabilities `census-fix`, `census-bare-shell`, `census-unsent`, `census-disk`, which
       stay `wezfleet` (below).
   - Host-neutral: the command reads only the view; the host-bound e2e is under `hosts/wezterm/`.

6. **Shadow, then switch.** The shadow starts when step 5 merges and `horde install` has been re-run.
   The fleet instruction is one line in the handoff: use `horde census` where you used `wezfleet census`
   (it prints the same thing during the shadow). The switch PR flips the mode constant, keeps `-Old`,
   and quotes `tools/ShadowReport.ps1 census` for the qualifying clean day. A new kind of difference
   found during the shadow gets a P-id, a classifier and a test in its own PR, and the day starts again.

7. **Adoption recorded.** A PR moves each (role, `census`) line that has qualifying post-switch evidence
   from `wezfleet` to `horde`, with the harvested evidence ids. **What stays on wezfleet** (decision 5,
   F9): `census-fix` (tab-title drift and its repair, used twice by `census -Fix`), `census-bare-shell`,
   `census-unsent` (`UNSENT` appears in a measured grep), and `census-disk`. Each stays until a host
   adapter provides it - title repair belongs with host decoration (step 7.2), bare shells and unsent
   text are host screen reads, and disk space belongs to a future startup or doctor command - so a
   caller that needs one of them keeps running `wezfleet census` for that, and the adoption ledger
   says so by name. Census is therefore only partly adopted in Phase 3, on purpose.

E. `horde sessions` (step 3.1)

8. **`horde sessions`, in shadow mode.** PR: `cli/commands/sessions.ps1`, `cli/Sessions.ps1`,
   `cli/shadow/sessions.ps1`, `planning/ledger/cli-sessions.md` (Appendix A), `test/test-sessions.ps1`,
   `test/e2e/e2e-sessions.ps1`, `hosts/wezterm/test/e2e/e2e-sessions.ps1`. May open as soon as census is
   in shadow; it does not wait for census's switch, because a shadow is bound to the calendar.
   - Defines "running" once, in `cli/Sessions.ps1`, and the S-01 classifier uses the same definition:
     the view has one session per sessionId any store knows, including Codex sessions (W8),
     registry-only sessions and retired records, while wezfleet lists only `~/.claude/sessions/*.json`
     (`lib/MailPump.ps1:56-66`).
   - The filter is a literal substring over id, name and label (draft L-008, L-009), never a wildcard
     pattern.
   - Tests that must exist first: every `test` entry of Appendix A and the two end-to-end scenarios
     (host-neutral: `HORDE_HOST=none`, every pane `?`, the footer saying so; host-bound: one session in
     a pane and one with none, reading a handle and `-`).
   - Shadow comparer: old is the shipped command's text, `wezfleet.ps1 sessions`, run in the child,
     because the pane map and labels are built inline in the command (`sessions.ps1:37-63`) and calling
     library functions would reconstruct them. Each row is parsed with the format at `sessions.ps1:72`
     and re-formatted with the same format string; a row that does not round-trip is `parse-unknown`
     (SH-03), because a label longer than five characters moves the columns. Key: the 8-character
     SESSION column plus PID (the text has no full id). Compared: the key sets; per row label, status,
     pane (number, `-` or `?`), pid and name; the footer's no-pane count, unknown marker, total and busy;
     the exit code. Allowances: P-01 to P-07, P-27, and S-01 to S-03.
   - Host-neutral: the pane column prints the view's handle answer, whatever host produced it.

9. **Shadow, then switch - with the Warchief as the source of use** (decision 3). `wezfleet sessions`
   has three recorded uses ever, so a working day will not happen on its own. The Warchief adds `horde
   sessions` to its status loop; each call is a `trigger: use` comparison, because the Warchief acts on
   the output. The working-day rule still needs two distinct sessions, so the Warchief's handoff asks one
   orc to read its roster through `horde sessions` for the shadow's duration. Switch PR as in step 6.

10. **Adoption recorded:** (warchief, sessions) and each orc line with qualifying evidence move to
    `horde`.

F. `horde tree` (step 3.5)

11. **`horde tree`, in shadow mode.** PR: `cli/commands/tree.ps1`, `cli/Tree.ps1`,
    `cli/shadow/tree.ps1`, `planning/ledger/cli-tree.md` (Appendix C), `schema/fleet-tree.v1.json` for
    `-Json`, `test/test-tree.ps1`, and the two end-to-end scenarios.
    - Draws every non-retired session exactly once (draft L-009): children of an unassigned node, members
      of a parent loop, and sessions whose parent is gone are all drawn, which wezfleet's tree never does
      (read-found: only masters are recursed from, the unassigned list is flat, loop members are neither
      unassigned nor orphans).
    - Roles print in Horde's vocabulary through `core/roles`; fault kinds are the view's.
    - Advice names no wezfleet command (draft L-014): there is no Horde command that assigns a parent
      until step 3.8.
    - Tests that must exist first: every `test` entry of Appendix C; the tree suite reads only its
      temporary copy (draft L-020: test records reaching the live registry are how the Warchief found
      strays by reading tree).
    - Shadow comparer: old is the shipped `Get-WfHierarchy`, `Get-WfHierarchyFindings` and
      `Format-WfRecordPane` in the child, plus once per comparison the shipped `wezfleet.ps1 tree` text,
      only to count drawn rows per depth - the count is what exposes T-03, which the objects alone do not
      show. Key: claudeSessionId. Compared: the member set; role, mapped through `core/roles`; the parent
      edge; the displayed pane; the unassigned and orphan sets; finding kinds mapped (no-master to
      no-warchief, two-masters to two-warchiefs, orchestrator-not-under-master to
      orc-not-under-warchief, parent-missing to parent-missing or parent-retired). Allowances: P-23 to
      P-27, T-01 to T-03.
    - Host-neutral: tree reads no host at all beyond the view's handle answer (draft L-001: drawing the
      tree calls no host verb).

12. **Shadow, then switch.** The Warchief (11 recorded uses) and orc D (5) are the natural users; the
    master handoff skill reads scope names from "ROSTER.md (or `wezfleet tree`)", so the handoff line
    changes to `horde tree` at the shadow's start.

13. **Adoption recorded:** (warchief, tree) and (orc, tree) as evidence allows.

G. Message target resolution, the naming half of `tell` (step 3.6)

14. **`core/Target.ps1` and `horde target <name>`, in shadow mode.** PR: `core/Target.ps1`,
    `cli/commands/target.ps1`, `cli/Target.ps1`, `cli/shadow/target.ps1`, `schema/target-result.v1.json`,
    `planning/ledger/core-target.md` (Appendix D), `test/test-target.ps1`, the two end-to-end scenarios.
    - Resolves who, not where: a name is a label (case-sensitive), a full id, a unique id prefix of eight
      or more hex characters (any case), or a fleet id. It returns a result object and never exits
      (draft L-023); the CLI maps a refusal to exit 1 with the reason and a malformed name to exit 2.
    - Decision 6: a name that is both a lane fleet id in the caller's own run and another session's
      label is ambiguous, with both candidates named - where wezfleet silently picks the run
      (`lib/Run.ps1:54-62`).
    - Decision 7: at first, a name whose session has no verified handle is refused, as wezfleet does.
      "Verified" means the view answers the handle as known and live in the current host instance,
      which is the instance rule the projection already applies (core-projection L-011, L-022). An
      unknown handle list refuses every name with the host's reason.
    - Horde does not type and does not deliver. Delivery - wezfleet's exit codes 0, 2, 3, 4, 5 - is not
      ported (migration step 6.1). Adoption of `tell-target` means a caller resolves the name with
      `horde target` and sends through platform messaging to the messaging address it returns.
    - Tests that must exist first: every `test` entry of Appendix D.
    - Shadow comparer: old is the shipped `Resolve-WfRunForSession` then `Resolve-WfFleetTarget` in the
      child - never `Resolve-WfSessionRowOrFail` (it exits, `Run.ps1:57, :68`) and never `Invoke-WfTell`
      (it delivers). For a lane caller the child sets `WEZFLEET_RUN_DIR` to the caller's run, taken
      from the W6 path `runs/<id>/sessions/<fleet>/cmdlog.txt`, reproducing the run-first path. Key:
      (target string, caller session id). Compared: the outcome class (resolved, ambiguous,
      unknown-name, refused-unverified-handle); the resolved session id; the candidate set when
      ambiguous. The handle is logged, not compared. The warnings are not compared: wezfleet's two are
      defective (issues #18 and #19, below), so a difference is guaranteed and would say nothing about
      Horde. wezfleet's refusal reasons are text, and one of them names the terminal ("wezterm did not
      answer", `lib/Registry.ps1:733`); the table mapping reason text to outcome class is host
      knowledge and lives in `hosts/wezterm/Shadow.ps1`. Allowances: P-07 (here a difference is a Horde
      bug: both sides must exclude retired records), P-22, P-27, G-01, G-02.
    - Two triggers: a real `horde target` call is `use`. Every target string used that day by a real
      `wezfleet tell` (623 in the logs, labels dominating: M 202, F 139, B 69, A 65, E 38, D 23) is
      replayed with its caller as `sampler` - coverage of real names, never counted toward the use
      minimum (decision 8).
    - Host-neutral: core/Target.ps1 reads handle answers from the view, never a host.

15. **Shadow, then switch**, as in step 6.

16. **Adoption recorded** for each role whose sessions now resolve through `horde target`.

17. **Later, separate PR: relax the verified-handle requirement** (decision 7). Only after the target
    shadow logs are clean; the PR changes draft L-013, L-014 and L-017 to the research's original
    form (a session with no handle still resolves to its messaging address; an unknown handle list does
    not stop a name resolving), and its own shadow classifies the new difference against wezfleet. It
    is not part of step 3.6's gate.

H. The rest of Phase 3, planned when reached

- **3.4 `horde status`.** wezfleet's `status` is run-scoped and runs `Invoke-WfPump` before
  `Get-WfRunSnapshot` in every mode, so it writes before it reads (P-20); a shadow must call
  `Get-WfRunSnapshot` and never the command. Horde's `status` is fleet-wide, so what corresponds to what
  is itself the first decision of that step.
- **3.7 the Warchief's status loop.** Last, because the fleet depends on it. The measured shapes are
  the Warchief's composite checks (`wezfleet tree; ...; wezfleet census; ...`); by then its census, tree
  and sessions comparisons already run from the Warchief's session, which is why it has to come last.
- **3.8 the record writer.** Unchanged from the migration table. Its research notes (wezfleet `own`
  writes both `owner` and `parent`; `Set-WfSessionParent` refuses self, missing, retired and loop
  parents; `own` finds a row by pane, claude id or fleet id but not label) go into its ledger.

## The working-day rule (decision 8)

A **working day** is one America/New_York calendar date: wezfleet's commits carry -04:00, and a
founder's day spans two UTC dates. The zone is a parameter of `tools/ShadowReport.ps1` with that
default, and every report prints the zone it used.

A day **qualifies** when all of these hold:
- at least 5 comparisons with `trigger: use`, from sessions not in `adoption/implementers.txt`;
- from at least 2 distinct sessions;
- the first and last at least 6 hours apart;
- none of the 5 is `inconclusive`;
- wezfleet's commit constant through the day, or each change logged.

A qualifying day is **clean** when zero of its comparisons has an `unexplained` difference. A new kind
of difference found during a day gets an allowance id, a classifier and a test, and the day starts
again; it is never waived for the rest of the day. A `sampler` comparison may add coverage but never
counts toward the minimum (D11: use by the real fleet is the one test that cannot be passed by testing
the wrong thing). One clean qualifying day is the switch gate for each command.

## Shadow allowances beyond P-01..P-27

P-01 to P-27 are in `planning/parity-2.3.md` on `feature/core-projection`. The research found the
following differences a shadow will see on day one that no P-id covers (F5). Each gets its classifier
and a test in the PR that adds its command's comparer, before that command's shadow starts.

| id | command | the difference | why it is explained |
|---|---|---|---|
| SH-01 | all | a field differs between wezfleet's two reads (A and A') | timing, not disagreement; busy and idle flip in seconds. Counted `volatile`, neither clean nor unexplained. |
| SH-02 | all | the host instance differs between the old and new reads | the two sides looked at different terminals; the comparison is `inconclusive` and never counts toward a day |
| SH-03 | text comparers | a wezfleet text row does not round-trip through its own format string | the parse cannot be trusted for that row; it is `parse-unknown`, reported, never skipped |
| S-01 | sessions | the population: Codex, registry-only and retired sessions are in the view, not in wezfleet's list | wezfleet reads only Claude control files (`lib/MailPump.ps1:56-66`); the classifier uses the one definition of "running" in `cli/Sessions.ps1` |
| S-02 | sessions | the filter matches a label in Horde and not in wezfleet | wezfleet matches id and name only (`sessions.ps1:67`); labels are the names people use (draft L-009) |
| S-03 | sessions | a filter holding `[`, `]`, `*` or `?`: wezfleet throws (exit 1) or matches as a wildcard | wezfleet uses `-like` (`sessions.ps1:67`, measured 2026-09-30); Horde matches literally (draft L-008) |
| T-01 | tree | a parent loop is invisible in wezfleet and drawn plus reported as a fault in Horde | wezfleet has no loop check (`lib/Hierarchy.ps1:52-58, :70-110`); draft L-010 |
| T-02 | tree | the unassigned set: wezfleet's comment says origin=user with no parent, its code checks role and parent only | Horde states the rule once (draft L-008) |
| T-03 | tree | sessions wezfleet never draws: children of an unassigned node, and sessions whose parent is gone | only masters are recursed from (`commands/tree.ps1:20-47`); draft L-009, L-012 |
| G-01 | target | wezfleet refuses because the handle's title fell back to a bare shell; Horde resolves | the bare-shell test reads host titles, dropped from the projection (L-058) and kept on wezfleet by decision 5 until a host adapter provides it |
| G-02 | target | a lane fleet id in the caller's run that is also another session's label: wezfleet picks the run, Horde reports ambiguous | decision 6, deliberate |

Research had G-01 as every pane-only refusal. Decision 7 narrows it: Horde also refuses a target with
no verified handle, so a refusal because the host did not answer, the handle is not the registry's, or
the handle is closed must now agree, and a disagreement there is `unexplained`.

## Filed on wezfleet, not fixed here (decision 10)

Horde reads wezfleet and never writes to it, so these two `tell` defects are wezfleet's to fix:

- **YedPool/wezfleet#18**, "tell: hierarchy warning reads CLAUDE_SESSION_ID, which nothing sets".
  `commands/tell.ps1:123` reads `$env:CLAUDE_SESSION_ID`; measured 2026-09-30, it is empty in a live
  session where `CLAUDE_CODE_SESSION_ID` is set, and it appears nowhere else in lib, commands or hooks.
  `test_debug/test-hierarchy.ps1:91-100` calls `Test-WfMayMessage` directly, so no test covers the path
  `tell` takes. Horde's counterpart is core-target draft L-021, tested through the command.
- **YedPool/wezfleet#19**, "tell: cross-owner warning compares a label with a fleet id".
  `lib/Registry.ps1:1070-1076` compares the stored `owner` (a label written by `own`) with
  `WEZFLEET_SESSION_ID` (a fleet id); `test_debug/test-registry.ps1:142-148` uses one word for both,
  which hides it. Read-found, unmeasured in live use. Horde's counterpart is core-target draft L-022.

The target shadow does not compare warnings while either issue is open (step 14).

## Host neutrality, step by step (D12)

| step | what could name a terminal | where it lives |
|---|---|---|
| 1 host discovery | nothing: core enumerates `hosts/*/HostRead.ps1` and never spells a host | `core/Hosts.ps1` |
| 2 read adapter | the list command, the socket pin, captured fixtures, the isolated e2e | `hosts/wezterm/` |
| 3 shadow harness | the instance-id translation between wezfleet and the adapter | `hosts/wezterm/Shadow.ps1` |
| 4 adoption ledger | nothing: capabilities are named by what they do; evidence stores no command text | `adoption/`, scanned |
| 5 census | nothing in the command (`PANE` is host-neutral); real-pane e2e | `hosts/wezterm/test/e2e/` |
| 8 sessions | nothing in the command; real-pane e2e | `hosts/wezterm/test/e2e/` |
| 11 tree | nothing: tree calls no host verb | - |
| 14 target | wezfleet's refusal reason text, which names the terminal | `hosts/wezterm/Shadow.ps1` |
| 7 census extras | title repair, bare shells, unsent text: future host capabilities | a later `hosts/<name>/` adapter, never core |

What a second host (tmux, psmux, Ghostty, VS Code) needs to join, with no engine change: a
`hosts/<name>/HostRead.ps1` declaration answering the same two script blocks, passing
`test/lib/HostReadConformance.ps1` with its own fixtures, and its own isolated e2e (for tmux a private
server socket with `-L`, per D12). A host with no handles at all answers a known empty list, and every
command above already prints that case. Handles are opaque text everywhere; census sorts numerically
only when every handle is a number. The shadow harness needs nothing from a new host: it exists only
where wezfleet does.

## Ledgers: who carries what (F10)

The `core-projection` ledger's header already lists wezfleet's `commands/sessions.ps1`, `census.ps1`
and `tree.ps1` under `replaces`. The split: `core-projection` keeps the data rules (which store answers,
the guards, the faults); `cli-sessions`, `cli-census`, `cli-tree` and `core-target` carry what each
command shows, what its options do, its exit codes, and what callers rely on. Each draft names the
projection entries it relies on instead of repeating them. The gate does not check overlap between
ledgers (`planning/ledger/README.md`, "What the gate does not check"); review does.

The drafts below follow `planning/ledger/README.md` and the research's harvest, adapted to the
decisions and to the file layout above (logic in `cli/<Name>.ps1`, comparers in `cli/shadow/`,
the harness in `cli/Shadow.ps1`). Assertions are at least three words and contain no double quote. Each
is copied into `planning/ledger/` by its command's first PR, together with the suite that makes it pass.

## Appendix A: draft `planning/ledger/cli-sessions.md` (steps 8-10)

Adapted from the research: comment dispositions point at `cli/Sessions.ps1` (logic beside the declaration) and L-018 at `cli/Shadow.ps1`.

```
module: cli/sessions
replaces: YedPool/wezfleet commands/sessions.ps1 (Invoke-WfSessions), lib/Hosts.ps1 (Get-WfFleetSessions, the rows it hands the printer), lib/Commands.ps1 (the sessions entry)
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

## What each source held

- comments: commands/sessions.ps1:5-25, :35-36, :51-55, :65, :79-81; lib/Hosts.ps1:163-182; lib/MailPump.ps1:36-54.
- history: 27cfafe (2026-09-29) is the whole history of commands/sessions.ps1 and test_debug/test-fleet-sessions.ps1
  (git log --follow); pickaxe for Get-WfFleetSessions adds only e63c859, which is planning prose.
- pull requests: none. `gh pr list --repo YedPool/wezfleet --state all --json files` over all 17 pull requests: none
  touched commands/sessions.ps1, lib/Hosts.ps1 or lib/MailPump.ps1. PR #12 added the planning document that records
  the measured output.
- docs: planning/wezfleet-ssot-multi-backend-2026-09-29.md:486-519 and :640-655; tasks/lessons.md:571-574.
- tests: test_debug/test-fleet-sessions.ps1, 20 assertions.
- carried elsewhere, not repeated here: which store answers pane, label, status and pid, and every guard on them, is
  core/projection (planning/ledger/core-projection.md L-004, L-005, L-007, L-008, L-009, L-010) and the parity
  differences P-01 to P-07 and P-27 (planning/parity-2.3.md).

### L-001 sessions answers what is running; census answers what is in the terminal
- source: YedPool/wezfleet commands/sessions.ps1:23-25 "census still answers what is in my terminal; this answers what is running"; lib/Commands.ps1:51
- disposition: comment
- where: cli/Sessions.ps1 :: "answers what is running, not what a terminal shows"

### L-002 Control files that cannot be read are unknown, never an empty fleet
- source: YedPool/wezfleet commands/sessions.ps1:30-32; lib/MailPump.ps1:53-54 "An empty map means UNKNOWN"; horde planning/parity-2.3.md P-06
- disposition: test
- where: test/test-sessions.ps1 :: "unreadable control files print unknown, never an empty fleet"

### L-003 The pane column has three values and prints them differently
- source: YedPool/wezfleet lib/Hosts.ps1:179-182; commands/sessions.ps1:87-89; test_debug/test-fleet-sessions.ps1:68-69 "every pane reads '?' rather than '-'"
- disposition: test
- where: test/test-sessions.ps1 :: "an unknown pane prints a question mark and an absent one a dash"

### L-004 How many sessions have no pane is said, not left for the reader to count
- source: YedPool/wezfleet commands/sessions.ps1:79-86 "THE NUMBER THAT MATTERS FOR THE FOUNDER'S ASK"; 27cfafe
- disposition: test
- where: test/test-sessions.ps1 :: "the footer counts sessions outside every host"

### L-005 Labels come from the session record; a census filtered by owner has none
- source: YedPool/wezfleet commands/sessions.ps1:51-55; 27cfafe "the column went silently blank rather than wrong - the harder kind to notice"
- disposition: test
- where: test/test-sessions.ps1 :: "the label column is filled from the label answer"

### L-006 Rows are computed apart from printing, so a paneless session is testable without an editor
- source: YedPool/wezfleet lib/Hosts.ps1:176-177; test_debug/test-fleet-sessions.ps1:84-87
- disposition: test
- where: test/test-sessions.ps1 :: "the rows are built from a view passed in, not read from the box"

### L-007 The command must reach the projection, proven by running the command
- source: YedPool/wezfleet c850e7b; tasks/lessons.md:449-481 "a mechanism with no callers"; test_debug/test-fleet-sessions.ps1:84-85 proved it only by matching source text; horde planning/ledger/core-projection.md L-052
- disposition: test
- where: test/test-sessions.ps1 :: "horde sessions reaches the projection through the command"

### L-008 A filter is a literal substring, never a wildcard pattern
- source: YedPool/wezfleet commands/sessions.ps1:67 (-like "*$Target*"); measured 2026-09-30 on PowerShell 5.1: "abc" -like "*[*" throws WildcardPatternException and "a1b" -like "*[1]*" is True; tasks/lessons.md:529 "-like reads [ as a wildcard"
- disposition: test
- where: test/test-sessions.ps1 :: "a filter holding brackets matches literally and never throws"

### L-009 The filter matches the label too
- source: YedPool/wezfleet commands/sessions.ps1:67 matches sessionId and name only, while the label is the name people use (623 tell targets measured 2026-09-30, mostly labels)
- disposition: test
- where: test/test-sessions.ps1 :: "a filter matches a label as well as an id or a name"

### L-010 Labelled sessions are listed first, then by label, then by name
- source: YedPool/wezfleet commands/sessions.ps1:73
- disposition: test
- where: test/test-sessions.ps1 :: "labelled sessions are listed before unlabelled ones"

### L-011 Busy is highlighted, and busy is a value the text also carries
- source: YedPool/wezfleet commands/sessions.ps1:74 (colour only) and :90 (the busy count)
- disposition: comment
- where: cli/Sessions.ps1 :: "colour repeats the status column and never replaces it"

### L-012 Every line reaches the success stream, so it can be captured in-process
- source: YedPool/wezfleet commands/sessions.ps1:31-90 prints only with Write-Host; callers capture it through %USERPROFILE%\bin\wezfleet.cmd (Get-Command measured 2026-09-30: Application)
- disposition: test
- where: test/test-sessions.ps1 :: "every line of output reaches the success stream"

### L-013 Nothing matching and nothing known are successes reported by returning, never by exit
- source: YedPool/wezfleet commands/sessions.ps1:32, :69, :92 (exit 0 inside the body); horde horde.ps1 header "EXIT CODES ARE 0, 1 OR 2"
- disposition: test
- where: test/test-sessions.ps1 :: "no match returns with exit 0 and prints why"

### L-014 Agents get a JSON form, validated, instead of parsing columns
- source: YedPool/wezfleet lib/Commands.ps1:50 (no -Json); command logs 2026-09-15..30 show callers reading this family of commands through Select-String and Select-Object -First
- disposition: test
- where: test/test-sessions.ps1 :: "sessions json validates against the session view schema"

### L-015 The population is every running session, not only Claude control files
- source: YedPool/wezfleet lib/MailPump.ps1:56-66 reads ~/.claude/sessions only, so Codex sessions never appear; horde schema/session-view.v1.json description "One session per sessionId any store knows" (feature/core-projection)
- disposition: test
- where: test/test-sessions.ps1 :: "a running codex session is listed beside claude ones"

### L-016 A session that removed its control file is not listed as running, even if its process survives
- source: YedPool/wezfleet planning/wezfleet-ssot-multi-backend-2026-09-29.md:640-655 (pid 5616 survived every kill; the session deregistered and sessions dropped it)
- disposition: test
- where: test/test-sessions.ps1 :: "a deregistered session is not listed as running"

### L-017 An unavailable host must print unknown panes, never a fleet that left its terminal
- source: YedPool/wezfleet planning/wezfleet-ssot-multi-backend-2026-09-29.md:512-519 (a spike cleared the mux socket, read 0 panes, and every session read '-'); horde planning/parity-2.3.md P-04, P-27
- disposition: test
- where: test/test-sessions.ps1 :: "an unavailable host port prints every pane as unknown"

### L-018 The shadow compares against the shipped command, never a rebuilt one
- source: YedPool/wezfleet tasks/lessons.md:571-574 "When wezfleet sessions and my hand-rolled equivalent disagreed, the command was right both times"
- disposition: comment
- where: cli/Shadow.ps1 :: "runs the shipped wezfleet command in a child process"

### L-019 Status and pid are the session's own report, checked against the process it describes
- source: YedPool/wezfleet test_debug/test-fleet-sessions.ps1:52-54; lib/MailPump.ps1:62-63; horde planning/parity-2.3.md P-05
- disposition: test
- where: test/test-sessions.ps1 :: "the status column is unknown when the process is not the one described"
```

## Appendix B: draft `planning/ledger/cli-census.md` (steps 5-7)

Adapted: comment dispositions point at `cli/Census.ps1`; L-018 to L-021 name the adoption capability each dropped feature stays on (decision 5); L-026 added for `-Json` (decision 4).

```
module: cli/census
replaces: YedPool/wezfleet commands/census.ps1 (Invoke-WfCensus), lib/Commands.ps1 (the census entry), and the printing of lib/Registry.ps1 Get-WfUnclaimedUserSessions and Write-WfIdentityHealth
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

## What each source held

- comments: commands/census.ps1:5-9, :19, :28-30, :38-45, :65-67, :78-88, :106-107, :110-112; lib/Registry.ps1:809-824,
  :830-832, :862-870, :1015-1016, :1191-1198.
- history: git log --follow commands/census.ps1: b1770fb, d811106, 0e1c75a, 6fe4e02, 71afcb0. Pickaxe Invoke-WfCensus
  and Get-WfFleetCensus before the split: 10b1782, c850e7b, 50a6944; and e36ea8e (two invented functions corrected).
- pull requests: none touched commands/census.ps1 or lib/Registry.ps1 (gh pr list, 17 pull requests, --json files).
- docs: planning/registry-design.md:64, :112, :132, :147; planning/BUG-2026-09-15-restart-pane-identity.md:6, :18-20,
  :94, :111; planning/BUG-2026-09-15-unsent-input-box.md:94; planning/wezfleet-v2-architecture.md:28, :100-111, :752;
  tasks/lessons.md:418-447; README.md:110.
- tests: test_debug/test-registry.ps1:92-172; test-instance.ps1:110-128; test-presentation.ps1:96-105;
  test-disk-space.ps1:102-106; test-input-box.ps1:382-402; test-delivery-callers.ps1:156.
- carried elsewhere, not repeated: the data rules, meaning which store answers each handle and every guard, are
  core/projection L-004 to L-006, L-011 to L-018, L-021, L-022, L-024 to L-027, L-042 to L-046, L-049, L-063 to L-065,
  and P-04, P-08 to P-16, P-26 and P-27. Title drift, bare shells, unsent text and disk space are dropped there
  (L-058, L-059, L-060); they are repeated below only to record that they stay on wezfleet in the adoption ledger.

### L-001 One row per live handle, including handles nothing knows
- source: YedPool/wezfleet lib/Registry.ps1:835-878; test_debug/test-registry.ps1:106 "a pane nothing knows about is reported as UNKNOWN, not omitted"; 10b1782 mutation "census omitting unknown panes"
- disposition: test
- where: test/test-census.ps1 :: "a handle no session answers is printed as unknown"

### L-002 Every row says which store answered it
- source: YedPool/wezfleet lib/Registry.ps1:822-823 "a census that cannot say how confident it is invites the reader to treat a guess as a fact"; planning/wezfleet-v2-architecture.md:752
- disposition: test
- where: test/test-census.ps1 :: "every row names the store its session came from"

### L-003 The summary counts rows per source in name=count form, because callers grep it
- source: YedPool/wezfleet commands/census.ps1:26-27; command logs measured 2026-09-30: Select-String -Pattern '^PANE|^\d|registry=' and '^13 |^PANE|registry=|UNSENT'
- disposition: test
- where: test/test-census.ps1 :: "the summary line counts rows per source as name equals count"

### L-004 The header starts with the handle column and each row starts with its handle
- source: YedPool/wezfleet commands/census.ps1:14, :23; command logs measured 2026-09-30 anchor on ^PANE and ^\d
- disposition: test
- where: test/test-census.ps1 :: "the header and every data row start with the handle column"

### L-005 Data rows come before every diagnostic section
- source: command logs measured 2026-09-30: wezfleet census 2>&1 | Select-Object -First 14 (and 16, 20, 25, 30, 32, 40, 45); YedPool/wezfleet commands/census.ps1:13-27 before :28-123
- disposition: test
- where: test/test-census.ps1 :: "every data row is printed before any diagnostic section"

### L-006 An unreadable handle list prints unknown, never no live panes
- source: YedPool/wezfleet commands/census.ps1:11; horde planning/parity-2.3.md P-16; horde planning/ledger/core-projection.md L-006
- disposition: test
- where: test/test-census.ps1 :: "an unknown handle list prints unknown, not no live panes"

### L-007 An age that cannot be measured prints a dash, never a number
- source: YedPool/wezfleet commands/census.ps1:19-20; lib/Registry.ps1:868-870; test_debug/test-registry.ps1:115, :128 (with its control)
- disposition: test
- where: test/test-census.ps1 :: "an unknown activity age prints a dash"

### L-008 The age column is last activity; it once silently meant first seen
- source: YedPool/wezfleet planning/wezfleet-v2-architecture.md:100-111 "The field named lastSeen records FIRST seen"; lib/Registry.ps1:862-876; horde planning/parity-2.3.md P-10
- disposition: test
- where: test/test-census.ps1 :: "the age column reads last activity, not a record write time"

### L-009 Sessions the founder opened that nobody owns are called out, not left in a column
- source: YedPool/wezfleet commands/census.ps1:28-37; lib/Registry.ps1:1190-1202; 10b1782; test_debug/test-registry.ps1:169, :172 (the control: once assigned it stops being flagged)
- disposition: test
- where: test/test-census.ps1 :: "founder sessions nobody owns are listed after the table"

### L-010 The owner column prints the derived owner, not an empty stored one
- source: YedPool/wezfleet commands/census.ps1:17 prints (unowned) for an empty stored owner; horde planning/parity-2.3.md P-11 (9 records agreed, 7 differed, all 7 empty where founder is derived)
- disposition: test
- where: test/test-census.ps1 :: "the owner column prints the derived owner"

### L-011 A missing origin is shown as missing, not as the word unknown
- source: YedPool/wezfleet lib/Registry.ps1:858; horde planning/parity-2.3.md P-12; horde planning/ledger/core-projection.md L-046
- disposition: test
- where: test/test-census.ps1 :: "a missing origin prints a dash"

### L-012 The session column is the first eight characters of the id
- source: YedPool/wezfleet commands/census.ps1:16
- disposition: test
- where: test/test-census.ps1 :: "the session column prints eight characters of the id"

### L-013 Titles are cut so a row stays one line
- source: YedPool/wezfleet commands/census.ps1:21-22 (44 characters)
- disposition: comment
- where: cli/Census.ps1 :: "titles are cut so each row stays one line"

### L-014 Handles sort numerically when they are numbers, and as text otherwise
- source: YedPool/wezfleet lib/Registry.ps1:835 sorts by [int]; horde core/HostPort.ps1:10-12 (feature/core-projection) makes a handle opaque text, per D12
- disposition: test
- where: test/test-census.ps1 :: "handles sort numerically when every handle is a number"

### L-015 Identity faults print only when present, through one printer that status also uses
- source: YedPool/wezfleet lib/Registry.ps1:1014-1016 "so census and startup cannot drift into saying different things about the same fault"; commands/census.ps1:106-108
- disposition: test
- where: test/test-census.ps1 :: "faults print through the one fault formatter"

### L-016 A side check that fails is said, not swallowed
- source: YedPool/wezfleet commands/census.ps1:68-76, :108, :113-123 each wrap a check in try with an empty catch
- disposition: test
- where: test/test-census.ps1 :: "a fault answer that is unknown is printed with its reason"

### L-017 Unknown panes come with a reason that names the missing writer
- source: YedPool/wezfleet commands/census.ps1:99-104 (advice naming wezfleet registry status); horde fault registry-hook-silent in schema/session-view.v1.json (feature/core-projection)
- disposition: comment
- where: cli/Census.ps1 :: "a handle nobody recorded is explained by the fault list"

### L-018 Tab titles that name the wrong pane, and their repair with -Fix
- source: YedPool/wezfleet commands/census.ps1:38-63; 50a6944; d811106 (whole-string comparison would have truncated good titles)
- disposition: dropped
- reason: horde census writes nothing and reads no tab title rules; title repair belongs to a host decoration adapter (step 7.2), and census -Fix stays on wezfleet as the adoption capability census-fix until one exists (decision 5) (horde core-projection ledger L-058).

### L-019 A pane showing a bare shell after its session exited is reported, not acted on
- source: YedPool/wezfleet commands/census.ps1:78-97; d811106
- disposition: dropped
- reason: it reads host pane titles, which are host presentation; it stays on wezfleet as the adoption capability census-bare-shell until a host adapter carries it (decision 5; horde core-projection ledger L-058).

### L-020 Unsent text sitting in an input box is listed
- source: YedPool/wezfleet commands/census.ps1:110-123; 6fe4e02; planning/BUG-2026-09-15-unsent-input-box.md:94
- disposition: dropped
- reason: it reads each pane's screen for typed delivery safety; Horde does not type, and the feature stays on wezfleet as the adoption capability census-unsent (decision 5; horde core-projection ledger L-059).

### L-021 Free disk space is reported because a full drive broke networking box-wide
- source: YedPool/wezfleet commands/census.ps1:64-76; 71afcb0
- disposition: dropped
- reason: machine health is not a session fact and belongs to a future startup or doctor command; it stays on wezfleet as the adoption capability census-disk (decision 5; horde core-projection ledger L-060).

### L-022 census exists because every consumer invented its own and got identity wrong
- source: YedPool/wezfleet commands/census.ps1:5-9 "cost one orchestrator three collisions in a day"; lib/Registry.ps1:814-815
- disposition: comment
- where: cli/Census.ps1 :: "one census so no caller rebuilds identity rules"

### L-023 census rows come from the view's handles section, one per handle
- source: horde planning/parity-2.3.md P-08 and the lead's decision 3; horde planning/ledger/core-projection.md L-065
- disposition: test
- where: test/test-census.ps1 :: "census prints one row per handle in the view"

### L-024 The command must reach the projection, proven by running the command
- source: YedPool/wezfleet c850e7b; tasks/lessons.md:449-481; test_debug/test-delivery-callers.ps1:156 proved it by reading the function body; horde planning/ledger/core-projection.md L-052
- disposition: test
- where: test/test-census.ps1 :: "horde census reaches the projection through the command"

### L-025 A read command writes nothing, and the proof runs it against a copied store
- source: YedPool/wezfleet commands/census.ps1:44-45 "Renaming twenty tabs as a side effect of looking at them is a surprise"; 50a6944 tripwire on Set-WfTabTitle
- disposition: test
- where: test/test-census.ps1 :: "running census leaves every store byte identical"

### L-026 Agents get a JSON form beside the text anchors, and move to it when they choose
- source: command logs measured 2026-09-30 (callers grep ^PANE, ^\d and registry=); decision 4 of 2026-09-30 keeps the anchors and adds -Json
- disposition: test
- where: test/test-census.ps1 :: "census json validates against the session view schema"
```

## Appendix C: draft `planning/ledger/cli-tree.md` (steps 11-13)

Adapted: L-018 points at the tree comparer `cli/shadow/tree.ps1`; L-019 is carried in `cli/Tree.ps1` rather than in an adoption line, which would break the day that line moves to `horde`.

```
module: cli/tree
replaces: YedPool/wezfleet commands/tree.ps1 (Invoke-WfTree), the display use of lib/Hierarchy.ps1 (Get-WfHierarchy, Get-WfHierarchyFindings) and lib/Common.ps1 (Format-WfRecordPane)
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

## What each source held

- comments: commands/tree.ps1:5-9, :38-39, :50-52; lib/Hierarchy.ps1:1-24, :36-39, :49-51, :77-78, :100-102, :113-117;
  lib/Common.ps1:598-601.
- history: git log --follow commands/tree.ps1: b1770fb, 0e1c75a; pickaxe Invoke-WfTree: 4eba288; lib/Hierarchy.ps1:
  4eba288 only; 1e8837a made own write the parent edge tree draws.
- pull requests: none touched commands/tree.ps1 or lib/Hierarchy.ps1 (gh pr list, 17 pull requests, --json files).
- docs: planning/BUG-2026-09-15-restart-pane-identity.md:72 "display only: tree (3 sites), master (3 sites)"; horde
  planning/migration-plan.html section 2 correction (Hierarchy.ps1:85); README.md:109;
  ~/.claude/skills/master-orchestrator-handoff/SKILL.md:67-68 (scope names from ROSTER.md or wezfleet tree).
- tests: test_debug/test-hierarchy.ps1 (24 assertions); test-instance.ps1:239-240; strays M found reading tree:
  test-delivery.ps1:68-69, test-registry-hook.ps1:183, :303, test-safe-kill.ps1:58.
- carried elsewhere, not repeated: the fault rules are core/projection L-035 to L-040 and L-072, and P-24, P-25.

### L-001 Looking at the tree costs nobody a message
- source: YedPool/wezfleet commands/tree.ps1:5-9; lib/Hierarchy.ps1:11-15; 4eba288; test_debug/test-hierarchy.ps1:112, :116 (a tripwire and its control)
- disposition: test
- where: test/test-tree.ps1 :: "drawing the tree calls no host verb at all"

### L-002 A child hangs under its parent by session id, never by name
- source: YedPool/wezfleet lib/Hierarchy.ps1:17-19; commands/own.ps1:51-64; 1e8837a (own wrote a name, tree read an id, and they disagreed)
- disposition: test
- where: test/test-tree.ps1 :: "a child is drawn under its parent by session id"

### L-003 Every finding reports and nothing repairs
- source: YedPool/wezfleet commands/tree.ps1:50-52; lib/Hierarchy.ps1:21-24; test_debug/test-hierarchy.ps1:68
- disposition: test
- where: test/test-tree.ps1 :: "tree leaves every record unchanged when it reports two warchiefs"

### L-004 Two warchiefs are both drawn as roots and both named
- source: YedPool/wezfleet commands/tree.ps1:32-36; lib/Hierarchy.ps1:83-87; test_debug/test-hierarchy.ps1:66-67
- disposition: test
- where: test/test-tree.ps1 :: "two warchiefs are both drawn and both named"

### L-005 No warchief is printed as a finding
- source: YedPool/wezfleet lib/Hierarchy.ps1:79-82; test_debug/test-hierarchy.ps1:45 "no master is a FINDING, not a silent normal"
- disposition: test
- where: test/test-tree.ps1 :: "no warchief is printed as a finding"

### L-006 A handle is shown only when it is live in this host instance
- source: YedPool/wezfleet lib/Common.ps1:597-609 (instance only, no live check); 0e1c75a (tree printed the master at pre-restart pane 32); test_debug/test-instance.ps1:239-240; horde planning/parity-2.3.md P-23
- disposition: test
- where: test/test-tree.ps1 :: "a handle not live in this instance prints as unknown"

### L-007 Sessions with no parent are listed with their directory
- source: YedPool/wezfleet commands/tree.ps1:38-48 "called out rather than left in a column"
- disposition: test
- where: test/test-tree.ps1 :: "sessions with no parent are listed with their directory"

### L-008 Unassigned means no parent, whatever the origin, and the rule is stated once
- source: YedPool/wezfleet lib/Hierarchy.ps1:49-54 (the comment says origin=user with no parent; the code checks only role and parent), read-found 2026-09-30
- disposition: test
- where: test/test-tree.ps1 :: "an orc with no parent is unassigned whatever its origin"

### L-009 Every live session appears in the tree exactly once
- source: YedPool/wezfleet commands/tree.ps1:20-47: only warchiefs are recursed from and the unassigned list is flat, so a child of an unassigned node is never drawn; read-found 2026-09-30
- disposition: test
- where: test/test-tree.ps1 :: "every live session appears exactly once in the tree"

### L-010 Members of a parent loop are drawn and the loop is a fault
- source: YedPool/wezfleet lib/Hierarchy.ps1:52-58 and :70-110 (no loop check; loop members are neither unassigned nor orphans); :133-142 (Set-WfSessionParent refuses a loop, other writers do not); read-found 2026-09-30; horde fault parent-cycle in schema/session-view.v1.json (feature/core-projection)
- disposition: test
- where: test/test-tree.ps1 :: "a parent loop is drawn and reported as a fault"

### L-011 A retired session is not a member
- source: YedPool/wezfleet lib/Hierarchy.ps1:38-42; test_debug/test-hierarchy.ps1:71 (the control: closing one clears the finding)
- disposition: test
- where: test/test-tree.ps1 :: "a retired session is not drawn in the tree"

### L-012 A session whose parent is gone is drawn, and says whether the parent is missing or retired
- source: YedPool/wezfleet lib/Hierarchy.ps1:100-107 (only the finding names it; the body never draws it); horde planning/parity-2.3.md P-25
- disposition: test
- where: test/test-tree.ps1 :: "a session whose parent is gone is drawn and named"

### L-013 An orc under something other than the warchief is printed with its label
- source: YedPool/wezfleet lib/Hierarchy.ps1:89-98; horde planning/ledger/core-projection.md L-038
- disposition: test
- where: test/test-tree.ps1 :: "an orc outside the warchief is printed with its label"

### L-014 Advice names only commands Horde has
- source: YedPool/wezfleet commands/tree.ps1:47 and commands/census.ps1:36 advise wezfleet own; own matches pane, claude id or fleet id but not the label (commands/own.ps1:43); Horde has no assigning command before step 3.8
- disposition: dropped
- reason: Horde has no command that sets a parent until step 3.8, and advice naming another system's command would tie Horde's output to wezfleet's surface; the adoption ledger records who still assigns through wezfleet.

### L-015 An unreadable registry prints unknown, never no sessions recorded
- source: YedPool/wezfleet commands/tree.ps1:13-18; lib/Registry.ps1:115 onward (Read-WfAllSessionRecords)
- disposition: test
- where: test/test-tree.ps1 :: "an unreadable registry prints unknown, never no sessions"

### L-016 An unlabelled session is drawn with its id prefix, so two of them can be told apart
- source: YedPool/wezfleet commands/tree.ps1:25, :33, :44 print (unlabelled) for every one
- disposition: test
- where: test/test-tree.ps1 :: "an unlabelled session is drawn with its id prefix"

### L-017 Roles print in Horde's vocabulary, read through the alias table
- source: YedPool/wezfleet commands/tree.ps1:26, :34 print wezfleet's role words; lib/Hierarchy.ps1:28; horde planning/migration-plan.html step 0.8
- disposition: test
- where: test/test-tree.ps1 :: "roles print in the horde vocabulary"

### L-018 Fault kinds are renamed, so the shadow maps them before comparing
- source: YedPool/wezfleet lib/Hierarchy.ps1:80, :84, :94, :104 (no-master, two-masters, orchestrator-not-under-master, parent-missing); horde schema/session-view.v1.json fault kinds (feature/core-projection)
- disposition: comment
- where: cli/shadow/tree.ps1 :: "fault kinds are compared through the role alias table"

### L-019 The Warchief reads scope names from the tree
- source: ~/.claude/skills/master-orchestrator-handoff/SKILL.md:67-68; command logs measured 2026-09-30: M 11 uses of tree
- disposition: comment
- where: cli/Tree.ps1 :: "the warchief reads scope names here"

### L-020 Test records must never reach the live registry the tree is drawn from
- source: YedPool/wezfleet test_debug/test-delivery.ps1:68-69; test-registry-hook.ps1:183, :303; test-safe-kill.ps1:58 (M found strays by reading tree)
- disposition: test
- where: test/test-tree.ps1 :: "the tree suite reads only its temporary copy"

### L-021 The command must reach the projection, proven by running the command
- source: YedPool/wezfleet c850e7b; tasks/lessons.md:449-481; horde planning/ledger/core-projection.md L-052
- disposition: test
- where: test/test-tree.ps1 :: "horde tree reaches the projection through the command"
```

## Appendix D: draft `planning/ledger/core-target.md` (steps 14-17)

Adapted to decision 7: L-013, L-014, L-015 and L-017 now require a verified handle (L-015 and L-017 were dropped in the research, L-013 and L-014 said the opposite); step 17 reverses L-013, L-014 and L-017 later. L-016 is dropped with allowance G-01 named. L-009 cites decision 6; L-021 and L-022 cite wezfleet issues #18 and #19.

```
module: core/target
replaces: YedPool/wezfleet lib/Registry.ps1 (Resolve-WfFleetTarget, the naming half; Test-WfCrossOwnerTarget), lib/Run.ps1 (Resolve-WfSessionRowOrFail, the run-then-registry order), lib/Common.ps1 (Resolve-WfRunForSession, as tell uses it), lib/Hierarchy.ps1 (Test-WfMayMessage), commands/tell.ps1:57-144 (target resolution only, not delivery)
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

## What each source held

- comments: lib/Registry.ps1:627-647, :677-698, :736-738, :745-746, :1061-1069; lib/Run.ps1:19-21, :40-51, :73-74;
  lib/Common.ps1:270-279; commands/tell.ps1:61-85, :106-111, :119-122, :138-140; lib/Hierarchy.ps1:150-159.
- history: 17c5d42 (Resolve-WfFleetTarget and Resolve-WfSessionRowOrFail, 2026-09-15); c850e7b (follow a moved pane;
  warn across owners); 0e1c75a (tell no longer forces identityOk); 4eba288 (Test-WfMayMessage and the
  CLAUDE_SESSION_ID read); 10b1782 (Test-WfCrossOwnerTarget).
- pull requests: none touched lib/Registry.ps1, lib/Run.ps1, lib/Hierarchy.ps1 or commands/tell.ps1 (gh pr list,
  17 pull requests, --json files).
- docs: planning/BUG-2026-09-15-registry-record-wipe.md:7, :85-110; planning/BUG-2026-09-15-restart-pane-identity.md:111;
  tasks/lessons.md:204-215, :449-481, :483-533; ORCHESTRATOR.md:14-17, :46-49, :74, :274, :351.
- tests: test_debug/test-instance.ps1:257-309, :356-360; test-hierarchy.ps1:91-100; test-registry.ps1:142-148;
  test-run-resolution.ps1:51-90.
- measured use, 2026-09-30: 623 tell invocations in 299 command logs; targets M 202, F 139, B 69, A 65, E 38, D 23,
  G 7, C 4, A1 3, H 2, a hex prefix 5, a dozen fleet ids.

### L-001 A session is named by label, full id, unique id prefix of eight or more, or fleet id
- source: YedPool/wezfleet lib/Registry.ps1:685-688, :708-714; test_debug/test-instance.ps1:285-287
- disposition: test
- where: test/test-target.ps1 :: "a label, an id prefix and a fleet id name the same session"

### L-002 Labels match case-sensitively
- source: YedPool/wezfleet lib/Registry.ps1:686, :711 (-ceq); test_debug/test-instance.ps1:288
- disposition: test
- where: test/test-target.ps1 :: "labels are matched case-sensitively"

### L-003 A name that fits several sessions is refused with every candidate named, never chosen
- source: YedPool/wezfleet lib/Registry.ps1:689, :720-724; test_debug/test-instance.ps1:290; 17c5d42 mutation "ambiguity picked"; horde fault label-held-twice (feature/core-projection)
- disposition: test
- where: test/test-target.ps1 :: "two sessions wearing one label are refused with both named"

### L-004 A retired session does not compete for its label
- source: YedPool/wezfleet lib/Registry.ps1:710; test_debug/test-instance.ps1:308; horde planning/parity-2.3.md P-07 (the view's label reads W1 whatever retired says, so the resolver filters retired itself)
- disposition: test
- where: test/test-target.ps1 :: "a retired session does not compete for its label"

### L-005 An unknown name resolves to nothing, with the reason
- source: YedPool/wezfleet lib/Registry.ps1:716-718; test_debug/test-instance.ps1:309
- disposition: test
- where: test/test-target.ps1 :: "an unknown name resolves to nothing and says why"

### L-006 An id prefix needs eight characters
- source: YedPool/wezfleet lib/Registry.ps1:708 (^[0-9a-fA-F-]{8,36}\z)
- disposition: test
- where: test/test-target.ps1 :: "an id prefix shorter than eight characters is refused"

### L-007 An id prefix matches whatever its case
- source: YedPool/wezfleet lib/Registry.ps1:713 (StartsWith of the lower-cased target)
- disposition: test
- where: test/test-target.ps1 :: "an upper case id prefix still names the session"

### L-008 A hex-looking label that is also another session's id prefix is ambiguous
- source: YedPool/wezfleet lib/Registry.ps1:709-715 matches label and prefix in one pass; read-found 2026-09-30
- disposition: test
- where: test/test-target.ps1 :: "a label that is also an id prefix is ambiguous"

### L-009 A name that is both a fleet id in the caller's run and a label elsewhere is not silently resolved to the run
- source: YedPool/wezfleet lib/Run.ps1:54-62 (the run is consulted first) and lib/Common.ps1:283-287 (WEZFLEET_RUN_DIR returns the caller's run); read-found 2026-09-30, unmeasured; decision 6 of 2026-09-30 makes it ambiguous, shadow allowance G-02
- disposition: test
- where: test/test-target.ps1 :: "a fleet id and a label of the same text are reported as ambiguous"

### L-010 Two open runs holding the name are refused, naming both
- source: YedPool/wezfleet lib/Run.ps1:18-31; lib/Common.ps1:277-278; test_debug/test-run-resolution.ps1:62-64; tasks/lessons.md:204-215
- disposition: test
- where: test/test-target.ps1 :: "two open runs holding the name are refused with both named"

### L-011 A pending entry elsewhere does not make a spawned session ambiguous
- source: YedPool/wezfleet test_debug/test-run-resolution.ps1:55-56, :75-76, :83, :90; horde planning/ledger/core-projection.md L-032, L-033
- disposition: test
- where: test/test-target.ps1 :: "a pending entry elsewhere does not make a name ambiguous"

### L-012 A session that is in no run is still nameable
- source: YedPool/wezfleet lib/Registry.ps1:679-683; lib/Run.ps1:43-45; 17c5d42 (A worked around it with raw send-text, which skips every guard)
- disposition: test
- where: test/test-target.ps1 :: "a session in no run is nameable by its label"

### L-013 At first, a session with no verified handle is refused, as wezfleet refuses it
- source: YedPool/wezfleet lib/Registry.ps1:733-750 (every refusal before a pane may be typed into); decision 7 of 2026-09-30 keeps the refusal until the shadow logs are clean; the research's original form (a session with no handle still resolves, wezfleet planning/wezfleet-ssot-multi-backend-2026-09-29.md:486-503) returns in the later relaxing PR
- disposition: test
- where: test/test-target.ps1 :: "a session with no verified handle is refused with the reason"
### L-014 An unknown handle list refuses every name, with the host's reason
- source: YedPool/wezfleet lib/Registry.ps1:733 ("no pane can be verified"); test_debug/test-instance.ps1:305; decision 7 of 2026-09-30
- disposition: test
- where: test/test-target.ps1 :: "an unknown handle list refuses with the host reason"
### L-015 A handle is verified only when the view answers it live in the current host instance
- source: YedPool/wezfleet lib/Registry.ps1:691-693, :736-742; test_debug/test-instance.ps1:292, :297-298; 17c5d42 mutation "pane-sessions accepted" survived its first run; horde planning/ledger/core-projection.md L-011, L-022 (the instance rule on every handle); decision 7 of 2026-09-30
- disposition: test
- where: test/test-target.ps1 :: "a handle not live in this instance is refused"
### L-016 A pane whose title fell back to a bare shell is refused
- source: YedPool/wezfleet lib/Registry.ps1:745-750; lib/Common.ps1:375-395; test_debug/test-instance.ps1:300, :302 (with its control)
- disposition: dropped
- reason: the bare-shell test reads host titles, which the projection dropped (core-projection L-058) and decision 5 keeps on wezfleet until a host adapter provides it; Horde does not type, and the shadow classifies the resulting difference as allowance G-01.
### L-017 A closed pane is refused
- source: YedPool/wezfleet lib/Registry.ps1:743-744; test_debug/test-instance.ps1:303-304; decision 7 of 2026-09-30
- disposition: test
- where: test/test-target.ps1 :: "a closed handle is refused as unverified"
### L-018 A name resolves to the session, never to a spawn-time handle
- source: YedPool/wezfleet commands/tell.ps1:65-77; c850e7b (recorded at 26, alive at 22); test_debug/test-ssot.ps1:11-12; horde planning/migration-plan.html D3
- disposition: test
- where: test/test-target.ps1 :: "a name resolves to a session id, never to a roster handle"

### L-019 Forcing identity true to follow a moved pane would type into a stranger after a restart
- source: YedPool/wezfleet commands/tell.ps1:79-85; 0e1c75a
- disposition: dropped
- reason: the forced flag existed only to let typed delivery follow a pane; Horde neither types nor follows panes by number.

### L-020 Crossing into another orc's goblin warns and names the orc, never refuses
- source: YedPool/wezfleet lib/Hierarchy.ps1:149-159; commands/tell.ps1:106-111, :119-122; test_debug/test-hierarchy.ps1:93-100; 4eba288; 10b1782
- disposition: test
- where: test/test-target.ps1 :: "a target inside another orc warns and names that orc"

### L-021 The caller is identified the way the projection identifies sessions, not by a variable nothing sets
- source: YedPool/wezfleet commands/tell.ps1:123 reads $env:CLAUDE_SESSION_ID; measured 2026-09-30: set nowhere in lib, commands or hooks (Select-String finds only tell.ps1:123), empty in a live Claude Code session where CLAUDE_CODE_SESSION_ID was set; introduced 4eba288; test_debug/test-hierarchy.ps1:91-100 tested only the verdict function; filed as YedPool/wezfleet#18
- disposition: test
- where: test/test-target.ps1 :: "the boundary warning fires when run through the command"

### L-022 Ownership is compared by session id, never by a name against a fleet id
- source: YedPool/wezfleet lib/Registry.ps1:1070-1076 compares the stored owner (a label, commands/own.ps1:73) with WEZFLEET_SESSION_ID (a fleet id); test_debug/test-registry.ps1:142-148 uses boss for both; read-found 2026-09-30, unmeasured in live use; filed as YedPool/wezfleet#19
- disposition: test
- where: test/test-target.ps1 :: "ownership is compared by parent session id"

### L-023 The resolver returns a refusal and never ends the process
- source: YedPool/wezfleet lib/Run.ps1:30, :57, :68 (exit inside library functions), so neither another command nor a shadow can call it and continue
- disposition: test
- where: test/test-target.ps1 :: "core target returns a refusal and never exits"

### L-024 A refusal exits 1 with the reason, and a malformed name exits 2
- source: YedPool/wezfleet lib/Run.ps1:65-68 and commands/tell.ps1:133-144 exit 1 for every refusal; horde horde.ps1 header exit code contract
- disposition: test
- where: test/test-target.ps1 :: "an ambiguous name exits 1 with the candidates"

### L-025 The product must reach the resolver, proven by behaviour and not by matching source text
- source: YedPool/wezfleet test_debug/test-instance.ps1:356-359 (a regex over source); tasks/lessons.md:483-533 "A guard that EXISTS is not a guard that GUARDS"
- disposition: test
- where: test/test-target.ps1 :: "horde target reaches the resolver through the command"

### L-026 The cwd and transcript returned with a target served delivery receipts
- source: YedPool/wezfleet lib/Registry.ps1:729-730; commands/tell.ps1:155-161
- disposition: dropped
- reason: the transcript was the receipt for typed delivery, which Horde does not port (step 6.1); the view already answers cwd and transcriptPath for anyone who needs them.

### L-027 A deregistered session has no messaging address
- source: YedPool/wezfleet planning/wezfleet-ssot-multi-backend-2026-09-29.md:653 (the control file was removed and the session could not be messaged); horde core/ownership.json messagingAddress row reads X2 only (feature/core-projection)
- disposition: test
- where: test/test-target.ps1 :: "a deregistered session has no messaging address"

### L-028 Labels are the names people use
- source: command logs measured 2026-09-30: of 623 tell targets, single letters and letter-digit labels were the large majority (M 202, F 139, B 69, A 65, E 38, D 23)
- disposition: comment
- where: core/Target.ps1 :: "labels are the names people use"
```
