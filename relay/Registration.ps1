# relay/Registration.ps1 - verify a WebAuthn registration with attestation "none": the founder's phone
# making the passkey that will sign every answer this machine takes from it.
#
# WHAT A REGISTRATION PROVES HERE, AND WHAT IT DOES NOT. With attestation "none" nothing in a
# registration is signed: it is a public key, a credential id and some flags, wrapped in CBOR. So it
# proves nothing about the AUTHENTICATOR (no maker, no model, no hardware claim - Horde asks for none,
# and Android's passkey providers give none). What binds it to a pairing is the CHALLENGE: the phone's
# clientDataJSON must carry, as its challenge, the hash of the one-time pairing offer this machine
# showed (relay/Pairing.ps1). Whoever submits a registration over that challenge held the offer; the
# key it carries is the key every later assertion must verify under (relay/WebAuthn.ps1). Pairing's
# header says what a stolen offer can and cannot do.
#
# WHAT IS CHECKED, in the order of WebAuthn Level 3, section 7.1 ("Registering a New Credential"),
# steps 5 to 26, each refusal naming its reason:
#   - clientDataJSON as relay/WebAuthn.ps1 checks it (size, strict UTF-8, one JSON object with no member
#     repeated, origin exactly one of the expected, not framed), with type exactly "webauthn.create"
#     and challenge exactly the base64url of the expected bytes;
#   - attestationObject: at most 4096 bytes, one CBOR map (relay/Cbor.ps1: shortest form, no
#     indefinite lengths, no tags, no key twice) with exactly fmt, attStmt and authData, and nothing
#     after it;
#   - fmt is "none" and attStmt is the empty map: another format is refused BY NAME, not verified -
#     Horde asks for none, so a statement is a client that did not do what it was asked;
#   - authData: rpIdHash = SHA-256(rpId); user present (UP); user verified (UV) when required; backed
#     up (BS) only if backup eligible (BE); attested credential data present (AT);
#   - the attested credential data: aaguid (16 bytes, reported only), a credential id of 1 to 1023
#     bytes (L3 step 22) equal to rawId, and a COSE_Key that relay/Cose.ps1 imports as ES256 on P-256,
#     point validated;
#   - extensions: present exactly when the ED flag is set, one CBOR map ending exactly at the end of
#     authData; "hmac-secret": true there is reported (the authenticator's side of PRF), nothing else
#     in it is used.
# NOT CHECKED HERE, ON PURPOSE: whether the credential id is already enrolled or revoked - that is the
# trust store's (relay/Trust.ps1), which refuses both; and the signature counter, which is reported,
# never judged (synced passkeys report 0, design Q11).
#
# Never throws for a bad registration: the answer is { ok; reason; credentialId; public; alg;
# signCount; userVerified; backupEligible; backupState; aaguid; hmacSecret }, ok $false with the first
# reason found.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path $PSScriptRoot "Bytes.ps1")
. (Join-Path $PSScriptRoot "Cbor.ps1")
. (Join-Path $PSScriptRoot "Cose.ps1")
. (Join-Path $PSScriptRoot "WebAuthn.ps1")

function Get-HordeRelayRegistrationLimits {
    # attestationObject: with attestation none it is 3 small members around authData, and authData is
    # 37 + 16 + 2 + the credential id (at most 1023) + a COSE EC2 key (77 bytes) + extensions - about
    # 1.2 KB at the largest id. 4096 holds that and a refused format's statement read far enough to name
    # it. credentialIdBytes is WebAuthn Level 3's own ceiling (7.1, step 22).
    return [pscustomobject]@{ attestationObjectBytes = 4096; credentialIdBytes = 1023 }
}

function New-HordeRelayRegistrationAnswer {
    param([string]$Reason, $Flags = $null, $Fields = $null)
    $f = 0
    if ($null -ne $Flags) { $f = [int]$Flags }
    $a = [pscustomobject]@{
        ok = ($Reason -ceq ""); reason = $Reason; credentialId = $null; public = $null; alg = $null; signCount = $null
        userVerified = [bool](($f -band 0x04) -ne 0); backupEligible = [bool](($f -band 0x08) -ne 0); backupState = [bool](($f -band 0x10) -ne 0)
        aaguid = ""; hmacSecret = $false
    }
    if ($null -ne $Fields) {
        $a.credentialId = $Fields.credentialId; $a.public = $Fields.public; $a.alg = $Fields.alg; $a.signCount = $Fields.signCount
        $a.aaguid = $Fields.aaguid; $a.hmacSecret = $Fields.hmacSecret
    }
    return $a
}

function Test-HordeRelayWebAuthnRegistration {
    # Is this registration valid for this challenge, relying party and origins?
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$ClientDataJson,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$AttestationObject,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$RawId,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Challenge,
        [Parameter(Mandatory = $true)][string]$RpId,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Origins,
        [Parameter(Mandatory = $true)][bool]$RequireUserVerification)
    if ($Challenge.Length -lt 16) { return (New-HordeRelayRegistrationAnswer -Reason "the expected challenge is shorter than 16 bytes") }
    $cdFinding = Get-HordeRelayClientDataFindings -ClientDataJson $ClientDataJson -Challenge $Challenge -Origins $Origins -Type "webauthn.create"
    if ($cdFinding -cne "") { return (New-HordeRelayRegistrationAnswer -Reason $cdFinding) }

    $limits = Get-HordeRelayRegistrationLimits
    if ($AttestationObject.Length -gt $limits.attestationObjectBytes) { return (New-HordeRelayRegistrationAnswer -Reason ("the attestationObject is larger than " + $limits.attestationObjectBytes + " bytes")) }
    $att = Read-HordeRelayCbor -Bytes $AttestationObject -Whole
    if (-not $att.ok) { return (New-HordeRelayRegistrationAnswer -Reason ("the attestationObject is not CBOR this reader accepts: " + $att.reason)) }
    if ($att.value.type -cne "map") { return (New-HordeRelayRegistrationAnswer -Reason "the attestationObject is not a CBOR map") }
    $names = @(Get-HordeRelayCborKeyNames -Map $att.value | Sort-Object)
    if (($names -join ",") -cne "attStmt,authData,fmt") { return (New-HordeRelayRegistrationAnswer -Reason ("the attestationObject's members are " + ($names -join ", ") + ", not exactly fmt, attStmt and authData")) }
    $fmt = Get-HordeRelayCborMember -Map $att.value -Key "fmt"
    $stmt = Get-HordeRelayCborMember -Map $att.value -Key "attStmt"
    $adNode = Get-HordeRelayCborMember -Map $att.value -Key "authData"
    if ($adNode.type -cne "bytes") { return (New-HordeRelayRegistrationAnswer -Reason "the attestationObject's authData is not a byte string") }
    if ($fmt.type -cne "text" -or $fmt.value -cne "none") { return (New-HordeRelayRegistrationAnswer -Reason ("the attestation format is '" + $fmt.value + "'; only none is accepted, because none is what pairing asks for")) }
    if ($stmt.type -cne "map" -or @($stmt.value).Count -ne 0) { return (New-HordeRelayRegistrationAnswer -Reason "attestation none carries an attStmt that is not the empty map") }

    $ad = [byte[]]$adNode.value
    if ($ad.Length -lt 55) { return (New-HordeRelayRegistrationAnswer -Reason "authData is too short to hold attested credential data") }
    $rpIdHash = New-Object byte[] 32
    [System.Array]::Copy($ad, 0, $rpIdHash, 0, 32)
    if (-not (Test-HordeRelayBytesEqual -Left $rpIdHash -Right (Get-HordeRelaySha256 -Bytes ([System.Text.Encoding]::UTF8.GetBytes($RpId))))) { return (New-HordeRelayRegistrationAnswer -Reason "the rpIdHash in authData is not this relying party's") }
    $flags = [int]$ad[32]
    $count = ([long]$ad[33] -shl 24) + ([long]$ad[34] -shl 16) + ([long]$ad[35] -shl 8) + [long]$ad[36]
    if (($flags -band 0x01) -eq 0) { return (New-HordeRelayRegistrationAnswer -Reason "the authenticator did not see user presence" -Flags $flags) }
    if ($RequireUserVerification -and ($flags -band 0x04) -eq 0) { return (New-HordeRelayRegistrationAnswer -Reason "user verification was required and the authenticator did not do it" -Flags $flags) }
    if (($flags -band 0x10) -ne 0 -and ($flags -band 0x08) -eq 0) { return (New-HordeRelayRegistrationAnswer -Reason "backed up (BS) without being backup eligible (BE)" -Flags $flags) }
    if (($flags -band 0x40) -eq 0) { return (New-HordeRelayRegistrationAnswer -Reason "authData has no attested credential data (AT is not set)" -Flags $flags) }

    $aaguid = New-Object byte[] 16
    [System.Array]::Copy($ad, 37, $aaguid, 0, 16)
    $idLen = ([int]$ad[53] -shl 8) + [int]$ad[54]
    if ($idLen -lt 1 -or $idLen -gt $limits.credentialIdBytes) { return (New-HordeRelayRegistrationAnswer -Reason ("the credential id is " + $idLen + " bytes; 1 to " + $limits.credentialIdBytes + " are allowed") -Flags $flags) }
    if (55 + $idLen -gt $ad.Length) { return (New-HordeRelayRegistrationAnswer -Reason "the credential id's length runs past the end of authData" -Flags $flags) }
    $credId = New-Object byte[] $idLen
    [System.Array]::Copy($ad, 55, $credId, 0, $idLen)
    if (-not (Test-HordeRelayBytesEqual -Left $credId -Right $RawId)) { return (New-HordeRelayRegistrationAnswer -Reason "rawId is not the credential id in authData" -Flags $flags) }

    $keyRead = Read-HordeRelayCbor -Bytes $ad -Offset (55 + $idLen)
    if (-not $keyRead.ok) { return (New-HordeRelayRegistrationAnswer -Reason ("the credential public key is not CBOR this reader accepts: " + $keyRead.reason) -Flags $flags) }
    $cose = ConvertFrom-HordeRelayCoseKey -Map $keyRead.value
    if (-not $cose.ok) { return (New-HordeRelayRegistrationAnswer -Reason $cose.reason -Flags $flags) }

    $hmacSecret = $false
    if (($flags -band 0x80) -ne 0) {
        if ($keyRead.next -ge $ad.Length) { return (New-HordeRelayRegistrationAnswer -Reason "the extension data flag (ED) is set but no extensions follow the credential public key" -Flags $flags) }
        $ext = Read-HordeRelayCbor -Bytes $ad -Offset $keyRead.next -Whole
        if (-not $ext.ok) { return (New-HordeRelayRegistrationAnswer -Reason ("the authenticator extensions are not CBOR this reader accepts: " + $ext.reason) -Flags $flags) }
        if ($ext.value.type -cne "map") { return (New-HordeRelayRegistrationAnswer -Reason "the authenticator extensions are not a CBOR map" -Flags $flags) }
        $hs = Get-HordeRelayCborMember -Map $ext.value -Key "hmac-secret"
        $hmacSecret = [bool]($null -ne $hs -and $hs.type -ceq "bool" -and $hs.value -eq $true)
    } elseif ($keyRead.next -ne $ad.Length) {
        return (New-HordeRelayRegistrationAnswer -Reason "authData has bytes after the credential public key but the extension data flag (ED) is not set" -Flags $flags)
    }

    $fields = [pscustomobject]@{ credentialId = $credId; public = $cose.public; alg = $cose.alg; signCount = $count; aaguid = (ConvertTo-HordeRelayHex -Bytes $aaguid); hmacSecret = $hmacSecret }
    return (New-HordeRelayRegistrationAnswer -Reason "" -Flags $flags -Fields $fields)
}
