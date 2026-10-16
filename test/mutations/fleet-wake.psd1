# Mutations of fleet/Wake.ps1, waking a hibernation. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-wake.psd1
# Each breaks one rule of the wake; test\test-fleet-wake.ps1 must fail a check for every one.
@{
    Target = "fleet\Wake.ps1"
    Suite  = "test\test-fleet-wake.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "live-lock-owner-ignored"
           Find = 'if (-not $owner.stale) { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "gone-owner-alive"
           Find = 'if ($now -eq "") { return [pscustomobject]@{ stale = $true;'
           Replace = 'if ($now -eq "") { return [pscustomobject]@{ stale = $false;' }
        @{ Name = "reused-pid-owner-alive"
           Find = 'return [pscustomobject]@{ stale = $true; owner = $owner; reason = ("pid " + $owner + " now belongs'
           Replace = 'return [pscustomobject]@{ stale = $false; owner = $owner; reason = ("pid " + $owner + " now belongs' }
        @{ Name = "unreadable-owner-stale"
           Find = 'stale = $false; owner = $owner; reason = ("pid " + $owner + " runs and its start time'
           Replace = 'stale = $true; owner = $owner; reason = ("pid " + $owner + " runs and its start time' }
        @{ Name = "lock-without-start"
           Find = '"pid " + $self.pid + " start " + $self.start + " at "'
           Replace = '"pid " + $self.pid + " at "' }
        @{ Name = "record-mates-not-ignored"
           Find = '("" + $s.cwd) $recordIds (Get-HordeFleetSince'
           Replace = '("" + $s.cwd) @() (Get-HordeFleetSince' }
        @{ Name = "exit-time-not-read"
           Find = '$text = $(if ($exits.Count -gt 0) {'
           Replace = '$text = $(if ($false) {' }
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
           Find = '($null -ne $free -and $free -lt $script:HordeFleetWakeMinFreePercent)'
           Replace = '($false)' }
        @{ Name = "memory-read-failure-ignored"
           Find = 'if ($readFailed -ne "" -or ($null -ne $free'
           Replace = 'if ($false -or ($null -ne $free' }
        @{ Name = "self-start-unread-accepted"
           Find = 'if (-not $DryRun -and "" + $self.start -cnotmatch'
           Replace = 'if ($false -and "" + $self.start -cnotmatch' }
        @{ Name = "earlier-pane-not-held"
           Find = 'if ($holdWhy -ne "" -and -not $Retry) {'
           Replace = 'if ($false) {' }
        @{ Name = "waking-not-held"
           Find = 'if ("" + $s.state -ceq "waking") { $holdWhy ='
           Replace = 'if ($false) { $holdWhy =' }
        @{ Name = "not-read-again-under-lock"
           Find = '$record = $again.value'
           Replace = '$null = $again.value' }
        @{ Name = "lost-window-ignored"
           Find = 'if ($window -eq "") { $groupStop ='
           Replace = 'if ($false) { $groupStop =' }
        @{ Name = "recorded-process-not-passed"
           Find = '$recordIds (Get-HordeFleetSince -Session $s -Record $record) (Get-HordeFleetMember $s "process")'
           Replace = '$recordIds (Get-HordeFleetSince -Session $s -Record $record)' }
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
           Find = 'if (@($all | Where-Object { "" + (Get-HordeFleetMember $_ "label") -ceq $l }).Count -eq 0) { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "no-fresh-check-before-spawn"
           Find = 'if ("" + $recheck.state -cne "stopped") {'
           Replace = 'if ($false) {' }
        @{ Name = "fresh-check-forgets-started"
           Find = '@($recordIds + @($startedIds)) (Get-HordeFleetSince'
           Replace = '@($recordIds) (Get-HordeFleetSince' }
        @{ Name = "mail-id-random"
           Find = 'return (ConvertTo-HordeTextUuid -Text ("horde-fleet-wake/" + $Id + "/" + $SessionId))'
           Replace = 'return ([guid]::NewGuid().ToString())' }
    )
}
