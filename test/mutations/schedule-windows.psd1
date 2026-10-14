# Mutations of core/schedule/WindowsTaskScheduler.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\schedule-windows.psd1
# Each breaks one property of the task; test\test-metrics-schedule.ps1 must fail for every one. The
# suite's jobs are disabled, test-named and in the HordeTest folder, and are removed whatever happens.
@{
    Target = "core\schedule\WindowsTaskScheduler.ps1"
    Suite  = "test\test-metrics-schedule.ps1"
    Mutations = @(
        @{ Name = "normal-priority"
           Find = 'Priority = 7;'
           Replace = 'Priority = 5;' }
        @{ Name = "no-time-limit-from-the-job"
           Find = 'ExecutionTimeLimit = (New-TimeSpan -Minutes $Job.timeLimitMinutes)'
           Replace = 'ExecutionTimeLimit = (New-TimeSpan -Minutes 60)' }
        @{ Name = "interactive-logon"
           Find = '-LogonType S4U -RunLevel Limited'
           Replace = '-LogonType Interactive -RunLevel Limited' }
        @{ Name = "second-install-fails"
           Find = '-TaskName $Name -TaskPath $Path -Force -ErrorAction Stop'
           Replace = '-TaskName $Name -TaskPath $Path -ErrorAction Stop' }
        @{ Name = "foreign-task-overwritten"
           Find = '        if (-not (Test-HordeTaskMarked $old)) { throw'
           Replace = '        if ($false) { throw' }
        @{ Name = "foreign-task-removed"
           Find = '    if (-not (Test-HordeTaskMarked $t)) { throw ("the task '''
           Replace = '    if ($false) { throw ("the task ''' }
        @{ Name = "other-home-taken-over"
           Find = 'if ($oldHome -cne $Job.hordeHome) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "author-not-set"
           Find = '    $task.Author = $script:HordeTaskAuthor'
           Replace = '' }
        @{ Name = "remove-is-a-no-op"
           Find = '    Unregister-ScheduledTask -TaskName $Name -TaskPath ("\" + $Folder + "\") -Confirm:$false -ErrorAction Stop'
           Replace = '' }
        @{ Name = "folder-left-behind"
           Find = '    Remove-HordeTaskFolderIfEmpty -Folder $Folder'
           Replace = '' }
        @{ Name = "home-quoted-into-the-command"
           Find = '[void]$sb.Append(''[System.Environment]::SetEnvironmentVariable('''''' + $k + '''''', (& $d '''''' + (ConvertTo-HordeBase64Text "$($Job.environment[$k])") + ''''''), ''''Process''''); '')'
           Replace = '[void]$sb.Append(''$env:'' + $k + '' = '''''' + "$($Job.environment[$k])" + ''''''; '')' }
        @{ Name = "with-person-job-runs-unseen"
           Find = '{ $principal = New-ScheduledTaskPrincipal -UserId $UserId -LogonType Interactive -RunLevel Limited }'
           Replace = '{ }' }
        @{ Name = "with-person-job-flashes-a-window"
           Find = '        return [pscustomobject]@{ program = $console; arguments = (''--headless "'' + $shell + ''" '' + $shellArguments) }'
           Replace = '' }
        @{ Name = "every-job-with-the-person"
           Find = 'if ($null -ne $Job.PSObject.Properties["withPerson"] -and $Job.withPerson -eq $true) { $principal ='
           Replace = 'if ($true) { $principal =' }
        @{ Name = "with-person-job-by-bare-names"
           Find = '        return [pscustomobject]@{ program = $console; arguments = (''--headless "'' + $shell + ''" '' + $shellArguments) }'
           Replace = '        return [pscustomobject]@{ program = "conhost.exe"; arguments = ("--headless powershell.exe " + $shellArguments) }' }
        # --- the supervisor runs whether or not anyone is signed in (2026-10-14) ---
        @{ Name = "no-boot-trigger"
           Find = '{ $triggers += New-ScheduledTaskTrigger -AtStartup }'
           Replace = '{ }' }
        @{ Name = "refused-registration-falls-back-to-interactive"
           Find = '        throw ("Task Scheduler refused to register ''" + $Job.name'
           Replace = '        & $Register (New-ScheduledTask -Action $task.Actions -Trigger $task.Triggers -Settings $task.Settings -Principal (New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited)) $Job.name ("\" + $Job.folder + "\"); return; throw ("Task Scheduler refused to register ''" + $Job.name' }
        @{ Name = "refused-registration-silent"
           Find = '        throw ("Task Scheduler refused to register ''" + $Job.name'
           Replace = '        return; throw ("Task Scheduler refused to register ''" + $Job.name' }
        @{ Name = "no-elevation-hint"
           Find = '$rights = $(if ($null -ne $Job.PSObject.Properties["atStartup"] -and $Job.atStartup -eq $true -and -not $up) {'
           Replace = '$rights = $(if ($false) {' }
        @{ Name = "old-task-said-gone"
           Find = '$was = $(if ($null -ne $old) { "the task that was there is left exactly as it was" } else {'
           Replace = '$was = $(if ($false) { "the task that was there is left exactly as it was" } else {' }
        @{ Name = "unseen-job-shell-by-bare-name"
           Find = '    return [pscustomobject]@{ program = $shell; arguments = $shellArguments }'
           Replace = '    return [pscustomobject]@{ program = "powershell.exe"; arguments = $shellArguments }' }
        @{ Name = "status-always-at-start-up"
           Find = 'logonType = "$($t.Principal.LogonType)"; atStartup = $boot;'
           Replace = 'logonType = "$($t.Principal.LogonType)"; atStartup = $true;' }
            # --- review of PR 249 ---
        @{ Name = "no-logon-trigger"
           Find = '{ $triggers += New-ScheduledTaskTrigger -AtLogOn -User $UserId }'
           Replace = '{ }' }
        @{ Name = "elevation-hint-for-everyone"
           Find = '-and $Job.atStartup -eq $true -and -not $up) {'
           Replace = '-and $Job.atStartup -eq $true) {' }
        @{ Name = "refusal-names-no-account"
           Find = '\ to run as " + $user + " (" + $why'
           Replace = '\ (" + $why' }
        @{ Name = "listing-failure-read-as-none"
           Find = '        throw ("the scheduler''s folder \" + $Folder'
           Replace = '        return $null; throw ("the scheduler''s folder \" + $Folder' }
        @{ Name = "interval-from-the-first-trigger"
           Find = '$rep = @(@($t.Triggers) | Where-Object { $null -ne $_ -and $null -ne $_.Repetition -and "$($_.Repetition.Interval)" -ne "" } | ForEach-Object { $_.Repetition }) | Select-Object -First 1'
           Replace = '$rep = @($t.Triggers)[0].Repetition' }
        @{ Name = "status-names-no-account"
           Find = 'atLogon = $logon; runsAs = "$($t.Principal.UserId)";'
           Replace = 'atLogon = $logon; runsAs = "";' }
    )
}
