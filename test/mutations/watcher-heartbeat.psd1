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
        @{ Name = "reader-notice-key-changed"
           Find = 'Key "watcher-unread"'
           Replace = 'Key "watcher-unreadx"' }
        # The watcher's own heartbeat: told only when taken (T-0391 slice 8), and its limits.
        @{ Name = "beat-held-or-lost-notice-posted-again"
           Find = 'if ($St.tell -ceq "held" -or $St.tell -ceq "lost") {'
           Replace = 'if ($false) {' }
        @{ Name = "beat-posted-notice-posted-again"
           Find = 'if ($St.alerted -or $St.tell -ceq "posted") { return @($lines.ToArray()) }'
           Replace = 'if ($St.alerted) { return @($lines.ToArray()) }' }
        @{ Name = "beat-unknown-never-posted-again"
           Find = 'if ($St.alerted -or $St.tell -ceq "posted") { return @($lines.ToArray()) }'
           Replace = 'if ($St.alerted -or $St.tell -ceq "posted" -or $St.tell -ceq "maybe") { return @($lines.ToArray()) }' }
        @{ Name = "beat-unknown-not-looked-at"
           Find = 'if ($State.tell -cne "posted" -and $State.tell -cne "maybe") { return @() }'
           Replace = 'if ($State.tell -cne "posted") { return @() }' }
        @{ Name = "beat-episode-never-closes"
           Find = '        Write-HordeWatcherBeatState -Path $StatePath -State ([pscustomobject]@{ alerted = $false; since = $null; gen = ([long]$st.gen + 1)'
           Replace = '        $null = ([pscustomobject]@{ alerted = $false; since = $null; gen = ([long]$st.gen + 1)' }
        @{ Name = "alarm-told-though-nothing-was-accepted"
           Find = 'elseif ($null -ne $w -and ($w.state -ceq "posted" -or $w.state -ceq "maybe")) { Write-HordeWatcherBeatState'
           Replace = 'elseif ($true) { Write-HordeWatcherBeatState' }
        @{ Name = "mail-accepted-counts-as-told"
           Find = 'if ($n.ok) { Write-HordeWatcherBeatState'
           Replace = 'if ($n.ok -or ($null -ne $w -and $w.ok)) { Write-HordeWatcherBeatState' }
        @{ Name = "mail-taken-not-counted"
           Find = 'if ($t -ceq "taken") {'
           Replace = 'if ($false) {' }
        @{ Name = "mail-given-up-counted-as-told"
           Find = 'alerted = $false; since = $null; gen = [long]$State.gen; tell = $t; tellAt = $State.tellAt'
           Replace = 'alerted = $true; since = $null; gen = [long]$State.gen; tell = $t; tellAt = $State.tellAt' }
        @{ Name = "mail-held-stored-as-lost"
           Find = 'alerted = $false; since = $null; gen = [long]$State.gen; tell = $t; tellAt = $State.tellAt'
           Replace = 'alerted = $false; since = $null; gen = [long]$State.gen; tell = "lost"; tellAt = $State.tellAt' }
        @{ Name = "alarm-phone-words-always-posted"
           Find = '$words = Get-HordeWatchTellWords -State $w.state'
           Replace = '$words = Get-HordeWatchTellWords -State "posted"' }
        @{ Name = "alarm-phone-not-tried-again-for-a-held-notice"
           Find = 'if ($NoPost) { $words = Get-HordeWatchLostWords -Why $State.tell }'
           Replace = 'if ($NoPost) { return @() }' }
        @{ Name = "alarm-phone-words-for-a-held-notice-say-nothing"
           Find = 'if ($NoPost) { $words = Get-HordeWatchLostWords -Why $State.tell }'
           Replace = 'if ($NoPost) { $words = "" }' }
        @{ Name = "alarm-id-ignores-the-episode"
           Find = '-Gen ([long]$State.gen) -Text $WarchiefBody'
           Replace = '-Gen 0 -Text $WarchiefBody' }
        @{ Name = "episode-number-not-kept-in-the-file"
           Find = 'since = $null; gen = [long]$State.gen; tell = "" + $State.tell'
           Replace = 'since = $null; gen = 0; tell = "" + $State.tell' }
        @{ Name = "fresh-state-reuses-episode-zero"
           Find = '$clock = [long][System.Math]::Floor(($Now.ToUniversalTime() - ([datetime]"1970-01-01T00:00:00Z").ToUniversalTime()).TotalSeconds)'
           Replace = '$clock = [long]0' }
        @{ Name = "fresh-state-not-written-at-once"
           Find = 'if ($st.seeded) { Write-HordeWatcherBeatState -Path $Path -State $st; $st.seeded = $false }'
           Replace = '$st.seeded = $false' }
        @{ Name = "unreadable-state-reuses-episode-zero"
           Find = '} catch { $s.gen = $clock; $s.seeded = $true }'
           Replace = '} catch { $s.gen = 0; $s.seeded = $true }' }
        @{ Name = "beat-stale-limit-moved"
           Find = 'if ($fage -gt $staleMin)'
           Replace = 'if ($fage -gt ($staleMin + 1))' }
        @{ Name = "beat-hung-limit-moved"
           Find = 'if ($age -gt $hungMin)'
           Replace = 'if ($age -gt ($hungMin + 1))' }
    )
}
