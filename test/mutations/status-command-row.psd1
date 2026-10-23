# Mutations of the status command's fleet.db row step (cli/commands/status.ps1). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\status-command-row.psd1
# test\test-status-set.ps1 must fail a check for every one. Every find string occurs once.
@{
    Target = "cli\commands\status.ps1"
    Suite  = "test\test-status-set.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "dry-run-touches-fleet-db"
           Find = 'if ($r.written) {'
           Replace = 'if ($r.ok) {' }
        @{ Name = "row-line-printed-when-kept"
           Find = 'if ($row.state -ceq "added") {'
           Replace = 'if ($row.state -cne "skipped") {' }
        @{ Name = "warning-line-dropped"
           Find = 'elseif ($row.state -ceq "skipped") {'
           Replace = 'elseif ($false) {' }
        @{ Name = "row-step-never-run"
           Find = '$row = Invoke-HordeStatusOrcRow -Folder $dir'
           Replace = '$row = [pscustomobject]@{ state = "kept"; reason = "" }; $null = $dir' }
    )
}
