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
#   - -Proof -Target <the idle session> -Once sends the real nudge: one line typed into that session and
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
function New-Row { param([string]$Id, [string]$Idle = "yes", [string]$Box = "yes", [string]$Turn = "no") return [ordered]@{ id = $Id; label = "A"; role = "orchestrator"; parent = ""; retired = $false; reachable = "yes"; mail = "known"; unreadCount = 1; unreadableCount = 0; oldestUnreadAt = $old; idle = $Idle; boxEmpty = $Box; midTurn = $Turn; reason = ""; reasons = @(); limited = "no"; limitedUntil = $null; handedOverCount = 0; oldestHandedOverAt = $null; acked = "known"; lastAckedAt = $null; betweenTurns = "no" } }
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
foreach ($bad in @(@("-M", "live"), @("-Mo", "live"), @("-Mod", "live"), @("-L"), @("-Live"), @("-Shadow"), @("-Mode", "LIVE"), @("-Mode", "Live"), @("-Mode", "liv"), @("-Mode", "l"), @("-Mode", "both"), @("-Mode"), @("-Mode", "proof"), @("-M", "proof"), @("-P"), @("-Proof"))) {
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
Check ($help.code -eq 0 -and $help.out -like "*horde wake run*-Mode shadow|live*" -and $help.out -like "*wake run -Proof -Target <session id> -Once*") "help lists the command, its modes, and that a proof run names its one session"
Check (@(Read-FakeLog "argv.log").Count -eq 0) "CONTROL: nothing so far started the fleet's command"

Write-Host ""
Write-Host "=== with no flag the run is SHADOW: it reads the fleet and types nothing ===" -ForegroundColor Cyan
$once = Invoke-Wake $fleetHome @("run", "-Once")
Check ($once.code -eq 0) ("run -Once makes its pass and exits 0" + $(if ($once.code -ne 0) { ": " + $once.out } else { "" }))
Check ($once.out -like "*wake: SHADOW - nothing is nudged*" -and $once.out -like "*through the waker 'wezfleet'*" -and $once.out -notlike "*LIVE*") "its first line says SHADOW, loudly, and which waker it reads through"
Check ($once.out -like "*UNVERIFIED, so nothing this run journals is proof of them: nudge.pointer-only, state.box, state.turn, reach.unseen, nudge.guarded, state.limit, state.between-turns*") "and names the capabilities of that waker that are unverified"
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
# CALLED FROM INSIDE A SESSION THAT SETS DEFAULTS FOR PARAMETERS BY NAME, the run is still shadow: horde is
# started here by -Command, in a PowerShell whose $PSDefaultParameterValues says every -Mode is live.
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "powershell.exe"
$psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"`$PSDefaultParameterValues = @{ '*:Mode' = 'live'; '*:Once' = `$true }; & '" + (Join-Path $root "horde.ps1") + "' wake run -Once; exit `$LASTEXITCODE`""
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
foreach ($k in @{ HORDE_HOME = $fleetHome; WEZFLEET_ROOT = $fleetPin.path; USERPROFILE = $fakeProfile }.GetEnumerator()) { $psi.EnvironmentVariables[$k.Key] = $k.Value }
$inside = [System.Diagnostics.Process]::Start($psi)
$insideOut = $inside.StandardOutput.ReadToEndAsync(); $insideErr = $inside.StandardError.ReadToEndAsync()
$insideEnded = $inside.WaitForExit(180000)
if (-not $insideEnded) { try { $inside.Kill() } catch { } }
$insideSaid = $(if ($insideEnded) { "$($insideOut.Result)" + "$($insideErr.Result)" } else { "(did not end)" })
Check ($insideEnded -and $insideSaid -like "*wake: SHADOW*" -and $insideSaid -notlike "*-Mode live*" -and $insideSaid -notlike "*wake: LIVE*" -and @(Read-FakeLog "typed.log").Count -eq 0) ("called from a PowerShell whose `$PSDefaultParameterValues makes every -Mode live, wake run is still a SHADOW run: a command is given what was typed, not what a session defaults (" + ($insideSaid -split "`r?`n")[0] + ")")
$inside.Dispose()
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
Write-Host "=== -Proof -Target <session id> -Once: one pass, one named session, never a loop, with files of its own ===" -ForegroundColor Cyan
$typedBefore = @(Read-FakeLog "typed.log").Count
# ONE SESSION, NAMED: every proof command line that does not name a whole session id is a usage error,
# and so is a target given to a mode that has none. Nothing runs and nothing is typed.
foreach ($bad in @(@("-Proof", "-Once"), @("-Proof", "-Target", "A", "-Once"), @("-Proof", "-Target", $idle.Substring(0, 8), "-Once"), @("-Proof", "-Target", $idle.ToUpperInvariant(), "-Once"), @("-Proof", "-Target", "-Once"), @("-Proof", "-Target", $idle), @("-Mode", "shadow", "-Target", $idle, "-Once"), @("-Mode", "live", "-Target", $idle, "-Once"), @("-Mode", "live", "-Proof", "-Target", $idle, "-Once"), @("-Mode", "proof", "-Target", $idle, "-Once"), @("-Proof", "-Target", $idle, "-Once", "-TickSeconds", "3"), @("-Target", $idle, "-Once"), @("-Target", $idle), @("-Proof"), @("-Proof", "-Target", ($idle + "," + $busy), "-Once"))) {
    $r = Invoke-Wake $fleetHome (@("run") + $bad)
    Check ($r.code -eq 2 -and $r.out -like "*usage: horde wake run*" -and @(Read-FakeLog "typed.log").Count -eq $typedBefore -and -not (Test-Path -LiteralPath (Join-Path $wakeDir "heartbeat-proof.json"))) ("run " + ($bad -join " ") + " is a usage error: exit 2, the usage, nothing run and nothing typed")
}
# ...AND NONE OF THEM IS A QUESTION. A missing mandatory parameter makes PowerShell ASK when it can, and a
# horde started with its input open would wait there for ever. So the same incomplete forms, with the
# input held OPEN and never written, must end by themselves, as a usage error.
foreach ($bad in @(@("-Proof", "-Once"), @("-Proof", "-Target", $idle), @("-Proof"), @("-Target", $idle, "-Once"))) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $root "horde.ps1") + "`" wake run " + ($bad -join " ")
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    foreach ($k in @{ HORDE_HOME = $fleetHome; WEZFLEET_ROOT = $fleetPin.path; USERPROFILE = $fakeProfile }.GetEnumerator()) { $psi.EnvironmentVariables[$k.Key] = $k.Value }
    $asked = [System.Diagnostics.Process]::Start($psi)
    $outTask = $asked.StandardOutput.ReadToEndAsync(); $errTask = $asked.StandardError.ReadToEndAsync()
    $ended = $asked.WaitForExit(120000)
    if (-not $ended) { try { $asked.Kill() } catch { } }
    $code = $(if ($ended) { $asked.ExitCode } else { -1 })
    $said = $(if ($ended) { "$($outTask.Result)" + "$($errTask.Result)" } else { "" })
    Check ($ended -and $code -eq 2 -and $said -like "*usage: horde wake run*" -and $said -notlike "*Supply values*") ("run " + ($bad -join " ") + ", with its input held open, ends by itself as a usage error: it does not ask for what is missing (ended " + $ended + ", exit " + $code + ")")
    $asked.Dispose()
}
# AND SO FOR NO VERB AT ALL, AND FOR A PROOF WHOSE SWITCH WAS GIVEN AS FALSE: each ends by itself, with
# its input held open, as a usage error - exit 2 and the usage, like every other wrong form - and
# nothing is typed. (The whole command line is written here: the first has no "run" in it.)
foreach ($line in @("wake", ("wake run -Proof:`$false -Target " + $idle + " -Once"), ("wake run -Proof -Target " + $idle + " -Once:`$false"), ("wake run -Proof:`$false -Target " + $idle + " -Once:`$false"))) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $root "horde.ps1") + "`" " + $line
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    foreach ($k in @{ HORDE_HOME = $fleetHome; WEZFLEET_ROOT = $fleetPin.path; USERPROFILE = $fakeProfile }.GetEnumerator()) { $psi.EnvironmentVariables[$k.Key] = $k.Value }
    $asked = [System.Diagnostics.Process]::Start($psi)
    $outTask = $asked.StandardOutput.ReadToEndAsync(); $errTask = $asked.StandardError.ReadToEndAsync()
    $ended = $asked.WaitForExit(120000)
    if (-not $ended) { try { $asked.Kill() } catch { } }
    $code = $(if ($ended) { $asked.ExitCode } else { -1 })
    $said = $(if ($ended) { "$($outTask.Result)" + "$($errTask.Result)" } else { "" })
    Check ($ended -and $code -eq 2 -and $said -like "*usage: horde wake run*" -and $said -notlike "*Supply values*" -and $said -cnotlike "*Verb:*" -and @(Read-FakeLog "typed.log").Count -eq $typedBefore -and -not (Test-Path -LiteralPath (Join-Path $wakeDir "heartbeat-proof.json"))) ("horde " + $line + ", with its input held open, ends by itself as a usage error, exit 2, with nothing run or typed (ended " + $ended + ", exit " + $code + ": " + $(if ($said.Length -gt 160) { $said.Substring(0, 160) } else { $said }) + ")")
    $asked.Dispose()
}
$wrongFlag = Invoke-Wake $fleetHome @("status", "-Once")
Check ($wrongFlag.code -eq 1) "CONTROL: a refusal that is not about the form of the command line - a flag of run given to status - is still exit 1"
$stranger = "0a000000-0000-4000-8000-000000000099"
$astray = Invoke-Wake $fleetHome @("run", "-Proof", "-Target", $stranger, "-Once")
Check ($astray.code -eq 1 -and $astray.out -like "*proof-target-absent*" -and $astray.out -like "*nudged nobody*" -and @(Read-FakeLog "typed.log").Count -eq $typedBefore) ("a proof run aimed at a session the fleet does not list nudges nobody - not the idle session that is ready - says so, and exits 1" + $(if ($astray.code -ne 1) { ": " + $astray.out } else { "" }))
$aside = Invoke-Wake $fleetHome @("run", "-Proof", "-Target", $busy, "-Once")
Check ($aside.code -eq 0 -and @(Read-FakeLog "typed.log").Count -eq $typedBefore) "a proof run aimed at the busy session types nothing - and does not type into the idle one instead"
Remove-Item -LiteralPath (Join-Path $wakeDir "heartbeat-proof.json") -Force -ErrorAction SilentlyContinue
# A LEDGER THAT CANNOT BE READ: the proof does not start, and types nothing. Mended (removed), it runs.
$proofLedger = Join-Path $wakeDir "ledger-live.json"
[System.IO.File]::WriteAllText($proofLedger, "{ not json", $utf8)
$refusedRun = Invoke-Wake $fleetHome @("run", "-Proof", "-Target", $idle, "-Once")
Check ($refusedRun.code -eq 1 -and $refusedRun.out -like "*has not started*cannot be read*ledger-live.json*" -and $refusedRun.out -notlike "*pass 1 done*" -and @(Read-FakeLog "typed.log").Count -eq $typedBefore -and [System.IO.File]::ReadAllText($proofLedger) -ceq "{ not json") ("a proof run over a ledger file that cannot be read does not start: exit 1, the file named and left as it was, nothing typed" + $(if ($refusedRun.code -ne 1) { ": " + $refusedRun.out } else { "" }))
Remove-Item -LiteralPath $proofLedger -Force
# AND SO FOR WHAT WAS SAVED OF A SILENT FLEET: unreadable, the proof does not start, and types nothing.
$proofSilence = Join-Path $wakeDir "silence-live.json"
$silenceWas = $(if (Test-Path -LiteralPath $proofSilence) { [System.IO.File]::ReadAllText($proofSilence) } else { $null })
[System.IO.File]::WriteAllText($proofSilence, "{ not json", $utf8)
$refusedSilent = Invoke-Wake $fleetHome @("run", "-Proof", "-Target", $idle, "-Once")
Check ($refusedSilent.code -eq 1 -and $refusedSilent.out -like "*has not started*cannot be read*silence-live.json*" -and $refusedSilent.out -notlike "*pass 1 done*" -and @(Read-FakeLog "typed.log").Count -eq $typedBefore -and [System.IO.File]::ReadAllText($proofSilence) -ceq "{ not json") ("a proof run over a silence file that cannot be read does not start: exit 1, the file named and left as it was, nothing typed" + $(if ($refusedSilent.code -ne 1) { ": " + $refusedSilent.out } else { "" }))
if ($null -eq $silenceWas) { Remove-Item -LiteralPath $proofSilence -Force } else { [System.IO.File]::WriteAllText($proofSilence, $silenceWas, $utf8) }
Remove-Item -LiteralPath (Join-Path $wakeDir "heartbeat-proof.json") -Force -ErrorAction SilentlyContinue
$proofRun = Invoke-Wake $fleetHome @("run", "-Proof", "-Target", $idle, "-Once")
Check ($proofRun.code -eq 0 -and $proofRun.out -like ("*wake: PROOF - PROOF - PROOF - ONE PASS, AND AT MOST ONE REAL NUDGE, TO THE SESSION " + $idle + " AND NO OTHER, through the waker 'wezfleet'*") -and $proofRun.out -like "*UNVERIFIED, and what this pass is here to show: nudge.pointer-only, state.box, state.turn, reach.unseen, nudge.guarded, state.limit, state.between-turns*" -and $proofRun.out -like "*pass 1 done*PROOF*") ("run -Mode proof -Once makes its one pass and says PROOF, loudly, first and last" + $(if ($proofRun.code -ne 0) { ": " + $proofRun.out } else { "" }))
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
Write-Host "=== a fleet command only FOUND ON PATH: shadow reads through it and says so; a run that sends is refused ===" -ForegroundColor Cyan
# A home with no settings at all, and this scenario's fake checkout first on PATH: the waker finds the
# command by looking, as a shell typing wezfleet would. Nobody named it.
$pathHome = Join-Path $script:work "home-path-only"
New-Item -ItemType Directory -Path $pathHome -Force | Out-Null
$pathEnv = @{ HORDE_HOME = $pathHome; USERPROFILE = $fakeProfile; PATH = ($checkout + ";" + $env:PATH) }
$typedPath = @(Read-FakeLog "typed.log").Count
$nudgesPath = @(Read-FakeLog "argv.log" | Where-Object { "$(@($_.argv) -join ' ')" -like "mail nudge*" }).Count
$shadowPath = Invoke-HordeCliProcess -Root $root -HordeArgs @("wake", "run", "-Once") -Env $pathEnv
Check ($shadowPath.code -eq 0 -and $shadowPath.out -like "*wake: SHADOW*through the waker 'wezfleet'*" -and $shadowPath.out -like "*NOT NAMED IN A SETTING*found from the wezfleet command on PATH*" -and $shadowPath.out -like "*would-nudge*") ("a shadow run reads the fleet through a command found on PATH, and its banner says nobody named it" + $(if ($shadowPath.code -ne 0) { ": " + $shadowPath.out } else { "" }))
$proofPath = Invoke-HordeCliProcess -Root $root -HordeArgs @("wake", "run", "-Proof", "-Target", $idle, "-Once") -Env $pathEnv
Check ($proofPath.code -eq 1 -and $proofPath.out -like "*is refused*was not named in a setting*found from the wezfleet command on PATH*" -and $proofPath.out -notlike "*wake: PROOF*") ("a proof run through it is refused, exit 1, saying where the command was found" + $(if ($proofPath.code -ne 1) { ": " + $proofPath.out } else { "" }))
$livePath = Invoke-HordeCliProcess -Root $root -HordeArgs @("wake", "run", "-Mode", "live", "-Once") -Env $pathEnv
Check ($livePath.code -eq 1 -and $livePath.out -notlike "*wake: LIVE*") "and so is a live run"
Check (@(Read-FakeLog "typed.log").Count -eq $typedPath -and @(Read-FakeLog "argv.log" | Where-Object { "$(@($_.argv) -join ' ')" -like "mail nudge*" }).Count -eq $nudgesPath) "nothing was typed and no nudge was asked for by any of the three"
Check (@(Get-ChildItem -LiteralPath (Join-Path $pathHome "wake") | Where-Object { $_.Name -like "*-proof*" -or $_.Name -like "*-live*" }).Count -eq 0) "and the refused runs wrote no file: no lock, no heartbeat, no ledger"

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
$beside = Invoke-Wake $pinnedHome @("run", "-Proof", "-Target", "0a000000-0000-4000-8000-000000000001", "-Once")
Check ($beside.code -eq 1 -and $beside.out -like "*pass 1 done*PROOF*" -and $beside.out -like "*nudged nobody*" -and $beside.out -notlike "*already running*" -and (Test-Path -LiteralPath (Join-Path $pinnedWake "run-live.lock") -PathType Leaf) -and -not $run.p.HasExited) "a proof run beside the running SHADOW one is not refused: shadow has a lock of its own, and the runs that send share the other. (It finds no fleet, so it says it nudged nobody.)"
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

Write-Host ""
Write-Host "=== which session a watcher holds as its own is said: in the run's banner, and by status ===" -ForegroundColor Cyan
# The command is started as it is everywhere here, and inherits this scenario's own environment: so
# whichever is true of this scenario - it was started from inside a session, or from none - is true
# of the watcher, and core/Identity.ps1 says which. (Both lines, and that a heartbeat carries either,
# are held where a run can be handed its session: test/test-wake-run.ps1.)
. (Join-Path $root "core\Identity.ps1")
$me = Get-HordeSelfSessionId
$expect = $(if ($me.state -ceq "known") { "this watcher holds session " + $me.value + " as its own" } else { "this watcher holds no session as its own" })
$selfHome = Join-Path $script:work "home-self"
New-Item -ItemType Directory -Path $selfHome | Out-Null
$held = Invoke-Wake $selfHome @("run", "-Once")
Check ($held.code -eq 0 -and $held.out -like ("*wake: " + $expect + "*") -and $held.out.IndexOf("wake: " + $expect) -lt $held.out.IndexOf("pass 1 done")) ("a run says, with its banner and before its first pass, which session it holds as its own (" + $expect + ")")
$heldStatus = Invoke-Wake $selfHome @("status")
Check ($heldStatus.code -eq 0 -and $heldStatus.out -like ("*SHADOW: " + $expect + "*") -and $heldStatus.out -notlike "*LIVE: this watcher*" -and $heldStatus.out -notlike "*PROOF: this watcher*") "status says it of the watcher that ran, from its heartbeat, and says nothing of the kind for a mode that never ran"

Check ((Get-RealWakeListing) -ceq $realBefore) "the real home's wake folder is as it was"

} finally {
    if ($null -ne $run) { Stop-HordeCliRun $run }
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-wake-e2e-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction SilentlyContinue }
}

Complete-HordeSuite -Success "horde wake runs at the real command line: shadow by default, typing nothing; proof by name, one pass typing one line into the one session to wake; live refused through an unverified waker; a heartbeat and a journal for each"
