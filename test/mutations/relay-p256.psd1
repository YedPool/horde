# Mutations of relay/P256.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-p256.psd1
# Each loosens one rule of key import, ECDH or the one-minimal-DER signature reader, and
# test\test-relay-crypto.ps1 must fail for every one. Every find string occurs once in the target.
@{
    Target = "relay\P256.ps1"
    Suite  = "test\test-relay-crypto.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "compressed-point-read"
           Find = 'if ($Bytes.Length -ne 65 -or $Bytes[0] -ne 4)'
           Replace = 'if ($Bytes.Length -ne 65)' }
        @{ Name = "ecdh-prefix-dropped"
           Find = '[System.Security.Cryptography.HashAlgorithmName]::SHA256, $s, $Prefix, $null)'
           Replace = '[System.Security.Cryptography.HashAlgorithmName]::SHA256, $s, $null, $null)' }
        @{ Name = "der-sign-byte-accepted"
           Find = 'if (($Der[$start] -band 0x80) -ne 0) { throw "the signature''s DER INTEGER is negative" }'
           Replace = '' }
        @{ Name = "der-needless-zero-accepted"
           Find = 'if ($len -gt 1 -and $Der[$start] -eq 0 -and ($Der[$start + 1] -band 0x80) -eq 0) { throw "the signature''s DER INTEGER has a needless leading zero" }'
           Replace = '' }
        @{ Name = "der-trailing-bytes-accepted"
           Find = 'if ($s.next -ne $Der.Length) { throw "the signature has bytes after its second INTEGER" }'
           Replace = '' }
        @{ Name = "der-sequence-length-unchecked"
           Find = 'if ([int]$Der[1] -ne $Der.Length - 2) { throw "the signature''s DER SEQUENCE length does not match its bytes" }'
           Replace = '' }
        @{ Name = "der-zero-accepted"
           Find = 'if ((Test-HordeRelayBytesEqual -Left $r.value -Right $zero) -or (Test-HordeRelayBytesEqual -Left $s.value -Right $zero)) { throw "a signature value of zero is never valid" }'
           Replace = '' }
        @{ Name = "der-any-tag"
           Find = 'if ($Der[0] -ne 0x30) { throw "the signature is not a DER SEQUENCE" }'
           Replace = '' }
        @{ Name = "verify-ignores-length"
           Find = '-or $Signature.Length -ne 64) { return $false }'
           Replace = ') { return $false }'
           Expect = "survives"
           Reason = "an equivalent mutant: VerifyData answers false for a signature of any other length on both runtimes (measured 2026-10-09 by this mutant), so the length check only says early what the verify says anyway" }
        @{ Name = "key-id-from-whole-hash"
           Find = '[System.Array]::Copy($h, 0, $first, 0, 16)'
           Replace = '[System.Array]::Copy($h, 16, $first, 0, 16)' }
    )
}
