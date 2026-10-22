# Mutations of the fleet meter's limit watch (fleet-metrics/watch-limits.mjs): the decision to alert. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-meter-watch.psd1
# test\test-fleet-meter.ps1 (the meter's node tests, on synthetic transcripts) must fail for every one.
# Every find string occurs once.
@{
    Target = "fleet-metrics\watch-limits.mjs"
    Suite  = "test\test-fleet-meter.ps1"
    Mutations = @(
        @{ Name = "no-five-minute-wait"
           Find = 'age <= ALERT_AFTER_MS || '
           Replace = '' }
        @{ Name = "one-minute-wait-instead-of-five"
           Find = 'export const ALERT_AFTER_MS = 5 * 60 * 1000;'
           Replace = 'export const ALERT_AFTER_MS = 1 * 60 * 1000;' }
        @{ Name = "stale-hit-still-alerts"
           Find = ' || age >= STALE_HIT_MS'
           Replace = '' }
        @{ Name = "alerted-hit-alerts-again"
           Find = 'if (existing && existing.alerted_at != null) continue;'
           Replace = '' }
        @{ Name = "alerted-never-recorded"
           Find = 'for (const i of pending) store.markAlerted(i.hit.hit_uuid, now);'
           Replace = '' }
        @{ Name = "failed-send-counts-as-told"
           Find = 'if (r.ok) {'
           Replace = 'if (true) {' }
        @{ Name = "first-run-not-silent"
           Find = 'if (firstRun && age > BASELINE_MS) {'
           Replace = 'if (false) {' }
        @{ Name = "silent-baseline-window-too-long"
           Find = 'export const BASELINE_MS = 30 * 60 * 1000;'
           Replace = 'export const BASELINE_MS = 3 * 3600 * 1000;' }
        @{ Name = "first-run-never-remembered"
           Find = 'if (!dryRun && firstRun) store.setState(FIRST_RUN_KEY, now);'
           Replace = '' }
        @{ Name = "silent-baseline-not-flagged"
           Find = 'store.markAlerted(last.hit_uuid, now, true);'
           Replace = 'store.markAlerted(last.hit_uuid, now, false);' }
        @{ Name = "long-list-not-cut"
           Find = "if (items.length > MAX_LINES) lines.push("
           Replace = "if (false) lines.push(" }
        @{ Name = "dry-run-writes-rows"
           Find = 'if (!dryRun) store.apply({ tokens_limits: [row] }, null);'
           Replace = 'store.apply({ tokens_limits: [row] }, null);' }
        @{ Name = "old-transcripts-opened"
           Find = 'if (now - st.mtimeMs > RECENT_MS || st.size === 0) continue;'
           Replace = 'if (st.size === 0) continue;' }
    )
}
