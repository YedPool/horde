# Mutations of a machine request's signature wire (relays/cloudflare/worker/request-signature.js,
# relay PR 8b). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-request-signature.psd1
# relays\cloudflare\test\test-cloudflare-accounts.ps1 must fail for every one (its node units first, then
# the machine's requests against the Worker). Every find string occurs once.
@{
    Target = "relays\cloudflare\worker\request-signature.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-accounts.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "future-time-taken"
           Find = 'return Math.abs(now - time) <= MAX_SKEW_MS;'
           Replace = 'return now - time <= MAX_SKEW_MS;' }
        @{ Name = "window-ten-minutes"
           Find = 'export const MAX_SKEW_MS = 60000;'
           Replace = 'export const MAX_SKEW_MS = 600000;' }
        @{ Name = "header-unanchored"
           Find = 'const HEADER = /^Horde-Machine key='
           Replace = 'const HEADER = /Horde-Machine key=' }
        @{ Name = "method-not-in-the-signed-bytes"
           Find = 'origin + "\n" + method + "\n" + target'
           Replace = 'origin + "\n" + "GET" + "\n" + target' }
        @{ Name = "body-not-in-the-signed-bytes"
           Find = 'keyId + "\n" + hash);'
           Replace = 'keyId + "\n");' }
    )
}
