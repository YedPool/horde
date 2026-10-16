# DOES THE PHONE ANNOUNCE ITSELF WITH NO ANNOUNCE BUTTON - ON THE UNLOCK IT SHOWS ANYWAY, ONE PROMPT - AND
# DOES THE MACHINE STILL REFUSE AN ANNOUNCEMENT IT SHOULD NOT TAKE?
#
# The founder, 2026-10-14: "that piece should happen automatically on login - I don't see why I should
# press a button". The phone app in headless Chrome (browser-drive.mjs: Chrome's own WebAuthn by its
# virtual authenticator, its IndexedDB and worker), a real `horde relay run` over the local relay's
# folders, the shipped horde.ps1. test-pwa-browser.ps1 has the pairing screen's Finish pairing; this
# suite has the other path (phone-core.js, THE ANNOUNCEMENT IS NO BUTTON):
#   1. the phone pairs and the founder LEAVES the pairing screen before typing the number at the machine;
#      nowhere on any screen is there a button that offers to announce;
#   2. NOT YET CONFIRMED: the next unlock is ONE passkey prompt, and it puts the vouch; the run refuses it,
#      and the trust store is as it was - an announcement before confirmation changes nothing; the phone
#      does not try again by itself (no prompt, no put, for seconds after);
#   3. MUST-REFUSE TWINS, once the passkey IS trusted: a vouch item with no signature, and one signed by
#      another key in the name of the trusted passkey (what a relay could forge), are each refused and
#      change nothing;
#   4. CONFIRMED: the next unlock - one prompt again - announces it; the run takes the key in and sends
#      the snapshot, and the question is drawn;
#   5. HEARD: an unlock once the machine has answered puts nothing, still one prompt.
#
# NEEDS Chrome installed and Node. Without either the suite says so and exits 3, a partial run, never 0.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Browser.ps1")
# No channel may find this machine's real Thrall (test/lib/FleetPin.ps1): first thing, before any loads.
. (Join-Path $root "test\lib\FleetPin.ps1")
$fleetPin = Enter-HordeTestEmptyFleet
. (Join-Path $root "core\ModuleSettings.ps1")
. (Join-Path $root "channels\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
foreach ($f in @(Get-HordeRelayChannelFiles)) { . $f }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "test\lib\RelayPhone.ps1")
. (Join-Path $root "surfaces\pwa\Site.ps1")
Set-StrictMode -Version Latest

$node = Get-Command -Name "node" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$chrome = Find-HordeTestChrome
if ($null -eq $node -or $chrome -eq "") {
    Write-Host ("  [SKIP] " + $(if ($null -eq $node) { "node" } else { "Chrome" }) + " is not installed here, so the app is not run in a browser") -ForegroundColor Yellow
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "skipped: no node or no Chrome" -PassCode 3
}
if ((Get-HordeRelayKeyStore).state -cne "known") {
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "skipped: no key store here, so no machine identity" -PassCode 3
}

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$realHome = $env:HORDE_HOME
$work = Join-Path $env:TEMP ("horde-pwa-announce-" + [guid]::NewGuid().ToString("N"))
$hh = Join-Path $work "home"
$mailboxes = Join-Path $work "relay"
$site = Join-Path $work "site"
New-Item -ItemType Directory -Path (Join-Path $hh "settings"), $mailboxes -Force | Out-Null
$browser = $null
$keysMade = @()
$drv = $null
$canDecide = $false

function ConvertTo-AsciiJson {
    param($Value)
    $t = ConvertTo-Json -InputObject $Value -Compress -Depth 8
    return ([regex]::Replace($t, '[^\x20-\x7E]', { param($m) '\u' + ([int][char]$m.Value).ToString("x4") }))
}
function Read-Driver {
    $read = $script:drv.p.StandardOutput.ReadLineAsync()
    if (-not $read.Wait(90000)) { throw "the browser driver did not answer in 90 s" }
    if ($null -eq $read.Result) { throw ("the browser driver ended: " + $script:drv.err.Result) }
    return ($read.Result | ConvertFrom-Json)
}
function Invoke-Browser {
    param([hashtable]$Command)
    $script:drv.p.StandardInput.WriteLine((ConvertTo-AsciiJson $Command))
    $script:drv.p.StandardInput.Flush()
    return (Read-Driver)
}
function Invoke-Run {
    param([int]$Turns = 1)
    return (Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "run", "-Relay", "local", "-RelayRoot", $mailboxes, "-MaxTurns", "" + $Turns) -Env @{ HORDE_HOME = $hh })
}
# The trust store's phone keys and the device's state: what an announcement can change.
function Get-TrustShape {
    $t = Get-HordeRelayTrust -HordeHome $hh
    if ($t.state -cne "known") { return "unreadable: " + $t.reason }
    return ((@($t.value.devices | ForEach-Object { "device " + $_.id + " " + $_.state }) + @($t.value.phones | ForEach-Object { "phone " + $_.agreeKeyId + " " + $_.state + " by " + $_.by })) -join "; ")
}
function Get-Head { param([string]$Mailbox) $r = Invoke-Browser @{ cmd = "head"; mailbox = $Mailbox }; if ($r.ok) { return [long]$r.value }; return -1 }
function Get-KeysAfter {
    # The keys of the items in a mailbox after seq -After, read from the local relay's own files (relays/local:
    # each item is its key, a line feed, its text): what was put, not just how many.
    param([string]$Mailbox, [long]$After)
    $box = Join-Path $mailboxes ($Mailbox -replace '/', '\')
    return @(Get-ChildItem -LiteralPath $box -Filter "*.item" | Where-Object { [long]$_.Name.Substring(0, 16) -gt $After } | Sort-Object Name | ForEach-Object { $t = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::ASCII); $t.Substring(0, $t.IndexOf([char]10)) })
}
function Send-Item {
    param([string]$Mailbox, [string]$Text, [string]$Key)
    $c = Connect-HordeRelay -Name "local" -Options @{ root = $mailboxes }
    if ($c.state -cne "known") { return $c }
    return (Send-HordeRelayItem -Connection $c.value -Mailbox $Mailbox -Text $Text -Key $Key)
}

try {
    $env:HORDE_HOME = $hh
    $built = New-HordePwaSite -Out $site -Transport "binding"
    Check ($built.state -ceq "known") "CONTROL: the site is built as it ships, with the local test transport"
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay.json"), '{"schemaVersion": 1, "settings": {"horde": "work"}}', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay-run.json"), '{"schemaVersion": 1, "settings": {"watchMs": 200}}', $utf8)
    $id = New-HordeRelayMachineIdentity -HordeHome $hh -Provider "software"
    Check ($id.state -ceq "known") "CONTROL: the machine has its relay identity"
    $keysMade = @(@{ n = $id.value.sign.name; s = $id.value.scope }, @{ n = $id.value.agree.name; s = $id.value.scope })
    $store = Join-Path $hh "store\decisions"
    $title = "Should the phone announce itself on unlock?"
    $q = Invoke-HordeDecision -Operation "add" -Root $store -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = @{ title = $title; kind = "yes-no"; whatItIs = "The founder asked for no announce button."; group = "relay"; askedBy = "orc-f" } }
    $canDecide = ($q.state -ceq "known" -and $q.value.outcome -ceq "done")
    if (-not $canDecide) { Write-Host "  [SKIP] the decisions list cannot add a question under this runtime (issue #173): the scenario is not run" -ForegroundColor Yellow }
    if ($canDecide -and $built.state -ceq "known") {
    $browser = Start-HordeTestBrowser -Chrome $chrome -Parent $work -ExtraArgs @("--host-resolver-rules=MAP localhost 127.0.0.1", "--window-size=412,915")
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $node.Source
    $psi.Arguments = '"' + (Join-Path $here "browser-drive.mjs") + '" "' + $site + '" "' + $mailboxes + '" ' + $browser.port
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $drv = [pscustomobject]@{ p = $p; err = $p.StandardError.ReadToEndAsync() }
    $ready = Read-Driver
    Check ($ready.ok -and $ready.value.origin -cmatch '\Ahttp://localhost:[0-9]+\z') ("CONTROL: headless Chrome is up and the site is served at " + $(if ($ready.ok) { $ready.value.origin } else { $ready.reason }))
    $origin = $ready.value.origin
    $mailbox = $id.value.mailbox

    Write-Host ""
    Write-Host "--- 1. the phone pairs, and he leaves the pairing screen before confirming at the machine ---" -ForegroundColor Cyan
    $open = Invoke-Browser @{ cmd = "open" }
    Check ($open.ok -and $open.value.empty) "the app starts, holding no horde yet"
    $offer = New-HordeRelayPairingOffer -HordeHome $hh -RpId "localhost" -Origins @($origin)
    $paired = Invoke-Browser @{ cmd = "pair"; offer = $offer.value.text; label = "Founder phone" }
    Check ($paired.ok -and $paired.value.paired) ("Chrome makes the passkey and the app shows its number (" + $(if ($paired.ok) { $paired.value.fingerprint } else { $paired.reason }) + ")")
    $done = Complete-HordeRelayPairing -HordeHome $hh -Response $(if ($paired.ok) { $paired.value.response } else { "" })
    Check ($done.ok -and $done.value.device.state -ceq "pending") "the machine enrolls the passkey, PENDING"
    $st = Invoke-Browser @{ cmd = "finishState" }
    Check ($st.ok -and -not $st.value.finishShown -and $st.value.waiting -and @($st.value.announceButtons).Count -eq 0) ("the pairing screen waits for the machine, offers no Finish pairing yet, and no button offers to announce (" + $(if ($st.ok) { ConvertTo-Json $st.value -Compress } else { $st.reason }) + ")")
    $later = Invoke-Browser @{ cmd = "pairLater" }
    Check ($later.ok -and -not $later.value.paired) "Later leaves the pairing screen"
    $lk = Invoke-Browser @{ cmd = "lock" }
    $st2 = Invoke-Browser @{ cmd = "finishState" }
    Check ($lk.ok -and $lk.value.locked -and $st2.ok -and @($st2.value.announceButtons).Count -eq 0) ("locked, the screen offers to unlock and no button offers to announce (" + $(if ($st2.ok) { @($st2.value.announceButtons) -join ", " } else { $st2.reason }) + ")")

    Write-Host ""
    Write-Host "--- 2. not yet confirmed: the unlock announces, the machine refuses, nothing changes, nothing loops ---" -ForegroundColor Cyan
    $shape0 = Get-TrustShape
    $head0 = Get-Head $mailbox
    $null = Invoke-Browser @{ cmd = "countPrompts" }
    $un = Invoke-Browser @{ cmd = "unlock" }
    $pr = Invoke-Browser @{ cmd = "prompts" }
    $head1 = Get-Head $mailbox
    Check ($un.ok -and $un.value.doc -and $pr.ok -and $pr.value -eq 1) ("the unlock is ONE passkey prompt (" + $(if ($pr.ok) { "" + $pr.value + " prompt(s)" } else { $pr.reason }) + "; " + $(if ($un.ok) { $un.value.notice } else { $un.reason }) + ")")
    Check ($head1 -eq $head0 + 1) ("and that same prompt put the phone's vouch into the machine's mailbox (head " + $head0 + " -> " + $head1 + ")")
    $run = Invoke-Run -Turns 1
    Check ($run.code -eq 0 -and $run.out.Contains("refused item") -and $run.out.Contains("is not a trusted device of the founder")) ("THE MACHINE REFUSES IT: the passkey is not confirmed yet (exit " + $run.code + ")")
    $shape1 = Get-TrustShape
    Check ($shape1 -ceq $shape0 -and $shape1.Contains("pending") -and -not $shape1.Contains("phone ")) ("an announcement before confirmation changes nothing: the trust store is as it was (" + $shape1 + ")")
    Start-Sleep -Seconds 6
    $pr2 = Invoke-Browser @{ cmd = "prompts" }
    $head2 = Get-Head $mailbox
    Check ($pr2.ok -and $pr2.value -eq 1 -and $head2 -eq $head1) ("NO LOOP: six seconds on, no other prompt and no other put (" + $(if ($pr2.ok) { $pr2.value } else { $pr2.reason }) + " prompt(s), head " + $head2 + ")")

    Write-Host ""
    Write-Host "--- 3. must-refuse twins: an unsigned vouch, and one signed by another key in the passkey's name ---" -ForegroundColor Cyan
    $conf = Confirm-HordeRelayDevice -HordeHome $hh -Id $(if ($done.ok) { $done.value.device.id } else { "none" }) -Fingerprint $(if ($paired.ok) { $paired.value.fingerprint } else { "" })
    Check ($conf.ok -and $conf.value.device.state -ceq "trusted") "the founder confirms the passkey at the machine"
    $dev = $conf.value.device
    $stranger = New-HordeTestPhone
    $strangerKey = ConvertTo-HordeRelayBase64Url -Bytes $stranger.agreePublic
    $unsigned = '{"v":1,"kind":"horde-relay-phone-vouch","horde":"work","by":"' + $dev.keyId + '","agreePublic":"' + $strangerKey + '","authenticatorData":"","clientDataJSON":"","signature":""}'
    $forged = New-HordeTestPhoneVouch -Phone $stranger -Horde "work"
    $wrongKey = '{"v":1,"kind":"horde-relay-phone-vouch","horde":"work","by":"' + $dev.keyId + '","agreePublic":"' + $strangerKey + '","authenticatorData":"' + (ConvertTo-HordeRelayBase64Url -Bytes $forged.authenticatorData) +
        '","clientDataJSON":"' + (ConvertTo-HordeRelayBase64Url -Bytes $forged.clientDataJson) + '","signature":"' + (ConvertTo-HordeRelayBase64Url -Bytes $forged.signature) + '"}'
    $s1 = Send-Item -Mailbox $mailbox -Text $unsigned -Key ("vouch/" + $dev.keyId + "/unsigned")
    $s2 = Send-Item -Mailbox $mailbox -Text $wrongKey -Key ("vouch/" + $dev.keyId + "/forged")
    Check ($s1.state -ceq "known" -and $s2.state -ceq "known") "CONTROL: both forgeries are in the machine's mailbox, as a relay could put them"
    $shapeT = Get-TrustShape
    $run = Invoke-Run -Turns 1
    Check ($run.code -eq 0 -and $run.out.Contains("carries no signature")) ("an UNSIGNED vouch is refused, by name (exit " + $run.code + ")")
    Check ($run.out.Contains("the vouch for the phone key is refused")) "a vouch signed by ANOTHER key in the trusted passkey's name is refused"
    $shapeU = Get-TrustShape
    Check ($shapeU -ceq $shapeT -and -not $shapeU.Contains("phone ")) ("and neither changed the trust store: no phone key is trusted (" + $shapeU + ")")

    Write-Host ""
    Write-Host "--- 4. confirmed: the next unlock announces it, one prompt, and the question comes ---" -ForegroundColor Cyan
    $null = Invoke-Browser @{ cmd = "lock" }
    $null = Invoke-Browser @{ cmd = "countPrompts" }
    $headA = Get-Head $mailbox
    $un2 = Invoke-Browser @{ cmd = "unlock" }
    $pr3 = Invoke-Browser @{ cmd = "prompts" }
    $headB = Get-Head $mailbox
    Check ($un2.ok -and $un2.value.doc -and $pr3.ok -and $pr3.value -eq 1 -and $headB -eq $headA + 1) ("the next unlock is again one prompt, and it puts the vouch again (" + $(if ($pr3.ok) { $pr3.value } else { $pr3.reason }) + " prompt(s), head " + $headA + " -> " + $headB + ")")
    $keysAB = @(Get-KeysAfter -Mailbox $mailbox -After $headA)
    Check (@($keysAB | Where-Object { $_.StartsWith("vouch/") }).Count -eq 1) ("CONTROL: the mailbox's keys show that vouch, so section 5's reading of them can see one (" + ($keysAB -join ", ") + ")")
    $run = Invoke-Run -Turns 2
    Check ($run.code -eq 0 -and $run.out.Contains("is now in the trust store") -and $run.out.Contains("snapshot of 1 open question(s)")) ("a run takes the key in from the vouch alone and sends the snapshot (exit " + $run.code + ")")
    $shapeV = Get-TrustShape
    Check ($shapeV.Contains("phone ") -and $shapeV.Contains("trusted by " + $dev.keyId)) ("the phone key is trusted, vouched for by the confirmed passkey (" + $shapeV + ")")
    $seen = Invoke-Browser @{ cmd = "waitText"; text = $title }
    Check ($seen.ok -and $seen.value.found) "the question appears in the app"
    $box = Invoke-Browser @{ cmd = "announceBox" }
    Check ($box.ok -and -not $box.value.shown) "and the horde's view no longer says the machine has not answered"

    Write-Host ""
    Write-Host "--- 5. heard: an unlock puts nothing more ---" -ForegroundColor Cyan
    $null = Invoke-Browser @{ cmd = "lock" }
    $null = Invoke-Browser @{ cmd = "countPrompts" }
    $headC = Get-Head $mailbox
    $un3 = Invoke-Browser @{ cmd = "unlock" }
    $pr4 = Invoke-Browser @{ cmd = "prompts" }
    $headD = Get-Head $mailbox
    # No VOUCH: the unlocked session (PR 312) may put its own opening envelope once the PC says it keeps
    # sessions, so the mailbox's keys are read, not its head.
    $keysCD = @(Get-KeysAfter -Mailbox $mailbox -After $headC)
    Check ($un3.ok -and $un3.value.doc -and $pr4.ok -and $pr4.value -eq 1 -and @($keysCD | Where-Object { $_.StartsWith("vouch/") }).Count -eq 0) ("once the machine has answered, an unlock is one prompt and puts no vouch (" + $(if ($pr4.ok) { $pr4.value } else { $pr4.reason }) + " prompt(s), head " + $headC + " -> " + $headD + ", put: " + ($keysCD -join ", ") + ")")
    $probs = Invoke-Browser @{ cmd = "problems" }
    Check ($probs.ok -and @($probs.value).Count -eq 0) ("no exception, no console error and no policy violation in the whole run (" + $(if ($probs.ok) { @($probs.value) -join " | " } else { $probs.reason }) + ")")
    }
} finally {
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    if ($null -ne $drv) { try { $drv.p.StandardInput.WriteLine('{"cmd":"exit"}'); if (-not $drv.p.WaitForExit(20000)) { $drv.p.Kill() } } catch { } ; $drv.p.Dispose() }
    if ($null -ne $browser) {
        $bProfile = $browser.profile
        $bEnd = Stop-HordeTestBrowser -Browser $browser
        Check ($bEnd.left -eq 0 -and $bEnd.profileGone -and @(Get-HordeTestBrowserProcesses -ProfileDir $bProfile).Count -eq 0) ("the browser the suite started is ended, every process of it, and its profile removed (" + $bEnd.said + ")")
    }
    $env:HORDE_HOME = $realHome
    foreach ($k in @($keysMade)) { try { [void](Remove-HordeRelayKey -Name $k.n -Scope $k.s) } catch { } }
    $left = @($keysMade | Where-Object { (Find-HordeRelayCngKey -Name $_.n -Scope $_.s) -cne "" })
    Check (@($keysMade).Count -eq 2 -and $left.Count -eq 0) "both keys of the suite's identity are gone"
    for ($i = 0; $i -lt 20 -and (Test-Path -LiteralPath $work); $i++) {
        if ((Split-Path -Leaf $work) -match '^horde-pwa-announce-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $work) { Start-Sleep -Milliseconds 250 }
    }
    Check (-not (Test-Path -LiteralPath $work)) "the suite's folder - the site, the relay and Chrome's profile with its passkey - is gone"
}

if (-not $canDecide) { Complete-HordeSuite -Success "skipped under this runtime: the decisions list cannot add a question (issue #173)" -PassCode 3 }
Complete-HordeSuite -Success "in headless Chrome the phone has no announce button; its unlock announces it in one passkey prompt; the machine refuses it before confirmation and refuses unsigned and forged vouches, changing nothing; once confirmed the next unlock announces it and the question comes"
