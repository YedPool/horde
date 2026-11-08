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
        # An unknown result may have landed: it is watched and posted again, not forgotten; a refusal is not posted.
        @{ Name = "unknown-result-taken-for-not-posted"
           Find = 'elseif ($ok) { "posted" } elseif ($listed) { "maybe" } else { "none" })'
           Replace = 'elseif ($ok) { "posted" } else { "none" })' }
        @{ Name = "refused-result-taken-for-posted"
           Find = 'elseif ($ok) { "posted" } elseif ($listed) { "maybe" } else { "none" })'
           Replace = 'else { "posted" })' }
        # ok with no mark kept is a repost of a copy the messenger already held: not posted, not watched, not taken (MUST-FIX 1a).
        @{ Name = "repost-of-a-held-copy-taken-for-posted"
           Find = '$state = $(if ($ok -and $hasListed -and -not $listed) { "copy" } elseif ($ok)'
           Replace = '$state = $(if ($false) { "copy" } elseif ($ok)' }
        @{ Name = "words-copy-says-posted"
           Find = 'return "Nothing new was posted to the warchief: the messenger already held a copy of this notice."'
           Replace = 'return "A notice to the warchief was posted and is being watched for its taking."' }
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
        # What became of a notice that is not taken and not watched, in what is known (MUST-FIX 2).
        @{ Name = "held-ignored-by-the-taken-look"
           Find = 'if ($a -ceq "held") { return "held" }'
           Replace = '' }
        @{ Name = "held-text-says-given-up"
           Find = 'return "could not be delivered (the messenger holds it for good) and is not taken"'
           Replace = 'return "was given up unread"' }
        @{ Name = "lost-text-says-unread"
           Find = 'return "was not taken in time and is no longer watched (it may still be in his mailbox)"'
           Replace = 'return "was given up unread"' }
        @{ Name = "lost-phone-words-say-nothing-reached"
           Find = 'return "The warchief''s notice was not taken in time and is no longer watched; it may still be in his mailbox."'
           Replace = 'return "No notice reached the warchief."' }
        @{ Name = "held-phone-words-say-given-up"
           Find = 'if ($Why -ceq "held") { return "The warchief''s notice could not be delivered: the messenger holds it, and it was not taken." }'
           Replace = 'if ($false) { return "" }' }
        # A tool that is off tells nobody.
        @{ Name = "off-tell-says-posted"
           Find = 'return [pscustomobject]@{ ok = $false; state = "none"; line = ($Prefix + ": would tell "'
           Replace = 'return [pscustomobject]@{ ok = $true; state = "posted"; line = ($Prefix + ": would tell "' }
    )
}
