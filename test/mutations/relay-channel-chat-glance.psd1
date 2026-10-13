# Mutations of the chat channel's Glance (channels/chat/Channel.ps1, Test-HordeChatChannelGlance; the
# runner sends while its watch is open, 2026-10-13). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channel-chat-glance.psd1
# test\test-relay-run-send.ps1 must fail for every one. Every find string occurs exactly once. The
# channel's other rules are test\mutations\relay-channel-chat.psd1's, against
# test\test-relay-channel-chat.ps1.
#
# NOT HERE, and why: the no for a session cleared since the last Tick (the suite's synthetic Thrall is
# cleared only by its fixture, and a cleared session's old conversation stops growing, so the look
# after it answers no by itself: the guard only saves the read).
@{
    Target = "channels\chat\Channel.ps1"
    Suite  = "test\test-relay-run-send.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "chat-glance-always-no"
           Find = '    return (@($r.value.turns).Count -gt 0 -or $r.value.more -or $r.value.reset -cne "none" -or "$($r.value.next.position)" -cne "$($d.cursor.position)")'
           Replace = '    return $false' }
        @{ Name = "chat-glance-always-yes"
           Find = '    return (@($r.value.turns).Count -gt 0 -or $r.value.more -or $r.value.reset -cne "none" -or "$($r.value.next.position)" -cne "$($d.cursor.position)")'
           Replace = '    return $true' }
        @{ Name = "chat-glance-while-turns-wait"
           Find = 'if ($null -eq $d.cursor -or @($d.pending).Count -gt 0) { return $false }'
           Replace = 'if ($null -eq $d.cursor) { return $false }' }
        @{ Name = "chat-glance-inside-the-interval"
           Find = '    if (([datetime]::UtcNow - $mine.lastSentAt).TotalMilliseconds -lt [long]$mine["sendIntervalMs"]) { return $false }'
           Replace = '' }
        @{ Name = "chat-thrall-not-remembered-for-the-glance"
           Find = '    $mine["source"] = $source'
           Replace = '' }
        @{ Name = "chat-interval-not-remembered-for-the-glance"
           Find = '    $mine["sendIntervalMs"] = [long]$set.sendIntervalMs'
           Replace = '    $mine["sendIntervalMs"] = [long]0' }
        @{ Name = "chat-glance-not-registered"
           Find = '    -Glance { param($Context) return (Test-HordeChatChannelGlance -Context $Context) }'
           Replace = '    -Glance { param($Context) return $false }' }
    )
}
