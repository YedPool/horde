# DOES A MACHINE KNOW ITS HORDE AND ITS OWN KEYS, TRUST ONLY WHAT IT ENROLLED AND NOT WHAT IT REVOKED,
# AND PAIR A PHONE ONLY THROUGH A LIVE, UNUSED OFFER AND A FINGERPRINT CONFIRMED AT THE MACHINE?
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
    param([string]$HordeHome, [string]$Horde, [int]$AgreeDays = -1, [int]$ConfirmMinutes = -1)
    New-Item -ItemType Directory -Path (Join-Path $HordeHome "settings") -Force | Out-Null
    $more = $(if ($AgreeDays -ge 0) { ', "retiredAgreeKeyDays": ' + $AgreeDays } else { "" })
    if ($ConfirmMinutes -ge 0) { $more += ', "pendingConfirmMinutes": ' + $ConfirmMinutes }
    [System.IO.File]::WriteAllText((Join-Path $HordeHome "settings\relay.json"), ('{"schemaVersion": 1, "settings": {"horde": "' + $Horde + '"' + $more + '}}'), $utf8)
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

# A PASSKEY OF THE SUITE'S OWN, for flows that need assertions over challenges made at run time (a
# countersignature) or more credentials than the fixture holds. Its registration is written here byte
# by byte - attestation "none" signs nothing - and its assertions are signed with an in-memory key.
function ConvertTo-TestDer {
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
function New-TestPasskey {
    $k = New-HordeRelayP256Key -Use "ecdsa"
    return [pscustomobject]@{ key = $k; public = (ConvertTo-HordeRelayP256Public -Key $k); credentialId = (Get-HordeRelayRandomBytes -Count 32) }
}
function New-PasskeyResponse {
    param($Offer, $Passkey, [string]$Label = "Founder phone")
    $x = New-Object byte[] 32; $y = New-Object byte[] 32
    [System.Array]::Copy($Passkey.public, 1, $x, 0, 32); [System.Array]::Copy($Passkey.public, 33, $y, 0, 32)
    $cose = Join-HordeRelayBytes -Parts @((ConvertFrom-HordeRelayHex -Text "a5010203262001215820"), $x, (ConvertFrom-HordeRelayHex -Text "225820"), $y)
    $ad = Join-HordeRelayBytes -Parts @((Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text $rp)), [byte[]]@(0x45, 0, 0, 0, 0), (New-Object byte[] 16), [byte[]]@(0, 32), $Passkey.credentialId, $cose)
    $att = Join-HordeRelayBytes -Parts @((ConvertFrom-HordeRelayHex -Text "a363666d74646e6f6e656761747453746d74a0686175746844617461"), [byte[]]@(0x58, $ad.Length), $ad)
    $cdj = $utf8.GetBytes('{"type":"webauthn.create","challenge":"' + $Offer.challenge + '","origin":"' + $fx.origin + '","crossOrigin":false}')
    return (New-HordeRelayPairingResponseText -Offer $Offer.offer -Code $Offer.code -RawId $Passkey.credentialId -ClientDataJson $cdj -AttestationObject $att -Label $Label -Prf $false)
}
function New-TestAssertion {
    param($Passkey, [byte[]]$Challenge)
    $ad = Join-HordeRelayBytes -Parts @((Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text $rp)), [byte[]]@(0x05, 0, 0, 0, 1))
    $cdj = $utf8.GetBytes('{"type":"webauthn.get","challenge":"' + (ConvertTo-HordeRelayBase64Url -Bytes $Challenge) + '","origin":"' + $fx.origin + '","crossOrigin":false}')
    $sig = $Passkey.key.SignData((Join-HordeRelayBytes -Parts @($ad, (Get-HordeRelaySha256 -Bytes $cdj))), [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    return [pscustomobject]@{ authenticatorData = $ad; clientDataJson = $cdj; signature = (ConvertTo-TestDer -Sig $sig) }
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
    Check ((Get-HordeRelayMachineIdentity -HordeHome $hd).reason.Contains("'notes.txt', which is not a record this folder keeps")) "a file the folder does not keep refuses the identity, by its name"
    Remove-Item -LiteralPath (Join-Path $hd "relay\identity\notes.txt")
    [System.IO.File]::WriteAllText((Join-Path $hd "relay\identity\writing-0123456789abcdef0123456789abcdef.part"), "half", $utf8)
    Check ((Get-HordeRelayMachineIdentity -HordeHome $hd).state -ceq "known") "a dead writer's temporary file is passed over"

    Write-Host ""
    Write-Host "--- pairing: an offer, a registration, a PENDING device, a confirmation ---" -ForegroundColor Cyan
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
    Check ($dev.state -ceq "pending" -and $done.value.pendingUntil -eq ((ConvertTo-HordeRelayRecordMs -Time $t0.AddSeconds(60)) + 600000)) "it is enrolled PENDING - not trusted - for a confirm window of its own: 10 minutes from its registration"
    $fp = $done.value.fingerprint
    $fpArgs = @{ Challenge = (B $o1.challenge); Public = (B $valid[0].publicKey); CredentialId = (B $valid[0].credentialId); RpId = $rp }
    Check ($fp -cmatch '\A[0-9]{4}-[0-9]{4}-[0-9]{4}\z' -and $fp -ceq (Get-HordeRelayPairingFingerprint @fpArgs)) ("its fingerprint is 12 digits from the offer, the key, the credential id and the rpId, which the phone computes too (" + $fp + ")")
    Check ($fp -cne (Get-HordeRelayPairingFingerprint -Challenge (Get-HordeRelayRandomBytes -Count 32) -Public $fpArgs.Public -CredentialId $fpArgs.CredentialId -RpId $rp)) "CONTROL: the same key under another offer has another fingerprint"
    Check ($fp -cne (Get-HordeRelayPairingFingerprint -Challenge $fpArgs.Challenge -Public $fpArgs.Public -CredentialId (Get-HordeRelayRandomBytes -Count 32) -RpId $rp)) "the same key under another credential id has another fingerprint"
    Check ($fp -cne (Get-HordeRelayPairingFingerprint -Challenge $fpArgs.Challenge -Public $fpArgs.Public -CredentialId $fpArgs.CredentialId -RpId "other.example.test")) "and for another relying party"
    # A known answer, computed here a second way (the 8 bytes as one unsigned number, then modulo
    # 10^12): what the phone's code must also produce for these inputs.
    $kaCh = New-Object byte[] 32; for ($i = 0; $i -lt 32; $i++) { $kaCh[$i] = 0x11 }
    $kaId = New-Object byte[] 16; for ($i = 0; $i -lt 16; $i++) { $kaId[$i] = 0x22 }
    $kaPub = B $valid[0].publicKey
    $kaHash = Get-HordeRelaySha256 -Bytes (Join-HordeRelayBytes -Parts @((Get-HordeRelayAsciiBytes -Text "horde-relay/pairing/v1 fingerprint`n"), $kaCh, $kaPub, [byte[]]@(0, 16), $kaId, (Get-HordeRelayAsciiBytes -Text $rp)))
    $kaNum = [decimal]0; for ($i = 0; $i -lt 8; $i++) { $kaNum = $kaNum * 256 + [decimal]$kaHash[$i] }
    $kaDigits = ([decimal]($kaNum % [decimal]1000000000000)).ToString("000000000000")
    $kaWant = $kaDigits.Substring(0, 4) + "-" + $kaDigits.Substring(4, 4) + "-" + $kaDigits.Substring(8, 4)
    Check ((Get-HordeRelayPairingFingerprint -Challenge $kaCh -Public $kaPub -CredentialId $kaId -RpId $rp) -ceq $kaWant) ("it is the first 8 bytes of the hash, as one number, modulo 10^12 (" + $kaWant + ")")
    Check (-not (Find-HordeRelayTrustedSenders -HordeHome $ha).value.ContainsKey($dev.keyId)) "a pending device is not a trusted sender"
    $one = Find-HordeRelayTrustedSender -HordeHome $ha -KeyId $dev.keyId -Now $t0.AddSeconds(65)
    Check ($one.state -ceq "absent" -and $one.reason.Contains("pending")) ("asked for by key id it is absent, pending (" + $one.reason + ")")
    $wrongFp = $(if ($fp -ceq "0000-0000-0000") { "1111-1111-1111" } else { "0000-0000-0000" })
    # A key ground until its fingerprint matches the founder's first 8 digits (about 2^26.6 tries, too
    # slow for a suite; review of 2243720, F1) would still differ in the last 4. What the machine
    # checks is all 12: the right first 8 with any other last 4 is refused.
    $last4 = $fp.Substring(10, 4)
    $other4 = ("" + (([int]$last4 + 1) % 10000)).PadLeft(4, [char]'0')
    $grind = Confirm-HordeRelayDevice -HordeHome $ha -Id $dev.id -Fingerprint ($fp.Substring(0, 10) + $other4) -Now $t0.AddSeconds(66)
    Check ((-not $grind.ok) -and $grind.reason.Contains("fingerprint")) "a fingerprint that matches only the first 8 digits is refused"
    $wrong = Confirm-HordeRelayDevice -HordeHome $ha -Id $dev.id -Fingerprint $wrongFp -Now $t0.AddSeconds(70)
    Check ((-not $wrong.ok) -and $wrong.reason.Contains("fingerprint")) "a confirmation with another fingerprint is refused"
    Check ((Get-HordeRelayTrust -HordeHome $ha -Now $t0.AddSeconds(70)).value.devices[0].state -ceq "pending") "and the device stays pending"
    $conf = Confirm-HordeRelayDevice -HordeHome $ha -Id $dev.id -Fingerprint $fp.Replace("-", " ") -Now $t0.AddSeconds(90)
    Check ($conf.ok -and -not $conf.value.already -and $conf.value.device.state -ceq "trusted") ("the fingerprint both screens show confirms it, spaces or dash alike (" + $conf.reason + ")")
    Check ((Confirm-HordeRelayDevice -HordeHome $ha -Id $dev.id -Fingerprint $fp -Now $t0.AddSeconds(95)).value.already) "confirming again is already done"
    $senders = Find-HordeRelayTrustedSenders -HordeHome $ha
    $s0 = $(if ($senders.state -ceq "known" -and $senders.value.ContainsKey($dev.keyId)) { $senders.value[$dev.keyId] } else { $null })
    Check ($null -ne $s0 -and $s0.proof -ceq "webauthn" -and $s0.requireUserVerification -and $s0.rpId -ceq $rp) "confirmed, the device is a trusted passkey sender, user verification required"
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
    Check ((Confirm-HordeRelayDevice -HordeHome $ha -Id $o2b.value.device.id -Fingerprint $o2b.value.fingerprint -Now $t0.AddSeconds(12)).ok) "CONTROL: and is confirmed"

    Write-Host ""
    Write-Host "--- a thief who registers first leaves a pending device the founder sees and rejects ---" -ForegroundColor Cyan
    $ht = New-TestHome
    [void](New-HordeRelayMachineIdentity -HordeHome $ht -Provider "software")
    $oT = New-Offer -HordeHome $ht
    $pkThief = New-TestPasskey
    $pkFounder = New-TestPasskey
    $thief = Complete-HordeRelayPairing -HordeHome $ht -Response (New-PasskeyResponse -Offer $oT -Passkey $pkThief) -Now $t0.AddSeconds(10)
    Check ($thief.ok -and $thief.value.device.state -ceq "pending") "a photo of the offer lets a thief register first - as a pending device"
    $mine = Complete-HordeRelayPairing -HordeHome $ht -Response (New-PasskeyResponse -Offer $oT -Passkey $pkFounder) -Now $t0.AddSeconds(20)
    Check ((-not $mine.ok) -and $mine.reason.Contains("already used") -and $mine.reason.Contains($thief.value.device.id) -and $mine.reason.Contains($thief.value.fingerprint) -and $mine.reason.Contains("pending")) ("the founder's own attempt is refused, naming the earlier pending device and its fingerprint (" + $mine.reason + ")")
    Check ($null -ne $mine.value -and $mine.value.earlier.id -ceq $thief.value.device.id) "and hands it back, so it can be rejected"
    $founderFp = Get-HordeRelayPairingFingerprint -Challenge (B $oT.challenge) -Public $pkFounder.public -CredentialId $pkFounder.credentialId -RpId $rp
    Check ($founderFp -cne $thief.value.fingerprint) "the founder's phone shows another fingerprint than the thief's device"
    Check (-not (Confirm-HordeRelayDevice -HordeHome $ht -Id $thief.value.device.id -Fingerprint $founderFp -Now $t0.AddSeconds(30)).ok) "so the thief's device cannot be confirmed with what the founder's phone shows"
    $rej = Revoke-HordeRelayTrust -HordeHome $ht -Subject "device" -Id $thief.value.device.id -Reason "not mine" -Now $t0.AddSeconds(31)
    Check ($rej.state -ceq "known") "the founder rejects the pending device by revoking it"
    $late = Confirm-HordeRelayDevice -HordeHome $ht -Id $thief.value.device.id -Fingerprint $thief.value.fingerprint -Now $t0.AddSeconds(32)
    Check ((-not $late.ok) -and $late.reason.Contains("revoked")) "and then not even its own fingerprint confirms it"
    Check ((Get-HordeRelayTrust -HordeHome $ht -Now $t0.AddSeconds(33)).value.devices[0].state -ceq "revoked") "it is listed as revoked"
    # The confirm window runs from the registration, not from the offer: a phone that registers in the
    # offer's last seconds still has the whole window.
    $oE = New-Offer -HordeHome $ht
    $pkE = New-TestPasskey
    $pe = Complete-HordeRelayPairing -HordeHome $ht -Response (New-PasskeyResponse -Offer $oE -Passkey $pkE) -Now $t0.AddSeconds(290)
    Check ($pe.ok -and $pe.value.pendingUntil -eq ((ConvertTo-HordeRelayRecordMs -Time $t0.AddSeconds(290)) + 600000)) "registered 10 s before the offer expires, it is pending for the full 10 minutes"
    $exp = Confirm-HordeRelayDevice -HordeHome $ht -Id $pe.value.device.id -Fingerprint $pe.value.fingerprint -Now $t0.AddSeconds(891)
    Check ((-not $exp.ok) -and $exp.reason.Contains("expired")) "a confirmation after its window is refused"
    $expDev = @((Get-HordeRelayTrust -HordeHome $ht -Now $t0.AddSeconds(891)).value.devices | Where-Object { $_.id -ceq $pe.value.device.id })[0]
    Check ($expDev.state -ceq "expired") "and the device is listed as expired"
    Check ((Find-HordeRelayTrustedSender -HordeHome $ht -KeyId $expDev.keyId -Now $t0.AddSeconds(891)).reason.Contains("never confirmed")) "asked for, it was never confirmed"
    $oE2 = New-Offer -HordeHome $ht
    $pkE2 = New-TestPasskey
    $pe2 = Complete-HordeRelayPairing -HordeHome $ht -Response (New-PasskeyResponse -Offer $oE2 -Passkey $pkE2) -Now $t0.AddSeconds(290)
    Check ((Confirm-HordeRelayDevice -HordeHome $ht -Id $pe2.value.device.id -Fingerprint $pe2.value.fingerprint -Now $t0.AddSeconds(890)).ok) "CONTROL: at its window's last millisecond, long after the offer expired, it still confirms"
    Set-TestHorde -HordeHome $ht -Horde "work" -ConfirmMinutes 1
    $oE3 = New-Offer -HordeHome $ht
    $pe3 = Complete-HordeRelayPairing -HordeHome $ht -Response (New-PasskeyResponse -Offer $oE3 -Passkey (New-TestPasskey)) -Now $t0.AddSeconds(10)
    Check ($pe3.ok -and $pe3.value.pendingUntil -eq ((ConvertTo-HordeRelayRecordMs -Time $t0.AddSeconds(10)) + 60000)) "the window is the setting pendingConfirmMinutes"
    $oE4 = New-Offer -HordeHome $ht
    Set-TestHorde -HordeHome $ht -Horde "work" -ConfirmMinutes 31
    $pe4 = Complete-HordeRelayPairing -HordeHome $ht -Response (New-PasskeyResponse -Offer $oE4 -Passkey (New-TestPasskey)) -Now $t0.AddSeconds(10)
    Check ((-not $pe4.ok) -and $pe4.reason.Contains("pendingConfirmMinutes") -and -not (Test-Path -LiteralPath (Join-Path $ht ("relay\pairing\used\" + $oE4.offer + ".json")))) "a window over 30 minutes is refused, and the offer is not used"
    Set-TestHorde -HordeHome $ht -Horde "work"
    Check ((Confirm-HordeRelayDevice -HordeHome $ht -Id ("e" * 32) -Fingerprint "0000-0000-0000").reason.Contains("no device")) "confirming a device the store does not hold is refused"

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
    [void](Confirm-HordeRelayDevice -HordeHome $ha -Id $after.value.device.id -Fingerprint $after.value.fingerprint -Now $t0.AddSeconds(32))
    Check ((Complete-HordeRelayPairing -HordeHome $ha -Response (New-Response -Offer $o4 -Reg $valid[3]) -Now $t0.AddSeconds(301)).reason.Contains("expired")) "a response after the offer expired is refused"
    Check ((Complete-HordeRelayPairing -HordeHome $ha -Response (New-Response -Offer $o4 -Reg $valid[3]) -Now $t0.AddSeconds(300)).ok) "CONTROL: at its last millisecond it is not expired"

    Write-Host ""
    Write-Host "--- revocation: written beside the entry, honoured by every find ---" -ForegroundColor Cyan
    $before = (Find-HordeRelayTrustedSenders -HordeHome $ha).value
    Check ($before.Count -eq 3) ("CONTROL: three devices are trusted before; the fourth was never confirmed (" + $before.Count + ")")
    $rv = Revoke-HordeRelayTrust -HordeHome $ha -Subject "device" -Id $dev.id -Reason "lost phone" -Now $t0.AddMinutes(5)
    Check ($rv.state -ceq "known" -and -not $rv.value.already -and $rv.value.revocation.keyId -ceq $dev.keyId) "the device is revoked, by its id, naming its key"
    Check (Test-Path -LiteralPath (Join-Path $ha ("relay\trust\devices\" + $dev.id + ".json"))) "its record is kept: revocation is a record beside it, not a deletion"
    $afterRev = (Find-HordeRelayTrustedSenders -HordeHome $ha).value
    Check ($afterRev.Count -eq 2 -and -not $afterRev.ContainsKey($dev.keyId)) "the revoked device is not among the trusted senders"
    $one = Find-HordeRelayTrustedSender -HordeHome $ha -KeyId $dev.keyId
    Check ($one.state -ceq "absent" -and $one.reason.Contains("revoked") -and $one.reason.Contains("lost phone")) ("asked for by key id it is refused, saying when and why (" + $one.reason + ")")
    Check ((Find-HordeRelayTrustedSender -HordeHome $ha -KeyId $o2b.value.device.keyId).state -ceq "known") "CONTROL: another device is still found"
    $twice = Revoke-HordeRelayTrust -HordeHome $ha -Subject "device" -Id $dev.id -Reason "again" -Now $t0.AddMinutes(6)
    Check ($twice.state -ceq "known" -and $twice.value.already -and $twice.value.revocation.reason -ceq "lost phone") "revoking twice is already done, and the first record stands"
    $o5 = New-Offer -HordeHome $ha
    $back = Complete-HordeRelayPairing -HordeHome $ha -Response (New-Response -Offer $o5 -Reg $valid[0]) -Now $t0.AddSeconds(5)
    Check ((-not $back.ok) -and $back.reason.Contains("revoked")) "a revoked credential is never enrolled again"
    $list = Get-HordeRelayTrust -HordeHome $ha -Now $t0.AddMinutes(16)
    Check ($list.state -ceq "known" -and @($list.value.devices).Count -eq 4 -and @($list.value.devices | Where-Object { $_.state -ceq "revoked" }).Count -eq 1 -and @($list.value.devices | Where-Object { $_.state -ceq "expired" }).Count -eq 1) "the list shows every device with its state: revoked, expired and trusted"
    Check ((Revoke-HordeRelayTrust -HordeHome $ha -Subject "device" -Id ("f" * 32) -Reason "x").state -ceq "absent") "revoking what the store does not hold is absent"
    Check ((Revoke-HordeRelayTrust -HordeHome $ha -Subject "device" -Id $o2b.value.device.id -Reason "").state -ceq "unknown") "a revocation needs a reason"

    Write-Host ""
    Write-Host "--- peer machines of the same horde: a card, then a founder passkey's countersignature ---" -ForegroundColor Cyan
    $cardB = Export-HordeRelayMachineCard -HordeHome $hb -Label "Desk box" -Now $t0
    Check ($cardB.state -ceq "known" -and (Read-HordeRelayMachineCard -Text $cardB.value).ok) "a machine exports a card that reads back, proof verified"
    $addB = Add-HordeRelayPeerMachine -HordeHome $ha -Card $cardB.value -Now $t0
    Check ($addB.state -ceq "known" -and -not $addB.value.duplicate -and $addB.value.record.keyId -ceq $B.sign.keyId -and $addB.value.record.state -ceq "pending") "the peer is added by its signing key id - pending, a self-signed card alone"
    Check (-not (Find-HordeRelayTrustedSenders -HordeHome $ha).value.ContainsKey($B.sign.keyId)) "a pending peer is not a trusted sender"
    Check ((Find-HordeRelayTrustedSender -HordeHome $ha -KeyId $B.sign.keyId).reason.Contains("countersign")) "asked for, it waits for a countersignature"
    $chB = Get-HordeRelayCardChallenge -Card $cardB.value
    Check ((ConvertTo-HordeRelayHex -Bytes $chB) -ceq (ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text ("horde-relay/machine-card/v1 countersign`n" + $cardB.value))))) "the challenge a passkey signs is SHA-256 of the domain and the card's exact text"
    $oF = New-Offer -HordeHome $ha
    $pkF = New-TestPasskey
    $pf = Complete-HordeRelayPairing -HordeHome $ha -Response (New-PasskeyResponse -Offer $oF -Passkey $pkF -Label "Countersigner") -Now $t0.AddSeconds(5)
    $pkP = New-TestPasskey
    $oP = New-Offer -HordeHome $ha
    [void](Complete-HordeRelayPairing -HordeHome $ha -Response (New-PasskeyResponse -Offer $oP -Passkey $pkP -Label "Pending phone") -Now $t0.AddSeconds(5))
    $fKey = Get-HordeRelayKeyId -Public $pkF.public
    $pKey = Get-HordeRelayKeyId -Public $pkP.public
    $asB = New-TestAssertion -Passkey $pkF -Challenge $chB
    $byPending = Confirm-HordeRelayPeerMachine -HordeHome $ha -KeyId $B.sign.keyId -By $pKey -AuthenticatorData $asB.authenticatorData -ClientDataJson $asB.clientDataJson -Signature $asB.signature -Now $t0.AddSeconds(6)
    Check ($byPending.state -ceq "unknown" -and $byPending.reason.Contains("not a trusted device")) "a countersignature by a device that is only pending is refused"
    Check ((Confirm-HordeRelayPeerMachine -HordeHome $ha -KeyId $B.sign.keyId -By ("d" * 32) -AuthenticatorData $asB.authenticatorData -ClientDataJson $asB.clientDataJson -Signature $asB.signature).reason.Contains("not a trusted device")) "and by a key the store does not hold"
    [void](Confirm-HordeRelayDevice -HordeHome $ha -Id $pf.value.device.id -Fingerprint $pf.value.fingerprint -Now $t0.AddSeconds(6))
    $asOther = New-TestAssertion -Passkey $pkF -Challenge (Get-HordeRelayRandomBytes -Count 32)
    $wrongCh = Confirm-HordeRelayPeerMachine -HordeHome $ha -KeyId $B.sign.keyId -By $fKey -AuthenticatorData $asOther.authenticatorData -ClientDataJson $asOther.clientDataJson -Signature $asOther.signature -Now $t0.AddSeconds(7)
    Check ($wrongCh.state -ceq "unknown" -and $wrongCh.reason.Contains("challenge")) "an assertion over anything but this card is refused"
    $asP = New-TestAssertion -Passkey $pkP -Challenge $chB
    Check ((Confirm-HordeRelayPeerMachine -HordeHome $ha -KeyId $B.sign.keyId -By $fKey -AuthenticatorData $asP.authenticatorData -ClientDataJson $asP.clientDataJson -Signature $asP.signature).reason.Contains("does not verify")) "an assertion by another passkey, named as the trusted one, is refused"
    $cs = Confirm-HordeRelayPeerMachine -HordeHome $ha -KeyId $B.sign.keyId -By $fKey -AuthenticatorData $asB.authenticatorData -ClientDataJson $asB.clientDataJson -Signature $asB.signature -Now $t0.AddSeconds(8)
    Check ($cs.state -ceq "known" -and -not $cs.value.already -and $cs.value.record.state -ceq "trusted") ("a trusted founder passkey's assertion over the card makes the peer trusted (" + $cs.reason + ")")
    $sB = (Find-HordeRelayTrustedSenders -HordeHome $ha).value
    Check ($sB.ContainsKey($B.sign.keyId) -and $sB[$B.sign.keyId].proof -ceq "es256") "and a trusted ES256 sender"
    Check ((Confirm-HordeRelayPeerMachine -HordeHome $ha -KeyId $B.sign.keyId -By $fKey -AuthenticatorData $asB.authenticatorData -ClientDataJson $asB.clientDataJson -Signature $asB.signature).value.already) "countersigning again is already done"
    Check ((Add-HordeRelayPeerMachine -HordeHome $ha -Card $cardB.value).value.duplicate) "adding the same card again is a duplicate, not an error"
    $own = Export-HordeRelayMachineCard -HordeHome $ha -Label "Me"
    Check ((Add-HordeRelayPeerMachine -HordeHome $ha -Card $own.value).reason.Contains("own")) "a machine does not add its own card"
    $hp = New-TestHome -Horde "personal"
    [void](New-HordeRelayMachineIdentity -HordeHome $hp -Provider "software")
    $cardP = Export-HordeRelayMachineCard -HordeHome $hp -Label "Home box"
    Check ((Add-HordeRelayPeerMachine -HordeHome $ha -Card $cardP.value).reason.Contains("horde 'personal'")) "a card from another horde is refused"
    Check ((Add-HordeRelayPeerMachine -HordeHome $ha -Card $cardB.value.Replace('"label":"Desk box"', '"label":"Desk boX"')).reason.Contains("proof")) "a card whose label was changed after signing is refused"
    $forgedKey = $cardB.value.Replace($B.agree.keyId, $A.agree.keyId)
    Check (-not (Read-HordeRelayMachineCard -Text $forgedKey).ok) "a card naming another agreement key id is refused"
    Check ((Add-HordeRelayPeerMachine -HordeHome $ha -Card "{}").reason.Contains("canonical")) "a card that is not one is refused"
    [void](Revoke-HordeRelayTrust -HordeHome $ha -Subject "device" -Id $pf.value.device.id -Reason "countersigner lost")
    $peerNow = @((Get-HordeRelayTrust -HordeHome $ha).value.machines | Where-Object { $_.keyId -ceq $B.sign.keyId })[0]
    Check ($peerNow.state -ceq "pending" -and -not (Find-HordeRelayTrustedSenders -HordeHome $ha).value.ContainsKey($B.sign.keyId)) "when the countersigning passkey is revoked, the peer it vouched for is pending again"
    $rm = Revoke-HordeRelayTrust -HordeHome $ha -Subject "machine" -Id $B.sign.keyId -Reason "decommissioned"
    Check ($rm.state -ceq "known" -and -not (Find-HordeRelayTrustedSenders -HordeHome $ha).value.ContainsKey($B.sign.keyId)) "a revoked peer is not a trusted sender"
    Check ((Add-HordeRelayPeerMachine -HordeHome $ha -Card $cardB.value).reason.Contains("revoked")) "and its card is never added again"

    Write-Host ""
    Write-Host "--- rotation: a new generation, a new stream, the old one retired on record ---" -ForegroundColor Cyan
    $oStale = New-Offer -HordeHome $ha
    $tRot = $t0.AddDays(1)
    $rot = Update-HordeRelayMachineIdentity -HordeHome $ha -Reason "scheduled rotation" -Provider "software" -Now $tRot
    Check ($rot.state -ceq "known" -and $rot.value.previous -eq 1 -and $rot.value.identity.generation -eq 2) ("rotated from generation 1 to 2 (" + $(if ($rot.state -ceq "known") { "cleanup: '" + $rot.value.cleanup + "'" } else { $rot.reason }) + ")")
    $A2 = $rot.value.identity
    Check ($A2.sign.keyId -cne $A.sign.keyId -and $A2.agree.keyId -cne $A.agree.keyId -and $A2.mailbox -cne $A.mailbox) "the new keys have new ids, so new streams and a new mailbox"
    Check (@($A2.retired) -contains 1 -and @($A2.unretired).Count -eq 0 -and @($rot.value.vouched) -contains 1) "generation 1 is retired, vouched for by its own key"
    Check ((Get-HordeRelayKey -Name $A.sign.name -Use "sign").state -ceq "absent") "its signing key is gone at once"
    $keptAgree = Get-HordeRelayKey -Name $A.agree.name -Use "agree"
    Check ($keptAgree.state -ceq "known") "its agreement key is kept, for opening only"
    if ($keptAgree.state -ceq "known") { $keptAgree.value.key.Dispose() }
    $graceEnd = (ConvertTo-HordeRelayRecordMs -Time $tRot) + 7 * 86400000
    Check (@($A2.opening).Count -eq 1 -and $A2.opening[0].generation -eq 1 -and $A2.opening[0].agreeKeyId -ceq $A.agree.keyId -and $A2.opening[0].until -eq $graceEnd) "for the default grace of 7 days"
    $ret = Get-HordeRelayRetirementText -HordeHome $ha -Generation 1
    Check ($ret.state -ceq "known" -and $ret.value.Contains($A2.sign.keyId) -and $ret.value.Contains('"reason":"scheduled rotation"') -and $ret.value.Contains('"agreeKeptUntil":' + $graceEnd)) "the retirement record names the successor, the reason and the grace's end"
    Check (Test-HordeRelayRetirementVouch -Text $ret.value -PublicOld $A.sign.public) "its vouch verifies under the retired signing key"
    Check (-not (Test-HordeRelayRetirementVouch -Text $ret.value -PublicOld $B.sign.public)) "CONTROL: and under no other key"
    Check (-not (Test-HordeRelayRetirementVouch -Text $ret.value.Replace("scheduled rotation", "scheduled rotatiom") -PublicOld $A.sign.public)) "a retirement record changed after it was vouched for does not verify"
    $ok = Get-HordeRelayOpeningKeys -HordeHome $ha -Now $tRot.AddDays(2)
    Check ($ok.state -ceq "known" -and $ok.value.keys.ContainsKey($A.agree.keyId) -and $ok.value.keys.ContainsKey($A2.agree.keyId)) "the keys that open are the current agreement key and the one in its grace"
    if ($ok.state -ceq "known") {
        $box = Protect-HordeRelayHpke -RecipientPublic $A.agree.public -Info (Get-HordeRelayAsciiBytes -Text "i") -Aad (Get-HordeRelayAsciiBytes -Text "a") -Plaintext (Get-HordeRelayAsciiBytes -Text "in flight")
        $opened = Unprotect-HordeRelayHpke -RecipientKey $ok.value.keys[$A.agree.keyId] -Enc $box.enc -Info (Get-HordeRelayAsciiBytes -Text "i") -Aad (Get-HordeRelayAsciiBytes -Text "a") -Sealed $box.sealed
        Check ($null -ne $opened -and [System.Text.Encoding]::ASCII.GetString($opened) -ceq "in flight") "a message sealed to the old key before the rotation still opens"
        foreach ($k in @($ok.value.keys.Values)) { $k.Dispose() }
    }
    Check ((Read-HordeRelayPairingOffer -Text (New-Offer -HordeHome $ha -Now $tRot).text).value.agreeKeyId -ceq $A2.agree.keyId) "what the machine hands out names only the current agreement key: the old one is never sealed to again"
    $early = Remove-HordeRelayRetiredAgreeKeys -HordeHome $ha -Now (New-Object datetime -ArgumentList (($tRot.AddDays(7)).Ticks - 10000), ([System.DateTimeKind]::Utc))
    Check ($early.state -ceq "known" -and @($early.value.released).Count -eq 0 -and (Get-HordeRelayKey -Name $A.agree.name -Use "agree").state -ceq "known") "a millisecond before the grace ends the key is kept"
    Check (@((Get-HordeRelayMachineIdentity -HordeHome $ha -Now $tRot.AddDays(7)).value.opening).Count -eq 0) "at the grace's end the old key opens nothing, swept or not"
    $swept = Remove-HordeRelayRetiredAgreeKeys -HordeHome $ha -Now $tRot.AddDays(7)
    Check ($swept.state -ceq "known" -and @($swept.value.released) -contains 1 -and (Get-HordeRelayKey -Name $A.agree.name -Use "agree").state -ceq "absent") "when the grace ends the old agreement key is deleted"
    Check (Test-Path -LiteralPath (Join-Path $ha "relay\identity\released-000001.json")) "and its release is recorded"
    Check ((-not (Get-HordeRelayOpeningKeys -HordeHome $ha -Now $tRot.AddDays(8)).value.keys.ContainsKey($A.agree.keyId)) -and @((Get-HordeRelayMachineIdentity -HordeHome $ha -Now $tRot.AddDays(8)).value.opening).Count -eq 0) "and it opens nothing any more"
    Check (@((Remove-HordeRelayRetiredAgreeKeys -HordeHome $ha -Now $tRot.AddDays(9)).value.released).Count -eq 0) "sweeping again releases nothing"
    $stale = Complete-HordeRelayPairing -HordeHome $ha -Response (New-Response -Offer $oStale -Reg $valid[4]) -Now $t0.AddSeconds(20)
    Check ((-not $stale.ok) -and $stale.reason.Contains("changed since the offer")) "an offer made before the rotation is void"
    Check ((Find-HordeRelayTrustedSenders -HordeHome $ha).value.ContainsKey($o2b.value.device.keyId)) "the trust store is the machine's, not the generation's: enrolled devices stay"
    # A rotation forced by a lost key carries no vouch; a grace of 0 releases at once.
    Set-TestHorde -HordeHome $hb -Horde "work" -AgreeDays 0
    [void](Remove-HordeRelayKey -Name $B.sign.name)
    $lost = Update-HordeRelayMachineIdentity -HordeHome $hb -Reason "signing key lost" -Provider "software"
    Check ($lost.state -ceq "known" -and @($lost.value.vouched).Count -eq 0 -and (Get-HordeRelayRetirementText -HordeHome $hb -Generation 1).value.Contains('"vouch":""')) "a rotation after the signing key was lost retires it with no vouch"
    Check (@($lost.value.released) -contains 1 -and (Get-HordeRelayKey -Name $B.agree.name -Use "agree").state -ceq "absent") "with a grace of 0 days the old agreement key is released at once, on record"
    Set-TestHorde -HordeHome $hb -Horde "work" -AgreeDays 31
    Check ((Update-HordeRelayMachineIdentity -HordeHome $hb -Reason "too long a grace" -Provider "software").state -ceq "unknown") "a grace over 30 days is refused, and nothing rotates"
    Set-TestHorde -HordeHome $hb -Horde "work"
    Check ((Update-HordeRelayMachineIdentity -HordeHome $hb -Reason "bad `"quote`"").state -ceq "unknown") "a reason with a quote in it is refused"

    Write-Host ""
    Write-Host "--- a damaged trust store trusts nobody ---" -ForegroundColor Cyan
    $hx = New-TestHome
    [void](New-HordeRelayMachineIdentity -HordeHome $hx -Provider "software")
    $ox = New-Offer -HordeHome $hx
    $px = Complete-HordeRelayPairing -HordeHome $hx -Response (New-Response -Offer $ox -Reg $valid[5]) -Now $t0
    [void](Confirm-HordeRelayDevice -HordeHome $hx -Id $px.value.device.id -Fingerprint $px.value.fingerprint -Now $t0)
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
    $confDir = Join-Path $hx "relay\trust\confirmed"
    $orphanC = '{"v":1,"kind":"horde-relay-device-confirmed","id":"' + ("a" * 32) + '","keyId":"' + ("b" * 32) + '","fingerprint":"0000-0000-0000","confirmedAt":1}'
    [System.IO.File]::WriteAllText((Join-Path $confDir ("device-" + ("a" * 32) + ".json")), $orphanC, $utf8)
    Check ((Find-HordeRelayTrustedSenders -HordeHome $hx).reason.Contains("does not hold")) "a confirmation of a device the store does not hold makes it unknown"
    Remove-Item -LiteralPath (Join-Path $confDir ("device-" + ("a" * 32) + ".json"))
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
Complete-HordeSuite -Success "a machine knows its horde and keys, trusts only what it confirmed and did not revoke, and pairs only through a live, unused offer - under both runtimes"
