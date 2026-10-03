# Mutations of the caps the link walk checks. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\link-walk-caps.psd1
# The per-field caps moved from remote/Protocol.ps1 into remote/Contract.ps1's Invoke-HordeLinkWalk
# (fix/link-writer-speed), so their mutations moved here from test\mutations\link-protocol.psd1, which
# keeps the ones on what is still in remote/Protocol.ps1. test\test-link-protocol.ps1 must fail for every
# one. Every find string occurs exactly once.
@{
    Target = "remote\Contract.ps1"
    Suite  = "test\test-link-protocol.ps1"
    Mutations = @(
        @{ Name = "string-cap-off-by-one"
           Find = 'if ($size -gt $limit) {'
           Replace = 'if ($size -gt $limit + 1) {' }
        @{ Name = "list-cap-off-by-one"
           Find = 'if ($v.Count -gt $listCap) {'
           Replace = 'if ($v.Count -gt $listCap + 1) {' }
        @{ Name = "string-without-cap-allowed"
           Find = 'if (-not $r.capEnum) {'
           Replace = 'if ($false) {' }
        @{ Name = "plain-string-measured-short"
           Find = '{ $size = $v.Length }'
           Replace = '{ $size = 0 }' }
        @{ Name = "caps-stop-where-the-schema-check-would"
           Find = '$order.Push(@(0, $childValue, $anyCase.rec, $childPath, $childLive))'
           Replace = 'if ($childLive) { $order.Push(@(0, $childValue, $anyCase.rec, $childPath, $childLive)) }' }
    )
}
