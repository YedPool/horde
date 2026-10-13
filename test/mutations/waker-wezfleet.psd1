# Mutations of wakers/wezfleet/Waker.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\waker-wezfleet.psd1
# Each breaks one thing the fleet's waker exists for - the mapping, one of the six rules of its header,
# the nudge's outcomes, or where the fleet is found; test\test-waker-wezfleet.ps1 must fail for every one.
@{
    Target = "wakers\wezfleet\Waker.ps1"
    Suite  = "test\test-waker-wezfleet.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "retired-session-with-no-mail-is-a-target"
           Find = 'if ($row.retired -and -not $hasMail) { continue }'
           Replace = '' }
        @{ Name = "retired-session-with-mail-dropped"
           Find = 'if ($row.retired -and -not $hasMail) { continue }'
           Replace = 'if ($row.retired) { continue }' }
        @{ Name = "unknown-role-guessed-a-goblin"
           Find = 'is [string]) { return $script:HordeWezfleetWakerRoles[$Word] }'
           Replace = 'is [string]) { return $script:HordeWezfleetWakerRoles[$Word] }; if ($true) { return "goblin" }' }
        @{ Name = "master-read-as-an-orc"
           Find = '$script:HordeWezfleetWakerRoles = @{ "master" = "warchief"; "orchestrator" = "orc"; "session" = "goblin" }'
           Replace = '$script:HordeWezfleetWakerRoles = @{ "master" = "orc"; "orchestrator" = "orc"; "session" = "goblin" }' }
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
           Find = 'paneFlag = 5; nudgeBudget = 60 }'
           Replace = 'paneFlag = 5; nudgeBudget = 30 }' }
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
           Find = 'if ("$($s.values.root)" -ne "") { return (New-HordeWezfleetWakerChoice -Root $s.values.root -How ("set as root in " + $s.path)) }'
           Replace = '' }
        @{ Name = "folder-with-dot-dot-accepted"
           Find = '-or @($dir -split ''[\\/]'') -contains "..") {'
           Replace = ') {' }
    )
}
