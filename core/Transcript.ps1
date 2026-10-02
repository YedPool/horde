# core/Transcript - the transcript port: one shape for what any agent harness's transcript says.
#
# WHY A PORT. Metrics must read every harness the fleet runs, and the founder's decision of 2026-09-30
# is that core never names one (CONTRIBUTING 14). So each harness has an ADAPTER in
# agents/<name>/Transcript.ps1 that turns its own file format into the records below, and everything
# that measures - core/Metrics.ps1 - reads only these records. A new harness is a new adapter.
#
# THE RECORDS, in file order. Every record has kind, role, ts (a UTC [datetime]) and line (the
# 1-based line it came from). Kinds:
#   call        one model request, deduplicated. id; model (an answer); usage (an answer: known
#               { input; cacheRead; cacheWrite; output; cacheWriteSplit }, where input EXCLUDES cached
#               input and cacheWriteSplit is itself an answer, known { m5; h1 }); textChars (the
#               length of the text the model wrote); toolCallCount; speed; inferenceGeo. role "assistant".
#   toolCall    one tool invocation. id; name; callId (the call that made it, "" when not known);
#               launchesWorker (whether this tool starts a worker). role "assistant".
#   toolResult  the result of a tool invocation. toolCallId; isError (an answer: some harnesses do not
#               say); chars; worker (an answer: known
#               worker id, absent when the tool is not a worker launch, unknown when it is one whose
#               worker cannot be proved). role "tool".
#   input       text that entered the session from outside the model. source "user" or "notification";
#               chars; for a notification: taskId, toolCallId, interim, and worker (an answer: known id
#               when the transcript PROVES which worker it is about, absent when it proves it is about
#               something that is not a worker, such as a background shell job, unknown otherwise).
#               role "user".
#   usageTotal  a cumulative usage figure the harness itself wrote (not summed; the last one stands).
#               usage as on a call. role "system".
#   turnEnd     the end of a turn. durationMs (an answer). role "system".
#   compaction  the harness compacted its context. role "system".
#   event       any other timestamped line, kept only so the gap between events is measured honestly.
#               role "system".
#
# RECORDS CARRY LENGTHS AND IDS, NEVER TEXT (metrics design section 8, rule 2). An adapter reads the
# fields it names and drops the rest of each line in memory; nothing here can hold a prompt, a tool
# argument or a result. agents/<name>/test plants a secret in a transcript and greps every output.
#
# UNKNOWN STAYS UNKNOWN: a value the transcript does not give is a core/tristate unknown with a reason,
# never 0 and never "" (core/Tristate.ps1). Dedup is the adapter's job, because what identifies one
# request differs per harness; core/Metrics.ps1 still refuses to count one id twice.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). Needs core/Tristate.ps1
# and core/ReadShared.ps1 loaded first.

$script:HordeTranscriptKinds = @("call", "toolCall", "toolResult", "input", "usageTotal", "turnEnd", "compaction", "event")
$script:HordeTranscriptAdapters = New-Object System.Collections.ArrayList

function ConvertTo-HordeUtcTime {
    # A transcript timestamp as a UTC [datetime], or $null when it is missing or carries no zone.
    # A time with no zone cannot be placed (core/Tristate.ps1, ConvertFrom-HordeAnswerRecord, measured
    # at UTC-4 on 2026-09-29), so it is not guessed to be UTC.
    param($Text)
    if ($null -eq $Text -or "$Text" -eq "") { return $null }
    $parsed = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::RoundtripKind
    if (-not [datetime]::TryParse("$Text", [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) { return $null }
    if ($parsed.Kind -eq [System.DateTimeKind]::Unspecified) { return $null }
    return $parsed.ToUniversalTime()
}

function New-HordeTranscriptRecord {
    # The one constructor. Refuses a record with an unknown kind or no UTC time, so an adapter cannot
    # emit a shape core does not read.
    #
    # NO [Parameter(Mandatory)] HERE, ON PURPOSE: it is called once per transcript line, and measured
    # 2026-10-01 on PowerShell 5.1, 20,000 calls took 6,883 ms with mandatory parameters and 811 ms
    # without (a 46 MB transcript took 63 s to read). The checks below do the refusing instead.
    param([string]$Kind, [string]$Role, $Ts, [int]$Line, $Fields)
    if ($script:HordeTranscriptKinds -cnotcontains $Kind) { throw ("not a transcript record kind: '" + $Kind + "'") }
    if ("$Role" -eq "") { throw ("a transcript record needs a role (kind " + $Kind + ", line " + $Line + ")") }
    if ($Ts -isnot [datetime] -or $Ts.Kind -ne [System.DateTimeKind]::Utc) { throw ("a transcript record needs a UTC time (kind " + $Kind + ", line " + $Line + ")") }
    $r = [ordered]@{ PSTypeName = "Horde.TranscriptRecord"; kind = $Kind; role = $Role; ts = $Ts; line = $Line }
    if ($null -ne $Fields) { foreach ($k in $Fields.Keys) { $r[$k] = $Fields[$k] } }
    return [pscustomobject]$r
}

function New-HordeUsage {
    # A known usage answer. input EXCLUDES cached input on every harness: an adapter whose harness
    # counts cached input inside input subtracts it (measured for one harness on 2026-09-30, EP 12.2).
    # -Split is an answer: known @{ m5; h1 } when the harness splits cache writes by lifetime, which is
    # priced differently (metrics design 2.9), absent when the harness has no such split.
    #
    # NOT -Input: $input is an automatic variable inside a function (CONTRIBUTING 12's family of traps).
    param([long]$Uncached, [long]$CacheRead, [long]$CacheWrite, [long]$Output, $Split)
    foreach ($v in @($Uncached, $CacheRead, $CacheWrite, $Output)) { if ($v -lt 0) { throw "a token count cannot be negative" } }
    Assert-HordeAnswer $Split
    return (New-HordeKnown -Value ([pscustomobject]@{ input = $Uncached; cacheRead = $CacheRead; cacheWrite = $CacheWrite; output = $Output; cacheWriteSplit = $Split }))
}

function Read-HordeJsonLines {
    # Every line of a JSONL file, parsed, in order: { lines = @({ line; value }); parseSkipped; tornTail;
    # lineCount; lastBad; lastTorn; stopped }.
    #
    # READ-ONLY AND SHARED (core/ReadShared.ps1): the harness is appending to the file while it is read,
    # and an ordinary read share made another system's writes fail (measured 2026-09-29).
    #
    # A LINE THAT DOES NOT PARSE IS COUNTED, NEVER SILENTLY DROPPED (metrics design 2.1): a summary
    # built on skipped lines is a smaller number that must say so. The LAST line, when the file does
    # not end with a newline, is the line being written right now; it is counted apart as tornTail.
    #
    # THE PARSER IS .NET's JavaScriptSerializer, not ConvertFrom-Json: it returns dictionaries and
    # arrays without building a PowerShell object per field. Measured 2026-10-01 on PowerShell 5.1: a
    # 46 MB, 31,204-line transcript parsed in 925 ms. A missing key reads as $null on its dictionaries
    # (measured the same day), and integers arrive as Int32 or Int64, fractions as Decimal.
    #
    # -Each STREAMS: with it, each parsed line is handed to the block (line number, value) and not kept,
    # so the file is never held in memory whole. Measured 2026-10-01 on PowerShell 5.1: with all 31,204
    # lines of a 46 MB transcript held as dictionaries, every later allocation slowed about tenfold (a
    # record constructor went from 0.04 to 0.4 ms), and reading took 56 s; an adapter streams.
    #
    # -Upto REREADS EXACTLY WHAT AN EARLIER READ SAW (plan step M2). An adapter that needs a fact from
    # the whole file before it can emit its first record reads twice; the transcript is still being
    # appended to, so the second read stops at the first one's lineCount, and a last line the first read
    # could not parse is not parsed now either, though it may be whole by now. The counts it returns are
    # then the first read's. A file that has become SHORTER than the first read saw throws: it was
    # rewritten, and two reads of it would not describe one file.
    #
    # -Control STOPS EARLY: a hashtable the block may set stop = $true in; the read ends after that
    # line, and returns stopped = $true. An adapter looking for one fact need not read the rest.
    param([Parameter(Mandatory = $true)][string]$Path, [scriptblock]$Each, $Upto = $null, [hashtable]$Control = $null)
    # EVERY LOCAL HERE IS PRIVATE. PowerShell scopes are dynamic: the -Each block runs below this
    # function, so a name it reads that this function also uses resolves HERE, not in the adapter that
    # wrote the block. Measured 2026-10-01: an adapter whose block added records to its own $out added
    # them to this function's $out instead, and the adapter read nothing. Private variables are not
    # visible to a child scope, so the block sees only its own and its author's.
    foreach ($private:hordeParam in @("Path", "Each", "Upto", "Control")) { (Get-Variable -Name $hordeParam -Scope Local).Options = "Private" }
    $private:ser = $null; $private:out = $null; $private:skipped = 0; $private:torn = 0; $private:stream = $null
    $private:endsWithNewline = $true; $private:reader = $null; $private:n = 0; $private:pendingBad = $false; $private:text = $null; $private:value = $null
    $private:limit = 0; $private:stopped = $false
    if ($null -ne $Upto) { $limit = [int]$Upto.lineCount }
    Add-Type -AssemblyName System.Web.Extensions
    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $ser.MaxJsonLength = [int]::MaxValue
    $out = New-Object System.Collections.ArrayList
    $skipped = 0; $torn = 0
    $stream = Open-HordeSharedStream -Path $Path
    try {
        $endsWithNewline = $true
        if ($stream.Length -gt 0) {
            [void]$stream.Seek(-1, [System.IO.SeekOrigin]::End)
            $endsWithNewline = ($stream.ReadByte() -eq 10)
            [void]$stream.Seek(0, [System.IO.SeekOrigin]::Begin)
        }
        $reader = New-Object System.IO.StreamReader($stream, (New-Object System.Text.UTF8Encoding($false)), $true)
        try {
            $n = 0
            $pendingBad = $false
            while (($null -eq $Upto -or $n -lt $limit) -and $null -ne ($text = $reader.ReadLine())) {
                $n++
                if ($pendingBad) { $skipped++; $pendingBad = $false }
                if ($null -ne $Upto -and $n -eq $limit -and $Upto.lastBad) { $pendingBad = $true; continue }
                if ($text.Trim() -eq "") { continue }
                $value = $null
                try { $value = $ser.DeserializeObject($text) } catch { $value = $null }
                if ($value -isnot [System.Collections.Generic.Dictionary[string, object]]) { $pendingBad = $true; continue }
                # The block's output is discarded, so a stray value in an adapter can never become a line.
                if ($null -ne $Each) { $null = & $Each $n $value } else { [void]$out.Add([pscustomobject]@{ line = $n; value = $value }) }
                if ($null -ne $Control -and $Control["stop"] -eq $true) { $stopped = $true; break }
            }
            if ($null -ne $Upto -and $n -lt $limit) { throw ("the file is shorter than when it was first read (" + $n + " lines, then " + $limit + "), so it was rewritten") }
            if ($null -ne $Upto) { $endsWithNewline = -not $Upto.lastTorn }
            if ($pendingBad -and -not $stopped) { if ($endsWithNewline) { $skipped++ } else { $torn++ } }
        } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
    return [pscustomobject]@{ lines = $out.ToArray(); parseSkipped = $skipped; tornTail = $torn; lineCount = $n; lastBad = ($pendingBad -and -not $stopped); lastTorn = ($pendingBad -and -not $stopped -and -not $endsWithNewline); stopped = $stopped }
}

function Get-HordeJsonPath {
    # The value at a dotted path in parsed JSON, or $null when any step is missing or not an object.
    # Keeps adapters from writing nested null checks, each one a place to get it wrong.
    param($Value, [string]$Path)
    $cur = $Value
    foreach ($step in $Path.Split(".")) {
        if ($cur -isnot [System.Collections.IDictionary]) { return $null }
        # ContainsKey, not Contains: a generic Dictionary implements IDictionary.Contains only explicitly,
        # and PowerShell 5.1 finds no Contains overload on it (measured 2026-10-01).
        if (-not $cur.ContainsKey($step)) { return $null }
        $cur = $cur[$step]
    }
    return $cur
}

function Register-HordeTranscriptAdapter {
    # Called by an adapter file when it is dot-sourced. -Claim answers whether a path is this harness's
    # transcript ($true/$false), reading as little as it can. -Read returns
    # { records; parseSkipped; tornTail; sessionId } for a claimed path. Where a harness keeps its
    # files is not the adapter's to say: it is data, in agents/<name>/stores.json (core/MetricsStore.ps1).
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Claim,
        [Parameter(Mandatory = $true)][scriptblock]$Read
    )
    if ($Name -cnotmatch '\A[a-z][a-z0-9-]*\z') { throw ("an adapter name is lowercase letters, digits and hyphens: '" + $Name + "'") }
    foreach ($a in $script:HordeTranscriptAdapters) { if ($a.name -ceq $Name) { $script:HordeTranscriptAdapters.Remove($a); break } }
    [void]$script:HordeTranscriptAdapters.Add([pscustomobject]@{ name = $Name; claim = $Claim; read = $Read })
}

function Get-HordeTranscriptAdapters { return @($script:HordeTranscriptAdapters) }

function Get-HordeTranscriptAdapterFiles {
    # The adapter files, found by folder and never named: agents/<name>/Transcript.ps1. The CALLER
    # dot-sources each one at its own scope, so the adapter's helper functions stay visible to the
    # blocks it registers (a file dot-sourced inside a function would take them with it on return).
    param([string]$Root = (Split-Path -Parent $PSScriptRoot))
    $agents = Join-Path $Root "agents"
    if (-not (Test-Path -LiteralPath $agents -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $agents -Directory | Sort-Object Name | ForEach-Object { Join-Path $_.FullName "Transcript.ps1" } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
}

function Resolve-HordeTranscriptAdapter {
    # Which adapter reads this file, as an answer: known adapter, absent when none claims it, unknown
    # when more than one does or a claim throws - a file two harnesses both recognise is not read as
    # either, because which one is right cannot be told.
    param([Parameter(Mandatory = $true)][string]$Path)
    $claimed = New-Object System.Collections.ArrayList
    foreach ($a in $script:HordeTranscriptAdapters) {
        $yes = $false
        try { $yes = (& $a.claim $Path) -eq $true }
        catch { return (New-HordeUnknown -Reason ("adapter " + $a.name + " could not decide whether it reads " + (Split-Path -Leaf $Path)) -ErrorRecord $_) }
        if ($yes) { [void]$claimed.Add($a) }
    }
    if ($claimed.Count -eq 0) { return (New-HordeAbsent -Note "no adapter reads this file") }
    if ($claimed.Count -gt 1) { return (New-HordeUnknown -Reason ("more than one adapter claims it: " + (@($claimed | ForEach-Object { $_.name }) -join ", "))) }
    return (New-HordeKnown -Value $claimed[0])
}

function Test-HordeTranscriptRecord {
    # Problems with one record of an adapter's output, as strings; none means it keeps the port's
    # contract. -PreviousLine is the line of the record before it, for the file-order check.
    param($Record, [int]$PreviousLine = 0)
    $r = $Record
    $problems = New-Object System.Collections.ArrayList
    if ($null -eq $r -or @($r.PSObject.TypeNames) -notcontains "Horde.TranscriptRecord") { [void]$problems.Add("a record was not made by New-HordeTranscriptRecord"); return @($problems) }
    if ($r.line -lt $PreviousLine) { [void]$problems.Add("records are out of file order at line " + $r.line) }
    switch ($r.kind) {
        "call" {
            if ("$($r.id)" -eq "") { [void]$problems.Add("a call at line " + $r.line + " has no id") }
            foreach ($f in @("model", "usage")) { if (-not (Test-HordeAnswer $r.$f)) { [void]$problems.Add("a call's " + $f + " at line " + $r.line + " is not an answer") } }
        }
        "toolCall" { if ("$($r.id)" -eq "") { [void]$problems.Add("a tool call at line " + $r.line + " has no id") } }
        "toolResult" {
            if (-not (Test-HordeAnswer $r.worker)) { [void]$problems.Add("a tool result's worker at line " + $r.line + " is not an answer") }
            if (-not (Test-HordeAnswer $r.isError)) { [void]$problems.Add("a tool result's isError at line " + $r.line + " is not an answer") }
        }
        "input" {
            if (@("user", "notification") -cnotcontains $r.source) { [void]$problems.Add("an input at line " + $r.line + " has source '" + $r.source + "'") }
            if ($r.source -ceq "notification" -and -not (Test-HordeAnswer $r.worker)) { [void]$problems.Add("a notification's worker at line " + $r.line + " is not an answer") }
        }
        "turnEnd" { if (-not (Test-HordeAnswer $r.durationMs)) { [void]$problems.Add("a turn end's duration at line " + $r.line + " is not an answer") } }
    }
    return @($problems)
}

function Test-HordeTranscriptRecords {
    # Problems with an adapter's whole output, as strings, in record order.
    param($Records)
    $problems = New-Object System.Collections.ArrayList
    $prev = 0
    foreach ($r in @($Records)) {
        foreach ($p in @(Test-HordeTranscriptRecord -Record $r -PreviousLine $prev)) { [void]$problems.Add($p) }
        if ($null -ne $r -and $null -ne $r.PSObject.Properties["line"] -and $r.line -ge $prev) { $prev = $r.line }
    }
    return @($problems)
}

function New-HordeTranscriptSink {
    # What an adapter hands its records to, one at a time, in file order: an object with Add(record).
    # The sink checks each record against the port's contract AS IT ARRIVES and passes it on to -Into,
    # which is anything with an Add(record) method: a list, for a caller that wants every record, or a
    # running total (core/Metrics.ps1) for one that must not hold them.
    #
    # WHY A SINK AND NOT A SCRIPT BLOCK (plan step M2): a block handed down runs in the scope of whoever
    # calls it, and reads THAT scope's variables of the same name (measured 2026-10-01; see
    # Read-HordeJsonLines). A method reads its state from $this, which is always its own.
    #
    # The first broken record stops the read: problem says why, and the caller reports the file as
    # unknown, as it did when the whole output was checked at the end.
    param([Parameter(Mandatory = $true)]$Into)
    $sink = [pscustomobject]@{ into = $Into; prev = 0; count = 0; problem = ""; downstream = $null }
    $sink | Add-Member -MemberType ScriptMethod -Name Add -Value {
        param($Record)
        $bad = @(Test-HordeTranscriptRecord -Record $Record -PreviousLine $this.prev)
        if ($bad.Count -gt 0) { $this.problem = $bad[0]; throw ("broke the record contract: " + $bad[0]) }
        $this.prev = $Record.line
        $this.count++
        try { [void]$this.into.Add($Record) }
        catch { $this.downstream = $_; throw }
    }
    return $sink
}

function Read-HordeTranscript {
    # Read one transcript through the adapter that claims it. Returns an answer: known
    # { adapter; path; sessionId; records; parseSkipped; tornTail }, unknown when no single adapter
    # claims it, the adapter fails, or its output breaks the contract.
    #
    # -Into STREAMS (plan step M2): each record goes to -Into's Add method as the adapter makes it, and
    # records is then empty. Without it, records holds every record, as in M1. Measured 2026-10-02 on
    # the always-on box: holding every record of a 133 MB transcript, and the summary's objects for
    # each, peaked at 1,734 MB.
    #
    # AN ADAPTER EMITS OR RETURNS. Its -Read block is called with (path, sink); it hands each record to
    # $sink.Add in file order and returns { sessionId; parseSkipped; tornTail }, or it returns its
    # records in `records` as M1's did, and they are passed through the same sink here. Either way every
    # record is checked against the contract before anything reads it.
    param([Parameter(Mandatory = $true)][string]$Path, $Into = $null)
    $which = Resolve-HordeTranscriptAdapter -Path $Path
    if ($which.state -ne "known") {
        if ($which.state -eq "absent") { return (New-HordeUnknown -Reason ("no adapter reads " + (Split-Path -Leaf $Path))) }
        return $which
    }
    $adapter = $which.value
    $kept = $null
    $target = $Into
    if ($null -eq $target) { $kept = New-Object System.Collections.ArrayList; $target = $kept }
    $sink = New-HordeTranscriptSink -Into $target
    $got = $null
    try {
        $got = & $adapter.read $Path $sink
        if ($null -ne $got -and $null -ne $got.PSObject.Properties["records"]) { foreach ($r in @($got.records)) { $sink.Add($r) } }
    }
    catch {
        if ($sink.problem -ne "") { return (New-HordeUnknown -Reason ("adapter " + $adapter.name + " broke the record contract: " + $sink.problem)) }
        if ($null -ne $sink.downstream) { return (New-HordeUnknown -Reason ("what reads the records of " + (Split-Path -Leaf $Path) + " failed") -ErrorRecord $sink.downstream) }
        return (New-HordeUnknown -Reason ("adapter " + $adapter.name + " failed to read " + (Split-Path -Leaf $Path)) -ErrorRecord $_)
    }
    $records = @()
    if ($null -ne $kept) { $records = $kept.ToArray() }
    return (New-HordeKnown -Value ([pscustomobject]@{
        adapter = $adapter.name; path = $Path; sessionId = $got.sessionId
        records = $records; parseSkipped = [int]$got.parseSkipped; tornTail = [int]$got.tornTail
    }))
}
