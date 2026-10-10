# Mutations of relay/Bytes.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-bytes.psd1
# Each loosens the one-spelling decoder or breaks HKDF, and test\test-relay-crypto.ps1 must fail for
# every one. Every find string occurs once in the target.
@{
    Target = "relay\Bytes.ps1"
    Suite  = "test\test-relay-crypto.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "padding-accepted"
           Find = 'if ($Text -cnotmatch ''\A[A-Za-z0-9_-]*\z'') {'
           Replace = 'if ($Text -cnotmatch ''\A[A-Za-z0-9_=+/-]*\z'') {' }
        @{ Name = "stray-bits-accepted"
           Find = 'if ((ConvertTo-HordeRelayBase64Url -Bytes $decoded) -cne $Text) {'
           Replace = 'if ($false) {' }
        @{ Name = "hex-any-case"
           Find = 'if ($Text -cnotmatch ''\A([0-9a-f]{2})*\z'') {'
           Replace = 'if ($Text -notmatch ''\A([0-9a-f]{2})*\z'') {' }
        @{ Name = "hkdf-counter-from-zero"
           Find = '$counter = 1'
           Replace = '$counter = 0' }
        @{ Name = "hkdf-previous-block-dropped"
           Find = '-Bytes (Join-HordeRelayBytes -Parts @($prev, $Info, [byte[]]@([byte]$counter)))'
           Replace = '-Bytes (Join-HordeRelayBytes -Parts @($Info, [byte[]]@([byte]$counter)))' }
        @{ Name = "empty-salt-not-zeros"
           Find = 'if ($s.Length -eq 0) { $s = New-Object byte[] 32 }'
           Replace = 'if ($s.Length -eq 0) { $s = New-Object byte[] 1 }'
           Expect = "survives"
           Reason = "an equivalent mutant: HMAC pads any key shorter than its block with zeros, so one zero byte, 32 zero bytes and an empty salt are the same key (RFC 2104); the branch only says in code what RFC 5869 says in words" }
        @{ Name = "equal-ignores-length"
           Find = 'if ($Left.Length -ne $Right.Length) { return $false }'
           Replace = 'if ($Left.Length -gt $Right.Length) { return $false }' }
    )
}
