# DOES THE RELAY ACCEPT A WEBAUTHN ASSERTION EXACTLY WHEN WEBAUTHN SAYS IT IS VALID FOR US?
#
# relay/WebAuthn.ps1. A founder's answer from a phone is signed by a passkey; this is the check that
# says the signature is the founder's, over this challenge, for this site, with the person present and
# verified. The assertions in test/fixtures/relay/webauthn/assertions.json were made by WebCrypto
# (make-fixtures.mjs beside them, run with Node), not by Horde, and each refused case is wrong in one
# way only, so every refusal is reached for its own reason. Run under powershell.exe and pwsh alike.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "relay\WebAuthn.ps1")
Set-StrictMode -Version Latest
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + ")") -ForegroundColor DarkGray

$fx = [System.IO.File]::ReadAllText((Join-Path $here "fixtures\relay\webauthn\assertions.json")) | ConvertFrom-Json
$pub = ConvertFrom-HordeRelayBase64Url -Text $fx.publicKey
$cases = @($fx.cases)

function Invoke-Case {
    param($Case, [string[]]$Origins = @($fx.origin), [string]$RpId = $fx.rpId, [byte[]]$Public = $pub, $Uv = $null)
    $requireUv = [bool]$Case.requireUserVerification
    if ($null -ne $Uv) { $requireUv = [bool]$Uv }
    return (Test-HordeRelayWebAuthnAssertion -Public $Public `
        -AuthenticatorData (ConvertFrom-HordeRelayBase64Url -Text $Case.authenticatorData) `
        -ClientDataJson (ConvertFrom-HordeRelayBase64Url -Text $Case.clientDataJSON) `
        -Signature (ConvertFrom-HordeRelayBase64Url -Text $Case.signature) `
        -Challenge (ConvertFrom-HordeRelayBase64Url -Text $Case.challenge) `
        -RpId $RpId -Origins $Origins -RequireUserVerification $requireUv)
}

Write-Host ""
Write-Host "--- every WebCrypto-made case gets its expected answer ---" -ForegroundColor Cyan
Check ($cases.Count -eq 25) ("CONTROL: the fixture holds its 25 cases (" + $cases.Count + ")")
Check (@($cases | Where-Object { $_.expect -ceq "accepted" }).Count -eq 5) "CONTROL: five of them are valid, so acceptance is tested as hard as refusal"
foreach ($c in $cases) {
    $r = Invoke-Case -Case $c
    if ($c.expect -ceq "accepted") {
        Check ($r.ok -eq $true -and $r.reason -ceq "") ($c.name + " -> accepted" + $(if (-not $r.ok) { " (refused: " + $r.reason + ")" } else { "" }))
    } else {
        Check ($r.ok -eq $false -and $r.reason.Contains($c.expect)) ($c.name + " -> refused for '" + $c.expect + "' (" + $r.reason + ")")
    }
}

Write-Host ""
Write-Host "--- what an accepted assertion reports ---" -ForegroundColor Cyan
$valid = $cases[0]
$ok = Invoke-Case -Case $valid
Check ($ok.signCount -eq 7 -and $ok.userVerified -eq $true -and $ok.backupEligible -eq $false -and $ok.backupState -eq $false) "the counter (7) and the flags are read from authenticatorData"
$synced = Invoke-Case -Case $cases[3]
Check ($synced.ok -and $synced.signCount -eq 0 -and $synced.backupEligible -and $synced.backupState) "a synced passkey's counter of 0 is accepted and reported, never treated as a replay here (design Q11)"
$upOnly = Invoke-Case -Case $cases[1]
Check ($upOnly.ok -and $upOnly.userVerified -eq $false) "presence without verification is reported as not verified"

Write-Host ""
Write-Host "--- the same valid assertion, checked against the wrong expectation ---" -ForegroundColor Cyan
Check (-not (Invoke-Case -Case $valid -Origins @("https://other.example.test")).ok) "another expected origin refuses it"
Check ((Invoke-Case -Case $valid -Origins @("https://other.example.test", $fx.origin)).ok) "CONTROL: a list of origins that includes its own accepts it"
Check (-not (Invoke-Case -Case $valid -Origins @("https://RELAY.example.test")).ok) "origins are compared exactly, case included"
Check (-not (Invoke-Case -Case $valid -RpId "example.test").ok) "a parent domain as the relying party refuses it"
$otherKey = ConvertTo-HordeRelayP256Public -Key (New-HordeRelayP256Key -Use "ecdsa")
Check (-not (Invoke-Case -Case $valid -Public $otherKey).ok) "another credential's public key refuses it"
$r = Test-HordeRelayWebAuthnAssertion -Public $pub -AuthenticatorData (ConvertFrom-HordeRelayBase64Url -Text $valid.authenticatorData) -ClientDataJson (ConvertFrom-HordeRelayBase64Url -Text $valid.clientDataJSON) -Signature (ConvertFrom-HordeRelayBase64Url -Text $valid.signature) -Challenge (Get-HordeRelayRandomBytes -Count 32) -RpId $fx.rpId -Origins @($fx.origin) -RequireUserVerification $true
Check (-not $r.ok -and $r.reason.Contains("challenge")) "another expected challenge refuses it: the challenge is what binds the signature to one envelope"
Check (-not (Invoke-Case -Case $valid -Origins @()).ok) "no expected origin at all refuses everything"

Write-Host ""
Write-Host "--- sizes and shapes the verifier refuses before reading ---" -ForegroundColor Cyan
$ad = ConvertFrom-HordeRelayBase64Url -Text $valid.authenticatorData
$cdj = ConvertFrom-HordeRelayBase64Url -Text $valid.clientDataJSON
$sig = ConvertFrom-HordeRelayBase64Url -Text $valid.signature
$ch = ConvertFrom-HordeRelayBase64Url -Text $valid.challenge
$short = New-Object byte[] 36; [System.Array]::Copy($ad, 0, $short, 0, 36)
$r = Test-HordeRelayWebAuthnAssertion -Public $pub -AuthenticatorData $short -ClientDataJson $cdj -Signature $sig -Challenge $ch -RpId $fx.rpId -Origins @($fx.origin) -RequireUserVerification $true
Check (-not $r.ok -and $r.reason.Contains("37 bytes")) ("authenticatorData shorter than 37 bytes is refused (" + $r.reason + ")")
$big = Join-HordeRelayBytes -Parts @($cdj, (Get-HordeRelayAsciiBytes -Text (" " * 4096)))
$r = Test-HordeRelayWebAuthnAssertion -Public $pub -AuthenticatorData $ad -ClientDataJson $big -Signature $sig -Challenge $ch -RpId $fx.rpId -Origins @($fx.origin) -RequireUserVerification $true
Check (-not $r.ok -and $r.reason.Contains("larger than")) ("clientDataJSON over the cap is refused before it is parsed (" + $r.reason + ")")
$r = Test-HordeRelayWebAuthnAssertion -Public $pub -AuthenticatorData $ad -ClientDataJson $cdj -Signature (Get-HordeRelayRandomBytes -Count 64) -Challenge $ch -RpId $fx.rpId -Origins @($fx.origin) -RequireUserVerification $true
Check (-not $r.ok -and $r.reason.Contains("DER")) "a raw 64-byte signature where DER belongs is refused"

Write-Host ""
Write-Host "--- high-S is accepted for WebAuthn, by design ---" -ForegroundColor Cyan
# Authenticators emit either half of s and the founder cannot choose, so a passkey signature is not
# part of an envelope's identity (relay/Envelope.ps1): its high-S twin must verify too.
Add-Type -AssemblyName System.Numerics
$nOrder = [System.Numerics.BigInteger]::Parse("0FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551", "AllowHexSpecifier")
function DerInt { param([byte[]]$V) $i = 0; while ($i -lt 31 -and $V[$i] -eq 0) { $i++ }; $b = New-Object byte[] (32 - $i); [System.Array]::Copy($V, $i, $b, 0, $b.Length); if ($b[0] -band 0x80) { $b = Join-HordeRelayBytes -Parts @([byte[]]@(0), $b) }; return ,(Join-HordeRelayBytes -Parts @([byte[]]@(2, $b.Length), $b)) }
$p = ConvertFrom-HordeRelayDerSignature -Der $sig
$sHex = ($nOrder - [System.Numerics.BigInteger]::Parse("0" + (ConvertTo-HordeRelayHex -Bytes ([byte[]]$p[32..63])), "AllowHexSpecifier")).ToString("x64")
$rPart = DerInt ([byte[]]$p[0..31]); $sPart = DerInt (ConvertFrom-HordeRelayHex -Text $sHex.Substring($sHex.Length - 64))
$twinDer = Join-HordeRelayBytes -Parts @([byte[]]@(0x30, ($rPart.Length + $sPart.Length)), $rPart, $sPart)
Check ((ConvertTo-HordeRelayHex -Bytes $twinDer) -cne (ConvertTo-HordeRelayHex -Bytes $sig)) "CONTROL: the twin DER differs from the fixture's"
$r = Test-HordeRelayWebAuthnAssertion -Public $pub -AuthenticatorData $ad -ClientDataJson $cdj -Signature $twinDer -Challenge $ch -RpId $fx.rpId -Origins @($fx.origin) -RequireUserVerification $true
Check ($r.ok) ("the high-S twin of a valid assertion is accepted (" + $r.reason + ")")

Complete-HordeSuite -Success "a WebAuthn assertion is accepted exactly when its type, challenge, origin, relying party, flags and ES256 signature are all right"
