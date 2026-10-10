# agents/claude-code/test/ConversationLines.ps1 - SYNTHETIC transcript lines, for the conversation suites.
#
# WHY A GENERATOR. No transcript is ever copied into the repository: a real one holds a founder's words
# and a Thrall's work. So every line the conversation suites read is made here, with made-up values, in
# the SHAPES measured on the live Thrall transcript on 2026-10-10 by a probe that printed property names
# and counts, never values: which keys each kind of line carries, that the JSON is compact, that one
# assistant line holds one content block, and that bookkeeping lines carry no uuid. The words come from
# the suite that calls this; nothing here is taken from a real file.
#
# New-ClaudeCodeLine -Kind <kind> returns one line of compact JSON (no line end). Kinds:
#   human, human-blocks          a person's prompt (origin.kind human), as a string or as text blocks
#   assistant-text               one text block of a response (message.id groups a response's lines)
#   assistant-texts              one line holding several text blocks (-Texts)
#   thinking, tool-use           other blocks of a response: not turns
#   tool-result                  a tool's output, as a user line: not a turn
#   notification                 a task notification (origin.kind task-notification): not a turn
#   meta                         a meta line (isMeta): not a turn
#   compact-summary              a compaction summary (isCompactSummary): not a turn
#   interrupt                    an interruption marker (text blocks, no origin): not a turn
#   synthetic                    the harness reporting an API error (model "<synthetic>"): a system turn
#   sidechain-human, sidechain-text   a side conversation's lines (isSidechain): never turns
#   turn-duration, compact-boundary, attachment, last-prompt, mode, file-history-snapshot  bookkeeping

function New-ClaudeCodeSyntheticId { return [guid]::NewGuid().ToString() }

function ConvertTo-ClaudeCodeJsonLine {
    # Compact JSON, as the harness writes it. ConvertTo-Json is told the depth, so nested content is kept.
    param($Value)
    return ($Value | ConvertTo-Json -Compress -Depth 12)
}

function New-ClaudeCodeLine {
    param(
        [Parameter(Mandatory = $true)][string]$Kind,
        [string]$Session = "00000000-0000-4000-8000-000000000000",
        [string]$Text = "synthetic words",
        [string[]]$Texts = @(),
        [string]$MessageId = "",
        [string]$Uuid = "",
        [string]$Time = ""
    )
    if ($Uuid -eq "") { $Uuid = New-ClaudeCodeSyntheticId }
    if ($Time -eq "") { $Time = [datetime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ") }
    if ($MessageId -eq "") { $MessageId = "msg_synthetic" + [guid]::NewGuid().ToString("N").Substring(0, 16) }
    $common = [ordered]@{ parentUuid = (New-ClaudeCodeSyntheticId); isSidechain = $false; userType = "external"; entrypoint = "cli"; cwd = "C:\work\synthetic"; sessionId = $Session; version = "2.1.287"; gitBranch = "main" }
    function Merge { param($A, $B) $o = [ordered]@{}; foreach ($k in $A.Keys) { $o[$k] = $A[$k] }; foreach ($k in $B.Keys) { $o[$k] = $B[$k] }; return $o }
    function Assistant { param($Content, [string]$Model = "synthetic-model-1")
        return (Merge $common ([ordered]@{ message = [ordered]@{ model = $Model; id = $MessageId; type = "message"; role = "assistant"; content = @($Content); stop_reason = $null; usage = [ordered]@{ input_tokens = 3; output_tokens = 5 } }; requestId = ("req_synthetic" + [guid]::NewGuid().ToString("N").Substring(0, 12)); type = "assistant"; uuid = $Uuid; timestamp = $Time })) }
    switch ($Kind) {
        "human" { $v = Merge $common ([ordered]@{ promptId = (New-ClaudeCodeSyntheticId); type = "user"; message = [ordered]@{ role = "user"; content = $Text }; uuid = $Uuid; timestamp = $Time; permissionMode = "bypassPermissions"; origin = [ordered]@{ kind = "human" }; promptSource = "typed"; turnOrigin = "user"; turnPosition = 0 }) }
        "human-blocks" { $v = Merge $common ([ordered]@{ promptId = (New-ClaudeCodeSyntheticId); type = "user"; message = [ordered]@{ role = "user"; content = @(@($Texts) | ForEach-Object { [ordered]@{ type = "text"; text = $_ } }) }; uuid = $Uuid; timestamp = $Time; origin = [ordered]@{ kind = "human" } }) }
        "assistant-text" { $v = Assistant @([ordered]@{ type = "text"; text = $Text }) }
        "assistant-texts" { $v = Assistant @(@($Texts) | ForEach-Object { [ordered]@{ type = "text"; text = $_ } }) }
        "thinking" { $v = Assistant @([ordered]@{ type = "thinking"; thinking = "synthetic reasoning that is never a turn"; signature = "c3ludGhldGlj" }) }
        "tool-use" { $v = Assistant @([ordered]@{ type = "tool_use"; id = ("toolu_synthetic" + [guid]::NewGuid().ToString("N").Substring(0, 10)); name = "Bash"; input = [ordered]@{ command = "echo synthetic tool input"; description = "a synthetic call" } }) }
        "tool-result" { $v = Merge $common ([ordered]@{ type = "user"; message = [ordered]@{ role = "user"; content = @([ordered]@{ tool_use_id = "toolu_synthetic"; type = "tool_result"; content = "synthetic tool output, never a turn" }) }; uuid = $Uuid; timestamp = $Time; toolUseResult = [ordered]@{ stdout = "synthetic tool output" } }) }
        "notification" { $v = Merge $common ([ordered]@{ type = "user"; message = [ordered]@{ role = "user"; content = "<task-notification><task-id>synthetic</task-id></task-notification>" }; uuid = $Uuid; timestamp = $Time; origin = [ordered]@{ kind = "task-notification" } }) }
        "meta" { $v = Merge $common ([ordered]@{ type = "user"; message = [ordered]@{ role = "user"; content = "<command-name>/synthetic</command-name>" }; isMeta = $true; uuid = $Uuid; timestamp = $Time }) }
        "compact-summary" { $v = Merge $common ([ordered]@{ type = "user"; message = [ordered]@{ role = "user"; content = "This session is being continued from a synthetic summary." }; isCompactSummary = $true; isVisibleInTranscriptOnly = $true; uuid = $Uuid; timestamp = $Time }) }
        "interrupt" { $v = Merge $common ([ordered]@{ type = "user"; message = [ordered]@{ role = "user"; content = @([ordered]@{ type = "text"; text = "[Request interrupted by user]" }) }; uuid = $Uuid; timestamp = $Time }) }
        "synthetic" { $v = Assistant @([ordered]@{ type = "text"; text = $Text }) "<synthetic>"; $v["isApiErrorMessage"] = $true }
        "sidechain-human" { $v = Merge $common ([ordered]@{ type = "user"; message = [ordered]@{ role = "user"; content = $Text }; uuid = $Uuid; timestamp = $Time; origin = [ordered]@{ kind = "human" } }); $v["isSidechain"] = $true }
        "sidechain-text" { $v = Assistant @([ordered]@{ type = "text"; text = $Text }); $v["isSidechain"] = $true }
        "turn-duration" { $v = Merge $common ([ordered]@{ type = "system"; subtype = "turn_duration"; durationMs = 1234; uuid = $Uuid; timestamp = $Time }) }
        "compact-boundary" { $v = Merge $common ([ordered]@{ type = "system"; subtype = "compact_boundary"; content = "Conversation compacted"; uuid = $Uuid; timestamp = $Time }) }
        "attachment" { $v = Merge $common ([ordered]@{ type = "attachment"; attachment = [ordered]@{ type = "synthetic"; content = "an attachment's words are never a turn" }; uuid = $Uuid; timestamp = $Time }) }
        "last-prompt" { $v = [ordered]@{ type = "last-prompt"; lastPrompt = "a synthetic last prompt"; sessionId = $Session } }
        "mode" { $v = [ordered]@{ type = "mode"; mode = "normal"; sessionId = $Session } }
        "file-history-snapshot" { $v = [ordered]@{ type = "file-history-snapshot"; messageId = (New-ClaudeCodeSyntheticId); snapshot = [ordered]@{ trackedFileBackups = [ordered]@{} }; isSnapshotUpdate = $false } }
        default { throw ("not a synthetic line kind: " + $Kind) }
    }
    return (ConvertTo-ClaudeCodeJsonLine $v)
}

function New-ClaudeCodeNoise {
    # The harness's own lines that sit around a turn and must never become one: one of each kind.
    param([string]$Session)
    return @(
        (New-ClaudeCodeLine -Kind "thinking" -Session $Session),
        (New-ClaudeCodeLine -Kind "tool-use" -Session $Session),
        (New-ClaudeCodeLine -Kind "tool-result" -Session $Session),
        (New-ClaudeCodeLine -Kind "attachment" -Session $Session),
        (New-ClaudeCodeLine -Kind "notification" -Session $Session),
        (New-ClaudeCodeLine -Kind "meta" -Session $Session),
        (New-ClaudeCodeLine -Kind "interrupt" -Session $Session),
        (New-ClaudeCodeLine -Kind "sidechain-human" -Session $Session -Text "a side conversation's prompt"),
        (New-ClaudeCodeLine -Kind "sidechain-text" -Session $Session -Text "a side conversation's reply"),
        (New-ClaudeCodeLine -Kind "turn-duration" -Session $Session),
        (New-ClaudeCodeLine -Kind "last-prompt" -Session $Session),
        (New-ClaudeCodeLine -Kind "file-history-snapshot" -Session $Session)
    )
}

function Add-ClaudeCodeLines {
    # Append lines, each with its line end, to a transcript in UTF-8 without a byte order mark.
    param([string]$Path, [string[]]$Lines)
    $enc = New-Object System.Text.UTF8Encoding $false
    $sb = New-Object System.Text.StringBuilder
    foreach ($l in $Lines) { [void]$sb.Append($l); [void]$sb.Append("`n") }
    [System.IO.File]::AppendAllText($Path, $sb.ToString(), $enc)
}

function New-ClaudeCodeRegistry {
    # A fleet registry in a new temp folder: { root; projects }. Nothing outside it is written.
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-cc-conv-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
    [void][System.IO.Directory]::CreateDirectory((Join-Path $dir "registry\sessions"))
    [void][System.IO.Directory]::CreateDirectory((Join-Path $dir "projects\C--work-synthetic"))
    return [pscustomobject]@{ root = $dir; projects = (Join-Path $dir "projects\C--work-synthetic") }
}

function Set-ClaudeCodeRecord {
    # Write one session's registry record, in the fields the fleet's registry writes (88 records measured
    # 2026-10-10: claudeSessionId, cwd, firstSeen, lastSeen, pane, instance, role, transcriptPath, ...).
    param($Registry, [string]$Session, [string]$Role = "master", [bool]$Retired = $false, [string]$TranscriptPath = "")
    if ($TranscriptPath -eq "") { $TranscriptPath = Join-Path $Registry.projects ($Session + ".jsonl") }
    $r = [ordered]@{ claudeSessionId = $Session; origin = "user"; fleetSessionId = ""; pane = "10"; instance = "inst-synthetic"; cwd = "C:\work\synthetic"; firstCwd = "C:\work\synthetic"; owner = ""
        firstSeen = "2026-10-10T10:00:00.0000000Z"; lastSeen = "2026-10-10T11:00:00.0000000Z"; lastTool = "Bash"; transcriptPath = $TranscriptPath }
    if ($Role -ne "") { $r["role"] = $Role }
    if ($Retired) { $r["retired"] = $true; $r["retiredAt"] = "2026-10-10T11:30:00.0000000Z" }
    [System.IO.File]::WriteAllText((Join-Path $Registry.root ("registry\sessions\" + $Session + ".json")), ($r | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding $false))
    return $TranscriptPath
}

function Remove-ClaudeCodeRegistry {
    # Removes the folder New-ClaudeCodeRegistry made, and nothing else.
    param($Registry)
    if ($Registry.root -like "*horde-cc-conv-*" -and [System.IO.Directory]::Exists($Registry.root)) { Remove-Item -LiteralPath $Registry.root -Recurse -Force }
}
