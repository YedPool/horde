# Mutations of the provider's side of sign-in (relays/cloudflare/worker/oidc.js, relay PR 8b): which
# provider, PKCE, the code's exchange and the key cache. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-oidc.psd1
# relays\cloudflare\test\test-cloudflare-accounts.ps1 must fail for every one. Every find string occurs once.
#
# NOT HERE, and why: the fetch timeouts and the answer's size cap (a suite's provider answers at once,
# and small); the cache's bounds of 5 minutes and a day (a suite cannot wait them out); and Google's
# endpoints themselves (no suite may contact Google - they are read off its discovery document, cited
# in the file).
@{
    Target = "relays\cloudflare\worker\oidc.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-accounts.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "test-provider-for-a-deployed-name"
           Find = 'if (typeof t !== "string" || !TEST_ISSUER.test(t) || !isLoopback(url)) return GOOGLE;'
           Replace = 'if (typeof t !== "string") return GOOGLE;' }
        @{ Name = "plain-pkce"
           Find = 'challenge: b64u(await sha256(utf8(verifier)))'
           Replace = 'challenge: verifier' }
        @{ Name = "state-is-the-nonce"
           Find = 'return { state: b64u(randomBytes(32)), nonce: b64u(randomBytes(32)), verifier,'
           Replace = 'const same = b64u(randomBytes(32)); return { state: same, nonce: same, verifier,' }
        @{ Name = "keys-fetched-every-time"
           Find = 'if (!c || now() >= c.until) c = await load(provider);'
           Replace = 'c = await load(provider);' }
        @{ Name = "keys-refetched-without-pause"
           Find = 'if (was && t - was.fetchedAt < REFETCH_GAP_MS) return was;'
           Replace = '' }
        @{ Name = "rotated-keys-never-refetched"
           Find = 'if (!k) { c = await load(provider); k = c.keys.find((x) => x.kid === kid); }'
           Replace = '' }
        @{ Name = "refused-code-taken"
           Find = 'if (r.status !== 200 || text === null) return { ok: false,'
           Replace = 'if (text === null) return { ok: false,' }
    )
}
