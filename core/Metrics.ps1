# core/Metrics - what one transcript says about the work done in it, measured from port records.
#
# WHAT IT REPLACES. The 2026-09-30 goblin-versus-agent study took these measures by hand, with
# throwaway scripts (worker-extract.js, orc-extract.js, join.js; planning/ledger/core-metrics-transcript.md
# lists each rule taken from them and why). Here each measure is an instrument with a positive
# control in the suites, so the study's headline numbers come from code.
#
# IT READS ONLY core/Transcript.ps1 RECORDS and names no harness (CONTRIBUTING 14). Every count that a
# transcript cannot support is a core/tristate unknown with the reason.
#
# THE TWO GROUPS OF MEASURES:
#   Get-HordeWorkerSummary - wall-clock, tokens by kind, model calls, tool calls, the longest silence
#     and the longest tool call, the model, and the notional cost.
#   Get-HordeOrcMeasures - the orchestrator's "still waiting" calls and the worker results that land
#     in its context (study sections 4 and 5.2), attributed to a worker only where the transcript
#     proves the link. A still-waiting call answers an INTERIM notification with no person speaking
#     in between; these rules are definitions until the hand-labelling of experiment program
#     section 3.4 calibrates them (see Get-HordeOrcMeasures).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). Needs core/Tristate.ps1,
# core/Transcript.ps1 and core/Price.ps1.

# Study 1.4 and experiment program A5: a "still waiting" call has no tool call and fewer than this
# many characters of text. Chosen by the study's author on 2026-09-30; validated by EP 3.4 (hand-label
# 20 turns, precision and recall at least 0.9) before it is promoted. A parameter, not a magic number.
$script:HordeStillWaitingMaxChars = 400
# Study 1.4: MEASURED from the orchestrator itself, 53 pairs of consecutive calls with one tool result
# over 4,000 characters between them; context growth divided into result size, median 2.38 (IQR 2.27
# to 2.53). It includes harness overhead, so it slightly overstates tokens per character of content.
# Tokens from it are ESTIMATED; plan step M2 replaces it with the usage delta (study 4.5).
$script:HordeCharsPerToken = [decimal]2.38

# THE ORDER M1'S SORT PUT TIED RECORDS IN. M1 found the longest silence by sorting every record with
# Sort-Object on (time, line), and reported the kind of the record just before it. Sort-Object on
# PowerShell 5.1 is NOT stable: measured 2026-10-02, 17,773 of 50,000 records with tied keys came out
# in a different order than they went in. So when the records just before the longest silence share
# a time and a line (a call and the tool call it makes, written on one line), which kind M1 reported
# depends on how the sort happened to run. To keep the output byte for byte M1's (plan step M2), that
# one case replays the same sort - List.Sort with a comparer on the same two keys, the algorithm
# Sort-Object uses - over two compact arrays instead of the records; measured the same day to give
# the identical order on 10, 17, 1,000, 50,000 and 160,000 records with random ties. A stable rule
# is a change of output, and belongs in its own pull request.
class HordeRecordOrderComparer : System.Collections.Generic.IComparer[object] {
    [long[]]$Ticks
    [int[]]$Lines
    [int] Compare([object]$a, [object]$b) {
        $x = [int]$a; $y = [int]$b
        $c = $this.Ticks[$x].CompareTo($this.Ticks[$y])
        if ($c -ne 0) { return $c }
        return $this.Lines[$x].CompareTo($this.Lines[$y])
    }
}

function New-HordeMetricsAccumulator {
    # RUNNING TOTALS for one transcript (plan step M2). Records are folded in one at a time, in file
    # order, through Add(record), and none is kept: measured 2026-10-02 on the always-on box, M1's
    # summary held the records and an answer object for each, about 11 MB of memory per MB of
    # transcript (1,734 MB on 133 MB). What is kept per record is three numbers - its time, its line
    # and its kind - for the longest silence, which needs every time; per call, its id; per tool call
    # with a result, the result's time. Complete-HordeMetricsAccumulator gives { worker; orc }, the
    # same values Get-HordeWorkerSummary and Get-HordeOrcMeasures gave in M1.
    #
    # -From and -To keep only the records inside the window, as M1's Select-HordeRecordsInWindow did.
    # -PriceTable is an answer from Read-HordePriceBook; -MaxChars the still-waiting limit.
    param($PriceTable = $null, [int]$MaxChars = $script:HordeStillWaitingMaxChars, $From = $null, $To = $null)
    if ($null -eq $PriceTable) { $PriceTable = New-HordeAbsent -Note "no price table" }
    $a = [pscustomobject]@{
        priceTable = $PriceTable; maxChars = $MaxChars; from = $From; to = $To
        ticks = (New-Object 'System.Collections.Generic.List[long]'); lines = (New-Object 'System.Collections.Generic.List[int]'); kinds = (New-Object 'System.Collections.Generic.List[byte]')
        seen = (New-Object 'System.Collections.Generic.HashSet[string]'); calls = 0; duplicates = 0
        tokens = [ordered]@{ input = [long]0; cacheRead = [long]0; cacheWrite = [long]0; cacheWrite5m = [long]0; cacheWrite1h = [long]0; cacheWriteUnsplit = [long]0; output = [long]0 }; tokensMissing = 0
        models = [ordered]@{}; usageTotal = $null
        toolCalls = 0; resultTicks = (New-Object 'System.Collections.Generic.Dictionary[string,long]'); pending = @{}; open = 0; backwards = 0; longest = $null
        turns = 0; compactions = 0
        costSum = [decimal]0; costBad = 0; costFirst = ""; costUsed = (New-Object System.Collections.ArrayList)
        notifications = 0; interim = 0; unrecognised = 0
        wait = [ordered]@{ calls = 0; contextTokens = [long]0; outputTokens = [long]0; callsWithoutUsage = 0; afterUnrecognisedNote = 0; byWorker = [ordered]@{}; jobs = 0; unattributed = 0; lines = New-Object System.Collections.ArrayList }
        trigger = $null; personSpoke = $false
        landed = [ordered]@{ byWorker = [ordered]@{}; workerChars = [long]0; unattributedChars = [long]0; unattributedCount = 0; jobChars = [long]0; jobCount = 0; charsPerToken = $script:HordeCharsPerToken; confidence = "estimated"; tag = "ESTIMATE" }
    }
    $a | Add-Member -MemberType ScriptMethod -Name Add -Value { param($Record) Add-HordeMetricsRecord -Accumulator $this -Record $Record }
    return $a
}

function Add-HordeLandedWorker {
    # One worker result landing in the context: its characters, and whether by notification or result.
    param($Landed, [string]$Id, [long]$Chars, [string]$How)
    if (-not $Landed.byWorker.Contains($Id)) { $Landed.byWorker[$Id] = [pscustomobject]@{ chars = [long]0; notifications = 0; toolResults = 0 } }
    $e = $Landed.byWorker[$Id]
    $e.chars += $Chars
    if ($How -eq "notification") { $e.notifications++ } else { $e.toolResults++ }
    $Landed.workerChars += $Chars
}

function Resolve-HordeToolDuration {
    # A tool call whose duration is now known: counted apart when its result is timed before it (review
    # of PR #50, F9), otherwise a candidate for the longest. M1 walked the tool calls in file order and
    # kept the first of the longest; here they end in any order, so a tie goes to the earlier call.
    param($Acc, $Call, [long]$EndTicks, [bool]$Returned)
    $sec = [TimeSpan]::FromTicks($EndTicks - $Call.ticks).TotalSeconds
    if ($sec -lt 0) { $Acc.backwards++; return }
    $b = $Acc.longest
    if ($null -eq $b -or $sec -gt $b.sec -or ($sec -eq $b.sec -and $Call.index -lt $b.index)) {
        $Acc.longest = [pscustomobject]@{ sec = $sec; index = $Call.index; name = $Call.name; ticks = $Call.ticks; line = $Call.line; returned = $Returned }
    }
}

function Add-HordeMetricsRecord {
    # Fold one record into the running totals. The rules are M1's, rule for rule; each comment that
    # says why is where M1 said it.
    param($Accumulator, $Record)
    $acc = $Accumulator; $r = $Record
    if (($null -ne $acc.from -and $r.ts -lt $acc.from) -or ($null -ne $acc.to -and $r.ts -gt $acc.to)) { return }
    $acc.ticks.Add($r.ts.Ticks); $acc.lines.Add($r.line); $acc.kinds.Add([byte][array]::IndexOf($script:HordeTranscriptKinds, $r.kind))

    # The orchestrator's still-waiting state, in M1's order: a person speaking, then a trigger.
    if ($r.kind -eq "input" -and $r.source -eq "user") { $acc.personSpoke = $true }
    switch ($r.kind) {
        "call" {
            # ONE COUNT PER ID, whatever an adapter does: summing per line inflated one harness's totals
            # about 1.6x to 1.9x (metrics design 2.1).
            if (-not $acc.seen.Add("$($r.id)")) { $acc.duplicates++; return }
            $acc.calls++
            $t = $acc.tokens
            if ($r.usage.state -ne "known") { $acc.tokensMissing++ }
            else {
                $u = $r.usage.value
                $t.input += $u.input; $t.cacheRead += $u.cacheRead; $t.cacheWrite += $u.cacheWrite; $t.output += $u.output
                if ($u.cacheWriteSplit.state -eq "known") { $t.cacheWrite5m += $u.cacheWriteSplit.value.m5; $t.cacheWrite1h += $u.cacheWriteSplit.value.h1 }
                else { $t.cacheWriteUnsplit += $u.cacheWrite }
            }
            $m = "?"; if ($r.model.state -eq "known") { $m = "$($r.model.value)" }
            if ($acc.models.Contains($m)) { $acc.models[$m]++ } else { $acc.models[$m] = 1 }
            if ($acc.priceTable.state -eq "known") {
                $one = Get-HordeCallCost -Table $acc.priceTable.value -Call $r
                if ($one.state -eq "known") { $acc.costSum += $one.value; $src = Get-HordePriceSource -Table $acc.priceTable.value -Model "$($r.model.value)"; if ($acc.costUsed -notcontains $src) { [void]$acc.costUsed.Add($src) } }
                else { $acc.costBad++; if ($acc.costFirst -eq "") { $acc.costFirst = $one.reason } }
            }
            # STILL WAITING (study 1.4, EP A5; see Get-HordeOrcMeasures for the rules and why).
            $wait = $acc.wait
            $trigger = $acc.trigger
            $isWait = ($r.toolCallCount -eq 0 -and $r.textChars -lt $acc.maxChars -and $null -ne $trigger -and $trigger.kind -eq "input" -and $trigger.source -eq "notification" -and $trigger.interim -eq $true -and -not $acc.personSpoke)
            $personSpokeThen = $acc.personSpoke
            $acc.trigger = $null
            $acc.personSpoke = $false
            # A reply that would be still-waiting but for a note in unknown wording is counted apart.
            if (-not $isWait -and $r.toolCallCount -eq 0 -and $r.textChars -lt $acc.maxChars -and $null -ne $trigger -and $trigger.kind -eq "input" -and $trigger.source -eq "notification" -and -not $personSpokeThen -and $null -ne $trigger.PSObject.Properties["noteKind"] -and $trigger.noteKind -ceq "unrecognised") { $wait.afterUnrecognisedNote++ }
            if (-not $isWait) { return }
            $wait.calls++
            [void]$wait.lines.Add($r.line)
            if ($r.usage.state -eq "known") {
                $uv = $r.usage.value
                $wait.contextTokens += ($uv.input + $uv.cacheRead + $uv.cacheWrite)
                $wait.outputTokens += $uv.output
            } else { $wait.callsWithoutUsage++ }
            # Attributed through the notification that triggered it, and only as far as it proves.
            $w = $trigger.worker
            if ($w.state -eq "known") { $id = "$($w.value)"; if ($wait.byWorker.Contains($id)) { $wait.byWorker[$id]++ } else { $wait.byWorker[$id] = 1 } }
            elseif ($w.state -eq "absent") { $wait.jobs++ }
            else { $wait.unattributed++ }
            return
        }
        "toolCall" {
            # TOOL CALLS, paired with the FIRST result of the same id wherever it is in the file. One
            # still waiting for its result is held until the result comes, or the end.
            $tc = [pscustomobject]@{ index = $acc.toolCalls; ticks = $r.ts.Ticks; line = $r.line; name = $r.name }
            $acc.toolCalls++
            $id = "$($r.id)"
            $end = [long]0
            if ($acc.resultTicks.TryGetValue($id, [ref]$end)) { Resolve-HordeToolDuration -Acc $acc -Call $tc -EndTicks $end -Returned $true }
            else {
                if (-not $acc.pending.ContainsKey($id)) { $acc.pending[$id] = New-Object System.Collections.ArrayList }
                [void]$acc.pending[$id].Add($tc)
            }
            return
        }
        "toolResult" {
            $acc.trigger = $r; $id = "$($r.toolCallId)"
            if (-not $acc.resultTicks.ContainsKey($id)) {
                $acc.resultTicks[$id] = $r.ts.Ticks
                if ($acc.pending.ContainsKey($id)) {
                    foreach ($tc in $acc.pending[$id]) { Resolve-HordeToolDuration -Acc $acc -Call $tc -EndTicks $r.ts.Ticks -Returned $true }
                    $acc.pending.Remove($id)
                }
            }
            # LANDED: the result of a worker launch lands on its worker; one that cannot be proved is
            # unattributed; an ordinary tool's result is not a worker's.
            if ($r.worker.state -ne "absent") {
                if ($r.worker.state -eq "known") { Add-HordeLandedWorker -Landed $acc.landed -Id "$($r.worker.value)" -Chars ([long]$r.chars) -How "toolResult" }
                else { $acc.landed.unattributedChars += [long]$r.chars; $acc.landed.unattributedCount++ }
            }
            return
        }
        "input" {
            $acc.trigger = $r
            if ($r.source -ne "notification") { return }
            $acc.notifications++
            if ($r.interim -eq $true) { $acc.interim++ }
            # A note the adapter could not classify is counted, never read as final (verification of
            # PR #50, 2026-10-02). An adapter that gives no noteKind gives none.
            if ($null -ne $r.PSObject.Properties["noteKind"] -and $r.noteKind -ceq "unrecognised") { $acc.unrecognised++ }
            if ($r.worker.state -eq "known") { Add-HordeLandedWorker -Landed $acc.landed -Id "$($r.worker.value)" -Chars ([long]$r.chars) -How "notification" }
            elseif ($r.worker.state -eq "absent") { $acc.landed.jobChars += $r.chars; $acc.landed.jobCount++ }
            else { $acc.landed.unattributedChars += $r.chars; $acc.landed.unattributedCount++ }
            return
        }
        "usageTotal" { $acc.usageTotal = $r.usage; return }
        "turnEnd" { $acc.turns++; return }
        "compaction" { $acc.compactions++; return }
    }
}

function Get-HordeLongestGap {
    # THE LONGEST SILENCE: the widest gap between consecutive events of ANY kind, in time order, so a
    # gap is a stretch where the transcript says nothing at all. The study counted gaps of 5 minutes and
    # more (study 1.4); the longest is reported here, with when it began and what came before it - the
    # first of the widest, as M1's walk over its sorted records found it.
    param($Acc)
    $n = $Acc.ticks.Count
    $sorted = $Acc.ticks.ToArray()
    [Array]::Sort($sorted)
    $best = $null; $bestAt = 0
    for ($i = 1; $i -lt $n; $i++) {
        $g = [TimeSpan]::FromTicks($sorted[$i] - $sorted[$i - 1]).TotalSeconds
        if ($null -eq $best -or $g -gt $best) { $best = [decimal]$g; $bestAt = $i }
    }
    # The record just before it, among those at that time: the last by line when time moved, or, when
    # every record has one time, the first. Which of several records on that one line M1's sort put
    # there is replayed only when they differ in kind (HordeRecordOrderComparer).
    $at = $sorted[$bestAt - 1]
    $last = ($sorted[$bestAt] -ne $at)
    $line = $null
    for ($k = 0; $k -lt $n; $k++) {
        if ($Acc.ticks[$k] -ne $at) { continue }
        if ($null -eq $line -or ($last -and $Acc.lines[$k] -gt $line) -or (-not $last -and $Acc.lines[$k] -lt $line)) { $line = $Acc.lines[$k] }
    }
    $tied = New-Object System.Collections.ArrayList
    for ($k = 0; $k -lt $n; $k++) { if ($Acc.ticks[$k] -eq $at -and $Acc.lines[$k] -eq $line) { [void]$tied.Add($k) } }
    $pick = $tied[0]
    $kinds = @($tied | ForEach-Object { $Acc.kinds[$_] } | Sort-Object -Unique)
    if ($kinds.Count -gt 1) {
        $cmp = [HordeRecordOrderComparer]::new()
        $cmp.Ticks = $Acc.ticks.ToArray(); $cmp.Lines = $Acc.lines.ToArray()
        $order = New-Object 'System.Collections.Generic.List[object]'
        for ($k = 0; $k -lt $n; $k++) { $order.Add([object]$k) }
        $order.Sort($cmp)
        $want = New-Object 'System.Collections.Generic.HashSet[int]'
        foreach ($k in $tied) { [void]$want.Add([int]$k) }
        $found = $null
        for ($p = 0; $p -lt $n; $p++) {
            $k = [int]$order[$p]
            if ($want.Contains($k)) { $found = $k; if (-not $last) { break } }
        }
        $pick = $found
    }
    return [pscustomobject]@{ seconds = $best; startedAt = (New-Object DateTime ($at, [DateTimeKind]::Utc)); afterKind = $script:HordeTranscriptKinds[$Acc.kinds[$pick]]; afterLine = $Acc.lines[$pick] }
}

function Complete-HordeMetricsAccumulator {
    # The measures from the running totals: { worker; orc }, each built in M1's order of fields, so
    # the record M1 wrote is written again.
    param($Accumulator)
    $acc = $Accumulator
    $n = $acc.ticks.Count
    $s = [ordered]@{}
    $lastTicks = [long]0
    if ($n -eq 0) {
        $none = New-HordeAbsent -Note "the transcript has no timestamped events"
        foreach ($k in @("firstEventAt", "lastEventAt", "wallClockSeconds", "longestGap", "longestToolCall", "model")) { $s[$k] = $none }
    } else {
        $firstTicks = [long]::MaxValue; $lastTicks = [long]::MinValue
        foreach ($t in $acc.ticks) { if ($t -lt $firstTicks) { $firstTicks = $t }; if ($t -gt $lastTicks) { $lastTicks = $t } }
        $first = New-Object DateTime ($firstTicks, [DateTimeKind]::Utc); $last = New-Object DateTime ($lastTicks, [DateTimeKind]::Utc)
        $s.firstEventAt = New-HordeKnown -Value $first
        $s.lastEventAt = New-HordeKnown -Value $last
        $s.wallClockSeconds = New-HordeKnown -Value ([decimal]($last - $first).TotalSeconds)
        if ($n -lt 2) { $s.longestGap = New-HordeAbsent -Note "one event, so no gap" }
        else { $s.longestGap = New-HordeKnown -Value (Get-HordeLongestGap -Acc $acc) }
    }

    $s.calls = New-HordeKnown -Value $acc.calls
    $s.duplicateCallRecords = $acc.duplicates
    # Unknown when any call has no usage, naming how many: a total missing calls is a smaller number
    # that would look like a real one.
    if ($acc.tokensMissing -gt 0) { $s.tokens = New-HordeUnknown -Reason ("" + $acc.tokensMissing + " of " + $acc.calls + " calls carry no usage") }
    else { $s.tokens = New-HordeKnown -Value ([pscustomobject]$acc.tokens) }
    if ($null -ne $acc.usageTotal) { $s.tokensReportedTotal = $acc.usageTotal } else { $s.tokensReportedTotal = New-HordeAbsent -Note "the harness writes no cumulative total" }

    $models = $acc.models
    $s.models = $models
    if ($acc.calls -gt 0) {
        $knownModels = @($models.Keys | Where-Object { $_ -ne "?" })
        if ($knownModels.Count -eq 0) { $s.model = New-HordeUnknown -Reason "no call names its model" }
        else { $s.model = New-HordeKnown -Value (@($knownModels | Sort-Object -Property @{ Expression = { $models[$_] }; Descending = $true }, @{ Expression = { $_ } })[0]) }
    } elseif ($n -gt 0) { $s.model = New-HordeAbsent -Note "the transcript has no model calls" }

    # A tool call with no result is still in flight, or never came back: it is counted up to the last
    # event and flagged, because the study's two longest stalls were calls that sat 314 and 325
    # minutes before their results landed (study 5.1), and a frozen call never gets a result at all.
    foreach ($list in @($acc.pending.Values)) {
        foreach ($tc in $list) { $acc.open++; Resolve-HordeToolDuration -Acc $acc -Call $tc -EndTicks $lastTicks -Returned $false }
    }
    $acc.pending = @{}
    $s.toolCalls = New-HordeKnown -Value $acc.toolCalls
    $s.toolCallsWithoutResult = $acc.open
    $s.toolCallsWithNegativeDuration = $acc.backwards
    $lg = $acc.longest
    if ($acc.toolCalls -eq 0) { $s.longestToolCall = New-HordeAbsent -Note "no tool calls" }
    elseif ($null -eq $lg) { $s.longestToolCall = New-HordeUnknown -Reason "every tool call's result is timed before it" }
    else { $s.longestToolCall = New-HordeKnown -Value ([pscustomobject]@{ seconds = [decimal]$lg.sec; name = $lg.name; startedAt = (New-Object DateTime ($lg.ticks, [DateTimeKind]::Utc)); returned = $lg.returned; line = $lg.line }) }
    $s.turns = New-HordeKnown -Value $acc.turns
    $s.compactions = $acc.compactions

    # The notional cost, { cost (answer); unit; confidence; tag; priceTables }, where priceTables names
    # each table - file and version - that priced one of the calls. Unknown when there is no table or
    # any call cannot be priced: a partial total is not a total.
    $cost = [ordered]@{ cost = $null; unit = "notionalUsd"; confidence = "derived"; tag = "ESTIMATE"; priceTables = @() }
    if ($acc.priceTable.state -ne "known") {
        $cost.cost = New-HordeUnknown -Reason ("no usable price table: " + $acc.priceTable.reason)
        $cost.confidence = "unknown"
    } else {
        if ($acc.costBad -gt 0) {
            $cost.cost = New-HordeUnknown -Reason ("" + $acc.costBad + " of " + $acc.calls + " calls cannot be priced; the first: " + $acc.costFirst)
            $cost.confidence = "unknown"
        } else { $cost.cost = New-HordeKnown -Value $acc.costSum }
        $cost.priceTables = @($acc.costUsed | Sort-Object)
    }
    $s.cost = [pscustomobject]$cost

    $o = [ordered]@{}
    $o.notifications = $acc.notifications
    $o.interimNotifications = $acc.interim
    $o.unrecognisedNotes = $acc.unrecognised
    $wait = $acc.wait
    # A TOTAL MISSING SOME CALLS IS NOT A TOTAL (review of PR #50, F6): the sums become answers, unknown
    # when any still-waiting call has no usage, naming how many and the part that is known.
    foreach ($k in @("contextTokens", "outputTokens")) {
        if ($wait.callsWithoutUsage -gt 0) { $wait[$k] = New-HordeUnknown -Reason ("" + $wait.callsWithoutUsage + " of " + $wait.calls + " still-waiting calls have no usage; the known part is " + $wait[$k]) }
        else { $wait[$k] = New-HordeKnown -Value $wait[$k] }
    }
    $o.stillWaiting = [pscustomobject]$wait
    $landed = $acc.landed
    $landed.workerTokensEstimated = [long][Math]::Round([decimal]$landed.workerChars / $script:HordeCharsPerToken)
    $landed.unattributedTokensEstimated = [long][Math]::Round([decimal]$landed.unattributedChars / $script:HordeCharsPerToken)
    $o.landed = [pscustomobject]$landed
    return [pscustomobject]@{ worker = [pscustomobject]$s; orc = [pscustomobject]$o }
}

function Get-HordeWorkerSummary {
    # One transcript's summary: wall-clock, tokens by kind, model calls, tool calls, the longest silence
    # and the longest tool call, the model, and the notional cost. -Records are port records;
    # -PriceTable an answer from Read-HordePriceBook. Times are UTC. The records are folded through the
    # running totals (New-HordeMetricsAccumulator), the one place the rules live.
    param([Parameter(Mandatory = $true)]$Records, [Parameter(Mandatory = $true)]$PriceTable)
    $acc = New-HordeMetricsAccumulator -PriceTable $PriceTable
    foreach ($r in @($Records)) { Add-HordeMetricsRecord -Accumulator $acc -Record $r }
    return (Complete-HordeMetricsAccumulator -Accumulator $acc).worker
}

function Get-HordeOrcMeasures {
    # The orchestrator-side measures of the study, from one transcript's records.
    #
    # A STILL-WAITING CALL (study 1.4, EP A5): a model call that makes no tool call, writes fewer than
    # -MaxChars characters, and whose TRIGGER is a notification - the trigger being the last input or
    # tool result between the previous call and this one. That rule is stricter than the study's
    # script, which looked only at the last user-side message and ignored tool results in between
    # (join.js); a call answering a tool result is not answering a notification. The context it
    # processed is input plus cache read plus cache write: what the call paid to say "still waiting".
    #
    # TWO MORE RULES, decided 2026-10-02 (coordinator, after review of PR #50): the triggering
    # notification must be INTERIM - a short reply to a final notification is a report, never waiting -
    # and no person may have spoken since the previous call, or the reply is answering the person.
    # EP 3.4's hand-labelling of 20 orchestrator turns will calibrate these rules and the 400-character
    # limit; until then they are definitions, not measurements.
    #
    # LANDED: the characters of worker results that entered this context - notifications about a
    # worker, and results of the tool that launches one - with tokens ESTIMATED at the study's
    # measured ratio. A notification about something that is provably not a worker (a background
    # shell job) is counted apart, as a job, never as a worker. A notification whose subject cannot be
    # proved is UNATTRIBUTED: it is counted, and given to no worker. The study's attribution by "a
    # message naming the worker in the same turn" is not used (study section 9, item 3: it
    # over-attributes and under-attributes).
    #
    # The rules themselves are applied in Add-HordeMetricsRecord, record by record.
    param([Parameter(Mandatory = $true)]$Records, [int]$MaxChars = $script:HordeStillWaitingMaxChars)
    $acc = New-HordeMetricsAccumulator -MaxChars $MaxChars
    foreach ($r in @($Records)) { Add-HordeMetricsRecord -Accumulator $acc -Record $r }
    return (Complete-HordeMetricsAccumulator -Accumulator $acc).orc
}
