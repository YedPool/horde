# Mutations of core/Idle.ps1, the idle port.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\idle-port.psd1
# Each breaks one guarantee of the port; test\test-idle-port.ps1 must fail for every one.
@{
    Target = "core\Idle.ps1"
    Suite  = "test\test-idle-port.ps1"
    Mutations = @(
        @{ Name = "missing-field-accepted"
           Find = 'foreach ($k in $script:HordeTurnStateFields) { if (-not $Fields.ContainsKey($k)) { throw ("a turn state needs the field ''" + $k + "''") } }'
           Replace = '$null = 0' }
        @{ Name = "extra-field-accepted"
           Find = 'foreach ($k in @($Fields.Keys)) { if ($script:HordeTurnStateFields -cnotcontains $k) { throw ("a turn state has no field ''" + $k + "''") } }'
           Replace = '$null = 0' }
        @{ Name = "bare-value-accepted"
           Find = 'if (-not (Test-HordeAnswer $a)) { throw ("the turn state''s ''" + $k + "'' must be an answer") }'
           Replace = '$null = 0' }
        @{ Name = "non-utc-time-accepted"
           Find = 'return ($Answer.value.Kind -eq [System.DateTimeKind]::Utc)'
           Replace = 'return $true' }
        @{ Name = "negative-count-accepted"
           Find = 'if (($v -isnot [int] -and $v -isnot [long]) -or $v -lt 0) {'
           Replace = 'if ($v -isnot [int] -and $v -isnot [long]) {' }
        @{ Name = "failed-reader-is-known"
           Find = 'catch { return (New-HordeUnknown -Reason ("the " + $Harness + " idle reader failed on " + (Split-Path -Leaf $Path)) -ErrorRecord $_) }'
           Replace = 'catch { return (New-HordeKnown -Value "failed") }' }
        @{ Name = "not-a-turn-state-accepted"
           Find = 'if ($one.Count -ne 1 -or $one[0] -isnot [psobject] -or $one[0].PSObject.TypeNames -notcontains "Horde.TurnState") {'
           Replace = 'if ($false) {' }
        @{ Name = "other-harness-accepted"
           Find = 'if ($one[0].harness -cne $Harness) {'
           Replace = 'if ($false) {' }
        @{ Name = "local-since-accepted"
           Find = 'if ($Since.Kind -ne [System.DateTimeKind]::Utc -or $Now.Kind -ne [System.DateTimeKind]::Utc) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "survey-always-clean"
           Find = 'Where-Object { @($_.unrecognised).Count -gt 0 }'
           Replace = 'Where-Object { $false }' }
        @{ Name = "reader-file-not-required"
           Find = 'ForEach-Object { Join-Path $_.FullName "Idle.ps1" } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }'
           Replace = 'ForEach-Object { Join-Path $_.FullName "Idle.ps1" }' }
        @{ Name = "no-reader-throws-instead"
           Find = 'if ($null -eq $reader) { return (New-HordeUnknown -Reason ("no idle reader for the harness ''" + $Harness + "''")) }'
           Replace = 'if ($null -eq $reader) { return (New-HordeUnknown -Reason "unknown") }' }
        @{ Name = "remote-link-not-an-answer"
           Find = '$script:HordeTurnStateAnswers = @("newestEventAt", "lastTurnEndAt", "atBoundary", "remoteLink")'
           Replace = '$script:HordeTurnStateAnswers = @("newestEventAt", "lastTurnEndAt", "atBoundary")' }
    )
}
