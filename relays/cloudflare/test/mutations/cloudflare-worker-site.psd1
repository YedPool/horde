# Mutations of where the Worker is (relays/cloudflare/worker/site.js, relay PR 8b): its origin, and what
# counts as the site's own page. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-site.psd1
# relays\cloudflare\test\test-cloudflare-accounts.ps1 must fail for every one. Every find string occurs once.
#
# NOT HERE, and why: the callback path's pattern (wrangler.json's one value always matches it).
@{
    Target = "relays\cloudflare\worker\site.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-accounts.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "any-page-is-the-site"
           Find = 'return request.headers.get("Origin") === site.origin;'
           Replace = 'return request.headers.get("Origin") !== "x";' }
        @{ Name = "origin-with-a-path-taken"
           Find = '(?::[0-9]{1,5})?$/;'
           Replace = '(?::[0-9]{1,5})?/;' }
    )
}
