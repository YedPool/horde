# Mutations of agents/codex/Idle.ps1.
# Run: powershell -File tools\Mutate.ps1 -Spec agents\codex\test\mutations\idle.psd1
# Each breaks one rule of the Codex idle reader; agents\codex\test\test-idle.ps1 must fail for every one.
@{
    Target = "agents\codex\Idle.ps1"
    Suite  = "agents\codex\test\test-idle.ps1"
    Mutations = @(
        @{ Name = "any-end-closes-every-turn"
           Find = '$st.turns.Remove($turn)'
           Replace = '$st.turns.Clear()' }
        @{ Name = "abort-is-not-an-end"
           Find = 'if ($kind -ceq "event_msg/task_complete" -or $kind -ceq "event_msg/turn_aborted") {'
           Replace = 'if ($kind -ceq "event_msg/task_complete") {' }
        @{ Name = "lines-after-end-allowed"
           Find = 'if ($st.hasEnd -and $st.turns.Count -eq 0 -and -not $st.blockers.Contains($kind)) { [void]$st.blockers.Add($kind) }'
           Replace = 'if ($false) { }' }
        @{ Name = "call-output-ignored"
           Find = 'elseif ($kind -ceq "response_item/function_call_output") { $st.tools.Remove("$($p["call_id"])") }'
           Replace = 'elseif ($false) { }' }
        @{ Name = "zone-less-time-accepted"
           Find = 'if ($null -eq $t) { $st.badTime = "line " + $ln + " has a time with no zone" }'
           Replace = 'if ($null -eq $t) { }' }
        @{ Name = "future-time-accepted"
           Find = 'if (($st.newest - $Now).TotalSeconds -gt $script:HordeClockSkewSeconds) {'
           Replace = 'if ($false) {' }
        @{ Name = "torn-tail-is-known"
           Find = 'if ($read.tornTail -gt 0) { $boundary = New-HordeUnknown -Reason "the last line is still being written" }'
           Replace = 'if ($false) { }' }
        @{ Name = "version-survey-off"
           Find = 'if ($script:CodexKnownKinds -cnotcontains $kind -and -not $st.versions[$st.version].unrecognised.Contains($kind)) {'
           Replace = 'if ($false) {' }
        @{ Name = "open-turn-is-a-boundary"
           Find = 'else { $boundary = New-HordeKnown -Value ($st.turns.Count -eq 0 -and $blockers.Count -eq 0) }'
           Replace = 'else { $boundary = New-HordeKnown -Value ($blockers.Count -eq 0 -or $true) }' }
    )
}
