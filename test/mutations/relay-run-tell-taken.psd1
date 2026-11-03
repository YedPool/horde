# Mutations of the relay run's full-mailbox notice to the warchief (cli/RelayRunTell.ps1), T-0391 slice 5: the notice is awaited BEFORE it
# is posted, is delivered only on the warchief's own TAKEN, a refusal (and only a refusal) takes its mark off, one alarm and a re-ask
# cadence and a 7-day give-up, and the notice id is stable.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-run-tell-taken.psd1
# test\test-relay-run-tell-taken.ps1 must fail for every one. The list's engine is in decisions-route-taken.psd1 (NoticeTaken.ps1).
@{
    Target = "cli\RelayRunTell.ps1"
    Suite  = "test\test-relay-run-tell-taken.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # A list that cannot be written no longer holds the post back.
        @{ Name = "run-tell-unlisted-notice-still-posted"
           Find = 'if (-not $awaited.ok) { return (& $done $false ("the notice cannot be awaited ('
           Replace = 'if ($false) { return (& $done $false ("the notice cannot be awaited (' }
        # The mark does not name the warchief's session.
        @{ Name = "run-tell-mark-without-session"
           Find = '-SessionId ("" + $where.value.sessionId) -Now $at'
           Replace = '-SessionId "" -Now $at' }
        # A known refusal keeps its mark (a never-sent notice alarms).
        @{ Name = "run-tell-refusal-keeps-mark"
           Find = '        $removed = Remove-HordeDecisionNoticeTaken -Kind $script:HordeRelayRunTellTakenKind -HordeHome $HordeHome -NoticeId $message.messageId'
           Replace = '        $removed = [pscustomobject]@{ ok = $true; reason = "" }' }
        # An unknown result loses its mark (a notice that landed is no longer watched).
        @{ Name = "run-tell-unknown-loses-mark"
           Find = '    return (& $done $false ("messenger " + $messenger.name + " did not take it: " + $posted.reason))'
           Replace = '    $null = Remove-HordeDecisionNoticeTaken -Kind $script:HordeRelayRunTellTakenKind -HordeHome $HordeHome -NoticeId $message.messageId; return (& $done $false ("messenger " + $messenger.name + " did not take it: " + $posted.reason))' }
        # A known refusal is counted as the messenger having taken it (a held post).
        @{ Name = "run-tell-refused-stage-counts-as-taken"
           Find = '$script:HordeRelayRunTellStages = @("accepted", "handed-over", "seen")'
           Replace = '$script:HordeRelayRunTellStages = @("accepted", "handed-over", "seen", "held")' }
        # The notice id changes on every pass (a restart posts a second message).
        @{ Name = "run-tell-notice-id-not-stable"
           Find = 'messageId = (Get-HordeRelayFullNoticeId -HordeHome $HordeHome -Mailbox $Mailbox -Day $Day);'
           Replace = 'messageId = [guid]::NewGuid().ToString();' }
        # The list is asked with no messenger: only the clock speaks, so a TAKEN is never seen.
        @{ Name = "run-tell-tick-never-asks-the-messenger"
           Find = 'if ($found.state -ceq "known") { $messenger = $found.value }'
           Replace = '$null = 0' }
        # The alarm limit, the re-ask cadence and the give-up are the engine's three clocks.
        @{ Name = "run-tell-alarm-limit-ignored"
           Find = '-Now $Now.ToUniversalTime() -AlarmSeconds $AlarmSeconds -AfterAlarmSeconds'
           Replace = '-Now $Now.ToUniversalTime() -AlarmSeconds 90 -AfterAlarmSeconds' }
        @{ Name = "run-tell-reask-every-pass"
           Find = '-AfterAlarmSeconds $AfterAlarmSeconds -TtlSeconds'
           Replace = '-AfterAlarmSeconds 0 -TtlSeconds' }
        @{ Name = "run-tell-never-given-up"
           Find = '-TtlSeconds $script:HordeRelayRunTellTtlSeconds -Memory $Memory'
           Replace = '-TtlSeconds 1e12 -Memory $Memory' }
        # The tick's memory is not the caller's: a table lost between passes asks every pass.
        @{ Name = "run-tell-memory-not-kept"
           Find = '-TtlSeconds $script:HordeRelayRunTellTtlSeconds -Memory $Memory'
           Replace = '-TtlSeconds $script:HordeRelayRunTellTtlSeconds -Memory @{}' }
    )
}