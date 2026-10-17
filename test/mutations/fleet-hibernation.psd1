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
           Find = '[System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None'
           Replace = '[System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None' }
        @{ Name = "process-not-kept"
           Find = '{ $s["process"] = [pscustomobject][ordered]@{'
           Replace = '{ $null = [pscustomobject][ordered]@{' }
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
        @{ Name = "reason-cap-too-long"
           Find = 'if ($Reason.Length -gt 600) {'
           Replace = 'if ($Reason.Length -gt 601) {' }
        @{ Name = "reason-cap-too-short"
           Find = 'if ($Reason.Length -gt 600) {'
           Replace = 'if ($Reason.Length -gt 599) {' }
        @{ Name = "reason-cut-one-too-long"
           Find = '$keep = 597;'
           Replace = '$keep = 598;' }
        @{ Name = "reason-cut-one-too-short"
           Find = '$keep = 597;'
           Replace = '$keep = 596;' }
        @{ Name = "reason-cut-splits-surrogate-pair"
           Find = 'if ([char]::IsHighSurrogate($Reason[596])) { $keep = 596 }'
           Replace = 'if ($false) { $keep = 596 }' }
        @{ Name = "reason-surrogate-checked-at-wrong-index"
           Find = '[char]::IsHighSurrogate($Reason[596])'
           Replace = '[char]::IsHighSurrogate($Reason[595])' }
        @{ Name = "unmark-asked-for-the-wrong-reason"
           Find = 'try { $a = & $HostAdapter.unmark ("" + $id) "hibernated" }'
           Replace = 'try { $a = & $HostAdapter.unmark ("" + $id) "parked" }' }
        @{ Name = "unmark-failure-unsaid"
           Find = 'if ($null -eq $a -or "" + $a.state -cne "known") { [void]$lines.Add('
           Replace = 'if ($null -eq $a -or "" + $a.state -cne "known") { continue; [void]$lines.Add(' }
        @{ Name = "unmark-asked-twice-for-one-id"
           Find = 'foreach ($id in @($Ids | Where-Object { "" + $_ -ne "" } | Select-Object -Unique)) {'
           Replace = 'foreach ($id in @($Ids | Where-Object { "" + $_ -ne "" })) {' }
        @{ Name = "unmark-throw-escapes"
           Find = 'catch { $a = New-HordeUnknown -Reason ("" + $_.Exception.Message) }'
           Replace = 'catch { throw }' }
    )
}
