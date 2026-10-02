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
#     proves the link.
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

function Get-HordeUniqueCalls {
    # The call records, one per id, in file order, and how many repeats were dropped. The adapter
    # already merges one request's lines; this refuses to count an id twice whatever an adapter does,
    # because summing per line inflated one harness's totals about 1.6x to 1.9x (metrics design 2.1).
    param($Records)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $calls = New-Object System.Collections.ArrayList
    $dup = 0
    foreach ($r in @($Records)) {
        if ($r.kind -ne "call") { continue }
        if ($seen.Add("$($r.id)")) { [void]$calls.Add($r) } else { $dup++ }
    }
    return [pscustomobject]@{ calls = $calls.ToArray(); duplicates = $dup }
}

function Get-HordeTokenTotals {
    # Tokens by kind over calls, as an answer. Unknown when any call has no usage, naming how many,
    # because a total missing calls is a smaller number that would look like a real one.
    param($Calls)
    $t = [ordered]@{ input = [long]0; cacheRead = [long]0; cacheWrite = [long]0; cacheWrite5m = [long]0; cacheWrite1h = [long]0; cacheWriteUnsplit = [long]0; output = [long]0 }
    $missing = 0
    foreach ($c in @($Calls)) {
        if ($c.usage.state -ne "known") { $missing++; continue }
        $u = $c.usage.value
        $t.input += $u.input; $t.cacheRead += $u.cacheRead; $t.cacheWrite += $u.cacheWrite; $t.output += $u.output
        if ($u.cacheWriteSplit.state -eq "known") { $t.cacheWrite5m += $u.cacheWriteSplit.value.m5; $t.cacheWrite1h += $u.cacheWriteSplit.value.h1 }
        else { $t.cacheWriteUnsplit += $u.cacheWrite }
    }
    if ($missing -gt 0) { return (New-HordeUnknown -Reason ("" + $missing + " of " + @($Calls).Count + " calls carry no usage")) }
    return (New-HordeKnown -Value ([pscustomobject]$t))
}

function Get-HordeCostTotal {
    # The notional cost of the calls, as { cost (answer); unit; confidence; tag; priceTables }, where
    # priceTables names each table - file and version - that priced one of the calls, so a figure from
    # an override is never mistaken for one from the repository. Unknown when there is no table or any
    # call cannot be priced: a partial total is not a total.
    param($Calls, $PriceTable)
    $out = [ordered]@{ cost = $null; unit = "notionalUsd"; confidence = "derived"; tag = "ESTIMATE"; priceTables = @() }
    if ($PriceTable.state -ne "known") {
        $out.cost = New-HordeUnknown -Reason ("no usable price table: " + $PriceTable.reason)
        $out.confidence = "unknown"
        return [pscustomobject]$out
    }
    $sum = [decimal]0; $bad = 0; $first = ""; $used = @()
    foreach ($c in @($Calls)) {
        $one = Get-HordeCallCost -Table $PriceTable.value -Call $c
        if ($one.state -eq "known") { $sum += $one.value; $src = Get-HordePriceSource -Table $PriceTable.value -Model "$($c.model.value)"; if ($used -notcontains $src) { $used += $src } }
        else { $bad++; if ($first -eq "") { $first = $one.reason } }
    }
    if ($bad -gt 0) {
        $out.cost = New-HordeUnknown -Reason ("" + $bad + " of " + @($Calls).Count + " calls cannot be priced; the first: " + $first)
        $out.confidence = "unknown"
    } else { $out.cost = New-HordeKnown -Value $sum }
    $out.priceTables = @($used | Sort-Object)
    return [pscustomobject]$out
}

function Get-HordeWorkerSummary {
    # One transcript's summary. -Records are port records; -PriceTable an answer from
    # Read-HordePriceBook. Times are UTC.
    param([Parameter(Mandatory = $true)]$Records, [Parameter(Mandatory = $true)]$PriceTable)
    $all = @($Records)
    $timed = @($all | Sort-Object -Property @{ Expression = { $_.ts } }, @{ Expression = { $_.line } })
    $s = [ordered]@{}
    if ($timed.Count -eq 0) {
        $none = New-HordeAbsent -Note "the transcript has no timestamped events"
        foreach ($k in @("firstEventAt", "lastEventAt", "wallClockSeconds", "longestGap", "longestToolCall", "model")) { $s[$k] = $none }
    } else {
        $first = $timed[0].ts; $last = $timed[$timed.Count - 1].ts
        $s.firstEventAt = New-HordeKnown -Value $first
        $s.lastEventAt = New-HordeKnown -Value $last
        $s.wallClockSeconds = New-HordeKnown -Value ([decimal]($last - $first).TotalSeconds)
        # THE LONGEST SILENCE: the widest gap between consecutive events of ANY kind, so a gap is a
        # stretch where the transcript says nothing at all. The study counted gaps of 5 minutes and
        # more (study 1.4); the longest is reported here, with when it began and what came before it.
        if ($timed.Count -lt 2) { $s.longestGap = New-HordeAbsent -Note "one event, so no gap" }
        else {
            $best = $null
            for ($i = 1; $i -lt $timed.Count; $i++) {
                $g = ($timed[$i].ts - $timed[$i - 1].ts).TotalSeconds
                if ($null -eq $best -or $g -gt $best.seconds) { $best = [pscustomobject]@{ seconds = [decimal]$g; startedAt = $timed[$i - 1].ts; afterKind = $timed[$i - 1].kind; afterLine = $timed[$i - 1].line } }
            }
            $s.longestGap = New-HordeKnown -Value $best
        }
    }

    $u = Get-HordeUniqueCalls -Records $all
    $calls = @($u.calls)
    $s.calls = New-HordeKnown -Value $calls.Count
    $s.duplicateCallRecords = $u.duplicates
    $s.tokens = Get-HordeTokenTotals -Calls $calls
    $totals = @($all | Where-Object { $_.kind -eq "usageTotal" })
    if ($totals.Count -gt 0) { $s.tokensReportedTotal = $totals[$totals.Count - 1].usage } else { $s.tokensReportedTotal = New-HordeAbsent -Note "the harness writes no cumulative total" }

    $models = [ordered]@{}
    foreach ($c in $calls) { $m = "?"; if ($c.model.state -eq "known") { $m = "$($c.model.value)" }; if ($models.Contains($m)) { $models[$m]++ } else { $models[$m] = 1 } }
    $s.models = $models
    if ($calls.Count -gt 0) {
        $knownModels = @($models.Keys | Where-Object { $_ -ne "?" })
        if ($knownModels.Count -eq 0) { $s.model = New-HordeUnknown -Reason "no call names its model" }
        else { $s.model = New-HordeKnown -Value (@($knownModels | Sort-Object -Property @{ Expression = { $models[$_] }; Descending = $true }, @{ Expression = { $_ } })[0]) }
    } elseif ($timed.Count -gt 0) { $s.model = New-HordeAbsent -Note "the transcript has no model calls" }

    # TOOL CALLS, paired with their results by id. Duration is result time minus call time. A call
    # with no result is still in flight, or never came back: it is counted up to the last event and
    # flagged, because the study's two longest stalls were calls that sat 314 and 325 minutes before
    # their results landed (study 5.1), and a frozen call never gets a result line at all.
    $tools = @($all | Where-Object { $_.kind -eq "toolCall" })
    $results = @{}
    foreach ($r in @($all | Where-Object { $_.kind -eq "toolResult" })) { if (-not $results.ContainsKey("$($r.toolCallId)")) { $results["$($r.toolCallId)"] = $r } }
    $s.toolCalls = New-HordeKnown -Value $tools.Count
    $open = 0; $longest = $null
    foreach ($tc in $tools) {
        $res = $results["$($tc.id)"]
        if ($null -ne $res) { $sec = ($res.ts - $tc.ts).TotalSeconds; $returned = $true }
        else { $open++; $sec = ($timed[$timed.Count - 1].ts - $tc.ts).TotalSeconds; $returned = $false }
        if ($null -eq $longest -or $sec -gt $longest.seconds) { $longest = [pscustomobject]@{ seconds = [decimal]$sec; name = $tc.name; startedAt = $tc.ts; returned = $returned; line = $tc.line } }
    }
    $s.toolCallsWithoutResult = $open
    if ($tools.Count -eq 0) { $s.longestToolCall = New-HordeAbsent -Note "no tool calls" } else { $s.longestToolCall = New-HordeKnown -Value $longest }
    $s.turns = New-HordeKnown -Value @($all | Where-Object { $_.kind -eq "turnEnd" }).Count
    $s.compactions = @($all | Where-Object { $_.kind -eq "compaction" }).Count
    $s.cost = Get-HordeCostTotal -Calls $calls -PriceTable $PriceTable
    return [pscustomobject]$s
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
    # LANDED: the characters of worker results that entered this context - notifications about a
    # worker, and results of the tool that launches one - with tokens ESTIMATED at the study's
    # measured ratio. A notification about something that is provably not a worker (a background
    # shell job) is counted apart, as a job, never as a worker. A notification whose subject cannot be
    # proved is UNATTRIBUTED: it is counted, and given to no worker. The study's attribution by "a
    # message naming the worker in the same turn" is not used (study section 9, item 3: it
    # over-attributes and under-attributes).
    param([Parameter(Mandatory = $true)]$Records, [int]$MaxChars = $script:HordeStillWaitingMaxChars)
    $all = @($Records)
    $notifications = @($all | Where-Object { $_.kind -eq "input" -and $_.source -eq "notification" })
    $o = [ordered]@{}
    $o.notifications = $notifications.Count
    $o.interimNotifications = @($notifications | Where-Object { $_.interim -eq $true }).Count

    $wait = [ordered]@{ calls = 0; contextTokens = [long]0; outputTokens = [long]0; callsWithoutUsage = 0; byWorker = [ordered]@{}; jobs = 0; unattributed = 0; lines = New-Object System.Collections.ArrayList }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $trigger = $null
    foreach ($r in $all) {
        if ($r.kind -eq "input" -or $r.kind -eq "toolResult") { $trigger = $r; continue }
        if ($r.kind -ne "call") { continue }
        if (-not $seen.Add("$($r.id)")) { continue }
        $isWait = ($r.toolCallCount -eq 0 -and $r.textChars -lt $MaxChars -and $null -ne $trigger -and $trigger.kind -eq "input" -and $trigger.source -eq "notification")
        $trig = $trigger
        $trigger = $null
        if (-not $isWait) { continue }
        $wait.calls++
        [void]$wait.lines.Add($r.line)
        if ($r.usage.state -eq "known") {
            $uv = $r.usage.value
            $wait.contextTokens += ($uv.input + $uv.cacheRead + $uv.cacheWrite)
            $wait.outputTokens += $uv.output
        } else { $wait.callsWithoutUsage++ }
        # Attributed through the notification that triggered it, and only as far as that notification
        # proves its subject.
        $w = $trig.worker
        if ($w.state -eq "known") { $id = "$($w.value)"; if ($wait.byWorker.Contains($id)) { $wait.byWorker[$id]++ } else { $wait.byWorker[$id] = 1 } }
        elseif ($w.state -eq "absent") { $wait.jobs++ }
        else { $wait.unattributed++ }
    }
    $o.stillWaiting = [pscustomobject]$wait

    $landed = [ordered]@{ byWorker = [ordered]@{}; workerChars = [long]0; unattributedChars = [long]0; unattributedCount = 0; jobChars = [long]0; jobCount = 0; charsPerToken = $script:HordeCharsPerToken; confidence = "estimated"; tag = "ESTIMATE" }
    $addWorker = {
        param($Id, $Chars, [string]$How)
        if (-not $landed.byWorker.Contains($Id)) { $landed.byWorker[$Id] = [pscustomobject]@{ chars = [long]0; notifications = 0; toolResults = 0 } }
        $e = $landed.byWorker[$Id]
        $e.chars += $Chars
        if ($How -eq "notification") { $e.notifications++ } else { $e.toolResults++ }
        $landed.workerChars += $Chars
    }
    foreach ($r in $all) {
        if ($r.kind -eq "input" -and $r.source -eq "notification") {
            if ($r.worker.state -eq "known") { & $addWorker "$($r.worker.value)" ([long]$r.chars) "notification" }
            elseif ($r.worker.state -eq "absent") { $landed.jobChars += $r.chars; $landed.jobCount++ }
            else { $landed.unattributedChars += $r.chars; $landed.unattributedCount++ }
        }
        elseif ($r.kind -eq "toolResult" -and $r.worker.state -ne "absent") {
            if ($r.worker.state -eq "known") { & $addWorker "$($r.worker.value)" ([long]$r.chars) "toolResult" }
            else { $landed.unattributedChars += [long]$r.chars; $landed.unattributedCount++ }
        }
    }
    $landed.workerTokensEstimated = [long][Math]::Round([decimal]$landed.workerChars / $script:HordeCharsPerToken)
    $landed.unattributedTokensEstimated = [long][Math]::Round([decimal]$landed.unattributedChars / $script:HordeCharsPerToken)
    $o.landed = [pscustomobject]$landed
    return [pscustomobject]$o
}
