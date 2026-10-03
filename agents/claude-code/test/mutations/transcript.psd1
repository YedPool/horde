# Mutations of agents/claude-code/Transcript.ps1.
# Run: powershell -File tools\Mutate.ps1 -Spec agents\claude-code\test\mutations\transcript.psd1
# Each breaks one rule the adapter carries; agents\claude-code\test\test-transcript.ps1 must fail for every one.
# Plan step M2 split the adapter into two reads (facts, then records); each M1 mutation breaks the
# same rule at its new place, and the last two break the split itself.
@{
    Target = "agents\claude-code\Transcript.ps1"
    Suite  = "agents\claude-code\test\test-transcript.ps1"
    Mutations = @(
        @{ Name = "one-call-per-line"
           Find = '                [void]$calls.Remove($id)'
           Replace = '                $null = 0' }
        @{ Name = "api-error-is-a-call"
           Find = 'if ($model -eq "<synthetic>" -or $v["isApiErrorMessage"] -eq $true -or $msg -isnot [System.Collections.IDictionary]) {'
           Replace = 'if ($msg -isnot [System.Collections.IDictionary]) {' }
        @{ Name = "cache-split-dropped"
           Find = '    if ($cc -is [System.Collections.IDictionary]) {'
           Replace = '    if ($false) {' }
        @{ Name = "job-is-a-worker"
           Find = 'elseif ($tcKnown) { $worker = New-HordeAbsent -Note ("about a " + $tcName + " call, not a worker") }'
           Replace = 'elseif ($tcKnown) { $worker = New-HordeKnown -Value $n.toolCallId }' }
        @{ Name = "unresolved-guessed-as-worker"
           Find = 'else { $worker = New-HordeUnknown -Reason "its task and call resolve to nothing in this transcript or its subagents folder" }'
           Replace = 'else { $worker = New-HordeKnown -Value "guessed" }' }
        @{ Name = "launch-tool-not-known"
           Find = '$script:ClaudeCodeWorkerTools = @("Agent", "Task")'
           Replace = '$script:ClaudeCodeWorkerTools = @("Task")' }
        @{ Name = "meta-line-is-input"
           Find = 'if ($v["isMeta"] -eq $true -or $v["isCompactSummary"] -eq $true) {'
           Replace = 'if ($false) {' }
        @{ Name = "end-turn-always-a-turn-end"
           Find = 'if ($st.turnDurations -eq 0 -and $f[9] -eq 1) {'
           Replace = 'if ($f[9] -eq 1) {' }
        @{ Name = "queued-notifications-missed"
           Find = 'if ($att -is [System.Collections.IDictionary] -and $att["type"] -eq "queued_command") {'
           Replace = 'if ($false) {' }
        @{ Name = "subagent-folder-not-read"
           Find = 'if ($f.Name -match ''\Aagent-(.+)\.jsonl\z'') { [void]$agents.Add($Matches[1]); continue }'
           Replace = 'if ($f.Name -match ''\Aagent-(.+)\.jsonl\z'') { continue }' }
        @{ Name = "meta-json-not-read"
           Find = 'if ($meta -is [System.Collections.IDictionary] -and $meta["toolUseId"] -is [string]) { $byTool[$meta["toolUseId"]] = $id }'
           Replace = '$null = $meta' }
        @{ Name = "tool-input-text-counted"
           Find = 'if ($b["type"] -eq "text" -and $b["text"] -is [string]) { $f[7] += $b["text"].Length }'
           Replace = 'if ($b["type"] -eq "text" -and $b["text"] -is [string]) { $f[7] += $b["text"].Length + 400 }' }
        @{ Name = "first-line-usage-only"
           Find = '        if ($null -ne $v -and [long]$v -gt $Max[$i + 1]) { $Max[$i + 1] = [long]$v }'
           Replace = '        if ($null -ne $v -and $Max[$i + 1] -eq [long]::MinValue) { $Max[$i + 1] = [long]$v }' }
        @{ Name = "usage-summed-across-lines"
           Find = '        if ($null -ne $v -and [long]$v -gt $Max[$i + 1]) { $Max[$i + 1] = [long]$v }'
           Replace = '        if ($null -ne $v) { if ($Max[$i + 1] -eq [long]::MinValue) { $Max[$i + 1] = 0 }; $Max[$i + 1] += [long]$v }' }
        @{ Name = "notification-by-text"
           Find = '    if (-not $IsNote) {'
           Replace = '    if (-not ($IsNote -or $Text -like "*<task-notification>*")) {' }
        @{ Name = "human-origin-ignored"
           Find = '    if ($Origin -is [System.Collections.IDictionary]) { return ($Origin["kind"] -ceq "task-notification") }'
           Replace = '    if ($Origin -is [System.Collections.IDictionary]) { return $true }' }
        @{ Name = "task-id-text-trusted"
           Find = '        elseif ($taskOk) { $worker = New-HordeKnown -Value $n.taskId }'
           Replace = '        elseif ($n.taskId -ne "") { $worker = New-HordeKnown -Value $n.taskId }' }
        @{ Name = "unchecked-task-id-kept"
           Find = '    $keptTask = ""; if ($taskOk) { $keptTask = $n.taskId }'
           Replace = '    $keptTask = $n.taskId' }
        @{ Name = "interim-from-whole-text"
           Find = '    $noteKind = Get-ClaudeCodeNoteKind -Note (& $get "note")'
           Replace = '    $noteKind = Get-ClaudeCodeNoteKind -Note $Text' }
        @{ Name = "missing-usage-field-is-zero"
           Find = '        if ($Max[$i + 1] -eq [long]::MinValue) { return (New-HordeUnknown -Reason ("the usage has no " + $script:ClaudeCodeUsageFields[$i])) }'
           Replace = '        if ($false) { }' }
        @{ Name = "session-side-chain-counted"
           Find = '        if ($isSessionFile -and $v["isSidechain"] -eq $true) {'
           Replace = '        if ($false) {' }
        @{ Name = "unknown-note-read-as-final"
           Find = '    return "unrecognised"'
           Replace = '    return "final"' }
        @{ Name = "facts-from-the-second-read-only"
           Find = '    $firstRead = Read-HordeJsonLines -Path $Path -Each $visit'
           Replace = '    $firstRead = Read-HordeJsonLines -Path $Path -Each { param($a, $b) }' }
        @{ Name = "tool-names-not-gathered"
           Find = 'elseif ($b["type"] -eq "tool_use") { $f[8]++; $tools["$($b["id"])"] = "$($b["name"])" }'
           Replace = 'elseif ($b["type"] -eq "tool_use") { $f[8]++ }' }
    )
}
