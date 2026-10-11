# Mutations of relay/Registration.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-registration.psd1
# Each switches off one check of WebAuthn Level 3 section 7.1 that the verifier makes, and
# test\test-relay-registration.ps1 - whose refused registrations are each wrong in one way only - must
# fail for every one. Every find string occurs once in the target.
@{
    Target = "relay\Registration.ps1"
    Suite  = "test\test-relay-registration.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "short-challenge-allowed"
           Find = 'if ($Challenge.Length -lt 16) {'
           Replace = 'if ($false) {' }
        @{ Name = "assertion-type-expected"
           Find = '-Type "webauthn.create"'
           Replace = '-Type "webauthn.get"' }
        @{ Name = "no-size-cap"
           Find = 'if ($AttestationObject.Length -gt $limits.attestationObjectBytes) {'
           Replace = 'if ($false) {' }
        @{ Name = "members-not-exact"
           Find = 'if (($names -join ",") -cne "attStmt,authData,fmt") {'
           Replace = 'if ($false) {' }
        @{ Name = "any-format"
           Find = 'if ($fmt.type -cne "text" -or $fmt.value -cne "none") {'
           Replace = 'if ($false) {' }
        @{ Name = "statement-allowed"
           Find = 'if ($stmt.type -cne "map" -or @($stmt.value).Count -ne 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-relying-party"
           Find = 'if (-not (Test-HordeRelayBytesEqual -Left $rpIdHash -Right'
           Replace = 'if ($false -and -not (Test-HordeRelayBytesEqual -Left $rpIdHash -Right' }
        @{ Name = "presence-not-required"
           Find = 'if (($flags -band 0x01) -eq 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "verification-not-required"
           Find = 'if ($RequireUserVerification -and ($flags -band 0x04) -eq 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "backup-state-without-eligibility"
           Find = 'if (($flags -band 0x10) -ne 0 -and ($flags -band 0x08) -eq 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "attested-data-not-required"
           Find = 'if (($flags -band 0x40) -eq 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "credential-id-any-length"
           Find = 'if ($idLen -lt 1 -or $idLen -gt $limits.credentialIdBytes) {'
           Replace = 'if ($false) {' }
        @{ Name = "raw-id-not-compared"
           Find = 'if (-not (Test-HordeRelayBytesEqual -Left $credId -Right $RawId)) {'
           Replace = 'if ($false) {' }
        @{ Name = "flag-without-extensions"
           Find = 'if ($keyRead.next -ge $ad.Length) {'
           Replace = 'if ($false) {' }
        @{ Name = "bytes-after-key-without-flag"
           Find = '} elseif ($keyRead.next -ne $ad.Length) {'
           Replace = '} elseif ($false) {' }
        @{ Name = "hmac-secret-any-value"
           Find = '$hmacSecret = [bool]($null -ne $hs -and $hs.type -ceq "bool" -and $hs.value -eq $true)'
           Replace = '$hmacSecret = [bool]($null -ne $hs)' }
    )
}
