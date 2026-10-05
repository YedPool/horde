# Mutations of the isolation harness. Run: powershell -File tools\Mutate.ps1 -Spec hosts\wezterm\test\mutations\isolation.psd1
# Each breaks one rule the harness depends on; hosts\wezterm\test\test-isolation.ps1 must fail for every one of
# them except those declared Expect = "survives", which name a gap the fast suite cannot reach.
@{
    Target = "hosts\wezterm\test\Isolation.ps1"
    Suite  = "hosts\wezterm\test\test-isolation.ps1"
    Mutations = @(
        @{ Name = "walker-attributes-despite-stranger"
           Find = '} elseif ($owner -or -not $RootPinned) {'
           Replace = '} elseif ($false) {' }
        @{ Name = "walker-attributes-without-pin"
           Find = '} elseif ($owner -or -not $RootPinned) {'
           Replace = '} elseif ($owner) {' }
        @{ Name = "walker-ignores-parent-age"
           Find = '(Get-HordeMicroseconds $c.created) -lt $parUs) { continue }'
           Replace = '$false) { continue }' }
        @{ Name = "walker-compares-root-by-tick"
           Find = '(Get-HordeMicroseconds $owner.created) -eq $rootUs'
           Replace = '$owner.created -eq $RootCreated' }
        @{ Name = "teardown-kills-non-wezterm"
           Find = '-and $live.name -ne "wezterm-gui.exe"'
           Replace = '-and $false' }
        @{ Name = "teardown-deletes-any-socket"
           Find = '$sockOk = Test-HordeOwnedPath'
           Replace = '$sockOk = $true; $null = Test-HordeOwnedPath' }
        @{ Name = "teardown-deletes-any-store"
           Find = 'if ((Test-HordeOwnedPath -Path $ourStore'
           Replace = 'if ($true -or (Test-HordeOwnedPath -Path $ourStore' }
        @{ Name = "owned-path-ignores-name"
           Find = 'if ((Split-Path -Leaf $Path) -notmatch $LeafPattern) { return $false }'
           Replace = '' }
        @{ Name = "owned-path-ignores-folder"
           Find = '[System.IO.Path]::GetFullPath($Folder).TrimEnd(''\''), [System.StringComparison]::OrdinalIgnoreCase)'
           Replace = '$parent, [System.StringComparison]::OrdinalIgnoreCase)' }
        @{ Name = "token-not-spent"
           Find = '$script:HordeIsoStarted.Remove("$($Instance.token)")'
           Replace = '' }
        @{ Name = "registry-reset-on-reload"
           Find = 'if ($null -eq $script:HordeIsoStarted) { $script:HordeIsoStarted = @{} }'
           Replace = '$script:HordeIsoStarted = @{}' }
        @{ Name = "register-trusts-any-pid"
           Find = 'if ($pin.HasExited -or (Get-HordeMicroseconds $pin.StartTime) -ne (Get-HordeMicroseconds $Created)) {'
           Replace = 'if ($false) {' }
        @{ Name = "restore-from-handed-object"
           Find = '$env:WEZTERM_UNIX_SOCKET = $known.originalSocket'
           Replace = '$env:WEZTERM_UNIX_SOCKET = $Instance.originalSocket' }
        @{ Name = "microseconds-by-float"
           Find = 'return [Math]::DivRem([long]([datetime]$Time).ToUniversalTime().Ticks, [long]10, [ref]$rem)'
           Replace = 'return [long][Math]::Floor(([datetime]$Time).ToUniversalTime().Ticks / 10)' }
        @{ Name = "kill-ignores-creation-time"
           Find = 'if ((Get-HordeMicroseconds $p.StartTime) -ne (Get-HordeMicroseconds $Created)) { return "not-same" }'
           Replace = '' }
        @{ Name = "teardown-forgets-the-pin"
           Find = '$pinned = [bool]$known.pin'
           Replace = '$pinned = $false' }
        @{ Name = "teardown-leaves-orphans"
           Find = '$r = Invoke-HordeKill -Id $d.pid -Created $d.created -KillWith $KillWith'
           Replace = '$r = "gone"' }
        @{ Name = "adopts-a-gui-with-another-parent"
           Find = 'if ([int]$Gui.ppid -ne $LauncherPid) { return $false }'
           Replace = '' }
        @{ Name = "adopts-a-gui-older-than-the-launcher"
           Find = 'return ((Get-HordeMicroseconds $Gui.created) -ge [long]$LauncherUs)'
           Replace = 'return $true' }
        @{ Name = "launch-tree-ignores-start-time"
           Find = 'if ($null -eq $lc -or (Get-HordeMicroseconds $lc) -ne [long]$LauncherUs) { return }'
           Replace = 'if ($null -eq $lc) { return }' }
        @{ Name = "kill-ignores-the-guard"
           Find = 'if ($KillWith) { return (& $KillWith $Id $Created) }'
           Replace = '' }
        @{ Name = "orphan-kill-drops-the-guard"
           Find = '$r = Invoke-HordeKill -Id $d.pid -Created $d.created -KillWith $KillWith'
           Replace = '$r = Invoke-HordeKill -Id $d.pid -Created $d.created' }
        @{ Name = "no-second-walk-after-the-kill"
           Find = 'foreach ($pass in 1..2) {'
           Replace = 'foreach ($pass in 1..1) {'
           Expect = "survives"
           Reason = "Proving it needs a process that appears between the first walk and the kill, which the fast suite cannot stage deterministically; the rule is carried by its comment in Stop-HordeIsolatedWezterm." }
        @{ Name = "socket-deleted-though-gui-survived"
           Find = 'if ($sockOk -and -not $survived) {'
           Replace = 'if ($sockOk) {'
           Expect = "survives"
           Reason = "Proving it needs a gui that outlives a kill, which the fast suite cannot make without a real terminal; the rule is carried by its comment in Stop-HordeIsolatedWezterm." }
        @{ Name = "pane-env-missing-passes"
           Find = 'if (-not $Dump.ContainsKey($k)) { [void]$bad.Add($k + " is not set inside the pane") }'
           Replace = 'if (-not $Dump.ContainsKey($k)) { }' }
        @{ Name = "pane-env-value-ignored"
           Find = 'elseif ("" + $Dump[$k] -cne "" + $Expect[$k]) {'
           Replace = 'elseif ("" + $Dump[$k] -ne "" + $Expect[$k]) {' }
        @{ Name = "pane-env-no-dump-passes"
           Find = 'if ($null -eq $Dump) { return "no environment was read from inside the pane - unknown, not proven" }'
           Replace = 'if ($null -eq $Dump) { return $null }' }
        @{ Name = "pane-env-nothing-expected-passes"
           Find = 'if ($Expect.Count -eq 0) { return "nothing was expected, so nothing was proven" }'
           Replace = 'if ($false) { }' }
    )
}
