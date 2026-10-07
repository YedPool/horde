# agents/claude-code/Idle.ps1 - the idle reader for Claude Code session transcripts: what the
# transcript says about whether the session is mid-turn or holds live work (core/Idle.ps1's turn
# state; planning/idle-session-reaper.md sections 1.3, 1.5, 1.6 and protections P8, P12, P13).
#
# WHAT IT READS. One session transcript, <store>/projects/<slug>/<sessionId>.jsonl, streamed once
# through core/Transcript.ps1's shared reader, which never blocks the harness's own writes. It keeps ids,
# kinds and times; message text is looked at only to find a task id or a cron id, and never kept.
#
# THE RULES, each a check in agents/claude-code/test/test-idle.ps1, each measured read-only on this
# machine's transcripts (2026-10-05: 74 written in the last 8 days, 224 in the last 30):
#   - A TURN ENDS at a system/turn_duration line; its pendingBackgroundAgentCount is the background
#     agents still running (absent means none: 1,427 lines carry it, and only when it is above 0).
#   - THE TURN BOUNDARY (design 1.5). After the last turn end only these may follow: untimestamped
#     metadata of a kind the reader knows, and the timestamped kinds of $script:ClaudeCodeBoundaryKinds,
#     which together started no turn in 4,939 turn ends. Everything else - a prompt, a user meta line
#     (a local slash command: a known false keep, safe), a queue operation, an attachment, a scheduled
#     task firing, a compaction, a kind never seen - is a blocker.
#   - BACKGROUND TASKS (P12) start when a tool result announces one. A SHELL task is recognised by its
#     STRUCTURE, an id followed by the file its output goes to ("ID: x" or "(ID: x)", then "Output is
#     being written to"), never by the phrase before it: measured 2026-10-07 over 30 days, 3,678
#     "Command running in background with ID: x.", 280 "Command did not complete within its Ns timeout
#     and was moved to the background (ID: x)." and 11 "Command was manually backgrounded by user with
#     ID: x." The first version knew only the first phrase and called 27 working sessions idle (review
#     of #93, F1; the founder's run-complete-handoff hook already counted the timeout shape as "a launch
#     too"). Monitors ("Monitor started (task x"; 47), async agents ("Async agent launched successfully"
#     with "agentId: x"; 314) and Workflows ("Workflow launched in ... Task ID: x"; 3) keep their own.
#     A SUBAGENT'S tasks start in <session>/subagents/agent-*.jsonl and are announced to the MAIN
#     transcript when they finish, so those files are read for starts too (review of #93, F2: 17 working
#     sessions called idle). They finish at a notification the HARNESS marked as one (agents/claude-code/Transcript.ps1,
#     Test-ClaudeCodeNotificationOrigin: never text a person pasted) whose status is completed, failed,
#     killed or stopped and whose note is not interim (2,275, 44, 195, 11; interim notes say the agent
#     still has work running), or at a TaskStop that succeeded. A Monitor's event notifications carry
#     no status and finish nothing. A notification that is not final, about a task no start was seen
#     for, is an unknown task: some kind this reader does not recognise is running.
#     Measured: on 1,625 of 1,856 turn ends with such a task open, pendingBackgroundAgentCount was 0 or
#     absent, which is why tasks are read here and not inferred from the pending count.
#   - QUEUED INPUT (P13): queue-operation enqueue, then dequeue or remove. Counted over a whole file
#     they never balance, because a process can end with items queued; since this process started they
#     balance on all 8 live sessions measured. An operation the reader does not know is refused.
#   - CRONS AND WAKES (P8): CronCreate makes a job, named in its result ("Scheduled recurring job
#     a1b2c3d4 ..."; 15 of 15 results); CronDelete with that id ends it; a one-shot job ends when
#     system/scheduled_task_fire names it (its taskId). A recurring job expires 7 days after it was
#     made (the harness's own expiry, from the review of PR #84). A job whose id cannot be read still
#     counts, and cannot be deleted by id: it holds until it expires. ScheduleWakeup asks for a wake at
#     its time plus delaySeconds (61 of 84 calls carry it); a call that only says stop (23) is not a
#     wake.
#   - EVERY TIME HAS A ZONE OR THE AGE IS UNKNOWN, and a time more than the clock skew allowance in the
#     future makes it unknown too (core/Tristate.ps1, HordeClockSkewSeconds). The age is never the
#     file's modification time.
#   - TASKS, CRONS, WAKES AND THE QUEUE COUNT FROM -Since, the process's start: they live in the
#     process and die with it. A line whose time cannot be placed counts, which can only hold a session.
#   - THE VERSION SURVEY (design 1.6): every kind each harness version wrote since -Since is checked
#     against $script:ClaudeCodeKnownKinds, the kinds seen in 224 transcripts over 30 days (versions
#     2.1.268 to 2.1.285). A version that wrote anything else is unsurveyed for this session.
#   - ANY LINE AFTER THE LAST TURN END THAT CANNOT BE READ MAKES THE BOUNDARY UNKNOWN, never idle: a line
#     that does not parse, one nested past the parser's limit, a NUL-filled crash tail (all skipped by
#     the shared reader, seen here as a gap in the line numbers), a last line still being written, and an
#     untimestamped line of any kind but the metadata of $script:ClaudeCodeMetadataKinds (review of #93,
#     F3 and F4). A skipped line before the last turn end is counted (parseSkipped) and decides nothing.
#   - A CRON ENDS ONLY AT A CronDelete THAT SUCCEEDED - its result, not its call (review of #93, F5).
#   - THE REMOTE CONTROL LINK is reported from the bridge-session line, and holds nothing (founder,
#     2026-10-05: Remote Control activity shows in the transcript like any other).
#
# No Set-StrictMode here: dot-sourced (see core/Tristate.ps1). Needs core/Tristate.ps1,
# core/ReadShared.ps1, core/Transcript.ps1, core/Idle.ps1 and agents/claude-code/Transcript.ps1.

# Every line kind seen in 224 transcripts written in the 30 days to 2026-10-05: a line's kind is its
# type, or system/<subtype>; "(empty)" is a line holding an empty object (62 of them).
$script:ClaudeCodeKnownKinds = @("assistant", "user", "attachment", "queue-operation", "last-prompt", "mode", "permission-mode", "bridge-session",
    "atis-latch", "ai-title", "pr-link", "agent-name", "custom-title", "history-suppression", "file-history-snapshot", "file-history-delta",
    "frame-link", "cost-state", "artifact-autoreact-ledger", "artifact-comment-monitor", "(empty)",
    "system/stop_hook_summary", "system/turn_duration", "system/scheduled_task_fire", "system/away_summary", "system/local_command",
    "system/informational", "system/compact_boundary", "system/bridge_status", "system/model_refusal_no_fallback")
# The kinds whose lines carry no time and may follow a turn end: the harness's metadata, every one seen
# untimestamped after a turn end in 74 transcripts (design I-17). Any other untimestamped line there is
# unknown.
$script:ClaudeCodeMetadataKinds = @("last-prompt", "mode", "permission-mode", "bridge-session", "atis-latch", "ai-title", "agent-name", "custom-title",
    "history-suppression", "file-history-snapshot", "cost-state", "artifact-autoreact-ledger", "artifact-comment-monitor", "(empty)")
# Timestamped kinds that followed a turn end without starting a turn (design I-17).
$script:ClaudeCodeBoundaryKinds = @("system/away_summary", "system/bridge_status", "system/informational", "system/local_command", "pr-link", "frame-link", "file-history-delta")
$script:ClaudeCodeFinalTaskStatuses = @("completed", "failed", "killed", "stopped")
$script:ClaudeCodeCronExpiryDays = 7
$script:ClaudeCodeTaskStarts = @(
    @{ kind = "shell"; pattern = 'ID: ([A-Za-z0-9]+)\)?\.?\s*Output is being written to' },
    @{ kind = "monitor"; pattern = 'Monitor started \(task ([A-Za-z0-9]+)' },
    @{ kind = "workflow"; pattern = 'Workflow launched in [^\r\n]*?Task ID: ([A-Za-z0-9]+)' },
    @{ kind = "agent"; pattern = 'Async agent launched successfully[\s\S]*?agentId: ([A-Za-z0-9]+)' }
)

function Get-ClaudeCodeIdleKind {
    # A line's kind: its type, or system/<subtype>.
    param($Value)
    $type = $Value["type"]
    if ($null -eq $type) { if ($Value.Count -eq 0) { return "(empty)" }; return "(untyped)" }
    if ("$type" -ceq "system") { return ("system/" + $Value["subtype"]) }
    return "$type"
}

function Get-ClaudeCodeResultText {
    # The text of a tool result's content: a string, or its text blocks joined. Looked at, never kept.
    param($Content)
    if ($Content -is [string]) { return $Content }
    return (Get-ClaudeCodeText $Content)
}

function Add-ClaudeCodeIdleNotification {
    # Apply one harness-marked notification to the open and unknown task lists.
    param($St, [string]$Text)
    $n = Get-ClaudeCodeNotification -Text $Text
    if ($n.taskId -eq "") { return }
    $final = ($script:ClaudeCodeFinalTaskStatuses -ccontains $n.status) -and (@("final", "none") -ccontains $n.noteKind)
    if ($St.tasks.ContainsKey($n.taskId)) { if ($final) { $St.tasks.Remove($n.taskId) }; return }
    if ($final) { $St.unknownTasks.Remove($n.taskId) } else { $St.unknownTasks[$n.taskId] = $n.status }
}

function Add-ClaudeCodeIdleToolResult {
    # Apply one tool result (a cron made, a task stopped, a cron deleted, a task started) to the state.
    param($St, [string]$Id, [bool]$Err, [string]$Text)
    if ($St.cronCalls.ContainsKey($Id)) {
        $c = $St.cronCalls[$Id]; $St.cronCalls.Remove($Id)
        if (-not $Err) {
            $m = [regex]::Match($Text, 'job ([0-9a-f]{8})\b')
            $cid = "?" + $Id; if ($m.Success) { $cid = $m.Groups[1].Value }
            $St.crons[$cid] = $c
        }
    }
    if ($St.stops.ContainsKey($Id)) { if (-not $Err) { $St.tasks.Remove($St.stops[$Id]) }; $St.stops.Remove($Id) }
    if ($St.deletes.ContainsKey($Id)) { if (-not $Err) { $St.crons.Remove($St.deletes[$Id]) }; $St.deletes.Remove($Id) }
    if ($Err) { return }
    foreach ($s in $script:ClaudeCodeTaskStarts) {
        $m = [regex]::Match($Text, $s.pattern)
        if ($m.Success) { $St.tasks[$m.Groups[1].Value] = $s.kind; break }
    }
}

function Read-ClaudeCodeSubagentTasks {
    # The background tasks this session's subagents started since -Since: <session>/subagents/agent-*.jsonl.
    # A file not written since -Since holds no line since then, so it is not opened. Their notifications
    # arrive in the main transcript, which is read after these.
    param($St, [string]$Path, [datetime]$Since)
    $dir = Join-Path ([System.IO.Path]::ChangeExtension($Path, $null).TrimEnd(".")) "subagents"
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter "agent-*.jsonl" -File | Sort-Object Name)) {
        if ($f.LastWriteTimeUtc -lt $Since) { continue }
        $visitSub = {
            param($ln, $v)
            $t = $null
            if ($null -ne $v["timestamp"]) { $t = ConvertTo-HordeUtcTime $v["timestamp"] }
            if ($null -ne $t -and $t -lt $Since) { return }
            $content = Get-HordeJsonPath $v "message.content"
            if ("$($v["type"])" -ceq "assistant") {
                foreach ($b in @($content)) {
                    if ($b -isnot [System.Collections.IDictionary] -or $b["type"] -ne "tool_use" -or $b["input"] -isnot [System.Collections.IDictionary]) { continue }
                    if ("$($b["name"])" -ceq "TaskStop") { $St.stops["$($b["id"])"] = "$($b["input"]["task_id"])" }
                }
                return
            }
            if ("$($v["type"])" -cne "user") { return }
            if (Test-ClaudeCodeNotificationOrigin -Origin $v["origin"]) { Add-ClaudeCodeIdleNotification -St $St -Text (Get-ClaudeCodeResultText $content) }
            if ($content -is [string]) { return }
            foreach ($b in @($content)) {
                if ($b -isnot [System.Collections.IDictionary] -or $b["type"] -ne "tool_result") { continue }
                Add-ClaudeCodeIdleToolResult -St $St -Id "$($b["tool_use_id"])" -Err ($b["is_error"] -eq $true) -Text (Get-ClaudeCodeResultText $b["content"])
            }
        }
        $null = Read-HordeJsonLines -Path $f.FullName -Each $visitSub
    }
}

function Read-ClaudeCodeTurnState {
    # The turn state of one transcript (core/Idle.ps1). -Since is the harness process's start and -Now
    # the time of the reading, both UTC.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][datetime]$Since, [Parameter(Mandatory = $true)][datetime]$Now)
    $st = @{
        newest = $null; badTime = ""; hasEnd = $false; endAt = $null; endTimeBad = $false; pending = 0; blockers = (New-Object System.Collections.ArrayList)
        tools = @{}; tasks = @{}; unknownTasks = @{}; queued = 0; crons = @{}; cronCalls = @{}; stops = @{}; deletes = @{}; wakes = (New-Object System.Collections.ArrayList)
        versions = @{}; lastLn = 0; unreadable = ""; link = $null
    }
    Read-ClaudeCodeSubagentTasks -St $st -Path $Path -Since $Since
    $visit = {
        param($ln, $v)
        $kind = Get-ClaudeCodeIdleKind $v
        # A gap in the line numbers is a line the shared reader skipped: it could not be read.
        if ($st.hasEnd -and $ln -ne $st.lastLn + 1 -and $st.unreadable -eq "") { $st.unreadable = "line " + ($st.lastLn + 1) + ", after the last turn end, cannot be read" }
        $st.lastLn = $ln
        if ($kind -ceq "bridge-session" -and $v["bridgeSessionId"] -is [string] -and $v["bridgeSessionId"] -ne "") { $st.link = $v["bridgeSessionId"] }
        $raw = $v["timestamp"]
        $t = $null
        if ($null -ne $raw) {
            $t = ConvertTo-HordeUtcTime $raw
            if ($null -eq $t) { $st.badTime = "line " + $ln + " has a time with no zone" }
            elseif ($null -eq $st.newest -or $t -gt $st.newest) { $st.newest = $t }
        }
        # A line whose time cannot be placed counts as this process's: that can only hold a session.
        $cur = ($null -eq $t) -or ($t -ge $Since)
        if ($cur) {
            $ver = $v["version"]
            $vkey = "unversioned"; if ($ver -is [string] -and $ver -ne "") { $vkey = $ver }
            if ($vkey -ne "unversioned" -or $script:ClaudeCodeKnownKinds -cnotcontains $kind) {
                if (-not $st.versions.ContainsKey($vkey)) { $st.versions[$vkey] = @{ lines = 0; unrecognised = (New-Object System.Collections.ArrayList) } }
                $st.versions[$vkey].lines++
                if ($script:ClaudeCodeKnownKinds -cnotcontains $kind -and -not $st.versions[$vkey].unrecognised.Contains($kind)) { [void]$st.versions[$vkey].unrecognised.Add($kind) }
            }
        }

        if ($kind -ceq "system/turn_duration") {
            $st.hasEnd = $true; $st.endAt = $t; $st.endTimeBad = ($null -eq $t)
            $p = $v["pendingBackgroundAgentCount"]
            if ($null -eq $p) { $st.pending = 0 }
            elseif ($p -is [int] -or $p -is [long]) { $st.pending = [long]$p }
            else { throw ("line " + $ln + ": pendingBackgroundAgentCount is not a count") }
            $st.blockers.Clear(); $st.tools.Clear(); $st.unreadable = ""
            return
        }
        if ($st.hasEnd) {
            if ($null -eq $raw) {
                if ($script:ClaudeCodeMetadataKinds -cnotcontains $kind -and $st.unreadable -eq "") { $st.unreadable = "line " + $ln + " after the last turn end has no time and is not metadata (" + $kind + ")" }
            } elseif ($script:ClaudeCodeBoundaryKinds -cnotcontains $kind -and -not $st.blockers.Contains($kind)) { [void]$st.blockers.Add($kind) }
        }

        if ($kind -ceq "assistant") {
            $content = Get-HordeJsonPath $v "message.content"
            foreach ($b in @($content)) {
                if ($b -isnot [System.Collections.IDictionary] -or $b["type"] -ne "tool_use") { continue }
                $id = "$($b["id"])"; $name = "$($b["name"])"; $in = $b["input"]
                $st.tools[$id] = $name
                if (-not $cur -or $in -isnot [System.Collections.IDictionary]) { continue }
                if ($name -ceq "CronCreate") { $st.cronCalls[$id] = @{ recurring = ($in["recurring"] -eq $true); at = $t } }
                elseif ($name -ceq "CronDelete") { $st.deletes[$id] = "$($in["id"])" }
                elseif ($name -ceq "TaskStop") { $st.stops[$id] = "$($in["task_id"])" }
                elseif ($name -ceq "ScheduleWakeup" -and ($in.ContainsKey("delaySeconds") -or $in.ContainsKey("prompt"))) {
                    $d = $in["delaySeconds"]
                    $due = New-HordeUnknown -Reason "the wake-up's delay or request time cannot be read"
                    if ($null -ne $t -and ($d -is [int] -or $d -is [long] -or $d -is [decimal] -or $d -is [double])) { $due = New-HordeKnown -Value $t.AddSeconds([double]$d) }
                    [void]$st.wakes.Add([pscustomobject]@{ id = $id; dueAt = $due })
                }
            }
            return
        }
        if ($kind -ceq "user") {
            $content = Get-HordeJsonPath $v "message.content"
            if ($cur -and (Test-ClaudeCodeNotificationOrigin -Origin $v["origin"])) { Add-ClaudeCodeIdleNotification -St $st -Text (Get-ClaudeCodeResultText $content) }
            if ($content -is [string]) { return }
            foreach ($b in @($content)) {
                if ($b -isnot [System.Collections.IDictionary] -or $b["type"] -ne "tool_result") { continue }
                $id = "$($b["tool_use_id"])"
                $st.tools.Remove($id)
                if (-not $cur) { continue }
                Add-ClaudeCodeIdleToolResult -St $st -Id $id -Err ($b["is_error"] -eq $true) -Text (Get-ClaudeCodeResultText $b["content"])
            }
            return
        }
        if (-not $cur) { return }
        if ($kind -ceq "attachment") {
            $att = $v["attachment"]
            if ($att -is [System.Collections.IDictionary] -and $att["type"] -eq "queued_command" -and (Test-ClaudeCodeNotificationOrigin -Origin $att["origin"] -CommandMode $att["commandMode"])) {
                Add-ClaudeCodeIdleNotification -St $st -Text (Get-ClaudeCodeText $att["prompt"])
            }
            return
        }
        if ($kind -ceq "queue-operation") {
            $op = "$($v["operation"])"
            if ($op -ceq "enqueue") { $st.queued++ }
            elseif ($op -ceq "dequeue" -or $op -ceq "remove") { if ($st.queued -gt 0) { $st.queued-- } }
            else { throw ("line " + $ln + ": the queue operation '" + $op + "' is not one this reader knows") }
            return
        }
        if ($kind -ceq "system/scheduled_task_fire") {
            $tid = "$($v["taskId"])"
            if ($st.crons.ContainsKey($tid) -and -not $st.crons[$tid].recurring) { $st.crons.Remove($tid) }
        }
    }

    $read = Read-HordeJsonLines -Path $Path -Each $visit

    $newest = New-HordeUnknown -Reason "no line carries a time"
    if ($st.badTime -ne "") { $newest = New-HordeUnknown -Reason $st.badTime }
    elseif ($null -ne $st.newest) {
        if (($st.newest - $Now).TotalSeconds -gt $script:HordeClockSkewSeconds) { $newest = New-HordeUnknown -Reason ("the newest line is " + [int]($st.newest - $Now).TotalSeconds + "s in the future, past the clock skew allowance") }
        else { $newest = New-HordeKnown -Value $st.newest }
    }
    $endAt = New-HordeAbsent -Note "the transcript has no turn end"
    if ($st.hasEnd) { if ($st.endTimeBad) { $endAt = New-HordeUnknown -Reason "the last turn end's time cannot be placed" } else { $endAt = New-HordeKnown -Value $st.endAt } }
    # Lines after the last one read that the reader skipped (a bad or NUL-filled last line with a newline).
    if ($st.hasEnd -and $read.lineCount -gt $st.lastLn -and $read.tornTail -eq 0 -and $st.unreadable -eq "") { $st.unreadable = "line " + ($st.lastLn + 1) + ", after the last turn end, cannot be read" }
    $blockers = @($st.blockers)
    $boundary = $null
    if ($read.tornTail -gt 0) { $boundary = New-HordeUnknown -Reason "the last line is still being written" }
    elseif ($st.unreadable -ne "") { $boundary = New-HordeUnknown -Reason $st.unreadable }
    elseif (-not $st.hasEnd) { $boundary = New-HordeKnown -Value $false; $blockers = @("no turn end") }
    else { $boundary = New-HordeKnown -Value ($blockers.Count -eq 0) }
    $expiry = $Now.AddDays(-$script:ClaudeCodeCronExpiryDays)
    $crons = @($st.crons.Keys | Sort-Object | Where-Object { -not ($st.crons[$_].recurring -and $null -ne $st.crons[$_].at -and $st.crons[$_].at -lt $expiry) } | ForEach-Object { [pscustomobject]@{ id = $_; recurring = [bool]$st.crons[$_].recurring } })
    $fields = @{
        harness = "claude-code"; lineCount = [int]$read.lineCount; parseSkipped = [int]$read.parseSkipped; tornTail = [int]$read.tornTail
        newestEventAt = $newest; lastTurnEndAt = $endAt; atBoundary = $boundary; blockers = $blockers
        remoteLink = $(if ($null -ne $st.link) { New-HordeKnown -Value $st.link } else { New-HordeAbsent -Note "no bridge-session line names a Remote Control link" })
        pendingAgents = [long]$st.pending
        openTools = @($st.tools.Keys | Sort-Object | ForEach-Object { [pscustomobject]@{ id = $_; name = $st.tools[$_] } })
        openTasks = @($st.tasks.Keys | Sort-Object | ForEach-Object { [pscustomobject]@{ id = $_; kind = $st.tasks[$_] } })
        unknownTasks = @($st.unknownTasks.Keys | Sort-Object | ForEach-Object { [pscustomobject]@{ id = $_; status = $st.unknownTasks[$_] } })
        queued = [int]$st.queued
        wakes = @($st.wakes)
        crons = $crons
        versions = @($st.versions.Keys | Sort-Object | ForEach-Object { [pscustomobject]@{ version = $_; lines = [int]$st.versions[$_].lines; unrecognised = @($st.versions[$_].unrecognised) } })
    }
    return (New-HordeTurnState -Fields $fields)
}

Register-HordeIdleAdapter -Name "claude-code" -Read { param($Path, $Since, $Now) Read-ClaudeCodeTurnState -Path $Path -Since $Since -Now $Now }
