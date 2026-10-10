# test/lib/RelayPhone.ps1 - a founder's phone in PowerShell, for the suites of the relay channels: a passkey
# and a phone identity key held in memory, and the bytes a phone sends, built from relay/'s own
# primitives. test/test-relay-phone-e2e.ps1 uses a phone made with WebCrypto instead
# (test/fixtures/relay/phone/phone.mjs), so the machine side is also checked against bytes it did not
# make; this one is for the many cases a suite needs fast, in one process.
#
# Requires relay/Pairing.ps1 (and so relay/Envelope.ps1 and relay/Trust.ps1) to be loaded first.

$script:HordeTestPhoneRpId = "relay.example.test"
$script:HordeTestPhoneOrigin = "https://relay.example.test"
$script:HordeTestPhoneUtf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false

function ConvertTo-HordeTestPhoneDer {
    # A 64-byte r || s signature as the minimal DER a WebAuthn assertion carries.
    param([byte[]]$Sig)
    $ints = New-Object System.Collections.ArrayList
    foreach ($half in @(0, 32)) {
        $i = $half
        while ($i -lt $half + 31 -and $Sig[$i] -eq 0) { $i++ }
        $trim = New-Object byte[] (($half + 32) - $i)
        [System.Array]::Copy($Sig, $i, $trim, 0, $trim.Length)
        if (($trim[0] -band 0x80) -ne 0) { $trim = Join-HordeRelayBytes -Parts @([byte[]]@(0), $trim) }
        [void]$ints.Add((Join-HordeRelayBytes -Parts @([byte[]]@(2, $trim.Length), $trim)))
    }
    $body = Join-HordeRelayBytes -Parts @($ints[0], $ints[1])
    return ,(Join-HordeRelayBytes -Parts @([byte[]]@(0x30, $body.Length), $body))
}

function New-HordeTestPhone {
    # A phone: a passkey (ECDSA) with its credential id, and a phone identity key (ECDH).
    $k = New-HordeRelayP256Key -Use "ecdsa"
    $a = New-HordeRelayP256Key -Use "ecdh"
    $pub = ConvertTo-HordeRelayP256Public -Key $k
    return [pscustomobject]@{ key = $k; public = $pub; keyId = (Get-HordeRelayKeyId -Public $pub); credentialId = (Get-HordeRelayRandomBytes -Count 32)
        agree = $a; agreePublic = (ConvertTo-HordeRelayP256Public -Key $a); seq = @{}; deviceId = "" }
}

function New-HordeTestPhoneAssertion {
    # A WebAuthn get() by the phone's passkey over -Challenge, user verified: { authenticatorData;
    # clientDataJson; signature }.
    param($Phone, [byte[]]$Challenge)
    $ad = Join-HordeRelayBytes -Parts @((Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text $script:HordeTestPhoneRpId)), [byte[]]@(0x05, 0, 0, 0, 0))
    $cdj = $script:HordeTestPhoneUtf8.GetBytes('{"type":"webauthn.get","challenge":"' + (ConvertTo-HordeRelayBase64Url -Bytes $Challenge) + '","origin":"' + $script:HordeTestPhoneOrigin + '","crossOrigin":false}')
    $sig = $Phone.key.SignData((Join-HordeRelayBytes -Parts @($ad, (Get-HordeRelaySha256 -Bytes $cdj))), [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    return [pscustomobject]@{ authenticatorData = $ad; clientDataJson = $cdj; signature = (ConvertTo-HordeTestPhoneDer -Sig $sig) }
}

function Add-HordeTestPhonePairing {
    # Pair the phone with the machine of -HordeHome and confirm it at the "machine" with the fingerprint:
    # its passkey becomes a TRUSTED device. -NoConfirm leaves it pending. The device's id, or a throw.
    param([string]$HordeHome, $Phone, [switch]$NoConfirm)
    $o = New-HordeRelayPairingOffer -HordeHome $HordeHome -RpId $script:HordeTestPhoneRpId -Origins @($script:HordeTestPhoneOrigin)
    if ($o.state -cne "known") { throw ("no offer: " + $o.reason) }
    $offer = $o.value
    $x = New-Object byte[] 32; $y = New-Object byte[] 32
    [System.Array]::Copy($Phone.public, 1, $x, 0, 32); [System.Array]::Copy($Phone.public, 33, $y, 0, 32)
    $cose = Join-HordeRelayBytes -Parts @((ConvertFrom-HordeRelayHex -Text "a5010203262001215820"), $x, (ConvertFrom-HordeRelayHex -Text "225820"), $y)
    $ad = Join-HordeRelayBytes -Parts @((Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text $script:HordeTestPhoneRpId)), [byte[]]@(0x45, 0, 0, 0, 0), (New-Object byte[] 16), [byte[]]@(0, 32), $Phone.credentialId, $cose)
    $att = Join-HordeRelayBytes -Parts @((ConvertFrom-HordeRelayHex -Text "a363666d74646e6f6e656761747453746d74a0686175746844617461"), [byte[]]@(0x58, $ad.Length), $ad)
    $cdj = $script:HordeTestPhoneUtf8.GetBytes('{"type":"webauthn.create","challenge":"' + $offer.challenge + '","origin":"' + $script:HordeTestPhoneOrigin + '","crossOrigin":false}')
    $resp = New-HordeRelayPairingResponseText -Offer $offer.offer -Code $offer.code -RawId $Phone.credentialId -ClientDataJson $cdj -AttestationObject $att -Label "Founder phone" -Prf $false
    $c = Complete-HordeRelayPairing -HordeHome $HordeHome -Response $resp
    if (-not $c.ok) { throw ("pairing refused: " + $c.reason) }
    $Phone.deviceId = $c.value.device.id
    if (-not $NoConfirm) {
        $k = Confirm-HordeRelayDevice -HordeHome $HordeHome -Id $c.value.device.id -Fingerprint $c.value.fingerprint
        if (-not $k.ok) { throw ("confirm refused: " + $k.reason) }
    }
    return $c.value.device.id
}

function New-HordeTestPhoneVouch {
    # The passkey's vouch for the phone identity key in -Horde (relay/Trust.ps1, PHONE KEYS).
    param($Phone, [string]$Horde)
    return (New-HordeTestPhoneAssertion -Phone $Phone -Challenge (Get-HordeRelayPhoneKeyChallenge -Horde $Horde -AgreePublic (ConvertTo-HordeRelayBase64Url -Bytes $Phone.agreePublic)))
}

function New-HordeTestPhoneEnvelope {
    # An envelope from the phone: -Body sealed to -To (65-byte agreement keys), signed with the passkey.
    # -Seq picks the sequence number; without it the phone's next on that channel. -From signs as
    # another key id than the passkey's (a forgery). { text; key; header }.
    param($Phone, [string]$Kind, [string]$Channel, [byte[]]$Body, [object[]]$To, [long]$Seq = -1, [string]$From = "")
    if ($Seq -lt 0) {
        if (-not $Phone.seq.ContainsKey($Channel)) { $Phone.seq[$Channel] = [long]0 }
        $Phone.seq[$Channel] = [long]$Phone.seq[$Channel] + 1
        $Seq = $Phone.seq[$Channel]
    }
    $who = $(if ($From -cne "") { $From } else { $Phone.keyId })
    $draft = New-HordeRelayEnvelopeDraft -Kind $Kind -Channel $Channel -From $who -Seq $Seq -Body $Body -Recipients $To
    $a = New-HordeTestPhoneAssertion -Phone $Phone -Challenge $draft.challenge
    $text = Complete-HordeRelayEnvelope -Draft $draft -AuthenticatorData $a.authenticatorData -ClientDataJson $a.clientDataJson -Signature $a.signature
    return [pscustomobject]@{ text = $text; key = (Get-HordeRelayReplayKey -Header $draft.header); header = $draft.header; draft = $draft }
}

function New-HordeTestPhoneResigned {
    # The same signed content signed again, by a new assertion: a second text of one envelope.
    param($Phone, $Envelope)
    $a = New-HordeTestPhoneAssertion -Phone $Phone -Challenge $Envelope.draft.challenge
    return (Complete-HordeRelayEnvelope -Draft $Envelope.draft -AuthenticatorData $a.authenticatorData -ClientDataJson $a.clientDataJson -Signature $a.signature)
}

function New-HordeTestPhoneKeyBody {
    # The trust channel's phone-key body (channels/trust/Channel.ps1), with a vouch by the passkey.
    param($Phone, [string]$Horde, $Vouch = $null)
    if ($null -eq $Vouch) { $Vouch = New-HordeTestPhoneVouch -Phone $Phone -Horde $Horde }
    $t = '{"v":1,"agreePublic":"' + (ConvertTo-HordeRelayBase64Url -Bytes $Phone.agreePublic) + '","authenticatorData":"' + (ConvertTo-HordeRelayBase64Url -Bytes $Vouch.authenticatorData) +
        '","clientDataJSON":"' + (ConvertTo-HordeRelayBase64Url -Bytes $Vouch.clientDataJson) + '","signature":"' + (ConvertTo-HordeRelayBase64Url -Bytes $Vouch.signature) + '"}'
    return ,($script:HordeTestPhoneUtf8.GetBytes($t))
}

function New-HordeTestPhoneAnswerBody {
    # The decisions channel's answer body (channels/decisions/Channel.ps1).
    param([string]$AnswerId = "", [int]$Number = 1, [int]$Wording = 1, [string]$Text = "Yes, play it.")
    if ($AnswerId -ceq "") { $AnswerId = [guid]::NewGuid().ToString("N") }
    $t = ConvertTo-Json -InputObject ([ordered]@{ v = 1; answerId = $AnswerId; number = $Number; wordingVersion = $Wording; text = $Text }) -Compress
    return ,($script:HordeTestPhoneUtf8.GetBytes($t))
}

function Open-HordeTestPhoneEnvelope {
    # What the phone does with an envelope from the machine: verify it against the machine's signing key
    # and open it with the phone identity key. { ok; reason; body (parsed JSON) }. The phone keeps no
    # journal in this suite, so the verdict is the phone's own: this envelope, fresh.
    param($Phone, [string]$Text, [byte[]]$MachineSignPublic)
    $r = Read-HordeRelayEnvelope -Text $Text
    if (-not $r.ok) { return [pscustomobject]@{ ok = $false; reason = $r.reason; body = $null } }
    $machine = New-HordeRelaySender -Public $MachineSignPublic -Proof "es256"
    $verdict = New-HordeKnown -Value ([pscustomobject]@{ key = (Get-HordeRelayReplayKey -Header $r.value.header); fresh = $true })
    $o = Unprotect-HordeRelayEnvelope -Envelope $r.value -Senders @{ ($machine.keyId) = $machine } -RecipientKeys @{ (Get-HordeRelayKeyId -Public $Phone.agreePublic) = $Phone.agree } -Replay $verdict -Channel $r.value.header.channel -Kind $r.value.header.kind
    if (-not $o.ok) { return [pscustomobject]@{ ok = $false; reason = $o.reason; body = $null } }
    return [pscustomobject]@{ ok = $true; reason = ""; body = ($script:HordeTestPhoneUtf8.GetString($o.value) | ConvertFrom-Json); header = $r.value.header }
}
