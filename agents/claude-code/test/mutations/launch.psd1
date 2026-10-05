# Mutations of agents/claude-code/Launch.ps1 (the act path's A1; issue #67, decision 6). Run:
#   powershell -File tools\Mutate.ps1 -Spec agents\claude-code\test\mutations\launch.psd1
# agents\claude-code\test\test-launch.ps1 must fail for every one.
@{
    Target = "agents\claude-code\Launch.ps1"
    Suite  = "agents\claude-code\test\test-launch.ps1"
    Mutations = @(
        @{ Name = "first-mode-not-last"
           Find = 'if ($m.Success) { $last = $m.Groups[1].Value }'
           Replace = 'if ($m.Success -and $null -eq $last) { $last = $m.Groups[1].Value }' }
        @{ Name = "other-session-lines-count"
           Find = 'if ($line -cnotmatch (''"sessionId"\s*:\s*"'' + [regex]::Escape($SessionId) + ''"'')) { continue }'
           Replace = 'if ($false) { continue }' }
        @{ Name = "any-line-with-the-field"
           Find = 'if ($line -cnotmatch ''"type"\s*:\s*"permission-mode"'') { continue }'
           Replace = 'if ($false) { continue }' }
        @{ Name = "mode-matched-without-case"
           Find = ' -or -not ($script:ClaudeCodeModeLevels.Keys -ccontains $last)'
           Replace = '' }
        @{ Name = "remote-control-bare"
           Find = '$argv.Add("-n"); $argv.Add($name); $argv.Add("--remote-control"); $argv.Add($name)'
           Replace = '$argv.Add("-n"); $argv.Add($name); $argv.Add("--remote-control")' }
        @{ Name = "dash-prompt-passed"
           Find = 'if ($prompt.StartsWith("-")) {'
           Replace = 'if ($false) {' }
        @{ Name = "long-prompt-passed"
           Find = 'if ($prompt.Length -gt $script:ClaudeCodePromptMax) {'
           Replace = 'if ($false) {' }
        @{ Name = "control-characters-passed"
           Find = 'if ($prompt -cmatch ''[\x00-\x08\x0B-\x1F\x7F]'') {'
           Replace = 'if ($false) {' }
        @{ Name = "pid-not-checked"
           Find = 'if ("" + $d.pid -cne $pidText) {'
           Replace = 'if ($false) {' }
        @{ Name = "remote-control-assumed"
           Find = '$rc = New-HordeUnknown -Reason "the control file names no Remote Control session yet"'
           Replace = '$rc = New-HordeKnown -Value $true' }
        @{ Name = "edits-mapped-as-bypass"
           Find = '"acceptEdits" = "edits"'
           Replace = '"acceptEdits" = "bypass"' }
        @{ Name = "config-dir-ignored"
           Find = 'if ($set.Trim() -ne "") { return $set.Trim() }'
           Replace = 'if ($false) { return $set.Trim() }' }
        @{ Name = "precondition-claimed"
           Find = '    return @()'
           Replace = '    return $Names' }
    )
}
