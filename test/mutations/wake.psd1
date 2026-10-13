# Mutations of core/Wake.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake.psd1
# Each breaks one rule the wake watcher exists for - one of the six conditions of a nudge, the back-off,
# the fleet's rate limit and its order, the thresholds of a restore, who is told to resume and when, and
# shadow doing nothing; test\test-wake.ps1 must fail for every one.
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
           Find = '$next[$id] = [pscustomobject]@{ attempts = ($before + 1);'
           Replace = '$next[$id] = [pscustomobject]@{ attempts = 1;' }
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
           Find = 'if ("$($Outcomes[$id])" -ceq "nothing") { continue }'
           Replace = '' }
        @{ Name = "rate-limit-ignored"
           Find = 'if ($i -lt $allowed) {'
           Replace = 'if ($true) {' }
        @{ Name = "role-order-ignored"
           Find = 'Sort-Object -Property attempts, rank, oldest, id'
           Replace = 'Sort-Object -Property attempts, oldest, id' }
        @{ Name = "fewest-attempts-not-first"
           Find = 'Sort-Object -Property attempts, rank, oldest, id'
           Replace = 'Sort-Object -Property rank, oldest, id' }
        @{ Name = "oldest-mail-not-first"
           Find = 'Sort-Object -Property attempts, rank, oldest, id'
           Replace = 'Sort-Object -Property attempts, rank, id' }
        @{ Name = "shadow-nudges"
           Find = 'if ($Shadow) { $outcomes[$d.id] = "would-nudge";'
           Replace = 'if ($false) { $outcomes[$d.id] = "would-nudge";' }
        @{ Name = "shadow-posts"
           Find = 'if ($Shadow) { $nextPosted[$mail.messageId] = $true;'
           Replace = 'if ($false) { $nextPosted[$mail.messageId] = $true;' }
        @{ Name = "posted-mail-posted-again"
           Find = 'if ($nextPosted.ContainsKey($mail.messageId)) { continue }'
           Replace = '' }
        @{ Name = "unknown-post-marked-posted"
           Find = 'if ((Test-HordeAnswer $took) -and $took.state -ceq "known") {'
           Replace = 'if ($true) {' }
        @{ Name = "restore-share-ignored"
           Find = 'if (($best.Count / $all.Count) -lt $Settings.restoreShare) {'
           Replace = 'if ($false) {' }
        @{ Name = "restore-minimum-ignored"
           Find = 'if ($best.Count -lt $Settings.restoreMinSessions) {'
           Replace = 'if ($false) {' }
        @{ Name = "restore-window-a-day-long"
           Find = '$until = $from.AddSeconds($Settings.restoreWindowSeconds)'
           Replace = '$until = $from.AddSeconds(86400)' }
        @{ Name = "old-restore-still-planned"
           Find = 'if (($Now - $windowEnd).TotalSeconds -gt $Settings.restoreMaxAgeSeconds) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-status-change-is-a-move"
           Find = '$moved = (($_.lastChangeAt - $_.startedAt).TotalSeconds -ge $Settings.movedSeconds)'
           Replace = '$moved = (($_.lastChangeAt - $_.startedAt).TotalSeconds -gt 0)' }
        @{ Name = "restore-id-follows-the-clock"
           Find = '$minute.ToString("yyyy-MM-ddTHH:mm", [System.Globalization.CultureInfo]::InvariantCulture))'
           Replace = '$Now.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture))' }
        @{ Name = "restore-id-ignores-its-minute"
           Find = '$minute.ToString("yyyy-MM-ddTHH:mm", [System.Globalization.CultureInfo]::InvariantCulture))'
           Replace = '$minute.ToString("yyyy-MM-ddTHH", [System.Globalization.CultureInfo]::InvariantCulture))' }
        @{ Name = "message-id-follows-the-clock"
           Find = '+ $f.restoreId + "`n" + $m.id.ToLowerInvariant()'
           Replace = '+ $f.restoreId + "`n" + $Now.Ticks' }
        @{ Name = "message-id-same-for-every-session"
           Find = '+ $f.restoreId + "`n" + $m.id.ToLowerInvariant()'
           Replace = '+ $f.restoreId' }
        @{ Name = "orcs-held"
           Find = '$due = ($m.role -ceq "orc")'
           Replace = '$due = $false' }
        @{ Name = "goblins-not-held"
           Find = 'if (-not $due) { $due = ($sinceEnd -ge $Settings.goblinDelaySeconds) }'
           Replace = 'if (-not $due) { $due = $true }' }
        @{ Name = "goblins-never-released-by-time"
           Find = 'if (-not $due) { $due = ($sinceEnd -ge $Settings.goblinDelaySeconds) }'
           Replace = '' }
        @{ Name = "moved-parent-ignored"
           Find = 'if (-not $due) { $due = ($m.parent -cne "" -and $movedIds.ContainsKey($m.parent)) }'
           Replace = '' }
        @{ Name = "warchief-told-to-resume"
           Find = 'if ($m.moved -or $m.role -ceq "warchief") { continue }'
           Replace = 'if ($m.moved) { continue }' }
        @{ Name = "moved-session-told-to-resume"
           Find = 'if ($m.moved -or $m.role -ceq "warchief") { continue }'
           Replace = 'if ($m.role -ceq "warchief") { continue }' }
        @{ Name = "stall-notice-early"
           Find = 'if ($sinceEnd -ge $Settings.stallSeconds -and $movedIds.Count -eq 0) {'
           Replace = 'if ($movedIds.Count -eq 0) {' }
        @{ Name = "stall-notice-though-something-moved"
           Find = 'if ($sinceEnd -ge $Settings.stallSeconds -and $movedIds.Count -eq 0) {'
           Replace = 'if ($sinceEnd -ge $Settings.stallSeconds) {' }
        @{ Name = "unknown-journaled-every-pass"
           Find = '-and "$($Unknown["$($e.id)"])" -ceq "$($e.reason)") { continue }'
           Replace = '-and $false) { continue }' }
        @{ Name = "dead-session-counted-as-running"
           Find = 'if ("$($status.state)" -cne "known" -or $status.observedAt -isnot [datetime]) { continue }'
           Replace = 'if ($false) { continue }' }
        @{ Name = "partial-listing-read-as-the-fleet"
           Find = 'if ("$($whole.state)" -cne "known") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "role-guessed-from-nothing"
           Find = '$role = "unknown"'
           Replace = '$role = "goblin"' }
    )
}
