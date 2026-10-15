# THE ORC REGISTRY AND THE DASH: ONE LIST OF ORCS IN HIS ORDER, KEPT AS WRITE-ONCE RECORDS, WITH WHAT IS
# DERIVED OF EACH ORC WORKED OUT FROM THE FLEET AND NEVER STORED.
#
# orcs/Registry.ps1 and `horde orcs` (design "Dash: one list of Orcs", PR 1, 2026-10-15), on homes and
# fleets of the suite's own under %TEMP%. It attacks:
#   1. the fold and write-once: records 1..n, each file never rewritten; a damaged record and a record that
#      breaks the schema are reported by number and change nothing; a later version's kind is set aside;
#   2. a lane seen and not registered is shown at the end of the main list, and written there by the next
#      change, before the back-burner;
#   3. a lane the fleet retired leaves the list (and comes back at the end); one retired by hand stays off;
#   4. each status rule both ways, with its age: blocked by a waiting-on line (not by "nothing"), blocked by
#      a question that blocks all, working within 15 minutes, idle past it;
#   5. Wargs: active and inactive either side of the 15-minute line, a Warg found through its parent, one
#      through its owner, and one with no Orc that can be told, counted under none and said;
#   6. an order refused when an Orc is missing, extra or named twice; a stale version refused; names and
#      domains held to their rules;
#   7. the dash snapshot's fields, through the cards channel's own snapshot;
#   8. `horde orcs` under BOTH Windows PowerShell 5.1 and pwsh 7, each reading the other's records;
#   9. the PC's lane rule is the decisions page's, name for name (under Node).
# Without pwsh.exe or node the part that needs it is NOT RUN, said loudly, and the suite exits 3.
# NO REAL FLEET IS TOUCHED: the fleet root is pinned to an empty folder (test/lib/FleetPin.ps1), and every
# home, lanes folder and sessions folder is the suite's own.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\FleetPin.ps1")
$fleetPin = Enter-HordeTestEmptyFleet
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "channels\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
foreach ($f in @(Get-HordeRelayChannelFiles)) { . $f }
Set-StrictMode -Version Latest
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + ")") -ForegroundColor DarkGray

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$work = Join-Path $env:TEMP ("horde-orcs-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$realHome = $env:HORDE_HOME
$partial = New-Object System.Collections.ArrayList
$now = [datetime]::new(2026, 10, 15, 12, 0, 0, [System.DateTimeKind]::Utc)

function New-Home {
    param([string]$Name)
    $h = Join-Path $script:work $Name
    New-Item -ItemType Directory -Path (Join-Path $h "progress\lanes") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $h "progress\sessions") -Force | Out-Null
    return $h
}
function Set-Lane {
    # A lane folder with a standard status.txt, written -Ago minutes before $now; -Waiting adds the seventh line.
    param([string]$HomeDir, [string]$Folder, [string]$Orc, [double]$Ago = 60, [string]$Waiting = "")
    $dir = Join-Path $HomeDir ("progress\lanes\" + $Folder)
    [void][System.IO.Directory]::CreateDirectory($dir)
    $t = "horde-orc-status 1`norc: " + $Orc + "`nlane: a lane`ndoing: building a thing`nfinished: merged a thing`nblocked: no`n"
    if ($Waiting -ne "") { $t = $t + "waiting on: " + $Waiting + "`n" }
    $p = Join-Path $dir "status.txt"
    [System.IO.File]::WriteAllText($p, $t, $script:utf8)
    [System.IO.File]::SetLastWriteTimeUtc($p, $script:now.AddMinutes(-$Ago))
}
function Set-Session {
    # One session record: its id is the file name; label, parent, owner and lastSeen -Ago minutes before $now.
    param([string]$HomeDir, [string]$Id, [string]$Label = "", [string]$Parent = "", [string]$Owner = "", [double]$Ago = 1, [switch]$Retired)
    $r = [ordered]@{ label = $Label; parent = $Parent; owner = $Owner; lastSeen = $script:now.AddMinutes(-$Ago).ToString("o") }
    if ($Retired) { $r["retired"] = $true }
    [System.IO.File]::WriteAllText((Join-Path $HomeDir ("progress\sessions\" + $Id + ".json")), (ConvertTo-Json -InputObject $r -Compress), $script:utf8)
}
function Get-Dash { param([string]$HomeDir) $env:HORDE_HOME = $HomeDir; return (Get-HordeOrcDash -HordeHome $HomeDir -Now $script:now) }
function Get-Row { param($Dash, [string]$Id) return (@($Dash.orcs | Where-Object { $_.id -ceq $Id }) | Select-Object -First 1) }
function Write-Orc { param([string]$HomeDir, [string]$Op, $Request, [long]$Version = -1) $env:HORDE_HOME = $HomeDir; return (Invoke-HordeOrcWrite -Operation $Op -Request $Request -HordeHome $HomeDir -Version $Version -Now $script:now) }
function Get-Records { param([string]$HomeDir) return @(Get-ChildItem -LiteralPath (Join-Path $HomeDir "orcs\registry") -Filter "*.json" | Sort-Object Name | ForEach-Object { ConvertFrom-HordeJson ([System.IO.File]::ReadAllText($_.FullName)) }) }
function Ids { param($Dash) return ((@($Dash.orcs) | ForEach-Object { $_.id + $(if ($_.backBurner) { "*" } else { "" }) }) -join ",") }
function Add-Question {
    param([string]$HomeDir, [string]$AskedBy, [string]$Blocks = "part")
    $env:HORDE_HOME = $HomeDir
    $q = [ordered]@{ title = "Should the step go ahead?"; kind = "yes-no"; whatItIs = "The step is ready."; group = "A group"; askedBy = $AskedBy; waiting = @($AskedBy) }
    $a = Invoke-HordeDecision -Operation "add" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = $q; blocks = $Blocks } -Root (Join-Path $HomeDir "store\decisions")
    if ($a.state -cne "known" -or $a.value.outcome -cne "done") { throw ("the question was not added: " + $a.reason) }
    return [int]$a.value.number
}

try {
    Write-Host ""
    Write-Host "--- 1. the fold and write-once ---" -ForegroundColor Cyan
    $A = New-Home "fold"
    Set-Lane $A "decisions-page" "F"
    Set-Lane $A "form-fill" "C"
    $d0 = Get-Dash $A
    Check ($d0.ok -and $d0.version -eq 0 -and (Ids $d0) -ceq "decisions-page,form-fill" -and @($d0.orcs | Where-Object { $_.registered }).Count -eq 0 -and -not (Test-Path (Join-Path $A "orcs\registry"))) ("a home with no registry reads as version 0, shows the lanes it sees, and the read writes nothing (" + (Ids $d0) + ")")
    $r1 = Write-Orc $A "domain" @{ id = "decisions-page"; domain = "Horde relay,  decisions page " }
    $recs = Get-Records $A
    Check ($r1.outcome -ceq "done" -and $r1.version -eq 3 -and $recs.Count -eq 3 -and (@($recs | ForEach-Object { $_.kind }) -join ",") -ceq "orc-registered,orc-registered,orc-domain-set" -and (@($recs | ForEach-Object { $_.sequence }) -join ",") -ceq "1,2,3") ("a first change registers the lanes first, then writes itself: records 1 to 3 (" + $r1.outcome + " " + $r1.reason + ")")
    Check ((Get-Row (Get-Dash $A) "decisions-page").domain -ceq "Horde relay,  decisions page ") "a domain is stored exactly as given, its spaces kept"
    $bytes1 = [System.IO.File]::ReadAllBytes((Join-Path $A "orcs\registry\0000000001.json"))
    $r2 = Write-Orc $A "name" @{ id = "form-fill"; name = "Form fill" }
    $bytes1b = [System.IO.File]::ReadAllBytes((Join-Path $A "orcs\registry\0000000001.json"))
    Check ($r2.outcome -ceq "done" -and $r2.version -eq 4 -and [Convert]::ToBase64String($bytes1) -ceq [Convert]::ToBase64String($bytes1b)) "a later change is a new record; record 1 is not rewritten"
    $r3 = Write-Orc $A "name" @{ id = "form-fill"; name = "Form fill" }
    Check ($r3.outcome -ceq "unchanged" -and @(Get-Records $A).Count -eq 4) "a change that changes nothing writes nothing"
    # A damaged record, a record that breaks the schema, and a later version's kind - each written by hand.
    [System.IO.File]::WriteAllText((Join-Path $A "orcs\registry\0000000005.json"), '{"schemaVersion":1,"sequence":5,"kind":"orc-nam', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $A "orcs\registry\0000000006.json"), '{"schemaVersion":1,"sequence":6,"kind":"orc-named","at":"2026-10-15T12:00:00Z","actor":"cli","by":"console","data":{"id":"form-fill","name":"' + ("x" * 41) + '"}}', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $A "orcs\registry\0000000007.json"), '{"schemaVersion":1,"sequence":7,"kind":"orc-coloured","at":"2026-10-15T12:00:00Z","actor":"cli","by":"console","data":{"id":"form-fill","colour":"red"}}', $utf8)
    $st = Read-HordeOrcRegistry -Root (Join-Path $A "orcs\registry")
    Check ($st.state -ceq "ok" -and $st.version -eq 7 -and (@($st.unreadable | ForEach-Object { $_.sequence }) -join ",") -ceq "5,6" -and $st.later.ContainsKey("orc-coloured") -and $st.orcs["form-fill"].name -ceq "Form fill") ("a torn record and a record that breaks the schema are reported by number and change nothing; a later kind is set aside; the fold goes on (" + (@($st.unreadable | ForEach-Object { "" + $_.sequence + ": " + $_.reason }) -join " | ") + ")")
    $dA = Get-Dash $A
    Check (@($dA.lines | Where-Object { $_ -like "record 5 *" }).Count -eq 1 -and @($dA.lines | Where-Object { $_ -like "*orc-coloured*" }).Count -eq 1) "the dash says which records it could not read and which it set aside"
    $r4 = Write-Orc $A "name" @{ id = "form-fill"; name = "Form fill two" }
    Check ($r4.outcome -ceq "done" -and $r4.version -eq 8) "a write after damaged records takes the next place, past them"

    Write-Host ""
    Write-Host "--- 2. a lane seen and not registered goes to the end of the main list ---" -ForegroundColor Cyan
    $B = New-Home "register"
    Set-Lane $B "aaa-lane" "A"
    Set-Lane $B "ccc-lane" "C"
    $null = Write-Orc $B "backburner" @{ id = "ccc-lane"; on = $true }
    Set-Lane $B "bbb-lane" "B"
    $dB = Get-Dash $B
    $new = Get-Row $dB "bbb-lane"
    Check ((Ids $dB) -ceq "aaa-lane,bbb-lane,ccc-lane*" -and -not $new.registered -and $new.name -ceq "Orc B" -and -not $new.backBurner) ("a new lane is shown at the END of the main list, above the back-burner, not registered yet, named Orc B (" + (Ids $dB) + ")")
    $null = Write-Orc $B "domain" @{ id = "aaa-lane"; domain = "something" }
    $recs = Get-Records $B
    $dB2 = Get-Dash $B
    Check ((Ids $dB2) -ceq "aaa-lane,bbb-lane,ccc-lane*" -and (Get-Row $dB2 "bbb-lane").registered -and @($recs | Where-Object { $_.kind -ceq "orc-registered" -and $_.data.id -ceq "bbb-lane" -and $_.actor -ceq "fleet" }).Count -eq 1) "the next change writes it into the registry, by the fleet, at the end of the main list"
    New-Item -ItemType Directory -Path (Join-Path $B "progress\lanes\no-status-here") -Force | Out-Null
    Set-Lane $B "thrall-helper" "M"
    $env:HORDE_HOME = $B
    [void][System.IO.Directory]::CreateDirectory((Join-Path $B "settings"))
    [System.IO.File]::WriteAllText((Join-Path $B "settings\orcs.json"), '{"schemaVersion": 1, "settings": {"notOrcs": "aaa-lane"}}', $utf8)
    $dB3 = Get-Dash $B
    Check ((Ids $dB3) -ceq "bbb-lane,ccc-lane*") ("a folder with no status.txt, a lane whose status names M, and a lane named in notOrcs get no card (" + (Ids $dB3) + ")")
    Remove-Item -LiteralPath (Join-Path $B "settings\orcs.json")

    Write-Host ""
    Write-Host "--- 3. retired lanes leave the list ---" -ForegroundColor Cyan
    $lane = Join-Path $B "progress\lanes\bbb-lane"
    Move-Item -LiteralPath (Join-Path $lane "status.txt") -Destination (Join-Path $lane "status.retired.txt")
    $dR = Get-Dash $B
    Check ((Ids $dR) -ceq "aaa-lane,ccc-lane*") ("a lane the fleet retired leaves the list at once, before anything is written (" + (Ids $dR) + ")")
    $null = Write-Orc $B "domain" @{ id = "aaa-lane"; domain = "something else" }
    Check (@(Get-Records $B | Where-Object { $_.kind -ceq "orc-retired" -and $_.data.id -ceq "bbb-lane" -and $_.data.reason -ceq "fleet" }).Count -eq 1) "the next change records it as retired by the fleet"
    Set-Lane $B "bbb-lane" "B"
    $dBack = Get-Dash $B
    Check ((Ids $dBack) -ceq "aaa-lane,bbb-lane,ccc-lane*" -and -not (Get-Row $dBack "bbb-lane").registered) "a lane the fleet retired that comes back is shown again, at the end of the main list"
    $rr = Write-Orc $B "retire" @{ id = "aaa-lane" }
    $dH = Get-Dash $B
    Check ($rr.outcome -ceq "done" -and (Ids $dH) -ceq "bbb-lane,ccc-lane*") ("an Orc retired by hand leaves the list though its lane still has a status (" + (Ids $dH) + ")")
    $null = Write-Orc $B "domain" @{ id = "bbb-lane"; domain = "x" }
    Check ((Ids (Get-Dash $B)) -ceq "bbb-lane,ccc-lane*") "and it stays off: a later change does not register it again"
    $gone = Write-Orc $B "name" @{ id = "aaa-lane"; name = "Back" }
    Check ($gone.outcome -ceq "refused") "a change to a retired Orc is refused"

    Write-Host ""
    Write-Host "--- 4. the status rules, each both ways, with their ages ---" -ForegroundColor Cyan
    $s1 = Get-HordeOrcStatus -StatusAt $now.AddMinutes(-40) -WaitingOn "the founder, on a thing" -Now $now
    Check ($s1.status -ceq "blocked" -and $s1.text -ceq "blocked 40 min" -and $s1.since -ceq "2026-10-15T11:20:00Z") ("a waiting-on line blocks, aged from the status file (" + $s1.text + ")")
    $s2 = Get-HordeOrcStatus -StatusAt $now.AddMinutes(-40) -WaitingOn "nothing; question 76 waits on the founder" -Now $now
    Check ($s2.status -ceq "idle" -and $s2.text -ceq "idle 40 min") ("a waiting-on line that says nothing does not block (" + $s2.text + ")")
    $s3 = Get-HordeOrcStatus -StatusAt $now.AddMinutes(-2) -BlocksAllSince @($now.AddHours(-3)) -Now $now
    Check ($s3.status -ceq "blocked" -and $s3.text -ceq "blocked 3 h") ("a question that blocks all blocks, though the lane moved 2 minutes ago, aged from the question (" + $s3.text + ")")
    $s4 = Get-HordeOrcStatus -StatusAt $now.AddMinutes(-14) -Now $now
    $s5 = Get-HordeOrcStatus -StatusAt $now.AddMinutes(-16) -Now $now
    Check ($s4.status -ceq "working" -and $s4.text -ceq "working" -and $s5.status -ceq "idle" -and $s5.text -ceq "idle 15 min") ("moved 14 minutes ago is working; 16 minutes ago is idle, and says how long (" + $s4.text + " / " + $s5.text + ")")
    $s6 = Get-HordeOrcStatus -StatusAt $now.AddHours(-5) -SessionTimes @($now.AddMinutes(-3)) -Now $now
    Check ($s6.status -ceq "working") "a session that moved within 15 minutes makes it working though its status file is old"
    Check ((Format-HordeOrcAge 100) -ceq "under 5 min" -and (Format-HordeOrcAge (3 * 3600 + 59)) -ceq "3 h" -and (Format-HordeOrcAge (5 * 86400)) -ceq "5 d") "ages are said in steps: minutes, hours, days"
    $Q = New-Home "status"
    Set-Lane $Q "lane-b" "B" -Ago 5
    Set-Lane $Q "lane-c" "C" -Ago 30
    Set-Lane $Q "lane-d" "D" -Ago 30 -Waiting "M, since this morning, on a review"
    Set-Lane $Q "lane-f" "F" -Ago 300
    $null = Add-Question $Q "Orc C" "all"
    $null = Add-Question $Q "Orc F1" "part"
    $answered = Add-Question $Q "Orc F" "all"
    $a = Invoke-HordeDecision -Operation "say" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "founder"; number = $answered; speaker = "founder"; route = "window"; text = "Yes."; wordingVersion = 1 } -Root (Join-Path $Q "store\decisions")
    $dQ = Get-Dash $Q
    $b = Get-Row $dQ "lane-b"; $c = Get-Row $dQ "lane-c"; $dd = Get-Row $dQ "lane-d"; $ff = Get-Row $dQ "lane-f"
    Check ($a.state -ceq "known" -and $b.status -ceq "working" -and $b.open -eq 0 -and $c.status -ceq "blocked" -and $c.open -eq 1 -and $dd.status -ceq "blocked" -and $dd.statusText -ceq "blocked 30 min" -and $ff.status -ceq "idle" -and $ff.statusText -ceq "idle 5 h" -and $ff.open -eq 1) ("through the dash: B working, C blocked by its question that blocks all, D by its waiting-on line, F idle 5 h - its Wargs' question counted, the one he answered not (" + (@($dQ.orcs | ForEach-Object { $_.id + "=" + $_.statusText + "/" + $_.open }) -join ", ") + ")")

    Write-Host ""
    Write-Host "--- 5. Wargs: active and inactive, and whose ---" -ForegroundColor Cyan
    $W = New-Home "wargs"
    Set-Lane $W "lane-c" "C" -Ago 120
    Set-Lane $W "lane-f" "F" -Ago 120
    Set-Session $W "s-f" -Label "F" -Ago 30
    Set-Session $W "s-c" -Label "C" -Ago 200
    Set-Session $W "w-1" -Label "F1" -Parent "s-f" -Ago 14
    Set-Session $W "w-2" -Label "F2" -Parent "s-f" -Ago 16
    Set-Session $W "w-3" -Parent "w-1" -Ago 600
    Set-Session $W "w-4" -Owner "C" -Ago 5
    Set-Session $W "w-5" -Label "F7" -Ago 2
    Set-Session $W "w-6" -Parent "s-f" -Ago 1 -Retired
    $dW = Get-Dash $W
    $wf = Get-Row $dW "lane-f"; $wc = Get-Row $dW "lane-c"
    Check ($wf.wargsActive -eq 1 -and $wf.wargsInactive -eq 2 -and $wf.sessions -eq 4) ("F: the Warg that moved 14 minutes ago is active, the ones 16 minutes and 10 hours ago (one found through another Warg) inactive; the retired one is not counted; sessions are its own and its Wargs (" + $wf.wargsActive + "/" + $wf.wargsInactive + ", " + $wf.sessions + ")")
    Check ($wf.status -ceq "working") "a Warg that moved within 15 minutes makes its Orc working"
    Check ($wc.wargsActive -eq 1 -and $wc.wargsInactive -eq 0 -and $wc.sessions -eq 2) ("C: a Warg with no parent record is C's by the owner the fleet wrote (" + $wc.wargsActive + "/" + $wc.wargsInactive + ")")
    Check (@($dW.lines | Where-Object { $_ -like "1 open Warg session(s) name no Orc*" }).Count -eq 1) ("a Warg with neither parent nor owner is counted under no Orc - not under F by its label F7 - and said (" + (@($dW.lines) -join " | ") + ")")

    Write-Host ""
    Write-Host "--- 5b. latest activity: each source alone, the newest of several, none ---" -ForegroundColor Cyan
    $L = New-Home "latest"
    foreach ($x in @(@("x-a", "A"), @("x-b", "B"), @("x-c", "C"), @("x-d", "D"))) { Set-Lane $L $x[0] $x[1] -Ago 300 }
    $null = Write-Orc $L "domain" @{ id = "x-a"; domain = "registers all four" }
    # B, C and D lose their lane folders (not retired): they stay on the list with no status file.
    foreach ($x in @("x-b", "x-c", "x-d")) { Remove-Item -LiteralPath (Join-Path $L ("progress\lanes\" + $x)) -Recurse -Force }
    $iso = { param([datetime]$T) return $T.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture) }
    $log = @(
        ('{"v":1,"id":"e1","ts":"' + (& $iso $now.AddMinutes(-400)) + '","kind":"note","area":"Alpha","title":"older than the status","text":"x"}'),
        ('{"v":1,"id":"e2","ts":"' + (& $iso $now.AddMinutes(-90)) + '","kind":"note","area":"Alpha","title":"newer, by the area map","text":"x"}'),
        ('{"v":1,"id":"e3","ts":"' + (& $iso $now.AddMinutes(-50)) + '","kind":"note","lane":"B","title":"by its lane","text":"x"}'),
        ('{"v":1,"id":"e4","ts":"' + (& $iso $now.AddMinutes(-10)) + '","kind":"note","area":"Nowhere","title":"an area the map does not know","text":"x"}'),
        'not json at all')
    [System.IO.File]::WriteAllText((Join-Path $L "progress\changelog.jsonl"), (($log -join "`n") + "`n"), $utf8)
    [System.IO.File]::WriteAllText((Join-Path $L "progress\area-lanes.json"), '{"v":1,"areas":{"Alpha":"A"}}', $utf8)
    $qn = Add-Question $L "Orc C" "part"
    $env:HORDE_HOME = $L
    $null = Invoke-HordeDecision -Operation "say" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "founder"; number = $qn; speaker = "founder"; route = "window"; text = "Yes."; wordingVersion = 1 } -Root (Join-Path $L "store\decisions")
    $shown = Invoke-HordeDecision -Operation "show" -Request @{ number = $qn } -Root (Join-Path $L "store\decisions")
    $askedAt = ConvertFrom-HordeOrcTime "$($shown.value.question.addedAt)"
    $saidAt = ConvertFrom-HordeOrcTime "$(@($shown.value.question.thread.messages | Where-Object { $_.speaker -ceq 'founder' })[0].at)"
    $dL = Get-Dash $L
    $la = Get-Row $dL "x-a"; $lb = Get-Row $dL "x-b"; $lc = Get-Row $dL "x-c"; $ld = Get-Row $dL "x-d"
    Check ($lb.lastActivityAt -ceq (& $iso $now.AddMinutes(-50))) ("a progress entry alone, by its lane, sets it (" + $lb.lastActivityAt + ")")
    Check ($null -ne $saidAt -and $saidAt -ge $askedAt -and $lc.lastActivityAt -ceq (& $iso $saidAt)) ("a question alone sets it, to when the founder answered it, the newer of asked and answered (" + $lc.lastActivityAt + ")")
    Check ($la.lastActivityAt -ceq (& $iso $now.AddMinutes(-90))) ("of the status file (300 minutes ago) and two entries of its area (400 and 90 minutes ago), the newest wins; an entry of an area the map does not know is nobody's (" + $la.lastActivityAt + ")")
    Check ($null -eq $ld.lastActivityAt) "an Orc no source speaks for has no time"
    Remove-Item -LiteralPath (Join-Path $L "progress\changelog.jsonl")
    Check ((Get-Row (Get-Dash $L) "x-a").lastActivityAt -ceq (& $iso $now.AddMinutes(-300))) "the status file alone sets it too"

    Write-Host ""
    Write-Host "--- 6. orders, stale versions, names and domains ---" -ForegroundColor Cyan
    $O = New-Home "order"
    Set-Lane $O "l-a" "A"; Set-Lane $O "l-b" "B"; Set-Lane $O "l-c" "C"
    $v0 = (Get-Dash $O).version
    $miss = Write-Orc $O "order" @{ order = @("l-a", "l-b"); backBurner = @() }
    $extra = Write-Orc $O "order" @{ order = @("l-a", "l-b", "l-c", "l-x"); backBurner = @() }
    $twice = Write-Orc $O "order" @{ order = @("l-a", "l-b"); backBurner = @("l-c", "l-a") }
    Check ($miss.outcome -ceq "refused" -and $miss.reason -like "*leaves out l-c*" -and $extra.outcome -ceq "refused" -and $extra.reason -like "*l-x, which is not on the list*" -and $twice.outcome -ceq "refused" -and $twice.reason -like "*l-a more than once*") ("an order missing an Orc, naming one not on the list, or naming one twice is refused, each saying which (" + $miss.reason + " | " + $extra.reason + " | " + $twice.reason + ")")
    Check (-not (Test-Path (Join-Path $O "orcs\registry"))) "a refused order writes nothing, not even the registration of the lanes it saw"
    $ok = Write-Orc $O "order" @{ order = @("l-c", "l-a"); backBurner = @("l-b") } -Version $v0
    Check ($ok.outcome -ceq "done" -and (Ids (Get-Dash $O)) -ceq "l-c,l-a,l-b*") ("an order drawn from the version the registry is at is written whole, the back-burner below (" + $ok.reason + ")")
    $stale = Write-Orc $O "order" @{ order = @("l-a", "l-c"); backBurner = @("l-b") } -Version $v0
    Check ($stale.outcome -ceq "stale" -and $stale.version -eq $ok.version -and (Ids (Get-Dash $O)) -ceq "l-c,l-a,l-b*") "an order drawn from an older version is refused as stale, and the list is as it was"
    $staleName = Write-Orc $O "name" @{ id = "l-a"; name = "Alpha" } -Version ($ok.version - 1)
    Check ($staleName.outcome -ceq "stale") "any versioned change drawn from an older version is stale"
    $bbOn = Write-Orc $O "backburner" @{ id = "l-c"; on = $true } -Version $ok.version
    $bbOff = Write-Orc $O "backburner" @{ id = "l-b"; on = $false }
    Check ($bbOn.outcome -ceq "done" -and $bbOff.outcome -ceq "done" -and (Ids (Get-Dash $O)) -ceq "l-a,l-b,l-c*") ("backburner on moves an Orc to the end of the back-burner, off to the end of the main list (" + (Ids (Get-Dash $O)) + ")")
    $long = Write-Orc $O "domain" @{ id = "l-a"; domain = ("d" * 81) }
    $exact = Write-Orc $O "domain" @{ id = "l-a"; domain = ("d" * 80) }
    $hebrew = Write-Orc $O "domain" @{ id = "l-a"; domain = ("caf" + [char]0x00E9) }
    $secret = Write-Orc $O "domain" @{ id = "l-a"; domain = "key ghp_0123456789abcdefABCDEF0123456789abcd" }
    $noName = Write-Orc $O "name" @{ id = "l-a"; name = "   " }
    Check ($long.outcome -ceq "refused" -and $exact.outcome -ceq "done" -and $hebrew.outcome -ceq "refused" -and $secret.outcome -ceq "refused" -and $noName.outcome -ceq "refused" -and $secret.reason -notlike "*ghp_*") "a domain over 80 characters, one not printable ASCII and one that looks like a secret are refused (the secret not repeated); 80 is taken; a blank name is refused"

    Write-Host ""
    Write-Host "--- 7. the dash snapshot's fields, through the cards channel ---" -ForegroundColor Cyan
    $env:HORDE_HOME = $Q
    $wq = Write-Orc $Q "domain" @{ id = "lane-c"; domain = "Form fill" }
    # A domain that looks like a secret, put in by hand past the write's own refusal: the channel must
    # still not send it.
    [System.IO.File]::WriteAllText((Join-Path $Q ("orcs\registry\" + ($wq.version + 1).ToString("D10") + ".json")), ('{"schemaVersion":1,"sequence":' + ($wq.version + 1) + ',"kind":"orc-domain-set","at":"2026-10-15T12:00:00Z","actor":"cli","by":"console","data":{"id":"lane-d","domain":"token ghp_0123456789abcdefABCDEF0123456789abcd"}}'), $utf8)
    $set =(Get-HordeModuleSettings -Declaration (Get-HordeCardsChannelSettingsDeclaration) -HordeHome $Q).values
    $ctx = [pscustomobject]@{ horde = "work"; signKeyId = ("0" * 32); hordeHome = $Q }
    $snap = New-HordeCardsChannelSnapshot -Context $ctx -Settings $set -Paths (Get-HordeCardsChannelPaths -HordeHome $Q -Settings $set) -Now $now -Budget 60000
    $body = ConvertFrom-HordeJson $snap.body
    $first = @(Get-HordeTestMember $body "dash.orcs") | Select-Object -First 1
    $want = "id,letter,name,domain,order,backBurner,registered,open,status,age,since,statusText,sessions,wargsActive,wargsInactive,lastActivityAt,lastActivitySource"
    Check ((Get-HordeTestMember $body "dash.v") -eq 1 -and (Test-HordeTestMember $body "dash.version") -and (Get-HordeTestMember $body "dash.ok") -eq $true -and (Get-HordeTestMember $body "dash.orcsLeftOut") -eq 0 -and @(Get-HordeTestMember $body "dash.orcs").Count -eq 4) "the cards snapshot carries the dash: v 1, ok, the registry version, the Orcs, and how many were left out"
    Check ($null -ne $first -and (@($first.PSObject.Properties | ForEach-Object { $_.Name }) -join ",") -ceq $want) ("each Orc carries exactly its named fields, in order (" + $(if ($null -ne $first) { @($first.PSObject.Properties | ForEach-Object { $_.Name }) -join "," } else { "none" }) + ")")
    $cRow = @(Get-HordeTestMember $body "dash.orcs") | Where-Object { $_.id -ceq "lane-c" } | Select-Object -First 1
    Check ($null -ne $cRow -and $cRow.letter -ceq "C" -and $cRow.status -ceq "blocked" -and $cRow.open -eq 1 -and $cRow.statusText -like "blocked *" -and $cRow.backBurner -eq $false -and $cRow.domain -ceq "Form fill") "an Orc's letter, domain, status word with its age, open count and back-burner flag ride as the dash says them"
    Check ($wq.outcome -ceq "done" -and (Get-HordeTestMember $body "dash.version") -eq ($wq.version + 1)) ("the dash carries the registry's version, its last record (" + (Get-HordeTestMember $body "dash.version") + ")")
    Check ($snap.body -notlike "*ghp_*" -and (@(Get-HordeTestMember $body "dash.orcs") | Where-Object { $_.id -ceq "lane-d" } | Select-Object -First 1).domain -like "Not shown*") "a stored domain that looks like a secret is not sent: the refusal's sentence goes in its place"
    Check (@(Get-HordeTestMember $body "cards").Count -eq 4 -and (Test-HordeTestMember $body "thrall") -and $snap.body -cmatch '\A[\x20-\x7E]*\z') "the cards feed is still there beside it, and the body is ASCII"

    Write-Host ""
    Write-Host "--- 7b. a card's age is the lane's latest activity, and says its source ---" -ForegroundColor Cyan
    $G = New-Home "cardage"
    Set-Lane $G "lane-e" "E" -Ago (3 * 1440)
    Set-Lane $G "lane-f" "F" -Ago (3 * 1440)
    Set-Lane $G "lane-g" "G" -Ago 1
    Set-Lane $G "lane-h" "H" -Ago (3 * 1440)
    [System.IO.File]::WriteAllText((Join-Path $G "progress\changelog.jsonl"), ('{"v":1,"id":"p1","ts":"' + (& $iso $now.AddMinutes(-5)) + '","kind":"note","lane":"E,F","title":"two lanes","text":"x"}' + "`n" +
        '{"v":1,"id":"p2","ts":"' + (& $iso $now.AddMinutes(-30)) + '","kind":"note","lane":" G ","title":"older than G''s status","text":"x"}' + "`n"), $utf8)
    $null = Add-Question $G "Orc H" "part"
    $env:HORDE_HOME = $G
    $hAsked = ConvertFrom-HordeOrcTime "$((Invoke-HordeDecision -Operation 'show' -Request @{ number = 1 } -Root (Join-Path $G 'store\decisions')).value.question.addedAt)"
    $setG = (Get-HordeModuleSettings -Declaration (Get-HordeCardsChannelSettingsDeclaration) -HordeHome $G).values
    $snapG = New-HordeCardsChannelSnapshot -Context ([pscustomobject]@{ horde = "work"; signKeyId = ("0" * 32); hordeHome = $G }) -Settings $setG -Paths (Get-HordeCardsChannelPaths -HordeHome $G -Settings $setG) -Now $now -Budget 60000
    $bodyG = ConvertFrom-HordeJson $snapG.body
    $card = { param([string]$Lane) return (@(Get-HordeTestMember $bodyG "cards") | Where-Object { $_.lane -ceq $Lane } | Select-Object -First 1) }
    $ce = & $card "E"; $cf = & $card "F"; $cg = & $card "G"; $ch = & $card "H"
    Check ($null -ne $ce -and $ce.asOf -ceq (& $iso $now.AddMinutes(-5)) -and $ce.asOfSource -ceq "progress") ("a card whose status file is 3 days old and whose lane logged progress 5 minutes ago is aged from the progress, and says so (" + $(if ($null -ne $ce) { $ce.asOf + " " + $ce.asOfSource } else { "no card" }) + ")")
    Check ($null -ne $cf -and $cf.asOf -ceq (& $iso $now.AddMinutes(-5)) -and $cf.asOfSource -ceq "progress") "an entry tagged E,F freshens F's card as well as E's"
    Check ($null -ne $cg -and $cg.asOf -ceq (& $iso $now.AddMinutes(-1)) -and $cg.asOfSource -ceq "status") ("a card whose status file is newer than its progress is aged from its status (" + $(if ($null -ne $cg) { $cg.asOf + " " + $cg.asOfSource } else { "no card" }) + ")")
    Check ($null -ne $ch -and $null -ne $hAsked -and $ch.asOf -ceq (& $iso $hAsked) -and $ch.asOfSource -ceq "decision") ("a card whose lane asked a question since its status file is aged from the question (" + $(if ($null -ne $ch) { $ch.asOf + " " + $ch.asOfSource } else { "no card" }) + ")")
    $dashE = @(Get-HordeTestMember $bodyG "dash.orcs") | Where-Object { $_.id -ceq "lane-e" } | Select-Object -First 1
    $dashF = @(Get-HordeTestMember $bodyG "dash.orcs") | Where-Object { $_.id -ceq "lane-f" } | Select-Object -First 1
    Check ($null -ne $dashE -and $null -ne $dashF -and $dashE.lastActivityAt -ceq $ce.asOf -and $dashE.lastActivitySource -ceq "progress" -and $dashF.lastActivityAt -ceq $cf.asOf) "the dash's latest activity and the card's age are one value: an E,F entry is both E's and F's"

    Write-Host ""
    Write-Host "--- 8. horde orcs under both shells ---" -ForegroundColor Cyan
    $pwsh = Get-Command -Name "pwsh.exe" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $shells = @("powershell.exe")
    if ($null -ne $pwsh) { $shells += "pwsh.exe" } else { Write-Host "  [NOT RUN] pwsh.exe is not installed: the PowerShell 7 half is not run" -ForegroundColor Yellow; [void]$partial.Add("pwsh") }
    $C = New-Home "cli"
    Set-Lane $C "decisions-page" "F" -Ago 1
    Set-Lane $C "form-fill" "C" -Ago 1
    $i = 0
    foreach ($sh in $shells) {
        $i++
        $run = { param([string[]]$A) return (Invoke-HordeCliProcess -Root $root -HordeArgs (@("orcs") + $A) -Env @{ HORDE_HOME = $C } -Shell $sh) }
        $l = & $run @("list", "-Json")
        $line = @(@($l.out -split "\r?\n") | Where-Object { $_.StartsWith('{"v":') }) | Select-Object -First 1
        $j = $null; if ($null -ne $line) { $j = ConvertFrom-HordeJson $line }
        Check ($l.code -eq 0 -and $null -ne $j -and (Get-HordeTestMember $j "v") -eq 1 -and @(Get-HordeTestMember $j "orcs").Count -eq 2) ($sh + ": orcs list -Json prints the dash document (exit " + $l.code + ")")
        $ver = [long](Get-HordeTestMember $j "version")
        $dom = & $run @("domain", "F", ("Horde relay, set by " + $sh))
        Check ($dom.code -eq 0 -and $dom.out -like "*done*") ($sh + ": orcs domain takes the Orc's letter for its id (" + $dom.out.Trim() + ")")
        $st = & $run @("order", "C", "-BackBurner", "F", "-Version", ("" + $ver))
        Check ($st.code -eq 1 -and $st.out -like "*stale*") ($sh + ": an order drawn from the version before is refused as stale, exit 1")
        $miss = & $run @("order", "C")
        Check ($miss.code -eq 1 -and $miss.out -like "*leaves out decisions-page*") ($sh + ": an order that leaves an Orc out is refused, exit 1")
        $txt = & $run @("list")
        Check ($txt.code -eq 0 -and $txt.out -like "*Back-burner*" -and $txt.out -like ("*Horde relay, set by " + $sh + "*")) ($sh + ": orcs list prints the list, the divider and the domain the other shell's records hold")
        $bad = & $run @("order")
        Check ($bad.code -eq 2) ($sh + ": an order naming nobody is a wrong command line, exit 2")
    }
    $recsC = Get-Records $C
    Check (@($recsC | Where-Object { $_.kind -ceq "orc-domain-set" }).Count -eq $shells.Count -and (@($recsC | ForEach-Object { $_.sequence }) -join ",") -ceq ((1..$recsC.Count) -join ",")) "each shell's writes are records in one order, read whole by the other"
    $seedFile = Join-Path $work "seed.json"
    [System.IO.File]::WriteAllText($seedFile, '{"v":1,"domains":{"C":"Form fill and the second model; coordinates Horde","F":"Horde relay, decisions page, sign-in, pairing and setup","Z":"Nobody"}}', $utf8)
    $seed = Invoke-HordeCliProcess -Root $root -HordeArgs @("orcs", "seed", "-File", $seedFile) -Env @{ HORDE_HOME = $C }
    $dC = Get-Dash $C
    Check ($seed.code -eq 0 -and (Get-Row $dC "form-fill").domain -ceq "Form fill and the second model; coordinates Horde" -and (Get-Row $dC "decisions-page").domain -ceq "Horde relay, decisions page, sign-in, pairing and setup" -and $seed.out -like "*no Orc on the list has the letter Z*") ("seed sets every domain by letter in one step, and says which letter has no Orc (" + $seed.out.Trim() + ")")
    $again = Invoke-HordeCliProcess -Root $root -HordeArgs @("orcs", "seed", "-File", $seedFile) -Env @{ HORDE_HOME = $C }
    Check ($again.code -eq 0 -and $again.out -like "*already set*" -and @(Get-Records $C).Count -eq $recsC.Count + 2) "seed run again writes nothing new"

    Write-Host ""
    Write-Host "--- 9. the PC's lane rule is the decisions page's ---" -ForegroundColor Cyan
    $names = @("Orc C", "Orc E", "Orc F1", "Orc B, for the fleet", "M (Thrall)", "Thrall", "", $null, "someone", "orc c", "Orchard", "Orc Fred", "B (by hand)", "Orc F123", "Orc F1234", "M", "Orc M", "X1", "Q", " Orc C")
    $mine = @($names | ForEach-Object { Get-HordeOrcQuestionLane $_ })
    $node = Get-Command -Name "node" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $node) { Write-Host "  [NOT RUN] node is not installed: the page's and the phone's rules are not run" -ForegroundColor Yellow; [void]$partial.Add("node") }
    else {
        $runNode = {
            # node <script> <a> <b>: { code; out } - out its one line of JSON, parsed.
            param([string]$Script, [string]$A, [string]$B)
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $node.Source
            $psi.Arguments = '"' + $Script + '" "' + $A + '" "' + $B + '"'
            $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
            $p = [System.Diagnostics.Process]::Start($psi)
            try { $errTask = $p.StandardError.ReadToEndAsync(); $out = $p.StandardOutput.ReadToEnd(); $p.WaitForExit(); $code = $p.ExitCode } finally { $p.Dispose() }
            $parsed = $null; try { $parsed = ConvertFrom-HordeJson $out.Trim() } catch { $parsed = $null }
            return [pscustomobject]@{ code = $code; out = $parsed; err = $errTask.Result }
        }
        $namesFile = Join-Path $work "names.json"
        [System.IO.File]::WriteAllText($namesFile, (ConvertTo-Json -InputObject @($names) -Compress), $utf8)
        $r = & $runNode (Join-Path $root "orcs\test\lane-of.mjs") (Join-Path $root "decisions\page\list.js") $namesFile
        $theirs = @(@($r.out) | ForEach-Object { $_ })
        $diff = @(for ($k = 0; $k -lt $names.Count; $k++) { if ($k -ge $theirs.Count -or "$($theirs[$k])" -cne "$($mine[$k])") { "'" + $names[$k] + "': page " + $(if ($k -lt $theirs.Count) { $theirs[$k] } else { "(none)" }) + ", PC " + $mine[$k] } })
        Check ($r.code -eq 0 -and $theirs.Count -eq $names.Count -and $diff.Count -eq 0) ("the PC reads the lane of every name in the table exactly as the page does (" + $(if ($diff.Count -gt 0) { $diff -join "; " } else { "" + $names.Count + " names" }) + ")")
        Check ("$($mine[2])" -ceq "F1" -and "$($mine[4])" -ceq "thrall" -and "$($mine[11])" -ceq "thrall") "CONTROL: the table holds an Orc's sub-lane and the Thrall's lane, so it can tell the rules apart"

        Write-Host ""
        Write-Host "--- 10. the PC's entry-lanes rule is the phone's ---" -ForegroundColor Cyan
        $casesJson = '{"areas":[{"area":"Alpha","lanes":["A","decisions-page"]},{"area":"Beta","lanes":["B"]}],"entries":[' +
            '{"lane":"E,F"},{"lane":" F "},{"area":"Alpha"},{"area":" alpha "},{},{"lane":"","area":"Alpha"},{"lane":"B","area":"Alpha"},' +
            '{"lane":" , "},{"area":"Nowhere"},{"lane":["E","F"]},{"lane":7},{"lane":0,"area":"Beta"},{"lane":null,"area":"Beta"},{"lane":"B,C,D,E,F"},{"lane":false,"area":"beta"},{"area":"Al pha"}]}'
        $casesFile = Join-Path $work "entries.json"
        [System.IO.File]::WriteAllText($casesFile, $casesJson, $utf8)
        $cases = ConvertFrom-HordeJson $casesJson
        $pcLanes = @(@($cases.entries) | ForEach-Object { , @(Get-HordeOrcEntryLanes -Entry $_ -Areas @($cases.areas)) })
        $r2 = & $runNode (Join-Path $root "orcs\test\entry-lanes.mjs") (Join-Path $root "relay\js\protocol.js") $casesFile
        $phone = @(@($r2.out) | ForEach-Object { , @($_) })
        $diff2 = @(for ($k = 0; $k -lt @($cases.entries).Count; $k++) { $a = $(if ($k -lt $phone.Count) { @($phone[$k]) -join "|" } else { "(none)" }); $b = @($pcLanes[$k]) -join "|"; if ($a -cne $b) { "entry " + $k + ": phone [" + $a + "], PC [" + $b + "]" } })
        Check ($r2.code -eq 0 -and $phone.Count -eq @($cases.entries).Count -and $diff2.Count -eq 0) ("the PC reads the lanes of every entry in the table exactly as the phone does (" + $(if ($diff2.Count -gt 0) { $diff2 -join "; " } else { "" + $phone.Count + " entries" }) + "; " + "$($r2.err)".Trim() + ")")
        Check ((@($pcLanes[0]) -join "|") -ceq "E|F" -and (@($pcLanes[1]) -join "|") -ceq "F" -and (@($pcLanes[2]) -join "|") -ceq "A|decisions-page" -and @($pcLanes[4]).Count -eq 0 -and (@($pcLanes[6]) -join "|") -ceq "B") "CONTROL: the table holds a two-lane entry, a padded lane, an area-only entry, a no-lane entry and an own lane that wins over its area"
    }
} finally {
    $env:HORDE_HOME = $realHome
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    if ((Split-Path -Leaf $work) -match '^horde-orcs-test-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
if ($partial.Count -gt 0) { Complete-HordeSuite -Success ("every check run passed; NOT RUN: " + ($partial -join ", ")) -PassCode 3 }
Complete-HordeSuite -Success "the Orc registry folds write-once records, registers new lanes at the end, derives status, Wargs and open questions, refuses bad and stale orders, and the dash rides in the cards snapshot - under both shells"
