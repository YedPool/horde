# Mutations of core/WatchTell.ps1 (how the relay watch and the watcher check hand a tell to the warchief and count it, T-0391 slice 8).
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\watch-tell.psd1
# Each breaks one rule of it; test\test-relay-watch.ps1 must fail for every one (test\test-watcher-heartbeat.ps1 holds the same rules for the watcher check).
@{
    Target = "core\WatchTell.ps1"
    Suite  = "test\test-relay-watch.ps1"
    Mutations = @(
        # What the phone is told is what is known.
        @{ Name = "words-posted-claims-the-warchief-is-told"
           Find = 'return "A notice to the warchief was posted and is being watched for its taking."'
           Replace = 'return "The warchief is told by fleet mail."' }
        @{ Name = "words-maybe-says-not-posted"
           Find = 'return "A notice to the warchief may have been posted; the watch cannot tell."'
           Replace = 'return "A notice to the warchief was not posted."' }
        @{ Name = "words-none-says-posted"
           Find = 'return "A notice to the warchief was not posted."'
           Replace = 'return "A notice to the warchief was posted and is being watched for its taking."' }
        # An unknown result may have landed: it is watched, not forgotten.
        @{ Name = "unknown-result-taken-for-not-posted"
           Find = '$state = $(if ($ok) { "posted" } elseif ($listed) { "maybe" } else { "none" })'
           Replace = '$state = $(if ($ok) { "posted" } else { "none" })' }
        @{ Name = "refused-result-taken-for-posted"
           Find = '$state = $(if ($ok) { "posted" } elseif ($listed) { "maybe" } else { "none" })'
           Replace = '$state = "posted"' }
        # Only TAKEN counts; an answer that cannot be had counts as nothing.
        @{ Name = "no-answer-taken-for-taken"
           Find = 'return "unknown"'
           Replace = 'return "taken"' }
        @{ Name = "pending-taken-for-taken"
           Find = 'if ($a -ceq "pending") { return "pending" }'
           Replace = 'if ($a -ceq "pending") { return "taken" }' }
        @{ Name = "given-up-ignored"
           Find = 'if ($a -ceq "lost") { return "lost" }'
           Replace = '' }
        @{ Name = "age-rule-dropped"
           Find = '.TotalSeconds -ge $script:HordeWatchTellTtlSeconds) { return "lost" }'
           Replace = '.TotalSeconds -ge 9e99) { return "lost" }' }
        # The key and the generation reach both tools.
        @{ Name = "tell-gets-no-key"
           Find = 'try { $r = @(& $Tools["Tell"] $Text $Key $Gen) | Select-Object -Last 1 }'
           Replace = 'try { $r = @(& $Tools["Tell"] $Text) | Select-Object -Last 1 }' }
        @{ Name = "taken-gets-no-key"
           Find = '$a = "" + (@(& $Tools["Taken"] $Key $Gen) | Select-Object -Last 1)'
           Replace = '$a = "" + (@(& $Tools["Taken"]) | Select-Object -Last 1)' }
        # A tool that is off tells nobody.
        @{ Name = "off-tell-says-posted"
           Find = 'return [pscustomobject]@{ ok = $false; state = "none"; line = ($Prefix + ": would tell "'
           Replace = 'return [pscustomobject]@{ ok = $true; state = "posted"; line = ($Prefix + ": would tell "' }
    )
}
