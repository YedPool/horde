# core/MetricsCollect - `horde metrics collect`: summarise every transcript that is new or changed
# since the last run into the metrics store, and nothing else.
#
# WHY IT EXISTS. The founder, 2026-10-02: "I want the metrics collector on until we have a clear
# initial method for when to use a real session, when an agent etc." Summarize records what a person
# names; collect finds the transcripts itself, from every engine's declared stores
# (agents/<name>/stores.json, "transcripts"), so a scheduled run (core/Schedule.ps1) keeps the store
# current without anyone naming a file.
#
# THE RULES, each one a test in test/test-metrics-collect.ps1:
#   - THE GATE EXACTLY AS SUMMARIZE: nothing is read or written when it is off, and nothing is written
#     when it is refused (core/MetricsStore.ps1). Every record passes Get-HordeMetricsWriteDecision, so
#     nothing that began before consent is recorded (decision 2, no backfill).
#   - INCREMENTAL AND IDEMPOTENT: an index, <metrics>\collect-index.json, maps each transcript's path to
#     the size and modification time it had when it was last collected, what became of it, and its
#     record. A run with nothing new or changed writes nothing at all, the index included. A changed
#     transcript replaces its record; it never adds a second one. A transcript that is gone leaves
#     the index, and its record stays: the measure of work done does not vanish with the file.
#   - ONE FILE AT A TIME (Measure-HordeTranscriptFile), so the peak memory is one transcript's running
#     totals, whatever the number of files.
#   - STILL BEING WRITTEN: a transcript modified within the last -SettleMinutes is recorded as
#     provisional, says so in its record ("collection"), and is collected again once it settles.
#   - NEVER IN AN ENGINE'S FOLDERS: transcripts are opened read-only and shared (core/ReadShared.ps1),
#     and the metrics folder - index included - is refused inside any engine's store
#     (Get-HordeMetricsWriteDecision).
#
# THE INDEX HOLDS PATHS, the one place in the store that does: it is Horde's own bookkeeping, never a
# record, and a path is what says that a file is the one seen before. A record still holds only the
# transcript's file name (core/MetricsStore.ps1).
#
# A FILE LAST WRITTEN BEFORE CONSENT IS NOT READ. Every event in it is older than its last write, so it
# began before enabledAt and summarize would not record it; collect indexes it unread, which keeps the
# first run over years of transcripts from reading them all only to record none. A file that began
# before consent and is still growing is read once, and while it only grows it is not read again: its
# first event cannot move later.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). Needs core/Tristate.ps1,
# core/ReadShared.ps1, core/Home.ps1, core/Transcript.ps1, core/Price.ps1, core/Metrics.ps1,
# core/MetricsStore.ps1, core/MetricsReport.ps1, and the adapters loaded.

$script:HordeCollectSettleMinutes = 10

function Get-HordeCollectIndexPath { return (Join-Path (Get-HordeMetricsDir) "collect-index.json") }

function Read-HordeCollectIndex {
    # The index as { entries (a hashtable by path); note }. A missing index is empty. One that cannot be
    # read is empty too, and note says so: every transcript is then collected again, which replaces
    # each record with the same one - the cost is time, never a duplicate.
    $path = Get-HordeCollectIndexPath
    $entries = @{}
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return [pscustomobject]@{ entries = $entries; note = "" } }
    Add-Type -AssemblyName System.Web.Extensions
    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $ser.MaxJsonLength = [int]::MaxValue
    $doc = $null
    try { $doc = $ser.DeserializeObject((Read-HordeSharedText -Path $path)) } catch { $doc = $null }
    if ($doc -isnot [System.Collections.IDictionary] -or $doc["schemaVersion"] -ne 1 -or $doc["entries"] -isnot [System.Collections.IDictionary]) {
        return [pscustomobject]@{ entries = $entries; note = "the index could not be read, so every transcript is collected again" }
    }
    foreach ($k in @($doc["entries"].Keys)) {
        $e = $doc["entries"][$k]
        if ($e -isnot [System.Collections.IDictionary]) { continue }
        $entries[$k] = [pscustomobject]@{
            size = [long]$e["size"]; modifiedTicks = [long]$e["modifiedTicks"]; outcome = "$($e["outcome"])"; record = "$($e["record"])"
            firstEventTicks = [long]$e["firstEventTicks"]; enabledAtTicks = [long]$e["enabledAtTicks"]; reason = "$($e["reason"])"
        }
    }
    return [pscustomobject]@{ entries = $entries; note = "" }
}

function Write-HordeCollectIndex {
    param([Parameter(Mandatory = $true)][hashtable]$Entries)
    $out = [ordered]@{}
    foreach ($k in @($Entries.Keys | Sort-Object)) {
        $e = $Entries[$k]
        $out[$k] = [ordered]@{ size = $e.size; modifiedTicks = $e.modifiedTicks; outcome = $e.outcome; record = $e.record; firstEventTicks = $e.firstEventTicks; enabledAtTicks = $e.enabledAtTicks; reason = $e.reason }
    }
    $doc = [ordered]@{ schemaVersion = 1; kind = "metrics.collectIndex"; entries = $out }
    Write-HordeMetricsFile -Path (Get-HordeCollectIndexPath) -Text (ConvertTo-Json -InputObject $doc -Depth 6)
}

function Get-HordeCollectFiles {
    # Every .jsonl under every engine's declared transcript folders, as full paths in name order, once
    # each. Extension compared here, not with -Filter, which also matches 8.3 short names (cli/Commands.ps1,
    # measured 2026-09-29).
    param([Parameter(Mandatory = $true)]$Stores)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $files = New-Object System.Collections.ArrayList
    foreach ($s in @($Stores)) {
        foreach ($dir in @($s.transcripts)) {
            if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
            foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Extension -ieq ".jsonl" })) {
                if ($seen.Add($f.FullName)) { [void]$files.Add($f) }
            }
        }
    }
    return @($files | Sort-Object FullName)
}

function Get-HordeCollectRecordName {
    # The record name for a transcript: its file name, as summarize uses, unless another indexed
    # transcript already holds that record - then the name carries 8 hex digits of the path's hash, so
    # two files never overwrite each other's record.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Adapter, [Parameter(Mandatory = $true)][hashtable]$Entries)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $id = $Adapter + "/" + $name
    foreach ($k in @($Entries.Keys)) {
        if ($k -ne $Path -and $Entries[$k].record -eq $id) {
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try { $hash = -join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Path.ToLowerInvariant())) | Select-Object -First 4 | ForEach-Object { $_.ToString("x2") }) } finally { $sha.Dispose() }
            return ($name + "." + $hash)
        }
    }
    return $name
}

function Invoke-HordeMetricsCollect {
    # One collect run. Returns { state; reason; found; unchanged; read; recorded; provisional;
    # beforeConsent; unreadable; noAdapter; removed; wroteIndex; rows }. state is "off", "refused",
    # "busy" or "done"; only "done" may have written anything.
    # -Now and -RepoRoot are for tests; -SettleMinutes is how long a transcript must be still before
    # its record is final.
    param([int]$SettleMinutes = $script:HordeCollectSettleMinutes, $Now = $null, [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot))
    if ($null -eq $Now) { $Now = [datetime]::UtcNow }
    $res = [ordered]@{ state = ""; reason = ""; found = 0; unchanged = 0; read = 0; recorded = 0; provisional = 0; beforeConsent = 0; notRecorded = 0; unreadable = 0; noAdapter = 0; removed = 0; wroteIndex = $false; rows = (New-Object System.Collections.ArrayList) }
    $gate = Read-HordeMetricsGate
    if ($gate.state -eq "absent" -or ($gate.state -eq "known" -and $gate.value.level -cne "usage")) { $res.state = "off"; $res.reason = "metrics are off; nothing was collected"; return [pscustomobject]$res }
    if ($gate.state -ne "known") { $res.state = "refused"; $res.reason = ("the gate is refused, so nothing was collected: " + $gate.reason); return [pscustomobject]$res }
    # The folder itself must be allowed before anything - the index included - is written to it.
    $probe = Get-HordeMetricsWriteDecision -Gate $gate -FirstEventAt (New-HordeKnown -Value $gate.value.enabledAt) -RepoRoot $RepoRoot
    if (-not $probe.write) { $res.state = "refused"; $res.reason = ("nothing was collected: " + $probe.reason); return [pscustomobject]$res }
    $stores = Get-HordeAgentStores -Root $RepoRoot
    if ($stores.state -ne "known") { $res.state = "refused"; $res.reason = ("nothing was collected: " + $stores.reason); return [pscustomobject]$res }

    # ONE RUN AT A TIME: two runs would each rewrite the index from what they read. A file held with no
    # sharing is released by the system if its holder dies, so a killed run never leaves it locked.
    $dir = Get-HordeMetricsDir
    [void][System.IO.Directory]::CreateDirectory($dir)
    $lock = $null
    try { $lock = [System.IO.File]::Open((Join-Path $dir "collect.lock"), [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None) }
    catch { $res.state = "busy"; $res.reason = "another collect is running; this one did nothing"; return [pscustomobject]$res }
    try {
        $index = Read-HordeCollectIndex
        if ($index.note -ne "") { $res.reason = $index.note }
        $entries = $index.entries
        $dirty = ($index.note -ne "")
        $table = Read-HordePriceBook
        $enabledTicks = $gate.value.enabledAt.Ticks
        $settleTicks = [TimeSpan]::FromMinutes($SettleMinutes).Ticks
        $present = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($f in (Get-HordeCollectFiles -Stores $stores.value)) {
            $res.found++
            $path = $f.FullName
            [void]$present.Add($path)
            $size = $f.Length
            $mod = $f.LastWriteTimeUtc.Ticks
            $settled = (($Now.Ticks - $mod) -ge $settleTicks)
            $old = $entries[$path]
            if ($null -ne $old -and $old.size -eq $size -and $old.modifiedTicks -eq $mod -and $old.enabledAtTicks -eq $enabledTicks) {
                # Unchanged. A provisional record is collected again only once its file has settled.
                if ($old.outcome -ne "provisional" -or -not $settled) { $res.unchanged++; continue }
            }
            $entry = [pscustomobject]@{ size = $size; modifiedTicks = $mod; outcome = ""; record = ""; firstEventTicks = [long]0; enabledAtTicks = $enabledTicks; reason = "" }
            if ($null -ne $old) { $entry.record = $old.record }
            if ($mod -lt $enabledTicks) {
                $entry.outcome = "beforeConsent"; $entry.reason = "last written before metrics were enabled"
                $entries[$path] = $entry; $dirty = $true; $res.beforeConsent++; continue
            }
            if ($null -ne $old -and $old.outcome -eq "beforeConsent" -and $old.enabledAtTicks -eq $enabledTicks -and $old.firstEventTicks -gt 0 -and $size -ge $old.size) {
                $entry.outcome = "beforeConsent"; $entry.firstEventTicks = $old.firstEventTicks; $entry.reason = "began before metrics were enabled, and has only grown since"
                $entries[$path] = $entry; $dirty = $true; $res.beforeConsent++; continue
            }
            $res.read++
            $measured = Measure-HordeTranscriptFile -Path $path -PriceTable $table
            if ($measured.state -ne "known") {
                if ($measured.reason -like "no adapter reads*") { $entry.outcome = "noAdapter"; $res.noAdapter++ } else { $entry.outcome = "unreadable"; $res.unreadable++ }
                $entry.reason = $measured.reason
                $entries[$path] = $entry; $dirty = $true; continue
            }
            $mv = $measured.value
            if ($mv.worker.firstEventAt.state -eq "known") { $entry.firstEventTicks = $mv.worker.firstEventAt.value.Ticks }
            $decision = Get-HordeMetricsWriteDecision -Gate $gate -FirstEventAt $mv.worker.firstEventAt -RepoRoot $RepoRoot
            if (-not $decision.write) {
                if ($mv.worker.firstEventAt.state -eq "known" -and $mv.worker.firstEventAt.value -lt $gate.value.enabledAt) { $entry.outcome = "beforeConsent"; $res.beforeConsent++ }
                else { $entry.outcome = "notRecorded"; $res.notRecorded++ }
                $entry.reason = $decision.reason
                $entries[$path] = $entry; $dirty = $true; continue
            }
            $adapter = $mv.read.adapter
            $name = $null
            if ($entry.record -like ($adapter + "/*")) { $name = $entry.record.Substring($adapter.Length + 1) }
            else { $name = Get-HordeCollectRecordName -Path $path -Adapter $adapter -Entries $entries }
            $record = $mv.record
            $modifiedAt = New-Object DateTime ($mod, [DateTimeKind]::Utc)
            $record["collection"] = [ordered]@{
                provisional = (-not $settled)
                why = $(if ($settled) { "" } else { "the transcript was written to within the last " + $SettleMinutes + " minutes, so it may still grow; it will be collected again once it is still" })
                sourceBytes = $size
                sourceModifiedAt = (ConvertTo-HordeJsonSafe $modifiedAt)
            }
            $written = Write-HordeMetricsRecord -Record $record -Adapter $adapter -Name $name
            $entry.record = $adapter + "/" + $name
            $entry.outcome = $(if ($settled) { "recorded" } else { "provisional" })
            $entries[$path] = $entry; $dirty = $true
            $res.recorded++
            if (-not $settled) { $res.provisional++ }
            [void]$res.rows.Add([pscustomobject]@{ file = (Split-Path -Leaf $path); record = $entry.record; provisional = (-not $settled); written = $written })
        }
        # A transcript that is gone leaves the index; its record stays.
        foreach ($k in @($entries.Keys)) {
            if (-not $present.Contains($k)) { $entries.Remove($k); $dirty = $true; $res.removed++ }
        }
        if ($dirty) { Write-HordeCollectIndex -Entries $entries; $res.wroteIndex = $true }
        $res.state = "done"
    } finally { $lock.Dispose() }
    return [pscustomobject]$res
}

function Format-HordeMetricsCollect {
    # The lines a person, or a scheduler's log, sees for one run.
    param([Parameter(Mandatory = $true)]$Result)
    $r = $Result
    if ($r.state -ne "done") { return @("collect: " + $r.state + " - " + $r.reason) }
    $lines = @("collect: " + $r.found + " transcripts; " + $r.unchanged + " unchanged; " + $r.read + " read; " + $r.recorded + " recorded (" + $r.provisional + " provisional); " + $r.beforeConsent + " from before consent; " + $r.notRecorded + " not recorded; " + $r.noAdapter + " no adapter; " + $r.unreadable + " not readable; " + $r.removed + " gone from the index")
    if ($r.reason -ne "") { $lines += ("collect: " + $r.reason) }
    if (-not $r.wroteIndex) { $lines += "collect: nothing new or changed, nothing written" }
    return $lines
}

function Invoke-HordeMetricsSchedule {
    # `horde metrics schedule install|remove|status`: the one scheduled job that runs collect, through
    # whichever scheduler this machine has (core/Schedule.ps1). Returns the lines to show; throws when
    # the action cannot be done. -TaskName exists so a test acts only on a job it named itself.
    #
    # INSTALL ONLY WHILE THE GATE SAYS USAGE: a job that collects nothing every 30 minutes is a job
    # nobody needs, and the gate stays the one switch. Collect checks the gate again on every run, so
    # turning metrics off later stops the recording at once, with or without removing the job.
    param([Parameter(Mandatory = $true)][ValidateSet("install", "remove", "status")][string]$Action, [string]$TaskName = $script:HordeCollectJobName, [switch]$Disabled, [Parameter(Mandatory = $true)][string]$HordeScript)
    $sched = Get-HordeScheduler
    if ($sched.state -ne "known") { throw ("cannot schedule collect: " + $sched.reason) }
    $s = $sched.value
    $gate = Read-HordeMetricsGate
    $gateText = "off"
    if ($gate.state -eq "known") { $gateText = $gate.value.level } elseif ($gate.state -eq "unknown") { $gateText = "refused (" + $gate.reason + ")" }
    switch ($Action) {
        "install" {
            if ($gate.state -ne "known" -or $gate.value.level -cne "usage") { throw ("metrics are " + $gateText + ", so a collect job would record nothing; it was not installed") }
            $job = New-HordeCollectJob -HordeScript $HordeScript -Name $TaskName -Disabled:$Disabled
            & $s.install $job
            $st = & $s.status $TaskName
            if ($st.state -ne "known") { throw ("the " + $s.name + " did not keep the job '" + $TaskName + "': " + $st.reason) }
            return @("installed '" + $TaskName + "' with " + $s.name + ": every " + $job.everyMinutes + " minutes, low priority, stopped after " + $job.timeLimitMinutes + " minutes" + $(if ($Disabled) { "; DISABLED, so it never runs" } else { "" }), ("runs: " + $job.program + " " + $job.arguments))
        }
        "remove" {
            $gone = & $s.remove $TaskName
            if ($gone) { return @("removed '" + $TaskName + "' from " + $s.name) }
            return @("no job named '" + $TaskName + "' in " + $s.name + "; nothing to remove")
        }
        "status" {
            $st = & $s.status $TaskName
            $lines = @("metrics gate: " + $gateText)
            if ($st.state -ne "known") { return ($lines + @("'" + $TaskName + "' is not installed in " + $s.name)) }
            $v = $st.value
            $fmt = { param($t) if ($null -eq $t) { "never" } else { $t.ToString("yyyy-MM-dd HH:mm 'UTC'", [System.Globalization.CultureInfo]::InvariantCulture) } }
            $lines += ("'" + $TaskName + "' in " + $s.name + ": " + $(if ($v.enabled) { "enabled" } else { "DISABLED" }) + ", " + $v.state + ", every " + $v.everyMinutes + " minutes, logon " + $v.logonType)
            $lines += ("last run " + (& $fmt $v.lastRunAt) + " (result " + $v.lastResult + "), next run " + (& $fmt $v.nextRunAt))
            $lines += ("runs: " + $v.program + " " + $v.arguments)
            return $lines
        }
    }
}
