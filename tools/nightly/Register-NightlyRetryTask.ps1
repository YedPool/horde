# tools/nightly/Register-NightlyRetryTask.ps1 - registers or updates the scheduled task \Horde\HordeNightlyRetry. T-0397.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\nightly\Register-NightlyRetryTask.ps1 [-Plan] [-WhatIf] [-HordeRoot <dir>]
#
# The task runs tools\nightly\NightlyRetry.ps1 when the current user logs on. That script decides from the evidence on
# disk whether to run the nightly net once more after a restart killed it, and does nothing (exit 0, tells nobody) on any
# other logon. It is a SEPARATE task from \Horde\HordeNightlyNet so the net's own refused-start report, which tells M, cannot
# fire on every daytime logon. Same settings as Register-NightlyTask.ps1: execution time limit 8 h 30 min (the net runs
# for hours), a second start while one runs is ignored, start on battery and do not stop on battery, runs as the current
# user (interactive, limited). There is no start time here, so no boundary and no clock-change trap. -Plan or -WhatIf prints
# the trigger, action and settings and registers nothing. Windows PowerShell 5.1 and 7. ASCII only.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$HordeRoot = "",
    [switch]$Plan
)
$ErrorActionPreference = "Stop"
if ($HordeRoot -eq "") { $HordeRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }

$taskName = "HordeNightlyRetry"
$taskPath = "\Horde\"
$script = Join-Path $HordeRoot "tools\nightly\NightlyRetry.ps1"
$ps51 = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$argument = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $script + '"'
$who = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
# One splat feeds the printed line and the call, so the dry run cannot say one thing and register another.
$batterySettings = @{ AllowStartIfOnBatteries = $true; DontStopIfGoingOnBatteries = $true }

Write-Host ("task " + $taskPath + $taskName)
Write-Host ("trigger: at logon of " + $who)
Write-Host ("action: " + $ps51 + " " + $argument)
Write-Host ("settings: execution time limit PT8H30M, multiple instances IgnoreNew, start on battery, not stopped on battery (" + (@($batterySettings.Keys | Sort-Object) -join " ") + ")")
if ($Plan -or $WhatIfPreference) { Write-Host "dry run: nothing registered"; exit 0 }
if (-not (Test-Path -LiteralPath $script)) { throw ("not found: " + $script) }

$action = New-ScheduledTaskAction -Execute $ps51 -Argument $argument -WorkingDirectory $HordeRoot
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $who
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 8 -Minutes 30) @batterySettings
$principal = New-ScheduledTaskPrincipal -UserId $who -LogonType Interactive -RunLevel Limited
if ($PSCmdlet.ShouldProcess($taskPath + $taskName, "register or update")) {
    [void](Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force)
    Write-Host "registered"
}
