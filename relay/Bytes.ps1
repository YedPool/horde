# relay/Bytes.ps1 - the byte-level helpers every relay file shares: strict encodings, hashing, HMAC,
# HKDF (RFC 5869) and randomness.
#
# ONE COPY FOR EVERY RUNTIME. Everything here is in both .NET Framework 4.8 (Windows PowerShell 5.1)
# and .NET (PowerShell 7 on any system): SHA256, HMACSHA256, RandomNumberGenerator and Convert. HKDF is
# written out from HMAC rather than taken from .NET's HKDF class, because .NET Framework has none and a
# second implementation for one runtime would be a second thing to get wrong. relay/Backend.ps1 is the
# only place where the runtimes differ (AES-GCM).
#
# POWERSHELL RETURNS ARRAYS ONE ELEMENT AT A TIME. A function that returns a byte[] has it unrolled into
# object[] (and an empty one into $null) unless it returns it with the unary comma, so every function
# here that answers bytes ends `return ,$x`. CONTRIBUTING 12 lists the trap.
#
# STRICT DECODING. Text from the relay is untrusted, and a decoder that accepts several spellings of one
# value lets two parties disagree about what was signed. ConvertFrom-HordeRelayBase64Url accepts exactly
# the one spelling ConvertTo-HordeRelayBase64Url produces: the URL alphabet, no padding, no whitespace,
# and no stray bits in the last character (measured 2026-10-09: [Convert]::FromBase64String reads
# "AB==" and "AA==" as the same byte, so a re-encode comparison is what refuses the second spelling).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). The functions run under
# -Version Latest.

function ConvertTo-HordeRelayBase64Url {
    # Bytes as unpadded base64url (RFC 4648 section 5), the form WebAuthn and JWK use.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes)
    return [System.Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function ConvertFrom-HordeRelayBase64Url {
    # The bytes of unpadded, canonical base64url text, or a throw naming What. Never a second spelling.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text, [string]$What = "the value")
    if ($Text -cnotmatch '\A[A-Za-z0-9_-]*\z') { throw ($What + " is not base64url: only A-Z, a-z, 0-9, - and _ may appear, with no padding") }
    if (($Text.Length % 4) -eq 1) { throw ($What + " is not base64url: its length cannot be a whole number of bytes") }
    $std = $Text.Replace('-', '+').Replace('_', '/')
    while (($std.Length % 4) -ne 0) { $std += "=" }
    $decoded = [System.Convert]::FromBase64String($std)
    if ((ConvertTo-HordeRelayBase64Url -Bytes $decoded) -cne $Text) { throw ($What + " is not canonical base64url: its last character carries bits that are not zero") }
    return ,$decoded
}

function ConvertTo-HordeRelayHex {
    # Bytes as lower-case hex.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes)
    $sb = New-Object System.Text.StringBuilder ($Bytes.Length * 2)
    foreach ($b in $Bytes) { [void]$sb.Append($b.ToString("x2")) }
    return $sb.ToString()
}

function ConvertFrom-HordeRelayHex {
    # The bytes of lower-case hex text (the form the RFC 9180 vectors use), or a throw.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text, [string]$What = "the value")
    if ($Text -cnotmatch '\A([0-9a-f]{2})*\z') { throw ($What + " is not lower-case hex of whole bytes") }
    $out = New-Object byte[] ($Text.Length / 2)
    for ($i = 0; $i -lt $out.Length; $i++) { $out[$i] = [System.Convert]::ToByte($Text.Substring($i * 2, 2), 16) }
    return ,$out
}

function Join-HordeRelayBytes {
    # The byte arrays of Parts, end to end. Pass at least two parts, or wrap one as (,$x): @($x) of a
    # single byte[] is the bytes themselves, not a list holding it.
    param([Parameter(Mandatory = $true)][object[]]$Parts)
    $total = 0
    foreach ($p in $Parts) { $total += ([byte[]]$p).Length }
    $out = New-Object byte[] $total
    $at = 0
    foreach ($p in $Parts) {
        $pb = [byte[]]$p
        [System.Array]::Copy($pb, 0, $out, $at, $pb.Length)
        $at += $pb.Length
    }
    return ,$out
}

function Test-HordeRelayBytesEqual {
    # Are two byte arrays equal? Every byte is compared whatever the first difference, so the time taken
    # says nothing about where a forged tag or hash first went wrong.
    param([AllowNull()][byte[]]$Left, [AllowNull()][byte[]]$Right)
    if ($null -eq $Left -or $null -eq $Right) { return $false }
    if ($Left.Length -ne $Right.Length) { return $false }
    $diff = 0
    for ($i = 0; $i -lt $Left.Length; $i++) { $diff = $diff -bor ($Left[$i] -bxor $Right[$i]) }
    return [bool]($diff -eq 0)
}

function Get-HordeRelaySha256 {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes)
    $h = [System.Security.Cryptography.SHA256]::Create()
    try { $digest = $h.ComputeHash($Bytes) } finally { $h.Dispose() }
    return ,$digest
}

function Get-HordeRelayHmacSha256 {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Key, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes)
    $mac = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList (, $Key)
    try { $digest = $mac.ComputeHash($Bytes) } finally { $mac.Dispose() }
    return ,$digest
}

function Invoke-HordeRelayHkdfExtract {
    # HKDF-Extract (RFC 5869 2.2) with SHA-256. An empty salt is HashLen zero bytes, which HMAC pads to
    # the same key as an empty one.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Salt, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Ikm)
    $s = $Salt
    if ($s.Length -eq 0) { $s = New-Object byte[] 32 }
    return ,(Get-HordeRelayHmacSha256 -Key $s -Bytes $Ikm)
}

function Invoke-HordeRelayHkdfExpand {
    # HKDF-Expand (RFC 5869 2.3) with SHA-256: Length bytes, at most 255 blocks of 32.
    param([Parameter(Mandatory = $true)][byte[]]$Prk, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Info, [Parameter(Mandatory = $true)][int]$Length)
    if ($Prk.Length -lt 32) { throw "an HKDF pseudorandom key is at least 32 bytes" }
    if ($Length -lt 1 -or $Length -gt (255 * 32)) { throw ("HKDF-Expand cannot give " + $Length + " bytes: 1 to 8160") }
    $out = New-Object byte[] $Length
    $prev = New-Object byte[] 0
    $at = 0
    $counter = 1
    while ($at -lt $Length) {
        $block = Get-HordeRelayHmacSha256 -Key $Prk -Bytes (Join-HordeRelayBytes -Parts @($prev, $Info, [byte[]]@([byte]$counter)))
        $take = [System.Math]::Min(32, $Length - $at)
        [System.Array]::Copy($block, 0, $out, $at, $take)
        $at += $take
        $prev = $block
        $counter++
    }
    return ,$out
}

function Get-HordeRelayRandomBytes {
    param([Parameter(Mandatory = $true)][int]$Count)
    $out = New-Object byte[] $Count
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($out) } finally { $rng.Dispose() }
    return ,$out
}

function Get-HordeRelayAsciiBytes {
    # The bytes of text that must be plain printable ASCII (labels, canonical headers); anything else
    # throws, so no encoding choice can change what is hashed or signed.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    if ($Text -cnotmatch '\A[\x20-\x7E\n]*\z') { throw "text that is hashed or signed must be printable ASCII" }
    return ,([System.Text.Encoding]::ASCII.GetBytes($Text))
}
