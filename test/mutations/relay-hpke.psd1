# Mutations of relay/Hpke.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-hpke.psd1
# Each changes one step of RFC 9180's base mode, and test\test-relay-crypto.ps1 - which derives every
# intermediate value of the official vector - must fail for every one. Every find string occurs once.
@{
    Target = "relay\Hpke.ps1"
    Suite  = "test\test-relay-crypto.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "kem-id-wrong"
           Find = '(Get-HordeRelayAsciiBytes -Text "KEM"), [byte[]]@(0x00, 0x10)'
           Replace = '(Get-HordeRelayAsciiBytes -Text "KEM"), [byte[]]@(0x00, 0x11)' }
        @{ Name = "aead-id-wrong"
           Find = '[byte[]]@(0x00, 0x10, 0x00, 0x01, 0x00, 0x02)'
           Replace = '[byte[]]@(0x00, 0x10, 0x00, 0x01, 0x00, 0x01)' }
        @{ Name = "version-label-wrong"
           Find = '(Get-HordeRelayAsciiBytes -Text "HPKE-v1"), $SuiteId'
           Replace = '(Get-HordeRelayAsciiBytes -Text "HPKE-v2"), $SuiteId' }
        @{ Name = "expand-length-prefix-one-byte"
           Find = '$lengthBytes = [byte[]]@([byte](($Length -shr 8) -band 0xFF), [byte]($Length -band 0xFF))'
           Replace = '$lengthBytes = [byte[]]@([byte]($Length -band 0xFF))' }
        @{ Name = "kem-context-without-recipient"
           Find = '$kemContext = Join-HordeRelayBytes -Parts @($Enc, $RecipientPublic)'
           Replace = '$kemContext = $Enc' }
        @{ Name = "mode-not-base"
           Find = '[byte[]]@(0x00), $pskIdHash, $infoHash'
           Replace = '[byte[]]@(0x01), $pskIdHash, $infoHash' }
        @{ Name = "info-not-hashed-in"
           Find = '-Label "info_hash" -Ikm $Info'
           Replace = '-Label "info_hash" -Ikm $empty' }
        @{ Name = "nonce-not-xored"
           Find = '$n[$i] = $n[$i] -bxor [byte]($s -band 0xFF)'
           Replace = '$n[$i] = $n[$i]' }
        @{ Name = "nonce-xor-little-endian"
           Find = 'for ($i = 11; $i -ge 4; $i--) {'
           Replace = 'for ($i = 4; $i -le 11; $i++) {' }
        @{ Name = "base-nonce-from-key-label"
           Find = '-Label "base_nonce" -Info $ksc -Length 12'
           Replace = '-Label "key" -Info $ksc -Length 12' }
        @{ Name = "open-failure-moves-the-sequence"
           Find = '    $plain = Unprotect-HordeRelayAesGcm -Key $Context.key -Nonce (Get-HordeRelayHpkeNonce -Context $Context) -Aad $Aad -Sealed $Sealed'
           Replace = '    $plain = Unprotect-HordeRelayAesGcm -Key $Context.key -Nonce (Get-HordeRelayHpkeNonce -Context $Context) -Aad $Aad -Sealed $Sealed; $Context.seq = $Context.seq + 1' }
    )
}
