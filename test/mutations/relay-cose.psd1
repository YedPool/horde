# Mutations of relay/Cose.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-cose.psd1
# Each switches off one check of the COSE EC2 ES256 import, and test\test-relay-registration.ps1 must
# fail for every one: a key of another type, algorithm or curve, a member too many (a private part), a
# coordinate of the wrong size or past the field prime, or a point off the curve would be enrolled.
# Every find string occurs once in the target.
@{
    Target = "relay\Cose.ps1"
    Suite  = "test\test-relay-registration.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "extra-member-allowed"
           Find = 'if ($extra.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-key-type"
           Find = 'if ($null -eq $kty -or $kty.type -cne "uint" -or $kty.value -ne 2) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-algorithm"
           Find = 'if ($alg.type -cne "nint" -or $alg.value -ne -7) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-curve"
           Find = 'if ($null -eq $crv -or $crv.type -cne "uint" -or $crv.value -ne 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "x-any-length"
           Find = 'if ($null -eq $x -or $x.type -cne "bytes" -or $x.value.Length -ne 32) {'
           Replace = 'if ($false) {' }
        @{ Name = "past-field-prime-allowed"
           Find = 'if ((Compare-HordeRelayUInt256 -Left $x.value -Right $p) -ge 0 -or (Compare-HordeRelayUInt256 -Left $y.value -Right $p) -ge 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "point-not-validated"
           Find = 'try { $k = ConvertFrom-HordeRelayP256Public -Bytes $point -Use "ecdsa"; $k.Dispose() }'
           Replace = 'try { }' }
    )
}
