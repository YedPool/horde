# agents/claude-code/Conversation.ps1 - the conversation adapter for Claude Code: a Thrall's turns.
#
# WHAT IT IS (relay design 2026-10-09, Q2 and PR plan item 9). The first adapter of conversations/Port.ps1.
# It finds a horde's Thrall through the fleet's session registry and tails that session's transcript,
# <store>/projects/<slug>/<sessionId>.jsonl, one JSON object per line. Its rules were proven by relay
# spike S4 (2026-10-09) and confirmed against the live Thrall transcript on 2026-10-10 by a probe that
# printed counts of shapes and never text (27.4 MB, 16,276 lines).
#
# THIS READER KEEPS TEXT, AND ONLY THIS MUCH OF IT. core/Transcript.ps1, the metrics port, forbids
# keeping any text; this is the separate, reviewed reader that keeps the words of a person's prompt and
# of the model's reply, and nothing else of a line. It reads by allowlist: type, isSidechain, isMeta,
# isCompactSummary, isApiErrorMessage, origin.kind, uuid, timestamp, message.id, message.model and
# message.content - and of message.content only a string, or the type and text of a block. Every other
# key of a line (tool inputs, tool results, thinking, paths, usage) is dropped in memory. It never
# redacts: the port does, for every adapter (conversations/Port.ps1, REDACTION IS HERE).
#
# FINDING THE THRALL. The fleet's registry (<root>/registry/sessions/<sessionId>.json, read by
# core/WezfleetState.ps1's Read-HordeRegistry) holds one record per session. The Thrall is the one live
# record - not retired - whose role is the one asked for (warchief; the registry spells it "master",
# core/roles.json), and its transcriptPath field names the file (88 of 88 records have it, 2026-10-10).
# None: absent. Two or more: unknown, never one chosen. A registry that could not be read whole: unknown,
# because the record that could not be read may be the Thrall's. A transcriptPath whose file name is not
# the record's session id is unknown: it is someone else's file. The process is NOT checked to be
# running (core/SessionSeat.ps1's Get-HordeRoleSeat does that, from the harness's control files): a
# transcript says what was said whether its writer still runs or not, and reading a stopped Thrall's
# last words is what a phone should do. The registry root is -Options.registryRoot, else the fleet's own
# (Get-HordeWezfleetRoot).
#
# THE TAIL (S4). The file is opened sharing read, write and delete (core/ReadShared.ps1: the harness
# keeps appending, and a reader must never block it), read from the saved byte offset, at most MaxBytes,
# and only up to the LAST LINE END in what was read: a trailing line without one is being written, and is
# read next time, whole. The offset saved is the end of the last line consumed.
#   - A LINE LONGER THAN MaxBytes cannot be held by one read. It is skipped, in 64 KiB steps that keep
#     nothing, as an anomaly - unless it has no line end yet, when it is left for a later read.
#   - A BATCH STOPS AT MaxTurns, at a line boundary. A line holding more text blocks than the batch has
#     room for is split: the position also says how many turns of the line at the offset were already
#     handed over, so the next read starts inside it and no turn is given twice.
#   - ROTATION. The position keeps a hash of the file's first bytes (up to 4 KiB, never past the offset).
#     The file is taken to be rewritten - and read again from the start, reset rotated - when it is now
#     shorter than the offset, when those first bytes changed, or when the byte before the offset is not
#     a line end. A file rewritten to the same first 4 KiB and longer than the offset, with a line end
#     exactly at the offset, is not seen; the harness has never been seen rewriting a transcript at all.
#   - A NEW SESSION (/clear) is a new session id, a new registry record and a new file (S4); the port
#     sees the session change and starts it from the beginning. The OLD session is still found by its id
#     (the port's A PAST SESSION BY ITS ID): its registry record, retired or not, still names the role and
#     its transcript, so a caller can read its tail to the end before moving on.
#
# WHAT IS A TURN (S4, and the 2026-10-10 probe):
#   - USER: a user line whose origin.kind is "human" (485 in the live file), its content a string or text
#     blocks. NOT a tool result (1,219: content of tool_result blocks), a task notification (83, origin
#     task-notification), a meta line (116, isMeta: command wrappers and reminders), a compaction summary
#     (2, isCompactSummary), or an interruption marker (5: text blocks with no origin).
#   - ASSISTANT: each text block of an assistant line. One API response is written as one line per
#     content block (2,719 assistant lines, every one holding exactly one block), and one response's
#     lines are interleaved with tool results (66 times a message.id came back after other lines). So a
#     text block is ONE turn, with the line's uuid as its id and message.id as its groupId: grouping in
#     the reader would give a turn whose text depends on where a read happened to stop. Thinking and
#     tool_use blocks are not turns.
#   - SYSTEM: an assistant line the harness wrote itself to report an API error (model "<synthetic>" or
#     isApiErrorMessage; 4 in the live file): the founder should see that the Thrall stopped on an error.
#   - SKIPPED ALWAYS: every line of a side conversation (isSidechain), and every other line type
#     (system turn_duration and compact_boundary, attachments, bookkeeping such as last-prompt and mode).
# A PREFILTER skips lines that cannot be a turn before they are parsed: a candidate user line holds
# "kind":"human" and a candidate assistant line "type":"text" (S4: 10,373 of 16,247 lines skipped, the
# whole 27 MB file read in 1,531 ms). The harness writes compact JSON; a line the prefilter passes is
# still judged on its parsed fields, so it can only skip, never admit.
#
# No Set-StrictMode here: dot-sourced (see core/Tristate.ps1). Needs conversations/Port.ps1 loaded first.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\ReadShared.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\WezfleetState.ps1")

$script:ClaudeCodeConversationHeadBytes = 4096
# POWERSHELL 7 READS A DATE-SHAPED STRING AS A [datetime] (measured 2026-10-10 on 7.6: every timestamp came
# back a DateTime, and the conformance suite's timestamps case failed under 7 and passed under 5.1). 7.5
# and later can be told not to (-DateKind String); 5.1 never does it. On a 7 before 7.5 the value is
# turned back into ISO text (ConvertTo-ClaudeCodeText), which keeps the time but may not keep a prompt
# that was nothing but a date exactly as typed.
$script:ClaudeCodeJsonDateKind = (Get-Command ConvertFrom-Json).Parameters.ContainsKey("DateKind")
$script:ClaudeCodeConversationSkipStep = 65536
# The position this adapter writes: v1.<offset>.<turns of the line at the offset already given>.<head length>.<head hash>
$script:ClaudeCodeConversationPositionPattern = '\Av1\.(\d{1,15})\.(\d{1,6})\.(\d{1,5})\.([0-9a-f]{16}|-)\z'

function Find-ClaudeCodeThrall {
    # The registry record holding -Role: known { session; locator }, absent or unknown (header). -Session
    # asks for that one session's record instead, retired or not, and it must name -Role too: a session
    # that never held the role is not the Thrall's, so it is absent.
    param([string]$Root, [string]$Role, [string]$Session = "")
    $registry = Read-HordeRegistry -Root $Root
    if ($registry.complete.state -cne "known") { return (New-HordeUnknown -Reason ("the session records could not all be read, so which session is the " + $Role + " cannot be told: " + $registry.complete.reason)) }
    $table = Get-HordeRoleTable
    $holders = New-Object System.Collections.ArrayList
    foreach ($id in @($registry.records.Keys | Sort-Object)) {
        $record = $registry.records[$id].record
        if ($Session -ne "") { if ("$id" -cne $Session) { continue } }
        else {
            $retired = Get-HordeField -Record $record -Name "retired"
            if ($retired.state -ceq "known" -and [bool]$retired.value) { continue }
        }
        $named = (Read-HordeRecordRole -Record $record -Table $table).role
        if ($named.state -ceq "known" -and "$($named.value)" -ceq $Role) { [void]$holders.Add([pscustomobject]@{ id = "$id"; record = $record }) }
    }
    if ($holders.Count -eq 0) { return (New-HordeAbsent -Note $(if ($Session -ne "") { "no session record of that id names the role " + $Role } else { "no live session's record names the role " + $Role })) }
    if ($holders.Count -gt 1) { return (New-HordeUnknown -Reason ("" + $holders.Count + " live sessions each say they are the " + $Role + " (" + (@($holders | ForEach-Object { $_.id }) -join ", ") + "); one is never chosen over another")) }
    $one = $holders[0]
    $tp = Get-HordeField -Record $one.record -Name "transcriptPath"
    if ($tp.state -cne "known" -or $tp.value -isnot [string] -or $tp.value -eq "") { return (New-HordeUnknown -Reason ("the " + $Role + "'s record (" + $one.id + ") does not say where its transcript is")) }
    if ([System.IO.Path]::GetFileNameWithoutExtension($tp.value) -ine $one.id -or [System.IO.Path]::GetExtension($tp.value) -ine ".jsonl") { return (New-HordeUnknown -Reason ("the " + $Role + "'s record (" + $one.id + ") names a transcript that is not its own session's file")) }
    return (New-HordeKnown -Value ([pscustomobject]@{ session = $one.id; locator = $tp.value }))
}

function Get-ClaudeCodeHeadHash {
    # The first 16 hex digits of the SHA-256 of -Count bytes from the start of -Stream.
    param($Stream, [int]$Count)
    $buf = New-Object byte[] $Count
    $Stream.Position = 0
    $got = 0
    while ($got -lt $Count) { $n = $Stream.Read($buf, $got, $Count - $got); if ($n -le 0) { break }; $got += $n }
    if ($got -lt $Count) { return "" }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $h = $sha.ComputeHash($buf) } finally { $sha.Dispose() }
    return ((($h[0..7]) | ForEach-Object { $_.ToString("x2") }) -join "")
}

function ConvertTo-ClaudeCodeText {
    # A parsed string as text; a date-shaped string that a parser made a [datetime] as ISO text again.
    param($Value)
    if ($Value -is [string]) { return $Value }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ", [System.Globalization.CultureInfo]::InvariantCulture) }
    return $null
}

function Get-ClaudeCodeMember {
    # One member of a parsed line, or $null, without failing under strict mode.
    param($Object, [string]$Name)
    if ($null -eq $Object -or $Object -isnot [System.Management.Automation.PSCustomObject]) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function ConvertFrom-ClaudeCodeLine {
    # The turns one transcript line holds, as raw port turns (header, WHAT IS A TURN): none for most.
    param([string]$Line)
    $isUser = $Line.IndexOf('"kind":"human"', [System.StringComparison]::Ordinal) -ge 0 -and $Line.IndexOf('"type":"user"', [System.StringComparison]::Ordinal) -ge 0
    $isAssistant = $Line.IndexOf('"type":"assistant"', [System.StringComparison]::Ordinal) -ge 0 -and $Line.IndexOf('"type":"text"', [System.StringComparison]::Ordinal) -ge 0
    if (-not $isUser -and -not $isAssistant) { return @() }
    if ($script:ClaudeCodeJsonDateKind) { $j = $Line | ConvertFrom-Json -DateKind String } else { $j = $Line | ConvertFrom-Json }
    if ($j -isnot [System.Management.Automation.PSCustomObject]) { return @() }
    if ((Get-ClaudeCodeMember $j "isSidechain") -eq $true) { return @() }
    $type = Get-ClaudeCodeMember $j "type"
    $uuid = Get-ClaudeCodeMember $j "uuid"
    $time = ConvertTo-ClaudeCodeText (Get-ClaudeCodeMember $j "timestamp")
    $message = Get-ClaudeCodeMember $j "message"
    $content = Get-ClaudeCodeMember $message "content"
    if ($uuid -isnot [string]) { return @() }
    $out = New-Object System.Collections.ArrayList
    if ($type -ceq "user") {
        if ((Get-ClaudeCodeMember $j "isMeta") -eq $true -or (Get-ClaudeCodeMember $j "isCompactSummary") -eq $true) { return @() }
        if ((Get-ClaudeCodeMember (Get-ClaudeCodeMember $j "origin") "kind") -cne "human") { return @() }
        $text = ""
        if ($content -is [string] -or $content -is [datetime]) { $text = ConvertTo-ClaudeCodeText $content }
        else {
            $parts = @(@($content) | Where-Object { (Get-ClaudeCodeMember $_ "type") -ceq "text" } | ForEach-Object { ConvertTo-ClaudeCodeText (Get-ClaudeCodeMember $_ "text") } | Where-Object { $null -ne $_ })
            $text = $parts -join "`n"
        }
        if ($text -match '\S') { [void]$out.Add([pscustomobject]@{ role = "user"; text = $text; time = $time; turnId = $uuid }) }
        return @($out)
    }
    if ($type -ceq "assistant") {
        $role = "assistant"
        if ((Get-ClaudeCodeMember $message "model") -ceq "<synthetic>" -or (Get-ClaudeCodeMember $j "isApiErrorMessage") -eq $true) { $role = "system" }
        $group = Get-ClaudeCodeMember $message "id"
        $k = 0
        foreach ($b in @($content)) {
            if ((Get-ClaudeCodeMember $b "type") -cne "text") { continue }
            $text = ConvertTo-ClaudeCodeText (Get-ClaudeCodeMember $b "text")
            if ($text -isnot [string] -or $text -notmatch '\S') { continue }
            $t = [ordered]@{ role = $role; text = $text; time = $time; turnId = $(if ($k -eq 0) { $uuid } else { $uuid + "#" + $k }) }
            if ($group -is [string] -and $group -ne "") { $t["groupId"] = $group }
            [void]$out.Add([pscustomobject]$t)
            $k++
        }
    }
    return @($out)
}

function Read-ClaudeCodeConversation {
    # The port's Read (conversations/Port.ps1, ADAPTER CONTRACT), over one transcript (header, THE TAIL).
    param($Source, [string]$Position, [int]$MaxTurns, [long]$MaxBytes)
    $offset = [long]0; $skipTurns = 0; $headLen = 0; $headHash = ""
    if ($Position -ne "") {
        if ($Position -cnotmatch $script:ClaudeCodeConversationPositionPattern) { return (New-HordeUnknown -Reason "the position is not one this adapter writes") }
        $offset = [long]$Matches[1]; $skipTurns = [int]$Matches[2]; $headLen = [int]$Matches[3]; $headHash = $(if ($Matches[4] -ceq "-") { "" } else { $Matches[4] })
    }
    $path = $Source.locator
    if (-not [System.IO.File]::Exists($path)) {
        # A Thrall that has not written its first line has no file yet: from the start, that is empty.
        if ($offset -eq 0) { return (New-HordeKnown -Value ([pscustomobject]@{ turns = @(); position = $Position; more = $false; reset = ""; anomalies = @() })) }
        return (New-HordeUnknown -Reason "the transcript read before is no longer there")
    }
    $anomalies = New-Object System.Collections.ArrayList
    $reset = ""
    $stream = Open-HordeSharedStream -Path $path
    try {
        $length = $stream.Length
        if ($offset -gt 0) {
            $rotated = ""
            if ($length -lt $offset) { $rotated = "it is shorter than the cursor" }
            elseif ($headLen -gt 0 -and (Get-ClaudeCodeHeadHash -Stream $stream -Count $headLen) -cne $headHash) { $rotated = "its first bytes changed" }
            else {
                $stream.Position = $offset - 1
                if ($stream.ReadByte() -ne 10) { $rotated = "no line ends where the cursor stands" }
            }
            if ($rotated -ne "") {
                [void]$anomalies.Add("the transcript was rewritten (" + $rotated + "); it is read again from its start")
                $offset = 0; $skipTurns = 0; $headLen = 0; $headHash = ""; $reset = "rotated"
            }
        }
        $turns = New-Object System.Collections.ArrayList
        $consumed = $offset
        $more = $false
        $unreadable = 0
        while ($consumed -lt $length) {
            $window = [long][Math]::Min([long]($length - $consumed), $MaxBytes)
            $buf = New-Object byte[] $window
            $stream.Position = $consumed
            $got = 0
            while ($got -lt $window) { $n = $stream.Read($buf, $got, [int]($window - $got)); if ($n -le 0) { break }; $got += $n }
            $lastLf = [Array]::LastIndexOf($buf, [byte]10, $got - 1)
            if ($lastLf -lt 0) {
                if ($consumed + $got -ge $length) { break }
                # A LINE LONGER THAN A READ MAY HOLD: skipped in steps that keep nothing, if it is whole.
                $at = $consumed + $got
                $step = New-Object byte[] $script:ClaudeCodeConversationSkipStep
                $end = -1
                while ($at -lt $length) {
                    $stream.Position = $at
                    $n = $stream.Read($step, 0, $step.Length)
                    if ($n -le 0) { break }
                    $i = [Array]::IndexOf($step, [byte]10, 0, $n)
                    if ($i -ge 0) { $end = $at + $i; break }
                    $at += $n
                }
                if ($end -lt 0) { break }
                [void]$anomalies.Add("a line of " + ($end + 1 - $consumed) + " bytes, more than the " + $MaxBytes + " a read may hold, was skipped")
                $consumed = $end + 1; $skipTurns = 0
                $more = $true
                break
            }
            $start = 0
            $stop = $false
            while ($start -le $lastLf) {
                $nl = [Array]::IndexOf($buf, [byte]10, $start, $lastLf - $start + 1)
                # Never true while lastLf is a line end; a guard, so a wrong lastLf ends the scan instead
                # of looping on the same bytes (a mutation run of the last-line-end rule spun 12 minutes).
                if ($nl -lt 0) { break }
                $lineTurns = @()
                if ($nl -gt $start) {
                    $text = [System.Text.Encoding]::UTF8.GetString($buf, $start, $nl - $start)
                    # THE PREFILTER IS ALSO HERE, before the call: a function call per line cost more than
                    # the whole parse of the lines that matter (2026-10-10, 27.9 MB synthetic file: 6.5 s
                    # with the call on every line).
                    if (($text.IndexOf('"kind":"human"', [System.StringComparison]::Ordinal) -ge 0) -or ($text.IndexOf('"type":"text"', [System.StringComparison]::Ordinal) -ge 0)) {
                        try { $lineTurns = @(ConvertFrom-ClaudeCodeLine -Line $text.TrimEnd([char]13)) } catch { $unreadable++ }
                    }
                }
                if ($skipTurns -gt 0) { $lineTurns = @($lineTurns | Select-Object -Skip $skipTurns) }
                $room = $MaxTurns - $turns.Count
                if ($lineTurns.Count -gt $room) {
                    foreach ($t in @($lineTurns | Select-Object -First $room)) { [void]$turns.Add($t) }
                    $skipTurns = $skipTurns + $room
                    $consumed = $consumed + $start
                    $stop = $true; $more = $true
                    break
                }
                foreach ($t in $lineTurns) { [void]$turns.Add($t) }
                $skipTurns = 0
                $start = $nl + 1
                if ($turns.Count -ge $MaxTurns) {
                    $consumed = $consumed + $start
                    $stop = $true
                    $more = ($consumed -lt $length)
                    break
                }
            }
            if ($stop) { break }
            $consumed = $consumed + $lastLf + 1
            if ($consumed -lt $length -and $window -ge $MaxBytes) { $more = $true; break }
        }
        if ($unreadable -gt 0) { [void]$anomalies.Add("" + $unreadable + " line(s) that looked like turns could not be parsed and were skipped") }
        # THE HEAD is hashed once there is something consumed, over at most the bytes consumed.
        if ($headLen -eq 0 -and $consumed -gt 0) {
            $headLen = [int][Math]::Min([long]$script:ClaudeCodeConversationHeadBytes, $consumed)
            $headHash = Get-ClaudeCodeHeadHash -Stream $stream -Count $headLen
        }
    } finally { $stream.Dispose() }
    $pos = "v1." + $consumed + "." + $skipTurns + "." + $headLen + "." + $(if ($headHash -eq "") { "-" } else { $headHash })
    if ($consumed -eq 0 -and $skipTurns -eq 0) { $pos = "" }
    return (New-HordeKnown -Value ([pscustomobject]@{ turns = @($turns.ToArray()); position = $pos; more = $more; reset = $reset; anomalies = @($anomalies.ToArray()) }))
}

$null = Register-HordeConversationAdapter -Folder $PSScriptRoot -Locate {
    param($Request)
    $root = ""
    if ($null -ne $Request.options -and $Request.options.Contains("registryRoot")) { $root = "" + $Request.options["registryRoot"] }
    if ($root -eq "") { $root = Get-HordeWezfleetRoot }
    $asked = ""
    if ($null -ne $Request.PSObject.Properties["session"]) { $asked = "" + $Request.session }
    return (Find-ClaudeCodeThrall -Root $root -Role $Request.role -Session $asked)
} -Read {
    param($Source, [string]$Position, [int]$MaxTurns, [long]$MaxBytes)
    return (Read-ClaudeCodeConversation -Source $Source -Position $Position -MaxTurns $MaxTurns -MaxBytes $MaxBytes)
}
