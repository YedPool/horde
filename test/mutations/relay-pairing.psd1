# Mutations of relay/Pairing.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-pairing.psd1
# Each switches off one check of completing a pairing - replay, expiry, the code, a rotation since the
# offer, user verification, the offer's bounds - and test\test-relay-pairing.ps1 must fail for every
# one. Every find string occurs once in the target.
@{
    Target = "relay\Pairing.ps1"
    Suite  = "test\test-relay-pairing.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "replay-allowed"
           Find = 'if ($uf.found) {'
           Replace = 'if ($false) {' }
        @{ Name = "never-expires"
           Find = 'if ($nowMs -gt $pending.expiresAt) {'
           Replace = 'if ($false) {' }
        @{ Name = "expires-a-millisecond-early"
           Find = '$nowMs -gt $pending.expiresAt'
           Replace = '$nowMs -ge $pending.expiresAt' }
        @{ Name = "code-not-checked"
           Find = 'if (-not (Test-HordeRelayBytesEqual -Left (Get-HordeRelayAsciiBytes -Text $codeHash)'
           Replace = 'if ($false -and -not (Test-HordeRelayBytesEqual -Left (Get-HordeRelayAsciiBytes -Text $codeHash)' }
        @{ Name = "rotation-does-not-void"
           Find = 'if ($id.value.horde -cne $pending.horde -or $id.value.sign.keyId -cne $pending.machine) {'
           Replace = 'if ($false) {' }
        @{ Name = "verification-not-required"
           Find = '-RequireUserVerification $true'
           Replace = '-RequireUserVerification $false' }
        @{ Name = "used-mark-not-written"
           Find = '$moved = Write-HordeRelayRecordFile -Dir ([System.IO.Path]::Combine($root, "used")) -Name ($resp.offer + ".json") -Text $used'
           Replace = '$moved = "moved"' }
        @{ Name = "any-lifetime"
           Find = 'if ($TtlSeconds -lt $limits.minTtlSeconds -or $TtlSeconds -gt $limits.maxTtlSeconds) {'
           Replace = 'if ($false) {' }
        @{ Name = "origin-not-under-rp"
           Find = 'if ($hostPart -cne $RpId -and -not $hostPart.EndsWith("." + $RpId)) {'
           Replace = 'if ($false) {' }
        @{ Name = "fingerprint-not-checked"
           Find = 'if ($given -cnotmatch ''\A[0-9]{8}\z'' -or -not (Test-HordeRelayBytesEqual'
           Replace = 'if ($false -and -not (Test-HordeRelayBytesEqual' }
        @{ Name = "fingerprint-ignores-offer"
           Find = '"horde-relay/pairing/v1 fingerprint`n"), $Challenge, $Public)'
           Replace = '"horde-relay/pairing/v1 fingerprint`n"), $Public)' }
        @{ Name = "earlier-device-not-named"
           Find = 'if ($null -ne $Earlier) {'
           Replace = 'if ($false) {' }
    )
}
