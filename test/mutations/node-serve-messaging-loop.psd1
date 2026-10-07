# Mutations of the serve loop's messaging step. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\node-serve-messaging-loop.psd1
# Each mutation loosens one thing cli/NodeServe.ps1's Invoke-HordeNodeServeStep does for messaging (R21
# slice 4), and test\test-node-serve-messaging.ps1 must fail for every one. Every find string occurs
# exactly once.
@{
    Target = "cli\NodeServe.ps1"
    Suite  = "test\test-node-serve-messaging.ps1"
    Mutations = @(
        @{ Name = "layers-cached-across-delivers"
           Find = 'try { $got = Read-HordeNodeDeliverTo -Root $layerSource.root -HordeHome $layerSource.hordeHome -Descriptors $layerSource.descriptors -Builtin $layerSource.builtin }'
           Replace = 'try { if ($null -eq $script:HordeMutantDeliverToCache) { $script:HordeMutantDeliverToCache = Read-HordeNodeDeliverTo -Root $layerSource.root -HordeHome $layerSource.hordeHome -Descriptors $layerSource.descriptors -Builtin $layerSource.builtin }; $got = $script:HordeMutantDeliverToCache }' }
        @{ Name = "layer-error-dropped"
           Find = '$data.deliverToError = "$($got.error)"'
           Replace = '$data.deliverToError = ""' }
        @{ Name = "handed-out-mark-not-written-before-the-reply"
           Find = '$w = Add-HordeOutboxMarker -Root $outboxRoot -MessageId "$($r.write.messageId)" -Marker "$($r.write.marker)" -At "$($r.write.at)"'
           Replace = '$w = [pscustomobject]@{ state = "known" }' }
        @{ Name = "loop-drops-read-only"
           Find = 'actOutcome = $null; readOnly = [bool]$ReadOnly'
           Replace = 'actOutcome = $null; readOnly = $false' }
        @{ Name = "layer-problems-ignored"
           Find = '$a = Get-HordeNodeDeliverTo -Layers @($eng.layers) -Problems @($eng.problems)'
           Replace = '$a = Get-HordeNodeDeliverTo -Layers @($eng.layers) -Problems @()' }
        @{ Name = "message-sent-to-the-named-session"
           Find = '$m = [ordered]@{ messageId = "$($a.messageId)"; sessionId = "$($Need.target.sessionId)" }'
           Replace = '$m = [ordered]@{ messageId = "$($a.messageId)"; sessionId = "$($a.sessionId)" }' }
        @{ Name = "unresolved-messenger-reason-dropped"
           Find = 'if ($got.state -ceq "known") { $Messenger = $got.value } else { $why = "$($got.reason)" }'
           Replace = '$Messenger = $got.value' }
    )
}
