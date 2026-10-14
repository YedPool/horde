# Mutations of the runner's side of the relay's request metrics (cli\RelayMetrics.ps1): one summary
# request a day and none on a restart, the file written, this PC's counts kept across runs. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\cli-relay-metrics.psd1
# test\test-relay-run-send.ps1 must fail for every one (its section on the request metrics, over the
# counting relay). Every find string occurs once.
@{
    Target = "cli\RelayMetrics.ps1"
    Suite  = "test\test-relay-run-send.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "asked-every-turn"
           Find = '    if ($Metrics.lookedOn -ceq $today) { return $null }'
           Replace = '' }
        @{ Name = "asked-again-after-a-restart"
           Find = '    try { if ([System.IO.File]::Exists($path)) { return $null } } catch { return $null }'
           Replace = '' }
        @{ Name = "today-asked-not-yesterday"
           Find = '    $day = Get-HordeRelayMetricsDay -At $when.ToUniversalTime().AddDays(-1)'
           Replace = '    $day = Get-HordeRelayMetricsDay -At $when.ToUniversalTime()' }
        @{ Name = "counts-overwritten-not-added"
           Find = '            foreach ($n in $script:HordeRelayMetricsNames) { $held[$hour][$n] = [long]$held[$hour][$n] + [long]$Metrics.hours[$hour][$n] }'
           Replace = '            foreach ($n in $script:HordeRelayMetricsNames) { $held[$hour][$n] = [long]$Metrics.hours[$hour][$n] }' }
        @{ Name = "a-relay-with-none-still-written"
           Find = '    if ($a.state -ceq "absent") {'
           Replace = '    if ($false) {' }
    )
}
