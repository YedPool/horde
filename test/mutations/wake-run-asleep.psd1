# Mutations of core/WakeRun.ps1's reading of the sessions asleep in a hibernation. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-run-asleep.psd1
# The rest of core/WakeRun.ps1 is its own spec's; test\test-fleet-hibernate.ps1 must fail a check for
# every one of these.
@{
    Target = "core\WakeRun.ps1"
    Suite  = "test\test-fleet-hibernate.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "sleepers-not-read"
           Find = 'if ((Test-HordeAnswer $sleepers) -and $sleepers.state -ceq "known") {'
           Replace = 'if ($false) {' }
        @{ Name = "unknown-sleepers-ignored"
           Find = 'elseif (Test-HordeAnswer $sleepers) { $asleepUnknown = "$($sleepers.reason)" }'
           Replace = 'elseif (Test-HordeAnswer $sleepers) { }' }
        @{ Name = "shadow-and-proof-watchers-clear-markers"
           Find = ' -KeepMarkers:($mode -cne "live") })'
           Replace = ' })' }
        @{ Name = "skipped-records-not-journaled"
           Find = 'foreach ($line in @($skippedRecords.Value)) {'
           Replace = 'foreach ($line in @()) {' }
    )
}
