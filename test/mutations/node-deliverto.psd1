# Mutations of the node's opt-in list. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\node-deliverto.psd1
# Each mutation loosens one rule of core/NodeDeliverTo.ps1 (remote.deliverTo from L1 only, R21 slice 4),
# and test\test-node-deliverto.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "core\NodeDeliverTo.ps1"
    Suite  = "test\test-node-deliverto.ps1"
    Mutations = @(
        @{ Name = "refused-configuration-read"
           Find = 'if ($findings.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "per-target-list-accepted"
           Find = 'if (@($r.match.PSObject.Properties).Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "disagreeing-rules-pick-one"
           Find = 'if ($distinct.Count -gt 1) {'
           Replace = 'if ($false) {' }
    )
}
