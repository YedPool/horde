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
           Find = '            } else { $failures = 0 }'
           Replace = '            } else { }' }
        # --- a clean stop ---
        @{ Name = "stop-file-not-obeyed"
           Find = '            if ([System.IO.File]::Exists($stopPath)) { $stoppedBy = "stop file"; break }'
           Replace = '' }
        @{ Name = "stale-stop-file-obeyed"
           Find = '    if ([System.IO.File]::Exists($stopPath)) { [System.IO.File]::Delete($stopPath);'
           Replace = '    if ($false) { [System.IO.File]::Delete($stopPath);' }
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
    )
}
