# Mutations of cli/commands/merge.ps1, the `horde merge` command. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\merge-command.psd1
# Each makes the command take what it must refuse, exit wrongly, or leave a step unwired;
# test\test-merge.ps1, whose second part runs the real command as its own process, must fail for every one.
@{
    Target = "cli\commands\merge.ps1"
    Suite  = "test\test-merge.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "missing-by-not-named"
           Find = 'foreach ($need in $(if ($isMerge) { @("Pr", "Task", "State", "By") } else { @() })) {'
           Replace = 'foreach ($need in $(if ($isMerge) { @("Pr", "Task", "State") } else { @() })) {' }
        @{ Name = "bad-request-exits-one"
           Find = 'if (-not $request.ok) { throw (New-HordeUsageError $request.why) }'
           Replace = 'if (-not $request.ok) { throw $request.why }' }
        @{ Name = "no-ledger-script-not-named"
           Find = 'if ($isMerge -and "" + $mergeValues.ledgerScript -eq "") {'
           Replace = 'if ($false) {' }
        @{ Name = "analyst-mail-not-written"
           Find = '(Write-HordeAnalystMail -Folder $folder -Text $Text -Markers $policy.markers)'
           Replace = '"not written"' }
        @{ Name = "refused-exits-zero"
           Find = '"refused" { throw ("refused, nothing merged: " + $done.why) }'
           Replace = '"refused" { Write-Output ("refused, nothing merged: " + $done.why) }' }
        @{ Name = "unfinished-exits-zero"
           Find = 'default { throw ("MERGED, NOT FINISHED: " + $done.why) }'
           Replace = 'default { Write-Output ("MERGED, NOT FINISHED: " + $done.why) }' }
        @{ Name = "cmd-setting-not-refused"
           Find = 'if (Test-HordeMergeShellScript -Program ("" + $mergeValues.$prog)) {'
           Replace = 'if ($false) {' }
        @{ Name = "merge-lock-not-waited-for"
           Find = 'try { $held = $lock.WaitOne(0) }'
           Replace = 'try { $held = $true }' }
        @{ Name = "runowed-takes-a-pull-request"
           Find = 'foreach ($no in @("Pr", "Task", "State", "By", "On", "Reason", "Guards", "Base", "Guard")) {'
           Replace = 'foreach ($no in @("Task")) {' }
        @{ Name = "json-without-runowed-taken"
           Find = '} elseif ($PSBoundParameters.ContainsKey("Repo") -or $Json) {'
           Replace = '} elseif ($false) {' }
        @{ Name = "runowed-json-not-printed"
           Find = 'if ($Json) { Write-Output $owedRun.json }'
           Replace = '' }
        @{ Name = "runowed-red-exits-zero"
           Find = 'if ($owedRun.exit -ne 0) { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "daytime-merge-takes-the-lock"
           Find = '$needLock = ($RunOwed -or $ClearRed -or $request.guards -ceq "now")'
           Replace = '$needLock = $true' }
        @{ Name = "command-default-is-now"
           Find = '[string]$Guards = "later",'
           Replace = '[string]$Guards = "now",' }
        @{ Name = "clearred-takes-no-reason"
           Find = 'foreach ($need in @("Repo", "Base", "Guard", "Reason")) {'
           Replace = 'foreach ($need in @("Repo", "Base", "Guard")) {' }
        @{ Name = "clearred-with-runowed-taken"
           Find = 'if ($RunOwed -and $ClearRed) { throw (New-HordeUsageError "merge -RunOwed and merge -ClearRed are two commands; give one") }'
           Replace = 'if ($false) { throw (New-HordeUsageError "merge -RunOwed and merge -ClearRed are two commands; give one") }' }
        @{ Name = "clearred-refusal-exits-zero"
           Find = 'if (-not $cleared.ok) { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "runowed-takes-a-guard-flag"
           Find = '"Reason", "Guards", "Base", "Guard")) {'
           Replace = '"Reason", "Guards")) {' }
    )
}
