# Mutations of agents/codex/Transcript.ps1.
# Run: powershell -File tools\Mutate.ps1 -Spec agents\codex\test\mutations\transcript.psd1
# Each breaks one rule the adapter carries; agents\codex\test\test-transcript.ps1 must fail for every one.
@{
    Target = "agents\codex\Transcript.ps1"
    Suite  = "agents\codex\test\test-transcript.ps1"
    Mutations = @(
        @{ Name = "cached-counted-as-uncached"
           Find = 'return (New-HordeUsage -Uncached ($inTok - $cached)'
           Replace = 'return (New-HordeUsage -Uncached ($inTok)' }
        @{ Name = "turn-aborted-not-a-turn-end"
           Find = 'if ($type -eq "event_msg" -and ($ptype -eq "task_complete" -or $ptype -eq "turn_aborted")) {'
           Replace = 'if ($type -eq "event_msg" -and ($ptype -eq "task_complete")) {' }
        @{ Name = "token-count-counted-too"
           Find = '            if ($sawRecord) { return }'
           Replace = '            if ($false) { return }' }
        @{ Name = "repeated-token-count-is-a-call"
           Find = 'if ($key -ne "" -and $key -eq $st.prevTotal) { return }'
           Replace = '' }
        @{ Name = "response-item-user-is-input"
           Find = '            if ($ptype -eq "message" -and $p["role"] -eq "assistant") {'
           Replace = '            if ($ptype -eq "message" -and $p["role"] -eq "user") { [void]$out.Add((New-HordeTranscriptRecord -Kind "input" -Role "user" -Ts $ts -Line $ln -Fields @{ source = "user"; chars = 1; taskId = ""; toolCallId = ""; interim = $false; worker = $userAbsent })); return }
            if ($ptype -eq "message" -and $p["role"] -eq "assistant") {' }
        @{ Name = "items-not-carried-to-their-turn"
           Find = '        if ($turn -eq "") { $turn = $st.turn }'
           Replace = '' }
        @{ Name = "model-not-from-turn"
           Find = 'if ($turnModel.ContainsKey($turn)) { $model = New-HordeKnown -Value $turnModel[$turn] }'
           Replace = '' }
        @{ Name = "outputs-not-paired"
           Find = 'if ($ptype -like "*_call_output" -and "$($p["call_id"])" -ne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "tool-failure-claimed-false"
           Find = 'isError = $errorUnsaid; chars = $chars'
           Replace = 'isError = (New-HordeKnown -Value $false); chars = $chars' }
        @{ Name = "no-split-read-as-unknown"
           Find = '-Split (New-HordeAbsent -Note "this harness does not split cache writes by lifetime"))'
           Replace = '-Split (New-HordeUnknown -Reason "not split"))' }
        @{ Name = "missing-usage-field-is-zero"
           Find = '        if ($null -eq $U[$k]) { return (New-HordeUnknown -Reason ("the usage has no " + $k)) }'
           Replace = '        if ($false) { }' }
        @{ Name = "rate-limit-only-token-count-is-a-call"
           Find = '            if ($last -isnot [System.Collections.IDictionary]) { return }'
           Replace = ''  }
        @{ Name = "fallback-model-from-the-line"
           Find = 'if ($finalModel.ContainsKey($turn)) { $model = New-HordeKnown -Value $finalModel[$turn] }'
           Replace = 'if ($turnModel.ContainsKey($turn)) { $model = New-HordeKnown -Value $turnModel[$turn] }'
           Expect = "survives"
           Reason = "M1 priced a token_count call with the model its turn had at the end of the file, and plan step M2 keeps that; in every rollout measured, a turn_context comes before the token_count lines of its turn, so the map at the line and the map at the end agree. Kept so the choice is written where a reader can disagree." }
    )
}
