# Mutations of core/WakeTell.ps1, T-0391 slice 9: a tell the messenger accepted is posted, not told - the warchief is told only when its
# own session took it - and a tell awaiting still counts against the hour's budget.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-tell-taken.psd1 [-Only <name>,...]
# test\test-wake-taken.ps1 must fail for every one.
@{
    Target = "core\WakeTell.ps1"
    Suite  = "test\test-wake-taken.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # An awaiting answer is counted as told.
        @{ Name = "tell-awaiting-counted-told"
           Find = 'if ((Test-HordeAnswer $took) -and $took.state -ceq "known") {'
           Replace = 'if ((Test-HordeAnswer $took) -and ($took.state -ceq "known" -or (Test-HordeWakeMailAwaiting $took))) {' }
        # An awaiting answer is a failed post, tried again after retrySeconds.
        @{ Name = "tell-awaiting-treated-as-failed"
           Find = '} elseif (Test-HordeWakeMailAwaiting $took) {'
           Replace = '} elseif ($false) {' }
        # A tell awaiting does not count against the hour's budget.
        @{ Name = "tell-awaiting-not-budgeted"
           Find = ' -or $_.state -ceq "awaiting"'
           Replace = '' }
        # The poster marks another sender's list.
        @{ Name = "tell-poster-without-its-list"
           Find = '-Kind $script:HordeWakeTellTakenKind -TtlSeconds'
           Replace = '-Kind $script:HordeRestoreTakenKind -TtlSeconds' }
        # The tell about an untaken resume mail is not a kind the tell sender knows.
        @{ Name = "tell-resume-untaken-not-a-kind"
           Find = '"duplicate-copies", "resume-untaken")'
           Replace = '"duplicate-copies")' }
        # An already-posted answer is a failed post.
        @{ Name = "tell-already-posted-treated-as-failed"
           Find = '} elseif (Test-HordeWakeMailAlready $took) {'
           Replace = '} elseif ($false) {' }
    )
}
