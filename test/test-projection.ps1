# DOES CORE/PROJECTION GIVE ONE CORRECT, READ-ONLY VIEW OF THE HORDE?
#
# Every lesson here is cited in planning/ledger/core-projection.md. The fixture sections read only a
# copy of test/fixtures/projection/fleet made in TEMP, with an injected process table, a fake host
# port and a fake layout port; the functions that would read the real machine are replaced by trip
# wires until the last section, a read-only reality check over this machine's own stores with the
# host unavailable.
#
# THE FIXTURE, in short (ids aaaaaaaa-0000-4000-8000-0000000000NN). Every value is synthetic, and
# write times the view depends on are in times.json, because git does not keep them:
#   01 warchief, handle 10    02 orc under 01, handle 11    03 goblin in run alpha, handle 12
#   04 stopped, handle 13 gone  05 retired, handle 14         06 running, record retired
#   07 08 09 all claim handle 16 (08 is shaped like the stray 11111111-... record)
#   10 no record, pane-sessions file 17 and a claim for 17    11 holds 18; 12's file hijacks 18
#   13 named by files 19 and 20   codex-thread-1 a codex session with a non-UUID id
#   15 fleet id in two open runs  16 in two closed runs  17 pending  18 orphaned  19 gone but active
#   20 done  21 parent missing  22 parent retired  23 24 label held twice  25 orc under 03
#   26 27 one fleet id  28 29 a parent loop  30 another instance  31 written before the instance
#   32 resumed by two processes  33 resumed by one  34 known only from a report

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\Projection.ps1")
Set-StrictMode -Version Latest

# TRIP WIRES (ledger L-051). Until the reality check nothing may read the real stores. Each default
# a reader would fall back to is replaced here, after loading, so a reader that ignores an injected
# source trips one and is counted. A trip records and answers harmlessly, never throws, so the check
# that counts trips still runs (core-identity's lesson, 2026-09-30).
$script:trips = New-Object System.Collections.ArrayList
$real = @{}
foreach ($fn in @("Get-HordeProcessTable", "Get-HordeProjectionProcessTable", "Get-HordeClaudeSessionsDir", "Get-HordeClaudeProjectsDir",
                  "Get-HordeCodexSessionsDir", "Get-HordePaneSessionsDir", "Get-HordeWezfleetRoot")) { $real[$fn] = (Get-Item ("function:" + $fn)).ScriptBlock }
function Get-HordeProcessTable { [void]$script:trips.Add("process table"); return (New-HordeUnknown -Reason "TRIP: the real process table was asked for") }
function Get-HordeProjectionProcessTable { [void]$script:trips.Add("process table with command lines"); return (New-HordeUnknown -Reason "TRIP: the real process table was asked for") }
function Get-HordeClaudeSessionsDir { [void]$script:trips.Add("claude sessions"); return (Join-Path $env:TEMP ("horde-projection-trip-" + [guid]::NewGuid().ToString("N"))) }
function Get-HordeClaudeProjectsDir { [void]$script:trips.Add("claude projects"); return (Join-Path $env:TEMP ("horde-projection-trip-" + [guid]::NewGuid().ToString("N"))) }
function Get-HordeCodexSessionsDir { [void]$script:trips.Add("codex sessions"); return (Join-Path $env:TEMP ("horde-projection-trip-" + [guid]::NewGuid().ToString("N"))) }
function Get-HordePaneSessionsDir { [void]$script:trips.Add("pane-sessions"); return (Join-Path $env:TEMP ("horde-projection-trip-" + [guid]::NewGuid().ToString("N"))) }
function Get-HordeWezfleetRoot { [void]$script:trips.Add("wezfleet root"); return (Join-Path $env:TEMP ("horde-projection-trip-" + [guid]::NewGuid().ToString("N"))) }

$fx = Join-Path $root "test\fixtures\projection\fleet"
$work = Join-Path $env:TEMP ("horde-projection-" + [guid]::NewGuid().ToString("N"))
$script:copies = 0
$timesDoc = (Get-Content -LiteralPath (Join-Path $fx "times.json") -Raw) | ConvertFrom-Json
$now = [datetime]::Parse($timesDoc.now, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
$ownership = (Get-Content -LiteralPath (Join-Path $root "core\ownership.json") -Raw) | ConvertFrom-Json
$viewSchema = Get-HordeSchema -Name "session-view.v1"

function Sid { param([int]$N) return ("aaaaaaaa-0000-4000-8000-" + $N.ToString("000000000000")) }
function Utc { param([string]$Text) return [datetime]::Parse($Text, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime() }
function Encoding { return (New-Object System.Text.UTF8Encoding($false)) }
function PutJson { param([string]$Path, $Obj) [System.IO.File]::WriteAllText($Path, ($Obj | ConvertTo-Json -Depth 12), (Encoding)) }
function PutText { param([string]$Path, [string]$Text) [System.IO.File]::WriteAllText($Path, $Text, (Encoding)) }
function ReadJson { param([string]$Path) return ((Get-Content -LiteralPath $Path -Raw) | ConvertFrom-Json) }

function New-Fleet {
    # A fresh copy of the fixture with its file times set: git does not keep write times, so the
    # ones the view depends on (pane-sessions files, transcripts, command logs) are in times.json,
    # as seconds from the fixture's own "now".
    param([string]$Name)
    $script:copies++
    $d = Join-Path $work ($Name + "-" + $script:copies)
    Copy-Item -LiteralPath $fx -Destination $d -Recurse
    foreach ($p in $timesDoc.offsetsSeconds.PSObject.Properties) { [System.IO.File]::SetLastWriteTimeUtc((Join-Path $d ($p.Name -replace '/', '\')), $now.AddSeconds([int]$p.Value)) }
    return $d
}
function RegPath { param([string]$D, $N) if ($N -is [int]) { $N = Sid $N }; return (Join-Path $D ("wezfleet\registry\sessions\" + $N + ".json")) }
function EditReg { param([string]$D, $N, [scriptblock]$Edit) $p = RegPath $D $N; $r = ReadJson $p; & $Edit $r; PutJson $p $r }

function HostOf {
    # The fake host port, from host.json, with optional overrides.
    param([string]$D, $Running = $null, $Id = $null, [switch]$Ambiguous, [string[]]$Add = @(), [switch]$NoHandles, [hashtable]$Caps = @{})
    $h = ReadJson (Join-Path $D "host.json")
    $rows = @($h.handles | ForEach-Object { [pscustomobject]@{ handle = $_.handle; window = $_.window; tab = $_.tab; hostTitle = $_.hostTitle } })
    foreach ($a in $Add) { $rows += [pscustomobject]@{ handle = $a; window = "1"; tab = "9"; hostTitle = "added" } }
    if ($NoHandles) { $rows = @() }
    $inst = [pscustomobject]@{ id = $h.instance.id; startedAt = (Utc $h.instance.startedAt); running = [int]$h.instance.running; ambiguous = [bool]$h.instance.ambiguous }
    if ($null -ne $Running) { $inst.running = [int]$Running }
    if ($null -ne $Id) { $inst.id = $Id }
    if ($Ambiguous) { $inst.ambiguous = $true }
    $handlesBlock = { return , $rows }.GetNewClosure()
    $instanceBlock = { return $inst }.GetNewClosure()
    # What the fake declares: the two facts the view relies on, and nothing it has not measured.
    $capTable = @{ "list" = "yes"; "instance.startedAt" = "yes"; "text.read" = "unverified" }
    foreach ($k in $Caps.Keys) { $capTable[$k] = $Caps[$k] }
    return (New-HordeHostPort -Name "fake" -Capabilities $capTable -Handles $handlesBlock -Instance $instanceBlock)
}
function ProcsOf {
    param([string]$D)
    $t = @{}
    foreach ($p in @(ReadJson (Join-Path $D "processes.json"))) { $t[[int]$p.pid] = [pscustomobject]@{ pid = [int]$p.pid; name = "$($p.name)"; created = (Utc $p.created); commandLine = $p.commandLine } }
    return (New-HordeKnown -Value $t)
}
function LayoutOf {
    param([string]$D)
    $rows = @(ReadJson (Join-Path $D "layout.json") | ForEach-Object { [pscustomobject]@{ sessionId = $_.sessionId; argv = @($_.argv) } })
    return ({ return , $rows }.GetNewClosure())
}
function Project {
    param([string]$D, $HostPort = $null, $Processes = $null, $Layout = $null)
    if ($null -eq $HostPort) { $HostPort = HostOf $D }
    if ($null -eq $Processes) { $Processes = ProcsOf $D }
    if ($null -eq $Layout) { $Layout = LayoutOf $D }
    return (Get-HordeProjection -WezfleetRoot (Join-Path $D "wezfleet") -ClaudeDir (Join-Path $D "claude\sessions") -ProjectsDir (Join-Path $D "claude\projects") `
        -CodexDir (Join-Path $D "wezfleet\codex-sessions") -PaneSessionsDir (Join-Path $D "claude\pane-sessions") -Processes $Processes -HostPort $HostPort `
        -LayoutPort $Layout -TtlSeconds 900 -Now $now)
}
function Ans { param($P, $Id, [string]$Field) if ($Id -is [int]) { $Id = Sid $Id }; foreach ($s in $P.sessions) { if ($s.sessionId -ieq $Id) { return $s.fields[$Field] } }; return $null }
function Has { param($P, $Id) if ($Id -is [int]) { $Id = Sid $Id }; return (@($P.sessions | Where-Object { $_.sessionId -ieq $Id }).Count -eq 1) }
function St { param($A) if ($null -eq $A) { return "(no session)" }; return "$($A.answer.state)" }
function Val {
    # The value of a view answer, or of a bare answer (the handles list is one).
    param($A)
    if ($null -eq $A) { return $null }
    $x = $A; if ($null -ne $A.PSObject.Properties["answer"]) { $x = $A.answer }
    if ($x.state -ne "known") { return $null }
    return $x.value
}
function Src { param($A) if ($null -eq $A -or $null -eq $A.source) { return "" }; return "$($A.source.store)" }
function Why { param($A) if ($null -eq $A) { return "" }; return "$($A.answer.reason)" }
function Fault { param($P, [string]$Kind) foreach ($f in $P.faults) { if ($f.kind -ceq $Kind) { return $f } }; return $null }
function FSt { param($F) if ($null -eq $F) { return "(no check)" }; if ($F.answer.state -eq "known") { return ("" + $F.answer.value).ToLowerInvariant() }; return "unknown" }
function Subjects { param($F) if ($null -eq $F) { return @() }; return @($F.found | ForEach-Object { @($_.subjects) }) }

try {
New-Item -ItemType Directory -Path $work -Force | Out-Null

Write-Host ""
Write-Host "--- loading the module ---" -ForegroundColor Cyan
$strictKept = & { Set-StrictMode -Version Latest; . (Join-Path $root "core\Projection.ps1"); try { $null = $hordeNeverAssignedVariable; $false } catch { $true } }
Check ($strictKept -eq $true) "dot-sourcing core/projection leaves the caller's strict mode on"

Write-Host ""
Write-Host "--- the view over the fixture ---" -ForegroundColor Cyan
$base = New-Fleet "base"
$p = Project $base
$ids = @($p.sessions | ForEach-Object { $_.sessionId })
Check ($ids.Count -eq 34) ("CONTROL: the fixture's 34 sessions are all in the view (" + $ids.Count + ")")
$required = @($ownership.required | ForEach-Object { "$_" })
$shapeBad = @($p.sessions | Where-Object { (@($_.fields.Keys) -join ",") -cne ($required -join ",") })
Check ($shapeBad.Count -eq 0) "every session carries every required field, in the table's order"
$notAnswers = @($p.sessions | ForEach-Object { $s = $_; @($s.fields.Keys) | Where-Object { -not (Test-HordeAnswer $s.fields[$_].answer) } })
Check ($notAnswers.Count -eq 0) "every field of the view is a horde answer"
$unsourced = @($p.sessions | ForEach-Object { $s = $_; @($s.fields.Keys) | Where-Object { $s.fields[$_].answer.state -eq "known" -and $null -eq $s.fields[$_].source } | ForEach-Object { $s.sessionId + " " + $_ } })
foreach ($u in $unsourced) { Write-Host ("  known with no source: " + $u) -ForegroundColor Red }
Check ($unsourced.Count -eq 0) "every answer names the store it came from"
# A FIELD READS ONLY THE STORES ITS ROW LISTS. The derived transcript path also comes from the
# control file (X2, W8) and the project folders (X3), as the row's derived text says.
$allowed = @{}
foreach ($f in @($ownership.fields)) { $allowed["$($f.name)"] = @($f.read | ForEach-Object { "$($_.store)" }) }
$allowed["transcriptPath"] += @("X2", "W8", "X3")
$offRow = @($p.sessions | ForEach-Object { $s = $_; @($s.fields.Keys) | Where-Object { $null -ne $s.fields[$_].source -and @($allowed[$_]) -notcontains $s.fields[$_].source.store } | ForEach-Object { $s.sessionId + " " + $_ + " from " + $s.fields[$_].source.store } })
foreach ($u in $offRow) { Write-Host ("  read from a store its row does not list: " + $u) -ForegroundColor Red }
Check ($offRow.Count -eq 0) "a field is read only from the stores its ownership row lists"

Write-Host ""
Write-Host "--- precedence, one field at a time (core/ownership.json) ---" -ForegroundColor Cyan
Check ((Src (Ans $p 1 "sessionId")) -eq "X2" -and (Src (Ans $p 4 "sessionId")) -eq "W1" -and (Src (Ans $p 34 "sessionId")) -eq "W5") "session ids come from the control file, then the registry, then a report"
Check ((Val (Ans $p 1 "agent")) -eq "claude" -and (Src (Ans $p 1 "agent")) -eq "X2" -and (Val (Ans $p "codex-thread-1" "agent")) -eq "codex" -and (Src (Ans $p "codex-thread-1" "agent")) -eq "W8") "the agent is the control-file directory the session was found in"
Check ((Val (Ans $p 1 "pid")) -eq 1001 -and (Src (Ans $p 1 "pid")) -eq "X2" -and (Val (Ans $p 33 "pid")) -eq 1102 -and (Src (Ans $p 33 "pid")) -eq "X5") "a pid comes from the control file, then a process whose --resume id matches"
Check ((St (Ans $p 32 "pid")) -eq "unknown" -and (Why (Ans $p 32 "pid")) -like "*2 processes*") "two processes resuming one session leave its pid unknown"
Check ((Val (Ans $p 3 "cwd")) -eq "C:\work\gamma" -and (Src (Ans $p 3 "cwd")) -eq "X2" -and (Val (Ans $p 4 "cwd")) -eq "C:\work\x" -and (Src (Ans $p 4 "cwd")) -eq "W1" -and (Src (Ans $p 34 "cwd")) -eq "W5") "cwd comes from the control file, then the registry, then a report"
Check ((Src (Ans $p 1 "projectCwd")) -eq "X2" -and (Val (Ans $p 4 "projectCwd")) -eq "C:\work\x" -and (Src (Ans $p 4 "projectCwd")) -eq "W1") "the project directory comes from a running control file, then the registry's firstCwd"
Check ((Src (Ans $p 1 "pane")) -eq "W1" -and (Val (Ans $p 1 "pane")) -eq "10" -and (Src (Ans $p 10 "pane")) -eq "X1" -and (Val (Ans $p 10 "pane")) -eq "17") "a pane comes from the registry, then a guarded pane-sessions file"
Check ((Val (Ans $p 1 "window")) -eq "1" -and (Src (Ans $p 1 "window")) -eq "X4" -and (Src (Ans $p 18 "window")) -eq "W3") "a window comes from the live handle, then the run"
Check ((Val (Ans $p 1 "hostInstance")) -eq "inst-1" -and (Src (Ans $p 1 "hostInstance")) -eq "W1" -and (Val (Ans $p 10 "hostInstance")) -eq "inst-1" -and (Src (Ans $p 10 "hostInstance")) -eq "X5") "the host instance comes from the registry, then the one instance running"
Check ((Val (Ans $p 1 "role")) -eq "warchief" -and (Src (Ans $p 1 "role")) -eq "W1" -and (Val (Ans $p 10 "role")) -eq "orc" -and (Src (Ans $p 10 "role")) -eq "W2") "a role comes from the registry, then the session's pending claim"
Check ((Val (Ans $p 2 "label")) -eq "A" -and (Val (Ans $p 10 "label")) -eq "B" -and (Src (Ans $p 10 "label")) -eq "W2" -and (Val (Ans $p 10 "parent")) -eq (Sid 1) -and (Src (Ans $p 10 "parent")) -eq "W2") "label and parent come from the registry, then the claim"
Check ((Val (Ans $p 2 "labelCycle")) -eq 0 -and (Val (Ans $p 1 "labelCycle")) -eq 0 -and (St (Ans $p 4 "labelCycle")) -eq "absent") "a labelled record with no labelCycle reads as cycle 0, as wezfleet reads it"
Check ((Val (Ans $p 1 "name")) -eq "fixture-1" -and (Src (Ans $p 1 "name")) -eq "X2" -and (Val (Ans $p 10 "name")) -eq "delta work" -and (Src (Ans $p 10 "name")) -eq "X1") "a name comes from the control file, then the pane-sessions title"
Check ((Val (Ans $p 3 "fleetSessionId")) -eq "alpha" -and (Src (Ans $p 3 "fleetSessionId")) -eq "W1" -and (Val (Ans $p 34 "fleetSessionId")) -eq "kappa" -and (Src (Ans $p 34 "fleetSessionId")) -eq "W4" -and (Val (Ans $p "codex-thread-1" "fleetSessionId")) -eq "cx" -and (Src (Ans $p "codex-thread-1" "fleetSessionId")) -eq "W8") "a fleet id comes from the registry, then a roster a report links, then a codex file"
Check ((St (Ans $p 1 "fleetSessionId")) -eq "absent" -and (St (Ans $p 1 "runId")) -eq "absent") "an empty fleet id is absent, and so is the run"
Check ((Val (Ans $p 1 "liveStatus")) -eq "idle" -and (Val (Ans $p "codex-thread-1" "liveStatus")) -eq "idle" -and (Src (Ans $p "codex-thread-1" "liveStatus")) -eq "W8" -and (St (Ans $p 4 "liveStatus")) -eq "absent") "live status comes from the agent's own file, and a session with none is not running"
# waitingFor (PR #24): in the view because the table requires it; read from the control file only.
$waits = New-Fleet "waiting"
$w2 = ReadJson (Join-Path $waits "claude\sessions\1002.json"); $w2.status = "waiting"; $w2 | Add-Member -NotePropertyName waitingFor -NotePropertyValue "permission prompt" -Force; PutJson (Join-Path $waits "claude\sessions\1002.json") $w2
$pw2 = Project $waits
$wf2 = Ans $pw2 2 "waitingFor"
Check ((Val $wf2) -eq "permission prompt" -and (Src $wf2) -eq "X2" -and "$($wf2.provisional)" -ne "" -and (Val (Ans $pw2 2 "liveStatus")) -eq "waiting") "a waiting session says what it waits for, from its own control file"
Check ((St (Ans $p 1 "waitingFor")) -eq "absent" -and (Src (Ans $p 1 "waitingFor")) -eq "X2" -and (St (Ans $p 4 "waitingFor")) -eq "absent") "an idle session, or one not running, waits for nothing"
Check ((Val (Ans $p 3 "runId")) -eq "20260601-100000-alpha" -and (Val (Ans $p 3 "title")) -eq "the alpha lane" -and (Src (Ans $p 3 "title")) -eq "W4" -and (Val (Ans $p 3 "spawnedAt")) -like "2026-06-01T10:10:00*") "the run, title and spawn time come from the roster"
Check (@(Val (Ans $p 17 "dependsOn")) -contains "alpha" -and (St (Ans $p 17 "spawnedAt")) -eq "absent" -and (Val (Ans $p 10 "spawnedAt")) -like "2026-06-01T11:05:00*" -and (Src (Ans $p 10 "spawnedAt")) -eq "W2") "a null spawn time is absent, and a claim gives one when there is no roster"
Check ((Src (Ans $p 1 "startedAt")) -eq "X2" -and (Src (Ans $p 33 "startedAt")) -eq "X5" -and (Src (Ans $p 4 "startedAt")) -eq "W1") "a start time comes from the control file, then the process, then firstSeen"
Check ((Src (Ans $p 1 "procStart")) -eq "X2" -and (Src (Ans $p 33 "procStart")) -eq "X5" -and (Val (Ans $p 33 "procStart")) -eq (Utc "2026-06-01T11:42:00Z").ToFileTimeUtc()) "a process start comes from the control file, then the process table"
Check ((Val (Ans $p 1 "origin")) -eq "user" -and (Val (Ans $p 3 "origin")) -eq "fleet" -and (Val (Ans $p 1 "lastSeen")) -like "2026-06-01T11:59:00*" -and (Val (Ans $p 5 "retired")) -eq $true -and (Val (Ans $p 1 "retired")) -eq $false) "origin, lastSeen and retired come from the registry"
Check ((Val (Ans $p 2 "owner")) -eq "M" -and (Src (Ans $p 2 "owner")) -eq "W1" -and (Val (Ans $p 10 "owner")) -eq "M") "the owner is the parent's label, derived, never the stored name"
Check ((Val (Ans $p 1 "owner")) -eq "founder") "a user session with no parent is owned by the founder"
$rep3 = Val (Ans $p 3 "report")
Check ($null -ne $rep3 -and "$($rep3.event)" -eq "progress" -and "$($rep3.summary)" -eq "halfway" -and (Src (Ans $p 3 "report")) -eq "W5") "the report is the last event in the log"
Check ((Val (Ans $p 3 "workState")) -eq "running") "a reporting session with a live handle is running"
Check ((Src (Ans $p 3 "lastActivity")) -eq "W6" -and (Val (Ans $p 3 "lastActivity")) -like "2026-06-01T11:59:40*") "last activity takes the newest source"
Check ((Src (Ans $p 1 "lastActivity")) -eq "X3") "CONTROL: a transcript newer than the control file's time is the newest source"
Check ((St (Ans $p 15 "lastActivity")) -eq "unknown" -and (Why (Ans $p 15 "lastActivity")) -like "*never idle*") "no transcript leaves last activity unknown"
Check ((Val (Ans $p 21 "transcriptPath")) -like "*C--work-x*" -and (Src (Ans $p 21 "transcriptPath")) -eq "X3" -and (St (Ans $p 4 "transcriptPath")) -eq "unknown" -and (Why (Ans $p 4 "transcriptPath")) -like "*2 project folders*") "a stopped session's transcript is the one file for its id, never one of two"
Check ((Src (Ans $p 1 "transcriptPath")) -eq "X2" -and (Val (Ans $p 1 "transcriptPath")) -like "*C--work-alpha*") "a running session's transcript is derived from its control file"

Write-Host ""
Write-Host "--- the pane, and the lead's decisions of 2026-09-30 ---" -ForegroundColor Cyan
# DECISION 1: several sessions claim one handle - every claimant unknown, naming all of them.
$claimants = @(7, 8, 9)
$allUnknown = @($claimants | Where-Object { (St (Ans $p $_ "pane")) -ne "unknown" -or -not ((Why (Ans $p $_ "pane")) -like ("*" + (Sid 7) + "*" + (Sid 8) + "*" + (Sid 9) + "*")) }).Count -eq 0
Check $allUnknown "every claimant of one handle has an unknown pane naming every claimant"
$hc = Fault $p "handle-claimed-twice"
Check ((FSt $hc) -eq "true" -and (Subjects $hc) -contains "handle 16" -and (Subjects $hc) -contains (Sid 8)) "a handle claimed twice is reported as a fault"
$row16 = @((Val $p.handles) | Where-Object { $_.handle -eq "16" })
Check ($row16.Count -eq 1 -and @($row16[0].claimants).Count -eq 3 -and @($row16[0].sessions).Count -eq 0) "the claimed handle lists its claimants and answers for none of them"
# DECISION 2: with no host to ask, a stored handle cannot be verified - unknown, never absent.
$pu = Project $base -HostPort (New-HordeUnavailableHostPort -Reason "the fixture's host is switched off")
$notUnknown = @($pu.sessions | Where-Object { $_.fields["pane"].answer.state -ne "unknown" } | ForEach-Object { $_.sessionId })
Check ($notUnknown.Count -eq 0 -and (Why (Ans $pu 4 "pane")) -like "*switched off*") "an unreadable handle list leaves every pane unknown"
Check ($pu.handles.state -eq "unknown") "parity exception unreadable mux is not an empty census"
$p0 = Project $base -HostPort (HostOf $base -Running 0)
Check (@($p0.sessions | Where-Object { $_.fields["pane"].answer.state -ne "unknown" }).Count -eq 0 -and (Why (Ans $p0 1 "pane")) -like "*no terminal instance is running*") "with no host instance running every pane is unknown"
$pe = Project $base -HostPort (HostOf $base -NoHandles)
Check ($pe.handles.state -eq "known" -and @(Val $pe.handles).Count -eq 0) "an empty handle list is known and empty"
Check ((St (Ans $pe 1 "pane")) -eq "unknown" -and (St (Ans $pe 4 "pane")) -eq "absent") "with no live handle a running session is unknown and a stopped one absent"
# DECISION 3: every live handle is listed, with or without a session.
$rows = @(Val $p.handles)
$r30 = @($rows | Where-Object { $_.handle -eq "30" })
Check ($rows.Count -eq 13 -and $r30.Count -eq 1 -and @($r30[0].sessions).Count -eq 0 -and "$($r30[0].hostTitle)" -eq "pwsh") "a handle no session answers is still listed"
$r10 = @($rows | Where-Object { $_.handle -eq "10" })
Check ($r10.Count -eq 1 -and @($r10[0].sessions).Count -eq 1 -and @($r10[0].sessions)[0] -eq (Sid 1)) "CONTROL: a handle a session answers lists that session"
Check ((Val (Ans $p 3 "title")) -eq "the alpha lane" -and "$(@($rows | Where-Object { $_.handle -eq '12' })[0].hostTitle)" -eq "tab 12") "the host title is not the session title"
# The rest of the pane row.
Check ((St (Ans $p 4 "pane")) -eq "absent") "a paneless session reads absent, not unknown"
Check ((St (Ans $p 5 "pane")) -eq "absent" -and (Why (Ans $p 5 "pane")) -like "*and it is not running*") "a retired record answers no pane"
Check ((St (Ans $p 30 "pane")) -eq "absent") "a record from another instance names no pane"
Check ((St (Ans $p 31 "pane")) -eq "absent") "a record written before the instance started names no pane"
Check ((Has $p "codex-thread-1") -and (St (Ans $p "codex-thread-1" "pane")) -eq "unknown" -and (St (Ans $p 12 "pane")) -eq "unknown") "a session outside every host is still listed"
$pi = Project $base -HostPort (HostOf $base -Id "inst-0")
Check ((Val (Ans $pi 30 "pane")) -eq "23" -and (Src (Ans $pi 1 "pane")) -ne "W1") "an injected instance is the one judged"
$pa = Project $base -HostPort (HostOf $base -Ambiguous)
Check (@($pa.sessions | Where-Object { $_.fields["pane"].answer.state -eq "known" }).Count -eq 0 -and (Why (Ans $pa 1 "pane")) -like "*ambiguous*") "an ambiguous host instance trusts no record"
$p2 = Project $base -HostPort (HostOf $base -Running 2)
Check ((St (Ans $p2 10 "pane")) -eq "unknown" -and (Why (Ans $p2 10 "pane")) -like "*2 host instances*" -and (Val (Ans $p2 1 "pane")) -eq "10") "two host instances refuse every pane file"
$quiet = New-Fleet "quiet"
EditReg $quiet 2 { param($r) $r.lastSeen = "2026-06-01T10:10:00.0000000Z" }
Check ((Val (Ans (Project $quiet) 2 "pane")) -eq "11") "a quiet session keeps its registry pane"
$late = New-Fleet "late"
$pl = Project $late -HostPort (HostOf $late -Add @("26"))
Check ((Val (Ans $pl 34 "pane")) -eq "26" -and (Src (Ans $pl 34 "pane")) -eq "W5") "a report's handle answers when the registry and pane-sessions do not"
# A pane number never makes a session: with its record gone, 31's only trace is a stale file.
$nopane = New-Fleet "nopane"
Remove-Item -LiteralPath (RegPath $nopane 31) -Force
$pn = Project $nopane
Check (-not (Has $pn 31) -and (Has $pn 30)) "no session is inferred from a pane number"
$keepEnv = $env:CLAUDE_CODE_SESSION_ID
try { $env:CLAUDE_CODE_SESSION_ID = (Sid 77); $penv = Project $base } finally { $env:CLAUDE_CODE_SESSION_ID = $keepEnv }
Check (-not (Has $penv 77) -and @($penv.sessions).Count -eq 34) "the environment never names another session"

Write-Host ""
Write-Host "--- the host port contract (core/HostPort.ps1) ---" -ForegroundColor Cyan
# CAPABILITIES ARE DECLARED. A port without a declaration is refused, and so is a name or a state
# outside the vocabulary; core relies on a capability only when it is yes.
$noop = { return , @() }
Check ((Throws { New-HordeHostPort -Name "x" -Capabilities $null -Handles $noop -Instance $noop } "Capabilities") -and (Throws { New-HordeHostPort -Name "x" -Capabilities @{ "list" = "maybe" } -Handles $noop -Instance $noop } "yes, no, declined or unverified") -and (Throws { New-HordeHostPort -Name "x" -Capabilities @{ "readMinds" = "yes" } -Handles $noop -Instance $noop } "not a host capability")) "a host port must declare its capabilities from the closed vocabulary"
$offPort = New-HordeUnavailableHostPort -Reason "switched off"
Check (@($script:HordeHostCapabilityNames | Where-Object { Test-HordeHostCapability -Port $offPort -Name $_ }).Count -eq 0 -and $script:HordeHostCapabilityNames.Count -ge 10) "the unavailable host declares every capability no"
$pnl2 = Project $base -HostPort (HostOf $base -Caps @{ "list" = "no" })
Check ($pnl2.handles.state -eq "unknown" -and $pnl2.handles.reason -like "*does not offer list*" -and @($pnl2.sessions | Where-Object { $_.fields["pane"].answer.state -ne "unknown" }).Count -eq 0) "a host that does not offer its handle list leaves every pane unknown"
$pun = Project $base -HostPort (HostOf $base -Caps @{ "instance.startedAt" = "unverified" })
Check ((St (Ans $pun 1 "pane")) -eq "unknown" -and (Why (Ans $pun 1 "pane")) -like "*does not offer instance.startedAt*") "an unverified capability counts as no"
$declPort = HostOf $base -Caps @{ "text.read" = "declined" }
Check ((Test-HordeHostCapability -Port $declPort -Name "text.read") -eq $false -and (Test-HordeHostCapability -Port $declPort -Name "list") -eq $true) "a declined capability is not relied on"
# A HANDLE IS UNIQUE WITHIN ITS INSTANCE, as plain text; a native id with a sigil is the adapter's to map.
function RowsPort { param([object[]]$Rows, [hashtable]$Caps = @{ "list" = "yes" }) $rb = { return , $Rows }.GetNewClosure(); return (New-HordeHostPort -Name "fake" -Capabilities $Caps -Handles $rb -Instance $noop) }
$sigil = Read-HordeHostHandles -Port (RowsPort @([pscustomobject]@{ handle = ([string][char]37 + "1") }))
Check ($sigil.state -eq "unknown" -and $sigil.reason -like "*plain handle text*") "a native id with a sigil is refused, so adapters map it to handle text"
$twice = Read-HordeHostHandles -Port (RowsPort @([pscustomobject]@{ handle = "p1" }, [pscustomobject]@{ handle = "p1" }))
Check ($twice.state -eq "unknown" -and $twice.reason -like "*unique within its instance*") "a handle listed twice in one instance makes the list unknown"
$composed = Read-HordeHostHandles -Port (RowsPort @([pscustomobject]@{ handle = "s1.p1" }, [pscustomobject]@{ handle = "s2.p1" }))
Check ($composed.state -eq "known" -and @($composed.value).Count -eq 2) "CONTROL: two servers' panes composed with their session are two handles"
# RUNNING COUNTS INSTANCES, NOT SERVERS: a host with one server per session reports one instance,
# and its pane-sessions files are read; two instances refuse them (checked above).
$p1inst = Project $base -HostPort (HostOf $base -Running 1)
Check ((Val (Ans $p1inst 10 "pane")) -eq "17" -and (Src (Ans $p1inst 10 "pane")) -eq "X1") "one instance with many servers still reads its pane-sessions files"
# PID AND CWD CARRY A NAMESPACE, and only core's own is ever compared.
$nsCaps = @{ "list" = "yes"; "pid" = "yes"; "cwd" = "yes" }
$ns = Read-HordeHostHandles -Port (RowsPort -Caps $nsCaps @(
    [pscustomobject]@{ handle = "a"; pid = 4242; cwd = "C:\work"; space = "windows" },
    [pscustomobject]@{ handle = "b"; pid = 4242; cwd = "/home/w"; space = "wsl:Ubuntu" },
    [pscustomobject]@{ handle = "c"; pid = 4242; cwd = "C:\work" }))
$nsRows = @{}; foreach ($r in @(Val $ns)) { $nsRows[$r.handle] = $r }
Check ($ns.state -eq "known" -and $nsRows["b"].pid.state -eq "unknown" -and $nsRows["b"].pid.reason -like "*never compared across namespaces*" -and $nsRows["b"].cwd.state -eq "unknown") "a pid from another namespace is unknown, never compared"
Check ($nsRows["c"].pid.state -eq "unknown" -and $nsRows["c"].pid.reason -like "*no namespace*") "a pid with no namespace is unknown"
Check ((Val $nsRows["a"].pid) -eq 4242 -and (Val $nsRows["a"].cwd) -eq "C:\work") "CONTROL: a pid in core's own namespace is known"
$nsNo = Read-HordeHostHandles -Port (RowsPort @([pscustomobject]@{ handle = "a"; pid = 4242; space = "windows" }))
Check (@(Val $nsNo)[0].pid.state -eq "unknown" -and @(Val $nsNo)[0].pid.reason -like "*does not offer pid*") "a pid the host does not declare is not relied on"

Write-Host ""
Write-Host "--- the pane-sessions guard ---" -ForegroundColor Cyan
$two = Fault $p "session-in-two-handles"
Check ((FSt $two) -eq "true" -and (Subjects $two) -contains (Sid 13) -and (St (Ans $p 13 "pane")) -eq "unknown") "a session in two handles is reported"
$hij = Fault $p "pane-sessions-hijack"
Check ((FSt $hij) -eq "true" -and (Subjects $hij) -contains (Sid 11) -and (Subjects $hij) -contains (Sid 12) -and (Val (Ans $p 11 "pane")) -eq "18" -and (St (Ans $p 12 "pane")) -eq "unknown") "a hijacked pane file does not answer"
$tx = New-Fleet "transcript"
Remove-Item -LiteralPath (Join-Path $tx ("claude\projects\C--work-delta\" + (Sid 10) + ".jsonl")) -Force
$ptx = Project $tx
Check ((St (Ans $ptx 10 "transcriptPath")) -eq "unknown" -and (Why (Ans $ptx 10 "transcriptPath")) -like "*names a transcript that exists*") "a pane file naming a missing transcript does not answer the transcript"
$f17 = Join-Path $tx "claude\pane-sessions\17.json"
$j17 = ReadJson $f17; $j17.transcript_path = (Join-Path $tx "claude\projects\C--work-x\aaaaaaaa-0000-4000-8000-000000000021.jsonl"); PutJson $f17 $j17
[System.IO.File]::SetLastWriteTimeUtc($f17, $now.AddMinutes(-50))
$ptx2 = Project $tx
Check ((Src (Ans $ptx2 10 "transcriptPath")) -eq "X1") "CONTROL: a pane file naming a transcript that exists answers it"

$ref40 = @($p.inputs.paneRead.refused | Where-Object { $_.name -eq "40.json" })
Check ($ref40.Count -eq 1 -and "$($ref40[0].reason)" -like "*pane-session.v1*" -and $p.complete["X1"].state -eq "known") "a pane-sessions file that breaks the schema is refused, not a gap"

Write-Host ""
Write-Host "--- the spawn claim's guard ---" -ForegroundColor Cyan
# The claim for handle 17 names session 10's role, label and parent. It is read only while the
# session has no registry record, within wezfleet's seven-day backstop, and for the same directory.
$cl1 = New-Fleet "claim-record"
PutJson (RegPath $cl1 10) ([ordered]@{ claudeSessionId = (Sid 10); origin = "user"; fleetSessionId = ""; pane = "17"; instance = "inst-1"; cwd = "C:\work\delta"; firstCwd = "C:\work\delta"; owner = ""; firstSeen = "2026-06-01T11:00:00.0000000Z"; lastSeen = "2026-06-01T11:58:00.0000000Z"; lastTool = "Bash" })
$pcl1 = Project $cl1
Check ((St (Ans $pcl1 10 "role")) -eq "unknown" -and (Src (Ans $pcl1 10 "role")) -eq "" -and (St (Ans $pcl1 10 "label")) -eq "absent" -and (Src (Ans $pcl1 10 "label")) -eq "W1") "a claim is not read once the session has a record"
$cl2 = New-Fleet "claim-old"
$c2 = ReadJson (Join-Path $cl2 "wezfleet\registry\claims\17.json"); $c2.spawnedAt = "2026-05-24T11:00:00.0000000Z"; PutJson (Join-Path $cl2 "wezfleet\registry\claims\17.json") $c2
Check ((St (Ans (Project $cl2) 10 "role")) -eq "unknown") "a claim past the seven-day backstop does not answer"
$cl3 = New-Fleet "claim-cwd"
$c3 = ReadJson (Join-Path $cl3 "wezfleet\registry\claims\17.json"); $c3.cwd = "C:\elsewhere"; PutJson (Join-Path $cl3 "wezfleet\registry\claims\17.json") $c3
Check ((St (Ans (Project $cl3) 10 "role")) -eq "unknown") "a claim naming another directory does not answer"

Write-Host ""
Write-Host "--- a stored value the view cannot carry ---" -ForegroundColor Cyan
# schema/session-record.v1's types are the view's for engine fields: a label of the wrong shape or a
# parent that is not a session id is never passed on as known.
$shape = New-Fleet "shape"
EditReg $shape 4 { param($r) $r | Add-Member -NotePropertyName label -NotePropertyValue "b-1" -Force; $r.parent = "the orchestrator" }
$psh = Project $shape
Check ((St (Ans $psh 4 "label")) -eq "unknown" -and (Why (Ans $psh 4 "label")) -like "*does not match*" -and (St (Ans $psh 4 "parent")) -eq "unknown") "a stored value the view cannot carry is unknown, naming why"
$shDoc = (ConvertTo-HordeSessionViewDocument $psh) | ConvertTo-Json -Depth 40 | ConvertFrom-Json
Check (@(Test-HordeSchema -Value $shDoc -Schema $viewSchema).Count -eq 0) "and the view that carries it still validates"

Write-Host ""
Write-Host "--- a store that cannot tell is not a store that holds none ---" -ForegroundColor Cyan
# A candidate that is skipped proves "none" only when its store was read whole and holds nothing for
# the session. When the skip rests on something unknown - a run no one can choose, a handle the host
# cannot verify, a registry with a hole in it - the answer is unknown (review of PR #31, finding 1).
$amb = Project (New-Fleet "ambiguous-run")
$ambBad = @(15, 16 | ForEach-Object { $n = $_; @("title", "dependsOn", "spawnedAt") | Where-Object { (St (Ans $amb $n $_)) -ne "unknown" } | ForEach-Object { "" + $n + " " + $_ + "=" + (St (Ans $amb $n $_)) } })
foreach ($x in $ambBad) { Write-Host ("  not unknown: " + $x) -ForegroundColor Red }
Check ($ambBad.Count -eq 0) "a session whose run cannot be chosen has an unknown title, never absent"
$nh = New-Fleet "nohost-fleet"
$nhc = Join-Path $nh "wezfleet\registry\claims\17.json"; $nhj = ReadJson $nhc; $nhj.fleetSessionId = "fleet-x"; PutJson $nhc $nhj
Check ((Val (Ans (Project $nh) 10 "fleetSessionId")) -eq "fleet-x") "CONTROL: with the host attached, the claim gives the fleet id"
$pnh = Project $nh -HostPort (New-HordeUnavailableHostPort -Reason "switched off")
$nhBad = @("fleetSessionId", "runId", "spawnedAt" | Where-Object { (St (Ans $pnh 10 $_)) -ne "unknown" } | ForEach-Object { $_ + "=" + (St (Ans $pnh 10 $_)) })
foreach ($x in $nhBad) { Write-Host ("  not unknown: " + $x) -ForegroundColor Red }
Check ($nhBad.Count -eq 0) "with no host, a claim that cannot be matched leaves the fleet id unknown, never absent"
$noreg = New-Fleet "noreg"
Rename-Item -LiteralPath (Join-Path $noreg "wezfleet\registry\sessions") -NewName "sessions-hidden"
$pnr = Project $noreg
$nrBad = @(1, 2 | ForEach-Object { $n = $_; @("fleetSessionId", "parent", "label", "origin") | Where-Object { (St (Ans $pnr $n $_)) -ne "unknown" } | ForEach-Object { "" + $n + " " + $_ + "=" + (St (Ans $pnr $n $_)) } })
foreach ($x in $nrBad) { Write-Host ("  not unknown: " + $x) -ForegroundColor Red }
Check ($pnr.complete["W1"].state -eq "unknown" -and $nrBad.Count -eq 0) "an incomplete registry never proves a session has no record"
$realExtras = ${function:Read-HordeControlExtras}
function Read-HordeControlExtras { param($Record) if ("$($Record.fields.agent.value)" -ceq "codex") { return $null }; return (& $realExtras -Record $Record) }
$pcx = $null
try { $pcx = Project $base } finally { ${function:Read-HordeControlExtras} = $realExtras }
Check ((St (Ans $pcx "codex-thread-1" "fleetSessionId")) -eq "unknown" -and (Why (Ans $pcx "codex-thread-1" "fleetSessionId")) -like "*could not be read again*") "a codex file that cannot be read again is not a codex file that is missing"

Write-Host ""
Write-Host "--- runs, reports and work ---" -ForegroundColor Cyan
Check ((St (Ans $p 15 "runId")) -eq "unknown" -and (Why (Ans $p 15 "runId")) -like "*2 open runs*") "two open runs make the run unknown"
Check ((St (Ans $p 16 "runId")) -eq "unknown" -and (Why (Ans $p 16 "runId")) -like "*only by closed runs*") "two closed runs are not chosen between"
$ra = Fault $p "run-ambiguous"
Check ((FSt $ra) -eq "true" -and (Subjects $ra) -contains (Sid 15) -and (Subjects $ra) -contains (Sid 16)) "an ambiguous run is reported as a fault"
Check ((Val (Ans $p 17 "workState")) -eq "pending" -and (Src (Ans $p 17 "workState")) -eq "W4") "an unspawned roster entry reads pending"
Check ((Val (Ans $p 18 "workState")) -eq "orphaned") "a gone handle with stopped activity is orphaned"
Check ((Val (Ans $p 19 "workState")) -eq "running") "a gone pane with fresh activity is not orphaned"
Check ((Val (Ans $p 20 "workState")) -eq "done") "a done event is trusted outright"
Check ((St (Ans $pu 18 "workState")) -eq "unknown" -and (Why (Ans $pu 18 "workState")) -like "*never makes an orphan*") "unknown liveness is never orphaned"
Check ((St (Ans $p 1 "workState")) -eq "absent" -and (St (Ans $p 1 "report")) -eq "absent") "a session in no run has no work state and no report"
$future = New-Fleet "future"
[System.IO.File]::SetLastWriteTimeUtc((Join-Path $future "wezfleet\proj\runs\20260601-100000-alpha\sessions\alpha\cmdlog.txt"), $now.AddSeconds(60))
$pf = Project $future
Check ((St (Ans $pf 3 "lastActivity")) -eq "unknown" -and (Why (Ans $pf 3 "lastActivity")) -like "*in the future*") "a future activity time is not fresh"
$bad = New-Fleet "badlog"
Add-Content -LiteralPath (Join-Path $bad "wezfleet\proj\runs\20260601-100000-alpha\sessions\alpha\events.jsonl") -Value '{"ts":"2026-06-01T11:59:00Z","event":"do'
$pb = Project $bad
Check ((St (Ans $pb 3 "report")) -eq "unknown" -and $pb.complete["W5"].state -eq "unknown") "an event log with a torn line is unknown, never shorter"

Write-Host ""
Write-Host "--- cardinality checks ---" -ForegroundColor Cyan
Check ((FSt (Fault $p "no-warchief")) -eq "false" -and (FSt (Fault $p "two-warchiefs")) -eq "false") "CONTROL: one warchief is neither none nor two"
$nowc = New-Fleet "nowarchief"
EditReg $nowc 1 { param($r) $r.role = "session" }
$pnw = Project $nowc
Check ((FSt (Fault $pnw "no-warchief")) -eq "true") "no warchief is reported as a fault"
$twowc = New-Fleet "twowarchiefs"
EditReg $twowc 2 { param($r) $r.role = "master" }
$ptw = Project $twowc
$tw = Fault $ptw "two-warchiefs"
Check ((FSt $tw) -eq "true" -and (Subjects $tw) -contains (Sid 1) -and (Subjects $tw) -contains (Sid 2)) "two warchiefs are reported and both named"
Check ((FSt (Fault $ptw "orc-not-under-warchief")) -eq "unknown") "an orc's parent is judged only when exactly one warchief is known"
$corrupt = New-Fleet "corrupt"
PutText (RegPath $corrupt 23) "{ not json"
$pc = Project $corrupt
Check ($pc.complete["W1"].state -eq "unknown" -and $pc.complete["W1"].reason -like ("*" + (Sid 23) + "*")) "a corrupt record makes the registry incomplete"
Check ((FSt (Fault $pc "two-warchiefs")) -eq "unknown" -and (St (Ans $pc 23 "role")) -eq "unknown" -and (Has $pc 23)) "an unreadable registry leaves the warchief count unknown"
$misn = New-Fleet "misnamed"
$copy = ReadJson (RegPath $misn 24); $copy.claudeSessionId = (Sid 55); PutJson (Join-Path $misn "wezfleet\registry\sessions\copy-of-24.json") $copy
$pm = Project $misn
Check ($pm.complete["W1"].state -eq "unknown" -and $pm.complete["W1"].reason -like "*copy-of-24.json*" -and -not (Has $pm 55)) "a misnamed record is refused and reported"
$roleless = New-Fleet "roleless"
EditReg $roleless 4 { param($r) $r.PSObject.Properties.Remove("role") }
$prl = Project $roleless
Check ((St (Ans $prl 4 "role")) -eq "unknown" -and (FSt (Fault $prl "two-warchiefs")) -eq "unknown") "a live record with no role is unknown, never goblin, and makes the count unknown"
$oc = Fault $p "orc-not-under-warchief"
Check ((FSt $oc) -eq "true" -and (Subjects $oc) -contains (Sid 25) -and -not ((Subjects $oc) -contains (Sid 2))) "an orc under another parent is reported"
$pmiss = Fault $p "parent-missing"; $pret = Fault $p "parent-retired"
Check ((FSt $pmiss) -eq "true" -and (Subjects $pmiss) -contains (Sid 21) -and -not ((Subjects $pmiss) -contains (Sid 22))) "a parent with no record is reported"
Check ((FSt $pret) -eq "true" -and (Subjects $pret) -contains (Sid 22) -and (Subjects $pret) -contains (Sid 5)) "a retired parent is not a missing parent"
$cyc = Fault $p "parent-cycle"
Check ((FSt $cyc) -eq "true" -and (Subjects $cyc) -contains (Sid 28) -and (Subjects $cyc) -contains (Sid 29)) "a loop of parent edges is reported"
$dup = Fault $p "conversation-in-two-processes"
Check ((FSt $dup) -eq "true" -and (Subjects $dup) -contains (Sid 32) -and (Subjects $dup) -contains "pid 1101") "one conversation in two processes is a fault"
$rbr = Fault $p "running-but-retired"
Check ((FSt $rbr) -eq "true" -and @(Subjects $rbr).Count -eq 1 -and (Subjects $rbr) -contains (Sid 6)) "a live session with a tombstone is reported"
$orph = Fault $p "orphan-process"
Check ((FSt $orph) -eq "true" -and (Subjects $orph) -contains "pid 1099" -and -not ((Subjects $orph) -contains "pid 1001")) "a claude process no control file verifies is an orphan"
$fid = Fault $p "fleet-id-on-two-records"
Check ((FSt $fid) -eq "true" -and (Subjects $fid) -contains (Sid 26) -and (Subjects $fid) -contains (Sid 27)) "one fleet id on two live records is reported"
$lbl = Fault $p "label-held-twice"
Check ((FSt $lbl) -eq "true" -and (Subjects $lbl) -contains (Sid 23) -and (Subjects $lbl) -contains (Sid 24)) "one label held by two live records is reported"
$nu = Fault $p "session-id-not-uuid"
Check ((FSt $nu) -eq "true" -and (Subjects $nu) -contains "codex-thread-1" -and (Has $p "codex-thread-1")) "a non-uuid session id is keyed and flagged"
Check ((FSt (Fault $p "registry-hook-silent")) -eq "false" -and (FSt (Fault $p "warchief-claim-pending")) -eq "false") "CONTROL: a writing hook and no warchief claim are not faults"
$silent = New-Fleet "silent"
foreach ($n in @(1, 2, 3, 6, 7, 11)) { Remove-Item -LiteralPath (RegPath $silent $n) -Force }
Check ((FSt (Fault (Project $silent) "registry-hook-silent")) -eq "true") "running sessions with no registry record at all mean the hook is silent"
$pend = New-Fleet "pending"
$c17 = ReadJson (Join-Path $pend "wezfleet\registry\claims\17.json"); $c17.role = "master"; PutJson (Join-Path $pend "wezfleet\registry\claims\17.json") $c17
$ppd = Project $pend
Check ((FSt (Fault $ppd "warchief-claim-pending")) -eq "true" -and (Subjects (Fault $ppd "warchief-claim-pending")) -contains "handle 17") "a pending warchief claim is reported apart from the running count"
# CONTROL for every check: a fleet with nothing wrong gives every check a known false.
$clean = New-Fleet "clean"
foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $clean "wezfleet\registry\sessions") -File)) { if ($f.BaseName -ne (Sid 1) -and $f.BaseName -ne (Sid 2)) { Remove-Item -LiteralPath $f.FullName -Force } }
foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $clean "claude\sessions") -File)) { if (@("1001.json", "1002.json") -notcontains $f.Name) { Remove-Item -LiteralPath $f.FullName -Force } }
foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $clean "claude\pane-sessions") -File)) { if ($f.Name -ne "10.json") { Remove-Item -LiteralPath $f.FullName -Force } }
Remove-Item -LiteralPath (Join-Path $clean "wezfleet\codex-sessions") -Recurse -Force
New-Item -ItemType Directory -Path (Join-Path $clean "wezfleet\codex-sessions") | Out-Null
foreach ($repo in @("proj", "other")) { Remove-Item -LiteralPath (Join-Path $clean ("wezfleet\" + $repo)) -Recurse -Force }
PutJson (Join-Path $clean "processes.json") @(@(ReadJson (Join-Path $clean "processes.json")) | Where-Object { @(1001, 1002, 4) -contains [int]$_.pid })
$pcl = Project $clean
$notFalse = @($pcl.faults | Where-Object { (FSt $_) -ne "false" } | ForEach-Object { $_.kind + "=" + (FSt $_) + " " + $_.answer.reason })
foreach ($x in $notFalse) { Write-Host ("  not false on the clean fleet: " + $x) -ForegroundColor Red }
Check (@($pcl.sessions).Count -eq 2 -and @($pcl.faults).Count -eq 18 -and $notFalse.Count -eq 0) "CONTROL: a clean fleet has no fault, and every check says so"
Check ((FSt (Fault $pu "handle-claimed-twice")) -eq "unknown" -and (FSt (Fault $pu "session-in-two-handles")) -eq "unknown") "with no host to ask, the handle checks are unknown, not clean"

Write-Host ""
Write-Host "--- parity differences, in their documented direction (planning/parity-2.3.md) ---" -ForegroundColor Cyan
# P-17: the run snapshot trusts the registry's handle only while lastSeen is under 900 s old, then
# falls back to the roster. Horde trusts it for the whole instance.
$snap = New-Fleet "snapshot"
EditReg $snap 3 { param($r) $r.pane = "15"; $r.lastSeen = "2026-06-01T11:40:00.0000000Z" }
$psn = Project $snap
Check ((Val (Ans $psn 3 "pane")) -eq "15" -and (Src (Ans $psn 3 "pane")) -eq "W1") "parity exception snapshot pane order"
# P-09: census derives the transcript from the CURRENT cwd, with a colon-and-slash key; the view
# finds it from the launch directory.
$moved = New-Fleet "moved"
EditReg $moved 21 { param($r) $r.cwd = "C:\work\moved" }
$pmv = Project $moved
$censusRule = Join-Path $moved ("claude\projects\" + ("C:\work\moved" -replace '[:\\/]', '-') + "\" + (Sid 21) + ".jsonl")
Check ((Val (Ans $pmv 21 "transcriptPath")) -like "*C--work-x*" -and (Val (Ans $pmv 21 "projectCwd")) -eq "C:\work\x" -and -not (Test-Path -LiteralPath $censusRule)) "parity exception census transcript from current cwd"
# P-11: census prints the stored owner, "(unowned)" when empty; the view derives the parent's label.
Check ("$((ReadJson (RegPath $base 4)).owner)" -eq "" -and (Val (Ans $p 4 "owner")) -eq "A") "parity exception owner derived from parent"
# P-12: census prints origin "unknown" for a record with none.
$noorigin = New-Fleet "noorigin"
EditReg $noorigin 4 { param($r) $r.PSObject.Properties.Remove("origin") }
Check ((St (Ans (Project $noorigin) 4 "origin")) -eq "absent") "a missing origin is not the string unknown"

Write-Host ""
Write-Host "--- the layout and the resume command ---" -ForegroundColor Cyan
$rc1 = Ans $p 1 "resumeCommand"
Check ((St $rc1) -eq "unknown" -and @($rc1.shadow | Where-Object { $_.store -eq "R1" }).Count -eq 1 -and "$(@($rc1.shadow)[0].value)" -like "*--resume*") "a layout save never answers resumeCommand"
$rc3 = Ans $p 3 "resumeCommand"
Check ((St $rc3) -eq "unknown" -and @($rc3.shadow | Where-Object { $_.store -eq "W5" }).Count -eq 1) "the report's stored resume command is a shadow too"
Check ($p.complete["R1"].state -eq "known" -and $pu.complete["R1"].state -eq "known") "CONTROL: the layout port was read"
$pnl = Get-HordeProjection -WezfleetRoot (Join-Path $base "wezfleet") -ClaudeDir (Join-Path $base "claude\sessions") -ProjectsDir (Join-Path $base "claude\projects") -CodexDir (Join-Path $base "wezfleet\codex-sessions") -PaneSessionsDir (Join-Path $base "claude\pane-sessions") -Processes (ProcsOf $base) -HostPort (HostOf $base) -TtlSeconds 900 -Now $now
Check ($pnl.complete["R1"].state -eq "unknown" -and (St (Ans $pnl 1 "resumeCommand")) -eq "unknown") "with no layout port the saves are unknown, not empty"

Write-Host ""
Write-Host "--- schema/session-view.v1 ---" -ForegroundColor Cyan
$doc = (ConvertTo-HordeSessionViewDocument $p) | ConvertTo-Json -Depth 40 | ConvertFrom-Json
$sf = @(Test-HordeSchema -Value $doc -Schema $viewSchema)
foreach ($x in @($sf | Select-Object -First 10)) { Write-Host ("  " + $x) -ForegroundColor Red }
Check ($sf.Count -eq 0) "every answer validates against schema/session-view.v1"
$rf = @(Test-HordeSessionViewRules -Document $doc)
foreach ($x in @($rf | Select-Object -First 10)) { Write-Host ("  " + $x) -ForegroundColor Red }
Check ($rf.Count -eq 0) "the view keeps the rules the schema cannot state"
$docU = (ConvertTo-HordeSessionViewDocument $pu) | ConvertTo-Json -Depth 40 | ConvertFrom-Json
Check (@(Test-HordeSchema -Value $docU -Schema $viewSchema).Count -eq 0 -and @(Test-HordeSessionViewRules -Document $docU).Count -eq 0) "a view with no host validates too"
# CONTROLS: each check can fail.
$broken = $doc | ConvertTo-Json -Depth 40 | ConvertFrom-Json
$broken.sessions[0].fields.pid.PSObject.Properties.Remove("value")
$broken.sessions[0].fields.role | Add-Member -NotePropertyName value -NotePropertyValue "master" -Force
$broken.sessions[0].fields.role.state = "known"
Check (@(Test-HordeSessionViewRules -Document $broken | Where-Object { $_ -like "*fields.pid is known and has no value*" }).Count -eq 1) "CONTROL: a known answer with no value breaks the view's rules"
Check (@(Test-HordeSchema -Value $broken -Schema $viewSchema | Where-Object { $_ -like "*role.value*" }).Count -ge 1) "CONTROL: a role outside the native vocabulary fails the schema"
# Engine-stored fields: the view's value type is exactly the stored record's.
$rec = Get-HordeSchema -Name "session-record.v1"
$vals = Get-HordeViewValueSchemas -ViewSchema $viewSchema
function Strip { param($N) $o = [ordered]@{}; foreach ($q in $N.PSObject.Properties) { if ($q.Name -ne "description" -and $q.Name -notlike "x-*") { $o[$q.Name] = $q.Value } }; return ($o | ConvertTo-Json -Depth 10 -Compress) }
$differ = @($rec.properties.PSObject.Properties | Where-Object { $_.Name -ne "schemaVersion" -and $_.Name -ne "sessionId" } | Where-Object { -not $vals.ContainsKey($_.Name) -or (Strip $_.Value) -cne (Strip $vals[$_.Name]) } | ForEach-Object { $_.Name })
foreach ($x in $differ) { Write-Host ("  value type differs from the stored record: " + $x) -ForegroundColor Red }
Check (@($rec.properties.PSObject.Properties).Count -ge 16 -and $differ.Count -eq 0) "an engine-stored field's value type is the stored record's"
$viewFields = @($viewSchema.definitions.session.properties.fields.required)
Check (($viewFields -join ",") -ceq ($required -join ",")) "the view schema requires exactly the ownership table's fields"
# Provisional marks: wherever the table has one, and nowhere else it has none.
$provFields = @($ownership.fields | Where-Object { $null -ne $_.PSObject.Properties["provisional"] } | ForEach-Object { "$($_.name)" })
$missingMark = @($p.sessions | ForEach-Object { $s = $_; $provFields | Where-Object { "$($s.fields[$_].provisional)" -eq "" } })
$strayMark = @($p.sessions | ForEach-Object { $s = $_; @($s.fields.Keys) | Where-Object { $provFields -notcontains $_ -and "$($s.fields[$_].provisional)" -ne "" } })
Check ($provFields.Count -ge 5 -and $missingMark.Count -eq 0 -and $strayMark.Count -eq 0) "the view carries a provisional mark exactly where the table has one"
Check (@($ownership.dropped | ForEach-Object { "$($_.name)" } | Where-Object { (St (Ans $p 1 $_)) -ne "unknown" -or (Why (Ans $p 1 $_)) -notlike "*drops it*" }).Count -eq 0) "a dropped field is present and unknown, naming the drop"

Write-Host ""
Write-Host "--- the projection writes nothing ---" -ForegroundColor Cyan
# THE SYNTAX TREE (ledger L-001). core/Projection.ps1 and every file it loads, followed through its
# dot-sources, must hold no call that writes, moves or deletes a file, and none that signals a process.
$writeCommands = @("Set-Content", "Add-Content", "Out-File", "New-Item", "Remove-Item", "Move-Item", "Copy-Item", "Rename-Item", "Tee-Object",
                   "Clear-Content", "Set-Item", "Clear-Item", "New-ItemProperty", "Set-ItemProperty", "Remove-ItemProperty", "Stop-Process", "Start-Process", "Invoke-Item")
$writeMembers = @("WriteAllText", "WriteAllLines", "WriteAllBytes", "AppendAllText", "AppendAllLines", "AppendText", "CreateText", "Create", "CreateDirectory",
                  "Replace", "Move", "MoveTo", "Delete", "Copy", "CopyTo", "OpenWrite", "SetLastWriteTime", "SetLastWriteTimeUtc", "SetCreationTime",
                  "SetCreationTimeUtc", "SetAttributes", "Encrypt", "Decrypt", "Kill", "WriteLine", "Write")
function Find-HordeWriteCalls {
    param($Ast)
    $hits = New-Object System.Collections.ArrayList
    foreach ($n in $Ast.FindAll({ param($x) $true }, $true)) {
        if ($n -is [System.Management.Automation.Language.CommandAst]) {
            $name = $n.GetCommandName()
            if ($null -ne $name -and ($writeCommands -contains $name -or $name -like "Export-*" -or $name -like "Set-Acl" -or $name -ieq "taskkill")) { [void]$hits.Add("command " + $name + " at line " + $n.Extent.StartLineNumber) }
            if ($null -ne $name -and $name -ieq "New-Object" -and $n.Extent.Text -match 'Writer|FileStream') { [void]$hits.Add("New-Object writer at line " + $n.Extent.StartLineNumber) }
        }
        elseif ($n -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
            $m = "$($n.Member.Extent.Text)".Trim("'", '"')
            if ($writeMembers -contains $m) { [void]$hits.Add("member ." + $m + " at line " + $n.Extent.StartLineNumber) }
            if ($m -eq "Open") {
                # Judged by the mode and access arguments, never the share argument: sharing write is
                # what lets the writer keep writing (core/ReadShared.ps1). No access argument means
                # FileAccess.ReadWrite.
                $oa = @($n.Arguments)
                $mode = ""; if ($oa.Count -ge 2) { $mode = $oa[1].Extent.Text }
                $access = ""; if ($oa.Count -ge 3) { $access = $oa[2].Extent.Text }
                if ($oa.Count -lt 3 -or $access -match 'Write' -or $mode -match 'Create|Append|Truncate') { [void]$hits.Add("Open for writing at line " + $n.Extent.StartLineNumber) }
            }
            if ($m -eq "new" -and $n.Extent.Text -match 'Writer|FileStream') { [void]$hits.Add("a writer constructed at line " + $n.Extent.StartLineNumber) }
        }
        elseif ($n -is [System.Management.Automation.Language.FileRedirectionAst]) {
            if ($n.Location.Extent.Text -ne '$null') { [void]$hits.Add("redirection to " + $n.Location.Extent.Text + " at line " + $n.Extent.StartLineNumber) }
        }
    }
    return @($hits)
}
function Get-LoadedFiles {
    # The file and every core file it dot-sources, transitively, by the Join-Path $PSScriptRoot form.
    param([string]$Path)
    $seen = New-Object System.Collections.ArrayList
    $todo = New-Object System.Collections.ArrayList
    [void]$todo.Add([System.IO.Path]::GetFullPath($Path))
    while ($todo.Count -gt 0) {
        $f = $todo[0]; $todo.RemoveAt(0)
        if ($seen -contains $f) { continue }
        [void]$seen.Add($f)
        $tk = $null; $pe = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tk, [ref]$pe)
        foreach ($c in $ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.CommandAst] -and $x.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot }, $true)) {
            $m = [regex]::Match($c.Extent.Text, '"([A-Za-z]+\.ps1)"')
            if ($m.Success) { [void]$todo.Add([System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $f) $m.Groups[1].Value))) }
        }
    }
    return @($seen)
}
$loaded = @(Get-LoadedFiles (Join-Path $root "core\Projection.ps1"))
$names = @($loaded | ForEach-Object { Split-Path -Leaf $_ })
Check ($loaded.Count -ge 9 -and $names -contains "WezfleetState.ps1" -and $names -contains "Identity.ps1" -and $names -contains "HostPort.ps1") ("CONTROL: the scan follows every file the projection loads (" + ($names -join ", ") + ")")
$writes = @()
foreach ($f in $loaded) { $tk = $null; $pe = $null; $writes += @(Find-HordeWriteCalls ([System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tk, [ref]$pe)) | ForEach-Object { (Split-Path -Leaf $f) + ": " + $_ }) }
foreach ($x in $writes) { Write-Host ("  " + $x) -ForegroundColor Red }
Check ($writes.Count -eq 0) "the projection module contains no file-writing call"
# CONTROL: one of each kind the scan looks for, each on its own, must be flagged.
$seeded = @('Set-Content -Path x -Value 1', 'Add-Content x 1', '"a" | Out-File x', 'New-Item -ItemType File x', 'Remove-Item x', 'Move-Item a b', 'Copy-Item a b',
    'Rename-Item a b', '1 | Tee-Object -FilePath x', 'Export-Csv -Path x', 'Stop-Process -Id 1', '[System.IO.File]::WriteAllText("x", "y")',
    '[System.IO.File]::AppendAllText("x", "y")', '[System.IO.File]::Replace("a", "b", $null)', '[System.IO.File]::Delete("x")', '[System.IO.File]::Move("a", "b")',
    '[System.IO.File]::Open("x", "Open", "ReadWrite")', 'New-Object System.IO.StreamWriter("x")', '[System.IO.StreamWriter]::new("x")', '"a" > x', '"a" >> x',
    '$p.Kill()', '[System.IO.File]::SetLastWriteTimeUtc("x", (Get-Date))', '[System.IO.Directory]::CreateDirectory("x")')
$missed = @($seeded | Where-Object { $tk = $null; $pe = $null; @(Find-HordeWriteCalls ([System.Management.Automation.Language.Parser]::ParseInput($_, [ref]$tk, [ref]$pe))).Count -eq 0 })
foreach ($x in $missed) { Write-Host ("  not flagged: " + $x) -ForegroundColor Red }
Check ($missed.Count -eq 0) ("CONTROL: the scan flags every kind of file-writing call (" + ($seeded.Count - $missed.Count) + " of " + $seeded.Count + ")")
Check (@(Find-HordeWriteCalls ([System.Management.Automation.Language.Parser]::ParseInput('Get-Content x 2>$null; [System.IO.File]::Open("x", "Open", "Read", "ReadWrite")', [ref]$null, [ref]$null))).Count -eq 0) "CONTROL: a read and a discarded error stream are not writes"
# Every foreign file goes through the shared reader. core/Schema.ps1 reads Horde's own schema files,
# which no other system writes, with ReadAllText; nothing else may use another reader.
$plainReads = @()
foreach ($f in $loaded) {
    if ((Split-Path -Leaf $f) -eq "Schema.ps1") { continue }
    $tk = $null; $pe = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tk, [ref]$pe)
    foreach ($n in $ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.CommandAst] -or $x -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true)) {
        if ($n -is [System.Management.Automation.Language.CommandAst]) { $cn = $n.GetCommandName(); if (@("Get-Content", "Import-Csv", "Import-Clixml", "Select-String") -contains $cn) { $plainReads += (Split-Path -Leaf $f) + ": " + $cn } }
        else { $mn = "$($n.Member.Extent.Text)"; if (@("ReadAllText", "ReadAllLines", "ReadAllBytes", "OpenRead", "OpenText", "ReadLines") -contains $mn) { $plainReads += (Split-Path -Leaf $f) + ": ." + $mn } }
    }
}
foreach ($x in $plainReads) { Write-Host ("  " + $x) -ForegroundColor Red }
Check ($plainReads.Count -eq 0) "every foreign file is read through the shared reader"
# D12: nothing outside hosts/ names a terminal. The names are each host's own, from
# hosts/<name>/names.txt, so this suite spells none of them (test/test-host-names.ps1 is the
# repository-wide ratchet; this check pins the projection's files to zero, with no allowance).
$hostNames = @(Get-ChildItem -LiteralPath (Join-Path $root "hosts") -Directory | ForEach-Object { Join-Path $_.FullName "names.txt" } | Where-Object { Test-Path -LiteralPath $_ } |
    ForEach-Object { Get-Content -LiteralPath $_ } | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\|' } | ForEach-Object { ($_ -split '\|')[0].Trim().ToLowerInvariant() } | Where-Object { $_ -ne "" })
$newCore = @("Projection.ps1", "HostPort.ps1", "Faults.ps1", "PaneSessions.ps1", "WezfleetState.ps1")
$named = @($newCore | Where-Object { $txt = (Get-Content -LiteralPath (Join-Path $root ("core\" + $_)) -Raw).ToLowerInvariant(); @($hostNames | Where-Object { $txt.Contains($_) }).Count -gt 0 })
foreach ($x in $named) { Write-Host ("  names a terminal: core/" + $x) -ForegroundColor Red }
$caught = ($hostNames.Count -ge 1 -and ("x " + $hostNames[0].ToUpperInvariant() + " y").ToLowerInvariant().Contains($hostNames[0]))
Check ($hostNames.Count -ge 1 -and $caught -and $named.Count -eq 0) "the projection names no terminal"
$nonAscii = @($newCore | Where-Object { (Get-Content -LiteralPath (Join-Path $root ("core\" + $_)) -Raw -Encoding UTF8) -match '[^\x00-\x7F]' })
Check ($nonAscii.Count -eq 0) ("every projection source file is ASCII (" + ($nonAscii -join ", ") + ")")

# THE FIXTURE, BYTE FOR BYTE (ledger L-002): fingerprint every file, then project with every file
# held open against writing and deleting; the projection must still read everything, and leave no
# new or changed file behind.
function Get-TreeFingerprint { param([string]$Dir)
    return @(Get-ChildItem -LiteralPath $Dir -Recurse -Force | Sort-Object FullName | ForEach-Object {
        if ($_.PSIsContainer) { "D " + $_.FullName.Substring($Dir.Length) }
        else { "F " + $_.FullName.Substring($Dir.Length) + " " + $_.Length + " " + $_.LastWriteTimeUtc.Ticks + " " + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    }) -join "`n" }
$nw = New-Fleet "nowrite"
$hostNw = HostOf $nw; $procNw = ProcsOf $nw; $layNw = LayoutOf $nw
$before = Get-TreeFingerprint -Dir $nw
$holds = @(Get-ChildItem -LiteralPath $nw -Recurse -File | ForEach-Object { [System.IO.File]::Open($_.FullName, "Open", "Read", "Read") })
$pnw2 = $null; $nwThrew = $null
try { $pnw2 = Project $nw -HostPort $hostNw -Processes $procNw -Layout $layNw } catch { $nwThrew = $_.Exception.Message } finally { $holds | ForEach-Object { $_.Dispose() } }
$after = Get-TreeFingerprint -Dir $nw
if ($null -ne $nwThrew) { Write-Host ("  the projection threw: " + $nwThrew) -ForegroundColor Red }
$incomplete = @(); if ($null -ne $pnw2) { $incomplete = @($pnw2.complete.Keys | Where-Object { $_ -ne "R1" -and $_ -ne "X4" -and $pnw2.complete[$_].state -ne "known" }) }
Check ($null -eq $nwThrew -and $null -ne $pnw2 -and @($pnw2.sessions).Count -eq 34 -and $incomplete.Count -eq 0) ("the projection opens no store file for writing (" + ($incomplete -join ", ") + ")")
Check ($before -eq $after) "projecting leaves no new or changed file in any store"
PutText (Join-Path $nw "wezfleet\registry\sessions\x.lock") "x"
Check ((Get-TreeFingerprint -Dir $nw) -ne $before) "CONTROL: a reader that leaves a lock file behind is caught by the same comparison"
Remove-Item -LiteralPath (Join-Path $nw "wezfleet\registry\sessions\x.lock") -Force
# A WRITER HOLDING ITS FILE (ledger L-003): wezfleet swaps records in with File.Replace, which fails
# against the ordinary read share (core/ReadShared.ps1). Every file held open for writing, sharing
# read, write and delete as a writer does: the ordinary read fails, and the projection reads it all.
$wHolds = @(Get-ChildItem -LiteralPath $nw -Recurse -File | ForEach-Object { [System.IO.File]::Open($_.FullName, "Open", "ReadWrite", ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)) })
$plainFailed = $false; $pw = $null
try {
    try { $null = [System.IO.File]::ReadAllText((RegPath $nw 1)) } catch { $plainFailed = $true }
    $pw = Project $nw -HostPort $hostNw -Processes $procNw -Layout $layNw
} finally { $wHolds | ForEach-Object { $_.Dispose() } }
Check ($plainFailed) "CONTROL: an ordinary read fails while a writer holds its file"
$wIncomplete = @(); if ($null -ne $pw) { $wIncomplete = @($pw.complete.Keys | Where-Object { $_ -ne "R1" -and $_ -ne "X4" -and $pw.complete[$_].state -ne "known" }) }
Check ($null -ne $pw -and @($pw.sessions).Count -eq 34 -and $wIncomplete.Count -eq 0) "a wezfleet write succeeds while the projection reads"

foreach ($n in $script:trips) { Write-Host ("  tripped: " + $n) -ForegroundColor Red }
Check ($script:trips.Count -eq 0) "the suite reads no real store before the reality check"

} finally {
    if ((Split-Path -Leaf $work) -match '^horde-projection-[0-9a-f]{32}$' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host "--- reality check: this machine's own stores, read only, no host attached ---" -ForegroundColor Cyan
# The real functions go back in, and only here. Every store is read through the shared reader; the
# host is unavailable, so every pane must come back unknown - never absent (decision 2). Real-world
# faults - stray records, a running session with a tombstone - are REPORTED, not failed on (decision
# 4): they are facts about this machine. The section fails only if the projection throws, reads
# nothing, or produces a view that breaks its own schema.
#
# SKIPPED ONLY WHEN ASKED BY NAME, and said on every run - as test-roles' HORDE_SKIP_DRIFT. Measured
# 2026-09-30: reading the real stores (326 sessions) took 36 s alone and 197 s beside a mutation run,
# and validating the real view 99 s and 555 s, past tools\Mutate.ps1's 900 s limit per run. A mutant
# of core/projection must be caught by the fixture sections, so mutation runs set HORDE_SKIP_REALITY=1
# (test/mutations/projection.psd1); every other run reads the machine.
if ($env:HORDE_SKIP_REALITY -eq "1") {
    Write-Host "  [SKIP] the reality check did not run: HORDE_SKIP_REALITY=1 asked to skip it" -ForegroundColor Yellow
} else {
foreach ($fn in @($real.Keys)) { Set-Item -Path ("function:" + $fn) -Value $real[$fn] }
$rp = $null; $rThrew = $null
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try { $rp = Get-HordeProjection -HostPort (New-HordeUnavailableHostPort -Reason "the reality check runs with no host attached") } catch { $rThrew = $_.Exception.Message }
if ($null -ne $rThrew) { Write-Host ("  the projection threw: " + $rThrew) -ForegroundColor Red }
Check ($null -eq $rThrew -and $null -ne $rp) "the reality check projects this machine's stores without throwing"
if ($null -ne $rp) {
    $recs = @($rp.inputs.wf.registry.records.Keys).Count
    Write-Host ("  " + @($rp.sessions).Count + " sessions, " + $recs + " registry records, " + @($rp.inputs.identity.records.Keys).Count + " control files, " + @($rp.inputs.wf.runs.runs).Count + " runs, " + @($rp.inputs.paneRead.files).Count + " pane-sessions files; " + $sw.ElapsedMilliseconds + " ms") -ForegroundColor DarkGray
    foreach ($k in @($rp.complete.Keys)) { if ($rp.complete[$k].state -ne "known") { Write-Host ("  REPORT: store " + $k + " is incomplete: " + $rp.complete[$k].reason) -ForegroundColor Yellow } }
    foreach ($f in @($rp.faults)) {
        if ((FSt $f) -eq "true") { Write-Host ("  REPORT: fault " + $f.kind + " (" + @($f.found).Count + "): " + ((@($f.found | Select-Object -First 3 | ForEach-Object { $_.detail })) -join " | ")) -ForegroundColor Yellow }
        elseif ((FSt $f) -eq "unknown") { Write-Host ("  REPORT: fault " + $f.kind + " unknown: " + $f.answer.reason) -ForegroundColor DarkGray }
    }
    Check (@($rp.sessions).Count -ge 1 -and $recs -ge 1) ("CONTROL: the reality check read real sessions (" + @($rp.sessions).Count + ") and registry records (" + $recs + ")")
    $rPanes = @($rp.sessions | Where-Object { $_.fields["pane"].answer.state -ne "unknown" })
    Check ($rPanes.Count -eq 0) ("with no host attached, no real pane is known or absent (" + $rPanes.Count + " are)")
    $sw.Restart()
    $rdoc = (ConvertTo-HordeSessionViewDocument $rp) | ConvertTo-Json -Depth 40 | ConvertFrom-Json
    $rsf = @(Test-HordeSchema -Value $rdoc -Schema $viewSchema)
    foreach ($x in @($rsf | Select-Object -First 10)) { Write-Host ("  " + $x) -ForegroundColor Red }
    Check ($rsf.Count -eq 0) ("the real view validates against schema/session-view.v1 (" + $sw.ElapsedMilliseconds + " ms)")
    $rrf = @(Test-HordeSessionViewRules -Document $rdoc)
    foreach ($x in @($rrf | Select-Object -First 10)) { Write-Host ("  " + $x) -ForegroundColor Red }
    Check ($rrf.Count -eq 0) "the real view keeps the rules the schema cannot state"
}

}

Complete-HordeSuite -Success "one read-only view of the Horde, every field an answer with its source, and nothing written"
