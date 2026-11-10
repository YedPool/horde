# Mutations of wakers/Port.ps1 held by test\test-wake-shadow-nudge.ps1 (T-0116). Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-shadow-nudge-port.psd1
# The waker a shadow tick hands its pass has no nudge, and the port refuses a nudge asked of it;
# the suite, which drives the real plan and tick, must fail for each.
@{
    Target = "wakers\Port.ps1"
    Suite  = "test\test-wake-shadow-nudge.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "the-shadow-waker-keeps-the-nudge"
           Find = 'nudge = $null; begin = $Waker.begin'
           Replace = 'nudge = $Waker.nudge; begin = $Waker.begin' }
        @{ Name = "the-port-does-not-refuse-a-waker-with-no-nudge"
           Find = 'if ($null -eq $Waker.nudge) { return (New-HordeUnknown'
           Replace = 'if ($false) { return (New-HordeUnknown' }
    )
}
