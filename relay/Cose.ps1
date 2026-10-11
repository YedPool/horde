# relay/Cose.ps1 - a passkey's public key, from the COSE_Key its registration carries to the 65-byte
# point every other relay file uses.
#
# WHY ONLY ES256. A passkey that signs the founder's answers is checked by relay/WebAuthn.ps1, which
# verifies ES256 (ECDSA on P-256 with SHA-256) and nothing else: one algorithm, the one every passkey
# provider offers and WebCrypto has everywhere (relay design, Q6). Pairing asks the phone for ES256 only
# (pubKeyCredParams [{type: public-key, alg: -7}]), so any other key is a phone that did not do what it
# was asked, and is refused with what it was.
#
# WHAT IS CHECKED (RFC 9052 section 7, RFC 9053 section 7.1.1, WebAuthn Level 3 section 6.5.1.1), each
# refusal naming its member:
#   - the key is a CBOR map (relay/Cbor.ps1, which has already refused a label written twice);
#   - it has EXACTLY the members 1 (kty), 3 (alg), -1 (crv), -2 (x) and -3 (y) - an extra member is
#     refused, above all -4 (d): a "public" key that carries its private scalar was made by something
#     that does not keep secrets, and is not trusted to sign for the founder;
#   - kty is 2 (EC2), alg is -7 (ES256), crv is 1 (P-256);
#   - x and y are byte strings of exactly 32 bytes (y as a boolean, the compressed form, is refused);
#   - x and y are each below the field prime p. A 32-byte number at or above p names no field element,
#     and a reader that reduced it modulo p would import ANOTHER key than the bytes say - so the bytes
#     are refused before any import (measured 2026-10-09: whether CNG reduces or refuses is not
#     something this file relies on);
#   - the point is on P-256: ConvertFrom-HordeRelayP256Public imports it, which refuses a point off the
#     curve on both runtimes (relay/P256.ps1). That is what stops an invalid-curve key from being
#     enrolled at all, not only from verifying.
#
# Answers { ok; reason; public; alg } and never throws for the input.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path $PSScriptRoot "Bytes.ps1")
. (Join-Path $PSScriptRoot "P256.ps1")
. (Join-Path $PSScriptRoot "Cbor.ps1")

function Get-HordeRelayP256FieldPrime {
    # p of P-256, big-endian (FIPS 186-4, D.1.2.3).
    return ,(ConvertFrom-HordeRelayHex -Text "ffffffff00000001000000000000000000000000ffffffffffffffffffffffff")
}

function New-HordeRelayCoseAnswer {
    param([string]$Reason, $Public = $null, $Alg = $null)
    return [pscustomobject]@{ ok = ($Reason -ceq ""); reason = $Reason; public = $Public; alg = $Alg }
}

function ConvertFrom-HordeRelayCoseKey {
    # The 65-byte SEC1 point of a COSE EC2 ES256 key, from a read CBOR map value (relay/Cbor.ps1).
    param([Parameter(Mandatory = $true)]$Map)
    if ($Map.type -cne "map") { return (New-HordeRelayCoseAnswer -Reason "the credential public key is not a COSE map") }
    $names = @(Get-HordeRelayCborKeyNames -Map $Map)
    $extra = @($names | Where-Object { @("1", "3", "-1", "-2", "-3") -cnotcontains $_ })
    if ($extra.Count -gt 0) { return (New-HordeRelayCoseAnswer -Reason ("the credential public key has a member this key type does not have: " + ($extra -join ", ") + " (only 1, 3, -1, -2 and -3)")) }
    $kty = Get-HordeRelayCborMember -Map $Map -Key 1
    if ($null -eq $kty -or $kty.type -cne "uint" -or $kty.value -ne 2) { return (New-HordeRelayCoseAnswer -Reason "the credential public key is not an EC2 key (kty 2); only ES256 passkeys are paired") }
    $alg = Get-HordeRelayCborMember -Map $Map -Key 3
    if ($null -eq $alg) { return (New-HordeRelayCoseAnswer -Reason "the credential public key has no alg member") }
    if ($alg.type -cne "nint" -or $alg.value -ne -7) { return (New-HordeRelayCoseAnswer -Reason ("the credential public key's alg is " + $alg.value + ", not -7 (ES256)")) }
    $crv = Get-HordeRelayCborMember -Map $Map -Key (-1)
    if ($null -eq $crv -or $crv.type -cne "uint" -or $crv.value -ne 1) { return (New-HordeRelayCoseAnswer -Reason "the credential public key's curve is not P-256 (crv 1)") }
    $x = Get-HordeRelayCborMember -Map $Map -Key (-2)
    $y = Get-HordeRelayCborMember -Map $Map -Key (-3)
    if ($null -eq $x -or $x.type -cne "bytes" -or $x.value.Length -ne 32) { return (New-HordeRelayCoseAnswer -Reason "the credential public key's x is not a byte string of 32 bytes") }
    if ($null -eq $y -or $y.type -cne "bytes" -or $y.value.Length -ne 32) { return (New-HordeRelayCoseAnswer -Reason "the credential public key's y is not a byte string of 32 bytes (a compressed point is not read)") }
    $p = Get-HordeRelayP256FieldPrime
    if ((Compare-HordeRelayUInt256 -Left $x.value -Right $p) -ge 0 -or (Compare-HordeRelayUInt256 -Left $y.value -Right $p) -ge 0) {
        return (New-HordeRelayCoseAnswer -Reason "the credential public key has a coordinate at or above the field prime: not a field element")
    }
    $point = Join-HordeRelayBytes -Parts @([byte[]]@(4), $x.value, $y.value)
    try { $k = ConvertFrom-HordeRelayP256Public -Bytes $point -Use "ecdsa"; $k.Dispose() }
    catch { return (New-HordeRelayCoseAnswer -Reason ("the credential public key is refused: " + $_.Exception.Message)) }
    return (New-HordeRelayCoseAnswer -Reason "" -Public $point -Alg -7)
}

function ConvertFrom-HordeRelayCoseKeyBytes {
    # The same, from the COSE_Key's own bytes, which must be one CBOR item and nothing after it.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes)
    $r = Read-HordeRelayCbor -Bytes $Bytes -Whole
    if (-not $r.ok) { return (New-HordeRelayCoseAnswer -Reason ("the credential public key is not CBOR this reader accepts: " + $r.reason)) }
    return (ConvertFrom-HordeRelayCoseKey -Map $r.value)
}
