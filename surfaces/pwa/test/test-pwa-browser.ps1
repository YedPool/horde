# DOES THE PHONE APP WORK IN A REAL BROWSER - CHROME'S OWN PASSKEYS, STORAGE, WORKER AND POLICY - AND
# DOES ITS ANSWER, SIGNED BY CHROME'S WEBAUTHN, LAND ONCE THROUGH THE REAL horde relay run?
#
# The phone app in headless Chrome (relay design 2026-10-09, PR plan item 7), driven over Chrome's
# debugging protocol by surfaces/pwa/test/browser-drive.mjs with nothing installed. Chrome is the
# browser; its virtual authenticator (ctap2, internal, user verification, PRF) is the passkey; the site
# is the one New-HordePwaSite builds, served on http://localhost; the relay is the local test transport
# carried to relays/local's folders; the machine is the shipped horde.ps1. At phone size (412 by 915
# CSS pixels, a common Android width), with touch.
#   1. the app loads under its strict policy with no error; it pairs with a Chrome passkey that the
#      machine enrolls, the two fingerprints agree, and the passkey is confirmed;
#   2. it announces its key; a run sends the snapshot; the question is drawn by the window's own
#      document (list.js);
#   3. Shift+Enter and the row's New line add lines and send nothing; the answer typed and sent with a
#      real Enter lands once, his words exactly, signed by Chrome's WebAuthn;
#   4. at phone width nothing scrolls sideways and the answering row stands on the screen;
#   5. IndexedDB holds wraps and ids, nothing opened; the private key is never extractable;
#   6. a reload is controlled by the worker and locked; the passkey's PRF unlocks it; with the site's
#      server down the shell still starts from the worker's cache, which holds the shell and nothing else;
#   7. the recovery code unlocks to read, and the answer typed then is refused and nothing is sent;
#   8. a second answer sent from the row's Send key by touch lands too.
#
# NEEDS Chrome installed and Node. Without either the suite says so and exits 3, a partial run, never 0.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\ModuleSettings.ps1")
. (Join-Path $root "channels\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
foreach ($f in @(Get-HordeRelayChannelFiles)) { . $f }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "surfaces\pwa\Site.ps1")
Set-StrictMode -Version Latest

$node = Get-Command -Name "node" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$chrome = @(
    (Join-Path ${env:ProgramFiles} "Google\Chrome\Application\chrome.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe"),
    (Join-Path ${env:LOCALAPPDATA} "Google\Chrome\Application\chrome.exe")
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
if ($null -eq $node -or $null -eq $chrome) {
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
$work = Join-Path $env:TEMP ("horde-pwa-browser-" + [guid]::NewGuid().ToString("N"))
$hh = Join-Path $work "home"
$mailboxes = Join-Path $work "relay"
$site = Join-Path $work "site"
$profile = Join-Path $work "chrome"
New-Item -ItemType Directory -Path (Join-Path $hh "settings"), $mailboxes, $profile -Force | Out-Null
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
    param([int]$Turns = 2)
    return (Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "run", "-Relay", "local", "-RelayRoot", $mailboxes, "-MaxTurns", "" + $Turns) -Env @{ HORDE_HOME = $hh })
}
function Get-Said { if (-not (Test-Path -LiteralPath $store)) { return @() }; return @(Get-ChildItem -LiteralPath $store -Filter "*.json" | Sort-Object Name | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName, $utf8) | ConvertFrom-Json } | Where-Object { $_.kind -ceq "message-said" -and $_.data.route -ceq "phone" }) }
function Save-Shot {
    # A picture of the phone's screen, for a person: kept when HORDE_PWA_SHOTS names a folder.
    param([string]$Name)
    $path = Join-Path $work ($Name + ".png")
    $r = Invoke-Browser @{ cmd = "screenshot"; path = $path }
    if ($env:HORDE_PWA_SHOTS -and (Test-Path -LiteralPath $env:HORDE_PWA_SHOTS -PathType Container) -and (Test-Path -LiteralPath $path)) { Copy-Item -LiteralPath $path -Destination (Join-Path $env:HORDE_PWA_SHOTS ($Name + ".png")) -Force }
    return [pscustomobject]@{ r = $r; path = $path }
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
    $title = "Should the closing sound play when the assistant closes?"
    $q = Invoke-HordeDecision -Operation "add" -Root $store -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = @{ title = $title; kind = "yes-no"; whatItIs = "The app has no closing sound today."; group = "voice"; askedBy = "orc-b" } }
    $canDecide = ($q.state -ceq "known" -and $q.value.outcome -ceq "done")
    if (-not $canDecide) { Write-Host "  [SKIP] the decisions list cannot add a question under this runtime (issue #173): the scenario is not run" -ForegroundColor Yellow }
    if ($canDecide -and $built.state -ceq "known") {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $node.Source
    $psi.Arguments = '"' + (Join-Path $here "browser-drive.mjs") + '" "' + $site + '" "' + $mailboxes + '" "' + $chrome + '" "' + $profile + '"'
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
    Write-Host "--- 1. the app loads under its policy, and pairs with Chrome's passkey ---" -ForegroundColor Cyan
    $open = Invoke-Browser @{ cmd = "open" }
    Check ($open.ok -and $open.value.empty) "the app starts, shows that it holds no horde yet"
    $offer = New-HordeRelayPairingOffer -HordeHome $hh -RpId "localhost" -Origins @($origin)
    $paired = Invoke-Browser @{ cmd = "pair"; offer = $offer.value.text; label = "Founder phone" }
    Check ($paired.ok -and $paired.value.paired -and $paired.value.fingerprint -cmatch '\A[0-9]{4}-[0-9]{4}-[0-9]{4}\z') ("Chrome makes the passkey and the app shows a fingerprint (" + $(if ($paired.ok) { $paired.value.fingerprint + $paired.value.notice } else { $paired.reason }) + ")")
    $done = Complete-HordeRelayPairing -HordeHome $hh -Response $(if ($paired.ok) { $paired.value.response } else { "" })
    Check ($done.ok -and $done.value.fingerprint -ceq $paired.value.fingerprint) ("the machine enrolls Chrome's passkey and computes the same fingerprint (" + $(if ($done.ok) { $done.value.fingerprint } else { $done.reason }) + ")")
    Check ($done.ok -and $done.value.device.prf -eq $true) "and records that the passkey has PRF"
    $confirmed = Confirm-HordeRelayDevice -HordeHome $hh -Id $(if ($done.ok) { $done.value.device.id } else { "none" }) -Fingerprint $(if ($paired.ok) { $paired.value.fingerprint } else { "" })
    Check ($confirmed.ok -and $confirmed.value.device.state -ceq "trusted") "the founder confirms it at the machine"

    Write-Host ""
    Write-Host "--- 2. the key is announced, and the window's document draws the question ---" -ForegroundColor Cyan
    $ann = Invoke-Browser @{ cmd = "announce" }
    Check ($ann.ok -and $ann.value.enabledAfterTick -and $ann.value.doc -and $ann.value.recoveryCleared) ("the announce key opens only once the code is written down; after it the list shows and the code leaves the screen (" + $(if ($ann.ok) { $ann.value.notice } else { $ann.reason }) + ")")
    $run = Invoke-Run -Turns 2
    Check ($run.code -eq 0 -and $run.out.Contains("is now in the trust store") -and $run.out.Contains("snapshot of 1 open question(s)")) ("a run takes the app's key and sends the snapshot (exit " + $run.code + ")")
    $seen = Invoke-Browser @{ cmd = "waitText"; text = $title }
    Check ($seen.ok -and $seen.value.found) "the question appears in the app, drawn by list.js, without a reload"
    $shot1 = Save-Shot "phone-list"

    Write-Host ""
    Write-Host "--- 3. new lines stay in the field; Enter sends, signed by Chrome ---" -ForegroundColor Cyan
    $nl = Invoke-Browser @{ cmd = "newline"; mailbox = $mailbox }
    Check ($nl.ok -and $nl.value.value -ceq "first`nsecond`nthird" -and -not $nl.value.sent) ("Shift+Enter and the row's New line each add a line and send nothing (" + $(if ($nl.ok) { ($nl.value.value -replace "`n", "|") } else { $nl.reason }) + ")")
    $words = "Yes, a short chime " + [char]0x05DB + [char]0x05DF
    $sent = Invoke-Browser @{ cmd = "answer"; text = $words; via = "enter"; mailbox = $mailbox }
    Check ($sent.ok -and $sent.value.put) ("a real Enter in the field sends the answer: the signed envelope is in the machine's mailbox (" + $(if ($sent.ok) { $sent.value.head } else { $sent.reason }) + ")")
    $run = Invoke-Run -Turns 1
    $run = Invoke-Run -Turns 1
    $said = @(Get-Said)
    Check ($run.code -eq 0 -and $said.Count -eq 1 -and $said[0].data.text -ceq $words -and $said[0].data.speaker -ceq "founder") ("the machine verifies Chrome's WebAuthn assertion and stores his words once, exactly (" + $said.Count + " record(s))")
    $creds = Invoke-Browser @{ cmd = "credentials" }
    Check ($creds.ok -and @($creds.value).Count -eq 1 -and $creds.value[0].rpId -ceq "localhost") "Chrome holds one passkey, for the relying party the offer named"

    Write-Host ""
    Write-Host "--- 4. at phone width ---" -ForegroundColor Cyan
    Check ($shot1.r.ok -and $shot1.r.value.scrollWidth -le $shot1.r.value.innerWidth -and $shot1.r.value.innerWidth -eq 412) ("nothing scrolls sideways at 412 CSS pixels (" + $(if ($shot1.r.ok) { "" + $shot1.r.value.scrollWidth + " of " + $shot1.r.value.innerWidth } else { $shot1.r.reason }) + ")")
    Check ($shot1.r.ok -and [math]::Abs($shot1.r.value.keysBottom - $shot1.r.value.innerHeight) -le 1) "the answering row stands at the foot of the screen"
    Check ((Test-Path -LiteralPath $shot1.path) -and (Get-Item -LiteralPath $shot1.path).Length -gt 1000) "a picture of the phone's screen is taken"

    Write-Host ""
    Write-Host "--- 5. what Chrome keeps ---" -ForegroundColor Cyan
    $dump = Invoke-Browser @{ cmd = "dump" }
    $leaks = @("closing sound", "short chime", "whatItIs", "decisions-snapshot") | Where-Object { $dump.ok -and $dump.value.Contains($_) }
    Check ($dump.ok -and @($leaks).Count -eq 0 -and $dump.value.Contains('"kind":"prf"') -and $dump.value.Contains('"kind":"recovery"')) ("IndexedDB holds the prf and recovery wraps and no question, answer or snapshot (" + (@($leaks) -join ", ") + ")")

    Write-Host ""
    Write-Host "--- 6. reload, unlock by PRF, and start with the site's server down ---" -ForegroundColor Cyan
    $re = Invoke-Browser @{ cmd = "reload" }
    Check ($re.ok -and $re.value.locked -and $re.value.controlled) "after a reload the page is the worker's, and the horde is locked"
    $un = Invoke-Browser @{ cmd = "unlock" }
    Check ($un.ok -and $un.value.doc) ("Chrome's passkey, by PRF, unlocks it (" + $(if ($un.ok) { $un.value.notice } else { $un.reason }) + ")")
    $again = Invoke-Browser @{ cmd = "waitText"; text = $title }
    Check ($again.ok -and $again.value.found -and $again.value.text.Contains("short chime")) ("and the question shows again, his answer under it (" + $(if ($again.ok) { ($again.value.text -replace '\s+', ' ') } else { $again.reason }) + ")")
    $null = Invoke-Browser @{ cmd = "serve"; on = $false }
    $off = Invoke-Browser @{ cmd = "reload" }
    Check ($off.ok -and $off.value.locked) "with the site's server down the app still starts, from the worker's cache"
    $null = Invoke-Browser @{ cmd = "serve"; on = $true }
    $cached = Invoke-Browser @{ cmd = "caches" }
    $paths = @(); if ($cached.ok) { foreach ($pr in $cached.value.PSObject.Properties) { $paths += @($pr.Value) } }
    $shellPaths = @($built.value.shell | ForEach-Object { "/" + $_ })
    $extra = @($paths | Where-Object { $shellPaths -cnotcontains $_ })
    Check ($cached.ok -and $paths.Count -ge 10 -and $extra.Count -eq 0) ("the worker's cache holds the shell and nothing else (" + $paths.Count + " files; not shell: " + ($extra -join ", ") + ")")

    Write-Host ""
    Write-Host "--- 7. the recovery code reads, and never answers ---" -ForegroundColor Cyan
    $null = Invoke-Browser @{ cmd = "unlock" }
    $null = Invoke-Browser @{ cmd = "lock" }
    $rc = Invoke-Browser @{ cmd = "recover"; code = $(if ($paired.ok) { $paired.value.recoveryCode } else { "" }) }
    Check ($rc.ok -and $rc.value.doc -and $rc.value.mode.Contains("Read only")) ("the recovery code unlocks the horde, said to be read only (" + $(if ($rc.ok) { $rc.value.notice } else { $rc.reason }) + ")")
    $ro = Invoke-Browser @{ cmd = "answer"; text = "Not from a recovery code."; via = "enter"; mailbox = $mailbox }
    Check ($ro.ok -and -not $ro.value.put) "an answer typed then is not sent: nothing reaches the machine's mailbox"
    $null = Invoke-Browser @{ cmd = "lock" }
    $null = Invoke-Browser @{ cmd = "unlock" }

    Write-Host ""
    Write-Host "--- 8. the row's Send key, by touch ---" -ForegroundColor Cyan
    $q2 = Invoke-HordeDecision -Operation "add" -Root $store -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = @{ title = "Which chime of the three?"; kind = "yes-no"; whatItIs = "Three chimes were tried."; group = "voice"; askedBy = "orc-b" } }
    Check ($q2.state -ceq "known" -and $q2.value.outcome -ceq "done") "CONTROL: a second question is asked"
    $run = Invoke-Run -Turns 1
    $seen2 = Invoke-Browser @{ cmd = "waitText"; text = "Which chime of the three?" }
    $null = Save-Shot "phone-two-questions"
    $touch = Invoke-Browser @{ cmd = "answer"; text = "The second one."; via = "touch"; mailbox = $mailbox; question = "Which chime of the three?" }
    $run = Invoke-Run -Turns 1
    $said = @(Get-Said)
    Check ($seen2.ok -and $seen2.value.found -and $touch.ok -and $touch.value.put -and $said.Count -eq 2 -and @($said | Where-Object { $_.data.text -ceq "The second one." }).Count -eq 1) ("a touch on Send sends the answer in the field with the caret, and it lands (" + $said.Count + " records; seen " + $(if ($seen2.ok) { $seen2.value.found } else { $seen2.reason }) + "; touch " + $(if ($touch.ok) { ConvertTo-Json $touch.value -Compress } else { $touch.reason }) + ")")
    $probs = Invoke-Browser @{ cmd = "problems" }
    Check ($probs.ok -and @($probs.value).Count -eq 0) ("no exception, no console error and no policy violation in the whole run (" + $(if ($probs.ok) { @($probs.value) -join " | " } else { $probs.reason }) + ")")
    }
} finally {
    if ($null -ne $drv) { try { $drv.p.StandardInput.WriteLine('{"cmd":"exit"}'); if (-not $drv.p.WaitForExit(20000)) { $drv.p.Kill() } } catch { } ; $drv.p.Dispose() }
    $env:HORDE_HOME = $realHome
    foreach ($k in @($keysMade)) { try { [void](Remove-HordeRelayKey -Name $k.n -Scope $k.s) } catch { } }
    $left = @($keysMade | Where-Object { (Find-HordeRelayCngKey -Name $_.n -Scope $_.s) -cne "" })
    Check (@($keysMade).Count -eq 2 -and $left.Count -eq 0) "both keys of the suite's identity are gone"
    for ($i = 0; $i -lt 20 -and (Test-Path -LiteralPath $work); $i++) {
        if ((Split-Path -Leaf $work) -match '^horde-pwa-browser-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $work) { Start-Sleep -Milliseconds 250 }
    }
    Check (-not (Test-Path -LiteralPath $work)) "the suite's folder - the site, the relay and Chrome's profile with its passkey - is gone"
}

if (-not $canDecide) { Complete-HordeSuite -Success "skipped under this runtime: the decisions list cannot add a question (issue #173)" -PassCode 3 }
Complete-HordeSuite -Success "in headless Chrome at phone size the app pairs with Chrome's passkey, draws the question with the window's document, sends answers by Enter and by touch that land once, unlocks by PRF, starts offline from its worker, keeps nothing opened, and reads but never answers by its recovery code"
