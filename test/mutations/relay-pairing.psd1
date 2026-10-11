# Mutations of relay/Pairing.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-pairing.psd1
# Each switches off one check of completing a pairing - replay, expiry, the code, a rotation since the
# offer, user verification, the offer's bounds - and test\test-relay-pairing.ps1 must fail for every
# one. Every find string occurs once in the target.
# NOT HERE: Open-HordeRelayPairingSealed skipping its open-offer check. Without it the code that follows
# reads an offer that is not there and stops with an error, which Mutate.ps1 rightly does not count as a
# catch; the checks it shares with Complete (replay, expiry) are mutated above, and the suite opens a
# sealed response for an expired, a used and an unknown offer and requires each refusal by name.
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
           Find = 'if ($given -cnotmatch ''\A[0-9]{12}\z'' -or -not (Test-HordeRelayBytesEqual'
           Replace = 'if ($false -and -not (Test-HordeRelayBytesEqual' }
        @{ Name = "fingerprint-ignores-offer"
           Find = '"horde-relay/pairing/v1 fingerprint`n"), $Challenge, $Public, $idLen, $CredentialId, (Get-HordeRelayAsciiBytes -Text $RpId))'
           Replace = '"horde-relay/pairing/v1 fingerprint`n"), $Public)' }
        @{ Name = "fingerprint-ignores-credential-and-rp"
           Find = '$Challenge, $Public, $idLen, $CredentialId, (Get-HordeRelayAsciiBytes -Text $RpId)))'
           Replace = '$Challenge, $Public))' }
        @{ Name = "fingerprint-eight-digits"
           Find = '% 1000000000000 }'
           Replace = '% 100000000 }' }
        @{ Name = "earlier-device-not-named"
           Find = 'if ($null -ne $Earlier) {'
           Replace = 'if ($false) {' }
        @{ Name = "window-from-offer"
           Find = '-PendingUntil $pendingUntil'
           Replace = '-PendingUntil $pending.expiresAt' }
        # The response through the relay (Open-HordeRelayPairingSealed) and its bounds.
        @{ Name = "offer-names-no-pairing-mailbox"
           Find = 'pairMailbox = (Get-HordeRelayPairingMailbox -Horde $id.value.horde -Offer $offerId); rpId = $RpId;'
           Replace = 'pairMailbox = $id.value.mailbox; rpId = $RpId;' }
        @{ Name = "sealed-size-not-bounded"
           Find = 'if ($Text.Length -gt $limits.maxSealedChars) {'
           Replace = 'if ($false) {' }
        @{ Name = "sealed-for-another-offer-opened"
           Find = 'if ($sealed.offer -cne $Offer) {'
           Replace = 'if ($false) {' }
        @{ Name = "sealed-key-id-not-compared"
           Find = 'if ($sealed.agreeKeyId -cne $id.value.agree.keyId) {'
           Replace = 'if ($false) {' }
        @{ Name = "sealed-aad-without-offer"
           Find = '"horde-relay/pairing/v1 response aad`n" + $Horde + "`n" + $Offer + "`n" + $AgreeKeyId'
           Replace = '"horde-relay/pairing/v1 response aad`n" + $Horde + "`n" + $AgreeKeyId' }
        @{ Name = "sealed-inner-size-not-bounded"
           Find = 'if ($plain.Length -gt $limits.maxResponseChars) {'
           Replace = 'if ($false) {' }
        @{ Name = "sealed-inner-not-ascii-taken"
           Find = 'foreach ($b in $plain) { if ($b -lt 0x20 -or $b -gt 0x7E) {'
           Replace = 'foreach ($b in $plain) { if ($false) {' }
        @{ Name = "sealed-inner-offer-not-compared"
           Find = 'if ($resp.value.offer -cne $Offer) {'
           Replace = 'if ($false) {' }
        @{ Name = "pasted-response-not-bounded"
           Find = 'if ($Response.Length -gt $limits.maxResponseChars) {'
           Replace = 'if ($false) {' }
        @{ Name = "machine-label-ignored"
           Find = '-Label $(if ($Label -cne "") { $Label } else { $resp.label })'
           Replace = '-Label $resp.label' }
        @{ Name = "machine-label-not-checked-first"
           Find = 'if ($Label -cne "" -and (Test-HordeRelayRecordValue -Kind "label" -Value $Label) -cne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "refusal-shows-the-fingerprint"
           Find = '"'', now " + $Earlier.state'
           Replace = '"'', fingerprint " + $Earlier.fingerprint + ", now " + $Earlier.state' }
        @{ Name = "window-not-the-setting"
           Find = '[long]$settings.value.values.pendingConfirmMinutes * 60000'
           Replace = '[long]10 * 60000' }
        @{ Name = "grant-over-another-expiry"
           Find = '-Machine $id.value.sign.keyId -ExpiresAt $expires))'
           Replace = '-Machine $id.value.sign.keyId -ExpiresAt ($expires + 1)))' }
        @{ Name = "grant-of-another-domain"
           Find = '"horde-relay/pairing/v1 account-grant`n"'
           Replace = '"horde-relay/pairing/v1 account-grant-v2`n"' }
        @{ Name = "grant-check-takes-anything"
           Find = 'return (Test-HordeRelayEs256Signature -Public $SignPublic -Bytes (Get-HordeRelayAccountGrantBytes'
           Replace = 'return $true; (Test-HordeRelayEs256Signature -Public $SignPublic -Bytes (Get-HordeRelayAccountGrantBytes' }
    )
}
