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
    )
}