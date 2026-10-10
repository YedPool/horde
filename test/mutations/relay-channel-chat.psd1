# Mutations of channels/chat/Channel.ps1, the chat channel. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channel-chat.psd1
# Each lets someone other than the founder speak to the Thrall, a line reach it twice or in the wrong
# session, a messenger be picked that should not be, or the phone get the wrong turns, too many, or
# lose its place; test\test-relay-channel-chat.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "channels\chat\Channel.ps1"
    Suite  = "test\test-relay-channel-chat.ps1"
    Mutations = @(
        @{ Name = "any-trusted-sender-speaks"
           Find = '-Name "chat" -Kinds @("line") -Senders "founder"'
           Replace = '-Name "chat" -Kinds @("line") -Senders "horde"' }
        @{ Name = "machine-not-checked"
           Find = 'if ($line.machine -cne $Context.signKeyId) {'
           Replace = 'if ($false) {' }
        @{ Name = "horde-not-checked"
           Find = 'if ($line.horde -cne $Context.horde) {'
           Replace = 'if ($false) {' }
        @{ Name = "session-not-checked"
           Find = 'if ($src.value.session -cne $line.session) {'
           Replace = 'if ($false) {' }
        @{ Name = "empty-line-delivered"
           Find = 'if ($line.text.Trim() -eq "") {'
           Replace = 'if ($false) {' }
        @{ Name = "long-line-delivered"
           Find = 'if ($line.text.Length -gt [int]$set.lineChars) {'
           Replace = 'if ($false) {' }
        @{ Name = "message-id-not-derived"
           Find = 'messageId = (Get-HordeChatChannelMessageId -From $Item.from -MessageId $line.messageId); sessionId'
           Replace = 'messageId = ([guid]::NewGuid().ToString()); sessionId' }
        @{ Name = "body-without-header"
           Find = 'return ("FOUNDER LINE from the phone (line " + $MessageId + ")`n`n" + $Text)'
           Replace = 'return $Text' }
        @{ Name = "wake-not-preferred"
           Find = '$wakes = Find-HordeMessenger -Require @("body.untyped", "idempotent.post", "wake")'
           Replace = '$wakes = Find-HordeMessenger -Require @("body.untyped", "idempotent.post", "receipt.receiver")' }
        @{ Name = "messenger-that-can-neither-picked"
           Find = '$sees = Find-HordeMessenger -Require @("body.untyped", "idempotent.post", "receipt.receiver")'
           Replace = '$sees = Find-HordeMessenger -Require @("body.untyped", "idempotent.post")' }
        @{ Name = "held-receipt-every-turn"
           Find = 'if ($Status -cne "held" -or -not $mine.heldSaid.ContainsKey($heldKey)) {'
           Replace = 'if ($true) {' }
        @{ Name = "receipt-without-words"
           Find = '-Session $Session -Text $line.text'
           Replace = '-Session $Session -Text ""' }
        @{ Name = "cursor-not-advanced"
           Find = '    $d.cursor = $next'
           Replace = '    $d.cursor = $d.cursor' }
        @{ Name = "not-from-the-end"
           Find = '-Cursor $null -Settings $set -Keep ([int]$set.startTurns)'
           Replace = '-Cursor $null -Settings $set -Keep 1000' }
        @{ Name = "backfill-sealed-to-all"
           Find = '[void]$batches.Add([pscustomobject]@{ phones = $fresh; backfill = $true'
           Replace = '[void]$batches.Add([pscustomobject]@{ phones = $all; backfill = $true' }
        @{ Name = "clear-tail-not-drained"
           Find = '$old = Find-HordeChatChannelSource -Context $Context -Session "$($cursor.session)"'
           Replace = '$old = New-HordeAbsent -Note "not looked for"' }
        @{ Name = "clear-not-announced"
           Find = '[void]$batches.Add([pscustomobject]@{ phones = $all; backfill = $false; turns = @() })'
           Replace = '$null = $batches' }
        @{ Name = "rate-ignored"
           Find = 'if ([long]$set.sendIntervalMs -gt 0 -and'
           Replace = 'if ($false -and' }
        @{ Name = "long-turn-not-split"
           Find = 'if ($whole.Length -le $Room) { return @($whole) }'
           Replace = 'return @($whole)' }
        @{ Name = "quote-not-escaped"
           Find = '[^\x20\x21\x23-\x5B\x5D-\x7E]'
           Replace = '[^\x20-\x5B\x5D-\x7E]' }
        @{ Name = "pending-not-kept"
           Find = '$d.pending = @(@($d.pending) + @($keys.ToArray()))'
           Replace = '$null = $keys' }
        @{ Name = "pending-put-from-elsewhere"
           Find = 'if ($rec.value.sent) {'
           Replace = 'if ($false) {' }
        @{ Name = "damaged-state-started-over"
           Find = 'try { $s = ConvertFrom-Json -InputObject $text } catch { return (New-HordeUnknown -Reason ($why + ": it is not JSON")) }'
           Replace = 'try { $s = ConvertFrom-Json -InputObject $text } catch { return (New-HordeKnown -Value $empty) }' }
    )
}
