module: core/identity
replaces: YedPool/wezfleet lib/MailPump.ps1 (Get-WfClaudeSessionStatus), lib/CodexStatus.ps1 (Get-WfCodexSessionStatus, Get-WfCodexStatusTtlSeconds, Get-WfCodexStatusDir - the read side only), lib/Mail.ps1 (Get-WfSessionPidFor, Get-WfMailSelfId, and Repair-WfMailbox's pid-continuity rule), lib/Hosts.ps1 (Get-WfFleetSessions identity columns), commands/sessions.ps1 (the control-file read), lib/Registry.ps1 (Test-WfLooksLikeClaudeSessionId, Resolve-WfTranscriptPath), lib/Common.ps1 (Get-WfClaudeProcesses and Get-WfDuplicateSessions, as process verification)
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

## What each source held

Harvested 2026-09-30 from YedPool/wezfleet at acda968 and YedPool/horde at 397cef0, read-only, with
a census of this machine's ~/.claude/sessions (10 control files, 10 key files whose contents were not
read) and of wezfleet's codex-sessions directory (0 files: the codex shape is taken from its writer).

- comments: lib/MailPump.ps1:35-67, lib/Mail.ps1:63-172, lib/CodexStatus.ps1:1-256, lib/Hosts.ps1:162-206, commands/sessions.ps1:4-25, lib/Protocol.ps1:351-442, lib/Registry.ps1:84-105, lib/Common.ps1:643-700, hooks/wf-registry-refresh.ps1:64-81.
- history: 648095e, 88aab20, b50b2d4, 27cfafe, 2315a53, 51599f8, f09f4e1, 0e1c75a.
- pull requests: #11 (codex control file); #10 is the first merge after the mail commits, which were made on main outside any pull request; #9 (open) proposes a pane-sessions writer. #1 and #6 touched lib/Common.ps1 and lib/Protocol.ps1 only.
- docs: planning/wezfleet-ssot-multi-backend-2026-09-29.md sections 1.7, 8 and :640-660; planning/registry-design.md:49-53; tasks/lessons.md:324-345; horde planning/ledger/core-ownership.md L-005, L-009, L-013, L-014, L-018, L-032, L-034, L-047, L-048, L-049.
- tests: test_debug/test-mail.ps1:141-193, test_debug/test-mail-pump.ps1:131-157, test_debug/test-codex-status.ps1:44-216, test_debug/test-fleet-sessions.ps1:47-87, test_debug/test-wezfleet.ps1:641-656.

### L-001 A session's identity is complete without a terminal
- source: YedPool/wezfleet commands/sessions.ps1:13-16 "That is a complete identity with no terminal in it"; 27cfafe; lib/Hosts.ps1:170-174
- disposition: test
- where: test/test-identity.ps1 :: "a record built from control files carries no terminal field"

### L-002 A control directory that is missing or unlistable is unknown, never an empty fleet
- source: YedPool/wezfleet lib/MailPump.ps1:53-54 "An empty map means UNKNOWN, never everything is idle", yet :58 returns that same empty map for a missing directory; commands/sessions.ps1:30-31; lib/CodexStatus.ps1:213-218
- disposition: test
- where: test/test-identity.ps1 :: "a missing control directory reads as unknown, not empty"

### L-003 One unreadable control file makes the listing incomplete, not shorter
- source: YedPool/wezfleet lib/MailPump.ps1:60 and lib/CodexStatus.ps1:222 "catch { continue }" drop the file silently; test_debug/test-codex-status.ps1:145 pins the skip; horde core/Roles.ps1 sessionsComplete is the precedent
- disposition: test
- where: test/test-identity.ps1 :: "an unparseable control file makes the listing incomplete"

### L-004 Only <pid>.json is a control file; the key files beside it are never opened
- source: census 2026-09-30: ~/.claude/sessions holds 10 files named <pid>.<64 hex>.key, 111 bytes, one per control file; YedPool/wezfleet lib/MailPump.ps1:59 lists with -Filter *.json. The test holds a key file open with no sharing at all, so any open of it fails the read.
- disposition: test
- where: test/test-identity.ps1 :: "a key file beside a control file is never opened"

### L-005 The file name is the pid, and a file that disagrees with its own pid is refused
- source: census 2026-09-30: file name equals the pid field in 10 of 10; YedPool/wezfleet lib/Mail.ps1:144 keys by the pid field and never looks at the name
- disposition: test
- where: test/test-identity.ps1 :: "a control file whose name disagrees with its pid is refused"

### L-006 A pid is the same process only while procStart equals its creation time
- source: census 2026-09-30: procStart equals Process.StartTime.ToFileTimeUtc() in 10 of 10; wezfleet never checks it (0 hits for procStart; control: the same search finds messagingSocketPath at lib/MailPump.ps1:64); lib/Mail.ps1:156-159 moves mail by bare pid; horde core-ownership L-032
- disposition: test
- where: test/test-identity.ps1 :: "a reused pid makes every live field unknown"

### L-007 procStart is a decimal string and is compared as an integer
- source: census 2026-09-30: procStart is a string in 10 of 10 while pid is an int; horde CONTRIBUTING.md section 12 (integer ticks), core-ownership L-032
- disposition: test
- where: test/test-identity.ps1 :: "procStart is compared as integer ticks, never as text"

### L-008 A control file whose process is gone is stale, and its live fields are unknown
- source: YedPool/wezfleet lib/MailPump.ps1:59-66 reads every file as a running session with no process check; planning/wezfleet-ssot-multi-backend-2026-09-29.md:652-654 (Claude removed its file on exit); 0 of 10 stale files on 2026-09-30, so what a crash leaves is unmeasured
- disposition: test
- where: test/test-identity.ps1 :: "a control file whose process is gone reads its status as unknown"

### L-009 An unreadable process table leaves liveness unknown, not confirmed
- source: YedPool/wezfleet lib/Common.ps1:657-659 returns an empty process list when Win32_Process fails, which a caller cannot tell from no processes; horde core/Tristate.ps1 Invoke-HordeRead
- disposition: test
- where: test/test-identity.ps1 :: "an unreadable process table leaves liveness unknown"

### L-010 A claude process with no control file yields no record
- source: census 2026-09-30: 11 claude.exe, 10 control files; pid 5616 alive with no file, the orphan in planning/wezfleet-ssot-multi-backend-2026-09-29.md:642-655 "an orphaned process, not an orphaned session". The reality check in test/test-identity.ps1 found the same on 2026-09-30: 10 files, 10 verified live, 1 claude process with no file.
- disposition: test
- where: test/test-identity.ps1 :: "a claude process with no control file yields no record"

### L-011 Live status is what the session says about itself; an unseen value is unknown
- source: YedPool/wezfleet 648095e (the screen detector read a mid-turn pane as idle); lib/MailPump.ps1:36-47; census status idle 9, busy 1
- disposition: test
- where: test/test-identity.ps1 :: "an unrecognised claude status reads as unknown"

### L-012 A codex reading past its TTL is unknown, idle included
- source: YedPool/wezfleet lib/CodexStatus.ps1:230-236 "a session killed while idle would then read idle forever"; 2315a53; test_debug/test-codex-status.ps1:103 and :112; horde core-ownership L-014
- disposition: test
- where: test/test-identity.ps1 :: "a stale codex idle reading is unknown"

### L-013 A codex ended reading never expires
- source: YedPool/wezfleet lib/CodexStatus.ps1:234-236 "ended is exempt ... that fact does not decay"; test_debug/test-codex-status.ps1:117
- disposition: test
- where: test/test-identity.ps1 :: "a codex ended reading never expires"

### L-014 A codex TTL override that is not a positive integer is ignored
- source: YedPool/wezfleet lib/CodexStatus.ps1:75-84 (Get-WfCodexStatusTtlSeconds, default 900 at :68); test_debug/test-codex-status.ps1:214-216. horde core/Tristate.ps1 Limit-HordeAge throws on such a TTL, so identity must fall back to 900 before calling it
- disposition: test
- where: test/test-identity.ps1 :: "a bad codex TTL override falls back to the default"

### L-015 A field codex did not write is unknown in the record, never invented
- source: YedPool/wezfleet lib/CodexStatus.ps1:51-57 "the field is OMITTED rather than invented" (no pid, name or socket) and :146-147; test_debug/test-codex-status.ps1:69-79
- disposition: test
- where: test/test-identity.ps1 :: "a codex record has an unknown pid, never an invented one"

### L-016 The codex file carries terminal and wezfleet facts; identity takes none of them
- source: YedPool/wezfleet lib/CodexStatus.ps1:161-167 writes pane, runDir, orchestratorPane and wezfleetSessionId from the environment; horde core/ownership.json gives pane to host and fleetSessionId to engine
- disposition: test
- where: test/test-identity.ps1 :: "a codex pane in the control file is not carried into the record"

### L-017 A codex session has no file until its first turn
- source: YedPool/wezfleet lib/CodexStatus.ps1:19-20 "fires on the FIRST TURN, not at thread creation"
- disposition: comment
- where: core/Identity.ps1 :: "no control file until its first turn"

### L-018 The codex file is written in place, so a read can catch it half-written
- source: YedPool/wezfleet lib/CodexStatus.ps1:200 WriteAllText to the final path, against lib/Mail.ps1:219-223 which writes a temp file and moves it; horde migration-plan section 9 "Added risk"
- disposition: test
- where: test/test-identity.ps1 :: "a half-written codex file reads as unknown, not absent"

### L-019 Every control file is read with read, write and delete sharing
- source: horde core/ReadShared.ps1:4-8 (a plain read makes the writer's Replace fail); YedPool/wezfleet lib/MailPump.ps1:60 uses Get-Content. The test holds every control file open for writing, as its writer would, and shows an ordinary read failing against the same hold.
- disposition: test
- where: test/test-identity.ps1 :: "every control file is read through the shared reader"

### L-020 Two control files naming one session is a finding, never settled by file order
- source: YedPool/wezfleet lib/MailPump.ps1:62 keeps the last file, lib/Mail.ps1:106-108 the first; 0e1c75a "seven conversations ran in both with nothing noticing"; lib/Common.ps1:684-694
- disposition: test
- where: test/test-identity.ps1 :: "two live control files naming one session are reported as a duplicate"

### L-021 Self-identity takes the agent's own export first
- source: YedPool/wezfleet lib/Mail.ps1:75-86 and 88aab20; test_debug/test-mail.ps1:182-187; hooks/wf-registry-refresh.ps1:74-75 "CLAUDE_CODE_SESSION_ID is each process's own id"; horde core-ownership L-013
- disposition: test
- where: test/test-identity.ps1 :: "self identity takes the agent's own session variable first"

### L-022 A fleet id is never returned as a session id
- source: YedPool/wezfleet lib/Mail.ps1:88 returns WEZFLEET_SESSION_ID through the same string as a Claude id; test_debug/test-mail.ps1:190 asserts it as "the second choice"
- disposition: test
- where: test/test-identity.ps1 :: "a fleet id is never returned as a session id"

### L-023 Another session's identity never reads the environment
- source: YedPool/wezfleet lib/Protocol.ps1:361-364 "the environment variable is INHERITED"; test_debug/test-wezfleet.ps1:654-656
- disposition: test
- where: test/test-identity.ps1 :: "another session's identity never reads the environment"

### L-024 Self-identity must not depend on how many terminals are open
- source: YedPool/wezfleet 88aab20 "An identity that depends on how many terminals happen to be open is not an identity"; lib/Mail.ps1:84-85; lib/Registry.ps1:234-247
- disposition: test
- where: test/test-identity.ps1 :: "self identity reads no pane record at all"

### L-025 kind and entrypoint are carried as written; what they say for a nested session is unmeasured
- source: census kind interactive 10, entrypoint cli 10; whether a nested session writes a control file is unmeasured. CORRECTED 2026-09-30, review finding 4 of PR #18: this entry first said the two keys tell a nested session apart, citing YedPool/wezfleet hooks/wf-registry-refresh.ps1:64-81, but what that hook measured on 2026-09-15 (sdk-cli for a nested claude -p against cli for a pane session) is the environment variable CLAUDE_CODE_ENTRYPOINT, not the control-file key
- disposition: test
- where: test/test-identity.ps1 :: "kind and entrypoint are carried as the agent wrote them"

### L-026 Eight control-file keys had no row in the ownership table
- source: census 2026-09-30 against horde core/ownership.json: version, peerProtocol, peerFeatures, kind, entrypoint, pidDomain, nameSince and statusUpdatedAt appeared in 10 of 10 control files and in no X2 read, though core-ownership L-029 claimed every field the old stores hold is kept or dropped. Resolved in core-ownership L-048 (seven kept, statusUpdatedAt dropped); the suite checks the fixture's 20 keys, and the reality check every key on this machine, against the table.
- disposition: test
- where: test/test-identity.ps1 :: "every control file key is kept or dropped"

### L-027 Auto-compaction keeps the session id, so the record is keyed by it
- source: measured 2026-09-30: 12 auto compactions inside 7 live processes, id unchanged in transcript, control file, compact hook and --resume argv; 51 boundaries in 265 transcripts, 0 id changes (core-ownership L-047). Contradicts YedPool/wezfleet lib/Mail.ps1:116 and b50b2d4; agrees with planning/registry-design.md:49-53
- disposition: test
- where: test/test-identity.ps1 :: "records are keyed by session id, with pid and procStart as the process check"

### L-028 Whether /clear changes the id is unmeasured, so a new id in one process is reported, not merged
- source: YedPool/wezfleet lib/Mail.ps1:116 (asserted); transcript 33059eb5 opens with the /clear command (2026-08-21T04:30:03Z); pane-sessions 2.json source clear names d08701e5, which has no transcript; no pairing in one process exists on disk
- disposition: test
- where: test/test-identity.ps1 :: "a rule that rests on the unmeasured clear behaviour is marked provisional"

### L-029 Mail follows a session by pid across an id change
- source: YedPool/wezfleet lib/Mail.ps1:113-172 (Repair-WfMailbox), b50b2d4; test_debug/test-mail.ps1:141-163
- disposition: dropped
- reason: Horde does not port the typed-mail subsystem (migration plan step 6.1); the part that applies, process continuity by pid and procStart, is L-006 and L-028.

### L-030 A former name's sessionId matches the current id in the one file on disk
- source: census 2026-09-30: 17948.json formerNames[0].sessionId equals its sessionId and until equals nameSince, across a compaction at 2026-09-29T00:51:23Z; horde core-ownership L-034 had recorded it as different and is corrected
- disposition: test
- where: test/test-identity.ps1 :: "former names are carried as written and marked provisional"

### L-031 startedAt is the session start in this process, not the process start
- source: census 2026-09-30: startedAt later than process creation in 10 of 10, by 1,341 to 160,266 ms; 19728 startedAt 00:50:32.451Z against its SessionStart file written 00:50:32.6Z
- disposition: test
- where: test/test-identity.ps1 :: "startedAt is never used as the process start"

### L-032 Agent times are epoch milliseconds, and live status is observed at statusUpdatedAt
- source: census 2026-09-30: startedAt, nameSince, updatedAt, statusUpdatedAt are ints in 10 of 10; YedPool/wezfleet lib/CodexStatus.ps1:142-143 and :225 use the same unit
- disposition: test
- where: test/test-identity.ps1 :: "live status is observed at the agent's own status time"

### L-033 bridgeSessionId has three states on disk
- source: census 2026-09-30: string 8, null 1 (18056), key missing 1 (2720)
- disposition: test
- where: test/test-identity.ps1 :: "a null bridge id is absent and a missing one unknown"

### L-034 The control file's cwd names the transcript's project directory
- source: census 2026-09-30: the transcript exists under key(cwd) for 10 of 10; pane-sessions 23.json (compact hook for b12f72ab) gives a deeper cwd than the control file, and the transcript lives under the control file's; horde core-ownership L-049 moves the table's derivation onto it
- disposition: test
- where: test/test-identity.ps1 :: "the claude transcript path is derived from the control file cwd"

### L-035 The project key replaces every non-alphanumeric character, not only colon and slashes
- source: YedPool/wezfleet lib/Registry.ps1:103 "-replace '[:\\/]', '-'"; 149 project directories hold 0 spaces, underscores or dots; a cwd ending Dist Folders\Dist_12_23_25_ai-latency-optimizations maps to ...-Dist-Folders-Dist-12-23-25-ai-latency-optimizations
- disposition: test
- where: test/test-identity.ps1 :: "a cwd with spaces and underscores maps to dashes"

### L-036 A session id is validated before it becomes a key or a path
- source: YedPool/wezfleet lib/Registry.ps1:84-87; lib/CodexStatus.ps1:193-196 "refused instead of sanitised"; lib/Mail.ps1:151
- disposition: test
- where: test/test-identity.ps1 :: "a malformed session id is refused as a key"

### L-037 The messaging address is the agent's own, carried and never written to
- source: YedPool/wezfleet 648095e (the pipe connects but is undocumented internal IPC); planning/wezfleet-ssot-multi-backend-2026-09-29.md section 1.7 (documented cross-session messaging)
- disposition: comment
- where: core/Identity.ps1 :: "as the agent's own messaging address"

### L-038 The live session set is the tie-breaker for a pane-sessions hijack
- source: YedPool/wezfleet f09f4e1 and test_debug/diag-pane-session-hijack.ps1:28-30 "If X is alive, the registry is right and the file is a hijack"; horde core-ownership L-009 hands this to core/identity
- disposition: test
- where: test/test-identity.ps1 :: "the live set lists only sessions whose process is verified"

### L-039 Deciding a hijack compares pane files, which identity does not read
- source: horde core-ownership L-009 and L-018; migration plan step 5.2 "decided from Claude's own list of live sessions"
- disposition: dropped
- reason: Identity has no terminal in it; it supplies the verified live set (L-038) and the pane comparison belongs to the projection (step 2.2) and the pane-sessions writer (step 5.2).

### L-040 Knock only on an idle session
- source: YedPool/wezfleet lib/MailPump.ps1:49-51; test_debug/test-mail-pump.ps1:139-147
- disposition: dropped
- reason: Delivery policy of the typed-mail pump, which Horde does not port (step 6.1); identity only reports the status it read.

### L-041 The readers take their sources as parameters so tests never read the box
- source: YedPool/wezfleet lib/Protocol.ps1:369-380 (four assertions changed answer with the process list, 2026-09-29); b50b2d4 "$SessionDir IS INJECTABLE"; lib/Hosts.ps1:176-177. The suite replaces every function that names a real directory or reads the real process table with a trip wire until its reality check.
- disposition: test
- where: test/test-identity.ps1 :: "the suite reads no real control directory or process table"

### L-042 Process start times are compared to the microsecond, by integer division
- source: horde test/harness/Isolation.ps1:173-183 "Measured 2026-09-29: with / the CIM and .NET readings of the same process disagreed for 304 of 365 processes"; CIM reports creation time to the microsecond while procStart is written in 100-nanosecond ticks, so they are compared after [Math]::DivRem by 10. The reality check matched 10 of 10 live control files against the CIM table on 2026-09-30.
- disposition: test
- where: test/test-identity.ps1 :: "procStart matches the start time at microsecond precision"

### L-044 A control file that cannot be checked against its process is a finding, chosen by kind
- source: review finding 3 of PR #19, 2026-09-30: the reader chose which stale files to report by matching "not running" and "reused" in the verdict's reason text, so a control file with a missing or unparseable procStart, or one whose process the table gave no start time, left its live fields unknown and was reported nowhere. Get-HordeProcessVerdict now returns a kind - verified, gone, reused, uncheckable or no-table - every record carries it as processCheck, and gone, reused and uncheckable each produce a finding. An unreadable process table is reported once, in verifiedLive and the orphan answer, not once per file.
- disposition: test
- where: test/test-identity.ps1 :: "a control file with no procStart is reported as a finding"

### L-045 A leftover file beside one verified file is a finding, not a duplicate
- source: review finding 1 of PR #19, 2026-09-30, with the reviewer's probe: a control file for a dead pid and a live, process-verified file naming the same session id made the whole claude listing incomplete and dropped the live session from records and from verifiedLive. A session resumed after its process died leaves exactly that pair on disk. When one file is verified and every other is proven stale (processCheck gone or reused), the verified file is the record and each other file is a finding; two verified files, or any file that cannot be checked (uncheckable, no-table, or a codex file, which carries no pid), is still a duplicate and never settled (L-020).
- disposition: test
- where: test/test-identity.ps1 :: "a leftover file for a dead process does not hide the live session it names"
