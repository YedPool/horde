# One mutation of relays/cloudflare/worker/mailbox.js that only the accounts suite shows: every mailbox
# is its account's (relay PR 8b; the name moved here from api.js in 8c, with the account's epoch). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-mailbox-accounts.psd1
# relays\cloudflare\test\test-cloudflare-accounts.ps1 must fail for it. Every find string occurs once.
@{
    Target = "relays\cloudflare\worker\mailbox.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-accounts.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "one-mailbox-for-every-account"
           Find = 'JSON.stringify([account, epoch, mailbox])'
           Replace = 'JSON.stringify(["", "", mailbox])' }
    )
}
