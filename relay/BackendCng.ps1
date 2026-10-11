# relay/BackendCng.ps1 - the AES-256-GCM backend for runtimes without an AesGcm class: Windows CNG
# (bcrypt.dll) through relay/Gcm.cs.
#
# THE RUNTIME IT IS FOR is Windows PowerShell 5.1 on .NET Framework 4.8, which has no AES-GCM type
# (spike S1, 2026-10-09). PowerShell 7 on Windows can load it too, which is what lets
# test/test-relay-crypto.ps1 seal with one backend and open with the other in one process.
#
# THE TYPE IS COMPILED ONCE PER PROCESS, on first use, from the fixed neighbour file. That Add-Type
# line, in exactly that form, is the one compile tools/ExecScan.ps1 admits in relay/: a literal
# neighbour .cs file, never source built from data.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

function Initialize-HordeRelayCngGcm {
    # Load the bcrypt type, once. Throws off Windows (no bcrypt.dll) or when compiling fails; the
    # backend list (relay/Backend.ps1) turns that into "not available", with the reason.
    if ($null -eq ("HordeRelayGcmV1" -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot "Gcm.cs")
    }
}

function Protect-HordeRelayCngGcm {
    # ciphertext || 16-byte tag.
    param([byte[]]$Key, [byte[]]$Nonce, [AllowEmptyCollection()][byte[]]$Aad, [AllowEmptyCollection()][byte[]]$Plaintext)
    Initialize-HordeRelayCngGcm
    return ,([HordeRelayGcmV1]::Seal($Key, $Nonce, $Aad, $Plaintext))
}

function Unprotect-HordeRelayCngGcm {
    # The plaintext, or $null when the tag does not verify.
    param([byte[]]$Key, [byte[]]$Nonce, [AllowEmptyCollection()][byte[]]$Aad, [byte[]]$Sealed)
    Initialize-HordeRelayCngGcm
    $plain = [HordeRelayGcmV1]::Open($Key, $Nonce, $Aad, $Sealed)
    if ($null -eq $plain) { return $null }
    return ,$plain
}
