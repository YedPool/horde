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
#   1. `horde relay pair`, as its own process, makes the offer; the app answers it with a passkey and
#      sends its response through the relay, sealed; the command takes it from the offer's pairing
#      mailbox, and the founder types the fingerprint the APP shows (through the command's -InputFile):
#      the passkey is trusted;
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
#      passkey, is posted to the Thrall once, and the receipt shows in the app's own words;
#  10. an answer the relay loses (the founder's decisions/16, 2026-10-14): the app shows it answered and
#      sent; the run reports its seq missing; the app sends it again in a new envelope; it lands once
#      and the app says applied.
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
    Write-Host "--- 1. horde relay pair offers; the app answers through the relay; the founder types the app's number ---" -ForegroundColor Cyan
    $typed = Join-Path $work "typed.txt"
    [System.IO.File]::WriteAllText($typed, "", [System.Text.Encoding]::ASCII)
    $pairRun = Start-HordeCliRun -Root $root -HordeArgs @("relay", "pair", "-Relay", "local", "-RelayRoot", $mailboxes, "-RpId", "relay.example.test", "-Origin", $origin, "-InputFile", $typed, "-NoPicture") -Env @{ HORDE_HOME = $hh }
    $offerText = Wait-HordeCliLine -Run $pairRun -Like '{"v":1,"kind":"horde-relay-pairing-offer"*'
    Check ($null -ne $offerText) "horde relay pair prints its offer for the app"
    $paired = Invoke-App @{ cmd = "pair"; offer = $(if ($null -ne $offerText) { $offerText } else { "" }); label = "Founder phone" }
    Check ($paired.ok -and $paired.value.relayed -eq $true) ("the app answers the offer with a passkey, and the relay takes its sealed response (" + $(if ($paired.ok) { "fingerprint " + $paired.value.fingerprint } else { $paired.reason }) + ")")
    $hid = $(if ($paired.ok) { $paired.value.id } else { "" })
    Check ($paired.ok -and $paired.value.recoveryCode -cmatch '\A[0-9A-HJKMNP-TV-Z]{4}(-[0-9A-HJKMNP-TV-Z]{4}){5}\z') "the app shows a recovery code to write down: six groups of four"
    Check ($null -ne (Wait-HordeCliLine -Run $pairRun -Like "A phone registered: 'Founder phone'*") -and $null -ne (Wait-HordeCliLine -Run $pairRun -Like "*Type that number here*")) "the command takes the response from the relay and asks for the number the app shows"
    [System.IO.File]::AppendAllText($typed, $(if ($paired.ok) { $paired.value.fingerprint } else { "none" }) + "`n", [System.Text.Encoding]::ASCII)
    $pairEnd = Complete-HordeCliRun -Run $pairRun
    $dev = @((Get-HordeRelayTrust -HordeHome $hh).value.devices) | Select-Object -First 1
    Check ($pairEnd.code -eq 0 -and $null -ne $dev -and $dev.state -ceq "trusted" -and $paired.ok -and $dev.fingerprint -ceq $paired.value.fingerprint) ("the app's number confirms it: the passkey is trusted, under the fingerprint both screens computed (exit " + $pairEnd.code + ")")
    Check ($null -ne $dev -and $dev.prf -eq $true) "the app told the machine its passkey has PRF, and the machine recorded it"

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
    $null = Invoke-HordeDecision -Operation "say" -Root $store -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; number = 1; speaker = "warchief"; route = "command"; text = "A chime it is."; asks = $false }
    $run = Invoke-Run -Turns 1
    $newer = Invoke-App @{ cmd = "refresh"; id = $hid }
    $count = $(if ($newer.ok -and @($newer.value.questions).Count -gt 0) { [int]$newer.value.questions[0].thread.count } else { -1 })
    Check ($newer.ok -and $count -ge 2 -and $newer.value.questions[0].thread.turn -ceq "warchief") ("the newer snapshot shows the warchief's note under the question he answered, the turn still the warchief's (" + $count + " messages)")
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

    Write-Host ""
    Write-Host "--- 9. the progress log: a changelog on the machine, read by the app in the order written, his place kept ---" -ForegroundColor Cyan
    # A changelog of the suite's own, in the shape the fleet's is, under the suite's home: where a run
    # with no progressFile set looks for it.
    $logFile = Join-Path $hh "progress\changelog.jsonl"
    New-Item -ItemType Directory -Path (Split-Path -Parent $logFile) -Force | Out-Null
    $logLines = @(
        '{"v":1,"id":"20261012T181500Z-01","ts":"2026-10-12T18:15:00Z","kind":"merged","area":"Form fill","title":"Ruled-line fix merged","text":"Asked: keep text off the ink.\nHappened: the fix merged.\nMeans: no overlap.\nNext: the box path."}',
        '{"v":1,"id":"20261012T170000Z-02","ts":"2026-10-12T17:00:00Z","kind":"blocked","area":"Ask Orah voice","lane":"B","task":"T-0101","title":"Waiting on a quiet room","text":"Happened: the acoustic test was put off \u05e9\u05dc\u05d5\u05dd."}',
        '{"v":1,"id":"broken","ts":"not a time","title":"left out","text":"x"}',
        '{"v":1,"id":"20261012T190000Z-03","ts":"2026-10-12T19:00:00Z","kind":"new-kind","area":"Whole fleet","title":"A kind the app does not know","text":"plain words"}'
    )
    [System.IO.File]::WriteAllText($logFile, (($logLines | ForEach-Object { $_ + "`n" }) -join ""), $utf8)
    $run = Invoke-Run -Turns 1
    Check ($run.code -eq 0 -and $run.out.Contains("3 progress entries in 1 envelope(s) and 1 notice(s) sent") -and $run.out.Contains("left out of the progress sent: line 3: its ts is not a time")) ("a run follows the changelog under its home: three entries sent, the line that does not hold together named by its number (exit " + $run.code + ")")
    $null = Invoke-App @{ cmd = "refresh"; id = $hid }
    $pg = Invoke-App @{ cmd = "bridge"; name = "progress" }
    $items = @(); if ($pg.ok -and $pg.value.state -ceq "known") { $items = @($pg.value.value.items) }
    Check ($items.Count -eq 3 -and (@($items | ForEach-Object { $_.title }) -join "|") -ceq "Ruled-line fix merged|Waiting on a quiet room|A kind the app does not know") ("the app shows the entries in the order they were written - the second happened before the first - through the bridge (" + (@($items | ForEach-Object { $_.title }) -join "|") + ")")
    Check ($items.Count -eq 3 -and $items[0].area -ceq "Form fill" -and $items[0].kindWord -ceq "Merged" -and @($items[0].paragraphs).Count -eq 4 -and $items[0].paragraphs[3].label -ceq "Next" -and $items[0].paragraphs[3].text -ceq "the box path." -and $items[1].lane -ceq "B" -and $items[1].task -ceq "T-0101" -and $items[1].text.EndsWith([string][char]0x05E9 + [char]0x05DC + [char]0x05D5 + [char]0x05DD + ".")) "each with its area, its kind in the app's word, its labelled paragraphs, its lane and task, its non-ASCII words exact"
    Check ($items.Count -eq 3 -and $items[2].kind -ceq "note" -and $pg.value.value.skipped -eq 1 -and $pg.value.value.unread -eq 3) "a kind the app does not know is a note; the app is told one line was left out; all three are unread"
    $rd = Invoke-App @{ cmd = "bridge"; name = "progress-read"; args = @{ id = "20261012T170000Z-02" } }
    Check ($rd.ok -and $rd.value.state -ceq "known" -and $rd.value.value.unread -eq 1) "reading as far as the second leaves one unread"
    $mailHead = Get-MailboxHead (Join-Path $mailboxes ("work\" + $id.value.sign.keyId))
    [System.IO.File]::AppendAllText($logFile, ('{"v":1,"id":"20261012T200000Z-04","ts":"2026-10-12T20:00:00Z","kind":"note","area":"Form fill","title":"Not merged after all","text":"Means: it was reverted.","corrects":"20261012T181500Z-01"}' + "`n"), $utf8)
    $run = Invoke-Run -Turns 1
    $null = Invoke-App @{ cmd = "reload" }
    $null = Invoke-App @{ cmd = "unlock"; id = $hid }
    $null = Invoke-App @{ cmd = "bridge"; name = "pick"; args = @{ id = $hid } }
    $pg2 = Invoke-App @{ cmd = "bridge"; name = "progress" }
    $v2 = $(if ($pg2.ok -and $pg2.value.state -ceq "known") { $pg2.value.value } else { $null })
    Check ($run.out.Contains("1 progress entry in 1 envelope(s) sent") -and $null -ne $v2 -and @($v2.items).Count -eq 4 -and $v2.readIndex -eq 1 -and $v2.unread -eq 2) ("only the new line is sent; after a reload the app reads the log again and is at his place: two read, two new (" + $(if ($null -ne $v2) { "" + $v2.readIndex + "/" + $v2.unread } else { "none" }) + ")")
    Check ($null -ne $v2 -and @($v2.items[0].corrections).Count -eq 1 -and $v2.items[0].corrections[0].title -ceq "Not merged after all" -and $v2.items[3].correctsTitle -ceq "Ruled-line fix merged") "the correction is shown on the entry it corrects, and in its own place"
    $dump = Invoke-App @{ cmd = "dump" }
    Check ($dump.ok -and -not $dump.value.Contains("Ruled-line") -and -not $dump.value.Contains("quiet room") -and $dump.value.Contains('"progressRead":{"id":"20261012T170000Z-02","n":2}')) "the store holds his place and no word of the log"
    # THE UNLOCK opens a session with a PC that keeps them (surfaces/pwa/page/phone-core.js, THE UNLOCKED
    # SESSION): its one opening envelope, channel trust and kind session, is the unlock's, not the log's.
    $machineBox = Join-Path $mailboxes ("work\" + $id.value.sign.keyId)
    $since = @(Get-ChildItem -LiteralPath $machineBox -Filter "*.item" | Where-Object { $_.Name -match '\A([0-9]{16})-' -and [long]$Matches[1] -gt $mailHead } | ForEach-Object { $t = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::ASCII); Read-HordeRelayEnvelope -Text $t.Substring($t.IndexOf([char]10) + 1) })
    $notOpening = @($since | Where-Object { -not ($_.ok -and $_.value.header.channel -ceq "trust" -and $_.value.header.kind -ceq "session") })
    Check ($notOpening.Count -eq 0 -and $since.Count -le 1) ("and the app put nothing into the machine's mailbox for any of it but the unlock's session opening: progress goes one way (" + $since.Count + " put, " + $notOpening.Count + " not an opening)")

    Write-Host ""
    Write-Host "--- 10. an answer the relay loses is shown answered, reported missing, sent again and applied once ---" -ForegroundColor Cyan
    $qLost = Invoke-HordeDecision -Operation "add" -Root $store -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = @{ title = "Which chime should play when the assistant opens?"; kind = "yes-no"; whatItIs = "A second question."; group = "voice"; askedBy = "orc-b" } }
    $qNext = Invoke-HordeDecision -Operation "add" -Root $store -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = @{ title = "Should the chime be quiet at night?"; kind = "yes-no"; whatItIs = "A third question."; group = "voice"; askedBy = "orc-b" } }
    $nLost = [int]$qLost.value.number
    $nNext = [int]$qNext.value.number
    $run = Invoke-Run -Turns 1
    $null = Invoke-App @{ cmd = "bridge"; name = "refresh" }
    $lostId = [guid]::NewGuid().ToString("N")
    $null = Invoke-App @{ cmd = "lose" }
    $lostSaid = Invoke-App @{ cmd = "bridge"; name = "say"; args = @{ number = $nLost; text = "The second chime, lost on the way."; wording = 1; id = $lostId } }
    $nextSaid = Invoke-App @{ cmd = "bridge"; name = "say"; args = @{ number = $nNext; text = "Yes, quiet at night."; wording = 1; id = [guid]::NewGuid().ToString("N") } }
    Check ($lostSaid.ok -and $lostSaid.value.ok -eq $true -and $nextSaid.ok -and $nextSaid.value.ok -eq $true) ("CONTROL: both answers are taken by the relay, as the app is told - the first of them written nowhere (" + $(if ($lostSaid.ok) { ConvertTo-Json $lostSaid.value -Compress } else { $lostSaid.reason }) + ")")
    $list = Invoke-App @{ cmd = "bridge"; name = "list" }
    $shown = $(if ($list.ok -and $list.value.state -ceq "known") { @(@($list.value.value.questions | Where-Object { $_.number -eq $nLost })[0].thread.messages) | Select-Object -Last 1 } else { $null })
    Check ($null -ne $shown -and $shown.text -ceq "The second chime, lost on the way." -and $shown.receipt -ceq "sent" -and $shown.local -eq $true) ("the app shows the question answered, his words marked sent, not an empty slot (" + $(if ($null -ne $shown) { ConvertTo-Json $shown -Compress } else { "nothing" }) + ")")
    $run = Invoke-Run -Turns 2
    Check ($run.code -eq 0 -and $run.out.Contains("missing") -and @(Get-Said | Where-Object { [int]$_.data.number -eq $nNext }).Count -eq 1 -and @(Get-Said | Where-Object { [int]$_.data.number -eq $nLost }).Count -eq 0) ("the run lands the later answer, says an envelope of the phone before it is missing, and has nothing for the lost one (exit " + $run.code + ")")
    $null = Invoke-App @{ cmd = "bridge"; name = "refresh" }
    $states = Invoke-App @{ cmd = "answers"; id = $hid }
    $lostState = $(if ($states.ok) { @($states.value | Where-Object { $_.answerId -ceq $lostId })[0] } else { $null })
    Check ($null -ne $lostState -and $lostState.state -ceq "sent" -and (Get-MailboxHead (Join-Path $mailboxes ("work\" + $id.value.sign.keyId))) -ge 1) ("the receipt reports it missing and the app keeps it as sent; it is not sent again before the interval (" + $(if ($null -ne $lostState) { $lostState.state } else { "none" }) + ")")
    $null = Invoke-App @{ cmd = "age"; id = $hid; ms = 11 * 60 * 1000 }
    $headBefore = Get-MailboxHead (Join-Path $mailboxes ("work\" + $id.value.sign.keyId))
    $null = Invoke-App @{ cmd = "bridge"; name = "refresh" }
    $headAfter = Get-MailboxHead (Join-Path $mailboxes ("work\" + $id.value.sign.keyId))
    Check ($headAfter -eq $headBefore + 1) ("once the interval is out the app sends it again, one new envelope (head " + $headBefore + " -> " + $headAfter + ")")
    $run = Invoke-Run -Turns 2
    $landed = @(Get-Said | Where-Object { [int]$_.data.number -eq $nLost })
    Check ($run.code -eq 0 -and $landed.Count -eq 1 -and $landed[0].data.text -ceq "The second chime, lost on the way.") ("the resent answer lands, once, his words exactly (" + $landed.Count + " record(s))")
    $null = Invoke-App @{ cmd = "bridge"; name = "refresh" }
    $states = Invoke-App @{ cmd = "answers"; id = $hid }
    $lostState = $(if ($states.ok) { @($states.value | Where-Object { $_.answerId -ceq $lostId })[0] } else { $null })
    $dump = Invoke-App @{ cmd = "dump" }
    Check ($null -ne $lostState -and $lostState.state -ceq "applied" -and $dump.ok -and -not $dump.value.Contains($lostId)) ("and the app says applied, and keeps it no longer (" + $(if ($null -ne $lostState) { $lostState.state } else { "none" }) + ")")
    Check ($dump.ok -and -not $dump.value.Contains("lost on the way") -and -not $dump.value.Contains("quiet at night")) "while it was kept, and after, the store never held his words as text"
    }
} finally {
    if ($null -ne (Get-Variable -Name pairRun -ErrorAction SilentlyContinue)) { Stop-HordeCliRun $pairRun }
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
