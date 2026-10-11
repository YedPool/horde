# Mutations of the account API (relays/cloudflare/worker/account-api.js, relay PR 8b): how a machine's
# key is registered to an account, and removed. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-account-api.psd1
# relays\cloudflare\test\test-cloudflare-accounts.ps1 must fail for every one. Every find string occurs once.
#
# NOT HERE, and why: the shape checks of horde, offer and machine (a bad one makes the grant fail to
# verify, which is refused as well); the release when listing fails (the Account object does not fail
# in a local dev); and the 405s of the wrong method (the router's words, no security in them).
@{
    Target = "relays\cloudflare\worker\account-api.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-accounts.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "grant-not-verified"
           Find = 'if (!(await verifyMachineSignature(point, accountGrantBytes(body), grant))) return refuse(403,'
           Replace = 'if (false) return refuse(403,' }
        @{ Name = "key-not-the-machine-named"
           Find = 'if (id !== body.machine) return refuse(400,'
           Replace = 'if (false) return refuse(400,' }
        @{ Name = "expired-offer-taken"
           Find = 'if (!Number.isSafeInteger(body.expiresAt) || body.expiresAt <= now) return refuse(400,'
           Replace = 'if (!Number.isSafeInteger(body.expiresAt)) return refuse(400,' }
        @{ Name = "grant-outliving-any-offer-taken"
           Find = 'if (body.expiresAt > now + PAIRING_LIMITS.maxTtlSeconds * 1000) return refuse(400,'
           Replace = 'if (false) return refuse(400,' }
        @{ Name = "claim-refusal-ignored"
           Find = 'if (!claimed.ok) return refuse(claimed.status, claimed.reason);'
           Replace = '' }
        @{ Name = "removal-not-released"
           Find = 'const released = await machineKeyOf(env, keyId).release(who.account);'
           Replace = 'const released = true;' }
        @{ Name = "removal-of-another-accounts-machine-is-yes"
           Find = 'if (!released) return refuse(404,'
           Replace = 'if (false) return refuse(404,' }
        @{ Name = "registered-but-not-listed"
           Find = 'listed = await account.listMachine({ entry: { keyId: id, horde: body.horde, label: body.label, registeredAt: now }, epoch: charged.epoch, limits });'
           Replace = 'listed = { ok: true };' }
        @{ Name = "machine-reads-the-account"
           Find = 'if (!authorize(who, "account", "")) return refuse(403,'
           Replace = 'if (false) return refuse(403,' }
        @{ Name = "machine-removes-another"
           Find = 'if (!authorize(who, "remove", m[1])) return refuse(403,'
           Replace = 'if (false) return refuse(403,' }
    )
}
