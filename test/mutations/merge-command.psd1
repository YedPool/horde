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
           Find = 'foreach ($need in @("Pr", "Task", "State", "By")) {'
           Replace = 'foreach ($need in @("Pr", "Task", "State")) {' }
        @{ Name = "bad-request-exits-one"
           Find = 'if (-not $request.ok) { throw (New-HordeUsageError $request.why) }'
           Replace = 'if (-not $request.ok) { throw $request.why }' }
        @{ Name = "no-ledger-script-not-named"
           Find = 'if ("" + $mergeValues.ledgerScript -eq "") {'
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
    )
}
