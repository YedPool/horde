# Mutations of the Worker's cookies (relays/cloudflare/worker/cookies.js, relay PR 8b). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-cookies.psd1
# relays\cloudflare\test\test-cloudflare-accounts.ps1 must fail for every one (its node units, its
# Set-Cookie checks, and Chrome's own record of the cookie). Every find string occurs once.
@{
    Target = "relays\cloudflare\worker\cookies.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-accounts.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "session-without-the-prefix"
           Find = 'export const SESSION_COOKIE = "__Host-horde-session";'
           Replace = 'export const SESSION_COOKIE = "horde-session";' }
        @{ Name = "name-given-twice-taken"
           Find = '    if (found !== null) return null;'
           Replace = '' }
        @{ Name = "readable-by-script"
           Find = '; Path=/; Secure; HttpOnly; SameSite=Lax";'
           Replace = '; Path=/; Secure; SameSite=Lax";' }
        @{ Name = "sent-cross-site"
           Find = '; Path=/; Secure; HttpOnly; SameSite=Lax";'
           Replace = '; Path=/; Secure; HttpOnly; SameSite=None";' }
        @{ Name = "unprefixed-cookie-set"
           Find = 'if (!name.startsWith("__Host-") || !VALUE.test(value)'
           Replace = 'if (!VALUE.test(value)' }
    )
}
