# relay/WebAuthn.ps1 - verify a WebAuthn ES256 assertion: the founder's passkey signature on an answer.
#
# WHY THE MACHINE VERIFIES IT, NOT THE RELAY. The relay is untrusted (relay design, threat model): it can
# drop, delay or reorder, and must not be able to forge an answer. So every answer from a phone carries a
# passkey assertion whose challenge is the hash of the envelope it signs (relay/Envelope.ps1), and the
# machine checks it against the credential it pinned at pairing.
#
# WHAT IS CHECKED, in the order of WebAuthn Level 3, section 7.2 ("Verifying an Authentication
# Assertion"), steps 10 to 21, each refusal naming its reason:
#   - clientDataJSON: at most 1024 bytes, strict UTF-8, a JSON object with no member repeated
#     (ConvertFrom-Json keeps the last of two repeated members and says nothing, measured 2026-10-09 on
#     both runtimes, so a text could show one challenge and be read as another); type exactly
#     "webauthn.get"; challenge exactly the base64url of the expected bytes; origin exactly one of the
#     expected; crossOrigin absent or false, and no topOrigin (the PWA is never framed).
#   - authenticatorData: at least 37 bytes, at most 512; rpIdHash = SHA-256(rpId); user present (UP);
#     user verified (UV) when required; no attested credential data (AT is for registration); backed up
#     (BS) only if backup eligible (BE); bytes after the counter exactly when extension data (ED) is
#     flagged. The extensions themselves are not parsed: nothing here uses one, and they are signed.
#   - the signature: minimal DER (relay/P256.ps1), ES256 over authenticatorData || SHA-256(clientDataJSON)
#     under the pinned public key.
#
# WHAT IS REPORTED, NOT JUDGED: the signature counter. Synced passkeys report 0 for ever (design Q11), so
# a counter cannot be the replay defence; the envelope's sequence and nonce are (the journal's hook,
# relay/Envelope.ps1). Credential ids and COSE key import belong to pairing: relay/Registration.ps1.
#
# Never throws for a bad assertion: the answer is { ok; reason; signCount; userVerified;
# backupEligible; backupState }, ok $false with the first reason found.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\JsonText.ps1")
. (Join-Path $PSScriptRoot "Bytes.ps1")
. (Join-Path $PSScriptRoot "P256.ps1")

function Get-HordeRelayWebAuthnLimits {
    # clientDataJSON measured 2026-10-09: 134 bytes from Node's WebCrypto fixture, about 150 to 250 from
    # browsers (the spec's members plus an origin). 1024 leaves room for a longer origin and the members
    # a browser may add, and stops a megabyte from being parsed. authenticatorData is 37 bytes without
    # extensions; 512 holds any extension a get() returns.
    return [pscustomobject]@{ clientDataJsonBytes = 1024; authenticatorDataBytes = 512 }
}

function New-HordeRelayWebAuthnAnswer {
    param([string]$Reason, $SignCount = $null, $Flags = $null)
    $f = 0
    if ($null -ne $Flags) { $f = [int]$Flags }
    return [pscustomobject]@{
        ok = ($Reason -ceq "")
        reason = $Reason
        signCount = $SignCount
        userVerified = [bool](($f -band 0x04) -ne 0)
        backupEligible = [bool](($f -band 0x08) -ne 0)
        backupState = [bool](($f -band 0x10) -ne 0)
    }
}

function Get-HordeRelayClientDataFindings {
    # The first thing wrong with clientDataJSON, or "" when it is right. Type is webauthn.get for an
    # assertion and webauthn.create for a registration (relay/Registration.ps1); the rest is the same.
    param([byte[]]$ClientDataJson, [byte[]]$Challenge, [string[]]$Origins, [string]$Type = "webauthn.get")
    $limits = Get-HordeRelayWebAuthnLimits
    if ($ClientDataJson.Length -gt $limits.clientDataJsonBytes) { return ("clientDataJSON is larger than " + $limits.clientDataJsonBytes + " bytes") }
    $strictUtf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false, $true
    try { $text = $strictUtf8.GetString($ClientDataJson) } catch { return "clientDataJSON is not UTF-8" }
    $trimmed = $text.Trim()
    if (-not $trimmed.StartsWith("{")) {
        if ($trimmed.StartsWith("[")) { return "clientDataJSON is not a JSON object" }
        return "clientDataJSON is not JSON"
    }
    $dups = @(Find-HordeJsonDuplicateKey -Text $text)
    if ($dups.Count -gt 0) { return ("clientDataJSON has a member more than once: " + $dups[0]) }
    try { $cd = ConvertFrom-Json -InputObject $text } catch { return "clientDataJSON is not JSON" }
    if ($cd -isnot [System.Management.Automation.PSCustomObject]) { return "clientDataJSON is not a JSON object" }
    $names = @($cd.PSObject.Properties | ForEach-Object { $_.Name })
    if ($names -cnotcontains "type" -or $cd.type -isnot [string] -or $cd.type -cne $Type) { return ("clientDataJSON type is not " + $Type) }
    if ($names -cnotcontains "challenge" -or $cd.challenge -isnot [string] -or $cd.challenge -cne (ConvertTo-HordeRelayBase64Url -Bytes $Challenge)) { return "the challenge in clientDataJSON is not the one expected" }
    if ($names -cnotcontains "origin" -or $cd.origin -isnot [string] -or $Origins -cnotcontains $cd.origin) { return "the origin in clientDataJSON is not one expected" }
    if ($names -ccontains "crossOrigin" -and -not ($cd.crossOrigin -is [bool] -and $cd.crossOrigin -eq $false)) { return "clientDataJSON says crossOrigin: the page was framed by another site" }
    if ($names -ccontains "topOrigin") { return "clientDataJSON names a topOrigin: the page was framed by another site" }
    return ""
}

function Test-HordeRelayWebAuthnAssertion {
    # Is this WebAuthn assertion valid for this credential, challenge, relying party and origins?
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Public,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$AuthenticatorData,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$ClientDataJson,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Signature,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Challenge,
        [Parameter(Mandatory = $true)][string]$RpId,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Origins,
        [Parameter(Mandatory = $true)][bool]$RequireUserVerification)
    if ($Challenge.Length -lt 16) { return (New-HordeRelayWebAuthnAnswer -Reason "the expected challenge is shorter than 16 bytes") }
    $cdFinding = Get-HordeRelayClientDataFindings -ClientDataJson $ClientDataJson -Challenge $Challenge -Origins $Origins
    if ($cdFinding -cne "") { return (New-HordeRelayWebAuthnAnswer -Reason $cdFinding) }

    $limits = Get-HordeRelayWebAuthnLimits
    $ad = $AuthenticatorData
    if ($ad.Length -lt 37) { return (New-HordeRelayWebAuthnAnswer -Reason "authenticatorData is shorter than 37 bytes") }
    if ($ad.Length -gt $limits.authenticatorDataBytes) { return (New-HordeRelayWebAuthnAnswer -Reason ("authenticatorData is larger than " + $limits.authenticatorDataBytes + " bytes")) }
    $rpIdHash = New-Object byte[] 32
    [System.Array]::Copy($ad, 0, $rpIdHash, 0, 32)
    if (-not (Test-HordeRelayBytesEqual -Left $rpIdHash -Right (Get-HordeRelaySha256 -Bytes ([System.Text.Encoding]::UTF8.GetBytes($RpId))))) { return (New-HordeRelayWebAuthnAnswer -Reason "the rpIdHash in authenticatorData is not this relying party's") }
    $flags = [int]$ad[32]
    $count = ([long]$ad[33] -shl 24) + ([long]$ad[34] -shl 16) + ([long]$ad[35] -shl 8) + [long]$ad[36]
    if (($flags -band 0x01) -eq 0) { return (New-HordeRelayWebAuthnAnswer -Reason "the authenticator did not see user presence" -Flags $flags) }
    if ($RequireUserVerification -and ($flags -band 0x04) -eq 0) { return (New-HordeRelayWebAuthnAnswer -Reason "user verification was required and the authenticator did not do it" -Flags $flags) }
    if (($flags -band 0x40) -ne 0) { return (New-HordeRelayWebAuthnAnswer -Reason "an assertion carries no attested credential data (AT is for registration)" -Flags $flags) }
    if (($flags -band 0x10) -ne 0 -and ($flags -band 0x08) -eq 0) { return (New-HordeRelayWebAuthnAnswer -Reason "backed up (BS) without being backup eligible (BE)" -Flags $flags) }
    $hasExtensionBytes = ($ad.Length -gt 37)
    if ((($flags -band 0x80) -ne 0) -ne $hasExtensionBytes) {
        if ($hasExtensionBytes) { return (New-HordeRelayWebAuthnAnswer -Reason "authenticatorData has bytes after the counter but the extension data flag (ED) is not set" -Flags $flags) }
        return (New-HordeRelayWebAuthnAnswer -Reason "the extension data flag (ED) is set but no extension bytes follow the counter" -Flags $flags)
    }

    try { $p1363 = ConvertFrom-HordeRelayDerSignature -Der $Signature }
    catch { return (New-HordeRelayWebAuthnAnswer -Reason ("the signature is not minimal DER: " + $_.Exception.Message) -Flags $flags) }
    $signed = Join-HordeRelayBytes -Parts @($ad, (Get-HordeRelaySha256 -Bytes $ClientDataJson))
    # -AllowHighS: an authenticator emits either half of s (relay/P256.ps1, LOW-S), so a passkey
    # signature can have two spellings; it is not part of an envelope's identity (relay/Envelope.ps1).
    if (-not (Test-HordeRelayEs256Signature -Public $Public -Bytes $signed -Signature $p1363 -AllowHighS)) { return (New-HordeRelayWebAuthnAnswer -Reason "the ES256 signature does not verify under the pinned credential" -Flags $flags) }
    return (New-HordeRelayWebAuthnAnswer -Reason "" -SignCount $count -Flags $flags)
}
