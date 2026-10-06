# Mutations of decisions/Store.ps1 that only racing processes can see. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-store-race.psd1
# test\test-decisions-store-race.ps1 must fail for each.
#
# Each run of the suite starts 16 powershell.exe processes (4 racers, four races); measured 2026-10-06
# on a throttled machine, one run took 49 s.
@{
    Target = "decisions\Store.ps1"
    Suite  = "test\test-decisions-store-race.ps1"
    Mutations = @(
        @{ Name = "create-overwrites"
           Find = '[System.IO.FileMode]::CreateNew'
           Replace = '[System.IO.FileMode]::OpenOrCreate' }
        @{ Name = "check-then-create"
           Find = '    $recPath = Join-Path $Root (Get-HordeDecisionRecordName -Sequence $Sequence)'
           Replace = '    $recPath = Join-Path $Root (Get-HordeDecisionRecordName -Sequence $Sequence); if ([System.IO.File]::Exists($recPath)) { return "exists" } else { [System.IO.File]::WriteAllBytes($recPath, $script:HordeDecisionStoreUtf8.GetBytes($Text)); return "created" }' }
    )
}
