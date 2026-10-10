# Mutations of relay/Identity.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-identity.psd1
# Each switches off one rule of the machine identity - made once, one horde, keys pinned, rotation
# retiring, vouching and keeping the old agreement key for its grace only - and
# test\test-relay-pairing.ps1 must fail for every one. Every find string occurs once in the target.
@{
    Target = "relay\Identity.ps1"
    Suite  = "test\test-relay-pairing.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "horde-any-text"
           Find = 'if ($Name -cnotmatch $script:HordeRelayHordePattern) {'
           Replace = 'if ($false) {' }
        @{ Name = "horde-device-name"
           Find = 'if ($Name -cmatch $script:HordeRelayDeviceNamePattern) {'
           Replace = 'if ($false) {' }
        @{ Name = "made-twice"
           Find = 'if (@($have.machines).Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "moved-by-a-setting"
           Find = 'if ($horde.state -ceq "absent" -or $horde.value -cne $cur.horde) {'
           Replace = 'if ($false) {' }
        @{ Name = "key-not-pinned"
           Find = 'if ((ConvertTo-HordeRelayBase64Url -Bytes $k.value.publicKey) -cne $pinned) {'
           Replace = 'if ($false) {' }
        @{ Name = "old-keys-kept"
           Find = '$left = Remove-HordeRelayKey -Name $old.signName -Scope $old.scope'
           Replace = '$left = [pscustomobject]@{ state = "known" }' }
        @{ Name = "no-vouch"
           Find = '$values.vouch = Get-HordeRelayRetirementVouch -Record $old'
           Replace = '$values.vouch = ""; $null = Get-HordeRelayRetirementVouch -Record $old' }
        @{ Name = "card-proof-not-checked"
           Find = 'if (-not (Test-HordeRelayEs256Signature -Public $signPub -Bytes $signed -Signature $proof)) {'
           Replace = 'if ($false) {' }
        @{ Name = "no-grace"
           Find = '$graceMs = [long]$settings.value.values.retiredAgreeKeyDays * 86400000'
           Replace = '$graceMs = 0' }
        @{ Name = "released-before-grace-ends"
           Find = 'if ($nowMs -lt $have.retired[$k].agreeKeptUntil) { continue }'
           Replace = 'if ($false) { continue }' }
        @{ Name = "kept-a-millisecond-too-long"
           Find = '$nowMs -lt $have.retired[$k].agreeKeptUntil'
           Replace = '$nowMs -le $have.retired[$k].agreeKeptUntil' }
        @{ Name = "opens-past-grace"
           Find = 'if ($NowMs -lt $Have.retired[$k].agreeKeptUntil) {'
           Replace = 'if ($true) {' }
    )
}
