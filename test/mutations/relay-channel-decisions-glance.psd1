# Mutations of the decisions channel's Glance (channels/decisions/Channel.ps1,
# Test-HordeDecisionsChannelGlance; the runner sends while its watch is open, 2026-10-13). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channel-decisions-glance.psd1
# test\test-relay-run-send.ps1 must fail for every one. Every find string occurs exactly once. The
# channel's other rules are test\mutations\relay-channel-decisions.psd1's, against
# test\test-relay-channels.ps1. The chat's and the progress log's Glances are
# relay-channel-chat-glance.psd1's and relay-channel-progress-glance.psd1's: a spec has one target.
@{
    Target = "channels\decisions\Channel.ps1"
    Suite  = "test\test-relay-run-send.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "decisions-glance-always-no"
           Find = '    return ($names -cne $last.Substring(0, $bar + 1))'
           Replace = '    return $false' }
        @{ Name = "decisions-glance-always-yes"
           Find = '    return ($names -cne $last.Substring(0, $bar + 1))'
           Replace = '    return $true' }
        @{ Name = "decisions-glance-while-a-snapshot-waits"
           Find = '    if (@($mine.pending).Count -ne 0) { return $false }'
           Replace = '' }
        @{ Name = "decisions-glance-with-no-phone-to-send-to"
           Find = '    if ($bar -lt 0) { return $false }'
           Replace = '' }
        @{ Name = "decisions-glance-not-registered"
           Find = '    -Glance { param($Context) return (Test-HordeDecisionsChannelGlance -Context $Context) }'
           Replace = '    -Glance { param($Context) return $false }' }
    )
}
