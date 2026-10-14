# agents/claude-code/Launch.ps1 - how this harness is started, and how Horde reads back what started.
#
# The claude-code half of the launch port (core/AgentLaunch.ps1; remote plan R9, engines E9, issue
# #67). Everything here names this harness's flags, files or modes, so it lives in this folder
# (CONTRIBUTING 14). Nothing here starts a process: the host layer runs the argv this file builds.
#
# THE ARGV, every flag read off --help 2.1.287 (agent.json cites each):
#   --session-id <uuid>        the node chooses the id, so it can find the session afterwards
#   --add-dir <folder>         once per folder the session is granted beyond its working folder: the
#                              folder its prompt file is put in. Read 2026-10-06 from the 2.1.289
#                              program's own option table: "--add-dir <directories...>", "Additional
#                              directories to allow tool access to". It takes several values, so it is
#                              placed right after --session-id, where the next item is a flag.
#   <permission fragment>      from agent.json permissionLevels, through Get-HordePermissionArgs
#   --model <id>               only when the resolution pinned one; otherwise the harness's own choice
#   -n <name> --remote-control <name>
#                              the name in the prompt box and terminal title, and the Remote Control
#                              session's web title. --remote-control takes an OPTIONAL value, so the
#                              name always follows it at once: a bare flag in front of the prompt
#                              would take the prompt as the name (engines E9). No name, neither flag.
#   <prompt>                   last, as one argument. A prompt starting with '-' would be read as a
#                              flag, so it is refused rather than guessed about.
#
# THE READBACK (issue #67, item 2; decision 6 of 2026-10-05, fail closed). MEASURED 2026-10-05 on
# 2.1.289, interactive sessions in an isolated terminal, one per level: the transcript's first lines
# include {"type":"permission-mode","permissionMode":<mode>,"sessionId":<id>}, written at start
# before the first turn and again on each turn, and the four levels read back as plan, default,
# acceptEdits and bypassPermissions. The same transcript carries {"type":"bridge-session",
# "bridgeSessionId":...} once Remote Control is up, and the session's control file
# (<config>/sessions/<pid>.json, store X2) carries pid, procStart and name.
#
# WHERE THE HARNESS KEEPS THEM: CLAUDE_CONFIG_DIR, else .claude in the user's profile (stores.json).
# The caller passes the environment the HARNESS sees (a hashtable), never this process's own, because
# a pane does not inherit the environment of the process that starts it (measured 2026-10-05: a
# variable set in the process that started the terminal was absent inside its panes).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

$script:ClaudeCodeProgram = "claude"
# This harness's names for its modes, mapped to Horde's levels. The descriptor's readback evidence
# names the same four; agents/claude-code/test/test-launch.ps1 checks they agree.
$script:ClaudeCodeModeLevels = @{ "plan" = "plan"; "default" = "ask"; "acceptEdits" = "edits"; "bypassPermissions" = "bypass" }
# The longest prompt passed in argv. Windows caps a whole command line at 32767 characters; the rest
# of the argv is under 400, and the host's own wrapper takes some. A longer first prompt is refused
# here, never cut, and is delivered as a message once the session runs.
$script:ClaudeCodePromptMax = 16000
# What ends a session gracefully: the /exit command, then Enter, typed as two keystroke runs. MEASURED
# 2026-10-05 (2.1.289, interactive, isolated terminal): in three sessions at their prompt the pane
# closed after it; in a fourth showing a first-run dialog it did not, so a caller proves the end by
# pid and start time and ends the pane itself when it has not come.
$script:ClaudeCodeCloseText = @("/exit", "`r")

function Get-ClaudeCodeConfigDir {
    # The harness's folder for a given environment view: CLAUDE_CONFIG_DIR when set, else the profile's
    # .claude. -Environment is a hashtable of the variables the harness will see.
    param([Parameter(Mandatory = $true)][hashtable]$Environment)
    $set = "" + $Environment["CLAUDE_CONFIG_DIR"]
    if ($set.Trim() -ne "") { return $set.Trim() }
    return (Join-Path ("" + $Environment["USERPROFILE"]) ".claude")
}

function New-ClaudeCodeArgv {
    # The argv for one start, as an answer. -Spec: { sessionId; permissionArgs; model; name; prompt; addDirs }.
    param([Parameter(Mandatory = $true)]$Spec)
    $argv = New-Object System.Collections.Generic.List[string]
    $argv.Add("--session-id"); $argv.Add("" + $Spec.sessionId)
    foreach ($dir in @($Spec.addDirs)) {
        if ($null -eq $dir -or "" + $dir -eq "") { continue }
        if (("" + $dir).StartsWith("-")) { return (New-HordeUnknown -Reason ("the folder '" + $dir + "' starts with '-', which the harness would read as a flag")) }
        $argv.Add("--add-dir"); $argv.Add("" + $dir)
    }
    foreach ($p in @($Spec.permissionArgs)) { if ($null -ne $p) { $argv.Add("" + $p) } }
    if ($null -ne $Spec.model -and "" + $Spec.model -ne "") {
        if (("" + $Spec.model).StartsWith("-")) { return (New-HordeUnknown -Reason ("the model '" + $Spec.model + "' starts with '-', which the harness would read as a flag")) }
        $argv.Add("--model"); $argv.Add("" + $Spec.model)
    }
    $name = "" + $Spec.name
    if ($name -ne "") {
        if ($name.StartsWith("-")) { return (New-HordeUnknown -Reason ("the session name '" + $name + "' starts with '-', which the harness would read as a flag")) }
        $argv.Add("-n"); $argv.Add($name); $argv.Add("--remote-control"); $argv.Add($name)
    }
    $prompt = "" + $Spec.prompt
    if ($prompt -ne "") {
        if ($prompt.StartsWith("-")) { return (New-HordeUnknown -Reason "the first prompt starts with '-', which the harness would read as a flag; send it as a message once the session runs") }
        if ($prompt.Length -gt $script:ClaudeCodePromptMax) { return (New-HordeUnknown -Reason ("the first prompt is " + $prompt.Length + " characters, over the " + $script:ClaudeCodePromptMax + " a command line can carry; send it as a message once the session runs")) }
        if ($prompt -cmatch '[\x00-\x08\x0B-\x1F\x7F]') { return (New-HordeUnknown -Reason "the first prompt holds a control character other than a line break or tab") }
        $argv.Add($prompt)
    }
    return (New-HordeKnown -Value $argv.ToArray())
}

function Find-ClaudeCodeTranscript {
    # The transcript of one session: <config>\projects\<folder>\<id>.jsonl, as an answer. The folder is
    # the harness's own spelling of the working directory, so it is found, never computed.
    param([Parameter(Mandatory = $true)][string]$ConfigDir, [Parameter(Mandatory = $true)][string]$SessionId)
    $projects = Join-Path $ConfigDir "projects"
    if (-not (Test-Path -LiteralPath $projects -PathType Container)) { return (New-HordeAbsent -Note ("there is no projects folder under " + $ConfigDir)) }
    $hits = @(Get-ChildItem -LiteralPath $projects -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName ($SessionId + ".jsonl") } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if ($hits.Count -eq 0) { return (New-HordeAbsent -Note ("no transcript of " + $SessionId + " yet")) }
    if ($hits.Count -gt 1) { return (New-HordeUnknown -Reason ("" + $hits.Count + " transcripts are named " + $SessionId + ", so which one is this session's cannot be told")) }
    return (New-HordeKnown -Value $hits[0])
}

function Read-ClaudeCodeModeText {
    # The level a transcript's text says the session is in now: its LAST permission-mode line for this
    # session id, mapped to a Horde level. Unknown for a mode this file does not map; absent when the
    # text has no such line.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text, [Parameter(Mandatory = $true)][string]$SessionId)
    $last = $null
    foreach ($line in ($Text -split "`n")) {
        if ($line -cnotmatch '"type"\s*:\s*"permission-mode"') { continue }
        if ($line -cnotmatch ('"sessionId"\s*:\s*"' + [regex]::Escape($SessionId) + '"')) { continue }
        $m = [regex]::Match($line, '"permissionMode"\s*:\s*"([A-Za-z]+)"')
        if ($m.Success) { $last = $m.Groups[1].Value }
    }
    if ($null -eq $last) { return (New-HordeAbsent -Note "the transcript has no permission-mode line for this session yet") }
    if (-not $script:ClaudeCodeModeLevels.ContainsKey($last) -or -not ($script:ClaudeCodeModeLevels.Keys -ccontains $last)) { return (New-HordeUnknown -Reason ("the session reports the mode '" + $last + "', which Horde does not map to a level")) }
    return (New-HordeKnown -Value $script:ClaudeCodeModeLevels[$last])
}

function Read-ClaudeCodeMode {
    # The level a running session reports, read from its transcript, as an answer.
    param([Parameter(Mandatory = $true)][string]$ConfigDir, [Parameter(Mandatory = $true)][string]$SessionId)
    $t = Find-ClaudeCodeTranscript -ConfigDir $ConfigDir -SessionId $SessionId
    if ($t.state -ne "known") { return $t }
    $text = $null
    try { $text = Read-HordeSharedText -Path $t.value } catch { return (New-HordeUnknown -Reason ("the transcript could not be read: " + $_.Exception.Message)) }
    return (Read-ClaudeCodeModeText -Text $text -SessionId $SessionId)
}

# THE TURN RECEIPT (issue #214). A line the host typed is taken only once the transcript holds a NEW
# row that submits it, for this session id:
#   - a "type":"user" row, not one of the harness's own (isMeta) and not a side chain's (isSidechain),
#     whose message text - a string, or its text blocks joined - equals the line after trimming; or
#   - a "type":"attachment" row whose attachment is a queued_command a person typed (origin.kind
#     "human", commandMode "prompt" or none) whose prompt equals the line: the harness's record of a
#     line typed while a turn runs and handed to it inside that turn (Transcript.ps1 reads the same
#     shape; review of PR 239, M1).
# Equal, not "contains": a tool result or a later turn that quotes the line is not it. A queue-operation
# "enqueue" row is NOT a receipt: MEASURED 2026-10-14 on 2.1.299 (an isolated terminal; the PR 239 live
# check) a line typed during a turn was written as enqueue 0.3 s after its Enter, and became a user row
# only once the running turn ended, 0.6 s later; until then a person can still take a queued line back.
# The node waits for the running turn to end before it types the next line (Test-ClaudeCodeTurnDone), so
# a queued line is the exception, not the path.
# New means after the mark taken before typing: the transcript's size then, or 0 when it did not exist
# yet (a session's file can appear only with its first user line: cli/NodeAct.ps1, the no-op line).
# A file SHORTER than its mark is unknown: it is not the file the mark measured, and reading it from its
# start could take a turn typed before the mark for this one (review of PR 239, F's probe).
# Rows are parsed with the serializer Transcript.ps1 uses, which keeps keys that differ only in case
# apart, where ConvertFrom-Json on PowerShell 5.1 throws on them (F's probe, case H); a whole row that
# still cannot be parsed makes a "no" unknown, since the turn could be in it. MEASURED 2026-10-14 on
# 2.1.299: a typed line's user row was written 0.18 s to 0.53 s after its Enter.
function Get-ClaudeCodeTurnMark {
    # Before a line is typed: known { size } (0 when there is no transcript yet), unknown when which
    # transcript is this session's cannot be told.
    param([Parameter(Mandatory = $true)][string]$ConfigDir, [Parameter(Mandatory = $true)][string]$SessionId)
    $t = Find-ClaudeCodeTranscript -ConfigDir $ConfigDir -SessionId $SessionId
    if ($t.state -eq "absent") { return (New-HordeKnown -Value ([pscustomobject]@{ size = [long]0 })) }
    if ($t.state -ne "known") { return $t }
    try { return (New-HordeKnown -Value ([pscustomobject]@{ size = [long](Get-Item -LiteralPath $t.value -Force).Length })) }
    catch { return (New-HordeUnknown -Reason ("the transcript's size could not be read: " + $_.Exception.Message)) }
}

function Read-ClaudeCodeTextFrom {
    # The text of -Path from byte -Offset on, opened with sharing (core/ReadShared.ps1), as an answer:
    # unknown when the file is shorter than -Offset (see above).
    param([Parameter(Mandatory = $true)][string]$Path, [long]$Offset = 0)
    $stream = Open-HordeSharedStream -Path $Path
    try {
        if ($Offset -gt $stream.Length) { return (New-HordeUnknown -Reason ("the transcript is shorter (" + $stream.Length + " bytes) than when it was marked (" + $Offset + "), so it is not the file the mark measured")) }
        [void]$stream.Seek($Offset, [System.IO.SeekOrigin]::Begin)
        $reader = New-Object System.IO.StreamReader($stream, (New-Object System.Text.UTF8Encoding($false)))
        try { return (New-HordeKnown -Value $reader.ReadToEnd()) } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
}

function Get-ClaudeCodeRows {
    # The rows of transcript text: { doc; whole; text } each, doc a dictionary or $null when the row is
    # not a JSON object. whole is false only for the last row when the text does not end in a line end
    # (the harness may be mid-write; it is read again on the next look).
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    Add-Type -AssemblyName System.Web.Extensions
    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $ser.MaxJsonLength = [int]::MaxValue
    $parts = $Text -split "`n"
    $out = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $row = $parts[$i].TrimEnd("`r")
        if ($row.Trim() -eq "") { continue }
        $doc = $null
        try { $doc = $ser.DeserializeObject($row) } catch { $doc = $null }
        if ($doc -isnot [System.Collections.IDictionary]) { $doc = $null }
        [void]$out.Add([pscustomobject]@{ doc = $doc; whole = ($i -lt $parts.Count - 1); text = $row })
    }
    return $out.ToArray()
}

function Get-ClaudeCodeContentText {
    # A message's or prompt's text: a string, or its text blocks joined; $null for anything else.
    param($Content)
    if ($Content -is [string]) { return $Content }
    if ($Content -isnot [System.Collections.IEnumerable]) { return $null }
    $sb = New-Object System.Text.StringBuilder
    foreach ($b in $Content) { if ($b -is [System.Collections.IDictionary] -and $b["type"] -ceq "text" -and $b["text"] -is [string]) { [void]$sb.Append($b["text"]) } }
    return $sb.ToString()
}

function Find-ClaudeCodeTurnRow {
    # Does transcript text hold a row that submits -Line for -SessionId (see above)? "taken", "none", or
    # "unreadable" when none does and a whole row that might have been it could not be parsed.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text, [Parameter(Mandatory = $true)][string]$SessionId, [Parameter(Mandatory = $true)][string]$Line)
    $want = $Line.Trim()
    $unreadable = $false
    foreach ($r in @(Get-ClaudeCodeRows -Text $Text)) {
        $d = $r.doc
        if ($null -eq $d) {
            if ($r.whole -and $r.text -cmatch '"type"\s*:\s*"(user|attachment)"') { $unreadable = $true }
            continue
        }
        if ($d["sessionId"] -cne $SessionId) { continue }
        if ($d["isSidechain"] -eq $true) { continue }
        $said = $null
        if ($d["type"] -ceq "user") {
            if ($d["isMeta"] -eq $true) { continue }
            $m = $d["message"]
            if ($m -is [System.Collections.IDictionary]) { $said = Get-ClaudeCodeContentText $m["content"] }
        } elseif ($d["type"] -ceq "attachment") {
            $a = $d["attachment"]
            if ($a -isnot [System.Collections.IDictionary] -or $a["type"] -cne "queued_command") { continue }
            $o = $a["origin"]
            if ($o -isnot [System.Collections.IDictionary] -or $o["kind"] -cne "human") { continue }
            if ($null -ne $a["commandMode"] -and $a["commandMode"] -cne "prompt") { continue }
            $said = Get-ClaudeCodeContentText $a["prompt"]
        }
        if ($null -ne $said -and $said.Trim() -ceq $want) { return "taken" }
    }
    if ($unreadable) { return "unreadable" }
    return "none"
}

function Test-ClaudeCodeTurnText {
    # Does transcript text hold a row that submits -Line for -SessionId? True only when one does.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text, [Parameter(Mandatory = $true)][string]$SessionId, [Parameter(Mandatory = $true)][string]$Line)
    return [bool]((Find-ClaudeCodeTurnRow -Text $Text -SessionId $SessionId -Line $Line) -ceq "taken")
}

function Read-ClaudeCodeSinceMark {
    # The transcript text written after -Mark, as an answer: known "" while there is no transcript.
    param([Parameter(Mandatory = $true)][string]$ConfigDir, [Parameter(Mandatory = $true)][string]$SessionId, $Mark)
    if ($null -eq $Mark -or $null -eq $Mark.PSObject.Properties["size"]) { return (New-HordeUnknown -Reason "no transcript mark was taken before the line was typed, so a new row cannot be told from an old one") }
    $t = Find-ClaudeCodeTranscript -ConfigDir $ConfigDir -SessionId $SessionId
    if ($t.state -eq "absent") { return (New-HordeKnown -Value "") }
    if ($t.state -ne "known") { return $t }
    try { return (Read-ClaudeCodeTextFrom -Path $t.value -Offset ([long]$Mark.size)) } catch { return (New-HordeUnknown -Reason ("the transcript could not be read: " + $_.Exception.Message)) }
}

function Test-ClaudeCodeTurnSeen {
    # After a line is typed: known $true once a new row submits it, known $false while none does.
    param([Parameter(Mandatory = $true)][string]$ConfigDir, [Parameter(Mandatory = $true)][string]$SessionId, $Mark, [Parameter(Mandatory = $true)][string]$Line)
    $since = Read-ClaudeCodeSinceMark -ConfigDir $ConfigDir -SessionId $SessionId -Mark $Mark
    if ($since.state -ne "known") { return $since }
    $f = Find-ClaudeCodeTurnRow -Text $since.value -SessionId $SessionId -Line $Line
    if ($f -ceq "unreadable") { return (New-HordeUnknown -Reason "a whole transcript row written after the mark could not be read, and it could be the turn") }
    return (New-HordeKnown -Value ([bool]($f -ceq "taken")))
}

# THE END OF A TURN (review of PR 239, M1). The node types the prompt only once the no-op line's turn has
# ENDED: typed while the model still answers, the harness queues it (measured above), and a queued line
# is not yet a turn. A turn has ended once the transcript holds, after the mark, a "type":"system" row
# with "subtype":"turn_duration" for this session id. MEASURED 2026-10-14 on 2.1.299: one such row after
# every one of three turns, written after the Stop hooks (stop_hook_summary just before it), 1.8 s to
# 2.4 s after the user row of a one-line turn, with the box idle. Transcript.ps1 reads turn ends from the
# same rows.
# KNOWN LIMITS, kept (review of PR 239, F's nits): (1) only turn_duration ends a turn, with no fallback
# to an assistant row's stop_reason "end_turn": a version that stops writing it makes the wait run out,
# which fails the spawn not-ready with the prompt untyped - never a false done; (2) any turn end after
# the mark counts, not only one after the no-op's own user row: the mark is taken on a new session the
# node has just seen ready - no "esc to interrupt", so no turn running - before its first line, so no
# earlier turn can end after it.
function Test-ClaudeCodeTurnDone {
    # After a line was taken: known $true once a turn has ended after -Mark, known $false while not.
    param([Parameter(Mandatory = $true)][string]$ConfigDir, [Parameter(Mandatory = $true)][string]$SessionId, $Mark)
    $since = Read-ClaudeCodeSinceMark -ConfigDir $ConfigDir -SessionId $SessionId -Mark $Mark
    if ($since.state -ne "known") { return $since }
    foreach ($r in @(Get-ClaudeCodeRows -Text $since.value)) {
        $d = $r.doc
        if ($null -eq $d) { continue }
        if ($d["type"] -ceq "system" -and $d["subtype"] -ceq "turn_duration" -and $d["sessionId"] -ceq $SessionId -and $d["isSidechain"] -ne $true) { return (New-HordeKnown -Value $true) }
    }
    return (New-HordeKnown -Value $false)
}

# THE INPUT BOX ON SCREEN. MEASURED 2026-09-15 in an isolated terminal, and AGAIN 2026-10-14 on 2.1.299
# (the PR 239 live check, a 120x40 pane): the box is the lowest pair of rule rows whose first row inside
# starts with the prompt glyph U+276F. On 2.1.299:
#   - the TOP rule carries the session's name near its right end ("---- ... ---- E livecheck -") when the
#     session was started with a name (-n), as every Horde spawn is. So a rule is a row that, trimmed,
#     starts with at least 8 U+2500 and ends with one; what lies between is a label. The 2026-09-15
#     reader wanted every character to be U+2500, and found NO box on any 2.1.299 screen: no extra Enter
#     could ever have been pressed;
#   - the glyph is followed by U+00A0, not a space. An idle box at start shows a placeholder after it,
#     such as 'Try "edit <filepath> to..."'; an idle box after a turn shows the glyph alone; while a typed
#     line waits in the queue the box shows "Press up to edit queued messages" and the queued line is
#     drawn ABOVE the box, so the box never holds a queued line;
#   - the row under the bottom rule reads "? for shortcuts" when idle and "esc to interrupt" while a turn
#     or a hook runs (seen during the no-op line's UserPromptSubmit hook).
# Typed text follows the glyph and wraps onto the rows below at any column, even inside a word (the
# 2026-09-15 measurement), so the rows are joined, the glyph dropped, and ALL whitespace removed from
# both sides before they are compared. A glyph row whose text starts with a number and a dot is a dialog
# of choices, not a box (the trust dialog's "1. Yes, proceed"). The box is ANCHORED TO THE BOTTOM (review
# of PR 239, S-c): under its bottom rule only footer rows may stand - none with the prompt glyph and none
# with a numbered choice ("1. ") - or what looked like a box is model output with rules in it, or a box
# with a dialog drawn under it, and the answer is unknown. MEASURED on the 48 saved 2.1.299 screens of
# the live check: under the bottom rule stood blank rows and one footer row ("manual mode on", with
# "? for shortcuts" or "esc to interrupt", "1 agent", the effort), never a glyph or a numbered choice.
# A screen with no box is unknown, never empty, so no Enter is pressed into a dialog or a screen nobody
# can read (a dialog takes Enter as its answer).
$script:ClaudeCodeBoxRule = [char]0x2500
$script:ClaudeCodePromptGlyph = [char]0x276F
$script:ClaudeCodeBusyMark = "esc to interrupt"
# The mark as a STATUS ITEM, never inside a sentence (F's re-check of round 3: a start-up tip such as
# "press esc to interrupt a turn" read anywhere on the screen would end the session as not ready): the
# phrase stands alone on its row, or between the separators a footer or spinner row puts round its
# items - "(" or a middle dot before it, ")" or a middle dot after it. Both measured forms are that:
# the 2.1.299 footer "... manual mode on, a middle dot, esc to interrupt, a middle dot ..." and the spinner
# "* Thinking... (esc to interrupt)". THREE FORMS NOT SEEN ON 2.1.299 ARE BUSY TOO (F's re-check of round
# 4, nit), since a spinner's wording moves between versions and a busy session read as ready takes a key
# it should not: a comma as the separator ("(12s, esc to interrupt)"), the spinner's own "..." (or the
# one-glyph ellipsis) before it with nothing after ("* Working... esc to interrupt"), and the phrase in
# any case ("Esc to interrupt"). A tip still reads ready: "press esc to interrupt a turn" has a word
# before the phrase and words after it.
$script:ClaudeCodeBusyItem = '(?:\A|[(\u00B7,]|\.\.\.|\u2026)\s*(?i:esc to interrupt)\s*(?:[)\u00B7,]|\z)'

function Test-ClaudeCodeRuleRow {
    # Is a screen row a rule: trimmed, at least 8 U+2500 first and one last, a label allowed between?
    param([AllowEmptyString()][string]$Row)
    $t = ("" + $Row).Trim()
    if ($t.Length -lt 8 -or $t[$t.Length - 1] -ne $script:ClaudeCodeBoxRule) { return $false }
    for ($i = 0; $i -lt 8; $i++) { if ($t[$i] -ne $script:ClaudeCodeBoxRule) { return $false } }
    return $true
}

function Find-ClaudeCodeInputBox {
    # The lowest input box on -Screen: known { body; below } - body the box's text with the glyph dropped
    # and its rows joined, below the rows under its bottom rule - or unknown with why there is none.
    param([AllowEmptyCollection()][string[]]$Screen = @())
    $rows = @(@($Screen) | ForEach-Object { ("" + $_) -split "`n" } | ForEach-Object { $_.TrimEnd("`r") })
    $rules = @()
    for ($i = 0; $i -lt $rows.Count; $i++) { if (Test-ClaudeCodeRuleRow -Row $rows[$i]) { $rules += $i } }
    for ($k = $rules.Count - 1; $k -ge 1; $k--) {
        $top = $rules[$k - 1]; $bottom = $rules[$k]
        if ($bottom -le $top + 1) { continue }
        $first = $rows[$top + 1].TrimStart()
        if ($first.Length -eq 0 -or $first[0] -ne $script:ClaudeCodePromptGlyph) { continue }
        $body = $first.Substring(1)
        if ($body -cmatch '\A\s*[0-9]+\.\s') { return (New-HordeUnknown -Reason "a dialog of numbered choices is showing where the input box would be") }
        for ($j = $top + 2; $j -lt $bottom; $j++) { $body += $rows[$j] }
        $below = @(); if ($bottom + 1 -lt $rows.Count) { $below = @($rows[($bottom + 1)..($rows.Count - 1)]) }
        foreach ($r in $below) { if (("" + $r).IndexOf($script:ClaudeCodePromptGlyph) -ge 0 -or ("" + $r) -cmatch '(\A|\s)[0-9]+\.\s') { return (New-HordeUnknown -Reason "a dialog of choices is drawn under the input box, or the rules found are not the input box's") } }
        return (New-HordeKnown -Value ([pscustomobject]@{ body = $body; below = $below }))
    }
    return (New-HordeUnknown -Reason "no input box of this harness can be read on the pane's screen")
}

function Test-ClaudeCodeInputHolds {
    # Does the lowest input box on -Screen hold exactly -Line, unsent? An answer (see above).
    param([AllowEmptyCollection()][string[]]$Screen = @(), [Parameter(Mandatory = $true)][string]$Line)
    $b = Find-ClaudeCodeInputBox -Screen $Screen
    if ($b.state -ne "known") { return $b }
    return (New-HordeKnown -Value ([bool](($b.value.body -replace '\s', '') -ceq ($Line -replace '\s', ''))))
}

# READY FOR KEYS (PR 239 round 2, the readiness wait). MEASURED 2026-10-14 on 2.1.299 (the live check's
# keys probe): one letter typed every 0.5 s from the moment the pane started, no Enter. The box was first
# drawn 2.8 s in, holding the two letters typed before 1.6 s (buffered), WITHOUT the one typed at 2.3 s
# (lost while the program set its console up), and with every letter typed after it. So a key typed
# before the box is drawn can be lost, and every key typed once it was drawn was kept; an Enter is a key,
# and on 2026-10-13 a spawn lost both of its Enters. The control file the node identifies the session by
# was written 3.9 s and 4.3 s in, after the box, on this machine; nothing orders the two on a slower one.
# So the session is ready once the box is drawn, is not a dialog, and nothing runs: no row under the box
# says "esc to interrupt" - on 2.1.299 the footer under the box, on other versions a spinner row above it,
# so every row of the screen is read for it (review of PR 239, F's nit; at spawn the screen holds no
# conversation that could quote it). Anything else is not ready, said as unknown with why.
function Test-ClaudeCodeInputReady {
    # Is the session on -Screen ready to take a typed line? known $true, or unknown with why not.
    param([AllowEmptyCollection()][string[]]$Screen = @())
    $b = Find-ClaudeCodeInputBox -Screen $Screen
    if ($b.state -ne "known") { return $b }
    foreach ($r in @($Screen)) { if (("" + $r).Trim() -cmatch $script:ClaudeCodeBusyItem) { return (New-HordeUnknown -Reason "the input box is drawn but a turn or hook is running (the screen says esc to interrupt)") } }
    return (New-HordeKnown -Value $true)
}

function Find-ClaudeCodeSession {
    # The started process as the harness records it, from its control file: known { pid; procStart;
    # name; remoteControl }, absent before the file exists. remoteControl is an answer: known true
    # when the file names a bridge session, unknown otherwise (it may not be up yet).
    param([Parameter(Mandatory = $true)][string]$ConfigDir, [Parameter(Mandatory = $true)][string]$SessionId)
    $dir = Join-Path $ConfigDir "sessions"
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return (New-HordeAbsent -Note ("there is no sessions folder under " + $ConfigDir)) }
    $found = New-Object System.Collections.ArrayList
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
        if ($f.BaseName -cnotmatch '\A[0-9]{1,10}\z') { continue }
        $text = $null
        try { $text = Read-HordeSharedText -Path $f.FullName } catch { continue }
        if ($text -cnotmatch ('"sessionId"\s*:\s*"' + [regex]::Escape($SessionId) + '"')) { continue }
        $doc = $null
        try { $doc = $text | ConvertFrom-Json } catch { return (New-HordeUnknown -Reason ("the control file " + $f.Name + " names the session but is not JSON")) }
        if ("" + $doc.sessionId -cne $SessionId) { continue }
        [void]$found.Add([pscustomobject]@{ file = $f; doc = $doc })
    }
    if ($found.Count -eq 0) { return (New-HordeAbsent -Note ("no control file names " + $SessionId + " yet")) }
    if ($found.Count -gt 1) { return (New-HordeUnknown -Reason ("" + $found.Count + " control files name " + $SessionId)) }
    $d = $found[0].doc
    $pidText = "" + $found[0].file.BaseName
    if ("" + $d.pid -cne $pidText) { return (New-HordeUnknown -Reason ("the control file " + $found[0].file.Name + " names the pid " + $d.pid + ", not its own")) }
    if ("" + $d.procStart -cnotmatch '\A[0-9]{1,20}\z') { return (New-HordeUnknown -Reason ("the control file " + $found[0].file.Name + " gives no process start time")) }
    $rc = New-HordeUnknown -Reason "the control file names no Remote Control session yet"
    $bp = $d.PSObject.Properties["bridgeSessionId"]
    if ($null -ne $bp -and "" + $bp.Value -ne "") { $rc = New-HordeKnown -Value $true }
    return (New-HordeKnown -Value ([pscustomobject]@{ pid = [int]$d.pid; procStart = "" + $d.procStart; name = "" + $d.name; remoteControl = $rc }))
}

function Get-ClaudeCodeVerifiedPreconditions {
    # The preconditions this file can check against the real environment. This harness's rows declare
    # none (agent.json, measured 2026-10-02), so it verifies none: a precondition a later descriptor
    # adds is unverified here, and its level is refused until this file learns to check it.
    param([string[]]$Names)
    return @()
}

Register-HordeLaunchAdapter -Name "claude-code" -Program $script:ClaudeCodeProgram `
    -Argv { param($s) New-ClaudeCodeArgv -Spec $s } `
    -Preconditions { param($n) Get-ClaudeCodeVerifiedPreconditions -Names $n } `
    -Identify { param($id, $view) Find-ClaudeCodeSession -ConfigDir (Get-ClaudeCodeConfigDir -Environment $view) -SessionId $id } `
    -ReadMode { param($id, $view) Read-ClaudeCodeMode -ConfigDir (Get-ClaudeCodeConfigDir -Environment $view) -SessionId $id } `
    -CloseText $script:ClaudeCodeCloseText `
    -TurnMark { param($id, $view) Get-ClaudeCodeTurnMark -ConfigDir (Get-ClaudeCodeConfigDir -Environment $view) -SessionId $id } `
    -TurnSeen { param($id, $view, $mark, $line) Test-ClaudeCodeTurnSeen -ConfigDir (Get-ClaudeCodeConfigDir -Environment $view) -SessionId $id -Mark $mark -Line $line } `
    -TurnDone { param($id, $view, $mark) Test-ClaudeCodeTurnDone -ConfigDir (Get-ClaudeCodeConfigDir -Environment $view) -SessionId $id -Mark $mark } `
    -InputHolds { param($screen, $line) Test-ClaudeCodeInputHolds -Screen $screen -Line $line } `
    -InputReady { param($screen) Test-ClaudeCodeInputReady -Screen $screen }
