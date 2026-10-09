# relay/Hpke.ps1 - HPKE (RFC 9180), base mode, one suite only:
#   KEM  0x0010  DHKEM(P-256, HKDF-SHA256)
#   KDF  0x0001  HKDF-SHA256
#   AEAD 0x0002  AES-256-GCM
#
# WHY HPKE, AND WHY ONE SUITE. The relay must never read what it carries (relay design, section 3), and
# a PWA must be able to do the same with WebCrypto alone. HPKE is the standard way to encrypt to a
# public key, and every primitive of this suite is in WebCrypto and in both .NET runtimes. One suite
# means no negotiation to downgrade: an envelope names no algorithm, version 1 IS this suite
# (relay/Envelope.ps1).
#
# CHECKED AGAINST THE OFFICIAL VECTORS. test/fixtures/relay/hpke-p256-sha256-aes256gcm.json is the one
# base-mode vector for this suite from the CFRG's test-vectors.json (its source and hash are in the
# fixture); test/test-relay-crypto.ps1 derives every intermediate value - enc, shared_secret,
# key_schedule_context, secret, key, base_nonce - and three of its encryptions, on every backend.
#
# WHAT IS NOT HERE, ON PURPOSE: the PSK, Auth and AuthPSK modes (sender authenticity comes from the
# envelope's signature instead), the secret export interface, and DeriveKeyPair (real keys come from
# the key store; the vectors give their private scalars directly). Each is a few lines to add, and
# none has a caller.
#
# THE ECDH SECRET IS NEVER HELD. Encap and Decap need only LabeledExtract("", "eae_prk", dh), which is
# HMAC(zeros, "HPKE-v1" || suite_id || "eae_prk" || dh) - an HMAC of a fixed prefix and Z, which is
# what DeriveKeyFromHmac computes inside the key's provider (relay/P256.ps1).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path $PSScriptRoot "Bytes.ps1")
. (Join-Path $PSScriptRoot "Backend.ps1")
. (Join-Path $PSScriptRoot "P256.ps1")

function Get-HordeRelayHpkeKemSuiteId {
    # "KEM" || I2OSP(kem_id, 2)
    return ,(Join-HordeRelayBytes -Parts @((Get-HordeRelayAsciiBytes -Text "KEM"), [byte[]]@(0x00, 0x10)))
}

function Get-HordeRelayHpkeSuiteId {
    # "HPKE" || I2OSP(kem_id, 2) || I2OSP(kdf_id, 2) || I2OSP(aead_id, 2)
    return ,(Join-HordeRelayBytes -Parts @((Get-HordeRelayAsciiBytes -Text "HPKE"), [byte[]]@(0x00, 0x10, 0x00, 0x01, 0x00, 0x02)))
}

function Get-HordeRelayHpkeLabel {
    # "HPKE-v1" || suite_id || label
    param([byte[]]$SuiteId, [string]$Label)
    return ,(Join-HordeRelayBytes -Parts @((Get-HordeRelayAsciiBytes -Text "HPKE-v1"), $SuiteId, (Get-HordeRelayAsciiBytes -Text $Label)))
}

function Invoke-HordeRelayHpkeLabeledExtract {
    param([AllowEmptyCollection()][byte[]]$Salt, [byte[]]$SuiteId, [string]$Label, [AllowEmptyCollection()][byte[]]$Ikm)
    return ,(Invoke-HordeRelayHkdfExtract -Salt $Salt -Ikm (Join-HordeRelayBytes -Parts @((Get-HordeRelayHpkeLabel -SuiteId $SuiteId -Label $Label), $Ikm)))
}

function Invoke-HordeRelayHpkeLabeledExpand {
    param([byte[]]$Prk, [byte[]]$SuiteId, [string]$Label, [AllowEmptyCollection()][byte[]]$Info, [int]$Length)
    $lengthBytes = [byte[]]@([byte](($Length -shr 8) -band 0xFF), [byte]($Length -band 0xFF))
    $labeled = Join-HordeRelayBytes -Parts @($lengthBytes, (Get-HordeRelayHpkeLabel -SuiteId $SuiteId -Label $Label), $Info)
    return ,(Invoke-HordeRelayHkdfExpand -Prk $Prk -Info $labeled -Length $Length)
}

function Get-HordeRelayHpkeSharedSecret {
    # DHKEM ExtractAndExpand: eae_prk = LabeledExtract("", "eae_prk", dh), then
    # shared_secret = LabeledExpand(eae_prk, "shared_secret", enc || pkR, 32).
    param($Private, [byte[]]$PeerPublic, [byte[]]$Enc, [byte[]]$RecipientPublic)
    $kem = Get-HordeRelayHpkeKemSuiteId
    $eaePrk = Invoke-HordeRelayEcdhExtract -Private $Private -PeerPublic $PeerPublic -Salt (New-Object byte[] 0) -Prefix (Get-HordeRelayHpkeLabel -SuiteId $kem -Label "eae_prk")
    $kemContext = Join-HordeRelayBytes -Parts @($Enc, $RecipientPublic)
    return ,(Invoke-HordeRelayHpkeLabeledExpand -Prk $eaePrk -SuiteId $kem -Label "shared_secret" -Info $kemContext -Length 32)
}

function New-HordeRelayHpkeKeySchedule {
    # KeySchedule for mode_base (0x00) with no PSK: { keyScheduleContext; secret; key; baseNonce; seq }.
    param([byte[]]$SharedSecret, [AllowEmptyCollection()][byte[]]$Info)
    $suite = Get-HordeRelayHpkeSuiteId
    $empty = New-Object byte[] 0
    $pskIdHash = Invoke-HordeRelayHpkeLabeledExtract -Salt $empty -SuiteId $suite -Label "psk_id_hash" -Ikm $empty
    $infoHash = Invoke-HordeRelayHpkeLabeledExtract -Salt $empty -SuiteId $suite -Label "info_hash" -Ikm $Info
    $ksc = Join-HordeRelayBytes -Parts @([byte[]]@(0x00), $pskIdHash, $infoHash)
    $secret = Invoke-HordeRelayHpkeLabeledExtract -Salt $SharedSecret -SuiteId $suite -Label "secret" -Ikm $empty
    return [pscustomobject]@{
        keyScheduleContext = $ksc
        secret = $secret
        key = (Invoke-HordeRelayHpkeLabeledExpand -Prk $secret -SuiteId $suite -Label "key" -Info $ksc -Length 32)
        baseNonce = (Invoke-HordeRelayHpkeLabeledExpand -Prk $secret -SuiteId $suite -Label "base_nonce" -Info $ksc -Length 12)
        seq = [long]0
    }
}

function New-HordeRelayHpkeSender {
    # SetupBaseS: encapsulate to the recipient's 65-byte public key. Returns the key schedule plus
    # enc (the 65-byte ephemeral public key the recipient needs) and sharedSecret. Ephemeral is for the
    # RFC 9180 vectors only, which fix the ephemeral key; every other caller leaves it out and gets a
    # fresh one, used once and disposed.
    param([Parameter(Mandatory = $true)][byte[]]$RecipientPublic, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Info, $Ephemeral = $null)
    $eph = $Ephemeral
    if ($null -eq $eph) { $eph = New-HordeRelayP256Key -Use "ecdh" }
    try {
        $enc = ConvertTo-HordeRelayP256Public -Key $eph
        $ss = Get-HordeRelayHpkeSharedSecret -Private $eph -PeerPublic $RecipientPublic -Enc $enc -RecipientPublic $RecipientPublic
    } finally { if ($null -eq $Ephemeral) { $eph.Dispose() } }
    $ctx = New-HordeRelayHpkeKeySchedule -SharedSecret $ss -Info $Info
    Add-Member -InputObject $ctx -NotePropertyName "enc" -NotePropertyValue $enc
    Add-Member -InputObject $ctx -NotePropertyName "sharedSecret" -NotePropertyValue $ss
    return $ctx
}

function New-HordeRelayHpkeReceiver {
    # SetupBaseR: decapsulate enc with the recipient's private key (an in-memory key, or a
    # non-exportable one from relay/Keys.ps1). Throws when enc is not a point on P-256.
    param([Parameter(Mandatory = $true)]$RecipientKey, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Enc, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Info)
    $pkR = ConvertTo-HordeRelayP256Public -Key $RecipientKey
    $ss = Get-HordeRelayHpkeSharedSecret -Private $RecipientKey -PeerPublic $Enc -Enc $Enc -RecipientPublic $pkR
    $ctx = New-HordeRelayHpkeKeySchedule -SharedSecret $ss -Info $Info
    Add-Member -InputObject $ctx -NotePropertyName "enc" -NotePropertyValue $Enc
    Add-Member -InputObject $ctx -NotePropertyName "sharedSecret" -NotePropertyValue $ss
    return $ctx
}

function Get-HordeRelayHpkeNonce {
    # ComputeNonce: base_nonce XOR I2OSP(seq, 12).
    param($Context)
    if ($Context.seq -lt 0 -or $Context.seq -eq [long]::MaxValue) { throw "the HPKE context's message limit is reached" }
    $n = New-Object byte[] 12
    [System.Array]::Copy([byte[]]$Context.baseNonce, 0, $n, 0, 12)
    $s = [long]$Context.seq
    for ($i = 11; $i -ge 4; $i--) {
        $n[$i] = $n[$i] -bxor [byte]($s -band 0xFF)
        $s = $s -shr 8
    }
    return ,$n
}

function Protect-HordeRelayHpkeMessage {
    # ContextS.Seal: the next message of this context; its sequence number then moves on by one.
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Aad, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Plaintext)
    $sealed = Protect-HordeRelayAesGcm -Key $Context.key -Nonce (Get-HordeRelayHpkeNonce -Context $Context) -Aad $Aad -Plaintext $Plaintext
    $Context.seq = $Context.seq + 1
    return ,$sealed
}

function Unprotect-HordeRelayHpkeMessage {
    # ContextR.Open: the plaintext, or $null when it does not open. The sequence number moves on only
    # when it opened (RFC 9180 5.2), so a forged message cannot knock a receiver out of step.
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Aad, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Sealed)
    $plain = Unprotect-HordeRelayAesGcm -Key $Context.key -Nonce (Get-HordeRelayHpkeNonce -Context $Context) -Aad $Aad -Sealed $Sealed
    if ($null -eq $plain) { return $null }
    $Context.seq = $Context.seq + 1
    return ,([byte[]]$plain)
}

function Protect-HordeRelayHpke {
    # Single-shot SealBase: { enc; sealed } for one message to one recipient.
    param([Parameter(Mandatory = $true)][byte[]]$RecipientPublic, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Info,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Aad, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Plaintext)
    $ctx = New-HordeRelayHpkeSender -RecipientPublic $RecipientPublic -Info $Info
    $sealed = Protect-HordeRelayHpkeMessage -Context $ctx -Aad $Aad -Plaintext $Plaintext
    return [pscustomobject]@{ enc = $ctx.enc; sealed = $sealed }
}

function Unprotect-HordeRelayHpke {
    # Single-shot OpenBase: the plaintext, or $null when it does not open - a wrong key, a wrong info or
    # AAD, a changed enc or ciphertext, or an enc that is not a P-256 point all look alike to the caller.
    param([Parameter(Mandatory = $true)]$RecipientKey, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Enc, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Info,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Aad, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Sealed)
    try { $ctx = New-HordeRelayHpkeReceiver -RecipientKey $RecipientKey -Enc $Enc -Info $Info } catch { return $null }
    $plain = Unprotect-HordeRelayHpkeMessage -Context $ctx -Aad $Aad -Sealed $Sealed
    if ($null -eq $plain) { return $null }
    return ,([byte[]]$plain)
}
