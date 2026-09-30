module: test/harness/Isolation.ps1
replaces: YedPool/wezfleet lib/Isolation.ps1 (Start-WfIsolatedWezterm, Assert-WfIsolated, Stop-WfIsolatedWezterm)
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

## What each source held

- **comments** - `lib/Isolation.ps1`, 170 lines, 72 of them comment.
- **history** - three commits: `05a7386` (created it, alongside verified delivery and safe kill), `21950af` (the
  `@()` collapse), `a461703` (teardown must report and be asserted).
- **pull requests** - none. None of the three commits reached `main` through a pull request; they were pushed
  directly. This is a controlled null: the same file-to-pull-request search found wezfleet #10 touching
  `lib/Hooks.ps1`, and GitHub's own commit-to-pull-request lookup returned nothing for all three commits.
- **docs** - `tasks/lessons.md` (four isolation entries, 2026-08-16 and 2026-08-17),
  `planning/verified-delivery-and-safe-kill.md`, `planning/BUG-2026-09-15-restart-pane-identity.md`,
  `planning/BUG-2026-09-15-registry-record-wipe.md`, `planning/wezfleet-ssot-multi-backend-2026-09-29.md`.
- **tests** - `test_debug/test-isolation-teardown.ps1`, whose ten checks are carried below, and ten probe and
  suite scripts that use the module.

### L-001 One definition, dot-sourced everywhere; a second copy is how the safety property rots
- source: YedPool/wezfleet lib/Isolation.ps1:3-6
- disposition: comment
- where: test/harness/Isolation.ps1 :: "Every script that needs an isolated terminal dot-sources this file"

### L-002 Isolation is a separate instance with its own mux, never a separate window
- source: YedPool/wezfleet tasks/lessons.md "a separate WINDOW is not isolation" (2026-08-16); lib/Isolation.ps1:11-15
- disposition: test
- where: test/e2e/e2e-isolation.ps1 :: "it is isolated, measured: exactly one pane, in its own window"

### L-003 The pin is WEZTERM_UNIX_SOCKET, not --class; measured 1 pane pinned against 13 unpinned
- source: YedPool/wezfleet tasks/lessons.md "--class looks like isolation and is not; the socket is the pin"
- disposition: comment
- where: test/harness/Isolation.ps1 :: "THE PIN IS WEZTERM_UNIX_SOCKET, NOT --class"

### L-004 The pin is inherited by child processes, so every later call is pinned without being told
- source: YedPool/wezfleet lib/Isolation.ps1:21-22
- disposition: comment
- where: test/harness/Isolation.ps1 :: "It is inherited by children"

### L-005 --always-new-process stops the launch attaching to the running GUI
- source: YedPool/wezfleet lib/Isolation.ps1:41-42
- disposition: comment
- where: test/harness/Isolation.ps1 :: "always-new-process stops it attaching to the running GUI"

### L-006 --skip-config is load-bearing: a fresh mux otherwise restores the user's real sessions or blocks on a prompt
- source: YedPool/wezfleet tasks/lessons.md "a fresh mux inherits the user's config, including session restore" (2026-08-17)
- disposition: test
- where: test/e2e/e2e-isolation.ps1 :: "it is isolated, measured: exactly one pane, in its own window"

### L-007 A new instance is found by diffing wezterm-gui pids before and after the launch
- source: YedPool/wezfleet lib/Isolation.ps1:36-39,56-57
- disposition: test
- where: test/e2e/e2e-isolation.ps1 :: "an isolated instance started and answered"

### L-008 Unpin while the instance is not answering; a half-open socket is where a safe call reaches the user
- source: YedPool/wezfleet lib/Isolation.ps1:68-71
- disposition: comment
- where: test/harness/Isolation.ps1 :: "UNPIN rather than leave this process aimed at a half-open socket"

### L-009 Isolation is proved by measurement, never by having just set a variable
- source: YedPool/wezfleet lib/Isolation.ps1:79-84
- disposition: test
- where: test/test-isolation.ps1 :: "pointed at the live terminal, the isolation check refuses"

### L-010 The CLI's JSON arrives as lines and must be joined before it is parsed
- source: YedPool/wezfleet tasks/lessons.md "`& wezterm --format json` returns LINES, and PS 5.1 mangles them" (2026-09-02)
- disposition: test
- where: test/test-isolation.ps1 :: "assign first, then wrap: three panes stay three"

### L-011 Assign first, then wrap: @() around the pipeline collapsed 29 panes to 1 and disarmed the guard
- source: YedPool/wezfleet commit 21950af; lib/Isolation.ps1:95-99
- disposition: test
- where: test/test-isolation.ps1 :: "CONTROL: wrapping the pipeline in @() really does collapse three panes into one here"

### L-012 Zero panes is unknown, never an empty terminal
- source: YedPool/wezfleet lib/Isolation.ps1:101
- disposition: test
- where: test/test-isolation.ps1 :: "zero panes is refused as unknown, never treated as an empty terminal"

### L-013 More than one window means the user's terminal; a heuristic, and named as one
- source: YedPool/wezfleet lib/Isolation.ps1:102-107
- disposition: test
- where: test/test-isolation.ps1 :: "panes across two windows are refused as the user's terminal"

### L-014 New in Horde: a hand-built instance whose socket and pid disagree is refused
- source: YedPool/wezfleet lib/Isolation.ps1:58, where the socket is built as gui-sock-<pid> but never checked back
- disposition: test
- where: test/test-isolation.ps1 :: "a hand-built instance whose socket names a different pid is refused"

### L-015 Teardown returns a verdict, so a caller asserts rather than hopes
- source: YedPool/wezfleet commit a461703; lib/Isolation.ps1:112-113
- disposition: test
- where: test/test-isolation.ps1 :: "passing no instance returns a refusal, not a claim that something stopped"

### L-016 With no instance, the verdict is not "stopped", because nothing was verified
- source: YedPool/wezfleet test_debug/test-isolation-teardown.ps1 "and that verdict is NOT 'stopped', because nothing was verified"
- disposition: test
- where: test/test-isolation.ps1 :: "and it says nothing was verified"

### L-017 A terminal that is already gone reads as stopped, not as survived
- source: YedPool/wezfleet test_debug/test-isolation-teardown.ps1 "a pid that is already gone reads as stopped"
- disposition: test
- where: test/test-isolation.ps1 :: "a valid instance whose terminal is already gone reads as stopped"

### L-018 The 2026-09-29 leak was a name: a probe called a teardown that did not exist
- source: YedPool/wezfleet commit a461703; lib/Isolation.ps1:122-126
- disposition: test
- where: test/test-isolation.ps1 :: "every script that starts an instance calls Stop-HordeIsolatedWezterm by its real name"

### L-019 No isolated run without a teardown that is asserted to have run, and runs whatever happened before it
- source: YedPool/wezfleet planning/wezfleet-ssot-multi-backend-2026-09-29.md:209
- disposition: test
- where: test/e2e/e2e-isolation.ps1 :: "when the scenario fails midway, teardown still runs and leaves nothing"

### L-020 Killing a terminal is not evidence that what ran in it died
- source: YedPool/wezfleet commit a461703 (instances "and their claude sessions" survived, about 590 MB); planning/wezfleet-ssot-multi-backend-2026-09-29.md section 9 (an agent outlived its editor and every kill tried)
- disposition: test
- where: test/e2e/e2e-isolation.ps1 :: "nothing that ran inside it is still running"

### L-021 Measured 2026-09-29: killing the isolated wezterm-gui took its children with it
- source: this module's own end-to-end run - the walker found a long-lived child inside the instance's tree before the kill, and 0 afterwards
- disposition: comment
- where: test/harness/Isolation.ps1 :: "wezterm-gui took its children with it"

### L-022 Unpin first on teardown, so nothing afterwards talks to a dying socket
- source: YedPool/wezfleet lib/Isolation.ps1:137-139
- disposition: comment
- where: test/harness/Isolation.ps1 :: "UNPIN FIRST, so nothing after this point talks to a socket"

### L-023 The socket file outlives its process and must be removed
- source: YedPool/wezfleet lib/Isolation.ps1:141-142
- disposition: test
- where: test/e2e/e2e-isolation.ps1 :: "its socket file is removed"

### L-024 Say a leak where a human will see it
- source: YedPool/wezfleet lib/Isolation.ps1:157-162
- disposition: comment
- where: test/harness/Isolation.ps1 :: "SAY IT WHERE A HUMAN WILL SEE IT"

### L-025 A surviving instance makes two WezTerms, and code that assumes one breaks
- source: YedPool/wezfleet lib/Isolation.ps1:117-120, where a leaked instance made guiCount 2 and four test-wezfleet assertions went red
- disposition: test
- where: test/e2e/e2e-isolation.ps1 :: "and no extra WezTerm was left behind"

### L-026 A separate mux does not separate the stores, so Horde points its own state at a throwaway one
- source: YedPool/wezfleet planning/BUG-2026-09-15-restart-pane-identity.md:107-109
- disposition: test
- where: test/e2e/e2e-isolation.ps1 :: "Horde's own state points at a throwaway store while it runs"

### L-027 An agent started in the isolated terminal still writes the agent's own real state
- source: YedPool/wezfleet planning/BUG-2026-09-15-restart-pane-identity.md:107-109
- disposition: comment
- where: test/harness/Isolation.ps1 :: "WHAT IS NOT ISOLATED, said plainly"

### L-028 Teardown restores the environment registration recorded, not what the object handed to it says
- source: YedPool/wezfleet lib/Isolation.ps1:24,61, where a second harness in one process would overwrite the first one's saved socket
- disposition: test
- where: test/test-isolation.ps1 :: "teardown restores the environment registration recorded, not what the object handed to it says"

### L-029 An isolated instance isolates a test; it cannot isolate anything aimed at the live fleet
- source: YedPool/wezfleet planning/verified-delivery-and-safe-kill.md:98-101
- disposition: comment
- where: test/harness/Isolation.ps1 :: "It cannot isolate anything aimed at the live fleet"

### L-030 A [string] parameter defaulted to $null arrives as an empty string
- source: YedPool/wezfleet planning/BUG-2026-09-15-registry-record-wipe.md:113-116
- disposition: dropped
- reason: No parameter in this module defaults a string to null, so it cannot occur here; it belongs among CONTRIBUTING's PowerShell traps, and is recorded for that follow-up.
