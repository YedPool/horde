# END TO END: `horde wake run` and `horde wake status`, at the real command line, in both modes.
#
# The user of the wake watcher is whoever keeps the fleet running: they start it, leave it, and ask
# `horde wake status` whether it is still alive and what it has been doing. This scenario is that, with
# the fleet's command played by a fake in a folder of this scenario's:
#   - status in a home where it never ran says so, for each mode;
#   - a wrong command line is refused: every way of reaching a mode but -Mode in full with one of its
#     three exact values, a mistyped flag, a tick too long;
#   - WITH NO FLAG THE RUN IS SHADOW: one pass over a fleet with an idle session that has old unread mail,
#     a busy one and one with text in its box journals would-nudge for the first and nothing for the
#     others, and the fake's record shows nothing was typed and no nudge was ever asked for;
#   - -Mode live is REFUSED while the fleet's waker says its capabilities are unverified;
#   - -Mode proof -Once sends the real nudge: the same fleet, one line typed into the idle session and
#     no other; without -Once it is refused;
#   - each mode keeps its own heartbeat and journal, and status shows all three;
#   - in a home pinned to no fleet at all, a run says what it could not read, once, and keeps beating
#     until it is stopped; a second run on the same home is refused, and once the first is killed - its
#     lock file left behind - the next one starts.
# Every step is the shipped horde.ps1 run as its own process (test/lib/Cli.ps1).
#
# NOTHING REAL IS READ, WRITTEN OR TYPED INTO, and no terminal is involved. HORDE_HOME is a folder this
# scenario made and removes, and its settings name the fleet's checkout as a folder of this scenario's:
# an empty one (the messenger's pin, test/lib/MessengerPins.ps1, which pins the waker too) or one holding
# the fake. So the fleet's real command, on PATH or not, is never found. The fleet's stores are an empty
# folder of this scenario's (test/lib/FleetPin.ps1), and the user profile every child sees is an empty
# folder too, so the session stores a child looks for are not this machine's. The real home's wake folder
# is listed before and after and must not have changed (CONTRIBUTING 9).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "test\lib\FleetPin.ps1")
. (Join-Path $root "test\lib\MessengerPins.ps1")

$fleetPin = Enter-HordeTestEmptyFleet
$script:work = Join-Path $env:TEMP ("horde-wake-e2e-" + [guid]::NewGuid().ToString("N"))
$pinnedHome = Join-Path $script:work "home"
$fleetHome = Join-Path $script:work "home-with-fleet"
$fakeProfile = Join-Path $script:work "profile"
$checkout = Join-Path $script:work "checkout"
foreach ($d in @($pinnedHome, $fleetHome, $fakeProfile, $checkout)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-RealWakeListing {
    $real = Join-Path (Join-Path "$env:USERPROFILE" ".horde") "wake"
    if (-not (Test-Path -LiteralPath $real)) { return "(no wake folder)" }
    return (@(Get-ChildItem -LiteralPath $real -Force | Sort-Object Name | ForEach-Object { $_.Name + "|" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks }) -join ";")
}
$realBefore = Get-RealWakeListing
function Invoke-Wake { param([string]$HordeHome, [string[]]$HordeArgs) return (Invoke-HordeCliProcess -Root $root -HordeArgs (@("wake") + $HordeArgs) -Env @{ HORDE_HOME = $HordeHome; WEZFLEET_ROOT = $fleetPin.path; USERPROFILE = $fakeProfile }) }
function Read-Journal {
    param([string]$HordeHome, [string]$Leaf)
    $path = Join-Path $HordeHome ("wake\" + $Leaf)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
    return @([System.IO.File]::ReadAllLines($path) | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_ | ConvertFrom-Json })
}
function Read-FakeLog {
    param([string]$Leaf)
    $path = Join-Path $checkout $Leaf
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
    return @([System.IO.File]::ReadAllLines($path) | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_ | ConvertFrom-Json })
}

$run = $null
try {

# THE PINNED HOME: every messenger pinned to nothing, which names the fleet's checkout as an empty folder
# for the waker too (they read one setting).
$null = Set-HordeTestMessengerPins -Root $root -HordeHome $pinnedHome
# THE HOME WITH A FLEET: the same setting names a folder holding the fake as the fleet's command.
Copy-Item -LiteralPath (Join-Path $root "wakers\wezfleet\test\FakeWezfleet.ps1") -Destination (Join-Path $checkout "wezfleet.ps1")
foreach ($marker in @("lib\Mail.ps1", "commands\mail.ps1")) {
    $mp = Join-Path $checkout $marker
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $mp) | Out-Null
    [System.IO.File]::WriteAllText($mp, "# a marker stub for the wake scenario`r`n")
}
$idle = "0a000000-0000-4000-8000-000000000001"; $busy = "0a000000-0000-4000-8000-000000000002"; $typing = "0a000000-0000-4000-8000-000000000003"
$old = [datetime]::UtcNow.AddMinutes(-10).ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
function New-Row { param([string]$Id, [string]$Idle = "yes", [string]$Box = "yes", [string]$Turn = "no") return [ordered]@{ id = $Id; label = "A"; role = "orchestrator"; parent = ""; retired = $false; reachable = "yes"; mail = "known"; unreadCount = 1; unreadableCount = 0; oldestUnreadAt = $old; idle = $Idle; boxEmpty = $Box; midTurn = $Turn; reason = ""; reasons = @() } }
$rows = @((New-Row $idle), (New-Row $busy -Idle "no" -Turn "yes"), (New-Row $typing -Box "no"))
[System.IO.File]::WriteAllText((Join-Path $checkout "fleet.json"), ("[" + ((@($rows | ForEach-Object { ConvertTo-Json -InputObject $_ -Compress -Depth 4 })) -join ",") + "]"), $utf8)
New-Item -ItemType Directory -Path (Join-Path $fleetHome "settings") -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $fleetHome "settings\messenger-wezfleet.json"), ([pscustomobject]@{ schemaVersion = 1; settings = [pscustomobject]@{ root = $checkout } } | ConvertTo-Json -Compress -Depth 3), $utf8)
$wakeDir = Join-Path $fleetHome "wake"

Write-Host ""
Write-Host "=== a home where the watcher never ran, and a wrong command line ===" -ForegroundColor Cyan
$status = Invoke-Wake $fleetHome @("status")
Check ($status.code -eq 0 -and $status.out -like "*LIVE: it has never run*" -and $status.out -like "*PROOF: it has never run*" -and $status.out -like "*SHADOW: it has never run*" -and $status.out -like "*LIVE: journal empty*" -and $status.out -like "*SHADOW: journal empty*") "status says, for each mode, that the watcher has never run here and its journal is empty"
Check (-not (Test-Path -LiteralPath $wakeDir)) "and asking made no wake folder"
# A HOME THAT EARLIER BUILDS RAN IN: their unsuffixed files, written in shadow, are no mode's history.
$legacyHome = Join-Path $script:work "home-of-earlier-builds"
New-Item -ItemType Directory -Path (Join-Path $legacyHome "wake") -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $legacyHome "wake\heartbeat.json"), ('{"at":"' + [datetime]::UtcNow.AddSeconds(-4439).ToString("o", [System.Globalization.CultureInfo]::InvariantCulture) + '","pid":7,"pass":900,"shadow":true,"tickSeconds":3}'), $utf8)
[System.IO.File]::WriteAllText((Join-Path $legacyHome "wake\journal.jsonl"), ('{"at":"2026-10-12T07:00:00.0000000Z","kind":"would-nudge","id":"x","outcome":"would-nudge","reason":"an old shadow line"}' + "`n"), $utf8)
$status = Invoke-Wake $legacyHome @("status")
Check ($status.code -eq 0 -and $status.out -like "*LIVE: it has never run*" -and $status.out -like "*SHADOW: it has never run*" -and $status.out -notlike "*STALE*" -and $status.out -notlike "*an old shadow line*") "in a home earlier builds ran in, status says neither mode has ever run - not that a live watcher is dead, and not their old shadow lines as a journal"
# THE MODE IS -Mode, IN FULL, WITH ONE OF THREE VALUES, EXACTLY. Every other way of reaching a mode is
# a usage error, and nothing runs - above all the ones that used to be, or could be read as, a live run.
foreach ($bad in @(@("-M", "live"), @("-Mo", "live"), @("-Mod", "live"), @("-L"), @("-Live"), @("-Shadow"), @("-Mode", "LIVE"), @("-Mode", "Live"), @("-Mode", "liv"), @("-Mode", "l"), @("-Mode", "both"), @("-Mode"), @("-M", "proof"), @("-P"))) {
    $r = Invoke-Wake $fleetHome (@("run") + $bad + @("-Once"))
    Check ($r.code -eq 2 -and $r.out -like "*usage: horde wake run*" -and -not (Test-Path -LiteralPath $wakeDir)) ("run " + ($bad -join " ") + " is a usage error: exit 2, the usage, and nothing run")
}
$typo = Invoke-Wake $fleetHome @("run", "-Shadwo")
Check ($typo.code -eq 2 -and $typo.out -like "*usage: horde wake run*") "a mistyped flag exits 2 with the usage"
$slow = Invoke-Wake $fleetHome @("run", "-Once", "-TickSeconds", "301")
Check ($slow.code -eq 2 -and -not (Test-Path -LiteralPath $wakeDir)) "a tick longer than 300 s is refused at the command line"
$wrongVerb = Invoke-Wake $fleetHome @("status", "-Mode", "live")
Check ($wrongVerb.code -eq 1 -and $wrongVerb.out -like "*belongs to wake run*") "a flag of run given to status is refused, not ignored"
$help = Invoke-HordeCliProcess -Root $root -HordeArgs @("--help") -Env @{ HORDE_HOME = $fleetHome }
Check ($help.code -eq 0 -and $help.out -like "*horde wake run*-Mode shadow|proof|live*") "help lists the command and its three modes"
Check (@(Read-FakeLog "argv.log").Count -eq 0) "CONTROL: nothing so far started the fleet's command"

Write-Host ""
Write-Host "=== with no flag the run is SHADOW: it reads the fleet and types nothing ===" -ForegroundColor Cyan
$once = Invoke-Wake $fleetHome @("run", "-Once")
Check ($once.code -eq 0) ("run -Once makes its pass and exits 0" + $(if ($once.code -ne 0) { ": " + $once.out } else { "" }))
Check ($once.out -like "*wake: SHADOW - nothing is nudged*" -and $once.out -like "*through the waker 'wezfleet'*" -and $once.out -notlike "*LIVE*") "its first line says SHADOW, loudly, and which waker it reads through"
Check ($once.out -like "*UNVERIFIED, so nothing this run journals is proof of them: nudge.pointer-only, state.box, state.turn, reach.unseen, nudge.guarded*") "and names the capabilities of that waker that are unverified"
Check ($once.out -like "*pass 1 done*shadow*") "and its last that its one pass is done, in shadow"
$lines = @(Read-Journal $fleetHome "journal-shadow.jsonl")
Check (@($lines | Where-Object { $_.kind -ceq "would-nudge" -and $_.id -ceq $idle }).Count -eq 1) "the journal says would-nudge for the idle session with an empty box and old unread mail"
Check (@($lines | Where-Object { $_.id -ceq $busy -or $_.id -ceq $typing }).Count -eq 0) "and nothing for the busy one or the one with text in its box"
Check (@($lines | Where-Object { @("nudge", "post", "stall") -ccontains $_.kind }).Count -eq 0) "no line of it is a nudge, a post or a stall notice"
Check (@(Read-FakeLog "typed.log").Count -eq 0) "the fleet's record shows nothing was typed into any session"
$asked = @(Read-FakeLog "argv.log" | ForEach-Object { @($_.argv) -join " " })
Check (@($asked | Where-Object { $_ -clike "mail nudge*" }).Count -eq 0 -and @($asked | Where-Object { $_ -ceq "mail state -Json" }).Count -eq 1) ("and the fleet's command was never asked to nudge: it was asked for the fleet's state once (" + ($asked -join " | ") + ")")
Check (@($asked | Where-Object { $_ -clike ("mail state -To " + $idle + " *") }).Count -eq 1 -and @($asked | Where-Object { $_ -clike ("mail state -To " + $busy + " *") }).Count -eq 0) "a pane was read for the one candidate, and not for the session that is not idle"
$names = @(Get-ChildItem -LiteralPath $wakeDir | ForEach-Object { $_.Name } | Sort-Object)
Check (($names -join ",") -ceq "heartbeat-shadow.json,journal-shadow.jsonl,ledger-shadow.json,run-shadow.lock") ("it wrote the shadow run's own files and no file of a live run (" + ($names -join ",") + ")")
$explicit = Invoke-Wake $fleetHome @("run", "-Mode", "shadow", "-Once")
Check ($explicit.code -eq 0 -and $explicit.out -like "*wake: SHADOW*" -and @(Read-FakeLog "typed.log").Count -eq 0) "-Mode shadow, the explicit form, is the same shadow run"

Write-Host ""
Write-Host "=== -Mode live is refused: the fleet's waker has not yet been shown against the real command ===" -ForegroundColor Cyan
$liveRun = Invoke-Wake $fleetHome @("run", "-Mode", "live", "-Once")
Check ($liveRun.code -eq 1 -and $liveRun.out -notlike "*wake: LIVE*") ("run -Mode live -Once is refused, exit 1" + $(if ($liveRun.code -ne 1) { ": " + $liveRun.out } else { "" }))
Check ($liveRun.out -like "*needs an installed waker*" -and $liveRun.out -like "*wezfleet: does not offer*(it says unverified)*") "it says why: no waker offers every capability, and the fleet's says unverified"
Check (@(Read-FakeLog "typed.log").Count -eq 0 -and @(Read-FakeLog "argv.log" | Where-Object { "$($_.argv)" -like "*mail nudge*" }).Count -eq 0) "nothing was typed, and no nudge was asked for"
Check (@(Get-ChildItem -LiteralPath $wakeDir | Where-Object { $_.Name -like "*-live*" }).Count -eq 0) "and no file of a live run was written: no heartbeat that would make a live watcher look alive, no lock"

Write-Host ""
Write-Host "=== -Mode proof: one pass of real nudges, never a loop, with files of its own ===" -ForegroundColor Cyan
$typedBefore = @(Read-FakeLog "typed.log").Count
$loop = Invoke-Wake $fleetHome @("run", "-Mode", "proof")
Check ($loop.code -eq 1 -and $loop.out -like "*add -Once*" -and @(Read-FakeLog "typed.log").Count -eq $typedBefore -and -not (Test-Path -LiteralPath (Join-Path $wakeDir "heartbeat-proof.json"))) "a proof run without -Once is refused, and nothing is typed: it is never a loop"
$proofRun = Invoke-Wake $fleetHome @("run", "-Mode", "proof", "-Once")
Check ($proofRun.code -eq 0 -and $proofRun.out -like "*wake: PROOF - PROOF - PROOF - ONE PASS OF REAL NUDGES through the waker 'wezfleet'*" -and $proofRun.out -like "*UNVERIFIED, and what this pass is here to show: nudge.pointer-only, state.box, state.turn, reach.unseen, nudge.guarded*" -and $proofRun.out -like "*pass 1 done*PROOF*") ("run -Mode proof -Once makes its one pass and says PROOF, loudly, first and last" + $(if ($proofRun.code -ne 0) { ": " + $proofRun.out } else { "" }))
$typedNow = @(Read-FakeLog "typed.log")
Check ($typedNow.Count -eq 1 -and $typedBefore -eq 0 -and $typedNow[0].id -ceq $idle -and "$($typedNow[0].text)" -cnotmatch '[\x00-\x1F]') "the fleet's record shows one line typed, into the idle session, and no other: a proof run's nudge is real"
$proofLines = @(Read-Journal $fleetHome "journal-proof.jsonl")
Check (@($proofLines | Where-Object { $_.kind -ceq "nudge" -and $_.id -ceq $idle -and $_.outcome -ceq "woken" -and $null -ne $_.PSObject.Properties["elapsedMs"] }).Count -eq 1 -and @($proofLines | Where-Object { @("post", "stall", "tell") -ccontains $_.kind }).Count -eq 0) "the proof run's own journal says nudge, woken, with how long the nudge took, and nothing was posted"
$proofBeat = [System.IO.File]::ReadAllText((Join-Path $wakeDir "heartbeat-proof.json")) | ConvertFrom-Json
Check ($proofBeat.mode -ceq "proof" -and $proofBeat.shadow -eq $false -and $proofBeat.pass -eq 1 -and $proofBeat.tickSeconds -eq 3) "and a heartbeat of its own, saying proof"
Check (@(Read-Journal $fleetHome "journal-shadow.jsonl" | Where-Object { $_.kind -ceq "nudge" }).Count -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $wakeDir "heartbeat-live.json"))) "the shadow journal holds no nudge, and the proof run left no live heartbeat"

Write-Host ""
Write-Host "=== status shows both modes; a watcher that died is called stale, by its own tick ===" -ForegroundColor Cyan
$status = Invoke-Wake $fleetHome @("status")
Check ($status.code -eq 0 -and $status.out -like "*LIVE: it has never run*" -and $status.out -match "PROOF: heartbeat \d+ s ago, fresh" -and $status.out -match "SHADOW: heartbeat \d+ s ago, fresh") "status shows a fresh heartbeat for the two modes that ran, and says the live watcher never has"
Check ($status.out -like "*LIVE: journal empty*" -and $status.out -like "*PROOF: journal, the last*" -and $status.out -like "*SHADOW: journal, the last*" -and $status.out -like "*would-nudge*" -and $status.out -like "*woken*") "and each mode's last journal lines"
$stale = [datetime]::UtcNow.AddSeconds(-600).ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
[System.IO.File]::WriteAllText((Join-Path $wakeDir "heartbeat-live.json"), ('{"at":"' + $stale + '","pid":1,"pass":40,"shadow":false,"tickSeconds":3}'), $utf8)
$status = Invoke-Wake $fleetHome @("status")
Check ($status.out -match "LIVE: heartbeat \d+ s ago, STALE[^
]*not running" -and $status.out -match "SHADOW: heartbeat \d+ s ago, fresh") "a live heartbeat ten minutes old is STALE while the shadow one is fresh: a shadow run does not make a dead live watcher look alive"
[System.IO.File]::WriteAllText((Join-Path $wakeDir "heartbeat-live.json"), ('{"at":"' + $stale + '","pid":1,"pass":40,"shadow":false,"tickSeconds":300}'), $utf8)
$status = Invoke-Wake $fleetHome @("status")
# One line at a time: "LIVE ... fresh" must not be satisfied by the shadow line's "fresh" further down.
Check ($status.out -match "LIVE: heartbeat \d+ s ago, fresh" -and $status.out -notmatch "LIVE: heartbeat \d+ s ago, STALE") "the same heartbeat from a watcher that beats every 300 s is fresh: stale is three of its ticks"

Write-Host ""
Write-Host "=== a home pinned to no fleet: it says what it could not read, once, and keeps beating ===" -ForegroundColor Cyan
$pinnedWake = Join-Path $pinnedHome "wake"
$beatPath = Join-Path $pinnedWake "heartbeat-shadow.json"
$run = Start-HordeCliRun -Root $root -HordeArgs @("wake", "run", "-TickSeconds", "1") -Env @{ HORDE_HOME = $pinnedHome; WEZFLEET_ROOT = $fleetPin.path; USERPROFILE = $fakeProfile }
$said = Wait-HordeCliLine -Run $run -Like "*wake: SHADOW*" -Seconds 60
Check ($null -ne $said) "the loop starts and says SHADOW"
$deadline = (Get-Date).AddSeconds(90)
$pass = 0
do {
    Start-Sleep -Milliseconds 500
    try { $pass = [long](([System.IO.File]::ReadAllText($beatPath) | ConvertFrom-Json).pass) } catch { $pass = 0 }
} while (($pass -lt 3 -or $pass -ge 60) -and (Get-Date) -lt $deadline)
Check ($pass -ge 3 -and $pass -lt 60) ("its heartbeat moves on, pass after pass (" + $pass + ")")
Check (-not $run.p.HasExited) "and it is still running: it does not stop by itself"
$second = Invoke-Wake $pinnedHome @("run", "-Once")
Check ($second.code -eq 1 -and $second.out -like "*shadow wake run is already running*" -and $second.out -notlike "*pass 1 done*") "a second shadow run on the same home is refused at once, saying one is running"
# A RUN IN ANOTHER MODE IS NOT THE SAME RUN: the lock is per mode. (No fleet here: its one pass can
# reach nobody.)
$beside = Invoke-Wake $pinnedHome @("run", "-Mode", "proof", "-Once")
Check ($beside.code -eq 0 -and $beside.out -like "*pass 1 done*PROOF*" -and (Test-Path -LiteralPath (Join-Path $pinnedWake "run-proof.lock") -PathType Leaf) -and -not $run.p.HasExited) ("a proof run beside the running shadow one is not refused: each mode has a lock of its own" + $(if ($beside.code -ne 0) { ": " + $beside.out } else { "" }))
$pinnedLines = @(Read-Journal $pinnedHome "journal-shadow.jsonl")
Check (@($pinnedLines | Where-Object { $_.kind -ceq "skip-unknown" -and $_.id -ceq "" -and "$($_.reason)" -like "*not a wezfleet checkout*" }).Count -eq 1) "with no fleet to read, the journal says once that the targets are unknown, and why - not once a pass"
Check (@($pinnedLines | Where-Object { $_.kind -ceq "skip-unknown" -and $_.id -ceq "restore" }).Count -eq 1) "and once that the restore source could not read the sessions of this scenario's empty profile"
Stop-HordeCliRun $run
$null = $run.p.WaitForExit(10000)
Check ($run.p.HasExited) "stopped, it is gone"
# It was KILLED, so it released nothing itself: its lock file is still there.
Check (Test-Path -LiteralPath (Join-Path $pinnedWake "run-shadow.lock") -PathType Leaf) "CONTROL: the killed run left its lock file behind"
$third = Invoke-Wake $pinnedHome @("run", "-Once")
Check ($third.code -eq 0 -and $third.out -like "*pass 1 done*") "and the lock a dead run left blocks nobody: the next run starts"
Check (@(Read-Journal $pinnedHome "journal-shadow.jsonl" | Where-Object { @("nudge", "post", "stall", "would-nudge") -ccontains $_.kind }).Count -eq 0) "nothing was nudged, or would have been: there was no fleet"
Check (@(Get-ChildItem -LiteralPath $fleetPin.path -Recurse -File).Count -eq 0) "nothing was written into the fleet's folder"

Check ((Get-RealWakeListing) -ceq $realBefore) "the real home's wake folder is as it was"

} finally {
    if ($null -ne $run) { Stop-HordeCliRun $run }
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-wake-e2e-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction SilentlyContinue }
}

Complete-HordeSuite -Success "horde wake runs at the real command line: shadow by default, typing nothing; proof by name, one pass typing one line into the one session to wake; live refused through an unverified waker; a heartbeat and a journal for each"
