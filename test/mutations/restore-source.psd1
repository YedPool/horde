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
           Find = 'if ($Shadow) { $nextPosted[$mail.messageId] = $Now;'
           Replace = 'if ($false) { $nextPosted[$mail.messageId] = $Now;' }
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
           Find = 'if ($Saved.windowStart -gt $WindowEnd -or $Saved.windowEnd -lt $WindowStart) { return $false }'
           Replace = '' }
        @{ Name = "a-window-alone-makes-it-the-same-restore"
           Find = 'return ($present -gt 0 -and ($unchanged * 2) -gt $present)'
           Replace = 'return $true' }
        @{ Name = "one-unchanged-member-makes-it-the-same-restore"
           Find = 'return ($present -gt 0 -and ($unchanged * 2) -gt $present)'
           Replace = 'return ($present -gt 0 -and $unchanged -gt 0)' }
        @{ Name = "every-member-must-be-unchanged"
           Find = 'return ($present -gt 0 -and ($unchanged * 2) -gt $present)'
           Replace = 'return ($present -gt 0 -and $unchanged -eq $present)' }
        @{ Name = "restore-with-no-member-left-is-the-same"
           Find = 'return ($present -gt 0 -and ($unchanged * 2) -gt $present)'
           Replace = 'return (($unchanged * 2) -ge $present)' }
        @{ Name = "second-restore-in-the-same-minute-shares-the-id"
           Find = 'if (@(@($Known) | Where-Object { $null -ne $_ -and "$($_.restoreId)" -ceq $restoreId }).Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "member-starts-not-saved"
           Find = 'if ($null -ne $held -and $held.Value -is [System.Collections.IDictionary]) { $row["members"] ='
           Replace = 'if ($false) { $row["members"] =' }
        @{ Name = "found-restore-not-handed-back"
           Find = 'if ($finding.state -ceq "known") { $nextKnown ='
           Replace = 'if ($false) { $nextKnown =' }
        @{ Name = "shadow-state-written-where-live-reads"
           Find = 'Write-HordeWakeFile -Path (Get-HordeWakeStateFile -Name $Name -Shadow:$Shadow -Mode $Mode -HordeHome $HordeHome) -Text'
           Replace = 'Write-HordeWakeFile -Path (Get-HordeWakeStateFile -Name $Name -Mode $Mode -HordeHome $HordeHome) -Text' }
        @{ Name = "posted-ids-never-dropped"
           Find = 'if (($Now - $when).TotalSeconds -le $Settings.restoreMaxAgeSeconds) { $nextPosted["$k"] = $when }'
           Replace = '$nextPosted["$k"] = $when' }
        @{ Name = "saved-restores-never-dropped"
           Find = '-and $_.windowEnd -is [datetime] -and ($Now - $_.windowEnd).TotalSeconds -le $Settings.restoreMaxAgeSeconds })'
           Replace = '})' }
        @{ Name = "any-status-change-is-a-move"
           Find = '$late = ($_.lastChangeAt -is [datetime] -and ($_.lastChangeAt - $_.startedAt).TotalSeconds -ge $Settings.movedSeconds)'
           Replace = '$late = ($_.lastChangeAt -is [datetime] -and ($_.lastChangeAt - $_.startedAt).TotalSeconds -gt 0)' }
        @{ Name = "moved-seconds-back-to-a-minute"
           Find = 'movedSeconds = 30'
           Replace = 'movedSeconds = 60' }
        @{ Name = "busy-session-not-moved"
           Find = 'if ("$($_.status)" -ceq "busy") { $moved = "yes" }'
           Replace = 'if ($false) { $moved = "yes" }' }
        @{ Name = "idle-session-in-no-turn-read-as-neither"
           Find = '{ $moved = $(if ($late) { "yes" } else { "no" }) }'
           Replace = '{ $moved = $(if ($late) { "yes" } else { "neither" }) }' }
        @{ Name = "waiting-since-its-start-read-as-moved"
           Find = 'elseif ("$($_.status)" -ceq "waiting" -and $late) { $moved = "yes" }'
           Replace = 'elseif ("$($_.status)" -ceq "waiting") { $moved = "yes" }' }
        @{ Name = "ended-session-read-as-moved"
           Find = '$moved = "neither"'
           Replace = '$moved = "yes"' }
        @{ Name = "neither-read-as-not-moved"
           Find = '$moved = "neither"'
           Replace = '$moved = "no"' }
        @{ Name = "neither-suppresses-the-stall-notice"
           Find = 'if ($m.moved -ceq "yes") { $movedIds[$m.id] = $true }'
           Replace = 'if ($m.moved -cne "no") { $movedIds[$m.id] = $true }' }
        @{ Name = "session-that-is-neither-mailed"
           Find = 'if ($m.moved -cne "no") { continue }'
           Replace = 'if ($m.moved -ceq "yes") { continue }' }
        @{ Name = "moved-session-told-to-resume"
           Find = 'if ($m.moved -cne "no") { continue }'
           Replace = '' }
        @{ Name = "no-settle-time"
           Find = 'if ($sinceEnd -lt $Settings.restoreSettleSeconds) { continue }'
           Replace = '' }
        @{ Name = "settle-time-of-a-minute"
           Find = 'restoreSettleSeconds = 120'
           Replace = 'restoreSettleSeconds = 60' }
        @{ Name = "resume-mail-does-not-say-it-is-automated"
           Find = 'resumeText = "AUTOMATED, from the restore source: START OR RESTORE.'
           Replace = 'resumeText = "START OR RESTORE.' }
        @{ Name = "stall-notice-does-not-say-it-is-automated"
           Find = 'stallText = "AUTOMATED, from the restore source: STALLED'
           Replace = 'stallText = "STALLED' }
        @{ Name = "mail-wears-a-label-a-session-may-have"
           Find = 'fromLabel = "RS"'
           Replace = 'fromLabel = "R"' }
        @{ Name = "resume-mail-not-from-the-restore-source"
           Find = '-From $script:HordeRestoreSourceFrom -Label "$($Settings.fromLabel)"'
           Replace = '-From "" -Label "$($Settings.fromLabel)"' }
        @{ Name = "resume-mail-wears-a-fixed-label"
           Find = '-From $script:HordeRestoreSourceFrom -Label "$($Settings.fromLabel)"'
           Replace = '-From $script:HordeRestoreSourceFrom -Label "RS"' }
        @{ Name = "restore-minimum-ignored"
           Find = 'if ($best.Count -lt $Settings.restoreMinSessions) {'
           Replace = 'if ($false) {' }
        @{ Name = "restore-window-a-day-long"
           Find = '$until = $from.AddSeconds($Settings.restoreWindowSeconds)'
           Replace = '$until = $from.AddSeconds(86400)' }
        @{ Name = "old-restore-still-planned"
           Find = 'if (($Now - $windowEnd).TotalSeconds -gt $Settings.restoreMaxAgeSeconds) {'
           Replace = 'if ($false) {' }
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
        @{ Name = "warg-mailed"
           Find = 'if ($m.role -cne "orc") { continue }'
           Replace = 'if ($m.role -cne "orc" -and $m.role -cne "warg") { continue }' }
        @{ Name = "warg-mailed-once-its-orc-moved"
           Find = 'if ($m.role -cne "orc") { continue }'
           Replace = 'if ($m.role -cne "orc" -and -not $movedIds.ContainsKey($m.parent)) { continue }' }
        @{ Name = "everyone-but-the-warchief-mailed"
           Find = 'if ($m.role -cne "orc") { continue }'
           Replace = 'if ($m.role -ceq "warchief") { continue }' }
        @{ Name = "unknown-role-mailed"
           Find = 'if ($m.role -cne "orc") { continue }'
           Replace = 'if ($m.role -cne "orc" -and $m.role -cne "unknown") { continue }' }
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
           Replace = '$role = "warg"' }
        @{ Name = "duplicates-not-in-the-share-denominator"
           Find = '$denominator = $lived.Count + $UncountedDuplicates'
           Replace = '$denominator = $lived.Count' }
        @{ Name = "duplicates-make-up-the-minimum"
           Find = 'if ($lived.Count -lt $Settings.restoreMinSessions) { return'
           Replace = 'if (($lived.Count + $UncountedDuplicates) -lt $Settings.restoreMinSessions) { return' }
        @{ Name = "stall-notice-while-a-duplicate-lasts"
           Find = '-and $movedIds.Count -eq 0 -and $dupes -gt 0) {'
           Replace = '-and $movedIds.Count -eq 0 -and $false) {' }
        @{ Name = "held-stall-not-journaled"
           Find = 'if ($mail.kind -ceq "stall-held") {'
           Replace = 'if ($false) {' }
        @{ Name = "duplicate-only-listing-still-blinds-the-source"
           Find = 'elseif ($dupOnly -is [System.Collections.IDictionary]'
           Replace = 'elseif ($false -and $dupOnly -is [System.Collections.IDictionary]' }
        @{ Name = "another-fault-beside-a-duplicate-counted-whole"
           Find = '-and $dupOnly["$agent"] -eq $true) { $whole["$agent"] = $true }'
           Replace = ') { $whole["$agent"] = $true }' }
        @{ Name = "duplicates-not-carried-in-the-answer"
           Find = '-Name "duplicates" -Value $dupes.ToArray()'
           Replace = '-Name "duplicates" -Value @()' }
        @{ Name = "uncounted-duplicates-not-handed-to-the-finding"
           Find = '-Known $Known -UncountedDuplicates $UncountedDuplicates'
           Replace = '-Known $Known' }
    )
}
