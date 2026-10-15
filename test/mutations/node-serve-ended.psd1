# Mutations of what remote/NodeServe.ps1's session.get says of a session the node left out because its
# end is proven (ledger core-projection L-100). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\node-serve-ended.psd1
# test\test-projection.ps1's ended section asks the node's frame handler, over the view the node builds,
# and must fail for each.
@{
    Target = "remote\NodeServe.ps1"
    Suite  = "test\test-projection.ps1"
    Environment = @{ HORDE_SKIP_REALITY = "1"; HORDE_FAIL_FAST = "1"; HORDE_SECTIONS = "ended" }
    PassCodes = @(3)
    Mutations = @(
        @{ Name = "ended-session-said-to-be-in-no-store"
           Find = 'foreach ($e in @(Get-HordeLinkProp $Data.view "endedSessions")) {'
           Replace = 'foreach ($e in @()) {' }
        @{ Name = "ended-session-agent-not-matched"
           Find = 'if ($wantAgent -ne "" -and "$(Get-HordeLinkProp $e ''agent'')" -cne $wantAgent) { continue }'
           Replace = '' }
    )
}
