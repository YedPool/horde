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
#   - NOTIFICATIONS are user content or a queued_command attachment containing <task-notification>
#     (orc-extract.js read both shapes; 594 and 137 of them in the orchestrator's transcript on
#     2026-10-01). The queue-operation lines repeat a queued prompt as bookkeeping and are NOT read
#     as inputs, or each notification would count twice.
#   - A NOTIFICATION'S WORKER IS PROVED, never guessed. It carries <task-id> and <tool-use-id>
#     (measured 2026-10-01). The worker is known when the task id names a subagent transcript in the
#     session's subagents folder, or when the tool-use id is a worker-launching call in this
#     transcript; it is absent - provably not a worker - when the tool-use id is a call of any other
#     tool (a background shell job); otherwise unknown. The study instead attributed by "a message
#     naming the worker in the same turn", which it reported as over- and under-attributing
#     (study section 9, item 3).
#   - Interim notifications are those whose text says "still running" or "may be interim" (join.js).
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
# core/ReadShared.ps1 and core/Transcript.ps1.

$script:ClaudeCodeWorkerTools = @("Agent", "Task")

function Get-ClaudeCodeStoreRoots {
    # Where the harness keeps its own files. CLAUDE_CONFIG_DIR moves the store (design 2.1); both the
    # moved and the default folder are protected, since either may hold transcripts.
    $roots = @()
    if ("$env:CLAUDE_CONFIG_DIR".Trim() -ne "") { $roots += "$env:CLAUDE_CONFIG_DIR" }
    if ("$env:USERPROFILE".Trim() -ne "") { $roots += (Join-Path "$env:USERPROFILE" ".claude") }
    return $roots
}

function Test-ClaudeCodeTranscript {
    # Is this file one of the harness's session transcripts? A .jsonl whose first parseable lines
    # carry a sessionId and a top-level type, and none a payload (the shape of other harnesses' files).
    param([string]$Path)
    if ([System.IO.Path]::GetExtension($Path) -ine ".jsonl" -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    Add-Type -AssemblyName System.Web.Extensions
    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $ser.MaxJsonLength = [int]::MaxValue
    $stream = Open-HordeSharedStream -Path $Path
    try {
        $reader = New-Object System.IO.StreamReader($stream)
        try {
            $seen = 0
            while ($seen -lt 20 -and $null -ne ($text = $reader.ReadLine())) {
                if ($text.Trim() -eq "") { continue }
                $v = $null
                try { $v = $ser.DeserializeObject($text) } catch { continue }
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

function New-ClaudeCodeUsageMax {
    # The running per-field maximum of one message id's usage, across all its lines; $null until a
    # line gives the field.
    return @{ lines = 0; input_tokens = $null; cache_read_input_tokens = $null; cache_creation_input_tokens = $null; output_tokens = $null; m5 = $null; h1 = $null }
}

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
    $Max.lines++
    foreach ($k in @("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens", "output_tokens")) {
        $v = $Usage[$k]
        if ($null -ne $v -and ($null -eq $Max[$k] -or [long]$v -gt $Max[$k])) { $Max[$k] = [long]$v }
    }
    $cc = $Usage["cache_creation"]
    if ($cc -is [System.Collections.IDictionary]) {
        foreach ($pair in @(@("m5", "ephemeral_5m_input_tokens"), @("h1", "ephemeral_1h_input_tokens"))) {
            $v = $cc[$pair[1]]
            if ($null -ne $v -and ($null -eq $Max[$pair[0]] -or [long]$v -gt $Max[$pair[0]])) { $Max[$pair[0]] = [long]$v }
        }
    }
}

function Get-ClaudeCodeUsage {
    # The port's usage answer from a message id's per-field maximum.
    param($Max)
    if ($Max.lines -eq 0) { return (New-HordeUnknown -Reason "the message carries no usage") }
    $num = { param($v) if ($null -eq $v) { [long]0 } else { [long]$v } }
    $split = New-HordeUnknown -Reason "the usage does not split cache writes by lifetime"
    if ($null -ne $Max.m5 -or $null -ne $Max.h1) {
        $split = New-HordeKnown -Value ([pscustomobject]@{ m5 = (& $num $Max.m5); h1 = (& $num $Max.h1) })
    }
    return (New-HordeUsage -Uncached (& $num $Max.input_tokens) -CacheRead (& $num $Max.cache_read_input_tokens) -CacheWrite (& $num $Max.cache_creation_input_tokens) -Output (& $num $Max.output_tokens) -Split $split)
}

function Get-ClaudeCodeNotification {
    # The parts of a <task-notification> text that link it to its subject, or $null if it is not one.
    param([string]$Text)
    if ($Text -notlike "*<task-notification>*") { return $null }
    $get = { param($tag) $m = [regex]::Match($Text, "<" + $tag + ">([^<]*)</" + $tag + ">"); if ($m.Success) { $m.Groups[1].Value.Trim() } else { "" } }
    return [pscustomobject]@{
        taskId = (& $get "task-id"); toolCallId = (& $get "tool-use-id"); status = (& $get "status")
        interim = ($Text -match 'still running|may be interim')
    }
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
        Add-Type -AssemblyName System.Web.Extensions
        $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        foreach ($f in @(Get-ChildItem -LiteralPath $sub -File)) {
            if ($f.Name -match '\Aagent-(.+)\.jsonl\z') { [void]$agents.Add($Matches[1]); continue }
            if ($f.Name -match '\Aagent-(.+)\.meta\.json\z') {
                $id = $Matches[1]
                try {
                    $meta = $ser.DeserializeObject((Read-HordeSharedText -Path $f.FullName))
                    if ($meta -is [System.Collections.IDictionary] -and $meta["toolUseId"] -is [string]) { $byTool[$meta["toolUseId"]] = $id }
                } catch { $unreadable++ }
            }
        }
    }
    return [pscustomobject]@{ agents = $agents; byTool = $byTool; unreadableMeta = $unreadable }
}

function Read-ClaudeCodeTranscript {
    # The port's records for one transcript: { records; parseSkipped; tornTail; sessionId }.
    param([string]$Path)
    $links = Read-ClaudeCodeSubagentLinks -Path $Path
    # Calls are built across lines, so each is a mutable holder until the end.
    $slots = New-Object System.Collections.ArrayList
    $callAt = @{}
    $toolCalls = @{}
    $st = @{ sessionId = ""; turnDurations = 0 }

    # STREAMED, one line at a time (core/Transcript.ps1, Read-HordeJsonLines -Each): holding a large
    # transcript whole slowed every allocation tenfold. Inside the block, "return" moves to the next line.
    $parsed = Read-HordeJsonLines -Path $Path -Each {
        param($ln, $v)
        if ($st.sessionId -eq "" -and $v["sessionId"] -is [string]) { $st.sessionId = $v["sessionId"] }
        $ts = ConvertTo-HordeUtcTime $v["timestamp"]
        if ($null -eq $ts) { return }
        $type = "$($v["type"])"

        if ($type -eq "assistant") {
            $msg = $v["message"]
            # Indexed directly, not through Get-HordeJsonPath: this runs once per line, and the helper cost
            # 6.6 s over a 31,204-line transcript (measured 2026-10-01).
            $model = ""
            if ($msg -is [System.Collections.IDictionary]) { $model = "$($msg["model"])" }
            if ($model -eq "<synthetic>" -or $v["isApiErrorMessage"] -eq $true -or $msg -isnot [System.Collections.IDictionary]) {
                [void]$slots.Add([pscustomobject]@{ kind = "record"; record = (New-HordeTranscriptRecord -Kind "event" -Role "system" -Ts $ts -Line $ln) })
                return
            }
            $id = "$($msg["id"])"
            if ($id -eq "") { $id = "line-" + $ln }
            $slot = $callAt[$id]
            if ($null -eq $slot) {
                $speed = ""; $geo = ""
                $mu = $msg["usage"]
                if ($mu -is [System.Collections.IDictionary]) { $speed = "$($mu["speed"])"; $geo = "$($mu["inference_geo"])" }
                $modelAnswer = New-HordeUnknown -Reason "the message names no model"
                if ($model -ne "") { $modelAnswer = New-HordeKnown -Value $model }
                $slot = [pscustomobject]@{ kind = "call"; id = $id; ts = $ts; line = $ln; model = $modelAnswer; usage = (New-ClaudeCodeUsageMax)
                    textChars = 0; toolCallCount = 0; speed = $speed; inferenceGeo = $geo; endTurn = $false }
                $callAt[$id] = $slot
                [void]$slots.Add($slot)
            }
            Add-ClaudeCodeUsageMax -Max $slot.usage -Usage $msg["usage"]
            if ($msg["stop_reason"] -eq "end_turn") { $slot.endTurn = $true }
            if ($msg["content"] -is [string]) { $slot.textChars += $msg["content"].Length }
            foreach ($b in @($msg["content"])) {
                if ($b -isnot [System.Collections.IDictionary]) { continue }
                if ($b["type"] -eq "text" -and $b["text"] -is [string]) { $slot.textChars += $b["text"].Length }
                elseif ($b["type"] -eq "tool_use") {
                    $slot.toolCallCount++
                    $name = "$($b["name"])"
                    $tc = New-HordeTranscriptRecord -Kind "toolCall" -Role "assistant" -Ts $ts -Line $ln -Fields @{ id = "$($b["id"])"; name = $name; callId = $id; launchesWorker = ($script:ClaudeCodeWorkerTools -ccontains $name) }
                    $toolCalls["$($b["id"])"] = $tc
                    [void]$slots.Add([pscustomobject]@{ kind = "record"; record = $tc })
                }
            }
            return
        }

        if ($type -eq "user") {
            if ($v["isMeta"] -eq $true -or $v["isCompactSummary"] -eq $true) {
                [void]$slots.Add([pscustomobject]@{ kind = "record"; record = (New-HordeTranscriptRecord -Kind "event" -Role "system" -Ts $ts -Line $ln) })
                return
            }
            $content = $null
            if ($v["message"] -is [System.Collections.IDictionary]) { $content = $v["message"]["content"] }
            if ($content -is [string]) { [void]$slots.Add([pscustomobject]@{ kind = "input"; text = $content; ts = $ts; line = $ln }); return }
            foreach ($b in @($content)) {
                if ($b -isnot [System.Collections.IDictionary]) { continue }
                if ($b["type"] -eq "tool_result") {
                    [void]$slots.Add([pscustomobject]@{ kind = "result"; toolCallId = "$($b["tool_use_id"])"; isError = ($b["is_error"] -eq $true); chars = (Get-ClaudeCodeTextChars $b["content"]); ts = $ts; line = $ln })
                }
                elseif ($b["type"] -eq "text" -and $b["text"] -is [string]) { [void]$slots.Add([pscustomobject]@{ kind = "input"; text = $b["text"]; ts = $ts; line = $ln }) }
            }
            return
        }

        if ($type -eq "attachment") {
            $att = $v["attachment"]
            if ($att -is [System.Collections.IDictionary] -and $att["type"] -eq "queued_command") {
                # A prompt is a string or a list of content blocks; its text is held only until the
                # second pass has measured it and looked for a notification in it.
                [void]$slots.Add([pscustomobject]@{ kind = "input"; text = (Get-ClaudeCodeText $att["prompt"]); ts = $ts; line = $ln })
                return
            }
        }

        if ($type -eq "system" -and $v["subtype"] -eq "turn_duration") {
            $st.turnDurations++
            $dur = New-HordeUnknown -Reason "the turn_duration line has no durationMs"
            if ($null -ne $v["durationMs"]) { $dur = New-HordeKnown -Value ([long]$v["durationMs"]) }
            [void]$slots.Add([pscustomobject]@{ kind = "record"; record = (New-HordeTranscriptRecord -Kind "turnEnd" -Role "system" -Ts $ts -Line $ln -Fields @{ durationMs = $dur }) })
            return
        }
        if ($type -eq "system" -and $v["subtype"] -eq "compact_boundary") {
            [void]$slots.Add([pscustomobject]@{ kind = "record"; record = (New-HordeTranscriptRecord -Kind "compaction" -Role "system" -Ts $ts -Line $ln) })
            return
        }
        [void]$slots.Add([pscustomobject]@{ kind = "record"; record = (New-HordeTranscriptRecord -Kind "event" -Role "system" -Ts $ts -Line $ln) })
    }

    # Second pass: everything that needs the whole file - which calls launch workers, and the
    # subagents folder - is known now.
    $records = New-Object System.Collections.ArrayList
    # Answers are never changed once made, so one is shared by every record it describes.
    $userAbsent = New-HordeAbsent -Note "a user message"
    $notWorker = @{}
    $errTrue = New-HordeKnown -Value $true
    $errFalse = New-HordeKnown -Value $false
    foreach ($s in $slots) {
        switch ($s.kind) {
            "record" { [void]$records.Add($s.record) }
            "call" {
                [void]$records.Add((New-HordeTranscriptRecord -Kind "call" -Role "assistant" -Ts $s.ts -Line $s.line -Fields @{
                    id = $s.id; model = $s.model; usage = (Get-ClaudeCodeUsage $s.usage); textChars = $s.textChars; toolCallCount = $s.toolCallCount; speed = $s.speed; inferenceGeo = $s.inferenceGeo }))
                if ($st.turnDurations -eq 0 -and $s.endTurn) {
                    [void]$records.Add((New-HordeTranscriptRecord -Kind "turnEnd" -Role "system" -Ts $s.ts -Line $s.line -Fields @{ durationMs = (New-HordeUnknown -Reason "this transcript writes no turn durations; the end is the call's end_turn") }))
                }
            }
            "result" {
                $tc = $toolCalls[$s.toolCallId]
                $worker = $null
                if ($null -eq $tc) { $worker = New-HordeUnknown -Reason ("the call " + $s.toolCallId + " is not in this transcript, so whether it launched a worker cannot be told") }
                elseif (-not $tc.launchesWorker) { if (-not $notWorker.ContainsKey($tc.name)) { $notWorker[$tc.name] = New-HordeAbsent -Note ("a " + $tc.name + " result, not a worker's") }; $worker = $notWorker[$tc.name] }
                elseif ($links.byTool.ContainsKey($s.toolCallId)) { $worker = New-HordeKnown -Value $links.byTool[$s.toolCallId] }
                else { $worker = New-HordeUnknown -Reason ("no meta.json names the launching call " + $s.toolCallId) }
                [void]$records.Add((New-HordeTranscriptRecord -Kind "toolResult" -Role "tool" -Ts $s.ts -Line $s.line -Fields @{ toolCallId = $s.toolCallId; isError = $(if ($s.isError) { $errTrue } else { $errFalse }); chars = $s.chars; worker = $worker }))
            }
            "input" {
                $n = Get-ClaudeCodeNotification -Text $s.text
                if ($null -eq $n) {
                    [void]$records.Add((New-HordeTranscriptRecord -Kind "input" -Role "user" -Ts $s.ts -Line $s.line -Fields @{ source = "user"; chars = $s.text.Length; taskId = ""; toolCallId = ""; interim = $false; worker = $userAbsent }))
                    continue
                }
                $worker = $null
                $tc = $null
                if ($n.toolCallId -ne "") { $tc = $toolCalls[$n.toolCallId] }
                if ($n.taskId -ne "" -and $links.agents.Contains($n.taskId)) { $worker = New-HordeKnown -Value $n.taskId }
                elseif ($null -ne $tc -and $tc.launchesWorker -and $n.taskId -ne "") { $worker = New-HordeKnown -Value $n.taskId }
                elseif ($null -ne $tc -and -not $tc.launchesWorker) { $worker = New-HordeAbsent -Note ("about a " + $tc.name + " call, not a worker") }
                else { $worker = New-HordeUnknown -Reason ("task " + $n.taskId + " and call " + $n.toolCallId + " resolve to nothing in this transcript or its subagents folder") }
                [void]$records.Add((New-HordeTranscriptRecord -Kind "input" -Role "user" -Ts $s.ts -Line $s.line -Fields @{ source = "notification"; chars = $s.text.Length; taskId = $n.taskId; toolCallId = $n.toolCallId; interim = [bool]$n.interim; worker = $worker }))
            }
        }
    }
    $sessionId = $st.sessionId
    if ($sessionId -eq "") { $sessionId = [System.IO.Path]::GetFileNameWithoutExtension($Path) }
    return [pscustomobject]@{ records = $records.ToArray(); parseSkipped = $parsed.parseSkipped; tornTail = $parsed.tornTail; sessionId = $sessionId }
}

Register-HordeTranscriptAdapter -Name "claude-code" -Claim { param($p) Test-ClaudeCodeTranscript -Path $p } -Read { param($p) Read-ClaudeCodeTranscript -Path $p } -StoreRoots { Get-ClaudeCodeStoreRoots }
