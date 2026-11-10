# Mutations of core/WakeRun.ps1 held by test\test-wake-shadow-nudge.ps1 (T-0116). Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-shadow-nudge-run.psd1
# The tick hands a shadow pass a waker with no nudge, and a proof or live pass the waker it was given;
# test\test-wake-shadow-nudge.ps1 watches the pass for the waker it is handed and must fail for each.
@{
    Target = "core\WakeRun.ps1"
    Suite  = "test\test-wake-shadow-nudge.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-shadow-tick-hands-the-real-waker"
           Find = 'if ($shadow) { $Waker = Get-HordeWakerReadOnly -Waker $Waker }'
           Replace = 'if ($false) { $Waker = Get-HordeWakerReadOnly -Waker $Waker }' }
        @{ Name = "every-tick-hands-a-waker-with-no-nudge"
           Find = 'if ($shadow) { $Waker = Get-HordeWakerReadOnly -Waker $Waker }'
           Replace = 'if ($true) { $Waker = Get-HordeWakerReadOnly -Waker $Waker }' }
    )
}
