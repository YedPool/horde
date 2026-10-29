# DOES A PHONE THAT PAIRS WITH THIS MACHINE SEE ITS OPEN QUESTIONS, AND DOES ITS ANSWER LAND IN THE
# DECISIONS LIST EXACTLY ONCE - END TO END, THROUGH THE REAL horde COMMAND?
#
# The relay's end-to-end scenario (relay design 2026-10-09, PR plan item 6; CONTRIBUTING 2). The phone
# is test/fixtures/relay/phone/phone.mjs: a passkey and a phone identity key made by WebCrypto - the
# API a PWA has - and every byte it sends built there from the specification, so the machine is
# checked against bytes it did not make. The machine is the shipped horde.ps1, `horde relay run` and
# `horde relay stop`, as their own processes, over relays/local in a folder of the suite's own. The
# steps a user takes that have no command yet - naming the horde, making the identity, offering and
# confirming the pairing - are made with the functions those commands will call.
#   1. the phone answers a pairing offer; the founder types the fingerprint the PHONE shows, and the
#      machine accepts it: the two screens agree;
#   2. the phone announces its identity key, vouched for by its passkey; a run takes it in, and sends
#      the snapshot of the open questions, which the phone opens;
#   3. the phone answers, in the wording it saw; a run lands it in the decisions list, with the hash of
#      its journal record as evidence; the phone's next snapshot shows the turn passed;
#   4. the same envelope again, a re-signed copy, and the same answer resent in a new envelope: still
#      one record; other words under the same answerId: refused, the first answer wins;
#   5. over the hostile test relay (test/lib/HostileRelay.ps1), in this process because the command
#      cannot pick a test relay: reordered, repeated, stale and garbage-salted, a new answer lands once;
#   5c. SENT WHILE THE WATCH IS OPEN (cli/RelayRun.ps1, SENDING DURING THE WATCH): a run that is left
#      running, with a watch of 30 s; the warchief's reply under a question, written a few seconds into
#      that watch, is in the phone's mailbox within seconds - not when the watch ends - and the phone
#      opens it; and `horde relay stop` ends that run inside the same watch, in its first turn;
#   6. one run per home: a second run started beside a first refuses, plainly, and the first stops
#      cleanly when `horde relay stop` asks.
#
# NODE IS NEEDED for the phone. Without it the suite says so and exits 3, a partial run, never 0. The
# phone's private keys live in a state file in the suite's own folder, deleted with it; nothing private
# is committed. HORDE_HOME is the suite's own home for every child and for this process, and is put back.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
# No channel may find this machine's real Thrall (test/lib/FleetPin.ps1): first thing, before any loads.
. (Join-Path $root "test\lib\FleetPin.ps1")
$fleetPin = Enter-HordeTestEmptyFleet
. (Join-Path $root "core\ModuleSettings.ps1")
. (Join-Path $root "channels\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
foreach ($f in @(Get-HordeRelayChannelFiles)) { . $f }
. (Join-Path $root "cli\RelayRun.ps1")
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "test\lib\HostileRelay.ps1")
Set-StrictMode -Version Latest

$node = Get-Command -Name "node" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) {
    Write-Host "  [SKIP] node is not installed here, so there is no phone to run" -ForegroundColor Yellow
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "skipped: no node, so no phone" -PassCode 3
}
if ((Get-HordeRelayKeyStore).state -cne "known") {
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "skipped: no key store here, so no machine identity" -PassCode 3
}

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$realHome = $env:HORDE_HOME
$work = Join-Path $env:TEMP ("horde-relay-e2e-" + [guid]::NewGuid().ToString("N"))
$hh = Join-Path $work "home"
$mailboxes = Join-Path $work "relay"
$phoneDir = Join-Path $work "phone"
New-Item -ItemType Directory -Path (Join-Path $hh "settings"), $mailboxes, $phoneDir -Force | Out-Null
$script:n = 0
$phoneScript = Join-Path $here "fixtures\relay\phone\phone.mjs"
$keysMade = @()

function Invoke-Phone {
    # One command of the phone (phone.mjs), its input and output as files; the output, parsed.
    param([string]$Command, [hashtable]$In = @{})
    $script:n++
    $inFile = Join-Path $phoneDir ("in-" + $script:n + ".json")
    $outFile = Join-Path $phoneDir ("out-" + $script:n + ".json")
    [System.IO.File]::WriteAllText($inFile, (ConvertTo-Json -InputObject $In -Compress -Depth 6), $utf8)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $node.Source
    $psi.Arguments = '"' + $phoneScript + '" ' + $Command + ' "' + (Join-Path $phoneDir "state.json") + '" "' + $inFile + '" "' + $outFile + '"'
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
function Invoke-Run {
    # `horde relay run` over the suite's relay folder, as its own process, for -Turns turns.
    param([int]$Turns = 2)
    return (Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "run", "-Relay", "local", "-RelayRoot", $mailboxes, "-MaxTurns", "" + $Turns) -Env @{ HORDE_HOME = $hh })
}
function Get-Said { if (-not (Test-Path -LiteralPath $store)) { return @() }; return @(Get-ChildItem -LiteralPath $store -Filter "*.json" | Sort-Object Name | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName, $utf8) | ConvertFrom-Json } | Where-Object { $_.kind -ceq "message-said" -and $_.data.route -ceq "phone" }) }
function Get-PhoneMail {
    param($Connection)
    $r = Receive-HordeRelayItems -Connection $Connection -Mailbox "work/phone" -Since 0
    if ($r.state -cne "known") { return @() }
    return @($r.value.items | ForEach-Object { $_.text })
}
function Get-PhoneHead {
    # The relay's number for the newest item in the phone's mailbox, 0 for none. NOT HOW MANY IT HOLDS: a
    # machine deletes its older snapshots from that mailbox when a newer one is whole there
    # (relays/Port.ps1, A SENDER TRIMS ITS OWN STREAM), so a new snapshot shows as a higher number, and
    # the count stays where it was.
    param($Connection)
    $r = Receive-HordeRelayItems -Connection $Connection -Mailbox "work/phone" -Since 0
    if ($r.state -cne "known" -or @($r.value.items).Count -eq 0) { return [long]0 }
    return [long](@($r.value.items | ForEach-Object { $_.seq }) | Measure-Object -Maximum).Maximum
}
function Open-Latest {
    # The phone opens the newest snapshot in its mailbox.
    param($Connection)
    $mail = @(Get-PhoneMail $Connection)
    if ($mail.Count -eq 0) { return [pscustomobject]@{ ok = $false; reason = "no snapshot in the phone's mailbox"; body = $null } }
    return (Invoke-Phone "open" @{ envelope = $mail[$mail.Count - 1] })
}

try {
    $env:HORDE_HOME = $hh
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay.json"), '{"schemaVersion": 1, "settings": {"horde": "work"}}', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay-run.json"), '{"schemaVersion": 1, "settings": {"watchMs": 200}}', $utf8)
    $id = New-HordeRelayMachineIdentity -HordeHome $hh -Provider "software"
    Check ($id.state -ceq "known") "CONTROL: the machine has its relay identity"
    $keysMade = @(@{ n = $id.value.sign.name; s = $id.value.scope }, @{ n = $id.value.agree.name; s = $id.value.scope })
    $store = Join-Path $hh "store\decisions"
    $q = Invoke-HordeDecision -Operation "add" -Root $store -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = @{ title = "Should the closing sound play when the assistant closes?"; kind = "yes-no"; whatItIs = "The app has no closing sound today."; group = "voice"; askedBy = "orc-b" } }
    $canDecide = ($q.state -ceq "known" -and $q.value.outcome -ceq "done")
    # Under PowerShell 7 the decisions list cannot add a question on origin/main (issue #173): the
    # scenario needs it at every step, so it is skipped there, said so, and the suite exits 3.
    if (-not $canDecide) { Write-Host "  [SKIP] the decisions list cannot add a question under this runtime (issue #173): the scenario is not run" -ForegroundColor Yellow }
    if ($canDecide) {
    $c = Connect-HordeRelay -Name "local" -Options @{ root = $mailboxes }

    Write-Host ""
    Write-Host "--- 1. the phone pairs, and the two screens agree on the fingerprint ---" -ForegroundColor Cyan
    $offer = New-HordeRelayPairingOffer -HordeHome $hh -RpId "relay.example.test" -Origins @("https://relay.example.test")
    $reg = Invoke-Phone "register" @{ offer = $offer.value.text; label = "Founder phone" }
    $done = Complete-HordeRelayPairing -HordeHome $hh -Response $reg.response
    Check ($done.ok -and $done.value.fingerprint -ceq $reg.fingerprint) ("the machine enrolls the phone's passkey, and computes the fingerprint the phone shows (" + $reg.fingerprint + ")")
    $confirmed = Confirm-HordeRelayDevice -HordeHome $hh -Id $done.value.device.id -Fingerprint $reg.fingerprint
    Check ($confirmed.ok -and $confirmed.value.device.state -ceq "trusted" -and $confirmed.value.device.keyId -ceq $reg.deviceKeyId) "the founder types the phone's fingerprint at the machine, and the passkey is trusted"

    Write-Host ""
    Write-Host "--- 2. the phone's identity key goes in, and the snapshot comes out ---" -ForegroundColor Cyan
    $pk = Invoke-Phone "phone-key"
    [void](Send-HordeRelayItem -Connection $c.value -Mailbox $id.value.mailbox -Text $pk.envelope -Key $pk.key)
    $run = Invoke-Run -Turns 2
    Check ($run.code -eq 0 -and $run.out.Contains("watching " + $id.value.mailbox) -and $run.out.Contains("stopped after 2 turn(s)")) ("horde relay run watches the machine's mailbox and stops after the turns asked (exit " + $run.code + ")")
    Check ($run.out.Contains("the phone key " + $pk.agreeKeyId + " is now in the trust store")) "the phone's identity key, vouched for by its passkey, is taken into the trust store"
    Check ($run.out.Contains("snapshot of 1 open question(s)")) "and the snapshot of the open question is sent"
    $o = Open-Latest $c.value
    Check ($o.ok -and $o.body.kind -ceq "decisions-snapshot" -and @($o.body.questions).Count -eq 1 -and $o.body.questions[0].title -ceq "Should the closing sound play when the assistant closes?") ("the phone verifies the machine's signature and opens the snapshot with its own key (" + $o.reason + ")")
    $wording = $(if ($o.ok) { [int]$o.body.questions[0].wordingVersion } else { 1 })

    Write-Host ""
    Write-Host "--- 3. the phone's answer lands once, with its evidence, and the phone sees the turn pass ---" -ForegroundColor Cyan
    # Hebrew for "yes, a short one", as escapes: the source stays ASCII (CONTRIBUTING 13).
    $words = "Yes, " + [char]0x05DB + [char]0x05DF + ", " + [char]0x05E7 + [char]0x05E6 + [char]0x05E8
    # The answer names the machine and the snapshot it was made from (review of 48bc492, finding 2).
    $machine = $(if ($o.ok) { "$($o.body.machine)" } else { "" })
    $snapKey = $(if ($o.ok) { "$($o.key)" } else { "" })
    $ans = Invoke-Phone "answer" @{ number = 1; wordingVersion = $wording; text = $words; machine = $machine; snapshot = $snapKey }
    [void](Send-HordeRelayItem -Connection $c.value -Mailbox $id.value.mailbox -Text $ans.envelope -Key $ans.key)
    $run = Invoke-Run -Turns 1
    $said = @(Get-Said)
    $hdr = (Read-HordeRelayEnvelope -Text $ans.envelope).value.header
    $recFile = Join-Path $hh ("relay\journal\in\s-" + $hdr.from + "\c-decisions\" + ([long]$hdr.seq).ToString("D16") + ".rec")
    $hash = $(if (Test-Path -LiteralPath $recFile) { ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes ([System.IO.File]::ReadAllBytes($recFile))) } else { "(no record)" })
    Check ($run.code -eq 0 -and $said.Count -eq 1 -and $said[0].data.text -ceq $words -and $said[0].data.route -ceq "phone" -and $said[0].data.speaker -ceq "founder" -and $said[0].data.wordingVersion -eq $wording) ("the answer is in the decisions list once, his words exactly, by the route phone, to the wording he saw (" + $said.Count + " record(s))")
    Check ($said.Count -eq 1 -and $said[0].data.evidence -ceq $hash) "its evidence is the hash of the journal record that holds his signed envelope"
    # HE HAS ANSWERED, so the question is off his list and nothing puts it back (2026-10-12): the
    # warchief's words that ask are refused, and a note - which asks nothing - is what it says there.
    $asked = Invoke-HordeDecision -Operation "say" -Root $store -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; number = 1; speaker = "warchief"; route = "command"; text = "A chime it is: which of the three?" }
    Check ($asked.state -ceq "known" -and $asked.value.outcome -ceq "refused" -and @(Get-Said).Count -eq 1) "the warchief's words that ask, under the question he answered from his phone, are refused: nothing is written"
    $null = Invoke-HordeDecision -Operation "say" -Root $store -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; number = 1; speaker = "warchief"; route = "command"; text = "A chime it is."; asks = $false }
    $run = Invoke-Run -Turns 1
    $o = Open-Latest $c.value
    Check ($o.ok -and $o.body.questions[0].thread.count -eq 2 -and $o.body.questions[0].thread.turn -ceq "warchief") "the phone's next snapshot shows his answer and the warchief's note under the question, and the turn still the warchief's: it is not back in front of him"
    $texts = $(if ($o.ok -and $null -ne $o.body.questions[0].thread.PSObject.Properties["messages"]) { @($o.body.questions[0].thread.messages | ForEach-Object { $_.text }) -join " | " } else { "(no messages)" })
    Check ($texts -ceq ($words + " | A chime it is.")) ("and it carries the messages themselves, his and the warchief's, word for word (" + $texts + ")")

    Write-Host ""
    Write-Host "--- 4. delivered again, re-signed, resent: one record; other words: the first answer wins ---" -ForegroundColor Cyan
    $dup = Send-HordeRelayItem -Connection $c.value -Mailbox $id.value.mailbox -Text $ans.envelope -Key $ans.key
    $re = Invoke-Phone "resign" @{ envelope = $ans.envelope }
    Check ($re.envelope -cne $ans.envelope) "CONTROL: the phone's re-signed copy is another text of the same envelope"
    [void](Send-HordeRelayItem -Connection $c.value -Mailbox $id.value.mailbox -Text $re.envelope -Key (Get-HordeRelayContentKey -Text $re.envelope))
    $again = Invoke-Phone "answer" @{ number = 1; wordingVersion = $wording; text = $words; answerId = $ans.answerId; machine = $machine; snapshot = $snapKey }
    [void](Send-HordeRelayItem -Connection $c.value -Mailbox $id.value.mailbox -Text $again.envelope -Key $again.key)
    $other = Invoke-Phone "answer" @{ number = 1; wordingVersion = $wording; text = "No, keep it silent."; answerId = $ans.answerId; machine = $machine; snapshot = $snapKey }
    [void](Send-HordeRelayItem -Connection $c.value -Mailbox $id.value.mailbox -Text $other.envelope -Key $other.key)
    $run = Invoke-Run -Turns 1
    # The relay acked and trimmed the first copy, so it takes the same put again as a new item: from here
    # on only the journal stands between a repeat and a second record.
    $replays = ([regex]::Matches($run.out, "a replay: this envelope was recorded")).Count
    Check ($dup.state -ceq "known" -and $replays -eq 2) ("the same envelope put again, and its re-signed copy, are both refused by the journal as replays (" + $replays + ")")
    Check ($run.out.Contains("(replayed)")) "the same answer resent in a new envelope is the first record answered again"
    Check ($run.out.Contains("already used for a different request")) "other words under the same answerId are refused"
    $said = @(Get-Said)
    Check ($said.Count -eq 1 -and $said[0].data.text -ceq $words) ("after all four, the list still holds the one answer, in his first words (" + $said.Count + ")")

    Write-Host ""
    Write-Host "--- 5. through a relay that lies, a new answer still lands once ---" -ForegroundColor Cyan
    Reset-HordeHostileRelay
    $hc = Connect-HordeRelay -Name "hostile" -Options @{}
    $late = Invoke-Phone "answer" @{ number = 1; wordingVersion = $wording; text = "And make it quiet."; machine = $machine; snapshot = $snapKey }
    foreach ($i in 1..3) { [void](Send-HordeRelayItem -Connection $hc.value -Mailbox $id.value.mailbox -Text $late.envelope -Key ($late.key + "/" + $i)) }
    Set-HordeHostileRelayFaults -Faults @("reorder", "duplicate", "stale", "garbage")
    $lines = New-Object System.Collections.ArrayList
    $r = Invoke-HordeRelayRun -HordeHome $hh -Connection $hc.value -MaxTurns 3 -Say { param($Line) [void]$lines.Add($Line) }
    Set-HordeHostileRelayFaults -Faults @()
    $said = @(Get-Said)
    Check ($r.turns -eq 3 -and $said.Count -eq 2 -and $said[1].data.text -ceq "And make it quiet.") ("put three times and served reversed, doubled, stale and salted, the answer is one more record (" + $said.Count + ")")
    Check ((@($lines) -join " ").Contains("a replay")) "the copies after the first are refused by the journal as replays"

    Write-Host ""
    Write-Host "--- 5b. one part of a question, answered from the phone by itself ---" -ForegroundColor Cyan
    # The founder, 2026-10-12: each part sends by itself. The machine's snapshot says it reads version 2
    # answers; the phone's answer names the part; the runner stores it as that part's own record.
    $pq = Invoke-HordeDecision -Operation "add" -Root $store -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = @{ title = "Two things to settle about the chime, one by one."; kind = "parts"; whatItIs = "Follow-ups."; parts = @("(a) Which of the three chimes?", "(b) How loud should it be?"); group = "voice"; askedBy = "orc-b" } }
    $pn = $(if ($pq.state -ceq "known") { [int]$pq.value.number } else { 0 })
    $run = Invoke-Run -Turns 1
    $po = Open-Latest $c.value
    $pqSnap = $(if ($po.ok) { @($po.body.questions | Where-Object { $_.number -eq $pn })[0] } else { $null })
    Check ($po.ok -and $null -ne $pqSnap -and $po.body.answers -eq 2 -and $po.body.v -eq 1) ("the snapshot that carries the question of parts says the machine reads version 2 answers, and is still a version 1 snapshot (" + $po.reason + ")")
    $partAns = Invoke-Phone "answer" @{ number = $pn; wordingVersion = 1; text = "Quiet."; part = "b"; machine = "$($po.body.machine)"; snapshot = "$($po.key)" }
    [void](Send-HordeRelayItem -Connection $c.value -Mailbox $id.value.mailbox -Text $partAns.envelope -Key $partAns.key)
    $run = Invoke-Run -Turns 1
    $partSaid = @(Get-Said | Where-Object { $_.data.number -eq $pn })
    Check ($run.code -eq 0 -and $run.out.Contains("question " + $pn + " part (b)") -and $partSaid.Count -eq 1 -and $null -ne $partSaid[0].data.PSObject.Properties["part"] -and $partSaid[0].data.part -ceq "b" -and $partSaid[0].data.text -ceq "Quiet." -and "$($partSaid[0].data.evidence)" -cmatch '\A[0-9a-f]{64}\z' -and $null -ne $partSaid[0].data.PSObject.Properties["signedBy"]) ("the runner stores the phone's answer as the record of part (b): his words, the part, the proof and the passkey that signed (" + $partSaid.Count + " record(s))")
    $pshow = Invoke-HordeDecision -Operation "show" -Root $store -Request @{ number = $pn }
    Check ($pshow.value.question.thread.turn -ceq "founder" -and (@($pshow.value.question.thread.parts | ForEach-Object { $_.letter + ":" + $_.answered }) -join ",") -ceq "a:False,b:True") "and the question is still his: part (a) is not answered"
    $again = Invoke-Phone "answer" @{ number = $pn; wordingVersion = 1; text = "Quiet."; part = "b"; answerId = $partAns.answerId; machine = "$($po.body.machine)"; snapshot = "$($po.key)" }
    [void](Send-HordeRelayItem -Connection $c.value -Mailbox $id.value.mailbox -Text $again.envelope -Key $again.key)
    $run = Invoke-Run -Turns 1
    Check ($run.out.Contains("(replayed)") -and @(Get-Said | Where-Object { $_.data.number -eq $pn }).Count -eq 1) "the same part's answer resent in a new envelope is the first record answered again: one record"

    Write-Host ""
    Write-Host "--- 5c. a reply written while the run's watch is open is on the phone in seconds, not at the end of the watch ---" -ForegroundColor Cyan
    # The founder's complaint, 2026-10-13: he saw his own message go and then nothing for up to a minute,
    # because the run sent only when its watch of the mailbox ended. MEASURED before the change with this
    # very scenario and an 8 s watch: 6.9 s, three times of three; after it, under a second. Here the
    # watch is 30 s, so a pass cannot be the watch happening to end: before the change this took the
    # rest of the watch, about 27 s, and failed the 8 s allowed.
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay-run.json"), '{"schemaVersion": 1, "settings": {"watchMs": 30000}}', $utf8)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"" + (Join-Path $root "horde.ps1") + "`" relay run -Relay local -RelayRoot `"" + $mailboxes + "`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables["HORDE_HOME"] = $hh
    $liveRun = [System.Diagnostics.Process]::Start($psi)
    $liveOut = $liveRun.StandardOutput.ReadToEndAsync()
    $liveErr = $liveRun.StandardError.ReadToEndAsync()
    try {
        # A run sends one snapshot at its first look: once that is in the phone's mailbox the run's own
        # Tick is done, and what follows it is the watch.
        $hadBefore = Get-PhoneHead $c.value
        $waited = [System.Diagnostics.Stopwatch]::StartNew()
        while ((Get-PhoneHead $c.value) -le $hadBefore -and $waited.ElapsedMilliseconds -lt 90000) { Start-Sleep -Milliseconds 100 }
        $hadUp = Get-PhoneHead $c.value
        Check ($hadUp -gt $hadBefore -and -not $liveRun.HasExited) ("CONTROL: the run is up and has made its first look (" + $waited.ElapsedMilliseconds + " ms)")
        Start-Sleep -Milliseconds 3000
        $reply = "Written while the watch was open."
        $wrote = Invoke-HordeDecision -Operation "say" -Root $store -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; number = 1; speaker = "warchief"; route = "command"; text = $reply; asks = $false }
        $waited.Restart()
        while ((Get-PhoneHead $c.value) -le $hadUp -and $waited.ElapsedMilliseconds -lt 60000) { Start-Sleep -Milliseconds 100 }
        $took = $waited.ElapsedMilliseconds
        Check ($wrote.state -ceq "known" -and $wrote.value.outcome -ceq "done" -and (Get-PhoneHead $c.value) -gt $hadUp -and $took -lt 8000) ("the warchief's reply, written three seconds into a 30 s watch, is in the phone's mailbox " + $took + " ms later - while the watch is still open, not when it ends")
        $o = Open-Latest $c.value
        $shown = $(if ($o.ok) { @(@($o.body.questions | Where-Object { $_.number -eq 1 }) | ForEach-Object { @($_.thread.messages) } | ForEach-Object { $_.text }) } else { @() })
        Check ($o.ok -and $shown -ccontains $reply) ("and the phone opens it: the reply is under the question (" + (@($shown | Select-Object -Last 1) -join "") + ")")
        # THE MAILBOX DID NOT GROW FOR IT (relays/Port.ps1, A SENDER TRIMS ITS OWN STREAM): through the real
        # command and the disk relay, the snapshots this machine sent before that one are gone from it.
        $heldSnapshots = @(@((Receive-HordeRelayItems -Connection $c.value -Mailbox "work/phone" -Since 0).value.items) | Where-Object { $_.key -clike "*/decisions/*" })
        Check ($heldSnapshots.Count -eq 1 -and $heldSnapshots[0].seq -eq (Get-PhoneHead $c.value)) ("and it is the only snapshot the mailbox holds: every one this machine sent before it was deleted when it was taken (" + $heldSnapshots.Count + " held)")
        $waited.Restart()
        $stop = Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "stop") -Env @{ HORDE_HOME = $hh }
        $ended = $liveRun.WaitForExit(20000)
        $stopTook = $waited.ElapsedMilliseconds
        Check ($stop.code -eq 0 -and $ended -and $liveRun.ExitCode -eq 0 -and $liveOut.Result.Contains("stopped after 1 turn(s): stop file")) ("horde relay stop ends that run inside its 30 s watch - " + $stopTook + " ms, where it was the rest of the watch - and it was all one turn: one watch, one request of the relay")
    } finally {
        if (-not $liveRun.HasExited) { $liveRun.Kill() }
        $liveRun.Dispose()
        [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay-run.json"), '{"schemaVersion": 1, "settings": {"watchMs": 200}}', $utf8)
    }

    Write-Host ""
    Write-Host "--- 6. one run per home: a second refuses; the first stops when asked ---" -ForegroundColor Cyan
    # Review of 3d837f0: two runs on one home were let race on its state; now the second refuses. The stop
    # file still obeys every run started before it (review of 48bc492, finding 4).
    $runs = New-Object System.Collections.ArrayList
    # A lock left by an earlier section is not held by anyone now; remove it so its appearing means the first run took the home.
    $lockFile = Join-Path $hh "relay\run.lock"
    Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue
    Check (-not (Test-Path -LiteralPath $lockFile)) "before the first run starts, no run.lock is left on the home (an earlier run still holds it if one is)"
    try {
    foreach ($i in 1..2) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"" + (Join-Path $root "horde.ps1") + "`" relay run -Relay local -RelayRoot `"" + $mailboxes + "`""
        # TEST-ONLY KNOBS (read here only, default off; production code is untouched): they make the SECOND run slow
        # to start (milliseconds of delay) or never end, to prove the wait below is on the run's exit and not a fixed sleep.
        if ($i -eq 2 -and $env:HORDE_TEST_SECOND_RUN_HANG -ceq "1") { $psi.Arguments = "-NoProfile -NonInteractive -Command Start-Sleep -Seconds 600" }
        elseif ($i -eq 2 -and $env:HORDE_TEST_SECOND_RUN_DELAY_MS -match '^[0-9]+$') { $psi.Arguments = "-NoProfile -NonInteractive -Command Start-Sleep -Milliseconds " + $env:HORDE_TEST_SECOND_RUN_DELAY_MS + "; & powershell.exe " + $psi.Arguments }
        elseif ($i -eq 1 -and $env:HORDE_TEST_FIRST_RUN_DELAY_MS -match '^[0-9]+$') { $psi.Arguments = "-NoProfile -NonInteractive -Command Start-Sleep -Milliseconds " + $env:HORDE_TEST_FIRST_RUN_DELAY_MS + "; & powershell.exe " + $psi.Arguments }
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $psi.EnvironmentVariables["HORDE_HOME"] = $hh
        $p = [System.Diagnostics.Process]::Start($psi)
        [void]$runs.Add([pscustomobject]@{ p = $p; out = $p.StandardOutput.ReadToEndAsync(); err = $p.StandardError.ReadToEndAsync() })
        if ($i -eq 1) {
            # Wait on the event, not a fixed head start: the first run has taken the home when it has created
            # <home>\relay\run.lock (cli/RelayRun.ps1 opens it OpenOrCreate, no sharing, before its first turn).
            $took = New-Object System.Diagnostics.Stopwatch
            $took.Start()
            while (-not (Test-Path -LiteralPath $lockFile) -and -not $p.HasExited -and $took.ElapsedMilliseconds -lt 20000) { Start-Sleep -Milliseconds 50 }
            # run.lock stays on disk after a run exits, so the file alone is not proof: the run must still be alive.
            $heldNow = (Test-Path -LiteralPath $lockFile) -and -not $p.HasExited
            Check $heldNow $(if ($heldNow) { "the first run took the home (run.lock) before the second was started" } elseif ($p.HasExited) { "the first run ended before taking the home" } else { "the first run never took the home within 20 s" })
        }
    }
        $second = $runs[1]
        # Wait on the event itself - the second run's exit - not a fixed sleep: a slow box needs longer to start it.
        $secondEnded = $second.p.WaitForExit(20000)
        Check ($secondEnded -and -not $runs[0].p.HasExited -and $second.p.ExitCode -ne 0) $(if ($secondEnded) { "the first run is running; the second, started beside it on the same home, has ended with an error" } else { "the first run is running; the second, started beside it on the same home, has ended with an error - but it had NOT ended 20 s after it started (a hang, not a slow start)" })
        Check (($second.out.Result + $second.err.Result).Contains("another relay run is already running on this home")) "and it says why, plainly"
        $stop = Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "stop") -Env @{ HORDE_HOME = $hh }
        $ended = $runs[0].p.WaitForExit(30000)
        Check ($stop.code -eq 0 -and $ended -and $runs[0].p.ExitCode -eq 0 -and $runs[0].out.Result.Contains("stopped after") -and $runs[0].out.Result.Contains("stop file")) "horde relay stop ends the first within a turn; it exits 0 and says it stopped for the stop file"
        $next = Invoke-Run -Turns 1
        Check ($next.code -eq 0 -and $next.out.Contains("stopped after 1 turn(s): turns") -and $next.out.Contains("stop file from before")) "a run started after the stop does not obey it: it was a request to the runs before it, and it clears it"
    } finally {
        # Kill the tree by the PID this test started (the delay/hang wrapper has the relay as a child); never by name.
        foreach ($x in $runs) { if (-not $x.p.HasExited) { & taskkill.exe /T /F /PID $x.p.Id *> $null }; $x.p.Dispose() }
    }
    }
} finally {
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    $env:HORDE_HOME = $realHome
    foreach ($k in @($keysMade)) { try { [void](Remove-HordeRelayKey -Name $k.n -Scope $k.s) } catch { } }
    $left = @($keysMade | Where-Object { (Find-HordeRelayCngKey -Name $_.n -Scope $_.s) -cne "" })
    Check (@($keysMade).Count -eq 2 -and $left.Count -eq 0) "both keys of the suite's identity are gone"
    if ((Split-Path -Leaf $work) -match '^horde-relay-e2e-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    Check (-not (Test-Path -LiteralPath $work)) "the suite's folder, the phone's keys with it, is gone"
}

if (-not $canDecide) { Complete-HordeSuite -Success "skipped under this runtime: the decisions list cannot add a question (issue #173)" -PassCode 3 }
Complete-HordeSuite -Success "a paired phone sees the open questions sealed to it, its answer lands once through the real horde command, the first answer wins, a lying relay changes nothing, and a run stops when asked"
