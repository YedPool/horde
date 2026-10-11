# Mutations of the ssh transport's live far end (transports/ssh/test/FarEnd.ps1, remote plan R17c-3).
# Run, from a PowerShell-launched session on the machine with OpenSSH Server installed:
#   powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\far-end.psd1
# test\test-transport-conformance.ps1 must fail for each: dial.out and auth.peer are yes only while every
# kind of evidence each needs is shown. Exit 3 is not a pass.
@{
    Target = "transports\ssh\test\FarEnd.ps1"
    Suite  = "test\test-transport-conformance.ps1"
    Mutations = @(
        # The coordinator's (2026-10-07): auth.peer flipped with one of its named checks gone.
        @{ Name = "auth-peer-without-revoked-evidence"
           Find = '        [pscustomobject]@{ capability = "auth.peer"; kind = "refuses-revoked";'
           Replace = '        [pscustomobject]@{ capability = "auth.peer-not"; kind = "refuses-revoked";' }
        @{ Name = "auth-peer-without-changed-host-evidence"
           Find = '        [pscustomobject]@{ capability = "auth.peer"; kind = "refuses-changed-host";'
           Replace = '        [pscustomobject]@{ capability = "auth.peer"; kind = "refuses-changed-host-not";' }
        @{ Name = "dial-out-without-evidence"
           Find = '        [pscustomobject]@{ capability = "dial.out"; kind = "round-trip";'
           Replace = '        [pscustomobject]@{ capability = "dial.out"; kind = "round-trip-not";' }
        # The far end itself must be able to refuse: without RevokedKeys a revoked key with its line put
        # back connects; with the right pin the wrong-pin node connects.
        @{ Name = "sshd-without-revoked-keys"
           Find = '-AuthorizedKeys $lp.authorized -RevokedKeys $lp.revoked'
           Replace = '-AuthorizedKeys $lp.authorized' }
        @{ Name = "wrong-pin-is-right"
           Find = '$misled = & $node "node-wrong-pin" "3d9f8b2c-4e5a-4b6c-8d7e-8f9a0b1c2d3e" $otherHost'
           Replace = '$misled = & $node "node-wrong-pin" "3d9f8b2c-4e5a-4b6c-8d7e-8f9a0b1c2d3e" $hostLine' }
        @{ Name = "stranger-enrolled"
           Find = '$stranger = & $node "node-stranger" "2c8e7a1b-3d4f-4a5b-9c6d-7e8f9a0b1c2d" $hostLine'
           Replace = '$stranger = & $node "node-stranger" "2c8e7a1b-3d4f-4a5b-9c6d-7e8f9a0b1c2d" $hostLine; $null = Add-HordeSshEnrolment -HordeHome $hubHome -DeviceId "2c8e7a1b-3d4f-4a5b-9c6d-7e8f9a0b1c2d" -Key $stranger.key -HordeRoot $fakeRoot' }
    )
}
