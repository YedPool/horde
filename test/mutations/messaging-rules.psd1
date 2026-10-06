# Mutations of the messaging rules. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\messaging-rules.psd1
# Each mutation loosens one rule of remote/Messaging.ps1 (review of PR #97, F1 to F6), and
# test\test-messaging-rules.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "remote\Messaging.ps1"
    Suite  = "test\test-messaging-rules.ps1"
    Mutations = @(
        @{ Name = "receipt-for-unknown-message-accepted"
           Find = 'if ($Recorded -eq "") { return [pscustomobject]@{ refused = "no outbound'
           Replace = 'if ($false) { return [pscustomobject]@{ refused = "no outbound' }
        @{ Name = "queued-receipt-accepted"
           Find = 'if ($receiptStages -cnotcontains $Asked) {'
           Replace = 'if ($false) {' }
        @{ Name = "final-stage-overwritten"
           Find = 'if ($script:HordeMailFinalStages -ccontains $Recorded) {'
           Replace = 'if ($false) {' }
        @{ Name = "receipt-moves-backward"
           Find = '-or (Get-HordeMailStageRank -Stage $Asked) -gt $have) {'
           Replace = '-or (Get-HordeMailStageRank -Stage $Asked) -ge 0) {' }
        @{ Name = "held-blocks-the-queue"
           Find = 'return ($Stage -cne "queued")'
           Replace = 'return ($Stage -cne "queued" -and $Stage -cne "held")' }
        @{ Name = "unknown-stage-settles"
           Find = 'if ((Get-HordeMailStageRank -Stage $Stage) -lt 0) { return $false }'
           Replace = 'if ((Get-HordeMailStageRank -Stage $Stage) -lt 0) { return $true }' }
        @{ Name = "next-is-the-newest"
           Find = '$first = $keys[0]'
           Replace = '$first = $keys[$keys.Count - 1]' }
        @{ Name = "sender-device-unchecked"
           Find = 'if (-not [string]::Equals($claimed, $PeerDeviceId,'
           Replace = 'if ($false -and -not [string]::Equals($claimed, $PeerDeviceId,' }
        @{ Name = "unknown-peer-trusted"
           Find = 'if ($PeerDeviceId -eq "") { return @('
           Replace = 'if ($false) { return @(' }
        @{ Name = "live-id-retargeted-by-label"
           Find = 'if ($Label -ne "" -and -not [string]::Equals("$($target.label)", $Label,'
           Replace = 'if ($false -and -not [string]::Equals("$($target.label)", $Label,' }
        @{ Name = "hub-spawned-carried-by-label"
           Find = 'Where-Object { $null -ne $_ -and (Test-HordeDeliverSameProcess $_ $target) }'
           Replace = 'Where-Object { $null -ne $_ -and ((Test-HordeDeliverSameProcess $_ $target) -or "$($_.label)" -ceq "$($target.label)") }' }
        @{ Name = "process-by-pid-alone"
           Find = 'return ([string]::Equals($ap, $bp, [System.StringComparison]::Ordinal) -and [string]::Equals($as, $bs,'
           Replace = 'return ([string]::Equals($ap, $bp, [System.StringComparison]::Ordinal) -or [string]::Equals($as, $bs,' }
        @{ Name = "empty-start-time-proves-the-process"
           Find = 'if ($ap -eq "" -or $as -eq "" -or $bs -eq "") { return $false }'
           Replace = 'if ($ap -eq "") { return $false }' }
        @{ Name = "shared-label-picks-one"
           Find = 'if ($byLabel.Count -gt 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "dead-id-without-label-follows"
           Find = 'elseif ($Label -eq "") {'
           Replace = 'elseif ($false) {' }
    )
}
