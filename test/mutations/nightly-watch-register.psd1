# Mutations of tools/nightly/Register-NightlyWatchTask.ps1 (T-0460). Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\nightly-watch-register.psd1
# Each breaks what the dry run shows; test\test-nightly-watch.ps1 must fail a named check for every one of them. The
# suite never registers a task, so the Register-ScheduledTask call itself is not mutated here: it is proven on the box by
# registering and reading the task back.
@{
    Target = "tools\nightly\Register-NightlyWatchTask.ps1"
    Suite  = "test\test-nightly-watch.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "task-built-with-the-daily-trigger-only"
           Find = '-Trigger $triggers -Settings'
           Replace = '-Trigger $triggers[0] -Settings' }
        @{ Name = "logon-trigger-not-shown"
           Find = 'if ($t.CimClass.CimClassName -eq "MSFT_TaskLogonTrigger") { Write-Host'
           Replace = 'if ($false) { Write-Host' }
    )
}
