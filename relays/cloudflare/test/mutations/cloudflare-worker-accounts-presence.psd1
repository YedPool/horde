# Mutations of where an account's object keeps when each machine was last heard from (relays/cloudflare/
# worker/accounts.js, with presence.js; the phone's PC offline banner, the founder's fix 2 of 2026-10-14).
# Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-accounts-presence.psd1
# relays\cloudflare\test\test-cloudflare-accounts.ps1 must fail for every one, except those declared to
# survive, each with its reason. Every find string occurs once.
#
# NOT HERE, and why: the storage write itself, and its removal when a machine is unlisted, moved by a
# rotation or deleted with its account - a local dev never evicts the object, so what storage holds is
# never read back without the memory beside it; the throttle that decides the write is presence.js's,
# mutated in cloudflare-worker-presence.psd1 and caught by its pure checks.
@{
    Target = "relays\cloudflare\worker\accounts.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-accounts.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "machine-never-heard"
           Find = 'if (device.startsWith(MACHINE_DEVICE)) await this.heard(device.slice(MACHINE_DEVICE.length), now);'
           Replace = '' }
        @{ Name = "heard-under-another-name"
           Find = 'if (device.startsWith(MACHINE_DEVICE)) await this.heard(device.slice(MACHINE_DEVICE.length), now);'
           Replace = 'if (device.startsWith(MACHINE_DEVICE)) await this.heard(device, now);' }
        @{ Name = "view-forgets-memory"
           Find = 'lastSeenAt: lastSeenOf(this.seen.get(entry.keyId), stored.get(SEEN + entry.keyId))'
           Replace = 'lastSeenAt: lastSeenOf(undefined, stored.get(SEEN + entry.keyId))' }
        @{ Name = "view-shows-no-time"
           Find = 'lastSeenAt: lastSeenOf(this.seen.get(entry.keyId), stored.get(SEEN + entry.keyId))'
           Replace = 'lastSeenAt: null' }
        @{ Name = "memory-not-kept"
           Find = 'this.seen.set(keyId, n.held);'
           Replace = ''
           Expect = "survives"
           Reason = "With nothing kept in memory every request is written (noteSeen of undefined writes), and the view reads storage: the phone is shown the same second. The harm is a storage write per request, which a local dev cannot count; the throttle's own rule is held by presence.js's pure checks (written-on-every-request)." }
    )
}
