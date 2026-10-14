# core/AnalystSession - keeping ONE fleet analyst session alive and lean, decided by no model.
#
# WHY THIS EXISTS. The analyst's context only ever fell when someone reset it by hand: measured
# 2026-10-14 from its transcript's usage fields, 62k tokens just after a fresh start, 221k after 34
# turns, 562k at its largest (10-13). Every call re-reads the whole context, so a wake at 221k costs
# about three times a wake at 70k (planning note "design-analyst-always-on", sections 1 and 2). The
# warchief decided (2026-10-14):
#   - a CONTEXT CAP of contextCapTokens (120k): past it, the next wake goes to a FRESH session that
#     starts from the HANDOVER FILE the analyst keeps, never to a /compact (a compact re-reads the 120k
#     and drifts; a fresh start from a file costs the same every time);
#   - a supervisor that spends no tokens may START that fresh session itself, through the normal spawn
#     path, in the warchief's window - NEVER a restore of saved terminal state - and tells the warchief
#     when it did. It also starts one when the analyst's process is gone.
# This file is the contract of the two files the supervisor and the analyst share, the readers of the
# analyst's liveness and context, and the decision about the session. It starts nothing and posts
# nothing: cli/AnalystTend.ps1 acts on what it answers, through tools a suite replaces.
#
# THE HANDOVER FILE, <analyst folder>\handover.json, written by the ANALYST at the end of every wake
# and read by the next session it is started fresh from. At most handoverMostBytes (8192: about 2k
# tokens, measured against the 63k base of a fresh start). UTF-8 JSON:
#   v           1
#   sessionId   the writing session's own id, in full (the session's own environment names it). THIS is
#               how a freshly started session is known to the supervisor: the spawn path does not
#               hand its id back, so the new session says who it is by writing the file.
#   writtenAt   when, UTC, ISO 8601 with its zone
#   round       the id of the last round it finished, or ""
#   holds       what it is holding: open findings, numbers it is watching          (at most 4000)
#   told        what it told whom, and when                                         (at most 2000)
#   followUps   what it must do next, and what it is waiting on                     (at most 2000)
# The supervisor reads only v, sessionId and writtenAt; the rest is the analyst's, for itself.
#
# THE SUPERVISOR'S STATE, <analyst folder>\supervisor.json, written only by the supervisor (whole, by
# rename, core/FileAtomic.ps1). Its shape is New-HordeAnalystState's.
#
# LIVENESS IS THE AGENT'S OWN ACCOUNT, PROVEN (core/Identity.ps1). A session is alive when a control
# file names it and its process is the one the file describes (pid and start time); gone when the
# listing is whole and no live file names it, or its process ended or its pid was reused; unknown
# otherwise - and AN UNKNOWN IS NEVER A START (core/Tristate.ps1): two analysts is worse than a late one.
#
# CONTEXT IS READ FROM THE TRANSCRIPT'S USAGE FIELDS (core/Transcript.ps1), never its text: the size of
# the context the last call read is input + cache read + cache write of that call. Only the newest call
# is kept while the file streams past, so a 100 MB transcript costs no more memory than a small one.
#
# NEVER A START LOOP. A start waits for the new session's handover (startWaitMinutes); while it waits,
# nothing else is started, and if it never comes the warchief is told once and the supervisor goes on
# waiting - a person decides. Two starts are at least restartMinMinutes apart.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "JsonText.ps1")
. (Join-Path $PSScriptRoot "ReadShared.ps1")
. (Join-Path $PSScriptRoot "FileAtomic.ps1")
. (Join-Path $PSScriptRoot "Transcript.ps1")
. (Join-Path $PSScriptRoot "Identity.ps1")
. (Join-Path $PSScriptRoot "AnalystRounds.ps1")

$script:HordeAnalystSessionIdPattern = '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z'
$script:HordeAnalystHandoverMembers = @("v", "sessionId", "writtenAt", "round", "holds", "told", "followUps")
$script:HordeAnalystHandoverCaps = @{ round = 80; holds = 4000; told = 2000; followUps = 2000 }
$script:HordeAnalystPhases = @("none", "running", "starting")
# How many rounds the state remembers: enough to see a day of rounds (about 50), and bounded.
$script:HordeAnalystRoundsKept = 64
$script:HordeAnalystStateMostBytes = 65536
$script:HordeAnalystSessionActions = @("keep", "adopt", "start", "wait", "tell")

function Get-HordeAnalystSessionPaths {
    # The two files of this contract under -Folder.
    param([Parameter(Mandatory = $true)][string]$Folder)
    return [pscustomobject]@{
        handover = [System.IO.Path]::Combine($Folder, "handover.json")
        state = [System.IO.Path]::Combine($Folder, "supervisor.json")
    }
}

function Get-HordeAnalystHeartbeatPath {
    # The heartbeat of `horde analyst run`: ALWAYS under the Horde home, analyst\heartbeat.json, wherever
    # the analyst folder is - horde services reads a heartbeat only by a path inside the home it serves
    # (core/Services.ps1, alive.heartbeat), and the analyst folder may be anywhere.
    param([string]$HordeHome = "")
    if ($HordeHome -eq "") { $HordeHome = Get-HordeHome }
    return [System.IO.Path]::Combine($HordeHome, "analyst", "heartbeat.json")
}

function Read-HordeAnalystSmallText {
    # The whole of a small file as text: known text, absent when there is no file, unknown when it is
    # larger than -Most bytes or cannot be read or decoded as UTF-8.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][int]$Most, [Parameter(Mandatory = $true)][string]$What)
    $stream = $null
    try {
        try { $stream = Open-HordeSharedStream -Path $Path }
        catch {
            $cause = $_.Exception.GetBaseException()
            if ($cause -is [System.IO.FileNotFoundException] -or $cause -is [System.IO.DirectoryNotFoundException]) { return (New-HordeAbsent -Note ("there is no " + $What)) }
            return (New-HordeUnknown -Reason ("the " + $What + " could not be opened") -ErrorRecord $_)
        }
        if ($stream.Length -gt $Most) { return (New-HordeUnknown -Reason ("the " + $What + " is " + $stream.Length + " bytes, more than the " + $Most + " it may be")) }
        $buffer = New-Object System.IO.MemoryStream
        $stream.CopyTo($buffer)
        $text = $null
        try { $text = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($buffer.ToArray()) } catch { return (New-HordeUnknown -Reason ("the " + $What + " is not UTF-8 text")) }
        return (New-HordeKnown -Value $text.TrimStart([char]0xFEFF))
    } catch {
        return (New-HordeUnknown -Reason ("the " + $What + " could not be read") -ErrorRecord $_)
    } finally { if ($null -ne $stream) { $stream.Dispose() } }
}

function ConvertFrom-HordeAnalystHandoverText {
    # PURE. The handover's text checked against the contract (header): known { sessionId; writtenAt;
    # round }, or unknown naming every problem. Its free text is checked for size and kind, never read.
    param([AllowEmptyString()][string]$Text)
    $doc = $null
    try { $doc = ConvertFrom-HordeJson -Text $Text } catch { return (New-HordeUnknown -Reason "the handover file is not JSON") }
    if ($doc -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeUnknown -Reason "the handover file is not a JSON object") }
    $problems = New-Object System.Collections.ArrayList
    $names = @($doc.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($n in $names) { if ($script:HordeAnalystHandoverMembers -cnotcontains $n) { [void]$problems.Add("it has the member '" + $(if ($n.Length -gt 40) { $n.Substring(0, 40) } else { $n }) + "', which a handover does not have") } }
    foreach ($n in $script:HordeAnalystHandoverMembers) { if ($names -cnotcontains $n) { [void]$problems.Add("it has no member '" + $n + "'") } }
    if ($problems.Count -eq 0) {
        if (("" + $doc.v) -cne "1") { [void]$problems.Add("its v is not 1") }
        if ($doc.sessionId -isnot [string] -or $doc.sessionId -cnotmatch $script:HordeAnalystSessionIdPattern) { [void]$problems.Add("its sessionId is not a session id written out in full, in lower case") }
        $at = ConvertFrom-HordeAnalystTime -Text $doc.writtenAt
        if ($null -eq $at) { [void]$problems.Add("its writtenAt is not a time with a zone") }
        foreach ($k in @("round", "holds", "told", "followUps")) {
            $v = $doc.$k
            if ($v -isnot [string] -or $v.Length -gt $script:HordeAnalystHandoverCaps[$k]) { [void]$problems.Add("its " + $k + " is not text of at most " + $script:HordeAnalystHandoverCaps[$k] + " characters") }
        }
    }
    if ($problems.Count -gt 0) { return (New-HordeUnknown -Reason ("the handover file is refused: " + ($problems -join "; "))) }
    return (New-HordeKnown -Value ([pscustomobject]@{ sessionId = $doc.sessionId; writtenAt = $at; round = $doc.round }))
}

function Read-HordeAnalystHandover {
    # The handover at -Path: known (ConvertFrom-HordeAnalystHandoverText), absent, or unknown.
    param([Parameter(Mandatory = $true)][string]$Path, [int]$Most = 8192)
    $text = Read-HordeAnalystSmallText -Path $Path -Most $Most -What "handover file"
    if ($text.state -cne "known") { return $text }
    return (ConvertFrom-HordeAnalystHandoverText -Text $text.value)
}

function New-HordeAnalystState {
    # The supervisor's state as a fresh supervisor holds it: no session known.
    return [pscustomobject]@{
        v = 1; sessionId = ""; phase = "none"; previousSessionId = ""; startedAt = $null; startReason = ""
        lastRoundAt = $null; lastWakeAt = $null; findingsOffset = [long]0
        rounds = @(); told = @()
        contextTokens = [long]-1; contextAt = $null; transcriptLength = [long]-1
    }
}

function ConvertTo-HordeAnalystTimeText {
    param($At)
    if ($At -isnot [datetime]) { return $null }
    return $At.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Read-HordeAnalystState {
    # The supervisor's state at -Path: known (New-HordeAnalystState's shape), known fresh when there is
    # no file, unknown when there is one that cannot be read: a supervisor that lost its state must not
    # act as if it had none, or it would start a second analyst.
    param([Parameter(Mandatory = $true)][string]$Path)
    $text = Read-HordeAnalystSmallText -Path $Path -Most $script:HordeAnalystStateMostBytes -What "supervisor's state file"
    if ($text.state -ceq "absent") { return (New-HordeKnown -Value (New-HordeAnalystState)) }
    if ($text.state -cne "known") { return $text }
    $doc = $null
    try { $doc = ConvertFrom-HordeJson -Text $text.value } catch { return (New-HordeUnknown -Reason "the supervisor's state file is not JSON") }
    $s = New-HordeAnalystState
    try {
        if (("" + $doc.v) -cne "1") { throw "its v is not 1" }
        $s.sessionId = "" + $doc.sessionId
        if ($s.sessionId -ne "" -and $s.sessionId -cnotmatch $script:HordeAnalystSessionIdPattern) { throw "its sessionId is not a session id" }
        $s.phase = "" + $doc.phase
        if ($script:HordeAnalystPhases -cnotcontains $s.phase) { throw "its phase is not one of none, running, starting" }
        $s.previousSessionId = "" + $doc.previousSessionId
        $s.startReason = "" + $doc.startReason
        $s.startedAt = ConvertFrom-HordeAnalystTime -Text $doc.startedAt
        $s.lastRoundAt = ConvertFrom-HordeAnalystTime -Text $doc.lastRoundAt
        $s.lastWakeAt = ConvertFrom-HordeAnalystTime -Text $doc.lastWakeAt
        $s.contextAt = ConvertFrom-HordeAnalystTime -Text $doc.contextAt
        $s.findingsOffset = [long]$doc.findingsOffset
        $s.contextTokens = [long]$doc.contextTokens
        $s.transcriptLength = [long]$doc.transcriptLength
        $s.told = [string[]]@($doc.told | Where-Object { $_ -is [string] })
        $rounds = New-Object System.Collections.ArrayList
        foreach ($r in @($doc.rounds)) {
            if ($null -eq $r) { continue }
            $at = ConvertFrom-HordeAnalystTime -Text $r.at
            if ($null -eq $at -or "" + $r.id -cnotmatch $script:HordeAnalystIdPattern) { throw "a round in it has no id or no time" }
            [void]$rounds.Add([pscustomobject]@{ id = "" + $r.id; kind = "" + $r.kind; at = $at; sessionId = "" + $r.sessionId; alerted = ($r.alerted -eq $true); woken = "" + $r.woken })
        }
        $s.rounds = @($rounds.ToArray())
    } catch { return (New-HordeUnknown -Reason ("the supervisor's state file is refused: " + $_.Exception.Message)) }
    return (New-HordeKnown -Value $s)
}

function Write-HordeAnalystState {
    # Replace the supervisor's state at -Path whole (written beside itself, renamed over it). The rounds
    # kept are the newest $script:HordeAnalystRoundsKept.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$State)
    $rounds = @($State.rounds)
    if ($rounds.Count -gt $script:HordeAnalystRoundsKept) { $rounds = @($rounds | Select-Object -Last $script:HordeAnalystRoundsKept) }
    $doc = [ordered]@{
        v = 1; sessionId = "" + $State.sessionId; phase = "" + $State.phase; previousSessionId = "" + $State.previousSessionId
        startedAt = (ConvertTo-HordeAnalystTimeText $State.startedAt); startReason = "" + $State.startReason
        lastRoundAt = (ConvertTo-HordeAnalystTimeText $State.lastRoundAt); lastWakeAt = (ConvertTo-HordeAnalystTimeText $State.lastWakeAt)
        findingsOffset = [long]$State.findingsOffset
        rounds = @($rounds | ForEach-Object { [ordered]@{ id = $_.id; kind = $_.kind; at = (ConvertTo-HordeAnalystTimeText $_.at); sessionId = $_.sessionId; alerted = [bool]$_.alerted; woken = "" + $_.woken } })
        told = @($State.told)
        contextTokens = [long]$State.contextTokens; contextAt = (ConvertTo-HordeAnalystTimeText $State.contextAt); transcriptLength = [long]$State.transcriptLength
    }
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    [void][System.IO.Directory]::CreateDirectory($dir)
    $temp = $Path + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    [System.IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject $doc -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
    try { Move-HordeFileAtomic -From $temp -To $Path }
    catch { try { [System.IO.File]::Delete($temp) } catch { }; throw }
}

function Get-HordeAnalystLiveness {
    # Whether -SessionId is running, from a reading of every agent's control files (Get-HordeIdentity):
    # { alive; transcript } where alive is known $true / known $false / unknown (LIVENESS, header) and
    # transcript the record's transcript path as an answer.
    param([Parameter(Mandatory = $true)][string]$SessionId, [Parameter(Mandatory = $true)]$Identity)
    $noPath = New-HordeUnknown -Reason "no record of the session names its transcript"
    if ($Identity.records.ContainsKey($SessionId)) {
        $rec = $Identity.records[$SessionId]
        $path = $rec.fields["transcriptPath"]
        switch -CaseSensitive ("" + $rec.processCheck) {
            "verified" { return [pscustomobject]@{ alive = (New-HordeKnown -Value $true); transcript = $path } }
            "gone" { return [pscustomobject]@{ alive = (New-HordeKnown -Value $false); transcript = $path } }
            "reused" { return [pscustomobject]@{ alive = (New-HordeKnown -Value $false); transcript = $path } }
            default { return [pscustomobject]@{ alive = (New-HordeUnknown -Reason ("its control file could not be checked against its process (" + $rec.processCheck + ")")); transcript = $path } }
        }
    }
    foreach ($d in @($Identity.duplicates)) { if ("" + $d.sessionId -ieq $SessionId) { return [pscustomobject]@{ alive = (New-HordeUnknown -Reason "more than one control file names it"); transcript = $noPath } } }
    # verifiedLive is known only when the process table and the listing are both whole (core/Identity.ps1):
    # then a session no file names is not running. Otherwise it may be, unseen.
    $whole = $Identity.verifiedLive
    if ($null -ne $whole -and $whole.state -ceq "known") { return [pscustomobject]@{ alive = (New-HordeKnown -Value $false); transcript = $noPath } }
    return [pscustomobject]@{ alive = (New-HordeUnknown -Reason ("the listing of running sessions is not whole" + $(if ($null -ne $whole -and $whole.state -ceq "unknown") { ": " + $whole.reason } else { "" }))); transcript = $noPath }
}

function New-HordeAnalystLastCallSink {
    # What a transcript read hands its records to (core/Transcript.ps1, -Into): keeps only the newest
    # call with known usage, so the read holds one record however long the file is.
    $sink = [pscustomobject]@{ last = $null; calls = 0 }
    $sink | Add-Member -MemberType ScriptMethod -Name Add -Value {
        param($Record)
        if ("" + $Record.kind -cne "call" -or $Record.usage.state -cne "known") { return }
        $this.calls++
        if ($null -eq $this.last -or $Record.ts -ge $this.last.ts) { $this.last = $Record }
    }
    return $sink
}

function Get-HordeAnalystContextTokens {
    # The size of the context the session's last call read, from its transcript at -Path: known
    # { tokens; at } (at: when that call was made), absent when the transcript holds no call with usage
    # yet, unknown when it cannot be read. The adapters (agents/<name>/Transcript.ps1) must have been
    # loaded by the caller (core/Transcript.ps1, Get-HordeTranscriptAdapterFiles).
    param([Parameter(Mandatory = $true)][string]$Path)
    $sink = New-HordeAnalystLastCallSink
    $read = Read-HordeTranscript -Path $Path -Into $sink
    if ($read.state -cne "known") { return $read }
    if ($null -eq $sink.last) { return (New-HordeAbsent -Note "the transcript holds no call with its usage yet") }
    $u = $sink.last.usage.value
    return (New-HordeKnown -Value ([pscustomobject]@{ tokens = ([long]$u.input + [long]$u.cacheRead + [long]$u.cacheWrite); at = $sink.last.ts }))
}

function Get-HordeAnalystSessionDecision {
    # PURE. What to do about the session this pass: { action; why; tell; sessionId; reason }.
    #   keep    the session it has is running and under the cap (or no round is due): go on.
    #   adopt   a session the supervisor did not know yet has written its handover: it is now THE
    #           analyst (sessionId names it). A fresh start ends this way, and so does a first run.
    #   start   start a fresh session now; reason is gone or over-cap. Only offered when -CanStart.
    #   wait    do nothing about the session this pass (an unknown, a start in progress).
    #   tell    the warchief must act; nothing is started (no spawn path is set, or none is known).
    # tell, on any action, is the key of something the warchief should hear once ("" for nothing).
    # -State: the supervisor's state. -Alive: liveness of state.sessionId (Get-HordeAnalystLiveness's
    # alive), ignored when no session is known. -Handover: Read-HordeAnalystHandover's answer.
    # -Context: known { tokens } or not. -RoundDue: whether this pass has something to deliver.
    param(
        [Parameter(Mandatory = $true)]$State,
        $Alive = $null,
        [Parameter(Mandatory = $true)]$Handover,
        $Context = $null,
        [Parameter(Mandatory = $true)][datetime]$Now,
        [Parameter(Mandatory = $true)]$Policy,
        [bool]$RoundDue = $false,
        [bool]$CanStart = $false
    )
    $out = { param($Action, $Why, $Tell, $Sid, $Reason) return [pscustomobject]@{ action = $Action; why = $Why; tell = $Tell; sessionId = $Sid; reason = $Reason } }
    $now = $Now.ToUniversalTime()
    $fresh = ($Handover.state -ceq "known")
    switch -CaseSensitive ("" + $State.phase) {
        "starting" {
            $since = $(if ($State.startedAt -is [datetime]) { $State.startedAt } else { $now })
            # A handover written after the start (a minute of clock slack), by a session that is not the
            # one replaced, is the new one.
            if ($fresh -and $Handover.value.sessionId -cne ("" + $State.previousSessionId) -and $Handover.value.writtenAt -ge $since.AddMinutes(-1)) {
                return (& $out "adopt" "the fresh session has written its handover" "" $Handover.value.sessionId "")
            }
            if ($now -ge $since.AddMinutes([int]$Policy.startWaitMinutes)) { return (& $out "wait" ("a fresh session was started " + [int]($now - $since).TotalMinutes + " minutes ago and has not written its handover") "start-silent" "" "") }
            return (& $out "wait" "a fresh session was started and has not written its handover yet" "" "" "")
        }
        "none" {
            if ($fresh) { return (& $out "adopt" "the analyst named in the handover file is taken as the analyst" "" $Handover.value.sessionId "") }
            return (& $out "tell" "no analyst session is known: none has written a handover file" "no-analyst" "" "")
        }
    }
    # running
    if ($null -eq $Alive -or $Alive.state -cne "known") { return (& $out "wait" ("whether the analyst is running cannot be told: " + $(if ($null -ne $Alive -and $Alive.state -ceq "unknown") { $Alive.reason } else { "nobody looked" })) "" "" "") }
    $gone = ($Alive.value -ne $true)
    $over = (-not $gone -and $null -ne $Context -and $Context.state -ceq "known" -and [long]$Context.value.tokens -gt [long]$Policy.contextCapTokens)
    if (-not $gone -and -not ($over -and $RoundDue)) { return (& $out "keep" $(if ($over) { "the analyst is over its context cap; the next round goes to a fresh session" } else { "the analyst is running" }) "" "" "") }
    $reason = $(if ($gone) { "gone" } else { "over-cap" })
    $why = $(if ($gone) { "the analyst's process is gone" } else { "the analyst's context is " + $Context.value.tokens + " tokens, over the cap of " + $Policy.contextCapTokens })
    # The warchief may have started one by hand: a newer handover from another session is followed.
    $since = $(if ($State.startedAt -is [datetime]) { [datetime]$State.startedAt } else { [datetime]::MinValue })
    if ($gone -and $fresh -and $Handover.value.sessionId -cne ("" + $State.sessionId) -and $Handover.value.writtenAt -gt $since) {
        return (& $out "adopt" "the analyst's process is gone, and another session has written the handover since" "" $Handover.value.sessionId "")
    }
    if (-not $CanStart) { return (& $out "tell" ($why + "; no spawn script is set, so the warchief must start one") ("no-spawn-" + $reason) "" $reason) }
    if ($State.startedAt -is [datetime] -and $now -lt ([datetime]$State.startedAt).AddMinutes([int]$Policy.restartMinMinutes)) {
        return (& $out "wait" ($why + "; the last start was under " + $Policy.restartMinMinutes + " minutes ago, so none is made yet") ("start-too-soon-" + $reason) "" $reason)
    }
    return (& $out "start" $why "" "" $reason)
}
