# FakeWezfleet.ps1 - a stand-in for the fleet's command, for the wezfleet waker's tests only.
#
# WHY A FAKE. The waker starts the fleet's command as a child process; the tests must see what that child
# was really handed and what it really did, without a real registry, a real pane or a real session - and
# no suite may ever run the real command, which reads and types into real terminals. The fixture copies
# this file into a temp folder as wezfleet.ps1, beside the marker files a checkout has, and the waker is
# pointed at that folder, so the program it starts is this script.
#
# WHAT IT KEEPS, all under its own folder and nowhere else:
#   fleet.json  the sessions, as a test wrote them: a list of rows with every member a row has, their
#               boxEmpty and midTurn being what the PANE holds (form A hides them, as the real one does)
#   argv.log    one JSON line per run: the arguments it received, as separate elements, its pid, the
#               program running it and that process's command line
#   typed.log   one JSON line per text "typed" into a session: { id; text } - the fake target. Only the
#               pointer line is ever written here, the same line whatever the session's mail says
#   mode.json   optional, per form (fleet | pane | nudge): { exit; stdout; stderr; hangSeconds }. stdout
#               is written as it is, with exit: usage text, garbage, two lines, a failure object - a
#               test scripts every answer the waker must survive
#
# THE CONTRACT IT PLAYS is the one the waker's header states (wakers/wezfleet/Waker.ps1):
#   mail state -Json                                   exit 0 { at; sessions: [ row ] }, boxEmpty and midTurn
#                                                      "unknown" in every row; no fleet.json: exit 1
#                                                      { at; sessions: null; reason: registry-absent; detail }
#   mail state -To <id> -TimeoutSeconds <n> -Json      exit 0 { at; session: row }; exit 3 { at; to; reason:
#                                                      absent; detail }; exit 2 for a missing -To or a
#                                                      timeout that is not a whole number above 0
#   mail nudge -To <id> -BudgetSeconds <n> -Json       exit 0 { outcome; reason; target; pane; instance; detail }:
#       refused      (reason budget-too-small) under 30 s of the budget is left: it does not start typing
#                    with too little time to finish, and NOTHING IS TYPED. No -BudgetSeconds is no limit;
#                    one that is not a whole number from 35 to 300 is exit 2, bad-budget. mode.json's
#                    nudge.slowStartSeconds is counted as time this script took to start, without
#                    waiting it out
#     every answer carries elapsedMs, a whole number of milliseconds since this script began, and rule:
#     between-turns-background-work for a woken of a session whose row says betweenTurns yes, else ""
#     (the real command's shape, read 2026-10-13)
#       unreachable  no such session, or its row says it cannot be reached
#       refused      it has no unread mail: there is nothing to nudge for; or (reason retired) the
#                    session is retired - and NOTHING IS TYPED
#       busy         its box is not empty (reason box-not-empty), or it is mid-turn or not idle (reason
#                    mid-turn, the real command's word) - and NOTHING IS TYPED
#       woken        the pointer line is "typed": one line appended to typed.log
#     exit 2 for an empty -To
#   labels reserved [-Json]                            exit 0. -Json: one line,
#                                                      {"schema":"wezfleet.labels.reserved","version":1,"labels":["RS","WW","SV"]};
#                                                      without it, one label a line. `labels` with
#                                                      anything else, or nothing, is exit 2. COPIED
#                                                      FROM THE REAL COMMAND'S OUTPUT (2026-10-13). A
#                                                      wezfleet from before the verb is played by
#                                                      mode.json's labels: a non-zero exit
#   box slash <id> <command> -Expect <words> -Reason <why>
#                                                      the fleet's checked slash command (hibernation's
#                                                      exit). Prints text, as the real one does, and
#                                                      exits 0 with "/exit" "typed" into typed.log as
#                                                      { id; text }, unless mode.json's box scripts the
#                                                      answer (exit, stdout, hangSeconds). Anything
#                                                      but slash is exit 1
param()
$ErrorActionPreference = "Stop"
$fakeClock = [System.Diagnostics.Stopwatch]::StartNew()
$root = $PSScriptRoot
$argvList = @($args | ForEach-Object { "$_" })
# HOW IT WAS STARTED is logged with what it was handed: the program running it, its pid, and that
# process's whole command line. A script called in-process from a test would show the test's own pid
# and command line here; started as the adapter starts the fleet's command, it shows a process of its
# own, the system PowerShell, with -File and this script.
[System.IO.File]::AppendAllText((Join-Path $root "argv.log"), ((@{ argv = $argvList; pid = $PID; program = (Get-Process -Id $PID).Path; commandLine = @([System.Environment]::GetCommandLineArgs()) } | ConvertTo-Json -Compress -Depth 4) + "`n"), [System.Text.Encoding]::ASCII)

function Get-FakeArg {
    param([string]$Name)
    for ($i = 0; $i -lt $argvList.Count - 1; $i++) { if ($argvList[$i] -ceq $Name) { return $argvList[$i + 1] } }
    return ""
}
function Write-FakeAnswer {
    # One line of ASCII JSON, and the exit code.
    param([int]$Exit, $Value)
    $json = (ConvertTo-Json -InputObject $Value -Compress -Depth 6)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $json.ToCharArray()) { if ([int]$ch -gt 0x7E) { [void]$sb.Append(('\u{0:x4}' -f [int]$ch)) } else { [void]$sb.Append($ch) } }
    [Console]::Out.WriteLine($sb.ToString())
    exit $Exit
}
function Get-FakeNow { return [datetime]::UtcNow.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture) }
function Test-Mode { param($M, [string]$Name) return ($null -ne $M -and $null -ne $M.PSObject.Properties[$Name]) }

$isLabels = ($argvList.Count -ge 1 -and $argvList[0] -ceq "labels")
if ($argvList.Count -ge 1 -and $argvList[0] -ceq "box") {
    $boxMode = $null
    $bm = Join-Path $root "mode.json"
    if (Test-Path -LiteralPath $bm) { $all = [System.IO.File]::ReadAllText($bm) | ConvertFrom-Json; if ($null -ne $all.PSObject.Properties["box"]) { $boxMode = $all.box } }
    if ($null -ne $boxMode -and $null -ne $boxMode.PSObject.Properties["hangSeconds"]) { Start-Sleep -Seconds ([int]$boxMode.hangSeconds) }
    if ($null -ne $boxMode -and $null -ne $boxMode.PSObject.Properties["stdout"]) { [Console]::Out.Write([string]$boxMode.stdout); exit ([int]$boxMode.exit) }
    if ($argvList.Count -lt 4 -or $argvList[1] -cne "slash") { [Console]::Out.WriteLine("fake wezfleet: only box slash is played"); exit 1 }
    [System.IO.File]::AppendAllText((Join-Path $root "typed.log"), ((@{ id = $argvList[2]; text = $argvList[3] } | ConvertTo-Json -Compress) + "`n"), [System.Text.Encoding]::ASCII)
    [Console]::Out.WriteLine("box slash " + $argvList[2] + " (pane 1): SUBMITTED - the text left the box.")
    exit 0
}
if (-not $isLabels -and ($argvList.Count -lt 2 -or $argvList[0] -cne "mail" -or @("state", "nudge") -cnotcontains $argvList[1])) { [Console]::Out.WriteLine("fake wezfleet: only mail state, mail nudge and labels reserved are played"); exit 1 }
$to = Get-FakeArg "-To"
$hasTo = ($argvList -ccontains "-To")
$form = "fleet"
if ($isLabels) { $form = "labels" } elseif ($argvList[1] -ceq "nudge") { $form = "nudge" } elseif ($hasTo) { $form = "pane" }

$mode = $null
$modePath = Join-Path $root "mode.json"
if (Test-Path -LiteralPath $modePath) { $mode = [System.IO.File]::ReadAllText($modePath) | ConvertFrom-Json }
$m = $null
if (Test-Mode $mode $form) { $m = $mode.$form }
if (Test-Mode $m "hangSeconds") { Start-Sleep -Seconds ([int]$m.hangSeconds) }
if (Test-Mode $m "stdout") {
    [Console]::Out.Write([string]$m.stdout)
    if (Test-Mode $m "stderr") { [Console]::Error.Write([string]$m.stderr) }
    exit ([int]$m.exit)
}

if ($form -ceq "labels") {
    if ($argvList.Count -lt 2 -or $argvList[1] -cne "reserved") { [Console]::Error.WriteLine("wezfleet labels: the one thing to ask for is: reserved (wezfleet labels reserved [-Json])"); exit 2 }
    if ($argvList -ccontains "-Json") { [Console]::Out.WriteLine('{"schema":"wezfleet.labels.reserved","version":1,"labels":["RS","WW","SV"]}') }
    else { foreach ($l in @("RS", "WW", "SV")) { [Console]::Out.WriteLine($l) } }
    exit 0
}

$fleetPath = Join-Path $root "fleet.json"
$rows = $null
# Held in a variable before it is wrapped: ConvertFrom-Json hands a list down the pipeline as ONE object.
if (Test-Path -LiteralPath $fleetPath) { $parsed = [System.IO.File]::ReadAllText($fleetPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json; $rows = @($parsed) }

if ($form -ceq "fleet") {
    if ($null -eq $rows) { Write-FakeAnswer 1 ([ordered]@{ at = (Get-FakeNow); sessions = $null; reason = "registry-absent"; detail = "there is no registry in the fake's folder" }) }
    # Form A reads no pane: the box and the turn are unknown in every row, whatever the pane holds.
    $shown = @($rows | ForEach-Object { $r = $_ | Select-Object *; $r.boxEmpty = "unknown"; $r.midTurn = "unknown"; $r })
    # A list of one is still a list on the wire.
    $json = '{"at":"' + (Get-FakeNow) + '","sessions":[' + ((@($shown | ForEach-Object { ConvertTo-Json -InputObject $_ -Compress -Depth 6 })) -join ",") + ']}'
    [Console]::Out.WriteLine($json)
    exit 0
}

if ($form -ceq "pane") {
    $seconds = 0
    if ($to -eq "" -or -not [int]::TryParse((Get-FakeArg "-TimeoutSeconds"), [ref]$seconds) -or $seconds -lt 1) { Write-FakeAnswer 2 ([ordered]@{ at = (Get-FakeNow); to = $to; reason = "bad-timeout"; detail = "a session and a whole number of seconds above 0 are needed" }) }
    $row = @(@($rows) | Where-Object { $null -ne $_ -and $_.id -ceq $to }) | Select-Object -First 1
    if ($null -eq $row) { Write-FakeAnswer 3 ([ordered]@{ at = (Get-FakeNow); to = $to; reason = "absent"; detail = "no session answers to that id" }) }
    Write-FakeAnswer 0 ([ordered]@{ at = (Get-FakeNow); session = $row })
}

# nudge
if ($to -eq "") { Write-FakeAnswer 2 ([ordered]@{ outcome = "unreachable"; reason = "bad-to"; target = ""; pane = ""; instance = ""; detail = "an empty -To" }) }
$row = @(@($rows) | Where-Object { $null -ne $_ -and $_.id -ceq $to }) | Select-Object -First 1
function Write-FakeNudge { param([string]$Outcome, [string]$Reason, [string]$Detail = "") Write-FakeAnswer 0 ([ordered]@{ outcome = $Outcome; reason = $Reason; target = $to; pane = "7"; instance = "fake-instance"; detail = $Detail; elapsedMs = [int]$fakeClock.ElapsedMilliseconds; rule = $(if ($Outcome -ceq "woken" -and "$($row.betweenTurns)" -ceq "yes") { "between-turns-background-work" } else { "" }) }) }
if ($null -eq $row -or $row.reachable -cne "yes") { Write-FakeNudge "unreachable" "no-pane" "no pane of that session was found" }
if ($row.retired -eq $true) { Write-FakeNudge "refused" "retired" "the session is retired; nothing is typed into a retired session" }
if ($null -eq $row.unreadCount -or $row.unreadCount -le 0) { Write-FakeNudge "refused" "no-unread-mail" "there is nothing to nudge for" }
# THE BUDGET, before anything is typed: with too little of it left, typing is not begun.
$budget = 0
if (($argvList -ccontains "-BudgetSeconds") -and (-not [int]::TryParse((Get-FakeArg "-BudgetSeconds"), [ref]$budget) -or $budget -lt 35 -or $budget -gt 300)) { Write-FakeAnswer 2 ([ordered]@{ outcome = "unreachable"; reason = "bad-budget"; target = $to; pane = ""; instance = ""; detail = "a budget is a whole number of seconds from 35 to 300"; elapsedMs = [int]$fakeClock.ElapsedMilliseconds }) }
# What is left of the budget, counted from this script's own start, against the 30 s typing may take.
$slowStart = 0
if (Test-Mode $m "slowStartSeconds") { $slowStart = [int]$m.slowStartSeconds }
if (($argvList -ccontains "-BudgetSeconds") -and ($budget - $slowStart - $fakeClock.Elapsed.TotalSeconds) -lt 30) { Write-FakeNudge "refused" "budget-too-small" ("less than 30 s of the " + $budget + " s budget is left, too little to type and send in") }
# THE GUARD, at the moment of typing: the pane as it is now.
if ($row.boxEmpty -cne "yes") { Write-FakeNudge "busy" "box-not-empty" "the input box holds unsent text" }
if ($row.midTurn -cne "no" -or $row.idle -cne "yes") { Write-FakeNudge "busy" "mid-turn" "the session says it is not idle; its own turn boundary delivers the mail; nothing typed" }
[System.IO.File]::AppendAllText((Join-Path $root "typed.log"), ((@{ id = $to; text = "You have unread fleet mail. Read it now." } | ConvertTo-Json -Compress) + "`n"), [System.Text.Encoding]::ASCII)
Write-FakeNudge "woken" "woken"
