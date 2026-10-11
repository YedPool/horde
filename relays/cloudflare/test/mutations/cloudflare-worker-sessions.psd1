# Mutations of a session's object (relays/cloudflare/worker/sessions.js, relay PR 8b). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-sessions.psd1
# relays\cloudflare\test\test-cloudflare-accounts.ps1 must fail for every one. Every find string occurs once.
#
# NOT HERE, and why: the end of a session's 30 days (read's expiry check and the alarm that deletes it:
# a suite cannot wait a month, and the dev's clock is the machine's); and the id's own pattern (an id
# the relay never made finds no record either way).
@{
    Target = "relays\cloudflare\worker\sessions.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-accounts.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "sign-out-ends-nothing"
           Find = '    await this.ctx.storage.deleteAll();'
           Replace = '' }
        @{ Name = "every-id-one-session"
           Find = 'env.SESSION.idFromName("session/" + id)'
           Replace = 'env.SESSION.idFromName("session/")' }
    )
}
