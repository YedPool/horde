# Mutations of wakers/wezfleet/Waker.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\waker-wezfleet.psd1
# Each breaks one thing the fleet's waker exists for - the mapping, one of the six rules of its header,
# the nudge's outcomes, or where the fleet is found; test\test-waker-wezfleet.ps1 must fail for every one.
@{
    Target = "wakers\wezfleet\Waker.ps1"
    Suite  = "test\test-waker-wezfleet.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-wezfleet-that-does-not-know-the-verb-reserves-nothing"
           Find = 'answered = $false; why = ("wezfleet labels reserved exit " + $run.exit'
           Replace = 'answered = $true; labels = @(); why = ("wezfleet labels reserved exit " + $run.exit' }
        @{ Name = "a-fleet-command-that-cannot-be-run-reserves-nothing"
           Find = 'answered = $false; why = ("wezfleet labels reserved could not be run: "'
           Replace = 'answered = $true; labels = @(); why = ("wezfleet labels reserved could not be run: "' }
        @{ Name = "a-non-zero-exit-is-read-for-its-list"
           Find = '    $read = Read-HordeWezfleetWakerJson -Run $run -What "wezfleet labels reserved"'
           Replace = '    $run.exit = 0; $read = Read-HordeWezfleetWakerJson -Run $run -What "wezfleet labels reserved"' }
        @{ Name = "any-schema-is-read-as-the-reserved-labels"
           Find = 'if ($null -eq $schema -or $schema.Value -isnot [string] -or $schema.Value -cne "wezfleet.labels.reserved" -or $null -eq $version'
           Replace = 'if ($null -eq $version' }
        @{ Name = "any-version-of-the-reserved-labels-is-read"
           Find = '-or -not ($version.Value -is [int] -or $version.Value -is [long]) -or $version.Value -ne 1) { return'
           Replace = ') { return' }
        @{ Name = "a-label-that-is-no-text-is-listed"
           Find = 'if ($l -isnot [string] -or $l.Trim() -eq "") { return (New-HordeUnknown -Reason "wezfleet labels reserved exit 0 listed something that is not a label"'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason "wezfleet labels reserved exit 0 listed something that is not a label"' }
        @{ Name = "the-fleets-reserved-labels-are-not-asked-for"
           Find = '    -Reserved { Get-HordeWezfleetWakerReservedLabels } `'
           Replace = '' }
        @{ Name = "a-nudge-reason-never-seen-is-an-error"
           Find = 'if ($null -ne $rp -and $rp.Value -is [string]) { $code = ConvertTo-HordeWezfleetWakerLine $rp.Value -Max 80 }'
           Replace = 'if ($null -ne $rp -and $rp.Value -is [string]) { if (@("", "woken", "mid-turn", "status-unreadable", "pointer-stale", "sender-busy", "box-not-empty", "no-unread-mail", "retired", "budget-too-small", "no-pane") -cnotcontains $rp.Value) { return (New-HordeUnknown -Reason "a reason this waker does not know") }; $code = ConvertTo-HordeWezfleetWakerLine $rp.Value -Max 80 }' }
        @{ Name = "a-row-reason-never-seen-is-an-error"
           Find = 'foreach ($k in $script:HordeWezfleetWakerRowMembers) { if ($names -cnotcontains $k) { return ("a row has no ''" + $k + "''") } }'
           Replace = 'if (@("", "mail-unreadable", "record-unreadable", "mid-turn", "status-unreadable") -cnotcontains "$($Row.reason)") { return "a row has a reason this waker does not know" }; foreach ($k in $script:HordeWezfleetWakerRowMembers) { if ($names -cnotcontains $k) { return ("a row has no ''" + $k + "''") } }' }
        @{ Name = "a-nudge-reason-is-not-cut-short"
           Find = '$code = ConvertTo-HordeWezfleetWakerLine $rp.Value -Max 80 }'
           Replace = '$code = ConvertTo-HordeWezfleetWakerLine $rp.Value -Max 8000 }' }
        @{ Name = "an-outcome-never-seen-is-taken-for-woken"
           Find = 'return (New-HordeUnknown -Reason ($said + " answered without an outcome this waker reads'
           Replace = 'return (New-HordeKnown -Value ([pscustomobject]@{ id = $Id; outcome = "woken"; reason = ""; at = $at }) -ObservedAt $at); return (New-HordeUnknown -Reason ($said + " answered without an outcome this waker reads' }
        @{ Name = "an-outcome-in-another-casing-is-read"
           Find = '-or @($script:HordeWezfleetWakerOutcomes.Keys) -cnotcontains $outcome.Value) {'
           Replace = '-or -not $script:HordeWezfleetWakerOutcomes.ContainsKey($outcome.Value)) {' }
        @{ Name = "the-fleets-rule-is-not-passed-on"
           Find = 'if ($null -ne $ruled -and $ruled.Value -is [string] -and $ruled.Value.Trim() -ne "") { $answer["rule"] ='
           Replace = 'if ($false) { $answer["rule"] =' }
        @{ Name = "an-older-rows-betweenturns-reads-as-no"
           Find = '    $between = "unknown"'
           Replace = '    $between = "no"' }
        @{ Name = "an-older-rows-acked-reads-as-known"
           Find = '    $acked = "unknown"'
           Replace = '    $acked = "known"' }
        @{ Name = "a-time-beside-acked-unknown-is-read"
           Find = 'if ($acked -ceq "known" -and $null -ne $p) { $lastAcked = ConvertTo-HordeWezfleetWakerTime $p.Value }'
           Replace = 'if ($null -ne $p) { $lastAcked = ConvertTo-HordeWezfleetWakerTime $p.Value }' }
        @{ Name = "an-older-rows-handed-over-count-reads-as-none"
           Find = '    $handed = $null'
           Replace = '    $handed = 0' }
        @{ Name = "a-betweenturns-that-is-no-word-is-accepted"
           Find = 'if ($names -ccontains "betweenTurns" -and ($Row.betweenTurns -isnot [string] -or $script:HordeWezfleetWakerWords -cnotcontains $Row.betweenTurns)) { return "a row''s betweenTurns is not yes, no or unknown" }'
           Replace = '' }
        @{ Name = "an-acked-that-is-no-word-is-accepted"
           Find = 'if ($names -ccontains "acked" -and ($Row.acked -isnot [string] -or @("known", "unknown") -cnotcontains $Row.acked)) { return "a row''s acked is not known or unknown" }'
           Replace = '' }
        @{ Name = "a-handed-over-count-that-is-no-count-is-accepted"
           Find = '(($Row.handedOverCount -is [int] -or $Row.handedOverCount -is [long]) -and $Row.handedOverCount -ge 0)) { return'
           Replace = '($false)) { return' }
        @{ Name = "betweenturns-is-not-carried"
           Find = 'betweenTurns = $later.betweenTurns; acked = $later.acked;'
           Replace = 'betweenTurns = "no"; acked = $later.acked;' }
        @{ Name = "what-was-acknowledged-is-not-carried"
           Find = 'acked = $later.acked; lastAckedAt = $later.lastAckedAt;'
           Replace = 'acked = $later.acked; lastAckedAt = $null;' }
        @{ Name = "what-was-handed-over-is-not-carried"
           Find = 'handedOverCount = $later.handedOverCount;'
           Replace = 'handedOverCount = $null;' }
        @{ Name = "a-time-with-no-zone-is-read-as-local"
           Find = 'if ([datetime]::TryParse($Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed) -and $parsed.Kind -ne [System.DateTimeKind]::Unspecified) { return $parsed.ToUniversalTime() }'
           Replace = 'if ([datetime]::TryParse($Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) { return $parsed.ToUniversalTime() }' }
        @{ Name = "the-commands-paths-are-kept-in-a-reason"
           Find = 'if ($Tool) { $clean = [regex]::Replace('
           Replace = 'if ($false) { $clean = [regex]::Replace(' }
        @{ Name = "three-hundred-characters-of-the-commands-words"
           Find = '$script:HordeWezfleetWakerDetailChars = 120'
           Replace = '$script:HordeWezfleetWakerDetailChars = 300' }
        @{ Name = "a-failing-reads-detail-is-not-cleaned"
           Find = '{ $detail = ConvertTo-HordeWezfleetWakerLine $d.Value -Max $script:HordeWezfleetWakerDetailChars -Tool }'
           Replace = '{ $detail = ConvertTo-HordeWezfleetWakerLine $d.Value -Max $script:HordeWezfleetWakerDetailChars }' }
        @{ Name = "output-that-is-not-json-is-not-cleaned"
           Find = 'printed something that is not JSON: " + (ConvertTo-HordeWezfleetWakerLine $lines[0] -Max $script:HordeWezfleetWakerDetailChars -Tool)'
           Replace = 'printed something that is not JSON: " + (ConvertTo-HordeWezfleetWakerLine $lines[0])' }
        @{ Name = "a-nudge-cut-for-printing-too-much-is-unreachable"
           Find = 'if ($null -ne $cut -and $cut.Value -eq $true) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "a-command-found-on-path-is-called-named"
           Find = 'fixed = [bool]$choice.fixed; how ='
           Replace = 'fixed = $true; how =' }
        @{ Name = "the-root-setting-is-not-called-named"
           Find = 'return (New-HordeWezfleetWakerChoice -Root $s.values.root -How ("set as root in " + $s.path) -Fixed) }'
           Replace = 'return (New-HordeWezfleetWakerChoice -Root $s.values.root -How ("set as root in " + $s.path)) }' }
        @{ Name = "a-row-that-does-not-say-reads-as-not-limited"
           Find = '        $word = "unknown"'
           Replace = '        $word = "no"' }
        @{ Name = "limited-no-is-read-as-unknown"
           Find = 'if ($null -ne $p -and $p.Value -ceq "no") { $word = "no" }'
           Replace = '' }
        @{ Name = "limited-yes-is-read-as-no"
           Find = 'return [pscustomobject]@{ limited = "yes"; limitedUntil = $until }'
           Replace = 'return [pscustomobject]@{ limited = "no"; limitedUntil = $until }' }
        @{ Name = "retired-true-read-as-no"
           Find = 'if ($Row.retired -eq $true) { return "yes" }'
           Replace = '' }
        @{ Name = "an-unreadable-record-reads-as-not-retired"
           Find = 'if (@($said) -ccontains "record-unreadable") { return "unknown" }'
           Replace = '' }
        @{ Name = "a-row-with-nothing-of-a-record-reads-as-not-retired"
           Find = 'if ("$($Row.label)" -ceq "" -and (ConvertTo-HordeWezfleetWakerRole $Row.role) -ceq "unknown") { return "unknown" }'
           Replace = '' }
        @{ Name = "a-row-with-no-label-alone-is-unknown"
           Find = 'if ("$($Row.label)" -ceq "" -and (ConvertTo-HordeWezfleetWakerRole $Row.role) -ceq "unknown") { return "unknown" }'
           Replace = 'if ("$($Row.label)" -ceq "") { return "unknown" }' }
        @{ Name = "the-listing-says-nobody-is-retired"
           Find = 'reachable = $row.reachable; retired = (Get-HordeWezfleetWakerRetired -Row $row) })'
           Replace = 'reachable = $row.reachable; retired = "no" })' }
        @{ Name = "a-reset-with-no-zone-is-read-as-local"
           Find = '[ref]$parsed) -and $parsed.Kind -ne [System.DateTimeKind]::Unspecified) { $until = $parsed.ToUniversalTime() }'
           Replace = '[ref]$parsed)) { $until = $parsed.ToUniversalTime() }' }
        @{ Name = "a-limited-that-is-no-word-accepted"
           Find = 'if ($names -ccontains "limited" -and ($Row.limited -isnot [string] -or $script:HordeWezfleetWakerWords -cnotcontains $Row.limited)) { return "a row''s limited is not yes, no or unknown" }'
           Replace = '' }
        @{ Name = "a-limitedUntil-that-is-no-time-accepted"
           Find = 'if ($names -ccontains "limitedUntil" -and $null -ne $Row.limitedUntil -and $Row.limitedUntil -isnot [string] -and $Row.limitedUntil -isnot [datetime]) { return "a row''s limitedUntil is neither a time nor null" }'
           Replace = '' }
        @{ Name = "retired-session-with-no-mail-is-a-target"
           Find = 'if ($row.retired -and -not $hasMail) { continue }'
           Replace = '' }
        @{ Name = "retired-session-with-mail-dropped"
           Find = 'if ($row.retired -and -not $hasMail) { continue }'
           Replace = 'if ($row.retired) { continue }' }
        @{ Name = "unknown-role-guessed-a-warg"
           Find = 'is [string]) { return $script:HordeWezfleetWakerRoles[$Word] }'
           Replace = 'is [string]) { return $script:HordeWezfleetWakerRoles[$Word] }; if ($true) { return "warg" }' }
        @{ Name = "master-read-as-an-orc"
           Find = '$script:HordeWezfleetWakerRoles = @{ "master" = "warchief"; "orchestrator" = "orc"; "session" = "warg" }'
           Replace = '$script:HordeWezfleetWakerRoles = @{ "master" = "orc"; "orchestrator" = "orc"; "session" = "warg" }' }
        @{ Name = "every-state-reads-a-pane"
           Find = '    if ($Full) {'
           Replace = '    if ($true) {' }
        @{ Name = "the-full-reading-reads-no-pane"
           Find = '    if ($Full) {'
           Replace = '    if ($false) {' }
        @{ Name = "fleet-asked-on-every-call"
           Find = '($now - $kept.at).TotalSeconds -lt $script:HordeWezfleetWakerFleetLifeSeconds) { return $kept.answer }'
           Replace = '$false) { return $kept.answer }' }
        @{ Name = "one-answer-kept-for-ever"
           Find = '($now - $kept.at).TotalSeconds -lt $script:HordeWezfleetWakerFleetLifeSeconds) { return $kept.answer }'
           Replace = '$true) { return $kept.answer }' }
        @{ Name = "answer-stamped-when-the-call-was-made"
           Find = '$script:HordeWezfleetWakerFleet = [pscustomobject]@{ at = (Get-HordeWezfleetWakerTime); answer = $answer }'
           Replace = '$script:HordeWezfleetWakerFleet = [pscustomobject]@{ at = $now; answer = $answer }' }
        @{ Name = "a-pass-beginning-keeps-the-last-reading"
           Find = '-Begin { Clear-HordeWezfleetWakerPass }'
           Replace = '-Begin { }' }
        @{ Name = "rule-1-a-row-with-a-reason-distrusted"
           Find = 'if ($Row.mail -cne "known") {'
           Replace = 'if ($Row.mail -cne "known" -or "$($Row.reason)" -cne "") {' }
        @{ Name = "rule-2-null-unread-count-read-as-none"
           Find = 'if ($null -eq $Row.unreadCount) { return'
           Replace = 'if ($null -eq $Row.unreadCount) { $Row.unreadCount = 0 }; if ($false) { return' }
        @{ Name = "rule-2-null-unreadable-count-read-as-none"
           Find = 'if ($null -eq $Row.unreadableCount) { return'
           Replace = 'if ($null -eq $Row.unreadableCount) { $Row.unreadableCount = 0 }; if ($false) { return' }
        @{ Name = "rule-2-unreadable-mail-read-as-known"
           Find = 'if ($Row.mail -cne "known") {'
           Replace = 'if ($false) {' }
        @{ Name = "time-with-no-zone-read-as-local"
           Find = '[ref]$parsed) -and $parsed.Kind -ne [System.DateTimeKind]::Unspecified) { $oldest = $parsed.ToUniversalTime() }'
           Replace = '[ref]$parsed)) { $oldest = $parsed.ToUniversalTime() }' }
        @{ Name = "rule-3-failing-read-repeated-every-call"
           Find = 'if ($fail.count -gt 0 -and $now -lt $fail.nextAt) { return [pscustomobject]@{ ok = $false; rows = $null; reason = $fail.reason } }'
           Replace = '' }
        @{ Name = "rule-3-failures-in-a-row-not-said"
           Find = '-Name "failures" -Value ([int]$script:HordeWezfleetWakerFleetFailures.count)'
           Replace = '-Name "failures" -Value 0' }
        @{ Name = "rule-3-back-off-never-grows"
           Find = 'return [int]$steps[[System.Math]::Min($Failures, $steps.Count) - 1]'
           Replace = 'return [int]$steps[0]' }
        @{ Name = "rule-3-back-off-not-reset-by-success"
           Find = 'if ($answer.ok) { $script:HordeWezfleetWakerFleetFailures = @{ count = 0; nextAt = [datetime]::MinValue; reason = "" } }'
           Replace = 'if ($false) { }' }
        @{ Name = "rule-3-reason-code-not-first"
           Find = 'return ($code + ": " + $Said + $(if ($detail -ne "") { ": " + $detail } else { "" }))'
           Replace = 'return ($Said + ": " + $code + $(if ($detail -ne "") { ": " + $detail } else { "" }))' }
        @{ Name = "rule-3-non-zero-exit-read-as-an-answer"
           Find = 'if ([int]$run.exit -ne 0) { return [pscustomobject]@{ ok = $false; rows = $null; reason = (Get-HordeWezfleetWakerFailure'
           Replace = 'if ($false) { return [pscustomobject]@{ ok = $false; rows = $null; reason = (Get-HordeWezfleetWakerFailure' }
        @{ Name = "rule-3-pane-failure-read-again-at-once"
           Find = 'if ($now -lt $fail.nextAt) { return [pscustomobject]@{ ok = $false; row = $null; reason = $fail.reason } }'
           Replace = '' }
        @{ Name = "rule-4-pane-deadline-not-three-times-its-flag"
           Find = '-DeadlineSeconds (3 * $flag)'
           Replace = '-DeadlineSeconds (300 * $flag)' }
        @{ Name = "rule-4-timeout-not-named"
           Find = 'reason = ("timed-out: the fleet''s command did not answer within "'
           Replace = 'reason = ("the fleet''s command did not answer within "' }
        @{ Name = "snapshot-with-no-time-limit"
           Find = 'CreationDate -OperationTimeoutSec $script:HordeWezfleetWakerSnapshotSeconds -ErrorAction Stop'
           Replace = 'CreationDate -ErrorAction Stop'
           Expect = "survives"
           Reason = "no suite can make the real process table slow; the limit is the cmdlet's own parameter, and the case it guards is played by Set-HordeWezfleetWakerSnapshotFault" }
        @{ Name = "no-list-said-as-no-descendants"
           Find = 'if (-not $listed) { $also ='
           Replace = 'if ($false) { $also =' }
        @{ Name = "rule-5-two-lines-read-as-one"
           Find = 'if ($lines.Count -ne 1) {'
           Replace = 'if ($lines.Count -lt 1) {' }
        @{ Name = "rule-5-row-shape-not-checked"
           Find = 'foreach ($k in $script:HordeWezfleetWakerRowMembers) { if ($names -cnotcontains $k) { return ("a row has no ''" + $k + "''") } }'
           Replace = '' }
        @{ Name = "rule-5-word-outside-the-three-accepted"
           Find = 'if ($script:HordeWezfleetWakerWords -cnotcontains $Row.$k) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "rule-5-session-listed-twice-accepted"
           Find = 'if ($rows.Contains($row.id)) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "pane-answer-about-another-session-accepted"
           Find = 'elseif ($p.Value.id -cne $Id) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "rule-6-unreadable-count-dropped"
           Find = 'unreadableCount = $Row.unreadableCount; oldestUnreadAt = $oldest'
           Replace = 'unreadableCount = 0; oldestUnreadAt = $oldest' }
        @{ Name = "refused-read-as-busy"
           Find = '"unreachable" = "unreachable"; "refused" = "nothing" }'
           Replace = '"unreachable" = "unreachable"; "refused" = "busy" }' }
        @{ Name = "nudge-about-another-session-read-as-this-one"
           Find = '-and $target.Value -cne "" -and $target.Value -cne $Id) { return (New-HordeUnknown'
           Replace = '-and $false) { return (New-HordeUnknown' }
        @{ Name = "failed-nudge-read-as-woken"
           Find = 'return (New-HordeKnown -Value ([pscustomobject]@{ id = $Id; outcome = "unreachable"; reason = $why; at = $at }) -ObservedAt $at)'
           Replace = 'return (New-HordeKnown -Value ([pscustomobject]@{ id = $Id; outcome = "woken"; reason = $why; at = $at }) -ObservedAt $at)' }
        @{ Name = "nudge-sent-without-its-budget"
           Find = '@("mail", "nudge", "-To", $Id, "-BudgetSeconds", ("" + $budget), "-Json")'
           Replace = '@("mail", "nudge", "-To", $Id, "-Json")' }
        @{ Name = "nudge-killed-at-its-budget"
           Find = '("" + $budget), "-Json") -DeadlineSeconds (3 * $budget)'
           Replace = '("" + $budget), "-Json") -DeadlineSeconds $budget' }
        @{ Name = "killed-nudge-read-as-unreachable"
           Find = 'if ($run.timedOut) { return (New-HordeKnown -Value ([pscustomobject]@{ id = $Id; outcome = "killed";'
           Replace = 'if ($run.timedOut) { return (New-HordeKnown -Value ([pscustomobject]@{ id = $Id; outcome = "unreachable";' }
        @{ Name = "old-tool-not-said-to-be-old"
           Find = 'if ($run.ok) { $why = $tooOld + $why }'
           Replace = '' }
        @{ Name = "nudge-budget-of-thirty"
           Find = '$script:HordeWezfleetWakerNudgeBudget = 60'
           Replace = '$script:HordeWezfleetWakerNudgeBudget = 30' }
        @{ Name = "elapsed-time-dropped"
           Find = '-and $took.Value -ge 0) { $answer["elapsedMs"] = [long]$took.Value }'
           Replace = '-and $false) { $answer["elapsedMs"] = [long]$took.Value }' }
        @{ Name = "outcome-with-no-reason-left-blank"
           Find = 'if ($why -eq "" -and $mapped -cne "woken") { $why = "the fleet answered " + $outcome.Value }'
           Replace = '' }
        @{ Name = "path-asked-though-the-settings-are-refused"
           Find = 'if ($s.state -cne "defaults" -and $s.state -cne "read") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "path-wins-over-the-setting"
           Find = 'if ("$($s.values.root)" -ne "") { return (New-HordeWezfleetWakerChoice -Root $s.values.root -How ("set as root in " + $s.path) -Fixed) }'
           Replace = '' }
        @{ Name = "folder-with-dot-dot-accepted"
           Find = '-or @($dir -split ''[\\/]'') -contains "..") {'
           Replace = ') {' }
    )
}
