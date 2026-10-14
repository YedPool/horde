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
        @{ Name = "close-without-enter"
           Find = '$script:ClaudeCodeCloseText = @("/exit", "`r")'
           Replace = '$script:ClaudeCodeCloseText = @("/exit")' }
        @{ Name = "model-dash-passed"
           Find = 'if (("" + $Spec.model).StartsWith("-")) {'
           Replace = 'if ($false) {' }
        @{ Name = "name-dash-passed"
           Find = 'if ($name.StartsWith("-")) {'
           Replace = 'if ($false) {' }
        @{ Name = "add-dir-dropped"
           Find = '        $argv.Add("--add-dir"); $argv.Add("" + $dir)'
           Replace = '' }
        # Issue #214: the turn receipt and the input box.
        @{ Name = "turn-contains-not-equals"
           Find = '        if ($null -ne $said -and $said.Trim() -ceq $want) { return "taken" }'
           Replace = '        if ($null -ne $said -and $said.Contains($want)) { return "taken" }' }
        @{ Name = "meta-line-is-a-turn"
           Find = '            if ($d["isMeta"] -eq $true) { continue }'
           Replace = '' }
        @{ Name = "other-session-turn-counts"
           Find = '        if ($d["sessionId"] -cne $SessionId) { continue }'
           Replace = '' }
        @{ Name = "turn-before-the-mark-counts"
           Find = '-Offset ([long]$Mark.size)'
           Replace = '-Offset 0' }
        @{ Name = "shrunk-transcript-not-reread"
           Find = '        if ($Offset -gt $stream.Length) { return (New-HordeUnknown'
           Replace = '        if ($Offset -gt $stream.Length) { $Offset = 0 }; if ($false) { return (New-HordeUnknown' }
        @{ Name = "no-transcript-no-mark"
           Find = '    if ($t.state -eq "absent") { return (New-HordeKnown -Value ([pscustomobject]@{ size = [long]0 })) }'
           Replace = '' }
        @{ Name = "box-wrap-not-joined"
           Find = '    return (New-HordeKnown -Value ([bool](($b.value.body -replace ''\s'', '''') -ceq ($Line -replace ''\s'', ''''))))'
           Replace = '    return (New-HordeKnown -Value ([bool]($b.value.body.Trim() -ceq $Line.Trim())))' }
        @{ Name = "box-not-the-lowest"
           Find = '    for ($k = $rules.Count - 1; $k -ge 1; $k--) {'
           Replace = '    for ($k = 1; $k -lt $rules.Count; $k++) {' }
        @{ Name = "box-without-glyph"
           Find = '        if ($first.Length -eq 0 -or $first[0] -ne $script:ClaudeCodePromptGlyph) { continue }'
           Replace = '        if ($first.Length -eq 0) { continue }' }
        @{ Name = "no-box-as-empty"
           Find = '    return (New-HordeUnknown -Reason "no input box of this harness can be read on the pane''s screen")'
           Replace = '    return (New-HordeKnown -Value $false)' }
        @{ Name = "sidechain-is-a-turn"
           Find = '        if ($d["isSidechain"] -eq $true) { continue }'
           Replace = '' }
        @{ Name = "queued-notification-is-a-turn"
           Find = '            if ($o -isnot [System.Collections.IDictionary] -or $o["kind"] -cne "human") { continue }'
           Replace = '' }
        @{ Name = "queued-command-not-a-receipt"
           Find = '            if ($a -isnot [System.Collections.IDictionary] -or $a["type"] -cne "queued_command") { continue }'
           Replace = '            continue' }
        @{ Name = "unparsed-row-a-silent-no"
           Find = '    if ($unreadable) { return "unreadable" }'
           Replace = '' }
        @{ Name = "case-twin-keys-dropped"
           Find = '        try { $doc = $ser.DeserializeObject($row) } catch { $doc = $null }'
           Replace = '        try { $doc = $ser.DeserializeObject($row.ToLowerInvariant()) } catch { $doc = $null }' }
        @{ Name = "turn-end-of-any-session"
           Find = '-and $d["sessionId"] -ceq $SessionId -and $d["isSidechain"] -ne $true) { return (New-HordeKnown -Value $true) }'
           Replace = ') { return (New-HordeKnown -Value $true) }' }
        @{ Name = "any-system-row-ends-a-turn"
           Find = '$d["type"] -ceq "system" -and $d["subtype"] -ceq "turn_duration"'
           Replace = '$d["type"] -ceq "system"' }
        @{ Name = "named-rule-not-a-rule"
           Find = '    for ($i = 0; $i -lt 8; $i++) { if ($t[$i] -ne $script:ClaudeCodeBoxRule) { return $false } }'
           Replace = '    if ($t.Trim($script:ClaudeCodeBoxRule).Length -ne 0) { return $false }' }
        @{ Name = "rule-may-start-with-a-label"
           Find = '    for ($i = 0; $i -lt 8; $i++) {'
           Replace = '    for ($i = 0; $i -lt 0; $i++) {' }
        @{ Name = "dialog-read-as-a-box"
           Find = '        if ($body -cmatch ''\A\s*[0-9]+\.\s'') { return (New-HordeUnknown'
           Replace = '        if ($false) { return (New-HordeUnknown' }
        @{ Name = "busy-read-as-ready"
           Find = '    foreach ($r in @($Screen)) { if (("" + $r).Contains($script:ClaudeCodeBusyMark))'
           Replace = '    foreach ($r in @()) { if (("" + $r).Contains($script:ClaudeCodeBusyMark))' }
        @{ Name = "box-not-anchored"
           Find = '        foreach ($r in $below) { if ('
           Replace = '        foreach ($r in @()) { if (' }
        @{ Name = "choice-under-the-box-ready"
           Find = ' -or ("" + $r) -cmatch ''(\A|\s)[0-9]+\.\s'') { return (New-HordeUnknown -Reason "a dialog of choices'
           Replace = ') { return (New-HordeUnknown -Reason "a dialog of choices' }
        @{ Name = "glyph-under-the-box-ready"
           Find = '("" + $r).IndexOf($script:ClaudeCodePromptGlyph) -ge 0 -or '
           Replace = '' }
        @{ Name = "busy-read-only-below"
           Find = '    foreach ($r in @($Screen)) { if (("" + $r).Contains($script:ClaudeCodeBusyMark))'
           Replace = '    foreach ($r in @($b.value.below)) { if (("" + $r).Contains($script:ClaudeCodeBusyMark))' }
    )
}
