# Mutations of the node's messaging verbs. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\node-serve-messaging.psd1
# Each mutation loosens one step remote/NodeServe.ps1 takes around the messaging rules (R21 slice 4),
# and test\test-node-serve-messaging.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "remote\NodeServe.ps1"
    Suite  = "test\test-node-serve-messaging.ps1"
    Mutations = @(
        @{ Name = "gate-refusal-ignored"
           Find = 'if ($target.refused -ne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "resend-delivered-again"
           Find = 'if ($prior.state -ceq "known") {'
           Replace = 'if ($false) {' }
        @{ Name = "reused-message-id-accepted"
           Find = 'if ("$($e.argsHash)" -cne (Get-HordeJournalArgsHash'
           Replace = 'if ($false -and "$($e.argsHash)" -cne (Get-HordeJournalArgsHash' }
        @{ Name = "deliverto-not-asked-for"
           Find = 'if (-not (Test-HordeNodeDataGiven $Data "deliverTo") -and'
           Replace = 'if ($false -and' }
        @{ Name = "read-only-ignored"
           Find = 'if ((Get-HordeLinkProp $Data "readOnly") -eq $true) {'
           Replace = 'if ($false) {' }
        @{ Name = "read-only-names-a-list"
           Find = 'if ($effect -cne "read") {'
           Replace = 'if (@("session.deliver") -ccontains $verb) {' }
        @{ Name = "refused-layer-still-delivers"
           Find = 'if ($layerWhy -ne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "delivered-with-no-messenger"
           Find = 'if ("$(Get-HordeLinkProp $Data ''messenger'')" -eq "") {'
           Replace = 'if ($false) {' }
        @{ Name = "unheard-messenger-taken-as-an-answer"
           Find = 'if ("$(Get-HordeLinkProp $said ''state'')" -cne "known") {'
           Replace = 'if ($false) {' }
        @{ Name = "status-not-asked-of-the-messenger"
           Find = 'if ($null -eq $said) { return (New-HordeNodeReply -NeedStatus $id) }'
           Replace = 'if ($false) { return (New-HordeNodeReply -NeedStatus $id) }' }
        @{ Name = "outbox-not-fetched"
           Find = 'if (-not (Test-HordeNodeDataGiven $Data "outbox")) {'
           Replace = 'if ($false) {' }
        @{ Name = "handed-out-mark-not-written"
           Find = 'if (-not $pick.next.handedOut) { $write ='
           Replace = 'if ($false) { $write =' }
        @{ Name = "receipt-for-unhanded-message-accepted"
           Find = 'if ($null -ne $rec -and $rec.handedOut) { $recorded ='
           Replace = 'if ($null -ne $rec) { $recorded =' }
        @{ Name = "unchanged-receipt-written"
           Find = 'if ($r.changed) { $at = $now; $write ='
           Replace = 'if ($true) { $at = $now; $write =' }
    )
}
