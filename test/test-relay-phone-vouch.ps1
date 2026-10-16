# DOES THE MACHINE TAKE A PHONE'S VOUCH ITEM ONLY FROM A TRUSTED PASSKEY - AND DOES ANYTHING ELSE CHANGE
# NOTHING?
#
# relay/Trust.ps1, THE VOUCH TRAVELS BY ITSELF (the founder, 2026-10-14: the phone announces itself with
# no button, on the one passkey prompt of an unlock): the vouch arrives as a plain item in the machine's
# mailbox, not an envelope, and channels/Port.ps1 hands it to Receive-HordeRelayPhoneVouch. Over
# relays/local, in this process, with phones held in memory (test/lib/RelayPhone.ps1). Must-refuse and
# must-accept twins, each refusal checked to change nothing in the trust store:
#   - a PENDING passkey's vouch is refused (an announcement before confirmation changes nothing); the
#     same passkey, confirmed, is taken - from the same kind of item;
#   - an UNSIGNED vouch, one SIGNED BY ANOTHER KEY in a trusted passkey's name, one for ANOTHER HORDE,
#     one by a REVOKED passkey, one not in its canonical form, one over the size cap: refused;
#   - the same vouch twice is the same record; a trust store that cannot be read holds the item;
#   - the confirmed record the machine puts for the phone (relay/Pairing.ps1, TELLING THE PHONE IT IS
#     CONFIRMED) is made only for a trusted device of that offer, and verifies under the machine's key.
#
# Every home is the suite's own under %TEMP%; every key is made with the software provider and removed
# in the finally block, then checked gone. Off Windows there is no key store: the suite exits 3.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\FleetPin.ps1")
$fleetPin = Enter-HordeTestEmptyFleet
. (Join-Path $root "core\ModuleSettings.ps1")
. (Join-Path $root "channels\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
foreach ($f in @(Get-HordeRelayChannelFiles)) { . $f }
. (Join-Path $root "test\lib\RelayPhone.ps1")
Set-StrictMode -Version Latest

if ((Get-HordeRelayKeyStore).state -cne "known") {
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "no key store here: no machine identity can be made, so nothing was run" -PassCode 3
}

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$realHome = $env:HORDE_HOME
$work = Join-Path $env:TEMP ("horde-relay-phone-vouch-" + [guid]::NewGuid().ToString("N"))
$hh = Join-Path $work "home"
New-Item -ItemType Directory -Path (Join-Path $hh "settings") -Force | Out-Null
$keysMade = @()

function New-VouchText {
    # A phone vouch item, as relay/js/protocol.js's phoneVouchText writes it. -Signer signs (the phone
    # itself by default); -By names the passkey; -Bare leaves the assertion out.
    param($Phone, [string]$Horde = "work", $Signer = $null, [string]$By = "", [switch]$Bare)
    if ($null -eq $Signer) { $Signer = $Phone }
    if ($By -ceq "") { $By = $Phone.keyId }
    $key = ConvertTo-HordeRelayBase64Url -Bytes $Phone.agreePublic
    $ad = ""; $cd = ""; $sg = ""
    if (-not $Bare) {
        $a = New-HordeTestPhoneAssertion -Phone $Signer -Challenge (Get-HordeRelayPhoneKeyChallenge -Horde $Horde -AgreePublic $key)
        $ad = ConvertTo-HordeRelayBase64Url -Bytes $a.authenticatorData; $cd = ConvertTo-HordeRelayBase64Url -Bytes $a.clientDataJson; $sg = ConvertTo-HordeRelayBase64Url -Bytes $a.signature
    }
    return ('{"v":1,"kind":"horde-relay-phone-vouch","horde":"' + $Horde + '","by":"' + $By + '","agreePublic":"' + $key + '","authenticatorData":"' + $ad + '","clientDataJSON":"' + $cd + '","signature":"' + $sg + '"}')
}
function Get-Shape {
    # What a vouch can change: every device's state and every phone key's vouch.
    $t = Get-HordeRelayTrust -HordeHome $hh
    if ($t.state -cne "known") { return "unreadable: " + $t.reason }
    return ((@($t.value.devices | ForEach-Object { "device " + $_.id + " " + $_.state }) + @($t.value.phones | ForEach-Object { "phone " + $_.agreeKeyId + " " + $_.state + " by " + $_.by })) -join "; ")
}
function Invoke-Inbox {
    # Put the texts into the machine's mailbox and take one turn of the path in: Receive-HordeRelayInbox.
    param([string[]]$Texts)
    $n = 0
    foreach ($t in $Texts) { $n++; [void](Send-HordeRelayItem -Connection $script:conn -Mailbox $script:ctx.mailbox -Text $t -Key ("vouch/test/" + [guid]::NewGuid().ToString("N"))) }
    return (Receive-HordeRelayInbox -Context $script:ctx -TimeoutMs 0)
}

try {
    $env:HORDE_HOME = $hh
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay.json"), '{"schemaVersion": 1, "settings": {"horde": "work"}}', $utf8)
    $id = New-HordeRelayMachineIdentity -HordeHome $hh -Provider "software"
    Check ($id.state -ceq "known") "CONTROL: the machine has its relay identity"
    $keysMade = @(@{ n = $id.value.sign.name; s = $id.value.scope }, @{ n = $id.value.agree.name; s = $id.value.scope })
    $c = Connect-HordeRelay -Name "local" -Options @{ root = (Join-Path $work "relay") }
    $script:conn = $c.value
    $made = New-HordeRelayRunContext -HordeHome $hh -Connection $script:conn
    Check ($c.state -ceq "known" -and $made.state -ceq "known") "CONTROL: a local relay and a run context over it"
    $script:ctx = $made.value

    Write-Host ""
    Write-Host "--- 1. pending, the vouch is refused and changes nothing; confirmed, the same is taken ---" -ForegroundColor Cyan
    $phone = New-HordeTestPhone
    $o = New-HordeRelayPairingOffer -HordeHome $hh -RpId "relay.example.test" -Origins @("https://relay.example.test")
    $done = Complete-HordeRelayPairing -HordeHome $hh -Response (New-HordeTestPhonePairingResponse -Offer $o.value -Phone $phone)
    Check ($done.ok -and $done.value.device.state -ceq "pending") "CONTROL: the phone's passkey is enrolled PENDING"
    $word = New-HordeRelayPairingConfirmedText -HordeHome $hh -Offer $o.value.offer -Device $done.value.device.id
    Check ($word.state -cne "known" -and $word.reason.Contains("is not trusted")) ("no confirmed record is made for a device not yet confirmed (" + $word.reason + ")")
    $before = Get-Shape
    $in = Invoke-Inbox @((New-VouchText -Phone $phone))
    $r = @(Get-HordeTestMember -Object $in -Path "value.refused")
    Check ($in.state -ceq "known" -and $r.Count -eq 1 -and $r[0].Contains("is not a trusted device of the founder")) ("A PENDING PASSKEY'S VOUCH IS REFUSED (" + ($r -join " | ") + ")")
    Check ((Get-Shape) -ceq $before -and -not $before.Contains("phone ")) ("an announcement before confirmation changes nothing (" + (Get-Shape) + ")")
    Check (@(Get-HordeTestMember -Object $in -Path "value.held").Count -eq 0 -and [long](Get-HordeTestMember -Object $in -Path "value.acked") -ge 1) "and it is settled - acked - not held to come again"
    $conf = Confirm-HordeRelayDevice -HordeHome $hh -Id $done.value.device.id -Fingerprint $done.value.fingerprint
    Check ($conf.ok) "CONTROL: the founder confirms the passkey at the machine"
    $in = Invoke-Inbox @((New-VouchText -Phone $phone))
    $v = @(Get-HordeTestMember -Object $in -Path "value.vouched")
    $phoneKeyId = Get-HordeRelayKeyId -Public $phone.agreePublic
    Check ($v.Count -eq 1 -and $v[0].Contains("the phone key " + $phoneKeyId + " is now in the trust store, vouched for by " + $phone.keyId)) ("CONFIRMED, THE SAME KIND OF ITEM IS TAKEN: the phone key is in the trust store (" + ($v -join " | ") + ")")
    $keys = Find-HordeRelayPhoneKeys -HordeHome $hh
    Check ($keys.state -ceq "known" -and @($keys.value).Count -eq 1 -and $keys.value[0].agreeKeyId -ceq $phoneKeyId) "and what is sealed for the founder now goes to that key"
    $in = Invoke-Inbox @((New-VouchText -Phone $phone))
    $v = @(Get-HordeTestMember -Object $in -Path "value.vouched")
    Check ($v.Count -eq 1 -and $v[0].Contains("is already in the trust store") -and @((Find-HordeRelayPhoneKeys -HordeHome $hh).value).Count -eq 1) "the same vouch again is the same record"
    $word = New-HordeRelayPairingConfirmedText -HordeHome $hh -Offer $o.value.offer -Device $done.value.device.id
    $wr = $(if ($word.state -ceq "known") { Read-HordeRelayRecordText -Text $word.value.text -Spec (Get-HordeRelayPairingConfirmedSpec) -Kind "horde-relay-pairing-confirmed" } else { $null })
    $sigOk = ($null -ne $wr -and $wr.ok -and (Test-HordeRelayEs256Signature -Public $id.value.sign.public -Bytes (Get-HordeRelayPairingConfirmedBytes -Horde "work" -Offer $o.value.offer -Device $done.value.device.id -ConfirmedAt $wr.value.confirmedAt) -Signature (ConvertFrom-HordeRelayBase64Url -Text $wr.value.sig)))
    Check ($sigOk -and $word.value.key -ceq ("confirmed/" + $o.value.offer)) "for a trusted device, the confirmed record names its offer and device and verifies under the machine's signing key"
    $other = New-HordeRelayPairingConfirmedText -HordeHome $hh -Offer ("0" * 32) -Device $done.value.device.id
    Check ($other.state -cne "known") "and none is made naming another offer than the one that enrolled the device"

    Write-Host ""
    Write-Host "--- 2. must-refuse: unsigned, another key's signature, another horde, malformed, oversized ---" -ForegroundColor Cyan
    $stranger = New-HordeTestPhone
    $before = Get-Shape
    $cases = [ordered]@{
        "an UNSIGNED vouch" = @((New-VouchText -Phone $stranger -By $phone.keyId -Bare), "carries no signature")
        "a vouch SIGNED BY ANOTHER KEY in the trusted passkey's name" = @((New-VouchText -Phone $stranger -Signer $stranger -By $phone.keyId), "the vouch for the phone key is refused")
        "a vouch by a passkey the machine never enrolled" = @((New-VouchText -Phone $stranger), "is not a trusted device of the founder")
        "a vouch for ANOTHER HORDE" = @((New-VouchText -Phone $stranger -Signer $phone -By $phone.keyId -Horde "home"), "for the horde home, not this one")
        "a vouch not in its canonical form" = @(((New-VouchText -Phone $stranger -Signer $phone -By $phone.keyId) -replace '"horde":"work",', '"horde":"work", '), "not in its canonical form")
        "a vouch over the size cap" = @(('{"v":1,"kind":"horde-relay-phone-vouch",' + ("x" * 17000)), "over the 16384")
    }
    foreach ($name in @($cases.Keys)) {
        $in = Invoke-Inbox @($cases[$name][0])
        $r = @(Get-HordeTestMember -Object $in -Path "value.refused")
        $v = @(Get-HordeTestMember -Object $in -Path "value.vouched")
        Check ($r.Count -eq 1 -and $r[0].Contains($cases[$name][1]) -and $v.Count -eq 0 -and (Get-Shape) -ceq $before) ($name + " is refused, says why, and changes nothing (" + ($r -join " | ") + ")")
    }
    $twin = Invoke-Inbox @((New-VouchText -Phone $stranger -Signer $phone -By $phone.keyId))
    Check (@(Get-HordeTestMember -Object $twin -Path "value.vouched").Count -eq 1) "CONTROL, the must-accept twin: the stranger's key vouched for by the TRUSTED passkey itself is taken"

    Write-Host ""
    Write-Host "--- 3. a revoked passkey vouches for nothing; an unreadable store holds the item ---" -ForegroundColor Cyan
    $rv = Revoke-HordeRelayTrust -HordeHome $hh -Subject "device" -Id $done.value.device.id -Reason "lost"
    Check ($rv.state -ceq "known") "CONTROL: the passkey is revoked"
    $late = New-HordeTestPhone
    $before = Get-Shape
    $in = Invoke-Inbox @((New-VouchText -Phone $late -Signer $phone -By $phone.keyId))
    $r = @(Get-HordeTestMember -Object $in -Path "value.refused")
    Check ($r.Count -eq 1 -and $r[0].Contains("is not a trusted device") -and (Get-Shape) -ceq $before) ("a revoked passkey's vouch is refused and changes nothing (" + ($r -join " | ") + ")")
    Check (@((Find-HordeRelayPhoneKeys -HordeHome $hh).value).Count -eq 0) "and the keys it vouched for before are no longer sealed to"
    $bad = Join-Path $hh "relay\trust\devices\not-a-record.json"
    [System.IO.File]::WriteAllText($bad, "damaged", $utf8)
    $in = Invoke-Inbox @((New-VouchText -Phone $late -Signer $phone -By $phone.keyId))
    $h = @(Get-HordeTestMember -Object $in -Path "value.held")
    Check ($h.Count -eq 1 -and $h[0].Contains("the trust store cannot be read") -and @(Get-HordeTestMember -Object $in -Path "value.refused").Count -eq 0) ("a trust store that cannot be read HOLDS the item for the next turn, refusing nothing for good (" + ($h -join " | ") + ")")
    Remove-Item -LiteralPath $bad -Force
} finally {
    Close-HordeRelayRunContext -Context $script:ctx
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    $env:HORDE_HOME = $realHome
    foreach ($k in @($keysMade)) { try { [void](Remove-HordeRelayKey -Name $k.n -Scope $k.s) } catch { } }
    $left = @($keysMade | Where-Object { (Find-HordeRelayCngKey -Name $_.n -Scope $_.s) -cne "" })
    Check (@($keysMade).Count -eq 2 -and $left.Count -eq 0) "both keys of the suite's identity are gone"
    if ((Split-Path -Leaf $work) -match '^horde-relay-phone-vouch-[0-9a-f]{32}$' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    Check (-not (Test-Path -LiteralPath $work)) "the suite's folder is gone"
}

Complete-HordeSuite -Success "a phone vouch item is taken only from a trusted passkey of this horde, by its own signature; pending, unsigned, forged, foreign, revoked, malformed and oversized ones are refused and change nothing; an unreadable store holds the item; the confirmed record is made only for a trusted device and verifies"
