# Mutations of channels/chat/Channel.ps1, the accept side of T-0281 (a line is done only once the
# awaiting list owns it, and delivered only when the Thrall's own side takes it).
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-chat-taken-accept.psd1
# test\test-relay-chat-taken.ps1 must fail for every one. The mutations of Taken.ps1 are in relay-chat-taken.psd1.
@{
    Target = "channels\chat\Channel.ps1"
    Suite  = "test\test-relay-chat-taken.ps1"
    Mutations = @(
        # Done before taken: the accepted post is answered as delivered at once.
        @{ Name = "done-before-taken"
           Find = 'return (& $answer "done" "accepted" "queued" ("messenger " + $messenger.value.name + " took it for the Thrall" + $wake + "; awaiting'
           Replace = 'return (& $answer "done" "accepted" "delivered" ("messenger " + $messenger.value.name + " took it for the Thrall" + $wake + "; awaiting' }
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
    )
}
