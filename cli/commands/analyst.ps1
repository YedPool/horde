$HordeCommand = @{
    name    = "analyst"
    group   = "analyst"
    sustained = $true
    usage   = "analyst tend | analyst run [-TickSeconds <n>] | analyst status | analyst mail -Text <message>"
    summary = "the fleet analyst kept always on, with no model in the loop. The scripts write findings to <analyst folder>\findings.jsonl; the warchief writes to it with mail. tend: one pass - is the analyst's session running and under its context cap (contextCapTokens); is a round due (every roundMinutes, only when something waits); does a finding marked now, or a mail whose first word is one of wakeNowMarkers (URGENT, QUESTION), wake it at once; after heartbeatHours (6) with no wake, a heartbeat round; a round with no ack after ackMinutes is told to the warchief and the founder, once; a session that is gone, or over its cap when a round is due, is replaced by a fresh one through the person's own spawn script (spawnScript; never a restore), and the warchief is told. run: tend every -TickSeconds (60), with a heartbeat, for horde services to keep running. Each tend and each pass of run also checks the hosted relay every relayEveryMinutes (5): its pages answer 200 and its Google sign-in redirects with a client id of the right shape; after relayFailuresBeforeAlert (2) failures in a row the warchief is told by the fleet's mail and one notice is tried, and both again once it is back. status: the session, its context, the rounds and what waits. mail: leave the analyst a message; plain mail waits for the next round, a message starting URGENT or QUESTION wakes it at once. Settings: <HORDE_HOME>\settings\analyst.json"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Position = 0)][ValidateSet("tend", "run", "status", "mail")][string]$Verb,
            [AllowEmptyString()][string]$Text,
            [ValidateRange(10, 600)][int]$TickSeconds = 60
        )
        # The verb is asked for in the body, not declared mandatory: a missing mandatory parameter is
        # PROMPTED for, and a horde started with its input open would wait there (cli/commands/wake.ps1).
        if (-not $PSBoundParameters.ContainsKey("Verb")) { throw (New-HordeUsageError "analyst needs a verb: tend, run, status or mail") }
        # A flag meant for another verb is refused, never silently ignored (cli/Commands.ps1, run blocks).
        $verbFlags = @{ tend = @(); run = @("TickSeconds"); status = @(); mail = @("Text") }
        foreach ($flag in @($PSBoundParameters.Keys)) { if ($flag -ne "Verb" -and $verbFlags[$Verb] -notcontains $flag) { throw ("-" + $flag + " does not belong to analyst " + $Verb) } }
        $root = Get-HordeRoot
        foreach ($f in @("Tristate", "Home", "ModuleSettings", "Heartbeat", "AnalystRounds", "AnalystSession")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
        . (Join-Path $root "cli\AnalystTend.ps1")
        $hordeHome = Get-HordeHome
        $policy = Get-HordeAnalystPolicy -HordeHome $hordeHome
        if (-not $policy.ok) { throw $policy.reason }
        $folder = Get-HordeAnalystFolder -Values $policy.values -HordeHome $hordeHome

        if ($Verb -eq "mail") {
            if (-not $PSBoundParameters.ContainsKey("Text") -or $Text.Trim() -eq "") { throw "analyst mail needs -Text, the message" }
            $w = Write-HordeAnalystMail -Folder $folder -Text $Text -Markers $policy.markers
            Write-Output $w
            return
        }
        if ($Verb -eq "status") { Format-HordeAnalystStatus -Folder $folder -Policy $policy -Heartbeat (Get-HordeAnalystHeartbeatPath -HordeHome $hordeHome) | ForEach-Object { Write-Output $_ }; return }

        # THE REAL TOOLS. The adapters a transcript is read through are loaded here, at the command's own
        # scope, so the blocks they register keep their helpers (core/Transcript.ps1).
        foreach ($a in @(Get-HordeTranscriptAdapterFiles -Root $root)) { . $a }
        $tools = New-HordeAnalystTools
        if (-not (Test-HordeAnalystHomeIsATests -HordeHome $hordeHome)) {
            # Loaded once, only for a home that is not a test's (A TEST'S HOME, cli/AnalystTend.ps1).
            foreach ($f in @("SessionSeat", "Device")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
            . (Join-Path $root "messengers\Port.ps1")
            foreach ($f in @(Get-HordeMessengerFiles)) { . $f }
            . (Join-Path $root "notices\Decide.ps1")
            $tools["Post"] = { param($SessionId, $MessageId, $Body, $Values) return (Send-HordeAnalystMessage -SessionId $SessionId -MessageId $MessageId -Body $Body -Values $Values -HordeHome $hordeHome) }
            $tools["Tell"] = { param($Key, $Body, $Values) return (Send-HordeAnalystWarchief -Key $Key -Body $Body -Values $Values -HordeHome $hordeHome) }
            $tools["Notify"] = { param($Line) return (Send-HordeAnalystFounderNotice -Text $Line -HordeHome $hordeHome) }
            $tools["Spawn"] = { param($Script, $Handover, $Reason, $Values) return (Start-HordeAnalystSession -Script $Script -Handover $Handover -Reason $Reason) }
        }
        # THE RELAY WATCH (core/RelayWatch.ps1): the warchief is told through the fleet's mail - the same
        # teller as above, which does not travel through the relay - and one notice is tried beside it.
        . (Join-Path $root "core\RelayWatch.ps1")
        $relayOrigin = "" + $policy.values.relayOrigin
        if ($relayOrigin -eq "") {
            . (Join-Path $root "relay\Identity.ps1")
            $rs = Get-HordeRelaySettingValues -HordeHome $hordeHome
            if ($rs.state -ceq "known") { $relayOrigin = "" + $rs.value.values.pairOrigin }
        }
        $relayTools = @{
            Now = { return [datetime]::UtcNow }
            # A test's home checks only a server on this machine: no suite can reach the real relay.
            Fetch = { param($Url) if ((Test-HordeAnalystHomeIsATests -HordeHome $hordeHome) -and -not ([uri]$Url).IsLoopback) { throw "a test's home checks only a relay on this machine" }; return (Get-HordeRelayWatchResponse -Url $Url) }
            Tell = $null; Notify = $null
        }
        if ($null -ne $tools["Tell"]) { $relayTools["Tell"] = { param($Body) return (Send-HordeAnalystWarchief -Key "relay" -Body $Body -Values $policy.values -HordeHome $hordeHome) } }
        if ($null -ne $tools["Notify"]) { $relayTools["Notify"] = { param($Line) return (Send-HordeAnalystFounderNotice -Text $Line -HordeHome $hordeHome) } }
        $relayState = [System.IO.Path]::Combine($hordeHome, "analyst", "relay-watch.json")
        # THE OVERSEER WATCHER CHECK (core/WatcherHeartbeat.ps1, T-0388): the same two tellers, a file of its own.
        . (Join-Path $root "core\WatcherHeartbeat.ps1")
        $beatState = [System.IO.Path]::Combine($hordeHome, "analyst", "watcher-beat.json")
        $beatRun = "" + $policy.values.watcherRunFile
        if ($beatRun -eq "") { $beatRun = [System.IO.Path]::Combine((Get-HordeWezfleetRoot), "_home", "orcs", "overseer", "run.json") }
        $beatTools = @{ Now = { return [datetime]::UtcNow }; Tell = $relayTools["Tell"]; Notify = $relayTools["Notify"] }
        if ($Verb -eq "tend") {
            $done = Invoke-HordeAnalystLockedPass -Tools $tools -Policy $policy -Folder $folder
            foreach ($l in @($done.lines)) { Write-Output ("analyst: " + $l) }
            foreach ($l in @((Invoke-HordeRelayWatch -Tools $relayTools -Policy $policy.values -StatePath $relayState -Origin $relayOrigin).lines)) { Write-Output $l }
            if ($policy.values.watcherCheck) { foreach ($l in @((Invoke-HordeWatcherHeartbeat -Tools $beatTools -Policy $policy.values -RunPath $beatRun -StatePath $beatState).lines)) { Write-Output $l } }
            if ($done.problem -ne "") { throw $done.problem }
            return
        }
        # run: the pass every tick, with a heartbeat horde services reads (alive.heartbeat:
        # analyst\heartbeat.json under the analyst folder's home, tickSeconds the same as here).
        $beat = Get-HordeAnalystHeartbeatPath -HordeHome $hordeHome
        $self = Get-HordeHeartbeatSelf
        $pass = [long]0
        while ($true) {
            $pass++
            $problem = ""
            try {
                $policy = Get-HordeAnalystPolicy -HordeHome $hordeHome
                if (-not $policy.ok) { $problem = $policy.reason }
                else {
                    $done = Invoke-HordeAnalystLockedPass -Tools $tools -Policy $policy -Folder $folder
                    foreach ($l in @($done.lines)) { Write-Output ((Get-Date).ToUniversalTime().ToString("s") + "Z analyst: " + $l) }
                    $problem = $done.problem
                    foreach ($l in @((Invoke-HordeRelayWatch -Tools $relayTools -Policy $policy.values -StatePath $relayState -Origin $relayOrigin).lines)) { Write-Output ((Get-Date).ToUniversalTime().ToString("s") + "Z " + $l) }
                    if ($policy.values.watcherCheck) { foreach ($l in @((Invoke-HordeWatcherHeartbeat -Tools $beatTools -Policy $policy.values -RunPath $beatRun -StatePath $beatState).lines)) { Write-Output ((Get-Date).ToUniversalTime().ToString("s") + "Z " + $l) } }
                }
            } catch { $problem = "the pass failed: " + $_.Exception.Message }
            if ($problem -ne "") { Write-Output ((Get-Date).ToUniversalTime().ToString("s") + "Z analyst: " + $problem) }
            # A pass that cannot act says so in its heartbeat (core/Heartbeat.ps1, condition), so the
            # supervisor of services never calls it well.
            $null = Write-HordeHeartbeatQuietly -Path $beat -At ([datetime]::UtcNow) -ProcessId $self.pid -ProcessStartedAt $self.startedAt -TickSeconds $TickSeconds -Pass $pass -Condition $(if ($problem -ne "") { "cannot-act" } else { "" }) -Why $problem
            Start-Sleep -Seconds $TickSeconds
        }
    }
}
