# Mutations of where the run counts its side of the relay's request metrics (cli\RelayRun.ps1). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\cli-relay-run-metrics.psd1
# test\test-relay-run-send.ps1 must fail for every one (its section on the request metrics). Every find
# string occurs once.
@{
    Target = "cli\RelayRun.ps1"
    Suite  = "test\test-relay-run-send.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "retry-never-counted"
           Find = '            if ($failures -gt 0) { Add-HordeRelayRunMetric -Metrics $metrics -Name "retries" }'
           Replace = '' }
        @{ Name = "no-daily-pull"
           Find = '            $pulled = Invoke-HordeRelayRunMetricsDay -Metrics $metrics -Connection $Connection'
           Replace = '            $pulled = $null' }
        @{ Name = "empty-polls-not-counted"
           Find = '                    if ($empty) { Add-HordeRelayRunMetric -Metrics $metrics -Name "emptyPolls" }'
           Replace = '' }
        @{ Name = "backoff-not-counted"
           Find = '                    Add-HordeRelayRunMetric -Metrics $metrics -Name "backoffWaits"'
           Replace = '' }
        @{ Name = "counts-not-saved-at-the-end"
           Find = '        if ($null -ne $metrics) { Save-HordeRelayRunMetrics -Metrics $metrics }'
           Replace = '' }
    )
}
