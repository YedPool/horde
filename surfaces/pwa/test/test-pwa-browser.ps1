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
#   2. NO ANNOUNCE BUTTON (the founder, 2026-10-14): once the machine's signed word that he typed the
#      number arrives, the pairing screen offers Finish pairing - one tap, ONE passkey prompt, counted -
#      shut and saying why until the recovery code is written down; a relay that refuses and a passkey
#      that does not sign are each said beside it, and the horde's own view says, with no button, that
#      the machine has not answered yet; a run takes the key in and sends the snapshot; the question is
#      drawn by the window's own document (list.js). The unlock path is test-pwa-announce-browser.ps1's;
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
#  10b. the chat opens at its newest message (the founder, 2026-10-15): a long chat (80 more lines, some
#      wrapping) opens at its newest message, clear of the composer, whether the window stood at the top or
#      part way down the questions, and again on return to the app; Jump to latest is hidden within 48 px
#      of the bottom and shown above it, a real button at least 44 px tall in the composer's own band; a
#      refresh and new lines while he reads back keep his place, and the button and a polite live region
#      say how many came; a touch, Space or Enter jumps, Shift+Tab reaches it with a visible ring; his own
#      line sent takes him down; its words stand out from its face by 4.5 to 1, light and dark;
#  10c. a photo: a touch on Photo opens the picker; a 3000 by 2000 JPEG with a camera block is shrunk by
#      Chrome's own canvas, signed under the unlocked session (no prompt; section 14 counts them) and put in parts; a real run writes
#      it to the PC's inbox at 1600 px with no camera block left, and posts one line; an HTML page called
#      .jpg is refused on the phone with nothing sent; his own photo sent while scrolled up takes him down,
#      and one arriving while he reads back (from another window) keeps his place and counts as new;
#  11. the progress tab (the founder asked for it, 2026-10-12): a changelog under the suite's home is sent by
#      a run and drawn oldest to newest in the order written, each entry with its time, bold title, labelled
#      paragraphs and chips; a correction on what it corrects; what stands on the screen is read, reading
#      down moves his place, Jump to newest marks nothing, a reload opens at his place, Mark all read; the
#      tab is reached by touch from the other views, and a lock takes the log off the page.
#  12. the cards (the founder's phone, 2026-10-14): a real cards envelope from a run is drawn, the Thrall's
#      card first and one per lane; a touch on the Thrall's card opens the whole log, and on a lane's card
#      that lane's stream, its area's entries only;
#  12b. the stream's entries folded (the founder asked, 2026-10-14): each opens as one line, its title and
#      its day and time, nothing else to be seen and all of one height, a long title cut; a touch opens one
#      and folds it by its head or title, a button inside does its own thing; one opened stays open while a
#      new entry redraws the log; leaving the stream forgets; Enter and Space toggle; aria-expanded follows;
#  13. a relay refusing every read with 401: the entry sent meanwhile is not drawn, and arrives once reads
#      come back; meanwhile the page says so and keeps saying it, with the sign-in banner and the time of
#      the last read that worked;
#  14. the unlocked session (design note "Unlocked session", 2026-10-14), its passkey prompts COUNTED by
#      the virtual authenticator's signature counter: what Chrome gives when the app is left is measured
#      and said; against the real PC, which keeps sessions (the unlocked session's PC side, relay/Session.ps1
#      and channels/Sessions.ps1), an unlock and then three answers, a chat line and a photo are ONE prompt and land
#      once, an answer to a needsPasskey question one more, and after the PC's idle limit (its own setting,
#      one minute here), after the app was away past its setting and after a reload the next answer asks
#      once again - each must-pass beside its control, every session envelope read and verified by the
#      PC's own reader and WebAuthn verifier before the run takes it;
#  15. THE SHIPPED TIMES (the founder's Q75 (c), 2026-10-15: keep the session through a switch-away of up
#      to 10 minutes): with config.json as New-HordePwaSite builds it by default, and with no times in it
#      at all (app.js's own fallbacks), a session survives 9 minutes hidden and is gone after 11 - beside a
#      CONTROL with the old five-minute lock, which ends it at 9. Nothing is waited: the page's clock is
#      moved between hidden and shown, and the return check in app.js measures the time hidden by it.
#
# NEEDS Chrome installed and Node. Without either the suite says so and exits 3, a partial run, never 0.
# The suite starts the browser itself (test/lib/Browser.ps1), in a kill-on-close job of its own, and
# ends it with its profile in the finally block, however the driver ends: until 2026-10-14 the driver
# started it, and a driver that died first left the browser running.

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
. (Join-Path $root "surfaces\pwa\Site.ps1")
. (Join-Path $root "test\lib\ChatFleet.ps1")
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
$work = Join-Path $env:TEMP ("horde-pwa-browser-" + [guid]::NewGuid().ToString("N"))
$hh = Join-Path $work "home"
$mailboxes = Join-Path $work "relay"
$site = Join-Path $work "site"
New-Item -ItemType Directory -Path (Join-Path $hh "settings"), $mailboxes -Force | Out-Null
$keysMade = @()
$drv = $null
$browser = $null
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
function Get-MachineEnvelopes {
    # What the phone has put into the machine's mailbox, each read by the PC's own reader: from item -Skip on.
    param([int]$Skip = 0)
    $box = Join-Path $mailboxes ($mailbox -replace '/', '\')
    $items = @(Get-ChildItem -LiteralPath $box -Filter "*.item" | Sort-Object Name)
    return @($items | Select-Object -Skip $Skip | ForEach-Object { $t = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::ASCII); Read-HordeRelayEnvelope -Text $t.Substring($t.IndexOf([char]10) + 1) })
}
function Get-MachineCount { return @(Get-ChildItem -LiteralPath (Join-Path $mailboxes ($mailbox -replace '/', '\')) -Filter "*.item").Count }
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
    # Away 1 s ends the unlocked session (section 14) before 2 s hidden locks the horde (section 9).
    $built = New-HordePwaSite -Out $site -Transport "binding" -LockAfterHiddenSeconds 2 -SessionAwaySeconds 1
    Check ($built.state -ceq "known") "CONTROL: the site is built as it ships, with the local test transport"
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay.json"), '{"schemaVersion": 1, "settings": {"horde": "work"}}', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay-run.json"), '{"schemaVersion": 1, "settings": {"watchMs": 200}}', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay-chat.json"), '{"schemaVersion": 1, "settings": {"sendIntervalMs": 0, "startTurns": 3}}', $utf8)
    $chatFixtures = @(Get-HordeTestChatFixtureFiles | ForEach-Object { . $_ -Root $root })
    $thrall = New-HordeTestChatThrall -Fixtures $chatFixtures
    Check ($null -ne $thrall -and (New-HordeTestFleetMessenger -HordeHome $hh -Folder $fake) -cne "") "CONTROL: a synthetic Thrall and a messenger stand-in are ready for the chat"
    Add-HordeTestChatTurns -Thrall $thrall -Turns @(@{ role = "user"; text = "how is the chime going?" }, @{ role = "assistant"; text = ("three chimes recorded, " + [char]0x05E9 + [char]0x05DC + [char]0x05D5 + [char]0x05DD) }, @{ role = "user"; text = "wezfleet: a message is waiting for you (id 7a5e99735c69f1bc6fdc90f7530561bc) - run 'wezfleet mail read' to take it; this line is a pointer, not the message, and re-reading it changes nothing" })
    $id = New-HordeRelayMachineIdentity -HordeHome $hh -Provider "software"
    Check ($id.state -ceq "known") "CONTROL: the machine has its relay identity"
    $keysMade = @(@{ n = $id.value.sign.name; s = $id.value.scope }, @{ n = $id.value.agree.name; s = $id.value.scope })
    $store = Join-Path $hh "store\decisions"
    $title = "Should the closing sound play when the assistant closes?"
    $q = Invoke-HordeDecision -Operation "add" -Root $store -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = @{ title = $title; kind = "yes-no"; whatItIs = "The app has no closing sound today."; group = "voice"; askedBy = "orc-b" } }
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
    Write-Host "--- 1. the app loads under its policy, and pairs with Chrome's passkey ---" -ForegroundColor Cyan
    $open = Invoke-Browser @{ cmd = "open" }
    Check ($open.ok -and $open.value.empty) "the app starts, shows that it holds no horde yet"
    $fi = Invoke-Browser @{ cmd = "firstInstall" }
    Check ($fi.ok -and $fi.value.controlled -and $fi.value.mark) ("THE FIRST INSTALL DOES NOT RELOAD: the first worker takes control of the page and the page stays as it was (" + $(if ($fi.ok) { ConvertTo-Json $fi.value -Compress } else { $fi.reason }) + ")")
    $offer = New-HordeRelayPairingOffer -HordeHome $hh -RpId "localhost" -Origins @($origin)
    $paired = Invoke-Browser @{ cmd = "pair"; offer = $offer.value.text; label = "Founder phone" }
    Check ($paired.ok -and $paired.value.paired -and $paired.value.fingerprint -cmatch '\A[0-9]{4}-[0-9]{4}-[0-9]{4}\z') ("Chrome makes the passkey and the app shows a fingerprint (" + $(if ($paired.ok) { $paired.value.fingerprint + $paired.value.notice } else { $paired.reason }) + ")")
    $done = Complete-HordeRelayPairing -HordeHome $hh -Response $(if ($paired.ok) { $paired.value.response } else { "" })
    Check ($done.ok -and $done.value.fingerprint -ceq $paired.value.fingerprint) ("the machine enrolls Chrome's passkey and computes the same fingerprint (" + $(if ($done.ok) { $done.value.fingerprint } else { $done.reason }) + ")")
    Check ($done.ok -and $done.value.device.prf -eq $true) "and records that the passkey has PRF"
    $before = Invoke-Browser @{ cmd = "finishState" }
    Check ($before.ok -and -not $before.value.finishShown -and $before.value.waiting -and @($before.value.announceButtons).Count -eq 0) ("BEFORE THE MACHINE'S WORD the pairing screen waits, Finish pairing is not offered, and no button anywhere offers to announce (" + $(if ($before.ok) { ConvertTo-Json $before.value -Compress } else { $before.reason }) + ")")
    $confirmed = Confirm-HordeRelayDevice -HordeHome $hh -Id $(if ($done.ok) { $done.value.device.id } else { "none" }) -Fingerprint $(if ($paired.ok) { $paired.value.fingerprint } else { "" })
    Check ($confirmed.ok -and $confirmed.value.device.state -ceq "trusted") "the founder confirms it at the machine"
    # What horde relay pair does once he typed the number (cli/RelayPair.ps1, Send-HordeRelayPairConfirmed).
    $word = New-HordeRelayPairingConfirmedText -HordeHome $hh -Offer $offer.value.offer -Device $(if ($done.ok) { $done.value.device.id } else { "none" })
    $lc = Connect-HordeRelay -Name "local" -Options @{ root = $mailboxes }
    $told = $(if ($word.state -ceq "known" -and $lc.state -ceq "known") { Send-HordeRelayItem -Connection $lc.value -Mailbox $offer.value.pairMailbox -Text $word.value.text -Key $word.value.key } else { $null })
    Check ($null -ne $told -and $told.state -ceq "known") "the machine puts its signed word that the phone is confirmed into the offer's pairing mailbox"

    Write-Host ""
    Write-Host "--- 2. Finish pairing - one tap, one passkey prompt - announces the key, and the window's document draws the question ---" -ForegroundColor Cyan
    $why = Invoke-Browser @{ cmd = "finishWhy" }
    Check ($why.ok -and $why.value.appeared -and $why.value.before.finishDisabled -and $why.value.before.why -and $why.value.before.whyWords.Contains("recovery code") -and -not $why.value.after.finishDisabled -and -not $why.value.after.why) ("once the machine's word arrives Finish pairing appears; while the recovery-code box is not ticked it is shut and says why; ticked, it opens (" + $(if ($why.ok) { $why.value.before.whyWords } else { $why.reason }) + ")")
    $null = Invoke-Browser @{ cmd = "countPrompts" }
    $null = Invoke-Browser @{ cmd = "relayFail"; on = $true }
    $f1 = Invoke-Browser @{ cmd = "finishTry" }
    $null = Invoke-Browser @{ cmd = "relayFail"; on = $false }
    Check ($f1.ok -and $f1.value.status.Contains("The relay did not take it") -and -not $f1.value.status.Contains("a stand-in") -and $f1.value.paired -and $f1.value.recovery) ("a Finish pairing the relay refuses says so beside its button, in the app's words, and the pairing screen stays with its code (" + $(if ($f1.ok) { $f1.value.status } else { $f1.reason }) + ")")
    $p1 = Invoke-Browser @{ cmd = "prompts" }
    Check ($p1.ok -and $p1.value -eq 1) ("ONE TAP, ONE PASSKEY PROMPT: Finish pairing asked the passkey once (" + $(if ($p1.ok) { $p1.value } else { $p1.reason }) + ")")
    $null = Invoke-Browser @{ cmd = "passkeyRefusesOnce" }
    $f2 = Invoke-Browser @{ cmd = "finishTry" }
    Check ($f2.ok -and $f2.value.status.Contains("did not sign") -and $f2.value.paired) ("a Finish pairing the passkey does not sign says so beside its button (" + $(if ($f2.ok) { $f2.value.status } else { $f2.reason }) + ")")
    $null = Invoke-Browser @{ cmd = "countPrompts" }
    $ann = Invoke-Browser @{ cmd = "finish" }
    Check ($ann.ok -and $ann.value.enabledAfterTick -and $ann.value.doc -and $ann.value.recoveryCleared) ("Finish pairing opens once the code is written down; after it the list shows and the code leaves the screen (" + $(if ($ann.ok) { $ann.value.notice } else { $ann.reason }) + ")")
    $p2 = Invoke-Browser @{ cmd = "prompts" }
    Check ($p2.ok -and $p2.value -eq 1) ("and that announcement was one passkey prompt (" + $(if ($p2.ok) { $p2.value } else { $p2.reason }) + ")")
    $box = Invoke-Browser @{ cmd = "announceBox" }
    Check ($box.ok -and $box.value.shown -and $box.value.words.Contains("has not answered this phone yet") -and $box.value.buttons -eq 0) ("until the machine answers, the horde's own view says so, and offers no button (" + $(if ($box.ok) { $box.value.words } else { $box.reason }) + ")")
    # EACH ORC'S PUBLISHED LIST (T-0328): fleet.db in the machine's home holds the Thrall's list of three - one
    # linking question 1, the question the store holds - and Orc F's empty one; Orc G never published. The run
    # below reads them from the file (read only) and seals them into the snapshot with the question.
    $seedJs = Join-Path $root "test\fixtures\phone-published-seed.mjs"
    $pubFile = Join-Path $work "thrall-items.json"
    [System.IO.File]::WriteAllText($pubFile, '[{"text":"Sales queue: forward the contract page?","recommendation":"yes, today","importance":"high","blocks":"part"},{"questionNumber":1,"text":"Closing sound: play it?","recommendation":"play it, short","importance":"normal","blocks":"none"},{"text":"Notifications on fleet.db?","importance":"low"}]', $utf8)
    $emptyFile = Join-Path $work "f-items.json"
    [System.IO.File]::WriteAllText($emptyFile, '[]', $utf8)
    & $node.Source $seedJs seed $hh
    $seeded = ($LASTEXITCODE -eq 0)
    if ($seeded) { & $node.Source $seedJs publish $hh thrall $pubFile; $seeded = ($LASTEXITCODE -eq 0) }
    if ($seeded) { & $node.Source $seedJs publish $hh F $emptyFile; $seeded = ($LASTEXITCODE -eq 0) }
    Check $seeded "CONTROL: fleet.db in the machine's home holds the Thrall's published list of three (one linking question 1) and Orc F's empty one"
    $run = Invoke-Run -Turns 2
    Check ($run.code -eq 0 -and $run.out.Contains("is now in the trust store") -and $run.out.Contains("snapshot of 1 open question(s)")) ("a run takes the app's key and sends the snapshot (exit " + $run.code + ")")
    $seen = Invoke-Browser @{ cmd = "waitText"; text = $title }
    Check ($seen.ok -and $seen.value.found) "the question appears in the app, drawn by list.js, without a reload"
    $box = Invoke-Browser @{ cmd = "announceBox" }
    Check ($box.ok -and -not $box.value.shown) "and once it has, the offer to announce goes"
    # The founder's gap: the questions were on his phone and the Orcs' published lists were not.
    $pl = Invoke-Browser @{ cmd = "waitPublished"; text = "Sales queue: forward the contract page?" }
    $plText = $(if ($pl.ok) { $pl.value.text } else { "" })
    Check ($pl.ok -and $pl.value.found -and $plText.Contains("Thrall: published list") -and $plText.Contains("Recommended: yes, today") -and $plText.Contains("importance high - blocks part of the work") -and $plText.Contains("Notifications on fleet.db?")) ("EACH ORC'S PUBLISHED LIST is on the phone beside the questions: the Thrall's items with their recommendation, importance and blocking (" + ($plText -replace "\s+", " ") + ")")
    Check ($plText -match 'Published .+ - checked ') "and its published time and the time it was checked"
    Check ($plText.Contains("Orc F published an empty list: nothing waits on you from here.")) "AN ORC WITH AN EMPTY LIST: the phone says so in plain words"
    Check (-not $plText.Contains("Orc G") -and -not $plText.Contains("Closing sound: play it?")) "an Orc that never published is not drawn as a list, and the item that links question 1 is not drawn twice"
    Check ($pl.ok -and $pl.value.listed.Contains($title) -and $pl.value.listed.Contains("play it, short")) "and that question, shown once, carries the published item's recommendation"
    [System.IO.File]::WriteAllText($pubFile, '[{"text":"Sales queue: forward the contract page, v3?","recommendation":"yes, today","importance":"high","blocks":"part"},{"questionNumber":1,"text":"Closing sound: play it?","recommendation":"play it, short","importance":"normal","blocks":"none"}]', $utf8)
    & $node.Source $seedJs publish $hh thrall $pubFile
    $run = Invoke-Run -Turns 1
    $pl2 = Invoke-Browser @{ cmd = "waitPublished"; text = "contract page, v3?" }
    Check ($run.code -eq 0 -and $pl2.ok -and $pl2.value.found -and -not $pl2.value.text.Contains("Notifications on fleet.db?")) ("a list published again reaches the phone without a reload, and the item it dropped is gone (exit " + $run.code + ")")
    # M1 (review of PR 365): an Orc that published and asks nothing, with no status card, is still a card the founder
    # can choose. Orc G has no question and no card in a lanes document: it publishes one item and nothing else.
    $gFile = Join-Path $work "g-items.json"
    [System.IO.File]::WriteAllText($gFile, '[{"text":"Orc G only item: rotate the keys?","recommendation":"next week","importance":"low"}]', $utf8)
    & $node.Source $seedJs publish $hh G $gFile
    $gSeeded = ($LASTEXITCODE -eq 0)
    $run = Invoke-Run -Turns 1
    $gc = Invoke-Browser @{ cmd = "publishedCard"; name = "Orc G" }
    Check ($gSeeded -and $run.code -eq 0 -and $gc.ok -and $gc.value.found -and $gc.value.slot -ceq "0 open - 1 published") ("A PUBLISHED-ONLY ORC HAS A CARD: Orc G publishes one item, asks nothing and has no status card, and its card says '0 open - 1 published' (exit " + $run.code + "; " + $(if ($gc.ok) { "found " + $gc.value.found + ", '" + $gc.value.slot + "'" } else { $gc.reason }) + ")")
    $gt = Invoke-Browser @{ cmd = "publishedCard"; name = "Orc G"; click = $true }
    $gp = Invoke-Browser @{ cmd = "waitPublished"; text = "Orc G only item: rotate the keys?" }
    $gpText = $(if ($gp.ok) { $gp.value.text } else { "" })
    Check ($gt.ok -and $gt.value.pressed -ceq "true" -and $gp.ok -and $gp.value.found -and $gpText.Contains("Recommended: next week") -and -not $gpText.Contains("Thrall: published list")) ("choosing that card shows Orc G's list, and only its own (" + ($gpText -replace "\s+", " ") + ")")
    $null = Invoke-Browser @{ cmd = "publishedCard"; name = "All questions"; click = $true }
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
    # HE HAS ANSWERED IT, so it is not in his list (2026-10-12): it stands under the folded "With Thrall",
    # with his answer, and the list itself shows the order line and that heading only.
    $again = Invoke-Browser @{ cmd = "waitText"; text = $title; folded = $true }
    Check ($again.ok -and $again.value.found -and $again.value.text.Contains("short chime") -and $again.value.shown.Contains("With Thrall (1)") -and -not $again.value.shown.Contains($title)) ("and the question he answered is there again, out of his list under the folded With Thrall, his answer with it (" + $(if ($again.ok) { ($again.value.shown -replace '\s+', ' ') } else { $again.reason }) + ")")
    Check ($again.ok -and $again.value.shown.Contains("Order by") -and $again.value.shown.Contains("Task importance") -and $again.value.shown.Contains("Blocking")) "the line where he chooses the order is on the phone too: Date, Task importance, Blocking"
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
    Write-Host "--- 6b. a new version: the page reloads once, never over his words ---" -ForegroundColor Cyan
    $wv = Invoke-Browser @{ cmd = "workerVersion" }
    Check ($wv.ok -and $wv.value -ceq $built.value.version) ("the worker in control says its version, the site's (" + $(if ($wv.ok) { $wv.value } else { $wv.reason }) + ")")
    $held = Invoke-Browser @{ cmd = "newWorker"; draft = "half a line to the Thrall"; ms = 6000 }
    Check ($held.ok -and -not $held.value.reloaded -and $held.value.loads -eq 0 -and $held.value.notice.Contains("A new version is ready - it loads when you finish.")) ("WITH A DRAFT OPEN a new worker does not reload the page; it says a new version is ready (" + $(if ($held.ok) { ConvertTo-Json $held.value -Compress } else { $held.reason }) + ")")
    $fin = Invoke-Browser @{ cmd = "finishDraft" }
    Check ($fin.ok -and $fin.value.reloaded -and $fin.value.loads -eq 1) ("the draft gone, the page hidden and shown again loads the new version, once (" + $(if ($fin.ok) { ConvertTo-Json $fin.value -Compress } else { $fin.reason }) + ")")
    $nw = Invoke-Browser @{ cmd = "newWorker" }
    Check ($nw.ok -and $nw.value.reloaded -and $nw.value.loads -eq 1 -and -not $nw.value.notice.Contains("new version")) ("A NEW WORKER TAKING CONTROL reloads the page once, and no more (" + $(if ($nw.ok) { ConvertTo-Json $nw.value -Compress } else { $nw.reason }) + ")")

    Write-Host ""
    Write-Host "--- 7. the recovery code reads, and never answers ---" -ForegroundColor Cyan
    # A second question first: the one he answered is out of his list, and has no field to type in.
    $q2 = Invoke-HordeDecision -Operation "add" -Root $store -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = @{ title = "Which chime of the three?"; kind = "yes-no"; whatItIs = "Three chimes were tried."; group = "voice"; askedBy = "orc-b" } }
    Check ($q2.state -ceq "known" -and $q2.value.outcome -ceq "done") "CONTROL: a second question is asked"
    $run = Invoke-Run -Turns 1
    $null = Invoke-Browser @{ cmd = "unlock" }
    $seen2 = Invoke-Browser @{ cmd = "waitText"; text = "Which chime of the three?" }
    $null = Invoke-Browser @{ cmd = "lock" }
    $rc = Invoke-Browser @{ cmd = "recover"; code = $(if ($paired.ok) { $paired.value.recoveryCode } else { "" }) }
    Check ($rc.ok -and $rc.value.doc -and $rc.value.mode.Contains("Read only")) ("the recovery code unlocks the horde, said to be read only (" + $(if ($rc.ok) { $rc.value.notice } else { $rc.reason }) + ")")
    $ro = Invoke-Browser @{ cmd = "answer"; text = "Not from a recovery code."; via = "enter"; mailbox = $mailbox; question = "Which chime of the three?" }
    Check ($ro.ok -and -not $ro.value.put) "an answer typed then is not sent: nothing reaches the machine's mailbox"
    $lk = Invoke-Browser @{ cmd = "lock" }
    Check ($lk.ok -and $lk.value.locked -and $lk.value.boxes -eq 0 -and $lk.value.published -eq 0 -and $lk.value.fields -ceq "") ("a lock removes the horde's list - and its Orcs' published lists - and the words left in its fields, not only hides them (review of a8b732d, finding 2: " + $(if ($lk.ok) { "" + $lk.value.boxes + " box(es), " + $lk.value.published + " published box(es), fields '" + $lk.value.fields + "'" } else { $lk.reason }) + ")")
    $null = Invoke-Browser @{ cmd = "unlock" }

    Write-Host ""
    Write-Host "--- 8. the row's Send key, by touch ---" -ForegroundColor Cyan
    $seen2 = Invoke-Browser @{ cmd = "waitText"; text = "Which chime of the three?" }
    $null = Save-Shot "phone-two-questions"
    $touch = Invoke-Browser @{ cmd = "answer"; text = "The second one."; via = "touch"; mailbox = $mailbox; question = "Which chime of the three?" }
    $run = Invoke-Run -Turns 1
    $said = @(Get-Said)
    Check ($seen2.ok -and $seen2.value.found -and $touch.ok -and $touch.value.put -and $said.Count -eq 2 -and @($said | Where-Object { $_.data.text -ceq "The second one." }).Count -eq 1) ("a touch on Send sends the answer in the field with the caret, and it lands (" + $said.Count + " records; seen " + $(if ($seen2.ok) { $seen2.value.found } else { $seen2.reason }) + "; touch " + $(if ($touch.ok) { ConvertTo-Json $touch.value -Compress } else { $touch.reason }) + ")")

    Write-Host ""
    Write-Host "--- 8b. a question of parts: each part is signed and sent by itself, and the question stays until the last ---" -ForegroundColor Cyan
    # THE FOUNDER, 2026-10-12: sub-questions each send by themselves; the question leaves the list when
    # all its parts are answered. Before the phone sent a part as a part, it sent "(b) words", the store
    # kept that as an answer to the WHOLE question, and the question left his phone after one part.
    $partsTitle = "Two things to settle about the chime, one by one."
    $q3 = Invoke-HordeDecision -Operation "add" -Root $store -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = @{ title = $partsTitle; kind = "parts"; whatItIs = "Follow-ups."; parts = @("(a) Which of the three chimes?", "(b) How loud should it be?"); group = "voice"; askedBy = "orc-b" } }
    $n3 = $(if ($q3.state -ceq "known") { [int]$q3.value.number } else { 0 })
    $run = Invoke-Run -Turns 1
    $seen3 = Invoke-Browser @{ cmd = "waitText"; text = $partsTitle }
    Check ($q3.state -ceq "known" -and $q3.value.outcome -ceq "done" -and $seen3.ok -and $seen3.value.found) "CONTROL: a question of two parts is asked, and the app shows it"
    $pa = Invoke-Browser @{ cmd = "answerPart"; question = $partsTitle; part = 0; text = "The second chime."; mailbox = $mailbox }
    # ON ITS WAY, IT SAYS SO (the founder, 2026-10-14): before any run has taken it, the part folds to
    # Answered with what became of it - sent - and never to an empty field.
    $pending = $null
    for ($i = 0; $i -lt 40; $i++) { $pending = Invoke-Browser @{ cmd = "parts"; question = $partsTitle }; if ($pending.ok -and $null -ne $pending.value -and $pending.value.folded[0] -eq $true) { break }; Start-Sleep -Milliseconds 250 }
    Check ($pending.ok -and $null -ne $pending.value -and $pending.value.folded[0] -eq $true -and "$($pending.value.marks[0])" -ceq "Answered, sent") ("BEFORE THE PC HAS IT, the part stands answered and says it is sent (" + $(if ($pending.ok) { ConvertTo-Json $pending.value -Compress } else { $pending.reason }) + ")")
    # Two turns, as for the first answer above: one takes the answer in, the next sends the snapshot that holds it.
    $run = Invoke-Run -Turns 1
    $run = Invoke-Run -Turns 1
    $saidParts = @(Get-Said | Where-Object { $_.data.number -eq $n3 })
    Check ($pa.ok -and $pa.value.put -and $saidParts.Count -eq 1 -and $saidParts[0].data.PSObject.Properties["part"] -and $saidParts[0].data.part -ceq "a" -and $saidParts[0].data.text -ceq "The second chime." -and $saidParts[0].data.route -ceq "phone") ("A PART ANSWERED IN THE APP is signed and sent by itself, and lands as the record of THAT PART - his words untouched, no letter put before them (" + $(if ($saidParts.Count) { ConvertTo-Json $saidParts[0].data -Compress } else { "no record; " + $(if ($pa.ok) { ConvertTo-Json $pa.value -Compress } else { $pa.reason }) }) + ")")
    Check ($pa.ok -and $pa.value.focusPart -eq 1) "and the caret went on to part (b)"
    $shown3 = Invoke-HordeDecision -Operation "show" -Root $store -Request @{ number = $n3 }
    Check ($shown3.value.question.thread.turn -ceq "founder" -and (@($shown3.value.question.thread.parts | ForEach-Object { $_.letter + ":" + $_.answered }) -join ",") -ceq "a:True,b:False") "the list says part (a) is answered, part (b) is not, and the question is still his"
    Start-Sleep -Seconds 6
    $still = Invoke-Browser @{ cmd = "parts"; question = $partsTitle }
    Check ($still.ok -and $null -ne $still.value -and (@($still.value.folded) -join ",") -ceq "True,False" -and $still.value.marks[0] -ceq "Answered") ("THE QUESTION IS STILL IN HIS LIST ON THE PHONE after the snapshot that holds part (a): that part folded to Answered, part (b) open (" + $(if ($still.ok) { ConvertTo-Json $still.value -Compress } else { $still.reason }) + ")")
    $pb = Invoke-Browser @{ cmd = "answerPart"; question = $partsTitle; part = 1; text = "Quiet."; mailbox = $mailbox }
    $run = Invoke-Run -Turns 1
    $run = Invoke-Run -Turns 1
    $saidParts = @(Get-Said | Where-Object { $_.data.number -eq $n3 })
    $shown3 = Invoke-HordeDecision -Operation "show" -Root $store -Request @{ number = $n3 }
    Check ($pb.ok -and $pb.value.put -and $saidParts.Count -eq 2 -and $saidParts[1].data.part -ceq "b" -and $saidParts[1].data.text -ceq "Quiet." -and $shown3.value.question.thread.turn -ceq "warchief") ("part (b), sent by itself, is the second record, and with it the question is the keeper's turn (" + $saidParts.Count + " record(s))")
    $goneParts = $null
    for ($i = 0; $i -lt 40; $i++) { $goneParts = Invoke-Browser @{ cmd = "parts"; question = $partsTitle }; if ($goneParts.ok -and $null -eq $goneParts.value) { break }; Start-Sleep -Milliseconds 500 }
    $folded3 = Invoke-Browser @{ cmd = "waitText"; text = $partsTitle; folded = $true }
    Check ($goneParts.ok -and $null -eq $goneParts.value -and $folded3.ok -and $folded3.value.found -and -not $folded3.value.shown.Contains($partsTitle)) "AND THEN, all its parts answered, it leaves his list on the phone for the folded With Thrall"

    Write-Host ""
    Write-Host "--- 8c. a snapshot that leaves a question out says so, above the list ---" -ForegroundColor Cyan
    # relay/js/protocol.js, withheldWords. A record is planted that the machine withholds - it holds what
    # looks like a secret - as a record written before a pattern was added would be: the snapshot names it
    # by number, and the page must say the list is short, how many and why, and show nothing of it.
    $token = "ghp_" + ("Ab3" * 10)
    $plantSeq = @(Get-ChildItem -LiteralPath $store -Filter "*.json").Count + 1
    $plantFile = Join-Path $store ($plantSeq.ToString("D10") + ".json")
    $planted = '{"schemaVersion":1,"sequence":' + $plantSeq + ',"id":"' + [guid]::NewGuid().ToString("N") + '","kind":"question-added","at":"2026-10-14T12:00:00.0000000Z","actor":"warchief","requestHash":"' + ("0" * 64) + '","data":{"number":' + ($n3 + 1) + ',"question":{"title":"Rotate the deploy token please now","kind":"yes-no","whatItIs":"The token is ' + $token + '","group":"ops","askedBy":"orc-a"}}}'
    [System.IO.File]::WriteAllText($plantFile, $planted, $utf8)
    $run = Invoke-Run -Turns 1
    $short = Invoke-Browser @{ cmd = "notShown"; shown = $true }
    Check ($run.out.Contains("1 withheld") -and $short.ok -and $short.value.shown -and $short.value.words -ceq "1 question is not shown here: it holds what looks like a secret, so it is shown at the machine only.") ("the machine withholds the question, and the app says so in one line above the list: how many, and why (" + $(if ($short.ok) { $short.value.words } else { $short.reason }) + ")")
    Check ($short.ok -and -not $short.value.page.Contains("Rotate the deploy token") -and -not $short.value.page.Contains("ghp_") -and -not $short.value.page.Contains("The token is")) "and nothing of the withheld question is anywhere on the page: not its title, not its text"
    Remove-Item -LiteralPath $plantFile
    $run = Invoke-Run -Turns 1
    $wholeAgain = Invoke-Browser @{ cmd = "notShown"; shown = $false }
    Check ($wholeAgain.ok -and -not $wholeAgain.value.shown -and $wholeAgain.value.words -ceq "") ("the next snapshot, with nothing left out, takes the line away (" + $(if ($wholeAgain.ok) { "shown " + $wholeAgain.value.shown } else { $wholeAgain.reason }) + ")")

    Write-Host ""
    Write-Host "--- 8d. reads that fail are said, with the time of the last that worked ---" -ForegroundColor Cyan
    $null = Invoke-Browser @{ cmd = "readFail"; reason = "the relay answered the read with 401: not signed in" }
    $nb = Invoke-Browser @{ cmd = "noticeHeld"; text = "Not signed in to the relay - sign in again."; hold = 8000 }
    Check ($nb.ok -and $nb.value.ok -and $nb.value.notice -cmatch 'Not signed in to the relay - sign in again\. Last updated [0-9]{2}:[0-9]{2}\.' -and $nb.value.notice.Contains("The relay could not be read just now")) ("A 401 ON THE MAILBOX READ shows the sign-in banner and the last-updated time, and it stays (" + $(if ($nb.ok) { $nb.value.notice } else { $nb.reason }) + ")")
    $null = Invoke-Browser @{ cmd = "readFail"; reason = "" }
    $ng = Invoke-Browser @{ cmd = "noticeHeld"; text = "Not signed in to the relay"; gone = $true }
    Check ($ng.ok -and $ng.value.ok -and -not $ng.value.notice.Contains("Not signed in")) ("a successful read clears it (" + $(if ($ng.ok) { $ng.value.notice } else { $ng.reason }) + ")")

    Write-Host ""
    Write-Host "--- 9. hidden, it locks itself; shown again, nothing openedshows first ---" -ForegroundColor Cyan
    $hid = Invoke-Browser @{ cmd = "hide"; ms = 3500 }
    Check ($hid.ok -and $hid.value.tabs.Contains("(locked)") -and $hid.value.boxes -eq 0 -and $hid.value.published -eq 0 -and $hid.value.fields -ceq "") ("left hidden past the lock time (2 s in this build), every horde locks while still hidden, its list removed (" + $(if ($hid.ok) { $hid.value.tabs + "; " + $hid.value.boxes + " box(es)" } else { $hid.reason }) + ")")
    $null = Invoke-Browser @{ cmd = "unlock" }
    $null = Invoke-Browser @{ cmd = "waitText"; text = $title; folded = $true }
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
    # THE POINTER LINE IS A MARKER (T-0309, the founder 2026-10-20): the third turn above is wezfleet's pointer, typed at the
    # Thrall's prompt; the phone shows "Message received" and its time, and nothing of the line - no id, no wording.
    Check ($w1.ok -and $w1.value.log.Contains("Message received") -and -not $w1.value.log.Contains("wezfleet") -and -not $w1.value.log.Contains("7a5e9973") -and -not $w1.value.log.Contains("pointer")) ("the wezfleet pointer line is drawn as a Message received marker, with none of its words or its id (" + $(if ($w1.ok) { ($w1.value.log -replace '\s+', ' ') } else { $w1.reason }) + ")")
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

    Write-Host ""
    Write-Host "--- 10b. the chat opens at its newest message, and Jump to latest (the founder, 2026-10-15) ---" -ForegroundColor Cyan
    # A LONG CHAT: 80 more lines, every seventh long enough to wrap over many lines at phone width.
    $longChat = @()
    for ($i = 1; $i -le 80; $i++) {
        $t = "long chat line " + $i
        if ($i % 7 -eq 0) { $t += " " + ("which goes on long enough to wrap over several lines on a phone screen, " * 6) }
        $longChat += @{ role = $(if ($i % 2 -eq 1) { "assistant" } else { "user" }); text = $t }
    }
    Add-HordeTestChatTurns -Thrall $thrall -Turns $longChat
    $null = Invoke-Run -Turns 2
    $lw = Invoke-Browser @{ cmd = "chatWait"; text = "long chat line 80" }
    Check ($lw.ok -and $lw.value.found) "CONTROL: the 80 lines of the long chat are drawn"
    function Show-Place { param($r) if ($r.ok) { return (ConvertTo-Json $r.value -Compress -Depth 4) } else { return $r.reason } }
    # THE CHAT OPENS AT ITS NEWEST MESSAGE, whatever window it inherits from the other tab.
    foreach ($from in @("top", "middle")) {
        $op = Invoke-Browser @{ cmd = "chatOpen"; from = $from }
        Check ($op.ok -and $op.value.items -ge 80 -and $op.value.dist -le 1 -and $op.value.lastText.StartsWith("long chat line 80") -and $op.value.lastBottom -le ($op.value.composeTop + 0.5) -and $op.value.lastBottom -gt 0 -and -not $op.value.jumpShown) ("opened from the questions with the window at the " + $from + " of the page (" + $(if ($op.ok) { $op.value.inherited } else { "?" }) + " px), the chat opens at its newest message, clear of the composer, with no Jump to latest (" + (Show-Place $op) + ")")
    }
    # THE STICK THRESHOLD: 30 px up is still the bottom; 300 px up is away, and the button shows.
    $near = Invoke-Browser @{ cmd = "chatScrollTo"; dist = 30 }
    Check ($near.ok -and $near.value.dist -ge 25 -and -not $near.value.jumpShown) ("30 px above the bottom counts as the bottom: no button (" + (Show-Place $near) + ")")
    $up = Invoke-Browser @{ cmd = "chatScrollTo"; dist = 1500 }
    Check ($up.ok -and $up.value.jumpShown -and $up.value.jumpText -ceq "Jump to latest" -and $up.value.jumpTag -ceq "BUTTON" -and $up.value.jumpType -ceq "button") ("scrolled up, a real button says Jump to latest (" + (Show-Place $up) + ")")
    Check ($up.ok -and $up.value.jumpH -ge 44 -and $up.value.jumpBottom -le ($up.value.textTop + 0.5) -and $up.value.jumpTop -ge ($up.value.composeTop - 0.5) -and $up.value.jumpRight -le 412 -and $up.value.jumpLeft -ge 0) ("at phone size it is at least 44 px tall, inside the composer's own band above the field: it covers neither the field nor a message (" + (Show-Place $up) + ")")
    # A REFRESH WHILE HE READS BACK KEEPS HIS PLACE.
    $rf = Invoke-Browser @{ cmd = "chatRefresh" }
    Check ($up.ok -and $rf.ok -and $rf.value.firstKey -ceq $up.value.firstKey -and [math]::Abs($rf.value.firstTop - $up.value.firstTop) -le 2 -and [math]::Abs($rf.value.dist - $up.value.dist) -le 2 -and $rf.value.jumpShown -and $rf.value.news -ceq "") ("a refresh while he is scrolled up keeps his place - the same message where it stood - and says nothing (" + (Show-Place $rf) + ")")
    # NEW LINES WHILE HE READS BACK: his place is kept, and the button and the live region say how many.
    Add-HordeTestChatTurns -Thrall $thrall -Turns @(@{ role = "assistant"; text = "fresh line one" }, @{ role = "assistant"; text = "fresh line two" })
    $null = Invoke-Run -Turns 2
    $fw = Invoke-Browser @{ cmd = "chatWait"; text = "fresh line two" }
    Start-Sleep -Milliseconds 500
    $nw = Invoke-Browser @{ cmd = "chatPlace" }
    Check ($fw.ok -and $fw.value.found -and $nw.ok -and $nw.value.firstKey -ceq $up.value.firstKey -and [math]::Abs($nw.value.firstTop - $up.value.firstTop) -le 2) ("two lines arriving while he is scrolled up do not move him (" + (Show-Place $nw) + ")")
    Check ($nw.ok -and $nw.value.jumpShown -and $nw.value.jumpText -ceq "Jump to latest (2 new)" -and $nw.value.news -ceq "2 new messages below. Jump to latest to read them." -and $nw.value.newsLive -ceq "polite" -and -not $nw.value.newsHidden) ("the button says Jump to latest (2 new), and a polite live region says it once (" + (Show-Place $nw) + ")")
    $rf2 = Invoke-Browser @{ cmd = "chatRefresh" }
    Check ($rf2.ok -and $rf2.value.jumpText -ceq "Jump to latest (2 new)" -and $rf2.value.firstKey -ceq $up.value.firstKey) "a refresh after them keeps the count and his place"
    # ONE TAP: the newest message.
    $jt = Invoke-Browser @{ cmd = "chatJumpTouch" }
    Check ($jt.ok -and $jt.value.dist -le 1 -and $jt.value.lastText -ceq "fresh line two" -and $jt.value.lastBottom -le ($jt.value.composeTop + 0.5) -and -not $jt.value.jumpShown -and $jt.value.news -ceq "") ("a touch on Jump to latest goes to the newest message, and the button goes (" + (Show-Place $jt) + ")")
    # BACK TO THE APP, after reading back: the chat opens at its newest message again.
    $null = Invoke-Browser @{ cmd = "chatScrollTo"; to = "top" }
    $null = Invoke-Browser @{ cmd = "hide"; ms = 200 }
    $null = Invoke-Browser @{ cmd = "show" }
    Start-Sleep -Milliseconds 1500
    $rt = Invoke-Browser @{ cmd = "chatPlace" }
    Check ($rt.ok -and $rt.value.items -ge 80 -and $rt.value.dist -le 1 -and $rt.value.lastText -ceq "fresh line two" -and -not $rt.value.jumpShown) ("back to the app, the chat opens at its newest message (" + (Show-Place $rt) + ")")
    # THE KEYBOARD: in the Tab order with a visible ring; Space and Enter each jump.
    foreach ($key in @("Space", "Enter")) {
        $null = Invoke-Browser @{ cmd = "chatScrollTo"; dist = 1500 }
        $kj = Invoke-Browser @{ cmd = "chatJumpKey"; key = $key }
        Check ($kj.ok -and $kj.value.focused.focus -ceq "chatJump" -and $kj.value.focused.focusVisible -and $kj.value.focused.outline -match '\Asolid [1-9]') ("Shift+Tab from the composer reaches Jump to latest, with a visible focus ring (" + $(if ($kj.ok) { ConvertTo-Json $kj.value.focused -Compress } else { $kj.reason }) + ")")
        Check ($kj.ok -and $kj.value.after.dist -le 1 -and -not $kj.value.after.jumpShown -and $kj.value.after.focus -ceq "chatText") ($key + " on it goes to the newest message, and the focus goes on to the composer (" + $(if ($kj.ok) { ConvertTo-Json $kj.value.after -Compress } else { $kj.reason }) + ")")
    }
    # HIS OWN LINE, SENT WHILE SCROLLED UP, TAKES HIM TO THE BOTTOM.
    $null = Invoke-Browser @{ cmd = "chatScrollTo"; dist = 1500 }
    $own = Invoke-Browser @{ cmd = "chatSend"; text = "Back down to the bottom."; via = "enter"; mailbox = $mailbox }
    Start-Sleep -Milliseconds 500
    $od = Invoke-Browser @{ cmd = "chatPlace" }
    Check ($own.ok -and $own.value.put -and $od.ok -and $od.value.dist -le 1 -and $od.value.lastText -ceq "Back down to the bottom." -and -not $od.value.jumpShown) ("his own line sent while scrolled up takes him to the bottom, where it stands (" + (Show-Place $od) + ")")
    $ct = Invoke-Browser @{ cmd = "chatContrast" }
    Check ($ct.ok -and $ct.value.light.ratio -ge 4.5 -and $ct.value.dark.ratio -ge 4.5) ("Jump to latest's words stand out from its face by at least 4.5 to 1, light and dark (" + $(if ($ct.ok) { ConvertTo-Json $ct.value -Compress } else { $ct.reason }) + ")")
    Write-Host "--- 10c. a photo from the Photo button: shrunk by Chrome, no prompt under the unlocked session, whole on the PC, one line to the Thrall ---" -ForegroundColor Cyan
    # A real picture, 3000 by 2000, drawn here and saved as a JPEG with a made-up camera block (APP1 Exif
    # holding a "GPS" marker) put in after its first two bytes, as a phone camera's would be.
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap 3000, 2000
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $rand = New-Object System.Random 5
    for ($k = 0; $k -lt 400; $k++) { $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($rand.Next(256), $rand.Next(256), $rand.Next(256))); $gfx.FillEllipse($brush, $rand.Next(3000), $rand.Next(2000), 40 + $rand.Next(400), 40 + $rand.Next(400)); $brush.Dispose() }
    $gfx.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Jpeg); $bmp.Dispose()
    $plain = $ms.ToArray(); $ms.Dispose()
    $exifBody = [System.Text.Encoding]::ASCII.GetBytes("Exif`0`0GPSLAT-SECRET-PLACE-31.7767N")
    $app1 = [byte[]](@(0xFF, 0xE1, 0, ($exifBody.Length + 2)) + $exifBody)
    $camera = [byte[]](@($plain[0], $plain[1]) + $app1 + $plain[2..($plain.Length - 1)])
    $photoPath = Join-Path $work "camera.jpg"
    [System.IO.File]::WriteAllBytes($photoPath, $camera)
    Check ([System.Text.Encoding]::ASCII.GetString($camera).Contains("GPSLAT-SECRET")) ("CONTROL: the picture picked carries a camera block with a location marker (" + $camera.Length + " bytes)")
    # Sent while he reads back: HIS OWN PHOTO, SENT, takes him to the bottom, as his own line does.
    $null = Invoke-Browser @{ cmd = "chatScrollTo"; dist = 1500 }
    $pp = Invoke-Browser @{ cmd = "chatPhoto"; path = $photoPath; mailbox = $mailbox; parts = 2 }
    $pd = Invoke-Browser @{ cmd = "chatPlace" }
    Check ($pp.ok -and $pd.ok -and $pd.value.dist -le 1 -and -not $pd.value.jumpShown) ("his own photo, sent while scrolled up, takes him to the bottom (" + $(if ($pd.ok) { ConvertTo-Json $pd.value -Compress -Depth 4 } else { $pd.reason }) + ")")
    Check ($pp.ok -and $pp.value.chooser) ("a touch on Photo opens the phone's picker (" + $(if ($pp.ok) { ConvertTo-Json $pp.value -Compress } else { $pp.reason }) + ")")
    Check ($pp.ok -and $pp.value.prompts -eq 0 -and $pp.value.put -ge 2) ("under the unlocked session this section's unlock opened (the PC keeps sessions), the photo asks for no passkey, as a line does, and its manifest and parts are put; section 14 counts the prompts from a lock (" + $(if ($pp.ok) { "" + $pp.value.prompts + " signature(s), " + $pp.value.put + " put(s)" } else { $pp.reason }) + ")")
    Check ($pp.ok -and $pp.value.thumbs -eq 1) "the chat shows the photo sent as a small picture"
    $run = Invoke-Run -Turns 2
    $landed = @(Get-ChildItem -LiteralPath (Join-Path $hh "inbox\photos") -File -ErrorAction SilentlyContinue)
    $bytesIn = $(if ($landed.Count -eq 1) { [System.IO.File]::ReadAllBytes($landed[0].FullName) } else { [byte[]]@() })
    Check ($landed.Count -eq 1 -and $bytesIn.Length -le 1000000 -and $bytesIn[0] -eq 0xFF -and $bytesIn[1] -eq 0xD8 -and $landed[0].Extension -ceq ".jpg") ("a real run writes one JPEG within 1,000,000 bytes to the PC's inbox (" + $(if ($landed.Count) { $landed[0].Name + ", " + $bytesIn.Length + " bytes" } else { "none" }) + "; exit " + $run.code + ")")
    $asText = [System.Text.Encoding]::ASCII.GetString($bytesIn)
    Check ($landed.Count -eq 1 -and -not $asText.Contains("GPSLAT-SECRET") -and -not $asText.Contains("Exif")) "the camera block, and the location in it, is not in what reached the PC"
    $dims = $null
    if ($landed.Count -eq 1) { $im = [System.Drawing.Image]::FromFile($landed[0].FullName); $dims = @($im.Width, $im.Height); $im.Dispose() }
    Check ($null -ne $dims -and [math]::Max($dims[0], $dims[1]) -eq 1600 -and $dims[1] -eq [math]::Round(1600 * 2000 / 3000)) ("a photo is shrunk to 1600 px on its longest side, its shape kept (" + $(if ($null -ne $dims) { "" + $dims[0] + " x " + $dims[1] } else { "none" }) + ")")
    $photoPosts = @(Get-HordeTestFleetPosts -Folder $fake | Where-Object { $_.body.StartsWith("FOUNDER PHOTO from the phone") })
    Check ($photoPosts.Count -eq 1 -and $landed.Count -eq 1 -and $photoPosts[0].body.Contains($landed[0].FullName)) ("one line to the Thrall names the file's path (" + $photoPosts.Count + ")")
    $w3 = Invoke-Browser @{ cmd = "chatWait"; text = "Photo saved on the PC, and the Thrall told." }
    Check ($w3.ok -and $w3.value.found) "the photo's receipt shows under it, in the app's own words"
    $fake1 = Join-Path $work "evil.jpg"
    [System.IO.File]::WriteAllText($fake1, "<!DOCTYPE html><html><script>alert(1)</script></html>", $utf8)
    $np = Invoke-Browser @{ cmd = "chatPhoto"; path = $fake1; mailbox = $mailbox; expectNone = $true }
    Check ($np.ok -and $np.value.put -eq 0 -and $np.value.prompts -eq 0 -and $np.value.notice.Contains("not a picture")) ("an HTML page called .jpg is refused on the phone by its first bytes, in a plain line, with no passkey asked and nothing sent (" + $(if ($np.ok) { $np.value.notice } else { $np.reason }) + ")")
    # A PHOTO ARRIVING WHILE HE READS BACK (chat-scroll.js; the founder, 2026-10-15): one that comes into the
    # chat without his touch here - as one sent from another window of the app - neither yanks him down
    # nor goes uncounted: it is a new message for Jump to latest.
    $sbmp = New-Object System.Drawing.Bitmap 64, 48
    $sgfx = [System.Drawing.Graphics]::FromImage($sbmp); $sgfx.Clear([System.Drawing.Color]::SteelBlue); $sgfx.Dispose()
    $smallPath = Join-Path $work "small.jpg"
    $sbmp.Save($smallPath, [System.Drawing.Imaging.ImageFormat]::Jpeg); $sbmp.Dispose()
    $up2 = Invoke-Browser @{ cmd = "chatScrollTo"; dist = 1500 }
    $pb = Invoke-Browser @{ cmd = "chatPhotoBehind"; path = $smallPath; mailbox = $mailbox; id = ("b" * 32) }
    $pbSaid = $(if ($pb.ok) { ConvertTo-Json $pb.value -Compress -Depth 4 } else { $pb.reason })
    Check ($up2.ok -and $up2.value.jumpShown -and $pb.ok -and $pb.value.sent.ok -and $pb.value.put -ge 2 -and $pb.value.place.firstKey -ceq $up2.value.firstKey -and [math]::Abs($pb.value.place.firstTop - $up2.value.firstTop) -le 2 -and $pb.value.place.dist -gt 48) ("A PHOTO ARRIVING while he is scrolled up does not move him: the same message stands where it stood (" + $pbSaid + ")")
    Check ($pb.ok -and $pb.value.place.jumpShown -and $pb.value.place.jumpText -ceq "Jump to latest (1 new)" -and $pb.value.place.news -ceq "1 new message below. Jump to latest to read it.") ("and it counts as a new message: Jump to latest (1 new), said once in the live region (" + $pbSaid + ")")
    $run = Invoke-Run -Turns 2
    $landed2 = @(Get-ChildItem -LiteralPath (Join-Path $hh "inbox\photos") -File -ErrorAction SilentlyContinue)
    Check ($landed2.Count -eq 2) ("and the PC takes it too (" + $landed2.Count + " file(s) in its inbox; exit " + $run.code + ")")
    $null = Invoke-Browser @{ cmd = "chatJumpTouch" }
    # THE HOUR (the founder's choice, 2026-10-16): a photo the PC has not taken waits for it, and says so;
    # past the hour the manifest names it says plainly it was not delivered, and Send again sends it again.
    # The page's clock stands 61 minutes back while it is sent, so by the real clock its hour has passed:
    # nothing is waited, and the PC, run only afterwards, sees a manifest whose window ended.
    $postsBeforeHour = @(Get-HordeTestFleetPosts -Folder $fake | Where-Object { $_.body.StartsWith("FOUNDER PHOTO from the phone") }).Count
    $null = Invoke-Browser @{ cmd = "clock"; ms = -3660000 }
    $late = Invoke-Browser @{ cmd = "chatPhoto"; path = $smallPath; mailbox = $mailbox; parts = 2 }
    $wt1 = Invoke-Browser @{ cmd = "chatWait"; text = "Sent: waiting for your PC to take it (it waits up to an hour)."; timeoutMs = 10000 }
    $sa0 = Invoke-Browser @{ cmd = "chatSendAgain"; mailbox = $mailbox }
    $null = Invoke-Browser @{ cmd = "clock"; ms = 0 }
    Check ($late.ok -and $late.value.put -ge 2 -and $wt1.ok -and $wt1.value.found) ("PC OFF: a photo sent and not yet taken says it waits for the PC, up to an hour (" + $(if ($late.ok) { "" + $late.value.put + " put(s)" } else { $late.reason }) + ")")
    $null = Invoke-Browser @{ cmd = "chatRefresh" }
    $nd = Invoke-Browser @{ cmd = "chatWait"; text = "No receipt yet: your PC has not said it took the photo within an hour. If it is still off, Send again."; timeoutMs = 10000 }
    Check ($nd.ok -and $nd.value.found) "PAST THE HOUR with no word from the PC, it says plainly it was not delivered"
    $sa = Invoke-Browser @{ cmd = "chatSendAgain"; mailbox = $mailbox }
    Check ($sa0.ok -and $sa0.value.shown -eq 0 -and $sa.ok -and $sa.value.shown -eq 1 -and $sa.value.put -ge 2 -and $sa.value.left -eq 0) ("and offers Send again - not while it still waits - which sends it again, and is then offered no more (" + $(if ($sa.ok) { ConvertTo-Json $sa.value -Compress } else { $sa.reason }) + "; while waiting: " + $(if ($sa0.ok) { $sa0.value.shown } else { $sa0.reason }) + ")")
    $run = Invoke-Run -Turns 2
    $landed3 = @(Get-ChildItem -LiteralPath (Join-Path $hh "inbox\photos") -File -ErrorAction SilentlyContinue)
    $postsAfterHour = @(Get-HordeTestFleetPosts -Folder $fake | Where-Object { $_.body.StartsWith("FOUNDER PHOTO from the phone") }).Count
    Check ($landed3.Count -eq 3 -and $postsAfterHour -eq $postsBeforeHour + 1) ("the PC takes the photo sent again and not the late one: one more file and one more line to the Thrall (" + $landed3.Count + " file(s), " + $postsBeforeHour + " -> " + $postsAfterHour + " line(s); exit " + $run.code + ")")
    $null = Save-Shot "phone-chat-photo"
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
    Check ($pw.ok -and $pw.value.cardsWhy -ceq "No cards from your PC yet.") ("WITH NO CARDS the tab falls back to the whole log under one plain line saying why (" + $(if ($pw.ok) { $pw.value.cardsWhy } else { $pw.reason }) + ")")
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
    # Half a screen, not five halves: folded to one line (section 12b) an entry is about 49 px, so 13 stand on
    # the first screen and five halves read the whole log, leaving nothing for Jump to newest to jump past
    # (measured 2026-10-14: 28 new, then 0). The rule of what is seen is unchanged; the entries are shorter.
    $ro = Invoke-Browser @{ cmd = "progressReadOn"; screens = 1 }
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
    # AT ONCE, AND BY THE LOCK ITSELF. The check above is also met by the redraw that follows the
    # bridge's answer, so it could not tell whether the lock emptied the log or only the answer did -
    # and a lock whose answer never comes must still leave no word on the page.
    Check ($lk.ok -and $lk.value.logBefore -gt 0) ("CONTROL: the log held entries when the lock was touched (" + $(if ($lk.ok) { $lk.value.logBefore } else { $lk.reason }) + ")")
    Check ($lk.ok -and $lk.value.logAtOnce -eq 0) ("and it is gone in the same moment as the touch, before the bridge has answered (" + $(if ($lk.ok) { "" + $lk.value.logAtOnce + " left" } else { $lk.reason }) + ")")
    $null = Invoke-Browser @{ cmd = "unlock" }

    Write-Host ""
    Write-Host "--- 12. the cards: a real cards envelope is drawn, and a touch opens the Thrall's and a lane's stream ---" -ForegroundColor Cyan
    # The founder's phone heard nothing new from 02:36 on 2026-10-14; the diagnosis found the cards
    # themselves work, and this keeps it so: the envelope is the real `horde relay run`'s, from two lane
    # status files under the suite's home and the map of areas to lanes.
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay-cards.json"), '{"schemaVersion": 1, "settings": {"sendIntervalMs": 0, "machineName": "office-pc"}}', $utf8)
    # A card's lane is its Orc's letter (the status file's orc line); the map of areas names lanes so.
    $laneWork = [ordered]@{ "F" = "formfill"; "V" = "voice" }
    foreach ($orc in @($laneWork.Keys)) {
        $laneDir = Join-Path $hh ("progress\lanes\" + $laneWork[$orc])
        [void][System.IO.Directory]::CreateDirectory($laneDir)
        [System.IO.File]::WriteAllText((Join-Path $laneDir "status.txt"), ("horde-orc-status 1`norc: " + $orc + "`nlane: " + $laneWork[$orc] + "`ndoing: working on " + $laneWork[$orc] + "`nfinished: the first part`nblocked: no`nwaiting on: nothing`n"), $utf8)
    }
    [System.IO.File]::WriteAllText((Join-Path $hh "progress\area-lanes.json"), '{"v":1,"areas":{"Form fill":"F","Ask Orah voice":"V"}}', $utf8)
    $run = Invoke-Run -Turns 2
    Check ($run.code -eq 0) ("CONTROL: a run with two lanes written sends its cards (exit " + $run.code + ")")
    $null = Invoke-Browser @{ cmd = "progressTab" }
    $cw = Invoke-Browser @{ cmd = "cardsWait"; count = 3 }
    $drawn = @(); if ($cw.ok) { $drawn = @($cw.value.cards) }
    $laneCards = @($drawn | Where-Object { -not $_.thrall } | ForEach-Object { $_.lane } | Sort-Object)
    Check ($cw.ok -and $cw.value.found -and $cw.value.cardsPage -and -not $cw.value.streamPage -and $drawn.Count -eq 3 -and $drawn[0].thrall -and ($laneCards -join ",") -ceq "F,V") ("the cards are drawn live, the Thrall's first and one per lane (" + $(if ($cw.ok) { ($drawn | ForEach-Object { $_.lane }) -join ", " } else { $cw.reason }) + ")")
    Check ($cw.ok -and @($drawn | Where-Object { -not $_.thrall -and $laneWork.Contains($_.lane) -and $_.text.Contains("working on " + $laneWork[$_.lane]) }).Count -eq 2) ("each lane's card says what its status file says it is doing (" + $(if ($cw.ok) { ($drawn | ForEach-Object { $_.text }) -join " | " } else { "" }) + ")")
    # The whole log: section 11's entries and what was written after them, one a line.
    $whole = @(Get-Content -LiteralPath $logFile | Where-Object { $_.Trim() }).Count
    $th = Invoke-Browser @{ cmd = "cardTouch"; thrall = $true }
    Check ($th.ok -and $th.value.streamPage -and -not $th.value.cardsPage -and $th.value.title -ceq "Thrall - the whole fleet, office-pc" -and $th.value.items -eq $whole -and $whole -ge 41) ("a touch on the Thrall's card opens the whole log (" + $(if ($th.ok) { $th.value.title + ": " + $th.value.items + " of " + $whole + " entries" } else { $th.reason }) + ")")
    $bk = Invoke-Browser @{ cmd = "streamBack" }
    Check ($bk.ok -and $bk.value.cardsPage -and @($bk.value.cards).Count -eq 3) "and Back goes back to the cards"
    $ff = Invoke-Browser @{ cmd = "cardTouch"; lane = "F" }
    $ffTexts = @(); if ($ff.ok) { $ffTexts = @($ff.value.texts) }
    Check ($ff.ok -and $ff.value.streamPage -and $ff.value.title -ceq "F, office-pc" -and $ff.value.items -eq 21 -and @($ffTexts | Where-Object { -not $_.Contains("Form fill") }).Count -eq 0) ("a touch on a lane's card opens that lane's stream: only the entries of its area (" + $(if ($ff.ok) { $ff.value.title + ": " + $ff.value.items + " entries" } else { $ff.reason }) + ")")
    $null = Save-Shot "cards-lane-stream"
    $null = Invoke-Browser @{ cmd = "streamBack" }

    Write-Host ""
    Write-Host "--- 12b. a stream's entries start folded to one line, title and time; a tap opens one ---" -ForegroundColor Cyan
    # The founder, 2026-10-14: "I want the entries in the progress cards to initialize collapsed, showing the
    # title and the datetime - only expanding if i click on them." Every check of what is shown reads what can
    # be SEEN (entriesState: checkVisibility and a box of some height): a folded entry still holds its text
    # and chips in the page, so a check of the DOM alone would pass with everything showing.
    function Get-PwaEntry($state, $id) { $hit = @(@($state) | Where-Object { $null -ne $_ -and $_.id -ceq $id }); if ($hit.Count -gt 0) { $hit[0] } else { $null } }
    function Get-PwaEntriesWords($state) { (@($state) | ForEach-Object { $_.id.Substring($_.id.Length - 2) + ":" + $(if ($_.folded) { "folded" } else { "open" }) + "/" + $_.expanded + "/" + $_.height }) -join " " }
    $null = Invoke-Browser @{ cmd = "cardTouch"; lane = "F" }
    $es = Invoke-Browser @{ cmd = "entriesState" }
    $ents = @(); if ($es.ok) { $ents = @($es.value) }
    Check ($es.ok -and $ents.Count -eq 21 -and @($ents | Where-Object { -not $_.folded -or $_.expanded -cne "false" -or $_.role -cne "button" -or -not $_.focusable }).Count -eq 0) ("the lane's stream opens with every entry folded, its one line a control saying aria-expanded false (" + $(if ($es.ok) { Get-PwaEntriesWords $ents } else { $es.reason }) + ")")
    Check ($ents.Count -eq 21 -and @($ents | Where-Object { -not $_.titleSeen -or -not $_.whenSeen -or $_.title -ceq "" -or $_.when -cne $_.stamp -or $_.when -cnotmatch '\A[0-9]{1,2} [A-Z][a-z]{2} [0-9]{2}:[0-9]{2}\z' }).Count -eq 0) ("each folded line shows its title and the same day and time its head's stamp shows (" + $(if ($ents.Count) { $ents[0].title + " | " + $ents[0].when } else { "" }) + ")")
    Check ($ents.Count -eq 21 -and @($ents | Where-Object { $_.textSeen -or $_.headSeen }).Count -eq 0) "and nothing else can be seen: no text, no chips"
    $heights = @($ents | ForEach-Object { $_.height } | Sort-Object -Unique)
    Check ($ents.Count -eq 21 -and $heights.Count -eq 1 -and $heights[0] -gt 0 -and $heights[0] -le 60) ("every folded entry is one line, all of one height (" + ($heights -join ", ") + " px)")
    # One entry, touched part by part; its neighbour must not move.
    $aId = $(if ($ents.Count -ge 4) { $ents[2].id } else { "" })
    $tw = Invoke-Browser @{ cmd = "entryTouch"; id = $aId; part = "when" }
    $a = $(if ($tw.ok) { Get-PwaEntry $tw.value $aId })
    Check ($null -ne $a -and -not $a.folded -and $a.expanded -ceq "true" -and $a.textSeen -and $a.headSeen) ("CONTROL: the same check of what can be seen finds the text and chips of an entry opened by a touch on its folded line's time (" + $(if ($tw.ok) { Get-PwaEntriesWords @($a) } else { $tw.reason }) + ")")
    Check ($null -ne $a -and -not $a.whenSeen -and $a.title -ceq $ents[2].title) "open, it is drawn as before: its head's stamp stands for the time, the line's own time is gone"
    Check ($tw.ok -and @($tw.value | Where-Object { $_.id -cne $aId -and (-not $_.folded -or $_.textSeen) }).Count -eq 0) ("and every other entry stays folded (" + $(if ($tw.ok) { Get-PwaEntriesWords $tw.value } else { "" }) + ")")
    $stampBefore = $(if ($null -ne $a) { $a.stamp } else { "" })
    $ts = Invoke-Browser @{ cmd = "entryTouch"; id = $aId; part = "stamp" }
    $a = $(if ($ts.ok) { Get-PwaEntry $ts.value $aId })
    Check ($null -ne $a -and $a.stamp -cne $stampBefore -and $a.stamp.Length -gt $stampBefore.Length) ("CONTROL: the touch on the open entry's stamp landed: it shows the exact time (" + $(if ($null -ne $a) { $a.stamp } else { $ts.reason }) + ")")
    Check ($null -ne $a -and -not $a.folded -and $a.textSeen) "and a button in an open entry does its own thing only: the entry stays open"
    $null = Invoke-Browser @{ cmd = "entryTouch"; id = $aId; part = "stamp" }
    $tt = Invoke-Browser @{ cmd = "entryTouch"; id = $aId; part = "text" }
    $a = $(if ($tt.ok) { Get-PwaEntry $tt.value $aId })
    Check ($null -ne $a -and -not $a.folded -and $a.expanded -ceq "true" -and $a.textSeen) "a touch on an open entry's text leaves it open"
    $th2 = Invoke-Browser @{ cmd = "entryTouch"; id = $aId; part = "head" }
    $a = $(if ($th2.ok) { Get-PwaEntry $th2.value $aId })
    Check ($null -ne $a -and $a.folded -and $a.expanded -ceq "false" -and -not $a.textSeen -and $a.titleSeen -and $a.whenSeen) "a touch on its head folds it again to its one line"
    $tl = Invoke-Browser @{ cmd = "entryTouch"; id = $aId; part = "line" }
    $a = $(if ($tl.ok) { Get-PwaEntry $tl.value $aId })
    Check ($null -ne $a -and -not $a.folded -and $a.expanded -ceq "true" -and $a.textSeen) "a touch on a folded entry's title opens it"
    $tl = Invoke-Browser @{ cmd = "entryTouch"; id = $aId; part = "line" }
    $a = $(if ($tl.ok) { Get-PwaEntry $tl.value $aId })
    Check ($null -ne $a -and $a.folded -and $a.expanded -ceq "false" -and -not $a.textSeen) "and a touch on an open entry's title folds it"
    # A NEW ENTRY REBUILDS THE WHOLE LOG (drawProgress): what he opened must survive that.
    $null = Invoke-Browser @{ cmd = "entryTouch"; id = $aId; part = "line" }
    $tagged = Invoke-Browser @{ cmd = "entriesTag" }
    # The longest title an entry may have: a progress title holds 100 characters (channels/progress/Channel.ps1,
    # relay/js/protocol.js PROGRESS_LIMITS), and a longer one is refused before it reaches the phone (a first
    # draft of this check wrote 125 and the entry never arrived).
    $longTitle = "Folded line test: a title of the most a progress entry may hold, far wider than one phone line, okay"
    Check ($longTitle.Length -eq 100) ("CONTROL: the long title is exactly the most a title may hold (" + $longTitle.Length + " characters)")
    [System.IO.File]::AppendAllText($logFile, ('{"v":1,"id":"20261014T080000Z-78","ts":"2026-10-14T08:00:00Z","kind":"progress","area":"Form fill","title":"' + $longTitle + '","text":"Happened: written while an entry was open."}' + "`n"), $utf8)
    $run = Invoke-Run -Turns 1
    $nwe = Invoke-Browser @{ cmd = "progressWait"; text = "Folded line test" }
    $er = Invoke-Browser @{ cmd = "entriesState" }
    $after = @(); if ($er.ok) { $after = @($er.value) }
    $newE = Get-PwaEntry $after "20261014T080000Z-78"
    $a = Get-PwaEntry $after $aId
    Check ($run.code -eq 0 -and $nwe.ok -and $nwe.value.found -and $tagged.ok -and $tagged.value -eq 21 -and $after.Count -eq 22 -and $null -ne $newE -and @($after | Where-Object { $_.tagged }).Count -eq 0) ("CONTROL: the new entry arrived and the log was drawn anew: not one entry is a node drawn before it (exit " + $run.code + "; found " + $(if ($nwe.ok) { $nwe.value.found } else { $nwe.reason }) + "; tagged " + $(if ($tagged.ok) { $tagged.value } else { $tagged.reason }) + "; " + $after.Count + " entries)")
    Check ($null -ne $a -and -not $a.folded -and $a.expanded -ceq "true" -and $a.textSeen) ("an entry opened before a new entry arrived is still open after the redraw (" + $(if ($er.ok) { Get-PwaEntriesWords $after } else { $er.reason }) + ")")
    Check ($after.Count -eq 22 -and @($after | Where-Object { $_.id -cne $aId -and (-not $_.folded -or $_.textSeen) }).Count -eq 0) "and the rest, the new one among them, are folded"
    $shortCut = @($after | Where-Object { $_.folded -and $_.id -cne "20261014T080000Z-78" -and $_.titleCut })
    Check ($after.Count -eq 22 -and $shortCut.Count -eq 0) "CONTROL: a short title on a folded line is not cut"
    Check ($null -ne $newE -and $newE.titleCut -and $newE.title -ceq $longTitle -and $newE.whenSeen -and $newE.height -eq $heights[0]) ("a long title is cut at the edge of its one line, its time still shown, and the entry is the height of every other folded one (" + $(if ($null -ne $newE) { "" + $newE.height + " px" } else { "not drawn" }) + ")")
    $null = Save-Shot "stream-folded"
    # LEAVING THE STREAM FORGETS: Back to the cards and in again starts folded.
    $null = Invoke-Browser @{ cmd = "streamBack" }
    $null = Invoke-Browser @{ cmd = "cardTouch"; lane = "F" }
    $re = Invoke-Browser @{ cmd = "entriesState" }
    Check ($re.ok -and @($re.value).Count -eq 22 -and @($re.value | Where-Object { -not $_.folded -or $_.expanded -cne "false" -or $_.textSeen }).Count -eq 0) ("leaving the stream and opening it again starts every entry folded, the one open before as well (" + $(if ($re.ok) { Get-PwaEntriesWords $re.value } else { $re.reason }) + ")")
    # THE KEYS: Enter and Space on the focused line, as from a keyboard.
    $k = Invoke-Browser @{ cmd = "entryKey"; id = $aId; key = "Enter" }
    $a = $(if ($k.ok) { Get-PwaEntry $k.value.entries $aId })
    Check ($null -ne $a -and -not $a.folded -and $a.expanded -ceq "true" -and $a.textSeen) "Enter on a folded line opens it, and aria-expanded says true"
    $k = Invoke-Browser @{ cmd = "entryKey"; id = $aId; key = "Enter" }
    $a = $(if ($k.ok) { Get-PwaEntry $k.value.entries $aId })
    Check ($null -ne $a -and $a.folded -and $a.expanded -ceq "false" -and -not $a.textSeen) "Enter again folds it, and aria-expanded says false"
    $k = Invoke-Browser @{ cmd = "entryKey"; id = $aId; key = " " }
    $a = $(if ($k.ok) { Get-PwaEntry $k.value.entries $aId })
    Check ($null -ne $a -and -not $a.folded -and $a.expanded -ceq "true" -and $a.textSeen) "Space opens it as well"
    $k = Invoke-Browser @{ cmd = "entryKey"; id = $aId; key = " " }
    $a = $(if ($k.ok) { Get-PwaEntry $k.value.entries $aId })
    Check ($null -ne $a -and $a.folded -and $a.expanded -ceq "false") "and folds it"
    $null = Invoke-Browser @{ cmd = "streamBack" }

    Write-Host ""
    Write-Host "--- 13. a relay that refuses every read: the page must say so ---" -ForegroundColor Cyan
    $null = Invoke-Browser @{ cmd = "cardTouch"; thrall = $true }
    $probe = Invoke-Browser @{ cmd = "noticeProbe"; text = "Probe: a line in the notice" }
    Check ($probe.ok -and $probe.value.found) "CONTROL: the check below can see a line in the notice: words put there as the page puts them are found"
    $null = Invoke-Browser @{ cmd = "readFail"; reason = "the relay answered the read with 401: sign in again" }
    [System.IO.File]::AppendAllText($logFile, ('{"v":1,"id":"20261014T070000Z-77","ts":"2026-10-14T07:00:00Z","kind":"note","area":"Form fill","title":"Written while the relay refused","text":"Means: the phone must not draw this until it can read."}' + "`n"), $utf8)
    $run = Invoke-Run -Turns 1
    $nw = Invoke-Browser @{ cmd = "noticeWait"; text = "could not be read"; timeoutMs = 15000 }
    $during = Invoke-Browser @{ cmd = "cardsState" }
    Check ($run.code -eq 0 -and $during.ok -and $during.value.streamPage -and $during.value.items -ge 41 -and -not (@($during.value.texts) -join " ").Contains("Written while the relay refused")) ("CONTROL: while every read is refused, the entry the run sent is not drawn: the refusal is in force (exit " + $run.code + "; " + $(if ($during.ok) { "stream " + $during.value.streamPage + ", " + $during.value.items + " entries, title '" + $during.value.title + "'" } else { $during.reason }) + ")")
    # THE NOTICE FIX (it was PENDING): a failed read used to be said by the bridge and wiped by the next draw of
    # the list (app.js, render). Now the relay's line stays until a read comes back clean, and the read banner
    # (read-banner.js) says he must sign in again, with the time of the last read that worked.
    $readSaid = $nw.ok -and $nw.value.found
    Check ($readSaid -and $nw.value.notice -cmatch 'Not signed in to the relay - sign in again\. Last updated [0-9]{2}:[0-9]{2}\.') ("a relay refusing every read with 401 IS said on the page: the line stays, with the sign-in banner and the last-updated time (notice now '" + $(if ($nw.ok) { $nw.value.notice } else { $nw.reason }) + "')")
    $null = Invoke-Browser @{ cmd = "readFail"; reason = "" }
    $rw = Invoke-Browser @{ cmd = "progressWait"; text = "Written while the relay refused" }
    Check ($rw.ok -and $rw.value.found) ("once the relay is read again, the entry written meanwhile arrives with no reload (" + $(if ($rw.ok) { "" + $rw.value.items + " entries" } else { $rw.reason }) + ")")
    $null = Invoke-Browser @{ cmd = "streamBack" }
    $null = Invoke-Browser @{ cmd = "chatTab"; which = "decisions" }

    Write-Host ""
    Write-Host "--- 14. the unlocked session: one passkey prompt for an unlock and the answers after it ---" -ForegroundColor Cyan
    # WHAT THE BROWSER GIVES when the app is left, measured: the frozen lifecycle, then another tab in front.
    $vp = Invoke-Browser @{ cmd = "visibilityProbe" }
    $heard = $(if ($vp.ok) { @($vp.value.after.heard) -join ", " } else { $vp.reason })
    Write-Host ("  [INFO] what headless Chrome gives the page: with another tab in front its visibilityState is '" + $(if ($vp.ok) { $vp.value.during } else { "?" }) + "'; it heard: " + $heard + $(if ($vp.ok -and $vp.value.frozenRefused) { "; the frozen lifecycle state was refused: " + $vp.value.frozenRefused } else { "" }))
    $realAway = ($vp.ok -and $vp.value.during -ceq "hidden" -and $heard.Contains("visibilitychange:hidden") -and $heard.Contains("visibilitychange:visible"))
    Check ($vp.ok -and $vp.value.after.state -ceq "visible") ("MEASURED: what Chrome reports when the app is left is recorded, and the page is in front again after (" + $heard + ")")
    # THE PC'S IDLE LIMIT, its own setting (channels/Sessions.ps1, idleMinutes), at its least: one minute.
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay-sessions.json"), '{"schemaVersion": 1, "settings": {"idleMinutes": 1}}', $utf8)
    # Fresh questions: an answered one leaves his list (2026-10-12). The fourth is flagged needsPasskey.
    $sTitles = @("Should the session answer number one go?", "Should the session answer number two go?", "Should the session answer number three go?", "Deploy the relay to production right now?", "Answer this after the idle limit?", "Answer this after the app was away?", "Answer this after the page reloaded?")
    $sNums = @()
    for ($i = 0; $i -lt $sTitles.Count; $i++) {
        $req = @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = @{ title = $sTitles[$i]; kind = "yes-no"; whatItIs = "Section 14."; group = "voice"; askedBy = "orc-e" } }
        if ($i -eq 3) { $req["needsPasskey"] = $true }
        $qa = Invoke-HordeDecision -Operation "add" -Root $store -Request $req
        $sNums += $(if ($qa.state -ceq "known" -and $null -ne $qa.value.PSObject.Properties["number"]) { [int]$qa.value.number } else { Write-Host ("  [WHY] '" + $sTitles[$i] + "' was not added: " + (ConvertTo-Json $qa -Compress -Depth 4)); 0 })
    }
    Check (@($sNums | Where-Object { $_ -gt 0 }).Count -eq 7) "CONTROL: seven questions are asked for the session, one flagged needsPasskey"
    $landedBefore = @(Get-Said).Count
    Check ($landedBefore -ge 3) ("CONTROL: the answers of the sections above landed at the real PC (" + $landedBefore + " record(s))")
    $vouchKeys = @{}
    function Test-SessionEnvelope {
        # The PC's own reader and verifier on one envelope the phone sent: a vouch it carries is the founder
        # passkey's assertion over relay/Session.ps1's challenge; the session signature verifies under the
        # vouched key. "" when it holds, else what does not.
        param($Read)
        if (-not $Read.ok) { return ("not read: " + $Read.reason) }
        $s = $Read.value.sig
        if ($s.alg -cne "session") { return ("signed " + $s.alg) }
        if ($null -ne $s.vouch) {
            $snd = (Find-HordeRelayTrustedSenders -HordeHome $hh).value[$Read.value.header.from]
            $wa = Test-HordeRelayWebAuthnAssertion -Public $snd.public -AuthenticatorData $s.authenticatorData -ClientDataJson $s.clientDataJson -Signature $s.signature -Challenge (Get-HordeRelaySessionVouchChallenge -Text $s.vouch.text) -RpId $snd.rpId -Origins @($snd.origins) -RequireUserVerification $true
            if (-not ($wa.ok -and $wa.userVerified)) { return ("the vouch does not verify: " + $wa.reason) }
            $script:vouchKeys[$s.vouchId] = $s.vouch.sessionPublic
        }
        if (-not $script:vouchKeys.ContainsKey($s.vouchId)) { return "a vouchId no vouch was seen for" }
        $signed = Get-HordeRelaySessionSigningInput -VouchId $s.vouchId -Signed (Get-HordeRelaySigningInput -HeaderText $Read.value.headerText -RecipientsText $Read.value.recipientsText -CtText $Read.value.ctText)
        if (-not (Test-HordeRelayEs256Signature -Public $script:vouchKeys[$s.vouchId] -Bytes $signed -Signature $s.value -AllowHighS)) { return "the session signature does not verify" }
        return ""
    }
    function Get-Landed { param([string]$Text) return @(Get-Said | Where-Object { $_.data.text -ceq $Text }).Count }
    # THE REAL PC: a run sends the snapshot of the new questions, with this passkey's session status.
    $run = Invoke-Run -Turns 1
    $null = Invoke-Browser @{ cmd = "lock" }
    $c0 = (Invoke-Browser @{ cmd = "assertions" }).value
    $skip = Get-MachineCount
    $null = Invoke-Browser @{ cmd = "unlock" }
    $c1 = (Invoke-Browser @{ cmd = "assertions" }).value
    Check ($c1 -eq $c0 + 1) ("CONTROL: the counter sees every prompt - the unlock is one (" + $c0 + " -> " + $c1 + ")")
    $w = Invoke-Browser @{ cmd = "waitText"; text = $sTitles[6] }
    $ss = $null
    for ($i = 0; $i -lt 40; $i++) { $ss = Invoke-Browser @{ cmd = "sessions" }; if ($ss.ok -and @($ss.value.list).Count -ge 1 -and $ss.value.list[0].keeps -eq $true) { break }; Start-Sleep -Milliseconds 250 }
    Check ($run.code -eq 0 -and $w.ok -and $w.value.found -and $ss.ok -and $ss.value.list[0].keeps -eq $true -and $ss.value.list[0].idleMs -eq 60000) ("CONTROL: the real PC's snapshot is drawn, and it says the PC keeps sessions, with its own idle limit (" + $(if ($ss.ok) { ConvertTo-Json $ss.value.list -Compress } else { $ss.reason }) + ")")
    Check ($ss.ok -and $ss.value.list[0].open -and $ss.value.account -cmatch 'an unlocked session is open until [0-9]{2}:[0-9]{2}\.') ("THE ACCOUNT SCREEN SAYS a session is open, and until when (" + $(if ($ss.ok) { $ss.value.account } else { $ss.reason }) + ")")
    $a1 = Invoke-Browser @{ cmd = "answer"; text = "One, no prompt."; via = "enter"; mailbox = $mailbox; question = $sTitles[0] }
    $a2 = Invoke-Browser @{ cmd = "answer"; text = "Two, no prompt."; via = "enter"; mailbox = $mailbox; question = $sTitles[1] }
    $a3 = Invoke-Browser @{ cmd = "answer"; text = "Three, no prompt."; via = "touch"; mailbox = $mailbox; question = $sTitles[2] }
    $null = Invoke-Browser @{ cmd = "chatTab"; which = "chat" }
    $cl = Invoke-Browser @{ cmd = "chatSend"; text = "A line, no prompt."; via = "enter"; mailbox = $mailbox }
    # A PHOTO TOO (PR 285; SESSION_SIGNED names "chat photo"): its manifest is the one envelope that is
    # signed, by the session key; its parts are data items, signed by nobody (Photo.ps1, THE PARTS).
    $photoPostsBefore = @(Get-HordeTestFleetPosts -Folder $fake | Where-Object { $_.body.StartsWith("FOUNDER PHOTO from the phone") }).Count
    $sp = Invoke-Browser @{ cmd = "chatPhoto"; path = $photoPath; mailbox = $mailbox; parts = 2 }
    # Every part put before the envelopes are read: the count stops growing.
    $was = -1; for ($i = 0; $i -lt 40 -and $was -ne (Get-MachineCount); $i++) { $was = Get-MachineCount; Start-Sleep -Milliseconds 500 }
    $null = Invoke-Browser @{ cmd = "chatTab"; which = "decisions" }
    $c2 = (Invoke-Browser @{ cmd = "assertions" }).value
    Check ($a1.value.put -and $a2.value.put -and $a3.value.put -and $cl.value.put -and $sp.ok -and $sp.value.put -ge 2 -and $sp.value.prompts -eq 0 -and $c2 -eq $c1) ("ONE PROMPT IN ALL: the unlock, then three answers, a chat line and a photo, sent with no passkey prompt (" + ($c2 - $c0) + " assertion(s) since the lock; the photo " + $(if ($sp.ok) { "" + $sp.value.prompts + " prompt(s), " + $sp.value.put + " put(s)" } else { $sp.reason }) + ")")
    $sentAll = @(Get-MachineEnvelopes -Skip $skip)
    $sentS = @($sentAll | Where-Object { $_.ok })
    $dataN = $sentAll.Count - $sentS.Count
    $why = @($sentS | ForEach-Object { Test-SessionEnvelope $_ })
    $kinds = @($sentS | ForEach-Object { $_.value.header.channel + "/" + $_.value.header.kind })
    Check ($sentS.Count -eq 6 -and @($why | Where-Object { $_ -cne "" }).Count -eq 0 -and ($kinds -join ",") -ceq "trust/session,decisions/answer,decisions/answer,decisions/answer,chat/line,chat/photo") ("the opening envelope, the three answers, the line and the photo's manifest are session-signed under the vouch, as the PC's own reader and WebAuthn verifier read them (" + ($kinds -join ",") + "; " + ($why -join "|") + ")")
    Check ($sp.ok -and $dataN -ge 1) ("and the photo's parts went beside them, as items that are no envelopes (" + $dataN + " part(s))")
    $vouchId1 = $(if ($sentS.Count -and $sentS[0].ok) { $sentS[0].value.sig.vouchId } else { "" })
    $run = Invoke-Run -Turns 1
    $run = Invoke-Run -Turns 1
    $posts = @(Get-HordeTestFleetPosts -Folder $fake)
    Check ((Get-Landed "One, no prompt.") -eq 1 -and (Get-Landed "Two, no prompt.") -eq 1 -and (Get-Landed "Three, no prompt.") -eq 1 -and @($posts | Where-Object { $_.body.EndsWith("A line, no prompt.") }).Count -eq 1) "THE REAL PC TAKES THEM: the three session-signed answers land once each, and the line is posted to the Thrall once"
    $photoPostsNow = @($posts | Where-Object { $_.body.StartsWith("FOUNDER PHOTO from the phone") }).Count
    Check ($photoPostsNow -eq $photoPostsBefore + 1) ("and the session-signed photo lands whole, its one line posted to the Thrall once (" + $photoPostsBefore + " -> " + $photoPostsNow + ")")
    # needsPasskey: one more prompt, signed by the passkey, and the PC takes it.
    $skip = Get-MachineCount
    $np = Invoke-Browser @{ cmd = "answer"; text = "Yes, deploy."; via = "enter"; mailbox = $mailbox; question = $sTitles[3] }
    $c3 = (Invoke-Browser @{ cmd = "assertions" }).value
    $npEnv = @(Get-MachineEnvelopes -Skip $skip | Where-Object { $_.ok -and $_.value.header.channel -ceq "decisions" })
    $run = Invoke-Run -Turns 1
    Check ($np.value.put -and $c3 -eq $c2 + 1 -and $npEnv.Count -eq 1 -and $npEnv[0].value.sig.alg -ceq "webauthn.get" -and (Get-Landed "Yes, deploy.") -eq 1) ("A QUESTION FLAGGED needsPasskey costs exactly one more prompt, goes signed by the passkey, and lands (" + ($c3 - $c2) + ")")
    # IDLE: the PC's limit, one minute here, as its status says; the page ends the session at that moment.
    $idle = $null
    for ($i = 0; $i -lt 150; $i++) { $idle = Invoke-Browser @{ cmd = "sessions" }; if ($idle.ok -and @($idle.value.list).Count -ge 1 -and -not $idle.value.list[0].open) { break }; Start-Sleep -Milliseconds 500 }
    Check ($idle.ok -and -not $idle.value.list[0].open -and $idle.value.notice.Contains("not used for as long as your PC allows") -and $idle.value.account.Contains("no unlocked session is open")) ("PAST THE PC'S IDLE LIMIT the page ends the session itself and says so, the Account screen too (" + $(if ($idle.ok) { $idle.value.notice } else { $idle.reason }) + ")")
    $skip = Get-MachineCount
    $ai = Invoke-Browser @{ cmd = "answer"; text = "After the idle."; via = "enter"; mailbox = $mailbox; question = $sTitles[4] }
    $c4 = (Invoke-Browser @{ cmd = "assertions" }).value
    $aiEnv = @(Get-MachineEnvelopes -Skip $skip | Where-Object { $_.ok -and $_.value.header.channel -ceq "decisions" })
    $vouchId2 = $(if ($aiEnv.Count) { $aiEnv[0].value.sig.vouchId } else { "" })
    Check ($ai.value.put -and $c4 -eq $c3 + 1 -and $aiEnv.Count -eq 1 -and (Test-SessionEnvelope $aiEnv[0]) -ceq "" -and $vouchId2 -cne $vouchId1 -and $null -ne $aiEnv[0].value.sig.vouch) ("then the next answer asks for the passkey once, for a new vouch, and goes under it (" + ($c4 - $c3) + ")")
    # AWAY: past the setting (1 s in this build) the session ends; the horde stays open to read. At once,
    # inside the PC's one minute.
    $brief = $(if ($realAway) { Invoke-Browser @{ cmd = "away"; ms = 300 } } else { Invoke-Browser @{ cmd = "hide"; ms = 300 } })
    if (-not $realAway) { $null = Invoke-Browser @{ cmd = "show" } }
    $ss = Invoke-Browser @{ cmd = "sessions" }
    Check ($ss.ok -and $ss.value.list[0].open) ("CONTROL: away for less than the setting, the session stays open (" + $(if ($realAway) { "another tab in front" } else { "the page told it is hidden: Chrome gave no hidden state" }) + ")")
    $gone = $(if ($realAway) { Invoke-Browser @{ cmd = "away"; ms = 1600 } } else { Invoke-Browser @{ cmd = "hide"; ms = 1600 } })
    if (-not $realAway) { $null = Invoke-Browser @{ cmd = "show" } }
    $ss = Invoke-Browser @{ cmd = "sessions" }
    Check ($ss.ok -and @($ss.value.list).Count -eq 1 -and -not $ss.value.list[0].open -and $ss.value.notice.Contains("in the background too long")) ("AWAY PAST THE SETTING the session ends and the page says so, the horde still open to read (" + $(if ($ss.ok) { $ss.value.notice } else { $ss.reason }) + ")")
    $null = Invoke-Browser @{ cmd = "waitText"; text = $sTitles[5] }
    $skip = Get-MachineCount
    $aa = Invoke-Browser @{ cmd = "answer"; text = "After the away."; via = "enter"; mailbox = $mailbox; question = $sTitles[5] }
    $c5 = (Invoke-Browser @{ cmd = "assertions" }).value
    $aaEnv = @(Get-MachineEnvelopes -Skip $skip | Where-Object { $_.ok -and $_.value.header.channel -ceq "decisions" })
    Check ($aa.value.put -and $c5 -eq $c4 + 1 -and $aaEnv.Count -eq 1 -and (Test-SessionEnvelope $aaEnv[0]) -ceq "" -and $aaEnv[0].value.sig.vouchId -cne $vouchId2) ("and the next answer asks for the passkey once again (" + ($c5 - $c4) + ")")
    $run = Invoke-Run -Turns 1
    Check ((Get-Landed "After the idle.") -eq 1 -and (Get-Landed "After the away.") -eq 1) "and the real PC takes both answers, each under its new vouch"
    # RELOAD: the key is gone with the page; the unlock is the one prompt, and the answer after it none.
    $null = Invoke-Browser @{ cmd = "reload" }
    $ss = Invoke-Browser @{ cmd = "sessions" }
    Check ($ss.ok -and @($ss.value.list).Count -eq 0) "A RELOAD: the page holds no session, nothing unlocked"
    $null = Invoke-Browser @{ cmd = "unlock" }
    $c6 = (Invoke-Browser @{ cmd = "assertions" }).value
    $null = Invoke-Browser @{ cmd = "waitText"; text = $sTitles[6] }
    $skip = Get-MachineCount
    $ar = Invoke-Browser @{ cmd = "answer"; text = "After the reload."; via = "enter"; mailbox = $mailbox; question = $sTitles[6] }
    $c7 = (Invoke-Browser @{ cmd = "assertions" }).value
    $arEnv = @(Get-MachineEnvelopes -Skip $skip | Where-Object { $_.ok -and $_.value.header.channel -ceq "decisions" })
    $run = Invoke-Run -Turns 1
    Check ($ar.value.put -and $c6 -eq $c5 + 1 -and $c7 -eq $c6 -and $arEnv.Count -eq 1 -and (Test-SessionEnvelope $arEnv[0]) -ceq "" -and $arEnv[0].value.sig.vouchId -cne $aaEnv[0].value.sig.vouchId -and (Get-Landed "After the reload.") -eq 1) ("then it asks again: the unlock is one prompt, and the answer after it none, under a new vouch the real PC takes (" + ($c6 - $c5) + " then " + ($c7 - $c6) + ")")

    Write-Host ""
    Write-Host "--- 15. the shipped times: a session survives 9 minutes hidden and is gone after 11 (Q75 (c)) ---" -ForegroundColor Cyan
    # The PC's idle limit back to an hour, past every time here, and a new question so a run sends a
    # snapshot that says so.
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay-sessions.json"), '{"schemaVersion": 1, "settings": {"idleMinutes": 60}}', $utf8)
    $q15 = Invoke-HordeDecision -Operation "add" -Root $store -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = @{ title = "Is the session still open after the switch-away?"; kind = "yes-no"; whatItIs = "Section 15."; group = "voice"; askedBy = "orc-e" } }
    $run = Invoke-Run -Turns 1
    Check ($q15.state -ceq "known" -and $run.code -eq 0) "CONTROL: the PC's idle limit is an hour, and a run sends a snapshot that says so"
    $shipped = New-HordePwaSite -Out (Join-Path $work "site-shipped") -Transport "binding"
    $shippedConfig = $(if ($shipped.state -ceq "known") { [System.IO.File]::ReadAllText((Join-Path $shipped.value.out "app\config.json"), $utf8) | ConvertFrom-Json } else { $null })
    Check ($null -ne $shippedConfig -and $null -ne $shippedConfig.PSObject.Properties["lockAfterHiddenSeconds"] -and $null -ne $shippedConfig.PSObject.Properties["sessionAwaySeconds"]) ("CONTROL: a site built with no times given, as a deployment builds it, names both (" + $(if ($null -ne $shippedConfig) { "lock " + $shippedConfig.lockAfterHiddenSeconds + " s, away " + $shippedConfig.sessionAwaySeconds + " s" } else { $shipped.reason }) + ")")
    $configPath = Join-Path $site "app\config.json"
    $configOriginal = [System.IO.File]::ReadAllText($configPath, $utf8)
    function Test-HiddenFor {
        # config.json served with -Times only (none: neither key), the page reloaded and unlocked (one prompt),
        # the PC's hour drawn; then hidden for -Minutes by the moved clock, and shown. Is a session open after?
        param([hashtable]$Times, [int]$Minutes)
        $c = $configOriginal | ConvertFrom-Json
        [void]$c.PSObject.Properties.Remove("lockAfterHiddenSeconds")
        [void]$c.PSObject.Properties.Remove("sessionAwaySeconds")
        foreach ($k in $Times.Keys) { $c | Add-Member -NotePropertyName $k -NotePropertyValue $Times[$k] }
        [System.IO.File]::WriteAllText($configPath, (ConvertTo-Json $c -Compress), $utf8)
        $null = Invoke-Browser @{ cmd = "reload" }
        $served = Invoke-Browser @{ cmd = "servedConfig" }
        $null = Invoke-Browser @{ cmd = "unlock" }
        $st = $null
        for ($i = 0; $i -lt 60; $i++) { $st = Invoke-Browser @{ cmd = "sessions" }; if ($st.ok -and @($st.value.list).Count -ge 1 -and $st.value.list[0].open -and $st.value.list[0].idleMs -eq 3600000) { break }; Start-Sleep -Milliseconds 250 }
        $ready = ($served.ok -and (ConvertTo-Json $served.value -Compress) -ceq (ConvertTo-Json $c -Compress) -and $st.ok -and @($st.value.list).Count -ge 1 -and $st.value.list[0].open -and $st.value.list[0].idleMs -eq 3600000)
        if (-not $ready) { return [pscustomobject]@{ ready = $false; open = $false; said = ("not ready: served " + $(if ($served.ok) { ConvertTo-Json $served.value -Compress } else { $served.reason }) + "; sessions " + $(if ($st.ok) { ConvertTo-Json $st.value.list -Compress } else { $st.reason })) } }
        $null = Invoke-Browser @{ cmd = "hide"; ms = 50 }
        $null = Invoke-Browser @{ cmd = "clock"; ms = $Minutes * 60000 }
        $null = Invoke-Browser @{ cmd = "show" }
        Start-Sleep -Milliseconds 1500
        $after = Invoke-Browser @{ cmd = "sessions" }
        $null = Invoke-Browser @{ cmd = "clock"; ms = 0 }
        return [pscustomobject]@{ ready = $true; open = ($after.ok -and @($after.value.list | Where-Object { $_.open }).Count -ge 1); said = $(if ($after.ok) { (ConvertTo-Json $after.value.list -Compress) + " " + $after.value.notice } else { $after.reason }) }
    }
    $old9 = Test-HiddenFor -Times @{ lockAfterHiddenSeconds = 300; sessionAwaySeconds = 600 } -Minutes 9
    Check ($old9.ready -and -not $old9.open) ("CONTROL: with the old five-minute lock, 9 minutes hidden ends the session - so this check can fail (" + $old9.said + ")")
    $shippedTimes = @{ lockAfterHiddenSeconds = $(if ($null -ne $shippedConfig) { $shippedConfig.lockAfterHiddenSeconds } else { 0 }); sessionAwaySeconds = $(if ($null -ne $shippedConfig) { $shippedConfig.sessionAwaySeconds } else { 0 }) }
    $ship9 = Test-HiddenFor -Times $shippedTimes -Minutes 9
    Check ($ship9.ready -and $ship9.open) ("WITH THE SHIPPED TIMES a session survives 9 minutes hidden: the founder's Q75 (c) (" + $ship9.said + ")")
    $ship11 = Test-HiddenFor -Times $shippedTimes -Minutes 11
    Check ($ship11.ready -and -not $ship11.open) ("and is gone after 11 (" + $ship11.said + ")")
    $none9 = Test-HiddenFor -Times @{} -Minutes 9
    Check ($none9.ready -and $none9.open) ("WITH NO TIMES IN config.json, app.js's own: a session survives 9 minutes hidden (" + $none9.said + ")")
    $none11 = Test-HiddenFor -Times @{} -Minutes 11
    Check ($none11.ready -and -not $none11.open) ("and is gone after 11 (" + $none11.said + ")")
    [System.IO.File]::WriteAllText($configPath, $configOriginal, $utf8)
    $dump = Invoke-Browser @{ cmd = "dump" }
    Check ($dump.ok -and -not $dump.value.Contains("sessionPublicKey") -and -not $dump.value.Contains("privateKey") -and $dump.value.Contains('"vouchSeq":')) "Chrome's storage holds the vouch counter and no session key"
    $probs = Invoke-Browser @{ cmd = "problems" }
    Check ($probs.ok -and @($probs.value).Count -eq 0) ("no exception, no console error and no policy violation in the whole run (" + $(if ($probs.ok) { @($probs.value) -join " | " } else { $probs.reason }) + ")")
    }
} finally {
    Remove-HordeTestChatThrall -Thrall $thrall
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
        if ((Split-Path -Leaf $work) -match '^horde-pwa-browser-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $work) { Start-Sleep -Milliseconds 250 }
    }
    Check (-not (Test-Path -LiteralPath $work)) "the suite's folder - the site, the relay and Chrome's profile with its passkey - is gone"
}

if (-not $canDecide) { Complete-HordeSuite -Success "skipped under this runtime: the decisions list cannot add a question (issue #173)" -PassCode 3 }
Complete-HordeSuite -Success "in headless Chrome at phone size the app pairs with Chrome's passkey, draws the question with the window's document, sends answers by Enter and by touch that land once, unlocks by PRF, starts offline from its worker, keeps nothing opened, reads but never answers by its recovery code, and draws the cards and opens their streams"
