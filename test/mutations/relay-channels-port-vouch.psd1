# Mutations of channels/Port.ps1's path in for the phone vouch item (relay/Trust.ps1, THE VOUCH TRAVELS BY
# ITSELF - the founder, 2026-10-14). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channels-port-vouch.psd1
# test\test-relay-phone-vouch.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "channels\Port.ps1"
    Suite  = "test\test-relay-phone-vouch.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "vouch-item-read-as-an-envelope"
           Find = '        if (Test-HordeRelayPhoneVouchText -Text $it.text) {'
           Replace = '        if ($false) {' }
        @{ Name = "held-vouch-settled"
           Find = '            if ($pv.outcome -ceq "held") { [void]$held.Add("item " + $it.seq + ": " + $pv.reason); continue }'
           Replace = '' }
        @{ Name = "refused-vouch-counted-as-taken"
           Find = 'if ($pv.outcome -ceq "done") { [void]$vouched.Add("item " + $it.seq + ": " + $pv.reason) } else { [void]$refused.Add("item " + $it.seq + ": " + $pv.reason) }'
           Replace = '[void]$vouched.Add("item " + $it.seq + ": " + $pv.reason)' }
        @{ Name = "refused-vouch-left-unacked"
           Find = '$settled[[long]$it.seq] = $true # a vouch, done or refused: acked'
           Replace = '' }
    )
}
