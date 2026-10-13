# Mutations of the progress channel's Glance (channels/progress/Channel.ps1,
# Test-HordeProgressChannelGlance; the runner sends while its watch is open, 2026-10-13). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channel-progress-glance.psd1
# test\test-relay-run-send.ps1 must fail for every one. Every find string occurs exactly once. The
# channel's other rules are test\mutations\relay-channel-progress.psd1's, against
# test\test-relay-channel-progress.ps1.
@{
    Target = "channels\progress\Channel.ps1"
    Suite  = "test\test-relay-run-send.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "progress-glance-always-no"
           Find = '        return ([long]$info.Length -ne $mine.seenLength -or $info.LastWriteTimeUtc -ne $mine.seenWrite)'
           Replace = '        return $false' }
        @{ Name = "progress-glance-always-yes"
           Find = '        return ([long]$info.Length -ne $mine.seenLength -or $info.LastWriteTimeUtc -ne $mine.seenWrite)'
           Replace = '        return $true' }
        @{ Name = "progress-glance-while-the-channel-is-stopped"
           Find = 'if (-not $d.started -or $d.stopped -cne "" -or $d.path -ceq ""'
           Replace = 'if (-not $d.started -or $d.path -ceq ""' }
        @{ Name = "progress-glance-while-entries-wait"
           Find = '-or $d.path -ceq "" -or @($d.pending).Count -gt 0) { return $false }'
           Replace = '-or $d.path -ceq "") { return $false }' }
        @{ Name = "progress-glance-inside-the-interval"
           Find = '    if (([datetime]::UtcNow - $mine.lastSentAt).TotalMilliseconds -lt [long]$mine["sendIntervalMs"]) { return $false }'
           Replace = '' }
        @{ Name = "progress-glance-not-registered"
           Find = '    -Glance { param($Context) return (Test-HordeProgressChannelGlance -Context $Context) }'
           Replace = '    -Glance { param($Context) return $false }' }
    )
}
