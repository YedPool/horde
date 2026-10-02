# Mutations of core/Metrics.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\metrics.psd1
# Each breaks one rule an instrument exists for; test\test-metrics.ps1 must fail for every one.
@{
    Target = "core\Metrics.ps1"
    Suite  = "test\test-metrics.ps1"
    Mutations = @(
        @{ Name = "wait-ignores-tool-calls"
           Find = '$isWait = ($r.toolCallCount -eq 0 -and $r.textChars -lt $MaxChars'
           Replace = '$isWait = ($r.textChars -lt $MaxChars' }
        @{ Name = "wait-ignores-length"
           Find = '$isWait = ($r.toolCallCount -eq 0 -and $r.textChars -lt $MaxChars'
           Replace = '$isWait = ($r.toolCallCount -eq 0' }
        @{ Name = "wait-trigger-not-reset"
           Find = '        $trigger = $null'
           Replace = '        $null = 0' }
        @{ Name = "wait-tool-result-not-a-trigger"
           Find = 'if ($r.kind -eq "input" -or $r.kind -eq "toolResult") { $trigger = $r; continue }'
           Replace = 'if ($r.kind -eq "input") { $trigger = $r; continue }; if ($r.kind -eq "toolResult") { continue }' }
        @{ Name = "wait-any-input-triggers"
           Find = '$trigger.kind -eq "input" -and $trigger.source -eq "notification")'
           Replace = '$trigger.kind -eq "input")' }
        @{ Name = "wait-context-omits-cache-read"
           Find = '$wait.contextTokens += ($uv.input + $uv.cacheRead + $uv.cacheWrite)'
           Replace = '$wait.contextTokens += ($uv.input + $uv.cacheWrite)' }
        @{ Name = "wait-unproved-given-to-a-job"
           Find = 'elseif ($w.state -eq "absent") { $wait.jobs++ }'
           Replace = 'elseif ($true) { $wait.jobs++ }' }
        @{ Name = "landed-job-counted-as-worker"
           Find = 'elseif ($r.worker.state -eq "absent") { $landed.jobChars += $r.chars; $landed.jobCount++ }'
           Replace = 'elseif ($r.worker.state -eq "absent") { & $addWorker "job" ([long]$r.chars) "notification" }' }
        @{ Name = "landed-unproved-tool-result-dropped"
           Find = 'else { $landed.unattributedChars += [long]$r.chars; $landed.unattributedCount++ }'
           Replace = 'else { }' }
        @{ Name = "landed-ordinary-tool-results-counted"
           Find = 'elseif ($r.kind -eq "toolResult" -and $r.worker.state -ne "absent") {'
           Replace = 'elseif ($r.kind -eq "toolResult") { if ($r.worker.state -eq "absent") { & $addWorker "tool" ([long]$r.chars) "toolResult"; continue }' }
        @{ Name = "duplicate-calls-summed"
           Find = 'if ($seen.Add("$($r.id)")) { [void]$calls.Add($r) } else { $dup++ }'
           Replace = '[void]$seen.Add("$($r.id)"); [void]$calls.Add($r)' }
        @{ Name = "missing-usage-is-zero"
           Find = 'if ($missing -gt 0) { return (New-HordeUnknown -Reason ("" + $missing + " of " + @($Calls).Count + " calls carry no usage")) }'
           Replace = '' }
        @{ Name = "partial-cost-is-a-total"
           Find = 'if ($bad -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "open-tool-call-is-instant"
           Find = 'else { $open++; $sec = ($timed[$timed.Count - 1].ts - $tc.ts).TotalSeconds; $returned = $false }'
           Replace = 'else { $open++; $sec = 0; $returned = $false }' }
        @{ Name = "gap-from-first-pair-only"
           Find = 'if ($null -eq $best -or $g -gt $best.seconds) {'
           Replace = 'if ($null -eq $best) {' }
        @{ Name = "model-is-the-first-not-the-most"
           Find = '@($knownModels | Sort-Object -Property @{ Expression = { $models[$_] }; Descending = $true }, @{ Expression = { $_ } })[0]'
           Replace = '@($knownModels)[@($knownModels).Count - 1]' }
    )
}
