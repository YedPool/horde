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
#   2. it announces its key - the button says why it is shut until the recovery code is written down, a
#      relay that refuses and a passkey that does not sign are each said beside it, and the horde's own
#      view offers "Announce this phone" until the machine answers (the founder's first live use,
#      2026-10-11); a run sends the snapshot; the question is drawn by the window's own document
#      (list.js);
#   3. Shift+Enter and the row's New line add lines and send nothing; the answer typed and sent with a
#      real Enter lands once, his words exactly, signed by Chrome's WebAuthn;
#   4. at phone width nothing scrolls sideways and the answering row stands on the screen;
#   5. IndexedDB holds wraps and ids, nothing opened; the private key is never extractable;
#   6. a reload is controlled by the worker and locked; the passkey's PRF unlocks it; with the site's
#      server down the shell still starts from the worker's cache, which holds the shell and nothing else;
#   7. the recovery code unlocks to read, and the answer typed then is refused and nothing is sent;
#   8. a second answer sent from the row's Send key by touch lands too;
#   9. hidden, it locks itself;
#  10. the chat tab: the Thrall's turns (a synthetic fleet, test/lib/ChatFleet.ps1) are drawn; Shift+Enter
#      and the New line key add lines and send nothing; a real Enter sends a line signed by Chrome's
#      WebAuthn, which a run posts to the Thrall once, and its receipt shows; at phone width nothing
#      scrolls sideways and the composer stands at the foot; with the page scrolled to its end the other
#      view's tab is still on the screen and a touch opens it, both ways, and the phone's Back goes back
#      between them (the founder's first live use, 2026-10-11); a lock takes the chat off the page;
#  11. the progress tab (the founder asked for it, 2026-10-12): a changelog under the suite's home is sent by
#      a run and drawn oldest to newest in the order written, each entry with its time, bold title, labelled
#      paragraphs and chips; a correction on what it corrects; what stands on the screen is read, reading
#      down moves his place, Jump to newest marks nothing, a reload opens at his place, Mark all read; the
#      tab is reached by touch from the other views, and a lock takes the log off the page.
#
# NEEDS Chrome installed and Node. Without either the suite says so and exits 3, a partial run, never 0.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
# No channel may find this machine's real Thrall (test/lib/FleetPin.ps1): first thing, before any loads.
. (Join-Path $root "test\lib\FleetPin.ps1")
$fleetPin = Enter-HordeTestEmptyFleet
. (Join-Path $root "core\ModuleSettings.ps1")
. (Join-Path $root "channels\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
foreach ($f in @(Get-HordeRelayChannelFiles)) { . $f }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "surfaces\pwa\Site.ps1")
. (Join-Path $root "test\lib\ChatFleet.ps1")
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
$thrall = $null
$fake = Join-Path $work "fleet-messenger"

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
    $built = New-HordePwaSite -Out $site -Transport "binding" -LockAfterHiddenSeconds 2
    Check ($built.state -ceq "known") "CONTROL: the site is built as it ships, with the local test transport"
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay.json"), '{"schemaVersion": 1, "settings": {"horde": "work"}}', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay-run.json"), '{"schemaVersion": 1, "settings": {"watchMs": 200}}', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay-chat.json"), '{"schemaVersion": 1, "settings": {"sendIntervalMs": 0, "startTurns": 3}}', $utf8)
    $chatFixtures = @(Get-HordeTestChatFixtureFiles | ForEach-Object { . $_ -Root $root })
    $thrall = New-HordeTestChatThrall -Fixtures $chatFixtures
    Check ($null -ne $thrall -and (New-HordeTestFleetMessenger -HordeHome $hh -Folder $fake) -cne "") "CONTROL: a synthetic Thrall and a messenger stand-in are ready for the chat"
    Add-HordeTestChatTurns -Thrall $thrall -Turns @(@{ role = "user"; text = "how is the chime going?" }, @{ role = "assistant"; text = ("three chimes recorded, " + [char]0x05E9 + [char]0x05DC + [char]0x05D5 + [char]0x05DD) })
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
    $why = Invoke-Browser @{ cmd = "announceWhy" }
    Check ($why.ok -and $why.value.before.disabled -and $why.value.before.why -and $why.value.before.words.Contains("recovery code") -and -not $why.value.after.disabled -and -not $why.value.after.why) ("while the recovery-code box is not ticked the announce button is shut and says why; ticked, it opens and the reason goes (" + $(if ($why.ok) { $why.value.before.words } else { $why.reason }) + ")")
    $null = Invoke-Browser @{ cmd = "relayFail"; on = $true }
    $f1 = Invoke-Browser @{ cmd = "announceTry" }
    $null = Invoke-Browser @{ cmd = "relayFail"; on = $false }
    Check ($f1.ok -and $f1.value.status.Contains("The relay did not take it") -and -not $f1.value.status.Contains("a stand-in") -and $f1.value.paired -and $f1.value.recovery) ("an announcement the relay refuses says so beside its button, in the app's words, and the pairing screen stays with its code (" + $(if ($f1.ok) { $f1.value.status } else { $f1.reason }) + ")")
    $null = Invoke-Browser @{ cmd = "passkeyRefusesOnce" }
    $f2 = Invoke-Browser @{ cmd = "announceTry" }
    Check ($f2.ok -and $f2.value.status.Contains("did not sign the announcement") -and $f2.value.paired) ("an announcement the passkey does not sign says so beside its button (" + $(if ($f2.ok) { $f2.value.status } else { $f2.reason }) + ")")
    $ann = Invoke-Browser @{ cmd = "announce" }
    Check ($ann.ok -and $ann.value.enabledAfterTick -and $ann.value.doc -and $ann.value.recoveryCleared) ("the announce key opens only once the code is written down; after it the list shows and the code leaves the screen (" + $(if ($ann.ok) { $ann.value.notice } else { $ann.reason }) + ")")
    $box = Invoke-Browser @{ cmd = "announceBox" }
    Check ($box.ok -and $box.value.shown -and $box.value.words.Contains("has not answered this phone yet")) ("until the machine answers, the horde's own view says so and offers Announce this phone (" + $(if ($box.ok) { $box.value.words } else { $box.reason }) + ")")
    $again = Invoke-Browser @{ cmd = "announceNow"; mailbox = $mailbox }
    Check ($again.ok -and $again.value.put -and $again.value.status.StartsWith("Announced.")) ("and its button announces the phone again, from that view (" + $(if ($again.ok) { $again.value.status } else { $again.reason }) + ")")
    $run = Invoke-Run -Turns 2
    Check ($run.code -eq 0 -and $run.out.Contains("is now in the trust store") -and $run.out.Contains("snapshot of 1 open question(s)")) ("a run takes the app's key and sends the snapshot (exit " + $run.code + ")")
    $seen = Invoke-Browser @{ cmd = "waitText"; text = $title }
    Check ($seen.ok -and $seen.value.found) "the question appears in the app, drawn by list.js, without a reload"
    $box = Invoke-Browser @{ cmd = "announceBox" }
    Check ($box.ok -and -not $box.value.shown) "and once it has, the offer to announce goes"
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
    $lk = Invoke-Browser @{ cmd = "lock" }
    Check ($lk.ok -and $lk.value.locked -and $lk.value.boxes -eq 0 -and $lk.value.fields -ceq "") ("a lock removes the horde's list and the words left in its fields, not only hides them (review of a8b732d, finding 2: " + $(if ($lk.ok) { "" + $lk.value.boxes + " box(es), fields '" + $lk.value.fields + "'" } else { $lk.reason }) + ")")
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

    Write-Host ""
    Write-Host "--- 9. hidden, it locks itself; shown again, nothing opened shows first ---" -ForegroundColor Cyan
    $hid = Invoke-Browser @{ cmd = "hide"; ms = 3500 }
    Check ($hid.ok -and $hid.value.tabs.Contains("(locked)") -and $hid.value.boxes -eq 0 -and $hid.value.fields -ceq "") ("left hidden past the lock time (2 s in this build), every horde locks while still hidden, its list removed (" + $(if ($hid.ok) { $hid.value.tabs + "; " + $hid.value.boxes + " box(es)" } else { $hid.reason }) + ")")
    $null = Invoke-Browser @{ cmd = "unlock" }
    $null = Invoke-Browser @{ cmd = "waitText"; text = $title }
    $null = Invoke-Browser @{ cmd = "hide"; ms = 200 }
    $sh = Invoke-Browser @{ cmd = "show" }
    Check ($sh.ok -and $sh.value.docHiddenAtOnce) "shown again, the list is hidden in the same moment, before the lock check runs"

    Write-Host ""
    Write-Host "--- 10. the chat tab: the Thrall's turns, and a line sent by Enter that reaches it once ---" -ForegroundColor Cyan
    $null = Invoke-Browser @{ cmd = "unlock" }
    $tab = Invoke-Browser @{ cmd = "chatTab"; which = "chat" }
    Check ($tab.ok -and $tab.value.chat -and -not $tab.value.doc -and -not $tab.value.keys) "the chat tab shows the chat, and the answering row of the questions goes"
    $w1 = Invoke-Browser @{ cmd = "chatWait"; text = "three chimes recorded" }
    Check ($w1.ok -and $w1.value.found -and $w1.value.log.Contains("how is the chime going?")) ("the Thrall's turns are drawn (" + $(if ($w1.ok) { ($w1.value.log -replace '\s+', ' ') } else { $w1.reason }) + ")")
    $cn = Invoke-Browser @{ cmd = "chatNewline"; mailbox = $mailbox }
    Check ($cn.ok -and $cn.value.value -ceq "one`ntwo`nthree" -and -not $cn.value.sent) ("Shift+Enter and the New line key each add a line and send nothing (" + $(if ($cn.ok) { ($cn.value.value -replace "`n", "|") } else { $cn.reason }) + ")")
    $cs = Invoke-Browser @{ cmd = "chatSend"; text = "Use the second chime."; via = "enter"; mailbox = $mailbox }
    Check ($cs.ok -and $cs.value.put -and $cs.value.left -ceq "") ("a real Enter sends the line, signed by Chrome's passkey, and empties the composer (" + $(if ($cs.ok) { $cs.value.notice } else { $cs.reason }) + ")")
    $run = Invoke-Run -Turns 1
    $posts = @(Get-HordeTestFleetPosts -Folder $fake)
    Check ($posts.Count -eq 1 -and $posts[0].to -ceq $thrall.state.session -and $posts[0].body.EndsWith("Use the second chime.")) ("a run posts it to the Thrall once (" + $posts.Count + ")")
    $w2 = Invoke-Browser @{ cmd = "chatWait"; text = "Sent: the Thrall's mailbox has it." }
    Check ($w2.ok -and $w2.value.found) "its receipt shows under it, in the app's own words"
    # WHEN IT WAS SAID (the founder asked for the time of every message, 2026-10-12).
    $stamps = Invoke-Browser @{ cmd = "chatStamps" }
    $stampList = @(); $dayList = @(); if ($stamps.ok) { $stampList = @($stamps.value.stamps); $dayList = @($stamps.value.days) }
    Check ($stamps.ok -and $stamps.value.items -ge 3 -and $stampList.Count -eq $stamps.value.items -and @($stampList | Where-Object { $_ -cnotmatch '\A[0-9]{2}:[0-9]{2}\z' }).Count -eq 0) ("every message in the chat - the Thrall's turns and his own line - shows when it was said, as a short local time (" + ($stampList -join ", ") + ")")
    Check ($stamps.ok -and $dayList.Count -ge 1 -and $stamps.value.first -ceq "chat-day" -and @($dayList | Where-Object { $_ -cnotmatch '\A(Sun|Mon|Tue|Wed|Thu|Fri|Sat) [0-9]{1,2} [A-Z][a-z]{2} [0-9]{4}\z' }).Count -eq 0 -and @($dayList | Select-Object -Unique).Count -eq $dayList.Count) ("the day stands on a line of its own before the first message of each day, once (" + ($dayList -join ", ") + ")")
    $exactLook = '\A(Sun|Mon|Tue|Wed|Thu|Fri|Sat) [0-9]{1,2} [A-Z][a-z]{2} [0-9]{4}, [0-9]{2}:[0-9]{2}:[0-9]{2} \(UTC[^)]*\)\z'
    Check ($stamps.ok -and $stamps.value.tapped -cmatch $exactLook -and $stamps.value.titles[0] -ceq $stamps.value.tapped -and $stamps.value.kept -ceq $stamps.value.tapped -and $stamps.value.again -ceq $stampList[0]) ("a touch on a time opens the exact one, to the second and with its zone - also its title; it stays open when the log is drawn again; a second touch closes it (" + $(if ($stamps.ok) { $stamps.value.tapped } else { $stamps.reason }) + ")")
    $shot = Invoke-Browser @{ cmd = "chatShot"; path = (Join-Path $work "phone-chat.png") }
    Check ($shot.ok -and $shot.value.scrollWidth -le $shot.value.innerWidth -and [math]::Abs($shot.value.composeBottom - $shot.value.innerHeight) -le 1) "at phone width nothing scrolls sideways, and the composer stands at the foot of the screen"
    if ($env:HORDE_PWA_SHOTS -and (Test-Path -LiteralPath $env:HORDE_PWA_SHOTS -PathType Container)) { Copy-Item -LiteralPath (Join-Path $work "phone-chat.png") -Destination (Join-Path $env:HORDE_PWA_SHOTS "phone-chat.png") -Force }
    $toDoc = Invoke-Browser @{ cmd = "navTouch"; to = "decisions" }
    Check ($toDoc.ok -and $toDoc.value.scrolled -gt 0 -and $toDoc.value.inView -and $toDoc.value.opened) ("with the chat scrolled to its end, the Decisions tab is still on the screen, and a touch on it opens the questions (" + $(if ($toDoc.ok) { ConvertTo-Json $toDoc.value -Compress } else { $toDoc.reason }) + ")")
    $toChat = Invoke-Browser @{ cmd = "navTouch"; to = "chat" }
    Check ($toChat.ok -and $toChat.value.scrolled -gt 0 -and $toChat.value.inView -and $toChat.value.opened) ("with the questions scrolled to their end, the Chat tab is still on the screen, and a touch on it opens the chat (" + $(if ($toChat.ok) { ConvertTo-Json $toChat.value -Compress } else { $toChat.reason }) + ")")
    $b1 = Invoke-Browser @{ cmd = "back" }
    $b2 = Invoke-Browser @{ cmd = "back" }
    Check ($b1.ok -and $b1.value.doc -and -not $b1.value.chat -and $b2.ok -and $b2.value.chat -and -not $b2.value.doc) ("the phone's Back goes back to the questions, and Back again to the chat (" + $(if ($b1.ok) { ConvertTo-Json $b1.value -Compress } else { $b1.reason }) + " " + $(if ($b2.ok) { ConvertTo-Json $b2.value -Compress } else { $b2.reason }) + ")")
    $lk = Invoke-Browser @{ cmd = "lock" }
    $st = Invoke-Browser @{ cmd = "chatState" }
    Check ($lk.ok -and $lk.value.locked -and $st.ok -and $st.value.items -eq 0 -and -not $st.value.log.Contains("Use the second chime")) "a lock takes the chat off the page, not only out of sight"
    $null = Invoke-Browser @{ cmd = "unlock" }
    $null = Invoke-Browser @{ cmd = "chatTab"; which = "decisions" }

    Write-Host ""
    Write-Host "--- 11. the progress tab: the log in the order written, his place kept, the newest always within reach ---" -ForegroundColor Cyan
    # A changelog of the suite's own, in the shape the fleet's is, where a run with no progressFile set
    # looks for it: under the suite's home.
    $logFile = Join-Path $hh "progress\changelog.jsonl"
    New-Item -ItemType Directory -Path (Split-Path -Parent $logFile) -Force | Out-Null
    $kinds = @("started", "progress", "merged", "blocked", "waiting", "decision", "result", "done", "note")
    $logLines = @(1..40 | ForEach-Object {
        $extra = $(if ($_ -eq 1) { ',"lane":"F","task":"T-0096"' } else { '' })
        '{"v":1,"id":"20261012T' + ('{0:d2}' -f (10 + ($_ % 10))) + '0000Z-' + ('{0:d2}' -f $_) + '","ts":"2026-10-12T' + ('{0:d2}' -f (10 + ($_ % 10))) + ':00:00Z","kind":"' + $kinds[($_ - 1) % 9] + '","area":"' + $(if ($_ % 2) { "Form fill" } else { "Ask Orah voice" }) + '"' + $extra + ',"title":"Progress entry ' + $_ + '","text":"Asked: do thing ' + $_ + '.\nHappened: it was done.\nMeans: one less to do.\nNext: thing ' + ($_ + 1) + '."}'
    })
    $logLines += '{"v":1,"id":"20261012T200000Z-41","ts":"2026-10-12T20:00:00Z","kind":"note","area":"Form fill","title":"Not quite","text":"Means: entry 2 was only half done.","corrects":"20261012T120000Z-02"}'
    [System.IO.File]::WriteAllText($logFile, (($logLines | ForEach-Object { $_ + "`n" }) -join ""), $utf8)
    $run = Invoke-Run -Turns 1
    Check ($run.code -eq 0 -and $run.out.Contains("41 progress entries in ")) ("a run reads the changelog under its own home and sends its 41 entries (exit " + $run.code + ")")
    $pt = Invoke-Browser @{ cmd = "progressTab" }
    Check ($pt.ok -and $pt.value.shown -and -not $pt.value.doc -and -not $pt.value.chat -and -not $pt.value.keys -and $pt.value.selected -ceq "true") "a third tab, Progress, beside Decisions and Chat, shows the log, and the other views and the answering row go"
    $pw = Invoke-Browser @{ cmd = "progressWait"; text = "Progress entry 40" }
    $ids = @(); if ($pw.ok) { $ids = @($pw.value.ids) }
    Check ($pw.ok -and $pw.value.found -and $pw.value.items -eq 41 -and $ids[0].EndsWith("-01") -and $ids[39].EndsWith("-40") -and $ids[40].EndsWith("-41")) ("the entries are drawn oldest to newest in the order they were written, though their times are not in order (" + $(if ($pw.ok) { "" + $pw.value.items } else { $pw.reason }) + ")")
    Check ($pw.ok -and (@($pw.value.firstChips) -join "|") -ceq "Form fill|Started|Lane F|T-0096") ("an entry's chips: the area's plain name first, its kind in a plain word, and the lane and task when it names them (" + $(if ($pw.ok) { @($pw.value.firstChips) -join "|" } else { "" }) + ")")
    Check ($pw.ok -and $pw.value.firstTime -cmatch '\A[0-9]{1,2} [A-Z][a-z]{2} [0-9]{2}:[0-9]{2}\z' -and $pw.value.firstTitle -ceq "Progress entry 1" -and $pw.value.titleWeight -ge 600) ("with its day and time, and its title in bold (" + $(if ($pw.ok) { $pw.value.firstTime } else { "" }) + ")")
    Check ($pw.ok -and (@($pw.value.firstLabels) -join "|") -ceq "Asked: |Happened: |Means: |Next: " -and @($pw.value.firstParagraphs).Count -eq 4 -and $pw.value.firstParagraphs[1] -ceq "Happened: it was done.") "its text is four short paragraphs, each label in bold"
    Check ($pw.ok -and @($pw.value.corrections).Count -eq 1 -and $pw.value.corrections[0] -ceq "20261012T120000Z-02 <- Not quite" -and @($pw.value.notes) -ccontains "This corrects: Progress entry 2") ("a correction is shown on the entry it corrects, and in its own place says what it corrects (" + $(if ($pw.ok) { @($pw.value.corrections) -join "; " } else { "" }) + ")")
    $null = Save-Shot "phone-progress"
    $unread0 = $(if ($pw.ok -and $pw.value.tab -cmatch '\AProgress \(([0-9]+)\)\z') { [int]$Matches[1] } else { -1 })
    Check ($pw.ok -and $unread0 -gt 20 -and $unread0 -lt 41 -and $pw.value.count -ceq ("" + $unread0 + " new") -and $null -eq $pw.value.mark -and $pw.value.scrollY -eq 0) ("never read before, it opens at its start; what stands on the screen is read, and the tab and the foot count the rest (" + $(if ($pw.ok) { $pw.value.tab } else { "" }) + ")")
    Check ($pw.ok -and [math]::Abs($pw.value.footBottom - $pw.value.innerHeight) -le 1 -and $pw.value.newestInView -and $pw.value.scrollWidth -le $pw.value.innerWidth) "at phone width nothing scrolls sideways, and Jump to newest stands at the foot of the screen"
    $ro = Invoke-Browser @{ cmd = "progressReadOn"; screens = 5 }
    $unread1 = $(if ($ro.ok -and $ro.value.tab -cmatch '\AProgress \(([0-9]+)\)\z') { [int]$Matches[1] } else { -1 })
    Check ($ro.ok -and $unread1 -gt 8 -and $unread1 -lt $unread0 -and $ro.value.newestInView) ("as he reads down, his place moves on with him - " + $unread0 + " new, then " + $unread1 + " - and Jump to newest is still on the screen")
    $jump = Invoke-Browser @{ cmd = "progressTouch"; which = "newest" }
    Check ($jump.ok -and $jump.value.atEnd -and @($jump.value.onScreen) -ccontains $ids[40] -and $jump.value.tab -ceq ("Progress (" + $unread1 + ")")) ("a touch on Jump to newest lands on the newest entry, and marks nothing read: the entries jumped past are still new (" + $(if ($jump.ok) { $jump.value.tab } else { $jump.reason }) + ")")
    $firstUnread = $ids[41 - $unread1]
    $null = Invoke-Browser @{ cmd = "reload" }
    $null = Invoke-Browser @{ cmd = "unlock" }
    $null = Invoke-Browser @{ cmd = "progressTab" }
    $again = Invoke-Browser @{ cmd = "progressWait"; text = "Progress entry 40" }
    Check ($again.ok -and $null -ne $again.value.mark -and $again.value.mark.before -ceq $firstUnread -and $again.value.mark.top -ge 0 -and $again.value.mark.top -le 40 -and @($again.value.onScreen) -ccontains $firstUnread) ("after a reload the log opens at his place: a line where the new entries begin, at the top of the screen, the first new entry under it (" + $(if ($again.ok -and $null -ne $again.value.mark) { $again.value.mark.before } else { "no line" }) + ")")
    $unread2 = $(if ($again.ok -and $again.value.tab -cmatch '\AProgress \(([0-9]+)\)\z') { [int]$Matches[1] } else { -1 })
    Check ($unread2 -gt 0 -and $unread2 -le $unread1) ("with the count of what is still new (" + $unread2 + " of " + $unread1 + ")")
    $allRead = Invoke-Browser @{ cmd = "progressTouch"; which = "all" }
    Check ($allRead.ok -and $allRead.value.tab -ceq "Progress" -and $allRead.value.count -ceq "All read") ("a touch on Mark all read leaves nothing new (" + $(if ($allRead.ok) { $allRead.value.tab + "; " + $allRead.value.count } else { $allRead.reason }) + ")")
    $pdump = Invoke-Browser @{ cmd = "dump" }
    Check ($pdump.ok -and $pdump.value.Contains('"progressRead":{"id":"20261012T200000Z-41","n":41}') -and -not $pdump.value.Contains("Progress entry") -and -not $pdump.value.Contains("Not quite") -and -not $pdump.value.Contains("Ask Orah")) "Chrome keeps his place - an entry's id and line number - and no word of the log"
    [System.IO.File]::AppendAllText($logFile, ('{"v":1,"id":"20261012T210000Z-42","ts":"2026-10-12T21:00:00Z","kind":"done","area":"Whole fleet","title":"Written while he was reading","text":"Happened: one more."}' + "`n"), $utf8)
    $run = Invoke-Run -Turns 1
    $live = Invoke-Browser @{ cmd = "progressWait"; text = "Written while he was reading" }
    Check ($live.ok -and $live.value.found -and $live.value.items -eq 42) "an entry written meanwhile appears at the end without a reload"
    $null = Invoke-Browser @{ cmd = "chatTab"; which = "decisions" }
    $toProgress = Invoke-Browser @{ cmd = "navTouch"; to = "progress" }
    $backFrom = Invoke-Browser @{ cmd = "back" }
    Check ($toProgress.ok -and $toProgress.value.inView -and $toProgress.value.opened -and $backFrom.ok -and $backFrom.value.doc -and -not $backFrom.value.progress) ("with the questions scrolled to their end the Progress tab is still on the screen and a touch opens it; the phone's Back goes back to the questions (" + $(if ($toProgress.ok) { ConvertTo-Json $toProgress.value -Compress } else { $toProgress.reason }) + ")")
    $null = Invoke-Browser @{ cmd = "progressTab" }
    $lk = Invoke-Browser @{ cmd = "lock" }
    $ps = Invoke-Browser @{ cmd = "progressState" }
    Check ($lk.ok -and $lk.value.locked -and $ps.ok -and $ps.value.items -eq 0 -and $ps.value.tab -ceq "Progress") "a lock takes the log off the page, not only out of sight"
    $null = Invoke-Browser @{ cmd = "unlock" }
    $null = Invoke-Browser @{ cmd = "chatTab"; which = "decisions" }
    $probs = Invoke-Browser @{ cmd = "problems" }
    Check ($probs.ok -and @($probs.value).Count -eq 0) ("no exception, no console error and no policy violation in the whole run (" + $(if ($probs.ok) { @($probs.value) -join " | " } else { $probs.reason }) + ")")
    }
} finally {
    Remove-HordeTestChatThrall -Thrall $thrall
    Exit-HordeTestEmptyFleet -Pin $fleetPin
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
