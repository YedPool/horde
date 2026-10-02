# DOES THE CODEX ADAPTER TURN A REAL-SHAPED ROLLOUT INTO THE RIGHT RECORDS, AND DO THE MEASURES FIND
# WHAT WAS PLANTED IN IT - THROUGH THE REAL `horde` COMMAND TOO?
#
# Fixtures, under fixtures/metrics/: line shapes copied from the rollouts measured on 2026-09-30 (CLI
# 0.159.2 and 0.159.3), every value invented. "planted" (0.159.3) holds two turns - one completed,
# one interrupted - three responses, a 300-minute tool call, a compaction followed by the re-emitted
# user message, and the string PLANTED-SECRET-7f3a in the instructions, a prompt, reasoning, a tool's
# arguments and output, and the reply. "old" (0.159.2) has no token_usage_record, and repeats one
# token_count. "clean" is one short turn with one short tool call.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "ReadShared", "Home", "Transcript", "Price", "Metrics", "MetricsStore")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "agents\codex\Transcript.ps1")
. (Join-Path $root "test\lib\Cli.ps1")

$fixtures = Join-Path $here "fixtures\metrics"
$plantedPath = Join-Path $fixtures "planted\rollout-2026-09-30T06-00-00-01a0aaaa-1111-7222-8333-444455556666.jsonl"
$oldPath = Join-Path $fixtures "old\rollout-2026-09-29T18-00-00-01a0bbbb-1111-7222-8333-444455556666.jsonl"
$cleanPath = Join-Path $fixtures "clean\rollout-2026-09-30T08-00-00-01a0cccc-1111-7222-8333-444455556666.jsonl"
$secret = "PLANTED-SECRET-7f3a"
$noTable = New-HordeAbsent -Note "no table"
$work = Join-Path $env:TEMP ("horde-codex-transcript-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null

try {
    Write-Host ""
    Write-Host "--- claiming files ---" -ForegroundColor Cyan
    Check ((Test-CodexTranscript -Path $plantedPath) -eq $true) "CONTROL: the adapter claims a rollout"
    $other = Join-Path $work "other.jsonl"
    [System.IO.File]::WriteAllText($other, '{"type":"user","sessionId":"s","timestamp":"2026-09-30T10:00:00.000Z","message":{"role":"user","content":"x"}}' + "`n")
    Check ((Test-CodexTranscript -Path $other) -eq $false) "a file of { sessionId, type, message } lines is not claimed"
    $notFirst = Join-Path $work "notfirst.jsonl"
    [System.IO.File]::WriteAllText($notFirst, '{"timestamp":"2026-09-30T10:00:00.000Z","ordinal":0,"type":"event_msg","payload":{"type":"task_started"}}' + "`n")
    Check ((Test-CodexTranscript -Path $notFirst) -eq $false) "a file whose first line is not a session_meta is not claimed"

    Write-Host ""
    Write-Host "--- records ---" -ForegroundColor Cyan
    $read = Read-HordeTranscript -Path $plantedPath
    Check ($read.state -eq "known" -and $read.value.adapter -eq "codex" -and $read.value.sessionId -eq "01a0aaaa-1111-7222-8333-444455556666") "the planted rollout is read through this adapter, keeping the port's contract, with its session id"
    $recs = @($read.value.records)
    $calls = @($recs | Where-Object { $_.kind -eq "call" })
    Check ($calls.Count -eq 3) ("one call per token_usage_record, the interrupted turn's response included: 3 (" + $calls.Count + ")")
    Check (@($calls | Where-Object { $_.model.state -eq "known" -and $_.model.value -eq "gpt-5.5" }).Count -eq 3) "each call takes its turn's model from turn_context"
    $c1 = $calls[0]
    Check ($c1.usage.value.input -eq 14000 -and $c1.usage.value.cacheRead -eq 5000) "input here includes cached input, so the uncached part is input minus cached (19000 - 5000)"
    Check ($c1.usage.value.cacheWriteSplit.state -eq "absent") "the cache write has no lifetime split on this harness, and says so as absent, not unknown"
    Check ($c1.toolCallCount -eq 1 -and $calls[1].toolCallCount -eq 0 -and $calls[2].toolCallCount -eq 1) "a tool call belongs to the next response of its turn"
    Check ($calls[1].textChars -eq 28) ("the reply's text is measured and given to its response (" + $calls[1].textChars + ")")
    Check (@($recs | Where-Object { $_.kind -eq "toolCall" }).Count -eq 2 -and @($recs | Where-Object { $_.kind -eq "toolResult" }).Count -eq 2) "two tool calls, paired with their outputs by call_id"
    $res = @($recs | Where-Object { $_.kind -eq "toolResult" })[0]
    Check ($res.isError.state -eq "unknown" -and $res.worker.state -eq "absent") "an output line does not say whether its tool failed: unknown, not false"
    $ends = @($recs | Where-Object { $_.kind -eq "turnEnd" })
    Check ($ends.Count -eq 2 -and $ends[0].durationMs.value -eq 18100000 -and $ends[1].durationMs.value -eq 60000) "task_complete and turn_aborted both end a turn, with their durations"
    Check (@($recs | Where-Object { $_.kind -eq "input" }).Count -eq 2) "user input is the UserMessage items, not the user messages re-emitted after compaction"
    Check (@($recs | Where-Object { $_.kind -eq "compaction" }).Count -eq 1) "the compaction is recorded"


    Write-Host ""
    Write-Host "--- a usage field the line does not give is unknown, not zero ---" -ForegroundColor Cyan
    # Review of PR #50, F5.
    $pu = Join-Path $work "partial-usage.jsonl"
    $plines = @(
        '{"timestamp":"2026-09-30T10:00:00.000Z","ordinal":0,"type":"session_meta","payload":{"id":"s1"}}',
        '{"timestamp":"2026-09-30T10:00:01.000Z","ordinal":1,"type":"turn_context","payload":{"turn_id":"t1","model":"gpt-5.5"}}',
        '{"timestamp":"2026-09-30T10:00:02.000Z","ordinal":2,"type":"token_usage_record","payload":{"turn_id":"t1","response_id":"r1","usage":{"input_tokens":100,"cached_input_tokens":10,"cache_write_input_tokens":0}}}'
    )
    [System.IO.File]::WriteAllText($pu, ($plines -join "`n") + "`n")
    $puc = @((Read-HordeTranscript -Path $pu).value.records | Where-Object { $_.kind -eq "call" })[0]
    Check ($puc.usage.state -eq "unknown" -and $puc.usage.reason -like "*output_tokens*") "a usage object with no output_tokens is unknown, naming the missing field"
    Check ($calls[0].usage.state -eq "known") "CONTROL: a complete usage object is known"

    Write-Host ""
    Write-Host "--- totals and their control ---" -ForegroundColor Cyan
    $ws = Get-HordeWorkerSummary -Records $recs -PriceTable $noTable
    Check ($ws.tokens.value.input -eq 16600 -and $ws.tokens.value.cacheRead -eq 41500 -and $ws.tokens.value.output -eq 100) "per-call tokens sum to uncached 16600, cached 41500, output 100"
    $rt = $ws.tokensReportedTotal.value
    Check ($rt.input -eq $ws.tokens.value.input -and $rt.cacheRead -eq $ws.tokens.value.cacheRead -and $rt.output -eq $ws.tokens.value.output) "and agree with the harness's own cumulative total, the normaliser's control (experiment program 12.2)"
    $old = Read-HordeTranscript -Path $oldPath
    $oc = @($old.value.records | Where-Object { $_.kind -eq "call" })
    Check ($oc.Count -eq 2) ("a 0.159.2 rollout, with no token_usage_record, gets one call per change in its cumulative total; the repeat is not a call (" + $oc.Count + ")")
    $ows = Get-HordeWorkerSummary -Records $old.value.records -PriceTable $noTable
    Check ($ows.tokens.value.input -eq 1300 -and $ows.tokens.value.output -eq 30 -and $ows.tokensReportedTotal.value.output -eq 30) "and its calls still sum to its cumulative total"

    Write-Host ""
    Write-Host "--- the planted measures are found ---" -ForegroundColor Cyan
    Check ($ws.longestToolCall.value.seconds -eq 18000 -and $ws.longestToolCall.value.name -eq "exec_command") ("the planted 300-minute tool call is found (" + $ws.longestToolCall.value.seconds + " s)")
    Check ($ws.longestGap.value.seconds -eq 17988) ("the longest silence is the 299.8 minutes no line was written while it ran, from the last token count to the output (" + $ws.longestGap.value.seconds + " s)")
    Check ($ws.model.value -eq "gpt-5.5" -and $ws.calls.value -eq 3 -and $ws.toolCalls.value -eq 2) "model, calls and tool calls"
    Check ($ws.turns.value -eq 2) "two turns"
    $cw = Get-HordeWorkerSummary -Records (Read-HordeTranscript -Path $cleanPath).value.records -PriceTable $noTable
    Check ($cw.longestToolCall.value.seconds -eq 30) "CONTROL: the clean rollout's longest tool call is its real 30 seconds"
    Check ((Get-HordeOrcMeasures -Records $recs).stillWaiting.calls -eq 0) "a rollout has no notifications, so no still-waiting calls"

    Write-Host ""
    Write-Host "--- cost ---" -ForegroundColor Cyan
    $tbl = ConvertFrom-HordePriceTableText -Text '{ "schemaVersion": 1, "version": "test-observed", "perTokens": 1000000, "models": { "gpt-5.5": { "provider": "openai", "rates": { "input": 5, "cacheRead": 0.5, "output": 30 } } } }'
    $wc = Get-HordeWorkerSummary -Records $recs -PriceTable $tbl
    Check ($wc.cost.cost.state -eq "known" -and $wc.cost.cost.value -eq [decimal]0.10675) ("16600x5 + 41500x0.5 + 100x30 per million = 0.10675 (" + $wc.cost.cost.value + ")")
    $repoBook = Read-HordePriceBook -OverridePath (Join-Path $work "no-override.json")
    $wr = Get-HordeWorkerSummary -Records $recs -PriceTable $repoBook
    Check ($repoBook.state -eq "known" -and $wr.cost.cost.value -eq [decimal]0.10675 -and @($wr.cost.priceTables) -contains "agents/codex/prices.json 2026-09-30.1") "the repository's own table, agents/codex/prices.json, loads, prices this harness's model, and is named as the source"

    Write-Host ""
    Write-Host "--- no text leaves the rollout ---" -ForegroundColor Cyan
    $all = @()
    foreach ($p in @($plantedPath, $oldPath, $cleanPath)) {
        $r = (Read-HordeTranscript -Path $p).value
        $all += (ConvertTo-Json -InputObject (New-HordeTranscriptSummaryRecord -Read $r -Worker (Get-HordeWorkerSummary -Records $r.records -PriceTable $tbl) -Orc (Get-HordeOrcMeasures -Records $r.records)) -Depth 30)
        $all += (ConvertTo-Json -InputObject (ConvertTo-HordeJsonSafe $r.records) -Depth 30)
    }
    Check (($all -join "`n").IndexOf($secret) -lt 0) "the planted secret is in no record and no summary"
    $places = ([regex]::Matches((Get-Content -LiteralPath $plantedPath -Raw), [regex]::Escape($secret))).Count
    Check ($places -ge 6) ("CONTROL: the secret really is in the fixture (" + $places + " places)")
    $leaky = Join-Path $work "leaky.jsonl"
    [System.IO.File]::WriteAllText($leaky, (Get-Content -LiteralPath $plantedPath -Raw).Replace('"model":"gpt-5.5","effort":"low","approval_policy":"never"}', '"model":"gpt-' + $secret + '","effort":"low","approval_policy":"never"}'))
    $lr = (Read-HordeTranscript -Path $leaky).value
    $leakJson = ConvertTo-Json -InputObject (New-HordeTranscriptSummaryRecord -Read $lr -Worker (Get-HordeWorkerSummary -Records $lr.records -PriceTable $tbl) -Orc (Get-HordeOrcMeasures -Records $lr.records)) -Depth 30
    Check ($leakJson.IndexOf($secret) -ge 0) "CONTROL: planted in a field the adapter does read (the turn's model), the same search finds it"

    Write-Host ""
    Write-Host "--- end to end: the real horde command ---" -ForegroundColor Cyan
    $hashes = @{}; foreach ($p in @(Get-ChildItem -LiteralPath $fixtures -File -Recurse)) { $hashes[$p.FullName] = (Get-FileHash -LiteralPath $p.FullName -Algorithm SHA256).Hash }
    $homeDir = Join-Path $work "home"
    $envs = @{ HORDE_HOME = $homeDir; CODEX_HOME = (Join-Path $work "harness-store") }
    New-Item -ItemType Directory -Path (Join-Path $homeDir "metrics") -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $homeDir "metrics\prices.json"), '{ "schemaVersion": 1, "version": "test-observed", "perTokens": 1000000, "models": { "gpt-5.5": { "provider": "openai", "rates": { "input": 50, "cacheRead": 0.5, "output": 30 } } } }')
    [System.IO.File]::WriteAllText((Join-Path $homeDir "metrics\gate.json"), '{ "schemaVersion": 1, "level": "usage", "enabledAt": "2026-09-30T00:00:00Z" }')
    $run = Invoke-HordeCliProcess -Root $root -HordeArgs @("metrics", "summarize", $fixtures) -Env $envs
    Check ($run.code -eq 0) ("horde metrics summarize exits 0 on the rollouts (" + $run.code + ")")
    Check ($run.out -match 'rollout-2026-09-30T06-00-00-01a0aaaa-1111-7222-8333-444455556666\.jsonl\s+codex\s+gpt-5\.5\s+\S+\s+3\s+2\s+16,600\s+41,500\s+0\s+100\s+299\.8m \(2026-09-30 10:01\)\s+300\.0m exec_command\s+0\.85') "its row shows the counts, the 300-minute tool call, and the cost at the override's rate (input 50, not the repository's 5)"
    Check ($run.out -like "*the HORDE_HOME override test-observed*" -and $run.out -like "*recorded 3 summaries*") "it names the override among its tables, and with the gate on records the three rollouts"
    $files = @(Get-ChildItem -LiteralPath (Join-Path $homeDir "metrics\summaries\codex") -File -ErrorAction SilentlyContinue)
    $text = (@($files | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n")
    Check ($files.Count -eq 3 -and $text.IndexOf($secret) -lt 0) "the three records written hold no planted secret"
    Check ($text -like "*the HORDE_HOME override test-observed*") "and each record names the override as the table that priced it"
    $changed = @($hashes.Keys | Where-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash -ne $hashes[$_] })
    Check ($changed.Count -eq 0 -and $hashes.Count -eq 3) ("every rollout read is byte for byte as it was (" + $hashes.Count + " files checked)")
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "the adapter's records are right, its totals match the harness's own, every planted measure is found, and no text leaves the rollout"
