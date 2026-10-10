# DOES THE CLAUDE CODE CONVERSATION ADAPTER FIND THE THRALL, KEEP ONLY ITS WORDS, AND TAIL ITS FILE EXACTLY?
#
# agents/claude-code/Conversation.ps1, through conversations/Port.ps1 as a caller uses it, over synthetic
# registries and transcripts (ConversationLines.ps1; no real transcript is read or copied). The contract
# every adapter keeps is test/test-conversation-conformance.ps1's; this suite attacks what is particular
# to this harness:
#   - FINDING THE THRALL in the fleet's registry: one live master record; a retired one is not it; two
#     are never chosen between; a record with no transcript, or another session's, is unknown; a
#     registry with an unreadable record is unknown; a Thrall with no file yet reads empty; a past
#     session asked for by its id is found though retired, and a session that never held the role is not.
#   - WHAT IS A TURN: each kind of the harness's own line is planted alone and must give nothing; a
#     prompt as text blocks is one turn; a line with several text blocks gives one turn each, ids
#     uuid and uuid#1, one groupId; a response's text blocks split by tool results share the groupId; an
#     API error is a system turn; a side conversation gives nothing.
#   - THE TAIL: a batch of one through a line of three text blocks gives each once; a small byte limit
#     reads to the end in steps and gets exactly the whole; a line longer than a read may hold is
#     skipped with an anomaly while the next turn is still read, and is waited for while it has no line
#     end; a candidate line that does not parse is counted, not fatal; a rewrite that keeps the length
#     but changes the first bytes, or moves the line end from under the cursor, is a rotation.
#   - SPEED: a no-change re-read of a large synthetic transcript is fast (S4 measured 37 ms on a 27.3 MB
#     live file), and the first read of the whole of it is timed and reported.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "conversations\Port.ps1")
. (Join-Path $root "agents\claude-code\Conversation.ps1")
. (Join-Path $here "ConversationLines.ps1")

$vendor = "claude-code"
function Find-Thrall { param($Reg) return (Find-HordeConversationSource -Fleet "alpha" -Vendor $vendor -Require @() -Refuse @() -Options @{ registryRoot = $Reg.root }) }
function New-Thrall {
    # A registry with one live Thrall and its (empty) transcript: { reg; sid; path; src }.
    $reg = New-ClaudeCodeRegistry
    $sid = [guid]::NewGuid().ToString()
    $path = Set-ClaudeCodeRecord -Registry $reg -Session $sid
    [System.IO.File]::WriteAllText($path, "")
    return [pscustomobject]@{ reg = $reg; sid = $sid; path = $path; src = (Find-Thrall $reg).value }
}
function Read-Turns { param($T, $Cursor = $null, [int]$MaxTurns = 200, [long]$MaxBytes = 4194304) return (Read-HordeConversationTurns -Source $T.src -Cursor $Cursor -MaxTurns $MaxTurns -MaxBytes $MaxBytes) }
function Sig { param($Answer) return (@($Answer.value.turns | ForEach-Object { $_.role + ":" + $_.text }) -join "|") }
$made = New-Object System.Collections.ArrayList

try {
    Write-Host ""
    Write-Host "--- finding the Thrall in the registry ---" -ForegroundColor Cyan
    $reg = New-ClaudeCodeRegistry; [void]$made.Add($reg)
    Check ((Find-Thrall $reg).state -ceq "absent") "an empty registry: absent"
    $old = [guid]::NewGuid().ToString()
    $null = Set-ClaudeCodeRecord -Registry $reg -Session $old -Retired $true
    $orc = [guid]::NewGuid().ToString()
    $null = Set-ClaudeCodeRecord -Registry $reg -Session $orc -Role "orc"
    $null = Set-ClaudeCodeRecord -Registry $reg -Session ([guid]::NewGuid().ToString()) -Role ""
    Check ((Find-Thrall $reg).state -ceq "absent") "a retired master, an orc and a record with no role: still absent"
    $sid = [guid]::NewGuid().ToString()
    $path = Set-ClaudeCodeRecord -Registry $reg -Session $sid
    $f = Find-Thrall $reg
    Check ($f.state -ceq "known" -and $f.value.session -ceq $sid -and $f.value.locator -ceq $path) "one live master: known, its session and its transcript"
    $r = Read-HordeConversationTurns -Source $f.value -Cursor $null
    Check ($r.state -ceq "known" -and @($r.value.turns).Count -eq 0) "a Thrall that has not written its transcript yet reads empty"
    $second = [guid]::NewGuid().ToString()
    $null = Set-ClaudeCodeRecord -Registry $reg -Session $second
    $f = Find-Thrall $reg
    Check ($f.state -ceq "unknown" -and $f.reason -like "*2 live sessions*" -and $f.reason -like ("*" + $sid + "*")) ("two live masters: unknown, naming both (" + $f.reason + ")")
    $null = Set-ClaudeCodeRecord -Registry $reg -Session $second -Retired $true
    Check ((Find-Thrall $reg).state -ceq "known") "CONTROL: retire the second and the first is found again"
    $past = Find-HordeConversationSource -Fleet "alpha" -Vendor $vendor -Session $second -Require @() -Refuse @() -Options @{ registryRoot = $reg.root }
    Check ($past.state -ceq "known" -and $past.value.session -ceq $second -and $past.value.locator -ceq (Join-Path $reg.projects ($second + ".jsonl"))) ("asked by its id, a RETIRED Thrall session is found, with its own transcript (" + $past.state + ")")
    $notThrall = Find-HordeConversationSource -Fleet "alpha" -Vendor $vendor -Session $orc -Require @() -Refuse @() -Options @{ registryRoot = $reg.root }
    Check ($notThrall.state -ceq "absent") ("asked by its id, a session that never held the role is absent (" + $notThrall.state + ")")
    $null = Set-ClaudeCodeRecord -Registry $reg -Session $sid -TranscriptPath (Join-Path $reg.projects ($second + ".jsonl"))
    $f = Find-Thrall $reg
    Check ($f.state -ceq "unknown" -and $f.reason -like "*not its own session's file*") "a record naming another session's transcript: unknown"
    $rec = Join-Path $reg.root ("registry\sessions\" + $sid + ".json")
    $j = Get-Content -Raw $rec | ConvertFrom-Json; $j.PSObject.Properties.Remove("transcriptPath")
    [System.IO.File]::WriteAllText($rec, ($j | ConvertTo-Json))
    $f = Find-Thrall $reg
    Check ($f.state -ceq "unknown" -and $f.reason -like "*does not say where its transcript is*") "a record with no transcriptPath: unknown"
    $null = Set-ClaudeCodeRecord -Registry $reg -Session $sid
    [System.IO.File]::WriteAllText((Join-Path $reg.root "registry\sessions\broken.json"), "{ not json")
    $f = Find-Thrall $reg
    Check ($f.state -ceq "unknown" -and $f.reason -like "*could not all be read*") "a registry with an unreadable record: unknown - that record may be the Thrall's"

    Write-Host ""
    Write-Host "--- what is a turn ---" -ForegroundColor Cyan
    $T = New-Thrall; [void]$made.Add($T.reg)
    $kinds = @("thinking", "tool-use", "tool-result", "notification", "meta", "compact-summary", "interrupt", "sidechain-human", "sidechain-text", "turn-duration", "compact-boundary", "attachment", "last-prompt", "mode", "file-history-snapshot")
    $cursor = $null
    foreach ($k in $kinds) {
        Add-ClaudeCodeLines -Path $T.path -Lines @((New-ClaudeCodeLine -Kind $k -Session $T.sid -Text "words that must not be a turn"))
        $r = Read-Turns $T $cursor
        Check ($r.state -ceq "known" -and @($r.value.turns).Count -eq 0 -and @($r.value.anomalies).Count -eq 0) ("a " + $k + " line gives no turn and no anomaly")
        $cursor = $r.value.next
    }
    Add-ClaudeCodeLines -Path $T.path -Lines @((New-ClaudeCodeLine -Kind "human" -Session $T.sid -Text "a typed prompt"))
    $r = Read-Turns $T $cursor
    Check ((Sig $r) -ceq "user:a typed prompt") "CONTROL: a human line after them is a user turn"
    $cursor = $r.value.next
    Add-ClaudeCodeLines -Path $T.path -Lines @((New-ClaudeCodeLine -Kind "human-blocks" -Session $T.sid -Texts @("first block", "second block")))
    $r = Read-Turns $T $cursor
    Check ((Sig $r) -ceq "user:first block`nsecond block") "a prompt written as text blocks is one user turn, its blocks joined by a line end"
    $cursor = $r.value.next
    $u = [guid]::NewGuid().ToString()
    Add-ClaudeCodeLines -Path $T.path -Lines @((New-ClaudeCodeLine -Kind "assistant-texts" -Session $T.sid -Texts @("part one", "part two") -Uuid $u -MessageId "msg_syntheticAAAA"))
    $r = Read-Turns $T $cursor
    Check ((Sig $r) -ceq "assistant:part one|assistant:part two" -and $r.value.turns[0].turnId -ceq $u -and $r.value.turns[1].turnId -ceq ($u + "#1")) "a line of two text blocks: two turns, ids uuid and uuid#1"
    Check (@($r.value.turns | Where-Object { $null -ne $_.PSObject.Properties["groupId"] -and $_.groupId -ceq "msg_syntheticAAAA" }).Count -eq 2) "both carry the response's message id as their groupId"
    $cursor = $r.value.next
    Add-ClaudeCodeLines -Path $T.path -Lines @(
        (New-ClaudeCodeLine -Kind "assistant-text" -Session $T.sid -Text "before the tool" -MessageId "msg_syntheticBBBB"),
        (New-ClaudeCodeLine -Kind "tool-use" -Session $T.sid -MessageId "msg_syntheticBBBB"),
        (New-ClaudeCodeLine -Kind "tool-result" -Session $T.sid),
        (New-ClaudeCodeLine -Kind "assistant-text" -Session $T.sid -Text "after the tool" -MessageId "msg_syntheticBBBB"))
    $r = Read-Turns $T $cursor
    Check ((Sig $r) -ceq "assistant:before the tool|assistant:after the tool" -and @($r.value.turns | Where-Object { $null -eq $_.PSObject.Properties["groupId"] -or $_.groupId -cne "msg_syntheticBBBB" }).Count -eq 0) "a response's text split by a tool call and its result: two turns, one groupId"
    $cursor = $r.value.next
    Add-ClaudeCodeLines -Path $T.path -Lines @((New-ClaudeCodeLine -Kind "synthetic" -Session $T.sid -Text "API Error: synthetic overload"))
    $r = Read-Turns $T $cursor
    Check ((Sig $r) -ceq "system:API Error: synthetic overload") "the harness's own API error is a system turn"
    $cursor = $r.value.next
    Add-ClaudeCodeLines -Path $T.path -Lines @((New-ClaudeCodeLine -Kind "human" -Session $T.sid -Text "   "), (New-ClaudeCodeLine -Kind "assistant-text" -Session $T.sid -Text ""))
    $r = Read-Turns $T $cursor
    Check (@($r.value.turns).Count -eq 0) "a prompt or a text block of nothing but white space is no turn"
    $cursor = $r.value.next
    # THE HARNESS'S OWN FLAGS WIN over origin: a meta line or a compaction summary is the harness's text
    # even if a later version also marked it human (none has been seen marked so; this is a defence).
    $metaHuman = (New-ClaudeCodeLine -Kind "meta" -Session $T.sid).Replace('"isMeta":true', '"isMeta":true,"origin":{"kind":"human"}')
    $summaryHuman = (New-ClaudeCodeLine -Kind "compact-summary" -Session $T.sid).Replace('"isCompactSummary":true', '"isCompactSummary":true,"origin":{"kind":"human"}')
    Add-ClaudeCodeLines -Path $T.path -Lines @($metaHuman, $summaryHuman)
    $r = Read-Turns $T $cursor
    Check (@($r.value.turns).Count -eq 0) "a meta line and a compaction summary are no turn even when marked human"
    $cursor = $r.value.next
    # A TOOL'S STRUCTURED OUTPUT may hold any member, "kind":"human" among them: only the line's own origin counts.
    # An interruption marker carries text blocks and no origin: with a member that happens to say kind
    # human, only the origin check keeps its text out.
    $toolHuman = (New-ClaudeCodeLine -Kind "tool-result" -Session $T.sid).Replace('"toolUseResult":{', '"toolUseResult":{"kind":"human",')
    $interruptHuman = (New-ClaudeCodeLine -Kind "interrupt" -Session $T.sid).Replace('"uuid":', '"extra":{"kind":"human"},"uuid":')
    Add-ClaudeCodeLines -Path $T.path -Lines @($toolHuman, $interruptHuman)
    $r = Read-Turns $T $cursor
    Check (@($r.value.turns).Count -eq 0 -and $toolHuman.Contains('"kind":"human"') -and $interruptHuman.Contains('"kind":"human"')) "a tool result and an interruption marker that hold kind human elsewhere are no turn: the prefilter passes them, the origin check does not"
    $cursor = $r.value.next
    # THE PREFILTER'S STATED LIMIT: it looks for the harness's compact spelling, so a line spaced out
    # by another writer is skipped. Pinned so that it is a decision (the harness writes compact JSON:
    # 16,276 of 16,276 lines, 2026-10-10).
    $spaced = (New-ClaudeCodeLine -Kind "human" -Session $T.sid -Text "spaced out") -replace '":"', '": "'
    Add-ClaudeCodeLines -Path $T.path -Lines @($spaced)
    $r = Read-Turns $T $cursor
    Check (@($r.value.turns).Count -eq 0) "the stated limit: a human line written with spaces after its colons is not seen by the prefilter"
    $cursor = $r.value.next
    Add-ClaudeCodeLines -Path $T.path -Lines @('{"type":"user","origin":{"kind":"human"},"message":{"content":"torn', (New-ClaudeCodeLine -Kind "human" -Session $T.sid -Text "after the bad line"))
    $r = Read-Turns $T $cursor
    Check ((Sig $r) -ceq "user:after the bad line" -and (@($r.value.anomalies) -join " ") -like "*1 line(s)*could not be parsed*") "a candidate line that does not parse is counted as an anomaly, and the next turn is still read"
    Check (-not ((@($r.value.anomalies) -join " ").Contains("torn"))) "and the anomaly does not quote the line"

    Write-Host ""
    Write-Host "--- the tail ---" -ForegroundColor Cyan
    $T = New-Thrall; [void]$made.Add($T.reg)
    Add-ClaudeCodeLines -Path $T.path -Lines @((New-ClaudeCodeLine -Kind "assistant-texts" -Session $T.sid -Texts @("one", "two", "three")), (New-ClaudeCodeLine -Kind "human" -Session $T.sid -Text "four"))
    $got = New-Object System.Collections.ArrayList
    $c = $null
    for ($i = 0; $i -lt 10; $i++) {
        $r = Read-Turns $T $c -MaxTurns 1
        foreach ($turn in @($r.value.turns)) { [void]$got.Add($turn.text) }
        $c = $r.value.next
        if (-not $r.value.more) { break }
    }
    Check (($got -join ",") -ceq "one,two,three,four") ("a batch of one through a line of three text blocks: each once, in order (" + ($got -join ",") + ")")
    $T = New-Thrall; [void]$made.Add($T.reg)
    $lines = New-Object System.Collections.ArrayList
    foreach ($i in 1..30) { foreach ($n in @(New-ClaudeCodeNoise -Session $T.sid)) { [void]$lines.Add($n) }; [void]$lines.Add((New-ClaudeCodeLine -Kind "human" -Session $T.sid -Text ("prompt " + $i))) }
    Add-ClaudeCodeLines -Path $T.path -Lines @($lines)
    $whole = Read-Turns $T $null -MaxTurns 1000
    $steps = 0; $c = $null; $texts = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt 2000; $i++) {
        $r = Read-Turns $T $c -MaxBytes 2048
        $steps++
        foreach ($turn in @($r.value.turns)) { [void]$texts.Add($turn.text) }
        $c = $r.value.next
        if (-not $r.value.more) { break }
    }
    $len = (Get-Item -LiteralPath $T.path).Length
    Check (@($whole.value.turns).Count -eq 30 -and ($texts -join ",") -ceq (@($whole.value.turns | ForEach-Object { $_.text }) -join ",")) ("reads of at most 2 KiB, " + $steps + " of them over " + $len + " bytes, get exactly the 30 turns one read gets")
    Check ($steps -ge [int]($len / 2048)) "and the byte limit was kept: at least as many steps as 2 KiB pieces"
    $T = New-Thrall; [void]$made.Add($T.reg)
    $huge = New-ClaudeCodeLine -Kind "human" -Session $T.sid -Text ("x" * 9000)
    Add-ClaudeCodeLines -Path $T.path -Lines @((New-ClaudeCodeLine -Kind "human" -Session $T.sid -Text "before"), $huge, (New-ClaudeCodeLine -Kind "human" -Session $T.sid -Text "after"))
    $c = $null; $texts = New-Object System.Collections.ArrayList; $anoms = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt 50; $i++) { $r = Read-Turns $T $c -MaxBytes 4096; foreach ($turn in @($r.value.turns)) { [void]$texts.Add($turn.text) }; foreach ($a in @($r.value.anomalies)) { [void]$anoms.Add($a) }; $c = $r.value.next; if (-not $r.value.more) { break } }
    Check (($texts -join ",") -ceq "before,after" -and ($anoms -join " ") -like "*more than the 4096 a read may hold, was skipped*") "a line longer than a read may hold is skipped with an anomaly, and the turns around it are read"
    $T = New-Thrall; [void]$made.Add($T.reg)
    Add-ClaudeCodeLines -Path $T.path -Lines @((New-ClaudeCodeLine -Kind "human" -Session $T.sid -Text "first"))
    $r = Read-Turns $T $null -MaxBytes 4096
    $c = $r.value.next
    $bigLine = New-ClaudeCodeLine -Kind "human" -Session $T.sid -Text ("y" * 9000)
    [System.IO.File]::AppendAllText($T.path, $bigLine.Substring(0, 6000))
    $r = Read-Turns $T $c -MaxBytes 4096
    Check ($r.state -ceq "known" -and @($r.value.turns).Count -eq 0 -and $r.value.next.position -ceq $c.position -and @($r.value.anomalies).Count -eq 0) "a long line still being written is waited for, not skipped"
    [System.IO.File]::AppendAllText($T.path, $bigLine.Substring(6000) + "`n")
    $r = Read-Turns $T $c -MaxBytes 4096
    Check ($r.state -ceq "known" -and @($r.value.turns).Count -eq 0 -and (@($r.value.anomalies) -join " ") -like "*was skipped*") "and once whole, longer than a read, it is skipped"

    Write-Host ""
    Write-Host "--- rotation ---" -ForegroundColor Cyan
    $T = New-Thrall; [void]$made.Add($T.reg)
    Add-ClaudeCodeLines -Path $T.path -Lines @((New-ClaudeCodeLine -Kind "human" -Session $T.sid -Text "original"), (New-ClaudeCodeLine -Kind "assistant-text" -Session $T.sid -Text "original reply"))
    $r = Read-Turns $T $null
    $c = $r.value.next
    [System.IO.File]::Delete($T.path)
    Add-ClaudeCodeLines -Path $T.path -Lines @((New-ClaudeCodeLine -Kind "human" -Session $T.sid -Text "rewritten, and longer than before, so the length alone cannot tell"), (New-ClaudeCodeLine -Kind "assistant-text" -Session $T.sid -Text "a rewritten reply"), (New-ClaudeCodeLine -Kind "human" -Session $T.sid -Text "and one more"))
    $r = Read-Turns $T $c
    Check ($r.state -ceq "known" -and $r.value.reset -ceq "rotated" -and @($r.value.turns).Count -eq 3 -and (@($r.value.anomalies) -join " ") -like "*first bytes changed*") "a file rewritten longer with other first bytes: rotated, read from its start"
    $c = $r.value.next
    [System.IO.File]::Delete($T.path)
    Add-ClaudeCodeLines -Path $T.path -Lines @((New-ClaudeCodeLine -Kind "human" -Session $T.sid -Text "short"))
    $r = Read-Turns $T $c
    Check ($r.state -ceq "known" -and $r.value.reset -ceq "rotated" -and (Sig $r) -ceq "user:short" -and (@($r.value.anomalies) -join " ") -like "*shorter than the cursor*") "a file rewritten shorter than the cursor: rotated, and the reason says so"
    # THE SAME FIRST 4 KiB, a line end moved from under the cursor.
    $T = New-Thrall; [void]$made.Add($T.reg)
    $pad = New-Object System.Collections.ArrayList
    foreach ($i in 1..40) { [void]$pad.Add((New-ClaudeCodeLine -Kind "mode" -Session $T.sid)) }
    foreach ($i in 1..40) { [void]$pad.Add((New-ClaudeCodeLine -Kind "human" -Session $T.sid -Text ("filler " + $i))) }
    Add-ClaudeCodeLines -Path $T.path -Lines @($pad)
    $r = Read-Turns $T $null -MaxTurns 1000
    $c = $r.value.next
    $bytes = [System.IO.File]::ReadAllBytes($T.path)
    Check ($bytes.Length -gt 8192) ("CONTROL: the file is past the 4 KiB head (" + $bytes.Length + " bytes)")
    $keep = New-Object byte[] 4096
    [Array]::Copy($bytes, $keep, 4096)
    $tail = [System.Text.Encoding]::UTF8.GetBytes("Q" * ($bytes.Length - 4096 + 200) + "`n")
    $fs = [System.IO.File]::Open($T.path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
    try { $fs.Write($keep, 0, $keep.Length); $fs.Write($tail, 0, $tail.Length) } finally { $fs.Dispose() }
    $r = Read-Turns $T $c
    Check ($r.state -ceq "known" -and $r.value.reset -ceq "rotated" -and (@($r.value.anomalies) -join " ") -like "*no line ends where the cursor stands*") "the same first 4 KiB, longer, but no line end at the cursor: rotated"
    [System.IO.File]::Delete($T.path)
    $r = Read-Turns $T $c
    Check ($r.state -ceq "unknown" -and $r.reason -like "*no longer there*") "the transcript gone after it was read: unknown"
    $bad = [pscustomobject]@{ schemaVersion = 1; vendor = $vendor; session = $T.sid; position = "v2.whatever" }
    Check ((Read-Turns $T $bad).state -ceq "unknown") "a position this adapter does not write: unknown"

    Write-Host ""
    Write-Host "--- speed, on a large synthetic transcript ---" -ForegroundColor Cyan
    $T = New-Thrall; [void]$made.Add($T.reg)
    # Built by repeating synthetic lines, in the live file's proportions (2026-10-10: about one prompt or
    # text block per 13 lines, the rest tool results, tool calls and bookkeeping, 1.7 KB a line).
    $result = New-ClaudeCodeLine -Kind "tool-result" -Session $T.sid
    $result = $result.Replace("synthetic tool output, never a turn", ("synthetic tool output " * 80))
    $blockA = New-Object System.Text.StringBuilder
    foreach ($i in 1..10) { [void]$blockA.Append($result).Append("`n") }
    [void]$blockA.Append((New-ClaudeCodeLine -Kind "tool-use" -Session $T.sid)).Append("`n")
    $enc = New-Object System.Text.UTF8Encoding $false
    $fs = [System.IO.File]::Open($T.path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
    try {
        foreach ($i in 1..1200) {
            $b = $enc.GetBytes($blockA.ToString() + (New-ClaudeCodeLine -Kind "human" -Session $T.sid -Text ("prompt " + $i)) + "`n" + (New-ClaudeCodeLine -Kind "assistant-text" -Session $T.sid -Text ("reply " + $i)) + "`n")
            $fs.Write($b, 0, $b.Length)
        }
    } finally { $fs.Dispose() }
    $size = (Get-Item -LiteralPath $T.path).Length
    Check ($size -gt 20000000) ("CONTROL: the synthetic transcript is large (" + [Math]::Round($size / 1MB, 1) + " MB)")
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $c = $null; $n = 0
    for ($i = 0; $i -lt 100; $i++) { $r = Read-Turns $T $c -MaxTurns 1000 -MaxBytes 33554432; $n += @($r.value.turns).Count; $c = $r.value.next; if (-not $r.value.more) { break } }
    $clock.Stop()
    $firstMs = $clock.ElapsedMilliseconds
    Check ($n -eq 2400) ("the whole file read to its end: 2,400 turns, in " + $firstMs + " ms")
    $times = New-Object System.Collections.ArrayList
    foreach ($k in 1..5) { $clock = [System.Diagnostics.Stopwatch]::StartNew(); $r = Read-Turns $T $c; $clock.Stop(); [void]$times.Add($clock.ElapsedMilliseconds) }
    $best = ($times | Measure-Object -Minimum).Minimum
    Check ($r.state -ceq "known" -and @($r.value.turns).Count -eq 0 -and $best -lt 250) ("a re-read with nothing new is fast: best of five " + $best + " ms (" + ($times -join ", ") + " ms), under 250")
    Add-ClaudeCodeLines -Path $T.path -Lines @((New-ClaudeCodeLine -Kind "human" -Session $T.sid -Text "one more"))
    $clock = [System.Diagnostics.Stopwatch]::StartNew(); $r = Read-Turns $T $c; $clock.Stop()
    Check ((Sig $r) -ceq "user:one more" -and $clock.ElapsedMilliseconds -lt 500) ("one new line at the end of it is read in " + $clock.ElapsedMilliseconds + " ms, under 500")
} finally {
    foreach ($m in $made) { Remove-ClaudeCodeRegistry -Registry $m }
}

Complete-HordeSuite -Success "the Thrall is found, only its words are kept, and its file is tailed exactly"
