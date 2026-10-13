# Mutations of core/WakeTell.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-tell.psd1
# Each breaks one thing the tell sender exists for - one mail a condition, at most six an hour, the rest
# journaled as suppressed, the text saying it is automated, shadow posting nothing, a failed post tried
# again and nothing claimed that did not happen; test\test-wake-tell.ps1 must fail for every one.
@{
    Target = "core\WakeTell.ps1"
    Suite  = "test\test-wake-tell.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-fleet-notice-counts-against-the-sessions-budget"
           Find = '-and "$(Get-HordeWakeTellClass $_)" -ceq $class }).Count'
           Replace = '}).Count' }
        @{ Name = "a-fleet-notice-waits-its-turn-in-the-list"
           Find = '$ordered = @(@($Conditions | Where-Object { $null -ne $_ -and "$($_.subject)" -ceq "" }) + @($Conditions | Where-Object { $null -ne $_ -and "$($_.subject)" -cne "" }))'
           Replace = '$ordered = @($Conditions)' }
        @{ Name = "every-tell-is-a-fleet-notice"
           Find = 'if ("$($c.subject)" -ceq "") { $class = "fleet" }'
           Replace = '$class = "fleet"' }
        @{ Name = "the-class-of-a-tell-is-not-saved"
           Find = 'state = "$($Told[$_].state)"; class = (Get-HordeWakeTellClass $Told[$_]) } })'
           Replace = 'state = "$($Told[$_].state)" } })' }
        @{ Name = "told-again-every-pass"
           Find = 'if ($next[$id].state -cne "failed" -or ($Now - $next[$id].at).TotalSeconds -lt $Settings.retrySeconds) { continue }'
           Replace = '' }
        @{ Name = "failed-post-never-tried-again"
           Find = 'if ($next[$id].state -cne "failed" -or ($Now - $next[$id].at).TotalSeconds -lt $Settings.retrySeconds) { continue }'
           Replace = 'continue' }
        @{ Name = "failed-post-tried-again-at-once"
           Find = 'if ($next[$id].state -cne "failed" -or ($Now - $next[$id].at).TotalSeconds -lt $Settings.retrySeconds) { continue }'
           Replace = 'if ($next[$id].state -cne "failed") { continue }' }
        @{ Name = "no-rate-limit"
           Find = 'if ($sentLately -ge [int]$Settings.maxTellsPerHour) {'
           Replace = 'if ($false) {' }
        @{ Name = "rate-limit-of-seven"
           Find = 'maxTellsPerHour = 6'
           Replace = 'maxTellsPerHour = 7' }
        @{ Name = "rate-limit-never-forgets-an-hour"
           Find = '-and ($Now - $_.at).TotalSeconds -lt 3600 -and'
           Replace = '-and' }
        @{ Name = "suppressed-tells-count-against-the-limit"
           Find = '$next.Values | Where-Object { ($_.state -ceq "told" -or $_.state -ceq "would-tell") -and'
           Replace = '$next.Values | Where-Object { $true -and' }
        @{ Name = "shadow-tells"
           Find = 'if ($Shadow) { $next[$id] = [pscustomobject]@{ at = $Now; state = "would-tell"; class = $class };'
           Replace = 'if ($false) { $next[$id] = [pscustomobject]@{ at = $Now; state = "would-tell"; class = $class };' }
        @{ Name = "text-does-not-say-it-is-automated"
           Find = '$body = "$($Settings.prefix)" + $c.text'
           Replace = '$body = $c.text' }
        @{ Name = "prefix-names-nobody"
           Find = 'prefix = "AUTOMATED, from the wake watcher: "'
           Replace = 'prefix = "NOTE: "' }
        @{ Name = "failed-post-claimed-as-told"
           Find = 'if ((Test-HordeAnswer $took) -and $took.state -ceq "known") {'
           Replace = 'if ($true) {' }
        @{ Name = "nobody-to-tell-is-a-post-anyway"
           Find = 'if ($Warchief -ceq "") { $next[$id] ='
           Replace = 'if ($false) { $next[$id] =' }
        @{ Name = "same-id-for-every-session"
           Find = '("$($Condition.subject)").ToLowerInvariant() + "`n" + $Condition.instance))'
           Replace = '"`n" + $Condition.instance))' }
        @{ Name = "same-id-for-every-instance"
           Find = '("$($Condition.subject)").ToLowerInvariant() + "`n" + $Condition.instance))'
           Replace = '("$($Condition.subject)").ToLowerInvariant()))' }
        @{ Name = "what-was-told-never-forgotten"
           Find = '-and ($Now - $was.at).TotalSeconds -le $Settings.keepSeconds) { $next["$k"] = $was }'
           Replace = ') { $next["$k"] = $was }' }
        @{ Name = "tell-wears-the-restore-sources-name"
           Find = '$script:HordeWakeTellFrom = "horde-wake-watcher"'
           Replace = '$script:HordeWakeTellFrom = ""' }
        @{ Name = "a-kind-nobody-declared-accepted"
           Find = 'if ($script:HordeWakeTellKinds -cnotcontains $Kind) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "tell-state-saved-under-another-mode"
           Find = 'Write-HordeWakeFile -Path (Get-HordeWakeStateFile -Name $Name -Mode $Mode -Shadow:$Shadow -HordeHome $HordeHome) -Text'
           Replace = 'Write-HordeWakeFile -Path (Get-HordeWakeStateFile -Name $Name -HordeHome $HordeHome) -Text' }
    )
}
