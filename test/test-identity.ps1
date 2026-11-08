# DOES CORE/IDENTITY READ EVERY AGENT'S CONTROL FILES INTO ONE RECORD SHAPE, CORRECTLY, AND WITHOUT
# EVER WRITING ANYTHING?
#
# Every lesson here is cited in planning/ledger/core-identity.md. The fixture sections read only
# throwaway directories built in TEMP and process tables built in memory; the functions that would
# read the real machine are replaced by trip wires until the last section, which is a read-only
# reality check over this machine's own ~/.claude/sessions (skipped when there is none).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
# The shared helper first, so an error while loading the module is recorded like any other.
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
# Strictest mode throughout, so the module is proved to work for a caller that uses it.
Set-StrictMode -Version Latest
. (Join-Path $root "core\Identity.ps1")
. (Join-Path $root "core\Ownership.ps1")
Set-StrictMode -Version Latest

# TRIP WIRES (ledger L-041). Until the reality check, nothing in this suite may read the real control
# directories or the real process table. The functions that would are replaced here, after loading,
# so a reader that ignored an injected source - or a default that leaked - trips one and is counted.
# The real ones are kept and put back for the reality check.
#
# A TRIP RECORDS AND ANSWERS HARMLESSLY; IT DOES NOT THROW. A throwing trip wire stopped the fixture
# section at the first leak, before the check that counts trips could run, so the mutation run saw a
# crashed suite and no failed check - not a catch (measured 2026-09-30, mutant injected-table-ignored).
# So a tripped table is an unknown answer and a tripped directory is one that does not exist.
$script:trips = New-Object System.Collections.ArrayList
$realProcessTable = ${function:Get-HordeProcessTable}
$realClaudeDir = ${function:Get-HordeClaudeSessionsDir}
$realProjectsDir = ${function:Get-HordeClaudeProjectsDir}
$realCodexDir = ${function:Get-HordeCodexSessionsDir}
function Get-HordeProcessTable { [void]$script:trips.Add("process table"); return (New-HordeUnknown -Reason "TRIP: the real process table was asked for") }
function Get-HordeClaudeSessionsDir { [void]$script:trips.Add("claude sessions"); return (Join-Path $env:TEMP ("horde-identity-trip-" + [guid]::NewGuid().ToString("N"))) }
function Get-HordeClaudeProjectsDir { [void]$script:trips.Add("claude projects"); return (Join-Path $env:TEMP ("horde-identity-trip-" + [guid]::NewGuid().ToString("N"))) }
function Get-HordeCodexSessionsDir { [void]$script:trips.Add("codex sessions"); return (Join-Path $env:TEMP ("horde-identity-trip-" + [guid]::NewGuid().ToString("N"))) }

$ownership = Get-HordeOwnership -Path (Join-Path $root "core\ownership.json")
$agentOwned = @($ownership.fields | Where-Object { "$($_.owner)" -ceq "agent" -and "$($_.name)" -cne "sessionId" } | ForEach-Object { "$($_.name)" })

function St { param($Answer) return "$($Answer.state)" }
function Val { param($Answer) if ($Answer.state -eq "known") { return $Answer.value } return $null }
function Encoding { return (New-Object System.Text.UTF8Encoding($false)) }
function PutJson { param([string]$Path, $Obj) [System.IO.File]::WriteAllText($Path, ($Obj | ConvertTo-Json -Depth 6), (Encoding)) }
function PutText { param([string]$Path, [string]$Text) [System.IO.File]::WriteAllText($Path, $Text, (Encoding)) }
function EpochMs { param([datetime]$Time) return ([DateTimeOffset]$Time.ToUniversalTime()).ToUnixTimeMilliseconds() }
function Sid { param([int]$N) return ("aaaaaaaa-0000-4000-8000-" + $N.ToString("000000000000")) }

# One process creation time with sub-microsecond ticks, as .NET reports it; CIM reports the same
# time truncated to the microsecond.
$t0 = New-Object DateTime 2026, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc)
$t0 = $t0.AddTicks(1234567)
function Created { param([int]$Seconds) return $t0.AddSeconds($Seconds) }
function Micro { param([datetime]$Time) $rem = [long]0; $us = [Math]::DivRem($Time.Ticks, [long]10, [ref]$rem); return (New-Object DateTime ($us * 10), ([DateTimeKind]::Utc)) }

function ClaudeRec {
    # A control file with the 19 keys every census file had. Values are invented; the shape is the
    # census's (2026-09-30): procStart a decimal string of file-time ticks, times in epoch ms.
    param([int]$ProcId, [string]$SessionId, [datetime]$Created, [hashtable]$Set = @{}, [string[]]$Drop = @())
    $ms = EpochMs $Created.AddSeconds(90)
    $o = [ordered]@{
        pid = $ProcId; sessionId = $SessionId; cwd = "C:\work\proj"; startedAt = (EpochMs $Created.AddSeconds(5))
        procStart = "" + $Created.ToFileTimeUtc(); version = "9.9.9"; peerProtocol = 1; peerFeatures = @("f-one", "f-two")
        kind = "interactive"; entrypoint = "cli"; pidDomain = "win32:tester"; messagingSocketPath = ("\\.\pipe\LOCAL\test-" + $ProcId)
        name = ("fixture-" + $ProcId); nameSource = "user"; nameSince = $ms; updatedAt = $ms; status = "idle"; statusUpdatedAt = $ms
        bridgeSessionId = ("bridge-" + $ProcId)
    }
    foreach ($k in $Set.Keys) { $o[$k] = $Set[$k] }
    foreach ($k in $Drop) { $o.Remove($k) }
    return $o
}
function Table {
    # An injected process table: rows of @(pid, name, created). Always known; an unreadable table is
    # built with New-HordeUnknown where a test needs one.
    param([object[]]$Rows)
    $t = @{}
    foreach ($r in $Rows) { $t[[int]$r[0]] = [pscustomobject]@{ pid = [int]$r[0]; name = "$($r[1])"; created = $r[2] } }
    return (New-HordeKnown -Value $t)
}

$work = Join-Path $env:TEMP ("horde-identity-" + [guid]::NewGuid().ToString("N"))
$script:dirCount = 0
function NewDir {
    # A fresh, empty directory inside this run's throwaway folder.
    param([string]$Name)
    $script:dirCount++
    $d = Join-Path $work ($Name + "-" + $script:dirCount)
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    return $d
}
$now = New-Object DateTime 2026, 6, 1, 12, 0, 0, ([DateTimeKind]::Utc)
$empty = $null

try {
New-Item -ItemType Directory -Path $work -Force | Out-Null
$empty = NewDir "empty"

Write-Host ""
Write-Host "--- loading the module ---" -ForegroundColor Cyan
$strictKept = & { Set-StrictMode -Version Latest; . (Join-Path $root "core\Identity.ps1"); try { $null = $hordeNeverAssignedVariable; $false } catch { $true } }
Check ($strictKept -eq $true) "dot-sourcing core/identity leaves the caller's strict mode on"

Write-Host ""
Write-Host "--- one healthy claude directory ---" -ForegroundColor Cyan
# 101 is running and is the process its file describes; 102's process is gone; 103's pid now
# belongs to a later process; 105 is a claude process with no file; 106 is not claude at all.
$cDir = NewDir "claude"
$pDir = NewDir "projects"
PutJson (Join-Path $cDir "101.json") (ClaudeRec 101 (Sid 1) (Created 0))
PutJson (Join-Path $cDir "102.json") (ClaudeRec 102 (Sid 2) (Created 10))
PutJson (Join-Path $cDir "103.json") (ClaudeRec 103 (Sid 3) (Created 20))
# The key file beside each control file (census: <pid>.<64 hex>.key). Held with no sharing at all for
# the whole read, so any attempt to open it - even to read - fails the read.
$keyPath = Join-Path $cDir ("101." + ("0123456789abcdef" * 4) + ".key")
PutText $keyPath "not-a-real-key"
New-Item -ItemType Directory -Path (Join-Path $pDir "C--work-proj") -Force | Out-Null
PutText (Join-Path $pDir ("C--work-proj\" + (Sid 1) + ".jsonl")) "{}"
$procs = Table @(
    @(101, "claude.exe", (Micro (Created 0))),
    @(103, "claude.exe", (Micro (Created 500))),
    @(105, "claude.exe", (Created 30)),
    @(106, "notepad.exe", (Created 40)))

$keyHold = [System.IO.File]::Open($keyPath, "Open", "Read", "None")
$id = $null
try { $id = Get-HordeIdentity -ClaudeDir $cDir -ProjectsDir $pDir -CodexDir $empty -Processes $procs -Now $now }
finally { $keyHold.Dispose() }
Check ($null -ne $id -and (St $id.complete.claude) -eq "known") "a key file beside a control file is never opened"

$r1 = $id.records[(Sid 1)]
$r2 = $id.records[(Sid 2)]
$r3 = $id.records[(Sid 3)]
Check ($id.records.Count -eq 3 -and $null -ne $r1 -and $null -ne $r2 -and $null -ne $r3) ("CONTROL: the three control files were read (" + $id.records.Count + " records)")
Check ($r1.sessionId -ceq (Sid 1) -and (Val $r1.fields.pid) -eq 101 -and (Val $r1.fields.procStart) -eq (Created 0).ToFileTimeUtc()) "records are keyed by session id, with pid and procStart as the process check"
Check ((Val $r1.fields.liveStatus) -eq "idle" -and (Val $r1.fields.agent) -eq "claude") "CONTROL: a verified session reads its status as known"
$fieldKeys = @($r1.fields.Keys)
$terminal = @($fieldKeys | Where-Object { @("pane", "window", "hostInstance") -contains $_ })
$notAgent = @($fieldKeys | Where-Object { $agentOwned -cnotcontains $_ })
foreach ($n in @($terminal) + @($notAgent)) { Write-Host ("  not an agent field: " + $n) -ForegroundColor Red }
Check ($terminal.Count -eq 0 -and $notAgent.Count -eq 0) "a record built from control files carries no terminal field"
$missing = @($agentOwned | Where-Object { $fieldKeys -cnotcontains $_ })
Check ($missing.Count -eq 0 -and $fieldKeys.Count -eq $agentOwned.Count) ("a record carries exactly the agent-owned fields of the ownership table (missing: " + ($missing -join ", ") + ")")
$allAnswers = @($fieldKeys | Where-Object { -not (Test-HordeAnswer $r1.fields[$_]) })
Check ($allAnswers.Count -eq 0) ("every field of a record is a horde answer (" + ($allAnswers -join ", ") + ")")

Check ((St $r2.fields.liveStatus) -eq "unknown" -and $r2.fields.liveStatus.reason -like "*not running*") "a control file whose process is gone reads its status as unknown"
Check ((St $r2.fields.pid) -eq "unknown" -and (Val $r2.fields.cwd) -eq "C:\work\proj" -and (Val $r2.fields.name) -eq "fixture-102") "and its identity fields stay known as written"
$live3 = @("liveStatus", "pid", "procStart", "messagingAddress" | Where-Object { (St $r3.fields[$_]) -ne "unknown" -or $r3.fields[$_].reason -notlike "*reused*" })
foreach ($n in $live3) { Write-Host ("  still believed after the pid was reused: " + $n) -ForegroundColor Red }
Check ($live3.Count -eq 0) "a reused pid makes every live field unknown"
Check ((Val $r3.fields.sessionKind) -eq "interactive") "CONTROL: a reused pid leaves the identity fields known"

$orph = @(Val $id.orphanProcesses)
Check ($orph -contains 105 -and $orph -notcontains 101 -and $orph -notcontains 106) "a claude process with no control file yields no record"
# AN ORPHAN IS A CLAUDE PROCESS NO FILE VERIFIES. 103's file is stale and its pid now belongs to a
# later claude process; counting any file at that pid as a match hid the new process (review
# finding 2 of PR #19).
Check ((St $id.orphanProcesses) -eq "known" -and $orph -contains 103 -and $orph.Count -eq 2) "a claude process whose pid a stale file names is still an orphan"
Check ("$($id.provisional['orphanProcesses'])" -like "*claude.exe*node*") "the process names an orphan is looked for under are marked provisional"
$liveSet = @(Val $id.verifiedLive)
Check ((St $id.verifiedLive) -eq "known" -and $liveSet.Count -eq 1 -and $liveSet -contains (Sid 1)) "the live set lists only sessions whose process is verified"

# L-033: the three states bridgeSessionId has on disk.
Check ((Val $r1.fields.bridgeSessionId) -eq "bridge-101") "CONTROL: a written bridge id is known"
Check ((Val $r1.fields.messagingAddress) -eq "\\.\pipe\LOCAL\test-101") "the messaging address is carried as the agent wrote it"

# L-034: the transcript lives under the control file's cwd, and must exist.
$expectT = Join-Path $pDir ("C--work-proj\" + (Sid 1) + ".jsonl")
Check ((Val $r1.fields.transcriptPath) -eq $expectT) "the claude transcript path is derived from the control file cwd"
Check ((St $r2.fields.transcriptPath) -eq "unknown" -and $r2.fields.transcriptPath.reason -like "*does not exist*") "a derived transcript that is not there is unknown"

Write-Host ""
Write-Host "--- the process check ---" -ForegroundColor Cyan
# L-007: procStart is a decimal string on disk; compared as a number, "0" + ticks is the same time.
$d7 = NewDir "claude"
$c7 = Created 100
PutJson (Join-Path $d7 "201.json") (ClaudeRec 201 (Sid 21) $c7 -Set @{ procStart = ("00" + $c7.ToFileTimeUtc()) })
PutJson (Join-Path $d7 "202.json") (ClaudeRec 202 (Sid 22) $c7 -Set @{ procStart = [long]$c7.ToFileTimeUtc() })
$r7 = Get-HordeIdentity -ClaudeDir $d7 -ProjectsDir $pDir -CodexDir $empty -Processes (Table @(@(201, "claude.exe", $c7), @(202, "claude.exe", $c7))) -Now $now
Check ((Val $r7.records[(Sid 21)].fields.liveStatus) -eq "idle" -and (Val $r7.records[(Sid 22)].fields.liveStatus) -eq "idle") "procStart is compared as integer ticks, never as text"
# Microsecond precision: CIM reports creation to the microsecond, .NET to 100 ns. The same process
# read both ways must match; one microsecond apart is another process.
$d8 = NewDir "claude"
PutJson (Join-Path $d8 "211.json") (ClaudeRec 211 (Sid 31) (Created 0))
PutJson (Join-Path $d8 "212.json") (ClaudeRec 212 (Sid 32) (Created 0))
$r8 = Get-HordeIdentity -ClaudeDir $d8 -ProjectsDir $pDir -CodexDir $empty -Processes (Table @(@(211, "claude.exe", (Micro (Created 0))), @(212, "claude.exe", (Micro (Created 0)).AddTicks(10)))) -Now $now
Check ((St $r8.records[(Sid 31)].fields.liveStatus) -eq "known") "procStart matches the start time at microsecond precision"
# A REAL-SIZED TICK COUNT. The fixture times above happen to survive a conversion through a double;
# a procStart read from a live control file on 2026-09-30 does not - dividing it by 10 as a double
# puts it in another microsecond than its own CIM reading. The reality check used to be the only
# thing that caught that, and a pid reuse on the machine now only reports (review finding 6 of PR
# #19), so the value is pinned here.
$realTicks = [long]134350994473105437
$realStart = [DateTime]::FromFileTimeUtc($realTicks)
$d8b = NewDir "claude"
PutJson (Join-Path $d8b "213.json") (ClaudeRec 213 (Sid 33) $realStart -Set @{ procStart = ("" + $realTicks) })
$r8b = Get-HordeIdentity -ClaudeDir $d8b -ProjectsDir $pDir -CodexDir $empty -Processes (Table @(, @(213, "claude.exe", (Micro $realStart)))) -Now $now
Check ((St $r8b.records[(Sid 33)].fields.liveStatus) -eq "known") "a real 18-digit procStart matches its own microsecond-truncated start time"
Check ((St $r8.records[(Sid 32)].fields.liveStatus) -eq "unknown" -and $r8.records[(Sid 32)].fields.liveStatus.reason -like "*reused*") "a start time one microsecond away is another process"
$d9 = NewDir "claude"
PutJson (Join-Path $d9 "221.json") (ClaudeRec 221 (Sid 41) (Created 0) -Set @{ procStart = "yesterday" })
$r9 = Get-HordeIdentity -ClaudeDir $d9 -ProjectsDir $pDir -CodexDir $empty -Processes (Table @(, @(221, "claude.exe", (Created 0)))) -Now $now
Check ((St $r9.records[(Sid 41)].fields.liveStatus) -eq "unknown" -and $r9.records[(Sid 41)].fields.liveStatus.reason -like "*procStart*") "a procStart that is not an integer leaves liveness unknown"
# A FILE THAT CANNOT BE CHECKED IS A FINDING, like one that is stale. The verdict names its kind, and
# the findings are chosen by that kind: they were chosen by words in the reason text, so a missing
# procStart, or a process the table gives no start time, was a file nobody heard about (review
# finding 3 of PR #19).
$d9b = NewDir "claude"
PutJson (Join-Path $d9b "222.json") (ClaudeRec 222 (Sid 42) (Created 0) -Drop @("procStart"))
PutJson (Join-Path $d9b "223.json") (ClaudeRec 223 (Sid 43) (Created 0))
$r9b = Get-HordeIdentity -ClaudeDir $d9b -ProjectsDir $pDir -CodexDir $empty -Processes (Table @(@(222, "claude.exe", (Created 0)), @(223, "claude.exe", $null))) -Now $now
Check (@($r9b.findings | Where-Object { $_ -like "222.json:*procStart*" }).Count -eq 1) "a control file with no procStart is reported as a finding"
Check (@($r9b.findings | Where-Object { $_ -like "223.json:*no start time*" }).Count -eq 1) "a process the table gives no start time is reported as a finding"
Check ("$($r9b.records[(Sid 42)].processCheck)" -ceq "uncheckable" -and "$($r1.processCheck)" -ceq "verified" -and "$($r2.processCheck)" -ceq "gone" -and "$($r3.processCheck)" -ceq "reused") "every control file says which process check it passed or failed"
Check ((St $r9b.orphanProcesses) -eq "unknown" -and $r9b.orphanProcesses.reason -like "*222*") "a claude process whose file cannot be checked is neither an orphan nor verified"
# CLAUDE CAN RUN UNDER NODE, and a node process no file verifies may be a claude with no file. So
# the orphan answer is unknown while one runs, never a known list that may be short; a node process
# a file verifies is that claude, and does not stand in the way.
$d9c = NewDir "claude"
PutJson (Join-Path $d9c "231.json") (ClaudeRec 231 (Sid 44) (Created 0))
$r9c = Get-HordeIdentity -ClaudeDir $d9c -ProjectsDir $pDir -CodexDir $empty -Processes (Table @(@(231, "node.exe", (Created 0)), @(232, "claude.exe", (Created 3)))) -Now $now
Check ((St $r9c.orphanProcesses) -eq "known" -and @(Val $r9c.orphanProcesses).Count -eq 1 -and @(Val $r9c.verifiedLive) -contains (Sid 44)) "CONTROL: a claude under node that its file verifies is no orphan"
$r9d = Get-HordeIdentity -ClaudeDir $d9c -ProjectsDir $pDir -CodexDir $empty -Processes (Table @(@(231, "node.exe", (Created 0)), @(233, "node.exe", (Created 9)))) -Now $now
Check ((St $r9d.orphanProcesses) -eq "unknown" -and $r9d.orphanProcesses.reason -like "*node*") "a node process no file verifies leaves the orphan answer unknown"

# L-031: startedAt is the session start inside the process, seconds after the process began. It is
# never the process check - here startedAt equals the table's time and procStart does not.
$d10 = NewDir "claude"
$c10 = Created 0
PutJson (Join-Path $d10 "231.json") (ClaudeRec 231 (Sid 51) $c10 -Set @{ startedAt = (EpochMs $c10.AddSeconds(60)) })
PutJson (Join-Path $d10 "232.json") (ClaudeRec 232 (Sid 52) $c10 -Set @{ startedAt = (EpochMs $c10) })
$r10 = Get-HordeIdentity -ClaudeDir $d10 -ProjectsDir $pDir -CodexDir $empty -Processes (Table @(@(231, "claude.exe", $c10), @(232, "claude.exe", $c10.AddSeconds(60)))) -Now $now
Check ((St $r10.records[(Sid 51)].fields.liveStatus) -eq "known" -and (St $r10.records[(Sid 52)].fields.liveStatus) -eq "unknown") "startedAt is never used as the process start"
Check ((Val $r10.records[(Sid 51)].fields.startedAt) -eq $c10.AddSeconds(60).AddTicks(-($c10.AddSeconds(60).Ticks % 10000))) "CONTROL: startedAt is still carried, as the session's own start"

# L-009: a process table that could not be read.
$r11 = Get-HordeIdentity -ClaudeDir $cDir -ProjectsDir $pDir -CodexDir $empty -Processes (New-HordeUnknown -Reason "the fixture's table is unreadable") -Now $now
$s11 = $r11.records[(Sid 1)].fields.liveStatus
Check ((St $s11) -eq "unknown" -and $s11.reason -like "*unreadable*" -and (St $r11.verifiedLive) -eq "unknown" -and (St $r11.orphanProcesses) -eq "unknown") "an unreadable process table leaves liveness unknown"
Check (Throws { Get-HordeIdentity -ClaudeDir $cDir -ProjectsDir $pDir -CodexDir $empty -Processes @{ 101 = "x" } -Now $now } "process table") "a process table that is not an answer is refused"

Write-Host ""
Write-Host "--- what the agent wrote, as it wrote it ---" -ForegroundColor Cyan
$d12 = NewDir "claude"
$c12 = Created 0
$stamp = $c12.AddMinutes(7)
PutJson (Join-Path $d12 "301.json") (ClaudeRec 301 (Sid 61) $c12 -Set @{ status = "thinking" })
PutJson (Join-Path $d12 "302.json") (ClaudeRec 302 (Sid 62) $c12 -Set @{ status = "busy"; statusUpdatedAt = (EpochMs $stamp); bridgeSessionId = $null; kind = "odd-kind"; entrypoint = "sdk-cli" })
PutJson (Join-Path $d12 "303.json") (ClaudeRec 303 (Sid 63) $c12 -Drop @("bridgeSessionId", "status"))
PutJson (Join-Path $d12 "304.json") (ClaudeRec 304 (Sid 64) $c12 -Set @{ formerNames = @(@{ name = "old-name"; until = (EpochMs $c12); sessionId = (Sid 64) }, @{ name = "older"; until = (EpochMs $c12); sessionId = (Sid 99) }) })
# core-identity L-054: waitingFor is written beside status only while the session waits on the user - "permission
# prompt" in the one waiting file of 10 on 2026-09-30, and absent from the 9 idle ones. 305 waits and
# says for what; 306 waits and says nothing; 307 waited, but its process is gone.
PutJson (Join-Path $d12 "305.json") (ClaudeRec 305 (Sid 65) $c12 -Set @{ status = "waiting"; waitingFor = "permission prompt" })
PutJson (Join-Path $d12 "306.json") (ClaudeRec 306 (Sid 66) $c12 -Set @{ status = "waiting" })
PutJson (Join-Path $d12 "307.json") (ClaudeRec 307 (Sid 67) $c12 -Set @{ status = "waiting"; waitingFor = "dialog open" })
# Review of PR #24: 308 names its wait as a number, not text; 309 names it as the empty string.
PutJson (Join-Path $d12 "308.json") (ClaudeRec 308 (Sid 68) $c12 -Set @{ waitingFor = 5 })
PutJson (Join-Path $d12 "309.json") (ClaudeRec 309 (Sid 69) $c12 -Set @{ status = "waiting"; waitingFor = "" })
$tab12 = Table @(@(301, "claude.exe", $c12), @(302, "claude.exe", $c12), @(303, "claude.exe", $c12), @(304, "claude.exe", $c12), @(305, "claude.exe", $c12), @(306, "claude.exe", $c12), @(308, "claude.exe", $c12), @(309, "claude.exe", $c12))
$r12 = Get-HordeIdentity -ClaudeDir $d12 -ProjectsDir $pDir -CodexDir $empty -Processes $tab12 -Now $now
$a = $r12.records[(Sid 61)]; $b = $r12.records[(Sid 62)]; $c = $r12.records[(Sid 63)]; $e = $r12.records[(Sid 64)]
Check ((St $a.fields.liveStatus) -eq "unknown" -and $a.fields.liveStatus.reason -like "*'thinking'*") "an unrecognised claude status reads as unknown"
Check ((St $c.fields.liveStatus) -eq "unknown") "a control file with no status reads its status as unknown"
Check ((Val $b.fields.liveStatus) -eq "busy" -and $b.fields.liveStatus.observedAt -eq $stamp.AddTicks(-($stamp.Ticks % 10000))) "live status is observed at the agent's own status time"
Check ((St $b.fields.bridgeSessionId) -eq "absent" -and (St $c.fields.bridgeSessionId) -eq "unknown") "a null bridge id is absent and a missing one unknown"
Check ((Val $b.fields.sessionKind) -ceq "odd-kind" -and (Val $b.fields.entrypoint) -ceq "sdk-cli") "kind and entrypoint are carried as the agent wrote them"
Check ((Val $b.fields.agentVersion) -eq "9.9.9" -and (Val $b.fields.pidDomain) -eq "win32:tester" -and @(Val $b.fields.peerFeatures).Count -eq 2 -and (Val $b.fields.peerProtocol) -eq 1) "the control file's own facts are carried under their horde names"
$fn = @(Val $e.fields.formerNames)
Check ($fn.Count -eq 2 -and "$($fn[0].name)" -eq "old-name" -and "$($fn[1].sessionId)" -eq (Sid 99) -and "$($e.provisional['formerNames'])" -ne "") "former names are carried as written and marked provisional"
Check ("$($e.provisional['formerNames'])" -like "*/clear*") "a rule that rests on the unmeasured clear behaviour is marked provisional"
Check (-not $r12.records.ContainsKey((Sid 99)) -and @($r12.findings | Where-Object { $_ -like ("*" + (Sid 99) + "*") }).Count -eq 1) "a former name naming another session is reported, not merged"
Check ((St $a.fields.resumeCommand) -eq "unknown" -and $a.fields.resumeCommand.reason -like "*AgentPort*") "the resume command is left to the agent port"
# Read by index, so a record with no waitingFor at all fails these checks instead of stopping the suite.
$w5 = $r12.records[(Sid 65)].fields["waitingFor"]; $w6 = $r12.records[(Sid 66)].fields["waitingFor"]; $w7 = $r12.records[(Sid 67)].fields["waitingFor"]
$wb = $b.fields["waitingFor"]; $w1 = $r1.fields["waitingFor"]
Check ($null -ne $w5 -and (Val $w5) -ceq "permission prompt") "a waiting session says what it waits for"
# Review of PR #24: the wait is observed when the status beside it was written, like the status.
$ls5 = $r12.records[(Sid 65)].fields["liveStatus"]
Check ($null -ne $w5 -and $null -ne $w5.observedAt -and $null -ne $ls5 -and $w5.observedAt -eq $ls5.observedAt) "a wait is observed at the agent's own status time"
# L-055: waiting is a status Claude Code writes (1 of 10 control files on 2026-09-30), not a guess.
Check ((Val $r12.records[(Sid 65)].fields["liveStatus"]) -ceq "waiting") "a claude session waiting on the user reads its status as known"
Check ($null -ne $wb -and $null -ne $w1 -and (St $wb) -eq "absent" -and (St $w1) -eq "absent") "a session that is not waiting waits for nothing"
Check ($null -ne $w6 -and (St $w6) -eq "unknown") "a waiting session that names nothing is unknown, not absent"
Check ($null -ne $w7 -and (St $w7) -eq "unknown" -and $w7.reason -like "*not running*") "a stale control file says nothing about a wait"
# Review of PR #24, hand mutants R3-R5, each of which these three checks did not exist to catch.
$w8 = $r12.records[(Sid 68)].fields["waitingFor"]; $w9 = $r12.records[(Sid 69)].fields["waitingFor"]; $w63 = $c.fields["waitingFor"]
Check ($null -ne $w8 -and (St $w8) -eq "unknown" -and $w8.reason -like "*not text*") "a wait that is not text is unknown, whatever the status"
Check ($null -ne $w63 -and (St $w63) -eq "unknown" -and $w63.reason -like "*no status*") "a control file with no status leaves the wait unknown"
Check ($null -ne $w9 -and (St $w9) -eq "unknown") "an empty wait is unknown, not a known empty text"
# Review of PR #24: 301's status 'thinking' is not one Horde knows, so it cannot say the session is
# not waiting; the first reader called its wait absent.
$w61 = $a.fields["waitingFor"]
Check ($null -ne $w61 -and (St $w61) -eq "unknown" -and $w61.reason -like "*'thinking'*") "a status Horde does not know leaves the wait unknown"

Write-Host ""
Write-Host "--- a claude listing is complete or it says why not ---" -ForegroundColor Cyan
$gone = Join-Path $work "never-created"
$r13 = Get-HordeIdentity -ClaudeDir $gone -ProjectsDir $pDir -CodexDir $gone -Processes $procs -Now $now
Check ((St $r13.complete.claude) -eq "unknown" -and (St $r13.complete.codex) -eq "unknown" -and $r13.complete.claude.reason -like "*no claude control directory*") "a missing control directory reads as unknown, not empty"
Check ((St $r13.orphanProcesses) -eq "unknown" -and (St $r13.verifiedLive) -eq "unknown") "with no listing, no process is called an orphan and no session live"
$r13b = Get-HordeIdentity -ClaudeDir $empty -ProjectsDir $pDir -CodexDir $empty -Processes (Table @()) -Now $now
Check ((St $r13b.complete.claude) -eq "known" -and $r13b.records.Count -eq 0) "CONTROL: an empty directory that exists is a complete, empty listing"

$d14 = NewDir "claude"
PutJson (Join-Path $d14 "401.json") (ClaudeRec 401 (Sid 71) (Created 0))
PutText (Join-Path $d14 "402.json") '{"pid":402,"sessionId":"aaaa'
$r14 = Get-HordeIdentity -ClaudeDir $d14 -ProjectsDir $pDir -CodexDir $empty -Processes (Table @(@(401, "claude.exe", (Created 0)), @(402, "claude.exe", (Created 0)))) -Now $now
Check ((St $r14.complete.claude) -eq "unknown" -and $r14.complete.claude.reason -like "*402.json*" -and $r14.records.Count -eq 1) "an unparseable control file makes the listing incomplete"
Check ((St $r14.orphanProcesses) -eq "unknown") "an incomplete listing calls no process an orphan"

$d15 = NewDir "claude"
PutJson (Join-Path $d15 "501.json") (ClaudeRec 502 (Sid 81) (Created 0))
PutJson (Join-Path $d15 "503.json") (ClaudeRec 503 "../../escape" (Created 0))
PutJson (Join-Path $d15 "504.json") (ClaudeRec 504 (Sid 84) (Created 0) -Drop @("sessionId"))
PutJson (Join-Path $d15 "notes.json") (ClaudeRec 505 (Sid 85) (Created 0))
$r15 = Get-HordeIdentity -ClaudeDir $d15 -ProjectsDir $pDir -CodexDir $empty -Processes (Table @()) -Now $now
Check (-not $r15.records.ContainsKey((Sid 81)) -and $r15.complete.claude.reason -like "*501.json*") "a control file whose name disagrees with its pid is refused"
Check ($r15.records.Count -eq 0 -and $r15.complete.claude.reason -like "*503.json*") "a malformed session id is refused as a key"
Check ($r15.complete.claude.reason -like "*504.json*" -and $r15.complete.claude.reason -like "*notes.json*") "a control file with no session id, or not named by a pid, is refused"

# L-020: two files naming one session. Neither is chosen; both are reported, and the listing is not
# complete, because it omits that session.
$d16 = NewDir "claude"
PutJson (Join-Path $d16 "601.json") (ClaudeRec 601 (Sid 91) (Created 0))
PutJson (Join-Path $d16 "602.json") (ClaudeRec 602 (Sid 91) (Created 5))
PutJson (Join-Path $d16 "603.json") (ClaudeRec 603 (Sid 93) (Created 5))
$r16 = Get-HordeIdentity -ClaudeDir $d16 -ProjectsDir $pDir -CodexDir $empty -Processes (Table @(@(601, "claude.exe", (Created 0)), @(602, "claude.exe", (Created 5)), @(603, "claude.exe", (Created 5)))) -Now $now
$dup = @($r16.duplicates | Where-Object { $_.sessionId -eq (Sid 91) })
Check ($dup.Count -eq 1 -and @($dup[0].sources).Count -eq 2 -and -not $r16.records.ContainsKey((Sid 91))) "two live control files naming one session are reported as a duplicate"
Check ((St $r16.complete.claude) -eq "unknown" -and $r16.complete.claude.reason -like ("*" + (Sid 91) + "*") -and $r16.records.ContainsKey((Sid 93))) "a duplicated session leaves the listing incomplete, never silently shorter"
Check (@(Val $r16.verifiedLive) -notcontains (Sid 91)) "a duplicated session is not in the live set"
# A LEFTOVER IS NOT A TIE. A session resumed after a crash leaves the dead process's file beside the
# live one; treating the pair as a duplicate made the whole listing incomplete and dropped the one
# session that is certainly running (review finding 1 of PR #19). When exactly one file is verified
# and every other is proven stale - its process gone, or its pid reused - the verified file is kept
# and the rest are findings. Only a real tie stays a duplicate: two verified, or one not checkable.
$d16b = NewDir "claude"
PutJson (Join-Path $d16b "611.json") (ClaudeRec 611 (Sid 94) (Created 0))
PutJson (Join-Path $d16b "612.json") (ClaudeRec 612 (Sid 94) (Created 5))
PutJson (Join-Path $d16b "613.json") (ClaudeRec 613 (Sid 94) (Created 60))
$r16b = Get-HordeIdentity -ClaudeDir $d16b -ProjectsDir $pDir -CodexDir $empty -Processes (Table @(@(612, "claude.exe", (Created 500)), @(613, "claude.exe", (Created 60)))) -Now $now
$d16c = NewDir "claude"
PutJson (Join-Path $d16c "614.json") (ClaudeRec 614 (Sid 95) (Created 0) -Drop @("procStart"))
PutJson (Join-Path $d16c "615.json") (ClaudeRec 615 (Sid 95) (Created 70))
$r16c = Get-HordeIdentity -ClaudeDir $d16c -ProjectsDir $pDir -CodexDir $empty -Processes (Table @(@(614, "claude.exe", (Created 0)), @(615, "claude.exe", (Created 70)))) -Now $now
$kept94 = $null; if ($r16b.records.ContainsKey((Sid 94))) { $kept94 = $r16b.records[(Sid 94)] }
Check ($null -ne $kept94 -and $kept94.source -like "*613.json" -and @(Val $r16b.verifiedLive) -contains (Sid 94) -and @($r16b.duplicates).Count -eq 0 -and (St $r16b.complete.claude) -eq "known") "a leftover file for a dead process does not hide the live session it names"
Check (@($r16b.findings | Where-Object { $_ -like ("*611.json*" + (Sid 94) + "*") }).Count -eq 1 -and @($r16b.findings | Where-Object { $_ -like ("*612.json*" + (Sid 94) + "*") }).Count -eq 1) "each leftover beside the live file is reported as a finding"
Check (@($r16c.duplicates | Where-Object { $_.sessionId -eq (Sid 95) }).Count -eq 1 -and -not $r16c.records.ContainsKey((Sid 95)) -and (St $r16c.complete.claude) -eq "unknown") "a leftover that cannot be checked beside a live file is still a duplicate"
# T-0116: complete is unchanged by a duplicate (every other reader leans on it), and a NEW member says an agent is short ONLY
# because of named duplicates - the one fact the restore source needs to go on counting the rest.
Check ($r16.wholeButDuplicates["claude"] -eq $true -and (St $r16.complete.claude) -eq "unknown") "an agent short only by a duplicate: complete still says unknown, and wholeButDuplicates says true"
Check ($r16.wholeButDuplicates["codex"] -eq $false) "an agent with no duplicate (codex) is false there: only a duplicate makes it true"
$rNoCodex = Get-HordeIdentity -ClaudeDir $d16b -ProjectsDir $pDir -CodexDir (Join-Path $empty "no-such-control-folder") -Processes (Table @(@(612, "claude.exe", (Created 500)), @(613, "claude.exe", (Created 60)))) -Now $now
Check ($rNoCodex.wholeButDuplicates["codex"] -eq $false) "codex with no control folder is false there (its complete is untouched)"
Check ($r16b.wholeButDuplicates["claude"] -eq $false -and (St $r16b.complete.claude) -eq "known") "a whole listing with no duplicate is not 'whole but for duplicates'"
Check (@($dup[0].agents) -contains "claude") "each duplicate names the agents whose files it came from"
$d16d = NewDir "claude"
PutJson (Join-Path $d16d "621.json") (ClaudeRec 621 (Sid 96) (Created 0))
PutJson (Join-Path $d16d "622.json") (ClaudeRec 622 (Sid 96) (Created 5))
[System.IO.File]::WriteAllText((Join-Path $d16d "623.json"), "{ not json")
$r16d = Get-HordeIdentity -ClaudeDir $d16d -ProjectsDir $pDir -CodexDir $empty -Processes (Table @(@(621, "claude.exe", (Created 0)), @(622, "claude.exe", (Created 5)))) -Now $now
Check (@($r16d.duplicates | Where-Object { $_.sessionId -eq (Sid 96) }).Count -eq 1 -and (St $r16d.complete.claude) -eq "unknown" -and $r16d.wholeButDuplicates["claude"] -eq $false) "a duplicate beside another fault (an unreadable file) is false: the other fault still blinds"
$r16e = Get-HordeIdentity -ClaudeDir $d16c -ProjectsDir $pDir -CodexDir $empty -Processes (Table @(@(614, "claude.exe", (Created 0)), @(615, "claude.exe", (Created 70)))) -Now $now
Check ($r16e.wholeButDuplicates["claude"] -eq $true) "a tie with a file that cannot be checked is a duplicate, named, and the listing is short only by it"

# T-0116 round 2: a duplicate whose files are ALL proven stale is flagged allStale; a real tie is not.
$d16f = NewDir "claude"
PutJson (Join-Path $d16f "631.json") (ClaudeRec 631 (Sid 97) (Created 0))
PutJson (Join-Path $d16f "632.json") (ClaudeRec 632 (Sid 97) (Created 5))
PutJson (Join-Path $d16f "633.json") (ClaudeRec 633 (Sid 98) (Created 5))
$r16f = Get-HordeIdentity -ClaudeDir $d16f -ProjectsDir $pDir -CodexDir $empty -Processes (Table @(@(633, "claude.exe", (Created 5)))) -Now $now
$ghostDup = @($r16f.duplicates | Where-Object { $_.sessionId -eq (Sid 97) })
Check ($ghostDup.Count -eq 1 -and $ghostDup[0].allStale -eq $true -and (St $r16f.complete.claude) -eq "unknown" -and $r16f.wholeButDuplicates["claude"] -eq $true) "two files for one id whose processes are both gone: still a duplicate and complete unchanged, but flagged allStale"
Check ($dup[0].allStale -eq $false -and @($r16c.duplicates)[0].allStale -eq $false) "two verified files, or a file that cannot be checked beside a live one, are not allStale: a real tie stays one"
$d16g = NewDir "claude"
PutJson (Join-Path $d16g "641.json") (ClaudeRec 641 (Sid 99) (Created 0))
PutJson (Join-Path $d16g "642.json") (ClaudeRec 642 (Sid 99) (Created 5) -Drop @("procStart"))
$r16g = Get-HordeIdentity -ClaudeDir $d16g -ProjectsDir $pDir -CodexDir $empty -Processes (Table @(@(641, "claude.exe", (Created 500)), @(642, "claude.exe", (Created 5)))) -Now $now
$halfDup = @($r16g.duplicates | Where-Object { $_.sessionId -eq (Sid 99) })
Check ($halfDup.Count -eq 1 -and $halfDup[0].allStale -eq $false) "one file proven gone beside one that cannot be checked is not allStale: never chosen, and still counted"

# A FILE REMOVED BETWEEN THE LISTING AND THE READ. Claude removes a session's file when it exits, so
# on a live machine a file can be listed and gone a moment later. That is the session exiting during
# the read - a finding - not an unreadable file that makes the listing incomplete (review finding 5 of
# PR #19). The listing is injected: the real one, with 702.json deleted right after it is taken.
$d17 = NewDir "claude"
PutJson (Join-Path $d17 "701.json") (ClaudeRec 701 (Sid 101) (Created 0))
PutJson (Join-Path $d17 "702.json") (ClaudeRec 702 (Sid 102) (Created 0))
$realListing = ${function:Get-HordeControlFiles}
function Get-HordeControlFiles {
    param([string]$Dir, [string]$Agent, $Gaps)
    $listed = @(& $realListing -Dir $Dir -Agent $Agent -Gaps $Gaps)
    foreach ($lf in $listed) { if ($lf.FullName -like "*horde-identity-*" -and $lf.Name -ceq "702.json") { Remove-Item -LiteralPath $lf.FullName -Force } }
    return $listed
}
$r17 = $null
try { $r17 = Get-HordeIdentity -ClaudeDir $d17 -ProjectsDir $pDir -CodexDir $empty -Processes (Table @(@(701, "claude.exe", (Created 0)), @(702, "claude.exe", (Created 0)))) -Now $now }
finally { ${function:Get-HordeControlFiles} = $realListing }
Check ($null -ne $r17 -and -not (Test-Path -LiteralPath (Join-Path $d17 "702.json")) -and $r17.records.ContainsKey((Sid 101))) "CONTROL: the injected listing named a file that was gone by the read"
Check ((St $r17.complete.claude) -eq "known" -and @($r17.findings | Where-Object { $_ -like "702.json:*exited during the read*" }).Count -eq 1) "a control file removed between listing and read is a finding, not a gap"
Check ((St $r17.orphanProcesses) -eq "known" -and @(Val $r17.orphanProcesses) -notcontains 702) "a process whose file vanished during the read is not called an orphan"

Write-Host ""
Write-Host "--- codex ---" -ForegroundColor Cyan
function CodexRec {
    # The shape lib/CodexStatus.ps1 writes (census: no file on disk to copy, so from the writer).
    param([string]$SessionId, [string]$Status, [datetime]$At, [hashtable]$Set = @{}, [string[]]$Drop = @())
    $ms = EpochMs $At
    $o = [ordered]@{ agent = "codex"; sessionId = $SessionId; status = $Status; statusUpdatedAt = $ms; updatedAt = $ms; lastEvent = "Stop"
                     cwd = "C:\work\codex"; transcriptPath = "C:\work\codex-transcript.jsonl"; pane = "7"; runDir = "C:\work\run"
                     orchestratorPane = "3"; wezfleetSessionId = "fleet-1" }
    foreach ($k in $Set.Keys) { $o[$k] = $Set[$k] }
    foreach ($k in $Drop) { $o.Remove($k) }
    return $o
}
$x = NewDir "codex"
PutJson (Join-Path $x "c-idle.json") (CodexRec "c-idle" "idle" $now.AddSeconds(-60))
PutJson (Join-Path $x "c-stale.json") (CodexRec "c-stale" "idle" $now.AddSeconds(-2000))
PutJson (Join-Path $x "c-ended.json") (CodexRec "c-ended" "ended" $now.AddDays(-30))
PutJson (Join-Path $x "c-says-unknown.json") (CodexRec "c-says-unknown" "unknown" $now.AddSeconds(-10))
PutJson (Join-Path $x "c-no-time.json") (CodexRec "c-no-time" "busy" $now -Drop @("statusUpdatedAt"))
$rx = Get-HordeIdentity -ClaudeDir $empty -ProjectsDir $pDir -CodexDir $x -Processes (Table @()) -TtlSeconds 900 -Now $now
$ci = $rx.records["c-idle"]
Check ((St $rx.complete.codex) -eq "known" -and $rx.records.Count -eq 5) ("CONTROL: the codex directory was read (" + $rx.records.Count + " records)")
Check ((Val $ci.fields.liveStatus) -eq "idle" -and (Val $ci.fields.agent) -eq "codex") "CONTROL: a fresh codex idle reading is known"
Check ((St $rx.records["c-stale"].fields.liveStatus) -eq "unknown" -and $rx.records["c-stale"].fields.liveStatus.reason -like "*stale*") "a stale codex idle reading is unknown"
Check ((Val $rx.records["c-ended"].fields.liveStatus) -eq "ended") "a codex ended reading never expires"
Check ((St $rx.records["c-says-unknown"].fields.liveStatus) -eq "unknown" -and (St $rx.records["c-no-time"].fields.liveStatus) -eq "unknown") "a codex status of unknown, or with no time, reads as unknown"
Check ((St $ci.fields.pid) -eq "unknown" -and $ci.fields.pid.reason -like "*codex writes no*" -and (St $ci.fields.messagingAddress) -eq "unknown") "a codex record has an unknown pid, never an invented one"
Check (@($ci.fields.Keys | Where-Object { @("pane", "runDir", "orchestratorPane", "wezfleetSessionId", "fleetSessionId") -contains $_ }).Count -eq 0 -and @($ci.fields.Keys).Count -eq $agentOwned.Count) "a codex pane in the control file is not carried into the record"
Check ((Val $ci.fields.cwd) -eq "C:\work\codex" -and (Val $ci.fields.transcriptPath) -eq "C:\work\codex-transcript.jsonl" -and "$($ci.provisional['transcriptPath'])" -ne "") "a codex transcript is taken from its file and marked provisional"
Check (@(Val $rx.verifiedLive).Count -eq 0) "a codex session, which writes no pid, is never in the verified live set"

$x2 = NewDir "codex"
PutJson (Join-Path $x2 "c-ok.json") (CodexRec "c-ok" "busy" $now)
PutText (Join-Path $x2 "c-half.json") '{"agent":"codex","sessionId":"c-ha'
$rx2 = Get-HordeIdentity -ClaudeDir $empty -ProjectsDir $pDir -CodexDir $x2 -Processes (Table @()) -TtlSeconds 900 -Now $now
Check ((St $rx2.complete.codex) -eq "unknown" -and $rx2.complete.codex.reason -like "*c-half.json*" -and $rx2.records.Count -eq 1) "a half-written codex file reads as unknown, not absent"
$x3 = NewDir "codex"
PutJson (Join-Path $x3 "c-name.json") (CodexRec "c-other" "busy" $now)
PutJson (Join-Path $x3 "c-agent.json") (CodexRec "c-agent" "busy" $now -Set @{ agent = "claude" })
$rx3 = Get-HordeIdentity -ClaudeDir $empty -ProjectsDir $pDir -CodexDir $x3 -Processes (Table @()) -TtlSeconds 900 -Now $now
Check ($rx3.records.Count -eq 0 -and $rx3.complete.codex.reason -like "*c-name.json*" -and $rx3.complete.codex.reason -like "*c-agent.json*") "a codex file whose name or agent disagrees with its content is refused"

# L-014: wezfleet ignores a TTL override that is not a positive integer (lib/CodexStatus.ps1:79-83).
Check ((Get-HordeCodexTtlSeconds -Value "") -eq 900 -and (Get-HordeCodexTtlSeconds -Value "0") -eq 900 -and (Get-HordeCodexTtlSeconds -Value "-5") -eq 900 -and (Get-HordeCodexTtlSeconds -Value "ten") -eq 900 -and (Get-HordeCodexTtlSeconds -Value "1.5") -eq 900) "a bad codex TTL override falls back to the default"
Check ((Get-HordeCodexTtlSeconds -Value "30") -eq 30) "CONTROL: a good codex TTL override is honoured"
$rx4 = Get-HordeIdentity -ClaudeDir $empty -ProjectsDir $pDir -CodexDir $x -Processes (Table @()) -TtlSeconds 30 -Now $now
Check ((St $rx4.records["c-idle"].fields.liveStatus) -eq "unknown") "the TTL passed in is the one applied"
# wezfleet parses the override with [int]::TryParse's default style, which allows a sign and white
# space around the digits; Horde refused both and so fell back where wezfleet honoured (review
# finding 4 of PR #19).
Check ((Get-HordeCodexTtlSeconds -Value "+60") -eq 60 -and (Get-HordeCodexTtlSeconds -Value " 60") -eq 60 -and (Get-HordeCodexTtlSeconds -Value "60 ") -eq 60) "a codex TTL override is parsed as wezfleet parses it"
# A TTL PASSED IN goes through the same fallback, so a bad one cannot make Limit-HordeAge throw for
# the whole read: -TtlSeconds 0 did.
$rx4b = $null; $ttlThrew = $null
try { $rx4b = Get-HordeIdentity -ClaudeDir $empty -ProjectsDir $pDir -CodexDir $x -Processes (Table @()) -TtlSeconds 0 -Now $now } catch { $ttlThrew = $_.Exception.Message }
if ($null -ne $ttlThrew) { Write-Host ("  the read threw: " + $ttlThrew) -ForegroundColor Red }
Check ($null -eq $ttlThrew -and $null -ne $rx4b -and (Val $rx4b.records["c-idle"].fields.liveStatus) -eq "idle") "a bad TTL passed in falls back to the default instead of failing the read"

# A session id is unique across agents too: the same id under both is a duplicate, not two sessions.
$x5 = NewDir "codex"
PutJson (Join-Path $x5 ((Sid 1) + ".json")) (CodexRec (Sid 1) "busy" $now)
$rx5 = Get-HordeIdentity -ClaudeDir $cDir -ProjectsDir $pDir -CodexDir $x5 -Processes $procs -TtlSeconds 900 -Now $now
Check (@($rx5.duplicates | Where-Object { $_.sessionId -eq (Sid 1) }).Count -eq 1 -and -not $rx5.records.ContainsKey((Sid 1)) -and (St $rx5.complete.claude) -eq "unknown" -and (St $rx5.complete.codex) -eq "unknown") "one session id under two agents is a duplicate"

Write-Host ""
Write-Host "--- keys and names ---" -ForegroundColor Cyan
Check ((ConvertTo-HordeClaudeProjectKey -Cwd "C:\Code\Dist Folders\Dist_12_23_25_ai-latency.v2") -ceq "C--Code-Dist-Folders-Dist-12-23-25-ai-latency-v2") "a cwd with spaces and underscores maps to dashes"
Check ((ConvertTo-HordeClaudeProjectKey -Cwd "C:\Users\x\Code") -ceq "C--Users-x-Code") "CONTROL: a plain cwd maps as wezfleet's colon-and-slash rule would"
Check ((Test-HordeSessionId -Id (Sid 1)) -and -not (Test-HordeSessionId -Id "a/b") -and -not (Test-HordeSessionId -Id "") -and -not (Test-HordeSessionId -Id ("x" * 129))) "a session id is validated before it becomes a key"
# L-026: every key a fixture control file carries - the census's 19 plus formerNames, and waitingFor,
# which only a waiting session writes (core-identity L-054) - has a row.
# The 11 more are the keys the Claude Code 2.1.285 reader accepts that no file here has carried,
# dropped provisionally in the table (core-ownership L-056).
# asksForConvertedSkills first appeared in 2.1.318 and is dropped the same way (T-0430).
$keys = @((ClaudeRec 1 (Sid 1) (Created 0)).Keys) + @("formerNames", "waitingFor") + @("jobId", "parkedJobId", "spare", "logPath", "hostSessionId", "agent", "state", "detail", "tempo", "needs", "tmux") + @("asksForConvertedSkills")
$x2Known = @(Get-HordeOwnershipStoreKeys -Doc $ownership -Store "X2")
$noRow = @($keys | Where-Object { $x2Known -cnotcontains $_ })
foreach ($n in $noRow) { Write-Host ("  control file key with no row: " + $n) -ForegroundColor Red }
Check ($keys.Count -eq 33 -and $noRow.Count -eq 0) "every control file key is kept or dropped"

Write-Host ""
Write-Host "--- self identity ---" -ForegroundColor Cyan
$self = Get-HordeSelfSessionId -Environment @{ CLAUDE_CODE_SESSION_ID = (Sid 1); WEZFLEET_SESSION_ID = "fleet-9"; WEZTERM_PANE = "4" }
Check ((Val $self) -eq (Sid 1)) "self identity takes the agent's own session variable first"
$fleetOnly = Get-HordeSelfSessionId -Environment @{ WEZFLEET_SESSION_ID = "fleet-9" }
Check ((St $fleetOnly) -eq "unknown") "a fleet id is never returned as a session id"
$paneOnly = Get-HordeSelfSessionId -Environment @{ WEZTERM_PANE = "4" }
Check ((St $paneOnly) -eq "unknown" -and $paneOnly.reason -like "*CLAUDE_CODE_SESSION_ID*") "self identity reads no pane record at all"
Check ((St (Get-HordeSelfSessionId -Environment @{ CLAUDE_CODE_SESSION_ID = "../x" })) -eq "unknown") "a malformed self id is unknown, not trusted"

# L-023: the variable is inherited, so it must not change what the readers say about anyone else.
$keepA = $env:CLAUDE_CODE_SESSION_ID; $keepB = $env:WEZFLEET_SESSION_ID
try {
    $env:CLAUDE_CODE_SESSION_ID = (Sid 777); $env:WEZFLEET_SESSION_ID = (Sid 778)
    $withEnv = Get-HordeIdentity -ClaudeDir $cDir -ProjectsDir $pDir -CodexDir $empty -Processes $procs -Now $now
} finally { $env:CLAUDE_CODE_SESSION_ID = $keepA; $env:WEZFLEET_SESSION_ID = $keepB }
$sameKeys = ((@($withEnv.records.Keys | Sort-Object) -join ",") -eq (@($id.records.Keys | Sort-Object) -join ","))
Check ($sameKeys -and -not $withEnv.records.ContainsKey((Sid 777)) -and -not $withEnv.records.ContainsKey((Sid 778))) "another session's identity never reads the environment"

Write-Host ""
Write-Host "--- reading never writes, and never blocks the writer ---" -ForegroundColor Cyan
function Get-TreeFingerprint { param([string]$Dir)
    return @(Get-ChildItem -LiteralPath $Dir -Recurse -Force | Sort-Object FullName | ForEach-Object {
        if ($_.PSIsContainer) { "D " + $_.FullName.Substring($Dir.Length) }
        else { "F " + $_.FullName.Substring($Dir.Length) + " " + $_.Length + " " + $_.LastWriteTimeUtc.Ticks + " " + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    }) -join "`n" }
$before = Get-TreeFingerprint -Dir $work
# Every file held open against writing and deleting for the whole read: a reader that opened any of
# them for writing would fail, and one that wrote a new file would show in the fingerprint.
$holds = @(Get-ChildItem -LiteralPath $work -Recurse -File | ForEach-Object { [System.IO.File]::Open($_.FullName, "Open", "Read", "Read") })
$nw = $null; $nwThrew = $null
try { $nw = Get-HordeIdentity -ClaudeDir $cDir -ProjectsDir $pDir -CodexDir $x -Processes $procs -TtlSeconds 900 -Now $now } catch { $nwThrew = $_.Exception.Message }
finally { $holds | ForEach-Object { $_.Dispose() } }
$after = Get-TreeFingerprint -Dir $work
Check ($null -eq $nwThrew -and $null -ne $nw -and (St $nw.complete.claude) -eq "known" -and (St $nw.complete.codex) -eq "known") "identity opens no control file for writing"
Check ($before -eq $after) "reading leaves no new file in any control directory"
PutText (Join-Path $cDir "101.json.lock") "x"
Check ((Get-TreeFingerprint -Dir $work) -ne $before) "CONTROL: a reader that leaves a lock file behind is caught by the same comparison"
Remove-Item -LiteralPath (Join-Path $cDir "101.json.lock") -Force

# L-019: a writer holding its file open for writing does not stop the read, because every control
# file goes through the shared reader; the ordinary read share would fail against the same hold.
$wHolds = @(Get-ChildItem -LiteralPath $cDir -File -Filter "*.json" | ForEach-Object { [System.IO.File]::Open($_.FullName, "Open", "ReadWrite", ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)) })
$plainFailed = $false
$wr = $null
try {
    try { $null = [System.IO.File]::ReadAllText((Join-Path $cDir "101.json")) } catch { $plainFailed = $true }
    $wr = Get-HordeIdentity -ClaudeDir $cDir -ProjectsDir $pDir -CodexDir $empty -Processes $procs -Now $now
} finally { $wHolds | ForEach-Object { $_.Dispose() } }
Check ($plainFailed) "CONTROL: an ordinary read fails while the writer holds its file"
Check ((St $wr.complete.claude) -eq "known" -and $wr.records.Count -eq 3) "every control file is read through the shared reader"

foreach ($n in $script:trips) { Write-Host ("  tripped: " + $n) -ForegroundColor Red }
Check ($script:trips.Count -eq 0) "the suite reads no real control directory or process table"

} finally {
    if ((Split-Path -Leaf $work) -match '^horde-identity-[0-9a-f]{32}$' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host "--- reality check: this machine's own control files, read only ---" -ForegroundColor Cyan
# The real functions go back in, and only here. This section opens every <pid>.json in the real
# directory through the shared reader, never a key file, and asks the process table read-only.
${function:Get-HordeProcessTable} = $realProcessTable
${function:Get-HordeClaudeSessionsDir} = $realClaudeDir
${function:Get-HordeClaudeProjectsDir} = $realProjectsDir
${function:Get-HordeCodexSessionsDir} = $realCodexDir
$realDir = Get-HordeClaudeSessionsDir
if (-not (Test-Path -LiteralPath $realDir -PathType Container)) {
    Write-Host ("  [SKIP] no claude control directory on this machine, so there is nothing real to check") -ForegroundColor Yellow
} else {
    $realFiles = @(Get-ChildItem -LiteralPath $realDir -File | Where-Object { $_.Extension -eq ".json" })
    $realTable = Get-HordeProcessTable
    Check ((St $realTable) -eq "known") ("the real process table is read (" + $(if ((St $realTable) -eq "known") { "" + @((Val $realTable).Keys).Count + " processes" } else { $realTable.reason }) + ")")
    # A session can exit between the listing and the read, and its file goes with it. That is the
    # machine changing, not a reader failure, so one more read is taken before calling it a failure.
    $real = Read-HordeClaudeControlFiles -Dir $realDir -Processes $realTable -ProjectsDir (Get-HordeClaudeProjectsDir)
    if ((St $real.complete) -ne "known") {
        Write-Host ("  first read incomplete (" + $real.complete.reason + "); reading once more") -ForegroundColor Yellow
        $real = Read-HordeClaudeControlFiles -Dir $realDir -Processes $realTable -ProjectsDir (Get-HordeClaudeProjectsDir)
    }
    $recs = @($real.entries)
    $verified = @($real.verified)
    $reused = @($recs | Where-Object { (St $_.fields.liveStatus) -eq "unknown" -and $_.fields.liveStatus.reason -like "*reused*" })
    $stale = @($recs | Where-Object { (St $_.fields.liveStatus) -eq "unknown" -and $_.fields.liveStatus.reason -like "*not running*" })
    $orphText = "orphans unknown: " + $real.orphans.reason
    if ((St $real.orphans) -eq "known") { $orphText = "" + @(Val $real.orphans).Count + " claude processes no file verifies" }
    Write-Host ("  " + $realFiles.Count + " control files, " + $recs.Count + " records, " + $verified.Count + " verified live, " + $stale.Count + " stale, " + $reused.Count + " pid reused; " + $orphText) -ForegroundColor DarkGray
    Check ((St $real.complete) -eq "known" -and $recs.Count -eq $realFiles.Count) ("every real control file is read without error (" + $recs.Count + " of " + $realFiles.Count + $(if ((St $real.complete) -ne "known") { "; " + $real.complete.reason } else { "" }) + ")")
    # A REUSED PID ON THIS MACHINE IS A FACT ABOUT THE MACHINE, not a failure of the code: a crashed
    # session's file can outlive its process while Windows hands the pid on. It is reported, and the
    # suite stays green (review finding 6 of PR #19); the fixtures above prove the reuse rule.
    foreach ($ru in $reused) { Write-Host ("  REPORT: a real control file's pid now belongs to another process: " + $ru.source) -ForegroundColor Yellow }
    if ($realFiles.Count -gt 0) {
        Check ($verified.Count -ge 1) ("CONTROL: at least one real control file names its running process (" + $verified.Count + ")")
    }
    $realKeys = @()
    $realVersions = @()
    $keyFiles = 0
    foreach ($f in $realFiles) {
        try {
            $o = (Read-HordeSharedText -Path $f.FullName) | ConvertFrom-Json
            $realKeys += @($o.PSObject.Properties | ForEach-Object { $_.Name })
            $vp = $o.PSObject.Properties["version"]
            if ($null -ne $vp) { $realVersions += "$($vp.Value)" }
            $keyFiles++
        } catch { Write-Host ("  keys not read from " + $f.Name + ": " + $_.Exception.Message) -ForegroundColor Yellow }
    }
    # The key check below passes vacuously on no keys, and the read above swallows each file's error,
    # so it must be shown to have read something whenever there were files to read (review finding 6
    # of PR #19).
    Check ($realFiles.Count -eq 0 -or ($keyFiles -ge 1 -and @($realKeys).Count -ge 1)) ("CONTROL: the keys of the real control files were read (" + $keyFiles + " of " + $realFiles.Count + " files, " + @($realKeys | Sort-Object -Unique).Count + " distinct keys)")
    # DRIFT FAILS, AND WAITING DOES NOT (core-identity L-056). The table keeps or drops every key seen
    # on disk and the 11 more the 2.1.285 reader accepts, so a session that happens to be waiting, or in
    # any state that version knows, cannot turn this red. What does: a key in neither list, which a newer
    # or unsurveyed writer added. A newer version alone is said, not failed (T-0430): Claude Code updates
    # itself most days, so a check on the number stayed red from 10-26 on and stopped being read, while
    # the key check is what finds a change this table must answer. A version that cannot be read fails.
    $realNoRow = @($realKeys | Sort-Object -Unique | Where-Object { $x2Known -cnotcontains $_ })
    Check ($realNoRow.Count -eq 0) ("every key in this machine's control files is kept or dropped in the ownership table (" + ($realNoRow -join ", ") + ")")
    $surveyed = Get-HordeOwnershipSurveyedVersion -Doc $ownership -Store "X2"
    $unreadable = @($realVersions | Sort-Object -Unique | Where-Object { $pv = $null; -not [version]::TryParse("$_", [ref]$pv) })
    $newer = @($realVersions | Sort-Object -Unique | Where-Object { $pv = $null; [version]::TryParse("$_", [ref]$pv) -and $null -ne $surveyed -and $pv -gt $surveyed })
    if ($newer.Count -gt 0) { Write-Host ("  control files newer than the table's survey (surveyed " + $surveyed + "): " + ($newer -join ", ")) -ForegroundColor DarkGray }
    Check ($null -ne $surveyed -and ($realFiles.Count -eq 0 -or $realVersions.Count -ge 1) -and $unreadable.Count -eq 0) ("every control file on this machine names a Claude Code version the table's survey can be compared with (surveyed " + $surveyed + "; unreadable: " + ($unreadable -join ", ") + ")")
}

Complete-HordeSuite -Success "every agent's control files read into one record shape, and nothing written"
