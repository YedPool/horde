# Mutations of core/Wake.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake.psd1
# Each breaks one rule the wake watcher exists for - one of the six conditions of a nudge, the back-off,
# the fleet's rate limit and its order, and shadow doing nothing; test\test-wake.ps1 must fail for every one.
@{
    Target = "core\Wake.ps1"
    Suite  = "test\test-wake.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
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
           Find = '$next[$id] = [pscustomobject]@{ attempts = $count; lastAttemptAt = $Now; lastOutcome = "$($Outcomes[$id])" }'
           Replace = '$next[$id] = [pscustomobject]@{ attempts = $count; lastAttemptAt = $Now; lastOutcome = "$($Outcomes[$id])"; nothingAt = (Get-HordeWakeNothingAt (Get-HordeWakeLedgerEntry -Ledger $Ledger -Id $id)) }' }
        @{ Name = "shadow-ledger-written-where-live-reads"
           Find = 'Write-HordeWakeFile -Path (Get-HordeWakeStateFile -Name "ledger" -Shadow:$Shadow -HordeHome $HordeHome) -Text'
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
           Find = 'if ($confirmed.Count -ge [int]$Settings.maxConfirmsPerPass) { break }'
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
           Replace = '' }
        @{ Name = "killed-nudge-backs-off-like-any-other"
           Find = 'if ("$($Outcomes[$id])" -ceq "killed") { $count = [System.Math]::Max($count, @($Settings.backoffSeconds).Count) }'
           Replace = '' }
        @{ Name = "killed-nudge-sets-a-long-count-back"
           Find = '$count = [System.Math]::Max($count, @($Settings.backoffSeconds).Count) }'
           Replace = '$count = @($Settings.backoffSeconds).Count }' }
        @{ Name = "killed-nudge-journaled-as-a-nudge"
           Find = 'if ($rang.value.outcome -ceq "killed") { $kind = "nudge-killed" }'
           Replace = '' }
        @{ Name = "rate-limit-ignored"
           Find = 'if ($i -ge $allowed) { $ready[$i].action = "wait"; $ready[$i].reason = "rate limit" }'
           Replace = '' }
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
