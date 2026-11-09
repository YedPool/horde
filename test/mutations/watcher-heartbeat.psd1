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
        # One alarm per episode; the phone's accept does NOT end the watch on the warchief's mail; the next backlog is a new episode.
        @{ Name = "reader-episode-never-closes"
           Find = 'if ($st.alerted -or $st.tell -cne "" -or $st.phoneAbout -cne "") { Write-HordeWatcherBeatState'
           Replace = 'if ($false) { Write-HordeWatcherBeatState' }
        @{ Name = "reader-notice-key-changed"
           Find = 'Key "watcher-unread"'
           Replace = 'Key "watcher-unreadx"' }
        @{ Name = "reader-unreadable-state-forgotten"
           Find = 'if ($st.unreadable) { return [pscustomobject]@{ lines = @(Send-HordeWatcherUnreadable -Tools $Tools -StatePath $StatePath -Now $now -Prefix "watcher reader check"'
           Replace = 'if ($false) { return [pscustomobject]@{ lines = @(Send-HordeWatcherUnreadable -Tools $Tools -StatePath $StatePath -Now $now -Prefix "watcher reader check"' }
        # A state file that cannot be read fails closed: said, kept, not written over, not taken for a fresh one (SHOULD 1).
        @{ Name = "beat-unreadable-state-forgotten"
           Find = 'if ($st.unreadable) { return [pscustomobject]@{ lines = @(Send-HordeWatcherUnreadable -Tools $Tools -StatePath $StatePath -Now $now -Prefix "watcher check"'
           Replace = 'if ($false) { return [pscustomobject]@{ lines = @(Send-HordeWatcherUnreadable -Tools $Tools -StatePath $StatePath -Now $now -Prefix "watcher check"' }
        @{ Name = "state-with-an-unknown-tell-accepted"
           Find = 'else { throw "tell is not a known value" }'
           Replace = 'else { }' }
        @{ Name = "state-with-an-unknown-phone-value-accepted"
           Find = 'else { throw "phoneAbout is not a known value" }'
           Replace = 'else { }' }
        @{ Name = "state-from-before-the-phone-field-told-again"
           Find = 'elseif ($s.alerted) { $s.phoneAbout = "legacy" }'
           Replace = '' }
        # THE PHONE ACCEPTING IS NOT THE EPISODE TOLD (MUST 1): the warchief's mail is looked at until it is taken, held or given up.
        @{ Name = "beat-phone-accept-ends-the-watch"
           Find = '$over = (($St.tell -ceq "" -and $phoneKnows -and $words -ceq "off") -or'
           Replace = '$over = (($St.tell -ceq "" -and $phoneKnows) -or' }
        @{ Name = "beat-stops-at-alerted-though-the-phone-refused"
           Find = 'if ($st.alerted -and $st.phoneAbout -cne "") { return [pscustomobject]@{ lines = @() } }'
           Replace = 'if ($st.alerted) { return [pscustomobject]@{ lines = @() } }' }
        @{ Name = "beat-phone-not-told-again-when-the-mail-is-held"
           Find = '$needPhone = ($St.phoneAbout -ceq "" -or ($lost -and $St.phoneAbout -cne "held" -and $St.phoneAbout -cne "lost"))'
           Replace = '$needPhone = ($St.phoneAbout -ceq "")' }
        @{ Name = "beat-phone-answer-not-kept"
           Find = 'if ($n.ok) { $St.phoneAbout = $words }'
           Replace = 'if ($n.ok) { }' }
        @{ Name = "beat-phone-words-always-posted"
           Find = '(Get-HordeWatcherPhoneWords -State $words)'
           Replace = '(Get-HordeWatcherPhoneWords -State "posted")' }
        @{ Name = "beat-held-words-say-nothing"
           Find = 'if ($State -ceq "held" -or $State -ceq "lost") { return (Get-HordeWatchLostWords -Why $State) }'
           Replace = 'if ($false) { return "" }' }
        @{ Name = "beat-taken-words-say-posted"
           Find = 'return "A notice to the warchief was taken by his session."'
           Replace = 'return "A notice to the warchief was posted and is being watched for its taking."' }
        @{ Name = "beat-back-notice-needs-alerted"
           Find = 'if ($st.alerted -or $st.phoneAbout -cne "") {'
           Replace = 'if ($st.alerted) {' }
        # The warchief's mail: counted only on TAKEN, looked at while awaited, posted again when unknown, aged from its first post.
        @{ Name = "beat-taken-not-counted"
           Find = '$State.alerted = $true; $State.since = $Now; $State.tell = "taken"'
           Replace = '$State.since = $Now; $State.tell = "taken"' }
        @{ Name = "beat-unknown-not-looked-at"
           Find = 'if ($State.tell -cne "posted" -and $State.tell -cne "maybe") { return @() }'
           Replace = 'if ($State.tell -cne "posted") { return @() }' }
        @{ Name = "beat-held-stored-as-lost"
           Find = '        $State.tell = $t'
           Replace = '        $State.tell = "lost"' }
        @{ Name = "beat-posted-notice-posted-again"
           Find = 'if (-not $St.alerted -and ($St.tell -ceq "" -or $St.tell -ceq "maybe")) {'
           Replace = 'if (-not $St.alerted) {' }
        @{ Name = "beat-unknown-never-posted-again"
           Find = 'if (-not $St.alerted -and ($St.tell -ceq "" -or $St.tell -ceq "maybe")) {'
           Replace = 'if (-not $St.alerted -and $St.tell -ceq "") {' }
        @{ Name = "beat-first-post-time-forgotten-on-repost"
           Find = 'if ($null -eq $St.tellAt) { $St.tellAt = $Now }'
           Replace = '$St.tellAt = $Now' }
        @{ Name = "beat-mail-accepted-counts-as-told"
           Find = 'if ($w.state -ceq "posted" -or $w.state -ceq "maybe") { $St.tell = $w.state;'
           Replace = 'if ($w.state -ceq "posted" -or $w.state -ceq "maybe") { $St.alerted = $true; $St.tell = $w.state;' }
        @{ Name = "beat-state-change-not-written"
           Find = 'if ($before -cne ("" + $St.alerted'
           Replace = 'if ($false -and $before -cne ("" + $St.alerted' }
        @{ Name = "beat-episode-never-closes"
           Find = '        Write-HordeWatcherBeatState -Path $StatePath -State (New-HordeWatcherBeatState -Gen ([long]$st.gen + 1))'
           Replace = '        $null = (New-HordeWatcherBeatState -Gen ([long]$st.gen + 1))' }
        @{ Name = "alarm-id-ignores-the-episode"
           Find = '-Gen ([long]$St.gen) -Text $WarchiefBody'
           Replace = '-Gen 0 -Text $WarchiefBody' }
        @{ Name = "episode-number-not-kept-in-the-file"
           Find = 'since = $null; gen = [long]$State.gen; tell = "" + $State.tell'
           Replace = 'since = $null; gen = 0; tell = "" + $State.tell' }
        @{ Name = "phone-answer-not-kept-in-the-file"
           Find = 'tellAt = $null; phoneAbout = "" + $State.phoneAbout }'
           Replace = 'tellAt = $null; phoneAbout = "" }' }
        @{ Name = "fresh-state-reuses-episode-zero"
           Find = '$clock = [long][System.Math]::Floor(($Now.ToUniversalTime() - ([datetime]"1970-01-01T00:00:00Z").ToUniversalTime()).TotalSeconds)'
           Replace = '$clock = [long]0' }
        @{ Name = "fresh-state-not-written-at-once"
           Find = 'if ($st.seeded) { Write-HordeWatcherBeatState -Path $Path -State $st; $st.seeded = $false }'
           Replace = '$st.seeded = $false' }
        @{ Name = "beat-stale-limit-moved"
           Find = 'if ($fage -gt $staleMin)'
           Replace = 'if ($fage -gt ($staleMin + 1))' }
        @{ Name = "beat-hung-limit-moved"
           Find = 'if ($age -gt $hungMin)'
           Replace = 'if ($age -gt ($hungMin + 1))' }
        # An unreadable state file: kept, and a person is told once a day on the TAKEN rules (ROUND 4).
        @{ Name = "unreadable-state-key-changed"
           Find = '-Key $Key -Noun "UNREADABLE-STATE notice"'
           Replace = '-Key "x" -Noun "UNREADABLE-STATE notice"' }
        @{ Name = "unreadable-state-phone-never-told"
           Find = 'if (($dailyDue -or $update) -and $null -ne $Tools["Notify"]) {'
           Replace = 'if ($false) {' }
        @{ Name = "unreadable-state-phone-told-every-pass"
           Find = '$dailyDue = (-not $pmExists) -or ($Now -ge [System.IO.File]::GetLastWriteTimeUtc($pm).AddHours(24))'
           Replace = '$dailyDue = $true' }
        @{ Name = "unreadable-state-logged-every-pass"
           Find = 'if ($r.logDue) { [void]$lines.Add($Prefix + ": its state file cannot be read'
           Replace = 'if ($true) { [void]$lines.Add($Prefix + ": its state file cannot be read' }
        @{ Name = "unreadable-phone-never-corrected"
           Find = '$update = ($pmExists -and $terminal -and $told -cne $r.state)'
           Replace = '$update = $false' }
        @{ Name = "unreadable-phone-corrected-every-pass"
           Find = '$update = ($pmExists -and $terminal -and $told -cne $r.state)'
           Replace = '$update = ($pmExists -and $terminal)' }
        @{ Name = "unreadable-phone-told-of-every-posted"
           Find = '$terminal = ($r.state -ceq "taken" -or $r.state -ceq "held" -or $r.state -ceq "lost")'
           Replace = '$terminal = ($r.state -cne "")' }
        @{ Name = "unreadable-phone-answer-not-kept"
           Find = '[System.IO.File]::WriteAllText($pm, $(if ($r.state -cne "") { $r.state } else { "none" }))'
           Replace = '[System.IO.File]::WriteAllText($pm, "told")' }
    )
}
