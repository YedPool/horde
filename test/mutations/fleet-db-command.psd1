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
        @{ Name = "import-flag-accepted-on-other-verbs"
           Find = 'if ($Verb -ne "import") {'
           Replace = 'if ($false) {' }
        @{ Name = "import-dry-run-not-passed"
           Find = 'if ($DryRun) { $nodeArgs += "--dry-run" }'
           Replace = 'if ($false) { $nodeArgs += "--dry-run" }' }
        @{ Name = "import-registry-not-passed"
           Find = '"--registry" = $Registry;'
           Replace = '"--registry" = $null;' }
        @{ Name = "import-decisions-not-passed"
           Find = '"--decisions" = $Decisions;'
           Replace = '"--decisions" = $null;' }
        @{ Name = "decisions-flag-accepted-on-other-verbs"
           Find = '"Registry", "Decisions", "Lots", "DryRun")'
           Replace = '"Registry", "Lots", "DryRun")' }
        @{ Name = "import-lots-not-passed"
           Find = '"--lots" = $Lots }'
           Replace = '"--lots" = $null }' }
        @{ Name = "lots-flag-accepted-on-other-verbs"
           Find = '"Registry", "Decisions", "Lots", "DryRun")'
           Replace = '"Registry", "Decisions", "DryRun")' }
        @{ Name = "import-thrall-card-not-passed"
           Find = '"--thrall-card" = $ThrallCard;'
           Replace = '"--thrall-card" = $null;' }
        @{ Name = "failure-exit-0"
           Find = 'if ($LASTEXITCODE -ne 0) { throw'
           Replace = 'if ($false) { throw' }
    )
}
