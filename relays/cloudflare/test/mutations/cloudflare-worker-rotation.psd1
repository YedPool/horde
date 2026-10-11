# Mutations of a machine's identity rotation at the relay (relays/cloudflare/worker/rotation.js, relay PR
# 8c): signed by the new key under its own key id, vouched for by the old key as registered, once.
# Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-rotation.psd1
# relays\cloudflare\test\test-cloudflare-limits.ps1 must fail for every one, except those declared to
# survive, each with its reason. Every find string occurs once.
#
# NOT HERE, and why: the cap on the body (a rotation's body is one record of some 900 characters; the
# cap only bounds what a stranger can make the Worker read); the refusal of a method other than POST
# (any other is refused the same way, as no rotation at all); and counting a refused rotation against
# its address (noteRefusedSignature is auth.js's, whose own counting is caught there; that an address
# over its rate is refused here is caught as address-refusal-skipped).
@{
    Target = "relays\cloudflare\worker\rotation.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-limits.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "stale-rotation-taken"
           Find = 'if (!isFresh(a.time, now)) return refuse(401,'
           Replace = 'if (false) return refuse(401,' }
        @{ Name = "address-refusal-skipped"
           Find = 'if (held) return refusalOf('
           Replace = 'if (false) return refusalOf(' }
        @{ Name = "under-any-key-id"
           Find = 'if (!rec.ok || rec.value.successorSignKeyId !== a.keyId) return fail();'
           Replace = 'if (!rec.ok) return fail();' }
        @{ Name = "new-key-signature-unchecked"
           Find = 'if (!(await verifyMachineSignature(newPoint, signed, sig))) return fail();'
           Replace = '' }
        @{ Name = "vouch-unchecked"
           Find = 'if (!(await verifyMachineSignature(oldPoint, rec.value.signed, vouch))) return fail();'
           Replace = '' }
        @{ Name = "unregistered-old-key-moved"
           Find = 'if (!owner || owner.horde !== rec.value.horde) return fail();'
           Replace = 'if (!owner) return fail();'
           Expect = "survives"
           Reason = "Defence in depth: a registered key's horde is the one its own grant signed, and the record's is the one its own vouch signed, so the two differ only for a record the old key never made - which vouch-unchecked shows is refused." }
        @{ Name = "handover-refusal-ignored"
           Find = 'if (!handed.ok) return fail();'
           Replace = ''
           Expect = "survives"
           Reason = "The registration is read a moment before (old.owner) and refused when it is gone, so a rotation presented again never reaches the hand-over; only a removal landing between the read and the hand-over makes the hand-over refuse - a race no suite can place." }
        @{ Name = "registration-not-put-back"
           Find = 'if (!adopted.ok) { await old.restore(handed.owner); return fail(); }'
           Replace = 'if (!adopted.ok) { return fail(); }' }
        @{ Name = "adoption-refusal-ignored"
           Find = 'if (!adopted.ok) { await old.restore(handed.owner); return fail(); }'
           Replace = '' }
        @{ Name = "account-list-not-moved"
           Find = 'await accountOf(env, owner.account).moveMachine('
           Replace = 'await Promise.resolve(' }
    )
}
