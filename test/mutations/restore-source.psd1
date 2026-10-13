# Mutations of core/RestoreSource.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\restore-source.psd1
# Each breaks one rule the restore source exists for - the thresholds of a restore, who is told to resume
# and who never is, the stall notice, ids that never change, and shadow posting nothing;
# test\test-restore-source.ps1 must fail for every one.
@{
    Target = "core\RestoreSource.ps1"
    Suite  = "test\test-restore-source.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
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
           Find = 'if (($best.Count / $lived.Count) -lt $Settings.restoreShare) {'
           Replace = 'if ($false) {' }
        @{ Name = "spawned-session-counted-as-restored"
           Find = '$_.firstSeenAt -is [datetime] -and ($_.startedAt - $_.firstSeenAt).TotalSeconds -ge $Settings.earlierLifeSeconds }'
           Replace = '$true }' }
        @{ Name = "any-record-is-an-earlier-life"
           Find = '$_.firstSeenAt -is [datetime] -and ($_.startedAt - $_.firstSeenAt).TotalSeconds -ge $Settings.earlierLifeSeconds }'
           Replace = '$_.firstSeenAt -is [datetime] }' }
        @{ Name = "share-taken-among-every-session"
           Find = 'if (($best.Count / $lived.Count) -lt $Settings.restoreShare) {'
           Replace = 'if (($best.Count / $all.Count) -lt $Settings.restoreShare) {' }
        @{ Name = "first-seen-not-carried"
           Find = 'status = "$($status.value)"; firstSeenAt = $firstSeenAt })'
           Replace = 'status = "$($status.value)"; firstSeenAt = $null })' }
        @{ Name = "saved-restore-ignored-so-the-id-follows-the-earliest-member"
           Find = 'if ($null -ne $same) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-saved-restore-is-this-one"
           Find = '-and $_.windowStart -le $windowEnd -and $_.windowEnd -ge $windowStart }'
           Replace = '}' }
        @{ Name = "found-restore-not-handed-back"
           Find = 'if ($finding.state -ceq "known") { $nextKnown ='
           Replace = 'if ($false) { $nextKnown =' }
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
           Find = '-or ($_.lastChangeAt - $_.startedAt).TotalSeconds -ge $Settings.movedSeconds)'
           Replace = '-or ($_.lastChangeAt - $_.startedAt).TotalSeconds -gt 0)' }
        @{ Name = "status-not-read-so-a-first-turn-is-not-moved"
           Find = '$resting = ("$($_.status)" -ceq "idle" -and'
           Replace = '$resting = ($true -and' }
        @{ Name = "status-word-not-carried"
           Find = 'lastChangeAt = $status.observedAt; status = "$($status.value)";'
           Replace = 'lastChangeAt = $status.observedAt; status = "idle";' }
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
        @{ Name = "orcs-not-told"
           Find = 'if ($m.role -cne "orc") { continue }'
           Replace = 'if ($m.role -ceq "orc") { continue }' }
        @{ Name = "goblin-mailed"
           Find = 'if ($m.role -cne "orc") { continue }'
           Replace = 'if ($m.role -cne "orc" -and $m.role -cne "goblin") { continue }' }
        @{ Name = "goblin-mailed-once-its-orc-moved"
           Find = 'if ($m.role -cne "orc") { continue }'
           Replace = 'if ($m.role -cne "orc" -and -not $movedIds.ContainsKey($m.parent)) { continue }' }
        @{ Name = "everyone-but-the-warchief-mailed"
           Find = 'if ($m.role -cne "orc") { continue }'
           Replace = 'if ($m.role -ceq "warchief") { continue }' }
        @{ Name = "unknown-role-mailed"
           Find = 'if ($m.role -cne "orc") { continue }'
           Replace = 'if ($m.role -cne "orc" -and $m.role -cne "unknown") { continue }' }
        @{ Name = "moved-session-told-to-resume"
           Find = 'if ($m.moved) { continue }'
           Replace = '' }
        @{ Name = "stall-notice-early"
           Find = 'if ($sinceEnd -ge $Settings.stallSeconds -and $movedIds.Count -eq 0) {'
           Replace = 'if ($movedIds.Count -eq 0) {' }
        @{ Name = "stall-notice-though-something-moved"
           Find = 'if ($sinceEnd -ge $Settings.stallSeconds -and $movedIds.Count -eq 0) {'
           Replace = 'if ($sinceEnd -ge $Settings.stallSeconds) {' }
        @{ Name = "dead-session-counted-as-running"
           Find = 'if ("$($status.state)" -cne "known" -or $status.observedAt -isnot [datetime]) { continue }'
           Replace = 'if ($false) { continue }' }
        @{ Name = "partial-listing-read-as-the-fleet"
           Find = 'if ($whole.Count -eq 0) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "session-of-a-listing-not-whole-counted"
           Find = 'if ("$($of.state)" -cne "known" -or -not $whole.ContainsKey("$($of.value)")) { continue }'
           Replace = '' }
        @{ Name = "one-listing-not-whole-is-unknown"
           Find = 'if ($whole.Count -eq 0) { return'
           Replace = 'if ($leftOut.Count -gt 0) { return' }
        @{ Name = "role-guessed-from-nothing"
           Find = '$role = "unknown"'
           Replace = '$role = "goblin"' }
    )
}
