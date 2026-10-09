# Mutations of relay/Trust.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-trust.psd1
# Each lets a revoked, foreign or own key be trusted, and test\test-relay-pairing.ps1 must fail for
# every one. Every find string occurs once in the target.
@{
    Target = "relay\Trust.ps1"
    Suite  = "test\test-relay-pairing.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "revoked-device-trusted"
           Find = 'foreach ($d in @($s.devices | Where-Object { $null -eq $_.revoked })) {'
           Replace = 'foreach ($d in @($s.devices)) {' }
        @{ Name = "revoked-machine-trusted"
           Find = 'foreach ($m in @($s.machines | Where-Object { $null -eq $_.revoked })) {'
           Replace = 'foreach ($m in @($s.machines)) {' }
        @{ Name = "find-one-ignores-revocation"
           Find = 'if ($null -ne $hit.revoked) {'
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
    )
}
