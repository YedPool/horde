# DOES EACH METRIC FIND WHAT IS THERE, AND NOTHING THAT IS NOT?
#
# core/Metrics.ps1, on port records built here with neutral names. Every instrument gets a positive
# control - a transcript with a known count, including a planted "still waiting" call and a planted
# 300-minute tool call - and a clean transcript that must find none (CONTRIBUTING 7: a search that
# finds nothing proves nothing until it finds something known to be there). The adapters' own suites,
# in agents/<name>/test/, run the same controls through real transcript formats.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\Tristate.ps1")
. (Join-Path $root "core\ReadShared.ps1")
. (Join-Path $root "core\Home.ps1")
. (Join-Path $root "core\Transcript.ps1")
. (Join-Path $root "core\Price.ps1")
. (Join-Path $root "core\Metrics.ps1")

$t0 = ConvertTo-HordeUtcTime "2026-09-30T10:00:00Z"
$script:line = 0
function At { param([double]$Minutes) return $t0.AddMinutes($Minutes) }
function Next { $script:line++; return $script:line }
function Call {
    param([string]$Id, [double]$Min, [int]$Tools = 0, [int]$Chars = 20, [long]$In = 10, [long]$Read = 1000, [long]$Write = 100, [long]$Out = 50, [string]$Model = "model-a", [switch]$NoUsage)
    $usage = New-HordeUsage -Uncached $In -CacheRead $Read -CacheWrite $Write -Output $Out -Split (New-HordeKnown -Value ([pscustomobject]@{ m5 = $Write; h1 = [long]0 }))
    if ($NoUsage) { $usage = New-HordeUnknown -Reason "the line carries no usage" }
    New-HordeTranscriptRecord -Kind "call" -Role "assistant" -Ts (At $Min) -Line (Next) -Fields @{ id = $Id; model = (New-HordeKnown -Value $Model); usage = $usage; textChars = $Chars; toolCallCount = $Tools; speed = ""; inferenceGeo = "" }
}
function Tool { param([string]$Id, [double]$Min, [string]$Name = "tool-x") New-HordeTranscriptRecord -Kind "toolCall" -Role "assistant" -Ts (At $Min) -Line (Next) -Fields @{ id = $Id; name = $Name; callId = ""; launchesWorker = $false } }
function Result { param([string]$Id, [double]$Min, [int]$Chars = 100, $Worker = (New-HordeAbsent -Note "not a worker launch")) New-HordeTranscriptRecord -Kind "toolResult" -Role "tool" -Ts (At $Min) -Line (Next) -Fields @{ toolCallId = $Id; isError = (New-HordeKnown -Value $false); chars = $Chars; worker = $Worker } }
function Note {
    param([double]$Min, $Worker, [int]$Chars = 500, [switch]$Interim, [string]$NoteKind = "")
    New-HordeTranscriptRecord -Kind "input" -Role "user" -Ts (At $Min) -Line (Next) -Fields @{ source = "notification"; chars = $Chars; taskId = "t"; toolCallId = "u"; interim = [bool]$Interim; noteKind = $(if ($NoteKind -ne "") { $NoteKind } elseif ($Interim) { "interim" } else { "final" }); worker = $Worker }
}
function UserSays { param([double]$Min, [int]$Chars = 40) New-HordeTranscriptRecord -Kind "input" -Role "user" -Ts (At $Min) -Line (Next) -Fields @{ source = "user"; chars = $Chars; taskId = ""; toolCallId = ""; interim = $false; worker = (New-HordeAbsent -Note "a user message") } }
function TurnEnd { param([double]$Min) New-HordeTranscriptRecord -Kind "turnEnd" -Role "system" -Ts (At $Min) -Line (Next) -Fields @{ durationMs = (New-HordeKnown -Value 1000) } }
function Worker { param([string]$Id) New-HordeKnown -Value $Id }
$job = New-HordeAbsent -Note "a background shell job"
$unproved = New-HordeUnknown -Reason "the notification names nothing this transcript resolves"
$noTable = New-HordeAbsent -Note "no price table"

Write-Host ""
Write-Host "--- still waiting: the planted call is found ---" -ForegroundColor Cyan
$script:line = 0
$planted = @(
    (UserSays 0), (Call "c1" 1 -Tools 1), (Tool "k1" 1), (Result "k1" 2), (Call "c2" 3 -Chars 900), (TurnEnd 3),
    (Note 10 (Worker "w1") -Interim), (Call "c3" 11 -Chars 25 -In 5 -Read 90000 -Write 300 -Out 12), (TurnEnd 11)
)
$m = Get-HordeOrcMeasures -Records $planted
Check ($m.stillWaiting.calls -eq 1) "the planted still-waiting call is found"
Check ($m.stillWaiting.contextTokens.value -eq 90305) "with the context it processed: input + cache read + cache write = 90305"
Check ($m.stillWaiting.outputTokens.value -eq 12) "and the output it wrote"
$script:line = 0
$noUse = Get-HordeOrcMeasures -Records @((Note 0 (Worker "w1") -Interim), (Call "nu1" 1 -Chars 10), (Note 2 (Worker "w1") -Interim), (Call "nu2" 3 -Chars 10 -NoUsage))
Check ($noUse.stillWaiting.contextTokens.state -eq "unknown" -and $noUse.stillWaiting.contextTokens.reason -like "*1 of 2*") "a still-waiting total missing a call's usage is unknown, saying how many calls it lacks, not a smaller number"
Check ($noUse.stillWaiting.outputTokens.state -eq "unknown") "and so is the output total"
Check ($m.stillWaiting.byWorker["w1"] -eq 1 -and $m.stillWaiting.unattributed -eq 0) "it is attributed to the worker its notification proves"
Check (@($m.stillWaiting.lines) -contains 8) "and the line it is on is reported, so a person can look"

Write-Host ""
Write-Host "--- still waiting: a clean transcript finds none ---" -ForegroundColor Cyan
$script:line = 0
$clean = @(
    (Note 0 (Worker "w1") -Interim), (Call "d1" 1 -Tools 1), (Tool "k1" 1), (Result "k1" 2), (Call "d2" 2 -Chars 30),
    (Note 5 (Worker "w2") -Interim), (Call "d3" 6 -Chars 400),
    (UserSays 7), (Call "d4" 8 -Chars 10),
    (Note 9 (Worker "w3") -Interim), (Tool "k2" 9), (Result "k2" 9.5), (Call "d5" 10 -Chars 10),
    (Note 11 (Worker "w4") -Interim), (Call "d6" 12 -Tools 1), (Call "d7" 13 -Chars 10)
)
$mc = Get-HordeOrcMeasures -Records $clean
Check ($mc.stillWaiting.calls -eq 0) "none in a transcript with none"
$script:line = 0
$viaTool = Get-HordeOrcMeasures -Records @((Note 0 (Worker "w1") -Interim), (Tool "k" 0.5), (Result "k" 1), (Call "v1" 2 -Chars 10))
$direct = Get-HordeOrcMeasures -Records @((Note 0 (Worker "w1") -Interim), (Call "v2" 2 -Chars 10))
Check ($viaTool.stillWaiting.calls -eq 0 -and $direct.stillWaiting.calls -eq 1) "a tool result between the notification and the reply means the reply answers the tool, not the notification"
Check ($mc.notifications -eq 4) "CONTROL: the clean transcript does contain notifications, so the zero is not for want of any"
# Two rules decided by the coordinator on 2026-10-02, to be calibrated by experiment program 3.4's
# hand-labelling: a person speaking since the last call takes the reply, and only an INTERIM
# notification can be waited on.
$script:line = 0
$humanBetween = Get-HordeOrcMeasures -Records @((UserSays 0), (Note 1 (Worker "w1") -Interim), (Call "h1" 2 -Chars 10))
$noHuman = Get-HordeOrcMeasures -Records @((Note 1 (Worker "w1") -Interim), (Call "h2" 2 -Chars 10))
Check ($humanBetween.stillWaiting.calls -eq 0) "a reply after a person spoke since the last call answers the person, not the notification"
Check ($noHuman.stillWaiting.calls -eq 1) "CONTROL: the same reply with no person speaking is still-waiting"
$script:line = 0
$final = Get-HordeOrcMeasures -Records @((Note 1 (Worker "w1")), (Call "f1" 2 -Chars 10))
$interimOne = Get-HordeOrcMeasures -Records @((Note 1 (Worker "w1") -Interim), (Call "f2" 2 -Chars 10))
Check ($final.stillWaiting.calls -eq 0) "a short reply to a final notification is a report, never still-waiting"
Check ($interimOne.stillWaiting.calls -eq 1) "CONTROL: a short reply to an interim notification is still-waiting"
$script:line = 0
$unknownNote = Get-HordeOrcMeasures -Records @((Note 1 (Worker "w1") -NoteKind "unrecognised"), (Call "u1" 2 -Chars 10))
Check ($unknownNote.unrecognisedNotes -eq 1 -and $unknownNote.stillWaiting.calls -eq 0 -and $unknownNote.stillWaiting.afterUnrecognisedNote -eq 1) "a note in unknown wording is counted, and a short reply to it is counted apart, not read as answering a final notification"
Check ($interimOne.unrecognisedNotes -eq 0 -and $interimOne.stillWaiting.afterUnrecognisedNote -eq 0) "CONTROL: a recognised interim note is not counted as unrecognised"

Write-Host ""
Write-Host "--- still waiting: attribution is never guessed ---" -ForegroundColor Cyan
$script:line = 0
$mixed = @(
    (Note 0 $job -Interim), (Call "e1" 1), (Note 2 $unproved -Interim), (Call "e2" 3), (Note 4 (Worker "w9") -Interim), (Call "e3" 5), (Call "e3" 5)
)
$mm = Get-HordeOrcMeasures -Records $mixed
Check ($mm.stillWaiting.calls -eq 3) "three still-waiting calls; the repeated id is counted once"
Check ($mm.stillWaiting.jobs -eq 1 -and $mm.stillWaiting.unattributed -eq 1 -and $mm.stillWaiting.byWorker["w9"] -eq 1) "one about a job, one unattributed, one on the proved worker"
Check ($mm.interimNotifications -eq 3 -and $final.interimNotifications -eq 0) "interim notifications are counted as interim, and a final one is not"
$m200 = Get-HordeOrcMeasures -Records $planted -MaxChars 20
Check ($m200.stillWaiting.calls -eq 0) "the character limit is a parameter: at 20 characters the 25-character call is not counted"

Write-Host ""
Write-Host "--- worker results landing in the orchestrator ---" -ForegroundColor Cyan
$script:line = 0
$land = @(
    (Note 0 (Worker "w1") -Chars 2380), (Note 1 (Worker "w1") -Chars 238), (Note 2 $job -Chars 300), (Note 3 $unproved -Chars 476),
    (Tool "L1" 4 -Name "launch"), (Result "L1" 5 -Chars 1000 -Worker (Worker "w2")),
    (Tool "L2" 6 -Name "launch"), (Result "L2" 7 -Chars 50 -Worker (New-HordeUnknown -Reason "no record of which worker")),
    (Tool "k9" 8), (Result "k9" 9 -Chars 99999)
)
$ml = Get-HordeOrcMeasures -Records $land
Check ($ml.landed.byWorker["w1"].chars -eq 2618 -and $ml.landed.byWorker["w1"].notifications -eq 2) "a worker's notifications land on that worker (2380 + 238 characters)"
Check ($ml.landed.byWorker["w2"].chars -eq 1000 -and $ml.landed.byWorker["w2"].toolResults -eq 1) "a launch tool's result lands on the worker it proves"
Check ($ml.landed.jobChars -eq 300 -and $ml.landed.jobCount -eq 1) "a notification about a background job is a job, not a worker result"
Check ($ml.landed.unattributedChars -eq 526 -and $ml.landed.unattributedCount -eq 2) "what cannot be proved is counted unattributed (476 + 50), never given to a worker"
Check ($ml.landed.workerChars -eq 3618) "an ordinary tool's result is not a worker result (the 99999 characters are not counted)"
Check ($ml.landed.workerTokensEstimated -eq 1520 -and $ml.landed.tag -eq "ESTIMATE" -and $ml.landed.confidence -eq "estimated") "tokens are estimated at 2.38 characters each (3618 / 2.38 = 1520) and labelled ESTIMATE"

Write-Host ""
Write-Host "--- the worker summary: the planted 300-minute tool call ---" -ForegroundColor Cyan
$script:line = 0
$long = @(
    (UserSays 0), (Call "f1" 1 -Tools 1), (Tool "slow" 1 -Name "tool-slow"), (Result "slow" 301),
    (Call "f2" 302 -Tools 2), (Tool "q1" 302), (Result "q1" 302.5), (Tool "q2" 302), (Result "q2" 303), (Call "f3" 304), (TurnEnd 304)
)
$ws = Get-HordeWorkerSummary -Records $long -PriceTable $noTable
Check ($ws.longestToolCall.state -eq "known" -and $ws.longestToolCall.value.seconds -eq 18000) ("the planted 300-minute tool call is the longest (" + $ws.longestToolCall.value.seconds + " s)")
Check ($ws.longestToolCall.value.name -eq "tool-slow" -and $ws.longestToolCall.value.startedAt -eq (At 1) -and $ws.longestToolCall.value.returned) "with its name, its start, and that it returned"
Check ($ws.longestGap.value.seconds -eq 18000 -and $ws.longestGap.value.startedAt -eq (At 1)) "the longest silence is the same 300 minutes, starting when the call went out"
Check ($ws.wallClockSeconds.value -eq (304 * 60)) "wall-clock runs from the first event to the last (304 minutes)"
Check ($ws.toolCalls.value -eq 3 -and $ws.calls.value -eq 3) "three tool calls and three model calls"
Check ($ws.turns.value -eq 1) "one turn end"
$script:line = 0
$short = @((UserSays 0), (Call "g1" 1 -Tools 1), (Tool "q" 1), (Result "q" 1.5), (Call "g2" 2), (TurnEnd 2))
$wshort = Get-HordeWorkerSummary -Records $short -PriceTable $noTable
Check ($wshort.longestToolCall.value.seconds -eq 30) "CONTROL: a transcript with no long call reports its real longest, 30 seconds"
$script:line = 0
$frozen = @((UserSays 0), (Call "h1" 1 -Tools 1), (Tool "stuck" 2 -Name "tool-stuck"), (UserSays 62))
$wf = Get-HordeWorkerSummary -Records $frozen -PriceTable $noTable
Check ($wf.longestToolCall.value.returned -eq $false -and $wf.longestToolCall.value.seconds -eq 3600) "a tool call with no result is counted to the last event (60 minutes) and flagged as not returned"
Check ($wf.toolCallsWithoutResult -eq 1) "and counted as a call without a result"
$script:line = 0
$back = Get-HordeWorkerSummary -Records @((UserSays 0), (Call "b1" 10 -Tools 1), (Tool "tb" 10 -Name "tool-back"), (Result "tb" 4), (Call "b2" 11 -Tools 1), (Tool "tc" 11), (Result "tc" 11.5)) -PriceTable $noTable
Check ($back.longestToolCall.value.seconds -eq 30 -and $back.toolCallsWithNegativeDuration -eq 1) "a tool call whose result is timed before it (the clock went back) is never the longest; it is counted apart"

Write-Host ""
Write-Host "--- the worker summary: tokens, model and cost ---" -ForegroundColor Cyan
$script:line = 0
$tok = @(
    (Call "a" 0 -In 1 -Read 10 -Write 100 -Out 1000 -Model "model-a"), (Call "a" 0 -In 1 -Read 10 -Write 100 -Out 1000 -Model "model-a"),
    (Call "b" 1 -In 2 -Read 20 -Write 200 -Out 2000 -Model "model-a"), (Call "c" 2 -In 4 -Read 40 -Write 400 -Out 4000 -Model "model-b")
)
$wt = Get-HordeWorkerSummary -Records $tok -PriceTable $noTable
Check ($wt.tokens.state -eq "known" -and $wt.tokens.value.output -eq 7000) ("a call repeated under one id is counted once (output 1000 + 2000 + 4000 = " + $wt.tokens.value.output + ")")
Check ($wt.tokens.value.input -eq 7 -and $wt.tokens.value.cacheRead -eq 70 -and $wt.tokens.value.cacheWrite -eq 700 -and $wt.tokens.value.cacheWrite5m -eq 700) "every token kind is summed the same way"
Check ($wt.duplicateCallRecords -eq 1) "and the repeat is counted, not hidden"
Check ($wt.model.value -eq "model-a" -and $wt.models["model-b"] -eq 1) "the model is the one most calls used, and every model is listed with its calls"
Check ($wt.cost.cost.state -eq "unknown" -and $wt.cost.confidence -eq "unknown") "with no price table the cost is unknown, not zero"
$tbl = ConvertFrom-HordePriceTableText -Text '{ "schemaVersion": 1, "version": "t.2", "perTokens": 1000000, "models": { "model-a": { "rates": { "input": 1, "cacheRead": 1, "cacheWrite5m": 1, "cacheWrite1h": 1, "output": 1 } }, "model-b": { "rates": { "input": 2, "cacheRead": 2, "cacheWrite5m": 2, "cacheWrite1h": 2, "output": 2 } } } }'
$wp = Get-HordeWorkerSummary -Records $tok -PriceTable $tbl
Check ($wp.cost.cost.state -eq "known" -and $wp.cost.cost.value -eq [decimal]0.012221) ("priced per call and summed once per id: 1111 + 2222 at rate 1 and 4444 at rate 2, per million = 0.012221 (" + $wp.cost.cost.value + ")")
Check ($wp.cost.tag -eq "ESTIMATE" -and $wp.cost.unit -eq "notionalUsd" -and @($wp.cost.priceTables) -contains "a given table t.2" -and $wp.cost.confidence -eq "derived") "a cost is derived, tagged ESTIMATE, labelled notional, and names the table and version that priced it"
$tblA = ConvertFrom-HordePriceTableText -Text '{ "schemaVersion": 1, "version": "t.3", "perTokens": 1000000, "models": { "model-a": { "rates": { "input": 1, "cacheRead": 1, "cacheWrite5m": 1, "cacheWrite1h": 1, "output": 1 } } } }'
$wpa = Get-HordeWorkerSummary -Records $tok -PriceTable $tblA
Check ($wpa.cost.cost.state -eq "unknown" -and $wpa.cost.cost.reason -like "*1 of 3 calls*model-b*") "one unpriced call makes the total unknown, naming how many and why"
$script:line = 0
$partial = @((Call "p1" 0), (Call "p2" 1 -NoUsage))
$wpart = Get-HordeWorkerSummary -Records $partial -PriceTable $noTable
Check ($wpart.tokens.state -eq "unknown" -and $wpart.tokens.reason -like "*1 of 2 calls*") "a call with no usage makes the token total unknown, not smaller"
$script:line = 0
$withTotal = @((Call "r1" 0), (New-HordeTranscriptRecord -Kind "usageTotal" -Role "system" -Ts (At 1) -Line (Next) -Fields @{ usage = (New-HordeUsage -Uncached 1 -CacheRead 2 -CacheWrite 0 -Output 3 -Split (New-HordeAbsent)) }), (New-HordeTranscriptRecord -Kind "usageTotal" -Role "system" -Ts (At 2) -Line (Next) -Fields @{ usage = (New-HordeUsage -Uncached 9 -CacheRead 9 -CacheWrite 0 -Output 9 -Split (New-HordeAbsent)) }))
$wtot = Get-HordeWorkerSummary -Records $withTotal -PriceTable $noTable
Check ($wtot.tokensReportedTotal.value.output -eq 9) "a cumulative total the harness wrote is kept as reported, the last one standing"
Check ((Get-HordeWorkerSummary -Records $tok -PriceTable $noTable).tokensReportedTotal.state -eq "absent") "CONTROL: a transcript with no cumulative total says so"
$empty = Get-HordeWorkerSummary -Records @() -PriceTable $noTable
Check ($empty.wallClockSeconds.state -eq "absent" -and $empty.calls.value -eq 0) "an empty transcript has no wall-clock and no calls, and says so"

Write-Host ""
Write-Host "--- running totals: what streaming must still get right (plan step M2) ---" -ForegroundColor Cyan
# Records now arrive one at a time and are not kept, so every rule that looked across the whole list
# in M1 is checked here where the order of arrival could change its answer.
$script:line = 0
$early = Get-HordeWorkerSummary -Records @((UserSays 0), (Result "pre" 10), (Tool "pre" 2 -Name "tool-pre"), (Call "e1" 11)) -PriceTable $noTable
Check ($early.longestToolCall.value.name -eq "tool-pre" -and $early.longestToolCall.value.seconds -eq 480 -and $early.longestToolCall.value.returned) "a result that comes before its tool call in the file is still its result (8 minutes, returned)"
Check ($early.toolCallsWithoutResult -eq 0) "and that call is not counted as one without a result"
$script:line = 0
$tie = Get-HordeWorkerSummary -Records @((UserSays 0), (Tool "ta" 0 -Name "tool-first"), (Tool "tb" 1 -Name "tool-second"), (Result "tb" 6), (Result "ta" 5)) -PriceTable $noTable
Check ($tie.longestToolCall.value.name -eq "tool-first") "two tool calls of the same length: the earlier in the file is the longest, as M1 reported, though the later one ended first"
$script:line = 0
$unsorted = Get-HordeWorkerSummary -Records @((UserSays 0), (UserSays 100), (UserSays 10), (UserSays 20)) -PriceTable $noTable
Check ($unsorted.longestGap.value.seconds -eq 4800 -and $unsorted.longestGap.value.startedAt -eq (At 20)) "the longest silence is measured in time order, not file order (80 minutes from minute 20)"
$script:line = 0
$sameTime = Get-HordeWorkerSummary -Records @((UserSays 0), (TurnEnd 0), (Call "s1" 50)) -PriceTable $noTable
Check ($sameTime.longestGap.value.afterLine -eq 2 -and $sameTime.longestGap.value.afterKind -eq "turnEnd") "of two records at the time a silence starts, the one after it is the later line"
$script:line = 0
$allOne = Get-HordeWorkerSummary -Records @((UserSays 0), (TurnEnd 0)) -PriceTable $noTable
Check ($allOne.longestGap.value.seconds -eq 0 -and $allOne.longestGap.value.afterLine -eq 1) "when every record has one time, the silence is 0 and starts after the first"

# THE TIED-RECORD ORDER. M1 sorted with Sort-Object, which is not stable on PowerShell 5.1, so the
# kind it reported for records sharing a time and a line is whatever its sort did. The oracle here
# is that same sort, run on the same records; the summary must agree with it.
$script:line = 0
$tiedRecs = New-Object System.Collections.ArrayList
$minute = 0.0
for ($i = 0; $i -lt 40; $i++) {
    $minute += $(if ($i -eq 23) { 90 } else { 1 + ($i % 3) })
    $ln = Next
    [void]$tiedRecs.Add((New-HordeTranscriptRecord -Kind "call" -Role "assistant" -Ts (At $minute) -Line $ln -Fields @{ id = ("tc" + $i); model = (New-HordeKnown -Value "model-a"); usage = (New-HordeUnknown -Reason "x"); textChars = 0; toolCallCount = 1; speed = ""; inferenceGeo = "" }))
    [void]$tiedRecs.Add((New-HordeTranscriptRecord -Kind "toolCall" -Role "assistant" -Ts (At $minute) -Line $ln -Fields @{ id = ("tt" + $i); name = "tool-x"; callId = ("tc" + $i); launchesWorker = $false }))
}
$oracle = @($tiedRecs | Sort-Object -Property @{ Expression = { $_.ts } }, @{ Expression = { $_.line } })
$ob = $null
for ($i = 1; $i -lt $oracle.Count; $i++) { $g = ($oracle[$i].ts - $oracle[$i - 1].ts).TotalSeconds; if ($null -eq $ob -or $g -gt $ob.seconds) { $ob = [pscustomobject]@{ seconds = [decimal]$g; kind = $oracle[$i - 1].kind; line = $oracle[$i - 1].line } } }
$wtie = Get-HordeWorkerSummary -Records $tiedRecs -PriceTable $noTable
Check ($ob.seconds -eq 5400) "CONTROL: the planted 90-minute silence is the longest"
Check ($ob.kind -eq "call") ("CONTROL: on these records M1's unstable sort puts the call after its tool call, the opposite of file order (" + $ob.kind + "), so a summary that kept file order, as a stable sort would, would differ")
Check ($wtie.longestGap.value.afterKind -eq $ob.kind -and $wtie.longestGap.value.afterLine -eq $ob.line) ("the kind before the longest silence is the one M1's sort put there (" + $wtie.longestGap.value.afterKind + ")")

$script:line = 0
$acc = New-HordeMetricsAccumulator -PriceTable $noTable -From (At 5) -To (At 10)
foreach ($r in @((UserSays 0), (Call "w1" 6), (Call "w2" 8), (Call "w3" 12))) { $acc.Add($r) }
$win = (Complete-HordeMetricsAccumulator -Accumulator $acc).worker
Check ($win.calls.value -eq 2 -and $win.firstEventAt.value -eq (At 6)) "a window keeps only the records inside it (2 calls, from minute 6)"

Complete-HordeSuite -Success "every metric finds its planted case, finds nothing in a clean transcript, and never guesses an attribution"
