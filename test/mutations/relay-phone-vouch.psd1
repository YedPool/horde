# Mutations of relay/Trust.ps1's phone vouch item and relay/Pairing.ps1's confirmed record (THE VOUCH
# TRAVELS BY ITSELF; TELLING THE PHONE IT IS CONFIRMED - the founder, 2026-10-14). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-phone-vouch.psd1
# Each lets a vouch be taken that must be refused, or loses one that must be taken;
# test\test-relay-phone-vouch.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "relay\Trust.ps1"
    Suite  = "test\test-relay-phone-vouch.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "unsigned-vouch-taken-to-the-check"
           Find = 'if ($v.signature -ceq "" -or $v.authenticatorData -ceq "" -or $v.clientDataJSON -ceq "") { return (& $no "the phone vouch carries no signature: an unsigned announcement is never taken") }'
           Replace = '' }
        @{ Name = "another-hordes-vouch-not-refused-by-name"
           Find = 'if ($v.horde -cne $horde.value) { return (& $no ("the phone vouch is for the horde " + $v.horde + ", not this one (" + $horde.value + ")")) }'
           Replace = '' }
        @{ Name = "unreadable-store-refuses-for-good"
           Find = 'if (-not $s.ok) { return [pscustomobject]@{ outcome = "held"; reason = ("the trust store cannot be read: " + $s.reason) } }'
           Replace = '' }
        @{ Name = "refused-vouch-said-done"
           Find = 'if ($added.state -cne "known") { return (& $no ("the phone key is refused: " + $added.reason)) }'
           Replace = 'if ($added.state -cne "known") { return [pscustomobject]@{ outcome = "done"; reason = "the phone key is now in the trust store" } }' }
        @{ Name = "no-size-cap"
           Find = 'if ($Text.Length -gt 16384) {'
           Replace = 'if ($false) {' }
    )
}
