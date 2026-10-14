# Knowledge ledger: core/projection

module: core/projection
replaces: YedPool/wezfleet lib/Registry.ps1 (Get-WfFleetCensus, Get-WfPaneIndex, Get-WfPaneIdentity, Find-WfLivePaneForSession, Get-WfLivePaneForFleetSession, Get-WfSession, Get-WfIdentityHealth, Get-WfUnclaimedUserSessions, and the read side of Read-WfAllSessionRecords and Read-WfPaneSessionFile), lib/Protocol.ps1 (Get-WfRunSnapshot, Get-WfSessionState, Get-WfLiveFleetSessions, Get-WfClaudeSessionInfo), lib/Hierarchy.ps1 (Get-WfHierarchy, Get-WfHierarchyFindings), lib/Common.ps1 (Get-WfLivePanes, Get-WfCurrentInstance, Test-WfWrittenInInstance, Format-WfRecordPane, Resolve-WfRunForSession, Get-WfDuplicateSessions), lib/Hosts.ps1 (Get-WfFleetSessions), lib/Activity.ps1 (Get-WfSessionActivity), commands/sessions.ps1, commands/census.ps1, commands/tree.ps1, and the read side of commands/status.ps1
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

Harvested 2026-09-30 from YedPool/wezfleet main acda968 and YedPool/horde main c5cb727. Of the 17
wezfleet pull requests, #1, #2, #4 and #5 touched lib/Protocol.ps1 and #1 and #6 lib/Common.ps1; none
touched Registry.ps1, Hierarchy.ps1, Hosts.ps1 or the four commands, and every incident commit cited
below was pushed directly (checked with `gh pr list --json files`). The places wezfleet's readers
differ from core/ownership.json on purpose are recorded as P-01 to P-27 in planning/parity-2.3.md, for
step 2.3's parity run. Citations checked against the source on 2026-09-30, by reading the lines: Hosts.ps1:59-61,
census.ps1:10-11 and :17, Registry.ps1:122-123, :393, :395, :578-583, :667-673, :854-861, :868-876,
Common.ps1:546-548, :349, Activity.ps1:282, Protocol.ps1:11, :438-441, MailPump.ps1:58-62,
sessions.ps1:41-46, status.ps1:8.

### L-001 The projection writes nothing, and the proof is that the module holds no file-writing call
- source: horde planning/migration-plan.html step 2.2 "A test asserting the module contains no file-writing call at all"; D2
- disposition: test
- where: test/test-projection.ps1 :: "the projection module contains no file-writing call"

### L-002 A read leaves every store byte-identical, including no lock or temp file
- source: horde planning/ledger/core-roles.md L-008, L-009; YedPool/wezfleet lib/Registry.ps1:147-158 (a held lock makes the hook skip its write)
- disposition: test
- where: test/test-projection.ps1 :: "projecting leaves no new or changed file in any store"

### L-003 Every foreign file is read with read, write and delete sharing
- source: horde core/ReadShared.ps1:4-8 (measured 2026-09-29: an ordinary read share makes File.Replace fail); YedPool/wezfleet lib/Registry.ps1:121 reads with Get-Content
- disposition: test
- where: test/test-projection.ps1 :: "a wezfleet write succeeds while the projection reads"

### L-004 An unreadable pane list is unknown, never zero panes
- source: YedPool/wezfleet lib/Hosts.ps1:59-61 "$null is a real answer meaning UNKNOWN"; lib/Common.ps1:497-503 then collapses it to an empty map
- disposition: test
- where: test/test-projection.ps1 :: "an unreadable handle list leaves every pane unknown"

### L-005 Zero live handles is a known empty list, distinct from unknown
- source: YedPool/wezfleet commands/sessions.ps1:41 and lib/Protocol.ps1:170 treat a count of 0 as unknown
- disposition: test
- where: test/test-projection.ps1 :: "an empty handle list is known and empty"

### L-006 A census never prints no live panes for an unreadable mux
- source: YedPool/wezfleet commands/census.ps1:10-11; horde planning/ledger/core-tristate.md L-037 "the census.ps1 defect should be written into that ledger as a parity case"
- disposition: test
- where: test/test-projection.ps1 :: "parity exception unreadable mux is not an empty census"

### L-007 Three pane states: a handle, known to be in none, and unknown
- source: YedPool/wezfleet lib/Hosts.ps1:178-182; commit 27cfafe; test_debug/test-fleet-sessions.ps1 "every pane reads '?' rather than '-'"
- disposition: test
- where: test/test-projection.ps1 :: "a paneless session reads absent, not unknown"

### L-008 A session with no pane is still a member of the fleet
- source: YedPool/wezfleet 27cfafe; test_debug/test-fleet-sessions.ps1 "the paneless session appears at all - census cannot show this one"
- disposition: test
- where: test/test-projection.ps1 :: "a session outside every host is still listed"

### L-009 Rows are keyed by session; the pane is an attribute, never the key
- source: horde planning/migration-plan.html D3; YedPool/wezfleet lib/Protocol.ps1:555-569 derived the session from the pane
- disposition: test
- where: test/test-projection.ps1 :: "no session is inferred from a pane number"

### L-010 The caller's own session id never identifies a pane
- source: YedPool/wezfleet lib/Protocol.ps1:438-441, reached from commands/sessions.ps1:45 (a live pane with no file takes CLAUDE_CODE_SESSION_ID); core/ownership.json sessionId row "never identifies another pane"
- disposition: test
- where: test/test-projection.ps1 :: "the environment never names another session"

### L-011 A pane number is evidence only inside the instance that issued it, and only if written after it started
- source: YedPool/wezfleet 0e1c75a; lib/Common.ps1:611-641; test_debug/test-instance.ps1:95-101, :117-123; horde planning/ledger/core-tristate.md L-023
- disposition: test
- where: test/test-projection.ps1 :: "a record from another instance names no pane"

### L-012 An ambiguous instance trusts no pane record
- source: YedPool/wezfleet lib/Common.ps1:546-548, :625; test_debug/test-instance.ps1:101 "an AMBIGUOUS instance trusts nothing"
- disposition: test
- where: test/test-projection.ps1 :: "an ambiguous host instance trusts no record"

### L-013 An instance id passed in must reach the rule, not be defaulted away
- source: YedPool/wezfleet 17c5d42; planning/BUG-2026-09-15-registry-record-wipe.md:112-120 ([string]$Socket=$null became "")
- disposition: test
- where: test/test-projection.ps1 :: "an injected instance is the one judged"

### L-014 A retired record holds no pane
- source: YedPool/wezfleet 562f0e8; lib/Registry.ps1:388-393; test_debug/test-pane-resolution.ps1:89 "a RETIRED session stops claiming its pane"
- disposition: test
- where: test/test-projection.ps1 :: "a retired record answers no pane"

### L-015 Several sessions answering one handle is a fault, never a silent newest-wins
- source: YedPool/wezfleet lib/Registry.ps1:395; horde planning/ledger/core-ownership.md L-011 (handed to the projection); live 2026-09-30: pane 27 claimed by 3 non-retired records
- disposition: test
- where: test/test-projection.ps1 :: "a handle claimed twice is reported as a fault"

### L-016 One session in two live pane-sessions files is a fault, and neither file answers
- source: YedPool/wezfleet lib/Registry.ps1:667-673 (the finder takes exactly one match); commands/sessions.ps1:46 keeps the last; core/ownership.json X1 guard; cef5ba3
- disposition: test
- where: test/test-projection.ps1 :: "a session in two handles is reported"

### L-017 A pane-sessions file contradicting a live session in that pane is a hijack
- source: YedPool/wezfleet f09f4e1; test_debug/diag-pane-session-hijack.ps1; horde planning/ledger/core-identity.md L-038, L-039; planning/ledger/core-ownership.md L-009
- disposition: test
- where: test/test-projection.ps1 :: "a hijacked pane file does not answer"

### L-018 Pane-sessions files are refused while more than one terminal instance runs
- source: YedPool/wezfleet lib/Registry.ps1:223-247; 88aab20; test_debug/test-instance.ps1:165-166
- disposition: test
- where: test/test-projection.ps1 :: "two host instances refuse every pane file"

### L-019 A pane-sessions file whose transcript is gone does not answer for the transcript
- source: YedPool/wezfleet lib/Protocol.ps1:402-424 (diag-pane-session-staleness.ps1: 141 of 150 share one cwd); horde planning/ledger/core-ownership.md L-043; core/ownership.json transcriptPath X1 "when the transcript it names exists"
- disposition: test
- where: test/test-projection.ps1 :: "a pane file naming a missing transcript does not answer the transcript"

### L-020 The cwd guard barely discriminates, so it is never the only guard
- source: YedPool/wezfleet lib/Registry.ps1:578-583 "94% of the time"; d8449ea (35 rejections were pane reuse); horde planning/ledger/core-ownership.md L-018
- disposition: comment
- where: core/Projection.ps1 :: "the cwd guard barely discriminates"

### L-021 The pane is read in the ownership table's order, and every answer says where it came from
- source: core/ownership.json pane row; YedPool/wezfleet census source column (lib/Registry.ps1:822-823 "a census that cannot say how confident it is")
- disposition: test
- where: test/test-projection.ps1 :: "every answer names the store it came from"

### L-022 Registry pane freshness is by instance, not the 900 second age
- source: YedPool/wezfleet lib/Registry.ps1:774-779, :537, :553 against :394; horde planning/ledger/core-ownership.md L-025
- disposition: test
- where: test/test-projection.ps1 :: "a quiet session keeps its registry pane"

### L-023 The run snapshot's pane order differs, and is a documented parity exception
- source: YedPool/wezfleet lib/Protocol.ps1:522-537; 4947d8c; horde planning/ledger/core-ownership.md L-026; planning/parity-2.3.md P-17
- disposition: test
- where: test/test-projection.ps1 :: "parity exception snapshot pane order"

### L-024 A transcript is found from the launch directory, not the current one
- source: YedPool/wezfleet lib/Registry.ps1:861, :872 use rec.cwd while :486 and :796-799 use firstCwd; measured 2026-09-30: 23 of 31 found by census's rule, 26 by firstCwd
- disposition: test
- where: test/test-projection.ps1 :: "parity exception census transcript from current cwd"

### L-025 A missing measurement is unknown, never zero or idle
- source: YedPool/wezfleet b2e59c6 "-1 means UNKNOWN, never idle"; lib/Registry.ps1:868-876; test_debug/test-registry.ps1:115
- disposition: test
- where: test/test-projection.ps1 :: "no transcript leaves last activity unknown"

### L-026 Last activity is the newest of all involuntary sources
- source: YedPool/wezfleet lib/Activity.ps1:245-272 (cmdlog, loose cmdlog, transcript); PR #1; core/ownership.json lastActivity row
- disposition: test
- where: test/test-projection.ps1 :: "last activity takes the newest source"

### L-027 A timestamp from the future is not read as fresh
- source: YedPool/wezfleet lib/Activity.ps1:282 clamps to 0; horde core/Tristate.ps1:37 (5 s skew)
- disposition: test
- where: test/test-projection.ps1 :: "a future activity time is not fresh"

### L-028 The report is what the session chose to say; activity is what it did
- source: YedPool/wezfleet cf5c370 (12 of about 28 fields voluntary); test_debug/audit-state-sources.ps1:23-51
- disposition: comment
- where: core/Projection.ps1 :: "voluntary facts are provenance W5"

### L-029 Work state reads the event log, and a terminal event is trusted outright
- source: YedPool/wezfleet lib/Protocol.ps1:11, :187-188; horde planning/ledger/core-ownership.md L-015
- disposition: test
- where: test/test-projection.ps1 :: "a done event is trusted outright"

### L-030 Unknown liveness never fabricates an orphan
- source: YedPool/wezfleet lib/Protocol.ps1:169-172; test_debug/test-wezfleet.ps1:328 "unknown liveness does not fabricate orphans"; horde planning/ledger/core-tristate.md L-029 (handed here)
- disposition: test
- where: test/test-projection.ps1 :: "unknown liveness is never orphaned"

### L-031 Orphaned needs both the pane gone and the activity stopped
- source: YedPool/wezfleet lib/Protocol.ps1:139-142, :180-185; test_debug/test-wezfleet.ps1:310, :1030
- disposition: test
- where: test/test-projection.ps1 :: "a gone pane with fresh activity is not orphaned"

### L-032 A pending roster entry is pending, not starting
- source: YedPool/wezfleet lib/Protocol.ps1:590-599; test_debug/test-wezfleet.ps1:896; horde planning/ledger/core-ownership.md L-016
- disposition: test
- where: test/test-projection.ps1 :: "an unspawned roster entry reads pending"

### L-033 Run membership is ambiguous when two open runs spawned the id, and is reported
- source: YedPool/wezfleet lib/Common.ps1:331-347; test_debug/test-run-resolution.ps1:55-90; horde planning/ledger/core-ownership.md L-030; live 2026-09-30: 5 fleet ids spawned in more than one open run
- disposition: test
- where: test/test-projection.ps1 :: "two open runs make the run unknown"

### L-034 Several closed runs listing one id are ambiguous too
- source: YedPool/wezfleet lib/Common.ps1:349 returns hits[0]; core/ownership.json runId row is silent on it; planning/parity-2.3.md P-22
- disposition: test
- where: test/test-projection.ps1 :: "two closed runs are not chosen between"

### L-035 Exactly one warchief; two is a finding naming both, never chosen by time
- source: YedPool/wezfleet lib/Hierarchy.ps1:21-24, :77-87; 4eba288; test_debug/test-hierarchy.ps1:66-71; horde planning/ledger/core-roles.md L-017, planning/ledger/core-ownership.md L-021 (handed here)
- disposition: test
- where: test/test-projection.ps1 :: "two warchiefs are reported and both named"

### L-036 No warchief is a finding, not a silent normal
- source: YedPool/wezfleet lib/Hierarchy.ps1:79-82; test_debug/test-hierarchy.ps1:45
- disposition: test
- where: test/test-projection.ps1 :: "no warchief is reported as a fault"

### L-037 The warchief count is unknown when the registry cannot be read or a live role is unknown
- source: horde planning/migration-plan.html section 2 "the Warchief count is unknown, not zero"; planning/ledger/core-roles.md L-011, core/Roles.ps1 Get-HordeRoleCount; live 2026-09-30: floor 1, 9 unsure
- disposition: test
- where: test/test-projection.ps1 :: "an unreadable registry leaves the warchief count unknown"

### L-038 An orc whose parent is not the warchief is a fault, judged only when the warchief is known
- source: YedPool/wezfleet lib/Hierarchy.ps1:89-98 (untested there: 0 hits in test_debug)
- disposition: test
- where: test/test-projection.ps1 :: "an orc under another parent is reported"

### L-039 A parent with no record and a retired parent are two faults
- source: YedPool/wezfleet lib/Hierarchy.ps1:42-58, :100-107 (retired records are dropped before the lookup; untested there); planning/parity-2.3.md P-25
- disposition: test
- where: test/test-projection.ps1 :: "a retired parent is not a missing parent"

### L-040 Faults report and repair nothing, and are never stored
- source: YedPool/wezfleet lib/Hierarchy.ps1:21-24; commands/tree.ps1:50-53; test_debug/test-hierarchy.ps1:68; horde planning/ledger/core-roles.md L-019. core/Faults.ps1 is loaded by the projection, so the syntax-tree scan covers it, stopping and starting processes included
- disposition: test
- where: test/test-projection.ps1 :: "the projection module contains no file-writing call"

### L-041 A running session with a retired record is a fault
- source: live 2026-09-30: d16b54b2 control file idle, registry retired 2026-09-23T03:22Z, lastSeen 2026-09-30T01:44Z; YedPool/wezfleet lib/Registry.ps1:393 skips it silently; planning/parity-2.3.md P-26
- disposition: test
- where: test/test-projection.ps1 :: "a live session with a tombstone is reported"

### L-042 One conversation in two processes is reported, never acted on, and the blind spot is stated
- source: YedPool/wezfleet lib/Common.ps1:684-708; 0e1c75a; test_debug/test-instance.ps1:193-196; horde planning/ledger/core-identity.md L-020
- disposition: test
- where: test/test-projection.ps1 :: "one conversation in two processes is a fault"

### L-043 A registry hook that writes nothing is a fault, judged from the sessions that run
- source: YedPool/wezfleet lib/Registry.ps1:952-964, :987-1010; e929318 (one record while 19 panes were live); 0e1c75a. The draft dropped this as hook health; the lead asked for the ten existing rules, so it is kept in its read-only form - running claude sessions exist and none has a registry record
- disposition: test
- where: test/test-projection.ps1 :: "running sessions with no registry record at all mean the hook is silent"

### L-044 Owner is derived from the parent's label, and the stored name is display only
- source: core/ownership.json owner row; YedPool/wezfleet 1e8837a; commands/census.ps1:17 prints (unowned); live 2026-09-30: 7 of 16 non-retired records have an empty owner where founder is derived
- disposition: test
- where: test/test-projection.ps1 :: "parity exception owner derived from parent"

### L-045 A founder session nobody owns is found from origin and parent, not from an empty name
- source: YedPool/wezfleet lib/Registry.ps1:1190-1201; commands/census.ps1:31-37; test_debug/test-registry.ps1:169, :172
- disposition: test
- where: test/test-projection.ps1 :: "a user session with no parent is owned by the founder"

### L-046 Origin has two values; anything else is absent or unknown, never the word unknown
- source: YedPool/wezfleet lib/Registry.ps1:858; test_debug/test-registry.ps1:156-164; planning/parity-2.3.md P-12
- disposition: test
- where: test/test-projection.ps1 :: "a missing origin is not the string unknown"

### L-047 A corrupt record costs one session and makes the listing incomplete
- source: YedPool/wezfleet lib/Registry.ps1:121-123; test_debug/test-registry.ps1:213 "one corrupt file costs ONE row"; horde planning/ledger/core-roles.md L-011
- disposition: test
- where: test/test-projection.ps1 :: "a corrupt record makes the registry incomplete"

### L-048 A record whose file name and content disagree is not a record
- source: YedPool/wezfleet lib/Registry.ps1:122-123; test_debug/test-registry.ps1:217; horde planning/ledger/core-roles.md L-010
- disposition: test
- where: test/test-projection.ps1 :: "a misnamed record is refused and reported"

### L-049 Host title and roster title are different facts
- source: YedPool/wezfleet lib/Registry.ps1:854 against core/ownership.json title row (W4, W3); planning/parity-2.3.md P-15
- disposition: test
- where: test/test-projection.ps1 :: "the host title is not the session title"

### L-050 Nothing outside hosts names a terminal; the handle list arrives through a port
- source: horde planning/migration-plan.html D12; YedPool/wezfleet lib/Hosts.ps1:21-32 and lib/Common.ps1:487-492
- disposition: test
- where: test/test-projection.ps1 :: "the projection names no terminal"

### L-051 Every source is a parameter, so tests never read the box
- source: YedPool/wezfleet lib/Protocol.ps1:369-380 (four assertions changed answer with the process list); lib/Hosts.ps1:175-176; horde planning/ledger/core-identity.md L-041
- disposition: test
- where: test/test-projection.ps1 :: "the suite reads no real store before the reality check"

### L-052 The product must call the resolver, proven through the command and not only the function
- source: YedPool/wezfleet 4947d8c (a mutation of the wiring left test-registry green); tasks/lessons.md 2026-09-09 "a mechanism with no callers". Step 2.2 is a library with no command (the lead's decision 5), so the proof belongs to step 2.3 and is carried there
- disposition: comment
- where: planning/parity-2.3.md :: "horde status calls the projection"

### L-053 Parity is measured against the shipped functions over one fixture, never a reconstruction
- source: YedPool/wezfleet tasks/lessons.md:571-574 "VERIFY AGAINST THE SHIPPED COMMAND"; horde tasks/lessons.md "Every number in a commit, PR or report comes from command output". Step 2.3 runs the comparison; the method is carried there
- disposition: comment
- where: planning/parity-2.3.md :: "parity runs wezfleet functions on the fixture"

### L-054 wezfleet status writes before it reads, so parity uses the snapshot function
- source: YedPool/wezfleet commands/status.ps1:8, :15; commands/pump.ps1:4-5
- disposition: comment
- where: core/Projection.ps1 :: "wezfleet status spawns before it reads"

### L-055 Identity accepts ids the stored record refuses; the projection decides: keyed, and flagged
- source: horde planning/ledger/core-identity.md L-052; core/Identity.ps1:68-79 "which rule wins is for step 2.2"
- disposition: test
- where: test/test-projection.ps1 :: "a non-uuid session id is keyed and flagged"

### L-056 A layout save is compared against, never used as the answer
- source: core/ownership.json resumeCommand row (R1 shadow only); horde planning/ledger/core-ownership.md L-044; resurrect state workspace/default.json process.argv read 2026-09-30 as claude --resume and the id
- disposition: test
- where: test/test-projection.ps1 :: "a layout save never answers resumeCommand"

### L-057 resurrect keeps per-instance saves the ownership table does not list
- source: resurrect state/instances (15 entries, .json and .meta, 2026-09-30) and state/current_state; plugin/resurrect/instance_manager.lua:4-5; core/ownership.json R1 path lists only workspace, window, tab
- disposition: dropped
- reason: Layout is advisory (D3) and read only for the resume shadow, through a layout port the projection is handed; which save a restore uses belongs to the LayoutPort and restore planner ledgers (steps 4.x).

### L-058 Title drift and bare shells are presentation over the host's titles
- source: YedPool/wezfleet commands/census.ps1:38-63, :78-97; 50a6944; d811106
- disposition: dropped
- reason: Title repair and bare-shell detection read and write host tab titles; they belong to the first host adapter's decoration code (step 7.2), not the read model.

### L-059 Unsent text in an input box is read from the screen
- source: YedPool/wezfleet commands/census.ps1:110-123; 6fe4e02; planning/BUG-2026-09-15-unsent-input-box.md
- disposition: dropped
- reason: Screen text is the TerminalPort getText verb used for delivery safety; Horde delivers over the session socket, so this belongs to a host adapter's ledger if it is ever needed.

### L-060 Disk space is reported by census and startup
- source: YedPool/wezfleet commands/census.ps1:64-76; 71afcb0
- disposition: dropped
- reason: Machine health is not a session fact; it belongs to the horde startup or doctor command ledger.

### L-061 The machine-wide live fleet count bounds launches
- source: YedPool/wezfleet lib/Protocol.ps1:445-495; test_debug/test-wezfleet.ps1:731-752
- disposition: dropped
- reason: The launch cap is spawner policy owned by the Phase 5 spawn module; it can be computed from the projection there, and its unknown-as-minus-one rule is carried by L-004.

### L-062 The roster may still group sessions; only identity and pane moved off it
- source: YedPool/wezfleet test_debug/test-ssot.ps1:43-44; 562f0e8 "GROUPING is the roster's proper job"
- disposition: comment
- where: core/Projection.ps1 :: "the roster groups sessions into runs"

### L-063 Every claimant of one handle is unknown, and each reason names them all
- source: the lead's decision 1, 2026-09-30; YedPool/wezfleet lib/Registry.ps1:395 (newest lastSeen wins); planning/parity-2.3.md P-14
- disposition: test
- where: test/test-projection.ps1 :: "every claimant of one handle has an unknown pane naming every claimant"

### L-064 With no host instance running a stored handle cannot be verified
- source: the lead's decision 2, 2026-09-30; YedPool/wezfleet lib/Common.ps1:624, :626 (no wezterm-gui running trusts every record); planning/parity-2.3.md P-27
- disposition: test
- where: test/test-projection.ps1 :: "with no host instance running every pane is unknown"

### L-065 The view lists every live handle, including the ones no session answers
- source: the lead's decision 3, 2026-09-30; YedPool/wezfleet census rows are pane-first (lib/Registry.ps1:808-881); planning/parity-2.3.md P-08
- disposition: test
- where: test/test-projection.ps1 :: "a handle no session answers is still listed"

### L-066 Stray records in the real store are reported, never written, and never fail the check
- source: the lead's decision 4, 2026-09-30; live registry 2026-09-30: 11111111-2222-4333-8444-555555555555 (cwd C:/w), f47a6158 (the f09f4e1 spike), d16b54b2 (running, retired)
- disposition: test
- where: test/test-projection.ps1 :: "the reality check projects this machine's stores without throwing"

### L-067 Every answer is typed and validated against one schema
- source: horde planning/execution-plan-phases-0-2.md step 14; schema/session-record.v1 description "the review's findings about value types and answer consistency ... apply to that view"
- disposition: test
- where: test/test-projection.ps1 :: "every answer validates against schema/session-view.v1"

### L-068 What the validator cannot express is checked in code, not dropped from the schema
- source: horde core/Schema.ps1:1-23 (the subset: no oneOf, anyOf, if/then or dependencies); schema/session-view.v1 description "WHAT THIS SCHEMA CANNOT SAY"
- disposition: test
- where: test/test-projection.ps1 :: "the view keeps the rules the schema cannot state"

### L-069 A provisional rule is marked on every answer it produced
- source: core/ownership.json provisional marks (pane, transcriptPath, resumeCommand, formerNames, entrypoint); horde planning/execution-plan-phases-0-2.md step 14 "the provisional mark wherever the ownership table has one"
- disposition: test
- where: test/test-projection.ps1 :: "the view carries a provisional mark exactly where the table has one"

### L-070 An event log with a line that does not parse is unknown, never a shorter log
- source: YedPool/wezfleet lib/Common.ps1:194-205 Read-WfJsonLines skips a line it cannot parse, so a torn "done" line reads as a session still running; core/ownership.json report row "the log is the truth"
- disposition: test
- where: test/test-projection.ps1 :: "an event log with a torn line is unknown, never shorter"

### L-071 A pane-sessions file that breaks its schema is refused and named, not a gap
- source: YedPool/wezfleet lib/Registry.ps1:244 refuses a malformed session_id; horde schema/pane-session.v1 (163 real files, 2026-09-29)
- disposition: test
- where: test/test-projection.ps1 :: "a pane-sessions file that breaks the schema is refused, not a gap"

### L-072 A role that is not there is unknown, never warg, in the view as in the counts
- source: horde planning/ledger/core-roles.md L-021; core/Roles.ps1 header "A ROLE THAT IS NOT THERE IS UNKNOWN, NEVER WARG"; live 2026-09-30: 13 of 31 records have no role
- disposition: test
- where: test/test-projection.ps1 :: "a live record with no role is unknown, never warg, and makes the count unknown"

### L-073 waitingFor is in the view because the table requires it, read from the control file alone
- source: horde PR #24 (b4898cc) adds waitingFor to core/ownership.json required, read only from X2 while the process runs, and waiting as a Claude status; planning/ledger/core-ownership.md L-055 (1 of 10 control files on 2026-09-30, "permission prompt"). The view carries every required field, so it is not optional here; a session no control file names waits on nothing, as with liveStatus
- disposition: test
- where: test/test-projection.ps1 :: "a waiting session says what it waits for, from its own control file"

## The host port contract, from research into three more hosts

Researched 2026-09-30 for orchestrator D: tmux 3.4 measured inside WSL, psmux (one server per
session, Windows) and Ghostty (macOS and Linux only) from their documentation and source. The research
proposed contract changes C1-C9 before this module merges, while the port has one caller; the lead took
C1, C3, C4 and C5 into this PR with tests, and C2, C6 and C8 as written contract, and left C7 (a
shared command dialect and the host-name ratchet) and C9 (native-tool output decoding) to the
adapters' own PRs.

### L-074 A host declares what it can do; core relies only on yes, and unverified counts as no
- source: host research 2026-09-30 C5 and the capability matrix (one host cannot read its screen, another cannot send text); horde planning/migration-plan.html D5 "each host declares what it can do"
- disposition: test
- where: test/test-projection.ps1 :: "an unverified capability counts as no"

### L-075 Asking for a capability a host lacks is an unknown with the reason, never a crash
- source: host research 2026-09-30 section 5.1 "asking for an absent verb is an unknown with the reason ... never a throw that reads as a host fault"
- disposition: test
- where: test/test-projection.ps1 :: "a host that does not offer its handle list leaves every pane unknown"

### L-076 A handle is unique within its instance, and running counts instances, not servers
- source: host research 2026-09-30 C3: a host with one server per session numbers panes per server, so a bare pane id repeats inside one instance; counting servers would refuse every pane-sessions file for a user with two sessions (the X1 guard's running > 1 rule)
- disposition: test
- where: test/test-projection.ps1 :: "one instance with many servers still reads its pane-sessions files"

### L-077 Handle text is plain; an adapter maps native ids with sigils to it and back
- source: host research 2026-09-30 C1: pane, window and session ids measured as %1, @0 and $0, which fail the handle rule, and a $ in a reason string is a PowerShell expansion hazard
- disposition: test
- where: test/test-projection.ps1 :: "a native id with a sigil is refused, so adapters map it to handle text"

### L-078 A pid or cwd carries its namespace, and core never compares across namespaces
- source: host research 2026-09-30 C4: a multiplexer inside WSL returns Linux pids and paths, while core's process table is Win32_Process (core/Projection.ps1 Get-HordeProjectionProcessTable)
- disposition: test
- where: test/test-projection.ps1 :: "a pid from another namespace is unknown, never compared"

### L-079 The adapter builds the instance id, and it must change when the server restarts
- source: host research 2026-09-30 C2: a socket path fails the handle rule, and a multiplexer reuses socket names across restarts, so an id built from the name alone would hand a new server the old one's records
- disposition: comment
- where: core/HostPort.ps1 :: "THE ADAPTER BUILDS THE INSTANCE ID"

### L-080 Window and tab are the first host's words; each host maps its own levels onto them
- source: host research 2026-09-30 C6: a multiplexer's session maps to window and its window to tab; a host with windows and tabs maps directly; a missing level is $null
- disposition: comment
- where: core/HostPort.ps1 :: "WINDOW AND TAB ARE THE FIRST HOST'S WORDS"

### L-081 A pane's own-id variable is a declared capability, and the adapter propagates it
- source: host research 2026-09-30 C8: each host names its own variable, and a child started from a pane inside WSL does not see it unless the adapter exports it (measured); core/Identity.ps1 still never falls back to it (planning/ledger/core-identity.md)
- disposition: comment
- where: core/HostPort.ps1 :: "A PANE'S OWN-ID VARIABLE IS A CAPABILITY"

## From the review of PR #31

### L-082 A skip proves "none" only over a whole store; a skip that rests on something unknown is unknown
- source: review of horde PR #31, finding 1, with probes: sessions whose run could not be chosen read title, dependsOn and spawnedAt absent; with no host, a session with no record read its fleet id absent (decision 2 leaking); an incomplete registry proved sessions had no record; a codex file that failed to re-read counted as no file
- disposition: test
- where: test/test-projection.ps1 :: "an incomplete registry never proves a session has no record"

### L-083 A stored handle belongs to the host that wrote it
- source: review of horde PR #31, finding 2: roster, report, pane-sessions and claim handles carry no host or instance, so another host's handle 17 would match a pane 17 the first host wrote; horde planning/migration-plan.html D12 "a handle is never a key"
- disposition: test
- where: test/test-projection.ps1 :: "a stored handle counts only when this host declares it wrote that store"

### L-084 A session's host instance is proven by its live handle, never by its running
- source: review of horde PR #31, finding 3: hostInstance was the host's one running instance for any session a control file called alive, so a session in another terminal was labelled with this one
- disposition: test
- where: test/test-projection.ps1 :: "a running session whose handle is unknown is in no proven host instance"

### L-085 A malformed instance is unknown, never nameless or unambiguous by default
- source: review of horde PR #31, finding 4: a malformed instance id was dropped silently and a non-boolean ambiguous flag read as false; host research 2026-09-30 C2 (a composed <distro>.<socket>.<server pid> id can pass 64 characters)
- disposition: test
- where: test/test-projection.ps1 :: "a malformed instance id makes the instance unknown, never nameless"

### L-086 A skipped reality check is set by the spec that needs it, and never ends on the usual banner
- source: review of horde PR #31, finding 5: HORDE_SKIP_REALITY was set by hand in the shell running tools/Mutate.ps1, and a normal run with it set printed the same green banner as a whole run
- disposition: test
- where: test/test-mutate.ps1 :: "a spec's environment reaches every run of its suite"

### L-087 Core's process table and its namespace come from a platform
- source: review of horde PR #31, finding 6: the process table was a Win32_Process call in core and the local namespace a "windows" constant, so a node on another system (horde planning/execution-plan-remote.md R12) could not supply its own
- disposition: test
- where: test/test-projection.ps1 :: "the projection reads processes through the platform it is given"

### L-088 The view keys a session on its bare id until engines K1 keys it on (harness, id)
- source: review of horde PR #31, finding 7; planning/execution-plan-engines.md step 12 (K1: "the same id under two harnesses gives two records"), sequenced after the remote plan's R10 and before Phase 3 step 3.8, changing the record, view and restore-plan schemas together
- disposition: comment
- where: core/Projection.ps1 :: "THE KEY IS THE BARE ID, IGNORING CASE, UNTIL ENGINES K1"

### L-089 Where two records answer one question, neither is picked
- source: review of horde PR #31, finding 8: the pane-sessions holder map kept the last running session read, and a roster or manifest listing one fleet id twice gave its first entry
- disposition: test
- where: test/test-projection.ps1 :: "a roster that lists one fleet id twice is reported, and chooses neither entry"

### L-090 A check that reads one agent's processes is unknown while another agent's sessions exist
- source: review of horde PR #31, finding 9: conversation-in-two-processes reads only claude processes' command lines (YedPool/wezfleet lib/Common.ps1:684-708 has the same blind spot), yet answered a known false with a codex session present
- disposition: test
- where: test/test-projection.ps1 :: "a session of an agent whose processes are not read leaves the duplicate check unknown"

### L-091 The projection's engine names are counted exactly until engines A4 moves them out
- source: review of horde PR #31, finding 10: agent names in core/Projection.ps1 and core/Faults.ps1, the --resume pattern, and the agent enum in schema/session-view.v1; planning/execution-plan-engines.md step 13 (A4) and step 2 (E1); second review, finding 7
- disposition: dropped
- reason: A list kept here would be a second engine-name allowlist beside engines E1 (PR #34), which is the single one, kept per engine in agents/<name>/allowlist.txt; whichever of PR #31 or PR #34 merges second adds this module's files to it with growth.txt lines, so the counts are carried there and not in this module.

## From the second review of PR #31

### L-092 An unlistable runs directory, an unjudged pane file and an unread command line prove nothing absent
- source: second review of horde PR #31, finding 1: with the runs directory a dangling junction, session 3 read runId, title, dependsOn, workState and report absent, because the run resolver checked only rostersComplete; pane-sessions files held by two sessions or naming a session twice were passed over as "no file"; and a claude process with no readable command line counted as not resuming the session
- disposition: test
- where: test/test-projection.ps1 :: "a runs directory that cannot be listed never proves a session is in no run"

### L-093 Each store has exactly one writer host, and a record with no host belongs to it alone
- source: second review of horde PR #31, finding 2: per-store declaration holds only while each store has one writer host; planning/execution-plan-phase-3.md step 3 and planning/execution-plan-hosts.md omitted -StoredHandles and named windows as a fixed namespace
- disposition: test
- where: test/test-projection.ps1 :: "two hosts declaring the same store are refused"

### L-094 A run that skipped the reality check exits 3, and only a spec that declares 3 reads it as a pass
- source: second review of horde PR #31, finding 4: with HORDE_SKIP_REALITY set, the suite exited 0 with only its banner changed, so a gate could pass on a partial run, and the banner check was a tautology
- disposition: test
- where: test/test-mutate.ps1 :: "a pass code a spec does not declare is not a pass"

### L-095 Every reader of the process table goes through the platform seam
- source: second review of horde PR #31, finding 5: core/Identity.ps1 Get-HordeProcessTable still read Win32_Process outside core/Platform.ps1, and the seam's reader was named after the projection
- disposition: test
- where: test/test-projection.ps1 :: "the process table is read only behind the platform seam"

### L-096 Every rule of the pane-file judge and the claim matcher has a mutant a test catches
- source: second review of horde PR #31, finding 8: the checks added to the pane-sessions judge (writer, two files, contradicted file) and the claim matcher (writer, incomplete registry, unknown handle) had no mutants
- disposition: test
- where: test/test-projection.ps1 :: "a claim is not matched when this host did not write the claims"

### L-097 A caught mutant stops at its first failed check, and one mutant can be rerun alone
- source: second review of horde PR #31, finding 9: the projection suite takes over 20 minutes under load, so 105 mutants ran for days; a caught mutant needs only its first [FAIL], and rerunning one after a fix needed the whole spec
- disposition: test
- where: test/test-suite.ps1 :: "under fail-fast a suite stops at its first failed check"

### L-098 Each value is type-checked as it is given; the whole view is validated only in tests and on request
- source: coordinator decision 2026-09-30 for PR #31 and step 2.3: full-view validation costs about 0.6 ms per value with the schema cache (PR #43), about 54 s for 331 real sessions, too slow for every horde status; measured 2026-09-30 for this entry: the per-field gate takes 12,399 ms of a 100,067 ms projection of 333 real sessions (18,981 calls, 0.653 ms each), so it stays; reviewed again 2026-10-01 (coordinator, PR #31): the answer audit in New-HordeViewAnswer (Assert-HordeAnswer) also stays whole - a swap to a type-tag check was tried for speed and reverted, because the tag alone does not enforce what Test-HordeAnswer does (all four fields present; state exactly known, absent or unknown; an unknown carries a reason; a known holds a value; observedAt a date or nothing), and with no whole-view validation on horde status nothing else would; the two speedups kept are the statics cache and the loop in Resolve-HordeField, which drop no check
- disposition: comment
- where: core/Projection.ps1 :: "VALIDATION: PER FIELD ALWAYS, THE WHOLE VIEW ON REQUEST"

### L-099 horde status projects the current sessions; the module's default stays every session
- source: coordinator decision 2026-10-02 for PR #31 (horde status must be usable on real data): a session is current when any live signal holds - running, a registry record not retired, an open run, a control file or a guarded pane-sessions file names it, or a stored handle live in this instance makes its pane known; otherwise historical. Measured for it on this machine, 2026-10-02: 213 of the 229 sessions the structural measurement called historical were report-only sessions of closed runs; no fault finding named a historical session; 32 of 333 sessions are current under the rule, against 145 had raw pane-sessions files counted (113 of them named only by stale files). Current is never more confident than All: every field of a current session is identical under both scopes, checked over the fixtures and on the real stores from one reading
- disposition: comment
- where: core/Projection.ps1 :: "SCOPE: CURRENT OR ALL, ALL BY DEFAULT"

### L-100 A node serves no session whose end is proven, and keeps every session whose end is not
- source: the always-on node, 2026-10-13 (planning/first-live-link-always-on.md): the hub's `horde nodes` said "2 session(s)" for a node where no session ran. That node has no wezfleet stores and no host adapter, so its projection's only store of sessions is the agent's control files, and a session whose process is ended rather than exiting (a pane closed by hand, or ended by the host after a refused spawn, cli/NodeAct.ps1 Stop-HordeNodeSession) leaves its control file behind; -Scope All keeps every session any store names, and the node served -Scope All. Founder rule, fail-safe: a session is left out only when its death is PROVEN and nothing may say it is live. Get-HordeSessionEndProof's rules, each from the reviews of PR #240 (2026-10-13): the proof is core/identity's processCheck gone or reused, never uncheckable, no-table, a codex file (unchecked) or a duplicate; the agent's control-file listing is complete (a half-written file may be the session resumed under a new pid); the file's procStart is before the process table was read (the table is read before the files are listed); a reused pid counts only when the process now at it is not of the agent's image or host image (CIM's local start time can convert an hour off in the repeated hour of a clock change, core/Platform.ps1, which reads a live agent as reused); no process of the agent's image or host image has an unreadable command line; no process of the agent's image that no control file verifies started after the stale file's process less an hour, or has no start time; when a wezfleet root exists, its registry, runs, rosters and reports were each read whole (a misnamed record or an unlistable folder may hold a signal), while a machine with no wezfleet root has none to hold one; and no other live signal holds (a process resuming it, a guarded pane-sessions file, a registry record not retired or unreadable, an open run, a live handle making its pane known). Done in the node's serving path (ConvertTo-HordeNodeViewDocument, called by `horde node serve`), not in the read model: -Scope All and signal 4 of the current scope stay as L-099 decided. It applies to every verb that reads the view - sessions.list, session.get and session.deliver - so an ended session is not listed, is not delivered to, and session.get answers it absent with its proof ("has ended, proven by its process: ..."), never that no store holds it. Not covered here, by decision: the hub still carries a session a partial inventory leaves out (remote/Mirror.ps1), which the follow-up's membership-complete flag addresses. Rejected: keeping the session listed with liveStatus ended and having the hub count only live ones - identity's L-008 keeps a stale file's live fields unknown, stale files are never cleaned up, so the list would grow toward the link's listItems cap and push live sessions past it, and the hub would have to read the view's reasons to count
- disposition: test
- where: test/test-projection.ps1 :: "a session whose process is gone is not listed by the node"

### L-101 A node's list says it names every session only from the stores its owner declares; the hub then drops what it leaves out
- source: the follow-up of PR #240 (coordinator decision 2026-10-13): the always-on node's sessions.list is never complete - it has no host adapter (X4) and node serve passes no layout port (R1) - and by contract (remote/Mirror.ps1) the hub carries every session a partial inventory leaves out, up to 256, so a session that ended, killed or exited cleanly, stayed on the hub forever ("0 session(s), 2 carried"; the PR #240 probe read carried=2 on every later poll). Decision: split "membership complete" from "fields complete". sessions.list gains an optional membershipComplete (link-verbs v1, verbs version 2: the contract is closed, so a node sends it only when the hub's hello offers 2, and an older hub never sees it; an older node never sends it and is carried as before). It is known true only when every store the node's owner DECLARES names its sessions (node-policy.v1 sessionStores, one of X2, W8, W1, X1, W5; W5 also needs its runs W3 and rosters W4) was read whole, and no session was cut at the list cap or for an id the link cannot carry. A store not declared does not count; no declaration, or a policy that cannot be read, claims nothing; nothing is inferred from a missing folder. The declaration lives in the node policy, not the manifest (what the node SAYS over the link) nor the engine settings (one value per key): it is the owner's own list, read on the node and never written from the link, like the policy's other lists. On the hub, Update-HordeNodeMirror drops a session a membership-complete list leaves out; the node entry's complete (horde nodes, Find-HordeFleetSession) and the listed rows' presence stay on complete, so a dropped session is never read as absent while the fields are partial. Rejected: the node reports the sessions whose end it has proven, for the hub to drop - a clean exit deletes the control file, so nothing is left to prove the end by, and the hub would carry it forever
- disposition: test
- where: test/test-projection.ps1 :: "a clean exit is dropped by the hub"
