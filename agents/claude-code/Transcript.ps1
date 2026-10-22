# agents/claude-code/Transcript - the transcript adapter for Claude Code session files.
#
# WHAT IT READS. A session transcript, <store>/projects/<slug>/<sessionId>.jsonl, and an in-process
# subagent's, <store>/projects/<slug>/<sessionId>/subagents/agent-<agentId>.jsonl beside its
# agent-<agentId>.meta.json (metrics design 2.1, VERIFIED 2026-09-30). One JSON object per line. It
# turns them into core/Transcript.ps1 records and nothing else.
#
# WHERE ITS RULES COME FROM. The 2026-09-30 goblin-versus-agent study parsed these files by hand with
# throwaway scripts (worker-extract.js, orc-extract.js, join.js); planning/ledger/core-metrics-transcript.md
# lists every rule taken from them and what became of it. Measured again on 2026-10-01 against the
# orchestrator transcript the study read (31,204 lines): every line parsed; 4,981 assistant lines
# held 2,468 distinct message ids and 2,468 distinct request ids, one to one; every usage object had
# the cache_creation split; 14 lines had model "<synthetic>".
#
# THE RULES, each one a test in agents/claude-code/test/test-transcript.ps1:
#   - ONE CALL PER message.id. One API response is written as one line per content block, and every
#     line carries a usage object (design 2.1: summing lines inflated totals 1.6x to 1.9x; the study
#     summed "per unique assistant message.id", study 1.4). Text lengths and tool uses are gathered
#     across the lines; usage is the PER-FIELD MAXIMUM across them, because in a streamed response
#     output_tokens grows line by line (Add-ClaudeCodeUsageMax; review of PR #50, F1).
#   - A "<synthetic>" message, or one marked isApiErrorMessage, is the harness reporting an API error,
#     not a model call. It is an event, not a call. (The study counted it as a call; 14 such lines
#     in the orchestrator's transcript.)
#   - input_tokens EXCLUDES cache reads and writes on this harness, as the port requires; the cache
#     write is split into 5-minute and 1-hour lifetimes, priced differently (design 2.9).
#   - NOTIFICATIONS are user content or a queued_command attachment that the HARNESS marks as one -
#     origin.kind "task-notification", or on older attachments commandMode "task-notification" - never
#     text that merely contains <task-notification>, which a person can paste (review of PR #50, F2;
#     orc-extract.js read both shapes by their text, 594 and 137 of them in the orchestrator's
#     transcript on 2026-10-01). The queue-operation lines repeat a queued prompt as bookkeeping and are NOT read
#     as inputs, or each notification would count twice.
#   - A NOTIFICATION'S WORKER IS PROVED, never guessed. It carries <task-id> and <tool-use-id>
#     (measured 2026-10-01). The worker is known when the task id names a subagent transcript in the
#     session's subagents folder, or when the tool-use id is a worker-launching call in this
#     transcript; it is absent - provably not a worker - when the tool-use id is a call of any other
#     tool (a background shell job); otherwise unknown. The study instead attributed by "a message
#     naming the worker in the same turn", which it reported as over- and under-attributing
#     (study section 9, item 3).
#   - Interim notifications are those whose text says so in <note>, the harness's own field: "may be
#     interim" (join.js matched the words anywhere, including the result; review of PR #50, F4).
#   - The result of a worker-launching call lands on the worker its meta.json toolUseId names.
#   - Tool results are measured as the characters of their text blocks; images and tool references
#     count nothing (worker-extract.js). Only lengths are kept, never text.
#   - Turn ends are the harness's turn_duration lines; a file with none (a subagent's) uses the
#     calls whose stop_reason is end_turn instead, with the duration unknown.
#   - isMeta and isCompactSummary user lines are the harness's own text, not input: events.
#
# READ BY ALLOWLIST (design section 8): the fields above are read, and the rest of each line is
# dropped in memory. Every lookup of a key not named here is a review finding.
#
# No Set-StrictMode here: dot-sourced (see core/Tristate.ps1). Needs core/Tristate.ps1,
# core/ReadShared.ps1, core/JsonText.ps1 and core/Transcript.ps1.

$script:ClaudeCodeWorkerTools = @("Agent", "Task")

function Test-ClaudeCodeTranscript {
    # Is this file one of the harness's session transcripts? A .jsonl whose first parseable lines
    # carry a sessionId and a top-level type, and none a payload (the shape of other harnesses' files).
    param([string]$Path)
    if ([System.IO.Path]::GetExtension($Path) -ine ".jsonl" -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $stream = Open-HordeSharedStream -Path $Path
    try {
        $reader = New-Object System.IO.StreamReader($stream)
        try {
            $seen = 0
            while ($seen -lt 20 -and $null -ne ($text = $reader.ReadLine())) {
                if ($text.Trim() -eq "") { continue }
                $v = $null
                try { $v = ConvertFrom-HordeJsonObject -Text ($text) } catch { continue }
                if ($v -isnot [System.Collections.IDictionary]) { continue }
                $seen++
                if ($v.ContainsKey("payload")) { return $false }
                if ($v.ContainsKey("sessionId") -and $v["type"] -is [string]) { return $true }
            }
        } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
    return $false
}

function Get-ClaudeCodeText {
    # The text in a content value: a string, or the text blocks of a list joined. Held in memory only
    # long enough to be measured and searched for a notification; never stored.
    param($Content)
    if ($Content -is [string]) { return $Content }
    $sb = New-Object System.Text.StringBuilder
    if ($Content -is [System.Collections.IEnumerable]) {
        foreach ($b in $Content) {
            if ($b -is [System.Collections.IDictionary] -and $b["type"] -eq "text" -and $b["text"] -is [string]) { [void]$sb.Append($b["text"]) }
        }
    }
    return $sb.ToString()
}

function Get-ClaudeCodeTextChars {
    # The characters of the text in a content value.
    param($Content)
    return (Get-ClaudeCodeText $Content).Length
}

function New-ClaudeCodeCallFacts {
    # What the first read gathers about one message id across all its lines, as ten numbers, because
    # one is kept per call until the second read emits it (plan step M2): a hashtable per call cost
    # about 3 KB, measured 2026-10-02 on PowerShell 5.1; ten longs cost about 100 bytes.
    #   [0] lines that carried a usage object   [1] input_tokens        [2] cache_read_input_tokens
    #   [3] cache_creation_input_tokens          [4] output_tokens       [5] 5-minute cache writes
    #   [6] 1-hour cache writes                  [7] text characters     [8] tool uses
    #   [9] 1 when any line's stop_reason is end_turn
    # A token field no line has given yet holds [long]::MinValue, which any real count exceeds, so the
    # maximum below starts from "not given" exactly as M1's $null did.
    $f = New-Object 'long[]' 10
    for ($i = 1; $i -le 6; $i++) { $f[$i] = [long]::MinValue }
    return , $f
}

$script:ClaudeCodeUsageFields = @("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens", "output_tokens")

function Add-ClaudeCodeUsageMax {
    # Fold one line's usage into the maximum.
    #
    # THE MAXIMUM, NOT THE FIRST LINE AND NOT THE SUM (review of PR #50, F1). A response streamed in
    # blocks is written one line per block, and in subagent transcripts output_tokens GROWS from line
    # to line: measured 2026-10-02, read-only, on one session's 125 subagent files, 6,319 of 6,981
    # multi-line ids had growing output and none ever decreased; input and cache never differed.
    # The first line undercounted output by 88.9 percent; summing would overcount (design 2.1). The
    # study's worker-extract.js kept the LAST line; the maximum equals it on every id measured and
    # does not depend on line order.
    param($Max, $Usage)
    if ($Usage -isnot [System.Collections.IDictionary]) { return }
    $Max[0]++
    for ($i = 0; $i -lt 4; $i++) {
        $v = $Usage[$script:ClaudeCodeUsageFields[$i]]
        if ($null -ne $v -and [long]$v -gt $Max[$i + 1]) { $Max[$i + 1] = [long]$v }
    }
    $cc = $Usage["cache_creation"]
    if ($cc -is [System.Collections.IDictionary]) {
        $v = $cc["ephemeral_5m_input_tokens"]; if ($null -ne $v -and [long]$v -gt $Max[5]) { $Max[5] = [long]$v }
        $v = $cc["ephemeral_1h_input_tokens"]; if ($null -ne $v -and [long]$v -gt $Max[6]) { $Max[6] = [long]$v }
    }
}

function Get-ClaudeCodeUsage {
    # The port's usage answer from a message id's per-field maximum.
    param($Max)
    if ($Max[0] -eq 0) { return (New-HordeUnknown -Reason "the message carries no usage") }
    # A field no line gave is unknown, never a known 0 (review of PR #50, F5): the whole usage is then
    # unknown, naming the field, and the summary's totals say how many calls lack usage.
    for ($i = 0; $i -lt 4; $i++) {
        if ($Max[$i + 1] -eq [long]::MinValue) { return (New-HordeUnknown -Reason ("the usage has no " + $script:ClaudeCodeUsageFields[$i])) }
    }
    $split = New-HordeUnknown -Reason "the usage does not split cache writes by lifetime"
    if ($Max[5] -ne [long]::MinValue -or $Max[6] -ne [long]::MinValue) {
        $m5 = [long]0; if ($Max[5] -ne [long]::MinValue) { $m5 = $Max[5] }
        $h1 = [long]0; if ($Max[6] -ne [long]::MinValue) { $h1 = $Max[6] }
        $split = New-HordeKnown -Value ([pscustomobject]@{ m5 = $m5; h1 = $h1 })
    }
    return (New-HordeUsage -Uncached $Max[1] -CacheRead $Max[2] -CacheWrite $Max[3] -Output $Max[4] -Split $split)
}

function Test-ClaudeCodeNotificationOrigin {
    # Is this input the harness's own notification? Decided by STRUCTURE, never by the text: a person
    # who pastes a notification into the prompt wrote a user message (review of PR #50, F2).
    # Measured 2026-10-02, read-only, over every transcript on this machine: user lines carry
    # origin.kind "task-notification" (2,345) or "human"; queued attachments carry the same origin
    # (373), or, in lines written before origin existed, commandMode "task-notification" (1,016, every
    # one of them with no origin). 252 user lines contain notification text and have no origin: not
    # notifications. -CommandMode is given only for an attachment.
    param($Origin, $CommandMode = $null)
    if ($Origin -is [System.Collections.IDictionary]) { return ($Origin["kind"] -ceq "task-notification") }
    if ($null -eq $Origin -and $CommandMode -ceq "task-notification") { return $true }
    return $false
}

function Get-ClaudeCodeNotification {
    # The parts of a notification's text that link it to its subject. Called only for an input the
    # harness marked as a notification (Test-ClaudeCodeNotificationOrigin).
    param([string]$Text)
    $get = { param($tag) $m = [regex]::Match($Text, "<" + $tag + ">([^<]*)</" + $tag + ">"); if ($m.Success) { $m.Groups[1].Value.Trim() } else { "" } }
    $noteKind = Get-ClaudeCodeNoteKind -Note (& $get "note")
    return [pscustomobject]@{
        taskId = (& $get "task-id"); toolCallId = (& $get "tool-use-id"); status = (& $get "status")
        # Read from <note> only, never the whole text: a result can say "still running" (review of PR
        # #50, F4). <status> cannot tell: measured 2026-10-02, interim notifications carry "completed".
        interim = ($noteKind -ceq "interim"); noteKind = $noteKind
    }
}

function Get-ClaudeCodeNoteKind {
    # What a notification's <note> says: "interim", "final", "none" (no note), or "unrecognised".
    #
    # THE PHRASES ARE THE HARNESS'S OWN, AND ITS WORDING CAN CHANGE (verification of PR #50's fixes,
    # 2026-10-02): if it did, every interim note would silently read as final. So a note matching
    # neither list is "unrecognised", counted and shown, never assumed. Every distinct note on this
    # machine on 2026-10-02 (measured, read-only, over all transcripts) is one of these:
    #   interim (537): "This agent stopped with background work of its own still running ... the result
    #     below may be interim."
    #   final (898): "A task-notification fires each time this agent stops with no live background
    #     children of its own ..."
    #   final, a job stopped or lost (67, 3, 2, 1): "...stopped it because the system was critically
    #     low on memory...", "...start it again with `run_in_background`...", "No completion record was
    #     found for it/them in the previous session..."
    param([string]$Note)
    if ("$Note".Trim() -eq "") { return "none" }
    if ($Note -match 'may be interim') { return "interim" }
    foreach ($p in @('fires each time this agent stops with no live background children', 'stopped it because the system was critically low on memory', 'start it again with `run_in_background`', 'No completion record was found for')) {
        if ($Note.Contains($p)) { return "final" }
    }
    return "unrecognised"
}

function Read-ClaudeCodeSubagentLinks {
    # From the subagents folder beside a transcript: the agent ids that have a transcript, and the
    # map from the launching call's id to the agent id, read from each meta.json's toolUseId. Only
    # those two facts are read from a meta.json.
    param([string]$Path)
    $dir = Split-Path -Parent $Path
    $leaf = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $sub = $null
    if ($leaf -like "agent-*") { $sub = $dir } else { $sub = Join-Path (Join-Path $dir $leaf) "subagents" }
    $agents = New-Object 'System.Collections.Generic.HashSet[string]'
    $byTool = @{}
    $unreadable = 0
    if (Test-Path -LiteralPath $sub -PathType Container) {
        foreach ($f in @(Get-ChildItem -LiteralPath $sub -File)) {
            if ($f.Name -match '\Aagent-(.+)\.jsonl\z') { [void]$agents.Add($Matches[1]); continue }
            if ($f.Name -match '\Aagent-(.+)\.meta\.json\z') {
                $id = $Matches[1]
                try {
                    $meta = ConvertFrom-HordeJsonObject -Text ((Read-HordeSharedText -Path $f.FullName))
                    if ($meta -is [System.Collections.IDictionary] -and $meta["toolUseId"] -is [string]) { $byTool[$meta["toolUseId"]] = $id }
                } catch { $unreadable++ }
            }
        }
    }
    return [pscustomobject]@{ agents = $agents; byTool = $byTool; unreadableMeta = $unreadable }
}

function Read-ClaudeCodeTranscript {
    # The port's records for one transcript, handed to $Sink.Add in file order; returns
    # { records; parseSkipped; tornTail; sessionId }, records empty when a sink was given.
    #
    # TWO READS, BECAUSE A CALL'S RECORD STANDS AT ITS FIRST LINE BUT IS ONLY KNOWN AT ITS LAST. One
    # response is several lines, and its usage is the maximum over all of them (Add-ClaudeCodeUsageMax),
    # so M1 held every line until the end of the file. Plan step M2 must not hold them, and the lines of
    # one id are not always together: measured 2026-10-02, read-only, over this machine's 692
    # transcripts, an id came back after another id had started 73 times, all in one subagent file. So
    # the first read gathers, per id, the ten numbers of New-ClaudeCodeCallFacts, the name of every
    # tool call, and whether the file writes turn durations; the second read emits every record in M1's
    # order, each one complete when it is made. The second read stops exactly where the first did
    # (Read-HordeJsonLines -Upto), so a file still being written gives one consistent snapshot.
    param([string]$Path, $Sink = $null)
    $kept = $null
    if ($null -eq $Sink) { $kept = New-Object System.Collections.ArrayList; $Sink = $kept }
    $links = Read-ClaudeCodeSubagentLinks -Path $Path
    $calls = New-Object 'System.Collections.Generic.Dictionary[string,long[]]'
    $tools = New-Object 'System.Collections.Generic.Dictionary[string,string]'
    $st = @{ sessionId = ""; turnDurations = 0; phase = 1 }
    $isSessionFile = ([System.IO.Path]::GetFileName($Path) -notlike "agent-*")
    # Answers are never changed once made, so one is shared by every record it describes.
    $userAbsent = New-HordeAbsent -Note "a user message"
    $notWorker = @{}
    $errTrue = New-HordeKnown -Value $true
    $errFalse = New-HordeKnown -Value $false

    # ONE BLOCK FOR BOTH READS, so the two can never disagree about which lines are calls. Each read
    # streams one line at a time (core/Transcript.ps1, Read-HordeJsonLines -Each); "return" moves to the
    # next line. In the first read nothing is emitted.
    $visit = {
        param($ln, $v)
        if ($st.sessionId -eq "" -and $v["sessionId"] -is [string]) { $st.sessionId = $v["sessionId"] }
        $ts = ConvertTo-HordeUtcTime $v["timestamp"]
        if ($null -eq $ts) { return }
        $first = ($st.phase -eq 1)
        # A side chain inlined into a SESSION file is a subagent's work, not the session's (review of PR
        # #50, F10; metrics design 2.1): an event only. A subagent file is all side chain by design.
        if ($isSessionFile -and $v["isSidechain"] -eq $true) {
            if (-not $first) { $Sink.Add((New-HordeTranscriptRecord -Kind "event" -Role "system" -Ts $ts -Line $ln)) }
            return
        }
        $type = "$($v["type"])"

        if ($type -eq "assistant") {
            $msg = $v["message"]
            # Indexed directly, not through Get-HordeJsonPath: this runs once per line, and the helper cost
            # 6.6 s over a 31,204-line transcript (measured 2026-10-01).
            $model = ""
            if ($msg -is [System.Collections.IDictionary]) { $model = "$($msg["model"])" }
            if ($model -eq "<synthetic>" -or $v["isApiErrorMessage"] -eq $true -or $msg -isnot [System.Collections.IDictionary]) {
                if (-not $first) { $Sink.Add((New-HordeTranscriptRecord -Kind "event" -Role "system" -Ts $ts -Line $ln)) }
                return
            }
            $id = "$($msg["id"])"
            if ($id -eq "") { $id = "line-" + $ln }
            if ($first) {
                $f = $null
                if (-not $calls.TryGetValue($id, [ref]$f)) { $f = New-ClaudeCodeCallFacts; $calls[$id] = $f }
                Add-ClaudeCodeUsageMax -Max $f -Usage $msg["usage"]
                if ($msg["stop_reason"] -eq "end_turn") { $f[9] = 1 }
                if ($msg["content"] -is [string]) { $f[7] += $msg["content"].Length }
                foreach ($b in @($msg["content"])) {
                    if ($b -isnot [System.Collections.IDictionary]) { continue }
                    if ($b["type"] -eq "text" -and $b["text"] -is [string]) { $f[7] += $b["text"].Length }
                    elseif ($b["type"] -eq "tool_use") { $f[8]++; $tools["$($b["id"])"] = "$($b["name"])" }
                }
                return
            }
            # The call's record, at the first line of its id; later lines of the id add only their tool calls.
            $f = $null
            if ($calls.TryGetValue($id, [ref]$f)) {
                [void]$calls.Remove($id)
                $speed = ""; $geo = ""
                $mu = $msg["usage"]
                if ($mu -is [System.Collections.IDictionary]) { $speed = "$($mu["speed"])"; $geo = "$($mu["inference_geo"])" }
                $modelAnswer = New-HordeUnknown -Reason "the message names no model"
                if ($model -ne "") { $modelAnswer = New-HordeKnown -Value $model }
                $Sink.Add((New-HordeTranscriptRecord -Kind "call" -Role "assistant" -Ts $ts -Line $ln -Fields @{
                    id = $id; model = $modelAnswer; usage = (Get-ClaudeCodeUsage $f); textChars = [int]$f[7]; toolCallCount = [int]$f[8]; speed = $speed; inferenceGeo = $geo }))
                if ($st.turnDurations -eq 0 -and $f[9] -eq 1) {
                    $Sink.Add((New-HordeTranscriptRecord -Kind "turnEnd" -Role "system" -Ts $ts -Line $ln -Fields @{ durationMs = (New-HordeUnknown -Reason "this transcript writes no turn durations; the end is the call's end_turn") }))
                }
            }
            foreach ($b in @($msg["content"])) {
                if ($b -isnot [System.Collections.IDictionary] -or $b["type"] -ne "tool_use") { continue }
                $name = "$($b["name"])"
                $Sink.Add((New-HordeTranscriptRecord -Kind "toolCall" -Role "assistant" -Ts $ts -Line $ln -Fields @{ id = "$($b["id"])"; name = $name; callId = $id; launchesWorker = ($script:ClaudeCodeWorkerTools -ccontains $name) }))
            }
            return
        }

        if ($type -eq "system" -and $v["subtype"] -eq "turn_duration") {
            if ($first) { $st.turnDurations++; return }
            $dur = New-HordeUnknown -Reason "the turn_duration line has no durationMs"
            if ($null -ne $v["durationMs"]) { $dur = New-HordeKnown -Value ([long]$v["durationMs"]) }
            $Sink.Add((New-HordeTranscriptRecord -Kind "turnEnd" -Role "system" -Ts $ts -Line $ln -Fields @{ durationMs = $dur }))
            return
        }
        if ($first) { return }

        if ($type -eq "user") {
            if ($v["isMeta"] -eq $true -or $v["isCompactSummary"] -eq $true) {
                $Sink.Add((New-HordeTranscriptRecord -Kind "event" -Role "system" -Ts $ts -Line $ln))
                return
            }
            # A user line is a notification only when the harness says so (Test-ClaudeCodeNotificationOrigin).
            $isNote = Test-ClaudeCodeNotificationOrigin -Origin $v["origin"]
            $content = $null
            if ($v["message"] -is [System.Collections.IDictionary]) { $content = $v["message"]["content"] }
            if ($content -is [string]) { $Sink.Add((New-ClaudeCodeInputRecord -Tools $tools -Links $links -UserAbsent $userAbsent -IsNote $isNote -Text $content -Ts $ts -Line $ln)); return }
            foreach ($b in @($content)) {
                if ($b -isnot [System.Collections.IDictionary]) { continue }
                if ($b["type"] -eq "tool_result") {
                    $tid = "$($b["tool_use_id"])"
                    $name = $null
                    $worker = $null
                    if (-not $tools.TryGetValue($tid, [ref]$name)) { $worker = New-HordeUnknown -Reason ("the call " + $tid + " is not in this transcript, so whether it launched a worker cannot be told") }
                    elseif ($script:ClaudeCodeWorkerTools -cnotcontains $name) { if (-not $notWorker.ContainsKey($name)) { $notWorker[$name] = New-HordeAbsent -Note ("a " + $name + " result, not a worker's") }; $worker = $notWorker[$name] }
                    elseif ($links.byTool.ContainsKey($tid)) { $worker = New-HordeKnown -Value $links.byTool[$tid] }
                    else { $worker = New-HordeUnknown -Reason ("no meta.json names the launching call " + $tid) }
                    $Sink.Add((New-HordeTranscriptRecord -Kind "toolResult" -Role "tool" -Ts $ts -Line $ln -Fields @{ toolCallId = $tid; isError = $(if ($b["is_error"] -eq $true) { $errTrue } else { $errFalse }); chars = (Get-ClaudeCodeTextChars $b["content"]); worker = $worker }))
                }
                elseif ($b["type"] -eq "text" -and $b["text"] -is [string]) { $Sink.Add((New-ClaudeCodeInputRecord -Tools $tools -Links $links -UserAbsent $userAbsent -IsNote $isNote -Text $b["text"] -Ts $ts -Line $ln)) }
            }
            return
        }

        if ($type -eq "attachment") {
            $att = $v["attachment"]
            if ($att -is [System.Collections.IDictionary] -and $att["type"] -eq "queued_command") {
                # A prompt is a string or a list of content blocks; its text is held only until it has been
                # measured and looked at for a notification.
                $Sink.Add((New-ClaudeCodeInputRecord -Tools $tools -Links $links -UserAbsent $userAbsent -IsNote (Test-ClaudeCodeNotificationOrigin -Origin $att["origin"] -CommandMode $att["commandMode"]) -Text (Get-ClaudeCodeText $att["prompt"]) -Ts $ts -Line $ln))
                return
            }
        }

        if ($type -eq "system" -and $v["subtype"] -eq "compact_boundary") {
            $Sink.Add((New-HordeTranscriptRecord -Kind "compaction" -Role "system" -Ts $ts -Line $ln))
            return
        }
        $Sink.Add((New-HordeTranscriptRecord -Kind "event" -Role "system" -Ts $ts -Line $ln))
    }

    $firstRead = Read-HordeJsonLines -Path $Path -Each $visit
    $st.phase = 2
    $parsed = Read-HordeJsonLines -Path $Path -Each $visit -Upto $firstRead
    $sessionId = $st.sessionId
    if ($sessionId -eq "") { $sessionId = [System.IO.Path]::GetFileNameWithoutExtension($Path) }
    $records = @(); if ($null -ne $kept) { $records = $kept.ToArray() }
    # THE RECORD KEY IS THE TRANSCRIPT'S OWN IDENTITY, not its path (review of PR #70, F4): a session file is
    # its session id; a subagent file, which carries its parent's session id, is its own agent-<id> name.
    $recordKey = $sessionId
    if (-not $isSessionFile) { $recordKey = [System.IO.Path]::GetFileNameWithoutExtension($Path) }
    return [pscustomobject]@{ records = $records; parseSkipped = $parsed.parseSkipped; tornTail = $parsed.tornTail; sessionId = $sessionId; recordKey = $recordKey }
}

function New-ClaudeCodeInputRecord {
    # The record for one input: a user message, or a notification the harness marked as one, linked to
    # its subject only as far as this transcript and its subagents folder prove: -Tools maps each tool
    # call id in the transcript to its name, -Links is Read-ClaudeCodeSubagentLinks.
    param($Tools, $Links, $UserAbsent, [bool]$IsNote, [string]$Text, $Ts, [int]$Line)
    if (-not $IsNote) {
        return (New-HordeTranscriptRecord -Kind "input" -Role "user" -Ts $Ts -Line $Line -Fields @{ source = "user"; chars = $Text.Length; taskId = ""; toolCallId = ""; interim = $false; worker = $UserAbsent })
    }
    $n = Get-ClaudeCodeNotification -Text $Text
    # THE IDS IN A NOTIFICATION'S TEXT ARE CHECKED, NEVER COPIED (review of PR #50, F3). The text is the
    # harness's, but what reaches a record must be something this transcript or its subagents folder
    # vouches for: a task id that names a subagent transcript on disk, or a tool-use id that is a call
    # in this transcript. Anything else is dropped, so no text of a notification can become a key in a
    # written summary.
    $tcName = $null
    $tcKnown = ($n.toolCallId -ne "" -and $Tools.TryGetValue($n.toolCallId, [ref]$tcName))
    $taskOk = ($n.taskId -ne "" -and $Links.agents.Contains($n.taskId))
    $worker = $null
    if ($tcKnown -and $script:ClaudeCodeWorkerTools -ccontains $tcName) {
        if ($Links.byTool.ContainsKey($n.toolCallId)) { $worker = New-HordeKnown -Value $Links.byTool[$n.toolCallId] }
        elseif ($taskOk) { $worker = New-HordeKnown -Value $n.taskId }
        else { $worker = New-HordeKnown -Value $n.toolCallId }
    }
    elseif ($taskOk) { $worker = New-HordeKnown -Value $n.taskId }
    elseif ($tcKnown) { $worker = New-HordeAbsent -Note ("about a " + $tcName + " call, not a worker") }
    else { $worker = New-HordeUnknown -Reason "its task and call resolve to nothing in this transcript or its subagents folder" }
    $keptTask = ""; if ($taskOk) { $keptTask = $n.taskId }
    $keptCall = ""; if ($tcKnown) { $keptCall = $n.toolCallId }
    return (New-HordeTranscriptRecord -Kind "input" -Role "user" -Ts $Ts -Line $Line -Fields @{ source = "notification"; chars = $Text.Length; taskId = $keptTask; toolCallId = $keptCall; interim = [bool]$n.interim; noteKind = $n.noteKind; worker = $worker })
}

Register-HordeTranscriptAdapter -Name "claude-code" -Claim { param($p) Test-ClaudeCodeTranscript -Path $p } -Read { param($p, $s) Read-ClaudeCodeTranscript -Path $p -Sink $s }
