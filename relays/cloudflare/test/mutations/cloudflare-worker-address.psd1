# Mutations of one client address's object (relays/cloudflare/worker/address.js, relay PR 8c): sign-ins
# started, accounts made and machine signatures refused, per address. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-address.psd1
# relays\cloudflare\test\test-cloudflare-limits.ps1 must fail for every one. Every find string occurs once.
#
# NOT HERE, and why: the alarm that deletes a day's count at UTC midnight (a suite cannot wait for
# midnight, and a count of a past day is ignored all the same: throttle.js, countInDay).
@{
    Target = "relays\cloudflare\worker\address.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-limits.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "sign-ins-not-counted"; Find = 'this.signIns = t.state;'; Replace = '' }
        @{ Name = "accounts-made-not-counted"; Find = 'await storage.put(MADE, c.state);'; Replace = '' }
        @{ Name = "accounts-made-not-refused"; Find = 'if (!c.ok) return { ok: false, retryAfterMs: c.retryAfterMs };'; Replace = '' }
        @{ Name = "refusals-not-counted"; Find = 'this.refusals = r.state;'; Replace = '' }
        @{ Name = "refusals-held-to-the-sign-in-rate"
           Find = 'const r = takeToken(this.refusals, now, limits.refusedSignaturesPerMinutePerAddress, MINUTE_MS, limits.refusedSignaturesPerMinutePerAddress);'
           Replace = 'const r = takeToken(this.refusals, now, limits.signInStartsPerMinute, MINUTE_MS, limits.signInStartsPerMinute);' }
    )
}
