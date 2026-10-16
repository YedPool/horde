# Mutations of fleet/Wake.ps1, waking a hibernation. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-wake.psd1
# Each breaks one rule of the wake; test\test-fleet-wake.ps1 must fail a check for every one.
@{
    Target = "fleet\Wake.ps1"
    Suite  = "test\test-fleet-wake.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "lock-ignored"
           Find = 'if (Test-Path -LiteralPath $lockPath) { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "lock-left-behind"
           Find = '$lockStream.Dispose(); Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue'
           Replace = '$lockStream.Dispose()' }
        @{ Name = "unknown-started"
           Find = 'if ("" + $v.state -ceq "stopped") { [void]$spawnable.Add($s) }'
           Replace = 'if ("" + $v.state -cne "running") { [void]$spawnable.Add($s) }' }
        @{ Name = "refused-not-marked"
           Find = 'if (-not $DryRun) { Add-HordeFleetState -Session $r.session -State "still-awake" -At $now -Reason $r.reason }'
           Replace = '' }
        @{ Name = "memory-gate-off"
           Find = 'if ($free -lt $script:HordeFleetWakeMinFreePercent) {'
           Replace = 'if ($false) {' }
        @{ Name = "memory-stop-not-kept"
           Find = 'if ($stopped) { & $say'
           Replace = 'if ($false) { & $say' }
        @{ Name = "rotation-any-pane"
           Find = 'if ($null -ne $p -and $p.state -eq "known" -and ("" + $p.value) -ceq $Pane) {'
           Replace = 'if ($null -ne $p) {' }
        @{ Name = "rotation-not-recorded"
           Find = 'if ($found.rotated) { $s | Add-Member -NotePropertyName "wokenAs"'
           Replace = 'if ($false) { $s | Add-Member -NotePropertyName "wokenAs"' }
        @{ Name = "dry-run-acts"
           Find = '        if ($DryRun) {'
           Replace = '        if ($false) {' }
        @{ Name = "expected-starts-not-written"
           Find = '$record | Add-Member -NotePropertyName "expectedStarts" -NotePropertyValue $exp -Force'
           Replace = '$exp = $null' }
        @{ Name = "wargs-not-grouped"
           Find = 'if ("" + $byId[$p].role -ceq "orc") { $head = $p; break }'
           Replace = 'if ($false) { $head = $p; break }' }
        @{ Name = "never-split"
           Find = 'if ($Started.ContainsKey($key)) {'
           Replace = 'if ($false) {' }
        @{ Name = "untold-is-woken"
           Find = 'if ($null -eq $posted -or $posted.state -ne "known") {'
           Replace = 'if ($false) {' }
        @{ Name = "timeout-is-woken"
           Find = 'if (-not $found.found) {'
           Replace = 'if ($false) {' }
        @{ Name = "only-unknown-label-ignored"
           Find = 'if (@($sessions | Where-Object { "" + (Get-HordeFleetMember $_ "label") -ceq $l }).Count -eq 0) { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "mail-id-random"
           Find = 'return (ConvertTo-HordeTextUuid -Text ("horde-fleet-wake/" + $Id + "/" + $SessionId))'
           Replace = 'return ([guid]::NewGuid().ToString())' }
    )
}
