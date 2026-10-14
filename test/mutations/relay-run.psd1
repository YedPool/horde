# Mutations of cli/RelayRun.ps1, the loop of horde relay run (relay PR 6). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-run.psd1
# Each breaks one promise of the loop; test\test-relay-channels.ps1 must fail for every one.
@{
    Target = "cli\RelayRun.ps1"
    Suite  = "test\test-relay-channels.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- backoff ---
        @{ Name = "backoff-does-not-double"
           Find = '$base = $base * 2'
           Replace = '$base = $base * 3' }
        @{ Name = "backoff-not-capped"
           Find = '    $base = [System.Math]::Min($base, [double]$Settings.backoffMaxMs)'
           Replace = '' }
        @{ Name = "no-jitter"
           Find = '    $ms = $base - $spread + ($Random.NextDouble() * 2 * $spread)'
           Replace = '    $ms = $base' }
        @{ Name = "failures-never-reset"
           Find = '                $failures = 0'
           Replace = '' }
        # --- a clean stop ---
        @{ Name = "stop-file-not-obeyed"
           Find = '            if (Test-HordeRelayRunStopAsked -Path $stopPath -StartedMs $startedMs) { $stoppedBy = "stop file"; break }'
           Replace = '' }
        @{ Name = "stale-stop-file-obeyed"
           Find = '    if ([System.IO.File]::Exists($stopPath) -and -not (Test-HordeRelayRunStopAsked -Path $stopPath -StartedMs $startedMs)) {'
           Replace = '    if ($false) {' }
        @{ Name = "refused-settings-run-anyway"
           Find = 'if ($settings.state -cne "known") { $null = & $Say ("the run does not start: " + $settings.reason); return'
           Replace = 'if ($false) { $null = & $Say ("the run does not start: " + $settings.reason); return' }
        # --- the turn ---
        @{ Name = "retired-keys-checked-every-turn"
           Find = 'if ($null -eq $ctx -or ([datetime]::UtcNow - $lastCheck).TotalMinutes -ge $set.retiredAgreeCheckMinutes) {'
           Replace = 'if ($true) {' }
        @{ Name = "answer-waits-a-turn"
           Find = '                    $r2 = Invoke-HordeRelayUnfinished -Context $ctx'
           Replace = '                    $r2 = [pscustomobject]@{ value = $null }' }
        # --- review of 48bc492 ---
        @{ Name = "stop-not-asked-between-slices"
           Find = '        if (Test-HordeRelayRunStopAsked -Path $StopPath -StartedMs $StartedMs) { return $true }'
           Replace = '' }
        @{ Name = "slices-as-long-as-the-wait"
           Find = '$script:HordeRelayRunSliceMs = 500'
           Replace = '$script:HordeRelayRunSliceMs = 500000' }
        @{ Name = "empty-turns-not-padded"
           Find = '                if ($empty -and $left -gt 0 -and -not $last) {'
           Replace = '                if ($false) {' }
        @{ Name = "failed-tick-not-counted"
           Find = '                if ($failed -ceq "" -and $ticks.failed) {'
           Replace = '                if ($false) {' }
        @{ Name = "no-floor-under-the-minimum-turn"
           Find = 'default = 1000; min = 50; max = 60000'
           Replace = 'default = 1000; min = 0; max = 60000' }
        @{ Name = "two-runs-share-a-home"
           Find = '([System.IO.FileAccess]::ReadWrite), ([System.IO.FileShare]::None)'
           Replace = '([System.IO.FileAccess]::ReadWrite), ([System.IO.FileShare]::ReadWrite)' }
        # --- a watch waits no longer than a channel asked (the decisions bell, 2026-10-12)
        @{ Name = "watch-ignores-what-a-channel-asked"
           Find = '$in = Receive-HordeRelayInbox -Context $ctx -TimeoutMs $turnWatch'
           Replace = '$in = Receive-HordeRelayInbox -Context $ctx -TimeoutMs $watchMs' }
        @{ Name = "a-channel-can-lengthen-a-watch"
           Find = '-and $AgainMs -gt 0 -and $AgainMs -lt $WatchMs) { return [int]$AgainMs }'
           Replace = '-and $AgainMs -gt 0) { return [int]$AgainMs }' }
        # --- the heartbeat (core/Heartbeat.ps1) ---
        @{ Name = "no-heartbeat"
           Find = '$beat = Write-HordeHeartbeatQuietly @beatArgs'
           Replace = '$beat = New-HordeKnown -Value "written"' }
        @{ Name = "heartbeat-without-start"
           Find = 'ProcessStartedAt = $beatSelf.startedAt; TickSeconds'
           Replace = 'TickSeconds' }
        @{ Name = "heartbeat-failure-ends-the-run"
           Find = 'if ($beat.state -cne "known" -and -not $beatFailed) { $beatFailed = $true; $null = & $Say ('
           Replace = 'if ($beat.state -cne "known") { throw $beat.reason }; if ($false) { $beatFailed = $true; $null = & $Say (' }
        @{ Name = "heartbeat-failure-said-every-turn"
           Find = 'if ($beat.state -cne "known" -and -not $beatFailed) { $beatFailed = $true; $null = & $Say ('
           Replace = 'if ($beat.state -cne "known") { $beatFailed = $true; $null = & $Say (' }
        @{ Name = "tick-ignores-the-backoff"
           Find = '    $wait = [double]$Settings.backoffMaxMs * (1 + [double]$Settings.backoffJitterPercent / 100)'
           Replace = '    $wait = [double]0' }
        @{ Name = "tick-ignores-the-watch"
           Find = '    return [int]([System.Math]::Ceiling(([double]$WatchMs + $wait) / 1000) + 5)'
           Replace = '    return [int]([System.Math]::Ceiling($wait / 1000) + 5)' }
        @{ Name = "tick-ignores-the-jitter"
           Find = '    $wait = [double]$Settings.backoffMaxMs * (1 + [double]$Settings.backoffJitterPercent / 100)'
           Replace = '    $wait = [double]$Settings.backoffMaxMs' }
            # --- review of PR 249 ---
        @{ Name = "unproved-keys-handed-on"
           Find = '    if ("" + $why -eq "") { return $made }'
           Replace = '    return $made' }
        @{ Name = "signing-key-not-tried"
           Find = 'if ("" + $why -ne "") { return ("the signing key "'
           Replace = 'if ($false) { return ("the signing key "' }
        @{ Name = "agreement-keys-not-tried"
           Find = '    foreach ($id in @($Context.openingKeys.Keys)) {'
           Replace = '    foreach ($id in @()) {' }
        @{ Name = "healthy-beat-while-keys-down"
           Find = 'if ($null -eq $ctx) { $beatArgs["Condition"] = "keys-unavailable";'
           Replace = 'if ($false) { $beatArgs["Condition"] = "keys-unavailable";' }
        @{ Name = "keys-opened-unproved"
           Find = 'if ($null -eq $ctx) { $made = @(& $OpenContext $HordeHome $Connection $DecisionsRoot) | Select-Object -Last 1;'
           Replace = 'if ($null -eq $ctx) { $made = New-HordeRelayRunContext -HordeHome $HordeHome -Connection $Connection -DecisionsRoot $DecisionsRoot;' }
    )
}
