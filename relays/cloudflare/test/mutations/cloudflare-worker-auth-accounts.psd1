# Mutations of the auth seam's two real authenticators (relays/cloudflare/worker/auth.js, relay PR 8b):
# a signed-in phone's session, and a machine's signature. The test authenticator's own are
# cloudflare-worker-auth.psd1's. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-auth-accounts.psd1
# relays\cloudflare\test\test-cloudflare-accounts.ps1 must fail for every one. Every find string occurs once.
#
# NOT HERE, and why: the body read under its cap for the signature (a body past the cap is refused by
# the API's own read as well); and the check that a principal's may() is a function (every
# authenticator here makes one).
@{
    Target = "relays\cloudflare\worker\auth.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-accounts.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "cross-site-change-taken"
           Find = 'if ((changes || watch) && !fromSite(request, siteOf(env))) return null;'
           Replace = '' }
        @{ Name = "cross-site-watch-taken"
           Find = 'const watch = (request.headers.get("Upgrade") || "").toLowerCase() === "websocket";'
           Replace = 'const watch = false;' }
        @{ Name = "ended-session-taken"
           Find = '  if (!s) return null;'
           Replace = '' }
        @{ Name = "stale-request-taken"
           Find = 'if (!isFresh(a.time, now)) return { refusal:'
           Replace = 'if (false) return { refusal:' }
        @{ Name = "another-origin-signed"
           Find = 'origin: siteOf(env).origin, method: request.method'
           Replace = 'origin: url.origin === siteOf(env).origin ? "https://relay.example.test" : url.origin, method: request.method' }
        @{ Name = "query-not-signed"
           Find = 'target: url.pathname + url.search, time: a.time'
           Replace = 'target: url.pathname + (url.search ? "?since=0&max=10" : ""), time: a.time' }
        @{ Name = "machine-reaches-any-horde"
           Find = 'String(target).split("/")[0] === horde'
           Replace = 'true' }
        @{ Name = "machine-removes-any-key"
           Find = 'op === "remove" && target === keyId'
           Replace = 'op === "remove"' }
        @{ Name = "first-refusal-is-not-said"
           Find = 'if (who && refused === null) refused = who;'
           Replace = '' }
    )
}
