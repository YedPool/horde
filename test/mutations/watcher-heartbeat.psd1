# Mutations of core/WatcherHeartbeat.ps1 (the outside check of the overseer watcher and its alarm reader, T-0388).
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\watcher-heartbeat.psd1
# Each breaks one rule of that check; test\test-watcher-heartbeat.ps1 must fail for every one.
@{
    Target = "core\WatcherHeartbeat.ps1"
    Suite  = "test\test-watcher-heartbeat.ps1"
    Mutations = @(
        # A source that cannot be read must not read as all quiet.
        @{ Name = "reader-unknown-is-quiet"
           Find = 'stale = $true; kind = "unknown"'
           Replace = 'stale = $false; kind = ""' }
        @{ Name = "reader-no-mail-folder-is-quiet"
           Find = 'stale = $true; kind = "nomail"'
           Replace = 'stale = $false; kind = ""' }
        @{ Name = "reader-unlistable-inbox-is-quiet"
           Find = 'stale = $true; kind = "unreadable"; why = ("the alarm reader'
           Replace = 'stale = $false; kind = ""; why = ("the alarm reader' }
        # A message taken while it is looked at is not an old message (a missing file's time reads 1601).
        @{ Name = "reader-vanished-message-ages"
           Find = 'if ($t.Year -le 1601) { return $null }'
           Replace = '' }
        # Exactly 120 minutes old is not yet stale.
        @{ Name = "reader-boundary-moved"
           Find = 'if ($age -le $limit)'
           Replace = 'if ($age -lt $limit)' }
        # One notice per episode, told only when taken, and the next backlog is a new episode.
        @{ Name = "reader-told-every-pass"
           Find = 'if ($v.stale -and $st.alerted)'
           Replace = 'if ($false)' }
        @{ Name = "reader-told-though-nothing-was-taken"
           Find = '$told = ($n.ok -or $w.ok)'
           Replace = '$told = $true' }
        @{ Name = "reader-episode-never-closes"
           Find = 'if ($st.alerted) { Write-HordeWatcherBeatState -Path $StatePath -State ([pscustomobject]@{ alerted = $false; since = $null }) }'
           Replace = '' }
        # The watcher's own heartbeat: told only when taken, and its limits.
        @{ Name = "beat-told-though-nothing-was-taken"
           Find = 'if ($n.ok -or $w.ok) {'
           Replace = 'if ($true) {' }
        @{ Name = "beat-stale-limit-moved"
           Find = 'if ($fage -gt $staleMin)'
           Replace = 'if ($fage -gt ($staleMin + 1))' }
        @{ Name = "beat-hung-limit-moved"
           Find = 'if ($age -gt $hungMin)'
           Replace = 'if ($age -gt ($hungMin + 1))' }
    )
}
