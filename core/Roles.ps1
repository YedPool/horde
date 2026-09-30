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
    #
    # The field is looked up by core/tristate's Get-HordeField, which reads hashtables as well as
    # parsed JSON. A lookup of its own read @{ role = "master" } as having no role (review, 2026-09-29).
    param($Record, $Table = $null)
    $field = Get-HordeField -Record $Record -Name "role"
    if ($field.state -ne "known") { return (Resolve-HordeRole -Missing -Table $Table) }
    return (Resolve-HordeRole -Raw $field.value -Table $Table)
}

function Get-HordeWezfleetRoot {
    # Where wezfleet keeps its store: WEZFLEET_ROOT when set, else Documents\Code\.wezfleet under the
    # user profile (YedPool/wezfleet lib/Common.ps1:13-17). Not %USERPROFILE%\.wezfleet.
    # "Set" means exactly what wezfleet's `if ($env:WEZFLEET_ROOT)` means: non-empty, NOT trimmed. A
    # value of only spaces is used as it stands, so both read the same store, even a wrong one.
    if ("$env:WEZFLEET_ROOT" -ne "") { return $env:WEZFLEET_ROOT }
    return (Join-Path $env:USERPROFILE "Documents\Code\.wezfleet")
}

function Read-HordeWezfleetRoles {
    # Every role wezfleet holds - session records and pending spawn claims - read, never written.
    # Returns { sessions; claims; unreadable; complete }, where complete is an answer: known when
    # the sessions directory was there and listed and every record could be read, unknown with every
    # reason otherwise. wezfleet's own reader skips an
    # unreadable record silently, which can make it report "no master" when there is one.
    param([string]$Root = (Get-HordeWezfleetRoot), $Table = $null)
    if ($null -eq $Table) { $Table = Get-HordeRoleTable }
    $sessions = New-Object System.Collections.ArrayList
    $claims = New-Object System.Collections.ArrayList
    $unreadable = New-Object System.Collections.ArrayList

    # Problems that leave the read incomplete, beyond single unreadable records.
    $gaps = New-Object System.Collections.ArrayList

    # A MISSING SESSIONS DIRECTORY IS NOT AN EMPTY FLEET. wezfleet creates it with its first record, so
    # its absence says the root is wrong (a mistyped WEZFLEET_ROOT), not that nothing runs - and it
    # used to read as complete, with every count a known 0 (review, 2026-09-29).
    # AN UNLISTABLE ONE IS NOT EMPTY EITHER. Listed without -ErrorAction Stop, a directory that
    # cannot be read gives 0 files and a non-terminating error; measured with a junction whose
    # target is gone. So the listing stops on error, inside try, and a failure is a gap.
    $sessDir = Join-Path $Root "registry\sessions"
    $sessFiles = @()
    if (-not (Test-Path -LiteralPath $sessDir -PathType Container)) {
        [void]$gaps.Add("there is no sessions directory at " + $sessDir)
    } else {
        try { $sessFiles = @(Get-ChildItem -LiteralPath $sessDir -File -ErrorAction Stop | Where-Object { $_.Extension -eq ".json" }) }
        catch { [void]$gaps.Add("the sessions directory could not be listed: " + $_.Exception.Message) }
    }
    if ($sessFiles.Count -gt 0) {
        # Only <id>.json whose claudeSessionId is that id is a record. A writer's temp file
        # (<id>.<pid>.<guid>.tmp) sits beside the records mid-write and is not one.
        foreach ($f in $sessFiles) {
            $rec = $null
            try { $rec = (Read-HordeSharedText -Path $f.FullName) | ConvertFrom-Json } catch { [void]$unreadable.Add($f.FullName); continue }
            if ($null -eq $rec) { [void]$unreadable.Add($f.FullName); continue }
            $id = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            if ("$($rec.claudeSessionId)" -ne $id) { continue }
            $r = Read-HordeRecordRole -Record $rec -Table $Table
            [void]$sessions.Add([pscustomobject]@{ id = $id; retired = [bool]$rec.retired; role = $r.role; raw = $r.raw; field = $r.field })
        }
    }
    # A missing claims directory IS legitimately empty: wezfleet creates it only when it first
    # spawns with a claim (lib/Registry.ps1 Get-WfClaimDir -Create). One that cannot be listed is not.
    $claimDir = Join-Path $Root "registry\claims"
    $claimFiles = @()
    if (Test-Path -LiteralPath $claimDir) {
        try { $claimFiles = @(Get-ChildItem -LiteralPath $claimDir -File -ErrorAction Stop | Where-Object { $_.Extension -eq ".json" }) }
        catch { [void]$gaps.Add("the claims directory could not be listed: " + $_.Exception.Message) }
    }
    if ($claimFiles.Count -gt 0) {
        foreach ($f in $claimFiles) {
            $c = $null
            try { $c = (Read-HordeSharedText -Path $f.FullName) | ConvertFrom-Json } catch { [void]$unreadable.Add($f.FullName); continue }
            if ($null -eq $c) { [void]$unreadable.Add($f.FullName); continue }
            $r = Read-HordeRecordRole -Record $c -Table $Table
            $spawned = $null
            $spProp = $c.PSObject.Properties["spawnedAt"]
            if ($null -ne $spProp) { $spawned = $spProp.Value }
            [void]$claims.Add([pscustomobject]@{ pane = [System.IO.Path]::GetFileNameWithoutExtension($f.Name); role = $r.role; raw = $r.raw; field = $r.field; spawnedAt = $spawned })
        }
    }
    if ($unreadable.Count -gt 0) { [void]$gaps.Add("" + $unreadable.Count + " record(s) could not be read") }
    $complete = New-HordeKnown -Value $true
    if ($gaps.Count -gt 0) { $complete = New-HordeUnknown -Reason (@($gaps) -join "; ") }
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
    #
    # SESSIONS ONLY. Pending spawn claims - spawned, no record yet - are counted by
    # Get-HordeRoleClaimCount and deliberately not added in here; see there for why.
    param($Read, [Parameter(Mandatory = $true)][string]$Role, $Table = $null)
    # Only a native role can be counted. Stored roles are translated on read, so wezfleet's "master"
    # never matches anything and used to answer a known 0 while a master was running.
    if ($null -eq $Table) { $Table = Get-HordeRoleTable }
    if ($Table.native -notcontains $Role) { throw ("cannot count role '" + $Role + "': count one of " + ($Table.native -join ", ")) }
    if ($Read.complete.state -ne "known") { return (New-HordeUnknown -Reason ("cannot count: " + $Read.complete.reason)) }
    $unsure = @($Read.sessions | Where-Object { -not $_.retired -and $_.role.state -ne "known" } | ForEach-Object { $_.id })
    if ($unsure.Count -gt 0) {
        return (New-HordeUnknown -Reason ("cannot count: the role of " + $unsure.Count + " live session(s) is unknown (" + ($unsure -join ", ") + ")"))
    }
    $n = @($Read.sessions | Where-Object { -not $_.retired -and $_.role.state -eq "known" -and $_.role.value -eq $Role }).Count
    return (New-HordeKnown -Value $n)
}

# wezfleet's backstop for a spawn claim: older than this, it no longer applies
# (YedPool/wezfleet lib/Registry.ps1:1235, $script:WfClaimTtlMinutes = 10080, seven days).
$script:HordeWezfleetClaimTtlMinutes = 10080

function Test-HordeClaimPending {
    # Is this claim still pending by wezfleet's own rule? Read-WfPaneClaim (lib/Registry.ps1:1294-1307),
    # called with no cwd as `master ensure` calls it, accepts a claim with a parseable spawnedAt no
    # older than the backstop, and nothing else. Mirrored exactly, so a shadow count agrees with it.
    param($Claim, [datetime]$Now = (Get-Date))
    $at = $Claim.spawnedAt
    if ($null -eq $at -or "$at" -eq "") { return $false }
    $when = $null
    if ($at -is [datetime]) { $when = $at }
    else {
        $parsed = [datetime]::MinValue
        if (-not [datetime]::TryParse("$at", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) { return $false }
        $when = $parsed
    }
    # Both in UTC: a local Now against a UTC spawnedAt is off by the zone offset - the defect fixed in
    # core/tristate's Limit-HordeAge on 2026-09-29.
    $ageMinutes = ($Now.ToUniversalTime() - $when.ToUniversalTime()).TotalMinutes
    return ($ageMinutes -le $script:HordeWezfleetClaimTtlMinutes)
}

function Get-HordeRoleClaimCount {
    # How many PENDING spawn claims name a role: sessions spawned and not yet visible, because a
    # claim is consumed only by the session's first tool call. wezfleet's `master ensure` counts a
    # pending master claim AS a master (lib/Master.ps1:118-137): a master idle for three days once
    # had no record, and a second one was nearly spawned.
    #
    # THE CHOICE: this number is kept apart from Get-HordeRoleCount, not added into it. "Running" and
    # "spawned but not yet seen" are different facts, and a sum would hide which one a caller saw.
    # A caller asking wezfleet's question - is there a master at all? - adds the two. (Ledger L-023.)
    #
    # Unknown when the store read was incomplete, or when a pending claim's role is unknown (it may
    # be the role asked about). A claim whose role is empty names no role and is not counted, as in
    # wezfleet, where "" never equals "master".
    param($Read, [Parameter(Mandatory = $true)][string]$Role, $Table = $null, [datetime]$Now = (Get-Date))
    if ($null -eq $Table) { $Table = Get-HordeRoleTable }
    if ($Table.native -notcontains $Role) { throw ("cannot count role '" + $Role + "': count one of " + ($Table.native -join ", ")) }
    if ($Read.complete.state -ne "known") { return (New-HordeUnknown -Reason ("cannot count claims: " + $Read.complete.reason)) }
    $pending = @($Read.claims | Where-Object { Test-HordeClaimPending -Claim $_ -Now $Now })
    $unsure = @($pending | Where-Object { $_.role.state -ne "known" -and $_.field -ne "empty" } | ForEach-Object { $_.pane })
    if ($unsure.Count -gt 0) {
        return (New-HordeUnknown -Reason ("cannot count claims: the role of " + $unsure.Count + " pending claim(s) is unknown (pane " + ($unsure -join ", ") + ")"))
    }
    return (New-HordeKnown -Value @($pending | Where-Object { $_.role.state -eq "known" -and $_.role.value -eq $Role }).Count)
}
