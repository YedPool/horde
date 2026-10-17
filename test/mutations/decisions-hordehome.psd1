# Mutations of cli/commands/decisions.ps1's -HordeHome (alias -Home): it points one call at another home's
# list and puts HORDE_HOME back after it, whichever way the call ends. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-hordehome.psd1
# The suite is the router's (it runs the command's own body in-process, which a child process cannot show);
# the end-to-end spec of this file is decisions-command.psd1.
@{
    Target = "cli\commands\decisions.ps1"
    Suite  = "test\test-decisions-route.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "hordehome-never-restored"
           Find = 'finally { if ($PSBoundParameters.ContainsKey("HordeHome")) { $env:HORDE_HOME = $keptHordeHome } }'
           Replace = 'finally { }' }
        @{ Name = "hordehome-not-applied"
           Find = '$env:HORDE_HOME = "$HordeHome".Trim()'
           Replace = '' }
    )
}
