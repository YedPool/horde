# Mutations of core/Wake.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake.psd1
# Each breaks one rule the wake watcher exists for - one of the six conditions of a nudge, the back-off,
# the fleet's rate limit and its order, and shadow doing nothing; test\test-wake.ps1 must fail for every one.
@{
    Target = "core\Wake.ps1"
    Suite  = "test\test-wake.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-pass-given-one-session-runs-over-them-all"
           Find = 'if ($Only -cne "") { [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "proof-target-absent" -Id $Only -Outcome "absent" -Reason "the fleet'
           Replace = 'if ($false) { [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "proof-target-absent" -Id $Only -Outcome "absent" -Reason "the fleet' }
        @{ Name = "the-one-session-is-whoever-is-first"
           Find = '$targets = @($targets | Where-Object { $_.id -ceq $Only })'
           Replace = '$targets = @($targets | Select-Object -First 1)' }
        @{ Name = "the-one-session-matched-in-any-casing"
           Find = '$targets = @($targets | Where-Object { $_.id -ceq $Only })'
           Replace = '$targets = @($targets | Where-Object { $_.id -eq $Only })' }
        @{ Name = "the-pass-is-not-cut-to-its-one-session"
           Find = '$targets = @($targets | Where-Object { $_.id -ceq $Only })'
           Replace = '$targets = @($targets | Where-Object { $_.id -ceq $Only }); if ($targets.Count -eq 1) { $targets = @($listing.value) }' }
        @{ Name = "a-session-limited-until-later-is-nudged"
           Find = 'if ($limit.kind -ceq "until") { return [pscustomobject]@{ action = "wait"; reason = $limit.text } }'
           Replace = '' }
        @{ Name = "a-limit-that-is-over-still-holds"
           Find = 'if ($until -is [datetime] -and $until -le $Now) { return [pscustomobject]@{ kind = "none"; text = "" } }'
           Replace = '' }
        @{ Name = "a-limit-ends-a-moment-late"
           Find = 'if ($until -is [datetime] -and $until -le $Now) { return'
           Replace = 'if ($until -is [datetime] -and $until -lt $Now) { return' }
        @{ Name = "every-session-read-as-limited"
           Find = 'if ((Get-HordeWakeEntryValue $State "limited") -ne $true) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "limited-with-no-end-knocked-every-pass"
           Find = 'if (($Now - $last).TotalSeconds -lt $every) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "the-hourly-knock-is-counted"
           Find = 'if ($Silent -or (Get-HordeWakeLimit -State $stateNow -Now $Now).kind -ceq "open") {'
           Replace = 'if ($Silent) {' }
        @{ Name = "a-silent-fleets-probes-are-counted"
           Find = 'if ($Silent -or (Get-HordeWakeLimit -State $stateNow -Now $Now).kind -ceq "open") {'
           Replace = 'if ((Get-HordeWakeLimit -State $stateNow -Now $Now).kind -ceq "open") {' }
        @{ Name = "the-hour-is-two"
           Find = 'limitedUnknownProbeSeconds = 3600'
           Replace = 'limitedUnknownProbeSeconds = 7200' }
        @{ Name = "first-seen-limited-never-noted"
           Find = 'if ((Get-HordeWakeEntryValue $had "probeAt") -is [datetime]) { continue }'
           Replace = 'continue' }
        @{ Name = "first-seen-limited-noted-anew-every-pass"
           Find = 'if ((Get-HordeWakeEntryValue $had "probeAt") -is [datetime]) { continue }'
           Replace = '' }
        @{ Name = "a-release-marks-nothing-due"
           Find = '-GaveUp ((Get-HordeWakeEntryValue $e "gaveUp") -eq $true) -ProbeAt $script:HordeWakeProbeDue'
           Replace = '-GaveUp ((Get-HordeWakeEntryValue $e "gaveUp") -eq $true) -ProbeAt (Get-HordeWakeEntryValue $e "probeAt")' }
        @{ Name = "a-release-makes-every-entry-a-probe"
           Find = 'if ((Get-HordeWakeEntryValue $e "probeAt") -isnot [datetime]) { continue }'
           Replace = '' }
        @{ Name = "a-limit-journaled-every-pass"
           Find = 'if ($null -ne $Seen -and $Seen.ContainsKey("$id") -and "$($Seen[$id])" -ceq $text) { continue }'
           Replace = '' }
        @{ Name = "a-changed-limit-not-journaled"
           Find = 'if ($null -ne $Seen -and $Seen.ContainsKey("$id") -and "$($Seen[$id])" -ceq $text) { continue }'
           Replace = 'if ($null -ne $Seen -and $Seen.ContainsKey("$id")) { continue }' }
        @{ Name = "an-unread-pass-makes-a-limit-news-again"
           Find = 'if (@($Known) -cnotcontains "$id") { $next["$id"] = $Seen[$id] }'
           Replace = '' }
        @{ Name = "a-limit-that-ended-is-remembered"
           Find = 'if (@($Known) -cnotcontains "$id") { $next["$id"] = $Seen[$id] }'
           Replace = '$next["$id"] = $Seen[$id]' }
        @{ Name = "a-fleet-is-never-silent"
           Find = '$notWoken = @($nudges | Where-Object { $_.outcome -cne "woken" })'
           Replace = '$notWoken = @(1)' }
        @{ Name = "a-busy-answer-does-not-count"
           Find = '$notWoken = @($nudges | Where-Object { $_.outcome -cne "woken" })'
           Replace = '$notWoken = @()' }
        @{ Name = "two-sessions-are-a-fleet"
           Find = 'fleetSilentSessions = 3'
           Replace = 'fleetSilentSessions = 2' }
        @{ Name = "silence-found-only-after-the-cap-is-spent"
           Find = 'fleetSilentMinutes = 5'
           Replace = 'fleetSilentMinutes = 10' }
        @{ Name = "silent-without-waiting"
           Find = 'if ($quietSince -is [datetime] -and ($Now - $quietSince).TotalSeconds -ge $window -and $who.Count'
           Replace = 'if ($quietSince -is [datetime] -and $who.Count' }
        @{ Name = "arriving-mail-is-movement"
           Find = 'if ($had -is [datetime] -and ($Mail[$id] -isnot [datetime] -or $Mail[$id] -ne $had)) { $moved = $true }'
           Replace = 'if ($Mail[$id] -isnot [datetime] -or $Mail[$id] -ne $had) { $moved = $true }' }
        @{ Name = "taken-mail-is-not-movement"
           Find = 'if ($had -is [datetime] -and ($Mail[$id] -isnot [datetime] -or $Mail[$id] -ne $had)) { $moved = $true }'
           Replace = '' }
        @{ Name = "another-mail-becoming-the-oldest-is-not-movement"
           Find = 'if ($had -is [datetime] -and ($Mail[$id] -isnot [datetime] -or $Mail[$id] -ne $had)) { $moved = $true }'
           Replace = 'if ($had -is [datetime] -and $Mail[$id] -isnot [datetime]) { $moved = $true }' }
        @{ Name = "fleet-moving-not-said"
           Find = 'if ($before.silent -eq $true) { [void]$out.Add((New-HordeWakeEntry -At $Now -Kind "fleet-moving"'
           Replace = 'if ($false) { [void]$out.Add((New-HordeWakeEntry -At $Now -Kind "fleet-moving"' }
        @{ Name = "fleet-moving-said-of-a-fleet-never-silent"
           Find = 'if ($before.silent -eq $true) { [void]$out.Add((New-HordeWakeEntry -At $Now -Kind "fleet-moving"'
           Replace = 'if ($true) { [void]$out.Add((New-HordeWakeEntry -At $Now -Kind "fleet-moving"' }
        @{ Name = "the-quiet-is-not-counted-anew-after-movement"
           Find = 'seen = [pscustomobject]@{ silent = $false; quietSince = $null; nudges = @(); mail = $mailNow }'
           Replace = 'seen = [pscustomobject]@{ silent = $false; quietSince = $before.quietSince; nudges = @($before.nudges); mail = $mailNow }' }
        @{ Name = "silent-found-again-every-pass"
           Find = 'if ($next.silent) { return [pscustomobject]@{ seen = $next; entries = @(); silent = $true; declared = $false;'
           Replace = 'if ($false) { return [pscustomobject]@{ seen = $next; entries = @(); silent = $true; declared = $false;' }
        @{ Name = "a-session-not-read-this-pass-is-forgotten"
           Find = 'foreach ($id in @($before.mail.Keys)) { $mailNow["$id"] = $before.mail[$id] }'
           Replace = '' }
        @{ Name = "a-killed-nudge-is-not-seen"
           Find = 'if ($null -eq $e -or @("nudge", "nudge-killed") -cnotcontains "$($e.kind)") { continue }'
           Replace = 'if ($null -eq $e -or @("nudge") -cnotcontains "$($e.kind)") { continue }' }
        @{ Name = "a-silent-fleet-is-asked-at-any-step"
           Find = 'if ($last -is [datetime] -and ($Now - $last).TotalSeconds -lt $longest) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "a-probe-is-still-held-by-the-cap"
           Find = 'if (-not $probe -and $null -ne $Entry -and [int]$Entry.attempts -ge [int]$Settings.maxNudgesPerMail)'
           Replace = 'if ($null -ne $Entry -and [int]$Entry.attempts -ge [int]$Settings.maxNudgesPerMail)' }
        @{ Name = "found-silent-the-attempts-are-kept"
           Find = '$next["$id"] = New-HordeWakeLedgerRow -Attempts 0 -LastAttemptAt $e.lastAttemptAt'
           Replace = '$next["$id"] = New-HordeWakeLedgerRow -Attempts ([int]$e.attempts) -LastAttemptAt $e.lastAttemptAt' }
        @{ Name = "when-it-was-probed-is-not-saved"
           Find = 'if ($probeAt -is [datetime]) { $row["probeAt"] = ConvertTo-HordeWakeTimeText $probeAt }'
           Replace = '' }
        @{ Name = "the-pass-does-not-say-who-is-limited"
           Find = 'if ($a.value.unreadCount -gt 0 -and $limit.kind -cne "none") { $limited[$t.id] = $limit.text }'
           Replace = '' }
        @{ Name = "the-pass-does-not-say-what-mail-each-holds"
           Find = '$mail[$t.id] = $a.value.oldestUnreadAt'
           Replace = '' }
        @{ Name = "the-pass-counts-a-silent-fleets-nudges"
           Find = '-States $states -Now $Now -Settings $Settings -Silent:$Silent'
           Replace = '-States $states -Now $Now -Settings $Settings' }
        @{ Name = "reachable-unknown-is-permission"
           Find = 'if ("$($Target.reachable)" -cne "yes") {'
           Replace = 'if ("$($Target.reachable)" -ceq "no") {' }
        @{ Name = "reachable-not-required"
           Find = 'if ("$($Target.reachable)" -cne "yes") {'
           Replace = 'if ($false) {' }
        @{ Name = "mid-turn-unknown-is-permission"
           Find = 'if ("$($s.midTurn)" -cne "no") {'
           Replace = 'if ("$($s.midTurn)" -ceq "yes") {' }
        @{ Name = "mid-turn-not-checked"
           Find = 'if ("$($s.midTurn)" -cne "no") {'
           Replace = 'if ($false) {' }
        @{ Name = "idle-unknown-is-permission"
           Find = 'if ("$($s.idle)" -cne "yes") {'
           Replace = 'if ("$($s.idle)" -ceq "no") {' }
        @{ Name = "idle-not-required"
           Find = 'if ("$($s.idle)" -cne "yes") {'
           Replace = 'if ($false) {' }
        @{ Name = "box-unknown-is-permission"
           Find = 'if ("$($s.boxEmpty)" -cne "yes") {'
           Replace = 'if ("$($s.boxEmpty)" -ceq "no") {' }
        @{ Name = "box-not-required"
           Find = 'if ("$($s.boxEmpty)" -cne "yes") {'
           Replace = 'if ($false) {' }
        @{ Name = "no-mail-waits-instead-of-skips"
           Find = 'return [pscustomobject]@{ action = "skip"; reason = "no unread mail" }'
           Replace = 'return [pscustomobject]@{ action = "wait"; reason = "no unread mail" }' }
        @{ Name = "young-mail-nudged"
           Find = 'if ($age -lt $Settings.minUnreadSeconds) {'
           Replace = 'if ($false) {' }
        @{ Name = "mail-held-at-exactly-the-minimum"
           Find = 'if ($age -lt $Settings.minUnreadSeconds) {'
           Replace = 'if ($age -le $Settings.minUnreadSeconds) {' }
        @{ Name = "back-off-ignored"
           Find = 'if ($since -lt $wait) {'
           Replace = 'if ($false) {' }
        @{ Name = "back-off-never-grows"
           Find = '$index = [System.Math]::Min($Attempts, $steps.Count) - 1'
           Replace = '$index = 0' }
        @{ Name = "back-off-table-loses-its-cap"
           Find = 'backoffSeconds = @(5, 15, 45, 135, 300)'
           Replace = 'backoffSeconds = @(5, 15, 45, 135)' }
        @{ Name = "attempts-not-counted"
           Find = '$count = $before + 1'
           Replace = '$count = 1' }
        @{ Name = "mail-taken-does-not-reset"
           Find = 'if ($taken -or $old) { $next.Remove($id) }'
           Replace = 'if ($old) { $next.Remove($id) }' }
        @{ Name = "stale-ledger-entry-kept"
           Find = 'if ($taken -or $old) { $next.Remove($id) }'
           Replace = 'if ($taken) { $next.Remove($id) }' }
        @{ Name = "outcome-counted-without-a-nudge"
           Find = 'if ($null -eq $d -or "$($d.action)" -cne "nudge") { continue }'
           Replace = 'if ($null -eq $d) { continue }' }
        @{ Name = "nothing-counted-as-an-attempt"
           Find = 'if ("$($Outcomes[$id])" -ceq "nothing") {'
           Replace = 'if ($false) {' }
        @{ Name = "nothing-holds-the-slot"
           Find = 'if (($Now - $nothingAt).TotalSeconds -lt $rest) {'
           Replace = 'if ($false) {' }
        @{ Name = "nothing-goes-first"
           Find = 'Sort-Object -Property nothing, attempts, rank, oldest, id'
           Replace = 'Sort-Object -Property attempts, rank, oldest, id' }
        @{ Name = "nothing-journaled-every-pass"
           Find = 'if ($rang.value.outcome -ceq "nothing" -and $null -ne (Get-HordeWakeNothingAt (Get-HordeWakeLedgerEntry -Ledger $Ledger -Id $d.id))) { continue }'
           Replace = '' }
        @{ Name = "hold-outlives-a-real-attempt"
           Find = '$next[$id] = New-HordeWakeLedgerRow -Attempts $count -LastAttemptAt $Now -LastOutcome "$($Outcomes[$id])" -MailAt $mailAt'
           Replace = '$next[$id] = New-HordeWakeLedgerRow -Attempts $count -LastAttemptAt $Now -LastOutcome "$($Outcomes[$id])" -MailAt $mailAt -NothingAt (Get-HordeWakeNothingAt $had)' }
        @{ Name = "shadow-ledger-written-where-live-reads"
           Find = 'Write-HordeWakeFile -Path (Get-HordeWakeStateFile -Name "ledger" -Shadow:$Shadow -Mode $Mode -HordeHome $HordeHome) -Text'
           Replace = 'Write-HordeWakeFile -Path (Get-HordeWakeStateFile -Name "ledger" -HordeHome $HordeHome) -Text' }
        @{ Name = "bad-mail-said-on-the-first-sighting"
           Find = 'if ($passes -ge 2 -and -not $told) {'
           Replace = 'if ($passes -ge 1 -and -not $told) {' }
        @{ Name = "bad-mail-said-every-pass"
           Find = 'if ($passes -ge 2 -and -not $told) {'
           Replace = 'if ($passes -ge 2) {' }
        @{ Name = "bad-mail-never-forgotten"
           Find = 'if ($count -le 0) { continue }'
           Replace = '' }
        @{ Name = "unreadable-count-not-handed-on"
           Find = '$states[$t.id].value.unreadableCount -gt 0) { $unreadable[$t.id] ='
           Replace = '$false) { $unreadable[$t.id] =' }
        @{ Name = "waker-not-told-a-pass-begins"
           Find = 'Start-HordeWakePass -Waker $Waker'
           Replace = '$null = 0' }
        @{ Name = "every-session-with-mail-is-looked-at"
           Find = 'if ($i -ge $allowed) { $ready[$i].action = "wait"; $ready[$i].reason = "rate limit" }'
           Replace = 'if ($i -ge $allowed -and $ready[$i].action -ceq "ready") { $ready[$i].action = "wait"; $ready[$i].reason = "rate limit" }' }
        @{ Name = "looks-in-a-pass-not-capped"
           Find = 'if ($looks -ge [int]$Settings.maxConfirmsPerPass) { break }'
           Replace = '' }
        @{ Name = "a-known-full-box-is-looked-at-anyway"
           Find = 'if ($CanLook -and $unseen -and "$($s.midTurn)" -cne "yes" -and "$($s.boxEmpty)" -cne "no") {'
           Replace = 'if ($CanLook) {' }
        @{ Name = "never-looks"
           Find = '$canLook = Test-HordeWakerConfirms $Waker'
           Replace = '$canLook = $false' }
        @{ Name = "a-session-already-looked-at-is-looked-at-again"
           Find = '-CanLook:($CanLook -and -not $looked)'
           Replace = '-CanLook:$CanLook' }
        @{ Name = "the-look-is-not-used"
           Find = 'if ($looked) { $answer = $Confirmed[$id] }'
           Replace = ''
           Expect = "survives"
           Reason = "the pass copies a look that is known into the states it decides from, so this line decides only for a look that itself failed, and then only the words of the wait: with it the session waits as unknown, without it as unread. It is what makes Get-HordeWakeDecisions right for a caller that hands it looks and leaves its states alone" }
        @{ Name = "killed-nudge-backs-off-like-any-other"
           Find = 'if ("$($Outcomes[$id])" -ceq "killed") { $count = [System.Math]::Max($count, @($Settings.backoffSeconds).Count) }'
           Replace = '' }
        @{ Name = "killed-nudge-sets-a-long-count-back"
           Find = '$count = [System.Math]::Max($count, @($Settings.backoffSeconds).Count) }'
           Replace = '$count = @($Settings.backoffSeconds).Count }' }
        @{ Name = "killed-nudge-journaled-as-a-nudge"
           Find = 'if ($rang.value.outcome -ceq "killed") { $kind = "nudge-killed" }'
           Replace = '' }
        @{ Name = "no-cap-on-nudges-for-one-mail"
           Find = 'if (-not $probe -and $null -ne $Entry -and [int]$Entry.attempts -ge [int]$Settings.maxNudgesPerMail) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "cap-of-seven"
           Find = 'maxNudgesPerMail = 6'
           Replace = 'maxNudgesPerMail = 7' }
        @{ Name = "gave-up-said-every-pass"
           Find = '-or (Get-HordeWakeEntryValue $e "gaveUp") -eq $true) { continue }'
           Replace = ') { continue }' }
        @{ Name = "gave-up-never-said"
           Find = '$gave = Update-HordeWakeGaveUp -Ledger $nextLedger -Now $Now -Settings $Settings'
           Replace = '$gave = [pscustomobject]@{ ledger = $nextLedger; entries = @(); sessions = @() }' }
        @{ Name = "a-new-oldest-mail-inherits-the-old-count"
           Find = '-and $State.oldestUnreadAt -ne $mailAt) { return $null }'
           Replace = '-and $false) { return $null }' }
        @{ Name = "given-up-on-forgotten-after-nothing"
           Find = '-NothingAt $Now -MailAt $mailAt -GaveUp ((Get-HordeWakeEntryValue $had "gaveUp") -eq $true) -ProbeAt (Get-HordeWakeEntryValue $had "probeAt") }'
           Replace = '-NothingAt $Now -MailAt $mailAt }' }
        @{ Name = "who-was-given-up-on-not-handed-on"
           Find = '$gaveUp = @($gave.sessions)'
           Replace = '$gaveUp = @()' }
        @{ Name = "a-failing-fleet-read-is-never-permanent"
           Find = 'if (-not $told -and $count -ge [int]$Settings.maxFleetReadFailures) {'
           Replace = 'if ($false) {' }
        @{ Name = "permanent-said-every-pass"
           Find = 'if (-not $told -and $count -ge [int]$Settings.maxFleetReadFailures) {'
           Replace = 'if ($count -ge [int]$Settings.maxFleetReadFailures) {' }
        @{ Name = "permanent-after-eleven"
           Find = 'maxFleetReadFailures = 10'
           Replace = 'maxFleetReadFailures = 11' }
        @{ Name = "the-wakers-own-count-ignored"
           Find = 'if ($given -is [int] -or $given -is [long]) { $count = [int]$given }'
           Replace = '' }
        @{ Name = "recovered-said-for-a-hiccup"
           Find = 'if ($before.told -eq $true) { [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "recovered"'
           Replace = 'if ($before.failures -gt 0) { [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "recovered"' }
        @{ Name = "failures-not-forgotten-when-it-works"
           Find = 'return [pscustomobject]@{ seen = [pscustomobject]@{ failures = 0; since = $null; told = $false }; entries = $entries.ToArray(); quiet = $false; condition = $null }'
           Replace = 'return [pscustomobject]@{ seen = $before; entries = $entries.ToArray(); quiet = $false; condition = $null }' }
        @{ Name = "listing-not-handed-on"
           Find = 'gaveUp = $gaveUp; listing = $listing; warchief = $warchief;'
           Replace = 'gaveUp = $gaveUp; listing = $null; warchief = $warchief;' }
        @{ Name = "one-of-two-warchiefs-chosen"
           Find = 'if ($chiefs.Count -eq 1) { $warchief = $chiefs[0].id }'
           Replace = 'if ($chiefs.Count -ge 1) { $warchief = $chiefs[0].id }' }
        @{ Name = "an-orc-taken-for-the-warchief"
           Find = '$chiefs = @($targets | Where-Object { $_.role -ceq "warchief" })'
           Replace = '$chiefs = @($targets)' }
        @{ Name = "rate-limit-ignored"
           Find = 'if ($i -ge $allowed) { $ready[$i].action = "wait"; $ready[$i].reason = "rate limit" }'
           Replace = 'if ($false) { $ready[$i].action = "wait"; $ready[$i].reason = "rate limit" }' }
        @{ Name = "role-order-ignored"
           Find = 'Sort-Object -Property nothing, attempts, rank, oldest, id'
           Replace = 'Sort-Object -Property nothing, attempts, oldest, id' }
        @{ Name = "fewest-attempts-not-first"
           Find = 'Sort-Object -Property nothing, attempts, rank, oldest, id'
           Replace = 'Sort-Object -Property nothing, rank, oldest, id' }
        @{ Name = "oldest-mail-not-first"
           Find = 'Sort-Object -Property nothing, attempts, rank, oldest, id'
           Replace = 'Sort-Object -Property nothing, attempts, rank, id' }
        @{ Name = "shadow-nudges"
           Find = 'if ($Shadow) { $outcomes[$d.id] = "would-nudge";'
           Replace = 'if ($false) { $outcomes[$d.id] = "would-nudge";' }
    )
}
