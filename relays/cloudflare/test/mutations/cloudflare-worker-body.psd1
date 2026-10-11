# Mutations of how the Worker reads a body (relays/cloudflare/worker/body.js). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-body.psd1
# relays\cloudflare\test\test-cloudflare-worker.ps1 must fail for every one. Every find string occurs once.
#
# NOT HERE, and why: the declared-length check in readCappedBytes (a body that states a length past the
# cap is also stopped by the chunk-by-chunk count after it, so dropping it changes when a refusal
# comes, not whether - the chunked case holds the count itself to account); and the check that the body
# is an object and not an array or a scalar (an array or a string has no members named key and text, so
# the members check after it refuses the same body, in other words).
@{
    Target = "relays\cloudflare\worker\body.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-worker.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "chunked-body-read-whole"
           Find = 'if (size > cap) { await reader.cancel(); return null; }'
           Replace = '' }
        @{ Name = "extra-members-allowed"
           Find = 'if (names !== members.slice().sort().join(",")) return'
           Replace = 'if (false) return' }
    )
}
