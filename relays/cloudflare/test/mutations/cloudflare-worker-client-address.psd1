# Mutations of who is asking, by address (relays/cloudflare/worker/client-address.js, relay PR 8c): the
# IP Cloudflare reports, and the test override honoured only for a local test with its binding. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-client-address.psd1
# relays\cloudflare\test\test-cloudflare-limits.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "relays\cloudflare\worker\client-address.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-limits.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "override-without-the-binding"
           Find = 'if (typeof env[TEST_BINDING] === "string" && isLoopback(url)) {'
           Replace = 'if (isLoopback(url)) {' }
        @{ Name = "override-for-a-deployed-worker"
           Find = 'if (typeof env[TEST_BINDING] === "string" && isLoopback(url)) {'
           Replace = 'if (typeof env[TEST_BINDING] === "string") {' }
        @{ Name = "override-not-an-ip-taken"
           Find = 'if (typeof t === "string" && ADDRESS.test(t)) return t;'
           Replace = 'if (typeof t === "string") return t;' }
        @{ Name = "cloudflare-ip-ignored"
           Find = 'return typeof ip === "string" && ADDRESS.test(ip) ? ip : "local";'
           Replace = 'return "local";' }
        @{ Name = "garbage-ip-taken"
           Find = 'return typeof ip === "string" && ADDRESS.test(ip) ? ip : "local";'
           Replace = 'return typeof ip === "string" ? ip : "local";' }
    )
}
