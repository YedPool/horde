# Mutations of the sync verb of the horde db command (cli/commands/db.ps1) and of the task that runs it
# (fleet-db/register-sync.ps1 is its own spec: fleet-db-sync-task.psd1). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-sync-command.psd1
# test\test-db-sync.ps1 must fail a check for every one. Every find string occurs once.
@{
    Target = "cli\commands\db.ps1"
    Suite  = "test\test-db-sync.ps1"
    Mutations = @(
        @{ Name = "sync-flags-accepted-on-other-verbs"
           Find = 'if ($Verb -ne "sync") {'
           Replace = 'if ($false) {' }
        @{ Name = "save-not-passed"
           Find = '$syncArgs += "--save"'
           Replace = '$null = $syncArgs' }
        @{ Name = "force-not-passed"
           Find = 'if ($Force) { $syncArgs += "--force" }'
           Replace = '' }
        @{ Name = "time-limit-not-passed"
           Find = '-TimeLimitSeconds $TimeLimitSeconds'
           Replace = '-TimeLimitSeconds 50' }
        @{ Name = "failure-not-thrown"
           Find = 'if ($r.code -ne 0) { throw (@($r.lines) -join " ") }'
           Replace = '' }
        @{ Name = "paths-without-save-accepted"
           Find = 'throw "the source paths are only taken with -Save'
           Replace = 'Write-Output "the source paths are only taken with -Save' }
        @{ Name = "registry-flag-accepted-by-sync"
           Find = 'if ($Verb -eq "sync") { $importOnly = @($importOnly | Where-Object { @("Ledger", "PrCache", "Changelog", "Cards", "ThrallCard") -cnotcontains $_ }) }'
           Replace = 'if ($Verb -eq "sync") { $importOnly = @() }' }
        @{ Name = "test-seam-ignored"
           Find = 'if ("" + $env:HORDE_DB_SYNC_TEST_SCRIPT -ne "") { $syncScript = $env:HORDE_DB_SYNC_TEST_SCRIPT }'
           Replace = '' }
    )
}
