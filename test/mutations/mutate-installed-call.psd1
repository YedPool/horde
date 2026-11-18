# Mutations of tools\Mutate.ps1's refusal to run from the installed Horde (T-0466); test\test-mutate.ps1
# must fail for every one. The rule itself is tools\MutateInstalled.ps1 (test\mutations\mutate-installed.psd1).
@{
    Target = "tools\Mutate.ps1"
    Suite  = "test\test-mutate.ps1"
    Mutations = @(
        @{ Name = "installed-refusal-never-asked"
           Find = 'if ($installedRefusal -ne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "installed-refusal-does-not-stop"
           Find = 'Write-Host ("  " + $installedRefusal) -ForegroundColor Red; exit 2 }'
           Replace = 'Write-Host ("  " + $installedRefusal) -ForegroundColor Red }' }
        @{ Name = "installed-refusal-exits-zero"
           Find = 'Write-Host ("  " + $installedRefusal) -ForegroundColor Red; exit 2 }'
           Replace = 'Write-Host ("  " + $installedRefusal) -ForegroundColor Red; exit 0 }' }
        @{ Name = "installed-refusal-says-nothing"
           Find = 'Write-Host ("  " + $installedRefusal) -ForegroundColor Red; exit 2 }'
           Replace = 'exit 2 }' }
    )
}
