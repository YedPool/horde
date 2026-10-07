# The registry of core/Schedule.ps1 is made once and survives a second load of the file (review of #114). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\core-load-registry-schedule.psd1
# test\test-core-load.ps1 must fail: a reset on every load empties what registered before.
@{
    Target = "core\Schedule.ps1"
    Suite  = "test\test-core-load.ps1"
    Mutations = @(
        @{ Name = "registry-reset-on-load"
           Find = 'if ($null -eq (Get-Variable -Name HordeSchedulers -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeSchedulers = New-Object System.Collections.ArrayList }'
           Replace = '$script:HordeSchedulers = New-Object System.Collections.ArrayList' }
    )
}
