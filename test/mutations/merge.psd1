# Mutations of cli/Merge.ps1, the steps of `horde merge`. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\merge.psd1
# Each makes the command merge what it must refuse, merge the wrong way, check the wrong tree, or stay
# quiet after a merge about a step that failed; test\test-merge.ps1 must fail for every one. The suite
# makes temporary git repositories and runs no real gh, ledger or mail (measured 2026-10-16 on a
# throttled machine: about 75 s for a whole run, under both PowerShells).
@{
    Target = "cli\Merge.ps1"
    Suite  = "test\test-merge.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "task-pattern-loose"
           Find = '$script:HordeMergeTaskPattern = ''\AT-[0-9]{4,6}\z'''
           Replace = '$script:HordeMergeTaskPattern = ''\AT-[0-9]+''' }
        @{ Name = "lane-pattern-loose"
           Find = '$script:HordeMergeLanePattern = ''\A[A-Z]{1,2}([1-9][0-9]{0,3})?\z'''
           Replace = '$script:HordeMergeLanePattern = ''\A[A-Za-z0-9]{1,3}\z''' }
        @{ Name = "waiting-without-on-taken"
           Find = 'if ($State -ceq "waiting" -and $On -eq "") {'
           Replace = 'if ($false) {' }
        @{ Name = "progress-without-reason-taken"
           Find = 'if ($State -ceq "progress" -and $Reason -eq "") {'
           Replace = 'if ($false) {' }
        @{ Name = "ledger-loses-on"
           Find = 'if ("" + $Request.on -ne "") { [void]$a.Add("--on"); [void]$a.Add($Request.on) }'
           Replace = '' }
        @{ Name = "ledger-loses-reason"
           Find = 'if ("" + $Request.reason -ne "") { [void]$a.Add("--reason=" + $Request.reason) }'
           Replace = '' }
        @{ Name = "reason-split-into-two-words"
           Find = '[void]$a.Add("--reason=" + $Request.reason)'
           Replace = '[void]$a.Add("--reason"); [void]$a.Add($Request.reason)' }
        @{ Name = "hand-line-quote-not-doubled"
           Find = 'return ("''" + $Text.Replace("''", "''''") + "''")'
           Replace = 'return ("''" + $Text + "''")' }
        @{ Name = "message-loses-the-sha"
           Find = '" merged " + $Request.pr + " as " + $MergeSha + ".`n"'
           Replace = '" merged " + $Request.pr + ".`n"' }
        @{ Name = "guard-without-banner-is-green"
           Find = '$ok = ($Run.code -eq 0 -and $banner.Count -gt 0 -and $failedBanner.Count -eq 0)'
           Replace = '$ok = ($Run.code -eq 0 -and $failedBanner.Count -eq 0)' }
        @{ Name = "failures-banner-is-green"
           Find = '$ok = ($Run.code -eq 0 -and $banner.Count -gt 0 -and $failedBanner.Count -eq 0)'
           Replace = '$ok = ($Run.code -eq 0 -and $banner.Count -gt 0)' }
        @{ Name = "guard-exit-code-ignored"
           Find = '$ok = ($Run.code -eq 0 -and $banner.Count -gt 0 -and $failedBanner.Count -eq 0)'
           Replace = '$ok = ($banner.Count -gt 0 -and $failedBanner.Count -eq 0)' }
        @{ Name = "only-one-guard-runs"
           Find = '$script:HordeMergeGuards = @("test\test-host-names.ps1", "test\test-mutation-specs.ps1")'
           Replace = '$script:HordeMergeGuards = @("test\test-host-names.ps1")' }
        @{ Name = "unknown-mergeable-asked-once"
           Find = 'if ("" + $pr.mergeable -cne "UNKNOWN") { break }'
           Replace = 'break' }
        @{ Name = "closed-pr-taken"
           Find = 'if ("" + $pr.state -cne "OPEN") {'
           Replace = 'if ($false) {' }
        @{ Name = "draft-taken"
           Find = 'if ($pr.isDraft -eq $true) {'
           Replace = 'if ($false) {' }
        @{ Name = "conflicting-not-named"
           Find = 'if ("" + $pr.mergeable -ceq "CONFLICTING") {'
           Replace = 'if ($false) {' }
        @{ Name = "unknown-after-asks-taken"
           Find = 'if ("" + $pr.mergeable -cne "MERGEABLE") {'
           Replace = 'if ($false) {' }
        @{ Name = "missing-review-taken"
           Find = 'if (@("REVIEW_REQUIRED", "CHANGES_REQUESTED") -ccontains ("" + $pr.reviewDecision)) {'
           Replace = 'if (@() -ccontains ("" + $pr.reviewDecision)) {' }
        @{ Name = "changes-requested-taken"
           Find = 'if (@("REVIEW_REQUIRED", "CHANGES_REQUESTED") -ccontains ("" + $pr.reviewDecision)) {'
           Replace = 'if (@("REVIEW_REQUIRED") -ccontains ("" + $pr.reviewDecision)) {' }
        @{ Name = "moved-head-ignored"
           Find = 'if ($headSha -cne ("" + $Pr.headRefOid)) {'
           Replace = 'if ($false) {' }
        @{ Name = "head-checked-instead-of-the-merge"
           Find = '$commit = $c.out'
           Replace = '$commit = $headSha' }
        @{ Name = "conflict-not-named"
           Find = 'if ($t.code -eq 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "red-guard-ignored"
           Find = 'if (-not $read.ok) { return (& $no'
           Replace = 'if ($false) { return (& $no' }
        @{ Name = "failing-lines-not-printed"
           Find = 'foreach ($l in @($check.lines)) { & $say ("    " + $l) }'
           Replace = '' }
        @{ Name = "scratch-checkout-left"
           Find = '        Remove-HordeMergeFolder -Path $scratch -Tools $Tools'
           Replace = '' }
        @{ Name = "unreadable-ledger-not-named"
           Find = 'if ($shown.code -ne 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "unknown-task-taken"
           Find = 'if (-not $taskSeen) {'
           Replace = 'if ($false) {' }
        @{ Name = "moved-main-ignored"
           Find = 'if ($nowSha -ceq $check.base) { break }'
           Replace = 'break' }
        @{ Name = "more-rounds-than-said"
           Find = '$script:HordeMergeRounds = 3'
           Replace = '$script:HordeMergeRounds = 5' }
        @{ Name = "squash-merge"
           Find = '"--merge", "--match-head-commit", $check.head'
           Replace = '"--squash", "--match-head-commit", $check.head' }
        @{ Name = "head-not-pinned"
           Find = '"--merge", "--match-head-commit", $check.head'
           Replace = '"--merge"' }
        @{ Name = "failed-gh-merge-not-refused"
           Find = 'if (-not $isMerged -and $m.code -ne 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "ledger-failure-silent"
           Find = 'if ($lr.code -eq 0) {'
           Replace = 'if ($true) {' }
        @{ Name = "ledger-hand-line-not-printed"
           Find = '& $say ("run this by hand: " + $line)'
           Replace = '' }
        @{ Name = "tell-failure-silent"
           Find = 'if ($t.ok -eq $true) {'
           Replace = 'if ($true) {' }
        @{ Name = "mail-failure-silent"
           Find = 'if ($a.ok -eq $true) {'
           Replace = 'if ($true) {' }
        @{ Name = "analyst-never-mailed"
           Find = '$a = Invoke-HordeMergeTool -Tools $Tools -Name "Mail" -With @($message)'
           Replace = '$a = [pscustomobject]@{ ok = $true; detail = "" }' }
        @{ Name = "progress-draft-missing"
           Find = '& $say (Format-HordeMergeProgress -Request $Request -Title ("" + $pr.title))'
           Replace = '' }
        @{ Name = "ps1-program-not-run-by-powershell"
           Find = 'if ($Program -match ''\.ps1\z'') {'
           Replace = 'if ($false) {' }
        @{ Name = "base-reread-failure-ignored"
           Find = 'if ($now.code -ne 0 -or $nowSha -cnotmatch $script:HordeMergeShaPattern) {'
           Replace = 'if ($false) {' }
        @{ Name = "not-shown-merged-goes-on"
           Find = 'if (-not $isMerged) {'
           Replace = 'if ($false) {' }
        @{ Name = "refused-merge-waited-on"
           Find = 'if ($m.code -ne 0) { break }'
           Replace = '' }
        @{ Name = "head-sha-shape-unchecked"
           Find = 'if ("" + $pr.headRefOid -cnotmatch $script:HordeMergeShaPattern) {'
           Replace = 'if ($false) {' }
        @{ Name = "behind-main-branch-skipped"
           Find = 'elseif ($contains.code -eq 1) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "contains-failure-goes-on"
           Find = '    else { return (& $no ("asking git whether'
           Replace = '    else { $null = (& $no ("asking git whether' }
        @{ Name = "missing-guard-not-refused"
           Find = 'if (-not [System.IO.File]::Exists([System.IO.Path]::Combine($scratch, $g))) {'
           Replace = 'if ($false) {' }
        @{ Name = "test-home-never-a-tests"
           Find = 'return [bool]$full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)'
           Replace = 'return $false' }
        @{ Name = "unresolvable-home-not-a-tests"
           Find = '} catch { return $true }'
           Replace = '} catch { return $false }' }
        @{ Name = "landed-on-moved-main-not-seen"
           Find = 'elseif ($first -cne $check.base) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "landed-on-moved-main-not-a-problem"
           Find = '[void]$problems.Add($landed + "; run the guards on " + $pr.baseRefName + " now")'
           Replace = '' }
        @{ Name = "message-says-green-when-not-checked"
           Find = 'if ($Landed -ne "") { $checked = "NOT CHECKED: "'
           Replace = 'if ($false) { $checked = "NOT CHECKED: "' }
        @{ Name = "cmd-program-started"
           Find = 'if (Test-HordeMergeShellScript -Program $Program) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "bat-taken-for-a-program"
           Find = '''\.(cmd|bat)\z'''
           Replace = '''\.cmd\z''' }
        @{ Name = "left-over-runs-kept"
           Find = 'foreach ($old in [System.IO.Directory]::GetDirectories($runs)) { Remove-HordeMergeFolder -Path $old -Tools $Tools }'
           Replace = '' }
        @{ Name = "pr-ref-kept-in-cache"
           Find = '$null = Invoke-HordeMergeTool -Tools $Tools -Name "Git" -With @(, [string[]]@("-C", $cache, "update-ref", "-d", $prRef))'
           Replace = '' }
    )
}
