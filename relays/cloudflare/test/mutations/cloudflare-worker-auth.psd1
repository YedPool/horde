# Mutations of the hosted relay's auth seam (relays/cloudflare/worker/auth.js): each lets the test
# authenticator vouch where it must not. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-auth.psd1
# relays\cloudflare\test\test-cloudflare-worker.ps1 must fail for every one. Every find string occurs once.
#
# NOT HERE, and why: the constant-time comparison (a plain === answers the same; only timing differs,
# which no suite here can measure reliably).
@{
    Target = "relays\cloudflare\worker\auth.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-worker.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "any-host-name-vouched-for"
           Find = 'if (!LOOPBACK.has(url.hostname)) return null;'
           Replace = '' }
        @{ Name = "placeholder-counts-as-a-token"
           Find = 'const TEST_TOKEN_MIN = 32;'
           Replace = 'const TEST_TOKEN_MIN = 1;' }
        @{ Name = "any-bearer-vouched-for"
           Find = 'if (typeof given !== "string" || !sameText(given, "Bearer " + token)) return null;'
           Replace = 'if (typeof given !== "string" || !given.startsWith("Bearer ")) return null;' }
        @{ Name = "everyone-vouched-for"
           Find = '  for (const vouch of AUTHENTICATORS) {'
           Replace = '  if (true) return { name: "anyone", may: () => true }; for (const vouch of AUTHENTICATORS) {' }
    )
}
