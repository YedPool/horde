# Mutations of relay/Trust.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-trust.psd1
# Each lets a revoked, pending, expired, foreign or own key be trusted, and test\test-relay-pairing.ps1 must fail for
# every one. Every find string occurs once in the target.
@{
    Target = "relay\Trust.ps1"
    Suite  = "test\test-relay-pairing.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "untrusted-device-trusted"
           Find = 'foreach ($d in @($s.devices | Where-Object { $_.state -ceq "trusted" })) {'
           Replace = 'foreach ($d in @($s.devices)) {' }
        @{ Name = "untrusted-machine-trusted"
           Find = 'foreach ($m in @($s.machines | Where-Object { $_.state -ceq "trusted" })) {'
           Replace = 'foreach ($m in @($s.machines)) {' }
        @{ Name = "find-one-ignores-revocation"
           Find = 'if ($hit.state -ceq "revoked") {'
           Replace = 'if ($false) {' }
        @{ Name = "peer-of-another-horde"
           Find = 'if ($c.value.horde -cne $horde.value) {'
           Replace = 'if ($false) {' }
        @{ Name = "own-card-added"
           Find = 'if ($me.state -ceq "known" -and ('
           Replace = 'if ($false -and (' }
        @{ Name = "revoked-peer-added-again"
           Find = 'if ($null -ne $prior.revoked) {'
           Replace = 'if ($false) {' }
        @{ Name = "pending-never-expires"
           Find = '$state = $(if ($nowMs -le $r.pendingUntil) { "pending" } else { "expired" })'
           Replace = '$state = "pending"' }
        @{ Name = "expires-a-millisecond-early"
           Find = '$nowMs -le $r.pendingUntil'
           Replace = '$nowMs -lt $r.pendingUntil' }
        @{ Name = "trusted-without-confirmation"
           Find = 'elseif ($null -eq $conf) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "countersigner-revocation-ignored"
           Find = 'if ($by.state -ceq "trusted") { $state = "trusted"; $why = "" }'
           Replace = 'if ($true) { $state = "trusted"; $why = "" }' }
        @{ Name = "countersign-not-verified"
           Find = 'if (-not $check.ok) { return (New-HordeUnknown -Reason ("the countersignature is refused: "'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("the countersignature is refused: "' }
        @{ Name = "untrusted-device-countersigns"
           Find = '$dev = @($s.devices | Where-Object { $_.keyId -ceq $By -and $_.state -ceq "trusted" })'
           Replace = '$dev = @($s.devices | Where-Object { $_.keyId -ceq $By })' }
    )
}
