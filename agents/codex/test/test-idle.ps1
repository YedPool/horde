# DOES THE CODEX IDLE READER (agents/codex/Idle.ps1) TELL A ROLLOUT WHOSE TURN IS STILL RUNNING FROM
# ONE WHOSE TURNS HAVE ALL ENDED?
#
# The controls are built from the shapes of the four rollouts on this machine (2026-10-05, Codex CLI
# 0.149.1 to 0.159.3): every turn opens with event_msg task_started and closes with task_complete
# (a failed turn too, carrying an error) or turn_aborted, paired by turn_id. Every value is invented.
# The Codex idle flags stay unverified (no live Codex session existed to measure), so the reaper only
# reports Codex sessions; this suite pins what the reader says until a live measurement turns them on.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "ReadShared", "Transcript", "Idle")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "agents\codex\Idle.ps1")

$utc = { param($t) [datetime]::SpecifyKind([datetime]::Parse($t, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal), [System.DateTimeKind]::Utc) }
$since = & $utc "2026-10-01T00:00:00Z"
$now = & $utc "2026-10-05T02:00:00Z"
$work = Join-Path $env:TEMP ("horde-codex-idle-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null

function Meta { param($ts, $ver = "0.159.3") @{ timestamp = $ts; type = "session_meta"; payload = @{ id = "01a0dddd-1111-7222-8333-444455556666"; cli_version = $ver; cwd = "C:\work\repo" } } }
function Ev { param($ts, $kind, $turn = "t1", $extra = @{}) $p = @{ type = $kind; turn_id = $turn }; foreach ($k in $extra.Keys) { $p[$k] = $extra[$k] }; @{ timestamp = $ts; type = "event_msg"; payload = $p } }
function Item { param($ts, $kind, $extra = @{}) $p = @{ type = $kind }; foreach ($k in $extra.Keys) { $p[$k] = $extra[$k] }; @{ timestamp = $ts; type = "response_item"; payload = $p } }
function Plain { param($ts, $type) @{ timestamp = $ts; type = $type; payload = @{} } }
function Write-Lines {
    param([string]$Name, [object[]]$Lines, [switch]$Torn)
    $p = Join-Path $work ($Name + ".jsonl")
    $sb = New-Object System.Text.StringBuilder
    foreach ($l in $Lines) { [void]$sb.Append((ConvertTo-Json -InputObject $l -Compress -Depth 20)); [void]$sb.Append("`n") }
    if ($Torn) { [void]$sb.Append('{"timestamp":"2026-10-0') }
    [System.IO.File]::WriteAllText($p, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    return $p
}
function State { param([string]$Path, $Since = $since, $Now = $now) return (Read-CodexTurnState -Path $Path -Since $Since -Now $Now) }
$turn = @((Meta "2026-10-02T10:00:00Z"), (Plain "2026-10-02T10:00:01Z" "turn_context"), (Ev "2026-10-02T10:00:02Z" "task_started"), (Item "2026-10-02T10:00:03Z" "message" @{ role = "assistant" }), (Plain "2026-10-02T10:00:04Z" "token_usage_record"), (Ev "2026-10-02T10:00:05Z" "token_count"))

try {
    Write-Host ""
    Write-Host "--- the controls: a known-idle and a known-live rollout ---" -ForegroundColor Cyan
    $idle = State (Write-Lines "idle" @($turn + @(Ev "2026-10-02T10:00:06Z" "task_complete")))
    Check ($idle.atBoundary.state -eq "known" -and $idle.atBoundary.value -eq $true) "CONTROL: a rollout whose turn completed is at a boundary"
    Check ($idle.lastTurnEndAt.value -eq (& $utc "2026-10-02T10:00:06Z") -and $idle.newestEventAt.value -eq (& $utc "2026-10-02T10:00:06Z")) "its last turn end and newest event are the task_complete line"
    $live = State (Write-Lines "live" $turn)
    Check ($live.atBoundary.state -eq "known" -and $live.atBoundary.value -eq $false) "CONTROL: a rollout whose turn started and has not ended is not at a boundary"
    $through = Read-HordeTurnState -Harness "codex" -Path (Write-Lines "port" @($turn + @(Ev "2026-10-02T10:00:06Z" "task_complete"))) -Since $since -Now $now
    Check ($through.state -eq "known" -and $through.value.harness -ceq "codex") "the reader registers with the idle port under its harness name"

    Write-Host ""
    Write-Host "--- turn pairing ---" -ForegroundColor Cyan
    Check ((State (Write-Lines "aborted" @($turn + @(Ev "2026-10-02T10:00:06Z" "turn_aborted")))).atBoundary.value -eq $true) "turn_aborted ends a turn (an interrupt writes no task_complete)"
    Check ((State (Write-Lines "failed" @($turn + @(Ev "2026-10-02T10:00:06Z" "task_complete" "t1" @{ error = "x" })))).atBoundary.value -eq $true) "a failed turn's task_complete ends it"
    $s = State (Write-Lines "otherturn" @($turn + @(Ev "2026-10-02T10:00:06Z" "task_complete" "t9")))
    Check ($s.atBoundary.value -eq $false) "an end for another turn_id does not end this turn"
    $s = State (Write-Lines "after" @($turn + @((Ev "2026-10-02T10:00:06Z" "task_complete"), (Item "2026-10-02T10:00:07Z" "message" @{ role = "user" }))))
    Check ($s.atBoundary.value -eq $false -and @($s.blockers) -contains "response_item/message") "a line after the last turn end is not a boundary: none is allowed until measured"
    Check ((State (Write-Lines "noturn" @((Meta "2026-10-02T10:00:00Z")))).atBoundary.value -eq $false) "a rollout with no turn end is not at a boundary"
    $s = State (Write-Lines "torn" @($turn + @(Ev "2026-10-02T10:00:06Z" "task_complete")) -Torn)
    Check ($s.atBoundary.state -eq "unknown") "a last line still being written makes the boundary unknown"
    $s = State (Write-Lines "call" @($turn + @(Item "2026-10-02T10:00:05Z" "function_call" @{ call_id = "call_1"; name = "shell" })))
    Check (@($s.openTools).Count -eq 1 -and $s.openTools[0].id -ceq "call_1") "a function call with no output is an open tool"
    $s = State (Write-Lines "callout" @($turn + @((Item "2026-10-02T10:00:05Z" "function_call" @{ call_id = "call_1"; name = "shell" }), (Item "2026-10-02T10:00:06Z" "function_call_output" @{ call_id = "call_1" }))))
    Check (@($s.openTools).Count -eq 0) "CONTROL: one with its output is not"

    Write-Host ""
    Write-Host "--- times and versions ---" -ForegroundColor Cyan
    $s = State (Write-Lines "nozone" @($turn + @(@{ timestamp = "2026-10-02T10:00:06"; type = "event_msg"; payload = @{ type = "task_complete"; turn_id = "t1" } })))
    Check ($s.newestEventAt.state -eq "unknown") "a time with no zone makes the age unknown"
    $s = State (Write-Lines "future" @($turn + @(Ev "2026-10-05T03:00:00Z" "task_complete")))
    Check ($s.newestEventAt.state -eq "unknown") "a time in the future makes the age unknown"
    $s = State (Write-Lines "newkind" @($turn + @((Ev "2026-10-02T10:00:06Z" "task_complete"), (Ev "2026-10-02T10:00:07Z" "brand_new"))))
    $u = @(Get-HordeUnsurveyedVersions -TurnState $s)
    Check ($u.Count -eq 1 -and $u[0] -ceq "0.159.3") "a kind the reader does not know makes the session's version unsurveyed"
    Check (@(Get-HordeUnsurveyedVersions -TurnState $idle).Count -eq 0) "CONTROL: the known kinds survey clean"
    Check ($idle.pendingAgents -eq 0 -and @($idle.openTasks).Count -eq 0 -and @($idle.crons).Count -eq 0 -and $idle.queued -eq 0) "Codex records no background agents, tasks, crons or queue the reader could see: empty, and the flags stay unverified"
} finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }

Complete-HordeSuite -Success "the codex idle reader pairs turns by turn_id and holds every rollout that is mid-turn"
