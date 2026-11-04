# tools/nightly/Register-NightlyTask.ps1 - registers or updates the scheduled task \Horde\HordeNightlyNet. T-0397.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\nightly\Register-NightlyTask.ps1 [-Plan] [-WhatIf] [-HordeRoot <dir>] [-Hour 22]
#
# WHY IT IS IN THE REPO: the task was once registered by hand with StartBoundary 2026-10-23T21:00:00-05:00. An offset
# pins one UTC instant, so after the clocks changed (2026-11-01) it fired at 21:00 local, found the window closed and
# ran nothing for three nights. The schedule is wall-clock time: the daily trigger's StartBoundary carries NO offset
# and no Z (core Get-HordeNightlyTaskBoundary, tested without the scheduler).
#
# Settings kept from the task as it was: execution time limit 8 h 30 min, a second start while one runs is ignored,
# runs as the current user (interactive, limited), starts powershell on tools\NightlyNet.ps1 of -HordeRoot.
# -Plan or -WhatIf prints the boundary and the action and registers nothing. Windows PowerShell 5.1 and 7. ASCII only.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$HordeRoot = "",
    [ValidateRange(0, 23)][int]$Hour = 22,
    [switch]$Plan
)
$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\NightlyNet.ps1")
if ($HordeRoot -eq "") { $HordeRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }

$taskName = "HordeNightlyNet"
$taskPath = "\Horde\"
$script = Join-Path $HordeRoot "tools\NightlyNet.ps1"
$ps51 = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$argument = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $script + '"'
# The first night is tonight, or tomorrow if tonight's start has passed; the daily trigger repeats it.
$first = (Get-Date).Date
if ((Get-Date) -ge $first.AddHours($Hour)) { $first = $first.AddDays(1) }
$boundary = Get-HordeNightlyTaskBoundary -Date $first -Hour $Hour

Write-Host ("task " + $taskPath + $taskName)
Write-Host ("<StartBoundary>" + $boundary + "</StartBoundary>  (wall-clock, no offset), daily")
Write-Host ("action: " + $ps51 + " " + $argument)
Write-Host "settings: execution time limit PT8H30M, multiple instances IgnoreNew"
if ($Plan -or $WhatIfPreference) { Write-Host "dry run: nothing registered"; exit 0 }
if (-not (Test-Path -LiteralPath $script)) { throw ("not found: " + $script) }

$action = New-ScheduledTaskAction -Execute $ps51 -Argument $argument -WorkingDirectory $HordeRoot
$trigger = New-ScheduledTaskTrigger -Daily -At $first.AddHours($Hour)
# Set the string itself: whatever the cmdlet wrote, the stored boundary is exactly the offset-free one.
$trigger.StartBoundary = $boundary
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 8 -Minutes 30) -AllowStartIfOnBatteries
$who = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $who -LogonType Interactive -RunLevel Limited
if ($PSCmdlet.ShouldProcess($taskPath + $taskName, "register or update")) {
    [void](Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force)
    Write-Host "registered"
}
