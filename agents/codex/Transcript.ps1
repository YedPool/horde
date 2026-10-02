# agents/codex/Transcript - the transcript adapter for Codex rollout files.
#
# WHAT IT READS. <CODEX_HOME or ~/.codex>/sessions/YYYY/MM/DD/rollout-<local time>-<uuid>.jsonl, one
# { timestamp, ordinal, type, payload } object per line (metrics design 2.5; the rollout measurement of
# 2026-09-30, Codex CLI 0.159.2 and 0.159.3, cited below as "the measurement"). It turns a rollout into
# core/Transcript.ps1 records and nothing else.
#
# THE RULES, each one a test in agents/codex/test/test-transcript.ps1:
#   - ONE CALL PER MODEL RESPONSE, from token_usage_record lines (response_id, usage). The measurement
#     found them after every response; event_msg token_count lines are fewer - an interrupted turn's
#     response had a token_usage_record and no token_count (measured 2026-10-01 on the 0.159.3 rollout
#     01a0f4cf: 6 against 5, and the six usages sum exactly to the final cumulative total). A rollout
#     with no token_usage_record (0.159.2) falls back to token_count, one call per change in its
#     cumulative total, using last_token_usage.
#   - input_tokens INCLUDES cached_input_tokens on this harness (experiment program 12.2), so the
#     uncached input the port wants is input minus cached. The harness does not split cache writes by
#     lifetime: that split is absent, not unknown.
#   - The cumulative total (thread_token_usage, or token_count's total_token_usage) is kept as a
#     usageTotal record, never summed; the summary shows it beside the per-call sum as a control.
#   - The MODEL is per turn, from turn_context (the measurement: no model on any message), and a call
#     takes the model of its turn_id.
#   - TOOL CALLS are response_item lines whose payload type ends in _call, paired with the _call_output
#     line of the same call_id. They belong to the next response of the same turn, because the items
#     of a response are written before its usage line (the measurement, run B).
#   - TURN ENDS are task_complete and turn_aborted (the measurement: an interrupt writes turn_aborted
#     and no task_complete; a failed turn writes task_complete with an error). duration_ms is kept.
#   - USER INPUT is event_msg item_completed of a UserMessage, not the response_item user message:
#     after compaction the harness re-emits earlier context as response_items, which are not new input
#     (the measurement, run A ordinals 55-57).
#   - The text of a message is measured and dropped: assistant text length from response_item
#     messages with role assistant, user text length from the UserMessage item.
#
# READ BY ALLOWLIST (design section 8): session_meta is read for its id only - base_instructions is
# never looked at - and every other field of every line is dropped in memory.
#
# No Set-StrictMode here: dot-sourced (see core/Tristate.ps1). Needs core/Tristate.ps1,
# core/ReadShared.ps1 and core/Transcript.ps1.

function Test-CodexTranscript {
    # Is this a rollout? A .jsonl whose first parseable line has timestamp, type and payload, and whose
    # first line is a session_meta (the measurement: line 0 is always session_meta).
    param([string]$Path)
    if ([System.IO.Path]::GetExtension($Path) -ine ".jsonl" -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    Add-Type -AssemblyName System.Web.Extensions
    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $ser.MaxJsonLength = [int]::MaxValue
    $stream = Open-HordeSharedStream -Path $Path
    try {
        $reader = New-Object System.IO.StreamReader($stream)
        try {
            while ($null -ne ($text = $reader.ReadLine())) {
                if ($text.Trim() -eq "") { continue }
                $v = $null
                try { $v = $ser.DeserializeObject($text) } catch { return $false }
                if ($v -isnot [System.Collections.IDictionary]) { return $false }
                return ($v.ContainsKey("payload") -and $v.ContainsKey("timestamp") -and $v["type"] -eq "session_meta")
            }
        } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
    return $false
}

function Get-CodexUsage {
    # The port's usage answer from a usage object of this harness.
    param($U)
    if ($U -isnot [System.Collections.IDictionary]) { return (New-HordeUnknown -Reason "the line carries no usage") }
    # A field the line does not give is unknown, never a known 0 (review of PR #50, F5).
    foreach ($k in @("input_tokens", "cached_input_tokens", "cache_write_input_tokens", "output_tokens")) {
        if ($null -eq $U[$k]) { return (New-HordeUnknown -Reason ("the usage has no " + $k)) }
    }
    $num = { param($v) if ($null -eq $v) { [long]0 } else { [long]$v } }
    $inTok = & $num $U["input_tokens"]
    $cached = & $num $U["cached_input_tokens"]
    if ($cached -gt $inTok) { return (New-HordeUnknown -Reason ("cached input (" + $cached + ") exceeds input (" + $inTok + "), so the uncached part cannot be told")) }
    return (New-HordeUsage -Uncached ($inTok - $cached) -CacheRead $cached -CacheWrite (& $num $U["cache_write_input_tokens"]) -Output (& $num $U["output_tokens"]) -Split (New-HordeAbsent -Note "this harness does not split cache writes by lifetime"))
}

function Get-CodexContentChars {
    # The characters of the text parts of a message's content list.
    param($Content)
    $n = 0
    foreach ($c in @($Content)) {
        if ($c -is [System.Collections.IDictionary] -and $c["text"] -is [string]) { $n += $c["text"].Length }
    }
    return $n
}

function Read-CodexTranscript {
    # The port's records for one rollout, handed to $Sink.Add in file order; returns
    # { records; parseSkipped; tornTail; sessionId }, records empty when a sink was given.
    #
    # ONE FACT IS NEEDED BEFORE THE FIRST RECORD: whether the rollout has any token_usage_record, which
    # decides whether its token_count lines are calls. M1 held every record until the end to know it
    # (plan step M2 must not), so a first read looks for one and stops at the first it finds - early in
    # every rollout that has them. When it reads to the end without finding one, the second read stops
    # where it did (Read-HordeJsonLines -Upto), so a rollout still being written gives one snapshot.
    param([string]$Path, $Sink = $null)
    $kept = $null
    if ($null -eq $Sink) { $kept = New-Object System.Collections.ArrayList; $Sink = $kept }
    # When there is none, M1 priced each token_count call with the model its turn had at the END of the
    # file; that read is this one, so it keeps the same map.
    $look = @{ stop = $false; turn = "" }
    $finalModel = @{}
    $scan = Read-HordeJsonLines -Path $Path -Control $look -Each {
        param($ln, $v)
        if ($null -eq (ConvertTo-HordeUtcTime $v["timestamp"])) { return }
        $type = "$($v["type"])"
        if ($type -eq "token_usage_record") { $look.stop = $true; return }
        $p = $v["payload"]
        if ($p -isnot [System.Collections.IDictionary]) { $p = @{} }
        $turn = "$($p["turn_id"])"
        if ($turn -ne "" -and ("$($p["type"])" -eq "task_started" -or $type -eq "turn_context")) { $look.turn = $turn }
        if ($turn -eq "") { $turn = $look.turn }
        if ($type -eq "turn_context" -and $turn -ne "" -and $p["model"] -is [string]) { $finalModel[$turn] = $p["model"] }
    }
    $sawRecord = $scan.stopped
    $upto = $null
    if (-not $sawRecord) { $upto = $scan }

    $st = @{ sessionId = ""; turn = ""; prevTotal = "" }
    $turnModel = @{}
    # Items waiting for the response they belong to: how many tool calls, and the assistant text, per turn.
    $pendingTools = @{}
    $pendingText = @{}
    $userAbsent = New-HordeAbsent -Note "a user message"
    $notWorker = New-HordeAbsent -Note "this harness's tools do not launch workers that Horde can see"
    $errorUnsaid = New-HordeUnknown -Reason "the output line does not say whether the tool failed"

    # STREAMED one line at a time (core/Transcript.ps1, Read-HordeJsonLines -Each); "return" moves to
    # the next line.
    $parsed = Read-HordeJsonLines -Path $Path -Upto $upto -Each {
        param($ln, $v)
        $ts = ConvertTo-HordeUtcTime $v["timestamp"]
        if ($null -eq $ts) { return }
        $type = "$($v["type"])"
        $p = $v["payload"]
        if ($p -isnot [System.Collections.IDictionary]) { $p = @{} }
        $ptype = "$($p["type"])"
        # response_item lines carry no turn_id (measured on the 0.159.3 rollouts: their payload keys are
        # type, id, name, arguments, call_id), so they belong to the turn most recently started.
        $turn = "$($p["turn_id"])"
        if ($turn -ne "" -and ($ptype -eq "task_started" -or $type -eq "turn_context")) { $st.turn = $turn }
        if ($turn -eq "") { $turn = $st.turn }

        if ($type -eq "session_meta") {
            if ($st.sessionId -eq "" -and $p["id"] -is [string]) { $st.sessionId = $p["id"] }
            $Sink.Add((New-HordeTranscriptRecord -Kind "event" -Role "system" -Ts $ts -Line $ln))
            return
        }
        if ($type -eq "turn_context") {
            if ($turn -ne "" -and $p["model"] -is [string]) { $turnModel[$turn] = $p["model"] }
            $Sink.Add((New-HordeTranscriptRecord -Kind "event" -Role "system" -Ts $ts -Line $ln))
            return
        }
        if ($type -eq "token_usage_record") {
            $id = "$($p["response_id"])"
            if ($id -eq "") { $id = "line-" + $ln }
            $model = New-HordeUnknown -Reason ("no turn_context names the model of turn " + $turn)
            if ($turnModel.ContainsKey($turn)) { $model = New-HordeKnown -Value $turnModel[$turn] }
            $tools = 0; if ($pendingTools.ContainsKey($turn)) { $tools = $pendingTools[$turn]; $pendingTools.Remove($turn) }
            $chars = 0; if ($pendingText.ContainsKey($turn)) { $chars = $pendingText[$turn]; $pendingText.Remove($turn) }
            $Sink.Add((New-HordeTranscriptRecord -Kind "call" -Role "assistant" -Ts $ts -Line $ln -Fields @{
                id = $id; model = $model; usage = (Get-CodexUsage $p["usage"]); textChars = $chars; toolCallCount = $tools; speed = ""; inferenceGeo = "" }))
            if ($p["thread_token_usage"] -is [System.Collections.IDictionary]) {
                $Sink.Add((New-HordeTranscriptRecord -Kind "usageTotal" -Role "system" -Ts $ts -Line $ln -Fields @{ usage = (Get-CodexUsage $p["thread_token_usage"]) }))
            }
            return
        }
        if ($type -eq "event_msg" -and $ptype -eq "token_count") {
            # An event always; a call too only when the rollout has no token_usage_record at all.
            $Sink.Add((New-HordeTranscriptRecord -Kind "event" -Role "system" -Ts $ts -Line $ln))
            if ($sawRecord) { return }
            $info = $p["info"]
            $last = $null; $total = $null
            if ($info -is [System.Collections.IDictionary]) { $last = $info["last_token_usage"]; $total = $info["total_token_usage"] }
            # A token_count with no usage (info:null, a rate-limit-only event) is not a response (review of
            # PR #50, F8): made a call, its unknown usage made the whole rollout's tokens unknown.
            if ($last -isnot [System.Collections.IDictionary]) { return }
            # 0.159.2: no token_usage_record. One call per change in the cumulative total; a token_count
            # whose total did not move is a repeat of the last one, not a new response.
            $key = ""
            if ($total -is [System.Collections.IDictionary]) { $key = "" + $total["total_tokens"] + "/" + $total["input_tokens"] + "/" + $total["output_tokens"] }
            if ($key -ne "" -and $key -eq $st.prevTotal) { return }
            $st.prevTotal = $key
            $model = New-HordeUnknown -Reason ("no turn_context names the model of turn " + $turn)
            if ($finalModel.ContainsKey($turn)) { $model = New-HordeKnown -Value $finalModel[$turn] }
            $Sink.Add((New-HordeTranscriptRecord -Kind "call" -Role "assistant" -Ts $ts -Line $ln -Fields @{
                id = ("token-count-" + $ln); model = $model; usage = (Get-CodexUsage $last); textChars = 0; toolCallCount = 0; speed = ""; inferenceGeo = "" }))
            if ($total -is [System.Collections.IDictionary]) { $Sink.Add((New-HordeTranscriptRecord -Kind "usageTotal" -Role "system" -Ts $ts -Line $ln -Fields @{ usage = (Get-CodexUsage $total) })) }
            return
        }
        if ($type -eq "event_msg" -and ($ptype -eq "task_complete" -or $ptype -eq "turn_aborted")) {
            $dur = New-HordeUnknown -Reason ("the " + $ptype + " line has no duration_ms")
            if ($null -ne $p["duration_ms"]) { $dur = New-HordeKnown -Value ([long]$p["duration_ms"]) }
            $Sink.Add((New-HordeTranscriptRecord -Kind "turnEnd" -Role "system" -Ts $ts -Line $ln -Fields @{ durationMs = $dur }))
            return
        }
        if ($type -eq "event_msg" -and $ptype -eq "item_completed" -and $p["item"] -is [System.Collections.IDictionary] -and $p["item"]["type"] -eq "UserMessage") {
            $Sink.Add((New-HordeTranscriptRecord -Kind "input" -Role "user" -Ts $ts -Line $ln -Fields @{ source = "user"; chars = (Get-CodexContentChars $p["item"]["content"]); taskId = ""; toolCallId = ""; interim = $false; worker = $userAbsent }))
            return
        }
        if ($type -eq "compacted") {
            $Sink.Add((New-HordeTranscriptRecord -Kind "compaction" -Role "system" -Ts $ts -Line $ln))
            return
        }
        if ($type -eq "response_item") {
            if ($ptype -like "*_call" -and "$($p["call_id"])" -ne "") {
                if (-not $pendingTools.ContainsKey($turn)) { $pendingTools[$turn] = 0 }
                $pendingTools[$turn]++
                $Sink.Add((New-HordeTranscriptRecord -Kind "toolCall" -Role "assistant" -Ts $ts -Line $ln -Fields @{ id = "$($p["call_id"])"; name = "$($p["name"])"; callId = ""; launchesWorker = $false }))
                return
            }
            if ($ptype -like "*_call_output" -and "$($p["call_id"])" -ne "") {
                $o = $p["output"]
                $chars = 0
                if ($o -is [string]) { $chars = $o.Length } else { $chars = Get-CodexContentChars $o }
                $Sink.Add((New-HordeTranscriptRecord -Kind "toolResult" -Role "tool" -Ts $ts -Line $ln -Fields @{ toolCallId = "$($p["call_id"])"; isError = $errorUnsaid; chars = $chars; worker = $notWorker }))
                return
            }
            if ($ptype -eq "message" -and $p["role"] -eq "assistant") {
                if (-not $pendingText.ContainsKey($turn)) { $pendingText[$turn] = 0 }
                $pendingText[$turn] += (Get-CodexContentChars $p["content"])
            }
        }
        $Sink.Add((New-HordeTranscriptRecord -Kind "event" -Role "system" -Ts $ts -Line $ln))
    }
    $sessionId = $st.sessionId
    if ($sessionId -eq "") { $sessionId = [System.IO.Path]::GetFileNameWithoutExtension($Path) }
    $records = @(); if ($null -ne $kept) { $records = $kept.ToArray() }
    return [pscustomobject]@{ records = $records; parseSkipped = $parsed.parseSkipped; tornTail = $parsed.tornTail; sessionId = $sessionId }
}

Register-HordeTranscriptAdapter -Name "codex" -Claim { param($p) Test-CodexTranscript -Path $p } -Read { param($p, $s) Read-CodexTranscript -Path $p -Sink $s }
