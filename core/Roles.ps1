# core/roles - Horde's role names, and wezfleet's, read through one alias table.
#
# Horde speaks warchief, orc and goblin. wezfleet stored master, orchestrator and session. The
# translation happens ON READ, and Horde never writes a wezfleet file: wezfleet's record writer lost
# the role field three times (b9c9122, f37dee4 with 91e63df, 17c5d42 - see
# planning/ledger/core-roles.md), and a rename that rewrote records would have exercised that writer
# on every one of them. Reading is the one path that cannot lose a role.
#
# A ROLE THAT IS NOT THERE IS UNKNOWN, NEVER GOBLIN. On the live store 13 of 31 records have no role
# key, and in every case where a missing role mattered the session was really a master or an
# orchestrator. Defaulting to the humblest role would have mislabelled exactly those.
#
# MATCHING AGREES WITH WEZFLEET, so a shadow run beside it cannot disagree over spelling: case is
# ignored (every wezfleet comparison uses -eq or -contains, which ignore case), and padding is NOT
# trimmed (wezfleet never trims, so " master" is not a master to it either).
#
# The table is data (core\roles.json), so a further vocabulary is a row, not code.

Set-StrictMode -Off
. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "ReadShared.ps1")

function Get-HordeRoleTable {
    # { native = string[]; aliases = hashtable, keys lowercase } from core\roles.json.
    param([string]$Path = (Join-Path $PSScriptRoot "roles.json"))
    $j = (Read-HordeSharedText -Path $Path) | ConvertFrom-Json
    $aliases = @{}
    foreach ($p in $j.aliases.PSObject.Properties) { $aliases[$p.Name.ToLowerInvariant()] = "$($p.Value)" }
    return [pscustomobject]@{ native = @($j.native | ForEach-Object { "$_".ToLowerInvariant() }); aliases = $aliases }
}

function Resolve-HordeRole {
    # One stored role value, translated. Returns { role; raw; field }:
    #   role   a Horde answer - known (warchief, orc or goblin) or unknown with the reason
    #   raw    exactly what was stored, so a caller can always see what the mapping started from
    #   field  "missing", "empty" or "present" - absent and empty are different facts, and wezfleet
    #          reads both as the same thing
    param([switch]$Missing, $Raw = $null, $Table = $null)
    if ($null -eq $Table) { $Table = Get-HordeRoleTable }
    if ($Missing -or $null -eq $Raw) {
        return [pscustomobject]@{ role = (New-HordeUnknown -Reason "the record has no role"); raw = $null; field = "missing" }
    }
    $text = "$Raw"
    if ($text -eq "") {
        return [pscustomobject]@{ role = (New-HordeUnknown -Reason "the record's role is empty"); raw = $text; field = "empty" }
    }
    $key = $text.ToLowerInvariant()
    if ($Table.native -contains $key) { return [pscustomobject]@{ role = (New-HordeKnown -Value $key); raw = $text; field = "present" } }
    if ($Table.aliases.ContainsKey($key)) { return [pscustomobject]@{ role = (New-HordeKnown -Value $Table.aliases[$key]); raw = $text; field = "present" } }
    return [pscustomobject]@{ role = (New-HordeUnknown -Reason ("the stored role '" + $text + "' is not one Horde knows")); raw = $text; field = "present" }
}

function Read-HordeRecordRole {
    # The role of one parsed record. Only the role field is consulted: never the label, even though
    # wezfleet's labels M, A and A7 look like roles.
    param($Record, $Table = $null)
    $prop = $null
    if ($null -ne $Record) { $prop = $Record.PSObject.Properties["role"] }
    if ($null -eq $prop) { return (Resolve-HordeRole -Missing -Table $Table) }
    return (Resolve-HordeRole -Raw $prop.Value -Table $Table)
}

function Get-HordeWezfleetRoot {
    # Where wezfleet keeps its store: WEZFLEET_ROOT when set, else Documents\Code\.wezfleet under the
    # user profile (YedPool/wezfleet lib/Common.ps1:13-17). Not %USERPROFILE%\.wezfleet.
    if ("$env:WEZFLEET_ROOT".Trim() -ne "") { return $env:WEZFLEET_ROOT }
    return (Join-Path $env:USERPROFILE "Documents\Code\.wezfleet")
}

function Read-HordeWezfleetRoles {
    # Every role wezfleet holds - session records and pending spawn claims - read, never written.
    # Returns { sessions; claims; unreadable; complete }, where complete is an answer: known when
    # every record could be read, unknown when any could not. wezfleet's own reader skips an
    # unreadable record silently, which can make it report "no master" when there is one.
    param([string]$Root = (Get-HordeWezfleetRoot), $Table = $null)
    if ($null -eq $Table) { $Table = Get-HordeRoleTable }
    $sessions = New-Object System.Collections.ArrayList
    $claims = New-Object System.Collections.ArrayList
    $unreadable = New-Object System.Collections.ArrayList

    $sessDir = Join-Path $Root "registry\sessions"
    if (Test-Path -LiteralPath $sessDir) {
        # Only <id>.json whose claudeSessionId is that id is a record. A writer's temp file
        # (<id>.<pid>.<guid>.tmp) sits beside the records mid-write and is not one.
        foreach ($f in @(Get-ChildItem -LiteralPath $sessDir -File | Where-Object { $_.Extension -eq ".json" })) {
            $rec = $null
            try { $rec = (Read-HordeSharedText -Path $f.FullName) | ConvertFrom-Json } catch { [void]$unreadable.Add($f.FullName); continue }
            if ($null -eq $rec) { [void]$unreadable.Add($f.FullName); continue }
            $id = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            if ("$($rec.claudeSessionId)" -ne $id) { continue }
            $r = Read-HordeRecordRole -Record $rec -Table $Table
            [void]$sessions.Add([pscustomobject]@{ id = $id; retired = [bool]$rec.retired; role = $r.role; raw = $r.raw; field = $r.field })
        }
    }
    $claimDir = Join-Path $Root "registry\claims"
    if (Test-Path -LiteralPath $claimDir) {
        foreach ($f in @(Get-ChildItem -LiteralPath $claimDir -File | Where-Object { $_.Extension -eq ".json" })) {
            $c = $null
            try { $c = (Read-HordeSharedText -Path $f.FullName) | ConvertFrom-Json } catch { [void]$unreadable.Add($f.FullName); continue }
            if ($null -eq $c) { [void]$unreadable.Add($f.FullName); continue }
            $r = Read-HordeRecordRole -Record $c -Table $Table
            [void]$claims.Add([pscustomobject]@{ pane = [System.IO.Path]::GetFileNameWithoutExtension($f.Name); role = $r.role; raw = $r.raw; field = $r.field })
        }
    }
    $complete = New-HordeKnown -Value $true
    if ($unreadable.Count -gt 0) { $complete = New-HordeUnknown -Reason ("" + $unreadable.Count + " record(s) could not be read") }
    return [pscustomobject]@{ sessions = @($sessions); claims = @($claims); unreadable = @($unreadable); complete = $complete }
}

function Get-HordeRoleCount {
    # How many live (not retired) sessions hold a role, as an answer. Unknown when any record could
    # not be read - a count taken over a store with a hole in it is not a count.
    #
    # Unknown too when any LIVE session's role is unknown, naming those sessions. Such a session may
    # hold the very role being counted: every roleless record that mattered in wezfleet was a lost
    # master or orchestrator (ledger L-003). One master plus one live roleless session used to count
    # as "warchief known 1" (review, 2026-09-29). A retired session's role does not matter to a live
    # count, so it is not consulted.
    param($Read, [Parameter(Mandatory = $true)][string]$Role)
    if ($Read.complete.state -ne "known") { return (New-HordeUnknown -Reason ("cannot count: " + $Read.complete.reason)) }
    $unsure = @($Read.sessions | Where-Object { -not $_.retired -and $_.role.state -ne "known" } | ForEach-Object { $_.id })
    if ($unsure.Count -gt 0) {
        return (New-HordeUnknown -Reason ("cannot count: the role of " + $unsure.Count + " live session(s) is unknown (" + ($unsure -join ", ") + ")"))
    }
    $n = @($Read.sessions | Where-Object { -not $_.retired -and $_.role.state -eq "known" -and $_.role.value -eq $Role }).Count
    return (New-HordeKnown -Value $n)
}
