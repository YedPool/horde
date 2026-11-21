# Mutations of core/WakeRun.ps1 held by the shadow-ledger and strict-live sections of test\test-wake-run.ps1 (T-0116). Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-shadow-ledger-run.psd1
# A shadow run writes its own ledger file and never the live one, and only a real boolean true makes a run send.
@{
    Target = "core\WakeRun.ps1"
    Suite  = "test\test-wake-run.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-shadow-run-writes-the-live-ledger"
           Find = '-Mode (Get-HordeWakeSendWord -Mode $mode) -HordeHome $HordeHome } # the pass ledger, in its own mode'
           Replace = '-Mode "live" -HordeHome $HordeHome } # the pass ledger, in its own mode' }
        @{ Name = "a-run-is-live-for-anything-truthy"
           Find = '$liveWord.Value -isnot [bool] -or '
           Replace = '' }
        @{ Name = "a-run-with-no-live-member-is-an-error"
           Find = '$null -eq $liveWord -or '
           Replace = '' }
    )
}
