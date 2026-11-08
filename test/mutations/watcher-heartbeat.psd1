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
        @{ Name = "reader-episode-never-closes"
           Find = 'if ($st.alerted -or $st.tell -cne "") { Write-HordeWatcherBeatState'
           Replace = 'if ($false) { Write-HordeWatcherBeatState' }
        @{ Name = "reader-posted-notice-posted-again"
           Find = 'if ($st.tell -cne "") { return [pscustomobject]@{ lines = @(Resolve-HordeWatcherTell -Tools $Tools -State $st -StatePath $StatePath -Key "watcher-unread"'
           Replace = 'if ($false) { return [pscustomobject]@{ lines = @(Resolve-HordeWatcherTell -Tools $Tools -State $st -StatePath $StatePath -Key "watcher-unread"' }
        # The watcher's own heartbeat: told only when taken (T-0391 slice 8), and its limits.
        @{ Name = "beat-posted-notice-posted-again"
           Find = 'if ($st.tell -cne "") { return [pscustomobject]@{ lines = @(Resolve-HordeWatcherTell -Tools $Tools -State $st -StatePath $StatePath -Key "watcher-stale"'
           Replace = 'if ($false) { return [pscustomobject]@{ lines = @(Resolve-HordeWatcherTell -Tools $Tools -State $st -StatePath $StatePath -Key "watcher-stale"' }
        @{ Name = "beat-episode-never-closes"
           Find = '        Write-HordeWatcherBeatState -Path $StatePath -State ([pscustomobject]@{ alerted = $false; since = $null; gen = ([long]$st.gen + 1)'
           Replace = '        $null = ([pscustomobject]@{ alerted = $false; since = $null; gen = ([long]$st.gen + 1)' }
        @{ Name = "alarm-told-though-nothing-was-accepted"
           Find = 'elseif ($w.state -cne "none") {'
           Replace = 'elseif ($true) {' }
        @{ Name = "mail-accepted-counts-as-told"
           Find = 'if ($n.ok) { Write-HordeWatcherBeatState'
           Replace = 'if ($n.ok -or $w.ok) { Write-HordeWatcherBeatState' }
        @{ Name = "mail-taken-not-counted"
           Find = 'if ($t -ceq "taken") {'
           Replace = 'if ($false) {' }
        @{ Name = "mail-given-up-counted-as-told"
           Find = 'alerted = $false; since = $null; gen = [long]$State.gen; tell = "lost"'
           Replace = 'alerted = $true; since = $null; gen = [long]$State.gen; tell = "lost"' }
        @{ Name = "alarm-phone-words-always-posted"
           Find = '($PhoneText + " " + (Get-HordeWatchTellWords -State $w.state))'
           Replace = '($PhoneText + " " + (Get-HordeWatchTellWords -State "posted"))' }
        @{ Name = "alarm-id-ignores-the-episode"
           Find = '-Gen ([long]$State.gen) -Text $WarchiefBody'
           Replace = '-Gen 0 -Text $WarchiefBody' }
        @{ Name = "episode-number-not-kept-in-the-file"
           Find = 'since = $null; gen = [long]$State.gen; tell = "" + $State.tell'
           Replace = 'since = $null; gen = 0; tell = "" + $State.tell' }
        @{ Name = "unreadable-state-reuses-episode-zero"
           Find = 'Floor(([datetime]::UtcNow - ([datetime]"1970-01-01T00:00:00Z").ToUniversalTime()).TotalSeconds)'
           Replace = 'Floor(0)' }
        @{ Name = "beat-stale-limit-moved"
           Find = 'if ($fage -gt $staleMin)'
           Replace = 'if ($fage -gt ($staleMin + 1))' }
        @{ Name = "beat-hung-limit-moved"
           Find = 'if ($age -gt $hungMin)'
           Replace = 'if ($age -gt ($hungMin + 1))' }
    )
}
