# Mutations of the metrics object's book (relays/cloudflare/worker/metrics-book.js): rows added exactly,
# its own line, one account's summary, and the daily deletion past the retention. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-metrics-book.psd1
# relays\cloudflare\test\test-cloudflare-metrics.ps1 must fail for every one (part 1 over a storage in
# memory; the own line again in part 2, against a dev). Every find string occurs once.
@{
    Target = "relays\cloudflare\worker\metrics-book.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-metrics.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-flush-overwrites-the-row"
           Find = 'for (const [k, c] of part) out[prefix + k] = sum(held.get(prefix + k), c);'
           Replace = 'for (const [k, c] of part) out[prefix + k] = sum(undefined, c);' }
        @{ Name = "failing-object-keeps-the-batch"
           Find = '    if (failFlush) throw new Error("the metrics object refuses flushes (test)");'
           Replace = '    if (failFlush) { /* taken */ }' }
        @{ Name = "flushes-not-on-the-own-line"
           Find = '    await this.own(now, { flushes: 1, increments: b.increments });'
           Replace = '    await this.own(now, { increments: b.increments });' }
        @{ Name = "summary-reads-not-counted"
           Find = '    await this.own(now, { summaryReads: 1 });'
           Replace = '' }
        @{ Name = "one-account-sees-every-account"
           Find = '      if (!p || (account !== null && p.account !== account)) continue;'
           Replace = '      if (!p) continue;' }
        @{ Name = "one-account-sees-the-requests"
           Find = '    if (account !== null) return { accounts };'
           Replace = '' }
        @{ Name = "retention-a-day-short"
           Find = '    const cutoff = cutoffHourOf(now, retentionDays);'
           Replace = '    const cutoff = cutoffHourOf(now, retentionDays - 1);' }
        @{ Name = "account-rows-kept-for-ever"
           Find = '    for (const prefix of [ROW, ACCOUNT, OWN]) {'
           Replace = '    for (const prefix of [ROW, OWN]) {' }
        @{ Name = "alarm-not-set-again"
           Find = '    await this.storage.setAlarm(now + (deleted >= maxDelete ? AGAIN_MS : DAY_MS));'
           Replace = '' }
        @{ Name = "a-capped-run-waits-a-day"
           Find = '(deleted >= maxDelete ? AGAIN_MS : DAY_MS)'
           Replace = '(DAY_MS)' }
        @{ Name = "no-cap-on-a-run"
           Find = '      if (room <= 0) break;'
           Replace = '' }
        @{ Name = "no-first-alarm"
           Find = '    await this.keepAlarm(now);'
           Replace = '' }
    )
}
