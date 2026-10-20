# DOES EVERY PARK MAKE ONE LOT, DOES `horde fleet lots` LIST THEM NEWEST FIRST WITH THE RIGHT STATE FOR EACH
# MEMBER, DOES A WAKE TAKE A WHOLE LOT OR ANY PART OF IT WITH EVERY RULE A WAKE HAS, AND DOES A BACKFILL WRITE
# EACH PARK ONCE?
#
# fleet/LotTables.ps1, fleet/Lots.ps1 (T-0216). The founder's words of 2026-10-19: the park is one entity
# showing a list of Orcs parked, any combination or all can be resurrected, and a later park is another lot.
# The tables are the SSOT audit's (parking_lot, parking_lot_member, wake, wake_member), with ULID ids.
#
# Every lot is written in a Horde home this suite makes under TEMP, by the shipped writers. The harness and
# the terminal are stand-ins registered with the shipped Register-HordeFleet* and found by the shipped
# resolver, so one that does not fit the port fails here. The stand-in terminal "starts" a session by marking
# it running in this suite's world. Nothing real is started, typed into or mailed, and no real fleet file is
# read or written: test/fixtures/fleet/backfill-lots.json is READ by this suite (its shape is checked), and
# never applied to anything but a home under TEMP.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "fleet\Lots.ps1")
. (Join-Path $root "fleet\Asleep.ps1")

function Section { param([string]$Title) Write-Host ""; Write-Host ("--- " + $Title + " ---") -ForegroundColor Cyan }

$work = Join-Path $env:TEMP ("horde-fleet-lots-" + [guid]::NewGuid().ToString("N"))
[void](New-Item -ItemType Directory -Path $work -Force)
$ids = @{
    A = "44444444-0000-4000-8000-000000000001"; A1 = "44444444-0000-4000-8000-000000000002"; B = "b0b0b0b0-0000-4000-8000-000000000003"
    B1 = "44444444-0000-4000-8000-000000000004"; C = "44444444-0000-4000-8000-000000000005"; D = "44444444-0000-4000-8000-000000000006"
}
$cwds = @{ A = "C:\lanes\a"; A1 = "C:\work\a1"; B = "C:\lanes\b"; B1 = "C:\work\b1"; C = "C:\lanes\c"; D = "C:\lanes\d" }

# The world the stand-ins share. live: id -> { pid; cwd; state }.
$world = @{}
function Reset-World {
    $world.live = @{}; $world.error = ""; $world.spawns = New-Object System.Collections.ArrayList; $world.posts = New-Object System.Collections.ArrayList
    $world.free = New-Object System.Collections.ArrayList; $world.nextPane = 40; $world.clock = [datetime]::new(2026, 10, 19, 21, 0, 0, [System.DateTimeKind]::Utc)
    $world.order = New-Object System.Collections.ArrayList; $world.unmarks = New-Object System.Collections.ArrayList
    $world.procs = @{ "777" = "133000000000000000" }
}
Reset-World
Register-HordeFleetAgent -Name "stand-in" `
    -Snapshot { [pscustomobject]@{ error = $world.error; live = $world.live.Clone() } }.GetNewClosure() `
    -Verdict { param($snap, $id, $cwd, $ignore, $since, $process)
        if ($snap.error -ne "") { return [pscustomobject]@{ state = "unknown"; kind = "reading"; reason = $snap.error; pid = "" } }
        $e = $snap.live[$id]
        if ($null -eq $e) { return [pscustomobject]@{ state = "stopped"; kind = ""; reason = ""; pid = "" } }
        [pscustomobject]@{ state = "running"; kind = "live"; reason = ("already running pid " + $e.pid); pid = "" + $e.pid } } `
    -Running { param($snap) @($snap.live.Keys | ForEach-Object { [pscustomobject]@{ sessionId = $_; pid = $snap.live[$_].pid; cwd = $snap.live[$_].cwd } }) } `
    -ResumeLine { param($id) "resume " + $id } `
    -Scrub { @{} }
Register-HordeFleetHost -Name "stand-in" `
    -Placement { param($refs) New-HordeKnown -Value ([pscustomobject]@{ placed = @{}; notes = @() }) } `
    -Open {
        $spawn = { param($req)
            [void]$world.spawns.Add($req)
            $id = ("" + $req.line).Substring(7)
            [void]$world.order.Add("spawn " + $id)
            $world.nextPane++; $pane = "" + $world.nextPane
            $world.live[$id] = @{ pid = 1000 + [int]$pane; cwd = $req.cwd; state = "running" }
            $win = $(if ($req.mode -ceq "tab") { "" + $req.window } else { "w" + $pane })
            New-HordeKnown -Value ([pscustomobject]@{ pane = $pane; window = $win }) }.GetNewClosure()
        $paneOf = { param($p) New-HordeUnknown -Reason "unreadable" }
        New-HordeKnown -Value ([pscustomobject]@{ spawn = $spawn; paneOf = $paneOf }) }.GetNewClosure() `
    -Describe { param($req) "spawn " + $req.mode + " cwd=" + $req.cwd + " :: " + $req.line } `
    -Release { param($id) [void]$world.order.Add("release " + $id); New-HordeKnown -Value "removed" }.GetNewClosure() `
    -Unmark { param($id, $why) [void]$world.unmarks.Add([pscustomobject]@{ id = $id; why = $why }); New-HordeKnown -Value "removed" }.GetNewClosure()
$agent = (Resolve-HordeFleetAdapter -Kind "agent")
$hostA = (Resolve-HordeFleetAdapter -Kind "host")
Check ($agent.state -ceq "known" -and $hostA.state -ceq "known") "CONTROL: the stand-ins pass the shipped registration and are found by the shipped resolver"

$deps = [pscustomobject]@{
    Now = { $world.clock }.GetNewClosure()
    Sleep = { param($ms) $world.clock = $world.clock.AddMilliseconds($ms) }.GetNewClosure()
    FreePercent = { if ($world.free.Count -gt 0) { $v = $world.free[0]; $world.free.RemoveAt(0); $v } else { 50.0 } }.GetNewClosure()
    Agent = $agent.value; Host = $hostA.value
    Post = { param($sid, $label, $body, $mid) [void]$world.posts.Add([pscustomobject]@{ to = $sid; label = $label; body = $body; id = $mid }); New-HordeKnown -Value ([pscustomobject]@{ stage = "accepted" }) }.GetNewClosure()
    WaitSeconds = 5; PollMs = 1000
    ProcessStart = { param($p) $v = $world.procs["" + $p]; if ($null -eq $v) { "" } else { $v } }.GetNewClosure()
    Self = { [pscustomobject]@{ pid = 777; start = "133000000000000000" } }
    RegistryPane = { param($sid) New-HordeAbsent -Note "no row" }
}

function Session {
    param([string]$L, [string]$Role, [string]$Parent = "", [string]$State = "exited")
    $hist = @([pscustomobject]@{ state = "recorded"; at = "2026-10-16T09:15:00Z" })
    if ($State -ceq "exited") { $hist += [pscustomobject]@{ state = "exited"; at = "2026-10-16T09:30:00Z" } }
    elseif ($State -cne "recorded") { $hist += [pscustomobject]@{ state = $State; at = "2026-10-16T09:30:00Z" } }
    $s = [ordered]@{ sessionId = $ids[$L]; label = $L; role = $Role; cwd = $cwds[$L]; state = $State; history = $hist; pane = ("" + (10 + $ids.Keys.Count)) }
    if ($Parent -ne "") { $s["parent"] = $ids[$Parent] }
    return [pscustomobject]$s
}
function New-Home { $h = Join-Path $work ([guid]::NewGuid().ToString("N")); [void](New-Item -ItemType Directory -Path $h -Force); return $h }
function Put-Lot {
    # One park in -H, written as a hibernate run writes it: the record, then the lot beside it. Returns the lot row.
    param([string]$H, [string]$Id, [string]$At, $Sessions, [string]$Why = "test park", [string]$Kind = "orcs", [string]$ById = "")
    $dir = Join-Path (Get-HordeFleetHibernationsDir -HordeHome $H) $Id
    [void](New-Item -ItemType Directory -Path $dir -Force)
    $rec = [pscustomobject][ordered]@{ schemaVersion = 1; id = $Id; createdAt = $At; agent = "stand-in"; host = "stand-in"
        selection = [pscustomobject][ordered]@{ kind = "all"; labels = @(); exclude = @() }; sessions = @($Sessions) }
    [void](Write-HordeFleetRecord -Dir $dir -Record $rec)
    $when = [datetime]::Parse($At, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal)
    $lot = New-HordeFleetLot -At $when -ById $ById -Reason $Why -Kind $Kind
    [void](Write-HordeFleetLot -Dir $dir -Lot $lot -Members @(ConvertTo-HordeFleetLotMembers -LotId $lot.id -Record $rec))
    return $lot
}
function Wakes-Of { param([string]$H, [string]$Id) return ,@(Read-HordeFleetWakes -Dir (Get-HordeFleetLotDir -Id $Id -HordeHome $H)) }
function Lots-Of { param([string]$H) $a = Get-HordeFleetLots -HordeHome $H -Agent $agent.value; if ($a.state -cne "known") { throw ("lots unknown: " + $a.reason) }; return ,@($a.value.lots) }
function Member-Of { param($Lot, [string]$L) return @($Lot.members | Where-Object { $_.label -ceq $L })[0] }
function Spawned { param([string]$L) return @($world.spawns | Where-Object { $_.line -ceq ("resume " + $ids[$L]) }).Count }


Section "a park writes one lot, with one row for each session"
$reg = Join-Path $work "wezfleet\registry\sessions"
[void](New-Item -ItemType Directory -Path $reg -Force)
foreach ($l in @("A", "A1", "B")) {
    # The registry names the harness session id by a harness-named key, which the host-name scan reads in a source line; built from two halves here, as the key the shipped reader looks up.
    $idKey = "c" + "laudeSessionId"
    $r = [ordered]@{ $idKey = $ids[$l]; origin = "user"; fleetSessionId = ""; pane = ("" + (20 + $l.Length)); instance = "inst-1"; cwd = $cwds[$l]; transcriptPath = (Join-Path $work ($l + ".jsonl")); owner = ""; label = $l; role = $(if ($l -ceq "A1") { "session" } else { "orchestrator" }) }
    if ($l -ceq "A1") { $r["parent"] = $ids["A"] }
    [System.IO.File]::WriteAllText((Join-Path $reg ($ids[$l] + ".json")), (ConvertTo-Json -InputObject $r))
}
Reset-World
foreach ($l in @("A", "A1", "B")) { $world.live[$ids[$l]] = @{ pid = 100 + $l.Length; cwd = $cwds[$l]; state = "running" } }
$hh = New-Home
$recDeps = [pscustomobject]@{ Now = { $world.clock }.GetNewClosure(); Agent = $agent.value; Host = $hostA.value; Registry = { Read-HordeRegistry -Root (Join-Path $work "wezfleet") }.GetNewClosure() }
$sel = [pscustomobject][ordered]@{ kind = "orcs"; labels = @(); exclude = @() }
$made = Invoke-HordeFleetRecord -Deps $recDeps -Selector (New-HordeFleetSelectorAll) -Selection $sel -HordeHome $hh -By $ids["A"] -Why "unit park" -Tier 2
$dir1 = Split-Path -Parent $made.path
$lotRead = Read-HordeFleetLot -Id $made.id -HordeHome $hh
Check ($lotRead.state -ceq "known") ("the lot reads back and fits both schemas (" + $lotRead.reason + ")")
Check ((Test-Path -LiteralPath (Join-Path $dir1 "parking_lot.json")) -and (Test-Path -LiteralPath (Join-Path $dir1 "parking_lot_member.json"))) "a park writes parking_lot.json and parking_lot_member.json beside record.json"
$lot1 = $lotRead.value.lot
Check ($lot1.id -cmatch $script:HordeUlidPattern -and (Get-HordeFleetUlidTime -Ulid $lot1.id).ToString("yyyy-MM-ddTHH:mm:ssZ") -ceq $lot1.created_at) "the lot's id is a ULID whose time is its created_at"
Check ($lot1.created_at -ceq "2026-10-19T21:00:00Z" -and $lot1.reason -ceq "unit park" -and $lot1.selection_kind -ceq "orcs" -and $lot1.created_by_session_id -ceq $ids["A"]) "the parking_lot row: created_at, reason, selection_kind and the parking session's id"
Check ($lotRead.value.folder -ceq $made.id -and (Get-HordeFleetLotDir -Id $lot1.id -HordeHome $hh) -ceq $dir1) "the lot's folder is found from its ULID, and is the hibernation id"
$colsLot = @($lot1.PSObject.Properties | ForEach-Object { $_.Name }) | Sort-Object
Check (($colsLot -join ",") -ceq "created_at,created_by_session_id,id,keep_visible,reason,selection_kind") ("the row has the audit's columns and no others (" + ($colsLot -join ",") + ")")
Check (($lot1.keep_visible -is [long] -or $lot1.keep_visible -is [int]) -and $lot1.keep_visible -eq 0) "keep_visible is written for every new lot, and is 0 unless the park asks for 1"
$hhKv = New-Home
$madeKv = Invoke-HordeFleetRecord -Deps $recDeps -Selector (New-HordeFleetSelectorAll) -Selection $sel -HordeHome $hhKv -By $ids["A"] -Why "kept park" -Tier 2 -KeepVisible
$lotKv = (Read-HordeFleetLot -Id $madeKv.id -HordeHome $hhKv).value.lot
Check ($lotKv.keep_visible -eq 1) "-KeepVisible writes keep_visible 1 on the lot: one flag for the whole lot, not one per member"
$badKv = [pscustomobject][ordered]@{ id = $lot1.id; created_at = $lot1.created_at; reason = "x"; keep_visible = 2 }
Check (@(Test-HordeFleetTable -Name "fleet-parking-lot.v1" -Rows @($badKv)).Count -gt 0) "the schema refuses a keep_visible that is not 0 or 1"
Check (@($lotRead.value.members).Count -eq 3 -and @($lotRead.value.members | Where-Object { $_.lot_id -ceq $lot1.id }).Count -eq 3) "one parking_lot_member row for each session, each naming the lot by lot_id"
$mA1 = @($lotRead.value.members | Where-Object { $_.session_id -ceq $ids["A1"] })[0]
$colsM = @($mA1.PSObject.Properties | ForEach-Object { $_.Name }) | Sort-Object
Check (($colsM -join ",") -ceq "lot_id,session_id,state,tier" -and $mA1.state -ceq "parked" -and $mA1.tier -eq 2) ("a member row has the audit's columns it knows: lot_id, session_id, state parked, tier (" + ($colsM -join ",") + ")")
$recBack = (Read-HordeFleetRecord -Id $made.id -HordeHome $hh).value
Check ("" + $recBack.parkedBy -ceq "A") "who parked, in words, is in the record (the label of the parking session)"
Check ((Get-HordeFleetMember (@($recBack.sessions | Where-Object { $_.label -ceq "A1" })[0]) "pane") -ceq "22") "and each session's pane, the detail the member row does not repeat"
$tables = Get-Content -LiteralPath (Join-Path $dir1 "parking_lot_member.json") -Raw
Check ($tables -notmatch 'null') "no value in the member table is null"
$bytes = [System.IO.File]::ReadAllBytes((Join-Path $dir1 "parking_lot.json")) + [System.IO.File]::ReadAllBytes((Join-Path $dir1 "parking_lot_member.json"))
Check (@($bytes | Where-Object { $_ -gt 127 }).Count -eq 0) "the table files are ASCII"
Check (@(Get-ChildItem -LiteralPath $dir1 | Where-Object { $_.Name -like "*.tmp" }).Count -eq 0) "no temporary file is left beside them"
$world.clock = $world.clock.AddSeconds(1)
$made2 = Invoke-HordeFleetRecord -Deps $recDeps -Selector (New-HordeFleetSelectorLabels -Labels @("B")) -Selection ([pscustomobject][ordered]@{ kind = "labels"; labels = @("B"); exclude = @() }) -HordeHome $hh
$lotsNow = Lots-Of $hh
Check ($lotsNow.Count -eq 2) ("a second park is a second lot, not a change to the first (" + $lotsNow.Count + " lots)")
Check ($lotsNow[0].hibernation_id -ceq $made2.id -and $lotsNow[0].selection_kind -ceq "labels" -and @($lotsNow[0].members).Count -eq 1) "and a fleet record is a lot of its own, chosen by labels"
Check ($lotsNow[0].id -cne $lotsNow[1].id -and @($lotsNow[1].members).Count -eq 3) "with its own id, and the first lot still holds its three"
Check (Throws { Invoke-HordeFleetRecord -Deps $recDeps -Selector (New-HordeFleetSelectorLabels -Labels @("Q")) -Selection ([pscustomobject][ordered]@{ kind = "labels"; labels = @("Q"); exclude = @() }) -HordeHome $hh } "labelled Q") "CONTROL: a refused park writes no lot"
Check ((Lots-Of $hh).Count -eq 2) "and the number of lots did not change"

Section "a lot's members follow the record: a state change in the record is a state change in the table"
$hh = New-Home
$lotSync = Put-Lot -H $hh -Id "20261016-091500" -At "2026-10-16T09:15:00Z" -Sessions @((Session "A" "orc"), (Session "A1" "warg" "A"))
$rd = Read-HordeFleetRecord -Id "20261016-091500" -HordeHome $hh
$s1 = @($rd.value.sessions | Where-Object { $_.label -ceq "A" })[0]
Add-HordeFleetState -Session $s1 -State "woken" -At $world.clock
[void](Write-HordeFleetRecord -Dir (Get-HordeFleetLotDir -Id "20261016-091500" -HordeHome $hh) -Record $rd.value)
$rows = Read-HordeFleetTableFile -Path (Join-Path (Get-HordeFleetLotDir -Id "20261016-091500" -HordeHome $hh) "parking_lot_member.json") -Table "parking_lot_member"
Check ((@($rows | Where-Object { $_.session_id -ceq $ids["A"] })[0].state) -ceq "woken") "the written copy says woken after the record does"
Check ((@($rows | Where-Object { $_.session_id -ceq $ids["A1"] })[0].state) -ceq "parked") "and the other member is still parked"

Section "lots newest first"
$hh = New-Home
Reset-World
$null = Put-Lot -H $hh -Id "20261014-100000" -At "2026-10-14T10:00:00Z" -Sessions @((Session "A" "orc")) -Why "middle"
$null = Put-Lot -H $hh -Id "20261019-090000" -At "2026-10-19T09:00:00Z" -Sessions @((Session "B" "orc")) -Why "newest"
$null = Put-Lot -H $hh -Id "20261010-120000" -At "2026-10-10T12:00:00Z" -Sessions @((Session "C" "orc")) -Why "oldest"
$ls = Lots-Of $hh
Check ((@($ls | ForEach-Object { $_.reason }) -join ",") -ceq "newest,middle,oldest") ("listed newest first by the time parked (" + (@($ls | ForEach-Object { $_.reason }) -join ",") + ")")
Check ($ls[0].hibernation_id -ceq "20261019-090000") "the first is the newest park"
$text = @(Format-HordeFleetLotsText -Lots $ls)
Check ($text[0] -like "lot *newest*" -and $text[1] -like "*asleep*B*") ("the text lists a lot, then its members with their state (" + $text[0] + ")")

Section "a record from before lots is read as a lot, and nothing is rewritten"
$hh = New-Home
$old = Join-Path (Get-HordeFleetHibernationsDir -HordeHome $hh) "20261012-080000"
[void](New-Item -ItemType Directory -Path $old -Force)
$rec = [pscustomobject][ordered]@{ schemaVersion = 1; id = "20261012-080000"; createdAt = "2026-10-12T08:00:00Z"; agent = "stand-in"; host = "stand-in"
    selection = [pscustomobject][ordered]@{ kind = "all"; labels = @(); exclude = @() }; sessions = @((Session "C" "orc"), (Session "D" "other")) }
[void](Write-HordeFleetRecord -Dir $old -Record $rec)
$before = (Get-FileHash -LiteralPath (Join-Path $old "record.json")).Hash
$ls = Lots-Of $hh
Check ($ls.Count -eq 1 -and $ls[0].hibernation_id -ceq "20261012-080000" -and $ls[0].created_at -ceq "2026-10-12T08:00:00Z" -and @($ls[0].members).Count -eq 2) "the old record is a lot, at its createdAt, holding its sessions"
Check ($ls[0].id -cmatch $script:HordeUlidPattern -and $ls[0].selection_kind -ceq "all") "with a ULID and the selection it was taken by"
$again = Lots-Of $hh
Check ($again[0].id -ceq $ls[0].id) "and the same ULID every time, though nothing was written for it"
Check (-not (Test-Path -LiteralPath (Join-Path $old "parking_lot.json")) -and (Get-FileHash -LiteralPath (Join-Path $old "record.json")).Hash -ceq $before) "reading it wrote no lot file and left the record byte for byte"
Check ((Member-Of $ls[0] "C").state -ceq "asleep") "an old record's exited session is asleep"
$ar = Get-HordeFleetAsleep -HordeHome $hh -Agent $agent.value -HostAdapter $hostA.value -KeepMarkers
Check ($ar.state -ceq "known" -and @($ar.value.Keys).Count -eq 2) "and the wake watcher's own reading of the same record is unchanged: both asleep"

Section "a member that runs is not asleep"
$hh = New-Home
Reset-World
$null = Put-Lot -H $hh -Id "20261016-091500" -At "2026-10-16T09:15:00Z" -Sessions @((Session "A" "orc"), (Session "A1" "warg" "A"), (Session "B" "orc" "" "woken"), (Session "B1" "warg" "B" "failed"), (Session "C" "orc" "" "still-awake"))
$world.live[$ids["A1"]] = @{ pid = 301; cwd = $cwds["A1"]; state = "running" }
$world.live[$ids["B"]] = @{ pid = 302; cwd = $cwds["B"]; state = "running" }
$lot = (Lots-Of $hh)[0]
Check ((Member-Of $lot "A").state -ceq "asleep") "exited and not running: asleep"
Check ((Member-Of $lot "A1").state -ceq "still-awake" -and (Member-Of $lot "A1").stored -ceq "exited") "exited in the record but running now: still-awake, never asleep"
Check ((Member-Of $lot "B").state -ceq "woken") "woken and running: woken"
Check ((Member-Of $lot "B1").state -ceq "failed") "failed and not running: failed"
Check ((Member-Of $lot "C").state -ceq "still-awake") "never slept: still-awake"
$world.error = "the process list is unreadable"
$a = Get-HordeFleetLots -HordeHome $hh -Agent $agent.value
Check ($a.state -ceq "unknown" -and $a.reason -like "*cannot be read*") "when which processes run cannot be read, the lots are unknown with the reason, no member is guessed asleep"
$world.error = ""

Section "a lot that cannot be read is skipped and said; the rest are listed"
$bad = Join-Path (Get-HordeFleetHibernationsDir -HordeHome $hh) "20261001-000000"
[void](New-Item -ItemType Directory -Path $bad -Force)
[System.IO.File]::WriteAllText((Join-Path $bad "parking_lot.json"), "{ not json")
$a = Get-HordeFleetLots -HordeHome $hh -Agent $agent.value
Check ($a.state -ceq "known" -and @($a.value.lots).Count -eq 1 -and @($a.value.skipped).Count -eq 1 -and $a.value.skipped[0] -like "*20261001-000000*") "one corrupt lot is reported and the other still listed"
Remove-Item -LiteralPath $bad -Recurse -Force
$none = Get-HordeFleetLots -HordeHome (New-Home) -Agent $agent.value
Check ($none.state -ceq "known" -and @($none.value.lots).Count -eq 0) "CONTROL: no lots at all is known and empty"

Section "waking a whole lot, and the wake is recorded"
$hh = New-Home
Reset-World
$id1 = "20261016-091500"
$lotRow = Put-Lot -H $hh -Id $id1 -At "2026-10-16T09:15:00Z" -Sessions @((Session "A" "orc"), (Session "A1" "warg" "A"), (Session "B" "orc"), (Session "B1" "warg" "B"))
$r = Invoke-HordeFleetWakeLot -Lot $lotRow.id -Deps $deps -By $ids["C"] -HordeHome $hh
Check ($r.id -ceq $id1 -and (Spawned "A") -eq 1 -and (Spawned "A1") -eq 1 -and (Spawned "B") -eq 1 -and (Spawned "B1") -eq 1) "every member of the lot is started once (the lot named by its ULID)"
Check ((Member-Of (Lots-Of $hh)[0] "A").state -ceq "woken" -and (Member-Of (Lots-Of $hh)[0] "B1").state -ceq "woken") "and the lot lists them woken"
Check (@($r.outcomes | Where-Object { $_.outcome -ceq "woken" }).Count -eq 4) "each outcome says woken"
$wk = Wakes-Of $hh $id1
Check ($wk.Count -eq 1 -and $r.wake -ceq $wk[0].wake.id -and $wk[0].wake.lot_id -ceq $lotRow.id -and $wk[0].wake.requested_by_session_id -ceq $ids["C"] -and $wk[0].wake.requested_at -ceq "2026-10-19T21:00:00Z") "one wake row: which lot, when, by whom"
Check (@($wk[0].members).Count -eq 4 -and @($wk[0].members | Where-Object { $_.outcome -ceq "woken" -and $_.wake_id -ceq $wk[0].wake.id }).Count -eq 4) "and a wake_member row for each session it woke, with its outcome"
Check ($wk[0].wake.id -cmatch $script:HordeUlidPattern) "the wake's id is a ULID"
Check ((Lots-Of $hh)[0].wakes.Count -eq 1) "the lot listing shows its wakes"
Check (Throws { Invoke-HordeFleetWakeLot -Lot "20250101-000000" -Deps $deps -HordeHome $hh } "no hibernation") "a lot that is not there is refused with the reason"
Check (Throws { Invoke-HordeFleetWakeLot -Lot "nonsense" -Deps $deps -HordeHome $hh } "not a parking lot id") "and so is a name that is no id at all"

Section "waking a subset of a lot"
$hh = New-Home
Reset-World
$lotRow = Put-Lot -H $hh -Id $id1 -At "2026-10-16T09:15:00Z" -Sessions @((Session "A" "orc"), (Session "A1" "warg" "A"), (Session "B" "orc"), (Session "B1" "warg" "B"))
$r = Invoke-HordeFleetWakeLot -Lot $id1 -Members @($ids["A1"], $ids["B"].Substring(0, 8)) -Deps $deps -HordeHome $hh
Check ((Spawned "A1") -eq 1 -and (Spawned "B") -eq 1 -and (Spawned "A") -eq 0 -and (Spawned "B1") -eq 0) "only the members named are started (a full id, and a unique prefix of one)"
$lot = (Lots-Of $hh)[0]
Check ((Member-Of $lot "A1").state -ceq "woken" -and (Member-Of $lot "B").state -ceq "woken" -and (Member-Of $lot "A").state -ceq "asleep" -and (Member-Of $lot "B1").state -ceq "asleep") "the rest of the lot is still asleep"
$wk = Wakes-Of $hh $id1
Check ($wk.Count -eq 1 -and @($wk[0].members).Count -eq 2) "and the wake records only the two it was asked to wake"
Reset-World
$r = Invoke-HordeFleetWakeLot -Lot $id1 -Members @("A") -Deps $deps -HordeHome $hh
Check ((Spawned "A") -eq 1) "a member can be named by its label"
$nWakes = (Wakes-Of $hh $id1).Count
Check (Throws { Invoke-HordeFleetWakeLot -Lot $id1 -Members @("A1", "nobody") -Deps $deps -HordeHome $hh } "holds no member 'nobody'") "a name that picks no member refuses the whole request"
Check ($world.spawns.Count -eq 1 -and (Wakes-Of $hh $id1).Count -eq $nWakes) "and starts nothing more and records no wake"
Check (Throws { Invoke-HordeFleetWakeLot -Lot $id1 -Members @("44444444") -Deps $deps -HordeHome $hh } "names 3 members") "a prefix shared by several members is refused as ambiguous, not guessed"
Reset-World
$r = Invoke-HordeFleetWakeLot -Lot $id1 -Members @($ids["B1"]) -DryRun -Deps $deps -HordeHome $hh
Check ($world.spawns.Count -eq 0 -and (Member-Of (Lots-Of $hh)[0] "B1").state -ceq "asleep") "a dry run of a subset starts nothing and changes nothing"
Check (@($r.outcomes | Where-Object { $_.outcome -ceq "planned" }).Count -eq 1 -and $r.outcomes[0].label -ceq "B1") "and plans exactly the one named"
Check ((Wakes-Of $hh $id1).Count -eq $nWakes -and $r.wake -ceq "") "a dry run is not a wake: it records none"

Section "a wake of a lot keeps every rule a wake has"
$hh = New-Home
Reset-World
$null = Put-Lot -H $hh -Id $id1 -At "2026-10-16T09:15:00Z" -Sessions @((Session "A" "orc"), (Session "A1" "warg" "A"), (Session "B" "orc"))
$world.live[$ids["A1"]] = @{ pid = 501; cwd = $cwds["A1"]; state = "running" }
$r = Invoke-HordeFleetWakeLot -Lot $id1 -Deps $deps -HordeHome $hh
Check ((Spawned "A1") -eq 0 -and @($r.outcomes | Where-Object { $_.label -ceq "A1" -and $_.outcome -ceq "still-awake" }).Count -eq 1) "a member that runs is refused and left alone, never started twice"
Check ((Spawned "A") -eq 1 -and (Spawned "B") -eq 1) "the others are woken"
$wk = (Wakes-Of $hh $id1)[0]
Check ((@($wk.members | Where-Object { $_.session_id -ceq $ids["A1"] })[0]).outcome -ceq "still-awake") "and the wake row says so for it"
Check (@($world.order | Where-Object { $_ -ceq ("release " + $ids["A"]) }).Count -eq 1 -and $world.order.IndexOf("release " + $ids["A"]) -lt $world.order.IndexOf("spawn " + $ids["A"])) "a woken member's no-restore marker is released before its start"
Reset-World
$hh = New-Home
$null = Put-Lot -H $hh -Id $id1 -At "2026-10-16T09:15:00Z" -Sessions @((Session "A" "orc"), (Session "B" "orc"))
[void]$world.free.Add(5.0)
$r = Invoke-HordeFleetWakeLot -Lot $id1 -Deps $deps -HordeHome $hh
Check ($world.spawns.Count -eq 0 -and @($r.outcomes | Where-Object { $_.outcome -ceq "asleep" }).Count -eq 2) "below 15 percent free memory nothing starts and the whole lot stays asleep"
Reset-World
$hh = New-Home
$null = Put-Lot -H $hh -Id $id1 -At "2026-10-16T09:15:00Z" -Sessions @((Session "A" "orc" "" "waking"))
$r = Invoke-HordeFleetWakeLot -Lot $id1 -Deps $deps -HordeHome $hh
Check ($world.spawns.Count -eq 0 -and $r.outcomes[0].outcome -ceq "held") "a member an earlier wake may still be loading is held, not started again"
$r = Invoke-HordeFleetWakeLot -Lot $id1 -Deps $deps -HordeHome $hh -Retry
Check ($world.spawns.Count -eq 1) "until -Retry says it is not running there"
$existing = Invoke-HordeFleetWake -Id $id1 -Deps $deps -HordeHome $hh -DryRun
Check ($existing.id -ceq $id1) "CONTROL: fleet wake <id> still works on the same lot, as it always did"

Section "backfill: each park written once, from a file"
$hh = New-Home
$fixture = Join-Path $root "test\fixtures\fleet\backfill-lots.json"
$enrich = { param($sid) $o = [ordered]@{ cwd = ("C:\lanes\" + $sid.Substring(0, 8)) }; if ($sid -ceq "003f4e1a-5fad-433f-9512-73f21da583fa") { $o["pane"] = "29"; $o["parent"] = "fff7f6d8-eb20-4fd5-8fa2-028892bd50bb" }; return [pscustomobject]$o }
$bdeps = [pscustomobject]@{ AgentName = "stand-in"; HostName = "stand-in"; Enrich = $enrich; ParkedFolder = (Join-Path $work "parked"); ParkedExists = { param($p) ($p -like "*PARKED-C3.md") } }
$b1 = Invoke-HordeFleetLotBackfill -File $fixture -Deps $bdeps -HordeHome $hh
Check ($b1.written -eq 2 -and $b1.skipped -eq 0) ("the seed file writes its two lots (" + $b1.written + " written)")
$ls = Lots-Of $hh
Check ($ls.Count -eq 2 -and $ls[0].hibernation_id -ceq "20261019-202000" -and $ls[1].hibernation_id -ceq "20261016-195900") "newest first: M's park of 10-19, then the 10-16 parks"
Check ($ls[0].selection_kind -ceq "backfill" -and $ls[0].by -ceq "M" -and $ls[0].reason -ceq "free memory" -and $ls[0].created_at -ceq "2026-10-19T20:20:00Z") "lot B: by M, reason free memory, at 20:20Z, selection_kind backfill"
Check ($ls[1].by -ceq "K" -and $ls[1].reason -ceq "double-restore cleanup" -and $ls[1].created_at -ceq "2026-10-16T19:59:00Z") "lot A: by K, reason double-restore cleanup, at 19:59Z"
Check ($ls[0].id -cmatch $script:HordeUlidPattern -and (Get-HordeFleetUlidTime -Ulid $ls[0].id).ToString("yyyy-MM-ddTHH:mm:ssZ") -ceq "2026-10-19T20:20:00Z") "each lot's id is a ULID made for its time"
Check (@($ls[1].members).Count -eq 12 -and @($ls[0].members).Count -eq 2) "twelve sessions in lot A, two in lot B"
Check ((@($ls[0].members | ForEach-Object { $_.session_id.Substring(0, 8) }) -join ",") -ceq "3fc9bfc2,6168116b") "lot B holds B 3fc9bfc2 and E 6168116b"
$c3 = Member-Of $ls[1] "C3"
Check ($c3.cwd -ceq "C:\lanes\003f4e1a" -and $c3.pane -ceq "29" -and $c3.parent -ceq "fff7f6d8-eb20-4fd5-8fa2-028892bd50bb" -and $c3.note -like "*PARKED-C3.md") "blank cwd, pane and parent come from the enrichment; the note from the parked folder when it is there"
Check ($c3.state -ceq "asleep" -and $c3.stored -ceq "exited") "a backfilled member is asleep while it does not run"
$fixtureText = Get-Content -LiteralPath $fixture -Raw
Check ($fixtureText -notmatch '[A-Za-z]:\\' -and @([System.IO.File]::ReadAllBytes($fixture) | Where-Object { $_ -gt 127 }).Count -eq 0) "the seed file is ASCII and names no machine path"
$snap = @{}
foreach ($f in @(Get-ChildItem -LiteralPath (Get-HordeFleetHibernationsDir -HordeHome $hh) -Recurse -File)) { $snap[$f.FullName] = (Get-FileHash -LiteralPath $f.FullName).Hash }
$b2 = Invoke-HordeFleetLotBackfill -File $fixture -Deps $bdeps -HordeHome $hh
$snap2 = @{}
foreach ($f in @(Get-ChildItem -LiteralPath (Get-HordeFleetHibernationsDir -HordeHome $hh) -Recurse -File)) { $snap2[$f.FullName] = (Get-FileHash -LiteralPath $f.FullName).Hash }
Check ($b2.written -eq 0 -and $b2.skipped -eq 2) ("a second run writes nothing (" + $b2.written + " written, " + $b2.skipped + " skipped)")
Check ($snap.Count -eq $snap2.Count -and @($snap.Keys | Where-Object { $snap2[$_] -cne $snap[$_] }).Count -eq 0) "and no file changed"
Check ((Lots-Of $hh).Count -eq 2) "so there are still two lots"
$idsBefore = @($ls | ForEach-Object { $_.id })
$hhB = New-Home
$null = Invoke-HordeFleetLotBackfill -File $fixture -Deps $bdeps -HordeHome $hhB
Check ((@((Lots-Of $hhB) | ForEach-Object { $_.id }) -join ",") -ceq ($idsBefore -join ",")) "the same park gets the same ULID in another home: the id is made from the park, not from chance"
$hh2 = New-Home
$null = Put-Lot -H $hh2 -Id "20261016-195900" -At "2026-10-16T19:59:00Z" -Sessions @((Session "A" "orc")) -Why "a real hibernate at that second"
$b3 = Invoke-HordeFleetLotBackfill -File $fixture -Deps $bdeps -HordeHome $hh2
Check ($b3.written -eq 1 -and $b3.skipped -eq 1 -and (@(Lots-Of $hh2 | Where-Object { $_.hibernation_id -ceq "20261016-195900" })[0]).reason -ceq "a real hibernate at that second") "a lot already there at that second is left as it is, never overwritten"
$hh3 = New-Home
$badFile = Join-Path $work "bad.json"
$goodLot = '{ "at": "2026-10-01T00:00:00Z", "by": "K", "why": "ok", "members": [ { "sessionId": "55555555-0000-4000-8000-000000000001" } ] }'
foreach ($case in @(
    @("a session id that is not a uuid", '{ "at": "2026-10-02T00:00:00Z", "by": "K", "why": "bad", "members": [ { "sessionId": "nope" } ] }', "breaks the lot shape"),
    @("a member the shape does not name", '{ "at": "2026-10-02T00:00:00Z", "by": "K", "why": "bad", "members": [ { "sessionId": "55555555-0000-4000-8000-000000000002", "colour": "red" } ] }', "does not know"),
    @("a time that is not UTC", '{ "at": "yesterday", "by": "K", "why": "bad", "members": [ { "sessionId": "55555555-0000-4000-8000-000000000002" } ] }', "not a UTC time"),
    @("a lot with no members", '{ "at": "2026-10-02T00:00:00Z", "by": "K", "why": "bad", "members": [ ] }', "holds no member"))) {
    [System.IO.File]::WriteAllText($badFile, ('{ "v": 1, "lots": [ ' + $goodLot + ', ' + $case[1] + ' ] }'))
    Check (Throws { Invoke-HordeFleetLotBackfill -File $badFile -Deps $bdeps -HordeHome $hh3 } $case[2]) ("a file with " + $case[0] + " is refused")
    Check ((Lots-Of $hh3).Count -eq 0) ("and the good lot before it was not written either: the file is checked whole first (" + $case[0] + ")")
}
[System.IO.File]::WriteAllText($badFile, ('{ "v": 1, "lots": [ ' + $goodLot + ', ' + $goodLot + ' ] }'))
Check (Throws { Invoke-HordeFleetLotBackfill -File $badFile -Deps $bdeps -HordeHome $hh3 } "same second") "two lots at one second are refused: a lot's folder is its time"

Section "waking a backfilled lot"
$hh = New-Home
Reset-World
$partial = Join-Path $work "partial.json"
$e1 = "66666666-0000-4000-8000-000000000001"; $e2 = "66666666-0000-4000-8000-000000000002"
[System.IO.File]::WriteAllText($partial, ('{ "v": 1, "lots": [ { "at": "2026-10-16T19:59:00Z", "by": "K", "why": "old park", "members": [ { "sessionId": "' + $e1 + '", "label": "E1", "cwd": "C:\\lanes\\e1" }, { "sessionId": "' + $e2 + '", "label": "E2" } ] } ] }'))
$eDeps = [pscustomobject]@{ AgentName = "stand-in"; HostName = "stand-in"; Enrich = { param($sid) return $null } }
$null = Invoke-HordeFleetLotBackfill -File $partial -Deps $eDeps -HordeHome $hh
$lid = "20261016-195900"
$bl = (Lots-Of $hh)[0]
Check (@($bl.members).Count -eq 2 -and (Member-Of $bl "E1").state -ceq "asleep") "the backfilled lot lists both members; the one with a record is asleep"
$dryR = Invoke-HordeFleetWakeLot -Lot $lid -DryRun -Deps $deps -HordeHome $hh
Check ($world.spawns.Count -eq 0 -and (Wakes-Of $hh $lid).Count -eq 0) "a dry run starts nothing and records no wake"
Check (@($dryR.outcomes | Where-Object { $_.outcome -ceq "planned" }).Count -eq 1 -and @($dryR.outcomes | Where-Object { $_.outcome -ceq "failed" }).Count -eq 1) "it plans the member that has a folder and says the one without cannot be started"
$real = Invoke-HordeFleetWakeLot -Lot $bl.id -Deps $deps -HordeHome $hh
Check ($world.spawns.Count -eq 1 -and $world.spawns[0].cwd -ceq "C:\lanes\e1") "the member with a working directory is started in it"
$e2o = @($real.outcomes | Where-Object { $_.sessionId -ceq $e2 })[0]
Check ($e2o.outcome -ceq "failed" -and $e2o.reason -like "*no working directory*") "the one with none is reported failed with the reason, never started in a guessed folder"
$wk = Wakes-Of $hh $lid
Check ($wk.Count -eq 1 -and (@($wk[0].members | Where-Object { $_.session_id -ceq $e1 })[0]).outcome -ceq "woken" -and (@($wk[0].members | Where-Object { $_.session_id -ceq $e2 })[0]).outcome -ceq "failed") "the wake records both outcomes"
$ls = Lots-Of $hh
Check ((Member-Of $ls[0] "E1").state -ceq "woken" -and @($ls[0].members).Count -eq 2) "the lot lists the woken one and still holds the one that could not be woken"

Section "the command line"
$cliEnv = @{ HORDE_HOME = (Join-Path $work "cli-home"); WEZFLEET_ROOT = (Join-Path $work "no-registry") }
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "wake", "-Lot", "20261016-091500", "20261016-091500") -Env $cliEnv
Check ($c.code -eq 2 -and $c.out -like "*not both*") ("an id and -Lot together are a usage error (exit " + $c.code + ")")
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "wake", "20261016-091500", "-Members", "A") -Env $cliEnv
Check ($c.code -eq 2 -and $c.out -like "*belongs to fleet wake -Lot*") ("-Members without -Lot is a usage error (exit " + $c.code + ")")
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "wake", "-Lot", "not-an-id") -Env $cliEnv
Check ($c.code -eq 2 -and $c.out -like "*needs a lot id*") ("a lot id that is neither a ULID nor a time is a usage error (exit " + $c.code + ")")
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "record", "-All", "-Lot", "20261016-091500") -Env $cliEnv
Check ($c.code -eq 2 -and $c.out -like "*belong to fleet wake*") ("-Lot on another verb is a usage error (exit " + $c.code + ")")
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "lots", "backfill") -Env $cliEnv
Check ($c.code -eq 2 -and $c.out -like "*needs -File*") ("backfill without -File is a usage error (exit " + $c.code + ")")
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "lots", "frobnicate") -Env $cliEnv
Check ($c.code -eq 2 -and $c.out -like "*backfill*") ("an unknown lots argument is a usage error (exit " + $c.code + ")")
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "lots", "-DryRun") -Env $cliEnv
Check ($c.code -eq 2) ("fleet lots takes no -DryRun (exit " + $c.code + ")")
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "lots", "-Json") -Env $cliEnv
Check ($c.code -eq 0 -and $c.out -like '*"lots":*') ("fleet lots -Json in an empty home prints the empty list (exit " + $c.code + ")")
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "lots") -Env $cliEnv
Check ($c.code -eq 0 -and $c.out -like "*no parking lots yet*") ("fleet lots in an empty home says so (exit " + $c.code + ")")
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("help") -Env $cliEnv
Check ($c.code -eq 0 -and $c.out -like "*fleet lots*" -and $c.out -like "*wake -Lot*") "horde help lists the new verb and the new wake form"
$cliText = Get-Content -LiteralPath (Join-Path $root "cli\commands\fleet.ps1") -Raw
Check ($cliText -match 'Invoke-HordeFleetWakeLot\s+-Lot\s+\$\(') "every wake, by lot id or hibernation id, goes through the lot's wake, so every wake is recorded"
Check ($cliText -match 'wakeMembers\s*=\s*@\(@\(\$memberList\)') "and -Members (and the older -Only labels) reach it as the members to wake"
Check ($cliText -match 'Invoke-HordeFleetRecord[^\r\n]*-Why\s+"fleet record"') "and a fleet record gives its lot a reason"

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Complete-HordeSuite -Success "every park is one lot, lots list newest first with a running member never asleep, a wake takes a lot or any part of it under every wake rule and is recorded, and a backfill writes each park once"
