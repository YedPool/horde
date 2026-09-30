# Mutations of the isolation harness. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\isolation.psd1
# Each breaks one rule the harness depends on; test\test-isolation.ps1 must fail for every one of
# them except those declared Expect = "survives", which name a gap the fast suite cannot reach.
@{
    Target = "test\harness\Isolation.ps1"
    Suite  = "test\test-isolation.ps1"
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
        @{ Name = "socket-deleted-though-gui-survived"
           Find = 'if ($sockOk -and -not $survived) {'
           Replace = 'if ($sockOk) {'
           Expect = "survives"
           Reason = "Proving it needs a gui that outlives a kill, which the fast suite cannot make without a real terminal; the rule is carried by its comment in Stop-HordeIsolatedWezterm." }
    )
}
