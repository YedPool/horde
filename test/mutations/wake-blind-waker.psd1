# Mutations of the blind-look word in wakers/wezfleet/Waker.ps1 (T-0116). Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-blind-waker.psd1
# test\test-waker-wezfleet.ps1 must fail for every one.
@{
    Target = "wakers\wezfleet\Waker.ps1"
    Suite  = "test\test-waker-wezfleet.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-pane-look-never-says-it-was-blind"
           Find = '$state.value.blindReason = (Get-HordeWezfleetWakerBlind -Row $pane.row)'
           Replace = '$state.value.blindReason = ""' }
        @{ Name = "a-look-that-read-can-be-blind"
           Find = 'if ($Row.boxEmpty -cne "unknown" -and $Row.midTurn -cne "unknown") { return "" }'
           Replace = 'if ($false) { return "" }' }
        @{ Name = "a-timeout-is-not-blind"
           Find = '@("pane-unverified", "terminal-timeout", "box-unreadable")'
           Replace = '@("pane-unverified", "box-unreadable")' }
        @{ Name = "a-session-fact-is-blind"
           Find = '@("pane-unverified", "terminal-timeout", "box-unreadable")'
           Replace = '@("pane-unverified", "terminal-timeout", "box-unreadable", "duplicate-process")' }
        @{ Name = "the-cheap-reading-is-blind"
           Find = 'oldestHandedOverAt = $later.oldestHandedOverAt; blindReason = "" } }'
           Replace = 'oldestHandedOverAt = $later.oldestHandedOverAt; blindReason = "terminal-timeout" } }' }
    )
}
