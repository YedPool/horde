# DOES A SESSION RESUMED BY HAND, WITH NO CONTROL FILE, EVER READ AS ASLEEP OR GET A SECOND COPY? (T-0320)
#
# M resumed two lot members with `claude --resume <id>` in new panes (2026-10-21). Neither process had a
# control file, so `horde fleet lots` showed both asleep and a wake of the lot would have started a second
# copy of each. agents/claude-code/Fleet.ps1 now reads the harness processes' command lines as a second
# witness (test-fleet-liveness.ps1 checks the reading itself). THIS suite drives the REAL adapter's snapshot
# and verdict, over stand-in control files and a stand-in process table, through the three callers that act
# on a verdict: `fleet lots` (fleet/Lots.ps1), `fleet wake -Lot` (fleet/Wake.ps1) and the hibernate exit check
# (fleet/Hibernate.ps1). The terminal is a stand-in that records every start it is asked for. Nothing real is
# started, typed into or read: the control files and the home are under TEMP.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "agents\claude-code\Fleet.ps1")
. (Join-Path $root "fleet\Lots.ps1")
. (Join-Path $root "fleet\Asleep.ps1")
. (Join-Path $root "fleet\Hibernate.ps1")

function Section { param([string]$Title) Write-Host ""; Write-Host ("--- " + $Title + " ---") -ForegroundColor Cyan }

$work = Join-Path $env:TEMP ("horde-resumed-argv-" + [guid]::NewGuid().ToString("N"))
$ctl = Join-Path $work "sessions"
[void](New-Item -ItemType Directory -Path $ctl -Force)
$START = "134364209037804403"
$ids = @{ E = "6168116b-625a-4db3-841c-af42e6516996"; H = "4e2bf794-d16d-4a82-bd1a-6a2320d7b7d9"; X = "44444444-0000-4000-8000-000000000005" }
$cwds = @{ E = "C:\lanes\e"; H = "C:\lanes\h"; X = "C:\lanes\x" }
$exe = '"C:\Users\x\AppData\Roaming\npm\claude.exe"'

# The world: one unrelated live session with a control file (so the folder is not empty), the process table.
$world = @{}
function Reset-World {
    $world.procs = @{}; $world.listing = "ok"; $world.spawns = New-Object System.Collections.ArrayList
    $world.clock = [datetime]::new(2026, 10, 21, 20, 0, 0, [System.DateTimeKind]::Utc)
    Get-ChildItem -LiteralPath $ctl -File | Remove-Item -Force
    $j = [ordered]@{ pid = 4242; sessionId = "aaaaaaaa-1111-4111-8111-111111111111"; cwd = "C:\other"; procStart = $START; kind = "interactive" }
    [System.IO.File]::WriteAllText((Join-Path $ctl "4242.json"), (ConvertTo-Json -InputObject $j))
}
function Add-Proc { param([int]$ProcId, [string]$Name, [string]$Line) $world.procs[$ProcId] = [pscustomobject]@{ pid = $ProcId; name = $Name; commandLine = $Line } }
$table = { if ($world.listing -ceq "ok") { New-HordeKnown -Value $world.procs.Clone() } else { New-HordeUnknown -Reason "the process table is not readable" } }.GetNewClosure()
$procStart = { param($p) if ("" + $p -ceq "4242") { $START } else { "" } }.GetNewClosure()
$real = Resolve-HordeFleetAdapter -Kind "agent"
Check ($real.state -ceq "known" -and $real.value.name -ceq "claude-code") "CONTROL: the real adapter is the one under test"
# The real adapter's own verdict, running and the rest; only the snapshot reads the stand-in world.
$agent = [pscustomobject]@{
    name = $real.value.name
    snapshot = { New-ClaudeCodeFleetSnapshot -Read (Read-ClaudeCodeFleetRecords -Dirs @($ctl) -ProcessStart $procStart) -Resumed (Read-ClaudeCodeFleetResumeArgv -Table $table) }.GetNewClosure()
    verdict = $real.value.verdict; running = $real.value.running; resumeLine = { param($id) "resume " + $id }; scrub = { @{} }; lastTyped = $real.value.lastTyped
}

Register-HordeFleetHost -Name "stand-in" `
    -Placement { param($refs) New-HordeKnown -Value ([pscustomobject]@{ placed = @{}; notes = @() }) } `
    -Open {
        $spawn = { param($req) [void]$world.spawns.Add($req); New-HordeKnown -Value ([pscustomobject]@{ pane = "40"; window = "w40" }) }.GetNewClosure()
        $paneOf = { param($p) New-HordeUnknown -Reason "unreadable" }
        New-HordeKnown -Value ([pscustomobject]@{ spawn = $spawn; paneOf = $paneOf }) }.GetNewClosure() `
    -Describe { param($req) "spawn " + $req.mode + " cwd=" + $req.cwd + " :: " + $req.line } `
    -Release { param($id) New-HordeKnown -Value "removed" } `
    -Unmark { param($id, $why) New-HordeKnown -Value "removed" }
$hostA = Resolve-HordeFleetAdapter -Kind "host"
$deps = [pscustomobject]@{
    Now = { $world.clock }.GetNewClosure()
    Sleep = { param($ms) $world.clock = $world.clock.AddMilliseconds($ms) }.GetNewClosure()
    FreePercent = { 50.0 }
    Agent = $agent; Host = $hostA.value
    Post = { param($sid, $label, $body, $mid) New-HordeKnown -Value ([pscustomobject]@{ stage = "accepted" }) }
    WaitSeconds = 5; PollMs = 1000
    ProcessStart = { param($p) "" }
    Self = { [pscustomobject]@{ pid = 777; start = "133000000000000000" } }
    RegistryPane = { param($sid) New-HordeAbsent -Note "no row" }
}
function Session {
    param([string]$L, [string]$Role = "orc")
    $hist = @([pscustomobject]@{ state = "recorded"; at = "2026-10-16T09:15:00Z" }, [pscustomobject]@{ state = "exited"; at = "2026-10-16T09:30:00Z" })
    return [pscustomobject][ordered]@{ sessionId = $ids[$L]; label = $L; role = $Role; cwd = $cwds[$L]; state = "exited"; history = $hist; pane = "11" }
}
function New-Home { $h = Join-Path $work ([guid]::NewGuid().ToString("N")); [void](New-Item -ItemType Directory -Path $h -Force); return $h }
function Put-Lot {
    param([string]$H, [string]$Id, $Sessions)
    $dir = Join-Path (Get-HordeFleetHibernationsDir -HordeHome $H) $Id
    [void](New-Item -ItemType Directory -Path $dir -Force)
    $rec = [pscustomobject][ordered]@{ schemaVersion = 1; id = $Id; createdAt = "2026-10-16T09:15:00Z"; agent = "claude-code"; host = "stand-in"
        selection = [pscustomobject][ordered]@{ kind = "all"; labels = @(); exclude = @() }; sessions = @($Sessions) }
    [void](Write-HordeFleetRecord -Dir $dir -Record $rec)
    $when = [datetime]::Parse("2026-10-16T09:15:00Z", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal)
    $lot = New-HordeFleetLot -At $when -ById "" -Reason "test park" -Kind "orcs"
    [void](Write-HordeFleetLot -Dir $dir -Lot $lot -Members @(ConvertTo-HordeFleetLotMembers -LotId $lot.id -Record $rec))
    return $lot
}
function Lot-Of { param([string]$H) $a = Get-HordeFleetLots -HordeHome $H -Agent $agent; if ($a.state -cne "known") { throw ("lots unknown: " + $a.reason) }; return @($a.value.lots)[0] }
function Member-Of { param($Lot, [string]$L) return @($Lot.members | Where-Object { $_.label -ceq $L })[0] }
function Spawned { param([string]$L) return @($world.spawns | Where-Object { $_.line -ceq ("resume " + $ids[$L]) }).Count }

Section "fleet lots: a member resumed by hand is not asleep"
Reset-World
$hh = New-Home
$lot0 = Put-Lot -H $hh -Id "20261016-091500" -Sessions @((Session "E"), (Session "H"), (Session "X"))
$lot = Lot-Of $hh
Check ((Member-Of $lot "E").state -ceq "asleep" -and (Member-Of $lot "H").state -ceq "asleep") "CONTROL: with nothing resumed, exited members are asleep"
Add-Proc 28356 "claude.exe" ($exe + " --resume " + $ids["E"] + " --dangerously-skip-permissions")
Add-Proc 19364 "claude.exe" ($exe + " --resume=" + $ids["H"].ToUpperInvariant())
$lot = Lot-Of $hh
Check ((Member-Of $lot "E").state -ceq "still-awake" -and (Member-Of $lot "H").state -ceq "still-awake") ("a resumed member with no control file is still-awake, in both argv forms and either case (" + (Member-Of $lot "E").state + ", " + (Member-Of $lot "H").state + ")")
Check ((Member-Of $lot "X").state -ceq "asleep") "CONTROL: a member nothing resumed is still asleep"
$asleep = Get-HordeFleetAsleep -HordeHome $hh -Agent $agent -HostAdapter $hostA.value -KeepMarkers
Check ($asleep.state -ceq "known" -and -not $asleep.value.ContainsKey($ids["E"]) -and -not $asleep.value.ContainsKey($ids["H"]) -and $asleep.value.ContainsKey($ids["X"])) "the wake watcher's reading agrees: only X is asleep"
$world.procs.Clear()
Add-Proc 5 "claude.exe" ($exe + " --add-dir C:\work\" + $ids["E"])
Add-Proc 7 "claude.exe" ($exe + " --session-id " + $ids["H"])
Add-Proc 6 "claude.exe" ($exe + " --resume " + $ids["X"] + ' "look at ' + $ids["H"] + '"')
$lot = Lot-Of $hh
Check ((Member-Of $lot "E").state -ceq "asleep" -and (Member-Of $lot "H").state -ceq "asleep" -and (Member-Of $lot "X").state -ceq "still-awake") "an id that merely appears in a path or in a prompt after another id's --resume does not count"
$world.procs.Clear(); $world.listing = "unreadable"
$a = Get-HordeFleetLots -HordeHome $hh -Agent $agent
$lot = @($a.value.lots)[0]
Check ($a.state -cne "known" -or ((Member-Of $lot "E").state -cne "asleep" -and (Member-Of $lot "H").state -cne "asleep")) ("an unreadable process table never shows a member asleep (" + $a.state + ")")

Section "fleet wake -Lot: a resumed member is refused and never started"
Reset-World
$hh = New-Home
$null = Put-Lot -H $hh -Id "20261016-091500" -Sessions @((Session "E"), (Session "H"), (Session "X"))
Add-Proc 28356 "claude.exe" ($exe + " -r " + $ids["E"])
Add-Proc 19364 "claude.exe" ($exe + " --resume " + $ids["H"])
$r = Invoke-HordeFleetWakeLot -Lot "20261016-091500" -Deps $deps -HordeHome $hh
Check ((Spawned "E") -eq 0 -and (Spawned "H") -eq 0) "neither resumed member is started a second time"
Check ((Spawned "X") -eq 1) "CONTROL: the member nothing resumed is started"
$oc = @($r.outcomes | Where-Object { $_.label -ceq "E" })[0]
Check ($oc.outcome -ceq "still-awake") ("the refused member's outcome says still-awake (" + $oc.outcome + ")")
Reset-World
$hh = New-Home
$null = Put-Lot -H $hh -Id "20261016-091500" -Sessions @((Session "E"), (Session "H"))
$world.listing = "unreadable"
$r = $null
try { $r = Invoke-HordeFleetWakeLot -Lot "20261016-091500" -Deps $deps -HordeHome $hh } catch { $r = $null }
Check ($world.spawns.Count -eq 0) "with the process table unreadable nothing is started at all"

Section "hibernate: a process that resumed the id and still runs is not exited"
function Exit-Step {
    $req = [pscustomobject]@{ sessionId = $ids["E"]; label = "E"; cwd = $cwds["E"]; parkedPath = "x"; askedAt = "2026-10-21T19:00:00Z"; reason = "t"; others = @(); since = $null
        memo = [pscustomobject]@{ fileSeen = $true; exitSent = $true; blocked = "" } }
    $d = [pscustomobject]@{ Agent = $agent; ParkedAt = { param($p) $null }; State = { param($s) $null }; Exit = { param($s, $r) $null } }
    return (Invoke-HordeFleetParkSession -Request $req -Deps $d)
}
Reset-World
$o = Exit-Step
Check ($o.outcome -ceq "parked") ("CONTROL: with no process resuming it, a session sent its exit command is seen stopped (" + $o.outcome + ")")
Add-Proc 28356 "claude.exe" ($exe + " --resume " + $ids["E"])
$o = Exit-Step
Check ($o.outcome -ceq "not-yet" -and $o.reason -like "*still runs*") ("a process that resumed its id still running means not exited (" + $o.outcome + ": " + $o.reason + ")")
$world.procs.Clear()
$o = Exit-Step
Check ($o.outcome -ceq "parked") "and once that process is gone it is exited"
$world.listing = "unreadable"
$o = Exit-Step
Check ($o.outcome -ceq "not-yet") ("an unreadable process table is never read as exited (" + $o.outcome + ")")

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Complete-HordeSuite -Success "a session resumed by hand with no control file is never asleep, never started a second time and never seen exited while its process runs"
