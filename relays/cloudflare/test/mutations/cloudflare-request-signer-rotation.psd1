# One mutation of the machine's signer (relays/cloudflare/RequestSigner.ps1) that only a rotation shows
# (relay PR 8c): the signer says which generation of the identity it signs with, so the adapter knows
# there is an older one whose retirement to carry. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-request-signer-rotation.psd1
# relays\cloudflare\test\test-cloudflare-limits.ps1 must fail for it. Every find string occurs once.
@{
    Target = "relays\cloudflare\RequestSigner.ps1"
    Suite  = "relays\cloudflare\test\test-cloudflare-limits.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "generation-not-told"
           Find = 'generation = $id.value.generation'
           Replace = 'generation = 1' }
    )
}
