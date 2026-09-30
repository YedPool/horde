# Parity differences for step 2.3 (`horde status --json` against today's commands)

Step 2.2 built `core/projection`, a library. Step 2.3 puts it behind `horde status --json` and must
show it "agrees with today's sessions and census on the same fixtures" (planning/migration-plan.html,
step 2.3). It will not agree everywhere, on purpose. This file lists every place wezfleet's readers
differ from core/ownership.json's rules, and the direction Horde takes, so each difference in the step
2.3 parity run is either one of these - asserted to differ the documented way - or a bug.

Researched 2026-09-30 against YedPool/wezfleet main acda968 and YedPool/horde main c5cb727. Every
file reference is to YedPool/wezfleet unless it says otherwise. Store ids are core/ownership.json's
(W1 registry, W2 claim, W3 run.json, W4 roster, W5 events and status, W6 command logs, W8 codex file,
X1 pane-sessions, X2 claude control file, X3 transcript, X4 live pane list, X5 process table, X6
environment, R1 layout saves).

## How step 2.3 must measure parity

- parity runs wezfleet functions on the fixture: dot-source a pinned wezfleet on a COPY of
  test/fixtures/projection/fleet, with WEZFLEET_ROOT and USERPROFILE pointed at it, stub
  Get-WfLivePanes, Get-WfCurrentInstance and the CIM process query from the fixture's host.json and
  processes.json (the 4947d8c injection pattern), and run Get-WfFleetSessions, Get-WfFleetCensus,
  Get-WfHierarchyFindings and Get-WfRunSnapshot beside Get-HordeProjection. Never a reconstruction of
  those functions: eight hand-built instruments were wrong in one day while the shipped code was right
  (wezfleet tasks/lessons.md, "VERIFY AGAINST THE SHIPPED COMMAND").
- wezfleet status writes before it reads: `status` runs Invoke-WfPump first, which starts every session
  whose dependencies are met (commands/status.ps1:8; commands/pump.ps1:5). Parity calls
  Get-WfRunSnapshot directly and never the command.
- horde status calls the projection: the step 2.3 command must be proven to call Get-HordeProjection
  through the command itself, not only by testing the function - a mutation of the wiring once left a
  wezfleet suite green while the product called nothing (4947d8c; wezfleet tasks/lessons.md 2026-09-09,
  "a mechanism with no callers").
- Census is pane-first and Horde session-first (P-08). The view's `handles` section lists every live
  handle, including handles no session answers, so census parity reads from Horde's own output (the
  lead's decision 3, 2026-09-30).

## The lead's decisions of 2026-09-30, as they bear on parity

1. Several sessions claiming one handle: every claimant's pane is unknown with a reason naming all of
   them, and a `handle-claimed-twice` fault lists them. What census shows - the newest lastSeen - is
   recorded as P-14 and not adopted.
2. No live handle list, or a host reporting no instance running: a stored handle cannot be verified,
   so every pane is unknown with that reason (P-27).
3. The view carries `handles`, so census parity is a view of Horde's own output (P-08).
4. Horde never writes wezfleet's store. The stray records on the measuring machine - the
   fixture-shaped 11111111-2222-4333-8444-555555555555, the f09f4e1 spike session f47a6158, and
   d16b54b2, running with a retired record - stay as real cases, and Horde reports them as faults.

## The differences

**P-01.** `sessions` reads a session's pane only from live pane-sessions files (commands/sessions.ps1:45),
never the registry. Horde reads W1 first. A session with a right registry record and a missing or
refused file shows "-" in sessions and a pane in Horde.

**P-02.** `sessions`, for a live pane with no pane-sessions file, falls through Get-WfClaudeSessionInfo to
the caller's own CLAUDE_CODE_SESSION_ID (lib/Protocol.ps1:438-441) and maps the CALLER's session onto
that pane (commands/sessions.ps1:46); the last such pane in hashtable order wins. Horde never reads the
environment for another session (ownership sessionId row; test "the environment never names another
session"). Found by reading the code; reproducing it needs a live pane list.

**P-03.** `sessions` keeps the last of two live pane-sessions files naming one session
(commands/sessions.ps1:46). Horde's X1 guard needs the only live file naming the session; two make a
`session-in-two-handles` fault and neither answers. On 2026-09-30, 6 of the 10 running sessions were
named by more than one file on disk (14 ids over 32 files); how many were live and fresh is unmeasured.

**P-04.** Empty and unknown are one value: Get-WfLivePanes turns the host's unknown into an empty map
(lib/Common.ps1:501-503), and callers read a count of 0 as unknown (commands/sessions.ps1:41,
lib/Protocol.ps1:170). A mux with zero panes reads "?". Horde: `handles` is known empty, or unknown with
the reason.

**P-05.** `sessions` takes liveStatus and pid from control files it never checks against the process, and
a duplicate is decided by file order (lib/MailPump.ps1:59-62). Horde uses core/identity: a live field is
known only for the process the file describes.

**P-06.** `sessions` prints "UNKNOWN, not an empty fleet" when its map is empty (commands/sessions.ps1:30-32),
which is also what an existing directory with zero sessions, or one where every file fails to parse,
gives (lib/MailPump.ps1:58-61, a silent continue). Horde: X2's completeness answer, naming each file.

**P-07.** `sessions` label: non-retired W1 only, never W2 (commands/sessions.ps1:56-63). Horde: W1 label
whatever `retired` says, then the guarded claim.

**P-08.** Row keys differ: census has one row per live pane, `sessions` and Horde one per session. Parity
compares census with Horde's `handles` section.

**P-09.** Census's `cwd` is the registry's current directory (lib/Registry.ps1:859), and it derives the
transcript from it with a colon-and-slash key (:861, :103). The transcript is filed under the launch
directory. On 2026-09-30, 5 of 31 records had a cwd other than firstCwd, and census's rule found 23
transcripts where the firstCwd rule found 26. Horde's `cwd` is the control file's first (the launch
directory), and the transcript comes from the control file, else the one file for the id in any project
folder (test "parity exception census transcript from current cwd").

**P-10.** Three liveness-age rules: census reads the transcript alone (lib/Registry.ps1:871-876); the run
snapshot reads the run and loose command logs and the transcript, clamping a future time to 0
(lib/Activity.ps1:252-282); Horde reads the newest of W6, X3, X2 updatedAt and W8, and a time more than
5 s in the future makes lastActivity unknown (core/Tristate.ps1 Limit-HordeAge).

**P-11.** Census prints the stored owner, "(unowned)" when empty (commands/census.ps1:17), and builds
"YOU opened, nobody owns" on the empty owner (lib/Registry.ps1:1201). Horde derives the owner from the
parent's label, else founder. On 2026-09-30: 9 records agreed and 7 differed, all 7 empty where founder is
derived.

**P-12.** Census prints origin "unknown" for a record with none (lib/Registry.ps1:858). Horde: absent.

**P-13.** Census's pane-sessions fallback (lib/Registry.ps1:840) applies only Read-WfPaneSessionFile's
guards. Horde adds "the only live file naming that session" and "no running session holds that handle in
the registry" (the f09f4e1 hijack), so it shows fewer X1 answers than census on a doubled or hijacked
handle.

**P-14.** One handle claimed by several non-retired records in one instance: census's index keeps the
newest lastSeen silently (lib/Registry.ps1:395). Horde: every claimant unknown, a `handle-claimed-twice`
fault (decision 1). Live on 2026-09-30: pane 27 of gui-sock-15476 was claimed by three records -
38d41f80 (running), 11111111-2222-4333-8444-555555555555 (cwd C:/w, the test-fixture shape) and f47a6158
(the spike session) - and census showed the first.

**P-15.** Census's `title` is the host's tab title (lib/Registry.ps1:854); the table's `title` is the
roster's. Horde keeps them apart: `hostTitle` on a handle, `title` on a session.

**P-16.** `census` prints "no live panes." when the mux is unreadable (commands/census.ps1:10-11). Horde's
`handles` is unknown there, never empty (test "parity exception unreadable mux is not an empty census").

**P-17.** The run snapshot's pane is the roster's, overridden by the report's, overridden by the registry
only when the registry record is at most 900 s old (lib/Protocol.ps1:533-537; lib/Registry.ps1:537-556).
Horde reads W1 first with no age limit, then X1, then W5, then W4, as the ownership pane row says. And
Horde applies one guard to every stored handle, not only the registry's: it answers only when the host
lists it live now and it was written after the host instance started. The row gives that guard to W1
explicitly; W5 and W4 hold handles written at spawn time just the same, and handles are reused
(562f0e8, 0e1c75a), so without it an old run's roster would name a live stranger. Test "parity exception
snapshot pane order".

**P-18.** The snapshot derives the session from the pane (Get-WfPaneIdentity, then X1, then W5;
lib/Protocol.ps1:555-569). Horde never goes from a pane to a session (D3; test "no session is inferred
from a pane number").

**P-19.** Snapshot state reads status.json; the table says events.jsonl is the truth and status.json its
cache. Horde reads the log, and a torn line makes the report unknown rather than shorter.

**P-20.** `wezfleet status` mutates before it reads (the pump). Parity uses Get-WfRunSnapshot only (see
above).

**P-21.** Get-WfSession returns name and nameSource from W1 (lib/Registry.ps1:504-505); 0 of 31 records
carry a `name` key. Horde's name is X2's, then X1's session_title.

**P-22.** runId among closed-only runs: Resolve-WfRunForSession returns hits[0] (lib/Common.ps1:349). The
table is silent on several closed runs; Horde reports them as ambiguous and chooses none (test "two closed
runs are not chosen between"). Live 2026-09-30: 185 of 194 runs had no closedAt; 5 fleet ids were spawned
in more than one open run; 4 were in more than one open run with none spawned.

**P-23.** `tree`'s pane has no live check (lib/Common.ps1:603-608) and no fallback. Horde's pane is a live
handle, with the fallbacks.

**P-24.** wezfleet compares roles literally and ignores roleless records (lib/Hierarchy.ps1:46-47). Horde
maps roles through core/roles and counts a roleless live record as unsure: on 2026-09-30, warchief floor
1 with 9 unsure, so "two warchiefs" is unknown in Horde where wezfleet reports nothing. "No warchief" is
known false in both.

**P-25.** A parent retired after the edge was set reads "parent-missing" in wezfleet, which drops retired
records before the lookup (lib/Hierarchy.ps1:42-58). Horde reports `parent-missing` and `parent-retired`
apart. Live 2026-09-30: 0 of 8 parents missing or retired.

**P-26.** A running session with a retired record: census's index skips the record (lib/Registry.ps1:393),
so its pane comes from X1 or reads none. Horde does the same through "not retired", and also raises a
`running-but-retired` fault. Live 2026-09-30: d16b54b2, idle, retired 2026-09-23T03:22Z, its lastSeen
still advanced by the hook.

**P-27.** With no terminal process running, Test-WfWrittenInInstance trusts every record
(lib/Common.ps1:624, :626). Horde: a stored handle cannot be verified, so the pane is unknown (decision 2;
test "with no host instance running every pane is unknown").

## Not compared

Census's title drift, bare-shell detection, unsent input-box text and disk space (commands/census.ps1:38-123)
are host presentation or machine health, not session facts; see planning/ledger/core-projection.md
L-058 to L-060.
