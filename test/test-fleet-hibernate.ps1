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
$script:world = @{ stopped = @{}; error = ""; dieAt = @{}; askCostSeconds = 0; processSeen = @{}; processBound = @{}; processAsks = @{} }
$script:clock = @{ at = [datetime]::new(2026, 10, 16, 12, 0, 0, [System.DateTimeKind]::Utc) }
# A PROCESS DIES AT A TIME OF THE CLOCK (dieAt, set by the exit command), and a liveness ask that carries a
# session's record (it names `since`) costs askCostSeconds of that clock AFTER it answers: so a session can
# be alive when the last pass of the wait asks, and gone by the time the next ask is made.
Register-HordeFleetAgent -Name "stand-in" `
    -Snapshot { [pscustomobject]@{ error = $world.error; stopped = $world.stopped.Clone() } }.GetNewClosure() `
    -Verdict { param($snap, $id, $cwd, $ignore, $since, $process)
        if ($snap.error -ne "") { return [pscustomobject]@{ state = "unknown"; kind = "reading"; reason = $snap.error; pid = "" } }
        $gone = ($snap.stopped.ContainsKey($id) -or ($world.dieAt.ContainsKey($id) -and $script:clock.at -ge $world.dieAt[$id]))
        if ($PSBoundParameters.ContainsKey("since")) {
            $world.processBound[$id] = $PSBoundParameters.ContainsKey("process"); $world.processSeen[$id] = $process
            if (-not $world.processAsks.ContainsKey($id)) { $world.processAsks[$id] = New-Object System.Collections.ArrayList }
            [void]$world.processAsks[$id].Add($process)
            if ($world.askCostSeconds -gt 0) { $script:clock.at = $script:clock.at.AddSeconds($world.askCostSeconds) }
        }
        if ($gone) { return [pscustomobject]@{ state = "stopped"; kind = ""; reason = ""; pid = "" } }
        [pscustomobject]@{ state = "running"; kind = "live"; reason = "stand-in says running"; pid = "1" } } `
    -Running { param($snap) @($script:sids.Values | ForEach-Object { [pscustomobject]@{ sessionId = $_; pid = "1001"; start = "2002" } }) } -ResumeLine { param($id) "resume " + $id } -Scrub { @{} } `
    -LastTyped { param($path, $since) New-HordeUnknown -Reason "the suite hands typed turns in through Deps.Typed" }
# THE TERMINAL'S UNMARK, asked to remove a stale "hibernated" marker of a session found running.
$script:unmarks = New-Object System.Collections.ArrayList
Register-HordeFleetHost -Name "stand-in" -Placement { param($refs) New-HordeKnown -Value ([pscustomobject]@{ placed = @{}; notes = @() }) } `
    -Open { New-HordeUnknown -Reason "never opened" } -Describe { param($r) "describe" } `
    -Unmark { param($sid, $why) [void]$script:unmarks.Add([pscustomobject]@{ sid = $sid; why = $why }); New-HordeKnown -Value "none" }
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
    $script:world.dieAt = @{}; $script:world.askCostSeconds = 0; $script:world.processSeen = @{}; $script:world.processBound = @{}; $script:world.processAsks = @{}
    $script:unmarks.Clear()
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
        tiers = $null          # label -> 1, 2 or $null (a table of its own); $null = every Orc is tier 2
        tierState = "known"; typedInGap = @{}; gapSel = @{}; postCostSeconds = 0; typedAfterAsk = @{}; recheckUnreadable = @{}; recheck = @{}   # label -> the founder types after the ask; label -> times re-checked
        exitCostMinutes = 0    # what one exit command costs the clock
        dieOffset = @{}        # label -> seconds after its exit command that its process is gone
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
            $turns = @(@($t) | Where-Object { $null -ne $_ } | ForEach-Object { [pscustomobject]@{ at = $script:clock.at.AddMinutes(-$_[0]); text = $_[1] } })
            # TYPING IN THE GAP: the first look at a session is its selection; the founder types 5 s after it, which the
            # selection cannot see, and before the ask is posted (a post costs postCostSeconds). Seen once the clock is past it.
            $gl = $script:labelOf["" + $c.sessionId]
            if ($script:w.typedInGap.ContainsKey($gl)) {
                if (-not $script:w.gapSel.ContainsKey($gl)) { $script:w.gapSel[$gl] = $script:clock.at }
                $gapAt = $script:w.gapSel[$gl].AddSeconds(5)
                if ($script:clock.at -ge $gapAt) { $turns += [pscustomobject]@{ at = $gapAt; text = "no, leave this one running" } }
            }
            # A RE-CHECK is any look after the ask was posted (its since reaches back to the selection); the founder types after it.
            $lbl = $script:labelOf["" + $c.sessionId]
            if ($script:w.askedAt.ContainsKey($lbl)) {
                $script:w.recheck[$lbl] = 1 + [int]$script:w.recheck[$lbl]
                if ($script:w.recheckUnreadable.ContainsKey($lbl)) { return (New-HordeUnknown -Reason "its transcript could not be read again") }
                if ($script:w.typedAfterAsk.ContainsKey($lbl)) { $turns += [pscustomobject]@{ at = $script:clock.at; text = "wait, not that one" } }
            }
            New-HordeKnown -Value $turns }
        OrcTiers = {
            if ($script:w.tierState -ceq "unknown") { return (New-HordeUnknown -Reason "the Orc registry could not be read") }
            $m = @{}
            if ($null -ne $script:w.tiers) { foreach ($k in $script:w.tiers.Keys) { $m[$k] = $script:w.tiers[$k] } }
            else { foreach ($k in @("K", "L", "Q", "T", "U", "P", "R", "X")) { $m[$k] = 2 } }
            New-HordeKnown -Value $m }
        ParkedFolder = $script:parked
        ParkedAt = { param($path)
            $l = ([System.IO.Path]::GetFileNameWithoutExtension($path)).Substring(7)
            if (-not $script:w.parkAfter.ContainsKey($l)) { return $null }
            $after = $script:w.parkAfter[$l]
            if ($after -is [string] -and $after -ceq "old") { return $script:w.askedAt[$l].AddMinutes(-60) }
            $when = $script:w.askedAt[$l].AddMinutes([double]$after)
            if ($script:clock.at -ge $when) { return $when } else { return $null } }
        Post = { param($sid, $label, $body, $mid)
            $script:clock.at = $script:clock.at.AddSeconds($script:w.postCostSeconds)
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
            if ($script:w.exitCostMinutes -gt 0) { $script:clock.at = $script:clock.at.AddMinutes($script:w.exitCostMinutes) }
            if ($o -cne "refused" -and $script:w.dieOffset.ContainsKey($l)) { $script:world.dieAt[$sid] = $script:clock.at.AddSeconds([double]$script:w.dieOffset[$l]) }
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
    param([string[]]$Names = @(), [switch]$DryRun, [int]$WaitMinutes = 15, [scriptblock]$Selector = $null, [int]$Tier = 2)
    Next-Minute
    return (Invoke-HordeFleetHibernate -Deps (New-Deps) -Names $Names -Tier $Tier -DryRun:$DryRun -WaitMinutes $WaitMinutes -Selector $Selector -HordeHome $script:hh)
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
Check ((Reason $r "U") -notlike "founder-typed*") ("one he typed into 31 minutes ago is not held for his typing (" + (Outcome $r "U") + " " + (Reason $r "U") + ")")
Check ((Outcome $r "U") -ceq "excluded" -and (Reason $r "U") -like "warg-left-running:*22222222*") ("an Orc whose Warg is left running is left running too, and says which Warg (" + (Reason $r "U") + ")")
Check (@($r.lines | Where-Object { $_ -like "*PARKED-U.md" }).Count -eq 0) "and the dry run does not plan it"
$orcOfExcluded = @($r.outcomes | Where-Object { $_.outcome -ceq "planned" } | ForEach-Object { $_.label })
Check ($orcOfExcluded -ccontains "K1" -and $orcOfExcluded -ccontains "K") "CONTROL: an Orc and its Wargs that are all free to sleep are planned together"
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
$req = [pscustomobject]@{ sessionId = $script:sids["L1"]; label = "L1"; typedFor = [pscustomobject]@{ sessionId = $script:sids["L1"]; transcriptPath = "" }; process = $null; cwd = $script:work; parkedPath = (Join-Path $script:parked "PARKED-L1.md"); askedAt = $script:clock.at; typedSince = $script:clock.at.AddMinutes(-30); reason = "hibernation x"; others = @(); since = $null; memo = $memo }
$one = Invoke-HordeFleetParkSession -Request $req -Deps (New-Deps)
$two = Invoke-HordeFleetParkSession -Request $req -Deps (New-Deps)
Check ($one.outcome -ceq "refused" -and $two.outcome -ceq "refused" -and $script:w.exits.Count -eq 1) "a step whose box may hold the command answers refused for good, and never sends it again, however often it is asked"
Reset-World
$script:w.parkAfter["L1"] = 0; $script:w.askedAt["L1"] = $script:clock.at
$bare = [pscustomobject]@{ sessionId = $script:sids["L1"]; label = "L1"; cwd = $script:work; parkedPath = (Join-Path $script:parked "PARKED-L1.md"); askedAt = $script:clock.at; reason = "hibernation x"; others = @(); since = $null; memo = [pscustomobject]@{ fileSeen = $false; exitSent = $false; blocked = "" } }
$noWindow = $bare.PSObject.Copy()
$noWindow | Add-Member -NotePropertyName "typedFor" -NotePropertyValue ([pscustomobject]@{ sessionId = $script:sids["L1"]; transcriptPath = "" }) -Force
$nw = Invoke-HordeFleetParkSession -Request $noWindow -Deps (New-Deps)
Check ($nw.outcome -ceq "not-yet" -and $nw.reason -like "*window*" -and $script:w.exits.Count -eq 0) ("a step handed no start for the typing window fails safe: not yet, never its exit command (" + $nw.outcome + ": " + $nw.reason + ")")
$none = Invoke-HordeFleetParkSession -Request $bare -Deps (New-Deps)
Check ($none.outcome -ceq "not-yet" -and $none.reason -like "*cannot be checked*" -and $script:w.exits.Count -eq 0) "a step handed no session to re-check the founder's typing of is never sent its exit command: not yet, said why"
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
$wkDir = Join-Path $script:work "hib-stand-in"
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
# A CORRUPT RECORD IS SKIPPED, REPORTED, AND THE WATCHER CARRIES ON (T-0216): one bad file used to make who
# sleeps unknown, and the watcher then knocked on nobody for as long as it lay there.
$sk = & { Set-StrictMode -Version Latest; Get-HordeFleetAsleep -HordeHome $script:hh }
Check ($sk.state -ceq "known" -and $sk.value.ContainsKey($script:sids["K"]) -and $sk.value.ContainsKey($script:sids["K1"])) "one unreadable record is skipped: the sessions the other records put to sleep are still asleep"
Check (@($sk.skipped).Count -eq 1 -and ("" + @($sk.skipped)[0]) -like "*20990101-000000*") ("and the skipped record is reported by name (" + (@($sk.skipped) -join "; ") + ")")
Check (@((Get-HordeFleetAsleep -HordeHome (Join-Path $script:work "tick-home"))).Count -eq 1 -and @((Get-HordeFleetAsleep -HordeHome (Join-Path $script:work "tick-home")).skipped).Count -eq 0) "CONTROL: a home with no bad record reports nothing skipped"
Seat-Mail @("K", "L1")
$run3 = New-HordeWakeRun -HordeHome $script:hh -Self ""
$entries = @(Invoke-HordeWakeTick -Run $run3 -Now $t -Waker $standInWaker -Settings $settings -ReadSessions $none -TickSeconds 3 -ProcessId 4242 -HordeHome $script:hh)
Check (@($entries | Where-Object { $_.kind -ceq "would-nudge" -and $_.id -ceq $script:sids["L1"] }).Count -eq 1 -and @($entries | Where-Object { $_.kind -ceq "would-nudge" -and $_.id -ceq $script:sids["K"] }).Count -eq 0) "a tick with a corrupt record about still knocks on the awake and still leaves the sleeper alone"
Check (@($entries | Where-Object { $_.kind -ceq "skip-unknown" -and $_.id -ceq "hibernation" -and $_.reason -like "*20990101-000000*" }).Count -eq 1) "and journals the skipped record once, naming it"
Remove-Item -LiteralPath $bad -Recurse -Force
# ASLEEP IS IN A RECORD AND NOT RUNNING (T-0216): a session a record says exited whose process runs again - a
# hand restart, a restore - is awake, and a knock on it is the normal knock.
$script:world.stopped.Remove($script:sids["K"])
$script:unmarks.Clear()
$live = & { Set-StrictMode -Version Latest; Get-HordeFleetAsleep -HordeHome $script:hh }
Check ($live.state -ceq "known" -and -not $live.value.ContainsKey($script:sids["K"]) -and $live.value.ContainsKey($script:sids["K1"])) "a session in a record that is running again is not asleep; the one still stopped is"
Check (@($script:unmarks | Where-Object { $_.sid -ceq $script:sids["K"] -and $_.why -ceq "hibernated" }).Count -ge 1 -and @($script:unmarks | Where-Object { $_.sid -ceq $script:sids["K1"] }).Count -eq 0) "and the watcher asks the terminal to remove K's hibernated no-restore marker, which a hand restart outlived - never K1's, which sleeps on"
Seat-Mail @("K", "L")
$run4 = New-HordeWakeRun -HordeHome $script:hh -Self ""
$entries = @(Invoke-HordeWakeTick -Run $run4 -Now $t -Waker $standInWaker -Settings $settings -ReadSessions $none -TickSeconds 3 -ProcessId 4242 -HordeHome $script:hh)
Check (@($entries | Where-Object { $_.kind -ceq "would-nudge" -and $_.id -ceq $script:sids["K"] }).Count -eq 1) "the watcher knocks on it, as on any awake session"
# A SHADOW OR PROOF WATCHER CHANGES NOTHING (review of PR 326, nit): the same tick, K running again, and the
# terminal is asked to remove no marker unless the watcher is a live one.
foreach ($m in @("shadow", "proof", "live")) {
    $script:unmarks.Clear()
    Seat-Mail @("K", "L")
    $runM = $(if ($m -ceq "proof") { New-HordeWakeRun -Mode "proof" -Target $script:sids["L"] -Self "" -HordeHome $script:hh } else { New-HordeWakeRun -Mode $m -Self "" -HordeHome $script:hh })
    [void]@(Invoke-HordeWakeTick -Run $runM -Now $t -Waker $standInWaker -Settings $settings -ReadSessions $none -TickSeconds 3 -ProcessId 4242 -HordeHome $script:hh)
    $cleared = @($script:unmarks | Where-Object { $_.sid -ceq $script:sids["K"] -and $_.why -ceq "hibernated" }).Count
    if ($m -ceq "live") { Check ($cleared -ge 1) "CONTROL: a LIVE watcher's tick asks the terminal to remove K's stale hibernated marker" }
    else { Check ($cleared -eq 0) ("a " + $m.ToUpper() + " watcher's tick removes no marker (" + $cleared + " asked)") }
}
$script:world.error = "the control folder is empty"
Check ((Get-HordeFleetAsleep -HordeHome $script:hh).state -ceq "unknown") "when which sessions run cannot be read, who sleeps is unknown and nobody is knocked"
$script:world.error = ""
$script:world.stopped[$script:sids["K"]] = $true
# THE NEWEST RECORD IS THE LAST WORD: a later hibernation holds K woken and K1 exited again, and the earlier one
# still says K exited. Records are read oldest first so the later one wins.
$later = (Read-HordeFleetRecord -Id $r.id -HordeHome $script:hh).value
$later.id = "20990102-000000"
foreach ($ls in @($later.sessions)) { if ($ls.sessionId -ceq $script:sids["K"]) { Add-HordeFleetState -Session $ls -State "waking" -At $t; Add-HordeFleetState -Session $ls -State "woken" -At $t } }
$laterDir = Join-Path (Get-HordeFleetHibernationsDir -HordeHome $script:hh) "20990102-000000"
[void](New-Item -ItemType Directory -Path $laterDir -Force)
[void](Write-HordeFleetRecord -Dir $laterDir -Record $later)
$nw = Get-HordeFleetAsleep -HordeHome $script:hh
Check ($nw.state -ceq "known" -and -not $nw.value.ContainsKey($script:sids["K"]) -and $nw.value.ContainsKey($script:sids["K1"])) "a session the newest record holds woken is awake though an older record says it exited; the one it still holds exited sleeps"
Remove-Item -LiteralPath $laterDir -Recurse -Force
$woke = (Read-HordeFleetRecord -Id $r.id -HordeHome $script:hh).value
foreach ($s in @($woke.sessions)) { if ($s.sessionId -ceq $script:sids["K"]) { Add-HordeFleetState -Session $s -State "waking" -At $t; Add-HordeFleetState -Session $s -State "woken" -At $t } }
[void](Write-HordeFleetRecord -Dir (Join-Path (Get-HordeFleetHibernationsDir -HordeHome $script:hh) $r.id) -Record $woke)
$after = Get-HordeFleetAsleep -HordeHome $script:hh
Check ($after.state -ceq "known" -and -not $after.value.ContainsKey($script:sids["K"]) -and $after.value.ContainsKey($script:sids["K1"])) "a session woken again is knocked on again; one still asleep is not"

Section "a parked session gets its no-restore marker"
Reset-World
$script:marks = New-Object System.Collections.ArrayList
$script:markFail = @{}
Register-HordeFleetHost -Name "stand-in" -Placement { param($refs) New-HordeKnown -Value ([pscustomobject]@{ placed = @{}; notes = @() }) } `
    -Open { New-HordeUnknown -Reason "never opened" } -Describe { param($r) "describe" } `
    -Unmark { param($sid, $why) [void]$script:unmarks.Add([pscustomobject]@{ sid = $sid; why = $why }); New-HordeKnown -Value "none" } `
    -Mark { param($sid, $why) [void]$script:marks.Add([pscustomobject]@{ sid = $sid; why = $why }); if ($script:markFail.ContainsKey($sid)) { return (New-HordeUnknown -Reason "the folder is read-only") }; New-HordeKnown -Value ("C:\markers\" + $sid + ".json") }
$hostA = Resolve-HordeFleetAdapter -Kind "host"
Reset-World
$script:hh = Join-Path $script:work "home-marks2"
[void](New-Item -ItemType Directory -Path $script:hh -Force)
foreach ($l in @("K", "K1", "K2", "L", "L1")) { $script:w.parkAfter[$l] = 0 }
$script:w.stopAfter["L1"] = 1000
$script:markFail[$script:sids["K1"]] = $true
$r = Hib -Names @("K", "L") -WaitMinutes 2
Check ($script:marks.Count -eq 3 -and @($script:marks | Where-Object { $_.sid -ceq $script:sids["K"] }).Count -eq 1 -and @($script:marks | Where-Object { $_.sid -ceq $script:sids["K2"] }).Count -eq 1) ("a marker is asked for each session that exited: K, K1 and K2 (" + (@($script:marks | ForEach-Object { $script:labelOf[$_.sid] }) -join ",") + ")")
Check (@($script:marks | Where-Object { $_.why -cne "hibernated" }).Count -eq 0) "each with the reason hibernated"
Check (@($script:marks | Where-Object { $script:labelOf[$_.sid] -ceq "L" -or $script:labelOf[$_.sid] -ceq "L1" }).Count -eq 0) "none for a session left running: L1 did not stop, so neither it nor its Orc is marked"
Check ((Outcome $r "K1") -ceq "exited" -and @($r.lines | Where-Object { $_ -like "*K1*no-restore marker*could not be written*read-only*" }).Count -eq 1) "a marker that could not be written is said, and does not undo the exit"
$script:marks.Clear(); $script:markFail = @{}

Section "a session that exits just after the deadline is not recorded as awake (T-0216)"
# L1 is sent its exit at T0 and its process is gone 70 s later; the wait is one minute; each liveness ask costs
# 45 s of the clock. The pass at T0+30 asks (alive) and the clock is then past the deadline: one last ask is
# the only thing that can see it gone.
Reset-World
$script:marks.Clear()
$script:hh = Join-Path $script:work "home-final"
[void](New-Item -ItemType Directory -Path $script:hh -Force)
foreach ($l in @("L", "L1")) { $script:w.parkAfter[$l] = 0 }
$script:w.stopAfter["L1"] = 1000; $script:w.dieOffset["L1"] = 70; $script:world.askCostSeconds = 45
$r = Hib -Names @("L") -WaitMinutes 1
Check ((Outcome $r "L1") -ceq "exited") ("a Warg whose process went just past the deadline is exited, not still-awake (" + (Outcome $r "L1") + " " + (Reason $r "L1") + ")")
Check (@($script:marks | Where-Object { $_.sid -ceq $script:sids["L1"] }).Count -eq 1) "and it gets its no-restore marker"
Check (@($script:w.exits | Where-Object { $_.label -ceq "L1" }).Count -eq 1) "and was sent its exit command once"
$asks = @($script:world.processAsks[$script:sids["L1"]])
Check ($asks.Count -ge 2 -and @($asks | Where-Object { $null -eq $_ -or "" + $_.pid -cne "1001" }).Count -eq 0) ("every liveness ask - the passes' and the last look - carries the process the record names, as the watcher's does (" + $asks.Count + " asks)")
$rec = (Read-HordeFleetRecord -Id $r.id -HordeHome $script:hh).value
$l1 = @($rec.sessions | Where-Object { $_.sessionId -ceq $script:sids["L1"] })[0]
Check ($l1.state -ceq "exited") "the record says exited"
Check ((Outcome $r "L") -ceq "still-awake") "its Orc, which never reached its own exit, is still-awake"
Reset-World
foreach ($l in @("L", "L1")) { $script:w.parkAfter[$l] = 0 }
$script:w.stopAfter["L1"] = 1000; $script:w.dieOffset["L1"] = 400; $script:world.askCostSeconds = 45
$r = Hib -Names @("L") -WaitMinutes 1
Check ((Outcome $r "L1") -ceq "still-awake" -and (Reason $r "L1") -like "not exited within 1 minute(s)*still runs*") ("CONTROL: one whose process is really still there at the last look is still-awake (" + (Reason $r "L1") + ")")
Reset-World
foreach ($l in @("L", "L1")) { $script:w.parkAfter[$l] = 0 }
$script:w.stopAfter["L1"] = 1000; $script:w.dieOffset["L1"] = 20; $script:world.askCostSeconds = 45
$r = Hib -Names @("L") -WaitMinutes 1
Check ((Outcome $r "L1") -ceq "exited") "CONTROL: one gone before the last pass was exited by the pass itself"
Reset-World
foreach ($l in @("L", "L1")) { $script:w.parkAfter[$l] = 0 }
$script:w.exitAnswer["L1"] = @("unknown"); $script:w.dieOffset["L1"] = 5
$r = Hib -Names @("L") -WaitMinutes 1
Check ((Outcome $r "L1") -ceq "exited" -and @($script:w.exits | Where-Object { $_.label -ceq "L1" }).Count -eq 1) ("an exit whose answer nobody could read, after which the process is gone, is exited after one last look, and was not sent again (" + (Outcome $r "L1") + ")")
Reset-World
foreach ($l in @("L", "L1")) { $script:w.parkAfter[$l] = 0 }
$script:w.exitAnswer["L1"] = @("left-behind")
$r = Hib -Names @("L") -WaitMinutes 1
Check ((Outcome $r "L1") -ceq "still-awake" -and (Reason $r "L1") -like "*never sent the command again*") "CONTROL: a left-behind exit whose process is still there stays still-awake, with its reason"

Section "the deadline is kept between sessions, so the overshoot is one exit command at most"
Reset-World
$script:hh = Join-Path $script:work "home-between"
[void](New-Item -ItemType Directory -Path $script:hh -Force)
foreach ($l in @("T", "P")) { $script:w.parkAfter[$l] = 0 }
$script:w.exitCostMinutes = 2
$r = Hib -Names @("T", "P") -WaitMinutes 1
Check ((@($script:w.exits | ForEach-Object { $_.label }) -join ",") -ceq "T") ("one exit command ran the clock past the deadline, so the next session was not sent its own (" + (@($script:w.exits | ForEach-Object { $_.label }) -join ",") + ")")
Check ((Outcome $r "T") -ceq "exited" -and (Outcome $r "P") -ceq "still-awake") ("the one sent it exited; the other is still-awake (" + (Outcome $r "T") + ", " + (Outcome $r "P") + ")")

Section "the founder's typing is looked at again just before the exit command"
Reset-World
$script:hh = Join-Path $script:work "home-retyped"
[void](New-Item -ItemType Directory -Path $script:hh -Force)
foreach ($l in @("L", "L1")) { $script:w.parkAfter[$l] = 0 }
$script:w.typedAfterAsk["L1"] = $true
$r = Hib -Names @("L") -WaitMinutes 3
Check (@($script:w.exits | Where-Object { $_.label -ceq "L1" -or $_.label -ceq "L" }).Count -eq 0) "he typed into L1 after the ask: it is never sent its exit command, and neither is its Orc"
Check ((Outcome $r "L1") -ceq "still-awake" -and (Reason $r "L1") -like "*founder typed*") ("L1 is still-awake, saying why (" + (Reason $r "L1") + ")")
Check ([int]$script:w.recheck["L1"] -eq 1) ("and it was looked at once, never retried (" + [int]$script:w.recheck["L1"] + ")")
Check ((Outcome $r "L") -ceq "still-awake") "its Orc, which waits for it, is still-awake"
Reset-World
foreach ($l in @("L", "L1")) { $script:w.parkAfter[$l] = 0 }
$r = Hib -Names @("L") -WaitMinutes 3
Check ((Outcome $r "L1") -ceq "exited" -and (Outcome $r "L") -ceq "exited" -and [int]$script:w.recheck["L1"] -ge 1) "CONTROL: with nobody typing, the same run exits both, after the same re-check"

# THE GAP BETWEEN SELECTION AND THE ASK (review of PR 326): selection looks 30 minutes back from its own moment;
# the record, the markers and the earlier asks come after it. He types into L1 in that gap - after the selection
# looked, before its ask was posted - so the re-check must reach back to the selection's own look-back start.
Reset-World
foreach ($l in @("L", "L1")) { $script:w.parkAfter[$l] = 0 }
$script:w.typedInGap["L1"] = $true; $script:w.postCostSeconds = 10
$r = Hib -Names @("L") -WaitMinutes 3
Check (@($script:w.exits | Where-Object { $_.label -ceq "L1" -or $_.label -ceq "L" }).Count -eq 0) "he typed into L1 between selection and its ask: it is never sent its exit command, and neither is its Orc"
Check ((Outcome $r "L1") -ceq "still-awake" -and (Reason $r "L1") -like "*founder typed*") ("L1 is still-awake, saying why (" + (Outcome $r "L1") + ": " + (Reason $r "L1") + ")")
Reset-World
foreach ($l in @("L", "L1")) { $script:w.parkAfter[$l] = 0 }
$script:w.postCostSeconds = 10
$r = Hib -Names @("L") -WaitMinutes 3
Check ((Outcome $r "L1") -ceq "exited" -and (Outcome $r "L") -ceq "exited") "CONTROL: with the same slow asks and nobody typing, both exit"

Reset-World
foreach ($l in @("L", "L1")) { $script:w.parkAfter[$l] = 0 }
$script:w.recheckUnreadable["L1"] = $true
$r = Hib -Names @("L") -WaitMinutes 2
Check (@($script:w.exits | Where-Object { $_.label -ceq "L1" }).Count -eq 0 -and (Outcome $r "L1") -ceq "still-awake" -and (Reason $r "L1") -like "*could not be read*") ("a typing re-check that cannot be read is never taken as nobody typed: no exit command, still-awake (" + (Reason $r "L1") + ")")
Check ([int]$script:w.recheck["L1"] -ge 2) ("and it is asked again, not given up on (" + [int]$script:w.recheck["L1"] + " looks)")

Section "the tier gate: only an Orc in tier 2 is ever put to sleep"
Reset-World
$script:w.tiers = @{ K = 2; L = 1; Q = $null; T = 2 }
$r = Hib -DryRun
$got = @($r.outcomes | ForEach-Object { $_.label })
Check (($got -join ",") -ceq "K2,K1,K,T") ("-Tier 2 with no names chooses the tier 2 Orcs and their Wargs (" + ($got -join ",") + ")")
Check ($got -cnotcontains "L" -and $got -cnotcontains "L1") "a tier 1 Orc and its Warg are not chosen"
Check ($got -cnotcontains "Q" -and $got -cnotcontains "P" -and $got -cnotcontains "R") "an Orc whose tier is null, and one the registry does not know, are not chosen"
$script:w.tiers = @{ K = 2; L = 1; Q = $null }
foreach ($bad in @("L", "Q", "P")) {
    Check (Throws { Hib -Names @($bad) -DryRun } "tier 2") ("an Orc named in -Orcs that is not tier 2 is refused (" + $bad + ")")
}
Check (Throws { Hib -Names @("K", "L") } "L") "naming a tier 1 Orc beside a tier 2 one refuses the whole run, in words that name it"
Check ($script:w.posts.Count -eq 0 -and $script:w.exits.Count -eq 0) "and nothing was asked or exited"
$r = Hib -Names @("K") -DryRun
Check ((@($r.outcomes | ForEach-Object { $_.label }) -join ",") -ceq "K2,K1,K") "CONTROL: a named tier 2 Orc is chosen with its Wargs"
$script:w.tierState = "unknown"
Check (Throws { Hib -Names @("K") -DryRun } "could not be read") "an Orc registry that cannot be read refuses the whole run, saying so"
Check (Throws { Hib -DryRun } "could not be read") "and so does a run by tier"
$script:w.tierState = "known"
Check (Throws { Hib -Names @("K") -Tier 1 -DryRun } "tier 2") "there is no tier but 2 to ask for"
$script:w.tiers = @{ K = 2; L = 1 }
$r = Hib -DryRun -Selector $all
$ex = @($r.outcomes | Where-Object { $_.label -ceq "L" -or $_.label -ceq "L1" })
Check ($ex.Count -eq 2 -and @($ex | Where-Object { $_.outcome -cne "excluded" -or $_.reason -notlike "tier:*" }).Count -eq 0) "a selector that picks a tier 1 Orc anyway gets it, and its Warg, left running as tier"
Reset-World
$script:w.tiers = @{ T = 2; K = 2 }
Set-Typed "T" @(, @(5, "one moment"))
$r = Hib -DryRun
Check ((Outcome $r "T") -ceq "excluded" -and (Reason $r "T") -like "founder-typed:*" -and (Outcome $r "K") -ceq "planned") "the never-list still holds on top: a tier 2 Orc he typed into is left running"

Section "an Orc and its Wargs sleep together or not at all"
Reset-World
Set-Typed "K1" @(, @(3, "do not stop this"))
$r = Hib -Names @("K") -DryRun
Check ((Outcome $r "K1") -ceq "excluded" -and (Reason $r "K1") -like "founder-typed:*") "a Warg he typed into is left running"
Check ((Outcome $r "K") -ceq "excluded" -and (Reason $r "K") -like "warg-left-running:*K1*") ("so its Orc is left running too (" + (Reason $r "K") + ")")
Check ((Outcome $r "K2") -ceq "excluded" -and (Reason $r "K2") -like "orc-left-running:*K*") ("and so does the rest of its tree: nothing of it sleeps while part of it runs (" + (Reason $r "K2") + ")")
Reset-World
Set-Typed "L" @(, @(4, "mine"))
$r = Hib -Names @("L") -DryRun
Check ((Outcome $r "L") -ceq "excluded" -and (Outcome $r "L1") -ceq "excluded" -and (Reason $r "L1") -like "orc-left-running:*L*") ("an Orc left running keeps its Wargs running (" + (Reason $r "L1") + ")")

Section "a hibernate finds a session running that an earlier hibernation put to sleep: its marker goes"
Reset-World
$script:hh = Join-Path $script:work "home-unmark"
[void](New-Item -ItemType Directory -Path $script:hh -Force)
foreach ($l in @("L", "L1")) { $script:w.parkAfter[$l] = 0 }
$r = Hib -Names @("L")
Check (@($script:unmarks | Where-Object { $_.sid -ceq $script:sids["L1"] -and $_.why -ceq "hibernated" }).Count -ge 1 -and @($script:unmarks | Where-Object { $_.sid -ceq $script:sids["L"] }).Count -ge 1) "each chosen session, found running, is asked to lose a hibernated marker it may still carry"
Check (@($script:unmarks | Where-Object { $_.why -cne "hibernated" }).Count -eq 0) "and only ever a hibernated one, never a parked one"

Section "the command line"
$cliEnv = @{ HORDE_HOME = (Join-Path $script:work "cli-home"); WEZFLEET_ROOT = (Join-Path $script:work "no-registry") }
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "hibernate") -Env $cliEnv
Check ($c.code -eq 2 -and $c.out -like "*needs -Tier 2*") ("fleet hibernate with no -Tier is a usage error, exit 2 (exit " + $c.code + ")")
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "hibernate", "-Orcs", "K") -Env $cliEnv
Check ($c.code -eq 2 -and $c.out -like "*needs -Tier 2*") ("-Orcs alone is not enough: the tier gate is always asked for (exit " + $c.code + ")")
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "hibernate", "-Tier", "1") -Env $cliEnv
Check ($c.code -eq 2 -and $c.out -like "*tier 2*") ("-Tier 1 is a usage error: a tier 1 Orc is never hibernated (exit " + $c.code + ")")
$cliText = Get-Content -LiteralPath (Join-Path $root "cli\commands\fleet.ps1") -Raw
Check ($cliText -match 'Invoke-HordeFleetHibernate[^\r\n]*-Tier\s+\$Tier') "the command always hands the tier gate on to the hibernation"
Check ($cliText -match 'OrcTiers\s*=\s*\$tiers' -and $cliText -match 'Get-HordeOrcDash') "and reads the Orc registry's tiers from the Orc dash, handing them in as OrcTiers"
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "record", "-All", "-Orcs", "K") -Env $cliEnv
Check ($c.code -eq 2 -and $c.out -like "*belong to fleet hibernate*") ("-Orcs on another verb is a usage error (exit " + $c.code + ")")
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "record", "-All", "-Tier", "2") -Env $cliEnv
Check ($c.code -eq 2 -and $c.out -like "*belong to fleet hibernate*") ("-Tier on another verb is a usage error (exit " + $c.code + ")")
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "hibernate", "-Tier", "2", "-Orcs", "K", "-WaitMinutes", "0") -Env $cliEnv
Check ($c.code -eq 2) ("a wait of 0 minutes is a usage error (exit " + $c.code + ")")
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "hibernate", "-Tier", "2", "-Orcs", "K", "-DryRun") -Env $cliEnv
Check ($c.code -eq 1 -and $c.out -like "*cannot be read whole*") ("against a registry that is not there, even a dry run refuses, with the reason (exit " + $c.code + ")")
Check (-not (Test-Path -LiteralPath (Join-Path $cliEnv.HORDE_HOME "fleet"))) "and leaves nothing in Horde's home"
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("help") -Env $cliEnv
Check ($c.code -eq 0 -and $c.out -like "*fleet hibernate -Tier 2*") "horde help lists the verb"

Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction SilentlyContinue
Complete-HordeSuite -Success "hibernate puts to sleep exactly whom it may, each only once parked and idle, Wargs first, and the watcher leaves the sleepers alone"
