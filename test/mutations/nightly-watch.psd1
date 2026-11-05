# Mutations of core/NightlyNet.ps1's missed-run watcher deciding (T-0397). Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\nightly-watch.psd1
# Each breaks one rule of the watcher; test\test-nightly-watch.ps1 must fail a named check for every one of them.
@{
    Target = "core\NightlyNet.ps1"
    Suite  = "test\test-nightly-watch.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "night-is-two-days-back"
           Find = '    $night = $Now.Date.AddDays(-1)'
           Replace = '    $night = $Now.Date.AddDays(-2)' }
        @{ Name = "early-morning-judges-the-running-night"
           Find = '    if ($Now -lt $Now.Date.AddHours($EndHour).AddMinutes($EndMinute)) { $night = $night.AddDays(-1) }'
           Replace = '' }
        @{ Name = "dates-skip-every-other-day"
           Find = '$d.AddDays(-$i).ToString('
           Replace = '$d.AddDays(-2 * $i).ToString(' }
        @{ Name = "boundary-minute-dropped"
           Find = '.AddHours($Hour).AddMinutes($Minute).ToString('
           Replace = '.AddHours($Hour).ToString(' }
        @{ Name = "missing-task-is-fine"
           Find = 'return @("the scheduled task is missing or could not be read")'
           Replace = 'return @()' }
        @{ Name = "disabled-task-is-fine"
           Find = '{ $found += "the scheduled task is disabled" }'
           Replace = '{ }' }
        @{ Name = "no-trigger-is-fine"
           Find = 'if ($triggers.Count -eq 0) { $found += "the scheduled task has no trigger" }'
           Replace = '' }
        @{ Name = "disabled-trigger-is-fine"
           Find = '{ $found += "a trigger of the scheduled task is disabled" }'
           Replace = '{ }' }
        @{ Name = "offset-boundary-is-fine"
           Find = '-match ''(Z|[+-]\d\d:?\d\d)$'''
           Replace = '-match ''(Q)$''' }
        @{ Name = "positive-offset-is-fine"
           Find = '-match ''(Z|[+-]\d\d:?\d\d)$'''
           Replace = '-match ''(Z|-\d\d:?\d\d)$''' }
        @{ Name = "sent-line-from-the-next-night"
           Find = '            if ([regex]::IsMatch($lines[$i], $header)) { break }'
           Replace = '' }
        @{ Name = "closed-line-counts-as-a-start"
           Find = 'if ($m.Groups[2].Value -ceq "open") { $openAt = $i } else { $closed = $true }'
           Replace = '$openAt = $i' }
        @{ Name = "other-nights-lines-count"
           Find = 'if (-not $m.Success -or $m.Groups[1].Value -cne $Date) { continue }'
           Replace = 'if (-not $m.Success) { continue }' }
        @{ Name = "unsent-report-is-ran"
           Find = 'if ($sent) { $status = "RAN";'
           Replace = 'if ($true) { $status = "RAN";' }
        @{ Name = "failed-file-ignored"
           Find = 'elseif ($haveFailed) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "busy-file-ignored"
           Find = 'elseif ($haveBusy) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "started-without-report-ignored"
           Find = 'elseif ($openAt -ge 0) { $status = "NOT REPORTED";'
           Replace = 'elseif ($false) { $status = "NOT REPORTED";' }
        @{ Name = "refused-file-ignored"
           Find = 'elseif ($closed -or $haveRefused) {'
           Replace = 'elseif ($closed) {' }
        @{ Name = "closed-line-ignored"
           Find = 'elseif ($closed -or $haveRefused) {'
           Replace = 'elseif ($haveRefused) {' }
        @{ Name = "missing-folder-unsaid"
           Find = 'if ($FolderMissing) { $detail += " (the work folder does not exist)" }'
           Replace = 'if ($false) { }' }
        @{ Name = "incomplete-night-is-a-miss"
           Find = 'missed = ($status -cne "RAN"); detail'
           Replace = 'missed = ($status -cne "RAN" -or $inc); detail' }
        @{ Name = "incomplete-never-noted"
           Find = 'if ($im.Success) { $inc = $true;'
           Replace = 'if ($false) { $inc = $true;' }
        @{ Name = "streak-counts-past-a-ran-night"
           Find = 'foreach ($v in @($Verdicts)) { if (-not $v.missed) { break }; $n++ }'
           Replace = 'foreach ($v in @($Verdicts)) { if ($v.missed) { $n++ } }' }
        @{ Name = "task-finding-is-no-problem"
           Find = '$problem = ($Verdict.missed -or $findings.Count -gt 0)'
           Replace = '$problem = ($Verdict.missed)' }
        @{ Name = "recovery-never-said"
           Find = 'elseif ($State.problem) { $sig = "recovered|"'
           Replace = 'elseif ($false) { $sig = "recovered|"' }
        @{ Name = "undelivered-alarm-is-duplicate"
           Find = '$State.signature -ceq $sig -and $State.delivered)'
           Replace = '$State.signature -ceq $sig)' }
        @{ Name = "alarm-signature-without-date"
           Find = '$sig = "alarm|" + $Verdict.date + "|" + $Verdict.status'
           Replace = '$sig = "alarm|" + $Verdict.status' }
        @{ Name = "alarm-not-remembered-as-a-problem"
           Find = 'if ($Decision.kind -ceq "alarm") { $s.problem = $true; '
           Replace = 'if ($Decision.kind -ceq "alarm") { ' }
        @{ Name = "failed-recovery-clears-the-problem"
           Find = 'if ($Delivered) { $s.problem = $false; $s.streak = 0 }'
           Replace = '$s.problem = $false; $s.streak = 0' }
        @{ Name = "streak-unsaid"
           Find = 'if ($Decision.streak -gt 1) {'
           Replace = 'if ($Decision.streak -gt 99) {' }
        @{ Name = "phone-told-the-note"
           Find = '    elseif ($Decision.kind -ceq "note") { $lines += ("NIGHTLY WATCH " + $date + ": the night ran.") }'
           Replace = '    elseif ($Decision.kind -ceq "note") { $lines += ("NIGHTLY WATCH " + $date + ": the night ran."); $phone = "note" }' }
        @{ Name = "phone-says-not-run-for-a-night-that-ran"
           Find = '"NOT TOLD" { "Nightly tests ran on the night of "'
           Replace = '"NOT TOLD" { "Nightly tests did not run for the night of "' }
        @{ Name = "phone-says-not-run-for-a-night-that-started"
           Find = '"NOT REPORTED" { "Nightly tests started on the night of "'
           Replace = '"NOT REPORTED" { "Nightly tests did not run for the night of "' }
        @{ Name = "boot-before-the-run-is-a-restart"
           Find = 'if ($boot -ge $runStart -and $boot -le $winEnd) {'
           Replace = 'if ($boot -le $winEnd) {' }
        @{ Name = "boot-after-the-window-is-a-restart"
           Find = 'if ($boot -ge $runStart -and $boot -le $winEnd) {'
           Replace = 'if ($boot -ge $runStart) {' }
        @{ Name = "phone-ignores-the-restart"
           Find = '-and "" + $Verdict.rebootAt -ne "")'
           Replace = '-and $false)' }
        @{ Name = "all-failed-when-any-failed"
           Find = 'allFailed = ($results.Count -gt 0 -and $okCount -eq 0)'
           Replace = 'allFailed = ($okCount -lt $results.Count)' }
        @{ Name = "nothing-attempted-is-all-failed"
           Find = 'allFailed = ($results.Count -gt 0 -and $okCount -eq 0)'
           Replace = 'allFailed = ($okCount -eq 0)' }
        @{ Name = "later-channel-skipped-after-a-failure"
           Find = 'try { $ok = ((& $ch.send $results) -eq $true) }'
           Replace = 'if ($results.Values -contains $false) { $results[$ch.name] = $false; continue }; try { $ok = ((& $ch.send $results) -eq $true) }' }
    )
}
