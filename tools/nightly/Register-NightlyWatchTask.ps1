# tools/nightly/Register-NightlyWatchTask.ps1 - registers or updates the scheduled task \Horde\HordeNightlyWatch. T-0397.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\nightly\Register-NightlyWatchTask.ps1 [-Plan] [-WhatIf] [-HordeRoot <dir>]
#       [-NoticeService <name> -NoticeSecretFile <path> -HordeHome <dir>] [-TellProgram <path>]
#
# The watcher (tools\nightly\NightlyWatch.ps1) runs once each morning at 07:15 local, after the nightly net's report
# deadline, and says so when the night that began yesterday did not run. Same rules as Register-NightlyTask.ps1:
#   - the daily trigger's StartBoundary is WALL-CLOCK time with NO offset and no Z (core Get-HordeNightlyTaskBoundary), so
#     it stays 07:15 across a clock change (an offset made the nightly task fire an hour early on 2026-11-01 to 11-03);
#   - runs as the current user (interactive, limited), the PC is not woken for it;
#   - StartWhenAvailable: a PC that was off at 07:15 runs it as soon as it is on, because a machine that was off is one of
#     the failures the watcher exists to catch;
#   - a second trigger at the logon of the same user, 5 minutes after it (T-0460, core New-HordeNightlyWatchTriggers):
#     on 2026-11-10 an update restarted the PC at 20:29 and it sat at the lock screen until 11:12 the next day. The task
#     runs only while its user is logged on, so the 07:15 run was skipped, and StartWhenAvailable did not catch it up at
#     the logon. Run at logon, the watcher judges the last finished night; the same morning twice is a duplicate.
# -NoticeService and -NoticeSecretFile (both or neither) are put on the task's command line to switch the founder's phone
# channel on; only the PATH of the secret file is stored, never its content. A scheduled task has no HORDE_HOME of its
# own, so -HordeHome names the home holding the notice service, or horde notify would refuse the service. -Plan or -WhatIf prints the boundary and the
# action and registers nothing. Windows PowerShell 5.1 and 7. ASCII only.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$HordeRoot = "",
    [ValidateRange(0, 23)][int]$Hour = 7,
    [ValidateRange(0, 59)][int]$Minute = 15,
    [string]$NoticeService = "",
    [string]$NoticeSecretFile = "",
    [string]$HordeHome = "",
    [string]$TellProgram = "",
    [switch]$Plan
)
$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\NightlyNet.ps1")
if ($HordeRoot -eq "") { $HordeRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
if (($NoticeService -eq "") -ne ($NoticeSecretFile -eq "")) { throw "-NoticeService and -NoticeSecretFile go together: give both or neither" }

$taskName = "HordeNightlyWatch"
$taskPath = "\Horde\"
$script = Join-Path $HordeRoot "tools\nightly\NightlyWatch.ps1"
$ps51 = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$argument = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $script + '"'
if ($NoticeService -ne "") { $argument += ' -NoticeService ' + $NoticeService + ' -NoticeSecretFile "' + $NoticeSecretFile + '"' }
if ($HordeHome -ne "") { $argument += ' -HordeHome "' + $HordeHome + '"' }
if ($TellProgram -ne "") { $argument += ' -TellProgram "' + $TellProgram + '"' }
# The first morning is today, or tomorrow if today's time has passed; the daily trigger repeats it.
$first = (Get-Date).Date
if ((Get-Date) -ge $first.AddHours($Hour).AddMinutes($Minute)) { $first = $first.AddDays(1) }
$who = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

# One task object, built without touching the scheduler: the dry run prints ITS triggers and the real run registers IT,
# so what -Plan shows is what gets registered (T-0460).
$action = New-ScheduledTaskAction -Execute $ps51 -Argument $argument -WorkingDirectory $HordeRoot
$triggers = @(New-HordeNightlyWatchTriggers -First $first -Hour $Hour -Minute $Minute -UserId $who)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal -UserId $who -LogonType Interactive -RunLevel Limited
$task = New-ScheduledTask -Action $action -Trigger $triggers -Settings $settings -Principal $principal

Write-Host ("task " + $taskPath + $taskName)
foreach ($t in @($task.Triggers)) {
    if ($t.CimClass.CimClassName -eq "MSFT_TaskLogonTrigger") { Write-Host ("trigger: at logon of " + $t.UserId + " after " + $t.Delay + " (a PC restarted and left at the lock screen skips the morning run; StartWhenAvailable does not catch that up, 2026-11-11)") }
    else { Write-Host ("trigger: daily, <StartBoundary>" + $t.StartBoundary + "</StartBoundary>  (wall-clock, no offset)") }
}
Write-Host ("action: " + $ps51 + " " + $argument)
Write-Host ("settings: StartWhenAvailable (a PC that was off runs it when it is on), no wake, multiple instances IgnoreNew, execution time limit 30 min; founder phone channel " + $(if ($NoticeService -ne "") { "ON (service " + $NoticeService + ")" } else { "OFF" }))
if ($Plan -or $WhatIfPreference) { Write-Host "dry run: nothing registered"; exit 0 }
if (-not (Test-Path -LiteralPath $script)) { throw ("not found: " + $script) }

if ($PSCmdlet.ShouldProcess($taskPath + $taskName, "register or update")) {
    [void](Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -InputObject $task -Force)
    Write-Host "registered"
}
