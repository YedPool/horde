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
           Find = 'if ($w.state -cne "none") { $s.downTell = "posted"; $s.downAt = $utcNow }'
           Replace = 'if ($w.state -cne "none") { $s.downTell = "posted"; $s.downAt = $utcNow; $s.alerted = $true }' }
        @{ Name = "down-taken-not-counted"
           Find = '$State.alerted = $true; $State.downTell = ""; $State.downAt = $null; $changed = $true;'
           Replace = '$State.downTell = ""; $State.downAt = $null; $changed = $true;' }
        @{ Name = "down-given-up-counted-as-told"
           Find = 'elseif ($t -ceq "lost") { $State.downTell = "lost"; $changed = $true;'
           Replace = 'elseif ($t -ceq "lost") { $State.downTell = "lost"; $State.alerted = $true; $changed = $true;' }
        @{ Name = "down-posted-again-while-awaited"
           Find = 'if ($s.downTell -ceq "") {'
           Replace = 'if ($true) {' }
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
           Find = '$s.backTell = "posted"; $s.backAt = $utcNow'
           Replace = '$s.backTell = "posted"; $s.backAt = $utcNow; Close-HordeRelayEpisode -State $s' }
        @{ Name = "back-taken-does-not-close"
           Find = 'Close-HordeRelayEpisode -State $State; $changed = $true; [void]$lines.Add("relay watch: the warchief''s session took the BACK notice'
           Replace = '$changed = $true; [void]$lines.Add("relay watch: the warchief''s session took the BACK notice' }
        @{ Name = "back-given-up-does-not-close"
           Find = 'Close-HordeRelayEpisode -State $State; $changed = $true; [void]$lines.Add("relay watch: the BACK notice to the warchief was given up'
           Replace = '$changed = $true; [void]$lines.Add("relay watch: the BACK notice to the warchief was given up' }
        @{ Name = "episode-not-raised-on-close"
           Find = '$State.episode = [long]$State.episode + 1'
           Replace = '$State.episode = [long]$State.episode' }
        @{ Name = "episode-not-kept-in-the-file"
           Find = 'episode = [long]$State.episode; downTell = "" + $State.downTell; downAt = $null'
           Replace = 'episode = 0; downTell = "" + $State.downTell; downAt = $null' }
        @{ Name = "down-id-ignores-the-episode"
           Find = '-Key "relay-down" -Gen ([long]$s.episode)'
           Replace = '-Key "relay-down" -Gen 0' }
        @{ Name = "back-id-ignores-the-episode"
           Find = '-Key "relay-back" -Gen ([long]$s.episode)'
           Replace = '-Key "relay-back" -Gen 0' }
        @{ Name = "back-look-id-ignores-the-episode"
           Find = '-Key "relay-back" -Gen ([long]$State.episode)'
           Replace = '-Key "relay-back" -Gen 0' }
        # Each is told "back" only if it was told "down" (or the down notice is posted and awaited).
        @{ Name = "warchief-told-back-though-never-told-down"
           Find = '$owed = ($s.alerted -or $s.downTell -ceq "posted")'
           Replace = '$owed = $true' }
        @{ Name = "back-not-owed-for-a-posted-down"
           Find = '$owed = ($s.alerted -or $s.downTell -ceq "posted")'
           Replace = '$owed = $s.alerted' }
        @{ Name = "founder-told-back-though-never-told-down"
           Find = 'if ($s.notified) { [void]$lines.Add((Send-HordeRelayWatchWord -Tools $Tools -Name "Notify" -Text ("The relay is back; " + $d.why + ". " + (Get-HordeWatchTellWords'
           Replace = 'if ($true) { [void]$lines.Add((Send-HordeRelayWatchWord -Tools $Tools -Name "Notify" -Text ("The relay is back; " + $d.why + ". " + (Get-HordeWatchTellWords' }
        # A founder told "down" whose warchief never took it is still owed "back": no blip reset.
        @{ Name = "founder-told-down-forgotten-as-a-blip"
           Find = 'if (-not $s.alerted -and -not $s.notified -and $s.downTell -ceq "") {'
           Replace = 'if (-not $s.alerted -and $s.downTell -ceq "") {' }
        # What the phone is told is what is known.
        @{ Name = "phone-down-words-always-posted"
           Find = '". " + (Get-HordeWatchTellWords -State $tellState)'
           Replace = '". " + (Get-HordeWatchTellWords -State "posted")' }
        @{ Name = "phone-back-words-always-posted"
           Find = '". " + (Get-HordeWatchTellWords -State $w.state)'
           Replace = '". " + (Get-HordeWatchTellWords -State "posted")' }
        # One blip tells nobody.
        @{ Name = "down-on-first-failure"
           Find = '$s.failures -ge [int]$Policy.relayFailuresBeforeAlert) {'
           Replace = '$s.failures -ge 1) {' }
        # An unreadable state file is told, not a silent stop - and counted only when taken, once a day.
        @{ Name = "unreadable-state-silent"
           Find = 'if ($Now -lt $last.AddHours(24)) { return @() }'
           Replace = 'if ($true) { return @() }' }
        @{ Name = "unreadable-state-told-every-pass"
           Find = 'if ($Now -lt $last.AddHours(24)) { return @() }'
           Replace = '' }
        @{ Name = "stopped-posted-again-while-awaited"
           Find = 'if ($content -cmatch ''\Aposted ([0-9]{1,9})\z'') {'
           Replace = 'if ($false) {' }
        @{ Name = "stopped-taken-not-recorded"
           Find = 'if ($t -ceq "taken") { & $setMark "told";'
           Replace = 'if ($t -ceq "taken") {' }
        @{ Name = "stopped-marked-though-refused"
           Find = 'if ($w.state -cne "none") { & $setMark ("posted " + $day) }'
           Replace = '& $setMark ("posted " + $day)' }
        @{ Name = "stopped-id-ignores-the-day"
           Find = '-Key "relay-stopped" -Gen $day -Text'
           Replace = '-Key "relay-stopped" -Gen 0 -Text' }
        # A state an earlier version wrote still reads; a value that is not known is unreadable, not guessed.
        @{ Name = "state-with-an-unknown-tell-value-accepted"
           Find = 'else { throw ($k + " is not a known value") }'
           Replace = 'else { }' }
        # PR 275's client-id rule: a byte order mark in the client id is a fault.
        @{ Name = "client-id-bom-accepted"
           Find = 'if ($Value.Contains([string][char]0xFEFF)) { return "the client_id carries a byte order mark (U+FEFF)" }'
           Replace = '' }
    )
}
