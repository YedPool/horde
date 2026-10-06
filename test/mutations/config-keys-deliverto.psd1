# Mutations of remote.deliverTo's registry entry. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\config-keys-deliverto.psd1
# The key is settable only in L1, the node's own configuration (R21 slice 4); test\test-node-deliverto.ps1
# must fail when any other layer may set it. Every find string occurs exactly once.
@{
    Target = "core\config-keys.json"
    Suite  = "test\test-node-deliverto.ps1"
    Mutations = @(
        @{ Name = "deliverto-settable-in-a-run-spec"
           Find = '{ "name": "remote.deliverTo", "layers": ["L1"],'
           Replace = '{ "name": "remote.deliverTo", "layers": ["L1", "L3", "L4"],' }
    )
}
