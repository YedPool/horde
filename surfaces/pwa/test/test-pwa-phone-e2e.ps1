# DOES THE PHONE APP, BUILT AS IT SHIPS, PAIR WITH A MACHINE, READ ITS OPEN QUESTIONS AND ANSWER ONE
# THAT LANDS ONCE - THROUGH THE REAL horde relay run?
#
# The PWA's end-to-end scenario (relay design 2026-10-09, PR plan item 7; CONTRIBUTING 2). The phone is
# the app's own logic as New-HordePwaSite builds it (surfaces/pwa/Site.ps1): phone-core.js, keywrap.js,
# relay-client.js, the page's bridge.js and the protocol the test phone runs too, imported from the
# built site by surfaces/pwa/test/app-phone.mjs and run in ONE Node process, as one open page. What a
# browser lends it is stood in for: a software passkey (with PRF) for WebAuthn, a store in memory for
# IndexedDB, and a transport over the local relay's folders for the hosted relay. The machine is the
# shipped horde.ps1, `horde relay run`, as its own process, over relays/local in the suite's folder.
#   1. the app answers a pairing offer with a passkey; the machine enrolls it and computes the
#      fingerprint the app shows; the founder confirms it;
#   2. the app announces its identity key; a run takes it in and sends the snapshot; the app opens it,
#      and its bridge hands the document the list operation's answer;
#   3. the founder's answer goes through the bridge's say, signed with the passkey; a run lands it
#      once, his words exactly, by the route phone, to the wording he saw;
#   4. the same words saved again (the same id) are one record;
#   5. a reload drops the key from memory; the passkey's PRF unwraps it again; nothing decrypted was
#      ever in the store;
#   6. the recovery code unlocks to READ: the app refuses to answer, nothing is sent; a wrong code
#      unlocks nothing;
#   7. an old snapshot the relay puts again is not shown over the newer one;
#   8. the chat: the Thrall's last turns (a synthetic fleet, test/lib/ChatFleet.ps1) reach the app; a
#      recovery session cannot write; the founder's line, sent through the bridge and signed by the
#      passkey, is posted to the Thrall once, and the receipt shows in the app's own words.
#
# NODE IS NEEDED. Without it the suite says so and exits 3, a partial run, never 0. HORDE_HOME is the
# suite's own for every child and for this process, and is put back.

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
$work = Join-Path $env:TEMP ("horde-pwa-e2e-" + [guid]::NewGuid().ToString("N"))
$hh = Join-Path $work "home"
$mailboxes = Join-Path $work "relay"
$site = Join-Path $work "site"
New-Item -ItemType Directory -Path (Join-Path $hh "settings"), $mailboxes -Force | Out-Null
$origin = "https://relay.example.test"
$keysMade = @()
$app = $null
$canDecide = $false
$thrall = $null
$fake = Join-Path $work "fleet-messenger"

function ConvertTo-AsciiJson {
    # One line of JSON with everything past ASCII as a \u escape: the app's stdin is read as UTF-8,
    # and this process may not write UTF-8 to it.
    param($Value)
    $t = ConvertTo-Json -InputObject $Value -Compress -Depth 8
    return ([regex]::Replace($t, '[^\x20-\x7E]', { param($m) '\u' + ([int][char]$m.Value).ToString("x4") }))
}
function Invoke-App {
    # One command to the app (app-phone.mjs), its answer parsed: { ok; value; reason }.
    param([hashtable]$Command)
    $script:app.p.StandardInput.WriteLine((ConvertTo-AsciiJson $Command))
    $script:app.p.StandardInput.Flush()
    $read = $script:app.p.StandardOutput.ReadLineAsync()
    if (-not $read.Wait(60000)) { throw "the app did not answer in 60 s" }
    if ($null -eq $read.Result) { throw ("the app ended: " + $script:app.err.Result) }
    return ($read.Result | ConvertFrom-Json)
}
function Invoke-Run {
    param([int]$Turns = 2)
    return (Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "run", "-Relay", "local", "-RelayRoot", $mailboxes, "-MaxTurns", "" + $Turns) -Env @{ HORDE_HOME = $hh })
}
function Get-MailboxHead {
    # The highest seq a local relay's mailbox ever held (relays/local/Relay.ps1, THE HEAD): items are
    # trimmed on ack, so a count of files says nothing about what was put.
    param([string]$Dir)
    $seqs = @(Get-ChildItem -LiteralPath $Dir -File -ErrorAction SilentlyContinue | ForEach-Object { if ($_.Name -match '\A([0-9]{16})-' -or $_.Name -match '\Afloor-([0-9]{16})\z') { [long]$Matches[1] } })
    if ($seqs.Count -eq 0) { return 0 }
    return ($seqs | Measure-Object -Maximum).Maximum
}
function Get-Said { if (-not (Test-Path -LiteralPath $store)) { return @() }; return @(Get-ChildItem -LiteralPath $store -Filter "*.json" | Sort-Object Name | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName, $utf8) | ConvertFrom-Json } | Where-Object { $_.kind -ceq "message-said" -and $_.data.route -ceq "phone" }) }

try {
    $env:HORDE_HOME = $hh
    $built = New-HordePwaSite -Out $site -Transport "binding"
    Check ($built.state -ceq "known") ("CONTROL: the site is built as it ships (" + $(if ($built.state -ceq "known") { $built.value.version } else { $built.reason }) + ")")
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay.json"), '{"schemaVersion": 1, "settings": {"horde": "work"}}', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay-run.json"), '{"schemaVersion": 1, "settings": {"watchMs": 200}}', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay-chat.json"), '{"schemaVersion": 1, "settings": {"sendIntervalMs": 0, "startTurns": 2}}', $utf8)
    $chatFixtures = @(Get-HordeTestChatFixtureFiles | ForEach-Object { . $_ -Root $root })
    $thrall = New-HordeTestChatThrall -Fixtures $chatFixtures
    Check ($null -ne $thrall -and (New-HordeTestFleetMessenger -HordeHome $hh -Folder $fake) -cne "") "CONTROL: a synthetic Thrall and a messenger stand-in are ready for the chat"
    Add-HordeTestChatTurns -Thrall $thrall -Turns @(@{ role = "user"; text = "start the voice work" }, @{ role = "assistant"; text = "the old reply" }, @{ role = "user"; text = "status?" }, @{ role = "assistant"; text = "two of three done" })
    $id = New-HordeRelayMachineIdentity -HordeHome $hh -Provider "software"
    Check ($id.state -ceq "known") "CONTROL: the machine has its relay identity"
    $keysMade = @(@{ n = $id.value.sign.name; s = $id.value.scope }, @{ n = $id.value.agree.name; s = $id.value.scope })
    $store = Join-Path $hh "store\decisions"
    $q = Invoke-HordeDecision -Operation "add" -Root $store -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = @{ title = "Should the closing sound play when the assistant closes?"; kind = "yes-no"; whatItIs = "The app has no closing sound today."; group = "voice"; askedBy = "orc-b" } }
    $canDecide = ($q.state -ceq "known" -and $q.value.outcome -ceq "done")
    # Under PowerShell 7 the decisions list cannot add a question on main (issue #173).
    if (-not $canDecide) { Write-Host "  [SKIP] the decisions list cannot add a question under this runtime (issue #173): the scenario is not run" -ForegroundColor Yellow }
    if ($canDecide -and $built.state -ceq "known") {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $node.Source
    $psi.Arguments = '"' + (Join-Path $here "app-phone.mjs") + '" "' + $site + '" "' + $mailboxes + '" ' + $origin + ' on'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $app = [pscustomobject]@{ p = $p; err = $p.StandardError.ReadToEndAsync() }

    Write-Host ""
    Write-Host "--- 1. the app pairs with a passkey, and the two screens agree on the fingerprint ---" -ForegroundColor Cyan
    $offer = New-HordeRelayPairingOffer -HordeHome $hh -RpId "relay.example.test" -Origins @($origin)
    $paired = Invoke-App @{ cmd = "pair"; offer = $offer.value.text; label = "Founder phone" }
    Check ($paired.ok) ("the app answers the offer with a passkey registration (" + $(if ($paired.ok) { "fingerprint " + $paired.value.fingerprint } else { $paired.reason }) + ")")
    $hid = $(if ($paired.ok) { $paired.value.id } else { "" })
    $done = Complete-HordeRelayPairing -HordeHome $hh -Response $(if ($paired.ok) { $paired.value.response } else { "" })
    Check ($done.ok -and $paired.ok -and $done.value.fingerprint -ceq $paired.value.fingerprint) "the machine enrolls the app's passkey, and computes the fingerprint the app shows"
    Check ($paired.ok -and $paired.value.prf -eq $true -and $done.ok -and $done.value.device.prf -eq $true) "the app tells the machine its passkey has PRF, and the machine records it"
    Check ($paired.ok -and $paired.value.recoveryCode -cmatch '\A[0-9A-HJKMNP-TV-Z]{4}(-[0-9A-HJKMNP-TV-Z]{4}){5}\z') "the app shows a recovery code to write down: six groups of four"
    $confirmed = Confirm-HordeRelayDevice -HordeHome $hh -Id $(if ($done.ok) { $done.value.device.id } else { "none" }) -Fingerprint $(if ($paired.ok) { $paired.value.fingerprint } else { "" })
    Check ($confirmed.ok -and $confirmed.value.device.state -ceq "trusted") "the founder types the app's fingerprint at the machine, and the passkey is trusted"

    Write-Host ""
    Write-Host "--- 2. the app announces its key; the snapshot comes back and the bridge draws it ---" -ForegroundColor Cyan
    $ann = Invoke-App @{ cmd = "announce"; id = $hid }
    Check ($ann.ok) ("the app announces its identity key, vouched for by its passkey (" + $(if ($ann.ok) { $ann.value.agreeKeyId } else { $ann.reason }) + ")")
    $run = Invoke-Run -Turns 2
    Check ($run.code -eq 0 -and $ann.ok -and $run.out.Contains("the phone key " + $ann.value.agreeKeyId + " is now in the trust store")) ("a run takes the app's key into the trust store (exit " + $run.code + ")")
    Check ($run.out.Contains("snapshot of 1 open question(s)")) "and sends the snapshot of the open question"
    $pick = Invoke-App @{ cmd = "bridge"; name = "pick"; args = @{ id = $hid } }
    Check ($pick.ok -and $pick.value.state -ceq "known" -and $pick.value.value.outcome -ceq "done" -and @($pick.value.value.questions).Count -eq 1 -and $pick.value.value.questions[0].title -ceq "Should the closing sound play when the assistant closes?") "the bridge answers list as the list operation does: the question, verified, opened and handed to the document"
    $kinds = Invoke-App @{ cmd = "bridge"; name = "kinds" }
    Check ($kinds.ok -and $kinds.value.state -ceq "known" -and $null -ne $kinds.value.value.kinds.PSObject.Properties["yes-no"]) "and kinds as the kinds operation does, from the site's question-kinds.json"
    $off = Invoke-App @{ cmd = "bridge"; name = "hand-back" }
    Check (-not $off.ok -and $off.reason.Contains("not a request this page may make")) "a request off the bridge's list is refused"
    $wording = $(if ($pick.ok -and $pick.value.state -ceq "known") { [int]$pick.value.value.questions[0].wordingVersion } else { 1 })

    Write-Host ""
    Write-Host "--- 3. the answer, signed with the passkey, lands once ---" -ForegroundColor Cyan
    # Hebrew for "yes, a short one", as escapes: the source stays ASCII (CONTRIBUTING 13).
    $words = "Yes, " + [char]0x05DB + [char]0x05DF + ", " + [char]0x05E7 + [char]0x05E6 + [char]0x05E8
    $answerId = [guid]::NewGuid().ToString("N")
    $said1 = Invoke-App @{ cmd = "bridge"; name = "say"; args = @{ number = 1; text = $words; wording = $wording; id = $answerId } }
    Check ($said1.ok -and $said1.value.ok -eq $true -and $said1.value.sequence -ge 1) ("say answers saved once the relay has the signed envelope (" + $(if ($said1.ok) { ConvertTo-Json $said1.value -Compress } else { $said1.reason }) + ")")
    $run = Invoke-Run -Turns 1
    $said = @(Get-Said)
    Check ($run.code -eq 0 -and $said.Count -eq 1 -and $said[0].data.text -ceq $words -and $said[0].data.speaker -ceq "founder" -and $said[0].data.wordingVersion -eq $wording) ("the answer is in the decisions list once, his words exactly, by the route phone, to the wording he saw (" + $said.Count + " record(s))")
    Check ($said.Count -eq 1 -and "$($said[0].data.evidence)" -cmatch '\A[0-9a-f]{64}\z') "with the hash of the journal record holding his signed envelope as its evidence"

    Write-Host ""
    Write-Host "--- 4. the same words saved again are the same record ---" -ForegroundColor Cyan
    $said2 = Invoke-App @{ cmd = "bridge"; name = "say"; args = @{ number = 1; text = $words; wording = $wording; id = $answerId } }
    $run = Invoke-Run -Turns 1
    Check ($said2.ok -and $said2.value.ok -eq $true -and $run.out.Contains("(replayed)")) "sent again with the same id, in a new envelope, the machine answers it as the first record"
    Check (@(Get-Said).Count -eq 1) ("the list still holds one answer (" + @(Get-Said).Count + ")")

    Write-Host ""
    Write-Host "--- 5. a reload forgets the key; the passkey's PRF brings it back; the store holds nothing opened ---" -ForegroundColor Cyan
    $null = Invoke-App @{ cmd = "reload" }
    $locked = Invoke-App @{ cmd = "refresh"; id = $hid }
    Check (-not $locked.ok -and $locked.code -ceq "locked") "after a reload the horde is locked: no key was kept in the clear"
    $un = Invoke-App @{ cmd = "unlock"; id = $hid }
    Check ($un.ok -and $un.value.unlocked -and $un.value.mode -ceq "passkey" -and @($un.value.wraps) -ccontains "prf" -and @($un.value.wraps) -cnotcontains "device") ("the passkey's PRF unwraps it (wraps: " + $(if ($un.ok) { @($un.value.wraps) -join ", " } else { $un.reason }) + ")")
    $view = Invoke-App @{ cmd = "refresh"; id = $hid }
    Check ($view.ok -and @($view.value.questions).Count -eq 1 -and $view.value.questions[0].thread.count -ge 1) "and the snapshot opens again, his answer under the question"
    $dump = Invoke-App @{ cmd = "dump" }
    $leaks = @("closing sound", "Founder phone answer", $words, "whatItIs", "decisions-snapshot") | Where-Object { $dump.ok -and $dump.value.Contains($_) }
    Check ($dump.ok -and @($leaks).Count -eq 0) ("the store holds no question, no answer and no snapshot: only keys, ids and wraps (" + (@($leaks) -join ", ") + ")")
    Check ($dump.ok -and $dump.value.Contains('"kind":"prf"') -and $dump.value.Contains('"kind":"recovery"') -and -not $dump.value.Contains('"d":')) "it holds the prf and recovery wraps, and no private key as JWK"

    Write-Host ""
    Write-Host "--- 6. the recovery code reads and never answers ---" -ForegroundColor Cyan
    $null = Invoke-App @{ cmd = "lock"; id = $hid }
    $wrong = Invoke-App @{ cmd = "recover"; id = $hid; code = "0000-0000-0000-0000-0000-0000" }
    Check (-not $wrong.ok -and $wrong.reason.Contains("does not open")) "a wrong recovery code unlocks nothing"
    $rec = Invoke-App @{ cmd = "recover"; id = $hid; code = $(if ($paired.ok) { $paired.value.recoveryCode.ToLowerInvariant().Replace("-", " ") } else { "" }) }
    Check ($rec.ok -and $rec.value.mode -ceq "recovery") "the written-down code, typed in lower case with spaces, unlocks the horde to read"
    $view = Invoke-App @{ cmd = "bridge"; name = "pick"; args = @{ id = $hid } }
    Check ($view.ok -and $view.value.state -ceq "known" -and @($view.value.value.questions).Count -eq 1) "the questions can be read"
    $before = Get-MailboxHead (Join-Path $mailboxes ("work\" + $id.value.sign.keyId))
    $ro = Invoke-App @{ cmd = "bridge"; name = "say"; args = @{ number = 1; text = "Not from a recovery code."; wording = $wording; id = [guid]::NewGuid().ToString("N") } }
    $after = Get-MailboxHead (Join-Path $mailboxes ("work\" + $id.value.sign.keyId))
    Check ($ro.ok -and $ro.value.ok -eq $false -and $ro.value.reason.Contains("Read only")) "but say is refused in words: the recovery code cannot sign"
    Check ($before -ge 3 -and $before -eq $after) ("and nothing was put into the machine's mailbox: its head stays at " + $before + " (" + $after + ")")
    $ann2 = Invoke-App @{ cmd = "announce"; id = $hid }
    Check (-not $ann2.ok -and $ann2.reason.Contains("reads only")) "nor can it announce a key"

    Write-Host ""
    Write-Host "--- 7. an old snapshot put again is not shown over the newer one ---" -ForegroundColor Cyan
    $null = Invoke-HordeDecision -Operation "say" -Root $store -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; number = 1; speaker = "warchief"; route = "command"; text = "A chime it is." }
    $run = Invoke-Run -Turns 1
    $newer = Invoke-App @{ cmd = "refresh"; id = $hid }
    $count = $(if ($newer.ok -and @($newer.value.questions).Count -gt 0) { [int]$newer.value.questions[0].thread.count } else { -1 })
    Check ($newer.ok -and $count -ge 2 -and $newer.value.questions[0].thread.turn -ceq "founder") ("the newer snapshot shows the warchief's reply and the turn back with him (" + $count + " messages)")
    $phoneBox = Join-Path $mailboxes "work\phone"
    $oldest = @(Get-ChildItem -LiteralPath $phoneBox -Filter "*.item" | Sort-Object Name | Select-Object -First 1)
    $c = Connect-HordeRelay -Name "local" -Options @{ root = $mailboxes }
    $oldText = [System.IO.File]::ReadAllText($oldest[0].FullName, [System.Text.Encoding]::ASCII)
    $oldText = $oldText.Substring($oldText.IndexOf([char]10) + 1)
    [void](Send-HordeRelayItem -Connection $c.value -Mailbox "work/phone" -Text $oldText -Key ("replayed-" + [guid]::NewGuid().ToString("N")))
    $again = Invoke-App @{ cmd = "refresh"; id = $hid }
    Check ($again.ok -and @($again.value.questions).Count -eq 1 -and [int]$again.value.questions[0].thread.count -eq $count -and $again.value.seq -eq $newer.value.seq) "the relay's replay of the first snapshot changes nothing on screen"

    Write-Host ""
    Write-Host "--- 8. the chat: the Thrall's turns in, the founder's line out, once ---" -ForegroundColor Cyan
    $chat = Invoke-App @{ cmd = "bridge"; name = "chat" }
    $texts = $(if ($chat.ok -and $chat.value.state -ceq "known") { (@($chat.value.value.items | ForEach-Object { $_.text }) -join "|") } else { "" })
    Check ($texts -ceq "status?|two of three done") ("the app shows the Thrall's last two turns, from the end, through the bridge (" + $texts + ")")
    Check ($chat.ok -and $chat.value.value.mode -ceq "recovery") "CONTROL: the app is still unlocked by its recovery code"
    $ro = Invoke-App @{ cmd = "bridge"; name = "chat-send"; args = @{ text = "not from a recovery code"; id = ("a" * 32) } }
    Check ($ro.ok -and $ro.value.ok -eq $false -and $ro.value.reason.Contains("Read only")) "a recovery session cannot write to the Thrall: refused in words"
    $null = Invoke-App @{ cmd = "lock"; id = $hid }
    $null = Invoke-App @{ cmd = "unlock"; id = $hid }
    $null = Invoke-App @{ cmd = "bridge"; name = "pick"; args = @{ id = $hid } }
    $mid = [guid]::NewGuid().ToString("N")
    $sent = Invoke-App @{ cmd = "bridge"; name = "chat-send"; args = @{ text = "Ship the third one."; id = $mid } }
    Check ($sent.ok -and $sent.value.ok -eq $true -and $sent.value.id -ceq $mid) ("unlocked by the passkey, the line is signed and put (" + $(if ($sent.ok) { ConvertTo-Json $sent.value -Compress } else { $sent.reason }) + ")")
    $run = Invoke-Run -Turns 1
    $posts = @(Get-HordeTestFleetPosts -Folder $fake)
    Check ($posts.Count -eq 1 -and $posts[0].to -ceq $thrall.state.session -and $posts[0].body.EndsWith("Ship the third one.")) ("a run posts it to the Thrall's session, once (" + $posts.Count + ")")
    $null = Invoke-App @{ cmd = "bridge"; name = "chat-send"; args = @{ text = "Ship the third one."; id = $mid } }
    $run = Invoke-Run -Turns 1
    Check (@(Get-HordeTestFleetPosts -Folder $fake).Count -eq 1) "the same line sent again, with its id, is still one post"
    $null = Invoke-App @{ cmd = "refresh"; id = $hid }
    $chat = Invoke-App @{ cmd = "chat"; id = $hid }
    $lines = @(); if ($chat.ok) { $lines = @($chat.value.items | Where-Object { $_.kind -ceq "line" }) }
    Check ($lines.Count -eq 1 -and $lines[0].text -ceq "Ship the third one." -and $lines[0].status -ceq "accepted" -and $lines[0].words.StartsWith("Sent")) ("the app shows his line once, with the receipt in its own words (" + $(if ($lines.Count) { $lines[0].words } else { "none" }) + ")")
    }
} finally {
    Remove-HordeTestChatThrall -Thrall $thrall
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    if ($null -ne $app) { try { $app.p.StandardInput.WriteLine('{"cmd":"exit"}'); if (-not $app.p.WaitForExit(10000)) { $app.p.Kill() } } catch { } ; $app.p.Dispose() }
    $env:HORDE_HOME = $realHome
    foreach ($k in @($keysMade)) { try { [void](Remove-HordeRelayKey -Name $k.n -Scope $k.s) } catch { } }
    $left = @($keysMade | Where-Object { (Find-HordeRelayCngKey -Name $_.n -Scope $_.s) -cne "" })
    Check (@($keysMade).Count -eq 2 -and $left.Count -eq 0) "both keys of the suite's identity are gone"
    if ((Split-Path -Leaf $work) -match '^horde-pwa-e2e-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    Check (-not (Test-Path -LiteralPath $work)) "the suite's folder, the site and the relay's mailboxes with it, is gone"
}

if (-not $canDecide) { Complete-HordeSuite -Success "skipped under this runtime: the decisions list cannot add a question (issue #173)" -PassCode 3 }
Complete-HordeSuite -Success "the phone app, built as it ships, pairs with a passkey, reads the open questions sealed to it, answers once through the real horde command, unlocks again by PRF, reads but never answers by its recovery code, and ignores a replayed snapshot"
