# Contributing

How work is done in Horde, and why. Every rule cites the incident or measurement behind it, so it
can be argued with on its merits. Most were paid for in the two systems Horde is replacing; those
citations name the repository (`YedPool/wezfleet`, `wezterm-resurrect`) because the sources live
there, not here.

`CLAUDE.md` holds the same rules as short imperatives for agent sessions, which inherit it. This
file holds the reasons.

---

## 1. A piece is done when the fleet runs on it, not when its tests pass

Horde replaces a fleet that is running real work every day. So nothing here counts as finished
because a suite is green. A piece is done when **the live fleet uses it for real work** and has
kept using it.

Every step that takes over from the old system goes through three stages:

1. **Shadow.** The new path runs beside the old one. Both produce a result; the old result is the
   one used; every difference is logged with enough context to explain it.
2. **Switch.** Only after a run of clean or explained comparisons does the default flip. The old
   path stays reachable behind a flag for one more phase.
3. **Adopted.** The pull request that completes a step records who in the fleet now uses it, for
   what, and for how long, and what broke. An unexplained difference in shadow is a bug in one of
   the two paths until proven otherwise - never noise.

Why: the systems being replaced were repeatedly correct in their test suites and wrong in use. A
mechanism once existed, worked and had no callers while three suites agreed it was fine
(`YedPool/wezfleet`, `tasks/lessons.md`, "a mechanism with no callers, and three green suites that
agreed"). Use by the real fleet is the only test that cannot be satisfied by testing the wrong
thing.

## 2. Test end to end, the way a user would

Unit tests say a function is right. They cannot say the product works. Every user-facing command
has an **end-to-end scenario** that drives the real `horde` command line exactly as a person or an
orchestrating session would - spawning, reporting, restoring, reading status - and asserts on what
a user would see and on the state left behind.

End-to-end scenarios run in an **isolated terminal**, never the one you are working in. See rule 3;
it is not optional.

## 3. Never test against the terminal you are working in

The largest blast radius of any rule here. **The wezfleet suite took down every WezTerm window on
its machine twice.** Once because WezTerm recycles pane ids and the suite trusted a bare id; once
without mis-targeting anything, because a separate *window* shares the same mux server as every
other window (`YedPool/wezfleet`, `tasks/lessons.md`, both 2026-08-16 entries).

- Isolation is a **separate WezTerm instance with its own mux**, not a separate window.
- `--class NAME` looks like isolation and is not: inside a pane `WEZTERM_UNIX_SOCKET` is set and the
  CLI follows it to your real terminal. The pin that works is `WEZTERM_UNIX_SOCKET` aimed at the new
  instance's socket. Measured: pinned, 1 pane visible; unpinned, 13.
- Start the isolated instance with `--skip-config`, or it loads your config and your session-restore
  plugin, and either restores your real sessions inside the test or sits on a modal prompt.
- **Measure what an isolation mechanism can see before letting it destroy anything.** A harness
  asserts it cannot see your panes and aborts if it can. It never falls back to a shared mux,
  because that fallback is indistinguishable from the bug.
- Real agent sessions cost real money. End-to-end scenarios that start one use the cheapest prompt
  that proves the point, and say so.

In the original words: *"A lesson that only changes how carefully you do the dangerous thing has
not changed anything. Make the dangerous thing impossible by default instead."*

## 4. Branches, worktrees, atomic commits, small pull requests

- **Never commit to `main`.** The root commit was the only exception, because a new repository has
  nothing to branch from until one exists.
- **Work in a worktree**, in the one folder beside this repository, from a freshly updated `main`.
  From the repository root:

  ```
  git fetch origin main
  git worktree add -b <branch> ../horde-worktrees/<name> origin/main
  ```

  Never switch branches in a checkout where a suite is running; a worktree is a separate checkout,
  so work continues while tests run.
- **One logical change per commit**, each independently revertible. Two changes to one file are still
  two commits.
- **One concern per pull request.** Things noticed on the way are written down for their own pull
  request, not folded in.
- **Merge with a merge commit, never squash.** Squashing severs a branch's commits from `main` and
  breaks bisect, `git branch --contains` and cherry-pick provenance. Use `git log --first-parent`
  for a linear view.
- **Stacked pull requests:** retarget B onto `main` after A merges and before merging B, or B lands
  on A's branch.

## 5. Read what the old code learned before replacing it

No module replaces old code until its **knowledge ledger** is complete: `planning/ledger/<module>.md`,
harvested just before replacement from five sources, in both old repositories -

1. the old module's comments;
2. `git log --follow` of every file it spans;
3. every pull request that touched those files - as of 2026-09-29, 15 in wezfleet and 69 in
   wezterm-resurrect;
4. every planning, BUG and lessons entry that names it;
5. its tests - each test name is a behaviour someone once needed.

Every entry is cited and gets exactly one disposition: **encoded as a test**, **carried as a
comment**, or **dropped, with the reason**. An entry with no disposition means nobody looked.

Why this is a rule: the first version of this migration's own plan claimed the old master
orchestrator had no role field and no uniqueness check. Both existed, in the two files named after
it (`YedPool/wezfleet`, `lib/Hierarchy.ps1`, `lib/Master.ps1`).

## 6. Verify against the shipped command, not a reconstruction of it

In one day of work on the old system, eight hand-built checking instruments each gave a wrong or
empty answer at least once, and the shipped commands were right every time
(`YedPool/wezfleet`, `tasks/lessons.md`, "Eight harness failures, zero shipped-code failures"). Use
the real command and the real file first. Build an instrument only when nothing shipped can answer
the question - and then give it a control.

## 7. A null result is not a finding until a control says so

A search that finds nothing proves nothing until the same instrument finds something known to be
present. A line that looks like a check must be one: an assertion that passes by matching the wrong
text, or a teardown that prints "restored" without checking, is output shaped like evidence.
Mutation-test assertions as well as code - restore the defect and confirm the test goes red.

## 8. Comments say why, and cite the measurement

Comments do not describe what a line does. They record what was measured, what was tried and
failed, and what would break if the line changed, with dates and numbers a reader can check.
That is what let the old systems be picked up cold, and it is the most valuable thing Horde
inherits from them.

## 9. Tests act on what they created

A test acts on the run or session it just made, named explicitly, never on whatever ambient
resolution returns. Ambient behaviour is a thing to test, not a thing to depend on while testing
something else (`YedPool/wezfleet`, `tasks/lessons.md`, 2026-08-17).

A test of code that kills or deletes never lets that code choose the victim: it passes a guard that
acts only on what the test created and still holds (see `hosts/wezterm/test/test-isolation.ps1`).

Every suite is built on `test/lib/Suite.ps1`, whether it lives in `test/` or, for a suite about one
host, transport or agent harness, in that adapter's own `hosts/<name>/test/`,
`transports/<name>/test/` or `agents/<name>/test/` (D12): dot-source it, put its one `trap` line at
the suite's top level, and end with `Complete-HordeSuite`. It makes a check's condition be exactly
true or false, and it fails the suite when a check's own expression raises an error - which otherwise
makes the check vanish while the suite exits 0.

**The gate runs every suite in those four places**, one at a time, from a fresh CRLF checkout:

```
test/test-*.ps1
hosts/*/test/test-*.ps1
transports/*/test/test-*.ps1
agents/*/test/test-*.ps1
```

Every gate run includes `hosts/*/test/test-*.ps1`, so each host's isolation harness is exercised on
every run, not only when its own folder changes. `test/lib/SuiteFiles.ps1` is that list. `test/test-suite.ps1` checks how every suite on it is built,
and fails on any `test-*.ps1` anywhere else in the repository (`test/fixtures/` is data and is
skipped). A suite outside the gate's folders is one nobody runs, and it reads as coverage: the first
transport's own suite sat outside `test/test-*.ps1` until the review of PR #42 found it.

## 10. Code brought in from elsewhere keeps its licence notice

Horde is MIT. Code ported from another project keeps that project's copyright and permission notice
alongside it, as its licence requires. In particular, `wezterm-resurrect` is a fork of Malthe
Larsen's `resurrect.wezterm` and carries his MIT notice; any of its code that moves into Horde
brings that notice with it.

## 11. Nothing personal in shipping code

No absolute paths to anyone's home directory, no names of private projects, and no references to
particular people in code, scripts, comments or committed configuration. Paths are relative or
derived from the environment. The old system accumulated hundreds of these and removing them was a
review finding of its own.

## 12. PowerShell 5.1 traps that have already cost real time

- **Do not wrap a native command in `2>&1` or `*>`.** PowerShell 5.1 turns its stderr into
  terminating error records even under `ErrorActionPreference = Continue`.
- **`$Args`, `$PID` and `$Home` are automatic variables.** A parameter with one of those names is
  silently shadowed or refused.
- **`ConvertTo-Json` is not `JSON.stringify`.** It escapes `'`, `<`, `>` and `&` as `\u` sequences.
- **`/tmp` means `C:\tmp` to PowerShell**, and with `core.autocrlf` on, a checked-out file has CRLF
  line endings: collapse `\r` as well as `\n` before comparing text, and assert the match count
  after every scripted edit.
- **A `[string]` parameter never holds `$null`.** Defaulting one to `$null`, or passing `$null` to
  it, gives `""`. Test for an empty string, or leave the parameter untyped when "not given" and
  "empty" must differ.
- **Variable names are case-insensitive.** `$rel` and `$Rel` are one variable; a local named like a
  parameter overwrites it. Give locals names no parameter uses.
- **A function returning one element returns the element, not an array.** The caller gets a scalar,
  and `.Count` on a single `[pscustomobject]` is `$null`, so `-eq 1` fails. Wrap the call:
  `@(Get-Thing)`.
- **Inside a `Where-Object` or `ForEach-Object` block, `$MyInvocation` describes the block**, not the
  script. Use `$PSCommandPath` for the running file.
- **A process started from Git Bash makes user-owned objects, even elevated.** MSYS rewrites the
  token's default owner to the user at start-up, and its children inherit it; started from
  PowerShell under an elevated admin token, a new pipe is owned by Administrators. So test-local's
  elevated case - the attackers' explicit owner and the Administrators-owned pipe of issue #89 -
  must be launched from PowerShell, not Git Bash: launched from Git Bash it cannot see #89 or a
  regression of it (review of PRs #90 and #91, 2026-10-05).
- **Dividing two integers gives a double.** `$ticks / 10` loses precision past about 16 digits, and
  a tick count has 18: two readings of one process's creation time disagreed for 304 of 365
  processes. Use `[Math]::DivRem` when the result must be exact.

## 13. Source files are ASCII

No emoji and no non-ASCII characters in code, scripts or generated artefacts. Where a glyph is
wanted, write it as an escape sequence so the source stays ASCII.

## 14. A terminal, an agent harness or a transport is named only in its own folder

Nothing outside `hosts/<name>/` names a terminal (migration-plan decision D12): the engine, the
schemas and the read model speak of sessions, slots and capabilities, so that the next host is a new
adapter and not an engine change. Host-specific test tooling lives with its host too, in
`hosts/<name>/test/`.

The same seam holds for the agent harness - the command-line program a session runs. Nothing outside
`agents/<name>/` names a harness, so that the next harness is a new adapter and not an engine change
either (engine-settings design, 2026-09-30, section 9; the founder's decision of the same day that core
never names an engine). A harness folder carries the same `names.txt`, `allowlist.txt` and
`growth.txt`, read by the same scan, and everything below that is said of a host holds for a harness.

And for the transport - what carries the link between a hub and a node. Nothing outside
`transports/<name>/` names a transport program or its options (remote design, founder decision 10;
remote plan step R5), so that the second transport is a new folder and not an engine change.
`transports/Port.ps1`, beside the transport folders, belongs to none of them and is scanned like core.

And for the relay - the untrusted mailbox store the relay module meets a phone and other machines
through. Nothing outside `relays/<name>/` names a relay (relay design 2026-10-09, PR plan item 3), so
that the hosted relay after the local one is a new folder and not a change to the relay module or its
channels. `relays/Port.ps1` belongs to no relay, as `transports/Port.ps1` belongs to no transport. The
messengers (`messengers/<name>/`) and surfaces (`surfaces/<name>/`) are held the same way; the
families are listed once, in `tools/HostNames.ps1`.
Core still names the two harnesses the old system ran, because Phases 0 to 2 read their own files;
those entries were measured when the rule was extended and shrink as the reads move behind the
AgentPort.

A name line may say what kind of knowledge it is: `name`, `processImage` or `path`
(`<name> | <kind> | <reason>`; a two-part line is a `name`). The lifecycle plan's step 5 declares
each harness's process image and the path fragments of its transcripts and control files this way,
so the scan catches them outside the adapter. Where two declared names overlap, the place counts
once, as the longer name. A **process image is held to more than a name**: core matches no image
(lifecycle plan section 2.6), so outside every port's folder and `test/`, no file may match one,
whatever its allowlist says, written as is or as an escaped regular expression. The Phase 0 to 2
readers that already did when the rule came in are listed in `tools/process-image-legacy.txt` with
their exact number of matches; compared with `origin/main`, an entry may only be lowered or removed,
never added or raised, and no growth line changes that. A name that is a `processImage` on
`origin/main` stays one. What a text scan cannot see - an image assembled at run time, a looser
pattern - is written in the header of `tools/HostNames.ps1`.

**One host may import another's command language, and nothing else of it** (hosts plan step 5). Two
multiplexers that speak one language share it from the first one's folder, as `Dialect.ps1`. An
entry `<path> | import | <reason>` in the first host's `allowlist.txt` lets a file in the second
host's folder name the first exactly once, in the line that dot-sources that `Dialect.ps1`. Inside
another port's folder that is the only way in: any other mention there fails, except in that port's
own list files, which name other ports' files by path. The dialect hands out its environment
variables as data (`Get-HordeMuxDialectEnvNames`), so the importer never spells them. A new import
entry is growth like any other and needs its line in `growth.txt`.

`test/test-host-names.ps1` enforces it. Each host lists what identifies it in
`hosts/<name>/names.txt`, and every file elsewhere that still names it in
`hosts/<name>/allowlist.txt`, with a reason and its exact number of mentions. The list may only
shrink: a new mention fails, and so does an entry that allows more than its file needs. When the
checkout has `origin/main`, the suite also compares each host's lists with it, and fails on an entry
`origin/main` does not have, a count above its count, or a name or host folder it has and this
checkout does not; with no git or no `origin/main` it prints `[SKIP]` and the reason. A host that is
new on the branch is reported, not compared: its own pull request is where its lists are agreed.

A branch that genuinely needs a new entry or a higher count records it in
`hosts/<name>/growth.txt`, one line per increase: `path | old -> new | YYYY-MM-DD | reason`, with
`old` being `origin/main`'s count (0 for a new path) and a reason of at least four distinct words.
The increase passes only when a line added since `origin/main` matches that path and exactly those
two counts; that line is what the reviewer agrees to. Refusing every increase outright was a
deadlock - the entry could never pass until it was already on `main`. A line already on `main`
permits nothing again, so a mention removed later cannot come back unreviewed, and `growth.txt` is
append-only: its lines on `origin/main` must still open the file, unchanged and in order. A line that
matches no current difference is history, not a failure. There is no growth record for `names.txt`:
a declared name is never removed. The `.md`
and `.html` files under `planning/` are not scanned, because plans and ledgers record the system
being replaced and cannot be accurate without naming it; any other file under `planning/` fails.

## 15. Test levels and merging

Verification is cheap in a review round and thorough once per pull request, and the thorough run is
on the tree that will actually exist after the merge. The founder set these levels on 2026-10-02,
after rounds that reran every suite and every mutation spec on lines nobody had touched, while two
pull requests that were green on their branches left `main` red (`tasks/lessons.md`, "A PR green on
its branch can break main when main moved under it").

1. **Each review round tests only what changed:** the suites that cover the changed files, plus
   `tools\Mutate.ps1 -Changed <base-ref>`, which runs only the mutants whose find string lies on a
   line the diff added or modified. It lists every mutant it selects and every one it skips, with
   the reason; it runs every mutant it cannot place; and on a diff that touches a mutation target it
   treats a selection of zero as an error, not a pass. A change to a spec file reruns every mutant
   of that spec.

   **`-Changed` is a review-round accelerator only.** It selects by line, so it is blind to a
   change anywhere but on a mutant's own line: an edited helper that a target dot-sources; an
   edited config, schema or data file that is not itself a target; a guard inserted above a mutant
   whose own line did not change; and a suite edited to catch less. The review of its pull request
   (#63) probed the first three, and each time the affected mutants were skipped and the run
   exited 0. It proves only the mutants on touched lines and never stands in for the
   changed-target specs: **a pull request may not merge on `-Changed` results alone.**
2. **The full suite and the changed-target mutation specs run once per pull request**, on its
   final head, and on the **merge result** with current `main` (`git merge-tree`, or a throwaway
   merge commit) - not on the branch alone. The changed-target specs are every spec whose
   `Target`, `Suite` or spec file the pull request changes, so a suite edited to catch less reruns
   its specs. "Mergeable" on GitHub means the text merges; it says nothing about whether the merged
   tree is green. Why whole specs run at all, and not only `-Changed`: first, `-Changed` is blind
   to every change that is not on a mutant's own line (rule 1): whole specs see those on their own
   targets, and no run sees the rest (see below). Second, a spec on `main` can break without anyone
   running it. `test\mutations\port-names.psd1` had a mutant
   whose find string occurred twice from PR #57 on, so the mutant could not apply, and nothing
   reported it until the `-Changed` selector placed every mutant.

   **No full mutation sweep runs, nightly or otherwise, and nothing may lean on one** (T-0437,
   2026-11-07). The full sweep left the per-pull-request gate on 2026-10-21, at 470 specs and 9039
   mutants, because one pull request's gate held the one local heavy slot for over an hour and a
   half with about ten runs from other lanes queued behind it. This rule then said the sweep ran
   nightly, but the nightly net never ran mutants, and the by-hand run promised until it did had
   no owner or schedule. It is now 562 specs and 10600 mutants. The changed-target specs and `-Changed` cover the edited
   targets and suites. `test\test-mutation-specs.ps1` catches a mutant that no longer applies. So
   an edited helper or config that is no spec's target has no mutation check at all: say so when
   a change is one. A pull request body names the specs it ran and does not claim a sweep.
3. **Reviewers do not rerun the author's suites.** The author's runs, and the logs they leave, are
   the author's evidence. A reviewer reads the code and writes **targeted probes**: the input the
   author did not think of, run against the shipped command (rule 6). Rerunning the same suites
   adds time and finds what the author already found (`tasks/lessons.md`, "Tests I wrote and
   mutated myself are not an adversarial review").
4. **A suite that takes more than 2 minutes on fixtures is a defect**, measured as its wall time
   in the remote gate's log, alone on the remote test box (rule 5). File an issue to profile it.
   A slow suite is rerun less, and a mutation spec multiplies its time by its number of mutants.
5. **Heavy runs go to the remote test box, through the remote gate.** The box is whichever machine
   the local configuration names; nothing in this repository names it. The remote gate ships the
   exact commit, runs each suite in a contained environment, and decides the verdict from the logs
   it copies back. Anything that needs a real terminal, a local pipe, integrity levels, an
   interactive logon or the founder's real stores runs **locally, one run at a time, through the
   local gate**, which holds one lock across every agent on the machine. Several agents that each
   waited for free memory all started together when it freed, and were reaped for low memory four
   times in one hour (2026-10-01).
6. **Merges go in batches.** A pull request that is green and reviewed is **ready**, and is held.
   A few times a day the ready pull requests are merged together:
   - build the combined tree: `main` plus every ready pull request, in order;
   - run the touched suites, the full suite once, and the changed-target mutation specs once for
     the pull requests in the batch, on that tree;
   - merge in order, with merge commits only (rule 4).

   The combined tree is the true merge result, so this run is the once-per-pull-request run of
   rule 2 for every member of the batch. A batch member that turns red is dropped from the batch
   and goes back to its author; the rest are rebuilt without it and run again before they merge.
   Between batches, authors do not rebase on every merge: the batch tests the combination, which a
   rebase onto each new `main` only approximated.
7. **A suite with no checks, or with no closing banner, was NOT RUN.** A runner never reports it
   as green. A killed run and a clean one can leave the same exit code: the local gate's first
   version reported a child killed by the harness as exit 0, and its third read a suite's exit 5 as
   0 (2026-10-01). Every run must end in its own closing line (`Complete-HordeSuite`'s banner, a
   gate's `released exit=<n>`, the remote gate's `complete` line), and a log without it proves
   nothing.
8. **Infrastructure that verifies - gates, runners, test tools - gets a failure-case test matrix
   before it is rolled out.** For each way a run can end (pass, fail, crash, timeout, killed, no
   output, no checks, a suite that skipped part of itself), the matrix says what the tool must
   report, and each row is run once and checked. A gate is trusted with every result that passes
   through it, so a gate that is wrong is wrong everywhere at once: the remote gate's first pruning
   rule, keep the newest 10 runs, deleted other agents' finished runs from the shared folder
   (2026-10-01).
9. **Every repo-wide guard listed in `test\guards.txt` (`test-host-names`, `test-mutation-specs`,
   `test-function-names`, `test-json-parse-allowlist`, `test-param-shadow`, `test-core-load`,
   `test-exec-scan`, `test-start-sites`) is part of EVERY pull request's targeted set**, in both Windows
   PowerShell 5.1 and PowerShell 7, and run on the final head, in a clean tree, by any Orc. **They run
   once a day, at night or at idle, over everything merged that day - not before each merge**
   (founder rule of 2026-10-22: merges do not wait for test runs; rule 10 says how the nightly run
   names the merge that broke one). They are light and read the whole repository, so any pull
   request can break them: on 2026-10-14 PRs 278, 279 and 288 each merged green on their own suites
   and left `main` red on both. That is why the daily run names the merge behind a red guard, and
   why its owner fixes it first thing.
10. **Merges go through `horde merge`**, which does what rule 9 and rule 4 ask in one command, so no
   step rests on memory: it refuses a PR that is not open, is a draft, conflicts or misses a required
   review; merges with `gh pr merge --merge`; and records the task ledger's merged event and tells the warchief and
   the analyst, saying loudly what to run by hand if any of those fails after the merge. Before it, on
   2026-10-14 three merges skipped the guards and left `main` red, and on 2026-10-06 three merges were
   told to nobody (fleet audit of 2026-10-16, findings 2, 4 and 10). The repository's CI runs the
   same guards on every pull request and on `main`; it notifies and never blocks.

   **The guards are owed, not run, at merge time (founder rule of 2026-10-22, T-0347).** Running
   every guard in two shells before each merge was a test run, and it held every Orc's daytime
   merge. So `horde merge` takes `-Guards later|now`, default `later`: it skips the combined-tree
   build, the guards and the base-moved re-check, merges, and appends one line
   (`repo, baseRefName, pr, task, by, at, headSha, mergeSha, firstParent`) to `<HORDE_HOME>\merge\guards-owed.jsonl`;
   the warchief's message, the analyst's mail and the progress line say the guards are OWED, never
   that they passed. `-Guards now` is the old behaviour (guards first, nothing merged on a red one),
   for a merge someone wants checked first. **`horde merge -RunOwed [-Repo OWNER/REPO] [-Json]`** is
   the daily run: for each repository with unchecked entries it runs `test\guards.txt` in both shells
   on the base tip; for each guard red there it walks the queued merges in order, running only that
   guard (first at the first merge's first parent, as the baseline), and names the first merge that
   is red - or says "red before today's first queued merge" and names none. A guard the day's merges
   dropped from the list (listed at the baseline, gone at the tip) is red too, and the merge that dropped
   it is named. A merge is walked on the branch it went into (`baseRefName`), in the order of that branch's
   first-parent history (a recovered merge's queue line comes late in the file). A red stays open in
   `guards-red.json` until a run finds the guard green at the tip: a red guard that is no longer on the tip's
   list stays RED (not run) and is never read green. A guard removed or renamed on purpose is cleared with
   `horde merge -ClearRed -Repo OWNER/REPO -Base <branch> -Guard <guard> -Reason <text>`, which refuses a guard
   that is not in the record or is still on the list, and writes who cleared what and why into the report.
   A merge `gh` was refused is never settled by the daytime merge: the night asks GitHub and queues it if it
   was merged. A guard that did not run
   (PowerShell 7 missing, a timeout) is not a red: that branch ends "could not run", its merges stay owed
   and the run ends 2. A damaged queue line, or a merge missing from its branch, is reported in every run
   (the report prints the line to add to `guards-checked.jsonl` to give it up) and the rest is still
   checked. **The queue is per machine**: a merge made on another machine is in that machine's queue,
   so each machine that merges needs its own run; the report names the machine and the queue file. The
   report goes to
   `<HORDE_HOME>\merge\nightly\<UTC date>-<owner>-<repo>.txt` and is printed, one line per red
   guard naming the PR, task, lane and merge sha, or "all green over N merges"; each checked merge
   sha is then appended to `guards-checked.jsonl` (`guards-owed.jsonl` is append-only). The named
   merge's owner fixes it first thing. It schedules nothing and checks no idle: the nightly
   scheduler (T-0331) does, and reports to M by 07:00.

## 16. Horde never depends on a Microsoft Store package

Horde does not run, launch or require anything installed as a Microsoft Store (MSIX/AppX) package:
not PowerShell 7, not Node, not Python, not a terminal. Use the vendor's MSI or installer and start
it by its full path (`C:\Program Files\PowerShell\7\pwsh.exe`, never whatever `pwsh` the search path
finds first), and keep the Store's automatic updates off.

Why (2026-10-16, 13:58): the Store auto-updated PowerShell 7 (`Microsoft.PowerShell`, running from
`C:\Program Files\WindowsApps\...`). An update closes every running process of the package, so every
`pwsh.exe` was closed at once, and because the terminal's panes ran `pwsh`, every fleet session died
with it. A Store package also cannot be pinned to a version, and its alias can hide the MSI copy.

`horde setup` holds this rule in two steps of `setup/steps.json`: `store-updates-off` (the policy
`HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore` `AutoDownload` = 2; setting it needs an elevated run
and setup says so rather than do it silently) and `powershell-msi` (installs the MSI by the hash the
winget source publishes when `pwsh` is missing or is the Store copy). Setup never uninstalls the Store
copy, because removing it closes the `pwsh.exe` running from it: remove it by hand when no session
runs on it. `test\test-setup-store.ps1` and `test\e2e\e2e-setup-store.ps1` hold both steps.
