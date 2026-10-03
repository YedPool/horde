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

function Get-HordeAgentStores {
    # Every engine's declared stores, as an answer: known list of { agent; roots; transcripts }, roots
    # being full paths and transcripts { dir; extension; label } for each folder under them that holds
    # its transcripts, label naming the root and folder without a home path ("profile.x/logs",
    # "env-VAR/logs"); unknown when any engine folder does not say. Read as DATA from
    # agents/<name>/stores.json, found by folder and never named, so an engine with no transcript
    # adapter is protected too (review of PR #50, F7: a guard built from the loaded adapters left one
    # engine's folder open, and a probe wrote two summaries into a fake profile's copy of it).
    #
    # stores.json: { "schemaVersion": 1, "roots": [ { "profile": ".name" } | { "env": "VARIABLE" } ],
    # "transcripts": [ { "folder": "name", "extension": ".ext" }, ... ] }. "profile" is a folder in the
    # user profile; "env" names a variable that can move the store, and counts only when set.
    # "transcripts" names the folders, under each root, where `horde metrics collect` looks for
    # transcripts, and the extension of the engine's transcript files (plan step M2); an engine Horde
    # cannot read declares none. An engine folder with no stores.json, or one that cannot be
    # read, makes the whole answer unknown, and the writer refuses: an engine nobody described is not
    # left unguarded.
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
        $roots = New-Object System.Collections.ArrayList
        $labelled = New-Object System.Collections.ArrayList
        foreach ($r in @($s["roots"])) {
            if ($r -isnot [System.Collections.IDictionary]) { return (New-HordeUnknown -Reason ($where + " has a root that is not an object")) }
            if ($r["profile"] -is [string] -and $r["profile"] -ne "") {
                if ("$env:USERPROFILE".Trim() -ne "") { $p = Join-Path "$env:USERPROFILE" $r["profile"]; [void]$roots.Add($p); [void]$labelled.Add([pscustomobject]@{ label = ("profile" + $r["profile"]); path = $p }) }
            }
            elseif ($r["env"] -is [string] -and $r["env"] -ne "") {
                $v = [Environment]::GetEnvironmentVariable($r["env"])
                if ("$v".Trim() -ne "") { [void]$roots.Add("$v"); [void]$labelled.Add([pscustomobject]@{ label = ("env-" + $r["env"]); path = "$v" }) }
            }
            else { return (New-HordeUnknown -Reason ($where + " has a root with neither profile nor env")) }
        }
        $folders = New-Object System.Collections.ArrayList
        $exts = New-Object System.Collections.ArrayList
        if ($s.ContainsKey("transcripts")) {
            if ($s["transcripts"] -is [string] -or $s["transcripts"] -isnot [System.Collections.IEnumerable]) { return (New-HordeUnknown -Reason ($where + " has a transcripts entry that is not a list")) }
            foreach ($t in @($s["transcripts"])) {
                # A folder name under the root, never a path that climbs out of it, and the extension of the
                # engine's transcript files, which only the engine's folder may say (CONTRIBUTING 14).
                if ($t -isnot [System.Collections.IDictionary]) { return (New-HordeUnknown -Reason ($where + " has a transcripts entry that is not { folder; extension }")) }
                $fo = $t["folder"]; $ex = $t["extension"]
                if ($fo -isnot [string] -or $fo -notmatch '\A[A-Za-z0-9._-]+\z' -or $fo -match '\A\.+\z') { return (New-HordeUnknown -Reason ($where + " has a transcripts folder that is not one plain folder name: '" + $fo + "'")) }
                if ($ex -isnot [string] -or $ex -notmatch '\A\.[A-Za-z0-9]{1,10}\z') { return (New-HordeUnknown -Reason ($where + " has a transcripts extension that is not a dot and up to ten letters or digits: '" + $ex + "'")) }
                if ($exts -notcontains $ex) { [void]$exts.Add($ex) }
                foreach ($lr in $labelled) { [void]$folders.Add([pscustomobject]@{ dir = (Join-Path $lr.path $fo); extension = $ex; label = ($lr.label + "/" + $fo) }) }
            }
        }
        [void]$out.Add([pscustomobject]@{ agent = $d.Name; roots = $roots.ToArray(); transcripts = $folders.ToArray(); extensions = $exts.ToArray() })
    }
    return (New-HordeKnown -Value $out.ToArray())
}

function Get-HordeAgentStoreRoots {
    # The folders every engine keeps its own files in, as an answer: known list of full paths, or
    # unknown when any engine folder does not say (Get-HordeAgentStores).
    param([string]$Root = (Split-Path -Parent $PSScriptRoot))
    $stores = Get-HordeAgentStores -Root $Root
    if ($stores.state -ne "known") { return $stores }
    $out = New-Object System.Collections.ArrayList
    foreach ($s in @($stores.value)) { foreach ($r in @($s.roots)) { [void]$out.Add($r) } }
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

function Move-HordeFileAtomic {
    # Rename -From over -To in ONE step: MoveFileEx with REPLACE_EXISTING and WRITE_THROUGH, a single
    # rename on NTFS. Review of PR #70 measured why File.Replace is not enough: Win32 ReplaceFile works in
    # steps, and one of 40 kills inside it left NO index - the new one only in its temp file. A rename is
    # all or nothing: a kill leaves the old file or the new one, never neither. A reader holding the file
    # without delete sharing makes the rename fail for a moment; it is tried again for up to 2 s.
    param([Parameter(Mandatory = $true)][string]$From, [Parameter(Mandatory = $true)][string]$To)
    if (-not ([System.Management.Automation.PSTypeName]"HordeNative.FileMove").Type) {
        Add-Type -Namespace HordeNative -Name FileMove -MemberDefinition '[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags);'
    }
    $err = 0
    for ($i = 0; $i -lt 20; $i++) {
        # 0x1 MOVEFILE_REPLACE_EXISTING, 0x8 MOVEFILE_WRITE_THROUGH.
        if ([HordeNative.FileMove]::MoveFileEx($From, $To, 0x9)) { return }
        $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Start-Sleep -Milliseconds 100
    }
    throw (New-Object System.ComponentModel.Win32Exception($err))
}

function Write-HordeMetricsFile {
    # Write a file under the metrics folder whole: to a temporary file beside it, flushed to disk, then
    # renamed over the file in one step (Move-HordeFileAtomic), so a reader - or a kill - never sees half
    # of it. Used for records and for collect's index. The temp name is "." + name + "." + 32 hex + ".tmp":
    # collect recovers from, and cleans up, exactly that pattern (core/MetricsCollect.ps1).
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Text)
    $dir = Split-Path -Parent $Path
    [void][System.IO.Directory]::CreateDirectory($dir)
    $temp = Join-Path $dir ("." + (Split-Path -Leaf $Path) + "." + [guid]::NewGuid().ToString("N") + ".tmp")
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($Text)
    $fs = New-Object System.IO.FileStream($temp, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try { $fs.Write($bytes, 0, $bytes.Length); $fs.Flush($true) } finally { $fs.Dispose() }
    # A rename that fails while this process lives leaves an uncommitted temp: removed here. Only a kill
    # leaves one behind, and collect recovers or removes those (core/MetricsCollect.ps1).
    try { Move-HordeFileAtomic -From $temp -To $Path }
    catch { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue; throw }
}

function Test-HordeMetricsRecordName {
    # The record's name comes from a transcript's file name; anything that could climb out of the
    # folder or name a device is refused rather than cleaned.
    param([string]$Name)
    return ($Name -cmatch '\A[A-Za-z0-9][A-Za-z0-9._-]{0,200}\z' -and $Name -notmatch '\.\.')
}

function Get-HordeMetricsRecordPath {
    # Where the record <adapter>/<name> lives: <metrics>\summaries\<adapter>\<name>.json.
    param([Parameter(Mandatory = $true)][string]$Adapter, [Parameter(Mandatory = $true)][string]$Name)
    if ($Adapter -cnotmatch '\A[a-z][a-z0-9-]*\z') { throw ("not an adapter name: '" + $Adapter + "'") }
    if (-not (Test-HordeMetricsRecordName $Name)) { throw ("not a record name Horde will write: '" + $Name + "'") }
    return (Join-Path (Join-Path (Join-Path (Get-HordeMetricsDir) "summaries") $Adapter) ($Name + ".json"))
}

function Write-HordeMetricsRecord {
    # Write one record, whole, as <metrics>\summaries\<adapter>\<name>.json. Returns the path written.
    # The caller has already had Get-HordeMetricsWriteDecision say yes.
    param([Parameter(Mandatory = $true)]$Record, [Parameter(Mandatory = $true)][string]$Adapter, [Parameter(Mandatory = $true)][string]$Name)
    $target = Get-HordeMetricsRecordPath -Adapter $Adapter -Name $Name
    Write-HordeMetricsFile -Path $target -Text (ConvertTo-Json -InputObject $Record -Depth 30)
    return $target
}
