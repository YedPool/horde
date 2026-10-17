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
           Find = '-Name "chat" -Kinds @("line", "photo") -Senders "founder"'
           Replace = '-Name "chat" -Kinds @("line", "photo") -Senders "horde"' }
        @{ Name = "receipt-time-is-the-machines"
           Find = 'if ($null -ne $signedAt -and [long]$signedAt.Value -gt 0) { $sentAt = [long]$signedAt.Value }'
           Replace = '$sentAt = [long]([datetime]::UtcNow - (New-Object datetime -ArgumentList 1970, 1, 1, 0, 0, 0, ([System.DateTimeKind]::Utc))).TotalMilliseconds' }
        @{ Name = "receipt-carries-no-time"
           Find = '-Session $Session -Text $line.text -SentAt $sentAt'
           Replace = '-Session $Session -Text $line.text' }
        @{ Name = "receipt-time-written-when-there-is-none"
           Find = '$(if ($SentAt -gt 0) { '',"sentAt":'' + $SentAt } else { '''' })'
           Replace = '('',"sentAt":'' + $SentAt)' }
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
           Find = 'messageId = (Get-HordeChatChannelMessageId -From $Item.from -MessageId $line.messageId -Text $line.text); sessionId'
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
           Find = '$State.pending = @(@($State.pending) + @($Keys))'
           Replace = '$null = $Keys' }
        @{ Name = "pending-put-from-elsewhere"
           Find = 'if ($rec.value.sent) {'
           Replace = 'if ($false) {' }
        @{ Name = "delivered-words-not-checked"
           Find = 'if ((Get-HordeChatChannelLineMark -MessageId $m.Groups[1].Value -Text $words) -cne $known.mark) { continue }'
           Replace = '$null = $known' }
        @{ Name = "delivered-words-added-kept"
           Find = 'if ($rest -ne "" -and -not $rest.StartsWith("`n")) { continue }'
           Replace = '$null = $rest' }
        @{ Name = "other-mail-sent-to-the-phone"
           Find = 'if ($at -lt 0) { continue }'
           Replace = 'if ($at -lt 0) { [void]$out.Add($t); continue }' }
        @{ Name = "posted-line-not-remembered"
           Find = '$mine.durable.lines = @(@($mine.durable.lines) + @($mark) | Select-Object -Last $script:HordeChatChannelLinesKept)'
           Replace = '$null = $mark' }
        @{ Name = "inbound-cap-ignored"
           Find = 'if ($mine.posted.Count -ge [int]$set.linesPerMinute) {'
           Replace = 'if ($false) {' }
        @{ Name = "messenger-id-without-the-words"
           Find = '$MessageId + "`n" + $words)))'
           Replace = '$MessageId)))' }
        @{ Name = "receipt-words-not-the-posted"
           Find = 'messageId = (Get-HordeChatChannelMessageId -From $Item.from -MessageId $line.messageId -Text $line.text)'
           Replace = 'messageId = (Get-HordeChatChannelMessageId -From $Item.from -MessageId $line.messageId -Text "")' }
        @{ Name = "clear-unknown-moves-on"
           Find = 'if ($mine["clearTries"] -lt [int]$set.clearTries) {'
           Replace = 'if ($false) {' }
        @{ Name = "pending-put-to-a-revoked-key"
           Find = 'if (@($to | Where-Object { $trusted -cnotcontains $_ }).Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "revoked-turns-not-read-again"
           Find = '$Mine.durable.cursor = $Mine.durable.rewind'
           Replace = '$null = $Mine.durable.rewind' }
        @{ Name = "body-bytes-not-counted"
           Find = 'if ($bodyBytes -gt $script:HordeMessengerBodyBytes) {'
           Replace = 'if ($false) {' }
        @{ Name = "line-chars-allows-no-message"
           Find = 'default = 16000; min = 1; max = 21000;'
           Replace = 'default = 16000; min = 1; max = 60000;' }
        @{ Name = "damaged-state-started-over"
           Find = 'try { $s = ConvertFrom-Json -InputObject $text } catch { return (New-HordeUnknown -Reason ($why + ": it is not JSON")) }'
           Replace = 'try { $s = ConvertFrom-Json -InputObject $text } catch { return (New-HordeKnown -Value $empty) }' }
        # --- the sender named as verified (the founder's first live use, 2026-10-11)
        @{ Name = "line-not-said-verified"
           Find = '; verified = [pscustomobject]@{ kind = "founder"; by = "passkey"; keyId = $Item.from } }'
           Replace = ' }' }
        @{ Name = "line-verified-by-another-key"
           Find = 'keyId = $Item.from } }'
           Replace = 'keyId = ("0" * 32) } }' }
        # --- woken, or only queued (the founder's bug of 2026-10-12)
        @{ Name = "line-does-not-say-whether-woken"
           Find = '" took it for the Thrall" + $wake)'
           Replace = '" took it for the Thrall")' }
        @{ Name = "line-wake-word-never-asked"
           Find = '$wake = Format-HordeMessengerWake -Answer $posted'
           Replace = '$wake = ""' }
    )
}
