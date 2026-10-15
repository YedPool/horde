# Mutations of cli/AnalystTend.ps1 (the analyst's supervisor, PR 306).
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\analyst-tend.psd1
# Each breaks one rule the review of PR 306 asked for; test\test-analyst-tend.ps1 must fail for every one.
@{
    Target = "cli\AnalystTend.ps1"
    Suite  = "test\test-analyst-tend.ps1"
    Mutations = @(
        # One pass at a time on this machine: a pass that cannot have the lock does nothing.
        @{ Name = "lock-not-held-still-passes"
           Find = 'if (-not $held) { return [pscustomobject]@{ lines = @("another pass of the analyst''s supervisor is running on this machine; this one did nothing")'
           Replace = 'if ($false) { return [pscustomobject]@{ lines = @("another pass of the analyst''s supervisor is running on this machine; this one did nothing")' }
        @{ Name = "lock-wait-skipped"
           Find = 'try { $held = $mutex.WaitOne([System.TimeSpan]::FromSeconds($WaitSeconds)) }'
           Replace = 'try { $held = $true }' }
        # Starting is written before the spawn runs.
        @{ Name = "starting-not-written-before-spawn"
           Find = '            Write-HordeAnalystState -Path $sp.state -State $s'
           Replace = '' }
        @{ Name = "start-not-marked-starting"
           Find = '$s.sessionId = ""; $s.phase = "starting"; $s.startedAt = $now'
           Replace = '$s.sessionId = ""; $s.phase = "gone"; $s.startedAt = $now' }
        # A spawn that failed or timed out stays starting and is never taken for nothing happened.
        @{ Name = "failed-spawn-forgotten"
           Find = '"; waiting for a handover all the same")'
           Replace = '"; waiting for a handover all the same"); $s.phase = "gone"' }
        # One no-answer alert for a run of unacked rounds, cleared only by a newer ack.
        @{ Name = "no-answer-told-every-round"
           Find = 'if (@($s.told) -ccontains "no-answer") { continue }'
           Replace = 'if ($false) { continue }' }
        @{ Name = "no-answer-never-cleared-by-ack"
           Find = '$s.lastAckId = $newestAcked[0].id; Clear-HordeAnalystTold -State $s -Keys @("no-answer") }'
           Replace = '$s.lastAckId = $newestAcked[0].id }' }
        @{ Name = "no-answer-cleared-without-new-ack"
           Find = 'if ($newestAcked.Count -eq 1 -and $newestAcked[0].id -cne $s.lastAckId) {'
           Replace = 'if ($true) {' }
    )
}
