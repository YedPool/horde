# Mutations of relays/Port.ps1's Get-HordeRelayBundle: a relay's bundle is believed only when it is an
# answer that carries a 64-hex hash. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-port-bundle.psd1
# test\test-relay-publish.ps1 must fail for every one.
@{
    Target = "relays\Port.ps1"
    Suite  = "test\test-relay-publish.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "bundle-without-hash-believed"
           Find = 'if (-not $h.has -or $h.value -isnot [string] -or $h.value -cnotmatch ''\A[0-9a-f]{64}\z'') {'
           Replace = 'if (-not $h.has) {' }
        @{ Name = "bundle-not-an-answer-believed"
           Find = 'if (-not (Test-HordeAnswer $a)) { return (New-HordeUnknown -Reason ("relay ''" + $Name + "'' answered the bundle with something that is not an answer")) }'
           Replace = '' }
        @{ Name = "no-bundle-block-called"
           Find = 'if ($null -eq $r.bundle) { return (New-HordeUnknown -Reason ("relay ''" + $Name + "'' cannot bundle its code")) }'
           Replace = '' }
    )
}
