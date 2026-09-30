# core/Faults - the Horde's cardinality checks, computed from the same answers the view shows.
#
# Every check reports and repairs nothing (YedPool/wezfleet lib/Hierarchy.ps1:21-24, "NOTHING here
# repairs anything"), and none is stored (core-roles L-019): a fault is recomputed from the view each
# time, so it can never disagree with a row. Each check returns { kind; answer; found }:
#   answer  known $true when something was found, known $false when the stores prove there is
#           nothing, unknown with the reason when a store the check needs could not be read -
#           "if the registry cannot be read, the Warchief count is unknown, not zero"
#           (planning/migration-plan.html section 2)
#   found   { subjects; detail } per instance; subjects are session ids, handles or pids as text
#
# THE CHECKS. The ten wezfleet has today (research F1-F10), in Horde's vocabulary (core-roles L-019):
#   no-warchief, two-warchiefs, orc-not-under-warchief, parent-missing (lib/Hierarchy.ps1:77-107),
#   conversation-in-two-processes (lib/Common.ps1:684-708), registry-hook-silent
#   (lib/Registry.ps1:987-1010), session-in-two-handles (lib/Registry.ps1:667-673),
#   run-ambiguous (lib/Common.ps1:339-347), handle-claimed-twice (lib/Registry.ps1:395, where it is
#   not a fault at all: newest wins), warchief-claim-pending (lib/Master.ps1:118-137).
# And the ones the ownership table and the stores imply: parent-retired (split from parent-missing,
# which wezfleet cannot tell apart, lib/Hierarchy.ps1:42-58), parent-cycle, pane-sessions-hijack
# (YedPool/wezfleet f09f4e1), running-but-retired, orphan-process (core/identity), fleet-id-on-two-
# records, label-held-twice, session-id-not-uuid (core-identity L-052: identity keys ids the stored
# record refuses, and this is where that is decided - keyed, and flagged), and roster-entry-twice (a
# roster or run manifest listing one fleet id twice, whose entry the run resolver never picks - the
# review of PR #31, finding 8).
#
# A REGISTRY RECORD WITH NO CONTROL FILE IS NOT A FAULT: that is a stopped session, and absence is a
# liveStatus answer (7 of 16 live records on 2026-09-30).

# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "Roles.ps1")

function New-HordeFault {
    param([string]$Kind, $Found, [string]$UnknownReason = "")
    $list = @($Found | Where-Object { $null -ne $_ })
    $answer = $null
    if ($list.Count -gt 0) { $answer = New-HordeKnown -Value $true }
    elseif ($UnknownReason -ne "") { $answer = New-HordeUnknown -Reason $UnknownReason }
    else { $answer = New-HordeKnown -Value $false }
    return [pscustomobject]@{ PSTypeName = "Horde.Fault"; kind = $Kind; answer = $answer; found = $list }
}

function New-HordeFinding { param([string[]]$Subjects, [string]$Detail) return [pscustomobject]@{ subjects = @($Subjects); detail = $Detail } }

function ConvertTo-HordeRoleRead {
    # The registry and claims as core/roles counts them, so the warchief checks use the one counting
    # rule Horde has (Get-HordeRoleCount, Get-HordeRoleClaimCount, Get-HordeRoleHeld) over the same
    # read the view came from, rather than reading the registry a second time.
    param($C)
    $sessions = New-Object System.Collections.ArrayList
    foreach ($k in @($C.wf.registry.records.Keys)) {
        $r = $C.wf.registry.records[$k].record
        $role = Read-HordeRecordRole -Record $r -Table $C.roleTable
        $rt = Get-HordeField -Record $r -Name "retired"
        [void]$sessions.Add([pscustomobject]@{ id = $k; retired = ($rt.state -eq "known" -and [bool]$rt.value); role = $role.role; raw = $role.raw; field = $role.field })
    }
    $claims = New-Object System.Collections.ArrayList
    foreach ($k in @($C.wf.claims.claims.Keys)) {
        $claimObj = $C.wf.claims.claims[$k].claim
        $role = Read-HordeRecordRole -Record $claimObj -Table $C.roleTable
        $sp = $null; if ($null -ne $claimObj.PSObject.Properties["spawnedAt"]) { $sp = $claimObj.spawnedAt }
        [void]$claims.Add([pscustomobject]@{ pane = $k; role = $role.role; raw = $role.raw; field = $role.field; spawnedAt = $sp })
    }
    $all = New-HordeKnown -Value $true
    $why = @(@($C.wf.registry.complete, $C.wf.claims.complete) | Where-Object { $_.state -ne "known" } | ForEach-Object { $_.reason })
    if ($why.Count -gt 0) { $all = New-HordeUnknown -Reason ($why -join "; ") }
    return [pscustomobject]@{ PSTypeName = "Horde.RoleRead"; sessions = $sessions.ToArray(); claims = $claims.ToArray(); unreadable = @(); mismatched = @()
                              sessionsComplete = $C.wf.registry.complete; claimsComplete = $C.wf.claims.complete; complete = $all }
}

function Get-HordeLiveRecords {
    # The registry records that are not retired, as { id; record }.
    param($C)
    return @($C.wf.registry.records.Values | Where-Object { $rt = Get-HordeField -Record $_.record -Name "retired"; -not ($rt.state -eq "known" -and [bool]$rt.value) })
}

function Get-HordeFaults {
    param($States, $C, $Claimed)
    $out = New-Object System.Collections.ArrayList
    $roleRead = ConvertTo-HordeRoleRead -C $C
    $regIncomplete = ""
    if ($C.wf.registry.complete.state -ne "known") { $regIncomplete = "the registry is incomplete (" + $C.wf.registry.complete.reason + ")" }
    $byId = @{}
    foreach ($S in $States) { $byId[$S.id.ToLowerInvariant()] = $S }
    $live = Get-HordeLiveRecords -C $C

    # no-warchief: nobody holds the role, running or pending (wezfleet's own question,
    # lib/Master.ps1:118-137, answered by core/roles Get-HordeRoleHeld).
    $held = Get-HordeRoleHeld -Read $roleRead -Role "warchief" -Table $C.roleTable -Now $C.now
    if ($held.state -ne "known") { [void]$out.Add((New-HordeFault -Kind "no-warchief" -Found @() -UnknownReason $held.reason)) }
    elseif ($held.value -eq $false) { [void]$out.Add((New-HordeFault -Kind "no-warchief" -Found @((New-HordeFinding -Subjects @("warchief") -Detail "no session holds role warchief and no pending claim names it; nothing can distribute work or take the founder's own sessions")))) }
    else { [void]$out.Add((New-HordeFault -Kind "no-warchief" -Found @())) }

    # two-warchiefs: never chosen by time (YedPool/wezfleet lib/Hierarchy.ps1:83-87, 4eba288).
    $wc = Get-HordeRoleCount -Read $roleRead -Role "warchief" -Table $C.roleTable
    $warchiefs = @($roleRead.sessions | Where-Object { -not $_.retired -and $_.role.state -eq "known" -and $_.role.value -eq "warchief" } | ForEach-Object { $_.id } | Sort-Object)
    if ($wc.atLeast -ge 2) { [void]$out.Add((New-HordeFault -Kind "two-warchiefs" -Found @((New-HordeFinding -Subjects $warchiefs -Detail ("" + $warchiefs.Count + " live sessions hold role warchief; a person must choose, because picking by time eventually picks wrong silently"))))) }
    elseif ($wc.answer.state -eq "known") { [void]$out.Add((New-HordeFault -Kind "two-warchiefs" -Found @())) }
    else { [void]$out.Add((New-HordeFault -Kind "two-warchiefs" -Found @() -UnknownReason $wc.answer.reason)) }

    # orc-not-under-warchief: judged only when exactly one warchief is known (lib/Hierarchy.ps1:89-98).
    if ($wc.answer.state -eq "known" -and $wc.answer.value -eq 1) {
        $wid = $warchiefs[0]
        $f = @()
        foreach ($rs in $roleRead.sessions) {
            if ($rs.retired -or $rs.role.state -ne "known" -or $rs.role.value -ne "orc") { continue }
            $p = Get-HordeStoredField -Record $C.wf.registry.records[$rs.id].record -Name "parent"
            if ($p.state -eq "known" -and "$($p.value)" -ine $wid) { $f += New-HordeFinding -Subjects @($rs.id, "$($p.value)") -Detail ("orc " + $rs.id + " reports to " + $p.value + ", not to the warchief " + $wid) }
        }
        [void]$out.Add((New-HordeFault -Kind "orc-not-under-warchief" -Found $f))
    } else {
        $why = "judged only when exactly one warchief is known"
        if ($wc.answer.state -eq "known") { $why = $why + "; there are " + $wc.answer.value } else { $why = $why + "; the count is unknown: " + $wc.answer.reason }
        [void]$out.Add((New-HordeFault -Kind "orc-not-under-warchief" -Found @() -UnknownReason $why))
    }

    # parent-missing and parent-retired: two faults wezfleet reported as one, because it dropped
    # retired records before the lookup (lib/Hierarchy.ps1:42-58; parity difference P-25).
    $missing = @(); $retiredParent = @()
    foreach ($r in $live) {
        $p = Get-HordeStoredField -Record $r.record -Name "parent"
        if ($p.state -ne "known") { continue }
        $pid0 = "$($p.value)"
        if (-not $C.wf.registry.records.ContainsKey($pid0)) {
            if (-not $C.wf.registry.unreadable.Contains($pid0)) { $missing += New-HordeFinding -Subjects @($r.id, $pid0) -Detail ("session " + $r.id + " names parent " + $pid0 + ", which has no registry record") }
            continue
        }
        $prt = Get-HordeField -Record $C.wf.registry.records[$pid0].record -Name "retired"
        if ($prt.state -eq "known" -and [bool]$prt.value) { $retiredParent += New-HordeFinding -Subjects @($r.id, $pid0) -Detail ("session " + $r.id + " reports to " + $pid0 + ", whose record is retired") }
    }
    [void]$out.Add((New-HordeFault -Kind "parent-missing" -Found $missing -UnknownReason $regIncomplete))
    [void]$out.Add((New-HordeFault -Kind "parent-retired" -Found $retiredParent -UnknownReason $regIncomplete))

    # parent-cycle: wezfleet refuses a cycle when it writes an edge (Set-WfSessionParent), and never
    # checks for one on read; records are edited by hand, so a reader does.
    $cycles = @(); $inCycle = @{}
    foreach ($r in $C.wf.registry.records.Values) {
        $seen = New-Object System.Collections.ArrayList
        $cur = $r.id
        while ($true) {
            if ($seen -contains $cur.ToLowerInvariant()) {
                $loop = @($seen[($seen.IndexOf($cur.ToLowerInvariant()))..($seen.Count - 1)])
                $key = (@($loop | Sort-Object) -join ",")
                if (-not $inCycle.ContainsKey($key)) { $inCycle[$key] = $true; $cycles += New-HordeFinding -Subjects $loop -Detail ("parent edges form a loop: " + ($loop -join " -> ")) }
                break
            }
            [void]$seen.Add($cur.ToLowerInvariant())
            if (-not $C.wf.registry.records.ContainsKey($cur)) { break }
            $p = Get-HordeStoredField -Record $C.wf.registry.records[$cur].record -Name "parent"
            if ($p.state -ne "known") { break }
            $cur = "$($p.value)"
        }
    }
    [void]$out.Add((New-HordeFault -Kind "parent-cycle" -Found $cycles -UnknownReason $regIncomplete))

    # conversation-in-two-processes: two control files for one session (core/identity duplicates),
    # and two processes whose command lines resume one id (YedPool/wezfleet lib/Common.ps1:684-708,
    # 0e1c75a: seven conversations ran in two instances with nothing noticing). BLIND SPOT, stated so
    # a clean answer is not over-read: a session started without --resume has no id on its command
    # line, so its second copy is visible only through the control files.
    $dupes = @()
    foreach ($d in @($C.identity.duplicates)) { $dupes += New-HordeFinding -Subjects @($d.sessionId) -Detail ("control files " + (@($d.sources | ForEach-Object { Split-Path -Leaf $_ }) -join ", ") + " all name session " + $d.sessionId) }
    $why5 = ""
    if ($C.processes.state -ne "known") { $why5 = "the process table could not be read (" + $C.processes.reason + ")" }
    else {
        $groups = @{}
        $noLines = 0
        foreach ($p in $C.processes.value.Values) {
            if (@("claude.exe", "claude") -notcontains "$($p.name)".ToLowerInvariant()) { continue }
            $cl = $p.PSObject.Properties["commandLine"]
            if ($null -eq $cl -or $null -eq $cl.Value) { $noLines++; continue }
            $m = [regex]::Match("$($cl.Value)", '(?:--resume|-r)(?:\s+|=)"?([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})')
            if (-not $m.Success) { continue }
            $k = $m.Groups[1].Value.ToLowerInvariant()
            if (-not $groups.ContainsKey($k)) { $groups[$k] = New-Object System.Collections.ArrayList }
            [void]$groups[$k].Add([int]$p.pid)
        }
        foreach ($k in $groups.Keys) { if ($groups[$k].Count -gt 1) { $dupes += New-HordeFinding -Subjects (@($k) + @($groups[$k] | Sort-Object | ForEach-Object { "pid " + $_ })) -Detail ("" + $groups[$k].Count + " processes resume session " + $k) } }
        if ($noLines -gt 0) { $why5 = "" + $noLines + " claude process(es) show no command line, so a second copy among them cannot be seen" }
        elseif ($C.identity.complete["claude"].state -ne "known") { $why5 = "the claude control listing is incomplete (" + $C.identity.complete["claude"].reason + ")" }
    }
    # Only claude processes' command lines are read, so a session of any other agent could run twice
    # unseen: while one exists, "no duplicate" is not known (review of PR #31, finding 9).
    $unread = @($C.identity.records.Values | Where-Object { $_.fields.agent.state -ne "known" -or "$($_.fields.agent.value)" -cne "claude" } | ForEach-Object { $_.sessionId } | Sort-Object)
    if ($why5 -eq "" -and $unread.Count -gt 0) { $why5 = "only claude processes' command lines are read, and " + $unread.Count + " session(s) of another agent are known (" + ($unread -join ", ") + "), and a second copy of one could not be seen" }
    [void]$out.Add((New-HordeFault -Kind "conversation-in-two-processes" -Found $dupes -UnknownReason $why5))

    # registry-hook-silent: running claude sessions exist and not one has a registry record - the
    # hook is not writing (YedPool/wezfleet e929318: one record while 19 panes were live; its own
    # rule, lib/Registry.ps1:987-1010, fires when every expected session lacks one).
    $vl = $C.identity.verifiedLive
    if ($vl.state -ne "known") { [void]$out.Add((New-HordeFault -Kind "registry-hook-silent" -Found @() -UnknownReason ("which sessions run is unknown: " + $vl.reason))) }
    else {
        $claudeLive = @($vl.value | Where-Object { $C.identity.records.ContainsKey($_) -and "$($C.identity.records[$_].fields.agent.value)" -ceq "claude" })
        $unrecorded = @($claudeLive | Where-Object { -not $C.wf.registry.records.ContainsKey($_) -and -not $C.wf.registry.unreadable.Contains($_) })
        if ($claudeLive.Count -gt 0 -and $unrecorded.Count -eq $claudeLive.Count) {
            if ($regIncomplete -ne "") { [void]$out.Add((New-HordeFault -Kind "registry-hook-silent" -Found @() -UnknownReason $regIncomplete)) }
            else { [void]$out.Add((New-HordeFault -Kind "registry-hook-silent" -Found @((New-HordeFinding -Subjects $unrecorded -Detail ("" + $claudeLive.Count + " claude sessions are running and none has a registry record; the registry hook is not writing"))))) }
        } else { [void]$out.Add((New-HordeFault -Kind "registry-hook-silent" -Found @())) }
    }

    # session-in-two-handles and pane-sessions-hijack come from the pane-sessions guard, plus the
    # registry and a guarded file disagreeing about one session's handle ("which is right is for the
    # shadow to measure", core/ownership.json pane provisional).
    $two = @($C.paneVerdicts.findings | Where-Object { $_.kind -eq "session-in-two-handles" } | ForEach-Object { New-HordeFinding -Subjects $_.subjects -Detail $_.detail })
    foreach ($S in $States) {
        if ($null -eq $S.x1 -or $S.fields["pane"].answer.state -ne "known" -or $null -eq $S.fields["pane"].source) { continue }
        if ($S.fields["pane"].source.store -eq "W1" -and "$($S.fields['pane'].answer.value)" -ne $S.x1.handle) { $two += New-HordeFinding -Subjects @($S.id, ("handle " + $S.fields["pane"].answer.value), ("handle " + $S.x1.handle)) -Detail ("the registry puts session " + $S.id + " in handle " + $S.fields["pane"].answer.value + " and its pane-sessions file in handle " + $S.x1.handle) }
    }
    $pvWhy = ""; if ($C.paneVerdicts.state.state -ne "known") { $pvWhy = $C.paneVerdicts.state.reason }
    [void]$out.Add((New-HordeFault -Kind "session-in-two-handles" -Found $two -UnknownReason $pvWhy))
    $hij = @($C.paneVerdicts.findings | Where-Object { $_.kind -eq "pane-sessions-hijack" } | ForEach-Object { New-HordeFinding -Subjects $_.subjects -Detail $_.detail })
    [void]$out.Add((New-HordeFault -Kind "pane-sessions-hijack" -Found $hij -UnknownReason $pvWhy))

    # handle-claimed-twice: decision 1 of 2026-09-30.
    $hc = @()
    foreach ($h in @($Claimed.Keys | Sort-Object)) { $hc += New-HordeFinding -Subjects (@("handle " + $h) + @($Claimed[$h])) -Detail ("handle " + $h + " is claimed by " + @($Claimed[$h]).Count + " sessions (" + (@($Claimed[$h]) -join ", ") + "); every claimant's pane is unknown") }
    $hcWhy = ""; if ($C.host.verify.state -ne "known") { $hcWhy = $C.host.verify.reason }
    [void]$out.Add((New-HordeFault -Kind "handle-claimed-twice" -Found $hc -UnknownReason $hcWhy))

    # run-ambiguous: a session whose fleet id is in two open runs that spawned it, several open runs
    # none of which did, or several closed ones.
    $amb = @()
    foreach ($S in $States) { if (@($S.runAmbiguous).Count -gt 1) { $amb += New-HordeFinding -Subjects (@($S.id) + @($S.runAmbiguous)) -Detail $S.fields["runId"].answer.reason } }
    $runWhy = @(@($C.wf.runs.runsComplete, $C.wf.runs.rostersComplete) | Where-Object { $_.state -ne "known" } | ForEach-Object { $_.reason })
    [void]$out.Add((New-HordeFault -Kind "run-ambiguous" -Found $amb -UnknownReason ($runWhy -join "; ")))

    # warchief-claim-pending: a spawned warchief not yet seen, which wezfleet's master ensure counts
    # as a master (lib/Master.ps1:118-137); reported apart from the running count (core-roles L-023).
    $pc = Get-HordeRoleClaimCount -Read $roleRead -Role "warchief" -Table $C.roleTable -Now $C.now
    $pend = @($roleRead.claims | Where-Object { $_.role.state -eq "known" -and $_.role.value -eq "warchief" -and (Test-HordeClaimPending -Claim $_ -Now $C.now) } | ForEach-Object { "handle " + $_.pane })
    if ($pc.atLeast -gt 0) { [void]$out.Add((New-HordeFault -Kind "warchief-claim-pending" -Found @((New-HordeFinding -Subjects $pend -Detail ("" + $pc.atLeast + " pending spawn claim(s) name role warchief")))) ) }
    elseif ($pc.answer.state -eq "known") { [void]$out.Add((New-HordeFault -Kind "warchief-claim-pending" -Found @())) }
    else { [void]$out.Add((New-HordeFault -Kind "warchief-claim-pending" -Found @() -UnknownReason $pc.answer.reason)) }

    # running-but-retired: a process-verified session whose record is a tombstone (live 2026-09-30:
    # one, whose lastSeen the hook was still advancing a week after it was retired).
    $rbr = @()
    foreach ($S in $States) { if ($null -ne $S.rec -and "$($S.rec.processCheck)" -ceq "verified" -and $S.w1Retired) { $rbr += New-HordeFinding -Subjects @($S.id) -Detail ("session " + $S.id + " is running, and its registry record is retired") } }
    $rbrWhy = ""; if ($C.identity.verifiedLive.state -ne "known") { $rbrWhy = "which sessions run is unknown: " + $C.identity.verifiedLive.reason }
    [void]$out.Add((New-HordeFault -Kind "running-but-retired" -Found $rbr -UnknownReason $rbrWhy))

    # orphan-process: a claude process no control file verifies (core/identity).
    $op = $C.identity.orphanProcesses
    if ($op.state -eq "known") { [void]$out.Add((New-HordeFault -Kind "orphan-process" -Found @(@($op.value) | ForEach-Object { New-HordeFinding -Subjects @("pid " + $_) -Detail ("claude process " + $_ + " is running and no control file verifies it") }))) }
    else { [void]$out.Add((New-HordeFault -Kind "orphan-process" -Found @() -UnknownReason $op.reason)) }

    # fleet-id-on-two-records and label-held-twice, over the live records.
    $fg = @{}; $lg = @{}
    foreach ($r in $live) {
        $f = Get-HordeStoredField -Record $r.record -Name "fleetSessionId"
        if ($f.state -eq "known") { $k = "$($f.value)"; if (-not $fg.ContainsKey($k)) { $fg[$k] = New-Object System.Collections.ArrayList }; [void]$fg[$k].Add($r.id) }
        $l = Get-HordeStoredField -Record $r.record -Name "label"
        if ($l.state -eq "known") {
            $cy = Get-HordeField -Record $r.record -Name "labelCycle"
            $cyc = "0"; if ($cy.state -eq "known") { $cyc = "$($cy.value)" }
            $k = "$($l.value)" + " cycle " + $cyc
            if (-not $lg.ContainsKey($k)) { $lg[$k] = New-Object System.Collections.ArrayList }; [void]$lg[$k].Add($r.id)
        }
    }
    $ff = @(); foreach ($k in @($fg.Keys | Sort-Object)) { if ($fg[$k].Count -gt 1) { $ff += New-HordeFinding -Subjects @($fg[$k] | Sort-Object) -Detail ("fleet id " + $k + " is on " + $fg[$k].Count + " live records") } }
    [void]$out.Add((New-HordeFault -Kind "fleet-id-on-two-records" -Found $ff -UnknownReason $regIncomplete))
    $lf = @(); foreach ($k in @($lg.Keys | Sort-Object)) { if ($lg[$k].Count -gt 1) { $lf += New-HordeFinding -Subjects @($lg[$k] | Sort-Object) -Detail ("label " + $k + " is held by " + $lg[$k].Count + " live records") } }
    [void]$out.Add((New-HordeFault -Kind "label-held-twice" -Found $lf -UnknownReason $regIncomplete))

    # roster-entry-twice: a roster or run manifest that lists one fleet id twice. The run resolver
    # chooses neither entry (review of PR #31, finding 8); this says which run and which id.
    $twice = @()
    foreach ($run in @($C.wf.runs.runs)) {
        foreach ($g in @($run.entries | Group-Object -Property id -CaseSensitive | Where-Object { $_.Count -gt 1 })) { $twice += New-HordeFinding -Subjects @($g.Name, $run.runId) -Detail ("the roster of run " + $run.runId + " lists fleet id " + $g.Name + " " + $g.Count + " times") }
        if ($null -ne $run.manifest -and $null -ne $run.manifest.PSObject.Properties["sessions"]) {
            $mids = @(@($run.manifest.sessions) | Where-Object { $null -ne $_ -and $null -ne $_.PSObject.Properties["id"] } | ForEach-Object { "$($_.id)" })
            foreach ($g in @($mids | Group-Object -CaseSensitive | Where-Object { $_.Count -gt 1 })) { $twice += New-HordeFinding -Subjects @($g.Name, $run.runId) -Detail ("the manifest of run " + $run.runId + " lists fleet id " + $g.Name + " " + $g.Count + " times") }
        }
    }
    $twWhy = @(@($C.wf.runs.runsComplete, $C.wf.runs.rostersComplete) | Where-Object { $_.state -ne "known" } | ForEach-Object { $_.reason })
    [void]$out.Add((New-HordeFault -Kind "roster-entry-twice" -Found $twice -UnknownReason ($twWhy -join "; ")))

    # session-id-not-uuid: keyed, because identity accepts it, and flagged, because the stored record
    # refuses it (schema/session-record.v1 sessionId).
    $nu = @(); foreach ($S in $States) { if ($S.id -cnotmatch $script:HordeUuidPattern) { $nu += New-HordeFinding -Subjects @($S.id) -Detail ("session id " + $S.id + " is not a UUID; the view keys it, and the engine's stored record would refuse it") } }
    [void]$out.Add((New-HordeFault -Kind "session-id-not-uuid" -Found $nu))
    return $out.ToArray()
}
