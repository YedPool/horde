# Mutations of core/Metrics.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\metrics.psd1
# Each breaks one rule an instrument exists for; test\test-metrics.ps1 must fail for every one.
# Plan step M2 moved the rules into the running totals (Add-HordeMetricsRecord); each mutation below
# breaks the same rule M1's spec broke, at its new place.
@{
    Target = "core\Metrics.ps1"
    Suite  = "test\test-metrics.ps1"
    Mutations = @(
        @{ Name = "wait-ignores-tool-calls"
           Find = '$isWait = ($r.toolCallCount -eq 0 -and $r.textChars -lt $acc.maxChars'
           Replace = '$isWait = ($r.textChars -lt $acc.maxChars' }
        @{ Name = "wait-ignores-length"
           Find = '$isWait = ($r.toolCallCount -eq 0 -and $r.textChars -lt $acc.maxChars'
           Replace = '$isWait = ($r.toolCallCount -eq 0' }
        @{ Name = "wait-trigger-not-reset"
           Find = '            $acc.trigger = $null'
           Replace = '            $null = 0' }
        @{ Name = "wait-tool-result-not-a-trigger"
           Find = '$acc.trigger = $r; $id = "$($r.toolCallId)"'
           Replace = '$id = "$($r.toolCallId)"' }
        @{ Name = "wait-any-input-triggers"
           Find = '$trigger.kind -eq "input" -and $trigger.source -eq "notification" -and $trigger.interim'
           Replace = '$trigger.kind -eq "input" -and $trigger.interim'
           Expect = "survives"
           Reason = "Redundant since the two rules of 2026-10-02: a user input both sets personSpoke and carries interim false, so dropping the source check changes no outcome; kept to say so where a reader can disagree." }
        @{ Name = "wait-context-omits-cache-read"
           Find = '$wait.contextTokens += ($uv.input + $uv.cacheRead + $uv.cacheWrite)'
           Replace = '$wait.contextTokens += ($uv.input + $uv.cacheWrite)' }
        @{ Name = "wait-unproved-given-to-a-job"
           Find = '            elseif ($w.state -eq "absent") { $wait.jobs++ }'
           Replace = '            elseif ($true) { $wait.jobs++ }' }
        @{ Name = "landed-job-counted-as-worker"
           Find = 'elseif ($r.worker.state -eq "absent") { $acc.landed.jobChars += $r.chars; $acc.landed.jobCount++ }'
           Replace = 'elseif ($r.worker.state -eq "absent") { Add-HordeLandedWorker -Landed $acc.landed -Id "job" -Chars ([long]$r.chars) -How "notification" }' }
        @{ Name = "landed-unproved-tool-result-dropped"
           Find = 'else { $acc.landed.unattributedChars += [long]$r.chars; $acc.landed.unattributedCount++ }'
           Replace = 'else { }' }
        @{ Name = "landed-ordinary-tool-results-counted"
           Find = '            if ($r.worker.state -ne "absent") {'
           Replace = '            if ($r.worker.state -eq "absent") { Add-HordeLandedWorker -Landed $acc.landed -Id "tool" -Chars ([long]$r.chars) -How "toolResult" }; if ($r.worker.state -ne "absent") {' }
        @{ Name = "duplicate-calls-summed"
           Find = 'if (-not $acc.seen.Add("$($r.id)")) { $acc.duplicates++; return }'
           Replace = '[void]$acc.seen.Add("$($r.id)")' }
        @{ Name = "missing-usage-is-zero"
           Find = 'if ($acc.tokensMissing -gt 0) { $s.tokens = New-HordeUnknown'
           Replace = 'if ($false) { $s.tokens = New-HordeUnknown' }
        @{ Name = "partial-cost-is-a-total"
           Find = 'if ($acc.costBad -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "open-tool-call-is-instant"
           Find = 'Resolve-HordeToolDuration -Acc $acc -Call $tc -EndTicks $lastTicks -Returned $false'
           Replace = 'Resolve-HordeToolDuration -Acc $acc -Call $tc -EndTicks $tc.ticks -Returned $false' }
        @{ Name = "open-tool-call-forgotten"
           Find = '        foreach ($tc in $list) { $acc.open++;'
           Replace = '        foreach ($tc in @()) { $acc.open++;' }
        @{ Name = "result-before-its-call-not-paired"
           Find = 'if ($acc.resultTicks.TryGetValue($id, [ref]$end)) {'
           Replace = 'if ($false) {' }
        @{ Name = "longest-tool-tie-goes-to-the-later"
           Find = '($sec -eq $b.sec -and $Call.index -lt $b.index)'
           Replace = '($sec -eq $b.sec -and $Call.index -gt $b.index)' }
        @{ Name = "gap-from-first-pair-only"
           Find = 'if ($null -eq $best -or $g -gt $best) {'
           Replace = 'if ($null -eq $best) {' }
        @{ Name = "gap-unsorted"
           Find = '    [Array]::Sort($sorted)'
           Replace = '' }
        @{ Name = "gap-after-the-first-of-a-time"
           Find = '$last = ($sorted[$bestAt] -ne $at)'
           Replace = '$last = $false' }
        @{ Name = "gap-tie-not-replayed"
           Find = '    if ($kinds.Count -gt 1) {'
           Replace = '    $pick = $tied[$tied.Count - 1]; if ($false) {' }
        @{ Name = "model-is-the-first-not-the-most"
           Find = '@($knownModels | Sort-Object -Property @{ Expression = { $models[$_] }; Descending = $true }, @{ Expression = { $_ } })[0]'
           Replace = '@($knownModels)[@($knownModels).Count - 1]' }
        @{ Name = "partial-wait-total-is-known"
           Find = '        if ($wait.callsWithoutUsage -gt 0) { $wait[$k] = New-HordeUnknown'
           Replace = '        if ($false) { $wait[$k] = New-HordeUnknown' }
        @{ Name = "negative-duration-counted"
           Find = '    if ($sec -lt 0) { $Acc.backwards++; return }'
           Replace = '' }
        @{ Name = "person-speaking-ignored"
           Find = '    if ($r.kind -eq "input" -and $r.source -eq "user") { $acc.personSpoke = $true }'
           Replace = '' }
        @{ Name = "final-notification-waited-on"
           Find = ' -and $trigger.interim -eq $true -and -not $acc.personSpoke)'
           Replace = ' -and -not $acc.personSpoke)' }
        @{ Name = "unrecognised-note-not-counted"
           Find = '$r.noteKind -ceq "unrecognised") { $acc.unrecognised++ }'
           Replace = '$r.noteKind -ceq "unrecognised") { }' }
        @{ Name = "reply-to-unrecognised-not-counted"
           Find = '$trigger.noteKind -ceq "unrecognised") { $wait.afterUnrecognisedNote++ }'
           Replace = '$trigger.noteKind -ceq "unrecognised") { }' }
        @{ Name = "window-ignored"
           Find = 'if (($null -ne $acc.from -and $r.ts -lt $acc.from) -or ($null -ne $acc.to -and $r.ts -gt $acc.to)) { return }'
           Replace = '' }
    )
}
