# DOES THE CLAUDE CODE IDLE READER (agents/claude-code/Idle.ps1) TELL A SESSION THAT IS MID-TURN OR
# HOLDS LIVE WORK FROM ONE THAT HOLDS NOTHING - ON THE RULES OF planning/idle-session-reaper.md?
#
# Two committed fixtures are the controls: fixtures/idle/idle-session.jsonl (a turn that ended, then an
# away summary and metadata) and fixtures/idle/live-session.jsonl (a tool call still running). Their
# field names and nesting are copied from real lines read on 2026-10-05; every value is invented. Every
# other case is built line by line below, in one folder in TEMP that is removed at the end. Nothing here
# reads a real transcript, a control file or a pane.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "ReadShared", "Transcript", "Idle")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "agents\claude-code\Transcript.ps1")
. (Join-Path $root "agents\claude-code\Idle.ps1")

$fixtures = Join-Path $here "fixtures\idle"
$utc = { param($t) [datetime]::SpecifyKind([datetime]::Parse($t, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal), [System.DateTimeKind]::Utc) }
$since = & $utc "2026-10-01T00:00:00Z"
$now = & $utc "2026-10-05T02:00:00Z"
$V = "2.1.284"
$sid = "33333333-4444-4555-8666-777777777777"
$work = Join-Path $env:TEMP ("horde-cc-idle-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$script:n = 0

# ---- line builders: the real shapes, the fields the reader reads ----
function Prompt { param($ts, $text) @{ type = "user"; timestamp = $ts; version = $V; sessionId = $sid; origin = @{ kind = "human" }; message = @{ role = "user"; content = $text } } }
function MetaUser { param($ts, $text) @{ type = "user"; timestamp = $ts; version = $V; sessionId = $sid; isMeta = $true; message = @{ role = "user"; content = $text } } }
# $In, never $input: $input is PowerShell's automatic pipeline variable, and a parameter of that name
# arrived empty (measured while writing this suite: every tool input read as nothing).
function ToolUse { param($ts, $id, $name, $In) @{ type = "assistant"; timestamp = $ts; version = $V; sessionId = $sid; message = @{ id = ("msg_" + $id); role = "assistant"; content = @(@{ type = "tool_use"; id = $id; name = $name; input = $In }) } } }
function ToolResult { param($ts, $id, $text, $err = $false) @{ type = "user"; timestamp = $ts; version = $V; sessionId = $sid; message = @{ role = "user"; content = @(@{ type = "tool_result"; tool_use_id = $id; content = $text; is_error = $err }) } } }
function Say { param($ts) $script:n++; @{ type = "assistant"; timestamp = $ts; version = $V; sessionId = $sid; message = @{ id = ("msg_say" + $script:n); role = "assistant"; content = @(@{ type = "text"; text = "Done." }) } } }
function TurnEnd { param($ts, $pending = $null) $h = @{ type = "system"; subtype = "turn_duration"; timestamp = $ts; version = $V; sessionId = $sid; durationMs = 1000 }; if ($null -ne $pending) { $h["pendingBackgroundAgentCount"] = $pending }; $h }
function Sys { param($ts, $sub, $ver = $V) @{ type = "system"; subtype = $sub; timestamp = $ts; version = $ver; sessionId = $sid } }
function Meta { param($type) @{ type = $type; sessionId = $sid } }
function Note { param($ts, $task, $status, $note = "") @{ type = "user"; timestamp = $ts; version = $V; sessionId = $sid; origin = @{ kind = "task-notification" }; message = @{ role = "user"; content = ("<task-notification>`n<task-id>" + $task + "</task-id>`n<status>" + $status + "</status>`n<note>" + $note + "</note>`n</task-notification>") } } }
function Queue { param($ts, $op) @{ type = "queue-operation"; operation = $op; timestamp = $ts; sessionId = $sid } }
function Fire { param($ts, $task) @{ type = "system"; subtype = "scheduled_task_fire"; timestamp = $ts; version = $V; sessionId = $sid; taskId = $task; cron = "*/5 * * * *" } }

$finalNote = "A task-notification fires each time this agent stops with no live background children of its own."
$interimNote = "This agent stopped with background work of its own still running; the result below may be interim."

function Write-Lines {
    param([string]$Name, [object[]]$Lines, [switch]$Torn)
    $p = Join-Path $work ($Name + ".jsonl")
    $sb = New-Object System.Text.StringBuilder
    foreach ($l in $Lines) { [void]$sb.Append((ConvertTo-Json -InputObject $l -Compress -Depth 20)); [void]$sb.Append("`n") }
    if ($Torn) { [void]$sb.Append('{"type":"assistant","timestamp":"2026-10-0') }
    [System.IO.File]::WriteAllText($p, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    return $p
}
function State { param([string]$Path, $Since = $since, $Now = $now) return (Read-ClaudeCodeTurnState -Path $Path -Since $Since -Now $Now) }
# An ended turn to build on: a prompt, an answer, the turn end.
$ended = @((Prompt "2026-10-02T10:00:00Z" "go"), (Say "2026-10-02T10:00:05Z"), (TurnEnd "2026-10-02T10:00:06Z"))

try {
    Write-Host ""
    Write-Host "--- the controls: a known-idle and a known-live session ---" -ForegroundColor Cyan
    $idle = State (Join-Path $fixtures "idle-session.jsonl")
    Check ($idle.atBoundary.state -eq "known" -and $idle.atBoundary.value -eq $true) "CONTROL: the idle fixture is at a turn boundary"
    Check ($idle.pendingAgents -eq 0 -and @($idle.openTools).Count -eq 0 -and @($idle.openTasks).Count -eq 0 -and $idle.queued -eq 0 -and @($idle.crons).Count -eq 0 -and @($idle.wakes).Count -eq 0 -and @($idle.unknownTasks).Count -eq 0) "CONTROL: the idle fixture holds no agent, tool, task, queue, cron or wake"
    Check ($idle.newestEventAt.state -eq "known" -and $idle.newestEventAt.value -eq (& $utc "2026-10-01T10:30:00Z")) "the idle fixture's newest event is its away summary, after the turn end"
    Check ($idle.lastTurnEndAt.state -eq "known" -and $idle.lastTurnEndAt.value -eq (& $utc "2026-10-01T10:00:10.050Z")) "its last turn end is the turn_duration line"
    Check (@(Get-HordeUnsurveyedVersions -TurnState $idle).Count -eq 0) "every kind the idle fixture's version wrote is known"
    $live = State (Join-Path $fixtures "live-session.jsonl")
    Check ($live.atBoundary.state -eq "known" -and $live.atBoundary.value -eq $false) "CONTROL: the live fixture is not at a turn boundary"
    Check (@($live.openTools).Count -eq 1 -and $live.openTools[0].name -ceq "Bash") "the live fixture's running tool call is open"
    $through = Read-HordeTurnState -Harness "claude-code" -Path (Join-Path $fixtures "idle-session.jsonl") -Since $since -Now $now
    Check ($through.state -eq "known" -and $through.value.harness -ceq "claude-code") "the reader registers with the idle port under its harness name"

    Write-Host ""
    Write-Host "--- age is the newest event, never the file's time ---" -ForegroundColor Cyan
    $copy = Join-Path $work "touched.jsonl"
    Copy-Item -LiteralPath (Join-Path $fixtures "idle-session.jsonl") -Destination $copy
    [System.IO.File]::SetLastWriteTimeUtc($copy, [datetime]::UtcNow)
    $t = State $copy
    Check ($t.newestEventAt.value -eq (& $utc "2026-10-01T10:30:00Z")) "a transcript touched just now still ages from its newest line (design I-04)"
    $p = Write-Lines "nozone" @($ended + @(@{ type = "system"; subtype = "away_summary"; timestamp = "2026-10-02T10:05:00"; version = $V }))
    Check ((State $p).newestEventAt.state -eq "unknown") "a line time with no zone makes the age unknown"
    $p = Write-Lines "future" @($ended + @(Sys "2026-10-05T03:00:00Z" "away_summary"))
    Check ((State $p).newestEventAt.state -eq "unknown") "a line time an hour in the future makes the age unknown"
    $p = Write-Lines "nearfuture" @($ended + @(Sys "2026-10-05T02:00:03Z" "away_summary"))
    Check ((State $p).newestEventAt.state -eq "known") "a line time within the clock skew allowance is still known"

    Write-Host ""
    Write-Host "--- the turn boundary (design 1.5) ---" -ForegroundColor Cyan
    $p = Write-Lines "noend" @((Prompt "2026-10-02T10:00:00Z" "go"), (Say "2026-10-02T10:00:05Z"))
    $s = State $p
    Check ($s.atBoundary.value -eq $false -and $s.lastTurnEndAt.state -eq "absent" -and @($s.blockers) -contains "no turn end") "a transcript with no turn end is not at a boundary"
    $p = Write-Lines "away" @($ended + @((Sys "2026-10-02T10:30:00Z" "away_summary"), (Sys "2026-10-02T10:31:00Z" "bridge_status"), (Meta "last-prompt"), (Meta "bridge-session")))
    Check ((State $p).atBoundary.value -eq $true) "allowed system lines and metadata after a turn end keep the boundary"
    $p = Write-Lines "fire" @($ended + @(Fire "2026-10-02T10:05:00Z" "a1b2c3d4"))
    $s = State $p
    Check ($s.atBoundary.value -eq $false -and @($s.blockers) -contains "system/scheduled_task_fire") "a scheduled task firing after a turn end is not a boundary"
    $p = Write-Lines "newkind" @($ended + @(Sys "2026-10-02T10:05:00Z" "brand_new"))
    Check ((State $p).atBoundary.value -eq $false) "a line kind the reader has never seen, after a turn end, is not a boundary"
    $p = Write-Lines "newmeta" @($ended + @(Meta "brand-new-meta"))
    Check ((State $p).atBoundary.value -eq $false) "an untimestamped line of a kind the reader has never seen is not a boundary"
    $p = Write-Lines "metauser" @($ended + @(MetaUser "2026-10-02T10:05:00Z" "local command output"))
    $s = State $p
    Check ($s.atBoundary.value -eq $false -and @($s.blockers) -contains "user") "a user meta line after a turn end (a local command) is not a boundary: a known false keep"
    $p = Write-Lines "prompted" @($ended + @(Prompt "2026-10-02T10:05:00Z" "next"))
    Check ((State $p).atBoundary.value -eq $false) "a new prompt after a turn end is not a boundary"
    $p = Write-Lines "torn" $ended -Torn
    $s = State $p
    Check ($s.atBoundary.state -eq "unknown" -and $s.tornTail -eq 1) "a last line still being written makes the boundary unknown"

    Write-Host ""
    Write-Host "--- pending agents and open tool calls ---" -ForegroundColor Cyan
    $p = Write-Lines "pending" @((Prompt "2026-10-02T10:00:00Z" "go"), (TurnEnd "2026-10-02T10:00:06Z" 1))
    Check ((State $p).pendingAgents -eq 1) "a turn end that names a pending background agent holds it"
    Check ((State (Write-Lines "nopending" $ended)).pendingAgents -eq 0) "CONTROL: a turn end without the field has none pending"
    $p = Write-Lines "paired" @((Prompt "2026-10-02T10:00:00Z" "go"), (ToolUse "2026-10-02T10:00:01Z" "toolu_P1" "Read" @{ file_path = "x" }), (ToolResult "2026-10-02T10:00:02Z" "toolu_P1" "x"))
    Check (@((State $p).openTools).Count -eq 0) "a tool call with its result is not open"
    # Measured 2026-10-05 over 224 transcripts: 4 of 5,835 turn ends came with a tool call never answered.
    # The turn end is the harness saying the turn is over, so the call is not counted as running.
    $p = Write-Lines "unanswered" @((Prompt "2026-10-02T10:00:00Z" "go"), (ToolUse "2026-10-02T10:00:01Z" "toolu_Z1" "Read" @{ file_path = "x" }), (TurnEnd "2026-10-02T10:00:06Z"))
    Check (@((State $p).openTools).Count -eq 0) "a tool call the turn ended without answering is not open after the turn end"

    Write-Host ""
    Write-Host "--- background tasks (P12) ---" -ForegroundColor Cyan
    $bgStart = @((Prompt "2026-10-02T10:00:00Z" "go"), (ToolUse "2026-10-02T10:00:01Z" "toolu_B1" "Bash" @{ command = "x"; run_in_background = $true }), (ToolResult "2026-10-02T10:00:02Z" "toolu_B1" "Command running in background with ID: bsh0001. Output is being written to: x"), (Say "2026-10-02T10:00:03Z"), (TurnEnd "2026-10-02T10:00:04Z"))
    $s = State (Write-Lines "bg" $bgStart)
    Check (@($s.openTasks).Count -eq 1 -and $s.openTasks[0].id -ceq "bsh0001" -and $s.openTasks[0].kind -ceq "shell" -and $s.pendingAgents -eq 0) "an unfinished background shell task holds the session, though no agent is pending"
    $s = State (Write-Lines "bgdone" @($bgStart + @(Note "2026-10-02T10:10:00Z" "bsh0001" "completed")))
    Check (@($s.openTasks).Count -eq 0) "a completed notification finishes it"
    $s = State (Write-Lines "bgkilled" @($bgStart + @(Note "2026-10-02T10:10:00Z" "bsh0001" "killed")))
    Check (@($s.openTasks).Count -eq 0) "a killed notification finishes it"
    $s = State (Write-Lines "bgpasted" @($bgStart + @(Prompt "2026-10-02T10:10:00Z" "<task-notification>`n<task-id>bsh0001</task-id>`n<status>completed</status>`n</task-notification>")))
    Check (@($s.openTasks).Count -eq 1) "notification text a person pasted does not finish a task: only the harness's marked notifications count"
    $s = State (Write-Lines "bgold" $bgStart) -Since (& $utc "2026-10-03T00:00:00Z")
    Check (@($s.openTasks).Count -eq 0) "a task started before this process started died with the old process"
    $mon = @((ToolUse "2026-10-02T10:00:01Z" "toolu_M1" "Monitor" @{ command = "x" }), (ToolResult "2026-10-02T10:00:02Z" "toolu_M1" "Monitor started (task bmon001, persistent - runs until TaskStop or session end). You will be notified on each event."))
    $s = State (Write-Lines "mon" @($mon + @(Note "2026-10-02T10:05:00Z" "bmon001" "")))
    Check (@($s.openTasks).Count -eq 1 -and $s.openTasks[0].kind -ceq "monitor") "a Monitor stays open across its event notifications"
    $s = State (Write-Lines "monstop" @($mon + @((ToolUse "2026-10-02T10:06:00Z" "toolu_S1" "TaskStop" @{ task_id = "bmon001" }), (ToolResult "2026-10-02T10:06:01Z" "toolu_S1" "stopped"))))
    Check (@($s.openTasks).Count -eq 0) "TaskStop finishes the task it names"
    $s = State (Write-Lines "monstopfail" @($mon + @((ToolUse "2026-10-02T10:06:00Z" "toolu_S1" "TaskStop" @{ task_id = "bmon001" }), (ToolResult "2026-10-02T10:06:01Z" "toolu_S1" "no such task" $true))))
    Check (@($s.openTasks).Count -eq 1) "a TaskStop that failed finishes nothing"
    $ag = @((ToolUse "2026-10-02T10:00:01Z" "toolu_A1" "Agent" @{ description = "x"; prompt = "x" }), (ToolResult "2026-10-02T10:00:02Z" "toolu_A1" "Async agent launched successfully.`nagentId: aagent0001 (internal ID)"))
    $s = State (Write-Lines "aginterim" @($ag + @(Note "2026-10-02T10:30:00Z" "aagent0001" "completed" $interimNote)))
    Check (@($s.openTasks).Count -eq 1 -and $s.openTasks[0].kind -ceq "agent") "an agent whose notification says its result may be interim is still running"
    $s = State (Write-Lines "agfinal" @($ag + @(Note "2026-10-02T10:30:00Z" "aagent0001" "completed" $finalNote)))
    Check (@($s.openTasks).Count -eq 0) "an agent's final notification finishes it"
    $s = State (Write-Lines "wf" @((ToolUse "2026-10-02T10:00:01Z" "toolu_W1" "Workflow" @{ name = "x" }), (ToolResult "2026-10-02T10:00:02Z" "toolu_W1" "Workflow launched in wfrun001. Task ID: bwfl0001`nSummary: x")))
    Check (@($s.openTasks).Count -eq 1 -and $s.openTasks[0].kind -ceq "workflow") "a launched Workflow holds the session"
    $s = State (Write-Lines "unknowntask" @($ended + @(Note "2026-10-02T10:05:00Z" "bzzz9999" "running")))
    Check (@($s.unknownTasks).Count -eq 1 -and $s.unknownTasks[0].id -ceq "bzzz9999") "a report about a task of a kind the reader does not recognise, not final, is unknown"
    $s = State (Write-Lines "unknowndone" @($ended + @(Note "2026-10-02T10:05:00Z" "bzzz9999" "completed")))
    Check (@($s.unknownTasks).Count -eq 0) "a final report about an unrecognised task holds nothing"

    Write-Host ""
    Write-Host "--- queued input (P13) ---" -ForegroundColor Cyan
    Check ((State (Write-Lines "q1" @($ended + @(Queue "2026-10-02T10:05:00Z" "enqueue")))).queued -eq 1) "a message enqueued and not taken is queued"
    Check ((State (Write-Lines "q0" @($ended + @((Queue "2026-10-02T10:05:00Z" "enqueue"), (Queue "2026-10-02T10:05:01Z" "dequeue"))))).queued -eq 0) "CONTROL: one dequeued is not"
    Check ((State (Write-Lines "qr" @($ended + @((Queue "2026-10-02T10:05:00Z" "enqueue"), (Queue "2026-10-02T10:05:01Z" "remove"))))).queued -eq 0) "nor one removed"
    Check ((State (Write-Lines "qold" @((Queue "2026-09-30T10:05:00Z" "enqueue")) + $ended)).queued -eq 0) "an enqueue before this process started was lost with the old process (design I-19)"
    Check (Throws { State (Write-Lines "qnew" @($ended + @(Queue "2026-10-02T10:05:00Z" "reshuffle"))) } "reshuffle") "a queue operation the reader does not know is refused, so the turn state is unknown"

    Write-Host ""
    Write-Host "--- crons and wakes (P8) ---" -ForegroundColor Cyan
    $cron = @((ToolUse "2026-10-04T10:00:01Z" "toolu_C1" "CronCreate" @{ cron = "*/5 * * * *"; prompt = "x"; recurring = $true }), (ToolResult "2026-10-04T10:00:02Z" "toolu_C1" "Scheduled recurring job a1b2c3d4 (Every 5 minutes). Session-only."))
    $s = State (Write-Lines "cron" @($cron + $ended))
    Check (@($s.crons).Count -eq 1 -and $s.crons[0].id -ceq "a1b2c3d4" -and $s.crons[0].recurring -eq $true) "a recurring cron with no CronDelete holds the session"
    $s = State (Write-Lines "crondel" @($cron + @((ToolUse "2026-10-04T11:00:00Z" "toolu_C2" "CronDelete" @{ id = "a1b2c3d4" }), (ToolResult "2026-10-04T11:00:01Z" "toolu_C2" "deleted"))))
    Check (@($s.crons).Count -eq 0) "a CronDelete releases its cron"
    $s = State (Write-Lines "cronfire" @($cron + @(Fire "2026-10-04T10:05:00Z" "a1b2c3d4")))
    Check (@($s.crons).Count -eq 1) "a recurring cron that fired is still live"
    $s = State (Write-Lines "cronold" @($cron)) -Since (& $utc "2026-10-04T12:00:00Z")
    Check (@($s.crons).Count -eq 0) "a cron from before this process started does not hold it"
    $s = State (Write-Lines "cronexpired" @($cron)) -Now (& $utc "2026-10-11T10:00:03Z")
    Check (@($s.crons).Count -eq 0) "a recurring cron older than its 7-day expiry no longer holds the session"
    $s = State (Write-Lines "cronalive" @($cron)) -Now (& $utc "2026-10-11T09:59:00Z")
    Check (@($s.crons).Count -eq 1) "CONTROL: one just inside the 7 days still does"
    $one = @((ToolUse "2026-10-04T10:00:01Z" "toolu_O1" "CronCreate" @{ cron = "0 9 5 10 *"; prompt = "x"; recurring = $false }), (ToolResult "2026-10-04T10:00:02Z" "toolu_O1" "Scheduled one-shot job e5f6a7b8 (Oct 5 at 9:00). Session-only."))
    $s = State (Write-Lines "oneshot" $one)
    Check (@($s.crons).Count -eq 1 -and $s.crons[0].recurring -eq $false) "a one-shot cron not yet fired holds the session"
    $s = State (Write-Lines "oneshotfired" @($one + @(Fire "2026-10-05T09:00:00Z" "e5f6a7b8")))
    Check (@($s.crons).Count -eq 0) "a one-shot cron that fired is gone"
    $s = State (Write-Lines "cronerr" @((ToolUse "2026-10-04T10:00:01Z" "toolu_E1" "CronCreate" @{ cron = "x"; prompt = "x"; recurring = $true }), (ToolResult "2026-10-04T10:00:02Z" "toolu_E1" "invalid cron" $true)))
    Check (@($s.crons).Count -eq 0) "a CronCreate that failed created nothing"
    $s = State (Write-Lines "cronnoid" @((ToolUse "2026-10-04T10:00:01Z" "toolu_N1" "CronCreate" @{ cron = "x"; prompt = "x"; recurring = $true }), (ToolResult "2026-10-04T10:00:02Z" "toolu_N1" "Scheduled something new")))
    Check (@($s.crons).Count -eq 1) "a created cron whose id cannot be read still holds the session"
    $s = State (Write-Lines "wake" @((ToolUse "2026-10-04T10:00:00Z" "toolu_K1" "ScheduleWakeup" @{ delaySeconds = 600; prompt = "x"; reason = "x" }), (ToolResult "2026-10-04T10:00:01Z" "toolu_K1" "ok")))
    Check (@($s.wakes).Count -eq 1 -and $s.wakes[0].dueAt.state -eq "known" -and $s.wakes[0].dueAt.value -eq (& $utc "2026-10-04T10:10:00Z")) "a wake-up is due at its request time plus its delay"
    $s = State (Write-Lines "wakenodelay" @((ToolUse "2026-10-04T10:00:00Z" "toolu_K2" "ScheduleWakeup" @{ prompt = "x" }), (ToolResult "2026-10-04T10:00:01Z" "toolu_K2" "ok")))
    Check (@($s.wakes).Count -eq 1 -and $s.wakes[0].dueAt.state -eq "unknown") "a wake-up whose delay cannot be read has an unknown due time"
    $s = State (Write-Lines "wakeold" @((ToolUse "2026-10-04T10:00:00Z" "toolu_K4" "ScheduleWakeup" @{ delaySeconds = 600; prompt = "x"; reason = "x" }), (ToolResult "2026-10-04T10:00:01Z" "toolu_K4" "ok"))) -Since (& $utc "2026-10-04T12:00:00Z")
    Check (@($s.wakes).Count -eq 0) "a wake-up requested before this process started died with the old process"
    $s = State (Write-Lines "wakestop" @((ToolUse "2026-10-04T10:00:00Z" "toolu_K3" "ScheduleWakeup" @{ stop = $true }), (ToolResult "2026-10-04T10:00:01Z" "toolu_K3" "ok")))
    Check (@($s.wakes).Count -eq 0) "a call that only stops a loop is not a wake-up"

    Write-Host ""
    Write-Host "--- the per-version survey (design 1.6) ---" -ForegroundColor Cyan
    $s = State (Write-Lines "versions" @($ended + @(Sys "2026-10-02T10:05:00Z" "brand_new" "9.9.9")))
    $u = @(Get-HordeUnsurveyedVersions -TurnState $s)
    Check ($u.Count -eq 1 -and $u[0] -ceq "9.9.9") "a version whose lines carry a kind the reader does not know is unsurveyed, and only that version"
    $s = State (Write-Lines "versionsold" @(@(Sys "2026-09-30T10:05:00Z" "brand_new" "9.9.9") + $ended))
    Check (@(Get-HordeUnsurveyedVersions -TurnState $s).Count -eq 0) "lines written before this process started are not this process's version"

    Write-Host ""
    Write-Host "--- no text leaves the reader ---" -ForegroundColor Cyan
    $secret = "PLANTED-SECRET-91ab"
    $s = State (Write-Lines "secret" @((Prompt "2026-10-02T10:00:00Z" $secret), (ToolUse "2026-10-02T10:00:01Z" "toolu_X1" "Bash" @{ command = $secret }), (ToolResult "2026-10-02T10:00:02Z" "toolu_X1" ($secret + " Command running in background with ID: bsec0001."))))
    Check ((ConvertTo-Json -InputObject $s -Depth 20) -notlike ("*" + $secret + "*")) "no prompt, tool input or tool result text appears in the turn state"
} finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }

Complete-HordeSuite -Success "the claude-code idle reader holds every session that is mid-turn or holds live work, and releases one that holds nothing"
