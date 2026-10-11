# Mutations of a machine key's object (relays/cloudflare/worker/machines.js, relay PR 8b): who owns the
# key, which grants are spent, which nonces are used. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-machines.psd1
# relays\cloudflare\test\test-cloudflare-accounts.ps1 must fail for every one. Every find string occurs once.
#
# NOT HERE, and why: the sweep of expired grants (an expired grant is refused by the Worker before the
# object is asked, so keeping it longer changes nothing a request sees); and forgetting old nonces at
# exactly twice the window (a suite cannot wait two minutes; forgetting them at once is here).
@{
    Target = "relays\cloudflare\worker\machines.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-accounts.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "key-taken-from-another-account"
           Find = 'if (owner && owner.account !== account) return { ok: false, status: 409,'
           Replace = 'if (false) return { ok: false, status: 409,' }
        @{ Name = "spent-grant-taken-again"
           Find = 'if (spent !== undefined && !same) return { ok: false, status: 409,'
           Replace = 'if (false) return { ok: false, status: 409,' }
        @{ Name = "released-by-any-account"
           Find = 'if (!owner || owner.account !== account) return false;'
           Replace = 'if (!owner) return false;' }
        @{ Name = "signature-not-verified"
           Find = 'if (!(await verifyMachineSignature(point, signed, sigBytes))) return refused('
           Replace = 'if (false) return refused(' }
        @{ Name = "replay-taken"
           Find = 'if ((await storage.get(SEEN + nonce)) !== undefined) return refused('
           Replace = 'if (false) return refused(' }
        @{ Name = "nonce-not-kept"
           Find = 'await storage.put({ [SEEN + nonce]: now, [SEEN_AT + pad(now) + ":" + nonce]: nonce });'
           Replace = '' }
        @{ Name = "nonces-forgotten-at-once"
           Find = 'await forgetNonces(storage, now - 2 * MAX_SKEW_MS - 1000)'
           Replace = 'await forgetNonces(storage, now + 1)'
           Expect = "survives"
           Reason = "Since relay PR 8c a request forgets the old nonces BEFORE it keeps its own (so the nonce bound counts what is kept), so a replay sent straight after its original - this suite's - still meets its nonce. cloudflare-worker-machines-limits.psd1 holds the same mutant against test-cloudflare-limits.ps1, which replays a request after four others, and catches it." }
        @{ Name = "registered-to-no-horde"
           Find = 'return { account: owner.account, epoch: owner.epoch, horde: owner.horde, label: owner.label };'
           Replace = 'return { account: owner.account, epoch: owner.epoch, horde: "work" === owner.horde ? undefined : owner.horde, label: owner.label };' }
    )
}
