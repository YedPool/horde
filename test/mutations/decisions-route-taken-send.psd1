# Mutations of decisions/Route.ps1, the send side of T-0391 slice 1 (an accepted notice is awaited before its route record
# is written, is said SENT and never delivered, and the awaiting list is asked first at every pass).
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-route-taken-send.psd1
# test\test-decisions-route-taken.ps1 must fail for every one. The awaiting list itself is in decisions-route-taken.psd1.
@{
    Target = "decisions\Route.ps1"
    Suite  = "test\test-decisions-route-taken.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # A list that cannot be written no longer holds the route record back.
        @{ Name = "unlisted-notice-still-recorded"
           Find = 'if (-not $awaited.ok) {'
           Replace = 'if ($false) {' }
        # The line says delivered for a notice that was only accepted.
        @{ Name = "accepted-line-says-delivered"
           Find = '"; SENT, not yet delivered: awaiting the session''s own TAKEN")'
           Replace = '"; delivered")' }
        # The awaiting list is not asked at the pass.
        @{ Name = "pass-skips-the-taken-check"
           Find = 'if ($takenState.state -cne "known" -or @($takenState.value.awaiting).Count -gt 0) {'
           Replace = 'if ($false) {' }
        # What the check says is not carried into the pass's lines.
        @{ Name = "taken-lines-not-said"
           Find = 'lines = @(@($takenLines) + @($Lines))'
           Replace = 'lines = @($Lines)' }
        # A refused post keeps its mark, which alarms "not taken" for a notice that was never sent.
        @{ Name = "refused-post-keeps-its-mark"
           Find = '$removed = Remove-HordeDecisionRouteTaken -HordeHome $HordeHome -NoticeId $noticeId'
           Replace = '$removed = [pscustomobject]@{ ok = $true; reason = "" }' }
        # The mark is not written before the post (it is never written, so the unusable-list tests post).
        @{ Name = "mark-not-before-the-post"
           Find = 'if (-not $Memory.ContainsKey("delivered-" + $noticeId)) {'
           Replace = 'if ($false) {' }
        # A notice taken in this process is listed again by its repost, and reported TAKEN a second time.
        @{ Name = "taken-notice-listed-again"
           Find = 'if (-not $Memory.ContainsKey("delivered-" + $noticeId)) {'
           Replace = 'if ($true) {' }
        # The notice's age limit is not the mailbox's.
        @{ Name = "pass-ignores-the-notice-ttl"
           Find = '-TtlSeconds $script:HordeDecisionRouteTtlSeconds'
           Replace = '-TtlSeconds 100000000000' }
        # The alarm limit of the setting is not the one the pass uses.
        @{ Name = "turn-ignores-the-alarm-setting"
           Find = '-TakenAlarmSeconds ([int]$v.takenAlarmSeconds)'
           Replace = '-TakenAlarmSeconds 100000' }
    )
}
