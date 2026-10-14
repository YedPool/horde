# Mutations of the node command's view (cli/commands/node.ps1): horde node serve must build its view
# with ConvertTo-HordeNodeViewDocument (ledger core-projection L-100). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\node-view.psd1
# test\test-projection.ps1's ended section runs the command's own view block over a fixture projection,
# so the mutant is caught by what the block serves, not by its text.
@{
    Target = "cli\commands\node.ps1"
    Suite  = "test\test-projection.ps1"
    Environment = @{ HORDE_SKIP_REALITY = "1"; HORDE_FAIL_FAST = "1"; HORDE_SECTIONS = "ended" }
    PassCodes = @(3)
    Mutations = @(
        @{ Name = "node-serves-ended-sessions"
           Find = '$getView = { ConvertTo-HordeNodeViewDocument -Projection (Get-HordeProjection -Platform $platform) }'
           Replace = '$getView = { ConvertTo-HordeSessionViewDocument -Projection (Get-HordeProjection -Platform $platform) }' }
    )
}
