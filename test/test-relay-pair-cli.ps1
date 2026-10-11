# DOES `horde relay pair` PAIR THE FOUNDER'S PHONE THROUGH THE RELAY, CONFIRMED ONLY BY THE NUMBER HE
# TYPES FROM HIS PHONE - AND DO `horde relay trust` AND `horde relay identity` SAY WHAT THE MACHINE KNOWS?
#
# The end-to-end scenario of the commands (CONTRIBUTING 2): the shipped horde.ps1 as its own process,
# over relays/local in a folder of the suite's own, typed at through -InputFile (cli/RelayPair.ps1, THE
# INPUT: a file read as it grows, never a redirected stdin).
#   1. the WebCrypto test phone (test/fixtures/relay/phone/phone.mjs) answers the offer the command
#      prints and sends its sealed response through the relay; the founder types a wrong number, then
#      the phone's: the device is trusted, the picture is gone, the pairing mailbox is acked;
#   2. `relay identity`, `relay trust list` and `relay trust revoke` on what that pairing made;
#   3. what a hostile or careless relay can put in the pairing mailbox - an old offer's sealed
#      response, junk, a sealed response with the wrong code - is refused, and the phone still pairs;
#   4. a thief who answers the offer first: the founder's number never matches, and three tries reject
#      the thief's device;
#   5. no relay named: the response is pasted; a response to another offer is refused without ending
#      the pairing;
#   6. the command line's refusals;
#   7. in this process, because the command cannot pick a test relay or a clock: the hostile test relay
#      (test/lib/HostileRelay.ps1) reordering, repeating and salting the mailbox; a mailbox flooded past
#      the refusal cap; an offer that expires; reject typed; and an interruption (Ctrl+C) that still
#      deletes the picture.
#
# NODE IS NEEDED for the phone of section 1. Without it that section is skipped, said so, and the suite
# exits 3, a partial run, never 0. Every home, relay folder and phone state is the suite's own under
# %TEMP%; every key the homes make is removed in the finally block, then checked gone.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\ModuleSettings.ps1")
. (Join-Path $root "core\Home.ps1")
. (Join-Path $root "channels\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
. (Join-Path $root "cli\QrCode.ps1")
. (Join-Path $root "cli\RelayPair.ps1")
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "test\lib\HostileRelay.ps1")
. (Join-Path $root "test\lib\RelayPhone.ps1")
Set-StrictMode -Version Latest

if ((Get-HordeRelayKeyStore).state -cne "known") {
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "skipped: no key store here, so no machine identity" -PassCode 3
}
$node = Get-Command -Name "node" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1

$ascii = [System.Text.Encoding]::ASCII
$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$work = Join-Path $env:TEMP ("horde-relay-pair-cli-" + [guid]::NewGuid().ToString("N"))
$hh = Join-Path $work "home"
$mailboxes = Join-Path $work "relay"
$phoneDir = Join-Path $work "phone"
New-Item -ItemType Directory -Path (Join-Path $hh "settings"), $mailboxes, $phoneDir -Force | Out-Null
$script:n = 0
$script:homes = New-Object System.Collections.ArrayList
[void]$script:homes.Add($hh)
$phoneScript = Join-Path $here "fixtures\relay\phone\phone.mjs"
$rp = "relay.example.test"
$partial = $false

function Set-PairSettings {
    param([string]$HordeHome, [bool]$App = $true)
    New-Item -ItemType Directory -Path (Join-Path $HordeHome "settings") -Force | Out-Null
    $more = $(if ($App) { ', "pairRpId": "' + $rp + '", "pairOrigin": "https://' + $rp + '"' } else { "" })
    [System.IO.File]::WriteAllText((Join-Path $HordeHome "settings\relay.json"), ('{"schemaVersion": 1, "settings": {"horde": "work"' + $more + '}}'), $utf8)
}
function Invoke-Phone {
    # One command of the WebCrypto phone, with its own state file.
    param([string]$Command, [string]$State, [hashtable]$In = @{})
    $script:n++
    $inFile = Join-Path $phoneDir ("in-" + $script:n + ".json")
    $outFile = Join-Path $phoneDir ("out-" + $script:n + ".json")
    [System.IO.File]::WriteAllText($inFile, (ConvertTo-Json -InputObject $In -Compress -Depth 6), $utf8)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $node.Source
    $psi.Arguments = '"' + $phoneScript + '" ' + $Command + ' "' + (Join-Path $phoneDir ($State + ".json")) + '" "' + $inFile + '" "' + $outFile + '"'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $null = $p.StandardOutput.ReadToEnd()
    if (-not $p.WaitForExit(60000)) { $p.Kill(); throw "the phone did not answer in 60 s" }
    if ($p.ExitCode -ne 0) { throw ("the phone failed: " + $errTask.Result) }
    return ([System.IO.File]::ReadAllText($outFile, $utf8) | ConvertFrom-Json)
}
function Start-Pair {
    # `horde relay pair` as its own process (test/lib/Cli.ps1, Start-HordeCliRun), typed at through a
    # fresh input file.
    param([string[]]$More = @(), [string]$HordeHome = $hh)
    $script:n++
    $inputFile = Join-Path $work ("typed-" + $script:n + ".txt")
    [System.IO.File]::WriteAllText($inputFile, "", $ascii)
    $r = Start-HordeCliRun -Root $root -HordeArgs (@("relay", "pair") + $More + @("-InputFile", $inputFile, "-NoPicture")) -Env @{ HORDE_HOME = $HordeHome }
    $r | Add-Member -NotePropertyName input -NotePropertyValue $inputFile
    return $r
}
function Wait-PairLine { param($Run, [string]$Like, [int]$Seconds = 90) return (Wait-HordeCliLine -Run $Run -Like $Like -Seconds $Seconds) }
function Add-Typed { param($Run, [string]$Line) [System.IO.File]::AppendAllText($Run.input, $Line + "`n", $ascii) }
function Get-OfferOf {
    # The offer a run printed, read back as the machine wrote it.
    param($Run)
    $line = Wait-PairLine -Run $Run -Like '{"v":1,"kind":"horde-relay-pairing-offer"*'
    if ($null -eq $line) { return $null }
    $r = Read-HordeRelayPairingOffer -Text $line
    if (-not $r.ok) { return $null }
    $pend = Read-HordeRelayRecordText -Text ([System.IO.File]::ReadAllText((Join-Path $hh ("relay\pairing\offers\" + $r.value.offer + ".json")))) -Spec (Get-HordeRelayPendingSpec) -Kind "horde-relay-pairing-pending"
    return [pscustomobject]@{ text = $line; offer = $r.value.offer; code = $r.value.code; pairMailbox = $r.value.pairMailbox; challenge = $pend.value.challenge; expiresAt = $r.value.expiresAt; label = $r.value.label }
}
function Get-Fingerprint {
    param($Offer, $Phone)
    return (Get-HordeRelayPairingFingerprint -Challenge (ConvertFrom-HordeRelayBase64Url -Text $Offer.challenge) -Public $Phone.public -CredentialId $Phone.credentialId -RpId $rp)
}
function Get-Device { param([string]$HordeHome, [string]$Id) return (@((Get-HordeRelayTrust -HordeHome $HordeHome).value.devices | Where-Object { $_.id -ceq $Id }) | Select-Object -First 1) }

$run = $null
# Everything the machine printed or answered, for the check that no device fingerprint is ever in it.
$script:machineSaid = New-Object System.Collections.ArrayList
function Invoke-Horde { param([string[]]$HordeArgs, [string]$HordeHome = $hh) $r = Invoke-HordeCliProcess -Root $root -HordeArgs $HordeArgs -Env @{ HORDE_HOME = $HordeHome }; [void]$script:machineSaid.Add($r.out); return $r }
function Complete-Pair { param($Run) $r = Complete-HordeCliRun -Run $Run; [void]$script:machineSaid.Add($r.out); return $r }
try {
    Set-PairSettings -HordeHome $hh
    $id = New-HordeRelayMachineIdentity -HordeHome $hh -Provider "software"
    Check ($id.state -ceq "known") "CONTROL: the machine has its relay identity"
    $c = Connect-HordeRelay -Name "local" -Options @{ root = $mailboxes }

    Write-Host ""
    Write-Host "--- 1. the WebCrypto phone pairs through the relay; the founder types the number his phone shows ---" -ForegroundColor Cyan
    $deviceA = ""
    if ($null -eq $node) {
        Write-Host "  [SKIP] node is not installed here, so there is no WebCrypto phone" -ForegroundColor Yellow
        $partial = $true
    } else {
        $run = Start-Pair -More @("-Relay", "local", "-RelayRoot", $mailboxes, "-Label", "Founder phone")
        $pngLine = Wait-PairLine -Run $run -Like "Scan this QR code*"
        $offerA = Get-OfferOf $run
        Check ($null -ne $offerA) "the command prints its offer, as text, for the app's paste box"
        Check ($null -ne $offerA -and $offerA.label -ceq (ConvertTo-HordeDeviceName -Text "$env:COMPUTERNAME")) ("and names the machine in it by the computer's own name, which a hosted relay's Account screen shows (" + $(if ($null -ne $offerA) { $offerA.label } else { "" }) + ")")
        $png = $(if ($null -ne $pngLine) { $pngLine.Substring($pngLine.LastIndexOf(": ") + 2) } else { "" })
        Check ($png -ne "" -and (Test-Path -LiteralPath $png) -and ([System.BitConverter]::ToString([System.IO.File]::ReadAllBytes($png), 0, 4) -ceq "89-50-4E-47")) ("and writes its QR code as a PNG to show (" + $png + ")")
        Check ($null -ne (Wait-PairLine -Run $run -Like ("Waiting for the phone's response through the relay 'local' (" + $offerA.pairMailbox + ")*"))) "it waits on the offer's own pairing mailbox"
        $regA = Invoke-Phone "register" "phone-a" @{ offer = $offerA.text; label = "Pixel" }
        $sentA = Invoke-Phone "send-pairing" "phone-a" @{ relayRoot = $mailboxes }
        Check ($sentA.relayed -and $regA.pairMailbox -ceq $offerA.pairMailbox) "the phone seals its response and puts it in that mailbox"
        Check ($null -ne (Wait-PairLine -Run $run -Like "A phone registered: 'Founder phone'*")) "the machine takes it from the relay: a phone registered, under the label given at the machine"
        Check ($null -ne (Wait-PairLine -Run $run -Like "*Type that number here*")) "and asks for the number the PHONE shows"
        $printed = ($run.lines -join "`n")
        Check (-not $printed.Contains($regA.fingerprint) -and -not $printed.Contains($regA.fingerprint.Replace("-", ""))) "the machine never prints the fingerprint itself: it can only be copied from the phone"
        $wrongA = $(if ($regA.fingerprint -ceq "0000-0000-0000") { "1111-1111-1111" } else { "0000-0000-0000" })
        Add-Typed $run $wrongA
        Check ($null -ne (Wait-PairLine -Run $run -Like "That number does not match*(2 tries left)*")) "a wrong number is refused, with the tries left"
        Add-Typed $run $regA.fingerprint
        $endA = Complete-Pair $run
        Check ($endA.code -eq 0 -and $endA.out.Contains("Confirmed: 'Founder phone'")) ("the phone's number confirms it: exit 0 (exit " + $endA.code + ")")
        $devA = @((Get-HordeRelayTrust -HordeHome $hh).value.devices | Where-Object { $_.keyId -ceq $regA.deviceKeyId }) | Select-Object -First 1
        Check ($null -ne $devA -and $devA.state -ceq "trusted" -and $devA.label -ceq "Founder phone" -and $devA.fingerprint -ceq $regA.fingerprint) "the phone's passkey is trusted, under that label and the fingerprint both screens computed"
        $deviceA = $(if ($null -ne $devA) { $devA.id } else { "" })
        Check ($png -ne "" -and -not (Test-Path -LiteralPath $png)) "the picture of the offer is deleted"
        $boxDir = Join-Path $mailboxes ($offerA.pairMailbox.Replace("/", "\"))
        Check ((Test-Path -LiteralPath $boxDir) -and @(Get-ChildItem -LiteralPath $boxDir -Filter "*.item").Count -eq 0 -and @(Get-ChildItem -LiteralPath $boxDir -Filter "floor-*").Count -eq 1) "the pairing mailbox is acked through what was read, so the relay keeps nothing"
        $run = $null
    }

    Write-Host ""
    Write-Host "--- 2. relay identity, relay trust list and relay trust revoke ---" -ForegroundColor Cyan
    $idOut = Invoke-Horde @("relay", "identity")
    Check ($idOut.code -eq 0 -and $idOut.out.Contains("horde: work") -and $idOut.out.Contains("signing key: " + $id.value.sign.keyId) -and $idOut.out.Contains("agreement key: " + $id.value.agree.keyId) -and $idOut.out.Contains("mailbox: " + $id.value.mailbox)) ("relay identity shows the horde, both key ids and the mailbox (exit " + $idOut.code + ")")
    if ($deviceA -eq "") { $deviceA = Add-HordeTestPhonePairing -HordeHome $hh -Phone (New-HordeTestPhone) }
    $pendingId = Add-HordeTestPhonePairing -HordeHome $hh -Phone (New-HordeTestPhone) -NoConfirm
    $list = Invoke-Horde @("relay", "trust", "list")
    Check ($list.code -eq 0 -and @($list.out -split "`n" | Where-Object { $_ -clike ("device " + $deviceA + "  trusted  *") }).Count -eq 1) ("relay trust list shows the device, trusted (exit " + $list.code + ")")
    $pendFp = (Get-Device -HordeHome $hh -Id $pendingId).fingerprint
    Check (@($list.out -split "`n" | Where-Object { $_ -clike ("device " + $pendingId + "  pending  *") }).Count -eq 1 -and -not $list.out.Contains($pendFp) -and -not $list.out.Contains($pendFp.Replace("-", ""))) "a pending device is listed as pending, without its fingerprint: the number pair waits for is never on the machine's screen"
    $rev = Invoke-Horde @("relay", "trust", "revoke", $deviceA, "-Reason", "phone lost")
    Check ($rev.code -eq 0 -and $rev.out.Contains("revoked the device " + $deviceA)) ("relay trust revoke ends it (exit " + $rev.code + ")")
    Check ((Get-Device -HordeHome $hh -Id $deviceA).state -ceq "revoked" -and (Get-Device -HordeHome $hh -Id $deviceA).revoked.reason -ceq "phone lost") "the store holds the revocation, with its reason"
    $list2 = Invoke-Horde @("relay", "trust", "list")
    Check (@($list2.out -split "`n" | Where-Object { $_ -clike ("device " + $deviceA + "  revoked  *phone lost*") }).Count -eq 1) "and the list shows it revoked, with why"
    $again = Invoke-Horde @("relay", "trust", "revoke", $deviceA)
    Check ($again.code -eq 0 -and $again.out.Contains("already revoked")) "revoking again says it already was"
    $none = Invoke-Horde @("relay", "trust", "revoke", ("f" * 32))
    Check ($none.code -eq 1 -and $none.out.Contains("holds no device or machine")) "revoking an id the store does not hold fails, saying so"
    Check ((Invoke-Horde @("relay", "trust", "revoke")).code -eq 1 -and (Invoke-Horde @("relay", "trust")).code -eq 1 -and (Invoke-Horde @("relay", "trust", "forget")).code -eq 1) "relay trust revoke with no id, or relay trust without list or revoke, fails"
    $emptyHome = Join-Path $work "empty-home"
    [void]$script:homes.Add($emptyHome)
    Set-PairSettings -HordeHome $emptyHome
    $noId = Invoke-Horde @("relay", "identity") $emptyHome
    Check ($noId.code -eq 1 -and $noId.out.Contains("no relay identity")) "relay identity on a machine with none fails, saying so"
    Check ((Invoke-Horde @("relay", "trust", "list") $emptyHome).out.Contains("the trust store is empty")) "an empty trust store says so"
    $noHorde = Join-Path $work "no-horde-home"
    [void]$script:homes.Add($noHorde)
    New-Item -ItemType Directory -Path $noHorde -Force | Out-Null
    $nh = Invoke-Horde @("relay", "identity", "-New", "-Provider", "software") $noHorde
    Check ($nh.code -eq 1 -and $nh.out.Contains("no horde is named") -and -not (Test-Path -LiteralPath (Join-Path $noHorde "relay\identity"))) ("relay identity -New with no horde named fails, saying what to set, and makes nothing (exit " + $nh.code + ")")
    $made = Invoke-Horde @("relay", "identity", "-New", "-Provider", "software") $emptyHome
    $madeId = Get-HordeRelayMachineIdentity -HordeHome $emptyHome
    Check ($made.code -eq 0 -and $madeId.state -ceq "known" -and $made.out.Contains("made this machine's relay identity") -and $made.out.Contains("signing key: " + $madeId.value.sign.keyId) -and $made.out.Contains("mailbox: " + $madeId.value.mailbox)) ("relay identity -New makes the identity, in the provider asked, and shows it (exit " + $made.code + ")")
    Check ($madeId.state -ceq "known" -and $madeId.value.sign.provider -ceq "software") "the keys are in the provider asked for"
    $twice = Invoke-Horde @("relay", "identity", "-New", "-Provider", "software") $emptyHome
    Check ($twice.code -eq 1 -and $twice.out.Contains("already has a relay identity") -and (Get-HordeRelayMachineIdentity -HordeHome $emptyHome).value.sign.keyId -ceq $madeId.value.sign.keyId) "relay identity -New again is refused, and the identity stays the one made"
    Check ((Invoke-Horde @("relay", "identity", "-Provider", "software") $emptyHome).code -eq 1) "-Provider without -New is refused"
    Check ((Invoke-Horde @("relay", "identity", "-New", "-Provider", "nosuch") $emptyHome).code -eq 2) "an unknown provider is refused as a wrong command line (exit 2)"

    Write-Host ""
    Write-Host "--- 3. what a relay can put in the pairing mailbox is refused, and the phone still pairs ---" -ForegroundColor Cyan
    $run = Start-Pair -More @("-Relay", "local", "-RelayRoot", $mailboxes)
    $offerC = Get-OfferOf $run
    $phoneC = New-HordeTestPhone
    $oldOffer = New-HordeRelayPairingOffer -HordeHome $hh -RpId $rp -Origins @("https://" + $rp)
    $oldSealed = New-HordeRelayPairingSealedText -OfferText $oldOffer.value.text -Response (New-HordeTestPhonePairingResponse -Offer $oldOffer.value -Phone (New-HordeTestPhone))
    [void](Send-HordeRelayItem -Connection $c.value -Mailbox $offerC.pairMailbox -Text $oldSealed)
    [void](Send-HordeRelayItem -Connection $c.value -Mailbox $offerC.pairMailbox -Text "not a pairing response at all")
    $wrongCode = New-HordeRelayPairingSealedText -OfferText $offerC.text -Response (New-HordeTestPhonePairingResponse -Offer $offerC -Phone (New-HordeTestPhone) -Code "AAAAAAAAAAAAAAAAAAAAAA")
    [void](Send-HordeRelayItem -Connection $c.value -Mailbox $offerC.pairMailbox -Text $wrongCode)
    $good = New-HordeRelayPairingSealedText -OfferText $offerC.text -Response (New-HordeTestPhonePairingResponse -Offer $offerC -Phone $phoneC)
    [void](Send-HordeRelayItem -Connection $c.value -Mailbox $offerC.pairMailbox -Text $good)
    Check ($null -ne (Wait-PairLine -Run $run -Like "*Type that number here*")) "the phone's own response gets through after the rest"
    Add-Typed $run (Get-Fingerprint -Offer $offerC -Phone $phoneC)
    $endC = Complete-Pair $run
    $refusedC = @($endC.out -split "`n" | Where-Object { $_ -clike "refused what the relay brought*" })
    Check ($endC.code -eq 0 -and $refusedC.Count -eq 3) ("exit 0, after three refusals (exit " + $endC.code + ", " + $refusedC.Count + " refused)")
    Check ($endC.out.Contains("item 1): the sealed response is for the offer " + $oldOffer.value.offer) -and $endC.out.Contains("item 2): the sealed pairing response is not in its canonical form") -and $endC.out.Contains("item 3): the code is not this offer's")) "an old offer's sealed response, junk, and a response with the wrong code are each refused by name"
    Check ((Get-Device -HordeHome $hh -Id (Get-HordeRelayDeviceId -CredentialId $phoneC.credentialId)).state -ceq "trusted") "and the phone is trusted"
    $run = $null

    Write-Host ""
    Write-Host "--- 4. a thief who answers the offer first is never confirmed by the founder's number ---" -ForegroundColor Cyan
    $run = Start-Pair -More @("-Relay", "local", "-RelayRoot", $mailboxes)
    $offerD = Get-OfferOf $run
    $thief = New-HordeTestPhone
    $founder = New-HordeTestPhone
    [void](Send-HordeRelayItem -Connection $c.value -Mailbox $offerD.pairMailbox -Text (New-HordeRelayPairingSealedText -OfferText $offerD.text -Response (New-HordeTestPhonePairingResponse -Offer $offerD -Phone $thief -Label "Founder phone")))
    Check ($null -ne (Wait-PairLine -Run $run -Like "*Type that number here*")) "the thief's response registers first, as a pending device"
    [void](Send-HordeRelayItem -Connection $c.value -Mailbox $offerD.pairMailbox -Text (New-HordeRelayPairingSealedText -OfferText $offerD.text -Response (New-HordeTestPhonePairingResponse -Offer $offerD -Phone $founder)))
    $fpFounder = Get-Fingerprint -Offer $offerD -Phone $founder
    foreach ($i in 1..3) { Add-Typed $run $fpFounder }
    $endD = Complete-Pair $run
    $thiefDev = Get-Device -HordeHome $hh -Id (Get-HordeRelayDeviceId -CredentialId $thief.credentialId)
    Check ($endD.code -eq 1 -and $endD.out.Contains("three times") -and $null -ne $thiefDev -and $thiefDev.state -ceq "revoked") ("the number on the founder's phone never matches the thief's device; three tries reject it (exit " + $endD.code + ")")
    Check ($null -eq (Get-Device -HordeHome $hh -Id (Get-HordeRelayDeviceId -CredentialId $founder.credentialId))) "and the founder's late response enrolled nothing: the offer was single use"
    $run = $null

    Write-Host ""
    Write-Host "--- 5. no relay named: the response is pasted ---" -ForegroundColor Cyan
    $run = Start-Pair
    $offerE = Get-OfferOf $run
    Check ($null -ne (Wait-PairLine -Run $run -Like "No relay is named (-Relay), so paste*")) "with no -Relay it says to paste the response"
    $phoneE = New-HordeTestPhone
    Add-Typed $run "hello"
    Check ($null -ne (Wait-PairLine -Run $run -Like "refused: that is not a pairing response*")) "a line that is not a response is refused, and the wait goes on"
    Add-Typed $run (New-HordeTestPhonePairingResponse -Offer $oldOffer.value -Phone (New-HordeTestPhone))
    Check ($null -ne (Wait-PairLine -Run $run -Like "refused: that response answers another offer*")) "a response to another offer is refused without ending this pairing"
    Add-Typed $run (New-HordeTestPhonePairingResponse -Offer $offerE -Phone $phoneE)
    Check ($null -ne (Wait-PairLine -Run $run -Like "*Type that number here*")) "the phone's response, pasted, registers it"
    Add-Typed $run ((Get-Fingerprint -Offer $offerE -Phone $phoneE).Replace("-", " "))
    $endE = Complete-Pair $run
    Check ($endE.code -eq 0 -and (Get-Device -HordeHome $hh -Id (Get-HordeRelayDeviceId -CredentialId $phoneE.credentialId)).state -ceq "trusted") ("and its number, typed with spaces, confirms it (exit " + $endE.code + ")")
    $run = $null

    Write-Host ""
    Write-Host "--- 6. the command line's refusals ---" -ForegroundColor Cyan
    $noApp = Join-Path $work "no-app-home"
    [void]$script:homes.Add($noApp)
    Set-PairSettings -HordeHome $noApp -App $false
    [void](New-HordeRelayMachineIdentity -HordeHome $noApp -Provider "software")
    $r6 = Invoke-Horde @("relay", "pair", "-NoPicture") $noApp
    Check ($r6.code -eq 1 -and $r6.out.Contains("no phone app is named")) "with no phone app named by flag or setting, pair fails and says what to set"
    Check (@(Get-ChildItem -LiteralPath (Join-Path $noApp "relay") -Recurse -Filter "*.json" | Where-Object { $_.DirectoryName -like "*offers" }).Count -eq 0) "and made no offer"
    $r6b = Invoke-Horde @("relay", "pair", "-MaxTurns", "3")
    Check ($r6b.code -eq 1 -and $r6b.out.Contains("-MaxTurns does not belong to relay pair")) "a flag of another verb is refused"
    $r6c = Invoke-Horde @("relay", "pair", "-Relay", "nosuch", "-NoPicture")
    Check ($r6c.code -eq 1 -and $r6c.out.Contains("no relay named 'nosuch'")) "a relay that is not loaded is refused"
    $r6d = Invoke-Horde @("relay", "pair", "-Label", ("x" * 65), "-NoPicture")
    Check ($r6d.code -eq 1 -and $r6d.out.Contains("-Label is 1 to 64")) "a label the trust store cannot keep is refused before any offer"
    Check ((Invoke-Horde @("relay", "identity", "-Relay", "local")).code -eq 1) "relay identity takes no relay"

    Write-Host ""
    Write-Host "--- 7. in this process: a hostile relay, a flood, an expiry, reject, an interruption ---" -ForegroundColor Cyan
    $hostile = Connect-HordeRelay -Name "hostile"
    $said = New-Object System.Collections.ArrayList
    $typed = Join-Path $work "typed-in-process.txt"
    $script:onOffer = $null
    $say = { param($Line) [void]$said.Add($Line); if ($Line.StartsWith('{"v":1,"kind":"horde-relay-pairing-offer"') -and $null -ne $script:onOffer) { & $script:onOffer $Line } }
    function Get-PendingOffer { param([string]$Text) $r = Read-HordeRelayPairingOffer -Text $Text; $p = Read-HordeRelayRecordText -Text ([System.IO.File]::ReadAllText((Join-Path $hh ("relay\pairing\offers\" + $r.value.offer + ".json")))) -Spec (Get-HordeRelayPendingSpec) -Kind "horde-relay-pairing-pending"; return [pscustomobject]@{ text = $Text; offer = $r.value.offer; code = $r.value.code; pairMailbox = $r.value.pairMailbox; challenge = $p.value.challenge } }

    Reset-HordeHostileRelay
    Set-HordeHostileRelayFaults -Faults @("reorder", "duplicate", "stale", "garbage", "conflict")
    $phoneG = New-HordeTestPhone
    [System.IO.File]::WriteAllText($typed, "", $ascii)
    $script:onOffer = {
        param($Text)
        $o = Get-PendingOffer $Text
        [void](Send-HordeRelayItem -Connection $hostile.value -Mailbox $o.pairMailbox -Text "junk before")
        [void](Send-HordeRelayItem -Connection $hostile.value -Mailbox $o.pairMailbox -Text (New-HordeRelayPairingSealedText -OfferText $o.text -Response (New-HordeTestPhonePairingResponse -Offer $o -Phone $phoneG)))
        [void](Send-HordeRelayItem -Connection $hostile.value -Mailbox $o.pairMailbox -Text "junk after")
        [System.IO.File]::AppendAllText($typed, (Get-Fingerprint -Offer $o -Phone $phoneG) + "`n", $ascii)
    }
    $g = Invoke-HordeRelayPair -HordeHome $hh -Connection $hostile.value -InputFile $typed -Say $say
    Check ($g.ok -and $g.device.state -ceq "trusted" -and $g.device.id -ceq (Get-HordeRelayDeviceId -CredentialId $phoneG.credentialId)) ("through a relay that reorders, repeats, serves stale items and salts the mailbox with garbage, the phone pairs once (" + $g.reason + ")")
    Check (@($said | Where-Object { $_ -clike "relay: *" }).Count -gt 0) "and what the relay did wrong is said, as the relay's"
    Set-HordeHostileRelayFaults -Faults @()

    # A clock that moves 100 s a look: the runs below that wait end in seconds whatever goes wrong, and
    # never after the offer's or the confirm window's real minutes.
    $script:fake = [datetime]::UtcNow
    $clock = { $script:fake = $script:fake.AddSeconds(100); $script:fake }
    $said.Clear()
    $script:onOffer = { param($Text) $o = Get-PendingOffer $Text; foreach ($i in 1..40) { [void](Send-HordeRelayItem -Connection $hostile.value -Mailbox $o.pairMailbox -Text ("flood " + $i)) } }
    $script:fake = [datetime]::UtcNow
    # Five seconds a look here: the relay hands the flood over a batch at a time, and the cap must be
    # reached well inside the offer's 300 s.
    $fl = Invoke-HordeRelayPair -HordeHome $hh -Connection $hostile.value -InputFile $typed -Say $say -Clock { $script:fake = $script:fake.AddSeconds(5); $script:fake }
    Check ((-not $fl.ok) -and $fl.reason.Contains("32 refused items") -and @($said | Where-Object { $_ -clike "refused what the relay brought*" }).Count -eq 32) ("a mailbox flooded with junk is given up after 32 refusals, not opened until the offer expires (" + $fl.reason + ")")

    # Pictures left by a pairing that was killed outright: swept when the next one starts, once older
    # than the longest an offer lives (900 s); a younger one, or another file, is left alone.
    $pics = Join-Path $work "pictures"
    New-Item -ItemType Directory -Path $pics -Force | Out-Null
    $stale = Join-Path $pics ("horde-pair-" + ("a" * 32) + ".png")
    $young = Join-Path $pics ("horde-pair-" + ("b" * 32) + ".png")
    $other = Join-Path $pics ("horde-pair-notes-" + ("c" * 32) + ".png")
    foreach ($f in @($stale, $young, $other)) { [System.IO.File]::WriteAllBytes($f, [byte[]](1, 2, 3)) }
    [System.IO.File]::SetLastWriteTimeUtc($stale, [datetime]::UtcNow.AddSeconds(-901))
    [System.IO.File]::SetLastWriteTimeUtc($young, [datetime]::UtcNow.AddSeconds(-600))
    [System.IO.File]::SetLastWriteTimeUtc($other, [datetime]::UtcNow.AddHours(-2))
    $script:fake = [datetime]::UtcNow
    $script:onOffer = $null
    $script:pic = ""
    $sw = Invoke-HordeRelayPair -HordeHome $hh -InputFile (Join-Path $work "never-typed.txt") -Say $say -Clock $clock -PictureDir $pics -OpenPicture { param($Path) $script:pic = $Path }
    Check ((-not (Test-Path -LiteralPath $stale)) -and (Test-Path -LiteralPath $young) -and (Test-Path -LiteralPath $other)) "a pairing that starts sweeps the pictures older than the longest offer life, and leaves a younger one and another file"
    Check ($script:pic.StartsWith($pics) -and -not (Test-Path -LiteralPath $script:pic) -and -not $sw.ok) "and puts its own picture there, deleted when it ends"
    $script:fake = [datetime]::UtcNow
    $script:onOffer = $null
    $script:pic = ""
    $ex = Invoke-HordeRelayPair -HordeHome $hh -InputFile (Join-Path $work "never-typed.txt") -Say $say -Clock $clock -OpenPicture { param($Path) $script:pic = $Path }
    Check ((-not $ex.ok) -and $ex.reason.Contains("expired") -and $ex.reason.Contains("nothing was enrolled") -and -not (Test-Path -LiteralPath (Join-Path $hh ("relay\pairing\used\" + $ex.offer.offer + ".json")))) ("an offer nobody answers expires cleanly, with nothing enrolled (" + $ex.reason + ")")
    Check ($script:pic -ne "" -and -not (Test-Path -LiteralPath $script:pic)) "and its picture, opened, is deleted"

    $phoneR = New-HordeTestPhone
    [System.IO.File]::WriteAllText($typed, "", $ascii)
    $script:onOffer = { param($Text) $o = Get-PendingOffer $Text; [System.IO.File]::AppendAllText($typed, (New-HordeTestPhonePairingResponse -Offer $o -Phone $phoneR) + "`nreject`n", $ascii) }
    $script:fake = [datetime]::UtcNow
    $rj = Invoke-HordeRelayPair -HordeHome $hh -InputFile $typed -Say $say -Clock $clock
    Check ((-not $rj.ok) -and $rj.reason.Contains("rejected") -and (Get-Device -HordeHome $hh -Id (Get-HordeRelayDeviceId -CredentialId $phoneR.credentialId)).state -ceq "revoked") "reject, typed, rejects the device that registered: it is revoked"

    # The offer used behind the command's back (a thief who completed it first): the founder's sealed
    # response is refused naming the device that took the offer - but not its fingerprint.
    $said.Clear()
    $thiefH = New-HordeTestPhone
    $script:onOffer = {
        param($Text)
        $o = Get-PendingOffer $Text
        $t = Complete-HordeRelayPairing -HordeHome $hh -Response (New-HordeTestPhonePairingResponse -Offer $o -Phone $thiefH)
        $script:thiefId = $t.value.device.id
        [void](Send-HordeRelayItem -Connection $hostile.value -Mailbox $o.pairMailbox -Text (New-HordeRelayPairingSealedText -OfferText $o.text -Response (New-HordeTestPhonePairingResponse -Offer $o -Phone (New-HordeTestPhone))))
    }
    $script:fake = [datetime]::UtcNow
    $used = Invoke-HordeRelayPair -HordeHome $hh -Connection $hostile.value -InputFile $typed -Say $say -Clock { $script:fake = $script:fake.AddSeconds(5); $script:fake }
    [void]$script:machineSaid.Add($used.reason)
    Check ((-not $used.ok) -and $used.reason.Contains("already used") -and $used.reason.Contains($script:thiefId)) ("an offer used behind its back ends the pairing, naming the device that used it (" + $used.reason + ")")

    # A revocation that cannot be written is not reported as done: the device stays pending, and the
    # founder is told the command that ends it.
    foreach ($how in @("reject", "three wrong")) {
        $phoneF = New-HordeTestPhone
        [System.IO.File]::WriteAllText($typed, "", $ascii)
        $script:how = $how
        $script:onOffer = { param($Text) $o = Get-PendingOffer $Text; $lines = $(if ($script:how -ceq "reject") { "reject" } else { "0000-0000-0001`n0000-0000-0002`n0000-0000-0003" }); [System.IO.File]::AppendAllText($typed, (New-HordeTestPhonePairingResponse -Offer $o -Phone $phoneF) + "`n" + $lines + "`n", $ascii) }
        $script:fake = [datetime]::UtcNow
        $rf = & {
            function Revoke-HordeRelayTrust { return (New-HordeUnknown -Reason "the disk is full (a stand-in)") }
            Invoke-HordeRelayPair -HordeHome $hh -InputFile $typed -Say $say -Clock { $script:fake = $script:fake.AddSeconds(5); $script:fake }
        }
        $devF = Get-Device -HordeHome $hh -Id (Get-HordeRelayDeviceId -CredentialId $phoneF.credentialId)
        Check ((-not $rf.ok) -and $devF.state -ceq "pending" -and $rf.reason.Contains("stays pending") -and $rf.reason.Contains("horde relay trust revoke " + $devF.id) -and -not $rf.reason.Contains("is revoked")) ("with " + $how + ", a revocation that fails is said to have failed, with the command that ends the device (" + $rf.reason + ")")
        Check ((Revoke-HordeRelayTrust -HordeHome $hh -Subject "device" -Id $devF.id -Reason "suite cleanup").state -ceq "known") "CONTROL: that device is then revoked by hand"
    }

    # A relay whose watch fails at once must not be hit in a tight loop: in real time, the first retry
    # waits 5 s, so an offer of 3 s sees one watch.
    $script:watches = 0
    $downOffer = [pscustomobject]@{ offer = ("a" * 32); pairMailbox = "work/pair-" + ("a" * 32); expiresAt = [long]([System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + 3000) }
    $down = & {
        function Wait-HordeRelayItems { param($Connection, $Mailbox, $Since, $TimeoutMs) $script:watches++; return (New-HordeUnknown -Reason "connection refused (a stand-in)") }
        Wait-HordeRelayPairResponse -HordeHome (Join-Path $work "no-such-home") -Offer $downOffer -Connection $hostile.value -Source (New-HordeRelayPairInput -InputFile (Join-Path $work "never-typed.txt")) -Label "" -Say { param($l) } -Clock { [datetime]::UtcNow }
    }
    Check ((-not $down.ok) -and $down.reason.Contains("expired") -and $script:watches -eq 1) ("a relay that fails at once is not tried again for 5 s, in real time (" + $script:watches + " watches in 3 s)")

    # THE HOSTED RELAY REFUSES THIS MACHINE UNTIL THE PHONE REGISTERS IT (the founder's first live use,
    # 2026-10-11): 401 until then, and a watch every 1 to 6 s tripped the Worker's refused-signature
    # limit, 429, for about 90 s, with the raw 401 and 429 said on every try. Driven on a fake clock that
    # the keyboard's wait moves: each watch's time is recorded, so the gaps between tries are measured.
    function Invoke-RefusedWait {
        # -Answer: one script block for every watch, by its number (1, 2, ...), returning the watch's answer.
        # -Typed: the line the keyboard gives on its Nth wait, by N, a second into it. { result; gaps; said }.
        param([scriptblock]$Answer, [hashtable]$Typed = @{}, [long]$LifeMs = 300000)
        $script:fake = [datetime]::UtcNow
        $script:at = New-Object System.Collections.ArrayList
        $script:reads = 0
        $script:answerOf = $Answer
        $script:typedOf = $Typed
        $saidHere = New-Object System.Collections.ArrayList
        $o = [pscustomobject]@{ offer = ("c" * 32); pairMailbox = "work/pair-" + ("c" * 32); expiresAt = [long]((ConvertTo-HordeRelayRecordMs -Time $script:fake) + $LifeMs) }
        $res = & {
            function Wait-HordeRelayItems { param($Connection, $Mailbox, $Since, $TimeoutMs) [void]$script:at.Add((ConvertTo-HordeRelayRecordMs -Time $script:fake)); return (& $script:answerOf $script:at.Count) }
            function Read-HordeRelayPairLine { param($Source, [int]$TimeoutMs = 0, [switch]$Block) $script:reads++; if ($script:typedOf.ContainsKey($script:reads)) { $script:fake = $script:fake.AddMilliseconds([System.Math]::Min(1000, $TimeoutMs)); return $script:typedOf[$script:reads] }; $script:fake = $script:fake.AddMilliseconds($TimeoutMs); return $null }
            Wait-HordeRelayPairResponse -HordeHome (Join-Path $work "no-such-home") -Offer $o -Connection $hostile.value -Source $null -Label "" -Say { param($l) [void]$saidHere.Add($l) } -Clock { $script:fake }
        }
        $gaps = @()
        for ($i = 1; $i -lt $script:at.Count; $i++) { $gaps += [long]($script:at[$i] - $script:at[$i - 1]) }
        return [pscustomobject]@{ result = $res; gaps = $gaps; said = @($saidHere) }
    }
    function New-Refusal { param([int]$Status, [long]$RetryAfterMs = -1) $u = New-HordeUnknown -Reason ("relay 'hosted' could not do the watch: (" + $Status + ") a stand-in"); $u | Add-Member -NotePropertyName status -NotePropertyValue $Status; if ($RetryAfterMs -ge 0) { $u | Add-Member -NotePropertyName retryAfterMs -NotePropertyValue $RetryAfterMs }; return $u }
    # 401 and 429 in turn, as the founder's log shows them: the fourth, a 429, asks for 40 s; the other
    # 429s ask for 1 s, which never makes a retry sooner than its turn.
    $rw = Invoke-RefusedWait -Answer { param($n) if ($n -eq 4) { return (New-Refusal -Status 429 -RetryAfterMs 40000) }; if ($n % 2 -eq 0) { return (New-Refusal -Status 429 -RetryAfterMs 1000) }; return (New-Refusal -Status 401) }
    $first = ($rw.gaps | Select-Object -First 4) -join ","
    $rest = @($rw.gaps | Select-Object -Skip 4 | Select-Object -SkipLast 1)
    Check ($first -ceq "5000,10000,15000,40000") ("a relay that refuses is asked again after 5 s, then 10, then 15, and after its Retry-After when that is longer (" + $first + ")")
    Check ($rest.Count -ge 10 -and @($rest | Where-Object { $_ -ne 15000 }).Count -eq 0) ("and every 15 s after that, never faster, until the offer expires (" + (($rest | Select-Object -First 12) -join ",") + ", ...)")
    Check ((-not $rw.result.ok) -and $rw.result.reason.Contains("expired")) "and the offer still expires in words"
    $waiting = @($rw.said | Where-Object { $_.Contains("waiting for the phone to register this machine") })
    $raw = @($rw.said | Where-Object { $_.Contains("401") -or $_.Contains("429") -or $_.Contains("a stand-in") })
    Check ($waiting.Count -eq 1 -and $raw.Count -eq 0) ("401 and 429 in turn are said once, plainly, as waiting for the phone to register this machine - not the relay's raw words on every try (" + ($rw.said -join " | ") + ")")
    # A watch that works resets the wait: the next refusal waits 5 s again.
    $rr = Invoke-RefusedWait -LifeMs 60000 -Answer { param($n) if ($n -eq 3) { return (New-HordeKnown -Value ([pscustomobject]@{ items = @(); anomalies = @() })) }; return (New-Refusal -Status 401) }
    Check ((($rr.gaps | Select-Object -First 4) -join ",") -ceq "5000,10000,0,5000") ("a watch that works resets the wait, so the next refusal is asked again after 5 s (" + (($rr.gaps | Select-Object -First 6) -join ",") + ", ...)")
    # Another failure is said in its own words, once; a refusal after it is said once again.
    $ro = Invoke-RefusedWait -LifeMs 60000 -Answer { param($n) if ($n -le 2) { return (New-HordeUnknown -Reason "connection refused (a stand-in)") }; return (New-Refusal -Status 401) }
    Check (@($ro.said | Where-Object { $_.Contains("connection refused (a stand-in)") }).Count -eq 1 -and @($ro.said | Where-Object { $_.Contains("waiting for the phone to register this machine") }).Count -eq 1) ("a relay that cannot be reached is said in its words once, and the refusal after it once (" + ($ro.said -join " | ") + ")")
    # A line pasted while it waits is read at once, and does not bring the next watch forward.
    $rp = Invoke-RefusedWait -LifeMs 60000 -Typed @{ 1 = "not a response" } -Answer { param($n) return (New-Refusal -Status 401) }
    Check (@($rp.said | Where-Object { $_.Contains("refused: that is not a pairing response") }).Count -eq 1 -and $rp.gaps[0] -eq 5000) ("a line pasted while it waits is taken at once, and the next watch still waits its 5 s (" + (($rp.gaps | Select-Object -First 3) -join ",") + ", ...)")

    $script:pic = ""
    # Ctrl+C stops the pipeline, which unwinds through every finally block as a terminating error does;
    # a PipelineStoppedException itself cannot be caught by a suite, so a plain one stands in for it.
    $script:onOffer = { param($Text) throw "interrupted, as Ctrl+C would" }
    $stopped = $false
    try { [void](Invoke-HordeRelayPair -HordeHome $hh -InputFile $typed -Say $say -OpenPicture { param($Path) $script:pic = $Path }) } catch { $stopped = ("" + $_.Exception.Message).Contains("interrupted") }
    Check ($stopped -and $script:pic -ne "" -and -not (Test-Path -LiteralPath $script:pic)) "an interruption while it waits (Ctrl+C) still deletes the picture of the offer"
    $cut = [regex]::Match([System.IO.Path]::GetFileName($script:pic), '[0-9a-f]{32}').Value
    $after = Get-HordeRelayOpenOffer -HordeHome $hh -Offer $cut
    Check ((-not $after.ok) -and $after.reason.Contains("already used")) "and voids its offer: a phone that answers it later enrolls nothing"
    $script:onOffer = $null

    foreach ($l in @($said)) { [void]$script:machineSaid.Add($l) }
    foreach ($x in @($g, $fl, $sw, $ex, $rj)) { [void]$script:machineSaid.Add($x.reason) }
    $fps = New-Object System.Collections.ArrayList
    foreach ($h in @($hh, $emptyHome)) { foreach ($d in @((Get-HordeRelayTrust -HordeHome $h).value.devices)) { [void]$fps.Add($d.fingerprint) } }
    $all = ($script:machineSaid -join "`n")
    $shown = @($fps | Where-Object { $all.Contains($_) -or $all.Contains($_.Replace("-", "")) -or $all.Contains($_.Replace("-", " ")) })
    Check ($fps.Count -ge 8 -and $script:machineSaid.Count -ge 20 -and $shown.Count -eq 0) ("no fingerprint of any device, in any state, is in anything the machine printed or answered: pair, trust, identity, refusals (" + $fps.Count + " fingerprints, " + $script:machineSaid.Count + " outputs, " + $shown.Count + " shown)")
} finally {
    Stop-HordeCliRun $run
    $made = New-Object System.Collections.ArrayList
    foreach ($h in @($script:homes)) {
        $dir = Join-Path $h "relay\identity"
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter "machine-*.json")) {
            $m = [regex]::Match([System.IO.File]::ReadAllText($f.FullName), '"scope":"([a-z]+)","signName":"([a-z0-9-]+)".*"agreeName":"([a-z0-9-]+)"')
            if ($m.Success) { foreach ($k in @($m.Groups[2].Value, $m.Groups[3].Value)) { [void]$made.Add(@{ n = $k; s = $m.Groups[1].Value }); try { [void](Remove-HordeRelayKey -Name $k -Scope $m.Groups[1].Value) } catch { } } }
        }
    }
    $left = @($made | Where-Object { (Find-HordeRelayCngKey -Name $_.n -Scope $_.s) -cne "" })
    Check ($made.Count -ge 4 -and $left.Count -eq 0) ("every key the suite's homes made is gone (" + $made.Count + " names, " + $left.Count + " left)")
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    Check (-not (Test-Path -LiteralPath $work)) "the suite's folder is gone"
}

if ($partial) { Complete-HordeSuite -Success "horde relay pair, trust and identity hold; the WebCrypto phone was not here (no node)" -PassCode 3 }
Complete-HordeSuite -Success "horde relay pair pairs the phone through the relay or a paste, confirmed only by the number typed from the phone; trust and identity say what the machine knows"
