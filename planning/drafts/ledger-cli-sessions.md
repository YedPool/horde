DRAFT - not a ledger yet. Kept outside planning/ledger/ because its test dispositions cite suites
that do not exist; test/test-ledger.ps1 would fail on it there. Its command's first PR (steps 9-11 of
planning/execution-plan-phase-3.md) deletes this paragraph and the next, moves the file to
planning/ledger/cli-sessions.md, and adds the tests in the same PR.

Adapted from the research: comment dispositions point at `cli/Sessions.ps1` (logic beside the declaration). L-015 is phrased through the engine port, so the core suite names no engine; the fixture that proves it for a particular engine lives under that engine's `agents/<name>/test/`. L-018 is carried by CONTRIBUTING rule 6, which outlives the shadow harness.

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

### L-015 The population is every running session, whatever agent engine runs it
- source: YedPool/wezfleet lib/MailPump.ps1:56-66 reads one engine's control files only, so another engine's sessions never appear; horde schema/session-view.v1.json description "One session per sessionId any store knows" (feature/core-projection)
- disposition: test
- where: test/test-sessions.ps1 :: "a running session from a second engine is listed beside the first"
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
- where: CONTRIBUTING.md :: "Verify against the shipped command"
### L-019 Status and pid are the session's own report, checked against the process it describes
- source: YedPool/wezfleet test_debug/test-fleet-sessions.ps1:52-54; lib/MailPump.ps1:62-63; horde planning/parity-2.3.md P-05
- disposition: test
- where: test/test-sessions.ps1 :: "the status column is unknown when the process is not the one described"
