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
           Find = '    $base = [System.Math]::Min($base, $most)'
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
           Find = '$beat = Write-HordeHeartbeatQuietly -Path $beatPath -At ([datetime]::UtcNow) -ProcessId $beatSelf.pid -ProcessStartedAt $beatSelf.startedAt -TickSeconds $beatTick -Pass $turns'
           Replace = '$beat = New-HordeKnown -Value "written"' }
        @{ Name = "heartbeat-without-start"
           Find = '-ProcessId $beatSelf.pid -ProcessStartedAt $beatSelf.startedAt -TickSeconds $beatTick -Pass $turns'
           Replace = '-ProcessId $beatSelf.pid -TickSeconds $beatTick -Pass $turns' }
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
        # --- the backoff's cap: a live PC never looks offline on the phone (2026-10-14) ---
        @{ Name = "backoff-cap-not-used-by-the-run"
           Find = '-Random $Random -CapMs (Get-HordeRelayRunBackoffCap -Inbox $in -Context $ctx)'
           Replace = '-Random $Random' }
        @{ Name = "backoff-cap-forgets-the-jitter"
           Find = '[System.Math]::Floor([double]$CapMs / (1 + [double]$Settings.backoffJitterPercent / 100))'
           Replace = '[double]$CapMs' }
        @{ Name = "backoff-cap-past-the-offline-line"
           Find = '$script:HordeRelayRunBackoffCapMs = 45000'
           Replace = '$script:HordeRelayRunBackoffCapMs = 72000' }
        @{ Name = "relay-limit-refusal-capped"
           Find = '@(429, 507) -contains [int]$Inbox.status) { return 0 }'
           Replace = '@(429, 507) -contains [int]$Inbox.status) { return $script:HordeRelayRunBackoffCapMs }' }
        @{ Name = "own-turn-refusal-capped"
           Find = '($Context.refusedWith.ContainsKey(429) -or $Context.refusedWith.ContainsKey(507))) { return 0 }'
           Replace = '($false)) { return 0 }' }
        @{ Name = "cap-from-the-sticky-full-map"
           Find = '$null -ne $Context.PSObject.Properties["refusedWith"] -and ($Context.refusedWith.ContainsKey(429) -or $Context.refusedWith.ContainsKey(507))'
           Replace = '$null -ne $Context.PSObject.Properties["full"] -and $Context.full.Count -gt 0' }
        @{ Name = "nothing-capped"
           Find = '    return $script:HordeRelayRunBackoffCapMs'
           Replace = '    return 0' }
    )
}
