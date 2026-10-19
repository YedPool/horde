$HordeCommand = @{
    name    = "fleet"
    group   = "fleet"
    usage   = "fleet record [-All | -Labels <a,b>] [-Exclude <a,b>] | fleet wake <hibernation id> [-DryRun] [-Only <a,b>] [-Retry] | fleet wake -Lot <lot id> [-Members <sessions or labels>] [-DryRun] [-Retry] | fleet lots [-Json] | fleet lots backfill -File <json> | fleet hibernate -Tier 2 [-Orcs <orc labels or lane folders>] [-DryRun] [-WaitMinutes 15]"
    summary = "hibernation, slice 1. record: write down the fleet's running sessions - every one not retired and running now (-All), or exactly the ones labelled (-Labels), less any -Exclude - with where each sits in the terminal, as one hibernation under Horde's home, and print its id; the master (M) is left out unless -Labels names it, and a registry that cannot be read whole, or a selection that comes to nothing, is refused with nothing written. wake: start a hibernation's sessions again, one new window per orc with its wargs as tabs laid out as saved, each resumed by its session id; a session that is running, or that may be, is refused and left alone; free memory is checked before every start and the wake stops below 15 percent, leaving the rest asleep; each woken session gets one mail telling it to read its PARKED-<label>.md. a session an earlier wake left waking, or that failed after its pane was started, may still be loading there and is held unless -Retry is given (the liveness check still runs). -DryRun prints the exact plan and changes nothing. -Only wakes just those labels. hibernate (slice 2): put the Orcs the Orc registry puts in tier 2 - all of them, or only those -Orcs names, by label or lane folder - and their Wargs to sleep; -Tier 2 is always asked for, and a tier 1 Orc, one with no tier set or one the registry does not know is NEVER hibernated, not even when named (a named one that is not tier 2 refuses the run), and a registry that cannot be read refuses it; never the master, the fleet analyst, a session the founder typed into in the last 30 minutes, or an Orc with an open question on his decisions list, and each left running is listed with its reason; the sessions are recorded, asked by mail (Wargs before their Orc) to write where they got to into the fleet's parked folder and stop, and each whose PARKED file is newer than its ask and whose box is idle and empty is sent its own exit command through the waker's checked path, never killed, an Orc only after its Wargs have exited; any not exited within -WaitMinutes is left running as still-awake. One hibernation at a time: another running is refused, retry. While a session is asleep the wake watcher does not knock on it and its mail queues. -DryRun prints the selection, the exclusions and the plan and changes nothing. Nothing here asks a question. PARKING LOTS (T-0216): every hibernation is one lot, with its time, who parked and why. lots lists them newest first with each member and its state - asleep (in the lot and not running), woken, still-awake or failed; -Json prints the same as JSON. wake -Lot <id> wakes the whole lot, or just -Members (session ids, unique id prefixes of eight characters or more, or labels), with every rule of wake. lots backfill -File writes the lots a file names that are not there yet (source backfill) and writes nothing the second time."
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
            [int]$WaitMinutes = 15,
            [switch]$Retry,
            [string]$Lot = "",
            [string[]]$Members = @(),
            [string]$File = "",
            [switch]$Json
        )
        # NOTHING IS DECLARED MANDATORY: a missing mandatory parameter is prompted for, and a horde started
        # with its input open waits there for ever (cli/Commands.ps1, New-HordeUsageError). So what must
        # be given is checked here, first, and refused as a usage error.
        if (@("record", "wake", "hibernate", "lots") -cnotcontains $Verb) { throw (New-HordeUsageError -Message ("fleet needs a verb: record, wake, hibernate or lots, not '" + $Verb + "'")) }
        $split = { param($list) @(@($list) | ForEach-Object { ("" + $_).Split(",") } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }) }
        $labelList = & $split $Labels; $excludeList = & $split $Exclude; $onlyList = & $split $Only; $orcList = & $split $Orcs; $memberList = & $split $Members
        if ($Verb -cne "lots" -and ($Json -or $File -ne "")) { throw (New-HordeUsageError -Message "-Json and -File belong to fleet lots") }
        if ($Verb -cne "wake" -and ($Lot -ne "" -or $memberList.Count -gt 0)) { throw (New-HordeUsageError -Message "-Lot and -Members belong to fleet wake") }
        if ($Verb -cne "hibernate" -and ($orcList.Count -gt 0 -or $PSBoundParameters.ContainsKey("WaitMinutes") -or $PSBoundParameters.ContainsKey("Tier"))) { throw (New-HordeUsageError -Message "-Orcs, -Tier and -WaitMinutes belong to fleet hibernate") }
        if ($Verb -ceq "lots") {
            # fleet lots [-Json]  |  fleet lots backfill -File <json>: nothing else is taken.
            if ($All -or $labelList.Count -gt 0 -or $excludeList.Count -gt 0 -or $onlyList.Count -gt 0 -or $orcList.Count -gt 0 -or $DryRun -or $Retry -or $PSBoundParameters.ContainsKey("Tier") -or $PSBoundParameters.ContainsKey("WaitMinutes")) { throw (New-HordeUsageError -Message "fleet lots takes -Json, or backfill -File <json>, only") }
            if ($Id -cne "" -and $Id -cne "backfill") { throw (New-HordeUsageError -Message ("fleet lots takes no argument but backfill, not '" + $Id + "'")) }
            if ($Id -ceq "backfill" -and ($File -eq "" -or $Json)) { throw (New-HordeUsageError -Message "fleet lots backfill needs -File <json> and takes no -Json") }
            if ($Id -ceq "" -and $File -ne "") { throw (New-HordeUsageError -Message "-File belongs to fleet lots backfill") }
        } elseif ($Verb -ceq "hibernate") {
            if ($Id -ne "" -or $All -or $labelList.Count -gt 0 -or $excludeList.Count -gt 0 -or $onlyList.Count -gt 0 -or $Retry) { throw (New-HordeUsageError -Message "fleet hibernate takes -Tier, -Orcs, -DryRun and -WaitMinutes only") }
            # THE TIER GATE IS ALWAYS ASKED FOR: -Tier 2, the one tier that sleeps. -Orcs only narrows it.
            if ($Tier -ne 2) { throw (New-HordeUsageError -Message "fleet hibernate needs -Tier 2: only an Orc the Orc registry puts in tier 2 is ever hibernated (-Orcs <orc labels or lane folders> narrows it to those named)") }
            if ($WaitMinutes -lt 1 -or $WaitMinutes -gt 240) { throw (New-HordeUsageError -Message ("-WaitMinutes is 1 to 240, not " + $WaitMinutes)) }
        } elseif ($Verb -ceq "record") {
            if ($Id -ne "" -or $DryRun -or $Retry -or $onlyList.Count -gt 0) { throw (New-HordeUsageError -Message "fleet record takes -All or -Labels, and -Exclude; an id and -Only belong to fleet wake, -DryRun to wake and hibernate, -Retry to fleet wake") }
            if ($All -eq ($labelList.Count -gt 0)) { throw (New-HordeUsageError -Message "fleet record needs exactly one of -All or -Labels") }
        } else {
            if ($Lot -ne "") {
                # A LOT ID IS A HIBERNATION ID (fleet/LotTables.ps1): -Lot is the same wake, named for what the founder sees.
                if ($Id -ne "" -or $onlyList.Count -gt 0) { throw (New-HordeUsageError -Message "fleet wake takes a hibernation id or -Lot, not both, and -Only is for a hibernation id (-Members picks within a lot)") }
                if ($Lot -cnotmatch '\A([0-9]{8}-[0-9]{6}|[0-7][0-9A-HJKMNP-TV-Z]{25})\z') { throw (New-HordeUsageError -Message ("fleet wake -Lot needs a lot id (a 26-character ULID as fleet lots lists it, or a hibernation id yyyymmdd-hhmmss), not '" + $Lot + "'")) }
            } else {
                if ($memberList.Count -gt 0) { throw (New-HordeUsageError -Message "-Members belongs to fleet wake -Lot") }
                if ($Id -cnotmatch '\A[0-9]{8}-[0-9]{6}\z') { throw (New-HordeUsageError -Message ("fleet wake needs a hibernation id, yyyymmdd-hhmmss, not '" + $Id + "'")) }
            }
            if ($All -or $labelList.Count -gt 0 -or $excludeList.Count -gt 0) { throw (New-HordeUsageError -Message "fleet wake takes -DryRun and -Only; -All, -Labels and -Exclude belong to fleet record") }
        }
        # Loaded here, in the command's own scope (cli/commands/metrics.ps1 says why). This block chooses
        # the real outside world - the clock, the registry, the adapters, free memory, the mail - in this
        # one place; what is recorded and woken is decided in fleet/.
        $root = Get-HordeRoot
        . (Join-Path $root "fleet\Lots.ps1")
        foreach ($f in @(Get-HordeFleetAdapterFiles -Root $root)) { . $f }
        $agent = Resolve-HordeFleetAdapter -Kind "agent"
        if ($agent.state -ne "known") { throw $agent.reason }
        $hostAdapter = Resolve-HordeFleetAdapter -Kind "host"
        if ($hostAdapter.state -ne "known") { throw $hostAdapter.reason }
        $now = { [datetime]::UtcNow }

        if ($Verb -ceq "lots") {
            if ($Id -ceq "backfill") {
                # A FILE CARRIES NO MACHINE PATH: the working directory, pane, parent and label a row leaves blank are read
                # from the fleet registry (core/WezfleetState.ps1, read only), and a PARKED note is the one in the fleet's
                # parked folder when it is there.
                $reg = Read-HordeRegistry -Root (Get-HordeWezfleetRoot)
                $enrich = { param($sid)
                    $row = $reg.records["" + $sid]
                    if ($null -eq $row) { return $null }
                    $o = [ordered]@{}
                    foreach ($n in @("label", "parent", "cwd", "pane")) { $f = Get-HordeStoredField -Record $row.record -Name $n; if ($f.state -eq "known") { $o[$n] = "" + $f.value } }
                    return [pscustomobject]$o }
                $bdeps = [pscustomobject]@{ AgentName = $agent.value.name; HostName = $hostAdapter.value.name; Enrich = $enrich; ParkedFolder = (Join-Path (Get-HordeWezfleetRoot) "_home\thrall\parked") }
                $done = Invoke-HordeFleetLotBackfill -File $File -Deps $bdeps
                foreach ($l in @($done.lines)) { Write-Output $l }
                return
            }
            $got = Get-HordeFleetLots -Agent $agent.value
            if ($got.state -cne "known") { throw ("the lots cannot be listed: " + $got.reason) }
            if ($Json) { Write-Output (ConvertTo-HordeFleetAsciiJson -Value ([pscustomobject][ordered]@{ v = 1; lots = @($got.value.lots); skipped = @($got.value.skipped) })); return }
            if (@($got.value.lots).Count -eq 0) { Write-Output "no parking lots yet" }
            foreach ($l in @(Format-HordeFleetLotsText -Lots @($got.value.lots))) { Write-Output $l }
            foreach ($n in @($got.value.skipped)) { Write-Output ("  note: " + $n) }
            return
        }

        if ($Verb -ceq "record") {
            $deps = [pscustomobject]@{ Now = $now; Agent = $agent.value; Host = $hostAdapter.value; Registry = { Read-HordeRegistry -Root (Get-HordeWezfleetRoot) } }
            $selector = $null; $selection = $null
            if ($All) { $selector = New-HordeFleetSelectorAll; $selection = [pscustomobject][ordered]@{ kind = "all"; labels = @(); exclude = @($excludeList) } }
            else { $selector = New-HordeFleetSelectorLabels -Labels $labelList; $selection = [pscustomobject][ordered]@{ kind = "labels"; labels = @($labelList); exclude = @($excludeList) } }
            # THE LOT'S BY is the session running this, when it has an id (fleet/Hibernation.ps1 turns it into a label).
            . (Join-Path $root "core\Device.ps1")
            . (Join-Path $root "core\Identity.ps1")
            $recBy = ""
            $me = Get-HordeSelfSessionId
            if ($me.state -ceq "known") { $recBy = "" + $me.value }
            $done = Invoke-HordeFleetRecord -Deps $deps -Selector $selector -Selection $selection -Exclude $excludeList -By $recBy -Why "fleet record"
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
        if ($Verb -ceq "hibernate") {
            # WHAT ELSE A HIBERNATION READS, each chosen here and nowhere else (fleet/Hibernate.ps1): the
            # Orcs' status records (lane folder -> letter), the founder's decisions list, the analyst
            # service's files, the waker (a session's box and turn, and its exit command), and the fleet's
            # parked folder under the fleet's own root.
            . (Join-Path $root "fleet\Hibernate.ps1")
            . (Join-Path $root "fleet\StatusPanel.ps1")
            . (Join-Path $root "orcs\Registry.ps1")
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
            # THE ORC REGISTRY's TIERS by Orc letter (the label its session carries): the dash's rows, which take a lane's
            # letter as it is now. A letter two rows give different tiers is no tier at all. Unreadable: unknown.
            $tiers = {
                $dash = Get-HordeOrcDash
                if (-not $dash.ok) { return (New-HordeUnknown -Reason ("" + $dash.reason)) }
                $map = @{}
                foreach ($o in @($dash.orcs)) {
                    $l = "" + $o.letter
                    if ($l -eq "") { continue }
                    $t = $(if ($null -ne $o.tier) { [int]$o.tier } else { $null })
                    if ($map.ContainsKey($l) -and ("" + $map[$l]) -cne ("" + $t)) { $map[$l] = $null } else { $map[$l] = $t }
                }
                return (New-HordeKnown -Value $map)
            }
            $agentValue = $agent.value
            $hdeps = [pscustomobject]@{
                Now = $now
                Sleep = { param($ms) Start-Sleep -Milliseconds $ms }
                Registry = { Read-HordeRegistry -Root (Get-HordeWezfleetRoot) }
                Agent = $agentValue; Host = $hostAdapter.value
                Status = { Get-HordeFleetStatus }
                OrcTiers = $tiers
                Questions = $questions
                Analysts = $analysts
                Typed = { param($c, $since) if ($null -eq $agentValue.lastTyped) { return (New-HordeUnknown -Reason "the harness adapter cannot say what was typed") }; & $agentValue.lastTyped ("" + $c.transcriptPath) $since }
                ParkedFolder = (Join-Path (Get-HordeWezfleetRoot) "_home\thrall\parked")
                ParkedAt = { param($path) if (Test-Path -LiteralPath $path -PathType Leaf) { (Get-Item -LiteralPath $path).LastWriteTimeUtc } else { $null } }
                Post = $post
                Caller = { $me = Get-HordeSelfSessionId; if ($me.state -ceq "known") { "" + $me.value } else { "" } }
                State = { param($sid) Get-HordeWakeState -Waker $waker -Id $sid -Full }
                Exit = { param($sid, $why) Send-HordeWakeExit -Waker $waker -Id $sid -Reason $why }
            }
            $done = Invoke-HordeFleetHibernate -Deps $hdeps -Names $orcList -Tier $Tier -DryRun:$DryRun -WaitMinutes $WaitMinutes
            foreach ($l in @($done.lines)) { Write-Output $l }
            return
        }
        $deps = [pscustomobject]@{
            Now = $now
            Sleep = { param($ms) Start-Sleep -Milliseconds $ms }
            FreePercent = { $o = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop; 100.0 * [double]$o.FreePhysicalMemory / [double]$o.TotalVisibleMemorySize }
            Agent = $agent.value; Host = $hostAdapter.value; Post = $post
            # Where a session that parked without a file named in its record is told to look (fleet/Wake.ps1).
            ParkedFolder = (Join-Path (Get-HordeWezfleetRoot) "_home\thrall\parked")
            # The woken id's fleet registry row and its pane, read only through core/WezfleetState.ps1.
            RegistryPane = { param($sid)
                $reg = Read-HordeRegistry -Root (Get-HordeWezfleetRoot)
                $row = $reg.records["" + $sid]
                if ($null -eq $row) { return (New-HordeAbsent -Note ("the fleet registry has no row for " + $sid)) }
                $pane = Get-HordeStoredField -Record $row.record -Name "pane"
                if ($pane.state -eq "known") { return (New-HordeKnown -Value ("" + $pane.value)) }
                return (New-HordeUnknown -Reason "its registry row names no pane") }
        }
        # EVERY WAKE GOES THROUGH THE LOT'S (T-0216): a hibernation id and a lot id name the same park, and a wake of either
        # is recorded as a wake row with a row for each session it was asked to wake. -Only (labels) is -Members.
        $wakeBy = ""
        $me = Get-HordeSelfSessionId
        if ($me.state -ceq "known") { $wakeBy = "" + $me.value }
        $wakeMembers = @(@($memberList) + @($onlyList))
        $done = Invoke-HordeFleetWakeLot -Lot $(if ($Lot -ne "") { $Lot } else { $Id }) -Members $wakeMembers -Deps $deps -DryRun:$DryRun -Retry:$Retry -By $wakeBy
        foreach ($l in @($done.lines)) { Write-Output $l }
    }
}
