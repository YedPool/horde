# Mutations of the founder's answer to an item of a published list, machine side (channels/chat/Answer.ps1; T-0352). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-chat-answers.psd1
# test\test-relay-chat-answers.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "channels\chat\Answer.ps1"
    Suite  = "test\test-relay-chat-answers.ps1"
    Mutations = @(
        @{ Name = "the-lane-the-phone-claims-is-trusted"
           Find = 'if ($ownerLane -cne $ans.lane) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-retired-orc-is-sent-to"
           Find = 'if ($owner.retired) {'
           Replace = 'if ($false) {' }
        @{ Name = "every-list-goes-to-the-thrall"
           Find = 'if ($Rank -ceq "thrall") { $found = & $seat "warchief" "" } else { $found = & $seat "orc" $Orc }'
           Replace = '$found = & $seat "warchief" ""' }
        @{ Name = "a-member-the-phone-added-is-allowed"
           Find = 'if ((@($names | Sort-Object) -join ",") -cne (@($script:HordeChatAnswerMembers | Sort-Object) -join ",")) {'
           Replace = 'if (@($script:HordeChatAnswerMembers | Where-Object { $names -cnotcontains $_ }).Count -gt 0) {' }
        @{ Name = "the-post-id-ignores-his-words"
           Find = '$MessageId + "`n" + $words + "`n" + $Snapshot'
           Replace = '$MessageId + "`n" + $Snapshot' }
        @{ Name = "the-post-id-ignores-the-item"
           Find = '$words + "`n" + $Snapshot + "`n" + $Index'
           Replace = '$words' }
        @{ Name = "the-sender-is-not-the-verified-passkey"
           Find = 'keyId = $Item.from } }'
           Replace = 'keyId = ("0" * 32) } }' }
        @{ Name = "a-posted-answer-is-not-awaited"
           Find = 'if (Add-HordeChatAnswerAwaiting -Ledger $lg.ledger -Entry $entry) {'
           Replace = 'if ($false) {' }
        @{ Name = "delivered-without-the-sessions-own-word"
           Find = 'if ($act -ceq "wait") { [void]$keep.Add($mark); continue }'
           Replace = '$act = "confirmed"' }
        @{ Name = "the-alarm-can-come-twice"
           Find = '$e.alarmed = $true'
           Replace = '$e.alarmed = $false' }
        @{ Name = "the-receipt-drops-his-words"
           Find = '(ConvertTo-HordeChatChannelJsonString $Answer.text)'
           Replace = '(ConvertTo-HordeChatChannelJsonString "")' }
        @{ Name = "no-such-item-is-held-not-refused"
           Find = 'if ($pub.state -ceq "absent") { return (& $answer "refused" "refused" "no-such-item"'
           Replace = 'if ($pub.state -ceq "absent") { return (& $answer "retry" "held" "not-now"' }
        @{ Name = "fleet-db-down-refuses-the-answer-for-good"
           Find = 'if ($pub.state -cne "known") { return (& $answer "retry" "held" "not-now"'
           Replace = 'if ($pub.state -cne "known") { return (& $answer "refused" "refused" "no-such-item"' }
        @{ Name = "held-is-told-every-time"
           Find = 'if ($Status -ceq "held") { $mine.heldSaid[$heldKey] = $true }'
           Replace = 'if ($false) { }' }
        @{ Name = "the-items-text-keeps-its-line-breaks"
           Find = '$one = [regex]::Replace($ItemText,'
           Replace = '$one = $ItemText; $unused = [regex]::Replace($ItemText,' }
        @{ Name = "no-session-is-refused-not-held"
           Find = 'if ($seat.state -ceq "absent") { return (& $answer "retry" "held" "no-session"'
           Replace = 'if ($seat.state -ceq "absent") { return (& $answer "refused" "refused" "wrong-lane"' }
        @{ Name = "another-machine-is-answered"
           Find = 'if ($ans.machine -cne $Context.signKeyId) {'
           Replace = 'if ($false) {' }
        @{ Name = "no-words-are-posted"
           Find = 'if ($ans.text.Trim() -eq "") {'
           Replace = 'if ($false) {' }
        @{ Name = "a-too-long-answer-is-posted"
           Find = 'if ($ans.text.Length -gt [int]$set.lineChars) {'
           Replace = 'if ($false) {' }
        @{ Name = "held-for-good-is-told-delivered"
           Find = 'if ($act -ceq "held") { $status_ = "held"; $code = "not-delivered" }'
           Replace = 'if ($act -ceq "held") { $status_ = "accepted"; $code = "delivered" }' }
        @{ Name = "a-restart-forgets-the-awaiting-answers"
           Find = '$Mine["answerLedger"] = $r.value'
           Replace = '$Mine["answerLedger"] = [pscustomobject]@{ awaiting = @() }' }
        @{ Name = "the-glance-never-says-an-answer-is-due"
           Find = 'if ($now - $last -ge $every) { return $true }'
           Replace = 'if ($false) { return $true }' }
        # --- review of PR 382 (S3, S8, N1) ---
        @{ Name = "no-session-is-dropped-not-kept"
           Find = '& $answer "retry" "held" "no-session"'
           Replace = '& $answer "done" "held" "no-session"' }
        @{ Name = "the-thralls-lane-is-its-letter"
           Find = '$ownerLane = $(if ($owner.rank -ceq "thrall") { "thrall" } else { $owner.orc })'
           Replace = '$ownerLane = $owner.orc' }
        @{ Name = "the-body-cap-is-not-held"
           Find = 'if ($bodyBytes -gt $script:HordeMessengerBodyBytes) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-post-already-taken-is-told-held"
           Find = 'default { return (& $answer "done" "accepted" "delivered"'
           Replace = 'default { return (& $answer "done" "held" "not-delivered"' }
        @{ Name = "an-alarmed-answer-is-told-sent-over-its-alarm"
           Find = 'if ($null -ne $already -and $already.alarmed) {'
           Replace = 'if ($false) {' }
        @{ Name = "the-header-is-another-text"
           Find = '"FOUNDER ANSWER from the phone (answer "'
           Replace = '"ANSWER (answer "' }
        @{ Name = "an-old-answer-is-carried-on"
           Find = '-gt ([long]$set.ttlSeconds * 1000)) {'
           Replace = '-gt ([long]$set.ttlSeconds * 1000000000)) {' }
        @{ Name = "an-older-list-is-not-said"
           Find = '$older = $(if ($Live) { "" } else {'
           Replace = '$older = $(if ($true) { "" } else {' }
    )
}
