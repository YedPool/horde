# DOES "ADD THIS PHONE" WORK END TO END - THE NEW PHONE'S OWN CODE, A TRUSTED PHONE'S OWN CODE, AND THE
# REAL `horde relay run` - AND DOES IT TRUST NOTHING UNTIL THE NUMBER IS TYPED?
#
# Phone-started pairing (relay/Join.ps1, channels/join, phone-core.js ADD THIS PHONE and A NEW PHONE ASKS
# TO JOIN). Two phones, each the app's logic built as it ships and run under Node (app-phone.mjs, a
# software passkey, a store in memory), over the local relay's folders, and the shipped horde.ps1 as the
# machine:
#   1. the TRUSTED phone pairs the usual way and is announced;
#   2. a STRANGER signed in to the same account asks to join: the machine answers, the stranger makes its
#      passkey and shows a number nobody types; the trusted phone sees the request - with no number in
#      it - refuses a wrong number LOCALLY, sending nothing, and rejects it: the stranger's passkey is
#      revoked, and every device is told;
#   3. the slot is free at once: the founder's NEW phone asks, is answered, makes its passkey; the
#      trusted phone approves with the number the new phone shows; the machine trusts it, tells it so
#      (Finish pairing), and its one-prompt announcement brings it the open question.
#
# NEEDS node. Without it the suite says so and exits 3, a partial run, never 0.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\FleetPin.ps1")
$fleetPin = Enter-HordeTestEmptyFleet
. (Join-Path $root "core\ModuleSettings.ps1")
. (Join-Path $root "channels\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
foreach ($f in @(Get-HordeRelayChannelFiles)) { . $f }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "surfaces\pwa\Site.ps1")
Set-StrictMode -Version Latest

$node = Get-Command -Name "node" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) {
    Write-Host "  [SKIP] node is not installed here, so there is no phone app to run" -ForegroundColor Yellow
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "skipped: no node, so no phone app" -PassCode 3
}
if ((Get-HordeRelayKeyStore).state -cne "known") {
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "skipped: no key store here, so no machine identity" -PassCode 3
}

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$realHome = $env:HORDE_HOME
$work = Join-Path $env:TEMP ("horde-pwa-join-" + [guid]::NewGuid().ToString("N"))
$hh = Join-Path $work "home"
$mailboxes = Join-Path $work "relay"
$site = Join-Path $work "site"
New-Item -ItemType Directory -Path (Join-Path $hh "settings"), $mailboxes -Force | Out-Null
$origin = "https://relay.example.test"
$keysMade = @()
$apps = @{}
$canDecide = $false

function ConvertTo-AsciiJson {
    param($Value)
    $t = ConvertTo-Json -InputObject $Value -Compress -Depth 8
    return ([regex]::Replace($t, '[^\x20-\x7E]', { param($m) '\u' + ([int][char]$m.Value).ToString("x4") }))
}
function Start-App {
    param([string]$Name)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $node.Source
    $psi.Arguments = '"' + (Join-Path $here "app-phone.mjs") + '" "' + $site + '" "' + $mailboxes + '" ' + $origin + ' on'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $script:apps[$Name] = [pscustomobject]@{ p = $p; err = $p.StandardError.ReadToEndAsync() }
}
function Invoke-App {
    param([string]$Name, [hashtable]$Command)
    $a = $script:apps[$Name]
    $a.p.StandardInput.WriteLine((ConvertTo-AsciiJson $Command))
    $a.p.StandardInput.Flush()
    $read = $a.p.StandardOutput.ReadLineAsync()
    if (-not $read.Wait(60000)) { throw ("the app " + $Name + " did not answer in 60 s") }
    if ($null -eq $read.Result) { throw ("the app " + $Name + " ended: " + $a.err.Result) }
    return ($read.Result | ConvertFrom-Json)
}
function Invoke-Run {
    param([int]$Turns = 1)
    return (Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "run", "-Relay", "local", "-RelayRoot", $mailboxes, "-MaxTurns", "" + $Turns) -Env @{ HORDE_HOME = $hh })
}
function Get-DeviceOf { param([string]$Label) return (@((Get-HordeRelayTrust -HordeHome $hh).value.devices | Where-Object { $_.label -ceq $Label }) | Select-Object -First 1) }
function Get-NoticeTexts {
    $p = Join-Path $hh "notices\notices.jsonl"
    if (-not (Test-Path -LiteralPath $p)) { return @() }
    return @(Get-Content -LiteralPath $p | Where-Object { $_.Trim() } | ForEach-Object { ($_ | ConvertFrom-Json).text })
}
function Get-Head {
    param([string]$Mailbox)
    $dir = Join-Path $mailboxes ($Mailbox.Replace("/", "\"))
    $seqs = @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | ForEach-Object { if ($_.Name -match '\A([0-9]{16})-' -or $_.Name -match '\Afloor-([0-9]{16})\z') { [long]$Matches[1] } })
    if ($seqs.Count -eq 0) { return 0 }
    return ($seqs | Measure-Object -Maximum).Maximum
}

try {
    $env:HORDE_HOME = $hh
    $built = New-HordePwaSite -Out $site -Transport "binding"
    Check ($built.state -ceq "known") "CONTROL: the site is built as it ships"
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay.json"), '{"schemaVersion": 1, "settings": {"horde": "work", "pairRpId": "relay.example.test", "pairOrigin": "https://relay.example.test"}}', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay-run.json"), '{"schemaVersion": 1, "settings": {"watchMs": 200}}', $utf8)
    $id = New-HordeRelayMachineIdentity -HordeHome $hh -Provider "software"
    Check ($id.state -ceq "known") "CONTROL: the machine has its relay identity"
    $keysMade = @(@{ n = $id.value.sign.name; s = $id.value.scope }, @{ n = $id.value.agree.name; s = $id.value.scope })
    $machine = $id.value.sign.keyId
    $store = Join-Path $hh "store\decisions"
    $title = "Which phone should be the second one?"
    $q = Invoke-HordeDecision -Operation "add" -Root $store -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = @{ title = $title; kind = "yes-no"; whatItIs = "The founder adds a phone from the phone."; group = "relay"; askedBy = "orc-f" } }
    $canDecide = ($q.state -ceq "known" -and $q.value.outcome -ceq "done")
    if (-not $canDecide) { Write-Host "  [SKIP] the decisions list cannot add a question under this runtime (issue #173): the scenario is not run" -ForegroundColor Yellow }
    if ($canDecide -and $built.state -ceq "known") {
    Start-App "T"; Start-App "S"; Start-App "N"

    Write-Host ""
    Write-Host "--- 1. the trusted phone, paired the usual way ---" -ForegroundColor Cyan
    $offer = New-HordeRelayPairingOffer -HordeHome $hh -RpId "relay.example.test" -Origins @($origin)
    $tp = Invoke-App "T" @{ cmd = "pair"; offer = $offer.value.text; label = "Founder phone" }
    $td = Complete-HordeRelayPairing -HordeHome $hh -Response $(if ($tp.ok) { $tp.value.response } else { "" })
    $tc = Confirm-HordeRelayDevice -HordeHome $hh -Id $(if ($td.ok) { $td.value.device.id } else { "none" }) -Fingerprint $(if ($tp.ok) { $tp.value.fingerprint } else { "" })
    $ta = Invoke-App "T" @{ cmd = "announce"; id = $tp.value.id }
    $run = Invoke-Run -Turns 2
    $tid = $tp.value.id
    Check ($tp.ok -and $tc.ok -and $ta.ok -and $run.out.Contains("is now in the trust store")) "CONTROL: the founder's trusted phone is paired, confirmed and announced"

    Write-Host ""
    Write-Host "--- 2. a stranger in the same account asks; the trusted phone sees it, and rejects it ---" -ForegroundColor Cyan
    $sj = Invoke-App "S" @{ cmd = "join"; horde = "work"; machine = $machine; label = "Stranger"; agent = "Chrome on Android" }
    Check ($sj.ok -and $sj.value.request -cmatch '\A[0-9a-f]{32}\z') "the stranger's phone asks to join: a request, which is all signing in gives it"
    $run = Invoke-Run -Turns 2
    $so = Invoke-App "S" @{ cmd = "joinOffer"; request = $sj.value.request }
    Check ($run.code -eq 0 -and $so.ok -and $so.value.offerText.StartsWith('{"v":1,"kind":"horde-relay-pairing-offer"')) ("THE MACHINE ANSWERS AT ONCE: the phone opens the offer sealed to its request key (" + $(if ($so.ok) { "" } else { $so.reason }) + " | " + (($run.out -split "`n" | Where-Object { $_ -match "join|refused|held" }) -join " / ") + ")")
    $sp = Invoke-App "S" @{ cmd = "pair"; offer = $so.value.offerText; label = "Stranger"; joined = $true }
    $run = Invoke-Run -Turns 2
    $sdev = Get-DeviceOf "Stranger"
    Check ($sp.ok -and $sp.value.fingerprint -cmatch '\A[0-9]{4}-[0-9]{4}-[0-9]{4}\z' -and $null -ne $sdev -and $sdev.state -ceq "pending") ("the stranger makes its passkey and shows its number; the machine holds the passkey PENDING (" + $(if ($null -ne $sdev) { $sdev.state } else { "none" }) + ")")
    $null = Invoke-App "T" @{ cmd = "refresh"; id = $tid }
    $reqs = Invoke-App "T" @{ cmd = "joinRequests"; id = $tid }
    $shown = $(if ($reqs.ok) { ConvertTo-Json $reqs.value -Compress -Depth 5 } else { "" })
    Check ($reqs.ok -and @($reqs.value).Count -eq 1 -and $reqs.value[0].label -ceq "Stranger" -and $reqs.value[0].agent -ceq "Chrome on Android") ("THE TRUSTED PHONE SEES THE REQUEST: who, browser, time (" + $shown + ")")
    Check ($sp.ok -and -not $shown.Contains($sp.value.fingerprint) -and -not $shown.Contains($sp.value.fingerprint.Replace("-", ""))) "and no number: it is read on the new phone only"
    $headM = Get-Head ("work/" + $machine)
    $wrong = $(if ($sp.value.fingerprint -ceq "0000-0000-0000") { "1111-1111-1111" } else { "0000-0000-0000" })
    $wa = Invoke-App "T" @{ cmd = "approveJoin"; id = $tid; request = $sj.value.request; number = $wrong }
    Check (-not $wa.ok -and $wa.reason.Contains("does not match") -and (Get-Head ("work/" + $machine)) -eq $headM) "A WRONG NUMBER IS REFUSED ON THE TRUSTED PHONE ITSELF: nothing is signed, nothing is sent"
    $rj = Invoke-App "T" @{ cmd = "rejectJoin"; id = $tid; request = $sj.value.request }
    $run = Invoke-Run -Turns 2
    $sdev = Get-DeviceOf "Stranger"
    Check ($rj.ok -and $null -ne $sdev -and $sdev.state -ceq "revoked") ("its signed reject reaches the machine: the stranger's passkey is revoked, never trusted (" + $(if ($null -ne $sdev) { $sdev.state } else { "none" }) + ")")
    Check (@(Get-NoticeTexts | Where-Object { $_.Contains("'Stranger'") -and $_.Contains("rejected") }).Count -eq 1 -and @(Get-NoticeTexts | Where-Object { $_.Contains("A new phone asks to join this PC: 'Stranger'") }).Count -eq 1) "every trusted device is told: the request, and that it was rejected"
    $sc = Invoke-App "S" @{ cmd = "pairConfirmed"; id = $sp.value.id }
    Check ($sc.ok -and -not $sc.value.confirmed) "the stranger's phone is never told it is confirmed"

    Write-Host ""
    Write-Host "--- 3. the founder's new phone: the number typed on the trusted phone ---" -ForegroundColor Cyan
    $nj = Invoke-App "N" @{ cmd = "join"; horde = "work"; machine = $machine; label = "Pixel 9"; agent = "Safari on iPhone" }
    $run = Invoke-Run -Turns 2
    $no = Invoke-App "N" @{ cmd = "joinOffer"; request = $(if ($nj.ok) { $nj.value.request } else { "" }) }
    Check ($nj.ok -and $no.ok -and $no.value.offerText -cne "") "THE SLOT IS FREE AT ONCE after the reject: the new phone's request is answered"
    $np = Invoke-App "N" @{ cmd = "pair"; offer = $no.value.offerText; label = "Pixel 9"; joined = $true }
    $run = Invoke-Run -Turns 2
    $null = Invoke-App "T" @{ cmd = "refresh"; id = $tid }
    $ok = Invoke-App "T" @{ cmd = "approveJoin"; id = $tid; request = $nj.value.request; number = $np.value.fingerprint }
    $before = Get-DeviceOf "Pixel 9"
    Check ($ok.ok -and $null -ne $before -and $before.state -ceq "pending") ("the trusted phone computes the same number from the transcript and signs its approval; until the machine takes it the passkey is pending (" + $(if ($ok.ok) { "sent" } else { $ok.reason }) + ")")
    $run = Invoke-Run -Turns 2
    $ndev = Get-DeviceOf "Pixel 9"
    Check ($null -ne $ndev -and $ndev.state -ceq "trusted") ("THE MACHINE TRUSTS IT: the approval's transcript hash is the one it sent (" + $(if ($null -ne $ndev) { $ndev.state } else { "none" }) + ")")
    Check (@(Get-NoticeTexts | Where-Object { $_.Contains("'Pixel 9'") -and $_.Contains("approved") }).Count -eq 1) "every trusted device is told it was approved"
    $nc = Invoke-App "N" @{ cmd = "pairConfirmed"; id = $np.value.id }
    Check ($nc.ok -and $nc.value.confirmed) "the new phone is told it is confirmed: its pairing screen offers Finish pairing"
    $na = Invoke-App "N" @{ cmd = "announce"; id = $np.value.id }
    $run = Invoke-Run -Turns 2
    $nv = Invoke-App "N" @{ cmd = "refresh"; id = $np.value.id }
    Check ($na.ok -and $run.out.Contains("is now in the trust store") -and $nv.ok -and @($nv.value.questions | Where-Object { $_.title -ceq $title }).Count -eq 1) "its one-prompt announcement is taken, and the open question reaches it"
    }
} finally {
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    foreach ($a in @($apps.Values)) { try { $a.p.StandardInput.WriteLine('{"cmd":"exit"}'); if (-not $a.p.WaitForExit(20000)) { $a.p.Kill() } } catch { }; $a.p.Dispose() }
    $env:HORDE_HOME = $realHome
    foreach ($k in @($keysMade)) { try { [void](Remove-HordeRelayKey -Name $k.n -Scope $k.s) } catch { } }
    $left = @($keysMade | Where-Object { (Find-HordeRelayCngKey -Name $_.n -Scope $_.s) -cne "" })
    Check (@($keysMade).Count -eq 2 -and $left.Count -eq 0) "both keys of the suite's identity are gone"
    if ((Split-Path -Leaf $work) -match '^horde-pwa-join-[0-9a-f]{32}$' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    Check (-not (Test-Path -LiteralPath $work)) "the suite's folder is gone"
}

if (-not $canDecide) { Complete-HordeSuite -Success "skipped under this runtime: the decisions list cannot add a question (issue #173)" -PassCode 3 }
Complete-HordeSuite -Success "a new phone asks, is answered, and is trusted only when the number it shows is typed on a trusted phone, which compares it itself; a stranger's request is seen, refused and rejected, and trusts nothing"
