# Mutations of core/WakeMail.ps1, T-0391 slice 9: a wake sender's mail is awaited BEFORE it is posted, is delivered only on the target
# session's own TAKEN (an accepted post is posted, not delivered), a refusal (and only a refusal) takes its mark off, and what leaves the
# list is told as delivered only when it was taken.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-mail-taken.psd1 [-Only <name>,...]
# test\test-wake-taken.ps1 must fail for every one. The list's engine is in decisions-route-taken.psd1 (NoticeTaken.ps1).
@{
    Target = "core\WakeMail.ps1"
    Suite  = "test\test-wake-taken.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # An accepted post is read as the session having taken it.
        @{ Name = "wake-mail-accepted-read-as-taken"
           Find = 'return (New-HordeWakeMailAwaiting -MessageId "$($Mail.messageId)" -Stage "$($posted.value.stage)" -Messenger "$($through.name)")'
           Replace = 'return (New-HordeKnown -Value ([pscustomobject]@{ messageId = "$($Mail.messageId)"; stage = "$($posted.value.stage)"; messenger = "$($through.name)" }) -ObservedAt ([datetime]::UtcNow))' }
        # The mark is written after the post instead of before it.
        @{ Name = "wake-mail-mark-after-post"
           Find = '    $awaited = Add-HordeDecisionNoticeTaken -Kind $Kind -HordeHome $HordeHome -NoticeId $message.messageId -Answer 0 -SessionId $message.sessionId -Now $Now
    if (-not $awaited.ok) { return (New-HordeUnknown -Reason ("the mail cannot be awaited (" + $awaited.reason + "); nothing is posted until it can be")) }
    $posted = Send-HordeMessengerMessage -Messenger $through -Message $message'
           Replace = '    $posted = Send-HordeMessengerMessage -Messenger $through -Message $message
    $awaited = Add-HordeDecisionNoticeTaken -Kind $Kind -HordeHome $HordeHome -NoticeId $message.messageId -Answer 0 -SessionId $message.sessionId -Now $Now
    if (-not $awaited.ok) { return (New-HordeUnknown -Reason ("the mail cannot be awaited (" + $awaited.reason + "); nothing is posted until it can be")) }' }
        # A list that cannot be written no longer holds the post back.
        @{ Name = "wake-mail-unlisted-mail-still-posted"
           Find = 'if (-not $awaited.ok) { return (New-HordeUnknown -Reason ("the mail cannot be awaited'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("the mail cannot be awaited' }
        # A message the port would refuse is marked all the same (it would alarm for something never sent).
        @{ Name = "wake-mail-refusable-message-marked"
           Find = 'if ($findings.Count -gt 0) {'
           Replace = 'if ($false) {' }
        # A known refusal keeps its mark.
        @{ Name = "wake-mail-refusal-keeps-mark"
           Find = '$removed = Remove-HordeDecisionNoticeTaken -Kind $Kind -HordeHome $HordeHome -NoticeId $message.messageId'
           Replace = '$removed = [pscustomobject]@{ ok = $true; reason = "" }' }
        # An unknown result loses its mark (a mail that landed is no longer watched).
        @{ Name = "wake-mail-unknown-loses-mark"
           Find = 'if ($posted.state -cne "known") { return $posted }'
           Replace = 'if ($posted.state -cne "known") { $null = Remove-HordeDecisionNoticeTaken -Kind $Kind -HordeHome $HordeHome -NoticeId $message.messageId; return $posted }' }
        # A refusal (held) is counted as posted.
        @{ Name = "wake-mail-held-counts-as-posted"
           Find = '$script:HordeWakeMailStages = @("accepted", "handed-over", "seen")'
           Replace = '$script:HordeWakeMailStages = @("accepted", "handed-over", "seen", "held")' }
        # Whatever leaves the list is told as delivered, a give-up too.
        @{ Name = "wake-mail-given-up-read-as-delivered"
           Find = 'delivered = ($Memory.ContainsKey("delivered-" + $id))'
           Replace = 'delivered = $true' }
        # The list is never asked about.
        @{ Name = "wake-mail-tick-asks-nothing"
           Find = 'if ($before.Count -eq 0) { return'
           Replace = 'if ($true) { return' }
    )
}
