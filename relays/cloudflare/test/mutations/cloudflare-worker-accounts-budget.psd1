# Mutations of how one account draws on the relay-wide limits (relays/cloudflare/worker/accounts.js; the
# arithmetic is budget.js's, the counts relay-budget.js's): the lease of the relay's day spent in the
# gate, the relay's cap on characters leased with a put and given back with an ack. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-accounts-budget.psd1
# relays\cloudflare\test\test-cloudflare-limits.ps1 must fail for every one (part 5). Every find string
# occurs once.
#
# NOT HERE, and why: the share of the cap a deleted account gives back (no request can read the
# relay-wide count, and a suite would have to fill the cap across a deletion to see it: a lost give-back
# only refuses early, the side the design allows), the room an ack keeps (an over-count of one lease),
# and how much an account from before the cap asks for (only its first put after the deploy differs).
@{
    Target = "relays\cloudflare\worker\accounts.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-limits.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "relay-day-not-asked"
           Find = 'if (!(g.granted >= 1)) return { ok: false, status: 429, code: CODES.relayDaily'
           Replace = 'if (false) return { ok: false, status: 429, code: CODES.relayDaily' }
        @{ Name = "tier-not-passed"
           Find = 'want: limits.relayRequestLease, tier, limits });'
           Replace = 'want: limits.relayRequestLease, tier: "owner", limits });' }
        @{ Name = "lease-never-spent"
           Find = 'await storage.put(DAY, { ...c.state, lease: lease - 1 });'
           Replace = 'await storage.put(DAY, { ...c.state, lease });' }
        @{ Name = "relay-cap-not-asked"
           Find = 'if (!r.ok) return { ok: false, status: 507, code: CODES.relayFull, reason: RELAY_FULL_WORDS };'
           Replace = 'if (false) return { ok: false, status: 507, code: CODES.relayFull, reason: RELAY_FULL_WORDS };' }
        @{ Name = "ack-gives-nothing-back"
           Find = 'await relayBudgetOf(this.env).giveChars({ chars: back });'
           Replace = 'await Promise.resolve(back);' }
    )
}
