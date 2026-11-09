# Mutations of the blindReason member in wakers/Port.ps1 (T-0116). Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-blind-port.psd1
# test\test-wake-port.ps1 must fail for every one.
@{
    Target = "wakers\Port.ps1"
    Suite  = "test\test-wake-port.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "the-port-drops-the-blind-reason"
           Find = 'oldestHandedOverAt = $handedAt; blindReason = $blindReason }'
           Replace = 'oldestHandedOverAt = $handedAt; blindReason = "" }' }
        @{ Name = "the-port-carries-nothing-but-empty"
           Find = '$blindReason = [string]$bl.value'
           Replace = '$blindReason = ""' }
        @{ Name = "the-port-accepts-any-text-as-a-reason"
           Find = '-cnotmatch ''\A[a-z][a-z0-9]*(-[a-z0-9]+)*\z'')'
           Replace = '-cnotmatch ''\A.*\z'')' }
        @{ Name = "the-port-accepts-a-long-reason"
           Find = ' -or $bl.value.Length -gt 60) {'
           Replace = ') {' }
    )
}
