# Mutations of core/AnalystSession.ps1 (T-0341: a start that brings no session is failed and retried, bounded).
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\analyst-session.psd1
# test\test-analyst-tend.ps1 must fail for every one.
@{
    Target = "core\AnalystSession.ps1"
    Suite  = "test\test-analyst-tend.ps1"
    Mutations = @(
        @{ Name = "bound-ignored"
           Find = '$boundAt = $since.AddMinutes([int]$Policy.startBoundMinutes)'
           Replace = '$boundAt = [datetime]::MaxValue' }
        @{ Name = "attempts-unbounded"
           Find = '-lt [long]$Policy.startMaxAttempts)'
           Replace = '-lt [long]100000)' }
        @{ Name = "older-state-not-counted-as-a-start"
           Find = '[Math]::Max([long]1, [long]$State.startAttempts) -lt'
           Replace = '[long]$State.startAttempts -lt' }
        @{ Name = "unasked-spawn-log-is-a-failure"
           Find = '$noLog = ($SpawnLogged -eq $false -and'
           Replace = '$noLog = ($SpawnLogged -ne $true -and' }
        @{ Name = "spawn-log-grace-removed"
           Find = '$since.AddSeconds($script:HordeAnalystSpawnLogGraceSeconds)'
           Replace = '$since.AddSeconds(0)' }
        @{ Name = "attempts-not-written"
           Find = 'startReason = "" + $State.startReason; startAttempts = [long]$State.startAttempts'
           Replace = 'startReason = "" + $State.startReason' }
        @{ Name = "replaced-session-running-again-not-adopted"
           Find = 'if ($prevKnown -and $PreviousAlive.value -eq $true) {'
           Replace = 'if ($false) {' }
        @{ Name = "unknown-replaced-session-still-retries"
           Find = 'if ($prevUnsure) { [void]$unsure.Add('
           Replace = 'if ($false) { [void]$unsure.Add(' }
        @{ Name = "over-cap-replaced-session-readopted"
           Find = '$replacedGone = ("" + $State.startReason -ceq "gone")'
           Replace = '$replacedGone = $true' }
        # T-0341 review: no retry over a session that may exist, spacing, an unknown start time.
        @{ Name = "retry-over-a-late-session"
           Find = 'if (@($Late.value).Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "retry-on-unknown-late-listing"
           Find = 'if (-not $lateKnown) { [void]$unsure.Add('
           Replace = 'if ($false) { [void]$unsure.Add(' }
        @{ Name = "no-log-start-not-reported"
           Find = 'if ($noLog -and $utcNow -lt $boundAt) {'
           Replace = 'if ($false) {' }
        @{ Name = "missing-start-time-is-now"
           Find = '$State.startedAt } else { $utcNow.AddYears(-1) })'
           Replace = '$State.startedAt } else { $utcNow })' }
        @{ Name = "over-cap-retry-loses-its-reason"
           Find = '$again = $(if ("" + $State.startReason -ceq "over-cap") { "over-cap" } else { "gone" })'
           Replace = '$again = "gone"' }
        @{ Name = "replaced-session-counted-as-late"
           Find = 'if (@($Exclude) -ccontains ("" + $rec.sessionId)) { continue }'
           Replace = '' }
        @{ Name = "session-from-before-the-start-counted"
           Find = 'if ($began -lt $Since.ToUniversalTime().AddMinutes(-1)) { continue }'
           Replace = 'if ($false) { continue }' }
        @{ Name = "session-in-another-folder-counted"
           Find = 'foreach ($d in $dirs) { if ($where -ieq $d)'
           Replace = 'foreach ($d in $dirs) { if ($true)' }
        @{ Name = "listing-not-whole-taken-for-none"
           Find = 'if ($null -eq $whole -or $whole.state -cne "known") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "folder-above-the-analyst-counted"
           Find = '$dirs = @(($Folder -replace ''/'', ''\'').TrimEnd(''\''))'
           Replace = '$dirs = @(($Folder -replace ''/'', ''\'').TrimEnd(''\''), [System.IO.Path]::GetDirectoryName($Folder.TrimEnd(''\'')))' }
        @{ Name = "session-named-fleet-analyst-not-counted"
           Find = '-like "*M fleet analyst*"'
           Replace = '-like "*no such name*"' }
    )
}
