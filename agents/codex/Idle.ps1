# agents/codex/Idle.ps1 - the idle reader for Codex rollouts: whether the rollout's turns have all
# ended (core/Idle.ps1's turn state; planning/idle-session-reaper.md section 1.3).
#
# WHAT IT READS. One rollout, { timestamp, type, payload } per line, streamed through core/Transcript.ps1's
# shared reader. Measured read-only on the four rollouts on this machine (2026-10-05; Codex CLI 0.149.1,
# 0.159.2, 0.159.3; the design's I-13):
#   - A TURN opens at event_msg task_started and closes at task_complete (a failed turn's carries an
#     error) or turn_aborted (an interrupt writes no task_complete), PAIRED BY turn_id: 12 starts, 10
#     completes and 2 aborts, every one paired. The status hook's file is not read: it is believed for
#     900 s only and its Stop event does not fire on a failed or interrupted turn (wezfleet
#     lib/CodexStatus.ps1), so it can never say idle for long enough to matter.
#   - A TOOL CALL is a response_item function_call, closed by the function_call_output of its call_id.
#   - THE BOUNDARY allows NOTHING after the last turn end: in every rollout measured the turn end was the
#     last line, and nothing else has been measured to start no turn. A line after it that cannot be read
#     (skipped by the shared reader, seen as a gap in the line numbers) or that carries no time makes
#     the boundary unknown, never idle (review of #93, F3).
#   - THE REMOTE CONTROL LINK is unknown: no Codex remote view has been measured.
#   - THE VERSION is session_meta's cli_version; every line after it counts towards it. The known kinds
#     are the fifteen those rollouts hold.
#   - Codex has no background agents, tasks, crons or queue that this reader can see: those lists are
#     empty. That is a reason the Codex idle flags stay unverified (agents/codex/agent.json), so the
#     reaper only reports Codex sessions until a live session is measured.
#
# No Set-StrictMode here: dot-sourced (see core/Tristate.ps1). Needs core/Tristate.ps1,
# core/ReadShared.ps1, core/Transcript.ps1 and core/Idle.ps1.

$script:CodexKnownKinds = @("session_meta", "turn_context", "token_usage_record", "world_state", "compacted",
    "response_item/message", "response_item/function_call", "response_item/function_call_output", "response_item/reasoning",
    "event_msg/item_completed", "event_msg/token_count", "event_msg/task_started", "event_msg/task_complete", "event_msg/turn_aborted",
    "event_msg/thread_settings_applied")

function Get-CodexIdleKind {
    # A line's kind: its type, or <type>/<payload type> for event_msg and response_item.
    param($Value)
    $type = "$($Value["type"])"
    $p = $Value["payload"]
    if (($type -ceq "event_msg" -or $type -ceq "response_item") -and $p -is [System.Collections.IDictionary] -and $null -ne $p["type"]) { return ($type + "/" + $p["type"]) }
    return $type
}

function Read-CodexTurnState {
    # The turn state of one rollout (core/Idle.ps1). -Since and -Now are UTC.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][datetime]$Since, [Parameter(Mandatory = $true)][datetime]$Now)
    $st = @{ newest = $null; badTime = ""; hasEnd = $false; endAt = $null; endTimeBad = $false; turns = @{}; tools = @{}; blockers = (New-Object System.Collections.ArrayList); version = "unversioned"; versions = @{}; lastLn = 0; unreadable = "" }
    $visit = {
        param($ln, $v)
        $kind = Get-CodexIdleKind $v
        $p = $v["payload"]
        if ($st.hasEnd -and $ln -ne $st.lastLn + 1 -and $st.unreadable -eq "") { $st.unreadable = "line " + ($st.lastLn + 1) + ", after the last turn end, cannot be read" }
        $st.lastLn = $ln
        if ($st.hasEnd -and $st.turns.Count -eq 0 -and $null -eq $v["timestamp"] -and $st.unreadable -eq "") { $st.unreadable = "line " + $ln + " after the last turn end has no time" }
        $t = $null
        if ($null -ne $v["timestamp"]) {
            $t = ConvertTo-HordeUtcTime $v["timestamp"]
            if ($null -eq $t) { $st.badTime = "line " + $ln + " has a time with no zone" }
            elseif ($null -eq $st.newest -or $t -gt $st.newest) { $st.newest = $t }
        }
        if ($kind -ceq "session_meta" -and $p -is [System.Collections.IDictionary] -and $p["cli_version"] -is [string] -and $p["cli_version"] -ne "") { $st.version = $p["cli_version"] }
        if (($null -eq $t) -or ($t -ge $Since)) {
            if (-not $st.versions.ContainsKey($st.version)) { $st.versions[$st.version] = @{ lines = 0; unrecognised = (New-Object System.Collections.ArrayList) } }
            $st.versions[$st.version].lines++
            if ($script:CodexKnownKinds -cnotcontains $kind -and -not $st.versions[$st.version].unrecognised.Contains($kind)) { [void]$st.versions[$st.version].unrecognised.Add($kind) }
        }
        $turn = ""; if ($p -is [System.Collections.IDictionary]) { $turn = "$($p["turn_id"])" }
        if ($kind -ceq "event_msg/task_started") { $st.turns[$turn] = $true; $st.blockers.Clear(); [void]$st.blockers.Add($kind); return }
        if ($kind -ceq "event_msg/task_complete" -or $kind -ceq "event_msg/turn_aborted") {
            $st.turns.Remove($turn)
            if ($st.turns.Count -eq 0) { $st.hasEnd = $true; $st.endAt = $t; $st.endTimeBad = ($null -eq $t); $st.blockers.Clear(); $st.tools.Clear(); $st.unreadable = "" }
            return
        }
        if ($st.hasEnd -and $st.turns.Count -eq 0 -and -not $st.blockers.Contains($kind)) { [void]$st.blockers.Add($kind) }
        if ($kind -ceq "response_item/function_call") { $st.tools["$($p["call_id"])"] = "$($p["name"])" }
        elseif ($kind -ceq "response_item/function_call_output") { $st.tools.Remove("$($p["call_id"])") }
    }

    $read = Read-HordeJsonLines -Path $Path -Each $visit

    $newest = New-HordeUnknown -Reason "no line carries a time"
    if ($st.badTime -ne "") { $newest = New-HordeUnknown -Reason $st.badTime }
    elseif ($null -ne $st.newest) {
        if (($st.newest - $Now).TotalSeconds -gt $script:HordeClockSkewSeconds) { $newest = New-HordeUnknown -Reason ("the newest line is " + [int]($st.newest - $Now).TotalSeconds + "s in the future, past the clock skew allowance") }
        else { $newest = New-HordeKnown -Value $st.newest }
    }
    $endAt = New-HordeAbsent -Note "the rollout has no turn end"
    if ($st.hasEnd) { if ($st.endTimeBad) { $endAt = New-HordeUnknown -Reason "the last turn end's time cannot be placed" } else { $endAt = New-HordeKnown -Value $st.endAt } }
    $blockers = @($st.blockers)
    if ($st.turns.Count -gt 0) { $blockers = @("open turn") + @($blockers | Where-Object { $_ -cne "event_msg/task_started" }) }
    if ($st.hasEnd -and $read.lineCount -gt $st.lastLn -and $read.tornTail -eq 0 -and $st.unreadable -eq "") { $st.unreadable = "line " + ($st.lastLn + 1) + ", after the last turn end, cannot be read" }
    $boundary = $null
    if ($read.tornTail -gt 0) { $boundary = New-HordeUnknown -Reason "the last line is still being written" }
    elseif ($st.unreadable -ne "") { $boundary = New-HordeUnknown -Reason $st.unreadable }
    elseif (-not $st.hasEnd -and $st.turns.Count -eq 0) { $boundary = New-HordeKnown -Value $false; $blockers = @("no turn end") }
    else { $boundary = New-HordeKnown -Value ($st.turns.Count -eq 0 -and $blockers.Count -eq 0) }
    $fields = @{
        harness = "codex"; lineCount = [int]$read.lineCount; parseSkipped = [int]$read.parseSkipped; tornTail = [int]$read.tornTail
        newestEventAt = $newest; lastTurnEndAt = $endAt; atBoundary = $boundary; blockers = $blockers
        remoteLink = (New-HordeUnknown -Reason "no Codex remote view has been measured")
        pendingAgents = 0
        openTools = @($st.tools.Keys | Sort-Object | ForEach-Object { [pscustomobject]@{ id = $_; name = $st.tools[$_] } })
        openTasks = @(); unknownTasks = @(); queued = 0; wakes = @(); crons = @()
        versions = @($st.versions.Keys | Sort-Object | ForEach-Object { [pscustomobject]@{ version = $_; lines = [int]$st.versions[$_].lines; unrecognised = @($st.versions[$_].unrecognised) } })
    }
    return (New-HordeTurnState -Fields $fields)
}

Register-HordeIdleAdapter -Name "codex" -Read { param($Path, $Since, $Now) Read-CodexTurnState -Path $Path -Since $Since -Now $Now }
