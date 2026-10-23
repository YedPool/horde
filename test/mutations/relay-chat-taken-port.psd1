# Mutations of channels/Port.ps1's Open-HordeRelayChannelRecord, the -Reread branch of T-0340 (S-b): -Reread
# skips the sender and nothing else; the normal path judges the sender and the session as before.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-chat-taken-port.psd1
# test\test-relay-chat-taken.ps1 must fail for every one.
@{
    Target = "channels\Port.ps1"
    Suite  = "test\test-relay-chat-taken.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "default-path-acts-as-reread"
           Find = '    if ($Reread) {'
           Replace = '    if ($true) {' }
        @{ Name = "reread-judges-the-sender-again"
           Find = '    if ($Reread) {'
           Replace = '    if ($false) {' }
        @{ Name = "reread-ignores-the-channel"
           Find = '-Replay $Record.verdict -Channel $Channel.name -Kind $Record.kind -Reread'
           Replace = '-Replay $Record.verdict -Channel "chat" -Kind $Record.kind -Reread' }
        @{ Name = "reread-ignores-the-kind"
           Find = '-Replay $Record.verdict -Channel $Channel.name -Kind $Record.kind -Reread'
           Replace = '-Replay $Record.verdict -Channel $Channel.name -Kind "line" -Reread' }
        @{ Name = "reread-ignores-the-verdict"
           Find = '-Replay $Record.verdict -Channel $Channel.name -Kind $Record.kind -Reread'
           Replace = '-Replay (New-HordeKnown -Value ([pscustomobject]@{ key = (Get-HordeRelayReplayKey -Header $r.value.header); fresh = $true })) -Channel $Channel.name -Kind $Record.kind -Reread' }
    )
}