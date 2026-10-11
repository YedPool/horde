# Mutations of what relay PR 8c adds to the account API (relays/cloudflare/worker/account-api.js): the
# pairings an hour and the machines' cap on registration, the account's phones and signing one out, and
# deleting the account. The 8b promises are cloudflare-worker-account-api.psd1's. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-account-api-limits.psd1
# relays\cloudflare\test\test-cloudflare-limits.ps1 must fail for every one. Every find string occurs once.
#
# NOT HERE, and why: the label's own shape check (a registration whose label is not the offer's fails
# its grant, 403, which renamed-on-the-way shows; the shape check only words the refusal); the phone id's
# shape check at the route (the route's pattern takes 64 hex only); and the account's screen answered
# 401 when its account is gone (the gate refuses such a request first).
@{
    Target = "relays\cloudflare\worker\account-api.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-limits.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "pairing-not-counted"
           Find = 'const charged = await account.chargePairing({ now, limits });'
           Replace = 'const charged = await account.chargePairing({ now, limits: { ...limits, pairingsPerHour: 1000000 } });' }
        @{ Name = "pairing-refusal-ignored"
           Find = 'if (!charged.ok) return refusalOf(charged);'
           Replace = '' }
        @{ Name = "machines-cap-refusal-ignored"
           Find = '  if (!listed.ok) {'
           Replace = '  if (false) {' }
        @{ Name = "refused-machine-left-registered"
           Find = '    if (!claimed.duplicate) await key.release(who.account);'
           Replace = '' }
        @{ Name = "deletion-without-its-words"
           Find = 'if (body.confirm !== DELETE_CONFIRM) return refuse(400,'
           Replace = 'if (false) return refuse(400,' }
        @{ Name = "deleting-phone-keeps-its-cookie"
           Find = 'done.headers.append("Set-Cookie", clearedCookieHeader(SESSION_COOKIE));'
           Replace = '' }
        @{ Name = "machine-deletes-the-account"
           Find = 'if (!authorize(who, "delete", "")) return refuse(403,'
           Replace = 'if (false) return refuse(403,' }
        @{ Name = "no-phone-is-this-one"
           Find = 'current: p.id === who.phone }'
           Replace = 'current: false }' }
        @{ Name = "signing-out-no-phone-is-a-yes"
           Find = 'if (!(await accountOf(env, who.account).endPhone(phoneId))) return refuse(404,'
           Replace = 'if (false) return refuse(404,' }
    )
}
