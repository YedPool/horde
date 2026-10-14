# Mutations of the inbound gate's DATA KINDS (channels/Port.ps1; shape B, 2026-10-14). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-chat-photos-gate.psd1
# test\test-relay-chat-photos.ps1 (its section 10, THE GATE) must fail for every one. Every find string
# occurs exactly once.
@{
    Target = "channels\Port.ps1"
    Suite  = "test\test-relay-chat-photos.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "gate-data-kind-taken-as-an-envelope"
           Find = '    if ($script:HordeRelayDataKinds.Contains("$($h.kind)")) { return'
           Replace = '    if ($false) { return' }
        @{ Name = "gate-data-kind-record-handed-to-accept"
           Find = '    if ($script:HordeRelayDataKinds.Contains("$($Record.kind)")) { return'
           Replace = '    if ($false) { return' }
        @{ Name = "gate-channel-may-take-a-data-kind"
           Find = '    foreach ($k in $Kinds) { if ($script:HordeRelayDataKinds.Contains($k)) { throw'
           Replace = '    foreach ($k in $Kinds) { if ($false) { throw' }
        @{ Name = "gate-envelope-kind-may-be-data"
           Find = 'foreach ($c in @($script:HordeRelayChannels.Values)) { if (@($c.kinds) -ccontains $Name) { throw'
           Replace = 'foreach ($c in @($script:HordeRelayChannels.Values)) { if ($false) { throw' }
        @{ Name = "gate-data-items-not-routed"
           Find = '            $dk = Get-HordeRelayDataKindOf -Text $it.text'
           Replace = '            $dk = $null' }
        @{ Name = "gate-data-refusals-a-line-each"
           Find = '                    [void]$dataRefused[$said].Add([long]$it.seq)'
           Replace = '                    $dataRefused[$said + $it.seq] = New-Object System.Collections.ArrayList; [void]$dataRefused[$said + $it.seq].Add([long]$it.seq)' }
        @{ Name = "gate-taker-that-throws-is-not-caught"
           Find = '                try { $got = @(& $dk.take $Context $it.text) | Select-Object -Last 1 } catch {'
           Replace = '                $got = @(& $dk.take $Context $it.text) | Select-Object -Last 1; if ($false) {' }
    )
}
