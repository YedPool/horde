# Handoff: orchestrator D (laptop) to the Horde/wezfleet session on the office PC (always-on)

Written 2026-10-07 by orchestrator D on the founder's laptop (YEDIDYA), at the founder's instruction
(relayed by M): all imLev work goes ahead of Horde, D is closed, and Horde/wezfleet work continues on
the OFFICE device, the always-on PC (DESKTOP-TJQJGTM, Windows user `yagdil`).

Everything referenced here is pushed to GitHub (YedPool/horde, YedPool/wezfleet). Supporting tools
are in `planning/handoff-2026-10-07/` on this branch (`docs/handoff-d-to-office`).

## 0. Standing rules carried over (the laptop's memory files do not travel)

- **Founder's top priority (since 2026-10-05):** cross-PC orchestration end to end. Proof = M on the
  laptop starts an orchestrator on the always-on box, messages it, gets its reply and closes it, all
  through Horde, with Remote Control on and the session named. Acceptance is issue #107.
- **Review, test and merge PRs yourself.** Decisions only the founder can make go to the founder as
  numbered, self-contained one-liners.
- **Merging:** only `gh pr merge --merge --match-head-commit <sha>`, never squash. Test the COMBINED
  tree (main + the PRs, merged in order), then merge in that order, then verify
  `git rev-parse origin/main^{tree}` equals the tree you tested. Branch-green is not main-green.
- **Merge policy since 2026-10-07:** only correctness or safety findings block; everything else is
  filed as an issue.
- **The other session ("the decisions lane", on the fleet PC, commits as `yedpool`).** Never push to,
  rewrite or force-push a branch holding its commits. Fetch before every push. Agreed 2026-10-07:
  orchestrator D is the ONLY merger into horde main; the decisions lane marks a PR ready when it is
  reviewed and green and the batch takes it in. The office session inherits that role. It owns
  horde #106 (wezfleet messenger), #110 (decisions store) and wezfleet PR 70, plus the folders
  decisions/, surfaces/, platform/windows/, fleet/, and core/Fingerprints.ps1, SessionSeat.ps1 and
  HostWindow.ps1. It cannot reach the always-on box; run its branches for it on request.
- **Tests:** never run `-WithPanes` or anything that spawns/kills panes against a terminal holding
  work; isolation = a separate WezTerm instance pinned by `WEZTERM_UNIX_SOCKET`, `--skip-config`,
  `--no-auto-start`. Never write to `~/.claude`, `~/.codex`, `~/.gemini` in tests. Never touch the
  sshd SERVICE, the firewall, `~/.ssh` or `ProgramData\ssh` in tests (Horde's suites run their own
  child sshd on 127.0.0.1). Kill only processes you started, verified by pid + start time.
- **No real Claude sessions from probes.** A 2026-10-05 probe started 4 real sessions on the founder's
  login: do an in-pane env check first, never answer prompts in tests.
- **ASCII only** in source. **PowerShell 5.1 traps:** `$input` at script top level makes the host wait
  for stdin EOF (use `[Environment]::Exit` in such scripts); variable names ignore case (`$transport`
  overwrites a `[string]$Transport` parameter - `tools/ParamShadow.ps1` now guards it); .NET Console
  stdin is dead inside Windows OpenSSH sessions (`$input` works); a pane gets the environment of the
  process that runs `wezterm cli spawn`; never `2>&1` a native command.
- **Never block or poll.** Long runs go to background jobs ending in a `DONE=<exit>` sentinel line;
  read the finished log, never tail a gate's status.

## 1. What landed today (horde main = a3b9b35, tree f7b3dd2)

| PR | What | Merge |
|---|---|---|
| #126 | A4: `horde session` - the hub asks a node to start/close a session, once per request id | 07a2dd2 |
| #112 | R21 slice 4: node side of cross-PC messaging (deliver, delivery.status, mail.next, mail.receipt) | batch 21 |
| #121 | R16 sshd test-harness hardening | batch 21 |
| #131 | WezTerm Own hardening: junctions on the profile path and non-local drives refused (#119) | batch 21 |
| #111 | R17b enrolment (node key, hub pin, admitted keys) + `tools/ParamShadow.ps1` guard | a3b9b35 |

Earlier on 2026-10-05..07 (already on main): A1-A3 act path, R0-R16 remote steps, metrics M1/M2,
engines E0-E4, hosts 5, lifecycle 5, schema work, Mutate -Changed.

wezfleet: main is dc901ae. wezfleet PR 70 (the decisions lane's fix of issue #69, the mail-post
wrong-pane bug) is APPROVED by D; the decisions lane merges it. Follow-ups are wezfleet issue #71.
Archive branches kept for the decisions lane (delete once it confirms it has lifted them):
wezfleet `archive/mail-post-review-65-c4a17e4`, horde `archive/wezfleet-messenger-g1-g7-eaca175`.

## 2. What is open, in order

### 2.1 Batch 22 - all four approved, gate half done
Combined tree: main a3b9b35 + #120 (59ad2c8) + #146 (134304c) + #138 (f5a5d2e) + #139 (82f1f7a)
= tree **e0baaaf3fc85e86ce3b17ea7936bfdb9256ef2ce**, merged in that order with no conflicts.
- Remote (pure) suites: **79 green** (DONE=0).
- Mutation specs: stopped at spec 7 of 10 by the pause - **rerun all 10**.
- Local machine-bound suites + specs: **never ran** (stopped while queued) - **run them**.
Scripts: `planning/handoff-2026-10-07/batch22/` (suite and spec lists; paths are the laptop's).
Merge order after green: #120, #146, #138 (base main), then #139 (base is #138's branch; retarget to
main after #138 merges, or merge #138 first and GitHub will retarget), then verify the tree.
- #120 hub serve held-reason + bound timing (follow-ups #145).
- #146 R17a hub listener: `horde listen` (own child sshd on 127.0.0.1), `cli/attach.ps1` forced
  command, hub pipe user-only ACL (SYSTEM deliberately not admitted). Security review approved.
- #138 R17c-1/2: hub accepts dialled links bound by the attach preamble; `node serve -Dial`. Also
  FIXES a read-only bug on main (a node given an act handler AND -ReadOnly acted). Follow-ups #144.
- #139 R17c-3: ssh `dial.out` and `auth.peer` proven live. Follow-ups #143.

### 2.2 Next batch
- **#93** reaper slice RA (idle readers), head 0a84bad: APPROVED after two re-reviews (fails closed
  on unrecognised background launches). Follow-ups #148. One comment failed to post (GitHub API
  error) - post it to #148: "the wording fallback causes false HOLDs: 57 results in 30 days (45
  Bash/PowerShell outputs whose first line contains 'background', 4 Edit/Write confirmations, 2
  failed SendMessages); narrow it by applying the wording rule only to non-shell tools and exempting
  Edit and Write; RC's report should list sessions held this way."
- **R17a hardening**, branch `feature/remote-r17a-hardening` head 3c422ef (pushed, NO PR yet),
  stacked on #146. Issue #147 items 1-4 and 6-8 plus a 320 MiB per-process job memory cap (measured:
  attach relaying peak 207 MB; a never-ending line is killed at ~126 MiB). Green on the always-on box
  (13 suites + link-binding, listen specs) and test-listen-local. NOT done: local `Mutate -Changed`.
  On resume: rebase onto main after #146 merges; run test-local, test-transport-conformance,
  test-listen-local, test-node-serve-local, test-hub-serve-local, then `tools\Mutate.ps1 -Changed
  origin/main`; rerun the touched remote suites; open the PR; review it; batch it.

### 2.3 Then the cross-PC finish line
1. **R17d** - first live end-to-end over a reverse tunnel with the always-on box as a node. Not
   started; needs #146 + #138 + #139 merged. Before real network exposure also land #144 items 2-3
   (dialled-link starvation, enrolled-only binding at the hub) and #147 items 1, 2, 4.
2. **#107** - live acceptance: M on the laptop does start / message / reply / close on the always-on
   box through Horde. This is the moment the feature exists for the founder.

### 2.4 Other open PRs
- **#115** Mutate sections (run each mutant only on the suite sections that kill it; link-contract
  3306 s -> 483 s), head 6b002c8: **BLOCKED** on one finding - a sectioned CATCH is never confirmed
  against the whole suite, so a mutant on a cold-cache path can read caught when the whole suite says
  survived (reproduced). Fix: confirm sectioned catches with the whole suite whenever a map is new or
  changed (e.g. a -VerifyMaps mode Mutate -Changed triggers) and correct the header claim "A MAP CAN
  NEVER HIDE A SURVIVOR". Follow-ups #137. Its builder was told to park; its last state is unknown -
  check `git log origin/perf/mutate-sections` before continuing. Stacked on it: #127, #128, #129,
  #133, #134, #135, #136 (each spec 2-6x faster); retarget to main after #115 merges.
- **#110, #106** - the decisions lane's. Review when it marks them ready, then batch.
- **#61** (workflows plan, docs) and **#28** (install shim) - older, untouched today.

### 2.5 Issues filed today worth knowing
#130 ParamShadow gaps, #132 Own hardening leftovers, #137 suite sections, #140 Act.ps1 UTF-8,
#141 JSON duplicate-key scan, #142 86/151 pane session files refused (fleet PC), #143 #144 #145
#147 #148 above, #149 (the decisions lane's gate proposal).

## 3. The always-on (office) PC - setup state as of 2026-10-07

Verified over ssh today (user `yagdil`, host DESKTOP-TJQJGTM):
- `C:\Users\Yagdil\Documents\Code\imadi` - the imLev clone, with `.env.local` and `.env.prod`
  (founder approved secrets on this device). Head 3d9a16fa.
- `C:\Users\Yagdil\bin\wezfleet` - wezfleet clone at dc901ae; `install.ps1` has run.
- `C:\Users\yagdil\horde-ci` - where D's remote gate ran horde suites (runs under `runs\<label>`).
- **Horde itself is NOT cloned there.** Clone it (command below).
- gh (logged in as YedPool only), vercel (logged in as yedidyapool-1305), claude
  (`C:\Users\Yagdil\.local\bin\claude.exe`, founder did `/login` on the device), WezTerm, git, node.
- `~/.claude` bundle (skills, hooks, settings) was copied from the laptop.
- 13 GB RAM, does not EcoQoS-throttle (the laptop does, ~7x after 3 s).

## 4. Credentials

- Rotating OAuth tokens are PER MACHINE. **Never copy them between the office PC and the laptop, in
  either direction**: Claude's `.credentials.json`, Vercel's `auth.json`, gh tokens. Copying the
  laptop's Vercel auth.json to the device on 2026-10-06 rotated the token and logged the laptop out.
  Log in on each machine separately.
- Secrets (`.env.*`) on the office PC are approved by the founder. Do not push them anywhere.

## 5. The laptop

- The laptop's sshd is **stopped and disabled** (installed 2026-10-05, service Stopped/Disabled,
  firewall rule disabled, nothing on port 22). Anything that needs to dial BACK to the laptop (the
  laptop as a node, or ssh from the office PC to the laptop) will not work until the founder
  re-enables it. The laptop reaches the office PC as ssh host alias `always-on`.
- `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1` is set on the laptop (setx) so Claude Code's memory
  reaper stops killing background waiters; it takes effect after WezTerm restarts.
- D's worktrees were under `C:\Users\yedid\bin\horde-worktrees`; everything with work in it is pushed.

## 6. Gate tooling (in `planning/handoff-2026-10-07/tools/`)

- `remote-gate.ps1` ran a list of suites at one exact commit on the always-on box over ssh from the
  laptop (`-RemoteHost always-on`, root `C:\Users\yagdil\horde-ci`), detached, with a DONE marker.
  On the office PC itself you do not need ssh: run suites directly as background jobs, or point the
  script at localhost if useful.
- `remote-mut.ps1` - the same for named mutation specs.
- `gate-lock.ps1` (v7) - a machine-wide lock for machine-bound suites (pipes, sshd, panes): one at a
  time; a terminating error exits 97; `-MaxMinutes` (default 120) kills the child tree and exits 98.
  Its test is `gate-lock.test.sh` (20/20). Pure suites do NOT need the lock.
- Machine-bound suites are listed in `test/lib/SuiteFiles.ps1`; they need an interactive logon.

## 7. First three commands on the office PC

```
gh repo clone YedPool/horde C:\Users\Yagdil\bin\horde
git -C C:\Users\Yagdil\bin\horde fetch origin docs/handoff-d-to-office ; git -C C:\Users\Yagdil\bin\horde show origin/docs/handoff-d-to-office:planning/HANDOFF-D-to-office-2026-10-07.md
gh pr list -R YedPool/horde --state open
```

Then: create `C:\Users\Yagdil\bin\horde-worktrees`, build batch 22's tree there (section 2.1), run
the 10 mutation specs and the machine-bound suites, and merge if green. Ask the founder before
re-enabling anything on the laptop.
