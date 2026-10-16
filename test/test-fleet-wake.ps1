# DOES `horde fleet wake` START ONLY WHAT IS PROVEN STOPPED, LAY IT OUT AS SAVED, STOP ON LOW MEMORY,
# FIND A SESSION THAT CAME BACK UNDER A NEW ID, AND CHANGE NOTHING ON A DRY RUN OR A SECOND WAKE?
#
# fleet/Wake.ps1. Each case writes its own record with the shipped writer, in a Horde home this suite
# makes under TEMP. The harness, the terminal, the clock, free memory and the mail are stand-ins handed in
# through -Deps; the harness and terminal stand-ins are registered with the shipped Register-HordeFleet*
# and found by the shipped resolver, so one that does not fit the port fails here. The stand-in terminal
# "starts" a session by marking it running in this suite's world, as a real pane would make the harness
# write its control file. Nothing real is started, typed into or mailed.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "fleet\Wake.ps1")

function Section { param([string]$Title) Write-Host ""; Write-Host ("--- " + $Title + " ---") -ForegroundColor Cyan }

$work = Join-Path $env:TEMP ("horde-fleet-wake-" + [guid]::NewGuid().ToString("N"))
[void](New-Item -ItemType Directory -Path $work -Force)
$HID = "20261016-091500"
$ids = @{
    K = "22222222-0000-4000-8000-000000000001"; K1 = "22222222-0000-4000-8000-000000000002"; K2 = "22222222-0000-4000-8000-000000000003"
    L = "22222222-0000-4000-8000-000000000004"; L1 = "22222222-0000-4000-8000-000000000005"; X = "22222222-0000-4000-8000-000000000006"
}
$NEW = "33333333-0000-4000-8000-000000000009"
$SELFSTART = "133000000000000000"
$cwds = @{ K = "C:\lanes\k"; K1 = "C:\work\k1"; K2 = "C:\work\k2"; L = "C:\lanes\l"; L1 = "C:\work\l1"; X = "C:\work\x" }

# The world the stand-ins share. live: id -> { pid; cwd; state }. onSpawn: id -> start | rotate |
# elsewhere | silent (what the harness does when its pane is spawned). paneOf: pid -> pane.
$world = @{}
function Reset-World {
    $world.live = @{}; $world.error = ""; $world.onSpawn = @{}; $world.paneOf = @{}; $world.spawnFails = @(); $world.postFails = $false
    $world.spawns = New-Object System.Collections.ArrayList; $world.posts = New-Object System.Collections.ArrayList
    $world.free = New-Object System.Collections.ArrayList; $world.nextPane = 40; $world.clock = [datetime]::new(2026, 10, 16, 10, 0, 0, [System.DateTimeKind]::Utc)
    $world.opened = 0; $world.verdicts = New-Object System.Collections.ArrayList; $world.onOpen = $null
    # The process table the lock is judged by: pid -> start ticks text, "?" when unreadable.
    $world.procs = @{ "777" = $SELFSTART }
}
Reset-World

Register-HordeFleetAgent -Name "stand-in" `
    -Snapshot { [pscustomobject]@{ error = $world.error; live = $world.live.Clone() } }.GetNewClosure() `
    -Verdict { param($snap, $id, $cwd, $ignore, $since)
        [void]$world.verdicts.Add([pscustomobject]@{ id = $id; ignore = @($ignore); since = $since })
        if ($snap.error -ne "") { return [pscustomobject]@{ state = "unknown"; kind = "reading"; reason = $snap.error; pid = "" } }
        $e = $snap.live[$id]
        if ($null -eq $e) { return [pscustomobject]@{ state = "stopped"; kind = ""; reason = ""; pid = "" } }
        if ($e.state -ceq "unknown") { return [pscustomobject]@{ state = "unknown"; kind = "unconfirmed"; reason = ("pid " + $e.pid + " start time unreadable"); pid = "" + $e.pid } }
        [pscustomobject]@{ state = "running"; kind = "live"; reason = ("already running pid " + $e.pid); pid = "" + $e.pid } } `
    -Running { param($snap) @($snap.live.Keys | Where-Object { $snap.live[$_].state -ceq "running" } | ForEach-Object { [pscustomobject]@{ sessionId = $_; pid = $snap.live[$_].pid; cwd = $snap.live[$_].cwd } }) } `
    -ResumeLine { param($id) "resume " + $id } `
    -Scrub { @{ STAND_IN_SESSION = $null } }
Register-HordeFleetHost -Name "stand-in" `
    -Placement { param($refs) New-HordeKnown -Value ([pscustomobject]@{ placed = @{}; notes = @() }) } `
    -Open {
        $world.opened++
        if ($null -ne $world.onOpen) { & $world.onOpen }
        $spawn = { param($req)
            [void]$world.spawns.Add($req)
            $id = ("" + $req.line).Substring(7)
            if (@($world.spawnFails) -ccontains $id) { return (New-HordeUnknown -Reason "the stand-in terminal refused") }
            $world.nextPane++; $pane = "" + $world.nextPane
            $win = $(if ($req.mode -ceq "tab") { "" + $req.window } elseif ($req.mode -ceq "split") { "split-has-no-window" } else { "w" + $pane })
            $how = $world.onSpawn[$id]; if ($null -eq $how) { $how = "start" }
            $procId = 1000 + [int]$pane
            switch ($how) {
                "start" { $world.live[$id] = @{ pid = $procId; cwd = $req.cwd; state = "running" } }
                "rotate" { $world.live[$NEW] = @{ pid = $procId; cwd = $req.cwd; state = "running" }; $world.paneOf["" + $procId] = $pane }
                "elsewhere" { $world.live[$NEW] = @{ pid = $procId; cwd = $req.cwd; state = "running" }; $world.paneOf["" + $procId] = "999" }
                default { }
            }
            New-HordeKnown -Value ([pscustomobject]@{ pane = $pane; window = $win }) }.GetNewClosure()
        $paneOf = { param($p) $v = $world.paneOf["" + $p]; if ($null -eq $v) { New-HordeUnknown -Reason "unreadable" } else { New-HordeKnown -Value $v } }.GetNewClosure()
        New-HordeKnown -Value ([pscustomobject]@{ spawn = $spawn; paneOf = $paneOf }) }.GetNewClosure() `
    -Describe { param($req) "spawn " + $req.mode + " window=" + $req.window + " pane=" + $req.pane + " " + $req.direction + " " + $req.percent + " cwd=" + $req.cwd + " :: " + $req.line }
$agent = (Resolve-HordeFleetAdapter -Kind "agent")
$hostA = (Resolve-HordeFleetAdapter -Kind "host")
Check ($agent.state -ceq "known" -and $hostA.state -ceq "known") "CONTROL: the stand-ins pass the shipped registration and are found by the shipped resolver"

$deps = [pscustomobject]@{
    Now = { $world.clock }.GetNewClosure()
    Sleep = { param($ms) $world.clock = $world.clock.AddMilliseconds($ms) }.GetNewClosure()
    FreePercent = { if ($world.free.Count -gt 0) { $v = $world.free[0]; $world.free.RemoveAt(0); $v } else { 50.0 } }.GetNewClosure()
    Agent = $agent.value; Host = $hostA.value
    Post = { param($sid, $label, $body, $mid) [void]$world.posts.Add([pscustomobject]@{ to = $sid; label = $label; body = $body; id = $mid }); if ($world.postFails) { New-HordeUnknown -Reason "the stand-in mailbox is full" } else { New-HordeKnown -Value ([pscustomobject]@{ stage = "accepted" }) } }.GetNewClosure()
    WaitSeconds = 5; PollMs = 1000
    ProcessStart = { param($p) $v = $world.procs["" + $p]; if ($null -eq $v) { "" } else { $v } }.GetNewClosure()
    Self = { [pscustomobject]@{ pid = 777; start = $SELFSTART } }.GetNewClosure()
}

function Session {
    param([string]$L, [string]$Role, [string]$Parent = "", $Placement = $null)
    $s = [ordered]@{ sessionId = $ids[$L]; label = $L; role = $Role; cwd = $cwds[$L]; state = "recorded"; history = @([pscustomobject]@{ state = "recorded"; at = "2026-10-16T09:15:00Z" }) }
    if ($Parent -ne "") { $s["parent"] = $ids[$Parent] }
    if ($null -ne $Placement) { $s["placement"] = [pscustomobject][ordered]@{ windowKey = $Placement[0]; tabIndex = $Placement[1]; left = $Placement[2]; top = $Placement[3]; cols = $Placement[4]; rows = $Placement[5]; tabCols = 160; tabRows = 50 } }
    return [pscustomobject]$s
}
function New-Home {
    # A fresh Horde home holding hibernation $HID: K with K1 split to its right (a third of the tab) and
    # K2 in a second tab; L with L1, which has no placement; X, which has no orc.
    $h = Join-Path $work ([guid]::NewGuid().ToString("N"))
    $dir = Join-Path (Get-HordeFleetHibernationsDir -HordeHome $h) $HID
    [void](New-Item -ItemType Directory -Path $dir -Force)
    $rec = [pscustomobject][ordered]@{ schemaVersion = 1; id = $HID; createdAt = "2026-10-16T09:15:00Z"; agent = "stand-in"; host = "stand-in"
        selection = [pscustomobject][ordered]@{ kind = "all"; labels = @(); exclude = @() }
        sessions = @(
            (Session "L1" "other" "L"),
            (Session "K2" "warg" "K" @("i:1", 1, 0, 0, 160, 50)),
            (Session "K1" "warg" "K" @("i:1", 0, 100, 0, 60, 50)),
            (Session "K" "orc" "" @("i:1", 0, 0, 0, 100, 50)),
            (Session "L" "orc" "" @("i:2", 0, 0, 0, 160, 50)),
            (Session "X" "other")) }
    [void](Write-HordeFleetRecord -Dir $dir -Record $rec)
    return $h
}
function Read-Rec { param([string]$H) return (Read-HordeFleetRecord -Id $HID -HordeHome $H).value }
function State-Of { param($Rec, [string]$L) return ("" + @($Rec.sessions | Where-Object { $_.label -ceq $L })[0].state) }
function Get-Session { param($Rec, [string]$L) return @($Rec.sessions | Where-Object { $_.label -ceq $L })[0] }
function Spawn-For { param([string]$L) return @($world.spawns | Where-Object { $_.line -ceq ("resume " + $ids[$L]) })[0] }

# NOT ONE try AROUND THE CHECKS (test/test-files-cli.ps1 says why).
Section "a wake starts each orc in a window of its own, its wargs laid out as saved"
Reset-World
$h = New-Home
$r = Invoke-HordeFleetWake -Id $HID -Deps $deps -HordeHome $h
$rec = Read-Rec $h
Check (@("K", "K1", "K2", "L", "L1", "X" | Where-Object { (State-Of $rec $_) -cne "woken" }).Count -eq 0) ("every stopped session is woken (" + (($r.lines) -join " | ") + ")")
$order = @($world.spawns | ForEach-Object { $_.line.Substring(7) })
$want = @($ids["K"], $ids["K1"], $ids["K2"], $ids["L"], $ids["L1"], $ids["X"])
Check (($order -join ",") -ceq ($want -join ",")) "the orc first, then its wargs in saved order (same tab, then the next tab), orc by orc, then the session with no orc"
$k = Spawn-For "K"; $k1 = Spawn-For "K1"; $k2 = Spawn-For "K2"; $l = Spawn-For "L"; $l1 = Spawn-For "L1"; $x = Spawn-For "X"
Check ($k.mode -ceq "window" -and $k.cwd -ceq $cwds["K"]) "the orc gets a new window, in its own folder"
Check ($k1.mode -ceq "split" -and $k1.pane -ceq "41" -and $k1.direction -ceq "right" -and $k1.percent -ceq "38") ("the warg that shared the orc's saved tab is split from the orc's new pane, to the right, its saved share (" + $k1.mode + " " + $k1.pane + " " + $k1.direction + " " + $k1.percent + ")")
Check ($k2.mode -ceq "tab" -and $k2.window -ceq "w41") ("the warg of the second saved tab is a tab of the orc's new window (" + $k2.mode + " " + $k2.window + ")")
Check ($l.mode -ceq "window" -and $l1.mode -ceq "tab" -and $l1.window -ceq "w44") "the second orc gets a window of its own, and its warg with no placement is a tab in it"
Check ($x.mode -ceq "window") "a session with no orc gets a window of its own"
Check ($k.line -ceq ("resume " + $ids["K"]) -and $k.environment.ContainsKey("STAND_IN_SESSION")) "each pane runs the harness's resume line by session id, with the harness's scrub"
Check ($world.posts.Count -eq 6 -and @($world.posts | Where-Object { $_.to -ceq $ids["K"] -and $_.body -ceq ("You were woken from hibernation " + $HID + ". Read your PARKED-K.md and carry on.") }).Count -eq 1) "each woken session gets one mail, the agreed words, to its own id"
$mid = Get-HordeFleetWakeMessageId -Id $HID -SessionId $ids["K"]
Check ($mid -cmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z' -and @($world.posts | Where-Object { $_.id -ceq $mid }).Count -eq 1 -and $mid -ceq (Get-HordeFleetWakeMessageId -Id $HID -SessionId $ids["K"])) "the mail's id is made from the hibernation and the session, the same every time"
$hist = @((Get-Session $rec "K").history | ForEach-Object { $_.state }) -join ","
Check ($hist -ceq "recorded,waking,woken") ("the history keeps every step (" + $hist + ")")
$exp = Get-HordeTestMember $rec "expectedStarts"
Check ($null -ne $exp -and $exp.hibernationId -ceq $HID -and @($exp.ids).Count -eq 6 -and $exp.from -ceq "2026-10-16T10:00:00Z" -and ([datetime]$exp.to) -gt ([datetime]$exp.from)) "the expected starts are written, with every id to start and a window"
Check (-not (Test-Path -LiteralPath (Join-Path (Join-Path (Get-HordeFleetHibernationsDir -HordeHome $h) $HID) "waking.lock"))) "the waking lock is gone when the wake ends"
Check ($world.opened -eq 1) "the terminal is opened once for the whole wake"

Section "expected starts are on disk before the first spawn"
Reset-World
$h = New-Home
$seen = @{ before = $null }
$probe = [pscustomobject]@{ Now = $deps.Now; Sleep = $deps.Sleep; FreePercent = $deps.FreePercent; Agent = $deps.Agent; Post = $deps.Post; WaitSeconds = 5; PollMs = 1000; ProcessStart = $deps.ProcessStart; Self = $deps.Self
    Host = [pscustomobject]@{ name = "probe"; placement = $null; describe = $deps.Host.describe
        open = { $o = & $deps.Host.open; $seen.before = Get-HordeTestMember (Read-Rec $h) "expectedStarts"; $o }.GetNewClosure() } }
[void](Invoke-HordeFleetWake -Id $HID -Deps $probe -HordeHome $h)
Check ($null -ne $seen.before -and @($seen.before.ids).Count -eq 6) "the record held the expected starts when the terminal was opened, before any spawn"

Section "a second wake is refused"
Reset-World
$h = New-Home
$dir = Join-Path (Get-HordeFleetHibernationsDir -HordeHome $h) $HID
[System.IO.File]::WriteAllText((Join-Path $dir "waking.lock"), "pid 1")
$before = [System.IO.File]::ReadAllText((Join-Path $dir "record.json"))
Check (Throws { Invoke-HordeFleetWake -Id $HID -Deps $deps -HordeHome $h } "is being woken already") "a wake of a record that holds the waking lock is refused"
Check (Throws { Invoke-HordeFleetWake -Id $HID -Deps $deps -HordeHome $h -DryRun } "is being woken already") "a dry run is refused too: its plan would be wrong"
Check ($world.spawns.Count -eq 0 -and $world.posts.Count -eq 0 -and [System.IO.File]::ReadAllText((Join-Path $dir "record.json")) -ceq $before) "nothing was started, mailed or written"
Check ((Test-Path -LiteralPath (Join-Path $dir "waking.lock"))) "and the other wake's lock is left where it was"
# Two at once: the second is refused while the first is in its spawns.
Reset-World
$h = New-Home
$inner = @{ answer = "" }
$nested = [pscustomobject]@{ Now = $deps.Now; Sleep = $deps.Sleep; FreePercent = $deps.FreePercent; Agent = $deps.Agent; Post = $deps.Post; WaitSeconds = 5; PollMs = 1000; ProcessStart = $deps.ProcessStart; Self = $deps.Self
    Host = [pscustomobject]@{ name = "nested"; placement = $null; describe = $deps.Host.describe
        open = { try { [void](Invoke-HordeFleetWake -Id $HID -Deps $deps -HordeHome $h); $inner.answer = "ran" } catch { $inner.answer = $_.Exception.Message }; & $deps.Host.open }.GetNewClosure() } }
[void](Invoke-HordeFleetWake -Id $HID -Deps $nested -HordeHome $h)
Check ($inner.answer -like "*is being woken already*") ("a wake started while another holds the record is refused (" + $inner.answer + ")")
Check ($world.spawns.Count -eq 6) "CONTROL: the first wake went on and started each session once"

Section "running and unknown sessions are refused"
Reset-World
$h = New-Home
$world.live[$ids["K"]] = @{ pid = 7; cwd = $cwds["K"]; state = "running" }
$world.live[$ids["X"]] = @{ pid = 8; cwd = $cwds["X"]; state = "unknown" }
$r = Invoke-HordeFleetWake -Id $HID -Deps $deps -HordeHome $h
$rec = Read-Rec $h
Check ((State-Of $rec "K") -ceq "still-awake" -and (Get-Session $rec "K").history[-1].reason -like "still running*") "a running session is refused and left still-awake, with the reason"
Check ((State-Of $rec "X") -ceq "still-awake" -and (Get-Session $rec "X").history[-1].reason -like "may be running*") "a session whose liveness is unknown is refused as if running"
Check ($null -eq (Spawn-For "K") -and $null -eq (Spawn-For "X")) "neither is started"
Check ((Spawn-For "K1").mode -ceq "window" -and (Spawn-For "K2").mode -ceq "tab") "the orc's wargs still get the orc's window: the first one opens it"
Check (@($r.outcomes | Where-Object { $_.outcome -ceq "still-awake" }).Count -eq 2) "the outcome lists both as still awake"
Reset-World
$h = New-Home
$world.error = "the control folder is empty"
$r = Invoke-HordeFleetWake -Id $HID -Deps $deps -HordeHome $h
Check ($world.spawns.Count -eq 0 -and @($r.outcomes | Where-Object { $_.outcome -ceq "still-awake" }).Count -eq 6 -and $world.opened -eq 0) "when liveness cannot be read at all, nothing is started and the terminal is not even opened"

Section "each sleeper is checked again, from a fresh reading, right before its own spawn"
# Minutes can pass between the first reading and a late spawn: every earlier session is waited for. A
# sleeper resumed by hand meanwhile must not be started a second time (review of PR 318, finding 1).
# Here K1 is resumed by hand after the first reading - when the terminal is opened, before any spawn -
# while its twin K2, of the same orc, stays stopped.
Reset-World
$h = New-Home
$world.onOpen = { $world.live[$ids["K1"]] = @{ pid = 4711; cwd = $cwds["K1"]; state = "running" } }.GetNewClosure()
$world.onSpawn[$ids["K"]] = "rotate"
$r = Invoke-HordeFleetWake -Id $HID -Deps $deps -HordeHome $h -Only @("K", "K1", "K2")
$rec = Read-Rec $h
Check ($null -eq (Spawn-For "K1")) ("the sleeper resumed by hand after the first reading is not spawned (" + ($r.lines -join " | ") + ")")
Check ((State-Of $rec "K1") -ceq "still-awake" -and (Get-Session $rec "K1").history[-1].reason -like "still running*4711*") "it is left still-awake, with the fresh reading's reason"
Check (@($r.lines | Where-Object { $_ -like "*K1 (22222222)*refused*still running*4711*" }).Count -eq 1) "and the wake says so, by name"
Check ((State-Of $rec "K") -ceq "woken" -and (State-Of $rec "K2") -ceq "woken" -and $null -ne (Spawn-For "K2")) "its twin K2, still stopped on the fresh reading, is spawned and woken, and so is the orc"
$k2v = @($world.verdicts | Where-Object { $_.id -ceq $ids["K2"] })
Check ($k2v.Count -ge 2 -and @($k2v[-1].ignore) -ccontains $NEW) "the re-check passes the ids this wake already started - the orc came back as a new id - as ones that cannot be the sleeper"

Section "the memory gate stops the wake part way"
Reset-World
$h = New-Home
foreach ($v in @(40.0, 30.0, 14.9)) { [void]$world.free.Add($v) }
$r = Invoke-HordeFleetWake -Id $HID -Deps $deps -HordeHome $h
$rec = Read-Rec $h
Check ($world.spawns.Count -eq 2 -and (State-Of $rec "K") -ceq "woken" -and (State-Of $rec "K1") -ceq "woken") ("two sessions were started while 15 percent was free (" + $world.spawns.Count + ")")
Check (@("K2", "L", "L1", "X" | Where-Object { (State-Of $rec $_) -cne "recorded" }).Count -eq 0) "the third check found 14.9 percent: it and every later session stay asleep, their state untouched"
Check (@($r.outcomes | Where-Object { $_.outcome -ceq "asleep" }).Count -eq 4 -and @($r.lines | Where-Object { $_ -like "*14.9 percent, under 15*" }).Count -eq 1) "the stop is reported, with the reading, and the rest named"
Check ($world.free.Count -eq 0) "CONTROL: memory was read before each spawn, and not again after the stop"

Section "a session that comes back under a new id"
Reset-World
$h = New-Home
$world.onSpawn[$ids["X"]] = "rotate"
$r = Invoke-HordeFleetWake -Id $HID -Deps $deps -HordeHome $h -Only @("X")
$rec = Read-Rec $h
$xs = Get-Session $rec "X"
Check ((State-Of $rec "X") -ceq "woken" -and (Get-HordeTestMember $xs "wokenAs") -ceq $NEW) "a new session in the same folder AND in the spawned pane is the woken one, recorded as wokenAs"
Check ($world.posts.Count -eq 1 -and $world.posts[0].to -ceq $NEW) "its mail goes to the new id"
Reset-World
$h = New-Home
$world.onSpawn[$ids["X"]] = "elsewhere"
$r = Invoke-HordeFleetWake -Id $HID -Deps $deps -HordeHome $h -Only @("X")
$rec = Read-Rec $h
Check ((State-Of $rec "X") -ceq "failed" -and -not (Test-HordeTestMember (Get-Session $rec "X") "wokenAs") -and $world.posts.Count -eq 0) "CONTROL: a new session in the same folder but another pane is not taken: failed, after the bound"
Check ((Get-Session $rec "X").history[-1].reason -like "*not seen running within 5 s*") "the failure says what was waited for"
# A woken session that is running again under its new id is not started a second time.
$rec2 = $null
Reset-World
$h = New-Home
$world.onSpawn[$ids["X"]] = "rotate"
[void](Invoke-HordeFleetWake -Id $HID -Deps $deps -HordeHome $h -Only @("X"))
$n = $world.spawns.Count
[void](Invoke-HordeFleetWake -Id $HID -Deps $deps -HordeHome $h -Only @("X"))
Check ($world.spawns.Count -eq $n -and (State-Of (Read-Rec $h) "X") -ceq "still-awake") "a second wake checks the id it came back as, finds it running, and starts nothing"

Section "failures are failed, and the wake goes on"
Reset-World
$h = New-Home
$world.spawnFails = @($ids["K"])
$world.onSpawn[$ids["L"]] = "silent"
[void](Invoke-HordeFleetWake -Id $HID -Deps $deps -HordeHome $h)
$rec = Read-Rec $h
Check ((State-Of $rec "K") -ceq "failed" -and (Spawn-For "K1").mode -ceq "window") "a pane the terminal will not start fails that session, and the next of its group opens the window"
Check ((State-Of $rec "L") -ceq "failed" -and (State-Of $rec "L1") -ceq "woken" -and (State-Of $rec "X") -ceq "woken") "a session never seen running fails, and the rest are still woken"
Reset-World
$h = New-Home
$world.postFails = $true
[void](Invoke-HordeFleetWake -Id $HID -Deps $deps -HordeHome $h -Only @("X"))
$rec = Read-Rec $h
Check ((State-Of $rec "X") -ceq "failed" -and (Get-Session $rec "X").history[-1].reason -like "*wake mail was not posted*") "a session that runs again but could not be told is failed, saying so"

Section "-Only"
Reset-World
$h = New-Home
[void](Invoke-HordeFleetWake -Id $HID -Deps $deps -HordeHome $h -Only @("K1", "L"))
Check ($world.spawns.Count -eq 2 -and (Spawn-For "K1").mode -ceq "window" -and (Spawn-For "L").mode -ceq "window") "only the labels named are woken, each its own group when its orc is not woken"
Check ((State-Of (Read-Rec $h) "K") -ceq "recorded") "CONTROL: the others are untouched"
Check (Throws { Invoke-HordeFleetWake -Id $HID -Deps $deps -HordeHome $h -Only @("Q") } "holds no session labelled Q") "a label the hibernation does not hold is refused"

Section "the waking lock names its owner, and a dead owner's lock is taken over"
Reset-World
$h = New-Home
$dir = Join-Path (Get-HordeFleetHibernationsDir -HordeHome $h) $HID
$lock = Join-Path $dir "waking.lock"
$held = @{ text = "" }
$peek = [pscustomobject]@{ Now = $deps.Now; Sleep = $deps.Sleep; FreePercent = $deps.FreePercent; Agent = $deps.Agent; Post = $deps.Post; WaitSeconds = 5; PollMs = 1000; ProcessStart = $deps.ProcessStart; Self = $deps.Self
    Host = [pscustomobject]@{ name = "peek"; placement = $null; describe = $deps.Host.describe
        open = { $held.text = Read-HordeSharedText -Path $lock; & $deps.Host.open }.GetNewClosure() } }
[void](Invoke-HordeFleetWake -Id $HID -Deps $peek -HordeHome $h -Only @("X"))
Check ($held.text -like ("pid 777 start " + $SELFSTART + " at *")) ("while it runs, the lock names this wake's process and its start time (" + $held.text.Trim() + ")")
$S = "134000000000000000"
foreach ($case in @(
        @{ name = "its process is gone"; procs = @{}; takes = $true },
        @{ name = "its pid now belongs to a process that started 5 s later"; procs = @{ "4242" = ("" + ([long]$S + 50000000)) }; takes = $true },
        @{ name = "its process runs with that start time"; procs = @{ "4242" = $S }; takes = $false },
        @{ name = "its process runs, half a second off"; procs = @{ "4242" = ("" + ([long]$S + 5000000)) }; takes = $false },
        @{ name = "its process's start time cannot be read"; procs = @{ "4242" = "?" }; takes = $false })) {
    Reset-World
    foreach ($k in $case.procs.Keys) { $world.procs[$k] = $case.procs[$k] }
    $h = New-Home
    $dir = Join-Path (Get-HordeFleetHibernationsDir -HordeHome $h) $HID
    [System.IO.File]::WriteAllText((Join-Path $dir "waking.lock"), ("pid 4242 start " + $S + " at 2026-10-16T09:00:00Z`n"))
    if ($case.takes) {
        $r = $null
        try { $r = Invoke-HordeFleetWake -Id $HID -Deps $deps -HordeHome $h -Only @("X") } catch { $r = $null }
        Check ($null -ne $r -and $world.spawns.Count -eq 1 -and @($r.lines | Where-Object { $_ -like "*took over*stale*4242*" }).Count -eq 1) ("a lock whose owner is not alive (" + $case.name + ") is taken over, and the wake says so")
        Check (-not (Test-Path -LiteralPath (Join-Path $dir "waking.lock"))) ("and the lock is gone when that wake ends (" + $case.name + ")")
    } else {
        Check (Throws { Invoke-HordeFleetWake -Id $HID -Deps $deps -HordeHome $h -Only @("X") } "is being woken already") ("a lock whose owner may be alive (" + $case.name + ") still refuses")
        Check ($world.spawns.Count -eq 0 -and (Test-Path -LiteralPath (Join-Path $dir "waking.lock"))) ("nothing is started, and its lock is left (" + $case.name + ")")
    }
}

Section "a sleeper is checked against the sessions that could be its new id only"
Reset-World
$h = New-Home
$dir = Join-Path (Get-HordeFleetHibernationsDir -HordeHome $h) $HID
$rec = Read-Rec $h
Add-HordeFleetState -Session (Get-Session $rec "X") -State "exited" -At ([datetime]::new(2026, 10, 16, 9, 40, 0, [System.DateTimeKind]::Utc))
[void](Write-HordeFleetRecord -Dir $dir -Record $rec)
[void](Invoke-HordeFleetWake -Id $HID -Deps $deps -HordeHome $h -DryRun)
$vx = @($world.verdicts | Where-Object { $_.id -ceq $ids["X"] })[0]
$vk = @($world.verdicts | Where-Object { $_.id -ceq $ids["K"] })[0]
$all = @($ids.Values | Sort-Object)
Check ($null -ne $vx -and ((@($vx.ignore) | Sort-Object) -join ",") -ceq ($all -join ",")) "every session of the record is passed as one that cannot be a sleeper's new id: orcs and wargs share folders"
Check ($null -ne $vx -and $vx.since -is [datetime] -and $vx.since -eq [datetime]::new(2026, 10, 16, 9, 40, 0, [System.DateTimeKind]::Utc)) "a sleeper with an exit in its history is checked against sessions started after that exit"
Check ($null -ne $vk -and $vk.since -is [datetime] -and $vk.since -eq [datetime]::new(2026, 10, 16, 9, 15, 0, [System.DateTimeKind]::Utc)) "one with no exit is checked against sessions started after the hibernation was taken: anything older ran beside it"

Section "a dry run changes nothing"
Reset-World
$h = New-Home
$world.live[$ids["X"]] = @{ pid = 8; cwd = $cwds["X"]; state = "running" }
$dir = Join-Path (Get-HordeFleetHibernationsDir -HordeHome $h) $HID
$before = [System.IO.File]::ReadAllBytes((Join-Path $dir "record.json"))
$listing = (@(Get-ChildItem -LiteralPath $dir | ForEach-Object { $_.Name + ":" + $_.LastWriteTimeUtc.Ticks }) -join ",")
$r = Invoke-HordeFleetWake -Id $HID -Deps $deps -HordeHome $h -DryRun
$after = [System.IO.File]::ReadAllBytes((Join-Path $dir "record.json"))
Check ([Convert]::ToBase64String($before) -ceq [Convert]::ToBase64String($after)) "the record's bytes are the same"
Check ((@(Get-ChildItem -LiteralPath $dir | ForEach-Object { $_.Name + ":" + $_.LastWriteTimeUtc.Ticks }) -join ",") -ceq $listing) "no file was added, and none was touched: no lock was taken"
Check ($world.spawns.Count -eq 0 -and $world.posts.Count -eq 0 -and $world.opened -eq 0) "nothing was started, opened or mailed"
Check (@($r.lines | Where-Object { $_ -like "*spawn window*resume $($ids['K'])*" }).Count -eq 1 -and @($r.lines | Where-Object { $_ -like "*spawn split window= pane=K (22222222) right 38*resume $($ids['K1'])*" }).Count -eq 1) ("the plan prints the exact spawn each session would get, as the terminal describes it (" + ($r.lines -join " | ") + ")")
Check (@($r.lines | Where-Object { $_ -like "*refused X (22222222): still running*" }).Count -eq 1) "the plan names what it would refuse, and why"
Check (@($r.lines | Where-Object { $_ -like "*free memory now 50 percent*" }).Count -eq 1) "the plan says the free memory now"

Section "a record that cannot be read is refused"
Reset-World
$h = New-Home
$dir = Join-Path (Get-HordeFleetHibernationsDir -HordeHome $h) $HID
[System.IO.File]::WriteAllText((Join-Path $dir "record.json"), '{ "schemaVersion": 1 }')
Check (Throws { Invoke-HordeFleetWake -Id $HID -Deps $deps -HordeHome $h } "breaks its schema") "a record that breaks its schema is refused, and nothing is started"
Check ($world.spawns.Count -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $dir "waking.lock"))) "CONTROL: nothing ran and no lock was left"

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue

Complete-HordeSuite -Success "a wake starts only what is proven stopped, as saved, within the memory rule, and a dry run or a second wake changes nothing"
