# fleet-db/register-sync.ps1 - registers the ONE Windows scheduled task that keeps fleet.db current from the fleet's files.
#
#   "\Horde\Fleet db sync"   every 1 minute:  horde db sync
#
# RUN IT ONCE, by a person, with -WhatIf first to see what it would register. Nothing in the test suites registers it,
# and it changes nothing when -WhatIf is given. Run it again to change a setting: a task of the same name is replaced,
# never duplicated. Save the sources first (horde db sync -Save -Ledger .. -PrCache .. -Changelog .. -Cards ..
# -ThrallCard ..): a tick with none saved only logs the refusal.
#
# WHY ONE TASK, EVERY MINUTE (T-0389, M's order 2026-11-02). One tick is the clock for every fleet.db feed: the files step
# (task events, changelog, Orc cards) keeps its own five-minute pace in HORDE_HOME\fleet-db-sync-state.json, and the
# sessions step a later piece adds runs on every tick, in this same task. A minute is the shortest repeat the Windows
# scheduler allows. The task's whole action is `horde db sync`; all other policy lives in code that can be tested
# (fleet-db\sync.mjs, fleet-db\Sync.ps1), not in the task's settings.
#
# WHY HORDE_HOME IS NOT WRITTEN INTO THE ACTION (same reason as the fleet meter, fleet-metrics\register-schedule.ps1). The
# task runs as the user who registers it, so at each run horde resolves the home as every command does: HORDE_HOME, then
# the pointer file (%USERPROFILE%\.horde-home.json). A HORDE_HOME baked into the action would outrank the pointer and keep
# the old folder after horde home set. -HordeHome, when given, is only checked to be the home this shell resolves.
#
# WHY EACH SETTING:
#   priority 7 (BELOW_NORMAL)        a sync that slows the sessions it records defeats itself; the node child is also
#                                    lowered to below normal by the script, so both halves are polite.
#   MultipleInstances IgnoreNew      a slow tick makes the next start skip rather than pile up; fleet-db-sync.lock in
#                                    the script covers a hand `horde db sync` racing the task.
#   ExecutionTimeLimit 2 minutes     the script stops its own node child after 50 seconds, so this is only the net under
#                                    that: no tick can run past two ticks' time.
#   run only when the user is logged  the files it reads (status cards, the task ledger) are in the user's own profile, and a
#   on, Interactive, Limited          task that runs when nobody is logged on needs a stored password. No elevation is needed.
#   StartWhenAvailable               a tick missed while the machine slept runs when it wakes, and the next tick then finds
#                                    the files step due. (No "run missed ticks twice" catch-up: one run does it all.)
#   conhost.exe --headless ...       NO CONSOLE WINDOW EVERY MINUTE. A powershell.exe started in the person's session flashes
#                                    a window even with -WindowStyle Hidden; Horde's person-session jobs start the console host
#                                    headless (core/schedule/WindowsTaskScheduler.ps1, ConvertTo-HordeTaskAction, measured
#                                    there 2026-10-13 on Windows 11 26200). TWO THINGS FOLLOW: the console host exits 0
#                                    whatever PowerShell exited with, so the task's "last result" says nothing - read
#                                    HORDE_HOME\logs\fleet-db-sync.log or `horde db status` instead; and the flag is
#                                    undocumented, so a Windows that drops it would fail the task outright. Both programs are
#                                    named by their full system paths. The command goes in as -EncodedCommand (base64), so no
#                                    quote in a path can end a string.
#
# POWERSHELL 5.1: no 2>&1, no $Args/$Home/$PID parameters (CONTRIBUTING 12). ASCII only.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$HordeHome = "",
    [string]$HordeScript = "",
    [string]$TaskFolder = "\Horde\"
)
$ErrorActionPreference = "Stop"

. (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) "core") "Home.ps1")
$effective = (Resolve-HordeHome).path
if ($HordeHome -ne "") {
    if (-not (Test-HordeHomeRooted $HordeHome)) { throw ("-HordeHome must be an absolute path, not '" + $HordeHome + "'") }
    if ([System.IO.Path]::GetFullPath($HordeHome) -ine $effective) { throw ("-HordeHome is " + $HordeHome + " but this shell resolves " + $effective + "; the task resolves the home at each run, so point it first with horde home set -Path, or set HORDE_HOME here") }
}
# The default is worked out here: under 5.1 a script root used in a parameter default is empty.
if ($HordeScript -eq "") { $HordeScript = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) "horde.ps1" }
if (-not (Test-Path -LiteralPath $HordeScript -PathType Leaf)) { throw ("horde.ps1 not found at " + $HordeScript) }
$taskScript = (Resolve-Path -LiteralPath $HordeScript).Path

$sysDir = [System.Environment]::SystemDirectory
$consoleHost = [System.IO.Path]::Combine($sysDir, "conhost.exe")
$shell = [System.IO.Path]::Combine($sysDir, "WindowsPowerShell", "v1.0", "powershell.exe")
foreach ($needed in @($consoleHost, $shell)) { if (-not [System.IO.File]::Exists($needed)) { throw ($needed + " is not there, and the task cannot be run without a window") } }

$taskName = "Fleet db sync"
$everyMinutes = 1
$limitMinutes = 2

# The command as PowerShell text: horde, which resolves its home at each run (header).
$scriptQ = $taskScript -replace "'", "''"
$command = "& '" + $scriptQ + "' db sync; exit $" + "LASTEXITCODE"
$encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))
$argument = '--headless "' + $shell + '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand ' + $encoded

if ($PSCmdlet.ShouldProcess(($TaskFolder + $taskName), ("register: every " + $everyMinutes + " min, below normal priority, one instance, conhost.exe --headless powershell.exe -EncodedCommand [" + $command + "]"))) {
    $action = New-ScheduledTaskAction -Execute $consoleHost -Argument $argument
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $everyMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes $limitMinutes) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    # 7 is BELOW_NORMAL_PRIORITY_CLASS; the cmdlet has no parameter for it.
    $settings.Priority = 7
    $who = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $principal = New-ScheduledTaskPrincipal -UserId $who -LogonType Interactive -RunLevel Limited
    [void](Register-ScheduledTask -TaskName $taskName -TaskPath $TaskFolder -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force)
    Write-Output ("registered " + $TaskFolder + $taskName + " (every " + $everyMinutes + " min)")
}
