# Mutations of the phone-message hops (fleet-metrics/mail.mjs): the plausible-stamp window, the exact seq,
# the memory of skipped records, and the latency report's count of messages that lack a hop. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-meter-mail.psd1
# test\test-fleet-meter.ps1 (the meter's node tests, on a synthetic journal) must fail for every one.
# Every find string occurs once.
@{
    Target = "fleet-metrics\mail.mjs"
    Suite  = "test\test-fleet-meter.ps1"
    Mutations = @(
        @{ Name = "any-stamp-is-plausible"
           Find = 'const stamp = (v, now) => Number.isSafeInteger(v) && v >= PLAUSIBLE_FROM && v <= now + DAY_MS;'
           Replace = 'const stamp = (v, now) => Number.isSafeInteger(v) && v >= 0;' }
        @{ Name = "future-stamp-is-plausible"
           Find = 'v >= PLAUSIBLE_FROM && v <= now + DAY_MS;'
           Replace = 'v >= PLAUSIBLE_FROM;' }
        @{ Name = "seq-digits-not-compared"
           Find = 'if (!Number.isSafeInteger(o.seq) || String(o.seq) !== seq.replace(/^0+(?=\d)/, '''')) return null;'
           Replace = 'if (!Number.isSafeInteger(o.seq)) return null;' }
        @{ Name = "skipped-record-read-again"
           Find = 'if (was && was.ident === SKIP && was.size === st.size && was.mtime === mtime)'
           Replace = 'if (false)' }
        @{ Name = "skipped-record-never-remembered"
           Find = 'if (st) store.markOffset({ path: file, size: st.size, mtime, offset: 0, ident: SKIP });'
           Replace = '' }
        @{ Name = "lacking-a-hop-not-counted"
           Find = 'else if (a || b) lacking++;'
           Replace = '' }
        @{ Name = "only-cross-clock-negatives-counted"
           Find = 'negative: d.filter((x) => x < 0).length'
           Replace = 'negative: crossClock ? d.filter((x) => x < 0).length : 0' }
    )
}
