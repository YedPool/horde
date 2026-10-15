# Mutations of the hosted relay's join requests (relays/cloudflare/worker/join.js; phone-started pairing):
# the address's block, what a refusal spends, a request taken once, the request key's check, the
# country, and what a reject does. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-cloudflare-join.psd1
# relays\cloudflare\test\test-cloudflare-join.ps1 must fail for every one. Every find string occurs once.
#
# NOT HERE, and why: the field shape checks other than the request key's (each is one regex the suite's
# malformed table attacks one by one; a mutant per field would only repeat that table); the giving back
# of tokens when the mailbox throws (a mailbox object that throws cannot be made in a local dev); and the
# one pending slot and the caps themselves, which are the account's and the address's objects'
# (accounts.js, address.js), not this file's.
@{
    Target = "relays\cloudflare\worker\join.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-join.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "blocked-address-let-through"
           Find = 'if (a.blocked) return refuseWith(429, CODES.joinBlocked,'
           Replace = 'if (false) return refuseWith(429, CODES.joinBlocked,' }
        @{ Name = "reject-blocks-nothing"
           Find = 'if (c.freed && body.outcome === "rejected" && c.address) await addressOf'
           Replace = 'if (false) await addressOf' }
        @{ Name = "expiry-blocks-too"
           Find = 'body.outcome === "rejected" && c.address'
           Replace = 'body.outcome !== "approved" && c.address' }
        @{ Name = "account-refusal-spends-the-address-token"
           Find = 'if (a.taken && (!r.ok || r.repeat)) await place.joinRefund({ limits });'
           Replace = '' }
        @{ Name = "used-request-id-taken-again"
           Find = 'if (failure !== null || !done.ok || done.duplicate) {'
           Replace = 'if (failure !== null || !done.ok) {' }
        @{ Name = "refused-put-keeps-the-slot"
           Find = '    await account.joinRelease({ request: body.request, limits });'
           Replace = '' }
        @{ Name = "request-key-not-a-point"
           Find = 'try { await crypto.subtle.importKey("raw", bytes, { name: "ECDH", namedCurve: "P-256" }, true, []); return true; } catch (e) { return false; }'
           Replace = 'return true;' }
        @{ Name = "test-country-ignored"
           Find = '    if (t !== null) return COUNTRY.test(t) ? t : "";'
           Replace = '' }
    )
}
