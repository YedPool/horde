module: core/ownership
replaces: YedPool/wezfleet lib/Protocol.ps1 (Get-WfRunSnapshot pane and transcript precedence), lib/Registry.ps1 (Get-WfPaneIndex, Get-WfPaneIdentity, Find-WfLivePaneForSession, Resolve-WfFleetTarget, Get-WfFleetCensus source order), lib/Common.ps1 (Resolve-WfRunForSession, instance validity), lib/Mail.ps1 (Get-WfMailSelfId order) - the read orders only, recorded as data; no code is replaced yet
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

## What each source held

- comments: the precedence rules are stated in the code that applies them, cited per entry below.
- history: 4947d8c, 0e1c75a, d8449ea, f09f4e1, debac69, b54e331, 7631802, 88aab20, 1e8837a, 0a26496.
- pull requests: #9 (open) proposes a third writer of pane-sessions files; #11 carries the codex TTL rule.
- docs: planning/BUG-2026-09-15-restart-pane-identity.md; tasks/lessons.md:359 and :385.
- tests: test_debug/audit-state-sources.ps1:34 still describes the pane order as it used to be.

### L-001 Pane has three stored copies and one read order across them
- source: YedPool/wezfleet lib/Protocol.ps1:522-537 and 4947d8c "Three sources, weakest first, each overriding the last ... The registry wins when it has a FRESH answer, and is ignored otherwise"
- disposition: test
- where: test/test-ownership.ps1 :: "pane, stored three times in wezfleet, has one read order across all of them"

### L-002 A pane number is a host handle, never an identity
- source: YedPool/wezfleet lib/Common.ps1:507-527 and 0e1c75a, after a restart census named the wrong session for six of ten live panes; planning/BUG-2026-09-15-restart-pane-identity.md
- disposition: test
- where: test/test-ownership.ps1 :: "pane is owned by the host and is never identity"

### L-003 The transcript path is derived, not stored, because stored paths rot
- source: YedPool/wezfleet lib/Registry.ps1:30-33 "DERIVED, NEVER STORED ... A path is a snapshot that can rot"; three callers used three different orders (Activity.ps1:212-221, Protocol.ps1:544-569)
- disposition: test
- where: test/test-ownership.ps1 :: "the transcript path is derived, never trusted as stored"

### L-004 Owner is a name derived from the parent; the parent id is the edge
- source: YedPool/wezfleet commands/own.ps1:51-60 and 1e8837a: a session assigned by name appeared owned in census and unowned in tree
- disposition: test
- where: test/test-ownership.ps1 :: "owner is a derived display name; parent is the edge"

### L-005 A rule that rests on something unmeasured is marked provisional, not encoded as fact
- source: the installed wezterm-resurrect takes the session id from the saved argv first and its main branch from the pane-sessions file first (plugin/resurrect/process_handlers.lua:282-299 on main); and whether a session id changes on compaction is asserted by YedPool/wezfleet lib/Mail.ps1:116 but contradicted by one observation on 2026-09-29
- disposition: test
- where: test/test-ownership.ps1 :: "a rule that depends on something unmeasured is marked provisional"

### L-006 Every field has one future owner, so no second writer can disagree with it
- source: horde planning/migration-plan.html step 0.6 "Every field has exactly one owner and one precedence rule"
- disposition: test
- where: test/test-ownership.ps1 :: "every field has exactly one owner and one read rule"

### L-007 A field owned by two things is the defect this table exists to prevent
- source: YedPool/wezfleet owner and parent stored one relation twice and disagreed until 2026-09-14 (1e8837a)
- disposition: test
- where: test/test-ownership.ps1 :: "a field with two owners is refused"

### L-008 Role is Horde's own fact, read from the registry before a pending claim
- source: YedPool/wezfleet lib/Master.ps1:118-137 (a pending master claim counts as a master); lib/Registry.ps1:1261 (claims carry role)
- disposition: test
- where: test/test-ownership.ps1 :: "role is owned by horde's engine and read from the registry first"

### L-009 A pane-sessions file can be hijacked by a session with an inherited pane number
- source: YedPool/wezfleet f09f4e1: a session started with an inherited WEZTERM_PANE=27 wrote 27.json claiming another session's pane; the proposed tie-break by live control file is unimplemented
- disposition: dropped
- reason: The table records the condition in pane's read rule, but detecting a hijack is core/identity's job and belongs in that module's ledger with this commit cited.

### L-010 Acting on a pane - typing or killing - trusts the registry alone
- source: YedPool/wezfleet lib/Registry.ps1:736-755 "REGISTRY ONLY. A pane-sessions file can name this session in a live pane and still not justify typing into it"
- disposition: dropped
- reason: This is the policy of the TerminalPort verbs that act on a pane, not of reading; it belongs in the TerminalPort ledger, where kill and send are ported.

### L-011 A fresher registry record does not outrank a dead session's newer one without the retired flag
- source: YedPool/wezfleet lib/Registry.ps1:365-398 (newest lastSeen wins, retired skipped) "the dead session may genuinely have the newer record"
- disposition: dropped
- reason: Choosing among several records that claim one pane is the projection's rule (execution plan step 13) and belongs in its ledger.

### L-012 The project directory is fixed at start; the current directory is not the transcript key
- source: YedPool/wezfleet lib/Registry.ps1:332-343 and d8449ea; census still derives the transcript from the current cwd at lib/Registry.ps1:861 and :872
- disposition: comment
- where: core/ownership.json :: "a record older than firstCwd"

### L-013 Self-identity and other-identity read the environment in opposite orders
- source: YedPool/wezfleet lib/Protocol.ps1:355-365 (for another pane the file wins, because the variable is inherited) against lib/Mail.ps1:75-97 and 88aab20 (for oneself the variable comes first)
- disposition: comment
- where: core/ownership.json :: "only for a session asking who it is itself"

### L-014 A codex status past its TTL is unknown, except ended
- source: YedPool/wezfleet lib/CodexStatus.ps1:236; PR #11
- disposition: comment
- where: core/ownership.json :: "within its TTL, except ended, which never expires"

### L-015 The event log is the truth and status.json only its cache
- source: YedPool/wezfleet lib/Protocol.ps1:58-60
- disposition: comment
- where: core/ownership.json :: "the log is the truth; status.json is only its cache"

### L-016 A pending roster entry is not a spawned session
- source: YedPool/wezfleet lib/Common.ps1:307-352 and 0a26496 "A pending entry has spawned=$false and pane=-1 ... yet it counted as a candidate"
- disposition: comment
- where: core/ownership.json :: "false means pending"

### L-017 A stale record that matches is not confirmation
- source: YedPool/wezfleet tasks/lessons.md:385 "a guard that fails TOWARD the destructive action"; lib/Protocol.ps1:650-677 and debac69
- disposition: dropped
- reason: Freshness of the record that would confirm a finished session is cleanup's rule and belongs in the cleanup ledger; the unknown-is-not-fresh half is core-tristate L-013.

### L-018 The directory guard on pane-sessions barely discriminates
- source: YedPool/wezfleet tasks/lessons.md:359 "150 records, 141 of them - 94% - share the IDENTICAL cwd"; 7631802
- disposition: dropped
- reason: Which evidence may confirm a pane-sessions record belongs to core/identity, which will read it; time of writing against the instance start is the guard to port.

### L-019 wezterm-resurrect saves a pane as an agent whenever a record exists, with no freshness check
- source: wezterm-resurrect plugin/resurrect/pane_tree.lua:144-157 and its commit dac0011
- disposition: dropped
- reason: What a layout save records is the LayoutPort's concern (execution plan step 4); layout is advisory, so the table lists R1 only as a shadow source for the resume command.

### L-020 wezfleet startup never runs under the current terminal config
- source: .wezterm.lua:14-15 calls resurrect.setup, so the branch holding the wezfleet startup call is dead; after a restore registry panes read unknown until each session's next tool call
- disposition: dropped
- reason: A defect in the user's terminal configuration, not in any rule Horde reads by; reported to the founder separately on 2026-09-29.

### L-021 Two masters is a finding, never resolved by timestamp
- source: YedPool/wezfleet lib/Hierarchy.ps1:70-87 "picking by timestamp will eventually pick wrong silently"
- disposition: dropped
- reason: Cardinality is the projection's finding (execution plan step 13); core-roles L-017 carries it forward to that ledger.

### L-022 Identity survives renames only through the resume id set
- source: wezterm-resurrect installed save_index.lua:6-20 and commit ccb2e67: "947 saves that were only 331 distinct conversations"
- disposition: dropped
- reason: Deduplicating saves is the restore planner's concern (execution plan step 4) and belongs in its ledger.

### L-023 The audit script describes a pane order the code no longer uses
- source: YedPool/wezfleet test_debug/audit-state-sources.ps1:34 against lib/Protocol.ps1:522-537
- disposition: dropped
- reason: A stale description in the old system; Horde's read order is the one in core/ownership.json, and nothing in Horde reads the audit script.

### L-024 A table entry that nothing reads is dead weight that hides drift
- source: the first draft of core/ownership.json listed the environment as a store and no field read it; the gate caught it before commit
- disposition: test
- where: test/test-ownership.ps1 :: "a store no field reads is refused"

### L-025 wezfleet has two freshness rules for the registry's pane; Horde reads by census's
- source: YedPool/wezfleet lib/Registry.ps1:537 and :779 "[int]$MaxAgeSeconds = 900" measured against lastSeen (Get-WfLivePaneForFleetSession, used by the run snapshot at lib/Protocol.ps1:536; Get-WfPaneIdentity), against lib/Registry.ps1:393-394 "if ($r.retired) { continue }" and "Test-WfWrittenInInstance ... lastSeen" with no age (Get-WfPaneIndex, which census uses at :833) and :658-659, the same rule in Find-WfLivePaneForSession, which cleanup, tell and kill use to pick a pane to act on. Review finding 5, 2026-09-29.
- disposition: test
- where: test/test-ownership.ps1 :: "the registry's pane is read by census's rule, with no age limit"

### L-026 The pane-sessions file before the status snapshot is a new order, not an inherited one
- source: YedPool/wezfleet lib/Registry.ps1:833-840 (census: the registry index, else the pane-sessions file) against lib/Protocol.ps1:533-536 (run snapshot: roster, then status.json, then registry; no pane-sessions read). No function orders X1 against W5. Review finding 5, 2026-09-29.
- disposition: test
- where: test/test-ownership.ps1 :: "the order of the pane-sessions file before the status snapshot is marked as a new decision"
