# Mutations of what relay PR 8c adds to the mailbox API (relays/cloudflare/worker/api.js): the account's
# gate on every request, a limit's refusal said as itself, the device handed to a watch, and the
# rotation route. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-api-limits.psd1
# relays\cloudflare\test\test-cloudflare-limits.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "relays\cloudflare\worker\api.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-limits.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "gate-skipped"
           Find = '  if (who.gated) {'
           Replace = '  if (false) {' }
        @{ Name = "authenticator-429-said-as-401"
           Find = 'if (who && who.status === 429) return refusalOf('
           Replace = 'if (false) return refusalOf(' }
        @{ Name = "watch-of-no-device"
           Find = 'inner.searchParams.set("device", device);'
           Replace = 'inner.searchParams.set("device", "");' }
        @{ Name = "rotation-unreachable"
           Find = 'if (url.pathname === ROTATION_PATH) return handleRotation(request, env, url, limits);'
           Replace = '' }
        @{ Name = "put-charged-to-no-account"
           Find = 'who.gated ? { account: who.account, epoch: who.epoch, mailbox } : null'
           Replace = 'null' }
        @{ Name = "full-mailbox-said-as-a-bad-request"
           Find = 'if (!done.ok) return done.code ? refusalOf(done) : refuse(400,'
           Replace = 'if (!done.ok) return refuse(400,' }
    )
}
