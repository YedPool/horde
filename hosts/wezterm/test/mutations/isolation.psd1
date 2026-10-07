# Mutations of the isolation harness. Run: powershell -File tools\Mutate.ps1 -Spec hosts\wezterm\test\mutations\isolation.psd1
# Each breaks one rule the harness depends on; hosts\wezterm\test\test-isolation.ps1 must fail for every one of
# them except those declared Expect = "survives", which name a gap the fast suite cannot reach.
# SECTIONS (tools\Mutate.ps1; issue #83): each caught mutant runs only the first section of
# hosts\wezterm\test\test-isolation.ps1 whose checks failed for it in a whole-suite run of this spec on
# the always-on box (bd6cdb5, 2026-10-07). The declared survivors stay unmapped: the whole suite decides.
@{
    Target = "hosts\wezterm\test\Isolation.ps1"
    Suite  = "hosts\wezterm\test\test-isolation.ps1"
    Mutations = @(
        @{ Name = "walker-attributes-despite-stranger"
           Find = '} elseif ($owner -or -not $RootPinned) {'
           Replace = '} elseif ($false) {'
           Sections = @("walker") }
        @{ Name = "walker-attributes-without-pin"
           Find = '} elseif ($owner -or -not $RootPinned) {'
           Replace = '} elseif ($owner) {'
           Sections = @("walker") }
        @{ Name = "walker-ignores-parent-age"
           Find = '(Get-HordeMicroseconds $c.created) -lt $parUs) { continue }'
           Replace = '$false) { continue }'
           Sections = @("walker") }
        @{ Name = "walker-compares-root-by-tick"
           Find = '(Get-HordeMicroseconds $owner.created) -eq $rootUs'
           Replace = '$owner.created -eq $RootCreated'
           Sections = @("walker") }
        @{ Name = "teardown-kills-non-wezterm"
           Find = '-and $live.name -ne "wezterm-gui.exe"'
           Replace = '-and $false'
           Sections = @("teardown-refuse") }
        @{ Name = "teardown-deletes-any-socket"
           Find = '$sockOk = Test-HordeOwnedPath'
           Replace = '$sockOk = $true; $null = Test-HordeOwnedPath'
           Sections = @("teardown-refuse") }
        @{ Name = "teardown-deletes-any-store"
           Find = 'if ((Test-HordeOwnedPath -Path $ourStore'
           Replace = 'if ($true -or (Test-HordeOwnedPath -Path $ourStore'
           # Unmapped: run on its section alone it broke the suite rather than failing a check (the
           # always-on box, 2026-10-07), though the whole suite catches it there; the whole suite decides.
        }
        @{ Name = "owned-path-ignores-name"
           Find = 'if ((Split-Path -Leaf $Path) -notmatch $LeafPattern) { return $false }'
           Replace = ''
           Sections = @("teardown-refuse") }
        @{ Name = "owned-path-ignores-folder"
           Find = '[System.IO.Path]::GetFullPath($Folder).TrimEnd(''\''), [System.StringComparison]::OrdinalIgnoreCase)'
           Replace = '$parent, [System.StringComparison]::OrdinalIgnoreCase)'
           Sections = @("teardown-refuse") }
        @{ Name = "token-not-spent"
           Find = '$script:HordeIsoStarted.Remove("$($Instance.token)")'
           Replace = ''
           Sections = @("teardown-refuse") }
        @{ Name = "registry-reset-on-reload"
           Find = 'if ($null -eq $script:HordeIsoStarted) { $script:HordeIsoStarted = @{} }'
           Replace = '$script:HordeIsoStarted = @{}'
           Sections = @("teardown-refuse") }
        @{ Name = "register-trusts-any-pid"
           Find = 'if ($pin.HasExited -or (Get-HordeMicroseconds $pin.StartTime) -ne (Get-HordeMicroseconds $Created)) {'
           Replace = 'if ($false) {'
           Sections = @("teardown-refuse") }
        @{ Name = "restore-from-handed-object"
           Find = '$env:WEZTERM_UNIX_SOCKET = $known.originalSocket'
           Replace = '$env:WEZTERM_UNIX_SOCKET = $Instance.originalSocket'
           Sections = @("teardown-refuse") }
        @{ Name = "microseconds-by-float"
           Find = 'return [Math]::DivRem([long]([datetime]$Time).ToUniversalTime().Ticks, [long]10, [ref]$rem)'
           Replace = 'return [long][Math]::Floor(([datetime]$Time).ToUniversalTime().Ticks / 10)'
           Sections = @("no-pid-kill") }
        @{ Name = "kill-ignores-creation-time"
           Find = 'if ((Get-HordeMicroseconds $p.StartTime) -ne (Get-HordeMicroseconds $Created)) { return "not-same" }'
           Replace = ''
           Sections = @("no-pid-kill") }
        @{ Name = "teardown-forgets-the-pin"
           Find = '$pinned = [bool]$known.pin'
           Replace = '$pinned = $false'
           Sections = @("orphans") }
        @{ Name = "teardown-leaves-orphans"
           Find = '$r = Invoke-HordeKill -Id $d.pid -Created $d.created -KillWith $KillWith'
           Replace = '$r = "gone"'
           Sections = @("orphans") }
        @{ Name = "adopts-a-gui-with-another-parent"
           Find = 'if ([int]$Gui.ppid -ne $LauncherPid) { return $false }'
           Replace = ''
           Sections = @("adopt") }
        @{ Name = "adopts-a-gui-older-than-the-launcher"
           Find = 'return ((Get-HordeMicroseconds $Gui.created) -ge [long]$LauncherUs)'
           Replace = 'return $true'
           Sections = @("adopt") }
        @{ Name = "launch-tree-ignores-start-time"
           Find = 'if ($null -eq $lc -or (Get-HordeMicroseconds $lc) -ne [long]$LauncherUs) { return }'
           Replace = 'if ($null -eq $lc) { return }'
           Sections = @("launch-teardown") }
        @{ Name = "kill-ignores-the-guard"
           Find = 'if ($KillWith) { return (& $KillWith $Id $Created) }'
           Replace = ''
           Sections = @("orphans") }
        @{ Name = "orphan-kill-drops-the-guard"
           Find = '$r = Invoke-HordeKill -Id $d.pid -Created $d.created -KillWith $KillWith'
           Replace = '$r = Invoke-HordeKill -Id $d.pid -Created $d.created'
           Sections = @("orphans") }
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
           Replace = 'if (-not $Dump.ContainsKey($k)) { }'
           Sections = @("pane-env") }
        @{ Name = "pane-env-value-ignored"
           Find = 'elseif ("" + $Dump[$k] -cne "" + $Expect[$k]) {'
           Replace = 'elseif ("" + $Dump[$k] -ne "" + $Expect[$k]) {'
           Sections = @("pane-env") }
        @{ Name = "pane-env-no-dump-passes"
           Find = 'if ($null -eq $Dump) { return "no environment was read from inside the pane - unknown, not proven" }'
           Replace = 'if ($null -eq $Dump) { return $null }'
           Sections = @("pane-env") }
        @{ Name = "pane-env-nothing-expected-passes"
           Find = 'if ($Expect.Count -eq 0) { return "nothing was expected, so nothing was proven" }'
           Replace = 'if ($false) { }'
           Sections = @("pane-env") }
        @{ Name = "pin-comparison-skipped"
           Find = 'if ("$env:WEZTERM_UNIX_SOCKET" -ne "$($Instance.socket)") {'
           Replace = 'if ($false) {'
           Sections = @("refuse-doubt") }
    )
}
