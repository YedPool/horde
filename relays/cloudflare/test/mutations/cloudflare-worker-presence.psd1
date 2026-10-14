# Mutations of when a machine was last heard from (relays/cloudflare/worker/presence.js; the phone's PC
# offline banner, the founder's fix 2 of 2026-10-14): kept on every request, written at most once per
# 30 s, shown to the second. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-presence.psd1
# relays\cloudflare\test\test-cloudflare-accounts.ps1 must fail for every one (its pure checks, part 1,
# and the local dev's). Every find string occurs once.
@{
    Target = "relays\cloudflare\worker\presence.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-accounts.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "written-on-every-request"
           Find = 'const write = !held || now - held.wroteAt >= SEEN_WRITE_MS;'
           Replace = 'const write = true;' }
        @{ Name = "throttle-off-by-one"
           Find = 'const write = !held || now - held.wroteAt >= SEEN_WRITE_MS;'
           Replace = 'const write = !held || now - held.wroteAt > SEEN_WRITE_MS;' }
        @{ Name = "first-heard-not-written"
           Find = 'const write = !held || now - held.wroteAt >= SEEN_WRITE_MS;'
           Replace = 'const write = Boolean(held) && now - held.wroteAt >= SEEN_WRITE_MS;' }
        @{ Name = "time-moves-back"
           Find = 'const at = held && held.at > now ? held.at : now;'
           Replace = 'const at = now;' }
        @{ Name = "storage-ignored"
           Find = 'const at = Math.max(m, s);'
           Replace = 'const at = m;' }
        @{ Name = "not-cut-to-the-second"
           Find = 'return at > 0 ? at - (at % 1000) : null;'
           Replace = 'return at > 0 ? at : null;' }
        @{ Name = "never-heard-is-zero"
           Find = 'return at > 0 ? at - (at % 1000) : null;'
           Replace = 'return at - (at % 1000);' }
    )
}
