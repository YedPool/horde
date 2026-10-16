# Mutations of relay/Join.ps1, phone-started pairing's rules (the founder, 2026-10-14). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-join.psd1
# Each lets a new phone be trusted, or a request be taken, that must not; test\test-relay-join.ps1 must
# fail for every one. Every find string occurs once.
@{
    Target = "relay\Join.ps1"
    Suite  = "test\test-relay-join.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "approval-hash-not-compared"
           Find = 'if (-not (Test-HordeRelayBytesEqual -Left (Get-HordeRelayAsciiBytes -Text $want) -Right (Get-HordeRelayAsciiBytes -Text $Transcript))) {'
           Replace = 'if ($false) {' }
        @{ Name = "approval-for-another-device-taken"
           Find = 'if ($j.device.id -cne $Device) {'
           Replace = 'if ($false) {' }
        @{ Name = "second-pending-request-taken"
           Find = 'if ($null -ne $open) { return (New-HordeRelayRefusedOutcome'
           Replace = 'if ($false) { return (New-HordeRelayRefusedOutcome' }
        @{ Name = "request-under-any-key-taken"
           Find = 'if ($Key -cne (Get-HordeRelayJoinKey -Request $q.request)) {'
           Replace = 'if ($false) {' }
        @{ Name = "expired-request-taken"
           Find = 'if ($nowMs -gt $q.expiresAt) { return (New-HordeRelayRefusedOutcome'
           Replace = 'if ($false) { return (New-HordeRelayRefusedOutcome' }
        @{ Name = "another-machines-request-taken"
           Find = 'if ($q.machine -cne $id.value.sign.keyId) {'
           Replace = 'if ($false) {' }
        @{ Name = "wrong-numbers-never-reject"
           Find = 'if ($tries -ge $limits.tries) {'
           Replace = 'if ($false) {' }
        @{ Name = "expired-request-leaves-its-passkey"
           Find = 'if ($null -ne $j.device -and $j.device.state -cne "revoked") { $null = Revoke-HordeRelayTrust'
           Replace = 'if ($false) { $null = Revoke-HordeRelayTrust' }
        @{ Name = "closed-request-approved-again"
           Find = 'if ($null -ne $v.closed) { $fail.reason = ("the join request " + $Request + " is closed ('
           Replace = 'if ($false) { $fail.reason = ("the join request " + $Request + " is closed (' }
        @{ Name = "reject-leaves-the-pending-passkey"
           Find = '    if ($null -ne $v.device -and $v.device.state -ceq "pending") {'
           Replace = '    if ($false) {' }
    )
}
