# core/schedule/WindowsTaskScheduler - core/Schedule.ps1's job as a Windows Task Scheduler task.
#
# HOW THE JOB BECOMES A TASK, and why:
#   - AS THE CURRENT USER, LOGON TYPE S4U: it runs whether or not the user is logged on, stores no
#     password, and runs in no visible session, so no console window flashes every 30 minutes, which
#     an Interactive task running powershell.exe -WindowStyle Hidden still does. S4U has no network
#     credentials; collect reads and writes local files only. Run level Limited: it needs no elevation.
#   - EVERY N MINUTES, from a one-time trigger N minutes after install with an indefinite repetition.
#   - PRIORITY 7 (below normal; the Task Scheduler's own scale, 0 highest, 10 lowest), stopped after
#     the time limit, never two at once (IgnoreNew), and run on battery as well: a laptop on battery is
#     still the machine whose work is being measured.
#   - ONE TASK, IN THE ROOT FOLDER, BY NAME. Status and remove act on that name only.
#
# Uses the ScheduledTasks module that ships with Windows 8 and later. No Set-StrictMode here:
# dot-sourced (see core/Tristate.ps1). Needs core/Tristate.ps1 and core/Schedule.ps1.

function Test-HordeTaskSchedulerAvailable {
    if ("$env:OS" -ne "Windows_NT") { return $false }
    return ($null -ne (Get-Command -Name Register-ScheduledTask -ErrorAction SilentlyContinue))
}

function Get-HordeTaskSchedulerTask {
    # The task of that name in the root folder, or $null.
    param([Parameter(Mandatory = $true)][string]$Name)
    return (Get-ScheduledTask -TaskPath "\" -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -ceq $Name } | Select-Object -First 1)
}

function Install-HordeTaskSchedulerJob {
    param([Parameter(Mandatory = $true)]$Job)
    $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $action = New-ScheduledTaskAction -Execute $Job.program -Argument $Job.arguments
    $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes($Job.everyMinutes)) -RepetitionInterval (New-TimeSpan -Minutes $Job.everyMinutes)
    $settingArgs = @{
        Priority = 7; ExecutionTimeLimit = (New-TimeSpan -Minutes $Job.timeLimitMinutes); MultipleInstances = "IgnoreNew"
        StartWhenAvailable = $true; AllowStartIfOnBatteries = $true; DontStopIfGoingOnBatteries = $true
    }
    if ($Job.disabled) { $settingArgs["Disable"] = $true }
    $settings = New-ScheduledTaskSettingsSet @settingArgs
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType S4U -RunLevel Limited
    # -Force replaces a task of the same name, so installing twice leaves one task, the newer.
    $null = Register-ScheduledTask -TaskName $Job.name -TaskPath "\" -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description $Job.description -Force -ErrorAction Stop
}

function Remove-HordeTaskSchedulerJob {
    param([Parameter(Mandatory = $true)][string]$Name)
    $t = Get-HordeTaskSchedulerTask -Name $Name
    if ($null -eq $t) { return $false }
    Unregister-ScheduledTask -TaskName $Name -TaskPath "\" -Confirm:$false -ErrorAction Stop
    return $true
}

function Get-HordeTaskSchedulerStatus {
    param([Parameter(Mandatory = $true)][string]$Name)
    $t = Get-HordeTaskSchedulerTask -Name $Name
    if ($null -eq $t) { return (New-HordeAbsent -Note ("no task named '" + $Name + "'")) }
    $info = $null
    try { $info = Get-ScheduledTaskInfo -TaskName $Name -TaskPath "\" -ErrorAction Stop } catch { $info = $null }
    $every = 0
    $rep = @($t.Triggers)[0].Repetition
    # The interval is an ISO 8601 duration such as PT30M or PT1H.
    if ($null -ne $rep -and "$($rep.Interval)" -ne "") { $every = [int][System.Xml.XmlConvert]::ToTimeSpan("$($rep.Interval)").TotalMinutes }
    $act = @($t.Actions)[0]
    $last = $null; $next = $null; $result = $null
    if ($null -ne $info) {
        if ($info.LastRunTime -is [datetime] -and $info.LastRunTime.Year -gt 2000) { $last = $info.LastRunTime.ToUniversalTime() }
        if ($info.NextRunTime -is [datetime] -and $info.NextRunTime.Year -gt 2000) { $next = $info.NextRunTime.ToUniversalTime() }
        $result = $info.LastTaskResult
    }
    return (New-HordeKnown -Value ([pscustomobject]@{
        installed = $true; enabled = [bool]$t.Settings.Enabled; state = "$($t.State)"; everyMinutes = $every
        priority = $t.Settings.Priority; timeLimit = "$($t.Settings.ExecutionTimeLimit)"; logonType = "$($t.Principal.LogonType)"
        lastRunAt = $last; lastResult = $result; nextRunAt = $next; program = "$($act.Execute)"; arguments = "$($act.Arguments)"
    }))
}

Register-HordeScheduler -Name "windows-task-scheduler" -Available { Test-HordeTaskSchedulerAvailable } -Install { param($j) Install-HordeTaskSchedulerJob -Job $j } -Remove { param($n) Remove-HordeTaskSchedulerJob -Name $n } -Status { param($n) Get-HordeTaskSchedulerStatus -Name $n }
