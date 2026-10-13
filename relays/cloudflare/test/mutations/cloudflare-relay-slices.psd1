# Mutations of the hosted relay's watch in slices (relays/cloudflare/Relay.ps1, THE WATCH IN SLICES;
# the runner sends while its watch is open, 2026-10-13). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-relay-slices.psd1
# test\test-relay-conformance.ps1 must fail for every one: it holds every relay that watches in slices
# to the port's contract, this one against a local dev of the very Worker that is deployed. Every find
# string occurs once.
#
# NOT HERE, and why: the watch's own time running out (a slice that never answers "ended, empty" spins
# for ever in a mutant, which a mutation run reads as a timeout and not as caught - the suite's "runs
# out by itself" check is what holds the rule), and the look at the pending receive after the close
# (nothing a suite can see: it only keeps a fault from going unobserved).
@{
    Target = "relays\cloudflare\Relay.ps1"
    Suite  = "test\test-relay-conformance.ps1"
    Mutations = @(
        @{ Name = "slice-waits-out-the-whole-watch"
           Find = 'if ($WaitMs - $slice.ElapsedMilliseconds -le 0) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "slice-over-ends-the-watch"
           Find = 'return (New-HordeKnown -Value ([pscustomobject]@{ ended = $false; items = @() })'
           Replace = 'return (New-HordeKnown -Value ([pscustomobject]@{ ended = $true; items = @() })' }
        @{ Name = "first-slice-misses-what-is-already-there"
           Find = 'if (-not $Handle.waited) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-new-receive-every-slice"
           Find = 'if ($null -eq $Handle.pending) {'
           Replace = 'if ($true) {' }
        @{ Name = "items-come-without-ending-the-watch"
           Find = 'return (New-HordeKnown -Value ([pscustomobject]@{ ended = $true; items = @($got.value.items) })'
           Replace = 'return (New-HordeKnown -Value ([pscustomobject]@{ ended = $false; items = @() })' }
    )
}
