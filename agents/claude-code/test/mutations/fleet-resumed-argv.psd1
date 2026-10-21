# Mutations of agents/claude-code/Fleet.ps1 that a CALLER would feel (T-0320): the lots listing, the wake and the
# hibernate exit check over the real adapter. Run:
#   powershell -File tools\Mutate.ps1 -Spec agents\claude-code\test\mutations\fleet-resumed-argv.psd1
# agents\claude-code\test\test-fleet-resumed-argv.ps1 must fail a check for every one.
@{
    Target = "agents\claude-code\Fleet.ps1"
    Suite  = "agents\claude-code\test\test-fleet-resumed-argv.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "resume-argv-ignored"
           Find = 'if ($null -ne $argvPid) {'
           Replace = 'if ($false) {' }
        @{ Name = "listing-error-ignored"
           Find = 'if ($null -ne $Snapshot.PSObject.Properties["resumedError"] -and "" + $Snapshot.resumedError -ne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "listing-answer-trusted"
           Find = 'if ($null -eq $answer -or "" + $answer.state -cne "known") {'
           Replace = 'if ($false) {' }
        @{ Name = "resume-equals-form-ignored"
           Find = 'elseif ($a.StartsWith("--resume=", [System.StringComparison]::OrdinalIgnoreCase))'
           Replace = 'elseif ($false)' }
        @{ Name = "resume-short-flag-ignored"
           Find = 'if ($a -ieq "--resume" -or $a -ieq "-r") {'
           Replace = 'if ($a -ieq "--resume") {' }
        @{ Name = "id-anywhere-counts"
           Find = '{ $cand = $a.Substring(9) }'
           Replace = '{ $cand = $a.Substring(9) } elseif ($a.ToLowerInvariant() -cmatch $script:ClaudeCodeFleetIdPattern) { $cand = $a }' }
    )
}
