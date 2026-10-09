# ARE THE MACHINE'S RELAY KEYS MADE ONCE, NEVER EXPORTABLE, AND USABLE FOR WHAT THEY ARE FOR?
#
# relay/Keys.ps1. Every key this suite makes has a name of its own (horde-relay-test-<random>), is
# removed in the finally block by that name, and is the only key the suite touches (CONTRIBUTING 9).
# The user scope is tested always; the machine scope only shows that the scope asked for is the scope
# used, or a reason - it needs an elevated session, and the suite does not require one.
#
# Off Windows there is no non-exportable key store, and the suite checks that the module says so
# instead of faking one; everything else is skipped there and the suite exits 3 (a partial run).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "relay\Keys.ps1")
. (Join-Path $root "relay\Hpke.ps1")
Set-StrictMode -Version Latest
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + ")") -ForegroundColor DarkGray

$store = Get-HordeRelayKeyStore
$onWindows = ("" + [System.Environment]::OSVersion.Platform) -ceq "Win32NT"
if (-not $onWindows) {
    Check ($store.state -ceq "absent" -and $store.reason.Contains("not faked")) "off Windows the store is absent, and says no key is faked"
    Complete-HordeSuite -Success "off Windows: no key store, said plainly" -PassCode 3
}
Check ($store.state -ceq "known" -and $store.value -ceq "cng") "on Windows the store is CNG"

$tag = [guid]::NewGuid().ToString("N").Substring(0, 12)
$signName = "horde-relay-test-" + $tag + "-s"
$agreeName = "horde-relay-test-" + $tag + "-a"
$softName = "horde-relay-test-" + $tag + "-w"
$plantName = "horde-relay-test-" + $tag + "-p"
$machineName = "horde-relay-test-" + $tag + "-m"
$mine = @(@{ n = $signName; s = "user" }, @{ n = $agreeName; s = "user" }, @{ n = $softName; s = "user" }, @{ n = $plantName; s = "user" }, @{ n = $machineName; s = "machine" })
try {
    Write-Host ""
    Write-Host "--- a signing key: made once, never exportable ---" -ForegroundColor Cyan
    $made = New-HordeRelayKey -Name $signName -Use "sign"
    Check ($made.state -ceq "known") ("the signing key is made (" + $(if ($made.state -ceq "known") { $made.value.provider + "; tried: " + (@($made.value.tried) -join " / ") } else { $made.reason }) + ")")
    Check ($made.value.keyId -ceq (Get-HordeRelayKeyId -Public $made.value.publicKey) -and $made.value.scope -ceq "user") "it reports its key id and the scope asked for"
    Check (@($made.value.tried)[-1].EndsWith("made and used once")) "it was used once before it was kept"
    $again = New-HordeRelayKey -Name $signName -Use "sign"
    Check ($again.state -ceq "unknown" -and $again.reason.Contains("never overwritten")) "making it a second time is refused"
    $open = Get-HordeRelayKey -Name $signName -Use "sign"
    Check ($open.state -ceq "known" -and (ConvertTo-HordeRelayHex -Bytes $open.value.publicKey) -ceq (ConvertTo-HordeRelayHex -Bytes $made.value.publicKey)) "after the refused second make it is still the first key"
    Check (Throws { $open.value.key.ExportParameters($true) }) "its private half cannot be exported as parameters"
    Check (Throws { $open.value.key.Key.Export([System.Security.Cryptography.CngKeyBlobFormat]::EccPrivateBlob) }) "nor as a private blob"
    $msg = Get-HordeRelayAsciiBytes -Text "signed by a non-exportable key"
    $sig = New-HordeRelayEs256Signature -Key $open.value.key -Bytes $msg
    Check (Test-HordeRelayEs256Signature -Public $open.value.publicKey -Bytes $msg -Signature $sig) "it signs, and the signature verifies under its public key"
    $wrongUse = Get-HordeRelayKey -Name $signName -Use "agree"
    Check ($wrongUse.state -ceq "unknown" -and $wrongUse.reason.Contains("not a P-256 key for agree")) "opened as an agreement key it is refused"

    Write-Host ""
    Write-Host "--- an agreement key: opens HPKE without its scalar ever leaving the provider ---" -ForegroundColor Cyan
    $agree = New-HordeRelayKey -Name $agreeName -Use "agree"
    Check ($agree.state -ceq "known") ("the agreement key is made (" + $(if ($agree.state -ceq "known") { $agree.value.provider + "; tried: " + (@($agree.value.tried) -join " / ") } else { $agree.reason }) + ")")
    $ak = Get-HordeRelayKey -Name $agreeName -Use "agree"
    Check (Throws { $ak.value.key.ExportParameters($true) }) "its private half cannot be exported"
    $info = Get-HordeRelayAsciiBytes -Text "info"
    $aad = Get-HordeRelayAsciiBytes -Text "aad"
    $box = Protect-HordeRelayHpke -RecipientPublic $ak.value.publicKey -Info $info -Aad $aad -Plaintext (Get-HordeRelayAsciiBytes -Text "for this machine only")
    $plain = Unprotect-HordeRelayHpke -RecipientKey $ak.value.key -Enc $box.enc -Info $info -Aad $aad -Sealed $box.sealed
    Check ($null -ne $plain -and [System.Text.Encoding]::ASCII.GetString($plain) -ceq "for this machine only") "an HPKE message sealed to it opens with it"
    $soft = New-HordeRelayKey -Name $softName -Use "agree" -Provider "software"
    Check ($soft.state -ceq "known" -and $soft.value.provider -ceq "software" -and @($soft.value.tried).Count -eq 1) "a provider asked for by name is the only one tried"

    Write-Host ""
    Write-Host "--- what is not a relay key ---" -ForegroundColor Cyan
    Check ((Get-HordeRelayKey -Name ("horde-relay-test-" + $tag + "-none") -Use "sign").state -ceq "absent") "a name with no key is absent"
    Check (Throws { Get-HordeRelayKey -Name "someone-elses-key" -Use "sign" } "horde-relay-") "a name outside horde-relay- is refused before any store is asked"
    Check (Throws { New-HordeRelayKey -Name ($signName + "X") -Use "sign" } "horde-relay-") "upper case in a name is refused"
    # An exportable key planted under a relay name, made directly through CNG.
    $pp = New-Object System.Security.Cryptography.CngKeyCreationParameters
    $pp.ExportPolicy = [System.Security.Cryptography.CngExportPolicies]::AllowPlaintextExport
    $pp.Provider = New-Object System.Security.Cryptography.CngProvider -ArgumentList "Microsoft Software Key Storage Provider"
    [System.Security.Cryptography.CngKey]::Create([System.Security.Cryptography.CngAlgorithm]::ECDsaP256, $plantName, $pp).Dispose()
    $planted = Get-HordeRelayKey -Name $plantName -Use "sign"
    Check ($planted.state -ceq "unknown" -and $planted.reason.Contains("can be exported")) "an exportable key under a relay name is refused, not used"

    Write-Host ""
    Write-Host "--- the machine scope is the machine scope, or a reason ---" -ForegroundColor Cyan
    $m = New-HordeRelayKey -Name $machineName -Use "sign" -Scope "machine" -Provider "software"
    if ($m.state -ceq "known") {
        Check ($m.value.scope -ceq "machine" -and (Get-HordeRelayKey -Name $machineName -Use "sign" -Scope "machine").state -ceq "known") "made in the machine scope, and found there"
        Check ((Get-HordeRelayKey -Name $machineName -Use "sign" -Scope "user").state -ceq "absent") "and not in the user scope"
    } else {
        Check ($m.state -ceq "unknown" -and $m.reason.Length -gt 0) ("not made in the machine scope here, with a reason (" + $m.reason + ")")
        Check ((Get-HordeRelayKey -Name $machineName -Use "sign" -Scope "user").state -ceq "absent") "and never made in the user scope instead"
    }

    Write-Host ""
    Write-Host "--- removal ---" -ForegroundColor Cyan
    Check ((Remove-HordeRelayKey -Name $signName).state -ceq "known") "the signing key is removed"
    Check ((Get-HordeRelayKey -Name $signName -Use "sign").state -ceq "absent") "and is gone"
    Check ((Remove-HordeRelayKey -Name $signName).state -ceq "absent") "removing it again is absent, not an error"
} finally {
    foreach ($k in $mine) {
        try { [void](Remove-HordeRelayKey -Name $k.n -Scope $k.s) } catch { Write-Host ("  cleanup of " + $k.n + " failed: " + $_.Exception.Message) -ForegroundColor Yellow }
    }
}
$left = @($mine | Where-Object { (Find-HordeRelayCngKey -Name $_.n -Scope $_.s) -cne "" })
Check ($left.Count -eq 0) "every key the suite made is gone"

Complete-HordeSuite -Success "relay keys are made once, cannot be exported, sign and open HPKE, and refuse what is not theirs"
