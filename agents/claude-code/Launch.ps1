# agents/claude-code/Launch.ps1 - how this harness is started, and how Horde reads back what started.
#
# The claude-code half of the launch port (core/AgentLaunch.ps1; remote plan R9, engines E9, issue
# #67). Everything here names this harness's flags, files or modes, so it lives in this folder
# (CONTRIBUTING 14). Nothing here starts a process: the host layer runs the argv this file builds.
#
# THE ARGV, every flag read off --help 2.1.287 (agent.json cites each):
#   --session-id <uuid>        the node chooses the id, so it can find the session afterwards
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
# 2.1.289, interactive sessions in an isolated WezTerm, one per level: the transcript's first lines
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

function Get-ClaudeCodeConfigDir {
    # The harness's folder for a given environment view: CLAUDE_CONFIG_DIR when set, else the profile's
    # .claude. -Environment is a hashtable of the variables the harness will see.
    param([Parameter(Mandatory = $true)][hashtable]$Environment)
    $set = "" + $Environment["CLAUDE_CONFIG_DIR"]
    if ($set.Trim() -ne "") { return $set.Trim() }
    return (Join-Path ("" + $Environment["USERPROFILE"]) ".claude")
}

function New-ClaudeCodeArgv {
    # The argv for one start, as an answer. -Spec: { sessionId; permissionArgs; model; name; prompt }.
    param([Parameter(Mandatory = $true)]$Spec)
    $argv = New-Object System.Collections.Generic.List[string]
    $argv.Add("--session-id"); $argv.Add("" + $Spec.sessionId)
    foreach ($p in @($Spec.permissionArgs)) { if ($null -ne $p) { $argv.Add("" + $p) } }
    if ($null -ne $Spec.model -and "" + $Spec.model -ne "") { $argv.Add("--model"); $argv.Add("" + $Spec.model) }
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
    -ReadMode { param($id, $view) Read-ClaudeCodeMode -ConfigDir (Get-ClaudeCodeConfigDir -Environment $view) -SessionId $id }
