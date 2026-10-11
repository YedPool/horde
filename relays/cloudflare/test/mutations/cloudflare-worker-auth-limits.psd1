# Mutations of what relay PR 8c adds to the auth seam (relays/cloudflare/worker/auth.js): each principal's
# device and epoch, and refused machine signatures limited per address - told to the address's object,
# and refused at once in this isolate once it is over. The 8b promises are cloudflare-worker-auth-
# accounts.psd1's. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-auth-limits.psd1
# relays\cloudflare\test\test-cloudflare-limits.ps1 must fail for every one. Every find string occurs once.
#
# NOT HERE, and why: the bound on the isolate's list of blocked addresses (4096: a suite would need that
# many addresses), and an address's block lifted when its time is up (a minute, longer than a suite
# should wait; its time comes from the address's own bucket, whose refill throttle.js's mutants hold).
@{
    Target = "relays\cloudflare\worker\auth.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-limits.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "phones-one-device"
           Find = 'device: "phone:" + phone,'
           Replace = 'device: "phone:",' }
        @{ Name = "machines-one-device"
           Find = 'device: "machine:" + keyId,'
           Replace = 'device: "machine:",' }
        @{ Name = "phone-without-its-epoch"
           Find = 'epoch: s.epoch,'
           Replace = 'epoch: "",' }
        @{ Name = "machine-without-its-epoch"
           Find = 'epoch: v.epoch,'
           Replace = 'epoch: "",' }
        @{ Name = "blocked-address-let-through"
           Find = '  if (held) return held;'
           Replace = '' }
        @{ Name = "refusal-not-told-to-the-address"
           Find = 'return noteRefusedSignature(env, address, now, limits);'
           Replace = 'return null;' }
        @{ Name = "over-its-rate-not-blocked"
           Find = '  blocked.set(address, now + r.retryAfterMs);'
           Replace = '' }
        @{ Name = "key-limit-refusal-dropped"
           Find = 'if (v && v.status === 429) return { refusal:'
           Replace = 'if (false) return { refusal:' }
    )
}
