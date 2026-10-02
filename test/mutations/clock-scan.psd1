# The one ExecScan entry remote plan R6 adds. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\clock-scan.psd1
# Without Limit-HordeAge on the core-function list, remote/Clock.ps1 is a finding, and the contracts
# suite, which scans every file in remote/, must fail. This spec is the entry's own mutation; the
# scan's full spec (exec-scan.psd1) runs every mutant against the slow contracts suite and is left to
# the batch run.
@{
    Target = "tools\ExecScan.ps1"
    Suite  = "test\test-link-contracts.ps1"
    Mutations = @(
        @{ Name = "limit-age-not-allowed"
           Find = '    "Limit-HordeAge")'
           Replace = '    "New-HordeKnown")' }
    )
}
