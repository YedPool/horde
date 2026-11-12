# Mutations of core/RestoreSource.ps1, T-0391 slice 9: a resume mail the messenger accepted is posted, not delivered - not counted as a
# restore done until the session's own TAKEN, and not posted again while it waits.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\restore-source-taken.psd1 [-Only <name>,...]
# test\test-wake-taken.ps1 must fail for every one.
@{
    Target = "core\RestoreSource.ps1"
    Suite  = "test\test-wake-taken.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # An awaiting answer is counted as posted (the restore counted done on accepted).
        @{ Name = "restore-awaiting-counted-posted"
           Find = 'if ((Test-HordeAnswer $took) -and $took.state -ceq "known") {'
           Replace = 'if ((Test-HordeAnswer $took) -and ($took.state -ceq "known" -or (Test-HordeWakeMailAwaiting $took))) {' }
        # An awaiting answer is journaled as a failure to post.
        @{ Name = "restore-awaiting-journaled-unknown"
           Find = '} elseif (Test-HordeWakeMailAwaiting $took) {'
           Replace = '} elseif ($false) {' }
        # A mail on the awaiting list is planned and posted again.
        @{ Name = "restore-awaiting-posted-again"
           Find = 'if (@($Awaiting) -ccontains $mail.messageId -and @($Retry) -cnotcontains $mail.messageId) { continue }'
           Replace = '' }
        # The poster marks another sender's list.
        @{ Name = "restore-poster-without-its-list"
           Find = '-Kind $script:HordeRestoreTakenKind -TtlSeconds'
           Replace = '-Kind $script:HordeWakeTellTakenKind -TtlSeconds' }
        # A mail named for a retry is not posted again.
        @{ Name = "restore-retry-ignored"
           Find = 'if (@($Awaiting) -ccontains $mail.messageId -and @($Retry) -cnotcontains $mail.messageId) { continue }'
           Replace = 'if (@($Awaiting) -ccontains $mail.messageId) { continue }' }
        # An already-posted answer is journaled as a failure.
        @{ Name = "restore-already-posted-journaled-unknown"
           Find = '} elseif (Test-HordeWakeMailAlready $took) {'
           Replace = '} elseif ($false) {' }
        # The eviction ALARM of a full list is not journaled.
        @{ Name = "restore-eviction-alarm-dropped"
           Find = 'foreach ($ln in @(Get-HordeWakeMailLines $took)) {'
           Replace = 'foreach ($ln in @()) {' }
        # A repost the messenger already held is called an acceptance.
        @{ Name = "restore-already-held-called-accepted"
           Find = 'if ($took.awaiting.alreadyHeld) {'
           Replace = 'if ($false) {' }
    )
}
