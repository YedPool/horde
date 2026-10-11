# Mutations of how a rate and a day count are kept (relays/cloudflare/worker/throttle.js, relay PR 8c),
# each at its edge. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-throttle.psd1
# relays\cloudflare\test\test-cloudflare-limits.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "relays\cloudflare\worker\throttle.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-limits.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "fresh-bucket-empty"; Find = 'let tokens = burst;'; Replace = 'let tokens = 0;' }
        @{ Name = "bucket-fills-past-its-burst"
           Find = 'tokens = Math.min(burst, state.tokens + Math.max(0, now - state.at) * rate);'
           Replace = 'tokens = state.tokens + Math.max(0, now - state.at) * rate;' }
        @{ Name = "bucket-never-refills"
           Find = 'state.tokens + Math.max(0, now - state.at) * rate'
           Replace = 'state.tokens + 0 * rate' }
        @{ Name = "clock-going-back-refills"
           Find = 'Math.max(0, now - state.at)'
           Replace = 'Math.abs(now - state.at)' }
        @{ Name = "last-token-refused"; Find = 'if (tokens >= 1) return { ok: true'; Replace = 'if (tokens > 1) return { ok: true' }
        @{ Name = "token-not-taken"; Find = 'state: { tokens: tokens - 1, at: now }'; Replace = 'state: { tokens, at: now }' }
        @{ Name = "no-retry-after"; Find = 'retryAfterMs: Math.ceil((1 - tokens) / rate)'; Replace = 'retryAfterMs: 0' }
        @{ Name = "day-over-its-max"; Find = 'if (n >= max) return { ok: false'; Replace = 'if (n > max) return { ok: false' }
        @{ Name = "refused-counted"; Find = 'return { ok: false, state: { day, n },'; Replace = 'return { ok: false, state: { day, n: n + 1 },' }
        @{ Name = "day-never-starts-again"; Find = 'state && state.day === day && Number.isFinite(state.n)'; Replace = 'state && Number.isFinite(state.n)' }
        @{ Name = "retry-after-not-midnight"; Find = 'retryAfterMs: (day + 1) * DAY_MS - now'; Replace = 'retryAfterMs: DAY_MS' }
    )
}
