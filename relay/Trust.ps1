# relay/Trust.ps1 - who this machine believes: the founder's enrolled devices (passkeys) and the peer
# machines of its own horde. Added once, listed, revoked - never edited, never deleted.
#
# WHERE: <HORDE_HOME>\relay\trust\ (relay/Records.ps1, write-once):
#   devices\<id>.json       an enrolled founder device. id is the first 16 bytes of SHA-256 of the
#                           credential id, as hex: a credential id is up to 1023 bytes of anything, so
#                           it is never a file name itself.
#   machines\<keyId>.json   a peer machine of the same horde, by its signing key id.
#   revoked\device-<id>.json, revoked\machine-<keyId>.json
#                           the end of an entry: when, and why. Revocation is a record BESIDE the entry,
#                           never its deletion, so the trust store keeps its own history and a revoked
#                           key can never come back by being added again - a new key is a new entry.
#
# A DEVICE is a passkey credential, enrolled only through pairing (relay/Pairing.ps1), which verified
# its registration (relay/Registration.ps1): its COSE key imported as a P-256 point on the curve, the
# credential id, the relying party id and the origins its assertions must name, whether the phone said
# PRF works with it (prf: the client's own report, prf.enabled, which nothing signs - a hint for the
# phone-key wrap of a later pull request, never a trust decision), whether the authenticator reported
# hmac-secret, whether it is backup eligible (a synced passkey), what the person called it, when it was
# enrolled, and through which offer.
# A PEER MACHINE is added from its card (relay/Identity.ps1, Read-HordeRelayMachineCard): a card proves
# its maker held the signing key; it must name this machine's horde, and must not be this machine.
# How a card reaches a peer - and whether the founder's passkey must countersign it - is the runner's
# (a later pull request); this file only keeps what it is given, checked.
#
# EVERY READ RE-CHECKS EVERY RECORD: canonical form, key ids that are their keys', public keys that are
# points on P-256 (relay/Records.ps1's point kind), file names that are their records' ids, revocations
# that name an entry that exists. ANY damage makes the whole store unknown, not just the entry: a
# revocation that cannot be read is a revocation that cannot be honoured, so nothing is trusted until a
# person repairs it. Find-HordeRelayTrustedSenders answers the hashtable relay/Envelope.ps1 verifies
# against: active entries only, a revoked one never.
#
# Answers are core/tristate.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")
. (Join-Path $PSScriptRoot "Bytes.ps1")
. (Join-Path $PSScriptRoot "P256.ps1")
. (Join-Path $PSScriptRoot "Records.ps1")
. (Join-Path $PSScriptRoot "Identity.ps1")
. (Join-Path $PSScriptRoot "Envelope.ps1")

function Get-HordeRelayDeviceSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "id", "hex32", "horde", "name", "label", "label", "credentialId", "b64u",
        "publicKey", "point", "keyId", "hex32", "rpId", "rpid", "origins", "origins", "prf", "bool", "hmacSecret", "bool", "backupEligible", "bool",
        "aaguid", "hex", "offer", "hex32", "enrolledAt", "int"))
}

function Get-HordeRelayPeerSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "keyId", "hex32", "horde", "name", "label", "label", "generation", "int",
        "signPublic", "point", "agreeKeyId", "hex32", "agreePublic", "point", "mailbox", "mailbox", "addedAt", "int"))
}

function Get-HordeRelayRevocationSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "subject", "name", "id", "hex32", "keyId", "hex32", "reason", "text", "revokedAt", "int"))
}

function Get-HordeRelayDeviceId {
    # The id a device entry is filed under: the first 16 bytes of SHA-256(credential id), as hex.
    param([Parameter(Mandatory = $true)][byte[]]$CredentialId)
    $h = Get-HordeRelaySha256 -Bytes $CredentialId
    $first = New-Object byte[] 16
    [System.Array]::Copy($h, 0, $first, 0, 16)
    return (ConvertTo-HordeRelayHex -Bytes $first)
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

function Read-HordeRelayTrustStore {
    # The whole store, checked (the header): { ok; reason; devices; machines; revoked }, each entry a
    # record with revoked added ($null, or the revocation record).
    param([string]$HordeHome)
    $fail = [pscustomobject]@{ ok = $false; reason = ""; devices = @(); machines = @(); revoked = @() }
    try { $root = Get-HordeRelayStateDir -HordeHome $HordeHome -Part "trust" } catch { $fail.reason = $_.Exception.Message; return $fail }
    $devs = Read-HordeRelayTrustFolder -Dir ([System.IO.Path]::Combine($root, "devices")) -Pattern '\A[0-9a-f]{32}\.json\z' -Spec (Get-HordeRelayDeviceSpec) -Kind "horde-relay-device"
    if (-not $devs.ok) { $fail.reason = $devs.reason; return $fail }
    $peers = Read-HordeRelayTrustFolder -Dir ([System.IO.Path]::Combine($root, "machines")) -Pattern '\A[0-9a-f]{32}\.json\z' -Spec (Get-HordeRelayPeerSpec) -Kind "horde-relay-peer"
    if (-not $peers.ok) { $fail.reason = $peers.reason; return $fail }
    $revs = Read-HordeRelayTrustFolder -Dir ([System.IO.Path]::Combine($root, "revoked")) -Pattern '\A(device|machine)-[0-9a-f]{32}\.json\z' -Spec (Get-HordeRelayRevocationSpec) -Kind "horde-relay-revocation"
    if (-not $revs.ok) { $fail.reason = $revs.reason; return $fail }
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
        if ($r.keyId -cne (Get-HordeRelayKeyId -Public (ConvertFrom-HordeRelayBase64Url -Text $r.signPublic)) -or $r.agreeKeyId -cne (Get-HordeRelayKeyId -Public (ConvertFrom-HordeRelayBase64Url -Text $r.agreePublic))) { $fail.reason = ("the machine record " + $m.file + " names key ids that are not its keys'"); return $fail }
        if ($byKey.ContainsKey($r.keyId)) { $fail.reason = ("the key " + $r.keyId + " is in the store twice"); return $fail }
        $byKey[$r.keyId] = "machine-" + $r.keyId
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
    $devOut = @(@($devs.records) | ForEach-Object { $_.record | Add-Member -NotePropertyName "revoked" -NotePropertyValue $revBy[("device-" + $_.record.id)] -PassThru })
    $peerOut = @(@($peers.records) | ForEach-Object { $_.record | Add-Member -NotePropertyName "revoked" -NotePropertyValue $revBy[("machine-" + $_.record.keyId)] -PassThru })
    return [pscustomobject]@{ ok = $true; reason = ""; devices = $devOut; machines = $peerOut; revoked = @(@($revs.records) | ForEach-Object { $_.record }) }
}

function Get-HordeRelayTrust {
    # The store, for whoever shows it: known { devices; machines; revoked }, every entry with its
    # revocation or $null; unknown when the store is damaged.
    param([string]$HordeHome = "")
    $s = Read-HordeRelayTrustStore -HordeHome $HordeHome
    if (-not $s.ok) { return (New-HordeUnknown -Reason $s.reason) }
    return (New-HordeKnown -Value ([pscustomobject]@{ devices = @($s.devices); machines = @($s.machines); revoked = @($s.revoked) }))
}

function Add-HordeRelayTrustedDevice {
    # Enroll a founder device from a VERIFIED registration (Test-HordeRelayWebAuthnRegistration's
    # answer, ok). Pairing is its one caller: a registration only means something over an offer's
    # challenge. Known (the device record); unknown when the store is damaged, the credential is
    # already enrolled or was ever revoked, or the record could not be written.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)]$Registration, [Parameter(Mandatory = $true)][string]$Horde,
        [Parameter(Mandatory = $true)][string]$RpId, [Parameter(Mandatory = $true)][string[]]$Origins, [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][bool]$Prf, [Parameter(Mandatory = $true)][string]$OfferId, $Now = $null)
    if (-not $Registration.ok) { return (New-HordeUnknown -Reason "only a verified registration is enrolled") }
    $s = Read-HordeRelayTrustStore -HordeHome $HordeHome
    if (-not $s.ok) { return (New-HordeUnknown -Reason ($s.reason + "; nothing is enrolled until it is repaired")) }
    $id = Get-HordeRelayDeviceId -CredentialId $Registration.credentialId
    $keyId = Get-HordeRelayKeyId -Public $Registration.public
    $prior = @($s.devices | Where-Object { $_.id -ceq $id -or $_.keyId -ceq $keyId })
    if ($prior.Count -gt 0) {
        if ($null -ne $prior[0].revoked) { return (New-HordeUnknown -Reason ("this credential (" + $id + ") was revoked at " + $prior[0].revoked.revokedAt + " and is never enrolled again; make a new passkey")) }
        return (New-HordeUnknown -Reason ("this credential (" + $id + ") is already enrolled as '" + $prior[0].label + "'"))
    }
    if (@($s.machines | Where-Object { $_.keyId -ceq $keyId }).Count -gt 0) { return (New-HordeUnknown -Reason "this key is a peer machine's, not a device's") }
    $values = @{
        v = 1; kind = "horde-relay-device"; id = $id; horde = $Horde; label = $Label; credentialId = (ConvertTo-HordeRelayBase64Url -Bytes $Registration.credentialId)
        publicKey = (ConvertTo-HordeRelayBase64Url -Bytes $Registration.public); keyId = $keyId; rpId = $RpId; origins = @($Origins)
        prf = $Prf; hmacSecret = [bool]$Registration.hmacSecret; backupEligible = [bool]$Registration.backupEligible; aaguid = $Registration.aaguid
        offer = $OfferId; enrolledAt = (ConvertTo-HordeRelayRecordMs -Time $Now)
    }
    try {
        $text = ConvertTo-HordeRelayRecordText -Spec (Get-HordeRelayDeviceSpec) -Values $values
        $moved = Write-HordeRelayRecordFile -Dir ([System.IO.Path]::Combine((Get-HordeRelayStateDir -HordeHome $HordeHome -Part "trust"), "devices")) -Name ($id + ".json") -Text $text
    } catch { return (New-HordeUnknown -Reason "the device could not be enrolled" -ErrorRecord $_) }
    if ($moved -ceq "exists") { return (New-HordeUnknown -Reason ("this credential (" + $id + ") was enrolled by another process at the same moment")) }
    if ($moved -cne "moved") { return (New-HordeUnknown -Reason ("the device record " + $id + " has its name, but nothing says it reached the disk")) }
    return (New-HordeKnown -Value ([pscustomobject]$values))
}

function Add-HordeRelayTrustedMachine {
    # Trust a peer machine of this horde, from its card. Known { record; duplicate } - adding the same
    # card's keys again is duplicate, not an error; unknown when the card is refused, names another
    # horde or this machine, the key was ever revoked, or the store is damaged.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Card, $Now = $null)
    $c = Read-HordeRelayMachineCard -Text $Card
    if (-not $c.ok) { return (New-HordeUnknown -Reason ("the machine card is refused: " + $c.reason)) }
    $horde = Get-HordeRelayHorde -HordeHome $HordeHome
    if ($horde.state -cne "known") { return (New-HordeUnknown -Reason ("this machine's horde is not named, so no peer can be checked against it: " + $horde.reason)) }
    if ($c.value.horde -cne $horde.value) { return (New-HordeUnknown -Reason ("the card is from the horde '" + $c.value.horde + "', and this machine belongs to '" + $horde.value + "'")) }
    $me = Get-HordeRelayMachineIdentity -HordeHome $HordeHome
    if ($me.state -ceq "known" -and ($me.value.sign.keyId -ceq $c.value.signKeyId -or $me.value.agree.keyId -ceq $c.value.agreeKeyId)) { return (New-HordeUnknown -Reason "the card is this machine's own") }
    $s = Read-HordeRelayTrustStore -HordeHome $HordeHome
    if (-not $s.ok) { return (New-HordeUnknown -Reason ($s.reason + "; nothing is added until it is repaired")) }
    if (@($s.devices | Where-Object { $_.keyId -ceq $c.value.signKeyId }).Count -gt 0) { return (New-HordeUnknown -Reason "this key is an enrolled device's, not a machine's") }
    $prior = @($s.machines | Where-Object { $_.keyId -ceq $c.value.signKeyId }) | Select-Object -First 1
    if ($null -ne $prior) {
        if ($null -ne $prior.revoked) { return (New-HordeUnknown -Reason ("the machine " + $prior.keyId + " was revoked at " + $prior.revoked.revokedAt + " and is never trusted again; a rotated machine has a new key")) }
        if ($prior.agreePublic -ceq $c.value.agreePublic -and $prior.signPublic -ceq $c.value.signPublic) { return (New-HordeKnown -Value ([pscustomobject]@{ record = $prior; duplicate = $true })) }
        return (New-HordeUnknown -Reason ("the machine " + $prior.keyId + " is already trusted with another agreement key"))
    }
    $values = @{
        v = 1; kind = "horde-relay-peer"; keyId = $c.value.signKeyId; horde = $c.value.horde; label = $c.value.label; generation = $c.value.generation
        signPublic = $c.value.signPublic; agreeKeyId = $c.value.agreeKeyId; agreePublic = $c.value.agreePublic; mailbox = $c.value.mailbox
        addedAt = (ConvertTo-HordeRelayRecordMs -Time $Now)
    }
    try {
        $text = ConvertTo-HordeRelayRecordText -Spec (Get-HordeRelayPeerSpec) -Values $values
        $moved = Write-HordeRelayRecordFile -Dir ([System.IO.Path]::Combine((Get-HordeRelayStateDir -HordeHome $HordeHome -Part "trust"), "machines")) -Name ($c.value.signKeyId + ".json") -Text $text
    } catch { return (New-HordeUnknown -Reason "the machine could not be added" -ErrorRecord $_) }
    if ($moved -ceq "exists") { return (New-HordeUnknown -Reason ("the machine " + $c.value.signKeyId + " was added by another process at the same moment")) }
    if ($moved -cne "moved") { return (New-HordeUnknown -Reason ("the machine record " + $c.value.signKeyId + " has its name, but nothing says it reached the disk")) }
    return (New-HordeKnown -Value ([pscustomobject]@{ record = ([pscustomobject]$values); duplicate = $false }))
}

function Revoke-HordeRelayTrust {
    # End an entry: write its revocation beside it. Subject is device (Id is the device id) or machine
    # (Id is its signing key id). Known { revocation; already } - revoking twice is already, not an
    # error, and the first record stands; absent when the store holds no such entry; unknown when the
    # store is damaged or the record could not be written.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$Subject, [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Reason, $Now = $null)
    if (@("device", "machine") -cnotcontains $Subject) { throw ("a revocation's subject is device or machine, not '" + $Subject + "'") }
    if ($Id -cnotmatch '\A[0-9a-f]{32}\z') { return (New-HordeAbsent -Note ("'" + $Id + "' is not an id the trust store files anything under")) }
    if ((Test-HordeRelayRecordValue -Kind "text" -Value $Reason) -cne "" -or $Reason.Trim() -ceq "") { return (New-HordeUnknown -Reason "a revocation's reason is 1 to 512 printable ASCII characters, with no quote or backslash") }
    $s = Read-HordeRelayTrustStore -HordeHome $HordeHome
    if (-not $s.ok) { return (New-HordeUnknown -Reason ($s.reason + "; nothing is revoked until it is repaired, and nothing is trusted meanwhile")) }
    $entry = $null
    if ($Subject -ceq "device") { $entry = @($s.devices | Where-Object { $_.id -ceq $Id }) | Select-Object -First 1 }
    else { $entry = @($s.machines | Where-Object { $_.keyId -ceq $Id }) | Select-Object -First 1 }
    if ($null -eq $entry) { return (New-HordeAbsent -Note ("the trust store holds no " + $Subject + " " + $Id)) }
    if ($null -ne $entry.revoked) { return (New-HordeKnown -Value ([pscustomobject]@{ revocation = $entry.revoked; already = $true })) }
    $values = @{ v = 1; kind = "horde-relay-revocation"; subject = $Subject; id = $Id; keyId = $entry.keyId; reason = $Reason; revokedAt = (ConvertTo-HordeRelayRecordMs -Time $Now) }
    try {
        $text = ConvertTo-HordeRelayRecordText -Spec (Get-HordeRelayRevocationSpec) -Values $values
        $moved = Write-HordeRelayRecordFile -Dir ([System.IO.Path]::Combine((Get-HordeRelayStateDir -HordeHome $HordeHome -Part "trust"), "revoked")) -Name ($Subject + "-" + $Id + ".json") -Text $text
    } catch { return (New-HordeUnknown -Reason "the revocation could not be written" -ErrorRecord $_) }
    if ($moved -ceq "exists") {
        $again = Read-HordeRelayTrustStore -HordeHome $HordeHome
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
    # for every ACTIVE entry - devices as passkeys (webauthn, with their relying party and origins, user
    # verification required), machines as es256. A revoked entry is never in it. Known hashtable (empty
    # when nobody is trusted); unknown when the store is damaged - and then nobody is trusted.
    param([string]$HordeHome = "")
    $s = Read-HordeRelayTrustStore -HordeHome $HordeHome
    if (-not $s.ok) { return (New-HordeUnknown -Reason ($s.reason + "; no sender is trusted until it is repaired")) }
    $out = @{}
    foreach ($d in @($s.devices | Where-Object { $null -eq $_.revoked })) {
        $out[$d.keyId] = New-HordeRelaySender -Public (ConvertFrom-HordeRelayBase64Url -Text $d.publicKey) -Proof "webauthn" -RpId $d.rpId -Origins @($d.origins) -RequireUserVerification $true
    }
    foreach ($m in @($s.machines | Where-Object { $null -eq $_.revoked })) {
        $out[$m.keyId] = New-HordeRelaySender -Public (ConvertFrom-HordeRelayBase64Url -Text $m.signPublic) -Proof "es256"
    }
    return (New-HordeKnown -Value $out)
}

function Find-HordeRelayTrustedSender {
    # One sender by key id. Known sender; absent when the store holds no such key OR holds it revoked
    # (the note says which, and when); unknown when the store is damaged.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$KeyId)
    $s = Read-HordeRelayTrustStore -HordeHome $HordeHome
    if (-not $s.ok) { return (New-HordeUnknown -Reason ($s.reason + "; no sender is trusted until it is repaired")) }
    $d = @($s.devices | Where-Object { $_.keyId -ceq $KeyId }) | Select-Object -First 1
    $m = @($s.machines | Where-Object { $_.keyId -ceq $KeyId }) | Select-Object -First 1
    $hit = $(if ($null -ne $d) { $d } else { $m })
    if ($null -eq $hit) { return (New-HordeAbsent -Note ("no trusted sender has the key " + $KeyId)) }
    if ($null -ne $hit.revoked) { return (New-HordeAbsent -Note ("the key " + $KeyId + " was revoked at " + $hit.revoked.revokedAt + ": " + $hit.revoked.reason)) }
    if ($null -ne $d) { return (New-HordeKnown -Value (New-HordeRelaySender -Public (ConvertFrom-HordeRelayBase64Url -Text $d.publicKey) -Proof "webauthn" -RpId $d.rpId -Origins @($d.origins) -RequireUserVerification $true)) }
    return (New-HordeKnown -Value (New-HordeRelaySender -Public (ConvertFrom-HordeRelayBase64Url -Text $m.signPublic) -Proof "es256"))
}
