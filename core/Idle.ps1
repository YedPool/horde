# core/Idle - the idle port: what a harness's own files say about whether a session is mid-turn or
# holds live work, in one shape the reaper's classifier reads (planning/idle-session-reaper.md,
# sections 1.1 to 1.6, slice RA).
#
# WHY A PORT. Which lines end a turn, which tool starts a background task, how a queued message or a
# recurring cron is written: all of it is the harness's format, and core names no harness
# (CONTRIBUTING 14). So each harness has a READER in agents/<name>/Idle.ps1 that turns its transcript
# into the turn state below, and registers itself here. The classifier (slice RB) reads only turn
# states. A new harness is a new reader.
#
# THE TURN STATE. Every field is required; New-HordeTurnState refuses a missing one, an extra one and a
# wrong type, so a reader cannot hand the classifier a shape it does not read.
#   harness        the reader's name
#   lineCount      lines read; parseSkipped, tornTail: as core/Transcript.ps1 counts them
#   newestEventAt  answer: the newest line time (UTC). NEVER the file's modification time: on
#                  2026-10-05, 7 of 7 idle transcripts had an mtime 35 to 54 min old and a newest event
#                  2.5 to 5.2 days old (the design's I-04). Unknown when a time carries no zone or lies
#                  in the future, because then the age cannot be trusted
#   lastTurnEndAt  answer: the last turn end's time; absent when the file has none
#   atBoundary     answer, true or false: the last turn has ended and only lines the reader allows have
#                  followed it (design 1.5). Unknown when the last line is still being written
#   blockers       the kinds that keep it from a boundary, for people and the decision record
#   remoteLink     answer: the Remote Control link the transcript names (design S8), REPORTED ONLY - a
#                  linked session follows the same idle rules as any other (founder, 2026-10-05)
#   pendingAgents  the background agents the harness said were still running at the last turn end
#   openTools      { id; name }: tool calls with no result yet
#   openTasks      { id; kind }: background tasks started since the process started and not finished
#   unknownTasks   { id; status }: task reports about something the reader cannot recognise, not final
#   queued         messages queued for the session since the process started and not yet taken
#   wakes          { id; dueAt }: one-shot wake-ups requested since the process started, not cancelled;
#                  dueAt is an answer (unknown when the request cannot be timed)
#   crons          { id; recurring }: scheduled jobs created since the process started and still live
#   versions       { version; lines; unrecognised }: the per-version survey (design 1.6): every line kind
#                  each harness version wrote since the process started that the reader does not know
#
# THE SINCE TIME. Background tasks, crons, wakes and the queue live inside the harness process and die
# with it, so a reader counts them only from lines written at or after the process's start - the
# control file's procStart, placed exactly. A since time that is not UTC is refused.
#
# THE PORT NEVER DECIDES. Whether a turn state means idle is the classifier's question; this file only
# guarantees the shape and turns every failure into an unknown with its reason.
#
# No Set-StrictMode here: dot-sourced (see core/Tristate.ps1). It loads what it calls (tools/CoreLoad.ps1).
. (Join-Path $PSScriptRoot "Tristate.ps1")

$script:HordeIdleAdapters = New-Object System.Collections.ArrayList
$script:HordeTurnStateFields = @("harness", "lineCount", "parseSkipped", "tornTail", "newestEventAt", "lastTurnEndAt", "atBoundary", "blockers", "remoteLink",
    "pendingAgents", "openTools", "openTasks", "unknownTasks", "queued", "wakes", "crons", "versions")
$script:HordeTurnStateCounts = @("lineCount", "parseSkipped", "tornTail", "pendingAgents", "queued")
$script:HordeTurnStateAnswers = @("newestEventAt", "lastTurnEndAt", "atBoundary", "remoteLink")
$script:HordeTurnStateLists = @("blockers", "openTools", "openTasks", "unknownTasks", "wakes", "crons", "versions")

function Register-HordeIdleAdapter {
    # Called by a reader file when it is dot-sourced. -Read takes (path, since, now) and returns a turn
    # state made by New-HordeTurnState.
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][scriptblock]$Read)
    if ($Name -cnotmatch '\A[a-z][a-z0-9-]*\z') { throw ("a reader name is lowercase letters, digits and hyphens: '" + $Name + "'") }
    foreach ($a in $script:HordeIdleAdapters) { if ($a.name -ceq $Name) { $script:HordeIdleAdapters.Remove($a); break } }
    [void]$script:HordeIdleAdapters.Add([pscustomobject]@{ name = $Name; read = $Read })
}

function Get-HordeIdleAdapterFiles {
    # The reader files, found by folder and never named: agents/<name>/Idle.ps1. The CALLER dot-sources
    # each one at its own scope, so the reader's helpers stay visible to the block it registers.
    param([string]$Root = (Split-Path -Parent $PSScriptRoot))
    $agents = Join-Path $Root "agents"
    if (-not (Test-Path -LiteralPath $agents -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $agents -Directory | Sort-Object Name | ForEach-Object { Join-Path $_.FullName "Idle.ps1" } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
}

function Test-HordeUtcAnswer {
    # A known answer holding a time must hold a UTC one; an unknown or absent answer is fine.
    param($Answer)
    if ($Answer.state -ne "known") { return $true }
    if ($Answer.value -isnot [datetime]) { return $true }
    return ($Answer.value.Kind -eq [System.DateTimeKind]::Utc)
}

function New-HordeTurnState {
    # The one constructor. -Fields is a hashtable holding exactly $script:HordeTurnStateFields.
    param([Parameter(Mandatory = $true)][hashtable]$Fields)
    foreach ($k in $script:HordeTurnStateFields) { if (-not $Fields.ContainsKey($k)) { throw ("a turn state needs the field '" + $k + "'") } }
    foreach ($k in @($Fields.Keys)) { if ($script:HordeTurnStateFields -cnotcontains $k) { throw ("a turn state has no field '" + $k + "'") } }
    if ("$($Fields["harness"])" -cnotmatch '\A[a-z][a-z0-9-]*\z') { throw ("a turn state's harness is a reader name, not '" + $Fields["harness"] + "'") }
    foreach ($k in $script:HordeTurnStateCounts) {
        $v = $Fields[$k]
        if (($v -isnot [int] -and $v -isnot [long]) -or $v -lt 0) { throw ("the turn state's '" + $k + "' must be a count of zero or more, not '" + $v + "'") }
    }
    foreach ($k in $script:HordeTurnStateAnswers) {
        $a = $Fields[$k]
        if (-not (Test-HordeAnswer $a)) { throw ("the turn state's '" + $k + "' must be an answer") }
        if (-not (Test-HordeUtcAnswer $a)) { throw ("the turn state's '" + $k + "' holds a time that is not UTC") }
    }
    if ($Fields["atBoundary"].state -eq "known" -and $Fields["atBoundary"].value -isnot [bool]) { throw "the turn state's 'atBoundary' must be true or false when known" }
    foreach ($k in $script:HordeTurnStateLists) { if ($null -eq $Fields[$k] -or $Fields[$k] -is [string] -or $Fields[$k] -isnot [System.Collections.IEnumerable]) { throw ("the turn state's '" + $k + "' must be a list") } }
    foreach ($w in @($Fields["wakes"])) { if (-not (Test-HordeAnswer $w.dueAt) -or -not (Test-HordeUtcAnswer $w.dueAt)) { throw "every wake's dueAt must be an answer holding a UTC time" } }
    $r = [ordered]@{ PSTypeName = "Horde.TurnState" }
    foreach ($k in $script:HordeTurnStateFields) {
        if ($script:HordeTurnStateLists -ccontains $k) { $r[$k] = @($Fields[$k]) } else { $r[$k] = $Fields[$k] }
    }
    return [pscustomobject]$r
}

function Read-HordeTurnState {
    # The turn state of one transcript, as an answer: known turn state, or unknown with the reason - no
    # reader for the harness, the reader threw, or it returned something that is not a turn state for
    # that harness.
    param([Parameter(Mandatory = $true)][string]$Harness, [Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][datetime]$Since, [Parameter(Mandatory = $true)][datetime]$Now)
    if ($Since.Kind -ne [System.DateTimeKind]::Utc -or $Now.Kind -ne [System.DateTimeKind]::Utc) { throw "the since and now times must be UTC: a process start is placed exactly or not at all" }
    $reader = $null
    foreach ($a in $script:HordeIdleAdapters) { if ($a.name -ceq $Harness) { $reader = $a } }
    if ($null -eq $reader) { return (New-HordeUnknown -Reason ("no idle reader for the harness '" + $Harness + "'")) }
    $state = $null
    try { $state = & $reader.read $Path $Since $Now }
    catch { return (New-HordeUnknown -Reason ("the " + $Harness + " idle reader failed on " + (Split-Path -Leaf $Path)) -ErrorRecord $_) }
    $one = @($state)
    if ($one.Count -ne 1 -or $one[0] -isnot [psobject] -or $one[0].PSObject.TypeNames -notcontains "Horde.TurnState") {
        return (New-HordeUnknown -Reason ("the " + $Harness + " idle reader returned something that is not a turn state"))
    }
    if ($one[0].harness -cne $Harness) { return (New-HordeUnknown -Reason ("the " + $Harness + " idle reader answered for '" + $one[0].harness + "'")) }
    return (New-HordeKnown -Value $one[0])
}

function Get-HordeUnsurveyedVersions {
    # The harness versions whose lines, in this turn state, carry a kind the reader does not know
    # (design 1.6). A session that wrote any is report-only, named by its version.
    param([Parameter(Mandatory = $true)]$TurnState)
    return @(@($TurnState.versions) | Where-Object { @($_.unrecognised).Count -gt 0 } | ForEach-Object { "$($_.version)" })
}
