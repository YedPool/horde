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

# After how long with no heartbeat the watcher is called stale, at the least: 40 ticks of the default 3 s.
$script:HordeWakeStaleSeconds = 120
# How large the journal grows before it is set aside: 4 MiB, about 20,000 lines of 200 bytes.
$script:HordeWakeJournalMaxBytes = 4194304

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

function Get-HordeWakeModeFile {
    # The path of the journal or the heartbeat of one mode: <home>\wake\<stem><ext> for a live run and
    # <stem>-shadow<ext> for a shadow run. PER MODE, like the state files and the lock. The first version
    # had one of each, and the review of PR #208 found what two modes do with them: a shadow run kept
    # heartbeat.json fresh, so a live watcher that had died read as alive; and two processes appended
    # to one journal.jsonl, where their lines can collide.
    param([Parameter(Mandatory = $true)][string]$Stem, [Parameter(Mandatory = $true)][string]$Extension, [switch]$Shadow, [string]$HordeHome = (Get-HordeHome))
    $leaf = $Stem + $Extension
    if ($Shadow) { $leaf = $Stem + "-shadow" + $Extension }
    return (Join-Path (Get-HordeWakeFolder -HordeHome $HordeHome) $leaf)
}

function Get-HordeWakeStaleSeconds {
    # After how long with no heartbeat a watcher that ticks every -TickSeconds is stale: three ticks,
    # and never less than 120 s. The first version said 120 s whatever the tick, while the command took
    # a tick of up to an hour (review of PR #207; it now takes at most 300 s): such a watcher was "stale" for all but two minutes
    # of every hour while running perfectly. The tick is written into the heartbeat for this.
    param([int]$TickSeconds = 0)
    return [int][System.Math]::Max($script:HordeWakeStaleSeconds, 3 * $TickSeconds)
}

function Write-HordeWakeJournal {
    # Append each entry to the mode's journal (journal.jsonl, or journal-shadow.jsonl with -Shadow) as
    # one line of JSON. Returns how many lines it wrote.
    # THE JOURNAL IS BOUNDED (review of PR #207: it only grew). When it has reached -MaxBytes it is set
    # aside under the same name with .1 before its extension, replacing the one set aside before, and a new one is begun: at most two
    # files, and the newest lines are never the ones lost.
    param($Entries, [switch]$Shadow, [string]$HordeHome = (Get-HordeHome), [long]$MaxBytes = $script:HordeWakeJournalMaxBytes)
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
    $path = Get-HordeWakeModeFile -Stem "journal" -Extension ".jsonl" -Shadow:$Shadow -HordeHome $HordeHome
    if ((Test-Path -LiteralPath $path -PathType Leaf) -and (New-Object System.IO.FileInfo($path)).Length -ge $MaxBytes) { Move-HordeFileAtomic -From $path -To (Get-HordeWakeModeFile -Stem "journal" -Extension ".1.jsonl" -Shadow:$Shadow -HordeHome $HordeHome) }
    [System.IO.File]::AppendAllText($path, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    return $lines.Count
}

function Read-HordeWakeJournalTail {
    # The last -Count lines of the mode's journal, as they were written; none when there is no journal. Just after
    # the journal was set aside the new one is short, so the tail is filled from the one before it.
    param([int]$Count = 10, [switch]$Shadow, [string]$HordeHome = (Get-HordeHome))
    $lines = @()
    foreach ($ext in @(".1.jsonl", ".jsonl")) {
        $path = Get-HordeWakeModeFile -Stem "journal" -Extension $ext -Shadow:$Shadow -HordeHome $HordeHome
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $lines = @($lines) + @((Read-HordeSharedText -Path $path) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    }
    if ($lines.Count -le $Count) { return $lines }
    return @($lines[($lines.Count - $Count)..($lines.Count - 1)])
}

function Write-HordeWakeHeartbeat {
    # The mode's heartbeat (heartbeat.json, or heartbeat-shadow.json with -Shadow), replaced whole every pass: { at; pid; pass; shadow; tickSeconds }. It is how
    # anything else tells a watcher that is running from one that is not; tickSeconds is how often this
    # watcher beats, so a reader knows how long a silence is too long (Get-HordeWakeStaleSeconds).
    param([Parameter(Mandatory = $true)][datetime]$At, [Parameter(Mandatory = $true)][int]$ProcessId, [Parameter(Mandatory = $true)][long]$Pass, [switch]$Shadow, [int]$TickSeconds = 0, [string]$HordeHome = (Get-HordeHome))
    $beat = [ordered]@{ at = (ConvertTo-HordeWakeTimeText $At); pid = $ProcessId; pass = $Pass; shadow = [bool]$Shadow; tickSeconds = $TickSeconds }
    Write-HordeWakeFile -Path (Get-HordeWakeModeFile -Stem "heartbeat" -Extension ".json" -Shadow:$Shadow -HordeHome $HordeHome) -Text (ConvertTo-Json -InputObject $beat -Compress)
}

function Read-HordeWakeHeartbeat {
    # The mode's last heartbeat: known { at; pid; pass; shadow; tickSeconds }, absent when the watcher never ran
    # here, or unknown when the file cannot be read as one.
    param([switch]$Shadow, [string]$HordeHome = (Get-HordeHome))
    $path = Get-HordeWakeModeFile -Stem "heartbeat" -Extension ".json" -Shadow:$Shadow -HordeHome $HordeHome
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return (New-HordeAbsent -Note "it has never run in this home: there is no heartbeat") }
    try { $j = (Read-HordeSharedText -Path $path) | ConvertFrom-Json }
    catch { return (New-HordeUnknown -Reason "the heartbeat could not be read" -ErrorRecord $_) }
    $at = $null
    if ($null -ne $j -and $null -ne $j.PSObject.Properties["at"]) { $at = ConvertFrom-HordeWakeTimeText $j.at }
    if ($null -eq $at) { return (New-HordeUnknown -Reason "the heartbeat holds no time") }
    $beat = [ordered]@{ at = $at; pid = 0; pass = [long]0; shadow = $false; tickSeconds = 0 }
    foreach ($n in @("pid", "pass", "shadow", "tickSeconds")) { if ($null -ne $j.PSObject.Properties[$n]) { $beat[$n] = $j.$n } }
    return (New-HordeKnown -Value ([pscustomobject]$beat) -ObservedAt $at)
}

function Test-HordeWakeSharingViolation {
    # Is this failure to open a file the one that means ANOTHER PROCESS HOLDS IT - a sharing violation
    # (Win32 error 32) or a lock violation (33) - and not any other? Every failure to open the lock was
    # read as "a run is already running" (review of PR #208): a full disk, a path that is not there or a
    # file nobody may open said the same, and a person was sent looking for a second watcher that did not
    # exist while none was running at all. The error number is read from the exception's HResult, whose
    # low 16 bits are the Win32 error, on the exception itself or the one it wraps.
    param($Exception)
    $e = $Exception
    while ($null -ne $e) {
        if ($e -is [System.IO.IOException]) {
            $win32 = ($e.HResult -band 0xFFFF)
            if ($win32 -eq 32 -or $win32 -eq 33) { return $true }
        }
        $e = $e.InnerException
    }
    return $false
}

function Enter-HordeWakeLock {
    # ONE WATCHER A HOME AND A MODE. Returns the open lock - the caller keeps it for as long as it runs
    # and disposes it when it ends - or $null when another process holds it, AND ONLY THEN: any other
    # failure to open it is thrown as what it is (Test-HordeWakeSharingViolation). Two watchers on one home
    # would nudge one session twice a pass and write over each other's ledger; the first version let a
    # second one start (review of PR #207).
    # THE LOCK IS AN OPEN FILE HANDLE, NOT A PID IN A FILE. The file is opened for writing and shared for
    # reading only, so a second open for writing fails for exactly as long as the first is held, and
    # the operating system closes the handle when its process ends, however it ends. A pid written in a
    # file outlives its process, and Windows gives the same pid to another (core/Identity.ps1's second
    # rule): a lock that trusted one would block for ever after a crash, or never. The pid is written
    # inside all the same, for a person to read; nothing decides by it.
    param([switch]$Shadow, [int]$ProcessId = 0, [string]$HordeHome = (Get-HordeHome))
    $dir = Get-HordeWakeFolder -HordeHome $HordeHome
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $leaf = "run.lock"
    if ($Shadow) { $leaf = "run-shadow.lock" }
    try { $held = New-Object System.IO.FileStream((Join-Path $dir $leaf), [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read) }
    catch [System.IO.IOException] {
        if (Test-HordeWakeSharingViolation $_.Exception) { return $null }
        throw
    }
    try {
        $held.SetLength(0)
        $bytes = [System.Text.Encoding]::ASCII.GetBytes("" + $ProcessId)
        $held.Write($bytes, 0, $bytes.Length)
        $held.Flush()
    } catch { $held.Dispose(); throw }
    return $held
}
