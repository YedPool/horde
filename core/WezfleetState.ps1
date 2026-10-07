# core/WezfleetState - every wezfleet store the session view reads, read once, written never.
#
# The stores, by their ids in core/ownership.json:
#   W1  registry\sessions\<claudeSessionId>.json   one record per session, written by the hook
#   W2  registry\claims\<handle>.json               a spawn claim, consumed by the session's first tool call
#   W3  <repoKey>\runs\<runId>\run.json             the run manifest
#   W4  <run dir>\roster.json                       what the spawner launched, and where
#   W5  <run dir>\sessions\<fleetId>\events.jsonl   what the session reported; status.json is its cache
#   W6  <run dir>\sessions\<fleetId>\cmdlog.txt, and loose\<claudeSessionId>.cmdlog.txt
# (W8, the codex control files, is read by core/identity.)
#
# NOTHING HERE DECIDES WHAT A FIELD IS. This reader returns what each store holds, with a completeness
# answer per store, and the projection applies core/ownership.json's precedence. Keeping the two apart
# is what lets every consumer resolve a disagreement the same way (core/ownership.ps1's header).
#
# EVERY FILE IS READ THROUGH Read-HordeSharedText, which shares read, write and delete: wezfleet swaps
# records in with File.Replace, and a reader holding the ordinary read share makes that swap fail
# (core/ReadShared.ps1, measured 2026-09-29). wezfleet's own readers use Get-Content
# (YedPool/wezfleet lib/Registry.ps1:121) and so can fail a live hook write just by reading.
#
# A STORE IS COMPLETE OR IT SAYS WHY NOT. wezfleet skipped an unreadable record silently
# (lib/Registry.ps1:121-123, "one corrupt file costs ONE row"), so the fleet got shorter instead of
# unknown. Here the row is still lost - there is nothing to read - but the store's answer says so.
#
# The command logs are not opened at all: their write time is the activity signal ("the mtime is what
# decides liveness", YedPool/wezfleet lib/Activity.ps1:158-160), so only the file system's metadata
# is read.

# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "ReadShared.ps1")
. (Join-Path $PSScriptRoot "Roles.ps1")

# Get-HordeStoredField moved here from core/Projection.ps1 (2026-10-07): core/Faults.ps1 calls it, and
# Projection loads Faults, so Faults could not load Projection without a cycle. It reads a wezfleet
# record and needs only Tristate, so it lives with the wezfleet readers, which both files load.
function Get-HordeStoredField {
    # An ENGINE field of a wezfleet record, translated the way schema/session-record.v1 says: a
    # field that is not there, null, or an empty string is ABSENT - the store was read and holds
    # none - because wezfleet writes "" for none (fleetSessionId, lastTool, owner).
    param($Record, [string]$Name, [string]$What = "the record")
    $p = $Record.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value -or ($p.Value -is [string] -and $p.Value -eq "")) { return (New-HordeAbsent -Note ($What + " has no " + $Name)) }
    return (New-HordeKnown -Value $p.Value)
}

function New-HordeGapList {
    # An empty list, returned whole: PowerShell unrolls an empty collection returned bare into $null.
    return , (New-Object System.Collections.ArrayList)
}

function ConvertTo-HordeCompleteness {
    param($Gaps)
    if ($Gaps.Count -gt 0) { return (New-HordeUnknown -Reason (@($Gaps) -join "; ")) }
    return (New-HordeKnown -Value $true)
}

function Read-HordeJsonFile {
    # A parsed JSON object, or $null with the reason added to Gaps.
    param([string]$Path, $Gaps, [string]$Label)
    try {
        $j = (Read-HordeSharedText -Path $Path) | ConvertFrom-Json
        if ($null -eq $j -or $j -isnot [System.Management.Automation.PSCustomObject]) { [void]$Gaps.Add($Label + " is not a JSON object"); return $null }
        return $j
    } catch { [void]$Gaps.Add($Label + " could not be read: " + $_.Exception.Message); return $null }
}

function Get-HordeListing {
    # The entries of a directory, or $null with the reason added to Gaps. -Directory lists folders.
    param([string]$Dir, $Gaps, [string]$Label, [switch]$Directory, [switch]$MissingIsEmpty)
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) {
        if ($MissingIsEmpty) { return @() }
        [void]$Gaps.Add("there is no " + $Label + " directory at " + $Dir); return $null
    }
    try {
        if ($Directory) { return @(Get-ChildItem -LiteralPath $Dir -Directory -ErrorAction Stop) }
        return @(Get-ChildItem -LiteralPath $Dir -File -ErrorAction Stop)
    } catch { [void]$Gaps.Add("the " + $Label + " directory could not be listed: " + $_.Exception.Message); return $null }
}

function Read-HordeRegistry {
    # W1. Returns { records; unreadable; misnamed; complete }: records maps session id (ignoring case) to
    # { id; path; record }. A record whose file name and claudeSessionId disagree is not a record
    # (YedPool/wezfleet lib/Registry.ps1:122); it is listed, and when the session it names has no
    # record of its own it may be the only copy, so the store is incomplete (core/Roles.ps1).
    param([string]$Root)
    $gaps = New-HordeGapList
    $records = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    $misnamed = New-Object System.Collections.ArrayList
    # Ids whose record file exists and cannot be read: the session HAS a record, whatever it says,
    # so a spawn claim must not answer for it (the W2 guard) and its fields are unknown, not absent.
    $unreadable = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $dir = Join-Path $Root "registry\sessions"
    $listed = Get-HordeListing -Dir $dir -Gaps $gaps -Label "registry sessions"
    foreach ($f in @($listed | Where-Object { $null -ne $_ -and $_.Extension -eq ".json" })) {
        $id = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $j = Read-HordeJsonFile -Path $f.FullName -Gaps $gaps -Label ("registry record " + $f.Name)
        if ($null -eq $j) { [void]$unreadable.Add($id); continue }
        $stored = Get-HordeField -Record $j -Name "claudeSessionId"
        $storedId = ""
        if ($stored.state -eq "known") { $storedId = "$($stored.value)" }
        if ($storedId -ne $id) { [void]$misnamed.Add([pscustomobject]@{ name = $f.Name; storedId = $storedId }); continue }
        $records[$id] = [pscustomobject]@{ id = $id; path = $f.FullName; record = $j }
    }
    foreach ($m in $misnamed) {
        if ($m.storedId -eq "" -or -not $records.ContainsKey($m.storedId)) {
            [void]$gaps.Add($m.name + " holds session '" + $m.storedId + "', which has no record of its own, so it may be the only copy of that session")
        }
    }
    return [pscustomobject]@{ records = $records; unreadable = $unreadable; misnamed = $misnamed.ToArray(); complete = (ConvertTo-HordeCompleteness $gaps) }
}

function Read-HordeClaims {
    # W2. Returns { claims; complete }: claims maps handle text to { handle; path; claim }. A missing
    # claims directory is legitimately empty: wezfleet creates it on its first claim (core/Roles.ps1).
    param([string]$Root)
    $gaps = New-HordeGapList
    $claims = @{}
    $listed = Get-HordeListing -Dir (Join-Path $Root "registry\claims") -Gaps $gaps -Label "claims" -MissingIsEmpty
    foreach ($f in @($listed | Where-Object { $null -ne $_ -and $_.Extension -eq ".json" })) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        if ($base -notmatch '^[0-9]{1,9}$') { [void]$gaps.Add("claim " + $f.Name + " is not named by a handle number"); continue }
        $j = Read-HordeJsonFile -Path $f.FullName -Gaps $gaps -Label ("claim " + $f.Name)
        if ($null -eq $j) { continue }
        $claims["" + [long]$base] = [pscustomobject]@{ handle = ("" + [long]$base); path = $f.FullName; claim = $j }
    }
    return [pscustomobject]@{ claims = $claims; complete = (ConvertTo-HordeCompleteness $gaps) }
}

function Read-HordeEventLog {
    # W5 for one session folder: { events; complete }. The log is append-only and each line is one
    # whole JSON object (YedPool/wezfleet lib/Common.ps1:175-192). A line that does not parse makes
    # the log unknown, never shorter: wezfleet's reader skipped it (Read-WfJsonLines), and a skipped
    # "done" line reads as a session still running.
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return [pscustomobject]@{ events = @(); present = $false; complete = (New-HordeKnown -Value $true) } }
    $text = $null
    try { $text = Read-HordeSharedText -Path $Path } catch { return [pscustomobject]@{ events = @(); present = $true; complete = (New-HordeUnknown -Reason ("the event log " + $Path + " could not be read") -ErrorRecord $_) } }
    $events = New-Object System.Collections.ArrayList
    $n = 0
    foreach ($line in ($text -split "`n")) {
        $n++
        $t = $line.Trim()
        if ($t -eq "") { continue }
        $e = $null
        try { $e = $t | ConvertFrom-Json } catch { $e = $null }
        if ($null -eq $e -or $e -isnot [System.Management.Automation.PSCustomObject]) {
            return [pscustomobject]@{ events = @(); present = $true; complete = (New-HordeUnknown -Reason ("line " + $n + " of the event log " + $Path + " is not a JSON object")) }
        }
        [void]$events.Add($e)
    }
    return [pscustomobject]@{ events = $events.ToArray(); present = $true; complete = (New-HordeKnown -Value $true) }
}

function Get-HordeWriteTime {
    # A file's last write time in UTC as an answer: known, absent when there is no such file, or
    # unknown when the file system will not say. Metadata only; the file is not opened.
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return (New-HordeAbsent -Note ("there is no file at " + $Path)) }
    try { return (New-HordeKnown -Value ([System.IO.File]::GetLastWriteTimeUtc($Path)) -ObservedAt ([System.IO.File]::GetLastWriteTimeUtc($Path))) }
    catch { return (New-HordeUnknown -Reason ("the write time of " + $Path + " could not be read") -ErrorRecord $_) }
}

function Read-HordeRuns {
    # W3, W4, W5 and W6's run-scoped logs, over EVERY run folder of every repository key: the view is
    # fleet-wide, where wezfleet's resolver narrowed to one repository through its index
    # (lib/Common.ps1:235-242). A folder under runs\ with no run.json holds no run (the one such
    # folder on 2026-09-30, "handoffs", holds notes) and is not counted.
    #
    # Returns { runs; byFleetId; runsComplete; rostersComplete; reportsComplete }, each run
    # { runId; repoKey; dir; manifest; roster; closed; entries; sessions } where
    #   manifest  the parsed run.json, or $null when unreadable
    #   closed    an answer: known true when run.json has a closedAt, false when it has none
    #   entries   the roster's sessions[] entries, each with its id as text
    #   sessions  fleet id -> { dir; events (Read-HordeEventLog); cmdlogAt (Get-HordeWriteTime) }
    param([string]$Root)
    $runGaps = New-HordeGapList
    $rosterGaps = New-HordeGapList
    $reportGaps = New-HordeGapList
    $runs = New-Object System.Collections.ArrayList
    $repos = Get-HordeListing -Dir $Root -Gaps $runGaps -Label "wezfleet root" -Directory
    foreach ($repo in @($repos | Where-Object { $null -ne $_ })) {
        $runsDir = Join-Path $repo.FullName "runs"
        if (-not (Test-Path -LiteralPath $runsDir -PathType Container)) { continue }
        $runDirs = Get-HordeListing -Dir $runsDir -Gaps $runGaps -Label ("runs of " + $repo.Name) -Directory
        foreach ($rd in @($runDirs | Where-Object { $null -ne $_ })) {
            $manifestPath = Join-Path $rd.FullName "run.json"
            if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { continue }
            $manifest = Read-HordeJsonFile -Path $manifestPath -Gaps $runGaps -Label ("run manifest " + $repo.Name + "\" + $rd.Name)
            $closed = New-HordeUnknown -Reason ("the run manifest of " + $rd.Name + " could not be read")
            if ($null -ne $manifest) {
                $ca = $manifest.PSObject.Properties["closedAt"]
                $closed = New-HordeKnown -Value ($null -ne $ca -and $null -ne $ca.Value -and "$($ca.Value)" -ne "")
            }
            $roster = $null
            $rosterPath = Join-Path $rd.FullName "roster.json"
            if (Test-Path -LiteralPath $rosterPath -PathType Leaf) { $roster = Read-HordeJsonFile -Path $rosterPath -Gaps $rosterGaps -Label ("roster " + $rd.Name) }
            else { [void]$rosterGaps.Add("run " + $rd.Name + " has no roster") }
            $entries = New-Object System.Collections.ArrayList
            if ($null -ne $roster) {
                $sp = $roster.PSObject.Properties["sessions"]
                if ($null -eq $sp -or $null -eq $sp.Value) { [void]$rosterGaps.Add("roster " + $rd.Name + " has no sessions list") }
                else {
                    foreach ($e in @($sp.Value)) {
                        $idf = Get-HordeField -Record $e -Name "id"
                        if ($idf.state -ne "known" -or "$($idf.value)" -eq "") { [void]$rosterGaps.Add("roster " + $rd.Name + " has an entry with no id"); continue }
                        [void]$entries.Add([pscustomobject]@{ id = "$($idf.value)"; entry = $e })
                    }
                }
            }
            $sessions = @{}
            $sessDir = Join-Path $rd.FullName "sessions"
            $sessFolders = Get-HordeListing -Dir $sessDir -Gaps $reportGaps -Label ("sessions of run " + $rd.Name) -Directory -MissingIsEmpty
            foreach ($sf in @($sessFolders | Where-Object { $null -ne $_ })) {
                $ev = Read-HordeEventLog -Path (Join-Path $sf.FullName "events.jsonl")
                if ($ev.complete.state -ne "known") { [void]$reportGaps.Add($ev.complete.reason) }
                $sessions[$sf.Name] = [pscustomobject]@{ dir = $sf.FullName; events = $ev; cmdlogAt = (Get-HordeWriteTime -Path (Join-Path $sf.FullName "cmdlog.txt")) }
            }
            [void]$runs.Add([pscustomobject]@{ runId = $rd.Name; repoKey = $repo.Name; dir = $rd.FullName; manifest = $manifest; roster = $roster
                                              closed = $closed; entries = $entries.ToArray(); sessions = $sessions })
        }
    }
    # Fleet id -> the runs whose roster lists it, so a lookup does not scan every run (194 on the
    # measuring machine; a scan per session made the projection take 13 ms per lookup).
    $byFleetId = @{}
    foreach ($run in $runs) {
        foreach ($e in @($run.entries)) {
            if (-not $byFleetId.ContainsKey($e.id)) { $byFleetId[$e.id] = New-Object System.Collections.ArrayList }
            if (-not $byFleetId[$e.id].Contains($run)) { [void]$byFleetId[$e.id].Add($run) }
        }
    }
    return [pscustomobject]@{ runs = $runs.ToArray(); byFleetId = $byFleetId; runsComplete = (ConvertTo-HordeCompleteness $runGaps)
                              rostersComplete = (ConvertTo-HordeCompleteness $rosterGaps); reportsComplete = (ConvertTo-HordeCompleteness $reportGaps) }
}

function Read-HordeWezfleetState {
    # Every wezfleet store the view reads. Returns { root; registry; claims; runs; looseDir }.
    param([string]$Root = (Get-HordeWezfleetRoot))
    return [pscustomobject]@{
        PSTypeName = "Horde.WezfleetState"
        root = $Root
        registry = (Read-HordeRegistry -Root $Root)
        claims = (Read-HordeClaims -Root $Root)
        runs = (Read-HordeRuns -Root $Root)
        looseDir = (Join-Path $Root "loose")
    }
}
