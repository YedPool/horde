# Mutations of the Worker's front door (relays/cloudflare/worker/index.js). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-index.psd1
# relays\cloudflare\test\test-cloudflare-worker.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "relays\cloudflare\worker\index.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-worker.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "sign-in-path-not-reserved"
           Find = 'if (reserved) response = refuse(501,'
           Replace = 'if (false) response = refuse(501,' }
        @{ Name = "root-not-the-site-index"
           Find = 'if (url.pathname === "/") return env.ASSETS.fetch('
           Replace = 'if (false) return env.ASSETS.fetch(' }
        @{ Name = "files-get-the-api-cache-rule"
           Find = 'return withStrictHeaders(response, api);'
           Replace = 'return withStrictHeaders(response, true);' }
    )
}
