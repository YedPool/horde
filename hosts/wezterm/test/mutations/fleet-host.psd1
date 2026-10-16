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
        @{ Name = "marker-id-unchecked"
           Find = '{ return (New-HordeUnknown -Reason ("''" + $SessionId + "'' is not a session id, so no marker'
           Replace = '{ }; if ($false) { return (New-HordeUnknown -Reason ("''" + $SessionId + "'' is not a session id, so no marker' }
    )
}
