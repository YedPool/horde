# fleet-metrics/register-schedule.ps1 - registers the fleet meter's two Windows scheduled tasks.
#
#   "Fleet meter collect"  every 15 minutes:  horde meter collect
#   "Fleet limit watch"    every 2 minutes:   horde meter watch-limits
#
# RUN IT ONCE, by a person, with -WhatIf first to see what it would register. Nothing in the test suites
# runs it, and it changes nothing when -WhatIf is given. Run it again to change a setting: a task of the
# same name is replaced, never duplicated.
#
# WHY HORDE_HOME IS NOT WRITTEN INTO EACH TASK'S ACTION (T-0299). The tasks run as the user who registers them,
# so at each run horde resolves the home as every command does: HORDE_HOME, then the pointer file
# (%USERPROFILE%\.horde-home.json). A HORDE_HOME baked into the action would outrank the pointer and keep the old
# folder after horde home set. -HordeHome, when given, is only checked to be the home this shell resolves, so a
# task is never registered believing in a home it will not serve. A task registered under another account would
# need that account's profile to hold the pointer.
#
# WHY BELOW NORMAL PRIORITY (task priority 7). The collector reads a lot of text, and the machines that
# run the fleet are short of memory and CPU; a meter that slows the sessions it measures defeats itself.
#
# WHY IT RUNS ONLY WHEN THE USER IS LOGGED ON: the transcripts it reads are in the user's own profile and
# a task that must run when nobody is logged on needs a stored password. The tasks never overlap
# themselves (IgnoreNew), so a slow first collect makes the next start skip rather than pile up.
#
# NO CONSOLE WINDOW EVERY 2 MINUTES. The task runs in the person's session (it needs their profile), and
# a powershell.exe started there flashes a window even with -WindowStyle Hidden. Horde's own person-session
# jobs avoid it by starting the console host headless - `conhost.exe --headless <powershell.exe> ...` - and
# this reuses that exact form (core/schedule/WindowsTaskScheduler.ps1, ConvertTo-HordeTaskAction, measured
# there 2026-10-13 on Windows 11 26200: no window, command run in session 1). TWO THINGS FOLLOW, as there:
# the console host exits 0 whatever PowerShell exited with, so the task's "last result" says nothing about
# the meter - read `horde meter status` (data age) instead; and the flag is undocumented, so a Windows that
# drops it would fail the task outright. Both programs are named by their full system paths, never by a
# bare name a search path could answer with another program. The command itself goes in as -EncodedCommand
# (base64), so no quote in a path can end a string.
#
# DESIGN NOTE, NOT REGISTERED (PR 2a): A TEN-SECOND LIVE LOOP. `horde meter live` refreshes the per-session view
# (tokens_usage) from only the bytes written since the last pass. Measured on this fleet's real transcripts
# (2026-10-19): 6 to 50 ms of work per pass once a file has an offset, a 156 MB session read cold in under
# a second. The Windows task scheduler cannot repeat faster than once a minute and a node start is about a
# second on a busy box, so a 10-second loop is NOT a scheduled task. It would be ONE long-running process that
# calls the same refresh every 10 seconds (the collector module's runLive) and sleeps in between, started at
# logon, below normal priority, one instance (a lock file), and exiting when the database cannot be opened.
# Open questions for whoever builds it: who restarts it, and whether a panel that wants live numbers should
# instead ask for a refresh when it opens. Nothing here registers it, and no task for it exists.
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
    if ([System.IO.Path]::GetFullPath($HordeHome) -ine $effective) { throw ("-HordeHome is " + $HordeHome + " but this shell resolves " + $effective + "; the tasks resolve the home at each run, so point it first with horde home set -Path, or set HORDE_HOME here") }
}
# The default is worked out here: under 5.1 a script root used in a parameter default is empty.
if ($HordeScript -eq "") { $HordeScript = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) "horde.ps1" }
if (-not (Test-Path -LiteralPath $HordeScript -PathType Leaf)) { throw ("horde.ps1 not found at " + $HordeScript) }
$taskScript = (Resolve-Path -LiteralPath $HordeScript).Path

$sysDir = [System.Environment]::SystemDirectory
$consoleHost = [System.IO.Path]::Combine($sysDir, "conhost.exe")
$shell = [System.IO.Path]::Combine($sysDir, "WindowsPowerShell", "v1.0", "powershell.exe")
foreach ($needed in @($consoleHost, $shell)) { if (-not [System.IO.File]::Exists($needed)) { throw ($needed + " is not there, and the tasks cannot be run without a window") } }

function Get-MeterTaskCommand {
    # The command of one task as PowerShell text: horde, which resolves its home at each run (header).
    param([string]$MeterVerb)
    $scriptQ = $taskScript -replace "'", "''"
    return ("& '" + $scriptQ + "' meter " + $MeterVerb + "; exit $" + "LASTEXITCODE")
}

function Get-MeterTaskArgument {
    # The arguments of the headless console host: it starts the shell, which runs the encoded command.
    param([string]$MeterVerb)
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes((Get-MeterTaskCommand -MeterVerb $MeterVerb)))
    return ('--headless "' + $shell + '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand ' + $encoded)
}

$tasks = @(
    [pscustomobject]@{ name = "Fleet meter collect"; verb = "collect"; minutes = 15; limitMinutes = 30 },
    [pscustomobject]@{ name = "Fleet limit watch"; verb = "watch-limits"; minutes = 2; limitMinutes = 5 }
)

foreach ($t in $tasks) {
    $argument = Get-MeterTaskArgument -MeterVerb $t.verb
    if ($PSCmdlet.ShouldProcess(($TaskFolder + $t.name), ("register: every " + $t.minutes + " min, below normal priority, conhost.exe --headless powershell.exe -EncodedCommand [" + (Get-MeterTaskCommand -MeterVerb $t.verb) + "]"))) {
        $action = New-ScheduledTaskAction -Execute $consoleHost -Argument $argument
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $t.minutes) -RepetitionDuration (New-TimeSpan -Days 3650)
        $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes $t.limitMinutes) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        # 7 is BELOW_NORMAL_PRIORITY_CLASS; the cmdlet has no parameter for it.
        $settings.Priority = 7
        $who = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $principal = New-ScheduledTaskPrincipal -UserId $who -LogonType Interactive -RunLevel Limited
        [void](Register-ScheduledTask -TaskName $t.name -TaskPath $TaskFolder -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force)
        Write-Output ("registered " + $TaskFolder + $t.name + " (every " + $t.minutes + " min)")
    }
}
