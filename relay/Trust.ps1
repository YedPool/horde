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
#   revoked\device-<id>.json, revoked\machine-<keyId>.json
#                           the end of an entry: when, and why. Revocation is a record BESIDE the entry,
#                           never its deletion, so the trust store keeps its own history and a revoked
#                           key can never come back by being added again - a new key is a new entry.
#
# NOTHING IS TRUSTED ON ARRIVAL (founder decisions of 2026-10-09):
#   A DEVICE is enrolled through pairing (relay/Pairing.ps1) as PENDING: its registration verified, its
#   key on the curve, but not trusted. It becomes TRUSTED only when the founder confirms it at the
#   machine with the fingerprint both screens show (Confirm-HordeRelayDevice), before pendingUntil - the
#   offer's own expiry. Past that, unconfirmed, it is EXPIRED, for good. A pending device can be
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
    $fail = [pscustomobject]@{ ok = $false; reason = ""; devices = @(); machines = @(); revoked = @() }
    try { $root = Get-HordeRelayStateDir -HordeHome $HordeHome -Part "trust" } catch { $fail.reason = $_.Exception.Message; return $fail }
    $nowMs = ConvertTo-HordeRelayRecordMs -Time $Now
    $devs = Read-HordeRelayTrustFolder -Dir ([System.IO.Path]::Combine($root, "devices")) -Pattern '\A[0-9a-f]{32}\.json\z' -Spec (Get-HordeRelayDeviceSpec) -Kind "horde-relay-device"
    if (-not $devs.ok) { $fail.reason = $devs.reason; return $fail }
    $peers = Read-HordeRelayTrustFolder -Dir ([System.IO.Path]::Combine($root, "machines")) -Pattern '\A[0-9a-f]{32}\.json\z' -Spec (Get-HordeRelayPeerSpec) -Kind "horde-relay-peer"
    if (-not $peers.ok) { $fail.reason = $peers.reason; return $fail }
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
    return [pscustomobject]@{ ok = $true; reason = ""; devices = @($devOut.ToArray()); machines = @($peerOut.ToArray()); revoked = @(@($revs.records) | ForEach-Object { $_.record }) }
}

function Get-HordeRelayTrust {
    # The store, for whoever shows it: known { devices; machines; revoked }, every entry with its state
    # at -Now; unknown when the store is damaged.
    param([string]$HordeHome = "", $Now = $null)
    $s = Read-HordeRelayTrustStore -HordeHome $HordeHome -Now $Now
    if (-not $s.ok) { return (New-HordeUnknown -Reason $s.reason) }
    return (New-HordeKnown -Value ([pscustomobject]@{ devices = @($s.devices); machines = @($s.machines); revoked = @($s.revoked) }))
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
