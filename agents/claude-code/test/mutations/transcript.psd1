# Mutations of agents/claude-code/Transcript.ps1.
# Run: powershell -File tools\Mutate.ps1 -Spec agents\claude-code\test\mutations\transcript.psd1
# Each breaks one rule the adapter carries; agents\claude-code\test\test-transcript.ps1 must fail for every one.
@{
    Target = "agents\claude-code\Transcript.ps1"
    Suite  = "agents\claude-code\test\test-transcript.ps1"
    Mutations = @(
        @{ Name = "one-call-per-line"
           Find = '            $slot = $callAt[$id]'
           Replace = '            $slot = $null; $id = $id + "-" + $ln' }
        @{ Name = "api-error-is-a-call"
           Find = 'if ($model -eq "<synthetic>" -or $v["isApiErrorMessage"] -eq $true -or $msg -isnot [System.Collections.IDictionary]) {'
           Replace = 'if ($msg -isnot [System.Collections.IDictionary]) {' }
        @{ Name = "cache-split-dropped"
           Find = '    if ($cc -is [System.Collections.IDictionary]) {'
           Replace = '    if ($false) {' }
        @{ Name = "job-is-a-worker"
           Find = 'elseif ($null -ne $tc) { $worker = New-HordeAbsent -Note ("about a " + $tc.name + " call, not a worker") }'
           Replace = 'elseif ($null -ne $tc) { $worker = New-HordeKnown -Value $tc.id }' }
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
           Find = 'if ($st.turnDurations -eq 0 -and $s.endTurn) {'
           Replace = 'if ($s.endTurn) {' }
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
           Find = 'if ($b["type"] -eq "text" -and $b["text"] -is [string]) { $slot.textChars += $b["text"].Length }'
           Replace = 'if ($b["type"] -eq "text" -and $b["text"] -is [string]) { $slot.textChars += $b["text"].Length + 400 }' }
        @{ Name = "first-line-usage-only"
           Find = '        if ($null -ne $v -and ($null -eq $Max[$k] -or [long]$v -gt $Max[$k])) { $Max[$k] = [long]$v }'
           Replace = '        if ($null -ne $v -and $null -eq $Max[$k]) { $Max[$k] = [long]$v }' }
        @{ Name = "usage-summed-across-lines"
           Find = '        if ($null -ne $v -and ($null -eq $Max[$k] -or [long]$v -gt $Max[$k])) { $Max[$k] = [long]$v }'
           Replace = '        if ($null -ne $v) { $Max[$k] = [long]$Max[$k] + [long]$v }' }
        @{ Name = "notification-by-text"
           Find = '                if ($s.isNote) { $n = Get-ClaudeCodeNotification -Text $s.text }'
           Replace = '                if ($s.text -like "*<task-notification>*") { $n = Get-ClaudeCodeNotification -Text $s.text }' }
        @{ Name = "human-origin-ignored"
           Find = '    if ($Origin -is [System.Collections.IDictionary]) { return ($Origin["kind"] -ceq "task-notification") }'
           Replace = '    if ($Origin -is [System.Collections.IDictionary]) { return $true }' }
        @{ Name = "task-id-text-trusted"
           Find = '                    elseif ($taskOk) { $worker = New-HordeKnown -Value $n.taskId }'
           Replace = '                    elseif ($n.taskId -ne "") { $worker = New-HordeKnown -Value $n.taskId }' }
        @{ Name = "unchecked-task-id-kept"
           Find = '                $keptTask = ""; if ($taskOk) { $keptTask = $n.taskId }'
           Replace = '                $keptTask = $n.taskId' }
        @{ Name = "interim-from-whole-text"
           Find = "interim = ((& `$get ""note"") -match 'may be interim|still running')"
           Replace = "interim = (`$Text -match 'may be interim|still running')" }
    )
}
