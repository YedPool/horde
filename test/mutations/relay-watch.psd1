# Mutations of core/RelayWatch.ps1 (the hosted relay watch, PR 307; told only when TAKEN, T-0391 slice 8).
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-watch.psd1
# Each breaks one rule the reviews of PR 307 and of slice 8 asked for; test\test-relay-watch.ps1 must fail for every one.
# The mutants of core/WatchTell.ps1 (the words, the Taken look, the age rule) are in test\mutations\watch-tell.psd1.
@{
    Target = "core\RelayWatch.ps1"
    Suite  = "test\test-relay-watch.ps1"
    Mutations = @(
        # Told only when TAKEN: a down notice the messenger accepted is posted, not told.
        @{ Name = "alerted-when-posted-not-taken"
           Find = 'if ($w.state -ceq "posted" -or $w.state -ceq "maybe") { $s.downTell = $w.state; if ($null -eq $s.downAt) { $s.downAt = $utcNow } }'
           Replace = 'if ($w.state -ceq "posted" -or $w.state -ceq "maybe") { $s.downTell = $w.state; if ($null -eq $s.downAt) { $s.downAt = $utcNow }; $s.alerted = $true }' }
        @{ Name = "down-taken-not-counted"
           Find = '$State.alerted = $true; $State.downTell = ""; $State.downAt = $null; $changed = $true;'
           Replace = '$State.downTell = ""; $State.downAt = $null; $changed = $true;' }
        @{ Name = "down-given-up-counted-as-told"
           Find = 'elseif ($t -ceq "held" -or $t -ceq "lost") { $State.downTell = $t; $changed = $true;'
           Replace = 'elseif ($t -ceq "held" -or $t -ceq "lost") { $State.downTell = $t; $State.alerted = $true; $changed = $true;' }
        @{ Name = "down-held-stored-as-lost"
           Find = 'elseif ($t -ceq "held" -or $t -ceq "lost") { $State.downTell = $t;'
           Replace = 'elseif ($t -ceq "held" -or $t -ceq "lost") { $State.downTell = "lost";' }
        @{ Name = "down-posted-again-while-awaited"
           Find = 'if ($s.downTell -ceq "" -or $s.downTell -ceq "maybe") {'
           Replace = 'if ($true) {' }
        # An UNKNOWN result may have landed: it is watched, and posted again under the same id (SHOULD-FIX 1).
        @{ Name = "down-unknown-never-posted-again"
           Find = 'if ($s.downTell -ceq "" -or $s.downTell -ceq "maybe") {'
           Replace = 'if ($s.downTell -ceq "") {' }
        @{ Name = "down-unknown-not-looked-at"
           Find = 'if ($State.downTell -ceq "posted" -or $State.downTell -ceq "maybe") {'
           Replace = 'if ($State.downTell -ceq "posted") {' }
        @{ Name = "down-first-post-time-forgotten-on-repost"
           Find = 'if ($null -eq $s.downAt) { $s.downAt = $utcNow } }'
           Replace = '$s.downAt = $utcNow }' }
        @{ Name = "back-unknown-never-posted-again"
           Find = '} elseif ($s.backTell -ceq "" -or $s.backTell -ceq "maybe") {'
           Replace = '} elseif ($s.backTell -ceq "") {' }
        @{ Name = "back-unknown-not-looked-at"
           Find = 'if ($State.backTell -ceq "posted" -or $State.backTell -ceq "maybe") {'
           Replace = 'if ($State.backTell -ceq "posted") {' }
        @{ Name = "back-told-to-the-phone-on-every-repost"
           Find = 'if ($first -and $s.notified) {'
           Replace = 'if ($s.notified) {' }
        @{ Name = "taken-look-not-kept-when-no-look-is-due"
           Find = 'if ($res.changed) { Write-HordeRelayWatchState -Path $StatePath -State $st }'
           Replace = '' }
        # Two healthy checks in a row before it is called back.
        @{ Name = "recovered-after-one-healthy-check"
           Find = 'if ($s.healthy -lt 2) { return'
           Replace = 'if ($s.healthy -lt 1) { return' }
        @{ Name = "healthy-run-not-reset-by-a-failure"
           Find = '    $s.healthy = 0'
           Replace = '' }
        # A recovery the warchief did not take stays owed: the episode closes only on the back notice's TAKEN.
        @{ Name = "recovery-closed-though-only-posted"
           Find = '$s.backTell = $w.state; if ($null -eq $s.backAt) { $s.backAt = $utcNow }'
           Replace = '$s.backTell = $w.state; if ($null -eq $s.backAt) { $s.backAt = $utcNow }; Close-HordeRelayEpisode -State $s' }
        @{ Name = "back-taken-does-not-close"
           Find = 'Close-HordeRelayEpisode -State $State; $changed = $true; [void]$lines.Add("relay watch: the warchief''s session took the BACK notice'
           Replace = '$changed = $true; [void]$lines.Add("relay watch: the warchief''s session took the BACK notice' }
        @{ Name = "back-given-up-does-not-close"
           Find = 'Close-HordeRelayEpisode -State $State; $changed = $true; [void]$lines.Add("relay watch: the BACK notice to the warchief "'
           Replace = '$changed = $true; [void]$lines.Add("relay watch: the BACK notice to the warchief "' }
        # The episode number: raised on close, kept in the file, in every id - and a state with no file takes it from the clock (MUST-FIX 1).
        @{ Name = "episode-not-raised-on-close"
           Find = '$State.episode = [long]$State.episode + 1'
           Replace = '$State.episode = [long]$State.episode' }
        @{ Name = "episode-not-kept-in-the-file"
           Find = 'episode = [long]$State.episode; downTell = "" + $State.downTell; downAt = $null'
           Replace = 'episode = 0; downTell = "" + $State.downTell; downAt = $null' }
        @{ Name = "fresh-state-reuses-episode-zero"
           Find = '$fresh.episode = [long][System.Math]::Floor(($Now.ToUniversalTime() - ([datetime]"1970-01-01T00:00:00Z").ToUniversalTime()).TotalSeconds)'
           Replace = '$fresh.episode = [long]0' }
        @{ Name = "fresh-state-ignores-the-passed-clock"
           Find = '$fresh.episode = [long][System.Math]::Floor(($Now.ToUniversalTime()'
           Replace = '$fresh.episode = [long][System.Math]::Floor(([datetime]::UtcNow.ToUniversalTime()' }
        @{ Name = "down-id-ignores-the-episode"
           Find = '-Key "relay-down" -Gen ([long]$s.episode)'
           Replace = '-Key "relay-down" -Gen 0' }
        @{ Name = "back-id-ignores-the-episode"
           Find = '-Key "relay-back" -Gen ([long]$s.episode)'
           Replace = '-Key "relay-back" -Gen 0' }
        @{ Name = "back-look-id-ignores-the-episode"
           Find = '-Key "relay-back" -Gen ([long]$State.episode)'
           Replace = '-Key "relay-back" -Gen 0' }
        # Each is told "back" only if it was told "down" (or the down notice is posted, or may be, and awaited).
        @{ Name = "warchief-told-back-though-never-told-down"
           Find = '$owed = ($s.alerted -or $s.downTell -ceq "posted" -or $s.downTell -ceq "maybe")'
           Replace = '$owed = $true' }
        @{ Name = "back-not-owed-for-a-posted-down"
           Find = '$owed = ($s.alerted -or $s.downTell -ceq "posted" -or $s.downTell -ceq "maybe")'
           Replace = '$owed = $s.alerted' }
        @{ Name = "back-not-owed-for-an-unknown-down"
           Find = '$owed = ($s.alerted -or $s.downTell -ceq "posted" -or $s.downTell -ceq "maybe")'
           Replace = '$owed = ($s.alerted -or $s.downTell -ceq "posted")' }
        @{ Name = "founder-told-back-though-never-told-down"
           Find = 'if ($first -and $s.notified) {'
           Replace = 'if ($first) {' }
        # A founder told "down" whose warchief never took it is still owed "back": no blip reset.
        @{ Name = "founder-told-down-forgotten-as-a-blip"
           Find = 'if (-not $s.alerted -and -not $s.notified -and $s.downTell -ceq "") {'
           Replace = 'if (-not $s.alerted -and $s.downTell -ceq "") {' }
        # What the phone is told is what is known (MUST-FIX 2): held is not delivered; lost was not taken; none was never posted.
        @{ Name = "phone-down-words-always-posted"
           Find = '". " + (Get-HordeWatchTellWords -State $tellState)'
           Replace = '". " + (Get-HordeWatchTellWords -State "posted")' }
        @{ Name = "phone-back-words-always-posted"
           Find = '". " + (Get-HordeWatchTellWords -State $w.state)'
           Replace = '". " + (Get-HordeWatchTellWords -State "posted")' }
        @{ Name = "phone-held-says-nothing-reached"
           Find = 'if ($DownTell -ceq "held") { return "The warchief''s notice about the outage could not be delivered (the messenger holds it), so none about its end is posted." }'
           Replace = 'if ($false) { return "" }' }
        @{ Name = "phone-lost-says-nothing-reached"
           Find = 'return "The warchief''s notice about the outage was not taken in time, so none about its end is posted."'
           Replace = 'return "No notice about the outage reached the warchief, so none about its end is posted."' }
        @{ Name = "phone-never-posted-says-lost"
           Find = 'return "No notice about the outage was posted to the warchief, so none about its end is posted."'
           Replace = 'return "The warchief''s notice about the outage was not taken in time, so none about its end is posted."' }
        # A DOWN notice later held or given up: the phone is told once, in what is known (SHOULD 3).
        @{ Name = "down-lost-phone-never-told"
           Find = 'if (($st.downTell -ceq "held" -or $st.downTell -ceq "lost") -and $st.notified -and -not $st.downLostTold -and $null -ne $Tools["Notify"]) {'
           Replace = 'if ($false) {' }
        @{ Name = "down-lost-phone-told-every-pass"
           Find = 'if ($nl.ok) { $st.downLostTold = $true; $res.changed = $true }'
           Replace = 'if ($nl.ok) { $res.changed = $true }' }
        @{ Name = "down-lost-phone-words-say-posted"
           Find = '(Get-HordeWatchLostWords -Why $st.downTell)) -Who "the founder''s phone"'
           Replace = '(Get-HordeWatchTellWords -State "posted")) -Who "the founder''s phone"' }
        @{ Name = "down-lost-phone-answer-not-kept-in-the-file"
           Find = 'backAt = $null; downLostTold = [bool]$State.downLostTold }'
           Replace = 'backAt = $null; downLostTold = $false }' }
        # One blip tells nobody.
        @{ Name = "down-on-first-failure"
           Find = '$s.failures -ge [int]$Policy.relayFailuresBeforeAlert) {'
           Replace = '$s.failures -ge 1) {' }
        # An unreadable state file is told, not a silent stop - and counted only when taken, once a day.
        # A state an earlier version wrote still reads; a value that is not known is unreadable, not guessed.
        @{ Name = "state-with-an-unknown-tell-value-accepted"
           Find = 'else { throw ($k + " is not a known value") }'
           Replace = 'else { }' }
        # PR 275's client-id rule: a byte order mark in the client id is a fault.
        @{ Name = "client-id-bom-accepted"
           Find = 'if ($Value.Contains([string][char]0xFEFF)) { return "the client_id carries a byte order mark (U+FEFF)" }'
           Replace = '' }
        # The STOPPED notice is still told from here (NIT 3 of the round-4 review): the call, and its mark and key.
        @{ Name = "stopped-notice-never-called"
           Find = 'foreach ($l in @(Send-HordeRelayWatchStopped -Tools $Tools -StatePath $StatePath -Now $utcNow)) { [void]$lines.Add($l) }'
           Replace = '' }
        @{ Name = "stopped-notice-key-changed"
           Find = '-Prefix "relay watch" -Key "relay-stopped" -Noun "STOPPED notice"'
           Replace = '-Prefix "relay watch" -Key "relay-stoppedx" -Noun "STOPPED notice"' }
        @{ Name = "stopped-notice-mark-path-changed"
           Find = '-MarkPath ($StatePath + ".told")'
           Replace = '-MarkPath ($StatePath + ".toldx")' }
    )
}
