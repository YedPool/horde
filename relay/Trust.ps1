# relay/Trust.ps1 - who this machine believes: the founder's devices (passkeys) and the peer machines
# of its own horde. Added once, confirmed once, revoked once - never edited, never deleted.
#
# WHERE: <HORDE_HOME>\relay\trust\ (relay/Records.ps1, write-once):
#   devices\<id>.json       an enrolled founder device. id is the first 16 bytes of SHA-256 of the
#                           credential id, as hex: a credential id is up to 1023 bytes of anything, so
#                           it is never a file name itself.
#   machines\<keyId>.json   a peer machine of the same horde, by its signing key id, with its card.
#   confirmed\device-<id>.json
#                           the founder confirmed this device at the machine, by its fingerprint.
#   confirmed\machine-<keyId>.json
#                           a trusted founder passkey countersigned this peer's card.
#   phones\<agreeKeyId>-<by>.json
#                           a vouch for a phone identity key - the agreement key a phone opens what is
#                           sealed to it with (relay design, Q7) - by the founder passkey whose key id is
#                           <by> (PHONE KEYS, below). One key may have several.
#   revoked\device-<id>.json, revoked\machine-<keyId>.json
#                           the end of an entry: when, and why. Revocation is a record BESIDE the entry,
#                           never its deletion, so the trust store keeps its own history and a revoked
#                           key can never come back by being added again - a new key is a new entry.
#
# NOTHING IS TRUSTED ON ARRIVAL (founder decisions of 2026-10-09):
#   A DEVICE is enrolled through pairing (relay/Pairing.ps1) as PENDING: its registration verified, its
#   key on the curve, but not trusted. It becomes TRUSTED only when the founder confirms it at the
#   machine with the fingerprint both screens show (Confirm-HordeRelayDevice), before pendingUntil - the
#   end of its confirm window, counted from its registration. Past that, unconfirmed, it is EXPIRED,
#   for good. A pending device can be
#   rejected at any time by revoking it.
#   A PEER MACHINE is added from its self-signed card (relay/Identity.ps1, Read-HordeRelayMachineCard):
#   the card proves its maker holds the signing key, names this horde, and is not this machine - and
#   that is only PENDING. It is TRUSTED once a TRUSTED founder passkey has signed a WebAuthn assertion
#   over the card (challenge Get-HordeRelayCardChallenge), and only while that passkey stays trusted:
#   revoking the passkey that vouched for a peer puts the peer back to pending, because a stolen phone
#   may have countersigned a machine of the thief's.
# A device keeps: its key, credential id, relying party and origins, whether the phone said PRF works
# with it (prf: the client's own report, which nothing signs - a hint for the phone-key wrap of a later
# pull request, never a trust decision), hmac-secret, backup eligibility, its label, when and through
# which offer it was enrolled, its fingerprint and pendingUntil.
#
# PHONE KEYS (relay PR 6, the decisions channel). A passkey signs; it cannot open anything sealed to it.
# So what the machines seal for the founder - the decisions snapshot - goes to a separate PHONE IDENTITY
# KEY (design Q7), an agreement key the phone makes and keeps. It is added from a VOUCH: a WebAuthn
# assertion (UV) by a founder passkey over Get-HordeRelayPhoneKeyChallenge - SHA-256 of a domain, the
# horde and the key - so a key nobody vouched for is never sealed to, and a vouch for one horde is
# useless in another. A phone key is TRUSTED while ONE of its vouches is by a passkey that is trusted,
# made in the horde this home belongs to NOW: revoking the passkey (a lost phone) stops every key only it
# vouched for, as it does a countersigned peer; renaming the home's horde stops every key vouched for in
# the old one (review of 48bc492, finding 8: the horde was checked only when a key was added).
# A KEY CAN BE VOUCHED FOR AGAIN (finding 7). The founder who replaces the passkey on his phone vouches
# for the same phone key with the new one: that is a second record beside the first, write-once like
# every record here, and the key is trusted again. A vouch is never answered "already there" unless the
# key IS trusted by that very vouch.
# A phone key has no revocation of its own yet: rotating the phone key is the PWA's later pull request.
#
# THE VOUCH TRAVELS BY ITSELF (the founder, 2026-10-14: "that piece should happen automatically on
# login - I don't see why I should press a button"). An iPhone starts a passkey prompt only from a tap,
# one prompt a tap, so the announcement must cost ONE assertion, and ride a prompt the phone shows
# anyway: the unlock, or the one "Finish pairing" tap. The vouch is that assertion - its challenge is
# Get-HordeRelayPhoneKeyChallenge, fixed for a horde and a key, so the unlock's PRF get() can carry it
# - and it needs no envelope around it: it is a public statement (a public key, a public signature),
# it is verified under a TRUSTED device's key on arrival and again on every read, and adding it twice is
# the same record. So the phone puts it into the machine's mailbox as a PHONE VOUCH ITEM, kind
# horde-relay-phone-vouch (Get-HordeRelayPhoneVouchSpec): horde, by (the passkey's key id), agreePublic,
# and the assertion. Receive-HordeRelayPhoneVouch takes it in (channels/Port.ps1 hands it over before it
# reads an envelope). WHY NOT ONE ASSERTION OVER BOTH THE ENVELOPE AND THE VOUCH: an envelope's
# signature is over its own bytes (seq, nonce, ciphertext) and the stored vouch must verify by itself
# forever after the envelope is gone; one challenge cannot be both without changing what
# relay/Envelope.ps1 verifies and what every stored phone record means. An envelope signed by the
# passkey still takes a vouch in (channels/trust): an older phone keeps working.
# NOTHING IS TRUSTED THAT WAS NOT BEFORE: a vouch item by a pending, expired, revoked or unknown
# device, for another horde, by another key than it names, or with no signature, is refused and changes
# nothing; the phone sends it again only at its next unlock, never in a loop.
# Each vouch is kept in its record and verified again on every read, like a countersignature.
#
# EVERY READ RE-CHECKS EVERY RECORD: canonical form, key ids that are their keys', public keys that are
# points on P-256, file names that are their records' ids, a peer's card that still verifies and still
# says what its record says, every countersignature verified again, and confirmations and revocations
# that name an entry that exists. ANY damage makes the whole store unknown, not just the entry: a
# revocation that cannot be read cannot be honoured, so nothing is trusted until a person repairs it.
# Each entry is answered with its state: pending, trusted, expired (devices) or revoked.
# Find-HordeRelayTrustedSenders answers the hashtable relay/Envelope.ps1 verifies against: TRUSTED
# entries only.
#
# Answers are core/tristate.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")
. (Join-Path $PSScriptRoot "Bytes.ps1")
. (Join-Path $PSScriptRoot "P256.ps1")
. (Join-Path $PSScriptRoot "Records.ps1")
. (Join-Path $PSScriptRoot "Identity.ps1")
. (Join-Path $PSScriptRoot "WebAuthn.ps1")
. (Join-Path $PSScriptRoot "Envelope.ps1")

function Get-HordeRelayDeviceSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "id", "hex32", "horde", "name", "label", "label", "credentialId", "b64u",
        "publicKey", "point", "keyId", "hex32", "rpId", "rpid", "origins", "origins", "prf", "bool", "hmacSecret", "bool", "backupEligible", "bool",
        "aaguid", "hex", "offer", "hex32", "enrolledAt", "int", "fingerprint", "name", "pendingUntil", "int"))
}

function Get-HordeRelayPeerSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "keyId", "hex32", "horde", "name", "label", "label", "generation", "int",
        "signPublic", "point", "agreeKeyId", "hex32", "agreePublic", "point", "mailbox", "mailbox", "addedAt", "int", "card", "b64u"))
}

function Get-HordeRelayRevocationSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "subject", "name", "id", "hex32", "keyId", "hex32", "reason", "text", "revokedAt", "int"))
}

function Get-HordeRelayDeviceConfirmedSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "id", "hex32", "keyId", "hex32", "fingerprint", "name", "confirmedAt", "int"))
}

function Get-HordeRelayCountersignSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "keyId", "hex32", "by", "hex32", "authenticatorData", "b64u",
        "clientDataJSON", "b64u", "signature", "b64u", "countersignedAt", "int"))
}

function Get-HordeRelayPhoneKeySpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "agreeKeyId", "hex32", "horde", "name", "agreePublic", "point", "by", "hex32",
        "authenticatorData", "b64u", "clientDataJSON", "b64u", "signature", "b64u", "addedAt", "int"))
}

function Get-HordeRelayPhoneKeyChallenge {
    # What a founder passkey signs to vouch for a phone identity key: SHA-256 of the domain, the horde
    # and the key's base64url, each on its own line.
    param([Parameter(Mandatory = $true)][string]$Horde, [Parameter(Mandatory = $true)][string]$AgreePublic)
    return ,(Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text ("horde-relay/phone-key/v1 vouch`n" + $Horde + "`n" + $AgreePublic)))
}

function Test-HordeRelayPhoneKeyVouch {
    # Does a phone key record's vouch verify: an assertion by Device's key over the key's challenge, for
    # its relying party and origins, user verified? The WebAuthn answer.
    param($Phone, $Device)
    return (Test-HordeRelayWebAuthnAssertion -Public (ConvertFrom-HordeRelayBase64Url -Text $Device.publicKey) `
        -AuthenticatorData (ConvertFrom-HordeRelayBase64Url -Text $Phone.authenticatorData) -ClientDataJson (ConvertFrom-HordeRelayBase64Url -Text $Phone.clientDataJSON) `
        -Signature (ConvertFrom-HordeRelayBase64Url -Text $Phone.signature) -Challenge (Get-HordeRelayPhoneKeyChallenge -Horde $Phone.horde -AgreePublic $Phone.agreePublic) `
        -RpId $Device.rpId -Origins @($Device.origins) -RequireUserVerification $true)
}

function Get-HordeRelayDeviceId {
    # The id a device entry is filed under: the first 16 bytes of SHA-256(credential id), as hex.
    param([Parameter(Mandatory = $true)][byte[]]$CredentialId)
    $h = Get-HordeRelaySha256 -Bytes $CredentialId
    $first = New-Object byte[] 16
    [System.Array]::Copy($h, 0, $first, 0, 16)
    return (ConvertTo-HordeRelayHex -Bytes $first)
}

function Get-HordeRelayCardChallenge {
    # What a founder passkey signs to countersign a peer's card: SHA-256 of the domain and the card's
    # exact text.
    param([Parameter(Mandatory = $true)][string]$Card)
    return ,(Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text ("horde-relay/machine-card/v1 countersign`n" + $Card)))
}

function Read-HordeRelayTrustFolder {
    # Every record in one folder of the store, read with Spec: { ok; reason; records }.
    param([string]$Dir, [string]$Pattern, [object[]]$Spec, [string]$Kind)
    $list = Get-HordeRelayRecordNames -Dir $Dir -Pattern $Pattern
    if (-not $list.ok) { return [pscustomobject]@{ ok = $false; reason = $list.reason; records = @() } }
    $out = New-Object System.Collections.ArrayList
    foreach ($n in @($list.names)) {
        $f = Read-HordeRelayRecordFile -Path ([System.IO.Path]::Combine($Dir, $n))
        if (-not $f.ok) { return [pscustomobject]@{ ok = $false; reason = $f.reason; records = @() } }
        $r = Read-HordeRelayRecordText -Text $f.text -Spec $Spec -Kind $Kind -What ("the trust record " + $n)
        if (-not $r.ok) { return [pscustomobject]@{ ok = $false; reason = $r.reason; records = @() } }
        [void]$out.Add([pscustomobject]@{ file = $n; record = $r.value })
    }
    return [pscustomobject]@{ ok = $true; reason = ""; records = @($out.ToArray()) }
}

function Test-HordeRelayCountersign {
    # Does a countersignature record verify: an assertion by Device's key over Card's challenge, for its
    # relying party and origins, user verified? The WebAuthn answer.
    param($Countersign, $Device, [string]$Card)
    return (Test-HordeRelayWebAuthnAssertion -Public (ConvertFrom-HordeRelayBase64Url -Text $Device.publicKey) `
        -AuthenticatorData (ConvertFrom-HordeRelayBase64Url -Text $Countersign.authenticatorData) -ClientDataJson (ConvertFrom-HordeRelayBase64Url -Text $Countersign.clientDataJSON) `
        -Signature (ConvertFrom-HordeRelayBase64Url -Text $Countersign.signature) -Challenge (Get-HordeRelayCardChallenge -Card $Card) `
        -RpId $Device.rpId -Origins @($Device.origins) -RequireUserVerification $true)
}

function Read-HordeRelayTrustStore {
    # The whole store, checked (the header): { ok; reason; devices; machines; revoked }. Each device has
    # revoked, confirmed and state added; each machine has revoked, countersign, cardText, state and
    # why. State is judged at -Now (a pending device expires).
    param([string]$HordeHome, $Now = $null)
    $fail = [pscustomobject]@{ ok = $false; reason = ""; devices = @(); machines = @(); revoked = @(); phones = @() }
    try { $root = Get-HordeRelayStateDir -HordeHome $HordeHome -Part "trust" } catch { $fail.reason = $_.Exception.Message; return $fail }
    $nowMs = ConvertTo-HordeRelayRecordMs -Time $Now
    $devs = Read-HordeRelayTrustFolder -Dir ([System.IO.Path]::Combine($root, "devices")) -Pattern '\A[0-9a-f]{32}\.json\z' -Spec (Get-HordeRelayDeviceSpec) -Kind "horde-relay-device"
    if (-not $devs.ok) { $fail.reason = $devs.reason; return $fail }
    $peers = Read-HordeRelayTrustFolder -Dir ([System.IO.Path]::Combine($root, "machines")) -Pattern '\A[0-9a-f]{32}\.json\z' -Spec (Get-HordeRelayPeerSpec) -Kind "horde-relay-peer"
    if (-not $peers.ok) { $fail.reason = $peers.reason; return $fail }
    $phs = Read-HordeRelayTrustFolder -Dir ([System.IO.Path]::Combine($root, "phones")) -Pattern '\A[0-9a-f]{32}-[0-9a-f]{32}\.json\z' -Spec (Get-HordeRelayPhoneKeySpec) -Kind "horde-relay-phone-key"
    if (-not $phs.ok) { $fail.reason = $phs.reason; return $fail }
    $revs = Read-HordeRelayTrustFolder -Dir ([System.IO.Path]::Combine($root, "revoked")) -Pattern '\A(device|machine)-[0-9a-f]{32}\.json\z' -Spec (Get-HordeRelayRevocationSpec) -Kind "horde-relay-revocation"
    if (-not $revs.ok) { $fail.reason = $revs.reason; return $fail }
    $confDir = [System.IO.Path]::Combine($root, "confirmed")
    # The confirmed folder holds two kinds; each name is read with its own spec.
    $names = Get-HordeRelayRecordNames -Dir $confDir -Pattern '\A(device|machine)-[0-9a-f]{32}\.json\z'
    if (-not $names.ok) { $fail.reason = $names.reason; return $fail }
    $confBy = @{}
    $csBy = @{}
    foreach ($n in @($names.names)) {
        $f = Read-HordeRelayRecordFile -Path ([System.IO.Path]::Combine($confDir, $n))
        if (-not $f.ok) { $fail.reason = $f.reason; return $fail }
        if ($n.StartsWith("device-")) {
            $r = Read-HordeRelayRecordText -Text $f.text -Spec (Get-HordeRelayDeviceConfirmedSpec) -Kind "horde-relay-device-confirmed" -What ("the trust record " + $n)
            if (-not $r.ok) { $fail.reason = $r.reason; return $fail }
            if ($n -cne ("device-" + $r.value.id + ".json")) { $fail.reason = ("the confirmation " + $n + " is filed under another id than its own"); return $fail }
            $confBy[$r.value.id] = $r.value
        } else {
            $r = Read-HordeRelayRecordText -Text $f.text -Spec (Get-HordeRelayCountersignSpec) -Kind "horde-relay-peer-countersigned" -What ("the trust record " + $n)
            if (-not $r.ok) { $fail.reason = $r.reason; return $fail }
            if ($n -cne ("machine-" + $r.value.keyId + ".json")) { $fail.reason = ("the countersignature " + $n + " is filed under another key id than its own"); return $fail }
            $csBy[$r.value.keyId] = $r.value
        }
    }
    $byKey = @{}
    foreach ($d in @($devs.records)) {
        $r = $d.record
        if ($d.file -cne ($r.id + ".json")) { $fail.reason = ("the device record " + $d.file + " is filed under another id than its own"); return $fail }
        if ($r.id -cne (Get-HordeRelayDeviceId -CredentialId (ConvertFrom-HordeRelayBase64Url -Text $r.credentialId))) { $fail.reason = ("the device record " + $d.file + " has an id that is not its credential's"); return $fail }
        if ($r.keyId -cne (Get-HordeRelayKeyId -Public (ConvertFrom-HordeRelayBase64Url -Text $r.publicKey))) { $fail.reason = ("the device record " + $d.file + " names a key id that is not its key's"); return $fail }
        $byKey[$r.keyId] = "device-" + $r.id
    }
    foreach ($m in @($peers.records)) {
        $r = $m.record
        if ($m.file -cne ($r.keyId + ".json")) { $fail.reason = ("the machine record " + $m.file + " is filed under another key id than its own"); return $fail }
        if ($byKey.ContainsKey($r.keyId)) { $fail.reason = ("the key " + $r.keyId + " is in the store twice"); return $fail }
        $cardText = [System.Text.Encoding]::ASCII.GetString((ConvertFrom-HordeRelayBase64Url -Text $r.card))
        $card = Read-HordeRelayMachineCard -Text $cardText
        if (-not $card.ok) { $fail.reason = ("the machine record " + $m.file + " holds a card that is refused: " + $card.reason); return $fail }
        $c = $card.value
        if ($c.signKeyId -cne $r.keyId -or $c.horde -cne $r.horde -or $c.label -cne $r.label -or $c.generation -ne $r.generation -or $c.signPublic -cne $r.signPublic -or
            $c.agreeKeyId -cne $r.agreeKeyId -or $c.agreePublic -cne $r.agreePublic -or $c.mailbox -cne $r.mailbox) { $fail.reason = ("the machine record " + $m.file + " says other than its own card"); return $fail }
        $byKey[$r.keyId] = "machine-" + $r.keyId
        $r | Add-Member -NotePropertyName "cardText" -NotePropertyValue $cardText
    }
    $revBy = @{}
    foreach ($v in @($revs.records)) {
        $r = $v.record
        $subjectFile = $r.subject + "-" + $r.id
        if ($v.file -cne ($subjectFile + ".json")) { $fail.reason = ("the revocation " + $v.file + " is filed under another subject than its own"); return $fail }
        $target = $null
        if ($r.subject -ceq "device") { $target = @($devs.records | Where-Object { $_.record.id -ceq $r.id }) | Select-Object -First 1 }
        elseif ($r.subject -ceq "machine") { $target = @($peers.records | Where-Object { $_.record.keyId -ceq $r.id }) | Select-Object -First 1 }
        if ($null -eq $target) { $fail.reason = ("the revocation " + $v.file + " revokes an entry the store does not hold"); return $fail }
        if ($target.record.keyId -cne $r.keyId) { $fail.reason = ("the revocation " + $v.file + " names another key than its entry's"); return $fail }
        $revBy[$subjectFile] = $r
    }
    $devOut = New-Object System.Collections.ArrayList
    foreach ($d in @($devs.records)) {
        $r = $d.record
        $conf = $null
        if ($confBy.ContainsKey($r.id)) {
            $conf = $confBy[$r.id]
            if ($conf.keyId -cne $r.keyId -or $conf.fingerprint -cne $r.fingerprint) { $fail.reason = ("the confirmation of device " + $r.id + " names another key or fingerprint than the device's"); return $fail }
        }
        $rev = $revBy[("device-" + $r.id)]
        $state = "trusted"
        if ($null -ne $rev) { $state = "revoked" }
        elseif ($null -eq $conf) { $state = $(if ($nowMs -le $r.pendingUntil) { "pending" } else { "expired" }) }
        $r | Add-Member -NotePropertyName "revoked" -NotePropertyValue $rev
        $r | Add-Member -NotePropertyName "confirmed" -NotePropertyValue $conf
        $r | Add-Member -NotePropertyName "state" -NotePropertyValue $state
        [void]$devOut.Add($r)
    }
    foreach ($k in @($confBy.Keys)) {
        if (@($devOut | Where-Object { $_.id -ceq $k }).Count -ne 1) { $fail.reason = ("the confirmation of device " + $k + " confirms a device the store does not hold"); return $fail }
    }
    $peerOut = New-Object System.Collections.ArrayList
    foreach ($m in @($peers.records)) {
        $r = $m.record
        $rev = $revBy[("machine-" + $r.keyId)]
        $cs = $null
        $state = "pending"
        $why = "a self-signed card alone: it waits for a trusted founder passkey to countersign it"
        if ($csBy.ContainsKey($r.keyId)) {
            $cs = $csBy[$r.keyId]
            $by = @($devOut | Where-Object { $_.keyId -ceq $cs.by }) | Select-Object -First 1
            if ($null -eq $by) { $fail.reason = ("the countersignature of machine " + $r.keyId + " names a passkey the store does not hold"); return $fail }
            $check = Test-HordeRelayCountersign -Countersign $cs -Device $by -Card $r.cardText
            if (-not $check.ok) { $fail.reason = ("the countersignature of machine " + $r.keyId + " does not verify: " + $check.reason); return $fail }
            if ($by.state -ceq "trusted") { $state = "trusted"; $why = "" }
            else { $why = ("the passkey that countersigned it (" + $by.label + ") is " + $by.state + " now, so it waits for another countersignature") }
        }
        if ($null -ne $rev) { $state = "revoked"; $why = "" }
        $r | Add-Member -NotePropertyName "revoked" -NotePropertyValue $rev
        $r | Add-Member -NotePropertyName "countersign" -NotePropertyValue $cs
        $r | Add-Member -NotePropertyName "state" -NotePropertyValue $state
        $r | Add-Member -NotePropertyName "why" -NotePropertyValue $why
        [void]$peerOut.Add($r)
    }
    foreach ($k in @($csBy.Keys)) {
        if (@($peerOut | Where-Object { $_.keyId -ceq $k }).Count -ne 1) { $fail.reason = ("the countersignature of machine " + $k + " vouches for a machine the store does not hold"); return $fail }
    }
    $phoneOut = New-Object System.Collections.ArrayList
    # The horde the home belongs to now (finding 8). Unnamed or refused, no phone key is trusted.
    $nowHorde = Get-HordeRelayHorde -HordeHome $HordeHome
    foreach ($p in @($phs.records)) {
        $r = $p.record
        if ($p.file -cne ($r.agreeKeyId + "-" + $r.by + ".json")) { $fail.reason = ("the phone key record " + $p.file + " is filed under another key id than its own"); return $fail }
        if ($r.agreeKeyId -cne (Get-HordeRelayKeyId -Public (ConvertFrom-HordeRelayBase64Url -Text $r.agreePublic))) { $fail.reason = ("the phone key record " + $p.file + " names a key id that is not its key's"); return $fail }
        if ($byKey.ContainsKey($r.agreeKeyId)) { $fail.reason = ("the key " + $r.agreeKeyId + " is in the store twice"); return $fail }
        $by = @($devOut | Where-Object { $_.keyId -ceq $r.by }) | Select-Object -First 1
        if ($null -eq $by) { $fail.reason = ("the phone key " + $r.agreeKeyId + " is vouched for by a passkey the store does not hold"); return $fail }
        $check = Test-HordeRelayPhoneKeyVouch -Phone $r -Device $by
        if (-not $check.ok) { $fail.reason = ("the vouch for the phone key " + $r.agreeKeyId + " does not verify: " + $check.reason); return $fail }
        $state = "trusted"
        $why = ""
        if ($by.state -cne "trusted") { $state = "untrusted"; $why = ("the passkey that vouched for it (" + $by.label + ") is " + $by.state) }
        elseif ($nowHorde.state -cne "known" -or $nowHorde.value -cne $r.horde) { $state = "untrusted"; $why = ("it was vouched for in the horde '" + $r.horde + "', and this home belongs to " + $(if ($nowHorde.state -ceq "known") { "'" + $nowHorde.value + "'" } else { "no horde now" })) }
        $r | Add-Member -NotePropertyName "state" -NotePropertyValue $state
        $r | Add-Member -NotePropertyName "why" -NotePropertyValue $why
        [void]$phoneOut.Add($r)
    }
    return [pscustomobject]@{ ok = $true; reason = ""; devices = @($devOut.ToArray()); machines = @($peerOut.ToArray()); revoked = @(@($revs.records) | ForEach-Object { $_.record }); phones = @($phoneOut.ToArray()) }
}

function Get-HordeRelayTrust {
    # The store, for whoever shows it: known { devices; machines; revoked }, every entry with its state
    # at -Now; unknown when the store is damaged.
    param([string]$HordeHome = "", $Now = $null)
    $s = Read-HordeRelayTrustStore -HordeHome $HordeHome -Now $Now
    if (-not $s.ok) { return (New-HordeUnknown -Reason $s.reason) }
    return (New-HordeKnown -Value ([pscustomobject]@{ devices = @($s.devices); machines = @($s.machines); revoked = @($s.revoked); phones = @($s.phones) }))
}

function Write-HordeRelayTrustRecord {
    # Write one record under trust\<Folder>\<Name>; "moved", "exists" or "unconfirmed", or a throw.
    param([string]$HordeHome, [string]$Folder, [string]$Name, [object[]]$Spec, [hashtable]$Values)
    $text = ConvertTo-HordeRelayRecordText -Spec $Spec -Values $Values
    return (Write-HordeRelayRecordFile -Dir ([System.IO.Path]::Combine((Get-HordeRelayStateDir -HordeHome $HordeHome -Part "trust"), $Folder)) -Name $Name -Text $text)
}

function Add-HordeRelayPendingDevice {
    # Enroll a founder device from a VERIFIED registration (Test-HordeRelayWebAuthnRegistration's
    # answer, ok), as PENDING until PendingUntil. Pairing is its one caller: a registration only means
    # something over an offer's challenge. Known (the device record, state pending); unknown when the
    # store is damaged, the credential was ever enrolled or revoked, or the record could not be written.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)]$Registration, [Parameter(Mandatory = $true)][string]$Horde,
        [Parameter(Mandatory = $true)][string]$RpId, [Parameter(Mandatory = $true)][string[]]$Origins, [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][bool]$Prf, [Parameter(Mandatory = $true)][string]$OfferId, [Parameter(Mandatory = $true)][string]$Fingerprint,
        [Parameter(Mandatory = $true)][long]$PendingUntil, $Now = $null)
    if (-not $Registration.ok) { return (New-HordeUnknown -Reason "only a verified registration is enrolled") }
    $s = Read-HordeRelayTrustStore -HordeHome $HordeHome -Now $Now
    if (-not $s.ok) { return (New-HordeUnknown -Reason ($s.reason + "; nothing is enrolled until it is repaired")) }
    $id = Get-HordeRelayDeviceId -CredentialId $Registration.credentialId
    $keyId = Get-HordeRelayKeyId -Public $Registration.public
    $prior = @($s.devices | Where-Object { $_.id -ceq $id -or $_.keyId -ceq $keyId })
    if ($prior.Count -gt 0) {
        if ($null -ne $prior[0].revoked) { return (New-HordeUnknown -Reason ("this credential (" + $id + ") was revoked at " + $prior[0].revoked.revokedAt + " and is never enrolled again; make a new passkey")) }
        return (New-HordeUnknown -Reason ("this credential (" + $id + ") is already enrolled as '" + $prior[0].label + "' (" + $prior[0].state + ")"))
    }
    if (@($s.machines | Where-Object { $_.keyId -ceq $keyId }).Count -gt 0) { return (New-HordeUnknown -Reason "this key is a peer machine's, not a device's") }
    $values = @{
        v = 1; kind = "horde-relay-device"; id = $id; horde = $Horde; label = $Label; credentialId = (ConvertTo-HordeRelayBase64Url -Bytes $Registration.credentialId)
        publicKey = (ConvertTo-HordeRelayBase64Url -Bytes $Registration.public); keyId = $keyId; rpId = $RpId; origins = @($Origins)
        prf = $Prf; hmacSecret = [bool]$Registration.hmacSecret; backupEligible = [bool]$Registration.backupEligible; aaguid = $Registration.aaguid
        offer = $OfferId; enrolledAt = (ConvertTo-HordeRelayRecordMs -Time $Now); fingerprint = $Fingerprint; pendingUntil = $PendingUntil
    }
    try { $moved = Write-HordeRelayTrustRecord -HordeHome $HordeHome -Folder "devices" -Name ($id + ".json") -Spec (Get-HordeRelayDeviceSpec) -Values $values }
    catch { return (New-HordeUnknown -Reason "the device could not be enrolled" -ErrorRecord $_) }
    if ($moved -ceq "exists") { return (New-HordeUnknown -Reason ("this credential (" + $id + ") was enrolled by another process at the same moment")) }
    if ($moved -cne "moved") { return (New-HordeUnknown -Reason ("the device record " + $id + " has its name, but nothing says it reached the disk")) }
    $rec = [pscustomobject]$values
    $rec | Add-Member -NotePropertyName "revoked" -NotePropertyValue $null
    $rec | Add-Member -NotePropertyName "confirmed" -NotePropertyValue $null
    $rec | Add-Member -NotePropertyName "state" -NotePropertyValue "pending"
    return (New-HordeKnown -Value $rec)
}

function Add-HordeRelayDeviceConfirmation {
    # Record that the founder confirmed a PENDING device at the machine. The caller has checked the
    # fingerprint (relay/Pairing.ps1, Confirm-HordeRelayDevice); this checks the state at -Now. Known
    # { device; already }; unknown when the device is not pending (expired, revoked) or the store is
    # damaged; absent when the store holds no such device.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$Id, $Now = $null)
    $s = Read-HordeRelayTrustStore -HordeHome $HordeHome -Now $Now
    if (-not $s.ok) { return (New-HordeUnknown -Reason ($s.reason + "; nothing is confirmed until it is repaired")) }
    $d = @($s.devices | Where-Object { $_.id -ceq $Id }) | Select-Object -First 1
    if ($null -eq $d) { return (New-HordeAbsent -Note ("the trust store holds no device " + $Id)) }
    if ($d.state -ceq "trusted") { return (New-HordeKnown -Value ([pscustomobject]@{ device = $d; already = $true })) }
    if ($d.state -ceq "revoked") { return (New-HordeUnknown -Reason ("the device " + $Id + " was revoked (rejected) and is never confirmed")) }
    if ($d.state -cne "pending") { return (New-HordeUnknown -Reason ("the device " + $Id + " expired unconfirmed at " + $d.pendingUntil + "; pair again with a new passkey")) }
    $values = @{ v = 1; kind = "horde-relay-device-confirmed"; id = $d.id; keyId = $d.keyId; fingerprint = $d.fingerprint; confirmedAt = (ConvertTo-HordeRelayRecordMs -Time $Now) }
    try { $moved = Write-HordeRelayTrustRecord -HordeHome $HordeHome -Folder "confirmed" -Name ("device-" + $d.id + ".json") -Spec (Get-HordeRelayDeviceConfirmedSpec) -Values $values }
    catch { return (New-HordeUnknown -Reason "the confirmation could not be written" -ErrorRecord $_) }
    if ($moved -cne "moved" -and $moved -cne "exists") { return (New-HordeUnknown -Reason ("the confirmation of " + $Id + " has its name, but nothing says it reached the disk")) }
    $again = Read-HordeRelayTrustStore -HordeHome $HordeHome -Now $Now
    if (-not $again.ok) { return (New-HordeUnknown -Reason $again.reason) }
    return (New-HordeKnown -Value ([pscustomobject]@{ device = (@($again.devices | Where-Object { $_.id -ceq $Id }) | Select-Object -First 1); already = ($moved -ceq "exists") }))
}

function Add-HordeRelayPeerMachine {
    # Add a peer machine of this horde from its card, PENDING until a trusted founder passkey
    # countersigns it. Known { record; duplicate } - adding the same card's keys again is duplicate,
    # not an error; unknown when the card is refused, names another horde or this machine, the key was
    # ever revoked, or the store is damaged.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Card, $Now = $null)
    $c = Read-HordeRelayMachineCard -Text $Card
    if (-not $c.ok) { return (New-HordeUnknown -Reason ("the machine card is refused: " + $c.reason)) }
    $horde = Get-HordeRelayHorde -HordeHome $HordeHome
    if ($horde.state -cne "known") { return (New-HordeUnknown -Reason ("this machine's horde is not named, so no peer can be checked against it: " + $horde.reason)) }
    if ($c.value.horde -cne $horde.value) { return (New-HordeUnknown -Reason ("the card is from the horde '" + $c.value.horde + "', and this machine belongs to '" + $horde.value + "'")) }
    $me = Get-HordeRelayMachineIdentity -HordeHome $HordeHome
    if ($me.state -ceq "known" -and ($me.value.sign.keyId -ceq $c.value.signKeyId -or $me.value.agree.keyId -ceq $c.value.agreeKeyId)) { return (New-HordeUnknown -Reason "the card is this machine's own") }
    $s = Read-HordeRelayTrustStore -HordeHome $HordeHome -Now $Now
    if (-not $s.ok) { return (New-HordeUnknown -Reason ($s.reason + "; nothing is added until it is repaired")) }
    if (@($s.devices | Where-Object { $_.keyId -ceq $c.value.signKeyId }).Count -gt 0) { return (New-HordeUnknown -Reason "this key is an enrolled device's, not a machine's") }
    $prior = @($s.machines | Where-Object { $_.keyId -ceq $c.value.signKeyId }) | Select-Object -First 1
    if ($null -ne $prior) {
        if ($null -ne $prior.revoked) { return (New-HordeUnknown -Reason ("the machine " + $prior.keyId + " was revoked at " + $prior.revoked.revokedAt + " and is never trusted again; a rotated machine has a new key")) }
        if ($prior.agreePublic -ceq $c.value.agreePublic -and $prior.signPublic -ceq $c.value.signPublic) { return (New-HordeKnown -Value ([pscustomobject]@{ record = $prior; duplicate = $true })) }
        return (New-HordeUnknown -Reason ("the machine " + $prior.keyId + " is already in the store with another agreement key"))
    }
    $values = @{
        v = 1; kind = "horde-relay-peer"; keyId = $c.value.signKeyId; horde = $c.value.horde; label = $c.value.label; generation = $c.value.generation
        signPublic = $c.value.signPublic; agreeKeyId = $c.value.agreeKeyId; agreePublic = $c.value.agreePublic; mailbox = $c.value.mailbox
        addedAt = (ConvertTo-HordeRelayRecordMs -Time $Now); card = (ConvertTo-HordeRelayBase64Url -Bytes (Get-HordeRelayAsciiBytes -Text $Card))
    }
    try { $moved = Write-HordeRelayTrustRecord -HordeHome $HordeHome -Folder "machines" -Name ($c.value.signKeyId + ".json") -Spec (Get-HordeRelayPeerSpec) -Values $values }
    catch { return (New-HordeUnknown -Reason "the machine could not be added" -ErrorRecord $_) }
    if ($moved -ceq "exists") { return (New-HordeUnknown -Reason ("the machine " + $c.value.signKeyId + " was added by another process at the same moment")) }
    if ($moved -cne "moved") { return (New-HordeUnknown -Reason ("the machine record " + $c.value.signKeyId + " has its name, but nothing says it reached the disk")) }
    $again = Read-HordeRelayTrustStore -HordeHome $HordeHome -Now $Now
    if (-not $again.ok) { return (New-HordeUnknown -Reason $again.reason) }
    return (New-HordeKnown -Value ([pscustomobject]@{ record = (@($again.machines | Where-Object { $_.keyId -ceq $c.value.signKeyId }) | Select-Object -First 1); duplicate = $false }))
}

function Confirm-HordeRelayPeerMachine {
    # Countersign a pending peer: By is the key id of a TRUSTED founder device, and the assertion
    # (authenticatorData, clientDataJSON, signature, as its phone returned them) must be by that
    # passkey, over Get-HordeRelayCardChallenge of the peer's card, user verified. Known { record;
    # already }; unknown when anything is refused; absent when the store holds no such peer.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$KeyId, [Parameter(Mandatory = $true)][string]$By,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$AuthenticatorData, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$ClientDataJson,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Signature, $Now = $null)
    $s = Read-HordeRelayTrustStore -HordeHome $HordeHome -Now $Now
    if (-not $s.ok) { return (New-HordeUnknown -Reason ($s.reason + "; nothing is countersigned until it is repaired")) }
    $m = @($s.machines | Where-Object { $_.keyId -ceq $KeyId }) | Select-Object -First 1
    if ($null -eq $m) { return (New-HordeAbsent -Note ("the trust store holds no machine " + $KeyId)) }
    if ($null -ne $m.revoked) { return (New-HordeUnknown -Reason ("the machine " + $KeyId + " was revoked and is never trusted again")) }
    if ($m.state -ceq "trusted") { return (New-HordeKnown -Value ([pscustomobject]@{ record = $m; already = $true })) }
    $dev = @($s.devices | Where-Object { $_.keyId -ceq $By -and $_.state -ceq "trusted" }) | Select-Object -First 1
    if ($null -eq $dev) { return (New-HordeUnknown -Reason ("the key " + $By + " is not a trusted device of the founder, so it cannot countersign")) }
    $values = @{
        v = 1; kind = "horde-relay-peer-countersigned"; keyId = $KeyId; by = $By; authenticatorData = (ConvertTo-HordeRelayBase64Url -Bytes $AuthenticatorData)
        clientDataJSON = (ConvertTo-HordeRelayBase64Url -Bytes $ClientDataJson); signature = (ConvertTo-HordeRelayBase64Url -Bytes $Signature)
        countersignedAt = (ConvertTo-HordeRelayRecordMs -Time $Now)
    }
    $check = Test-HordeRelayCountersign -Countersign ([pscustomobject]$values) -Device $dev -Card $m.cardText
    if (-not $check.ok) { return (New-HordeUnknown -Reason ("the countersignature is refused: " + $check.reason)) }
    $name = "machine-" + $KeyId + ".json"
    try { $moved = Write-HordeRelayTrustRecord -HordeHome $HordeHome -Folder "confirmed" -Name $name -Spec (Get-HordeRelayCountersignSpec) -Values $values }
    catch { return (New-HordeUnknown -Reason "the countersignature could not be written" -ErrorRecord $_) }
    if ($moved -ceq "exists") {
        # An earlier countersignature stands, by a passkey that is no longer trusted: write-once means
        # it is not replaced. The peer stays pending; say so rather than pretend.
        return (New-HordeUnknown -Reason ("the machine " + $KeyId + " already holds a countersignature (" + $m.why + "); write-once records are not replaced, so it stays pending - revoke it and add its new card to trust it again"))
    }
    if ($moved -cne "moved") { return (New-HordeUnknown -Reason ("the countersignature of " + $KeyId + " has its name, but nothing says it reached the disk")) }
    $again = Read-HordeRelayTrustStore -HordeHome $HordeHome -Now $Now
    if (-not $again.ok) { return (New-HordeUnknown -Reason $again.reason) }
    return (New-HordeKnown -Value ([pscustomobject]@{ record = (@($again.machines | Where-Object { $_.keyId -ceq $KeyId }) | Select-Object -First 1); already = $false }))
}

function Revoke-HordeRelayTrust {
    # End an entry - or reject a pending one: write its revocation beside it. Subject is device (Id is
    # the device id) or machine (Id is its signing key id). Known { revocation; already } - revoking
    # twice is already, not an error, and the first record stands; absent when the store holds no such
    # entry; unknown when the store is damaged or the record could not be written.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$Subject, [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Reason, $Now = $null)
    if (@("device", "machine") -cnotcontains $Subject) { throw ("a revocation's subject is device or machine, not '" + $Subject + "'") }
    if ($Id -cnotmatch '\A[0-9a-f]{32}\z') { return (New-HordeAbsent -Note ("'" + $Id + "' is not an id the trust store files anything under")) }
    if ((Test-HordeRelayRecordValue -Kind "text" -Value $Reason) -cne "" -or $Reason.Trim() -ceq "") { return (New-HordeUnknown -Reason "a revocation's reason is 1 to 512 printable ASCII characters, with no quote or backslash") }
    $s = Read-HordeRelayTrustStore -HordeHome $HordeHome -Now $Now
    if (-not $s.ok) { return (New-HordeUnknown -Reason ($s.reason + "; nothing is revoked until it is repaired, and nothing is trusted meanwhile")) }
    $entry = $null
    if ($Subject -ceq "device") { $entry = @($s.devices | Where-Object { $_.id -ceq $Id }) | Select-Object -First 1 }
    else { $entry = @($s.machines | Where-Object { $_.keyId -ceq $Id }) | Select-Object -First 1 }
    if ($null -eq $entry) { return (New-HordeAbsent -Note ("the trust store holds no " + $Subject + " " + $Id)) }
    if ($null -ne $entry.revoked) { return (New-HordeKnown -Value ([pscustomobject]@{ revocation = $entry.revoked; already = $true })) }
    $values = @{ v = 1; kind = "horde-relay-revocation"; subject = $Subject; id = $Id; keyId = $entry.keyId; reason = $Reason; revokedAt = (ConvertTo-HordeRelayRecordMs -Time $Now) }
    try { $moved = Write-HordeRelayTrustRecord -HordeHome $HordeHome -Folder "revoked" -Name ($Subject + "-" + $Id + ".json") -Spec (Get-HordeRelayRevocationSpec) -Values $values }
    catch { return (New-HordeUnknown -Reason "the revocation could not be written" -ErrorRecord $_) }
    if ($moved -ceq "exists") {
        $again = Read-HordeRelayTrustStore -HordeHome $HordeHome -Now $Now
        $first = $null
        if ($again.ok) { $first = @($again.revoked | Where-Object { $_.subject -ceq $Subject -and $_.id -ceq $Id }) | Select-Object -First 1 }
        if ($null -eq $first) { return (New-HordeUnknown -Reason "another process revoked this entry at the same moment, and its record cannot be read") }
        return (New-HordeKnown -Value ([pscustomobject]@{ revocation = $first; already = $true }))
    }
    if ($moved -cne "moved") { return (New-HordeUnknown -Reason ("the revocation of " + $Subject + " " + $Id + " has its name, but nothing says it reached the disk")) }
    return (New-HordeKnown -Value ([pscustomobject]@{ revocation = ([pscustomobject]$values); already = $false }))
}

function Find-HordeRelayTrustedSenders {
    # The senders relay/Envelope.ps1 verifies against: a hashtable of key id to New-HordeRelaySender,
    # for every TRUSTED entry at -Now - devices as passkeys (webauthn, with their relying party and
    # origins, user verification required), machines as es256. A pending, expired or revoked entry is
    # never in it. Known hashtable (empty when nobody is trusted); unknown when the store is damaged -
    # and then nobody is trusted.
    param([string]$HordeHome = "", $Now = $null)
    $s = Read-HordeRelayTrustStore -HordeHome $HordeHome -Now $Now
    if (-not $s.ok) { return (New-HordeUnknown -Reason ($s.reason + "; no sender is trusted until it is repaired")) }
    $out = @{}
    foreach ($d in @($s.devices | Where-Object { $_.state -ceq "trusted" })) {
        $out[$d.keyId] = New-HordeRelaySender -Public (ConvertFrom-HordeRelayBase64Url -Text $d.publicKey) -Proof "webauthn" -RpId $d.rpId -Origins @($d.origins) -RequireUserVerification $true
    }
    foreach ($m in @($s.machines | Where-Object { $_.state -ceq "trusted" })) {
        $out[$m.keyId] = New-HordeRelaySender -Public (ConvertFrom-HordeRelayBase64Url -Text $m.signPublic) -Proof "es256"
    }
    return (New-HordeKnown -Value $out)
}

function Find-HordeRelayTrustedSender {
    # One sender by key id. Known sender when it is trusted; absent when the store holds no such key,
    # or holds it pending, expired or revoked (the note says which); unknown when the store is damaged.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$KeyId, $Now = $null)
    $s = Read-HordeRelayTrustStore -HordeHome $HordeHome -Now $Now
    if (-not $s.ok) { return (New-HordeUnknown -Reason ($s.reason + "; no sender is trusted until it is repaired")) }
    $d = @($s.devices | Where-Object { $_.keyId -ceq $KeyId }) | Select-Object -First 1
    $m = @($s.machines | Where-Object { $_.keyId -ceq $KeyId }) | Select-Object -First 1
    $hit = $(if ($null -ne $d) { $d } else { $m })
    if ($null -eq $hit) { return (New-HordeAbsent -Note ("no trusted sender has the key " + $KeyId)) }
    if ($hit.state -ceq "revoked") { return (New-HordeAbsent -Note ("the key " + $KeyId + " was revoked at " + $hit.revoked.revokedAt + ": " + $hit.revoked.reason)) }
    if ($hit.state -ceq "expired") { return (New-HordeAbsent -Note ("the device with the key " + $KeyId + " was never confirmed, and its pairing expired at " + $hit.pendingUntil)) }
    if ($hit.state -ceq "pending" -and $null -ne $d) { return (New-HordeAbsent -Note ("the device with the key " + $KeyId + " is pending: it waits for its fingerprint to be confirmed at this machine")) }
    if ($hit.state -ceq "pending") { return (New-HordeAbsent -Note ("the machine with the key " + $KeyId + " is pending: " + $hit.why)) }
    if ($null -ne $d) { return (New-HordeKnown -Value (New-HordeRelaySender -Public (ConvertFrom-HordeRelayBase64Url -Text $d.publicKey) -Proof "webauthn" -RpId $d.rpId -Origins @($d.origins) -RequireUserVerification $true)) }
    return (New-HordeKnown -Value (New-HordeRelaySender -Public (ConvertFrom-HordeRelayBase64Url -Text $m.signPublic) -Proof "es256"))
}

function Add-HordeRelayPhoneKey {
    # Add a phone identity key from a founder passkey's vouch (PHONE KEYS, in the header). By is the key
    # id of a TRUSTED founder device; the assertion (authenticatorData, clientDataJSON, signature) must
    # be by it, over Get-HordeRelayPhoneKeyChallenge of this horde and the key, user verified. Known
    # { record; duplicate } - record is this passkey's vouch, trusted; duplicate when it was already
    # recorded. Unknown when anything is refused or the store is damaged - including a vouch by this
    # passkey already recorded for another horde, which is never answered as done.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$AgreePublic, [Parameter(Mandatory = $true)][string]$By,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$AuthenticatorData, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$ClientDataJson,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Signature, $Now = $null)
    $public = ConvertTo-HordeRelayBase64Url -Bytes $AgreePublic
    if ((Test-HordeRelayRecordValue -Kind "point" -Value $public) -cne "") { return (New-HordeUnknown -Reason "the phone key is not a P-256 public point") }
    $horde = Get-HordeRelayHorde -HordeHome $HordeHome
    if ($horde.state -cne "known") { return (New-HordeUnknown -Reason ("this machine's horde is not named, so no phone key can be vouched for in it: " + $horde.reason)) }
    $s = Read-HordeRelayTrustStore -HordeHome $HordeHome -Now $Now
    if (-not $s.ok) { return (New-HordeUnknown -Reason ($s.reason + "; nothing is added until it is repaired")) }
    $agreeKeyId = Get-HordeRelayKeyId -Public $AgreePublic
    $voucher = @($s.devices | Where-Object { $_.keyId -ceq $By -and $_.state -ceq "trusted" }) | Select-Object -First 1
    if ($null -eq $voucher) { return (New-HordeUnknown -Reason ("the key " + $By + " is not a trusted device of the founder, so it cannot vouch for a phone key")) }
    if (@($s.devices | Where-Object { $_.keyId -ceq $agreeKeyId }).Count -gt 0 -or @($s.machines | Where-Object { $_.keyId -ceq $agreeKeyId -or $_.agreeKeyId -ceq $agreeKeyId }).Count -gt 0) {
        return (New-HordeUnknown -Reason "this key is already in the store as a device's or a machine's")
    }
    # This passkey's own vouch for this key, if any. A vouch by ANOTHER passkey does not stand in for it:
    # that passkey may be revoked (finding 7), and a new vouch is how the key is trusted again.
    $prior = @($s.phones | Where-Object { $_.agreeKeyId -ceq $agreeKeyId -and $_.by -ceq $By }) | Select-Object -First 1
    if ($null -ne $prior) {
        if ($prior.state -ceq "trusted") { return (New-HordeKnown -Value ([pscustomobject]@{ record = $prior; duplicate = $true })) }
        return (New-HordeUnknown -Reason ("this passkey's vouch for the phone key " + $agreeKeyId + " is already recorded, and it is untrusted: " + $prior.why))
    }
    $values = @{
        v = 1; kind = "horde-relay-phone-key"; agreeKeyId = $agreeKeyId; horde = $horde.value; agreePublic = $public; by = $By
        authenticatorData = (ConvertTo-HordeRelayBase64Url -Bytes $AuthenticatorData); clientDataJSON = (ConvertTo-HordeRelayBase64Url -Bytes $ClientDataJson)
        signature = (ConvertTo-HordeRelayBase64Url -Bytes $Signature); addedAt = (ConvertTo-HordeRelayRecordMs -Time $Now)
    }
    $check = Test-HordeRelayPhoneKeyVouch -Phone ([pscustomobject]$values) -Device $voucher
    if (-not $check.ok) { return (New-HordeUnknown -Reason ("the vouch for the phone key is refused: " + $check.reason)) }
    try { $moved = Write-HordeRelayTrustRecord -HordeHome $HordeHome -Folder "phones" -Name ($agreeKeyId + "-" + $By + ".json") -Spec (Get-HordeRelayPhoneKeySpec) -Values $values }
    catch { return (New-HordeUnknown -Reason "the phone key could not be added" -ErrorRecord $_) }
    if ($moved -cne "moved" -and $moved -cne "exists") { return (New-HordeUnknown -Reason ("the phone key " + $agreeKeyId + " has its name, but nothing says it reached the disk")) }
    $again = Read-HordeRelayTrustStore -HordeHome $HordeHome -Now $Now
    if (-not $again.ok) { return (New-HordeUnknown -Reason $again.reason) }
    return (New-HordeKnown -Value ([pscustomobject]@{ record = (@($again.phones | Where-Object { $_.agreeKeyId -ceq $agreeKeyId -and $_.by -ceq $By }) | Select-Object -First 1); duplicate = ($moved -ceq "exists") }))
}

function Find-HordeRelayPhoneKeys {
    # The phone identity keys what is sealed for the founder goes to: every key with a TRUSTED vouch at
    # -Now, once, as { agreeKeyId; public (65 bytes); by } (by: the first trusted voucher), in key id
    # order. Known (empty when there is none); unknown when the store is damaged - and then nothing is
    # sealed to anyone.
    param([string]$HordeHome = "", $Now = $null)
    $s = Read-HordeRelayTrustStore -HordeHome $HordeHome -Now $Now
    if (-not $s.ok) { return (New-HordeUnknown -Reason ($s.reason + "; nothing is sealed to a phone until it is repaired")) }
    $seen = @{}
    $out = New-Object System.Collections.ArrayList
    # The store reads its records in file name order, <agreeKeyId>-<by>: key id order, and the voucher
    # with the lowest key id first (Sort-Object takes one literal name under tools/ExecScan.ps1).
    foreach ($ph in @($s.phones | Where-Object { $_.state -ceq "trusted" })) {
        if ($seen.ContainsKey($ph.agreeKeyId)) { continue }
        $seen[$ph.agreeKeyId] = $true
        [void]$out.Add([pscustomobject]@{ agreeKeyId = $ph.agreeKeyId; public = (ConvertFrom-HordeRelayBase64Url -Text $ph.agreePublic); by = $ph.by })
    }
    $out = @($out.ToArray())
    return (New-HordeKnown -Value $out)
}

function Get-HordeRelayPhoneVouchSpec {
    # THE PHONE VOUCH ITEM (THE VOUCH TRAVELS BY ITSELF, in the header). relay/js/protocol.js's
    # phoneVouchText writes the same text.
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "horde", "name", "by", "hex32", "agreePublic", "point",
        "authenticatorData", "b64u", "clientDataJSON", "b64u", "signature", "b64u"))
}

function Test-HordeRelayPhoneVouchText {
    # Does -Text say it is a phone vouch item (its first members)? Only a routing question: what it holds
    # is judged by Receive-HordeRelayPhoneVouch.
    param([AllowNull()][AllowEmptyString()][string]$Text)
    return ($null -ne $Text -and $Text.StartsWith('{"v":1,"kind":"horde-relay-phone-vouch",'))
}

function New-HordeRelayRefusedOutcome {
    # { outcome = "refused"; reason; request = "" }: what an item judged here answers when it is refused
    # for good (a function, not a script block: tools/ExecScan.ps1 holds relay/ to holding none).
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Reason)
    return [pscustomobject]@{ outcome = "refused"; reason = $Reason; request = "" }
}

function Receive-HordeRelayPhoneVouch {
    # One phone vouch item from the machine's mailbox into the trust store (the header). { outcome;
    # reason }: done (the key is trusted by this vouch, now or already), refused (never will be: the
    # item, the device or the vouch) or held (the trust store cannot be read now: the item comes again).
    # Never throws.
    param([string]$HordeHome = "", [AllowNull()][AllowEmptyString()][string]$Text, $Now = $null)
    if ($null -eq $Text) { $Text = "" }
    # The three base64url parts of a WebAuthn assertion are a few hundred characters; 16384 is room.
    if ($Text.Length -gt 16384) { return (New-HordeRelayRefusedOutcome -Reason ("the phone vouch is " + $Text.Length + " characters, over the 16384 one may be; it is not read")) }
    $r = Read-HordeRelayRecordText -Text $Text -Spec (Get-HordeRelayPhoneVouchSpec) -Kind "horde-relay-phone-vouch" -What "the phone vouch"
    if (-not $r.ok) { return (New-HordeRelayRefusedOutcome -Reason $r.reason) }
    $v = $r.value
    if ($v.signature -ceq "" -or $v.authenticatorData -ceq "" -or $v.clientDataJSON -ceq "") { return (New-HordeRelayRefusedOutcome -Reason "the phone vouch carries no signature: an unsigned announcement is never taken") }
    $horde = Get-HordeRelayHorde -HordeHome $HordeHome
    if ($horde.state -cne "known") { return [pscustomobject]@{ outcome = "held"; reason = ("this machine's horde is not named: " + $horde.reason) } }
    if ($v.horde -cne $horde.value) { return (New-HordeRelayRefusedOutcome -Reason ("the phone vouch is for the horde " + $v.horde + ", not this one (" + $horde.value + ")")) }
    $s = Read-HordeRelayTrustStore -HordeHome $HordeHome -Now $Now
    if (-not $s.ok) { return [pscustomobject]@{ outcome = "held"; reason = ("the trust store cannot be read: " + $s.reason) } }
    try {
        $added = Add-HordeRelayPhoneKey -HordeHome $HordeHome -AgreePublic (ConvertFrom-HordeRelayBase64Url -Text $v.agreePublic) -By $v.by `
            -AuthenticatorData (ConvertFrom-HordeRelayBase64Url -Text $v.authenticatorData) -ClientDataJson (ConvertFrom-HordeRelayBase64Url -Text $v.clientDataJSON) `
            -Signature (ConvertFrom-HordeRelayBase64Url -Text $v.signature) -Now $Now
    } catch { return (New-HordeRelayRefusedOutcome -Reason ("the phone vouch could not be read: " + $_.Exception.Message)) }
    if ($added.state -cne "known") { return (New-HordeRelayRefusedOutcome -Reason ("the phone key is refused: " + $added.reason)) }
    return [pscustomobject]@{ outcome = "done"; reason = ("the phone key " + $added.value.record.agreeKeyId + " is " + $(if ($added.value.duplicate) { "already" } else { "now" }) + " in the trust store, vouched for by " + $added.value.record.by + " (a phone vouch item)") }
}
