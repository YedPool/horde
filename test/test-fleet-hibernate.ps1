# DOES `horde fleet hibernate` PUT TO SLEEP EXACTLY THE SESSIONS IT MAY, ONLY ONCE EACH HAS PARKED AND SITS
# IDLE WITH AN EMPTY BOX, WARGS BEFORE THEIR ORC - AND DOES THE WAKE WATCHER THEN LEAVE THEM ALONE?
#
# fleet/Hibernate.ps1, fleet/Asleep.ps1 and the watcher's skip (core/Wake.ps1, core/WakeRun.ps1). The
# harness and the terminal are stand-ins registered through the shipped seam (fleet/Port.ps1), as
# test/test-fleet-record.ps1's are; the registry is handed in as the reader's own shape, because the real
# reader is that suite's. Every other outside call - the clock, sleep, the decisions list, the analyst's
# files, the lane folders, mail, the waker's state and exit command, the PARKED files - is a stand-in
# block that records what it was asked, and the clock moves only when the run sleeps, so a 15 minute
# wait runs in a moment. The hibernation records are real files in a Horde home under TEMP, read back
# with the shipped reader. The real adapters are tested in their own folders: the harness's reader of
# typed turns (agents/<name>/test/test-fleet-typed.ps1) and the waker's exit command
# (test/test-waker-wezfleet.ps1). Nothing here reads a real store, posts real mail or types anywhere.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "fleet\Hibernate.ps1")
. (Join-Path $root "fleet\Asleep.ps1")
. (Join-Path $root "core\WakeRun.ps1")

function Section { param([string]$Title) Write-Host ""; Write-Host ("--- " + $Title + " ---") -ForegroundColor Cyan }

$script:work = Join-Path $env:TEMP ("horde-fleet-hibernate-" + [guid]::NewGuid().ToString("N"))
$script:hh = Join-Path $script:work "home"
$script:parked = Join-Path $script:work "parked"
[void](New-Item -ItemType Directory -Path $script:hh -Force)
[void](New-Item -ItemType Directory -Path $script:parked -Force)

$labels = @("M", "AN", "K", "K1", "K2", "L", "L1", "Q", "T", "U", "P", "R", "X")
$script:sids = @{}
$n = 0
foreach ($l in $labels) { $n++; $script:sids[$l] = "22222222-0000-4000-8000-" + $n.ToString("000000000000") }
$script:sids["NL"] = "22222222-0000-4000-8000-000000000099"
$script:labelOf = @{}
foreach ($k in $script:sids.Keys) { $script:labelOf[$script:sids[$k]] = $k }

# THE REGISTRY, in the shape Read-HordeRegistry answers: records keyed by session id, and complete.
$script:reg = @{
    M = @{ role = "master" }; AN = @{ role = "session"; parent = "M" }
    K = @{ role = "orchestrator" }; K1 = @{ role = "session"; parent = "K" }; K2 = @{ role = "session"; parent = "K1" }
    L = @{ role = "orchestrator" }; L1 = @{ role = "session"; parent = "L" }
    Q = @{ role = "orchestrator" }; T = @{ role = "orchestrator" }; U = @{ role = "orchestrator" }; P = @{ role = "orchestrator" }; R = @{ role = "orchestrator" }
    X = @{ role = "orchestrator"; retired = $true }; NL = @{ role = "session"; parent = "U"; nolabel = $true }
}
$script:registryState = @{ complete = $true }
function New-Registry {
    $records = @{}
    foreach ($k in $script:reg.Keys) {
        $r = [ordered]@{ cwd = $script:work; transcriptPath = (Join-Path $script:work ($k + ".jsonl")); instance = "inst-1"; pane = "5"; origin = "user" }
        if (-not $script:reg[$k].ContainsKey("nolabel")) { $r["label"] = $k }
        foreach ($f in @("role", "retired")) { if ($script:reg[$k].ContainsKey($f)) { $r[$f] = $script:reg[$k][$f] } }
        if ($script:reg[$k].ContainsKey("parent")) { $r["parent"] = $script:sids[$script:reg[$k]["parent"]] }
        $records[$script:sids[$k]] = [pscustomobject]@{ id = $script:sids[$k]; path = ""; record = [pscustomobject]$r }
    }
    $complete = $(if ($script:registryState.complete) { New-HordeKnown -Value $true } else { New-HordeUnknown -Reason "a record could not be read" })
    return [pscustomobject]@{ records = $records; unreadable = @(); misnamed = @(); complete = $complete }
}

# THE HARNESS STAND-IN: which ids run, and what was typed into each.
$script:world = @{ stopped = @{}; error = "" }
$script:clock = @{ at = [datetime]::new(2026, 10, 16, 12, 0, 0, [System.DateTimeKind]::Utc) }
Register-HordeFleetAgent -Name "stand-in" `
    -Snapshot { [pscustomobject]@{ error = $world.error; stopped = $world.stopped.Clone() } }.GetNewClosure() `
    -Verdict { param($snap, $id, $cwd, $ignore, $since)
        if ($snap.error -ne "") { return [pscustomobject]@{ state = "unknown"; kind = "reading"; reason = $snap.error; pid = "" } }
        if ($snap.stopped.ContainsKey($id)) { return [pscustomobject]@{ state = "stopped"; kind = ""; reason = ""; pid = "" } }
        [pscustomobject]@{ state = "running"; kind = "live"; reason = "stand-in says running"; pid = "1" } } `
    -Running { param($snap) @() } -ResumeLine { param($id) "resume " + $id } -Scrub { @{} } `
    -LastTyped { param($path, $since) New-HordeUnknown -Reason "the suite hands typed turns in through Deps.Typed" }
Register-HordeFleetHost -Name "stand-in" -Placement { param($refs) New-HordeKnown -Value ([pscustomobject]@{ placed = @{}; notes = @() }) } `
    -Open { New-HordeUnknown -Reason "never opened" } -Describe { param($r) "describe" }
$agent = Resolve-HordeFleetAdapter -Kind "agent"
$hostA = Resolve-HordeFleetAdapter -Kind "host"
Check ($agent.state -ceq "known" -and $hostA.state -ceq "known" -and $null -ne $agent.value.lastTyped) "CONTROL: the stand-ins pass the shipped registration, LastTyped included, and are found by the shipped resolver"

# TYPED TURNS, by label: minutes ago and text, or "unreadable".
$script:typedBy = @{}
function Set-Typed { param([string]$Label, $Turns) $script:typedBy[$Label] = $Turns }
# THE REST OF THE WORLD, reset by Reset-World.
$w = @{}
function Reset-World {
    $script:world.stopped = @{}; $script:world.error = ""; $script:registryState.complete = $true
    $script:typedBy.Clear()
    $script:w = @{
        posts = New-Object System.Collections.ArrayList; exits = New-Object System.Collections.ArrayList; states = New-Object System.Collections.ArrayList
        questions = @(); qState = "known"; analysts = @($script:sids["AN"]); aState = "known"
        parkAfter = @{}        # label -> minutes after its ask it writes its PARKED file ("old" = a file from before)
        boxes = @{}            # label -> @{ idle; boxEmpty; midTurn } or "unknown"
        exitAnswer = @{}       # label -> outcome words in turn (submitted by default)
        stopAfter = @{}        # label -> polls after its exit before its process is gone (0 default)
        exitAt = @{}; askedAt = @{}; polls = 0; postFail = @{}; caller = ""
        lane = $null
    }
    Get-ChildItem -LiteralPath $script:parked -File -ErrorAction SilentlyContinue | Remove-Item -Force
}
Reset-World

function New-Deps {
    return [pscustomobject]@{
        Now = { $script:clock.at }
        Sleep = { param($ms) $script:clock.at = $script:clock.at.AddMilliseconds($ms); $script:w.polls++
            foreach ($l in @($script:w.exitAt.Keys)) { if ($script:w.polls -ge $script:w.exitAt[$l]) { $script:world.stopped[$script:sids[$l]] = $true } } }
        Registry = { New-Registry }
        Agent = $agent.value; Host = $hostA.value
        Status = { if ($null -ne $script:w.lane) { $script:w.lane } else { [pscustomobject]@{ state = "not-configured"; reason = "no lanes here"; orcs = @() } } }
        Questions = { if ($script:w.qState -ceq "known") { New-HordeKnown -Value @($script:w.questions) } else { New-HordeUnknown -Reason "the store is held by another process" } }
        Analysts = { if ($script:w.aState -ceq "known") { New-HordeKnown -Value @($script:w.analysts) } else { New-HordeUnknown -Reason "its handover file is not JSON" } }
        Typed = { param($c, $since)
            $t = $script:typedBy[$script:labelOf["" + $c.sessionId]]
            if ($t -is [string] -and $t -ceq "unreadable") { return (New-HordeUnknown -Reason "its transcript could not be read") }
            New-HordeKnown -Value @(@($t) | Where-Object { $null -ne $_ } | ForEach-Object { [pscustomobject]@{ at = $script:clock.at.AddMinutes(-$_[0]); text = $_[1] } }) }
        ParkedFolder = $script:parked
        ParkedAt = { param($path)
            $l = ([System.IO.Path]::GetFileNameWithoutExtension($path)).Substring(7)
            if (-not $script:w.parkAfter.ContainsKey($l)) { return $null }
            $after = $script:w.parkAfter[$l]
            if ($after -is [string] -and $after -ceq "old") { return $script:w.askedAt[$l].AddMinutes(-60) }
            $when = $script:w.askedAt[$l].AddMinutes([double]$after)
            if ($script:clock.at -ge $when) { return $when } else { return $null } }
        Post = { param($sid, $label, $body, $mid)
            [void]$script:w.posts.Add([pscustomobject]@{ sid = $sid; label = $label; body = $body; mid = $mid })
            $script:w.askedAt[$label] = $script:clock.at
            if ($script:w.postFail.ContainsKey($label)) { return (New-HordeUnknown -Reason "the messenger held it") }
            New-HordeKnown -Value ([pscustomobject]@{ stage = "posted" }) }
        State = { param($sid)
            $l = $script:labelOf[$sid]; [void]$script:w.states.Add($l)
            $b = $script:w.boxes[$l]
            if ($b -is [string]) { return (New-HordeUnknown -Reason "the pane could not be read") }
            if ($null -eq $b) { $b = @{ idle = "yes"; boxEmpty = "yes"; midTurn = "no" } }
            New-HordeKnown -Value ([pscustomobject]@{ id = $sid; idle = $b.idle; boxEmpty = $b.boxEmpty; midTurn = $b.midTurn }) }
        Exit = { param($sid, $why)
            $l = $script:labelOf[$sid]; [void]$script:w.exits.Add([pscustomobject]@{ label = $l; why = $why })
            $o = "submitted"
            if ($script:w.exitAnswer.ContainsKey($l) -and @($script:w.exitAnswer[$l]).Count -gt 0) { $list = @($script:w.exitAnswer[$l]); $o = $list[0]; $script:w.exitAnswer[$l] = @($list | Select-Object -Skip 1) }
            if ($o -ceq "unknown") { return (New-HordeUnknown -Reason "the waker's answer could not be read") }
            if ($o -ceq "submitted") { $after = $(if ($script:w.stopAfter.ContainsKey($l)) { [int]$script:w.stopAfter[$l] } else { 0 }); $script:w.exitAt[$l] = $script:w.polls + $after; if ($after -eq 0) { $script:world.stopped[$sid] = $true } }
            New-HordeKnown -Value ([pscustomobject]@{ id = $sid; outcome = $o; reason = ("stand-in " + $o); at = $script:clock.at }) }
        Caller = { $script:w.caller }
        PollMs = 30000
        ProcessStart = { param($p) if ($p -eq 4242) { "100" } elseif ($p -eq 5151) { "200" } else { "" } }
        Self = { [pscustomobject]@{ pid = 4242; start = "100" } }
    }
}
function Next-Minute { $script:clock.at = $script:clock.at.AddMinutes(1) }
function Hib {
    param([string[]]$Names, [switch]$DryRun, [int]$WaitMinutes = 15, [scriptblock]$Selector = $null)
    Next-Minute
    return (Invoke-HordeFleetHibernate -Deps (New-Deps) -Names $Names -DryRun:$DryRun -WaitMinutes $WaitMinutes -Selector $Selector -HordeHome $script:hh)
}
function Outcome { param($R, [string]$Label) $o = @($R.outcomes | Where-Object { $_.label -ceq $Label }); if ($o.Count -eq 0) { return "" }; return ("" + $o[0].outcome) }
function Reason { param($R, [string]$Label) $o = @($R.outcomes | Where-Object { $_.label -ceq $Label }); if ($o.Count -eq 0) { return "" }; return ("" + $o[0].reason) }
function Count-Records { $d = Get-HordeFleetHibernationsDir -HordeHome $script:hh; if (-not (Test-Path -LiteralPath $d)) { return 0 }; return @(Get-ChildItem -LiteralPath $d -Directory).Count }
$all = { param($cands) @($cands) }

Section "who is never put to sleep, each with its word"
$script:w.questions = @([pscustomobject]@{ number = 7; askedBy = "Orc Q"; waiting = @() }, [pscustomobject]@{ number = 8; askedBy = "M (Thrall)"; waiting = @("Orc LL (a lane with a longer letter)") })
Set-Typed "T" @(, @(29, "please hold on, I am reading this"))
Set-Typed "U" @(, @(31, "an older word from the founder"))
Set-Typed "P" @(@(1, "wezfleet: a message is waiting for you (id 0123456789) - run 'wezfleet mail read' to take it"), @(2, ([string][char]0xFEFF + "Handoff at the lane's folder")), @(3, "MESSAGE FROM M (wezfleet mail 0123)"))
Set-Typed "R" "unreadable"
$r = Hib -Names @("everyone") -DryRun -Selector $all
Check ((Outcome $r "M") -ceq "excluded" -and (Reason $r "M") -like "master:*") ("the master is left running, said as master (" + (Reason $r "M") + ")")
Check ((Outcome $r "AN") -ceq "excluded" -and (Reason $r "AN") -like "analyst:*") ("the fleet analyst service is left running (" + (Reason $r "AN") + ")")
Check ((Outcome $r "T") -ceq "excluded" -and (Reason $r "T") -like "founder-typed:*") ("a session the founder typed into 29 minutes ago is left running (" + (Reason $r "T") + ")")
Check ((Outcome $r "U") -ceq "planned") ("one he typed into 31 minutes ago is put to sleep (" + (Outcome $r "U") + ")")
Check ((Outcome $r "P") -ceq "planned") ("the fleet's own lines - the mail pointer, a byte-order-marked delivery, a mail block - are not the founder (" + (Outcome $r "P") + " " + (Reason $r "P") + ")")
Check ((Outcome $r "Q") -ceq "excluded" -and (Reason $r "Q") -like "question:*question 7*") ("an Orc with an open question on the founder's list is left running (" + (Reason $r "Q") + ")")
Check ((Outcome $r "L") -ceq "planned") "CONTROL: a question that names Orc LL does not hold Orc L"
Check ((Outcome $r "R") -ceq "excluded" -and (Reason $r "R") -like "transcript-unreadable:*") ("a session whose transcript cannot be read is left running, never guessed asleep (" + (Reason $r "R") + ")")
$nl = @($r.outcomes | Where-Object { $_.sessionId -ceq $script:sids["NL"] })
Check ($nl.Count -eq 1 -and $nl[0].outcome -ceq "excluded" -and $nl[0].reason -like "unlabelled:*") "a session with no label is left running: its PARKED file could not be named"
Check ((Outcome $r "X") -ceq "") "a retired session is never selected at all"
Check (@($r.lines | Where-Object { $_ -like "  left running T (*): founder-typed - *" }).Count -eq 1) "each left running is printed with its plain word and why"
$script:w.caller = $script:sids["L"]
$r = Hib -Names @("L") -DryRun
Check ((Outcome $r "L") -ceq "excluded" -and (Reason $r "L") -like "self:*" -and (Outcome $r "L1") -ceq "planned") "the session running the command is left running (it cannot end itself and wait for itself); its Wargs are not"
$script:w.caller = ""

Section "selection: an Orc by label or lane folder, with every Warg under it, Wargs first"
Reset-World
$r = Hib -Names @("K") -DryRun
Check ((@($r.outcomes | ForEach-Object { $_.label }) -join ",") -ceq "K2,K1,K") ("K's Warg of a Warg, then its Warg, then K (" + (@($r.outcomes | ForEach-Object { $_.label }) -join ",") + ")")
$script:w.lane = [pscustomobject]@{ state = "read"; reason = ""; orcs = @([pscustomobject]@{ folder = "sleeping-sessions"; written = $true; orc = "K" }, [pscustomobject]@{ folder = "gone-lane"; written = $true; orc = "Z" }) }
$r = Hib -Names @("sleeping-sessions") -DryRun
Check ((@($r.outcomes | ForEach-Object { $_.label }) -join ",") -ceq "K2,K1,K") "a lane folder's name finds its Orc through its status record"
Check (Throws { Hib -Names @("K", "gone-lane") -DryRun } "not running") "a lane whose Orc does not run is refused, never dropped"
Check (Throws { Hib -Names @("K", "nobody") -DryRun } "no running, unretired Orc is named nobody") "a name that is no Orc is refused, never dropped"
Check (Throws { Hib -Names @("K1") -DryRun } "named K1") "a Warg is not an Orc to name"
$script:w.lane = $null
Check (Throws { Hib -Names @("sleeping-sessions") -DryRun } "lane folders could not be read") "a lane name with no lane folders to read is refused, and says so"

Section "a dry run changes nothing"
Reset-World
$before = Count-Records
$r = Hib -Names @("K", "L") -DryRun
Check ((Count-Records) -eq $before -and -not (Test-Path -LiteralPath (Get-HordeFleetHibernationsDir -HordeHome $script:hh))) "no record, no hibernations folder"
Check ($script:w.posts.Count -eq 0 -and $script:w.exits.Count -eq 0 -and $script:w.states.Count -eq 0) "no mail, no exit command, not even a box read"
Check (@($r.lines | Where-Object { $_ -like "*PARKED-K.md*" }).Count -eq 1 -and @($r.lines | Where-Object { $_ -like "*dry run*" }).Count -eq 1) "it prints the plan: each session and where it would park"

Section "the run: ask, park, exit - Wargs before their Orc"
Reset-World
foreach ($l in @("K", "K1", "K2")) { $script:w.parkAfter[$l] = 2 }
$r = Hib -Names @("K")
Check ($r.id -cmatch '\A[0-9]{8}-[0-9]{6}\z') ("a hibernation is recorded (" + $r.id + ")")
Check ((@($script:w.posts | ForEach-Object { $_.label }) -join ",") -ceq "K2,K1,K") ("asked Wargs before their Orc (" + (@($script:w.posts | ForEach-Object { $_.label }) -join ",") + ")")
$p0 = $script:w.posts[0]
Check ($p0.body -ceq ("Hibernation " + $r.id + ": write where you got to into " + (Join-Path $script:parked "PARKED-K2.md") + ", reply nothing, stop at your turn end.")) ("the ask names the hibernation and the PARKED file in the fleet's parked folder (" + $p0.body + ")")
Check ($p0.mid -ceq (ConvertTo-HordeTextUuid -Text ("horde-fleet-hibernate/" + $r.id + "/" + $script:sids["K2"]))) "its message id is made from the hibernation and the session, so a repeat is one"
Check ((@($script:w.exits | ForEach-Object { $_.label }) -join ",") -ceq "K2,K1,K") ("each is sent its exit command once, a Warg before its Orc (" + (@($script:w.exits | ForEach-Object { $_.label }) -join ",") + ")")
Check ((@($script:w.exits | ForEach-Object { $_.why }) | Select-Object -Unique) -ceq ("hibernation " + $r.id)) "the exit says which hibernation asked for it"
Check ((Outcome $r "K") -ceq "exited" -and (Outcome $r "K1") -ceq "exited" -and (Outcome $r "K2") -ceq "exited") "all three exited"
$rec = (Read-HordeFleetRecord -Id $r.id -HordeHome $script:hh).value
Check ("" + (Get-HordeTestMember $rec "phase") -ceq "done" -and "" + (Get-HordeTestMember $rec "selection.kind") -ceq "orcs") "the record reads back, phase done, chosen by Orcs"
$k = @($rec.sessions | Where-Object { $_.sessionId -ceq $script:sids["K"] })[0]
Check ((@($k.history | ForEach-Object { $_.state }) -join ",") -ceq "recorded,asked,parked,exited") ("K's history is recorded, asked, parked, exited (" + (@($k.history | ForEach-Object { $_.state }) -join ",") + ")")
Check ((Get-HordeTestMember $k "parkedFile") -ceq (Join-Path $script:parked "PARKED-K.md")) "its PARKED file is in the record"
$exitedAt = "" + @($k.history | Where-Object { $_.state -ceq "exited" })[0].at
Check ($null -ne (Get-HordeFleetSince -Session $k -Record $rec) -and (Format-HordeFleetTime -At (Get-HordeFleetSince -Session $k -Record $rec)) -ceq $exitedAt) "the exited time is in the history, where the wake's narrowing rule reads it"

Section "the idle gate: every unknown is not yet"
foreach ($case in @(@{ idle = "unknown"; boxEmpty = "yes"; midTurn = "no" }, @{ idle = "yes"; boxEmpty = "unknown"; midTurn = "no" }, @{ idle = "yes"; boxEmpty = "yes"; midTurn = "unknown" }, @{ idle = "no"; boxEmpty = "yes"; midTurn = "no" }, @{ idle = "yes"; boxEmpty = "no"; midTurn = "no" }, @{ idle = "yes"; boxEmpty = "yes"; midTurn = "yes" }, "unknown")) {
    Reset-World
    $script:w.parkAfter["L1"] = 0
    $script:w.boxes["L1"] = $case
    $r = Hib -Names @("L") -WaitMinutes 2
    $said = $(if ($case -is [string]) { "the state unreadable" } else { "idle " + $case.idle + ", box empty " + $case.boxEmpty + ", mid-turn " + $case.midTurn })
    Check (@($script:w.exits | Where-Object { $_.label -ceq "L1" }).Count -eq 0 -and (Outcome $r "L1") -ceq "still-awake") ("no exit command with " + $said + ": still-awake (" + (Reason $r "L1") + ")")
    Check (@($script:w.exits | Where-Object { $_.label -ceq "L" }).Count -eq 0) "and its Orc, waiting for it, is not sent one either"
}
Reset-World
$script:w.parkAfter["L1"] = 0; $script:w.parkAfter["L"] = 0
$r = Hib -Names @("L") -WaitMinutes 2
Check ((Outcome $r "L1") -ceq "exited" -and (Outcome $r "L") -ceq "exited") "CONTROL: idle yes, box empty yes, mid-turn no - exited"

Section "a PARKED file older than the ask is last time's"
Reset-World
$script:w.parkAfter["L1"] = "old"; $script:w.parkAfter["L"] = 0
$r = Hib -Names @("L") -WaitMinutes 3
Check ((Outcome $r "L1") -ceq "still-awake" -and (Reason $r "L1") -like "*older than its ask*" -and @($script:w.exits | Where-Object { $_.label -ceq "L1" }).Count -eq 0) ("an old PARKED file is ignored: no exit, still-awake (" + (Reason $r "L1") + ")")

Section "the deadline: whoever has not exited stays up, untouched"
Reset-World
$script:w.parkAfter["K2"] = 1; $script:w.parkAfter["K1"] = 40; $script:w.parkAfter["K"] = 1
$start = $script:clock.at
$r = Hib -Names @("K") -WaitMinutes 15
Check ((Outcome $r "K2") -ceq "exited") "the Warg that parked in time exited"
Check ((Outcome $r "K1") -ceq "still-awake" -and (Reason $r "K1") -like "not exited within 15 minute(s)*PARKED*") ("the one that did not park is still-awake, with why (" + (Reason $r "K1") + ")")
Check ((Outcome $r "K") -ceq "still-awake" -and (Reason $r "K") -like "*waits for its Wargs*" -and @($script:w.exits | Where-Object { $_.label -ceq "K" }).Count -eq 0) ("its Orc, parked, is never sent the command while a Warg runs (" + (Reason $r "K") + ")")
$rec = (Read-HordeFleetRecord -Id $r.id -HordeHome $script:hh).value
$k1 = @($rec.sessions | Where-Object { $_.sessionId -ceq $script:sids["K1"] })[0]
$awakeAt = [datetime]::ParseExact(("" + @($k1.history)[-1].at), "yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture, ([System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal))
$late = ($awakeAt - $start).TotalMinutes
Check ($late -ge 15 -and $late -le 17) ("the wait ends at -WaitMinutes, not later (" + $late + " min after the start)")
Check ("" + $rec.phase -ceq "done" -and $k1.state -ceq "still-awake") "the record says so, phase done"

Section "the exit command is sent once; a box that may hold it is never typed into again"
Reset-World
foreach ($l in @("L", "L1")) { $script:w.parkAfter[$l] = 0 }
$script:w.stopAfter["L1"] = 3
$r = Hib -Names @("L")
Check (@($script:w.exits | Where-Object { $_.label -ceq "L1" }).Count -eq 1 -and (Outcome $r "L1") -ceq "exited") "a session still running after its exit command is looked at again, never sent it twice, and exits"
Reset-World
foreach ($l in @("L", "L1")) { $script:w.parkAfter[$l] = 0 }
$script:w.exitAnswer["L1"] = @("refused", "refused", "submitted")
$r = Hib -Names @("L")
Check (@($script:w.exits | Where-Object { $_.label -ceq "L1" }).Count -eq 3 -and (Outcome $r "L1") -ceq "exited") "a refused exit typed nothing, and is asked again until it is submitted"
foreach ($bad in @("left-behind", "killed", "unknown")) {
    Reset-World
    foreach ($l in @("L", "L1")) { $script:w.parkAfter[$l] = 0 }
    $script:w.exitAnswer["L1"] = @($bad, "submitted", "submitted")
    $r = Hib -Names @("L") -WaitMinutes 3
    Check (@($script:w.exits | Where-Object { $_.label -ceq "L1" }).Count -eq 1 -and (Outcome $r "L1") -ceq "still-awake" -and (Reason $r "L1") -like "*never sent the command again*") ("after " + $bad + " its box may hold the command: never sent again, still-awake (" + (Reason $r "L1") + ")")
}
Reset-World
foreach ($l in @("L", "L1")) { $script:w.parkAfter[$l] = 0 }
$script:w.postFail["L1"] = $true
$r = Hib -Names @("L") -WaitMinutes 2
Check ((Outcome $r "L1") -ceq "still-awake" -and (Reason $r "L1") -like "its ask was not posted*" -and @($script:w.exits | Where-Object { $_.label -ceq "L1" }).Count -eq 0) "a session whose ask could not be posted is still-awake at once, and never sent its exit"

Section "the per-session step is one seam"
Reset-World
$memo = [pscustomobject]@{ fileSeen = $false; exitSent = $false; blocked = "" }
$script:w.parkAfter["L1"] = 0; $script:w.askedAt["L1"] = $script:clock.at
$script:w.exitAnswer["L1"] = @("left-behind", "submitted")
$req = [pscustomobject]@{ sessionId = $script:sids["L1"]; label = "L1"; cwd = $script:work; parkedPath = (Join-Path $script:parked "PARKED-L1.md"); askedAt = $script:clock.at; reason = "hibernation x"; others = @(); since = $null; memo = $memo }
$one = Invoke-HordeFleetParkSession -Request $req -Deps (New-Deps)
$two = Invoke-HordeFleetParkSession -Request $req -Deps (New-Deps)
Check ($one.outcome -ceq "refused" -and $two.outcome -ceq "refused" -and $script:w.exits.Count -eq 1) "a step whose box may hold the command answers refused for good, and never sends it again, however often it is asked"
Reset-World
$asked = New-Object System.Collections.ArrayList
$d = New-Deps
$d | Add-Member -NotePropertyName "Park" -NotePropertyValue { param($r) [void]$asked.Add($r.label); [pscustomobject]@{ outcome = "parked"; reason = ""; fileSeen = $true; said = "" } }.GetNewClosure()
Next-Minute
$r = Invoke-HordeFleetHibernate -Deps $d -Names @("L") -HordeHome $script:hh
Check ((@($asked) -join ",") -ceq "L1,L" -and (Outcome $r "L") -ceq "exited" -and $script:w.exits.Count -eq 0 -and $script:w.states.Count -eq 0) ("a Park step handed in is the only per-session call made, Wargs first (" + (@($asked) -join ",") + ")")

Section "one hibernation at a time"
Reset-World
$hd = Get-HordeFleetHibernationsDir -HordeHome $script:hh
[void](New-Item -ItemType Directory -Path $hd -Force)
$lock = Join-Path $hd "hibernating.lock"
[System.IO.File]::WriteAllText($lock, "pid 5151 start 200 at 2026-10-16T12:00:00Z`n")
$before = Count-Records
Check (Throws { Hib -Names @("L") } "another hibernation is running") "a hibernation whose owner runs refuses a second: retry"
Check (Throws { Hib -Names @("L") -DryRun } "retry") "a dry run refuses too, while one runs"
Check ((Count-Records) -eq $before -and $script:w.posts.Count -eq 0) "and nothing was recorded or posted"
[System.IO.File]::WriteAllText($lock, "pid 6161 start 300 at 2026-10-16T12:00:00Z`n")
foreach ($l in @("L", "L1")) { $script:w.parkAfter[$l] = 0 }
$r = Hib -Names @("L")
Check (@($r.lines | Where-Object { $_ -like "*took over a stale hibernating lock of pid 6161*" }).Count -eq 1 -and (Outcome $r "L") -ceq "exited") "a lock whose owner is gone is taken over, and said"
Check (-not (Test-Path -LiteralPath $lock)) "the lock is gone when the run ends"

Section "a reading the selection rests on that cannot be read refuses, never empties"
Reset-World
$before = Count-Records
$script:registryState.complete = $false
Check (Throws { Hib -Names @("K") } "cannot be read whole") "an unreadable registry refuses"
$script:registryState.complete = $true
$script:world.error = "the control folder is empty"
Check (Throws { Hib -Names @("K") } "which sessions run cannot be read") "an untrusted liveness reading refuses"
$script:world.error = ""
$script:w.qState = "unknown"
Check (Throws { Hib -Names @("K") } "decisions list could not be read") "an unreadable decisions list refuses: which Orcs wait on him cannot be told"
$script:w.qState = "known"; $script:w.aState = "unknown"
Check (Throws { Hib -Names @("K") } "analyst service") "unreadable analyst files refuse: it could not be told apart"
$script:w.aState = "known"
Set-Typed "Q" @(, @(1, "still here")); $script:w.questions = @([pscustomobject]@{ number = 9; askedBy = "Orc Q"; waiting = @() })
Check (Throws { Hib -Names @("Q") } "nothing was hibernated") "a selection left with nobody is refused, never an empty record"
Check ((Count-Records) -eq $before -and $script:w.posts.Count -eq 0) "every refusal wrote nothing and posted nothing"

Section "the watcher leaves a sleeping session alone; its mail queues"
Reset-World
# A home of its own: L slept in this suite's earlier hibernations, and here it must be awake.
$script:hh = Join-Path $script:work "home-watch"
[void](New-Item -ItemType Directory -Path $script:hh -Force)
foreach ($l in @("K", "K1", "K2")) { $script:w.parkAfter[$l] = 0 }
$r = Hib -Names @("K")
$asleep = & { Set-StrictMode -Version Latest; Get-HordeFleetAsleep -HordeHome $script:hh }
Check ($asleep.state -ceq "known" -and $asleep.value.ContainsKey($script:sids["K"]) -and $asleep.value.ContainsKey($script:sids["K1"]) -and -not $asleep.value.ContainsKey($script:sids["L"])) ("the exited sessions read as asleep, under strict mode, and no other (" + $asleep.state + " " + $asleep.reason + ")")
Check ("" + $asleep.value[$script:sids["K"]] -like ("asleep in hibernation " + $r.id + " since *")) "each says where and since when"
# A WAKER OF THIS SUITE'S OWN, registered through the shipped port from a folder of its own (wakers/Port.ps1,
# -Folder): two orcs, each with one unread mail, idle with an empty box; every nudge is recorded.
$t = $script:clock.at
$wkDir = Join-Path $script:work "stand-in-waker"
[void](New-Item -ItemType Directory -Path $wkDir -Force)
$caps = [ordered]@{ schemaVersion = 1; waker = "hib-stand-in"; capabilities = [ordered]@{} }
foreach ($cap in @("nudge.pointer-only", "state.box", "state.turn", "nudge.guarded", "state.limit", "state.between-turns")) { $caps.capabilities[$cap] = [ordered]@{ support = "yes"; evidence = "This suite's stand-in answers what the suite seats, read back through the port." } }
$caps.capabilities["reach.unseen"] = [ordered]@{ support = "declined"; evidence = "A table in this suite: declined so that no production path can pick it." }
[System.IO.File]::WriteAllText((Join-Path $wkDir "capabilities.json"), (ConvertTo-Json -InputObject $caps -Depth 5))
$seat = @{ sessions = [ordered]@{}; nudges = New-Object System.Collections.ArrayList }
function Seat-Mail { param([string[]]$Labels) $seat.sessions = [ordered]@{}; $seat.nudges.Clear(); foreach ($l in $Labels) { $seat.sessions[$script:sids[$l]] = $l } }
$standInWaker = Register-HordeWaker -Name "hib-stand-in" -Folder $wkDir `
    -Targets { New-HordeKnown -Value @(@($seat.sessions.Keys) | ForEach-Object { [pscustomobject]@{ id = $_; label = $seat.sessions[$_]; role = "orc"; parent = ""; reachable = "yes"; retired = "no" } }) }.GetNewClosure() `
    -State { param([string]$Id) New-HordeKnown -Value ([pscustomobject]@{ id = $Id; unreadCount = 1; oldestUnreadAt = $t.AddMinutes(-5); idle = "yes"; boxEmpty = "yes"; midTurn = "no"; limited = "no"; betweenTurns = "no"; acked = "known" }) }.GetNewClosure() `
    -Nudge { param([string]$Id) [void]$seat.nudges.Add($Id); New-HordeKnown -Value ([pscustomobject]@{ id = $Id; outcome = "woken"; reason = ""; at = $t }) }.GetNewClosure()
function Nudged { param([string]$Label = "") return @($seat.nudges | Where-Object { $Label -eq "" -or $_ -ceq $script:sids[$Label] }).Count }
Seat-Mail @("K", "L")
$settings = Get-HordeWakeSettings -Overrides @{ maxNudgesPerPass = 5 }
$pass = Invoke-HordeWakePass -Waker $standInWaker -Now $t -Settings $settings -Ledger @{} -Send -Asleep $asleep.value
Check ((Nudged "K") -eq 0 -and (Nudged "L") -eq 1) "a pass knocks on the awake session with mail and never on the sleeping one"
$dk = @($pass.decisions | Where-Object { $_.id -ceq $script:sids["K"] })[0]
Check ($dk.action -ceq "skip" -and $dk.reason -like "asleep in hibernation*") ("the sleeper is skipped, saying why (" + $dk.reason + ")")
Check ($pass.never.ContainsKey($script:sids["K"]) -and ("" + $pass.never[$script:sids["K"]]) -like "*its mail waits for its wake*") "its unread mail is said once as waiting for its wake, not lost"
Seat-Mail @("L")
$pass = Invoke-HordeWakePass -Waker $standInWaker -Now $t -Settings $settings -Ledger @{} -Send -AsleepUnknown "a record could not be read"
Check ((Nudged) -eq 0 -and @($pass.decisions | Where-Object { $_.action -ceq "wait" -and $_.reason -like "*asleep in a hibernation cannot be told*" }).Count -eq 1) "when who sleeps cannot be told, nobody is knocked"
# THE TICK, as `horde wake run` makes it: shadow, in a home of its own, reading the real records by default.
$none = { $a = New-HordeKnown -Value @(); Add-Member -InputObject $a -MemberType NoteProperty -Name "leftOut" -Value @(); $a }
Seat-Mail @("K", "L")
$run = New-HordeWakeRun -HordeHome $script:hh -Self ""
$entries = @(Invoke-HordeWakeTick -Run $run -Now $t -Waker $standInWaker -Settings $settings -ReadSessions $none -TickSeconds 3 -ProcessId 4242 -HordeHome $script:hh)
Check (@($entries | Where-Object { $_.kind -ceq "would-nudge" -and $_.id -ceq $script:sids["L"] }).Count -eq 1 -and @($entries | Where-Object { $_.kind -ceq "would-nudge" -and $_.id -ceq $script:sids["K"] }).Count -eq 0) "a watcher's tick reads this home's hibernations by itself and would knock only the awake session"
$run2 = New-HordeWakeRun -HordeHome (Join-Path $script:work "tick-home") -Self ""
$entries = @(Invoke-HordeWakeTick -Run $run2 -Now $t -Waker $standInWaker -Settings $settings -ReadSessions $none -ReadAsleep { New-HordeUnknown -Reason "a record could not be read" } -TickSeconds 3 -ProcessId 4242 -HordeHome (Join-Path $script:work "tick-home"))
Check (@($entries | Where-Object { $_.kind -ceq "would-nudge" }).Count -eq 0 -and @($entries | Where-Object { $_.kind -ceq "skip-unknown" -and $_.id -ceq "hibernation" }).Count -eq 1) "a tick that cannot tell who sleeps knocks nobody and journals why"
$bad = Join-Path (Get-HordeFleetHibernationsDir -HordeHome $script:hh) "20990101-000000"
[void](New-Item -ItemType Directory -Path $bad -Force)
[System.IO.File]::WriteAllText((Join-Path $bad "record.json"), "{ not json")
Check ((Get-HordeFleetAsleep -HordeHome $script:hh).state -ceq "unknown") "one unreadable record makes who sleeps unknown, never a shorter list"
Remove-Item -LiteralPath $bad -Recurse -Force
$woke = (Read-HordeFleetRecord -Id $r.id -HordeHome $script:hh).value
foreach ($s in @($woke.sessions)) { if ($s.sessionId -ceq $script:sids["K"]) { Add-HordeFleetState -Session $s -State "waking" -At $t; Add-HordeFleetState -Session $s -State "woken" -At $t } }
[void](Write-HordeFleetRecord -Dir (Join-Path (Get-HordeFleetHibernationsDir -HordeHome $script:hh) $r.id) -Record $woke)
$after = Get-HordeFleetAsleep -HordeHome $script:hh
Check ($after.state -ceq "known" -and -not $after.value.ContainsKey($script:sids["K"]) -and $after.value.ContainsKey($script:sids["K1"])) "a session woken again is knocked on again; one still asleep is not"

Section "the command line"
$cliEnv = @{ HORDE_HOME = (Join-Path $script:work "cli-home"); WEZFLEET_ROOT = (Join-Path $script:work "no-registry") }
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "hibernate") -Env $cliEnv
Check ($c.code -eq 2 -and $c.out -like "*needs -Orcs*") ("fleet hibernate with no -Orcs is a usage error, exit 2 (exit " + $c.code + ")")
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "record", "-All", "-Orcs", "K") -Env $cliEnv
Check ($c.code -eq 2 -and $c.out -like "*belong to fleet hibernate*") ("-Orcs on another verb is a usage error (exit " + $c.code + ")")
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "hibernate", "-Orcs", "K", "-WaitMinutes", "0") -Env $cliEnv
Check ($c.code -eq 2) ("a wait of 0 minutes is a usage error (exit " + $c.code + ")")
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "hibernate", "-Orcs", "K", "-DryRun") -Env $cliEnv
Check ($c.code -eq 1 -and $c.out -like "*cannot be read whole*") ("against a registry that is not there, even a dry run refuses, with the reason (exit " + $c.code + ")")
Check (-not (Test-Path -LiteralPath (Join-Path $cliEnv.HORDE_HOME "fleet"))) "and leaves nothing in Horde's home"
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("help") -Env $cliEnv
Check ($c.code -eq 0 -and $c.out -like "*fleet hibernate -Orcs*") "horde help lists the verb"

Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction SilentlyContinue
Complete-HordeSuite -Success "hibernate puts to sleep exactly whom it may, each only once parked and idle, Wargs first, and the watcher leaves the sleepers alone"
