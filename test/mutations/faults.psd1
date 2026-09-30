# Mutations of core/Faults.ps1, the cardinality checks the projection reports.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\faults.psd1
# One spec at a time. The spec sets HORDE_SKIP_REALITY=1 for its own runs (Environment below): the
# suite's reality check reads this machine's real stores and took past tools\Mutate.ps1's 900 s limit
# per run beside another run (2026-09-30), and a mutant must be caught by the fixture sections.
# Each breaks one check; test\test-projection.ps1 must fail for every one of them.
@{
    Target = "core\Faults.ps1"
    Suite  = "test\test-projection.ps1"
    Environment = @{ HORDE_SKIP_REALITY = "1" }
    Mutations = @(
        @{ Name = "no-warchief-never-reported"
           Find = 'elseif ($held.value -eq $false) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "two-warchiefs-never-reported"
           Find = 'if ($wc.atLeast -ge 2) {'
           Replace = 'if ($false) {' }
        @{ Name = "two-warchiefs-unknown-read-as-none"
           Find = 'else { [void]$out.Add((New-HordeFault -Kind "two-warchiefs" -Found @() -UnknownReason $wc.answer.reason)) }'
           Replace = 'else { [void]$out.Add((New-HordeFault -Kind "two-warchiefs" -Found @())) }' }
        @{ Name = "orc-judged-without-one-warchief"
           Find = 'if ($wc.answer.state -eq "known" -and $wc.answer.value -eq 1) {'
           Replace = 'if ($warchiefs.Count -ge 1) {' }
        @{ Name = "orc-parent-not-compared"
           Find = 'if ($p.state -eq "known" -and "$($p.value)" -ine $wid) {'
           Replace = 'if ($false) {' }
        @{ Name = "retired-parent-called-missing"
           Find = 'if ($prt.state -eq "known" -and [bool]$prt.value) { $retiredParent +='
           Replace = 'if ($prt.state -eq "known" -and [bool]$prt.value) { $missing +=' }
        @{ Name = "missing-parent-never-reported"
           Find = 'if (-not $C.wf.registry.unreadable.Contains($pid0)) { $missing +='
           Replace = 'if ($false) { $missing +=' }
        @{ Name = "parent-cycle-not-followed"
           Find = '$cur = "$($p.value)"'
           Replace = 'break' }
        @{ Name = "resume-duplicates-ignored"
           Find = 'if ($groups[$k].Count -gt 1) { $dupes +='
           Replace = 'if ($false) { $dupes +=' }
        @{ Name = "hook-silence-never-reported"
           Find = 'if ($claudeLive.Count -gt 0 -and $unrecorded.Count -eq $claudeLive.Count) {'
           Replace = 'if ($false) {' }
        @{ Name = "claimed-handle-not-reported"
           Find = 'foreach ($h in @($Claimed.Keys | Sort-Object)) { $hc +='
           Replace = 'foreach ($h in @()) { $hc +=' }
        @{ Name = "handle-checks-clean-without-a-host"
           Find = '$hcWhy = ""; if ($C.host.verify.state -ne "known") { $hcWhy = $C.host.verify.reason }'
           Replace = '$hcWhy = ""' }
        @{ Name = "run-ambiguity-not-reported"
           Find = 'if (@($S.runAmbiguous).Count -gt 1) { $amb +='
           Replace = 'if ($false) { $amb +=' }
        @{ Name = "pending-warchief-claim-ignored"
           Find = 'if ($pc.atLeast -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "tombstone-on-a-live-session-ignored"
           Find = '-and $S.w1Retired) { $rbr +='
           Replace = '-and $false) { $rbr +=' }
        @{ Name = "orphans-not-reported"
           Find = 'if ($op.state -eq "known") { [void]$out.Add((New-HordeFault -Kind "orphan-process" -Found @(@($op.value)'
           Replace = 'if ($op.state -eq "known") { [void]$out.Add((New-HordeFault -Kind "orphan-process" -Found @(@()' }
        @{ Name = "shared-fleet-id-ignored"
           Find = 'if ($fg[$k].Count -gt 1) { $ff +='
           Replace = 'if ($false) { $ff +=' }
        @{ Name = "shared-label-ignored"
           Find = 'if ($lg[$k].Count -gt 1) { $lf +='
           Replace = 'if ($false) { $lf +=' }
        @{ Name = "label-cycle-not-defaulted"
           Find = '$cyc = "0"; if ($cy.state -eq "known")'
           Replace = '$cyc = "none"; if ($cy.state -eq "known")' }
        @{ Name = "roster-listing-twice-not-reported"
           Find = '| Group-Object -Property id -CaseSensitive | Where-Object { $_.Count -gt 1 })) { $twice +='
           Replace = '| Group-Object -Property id -CaseSensitive | Where-Object { $false })) { $twice +=' }
        @{ Name = "other-agents-duplicates-called-none"
           Find = 'if ($why5 -eq "" -and $unread.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "non-uuid-id-not-flagged"
           Find = 'if ($S.id -cnotmatch $script:HordeUuidPattern) {'
           Replace = 'if ($false) {' }
        @{ Name = "unknown-reason-dropped"
           Find = 'elseif ($UnknownReason -ne "") { $answer = New-HordeUnknown -Reason $UnknownReason }'
           Replace = '' }
    )
}
