# END TO END: `horde wake run` and `horde wake status`, at the real command line, in shadow.
#
# The user of the wake watcher is whoever keeps the fleet running: they start it, leave it, and ask
# `horde wake status` whether it is still alive and what it has been doing. This scenario is the
# watcher's first day, before any waker that can reach a real session ships:
#   - status in a home where it never ran says so;
#   - run without -Shadow is refused, in words, and writes nothing;
#   - run -Shadow -Once makes one pass: it says no waker is installed, runs the restore source anyway,
#     journals what it could not read, and leaves a heartbeat;
#   - status then shows a fresh heartbeat and the journal's lines, and a heartbeat left by a watcher
#     that died is called stale;
#   - run -Shadow, left looping, keeps beating until it is stopped; while it runs a second run on the
#     same home is refused, and once it is killed - its lock file left behind - the next one starts.
# Every step is the shipped horde.ps1 run as its own process (test/lib/Cli.ps1).
#
# NOTHING REAL IS READ OR WRITTEN, and no terminal is involved. HORDE_HOME is a folder this scenario
# made and removes. The fleet is an empty one of this scenario's (test/lib/FleetPin.ps1), and the user
# profile every child sees is an empty folder of this scenario's too, so the session stores a child
# looks for are not this machine's: it finds none, and says the restore source could not read them.
# The real home's wake folder is listed before and after and must not have changed (CONTRIBUTING 9).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "test\lib\FleetPin.ps1")
. (Join-Path $root "test\lib\MessengerPins.ps1")

$fleetPin = Enter-HordeTestEmptyFleet
$script:work = Join-Path $env:TEMP ("horde-wake-e2e-" + [guid]::NewGuid().ToString("N"))
$hordeHome = Join-Path $script:work "home"
$fakeProfile = Join-Path $script:work "profile"
New-Item -ItemType Directory -Path $hordeHome -Force | Out-Null
New-Item -ItemType Directory -Path $fakeProfile -Force | Out-Null
$cliEnv = @{ HORDE_HOME = $hordeHome; WEZFLEET_ROOT = $fleetPin.path; USERPROFILE = $fakeProfile }
$wakeDir = Join-Path $hordeHome "wake"
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-RealWakeListing {
    $real = Join-Path (Join-Path "$env:USERPROFILE" ".horde") "wake"
    if (-not (Test-Path -LiteralPath $real)) { return "(no wake folder)" }
    return (@(Get-ChildItem -LiteralPath $real -Force | Sort-Object Name | ForEach-Object { $_.Name + "|" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks }) -join ";")
}
$realBefore = Get-RealWakeListing
function Invoke-Wake { param([string[]]$HordeArgs) return (Invoke-HordeCliProcess -Root $root -HordeArgs (@("wake") + $HordeArgs) -Env $cliEnv) }
function Read-Journal {
    $path = Join-Path $wakeDir "journal.jsonl"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
    return @([System.IO.File]::ReadAllLines($path) | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_ | ConvertFrom-Json })
}

$run = $null
try {

# The messengers are pinned in the home every child uses, as in every scenario that starts horde: the
# watcher loads no messenger today, and the first change that makes it post must not find a real one here.
$null = Set-HordeTestMessengerPins -Root $root -HordeHome $hordeHome

Write-Host ""
Write-Host "=== a home where the watcher never ran ===" -ForegroundColor Cyan
$status = Invoke-Wake @("status")
Check ($status.code -eq 0 -and $status.out -like "*never run*" -and $status.out -like "*journal: empty*") "status says the watcher has never run here, and that its journal is empty"
Check (-not (Test-Path -LiteralPath $wakeDir)) "and asking made no wake folder"

Write-Host ""
Write-Host "=== run without -Shadow is refused ===" -ForegroundColor Cyan
$live = Invoke-Wake @("run", "-Once")
Check ($live.code -ne 0 -and $live.out -like "*needs -Shadow*" -and $live.out -like "*live nudging arrives with the first real waker*") "run without -Shadow fails, saying live nudging arrives with the first real waker"
Check (-not (Test-Path -LiteralPath $wakeDir)) "and it wrote nothing: no journal, no heartbeat"
$typo = Invoke-Wake @("run", "-Shadwo")
Check ($typo.code -eq 2 -and $typo.out -like "*usage: horde wake run*") "a mistyped flag exits 2 with the usage"
$slow = Invoke-Wake @("run", "-Shadow", "-Once", "-TickSeconds", "301")
Check ($slow.code -eq 2 -and -not (Test-Path -LiteralPath $wakeDir)) "a tick longer than 300 s is refused at the command line"
$wrongVerb = Invoke-Wake @("status", "-Shadow")
Check ($wrongVerb.code -eq 1 -and $wrongVerb.out -like "*belongs to wake run*") "a flag of run given to status is refused, not ignored"
$help = Invoke-HordeCliProcess -Root $root -HordeArgs @("--help") -Env $cliEnv
Check ($help.code -eq 0 -and $help.out -like "*horde wake run -Shadow*") "help lists the command"

Write-Host ""
Write-Host "=== one shadow pass ===" -ForegroundColor Cyan
$once = Invoke-Wake @("run", "-Shadow", "-Once")
Check ($once.code -eq 0) ("run -Shadow -Once makes its pass and exits 0" + $(if ($once.code -ne 0) { ": " + $once.out } else { "" }))
Check (@($once.out -split "`n" | Where-Object { $_ -like "*no waker is installed*" }).Count -eq 1) "it says, in one line, that no waker is installed"
Check ($once.out -like "*pass 1 done*") "and that its one pass is done"
$beatPath = Join-Path $wakeDir "heartbeat.json"
$beat = $null
if (Test-Path -LiteralPath $beatPath -PathType Leaf) { $beat = [System.IO.File]::ReadAllText($beatPath) | ConvertFrom-Json }
Check ($null -ne $beat -and $beat.pass -eq 1 -and $beat.shadow -eq $true -and $beat.pid -gt 0 -and $beat.tickSeconds -eq 3) "it left a heartbeat: pass 1, shadow, its process and its tick"
Check ((Test-Path -LiteralPath (Join-Path $wakeDir "ledger.json")) -eq $false -and (Test-Path -LiteralPath (Join-Path $wakeDir "restore.json")) -eq $false) "and it wrote no live state: neither ledger.json nor restore.json"
$lines = @(Read-Journal)
Check ($lines.Count -ge 1 -and @($lines | Where-Object { $_.kind -ceq "skip-unknown" -and $_.id -ceq "restore" }).Count -eq 1) "the restore source ran with no waker: the journal says it could not read the sessions of this scenario's empty profile"
Check (@($lines | Where-Object { @("nudge", "post", "stall") -ccontains $_.kind }).Count -eq 0) "and no line of the journal is a nudge, a post or a stall notice: shadow did nothing"
Check (@(Get-ChildItem -LiteralPath $fleetPin.path -Recurse -File).Count -eq 0) "nothing was written into the fleet's folder"

Write-Host ""
Write-Host "=== status, after it ran; and after a watcher died ===" -ForegroundColor Cyan
$status = Invoke-Wake @("status")
Check ($status.code -eq 0 -and $status.out -like "*heartbeat: * s ago, fresh*" -and $status.out -like "*pass 1*" -and $status.out -like "*shadow true*") "status shows a fresh heartbeat, its pass, and that it was shadow"
Check ($status.out -like "*journal: the last*line(s)*" -and $status.out -like "*skip-unknown*") "and the journal's last lines"
$old = [datetime]::UtcNow.AddSeconds(-600).ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
[System.IO.File]::WriteAllText($beatPath, ('{"at":"' + $old + '","pid":1,"pass":40,"shadow":true,"tickSeconds":3}'), $utf8)
$status = Invoke-Wake @("status")
Check ($status.code -eq 0 -and $status.out -like "*STALE*" -and $status.out -like "*not running*") "a heartbeat ten minutes old, from a watcher that beat every 3 s, is called stale: the watcher is not running"
[System.IO.File]::WriteAllText($beatPath, ('{"at":"' + $old + '","pid":1,"pass":40,"shadow":true,"tickSeconds":300}'), $utf8)
$status = Invoke-Wake @("status")
Check ($status.code -eq 0 -and $status.out -like "*fresh*" -and $status.out -notlike "*STALE*") "the same heartbeat from a watcher that beats every 300 s is fresh: stale is three of its ticks"

Write-Host ""
Write-Host "=== left running, it keeps beating until it is stopped ===" -ForegroundColor Cyan
$run = Start-HordeCliRun -Root $root -HordeArgs @("wake", "run", "-Shadow", "-TickSeconds", "1") -Env $cliEnv
$said = Wait-HordeCliLine -Run $run -Like "*no waker is installed*" -Seconds 60
Check ($null -ne $said) "the loop starts and says no waker is installed"
$deadline = (Get-Date).AddSeconds(60)
$pass = 0
do {
    Start-Sleep -Milliseconds 500
    try { $pass = [long](([System.IO.File]::ReadAllText($beatPath) | ConvertFrom-Json).pass) } catch { $pass = 0 }
} while (($pass -lt 3 -or $pass -ge 40) -and (Get-Date) -lt $deadline)
Check ($pass -ge 3 -and $pass -lt 40) ("its heartbeat moves on, pass after pass (" + $pass + ")")
Check (-not $run.p.HasExited) "and it is still running: it does not stop by itself"
$second = Invoke-Wake @("run", "-Shadow", "-Once")
Check ($second.code -eq 1 -and $second.out -like "*already running*" -and $second.out -notlike "*pass 1 done*") "a second run on the same home is refused at once, saying one is running"
Check (@(Read-Journal | Where-Object { $_.kind -ceq "skip-unknown" -and $_.id -ceq "restore" }).Count -eq 2) "an unknown that lasts is journaled once for the run, not once a pass"
Stop-HordeCliRun $run
$null = $run.p.WaitForExit(10000)
Check ($run.p.HasExited) "stopped, it is gone"
# It was KILLED, so it released nothing itself: its lock file is still there.
Check (Test-Path -LiteralPath (Join-Path $wakeDir "run-shadow.lock") -PathType Leaf) "CONTROL: the killed run left its lock file behind"
$third = Invoke-Wake @("run", "-Shadow", "-Once")
Check ($third.code -eq 0 -and $third.out -like "*pass 1 done*") "and the lock a dead run left blocks nobody: the next run starts"
Check (@(Read-Journal | Where-Object { @("nudge", "post", "stall") -ccontains $_.kind }).Count -eq 0) "and still no line of the journal is a nudge, a post or a stall notice"

Check ((Get-RealWakeListing) -ceq $realBefore) "the real home's wake folder is as it was"

} finally {
    if ($null -ne $run) { Stop-HordeCliRun $run }
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-wake-e2e-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction SilentlyContinue }
}

Complete-HordeSuite -Success "horde wake runs in shadow at the real command line: one pass or a loop, a heartbeat, a journal, and nothing nudged or posted"
