# Mutations of decisions/Notify.ps1, the doorbell for the founder's answers. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-notify.psd1
# test\test-decisions-notify.ps1 must fail for each.
#
# NOT MUTATED HERE: Start- and Stop-HordeDecisionNotifyBeside's runspace plumbing, which the suite
# drives once and test/e2e/e2e-decisions-notify.ps1 drives beside a real window; and the notice's
# wording, which no text of a message ever reaches (it is built from numbers alone).
@{
    Target = "decisions\Notify.ps1"
    Suite  = "test\test-decisions-notify.ps1"
    Mutations = @(
        # --- what a messenger must offer
        @{ Name = "a-doorbell-that-cannot-wake"
           Find = '$script:HordeDecisionNotifyMessengerNeeds = @("body.untyped", "idempotent.post", "wake")'
           Replace = '$script:HordeDecisionNotifyMessengerNeeds = @("body.untyped", "idempotent.post")' }
        # --- the quiet rule
        @{ Name = "quiet-period-not-waited"
           Find = 'if ($Now -lt $quietEnds) {'
           Replace = 'if ($false) {' }
        @{ Name = "rings-on-a-reading-begun-before-quiet-ended"
           Find = 'if ($ReadStartedAt -lt $quietEnds) {'
           Replace = 'if ($false) {' }
        @{ Name = "back-off-not-kept"
           Find = 'if ($Now -lt $NextAttemptAt) {'
           Replace = 'if ($false) {' }
        @{ Name = "future-stored-time-believed"
           Find = 'if ($null -ne $stored -and $stored -le $Now) { return $stored }'
           Replace = 'if ($null -ne $stored) { return $stored }' }
        @{ Name = "back-off-does-not-double"
           Find = '[Math]::Min($Tracker.retryDelay * 2, $script:HordeDecisionNotifyRetryMostSeconds)'
           Replace = '[Math]::Min($Tracker.retryDelay * 1, $script:HordeDecisionNotifyRetryMostSeconds)' }
        # --- what is rung for
        @{ Name = "told-messages-ring-again"
           Find = '$pending = @($unread.items | Where-Object { -not $record.told.Contains($_.message) })'
           Replace = '$pending = @($unread.items)' }
        @{ Name = "any-speaker-rings"
           Find = '"$($_.message.speaker)" -ceq $script:HordeDecisionNotifySpeaker'
           Replace = '$true' }
        @{ Name = "told-on-any-stage"
           Find = '$posted.state -ceq "known" -and $script:HordeDecisionNotifyStages -ccontains "$($posted.value.stage)"'
           Replace = '$posted.state -ceq "known"' }
        @{ Name = "notice-id-depends-on-order"
           Find = '((@($Ids | Sort-Object { [long]$_ }) | ForEach-Object { "$_" }) -join ",")'
           Replace = '((@($Ids) | ForEach-Object { "$_" }) -join ",")' }
        @{ Name = "notice-id-ignores-the-home"
           Find = '"horde-decisions-notify`n" + [System.IO.Path]::GetFullPath($HordeHome).TrimEnd(''\'').ToLowerInvariant() + "`n" +'
           Replace = '"horde-decisions-notify`n" +' }
        # --- the told record
        @{ Name = "unreadable-record-rings-from-empty-memory"
           Find = 'if ($record.state -ceq "refused") { return (& $result "refused"'
           Replace = 'if ($false) { return (& $result "refused"' }
        @{ Name = "key-given-twice-read-anyway"
           Find = 'if (@(Find-HordeJsonDuplicateKey -Text $text).Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "bad-entry-passed-over"
           Find = 'if (-not $ok) { return (& $no "refused"'
           Replace = 'if ($false) { return (& $no "refused"' }
        # --- the loop
        @{ Name = "second-notify-for-a-home-runs"
           Find = 'try { $held = $mutex.WaitOne(0) }'
           Replace = 'try { [void]$mutex.WaitOne(0); $held = $true }' }
        @{ Name = "stop-drops-an-answer-in-its-quiet-period"
           Find = 'elseif (-not ($last.outcome -ceq "waiting"'
           Replace = 'elseif ($true -or -not ($last.outcome -ceq "waiting"' }
        # --- who the notice is from
        @{ Name = "notice-wears-no-label"
           Find = 'sessionId = $script:HordeDecisionNotifyFrom; label = $Tracker.fromLabel }'
           Replace = 'sessionId = $script:HordeDecisionNotifyFrom }' }
        @{ Name = "tracker-ignores-the-label-given"
           Find = 'if ($FromLabel -eq "") { $FromLabel ='
           Replace = 'if ($true) { $FromLabel =' }
        @{ Name = "loop-ignores-the-settings-label"
           Find = '-QuietSeconds $v.quietSeconds -FromLabel $v.fromLabel'
           Replace = '-QuietSeconds $v.quietSeconds' }
        # --- woken, or only queued (the founder's bug of 2026-10-12)
        @{ Name = "bell-does-not-say-whether-woken"
           Find = '$posted.value.stage + $wake + ")"'
           Replace = '$posted.value.stage + ")"' }
    )
}
