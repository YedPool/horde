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
#   - INCREMENTAL AND IDEMPOTENT: an index, <metrics>\collect-index.json, maps each transcript to the
#     size and modification time it had when it was last collected, what became of it, and its record.
#     A run with nothing new or changed writes nothing at all, the index included. A changed transcript
#     replaces its record; it never adds a second one. A transcript that is gone leaves the index, and
#     its record stays: the measure of work done does not vanish with the file.
#   - A RECORD IS NAMED BY THE TRANSCRIPT'S OWN IDENTITY - the record key its adapter reads from the
#     file, such as its session id - never by where it is (review of PR #70, F4: a moved transcript got
#     a second record). A moved file replaces its own record.
#   - ONE BAD FILE NEVER STOPS A RUN (review of PR #70, F3): a file whose record cannot be named or
#     written is an outcome in the index, reported, and the run goes on.
#   - ONE FILE AT A TIME (Measure-HordeTranscriptFile), so the peak memory is one transcript's.
#   - STILL BEING WRITTEN: a transcript modified within the last -SettleMinutes, or that changed while
#     it was read, is recorded as provisional, says so in its record ("collection"), and is collected
#     again once it settles. One whose file is gone before it settled is flagged in its record.
#   - NEVER IN AN ENGINE'S FOLDERS: transcripts are opened read-only and shared (core/ReadShared.ps1),
#     and the metrics folder - index included - is refused inside any engine's store
#     (Get-HordeMetricsWriteDecision).
#
# THE INDEX HOLDS NO HOME PATH (review of PR #70, F6). A transcript is keyed by its engine, the root
# and folder that hold it, and its path inside that folder: "<engine>/<root label>/<folder>/<hash of the folders below>/<file>".
# The hash is SHA-256, unsalted: not a secret - a known folder name can be confirmed by hashing it - only
# not a readable path.
# A transcript that began before consent is keyed only by a hash of that, so nothing about a session
# from before consent is kept in readable form.
#
# A FILE LAST WRITTEN BEFORE CONSENT IS NOT READ, and not indexed. Every event in it is older than its
# last write, so it began before enabledAt and summarize would not record it. A file that began before
# consent and is still growing is read once, and while it only grows it is not read again: its first
# event cannot move later.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). Needs core/Tristate.ps1,
# core/ReadShared.ps1, core/Home.ps1, core/Transcript.ps1, core/Price.ps1, core/Metrics.ps1,
# core/MetricsStore.ps1, core/MetricsReport.ps1, and the adapters loaded.

# What this file calls, loaded here so the file works on its own (tools/CoreLoad.ps1).
. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "ReadShared.ps1")
. (Join-Path $PSScriptRoot "FileAtomic.ps1")
. (Join-Path $PSScriptRoot "Price.ps1")
. (Join-Path $PSScriptRoot "Schedule.ps1")
. (Join-Path $PSScriptRoot "Transcript.ps1")
. (Join-Path $PSScriptRoot "MetricsStore.ps1")
. (Join-Path $PSScriptRoot "MetricsReport.ps1")

$script:HordeCollectSettleMinutes = 10
# A run's default time budget: 15 minutes, 5 under the scheduled task's 20-minute limit
# (core/Schedule.ps1), so a scheduled run ends itself instead of being killed.
$script:HordeCollectMaxSeconds = 900
# A transcript abandoned this many runs in a row because the budget ran out inside it is "tooLarge":
# skipped from then on, counted, and named by summarize, so the rest of the backlog always proceeds.
$script:HordeCollectMaxDeferrals = 3
# The temp-name pattern of Write-HordeMetricsFile: "." + name + "." + 32 hex + ".tmp".
$script:HordeTempNamePattern = '\A\..+\.[0-9a-f]{32}\.tmp\z'
# Windows' sharing violation, the one failure to open the lock that means another run holds it.
$script:HordeSharingViolation = -2147024864

function Get-HordeCollectIndexPath { return (Join-Path (Get-HordeMetricsDir) "collect-index.json") }

function Read-HordeCollectIndex {
    # The index as { entries (a hashtable by key); note }. A missing index is empty. One that cannot be
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
    if ($doc -isnot [System.Collections.IDictionary] -or $doc["schemaVersion"] -ne 2 -or $doc["entries"] -isnot [System.Collections.IDictionary]) {
        return [pscustomobject]@{ entries = $entries; note = "the index could not be read, so every transcript is collected again" }
    }
    foreach ($k in @($doc["entries"].Keys)) {
        $e = $doc["entries"][$k]
        if ($e -isnot [System.Collections.IDictionary]) { continue }
        $entries[$k] = [pscustomobject]@{
            size = [long]$e["size"]; modifiedTicks = [long]$e["modifiedTicks"]; outcome = "$($e["outcome"])"; record = "$($e["record"])"
            firstEventTicks = [long]$e["firstEventTicks"]; enabledAtTicks = [long]$e["enabledAtTicks"]; reason = "$($e["reason"])"; deferrals = [int]$e["deferrals"]
        }
    }
    return [pscustomobject]@{ entries = $entries; note = "" }
}

function Write-HordeCollectIndex {
    # Written whole, by temp file and replace (Write-HordeMetricsFile), AFTER EVERY TRANSCRIPT (review of
    # #70, NEW-1: written once at the end, a run killed by the scheduler's time limit lost all its work,
    # and a large backlog never finished). Serialised by .NET in one call, not ConvertTo-Json, so a commit
    # per transcript stays cheap.
    param([Parameter(Mandatory = $true)][hashtable]$Entries)
    $out = [System.Collections.Generic.Dictionary[string,object]]::new()
    foreach ($k in @($Entries.Keys | Sort-Object)) {
        $e = $Entries[$k]
        $d = [System.Collections.Generic.Dictionary[string,object]]::new()
        $d["size"] = [long]$e.size; $d["modifiedTicks"] = [long]$e.modifiedTicks; $d["outcome"] = "$($e.outcome)"; $d["record"] = "$($e.record)"
        $d["firstEventTicks"] = [long]$e.firstEventTicks; $d["enabledAtTicks"] = [long]$e.enabledAtTicks; $d["reason"] = "$($e.reason)"; $d["deferrals"] = [int]$e.deferrals
        $out[$k] = $d
    }
    $doc = [System.Collections.Generic.Dictionary[string,object]]::new()
    $doc["schemaVersion"] = 2; $doc["kind"] = "metrics.collectIndex"; $doc["entries"] = $out
    Add-Type -AssemblyName System.Web.Extensions
    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $ser.MaxJsonLength = [int]::MaxValue
    Write-HordeMetricsFile -Path (Get-HordeCollectIndexPath) -Text $ser.Serialize($doc)
}

function Get-HordeHashText {
    param([string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return (-join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)) | ForEach-Object { $_.ToString("x2") })) } finally { $sha.Dispose() }
}

function Get-HordeCollectFiles {
    # Every transcript file under every engine's declared transcript folders, once each, in key order:
    # { file (FileInfo); key = "<engine>/<root label>/<folder>/<hash of the folders below>/<file>" }. The extension is the engine's own
    # (stores.json), never assumed here.
    param([Parameter(Mandatory = $true)]$Stores)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $files = New-Object System.Collections.ArrayList
    foreach ($s in @($Stores)) {
        foreach ($t in @($s.transcripts)) {
            if (-not (Test-Path -LiteralPath $t.dir -PathType Container)) { continue }
            $base = [System.IO.Path]::GetFullPath($t.dir).TrimEnd('\') + '\'
            foreach ($f in @(Get-ChildItem -LiteralPath $t.dir -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Extension -ieq $t.extension })) {
                if (-not $seen.Add($f.FullName)) { continue }
                # The folders below the engine's transcript folder are hashed: a harness names them after the
                # project, whose path spells out the user (review of #70, verification: C--Users-<name>-...).
                $rel = $f.FullName.Substring($base.Length).Replace('\', '/')
                $cut = $rel.LastIndexOf('/')
                $shown = $rel
                if ($cut -ge 0) { $shown = (Get-HordeHashText $rel.Substring(0, $cut).ToLowerInvariant()).Substring(0, 16) + "/" + $rel.Substring($cut + 1) }
                [void]$files.Add([pscustomobject]@{ file = $f; key = ($s.agent + "/" + $t.label + "/" + $shown) })
            }
        }
    }
    return @($files | Sort-Object key)
}

function Set-HordeRecordSourceGone {
    # Flag a provisional record whose transcript is gone: it can never be made final (review of PR #70, F9).
    param([Parameter(Mandatory = $true)][string]$Record)
    $parts = $Record.Split("/", 2)
    $path = Get-HordeMetricsRecordPath -Adapter $parts[0] -Name $parts[1]
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    Add-Type -AssemblyName System.Web.Extensions
    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $ser.MaxJsonLength = [int]::MaxValue
    $doc = $ser.DeserializeObject([System.IO.File]::ReadAllText($path))
    if ($doc -isnot [System.Collections.IDictionary] -or $doc["collection"] -isnot [System.Collections.IDictionary] -or $doc["collection"]["provisional"] -ne $true) { return }
    $doc["collection"]["sourceGone"] = $true
    $doc["collection"]["why"] = "its transcript is gone, so this provisional record can never be made final"
    Write-HordeMetricsFile -Path $path -Text (ConvertTo-Json -InputObject $doc -Depth 30)
}

function Test-HordeMetricsFileValid {
    # Is this file a whole, valid copy of what its name says? The index: schemaVersion 2 with entries. A
    # record: a JSON object of kind transcript.summary.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Name)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    Add-Type -AssemblyName System.Web.Extensions
    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $ser.MaxJsonLength = [int]::MaxValue
    $d = $null
    try { $d = $ser.DeserializeObject((Read-HordeSharedText -Path $Path)) } catch { return $false }
    if ($d -isnot [System.Collections.IDictionary]) { return $false }
    if ($Name -ceq "collect-index.json") { return ($d["schemaVersion"] -eq 2 -and $d["entries"] -is [System.Collections.IDictionary]) }
    return ("$($d["kind"])" -ceq "transcript.summary")
}

function Restore-HordeMetricsTemps {
    # For every file under -Dir that has temp copies (Write-HordeMetricsFile's pattern, and only that):
    # when the file is missing or invalid, the newest VALID temp becomes the file, and nothing is deleted;
    # when the file is valid, temps OLDER than it are removed, and newer ones are left for a later run. A
    # temp is never deleted while it might be the only copy. Returns what was recovered ("" when nothing),
    # and records it in <metrics>\collect-recovered.json, which summarize reports.
    param([Parameter(Mandatory = $true)][string]$Dir)
    $groups = @{}
    foreach ($tmp in @(Get-ChildItem -LiteralPath $Dir -File -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -cmatch $script:HordeTempNamePattern })) {
        $target = Join-Path $tmp.DirectoryName ($tmp.Name.Substring(1, $tmp.Name.Length - 1 - 37))
        if (-not $groups.ContainsKey($target)) { $groups[$target] = New-Object System.Collections.ArrayList }
        [void]$groups[$target].Add($tmp)
    }
    $done = New-Object System.Collections.ArrayList
    $problems = New-Object System.Collections.ArrayList
    foreach ($target in @($groups.Keys)) {
        # One file that cannot be recovered or cleaned never stops the others, nor the run.
        try {
        $name = Split-Path -Leaf $target
        $temps = @($groups[$target] | Sort-Object LastWriteTimeUtc -Descending)
        if (-not (Test-HordeMetricsFileValid -Path $target -Name $name)) {
            foreach ($tmp in $temps) {
                if (Test-HordeMetricsFileValid -Path $tmp.FullName -Name $name) {
                    Move-HordeFileAtomic -From $tmp.FullName -To $target
                    [void]$done.Add($target.Substring($Dir.Length).TrimStart('\') + " from " + $tmp.Name)
                    break
                }
            }
            continue
        }
        $at = (Get-Item -LiteralPath $target).LastWriteTimeUtc
        foreach ($tmp in $temps) { if ($tmp.LastWriteTimeUtc -lt $at) { Remove-Item -LiteralPath $tmp.FullName -Force -ErrorAction SilentlyContinue } }
        } catch { [void]$problems.Add($target.Substring($Dir.Length).TrimStart('\') + " could not be recovered or cleaned: " + $_.Exception.Message) }
    }
    $text = ""
    if ($done.Count -gt 0) {
        $text = "a write had been killed half way; recovered " + ($done -join "; ")
        $note = [ordered]@{ schemaVersion = 1; kind = "metrics.recovered"; at = (ConvertTo-HordeJsonSafe ([datetime]::UtcNow)); what = $text }
        Write-HordeMetricsFile -Path (Join-Path $Dir "collect-recovered.json") -Text (ConvertTo-Json -InputObject $note)
    }
    if ($problems.Count -gt 0) { $text = (@($text, ($problems -join "; ")) | Where-Object { $_ -ne "" }) -join "; " }
    return $text
}

function Invoke-HordeMetricsCollect {
    # One collect run. Returns { state; reason; found; unchanged; read; recorded; provisional;
    # beforeConsent; notRecorded; failed; unreadable; noAdapter; removed; wroteIndex; rows }. state is
    # "off", "refused", "busy" or "done"; only "done" may have written anything.
    # -Now and -RepoRoot are for tests; -SettleMinutes is how long a transcript must be still before
    # its record is final.
    param([int]$SettleMinutes = $script:HordeCollectSettleMinutes, $Now = $null, [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot), [int]$MaxFiles = 0, [int]$MaxSeconds = $script:HordeCollectMaxSeconds, [switch]$IncludeLarge)
    # -IncludeLarge: a person is running this, so there is no time budget, and too-large files are read
    # whole however long they take. The scheduled job never passes it.
    if ($IncludeLarge) { $MaxSeconds = [int]::MaxValue }
    if ($null -eq $Now) { $Now = [datetime]::UtcNow }
    $res = [ordered]@{ state = ""; reason = ""; found = 0; unchanged = 0; read = 0; recorded = 0; provisional = 0; beforeConsent = 0; notRecorded = 0; failed = 0; unreadable = 0; noAdapter = 0; removed = 0; deferred = 0; tooLarge = 0; recovered = ""; wroteIndex = $false; stoppedEarly = $false; rows = (New-Object System.Collections.ArrayList) }
    $gate = Read-HordeMetricsGate
    if ($gate.state -eq "absent" -or ($gate.state -eq "known" -and $gate.value.level -cne "usage")) { $res.state = "off"; $res.reason = "metrics are off; nothing was collected"; return [pscustomobject]$res }
    if ($gate.state -ne "known") { $res.state = "refused"; $res.reason = ("the gate is refused, so nothing was collected: " + $gate.reason); return [pscustomobject]$res }
    # The folder itself must be allowed before anything - the index included - is written to it.
    $probe = Get-HordeMetricsWriteDecision -Gate $gate -FirstEventAt (New-HordeKnown -Value $gate.value.enabledAt) -RepoRoot $RepoRoot
    if (-not $probe.write) { $res.state = "refused"; $res.reason = ("nothing was collected: " + $probe.reason); return [pscustomobject]$res }
    $stores = Get-HordeAgentStores -Root $RepoRoot
    if ($stores.state -ne "known") { $res.state = "refused"; $res.reason = ("nothing was collected: " + $stores.reason); return [pscustomobject]$res }

    # ONE RUN AT A TIME: two runs would each rewrite the index from what they read. A file held with no
    # sharing is released by the system if its holder dies, so a killed run never leaves it locked. Only
    # a sharing violation means another run; any other failure to open the lock is a failure, said so,
    # never a silent "busy" on every scheduled run (review of PR #70, F8).
    $dir = Get-HordeMetricsDir
    [void][System.IO.Directory]::CreateDirectory($dir)
    $lock = $null
    try { $lock = [System.IO.File]::Open((Join-Path $dir "collect.lock"), [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None) }
    catch {
        $inner = $_.Exception; while ($null -ne $inner.InnerException) { $inner = $inner.InnerException }
        if ($inner -is [System.IO.IOException] -and $inner.HResult -eq $script:HordeSharingViolation) { $res.state = "busy"; $res.reason = "another collect is running; this one did nothing" }
        else { $res.state = "refused"; $res.reason = ("the collect lock could not be opened, so nothing was collected: " + $inner.Message) }
        return [pscustomobject]$res
    }
    try {
        # RECOVER BEFORE CLEANING (review of #70): a file that is missing or unreadable is restored from the
        # newest of its temp copies that is valid, and only then are temps older than a valid file removed.
        $res.recovered = Restore-HordeMetricsTemps -Dir $dir
        $index = Read-HordeCollectIndex
        if ($index.note -ne "") { $res.reason = $index.note }
        $entries = $index.entries
        $dirty = ($index.note -ne "")
        $table = Read-HordePriceBook
        $enabledTicks = $gate.value.enabledAt.Ticks
        $settleTicks = [TimeSpan]::FromMinutes($SettleMinutes).Ticks
        # Every file is enumerated first, so a run that stops early still knows which are present and
        # forgets none it did not reach.
        # A DEFERRED FILE IS READ LAST, so one that the budget runs out inside cannot starve the others.
        $all = @(Get-HordeCollectFiles -Stores $stores.value)
        $all = @(@($all | Where-Object { $null -eq $entries[$_.key] -or $entries[$_.key].outcome -ne "deferred" }) + @($all | Where-Object { $null -ne $entries[$_.key] -and $entries[$_.key].outcome -eq "deferred" }))
        $present = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($item in $all) { [void]$present.Add($item.key); [void]$present.Add("hash:" + (Get-HordeHashText $item.key)) }
        $started = [System.Diagnostics.Stopwatch]::StartNew()
        $res.found = $all.Count
        foreach ($item in $all) {
            # COMMIT what the previous transcript changed, before the next one is touched.
            if ($dirty) { Write-HordeCollectIndex -Entries $entries; $res.wroteIndex = $true; $dirty = $false }
            $f = $item.file
            $path = $f.FullName
            $plainKey = $item.key
            $hashKey = "hash:" + (Get-HordeHashText $plainKey)
            $size = $f.Length
            $mod = $f.LastWriteTimeUtc.Ticks
            $settled = (($Now.Ticks - $mod) -ge $settleTicks)
            $old = $entries[$plainKey]
            $key = $plainKey
            if ($null -eq $old) { $old = $entries[$hashKey]; if ($null -ne $old) { $key = $hashKey } }
            # TOO LARGE IS NOT FOREVER (review of #70: the largest transcripts matter most): it is skipped only
            # while it has not changed; a change gives it a fresh count of deferrals. -IncludeLarge reads it.
            if ($null -ne $old -and $old.outcome -eq "tooLarge" -and $old.size -eq $size -and $old.modifiedTicks -eq $mod -and -not $IncludeLarge) { $res.tooLarge++; continue }
            if ($null -ne $old -and $old.size -eq $size -and $old.modifiedTicks -eq $mod -and $old.enabledAtTicks -eq $enabledTicks) {
                # Unchanged. A provisional record is collected again only once its file has settled; a deferred
                # file is always tried again, last (its run ran out inside it, so it was never read whole).
                if (($old.outcome -ne "provisional" -or -not $settled) -and $old.outcome -ne "deferred" -and -not ($IncludeLarge -and $old.outcome -eq "tooLarge")) { $res.unchanged++; continue }
            }
            # Last written before consent, and never recorded: not read, not indexed.
            if ($mod -lt $enabledTicks -and ($null -eq $old -or $old.record -eq "")) {
                if ($null -ne $old) { $entries.Remove($key); $dirty = $true }
                $res.beforeConsent++; continue
            }
            if ($null -ne $old -and $old.outcome -eq "beforeConsent" -and $old.enabledAtTicks -eq $enabledTicks -and $old.firstEventTicks -gt 0 -and $size -ge $old.size) {
                $old.size = $size; $old.modifiedTicks = $mod; $old.reason = "began before metrics were enabled, and has only grown since"
                $dirty = $true; $res.beforeConsent++; continue
            }
            # THE BUDGET: a run ends cleanly before the scheduler's time limit would kill it (review of #70,
            # NEW-1); what it did not reach is read by the next run.
            if (($MaxFiles -gt 0 -and $res.read -ge $MaxFiles) -or ($started.Elapsed.TotalSeconds -ge $MaxSeconds)) {
                $res.stoppedEarly = $true
                $res.reason = ("the run's budget (" + $(if ($MaxFiles -gt 0) { "" + $MaxFiles + " files, " } else { "" }) + $MaxSeconds + " seconds) is spent; the rest is read next run")
                break
            }
            $entry = [pscustomobject]@{ size = $size; modifiedTicks = $mod; outcome = ""; record = ""; firstEventTicks = [long]0; enabledAtTicks = $enabledTicks; reason = ""; deferrals = 0 }
            $priorDeferrals = 0
            if ($null -ne $old) { $entry.record = $old.record; if ($old.outcome -eq "deferred") { $priorDeferrals = $old.deferrals }; $entries.Remove($key) }
            $res.read++
            try {
                # THE BUDGET HOLDS INSIDE A FILE TOO (review of #70: checked only between files, one file ran
                # 48 s on a 2 s budget): the read stops at the run's deadline, and the file is deferred -
                # uncommitted, its size kept - and read last next run. Deferred too often, it is too large.
                if (-not $IncludeLarge) { Set-HordeReadDeadline -At ([datetime]::UtcNow.AddSeconds([Math]::Max(0, $MaxSeconds - $started.Elapsed.TotalSeconds))) }
                $measured = Measure-HordeTranscriptFile -Path $path -PriceTable $table
                $hit = Test-HordeReadDeadlineHit
                Set-HordeReadDeadline -At $null
                if ($hit) {
                    $entry.deferrals = $priorDeferrals + 1
                    if ($entry.deferrals -ge $script:HordeCollectMaxDeferrals) {
                        $entry.outcome = "tooLarge"; $entry.reason = ("not read within a run's budget " + $entry.deferrals + " runs in a row (" + $size + " bytes); skipped from now on")
                        $res.tooLarge++
                    } else {
                        $entry.outcome = "deferred"; $entry.reason = ("the run's budget ran out inside it at " + $size + " bytes; it is read last next run")
                        $res.deferred++
                    }
                    $entries[$plainKey] = $entry; $dirty = $true
                    $res.stoppedEarly = $true
                    $res.reason = "the run's budget ran out inside a transcript; it was deferred, and the rest is read next run"
                    break
                }
                if ($measured.state -ne "known") {
                    if ($measured.reason -like "no adapter reads*") { $entry.outcome = "noAdapter"; $res.noAdapter++ } else { $entry.outcome = "unreadable"; $res.unreadable++ }
                    $entry.reason = $measured.reason
                    $entries[$plainKey] = $entry; $dirty = $true; continue
                }
                $mv = $measured.value
                if ($mv.worker.firstEventAt.state -eq "known") { $entry.firstEventTicks = $mv.worker.firstEventAt.value.Ticks }
                $decision = Get-HordeMetricsWriteDecision -Gate $gate -FirstEventAt $mv.worker.firstEventAt -RepoRoot $RepoRoot
                if (-not $decision.write) {
                    $entry.reason = $decision.reason
                    if ($mv.worker.firstEventAt.state -eq "known" -and $mv.worker.firstEventAt.value -lt $gate.value.enabledAt) {
                        $entry.outcome = "beforeConsent"; $entry.record = ""; $res.beforeConsent++
                        $entries[$hashKey] = $entry; $dirty = $true; continue
                    }
                    $entry.outcome = "notRecorded"; $res.notRecorded++
                    $entries[$plainKey] = $entry; $dirty = $true; continue
                }
                $adapter = $mv.read.adapter
                $name = $mv.read.recordKey
                if (-not (Test-HordeMetricsRecordName $name)) {
                    $entry.outcome = "notRecorded"; $entry.reason = ("the transcript's identity '" + $name + "' is not a record name Horde will write"); $res.notRecorded++
                    $entries[$plainKey] = $entry; $dirty = $true; continue
                }
                # A file that changed while it was read is provisional, whatever its time said before.
                $after = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
                $changedWhileRead = ($null -eq $after -or $after.Length -ne $size -or $after.LastWriteTimeUtc.Ticks -ne $mod)
                $final = ($settled -and -not $changedWhileRead)
                $why = ""
                if ($changedWhileRead) { $why = "the transcript changed while it was read; it will be collected again" }
                elseif (-not $settled) { $why = "the transcript was written to within the last " + $SettleMinutes + " minutes, so it may still grow; it will be collected again once it is still" }
                $record = $mv.record
                $record["collection"] = [ordered]@{
                    provisional = (-not $final)
                    why = $why
                    sourceBytes = $size
                    sourceModifiedAt = (ConvertTo-HordeJsonSafe (New-Object DateTime ($mod, [DateTimeKind]::Utc)))
                }
                $written = Write-HordeMetricsRecord -Record $record -Adapter $adapter -Name $name
                $entry.record = $adapter + "/" + $name
                $entry.outcome = $(if ($final) { "recorded" } else { "provisional" })
                $entries[$plainKey] = $entry; $dirty = $true
                $res.recorded++
                if (-not $final) { $res.provisional++ }
                [void]$res.rows.Add([pscustomobject]@{ file = $f.Name; record = $entry.record; provisional = (-not $final); written = $written })
            } catch {
                Set-HordeReadDeadline -At $null
                $entry.outcome = "failed"; $entry.reason = ("collecting it failed: " + $_.Exception.Message)
                $entries[$plainKey] = $entry; $dirty = $true; $res.failed++
            }
        }
        # A transcript that is gone leaves the index; its record stays, flagged if it was provisional and
        # no other transcript holds it.
        $held = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($k in @($entries.Keys)) { if ($present.Contains($k) -and $entries[$k].record -ne "") { [void]$held.Add($entries[$k].record) } }
        foreach ($k in @($entries.Keys)) {
            if ($present.Contains($k)) { continue }
            $gone = $entries[$k]
            if ($gone.outcome -eq "provisional" -and $gone.record -ne "" -and -not $held.Contains($gone.record)) {
                try { Set-HordeRecordSourceGone -Record $gone.record } catch { $res.failed++ }
            }
            $entries.Remove($k); $dirty = $true; $res.removed++
        }
        if ($dirty) { Write-HordeCollectIndex -Entries $entries; $res.wroteIndex = $true }
        # Temps that this run's commits have made older than their files are removed now, not a run later.
        $null = Restore-HordeMetricsTemps -Dir $dir
        # The recovery note is said until a clean run commits a valid index, then dropped (review of #70):
        # summarize warns about a recovery once it happened, not forever.
        if ($res.wroteIndex -and $res.recovered -eq "") { Remove-Item -LiteralPath (Join-Path $dir "collect-recovered.json") -Force -ErrorAction SilentlyContinue }
        $res.state = "done"
    } finally { $lock.Dispose() }
    return [pscustomobject]$res
}

function Format-HordeMetricsCollect {
    # The lines a person, or a scheduler's log, sees for one run.
    param([Parameter(Mandatory = $true)]$Result)
    $r = $Result
    if ($r.state -ne "done") { return @("collect: " + $r.state + " - " + $r.reason) }
    $lines = @("collect: " + $r.found + " transcripts; " + $r.unchanged + " unchanged; " + $r.read + " read; " + $r.recorded + " recorded (" + $r.provisional + " provisional); " + $r.beforeConsent + " from before consent; " + $r.notRecorded + " not recorded; " + $r.failed + " failed; " + $r.noAdapter + " no adapter; " + $r.unreadable + " not readable; " + $r.removed + " gone from the index; " + $r.deferred + " deferred; " + $r.tooLarge + " too large")
    if ($r.reason -ne "") { $lines += ("collect: " + $r.reason) }
    if ($r.recovered -ne "") { $lines += ("collect: WARNING: " + $r.recovered) }
    if (-not $r.wroteIndex) { $lines += "collect: nothing new or changed, nothing written" }
    if ($r.stoppedEarly) { $lines += "collect: stopped early on its budget; the next run goes on" }
    return $lines
}

function Invoke-HordeMetricsSchedule {
    # `horde metrics schedule install|remove|status`: the one scheduled job that runs collect, through
    # whichever scheduler this machine has (core/Schedule.ps1). Returns the lines to show; throws when
    # the action cannot be done. -TaskName and -Folder exist so a test acts only on a job it named
    # itself, in Horde's test folder.
    #
    # INSTALL ONLY WHILE THE GATE SAYS USAGE: a job that collects nothing every 30 minutes is a job
    # nobody needs, and the gate stays the one switch. Collect checks the gate again on every run, so
    # turning metrics off later stops the recording at once, with or without removing the job.
    param([Parameter(Mandatory = $true)][ValidateSet("install", "remove", "status")][string]$Action, [string]$TaskName = $script:HordeCollectJobName, [string]$Folder = "Horde", [switch]$Disabled, [switch]$TakeOver, [Parameter(Mandatory = $true)][string]$HordeScript)
    Assert-HordeJobName -Name $TaskName -Folder $Folder
    $sched = Get-HordeScheduler
    if ($sched.state -ne "known") { throw ("cannot schedule collect: " + $sched.reason) }
    $s = $sched.value
    $gate = Read-HordeMetricsGate
    $gateText = "off"
    if ($gate.state -eq "known") { $gateText = $gate.value.level } elseif ($gate.state -eq "unknown") { $gateText = "refused (" + $gate.reason + ")" }
    $where = "'" + $TaskName + "' in " + $s.name + " folder " + $Folder
    switch ($Action) {
        "install" {
            if ($gate.state -ne "known" -or $gate.value.level -cne "usage") { throw ("metrics are " + $gateText + ", so a collect job would record nothing; it was not installed") }
            $job = New-HordeCollectJob -HordeScript $HordeScript -Name $TaskName -Folder $Folder -Disabled:$Disabled -TakeOver:$TakeOver
            & $s.install $job
            $st = & $s.status $TaskName $Folder
            if ($st.state -ne "known" -or -not $st.value.marked) { throw ("the " + $s.name + " did not keep the job " + $where + ": " + $st.reason) }
            return @("installed " + $where + ": every " + $job.everyMinutes + " minutes, low priority, stopped after " + $job.timeLimitMinutes + " minutes, for the Horde home " + $job.hordeHome + $(if ($TakeOver) { "; -TakeOver: any task of this name registered under another home was replaced WITHOUT the check; " } else { "" }) + $(if ($Disabled) { "; DISABLED, so it never runs" } else { "" }), ("runs: " + $job.script + " " + ($job.arguments -join " ")))
        }
        "remove" {
            $gone = & $s.remove $TaskName $Folder
            if ($gone) { return @("removed " + $where) }
            return @("no job " + $where + "; nothing to remove")
        }
        "status" {
            $st = & $s.status $TaskName $Folder
            $lines = @("metrics gate: " + $gateText)
            if ($st.state -ne "known") { return ($lines + @($where + " is not installed")) }
            $v = $st.value
            $fmt = { param($t) if ($null -eq $t) { "never" } else { $t.ToString("yyyy-MM-dd HH:mm 'UTC'", [System.Globalization.CultureInfo]::InvariantCulture) } }
            $lines += ($where + ": " + $(if ($v.enabled) { "enabled" } else { "DISABLED" }) + ", " + $v.state + ", every " + $v.everyMinutes + " minutes, logon " + $v.logonType + $(if ($v.marked) { ", Horde's" } else { ", NOT made by Horde" }))
            $lines += ("registered under the Horde home " + $v.home + "; last run " + (& $fmt $v.lastRunAt) + " (result " + $v.lastResult + "), next run " + (& $fmt $v.nextRunAt))
            return $lines
        }
    }
}
