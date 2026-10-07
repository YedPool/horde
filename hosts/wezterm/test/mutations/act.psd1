# Mutations of hosts/wezterm/Act.ps1 (the act path's A2, with the fixes of PR #96's review). Run:
#   powershell -File tools\Mutate.ps1 -Spec hosts\wezterm\test\mutations\act.psd1
# hosts\wezterm\test\test-act.ps1 must fail for every one. Each breaks one rule that keeps a node's acts
# in the terminal it names and on the panes it proves are its own.
@{
    Target = "hosts\wezterm\Act.ps1"
    Suite  = "hosts\wezterm\test\test-act.ps1"
    Mutations = @(
        @{ Name = "no-auto-start-dropped"
           Find = 'return @("cli", "--no-auto-start") + @($Rest)'
           Replace = 'return @("cli") + @($Rest)' }
        @{ Name = "unnamed-terminal-allowed"
           Find = '    if ($null -ne $bad) { return [pscustomobject]@{ code = -1; out = ""; err = ("refused: " + $bad); timedOut = $false } }'
           Replace = '' }
        @{ Name = "empty-socket-allowed"
           Find = 'if ($sock.Trim() -eq "") { return "the named terminal has no socket'
           Replace = 'if ($false) { return "the named terminal has no socket' }
        @{ Name = "pin-not-set-from-target"
           Find = '    $psi.EnvironmentVariables["WEZTERM_UNIX_SOCKET"] = "" + $Target.socket'
           Replace = '' }
        @{ Name = "wezterm-names-allowed-in-map"
           Find = 'if (("" + $k).StartsWith("WEZTERM_", [System.StringComparison]::OrdinalIgnoreCase)) {'
           Replace = 'if ($false) {' }
        @{ Name = "nul-allowed"
           Find = 'if (("" + $v).Contains([string][char]0)) {'
           Replace = 'if ($false) {' }
        @{ Name = "value-uncapped"
           Find = 'if (("" + $v).Length -gt $script:HordeWeztermEnvValueMax) {'
           Replace = 'if ($false) {' }
        @{ Name = "removal-ignored"
           Find = 'if ($null -eq $Environment[$k]) { if ($Psi.EnvironmentVariables.ContainsKey($k)) { $Psi.EnvironmentVariables.Remove($k) } }'
           Replace = 'if ($null -eq $Environment[$k]) { }' }
        @{ Name = "quote-not-escaped"
           Find = 'if ($ch -eq ''"'') { [void]$sb.Append(([string][char]92) * ($slashes * 2 + 1)); [void]$sb.Append(''"''); $slashes = 0; continue }'
           Replace = 'if ($ch -eq ''"'') { [void]$sb.Append(''"''); $slashes = 0; continue }' }
        @{ Name = "trailing-slashes-not-doubled"
           Find = 'if ($slashes -gt 0) { [void]$sb.Append(([string][char]92) * ($slashes * 2)) }'
           Replace = 'if ($slashes -gt 0) { [void]$sb.Append(([string][char]92) * $slashes) }' }
        @{ Name = "line-break-not-quoted"
           Find = 'if ($Arg.Length -gt 0 -and $Arg -cnotmatch ''[\s"]'') { return $Arg }'
           Replace = 'if ($Arg.Length -gt 0 -and $Arg -cnotmatch ''[ "]'') { return $Arg }' }
        @{ Name = "shim-accepted"
           Find = '$exe = @($found | Where-Object { [System.IO.Path]::GetExtension("" + $_) -ieq ".exe" })'
           Replace = '$exe = @($found)' }
        @{ Name = "spawn-without-separator"
           Find = '$rest += @("--cwd", $Cwd, "--", $Program) + @($Argv)'
           Replace = '$rest += @("--cwd", $Cwd, $Program) + @($Argv)' }
        @{ Name = "handle-without-terminal"
           Find = 'return ("" + $Target.guiPid + "." + $Target.guiStart + "." + $Pane)'
           Replace = 'return ("" + $Pane)' }
        @{ Name = "handle-of-another-terminal-accepted"
           Find = 'if ($m.Groups[1].Value -cne "" + $Target.guiPid -or $m.Groups[2].Value -cne "" + $Target.guiStart) {'
           Replace = 'if ($false) {' }
        @{ Name = "restarted-terminal-accepted"
           Find = 'if (-not (Test-HordeWeztermSameStart $now $Target.guiStart)) {'
           Replace = 'if ($false) {' }
        @{ Name = "send-without-separator"
           Find = '$r = Invoke-HordeWeztermCall -Rest @("send-text", "--pane-id", $pane.value, "--no-paste", "--", $Text)'
           Replace = '$r = Invoke-HordeWeztermCall -Rest @("send-text", "--pane-id", $pane.value, "--no-paste", $Text)' }
        @{ Name = "control-characters-typed"
           Find = 'if ($Text -cmatch ''[\x00-\x1F\x7F-\x9F]'') {'
           Replace = 'if ($false) {' }
        @{ Name = "send-uncapped"
           Find = 'if ($Text.Length -gt $script:HordeWeztermSendMax) {'
           Replace = 'if ($false) {' }
        @{ Name = "enter-always-pressed"
           Find = '    if ($Submit) {'
           Replace = '    if ($true) {' }
        @{ Name = "stop-without-process-proof"
           Find = 'if ($in.state -ne "known") { return (New-HordeUnknown -Reason ("nothing was ended: " + $in.reason)) }'
           Replace = 'if ($false) { }' }
        @{ Name = "stop-on-gone-process"
           Find = 'if (-not $in.value) { return (New-HordeUnknown -Reason "nothing was ended: the expected process is not running with its start time") }'
           Replace = '' }
        @{ Name = "younger-parent-believed"
           Find = 'if ($null -eq $par -or [decimal]("0" + $par.start) -gt [decimal]("0" + $cur.start)) {'
           Replace = 'if ($null -eq $par) {' }
        @{ Name = "start-time-ignored"
           Find = 'if ($null -eq $cur -or -not (Test-HordeWeztermSameStart $cur.start $Expect.procStart)) { return (New-HordeKnown -Value $false) }'
           Replace = 'if ($null -eq $cur) { return (New-HordeKnown -Value $false) }' }
        @{ Name = "start-compared-to-the-millisecond"
           Find = 'return [bool]([decimal]::Floor($x / 10) -eq [decimal]::Floor($y / 10))'
           Replace = 'return [bool]([decimal]::Floor($x / 10000) -eq [decimal]::Floor($y / 10000))' }
        @{ Name = "empty-list-is-none"
           Find = 'if ($joined -eq "") { return (New-HordeUnknown -Reason "the terminal''s pane list was empty output, which is unknown, not none") }'
           Replace = 'if ($joined -eq "") { return (New-HordeKnown -Value @()) }' }
        @{ Name = "unlisted-is-gone"
           Find = 'if ($r.code -ne 0) { return (New-HordeUnknown -Reason ("the terminal did not list its panes (exit " + $r.code + ")")) }'
           Replace = 'if ($r.code -ne 0) { return (New-HordeKnown -Value $false) }' }
        @{ Name = "own-mux-picks-first"
           Find = 'if ($socks.Count -gt 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "c1-typed"
           Find = 'if ($Text -cmatch ''[\x00-\x1F\x7F-\x9F]'') {'
           Replace = 'if ($Text -cmatch ''[\x00-\x1F\x7F]'') {' }
        @{ Name = "pane-tie-skipped"
           Find = 'if (-not $tie.value) { return (New-HordeUnknown -Reason ($script:HordeWeztermPaneClaimMismatch + ": nothing was ended: the expected process runs in another pane than " + $pane.value)) }'
           Replace = '' }
        @{ Name = "unreadable-pane-ends"
           Find = 'if ($tie.state -ne "known") { return (New-HordeUnknown -Reason ("nothing was ended: " + $tie.reason)) }'
           Replace = '' }
        @{ Name = "unlisted-pane-ended"
           Find = 'if (@($listed.value | Where-Object { $_.pane -ceq $pane.value }).Count -eq 0) { return (New-HordeUnknown -Reason ("nothing was ended: the terminal lists no pane " + $pane.value)) }'
           Replace = '' }
        @{ Name = "live-without-tie"
           Find = '    if (-not $tie.value) { return (New-HordeUnknown -Reason ($script:HordeWeztermPaneClaimMismatch + ": the expected process runs in this terminal'
           Replace = '    if ($false) { return (New-HordeUnknown -Reason ($script:HordeWeztermPaneClaimMismatch + ": the expected process runs in this terminal' }
        @{ Name = "start-without-gui-check"
           Find = '    if ($null -ne $gone) { return (New-HordeUnknown -Reason $gone) }'
           Replace = '' }
        @{ Name = "unreadable-gui-start-passes"
           Find = 'if ($null -eq $now) { return ("the start time of the terminal'
           Replace = 'if ($false) { return ("the start time of the terminal' }
        @{ Name = "live-mismatch-called-gone"
           Find = '    if (-not $tie.value) { return (New-HordeUnknown -Reason ($script:HordeWeztermPaneClaimMismatch + ": the expected process runs in this terminal'
           Replace = '    if (-not $tie.value) { return (New-HordeKnown -Value $false) }; if ($false) { return (New-HordeUnknown -Reason ($script:HordeWeztermPaneClaimMismatch + ": the expected process runs in this terminal' }
        @{ Name = "stop-mismatch-unnamed"
           Find = 'return (New-HordeUnknown -Reason ($script:HordeWeztermPaneClaimMismatch + ": nothing was ended: the expected process runs in another pane than " + $pane.value)) }'
           Replace = 'return (New-HordeUnknown -Reason ("nothing was ended: the expected process runs in another pane than " + $pane.value)) }' }
        @{ Name = "reader-key-missed"
           Find = 'if ($kv.StartsWith("WEZTERM_PANE=", [System.StringComparison]::OrdinalIgnoreCase)) {'
           Replace = 'if ($kv.StartsWith("WEZTERM_PANEX=", [System.StringComparison]::OrdinalIgnoreCase)) {' }
        @{ Name = "reader-wrong-offset"
           Find = 'IntPtr env = ReadPtr(h, IntPtr.Add(pp, 0x80));'
           Replace = 'IntPtr env = ReadPtr(h, IntPtr.Add(pp, 0x88));' }
        @{ Name = "own-probe-ignores-profile"
           Find = '$sd = Get-HordeWeztermSockDir -ProfileDir $pd'
           Replace = '$sd = Get-HordeWeztermSockDir' }
        @{ Name = "own-probe-ignores-running"
           Find = 'if ($null -eq $Running) { return (Resolve-HordeWeztermOwnMux -SockDir $sd -Guis $Guis -ProcessStart $ProcessStart) }'
           Replace = 'return (Resolve-HordeWeztermOwnMux -SockDir $sd -Guis $Guis -ProcessStart $ProcessStart)' }
        @{ Name = "own-marker-elsewhere"
           Find = '    return (Join-Path (Get-HordeWeztermSockDir -ProfileDir $ProfileDir) ("gui-sock-" + $GuiPid))'
           Replace = '    return (Join-Path $ProfileDir ("gui-sock-" + $GuiPid))' }
        @{ Name = "own-default-profile-elsewhere"
           Find = '        $pd = "" + $env:USERPROFILE'
           Replace = '        $pd = "" + $env:TEMP' }
        @{ Name = "own-noarg-other-sockdir"
           Find = 'if ($null -eq $Running) { return (Resolve-HordeWeztermOwnMux -SockDir $sd -Guis $Guis -ProcessStart $ProcessStart) }'
           Replace = 'if ($null -eq $Running) { return (Resolve-HordeWeztermOwnMux -SockDir $env:TEMP -Guis $Guis -ProcessStart $ProcessStart) }' }
        @{ Name = "running-list-unchecked"
           Find = '    $why = Test-HordeWeztermRunningList -Running $Running'
           Replace = '    $why = ""' }
        @{ Name = "running-start-unchecked"
           Find = 'if (("" + $e.start) -cnotmatch ''\A[0-9]{1,20}\z'') {'
           Replace = 'if ($false) {' }
        @{ Name = "marker-pid-unchecked"
           Find = '    if (("" + $GuiPid) -cnotmatch ''\A[0-9]{1,10}\z'') { return $null }'
           Replace = '' }
        @{ Name = "profile-share-allowed"
           Find = '    if ($Path -cnotmatch ''\A[A-Za-z]:\\'') {'
           Replace = '    if ($false) {' }
        @{ Name = "profile-dotdot-allowed"
           Find = '    if ($full.TrimEnd(''\'') -cne $Path.TrimEnd(''\'')) {'
           Replace = '    if ($false) {' }
        @{ Name = "profile-junction-allowed"
           Find = '            if (($it.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {'
           Replace = '            if ($false) {' }
        @{ Name = "profile-unchecked-in-own"
           Find = '    if ($pd -ne "") { $why = Test-HordeWeztermProfileDir -Path $pd; if ($why -ne "") { return (New-HordeUnknown -Reason $why) } }'
           Replace = '' }
        @{ Name = "profile-network-drive-allowed"
           Find = '    if (@("Fixed", "Removable") -cnotcontains $kind) {'
           Replace = '    if ($false) {' }
        @{ Name = "profile-inner-junction-unchecked"
           Find = '    $p = (Get-HordeWeztermSockDir -ProfileDir $full.TrimEnd(''\'')).TrimEnd(''\'')'
           Replace = '    $p = $full.TrimEnd(''\'')' }
        @{ Name = "profile-unreadable-folder-passes"
           Find = '            if ($null -eq $it) {'
           Replace = '            if ($false) {' }
        @{ Name = "profile-walk-starts-above-socket-folder"
           Find = '    $p = (Get-HordeWeztermSockDir -ProfileDir $full.TrimEnd(''\'')).TrimEnd(''\'')'
           Replace = '    $p = Split-Path -Parent (Get-HordeWeztermSockDir -ProfileDir $full.TrimEnd(''\''))' }
        @{ Name = "default-profile-unchecked"
           Find = '        $why = Test-HordeWeztermProfileDir -Path $pd'
           Replace = '        $why = ""' }
    )
}
