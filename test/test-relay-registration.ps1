# DOES THE RELAY ACCEPT A PASSKEY REGISTRATION EXACTLY WHEN IT IS ONE WE ASKED FOR, AND IMPORT THE KEY
# IT CARRIES AS THAT KEY AND NO OTHER?
#
# relay/Cbor.ps1, relay/Cose.ps1 and relay/Registration.ps1. Pairing enrolls the key a registration
# carries as a founder device, so this is where a wrong key, a key off the curve, a key with its private
# part, or a registration for another site or without user verification must stop. The registrations
# in test/fixtures/relay/registration/registrations.json were made by WebCrypto and a CBOR encoder
# written in JavaScript (make-fixtures.mjs beside them, run with Node), not by Horde; each refused case
# is wrong in one way only. Each valid case's credential also signed an assertion, verified here under
# the key the import produced: the proof that it is the right key, not merely a valid one.
# Run under powershell.exe and pwsh alike.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "relay\Registration.ps1")
Set-StrictMode -Version Latest
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + ")") -ForegroundColor DarkGray

$fx = [System.IO.File]::ReadAllText((Join-Path $here "fixtures\relay\registration\registrations.json")) | ConvertFrom-Json
$regs = @($fx.registrations)
$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$challenge = New-Object byte[] 32
for ($i = 0; $i -lt 32; $i++) { $challenge[$i] = [byte](7 * $i + 3) }
$challengeText = ConvertTo-HordeRelayBase64Url -Bytes $challenge

function B { param([string]$Text) return ,(ConvertFrom-HordeRelayBase64Url -Text $Text) }
function Hex { param([string]$Text) return ,(ConvertFrom-HordeRelayHex -Text $Text) }
function New-ClientData {
    param([string]$Type = "webauthn.create", [string]$Challenge = $challengeText, [string]$Origin = $fx.origin, [string]$Extra = ',"crossOrigin":false')
    return ,($utf8.GetBytes('{"type":"' + $Type + '","challenge":"' + $Challenge + '","origin":"' + $Origin + '"' + $Extra + '}'))
}
function Invoke-Reg {
    param($Case, [byte[]]$ClientData = $null, [string]$RpId = $fx.rpId, [string[]]$Origins = @($fx.origin), [byte[]]$RawId = $null, [byte[]]$Att = $null, [bool]$Uv = $true)
    $cd = $ClientData; if ($null -eq $cd) { $cd = New-ClientData }
    $raw = $RawId; if ($null -eq $raw) { $raw = B $Case.rawId }
    $a = $Att; if ($null -eq $a) { $a = B $Case.attestationObject }
    return (Test-HordeRelayWebAuthnRegistration -ClientDataJson $cd -AttestationObject $a -RawId $raw -Challenge $challenge -RpId $RpId -Origins $Origins -RequireUserVerification $Uv)
}

Write-Host ""
Write-Host "--- the CBOR reader: what it reads, and every spelling it refuses ---" -ForegroundColor Cyan
$r = Read-HordeRelayCbor -Bytes (Hex "a3010203262001") -Whole
Check ($r.ok -and $r.value.type -ceq "map" -and @($r.value.value).Count -eq 3) "a small map of integers is read"
Check ((Get-HordeRelayCborMember -Map $r.value -Key 3).value -eq -7 -and (Get-HordeRelayCborMember -Map $r.value -Key (-1)).value -eq 1) "its members are found by integer key, negative ones included"
Check ($null -eq (Get-HordeRelayCborMember -Map $r.value -Key "3")) "CONTROL: a text key of the same digits is another key"
$t = Read-HordeRelayCbor -Bytes (Hex "6568656c6c6f") -Whole
Check ($t.ok -and $t.value.type -ceq "text" -and $t.value.value -ceq "hello") "text is read as text"
$big = Read-HordeRelayCbor -Bytes (Hex "1b7fffffffffffffff") -Whole
Check ($big.ok -and $big.value.value -eq [long]::MaxValue) "the largest Int64 is read exactly"
Check ((Read-HordeRelayCbor -Bytes (Hex "1bffffffffffffffff")).reason.Contains("larger than")) "a larger integer is refused, not wrapped"
Check ((Read-HordeRelayCbor -Bytes (Hex "f5")).value.value -eq $true -and (Read-HordeRelayCbor -Bytes (Hex "f6")).value.type -ceq "null") "true and null are read"
$cases = @(
    @("1817", "shortest"), @("190017", "shortest"), @("1a00000100", "shortest"), @("1b00000000ffffffff", "shortest"), @(("5818" + ("00" * 24)), ""),
    @("5f4100ff", "indefinite"), @("c0f5", "tag"), @("fa3f800000", "floating"), @("f7", "simple"), @("f820", "simple"), @("1c", "reserved"),
    @("a2010201ff", "more than once"), @("a1f5f5", "key of type"), @("62ff00", "UTF-8"), @("43", "past the end"), @("5a7fffffff", "past the end"),
    @("", "ends"), @("0000", "after"), @("818181818181818181", "deeper")
)
foreach ($c in $cases) {
    $got = Read-HordeRelayCbor -Bytes (Hex $c[0]) -Whole
    if ($c[1] -ceq "") { Check ($got.ok) ("CONTROL: " + $c[0] + " is read (" + $got.reason + ")") }
    else { Check ((-not $got.ok) -and $got.reason.Contains($c[1])) ($c[0] + " is refused for '" + $c[1] + "' (" + $got.reason + ")") }
}
$many = "98" + "41" + ("00" * 65)
Check ((Read-HordeRelayCbor -Bytes (Hex $many)).reason.Contains("more than 64")) "an array of 65 items is refused before it is read"
Check ((Read-HordeRelayCbor -Bytes (Hex ("98" + "40" + ("00" * 64))) -Whole).ok) "CONTROL: 64 items are read"
$off = Read-HordeRelayCbor -Bytes (Hex "ff0102") -Offset 1
Check ($off.ok -and $off.value.value -eq 1 -and $off.next -eq 2) "an item is read at an offset, and says where it ends"

Write-Host ""
Write-Host "--- COSE import: the WebCrypto key comes back as itself ---" -ForegroundColor Cyan
$valid = @($regs | Where-Object { $_.expect -ceq "accepted" })
Check ($regs.Count -eq 37 -and $valid.Count -eq 6) ("CONTROL: the fixture holds its 37 registrations, 6 valid (" + $regs.Count + ", " + $valid.Count + ")")
$cose = Hex ("a5" + "0102" + "0326" + "2001" + "2158" + "20" + ("11" * 32) + "2258" + "20" + ("22" * 32))
$k = ConvertFrom-HordeRelayCoseKeyBytes -Bytes $cose
Check ((-not $k.ok) -and $k.reason.Contains("not a point on P-256")) ("a well-formed COSE key whose point is off the curve is refused (" + $k.reason + ")")
foreach ($c in $valid) {
    $ans = Invoke-Reg -Case $c
    Check ($ans.ok -and (ConvertTo-HordeRelayBase64Url -Bytes $ans.public) -ceq $c.publicKey) ($c.name + ": the imported key is the key WebCrypto exported" + $(if (-not $ans.ok) { " (refused: " + $ans.reason + ")" } else { "" }))
    $a = $c.assertion
    $v = Test-HordeRelayWebAuthnAssertion -Public $ans.public -AuthenticatorData (B $a.authenticatorData) -ClientDataJson (B $a.clientDataJSON) -Signature (B $a.signature) `
        -Challenge (B $a.challenge) -RpId $fx.rpId -Origins @($fx.origin) -RequireUserVerification $true
    Check ($v.ok) ($c.name + ": an assertion its credential signed verifies under the imported key (" + $v.reason + ")")
    Check ((ConvertTo-HordeRelayBase64Url -Bytes $ans.credentialId) -ceq $c.credentialId -and $ans.alg -eq -7) ($c.name + ": the credential id and the algorithm are reported")
}
$other = Invoke-Reg -Case $valid[1]
$a0 = $valid[0].assertion
$cross = Test-HordeRelayWebAuthnAssertion -Public $other.public -AuthenticatorData (B $a0.authenticatorData) -ClientDataJson (B $a0.clientDataJSON) -Signature (B $a0.signature) -Challenge (B $a0.challenge) -RpId $fx.rpId -Origins @($fx.origin) -RequireUserVerification $true
Check (-not $cross.ok) "CONTROL: one credential's assertion does not verify under another credential's imported key"

Write-Host ""
Write-Host "--- every WebCrypto-made registration gets its expected answer ---" -ForegroundColor Cyan
foreach ($c in $regs) {
    $ans = Invoke-Reg -Case $c
    if ($c.expect -ceq "accepted") { Check ($ans.ok -and $ans.reason -ceq "") ($c.name + " -> accepted" + $(if (-not $ans.ok) { " (refused: " + $ans.reason + ")" } else { "" })) }
    else { Check ((-not $ans.ok) -and $ans.reason.Contains($c.expect) -and $null -eq $ans.public) ($c.name + " -> refused for '" + $c.expect + "' (" + $ans.reason + ")") }
}

Write-Host ""
Write-Host "--- what an accepted registration reports ---" -ForegroundColor Cyan
$synced = Invoke-Reg -Case $valid[0]
Check ($synced.backupEligible -and $synced.backupState -and $synced.signCount -eq 0 -and $synced.userVerified -and $synced.aaguid -ceq "ea9b8d664d011d213ce4b6b48cb575d4") "a synced passkey: BE, BS, counter 0, verified, its aaguid"
$bound = Invoke-Reg -Case $valid[1]
Check ((-not $bound.backupEligible) -and $bound.signCount -eq 5) "a device-bound passkey: not backup eligible, counter 5"
$prf = Invoke-Reg -Case $valid[2]
Check ($prf.ok -and $prf.hmacSecret -and -not $synced.hmacSecret) "hmac-secret in the extensions is reported, and its absence too"

Write-Host ""
Write-Host "--- the same valid registration, against the wrong client data or expectation ---" -ForegroundColor Cyan
$v0 = $valid[0]
Check ((Invoke-Reg -Case $v0 -ClientData (New-ClientData -Type "webauthn.get")).reason.Contains("not webauthn.create")) "clientDataJSON of an assertion (webauthn.get) is refused"
Check ((Invoke-Reg -Case $v0 -ClientData (New-ClientData -Challenge (ConvertTo-HordeRelayBase64Url -Bytes (New-Object byte[] 32)))).reason.Contains("challenge")) "another challenge is refused: a registration made for another offer"
Check ((Invoke-Reg -Case $v0 -ClientData (New-ClientData -Origin "https://evil.example.test")).reason.Contains("origin")) "another origin is refused"
Check ((Invoke-Reg -Case $v0 -ClientData (New-ClientData -Extra ',"crossOrigin":true')).reason.Contains("crossOrigin")) "a framed (cross-origin) creation is refused"
Check ((Invoke-Reg -Case $v0 -ClientData (New-ClientData -Extra ',"topOrigin":"https://evil.example.test"')).reason.Contains("topOrigin")) "a named top origin is refused"
Check ((Invoke-Reg -Case $v0 -ClientData (New-ClientData -Extra (',"challenge":"' + $challengeText + '"'))).reason.Contains("more than once")) "a repeated member is refused"
Check ((Invoke-Reg -Case $v0 -RpId "other.example.test").reason.Contains("rpIdHash")) "the right registration against another relying party id is refused"
Check ((Invoke-Reg -Case $v0 -Origins @("https://other.example.test")).reason.Contains("origin")) "and against another expected origin"
$noUv = @($regs | Where-Object { $_.name -clike "refused: user not verified*" })[0]
Check ((Invoke-Reg -Case $noUv -Uv $false).ok) "CONTROL: the not-verified registration is accepted only when verification is not required, so its refusal is for that alone"
Check ((Invoke-Reg -Case $v0 -RawId (New-Object byte[] 0)).reason.Contains("rawId")) "an empty rawId is refused"
$tooBig = New-Object byte[] 4097
Check ((Invoke-Reg -Case $v0 -Att $tooBig).reason.Contains("larger than 4096")) "an attestationObject over 4096 bytes is refused before it is read"
Check ((Test-HordeRelayWebAuthnRegistration -ClientDataJson (New-ClientData) -AttestationObject (B $v0.attestationObject) -RawId (B $v0.rawId) -Challenge (New-Object byte[] 15) -RpId $fx.rpId -Origins @($fx.origin) -RequireUserVerification $true).reason.Contains("shorter than 16")) "an expected challenge under 16 bytes is refused"

Write-Host ""
Write-Host "--- authData cut and spliced by hand ---" -ForegroundColor Cyan
# The valid attestationObject's authData, rebuilt around changes, so one thing at a time is wrong.
$att = Read-HordeRelayCbor -Bytes (B $v0.attestationObject) -Whole
$ad = [byte[]](Get-HordeRelayCborMember -Map $att.value -Key "authData").value
function New-Att {
    param([byte[]]$AuthData)
    $len = $AuthData.Length
    $head = $(if ($len -lt 256) { [byte[]]@(0x58, $len) } else { [byte[]]@(0x59, ($len -shr 8), ($len -band 255)) })
    # {"fmt": "none", "attStmt": {}, "authData": <bytes>}, written out.
    return ,(Join-HordeRelayBytes -Parts @((Hex "a363666d74646e6f6e656761747453746d74a0686175746844617461"), $head, $AuthData))
}
Check ((Invoke-Reg -Case $v0 -Att (New-Att -AuthData $ad)).ok) "CONTROL: the rebuilt attestationObject of the unchanged authData is accepted"
$short = New-Object byte[] 54
[System.Array]::Copy($ad, 0, $short, 0, 54)
Check ((Invoke-Reg -Case $v0 -Att (New-Att -AuthData $short)).reason.Contains("too short")) "authData that ends inside the attested credential data is refused"
$idLen = ([int]$ad[53] -shl 8) + [int]$ad[54]
$cut = New-Object byte[] (55 + 10)
[System.Array]::Copy($ad, 0, $cut, 0, $cut.Length)
Check ((Invoke-Reg -Case $v0 -Att (New-Att -AuthData $cut)).reason.Contains("runs past the end")) ("a credential id of " + $idLen + " bytes in authData that ends 10 bytes into it is refused")
$zero = [byte[]]$ad.Clone(); $zero[53] = 0; $zero[54] = 0
Check ((Invoke-Reg -Case $v0 -Att (New-Att -AuthData $zero)).reason.Contains("0 bytes")) "a credential id of 0 bytes is refused"
$edBad = Join-HordeRelayBytes -Parts @($ad, [byte[]]@(0xa1, 0x61))
$edBad[32] = $edBad[32] -bor 0x80
Check ((Invoke-Reg -Case $v0 -Att (New-Att -AuthData $edBad)).reason.Contains("extensions are not CBOR")) "extensions that are cut short are refused"
$edTrail = Join-HordeRelayBytes -Parts @($ad, [byte[]]@(0xa0, 0x00))
$edTrail[32] = $edTrail[32] -bor 0x80
Check ((Invoke-Reg -Case $v0 -Att (New-Att -AuthData $edTrail)).reason.Contains("after the CBOR item")) "bytes after the extensions map are refused"
$edOk = Join-HordeRelayBytes -Parts @($ad, [byte[]]@(0xa0))
$edOk[32] = $edOk[32] -bor 0x80
Check ((Invoke-Reg -Case $v0 -Att (New-Att -AuthData $edOk)).ok) "CONTROL: an empty extensions map, flagged, is accepted"
$hsFalse = Join-HordeRelayBytes -Parts @($ad, (Hex "a16b686d61632d736563726574f4"))
$hsFalse[32] = $hsFalse[32] -bor 0x80
$hf = Invoke-Reg -Case $v0 -Att (New-Att -AuthData $hsFalse)
Check ($hf.ok -and -not $hf.hmacSecret) "hmac-secret: false is accepted and reported as false"

Complete-HordeSuite -Success "registrations are accepted exactly when valid, and the key they carry imports as itself"
