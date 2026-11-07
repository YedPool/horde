# core/SessionSeat.ps1 - where the session that holds a role sits: its pane, in which terminal.
#
# WHY (window attach design, 2026-10-06). A companion window is to stand beside the terminal window of
# the session that holds a role, and it must find that window from the fleet's own record of who holds
# the role - never by looking for a window whose title says so. This file answers the first step:
# which session's record names the role, and what that record says of where the session runs. What a
# pane or a terminal IS belongs to the terminal's adapter; here they are two pieces of text, handed
# on unread.
#
# WHERE THE RECORD IS TODAY: the registry of the fleet being replaced, one file per session
# (core/WezfleetState.ps1, store W1), whose role words core/Roles.ps1 translates. When Horde keeps its
# own session records this file reads those instead, and its callers do not change.
#
# THE SEAT OF A ROLE IS THE ONE LIVE SESSION WHOSE RECORD NAMES IT.
#   - none names it: absent.
#   - two or more name it: unknown. One is never chosen over another by its age or by anything else
#     (the old fleet's own rule for two masters, YedPool/wezfleet lib/Hierarchy.ps1:83-87).
#   - a record that could not be read: unknown, because the unread one may name the role too.
#   - the one record gives no pane, or no terminal: unknown.
#
# AND THE SEAT IS TRUSTED ONLY WHILE THE SESSION IS STILL THERE (review of 2026-10-06, finding C5). A
# record outlives its session: one that ended without being retired, in a terminal still running,
# points at whatever is in that pane now. Three things must hold, each read with the repository's own
# readers and none of them new:
#   1. THE SESSION IS RUNNING. core/Identity.ps1 reads each agent's own control files and checks the
#      process behind each (its pid, and that the pid's start time is the one the file names). The
#      holder's session must be one whose process is verified. Gone, a pid now another process's, a
#      process table that could not be read, two files naming the session, an agent whose process
#      cannot be checked: unknown, with the reader's own reason.
#   2. THE RECORD IS THIS RUN'S. A session started again keeps its id, and until the new run first
#      writes the record it says where the earlier run sat. So the record's lastSeen must not be
#      earlier than the start of the session's present process (the rule the read model applies to
#      every stored handle, core/Projection.ps1 Test-HordeWrittenInInstance, there against the
#      terminal's start). No lastSeen, or one that is not a placeable time: unknown.
#   3. NO OTHER RUNNING SESSION'S RECORD NAMES THE SAME PANE OF THE SAME TERMINAL. A pane holds one
#      session; when two running sessions' records name it, neither is believed. A record of a session
#      that is not verified running is not counted: it is the stale kind this whole check is about.
# A session cannot move to another pane while its process lives, so these three are the proof that the
# pane still holds it. That the pane itself still exists is the terminal adapter's to say, from its own
# listing (core/HostWindow.ps1).
#
# WHY NOT THE PER-PANE FILE (schema/pane-session.v1, core/PaneSessions.ps1), which also ties a pane to
# a session. Measured 2026-10-07 on the measuring machine, read-only: of 151 such files 86 are refused
# by that reader today (they are written at the end of a turn now, with hook_event_name "Stop" and no
# source, which the schema of 2026-09-29 did not describe, and does since T-0433), the role holder's own among them; 22 of
# the 39 live records had no usable file. A check built on it would answer unknown for the real holder.
# The file also names no terminal (the schema says so), and is the store the old fleet's own reader
# could not rely on with more than one terminal open (core/Identity.ps1, Get-HordeSelfSessionId). On
# the same machine the three rules above held for the real holder: 29 of 29 control files verified,
# one live record for its pane and terminal, its record written after its process started; the
# process table took 249 ms to read and the control files 300 ms.
#
# THIS IS NOT core/Roles.ps1's COUNT, and differs from it on purpose. A count answers "how many hold
# the role", and a live session with no role at all makes it unknown, because that session may be a
# holder whose role was lost (measured 2026-10-06 on the measuring machine: 1 live record naming the
# role, 29 live records naming none, so the count is "at least 1, unknown"). A seat answers "where
# does the session that SAYS it holds the role sit". A record that names no role cannot be that
# session, so it does not make the seat unknown; a second record that names the role does.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced.

. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "Roles.ps1")
. (Join-Path $PSScriptRoot "WezfleetState.ps1")
. (Join-Path $PSScriptRoot "Identity.ps1")
# For ConvertFrom-HordeIsoTime: one definition of how a stored time is read, zone and all.
. (Join-Path $PSScriptRoot "Projection.ps1")

function Get-HordeSeatProcessStart {
    # When the present process of session -SessionId started, as an answer: known [datetime] (UTC) only
    # for a session the identity reading verifies as running; unknown, with that reader's reason,
    # otherwise (header, rule 1). -Identity is what Get-HordeIdentity returned.
    param([Parameter(Mandatory = $true)]$Identity, [Parameter(Mandatory = $true)][string]$SessionId)
    if (-not $Identity.records.ContainsKey($SessionId)) {
        # No record: either nothing names the session, or the reading could not be whole (a file that
        # could not be read, a session named by two files) and says so itself.
        if ($Identity.verifiedLive.state -cne "known") { return (New-HordeUnknown -Reason $Identity.verifiedLive.reason) }
        return (New-HordeUnknown -Reason "no running session's control file names it")
    }
    $record = $Identity.records[$SessionId]
    $started = $record.fields["procStart"]
    # The reader makes procStart known only for a verified process, and says why it is not.
    if ("$($record.processCheck)" -cne "verified" -or $started.state -cne "known") { return (New-HordeUnknown -Reason $(if ($started.state -ceq "unknown") { $started.reason } else { "its process could not be checked (" + $record.processCheck + ")" })) }
    return (New-HordeKnown -Value ([DateTime]::FromFileTimeUtc([long]$started.value)))
}

function Get-HordeRoleSeat {
    # The seat of -Role (a Horde role: warchief, orc or warg) as an answer: known { sessionId; pane;
    # instance }, absent, or unknown with the reason (header). -Root is the registry's folder, for a
    # caller that names the one it made; -Identity is a reading of who is running (Get-HordeIdentity),
    # for a caller that has one or a test that made one, and is read here when it is not given.
    param([Parameter(Mandatory = $true)][string]$Role, [string]$Root = (Get-HordeWezfleetRoot), $Table = $null, $Identity = $null)
    if ($null -eq $Table) { $Table = Get-HordeRoleTable }
    if ($Table.native -cnotcontains $Role) { throw ("'" + $Role + "' is not a role; the roles are: " + ($Table.native -join ", ")) }
    $registry = Read-HordeRegistry -Root $Root
    if ($registry.complete.state -cne "known") {
        return (New-HordeUnknown -Reason ("the session records could not all be read, so which session is the " + $Role + " cannot be told: " + $registry.complete.reason))
    }
    $holders = New-Object System.Collections.ArrayList
    foreach ($id in @($registry.records.Keys | Sort-Object)) {
        $record = $registry.records[$id].record
        # Retired is read as the old fleet reads it, by truthiness: a record with no such field is live.
        $retired = Get-HordeField -Record $record -Name "retired"
        if ($retired.state -ceq "known" -and [bool]$retired.value) { continue }
        # Named $named, not $role: variable names ignore case, so that would be the parameter itself
        # (CONTRIBUTING 12; measured here 2026-10-06 - the parameter became the first record's answer, no
        # record's role equalled it, and a registry with a holder answered absent).
        $named = (Read-HordeRecordRole -Record $record -Table $Table).role
        if ($named.state -ceq "known" -and "$($named.value)" -ceq $Role) { [void]$holders.Add([pscustomobject]@{ id = "$id"; record = $record }) }
    }
    if ($holders.Count -eq 0) { return (New-HordeAbsent -Note ("no live session's record names the role " + $Role)) }
    if ($holders.Count -gt 1) {
        return (New-HordeUnknown -Reason ("" + $holders.Count + " live sessions each say they are the " + $Role + " (" + (@($holders | ForEach-Object { $_.id }) -join ", ") + "); one is never chosen over another"))
    }
    return (Confirm-HordeSeatHolder -Holder $holders[0] -Registry $registry -Identity $Identity -What ("the " + $Role))
}

function Confirm-HordeSeatHolder {
    # The seat of the ONE live record that names a role or a label, as an answer (the header): its pane
    # and terminal, and STILL THERE - the session is running, the record is this run's, and no other
    # running session's record names the pane. -Holder is { id; record }; -What names the seat in a
    # reason ("the warchief", "orc C"). One function for both, so a seat found by its label is held to
    # exactly the checks a seat found by its role is.
    param([Parameter(Mandatory = $true)]$Holder, [Parameter(Mandatory = $true)]$Registry, $Identity = $null, [Parameter(Mandatory = $true)][string]$What)
    $one = $Holder
    $registry = $Registry
    $seat = [ordered]@{ sessionId = $one.id }
    foreach ($name in @("pane", "instance")) {
        $field = Get-HordeField -Record $one.record -Name $name
        $text = ""
        if ($field.state -ceq "known" -and ($field.value -is [string] -or $field.value -is [int] -or $field.value -is [long])) { $text = ("" + $field.value).Trim() }
        if ($text -eq "") { return (New-HordeUnknown -Reason ($What + "'s record (" + $one.id + ") does not say which " + $(if ($name -ceq "pane") { "pane" } else { "terminal" }) + " it runs in")) }
        $seat[$name] = $text
    }
    # STILL THERE (header): the session is running, the record is this run's, and no other running
    # session's record names the pane.
    if ($null -eq $Identity) { $Identity = Get-HordeIdentity }
    $running = Get-HordeSeatProcessStart -Identity $Identity -SessionId $one.id
    if ($running.state -cne "known") { return (New-HordeUnknown -Reason ($What + "'s session (" + $one.id + ") is not proven to be running, so the pane its record names may hold something else now: " + $running.reason)) }
    $written = ConvertFrom-HordeIsoTime (Get-HordeField -Record $one.record -Name "lastSeen").value
    if ($null -eq $written) { return (New-HordeUnknown -Reason ($What + "'s record (" + $one.id + ") does not say when it was last written, so it cannot be told from a record of an earlier run of the session")) }
    if ($written -lt $running.value) { return (New-HordeUnknown -Reason ($What + "'s record (" + $one.id + ") was last written " + (ConvertTo-HordeIsoText $written) + ", before the session's present process started " + (ConvertTo-HordeIsoText $running.value) + ", so it says where an earlier run of the session sat")) }
    $sharing = New-Object System.Collections.ArrayList
    foreach ($id in @($registry.records.Keys | Sort-Object)) {
        $other = $registry.records[$id].record
        $left = Get-HordeField -Record $other -Name "retired"
        if ($left.state -ceq "known" -and [bool]$left.value) { continue }
        if ("$((Get-HordeField -Record $other -Name 'pane').value)".Trim() -cne $seat["pane"] -or "$((Get-HordeField -Record $other -Name 'instance').value)".Trim() -cne $seat["instance"]) { continue }
        if ("$id" -ieq $one.id -or (Get-HordeSeatProcessStart -Identity $Identity -SessionId "$id").state -ceq "known") { [void]$sharing.Add("$id") }
    }
    if ($sharing.Count -gt 1) { return (New-HordeUnknown -Reason ("" + $sharing.Count + " running sessions' records name pane " + $seat["pane"] + " of that terminal (" + ($sharing -join ", ") + "), so which of them it holds now cannot be told")) }
    return (New-HordeKnown -Value ([pscustomobject]$seat))
}

function Get-HordeLabelSeat {
    # The seat of the session whose record wears fleet label -Label AND names role -Role (an Orc's lane
    # letter and orc), as an answer: known { sessionId; pane; instance }, absent, or unknown with the
    # reason. The registry's own two fields, read as the role seat reads them, never a guess: the label is
    # compared exactly as stored (an Orc's is "C"), and a record whose role cannot be read is not that
    # Orc's. Two live records that both wear the label and the role are unknown, one never chosen over
    # the other; the one found is held to the same STILL THERE checks (Confirm-HordeSeatHolder). -Root,
    # -Table and -Identity as for Get-HordeRoleSeat.
    param([Parameter(Mandatory = $true)][string]$Label, [Parameter(Mandatory = $true)][string]$Role, [string]$Root = (Get-HordeWezfleetRoot), $Table = $null, $Identity = $null)
    if ($null -eq $Table) { $Table = Get-HordeRoleTable }
    if (@($Table.native) -cnotcontains $Role) { throw ("'" + $Role + "' is not a role; the roles are: " + ($Table.native -join ", ")) }
    $what = $Role + " " + $Label
    $records = Read-HordeRegistry -Root $Root
    if ("$($records.complete.state)" -cne "known") {
        return (New-HordeUnknown -Reason ("the session records could not all be read, so which session is " + $what + " cannot be told: " + $records.complete.reason))
    }
    $wearers = New-Object System.Collections.ArrayList
    foreach ($id in @($records.records.Keys | Sort-Object)) {
        $entry = $records.records[$id].record
        $gone = Get-HordeField -Record $entry -Name "retired"
        if ($gone.state -ceq "known" -and [bool]$gone.value) { continue }
        $worn = Get-HordeField -Record $entry -Name "label"
        if ($worn.state -cne "known" -or $worn.value -isnot [string] -or $worn.value -cne $Label) { continue }
        $held = (Read-HordeRecordRole -Record $entry -Table $Table).role
        if ($held.state -cne "known" -or "$($held.value)" -cne $Role) { continue }
        [void]$wearers.Add([pscustomobject]@{ id = "$id"; record = $entry })
    }
    if ($wearers.Count -eq 0) { return (New-HordeAbsent -Note ("no live session's record wears the label " + $Label + " with the role " + $Role)) }
    if ($wearers.Count -ne 1) {
        return (New-HordeUnknown -Reason ("" + $wearers.Count + " live sessions each wear the label " + $Label + " with the role " + $Role + " (" + (@($wearers | ForEach-Object { $_.id }) -join ", ") + "); one is never chosen over another"))
    }
    return (Confirm-HordeSeatHolder -Holder $wearers[0] -Registry $records -Identity $Identity -What $what)
}
