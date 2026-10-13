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
           Find = '-TaskPath ("\" + $Job.folder + "\") -Force -ErrorAction Stop'
           Replace = '-TaskPath ("\" + $Job.folder + "\") -ErrorAction Stop' }
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
           Find = '{ $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited }'
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
    )
}
