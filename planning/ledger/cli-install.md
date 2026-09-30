module: cli/install
replaces: YedPool/wezfleet install.ps1 (the shims section, which writes wezfleet.cmd, wezreport.cmd, wezspawn.cmd and the `wf` POSIX entry point), and the wezfleet.cmd shim it writes
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

## What each source held

- comments: install.ps1:1-9 (re-running is safe and cheap), :80-105 (copy the module into bin),
  :107-126 (the command-log writer build), :131-162 (the shim template and why it is written from
  here), :164-182 (the `wf` POSIX entry point), :184-211 (workspace trust), :217-229 (PATH),
  :231-263 (verify). The shim itself carries the newline incident and the WEZFLEET_VIA_CMD marker.
- history: `git log --follow install.ps1` - b351601 (2026-08-17, initial import), 0d59626
  (2026-08-23, the command-log writer), d811106 (2026-09-14), 2cfdacc (2026-09-16, the
  setlocal/WEZFLEET_VIA_CMD shim and `wf`, "the hand-edited shim would have been reverted by the
  next install with nobody noticing"), 561466d (2026-09-29, an installed copy lacked LICENSE).
- pull requests: `gh pr list --repo YedPool/wezfleet --state all` filtered to those touching
  install.ps1 - #1 (liveness, the command-log writer) and #17 (the LICENSE copy). The shim change
  itself, 2cfdacc, was committed to main directly.
- docs: tasks/lessons.md, "2026-08-17 - cmd.exe cuts an argument at the first newline";
  planning/wezfleet-ssot-multi-backend-2026-09-29.md:182-186 (WEZFLEET_VIA_CMD changes no
  behaviour); planning/wezfleet-architecture.md:47-49 and :229 (the shims, "verify PATH resolution").
- tests: no suite tests install.ps1 or the shim it writes. test_debug/probe-shim-vs-direct.ps1 is a
  probe that measured delivery through the shim against a direct call; test-sendtext-guard.ps1 tests
  the hook that refuses a multi-line `tell` on the shim path, which is wezfleet's, not the shim's.

### L-001 An installer that rewrites its shim from a template silently destroys a hand edit
- source: YedPool/wezfleet install.ps1:136 "THE SHIM IS WRITTEN FROM HERE, so anything hand-edited into bin\wezfleet.cmd is destroyed by the next install", and commit 2cfdacc
- disposition: test
- where: test/test-install.ps1 :: "and the edited shim is left exactly as it was"

### L-002 A file the installer did not write is not the installer's to replace
- source: YedPool/wezfleet install.ps1:159, `WriteAllText` over whatever is at bin\<name>.cmd with no check of what was there
- disposition: test
- where: test/test-install.ps1 :: "and it is left exactly as it was"

### L-003 A newline cannot pass through a .cmd shim: the argument arrives as its first line, silently
- source: YedPool/wezfleet tasks/lessons.md, "2026-08-17 - cmd.exe cuts an argument at the first newline" (63 characters on three lines arrived as 20 on one); the shim's own comment, 111 characters / 3 lines arriving as 49 / 1 (2cfdacc)
- disposition: test
- where: test/test-install.ps1 :: "a two-line argument through the shim arrives as its first line only"

### L-004 The shim cannot see what was cut, so the limit is stated where the caller will read it
- source: YedPool/wezfleet install.ps1:145 "The shim cannot detect it - by the time it runs the text is gone"
- disposition: test
- where: test/test-install.ps1 :: "the shim states that a newline cannot pass through it"

### L-005 The WEZFLEET_VIA_CMD marker tells the program the call came through cmd
- source: YedPool/wezfleet install.ps1:149 and the shim's own comment; planning/wezfleet-ssot-multi-backend-2026-09-29.md:184 "WEZFLEET_VIA_CMD appears in exactly ONE place in the codebase, stamping the delivery record. It changes no behaviour."
- disposition: dropped
- reason: No horde command takes free text yet, so nothing would read a marker; wezfleet's own later review found its marker changed no behaviour, and a mechanism with no reader is the failure CONTRIBUTING 1 cites. The first command that takes free text adds the marker together with the code that reads it.

### L-006 The shim's exit code must be the program's exit code
- source: YedPool/wezfleet install.ps1:151 `endlocal & exit /b %ERRORLEVEL%`, the form that carries the code out through endlocal
- disposition: test
- where: test/test-install.ps1 :: "an unknown command exits 2 through the shim"

### L-007 The shim is written as ASCII
- source: YedPool/wezfleet install.ps1:159, `WriteAllText(..., New-Object System.Text.ASCIIEncoding)`
- disposition: test
- where: test/test-install.ps1 :: "the shim is ASCII"

### L-008 Re-running the installer after a git pull is safe and cheap
- source: YedPool/wezfleet install.ps1:9 "re-running after a git pull is safe and cheap"
- disposition: test
- where: test/test-install.ps1 :: "and changes nothing, not even the file's timestamp"

### L-009 A dry run says what it would do and changes nothing
- source: YedPool/wezfleet install.ps1:5 "-WhatIf say what it would do and change nothing"
- disposition: test
- where: test/test-install.ps1 :: "and creates nothing, not even the bin folder"

### L-010 The default bin folder is the one under the user's profile
- source: YedPool/wezfleet install.ps1:12 `[string]$BinDir = (Join-Path $env:USERPROFILE "bin")`
- disposition: test
- where: test/test-install.ps1 :: "with no -BinDir, the shim goes to the bin folder under USERPROFILE"

### L-011 A bin folder not on PATH is reported, and PATH itself is never edited
- source: YedPool/wezfleet install.ps1:217-229, and 561466d "its one PATH command is printed for the user, never run"
- disposition: test
- where: test/test-install.ps1 :: "install warns when the bin folder is not on PATH"

### L-012 A copy of the module in bin goes stale and misses files the copy list forgot
- source: YedPool/wezfleet 561466d (YedPool/wezfleet#17), "The list had README.md and ORCHESTRATOR.md but not LICENSE"
- disposition: comment
- where: cli/Install.ps1 :: "THE SHIM POINTS AT A CHECKOUT; IT COPIES NOTHING"

### L-013 The installer checks for the terminal and for claude on PATH before it installs
- source: YedPool/wezfleet install.ps1:42-67
- disposition: dropped
- reason: horde install writes a launcher and nothing else; horde's commands that need a host or an agent check for it when they run, and naming a terminal here would break the host rule of CONTRIBUTING 14.

### L-014 The command-log writer is built at install time, never committed as a binary
- source: YedPool/wezfleet install.ps1:107-111, 0d59626 (YedPool/wezfleet#1)
- disposition: dropped
- reason: Horde has no hook binary to build; when it has one, the lesson belongs to the command that builds it, not to the launcher.

### L-015 Folders the fleet works in are pre-trusted at install, or a session stops on a prompt
- source: YedPool/wezfleet install.ps1:14-16 and :184-186
- disposition: dropped
- reason: Workspace trust is about starting agent sessions, which horde install does not do; it belongs to the spawn step of the migration plan, which will carry it.

### L-016 Running the test suite from inside the installer stalled, so verify is opt-in
- source: YedPool/wezfleet install.ps1:246-247 "Launching the suite from inside this script nests PowerShell two deep and was observed to stall"
- disposition: dropped
- reason: horde install runs no suites at all; the suites are run by hand and by review, from the checkout the shim points at.

### L-017 A POSIX entry point (`wf`) carries multi-line arguments that the .cmd shim would cut
- source: YedPool/wezfleet install.ps1:164-182, 2cfdacc
- disposition: dropped
- reason: No horde command takes multi-line text yet, and Bash can already run horde.ps1 through powershell -File; an entry point is added with the first command that needs one, and tested then.
