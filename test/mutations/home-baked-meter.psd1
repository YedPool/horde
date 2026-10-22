# A baked home brought back into fleet-metrics/register-schedule.ps1 (the meter's two tasks), and its check that
# -HordeHome is the home this shell resolves (T-0299, round 1). See home-baked.psd1. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\home-baked-meter.psd1
@{
    Target = "fleet-metrics\register-schedule.ps1"
    Suite  = "test\test-home-tasks.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "meter-task-bakes-the-home"
           Find = 'return ("& ''" + $scriptQ'
           Replace = 'return ("$" + "env:HORDE_HOME = ''" + $effective + "''; & ''" + $scriptQ' }
        @{ Name = "meter-accepts-another-home"
           Find = 'if ([System.IO.Path]::GetFullPath($HordeHome) -ine $effective) {'
           Replace = 'if ($false) {' }
    )
}
