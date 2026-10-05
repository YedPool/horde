# Mutations of agents/claude-code/Idle.ps1.
# Run: powershell -File tools\Mutate.ps1 -Spec agents\claude-code\test\mutations\idle.psd1
# Each breaks one rule of the idle reader (planning/idle-session-reaper.md 1.3, 1.5, 1.6, P8, P12, P13);
# agents\claude-code\test\test-idle.ps1 must fail for every one.
@{
    Target = "agents\claude-code\Idle.ps1"
    Suite  = "agents\claude-code\test\test-idle.ps1"
    Mutations = @(
        @{ Name = "age-from-mtime"
           Find = 'elseif ($null -eq $st.newest -or $t -gt $st.newest) { $st.newest = $t }'
           Replace = 'elseif ($null -eq $st.newest) { $st.newest = [System.IO.File]::GetLastWriteTimeUtc($Path) }' }
        @{ Name = "pending-count-ignored"
           Find = 'elseif ($p -is [int] -or $p -is [long]) { $st.pending = [int]$p }'
           Replace = 'elseif ($p -is [int] -or $p -is [long]) { $st.pending = 0 }' }
        @{ Name = "task-starts-not-read"
           Find = 'if ($m.Success) { $st.tasks[$m.Groups[1].Value] = $s.kind; break }'
           Replace = 'if ($false) { break }' }
        @{ Name = "unrecognised-task-finished"
           Find = 'if ($final) { $St.unknownTasks.Remove($n.taskId) } else { $St.unknownTasks[$n.taskId] = $n.status }'
           Replace = '$St.unknownTasks.Remove($n.taskId)' }
        @{ Name = "interim-note-is-final"
           Find = '(@("final", "none") -ccontains $n.noteKind)'
           Replace = '$true' }
        @{ Name = "pasted-notification-counts"
           Find = 'if ($cur -and (Test-ClaudeCodeNotificationOrigin -Origin $v["origin"])) {'
           Replace = 'if ($cur -and $true) {' }
        @{ Name = "recurring-cron-as-one-shot"
           Find = 'if ($st.crons.ContainsKey($tid) -and -not $st.crons[$tid].recurring) { $st.crons.Remove($tid) }'
           Replace = 'if ($st.crons.ContainsKey($tid)) { $st.crons.Remove($tid) }' }
        @{ Name = "tool-calls-before-since-count"
           Find = 'if (-not $cur -or $in -isnot [System.Collections.IDictionary]) { continue }'
           Replace = 'if ($in -isnot [System.Collections.IDictionary]) { continue }' }
        @{ Name = "cron-never-expires"
           Find = 'Where-Object { -not ($st.crons[$_].recurring -and $null -ne $st.crons[$_].at -and $st.crons[$_].at -lt $expiry) }'
           Replace = 'Where-Object { $true }' }
        @{ Name = "scheduled-fire-allowed-at-boundary"
           Find = '$script:ClaudeCodeBoundaryKinds = @("system/away_summary",'
           Replace = '$script:ClaudeCodeBoundaryKinds = @("system/scheduled_task_fire", "system/away_summary",' }
        @{ Name = "unknown-metadata-allowed-at-boundary"
           Find = 'if ($null -eq $raw) { $allowed = ($script:ClaudeCodeKnownKinds -ccontains $kind) }'
           Replace = 'if ($null -eq $raw) { $allowed = $true }' }
        @{ Name = "enqueue-ignored"
           Find = 'if ($op -ceq "enqueue") { $st.queued++ }'
           Replace = 'if ($op -ceq "enqueue") { }' }
        @{ Name = "queue-before-since-counts"
           Find = '        if (-not $cur) { return }'
           Replace = '        if ($false) { return }' }
        @{ Name = "zone-less-time-accepted"
           Find = 'if ($null -eq $t) { $st.badTime = "line " + $ln + " has a time with no zone" }'
           Replace = 'if ($null -eq $t) { }' }
        @{ Name = "future-time-accepted"
           Find = 'if (($st.newest - $Now).TotalSeconds -gt $script:HordeClockSkewSeconds) {'
           Replace = 'if ($false) {' }
        @{ Name = "torn-tail-is-known"
           Find = 'if ($read.tornTail -gt 0) { $boundary = New-HordeUnknown -Reason "the last line is still being written" }'
           Replace = 'if ($false) { }' }
        @{ Name = "failed-taskstop-finishes"
           Find = 'if (-not $err) { $st.tasks.Remove($st.stops[$id]) }'
           Replace = '$st.tasks.Remove($st.stops[$id])' }
        @{ Name = "failed-croncreate-creates"
           Find = '                    if (-not $err) {'
           Replace = '                    if ($true) {' }
        @{ Name = "version-survey-off"
           Find = 'if ($script:ClaudeCodeKnownKinds -cnotcontains $kind -and -not $st.versions[$vkey].unrecognised.Contains($kind)) {'
           Replace = 'if ($false) {' }
        @{ Name = "since-ignored"
           Find = '$cur = ($null -eq $t) -or ($t -ge $Since)'
           Replace = '$cur = $true' }
        @{ Name = "stop-only-call-is-a-wake"
           Find = 'elseif ($name -ceq "ScheduleWakeup" -and ($in.ContainsKey("delaySeconds") -or $in.ContainsKey("prompt"))) {'
           Replace = 'elseif ($name -ceq "ScheduleWakeup") {' }
        @{ Name = "wake-delay-ignored"
           Find = '$due = New-HordeKnown -Value $t.AddSeconds([double]$d)'
           Replace = '$due = New-HordeKnown -Value $t' }
        @{ Name = "tool-calls-survive-turn-end"
           Find = '$st.blockers.Clear(); $st.tools.Clear()'
           Replace = '$st.blockers.Clear()' }
        @{ Name = "no-turn-end-is-a-boundary"
           Find = 'elseif (-not $st.hasEnd) { $boundary = New-HordeKnown -Value $false; $blockers = @("no turn end") }'
           Replace = 'elseif (-not $st.hasEnd) { $boundary = New-HordeKnown -Value $true }' }
        @{ Name = "tool-result-closes-nothing"
           Find = '                $st.tools.Remove($id)'
           Replace = '                $null = 0' }
    )
}
