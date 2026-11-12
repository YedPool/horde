# Mutations of the blind-look counts and spells in core/WakeRun.ps1 (T-0116). Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-blind-run.psd1
# Each breaks one rule of how a tick keeps them; test\test-wake-blind.ps1 must fail for every one.
@{
    Target = "core\WakeRun.ps1"
    Suite  = "test\test-wake-blind.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "the-pass-is-not-told-its-spells"
           Find = '-AsleepUnknown $asleepUnknown -Blind $Run.blind'
           Replace = '-AsleepUnknown $asleepUnknown' }
        @{ Name = "the-spells-are-not-kept-between-ticks"
           Find = '$Run.blind = $blindNow.seen'
           Replace = '$Run.blind = @{}' }
        @{ Name = "the-spell-lines-are-not-journaled"
           Find = 'foreach ($e in @($blindNow.entries)) { [void]$entries.Add($e) }'
           Replace = '' }
        @{ Name = "looks-are-not-counted"
           Find = '$Run.counts.looks = [long]$Run.counts.looks + [long]$result.looks'
           Replace = '$Run.counts.looks = [long]$Run.counts.looks + 0' }
        @{ Name = "blind-looks-are-not-counted"
           Find = '$Run.counts.blindLooks = [long]$Run.counts.blindLooks + [long]$result.blindLooks.Count'
           Replace = '$Run.counts.blindLooks = [long]$Run.counts.blindLooks + 0' }
        @{ Name = "every-pass-is-a-blind-pass"
           Find = 'if ($Run.blind.Count -gt 0) { $Run.counts.blindPasses'
           Replace = 'if ($true) { $Run.counts.blindPasses' }
        @{ Name = "only-a-pass-with-a-blind-look-is-a-blind-pass"
           Find = 'if ($Run.blind.Count -gt 0) { $Run.counts.blindPasses'
           Replace = 'if ($result.blindLooks.Count -gt 0) { $Run.counts.blindPasses' }
        @{ Name = "unreadable-counts-not-said"
           Find = 'elseif ($savedCounts.state -ceq "unknown") {'
           Replace = 'elseif ($false) {' }
        @{ Name = "unreadable-listing-forgets-spells-at-tick"
           Find = '$listedForBlind = $null'
           Replace = '$listedForBlind = @()' }
        @{ Name = "a-failed-counts-write-is-not-said"
           Find = 'if ($countsFailed -is [string]) {'
           Replace = 'if ($false) {' }
        @{ Name = "passes-are-not-counted"
           Find = '$Run.counts.passes = [long]$Run.counts.passes + 1'
           Replace = '$Run.counts.passes = [long]$Run.counts.passes + 0' }
        @{ Name = "the-counts-are-not-read-back-at-start"
           Find = 'if ($savedCounts.state -ceq "known") {'
           Replace = 'if ($false) {' }
        @{ Name = "a-restart-forgets-when-the-counting-began"
           Find = 'since = $savedCounts.value.since;'
           Replace = 'since = $startedAt;' }
        @{ Name = "the-counts-are-not-written-with-the-heartbeat"
           Find = ' -Counts $Run.counts'
           Replace = '' }
        @{ Name = "the-counts-are-always-read-from-the-live-files"
           Find = 'Read-HordeWakeCounts -Mode $word'
           Replace = 'Read-HordeWakeCounts -Mode "live"' }
    )
}
