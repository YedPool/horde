# core/Device - this machine's device id: one random id per Horde home, made once.
#
# WHAT IT IS FOR (remote plan step R7, planning/execution-plan-remote.md). The id names this machine
# everywhere a session or a fact must say where it lives: the link's hello and node-manifest.v1's
# deviceId, the session record's `device` (R10), every namespace tag (R11), and the lifecycle
# follower's stream file `<machineId>.jsonl` (its step 7: machineId IS this id). Identity is not
# location (the old system's rewrite proposal, wezfleet-v3-rewrite-proposal.html:105-111): the id
# says which machine, and nothing about where it is or what it is called.
#
# RANDOM, NEVER DERIVED. A UUID from [guid]::NewGuid(), never from a host name, a MAC address or a
# disk serial: those change with a rename or a new network card, and two machines cloned from one
# image share them. The device NAME is a handle for people, taken from the computer name and fitted
# to node-manifest.v1's pattern; renaming it in the file changes nothing about identity.
#
# MADE ONCE, EVEN WHEN FIRST CALLS RACE. The follower, `node serve` and a CLI call can all start at
# boot. Each writes its candidate in full to a temporary file of its own, then renames it to
# node.json with [System.IO.File]::Move, which on one volume is a single rename that fails if the
# target exists. So exactly one candidate becomes node.json, it is complete when it appears, and
# every loser reads the winner's id. CreateNew on node.json itself (the plan's first wording) also
# makes one winner, but a loser could then read the winner's file before its bytes were written.
#
# NEVER OVERWRITTEN. A node.json Horde cannot read is refused with the reason, and left alone: a
# fresh id over it would make the hub see a new device and orphan every session bound to the old one.
# The file must be exactly the one line Horde writes. That is stricter than JSON on purpose:
# PowerShell 5.1's ConvertFrom-Json keeps the last of two equal keys without a word, so a hand-edited
# file with two deviceIds would load as one a reader did not see.
#
# A COPIED node.json IS NOT CAUGHT HERE. Copied to a second machine it gives both one id, and nothing
# on either machine can tell. Enrolment catches it (step R17): the copy's link key differs, and a
# device id already bound to another key is refused. The way out is the same as for a file Horde
# cannot read: move node.json away by hand, and the next call makes a new device, which the hub must
# then enrol as new. No command does it, because a new id orphans every session bound to the old one.
#
# DURABLE BEFORE IT IS VISIBLE. The candidate is flushed through to the disk before the rename, so a
# power cut cannot leave a node.json that exists but is empty - which Horde would then refuse for good,
# possibly after the id had reached the hub (review of PR for R7, 2026-10-02). A rename that fails while
# node.json still does not exist is retried a few times: an antivirus or indexer scan briefly holding
# the new candidate open is not a reason for a first call at boot to fail.
#
# READ ON EVERY CALL. Nothing is cached here; a caller that compares many tags with the local device
# (R11) reads the id once and holds it.
#
# No Set-StrictMode here: this file is dot-sourced, so a file-scope Set-StrictMode would set the
# caller's mode (see core/Tristate.ps1). The functions run under -Version Latest.
. (Join-Path $PSScriptRoot "Home.ps1")

# node-manifest.v1's deviceId and deviceName patterns. Read here as the shapes this file may hold; the
# id Horde makes is always a lower-case version 4 UUID, which the first pattern includes.
$script:HordeDeviceIdPattern = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
$script:HordeDeviceNamePattern = '[A-Za-z0-9][A-Za-z0-9._-]{0,63}'
# The one line node.json holds, with an optional line ending. Nothing else is read as a node file.
# \z, not $: in .NET a final $ also matches before one more trailing newline, so "line\r\n\n" passed.
$script:HordeNodeLinePattern = '^\{"schemaVersion":1,"deviceId":"(' + $script:HordeDeviceIdPattern + ')","deviceName":"(' + $script:HordeDeviceNamePattern + ')"\}(\r?\n)?\z'
# How many times a rename that fails while node.json is still absent is tried, 100 ms apart.
$script:HordeNodeMoveTries = 5

function ConvertTo-HordeDeviceName {
    # A device name node-manifest.v1 accepts, made from any text: every character outside letters,
    # digits, dot, underscore and hyphen becomes a hyphen, the front is trimmed to a letter or digit,
    # and the whole is cut to 64. Nothing usable gives "node".
    param([string]$Text)
    $s = ($Text -replace '[^A-Za-z0-9._-]', '-') -replace '^[^A-Za-z0-9]+', ''
    if ($s.Length -gt 64) { $s = $s.Substring(0, 64) }
    if ($s -eq "") { return "node" }
    return $s
}

function Read-HordeNodeFile {
    # The device id and name in node.json, or a throw naming the file and what is wrong. The bytes are
    # checked as ASCII before they are read as text, so a byte-order mark or a raw non-ASCII byte is
    # refused instead of decoded into something that might match.
    param([Parameter(Mandatory = $true)][string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Container) { throw ("node.json at '" + $Path + "' is a folder, not Horde's node file; Horde will not make a device id beside it") }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    foreach ($b in $bytes) { if ($b -gt 0x7F) { throw ("node.json at '" + $Path + "' holds a byte that is not ASCII (a byte-order mark counts); Horde will not replace it, because a new id would be a new device. To start this machine over as a new device, move node.json away by hand") } }
    $text = [System.Text.Encoding]::ASCII.GetString($bytes)
    $m = [regex]::Match($text, $script:HordeNodeLinePattern)
    if (-not $m.Success) { throw ("node.json at '" + $Path + "' is not the one line Horde writes ({""schemaVersion"":1,""deviceId"":""<uuid>"",""deviceName"":""<name>""}); Horde will not replace it, because a new id would be a new device. To start this machine over as a new device, move node.json away by hand") }
    return [pscustomobject]@{ deviceId = $m.Groups[1].Value; deviceName = $m.Groups[2].Value }
}

function Get-HordeNode {
    # This machine's node identity, { deviceId; deviceName; path; created; raced }, made on the first
    # call for this home. created: this call wrote node.json. raced: this call made a candidate and
    # another call's candidate became node.json first (the race suite counts these to show the racers
    # met). -HomeRoot is for tests and tools; by default the home is core/Home's.
    param([string]$HomeRoot = "")
    if ($HomeRoot -eq "") { $HomeRoot = Get-HordeHome }
    $dir = Join-Path $HomeRoot "node"
    $file = Join-Path $dir "node.json"
    if (Test-Path -LiteralPath $file) {
        $r = Read-HordeNodeFile -Path $file
        return [pscustomobject]@{ deviceId = $r.deviceId; deviceName = $r.deviceName; path = $file; created = $false; raced = $false }
    }
    [void][System.IO.Directory]::CreateDirectory($dir)
    $id = [guid]::NewGuid().ToString("D").ToLowerInvariant()
    $name = ConvertTo-HordeDeviceName -Text "$env:COMPUTERNAME"
    $line = '{"schemaVersion":1,"deviceId":"' + $id + '","deviceName":"' + $name + '"}' + "`r`n"
    $tmp = Join-Path $dir ("node.json." + [guid]::NewGuid().ToString("N") + ".tmp")
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($line)
    $fs = New-Object System.IO.FileStream($tmp, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None, 4096, [System.IO.FileOptions]::WriteThrough)
    try { $fs.Write($bytes, 0, $bytes.Length); $fs.Flush($true) } finally { $fs.Dispose() }
    $won = $false
    try {
        for ($try = 1; -not $won; $try++) {
            try {
                [System.IO.File]::Move($tmp, $file)
                $won = $true
            } catch [System.IO.IOException] {
                # node.json exists: another call's candidate became it first, so read the winner's.
                if ([System.IO.File]::Exists($file)) { break }
                # It does not: something else holds the candidate or the folder. Retried, then thrown.
                if ($try -ge $script:HordeNodeMoveTries) { throw }
                Start-Sleep -Milliseconds 100
            }
        }
    } finally {
        if (-not $won -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
    if ($won) { return [pscustomobject]@{ deviceId = $id; deviceName = $name; path = $file; created = $true; raced = $false } }
    $w = Read-HordeNodeFile -Path $file
    return [pscustomobject]@{ deviceId = $w.deviceId; deviceName = $w.deviceName; path = $file; created = $false; raced = $true }
}

function Get-HordeDeviceId {
    # This machine's device id: the deviceId of Get-HordeNode.
    param([string]$HomeRoot = "")
    return (Get-HordeNode -HomeRoot $HomeRoot).deviceId
}
