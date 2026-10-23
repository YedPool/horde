# Mutations of channels/chat/Channel.ps1, the accept side of T-0281 (a line is done only once the
# awaiting list owns it, and delivered only when the Thrall's own side takes it).
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-chat-taken-accept.psd1
# test\test-relay-chat-taken.ps1 must fail for every one. The mutations of Taken.ps1 are in relay-chat-taken.psd1.
@{
    Target = "channels\chat\Channel.ps1"
    Suite  = "test\test-relay-chat-taken.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # Done before taken: the accepted post is answered as delivered at once.
        @{ Name = "done-before-taken"
           Find = '$queued = & $answer "done" "accepted" "queued" ("messenger " + $messenger.value.name + " took it for the Thrall" + $wake + "; awaiting'
           Replace = '$queued = & $answer "done" "accepted" "delivered" ("messenger " + $messenger.value.name + " took it for the Thrall" + $wake + "; awaiting' }
        # The line is not put on the awaiting list at all.
        @{ Name = "accepted-line-not-awaited"
           Find = 'if (Add-HordeChatTaken -State $mine.durable -Entry $entry) {'
           Replace = 'if ($false) {' }
        # The list is written before the record is done; a failed write holds the record.
        @{ Name = "awaiting-write-failure-still-done"
           Find = 'return (& $answer "retry" "held" "not-now" ("the chat state could not be written, so the line is not yet awaited: " + $_.Exception.Message) $line.session)'
           Replace = '' }
        @{ Name = "awaiting-write-failure-not-rolled-back"
           Find = '                    $mine.durable.awaiting = $awaitedBefore'
           Replace = '' }
        # The state keeps no word of the line.
        @{ Name = "words-stored-in-awaiting-list"
           Find = 'messengerId = $message.messageId; postedMs'
           Replace = 'messengerId = ($message.messageId + ":" + $line.text); postedMs' }
        # The tick runs the taken check.
        @{ Name = "tick-skips-taken-check"
           Find = 'try { $taken = Invoke-HordeChatTakenTick -Context $Context -Mine $m.mine -Settings $set.value }'
           Replace = 'try { }' }
        @{ Name = "glance-ignores-due-line"
           Find = 'if ($mine.loaded -and (Test-HordeChatTakenDue -Mine $mine)) { return $true }'
           Replace = '' }
        # S1: a line already awaited and alarmed is not answered "Sent" over its alarm.
        @{ Name = "queued-receipt-over-the-alarm"
           Find = 'if ($null -ne $already -and $already.alarmed) {'
           Replace = 'if ($false) {' }
        # S2: a line pushed off a full list is given up with a receipt and an ALARM line, never in silence.
        @{ Name = "overflow-line-dropped-silently"
           Find = '$told = @(foreach ($old in $overflow) { Send-HordeChatTakenGiveUp -Context $Context -Mine $mine -Entry $old -Why "the awaiting list is full" })'
           Replace = '$told = @()' }
        # S-d: the evicted line is told BEFORE the state write that drops it, never after.
        @{ Name = "giveup-disabled-when-the-list-is-full"
           Find = '            if ($null -eq $already) {'
           Replace = '            if ($false) {' }
        # S4 (round 2): an entry whose phone could not be told is not evicted; the record is retried.
        @{ Name = "giveup-unsent-entry-evicted-anyway"
           Find = '                if (@($told | Where-Object { -not $_.sent }).Count -gt 0) {'
           Replace = '                if ($false) {' }
        # M1 (round 2): the awaiting mark carries the line's session, for the wordless receipt.
        @{ Name = "mark-written-without-the-session"
           Find = 'woken = ($null -ne $wp -and $wp.Value -eq $true); session = "$($line.session)" }'
           Replace = 'woken = ($null -ne $wp -and $wp.Value -eq $true); session = "" }' }
        @{ Name = "giveup-sent-after-the-state-write"
           Find = '$told = @(foreach ($old in $overflow) { Send-HordeChatTakenGiveUp -Context $Context -Mine $mine -Entry $old -Why "the awaiting list is full" })'
           Replace = '[void](Add-HordeChatTaken -State $mine.durable -Entry $entry); try { Write-HordeChatChannelState -HordeHome (Get-HordeChatChannelHome $Context) -State $mine.durable } catch { }; $told = @(foreach ($old in $overflow) { Send-HordeChatTakenGiveUp -Context $Context -Mine $mine -Entry $old -Why "the awaiting list is full" })' }
    )
}
