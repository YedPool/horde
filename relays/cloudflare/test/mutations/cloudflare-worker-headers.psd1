# Mutations of the strict headers (relays/cloudflare/worker/headers.js). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-headers.psd1
# relays\cloudflare\test\test-cloudflare-worker.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "relays\cloudflare\worker\headers.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-worker.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "frame-ancestors-dropped"
           Find = '"Content-Security-Policy": found[1] + "; frame-ancestors ''none''",'
           Replace = '"Content-Security-Policy": found[1],' }
        @{ Name = "policy-not-the-pages-own"
           Find = 'const found = POLICY_LINE.exec(page);'
           Replace = 'const found = ["", "default-src ''self''"];' }
        @{ Name = "hsts-dropped"
           Find = '  "Strict-Transport-Security": "max-age=63072000; includeSubDomains",'
           Replace = '' }
        @{ Name = "nosniff-dropped"
           Find = '  "X-Content-Type-Options": "nosniff",'
           Replace = '' }
        @{ Name = "referrer-sent"
           Find = '  "Referrer-Policy": "no-referrer",'
           Replace = '  "Referrer-Policy": "origin",' }
        @{ Name = "frames-allowed-in-old-browsers"
           Find = '  "X-Frame-Options": "DENY"'
           Replace = '  "X-Frame-Options": "SAMEORIGIN"' }
        @{ Name = "microphone-allowed"
           Find = 'microphone=(), geolocation=()'
           Replace = 'geolocation=()' }
        @{ Name = "api-answers-cacheable"
           Find = 'if (isApi) headers.set("Cache-Control", "no-store");'
           Replace = '' }
        @{ Name = "upgrade-left-without-headers"
           Find = 'if (response.status === 101) return new Response(null, { status: 101, webSocket: response.webSocket, headers });'
           Replace = 'if (response.status === 101) return response;' }
    )
}
