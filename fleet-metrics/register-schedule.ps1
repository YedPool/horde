# fleet-metrics/register-schedule.ps1 - registers the fleet meter's two Windows scheduled tasks.
#
#   "Fleet meter collect"  every 15 minutes:  horde meter collect
#   "Fleet limit watch"    every 2 minutes:   horde meter watch-limits
#
# RUN IT ONCE, by a person, with -WhatIf first to see what it would register. Nothing in the test suites
# runs it, and it changes nothing when -WhatIf is given. Run it again to change a setting: a task of the
# same name is replaced, never duplicated.
#
# WHY HORDE_HOME IS WRITTEN INTO EACH TASK'S ACTION. A scheduled task starts with the user's environment
# as the task service sees it, and HORDE_HOME is not set at user level on this fleet's machines. The
# meter has no default home on purpose (fleet-metrics/home.mjs), so without it every run would fail with
# "HORDE_HOME is not set". The value is -HordeHome, which has no default either, for the same reason.
#
# WHY BELOW NORMAL PRIORITY (task priority 7). The collector reads a lot of text, and the machines that
# run the fleet are short of memory and CPU; a meter that slows the sessions it measures defeats itself.
#
# WHY IT RUNS ONLY WHEN THE USER IS LOGGED ON: the transcripts it reads are in the user's own profile and
# a task that must run when nobody is logged on needs a stored password. The tasks never overlap
# themselves (IgnoreNew), so a slow first collect makes the next start skip rather than pile up.
#
# POWERSHELL 5.1: no 2>&1, no $Args/$Home/$PID parameters (CONTRIBUTING 12). ASCII only.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$HordeHome,
    [string]$HordeScript = "",
    [string]$TaskFolder = "\Horde\"
)
$ErrorActionPreference = "Stop"

if (-not [System.IO.Path]::IsPathRooted($HordeHome)) { throw ("-HordeHome must be an absolute path, not '" + $HordeHome + "'") }
# The default is worked out here: under 5.1 a script root used in a parameter default is empty.
if ($HordeScript -eq "") { $HordeScript = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) "horde.ps1" }
if (-not (Test-Path -LiteralPath $HordeScript -PathType Leaf)) { throw ("horde.ps1 not found at " + $HordeScript) }
$taskHome = [System.IO.Path]::GetFullPath($HordeHome)
$taskScript = (Resolve-Path -LiteralPath $HordeScript).Path

function Get-MeterTaskArgument {
    # The PowerShell command line of one task: HORDE_HOME set in the task's own process, then horde.
    # Single quotes inside the values are doubled; the whole -Command is one double-quoted string.
    param([string]$MeterVerb)
    $homeQ = $taskHome -replace "'", "''"
    $scriptQ = $taskScript -replace "'", "''"
    $inner = "`$env:HORDE_HOME = '" + $homeQ + "'; & '" + $scriptQ + "' meter " + $MeterVerb
    return ("-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"" + $inner + "`"")
}

$tasks = @(
    [pscustomobject]@{ name = "Fleet meter collect"; verb = "collect"; minutes = 15; limitMinutes = 30 },
    [pscustomobject]@{ name = "Fleet limit watch"; verb = "watch-limits"; minutes = 2; limitMinutes = 5 }
)

foreach ($t in $tasks) {
    $argument = Get-MeterTaskArgument -MeterVerb $t.verb
    if ($PSCmdlet.ShouldProcess(($TaskFolder + $t.name), ("register: every " + $t.minutes + " min, below normal priority, powershell.exe " + $argument))) {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $argument
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
