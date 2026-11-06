# fleet/SessionSnapshot.ps1 - the port side of the fleet.db sessions step (T-0409, piece 2 of T-0299).
#
# `horde db sync` keeps session, pane and session_pane current every minute. What it needs from the machine is three
# plain facts, and this file gathers them through the ports and names none of them (CONTRIBUTING 14):
#   registry   the fleet registry's session records (-Registry: core/WezfleetState.ps1's Read-HordeRegistry)
#   panes      the live panes of every terminal instance (the host adapter's Panes block, fleet/Port.ps1)
#   processes  the sessions whose harness process is running (the agent adapter's Snapshot and Running blocks)
# The result is one object that ConvertTo-HordeFleetSessionSnapshotJson writes as ASCII JSON for fleet-db/sessions.mjs, which
# knows nothing of any port and decides everything else (shape: SNAPSHOT_SHAPE there). fleet-db/SessionSnapshotRun.ps1
# loads the adapters and runs this; fleet-db/Sync.ps1 starts that as a child with a time limit of its own.
#
# A FACT THAT CANNOT BE READ IS SAID SO, never left out. panes and processes are each { state: known | unknown, reason, ... }
# and each terminal instance is listed, closed or unknown: the node side never calls a session dead on a terminal it could
# not list or a process list it could not read. The registry is NOT a liveness source (about 115 of 155 records are never
# retired); it only says which pane a session last claimed, and the node side checks that claim against the live list.
#
# THE RECORDS ARE PASSED ON AS THE REGISTRY HOLDS THEM, by the fields the importer reads (RECORD_FIELDS), so one rule decides
# how a record becomes a session row (fleet-db/import.mjs) and this file copies none of it. A time that PowerShell 7 parsed into a
# [datetime] is written back as UTC text, which the importer reads.
#
# THE PROCESS FACT. The agent adapter's Running block lists the sessions with a live control file: a process that runs, that
# started when the file says (a reused pid proves nothing). Its Snapshot also reads the process table once for command lines
# (CIM; slow, so exactly one such read per tick, here), and a process started to resume a session by hand has no control file but
# names the id: those ids count as running too (erring toward alive). If that listing was partly unreadable, a session missing from
# the list may still run, so the whole process fact is unknown. What this cannot tell: a session that took a new id inside a
# running process (a clear or a compaction) keeps the process's old control-file id until the harness rewrites the file.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). POWERSHELL 5.1: no 2>&1 (CONTRIBUTING 12).
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")

# What the importer reads of a record (fleet-db/import.mjs stepSessions): the rest of a record is not carried.
$script:HordeFleetSnapshotRecordFields = @("kind", "rank", "role", "retired", "retiredAt", "owner", "label", "parent", "resumedFrom", "resumedFromId", "pid", "processStartedAt", "firstCwd", "cwd", "transcriptPath", "origin", "fleetSessionId", "fleetRunDir", "firstSeen", "lastSeen", "instance", "pane")

function ConvertTo-HordeFleetSnapshotValue {
    # One record field as JSON-safe data: a [datetime] (PowerShell 7 parses date-shaped strings) as UTC text, a number or a
    # boolean as it is, anything else as text.
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString("o") }
    if ($Value -is [bool] -or $Value -is [int] -or $Value -is [long] -or $Value -is [double]) { return $Value }
    return ("" + $Value)
}

function ConvertTo-HordeFleetSnapshotRecord {
    param($Record)
    $o = [ordered]@{}
    foreach ($n in $script:HordeFleetSnapshotRecordFields) {
        $p = $Record.PSObject.Properties[$n]
        if ($null -ne $p -and $null -ne $p.Value) { $o[$n] = ConvertTo-HordeFleetSnapshotValue $p.Value }
    }
    return [pscustomobject]$o
}

function Get-HordeFleetSnapshotPanes {
    # The panes fact: { state; reason; sockets }, from the host adapter's Panes block.
    param($HostAdapter)
    $none = { param($why) return [pscustomobject][ordered]@{ state = "unknown"; reason = $why; sockets = @() } }
    if ($null -eq $HostAdapter) { return (& $none "no terminal adapter is loaded, so the live panes are not known") }
    if ($null -eq $HostAdapter.PSObject.Properties["panes"] -or $null -eq $HostAdapter.panes) { return (& $none ("the terminal adapter " + $HostAdapter.name + " offers no pane list")) }
    $a = $null
    try { $a = & $HostAdapter.panes } catch { return (& $none ("the pane list failed: " + $_.Exception.Message)) }
    if (-not (Test-HordeAnswer $a)) { return (& $none "the terminal adapter's pane list is not an answer") }
    if ($a.state -cne "known") { return (& $none ("" + $a.reason)) }
    $sockets = New-Object System.Collections.ArrayList
    foreach ($s in @($a.value)) {
        if ($null -eq $s) { continue }
        [void]$sockets.Add([pscustomobject][ordered]@{ instance = "" + $s.instance; state = "" + $s.state; panes = @(@($s.panes) | Where-Object { $null -ne $_ } | ForEach-Object { [int]$_ }); reason = "" + $s.reason })
    }
    return [pscustomobject][ordered]@{ state = "known"; reason = ""; sockets = $sockets.ToArray() }
}

function Get-HordeFleetSnapshotProcesses {
    # The processes fact: { state; reason; running }, from the agent adapter. Exactly one process-table read: the adapter's
    # own Snapshot makes it. -Snapshot replaces that read in a test (a block returning the adapter's snapshot).
    param($Agent, [scriptblock]$Snapshot = $null)
    $none = { param($why) return [pscustomobject][ordered]@{ state = "unknown"; reason = $why; running = @() } }
    if ($null -eq $Agent) { return (& $none "no agent adapter is loaded, so the running sessions are not known") }
    $snap = $null
    try {
        if ($null -ne $Snapshot) { $snap = & $Snapshot } else { $snap = & $Agent.snapshot }
    } catch { return (& $none ("the running sessions could not be read: " + $_.Exception.Message)) }
    if ($null -eq $snap) { return (& $none "the agent adapter gave no reading of the running sessions") }
    if ("" + $snap.error -ne "") { return (& $none ("" + $snap.error)) }
    # A process listing that was partly unreadable may hide a session that runs: not knowing is the honest answer.
    $re = $snap.PSObject.Properties["resumedError"]
    if ($null -ne $re -and "" + $re.Value -ne "") { return (& $none ("" + $re.Value)) }
    $running = New-Object System.Collections.ArrayList
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($r in @(& $Agent.running $snap)) {
        if ($null -ne $r -and $seen.Add(("" + $r.sessionId).ToLowerInvariant())) { [void]$running.Add([pscustomobject][ordered]@{ sessionId = ("" + $r.sessionId).ToLowerInvariant(); pid = "" + $r.pid }) }
    }
    $rs = $snap.PSObject.Properties["resumed"]
    if ($null -ne $rs -and $null -ne $rs.Value -and $rs.Value -is [System.Collections.IDictionary]) {
        foreach ($id in @($rs.Value.Keys)) {
            if ($seen.Add(("" + $id).ToLowerInvariant())) { [void]$running.Add([pscustomobject][ordered]@{ sessionId = ("" + $id).ToLowerInvariant(); pid = "" + $rs.Value[$id] }) }
        }
    }
    return [pscustomobject][ordered]@{ state = "known"; reason = ""; running = $running.ToArray() }
}

function New-HordeFleetSessionSnapshot {
    # The snapshot object. -Registry is Read-HordeRegistry's result (or $null when it could not be read); -HostAdapter and
    # -Agent are the adapters fleet/Port.ps1 resolved (or $null when none could be, which the snapshot then says); -At the tick's time.
    param($Registry, $HostAdapter = $null, $Agent = $null, [datetime]$At = [datetime]::UtcNow, [scriptblock]$ProcessSnapshot = $null)
    $sessions = New-Object System.Collections.ArrayList
    $complete = $false
    $why = "the fleet registry could not be read"
    if ($null -ne $Registry) {
        foreach ($id in @($Registry.records.Keys | Sort-Object)) {
            $row = $Registry.records[$id]
            [void]$sessions.Add([pscustomobject][ordered]@{ id = ("" + $id).ToLowerInvariant(); rec = (ConvertTo-HordeFleetSnapshotRecord -Record $row.record) })
        }
        $complete = ($Registry.complete.state -ceq "known")
        $why = ""
        if (-not $complete) { $why = "" + $Registry.complete.reason }
    }
    $ms = [long][Math]::Floor(($At.ToUniversalTime() - [datetime]::new(1970, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)).TotalMilliseconds)
    return [pscustomobject][ordered]@{
        v         = 1
        at        = $ms
        registry  = [pscustomobject][ordered]@{ complete = $complete; reason = $why; sessions = $sessions.ToArray() }
        panes     = (Get-HordeFleetSnapshotPanes -HostAdapter $HostAdapter)
        processes = (Get-HordeFleetSnapshotProcesses -Agent $Agent -Snapshot $ProcessSnapshot)
    }
}

function ConvertTo-HordeFleetSessionSnapshotJson {
    # Compact JSON with every character past ASCII written as a \u escape, so the file is ASCII whatever a path or a label
    # holds (CONTRIBUTING 13).
    param([Parameter(Mandatory = $true)]$Snapshot)
    $json = ConvertTo-Json -InputObject $Snapshot -Depth 8 -Compress
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $json.ToCharArray()) {
        if ([int]$ch -gt 126) { [void]$sb.Append(("\u{0:x4}" -f [int]$ch)) } else { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
}
