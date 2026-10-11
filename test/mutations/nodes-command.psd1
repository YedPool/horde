# Mutations of `horde nodes` (cli\commands\nodes.ps1). Run, on a machine with an interactive logon for
# the local pipe:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\nodes-command.psd1
# transports\local\test\test-hub-serve-local.ps1 must fail for each: it enrols a device, binds its
# dialled link, and asks `horde nodes -Json` for both the hub's own node and that one.
@{
    Target = "cli\commands\nodes.ps1"
    Suite  = "transports\local\test\test-hub-serve-local.ps1"
    Mutations = @(
        # The first live mesh link (2026-10-11): a dialled node is bound by the hub's register, and
        # `horde nodes` read only the hub's own node.
        @{ Name = "nodes-own-only"
           Find = '@(Get-HordeHubListedNodes -Own @(Get-HordeHubRegistry -Node $node) -HordeHome (Get-HordeHome))'
           Replace = '@(Get-HordeHubRegistry -Node $node)' }
    )
}
