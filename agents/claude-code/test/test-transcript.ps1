# DOES THE CLAUDE CODE ADAPTER TURN A REAL-SHAPED TRANSCRIPT INTO THE RIGHT RECORDS, AND DO THE
# MEASURES FIND WHAT WAS PLANTED IN IT?
#
# Fixtures, under fixtures/metrics/: field names and nesting copied from real records read on
# 2026-10-01, every value invented. "planted" is an orchestrator transcript holding, on purpose:
# a response written as two lines, a "<synthetic>" API-error line, a worker launch and its
# notification (queued, with its queue-operation bookkeeping line), a background job and its
# notification, a notification nobody can resolve, three still-waiting replies (one per kind of
# subject), a 300-minute tool call, a compaction, and the string PLANTED-SECRET-7f3a in a prompt, a
# tool input, a tool result, wireToolInputs, last-prompt and a meta line. Its subagent and meta.json
# sit beside it. "clean" is an orchestrator transcript with a notification and no still-waiting reply.
#
# Everything this suite writes is under one folder in TEMP, removed at the end. HORDE_HOME and the
# harness's store variable are set only for the child processes it starts.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "ReadShared", "Home", "Transcript", "Price", "Metrics", "MetricsStore")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "agents\claude-code\Transcript.ps1")

$fixtures = Join-Path $here "fixtures\metrics"
$plantedPath = Join-Path $fixtures "planted\11111111-2222-4333-8444-555555555555.jsonl"
$subPath = Join-Path $fixtures "planted\11111111-2222-4333-8444-555555555555\subagents\agent-a1b2c3d4e5f6a7b8c.jsonl"
$cleanPath = Join-Path $fixtures "clean\22222222-3333-4444-8555-666666666666.jsonl"
$secret = "PLANTED-SECRET-7f3a"
$noTable = New-HordeAbsent -Note "no table"
$work = Join-Path $env:TEMP ("horde-cc-transcript-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null

try {
    Write-Host ""
    Write-Host "--- claiming files ---" -ForegroundColor Cyan
    Check ((Test-ClaudeCodeTranscript -Path $plantedPath) -eq $true) "CONTROL: the adapter claims a session transcript"
    Check ((Test-ClaudeCodeTranscript -Path $subPath) -eq $true) "and a subagent transcript"
    $other = Join-Path $work "other.jsonl"
    [System.IO.File]::WriteAllText($other, '{"timestamp":"2026-09-30T10:00:00.000Z","type":"session_meta","payload":{"id":"x"}}' + "`n")
    Check ((Test-ClaudeCodeTranscript -Path $other) -eq $false) "a file of { timestamp, type, payload } lines is not claimed"
    $meta = Join-Path $fixtures "planted\11111111-2222-4333-8444-555555555555\subagents\agent-a1b2c3d4e5f6a7b8c.meta.json"
    Check ((Test-ClaudeCodeTranscript -Path $meta) -eq $false) "a meta.json is not a transcript"

    Write-Host ""
    Write-Host "--- records ---" -ForegroundColor Cyan
    $script:HordeTranscriptAdapters.Clear()
    . (Join-Path $root "agents\claude-code\Transcript.ps1")
    $read = Read-HordeTranscript -Path $plantedPath
    Check ($read.state -eq "known" -and $read.value.adapter -eq "claude-code") "the planted transcript is read through this adapter, and keeps the port's contract"
    $recs = @($read.value.records)
    $calls = @($recs | Where-Object { $_.kind -eq "call" })
    Check ($calls.Count -eq 8) ("one call per message id, the API-error line excluded: 8 (" + $calls.Count + ")")
    $a1 = @($calls | Where-Object { $_.id -eq "msg_A1" })[0]
    Check ($a1.textChars -eq 19 -and $a1.toolCallCount -eq 1) "a response written as two lines is one call holding both lines' text and tool use"
    Check ($a1.usage.value.cacheWriteSplit.state -eq "known" -and $a1.usage.value.cacheWriteSplit.value.m5 -eq 200) "the cache write keeps its 5-minute and 1-hour split"
    Check (@($recs | Where-Object { $_.kind -eq "toolCall" }).Count -eq 3 -and @($recs | Where-Object { $_.kind -eq "toolResult" }).Count -eq 3) "three tool calls and their three results"
    $notes = @($recs | Where-Object { $_.kind -eq "input" -and $_.source -eq "notification" })
    Check ($notes.Count -eq 4) ("four notifications; the queue-operation copy of the queued one is not a fifth (" + $notes.Count + ")")
    $byCall = @{}; foreach ($n in $notes) { $byCall[$n.toolCallId] = $n }
    Check ($byCall["toolu_L1"].worker.state -eq "known" -and $byCall["toolu_L1"].worker.value -eq "a1b2c3d4e5f6a7b8c") "a notification about the call that launched a worker is that worker's"
    Check ($byCall["toolu_OLD"].worker.state -eq "known" -and $byCall["toolu_OLD"].worker.value -eq "a1b2c3d4e5f6a7b8c") "a notification whose call is not in this transcript is still the worker's when the subagents folder holds its transcript (a resumed worker)"
    Check ($byCall["toolu_B1"].worker.state -eq "absent") "a notification about a shell call is provably not a worker's"
    Check ($byCall["toolu_ZZ"].worker.state -eq "unknown") "a notification that resolves to nothing is unknown, not guessed"
    $launch = @($recs | Where-Object { $_.kind -eq "toolResult" -and $_.toolCallId -eq "toolu_L1" })[0]
    Check ($launch.worker.state -eq "known" -and $launch.worker.value -eq "a1b2c3d4e5f6a7b8c") "the launch call's result lands on the worker its meta.json names"
    $ordinary = @($recs | Where-Object { $_.kind -eq "toolResult" -and $_.toolCallId -eq "toolu_S1" })[0]
    Check ($ordinary.worker.state -eq "absent" -and $ordinary.isError.state -eq "known") "an ordinary tool's result is not a worker's, and says whether it failed"
    Check (@($recs | Where-Object { $_.kind -eq "turnEnd" }).Count -eq 5) "turn ends come from the turn_duration lines (5)"
    Check (@($recs | Where-Object { $_.kind -eq "compaction" }).Count -eq 1) "the compaction is recorded"
    Check (@($recs | Where-Object { $_.kind -eq "input" -and $_.source -eq "user" }).Count -eq 2) "the two prompts are user input; the harness's own meta line is not"
    $sub = Read-HordeTranscript -Path $subPath
    Check ($sub.state -eq "known" -and @($sub.value.records | Where-Object { $_.kind -eq "turnEnd" }).Count -eq 1) "a subagent transcript, which has no turn_duration lines, ends its turn at end_turn"

    Write-Host ""
    Write-Host "--- an independent recount ---" -ForegroundColor Cyan
    # EP 3.4, instrument check for worker tokens: a second instrument must agree exactly. This one is
    # PowerShell's own ConvertFrom-Json, not the adapter's parser, keyed by message id the way the
    # study's worker-extract.js was.
    $seen = @{}; $sum = @{ input = 0; cacheRead = 0; cacheWrite = 0; output = 0 }
    foreach ($line in [System.IO.File]::ReadAllLines($plantedPath)) {
        $o = $line | ConvertFrom-Json
        if ($o.type -ne "assistant" -or $o.message.model -eq "<synthetic>" -or $seen.ContainsKey($o.message.id)) { continue }
        $seen[$o.message.id] = $true
        $sum.input += $o.message.usage.input_tokens; $sum.cacheRead += $o.message.usage.cache_read_input_tokens
        $sum.cacheWrite += $o.message.usage.cache_creation_input_tokens; $sum.output += $o.message.usage.output_tokens
    }
    $ws = Get-HordeWorkerSummary -Records $recs -PriceTable $noTable
    $t = $ws.tokens.value
    Check ($t.input -eq $sum.input -and $t.cacheRead -eq $sum.cacheRead -and $t.cacheWrite -eq $sum.cacheWrite -and $t.output -eq $sum.output) ("the adapter's token totals equal an independent recount (output " + $t.output + " = " + $sum.output + ", cache read " + $t.cacheRead + " = " + $sum.cacheRead + ")")
    Check ($sum.output -eq 429) "CONTROL: the recount itself found the fixture's 429 output tokens"

    Write-Host ""
    Write-Host "--- the planted measures are found ---" -ForegroundColor Cyan
    Check ($ws.longestToolCall.value.seconds -eq 18000 -and $ws.longestToolCall.value.name -eq "Bash" -and $ws.longestToolCall.value.returned) ("the planted 300-minute tool call is found (" + $ws.longestToolCall.value.seconds + " s)")
    Check ($ws.longestGap.value.seconds -eq 18000 -and $ws.longestGap.value.startedAt -eq (ConvertTo-HordeUtcTime "2026-09-30T10:24:00Z")) "the longest silence is those 300 minutes, from 10:24 UTC"
    Check ($ws.wallClockSeconds.value -eq 19740) "wall-clock from the first timestamped line to the last (329 minutes)"
    Check ($ws.model.value -eq "claude-opus-5-5") "the model is read from the calls"
    $om = Get-HordeOrcMeasures -Records $recs
    Check ($om.stillWaiting.calls -eq 3) ("the three planted still-waiting replies are found (" + $om.stillWaiting.calls + ")")
    Check ($om.stillWaiting.byWorker["a1b2c3d4e5f6a7b8c"] -eq 1 -and $om.stillWaiting.jobs -eq 1 -and $om.stillWaiting.unattributed -eq 1) "one answers the worker, one the job, one an unresolved notification"
    Check ($om.stillWaiting.contextTokens -eq 275306) ("with the context they processed, 90303 + 91002 + 94001 = 275306 (" + $om.stillWaiting.contextTokens + ")")
    $workerNote = $byCall["toolu_L1"].chars + $byCall["toolu_OLD"].chars
    Check ($om.landed.byWorker["a1b2c3d4e5f6a7b8c"].chars -eq ($workerNote + $launch.chars) -and $om.landed.byWorker["a1b2c3d4e5f6a7b8c"].notifications -eq 2) "the worker's two notifications and its launch result land on it"
    Check ($om.landed.unattributedChars -eq $byCall["toolu_ZZ"].chars -and $om.landed.jobCount -eq 1) "the unresolved notification is unattributed and the job's is a job"
    $cread = Read-HordeTranscript -Path $cleanPath
    $cm = Get-HordeOrcMeasures -Records $cread.value.records
    Check ($cm.stillWaiting.calls -eq 0) "the clean transcript has no still-waiting reply"
    Check ($cm.notifications -eq 1) "CONTROL: and it does have a notification, answered with a tool call"
    $cws = Get-HordeWorkerSummary -Records $cread.value.records -PriceTable $noTable
    Check ($cws.longestToolCall.value.seconds -lt 3600) ("and no long tool call (" + $cws.longestToolCall.value.seconds + " s)")

    Write-Host ""
    Write-Host "--- cost from a price table ---" -ForegroundColor Cyan
    $tbl = ConvertFrom-HordePriceTableText -Text '{ "schemaVersion": 1, "version": "test-observed", "perTokens": 1000000, "models": { "claude-opus-5-5": { "provider": "anthropic", "rates": { "input": 4, "cacheWrite5m": 5, "cacheWrite1h": 8, "cacheRead": 0.2, "output": 20 }, "geo": { "us": 1.1 }, "geoStandard": ["not_available", ""] } } }'
    $wc = Get-HordeWorkerSummary -Records $recs -PriceTable $tbl
    Check ($wc.cost.cost.state -eq "known" -and $wc.cost.cost.value -eq [decimal]0.105192) ("28x4 + 466000x0.2 + 500x5 + 100x8 + 429x20 per million = 0.105192 (" + $wc.cost.cost.value + ")")
    $wsub = Get-HordeWorkerSummary -Records $sub.value.records -PriceTable $tbl
    Check ($wsub.cost.cost.state -eq "unknown" -and $wsub.cost.cost.reason -like "*claude-opus-5'*") "a model the table does not list leaves the cost unknown, naming it"

    Write-Host ""
    Write-Host "--- no text leaves the transcript ---" -ForegroundColor Cyan
    $all = @()
    foreach ($p in @($plantedPath, $subPath, $cleanPath)) {
        $r = (Read-HordeTranscript -Path $p).value
        $rec = New-HordeTranscriptSummaryRecord -Read $r -Worker (Get-HordeWorkerSummary -Records $r.records -PriceTable $tbl) -Orc (Get-HordeOrcMeasures -Records $r.records)
        $all += (ConvertTo-Json -InputObject $rec -Depth 30)
        $all += (ConvertTo-Json -InputObject (ConvertTo-HordeJsonSafe $r.records) -Depth 30)
    }
    $joined = $all -join "`n"
    Check ($joined.IndexOf($secret) -lt 0) "the planted secret is in no record and no summary"
    $places = ([regex]::Matches((Get-Content -LiteralPath $plantedPath -Raw), [regex]::Escape($secret))).Count
    Check ($places -ge 6) ("CONTROL: the secret really is in the fixture (" + $places + " places)")
    $leaky = Join-Path $work "leaky\11111111-2222-4333-8444-555555555555.jsonl"
    New-Item -ItemType Directory -Path (Split-Path -Parent $leaky) | Out-Null
    [System.IO.File]::WriteAllText($leaky, (Get-Content -LiteralPath $plantedPath -Raw).Replace('"model":"claude-opus-5-5","id":"msg_A4"', '"model":"claude-' + $secret + '","id":"msg_A4"'))
    $lr = (Read-HordeTranscript -Path $leaky).value
    $leakJson = ConvertTo-Json -InputObject (New-HordeTranscriptSummaryRecord -Read $lr -Worker (Get-HordeWorkerSummary -Records $lr.records -PriceTable $tbl) -Orc (Get-HordeOrcMeasures -Records $lr.records)) -Depth 30
    Check ($leakJson.IndexOf($secret) -ge 0) "CONTROL: planted in a field the adapter does read (a model id), the same search finds it"

} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "the adapter's records are right, every planted measure is found, nothing is found in the clean transcript, and no text leaves it"
