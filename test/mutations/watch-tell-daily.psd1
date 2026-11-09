# Mutations of core/WatchTell.ps1 whose rules the WATCHER check's suite holds (the daily notice's state as a phone is told of it, T-0391 slice 8 round 5).
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\watch-tell-daily.psd1
# (The rules the relay watch's suite holds are in test\mutations\watch-tell.psd1.)
@{
    Target = "core\WatchTell.ps1"
    Suite  = "test\test-watcher-heartbeat.ps1"
    Mutations = @(
        @{ Name = "daily-notice-taken-forgotten-while-throttled"
           Find = '$(if ($content -ceq "told") { "taken" }'
           Replace = '$(if ($content -ceq "told") { "" }' }
        @{ Name = "daily-notice-held-stored-as-lost"
           Find = '& $setMark $t $false; [void]$lines.Add($Prefix + ": the " + $Noun'
           Replace = '& $setMark "lost" $false; [void]$lines.Add($Prefix + ": the " + $Noun' }
        @{ Name = "daily-notice-log-every-pass"
           Find = 'elseif ($logDue) { [void]$lines.Add($w.line);'
           Replace = 'elseif ($true) { [void]$lines.Add($w.line);' }
        @{ Name = "daily-notice-log-day-not-kept"
           Find = 'Set-HordeWatchLogged -MarkPath $MarkPath -Now $Now }'
           Replace = '}' }
        @{ Name = "daily-notice-maybe-refused-says-none"
           Find = '$(if ($again -and $w.state -cne "posted") { "maybe" } else { $w.state })'
           Replace = '$w.state' }
        @{ Name = "daily-notice-taken-not-recorded"
           Find = '& $setMark "told" $false;'
           Replace = '' }
        @{ Name = "taken-words-say-posted"
           Find = 'if ($State -ceq "taken") { return "A notice to the warchief was taken by his session." }'
           Replace = 'if ($State -ceq "taken") { return "A notice to the warchief was posted and is being watched for its taking." }' }
    )
}
