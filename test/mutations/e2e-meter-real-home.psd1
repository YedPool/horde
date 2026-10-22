# Mutations of the real-home guard in test\e2e\e2e-meter.ps1 (the suite is its own target). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\e2e-meter-real-home.psd1
# No mutant here makes the suite write the REAL home: a leak is simulated by naming the test's own home as
# the "real" one, which gains the synthetic rows during the run and must turn the guard red.
@{
    Target = "test\e2e\e2e-meter.ps1"
    Suite  = "test\e2e\e2e-meter.ps1"
    Mutations = @(
        @{ Name = "real-home-is-the-test-home"
           Find = 'try { $realHome = Get-HordeHome }'
           Replace = 'try { $realHome = $hordeHome }' }
        @{ Name = "row-count-always-no-database"
           Find = '    if ($Db -eq "" -or -not (Test-Path -LiteralPath $Db -PathType Leaf)) { return -1 }'
           Replace = '    return -1' }
        @{ Name = "fixture-ids-not-read"
           Find = '"export const SID_\w+ = '''
           Replace = '"export const NO_SUCH_\w+ = ''' }
    )
}
