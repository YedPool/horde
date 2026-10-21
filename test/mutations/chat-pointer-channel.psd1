# Mutations of the marker turn in the chat channel (channels/chat/Channel.ps1, Select-HordeChatChannelShown, T-0309). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\chat-pointer-channel.psd1
# Each shows a wezfleet line's words to the phone, hides a line that is not wezfleet's, or loses the marker's time;
# test\test-chat-pointer.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "channels\chat\Channel.ps1"
    Suite  = "test\test-chat-pointer.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "marker-keeps-the-words"
           Find = '$mk = [ordered]@{ role = "marker"; text = ""; turnId'
           Replace = '$mk = [ordered]@{ role = "marker"; text = [string]$t.text; turnId' }
        @{ Name = "marker-loses-its-time"
           Find = 'if ($null -ne $t.PSObject.Properties["time"]) { $mk["time"] = $t.time }'
           Replace = '' }
        @{ Name = "any-role-becomes-a-marker"
           Find = 'if (($t.role -ceq "user" -or $t.role -ceq "delivered") -and (Test-HordeChatPointerLine'
           Replace = 'if (($true) -and (Test-HordeChatPointerLine' }
        @{ Name = "delivered-relay-not-a-marker"
           Find = 'if (($t.role -ceq "user" -or $t.role -ceq "delivered") -and (Test-HordeChatPointerLine'
           Replace = 'if (($t.role -ceq "user") -and (Test-HordeChatPointerLine' }
        @{ Name = "user-pointer-not-a-marker"
           Find = 'if (($t.role -ceq "user" -or $t.role -ceq "delivered") -and (Test-HordeChatPointerLine'
           Replace = 'if (($t.role -ceq "delivered") -and (Test-HordeChatPointerLine' }
        @{ Name = "marker-source-dropped"
           Find = 'text = ""; turnId = $t.turnId; source = $t.source }'
           Replace = 'text = ""; turnId = $t.turnId; source = $null }' }
    )
}
