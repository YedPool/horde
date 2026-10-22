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
#     That trigger is the task's FIRST, so status reads the interval from it.
#   - A JOB MADE -AtStartup (core/Schedule.ps1) HAS A SECOND TRIGGER, AT BOOT. RIGHTS, measured
#     2026-10-14 on Windows 11 26200 by registering disabled probe tasks in \HordeTest\ as an
#     administrator: an S4U task with only the time trigger registered from both an elevated and a
#     non-elevated token (runas /trustlevel:0x20000); with a boot trigger added it registered elevated
#     and was REFUSED non-elevated, "Access is denied" (Task Scheduler lets only an administrator make
#     a boot trigger). So a refused registration of such a job is said as what it is - run it again
#     from an elevated prompt - and the job is never registered in another form instead: not without
#     the boot trigger, and never as an Interactive task. A failed registration leaves the task that
#     was there, if any, exactly as it was. S4U also needs the right to log on as a batch job when it
#     RUNS, which administrators hold by default.
#     MEASURED AGAIN 2026-10-21 on Windows 11 26200 (the founder's PC), in a NON-ELEVATED shell
#     (not in the Administrators role): a bare Register-ScheduledTask of a disabled S4U task with
#     only a time trigger, no Horde code, was REFUSED "Access is denied" (an Interactive one was
#     accepted), while the S4U job already registered here (\Horde\Horde metrics collect) keeps
#     running every 30 minutes with last result 0. So registering a NEW S4U job can need an elevated
#     shell even without a boot trigger - likely the "Log on as a batch job" right, which a filtered
#     token may lack; this contradicts the runas /trustlevel result above for this shell. A refusal
#     of a not-elevated shell is therefore told to run again elevated, boot trigger or not, and
#     test\test-metrics-schedule.ps1 probes this with a bare task before it relies on installing.
#   - A JOB MADE -AtLogon HAS A TRIGGER AT THE SIGN-IN OF THE ACCOUNT IT RUNS AS. Measured 2026-10-14
#     the same way: an Interactive task with one registered elevated and non-elevated alike.
#   - THE JOB RUNS AS THE ACCOUNT THAT REGISTERS IT. An elevated prompt opened with another
#     administrator's name would make the job that account's, with that account's profile and keys, so
#     a refusal and status both name the account (review of PR 249, SHOULD 4).
#   - THE SHELL BY ITS FULL PATH in the system folder, for every job, never a bare name a search path
#     could answer with another program: the supervisor's job starts and updates code every minute.
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
    $shell = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe")
    # In the person's session a hidden PowerShell window still flashes; the headless console host has none (header).
    if ($null -ne $Job.PSObject.Properties["withPerson"] -and $Job.withPerson -eq $true) {
        # Measured 2026-10-13 on Windows 11 26200: the console host started with the shell's quoted
        # full path ran the command in 6 of 6 runs when it had no console to inherit, which is how a
        # scheduled job starts it. (Started from a terminal, WITH a console to inherit, the same
        # line - and the bare-name line of the first version - failed to run in 5 of 8 tries; that is
        # not this job's case, and it is why the probe that measured it gave the host none.)
        # BOTH PROGRAMS BY THEIR FULL PATHS in the system folder, never by a bare name a search path
        # could answer with another program: this job starts and updates code every minute. A system
        # that has not got them is refused here, when the job is made, not every minute it fires.
        $console = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "conhost.exe")
        foreach ($needed in @($console, $shell)) { if (-not [System.IO.File]::Exists($needed)) { throw ("a job that runs in the person's session needs " + $needed + ", which is not there") } }
        return [pscustomobject]@{ program = $console; arguments = ('--headless "' + $shell + '" ' + $shellArguments) }
    }
    # A job that runs where nobody sees it (S4U) is in session 0, with no desktop to flash a window
    # on, so it needs no console host - and without one the task's last result is the job's own exit
    # code again (header: the console host answers 0 whatever the job did).
    if (-not [System.IO.File]::Exists($shell)) { throw ("a job needs " + $shell + ", which is not there") }
    return [pscustomobject]@{ program = $shell; arguments = $shellArguments }
}

function Get-HordeTaskSchedulerTask {
    # The task of that name in that folder, or $null when the scheduler says there is none. A listing
    # that FAILS is not "none" (review of PR 249, N1): read as none, an install would not check the
    # task it replaces, and a status would say nothing is supervised. Measured 2026-10-14: a folder or
    # a name that is not there fails with an error id that begins CmdletizationQuery_NotFound.
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][string]$Folder)
    $found = $null
    try { $found = @(Get-ScheduledTask -TaskPath ("\" + $Folder + "\") -ErrorAction Stop) }
    catch {
        if ("" + $_.FullyQualifiedErrorId -like "CmdletizationQuery_NotFound*") { return $null }
        throw ("the scheduler's folder \" + $Folder + "\ could not be read: " + $_.Exception.Message)
    }
    return ($found | Where-Object { $_.TaskName -ceq $Name } | Select-Object -First 1)
}

function Test-HordeTaskSchedulerElevated {
    # Is this process an administrator's, elevated? Only such a one may register a boot trigger (header).
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    try { return (New-Object System.Security.Principal.WindowsPrincipal $id).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator) } finally { $id.Dispose() }
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

function New-HordeTaskSchedulerTask {
    # The task for -Job, as the scheduler's own object, made and NOT registered: the action, the
    # triggers (the repetition first; then the boot trigger of a job made -AtStartup), the settings
    # and the principal - S4U, with no password, or Interactive for a -WithPerson job. -UserId is the
    # account it runs as. Nothing here touches the scheduler, so a suite can read every property.
    param([Parameter(Mandatory = $true)]$Job, [Parameter(Mandatory = $true)][string]$UserId)
    $act = ConvertTo-HordeTaskAction -Job $Job
    $action = New-ScheduledTaskAction -Execute $act.program -Argument $act.arguments
    $triggers = @(New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes($Job.everyMinutes)) -RepetitionInterval (New-TimeSpan -Minutes $Job.everyMinutes))
    if ($null -ne $Job.PSObject.Properties["atStartup"] -and $Job.atStartup -eq $true) { $triggers += New-ScheduledTaskTrigger -AtStartup }
    if ($null -ne $Job.PSObject.Properties["atLogon"] -and $Job.atLogon -eq $true) { $triggers += New-ScheduledTaskTrigger -AtLogOn -User $UserId }
    $settingArgs = @{
        Priority = 7; ExecutionTimeLimit = (New-TimeSpan -Minutes $Job.timeLimitMinutes); MultipleInstances = "IgnoreNew"
        StartWhenAvailable = $true; AllowStartIfOnBatteries = $true; DontStopIfGoingOnBatteries = $true
    }
    if ($Job.disabled) { $settingArgs["Disable"] = $true }
    $settings = New-ScheduledTaskSettingsSet @settingArgs
    $principal = New-ScheduledTaskPrincipal -UserId $UserId -LogonType S4U -RunLevel Limited
    if ($null -ne $Job.PSObject.Properties["withPerson"] -and $Job.withPerson -eq $true) { $principal = New-ScheduledTaskPrincipal -UserId $UserId -LogonType Interactive -RunLevel Limited }
    $task = New-ScheduledTask -Action $action -Trigger $triggers -Settings $settings -Principal $principal -Description $Job.description
    $task.Author = $script:HordeTaskAuthor
    return $task
}

function ConvertTo-HordeTaskHomeKey {
    # A home made comparable: full path, no trailing separator, lower case (Windows paths ignore case).
    param([string]$Path)
    $p = "$Path".Trim()
    try { $p = [System.IO.Path]::GetFullPath($p) } catch { }
    return $p.TrimEnd('\', '/').ToLowerInvariant()
}

function Install-HordeTaskSchedulerJob {
    # -Find and -Register are the scheduler, handed in so a suite can install against a stand-in:
    # -Find { param($Name, $Folder) } answers the task there, or $null (Get-HordeTaskSchedulerTask);
    # -Register { param($Task, $Name, $Path) } registers the task under that name, REPLACING one of
    # the same name. It is called at most once. -Elevated { } answers whether this process is elevated.
    param([Parameter(Mandatory = $true)]$Job, [scriptblock]$Find = $null, [scriptblock]$Register = $null, [scriptblock]$Elevated = $null)
    if ($null -eq $Elevated) { $Elevated = { Test-HordeTaskSchedulerElevated } }
    if ($null -eq $Find) { $Find = { param($Name, $Folder) Get-HordeTaskSchedulerTask -Name $Name -Folder $Folder } }
    # -Force replaces a task of the same name - only ever Horde's own, checked below - so an install
    # over the job that is there is one job, never two, whatever its logon type was.
    if ($null -eq $Register) { $Register = { param($Task, $Name, $Path) $null = Register-ScheduledTask -InputObject $Task -TaskName $Name -TaskPath $Path -Force -ErrorAction Stop } }
    Assert-HordeJobName -Name $Job.name -Folder $Job.folder
    $old = & $Find $Job.name $Job.folder
    if ($null -ne $old) {
        if (-not (Test-HordeTaskMarked $old)) { throw ("a task named '" + $Job.name + "' in \" + $Job.folder + "\ was not made by Horde; it was left alone") }
        # A NARROW "SERVES ANOTHER HOME" REFUSAL (T-0299). A task bakes no home any more, so its marker is a label of where it
        # was registered, and the one elevated re-register after horde home set must be able to replace it: the old marker names
        # the OLD home, which holds no fleet.db (fleet.db lives in the new home), so that move passes. What the refusal still
        # stops is a developer's or test's scratch install: horde metrics schedule install with HORDE_HOME set to a scratch
        # home would replace the REAL \Horde\ task, whose action still names this checkout's script, and relabel it to the
        # scratch home. So it refuses when the existing task's marker names a home that (a) holds a fleet.db (so it still
        # exists) and (b) differs from the home this install resolves, and says so by both homes. -TakeOver (Job.takeOver)
        # replaces it on purpose. A marker home that is gone, or holds no fleet.db, or is the same home, is replaced.
        $oldHome = (Read-HordeJobMarker -Description $old.Description).home
        $takeOver = ($null -ne $Job.PSObject.Properties["takeOver"] -and $Job.takeOver -eq $true)
        $differs = ($oldHome -ne "" -and (ConvertTo-HordeTaskHomeKey $oldHome) -cne (ConvertTo-HordeTaskHomeKey $Job.hordeHome))
        $oldHolds = ($differs -and (Test-Path -LiteralPath (Join-Path $oldHome "fleet.db") -PathType Leaf))
        if ($oldHolds -and -not $takeOver) { throw ("the task '" + $Job.name + "' in \" + $Job.folder + "\ is registered under the Horde home " + $oldHome + ", which still holds a fleet.db, and this install resolves the home " + $Job.hordeHome + "; it was left alone. Pass -TakeOver to replace it on purpose (a scratch install over the real task would relabel it)") }
    }
    $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $task = New-HordeTaskSchedulerTask -Job $Job -UserId $user
    # ONE TRY, AND NO OTHER FORM (header, RIGHTS): a refusal is said, and never answered by
    # registering the job some other way.
    try { & $Register $task $Job.name ("\" + $Job.folder + "\") }
    catch {
        $why = ("" + $_.Exception.Message).Trim()
        $was = $(if ($null -ne $old) { "the task that was there is left exactly as it was" } else { "nothing was registered" })
        # The hint only where it is the answer (review of PR 249, SHOULD 2): an elevated process that
        # was refused was refused for some other reason, which the scheduler's own words say.
        $up = $true
        try { $up = (& $Elevated) -eq $true } catch { $up = $true }
        $rights = $(if ($null -ne $Job.PSObject.Properties["atStartup"] -and $Job.atStartup -eq $true -and -not $up) { " A job that runs at start-up, whether or not anyone is signed in, can be registered only by an administrator: run this again from an elevated prompt, signed in as " + $user + ", the account the job runs as." } elseif (-not $up -and $why -like "*Access is denied*") { " This shell may not be allowed to register a job that runs whether or not anyone is signed in: run this again from an elevated prompt, signed in as " + $user + ", the account the job runs as." } else { "" })
        throw ("Task Scheduler refused to register '" + $Job.name + "' in \" + $Job.folder + "\ to run as " + $user + " (" + $why + "); " + $was + "." + $rights)
    }
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
    $boot = @(@($t.Triggers) | Where-Object { $null -ne $_ -and "$($_.CimClass.CimClassName)" -ceq "MSFT_TaskBootTrigger" }).Count -gt 0
    $logon = @(@($t.Triggers) | Where-Object { $null -ne $_ -and "$($_.CimClass.CimClassName)" -ceq "MSFT_TaskLogonTrigger" }).Count -gt 0
    # The interval of the trigger that repeats, wherever it stands among them (review of PR 249, N2).
    $rep = @(@($t.Triggers) | Where-Object { $null -ne $_ -and $null -ne $_.Repetition -and "$($_.Repetition.Interval)" -ne "" } | ForEach-Object { $_.Repetition }) | Select-Object -First 1
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
        priority = $t.Settings.Priority; timeLimit = "$($t.Settings.ExecutionTimeLimit)"; logonType = "$($t.Principal.LogonType)"; atStartup = $boot; atLogon = $logon; runsAs = "$($t.Principal.UserId)"; author = "$($t.Author)"
        lastRunAt = $last; lastResult = $result; nextRunAt = $next; runs = ("" + @($t.Actions)[0].Execute + " -EncodedCommand ...")
        program = "$(@($t.Actions)[0].Execute)"; arguments = "$(@($t.Actions)[0].Arguments)"
    }))
}

Register-HordeScheduler -Name "windows-task-scheduler" -Available { Test-HordeTaskSchedulerAvailable } -Install { param($j) Install-HordeTaskSchedulerJob -Job $j } -Remove { param($n, $f) Remove-HordeTaskSchedulerJob -Name $n -Folder $f } -Status { param($n, $f) Get-HordeTaskSchedulerStatus -Name $n -Folder $f }
