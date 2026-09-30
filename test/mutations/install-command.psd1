# Mutations of the install command's run block. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\install-command.psd1
# Each breaks one thing cli\commands\install.ps1 does; test\test-install.ps1 must fail for every one of them.
@{
    Target = "cli\commands\install.ps1"
    Suite  = "test\test-install.ps1"
    Mutations = @(
        @{ Name = "refusal-not-raised"
           Find = 'if ($plan.action -eq "refuse") { throw $plan.problem }'
           Replace = 'if ($false) { throw $plan.problem }' }
        @{ Name = "dry-run-writes"
           Find = 'elseif ($DryRun) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "no-default-guessed-anyway"
           Find = 'if ($BinDir -eq "") { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "relative-bin-from-process-directory"
           Find = '$BinDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BinDir)'
           Replace = '$BinDir = [System.IO.Path]::GetFullPath($BinDir)' }
        @{ Name = "no-path-warning"
           Find = 'if (-not (Test-HordeOnPath -Dir $BinDir)) {'
           Replace = 'if ($false) {' }
        @{ Name = "replaced-checkout-not-named"
           Find = 'if ($plan.previous -and "$($plan.previous)" -ine $plan.target) {'
           Replace = 'if ($false) {' }
    )
}
