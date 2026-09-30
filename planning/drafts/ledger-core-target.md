DRAFT - not a ledger yet. Kept outside planning/ledger/ because its test dispositions cite suites
that do not exist; test/test-ledger.ps1 would fail on it there. Its command's first PR (steps 15-18 of
planning/execution-plan-phase-3.md) deletes this paragraph and the next, moves the file to
planning/ledger/core-target.md, and adds the tests in the same PR.

Adapted to decision 7: L-013, L-014, L-015 and L-017 now require a verified handle (L-015 and L-017 were dropped in the research, L-013 and L-014 said the opposite); step 18 reverses L-013, L-014 and L-017 later. L-016 is dropped with allowance G-01 named. L-009 cites decision 6; L-021 and L-022 cite wezfleet issues #18 and #19.

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
