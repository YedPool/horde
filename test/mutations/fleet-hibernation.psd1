# Mutations of fleet/Hibernation.ps1, the hibernation record. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-hibernation.psd1
# Each breaks one rule of what is recorded or how; test\test-fleet-record.ps1 must fail a check for every one.
@{
    Target = "fleet\Hibernation.ps1"
    Suite  = "test\test-fleet-record.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "retired-recorded"
           Find = 'if ($retired.state -eq "known" -and $retired.value -eq $true) { continue }'
           Replace = 'if ($false) { continue }' }
        @{ Name = "master-recorded-by-all"
           Find = 'return { param($candidates) @(@($candidates) | Where-Object { -not (Test-HordeFleetMaster -Candidate $_) }) }'
           Replace = 'return { param($candidates) @($candidates) }' }
        @{ Name = "warchief-role-not-master"
           Find = ' -or ("" + $Candidate.role) -ceq "warchief"'
           Replace = '' }
        @{ Name = "unknown-label-dropped"
           Find = 'if ($hit.Count -eq 0) { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "incomplete-registry-read"
           Find = 'if ($Registry.complete.state -ne "known") { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "empty-registry-read"
           Find = 'if ($Registry.records.Count -eq 0) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "unreadable-liveness-read"
           Find = 'if ("" + $v.kind -ceq "reading") { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "unknown-liveness-recorded"
           Find = 'if ("" + $v.state -cne "running") {'
           Replace = 'if ($false) {' }
        @{ Name = "empty-selection-written"
           Find = 'if ($chosen.Count -eq 0) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "exclude-ignored"
           Find = '$chosen = @($chosen | Where-Object { $drop -cnotcontains ("" + $_.label) })'
           Replace = '$chosen = @($chosen)' }
        @{ Name = "same-second-merged"
           Find = 'if (Test-Path -LiteralPath $dir) { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "non-ascii-written"
           Find = 'if ([int]$ch -gt 126) {'
           Replace = 'if ($false) {' }
        @{ Name = "parked-file-guessed"
           Find = 'if ([bool](& $ParkedExists $pf)) {'
           Replace = 'if ($true) {' }
        @{ Name = "duplicate-session-kept"
           Find = 'if (-not $seen.Add("" + $s.sessionId)) {'
           Replace = 'if ($false) {' }
        @{ Name = "empty-record-accepted"
           Find = 'if (@($Record.sessions).Count -eq 0) { [void]$out.Add('
           Replace = 'if ($false) { [void]$out.Add(' }
        @{ Name = "missing-role-guessed"
           Find = 'if ($r.role.state -ne "known") { return "other" }'
           Replace = 'if ($r.role.state -ne "known") { return "warg" }' }
    )
}
