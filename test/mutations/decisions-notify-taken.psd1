# Mutations of decisions/Notify.ps1, the doorbell side of T-0391 slice 3: a notice the messenger accepted is awaited BEFORE it is
# posted, is said SENT and never delivered, a refusal (and only a refusal) takes its mark off, the awaiting list is asked first at
# every pass, and what it says reaches the Turn and the Loop.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-notify-taken.psd1
# test\test-decisions-notify-taken.ps1 must fail for every one. The list's engine is in decisions-route-taken.psd1 (NoticeTaken.ps1).
@{
    Target = "decisions\Notify.ps1"
    Suite  = "test\test-decisions-notify-taken.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # The mark is never written before the post: an accepted notice is told and forgotten (today's bug).
        @{ Name = "no-mark-before-the-post"
           Find = 'if (-not $Tracker.taken.ContainsKey("delivered-" + $noticeId)) {'
           Replace = 'if ($false) {' }
        # A notice already TAKEN is listed again by the repost.
        @{ Name = "taken-notice-listed-again"
           Find = 'if (-not $Tracker.taken.ContainsKey("delivered-" + $noticeId)) {'
           Replace = 'if ($true) {' }
        # A list that cannot be written no longer holds the post back.
        @{ Name = "unlisted-notice-still-posted"
           Find = 'if (-not $awaited.ok) { $problem = '
           Replace = 'if ($false) { $problem = ' }
        # The mark does not name the warchief's session.
        @{ Name = "mark-without-session"
           Find = '-SessionId $sessionId -Now $now.ToUniversalTime()'
           Replace = '-SessionId "" -Now $now.ToUniversalTime()' }
        # The line says delivered for a notice that was only accepted.
        @{ Name = "accepted-line-says-delivered"
           Find = '+ "); SENT, not yet delivered: awaiting the session''s own TAKEN"'
           Replace = '+ "); delivered"' }
        # The awaiting list is not asked at the pass.
        @{ Name = "pass-skips-the-taken-check"
           Find = 'if ($takenState.state -cne "known" -or @($takenState.value.awaiting).Count -gt 0) {'
           Replace = 'if ($false) {' }
        # What the check says is not carried out of the pass.
        @{ Name = "taken-lines-not-carried"
           Find = 'takenLines = @($takenLines); takenFailed = $takenFailed }'
           Replace = 'takenLines = @(); takenFailed = $takenFailed }' }
        # The alarm limit is ignored: every notice alarms at once.
        @{ Name = "alarm-limit-ignored"
           Find = '-AlarmSeconds $Tracker.takenAlarmSeconds'
           Replace = '-AlarmSeconds 0' }
        # The after-alarm cadence is ignored: an alarmed notice is asked at every pass.
        @{ Name = "after-alarm-cadence-ignored"
           Find = '-AfterAlarmSeconds $Tracker.takenAfterAlarmSeconds'
           Replace = '-AfterAlarmSeconds 0' }
        # A notice is never given up at its age limit.
        @{ Name = "notice-never-expires"
           Find = '-TtlSeconds $script:HordeDecisionNotifyTtlSeconds -Memory $Tracker.taken'
           Replace = '-TtlSeconds 100000000000 -Memory $Tracker.taken' }
        # The tracker's memory is not handed to the tick: a failed write repeats its alarm, a TAKEN is forgotten.
        @{ Name = "tick-memory-not-passed"
           Find = '-Memory $Tracker.taken'
           Replace = '' }
        # A refused post keeps its mark, which alarms "not taken" for a notice that was never sent.
        @{ Name = "refused-post-keeps-its-mark"
           Find = '$removed = Remove-HordeDecisionNoticeTaken -Kind $script:HordeDecisionNotifyTakenKind -HordeHome $HordeHome -NoticeId $noticeId'
           Replace = '$removed = [pscustomobject]@{ ok = $true; reason = "" }' }
        # An UNKNOWN post result (a timeout) is treated as a refusal: the mark of a notice that may have landed is removed.
        @{ Name = "unknown-result-removes-the-mark"
           Find = 'if ($posted.state -ceq "known") { $removed = Remove-HordeDecisionNoticeTaken'
           Replace = 'if ($true) { $removed = Remove-HordeDecisionNoticeTaken' }
        # The Turn drops what the list said.
        @{ Name = "turn-drops-the-lines"
           Find = 'lines = @($takenOut); againMs = $AgainMs }'
           Replace = 'lines = @(); againMs = $AgainMs }' }
        # The Turn says an unreadable list at every turn.
        @{ Name = "turn-repeats-an-unreadable-list"
           Find = 'if ($takenText -ceq "$($Memory[''takenFailedSaid''])") { $takenOut = @() }'
           Replace = '' }
        # The Loop prints nothing of what the list said.
        @{ Name = "loop-silent-about-the-list"
           Find = 'foreach ($takenLine in @($last.takenLines)) { Write-Output $takenLine }'
           Replace = 'foreach ($takenLine in @()) { Write-Output $takenLine }' }
    )
}
