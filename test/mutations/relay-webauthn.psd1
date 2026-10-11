# Mutations of relay/WebAuthn.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-webauthn.psd1
# Each switches off one check of WebAuthn Level 3 section 7.2 that the verifier makes, and
# test\test-relay-webauthn.ps1 - whose refused fixtures are each wrong in one way only - must fail for
# every one. Every find string occurs once in the target.
@{
    Target = "relay\WebAuthn.ps1"
    Suite  = "test\test-relay-webauthn.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "client-data-cap-off"
           Find = 'if ($ClientDataJson.Length -gt $limits.clientDataJsonBytes) {'
           Replace = 'if ($false) {' }
        @{ Name = "utf8-not-strict"
           Find = 'New-Object System.Text.UTF8Encoding -ArgumentList $false, $true'
           Replace = 'New-Object System.Text.UTF8Encoding -ArgumentList $false, $false' }
        @{ Name = "repeated-member-read"
           Find = 'if ($dups.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-type"
           Find = 'if ($names -cnotcontains "type" -or $cd.type -isnot [string] -or $cd.type -cne $Type) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-challenge"
           Find = 'if ($names -cnotcontains "challenge" -or $cd.challenge -isnot [string] -or $cd.challenge -cne (ConvertTo-HordeRelayBase64Url -Bytes $Challenge)) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-origin"
           Find = 'if ($names -cnotcontains "origin" -or $cd.origin -isnot [string] -or $Origins -cnotcontains $cd.origin) {'
           Replace = 'if ($false) {' }
        @{ Name = "origin-ignoring-case"
           Find = '$Origins -cnotcontains $cd.origin'
           Replace = '$Origins -notcontains $cd.origin' }
        @{ Name = "cross-origin-allowed"
           Find = 'if ($names -ccontains "crossOrigin" -and -not ($cd.crossOrigin -is [bool] -and $cd.crossOrigin -eq $false)) {'
           Replace = 'if ($false) {' }
        @{ Name = "top-origin-allowed"
           Find = 'if ($names -ccontains "topOrigin") {'
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
        @{ Name = "attested-data-allowed"
           Find = 'if (($flags -band 0x40) -ne 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "backup-state-without-eligibility"
           Find = 'if (($flags -band 0x10) -ne 0 -and ($flags -band 0x08) -eq 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "extension-flag-not-matched"
           Find = 'if ((($flags -band 0x80) -ne 0) -ne $hasExtensionBytes) {'
           Replace = 'if ($false) {' }
        @{ Name = "short-authenticator-data"
           Find = 'if ($ad.Length -lt 37) {'
           Replace = 'if ($false) {' }
        @{ Name = "signature-not-verified"
           Find = 'if (-not (Test-HordeRelayEs256Signature -Public $Public -Bytes $signed -Signature $p1363 -AllowHighS)) {'
           Replace = 'if ($false) {' }
        @{ Name = "high-s-refused-for-passkeys"
           Find = '-Signature $p1363 -AllowHighS)) {'
           Replace = '-Signature $p1363)) {' }
        @{ Name = "client-data-not-hashed"
           Find = '$signed = Join-HordeRelayBytes -Parts @($ad, (Get-HordeRelaySha256 -Bytes $ClientDataJson))'
           Replace = '$signed = Join-HordeRelayBytes -Parts @($ad, $ClientDataJson)' }
        @{ Name = "counter-misread"
           Find = '([long]$ad[35] -shl 8) + [long]$ad[36]'
           Replace = '([long]$ad[35] -shl 8)' }
    )
}
