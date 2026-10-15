# cli/ServicesTend - `horde services tend`: one pass of the supervisor over every defined service -
# observe, decide, act, journal - and what `status`, `schedule` and `horde rollout` are made of.
#
# THE PASS IS THE SUPERVISOR. Nothing here stays running: the scheduler (core/Schedule.ps1) starts a
# pass at start-up and every minute, whether or not anyone is signed in, and the operating system is
# what keeps THAT coming round, with a second job in the person's own session beside it
# (New-HordeServiceTendJob says why two, and what each cannot do). A pass looks at each service as it
# is now and takes the next step towards how it should be
# (core/Services.ps1, LEVEL-TRIGGERED), so a pass that was killed, or a machine that slept, costs a
# minute and nothing else. The pass writes its own heartbeat, and `status` says plainly when no pass
# has come round lately - the one failure the passes themselves cannot report.
#
# ONE PASS AT A TIME. A pass holds <home>\services\tend.lock from before it reads anything to after
# it has written everything (core/ServicesFiles.ps1); a second pass on the same home does nothing and
# says so. `horde rollout` waits for the lock rather than give up, because a person is waiting on it.
#
# CHEAP WHEN ALL IS WELL. For a service that is running the revision it should, a pass reads one
# heartbeat file, looks up one process, and runs the revision tool twice; the remote is asked at the
# interval of the setting fetchIntervalSeconds, not every pass; whether the person is idle is asked
# only when an update is actually waiting on it; and the journal gets a line when something is done
# or a wait begins, not on every pass while it lasts.
#
# WITHIN ONE PASS, STEPS FOLLOW EACH OTHER WHILE THERE IS TIME. An update is verify, stop, advance,
# start, confirm; left to one step a minute a service would be down for minutes. So after a step that
# worked the pass looks again and takes the next, until nothing is left to do, a step fails, or the
# pass's budget (the setting passBudgetSeconds) is spent - the scheduler ends a pass at one minute.
# THE STATE IS WRITTEN BEFORE EVERY STEP AND AFTER IT, so a pass ended between two steps is picked up
# exactly there by the next.
#
# THE TOOLS ARE HANDED IN (New-HordeServiceTools). Everything a pass does to the machine goes through
# a table of script blocks, so a suite can run every path of a pass with a clock it moves by hand,
# processes that exist only in a table, and a checkout that is a throwaway repository in temp - and so
# that no suite can start, stop or update anything real by forgetting to stub it: a suite makes its
# own table, and the real one is made only by the command.
#   THE BLOCKS TAKE WHAT THEY NEED AS ARGUMENTS, never from a closure: a closure runs in a scope of
#   its own, from which the functions the command loaded are not visible.
#
# TELLING IS LAST, AND ONCE. A decision's notice is kept in the service's state until a messenger has
# taken it (core/Services.ps1), so a pass that cannot tell anyone loses nothing. After the passes,
# everything still untold is handed to the one teller in one call.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

$script:HordeServiceTendJobName = "Horde services tend"
# The codes of a decision that mean "an update is part way": `horde rollout` waits these out.
$script:HordeServiceMovingCodes = @("stopping", "stop-overdue", "confirming", "starting", "update", "advance", "start-new", "start-previous", "retreat", "roll-back", "verify")
# The most steps one service may take in one pass. An update is five; eight leaves room for a
# roll-back begun in the same pass, and stops a decision that never settles from spinning.
$script:HordeServiceStepsMost = 8

function New-HordeServiceTools {
    # The real tools (header). Each block's parameters are its whole contract.
    return @{
        Now          = { return [datetime]::UtcNow }
        Sleep        = { param($Ms) Start-Sleep -Milliseconds $Ms }
        NewId        = { return [guid]::NewGuid().ToString() }
        ProcessEntry = { param($ProcessId) return (Get-HordeServiceProcessEntry -ProcessId $ProcessId) }
        Heartbeat    = { param($Path) return (Read-HordeHeartbeat -Path $Path) }
        Idle         = { return (Get-HordePersonIdleSeconds) }
        Desktop      = { return (Get-HordeServiceDesktop) }
        PersonPass   = { return (Test-HordeServicePersonJob) }
        Fetch        = { param($Definition, $Policy) return (Update-HordeServiceRemote -Definition $Definition -TimeoutSeconds $Policy.gitSeconds) }
        Checkout     = { param($Definition, $RunningRevision, $Policy, $Full) return (Get-HordeServiceCheckoutState -Definition $Definition -RunningRevision $RunningRevision -TimeoutSeconds $Policy.gitSeconds -Full:($Full -eq $true)) }
        ExitCode     = { param($Definition, $HordeHome, $Process) return (Read-HordeServiceExitRecord -Name $Definition.name -Process $Process -HordeHome $HordeHome) }
        Verify       = { param($Definition, $Revision, $Policy) return (Test-HordeServiceRevision -Definition $Definition -Revision $Revision -GitSeconds $Policy.gitSeconds -CheckSeconds $Policy.checkSeconds) }
        Advance      = { param($Definition, $Revision, $Policy) return (Move-HordeServiceCheckout -Definition $Definition -Revision $Revision -TimeoutSeconds $Policy.gitSeconds) }
        Retreat      = { param($Definition, $Revision, $Policy) return (Move-HordeServiceCheckout -Definition $Definition -Revision $Revision -Back -TimeoutSeconds $Policy.gitSeconds) }
        Start        = { param($Definition, $HordeHome, $Policy) return (Start-HordeServiceNow -Definition $Definition -SupervisorHome $HordeHome -TimeoutSeconds $Policy.gitSeconds) }
        Stop         = { param($Definition, $Process, $Policy) return (Request-HordeServiceStop -Definition $Definition -Process $Process) }
        Kill         = { param($Process) return (Stop-HordeServiceProcess -Process $Process) }
        # $null: nobody is told. The command sets it (cli/commands/services.ps1), a suite sets its own.
        TellAll      = $null
        # $null: the hosted phone page is not looked at (cli/RelayPublish.ps1). The command sets it, so
        # no suite can deploy anything by forgetting to stub it: param($HordeHome, $Policy, $Teller).
        PagePublish  = $null
    }
}

function Invoke-HordeServiceTool {
    # Call one tool and take its LAST output, so a block that leaks a value cannot change the answer.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)][string]$Name, [object[]]$With = @())
    return (@(& $Tools[$Name] @With) | Select-Object -Last 1)
}

function Get-HordeServiceObservation {
    # What this pass sees of one service: { observed; state }. observed is core/Services.ps1's shape;
    # state is the one handed in with what looking changed - when the remote was last asked, and what
    # went wrong. Every tool that throws or does not answer becomes an unknown with the reason.
    # -NoFetch is `status`: it reads, and never asks a remote. -ForceFetch is `rollout`: it asks now.
    param([Parameter(Mandatory = $true)]$Definition, [Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)]$Policy, [Parameter(Mandatory = $true)][datetime]$Now, [switch]$ForceFetch, [switch]$NoFetch, [string]$HordeHome = "")
    $s = Copy-HordeServiceState -State $State
    $verdictOf = {
        param($Claim)
        if ($null -eq $Claim) { return (New-HordeAbsent -Note "nothing names a process") }
        $entry = $null
        try { $entry = Invoke-HordeServiceTool -Tools $Tools -Name "ProcessEntry" -With @([int]$Claim.pid) } catch { $entry = New-HordeUnknown -Reason "the process table could not be read" -ErrorRecord $_ }
        if (-not (Test-HordeAnswer $entry)) { $entry = New-HordeUnknown -Reason "the process table did not answer" }
        return (Get-HordeServiceProcessVerdict -Claim $Claim -Entry $entry)
    }
    $started = & $verdictOf $s.started
    $beat = New-HordeAbsent -Note "it keeps no heartbeat"
    $beater = New-HordeAbsent -Note "it keeps no heartbeat"
    if ($null -ne $Definition.alive) {
        try { $beat = Invoke-HordeServiceTool -Tools $Tools -Name "Heartbeat" -With @($Definition.alive.path) } catch { $beat = New-HordeUnknown -Reason "its heartbeat could not be read" -ErrorRecord $_ }
        if (-not (Test-HordeAnswer $beat)) { $beat = New-HordeUnknown -Reason "its heartbeat reader did not answer" }
        if ($beat.state -ceq "known") {
            $claim = [pscustomobject]@{ pid = $beat.value.pid; startedAt = $beat.value.startedAt }
            # The heartbeat's process is usually the state's own: one look serves both.
            if ($started.state -ceq "known" -and [int]$started.value.pid -eq [int]$claim.pid -and (Test-HordeHeartbeatSameStart -One $started.value.startedAt -Other $claim.startedAt)) { $beater = $started }
            else { $beater = & $verdictOf $claim }
        } else { $beater = New-HordeAbsent -Note "no heartbeat names a process" }
    }
    $checkout = New-HordeAbsent -Note "it follows no revision"
    $wanted = New-HordeAbsent -Note "it follows no revision"
    $idle = New-HordeUnknown -Reason "nobody looked: no update is waiting on it"
    if ($null -ne $Definition.follow) {
        if (-not $NoFetch -and ($ForceFetch -or (Test-HordeServiceFetchDue -LastFetchAt $s.lastFetchAt -Now $Now -IntervalSeconds $Policy.fetchIntervalSeconds))) {
            $fetched = $null
            try { $fetched = Invoke-HordeServiceTool -Tools $Tools -Name "Fetch" -With @($Definition, $Policy) } catch { $fetched = [pscustomobject]@{ ok = $false; detail = $_.Exception.Message } }
            # The time is kept whether or not it worked: a remote that cannot be reached is asked
            # again at the interval, not every pass.
            $s.lastFetchAt = $Now.ToUniversalTime()
            $s.fetchProblem = $(if ($null -ne $fetched -and $fetched.ok -eq $true) { "" } else { Protect-HordeServiceText ("the remote could not be asked: " + $(if ($null -ne $fetched) { "" + $fetched.detail } else { "the fetch did not answer" })) })
        }
        $read = $null
        try { $read = Invoke-HordeServiceTool -Tools $Tools -Name "Checkout" -With @($Definition, $s.runningRevision, $Policy, [bool]($null -ne $s.moving)) } catch { $read = $null; $checkout = New-HordeUnknown -Reason "its checkout could not be read" -ErrorRecord $_ }
        if ($null -ne $read -and (Test-HordeAnswer $read.checkout) -and (Test-HordeAnswer $read.wanted)) { $checkout = $read.checkout; $wanted = $read.wanted }
        elseif ($checkout.state -cne "unknown") { $checkout = New-HordeUnknown -Reason "its checkout reader did not answer" }
        if ($checkout.state -cne "known") { $wanted = New-HordeUnknown -Reason $checkout.reason }
        elseif ($wanted.state -ceq "unknown" -and $s.fetchProblem -ne "") { $wanted = New-HordeUnknown -Reason ($wanted.reason + "; " + $s.fetchProblem) }
        $waiting = ($checkout.state -ceq "known" -and $wanted.state -ceq "known" -and (("" + $wanted.value.revision) -cne ("" + $checkout.value.head) -or ($s.runningRevision -ne "" -and $s.runningRevision -cne ("" + $wanted.value.revision))))
        if ($waiting -and $Definition.follow.restart -ceq "idle") {
            try { $idle = Invoke-HordeServiceTool -Tools $Tools -Name "Idle" } catch { $idle = New-HordeUnknown -Reason "whether the person is idle could not be read" -ErrorRecord $_ }
            if (-not (Test-HordeAnswer $idle) -or $idle.state -ceq "absent") { $idle = New-HordeUnknown -Reason "nothing answered whether the person is idle" }
        }
    }
    # Whether this pass can reach the person's desktop is asked only of a service that needs it.
    $desktop = New-HordeUnknown -Reason "nobody looked: it needs no desktop"
    $needs = $Definition.PSObject.Properties["needsDesktop"]
    if ($null -ne $needs -and $needs.Value -eq $true) {
        try { $desktop = Invoke-HordeServiceTool -Tools $Tools -Name "Desktop" } catch { $desktop = New-HordeUnknown -Reason "whether the person's desktop can be reached could not be read" -ErrorRecord $_ }
        if (-not (Test-HordeAnswer $desktop) -or $desktop.state -ceq "absent") { $desktop = New-HordeUnknown -Reason "nothing answered whether the person's desktop can be reached" }
    }
    # Whether a job in the person's session will start it, asked only when this pass cannot.
    $personPass = New-HordeUnknown -Reason "nobody looked: this pass can start it, or it needs no desktop"
    if ($desktop.state -ceq "unknown" -and $null -ne $needs -and $needs.Value -eq $true -and $null -ne $Tools["PersonPass"]) {
        try { $personPass = Invoke-HordeServiceTool -Tools $Tools -Name "PersonPass" } catch { $personPass = New-HordeUnknown -Reason "whether the person's job is scheduled could not be read" -ErrorRecord $_ }
        if (-not (Test-HordeAnswer $personPass)) { $personPass = New-HordeUnknown -Reason "nothing answered whether the person's job is scheduled" }
    }
    # The code its process ended with is asked only when it could matter: the definition lists
    # deliberate exit codes, and the process the state names has just been found gone.
    $exit = New-HordeUnknown -Reason "nobody looked: it has not just ended, or no exit code of its is deliberate"
    if ($null -ne $s.started -and $started.state -ceq "absent" -and $null -ne $Tools["ExitCode"] -and @($Definition.stop.deliberateExitCodes).Count -gt 0) {
        try { $exit = Invoke-HordeServiceTool -Tools $Tools -Name "ExitCode" -With @($Definition, $HordeHome, $s.started) } catch { $exit = New-HordeUnknown -Reason "the code it ended with could not be read" -ErrorRecord $_ }
        if (-not (Test-HordeAnswer $exit) -or $exit.state -ceq "absent" -or ($exit.state -ceq "known" -and $exit.value -isnot [int] -and $exit.value -isnot [long])) { $exit = New-HordeUnknown -Reason "nothing recorded the code it ended with" }
    }
    return [pscustomobject]@{ observed = (New-HordeServiceObserved -Started $started -Heartbeat $beat -Beater $beater -Checkout $checkout -Wanted $wanted -IdleSeconds $idle -ExitCode $exit -Desktop $desktop -PersonPass $personPass); state = $s }
}

function Invoke-HordeServiceStep {
    # Take the decision's step through the tools: { ok; detail; process; revision }. A tool that
    # throws, or answers nothing, is a step that failed, with the reason.
    param([Parameter(Mandatory = $true)]$Definition, [Parameter(Mandatory = $true)]$Decision, [Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)]$Policy, [string]$HordeHome = "")
    $r = $null
    try {
        switch ($Decision.step) {
            "start"   { $r = Invoke-HordeServiceTool -Tools $Tools -Name "Start" -With @($Definition, $HordeHome, $Policy) }
            "stop"    { $r = Invoke-HordeServiceTool -Tools $Tools -Name "Stop" -With @($Definition, $Decision.process, $Policy) }
            "kill"    { $r = Invoke-HordeServiceTool -Tools $Tools -Name "Kill" -With @(, $Decision.process) }
            "verify"  { $r = Invoke-HordeServiceTool -Tools $Tools -Name "Verify" -With @($Definition, $Decision.revision, $Policy) }
            "advance" { $r = Invoke-HordeServiceTool -Tools $Tools -Name "Advance" -With @($Definition, $Decision.revision, $Policy) }
            "retreat" { $r = Invoke-HordeServiceTool -Tools $Tools -Name "Retreat" -With @($Definition, $Decision.revision, $Policy) }
            default   { throw ("'" + $Decision.step + "' is not a step") }
        }
    } catch { return [pscustomobject]@{ ok = $false; detail = (Protect-HordeServiceText ("the " + $Decision.step + " failed: " + $_.Exception.Message)); process = $null; revision = "" } }
    if ($null -eq $r -or $null -eq $r.PSObject.Properties["ok"]) { return [pscustomobject]@{ ok = $false; detail = ("the " + $Decision.step + " did not answer"); process = $null; revision = "" } }
    $process = $null
    if ($null -ne $r.PSObject.Properties["process"]) { $process = $r.process }
    $revision = ""
    if ($null -ne $r.PSObject.Properties["revision"]) { $revision = "" + $r.revision }
    $ok = [bool]($r.ok -eq $true)
    # A start that names no process did not start anything the supervisor can keep.
    if ($Decision.step -ceq "start" -and $ok -and ($null -eq $process -or $process.startedAt -isnot [datetime])) { return [pscustomobject]@{ ok = $false; detail = "the start named no process"; process = $null; revision = "" } }
    return [pscustomobject]@{ ok = $ok; detail = (Protect-HordeServiceText ("" + $r.detail)); process = $process; revision = $revision }
}

function Wait-HordeServiceGone {
    # After a service was asked to stop: look for its process to end, for at most -Seconds, so that a
    # service that stops promptly is moved on in the same pass. Returns whether it is gone.
    param([Parameter(Mandatory = $true)]$Process, [Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)][double]$Seconds)
    $until = (Invoke-HordeServiceTool -Tools $Tools -Name "Now").AddSeconds($Seconds)
    while ($true) {
        $entry = $null
        try { $entry = Invoke-HordeServiceTool -Tools $Tools -Name "ProcessEntry" -With @([int]$Process.pid) } catch { return $false }
        if (-not (Test-HordeAnswer $entry)) { return $false }
        if ((Get-HordeServiceProcessVerdict -Claim $Process -Entry $entry).state -ceq "absent") { return $true }
        if ((Invoke-HordeServiceTool -Tools $Tools -Name "Now") -ge $until) { return $false }
        $null = Invoke-HordeServiceTool -Tools $Tools -Name "Sleep" -With @(500)
    }
}

function Invoke-HordeServiceTendOne {
    # One service, one pass: { name; lines; action; step; code; reason; steps; left }. left is true
    # when the service was left alone because its state file could not be read.
    param([Parameter(Mandatory = $true)]$Definition, [Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)]$Policy, [string]$HordeHome = "", [Parameter(Mandatory = $true)][datetime]$Deadline, [switch]$IgnoreIdle, [switch]$ForceFetch, [double]$SupervisorGapSeconds = 0)
    $name = $Definition.name
    # The gap is handed to the FIRST decision of the pass only: it gives a revision being confirmed
    # the time back, and given again at every step it would give it back again and again.
    $gap = $SupervisorGapSeconds
    $lines = New-Object System.Collections.ArrayList
    $kept = Read-HordeServiceState -Name $name -HordeHome $HordeHome
    # A state that cannot be read is never begun again as new (core/ServicesFiles.ps1 says why).
    if ($kept.state -ceq "unknown") { [void]$lines.Add($name + ": LEFT ALONE - " + $kept.reason); return [pscustomobject]@{ name = $name; lines = @($lines.ToArray()); action = "wait"; step = ""; code = "state-unreadable"; reason = $kept.reason; steps = 0; left = $true } }
    $s = $(if ($kept.state -ceq "known") { $kept.value } else { New-HordeServiceState -Name $name })
    $written = $(if ($kept.state -ceq "known") { ConvertTo-Json -InputObject (ConvertTo-HordeServiceStateRecord -State $s) -Depth 6 -Compress } else { "" })
    $save = {
        # Written only when it differs from what is on disk: a quiet pass writes nothing.
        param($State)
        $text = ConvertTo-Json -InputObject (ConvertTo-HordeServiceStateRecord -State $State) -Depth 6 -Compress
        if ($text -cne $written) { Write-HordeServiceState -State $State -HordeHome $HordeHome; Set-Variable -Name written -Value $text -Scope 1 }
    }
    $d = $null
    $steps = 0
    while ($true) {
        $now = Invoke-HordeServiceTool -Tools $Tools -Name "Now"
        $seen = Get-HordeServiceObservation -Definition $Definition -State $s -Tools $Tools -Policy $Policy -Now $now -ForceFetch:($ForceFetch -and $steps -eq 0) -HordeHome $HordeHome
        $d = Get-HordeServiceDecision -Definition $Definition -State $seen.state -Observed $seen.observed -Now $now -Policy $Policy -IgnoreIdle:$IgnoreIdle -SupervisorGapSeconds $gap
        $gap = 0
        $s = $d.state
        if ($d.notify -ne "") { $s = Add-HordeServiceNotice -State $s -Decision $d -Id (Invoke-HordeServiceTool -Tools $Tools -Name "NewId") -Now $now }
        $worth = Test-HordeServiceWorthSaying -Decision $d -LastSaid $s.lastSaid
        $s.lastSaid = Get-HordeServiceSaidKey -Decision $d
        if ($d.step -eq "") {
            if ($d.code -ceq "updated") { $s.lastAction = [pscustomobject]@{ at = $now.ToUniversalTime(); action = "restart-for-update"; step = "confirm"; outcome = "done"; reason = $d.reason } }
            & $save $s
            if ($worth) { $null = Write-HordeServiceJournal -HordeHome $HordeHome -Entries @(New-HordeServiceJournalEntry -At $now -Service $name -Action $d.action -Code $d.code -Reason $d.reason) }
            [void]$lines.Add($name + ": " + $d.action + " - " + $d.reason)
            break
        }
        # A step. The state says where the service is BEFORE the step is taken (header).
        & $save $s
        $d.state = $s
        $outcome = Invoke-HordeServiceStep -Definition $Definition -Decision $d -Tools $Tools -Policy $Policy -HordeHome $HordeHome
        $after = Invoke-HordeServiceTool -Tools $Tools -Name "Now"
        $s = Complete-HordeServiceStep -Definition $Definition -Decision $d -Outcome $outcome -Now $after -Policy $Policy
        & $save $s
        $steps++
        $said = $(if ($outcome.detail -ne "") { $outcome.detail } else { $d.reason })
        $null = Write-HordeServiceJournal -HordeHome $HordeHome -Entries @(New-HordeServiceJournalEntry -At $after -Service $name -Action $d.action -Step $d.step -Code $d.code -Outcome $(if ($outcome.ok) { "done" } else { "failed" }) -Reason ($d.reason + $(if ($outcome.detail -ne "") { " -> " + $outcome.detail } else { "" })))
        [void]$lines.Add($name + ": " + $d.action + " (" + $d.step + ") " + $(if ($outcome.ok) { "done" } else { "FAILED" }) + " - " + $said)
        # A failed step is left to the next pass: tried again at once it would fail again at once.
        if (-not $outcome.ok -or $steps -ge $script:HordeServiceStepsMost) { break }
        # A service asked to stop is watched for as long as the pass has left, so one that stops
        # promptly is moved on in this pass; then the budget decides whether another step is taken.
        $left = ($Deadline - (Invoke-HordeServiceTool -Tools $Tools -Name "Now")).TotalSeconds
        if ($d.step -ceq "stop" -and $null -ne $d.process -and $left -gt 0) { $null = Wait-HordeServiceGone -Process $d.process -Tools $Tools -Seconds ([System.Math]::Min([double]$Definition.stop.waitSeconds, $left)) }
        if ((Invoke-HordeServiceTool -Tools $Tools -Name "Now") -ge $Deadline) { break }
    }
    return [pscustomobject]@{ name = $name; lines = @($lines.ToArray()); action = $d.action; step = $d.step; code = $d.code; reason = $d.reason; steps = $steps; left = $false }
}

function Send-HordeServicePending {
    # Hand everything still untold to the teller, in one call, and forget what it took: the lines to
    # say. The teller is Tools.TellAll: param($Notices, $HordeHome, $Policy) -> { told; problem },
    # told being the ids it handed over. With no teller, or with telling switched off, the notices
    # stay where they are and one line says so - a trouble nobody is told of must at least be said.
    param([Parameter(Mandatory = $true)]$Definitions, [Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)]$Policy, [string]$HordeHome = "")
    $waiting = New-Object System.Collections.ArrayList
    $states = @{}
    foreach ($def in @($Definitions)) {
        $kept = Read-HordeServiceState -Name $def.name -HordeHome $HordeHome
        if ($kept.state -cne "known" -or @($kept.value.notices).Count -eq 0) { continue }
        $states[$def.name] = $kept.value
        foreach ($n in @($kept.value.notices)) { [void]$waiting.Add([pscustomobject]@{ id = $n.id; kind = $n.kind; text = $n.text; at = $n.at; service = $def.name; what = (Get-HordeServiceNoticeWhat -Notice $n) }) }
    }
    if ($waiting.Count -eq 0) { return @() }
    if ($Policy.tellWarchief -ne $true) { return @("" + $waiting.Count + " notice(s) wait untold: telling is switched off (the setting tellWarchief)") }
    if ($null -eq $Tools["TellAll"]) { return @("" + $waiting.Count + " notice(s) wait untold: nothing here can tell anyone") }
    $answer = $null
    try { $answer = Invoke-HordeServiceTool -Tools $Tools -Name "TellAll" -With @(@($waiting.ToArray()), $HordeHome, $Policy) }
    catch { return @("" + $waiting.Count + " notice(s) wait untold: " + (Protect-HordeServiceText $_.Exception.Message) + "; they are tried again next pass") }
    $told = @()
    if ($null -ne $answer -and $null -ne $answer.PSObject.Properties["told"]) { $told = @($answer.told | ForEach-Object { "" + $_ }) }
    $lines = New-Object System.Collections.ArrayList
    foreach ($name in @($states.Keys | Sort-Object)) {
        $s = Copy-HordeServiceState -State $states[$name]
        $kept = @($s.notices | Where-Object { $told -cnotcontains $_.id })
        foreach ($n in @($s.notices | Where-Object { $told -ccontains $_.id })) { [void]$lines.Add("told (" + $n.kind + "): " + $n.text) }
        if ($kept.Count -ne @($s.notices).Count) { $s.notices = $kept; Write-HordeServiceState -State $s -HordeHome $HordeHome }
    }
    $untold = $waiting.Count - @($told).Count
    if ($untold -gt 0) {
        $why = ""
        if ($null -ne $answer -and $null -ne $answer.PSObject.Properties["problem"]) { $why = "" + $answer.problem }
        [void]$lines.Add("" + $untold + " notice(s) wait untold" + $(if ($why -ne "") { ": " + (Protect-HordeServiceText $why) } else { "" }) + "; they are tried again next pass")
    }
    return @($lines.ToArray())
}

function Invoke-HordeServiceSupervisor {
    # The pass, and `rollout`'s passes: { ran; problem; lines; services }. ran is false when nothing
    # was looked at - another pass holds the lock, or a file is refused - and problem says why when
    # that is an error. services is each service's last decision this run.
    #   -Only           these services only (a name that is not defined is a problem)
    #   -IgnoreIdle     `rollout -Now`: the person asked; their being here is not a reason to wait
    #   -ForceFetch     ask the remote now, whatever the interval
    #   -LockWaitSeconds  how long to wait for another pass to finish
    #   -SettleSeconds  `rollout`: go on passing until no chosen service is part way through an
    #                   update, for at most this long; 0 is the scheduled pass, which looks once
    #   -BudgetSeconds  how long one pass may go on taking steps; 0 is the setting
    param([string]$HordeHome = "", $Tools = $null, [string[]]$Only = @(), [switch]$IgnoreIdle, [switch]$ForceFetch, [int]$LockWaitSeconds = 0, [int]$SettleSeconds = 0, [int]$BudgetSeconds = 0)
    if ($HordeHome -eq "") { $HordeHome = Get-HordeHome }
    if ($null -eq $Tools) { $Tools = New-HordeServiceTools }
    $none = { param([string]$Problem, [string[]]$Lines = @()) return [pscustomobject]@{ ran = $false; problem = $Problem; lines = [string[]]@($Lines); services = @() } }
    $settings = Get-HordeServiceSettings -HordeHome $HordeHome
    if ($settings.state -ceq "refused") { return (& $none ($settings.findings -join " ")) }
    $policy = $settings.values
    $defined = Get-HordeServiceDefinitions -HordeHome $HordeHome
    if ($defined.state -ceq "refused") { return (& $none ($defined.findings -join " ")) }
    $chosen = @($defined.services)
    if (@($Only).Count -gt 0) {
        foreach ($n in @($Only)) { if (@($chosen | Where-Object { $_.name -ceq $n }).Count -eq 0) { return (& $none ("no service named '" + $n + "' is defined in " + $defined.path + $(if ($chosen.Count -gt 0) { " (defined: " + (@($chosen | ForEach-Object { $_.name }) -join ", ") + ")" } else { "" }))) } }
        $chosen = @($chosen | Where-Object { @($Only) -ccontains $_.name })
    }
    $lock = Enter-HordeServiceTendLock -HordeHome $HordeHome -WaitSeconds $LockWaitSeconds
    if ($null -eq $lock) { return (& $none $(if ($LockWaitSeconds -gt 0) { "another pass of the supervisor is still running on this home after " + $LockWaitSeconds + " s" } else { "" }) @("another pass is running on this home; this one does nothing")) }
    $lines = New-Object System.Collections.ArrayList
    $last = @{}
    try {
        $self = Get-HordeHeartbeatSelf
        $beatPath = Get-HordeServiceTendHeartbeatPath -HordeHome $HordeHome
        $before = Read-HordeHeartbeat -Path $beatPath
        $pass = [long]1
        if ($before.state -ceq "known") { $pass = [long]$before.value.pass + 1 }
        # WAS THE SUPERVISOR ITSELF NOT RUNNING? Its own last heartbeat says: stale by its own tick
        # means no pass came round - the machine slept, its clock moved, or the job was off - and for
        # exactly that long nobody was looking (core/Services.ps1 says what a decision does with it).
        # Read on the pass's own clock, like everything else a pass decides by.
        $gapSeconds = [double]0
        $own = Get-HordeHeartbeatVerdict -Heartbeat $before -Now (Invoke-HordeServiceTool -Tools $Tools -Name "Now") -DefaultTickSeconds (Get-HordeServiceTendTickSeconds)
        if ($own.state -ceq "known" -and -not $own.value.fresh) { $gapSeconds = [double]$own.value.ageSeconds; [void]$lines.Add("the supervisor's own last pass was " + $own.value.ageSeconds + " s ago: it was not running, so for this pass an old heartbeat is not read as a hung service") }
        # At the start as well as the end: a pass that takes its whole minute is not stale meanwhile.
        $null = Write-HordeHeartbeatQuietly -Path $beatPath -At (Invoke-HordeServiceTool -Tools $Tools -Name "Now") -ProcessId $self.pid -ProcessStartedAt $self.startedAt -TickSeconds (Get-HordeServiceTendTickSeconds) -Pass $pass
        if ($chosen.Count -eq 0) { [void]$lines.Add("no service is defined in " + $defined.path + "; there is nothing to tend") }
        $budget = $(if ($BudgetSeconds -gt 0) { $BudgetSeconds } else { [int]$policy.passBudgetSeconds })
        $settleBy = (Invoke-HordeServiceTool -Tools $Tools -Name "Now").AddSeconds($SettleSeconds)
        $first = $true
        while ($true) {
            $deadline = (Invoke-HordeServiceTool -Tools $Tools -Name "Now").AddSeconds($budget)
            foreach ($def in $chosen) {
                $one = $null
                try { $one = Invoke-HordeServiceTendOne -Definition $def -Tools $Tools -Policy $policy -HordeHome $HordeHome -Deadline $deadline -IgnoreIdle:$IgnoreIdle -ForceFetch:($ForceFetch -and $first) -SupervisorGapSeconds $(if ($first) { $gapSeconds } else { 0 }) }
                catch {
                    # One service's failure is its own: the others are still tended.
                    $why = Protect-HordeServiceText $_.Exception.Message
                    $one = [pscustomobject]@{ name = $def.name; lines = @($def.name + ": THE PASS FAILED ON IT - " + $why); action = "wait"; step = ""; code = "pass-failed"; reason = $why; steps = 0; left = $true }
                }
                foreach ($l in @($one.lines)) { [void]$lines.Add($l) }
                $last[$def.name] = $one
            }
            $first = $false
            $moving = @($last.Values | Where-Object { $script:HordeServiceMovingCodes -ccontains $_.code })
            if ($SettleSeconds -le 0 -or $moving.Count -eq 0 -or (Invoke-HordeServiceTool -Tools $Tools -Name "Now") -ge $settleBy) { break }
            $null = Invoke-HordeServiceTool -Tools $Tools -Name "Sleep" -With @(2000)
        }
        foreach ($l in @(Send-HordeServicePending -Definitions $chosen -Tools $Tools -Policy $policy -HordeHome $HordeHome)) { [void]$lines.Add($l) }
        # THE HOSTED PHONE PAGE, once a whole pass, after the services (cli/RelayPublish.ps1): a pass for
        # chosen services only - a person's start or rollout of one - leaves it to the next whole pass.
        # Its failure is its own, as one service's is.
        if (@($Only).Count -eq 0 -and $null -ne $Tools["PagePublish"]) {
            try { foreach ($l in @(& $Tools["PagePublish"] $HordeHome $policy $Tools["TellAll"])) { [void]$lines.Add("" + $l) } }
            catch { [void]$lines.Add("phone page: THE PASS FAILED ON IT - " + (Protect-HordeServiceText $_.Exception.Message)) }
        }
        $null = Write-HordeHeartbeatQuietly -Path $beatPath -At (Invoke-HordeServiceTool -Tools $Tools -Name "Now") -ProcessId $self.pid -ProcessStartedAt $self.startedAt -TickSeconds (Get-HordeServiceTendTickSeconds) -Pass $pass
    } finally { $lock.Dispose() }
    return [pscustomobject]@{ ran = $true; problem = ""; lines = [string[]]@($lines.ToArray()); services = @($chosen | ForEach-Object { $last[$_.name] } | Where-Object { $null -ne $_ }) }
}

function Get-HordeServiceStatusReport {
    # What `horde services status` shows, as data: { home; supervisor; definitions; settings;
    # services }. READS ONLY: no remote is asked, nothing is started, stopped or written. supervisor
    # is the pass's own heartbeat judged at -Now: state running, stale, never or unknown.
    param([string]$HordeHome = "", $Tools = $null, $Now = $null)
    if ($HordeHome -eq "") { $HordeHome = Get-HordeHome }
    if ($null -eq $Tools) { $Tools = New-HordeServiceTools }
    if ($Now -isnot [datetime]) { $Now = Invoke-HordeServiceTool -Tools $Tools -Name "Now" }
    $beat = Read-HordeHeartbeat -Path (Get-HordeServiceTendHeartbeatPath -HordeHome $HordeHome)
    $verdict = Get-HordeHeartbeatVerdict -Heartbeat $beat -Now $Now -DefaultTickSeconds (Get-HordeServiceTendTickSeconds)
    $supervisor = [ordered]@{ state = "unknown"; ageSeconds = $null; staleAfterSeconds = $null; said = "" }
    if ($verdict.state -ceq "absent") { $supervisor.state = "never"; $supervisor.said = "the supervisor has never run in this home: nothing here is being kept alive or updated" }
    elseif ($verdict.state -ceq "unknown") { $supervisor.said = "whether the supervisor is running cannot be told: " + $verdict.reason }
    else {
        $supervisor.ageSeconds = $verdict.value.ageSeconds; $supervisor.staleAfterSeconds = $verdict.value.staleAfterSeconds
        if ($verdict.value.fresh) { $supervisor.state = "running"; $supervisor.said = "the supervisor's last pass was " + $verdict.value.ageSeconds + " s ago" }
        else { $supervisor.state = "stale"; $supervisor.said = "THE SUPERVISOR IS NOT RUNNING: its last pass was " + $verdict.value.ageSeconds + " s ago (it should come round every " + $verdict.value.tickSeconds + " s); nothing here is being kept alive or updated" }
    }
    $settings = Get-HordeServiceSettings -HordeHome $HordeHome
    $defined = Get-HordeServiceDefinitions -HordeHome $HordeHome
    $rows = New-Object System.Collections.ArrayList
    if ($settings.state -cne "refused") {
        foreach ($def in @($defined.services)) {
            $kept = Read-HordeServiceState -Name $def.name -HordeHome $HordeHome
            if ($kept.state -ceq "unknown") { [void]$rows.Add([pscustomobject]@{ name = $def.name; enabled = [bool]$def.enabled; alive = "unknown"; why = $kept.reason; pid = $null; heartbeatAgeSeconds = $null; phase = $null; runningRevision = $null; wantedRevision = $null; current = $null; next = "wait"; nextReason = "it is left alone until its state file is mended or removed"; lastAction = $null; failures = $null; escalated = [string[]]@(); untold = 0; pinnedRevision = $null; fetchProblem = "" }); continue }
            $s = $(if ($kept.state -ceq "known") { $kept.value } else { New-HordeServiceState -Name $def.name })
            $seen = Get-HordeServiceObservation -Definition $def -State $s -Tools $Tools -Policy $settings.values -Now $Now -NoFetch -HordeHome $HordeHome
            [void]$rows.Add((Get-HordeServiceStatus -Definition $def -State $s -Observed $seen.observed -Now $Now -Policy $settings.values))
        }
    }
    return [pscustomobject]@{
        home = $HordeHome; supervisor = [pscustomobject]$supervisor
        definitions = [pscustomobject]@{ state = $defined.state; path = $defined.path; findings = [string[]]@($defined.findings) }
        settings = [pscustomobject]@{ state = $settings.state; path = $settings.path; findings = [string[]]@($settings.findings) }
        services = @($rows.ToArray())
    }
}

function ConvertTo-HordeServiceStatusRecord {
    # The report as -Json prints it: the same members, every time as text that reads back as the
    # same instant (ConvertTo-Json would write a [datetime] in a form of its own).
    param([Parameter(Mandatory = $true)]$Report)
    $services = @($Report.services | ForEach-Object {
        $row = [ordered]@{}
        foreach ($p in $_.PSObject.Properties) { $row[$p.Name] = $p.Value }
        if ($null -ne $_.lastAction) { $row["lastAction"] = [ordered]@{ at = (ConvertTo-HordeHeartbeatTimeText -At $_.lastAction.at); action = $_.lastAction.action; step = $_.lastAction.step; outcome = $_.lastAction.outcome; reason = (Protect-HordeServiceText ("" + $_.lastAction.reason)) } }
        $row["escalationOutstanding"] = [bool](@($_.escalated).Count -gt 0)
        $row
    })
    return [ordered]@{ home = $Report.home; supervisor = $Report.supervisor; definitions = $Report.definitions; settings = $Report.settings; services = $services }
}

function Format-HordeServiceStatus {
    # The report as a person reads it. The supervisor's own line is first, because when IT is not
    # running every line under it describes a past nobody is keeping true.
    param([Parameter(Mandatory = $true)]$Report)
    $short = { param($Revision) if ($null -eq $Revision -or "" + $Revision -eq "") { return "unknown" } return (ConvertTo-HordeServiceShortRevision ("" + $Revision)) }
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add("supervisor: " + $Report.supervisor.said)
    if ($Report.settings.state -ceq "refused") { foreach ($f in @($Report.settings.findings)) { [void]$lines.Add("settings: " + $f) } }
    if ($Report.definitions.state -ceq "refused") { foreach ($f in @($Report.definitions.findings)) { [void]$lines.Add("definitions: " + $f) }; [void]$lines.Add("definitions: NO SERVICE IS SUPERVISED until that file is mended") }
    elseif ($Report.definitions.state -ceq "none") { [void]$lines.Add("definitions: no service is defined (there is no " + $Report.definitions.path + ")") }
    else { [void]$lines.Add("definitions: " + @($Report.services).Count + " service(s) in " + $Report.definitions.path) }
    foreach ($r in @($Report.services)) {
        $alive = switch ("" + $r.alive) { "yes" { "alive" } "no" { "NOT RUNNING" } "starting" { "starting" } "hung" { "HUNG" } "unwell" { "UNWELL" } default { "UNKNOWN" } }
        [void]$lines.Add("")
        [void]$lines.Add($r.name + ": " + $alive + $(if (-not $r.enabled) { " (not supervised: enabled is false)" } else { "" }) + " - " + $r.why)
        if ($null -ne $r.PSObject.Properties["held"] -and $r.held -eq $true) { [void]$lines.Add("    HELD" + $(if ("" + $r.heldWhy -ne "") { " - " + $r.heldWhy } else { "" }) + ": the supervisor leaves it as it is until horde services start " + $r.name) }
        if ($null -ne $r.heartbeatAgeSeconds) { [void]$lines.Add("    heartbeat: " + $r.heartbeatAgeSeconds + " s ago") }
        if ($null -ne $r.wantedRevision -or $null -ne $r.runningRevision) {
            $state = $(if ($null -eq $r.current) { "cannot be compared" } elseif ($r.current) { "current" } else { "NOT CURRENT" })
            [void]$lines.Add("    revision: running " + (& $short $r.runningRevision) + ", wanted " + (& $short $r.wantedRevision) + " (" + $state + ")" + $(if ($null -ne $r.pinnedRevision) { "; " + (& $short $r.pinnedRevision) + " is pinned as failed" } else { "" }))
        }
        if ("" + $r.fetchProblem -ne "") { [void]$lines.Add("    remote: " + $r.fetchProblem) }
        [void]$lines.Add("    a pass would now: " + $r.next + " - " + $r.nextReason)
        if ($null -ne $r.lastAction) { [void]$lines.Add("    last action: " + $r.lastAction.at.ToString("yyyy-MM-dd HH:mm:ss 'UTC'", [System.Globalization.CultureInfo]::InvariantCulture) + " " + $r.lastAction.action + $(if ("" + $r.lastAction.step -ne "") { " (" + $r.lastAction.step + ")" } else { "" }) + $(if ("" + $r.lastAction.outcome -ne "") { " " + $r.lastAction.outcome } else { "" }) + " - " + (Protect-HordeServiceText ("" + $r.lastAction.reason))) }
        else { [void]$lines.Add("    last action: none yet") }
        if ($null -ne $r.failures) { [void]$lines.Add("    failures in a row: " + $r.failures + "; escalation outstanding: " + $(if (@($r.escalated).Count -gt 0) { "YES (" + (@($r.escalated) -join ", ") + ")" } else { "no" }) + $(if ($r.untold -gt 0) { "; " + $r.untold + " notice(s) not yet told" } else { "" })) }
    }
    return @($lines.ToArray())
}

# Where the start-up job finds the job in the person's session: <folder>\<name>, carried in its
# environment, so a pass of it can ask whether that job is scheduled (Test-HordeServicePersonJob).
$script:HordeServicePersonJobVariable = "HORDE_SERVICES_PERSON_JOB"

function Test-HordeServicePersonJob {
    # Is the supervisor's job in the person's own session scheduled, marked as Horde's and enabled?
    # known $true; unknown, with why, otherwise - including a pass that was not told its name, which
    # then tells as it always did.
    $named = "" + [System.Environment]::GetEnvironmentVariable($script:HordeServicePersonJobVariable)
    if ($named -cnotmatch '\A(Horde|HordeTest)\\(.+)\z') { return (New-HordeUnknown -Reason "this pass was not told which job of the supervisor's runs in the person's session") }
    $folder = $Matches[1]; $name = $Matches[2]
    try {
        foreach ($f in @(Get-HordeSchedulerFiles)) { . $f }
        $sched = Get-HordeScheduler
        if ($sched.state -cne "known") { return (New-HordeUnknown -Reason $sched.reason) }
        $st = & $sched.value.status $name $folder
        if ($st.state -ceq "known" -and $st.value.marked -eq $true -and $st.value.enabled -eq $true) { return (New-HordeKnown -Value $true) }
        return (New-HordeUnknown -Reason ("the job " + $name + " in the person's session is not scheduled and enabled"))
    } catch { return (New-HordeUnknown -Reason "whether the job in the person's session is scheduled could not be read" -ErrorRecord $_) }
}

function Get-HordeServiceTendJobNames {
    # The supervisor's TWO jobs (New-HordeServiceTendJob says why two), named from one: -TaskName is
    # the job in the person's own session - the name the supervisor's one job always had, so an
    # install updates that job in place - and the job that runs whether or not anyone is signed in
    # is the same name with " at start-up" after it. Both are checked as job names.
    param([Parameter(Mandatory = $true)][string]$TaskName, [Parameter(Mandatory = $true)][string]$Folder)
    $names = [pscustomobject]@{ person = $TaskName; startup = ($TaskName + " at start-up") }
    foreach ($n in @($names.person, $names.startup)) { Assert-HordeJobName -Name $n -Folder $Folder }
    return $names
}

function New-HordeServiceTendJob {
    # One of the supervisor's two jobs: this checkout's horde, `services tend`, every minute.
    #   -Kind startup  AT START-UP AND EVERY MINUTE, WHETHER OR NOT ANYONE IS SIGNED IN (core/Schedule.ps1,
    #                  -AtStartup). Until 2026-10-14 the supervisor had only the job in the person's
    #                  session, and so ran only while someone was signed in: after a restart nobody
    #                  signed in for 2 h 38 min, the relay it keeps was down all that time, and twenty
    #                  answers from a phone waited on it. What it starts runs in its own logon - the
    #                  person's account, their profile, no stored password - and it cannot see their
    #                  input or show them a window (core/Services.ps1, THE PASS THAT CANNOT SEE THE
    #                  PERSON).
    #   -Kind person   AT SIGN-IN AND EVERY MINUTE, IN THE PERSON'S OWN SESSION (-WithPerson, -AtLogon),
    #                  as the supervisor's one job always ran. KEPT BESIDE THE OTHER, NOT REPLACED BY IT
    #                  (review of PR 249, MUST 2): a service that needs the desktop - the decisions
    #                  window - is started only by a pass that can show it, an update that waits for
    #                  the person to be idle is taken only by a pass that can see them, and a service
    #                  started before anyone signed in that could not use the account's keys is
    #                  started again where it can.
    # TWO PASSES NEVER OVERLAP: each job's scheduler starts no second run of it while one is going, and
    # every pass holds the tend lock - an open file under the home (core/ServicesFiles.ps1) - which
    # keeps a pass of either job, and a person's own tend, apart from every other. STOPPED AT FIVE
    # MINUTES, NOT ONE: a pass decides to take a step while it has budget left, and the step it then
    # takes - the move of a checkout, a self-check - may itself run a minute; ended at one minute, a
    # pass was being cut down in the middle of exactly the steps that must not be cut (safety review
    # of the first build, item 6). The home travels with it as data, as the metrics job's does.
    # -PersonJob, for the start-up job: the name of the job in the person's session beside it.
    param([Parameter(Mandatory = $true)][string]$HordeScript, [string]$Name = $script:HordeServiceTendJobName, [string]$Folder = "Horde", [ValidateSet("startup", "person")][string]$Kind = "startup", [string]$PersonJob = "", [switch]$Disabled)
    $home2 = Get-HordeHome
    $where = $(if ($Kind -ceq "startup") { @{ AtStartup = $true } } else { @{ WithPerson = $true; AtLogon = $true } })
    $environment = @{ HORDE_HOME = $home2 }
    if ($Kind -ceq "startup" -and $PersonJob -ne "") { $environment[$script:HordeServicePersonJobVariable] = $Folder + "\" + $PersonJob }
    return (New-HordeScheduledJob -Name $Name -Folder $Folder -Script $HordeScript -Arguments @("services", "tend") -Environment $environment -HordeHome $home2 -EveryMinutes 1 -TimeLimitMinutes 5 -MayOutlastInterval @where -Disabled:$Disabled -Description "Horde: keep the defined services running and current - one pass over every service each minute. Managed by horde services schedule; remove it with horde services unschedule.")
}

function Invoke-HordeServiceSchedule {
    # `horde services schedule [status]` and `horde services unschedule`: the supervisor's TWO jobs
    # (New-HordeServiceTendJob), through whichever scheduler this machine has (core/Schedule.ps1).
    # Returns the lines to show; throws when the action cannot be done. Install over, and removal of,
    # a job that does not carry Horde's marker are refused by the scheduler, as for every Horde job.
    # INSTALL IS THE START-UP JOB FIRST: it is the one that may be refused for want of rights, and
    # refused, nothing else is touched - the job in the person's session stays exactly as it was.
    param([Parameter(Mandatory = $true)][ValidateSet("install", "remove", "status")][string]$Action, [string]$TaskName = $script:HordeServiceTendJobName, [string]$Folder = "Horde", [switch]$Disabled, [Parameter(Mandatory = $true)][string]$HordeScript)
    $names = Get-HordeServiceTendJobNames -TaskName $TaskName -Folder $Folder
    $sched = Get-HordeScheduler
    if ($sched.state -ne "known") { throw ("cannot schedule the supervisor: " + $sched.reason) }
    $s = $sched.value
    $where = { param($n) return ("'" + $n + "' in " + $s.name + " folder " + $Folder) }
    $both = @([pscustomobject]@{ kind = "startup"; name = $names.startup; says = "at start-up and every minute, whether or not anyone is signed in, with no password stored" },
              [pscustomobject]@{ kind = "person"; name = $names.person; says = "at sign-in and every minute, in the person's own session, for the services that need their desktop" })
    switch ($Action) {
        "install" {
            $lines = New-Object System.Collections.ArrayList
            foreach ($b in @($both)) {
                $job = New-HordeServiceTendJob -HordeScript $HordeScript -Name $b.name -Folder $Folder -Kind $b.kind -PersonJob $names.person -Disabled:$Disabled
                # Installed over a job of the same name REPLACES it: one job of each kind, never two.
                & $s.install $job
                $st = & $s.status $b.name $Folder
                if ($st.state -ne "known" -or -not $st.value.marked) { throw ("the " + $s.name + " did not keep the job " + (& $where $b.name) + ": " + $st.reason) }
                $as = $(if ($null -ne $st.value.PSObject.Properties["runsAs"] -and "" + $st.value.runsAs -ne "") { ", as " + $st.value.runsAs } else { "" })
                [void]$lines.Add("installed " + (& $where $b.name) + ": " + $b.says + $as + ", for the Horde home " + $job.hordeHome + $(if ($Disabled) { "; DISABLED, so it never runs" } else { "" }))
            }
            [void]$lines.Add("both run: " + $HordeScript + " services tend; one pass at a time, whichever starts it")
            [void]$lines.Add("horde services status says whether their passes are coming round")
            return @($lines.ToArray())
        }
        "remove" {
            # BOTH ARE TRIED, whatever the first does (review of PR 249, round 2), and both results said.
            $lines = New-Object System.Collections.ArrayList
            $failed = 0
            foreach ($b in $both) {
                try {
                    $gone = & $s.remove $b.name $Folder
                    [void]$lines.Add($(if ($gone) { "removed " + (& $where $b.name) } else { "no job " + (& $where $b.name) + "; nothing to remove" }))
                } catch { $failed++; [void]$lines.Add("COULD NOT REMOVE " + (& $where $b.name) + ": " + $_.Exception.Message) }
            }
            if ($failed -gt 0) { throw ($lines -join "; ") }
            [void]$lines.Add("no service is supervised until it is scheduled again. Nothing that is running was stopped.")
            return @($lines.ToArray())
        }
        "status" {
            $lines = New-Object System.Collections.ArrayList
            $fmt = { param($t) if ($null -eq $t) { "never" } else { $t.ToString("yyyy-MM-dd HH:mm 'UTC'", [System.Globalization.CultureInfo]::InvariantCulture) } }
            $none = 0
            foreach ($b in $both) {
                $st = & $s.status $b.name $Folder
                if ($st.state -ne "known") { $none++; [void]$lines.Add((& $where $b.name) + " is not installed"); continue }
                $v = $st.value
                $when = $(if ($null -ne $v.PSObject.Properties["atStartup"] -and $v.atStartup -eq $true) { "at start-up and " } elseif ($null -ne $v.PSObject.Properties["atLogon"] -and $v.atLogon -eq $true) { "at sign-in and " } else { "" })
                $as = $(if ($null -ne $v.PSObject.Properties["runsAs"] -and "" + $v.runsAs -ne "") { ", as " + $v.runsAs } else { "" })
                [void]$lines.Add((& $where $b.name) + ": " + $(if ($v.enabled) { "enabled" } else { "DISABLED" }) + ", " + $v.state + ", " + $when + "every " + $v.everyMinutes + " minute(s), logon " + $v.logonType + $as + $(if ($v.marked) { ", Horde's" } else { ", NOT made by Horde" }))
                [void]$lines.Add("    serves the Horde home " + $v.home + "; last run " + (& $fmt $v.lastRunAt) + ", next run " + (& $fmt $v.nextRunAt))
            }
            if ($none -eq 2) { [void]$lines.Add("neither job is installed: no service is being supervised") }
            elseif ($none -eq 1) { [void]$lines.Add("ONE OF THE TWO JOBS IS MISSING: horde services schedule installs both") }
            [void]$lines.Add("whether their passes do their work is horde services status's to say")
            return @($lines.ToArray())
        }
    }
}

function Set-HordeServiceHeld {
    # `horde services stop <name>` and `horde services start <name>`: { ok; problem; lines }.
    #   -Held        STOP IT AND HOLD IT. The service is asked to stop the way its definition says,
    #                waited for as long as its definition gives it, then ended; and its state is marked
    #                held, which every pass respects (core/Services.ps1): it is not started, stopped or
    #                updated until it is let go. Nobody edits a definitions file to stop a service.
    #   not -Held    LET IT GO. The mark is taken off, with what a held service may have left behind -
    #                a start whose outcome was never recorded, its count of failed starts, the telling
    #                that it ended itself - and the caller tends it at once.
    # Done under the pass's own lock, so a pass and a person never act on one service together. A
    # service whose state file cannot be read is refused: its state is where the mark is kept.
    param([Parameter(Mandatory = $true)][string]$Name, [switch]$Held, [string]$HordeHome = "", $Tools = $null)
    if ($HordeHome -eq "") { $HordeHome = Get-HordeHome }
    if ($null -eq $Tools) { $Tools = New-HordeServiceTools }
    $answer = { param([string]$Problem, [string[]]$Lines = @()) return [pscustomobject]@{ ok = [bool]($Problem -eq ""); problem = $Problem; lines = [string[]]@($Lines) } }
    $settings = Get-HordeServiceSettings -HordeHome $HordeHome
    if ($settings.state -ceq "refused") { return (& $answer ($settings.findings -join " ")) }
    $defined = Get-HordeServiceDefinitions -HordeHome $HordeHome
    if ($defined.state -ceq "refused") { return (& $answer ($defined.findings -join " ")) }
    $def = @($defined.services | Where-Object { $_.name -ceq $Name }) | Select-Object -First 1
    if ($null -eq $def) { return (& $answer ("no service named '" + $Name + "' is defined in " + $defined.path + $(if (@($defined.services).Count -gt 0) { " (defined: " + (@($defined.services | ForEach-Object { $_.name }) -join ", ") + ")" } else { "" }))) }
    $lock = Enter-HordeServiceTendLock -HordeHome $HordeHome -WaitSeconds 90
    if ($null -eq $lock) { return (& $answer "a pass of the supervisor is still running on this home after 90 s; nothing was done") }
    $lines = New-Object System.Collections.ArrayList
    try {
        $kept = Read-HordeServiceState -Name $Name -HordeHome $HordeHome
        if ($kept.state -ceq "unknown") { return (& $answer ("nothing was done: " + $kept.reason)) }
        $s = $(if ($kept.state -ceq "known") { Copy-HordeServiceState -State $kept.value } else { New-HordeServiceState -Name $Name })
        $now = Invoke-HordeServiceTool -Tools $Tools -Name "Now"
        if (-not $Held) {
            $was = [bool]($s.held -eq $true)
            $s.held = $false; $s.heldWhy = ""; $s.launchingAt = $null; $s.failures = 0; $s.nextStartAt = $null; $s.proving = $false
            $s.told = [string[]]@(@($s.told) | Where-Object { @("ended-itself", "start-unrecorded") -cnotcontains $_ })
            $s.lastAction = [pscustomobject]@{ at = $now.ToUniversalTime(); action = "start"; step = "let-go"; outcome = "done"; reason = "a person let it go with horde services start" }
            Write-HordeServiceState -State $s -HordeHome $HordeHome
            $null = Write-HordeServiceJournal -HordeHome $HordeHome -Entries @(New-HordeServiceJournalEntry -At $now -Service $Name -Action "start" -Step "let-go" -Code "let-go" -Outcome "done" -Reason "a person let it go with horde services start")
            [void]$lines.Add($Name + ": " + $(if ($was) { "no longer held" } else { "was not held" }) + "; the supervisor tends it again")
            return (& $answer "" @($lines.ToArray()))
        }
        # THE MARK FIRST, on disk, before anything is stopped: a pass that came round between the
        # stop and the mark would find the service gone and start it again.
        $s.held = $true; $s.heldWhy = "a person stopped it with horde services stop"; Write-HordeServiceState -State $s -HordeHome $HordeHome
        $seen = Get-HordeServiceObservation -Definition $def -State $s -Tools $Tools -Policy $settings.values -Now $now -NoFetch -HordeHome $HordeHome
        $live = Get-HordeServiceLiveness -Definition $def -State $s -Observed $seen.observed -Now $now
        $said = "it was not running"
        if ($live.alive -ceq "unknown") { $said = "whether it is running could not be told (" + $live.why + "), so nothing was stopped" }
        elseif ($null -ne $live.process) {
            $asked = $null
            try { $asked = Invoke-HordeServiceTool -Tools $Tools -Name "Stop" -With @($def, $live.process, $settings.values) } catch { $asked = [pscustomobject]@{ ok = $false; detail = $_.Exception.Message } }
            $gone = Wait-HordeServiceGone -Process $live.process -Tools $Tools -Seconds ([double]$def.stop.waitSeconds)
            if ($gone) { $said = "it was asked to stop, and stopped" }
            else {
                # Asked, waited for, still there: ended, as a pass would end it - by pid AND start.
                $ended = $null
                try { $ended = Invoke-HordeServiceTool -Tools $Tools -Name "Kill" -With @(, $live.process) } catch { $ended = [pscustomobject]@{ ok = $false; detail = $_.Exception.Message } }
                $said = $(if ($null -ne $ended -and $ended.ok -eq $true) { "it did not stop when asked within " + $def.stop.waitSeconds + " s, and was ended" } else { "IT IS STILL RUNNING: it did not stop when asked, and could not be ended (" + (Protect-HordeServiceText ("" + $ended.detail)) + ")" })
                $gone = [bool]($null -ne $ended -and $ended.ok -eq $true)
            }
            if ($gone) { $s.started = $null }
        }
        $s.proving = $false
        $s.lastAction = [pscustomobject]@{ at = $now.ToUniversalTime(); action = "stop"; step = "hold"; outcome = "done"; reason = ("a person stopped it with horde services stop: " + $said) }
        Write-HordeServiceState -State $s -HordeHome $HordeHome
        $null = Write-HordeServiceJournal -HordeHome $HordeHome -Entries @(New-HordeServiceJournalEntry -At $now -Service $Name -Action "stop" -Step "hold" -Code "held" -Outcome "done" -Reason ("a person stopped it with horde services stop: " + $said))
        [void]$lines.Add($Name + ": held - " + $said + ". The supervisor leaves it as it is until horde services start " + $Name)
        return (& $answer "" @($lines.ToArray()))
    } finally { $lock.Dispose() }
}

function Get-HordeServiceRolloutVerdict {
    # PURE. After `horde rollout`: which of the chosen services did not end where a roll-out should
    # leave them, as { name; reason }. A service that follows a revision must end on it (current, or
    # just updated); one that follows nothing has nothing to roll out; one that is not supervised is
    # left as it is. Everything else - a wait, a failure, an update still part way - is not done.
    param([Parameter(Mandatory = $true)]$Definitions, [Parameter(Mandatory = $true)]$Services)
    $out = New-Object System.Collections.ArrayList
    foreach ($def in @($Definitions)) {
        $one = @($Services | Where-Object { $_.name -ceq $def.name }) | Select-Object -First 1
        if ($null -eq $one) { [void]$out.Add([pscustomobject]@{ name = $def.name; reason = "it was not looked at" }); continue }
        if (@("current", "updated", "disabled", "held") -ccontains $one.code) { continue }
        if ($null -eq $def.follow -and $one.code -ceq "running") { continue }
        [void]$out.Add([pscustomobject]@{ name = $def.name; reason = $one.reason })
    }
    return @($out.ToArray())
}
