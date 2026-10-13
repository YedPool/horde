# core/schedule/WindowsTaskScheduler - core/Schedule.ps1's job as a Windows Task Scheduler task.
#
# HOW THE JOB BECOMES A TASK, and why:
#   - IN HORDE'S OWN FOLDER, \Horde\ (\HordeTest\ for suites), WITH AUTHOR "Horde" AND THE MARKER in its
#     description (review of PR #70, F1: matched by name alone in the root folder, remove could delete
#     and install -Force could overwrite a task the user made). Install over, and remove of, a task
#     without the marker are refused. Removing the last task removes the folder.
#   - THE PROGRAM IS powershell.exe AND THE COMMAND IS -EncodedCommand. The script, its arguments and its
#     environment are each written as base64 of their UTF-8 text inside a fixed command, and the command
#     is passed as base64 too, so no value is ever parsed as code: no quote of any kind, &, %, $ or `
#     in a path can end a string or start a command (review of PR #70, F2). Base64 holds no %, which
#     Task Scheduler might otherwise expand.
#   - AS THE CURRENT USER, LOGON TYPE S4U: it runs whether or not the user is logged on, stores no
#     password, and runs in no visible session, so no console window flashes every 30 minutes, which
#     an Interactive task running powershell.exe -WindowStyle Hidden still does. S4U has no network
#     credentials; collect reads and writes local files only. Run level Limited: no elevation.
#   - A JOB MADE -WithPerson (core/Schedule.ps1) IS THE EXCEPTION TO BOTH: logon type Interactive, so
#     it runs in the person's session and only while they are logged on, and its program is the
#     console host started headless, which runs PowerShell with no console window at all. Measured
#     2026-10-13 on Windows 11 26200: `conhost.exe --headless powershell.exe ...` ran the command in
#     session 1 as an interactive process and made no window. TWO THINGS FOLLOW, also measured then:
#     the console host exits 0 whatever PowerShell exited with (a command that exited 7 read as 0), so
#     such a task's last result says nothing about the job - the job must say for itself that it ran;
#     and the flag is not in Microsoft's documentation, so a Windows that drops it would fail the task
#     outright, which the job's own silence shows.
#   - EVERY N MINUTES, from a one-time trigger N minutes after install with an indefinite repetition.
#   - PRIORITY 7 (below normal; 0 highest, 10 lowest), stopped after the time limit, never two at once
#     (IgnoreNew), and run on battery as well.
#
# Uses the ScheduledTasks module that ships with Windows 8 and later. No Set-StrictMode here:
# dot-sourced (see core/Tristate.ps1). Needs core/Tristate.ps1 and core/Schedule.ps1.

$script:HordeTaskAuthor = "Horde"

function Test-HordeTaskSchedulerAvailable {
    if ("$env:OS" -ne "Windows_NT") { return $false }
    return ($null -ne (Get-Command -Name Register-ScheduledTask -ErrorAction SilentlyContinue))
}

function ConvertTo-HordeBase64Text { param([string]$Text) return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text)) }

function ConvertTo-HordeTaskAction {
    # The job as { program; arguments } for this platform. The fixed command decodes every value; only
    # base64 text is placed in it.
    param([Parameter(Mandatory = $true)]$Job)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('$ErrorActionPreference = ''Stop''; $d = { param($b) [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b)) }; ')
    foreach ($k in @($Job.environment.Keys | Sort-Object)) {
        [void]$sb.Append('[System.Environment]::SetEnvironmentVariable(''' + $k + ''', (& $d ''' + (ConvertTo-HordeBase64Text "$($Job.environment[$k])") + '''), ''Process''); ')
    }
    [void]$sb.Append('$a = @(')
    [void]$sb.Append((@($Job.arguments | ForEach-Object { '(& $d ''' + (ConvertTo-HordeBase64Text "$_") + ''')' }) -join ', '))
    [void]$sb.Append('); & (& $d ''' + (ConvertTo-HordeBase64Text $Job.script) + ''') @a; exit $LASTEXITCODE')
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($sb.ToString()))
    $shellArguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand " + $encoded
    # In the person's session a hidden PowerShell window still flashes; the headless console host has none (header).
    if ($null -ne $Job.PSObject.Properties["withPerson"] -and $Job.withPerson -eq $true) { return [pscustomobject]@{ program = "conhost.exe"; arguments = ("--headless powershell.exe " + $shellArguments) } }
    return [pscustomobject]@{ program = "powershell.exe"; arguments = $shellArguments }
}

function Get-HordeTaskSchedulerTask {
    # The task of that name in that folder, or $null.
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][string]$Folder)
    return (Get-ScheduledTask -TaskPath ("\" + $Folder + "\") -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -ceq $Name } | Select-Object -First 1)
}

function Test-HordeTaskMarked {
    # Horde's own task: author Horde and the marker line in its description.
    param($Task)
    return ($Task.Author -ceq $script:HordeTaskAuthor -and (Read-HordeJobMarker -Description $Task.Description).marked)
}

function Remove-HordeTaskFolderIfEmpty {
    # A folder Horde made is removed with its last task, so a suite leaves nothing behind.
    param([string]$Folder)
    $svc = New-Object -ComObject Schedule.Service
    $svc.Connect()
    $f = $null
    try { $f = $svc.GetFolder("\" + $Folder) } catch { return }
    if ($f.GetTasks(1).Count -eq 0 -and $f.GetFolders(0).Count -eq 0) { $svc.GetFolder("\").DeleteFolder($Folder, 0) }
}

function Install-HordeTaskSchedulerJob {
    param([Parameter(Mandatory = $true)]$Job)
    Assert-HordeJobName -Name $Job.name -Folder $Job.folder
    $old = Get-HordeTaskSchedulerTask -Name $Job.name -Folder $Job.folder
    if ($null -ne $old) {
        if (-not (Test-HordeTaskMarked $old)) { throw ("a task named '" + $Job.name + "' in \" + $Job.folder + "\ was not made by Horde; it was left alone") }
        $oldHome = (Read-HordeJobMarker -Description $old.Description).home
        if ($oldHome -cne $Job.hordeHome) { throw ("the task '" + $Job.name + "' serves the Horde home " + $oldHome + "; remove it first to serve " + $Job.hordeHome) }
    }
    $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $act = ConvertTo-HordeTaskAction -Job $Job
    $action = New-ScheduledTaskAction -Execute $act.program -Argument $act.arguments
    $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes($Job.everyMinutes)) -RepetitionInterval (New-TimeSpan -Minutes $Job.everyMinutes)
    $settingArgs = @{
        Priority = 7; ExecutionTimeLimit = (New-TimeSpan -Minutes $Job.timeLimitMinutes); MultipleInstances = "IgnoreNew"
        StartWhenAvailable = $true; AllowStartIfOnBatteries = $true; DontStopIfGoingOnBatteries = $true
    }
    if ($Job.disabled) { $settingArgs["Disable"] = $true }
    $settings = New-ScheduledTaskSettingsSet @settingArgs
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType S4U -RunLevel Limited
    if ($null -ne $Job.PSObject.Properties["withPerson"] -and $Job.withPerson -eq $true) { $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited }
    $task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description $Job.description
    $task.Author = $script:HordeTaskAuthor
    # -Force replaces a task of the same name - only ever Horde's own, checked above.
    $null = Register-ScheduledTask -InputObject $task -TaskName $Job.name -TaskPath ("\" + $Job.folder + "\") -Force -ErrorAction Stop
}

function Remove-HordeTaskSchedulerJob {
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][string]$Folder)
    Assert-HordeJobName -Name $Name -Folder $Folder
    $t = Get-HordeTaskSchedulerTask -Name $Name -Folder $Folder
    if ($null -eq $t) { return $false }
    if (-not (Test-HordeTaskMarked $t)) { throw ("the task '" + $Name + "' in \" + $Folder + "\ was not made by Horde; it was left alone") }
    Unregister-ScheduledTask -TaskName $Name -TaskPath ("\" + $Folder + "\") -Confirm:$false -ErrorAction Stop
    Remove-HordeTaskFolderIfEmpty -Folder $Folder
    return $true
}

function Get-HordeTaskSchedulerStatus {
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][string]$Folder)
    Assert-HordeJobName -Name $Name -Folder $Folder
    $t = Get-HordeTaskSchedulerTask -Name $Name -Folder $Folder
    if ($null -eq $t) { return (New-HordeAbsent -Note ("no task named '" + $Name + "' in \" + $Folder + "\")) }
    $info = $null
    try { $info = Get-ScheduledTaskInfo -TaskName $Name -TaskPath ("\" + $Folder + "\") -ErrorAction Stop } catch { $info = $null }
    $every = 0
    $rep = @($t.Triggers)[0].Repetition
    # The interval is an ISO 8601 duration such as PT30M or PT1H.
    if ($null -ne $rep -and "$($rep.Interval)" -ne "") { $every = [int][System.Xml.XmlConvert]::ToTimeSpan("$($rep.Interval)").TotalMinutes }
    $last = $null; $next = $null; $result = $null
    if ($null -ne $info) {
        if ($info.LastRunTime -is [datetime] -and $info.LastRunTime.Year -gt 2000) { $last = $info.LastRunTime.ToUniversalTime() }
        if ($info.NextRunTime -is [datetime] -and $info.NextRunTime.Year -gt 2000) { $next = $info.NextRunTime.ToUniversalTime() }
        $result = $info.LastTaskResult
    }
    $mark = Read-HordeJobMarker -Description $t.Description
    return (New-HordeKnown -Value ([pscustomobject]@{
        enabled = [bool]$t.Settings.Enabled; state = "$($t.State)"; everyMinutes = $every; marked = (Test-HordeTaskMarked $t); home = $mark.home
        priority = $t.Settings.Priority; timeLimit = "$($t.Settings.ExecutionTimeLimit)"; logonType = "$($t.Principal.LogonType)"; author = "$($t.Author)"
        lastRunAt = $last; lastResult = $result; nextRunAt = $next; runs = ("" + @($t.Actions)[0].Execute + " -EncodedCommand ...")
        program = "$(@($t.Actions)[0].Execute)"; arguments = "$(@($t.Actions)[0].Arguments)"
    }))
}

Register-HordeScheduler -Name "windows-task-scheduler" -Available { Test-HordeTaskSchedulerAvailable } -Install { param($j) Install-HordeTaskSchedulerJob -Job $j } -Remove { param($n, $f) Remove-HordeTaskSchedulerJob -Name $n -Folder $f } -Status { param($n, $f) Get-HordeTaskSchedulerStatus -Name $n -Folder $f }
