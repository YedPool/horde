$HordeCommand = @{
    name    = "fleet"
    group   = "fleet"
    usage   = "fleet record [-All | -Labels <a,b>] [-Exclude <a,b>] | fleet wake <hibernation id> [-DryRun] [-Only <a,b>] | fleet hibernate -Orcs <orc labels or lane folders> [-DryRun] [-WaitMinutes 15] | fleet hibernate -Tier 2 [-DryRun] [-WaitMinutes 15]"
    summary = "hibernation, slice 1. record: write down the fleet's running sessions - every one not retired and running now (-All), or exactly the ones labelled (-Labels), less any -Exclude - with where each sits in the terminal, as one hibernation under Horde's home, and print its id; the master (M) is left out unless -Labels names it, and a registry that cannot be read whole, or a selection that comes to nothing, is refused with nothing written. wake: start a hibernation's sessions again, one new window per orc with its wargs as tabs laid out as saved, each resumed by its session id; a session that is running, or that may be, is refused and left alone; free memory is checked before every start and the wake stops below 15 percent, leaving the rest asleep; each woken session gets one mail telling it to read its PARKED-<label>.md. -DryRun prints the exact plan and changes nothing. -Only wakes just those labels. hibernate (slice 2): put each named Orc - by label or lane folder - and its Wargs to sleep: never the master, the fleet analyst, a session the founder typed into in the last 30 minutes, or an Orc with an open question on his decisions list, and each left running is listed with its reason; the sessions are recorded, asked by mail (Wargs before their Orc) to write where they got to into the fleet's parked folder and stop, and each whose PARKED file is newer than its ask and whose box is idle and empty is sent its own exit command through the waker's checked path, never killed, an Orc only after its Wargs have exited; any not exited within -WaitMinutes is left running as still-awake. -Tier 2 names the Orcs the Orc registry puts in tier 2 instead of listing them (an Orc not running is passed over; a registry with no tier field, or no Orc in the tier, is refused in words with nothing written). One hibernation at a time: another running is refused, retry. While a session is asleep the wake watcher does not knock on it and its mail queues. -DryRun prints the selection, the exclusions and the plan and changes nothing. Nothing here asks a question"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Position = 0)][string]$Verb = "",
            [Parameter(Position = 1)][string]$Id = "",
            [switch]$All,
            [string[]]$Labels = @(),
            [string[]]$Exclude = @(),
            [switch]$DryRun,
            [string[]]$Only = @(),
            [string[]]$Orcs = @(),
            [int]$Tier = 0,
            [int]$WaitMinutes = 15
        )
        # NOTHING IS DECLARED MANDATORY: a missing mandatory parameter is prompted for, and a horde started
        # with its input open waits there for ever (cli/Commands.ps1, New-HordeUsageError). So what must
        # be given is checked here, first, and refused as a usage error.
        if (@("record", "wake", "hibernate") -cnotcontains $Verb) { throw (New-HordeUsageError -Message ("fleet needs a verb: record, wake or hibernate, not '" + $Verb + "'")) }
        $split = { param($list) @(@($list) | ForEach-Object { ("" + $_).Split(",") } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }) }
        $labelList = & $split $Labels; $excludeList = & $split $Exclude; $onlyList = & $split $Only; $orcList = & $split $Orcs
        if ($Verb -cne "hibernate" -and ($orcList.Count -gt 0 -or $PSBoundParameters.ContainsKey("Tier") -or $PSBoundParameters.ContainsKey("WaitMinutes"))) { throw (New-HordeUsageError -Message "-Orcs, -Tier and -WaitMinutes belong to fleet hibernate") }
        if ($Verb -ceq "hibernate") {
            if ($Id -ne "" -or $All -or $labelList.Count -gt 0 -or $excludeList.Count -gt 0 -or $onlyList.Count -gt 0) { throw (New-HordeUsageError -Message "fleet hibernate takes -Orcs or -Tier, -DryRun and -WaitMinutes only") }
            if ($PSBoundParameters.ContainsKey("Tier") -and $Tier -ne 2) { throw (New-HordeUsageError -Message ("-Tier is 2 (the tier that sleeps), not " + $Tier)) }
            if ($Tier -gt 0 -and $orcList.Count -gt 0) { throw (New-HordeUsageError -Message "fleet hibernate takes -Orcs or -Tier, not both") }
            if ($Tier -eq 0 -and $orcList.Count -eq 0) { throw (New-HordeUsageError -Message "fleet hibernate needs -Orcs <orc labels or lane folders>, or -Tier 2") }
            if ($WaitMinutes -lt 1 -or $WaitMinutes -gt 240) { throw (New-HordeUsageError -Message ("-WaitMinutes is 1 to 240, not " + $WaitMinutes)) }
        } elseif ($Verb -ceq "record") {
            if ($Id -ne "" -or $DryRun -or $onlyList.Count -gt 0) { throw (New-HordeUsageError -Message "fleet record takes -All or -Labels, and -Exclude; an id and -Only belong to fleet wake, -DryRun to wake and hibernate") }
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
        # once per message id, and wakes its target (decisions/Notify.ps1 asks the same three). The sender's
        # name says which verb posted it.
        $sender = $(if ($Verb -ceq "hibernate") { "horde-fleet-hibernate" } else { "horde-fleet-wake" })
        . (Join-Path $root "core\Device.ps1")
        . (Join-Path $root "messengers\Port.ps1")
        foreach ($m in @(Get-HordeMessengerFiles)) { if (@(Get-HordeMessengerNames) -cnotcontains (Split-Path -Leaf (Split-Path -Parent $m))) { . $m } }
        $post = {
            param($sessionId, $label, $body, $messageId)
            $found = Find-HordeMessenger -Require @("body.untyped", "idempotent.post", "wake")
            if ($found.state -cne "known") { return (New-HordeUnknown -Reason ("no messenger can deliver it: " + $found.reason)) }
            $from = [pscustomobject]@{ deviceId = (Get-HordeDeviceId); sessionId = $sender }
            $message = [pscustomobject]@{ messageId = $messageId; sessionId = $sessionId; from = $from; body = $body; ttlSeconds = 86400 }
            if ("" + $label -cmatch '\A[A-Z]{1,2}([1-9][0-9]{0,3})?\z') { $message | Add-Member -NotePropertyName "label" -NotePropertyValue $label }
            $a = Send-HordeMessengerMessage -Messenger $found.value -Message $message
            # held is known NOT delivered (messengers/Port.ps1, THE STAGES): a woken session that was not
            # told is not woken.
            if ($a.state -ceq "known" -and "" + $a.value.stage -ceq "held") { return (New-HordeUnknown -Reason ("the messenger held it: " + $a.value.reason)) }
            return $a
        }
        if ($Verb -ceq "hibernate") {
            # WHAT ELSE A HIBERNATION READS, each chosen here and nowhere else (fleet/Hibernate.ps1): the
            # Orcs' status records (lane folder -> letter), the founder's decisions list, the analyst
            # service's files, the waker (a session's box and turn, and its exit command), and the fleet's
            # parked folder under the fleet's own root.
            . (Join-Path $root "fleet\Hibernate.ps1")
            . (Join-Path $root "fleet\StatusPanel.ps1")
            . (Join-Path $root "decisions\Operations.ps1")
            . (Join-Path $root "core\AnalystSession.ps1")
            . (Join-Path $root "core\Identity.ps1")
            . (Join-Path $root "wakers\Port.ps1")
            foreach ($w in @(Get-HordeWakerFiles)) { . $w }
            $waker = $null
            if (-not $DryRun) {
                # READ THROUGH, NEVER RUNG: the waker is asked for a state and an exit command, never a
                # nudge, so a waker whose nudge claims are not yet shown may serve (wakers/Port.ps1).
                $picked = Resolve-HordeProductionWaker -AllowUnverified
                if ($picked.state -cne "known") { throw ("no waker can read whether a session is idle, so nothing was hibernated: " + $picked.reason) }
                $waker = $picked.value
                if (-not (Test-HordeWakerExits $waker)) { throw ("waker '" + $waker.name + "' cannot send a session its exit command, so nothing was hibernated") }
            }
            $questions = {
                $a = Invoke-HordeDecision -Operation "list" -Request @{ state = "open" }
                if ($null -eq $a -or $a.state -cne "known") { return (New-HordeUnknown -Reason $(if ($null -ne $a) { "" + $a.reason } else { "no answer" })) }
                if ("" + $a.value.outcome -cne "done") { return (New-HordeUnknown -Reason ("the list was refused: " + $a.value.reason)) }
                return (New-HordeKnown -Value @(@($a.value.questions) | ForEach-Object { [pscustomobject]@{ number = $_.number; askedBy = "" + $_.askedBy; waiting = @($_.waiting) } }))
            }
            $analysts = {
                $set = Get-HordeAnalystSettings
                if (@("defaults", "read") -cnotcontains ("" + $set.state)) { return (New-HordeUnknown -Reason ("the analyst's settings file is refused: " + (@($set.findings) -join "; "))) }
                $paths = Get-HordeAnalystSessionPaths -Folder (Get-HordeAnalystFolder -Values $set.values)
                $out = @()
                $h = Read-HordeAnalystHandover -Path $paths.handover
                if ($h.state -ceq "known") { $out += "" + $h.value.sessionId } elseif ($h.state -cne "absent") { return (New-HordeUnknown -Reason ("its handover file: " + $h.reason)) }
                $st = Read-HordeAnalystState -Path $paths.state
                if ($st.state -ceq "known") { if ("" + $st.value.sessionId -ne "") { $out += "" + $st.value.sessionId } } else { return (New-HordeUnknown -Reason ("its supervisor's state: " + $st.reason)) }
                return (New-HordeKnown -Value @($out))
            }
            $agentValue = $agent.value
            $hdeps = [pscustomobject]@{
                Now = $now
                Sleep = { param($ms) Start-Sleep -Milliseconds $ms }
                Registry = { Read-HordeRegistry -Root (Get-HordeWezfleetRoot) }
                Agent = $agentValue; Host = $hostAdapter.value
                Status = { Get-HordeFleetStatus }
                Questions = $questions
                Analysts = $analysts
                Typed = { param($c, $since) if ($null -eq $agentValue.lastTyped) { return (New-HordeUnknown -Reason "the harness adapter cannot say what was typed") }; & $agentValue.lastTyped ("" + $c.transcriptPath) $since }
                ParkedFolder = (Join-Path (Get-HordeWezfleetRoot) "_home\thrall\parked")
                ParkedAt = { param($path) if (Test-Path -LiteralPath $path -PathType Leaf) { (Get-Item -LiteralPath $path).LastWriteTimeUtc } else { $null } }
                Post = $post
                Caller = { $me = Get-HordeSelfSessionId; if ($me.state -ceq "known") { "" + $me.value } else { "" } }
                State = { param($sid) Get-HordeWakeState -Waker $waker -Id $sid -Full }
                Exit = { param($sid, $why) Send-HordeWakeExit -Waker $waker -Id $sid -Reason $why }
                # The Orc registry's rows { id; tier }, through its own reader (orcs/Registry.ps1, the dash). A
                # row with no tier member selects nothing, said in words (Get-HordeFleetTierIds).
                Tiers = {
                    . (Join-Path $root "orcs\Registry.ps1")
                    $dash = Get-HordeOrcDash
                    if (-not $dash.ok) { return (New-HordeUnknown -Reason ("" + $dash.reason)) }
                    return (New-HordeKnown -Value @(@($dash.orcs) | ForEach-Object { $row = [ordered]@{ id = "" + $_.id }; if ($null -ne $_.PSObject.Properties["tier"]) { $row["tier"] = $_.tier }; [pscustomobject]$row }))
                }
            }
            $done = $null
            if ($Tier -gt 0) { $done = Invoke-HordeFleetHibernate -Deps $hdeps -Tier $Tier -DryRun:$DryRun -WaitMinutes $WaitMinutes }
            else { $done = Invoke-HordeFleetHibernate -Deps $hdeps -Names $orcList -DryRun:$DryRun -WaitMinutes $WaitMinutes }
            foreach ($l in @($done.lines)) { Write-Output $l }
            return
        }
        $deps = [pscustomobject]@{
            Now = $now
            Sleep = { param($ms) Start-Sleep -Milliseconds $ms }
            FreePercent = { $o = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop; 100.0 * [double]$o.FreePhysicalMemory / [double]$o.TotalVisibleMemorySize }
            Agent = $agent.value; Host = $hostAdapter.value; Post = $post
        }
        $done = Invoke-HordeFleetWake -Id $Id -Deps $deps -DryRun:$DryRun -Only $onlyList
        foreach ($l in @($done.lines)) { Write-Output $l }
    }
}
