# Mutations of the node's opt-in list. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\node-deliverto.psd1
# Each mutation loosens one rule of core/NodeDeliverTo.ps1 (remote.deliverTo from the node's own L1 and L4, R21 slice 4),
# and test\test-node-deliverto.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "core\NodeDeliverTo.ps1"
    Suite  = "test\test-node-deliverto.ps1"
    Mutations = @(
        @{ Name = "reader-problem-ignored"
           Find = 'if ($bad.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "per-target-list-accepted"
           Find = 'if (@($r.match.PSObject.Properties).Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "disagreeing-rules-pick-one"
           Find = 'if ($distinct.Count -gt 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "l1-beats-l4"
           Find = '$script:HordeDeliverToLayers = @("L4", "L1")'
           Replace = '$script:HordeDeliverToLayers = @("L1", "L4")' }
        @{ Name = "foreign-layer-read"
           Find = 'if ($script:HordeDeliverToLayers -cnotcontains "$($d.layer)") {'
           Replace = 'if ($false) {' }
        @{ Name = "empty-value-is-one-empty-label"
           Find = 'if ($distinct.Count -eq 0 -or $distinct[0] -eq "") {'
           Replace = 'if ($distinct.Count -eq 0) {' }
    )
}
