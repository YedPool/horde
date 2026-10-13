# core/WakeFiles - the files under <home>\wake, and the journal lines written to them.
#
# WHY APART. The wake watcher (core/Wake.ps1) only wakes, and the restore source (core/RestoreSource.ps1)
# only posts mail; each decides without reading a clock or a file, and both write what they did - or, in
# shadow, would have done - to one journal that `horde wake status` shows. What the two share is here,
# and only here: the journal's line, the folder, the write that replaces a file whole, and the heartbeat.
# Neither loads the other.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "Home.ps1")
. (Join-Path $PSScriptRoot "FileAtomic.ps1")
. (Join-Path $PSScriptRoot "ReadShared.ps1")

# After how long with no heartbeat the watcher is called stale: 40 passes at the default tick of 3 s.
$script:HordeWakeStaleSeconds = 120

function New-HordeWakeEntry {
    # One journal line: { at; kind; id; outcome; reason }, and messageId for a mail.
    param([datetime]$At, [string]$Kind, [string]$Id = "", [string]$Outcome = "", [string]$Reason = "", [string]$MessageId = "")
    $e = [ordered]@{ at = $At; kind = $Kind; id = $Id; outcome = $Outcome; reason = $Reason }
    if ($MessageId -ne "") { $e["messageId"] = $MessageId }
    return [pscustomobject]$e
}

function Select-HordeWakeNewEntries {
    # The entries worth a journal line, given what the last pass could not read. A skip-unknown is
    # written when it starts, or when its reason changes, and not on every pass while it lasts: at a
    # tick of 3 s one unreadable session would otherwise write 28,800 lines a day. Returns
    # { entries; unknown }, unknown being this pass's table (id -> reason) to hand to the next call.
    param($Entries, $Unknown = @{})
    $keep = New-Object System.Collections.ArrayList
    $now = @{}
    foreach ($e in @($Entries)) {
        if ($null -eq $e) { continue }
        if ("$($e.kind)" -cne "skip-unknown") { [void]$keep.Add($e); continue }
        $now["$($e.id)"] = "$($e.reason)"
        if ($null -ne $Unknown -and $Unknown.ContainsKey("$($e.id)") -and "$($Unknown["$($e.id)"])" -ceq "$($e.reason)") { continue }
        [void]$keep.Add($e)
    }
    return [pscustomobject]@{ entries = $keep.ToArray(); unknown = $now }
}

function Get-HordeWakeFolder {
    param([string]$HordeHome = (Get-HordeHome))
    return (Join-Path $HordeHome "wake")
}

function Get-HordeWakeStateFile {
    # The path of one of the state files a run keeps: <home>\wake\<name>.json for a live run, and
    # <name>-shadow.json for a shadow run. TWO FILES, BECAUSE SHADOW MUST NOT TOUCH WHAT A LIVE RUN
    # READS. The first version kept one of each, and the review of PR #207 found what a shadow run left
    # in them: back-offs for nudges it never sent, and - worse - the ids of resume mails it never posted,
    # marked posted, so a live watcher started later would never have posted them.
    param([Parameter(Mandatory = $true)][string]$Name, [switch]$Shadow, [string]$HordeHome = (Get-HordeHome))
    $leaf = $Name + ".json"
    if ($Shadow) { $leaf = $Name + "-shadow.json" }
    return (Join-Path (Get-HordeWakeFolder -HordeHome $HordeHome) $leaf)
}

function Get-HordeWakeStaleSeconds {
    return $script:HordeWakeStaleSeconds
}

function ConvertTo-HordeWakeTimeText {
    # A UTC time as text that reads back as the same instant.
    param([datetime]$At)
    return $At.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertFrom-HordeWakeTimeText {
    # The time ConvertTo-HordeWakeTimeText wrote, as UTC, or $null when it is not one. Text with no
    # zone is not a time here: it cannot be placed (core/Tristate.ps1).
    param($Text)
    if ($Text -is [datetime]) { return $Text.ToUniversalTime() }
    $parsed = [datetime]::MinValue
    if ($Text -isnot [string] -or -not [datetime]::TryParse($Text, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) { return $null }
    if ($parsed.Kind -eq [System.DateTimeKind]::Unspecified) { return $null }
    return $parsed.ToUniversalTime()
}

function Write-HordeWakeFile {
    # Replace one file under the wake folder whole: written beside it, then renamed over it in one step
    # (core/FileAtomic.ps1), so a reader sees the old file or the new one and never half of either.
    param([string]$Path, [string]$Text)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $temp = $Path + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    [System.IO.File]::WriteAllText($temp, $Text, (New-Object System.Text.UTF8Encoding($false)))
    try { Move-HordeFileAtomic -From $temp -To $Path }
    catch { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue; throw }
}

function Write-HordeWakeJournal {
    # Append each entry to journal.jsonl as one line of JSON. Returns how many lines it wrote.
    param($Entries, [string]$HordeHome = (Get-HordeHome))
    $lines = New-Object System.Collections.ArrayList
    foreach ($e in @($Entries)) {
        if ($null -eq $e) { continue }
        $row = [ordered]@{ at = (ConvertTo-HordeWakeTimeText $e.at); kind = "$($e.kind)"; id = "$($e.id)"; outcome = "$($e.outcome)"; reason = "$($e.reason)" }
        if ($null -ne $e.PSObject.Properties["messageId"]) { $row["messageId"] = "$($e.messageId)" }
        [void]$lines.Add((ConvertTo-Json -InputObject $row -Compress))
    }
    if ($lines.Count -eq 0) { return 0 }
    $dir = Get-HordeWakeFolder -HordeHome $HordeHome
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::AppendAllText((Join-Path $dir "journal.jsonl"), (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    return $lines.Count
}

function Read-HordeWakeJournalTail {
    # The journal's last -Count lines, as they were written; none when there is no journal.
    param([int]$Count = 10, [string]$HordeHome = (Get-HordeHome))
    $path = Join-Path (Get-HordeWakeFolder -HordeHome $HordeHome) "journal.jsonl"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
    $lines = @((Read-HordeSharedText -Path $path) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    if ($lines.Count -le $Count) { return $lines }
    return @($lines[($lines.Count - $Count)..($lines.Count - 1)])
}

function Write-HordeWakeHeartbeat {
    # heartbeat.json, replaced whole every pass: { at; pid; pass; shadow }. It is how anything else
    # tells a watcher that is running from one that is not.
    param([Parameter(Mandatory = $true)][datetime]$At, [Parameter(Mandatory = $true)][int]$ProcessId, [Parameter(Mandatory = $true)][long]$Pass, [switch]$Shadow, [string]$HordeHome = (Get-HordeHome))
    $beat = [ordered]@{ at = (ConvertTo-HordeWakeTimeText $At); pid = $ProcessId; pass = $Pass; shadow = [bool]$Shadow }
    Write-HordeWakeFile -Path (Join-Path (Get-HordeWakeFolder -HordeHome $HordeHome) "heartbeat.json") -Text (ConvertTo-Json -InputObject $beat -Compress)
}

function Read-HordeWakeHeartbeat {
    # The last heartbeat: known { at; pid; pass; shadow }, absent when the watcher never ran here, or
    # unknown when the file cannot be read as one.
    param([string]$HordeHome = (Get-HordeHome))
    $path = Join-Path (Get-HordeWakeFolder -HordeHome $HordeHome) "heartbeat.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return (New-HordeAbsent -Note "the wake watcher has never run in this home: there is no heartbeat") }
    try { $j = (Read-HordeSharedText -Path $path) | ConvertFrom-Json }
    catch { return (New-HordeUnknown -Reason "the heartbeat could not be read" -ErrorRecord $_) }
    $at = $null
    if ($null -ne $j -and $null -ne $j.PSObject.Properties["at"]) { $at = ConvertFrom-HordeWakeTimeText $j.at }
    if ($null -eq $at) { return (New-HordeUnknown -Reason "the heartbeat holds no time") }
    $beat = [ordered]@{ at = $at; pid = 0; pass = [long]0; shadow = $false }
    foreach ($n in @("pid", "pass", "shadow")) { if ($null -ne $j.PSObject.Properties[$n]) { $beat[$n] = $j.$n } }
    return (New-HordeKnown -Value ([pscustomobject]$beat) -ObservedAt $at)
}
