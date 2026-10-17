$HordeCommand = @{
    name    = "fleet"
    group   = "fleet"
    usage   = "fleet record [-All | -Labels <a,b>] [-Exclude <a,b>] | fleet wake <hibernation id> [-DryRun] [-Only <a,b>] [-Retry]"
    summary = "hibernation, slice 1. record: write down the fleet's running sessions - every one not retired and running now (-All), or exactly the ones labelled (-Labels), less any -Exclude - with where each sits in the terminal, as one hibernation under Horde's home, and print its id; the master (M) is left out unless -Labels names it, and a registry that cannot be read whole, or a selection that comes to nothing, is refused with nothing written. wake: start a hibernation's sessions again, one new window per orc with its wargs as tabs laid out as saved, each resumed by its session id; a session that is running, or that may be, is refused and left alone; free memory is checked before every start and the wake stops below 15 percent, leaving the rest asleep; each woken session gets one mail telling it to read its PARKED-<label>.md. a session an earlier wake left waking, or that failed after its pane was started, may still be loading there and is held unless -Retry is given (the liveness check still runs). -DryRun prints the exact plan and changes nothing. -Only wakes just those labels. Nothing here asks a question"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Position = 0)][string]$Verb = "",
            [Parameter(Position = 1)][string]$Id = "",
            [switch]$All,
            [string[]]$Labels = @(),
            [string[]]$Exclude = @(),
            [switch]$DryRun,
            [string[]]$Only = @(),
            [switch]$Retry
        )
        # NOTHING IS DECLARED MANDATORY: a missing mandatory parameter is prompted for, and a horde started
        # with its input open waits there for ever (cli/Commands.ps1, New-HordeUsageError). So what must
        # be given is checked here, first, and refused as a usage error.
        if (@("record", "wake") -cnotcontains $Verb) { throw (New-HordeUsageError -Message ("fleet needs a verb: record or wake, not '" + $Verb + "'")) }
        $split = { param($list) @(@($list) | ForEach-Object { ("" + $_).Split(",") } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }) }
        $labelList = & $split $Labels; $excludeList = & $split $Exclude; $onlyList = & $split $Only
        if ($Verb -ceq "record") {
            if ($Id -ne "" -or $DryRun -or $Retry -or $onlyList.Count -gt 0) { throw (New-HordeUsageError -Message "fleet record takes -All or -Labels, and -Exclude; an id, -DryRun, -Only and -Retry belong to fleet wake") }
            if ($All -eq ($labelList.Count -gt 0)) { throw (New-HordeUsageError -Message "fleet record needs exactly one of -All or -Labels") }
        } else {
            if ($Id -cnotmatch '\A[0-9]{8}-[0-9]{6}\z') { throw (New-HordeUsageError -Message ("fleet wake needs a hibernation id, yyyymmdd-hhmmss, not '" + $Id + "'")) }
            if ($All -or $labelList.Count -gt 0 -or $excludeList.Count -gt 0) { throw (New-HordeUsageError -Message "fleet wake takes -DryRun and -Only; -All, -Labels and -Exclude belong to fleet record") }
        }
        # Loaded here, in the command's own scope (cli/commands/metrics.ps1 says why). This block chooses
        # the real outside world - the clock, the registry, the adapters, free memory, the mail - in this
        # one place; what is recorded and woken is decided in fleet/.
        $root = Get-HordeRoot
        . (Join-Path $root "fleet\Wake.ps1")
        foreach ($f in @(Get-HordeFleetAdapterFiles -Root $root)) { . $f }
        $agent = Resolve-HordeFleetAdapter -Kind "agent"
        if ($agent.state -ne "known") { throw $agent.reason }
        $hostAdapter = Resolve-HordeFleetAdapter -Kind "host"
        if ($hostAdapter.state -ne "known") { throw $hostAdapter.reason }
        $now = { [datetime]::UtcNow }

        if ($Verb -ceq "record") {
            $deps = [pscustomobject]@{ Now = $now; Agent = $agent.value; Host = $hostAdapter.value; Registry = { Read-HordeRegistry -Root (Get-HordeWezfleetRoot) } }
            $selector = $null; $selection = $null
            if ($All) { $selector = New-HordeFleetSelectorAll; $selection = [pscustomobject][ordered]@{ kind = "all"; labels = @(); exclude = @($excludeList) } }
            else { $selector = New-HordeFleetSelectorLabels -Labels $labelList; $selection = [pscustomobject][ordered]@{ kind = "labels"; labels = @($labelList); exclude = @($excludeList) } }
            $done = Invoke-HordeFleetRecord -Deps $deps -Selector $selector -Selection $selection -Exclude $excludeList
            foreach ($s in @($done.record.sessions)) { Write-Output ("  " + (Get-HordeFleetSessionName -Session $s) + " " + $s.role + " " + $s.cwd) }
            foreach ($n in @($done.notes)) { Write-Output ("  note: " + $n) }
            Write-Output ("recorded hibernation " + $done.id + ": " + @($done.record.sessions).Count + " session(s), in " + $done.path)
            return
        }

        # The mail goes through the messenger port, to the one loaded messenger that posts a body untyped,
        # once per message id, and wakes its target (decisions/Notify.ps1 asks the same three).
        . (Join-Path $root "core\Device.ps1")
        . (Join-Path $root "core\Identity.ps1")
        . (Join-Path $root "messengers\Port.ps1")
        foreach ($m in @(Get-HordeMessengerFiles)) { if (@(Get-HordeMessengerNames) -cnotcontains (Split-Path -Leaf (Split-Path -Parent $m))) { . $m } }
        $post = {
            param($sessionId, $label, $body, $messageId)
            $found = Find-HordeMessenger -Require @("body.untyped", "idempotent.post", "wake")
            if ($found.state -cne "known") { return (New-HordeUnknown -Reason ("no messenger can deliver it: " + $found.reason)) }
            # THE SENDER MUST BE ONE THE FLEET'S MAIL CAN NAME: a session id or a hub label. A made-up
            # sender name was held at once as bad-from, so every real wake marked its sessions failed though
            # they ran (found by test/e2e/e2e-fleet.ps1; probed on the shipped messenger). The
            # waking session's own id when it has one (core/Identity.ps1); else the reserved system sender
            # "horde" (fleet/Wake.ps1, New-HordeFleetWakeSender; decided by K, 2026-10-16). Never M: a wake
            # the phone started is not M's act.
            $from = New-HordeFleetWakeSender -DeviceId (Get-HordeDeviceId) -SelfSessionId (Get-HordeSelfSessionId)
            $message = [pscustomobject]@{ messageId = $messageId; sessionId = $sessionId; from = $from; body = $body; ttlSeconds = 86400 }
            if ("" + $label -cmatch '\A[A-Z]{1,2}([1-9][0-9]{0,3})?\z') { $message | Add-Member -NotePropertyName "label" -NotePropertyValue $label }
            $a = Send-HordeMessengerMessage -Messenger $found.value -Message $message
            # held is known NOT delivered (messengers/Port.ps1, THE STAGES): a woken session that was not
            # told is not woken.
            if ($a.state -ceq "known" -and "" + $a.value.stage -ceq "held") { return (New-HordeUnknown -Reason ("the messenger held it: " + $a.value.reason)) }
            return $a
        }
        $deps = [pscustomobject]@{
            Now = $now
            Sleep = { param($ms) Start-Sleep -Milliseconds $ms }
            FreePercent = { $o = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop; 100.0 * [double]$o.FreePhysicalMemory / [double]$o.TotalVisibleMemorySize }
            Agent = $agent.value; Host = $hostAdapter.value; Post = $post
            # The woken id's fleet registry row and its pane, read only through core/WezfleetState.ps1.
            RegistryPane = { param($sid)
                $reg = Read-HordeRegistry -Root (Get-HordeWezfleetRoot)
                $row = $reg.records["" + $sid]
                if ($null -eq $row) { return (New-HordeAbsent -Note ("the fleet registry has no row for " + $sid)) }
                $pane = Get-HordeStoredField -Record $row.record -Name "pane"
                if ($pane.state -eq "known") { return (New-HordeKnown -Value ("" + $pane.value)) }
                return (New-HordeUnknown -Reason "its registry row names no pane") }
        }
        $done = Invoke-HordeFleetWake -Id $Id -Deps $deps -DryRun:$DryRun -Only $onlyList -Retry:$Retry
        foreach ($l in @($done.lines)) { Write-Output $l }
    }
}
