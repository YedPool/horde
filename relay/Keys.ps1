# relay/Keys.ps1 - the machine's own relay keys: P-256, made once, never exportable, never overwritten.
#
# WHY NON-EXPORTABLE. A machine signs every envelope it sends and opens every envelope sent to it; a
# copy of either private key is that machine, until the founder revokes it (relay design, threat
# model: "a stolen machine key"). So the private halves are made inside a Windows key storage provider
# with an export policy of none, and Horde only ever holds a handle: it signs, and it agrees a key
# through DeriveKeyFromHmac (relay/P256.ps1), and the scalar never enters the process.
#
# TWO KEYS, BECAUSE CNG KEEPS THEM APART: an ECDSA key signs ("sign") and an ECDH key opens HPKE
# ("agree"); a CNG key is one or the other.
#
# WHERE A KEY LIVES, measured 2026-10-09 on the development machine (Windows 11, TPM 2.0, both
# runtimes alike):
#   - Microsoft Platform Crypto Provider (the TPM): an ECDSA P-256 key is made in about 90 ms and
#     signs in about 35 ms. An ECDH P-256 key is made too, but DeriveKeyFromHmac on it fails - "The
#     supplied handle is invalid" under .NET, "The keys from both parties must be the same size"
#     under .NET Framework - so it cannot open HPKE as this module does it.
#   - Microsoft Software Key Storage Provider: both kinds, made in under 35 ms, used in under 50 ms;
#     the key file is protected by DPAPI under the scope's account.
#   So -Provider auto ("where possible") tries the TPM first, PROVES the key works by using it once,
#   and only then keeps it; otherwise the TPM key is deleted and a software key is made. The answer
#   says which provider holds the key and what was tried. A key that merely exists is never assumed
#   to work.
#
# SCOPE. "user" (the default) keeps the key in the profile of the account Horde runs as. "machine"
# (CNG's MachineKey) keeps it in the machine store, readable by administrators and services as well;
# creating one needs write access to that store, which an elevated session has (measured: it
# worked elevated, 2026-10-09). The scope asked for is the scope used: never a silent fallback.
#
# NOT EVERY SYSTEM HAS SUCH A STORE. CNG is Windows'. Under PowerShell 7 on Linux or macOS, .NET has no
# store for non-exportable EC keys (the CngKey type is present but throws PlatformNotSupported), and
# this file does not fake one with a key file: Get-HordeRelayKeyStore answers absent there, with the
# reason, and so does every call below. A Linux or macOS store (a TPM through tpm2-pkcs11, the macOS
# keychain or Secure Enclave) would be another backend of this file, with the same answers.
#
# NAMES are horde-relay-<suffix>: a call can never touch a key another program made.
#
# Answers are core/tristate: known, absent (no such key, or no store here) or unknown (with why).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")
. (Join-Path $PSScriptRoot "Bytes.ps1")
. (Join-Path $PSScriptRoot "P256.ps1")

function Get-HordeRelayKeyProviders {
    # Provider name by our word, in the order -Provider auto tries them.
    return [ordered]@{ platform = "Microsoft Platform Crypto Provider"; software = "Microsoft Software Key Storage Provider" }
}

function Assert-HordeRelayKeyArgs {
    # The name, use and scope a caller gave are Horde's own values, not the far end's: a bad one throws.
    param([string]$Name, [string]$Use, [string]$Scope)
    if ($Name -cnotmatch '\Ahorde-relay-[a-z0-9][a-z0-9-]{0,47}\z') { throw ("a relay key is named horde-relay-<lower-case letters, digits and dashes>, not '" + $Name + "'") }
    if (@("sign", "agree") -cnotcontains $Use) { throw ("a relay key is for sign or agree, not '" + $Use + "'") }
    if (@("user", "machine") -cnotcontains $Scope) { throw ("a relay key's scope is user or machine, not '" + $Scope + "'") }
}

function Get-HordeRelayKeyStore {
    # Is there a non-exportable key store in this process? known "cng", or absent with the reason.
    $probeName = "horde-relay-probe-" + [guid]::NewGuid().ToString("N")
    try { [void][System.Security.Cryptography.CngKey]::Exists($probeName) }
    catch { return (New-HordeAbsent -Note ("no non-exportable key store in this runtime and system (" + $_.Exception.Message + "); keys are not faked with files")) }
    return (New-HordeKnown -Value "cng")
}

function Get-HordeRelayCngAlgorithm {
    param([string]$Use)
    if ($Use -ceq "sign") { return [System.Security.Cryptography.CngAlgorithm]::ECDsaP256 }
    return [System.Security.Cryptography.CngAlgorithm]::ECDiffieHellmanP256
}

function Test-HordeRelayCngKeyKind {
    # Is this opened CNG key a P-256 key for Use? Asked by algorithm GROUP and curve, not by algorithm
    # name: measured 2026-10-09, the software provider names its keys ECDSA_P256 and ECDH_P256 but the
    # TPM provider names the same keys ECDSA and ECDH (the curve is a property), so a name comparison
    # refused every TPM key.
    param($CngKey, [string]$Use)
    $group = $(if ($Use -ceq "sign") { [System.Security.Cryptography.CngAlgorithmGroup]::ECDsa } else { [System.Security.Cryptography.CngAlgorithmGroup]::ECDiffieHellman })
    if ($CngKey.AlgorithmGroup -ne $group) { return $false }
    $obj = ConvertTo-HordeRelayKeyObject -CngKey $CngKey -Use $Use
    try { $curveOid = $obj.ExportParameters($false).Curve.Oid } catch { return $false }
    # 1.2.840.10045.3.1.7 is secp256r1, which NIST calls P-256. Measured 2026-10-09: .NET names the
    # curve with that value; .NET Framework leaves the value empty and gives only the friendly name
    # nistP256, for keys of both providers.
    if ("" + $curveOid.Value -cne "") { return [bool]($curveOid.Value -ceq "1.2.840.10045.3.1.7") }
    return [bool]($curveOid.FriendlyName -ceq "nistP256")
}

function ConvertTo-HordeRelayKeyObject {
    # The .NET key object over a CNG key handle, for signing or agreement.
    param($CngKey, [string]$Use)
    if ($Use -ceq "sign") { return (New-Object System.Security.Cryptography.ECDsaCng -ArgumentList $CngKey) }
    return (New-Object System.Security.Cryptography.ECDiffieHellmanCng -ArgumentList $CngKey)
}

function Test-HordeRelayKeyWorks {
    # Use the key once: sign and verify, or agree with a fresh peer from both sides. "" or why not.
    param($KeyObject, [string]$Use)
    try {
        $pub = ConvertTo-HordeRelayP256Public -Key $KeyObject
        if ($Use -ceq "sign") {
            $probe = Get-HordeRelayRandomBytes -Count 32
            $sig = New-HordeRelayEs256Signature -Key $KeyObject -Bytes $probe
            if (-not (Test-HordeRelayEs256Signature -Public $pub -Bytes $probe -Signature $sig)) { return "its signature did not verify" }
            return ""
        }
        $peer = New-HordeRelayP256Key -Use "ecdh"
        try {
            $salt = Get-HordeRelayRandomBytes -Count 32
            $mine = Invoke-HordeRelayEcdhExtract -Private $KeyObject -PeerPublic (ConvertTo-HordeRelayP256Public -Key $peer) -Salt $salt -Prefix (New-Object byte[] 0)
            $theirs = Invoke-HordeRelayEcdhExtract -Private $peer -PeerPublic $pub -Salt $salt -Prefix (New-Object byte[] 0)
        } finally { $peer.Dispose() }
        if (-not (Test-HordeRelayBytesEqual -Left $mine -Right $theirs)) { return "its key agreement did not match the peer's" }
        return ""
    } catch { return $_.Exception.Message }
}

function Find-HordeRelayCngKey {
    # The provider word whose store holds Name in Scope, or "".
    param([string]$Name, [string]$Scope)
    $opt = $(if ($Scope -ceq "machine") { [System.Security.Cryptography.CngKeyOpenOptions]::MachineKey } else { [System.Security.Cryptography.CngKeyOpenOptions]::None })
    $providers = Get-HordeRelayKeyProviders
    foreach ($word in @($providers.Keys)) {
        $prov = New-Object System.Security.Cryptography.CngProvider -ArgumentList $providers[$word]
        $there = $false
        try { $there = [System.Security.Cryptography.CngKey]::Exists($Name, $prov, $opt) } catch { $there = $false }
        if ($there) { return $word }
    }
    return ""
}

function New-HordeRelayKey {
    # Make the named key, once. Known { name; use; scope; provider; keyId; publicKey; tried } when made;
    # unknown when it exists already (never overwritten) or could not be made; absent with no store.
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][string]$Use,
        [string]$Scope = "user", [string]$Provider = "auto")
    Assert-HordeRelayKeyArgs -Name $Name -Use $Use -Scope $Scope
    if (@("auto", "platform", "software") -cnotcontains $Provider) { throw ("a relay key's provider is auto, platform or software, not '" + $Provider + "'") }
    $store = Get-HordeRelayKeyStore
    if ($store.state -cne "known") { return $store }
    $existing = Find-HordeRelayCngKey -Name $Name -Scope $Scope
    if ($existing -cne "") { return (New-HordeUnknown -Reason ("the key " + $Name + " already exists (" + $Scope + " scope, " + $existing + " provider); relay keys are made once and never overwritten")) }
    $providers = Get-HordeRelayKeyProviders
    $order = $(if ($Provider -ceq "auto") { @($providers.Keys) } else { @($Provider) })
    $tried = New-Object System.Collections.ArrayList
    foreach ($word in $order) {
        $params = New-Object System.Security.Cryptography.CngKeyCreationParameters
        $params.Provider = New-Object System.Security.Cryptography.CngProvider -ArgumentList $providers[$word]
        $params.ExportPolicy = [System.Security.Cryptography.CngExportPolicies]::None
        if ($Scope -ceq "machine") { $params.KeyCreationOptions = [System.Security.Cryptography.CngKeyCreationOptions]::MachineKey }
        $cng = $null
        try { $cng = [System.Security.Cryptography.CngKey]::Create((Get-HordeRelayCngAlgorithm -Use $Use), $Name, $params) }
        catch { [void]$tried.Add($word + ": not made (" + $_.Exception.Message.Trim() + ")"); continue }
        $obj = ConvertTo-HordeRelayKeyObject -CngKey $cng -Use $Use
        $why = Test-HordeRelayKeyWorks -KeyObject $obj -Use $Use
        if ($why -cne "") {
            [void]$tried.Add($word + ": made, but it does not work for " + $Use + " (" + ($why -replace '\s+', ' ').Trim() + "), so it was deleted")
            try { $cng.Delete() } catch { [void]$tried.Add($word + ": and deleting it failed (" + $_.Exception.Message.Trim() + ")") }
            continue
        }
        $pub = ConvertTo-HordeRelayP256Public -Key $obj
        [void]$tried.Add($word + ": made and used once")
        $obj.Dispose()
        return (New-HordeKnown -Value ([pscustomobject]@{ name = $Name; use = $Use; scope = $Scope; provider = $word; keyId = (Get-HordeRelayKeyId -Public $pub); publicKey = $pub; tried = @($tried) }))
    }
    return (New-HordeUnknown -Reason ("the key " + $Name + " could not be made: " + (@($tried) -join "; ")))
}

function Get-HordeRelayKey {
    # Open the named key. Known { name; use; scope; provider; keyId; publicKey; key } where key is an
    # ECDsaCng (sign) or ECDiffieHellmanCng (agree) over the handle; absent when there is no such key or
    # no store; unknown when it is not a non-exportable P-256 key of that use, or cannot be opened.
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][string]$Use, [string]$Scope = "user")
    Assert-HordeRelayKeyArgs -Name $Name -Use $Use -Scope $Scope
    $store = Get-HordeRelayKeyStore
    if ($store.state -cne "known") { return $store }
    $word = Find-HordeRelayCngKey -Name $Name -Scope $Scope
    if ($word -ceq "") { return (New-HordeAbsent -Note ("no relay key " + $Name + " in the " + $Scope + " scope")) }
    $opt = $(if ($Scope -ceq "machine") { [System.Security.Cryptography.CngKeyOpenOptions]::MachineKey } else { [System.Security.Cryptography.CngKeyOpenOptions]::None })
    $prov = New-Object System.Security.Cryptography.CngProvider -ArgumentList (Get-HordeRelayKeyProviders)[$word]
    try { $cng = [System.Security.Cryptography.CngKey]::Open($Name, $prov, $opt) }
    catch { return (New-HordeUnknown -Reason ("the key " + $Name + " exists but could not be opened") -ErrorRecord $_) }
    if (-not (Test-HordeRelayCngKeyKind -CngKey $cng -Use $Use)) {
        $cng.Dispose()
        return (New-HordeUnknown -Reason ("the key " + $Name + " is not a P-256 key for " + $Use))
    }
    # A key with any export right is not a relay key, whoever made it: refuse rather than use it.
    if ($cng.ExportPolicy -ne [System.Security.Cryptography.CngExportPolicies]::None) {
        $cng.Dispose()
        return (New-HordeUnknown -Reason ("the key " + $Name + " can be exported (" + $cng.ExportPolicy + "), so it is not used"))
    }
    try {
        $obj = ConvertTo-HordeRelayKeyObject -CngKey $cng -Use $Use
        $pub = ConvertTo-HordeRelayP256Public -Key $obj
    } catch { $cng.Dispose(); return (New-HordeUnknown -Reason ("the key " + $Name + " could not be used for " + $Use) -ErrorRecord $_) }
    return (New-HordeKnown -Value ([pscustomobject]@{ name = $Name; use = $Use; scope = $Scope; provider = $word; keyId = (Get-HordeRelayKeyId -Public $pub); publicKey = $pub; key = $obj }))
}

function Remove-HordeRelayKey {
    # Delete the named key: revocation's last step on the machine, and a suite's cleanup. Known
    # "removed", absent when there was none, unknown when it could not be deleted.
    param([Parameter(Mandatory = $true)][string]$Name, [string]$Scope = "user")
    Assert-HordeRelayKeyArgs -Name $Name -Use "sign" -Scope $Scope
    $store = Get-HordeRelayKeyStore
    if ($store.state -cne "known") { return $store }
    $word = Find-HordeRelayCngKey -Name $Name -Scope $Scope
    if ($word -ceq "") { return (New-HordeAbsent -Note ("no relay key " + $Name + " in the " + $Scope + " scope")) }
    $opt = $(if ($Scope -ceq "machine") { [System.Security.Cryptography.CngKeyOpenOptions]::MachineKey } else { [System.Security.Cryptography.CngKeyOpenOptions]::None })
    $prov = New-Object System.Security.Cryptography.CngProvider -ArgumentList (Get-HordeRelayKeyProviders)[$word]
    try {
        $cng = [System.Security.Cryptography.CngKey]::Open($Name, $prov, $opt)
        $cng.Delete()
    } catch { return (New-HordeUnknown -Reason ("the key " + $Name + " could not be deleted") -ErrorRecord $_) }
    return (New-HordeKnown -Value "removed")
}
