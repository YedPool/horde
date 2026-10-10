# relay/BackendDotnet.ps1 - the AES-256-GCM backend for runtimes that have
# System.Security.Cryptography.AesGcm: .NET Core 3.0 and later, which is PowerShell 7 on Windows, Linux
# and macOS. Measured 2026-10-09: present under PowerShell 7.6.6 on .NET 10.0.12, absent under Windows
# PowerShell 5.1 on .NET Framework 4.8.
#
# The tag size is passed to the constructor: .NET 8 marked the constructor without it obsolete, so that a
# caller cannot be handed a shorter tag than it meant to check. Strict lengths as in relay/Gcm.cs: a
# 32-byte key, a 12-byte nonce, a 16-byte tag.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

function Assert-HordeRelayGcmLengths {
    param([byte[]]$Key, [byte[]]$Nonce)
    if ($null -eq $Key -or $Key.Length -ne 32) { throw "the key must be 32 bytes (AES-256)" }
    if ($null -eq $Nonce -or $Nonce.Length -ne 12) { throw "the nonce must be 12 bytes" }
}

function Protect-HordeRelayDotnetGcm {
    # ciphertext || 16-byte tag.
    param([byte[]]$Key, [byte[]]$Nonce, [AllowEmptyCollection()][byte[]]$Aad, [AllowEmptyCollection()][byte[]]$Plaintext)
    Assert-HordeRelayGcmLengths -Key $Key -Nonce $Nonce
    $gcm = New-Object System.Security.Cryptography.AesGcm -ArgumentList $Key, 16
    try {
        $ct = New-Object byte[] $Plaintext.Length
        $tag = New-Object byte[] 16
        $gcm.Encrypt($Nonce, $Plaintext, $ct, $tag, $Aad)
    } finally { $gcm.Dispose() }
    return ,(Join-HordeRelayBytes -Parts @($ct, $tag))
}

function Unprotect-HordeRelayDotnetGcm {
    # The plaintext, or $null when the tag does not verify or the input is shorter than a tag.
    param([byte[]]$Key, [byte[]]$Nonce, [AllowEmptyCollection()][byte[]]$Aad, [byte[]]$Sealed)
    Assert-HordeRelayGcmLengths -Key $Key -Nonce $Nonce
    if ($null -eq $Sealed -or $Sealed.Length -lt 16) { return $null }
    $ct = New-Object byte[] ($Sealed.Length - 16)
    $tag = New-Object byte[] 16
    [System.Array]::Copy($Sealed, 0, $ct, 0, $ct.Length)
    [System.Array]::Copy($Sealed, $ct.Length, $tag, 0, 16)
    $plain = New-Object byte[] $ct.Length
    $gcm = New-Object System.Security.Cryptography.AesGcm -ArgumentList $Key, 16
    try {
        # A tag that does not verify throws AuthenticationTagMismatchException, a CryptographicException;
        # .NET clears the output buffer itself before throwing.
        try { $gcm.Decrypt($Nonce, $ct, $tag, $plain, $Aad) } catch [System.Security.Cryptography.CryptographicException] { return $null }
    } finally { $gcm.Dispose() }
    return ,$plain
}
