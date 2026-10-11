# Mutations of Sign in with Google's flow (relays/cloudflare/worker/signin.js, relay PR 8b). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-signin.psd1
# relays\cloudflare\test\test-cloudflare-accounts.ps1 must fail for every one. Every find string occurs once.
#
# NOT HERE, and why: the provider's error parameter (a provider that answers error sends no code, so
# the code's own check refuses the same callback); the code's length bounds (the provider refuses a
# code it did not issue); and the refusal of a Worker with no client id or secret (a suite's dev always
# has both, and the deploy always stores both before it deploys).
@{
    Target = "relays\cloudflare\worker\signin.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-accounts.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "callback-this-browser-did-not-start"
           Find = 'const m = PENDING.exec(readCookie(request, SIGNIN_COOKIE) || "");'
           Replace = 'const m = PENDING.exec(readCookie(request, SIGNIN_COOKIE) || "") || [null, url.searchParams.get("state") || "", "", "", String(Date.now())];' }
        @{ Name = "state-not-compared"
           Find = 'if (typeof state !== "string" || !sameText(state, m[1])) return refused('
           Replace = 'if (typeof state !== "string") return refused(' }
        @{ Name = "stale-sign-in-taken"
           Find = 'if (now - Number(m[4]) > SIGNIN_MS || Number(m[4]) > now) return refused('
           Replace = 'if (Number(m[4]) > now) return refused(' }
        @{ Name = "token-not-verified"
           Find = 'if (!v.ok) return refused(v.reason);'
           Replace = 'if (!v.claims) v.claims = { sub: "1", email: "" };' }
        @{ Name = "allowlist-ignored"
           Find = 'if (!admits(readAllowlist(env.HORDE_RELAY_SIGNIN_ALLOWLIST), v.claims)) return refused('
           Replace = 'if (false) return refused(' }
        @{ Name = "account-is-the-email"
           Find = 'const accountId = ACCOUNT_PREFIX + v.claims.sub;'
           Replace = 'const accountId = ACCOUNT_PREFIX + v.claims.email;' }
        @{ Name = "sign-out-from-any-page"
           Find = 'if (!fromSite(request, siteOf(env))) return refuse(403,'
           Replace = 'if (false) return refuse(403,' }
        @{ Name = "sign-out-leaves-the-session"
           Find = '    await session.end();'
           Replace = '' }
        @{ Name = "sign-in-cookie-kept"
           Find = 'return redirect(site.origin + APP, [cookieHeader(SESSION_COOKIE, id, SESSION_MS / 1000), clearedCookieHeader(SIGNIN_COOKIE)]);'
           Replace = 'return redirect(site.origin + APP, [cookieHeader(SESSION_COOKIE, id, SESSION_MS / 1000)]);' }
    )
}
