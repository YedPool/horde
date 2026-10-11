# Mutations of what relay PR 8c adds to a machine key's object (relays/cloudflare/worker/machines.js):
# refused signatures limited per key and address, the nonce cache bounded without forgetting a nonce
# early, and a rotation's hand-over and adoption. The 8b promises are cloudflare-worker-machines.psd1's.
# Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-machines-limits.psd1
# relays\cloudflare\test\test-cloudflare-limits.ps1 must fail for every one. Every find string occurs once.
#
# NOT HERE, and why: the hand-over's check that the registration is still the very one read a moment
# before (the Worker reads it and hands over at once; only a removal landing between the two calls
# changes it); the adoption's own nonce check (a replayed rotation is refused first by the hand-over,
# whose old key is nobody's by then: handover-taken-twice is caught); and the bound on how many
# addresses' buckets a key keeps (256: a suite would need that many addresses at one key).
@{
    Target = "relays\cloudflare\worker\machines.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-limits.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "refusals-not-counted"
           Find = 'const refused = (why) => { keep(probe.state); return { refused: why }; };'
           Replace = 'const refused = (why) => ({ refused: why });' }
        @{ Name = "refusal-limit-ignored"
           Find = 'if (!probe.ok) { keep(probe.state); return'
           Replace = 'if (false) { keep(probe.state); return' }
        @{ Name = "one-bucket-for-the-whole-key"
           Find = 'const slot = address;'
           Replace = 'const slot = "";' }
        @{ Name = "nonce-bound-ignored"
           Find = 'if (this.nonces >= limits.noncesPerKey) return { refused:'
           Replace = 'if (false) return { refused:' }
        @{ Name = "nonce-bound-off-by-one"
           Find = 'if (this.nonces >= limits.noncesPerKey) return { refused:'
           Replace = 'if (this.nonces > limits.noncesPerKey) return { refused:' }
        @{ Name = "nonce-bound-makes-room-by-forgetting"
           Find = 'if (this.nonces >= limits.noncesPerKey) return { refused:'
           Replace = 'if (this.nonces >= limits.noncesPerKey) { this.nonces -= await forgetNonces(storage, now + 1); } if (false) return { refused:' }
        @{ Name = "nonces-not-counted"
           Find = '    this.nonces++;'
           Replace = '' }
        @{ Name = "handover-taken-twice"
           Find = '    await storage.delete(OWNER);'
           Replace = '' }
        @{ Name = "successor-of-another-account-taken"
           Find = 'if (mine && mine.account !== owner.account) return { ok: false,'
           Replace = 'if (false) return { ok: false,' }
        @{ Name = "registration-not-put-back"
           Find = '    await storage.put(OWNER, owner);'
           Replace = '' }
    )
}
