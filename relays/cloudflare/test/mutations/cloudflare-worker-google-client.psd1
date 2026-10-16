# Mutations of the Google client the Worker signs in with (relays/cloudflare/worker/google-client.js):
# a client id stored with a byte order mark in front (2026-10-14) must never reach Google. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-google-client.psd1
# relays\cloudflare\test\test-cloudflare-worker.ps1 (a dev with the marked id, and its clean twin) must
# fail for every one. Every find string occurs once.
@{
    Target = "relays\cloudflare\worker\google-client.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-worker.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "any-text-is-a-client"
           Find = 'const PRINTABLE = /^[\x21-\x7E](?:[\x20-\x7E]*[\x21-\x7E])?$/;'
           Replace = 'const PRINTABLE = /^[\s\S]+$/;' }
        @{ Name = "client-id-unchecked"
           Find = 'if (!cleanSecret(id) || !cleanSecret(secret)) return null;'
           Replace = 'if (!id || !cleanSecret(secret)) return null;' }
    )
}
