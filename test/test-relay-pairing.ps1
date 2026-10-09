# DOES A MACHINE KNOW ITS HORDE AND ITS OWN KEYS, TRUST ONLY WHAT IT ENROLLED AND NOT WHAT IT REVOKED,
# AND PAIR A PHONE ONLY THROUGH A LIVE, UNUSED OFFER?
#
# relay/Identity.ps1, relay/Trust.ps1, relay/Pairing.ps1 and relay/Records.ps1. Every Horde home here is
# a folder of the suite's own under %TEMP% (CONTRIBUTING 9), never HORDE_HOME, and every key it makes is
# named by that home's own install id and removed in the finally block, then checked gone. Keys are made
# with the software provider, except one identity made with -Provider auto to show the TPM is tried.
# The phone's side is the WebCrypto-made registrations of test/fixtures/relay/registration (with
# attestation "none" nothing in them is signed, so the suite writes each clientDataJSON around the
# offer's challenge itself), and each credential's assertion proves the enrolled key is the right one.
#
# BOTH RUNTIMES: run under powershell.exe and pwsh alike; its last section also starts the OTHER runtime
# to read an identity and a trust store made here. When the other runtime is not installed that section
# is skipped and the suite exits 3, a partial run (test/lib/Suite.ps1), never 0. Off Windows there is no
# key store (relay/Keys.ps1): the suite checks the identity says so, and exits 3.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "relay\Pairing.ps1")
Set-StrictMode -Version Latest
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + ")") -ForegroundColor DarkGray

$fx = [System.IO.File]::ReadAllText((Join-Path $here "fixtures\relay\registration\registrations.json")) | ConvertFrom-Json
$valid = @($fx.registrations | Where-Object { $_.expect -ceq "accepted" })
$noUv = @($fx.registrations | Where-Object { $_.name -clike "refused: user not verified*" })[0]
$rp = $fx.rpId
$origins = @($fx.origin)
$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$t0 = New-Object datetime -ArgumentList 2026, 10, 9, 12, 0, 0, ([System.DateTimeKind]::Utc)
$script:homes = New-Object System.Collections.ArrayList

function B { param([string]$Text) return ,(ConvertFrom-HordeRelayBase64Url -Text $Text) }
function New-TestHome {
    param([string]$Horde = "work")
    $h = Join-Path $env:TEMP ("horde-relay-pairing-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $h | Out-Null
    [void]$script:homes.Add($h)
    if ($Horde -cne "") { Set-TestHorde -HordeHome $h -Horde $Horde }
    return $h
}
function Set-TestHorde {
    param([string]$HordeHome, [string]$Horde)
    New-Item -ItemType Directory -Path (Join-Path $HordeHome "settings") -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $HordeHome "settings\relay.json"), ('{"schemaVersion": 1, "settings": {"horde": "' + $Horde + '"}}'), $utf8)
}
function Get-TestKeyNames {
    # Every key an identity record in a home names, with its scope.
    param([string]$HordeHome)
    $out = New-Object System.Collections.ArrayList
    $dir = Join-Path $HordeHome "relay\identity"
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter "machine-*.json")) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        $m = [regex]::Match($t, '"scope":"([a-z]+)","signName":"([a-z0-9-]+)".*"agreeName":"([a-z0-9-]+)"')
        if ($m.Success) { [void]$out.Add(@{ n = $m.Groups[2].Value; s = $m.Groups[1].Value }); [void]$out.Add(@{ n = $m.Groups[3].Value; s = $m.Groups[1].Value }) }
    }
    return @($out)
}
function New-Response {
    # A phone's response to an offer, from a fixture registration, with clientDataJSON written here.
    param($Offer, $Reg, [string]$Code = "", [string]$Challenge = "", [string]$Origin = $fx.origin, [string]$Type = "webauthn.create", [string]$Label = "Founder phone", [bool]$Prf = $true)
    $c = $(if ($Code -ceq "") { $Offer.code } else { $Code })
    $ch = $(if ($Challenge -ceq "") { $Offer.challenge } else { $Challenge })
    $cdj = $utf8.GetBytes('{"type":"' + $Type + '","challenge":"' + $ch + '","origin":"' + $Origin + '","crossOrigin":false}')
    return (New-HordeRelayPairingResponseText -Offer $Offer.offer -Code $c -RawId (B $Reg.rawId) -ClientDataJson $cdj -AttestationObject (B $Reg.attestationObject) -Label $Label -Prf $Prf)
}
function New-Offer {
    param([string]$HordeHome, $Now = $t0, [int]$Ttl = 300)
    $o = New-HordeRelayPairingOffer -HordeHome $HordeHome -RpId $rp -Origins $origins -TtlSeconds $Ttl -Now $Now
    if ($o.state -cne "known") { throw ("no offer: " + $o.reason) }
    return $o.value
}
function Test-Assertion {
    # Does the fixture credential's own assertion verify under a trusted sender?
    param($Sender, $Reg)
    $a = $Reg.assertion
    $v = Test-HordeRelayWebAuthnAssertion -Public $Sender.public -AuthenticatorData (B $a.authenticatorData) -ClientDataJson (B $a.clientDataJSON) -Signature (B $a.signature) `
        -Challenge (B $a.challenge) -RpId $Sender.rpId -Origins @($Sender.origins) -RequireUserVerification $Sender.requireUserVerification
    return [bool]$v.ok
}

$store = Get-HordeRelayKeyStore
if ($store.state -cne "known") {
    $h = New-TestHome
    $id = New-HordeRelayMachineIdentity -HordeHome $h
    Check ($id.state -ceq "absent" -and $id.reason.Contains("not faked")) "with no key store, the identity is absent and says no key is faked"
    Remove-Item -LiteralPath $h -Recurse -Force
    Complete-HordeSuite -Success "no key store here: said plainly" -PassCode 3
}

$partial = $false
try {
    Write-Host ""
    Write-Host "--- the horde: named by a setting, and nothing is made until it is ---" -ForegroundColor Cyan
    $hn = New-TestHome -Horde ""
    $g = Get-HordeRelayHorde -HordeHome $hn
    Check ($g.state -ceq "absent" -and $g.reason.Contains("relay.json")) ("with no setting the horde is absent, and says where to name it (" + $g.reason + ")")
    $none = New-HordeRelayMachineIdentity -HordeHome $hn -Provider "software"
    Check ($none.state -ceq "absent" -and -not (Test-Path -LiteralPath (Join-Path $hn "relay"))) "no identity is made, and nothing is written, until a horde is named"
    foreach ($bad in @("Work", "con", "-x", "a b", ("a" * 64))) {
        Set-TestHorde -HordeHome $hn -Horde $bad
        $g = Get-HordeRelayHorde -HordeHome $hn
        Check ($g.state -ceq "unknown") ("'" + $bad + "' is refused as a horde name (" + $g.reason + ")")
    }
    Set-TestHorde -HordeHome $hn -Horde "personal"
    Check ((Get-HordeRelayHorde -HordeHome $hn).value -ceq "personal") "CONTROL: 'personal' names a horde"

    Write-Host ""
    Write-Host "--- the machine identity: made once, pinned, per Horde home ---" -ForegroundColor Cyan
    $ha = New-TestHome
    $ia = New-HordeRelayMachineIdentity -HordeHome $ha -Provider "software" -Now $t0
    Check ($ia.state -ceq "known") ("the identity is made (" + $(if ($ia.state -ceq "known") { "generation " + $ia.value.generation } else { $ia.reason }) + ")")
    $A = $ia.value
    Check ($A.horde -ceq "work" -and $A.generation -eq 1 -and $A.scope -ceq "user" -and $A.sign.provider -ceq "software") "generation 1 of horde work, user scope, in the provider asked for"
    Check ($A.sign.keyId -ceq (Get-HordeRelayKeyId -Public $A.sign.public) -and $A.agree.keyId -ceq (Get-HordeRelayKeyId -Public $A.agree.public) -and $A.sign.keyId -cne $A.agree.keyId) "two keys, each with the stable id of its own public point"
    Check ($A.mailbox -ceq ("work/" + $A.sign.keyId)) "its mailbox is <horde>/<signing key id>"
    Check ($A.sign.name -ceq ("horde-relay-m" + $A.install + "-g1-s") -and $A.install -cmatch '\A[0-9a-f]{16}\z') "its keys are named by this home's install id and the generation"
    $again = New-HordeRelayMachineIdentity -HordeHome $ha -Provider "software"
    Check ($again.state -ceq "unknown" -and $again.reason.Contains("made once")) "making it again is refused"
    $ga = Get-HordeRelayMachineIdentity -HordeHome $ha -Open
    Check ($ga.state -ceq "known" -and $ga.value.sign.keyId -ceq $A.sign.keyId -and $ga.value.agree.keyId -ceq $A.agree.keyId) "it loads as the same keys"
    Check (Throws { $ga.value.sign.key.ExportParameters($true) }) "its signing key's private half cannot be exported"
    $msg = Get-HordeRelayAsciiBytes -Text "signed by the loaded identity"
    Check (Test-HordeRelayEs256Signature -Public $A.sign.public -Bytes $msg -Signature (New-HordeRelayEs256Signature -Key $ga.value.sign.key -Bytes $msg)) "and the loaded key signs under the pinned public key"
    $ga.value.sign.key.Dispose(); $ga.value.agree.key.Dispose()
    $hb = New-TestHome
    $iauto = New-HordeRelayMachineIdentity -HordeHome $hb -Now $t0
    Check ($iauto.state -ceq "known" -and @("platform", "software") -ccontains $iauto.value.sign.provider) ("-Provider auto: made in " + $(if ($iauto.state -ceq "known") { $iauto.value.sign.provider + " (sign), " + $iauto.value.agree.provider + " (agree)" } else { $iauto.reason }) + ", the TPM tried first")
    $B = $iauto.value
    Check ($B.install -cne $A.install -and $B.sign.name -cne $A.sign.name) "a second Horde home on the same account has keys of its own"
    Set-TestHorde -HordeHome $ha -Horde "personal"
    $moved = Get-HordeRelayMachineIdentity -HordeHome $ha
    Check ($moved.state -ceq "unknown" -and $moved.reason.Contains("belongs to the horde 'work'")) "with the setting changed to another horde the identity is refused, not moved"
    Set-TestHorde -HordeHome $ha -Horde ""
    Check ((Get-HordeRelayMachineIdentity -HordeHome $ha).state -ceq "unknown") "and with the setting emptied too"
    Set-TestHorde -HordeHome $ha -Horde "work"
    Check ((Get-HordeRelayMachineIdentity -HordeHome $ha).state -ceq "known") "CONTROL: the setting restored, it loads again"
    # A key swapped in the store under the identity's name is refused.
    $hs = New-TestHome
    $is = New-HordeRelayMachineIdentity -HordeHome $hs -Provider "software"
    [void](Remove-HordeRelayKey -Name $is.value.agree.name)
    $gone = Get-HordeRelayMachineIdentity -HordeHome $hs
    Check ($gone.state -ceq "unknown" -and $gone.reason.Contains("gone from the user key store")) ("a missing key is unknown, not a new key (" + $gone.reason + ")")
    [void](New-HordeRelayKey -Name $is.value.agree.name -Use "agree" -Provider "software")
    $swapped = Get-HordeRelayMachineIdentity -HordeHome $hs
    Check ($swapped.state -ceq "unknown" -and $swapped.reason.Contains("not the key generation 1 pinned")) "a different key under the same name is refused"
    # Damage in the identity folder.
    $hd = New-TestHome
    [void](New-HordeRelayMachineIdentity -HordeHome $hd -Provider "software")
    $rec = Join-Path $hd "relay\identity\machine-000001.json"
    $orig = [System.IO.File]::ReadAllText($rec)
    [System.IO.File]::WriteAllText($rec, $orig.Replace('"generation":1,', '"generation":1 ,'), $utf8)
    Check ((Get-HordeRelayMachineIdentity -HordeHome $hd).reason.Contains("canonical")) "an identity record with a space in it is refused"
    [System.IO.File]::WriteAllText($rec, $orig, $utf8)
    [System.IO.File]::WriteAllText((Join-Path $hd "relay\identity\notes.txt"), "x", $utf8)
    Check ((Get-HordeRelayMachineIdentity -HordeHome $hd).reason.Contains("notes.txt")) "a file the folder does not keep refuses the identity"
    Remove-Item -LiteralPath (Join-Path $hd "relay\identity\notes.txt")
    [System.IO.File]::WriteAllText((Join-Path $hd "relay\identity\writing-0123456789abcdef0123456789abcdef.part"), "half", $utf8)
    Check ((Get-HordeRelayMachineIdentity -HordeHome $hd).state -ceq "known") "a dead writer's temporary file is passed over"

    Write-Host ""
    Write-Host "--- pairing: an offer, a registration, an enrolled device ---" -ForegroundColor Cyan
    $o1 = New-Offer -HordeHome $ha
    $ro = Read-HordeRelayPairingOffer -Text $o1.text
    Check ($ro.ok -and $ro.value.horde -ceq "work" -and $ro.value.machine -ceq $A.sign.keyId -and $ro.value.mailbox -ceq $A.mailbox -and $ro.value.agreeKeyId -ceq $A.agree.keyId) "the offer names the horde, this machine's keys and its mailbox"
    Check ($ro.value.code -ceq $o1.code -and $o1.code.Length -eq 22 -and $o1.offer -cmatch '\A[0-9a-f]{32}\z') "and carries a 128-bit code under a 128-bit offer id"
    Check ($ro.value.expiresAt - $ro.value.issuedAt -eq 300000 -and $ro.value.issuedAt -eq (ConvertTo-HordeRelayRecordMs -Time $t0)) "it lives 300 s from when it was made"
    $expectCh = ConvertTo-HordeRelayBase64Url -Bytes (Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text ("horde-relay/pairing/v1 challenge`n" + $o1.text)))
    Check ($o1.challenge -ceq $expectCh) "its challenge is SHA-256 of the domain and the offer's exact text"
    Check ($o1.text.Length -lt 700) ("it is short enough for one QR code (" + $o1.text.Length + " characters)")
    $pendingText = [System.IO.File]::ReadAllText((Join-Path $ha ("relay\pairing\offers\" + $o1.offer + ".json")))
    Check (-not $pendingText.Contains($o1.code)) "the machine keeps the code's hash, not the code"
    Check ((New-HordeRelayPairingOffer -HordeHome $ha -RpId $rp -Origins $origins -TtlSeconds 10).reason.Contains("30 to 900")) "an offer of 10 s is refused"
    Check ((New-HordeRelayPairingOffer -HordeHome $ha -RpId $rp -Origins @("https://evil.example.test")).reason.Contains("cannot make passkeys")) "an origin that cannot make passkeys for the rpId is refused"
    Check ((New-HordeRelayPairingOffer -HordeHome $hn -RpId $rp -Origins $origins).state -ceq "absent") "a machine with no identity makes no offer"

    $done = Complete-HordeRelayPairing -HordeHome $ha -Response (New-Response -Offer $o1 -Reg $valid[0]) -Now $t0.AddSeconds(60)
    Check ($done.ok) ("a valid response within the offer's life enrolls the device (" + $done.reason + ")")
    $dev = $done.value.device
    Check ($dev.label -ceq "Founder phone" -and $dev.prf -eq $true -and $dev.backupEligible -eq $true -and $dev.offer -ceq $o1.offer -and $dev.rpId -ceq $rp) "the device record keeps its label, PRF flag, backup eligibility, offer and relying party"
    Check ($dev.publicKey -ceq $valid[0].publicKey -and $dev.credentialId -ceq $valid[0].credentialId) "and the key and credential id the phone made"
    Check ($done.value.fingerprint -cmatch '\A[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}\z' -and $done.value.fingerprint -ceq (Get-HordeRelayPairingFingerprint -Public (B $valid[0].publicKey))) ("a fingerprint both screens can show (" + $done.value.fingerprint + ")")
    $senders = Find-HordeRelayTrustedSenders -HordeHome $ha
    $s0 = $(if ($senders.state -ceq "known" -and $senders.value.ContainsKey($dev.keyId)) { $senders.value[$dev.keyId] } else { $null })
    Check ($null -ne $s0 -and $s0.proof -ceq "webauthn" -and $s0.requireUserVerification -and $s0.rpId -ceq $rp) "the device is a trusted passkey sender, user verification required"
    Check ($null -ne $s0 -and (Test-Assertion -Sender $s0 -Reg $valid[0])) "and an assertion the phone's credential signed verifies under it"
    Check ($null -ne $s0 -and -not (Test-Assertion -Sender $s0 -Reg $valid[1])) "CONTROL: another credential's assertion does not"

    Write-Host ""
    Write-Host "--- replay and reuse ---" -ForegroundColor Cyan
    $rep = Complete-HordeRelayPairing -HordeHome $ha -Response (New-Response -Offer $o1 -Reg $valid[0]) -Now $t0.AddSeconds(61)
    Check ((-not $rep.ok) -and $rep.reason.Contains("already used")) "the same response again is refused as a replay"
    $reuse = Complete-HordeRelayPairing -HordeHome $ha -Response (New-Response -Offer $o1 -Reg $valid[1]) -Now $t0.AddSeconds(62)
    Check ((-not $reuse.ok) -and $reuse.reason.Contains("already used")) "the used offer and code with another passkey are refused: one offer, one device"
    $o2 = New-Offer -HordeHome $ha
    $dupe = Complete-HordeRelayPairing -HordeHome $ha -Response (New-Response -Offer $o2 -Reg $valid[0]) -Now $t0.AddSeconds(10)
    Check ((-not $dupe.ok) -and $dupe.reason.Contains("already enrolled")) "an enrolled credential is not enrolled again through a new offer"
    $o2b = Complete-HordeRelayPairing -HordeHome $ha -Response (New-Response -Offer $o2 -Reg $valid[1] -Label "Tablet") -Now $t0.AddSeconds(11)
    Check ($o2b.ok) "CONTROL: that refusal did not use the offer; another passkey enrolls through it"

    Write-Host ""
    Write-Host "--- refused responses enroll nothing and leave the offer usable ---" -ForegroundColor Cyan
    $o3 = New-Offer -HordeHome $ha
    $o4 = New-Offer -HordeHome $ha
    $refusals = @(
        @{ what = "the wrong code"; r = (New-Response -Offer $o3 -Reg $valid[2] -Code $o4.code); want = "code is not this offer's" },
        @{ what = "a registration made for another offer's challenge"; r = (New-Response -Offer $o3 -Reg $valid[2] -Challenge $o4.challenge); want = "challenge" },
        @{ what = "another origin"; r = (New-Response -Offer $o3 -Reg $valid[2] -Origin "https://evil.example.test"); want = "origin" },
        @{ what = "an assertion's client data"; r = (New-Response -Offer $o3 -Reg $valid[2] -Type "webauthn.get"); want = "webauthn.create" },
        @{ what = "a passkey made without user verification"; r = (New-Response -Offer $o3 -Reg $noUv); want = "user verification" },
        @{ what = "a response with a space in it"; r = (New-Response -Offer $o3 -Reg $valid[2]).Replace(',"prf"', ', "prf"'); want = "canonical" },
        @{ what = "a response to an offer this machine never made"; r = (New-Response -Offer $o3 -Reg $valid[2]).Replace($o3.offer, ("0" * 32)); want = "no pairing offer" }
    )
    foreach ($x in $refusals) {
        $ans = Complete-HordeRelayPairing -HordeHome $ha -Response $x.r -Now $t0.AddSeconds(30)
        Check ((-not $ans.ok) -and $ans.reason.Contains($x.want)) ($x.what + " is refused (" + $ans.reason + ")")
    }
    foreach ($bad in @($fx.registrations | Where-Object { $_.expect -cne "accepted" } | Select-Object -First 6)) {
        $ans = Complete-HordeRelayPairing -HordeHome $ha -Response (New-Response -Offer $o3 -Reg $bad) -Now $t0.AddSeconds(30)
        Check ((-not $ans.ok) -and $ans.reason.Contains($bad.expect)) ("through pairing too: " + $bad.name)
    }
    Check (-not (Test-Path -LiteralPath (Join-Path $ha ("relay\pairing\used\" + $o3.offer + ".json")))) "none of them marked the offer used"
    $after = Complete-HordeRelayPairing -HordeHome $ha -Response (New-Response -Offer $o3 -Reg $valid[2]) -Now $t0.AddSeconds(31)
    Check ($after.ok) "CONTROL: the right response still enrolls through it"
    Check ((Complete-HordeRelayPairing -HordeHome $ha -Response (New-Response -Offer $o4 -Reg $valid[3]) -Now $t0.AddSeconds(301)).reason.Contains("expired")) "a response after the offer expired is refused"
    Check ((Complete-HordeRelayPairing -HordeHome $ha -Response (New-Response -Offer $o4 -Reg $valid[3]) -Now $t0.AddSeconds(300)).ok) "CONTROL: at its last millisecond it is not expired"

    Write-Host ""
    Write-Host "--- revocation: written beside the entry, honoured by every find ---" -ForegroundColor Cyan
    $before = (Find-HordeRelayTrustedSenders -HordeHome $ha).value
    Check ($before.Count -eq 4) ("CONTROL: four devices are trusted before (" + $before.Count + ")")
    $rv = Revoke-HordeRelayTrust -HordeHome $ha -Subject "device" -Id $dev.id -Reason "lost phone" -Now $t0.AddMinutes(5)
    Check ($rv.state -ceq "known" -and -not $rv.value.already -and $rv.value.revocation.keyId -ceq $dev.keyId) "the device is revoked, by its id, naming its key"
    Check (Test-Path -LiteralPath (Join-Path $ha ("relay\trust\devices\" + $dev.id + ".json"))) "its record is kept: revocation is a record beside it, not a deletion"
    $afterRev = (Find-HordeRelayTrustedSenders -HordeHome $ha).value
    Check ($afterRev.Count -eq 3 -and -not $afterRev.ContainsKey($dev.keyId)) "the revoked device is not among the trusted senders"
    $one = Find-HordeRelayTrustedSender -HordeHome $ha -KeyId $dev.keyId
    Check ($one.state -ceq "absent" -and $one.reason.Contains("revoked") -and $one.reason.Contains("lost phone")) ("asked for by key id it is refused, saying when and why (" + $one.reason + ")")
    Check ((Find-HordeRelayTrustedSender -HordeHome $ha -KeyId $o2b.value.device.keyId).state -ceq "known") "CONTROL: another device is still found"
    $twice = Revoke-HordeRelayTrust -HordeHome $ha -Subject "device" -Id $dev.id -Reason "again" -Now $t0.AddMinutes(6)
    Check ($twice.state -ceq "known" -and $twice.value.already -and $twice.value.revocation.reason -ceq "lost phone") "revoking twice is already done, and the first record stands"
    $o5 = New-Offer -HordeHome $ha
    $back = Complete-HordeRelayPairing -HordeHome $ha -Response (New-Response -Offer $o5 -Reg $valid[0]) -Now $t0.AddSeconds(5)
    Check ((-not $back.ok) -and $back.reason.Contains("revoked")) "a revoked credential is never enrolled again"
    $list = Get-HordeRelayTrust -HordeHome $ha
    Check ($list.state -ceq "known" -and @($list.value.devices).Count -eq 4 -and @($list.value.devices | Where-Object { $null -ne $_.revoked }).Count -eq 1) "the list shows every device, the revoked one marked"
    Check ((Revoke-HordeRelayTrust -HordeHome $ha -Subject "device" -Id ("f" * 32) -Reason "x").state -ceq "absent") "revoking what the store does not hold is absent"
    Check ((Revoke-HordeRelayTrust -HordeHome $ha -Subject "device" -Id $o2b.value.device.id -Reason "").state -ceq "unknown") "a revocation needs a reason"

    Write-Host ""
    Write-Host "--- peer machines of the same horde, by card ---" -ForegroundColor Cyan
    $cardB = Export-HordeRelayMachineCard -HordeHome $hb -Label "Desk box" -Now $t0
    Check ($cardB.state -ceq "known" -and (Read-HordeRelayMachineCard -Text $cardB.value).ok) "a machine exports a card that reads back, proof verified"
    $addB = Add-HordeRelayTrustedMachine -HordeHome $ha -Card $cardB.value -Now $t0
    Check ($addB.state -ceq "known" -and -not $addB.value.duplicate -and $addB.value.record.keyId -ceq $B.sign.keyId) "the peer is added by its signing key id"
    $sB = (Find-HordeRelayTrustedSenders -HordeHome $ha).value
    Check ($sB.ContainsKey($B.sign.keyId) -and $sB[$B.sign.keyId].proof -ceq "es256") "and is a trusted ES256 sender"
    Check ((Add-HordeRelayTrustedMachine -HordeHome $ha -Card $cardB.value).value.duplicate) "adding the same card again is a duplicate, not an error"
    $own = Export-HordeRelayMachineCard -HordeHome $ha -Label "Me"
    Check ((Add-HordeRelayTrustedMachine -HordeHome $ha -Card $own.value).reason.Contains("own")) "a machine does not add its own card"
    $hp = New-TestHome -Horde "personal"
    [void](New-HordeRelayMachineIdentity -HordeHome $hp -Provider "software")
    $cardP = Export-HordeRelayMachineCard -HordeHome $hp -Label "Home box"
    Check ((Add-HordeRelayTrustedMachine -HordeHome $ha -Card $cardP.value).reason.Contains("horde 'personal'")) "a card from another horde is refused"
    Check ((Add-HordeRelayTrustedMachine -HordeHome $ha -Card $cardB.value.Replace('"label":"Desk box"', '"label":"Desk boX"')).reason.Contains("proof")) "a card whose label was changed after signing is refused"
    $forgedKey = $cardB.value.Replace($B.agree.keyId, $A.agree.keyId)
    Check (-not (Read-HordeRelayMachineCard -Text $forgedKey).ok) "a card naming another agreement key id is refused"
    Check ((Add-HordeRelayTrustedMachine -HordeHome $ha -Card "{}").reason.Contains("canonical")) "a card that is not one is refused"
    $rm = Revoke-HordeRelayTrust -HordeHome $ha -Subject "machine" -Id $B.sign.keyId -Reason "decommissioned"
    Check ($rm.state -ceq "known" -and -not (Find-HordeRelayTrustedSenders -HordeHome $ha).value.ContainsKey($B.sign.keyId)) "a revoked peer is not a trusted sender"
    Check ((Add-HordeRelayTrustedMachine -HordeHome $ha -Card $cardB.value).reason.Contains("revoked")) "and its card is never added again"

    Write-Host ""
    Write-Host "--- rotation: a new generation, a new stream, the old one retired on record ---" -ForegroundColor Cyan
    $oStale = New-Offer -HordeHome $ha
    $rot = Update-HordeRelayMachineIdentity -HordeHome $ha -Reason "scheduled rotation" -Provider "software" -Now $t0.AddDays(1)
    Check ($rot.state -ceq "known" -and $rot.value.previous -eq 1 -and $rot.value.identity.generation -eq 2) ("rotated from generation 1 to 2 (" + $(if ($rot.state -ceq "known") { "cleanup: '" + $rot.value.cleanup + "'" } else { $rot.reason }) + ")")
    $A2 = $rot.value.identity
    Check ($A2.sign.keyId -cne $A.sign.keyId -and $A2.agree.keyId -cne $A.agree.keyId -and $A2.mailbox -cne $A.mailbox) "the new keys have new ids, so new streams and a new mailbox"
    Check (@($A2.retired) -contains 1 -and @($A2.unretired).Count -eq 0 -and @($rot.value.vouched) -contains 1) "generation 1 is retired, vouched for by its own key"
    Check ((Get-HordeRelayKey -Name $A.sign.name -Use "sign").state -ceq "absent" -and (Get-HordeRelayKey -Name $A.agree.name -Use "agree").state -ceq "absent") "and its keys are gone from the store"
    $ret = Get-HordeRelayRetirementText -HordeHome $ha -Generation 1
    Check ($ret.state -ceq "known" -and $ret.value.Contains($A2.sign.keyId) -and $ret.value.Contains('"reason":"scheduled rotation"')) "the retirement record names the successor and the reason"
    Check (Test-HordeRelayRetirementVouch -Text $ret.value -PublicOld $A.sign.public) "its vouch verifies under the retired signing key"
    Check (-not (Test-HordeRelayRetirementVouch -Text $ret.value -PublicOld $B.sign.public)) "CONTROL: and under no other key"
    Check (-not (Test-HordeRelayRetirementVouch -Text $ret.value.Replace("scheduled rotation", "scheduled rotatiom") -PublicOld $A.sign.public)) "a retirement record changed after it was vouched for does not verify"
    $stale = Complete-HordeRelayPairing -HordeHome $ha -Response (New-Response -Offer $oStale -Reg $valid[4]) -Now $t0.AddSeconds(20)
    Check ((-not $stale.ok) -and $stale.reason.Contains("changed since the offer")) "an offer made before the rotation is void"
    Check ((Find-HordeRelayTrustedSenders -HordeHome $ha).value.ContainsKey($o2b.value.device.keyId)) "the trust store is the machine's, not the generation's: enrolled devices stay"
    # A rotation forced by a lost key carries no vouch.
    [void](Remove-HordeRelayKey -Name $B.sign.name)
    $lost = Update-HordeRelayMachineIdentity -HordeHome $hb -Reason "signing key lost" -Provider "software"
    Check ($lost.state -ceq "known" -and @($lost.value.vouched).Count -eq 0 -and (Get-HordeRelayRetirementText -HordeHome $hb -Generation 1).value.Contains('"vouch":""')) "a rotation after the signing key was lost retires it with no vouch"
    Check ((Update-HordeRelayMachineIdentity -HordeHome $hb -Reason "bad `"quote`"").state -ceq "unknown") "a reason with a quote in it is refused"

    Write-Host ""
    Write-Host "--- a damaged trust store trusts nobody ---" -ForegroundColor Cyan
    $hx = New-TestHome
    [void](New-HordeRelayMachineIdentity -HordeHome $hx -Provider "software")
    $ox = New-Offer -HordeHome $hx
    [void](Complete-HordeRelayPairing -HordeHome $hx -Response (New-Response -Offer $ox -Reg $valid[5]) -Now $t0)
    Check ((Find-HordeRelayTrustedSenders -HordeHome $hx).value.Count -eq 1) "CONTROL: one device is trusted"
    $devFile = @(Get-ChildItem -LiteralPath (Join-Path $hx "relay\trust\devices"))[0].FullName
    $dtext = [System.IO.File]::ReadAllText($devFile)
    $offCurve = $dtext.Replace($valid[5].publicKey, ($valid[5].publicKey.Substring(0, 80) + $(if ($valid[5].publicKey.Substring(80, 1) -ceq "A") { "B" } else { "A" }) + $valid[5].publicKey.Substring(81)))
    [System.IO.File]::WriteAllText($devFile, $offCurve, $utf8)
    $dmg = Find-HordeRelayTrustedSenders -HordeHome $hx
    Check ($dmg.state -ceq "unknown" -and $dmg.reason.Contains("not a P-256 public key")) ("a device record whose key is off the curve makes the whole store unknown (" + $dmg.reason + ")")
    [System.IO.File]::WriteAllText($devFile, $dtext.Replace('"label":"Founder phone"', '"label":"Founder phone","x":1'), $utf8)
    Check ((Find-HordeRelayTrustedSenders -HordeHome $hx).state -ceq "unknown") "so does a record with a member added"
    [System.IO.File]::WriteAllText($devFile, ($dtext + " "), $utf8)
    Check ((Find-HordeRelayTrustedSenders -HordeHome $hx).state -ceq "unknown") "so does a record with a space after its end"
    [System.IO.File]::WriteAllText($devFile, $dtext, $utf8)
    Check ((Find-HordeRelayTrustedSenders -HordeHome $hx).state -ceq "known") "CONTROL: restored, the store is read again"
    $revDir = Join-Path $hx "relay\trust\revoked"
    New-Item -ItemType Directory -Path $revDir -Force | Out-Null
    $orphan = '{"v":1,"kind":"horde-relay-revocation","subject":"device","id":"' + ("a" * 32) + '","keyId":"' + ("b" * 32) + '","reason":"x","revokedAt":1}'
    [System.IO.File]::WriteAllText((Join-Path $revDir ("device-" + ("a" * 32) + ".json")), $orphan, $utf8)
    Check ((Find-HordeRelayTrustedSenders -HordeHome $hx).reason.Contains("does not hold")) "a revocation of an entry the store does not hold makes it unknown"
    Remove-Item -LiteralPath (Join-Path $revDir ("device-" + ("a" * 32) + ".json"))
    [System.IO.File]::WriteAllText((Join-Path $revDir ("device-" + ("c" * 32) + ".json")), "{", $utf8)
    Check ((Find-HordeRelayTrustedSender -HordeHome $hx -KeyId (Get-HordeRelayKeyId -Public (B $valid[5].publicKey))).state -ceq "unknown") "a revocation that cannot be read stops even a find by key id"

    Write-Host ""
    Write-Host "--- the other runtime reads what this one made ---" -ForegroundColor Cyan
    $desktop = ($PSVersionTable.PSEdition -ceq "Desktop")
    $otherName = $(if ($desktop) { "pwsh" } else { "powershell" })
    $other = Get-Command -Name $otherName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $other) {
        Write-Host ("  [SKIP] the other runtime (" + $otherName + ") is not installed here") -ForegroundColor Yellow
        $partial = $true
    } else {
        $outFile = Join-Path $ha "child.txt"
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $other.Source
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $here "fixtures\relay\pairing-child.ps1") + "`" -HordeHome `"" + $ha + "`" -Out `"" + $outFile + "`""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        [void]$psi.EnvironmentVariables.Remove("PSModulePath")
        $p = [System.Diagnostics.Process]::Start($psi)
        $errTask = $p.StandardError.ReadToEndAsync()
        $null = $p.StandardOutput.ReadToEnd()
        if (-not $p.WaitForExit(120000)) { $p.Kill() }
        $childSays = $(if (Test-Path -LiteralPath $outFile) { [System.IO.File]::ReadAllText($outFile) } else { "nothing: " + $errTask.Result })
        $want = $A2.sign.keyId + " " + $A2.agree.keyId + " " + (@((Find-HordeRelayTrustedSenders -HordeHome $ha).value.Keys | Sort-Object) -join ",")
        Check ($childSays -ceq $want) ("under " + $otherName + " the same identity and the same trusted senders are read (" + $childSays + ")")
    }
} finally {
    $made = New-Object System.Collections.ArrayList
    foreach ($h in @($script:homes)) {
        foreach ($k in @(Get-TestKeyNames -HordeHome $h)) {
            [void]$made.Add($k)
            try { [void](Remove-HordeRelayKey -Name $k.n -Scope $k.s) } catch { Write-Host ("  cleanup of " + $k.n + " failed: " + $_.Exception.Message) -ForegroundColor Yellow }
        }
    }
    $left = @($made | Where-Object { (Find-HordeRelayCngKey -Name $_.n -Scope $_.s) -cne "" })
    Check ($made.Count -ge 10 -and $left.Count -eq 0) ("every key the suite's homes name is gone (" + $made.Count + " names, " + $left.Count + " left)")
    foreach ($h in @($script:homes)) {
        if ((Split-Path -Leaf $h) -match '^horde-relay-pairing-[0-9a-f]{32}$') { Remove-Item -LiteralPath $h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Check (@($script:homes | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 0) "every temporary home is gone"
}

if ($partial) { Complete-HordeSuite -Success "identity, trust and pairing hold; the other runtime was not here to cross" -PassCode 3 }
Complete-HordeSuite -Success "a machine knows its horde and keys, trusts only what it enrolled and did not revoke, and pairs only through a live, unused offer - under both runtimes"
