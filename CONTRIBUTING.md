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
host, in that host's `hosts/<name>/test/` (D12): dot-source it, put its one `trap` line at the
suite's top level, and end with `Complete-HordeSuite`. It makes a check's condition be exactly true or
false, and it fails the suite when a check's own expression raises an error - which otherwise makes
the check vanish while the suite exits 0.

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
- **Dividing two integers gives a double.** `$ticks / 10` loses precision past about 16 digits, and
  a tick count has 18: two readings of one process's creation time disagreed for 304 of 365
  processes. Use `[Math]::DivRem` when the result must be exact.

## 13. Source files are ASCII

No emoji and no non-ASCII characters in code, scripts or generated artefacts. Where a glyph is
wanted, write it as an escape sequence so the source stays ASCII.

## 14. A terminal is named only in its own host folder

Nothing outside `hosts/<name>/` names a terminal (migration-plan decision D12): the engine, the
schemas and the read model speak of sessions, slots and capabilities, so that the next host is a new
adapter and not an engine change. Host-specific test tooling lives with its host too, in
`hosts/<name>/test/`.

`test/test-host-names.ps1` enforces it. Each host lists what identifies it in
`hosts/<name>/names.txt`, and every file elsewhere that still names it in
`hosts/<name>/allowlist.txt`, with a reason and its exact number of mentions. The list may only
shrink: a new mention fails, and so does an entry that allows more than its file needs. The `.md`
and `.html` files under `planning/` are not scanned, because plans and ledgers record the system
being replaced and cannot be accurate without naming it; any other file under `planning/` fails.
