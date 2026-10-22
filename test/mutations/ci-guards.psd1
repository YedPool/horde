# Mutations of tools/CiGuards.ps1, the one step of the CI workflow (T-0247). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\ci-guards.psd1
# Each makes the runner call green what did not prove it (no banner, a failures banner, a bad exit code),
# skip a shell, a guard or the list's checks, or start a child with the wrong PSModulePath;
# test\test-ci-guards.ps1, which runs the real script against stand-in guards, must fail for every one.
@{
    Target = "tools\CiGuards.ps1"
    Suite  = "test\test-ci-guards.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "banner-not-required"
           Find = 'return ($Code -eq 0 -and $Banner -ne "" -and $Banner -cnotmatch ''FAILURE'')'
           Replace = 'return ($Code -eq 0 -and $Banner -cnotmatch ''FAILURE'')' }
        @{ Name = "failures-banner-is-green"
           Find = ' -and $Banner -cnotmatch ''FAILURE'')'
           Replace = ')' }
        @{ Name = "exit-code-ignored"
           Find = 'return ($Code -eq 0 -and $Banner -ne "" -and'
           Replace = 'return ($Banner -ne "" -and' }
        @{ Name = "only-the-first-shell"
           Find = 'foreach ($sh in @(Get-HordeGuardShells)) {'
           Replace = 'foreach ($sh in @(Get-HordeGuardShells | Select-Object -First 1)) {' }
        @{ Name = "red-run-exits-zero"
           Find = 'if ($red.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "missing-list-not-refused"
           Find = 'if (-not [System.IO.File]::Exists($listFile)) {'
           Replace = 'if ($false) {' }
        @{ Name = "bad-list-not-refused"
           Find = 'if (-not $list.ok) {'
           Replace = 'if ($false) {' }
        @{ Name = "parent-module-path-passed-on"
           Find = 'if ($psi.EnvironmentVariables.ContainsKey("PSModulePath")) { $psi.EnvironmentVariables.Remove("PSModulePath") }'
           Replace = '' }
        @{ Name = "environment-not-given"
           Find = '-Environment (Get-HordeGuardEnvironment -Shell $sh.key -MachinePsModulePath ("" + $machinePath))'
           Replace = '-Environment @{}' }
        @{ Name = "missing-guard-not-red"
           Find = 'elseif (-not [System.IO.File]::Exists((Join-Path $Root $g))) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "summary-not-written"
           Find = 'if ("" + $env:GITHUB_STEP_SUMMARY -ne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "only-ignored"
           Find = '$guards = @($want)'
           Replace = '$guards = $guards' }
        @{ Name = "only-unlisted-taken"
           Find = 'if (-not ($guards -ccontains $want)) {'
           Replace = 'if ($false) {' }
    )
}
