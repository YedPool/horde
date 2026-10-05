# Mutations of hosts/wezterm/Act.ps1 (the act path's A2). Run:
#   powershell -File tools\Mutate.ps1 -Spec hosts\wezterm\test\mutations\act.psd1
# hosts\wezterm\test\test-act.ps1 must fail for every one. Each breaks one rule that keeps a node's own
# terminal safe to act in: the flag that never starts a server, the quoting a prompt depends on, no
# cmd.exe in between, and never calling a pane gone when the terminal could not say.
@{
    Target = "hosts\wezterm\Act.ps1"
    Suite  = "hosts\wezterm\test\test-act.ps1"
    Mutations = @(
        @{ Name = "no-auto-start-dropped"
           Find = 'return @("cli", "--no-auto-start") + @($Rest)'
           Replace = 'return @("cli") + @($Rest)' }
        @{ Name = "quote-not-escaped"
           Find = 'if ($ch -eq ''"'') { [void]$sb.Append(([string][char]92) * ($slashes * 2 + 1)); [void]$sb.Append(''"''); $slashes = 0; continue }'
           Replace = 'if ($ch -eq ''"'') { [void]$sb.Append(''"''); $slashes = 0; continue }' }
        @{ Name = "trailing-slashes-not-doubled"
           Find = 'if ($slashes -gt 0) { [void]$sb.Append(([string][char]92) * ($slashes * 2)) }'
           Replace = 'if ($slashes -gt 0) { [void]$sb.Append(([string][char]92) * $slashes) }' }
        @{ Name = "line-break-not-quoted"
           Find = 'if ($Arg.Length -gt 0 -and $Arg -cnotmatch ''[\s"]'') { return $Arg }'
           Replace = 'if ($Arg.Length -gt 0 -and $Arg -cnotmatch ''[ "]'') { return $Arg }' }
        @{ Name = "empty-not-quoted"
           Find = 'if ($Arg.Length -gt 0 -and $Arg -cnotmatch'
           Replace = 'if ($Arg.Length -ge 0 -and $Arg -cnotmatch' }
        @{ Name = "shim-accepted"
           Find = '$exe = @($found | Where-Object { [System.IO.Path]::GetExtension("" + $_) -ieq ".exe" })'
           Replace = '$exe = @($found)' }
        @{ Name = "spawn-without-separator"
           Find = '$rest += @("--cwd", $Cwd, "--", $Program) + @($Argv)'
           Replace = '$rest += @("--cwd", $Cwd, $Program) + @($Argv)' }
        @{ Name = "relative-program-accepted"
           Find = 'if (-not [System.IO.Path]::IsPathRooted($Program) -or [System.IO.Path]::GetExtension($Program) -ine ".exe") {'
           Replace = 'if ($false) {' }
        @{ Name = "non-numeric-answer-accepted"
           Find = 'if ($id -cnotmatch ''\A[0-9]{1,9}\z'') { return (New-HordeUnknown -Reason ("the terminal answered the spawn with'
           Replace = 'if ($id -eq "") { return (New-HordeUnknown -Reason ("the terminal answered the spawn with' }
        @{ Name = "send-pasted"
           Find = '$rest = @("send-text", "--pane-id", $Handle, "--no-paste", $Text)'
           Replace = '$rest = @("send-text", "--pane-id", $Handle, $Text)' }
        @{ Name = "empty-list-is-none"
           Find = 'if ($joined -eq "") { return (New-HordeUnknown -Reason "the terminal''s pane list was empty output, which is unknown, not none") }'
           Replace = 'if ($joined -eq "") { return (New-HordeKnown -Value @()) }' }
        @{ Name = "unlisted-is-gone"
           Find = 'if ($r.code -ne 0) { return (New-HordeUnknown -Reason ("the terminal did not list its panes (exit " + $r.code + ")")) }'
           Replace = 'if ($r.code -ne 0) { return (New-HordeKnown -Value $false) }' }
        @{ Name = "kill-any-handle"
           Find = '$rest = @("kill-pane", "--pane-id", $Handle)'
           Replace = '$rest = @("kill-pane")' }
        @{ Name = "environment-not-applied"
           Find = '    Set-HordeWeztermActEnvironment -Psi $psi -Environment $Environment'
           Replace = '' }
        @{ Name = "removal-ignored"
           Find = 'if ($null -eq $Environment[$k]) { if ($Psi.EnvironmentVariables.ContainsKey($k)) { $Psi.EnvironmentVariables.Remove($k) } }'
           Replace = 'if ($null -eq $Environment[$k]) { }' }
        @{ Name = "environment-not-passed-to-spawn"
           Find = 'if ($null -ne $Runner) { $r = & $Runner $rest $Environment } else { $r = Invoke-HordeWeztermAct -Rest $rest -Environment $Environment }'
           Replace = 'if ($null -ne $Runner) { $r = & $Runner $rest @{} } else { $r = Invoke-HordeWeztermAct -Rest $rest }' }
    )
}
