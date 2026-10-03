# The one ExecScan entry remote plan R6 adds. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\clock-scan.psd1
# Without Limit-HordeAge on the core-function list, remote/Clock.ps1 is a finding, and the exec-scan
# suite, which scans every file in remote/, must fail. That scan lived in test-link-contracts until PR
# #69 moved it to test-exec-scan; batch 1's combined run caught this spec still naming the old suite.
# This spec is the entry's own mutation; the scan's full spec (exec-scan.psd1) covers the rest.
@{
    Target = "tools\ExecScan.ps1"
    Suite  = "test\test-exec-scan.ps1"
    Mutations = @(
        @{ Name = "limit-age-not-allowed"
           Find = '    "Limit-HordeAge",'
           Replace = '    "New-HordeKnown",' }
    )
}
