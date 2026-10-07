# Mutations of core/config-keys.json's node-policy keys (remote R9, the act path's A1). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\config-keys-remote.psd1
# test\test-node-policy.ps1 must fail for every one: each lets something other than the node's owner
# raise what a hub may start, or lets a built-in layer choose a level nobody chose.
@{
    Target = "core\config-keys.json"
    Suite  = "test\test-node-policy.ps1"
    Mutations = @(
        @{ Name = "ceiling-any-direction"
           Find = '"values": ["plan", "ask", "edits", "bypass"] }, "direction": "lower-only" }'
           Replace = '"values": ["plan", "ask", "edits", "bypass"] }, "direction": "any" }' }
        @{ Name = "ceiling-in-spawn-layer"
           Find = '{ "name": "remote.permissionCeiling", "layers": ["L1", "L4"]'
           Replace = '{ "name": "remote.permissionCeiling", "layers": ["L1", "L4", "L5"]' }
        @{ Name = "level-built-in"
           Find = '{ "name": "permission", "layers": ["L1", "L3", "L4", "L5"]'
           Replace = '{ "name": "permission", "layers": ["L0", "L1", "L3", "L4", "L5"]' }
    )
}
