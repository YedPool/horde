# Mutations of the node command's view (cli/commands/node.ps1): horde node serve must serve its
# projection through Remove-HordeEndedSessions (ledger core-projection L-100). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\node-view.psd1
# test\test-projection.ps1's ended section reads the command's view line and must fail.
@{
    Target = "cli\commands\node.ps1"
    Suite  = "test\test-projection.ps1"
    Environment = @{ HORDE_SKIP_REALITY = "1"; HORDE_FAIL_FAST = "1"; HORDE_SECTIONS = "ended" }
    PassCodes = @(3)
    Mutations = @(
        @{ Name = "node-serves-ended-sessions"
           Find = 'ConvertTo-HordeSessionViewDocument -Projection (Remove-HordeEndedSessions -Projection (Get-HordeProjection -Platform $platform))'
           Replace = 'ConvertTo-HordeSessionViewDocument -Projection (Get-HordeProjection -Platform $platform)' }
    )
}
