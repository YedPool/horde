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
           Find = '        if ($st.sawRecord) { continue }'
           Replace = '        if ($false) { continue }' }
        @{ Name = "repeated-token-count-is-a-call"
           Find = 'if ($key -ne "" -and $key -eq $prevTotal) { continue }'
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
    )
}
