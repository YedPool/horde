# Mutations of tools\Mutate.ps1's Shells runs (T-0422); test\test-mutate.ps1 must fail for every one.
# Its runs under both shells need the MSI's pwsh.exe; without it the suite passes with 3 (NOT RUN), and
# these mutants would survive for that reason - so this spec accepts only 0.
@{
    Target = "tools\Mutate.ps1"
    Suite  = "test\test-mutate.ps1"
    Mutations = @(
        @{ Name = "caught-only-by-the-first-shell"
           Find = 'if ($caughtBy.Count -gt 0) { $row.outcome = "caught"'
           Replace = 'if ($per[0].outcome -eq "caught") { $row.outcome = "caught"' }
        @{ Name = "baseline-under-5-1-alone"
           Find = '$base = Invoke-HordeSuite -Path $suite -Seconds $TimeoutSeconds -Exe $sh.exe'
           Replace = '$base = Invoke-HordeSuite -Path $suite -Seconds $TimeoutSeconds -Exe "powershell.exe"' }
        @{ Name = "per-shell-lines-dropped"
           Find = 'if ($manyShells) { $row.shells = $per }'
           Replace = 'if ($false) { $row.shells = $per }' }
        @{ Name = "missing-pwsh-run-anyway"
           Find = 'if (-not $x.ok) { Write-Host ("  the spec runs its suite under "'
           Replace = 'if ($false) { Write-Host ("  the spec runs its suite under "' }
    )
}
