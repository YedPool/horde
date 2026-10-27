# Mutations of core/NightlyNet.ps1, the decisions of the nightly net. Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\nightly-net.psd1
@{
    Target = "core\NightlyNet.ps1"
    Suite  = "test\test-nightly-net.ps1"
    Mutations = @(
        @{ Name = "window-opens-an-hour-late"
           Find = 'return ($m -ge $StartHour * 60 -or $m -lt $end)'
           Replace = 'return ($m -ge ($StartHour + 1) * 60 -or $m -lt $end)' }
        @{ Name = "window-never-closes-in-the-morning"
           Find = 'return ($m -ge $StartHour * 60 -or $m -lt $end)'
           Replace = 'return ($m -ge $StartHour * 60 -or $m -le $end)' }
        @{ Name = "deadline-always-tomorrow"
           Find = '    if ($Now -lt $today) { return $today }'
           Replace = '    if ($false) { return $today }' }
        @{ Name = "run-may-overrun-the-cutoff"
           Find = 'return ($Now.AddSeconds($RunSeconds) -le $Cutoff)'
           Replace = 'return ($Now -le $Cutoff)' }
        @{ Name = "double-quote-kept"
           Find = '$t = $t.Replace(''"'', "''").Replace(";", ",")'
           Replace = '$t = $t.Replace(";", ",")' }
        @{ Name = "semicolon-kept"
           Find = '.Replace(";", ",")'
           Replace = '' }
        @{ Name = "angle-brackets-kept"
           Find = '.Replace("<", "(").Replace(">", ")")'
           Replace = '' }
        @{ Name = "owed-entry-of-another-repo-taken"
           Find = 'if ($Repo -ne "" -and $r -ne "" -and $r -ine $Repo) { continue }'
           Replace = '' }
        @{ Name = "bad-owed-line-not-counted"
           Find = 'if ($null -eq $o -or $o -isnot [pscustomobject]) { $bad++; continue }'
           Replace = 'if ($null -eq $o -or $o -isnot [pscustomobject]) { continue }' }
        @{ Name = "pr-not-read-from-the-subject"
           Find = 'if ($pr -eq "") { $m = [regex]::Match'
           Replace = 'if ($false) { $m = [regex]::Match' }
        @{ Name = "owed-label-ignored"
           Find = 'source = "owed"'
           Replace = 'source = "git"; $hit = $null' }
        @{ Name = "still-red-bisected-as-new"
           Find = 'if ($was -ceq "green") { $newly += $u } elseif ($was -ceq "red") { $still += $u } else { $new += $u }'
           Replace = 'if ($was -ceq "red") { $newly += $u } elseif ($was -ceq "green") { $still += $u } else { $new += $u }' }
        @{ Name = "no-verdict-counted-as-newly-red"
           Find = 'if ($was -ceq "green") { $newly += $u }'
           Replace = 'if ($was -ceq "green" -or $was -ceq "") { $newly += $u }' }
        @{ Name = "unrun-counted-as-red-or-green"
           Find = 'if ($v -ceq "unrun") { $unrun += $u; continue }'
           Replace = 'if ($false) { $unrun += $u; continue }' }
        @{ Name = "tip-not-checked-first"
           Find = '    if (-not $r) { return [pscustomobject]@{ state = "flaky"'
           Replace = '    if ($false) { return [pscustomobject]@{ state = "flaky"' }
        @{ Name = "bisect-picks-the-wrong-side"
           Find = '        if ($r) { $hi = $mid } else { $lo = $mid }'
           Replace = '        if ($r) { $lo = $mid } else { $hi = $mid }' }
        @{ Name = "unreadable-run-taken-as-green"
           Find = '        if ($null -eq $r) { return [pscustomobject]@{ state = "inconclusive"; sha = ""; runs = $runs; between = @($(if ($lo -ge 0)'
           Replace = '        if ($false) { return [pscustomobject]@{ state = "inconclusive"; sha = ""; runs = $runs; between = @($(if ($lo -ge 0)' }
        @{ Name = "run-cap-ignored"
           Find = '        if ($runs -ge $MaxRuns) { return'
           Replace = '        if ($false) { return' }
        @{ Name = "culprit-off-by-one"
           Find = 'return [pscustomobject]@{ state = "found"; sha = $m[$hi]'
           Replace = 'return [pscustomobject]@{ state = "found"; sha = $m[[math]::Max(0, $hi - 1)]' }
        @{ Name = "still-red-not-in-report"
           Find = '        foreach ($u in @($c.stillRed | Select-Object -First 15)) {'
           Replace = '        foreach ($u in @()) {' }
        @{ Name = "incomplete-night-not-said"
           Find = '        if ($r.incomplete) {'
           Replace = '        if ($false) {' }
        @{ Name = "guards-process-exit-2-not-could-not-run"
           Find = 'if ($ProcessExit -ne 0 -and $ProcessExit -ne 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "guards-json-exit-ignored"
           Find = '    if ($e -eq 1) { return [pscustomobject]@{ code = 1; state = "RED"; text = $text } }'
           Replace = '    if ($e -eq 1) { return [pscustomobject]@{ code = 0; state = "green"; text = $text } }' }
        @{ Name = "guards-json-exit-2-read-as-red"
           Find = '    if ($e -eq 2) { return [pscustomobject]@{ code = 2;'
           Replace = '    if ($e -eq 2) { return [pscustomobject]@{ code = 1;' }
        @{ Name = "guards-missing-json-taken-as-green"
           Find = '-not $o.PSObject.Properties["exit"]) { return [pscustomobject]@{ code = 2; state = "could not run"; text = "no -Json last line to read" } }'
           Replace = '-not $o.PSObject.Properties["exit"]) { return [pscustomobject]@{ code = 0; state = "green"; text = "no -Json last line to read" } }' }
        @{ Name = "guards-unknown-exit-value-taken-as-green"
           Find = '    return [pscustomobject]@{ code = 2; state = "could not run"; text = ("the -Json exit field is " + $e'
           Replace = '    return [pscustomobject]@{ code = 0; state = "green"; text = ("the -Json exit field is " + $e' }
        @{ Name = "guards-text-exit-field-accepted"
           Find = 'if ($e -isnot [int] -and $e -isnot [long]) {'
           Replace = 'if ($false) {' }
        @{ Name = "skip-keeps-a-stored-green"
           Find = 'if ($Verdict -ceq "skip" -or $Verdict -ceq "skipped") { if ($Previous -ceq "red") { return "" } return "skip" }'
           Replace = 'if ($Verdict -ceq "skip" -or $Verdict -ceq "skipped") { if ($Previous -ceq "red" -or $Previous -ceq "green") { return "" } return "skip" }' }
        @{ Name = "skip-clears-a-stored-red"
           Find = 'if ($Verdict -ceq "skip" -or $Verdict -ceq "skipped") { if ($Previous -ceq "red") { return "" } return "skip" }'
           Replace = 'if ($Verdict -ceq "skip" -or $Verdict -ceq "skipped") { return "skip" }' }
        @{ Name = "tell-exit-6-not-told"
           Find = 'if ($c -eq 0 -or $c -eq 6) { return "told" }'
           Replace = 'if ($c -eq 0) { return "told" }' }
        @{ Name = "unconfirmed-tell-resent"
           Find = 'if ($c -eq 2) { return "unconfirmed" }'
           Replace = '' }
        @{ Name = "tell-not-retried"
           Find = 'for ($try = 1; $try -le [math]::Max(1, $Tries); $try++) {'
           Replace = 'for ($try = 1; $try -le 1; $try++) {' }
        @{ Name = "untold-findings-dropped"
           Find = 'else { foreach ($f in @($Findings)) {'
           Replace = 'elseif ($false) { foreach ($f in @($Findings)) {' }
        @{ Name = "pending-not-cleared-when-told"
           Find = 'if ($Told) { $pending = @() }'
           Replace = '' }
        @{ Name = "pending-not-in-report"
           Find = 'if ($r.PSObject.Properties["pending"]) {'
           Replace = 'if ($false) {' }
        @{ Name = "timeout-at-tip-is-unrun"
           Find = 'if ($c -eq 124) { if ($AtTip) { return "hung" } return "unrun" }'
           Replace = 'if ($c -eq 124) { return "unrun" }' }
        @{ Name = "timeout-in-bisect-is-hung"
           Find = 'if ($c -eq 124) { if ($AtTip) { return "hung" } return "unrun" }'
           Replace = 'if ($c -eq 124) { return "hung" }' }
        @{ Name = "hung-counted-as-unrun"
           Find = 'if ($v -ceq "hung") { $hung += $u; continue }'
           Replace = 'if ($v -ceq "hung") { $unrun += $u; continue }' }
        @{ Name = "hung-not-in-report"
           Find = 'foreach ($u in @($c.hung)) { $lines += ("HUNG "'
           Replace = 'foreach ($u in @()) { $lines += ("HUNG "' }
        @{ Name = "process-time-limit-ignored"
           Find = 'if (-not $p.WaitForExit([math]::Max(1, $TimeoutSeconds) * 1000)) {'
           Replace = '$p.WaitForExit(); if ($false) {' }
        @{ Name = "argument-with-space-not-quoted"
           Find = 'if ($Arg -notmatch ''[\s"]'') { return $Arg }'
           Replace = 'return $Arg' }
        @{ Name = "missing-exit-code-read-as-green"
           Find = 'if ($null -eq $Run.code -or "" + $Run.code -eq "") { return "red" }'
           Replace = '' }
        @{ Name = "skip-in-bisect-is-green"
           Find = 'if ($Verdict -ceq "green" -or $Verdict -ceq "absent") { return $false }'
           Replace = 'if ($Verdict -ceq "green" -or $Verdict -ceq "absent" -or $Verdict -ceq "skip") { return $false }' }
        @{ Name = "no-report-reserve"
           Find = '.AddMinutes(-[math]::Max(0, $ReportReserveMinutes))'
           Replace = '' }
        @{ Name = "unnamed-bisect-still-complete"
           Find = 'if ($unnamed -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "memory-give-up-not-short"
           Find = 'if (Test-HordeNightlyMemoryGiveUp -Gate $Gate) { return $true }'
           Replace = 'if (Test-HordeNightlyMemoryGiveUp -Gate $Gate) { return $Short }' }
        @{ Name = "short-wait-never-ends"
           Find = 'heavy-slot: running '') { return $false }'
           Replace = 'heavy-slot: running '') { return $Short }' }
        @{ Name = "short-wait-not-used"
           Find = 'if ($MemoryShort) { return [math]::Min($Normal, $Short) }'
           Replace = 'if ($false) { return [math]::Min($Normal, $Short) }' }
        @{ Name = "commit-give-up-not-memory"
           Find = '(free memory|commit headroom)'
           Replace = '(free memory)' }
        @{ Name = "unrun-counted-as-run"
           Find = 'if ($v -cne "unrun" -and $v -cne "skipped") { $n++ }'
           Replace = 'if ($v -cne "skipped") { $n++ }' }
        @{ Name = "skipped-counted-as-run"
           Find = 'if ($v -cne "unrun" -and $v -cne "skipped") { $n++ }'
           Replace = 'if ($v -cne "unrun") { $n++ }' }
        @{ Name = "skipped-stored-as-given"
           Find = 'if ($Verdict -ceq "skip" -or $Verdict -ceq "skipped") { if ($Previous -ceq "red") { return "" } return "skip" }'
           Replace = 'if ($Verdict -ceq "skip") { if ($Previous -ceq "red") { return "" } return "skip" } if ($Verdict -ceq "skipped") { return "green" }' }
        @{ Name = "needs-read-past-the-header"
           Find = 'if (-not $t.StartsWith("#")) { break }'
           Replace = 'if (-not $t.StartsWith("#")) { continue }' }
        @{ Name = "malformed-need-read-as-nothing"
           Find = 'if (-not $m.Success) { $needs += "malformed"; continue }'
           Replace = 'if (-not $m.Success) { continue }' }
        @{ Name = "need-with-no-probe-taken-as-met"
           Find = 'if ($null -eq $p) { $why += ("needs " + $n + ", which no probe answers"); continue }'
           Replace = 'if ($null -eq $p) { continue }' }
        @{ Name = "probe-no-taken-as-met"
           Find = 'if ($p.ok -eq $true) { continue }'
           Replace = 'if ($true) { continue }' }
        @{ Name = "probe-yes-still-skips"
           Find = 'if ($p.ok -eq $true) { continue }'
           Replace = 'if ($false) { continue }' }
        @{ Name = "skipped-compared-as-unrun"
           Find = 'if ($v -ceq "skipped") { $skipped += $u; continue }'
           Replace = 'if ($v -ceq "skipped") { $unrun += $u; continue }' }
        @{ Name = "skipped-line-dropped"
           Find = 'foreach ($w in @($groups.Keys)) { $lines += ("  SKIPPED " + (@($groups[$w]) -join ", ") + " - " + $w) }'
           Replace = 'foreach ($w in @()) { }' }
        @{ Name = "skipped-headline-dropped"
           Find = 'if ($skipped -gt 0) { $t += " SKIPPED: "'
           Replace = 'if ($false) { $t += " SKIPPED: "' }
        @{ Name = "repos-not-ordered-by-units"
           Find = '@{ Expression = { $c[$_] } }, '
           Replace = '' }
        @{ Name = "memory-line-dropped"
           Find = 'if ($null -ne $Memory -and [int]$Memory.giveUps -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "holders-not-read"
           Find = '$out += [pscustomobject]@{ name = $m.Groups[1].Value;'
           Replace = 'if ($false) { } $null = [pscustomobject]@{ name = $m.Groups[1].Value;' }
    )
}