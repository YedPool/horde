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
#   01 warchief, handle 10    02 orc under 01, handle 11    03 warg in run alpha, handle 12
#   04 stopped, handle 13 gone  05 retired, handle 14         06 running, record retired
#   07 08 09 all claim handle 16 (08 is shaped like the stray 11111111-... record)
#   10 no record, pane-sessions file 17 and a claim for 17    11 holds 18; 12's file hijacks 18
#   13 named by files 19 and 20   codex-thread-1 a codex session with a non-UUID id
#   15 fleet id in two open runs  16 in two closed runs  17 pending  18 orphaned  19 gone but active
#   20 done  21 parent missing  22 parent retired  23 24 label held twice  25 orc under 03
#   26 27 one fleet id  28 29 a parent loop  30 another instance  31 written before the instance
#   32 resumed by two processes  33 resumed by one  34 known only from a report

# -Section: run only these sections (see SECTIONS below); HORDE_SECTIONS does the same.
param([string[]]$Section = @())

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
. (Join-Path $root "core\JsonText.ps1")

# SECTIONS (PR #31, 2026-10-01). A mutation spec names the sections that kill its mutants, so each
# mutant runs only those: HORDE_SECTIONS="pane,runs" (tools\Mutate.ps1 passes HORDE_* variables) or
# -Section pane,runs. The shared fixture views are built whatever is selected. A name this suite does
# not have fails the run, so a typo cannot select nothing and pass; and a run that skipped a section
# exits 3, as a skipped reality check does, so it is never a gate's pass.
$script:sectionIds = @("view", "scope", "ended", "membership", "precedence", "pane", "hostport", "stored-handle", "instance-proven", "instance-whole", "platform", "one-writer", "judge", "pane-guard", "claim-guard", "carry", "cannot-tell", "holes", "runs", "cardinality", "parity", "silent-winner", "one-agent", "layout", "schema", "writes", "reality")
$script:sectionsWanted = @()
if (@($Section).Count -gt 0) { $script:sectionsWanted = @($Section | ForEach-Object { "$_" -split "," } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }) }
elseif ("$env:HORDE_SECTIONS".Trim() -ne "") { $script:sectionsWanted = @("$env:HORDE_SECTIONS" -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }) }
$script:sectionsSkipped = New-Object System.Collections.ArrayList
$script:sectionsUnknown = @($script:sectionsWanted | Where-Object { $script:sectionIds -cnotcontains $_ })
function Section {
    # Print the section's header; say whether it runs.
    param([string]$Id, [string]$Title)
    if ($script:sectionIds -cnotcontains $Id) { throw ("not a section of this suite: " + $Id) }
    Write-Host ""
    Write-Host ("--- " + $Title + " ---") -ForegroundColor Cyan
    if ($script:sectionsWanted.Count -eq 0 -or $script:sectionsWanted -ccontains $Id) { return $true }
    [void]$script:sectionsSkipped.Add($Id)
    Write-Host ("  [SKIP] section " + $Id + " was not selected") -ForegroundColor Yellow
    return $false
}
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
foreach ($fn in @("Get-HordeProcessTable", "Read-HordeWindowsProcessTable", "Get-HordeClaudeSessionsDir", "Get-HordeClaudeProjectsDir",
                  "Get-HordeCodexSessionsDir", "Get-HordePaneSessionsDir", "Get-HordeWezfleetRoot")) { $real[$fn] = (Get-Item ("function:" + $fn)).ScriptBlock }
function Get-HordeProcessTable { [void]$script:trips.Add("process table"); return (New-HordeUnknown -Reason "TRIP: the real process table was asked for") }
function Read-HordeWindowsProcessTable { [void]$script:trips.Add("process table with command lines"); return (New-HordeUnknown -Reason "TRIP: the real process table was asked for") }
function Get-HordeClaudeSessionsDir { [void]$script:trips.Add("claude sessions"); return (Join-Path $env:TEMP ("horde-projection-trip-" + [guid]::NewGuid().ToString("N"))) }
function Get-HordeClaudeProjectsDir { [void]$script:trips.Add("claude projects"); return (Join-Path $env:TEMP ("horde-projection-trip-" + [guid]::NewGuid().ToString("N"))) }
function Get-HordeCodexSessionsDir { [void]$script:trips.Add("codex sessions"); return (Join-Path $env:TEMP ("horde-projection-trip-" + [guid]::NewGuid().ToString("N"))) }
function Get-HordePaneSessionsDir { [void]$script:trips.Add("pane-sessions"); return (Join-Path $env:TEMP ("horde-projection-trip-" + [guid]::NewGuid().ToString("N"))) }
function Get-HordeWezfleetRoot { [void]$script:trips.Add("wezfleet root"); return (Join-Path $env:TEMP ("horde-projection-trip-" + [guid]::NewGuid().ToString("N"))) }

$fx = Join-Path $root "test\fixtures\projection\fleet"
$work = Join-Path $env:TEMP ("horde-projection-" + [guid]::NewGuid().ToString("N"))
$script:copies = 0
$timesDoc = ConvertFrom-HordeJson -Text (Get-Content -LiteralPath (Join-Path $fx "times.json") -Raw)
$now = [datetime]::Parse($timesDoc.now, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
$ownership = ConvertFrom-HordeJson -Text (Get-Content -LiteralPath (Join-Path $root "core\ownership.json") -Raw)
$viewSchema = Get-HordeSchema -Name "session-view.v1"

function Sid { param([int]$N) return ("aaaaaaaa-0000-4000-8000-" + $N.ToString("000000000000")) }
function Utc { param([string]$Text) return [datetime]::Parse($Text, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime() }
function Encoding { return (New-Object System.Text.UTF8Encoding($false)) }
function PutJson { param([string]$Path, $Obj) [System.IO.File]::WriteAllText($Path, ($Obj | ConvertTo-Json -Depth 12), (Encoding)) }
function PutText { param([string]$Path, [string]$Text) [System.IO.File]::WriteAllText($Path, $Text, (Encoding)) }
function ReadJson { param([string]$Path) return (ConvertFrom-HordeJson -Text (Get-Content -LiteralPath $Path -Raw)) }

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
    param([string]$D, $Running = $null, $Id = $null, [switch]$Ambiguous, [string[]]$Add = @(), [switch]$NoHandles, [hashtable]$Caps = @{}, [string[]]$Stores = @("W1", "W2", "W4", "W5", "X1"))
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
    # The fake is the host that wrote the legacy stores, unless a test says otherwise.
    return (New-HordeHostPort -Name "fake" -Capabilities $capTable -StoredHandles $Stores -Handles $handlesBlock -Instance $instanceBlock)
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
    # -Platform reads the table through that platform, in the projection's own read order, instead of
    # handing it a table.
    param([string]$D, $HostPort = $null, $Processes = $null, $Layout = $null, [string]$Scope = "All", $Platform = $null)
    if ($null -eq $HostPort) { $HostPort = HostOf $D }
    if ($null -eq $Processes -and $null -eq $Platform) { $Processes = ProcsOf $D }
    if ($null -eq $Layout) { $Layout = LayoutOf $D }
    $table = @{ Processes = $Processes }
    if ($null -ne $Platform) { $table = @{ Platform = $Platform } }
    return (Get-HordeProjection -WezfleetRoot (Join-Path $D "wezfleet") -ClaudeDir (Join-Path $D "agent\sessions") -ProjectsDir (Join-Path $D "agent\projects") `
        -CodexDir (Join-Path $D "wezfleet\codex-sessions") -PaneSessionsDir (Join-Path $D "agent\pane-sessions") @table -HostPort $HostPort `
        -LayoutPort $Layout -TtlSeconds 900 -Now $now -Scope $Scope)
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

# THE NODE'S FIXTURES (sections ended and membership): a node's stores are control files under
# agent\sessions and only the store a case needs; its process table is given.
$agentImage = "$(@(ReadJson (Join-Path $fx 'processes.json'))[0].name)"
$nodeDevice = "0f8fad5b-d9cb-469f-a165-70867728950e"
function NodeFleet {
    # A node's stores: control files under agent\sessions, an empty projects folder, nothing else.
    param([string]$Name, [object[]]$Files)
    $script:copies++
    $d = Join-Path $work ($Name + "-" + $script:copies)
    New-Item -ItemType Directory -Path (Join-Path $d "agent\sessions") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $d "agent\projects") -Force | Out-Null
    foreach ($f in $Files) { PutJson (Join-Path $d ("agent\sessions\" + $f.pid + ".json")) $f }
    return $d
}
function ControlFile {
    # One control file; -Created $null writes no procStart, so its process cannot be checked.
    param([int]$ProcId, [int]$N, $Created)
    $o = [ordered]@{ pid = $ProcId; sessionId = (Sid $N); cwd = "C:\work\node"; startedAt = 1780304405000 }
    if ($null -ne $Created) { $o["procStart"] = "" + ([datetime]$Created).ToFileTimeUtc() }
    $o["version"] = "9.9.9"; $o["kind"] = "interactive"; $o["entrypoint"] = "cli"; $o["status"] = "idle"; $o["statusUpdatedAt"] = 1780315160000
    return [pscustomobject]$o
}
function Proc { param([int]$ProcId, $Created, $CommandLine = "harness-a", [string]$Name = $agentImage) return [pscustomobject]@{ pid = $ProcId; name = $Name; created = $Created; commandLine = $CommandLine } }
function Table { param([object[]]$Rows, $At = $null) $t = @{}; foreach ($r in $Rows) { $t[[int]$r.pid] = $r }; return (New-HordeKnown -Value $t -ObservedAt $At) }
function NodeProject { param([string]$D, $Processes, $HostPort = $null, $Platform = $null) if ($null -eq $HostPort) { $HostPort = New-HordeUnavailableHostPort -Reason "the node has no host adapter" }; return (Project $D -HostPort $HostPort -Processes $Processes -Platform $Platform -Layout { return , @() }) }
function NodeIds { param($P) return @($P.sessions | ForEach-Object { "$($_.sessionId)" }) }
function Served { param([string]$D, $Processes, $HostPort = $null) return @(NodeIds (Remove-HordeEndedSessions -Projection (NodeProject $D $Processes $HostPort))) }
function Reg {
    # A registry record for session N, the fixture's session 04 re-keyed: every member holding 04's id
    # now holds N's. -Set adds or replaces members.
    param([string]$D, [int]$N, [hashtable]$Set = @{})
    $regDir = Join-Path $D "wezfleet\registry\sessions"; New-Item -ItemType Directory -Path $regDir -Force | Out-Null
    $rec = ReadJson (Join-Path $fx ("wezfleet\registry\sessions\" + (Sid 4) + ".json"))
    foreach ($pp in @($rec.PSObject.Properties)) { if ("$($pp.Value)" -ceq (Sid 4)) { $pp.Value = (Sid $N) } }
    $rec.parent = ""
    foreach ($k in $Set.Keys) { $rec | Add-Member -NotePropertyName $k -NotePropertyValue $Set[$k] -Force }
    PutJson (Join-Path $regDir ((Sid $N) + ".json")) $rec
}
function FakeHost {
    # A host whose one instance started at -Started and lists -Live handles; it wrote the stored handles.
    param([string[]]$Live, [datetime]$Started)
    $rows = @($Live | ForEach-Object { [pscustomobject]@{ handle = $_; window = "1"; tab = "1"; hostTitle = "t" } })
    $inst = [pscustomobject]@{ id = "inst-n"; startedAt = $Started; running = 1; ambiguous = $false }
    return (New-HordeHostPort -Name "fake" -Capabilities @{ "list" = "yes"; "instance.startedAt" = "yes"; "text.read" = "unverified" } -StoredHandles @("W1", "W2", "W4", "W5", "X1") -Handles ({ return , $rows }.GetNewClosure()) -Instance ({ return $inst }.GetNewClosure()))
}

try {
New-Item -ItemType Directory -Path $work -Force | Out-Null
Check ($script:sectionsUnknown.Count -eq 0) ("every section asked for exists (unknown: " + ($script:sectionsUnknown -join ", ") + ")")

Write-Host ""
Write-Host "--- loading the module ---" -ForegroundColor Cyan
$strictKept = & { Set-StrictMode -Version Latest; . (Join-Path $root "core\Projection.ps1"); try { $null = $hordeNeverAssignedVariable; $false } catch { $true } }
Check ($strictKept -eq $true) "dot-sourcing core/projection leaves the caller's strict mode on"

# THE SHARED FIXTURE VIEWS, built whatever sections run: several sections read them.
$base = New-Fleet "base"
$p = Project $base
$required = @($ownership.required | ForEach-Object { "$_" })
$pu = Project $base -HostPort (New-HordeUnavailableHostPort -Reason "the fixture's host is switched off")

if (Section "view" "the view over the fixture") {
    $ids = @($p.sessions | ForEach-Object { $_.sessionId })
    Check ($ids.Count -eq 34) ("CONTROL: the fixture's 34 sessions are all in the view (" + $ids.Count + ")")
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

}

# Early on purpose: a mutant of the scope is caught here within seconds under fail-fast, instead of
# after every other section (60 minutes for eight of them on the always-on box, 2026-10-02).
if (Section "scope" "the current scope (core/Projection.ps1 header, SCOPE)") {
    # One session's entry of a view document as text, by id, so two scopes compare field for field.
    function ScopeDoc { param($P) $d = ConvertFrom-HordeJson -Text ((ConvertTo-HordeSessionViewDocument $P) | ConvertTo-Json -Depth 40); $m = @{}; foreach ($x in @($d.sessions)) { $m["" + $x.sessionId] = ($x | ConvertTo-Json -Depth 40 -Compress) }; return [pscustomobject]@{ doc = $d; byId = $m } }
    function ScopeDiff { param($All, $Cur) return @($Cur.byId.Keys | Where-Object { -not $All.byId.ContainsKey($_) -or $All.byId[$_] -cne $Cur.byId[$_] }) }
    # A report-only session of the closed run gamma1: fleet id omega, one report, and with -Pane the
    # handle that report names, written after this instance started.
    function AddReportOnly { param([string]$D, $Pane = $null)
        $runDir = Join-Path $D "wezfleet\other\runs\20260501-080000-gamma1"
        $ro = ReadJson (Join-Path $runDir "roster.json")
        $ro.sessions = @($ro.sessions) + @([pscustomobject]@{ id = "omega"; title = "omega"; cwd = "C:\work"; dependsOn = @(); spawned = $true; spawnedAt = "2026-05-01T12:00:00.0000000Z" })
        PutJson (Join-Path $runDir "roster.json") $ro
        $sd = Join-Path $runDir "sessions\omega"; New-Item -ItemType Directory -Path $sd -Force | Out-Null
        $sess = [ordered]@{ id = "omega"; claudeSessionId = (Sid 35); transcriptPath = ""; idSource = ""; cwd = "C:\work"; pid = 1 }
        if ($null -ne $Pane) { $sess["pane"] = $Pane }
        $ev = [ordered]@{ ts = "2026-06-01T11:30:00.0000000Z"; seq = 1; event = "done"; summary = "finished"; session = $sess; question = ""; resumeCommand = "" }
        PutText (Join-Path $sd "events.jsonl") (($ev | ConvertTo-Json -Depth 5 -Compress) + "`n")
    }
    function IsCurrent { param([string]$D, $N) return (Has (Project $D -Scope Current) $N) }

    $pcur = Project $base -Scope Current
    $dAll = ScopeDoc $p; $dCur = ScopeDoc $pcur
    $curIds = @($pcur.sessions | ForEach-Object { $_.sessionId })
    Check ($curIds.Count -eq 33 -and -not (Has $pcur 5) -and (Has $p 5)) ("the current scope leaves out the fixture's one historical session, 05: a retired record and nothing else (" + $curIds.Count + " current)")
    $scopeBad = @(ScopeDiff $dAll $dCur)
    foreach ($x in $scopeBad) { Write-Host ("  differs from All: " + $x) -ForegroundColor Red }
    Check ($scopeBad.Count -eq 0) "every field of every current session is identical to its field under All"
    Check (($dCur.doc.handles | ConvertTo-Json -Depth 20 -Compress) -ceq ($dAll.doc.handles | ConvertTo-Json -Depth 20 -Compress)) "the handle rows are identical under both scopes"
    Check ("$($dCur.doc.scope)" -ceq "current" -and $null -eq $dAll.doc.PSObject.Properties["scope"]) "a current view says it is one, and a whole view says nothing"
    Check (@(Test-HordeSchema -Value $dCur.doc -Schema $viewSchema).Count -eq 0 -and @(Test-HordeSessionViewRules -Document $dCur.doc).Count -eq 0) "a current view validates"
    $prc = Fault $pcur "parent-retired"
    Check ((FSt $prc) -eq "true" -and (Subjects $prc) -contains (Sid 22) -and (Subjects $prc) -contains (Sid 5)) "a fault that reads the registry still finds the historical session it collides with"

    $ronly = New-Fleet "scope-report-only"; AddReportOnly $ronly
    $pro = Project $ronly
    Check ((Has $pro 35) -and (Src (Ans $pro 35 "sessionId")) -eq "W5" -and (St (Ans $pro 35 "pane")) -eq "absent" -and -not (IsCurrent $ronly 35)) "a report-only session of a closed run is historical"

    # Each live signal on its own makes the historical session 05 current.
    $sg = New-Fleet "scope-running"
    PutJson (Join-Path $sg "processes.json") (@(ReadJson (Join-Path $sg "processes.json")) + @([pscustomobject]@{ pid = 1301; name = "harness-a.exe"; created = "2026-06-01T11:40:00.0000000Z"; commandLine = ("harness-a --resume " + (Sid 5)) }))
    Check (IsCurrent $sg 5) "signal 1: a process that resumes a session makes it current"
    $sg = New-Fleet "scope-live-record"
    EditReg $sg 5 { param($r) $r.retired = $false }
    Check (IsCurrent $sg 5) "signal 2: a registry record that is not retired makes a session current"
    $sg = New-Fleet "scope-torn-record"
    PutText (RegPath $sg 5) "{ torn"
    Check (IsCurrent $sg 5) "signal 2: a registry record that cannot be read makes a session current, since it may be live"
    $sg = New-Fleet "scope-open-run"
    EditReg $sg 5 { param($r) $r.fleetSessionId = "alpha" }
    Check (IsCurrent $sg 5) "signal 3: a fleet id an open run lists makes a session current"
    $sg = New-Fleet "scope-control-file"
    $cf = ReadJson (Join-Path $sg "agent\sessions\1003.json"); $cf.pid = 1999; $cf.sessionId = (Sid 5); PutJson (Join-Path $sg "agent\sessions\1999.json") $cf
    Check (IsCurrent $sg 5) "signal 4: a control file that names a session makes it current, running or not"
    $cx = ReadJson (Join-Path $sg "wezfleet\codex-sessions\codex-thread-1.json"); $cx.sessionId = (Sid 5); PutJson (Join-Path $sg ("wezfleet\codex-sessions\" + (Sid 5) + ".json")) $cx
    Check (IsCurrent $sg 5) "signal 4: two control files that name a session make it current, though neither is kept"
    $sg = New-Fleet "scope-pane-file"
    $pf = ReadJson (Join-Path $sg "agent\pane-sessions\17.json"); $pf.session_id = (Sid 5); $pf30 = Join-Path $sg "agent\pane-sessions\30.json"; PutJson $pf30 $pf; [System.IO.File]::SetLastWriteTimeUtc($pf30, $now.AddMinutes(-10))
    Check (IsCurrent $sg 5) "signal 4: a pane-sessions file that passes the guard makes a session current"
    $sg = New-Fleet "scope-stale-pane-file"
    $pf = ReadJson (Join-Path $sg "agent\pane-sessions\17.json"); $pf.session_id = (Sid 5); $pf30 = Join-Path $sg "agent\pane-sessions\30.json"; PutJson $pf30 $pf; [System.IO.File]::SetLastWriteTimeUtc($pf30, $now.AddHours(-3))
    Check (-not (IsCurrent $sg 5)) "CONTROL: a pane-sessions file written before this instance started does not"
    $sg = New-Fleet "scope-live-handle"; AddReportOnly $sg -Pane 30
    $psg = Project $sg; $psgC = Project $sg -Scope Current
    Check ((Val (Ans $psg 35 "pane")) -eq "30" -and (Has $psgC 35) -and @(ScopeDiff (ScopeDoc $psg) (ScopeDoc $psgC)).Count -eq 0) "signal 5: a stored handle live in this instance makes a finished session current, and both scopes agree on it"
    # One reading completed twice sees one set of live-file facts: its snapshot (the header's SCOPE).
    $snf = New-Fleet "scope-snapshot"
    $psn = Project $snf
    [System.IO.File]::SetLastWriteTimeUtc((Join-Path $snf ("agent\projects\C--work-gamma\" + (Sid 3) + ".jsonl")), $now.AddSeconds(-5))
    $psn2 = Complete-HordeProjection -C $psn.inputs -Scope Current
    Check ((Val (Ans $psn 3 "lastActivity")) -like "2026-06-01T11:59:40*" -and (Val (Ans $psn2 3 "lastActivity")) -like "2026-06-01T11:59:40*" -and (Val (Ans (Project $snf) 3 "lastActivity")) -like "2026-06-01T11:59:55*") "one reading completed twice sees one set of live-file facts, and a fresh reading sees the new one"
}

if (Section "ended" "a node lists no session whose end is proven (core/Projection.ps1, ConvertTo-HordeNodeViewDocument)") {
    # THE ALWAYS-ON NODE, 2026-10-13: the hub said "2 session(s)" for a node where none ran. That node
    # has the agent's control files and nothing else - no wezfleet stores, no host adapter - and a
    # session whose pane was ended leaves its control file behind. The fixtures are that node: control
    # files, a process table, and only the store a case needs. Only a death the process table PROVES
    # leaves a session out, and only when nothing else may say it is live; every other session stays
    # listed with its reason (ledger core-projection L-100; Get-HordeSessionEndProof's rules, each with
    # a case that keeps the session and, where the rule can be isolated, a control that drops it).
    $t0 = Utc "2026-06-01T05:00:00.0000000Z"
    $t1 = Utc "2026-06-01T09:00:00.0000000Z"
    $t2 = Utc "2026-06-01T10:00:00.0000000Z"
    # 41 live; 42 gone; 43 its pid now another program's; 44 no procStart, so unknown; 45 gone, but a
    # process resumes it.
    $nd = NodeFleet "ended-node" @((ControlFile 3001 41 $t1), (ControlFile 3002 42 $t1), (ControlFile 3003 43 $t1), (ControlFile 3004 44 $null), (ControlFile 3005 45 $t1))
    $ntab = Table @((Proc 3001 $t1), (Proc 3003 $t2 "svc -k" "other.exe"), (Proc 3004 $t1 "svc" "other.exe"), (Proc 3105 $t2 ("harness-a --resume " + (Sid 45)) "harness-a.exe"))
    $nAll = NodeProject $nd $ntab
    Check ((@(NodeIds $nAll) -join ",") -ceq ((@(41, 42, 43, 44, 45) | ForEach-Object { Sid $_ }) -join ",")) "CONTROL: the whole projection holds all five sessions its control files name, as the node served them before"
    $nLive = Remove-HordeEndedSessions -Projection $nAll
    $nIds = @(NodeIds $nLive)
    Check ($nIds -notcontains (Sid 42)) "a session whose process is gone is not listed by the node"
    Check ($nIds -notcontains (Sid 43)) "a session whose pid now runs another program is not listed"
    Check ($nIds -contains (Sid 44) -and (St (Ans $nLive 44 "liveStatus")) -eq "unknown" -and (Why (Ans $nLive 44 "liveStatus")) -like "*procStart*") "a session whose liveness is unknown is still listed, with its unknown reason"
    Check ($nIds -contains (Sid 41) -and (Val (Ans $nLive 41 "liveStatus")) -eq "idle") "CONTROL: a live session is still listed"
    Check ($nIds -contains (Sid 45)) "a stale session is still listed while a process resumes it"
    Check ($nIds.Count -eq 3) ("only the two proven ended are left out (" + ($nIds -join ", ") + ")")
    $endedBy = @{}; foreach ($e in @($nLive.ended)) { $endedBy[$e.sessionId] = $e.reason }
    Check ($endedBy.Count -eq 2 -and "$($endedBy[(Sid 42)])" -like "*3002 is not running*" -and "$($endedBy[(Sid 43)])" -like "*3003 was reused*") "each session left out is named with its proof"
    $sameFields = @($nLive.sessions | Where-Object { $s = $_; $o = @($nAll.sessions | Where-Object { $_.sessionId -ceq $s.sessionId })[0]; ($s.fields | ConvertTo-Json -Depth 12 -Compress) -cne ($o.fields | ConvertTo-Json -Depth 12 -Compress) })
    Check ($sameFields.Count -eq 0) "a session the node keeps is carried exactly as the whole projection has it"
    Check ((@(NodeIds $nAll) -join ",") -ceq ((@(41, 42, 43, 44, 45) | ForEach-Object { Sid $_ }) -join ",")) "leaving sessions out changes nothing in the projection it was given"
    $vdoc = ConvertFrom-HordeJson -Text ((ConvertTo-HordeSessionViewDocument $nLive) | ConvertTo-Json -Depth 40)
    Check (@(Test-HordeSchema -Value $vdoc -Schema $viewSchema).Count -eq 0 -and @(Test-HordeSessionViewRules -Document $vdoc).Count -eq 0) "the node's view without them still validates"

    # One stale file, 42, and the rules one at a time. Its control: the table whole, nothing else.
    $one = @((ControlFile 3002 42 $t1))
    $quiet = @((Proc 3001 $t0))
    Check (@(Served (NodeFleet "ended-one" $one) (Table $quiet)).Count -eq 0) "CONTROL: one stale file, the table whole and no other store, is left out"
    # ONLY gone AND reused ARE PROOF: a table that cannot be read, or one with no start time for the pid.
    Check ((@(Served (NodeFleet "ended-no-table" $one) (New-HordeUnknown -Reason "the process table could not be read")) -join ",") -ceq (Sid 42)) "a session is still listed when the process table cannot be read: its end is not proven"
    Check ((@(Served (NodeFleet "ended-no-start" $one) (Table @((Proc 3002 $null "svc" "other.exe")))) -join ",") -ceq (Sid 42)) "a session is still listed when the table gives no start time for its pid: its end is not proven"
    # REUSED BY THE AGENT ITSELF: around a clock change CIM's local start time converts an hour off.
    Check ((@(Served (NodeFleet "ended-reused-agent" $one) (Table @((Proc 3002 $t1.AddHours(-2))))) -join ",") -ceq (Sid 42)) "a session whose pid runs an agent process with another start time is still listed: it may be the same process read an hour off"
    Check ((@(Served (NodeFleet "ended-reused-host" $one) (Table @((Proc 3002 $t1.AddHours(-2) "host-a" "node.exe")))) -join ",") -ceq (Sid 42)) "a session whose pid runs a process of the agent's host image with another start time is still listed"
    # THE LISTING IS WHOLE: a half-written control file may be this session resumed under a new pid.
    $hw = NodeFleet "ended-half-written" $one
    PutText (Join-Path $hw "agent\sessions\3102.json") ('{"pid":3102,"sessionId":"' + (Sid 42) + '","cw')
    $hwP = NodeProject $hw (Table $quiet)
    Check ($hwP.complete["X2"].state -eq "unknown" -and (@(NodeIds (Remove-HordeEndedSessions -Projection $hwP)) -join ",") -ceq (Sid 42)) "a half-written control file makes the listing unknown, and the stale one is still listed"
    # THE FILE IS OLDER THAN THE TABLE: a session started after the table was read has no row yet.
    Check ((@(Served (NodeFleet "ended-race" $one) (Table $quiet -At $t1.AddMinutes(-1))) -join ",") -ceq (Sid 42)) "a control file whose process started after the process table was read is still listed"
    Check (@(Served (NodeFleet "ended-race-control" $one) (Table $quiet -At $t1.AddMinutes(1))).Count -eq 0) "CONTROL: the same file, the table read after its process started, is left out"
    # The same race through the projection's own read order: a session starts WHILE the table is read,
    # so its pid is not in the table, and its file is written before the files are listed. The read
    # time is the one taken before the read, never after it.
    $rr = NodeFleet "ended-race-read" @()
    $rrFile = Join-Path $rr "agent\sessions\3007.json"
    $rrText = ((ControlFile 3007 47 $t1) | ConvertTo-Json -Depth 5)
    $rrReader = {
        Start-Sleep -Milliseconds 40
        $mid = [datetime]::UtcNow
        [System.IO.File]::WriteAllText($rrFile, $rrText.Replace(("" + $t1.ToFileTimeUtc()), ("" + $mid.ToFileTimeUtc())))
        Start-Sleep -Milliseconds 40
        $tb = @{}; $tb[3300] = [pscustomobject]@{ pid = 3300; name = "other.exe"; created = $t0; commandLine = "svc" }
        return $tb
    }.GetNewClosure()
    $rrP = NodeProject $rr $null -Platform (New-HordePlatform -Name "windows" -ProcessSpace "windows" -ProcessTable $rrReader)
    Check ("$($rrP.inputs.identity.records[(Sid 47)].processCheck)" -ceq "gone" -and (@(NodeIds (Remove-HordeEndedSessions -Projection $rrP)) -join ",") -ceq (Sid 47)) "a session started while the process table was being read is still listed: the read time is taken before the read"
    # NO PROCESS OF THE AGENT IS UNREAD.
    Check ((@(Served (NodeFleet "ended-unread" $one) (Table @((Proc 3200 $t0 $null)))) -join ",") -ceq (Sid 42)) "a stale session is still listed while an agent process's command line cannot be read"
    Check ((@(Served (NodeFleet "ended-unread-host" $one) (Table @((Proc 3200 $t0 $null "node.exe")))) -join ",") -ceq (Sid 42)) "a stale session is still listed while a host-image process's command line cannot be read"
    Check (@(Served (NodeFleet "ended-unread-control" $one) (Table @((Proc 3200 $t0 "x" "node.exe")))).Count -eq 0) "CONTROL: the same host-image process with its command line read does not keep it"
    # NO UNACCOUNTED AGENT PROCESS: one that no control file verifies, started after the stale one.
    Check ((@(Served (NodeFleet "ended-orphan" $one) (Table @((Proc 3300 $t2)))) -join ",") -ceq (Sid 42)) "a stale session is still listed while an agent process with no control file started after it"
    Check ((@(Served (NodeFleet "ended-orphan-nostart" $one) (Table @((Proc 3300 $null)))) -join ",") -ceq (Sid 42)) "a stale session is still listed while an agent process with no control file has no start time"
    Check (@(Served (NodeFleet "ended-orphan-control" $one) (Table @((Proc 3300 $t0)))).Count -eq 0) "CONTROL: an agent process with no control file that started hours before does not keep it"
    Check ((@(Served (NodeFleet "ended-orphan-host" $one) (Table @((Proc 3300 $t2 "host-a --continue" "node.exe")))) -join ",") -ceq (Sid 42)) "a stale session is still listed while a host-image process that no control file verifies started after it: the agent may run inside it"
    Check (@(Served (NodeFleet "ended-orphan-host-control" $one) (Table @((Proc 3300 $t0 "host-a --continue" "node.exe")))).Count -eq 0) "CONTROL: a host-image process that no control file verifies and that started hours before does not keep it"
    # THE OTHER STORES ARE WHOLE when wezfleet's root exists.
    $mn = NodeFleet "ended-misnamed" $one
    Reg $mn 42; Move-Item -LiteralPath (Join-Path $mn ("wezfleet\registry\sessions\" + (Sid 42) + ".json")) -Destination (Join-Path $mn ("wezfleet\registry\sessions\" + (Sid 99) + ".json"))
    Check ((@(Served $mn (Table $quiet)) -join ",") -ceq (Sid 42)) "a stale session is still listed while a registry record under another file name may be its own"
    $ul = NodeFleet "ended-runs-unlisted" $one
    New-Item -ItemType Directory -Path (Join-Path $ul "wezfleet\registry\sessions") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $ul "wezfleet\repo\runs\20260601-100000-r1") -Force | Out-Null
    PutJson (Join-Path $ul "wezfleet\repo\runs\20260601-100000-r1\run.json") ([pscustomobject]@{ closedAt = "2026-06-01T11:00:00Z" })
    $ulP = NodeProject $ul (Table $quiet)
    Check (($ulP.complete["W4"].state -ne "known" -or $ulP.complete["W3"].state -ne "known") -and (@(NodeIds (Remove-HordeEndedSessions -Projection $ulP)) -join ",") -ceq (Sid 42)) "a stale session is still listed while a run's roster cannot be read"
    $wc = NodeFleet "ended-wezfleet-whole" $one
    New-Item -ItemType Directory -Path (Join-Path $wc "wezfleet\registry\sessions") -Force | Out-Null
    Check (@(Served $wc (Table $quiet)).Count -eq 0) "CONTROL: a wezfleet root whose stores are whole does not keep it"
    # NO OTHER SIGNAL, one fixture each (ledger L-100's list).
    $rg = NodeFleet "ended-registry" $one; Reg $rg 42
    Check ((@(Served $rg (Table $quiet)) -join ",") -ceq (Sid 42)) "a stale session is still listed while its registry record is not retired"
    $rr = NodeFleet "ended-registry-retired" $one; Reg $rr 42 @{ retired = $true }
    Check (@(Served $rr (Table $quiet)).Count -eq 0) "CONTROL: a retired registry record does not keep it"
    $ru = NodeFleet "ended-registry-unreadable" $one
    New-Item -ItemType Directory -Path (Join-Path $ru "wezfleet\registry\sessions") -Force | Out-Null
    PutText (Join-Path $ru ("wezfleet\registry\sessions\" + (Sid 42) + ".json")) "{ torn"
    Check ((@(Served $ru (Table $quiet)) -join ",") -ceq (Sid 42)) "a stale session is still listed while its registry record cannot be read"
    foreach ($closed in @($false, $true)) {
        $or = NodeFleet "ended-run" $one; Reg $or 42 @{ retired = $true; fleetSessionId = "f42" }
        $rd = Join-Path $or "wezfleet\repo\runs\20260601-100000-r1"; New-Item -ItemType Directory -Path $rd -Force | Out-Null
        $man = [ordered]@{ runId = "20260601-100000-r1" }; if ($closed) { $man["closedAt"] = "2026-06-01T11:00:00.0000000Z" }
        PutJson (Join-Path $rd "run.json") ([pscustomobject]$man)
        PutJson (Join-Path $rd "roster.json") ([pscustomobject]@{ sessions = @([pscustomobject]@{ id = "f42"; title = "f42"; cwd = "C:\work\node"; dependsOn = @(); spawned = $true; spawnedAt = "2026-06-01T09:00:00.0000000Z" }) })
        $orIds = @(Served $or (Table $quiet))
        if ($closed) { Check ($orIds.Count -eq 0) "CONTROL: the same run closed does not keep it" }
        else { Check (($orIds -join ",") -ceq (Sid 42)) "a stale session is still listed while a run that lists it is open" }
    }
    Check ((@(Served (NodeFleet "ended-duplicate" @((ControlFile 3002 42 $t1), (ControlFile 3012 42 $t1))) (Table $quiet)) -join ",") -ceq (Sid 42)) "a session two stale control files name is still listed: a duplicate is not a proof"
    # An agent that writes no pid: the fixture's one session whose agent is not session 01's, found
    # through the shared view rather than named, with its control folder copied as the fixture has it.
    $noPid = @($p.inputs.identity.records.Values | Where-Object { "$($_.fields.agent.value)" -cne "$(Val (Ans $p 1 'agent'))" })[0]
    $noPidDir = Split-Path -Leaf (Split-Path -Parent $noPid.source)
    $np = NodeFleet "ended-no-pid" $one
    New-Item -ItemType Directory -Path (Join-Path $np "wezfleet\registry\sessions") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $np ("wezfleet\" + $noPidDir)) -Force | Out-Null
    Copy-Item -LiteralPath $noPid.source -Destination (Join-Path $np ("wezfleet\" + $noPidDir + "\" + (Split-Path -Leaf $noPid.source)))
    $npP = NodeProject $np (Table $quiet)
    Check ("$($npP.inputs.identity.records[$noPid.sessionId].processCheck)" -ceq "unchecked" -and (@(NodeIds (Remove-HordeEndedSessions -Projection $npP)) -join ",") -ceq $noPid.sessionId) "a session of an agent that writes no pid (processCheck unchecked) is still listed, while the stale file beside it is left out"
    # A guarded pane-sessions file names it: written in this host instance, for a live handle.
    $started = $t1.AddHours(1)
    $pf = NodeFleet "ended-pane-file" $one
    New-Item -ItemType Directory -Path (Join-Path $pf "agent\pane-sessions") -Force | Out-Null
    $pfj = ReadJson (Join-Path $fx "agent\pane-sessions\17.json"); $pfj.session_id = (Sid 42)
    $pfPath = Join-Path $pf "agent\pane-sessions\21.json"; PutJson $pfPath $pfj; [System.IO.File]::SetLastWriteTimeUtc($pfPath, $started.AddMinutes(30))
    $pfP = NodeProject $pf (Table $quiet) (FakeHost -Live @("21") -Started $started)
    Check ($pfP.inputs.paneVerdicts.bySession.ContainsKey((Sid 42)) -and (@(NodeIds (Remove-HordeEndedSessions -Projection $pfP)) -join ",") -ceq (Sid 42)) "a stale session is still listed while a guarded pane-sessions file names it"
    Check (@(Served $pf (Table $quiet) (FakeHost -Live @("22") -Started $started)).Count -eq 0) "CONTROL: the same file for a handle that is not live does not keep it"
    # A live handle makes its pane known, and nothing else holds: the handle a closed run's roster gave
    # it, written in this instance and live now (a retired record holds no handle).
    $lh = NodeFleet "ended-live-handle" $one
    Reg $lh 42 @{ retired = $true; fleetSessionId = "f42" }
    $lrd = Join-Path $lh "wezfleet\repo\runs\20260601-100000-r1"; New-Item -ItemType Directory -Path $lrd -Force | Out-Null
    PutJson (Join-Path $lrd "run.json") ([pscustomobject]@{ runId = "20260601-100000-r1"; closedAt = "2026-06-01T11:50:00.0000000Z" })
    PutJson (Join-Path $lrd "roster.json") ([pscustomobject]@{ sessions = @([pscustomobject]@{ id = "f42"; title = "f42"; cwd = "C:\work\node"; dependsOn = @(); spawned = $true; spawnedAt = $started.AddMinutes(30).ToString("o"); pane = "22" }) })
    $lhP = NodeProject $lh (Table $quiet) (FakeHost -Live @("22") -Started $started)
    Check ((Val (Ans $lhP 42 "pane")) -eq "22" -and (@(NodeIds (Remove-HordeEndedSessions -Projection $lhP)) -join ",") -ceq (Sid 42)) "a stale session is still listed while a live handle makes its pane known"
    Check (@(Served $lh (Table $quiet) (FakeHost -Live @("23") -Started $started)).Count -eq 0) "CONTROL: the same record's handle not live does not keep it"
    function ClosedRun {
        # A closed run whose roster gives each fleet id a handle, written in this instance.
        param([string]$D, [hashtable]$Panes)
        $crd = Join-Path $D "wezfleet\repo\runs\20260601-100000-r1"; New-Item -ItemType Directory -Path $crd -Force | Out-Null
        PutJson (Join-Path $crd "run.json") ([pscustomobject]@{ runId = "20260601-100000-r1"; closedAt = "2026-06-01T11:50:00.0000000Z" })
        $entries = @($Panes.Keys | Sort-Object | ForEach-Object { [pscustomobject]@{ id = $_; title = $_; cwd = "C:\work\node"; dependsOn = @(); spawned = $true; spawnedAt = $started.AddMinutes(30).ToString("o"); pane = $Panes[$_] } })
        PutJson (Join-Path $crd "roster.json") ([pscustomobject]@{ sessions = $entries })
    }
    # A stale session whose live roster handle another session also claims: its pane is unknown, and
    # the handle still names it.
    $cc = NodeFleet "ended-claimed-twice" $one
    Reg $cc 42 @{ retired = $true; fleetSessionId = "f42" }; Reg $cc 43 @{ retired = $true; fleetSessionId = "f43" }
    ClosedRun $cc @{ f42 = "22"; f43 = "22" }
    $ccP = NodeProject $cc (Table $quiet) (FakeHost -Live @("22") -Started $started)
    Check ((St (Ans $ccP 42 "pane")) -eq "unknown" -and (Has (Remove-HordeEndedSessions -Projection $ccP) 42)) "a stale session is still listed while a live handle it claims is claimed by another session too"
    # The pane-sessions file's co-claimant (review of bcd060c): a stale session's guarded file names live
    # handle 21, and another session's roster entry names 21 too, so its pane is unknown.
    $pc = NodeFleet "ended-pane-file-claimed" $one
    New-Item -ItemType Directory -Path (Join-Path $pc "agent\pane-sessions") -Force | Out-Null
    $pcPath = Join-Path $pc "agent\pane-sessions\21.json"; PutJson $pcPath $pfj; [System.IO.File]::SetLastWriteTimeUtc($pcPath, $started.AddMinutes(30))
    Reg $pc 43 @{ retired = $true; fleetSessionId = "f43" }
    ClosedRun $pc @{ f43 = "21" }
    $pcP = NodeProject $pc (Table $quiet) (FakeHost -Live @("21") -Started $started)
    Check ($pcP.inputs.paneVerdicts.bySession.ContainsKey((Sid 42)) -and (St (Ans $pcP 42 "pane")) -eq "unknown" -and (Has (Remove-HordeEndedSessions -Projection $pcP) 42)) "a stale session is still listed while its guarded pane-sessions file names a live handle another session also claims"

    # WHAT THE NODE SERVES, and what the hub counts. remote/ is loaded in a child scope, so its files
    # do not replace this suite's trip wires.
    $nodeDoc = ConvertTo-HordeNodeViewDocument -Projection $nAll
    # The ended session's agent, from the projection, not from the note under test.
    $agentOf42 = "$(Val (Ans $nAll 42 'agent'))"
    $nodeCmd = Join-Path $root "cli\commands\node.ps1"
    $wire = & {
        . (Join-Path $root "remote\NodeServe.ps1")
        . (Join-Path $root "remote\Mirror.ps1")
        $contract = Get-HordeLinkContract
        $nsn = New-HordeNamespace -Device $nodeDevice -Space "windows"
        $list = Get-HordeNodeSessionList -View $nodeDoc -Namespace $nsn -Contract $contract
        $at = [datetime]::UtcNow
        $mirror = Update-HordeNodeMirror -Mirror (New-HordeNodeMirror -DeviceId $nodeDevice -DeviceName "always-on") -List (ConvertTo-HordeMirrorObject $list) -NodeSentAt $at -ReceivedAt $at
        # session.get over the node's frame handler, after a hello.
        $data = [pscustomobject]@{ manifest = $null; view = $nodeDoc; viewError = ""; journalRoot = ""; namespace = $nsn }
        $st = New-HordeNodeServeState -NodeId $nodeDevice -NodeName "always-on" -HordeVersion "0.1.0"
        $t = Get-HordeLinkTime
        $hello = [pscustomobject][ordered]@{ v = 1; kind = "hello"; id = (New-HordeLinkFrameId); seq = 1; ts = $t; hello = [pscustomobject][ordered]@{ role = "hub"; id = "7c9e6679-7425-40de-944b-e07fc1f90ae7"; name = "fixture-hub"; protocols = @(1); verbsVersions = @(1); hordeVersion = "0.1.0"; t1 = $t } }
        function FrameLine { param($Frame) $b = ConvertTo-HordeFrameBytes -Frame $Frame; return [System.Text.Encoding]::ASCII.GetString($b.bytes, 0, $b.bytes.Length - 1) }
        $null = Invoke-HordeNodeFrame -State $st -Line (FrameLine $hello) -Data $data
        $get = @{}
        foreach ($q in @(@(42, ""), @(41, ""), @(42, $agentOf42), @(42, "another-agent"))) {
            $qa = [ordered]@{ sessionId = (Sid $q[0]) }; if ($q[1] -ne "") { $qa["agent"] = $q[1] }
            $req = [pscustomobject][ordered]@{ v = 1; kind = "req"; id = (New-HordeLinkFrameId); seq = 2; ts = (Get-HordeLinkTime); verb = "session.get"; requestId = (New-HordeLinkFrameId); issuedAt = (Get-HordeLinkTime); args = [pscustomobject]$qa }
            $get["" + $q[0] + "|" + $q[1]] = (Invoke-HordeNodeFrame -State $st -Line (FrameLine $req) -Data $data).reply.result
        }
        # horde node serve's own view block, run as the command runs it, over this projection.
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($nodeCmd, [ref]$null, [ref]$null)
        $assign = @($ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.AssignmentStatementAst] -and "$($a.Left)" -ceq '$getView' }, $true))
        $served = $null
        if ($assign.Count -eq 1) {
            $block = [scriptblock]::Create($assign[0].Right.Expression.ScriptBlock.EndBlock.Extent.Text)
            function Get-HordeProjection { param($Platform) return $nAll }
            $platform = $null
            # The node's own declaration, in a temporary home, of the one store it names sessions from.
            . (Join-Path $root "core\NodePolicy.ps1")
            $hordeHome = Join-Path $work ("node-home-" + [guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Path (Join-Path $hordeHome "node") -Force | Out-Null
            [System.IO.File]::WriteAllText((Get-HordeNodeSessionStoresPath -HordeHome $hordeHome), '{ "schemaVersion": 1, "sessionStores": ["X2"] }', (New-Object System.Text.ASCIIEncoding))
            $served = & $block
        }
        $declared = $null; if ($null -ne $served) { $declared = Get-HordeLinkProp $served "sessionStores" }
        [pscustomobject]@{ ids = @(@($list["sessions"]) | ForEach-Object { "$(Get-HordeLinkProp $_ 'sessionId')" }); listed = (New-HordeFleetNode -Mirror $mirror -Now $at -TtlSeconds 60).listed; get = $get; commandIds = $(if ($null -ne $served) { @(@($served["sessions"]) | ForEach-Object { "$($_['sessionId'])" }) } else { $null }); getViews = $assign.Count; declared = $declared; agentOf42 = $agentOf42 }
    }
    Check (@($wire.ids) -notcontains (Sid 42) -and @($wire.ids) -notcontains (Sid 43) -and @($wire.ids) -contains (Sid 44)) "the node's sessions.list carries the sessions it keeps and not the ended ones"
    Check ($wire.listed -eq 3) ("the hub's count matches the live sessions, and the ones whose liveness is unknown (" + $wire.listed + ", want 3)")
    Check ("$($wire.get["42|"].state)" -ceq "absent" -and "$($wire.get["42|"].reason)" -like "*ended, proven by its process*3002 is not running*") ("session.get answers an ended session absent with its proof, not that no store holds it (" + $wire.get["42|"].reason + ")")
    Check ("$($wire.get["41|"].state)" -ceq "known") "CONTROL: session.get finds a live session"
    Check ($wire.agentOf42 -ne "" -and "$($wire.get["42|$($wire.agentOf42)"].reason)" -like "*ended, proven by its process*") "session.get naming the ended session's own agent still answers with its proof"
    Check ("$($wire.get['42|another-agent'].reason)" -notlike "*ended, proven*") "session.get naming another agent does not take the ended session's proof as its answer"
    Check ($wire.getViews -eq 1 -and $null -ne $wire.commandIds -and @($wire.commandIds) -notcontains (Sid 42) -and @($wire.commandIds) -contains (Sid 41)) "horde node serve's own view block leaves out the sessions whose end is proven"
    Check ($null -ne $wire.declared -and "$($wire.declared.state)" -ceq "known" -and (@($wire.declared.value) -join ",") -ceq "X2") "horde node serve's own view block carries the session stores the node declares"
}

if (Section "membership" "the hub drops a session a membership-complete node list leaves out (remote/NodeServe.ps1, remote/Mirror.ps1)") {
    # THE ALWAYS-ON NODE AFTER PR #240: its list is never complete (no host adapter, X4), so the hub
    # carried every session that ended, forever ("0 session(s), 2 carried"). The node now declares the
    # stores that name its sessions (session-stores.json, here X2 alone) and, when it read them
    # whole, says its list names every session it has (membershipComplete, verbs version 2); the hub then
    # drops what the list leaves out (ledger core-projection L-101). Each poll goes over the real frame
    # path: the node's hello and answer, encoded by the link's writer and decoded by the hub's reader.
    & {
        . (Join-Path $root "remote\NodeServe.ps1")
        . (Join-Path $root "remote\Mirror.ps1")
        $contract = Get-HordeLinkContract
        $nsn = New-HordeNamespace -Device $nodeDevice -Space "windows"
        $x2 = New-HordeKnown -Value @("X2")
        $t1 = Utc "2026-06-01T09:00:00.0000000Z"
        function FrameLine { param($Frame) $b = ConvertTo-HordeFrameBytes -Frame $Frame -Contract $contract; return [System.Text.Encoding]::ASCII.GetString($b.bytes, 0, $b.bytes.Length - 1) }
        function Poll {
            # One pull by a hub that speaks verbs version 2: the node's view as horde node serve builds it,
            # its sessions.list answer as the hub's reader decodes it, and the mirror after it.
            param($Mirror, [string]$D, $Processes, $Stores)
            $doc = ConvertTo-HordeNodeViewDocument -Projection (NodeProject $D $Processes)
            $doc["sessionStores"] = $Stores
            $data = [pscustomobject]@{ manifest = $null; view = $doc; viewError = ""; journalRoot = ""; namespace = $nsn }
            $st = New-HordeNodeServeState -NodeId $nodeDevice -NodeName "always-on" -HordeVersion "0.1.0" -Contract $contract
            $t = Get-HordeLinkTime
            $hello = [pscustomobject][ordered]@{ v = 1; kind = "hello"; id = (New-HordeLinkFrameId); seq = 1; ts = $t; hello = [pscustomobject][ordered]@{ role = "hub"; id = "7c9e6679-7425-40de-944b-e07fc1f90ae7"; name = "fixture-hub"; protocols = @(1); verbsVersions = @(1, 2); hordeVersion = "0.1.0"; t1 = $t } }
            $null = Invoke-HordeNodeFrame -State $st -Line (FrameLine $hello) -Data $data
            $req = [pscustomobject][ordered]@{ v = 1; kind = "req"; id = (New-HordeLinkFrameId); seq = 2; ts = (Get-HordeLinkTime); verb = "sessions.list"; requestId = (New-HordeLinkFrameId); issuedAt = (Get-HordeLinkTime); args = [pscustomobject]@{} }
            $reply = (Invoke-HordeNodeFrame -State $st -Line (FrameLine $req) -Data $data).reply
            $got = ConvertFrom-HordeFrameBytes -Bytes ([System.Text.Encoding]::ASCII.GetBytes((FrameLine $reply))) -Contract $contract
            if (-not $got.ok) { throw ("the hub's reader refused the node's answer: " + $got.reason) }
            $list = $got.frame.result.value
            $at = [datetime]::UtcNow
            $m = Update-HordeNodeMirror -Mirror $Mirror -List $list -NodeSentAt $at -ReceivedAt $at
            $rows = @(Get-HordeMirrorRows -Mirror $m -Now $at)
            return [pscustomobject]@{ mirror = $m; list = $list; node = (New-HordeFleetNode -Mirror $m -Now $at -TtlSeconds 60); rows = $rows; ids = @($rows | ForEach-Object { "$($_.sessionId)" }) }
        }
        function Start-Node {
            # A node with two live sessions, 51 and 52, pulled once: both listed, nothing carried.
            param([string]$Name, $Stores = $x2)
            $d = NodeFleet $Name @((ControlFile 5051 51 $t1), (ControlFile 5052 52 $t1))
            $p = Poll (New-HordeNodeMirror -DeviceId $nodeDevice -DeviceName "always-on") $d (Table @((Proc 5051 $t1), (Proc 5052 $t1))) $Stores
            return [pscustomobject]@{ dir = $d; first = $p }
        }
        $live = Table @((Proc 5051 $t1))

        # A CLEAN EXIT: the agent deletes its control file, so nothing is left to prove the end by.
        $n = Start-Node "member-clean"
        Check ($n.first.node.listed -eq 2 -and $n.first.node.carried -eq 0 -and "$($n.first.list.membershipComplete.state)" -ceq "known" -and $n.first.list.membershipComplete.value -eq $true -and $n.first.list.complete.value -eq $false) "CONTROL: the node's list names every session while its fields stay partial (no host adapter)"
        Remove-Item -LiteralPath (Join-Path $n.dir "agent\sessions\5052.json")
        $p2 = Poll $n.first.mirror $n.dir $live $x2
        Check ($p2.node.carried -eq 0 -and @($p2.ids) -notcontains (Sid 52)) "a clean exit is dropped by the hub"
        # Mirrored as listed, not carried: the fixture's clock is in the past, so its presence is aged out.
        $inList = @(@(Get-HordeLinkProp (Get-HordeLinkProp (Get-HordeLinkProp $p2.mirror "inventory") "list") "sessions") | ForEach-Object { "$(Get-HordeLinkProp $_ 'sessionId')" })
        Check (@($p2.rows | Where-Object { $_.sessionId -ceq (Sid 51) }).Count -eq 1 -and $inList -ccontains (Sid 51) -and $p2.node.listed -eq 1) "a live session stays listed and mirrored"
        $p3 = Poll $p2.mirror $n.dir $live $x2
        Check ($p3.node.carried -eq 0 -and $p3.node.listed -eq 1) "the next poll carries nothing either"

        # A KILLED PANE: the control file stays, its process is gone; the node drops it (PR #240).
        $n = Start-Node "member-killed"
        $p2 = Poll $n.first.mirror $n.dir $live $x2
        Check ($p2.node.carried -eq 0 -and @($p2.ids) -notcontains (Sid 52) -and $p2.list.membershipComplete.value -eq $true) "a killed pane is dropped by the hub"

        # THE LISTING CANNOT BE READ WHOLE: a half-written control file may name any session.
        $n = Start-Node "member-unread"
        Remove-Item -LiteralPath (Join-Path $n.dir "agent\sessions\5052.json")
        PutText (Join-Path $n.dir "agent\sessions\5099.json") '{"pid":5099,"sess'
        $p2 = Poll $n.first.mirror $n.dir $live $x2
        Check ($p2.list.membershipComplete.value -eq $false -and $p2.node.carried -eq 1 -and @($p2.ids) -contains (Sid 52)) ("an unreadable listing drops nothing (" + $p2.list.membershipComplete.reason + ")")

        # NO DECLARATION: the node says nothing about membership, and the hub carries as before.
        $n = Start-Node "member-undeclared" (New-HordeAbsent -Note "there is no session-stores.json")
        Remove-Item -LiteralPath (Join-Path $n.dir "agent\sessions\5052.json")
        $p2 = Poll $n.first.mirror $n.dir $live (New-HordeAbsent -Note "there is no session-stores.json")
        Check ($p2.list.membershipComplete.value -eq $false -and $p2.node.carried -eq 1 -and @($p2.ids) -contains (Sid 52)) "a node that declares no stores is unchanged: the hub carries what it leaves out"

        # AN UNDECLARED STORE ONLY TAKES THE CLAIM AWAY (review of PR #243). The node declares X2, then
        # runs the other agent too, whose control file is caught half written: it names nothing this
        # poll, so the session it would name must be carried, not dropped.
        # Its control folder, named as the fixture's own record of that agent names it.
        $otherRec = @($p.inputs.identity.records.Values | Where-Object { "$($_.fields.agent.value)" -cne "$(Val (Ans $p 1 'agent'))" })[0]
        $otherDir = "wezfleet\" + (Split-Path -Leaf (Split-Path -Parent $otherRec.source))
        $n = Start-Node "member-other-half"
        Remove-Item -LiteralPath (Join-Path $n.dir "agent\sessions\5052.json")
        New-Item -ItemType Directory -Path (Join-Path $n.dir $otherDir) -Force | Out-Null
        # The rest of the wezfleet root is whole, so only that agent's listing can take the claim away.
        New-Item -ItemType Directory -Path (Join-Path $n.dir "wezfleet\registry\sessions") -Force | Out-Null
        $whole = Poll $n.first.mirror $n.dir $live $x2
        Check ($whole.list.membershipComplete.value -eq $true) ("CONTROL: with that agent's folder empty and the wezfleet root whole, the claim stands (" + $whole.list.membershipComplete.reason + ")")
        PutText (Join-Path $n.dir ($otherDir + "\thread-9.json")) '{"sessionId":"thr'
        $p2 = Poll $n.first.mirror $n.dir $live $x2
        $why = "$($p2.list.membershipComplete.reason)"
        Check ($p2.list.membershipComplete.value -eq $false -and $why -clike "*W8*" -and $why -cnotlike "*W1*" -and $p2.node.carried -eq 1 -and @($p2.ids) -contains (Sid 52)) ("a half-written control file of an undeclared store keeps the hub carrying (" + $why + ")")
        # A pane-sessions file with no host to judge it names nothing, and its folder exists.
        $n = Start-Node "member-pane-file"
        Remove-Item -LiteralPath (Join-Path $n.dir "agent\sessions\5052.json")
        New-Item -ItemType Directory -Path (Join-Path $n.dir "agent\pane-sessions") -Force | Out-Null
        $pj = ReadJson (Join-Path $fx "agent\pane-sessions\17.json"); $pj.session_id = (Sid 52)
        PutJson (Join-Path $n.dir "agent\pane-sessions\17.json") $pj
        $p2 = Poll $n.first.mirror $n.dir $live $x2
        Check ($p2.list.membershipComplete.value -eq $false -and $p2.node.carried -eq 1 -and @($p2.ids) -contains (Sid 52)) ("a pane-sessions folder on the node keeps the hub carrying: its files name sessions only through the host (" + $p2.list.membershipComplete.reason + ")")
    }
}

if (Section "precedence" "precedence, one field at a time (core/ownership.json)") {
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
    $w2 = ReadJson (Join-Path $waits "agent\sessions\1002.json"); $w2.status = "waiting"; $w2 | Add-Member -NotePropertyName waitingFor -NotePropertyValue "permission prompt" -Force; PutJson (Join-Path $waits "agent\sessions\1002.json") $w2
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
    # The newest source wins even when it is not the first one walked: the run's command log comes first
    # (20 s ago), the transcript after it, made newer here (mutation run of PR #31, 2026-10-01).
    $act = New-Fleet "activity"
    [System.IO.File]::SetLastWriteTimeUtc((Join-Path $act ("agent\projects\C--work-gamma\" + (Sid 3) + ".jsonl")), $now.AddSeconds(-5))
    $pact = Project $act
    Check ((Src (Ans $pact 3 "lastActivity")) -eq "X3" -and (Val (Ans $pact 3 "lastActivity")) -like "2026-06-01T11:59:55*") "last activity is the newest source, not the first one read"
    Check ((St (Ans $p 15 "lastActivity")) -eq "unknown" -and (Why (Ans $p 15 "lastActivity")) -like "*never idle*") "no transcript leaves last activity unknown"
    Check ((Val (Ans $p 21 "transcriptPath")) -like "*C--work-x*" -and (Src (Ans $p 21 "transcriptPath")) -eq "X3" -and (St (Ans $p 4 "transcriptPath")) -eq "unknown" -and (Why (Ans $p 4 "transcriptPath")) -like "*2 project folders*") "a stopped session's transcript is the one file for its id, never one of two"
    Check ((Src (Ans $p 1 "transcriptPath")) -eq "X2" -and (Val (Ans $p 1 "transcriptPath")) -like "*C--work-alpha*") "a running session's transcript is derived from its control file"

}

if (Section "pane" "the pane, and the lead's decisions of 2026-09-30") {
    # DECISION 1: several sessions claim one handle - every claimant unknown, naming all of them.
    $claimants = @(7, 8, 9)
    $allUnknown = @($claimants | Where-Object { (St (Ans $p $_ "pane")) -ne "unknown" -or -not ((Why (Ans $p $_ "pane")) -like ("*" + (Sid 7) + "*" + (Sid 8) + "*" + (Sid 9) + "*")) }).Count -eq 0
    Check $allUnknown "every claimant of one handle has an unknown pane naming every claimant"
    $hc = Fault $p "handle-claimed-twice"
    Check ((FSt $hc) -eq "true" -and (Subjects $hc) -contains "handle 16" -and (Subjects $hc) -contains (Sid 8)) "a handle claimed twice is reported as a fault"
    $row16 = @((Val $p.handles) | Where-Object { $_.handle -eq "16" })
    Check ($row16.Count -eq 1 -and @($row16[0].claimants).Count -eq 3 -and @($row16[0].sessions).Count -eq 0) "the claimed handle lists its claimants and answers for none of them"
    # DECISION 2: with no host to ask, a stored handle cannot be verified - unknown, never absent.
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

}

if (Section "hostport" "the host port contract (core/HostPort.ps1)") {
    # CAPABILITIES ARE DECLARED. A port without a declaration is refused, and so is a name or a state
    # outside the vocabulary; core relies on a capability only when it is yes.
    $noop = { return , @() }
    Check ((Throws { New-HordeHostPort -Name "x" -StoredHandles @() -Capabilities $null -Handles $noop -Instance $noop } "Capabilities") -and (Throws { New-HordeHostPort -Name "x" -StoredHandles @() -Capabilities @{ "list" = "maybe" } -Handles $noop -Instance $noop } "yes, no, declined or unverified") -and (Throws { New-HordeHostPort -Name "x" -StoredHandles @() -Capabilities @{ "readMinds" = "yes" } -Handles $noop -Instance $noop } "not a host capability")) "a host port must declare its capabilities from the closed vocabulary"
    $offPort = New-HordeUnavailableHostPort -Reason "switched off"
    Check (@($script:HordeHostCapabilityNames | Where-Object { Test-HordeHostCapability -Port $offPort -Name $_ }).Count -eq 0 -and $script:HordeHostCapabilityNames.Count -ge 10) "the unavailable host declares every capability no"
    $pnl2 = Project $base -HostPort (HostOf $base -Caps @{ "list" = "no" })
    Check ($pnl2.handles.state -eq "unknown" -and $pnl2.handles.reason -like "*does not offer list*" -and @($pnl2.sessions | Where-Object { $_.fields["pane"].answer.state -ne "unknown" }).Count -eq 0) "a host that does not offer its handle list leaves every pane unknown"
    $pun = Project $base -HostPort (HostOf $base -Caps @{ "instance.startedAt" = "unverified" })
    Check ((St (Ans $pun 1 "pane")) -eq "unknown" -and (Why (Ans $pun 1 "pane")) -like "*does not offer instance.startedAt*") "an unverified capability counts as no"
    # A start time the host does not offer is not kept, even when the port hands one over: the view would
    # otherwise carry it as the instance's (mutation run of PR #31, 2026-10-01: nothing else checked it).
    Check ($null -ne $p.host.instance.value.startedAt -and $null -eq $pun.host.instance.value.startedAt) "a start time the host does not offer is not kept"
    $declPort = HostOf $base -Caps @{ "text.read" = "declined" }
    Check ((Test-HordeHostCapability -Port $declPort -Name "text.read") -eq $false -and (Test-HordeHostCapability -Port $declPort -Name "list") -eq $true) "a declined capability is not relied on"
    # A HANDLE IS UNIQUE WITHIN ITS INSTANCE, as plain text; a native id with a sigil is the adapter's to map.
    function RowsPort { param([object[]]$Rows, [hashtable]$Caps = @{ "list" = "yes" }) $rb = { return , $Rows }.GetNewClosure(); return (New-HordeHostPort -Name "fake" -StoredHandles @() -Capabilities $Caps -Handles $rb -Instance $noop) }
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

}

if (Section "stored-handle" "a stored handle belongs to the host that wrote it") {
    # The registry, rosters, reports, pane-sessions files and claims hold bare handle text, written by the
    # first host. Another host's handle 17 is not that host's pane 17 (review of PR #31, finding 2), so a
    # port declares which stores' handles it wrote, and a handle from any other store is unknown.
    Check ((Throws { New-HordeHostPort -Name "x" -Capabilities @{ "list" = "yes" } -StoredHandles @("W9") -Handles { , @() } -Instance { $null } } "not a store") -and (Throws { New-HordeHostPort -Name "x" -Capabilities @{ "list" = "yes" } -StoredHandles $null -Handles { , @() } -Instance { $null } } "StoredHandles")) "a host port must say which stores' handles it wrote"
    $pns = Project $base -HostPort (HostOf $base -Stores @())
    $nsKnown = @($pns.sessions | Where-Object { $_.fields["pane"].answer.state -eq "known" } | ForEach-Object { $_.sessionId })
    Check ($nsKnown.Count -eq 0 -and (Why (Ans $pns 1 "pane")) -like "*not written by this host*" -and (Why (Ans $pns 10 "pane")) -like "*not written by this host*") "a stored handle counts only when this host declares it wrote that store"
    Check ((St (Ans $pns 10 "role")) -eq "unknown") "a claim is matched by handle only when this host wrote the claims"
    $pw1 = Project $base -HostPort (HostOf $base -Stores @("W1"))
    Check ((Val (Ans $pw1 1 "pane")) -eq "10" -and (St (Ans $pw1 10 "pane")) -eq "unknown") "CONTROL: a host that wrote the registry but not the pane-sessions files is trusted for the registry only"

}

if (Section "instance-proven" "a session's host instance is proven, never assumed") {
    # A running session is not proven to be in this host's instance: it may run in another terminal
    # (review of PR #31, finding 3). The one instance running names it only when the session's handle is
    # live in it.
    Check ((St (Ans $p "codex-thread-1" "hostInstance")) -eq "unknown" -and (St (Ans $p 12 "hostInstance")) -eq "unknown") "a running session whose handle is unknown is in no proven host instance"
    Check ((Val (Ans $p 10 "hostInstance")) -eq "inst-1" -and (Src (Ans $p 10 "hostInstance")) -eq "X5") "CONTROL: a session whose handle is live in the one instance is in it"

}

if (Section "instance-whole" "the host instance is read whole, or not at all") {
    # A malformed instance id and an ambiguity flag that is not a boolean were dropped or read as false
    # (review of PR #31, finding 4). Both are unknown, with the reason.
    function InstPort { param($Inst) $ib = { return $Inst }.GetNewClosure(); return (New-HordeHostPort -Name "fake" -StoredHandles @() -Capabilities @{ "list" = "yes"; "instance.startedAt" = "yes" } -Handles { , @() } -Instance $ib) }
    $badId = Read-HordeHostInstance -Port (InstPort ([pscustomobject]@{ id = "a/b c"; running = 1; ambiguous = $false }))
    Check ($badId.state -eq "unknown" -and $badId.reason -like "*instance id*") "a malformed instance id makes the instance unknown, never nameless"
    $badAmb = Read-HordeHostInstance -Port (InstPort ([pscustomobject]@{ id = "i1"; running = 1; ambiguous = "no" }))
    Check ($badAmb.state -eq "unknown" -and $badAmb.reason -like "*ambiguous*") "an ambiguity flag that is not true or false makes the instance unknown"
    # An adapter composes the instance id from what names its server, for a multiplexer
    # <distro>.<socket>.<server pid>, which can pass 64 characters; the rule allows 128.
    $longId = ("Ubuntu-24.04." + ("s" * 90) + ".12345")
    $okLong = Read-HordeHostInstance -Port (InstPort ([pscustomobject]@{ id = $longId; running = 1; ambiguous = $false }))
    Check ($okLong.state -eq "known" -and "$($okLong.value.id)" -ceq $longId -and $longId.Length -gt 64) "an instance id composed of distro, socket and server pid is kept whole"
    # The boundary itself: 128 characters are an instance id, 129 are not (second review of PR #31, finding 3).
    $id128 = Read-HordeHostInstance -Port (InstPort ([pscustomobject]@{ id = ("i" * 128); running = 1; ambiguous = $false }))
    Check ($id128.state -eq "known" -and "$($id128.value.id)".Length -eq 128) "an instance id of 128 characters is kept"
    $id129 = Read-HordeHostInstance -Port (InstPort ([pscustomobject]@{ id = ("i" * 129); running = 1; ambiguous = $false }))
    Check ($id129.state -eq "unknown" -and $id129.reason -like "*at most 128*") "an instance id of 129 characters makes the instance unknown"

}

if (Section "platform" "the process table is the platform's") {
    # Core's own process table and the namespace its pids live in come from a platform, not from a
    # Windows call in core (review of PR #31, finding 6), so a node on another system supplies its own.
    $winPlat = Get-HordeLocalPlatform
    Check ("$($winPlat.processSpace)" -ceq "windows" -and $winPlat.processTable -is [scriptblock]) "the local platform names its process namespace and its process-table reader"
    $posixTable = ProcsOf $base
    $posixBlock = { return $posixTable }.GetNewClosure()
    $posix = New-HordePlatform -Name "posix-node" -ProcessSpace "posix" -ProcessTable $posixBlock
    $nsCaps2 = @{ "list" = "yes"; "pid" = "yes" }
    $rbp = { return , @([pscustomobject]@{ handle = "a"; pid = 7; space = "posix" }, [pscustomobject]@{ handle = "b"; pid = 7; space = "windows" }) }
    $pxPort = New-HordeHostPort -Name "fake" -StoredHandles @() -Capabilities $nsCaps2 -Handles $rbp -Instance { $null }
    $pxRows = @{}; foreach ($r in @(Val (Read-HordeHostHandles -Port $pxPort -Platform $posix))) { $pxRows[$r.handle] = $r }
    Check ((Val $pxRows["a"].pid) -eq 7 -and $pxRows["b"].pid.state -eq "unknown" -and $pxRows["b"].pid.reason -like "*namespace windows, not posix*") "on another platform its own namespace's pids are known and windows ones are not"
    $ppx = Get-HordeProjection -WezfleetRoot (Join-Path $base "wezfleet") -ClaudeDir (Join-Path $base "agent\sessions") -ProjectsDir (Join-Path $base "agent\projects") -CodexDir (Join-Path $base "wezfleet\codex-sessions") -PaneSessionsDir (Join-Path $base "agent\pane-sessions") -Platform $posix -HostPort (HostOf $base) -LayoutPort (LayoutOf $base) -TtlSeconds 900 -Now $now
    Check (@($ppx.sessions).Count -eq 34 -and (Val (Ans $ppx 1 "pid")) -eq 1001) "the projection reads processes through the platform it is given"
    Check (Throws { New-HordePlatform -Name "x" -ProcessSpace "mars" -ProcessTable { $null } } "namespace") "a platform's namespace is one core knows"
    # The operating system's process table is read in one place, behind the platform seam (second review
    # of PR #31, finding 5): core/identity used to call it directly.
    # A comment naming the class is not a read of it (core/Services.ps1 quotes a measurement), so the file's
    # tokens are asked, not its text. A string still counts: that is how the class is named to a CIM call.
    function Test-NamesWin32Process { param([string]$Text) $tok = $null; $bad = $null; $null = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tok, [ref]$bad); return (@($tok | Where-Object { $_.Kind -ne "Comment" -and $_.Text -match 'Win32_Process' }).Count -gt 0) }
    Check (-not (Test-NamesWin32Process "# measured with Win32_Process.Create") -and (Test-NamesWin32Process "Get-CimInstance -ClassName Win32_Process") -and (Test-NamesWin32Process "Get-CimInstance -ClassName 'Win32_Process'")) "CONTROL: a comment naming the process table is no read of it, and a call is, with or without quotes"
    $w32 = @(Get-ChildItem -LiteralPath (Join-Path $root "core") -Filter "*.ps1" | Where-Object { Test-NamesWin32Process (Get-Content -LiteralPath $_.FullName -Raw) } | ForEach-Object { $_.Name })
    foreach ($x in @($w32 | Where-Object { $_ -ne "Platform.ps1" })) { Write-Host ("  reads Win32_Process: core/" + $x) -ForegroundColor Red }
    Check ($w32.Count -eq 1 -and $w32[0] -eq "Platform.ps1") "the process table is read only behind the platform seam"
    $seamTable = Read-HordePlatformProcessTable -Platform $posix
    Check ($seamTable.state -eq "known" -and @($seamTable.value.Keys) -contains 1001) "the seam reads a platform's process table through one neutral function"

}

if (Section "one-writer" "one writer host per store") {
    # A store's handles are trusted from the host that declares it wrote them, which holds only while each
    # store has exactly one writer host (second review of PR #31, finding 2). A second host declaring a
    # store another host already declared is refused; the same host declaring it again is not.
    $wb = { , @() }; $wi = { $null }
    $firstOk = $true; try { $null = New-HordeHostPort -Name "fake" -StoredHandles @("W4") -Capabilities @{ "list" = "yes" } -Handles $wb -Instance $wi } catch { $firstOk = $false }
    Check ($firstOk -and -not (Throws { New-HordeHostPort -Name "fake" -StoredHandles @("W4") -Capabilities @{ "list" = "yes" } -Handles $wb -Instance $wi } "one writer")) "CONTROL: a host may declare the stores it wrote, and declare them again"
    Check (Throws { New-HordeHostPort -Name "writer-host-b" -StoredHandles @("W4") -Capabilities @{ "list" = "yes" } -Handles $wb -Instance $wi } "one writer") "two hosts declaring the same store are refused"

}

if (Section "judge" "the pane-file judge and the claim matcher, rule by rule") {
    # Each check below isolates one rule a mutant of core/Projection.ps1 breaks (second review of
    # PR #31, finding 8).
    $hv = New-Fleet "hijack-victim"
    $f18 = Join-Path $hv "agent\pane-sessions\18.json"; $j18 = ReadJson $f18; $j18.session_id = (Sid 4); PutJson $f18 $j18; [System.IO.File]::SetLastWriteTimeUtc($f18, $now.AddMinutes(-45))
    Check ((St (Ans (Project $hv) 4 "pane")) -eq "unknown") "a contradicted pane file leaves the session it names in no proven handle"
    $pnoc = Project $base -HostPort (HostOf $base -Stores @("W1", "W4", "W5", "X1"))
    Check ((Val (Ans $pnoc 10 "pane")) -eq "17" -and (St (Ans $pnoc 10 "role")) -eq "unknown" -and (Why (Ans $pnoc 10 "role")) -like "*claims' handles were not written by this host*") "a claim is not matched when this host did not write the claims"
    $nrc = New-Fleet "noreg-claim"
    Remove-Item -LiteralPath (RegPath $nrc 23) -Force
    PutText (Join-Path $nrc "wezfleet\registry\sessions\not-json.json") "{ torn"
    $pnrc = Project $nrc
    Check ($pnrc.complete["W1"].state -eq "unknown" -and (Val (Ans $pnrc 10 "pane")) -eq "17" -and (St (Ans $pnrc 10 "role")) -eq "unknown") "an incomplete registry leaves a claim unmatched, since the session's record may be the one missing"

}

if (Section "pane-guard" "the pane-sessions guard") {
    $two = Fault $p "session-in-two-handles"
    Check ((FSt $two) -eq "true" -and (Subjects $two) -contains (Sid 13) -and (St (Ans $p 13 "pane")) -eq "unknown") "a session in two handles is reported"
    $hij = Fault $p "pane-sessions-hijack"
    Check ((FSt $hij) -eq "true" -and (Subjects $hij) -contains (Sid 11) -and (Subjects $hij) -contains (Sid 12) -and (Val (Ans $p 11 "pane")) -eq "18" -and (St (Ans $p 12 "pane")) -eq "unknown") "a hijacked pane file does not answer"
    $tx = New-Fleet "transcript"
    Remove-Item -LiteralPath (Join-Path $tx ("agent\projects\C--work-delta\" + (Sid 10) + ".jsonl")) -Force
    $ptx = Project $tx
    Check ((St (Ans $ptx 10 "transcriptPath")) -eq "unknown" -and (Why (Ans $ptx 10 "transcriptPath")) -like "*names a transcript that exists*") "a pane file naming a missing transcript does not answer the transcript"
    $f17 = Join-Path $tx "agent\pane-sessions\17.json"
    $j17 = ReadJson $f17; $j17.transcript_path = (Join-Path $tx "agent\projects\C--work-x\aaaaaaaa-0000-4000-8000-000000000021.jsonl"); PutJson $f17 $j17
    [System.IO.File]::SetLastWriteTimeUtc($f17, $now.AddMinutes(-50))
    $ptx2 = Project $tx
    Check ((Src (Ans $ptx2 10 "transcriptPath")) -eq "X1") "CONTROL: a pane file naming a transcript that exists answers it"

    $nops = New-Fleet "no-pane-sessions"
    Remove-Item -LiteralPath (Join-Path $nops "agent\pane-sessions") -Recurse -Force
    $pnops = Project $nops
    Check ($pnops.complete["X1"].state -eq "unknown" -and $pnops.complete["X1"].reason -like "*no pane-sessions directory*" -and (St (Ans $pnops 10 "pane")) -eq "unknown") "a missing pane-sessions directory is unknown, not empty"
    $ref40 = @($p.inputs.paneRead.refused | Where-Object { $_.name -eq "40.json" })
    Check ($ref40.Count -eq 1 -and "$($ref40[0].reason)" -like "*pane-session.v1*" -and $p.complete["X1"].state -eq "known") "a pane-sessions file that breaks the schema is refused, not a gap"

}

if (Section "claim-guard" "the spawn claim's guard") {
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

}

if (Section "carry" "a stored value the view cannot carry") {
    # schema/session-record.v1's types are the view's for engine fields: a label of the wrong shape or a
    # parent that is not a session id is never passed on as known.
    $shape = New-Fleet "shape"
    EditReg $shape 4 { param($r) $r | Add-Member -NotePropertyName label -NotePropertyValue "b-1" -Force; $r.parent = "the orchestrator" }
    $psh = Project $shape
    Check ((St (Ans $psh 4 "label")) -eq "unknown" -and (Why (Ans $psh 4 "label")) -like "*does not match*" -and (St (Ans $psh 4 "parent")) -eq "unknown") "a stored value the view cannot carry is unknown, naming why"
    $shDoc = ConvertFrom-HordeJson -Text ((ConvertTo-HordeSessionViewDocument $psh) | ConvertTo-Json -Depth 40)
    Check (@(Test-HordeSchema -Value $shDoc -Schema $viewSchema).Count -eq 0) "and the view that carries it still validates"

}

if (Section "cannot-tell" "a store that cannot tell is not a store that holds none") {
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
    # Where nothing else answers, the registry's hole is the only thing between unknown and absent: session
    # 34 is known only from a report, and its pane is absent over the whole registry (mutation run of
    # PR #31, 2026-10-01: every field checked above also had an unsure claim to keep it unknown).
    Check ((St (Ans $p 34 "pane")) -eq "absent" -and (St (Ans $pnr 34 "pane")) -eq "unknown" -and (Why (Ans $pnr 34 "pane")) -like "*may be the one missing*") "an incomplete registry leaves a pane unknown where no other store answers"
    $realExtras = ${function:Read-HordeControlExtras}
    function Read-HordeControlExtras { param($Record) if ("$($Record.fields.agent.value)" -ceq "codex") { return $null }; return (& $realExtras -Record $Record) }
    $pcx = $null
    try { $pcx = Project $base } finally { ${function:Read-HordeControlExtras} = $realExtras }
    Check ((St (Ans $pcx "codex-thread-1" "fleetSessionId")) -eq "unknown" -and (Why (Ans $pcx "codex-thread-1" "fleetSessionId")) -like "*could not be read again*") "a codex file that cannot be read again is not a codex file that is missing"

}

if (Section "holes" "an unlistable run, a doubly held file, an unreadable command line") {
    # Three more skips that could end absent over a store with a hole in it (second review of PR #31,
    # finding 1). A runs directory that cannot be listed may hold the session's run; a pane-sessions file
    # that cannot be judged may be the session's; a claude process whose command line cannot be read may
    # be resuming it.
    $rj = New-Fleet "runs-junction"
    $projDir = Join-Path $rj "wezfleet\proj"
    Rename-Item -LiteralPath (Join-Path $projDir "runs") -NewName "runs-real"
    $gone = Join-Path $projDir "gone-target"
    New-Item -ItemType Directory -Path $gone | Out-Null
    $null = & cmd /c mklink /J (Join-Path $projDir "runs") $gone
    Remove-Item -LiteralPath $gone -Force
    $prj = $null
    try { $prj = Project $rj } finally { $null = & cmd /c rmdir (Join-Path $projDir "runs") }
    $rjBad = @("runId", "title", "dependsOn", "workState", "report" | Where-Object { (St (Ans $prj 3 $_)) -ne "unknown" } | ForEach-Object { $_ + "=" + (St (Ans $prj 3 $_)) })
    foreach ($x in $rjBad) { Write-Host ("  not unknown: " + $x) -ForegroundColor Red }
    Check ($prj.complete["W3"].state -eq "unknown" -and $rjBad.Count -eq 0) "a runs directory that cannot be listed never proves a session is in no run"
    # A pane-sessions file held by two running sessions, and one session named by two files: neither
    # file answers, and the session they name is not thereby proven to be in no handle.
    $hf = New-Fleet "held-files"
    EditReg $hf 2 { param($r) $r.pane = "10" }
    $f10 = Join-Path $hf "agent\pane-sessions\10.json"; $j10 = ReadJson $f10; $j10.session_id = (Sid 4); PutJson $f10 $j10; [System.IO.File]::SetLastWriteTimeUtc($f10, $now.AddHours(-1))
    $phf = Project $hf
    Check ((St (Ans $phf 4 "pane")) -eq "unknown") "a file that two running sessions hold does not prove the session it names is in no handle"
    $tf = New-Fleet "two-files"
    foreach ($h in @("19", "20")) { $fp = Join-Path $tf ("agent\pane-sessions\" + $h + ".json"); $jj = ReadJson $fp; $jj.session_id = (Sid 4); PutJson $fp $jj; [System.IO.File]::SetLastWriteTimeUtc($fp, $now.AddMinutes(-40)) }
    Check ((St (Ans (Project $tf) 4 "pane")) -eq "unknown") "two files naming a session do not prove it is in no handle"
    # A claude process whose command line cannot be read may be resuming any session.
    $nc = New-Fleet "no-command-line"
    PutJson (Join-Path $nc "processes.json") (@(ReadJson (Join-Path $nc "processes.json")) + @([pscustomobject]@{ pid = 1200; name = "claude.exe"; created = "2026-06-01T11:30:00.0000000Z"; commandLine = $null }))
    Check ((St (Ans $p 4 "pid")) -eq "absent") "CONTROL: a stopped session with every command line readable has no pid"
    Check ((St (Ans (Project $nc) 4 "pid")) -eq "unknown") "a claude process whose command line cannot be read leaves a stopped session's pid unknown"

}

if (Section "runs" "runs, reports and work") {
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
    Check ((St (Ans $pb 3 "workState")) -eq "unknown" -and (Val (Ans $p 3 "workState")) -eq "running") "a torn event log leaves the work state unknown, not read from what came before it"

}

if (Section "cardinality" "cardinality checks") {
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
    Check ((St (Ans $prl 4 "role")) -eq "unknown" -and (FSt (Fault $prl "two-warchiefs")) -eq "unknown") "a live record with no role is unknown, never warg, and makes the count unknown"
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
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $clean "agent\sessions") -File)) { if (@("1001.json", "1002.json") -notcontains $f.Name) { Remove-Item -LiteralPath $f.FullName -Force } }
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $clean "agent\pane-sessions") -File)) { if ($f.Name -ne "10.json") { Remove-Item -LiteralPath $f.FullName -Force } }
    Remove-Item -LiteralPath (Join-Path $clean "wezfleet\codex-sessions") -Recurse -Force
    New-Item -ItemType Directory -Path (Join-Path $clean "wezfleet\codex-sessions") | Out-Null
    foreach ($repo in @("proj", "other")) { Remove-Item -LiteralPath (Join-Path $clean ("wezfleet\" + $repo)) -Recurse -Force }
    PutJson (Join-Path $clean "processes.json") @(@(ReadJson (Join-Path $clean "processes.json")) | Where-Object { @(1001, 1002, 4) -contains [int]$_.pid })
    $pcl = Project $clean
    $notFalse = @($pcl.faults | Where-Object { (FSt $_) -ne "false" } | ForEach-Object { $_.kind + "=" + (FSt $_) + " " + $_.answer.reason })
    foreach ($x in $notFalse) { Write-Host ("  not false on the clean fleet: " + $x) -ForegroundColor Red }
    Check (@($pcl.sessions).Count -eq 2 -and @($pcl.faults).Count -eq 19 -and $notFalse.Count -eq 0) "CONTROL: a clean fleet has no fault, and every check says so"
    Check ((FSt (Fault $pu "handle-claimed-twice")) -eq "unknown" -and (FSt (Fault $pu "session-in-two-handles")) -eq "unknown") "with no host to ask, the handle checks are unknown, not clean"

}

if (Section "parity" "parity differences, in their documented direction (planning/parity-2.3.md)") {
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
    $censusRule = Join-Path $moved ("agent\projects\" + ("C:\work\moved" -replace '[:\\/]', '-') + "\" + (Sid 21) + ".jsonl")
    Check ((Val (Ans $pmv 21 "transcriptPath")) -like "*C--work-x*" -and (Val (Ans $pmv 21 "projectCwd")) -eq "C:\work\x" -and -not (Test-Path -LiteralPath $censusRule)) "parity exception census transcript from current cwd"
    # P-11: census prints the stored owner, "(unowned)" when empty; the view derives the parent's label.
    Check ("$((ReadJson (RegPath $base 4)).owner)" -eq "" -and (Val (Ans $p 4 "owner")) -eq "A") "parity exception owner derived from parent"
    # P-12: census prints origin "unknown" for a record with none.
    $noorigin = New-Fleet "noorigin"
    EditReg $noorigin 4 { param($r) $r.PSObject.Properties.Remove("origin") }
    Check ((St (Ans (Project $noorigin) 4 "origin")) -eq "absent") "a missing origin is not the string unknown"

}

if (Section "silent-winner" "no silent winner") {
    # Where two records answer one question, nothing picks the last or the first (review of PR #31,
    # finding 8): the question is unknown and the pair is reported.
    $hold = New-Fleet "two-holders"
    EditReg $hold 2 { param($r) $r.pane = "10" }
    $phd = Project $hold
    $hij10 = @((Fault $phd "pane-sessions-hijack").found | Where-Object { @($_.subjects) -contains "handle 10" })
    Check ($hij10.Count -eq 0 -and (St (Ans $phd 1 "pane")) -eq "unknown" -and (Subjects (Fault $phd "handle-claimed-twice")) -contains "handle 10") "two running sessions holding one handle leave its pane file unjudged, and are reported"
    $dupr = New-Fleet "roster-twice"
    $rp = Join-Path $dupr "wezfleet\proj\runs\20260601-100000-alpha\roster.json"
    $rj = ReadJson $rp; $rj.sessions = @($rj.sessions) + @($rj.sessions[0]); PutJson $rp $rj
    $pdr = Project $dupr
    $rt = Fault $pdr "roster-entry-twice"
    Check ((St (Ans $pdr 3 "runId")) -eq "unknown" -and (Why (Ans $pdr 3 "runId")) -like "*twice*" -and (FSt $rt) -eq "true" -and (Subjects $rt) -contains "alpha" -and (Subjects $rt) -contains "20260601-100000-alpha") "a roster that lists one fleet id twice is reported, and chooses neither entry"
    Check ((FSt (Fault $p "roster-entry-twice")) -eq "false") "CONTROL: rosters that list each id once are not a fault"
    # Either holder may be the one a held file names; neither makes it a hijack of the other (mutation run
    # of PR #31, 2026-10-01: the check above names only the holder read first).
    $hold2 = New-Fleet "two-holders-second"
    EditReg $hold2 2 { param($r) $r.pane = "10" }
    $fh2 = Join-Path $hold2 "agent\pane-sessions\10.json"; $jh2 = ReadJson $fh2; $jh2.session_id = (Sid 2); PutJson $fh2 $jh2; [System.IO.File]::SetLastWriteTimeUtc($fh2, $now.AddSeconds(-3600))
    $phd2 = Project $hold2
    $hij10b = @((Fault $phd2 "pane-sessions-hijack").found | Where-Object { @($_.subjects) -contains "handle 10" })
    Check ($hij10b.Count -eq 0 -and (St (Ans $phd2 2 "pane")) -eq "unknown") "a file held by two sessions is no hijack whichever of them it names"

}

if (Section "one-agent" "a check that reads one agent's processes speaks only for that agent") {
    # conversation-in-two-processes reads the command lines of one agent's processes. A session of any
    # other agent could be running twice unseen, so while one exists the clean answer is unknown, not
    # false (review of PR #31, finding 9).
    $onec = New-Fleet "one-copy"
    PutJson (Join-Path $onec "processes.json") @(@(ReadJson (Join-Path $onec "processes.json")) | Where-Object { @(1100, 1101) -notcontains [int]$_.pid })
    $c2p = Fault (Project $onec) "conversation-in-two-processes"
    Check ((FSt $c2p) -eq "unknown" -and $c2p.answer.reason -like "*codex-thread-1*") "a session of an agent whose processes are not read leaves the duplicate check unknown"
    Remove-Item -LiteralPath (Join-Path $onec "wezfleet\codex-sessions\codex-thread-1.json") -Force
    Check ((FSt (Fault (Project $onec) "conversation-in-two-processes")) -eq "false") "CONTROL: with only sessions whose processes are read, no duplicate is a known false"

}

if (Section "layout" "the layout and the resume command") {
    $rc1 = Ans $p 1 "resumeCommand"
    Check ((St $rc1) -eq "unknown" -and @($rc1.shadow | Where-Object { $_.store -eq "R1" }).Count -eq 1 -and "$(@($rc1.shadow)[0].value)" -like "*--resume*") "a layout save never answers resumeCommand"
    $rc3 = Ans $p 3 "resumeCommand"
    Check ((St $rc3) -eq "unknown" -and @($rc3.shadow | Where-Object { $_.store -eq "W5" }).Count -eq 1) "the report's stored resume command is a shadow too"
    Check ($p.complete["R1"].state -eq "known" -and $pu.complete["R1"].state -eq "known") "CONTROL: the layout port was read"
    $pnl = Get-HordeProjection -WezfleetRoot (Join-Path $base "wezfleet") -ClaudeDir (Join-Path $base "agent\sessions") -ProjectsDir (Join-Path $base "agent\projects") -CodexDir (Join-Path $base "wezfleet\codex-sessions") -PaneSessionsDir (Join-Path $base "agent\pane-sessions") -Processes (ProcsOf $base) -HostPort (HostOf $base) -TtlSeconds 900 -Now $now
    Check ($pnl.complete["R1"].state -eq "unknown" -and (St (Ans $pnl 1 "resumeCommand")) -eq "unknown") "with no layout port the saves are unknown, not empty"

}

if (Section "schema" "schema/session-view.v1") {
    $doc = ConvertFrom-HordeJson -Text ((ConvertTo-HordeSessionViewDocument $p) | ConvertTo-Json -Depth 40)
    $sf = @(Test-HordeSchema -Value $doc -Schema $viewSchema)
    foreach ($x in @($sf | Select-Object -First 10)) { Write-Host ("  " + $x) -ForegroundColor Red }
    Check ($sf.Count -eq 0) "every answer validates against schema/session-view.v1"
    $rf = @(Test-HordeSessionViewRules -Document $doc)
    foreach ($x in @($rf | Select-Object -First 10)) { Write-Host ("  " + $x) -ForegroundColor Red }
    Check ($rf.Count -eq 0) "the view keeps the rules the schema cannot state"
    $docU = ConvertFrom-HordeJson -Text ((ConvertTo-HordeSessionViewDocument $pu) | ConvertTo-Json -Depth 40)
    Check (@(Test-HordeSchema -Value $docU -Schema $viewSchema).Count -eq 0 -and @(Test-HordeSessionViewRules -Document $docU).Count -eq 0) "a view with no host validates too"
    # CONTROLS: each check can fail.
    $broken = ConvertFrom-HordeJson -Text ($doc | ConvertTo-Json -Depth 40)
    $broken.sessions[0].fields.pid.PSObject.Properties.Remove("value")
    $broken.sessions[0].fields.role | Add-Member -NotePropertyName value -NotePropertyValue "master" -Force
    $broken.sessions[0].fields.role.state = "known"
    Check (@(Test-HordeSessionViewRules -Document $broken | Where-Object { $_ -like "*fields.pid is known and has no value*" }).Count -eq 1) "CONTROL: a known answer with no value breaks the view's rules"
    Check (@(Test-HordeSchema -Value $broken -Schema $viewSchema | Where-Object { $_ -like "*role.value*" }).Count -ge 1) "CONTROL: a role outside the native vocabulary fails the schema"
    # Stored fields: the view's value type is exactly the stored record's, for both records since remote
    # plan R10 split the record into the hub's fleet record and the node's binding record. The fleet
    # record's device is where the session runs, not one of its fields; it enters the view at R13.
    $recProps = @(@((Get-HordeSchema -Name "session-record.v1"), (Get-HordeSchema -Name "session-binding.v1")) | ForEach-Object { @($_.properties.PSObject.Properties) } | Where-Object { $_.Name -ne "schemaVersion" -and $_.Name -ne "sessionId" -and $_.Name -ne "device" })
    $vals = Get-HordeViewValueSchemas -ViewSchema $viewSchema
    function Strip { param($N) $o = [ordered]@{}; foreach ($q in $N.PSObject.Properties) { if ($q.Name -ne "description" -and $q.Name -notlike "x-*") { $o[$q.Name] = $q.Value } }; return ($o | ConvertTo-Json -Depth 10 -Compress) }
    $differ = @($recProps | Where-Object { -not $vals.ContainsKey($_.Name) -or (Strip $_.Value) -cne (Strip $vals[$_.Name]) } | ForEach-Object { $_.Name })
    foreach ($x in $differ) { Write-Host ("  value type differs from the stored record: " + $x) -ForegroundColor Red }
    Check ($recProps.Count -ge 14 -and $differ.Count -eq 0) ("a stored field's value type, in either record, is the view's (" + $recProps.Count + " fields)")
    $viewFields = @($viewSchema.definitions.session.properties.fields.required)
    Check (($viewFields -join ",") -ceq ($required -join ",")) "the view schema requires exactly the ownership table's fields"
    # Provisional marks: wherever the table has one, and nowhere else it has none.
    $provFields = @($ownership.fields | Where-Object { $null -ne $_.PSObject.Properties["provisional"] } | ForEach-Object { "$($_.name)" })
    $missingMark = @($p.sessions | ForEach-Object { $s = $_; $provFields | Where-Object { "$($s.fields[$_].provisional)" -eq "" } })
    $strayMark = @($p.sessions | ForEach-Object { $s = $_; @($s.fields.Keys) | Where-Object { $provFields -notcontains $_ -and "$($s.fields[$_].provisional)" -ne "" } })
    Check ($provFields.Count -ge 5 -and $missingMark.Count -eq 0 -and $strayMark.Count -eq 0) "the view carries a provisional mark exactly where the table has one"
    Check (@($ownership.dropped | ForEach-Object { "$($_.name)" } | Where-Object { (St (Ans $p 1 $_)) -ne "unknown" -or (Why (Ans $p 1 $_)) -notlike "*drops it*" }).Count -eq 0) "a dropped field is present and unknown, naming the drop"

}

if (Section "writes" "the projection writes nothing") {
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
    $newCore = @("Projection.ps1", "HostPort.ps1", "Faults.ps1", "PaneSessions.ps1", "WezfleetState.ps1", "Platform.ps1")
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


}

foreach ($n in $script:trips) { Write-Host ("  tripped: " + $n) -ForegroundColor Red }
Check ($script:trips.Count -eq 0) "the suite reads no real store before the reality check"

} finally {
    if ((Split-Path -Leaf $work) -match '^horde-projection-[0-9a-f]{32}$' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

$wantReality = Section "reality" "reality check: this machine's own stores, read only, no host attached"
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
if (-not $wantReality) {
    # not selected: Section said so
} elseif ($env:HORDE_SKIP_REALITY -eq "1") {
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
    $rdoc = ConvertFrom-HordeJson -Text ((ConvertTo-HordeSessionViewDocument $rp) | ConvertTo-Json -Depth 40)
    $rsf = @(Test-HordeSchema -Value $rdoc -Schema $viewSchema)
    foreach ($x in @($rsf | Select-Object -First 10)) { Write-Host ("  " + $x) -ForegroundColor Red }
    Check ($rsf.Count -eq 0) ("the real view validates against schema/session-view.v1 (" + $sw.ElapsedMilliseconds + " ms)")
    $rrf = @(Test-HordeSessionViewRules -Document $rdoc)
    foreach ($x in @($rrf | Select-Object -First 10)) { Write-Host ("  " + $x) -ForegroundColor Red }
    Check ($rrf.Count -eq 0) "the real view keeps the rules the schema cannot state"
    # The same reading completed in the current scope: every current session as it is under All.
    $sw.Restart()
    $rcur = Complete-HordeProjection -C $rp.inputs -Scope Current
    $rcurMs = $sw.ElapsedMilliseconds
    $rAllById = @{}; foreach ($x in @($rdoc.sessions)) { $rAllById["" + $x.sessionId] = ($x | ConvertTo-Json -Depth 40 -Compress) }
    $rcdoc = ConvertFrom-HordeJson -Text ((ConvertTo-HordeSessionViewDocument $rcur) | ConvertTo-Json -Depth 40)
    $rScopeBad = @($rcdoc.sessions | Where-Object { -not $rAllById.ContainsKey("" + $_.sessionId) -or $rAllById["" + $_.sessionId] -cne ($_ | ConvertTo-Json -Depth 40 -Compress) } | ForEach-Object { "" + $_.sessionId })
    foreach ($x in @($rScopeBad | Select-Object -First 10)) { Write-Host ("  differs from All: " + $x) -ForegroundColor Red }
    Write-Host ("  " + @($rcur.sessions).Count + " of " + @($rp.sessions).Count + " real sessions are current; the current scope completed in " + $rcurMs + " ms") -ForegroundColor DarkGray
    Check (@($rcur.sessions).Count -ge 1 -and $rScopeBad.Count -eq 0) ("every current real session's fields are identical under both scopes (" + @($rcur.sessions).Count + " current)")
}

}

# A RUN THAT SKIPPED THE REALITY CHECK IS NOT A PASS TO A GATE. It says so in its banner and exits 3,
# not 0, so anything that expects 0 fails loudly; tools\Mutate.ps1 accepts 3 only from a spec that
# declares it (PassCodes), and test/test-suite.ps1 pins the helper's pass code (second review of
# PR #31, finding 4). A run that skipped any section is the same: exit 3.
$successBanner = "one read-only view of the Horde, every field an answer with its source, and nothing written"
$passCode = 0
if ($env:HORDE_SKIP_REALITY -eq "1") { $successBanner = "FIXTURES ONLY - REALITY CHECK SKIPPED (HORDE_SKIP_REALITY=1), EXIT 3: " + $successBanner; $passCode = 3 }
if ($script:sectionsSkipped.Count -gt 0) { $successBanner = "SECTIONS ONLY (" + ($script:sectionsWanted -join ",") + "), EXIT 3: " + $successBanner; $passCode = 3 }

Complete-HordeSuite -Success $successBanner -PassCode $passCode
