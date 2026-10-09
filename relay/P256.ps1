# relay/P256.ps1 - NIST P-256 keys, ECDH and ECDSA, the same on every runtime.
#
# ONE COPY FOR EVERY RUNTIME. ECDiffieHellman, ECDsa, ECParameters and ECCurve are the same API in
# .NET Framework 4.8 and in .NET (PowerShell 7 on any system), so nothing here sits behind the backend
# seam (relay/Backend.ps1).
#
# WHY P-256 AND NOT X25519. Passkeys sign with P-256 (COSE ES256), WebCrypto has P-256 everywhere, and
# spike S1 (2026-10-09) proved P-256 ECDH, HKDF and ES256 byte-for-byte between PowerShell 5.1 and
# WebCrypto; CNG's X25519 export format against WebCrypto's raw X25519 was never tested.
#
# THE RAW SHARED SECRET IS NEVER SEEN. .NET Framework does not expose the ECDH secret Z, but
# DeriveKeyFromHmac(peer, SHA256, hmacKey, prepend, append) returns HMAC(hmacKey, prepend || Z ||
# append), which is exactly HKDF-Extract(salt = hmacKey, ikm = prepend || Z). HPKE's DHKEM needs no
# more than that: its first step is LabeledExtract("", "eae_prk", Z), whose input is a fixed label
# prefix followed by Z (relay/Hpke.ps1). So Z stays inside CNG - which is also what lets a
# non-exportable key (relay/Keys.ps1) do the agreement.
#
# KEYS ON THE WIRE are SEC1 uncompressed points, 0x04 || X || Y, 65 bytes - HPKE's SerializePublicKey
# for DHKEM(P-256) and WebCrypto's "raw" format. A point that is not on the curve is refused by the
# import (measured 2026-10-09 on both runtimes; test/test-relay-crypto.ps1 holds it), which is what
# stops an invalid-curve attack on the ECDH.
#
# SIGNATURES are IEEE P1363 (r || s, 64 bytes), what .NET and WebCrypto produce. WebAuthn
# authenticators return DER instead; ConvertFrom-HordeRelayDerSignature converts, and refuses every
# encoding that is not the one minimal DER form.
#
# LOW-S. Plain ECDSA accepts (r, s) and (r, n - s) alike, so one signed message has two signatures
# (review of 3bf4657: a high-S twin of a machine's envelope verified). An ES256 signature made here is
# normalised to s <= n/2, and one checked here is refused when s > n/2 - except with -AllowHighS, which
# relay/WebAuthn.ps1 passes: an authenticator emits either half and nobody can make it choose. Measured
# 2026-10-09: 21 of 40 .NET signatures came out high-S before normalising.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path $PSScriptRoot "Bytes.ps1")

function Get-HordeRelayP256Curve {
    return [System.Security.Cryptography.ECCurve]::CreateFromFriendlyName("nistP256")
}

function ConvertFrom-HordeRelayP256Public {
    # A public key object from a 65-byte SEC1 uncompressed point. Use is "ecdh" or "ecdsa". Throws on any
    # other length, a compressed or infinity point, or a point not on the curve.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes, [Parameter(Mandatory = $true)][string]$Use)
    if ($Bytes.Length -ne 65 -or $Bytes[0] -ne 4) { throw "a P-256 public key is 65 bytes, 0x04 then X then Y" }
    if (@("ecdh", "ecdsa") -cnotcontains $Use) { throw ("a key is for ecdh or ecdsa, not '" + $Use + "'") }
    $x = New-Object byte[] 32
    $y = New-Object byte[] 32
    [System.Array]::Copy($Bytes, 1, $x, 0, 32)
    [System.Array]::Copy($Bytes, 33, $y, 0, 32)
    $q = New-Object System.Security.Cryptography.ECPoint
    $q.X = $x
    $q.Y = $y
    $params = New-Object System.Security.Cryptography.ECParameters
    $params.Curve = Get-HordeRelayP256Curve
    $params.Q = $q
    $key = $(if ($Use -ceq "ecdh") { [System.Security.Cryptography.ECDiffieHellman]::Create() } else { [System.Security.Cryptography.ECDsa]::Create() })
    try { $key.ImportParameters($params) }
    catch { $key.Dispose(); throw "the public key is not a point on P-256" }
    return $key
}

function ConvertFrom-HordeRelayP256Private {
    # A private key object from a 32-byte scalar and its 65-byte public point (the RFC 9180 vectors give
    # both). For tests and vectors only: a real machine key never leaves CNG (relay/Keys.ps1).
    param([Parameter(Mandatory = $true)][byte[]]$D, [Parameter(Mandatory = $true)][byte[]]$Public, [Parameter(Mandatory = $true)][string]$Use)
    if ($D.Length -ne 32) { throw "a P-256 private scalar is 32 bytes" }
    if ($Public.Length -ne 65 -or $Public[0] -ne 4) { throw "a P-256 public key is 65 bytes, 0x04 then X then Y" }
    $x = New-Object byte[] 32
    $y = New-Object byte[] 32
    [System.Array]::Copy($Public, 1, $x, 0, 32)
    [System.Array]::Copy($Public, 33, $y, 0, 32)
    $q = New-Object System.Security.Cryptography.ECPoint
    $q.X = $x
    $q.Y = $y
    $params = New-Object System.Security.Cryptography.ECParameters
    $params.Curve = Get-HordeRelayP256Curve
    $params.Q = $q
    $params.D = $D
    $key = $(if ($Use -ceq "ecdh") { [System.Security.Cryptography.ECDiffieHellman]::Create() } else { [System.Security.Cryptography.ECDsa]::Create() })
    try { $key.ImportParameters($params) }
    catch { $key.Dispose(); throw "the private key does not match its public point on P-256" }
    return $key
}

function New-HordeRelayP256Key {
    # A fresh in-memory key pair: HPKE's ephemeral key, and keys the suites make. Not persisted.
    param([Parameter(Mandatory = $true)][string]$Use)
    if ($Use -ceq "ecdh") { return [System.Security.Cryptography.ECDiffieHellman]::Create((Get-HordeRelayP256Curve)) }
    if ($Use -ceq "ecdsa") { return [System.Security.Cryptography.ECDsa]::Create((Get-HordeRelayP256Curve)) }
    throw ("a key is for ecdh or ecdsa, not '" + $Use + "'")
}

function ConvertTo-HordeRelayP256Public {
    # The 65-byte SEC1 uncompressed point of a key object. Reading the public half needs no export
    # right, so it works on a non-exportable CNG key too.
    param([Parameter(Mandatory = $true)]$Key)
    $p = $Key.ExportParameters($false)
    if ($p.Q.X.Length -ne 32 -or $p.Q.Y.Length -ne 32) { throw "the key is not a P-256 key" }
    return ,(Join-HordeRelayBytes -Parts @([byte[]]@(4), $p.Q.X, $p.Q.Y))
}

function Get-HordeRelayKeyId {
    # The id an envelope names a key by: the first 16 bytes of SHA-256 of its 65-byte public point, as
    # 32 lower-case hex. Only a label to find a pinned key with: every signature and every decryption
    # is checked against the key itself, never trusted because an id matched.
    param([Parameter(Mandatory = $true)][byte[]]$Public)
    if ($Public.Length -ne 65 -or $Public[0] -ne 4) { throw "a P-256 public key is 65 bytes, 0x04 then X then Y" }
    $h = Get-HordeRelaySha256 -Bytes $Public
    $first = New-Object byte[] 16
    [System.Array]::Copy($h, 0, $first, 0, 16)
    return (ConvertTo-HordeRelayHex -Bytes $first)
}

function Invoke-HordeRelayEcdhExtract {
    # HKDF-Extract(Salt, Prefix || Z), where Z is the ECDH secret of Private and the peer's 65-byte
    # public point. Z itself never leaves the key's provider (see the header).
    param([Parameter(Mandatory = $true)]$Private, [Parameter(Mandatory = $true)][byte[]]$PeerPublic,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Salt, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Prefix)
    $peer = ConvertFrom-HordeRelayP256Public -Bytes $PeerPublic -Use "ecdh"
    try {
        $s = $Salt
        # An empty salt is HashLen zeros (RFC 5869). Given as bytes, never as $null: a null HMAC key makes
        # CNG use Z itself as the key (KDF_USE_SECRET_AS_HMAC_KEY), a different function.
        if ($s.Length -eq 0) { $s = New-Object byte[] 32 }
        $prk = $Private.DeriveKeyFromHmac($peer.PublicKey, [System.Security.Cryptography.HashAlgorithmName]::SHA256, $s, $Prefix, $null)
    } finally { $peer.Dispose() }
    return ,$prk
}

function Get-HordeRelayP256Order {
    # n, the order of P-256's base point, and floor(n / 2), big-endian (FIPS 186-4, D.1.2.3).
    return [pscustomobject]@{
        n = (ConvertFrom-HordeRelayHex -Text "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551")
        half = (ConvertFrom-HordeRelayHex -Text "7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a8")
    }
}

function Compare-HordeRelayUInt256 {
    # -1, 0 or 1: two 32-byte big-endian numbers compared.
    param([byte[]]$Left, [byte[]]$Right)
    for ($i = 0; $i -lt 32; $i++) {
        if ($Left[$i] -ne $Right[$i]) { return $(if ($Left[$i] -gt $Right[$i]) { 1 } else { -1 }) }
    }
    return 0
}

function Get-HordeRelaySignatureS {
    param([byte[]]$Signature)
    $s = New-Object byte[] 32
    [System.Array]::Copy($Signature, 32, $s, 0, 32)
    return ,$s
}

function ConvertTo-HordeRelayLowS {
    # The same signature with s <= n/2: (r, n - s) when s is in the upper half, else unchanged.
    param([Parameter(Mandatory = $true)][byte[]]$Signature)
    $order = Get-HordeRelayP256Order
    $s = Get-HordeRelaySignatureS -Signature $Signature
    if ((Compare-HordeRelayUInt256 -Left $s -Right $order.half) -le 0) { return ,$Signature }
    $low = New-Object byte[] 32
    $borrow = 0
    for ($i = 31; $i -ge 0; $i--) {
        $d = [int]$order.n[$i] - [int]$s[$i] - $borrow
        if ($d -lt 0) { $d += 256; $borrow = 1 } else { $borrow = 0 }
        $low[$i] = [byte]$d
    }
    $out = New-Object byte[] 64
    [System.Array]::Copy($Signature, 0, $out, 0, 32)
    [System.Array]::Copy($low, 0, $out, 32, 32)
    return ,$out
}

function New-HordeRelayEs256Signature {
    # ECDSA P-256 with SHA-256 over Bytes: 64 bytes, r || s, with s <= n/2 (see LOW-S above).
    param([Parameter(Mandatory = $true)]$Key, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes)
    $sig = $Key.SignData($Bytes, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    if ($sig.Length -ne 64) { throw "the signature is not 64 bytes: the key is not a P-256 key" }
    return ,(ConvertTo-HordeRelayLowS -Signature $sig)
}

function Test-HordeRelayEs256Signature {
    # Does Signature (64 bytes, r || s) verify over Bytes under the 65-byte public point? Never throws
    # for a bad signature or a bad key: either is $false. A high-S signature is $false unless
    # -AllowHighS (WebAuthn only; see LOW-S above).
    param([AllowEmptyCollection()][byte[]]$Public, [AllowEmptyCollection()][byte[]]$Bytes, [AllowEmptyCollection()][byte[]]$Signature, [switch]$AllowHighS)
    if ($null -eq $Public -or $null -eq $Bytes -or $null -eq $Signature -or $Signature.Length -ne 64) { return $false }
    if (-not $AllowHighS -and (Compare-HordeRelayUInt256 -Left (Get-HordeRelaySignatureS -Signature $Signature) -Right (Get-HordeRelayP256Order).half) -gt 0) { return $false }
    try { $pub = ConvertFrom-HordeRelayP256Public -Bytes $Public -Use "ecdsa" } catch { return $false }
    try { return [bool]$pub.VerifyData($Bytes, $Signature, [System.Security.Cryptography.HashAlgorithmName]::SHA256) }
    catch { return $false }
    finally { $pub.Dispose() }
}

function ConvertFrom-HordeRelayDerInteger {
    # One minimal, positive DER INTEGER at Offset, as exactly 32 big-endian bytes, and where it ends.
    param([byte[]]$Der, [int]$Offset)
    if ($Offset + 2 -gt $Der.Length -or $Der[$Offset] -ne 0x02) { throw "the signature's DER does not hold an INTEGER where one belongs" }
    $len = [int]$Der[$Offset + 1]
    if ($len -lt 1 -or $len -gt 33) { throw "a P-256 signature INTEGER is 1 to 33 bytes long" }
    $start = $Offset + 2
    if ($start + $len -gt $Der.Length) { throw "the signature's DER INTEGER runs past its end" }
    if (($Der[$start] -band 0x80) -ne 0) { throw "the signature's DER INTEGER is negative" }
    # Minimal: a leading zero only to keep the next byte's top bit from reading as a sign.
    if ($len -gt 1 -and $Der[$start] -eq 0 -and ($Der[$start + 1] -band 0x80) -eq 0) { throw "the signature's DER INTEGER has a needless leading zero" }
    $skip = 0
    if ($len -eq 33) {
        if ($Der[$start] -ne 0) { throw "the signature's DER INTEGER is larger than 32 bytes" }
        $skip = 1
    }
    $out = New-Object byte[] 32
    [System.Array]::Copy($Der, $start + $skip, $out, 32 - ($len - $skip), $len - $skip)
    return [pscustomobject]@{ value = $out; next = ($start + $len) }
}

function ConvertFrom-HordeRelayDerSignature {
    # A DER ECDSA signature (SEQUENCE of two INTEGERs, what a WebAuthn authenticator returns for ES256) as
    # 64 bytes r || s. Throws on anything but the one minimal encoding: a long-form length, a negative or
    # padded integer, bytes after the sequence, or r or s of zero.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Der)
    # The longest P-256 DER signature is 72 bytes, so every length here fits the short form.
    if ($Der.Length -lt 8 -or $Der.Length -gt 72) { throw "a P-256 DER signature is 8 to 72 bytes" }
    if ($Der[0] -ne 0x30) { throw "the signature is not a DER SEQUENCE" }
    if ([int]$Der[1] -ne $Der.Length - 2) { throw "the signature's DER SEQUENCE length does not match its bytes" }
    $r = ConvertFrom-HordeRelayDerInteger -Der $Der -Offset 2
    $s = ConvertFrom-HordeRelayDerInteger -Der $Der -Offset $r.next
    if ($s.next -ne $Der.Length) { throw "the signature has bytes after its second INTEGER" }
    $zero = New-Object byte[] 32
    if ((Test-HordeRelayBytesEqual -Left $r.value -Right $zero) -or (Test-HordeRelayBytesEqual -Left $s.value -Right $zero)) { throw "a signature value of zero is never valid" }
    return ,(Join-HordeRelayBytes -Parts @($r.value, $s.value))
}
