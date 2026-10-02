# Mutations of core/schedule/WindowsTaskScheduler.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\schedule-windows.psd1
# Each breaks one property of the task; test\test-metrics-schedule.ps1 must fail for every one. The
# suite's job is disabled and test-named, and is removed whatever happens (see the suite's header).
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
           Find = '-Description $Job.description -Force -ErrorAction Stop'
           Replace = '-Description $Job.description -ErrorAction Stop' }
        @{ Name = "remove-is-a-no-op"
           Find = '    Unregister-ScheduledTask -TaskName $Name -TaskPath "\" -Confirm:$false -ErrorAction Stop'
           Replace = '' }
    )
}
