# Mutations of what accounts change in the mailbox API (relays/cloudflare/worker/api.js, relay PR 8b):
# every mailbox under the principal's account, what each principal may do, and the words of a machine
# refused for its clock. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-api-accounts.psd1
# relays\cloudflare\test\test-cloudflare-accounts.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "relays\cloudflare\worker\api.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-accounts.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "one-mailbox-for-every-account"
           Find = 'env.MAILBOX.idFromName(JSON.stringify([account, mailbox]))'
           Replace = 'env.MAILBOX.idFromName(JSON.stringify(["", mailbox]))' }
        @{ Name = "principal-may-anything"
           Find = 'if (!authorize(who, op, mailbox)) return refuse(403,'
           Replace = 'if (false) return refuse(403,' }
        @{ Name = "refusal-words-lost"
           Find = 'who && who.refusal ? who.refusal :'
           Replace = 'false ? who.refusal :' }
        @{ Name = "account-api-unreachable"
           Find = 'if (isAccountPath(url.pathname)) return handleAccountApi(request, env, url, who);'
           Replace = '' }
    )
}
