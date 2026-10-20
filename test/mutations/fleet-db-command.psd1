# Mutations of the horde db command (cli/commands/db.ps1). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-command.psd1
# test\e2e\e2e-db.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "cli\commands\db.ps1"
    Suite  = "test\e2e\e2e-db.ps1"
    Mutations = @(
        @{ Name = "home-defaulted"
           Find = 'if ("$env:HORDE_HOME".Trim() -eq "") { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "node-not-checked"
           Find = 'if ($null -eq $node) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "failure-exit-0"
           Find = 'if ($LASTEXITCODE -ne 0) { throw'
           Replace = 'if ($false) { throw' }
    )
}
