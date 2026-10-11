# Mutations of who may sign in (relays/cloudflare/worker/allowlist.js, relay PR 8b). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-allowlist.psd1
# relays\cloudflare\test\test-cloudflare-accounts.ps1 must fail for every one (its node units, and a dev
# with the allowlist switched on). Every find string occurs once.
@{
    Target = "relays\cloudflare\worker\allowlist.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-accounts.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "broken-list-lets-everyone-in"
           Find = 'if (list.state !== "on") return false;'
           Replace = 'if (list.state !== "on") return true;' }
        @{ Name = "email-case-matters"
           Find = 'list.emails.has(claims.email.toLowerCase())'
           Replace = 'list.emails.has(claims.email)' }
        @{ Name = "account-ids-ignored"
           Find = 'return list.subs.has(claims.sub) || '
           Replace = 'return ' }
        @{ Name = "switched-on-list-is-off"
           Find = 'return o.on ? { state: "on", emails, subs } : { state: "off" };'
           Replace = 'return { state: "off" };' }
        @{ Name = "any-shape-read"
           Find = 'Object.keys(o).sort().join(",") !== "emails,on,subs" || typeof o.on !== "boolean"'
           Replace = 'false' }
    )
}
