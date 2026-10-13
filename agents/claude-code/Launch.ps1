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
# user turn whose text is that line: a "type":"user" entry for this session id, not one of the
# harness's own (isMeta), whose message text - a string, or its text blocks joined - equals the line
# after trimming. Equal, not "contains": a tool result or a later turn that quotes the line is not it.
# New means after the mark taken before typing: the transcript's size then, or 0 when it did not
# exist yet (a session's file can appear only with its first user line: cli/NodeAct.ps1, the no-op
# line). A file shorter than its mark is read from its start: it is not the one the mark measured.
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
    # The text of -Path from byte -Offset on, opened with sharing (core/ReadShared.ps1). An offset past
    # the end reads the whole file (see above).
    param([Parameter(Mandatory = $true)][string]$Path, [long]$Offset = 0)
    $stream = Open-HordeSharedStream -Path $Path
    try {
        if ($Offset -gt $stream.Length) { $Offset = 0 }
        [void]$stream.Seek($Offset, [System.IO.SeekOrigin]::Begin)
        $reader = New-Object System.IO.StreamReader($stream, (New-Object System.Text.UTF8Encoding($false)))
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
}

function Test-ClaudeCodeTurnText {
    # Does transcript text hold a user turn of -SessionId whose text is -Line? A row that is not whole
    # JSON yet (the harness may be mid-write) is passed over, and read again on the next look.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text, [Parameter(Mandatory = $true)][string]$SessionId, [Parameter(Mandatory = $true)][string]$Line)
    $want = $Line.Trim()
    foreach ($row in ($Text -split "`n")) {
        if ($row -cnotmatch '"type"\s*:\s*"user"') { continue }
        $doc = $null
        try { $doc = $row | ConvertFrom-Json } catch { continue }
        if ($null -eq $doc -or "" + $doc.type -cne "user" -or "" + $doc.sessionId -cne $SessionId) { continue }
        if ($null -ne $doc.PSObject.Properties["isMeta"] -and $doc.isMeta -eq $true) { continue }
        if ($null -eq $doc.PSObject.Properties["message"] -or $null -eq $doc.message) { continue }
        $c = $doc.message.content
        $said = ""
        if ($c -is [string]) { $said = $c }
        else { $said = (@(@($c) | Where-Object { $null -ne $_ -and "" + $_.type -ceq "text" -and $_.text -is [string] } | ForEach-Object { $_.text }) -join "") }
        if ($said.Trim() -ceq $want) { return $true }
    }
    return $false
}

function Test-ClaudeCodeTurnSeen {
    # After a line is typed: known $true once a new user turn holds it, known $false while none does.
    param([Parameter(Mandatory = $true)][string]$ConfigDir, [Parameter(Mandatory = $true)][string]$SessionId, $Mark, [Parameter(Mandatory = $true)][string]$Line)
    if ($null -eq $Mark -or $null -eq $Mark.PSObject.Properties["size"]) { return (New-HordeUnknown -Reason "no transcript mark was taken before the line was typed, so a new turn cannot be told from an old one") }
    $t = Find-ClaudeCodeTranscript -ConfigDir $ConfigDir -SessionId $SessionId
    if ($t.state -eq "absent") { return (New-HordeKnown -Value $false) }
    if ($t.state -ne "known") { return $t }
    $text = $null
    try { $text = Read-ClaudeCodeTextFrom -Path $t.value -Offset ([long]$Mark.size) } catch { return (New-HordeUnknown -Reason ("the transcript could not be read: " + $_.Exception.Message)) }
    return (New-HordeKnown -Value (Test-ClaudeCodeTurnText -Text $text -SessionId $SessionId -Line $Line))
}

# THE INPUT BOX ON SCREEN. MEASURED 2026-09-15 in an isolated terminal: the box is the lowest pair of
# rule rows (U+2500) whose first row inside starts with the prompt glyph U+276F; typed text follows the
# glyph and wraps onto the rows below at any column, even inside a word. So the rows are joined, the
# glyph dropped, and ALL whitespace removed from both sides before they are compared. NOT measured:
# whether a later version draws it differently. A screen with no such box is unknown, never empty, so
# no Enter is pressed into a dialog or a screen nobody can read (a dialog takes Enter as its answer).
$script:ClaudeCodeBoxRule = [char]0x2500
$script:ClaudeCodePromptGlyph = [char]0x276F

function Test-ClaudeCodeRuleRow {
    # Is a screen row a rule: at least 8 characters, all U+2500 once trimmed?
    param([AllowEmptyString()][string]$Row)
    $t = ("" + $Row).Trim()
    if ($t.Length -lt 8) { return $false }
    return ($t.Trim($script:ClaudeCodeBoxRule).Length -eq 0)
}

function Test-ClaudeCodeInputHolds {
    # Does the lowest input box on -Screen hold exactly -Line, unsent? An answer (see above).
    param([AllowEmptyCollection()][string[]]$Screen = @(), [Parameter(Mandatory = $true)][string]$Line)
    $rows = @(@($Screen) | ForEach-Object { ("" + $_) -split "`n" } | ForEach-Object { $_.TrimEnd("`r") })
    $rules = @()
    for ($i = 0; $i -lt $rows.Count; $i++) { if (Test-ClaudeCodeRuleRow -Row $rows[$i]) { $rules += $i } }
    for ($k = $rules.Count - 1; $k -ge 1; $k--) {
        $top = $rules[$k - 1]; $bottom = $rules[$k]
        if ($bottom -le $top + 1) { continue }
        $first = $rows[$top + 1].TrimStart()
        if ($first.Length -eq 0 -or $first[0] -ne $script:ClaudeCodePromptGlyph) { continue }
        $body = $first.Substring(1)
        for ($j = $top + 2; $j -lt $bottom; $j++) { $body += $rows[$j] }
        return (New-HordeKnown -Value ([bool](($body -replace '\s', '') -ceq ($Line -replace '\s', ''))))
    }
    return (New-HordeUnknown -Reason "no input box of this harness can be read on the pane's screen")
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
    -InputHolds { param($screen, $line) Test-ClaudeCodeInputHolds -Screen $screen -Line $line }
