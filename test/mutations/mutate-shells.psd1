# Mutations of tools\MutateShells.ps1, the Shells rule (T-0422); test\test-mutate.ps1 must fail for
# every one. Not here: a mutant that admits a shell named twice - test\test-mutation-specs.ps1 is the
# suite that checks that, by text, and a spec has one suite.
# Its runs under both shells need the MSI's pwsh.exe; without it test	est-mutate.ps1 passes with 3 (NOT
# RUN), and these mutants could survive for that reason - so this spec accepts only 0.
@{
    Target = "tools\MutateShells.ps1"
    Suite  = "test\test-mutate.ps1"
    Mutations = @(
        @{ Name = "any-shell-name-admitted"
           Find = 'if ($script:HordeMutateShellNames -cnotcontains $n) {'
           Replace = 'if ($false) {' }
        @{ Name = "empty-shells-admitted"
           Find = 'if ($list.Count -eq 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "missing-pwsh-falls-back-to-5-1"
           Find = 'return [pscustomobject]@{ ok = $false; exe = ""; problem = ("PowerShell 7 is not at "'
           Replace = 'return [pscustomobject]@{ ok = $true; exe = "powershell.exe"; problem = ("PowerShell 7 is not at "' }
        @{ Name = "pwsh-from-the-search-path"
           Find = '$p = Get-HordeSetupMsiPwshPath'
           Replace = '$p = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source' }
    )
}
