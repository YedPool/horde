# relay/Pairing.ps1 - pairing a founder's phone with this machine, as data: the machine makes a
# one-time offer, the phone answers it with a passkey registration, the machine verifies and enrolls.
# No screen and no network here: the offer is text to draw as a QR code, the response is text that
# arrives somehow (the runner and the PWA are later pull requests).
#
# THE OFFER (New-HordeRelayPairingOffer) is one canonical line (relay/Records.ps1), kind
# horde-relay-pairing-offer:
#   horde, offer (a random 128-bit id), code (a random 128-bit single-use secret, base64url),
#   machine (this machine's signing key id) with signPublic, agreeKeyId and agreePublic (so the phone
#   can seal to it and verify it), mailbox (this machine's relay mailbox, <horde>/<machine>),
#   pairMailbox (where the phone sends its response through the relay: <horde>/pair-<offer>, a
#   mailbox of this offer alone),
#   rpId and origins (the relying party the passkey is made for, and where the PWA is served),
#   issuedAt and expiresAt (milliseconds; 300 s by default, 30 to 900).
# About 650 to 750 characters, which a QR code holds at version 20 or 21 (level M, cli/QrCode.ps1). The phone makes a passkey with
#   challenge = SHA-256("horde-relay/pairing/v1 challenge" LF <the offer's text, exactly>)
# ES256 only, user verification required, attestation "none", and answers with a response, kind
# horde-relay-pairing-response: offer, code, rawId, clientDataJSON, attestationObject (each base64url
# of the browser's bytes), label (what the founder calls the device) and prf (the client's
# prf.enabled). Since the challenge is the hash of the whole offer, a registration made for one offer
# is useless for any other, and one that names another machine's keys or another horde does not verify.
#
# WHAT THE MACHINE KEEPS: pairing\offers\<offer>.json, the pending offer - the code's HASH, never the
# code, and the challenge - and, once used, pairing\used\<offer>.json. Both are write-once
# (relay/Records.ps1): the used marker is made by a move that never replaces, so of two responses to one
# offer racing each other, exactly one is enrolled.
#
# COMPLETING (Complete-HordeRelayPairing) checks, in order, each refusal naming its reason, and enrolls
# nothing on any refusal:
#   the response's canonical form; that this machine made the offer; that it was not used (a REPLAY of
#   the offer or its code is refused, whatever the registration - and the refusal NAMES THE DEVICE THE
#   OFFER ALREADY ENROLLED, its label, fingerprint and state, and hands it back, so a founder whose own
#   attempt was refused can reject a device that is not his); that it has not expired; the code, by its
#   hash, compared in constant time; that the horde and this machine's signing key are still the ones
#   the offer named (a rotation since the offer voids it); the registration (relay/Registration.ps1:
#   challenge, origin, rpId, attestation none, user present and verified, the COSE key valid and on the
#   curve); that the credential was never enrolled nor revoked (relay/Trust.ps1). Then the offer is
#   marked used, and then the device is enrolled - as PENDING. A response refused before the mark leaves
#   the offer usable, so a response the relay damaged in transit costs nothing; the mark comes before the
#   enrollment, so no offer ever enrolls two devices.
#
# CONFIRMING (Confirm-HordeRelayDevice, founder decision of 2026-10-09). A pending device is trusted
# only when the founder, at this machine, enters the FINGERPRINT his phone shows, and it matches the
# one this machine computed, within its CONFIRM WINDOW: the relay setting pendingConfirmMinutes (10 by
# default, 1 to 30), counted from the registration and independent of the offer, so a phone that
# registers in the offer's last seconds still has the whole window (founder answer, 2026-10-09). The
# fingerprint is:
#   fingerprint = 12 decimal digits, dddd-dddd-dddd, of SHA-256("horde-relay/pairing/v1 fingerprint"
#                 LF || challenge (32 bytes) || the passkey's 65-byte public point || the credential
#                 id's length (2 bytes, big-endian) || the credential id || the rpId in ASCII), the first
#                 8 bytes read as a number modulo 10^12
# WHY 12 DIGITS AND ALL FOUR INPUTS (review of 2243720, F1): a thief who holds the offer and can see the
# founder's screen could grind passkeys until one's fingerprint matched what the founder expects; 8
# digits fall to about 2^26.6 key generations, 12 need about 2^40, each a full key pair and hash. The
# credential id and rpId are bound too, so no part of what is enrolled can be swapped under the same
# fingerprint.
# The phone computes it from the challenge it signed and the key it made, so the two screens agree
# only when the machine enrolled the phone's OWN key under THIS offer. Unconfirmed when the window
# closes (pendingUntil), the device is expired for good.
# The check is constant-time and spaces or a dash may separate the groups.
#
# WHAT A STOLEN OFFER CAN AND CANNOT DO. The offer is a bearer secret for its short life: whoever holds
# its text before it is used and before it expires - a photo of the QR code, a screen share, a copy in a
# clipboard or a chat - CAN register a passkey of their own against it, and nothing in a registration
# with attestation "none" tells the founder's phone from another (a software authenticator can claim
# any origin). But that passkey is only PENDING: it signs nothing this machine accepts until the
# founder confirms its fingerprint at the machine - a fingerprint the THIEF's key produced, which is not
# the one the founder's phone shows. So a thief now needs the founder to type, at his own machine, a
# fingerprint he did not produce - and grinding a key to match the founder's costs about 2^40 key
# generations: 12 digits over the challenge, key, credential id and rpId (above). And:
#   - SINGLE USE. The thief's registration uses the offer, so the founder's own attempt is refused - and
#     the refusal names the thief's pending device, its label and fingerprint, so the founder rejects it
#     (Revoke-HordeRelayTrust) and makes a new offer.
#   - SHORT LIFE: an offer lives 300 seconds by default, at most 900, and an expired offer enrolls
#     nothing; a pending device not confirmed within its window (30 minutes at most) never can be.
#   - THE OFFER IS SHOWN ON THE MACHINE'S OWN SCREEN, to a person in front of it (`horde relay pair`): it
#     is never sent through the relay. Only the phone's RESPONSE travels through it (below).
# A stolen offer CANNOT: get a device trusted without the founder confirming its fingerprint at the
# machine; enroll a second device (single use); enroll after it expires, after it was used, or after
# this machine rotated its keys; act as this machine (the offer holds only public keys and this
# machine's private keys never leave its key store, relay/Keys.ps1); read anything sent to the phone or
# to this machine (the offer holds no decryption key; the phone identity key is separate, design Q7);
# survive revocation; or be used against another machine or horde (the challenge binds them). What it
# reveals to whoever sees it is metadata: the horde's name, this machine's public keys and its mailbox.
# What remains is the founder confirming a fingerprint without comparing it. `horde relay pair`
# (cli/RelayPair.ps1) narrows that: it never prints the machine's own fingerprint, so the only number
# he can type is the one his phone shows, and three wrong ones reject the device.
#
# THE RESPONSE THROUGH THE RELAY (relay PR plan item 7, next PR 1). The phone does not hand its response
# to the founder to carry: it SEALS it to this machine's agreement key - the one the offer names - and
# puts it in the offer's own pairing mailbox, pairMailbox, where `horde relay pair` waits for it. The
# sealed text (Get-HordeRelaySealedSpec), kind horde-relay-pairing-sealed, is one canonical line:
#   offer, agreeKeyId (the key it was sealed to), enc and ct: HPKE (relay/Hpke.ps1) with
#   info = "horde-relay/pairing/v1 response-key" and
#   aad  = "horde-relay/pairing/v1 response aad" LF horde LF offer LF agreeKeyId,
#   the plaintext being the response text exactly.
# WHY SEALED, WHEN THE RESPONSE AUTHENTICATES ITSELF. The registration inside answers the offer's
# challenge, which hashes the whole offer, and carries the offer's single-use code: nothing the relay
# can make enrolls anything (Complete, above). Sealing keeps the code and the credential from the relay,
# which sees only that a pairing happened; and the AAD binds the offer, so a sealed response cannot be
# relabelled for another offer.
# THE MACHINE REFUSES EVERYTHING NOT MATCHING AN OPEN OFFER, before it decrypts a byte
# (Open-HordeRelayPairingSealed): a text over maxSealedChars is not even read; a sealed text for an
# offer other than the one this pairing waits on, for an offer this machine never made, or for one
# already used or expired, is not opened; one sealed to another agreement key is not opened. What opens
# must be printable ASCII of at most maxResponseChars, a canonical response, for that same offer - and
# then it goes through Complete like a pasted one, single use and all. A pasted response is bounded the
# same way. THE BOUNDS: a phone's response is a few hundred characters (the registrations of
# test/fixtures/relay/registration make responses of under 1000), so 6000 leaves room for any
# credential id a WebAuthn client makes and keeps the sealed text's ct inside one record b64u (8192).
#
# Every function that judges the far end's input answers { ok; reason; value } and never throws for it.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")
. (Join-Path $PSScriptRoot "Bytes.ps1")
. (Join-Path $PSScriptRoot "Records.ps1")
. (Join-Path $PSScriptRoot "Hpke.ps1")
. (Join-Path $PSScriptRoot "Registration.ps1")
. (Join-Path $PSScriptRoot "Identity.ps1")
. (Join-Path $PSScriptRoot "Trust.ps1")

function Get-HordeRelayPairingLimits {
    # ttl: long enough to unlock a phone, open the PWA and scan; short enough that a photo of the code
    # is soon worthless. 300 s is the default and 900 the most a caller may ask for.
    # maxResponseChars and maxSealedChars: THE RESPONSE THROUGH THE RELAY, in the header. A sealed text
    # is its ciphertext (the response and a 16-byte tag) in base64url and some 250 characters around it.
    return [pscustomobject]@{ defaultTtlSeconds = 300; minTtlSeconds = 30; maxTtlSeconds = 900; maxResponseChars = 6000; maxSealedChars = 8600 }
}

function Get-HordeRelayOfferSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "horde", "name", "offer", "hex32", "code", "b64u", "machine", "hex32",
        "signPublic", "point", "agreeKeyId", "hex32", "agreePublic", "point", "mailbox", "mailbox", "pairMailbox", "mailbox", "rpId", "rpid",
        "origins", "origins", "issuedAt", "int", "expiresAt", "int"))
}

function Get-HordeRelayPendingSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "offer", "hex32", "horde", "name", "machine", "hex32", "codeHash", "b64u",
        "challenge", "b64u", "rpId", "rpid", "origins", "origins", "issuedAt", "int", "expiresAt", "int"))
}

function Get-HordeRelayUsedSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "offer", "hex32", "device", "hex32", "usedAt", "int"))
}

function Get-HordeRelayResponseSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "offer", "hex32", "code", "b64u", "rawId", "b64u", "clientDataJSON", "b64u",
        "attestationObject", "b64u", "label", "label", "prf", "bool"))
}

function Get-HordeRelaySealedSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "offer", "hex32", "agreeKeyId", "hex32", "enc", "point", "ct", "b64u"))
}

function Get-HordeRelayPairingMailbox {
    # The offer's own pairing mailbox: <horde>/pair-<offer>, read by this machine alone and only while
    # the offer is open (THE RESPONSE THROUGH THE RELAY, in the header).
    param([Parameter(Mandatory = $true)][string]$Horde, [Parameter(Mandatory = $true)][string]$Offer)
    return ($Horde + "/pair-" + $Offer)
}

function Get-HordeRelaySealedDomain {
    # The sealed response's HPKE info, or its AAD, which binds the horde, the offer and the key (the
    # header).
    param([Parameter(Mandatory = $true)][string]$Part, [string]$Horde = "", [string]$Offer = "", [string]$AgreeKeyId = "")
    if ($Part -ceq "info") { return ,(Get-HordeRelayAsciiBytes -Text "horde-relay/pairing/v1 response-key") }
    return ,(Get-HordeRelayAsciiBytes -Text ("horde-relay/pairing/v1 response aad`n" + $Horde + "`n" + $Offer + "`n" + $AgreeKeyId))
}

function Get-HordeRelayPairingChallenge {
    # The challenge a passkey made for this offer carries: SHA-256 of the domain and the offer's text.
    param([Parameter(Mandatory = $true)][string]$OfferText)
    return ,(Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text ("horde-relay/pairing/v1 challenge`n" + $OfferText)))
}

function Get-HordeRelayPairingFingerprint {
    # The fingerprint both screens show for one passkey under one offer (the header): dddd-dddd-dddd,
    # from the offer's challenge, the passkey's 65-byte public point, its credential id and the rpId.
    param([Parameter(Mandatory = $true)][byte[]]$Challenge, [Parameter(Mandatory = $true)][byte[]]$Public,
        [Parameter(Mandatory = $true)][byte[]]$CredentialId, [Parameter(Mandatory = $true)][string]$RpId)
    if ($CredentialId.Length -gt 65535) { throw "a credential id is at most 65535 bytes here" }
    $idLen = [byte[]]@([byte]($CredentialId.Length -shr 8), [byte]($CredentialId.Length -band 255))
    $h = Get-HordeRelaySha256 -Bytes (Join-HordeRelayBytes -Parts @((Get-HordeRelayAsciiBytes -Text "horde-relay/pairing/v1 fingerprint`n"), $Challenge, $Public, $idLen, $CredentialId, (Get-HordeRelayAsciiBytes -Text $RpId)))
    $n = [long]0
    for ($i = 0; $i -lt 8; $i++) { $n = ($n * 256 + [long]$h[$i]) % 1000000000000 }
    $digits = $n.ToString("000000000000")
    return ($digits.Substring(0, 4) + "-" + $digits.Substring(4, 4) + "-" + $digits.Substring(8, 4))
}

function Get-HordeRelayEarlierDevice {
    # The device a used offer enrolled, from its used mark, as the trust store answers it at NowMs, or
    # $null. For a founder whose own attempt was refused (the header).
    param([string]$HordeHome, [string]$UsedText, $Now)
    $u = Read-HordeRelayRecordText -Text $UsedText -Spec (Get-HordeRelayUsedSpec) -Kind "horde-relay-pairing-used"
    if (-not $u.ok) { return $null }
    $s = Read-HordeRelayTrustStore -HordeHome $HordeHome -Now $Now
    if (-not $s.ok) { return $null }
    return (@($s.devices | Where-Object { $_.id -ceq $u.value.device }) | Select-Object -First 1)
}

function Get-HordeRelayUsedRefusal {
    # The refusal of a response to a used offer, naming what the offer enrolled.
    param([string]$Offer, $Earlier, [string]$Race = "")
    $fail = [pscustomobject]@{ ok = $false; reason = ""; value = $null }
    $fail.reason = "the pairing offer " + $Offer + " was already used" + $Race + "; an offer and its code enroll one device, once (a replay is refused)"
    if ($null -ne $Earlier) {
        $fail.reason += (". It enrolled the device " + $Earlier.id + " '" + $Earlier.label + "', fingerprint " + $Earlier.fingerprint + ", now " + $Earlier.state +
            ". If that is not yours, reject it: Revoke-HordeRelayTrust -Subject device -Id " + $Earlier.id)
        $fail.value = [pscustomobject]@{ earlier = $Earlier }
    }
    return $fail
}

function Test-HordeRelayOriginForRpId {
    # "" when every origin may make passkeys for RpId (its host is the rpId or a subdomain of it, as
    # WebAuthn requires), else why not.
    param([string]$RpId, [string[]]$Origins)
    if ((Test-HordeRelayRecordValue -Kind "rpid" -Value $RpId) -cne "") { return ("'" + $RpId + "' is not a relying party id") }
    $why = Test-HordeRelayRecordValue -Kind "origins" -Value $Origins
    if ($why -cne "") { return $why }
    foreach ($o in $Origins) {
        $hostPart = [regex]::Replace($o, '\A[a-z]+://([^:/]+)(:[0-9]+)?\z', '$1')
        if ($hostPart -cne $RpId -and -not $hostPart.EndsWith("." + $RpId)) { return ("the origin " + $o + " cannot make passkeys for the relying party " + $RpId) }
    }
    return ""
}

function New-HordeRelayPairingOffer {
    # A one-time pairing offer from this machine. Known { text; offer; code; challenge; expiresAt;
    # pairMailbox },
    # text being what the QR code holds; the identity's or horde's answer when there is none; unknown
    # when the offer could not be kept.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$RpId, [Parameter(Mandatory = $true)][string[]]$Origins,
        [int]$TtlSeconds = 300, $Now = $null)
    $limits = Get-HordeRelayPairingLimits
    if ($TtlSeconds -lt $limits.minTtlSeconds -or $TtlSeconds -gt $limits.maxTtlSeconds) { return (New-HordeUnknown -Reason ("an offer lives " + $limits.minTtlSeconds + " to " + $limits.maxTtlSeconds + " seconds, not " + $TtlSeconds)) }
    $why = Test-HordeRelayOriginForRpId -RpId $RpId -Origins $Origins
    if ($why -cne "") { return (New-HordeUnknown -Reason $why) }
    $id = Get-HordeRelayMachineIdentity -HordeHome $HordeHome
    if ($id.state -cne "known") { return $id }
    $issued = ConvertTo-HordeRelayRecordMs -Time $Now
    $offerId = ConvertTo-HordeRelayHex -Bytes (Get-HordeRelayRandomBytes -Count 16)
    $code = ConvertTo-HordeRelayBase64Url -Bytes (Get-HordeRelayRandomBytes -Count 16)
    $expires = $issued + [long]$TtlSeconds * 1000
    $text = ConvertTo-HordeRelayRecordText -Spec (Get-HordeRelayOfferSpec) -Values @{
        v = 1; kind = "horde-relay-pairing-offer"; horde = $id.value.horde; offer = $offerId; code = $code; machine = $id.value.sign.keyId
        signPublic = (ConvertTo-HordeRelayBase64Url -Bytes $id.value.sign.public); agreeKeyId = $id.value.agree.keyId
        agreePublic = (ConvertTo-HordeRelayBase64Url -Bytes $id.value.agree.public); mailbox = $id.value.mailbox
        pairMailbox = (Get-HordeRelayPairingMailbox -Horde $id.value.horde -Offer $offerId); rpId = $RpId; origins = @($Origins); issuedAt = $issued; expiresAt = $expires
    }
    $challenge = ConvertTo-HordeRelayBase64Url -Bytes (Get-HordeRelayPairingChallenge -OfferText $text)
    $codeHash = ConvertTo-HordeRelayBase64Url -Bytes (Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text $code))
    $pending = ConvertTo-HordeRelayRecordText -Spec (Get-HordeRelayPendingSpec) -Values @{
        v = 1; kind = "horde-relay-pairing-pending"; offer = $offerId; horde = $id.value.horde; machine = $id.value.sign.keyId; codeHash = $codeHash
        challenge = $challenge; rpId = $RpId; origins = @($Origins); issuedAt = $issued; expiresAt = $expires
    }
    try { $moved = Write-HordeRelayRecordFile -Dir ([System.IO.Path]::Combine((Get-HordeRelayStateDir -HordeHome $HordeHome -Part "pairing"), "offers")) -Name ($offerId + ".json") -Text $pending }
    catch { return (New-HordeUnknown -Reason "the pairing offer could not be kept" -ErrorRecord $_) }
    if ($moved -cne "moved") { return (New-HordeUnknown -Reason ("the pairing offer could not be kept: " + $moved)) }
    return (New-HordeKnown -Value ([pscustomobject]@{ text = $text; offer = $offerId; code = $code; challenge = $challenge; expiresAt = $expires
        pairMailbox = (Get-HordeRelayPairingMailbox -Horde $id.value.horde -Offer $offerId) }))
}

function Read-HordeRelayPairingOffer {
    # The values of an offer's text, for the phone side and the suites: { ok; reason; value }.
    param([AllowEmptyString()][string]$Text)
    return (Read-HordeRelayRecordText -Text $Text -Spec (Get-HordeRelayOfferSpec) -Kind "horde-relay-pairing-offer" -What "the pairing offer")
}

function New-HordeRelayPairingResponseText {
    # The response text the phone sends, from its parts - the one spelling Complete reads. The PWA
    # writes the same; the suites build theirs here.
    param([Parameter(Mandatory = $true)][string]$Offer, [Parameter(Mandatory = $true)][string]$Code, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$RawId,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$ClientDataJson, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$AttestationObject,
        [Parameter(Mandatory = $true)][string]$Label, [bool]$Prf = $false)
    return (ConvertTo-HordeRelayRecordText -Spec (Get-HordeRelayResponseSpec) -Values @{
        v = 1; kind = "horde-relay-pairing-response"; offer = $Offer; code = $Code; rawId = (ConvertTo-HordeRelayBase64Url -Bytes $RawId)
        clientDataJSON = (ConvertTo-HordeRelayBase64Url -Bytes $ClientDataJson); attestationObject = (ConvertTo-HordeRelayBase64Url -Bytes $AttestationObject)
        label = $Label; prf = $Prf
    })
}

function Get-HordeRelayOpenOffer {
    # Is -Offer an offer this machine made that is still open at -Now - not used, not expired?
    # { ok; reason; value }, value { pending; root; nowMs }; a used offer's refusal names the device it
    # enrolled (Get-HordeRelayUsedRefusal).
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$Offer, $Now = $null)
    $fail = [pscustomobject]@{ ok = $false; reason = ""; value = $null }
    if ($Offer -cnotmatch '\A[0-9a-f]{32}\z') { $fail.reason = ("'" + $Offer + "' is not an offer id"); return $fail }
    try {
        $root = Get-HordeRelayStateDir -HordeHome $HordeHome -Part "pairing"
    } catch { $fail.reason = $_.Exception.Message; return $fail }
    $pf = Read-HordeRelayRecordFile -Path ([System.IO.Path]::Combine($root, "offers", ($Offer + ".json")))
    if (-not $pf.ok) { $fail.reason = $pf.reason; return $fail }
    if (-not $pf.found) { $fail.reason = ("no pairing offer " + $Offer + " was made by this machine"); return $fail }
    $p = Read-HordeRelayRecordText -Text $pf.text -Spec (Get-HordeRelayPendingSpec) -Kind "horde-relay-pairing-pending" -What ("the pending offer " + $Offer)
    if (-not $p.ok) { $fail.reason = $p.reason; return $fail }
    $pending = $p.value
    if ($pending.offer -cne $Offer) { $fail.reason = ("the pending offer filed as " + $Offer + " is another offer's"); return $fail }
    $uf = Read-HordeRelayRecordFile -Path ([System.IO.Path]::Combine($root, "used", ($Offer + ".json")))
    if (-not $uf.ok) { $fail.reason = $uf.reason; return $fail }
    if ($uf.found) { return (Get-HordeRelayUsedRefusal -Offer $Offer -Earlier (Get-HordeRelayEarlierDevice -HordeHome $HordeHome -UsedText $uf.text -Now $Now)) }
    $nowMs = ConvertTo-HordeRelayRecordMs -Time $Now
    if ($nowMs -gt $pending.expiresAt) { $fail.reason = ("the pairing offer " + $Offer + " expired " + [long][System.Math]::Floor(($nowMs - $pending.expiresAt) / 1000) + " s ago"); return $fail }
    return [pscustomobject]@{ ok = $true; reason = ""; value = ([pscustomobject]@{ pending = $pending; root = $root; nowMs = $nowMs }) }
}

function New-HordeRelayPairingSealedText {
    # The sealed text a phone puts in the offer's pairing mailbox (the header): -Response sealed to the
    # agreement key -OfferText names. The PWA writes the same (relay/js/protocol.js); the suites build
    # theirs here, and -AgreePublic seals to another key, for the refusals.
    param([Parameter(Mandatory = $true)][string]$OfferText, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Response, [byte[]]$AgreePublic = $null)
    $o = Read-HordeRelayPairingOffer -Text $OfferText
    if (-not $o.ok) { throw $o.reason }
    $pub = $(if ($null -ne $AgreePublic) { $AgreePublic } else { ConvertFrom-HordeRelayBase64Url -Text $o.value.agreePublic })
    $kid = Get-HordeRelayKeyId -Public $pub
    $box = Protect-HordeRelayHpke -RecipientPublic $pub -Info (Get-HordeRelaySealedDomain -Part "info") `
        -Aad (Get-HordeRelaySealedDomain -Part "aad" -Horde $o.value.horde -Offer $o.value.offer -AgreeKeyId $kid) -Plaintext (Get-HordeRelayAsciiBytes -Text $Response)
    return (ConvertTo-HordeRelayRecordText -Spec (Get-HordeRelaySealedSpec) -Values @{
        v = 1; kind = "horde-relay-pairing-sealed"; offer = $o.value.offer; agreeKeyId = $kid
        enc = (ConvertTo-HordeRelayBase64Url -Bytes $box.enc); ct = (ConvertTo-HordeRelayBase64Url -Bytes $box.sealed)
    })
}

function Open-HordeRelayPairingSealed {
    # Open a sealed response that came through the relay, for the offer -Offer this pairing waits on
    # (the header: everything not matching that open offer is refused before a byte is decrypted).
    # { ok; reason; value }, value the response text, for Complete-HordeRelayPairing.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$Offer, [AllowEmptyString()][AllowNull()][string]$Text, $Now = $null)
    $fail = [pscustomobject]@{ ok = $false; reason = ""; value = $null }
    $limits = Get-HordeRelayPairingLimits
    if ($null -eq $Text) { $Text = "" }
    if ($Text.Length -gt $limits.maxSealedChars) { $fail.reason = ("the sealed response is " + $Text.Length + " characters, over the " + $limits.maxSealedChars + " a pairing response may be; it is not read"); return $fail }
    $r = Read-HordeRelayRecordText -Text $Text -Spec (Get-HordeRelaySealedSpec) -Kind "horde-relay-pairing-sealed" -What "the sealed pairing response"
    if (-not $r.ok) { $fail.reason = $r.reason; return $fail }
    $sealed = $r.value
    if ($sealed.offer -cne $Offer) { $fail.reason = ("the sealed response is for the offer " + $sealed.offer + ", not the offer this pairing waits on (" + $Offer + "); it is not opened"); return $fail }
    $open = Get-HordeRelayOpenOffer -HordeHome $HordeHome -Offer $Offer -Now $Now
    if (-not $open.ok) { $fail.reason = ($open.reason + "; the sealed response is not opened"); return $fail }
    $id = Get-HordeRelayMachineIdentity -HordeHome $HordeHome -Open -Now $Now
    if ($id.state -cne "known") { $fail.reason = ("this machine's keys cannot be opened, so the sealed response is not: " + $id.reason); return $fail }
    $plain = $null
    try {
        if ($id.value.horde -cne $open.value.pending.horde -or $id.value.sign.keyId -cne $open.value.pending.machine) { $fail.reason = "this machine's horde or signing key changed since the offer was made; the offer is void, make a new one"; return $fail }
        if ($sealed.agreeKeyId -cne $id.value.agree.keyId) { $fail.reason = ("the response is sealed to the agreement key " + $sealed.agreeKeyId + ", not this machine's current one (" + $id.value.agree.keyId + "); it is not opened"); return $fail }
        $plain = Unprotect-HordeRelayHpke -RecipientKey $id.value.agree.key -Enc (ConvertFrom-HordeRelayBase64Url -Text $sealed.enc) -Info (Get-HordeRelaySealedDomain -Part "info") `
            -Aad (Get-HordeRelaySealedDomain -Part "aad" -Horde $open.value.pending.horde -Offer $Offer -AgreeKeyId $sealed.agreeKeyId) -Sealed (ConvertFrom-HordeRelayBase64Url -Text $sealed.ct)
    } finally { $id.value.sign.key.Dispose(); $id.value.agree.key.Dispose() }
    if ($null -eq $plain) { $fail.reason = "the sealed response does not open: it was not sealed for this offer and this machine's key, or it was changed on the way"; return $fail }
    if ($plain.Length -gt $limits.maxResponseChars) { $fail.reason = ("the response inside is " + $plain.Length + " bytes, over the " + $limits.maxResponseChars + " a pairing response may be"); return $fail }
    foreach ($b in $plain) { if ($b -lt 0x20 -or $b -gt 0x7E) { $fail.reason = "the response inside is not printable ASCII"; return $fail } }
    $plainText = [System.Text.Encoding]::ASCII.GetString($plain)
    $resp = Read-HordeRelayRecordText -Text $plainText -Spec (Get-HordeRelayResponseSpec) -Kind "horde-relay-pairing-response" -What "the pairing response inside"
    if (-not $resp.ok) { $fail.reason = $resp.reason; return $fail }
    if ($resp.value.offer -cne $Offer) { $fail.reason = ("the response inside answers another offer (" + $resp.value.offer + ") than the one it was sealed for"); return $fail }
    return [pscustomobject]@{ ok = $true; reason = ""; value = $plainText }
}

function Complete-HordeRelayPairing {
    # Verify a phone's response to an offer and enroll its passkey (the header has the order of the
    # checks). { ok; reason; value }, value { device; fingerprint } when enrolled. -Label, when given, is
    # what the device is recorded as instead of the label the phone sent (the founder names it here).
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Response, [string]$Label = "", $Now = $null)
    $fail = [pscustomobject]@{ ok = $false; reason = ""; value = $null }
    $limits = Get-HordeRelayPairingLimits
    if ($Response.Length -gt $limits.maxResponseChars) { $fail.reason = ("the pairing response is " + $Response.Length + " characters, over the " + $limits.maxResponseChars + " one may be; it is not read"); return $fail }
    if ($Label -cne "" -and (Test-HordeRelayRecordValue -Kind "label" -Value $Label) -cne "") { $fail.reason = "a device label is 1 to 64 printable ASCII characters, no quote or backslash, no space at either end"; return $fail }
    $r = Read-HordeRelayRecordText -Text $Response -Spec (Get-HordeRelayResponseSpec) -Kind "horde-relay-pairing-response" -What "the pairing response"
    if (-not $r.ok) { $fail.reason = $r.reason; return $fail }
    $resp = $r.value
    $open = Get-HordeRelayOpenOffer -HordeHome $HordeHome -Offer $resp.offer -Now $Now
    if (-not $open.ok) { return $open }
    $pending = $open.value.pending
    $root = $open.value.root
    $nowMs = $open.value.nowMs
    $codeHash = ConvertTo-HordeRelayBase64Url -Bytes (Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text $resp.code))
    if (-not (Test-HordeRelayBytesEqual -Left (Get-HordeRelayAsciiBytes -Text $codeHash) -Right (Get-HordeRelayAsciiBytes -Text $pending.codeHash))) { $fail.reason = "the code is not this offer's"; return $fail }
    $id = Get-HordeRelayMachineIdentity -HordeHome $HordeHome
    if ($id.state -cne "known") { $fail.reason = ("this machine's identity cannot be read, so no device is enrolled: " + $id.reason); return $fail }
    if ($id.value.horde -cne $pending.horde -or $id.value.sign.keyId -cne $pending.machine) { $fail.reason = "this machine's horde or signing key changed since the offer was made; the offer is void, make a new one"; return $fail }
    $settings = Get-HordeRelaySettingValues -HordeHome $HordeHome
    if ($settings.state -cne "known") { $fail.reason = ("the relay settings are refused, so nothing is enrolled: " + $settings.reason); return $fail }
    $reg = Test-HordeRelayWebAuthnRegistration -ClientDataJson (ConvertFrom-HordeRelayBase64Url -Text $resp.clientDataJSON) -AttestationObject (ConvertFrom-HordeRelayBase64Url -Text $resp.attestationObject) `
        -RawId (ConvertFrom-HordeRelayBase64Url -Text $resp.rawId) -Challenge (ConvertFrom-HordeRelayBase64Url -Text $pending.challenge) -RpId $pending.rpId -Origins @($pending.origins) -RequireUserVerification $true
    if (-not $reg.ok) { $fail.reason = ("the registration is refused: " + $reg.reason); return $fail }
    $store = Read-HordeRelayTrustStore -HordeHome $HordeHome -Now $Now
    if (-not $store.ok) { $fail.reason = ($store.reason + "; nothing is enrolled until it is repaired"); return $fail }
    $devId = Get-HordeRelayDeviceId -CredentialId $reg.credentialId
    $prior = @($store.devices | Where-Object { $_.id -ceq $devId -or $_.keyId -ceq (Get-HordeRelayKeyId -Public $reg.public) }) | Select-Object -First 1
    if ($null -ne $prior) { $fail.reason = $(if ($null -ne $prior.revoked) { "this credential was revoked and is never enrolled again; make a new passkey" } else { "this credential is already enrolled as '" + $prior.label + "'" }); return $fail }
    # The mark, then the enrollment: no offer ever enrolls two devices (the header).
    try {
        $used = ConvertTo-HordeRelayRecordText -Spec (Get-HordeRelayUsedSpec) -Values @{ v = 1; kind = "horde-relay-pairing-used"; offer = $resp.offer; device = $devId; usedAt = $nowMs }
        $moved = Write-HordeRelayRecordFile -Dir ([System.IO.Path]::Combine($root, "used")) -Name ($resp.offer + ".json") -Text $used
    } catch { $fail.reason = ("the offer could not be marked used, so nothing was enrolled: " + $_.Exception.Message); return $fail }
    if ($moved -ceq "exists") {
        $uf = Read-HordeRelayRecordFile -Path ([System.IO.Path]::Combine($root, "used", ($resp.offer + ".json")))
        return (Get-HordeRelayUsedRefusal -Offer $resp.offer -Earlier $(if ($uf.ok -and $uf.found) { Get-HordeRelayEarlierDevice -HordeHome $HordeHome -UsedText $uf.text -Now $Now } else { $null }) -Race ", by another response at the same moment")
    }
    if ($moved -cne "moved") { $fail.reason = "the offer's used mark has its name, but nothing says it reached the disk; nothing was enrolled, and the offer is spent"; return $fail }
    $pendingUntil = $nowMs + [long]$settings.value.values.pendingConfirmMinutes * 60000
    $fingerprint = Get-HordeRelayPairingFingerprint -Challenge (ConvertFrom-HordeRelayBase64Url -Text $pending.challenge) -Public $reg.public -CredentialId $reg.credentialId -RpId $pending.rpId
    $dev = Add-HordeRelayPendingDevice -HordeHome $HordeHome -Registration $reg -Horde $pending.horde -RpId $pending.rpId -Origins @($pending.origins) -Label $(if ($Label -cne "") { $Label } else { $resp.label }) `
        -Prf $resp.prf -OfferId $resp.offer -Fingerprint $fingerprint -PendingUntil $pendingUntil -Now $Now
    if ($dev.state -cne "known") { $fail.reason = ("the offer is now used, but the device was not enrolled: " + $dev.reason); return $fail }
    return [pscustomobject]@{ ok = $true; reason = ""; value = ([pscustomobject]@{ device = $dev.value; fingerprint = $fingerprint; pendingUntil = $pendingUntil }) }
}

function Confirm-HordeRelayDevice {
    # The founder, at this machine, confirms a PENDING device with the fingerprint his phone shows
    # (the header). { ok; reason; value }, value { device; already } when it is trusted.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Fingerprint, $Now = $null)
    $fail = [pscustomobject]@{ ok = $false; reason = ""; value = $null }
    $s = Read-HordeRelayTrustStore -HordeHome $HordeHome -Now $Now
    if (-not $s.ok) { $fail.reason = ($s.reason + "; nothing is confirmed until it is repaired"); return $fail }
    $d = @($s.devices | Where-Object { $_.id -ceq $Id }) | Select-Object -First 1
    if ($null -eq $d) { $fail.reason = ("the trust store holds no device " + $Id); return $fail }
    if ($d.state -ceq "trusted") { return [pscustomobject]@{ ok = $true; reason = ""; value = ([pscustomobject]@{ device = $d; already = $true }) } }
    if ($d.state -ceq "revoked") { $fail.reason = ("the device " + $Id + " was revoked (rejected) and is never confirmed"); return $fail }
    if ($d.state -ceq "expired") { $fail.reason = ("the device " + $Id + " expired unconfirmed when its confirm window closed; pair again with a new passkey"); return $fail }
    try { $root = Get-HordeRelayStateDir -HordeHome $HordeHome -Part "pairing" } catch { $fail.reason = $_.Exception.Message; return $fail }
    $pf = Read-HordeRelayRecordFile -Path ([System.IO.Path]::Combine($root, "offers", ($d.offer + ".json")))
    if (-not $pf.ok -or -not $pf.found) { $fail.reason = ("the offer that enrolled device " + $Id + " cannot be read, so its fingerprint cannot be checked"); return $fail }
    $p = Read-HordeRelayRecordText -Text $pf.text -Spec (Get-HordeRelayPendingSpec) -Kind "horde-relay-pairing-pending" -What ("the pending offer " + $d.offer)
    if (-not $p.ok) { $fail.reason = $p.reason; return $fail }
    $want = Get-HordeRelayPairingFingerprint -Challenge (ConvertFrom-HordeRelayBase64Url -Text $p.value.challenge) -Public (ConvertFrom-HordeRelayBase64Url -Text $d.publicKey) `
        -CredentialId (ConvertFrom-HordeRelayBase64Url -Text $d.credentialId) -RpId $d.rpId
    if ($want -cne $d.fingerprint) { $fail.reason = ("the device " + $Id + " records a fingerprint that is not its offer's and key's; the store is damaged"); return $fail }
    $given = [regex]::Replace($Fingerprint, '[ -]', '')
    if ($given -cnotmatch '\A[0-9]{12}\z' -or -not (Test-HordeRelayBytesEqual -Left (Get-HordeRelayAsciiBytes -Text $given) -Right (Get-HordeRelayAsciiBytes -Text $want.Replace("-", "")))) {
        $fail.reason = ("the fingerprint does not match the one this machine computed for device " + $Id + "; if the phone shows another, this device is not that phone's - reject it")
        return $fail
    }
    $c = Add-HordeRelayDeviceConfirmation -HordeHome $HordeHome -Id $Id -Now $Now
    if ($c.state -cne "known") { $fail.reason = $c.reason; return $fail }
    return [pscustomobject]@{ ok = $true; reason = ""; value = $c.value }
}
