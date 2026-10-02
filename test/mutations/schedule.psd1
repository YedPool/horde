# Mutations of core/Schedule.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\schedule.psd1
# Each breaks one rule of the job's definition; test\test-metrics-schedule.ps1 must fail for every one.
@{
    Target = "core\Schedule.ps1"
    Suite  = "test\test-metrics-schedule.ps1"
    Mutations = @(
        @{ Name = "home-not-carried"
           Find = '    if ($setHome -ne "") {'
           Replace = '    if ($false) {' }
        @{ Name = "quote-not-refused"
           Find = 'if ($p -match "[''""`r`n]") { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "run-may-outlast-interval"
           Find = ' -or $TimeLimitMinutes -gt $EveryMinutes) {'
           Replace = ') {' }
        @{ Name = "job-name-unchecked"
           Find = "    if (`$Name -notmatch '\A[A-Za-z0-9][A-Za-z0-9 ._-]{0,100}\z') {"
           Replace = '    if ($false) {' }
        @{ Name = "unavailable-scheduler-used"
           Find = '        if ($ok) { return (New-HordeKnown -Value $s) }'
           Replace = '        return (New-HordeKnown -Value $s)' }
    )
}
