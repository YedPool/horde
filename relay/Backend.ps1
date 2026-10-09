# relay/Backend.ps1 - THE SEAM: which AES-256-GCM implementation this runtime uses.
#
# WHY A SEAM, AND WHY ONLY HERE. Horde is to run on Windows, Linux and macOS (direction of 2026-10-09),
# and the one primitive the relay needs that the runtimes do not share is AES-GCM: .NET Framework 4.8
# (Windows PowerShell 5.1) has no AesGcm class, .NET (PowerShell 7, any system) has. Everything else -
# SHA-256, HMAC, P-256 ECDH through DeriveKeyFromHmac, ECDSA - is the same API in both, so HKDF, HPKE,
# WebAuthn and the envelope are written once, above this file.
#
# SELECTED BY WHAT THE RUNTIME CAN DO, NOT BY THE NAME OF THE SYSTEM. A backend is available only after
# it has answered a known-answer test (McGrew and Viega's GCM test case 16, AES-256 with additional
# data, from the GCM specification): a backend that loads but computes wrongly is never used, and the
# reason it was refused is kept. The preferred order is dotnet, then cng: the runtime's own class needs
# no compile.
#
#   dotnet   System.Security.Cryptography.AesGcm (relay/BackendDotnet.ps1)
#   cng      bcrypt.dll through relay/Gcm.cs (relay/BackendCng.ps1); Windows only, any runtime
#
# The selection is remembered for the process. Select-HordeRelayAeadBackend changes it, to an available
# backend only; the suites use it to seal with one and open with the other.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path $PSScriptRoot "Bytes.ps1")
. (Join-Path $PSScriptRoot "BackendCng.ps1")
. (Join-Path $PSScriptRoot "BackendDotnet.ps1")

$script:HordeRelayAeadSelected = ""
$script:HordeRelayAeadProbe = $null

function Get-HordeRelayAeadKat {
    # GCM specification test case 16 (AES-256, 60-byte plaintext, 20-byte additional data).
    return [pscustomobject]@{
        key = "feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308"
        nonce = "cafebabefacedbaddecaf888"
        aad = "feedfacedeadbeeffeedfacedeadbeefabaddad2"
        plain = "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39"
        sealed = "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f66276fc6ece0f4e1768cddf8853bb2d551b"
    }
}

function Test-HordeRelayAeadBackend {
    # Does the named backend load and answer the known-answer test, both ways, and refuse a bad tag?
    # Returns { name; available; reason }.
    param([Parameter(Mandatory = $true)][string]$Name)
    if (@("dotnet", "cng") -cnotcontains $Name) { return [pscustomobject]@{ name = $Name; available = $false; reason = "no such backend" } }
    if ($Name -ceq "dotnet" -and $null -eq ("System.Security.Cryptography.AesGcm" -as [type])) {
        return [pscustomobject]@{ name = $Name; available = $false; reason = "this runtime has no System.Security.Cryptography.AesGcm (it arrived in .NET Core 3.0)" }
    }
    $kat = Get-HordeRelayAeadKat
    $k = ConvertFrom-HordeRelayHex -Text $kat.key
    $n = ConvertFrom-HordeRelayHex -Text $kat.nonce
    $a = ConvertFrom-HordeRelayHex -Text $kat.aad
    $p = ConvertFrom-HordeRelayHex -Text $kat.plain
    try {
        $sealed = Protect-HordeRelayAesGcm -Key $k -Nonce $n -Aad $a -Plaintext $p -Backend $Name
        if ((ConvertTo-HordeRelayHex -Bytes $sealed) -cne $kat.sealed) { return [pscustomobject]@{ name = $Name; available = $false; reason = "it sealed the known-answer test to the wrong bytes" } }
        $opened = Unprotect-HordeRelayAesGcm -Key $k -Nonce $n -Aad $a -Sealed $sealed -Backend $Name
        if ($null -eq $opened -or (ConvertTo-HordeRelayHex -Bytes $opened) -cne $kat.plain) { return [pscustomobject]@{ name = $Name; available = $false; reason = "it did not open the known-answer test" } }
        $sealed[$sealed.Length - 1] = $sealed[$sealed.Length - 1] -bxor 1
        if ($null -ne (Unprotect-HordeRelayAesGcm -Key $k -Nonce $n -Aad $a -Sealed $sealed -Backend $Name)) { return [pscustomobject]@{ name = $Name; available = $false; reason = "it opened the known-answer test with a flipped tag bit" } }
    } catch {
        return [pscustomobject]@{ name = $Name; available = $false; reason = ("it failed to load or run: " + $_.Exception.Message) }
    }
    return [pscustomobject]@{ name = $Name; available = $true; reason = "" }
}

function Get-HordeRelayAeadBackends {
    # Every backend, in preference order, with whether this runtime can use it and why not.
    if ($null -eq $script:HordeRelayAeadProbe) {
        $script:HordeRelayAeadProbe = @(@("dotnet", "cng") | ForEach-Object { Test-HordeRelayAeadBackend -Name $_ })
    }
    return @($script:HordeRelayAeadProbe)
}

function Get-HordeRelayAeadBackend {
    # The backend in use: the selected one, else the first available. Throws when none is.
    if ($script:HordeRelayAeadSelected -cne "") { return $script:HordeRelayAeadSelected }
    $first = @(Get-HordeRelayAeadBackends | Where-Object { $_.available }) | Select-Object -First 1
    if ($null -eq $first) {
        throw ("no AES-256-GCM backend is available in this runtime: " + (@(Get-HordeRelayAeadBackends | ForEach-Object { $_.name + ": " + $_.reason }) -join "; "))
    }
    $script:HordeRelayAeadSelected = $first.name
    return $script:HordeRelayAeadSelected
}

function Select-HordeRelayAeadBackend {
    # Use the named backend from now on in this process; refused unless it passed its known-answer test.
    param([Parameter(Mandatory = $true)][string]$Name)
    $b = @(Get-HordeRelayAeadBackends | Where-Object { $_.name -ceq $Name }) | Select-Object -First 1
    if ($null -eq $b -or -not $b.available) { throw ("the AES-GCM backend '" + $Name + "' is not available here" + $(if ($null -ne $b) { ": " + $b.reason } else { "" })) }
    $script:HordeRelayAeadSelected = $Name
}

function Protect-HordeRelayAesGcm {
    # AES-256-GCM seal: ciphertext || 16-byte tag. Backend is for the known-answer test and the suites;
    # every other caller leaves it empty and gets the backend in use.
    param([Parameter(Mandatory = $true)][byte[]]$Key, [Parameter(Mandatory = $true)][byte[]]$Nonce,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Aad, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Plaintext, [string]$Backend = "")
    $use = $Backend
    if ($use -ceq "") { $use = Get-HordeRelayAeadBackend }
    if ($use -ceq "dotnet") { return ,(Protect-HordeRelayDotnetGcm -Key $Key -Nonce $Nonce -Aad $Aad -Plaintext $Plaintext) }
    if ($use -ceq "cng") { return ,(Protect-HordeRelayCngGcm -Key $Key -Nonce $Nonce -Aad $Aad -Plaintext $Plaintext) }
    throw ("no such AES-GCM backend: '" + $use + "'")
}

function Unprotect-HordeRelayAesGcm {
    # AES-256-GCM open: the plaintext, or $null when the tag does not verify.
    param([Parameter(Mandatory = $true)][byte[]]$Key, [Parameter(Mandatory = $true)][byte[]]$Nonce,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Aad, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Sealed, [string]$Backend = "")
    $use = $Backend
    if ($use -ceq "") { $use = Get-HordeRelayAeadBackend }
    $plain = $null
    if ($use -ceq "dotnet") { $plain = Unprotect-HordeRelayDotnetGcm -Key $Key -Nonce $Nonce -Aad $Aad -Sealed $Sealed }
    elseif ($use -ceq "cng") { $plain = Unprotect-HordeRelayCngGcm -Key $Key -Nonce $Nonce -Aad $Aad -Sealed $Sealed }
    else { throw ("no such AES-GCM backend: '" + $use + "'") }
    if ($null -eq $plain) { return $null }
    return ,([byte[]]$plain)
}
