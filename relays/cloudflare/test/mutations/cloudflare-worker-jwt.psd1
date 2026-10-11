# Mutations of the id token's verification (relays/cloudflare/worker/jwt.js, relay PR 8b): each lets one
# lying token through. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-jwt.psd1
# relays\cloudflare\test\test-cloudflare-accounts.ps1 must fail for every one (its node units provoke
# each refusal; its sign-ins through the fake provider provoke most again). Every find string occurs once.
#
# NOT HERE, and why: the length and shape of a key id (a provider's key id is looked up, never trusted,
# so a strange one only fails the lookup); and exp at exactly the skew's edge (<= against <: a token
# expiring on the very millisecond cannot be made on purpose).
@{
    Target = "relays\cloudflare\worker\jwt.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-accounts.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "any-alg-taken"
           Find = 'if (header.alg !== "RS256") return no('
           Replace = 'if (false) return no(' }
        @{ Name = "signature-not-checked"
           Find = 'if (!verified) return no('
           Replace = 'if (false) return no(' }
        @{ Name = "encryption-key-used"
           Find = '(jwk.use !== undefined && jwk.use !== "sig") || '
           Replace = '' }
        @{ Name = "any-issuer-taken"
           Find = 'if (typeof c.iss !== "string" || !expect.issuers.includes(c.iss)) return no('
           Replace = 'if (typeof c.iss !== "string") return no(' }
        @{ Name = "any-audience-taken"
           Find = 'if (!audOk) return no('
           Replace = 'if (false) return no(' }
        @{ Name = "audience-list-without-azp-taken"
           Find = 'c.aud.includes(expect.audience) && c.azp === expect.audience'
           Replace = 'c.aud.includes(expect.audience)' }
        @{ Name = "expired-taken"
           Find = 'if (!Number.isFinite(c.exp) || c.exp * 1000 <= expect.now - SKEW_MS) return no('
           Replace = 'if (!Number.isFinite(c.exp)) return no(' }
        @{ Name = "skew-ten-minutes"
           Find = 'export const SKEW_MS = 60000;'
           Replace = 'export const SKEW_MS = 600000;' }
        @{ Name = "future-token-taken"
           Find = 'if (!Number.isFinite(c.iat) || c.iat * 1000 > expect.now + SKEW_MS) return no('
           Replace = 'if (!Number.isFinite(c.iat)) return no(' }
        @{ Name = "old-token-taken"
           Find = 'if (c.iat * 1000 < expect.now - expect.maxAgeMs - SKEW_MS) return no('
           Replace = 'if (false) return no(' }
        @{ Name = "any-nonce-taken"
           Find = 'if (typeof c.nonce !== "string" || c.nonce !== expect.nonce) return no('
           Replace = 'if (false) return no(' }
        @{ Name = "email-verified-as-text-taken"
           Find = 'if (c.email_verified !== true) return no('
           Replace = 'if (!c.email_verified) return no(' }
        @{ Name = "no-subject-taken"
           Find = 'if (typeof c.sub !== "string" || !SUB.test(c.sub)) return no('
           Replace = 'if (false) return no(' }
        @{ Name = "any-length-read"
           Find = 'const TOKEN_CHARS = 8192;'
           Replace = 'const TOKEN_CHARS = 1000000;' }
    )
}
