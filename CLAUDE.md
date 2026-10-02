# Horde - rules for sessions working in this repository

Every session started here inherits this file, subsessions included. The reasons behind each rule
are in `CONTRIBUTING.md`; read the matching section before arguing with one.

## Done means the fleet runs on it (CONTRIBUTING 1 and 2)

- A piece is not finished when its tests pass. It is finished when the live fleet uses it for real
  work: shadow beside the old path, switch after clean comparisons, then record who uses it.
- Every user-facing command gets an end-to-end scenario that drives the real `horde` CLI the way a
  user would.

## Never test against the terminal you are working in (CONTRIBUTING 3)

- Anything that spawns or kills panes runs in a separate WezTerm instance, pinned by
  `WEZTERM_UNIX_SOCKET` and started with `--skip-config` - never a separate window, never `--class`.
- Assert the harness cannot see the user's panes before it touches anything. Abort if it can.

## Work in a worktree, on a branch (CONTRIBUTING 4)

Never commit to `main`. From the repository root:

```
git fetch origin main
git worktree add -b <branch> ../horde-worktrees/<name> origin/main
```

- One logical change per commit. One concern per pull request.
- Merge with `gh pr merge --merge`. Never squash.
- Never switch branches in a checkout where a suite is running.

## Before replacing old code, write its knowledge ledger (CONTRIBUTING 5)

`planning/ledger/<module>.md`: every lesson from the old code, its history, its pull requests, its
docs and its tests, each cited and each given a disposition - test, comment, or dropped with the
reason.

## Checking your own work (CONTRIBUTING 6 and 7)

- Verify against the shipped command and the real file, not a reconstruction.
- A search that finds nothing proves nothing until the same instrument finds something known to be
  present. A line that prints "done" must have checked that it is.

## Test levels and merging (CONTRIBUTING 15)

- Each review round: the suites covering the changed files, plus `tools\Mutate.ps1 -Changed <base-ref>`.
  `-Changed` is a review-round accelerator only: it is blind to edited helpers, config and schemas,
  and to a guard added above a mutant. Never merge on it alone.
- Once per PR, on the final head merged with current `main`: the full suite and the full mutation
  specs. "Mergeable" is not "green".
- Reviewers read the code and write targeted probes; they do not rerun the author's suites.
- A suite over 2 minutes on fixtures is a defect: file an issue to profile it.
- Heavy runs go to the remote test box through the remote gate. A real terminal, a local pipe,
  integrity levels, an interactive logon or the real stores: locally, one run at a time, through
  the local gate.
- Ready PRs are merged in batches: on main plus every ready PR, run the touched suites, the full
  suite and the full mutation specs once; merge in order; drop a red one and rerun the rest.
- No checks, or no closing banner, means NOT RUN. Gates and runners get a failure-case matrix
  before rollout.

## Code (CONTRIBUTING 8 to 14)

- ASCII only. Glyphs as escape sequences.
- Comments say why and cite the measurement.
- No absolute home paths, private project names or references to people in shipping code.
- Ported code keeps its original licence notice.
- Do not wrap a native command in `2>&1` under PowerShell 5.1.
- Nothing outside `hosts/<name>/` names a terminal, and nothing outside `agents/<name>/` names an agent
  harness. Each port's `allowlist.txt` lists the exceptions and only shrinks;
  `test/test-host-names.ps1` fails on anything new.
- Core matches no process image name. A harness declares its image as a `processImage` line in its
  `names.txt`; which processes are its own is its adapter's to answer.
