module: core/tristate
replaces: YedPool/wezfleet lib/Hosts.ps1 (pane number / "-" / "?"), lib/Common.ps1 (Get-WfLivePanes empty map, wezterm-unknown, unknown-* trust reasons, disk $null), lib/CodexStatus.ps1 (TTL stale -> unknown, $null vs @(), -1 vs 0, three-valued trust), lib/Delivery.ps1 (-1 unreadable, none|unread|midturn|read|unknown, found=$false), lib/Activity.ps1 (yes|no|unknown), lib/Cleanup.ps1 (unsure), lib/Kill.ps1 (-1 siblings), lib/Protocol.ps1 (livenessKnown, -1 live count, paneRecordFresh), lib/Registry.ps1 (-1 pane/age/seen, $null alive, unreadable record), lib/Mail.ps1 ("" and 0 unknown), lib/Presentation.ps1 ("" title) - each of these encodings, not their callers' policies
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

### L-001 An unreadable source is unknown, never absent
- source: YedPool/wezfleet lib/Hosts.ps1:60 "a real answer meaning UNKNOWN, never 'no panes'"; lib/Common.ps1:497-499; commit 27cfafe
- disposition: test
- where: test/test-tristate.ps1 :: "an unreadable source reads as unknown"

### L-002 Absent is a known answer, and it is never equal to unknown
- source: YedPool/wezfleet lib/Hosts.ps1:180-182 ("-" known absent vs "?" unknown); commit 27cfafe "If those were merged, an unreadable mux would make the entire fleet look like it had left the terminal"; test_debug/test-fleet-sessions.ps1:67-70
- disposition: test
- where: test/test-tristate.ps1 :: "absent and unknown are never equal"

### L-003 A three-valued answer is never rounded to two when printed or serialised
- source: YedPool/wezfleet commands/hooks.ps1:120 "A three-valued trust that prints as two values would be a lie by rounding"; test_debug/test-hooks-command.ps1:104-105; commit b83fa31
- disposition: test
- where: test/test-tristate.ps1 :: "each state renders as its own word"

### L-004 An empty known collection must not arrive as null
- source: YedPool/wezfleet lib/CodexStatus.ps1:420 promises "$null being UNKNOWN and an empty array being none", but :504-511 returns a bare @(), which PowerShell 5.1 delivers as $null (measured 2026-09-29, PS 5.1.26100.9444), so the 0 branch at :372 is unreachable
- disposition: test
- where: test/test-tristate.ps1 :: "an empty known collection stays known and empty"

### L-005 A one-element known collection stays a collection
- source: measured 2026-09-29 on PS 5.1: a function returning @(5) delivers Int32; YedPool/wezfleet tasks/lessons.md:36-45 and :293-316 (collection shape lost across the pipeline); commit 21950af
- disposition: test
- where: test/test-tristate.ps1 :: "a single known item stays a collection"

### L-006 State is carried explicitly, never inferred from an empty map
- source: YedPool/wezfleet lib/Common.ps1:484-485 (empty hashtable = unknown), lib/CodexStatus.ps1:213-218, lib/MailPump.ps1:53, lib/Protocol.ps1:463; the inference cannot represent a genuinely empty answer, and test_debug/test-codex-status.ps1:132-138 contradicts itself about which one an empty map is
- disposition: test
- where: test/test-tristate.ps1 :: "an empty known map is not unknown"

### L-007 A known zero is a real value, not a sentinel
- source: YedPool/wezfleet lib/Registry.ps1:536 "never 0 - pane 0 is a real pane", and :646-649; lib/Kill.ps1:84 "unknown, NOT zero"; lib/CodexStatus.ps1:368-370; test_debug/test-registry.ps1:364
- disposition: test
- where: test/test-tristate.ps1 :: "a known zero is not unknown"

### L-008 An empty string is a known value, not an unknown sentinel
- source: YedPool/wezfleet lib/Mail.ps1:72 ("" when it cannot tell), lib/Presentation.ps1:38-39 ("" means UNKNOWN ... never read it as the title should be empty); commit 50a6944
- disposition: test
- where: test/test-tristate.ps1 :: "a known empty string stays known"

### L-009 A known false is not absent
- source: YedPool/wezfleet commit f7a1c45 "absent and said false are distinguished, so an explicit false beats the default"; test_debug/test-codex-status.ps1:78-79 "a field Codex did not send is absent, not empty"
- disposition: test
- where: test/test-tristate.ps1 :: "a known false is not absent"

### L-010 Unknown carries the reason it is unknown
- source: YedPool/wezfleet lib/Common.ps1:876-894 (reasons unknown-no-config / unknown-unreadable / unknown-no-projects); lib/Delivery.ps1:845-850 (the refusal wording blames the reader, not the target); commands/tell.ps1:296-300; commit 46d96dc
- disposition: test
- where: test/test-tristate.ps1 :: "an unknown without a reason is refused"

### L-011 An unknown produced by an exception keeps the exception's message
- source: YedPool/wezfleet commit a9c233f (a wrong parameter name swallowed by try/catch "would have ... degraded every session to unknown, silently"); planning/wezfleet-ssot-multi-backend-2026-09-29.md:523-524 ("silently resolved zero panes through a swallowing try/catch")
- disposition: test
- where: test/test-tristate.ps1 :: "an unknown from an exception keeps its message"

### L-012 There is no value to read out of unknown or absent
- source: YedPool/wezfleet lib/Registry.ps1:290 "present but unreadable: never a skeleton"; planning/BUG-2026-09-15-registry-record-wipe.md:77-78; YedPool/resurrect.wezterm plugin/resurrect/process_handlers.lua:336-340 and 423-429 (an unparseable settings.json becomes {} and is written back)
- disposition: test
- where: test/test-tristate.ps1 :: "reading the value of unknown throws"

### L-013 A missing field reads as unknown, never as the happy default
- source: YedPool/wezfleet lib/Protocol.ps1:665-669 (unknown is NOT fresh, 94 of 369 roster entries predate spawnedAt); commit debac69; commands/delivery.ps1:26-34 (records written before `outcome` existed are UNKNOWN, not failures); commit 1bcf850
- disposition: test
- where: test/test-tristate.ps1 :: "a missing field reads as unknown"

### L-014 An unrecognised state word never reads as known
- source: YedPool/wezfleet lib/Cleanup.ps1:152-153 "Unknown vocabulary is UNSURE, never done"; test_debug/test-cleanup.ps1:101
- disposition: test
- where: test/test-tristate.ps1 :: "an unrecognised state word is not known"

### L-015 Known evidence older than its TTL becomes unknown
- source: YedPool/wezfleet lib/CodexStatus.ps1:37 "anything older than the TTL is UNKNOWN, whatever it says"; lib/Delivery.ps1:50 and :510, :520 (staleness backstop reads unknown); commits 2315a53, e2d8f62; PR #11
- disposition: test
- where: test/test-tristate.ps1 :: "a known reading past its TTL becomes unknown"

### L-016 Expiry applies to the reassuring value too
- source: YedPool/wezfleet lib/CodexStatus.ps1:229-235 "a session killed while idle would then read idle forever"; test_debug/test-codex-status.ps1:112
- disposition: test
- where: test/test-tristate.ps1 :: "a stale reassuring value also becomes unknown"

### L-017 A zero or unparseable TTL is refused, not honoured
- source: YedPool/wezfleet lib/CodexStatus.ps1:76-78 "a typo that silently set the TTL to zero would make every session read unknown forever"
- disposition: test
- where: test/test-tristate.ps1 :: "a non-positive TTL is refused"

### L-018 Resolving unknown requires the caller to state a policy
- source: YedPool/wezfleet lib/Delivery.ps1:663-664 "the caller decides what an unknown costs"; the same wezterm-silent unknown is refused at lib/Common.ps1:825-828, permitted at lib/Protocol.ps1:169-172 and read as false at lib/Common.ps1:986-992 and lib/Kill.ps1:95-99
- disposition: test
- where: test/test-tristate.ps1 :: "resolving unknown without a policy throws"

### L-019 A test of unknown needs a control that returns known
- source: YedPool/wezfleet commit b2e59c6 "the -1 case cannot pass on a function that can only ever return -1"; test_debug/test-registry.ps1:128; test_debug/test-codex-status.ps1:138; wezfleet CLAUDE.md "A search that finds nothing proves nothing until the same instrument finds something known to be present"
- disposition: test
- where: test/test-tristate.ps1 :: "CONTROL: a readable source reads as known"

### L-020 Silence from a voluntary reporter is unknown, not death
- source: YedPool/wezfleet PR #1; tasks/lessons.md:233-245 "absence of evidence is not evidence of death, and it is not evidence of life either"
- disposition: test
- where: test/test-tristate.ps1 :: "no report is unknown, not absent"

### L-021 A destructive act refuses on unknown
- source: YedPool/wezfleet lib/Common.ps1:825-828 (wezterm-unknown); lib/Kill.ps1:136-137 "refusing to act on an unknown"; test_debug/test-safe-kill.ps1:122; test_debug/test-wezfleet.ps1:384
- disposition: dropped
- reason: This is the kill and retitle callers' policy, not a property of the type; it belongs in the TerminalPort ledger (kill and setTitle verbs), which will cite L-018 for the mechanism that forces it to be stated.

### L-022 An absent pane id is not evidence a session closed
- source: YedPool/wezfleet commit 26c58e0 (six panes reported closed and were not); lib/Kill.ps1:138-151; test_debug/test-safe-kill.ps1:135-136
- disposition: dropped
- reason: Absence from one enumeration of pane numbers is an identity question (was it renumbered?) and belongs to the core/identity ledger; core/tristate only guarantees absent and unknown stay distinct once a producer has decided which it has.

### L-023 A pane number from another terminal instance is not evidence
- source: YedPool/wezfleet commit 0e1c75a; planning/BUG-2026-09-15-restart-pane-identity.md; test_debug/test-instance.ps1:121-123
- disposition: dropped
- reason: Whether evidence is foreign or stale by instance is decided in core/identity and the projection, which then hand core/tristate an unknown; the type itself cannot see instances.

### L-024 Typing into an input box that cannot be read is refused
- source: YedPool/wezfleet lib/Delivery.ps1:827-844; commits 6fe4e02 and 70c8a48 (founder's text spliced 21:10:28Z and 21:12:00Z on 2026-09-15); test_debug/test-input-box.ps1:62, 172, 261
- disposition: dropped
- reason: Horde does not deliver by typing into panes; wezfleet PR #12 records that lib/Delivery.ps1 goes away in favour of platform cross-session messaging, so no Horde module owns this policy.

### L-025 An unknown read-state sends rather than suppresses a duplicate
- source: YedPool/wezfleet lib/Delivery.ps1:435 "Never suppress on a guess"; commits e2d8f62 and 7923231; test_debug/test-receipt.ps1:691, 702, 715
- disposition: dropped
- reason: The duplicate guard is part of the typed-delivery subsystem that Horde replaces with platform messaging (PR #12), so the policy has no Horde caller.

### L-026 An unverifiable receipt never triggers a re-send
- source: YedPool/wezfleet commit 1bcf850; lib/Delivery.ps1:1267-1277 and 1600-1606; test_debug/test-receipt.ps1:317-319
- disposition: dropped
- reason: Receipts and re-send rungs exist only for typed delivery, which Horde does not port (PR #12); the general rule underneath it is kept as L-018.

### L-027 An unknown live count holds spawning
- source: YedPool/wezfleet lib/Protocol.ps1:461-463; commands/pump.ps1:67-70; test_debug/test-wezfleet.ps1:747-748
- disposition: dropped
- reason: Holding a wave on an unknown count is the spawn scheduler's policy and belongs in that module's ledger; core/tristate supplies only the unknown it holds on.

### L-028 An unreadable trust config is permissive, with the reason kept
- source: YedPool/wezfleet lib/Common.ps1:876-894; tasks/lessons.md:89-91; test_debug/test-wezfleet.ps1:461-462
- disposition: dropped
- reason: Whether to launch into an unconfirmed workspace is the AgentPort claude spawn preflight's decision and belongs in that ledger; the reason-carrying half is kept as L-010.

### L-029 Unknown liveness never fabricates an orphan or writes mail off
- source: YedPool/wezfleet lib/Protocol.ps1:169-172; test_debug/test-wezfleet.ps1:326-328; commit e36ea8e; test_debug/test-mail-pump.ps1:109, 147
- disposition: dropped
- reason: Classifying sessions as orphaned from liveness is the projection's policy (migration plan step 2.2) and belongs in its ledger.

### L-030 Cleanup treats every unknown as unsure, never done
- source: YedPool/wezfleet lib/Cleanup.ps1:115-119, 136-146; lib/Activity.ps1:108-113; commits debac69 and a9c233f; test_debug/test-cleanup.ps1:94, 105, 160-165
- disposition: dropped
- reason: The done or unsure classification is the cleanup command's policy and belongs in its ledger; the parts that are properties of the type are L-013 and L-014.

### L-031 A window whose liveness is unknown is treated as gone
- source: YedPool/wezfleet lib/Common.ps1:986-992
- disposition: dropped
- reason: Choosing a fresh window over a possibly dead one is a restore planner and ports/layout decision (migration plan steps 4.1 and 4.2) and belongs there.

### L-032 A cosmetic retitle is permissive on unknown ownership
- source: YedPool/wezfleet lib/Common.ps1:1005-1008
- disposition: dropped
- reason: The permissive choice is justified only because the gated act is cosmetic, which is the setTitle caller's reasoning and belongs in the TerminalPort ledger.

### L-033 Busy-detection unknown reads as not working, and never gates delivery
- source: YedPool/wezfleet lib/Delivery.ps1:1045-1057
- disposition: dropped
- reason: The screen-scraped busy probe is part of typed delivery, which Horde does not port; agent status comes from control files under core/identity instead.

### L-034 Codex trust unchecked is unknown, never untrusted
- source: YedPool/wezfleet lib/CodexStatus.ps1:775-785; commands/hooks.ps1:94-101; PR #11; test_debug/test-codex-status.ps1:478, 482
- disposition: dropped
- reason: The trust vocabulary and when to spend twelve seconds asking codex belong in the AgentPort codex ledger; the rendering rule is kept as L-003.

### L-035 A codex session that said ended never expires
- source: YedPool/wezfleet lib/CodexStatus.ps1:229-236; test_debug/test-codex-status.ps1:117
- disposition: dropped
- reason: Which reported values are terminal facts exempt from expiry is agent-specific knowledge for the AgentPort codex ledger; core/tristate offers expiry and lets the caller exempt.

### L-036 An unreadable drive is unknown, not healthy
- source: YedPool/wezfleet lib/Common.ps1:1057-1058, 1088; commit 71afcb0; test_debug/test-disk-space.ps1:65, 83
- disposition: dropped
- reason: Disk health is a startup check with its own wording tests and belongs in that module's ledger; its encoding problem is covered by L-001.

### L-037 A census reports unknown rows instead of omitting them
- source: YedPool/wezfleet planning/registry-design.md:147 "the census omits unknown panes | the 28% hole hides itself"; commands/census.ps1:99-104; test_debug/test-registry.ps1:106; commands/census.ps1:11 still prints no live panes when wezterm is silent (found 2026-09-29, untested)
- disposition: dropped
- reason: Counting and showing unknown rows is the projection and horde status output's job (migration plan steps 2.2 and 2.3), and the census.ps1 defect should be written into that ledger as a parity case.

### L-038 A mail identity that cannot be established is refused
- source: YedPool/wezfleet lib/Mail.ps1:72-74; commit 88aab20; test_debug/test-mail.ps1:193; lib/Mail.ps1:147 and commit b50b2d4
- disposition: dropped
- reason: Self-identity belongs in core/identity, and lib/Mail.ps1 is replaced by platform messaging per PR #12.

### L-039 A parser that fails on a known source inflates unknown
- source: YedPool/wezfleet lib/Activity.ps1:130-136 (a BOM made a single-line log read unknown); commit a9c233f; commit 46d96dc (an empty box read unreadable, exit 4 twice)
- disposition: dropped
- reason: The fix lives in each reader's parser and belongs to the ledger of the module that ports that reader; core/tristate cannot tell a correct unknown from a parser bug.

