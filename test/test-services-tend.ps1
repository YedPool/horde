# DOES ONE PASS OBSERVE, DECIDE, ACT AND JOURNAL - AND ARE ITS HANDS SAFE ON A REAL CHECKOUT AND A REAL
# PROCESS?
#
# cli/ServicesTend.ps1 (the pass, status, the schedule), cli/ServicesAct.ps1 (the revision tool, the
# self-check, processes), cli/ServicesTell.ps1, core/ServiceHostPort.ps1 and platform/windows/Services.ps1.
#
# NOTHING OF THIS MACHINE'S IS STARTED, STOPPED, UPDATED OR TOLD (CONTRIBUTING 9):
#   - THE PASS runs on tools this suite makes: a clock it moves, processes that are rows in a table,
#     a checkout that is two names. The real tools are never made here.
#   - THE REVISION PATHS run on throwaway repositories this suite creates under its own temp folder,
#     and on nothing else: every call names the folder it made.
#   - THE ONLY PROCESSES STARTED are this suite's own children - a sleeping shell it then ends, and
#     one start through the Windows adapter of a stub that writes a file into the suite's folder and
#     exits. Each is ended, or checked to have ended, in a finally block, by the pid AND start time
#     the suite recorded, never by a name.
#   - NO SCHEDULER FOLDER, MESSENGER OR SESSION is reached: the scheduler is a stand-in, and the
#     teller is a block that records what it was handed.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "Home", "ModuleSettings", "Heartbeat", "Services", "ServicesFiles", "ServiceHostPort", "Schedule")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
foreach ($f in @("ServicesAct", "ServicesTend", "ServicesTell")) { . (Join-Path $root ("cli\" + $f + ".ps1")) }
. (Join-Path $root "messengers\Port.ps1")
. (Join-Path $root "platform\windows\Services.ps1")

$work = Join-Path $env:TEMP ("horde-tend-" + [guid]::NewGuid().ToString("N"))
[void][System.IO.Directory]::CreateDirectory($work)
$t0 = [datetime]::new(2026, 10, 13, 12, 0, 0, [System.DateTimeKind]::Utc)
$revA = "a" * 40; $revB = "b" * 40
$children = New-Object System.Collections.ArrayList

function New-Home {
    # A Horde home of this suite's own, with the definitions it is given; telling is on, to the
    # suite's own teller.
    param([string]$Name, [string]$Definitions = "")
    $h = Join-Path $work $Name
    [void][System.IO.Directory]::CreateDirectory((Join-Path $h "settings"))
    if ($Definitions -ne "") { [System.IO.File]::WriteAllText((Join-Path $h "settings\service-definitions.json"), ('{ "schemaVersion": 1, "settings": { ' + $Definitions + ' } }')) }
    return $h
}
function Esc { param([string]$Path) return $Path.Replace("\", "\\") }
$co = Esc (Join-Path $work "co"); $served = Esc (Join-Path $work "served")
$svcText = '"svc": { "checkout": "' + $co + '", "hordeHome": "' + $served + '", "start": { "kind": "horde", "words": ["relay", "run"] }, "stop": { "kind": "horde", "words": ["relay", "stop"], "waitSeconds": 20 }, "alive": { "heartbeat": "relay\\beat.json", "tickSeconds": 60 }, "follow": { "restart": "idle", "idleSeconds": 300 } }'

# THE WORLD the stand-in tools act on. Every tool records its call.
function New-World {
    return @{ now = $t0; tick = 0; procs = @{}; beat = (New-HordeAbsent -Note "none"); head = $revA; wanted = $revA; clean = $true; idle = (New-HordeKnown -Value ([long]9999))
        calls = (New-Object System.Collections.ArrayList); nextPid = 1000; startOk = $true; beatsOnStart = $true; verifyOk = $true; tableOk = $true; fetchOk = $true; told = (New-Object System.Collections.ArrayList); tellOk = $true; stopEnds = $true }
}
function New-Tools {
    return @{
        Now          = { $W.now = $W.now.AddSeconds($W.tick); return $W.now }
        Sleep        = { param($Ms) [void]$W.calls.Add("sleep"); $W.now = $W.now.AddMilliseconds($Ms) }
        NewId        = { return [guid]::NewGuid().ToString() }
        ProcessEntry = { param($ProcessId) if (-not $W.tableOk) { return (New-HordeUnknown -Reason "the table is unreadable") }; if ($W.procs.ContainsKey($ProcessId)) { return (New-HordeKnown -Value ([pscustomobject]@{ pid = $ProcessId; startedAt = $W.procs[$ProcessId] })) }; return (New-HordeAbsent -Note "none") }
        Heartbeat    = { param($Path) [void]$W.calls.Add("heartbeat " + $Path); return $W.beat }
        Idle         = { [void]$W.calls.Add("idle"); return $W.idle }
        Fetch        = { param($Definition, $Policy) [void]$W.calls.Add("fetch"); return [pscustomobject]@{ ok = $W.fetchOk; detail = $(if ($W.fetchOk) { "" } else { "could not resolve host" }) } }
        Checkout     = { param($Definition, $RunningRevision, $Policy) [void]$W.calls.Add("checkout"); return [pscustomobject]@{ checkout = (New-HordeKnown -Value ([pscustomobject]@{ head = $W.head; detached = $true; clean = $W.clean; branch = "" })); wanted = (New-HordeKnown -Value ([pscustomobject]@{ revision = $W.wanted; fastForward = $true })) } }
        Verify       = { param($Definition, $Revision, $Policy) [void]$W.calls.Add("verify " + $Revision.Substring(0, 3)); return [pscustomobject]@{ ok = $W.verifyOk; detail = $(if ($W.verifyOk) { "checked" } else { "cli/X.ps1 does not parse (line 1)" }) } }
        Advance      = { param($Definition, $Revision, $Policy) [void]$W.calls.Add("advance " + $Revision.Substring(0, 3)); $W.head = $Revision; return [pscustomobject]@{ ok = $true; detail = "moved" } }
        Retreat      = { param($Definition, $Revision, $Policy) [void]$W.calls.Add("retreat " + $Revision.Substring(0, 3)); $W.head = $Revision; return [pscustomobject]@{ ok = $true; detail = "moved back" } }
        Start        = {
            param($Definition, $HordeHome, $Policy)
            [void]$W.calls.Add("start")
            if (-not $W.startOk) { return [pscustomobject]@{ ok = $false; detail = "Windows did not create the process"; process = $null; revision = "" } }
            $id = $W.nextPid; $W.nextPid++
            $W.procs[$id] = $W.now
            if ($W.beatsOnStart) { $W.beat = New-HordeKnown -Value ([pscustomobject]@{ at = $W.now; pid = $id; startedAt = $W.now; tickSeconds = 60; pass = [long]1 }) -ObservedAt $W.now }
            return [pscustomobject]@{ ok = $true; detail = ("started as process " + $id); process = [pscustomobject]@{ pid = $id; startedAt = $W.now }; revision = $W.head }
        }
        Stop         = { param($Definition, $Process, $Policy) [void]$W.calls.Add("stop " + $Process.pid); if ($W.stopEnds) { $W.procs.Remove([int]$Process.pid) }; return [pscustomobject]@{ ok = $true; detail = "asked" } }
        Kill         = { param($Process) [void]$W.calls.Add("kill " + $Process.pid); $W.procs.Remove([int]$Process.pid); return [pscustomobject]@{ ok = $true; detail = "ended" } }
        TellAll      = { param($Notices, $HordeHome, $Policy) if (-not $W.tellOk) { return [pscustomobject]@{ told = @(); problem = "no session holds the role of warchief" } }; foreach ($n in @($Notices)) { [void]$W.told.Add($n) }; return [pscustomobject]@{ told = @($Notices | ForEach-Object { $_.id }); problem = "" } }
    }
}
function Pass { param([string]$HordeHome, [hashtable]$More = @{}) return (Invoke-HordeServiceSupervisor -HordeHome $HordeHome -Tools $tools @More) }
# A call that must not throw: when it does, the answer says so, and the check that reads it FAILS -
# a suite that merely crashed would not count as having caught anything (tools/Mutate.ps1).
function Quiet { param([scriptblock]$Block) try { return (@(& $Block) | Select-Object -Last 1) } catch { return [pscustomobject]@{ PSTypeName = "Horde.Answer"; state = "threw"; value = $null; reason = ("IT THREW: " + $_.Exception.Message); observedAt = $null; ran = $false; problem = ("IT THREW: " + $_.Exception.Message); lines = @(); services = @() } } }
function Calls { param([string]$Like) return @($W.calls | Where-Object { $_ -like $Like }).Count }
function Journal { param([string]$HordeHome) return @(Read-HordeServiceJournalTail -Count 200 -HordeHome $HordeHome | ForEach-Object { $_ | ConvertFrom-Json }) }
function Running { param([int]$Id, [datetime]$Born, [datetime]$BeatAt) $W.procs[$Id] = $Born; $W.beat = New-HordeKnown -Value ([pscustomobject]@{ at = $BeatAt; pid = $Id; startedAt = $Born; tickSeconds = 60; pass = [long]1 }) -ObservedAt $BeatAt }
function Seed { param([string]$HordeHome, [int]$Id, [datetime]$Born) $s = New-HordeServiceState -Name "svc"; $s.started = [pscustomobject]@{ pid = $Id; startedAt = $Born; at = $Born }; $s.runningRevision = $revA; $s.lastFetchAt = $t0; Write-HordeServiceState -State $s -HordeHome $HordeHome }

$tools = New-Tools
$savedHosts = @($script:HordeServiceHosts)

try {
    Write-Host ""
    Write-Host "--- I. the pass: nothing defined, and its own heartbeat ---" -ForegroundColor Cyan
    $W = New-World
    $h0 = New-Home "h0"
    $before = [datetime]::UtcNow
    $r = Pass $h0
    Check ($r.ran -and $r.problem -eq "" -and ($r.lines -join " ") -like "*no service is defined*nothing to tend*") "with no definitions the pass runs, and says there is nothing to tend"
    $own = Read-HordeHeartbeat -Path (Get-HordeServiceTendHeartbeatPath -HordeHome $h0)
    Check ($own.state -ceq "known" -and $own.value.pid -eq $PID -and $own.value.tickSeconds -eq 60 -and $own.value.pass -eq 1 -and $own.value.at -ge $before.AddSeconds(-1) -and $own.value.startedAt -is [datetime]) "the pass writes its own heartbeat: this process, its start, a 60 s tick"
    $null = Pass $h0
    Check ((Read-HordeHeartbeat -Path (Get-HordeServiceTendHeartbeatPath -HordeHome $h0)).value.pass -eq 2) "and counts its passes"

    Write-Host ""
    Write-Host "--- II. the pass starts what is not running, once, and says a wait once ---" -ForegroundColor Cyan
    $W = New-World
    $h1 = New-Home "h1" $svcText
    $r = Pass $h1
    Check ((Calls "start") -eq 1 -and ($r.lines -join " | ") -like "*svc: start (start) done - started as process 1000*") "a service that is not running is started"
    $kept = (Read-HordeServiceState -Name "svc" -HordeHome $h1).value
    Check ($kept.started.pid -eq 1000 -and $kept.proving -and $kept.runningRevision -ceq $revA -and $kept.lastAction.step -ceq "start" -and $kept.lastAction.outcome -ceq "done") "its state records the process, the revision it runs and the action"
    Check ($r.services[0].code -ceq "running" -or $r.services[0].code -ceq "current") "and the same pass looks again and finds it running"
    $j = Journal $h1
    Check ($j.Count -eq 2 -and $j[0].step -ceq "start" -and $j[0].outcome -ceq "done" -and $j[1].action -ceq "nothing") "the journal has the start, and one line for what it found after"
    $stateFile = Get-HordeServiceStatePath -Name "svc" -HordeHome $h1
    $bytes = [System.IO.File]::ReadAllText($stateFile)
    $stamp = [System.IO.File]::GetLastWriteTimeUtc($stateFile)
    $W.calls.Clear()
    $W.now = $W.now.AddSeconds(60); $W.beat.value.at = $W.now.AddSeconds(-5)
    $r = Pass $h1
    $r2 = Pass $h1
    Check ((Calls "start") -eq 0 -and @(Journal $h1).Count -eq 2) "two quiet passes later: nothing started, and no new journal line - a wait is said once"
    Check ([System.IO.File]::ReadAllText($stateFile) -ceq $bytes -and [System.IO.File]::GetLastWriteTimeUtc($stateFile) -eq $stamp) "a quiet pass does not write the state file at all"
    Check ((Calls "fetch") -eq 0 -and (Calls "idle") -eq 0) "nor ask the remote again inside its interval, nor ask whether the person is idle"
    $W.now = $W.now.AddSeconds(300); $W.beat.value.at = $W.now.AddSeconds(-5)
    $null = Pass $h1
    Check ((Calls "fetch") -eq 1) "five minutes on, the remote is asked once"
    $W.fetchOk = $false; $W.now = $W.now.AddSeconds(300); $W.beat.value.at = $W.now.AddSeconds(-5)
    $null = Pass $h1
    $null = Pass $h1
    Check ((Calls "fetch") -eq 2 -and (Read-HordeServiceState -Name "svc" -HordeHome $h1).value.fetchProblem -like "*could not resolve host*") "a remote that cannot be reached is recorded, and asked again at the interval - not every pass"

    Write-Host ""
    Write-Host "--- III. never a second copy: an unreadable process table starts nothing ---" -ForegroundColor Cyan
    $W = New-World; $W.tableOk = $false
    $h2 = New-Home "h2" $svcText
    Seed $h2 500 $t0.AddMinutes(-10)
    $r = Pass $h2
    Check ((Calls "start") -eq 0 -and ($r.lines -join " ") -like "*svc: wait - nothing is done*the table is unreadable*") "when the process table cannot be read the pass waits, and starts nothing"
    [System.IO.File]::WriteAllText((Get-HordeServiceStatePath -Name "svc" -HordeHome $h2), "{ broken")
    $W = New-World
    $r = Pass $h2
    Check ((Calls "*") -eq 0 -and ($r.lines -join " ") -like "*svc: LEFT ALONE*" -and $r.services[0].left) "a service whose state file cannot be read is left alone: no tool is called for it"

    Write-Host ""
    Write-Host "--- IV. an update, all its steps in one pass ---" -ForegroundColor Cyan
    $W = New-World; $W.wanted = $revB
    $h3 = New-Home "h3" $svcText
    Running 500 $t0.AddMinutes(-10) $t0.AddSeconds(-5)
    Seed $h3 500 $t0.AddMinutes(-10)
    $r = Pass $h3
    $order = @($W.calls | Where-Object { $_ -like "verify*" -or $_ -like "stop*" -or $_ -like "advance*" -or $_ -ceq "start" -or $_ -like "retreat*" -or $_ -like "kill*" }) -join ", "
    Check ($order -ceq "verify bbb, stop 500, advance bbb, start" -and (Calls "idle") -ge 1) ("verify, then stop, then advance, then start - in that order, in one pass (" + $order + ")")
    $kept = (Read-HordeServiceState -Name "svc" -HordeHome $h3).value
    Check ($kept.phase -ceq "steady" -and $kept.runningRevision -ceq $revB -and $kept.previousRevision -ceq $revA -and $kept.started.pid -eq 1000 -and $W.head -ceq $revB) "it ends running the new revision, with the previous one recorded"
    Check ((Journal $h3 | ForEach-Object { $_.step + ":" + $_.code }) -join " " -clike "verify:verify stop:update advance:advance start:start-new :updated") "the journal has one line a step, and the confirmation"
    Check ($r.services[0].code -ceq "updated" -and $kept.lastAction.step -ceq "confirm") "and the pass reports the update"

    Write-Host ""
    Write-Host "--- V. a pass ended between two steps is picked up at the next step ---" -ForegroundColor Cyan
    $W = New-World; $W.wanted = $revB; $W.tick = 3
    $h4 = New-Home "h4" $svcText
    Running 500 $t0.AddMinutes(-10) $t0.AddSeconds(-5)
    Seed $h4 500 $t0.AddMinutes(-10)
    $seen = New-Object System.Collections.ArrayList
    foreach ($i in 1..8) {
        if ($W.procs.ContainsKey(500)) { $W.beat.value.at = $W.now }
        $r = Pass $h4 @{ BudgetSeconds = 1 }
        [void]$seen.Add(("" + $r.services[0].steps + ":" + (Read-HordeServiceState -Name "svc" -HordeHome $h4).value.phase))
        if ($r.services[0].code -ceq "updated") { break }
    }
    $kept = (Read-HordeServiceState -Name "svc" -HordeHome $h4).value
    Check ($seen.Count -ge 4 -and $kept.runningRevision -ceq $revB -and $kept.phase -ceq "steady") ("with a budget that allows one step a pass, the update still completes, a step at a time (" + ($seen -join " ") + ")")
    Check ((Calls "verify*") -eq 1 -and (Calls "stop*") -eq 1 -and (Calls "advance*") -eq 1 -and (Calls "start") -eq 1) "and no step is taken twice"
    Check (@($seen | Where-Object { $_ -like "*:stopping" -or $_ -like "*:launching" -or $_ -like "*:confirming" }).Count -ge 1) "CONTROL: passes did end part way through, with the phase kept in the state"

    Write-Host ""
    Write-Host "--- VI. a new revision that does not come up is rolled back, and someone is told ---" -ForegroundColor Cyan
    $W = New-World; $W.wanted = $revB; $W.beatsOnStart = $false
    $h5 = New-Home "h5" $svcText
    Running 500 $t0.AddMinutes(-10) $t0.AddSeconds(-5)
    Seed $h5 500 $t0.AddMinutes(-10)
    $r = Pass $h5
    $kept = (Read-HordeServiceState -Name "svc" -HordeHome $h5).value
    Check ($kept.phase -ceq "confirming" -and $kept.started.pid -eq 1000 -and $W.head -ceq $revB -and $W.told.Count -eq 0) "the new revision is started and is being confirmed; nobody is told yet"
    $W.now = $W.now.AddSeconds(125); $W.beatsOnStart = $true; $W.calls.Clear()
    $r = Pass $h5
    $order = @($W.calls | Where-Object { $_ -like "stop*" -or $_ -like "retreat*" -or $_ -ceq "start" -or $_ -like "advance*" }) -join ", "
    Check ($order -ceq "stop 1000, retreat aaa, start") ("with no heartbeat of its own in 120 s it is stopped, the checkout goes back, and the previous revision is started (" + $order + ")")
    $kept = (Read-HordeServiceState -Name "svc" -HordeHome $h5).value
    Check ($kept.pinnedRevision -ceq $revB -and $kept.runningRevision -ceq $revA -and $W.head -ceq $revA -and $kept.phase -ceq "steady") "the bad revision is pinned, and the previous one is what runs"
    Check ($W.told.Count -eq 1 -and $W.told[0].kind -ceq "escalate" -and $W.told[0].text -like "service svc:*bbbbbbbbb did not prove itself*" -and $W.told[0].service -ceq "svc" -and @($kept.notices).Count -eq 0 -and ($r.lines -join " ") -like "*told (escalate)*") "someone is told once, and the notice is forgotten once it is taken"
    $W.now = $W.now.AddSeconds(600); $W.beat.value.at = $W.now.AddSeconds(-5); $W.calls.Clear()
    $r = Pass $h5
    Check ((Calls "verify*") -eq 0 -and (Calls "stop*") -eq 0 -and $W.told.Count -eq 1 -and $r.services[0].code -ceq "pinned") "later passes do not try the pinned revision again, and tell nobody again"

    Write-Host ""
    Write-Host "--- VII. a notice nobody could take waits, and is never lost ---" -ForegroundColor Cyan
    $W = New-World; $W.wanted = $revB; $W.clean = $false; $W.tellOk = $false
    $h6 = New-Home "h6" $svcText
    Running 500 $t0.AddMinutes(-10) $t0.AddSeconds(-5)
    Seed $h6 500 $t0.AddMinutes(-10)
    $s6 = (Read-HordeServiceState -Name "svc" -HordeHome $h6).value; $s6.verifiedRevision = $revB; Write-HordeServiceState -State $s6 -HordeHome $h6
    $r = Pass $h6
    $kept = (Read-HordeServiceState -Name "svc" -HordeHome $h6).value
    Check ((Calls "stop*") -eq 0 -and (Calls "advance*") -eq 0 -and $r.services[0].code -ceq "dirty") "a checkout with local changes is not stopped and not moved"
    Check (@($kept.notices).Count -eq 1 -and ($r.lines -join " ") -like "*1 notice(s) wait untold: no session holds the role of warchief*tried again next pass*") "the notice that could not be told stays in the state, and the pass says so"
    $id = $kept.notices[0].id
    $W.now = $W.now.AddSeconds(60); $W.beat.value.at = $W.now; $W.tellOk = $true
    $r = Pass $h6
    Check ($W.told.Count -eq 1 -and $W.told[0].id -ceq $id -and @((Read-HordeServiceState -Name "svc" -HordeHome $h6).value.notices).Count -eq 0) "the next pass tells it, under the same id, so a messenger keeps it as one"
    [System.IO.File]::WriteAllText((Join-Path $h6 "settings\services.json"), '{ "schemaVersion": 1, "settings": { "tellWarchief": false } }')
    $W.clean = $true; $W.wanted = $revA; $W.now = $W.now.AddSeconds(60); $W.beat.value.at = $W.now
    $r = Pass $h6
    Check ($W.told.Count -eq 1 -and ($r.lines -join " ") -like "*1 notice(s) wait untold: telling is switched off*") "with telling switched off in the home's settings the teller is never called, and the pass says a notice waits"
    $noTeller = New-Tools; $noTeller["TellAll"] = $null
    [System.IO.File]::Delete((Join-Path $h6 "settings\services.json"))
    $r = Invoke-HordeServiceSupervisor -HordeHome $h6 -Tools $noTeller
    Check (($r.lines -join " ") -like "*wait untold: nothing here can tell anyone*") "and with no teller at all, the same"
    $boom = New-Tools; $boom["TellAll"] = { param($Notices, $HordeHome, $Policy) throw "the messenger fell over" }
    $r = Quiet { Invoke-HordeServiceSupervisor -HordeHome $h6 -Tools $boom }
    Check ($r.ran -and ($r.lines -join " ") -like "*wait untold: the messenger fell over*" -and @((Read-HordeServiceState -Name "svc" -HordeHome $h6).value.notices).Count -eq 1) "a teller that throws costs the telling, not the pass"

    Write-Host ""
    Write-Host "--- VIII. what stops a pass, and what does not ---" -ForegroundColor Cyan
    $W = New-World
    $lock = Enter-HordeServiceTendLock -HordeHome $h1
    try { $r = Quiet { Pass $h1 } } finally { $lock.Dispose() }
    Check (-not $r.ran -and $r.problem -eq "" -and ($r.lines -join " ") -like "*another pass is running*" -and (Calls "*") -eq 0) "while another pass holds the home, a pass does nothing, and that is not an error"
    $two = New-Home "h7" ('"bad": { "checkout": "' + $co + '", "hordeHome": "' + $served + '", "start": { "kind": "horde", "words": ["x"] }, "stop": { "kind": "kill" } }, ' + $svcText)
    $throwing = New-Tools; $throwing["ProcessEntry"] = { param($ProcessId) return (New-HordeAbsent -Note "none") }
    $throwing["Start"] = { param($Definition, $HordeHome, $Policy) if ($Definition.name -ceq "bad") { throw "the launcher blew up" }; [void]$W.calls.Add("start " + $Definition.name); return [pscustomobject]@{ ok = $true; detail = "ok"; process = [pscustomobject]@{ pid = 77; startedAt = $W.now }; revision = $revA } }
    $r = Invoke-HordeServiceSupervisor -HordeHome $two -Tools $throwing
    Check (($r.lines -join " | ") -like "*bad: start (start) FAILED - the start failed: the launcher blew up*" -and (Calls "start svc") -eq 1) "a tool that throws for one service is that service's failed step; the others are still tended"
    Check ((Read-HordeServiceState -Name "bad" -HordeHome $two).value.failures -eq 1) "and the failed start is counted against it"
    # A start that says it worked and names no process started nothing the supervisor can keep.
    $W = New-World
    $nameless = New-Tools; $nameless["Start"] = { param($Definition, $HordeHome, $Policy) [void]$W.calls.Add("start"); return [pscustomobject]@{ ok = $true; detail = "started"; process = $null; revision = "" } }
    $hN = New-Home "h-nameless" $svcText
    $r = Invoke-HordeServiceSupervisor -HordeHome $hN -Tools $nameless
    Check (($r.lines -join " | ") -like "*svc: start (start) FAILED - the start named no process*" -and $null -eq (Read-HordeServiceState -Name "svc" -HordeHome $hN).value.started -and (Read-HordeServiceState -Name "svc" -HordeHome $hN).value.failures -eq 1) "a start that names no process is a failed start: there is no identity to keep or to stop by"
    # A step that failed is left to the next pass, not tried again at once.
    $W = New-World
    Running 500 $t0.AddMinutes(-10) $t0.AddSeconds(-400)
    $hK = New-Home "h-stuck" $svcText
    $sK = New-HordeServiceState -Name "svc"; $sK.started = [pscustomobject]@{ pid = 500; startedAt = $t0.AddMinutes(-10); at = $t0.AddMinutes(-10) }; $sK.runningRevision = $revA; $sK.lastFetchAt = $t0
    $sK.phase = "stopping"; $sK.intent = "heal"; $sK.phaseSince = $t0.AddSeconds(-100)
    Write-HordeServiceState -State $sK -HordeHome $hK
    $stuckTools = New-Tools; $stuckTools["Kill"] = { param($Process) [void]$W.calls.Add("kill " + $Process.pid); return [pscustomobject]@{ ok = $false; detail = "access denied" } }
    $r = Invoke-HordeServiceSupervisor -HordeHome $hK -Tools $stuckTools
    Check ((Calls "kill*") -eq 1 -and ($r.lines -join " | ") -like "*svc: start (kill) FAILED - access denied*" -and (Read-HordeServiceState -Name "svc" -HordeHome $hK).value.stuck -ceq "access denied") "a step that failed is tried once a pass, not again and again within it"
    $refused = New-Home "h8" '"svc": { "start": { "kind": "horde", "words": ["x"] } }'
    $r = Pass $refused
    Check (-not $r.ran -and $r.problem -like "*is refused*" -and (Calls "start") -eq 0) "a refused definitions file stops the pass with its findings: nothing is supervised on half a file"
    [void][System.IO.Directory]::CreateDirectory((Join-Path $h0 "settings"))
    [System.IO.File]::WriteAllText((Join-Path $h0 "settings\services.json"), '{ "schemaVersion": 1, "settings": { "fetchIntervalSeconds": 1 } }')
    Check ((Pass $h0).problem -like "*fetchIntervalSeconds*") "and so does a refused settings file"
    [System.IO.File]::Delete((Join-Path $h0 "settings\services.json"))
    Check ((Pass $h1 @{ Only = @("nope") }).problem -like "*no service named 'nope' is defined*(defined: svc)*") "asking for a service that is not defined is a problem that names the ones that are"
    $W = New-World
    $r = Pass $two @{ Only = @("svc") }
    Check (@($r.services).Count -eq 1 -and $r.services[0].name -ceq "svc") "-Only tends only the services named"

    Write-Host ""
    Write-Host "--- IX. rollout: ask now, wait for it to settle, and say what did not finish ---" -ForegroundColor Cyan
    $W = New-World; $W.wanted = $revB; $W.idle = New-HordeKnown -Value ([long]3); $W.beatsOnStart = $false
    $h9 = New-Home "h9" $svcText
    Running 500 $t0.AddMinutes(-10) $t0.AddSeconds(-5)
    Seed $h9 500 $t0.AddMinutes(-10)
    $r = Pass $h9 @{ ForceFetch = $true }
    Check ((Calls "fetch") -eq 1 -and $r.services[0].code -ceq "not-idle" -and (Calls "stop*") -eq 0) "without -Now a person at the machine keeps the update waiting, though the remote was asked at once"
    $defs = @((Get-HordeServiceDefinitions -HordeHome $h9).services)
    Check (@(Get-HordeServiceRolloutVerdict -Definitions $defs -Services $r.services).Count -eq 1) "and the roll-out is reported as not complete"
    # The new process beats only once the suite's clock has moved on, as a real one beats a little later.
    $tools["Sleep"] = { param($Ms) [void]$W.calls.Add("sleep"); $W.now = $W.now.AddMilliseconds($Ms); if ($W.procs.ContainsKey(1000)) { $W.beat = New-HordeKnown -Value ([pscustomobject]@{ at = $W.now; pid = 1000; startedAt = $W.procs[1000]; tickSeconds = 60; pass = [long]1 }) -ObservedAt $W.now } }
    $r = Pass $h9 @{ ForceFetch = $true; IgnoreIdle = $true; SettleSeconds = 60; BudgetSeconds = 60 }
    Check ($r.services[0].code -ceq "updated" -and (Calls "sleep") -ge 1 -and (Read-HordeServiceState -Name "svc" -HordeHome $h9).value.runningRevision -ceq $revB) "with -Now it goes on passing until the new revision has proven itself"
    Check (@(Get-HordeServiceRolloutVerdict -Definitions $defs -Services $r.services).Count -eq 0) "and then the roll-out is complete"
    $tools = New-Tools
    $plain = [pscustomobject]@{ name = "p"; follow = $null }
    Check (@(Get-HordeServiceRolloutVerdict -Definitions @($plain) -Services @([pscustomobject]@{ name = "p"; code = "running"; reason = "r" })).Count -eq 0 -and @(Get-HordeServiceRolloutVerdict -Definitions @($plain) -Services @([pscustomobject]@{ name = "p"; code = "backing-off"; reason = "r" })).Count -eq 1 -and @(Get-HordeServiceRolloutVerdict -Definitions @($plain) -Services @()).Count -eq 1) "a service that follows nothing has nothing to roll out; one that is failing, or was not looked at, is not done"

    Write-Host ""
    Write-Host "--- X. status reads, and says first whether the supervisor itself is running ---" -ForegroundColor Cyan
    $W = New-World; $W.wanted = $revB; $W.clean = $false
    $h10 = New-Home "h10" $svcText
    Running 500 $t0.AddMinutes(-10) $t0.AddSeconds(-5)
    Seed $h10 500 $t0.AddMinutes(-10)
    $rep = Get-HordeServiceStatusReport -HordeHome $h10 -Tools $tools -Now $t0
    Check ($rep.supervisor.state -ceq "never" -and (Format-HordeServiceStatus -Report $rep)[0] -like "supervisor: the supervisor has never run in this home*") "a home no pass has run in says so, first"
    Check ((Calls "fetch") -eq 0 -and (Calls "start") -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $h10 "services\journal.jsonl"))) "status asks no remote, starts nothing and writes nothing"
    $row = $rep.services[0]
    Check ($row.alive -ceq "yes" -and $row.pid -eq 500 -and $row.heartbeatAgeSeconds -eq 5 -and $row.runningRevision -ceq $revA -and $row.wantedRevision -ceq $revB -and $row.current -eq $false -and $row.next -ceq "wait" -and $row.nextReason -like "*local changes*") "each service: alive, its pid and heartbeat age, running against wanted, and what a pass would do"
    Write-HordeHeartbeat -Path (Get-HordeServiceTendHeartbeatPath -HordeHome $h10) -At $t0.AddSeconds(-100) -ProcessId 1 -ProcessStartedAt $t0 -TickSeconds 60
    Check ((Get-HordeServiceStatusReport -HordeHome $h10 -Tools $tools -Now $t0).supervisor.state -ceq "running") "a pass 100 s ago is the supervisor running"
    Write-HordeHeartbeat -Path (Get-HordeServiceTendHeartbeatPath -HordeHome $h10) -At $t0.AddSeconds(-900) -ProcessId 1 -ProcessStartedAt $t0 -TickSeconds 60
    $stale = Get-HordeServiceStatusReport -HordeHome $h10 -Tools $tools -Now $t0
    $text = Format-HordeServiceStatus -Report $stale
    Check ($stale.supervisor.state -ceq "stale" -and $text[0] -like "supervisor: THE SUPERVISOR IS NOT RUNNING: its last pass was 900 s ago*nothing here is being kept alive or updated") "a pass 15 minutes ago is the supervisor NOT running, said plainly in the first line"
    $null = Pass $h10
    $rep = Get-HordeServiceStatusReport -HordeHome $h10 -Tools $tools -Now $W.now
    $text = (Format-HordeServiceStatus -Report $rep) -join "`n"
    Check ($text -like "*svc: alive*" -and $text -like "*revision: running aaaaaaaaa, wanted bbbbbbbbb (NOT CURRENT)*" -and $text -like "*last action: none yet*" -and $text -like "*failures in a row: 0; escalation outstanding: YES (checkout:dirty)*") "the text says the revisions, the last action, the failures and the escalation outstanding"
    $json = ConvertTo-Json -InputObject (ConvertTo-HordeServiceStatusRecord -Report $rep) -Depth 8 -Compress
    $parsed = $json | ConvertFrom-Json
    Check ($parsed.services[0].name -ceq "svc" -and $parsed.services[0].escalationOutstanding -eq $true -and @("running", "stale", "unknown") -ccontains $parsed.supervisor.state -and $parsed.definitions.state -ceq "read") "-Json carries the same, and says in one word whether an escalation is outstanding"
    $rep3 = Get-HordeServiceStatusReport -HordeHome $h3 -Tools $tools -Now $t0
    $json3 = ConvertTo-Json -InputObject (ConvertTo-HordeServiceStatusRecord -Report $rep3) -Depth 8 -Compress
    Check (($json3 | ConvertFrom-Json).services[0].lastAction.at -like "2026-10-13T12:00:*Z" -and -not $json3.Contains("Date(") -and ((Format-HordeServiceStatus -Report $rep3) -join " ") -like "*last action: 2026-10-13 12:00:* UTC restart-for-update (confirm) done - updated to bbbbbbbbb*") "a last action is shown with its time, and in -Json as text that reads back"
    $rep8 = Get-HordeServiceStatusReport -HordeHome $refused -Tools $tools -Now $t0
    Check (((Format-HordeServiceStatus -Report $rep8) -join " ") -like "*NO SERVICE IS SUPERVISED until that file is mended*") "a refused definitions file is said as what it is: nothing is supervised"
    $rep2 = Get-HordeServiceStatusReport -HordeHome $h2 -Tools $tools -Now $t0
    Check ($rep2.services[0].alive -ceq "unknown" -and ((Format-HordeServiceStatus -Report $rep2) -join " ") -like "*svc: UNKNOWN*left alone until its state file is mended or removed*") "a service whose state file cannot be read is shown as unknown, with what to do"

    Write-Host ""
    Write-Host "--- XI. the schedule: the supervisor is one job, every minute, in the person's session ---" -ForegroundColor Cyan
    $savedHome = $env:HORDE_HOME
    $env:HORDE_HOME = $h0
    $saveSchedulers = @($script:HordeSchedulers)
    try {
        $horde = Join-Path $root "horde.ps1"
        $job = New-HordeServiceTendJob -HordeScript $horde -Name "Horde services tend TEST" -Folder "HordeTest" -Disabled
        Check ($job.script -eq $horde -and (@($job.arguments) -join " ") -eq "services tend" -and $job.environment["HORDE_HOME"] -eq $h0 -and $job.hordeHome -eq $h0) "the job is this checkout's horde, services tend, with this shell's Horde home"
        Check ($job.everyMinutes -eq 1 -and $job.timeLimitMinutes -eq 1 -and $job.withPerson -eq $true -and $job.disabled) "every minute, stopped at a minute, in the person's own session; disabled when asked"
        Check ((Read-HordeJobMarker -Description $job.description).marked) "it carries Horde's marker, so only Horde's own job is ever replaced or removed"
        $script:HordeSchedulers.Clear()
        $fake = @{ jobs = @{}; installs = 0 }
        Register-HordeScheduler -Name "fake" -Available { $true } -Install { param($j) $fake.installs++; $fake.jobs[$j.folder + "\" + $j.name] = $j } -Remove { param($n, $f) if ($fake.jobs.ContainsKey($f + "\" + $n)) { $fake.jobs.Remove($f + "\" + $n); $true } else { $false } } -Status { param($n, $f) if ($fake.jobs.ContainsKey($f + "\" + $n)) { $j = $fake.jobs[$f + "\" + $n]; New-HordeKnown -Value ([pscustomobject]@{ enabled = (-not $j.disabled); state = "Ready"; everyMinutes = $j.everyMinutes; marked = $true; home = $j.hordeHome; logonType = "fake"; lastRunAt = $null; lastResult = 0; nextRunAt = $null }) } else { New-HordeAbsent -Note "none" } }
        $out = @(Invoke-HordeServiceSchedule -Action install -TaskName "fake tend" -Folder "HordeTest" -HordeScript $horde)
        Check ($fake.installs -eq 1 -and $fake.jobs["HordeTest\fake tend"].withPerson -and $out[0] -like "installed 'fake tend' in fake folder HordeTest: every minute, in the person's own session*") "install hands the job to the scheduler and says what it did"
        $stat = @(Invoke-HordeServiceSchedule -Action status -TaskName "fake tend" -Folder "HordeTest" -HordeScript $horde)
        Check ($stat[0] -like "'fake tend' in fake folder HordeTest: enabled, Ready, every 1 minute(s)*Horde's" -and $stat[2] -like "*horde services status*") "status shows the job, and where to look for whether its passes work"
        Check ((@(Invoke-HordeServiceSchedule -Action remove -TaskName "fake tend" -Folder "HordeTest" -HordeScript $horde))[0] -like "removed*Nothing that is running was stopped*") "unschedule removes the job and stops nothing"
        Check ((@(Invoke-HordeServiceSchedule -Action status -TaskName "fake tend" -Folder "HordeTest" -HordeScript $horde))[0] -like "*is not installed: no service is being supervised") "and then status says nothing is supervised"
        Check ((@(Invoke-HordeServiceSchedule -Action remove -TaskName "fake tend" -Folder "HordeTest" -HordeScript $horde))[0] -like "no job*") "removing what is not there says so"
        Check ((Throws { Invoke-HordeServiceSchedule -Action install -TaskName "fake tend" -Folder "Microsoft" -HordeScript $horde } "not one of Horde's scheduler folders") -and (Throws { Invoke-HordeServiceSchedule -Action remove -TaskName "fake tend" -Folder "Microsoft" -HordeScript $horde } "not one of Horde's scheduler folders") -and (Throws { Invoke-HordeServiceSchedule -Action status -TaskName "C:\Windows\x" -Folder "HordeTest" -HordeScript $horde } "not a job name")) "it acts only in Horde's own scheduler folders and on plain job names - when removing and showing, as when installing"
        Register-HordeScheduler -Name "fake" -Available { $true } -Install { param($j) } -Remove { param($n, $f) $false } -Status { param($n, $f) New-HordeAbsent -Note "none" }
        Check (Throws { Invoke-HordeServiceSchedule -Action install -TaskName "fake tend" -Folder "HordeTest" -HordeScript $horde } "did not keep") "a scheduler that does not keep the job makes install fail"
    } finally {
        $script:HordeSchedulers.Clear()
        foreach ($s in $saveSchedulers) { [void]$script:HordeSchedulers.Add($s) }
        $env:HORDE_HOME = $savedHome
    }

    Write-Host ""
    Write-Host "--- XII. the port: unknown unless an adapter says otherwise ---" -ForegroundColor Cyan
    $script:HordeServiceHosts.Clear()
    Check ((Get-HordePersonIdleSeconds).state -ceq "unknown" -and (Get-HordePersonIdleSeconds).reason -like "*no service host adapter is loaded*") "with no adapter, whether the person is idle is unknown"
    $launch = New-HordeServiceLaunch -Kind "program" -Program "C:\x\y.exe" -Arguments @("a")
    Check ((Start-HordeServiceProcess -Launch $launch).state -ceq "unknown") "and a start is unknown: nothing was started"
    Register-HordeServiceHost -Name "elsewhere" -Applies { $false } -IdleSeconds { New-HordeKnown -Value 5 } -Start { param($L) $null }
    Check ((Get-HordePersonIdleSeconds).reason -like "*no service host adapter is for this system*") "an adapter for another system is not used"
    $handed = @{ launch = $null; closed = $null }
    Register-HordeServiceHost -Name "standin" -Applies { $true } -IdleSeconds { New-HordeKnown -Value 42 } -Start { param($L) $handed.launch = $L; New-HordeKnown -Value ([pscustomobject]@{ pid = 9; startedAt = $t0 }) }
    Check ((Get-HordePersonIdleSeconds).value -eq 42) "an adapter's idle seconds are passed on"
    $made = Start-HordeServiceProcess -Launch $launch
    Check ($made.state -ceq "known" -and $made.value.pid -eq 9 -and $made.value.startedAt -eq $t0 -and $handed.launch.program -ceq "C:\x\y.exe") "and its start, given the launch as data"
    Check ((Close-HordeServiceWindow -ProcessId 9 -Handle 100).reason -like "*the standin adapter cannot do that*") "an adapter that cannot close a window says so, as an unknown"
    Register-HordeServiceHost -Name "standin" -Applies { $true } -IdleSeconds { New-HordeKnown -Value -3 } -Start { param($L) New-HordeKnown -Value ([pscustomobject]@{ pid = 9 }) } -CloseWindow { param($P, $H) $handed.closed = ("" + $P + ":" + $H); New-HordeKnown -Value "asked" }
    Check ((Get-HordePersonIdleSeconds).state -ceq "unknown") "a negative idle time is not an answer"
    Check ((Start-HordeServiceProcess -Launch $launch).reason -like "*did not say which process it made and when it started*") "a start that names a pid and no start time is not an answer: the pair is the identity"
    Register-HordeServiceHost -Name "standin" -Applies { $true } -IdleSeconds { "idle" } -Start { param($L) throw "boom" } -CloseWindow { param($P, $H) $handed.closed = ("" + $P + ":" + $H); New-HordeKnown -Value "asked" }
    Check ((Get-HordePersonIdleSeconds).state -ceq "unknown" -and (Quiet { Start-HordeServiceProcess -Launch $launch }).reason -like "the start: the standin adapter failed*boom*") "an adapter that answers with a word, or throws, is unknown with the reason"
    Register-HordeServiceHost -Name "standin" -Applies { $true } -IdleSeconds { "idle" } -Start { param($L) New-HordeKnown -Value ([pscustomobject]@{ pid = 9; startedAt = "a moment ago" }) } -CloseWindow { param($P, $H) $handed.closed = ("" + $P + ":" + $H); New-HordeKnown -Value "asked" }
    Check ((Quiet { Start-HordeServiceProcess -Launch $launch }).reason -like "*did not say which process it made and when it started*") "and a start whose start time is a word, not a time, is not an answer either"
    Check ((Close-HordeServiceWindow -ProcessId 9 -Handle 100).state -ceq "known" -and $handed.closed -ceq "9:100") "a close is handed the process and the window"
    Check ((Close-HordeServiceWindow -ProcessId 9 -Handle 0).state -ceq "unknown") "a close with no window named is refused before any adapter is asked"
    Check (Throws { New-HordeServiceLaunch -Kind "horde" -Script "C:\h.ps1" -Words @("relay") -Switches @("Force; calc") } "not a parameter name") "a launch refuses a switch that is not a name"
    Check (Throws { New-HordeServiceLaunch -Kind "horde" -Script "C:\h.ps1" -Words @("-x") } "not a word") "and a word that starts with a dash"
    Check (Throws { New-HordeServiceLaunch -Kind "horde" -Script "h.ps1" -Words @("relay") } "absolute path") "and a script that is not an absolute path"
    Check (Throws { New-HordeServiceLaunch -Kind "horde" -Script "C:\h.ps1" -Words @("relay") -Environment @{ "A;B" = "1" } } "not an environment variable name") "and an environment name that is not one"
    Check (Throws { New-HordeServiceLaunch -Kind "program" -Program "C:\x.exe" -Arguments @("a`nb") } "control character") "and a value with a line break"
    Check (Throws { Start-HordeServiceProcess -Launch ([pscustomobject]@{ kind = "program" }) } "New-HordeServiceLaunch") "a start takes only a launch the port made"

    Write-Host ""
    Write-Host "--- XIII. a window is closed only when its report is about this process ---" -ForegroundColor Cyan
    $report = Join-Path $work "report.json"
    $winDef = [pscustomobject]@{ name = "win"; checkout = ""; hordeHome = ""; stop = [pscustomobject]@{ kind = "window"; report = $report; waitSeconds = 20; words = @(); named = @{}; switches = @() } }
    $handed.closed = $null
    $ask = Request-HordeServiceStop -Definition $winDef -Process ([pscustomobject]@{ pid = 9; startedAt = $t0 })
    Check (-not $ask.ok -and $ask.detail -like "*there is no report file*" -and $null -eq $handed.closed) "no report file: nothing is asked to close"
    [System.IO.File]::WriteAllText($report, '{ "schemaVersion": 2, "pid": 8, "handle": 4660, "title": "x" }')
    $ask = Request-HordeServiceStop -Definition $winDef -Process ([pscustomobject]@{ pid = 9; startedAt = $t0 })
    Check (-not $ask.ok -and $ask.detail -like "*the report file is about process 8, not its process 9*" -and $null -eq $handed.closed) "a report left by another process names a window that may be anyone's now: nothing is sent"
    [System.IO.File]::WriteAllText($report, '{ "schemaVersion": 2, "pid": 9, "handle": 4660, "title": "x" }')
    $ask = Request-HordeServiceStop -Definition $winDef -Process ([pscustomobject]@{ pid = 9; startedAt = $t0 })
    Check ($ask.ok -and $handed.closed -ceq "9:4660") "a report about this process: its window is asked to close"
    [System.IO.File]::WriteAllText($report, '{ "pid": 9, "handle": 0 }')
    Check ((Read-HordeServiceWindowReport -Path $report).reason -like "*names no process and window*") "a report with no window handle is unknown"
    [System.IO.File]::WriteAllText($report, 'not json')
    Check ((Read-HordeServiceWindowReport -Path $report).state -ceq "unknown") "and so is one that is not JSON"
    $script:HordeServiceHosts.Clear()
    foreach ($a in $savedHosts) { [void]$script:HordeServiceHosts.Add($a) }

    Write-Host ""
    Write-Host "--- XIV. Windows: no value is ever parsed as code ---" -ForegroundColor Cyan
    $q = { param([string]$Text) return (ConvertTo-HordeServiceArgument -Text $Text) }
    Check ((& $q "plain") -ceq "plain" -and (& $q "") -ceq '""' -and (& $q "a b") -ceq '"a b"') "a plain argument stands as it is; an empty one, or one with a space, is quoted"
    Check ((& $q 'say "hi"') -ceq '"say \"hi\""' -and (& $q 'C:\dir with space\') -ceq '"C:\dir with space\\"' -and (& $q 'a\\"b') -ceq '"a\\\\\"b"' -and (& $q 'C:\plain\path') -ceq 'C:\plain\path') "quotes are escaped, and backslashes doubled only before a quote"
    $hostile = "it's `$(Set-Content x) ``n & %PATH% `"q`""
    $l = New-HordeServiceLaunch -Kind "horde" -Script (Join-Path $work "st ub's\horde.ps1") -Words @("relay", "run") -Named ([ordered]@{ Relay = $hostile }) -Switches @("Hidden") -Environment @{ HORDE_HOME = $hostile } -WorkingDirectory $work -LogFile (Join-Path $work "l og.txt")
    $script = ConvertTo-HordeWindowsServiceScript -Launch $l
    Check (-not $script.Contains("Set-Content") -and -not $script.Contains("%PATH%") -and -not $script.Contains("st ub") -and -not $script.Contains("l og.txt")) "no value appears in the command as text: not the script, the home, a named value or the log"
    Check ($script.Contains(" -Relay (& `$d '") -and $script.Contains(" -Hidden") -and $script.Contains("SetEnvironmentVariable('HORDE_HOME', (& `$d '")) "parameter and environment NAMES are written as they are, each value decoded at run time"
    Check ($script.Contains("6>&1") -and -not $script.Contains("*>&1") -and -not $script.Contains("2>&1") -and $script.Contains("[System.Console]::SetError(`$w)")) "the service's lines are logged without redirecting its error stream (CONTRIBUTING 12)"
    $line = ConvertTo-HordeWindowsServiceCommandLine -Launch $l
    Check ($line -match '\A\S*powershell\.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand [A-Za-z0-9+/=]+\z' -and $line.StartsWith(([System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe") + " "))) "the command line is the system's own shell, fixed switches and base64"
    $pl = ConvertTo-HordeWindowsServiceCommandLine -Launch (New-HordeServiceLaunch -Kind "program" -Program "C:\Program Files\t\t.exe" -Arguments @("-q", "a b", 'c"d'))
    Check ($pl -ceq '"C:\Program Files\t\t.exe" -q "a b" "c\"d"') "a program launch is the program and its arguments, each quoted by the one rule"
    Check ((Get-HordeWindowsSessionSeesPerson -Interactive $false -SessionId 1) -like "*not interactive*" -and (Get-HordeWindowsSessionSeesPerson -Interactive $true -SessionId 0) -like "*session 0*" -and (Get-HordeWindowsSessionSeesPerson -Interactive $true -SessionId 2) -eq "") "a process outside the person's own session cannot see their input, and says why"

    Write-Host ""
    Write-Host "--- XV. Windows: one real start, of this suite's own stub ---" -ForegroundColor Cyan
    $stubDir = Join-Path $work "st ub's & co"
    [void][System.IO.Directory]::CreateDirectory($stubDir)
    $stub = Join-Path $stubDir "horde.ps1"
    $seenFile = Join-Path $work "seen.txt"
    # The stub writes what it received, says a line to the host, and a line to the process's error
    # stream, then exits. It ignores every word: it is not horde.
    [System.IO.File]::WriteAllText($stub, ('$t = $env:HORDE_HOME + "|" + (@($args) -join ","); [System.IO.File]::WriteAllText("' + $seenFile + '", $t, (New-Object System.Text.UTF8Encoding($false))); Write-Host "stub said hello"; [Console]::Error.WriteLine("stub failed plainly"); exit 0'))
    $logFile = Join-Path $work "stub l og.txt"
    $real = New-HordeServiceLaunch -Kind "horde" -Script $stub -Words @("relay", "run") -Named ([ordered]@{ Relay = $hostile }) -Environment @{ HORDE_HOME = $hostile } -WorkingDirectory $work -LogFile $logFile
    $startedReal = Start-HordeServiceProcess -Launch $real
    if ($startedReal.state -ceq "known") { [void]$children.Add($startedReal.value) }
    Check ($startedReal.state -ceq "known" -and $startedReal.value.pid -gt 0 -and $startedReal.value.startedAt -is [datetime]) ("the adapter starts the process and names it by pid and start (" + $startedReal.reason + ")")
    $deadline = (Get-Date).AddSeconds(60)
    while (-not (Test-Path -LiteralPath $seenFile) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
    $got = ""; if (Test-Path -LiteralPath $seenFile) { $got = [System.IO.File]::ReadAllText($seenFile) }
    Check ($got -ceq ($hostile + "|relay,run,-Relay:," + $hostile) -or $got -ceq ($hostile + "|relay,run,-Relay," + $hostile)) ("the stub received the home, the words and the named value exactly, hostile characters and all (" + $got + ")")
    Check (-not (Test-Path -LiteralPath (Join-Path $work "x"))) "and nothing in a value ran"
    $deadline = (Get-Date).AddSeconds(30)
    $logText = ""
    while ((Get-Date) -lt $deadline) { if (Test-Path -LiteralPath $logFile) { $logText = Read-HordeSharedText -Path $logFile; if ($logText.Contains("stub failed plainly") -and $logText.Contains("stub said hello")) { break } }; Start-Sleep -Milliseconds 300 }
    Check ($logText -match '(?m)^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d stub said hello' -and $logText.Contains("stub failed plainly")) "what it said, with the time, and what it wrote to the error stream are both in its log"

    Write-Host ""
    Write-Host "--- XVI. a process is ended only when it is still the process it was ---" -ForegroundColor Cyan
    Check ((Get-HordeServiceProcessEntry -ProcessId $PID).state -ceq "known" -and (Get-HordeServiceProcessEntry -ProcessId $PID).value.startedAt.Ticks -eq (Get-HordeHeartbeatSelf).startedAt.Ticks) "this process is found, with the start it names itself by"
    Check ((Get-HordeServiceProcessEntry -ProcessId 999999).state -ceq "absent") "a pid nothing has is absent"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-HordeServiceShell); $psi.Arguments = "-NoProfile -Command Start-Sleep -Seconds 120"; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $sleeper = [System.Diagnostics.Process]::Start($psi)
    $mine = [pscustomobject]@{ pid = $sleeper.Id; startedAt = $sleeper.StartTime.ToUniversalTime() }
    [void]$children.Add($mine)
    $wrong = Stop-HordeServiceProcess -Process ([pscustomobject]@{ pid = $sleeper.Id; startedAt = $mine.startedAt.AddMinutes(-7) })
    Check ($wrong.ok -and $wrong.detail -like "*is another process now*nothing was ended*" -and -not $sleeper.HasExited) "asked to end a pid whose start time is not the one recorded, it ends NOTHING: the pid belongs to someone else now"
    $right = Stop-HordeServiceProcess -Process $mine
    Check ($right.ok -and $right.detail -like "*was ended*" -and $sleeper.WaitForExit(5000)) "asked with the right start time, it ends the process"
    Check ((Stop-HordeServiceProcess -Process $mine).detail -like "*already ended*") "and one already gone is done"
    $sleeper.Dispose()

    Write-Host ""
    Write-Host "--- XVII. a horde command of a checkout, run to its end ---" -ForegroundColor Cyan
    $fakeCo = Join-Path $work "fake co"
    [void][System.IO.Directory]::CreateDirectory($fakeCo)
    $ranFile = Join-Path $work "ran.txt"
    [System.IO.File]::WriteAllText((Join-Path $fakeCo "horde.ps1"), ('[System.IO.File]::WriteAllText("' + $ranFile + '", ($env:HORDE_HOME + "|" + (@($args) -join ","))); if ($args[0] -eq "fail") { [Console]::Error.WriteLine("it went wrong"); exit 1 }; exit 0'))
    $ran = Invoke-HordeServiceHordeCommand -Checkout $fakeCo -HordeHome (Join-Path $work "served home") -Words @("relay", "stop") -Named ([ordered]@{ Reason = "a b" }) -Switches @("Quiet")
    Check ($ran.ok -and [System.IO.File]::ReadAllText($ranFile) -ceq ((Join-Path $work "served home") + "|relay,stop,-Reason,a b,-Quiet")) "the command gets its words, its named values and switches, and the home it serves"
    $bad = Invoke-HordeServiceHordeCommand -Checkout $fakeCo -HordeHome $work -Words @("fail")
    Check (-not $bad.ok -and $bad.detail -like "*horde fail failed with exit 1*it went wrong*") "a command that fails is said so, with what it wrote"
    Check ((Invoke-HordeServiceHordeCommand -Checkout $work -HordeHome $work -Words @("x")).detail -like "*no horde entry point*") "a checkout with no horde in it is said so"
    $slow = Invoke-HordeServiceProgram -Program (Get-HordeServiceShell) -Arguments @("-NoProfile", "-Command", "Start-Sleep -Seconds 60") -TimeoutSeconds 2
    Check ($slow.timedOut -and $slow.err -like "*did not finish within 2 s and was ended*") "a program that passes its time limit is ended and counted as failed"
    Check (-not (Invoke-HordeServiceProgram -Program (Join-Path $work "nothing.exe")).started) "a program that is not there did not start"

    Write-Host ""
    Write-Host "--- XVIII. the revision paths, on throwaway repositories ---" -ForegroundColor Cyan
    # No hook of this machine runs on the fixture's commits: the hooks folder is an empty one of the suite's.
    $noHooks = (Join-Path $work "no-hooks") -replace '\\', '/'
    [void][System.IO.Directory]::CreateDirectory($noHooks)
    $gitEnv = @{ GIT_AUTHOR_NAME = "t"; GIT_AUTHOR_EMAIL = "t@example.invalid"; GIT_COMMITTER_NAME = "t"; GIT_COMMITTER_EMAIL = "t@example.invalid"; GIT_CONFIG_NOSYSTEM = "1" }
    function G { param([string]$Dir, [string[]]$A) $x = Invoke-HordeServiceGit -Checkout $Dir -Arguments (@("-c", "commit.gpgsign=false", "-c", ("core.hooksPath=" + $noHooks), "-c", "core.autocrlf=false") + $A) -Environment $gitEnv -TimeoutSeconds 60; if (-not $x.ok) { throw ("git " + ($A -join " ") + " failed in the fixture: " + $x.detail) }; return $x.out }
    function Commit { param([string]$Dir, [string]$File, [string]$Text, [string]$Message) [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName((Join-Path $Dir $File))); [System.IO.File]::WriteAllText((Join-Path $Dir $File), $Text); $null = G $Dir @("add", "-A"); $null = G $Dir @("commit", "-q", "-m", $Message); return (G $Dir @("rev-parse", "HEAD")) }
    $up = Join-Path $work "upstream"; $live = Join-Path $work "live"
    [void][System.IO.Directory]::CreateDirectory($up)
    $null = G $up @("init", "-q", "-b", "main")
    $c1 = Commit $up "horde.ps1" 'if ($args[0] -eq "version") { Write-Output "horde 0.0.1"; exit 0 }; exit 3' "one"
    [System.IO.File]::WriteAllText((Join-Path $up "VERSION"), "0.0.1")
    $null = G $work @("clone", "-q", $up, $live)
    $null = G $live @("checkout", "-q", "--detach", $c1)
    $liveDef = (Read-HordeServiceDefinitionsText -Text ('{ "schemaVersion": 1, "settings": { "svc": { "checkout": "' + (Esc $live) + '", "hordeHome": "' + $served + '", "start": { "kind": "horde", "words": ["relay", "run"] }, "stop": { "kind": "kill" }, "follow": { "restart": "any" } } } }')).services[0]
    $st = Get-HordeServiceCheckoutState -Definition $liveDef -RunningRevision $c1
    Check ($st.checkout.state -ceq "known" -and $st.checkout.value.head -ceq $c1 -and $st.wanted.value.revision -ceq $c1 -and $st.wanted.value.fastForward) "a checkout on what its remote wants reads as current"
    $c2 = Commit $up "lib.ps1" 'function Get-Two { return 2 }' "two"
    Check ((Get-HordeServiceCheckoutState -Definition $liveDef -RunningRevision $c1).wanted.value.revision -ceq $c1) "CONTROL: before a fetch the checkout does not know of the new revision"
    $f = Update-HordeServiceRemote -Definition $liveDef
    $st = Get-HordeServiceCheckoutState -Definition $liveDef -RunningRevision $c1
    Check ($f.ok -and $st.wanted.value.revision -ceq $c2 -and $st.wanted.value.fastForward -and $st.checkout.value.detached -and $st.checkout.value.clean -and $st.checkout.value.head -ceq $c1) "the fetch brings the new revision: wanted, a fast-forward, the checkout detached and clean - and not moved"
    $null = G $up @("checkout", "-q", "-b", "other")
    $cOther = Commit $up "other.ps1" '1' "on another branch"
    $null = G $up @("checkout", "-q", "main")
    $null = Update-HordeServiceRemote -Definition $liveDef
    $otherRef = Invoke-HordeServiceGit -Checkout $live -Arguments @("rev-parse", "--verify", "--quiet", "refs/remotes/origin/other")
    Check (-not $otherRef.ok -or $otherRef.out -cne $cOther) "the fetch takes the configured branch only: another branch's new commit is not brought"
    $gone = (Read-HordeServiceDefinitionsText -Text ('{ "schemaVersion": 1, "settings": { "svc": { "checkout": "' + (Esc $live) + '", "hordeHome": "' + $served + '", "start": { "kind": "horde", "words": ["relay"] }, "stop": { "kind": "kill" }, "follow": { "remote": "nowhere" } } } }')).services[0]
    $noRemote = Update-HordeServiceRemote -Definition $gone
    Check (-not $noRemote.ok -and $noRemote.detail -like "git fetch:*" -and (Get-HordeServiceCheckoutState -Definition $gone).wanted.reason -like "*has not been fetched*") "a remote the checkout does not have fails the fetch with the tool's reason, and what is wanted stays unknown"

    $scratchRoot = Join-Path $work "scratch"
    [void][System.IO.Directory]::CreateDirectory($scratchRoot)
    $indexBefore = [System.IO.File]::GetLastWriteTimeUtc((G $live @("rev-parse", "--git-path", "index") | ForEach-Object { if ([System.IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path $live $_ } }))
    $v = Test-HordeServiceRevision -Definition $liveDef -Revision $c2 -TempRoot $scratchRoot -CheckSeconds 120
    $indexAfter = [System.IO.File]::GetLastWriteTimeUtc((G $live @("rev-parse", "--git-path", "index") | ForEach-Object { if ([System.IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path $live $_ } }))
    Check ($v.ok -and $v.detail -like "checked*") ("a good revision passes its self-check (" + $v.detail + ")")
    Check ((G $live @("rev-parse", "HEAD")) -ceq $c1 -and (G $live @("status", "--porcelain")) -eq "" -and -not (Test-Path -LiteralPath (Join-Path $live "lib.ps1"))) "the live checkout was not moved, changed or added to by the check"
    Check ($indexAfter -eq $indexBefore) "not even its index was written: the copy went through a private one"
    Check (@(Get-ChildItem -LiteralPath $scratchRoot).Count -eq 0) "and the scratch copy is gone"
    Check ((Test-HordeServiceRevision -Definition $liveDef -Revision $c1 -TempRoot $scratchRoot).detail -like "*no longer what origin/main names*") "a revision that is not what the configured remote names is refused, before anything is copied"
    Check (-not (Test-HordeServiceRevision -Definition $liveDef -Revision "HEAD" -TempRoot $scratchRoot).ok) "something that is not a revision is refused"
    $c3 = Commit $up "cli\Broken.ps1" 'function Broken { if ( }' "three, with a file that does not parse"
    $null = Update-HordeServiceRemote -Definition $liveDef
    $v3 = Test-HordeServiceRevision -Definition $liveDef -Revision $c3 -TempRoot $scratchRoot -CheckSeconds 120
    Check (-not $v3.ok -and $v3.detail -like "*cli/Broken.ps1 does not parse*") "a revision with a file that does not parse fails the check, though horde version would have run"
    $null = G $up @("rm", "-q", "cli/Broken.ps1")
    [System.IO.File]::WriteAllText((Join-Path $up "horde.ps1"), 'Write-Output "something else"; exit 1')
    $null = G $up @("add", "-A"); $null = G $up @("commit", "-q", "-m", "four, whose version fails")
    $c4 = G $up @("rev-parse", "HEAD")
    $null = Update-HordeServiceRemote -Definition $liveDef
    $v4 = Test-HordeServiceRevision -Definition $liveDef -Revision $c4 -TempRoot $scratchRoot -CheckSeconds 120
    Check (-not $v4.ok -and $v4.detail -like "*horde version failed from it with exit 1*") "a revision whose horde version fails is refused"
    [System.IO.File]::WriteAllText((Join-Path $up "horde.ps1"), 'if ($args[0] -eq "version") { Write-Output "horde 0.0.5"; exit 0 }; if (($args -join " ") -eq "services status") { exit 0 }; exit 3')
    [void][System.IO.Directory]::CreateDirectory((Join-Path $up "cli\commands"))
    [System.IO.File]::WriteAllText((Join-Path $up "cli\commands\services.ps1"), '$HordeCommand = @{ name = "services" }')
    $c5 = Commit $up "test\Fixture.ps1" 'function { broken on purpose' "five: a broken file under a folder named test, and the supervisor's own command"
    $null = Update-HordeServiceRemote -Definition $liveDef
    $v5 = Test-HordeServiceRevision -Definition $liveDef -Revision $c5 -TempRoot $scratchRoot -CheckSeconds 120
    Check ($v5.ok) ("a broken file under a folder named test does not fail the check - fixtures hold them on purpose - and the supervisor's own command ran (" + $v5.detail + ")")
    $tip = Commit $up "horde.ps1" 'if ($args[0] -eq "version") { Write-Output "horde 0.0.6"; exit 0 }; [Console]::Error.WriteLine("services cannot load"); exit 1' "six: the supervisor's own command fails"
    $null = Update-HordeServiceRemote -Definition $liveDef
    $v6 = Test-HordeServiceRevision -Definition $liveDef -Revision $tip -TempRoot $scratchRoot -CheckSeconds 120
    Check (-not $v6.ok -and $v6.detail -like "*horde services status failed from it with exit 1*services cannot load*") "a revision in which the supervisor's own command fails is refused: it would take the roll-back away with it"
    $progDef = (Read-HordeServiceDefinitionsText -Text ('{ "schemaVersion": 1, "settings": { "svc": { "checkout": "' + (Esc $live) + '", "start": { "kind": "program", "program": "C:\\x.exe" }, "stop": { "kind": "kill" }, "follow": { "restart": "any" } } } }')).services[0]
    Check ((Test-HordeServiceRevision -Definition $progDef -Revision $tip -TempRoot $scratchRoot).ok) "a service that is not a horde command gets the checks that run nothing: the remote's revision, a fast-forward, and every file parsing"
    Check (@(Get-ChildItem -LiteralPath $scratchRoot).Count -eq 0) "every failed check also removed its scratch copy"

    $adv = Move-HordeServiceCheckout -Definition $liveDef -Revision $c2
    Check (-not $adv.ok -and $adv.detail -like "*no longer what origin/main names*" -and (G $live @("rev-parse", "HEAD")) -ceq $c1) "a move to a revision the remote has since moved past is refused: the checkout stays"
    [System.IO.File]::WriteAllText((Join-Path $live "horde.ps1"), "somebody's edit")
    $dirty = Move-HordeServiceCheckout -Definition $liveDef -Revision $tip
    Check (-not $dirty.ok -and $dirty.detail -like "*local changes; they are never written over*" -and [System.IO.File]::ReadAllText((Join-Path $live "horde.ps1")) -ceq "somebody's edit" -and (G $live @("rev-parse", "HEAD")) -ceq $c1) "a checkout with a local change is not moved, and the change is still there"
    $st = Get-HordeServiceCheckoutState -Definition $liveDef -RunningRevision $c1
    Check ($st.checkout.value.clean -eq $false -and $st.checkout.value.detached) "and the pass's own look sees it is not clean"
    $null = G $live @("checkout", "-q", "--", "horde.ps1")
    $null = G $live @("checkout", "-q", "-b", "somebodys-work")
    $onBranch = Move-HordeServiceCheckout -Definition $liveDef -Revision $tip
    $st = Get-HordeServiceCheckoutState -Definition $liveDef -RunningRevision $c1
    Check (-not $onBranch.ok -and $onBranch.detail -like "*on the branch somebodys-work*" -and $st.checkout.value.detached -eq $false -and $st.checkout.value.branch -ceq "somebodys-work") "a checkout on a branch is not moved: nobody's branch is moved or left behind"
    $null = G $live @("checkout", "-q", "--detach", $c1)
    $ok = Move-HordeServiceCheckout -Definition $liveDef -Revision $tip
    Check ($ok.ok -and (G $live @("rev-parse", "HEAD")) -ceq $tip -and (Invoke-HordeServiceGit -Checkout $live -Arguments @("symbolic-ref", "--quiet", "HEAD")).code -eq 1) "a clean, detached checkout is moved forward to the remote's revision, and stays detached"
    Check ((Move-HordeServiceCheckout -Definition $liveDef -Revision $tip).detail -like "*already on*") "a checkout already there is done"
    $back = Move-HordeServiceCheckout -Definition $liveDef -Revision $c1 -Back
    Check ($back.ok -and (G $live @("rev-parse", "HEAD")) -ceq $c1) "a roll-back goes back along the checkout's own history"
    Check ((Move-HordeServiceCheckout -Definition $liveDef -Revision $cOther -Back).detail -like "*not in the history of what is checked out*") "and nowhere else: a revision that is not an ancestor is refused"
    $null = G $live @("checkout", "-q", "--detach", $c1)
    $side = Commit $live "local.ps1" '1' "a local commit the remote does not have"
    $st = Get-HordeServiceCheckoutState -Definition $liveDef -RunningRevision $side
    $div = Move-HordeServiceCheckout -Definition $liveDef -Revision $tip
    Check ($st.wanted.value.fastForward -eq $false -and -not $div.ok -and $div.detail -like "*not a fast-forward*" -and (G $live @("rev-parse", "HEAD")) -ceq $side) "a checkout that has diverged is seen as not a fast-forward, and is not moved"
    $started = Start-HordeServiceNow -Definition ([pscustomobject]@{ name = "svc"; checkout = (Join-Path $work "empty"); hordeHome = $work; follow = $null; start = [pscustomobject]@{ kind = "horde"; words = @("x"); named = @{}; switches = @() } }) -SupervisorHome $h0
    Check (-not $started.ok -and $started.detail -like "*no horde entry point in its checkout*") "a start from a checkout with no horde in it fails before anything is started"
    $noProgram = Start-HordeServiceNow -Definition ([pscustomobject]@{ name = "svc"; checkout = ""; hordeHome = ""; follow = $null; start = [pscustomobject]@{ kind = "program"; program = (Join-Path $work "nothing.exe"); arguments = @() } }) -SupervisorHome $h0
    Check (-not $noProgram.ok -and $noProgram.detail -like "*is not there*") "and so does a program that is not there"

    Write-Host ""
    Write-Host "--- XIX. telling goes through a messenger, to the warchief's session ---" -ForegroundColor Cyan
    $pol = (Get-HordeServiceSettings -HordeHome $h1).values
    $notice = [pscustomobject]@{ id = "44444444-4444-4444-4444-444444444444"; kind = "escalate"; text = "service svc: it has not stayed up"; at = $t0; service = "svc" }
    Check ((Format-HordeServiceNoticeBody -Notice $notice) -ceq ("HORDE SERVICES - needs attention`nservice svc: it has not stayed up`nSee it with: horde services status")) "a notice says what is wrong and how to see the rest"
    Check ((Format-HordeServiceNoticeBody -Notice ([pscustomobject]@{ kind = "recovered"; text = "x" })) -like "HORDE SERVICES - recovered*") "a recovery says it is one"
    $none = Send-HordeServiceNotices -Notices @($notice) -HordeHome $h1 -Policy $pol -Seat { throw "the seat must not be read when there is no messenger" }
    Check (@($none.told).Count -eq 0 -and $none.problem -like "no messenger on this machine can deliver*") "with no messenger loaded nobody is told, and the reason is returned: nothing is typed anywhere"
} finally {
    # Every child this suite started, by the pid and start it recorded.
    foreach ($c in @($children)) { try { $null = Stop-HordeServiceProcess -Process $c } catch { } }
    $script:HordeServiceHosts.Clear()
    foreach ($a in $savedHosts) { [void]$script:HordeServiceHosts.Add($a) }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "a pass observes, decides, acts and journals; its hands leave a checkout or a process alone unless it is exactly the one they were given"
