# Mutations of the relay-wide limits' pure parts (relays/cloudflare/worker/budget.js): who is an owner,
# which part of the day each tier may draw on, a lease granted whole or in part and never past the line,
# characters granted with room only where there is room, and what an account gives back. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-budget.psd1
# relays\cloudflare\test\test-cloudflare-limits.ps1 must fail for every one (its part 1, limits-units.mjs,
# and part 5 against a dev). Every find string occurs once.
#
# NOT HERE, and why: a binding that is not a string (a deploy only ever writes text, so no request
# carries one) and the retry time of a refusal (throttle.js's own day arithmetic, mutated there).
@{
    Target = "relays\cloudflare\worker\budget.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-limits.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "no-owner-holds-the-reserve-back"
           Find = 'if (owners.state === "none") return "everyone";'
           Replace = 'if (owners.state === "none") return "public";' }
        @{ Name = "broken-owners-fail-open"
           Find = 'if (owners.state !== "set" || typeof account'
           Replace = 'if (owners.state === "broken") return "owner"; if (owners.state !== "set" || typeof account' }
        @{ Name = "any-account-an-owner"
           Find = 'return owners.subs.has(account.slice(ACCOUNT_PREFIX.length)) ? "owner" : "public";'
           Replace = 'return "owner";' }
        @{ Name = "owners-split-on-spaces-too"
           Find = 'if (parts.length > MAX_OWNERS || !parts.every((p) => SUB.test(p))) return { state: "broken" };'
           Replace = 'if (parts.length > MAX_OWNERS) return { state: "broken" };' }
        @{ Name = "public-draws-on-the-reserve"
           Find = 'return limits.relayRequestsPerDay - limits.relayOwnerReserve;'
           Replace = 'return limits.relayRequestsPerDay;' }
        @{ Name = "owner-held-to-the-shared-part"
           Find = 'if (tier === "owner" || tier === "everyone") return limits.relayRequestsPerDay;'
           Replace = 'if (tier === "everyone") return limits.relayRequestsPerDay;' }
        @{ Name = "lease-granted-past-the-line"
           Find = 'const granted = Math.max(0, Math.min(want, cap - used));'
           Replace = 'const granted = used < cap ? want : 0;' }
        @{ Name = "day-never-starts-again"
           Find = 'state && state.day === day && Number.isSafeInteger(state.used)'
           Replace = 'state && Number.isSafeInteger(state.used)' }
        @{ Name = "chars-past-the-cap-taken"
           Find = 'if (held + need > max) return { ok: false, granted: 0, total: held };'
           Replace = 'if (held > max) return { ok: false, granted: 0, total: held };' }
        @{ Name = "room-granted-past-the-cap"
           Find = 'const granted = need + Math.max(0, Math.min(extra, max - held - need));'
           Replace = 'const granted = need + extra;' }
        @{ Name = "nothing-given-back"
           Find = 'return Math.max(0, granted - usage - lease);'
           Replace = 'return 0;' }
    )
}
