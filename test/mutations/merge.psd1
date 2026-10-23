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
        @{ Name = "guard-list-not-read-from-the-tree"
           Find = 'if ([System.IO.File]::Exists($listFile)) { $treeText = [System.IO.File]::ReadAllText($listFile) }'
           Replace = '' }
        @{ Name = "guards-the-base-lists-dropped"
           Find = '$guards = @(Join-HordeGuardLists -Tree $treeGuards -Base $baseGuards)'
           Replace = '$guards = @(Join-HordeGuardLists -Tree $treeGuards -Base $null)' }
        @{ Name = "guards-the-tree-adds-dropped"
           Find = '$guards = @(Join-HordeGuardLists -Tree $treeGuards -Base $baseGuards)'
           Replace = '$guards = @(Join-HordeGuardLists -Tree @() -Base $baseGuards)' }
        @{ Name = "base-list-not-read"
           Find = 'if ($baseHas.out -ne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "unusable-tree-list-not-refused"
           Find = 'if (-not $treeRead.ok) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "unusable-base-list-not-refused"
           Find = 'if (-not $baseRead.ok) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "no-list-anywhere-taken"
           Find = 'if ($guards.Count -eq 0) { return (& $no'
           Replace = 'if ($false) { return (& $no' }
        @{ Name = "guards-run-in-one-shell-only"
           Find = 'foreach ($sh in (Get-HordeGuardShells)) {'
           Replace = 'foreach ($sh in @((Get-HordeGuardShells)[0])) {' }
        @{ Name = "red-in-second-shell-ignored"
           Find = 'if (-not $read.ok) { return (& $no ("the guard " + $g + " is red on " + $commit.Substring(0, 8) + " in " + $sh.label'
           Replace = 'if (-not $read.ok -and $sh.key -ceq "5.1") { return (& $no ("the guard " + $g + " is red on " + $commit.Substring(0, 8) + " in " + $sh.label' }
        @{ Name = "shell-7-runs-the-5-1-program"
           Find = '$program = $shell7'
           Replace = '$program = $shell' }
        @{ Name = "missing-pwsh7-not-red"
           Find = 'if (-not [System.IO.File]::Exists($program)) { return [pscustomobject]@{ code = -1;'
           Replace = 'if ($false) { return [pscustomobject]@{ code = -1;' }
        @{ Name = "unknown-shell-taken"
           Find = 'elseif ($Which -cne "5.1") { return'
           Replace = 'elseif ($false) { return' }
        @{ Name = "machine-module-path-not-given"
           Find = '$env1 = & $guardEnvFor -Shell $Which -MachinePsModulePath ("" + $machinePath)'
           Replace = '$env1 = @{}' }
        @{ Name = "environment-not-set-on-the-child"
           Find = 'foreach ($k in @($Environment.Keys)) { $psi.EnvironmentVariables[[string]$k] = "" + $Environment[$k] }'
           Replace = '' }
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
           Find = '& $say (Format-HordeMergeProgress -Request $Request -Title ("" + $pr.title) -GuardsOwed:($check.skipped -eq $true) -NotQueued:(-not $queued))'
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
           Find = 'elseif ($check.skipped -ne $true -and $first -cne $check.base) {'
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
        @{ Name = "daytime-default-is-now"
           Find = '[string]$Reason = "", [string]$Guards = "later")'
           Replace = '[string]$Reason = "", [string]$Guards = "now")' }
        @{ Name = "daytime-still-runs-guards"
           Find = 'while (-not ($Request.guards -ceq "later")) {'
           Replace = 'while ($true) {' }
        @{ Name = "daytime-merge-not-queued"
           Find = 'else { $ow = Invoke-HordeMergeTool -Tools $Tools -Name "Owed" -With @($owedLine) }'
           Replace = 'else { $ow = [pscustomobject]@{ ok = $true; detail = "" } }' }
        @{ Name = "daytime-queue-failure-silent"
           Find = '[void]$problems.Add("the merge was not queued for the nightly guards run; add this line to guards-owed.jsonl: " + $hand)'
           Replace = '' }
        @{ Name = "daytime-queue-failure-says-queued"
           Find = '& $say ("THE MERGE HAPPENED, BUT IT WAS NOT QUEUED FOR THE NIGHTLY GUARDS RUN: " + $ow.detail)'
           Replace = '& $say "guards not run: queued for the nightly run (guards-owed.jsonl)"' }
        @{ Name = "daytime-tell-claims-green"
           Find = 'if ($Check.skipped -eq $true) { return ("HORDE MERGE: "'
           Replace = 'if ($false) { return ("HORDE MERGE: "' }
        @{ Name = "daytime-progress-silent-about-owed"
           Find = 'if ($GuardsOwed) { $line += "; guards owed to the nightly run" }'
           Replace = '' }
        @{ Name = "owed-line-loses-first-parent"
           Find = 'headSha = $HeadSha; mergeSha = $MergeSha; firstParent = $FirstParent }'
           Replace = 'headSha = $HeadSha; mergeSha = $MergeSha; firstParent = "" }' }
        @{ Name = "owed-line-appended-over-the-file"
           Find = '[System.IO.File]::AppendAllText($Path, ($prefix + $Line + "`n"), (New-Object System.Text.UTF8Encoding($false)))'
           Replace = '[System.IO.File]::WriteAllText($Path, ($prefix + $Line + "`n"), (New-Object System.Text.UTF8Encoding($false)))' }
        @{ Name = "nightly-names-the-last-red-merge"
           Find = '$item.lines = @($step.lines); $found = $true; break }'
           Replace = '$item.lines = @($step.lines); $found = $true }' }
        @{ Name = "nightly-skips-the-baseline"
           Find = 'if ($bl.red) { $item.note ='
           Replace = 'if ($false) { $item.note =' }
        @{ Name = "nightly-red-in-one-shell-only"
           Find = 'if (-not $read.ok) { $shells += $sh.label;'
           Replace = 'if (-not $read.ok -and $sh.key -ceq "5.1") { $shells += $sh.label;' }
        @{ Name = "nightly-checked-not-marked"
           Find = '$ap = Add-HordeMergeLine -Path $checkedPath -Line $l'
           Replace = '$ap = [pscustomobject]@{ ok = $true; detail = "" }' }
        @{ Name = "nightly-checked-merges-run-again"
           Find = 'if ($checked.ContainsKey($e.mergeSha)) { continue }'
           Replace = '' }
        @{ Name = "nightly-red-exits-zero"
           Find = 'if ($anyRed) { $code = 1 }'
           Replace = '' }
        @{ Name = "nightly-bad-line-ignored"
           Find = 'if ($owed.bad.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "nightly-unwalkable-merge-walked-anyway"
           Find = 'if ($h.code -eq 0) { [void]$walk.Add($e); continue }'
           Replace = '[void]$walk.Add($e); continue' }
        @{ Name = "nightly-unwalkable-merge-stops-the-rest"
           Find = '[void]$skipped.Add([pscustomobject]@{ entry = $e;'
           Replace = 'return (& $err "a merge is not in the history"); [void]$skipped.Add([pscustomobject]@{ entry = $e;' }
        @{ Name = "owed-line-base-not-recorded"
           Find = 'baseRefName = $BaseRef; pr = $Request.pr;'
           Replace = 'baseRefName = ""; pr = $Request.pr;' }
        @{ Name = "owed-line-repo-case-kept"
           Find = 'repo = ($Request.owner + "/" + $Request.repo).ToLowerInvariant();'
           Replace = 'repo = ($Request.owner + "/" + $Request.repo);' }
        @{ Name = "tell-says-queued-when-it-was-not"
           Find = 'if ($Check.skipped -eq $true -and $NotQueued) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "progress-says-owed-when-not-queued"
           Find = 'if ($GuardsOwed -and $NotQueued) {'
           Replace = 'if ($false) {' }
        @{ Name = "queue-line-glued-onto-unterminated-line"
           Find = 'if ($fs.ReadByte() -ne 10) { $prefix = "`n" }'
           Replace = 'if ($false) { $prefix = "`n" }' }
        @{ Name = "nightly-guard-list-from-the-tip-only"
           Find = 'foreach ($g in $baseGuards) {'
           Replace = 'foreach ($g in @()) {' }
        @{ Name = "nightly-guard-not-run-counted-red"
           Find = 'if (-not $read.ok -and -not $read.ran) { return (& $no ('
           Replace = 'if ($false) { return (& $no (' }
        @{ Name = "guard-result-always-ran"
           Find = 'ran = ($Run.code -ne -1);'
           Replace = 'ran = $true;' }
        @{ Name = "nightly-red-not-run-again"
           Find = 'if (-not $read.ok -and $read.ran) {'
           Replace = 'if ($false) {' }
        @{ Name = "nightly-walk-runs-every-shell"
           Find = '$step = Invoke-HordeMergeGuardAt -Tools $Tools -Scratch $scratch -Commit $e.mergeSha -Guard $g -ShellKeys $tipKeys'
           Replace = '$step = Invoke-HordeMergeGuardAt -Tools $Tools -Scratch $scratch -Commit $e.mergeSha -Guard $g' }
        @{ Name = "nightly-deleted-guard-script-not-blamed"
           Find = 'if ($step.absent -and $present) {'
           Replace = 'if ($false) {' }
        @{ Name = "nightly-branch-ignored"
           Find = 'if ($e.base -ne "") { $b = $e.base }'
           Replace = '' }
        @{ Name = "nightly-report-failure-still-marks"
           Find = 'if (-not $wrote.ok) {'
           Replace = 'if ($false) {' }
        @{ Name = "nightly-repo-filter-case-sensitive"
           Find = '$e.repo -cne $Repo.ToLowerInvariant()'
           Replace = '$e.repo -cne $Repo' }
        @{ Name = "nightly-damaged-line-fails-the-run"
           Find = 'if ($unchecked -gt 0 -and -not $anyChecked -and $worst -lt 2) { $worst = 2 }'
           Replace = 'if ($unchecked -gt 0 -and $worst -lt 2) { $worst = 2 }' }
        @{ Name = "nightly-queued-twice-walked-twice"
           Find = 'if ($seen.ContainsKey($v["mergeSha"])) { continue }'
           Replace = '' }
        @{ Name = "nightly-report-silent-about-the-machine"
           Find = '[void]$text.Add("queue: " + $owedPath + " on " + [Environment]::MachineName + " - this machine''s queue only; merges made on another machine are in that machine''s queue and are not covered by this report")'
           Replace = '' }
        @{ Name = "nightly-repo-dot-dot-taken"
           Find = 'return [bool]($m.Success -and $m.Groups[2].Value -cne "." -and $m.Groups[2].Value -cne "..")'
           Replace = 'return [bool]$m.Success' }
        @{ Name = "nightly-report-not-written"
           Find = '$wrote = Add-HordeMergeLine -Path $reportPath -Line (($text -join "`n") + "`n")'
           Replace = '$wrote = [pscustomobject]@{ ok = $true; detail = "" }' }
    )
}
