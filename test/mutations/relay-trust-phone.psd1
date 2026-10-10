# Mutations of relay/Trust.ps1's phone identity keys (relay PR 6). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-trust-phone.psd1
# Each lets a phone key be trusted that should not be; test\test-relay-channels.ps1 must fail for every one.
@{
    Target = "relay\Trust.ps1"
    Suite  = "test\test-relay-channels.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "pending-passkey-vouches"
           Find = '$voucher = @($s.devices | Where-Object { $_.keyId -ceq $By -and $_.state -ceq "trusted" }) | Select-Object -First 1'
           Replace = '$voucher = @($s.devices | Where-Object { $_.keyId -ceq $By }) | Select-Object -First 1' }
        @{ Name = "vouch-not-checked-when-added"
           Find = '    if (-not $check.ok) { return (New-HordeUnknown -Reason ("the vouch for the phone key is refused: " + $check.reason)) }'
           Replace = '' }
        @{ Name = "vouch-not-checked-when-read"
           Find = '        if (-not $check.ok) { $fail.reason = ("the vouch for the phone key " + $r.agreeKeyId + " does not verify: " + $check.reason); return $fail }'
           Replace = '' }
        @{ Name = "phone-key-outlives-its-passkey"
           Find = 'if ($by.state -cne "trusted") { $state = "untrusted";'
           Replace = 'if ($false) { $state = "untrusted";' }
        @{ Name = "untrusted-phone-keys-handed-out"
           Find = '$out = @($s.phones | Where-Object { $_.state -ceq "trusted" } | Sort-Object agreeKeyId'
           Replace = '$out = @($s.phones | Sort-Object agreeKeyId' }
        @{ Name = "vouch-not-bound-to-the-horde"
           Find = '("horde-relay/phone-key/v1 vouch`n" + $Horde + "`n" + $AgreePublic)'
           Replace = '("horde-relay/phone-key/v1 vouch`n" + "`n" + $AgreePublic)' }
    )
}
