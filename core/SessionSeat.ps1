# core/SessionSeat.ps1 - where the session that holds a role sits: its pane, in which terminal.
#
# WHY (decisions window attach design, 2026-10-06). A Horde window is to stand beside the terminal
# window of the session that keeps the list of questions, and it must find that window from the
# fleet's own record of who holds the role - never by looking for a window whose title says so. This
# file answers the first step: which session's record names the role, and what that record says of
# where the session runs. What a pane or a terminal IS belongs to the terminal's adapter; here they
# are two pieces of text, handed on unread.
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

function Get-HordeRoleSeat {
    # The seat of -Role (a Horde role: warchief, orc or goblin) as an answer: known { sessionId; pane;
    # instance }, absent, or unknown with the reason (header). -Root is the registry's folder, for a
    # caller that names the one it made.
    param([Parameter(Mandatory = $true)][string]$Role, [string]$Root = (Get-HordeWezfleetRoot), $Table = $null)
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
    $one = $holders[0]
    $seat = [ordered]@{ sessionId = $one.id }
    foreach ($name in @("pane", "instance")) {
        $field = Get-HordeField -Record $one.record -Name $name
        $text = ""
        if ($field.state -ceq "known" -and ($field.value -is [string] -or $field.value -is [int] -or $field.value -is [long])) { $text = ("" + $field.value).Trim() }
        if ($text -eq "") { return (New-HordeUnknown -Reason ("the " + $Role + "'s record (" + $one.id + ") does not say which " + $(if ($name -ceq "pane") { "pane" } else { "terminal" }) + " it runs in")) }
        $seat[$name] = $text
    }
    return (New-HordeKnown -Value ([pscustomobject]$seat))
}
