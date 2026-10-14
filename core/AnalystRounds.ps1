# core/AnalystRounds - WHEN the fleet analyst is woken, decided by no model.
#
# WHY THIS EXISTS. The fleet analyst (a session under the warchief that reads the fleet's numbers and
# alarms and sends the warchief conclusions) was woken by every task-ledger milestone, every alarm and
# every mail, each one a separate turn that re-read its whole context. Measured 2026-10-14 from its own
# transcript's usage fields: about 0.77M input tokens a wake, 164 turns on 10-13, 208M input tokens that
# day (planning note "design-analyst-always-on", sections 1 and 4). The warchief decided (2026-10-14):
#   - the deterministic scripts write every finding to ONE FINDINGS FILE and wake nobody;
#   - the analyst is woken by a ROUND every roundMinutes (30) that holds something new, never by a
#     single finding;
#   - a finding marked "now" (a fleet that has gone still, a PC out of memory) and mail from the
#     warchief whose first word is one of wakeNowMarkers (URGENT, QUESTION) wake it AT ONCE;
#     everything else the warchief writes to it waits for the next round;
#   - with nothing to say for heartbeatHours (6), it gets one HEARTBEAT round, so a wedged session is
#     found the same working day. The process's own liveness costs no tokens and is checked every pass
#     (cli/AnalystTend.ps1); the heartbeat only proves the session still answers;
#   - the analyst ends every round by appending "round <id> done" to the ACK FILE; a round with no ack
#     after ackMinutes (15) is told to the warchief and to the founder, by a script, once.
# This file is that decision and the readers of the three files it is made from. It starts nothing,
# posts nothing and writes nothing: cli/AnalystTend.ps1 acts on what it answers.
#
# THE FILES, all under the analyst folder (the setting folder; empty is <HORDE_HOME>\analyst):
#   findings.jsonl  APPENDED by the scripts, never rewritten. One JSON object a line, UTF-8:
#                     v       1
#                     id      the finding's own id, 1 to 80 of A-Z a-z 0-9 . _ : - (a script's own key:
#                             "alarm:TASK-LOST:T-0101", "milestone:20261014T2130Z-03")
#                     at      when it was found, UTC, ISO 8601 with its zone
#                     source  which script found it, 1 to 40 of the same characters
#                     wake    "now", "round" or "never" (written down for the record, wakes nobody)
#                     text    what was found, in the finding script's words: ONE line, at most 2000
#                   The supervisor reads only id and wake. The text is for the analyst, who reads the
#                   file itself; a round carries no finding's words (FIXED WORDS, below).
#   mail\           one file a message from the warchief, <yyyyMMddTHHmmssfffZ>-<8 hex>.txt, written by
#                   `horde analyst mail`. Its first word decides whether it waits (MARKERS, below).
#                   Delivered mail is moved to mail\delivered\ by the supervisor.
#   acks.txt        APPENDED by the analyst: "round <id> done", one a line.
#
# A LINE THAT CANNOT BE READ IS NOT DROPPED. A findings line that is not JSON, or not the shape above,
# becomes an item that waits for the next round, with the reason, so the analyst still sees that the
# script wrote something; it never wakes the analyst at once, because a broken line cannot say it is
# urgent. A partial last line (no newline yet) is left for the next pass: the writer is mid-append.
#
# MARKERS ARE THE MESSAGE'S FIRST WORD, IN CAPITALS, as the fleet already writes them: "URGENT: the
# relay is down" or "QUESTION 3: ...". The word must stand alone - followed by a colon, a blank or the
# end - so "URGENTLY" and "QUESTIONS" are not markers, and a marker inside a sentence is not either
# (the analyst's own watcher of 2026-10-13 flagged "...THE IDENTITY QUESTION" mid-sentence as a question
# waiting; the rule here never looks past the first word). Case is exact: "urgent:" waits.
#
# FIXED WORDS. A round tells the analyst WHERE to look and HOW MUCH is there, in words chosen here:
# counts, ids of its own making, the paths of the analyst folder. No finding's text and no mail's text
# is put in it, so nothing a script or a file can shape reaches the session as if Horde had said it
# (cli/ServicesTell.ps1, the same rule for the supervisor of services).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "Home.ps1")
. (Join-Path $PSScriptRoot "JsonText.ps1")
. (Join-Path $PSScriptRoot "ReadShared.ps1")
. (Join-Path $PSScriptRoot "ModuleSettings.ps1")

# THE ANALYST'S SETTINGS (<HORDE_HOME>\settings\analyst.json, core/ModuleSettings.ps1). The defaults are
# the warchief's decisions of 2026-10-14; a person changes them in that file, never in code.
$script:HordeAnalystSettings = New-HordeModuleSettings -Module "analyst" -Settings @(
    @{ name = "folder"; kind = "folder"; default = ""
       what = "The analyst folder: findings, mail, acks and state. Empty means analyst under the Horde home." },
    @{ name = "roundMinutes"; kind = "whole"; default = 30; min = 5; max = 240
       what = "How often, in minutes, at most, the analyst is woken for what has waited: a round." },
    # 6 hours, not the 2 of the first design: the token-free pass already proves the process is alive
    # every minute, so the heartbeat only has to prove the session still answers (the warchief, 2026-10-14).
    @{ name = "heartbeatHours"; kind = "whole"; default = 6; min = 1; max = 48
       what = "After this many hours with no wake, the analyst gets one heartbeat round." },
    @{ name = "wakeNowMarkers"; kind = "text"; default = "URGENT,QUESTION"; min = 1; max = 200
       what = "First words, comma separated, that make a mail from the warchief wake the analyst at once." },
    @{ name = "ackMinutes"; kind = "whole"; default = 15; min = 1; max = 240
       what = "How long, in minutes, a round may wait for its ack before the warchief and the founder are told." },
    # THE SESSION (core/AnalystSession.ps1). 120k is the warchief's cap of 2026-10-14: a fresh start
    # measured 62k to 67k, so a session gets about ten wakes of 4.7k each before it is replaced.
    @{ name = "contextCapTokens"; kind = "whole"; default = 120000; min = 20000; max = 2000000
       what = "Past this many tokens of context, the next round goes to a fresh session started from the handover file." },
    @{ name = "startWaitMinutes"; kind = "whole"; default = 20; min = 2; max = 240
       what = "How long, in minutes, a fresh session has to write its handover file before the warchief is told." },
    @{ name = "restartMinMinutes"; kind = "whole"; default = 30; min = 5; max = 1440
       what = "The least time, in minutes, between two starts of a fresh session." },
    # EMPTY BY DEFAULT: nothing is started until a person has named the script that starts it.
    @{ name = "spawnScript"; kind = "folder"; default = ""
       what = "The absolute path of the .ps1 that starts a fresh analyst. Empty: never start one; tell the warchief." },
    # ON BY DEFAULT, as the supervisor of services is: a trouble nobody is told of is the failure this
    # module exists to end. A test's home under the temp folder tells nobody whatever this says.
    @{ name = "tellWarchief"; kind = "truefalse"; default = $true
       what = "Whether the warchief is told when the analyst is started, cannot be started, or does not answer." },
    @{ name = "notifyFounder"; kind = "truefalse"; default = $true
       what = "Whether the founder's phone is told when a round gets no ack in time." },
    @{ name = "fromLabel"; kind = "label"; default = "AS"
       what = "The hub label the supervisor's messages wear, so a messenger can say who they are from." }
)

$script:HordeAnalystMarkerPattern = '\A[A-Z][A-Z0-9-]{1,23}\z'
$script:HordeAnalystIdPattern = '\A[A-Za-z0-9._:-]{1,80}\z'
$script:HordeAnalystSourcePattern = '\A[A-Za-z0-9._:-]{1,40}\z'
$script:HordeAnalystWakes = @("now", "round", "never")
$script:HordeAnalystTextMost = 2000
$script:HordeAnalystMailNamePattern = '\A[0-9]{8}T[0-9]{9}Z-[0-9a-f]{8}\.txt\z'
# The most of the findings file one pass reads. A busy day wrote 241 milestones (10-13); at 2000
# characters each that is under 0.5 MB, so 1 MB a pass never falls behind and never holds a runaway
# file in memory. What is past it is read by the next pass, from where this one stopped.
$script:HordeAnalystReadMostBytes = 1048576
# The most of a mail's start that is read for its marker: the marker is its first word.
$script:HordeAnalystMarkerReadChars = 64
# The most of the ack file's end that is read: a line is about 30 bytes, so 64 KB holds 2000 rounds,
# more than a month of them.
$script:HordeAnalystAckTailBytes = 65536
$script:HordeAnalystAckPattern = '\Around ([A-Za-z0-9._:-]{1,80}) done\s*\z'
$script:HordeAnalystActions = @("now", "round", "heartbeat", "none")

function Get-HordeAnalystSettingsDeclaration { return $script:HordeAnalystSettings }

function Get-HordeAnalystSettings {
    # The analyst's settings as they are now: { state; values; findings; path } (core/ModuleSettings.ps1).
    param([string]$HordeHome = "")
    return (Get-HordeModuleSettings -Declaration $script:HordeAnalystSettings -HordeHome $HordeHome)
}

function Get-HordeAnalystFolder {
    # The analyst folder for -Values (the settings' values): the setting, or analyst under the home.
    param([Parameter(Mandatory = $true)]$Values, [string]$HordeHome = "")
    if ("" + $Values.folder -ne "") { return ("" + $Values.folder) }
    if ($HordeHome -eq "") { $HordeHome = Get-HordeHome }
    return [System.IO.Path]::Combine($HordeHome, "analyst")
}

function Get-HordeAnalystPaths {
    # Every file of the analyst folder (header), by name, so no caller builds one by hand.
    param([Parameter(Mandatory = $true)][string]$Folder)
    return [pscustomobject]@{
        folder = $Folder
        findings = [System.IO.Path]::Combine($Folder, "findings.jsonl")
        mail = [System.IO.Path]::Combine($Folder, "mail")
        delivered = [System.IO.Path]::Combine($Folder, "mail", "delivered")
        acks = [System.IO.Path]::Combine($Folder, "acks.txt")
    }
}

function Get-HordeAnalystMarkers {
    # The markers of -Text (the setting wakeNowMarkers): known string[], or unknown naming what is wrong.
    # A setting the module cannot use refuses, as a bad settings file does: a marker list that silently
    # lost one word would let an URGENT mail wait half an hour.
    param([AllowEmptyString()][string]$Text)
    $out = New-Object System.Collections.ArrayList
    foreach ($part in @($Text -split ",")) {
        $w = $part.Trim()
        if ($w -cnotmatch $script:HordeAnalystMarkerPattern) { return (New-HordeUnknown -Reason ("the setting wakeNowMarkers holds '" + $(if ($w.Length -gt 24) { $w.Substring(0, 24) + "..." } else { $w }) + "', which is not a marker: 2 to 24 capital letters, digits or hyphens, starting with a letter")) }
        if (-not $out.Contains($w)) { [void]$out.Add($w) }
    }
    return (New-HordeKnown -Value ([string[]]$out.ToArray()))
}

function Get-HordeAnalystMailMarker {
    # PURE. The marker -Text starts with (MARKERS ARE THE MESSAGE'S FIRST WORD, header), or "".
    param([AllowEmptyString()][string]$Text, [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Markers)
    $m = [regex]::Match($Text, '\A\s*([A-Za-z0-9-]+)(?=\s|:|\z)')
    if (-not $m.Success) { return "" }
    $word = $m.Groups[1].Value
    if ($Markers -ccontains $word) { return $word }
    return ""
}

function ConvertFrom-HordeAnalystTime {
    # A finding's time: a UTC [datetime], or $null when it is not a time with a zone.
    param($Text)
    if ($Text -isnot [string] -or $Text -eq "") { return $null }
    $parsed = [datetime]::MinValue
    if (-not [datetime]::TryParse($Text, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) { return $null }
    if ($parsed.Kind -eq [System.DateTimeKind]::Unspecified) { return $null }
    return $parsed.ToUniversalTime()
}

function ConvertFrom-HordeAnalystFindingLine {
    # PURE. One line of the findings file: { id; wake; at; bad } where bad is "" for a good line and the
    # reason for one that is not (A LINE THAT CANNOT BE READ IS NOT DROPPED, header). -Place names the
    # line when it has no id of its own.
    param([AllowEmptyString()][string]$Line, [Parameter(Mandatory = $true)][string]$Place)
    $badOne = { param([string]$Why) return [pscustomobject]@{ id = ("unreadable@" + $Place); wake = "round"; at = $null; bad = $Why } }
    $doc = $null
    try { $doc = ConvertFrom-HordeJson -Text $Line } catch { return (& $badOne "it is not JSON") }
    if ($doc -isnot [System.Management.Automation.PSCustomObject]) { return (& $badOne "it is not a JSON object") }
    $names = @($doc.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($n in $names) { if (@("v", "id", "at", "source", "wake", "text") -cnotcontains $n) { return (& $badOne ("it has the member '" + $(if ($n.Length -gt 40) { $n.Substring(0, 40) } else { $n }) + "', which a finding does not have")) } }
    foreach ($n in @("v", "id", "at", "source", "wake", "text")) { if ($names -cnotcontains $n) { return (& $badOne ("it has no member '" + $n + "'")) } }
    if (("" + $doc.v) -cne "1") { return (& $badOne "its v is not 1") }
    if ($doc.id -isnot [string] -or $doc.id -cnotmatch $script:HordeAnalystIdPattern) { return (& $badOne "its id is not 1 to 80 of A-Z a-z 0-9 . _ : -") }
    $at = ConvertFrom-HordeAnalystTime -Text $doc.at
    if ($null -eq $at) { return (& $badOne "its at is not a time with a zone") }
    if ($doc.source -isnot [string] -or $doc.source -cnotmatch $script:HordeAnalystSourcePattern) { return (& $badOne "its source is not 1 to 40 of A-Z a-z 0-9 . _ : -") }
    if ($doc.wake -isnot [string] -or $script:HordeAnalystWakes -cnotcontains $doc.wake) { return (& $badOne "its wake is not now, round or never") }
    if ($doc.text -isnot [string] -or $doc.text.Length -eq 0 -or $doc.text.Length -gt $script:HordeAnalystTextMost -or $doc.text -match '\p{Cc}') { return (& $badOne ("its text is not one line of 1 to " + $script:HordeAnalystTextMost + " characters")) }
    return [pscustomobject]@{ id = $doc.id; wake = $doc.wake; at = $at; bad = "" }
}

function Read-HordeAnalystFindings {
    # The findings appended to -Path since byte -Offset: known { items; offset; restarted }, items in file
    # order (ConvertFrom-HordeAnalystFindingLine's shape), offset where the next pass reads from. No file
    # is no findings yet. A file SHORTER than -Offset was replaced, not appended to: it is read from its
    # start and restarted says so. Unknown, with the reason, when the file cannot be read.
    param([Parameter(Mandatory = $true)][string]$Path, [long]$Offset = 0)
    if ($Offset -lt 0) { $Offset = 0 }
    $stream = $null
    try {
        try { $stream = Open-HordeSharedStream -Path $Path }
        catch {
            $cause = $_.Exception.GetBaseException()
            if ($cause -is [System.IO.FileNotFoundException] -or $cause -is [System.IO.DirectoryNotFoundException]) { return (New-HordeKnown -Value ([pscustomobject]@{ items = @(); offset = [long]0; restarted = ($Offset -gt 0) })) }
            return (New-HordeUnknown -Reason "the findings file could not be opened" -ErrorRecord $_)
        }
        $restarted = $false
        if ($stream.Length -lt $Offset) { $Offset = 0; $restarted = $true }
        $want = [long][System.Math]::Min($stream.Length - $Offset, $script:HordeAnalystReadMostBytes)
        $bytes = New-Object byte[] $want
        [void]$stream.Seek($Offset, [System.IO.SeekOrigin]::Begin)
        $got = 0
        while ($got -lt $want) { $n = $stream.Read($bytes, $got, [int]($want - $got)); if ($n -le 0) { break }; $got += $n }
        # Only whole lines: a partial last line waits for its newline (header).
        $end = -1
        for ($i = $got - 1; $i -ge 0; $i--) { if ($bytes[$i] -eq 10) { $end = $i; break } }
        $items = New-Object System.Collections.ArrayList
        if ($end -lt 0) { return (New-HordeKnown -Value ([pscustomobject]@{ items = @(); offset = $Offset; restarted = $restarted })) }
        $text = (New-Object System.Text.UTF8Encoding($false, $false)).GetString($bytes, 0, $end + 1)
        $at = $Offset
        foreach ($raw in @($text -split "`n")) {
            $place = "" + $at
            $at += [System.Text.Encoding]::UTF8.GetByteCount($raw) + 1
            $line = $raw.TrimEnd("`r").TrimStart([char]0xFEFF)
            if ($line.Trim() -eq "") { continue }
            [void]$items.Add((ConvertFrom-HordeAnalystFindingLine -Line $line -Place $place))
        }
        return (New-HordeKnown -Value ([pscustomobject]@{ items = @($items.ToArray()); offset = ($Offset + $end + 1); restarted = $restarted }))
    } catch {
        return (New-HordeUnknown -Reason "the findings file could not be read" -ErrorRecord $_)
    } finally { if ($null -ne $stream) { $stream.Dispose() } }
}

function Read-HordeAnalystMail {
    # The warchief's mail waiting in -Folder (not yet delivered), oldest first: known list of
    # { id; path; marker }, marker "" for one that waits for a round. A file not named as the mail
    # command names them is not mail and is left alone. No folder is no mail. Unknown when the folder
    # or a mail cannot be read: a mail that cannot be read could be the urgent one.
    param([Parameter(Mandatory = $true)][string]$Folder, [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Markers)
    if (-not [System.IO.Directory]::Exists($Folder)) { return (New-HordeKnown -Value @()) }
    $out = New-Object System.Collections.ArrayList
    try {
        $names = @([System.IO.Directory]::GetFiles($Folder) | ForEach-Object { [System.IO.Path]::GetFileName($_) } | Where-Object { $_ -cmatch $script:HordeAnalystMailNamePattern } | Sort-Object)
        foreach ($name in $names) {
            $path = [System.IO.Path]::Combine($Folder, $name)
            $start = ""
            $stream = Open-HordeSharedStream -Path $path
            try {
                $reader = New-Object System.IO.StreamReader($stream, (New-Object System.Text.UTF8Encoding($false)), $true)
                $buffer = New-Object char[] $script:HordeAnalystMarkerReadChars
                $n = $reader.Read($buffer, 0, $buffer.Length)
                if ($n -gt 0) { $start = [string]::new($buffer, 0, $n) }
            } finally { $stream.Dispose() }
            [void]$out.Add([pscustomobject]@{ id = [System.IO.Path]::GetFileNameWithoutExtension($name); path = $path; marker = (Get-HordeAnalystMailMarker -Text $start -Markers $Markers) })
        }
    } catch { return (New-HordeUnknown -Reason "the analyst's mail could not be read" -ErrorRecord $_) }
    return (New-HordeKnown -Value @($out.ToArray()))
}

function Read-HordeAnalystAcks {
    # The round ids the analyst has acked in -Path (its last $script:HordeAnalystAckTailBytes): known
    # string[]. No file is none acked. Unknown when the file cannot be read: an ack that cannot be read
    # is not "no ack", and no alert is raised on it.
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = $null
    try {
        try { $stream = Open-HordeSharedStream -Path $Path }
        catch {
            $cause = $_.Exception.GetBaseException()
            if ($cause -is [System.IO.FileNotFoundException] -or $cause -is [System.IO.DirectoryNotFoundException]) { return (New-HordeKnown -Value ([string[]]@())) }
            return (New-HordeUnknown -Reason "the ack file could not be opened" -ErrorRecord $_)
        }
        $from = [long][System.Math]::Max(0, $stream.Length - $script:HordeAnalystAckTailBytes)
        [void]$stream.Seek($from, [System.IO.SeekOrigin]::Begin)
        $reader = New-Object System.IO.StreamReader($stream, (New-Object System.Text.UTF8Encoding($false)), $true)
        $text = $reader.ReadToEnd()
        $ids = New-Object System.Collections.ArrayList
        foreach ($line in @($text -split "`n")) {
            $m = [regex]::Match($line.Trim(), $script:HordeAnalystAckPattern)
            if ($m.Success -and -not $ids.Contains($m.Groups[1].Value)) { [void]$ids.Add($m.Groups[1].Value) }
        }
        return (New-HordeKnown -Value ([string[]]$ids.ToArray()))
    } catch {
        return (New-HordeUnknown -Reason "the ack file could not be read" -ErrorRecord $_)
    } finally { if ($null -ne $stream) { $stream.Dispose() } }
}

function New-HordeAnalystRoundId {
    # A round's id: its time to the second, UTC, and its kind's first letter ("20261014T213000Z-r").
    # One pass sends at most one round, and a pass takes more than a second, so two never share one.
    param([Parameter(Mandatory = $true)][datetime]$Now, [Parameter(Mandatory = $true)][ValidateSet("now", "round", "heartbeat")][string]$Kind)
    return ($Now.ToUniversalTime().ToString("yyyyMMddTHHmmssZ", [System.Globalization.CultureInfo]::InvariantCulture) + "-" + $Kind.Substring(0, 1))
}

function Get-HordeAnalystRoundDecision {
    # PURE. What to do about the analyst this pass: { action; why; findings; mail; nextAt }.
    #   action    now        something waiting must wake it at once: a finding marked now, or a mail
    #                        whose first word is a marker. It carries EVERYTHING waiting, so the
    #                        batched items ride along rather than wake it again minutes later.
    #             round      something waits, and roundMinutes have passed since the last round.
    #             heartbeat  nothing waits, and heartbeatHours have passed since its last wake.
    #             none       nothing to do; nextAt says when a round or a heartbeat could be due.
    #   findings  the ids of the findings this wake carries (wake now or round; never is never carried).
    #   mail      the ids of the mail it carries.
    # -LastRoundAt: when the last round of any kind was sent ($null: never). -LastWakeAt: the last time
    # the analyst was woken by anything the caller knows of - a round, or a turn its transcript shows -
    # ($null: never, and a heartbeat is due, so a supervisor that has just started learns at once
    # whether the session answers). -Findings and -Mail are the readers' items; -Policy holds
    # roundMinutes and heartbeatHours.
    param(
        [Parameter(Mandatory = $true)][datetime]$Now,
        $LastRoundAt = $null,
        $LastWakeAt = $null,
        [AllowEmptyCollection()][object[]]$Findings = @(),
        [AllowEmptyCollection()][object[]]$Mail = @(),
        [Parameter(Mandatory = $true)]$Policy
    )
    $now = $Now.ToUniversalTime()
    $carry = @($Findings | Where-Object { $null -ne $_ -and "" + $_.wake -cne "never" })
    $urgent = @($carry | Where-Object { "" + $_.wake -ceq "now" }).Count + @($Mail | Where-Object { $null -ne $_ -and "" + $_.marker -cne "" }).Count
    $fids = [string[]]@($carry | ForEach-Object { "" + $_.id })
    $mids = [string[]]@($Mail | Where-Object { $null -ne $_ } | ForEach-Object { "" + $_.id })
    $answer = { param($Action, $Why, $Next) return [pscustomobject]@{ action = $Action; why = $Why; findings = $(if ($Action -ceq "now" -or $Action -ceq "round") { $fids } else { [string[]]@() }); mail = $(if ($Action -ceq "now" -or $Action -ceq "round") { $mids } else { [string[]]@() }); nextAt = $Next } }
    if ($urgent -gt 0) { return (& $answer "now" ("" + $urgent + " item(s) marked to wake it at once") $null) }
    $waiting = $fids.Count + $mids.Count
    if ($waiting -gt 0) {
        if ($null -eq $LastRoundAt) { return (& $answer "round" ("" + $waiting + " item(s) waiting, and no round has been sent before") $null) }
        $due = ([datetime]$LastRoundAt).ToUniversalTime().AddMinutes([int]$Policy.roundMinutes)
        if ($now -ge $due) { return (& $answer "round" ("" + $waiting + " item(s) waiting, and the last round was " + [int]($now - ([datetime]$LastRoundAt).ToUniversalTime()).TotalMinutes + " minutes ago") $null) }
        return (& $answer "none" ("" + $waiting + " item(s) wait for the next round") $due)
    }
    if ($null -eq $LastWakeAt) { return (& $answer "heartbeat" "nothing waits, and no wake of it is known" $null) }
    $beat = ([datetime]$LastWakeAt).ToUniversalTime().AddHours([int]$Policy.heartbeatHours)
    if ($now -ge $beat) { return (& $answer "heartbeat" ("nothing waits, and it has not been woken for " + [int]($now - ([datetime]$LastWakeAt).ToUniversalTime()).TotalHours + " hours") $null) }
    return (& $answer "none" "nothing waits" $beat)
}

function Get-HordeAnalystAckAlerts {
    # PURE. Which rounds to tell about now: the ids of those sent at least ackMinutes ago that the ack
    # file does not hold and that were not told about before. -Rounds: { id; at; alerted }, -Acked the
    # acked ids, -Policy holds ackMinutes.
    param([Parameter(Mandatory = $true)][datetime]$Now, [AllowEmptyCollection()][object[]]$Rounds = @(), [AllowEmptyCollection()][string[]]$Acked = @(), [Parameter(Mandatory = $true)]$Policy)
    $out = New-Object System.Collections.ArrayList
    foreach ($r in @($Rounds)) {
        if ($null -eq $r -or $r.alerted -eq $true -or $Acked -ccontains ("" + $r.id)) { continue }
        if ($Now.ToUniversalTime() -ge ([datetime]$r.at).ToUniversalTime().AddMinutes([int]$Policy.ackMinutes)) { [void]$out.Add("" + $r.id) }
    }
    return [string[]]$out.ToArray()
}

function Format-HordeAnalystRoundBody {
    # PURE. The words of one round (FIXED WORDS, header): its id and kind, how many findings and mails it
    # carries and where they are, and the two things the analyst must do before it ends its turn.
    # -Handover is the path of the analyst's handover file, or "" when the caller keeps none.
    param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)][ValidateSet("now", "round", "heartbeat")][string]$Kind,
          [int]$Findings = 0, [int]$Unreadable = 0, [AllowEmptyCollection()][string[]]$MailIds = @(), [AllowEmptyCollection()][string[]]$Markers = @(),
          [Parameter(Mandatory = $true)]$Paths, [string]$Handover = "", [long]$FromOffset = 0)
    $lines = New-Object System.Collections.ArrayList
    $head = @{ now = "ANALYST ROUND " + $Id + " - AT ONCE"; round = "ANALYST ROUND " + $Id; heartbeat = "ANALYST ROUND " + $Id + " - HEARTBEAT" }[$Kind]
    [void]$lines.Add($head)
    if ($Kind -ceq "heartbeat") { [void]$lines.Add("Nothing new has come for a while. Check that nothing you hold has gone stale.") }
    if ($Findings -gt 0) {
        [void]$lines.Add("" + $Findings + " new finding(s) in " + $Paths.findings + " from byte " + $FromOffset + " on." + $(if ($Unreadable -gt 0) { " " + $Unreadable + " of those line(s) could not be read; look at them there." } else { "" }))
    }
    if (@($MailIds).Count -gt 0) {
        [void]$lines.Add("" + @($MailIds).Count + " mail(s) from the warchief, in " + $Paths.delivered + ": " + ((@($MailIds) | ForEach-Object { $_ + ".txt" }) -join ", ") + "." + $(if (@($Markers).Count -gt 0) { " Marked: " + ((@($Markers) | Sort-Object -Unique) -join ", ") + "." } else { "" }))
    }
    if ($Handover -ne "") { [void]$lines.Add("Before you end this turn, rewrite your handover file: " + $Handover) }
    [void]$lines.Add("Then append this one line to " + $Paths.acks + ": round " + $Id + " done")
    return ($lines -join "`n")
}
