# Mutations of hosts/wezterm/Fleet.ps1, the terminal's half of hibernation. Run:
#   powershell -File tools\Mutate.ps1 -Spec hosts\wezterm\test\mutations\fleet-host.psd1
# Each breaks one rule of placement or spawning; hosts\wezterm\test\test-fleet-host.ps1 must fail a check for every one.
@{
    Target = "hosts\wezterm\Fleet.ps1"
    Suite  = "hosts\wezterm\test\test-fleet-host.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "tab-index-lost"
           Find = 'tabIndex = $tabs.IndexOf($me.tab)'
           Replace = 'tabIndex = 0' }
        @{ Name = "tab-size-is-pane-size"
           Find = 'tabCols = [int]$tabCols'
           Replace = 'tabCols = $me.cols' }
        @{ Name = "geometry-guessed"
           Find = 'if ($null -eq $prop -or "" + $prop.Value -cnotmatch ''\A[0-9]{1,9}\z'') { return'
           Replace = 'if ($false) { return' }
        @{ Name = "line-split-into-words"
           Find = 'return @($rest + @("--cwd", $cwd, "--", $Program) + $script:HordeWeztermFleetShellArgs + @($line))'
           Replace = 'return @($rest + @("--cwd", $cwd, "--", $Program) + $script:HordeWeztermFleetShellArgs + @($line.Split(" ")))' }
        @{ Name = "control-character-allowed"
           Find = 'if ($line -eq "" -or $line -cmatch ''[\x00-\x1F\x7F]'') { throw'
           Replace = 'if ($line -eq "") { throw' }
        @{ Name = "percent-dropped"
           Find = 'if ("" + $Request.percent -cmatch ''\A[1-9][0-9]?\z'') { $rest += @("--percent", ("" + $Request.percent)) }'
           Replace = 'if ($false) { }' }
        @{ Name = "profile-loaded"
           Find = '@("-NoLogo", "-NoProfile", "-NoExit", "-Command")'
           Replace = '@("-NoLogo", "-NoExit", "-Command")' }
        @{ Name = "named-terminal-ignored"
           Find = 'if ($named -ne "") { return (New-HordeWeztermTarget -Socket $named -ProcessStart $ProcessStart) }'
           Replace = 'if ($false) { }' }
        @{ Name = "refused-settings-fall-back"
           Find = 'if ("" + $Settings.state -cne "defaults" -and "" + $Settings.state -cne "read") { return (New-HordeUnknown'
           Replace = 'if ($false) { return (New-HordeUnknown' }
        @{ Name = "placement-ignores-named-folder"
           Find = 'if ($named -ne "" -and [System.IO.Path]::IsPathRooted($named)) { return (Split-Path -Parent $named) }'
           Replace = 'if ($false) { }' }
        @{ Name = "lost-window-is-not-started"
           Find = 'if ($hit.Count -ne 1) { return (New-HordeKnown -Value'
           Replace = 'if ($hit.Count -ne 1) { return (New-HordeUnknown -Reason' }
        @{ Name = "store-shell-first"
           Find = 'if ($there) { return (New-HordeKnown -Value $installed) }'
           Replace = 'if ($false) { }' }
        @{ Name = "window-not-read-back"
           Find = 'if ($Request.mode -cne "tab") {'
           Replace = 'if ($false) {' }
        @{ Name = "scrub-not-passed"
           Find = '$r = Invoke-HordeWeztermCall -Rest $rest -Target $Target -Environment $envMap -Runner $Runner'
           Replace = '$r = Invoke-HordeWeztermCall -Rest $rest -Target $Target -Environment @{} -Runner $Runner' }
        @{ Name = "spawn-answer-trusted"
           Find = 'if ($pane -cnotmatch ''\A[0-9]{1,9}\z'') { return'
           Replace = 'if ($false) { return' }
        @{ Name = "refused-request-is-unknown"
           Find = 'catch { return (New-HordeAbsent -Note ("the spawn was not made: "'
           Replace = 'catch { return (New-HordeUnknown -Reason ("the spawn was not made: "' }
        @{ Name = "marker-id-unchecked"
           Find = '{ return (New-HordeUnknown -Reason ("''" + $SessionId + "'' is not a session id, so no marker was touched'
           Replace = '{ }; if ($false) { return (New-HordeUnknown -Reason ("''" + $SessionId + "'' is not a session id, so no marker was touched' }
        @{ Name = "marker-write-id-unchecked"
           Find = '{ return (New-HordeUnknown -Reason ("''" + $SessionId + "'' is not a session id, so no marker was written'
           Replace = '{ }; if ($false) { return (New-HordeUnknown -Reason ("''" + $SessionId + "'' is not a session id, so no marker was written' }
        @{ Name = "marker-reason-unchecked"
           Find = 'if (@("parked", "hibernated") -cnotcontains $Reason) {'
           Replace = 'if ($false) {' }
        @{ Name = "marker-not-written-by-rename"
           Find = 'Move-HordeFileAtomic -From $tmp -To $path'
           Replace = 'Copy-Item -LiteralPath $tmp -Destination $path -Force' }
        @{ Name = "marker-has-a-byte-order-mark"
           Find = '[System.IO.File]::WriteAllText($tmp, $text, (New-Object System.Text.UTF8Encoding($false)))'
           Replace = '[System.IO.File]::WriteAllText($tmp, $text, (New-Object System.Text.UTF8Encoding($true)))' }
        @{ Name = "marker-by-another-name"
           Find = '"by":"horde"'
           Replace = '"by":"hord"' }
        @{ Name = "marker-version-2"
           Find = '{"v":1,"sessionId"'
           Replace = '{"v":2,"sessionId"' }
        @{ Name = "marker-time-not-utc"
           Find = '$At.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"'
           Replace = '$At.ToString("yyyy-MM-ddTHH:mm:ssZ"' }
        @{ Name = "marker-writer-not-registered"
           Find = '-Mark { param($sessionId, $reason, $at) Write-HordeWeztermFleetNoRestore -SessionId $sessionId -Reason $reason -At $at }'
           Replace = '-Mark $null' }
    )
}
