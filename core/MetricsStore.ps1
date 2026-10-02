# core/MetricsStore - whether metrics may be recorded, and recording them.
#
# OFF BY DEFAULT, AND ONLY A FILE TURNS IT ON (metrics design, "Decisions taken" 1 and 8):
#   - The gate is <HordeHome>\metrics\gate.json: { "schemaVersion": 1, "level": "usage", "enabledAt":
#     "<UTC time>" }. No file means off. A file that cannot be read, or says anything else, is
#     REFUSED - nothing is written - because an unreadable consent is not consent.
#   - No environment variable turns it on or changes the level. A child inherits its parent's
#     environment, so one pane's variable would silently start recording every descendant
#     (design 7.2). HORDE_HOME, a path, is the only variable read, through core/Home.ps1.
#   - Nothing from before consent is recorded: a transcript whose first event is earlier than
#     enabledAt is summarised on screen and not written (decision 8, no backfill).
#   - THIS GATE FILE IS A STOPGAP, accepted for M1 only (coordinator's decision, 2026-10-01). Plan step
#     M2 (planning/execution-plan-metrics.md, "The gate becomes a setting") replaces it with
#     metrics.level in the layered engine-settings precedence, read and written through `horde config`,
#     with the project layer allowed only to lower it. gate.json is then migrated into the user layer,
#     its enabledAt kept as the consent time, and removed. Nothing new should come to depend on it.
#
# WHAT IS WRITTEN: one JSON record per transcript, <HordeHome>\metrics\summaries\<adapter>\<name>.json,
# replaced whole each time (written to a temporary file beside it and moved into place, so a reader
# never sees half a record). It holds counts, times, ids and the transcript's file NAME - never a path
# into anyone's home and never text (design section 8). A summary of a time window is never written.
#
# NEVER INSIDE ANY ENGINE'S OWN FOLDERS. Every agents/<name>/stores.json declares its engine's store
# folders, adapter or none (Get-HordeAgentStoreRoots); a metrics folder inside one is refused.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). Needs core/Tristate.ps1,
# core/ReadShared.ps1, core/Home.ps1 and core/Transcript.ps1.

$script:HordeMetricsLevels = @("off", "usage")
$script:HordeMetricsDefVersion = "m1"

function Get-HordeMetricsDir { return (Join-Path (Get-HordeHome) "metrics") }

function Read-HordeMetricsGate {
    # The gate as an answer: known { level; enabledAt }, absent when there is no gate file (off), or
    # unknown when the file is unreadable or not a gate - which the writer treats as a refusal.
    param([string]$Path = (Join-Path (Get-HordeMetricsDir) "gate.json"))
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return (New-HordeAbsent -Note ("no gate file at " + $Path + "; metrics are off")) }
    Add-Type -AssemblyName System.Web.Extensions
    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $g = $null
    try { $g = $ser.DeserializeObject((Read-HordeSharedText -Path $Path)) } catch { return (New-HordeUnknown -Reason ("the gate file " + $Path + " cannot be read") -ErrorRecord $_) }
    if ($g -isnot [System.Collections.IDictionary]) { return (New-HordeUnknown -Reason ("the gate file " + $Path + " is not a JSON object")) }
    if ($g["schemaVersion"] -ne 1) { return (New-HordeUnknown -Reason ("the gate file's schemaVersion is not 1")) }
    $level = $g["level"]
    # Case-sensitive: "USAGE" is not a level Horde writes, and a gate is not a place to be lenient.
    if ($level -isnot [string] -or $script:HordeMetricsLevels -cnotcontains $level) { return (New-HordeUnknown -Reason ("the gate's level '" + $level + "' is not one of " + ($script:HordeMetricsLevels -join ", "))) }
    $at = ConvertTo-HordeUtcTime $g["enabledAt"]
    if ($level -ceq "usage" -and $null -eq $at) { return (New-HordeUnknown -Reason "the gate says usage but gives no enabledAt with a zone, so what came before consent cannot be told") }
    return (New-HordeKnown -Value ([pscustomobject]@{ level = $level; enabledAt = $at }))
}

function Test-HordePathInside {
    # Whether Path is Root or inside it. Compared on full paths, case-insensitively (Windows), with a
    # trailing separator so C:\x\abc is not inside C:\x\ab.
    param([string]$Path, [string]$Root)
    if ("$Root".Trim() -eq "") { return $false }
    $p = [System.IO.Path]::GetFullPath($Path).TrimEnd('\') + '\'
    $r = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    return $p.StartsWith($r, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-HordeAgentStoreRoots {
    # The folders every engine keeps its own files in, as an answer: known list of full paths, or
    # unknown when any engine folder does not say. Read as DATA from agents/<name>/stores.json, found by
    # folder and never named, so an engine with no transcript adapter is protected too (review of PR
    # #50, F7: a guard built from the loaded adapters left one engine's folder open, and a probe wrote
    # two summaries into a fake profile's copy of it).
    #
    # stores.json: { "schemaVersion": 1, "roots": [ { "profile": ".name" } | { "env": "VARIABLE" } ] }.
    # "profile" is a folder in the user profile; "env" names a variable that can move the store, and
    # counts only when set. An engine folder with no stores.json, or one that cannot be read, makes the
    # whole answer unknown, and the writer refuses: an engine nobody described is not left unguarded.
    param([string]$Root = (Split-Path -Parent $PSScriptRoot))
    $agents = Join-Path $Root "agents"
    $out = New-Object System.Collections.ArrayList
    if (-not (Test-Path -LiteralPath $agents -PathType Container)) { return (New-HordeKnown -Value @()) }
    Add-Type -AssemblyName System.Web.Extensions
    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    foreach ($d in @(Get-ChildItem -LiteralPath $agents -Directory | Sort-Object Name)) {
        $file = Join-Path $d.FullName "stores.json"
        $where = "agents/" + $d.Name + "/stores.json"
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return (New-HordeUnknown -Reason ($where + " does not exist, so where that engine keeps its files is not known")) }
        $s = $null
        try { $s = $ser.DeserializeObject((Read-HordeSharedText -Path $file)) } catch { return (New-HordeUnknown -Reason ($where + " cannot be read") -ErrorRecord $_) }
        if ($s -isnot [System.Collections.IDictionary] -or $s["schemaVersion"] -ne 1 -or $s["roots"] -isnot [System.Collections.IEnumerable] -or @($s["roots"]).Count -eq 0) { return (New-HordeUnknown -Reason ($where + " is not a stores file with at least one root")) }
        foreach ($r in @($s["roots"])) {
            if ($r -isnot [System.Collections.IDictionary]) { return (New-HordeUnknown -Reason ($where + " has a root that is not an object")) }
            if ($r["profile"] -is [string] -and $r["profile"] -ne "") {
                if ("$env:USERPROFILE".Trim() -ne "") { [void]$out.Add((Join-Path "$env:USERPROFILE" $r["profile"])) }
            }
            elseif ($r["env"] -is [string] -and $r["env"] -ne "") {
                $v = [Environment]::GetEnvironmentVariable($r["env"])
                if ("$v".Trim() -ne "") { [void]$out.Add("$v") }
            }
            else { return (New-HordeUnknown -Reason ($where + " has a root with neither profile nor env")) }
        }
    }
    return (New-HordeKnown -Value $out.ToArray())
}

function Get-HordeMetricsWriteDecision {
    # May this summary be recorded? Returns { write; reason }. -FirstEventAt is the summary's answer.
    # -RepoRoot is where the engine folders are read from (Get-HordeAgentStoreRoots).
    param([Parameter(Mandatory = $true)]$Gate, [Parameter(Mandatory = $true)]$FirstEventAt, [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot), [switch]$Windowed)
    if ($Gate.state -eq "absent") { return [pscustomobject]@{ write = $false; reason = "metrics are off (no gate file); nothing was recorded" } }
    if ($Gate.state -eq "unknown") { return [pscustomobject]@{ write = $false; reason = ("the gate is refused, so nothing was recorded: " + $Gate.reason) } }
    if ($Gate.value.level -cne "usage") { return [pscustomobject]@{ write = $false; reason = "metrics are off (gate level off); nothing was recorded" } }
    if ($Windowed) { return [pscustomobject]@{ write = $false; reason = "a summary of a time window is shown, never recorded" } }
    if ($FirstEventAt.state -ne "known") { return [pscustomobject]@{ write = $false; reason = "the transcript has no first event, so whether it began after consent cannot be told" } }
    if ($FirstEventAt.value -lt $Gate.value.enabledAt) { return [pscustomobject]@{ write = $false; reason = ("the transcript began " + $FirstEventAt.value.ToString("o") + ", before metrics were enabled at " + $Gate.value.enabledAt.ToString("o") + "; nothing from before consent is recorded") } }
    $roots = Get-HordeAgentStoreRoots -Root $RepoRoot
    if ($roots.state -ne "known") { return [pscustomobject]@{ write = $false; reason = ("where the engines keep their files is not known, so nothing was recorded: " + $roots.reason) } }
    $dir = Get-HordeMetricsDir
    foreach ($root in @($roots.value)) {
        if (Test-HordePathInside -Path $dir -Root $root) { return [pscustomobject]@{ write = $false; reason = ("the metrics folder " + $dir + " is inside a harness's own folder " + $root + "; Horde never writes there") } }
    }
    return [pscustomobject]@{ write = $true; reason = "" }
}

function ConvertTo-HordeJsonSafe {
    # A value made safe for ConvertTo-Json: answers in their stored form, times as UTC ISO 8601 text
    # (ConvertTo-Json on PowerShell 5.1 writes a [datetime] as "\/Date(...)\/"), objects as ordered
    # maps, lists as arrays.
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ", [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($Value -is [string] -or $Value -is [bool] -or $Value -is [int] -or $Value -is [long] -or $Value -is [decimal] -or $Value -is [double]) { return $Value }
    if (Test-HordeAnswer $Value) {
        $rec = [ordered]@{ state = $Value.state; value = (ConvertTo-HordeJsonSafe $Value.value); reason = $Value.reason; observedAt = $null }
        if ($null -ne $Value.observedAt) { $rec.observedAt = ConvertTo-HordeJsonSafe $Value.observedAt }
        return $rec
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $m = [ordered]@{}
        foreach ($k in @($Value.Keys)) { $m["$k"] = ConvertTo-HordeJsonSafe $Value[$k] }
        return $m
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $m = [ordered]@{}
        foreach ($p in $Value.PSObject.Properties) { $m[$p.Name] = ConvertTo-HordeJsonSafe $p.Value }
        return $m
    }
    if ($Value -is [System.Collections.IEnumerable]) { return ,@(foreach ($x in $Value) { ConvertTo-HordeJsonSafe $x }) }
    return "$Value"
}

function New-HordeTranscriptSummaryRecord {
    # The record for one transcript. -Read is the known value of Read-HordeTranscript.
    param([Parameter(Mandatory = $true)]$Read, [Parameter(Mandatory = $true)]$Worker, [Parameter(Mandatory = $true)]$Orc)
    return [ordered]@{
        schemaVersion = 1
        kind = "transcript.summary"
        metricsDefVersion = $script:HordeMetricsDefVersion
        writtenAt = (ConvertTo-HordeJsonSafe ([datetime]::UtcNow))
        adapter = $Read.adapter
        file = (Split-Path -Leaf $Read.path)
        sessionId = $Read.sessionId
        parseSkipped = $Read.parseSkipped
        tornTail = $Read.tornTail
        worker = (ConvertTo-HordeJsonSafe $Worker)
        orc = (ConvertTo-HordeJsonSafe $Orc)
    }
}

function Write-HordeMetricsRecord {
    # Write one record, whole, as <metrics>\summaries\<adapter>\<name>.json. Returns the path written.
    # The caller has already had Get-HordeMetricsWriteDecision say yes.
    param([Parameter(Mandatory = $true)]$Record, [Parameter(Mandatory = $true)][string]$Adapter, [Parameter(Mandatory = $true)][string]$Name)
    if ($Adapter -cnotmatch '\A[a-z][a-z0-9-]*\z') { throw ("not an adapter name: '" + $Adapter + "'") }
    # The record's name comes from a transcript's file name; anything that could climb out of the
    # folder or name a device is refused rather than cleaned.
    if ($Name -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]{0,200}\z' -or $Name -match '\.\.') { throw ("not a record name Horde will write: '" + $Name + "'") }
    $dir = Join-Path (Join-Path (Get-HordeMetricsDir) "summaries") $Adapter
    [void][System.IO.Directory]::CreateDirectory($dir)
    $target = Join-Path $dir ($Name + ".json")
    $temp = Join-Path $dir ("." + $Name + "." + [guid]::NewGuid().ToString("N") + ".tmp")
    $json = ConvertTo-Json -InputObject $Record -Depth 30
    [System.IO.File]::WriteAllText($temp, $json, (New-Object System.Text.UTF8Encoding($false)))
    try {
        # [NullString]::Value, not $null: PowerShell passes $null to a string parameter as "", and Replace
        # refused "" as "not of a legal form" (measured 2026-10-01).
        if (Test-Path -LiteralPath $target -PathType Leaf) { [System.IO.File]::Replace($temp, $target, [NullString]::Value) }
        else { [System.IO.File]::Move($temp, $target) }
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
    return $target
}
