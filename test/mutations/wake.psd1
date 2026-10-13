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
           Find = '$next[$id] = [pscustomobject]@{ attempts = ($before + 1); lastAttemptAt'
           Replace = '$next[$id] = [pscustomobject]@{ attempts = 1; lastAttemptAt' }
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
           Find = '$next[$id] = [pscustomobject]@{ attempts = ($before + 1); lastAttemptAt = $Now; lastOutcome = "$($Outcomes[$id])" }'
           Replace = '$next[$id] = [pscustomobject]@{ attempts = ($before + 1); lastAttemptAt = $Now; lastOutcome = "$($Outcomes[$id])"; nothingAt = (Get-HordeWakeNothingAt (Get-HordeWakeLedgerEntry -Ledger $Ledger -Id $id)) }' }
        @{ Name = "shadow-ledger-written-where-live-reads"
           Find = 'Write-HordeWakeFile -Path (Get-HordeWakeStateFile -Name "ledger" -Shadow:$Shadow -HordeHome $HordeHome) -Text'
           Replace = 'Write-HordeWakeFile -Path (Get-HordeWakeStateFile -Name "ledger" -HordeHome $HordeHome) -Text' }
        @{ Name = "rate-limit-ignored"
           Find = 'if ($i -lt $allowed) {'
           Replace = 'if ($true) {' }
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
