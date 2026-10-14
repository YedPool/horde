# Mutations of the chat channel's wiring of photos (channels/chat/Channel.ps1). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-chat-photos-channel.psd1
# test\test-relay-chat-photos.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "channels\chat\Channel.ps1"
    Suite  = "test\test-relay-chat-photos.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "chat-photos-not-offered"
           Find = '$(if ($PhotoBytes -gt 0) { '',"photoBytes":'' + $PhotoBytes } else { '''' })'
           Replace = "''" }
        @{ Name = "chat-photo-kind-not-taken"
           Find = '-Name "chat" -Kinds @("line", "photo") -Senders "founder"'
           Replace = '-Name "chat" -Kinds @("line") -Senders "founder"' }
        @{ Name = "chat-photo-manifest-taken-as-a-line"
           Find = '    if ("$($Item.kind)" -ceq "photo") { return (Invoke-HordeChatPhotoAccept -Context $Context -Item $Item) }'
           Replace = '' }
        @{ Name = "chat-photo-tick-not-run"
           Find = '    try { $photo = @(Invoke-HordeChatPhotoTick -Context $Context -Mine $m.mine -Settings $set.value) }'
           Replace = '    try { $photo = @() }' }
        @{ Name = "chat-photo-parts-not-a-data-kind"
           Find = '    -Take { param($Context, $Text) return (Receive-HordeChatPhotoPart -Context $Context -Text $Text) }'
           Replace = '    -Take { param($Context, $Text) return [pscustomobject]@{ outcome = "refused"; reason = "mutant" } }' }
    )
}
