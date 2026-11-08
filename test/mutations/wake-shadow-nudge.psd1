# Mutations of core/Wake.ps1 held by test\test-wake-shadow-nudge.ps1 (T-0116). Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-shadow-nudge.psd1
# A shadow run is handed a waker with no nudge (wakers/Port.ps1, Get-HordeWakerReadOnly), so the would-nudge
# branch of the pass is a SECOND guard. This spec takes that branch out and the suite must still see no
# call: the mutant is declared a survivor on purpose, and the suite seeing it survive IS the proof that the
# branch is no longer the only thing between a shadow run and a keystroke. Before the waker was handed
# without a nudge, this same mutant reached the nudge and the suite caught it.
@{
    Target = "core\Wake.ps1"
    Suite  = "test\test-wake-shadow-nudge.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "the-would-nudge-branch-is-gone"
           Find = 'if ($shadowPass) { $outcomes[$d.id] = "would-nudge";'
           Replace = 'if ($false) { $outcomes[$d.id] = "would-nudge";'
           Expect = "survives"
           Reason = "Defence in depth, by design (T-0116): the shadow tick hands the pass a waker with no nudge, so with the branch gone the pass asks for a nudge and the port refuses it - no call reaches the waker, which is exactly what this suite holds. The branch is the second guard; the first is the waker." }
    )
}
