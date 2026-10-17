# DOES A CHANGE OF HIS ANSWER FROM THE FOUNDER'S PHONE TAKE EXACTLY WHAT THE FIRST ANSWER TAKES - A FRESH
# PASSKEY ON A needsPasskey QUESTION, THE NEWEST ANSWER WINNING FROM ANY ROUTE - AND NOTHING ONCE THE
# QUESTION IS CLOSED?
#
# T-0152, the founder on Q67 (2026-10-15): "On a phone it is easy to tap the wrong option." A change is an
# ordinary signed answer (channels/decisions/Channel.ps1; decisions/Rules.ps1, THE FOUNDER CHANGES HIS
# ANSWER), so it travels the answer's way: the same envelope, gate, journal and replay rules, the same
# needs-passkey refusal for an unlocked session's key, the same stale rule. This suite drives it over
# relays/local, in this process, with a phone held in memory (test/lib/RelayPhone.ps1), as
# test/test-relay-decisions-rank.ps1 drives the founder's other command. It attacks:
#   - ACCEPTED WHILE OPEN: a second answer from the phone is applied; the first stays in the record, the
#     second says it replaces it, and the next snapshot shows the phone the change;
#   - A FRESH PASSKEY ON A needsPasskey QUESTION: an unlocked session's change is refused as needs-passkey,
#     listed apart in the receipts, and the same change by a fresh passkey is applied; an item that names
#     no proof is looked at as a session's;
#   - THE NEWEST ANSWER WINS FROM ANY ROUTE: a change signed before his newer answer at the desk (the
#     window or the command line) is refused as superseded; one signed after it is applied;
#   - REFUSED BY NAME ONCE CLOSED: the exact sentence, nothing written, the receipt listing it refused;
#     the twin: a first answer to a closed question is still kept.
# Each refusal has its must-accept twin.
#
# EVERY HORDE HOME IS A FOLDER OF THE SUITE'S OWN under %TEMP% (CONTRIBUTING 9), never the real one, and
# every key is made with the software provider and removed at the end. Off Windows there is no key
# store: the suite says so and exits 3.

# Each refusal has its must-accept twin: the same envelope with the one thing put right is applied.
#
# EVERY HORDE HOME IS A FOLDER OF THE SUITE'S OWN under %TEMP% (CONTRIBUTING 9), never the real one, and
# every key is made with the software provider and removed at the end. Off Windows there is no key
# store: the suite says so and exits 3.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\FleetPin.ps1")
$fleetPin = Enter-HordeTestEmptyFleet
. (Join-Path $root "core\ModuleSettings.ps1")
. (Join-Path $root "channels\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
foreach ($f in @(Get-HordeRelayChannelFiles)) { . $f }
. (Join-Path $root "cli\RelayRun.ps1")
. (Join-Path $root "test\lib\RelayPhone.ps1")
Set-StrictMode -Version Latest
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + ")") -ForegroundColor DarkGray

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$script:homes = New-Object System.Collections.ArrayList
$script:worlds = New-Object System.Collections.ArrayList
$realHome = $env:HORDE_HOME

if ((Get-HordeRelayKeyStore).state -cne "known") {
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "no key store here: no machine identity can be made, so nothing was run" -PassCode 3
}

function New-Id { return [guid]::NewGuid().ToString("N") }
function New-TestHome {
    $h = Join-Path $env:TEMP ("horde-relay-change-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path (Join-Path $h "settings") -Force | Out-Null
    [void]$script:homes.Add($h)
    [System.IO.File]::WriteAllText((Join-Path $h "settings\relay.json"), '{"schemaVersion": 1, "settings": {"horde": "work"}}', $utf8)
    return $h
}
function Get-TestKeyNames {
    param([string]$HordeHome)
    $out = New-Object System.Collections.ArrayList
    $dir = Join-Path $HordeHome "relay\identity"
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter "machine-*.json")) {
        $m = [regex]::Match([System.IO.File]::ReadAllText($f.FullName), '"scope":"([a-z]+)","signName":"([a-z0-9-]+)".*"agreeName":"([a-z0-9-]+)"')
        if ($m.Success) { [void]$out.Add(@{ n = $m.Groups[2].Value; s = $m.Groups[1].Value }); [void]$out.Add(@{ n = $m.Groups[3].Value; s = $m.Groups[1].Value }) }
    }
    return @($out)
}
function Add-Question {
    param($World, [string]$Title)
    $q = Invoke-HordeDecision -Operation "add" -Root $World.store -Request @{ id = (New-Id); actor = "warchief"; question = @{ title = $Title; kind = "yes-no"; whatItIs = "A question for the change suite."; group = "voice"; askedBy = "Orc B" } }
    if ($q.state -cne "known" -or $q.value.outcome -cne "done") { throw ("the question was not added: " + $(if ($q.state -ceq "known") { $q.value.reason } else { $q.reason })) }
    return [int]$q.value.number
}
function New-World {
    # A machine with an identity and a decisions store of three open questions, a phone paired with its
    # identity key trusted, a local relay, a run context, and the first snapshot sent.
    $h = New-TestHome
    $env:HORDE_HOME = $h
    $id = New-HordeRelayMachineIdentity -HordeHome $h -Provider "software"
    if ($id.state -cne "known") { throw ("no identity: " + $id.reason) }
    $phone = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $h -Phone $phone)
    $v = New-HordeTestPhoneVouch -Phone $phone -Horde "work"
    $k = Add-HordeRelayPhoneKey -HordeHome $h -AgreePublic $phone.agreePublic -By $phone.keyId -AuthenticatorData $v.authenticatorData -ClientDataJson $v.clientDataJson -Signature $v.signature
    if ($k.state -cne "known") { throw ("no phone key: " + $k.reason) }
    $c = Connect-HordeRelay -Name "local" -Options @{ root = (Join-Path $h "relay-mailboxes") }
    if ($c.state -cne "known") { throw ("no relay: " + $c.reason) }
    $ctx = New-HordeRelayRunContext -HordeHome $h -Connection $c.value
    if ($ctx.state -cne "known") { throw ("no context: " + $ctx.reason) }
    $w = [pscustomobject]@{ home = $h; id = $id.value; phone = $phone; conn = $c.value; ctx = $ctx.value; store = (Join-Path $h "store\decisions"); agree = @(, ([byte[]]$id.value.agree.public)) }
    [void]$script:worlds.Add($w)
    foreach ($t in @("Should the closing sound play?", "Should the opening sound play?", "Should the alarm be louder?")) { [void](Add-Question $w $t) }
    $null = Invoke-HordeRelayChannelTicks -Context $w.ctx
    return $w
}
function Get-SentKey {
    # The replay key of the newest snapshot envelope this machine recorded as sent.
    param($World)
    $dir = Join-Path $World.home ("relay\journal\out\s-" + $World.id.sign.keyId + "\c-decisions")
    $newest = @(Get-ChildItem -LiteralPath $dir -Filter "*.rec" | Sort-Object Name | Select-Object -Last 1)
    return [regex]::Match([System.IO.File]::ReadAllText($newest[0].FullName), '"key":"([^"]+)"').Groups[1].Value
}
function Send-ToMachine {
    param($World, [string]$Text, [string]$Key = "-")
    if ($Key -ceq "-") { $Key = (Get-HordeRelayReplayKey -Header (Read-HordeRelayEnvelope -Text $Text).value.header) }
    return (Send-HordeRelayItem -Connection $World.conn -Mailbox $World.ctx.mailbox -Text $Text -Key $Key)
}
function Invoke-Turn {
    # One inbound turn: the mailbox read and journaled, every unfinished record handed over. { text }.
    param($World)
    $env:HORDE_HOME = $World.home
    $in = Receive-HordeRelayInbox -Context $World.ctx -TimeoutMs 0
    $un = Invoke-HordeRelayUnfinished -Context $World.ctx
    $lines = New-Object System.Collections.ArrayList
    if ($in.state -ceq "known") { foreach ($l in @($in.value.refused)) { [void]$lines.Add("refused " + $l) }; foreach ($l in @($in.value.held)) { [void]$lines.Add("held " + $l) } }
    else { [void]$lines.Add("inbox " + $in.state + ": " + $in.reason) }
    foreach ($l in @(Get-HordeRelayRunLines -Report $un.value)) { [void]$lines.Add($l) }
    return [pscustomobject]@{ text = (@($lines.ToArray()) -join " | ") }
}
function Has { param($Turn, [string]$Text) return [bool]($Turn.text.Contains($Text)) }
function Get-Records {
    # The records of one kind in a store, parsed, in order.
    param($World, [string]$Kind)
    if (-not (Test-Path -LiteralPath $World.store)) { return @() }
    return @(Get-ChildItem -LiteralPath $World.store -Filter "*.json" | Sort-Object Name | ForEach-Object { ConvertFrom-HordeJson ([System.IO.File]::ReadAllText($_.FullName, $utf8)) } | Where-Object { $_.kind -ceq $Kind })
}
function Get-Answer {
    # An answer envelope from -Phone (the world's) to the world's machine, signed at -Now (a UTC time) if given.
    param($World, [string]$AnswerId = "", [string]$Text = "Yes, play it.", [int]$Number = 1, $Now = $null)
    if ($AnswerId -ceq "") { $AnswerId = New-Id }
    $body = New-HordeTestPhoneAnswerBody -AnswerId $AnswerId -Text $Text -Number $Number -Machine $World.id.sign.keyId -Snapshot (Get-SentKey $World)
    return (New-HordeTestPhoneEnvelope -Phone $World.phone -Kind "answer" -Channel "decisions" -Body $body -To $World.agree -Now $Now)
}
function Send-Answer {
    param($World, [string]$Text, [int]$Number = 1, $Now = $null, [string]$AnswerId = "")
    $e = Get-Answer $World -Text $Text -Number $Number -Now $Now -AnswerId $AnswerId
    [void](Send-ToMachine $World $e.text)
    return (Invoke-Turn $World)
}
function Get-Said {
    # The founder's words under question -Number, in store order: { sequence; text; route; changedFrom }.
    param($World, [int]$Number)
    $q = (Invoke-HordeDecision -Operation "show" -Root $World.store -Request @{ number = $Number }).value.question
    return @($q.thread.messages | Where-Object { $_.speaker -ceq "founder" -and "$($_.act)" -eq "" } | ForEach-Object { [pscustomobject]@{ sequence = [long]$_.sequence; text = "$($_.text)"; route = "$($_.route)"; changedFrom = [long](Get-HordeTestMember $_ "changedFrom") } })
}
function Get-Receipt {
    # The newest receipts entry for the world's phone's passkey, as the channel sends it.
    param($World)
    return (@(ConvertFrom-HordeJson (Get-HordeDecisionsChannelReceipts -Context $World.ctx -Prefer @($World.phone.keyId)).text) | ForEach-Object { $_ } | Where-Object { "$(Get-HordeTestMember $_ 'from')" -ceq $World.phone.keyId } | Select-Object -First 1)
}
function Get-PhoneReceipt {
    # The receipt for the world's phone's passkey in the newest snapshot in the phone's mailbox, or $null.
    param($World)
    $r = Receive-HordeRelayItems -Connection $World.conn -Mailbox "work/phone" -Since 0
    $mail = @($r.value.items | ForEach-Object { $_.text })
    if ($mail.Count -eq 0) { return $null }
    $o = Open-HordeTestPhoneEnvelope -Phone $World.phone -Text $mail[$mail.Count - 1] -MachineSignPublic $World.id.sign.public
    if (-not $o.ok) { return $null }
    return [pscustomobject]@{ body = $o.body; mine = (@($o.body.receipts | Where-Object { $_.from -ceq $World.phone.keyId }) | Select-Object -First 1) }
}
$closedLine = "This question is closed - Orc B has acted on it. To change course, ask a follow-up."

try {
    Write-Host ""
    Write-Host "--- accepted while the question is open: a second answer is a change, and the phone is shown it ---" -ForegroundColor Cyan
    $W = New-World
    $t = Send-Answer $W "Option one." -Number 1
    $s = @(Get-Said $W 1)
    Check ((Has $t "done") -and $s.Count -eq 1 -and $s[0].text -ceq "Option one." -and $s[0].changedFrom -eq 0) ("CONTROL: his first answer from the phone lands, and is no change (" + $t.text + ")")
    $t = Send-Answer $W "Option two." -Number 1
    $s = @(Get-Said $W 1)
    Check ((Has $t "done") -and $s.Count -eq 2 -and $s[1].text -ceq "Option two." -and $s[1].changedFrom -eq $s[0].sequence -and $s[0].text -ceq "Option one.") ("his second answer from the phone is applied as a CHANGE: it replaces the first, which stays in the record (" + $t.text + ")")
    $null = Invoke-HordeRelayChannelTicks -Context $W.ctx
    $snap = Get-PhoneReceipt $W
    $q1 = @($snap.body.questions | Where-Object { [int]$_.number -eq 1 })[0]
    $ch = @(Get-HordeTestMember $q1 "answerChanges")
    Check ($ch.Count -eq 1 -and "$($ch[0].oldText)" -ceq "Option one." -and "$($ch[0].newText)" -ceq "Option two." -and "$($ch[0].orcShown)" -ceq "Orc B") "the next snapshot shows the phone the change: old words, new words, and which Orc is to confirm"
    $changedMessage = @($q1.thread.messages | Where-Object { [long](Get-HordeTestMember $_ "changedFrom") -ge 1 })
    Check ($changedMessage.Count -eq 1 -and "$($changedMessage[0].changedFromText)" -ceq "Option one.") "and the changed message says what it replaced"

    Write-Host ""
    Write-Host "--- the newest answer wins from any route: a change signed before a newer answer at the desk is refused ---" -ForegroundColor Cyan
    $D = New-World
    $t = Send-Answer $D "Phone one." -Number 1
    Check (Has $t "done") "CONTROL: his first answer lands"
    $desk = Invoke-HordeDecision -Operation "say" -Root $D.store -Request @{ id = (New-Id); actor = "founder"; number = 1; speaker = "founder"; route = "window"; text = "Desk answer."; wordingVersion = 1 }
    Check ($desk.value.outcome -ceq "done") "he answers at his desk (the window)"
    $t = Send-Answer $D "Phone older change." -Number 1 -Now ([datetime]::UtcNow.AddMinutes(-2))
    $s = @(Get-Said $D 1)
    Check ((Has $t "superseded") -and $s.Count -eq 2 -and $s[1].text -ceq "Desk answer.") ("a change from the phone signed BEFORE his answer at the desk is refused as superseded; the desk's stands (" + $t.text + ")")
    $t = Send-Answer $D "Phone newer change." -Number 1 -Now ([datetime]::UtcNow.AddSeconds(5))
    $s = @(Get-Said $D 1)
    Check ((Has $t "done") -and $s.Count -eq 3 -and $s[2].text -ceq "Phone newer change." -and $s[2].changedFrom -eq $s[1].sequence) ("MUST-ACCEPT TWIN: one signed after it is applied, and replaces the desk's (" + $t.text + ")")
    $cmd = Invoke-HordeDecision -Operation "say" -Root $D.store -Request @{ id = (New-Id); actor = "warchief"; number = 1; speaker = "founder"; route = "chat-recorded"; text = "Recorded from chat." }
    $t = Send-Answer $D "Phone stale change." -Number 1 -Now ([datetime]::UtcNow.AddMinutes(-2))
    Check ($cmd.value.outcome -ceq "done" -and (Has $t "superseded") -and @(Get-Said $D 1).Count -eq 4) ("and words the warchief recorded from chat stand over an older phone change too (" + $t.text + ")")

    Write-Host ""
    Write-Host "--- a needsPasskey question: a change takes a fresh passkey, as the first answer did ---" -ForegroundColor Cyan
    $U = New-World
    $np = Invoke-HordeDecision -Operation "add" -Root $U.store -Request @{ id = (New-Id); actor = "warchief"; needsPasskey = $true; question = @{ title = "Should the relay worker be deployed to production now?"; kind = "yes-no"; whatItIs = "A production deploy, for the change suite."; group = "relay"; askedBy = "Orc F" } }
    Check ($np.state -ceq "known" -and $np.value.outcome -ceq "done") "CONTROL: a question flagged needsPasskey is added"
    $nNp = [int]$np.value.number
    $null = Invoke-HordeRelayChannelTicks -Context $U.ctx
    $t = Send-Answer $U "Yes, deploy." -Number $nNp
    Check ((Has $t "done") -and @(Get-Said $U $nNp).Count -eq 1) ("CONTROL: the first answer, by a fresh passkey, is applied (" + $t.text + ")")
    $sess = New-HordeTestPhoneSession -Phone $U.phone -Machine $U.id.sign.keyId -NotBefore ([datetime]::UtcNow.AddMinutes(-10))
    $sendSession = {
        param($World, $Session, [byte[]]$Body, [switch]$WithVouch, $Now = $null)
        $e = New-HordeTestPhoneSessionEnvelope -Phone $World.phone -Session $Session -Kind "answer" -Channel "decisions" -Body $Body -To $World.agree -WithVouch:$WithVouch -Now $Now
        [void](Send-ToMachine $World $e.text)
        return (Invoke-Turn $World)
    }
    $changeId = New-Id
    $body = New-HordeTestPhoneAnswerBody -AnswerId $changeId -Text "No, do not deploy." -Number $nNp -Machine $U.id.sign.keyId -Snapshot (Get-SentKey $U)
    $t = & $sendSession $U $sess $body -WithVouch
    $rc = Get-Receipt $U
    Check ((Has $t "needs-passkey") -and @(Get-Said $U $nNp).Count -eq 1) ("MUST-REFUSE: a CHANGE signed by an unlocked session's key is refused as needs-passkey, and nothing is written (" + $t.text + ")")
    Check (@(Get-HordeTestMember $rc "session.needsPasskey") -ccontains $changeId -and @(Get-HordeTestMember $rc "refused") -cnotcontains $changeId) "the receipt lists it under session.needsPasskey, not as refused: the phone asks the passkey and sends it again"
    [void](Send-ToMachine $U (New-HordeTestPhoneEnvelope -Phone $U.phone -Kind "answer" -Channel "decisions" -Body $body -To $U.agree).text)
    $t = Invoke-Turn $U
    $s = @(Get-Said $U $nNp)
    $rc = Get-Receipt $U
    Check ((Has $t "done") -and $s.Count -eq 2 -and $s[1].text -ceq "No, do not deploy." -and $s[1].changedFrom -eq $s[0].sequence -and @(Get-HordeTestMember $rc "applied") -ccontains $changeId -and @(Get-HordeTestMember $rc "session.needsPasskey") -cnotcontains $changeId) ("MUST-ACCEPT TWIN: the same change by a fresh passkey is applied, as a change, and leaves the needsPasskey list (" + $t.text + ")")
    $bare = Invoke-HordeDecisionsChannelAccept -Context $U.ctx -Item ([pscustomobject]@{ from = $U.phone.keyId; channel = "decisions"; kind = "answer"; seq = 1; key = "x"; evidence = ""; ts = [long]([System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()); body = (New-HordeTestPhoneAnswerBody -AnswerId (New-Id) -Text "Bare." -Number $nNp -Machine $U.id.sign.keyId -Snapshot (Get-SentKey $U)) })
    Check ($bare.outcome -ceq "refused" -and "$($bare.reason)".StartsWith("needs-passkey:") -and @(Get-Said $U $nNp).Count -eq 2) ("a change whose item names no proof is refused on a needsPasskey question, as a session's (" + $bare.reason + ")")
    $t = & $sendSession $U $sess (New-HordeTestPhoneAnswerBody -AnswerId (New-Id) -Text "Session change on an ordinary question." -Number 1 -Machine $U.id.sign.keyId -Snapshot (Get-SentKey $U))
    Check ((Has $t "done") -and -not (Has $t "needs-passkey") -and @(Get-Said $U 1).Count -eq 1) ("CONTROL TWIN: an unlocked session's answer to an ordinary question is still applied - the passkey is asked only where the question says so (" + $t.text + ")")

    Write-Host ""
    Write-Host "--- refused by name once the question is closed ---" -ForegroundColor Cyan
    $C = New-World
    $t = Send-Answer $C "Before closing." -Number 1
    Check (Has $t "done") "CONTROL: his answer lands"
    $null = Invoke-HordeDecision -Operation "close" -Root $C.store -Request @{ id = (New-Id); actor = "warchief"; number = 1; outcome = "Done by hand." }
    $cid = New-Id
    $t = Send-Answer $C "After closing." -Number 1 -AnswerId $cid
    $rc = Get-Receipt $C
    Check ((Has $t "refused") -and (Has $t $closedLine) -and @(Get-Said $C 1).Count -eq 1) ("a change to a closed question is refused by name, with the sentence (" + $t.text + ")")
    Check (@(Get-HordeTestMember $rc "refused") -ccontains $cid) "and the receipt lists it refused"
    $t = Send-Answer $C "A first answer to a closed question." -Number 2
    $null = Invoke-HordeDecision -Operation "close" -Root $C.store -Request @{ id = (New-Id); actor = "warchief"; number = 3; outcome = "Dropped." }
    $t3 = Send-Answer $C "A first answer, late." -Number 3
    Check ((Has $t "done") -and (Has $t3 "done") -and @(Get-Said $C 3).Count -eq 1) ("MUST-ACCEPT TWIN: a FIRST answer to a closed question is no change, and is kept as it always was (" + $t3.text + ")")

} finally {
    $env:HORDE_HOME = $realHome
    foreach ($w in @($script:worlds)) { Close-HordeRelayRunContext -Context $w.ctx }
    $made = New-Object System.Collections.ArrayList
    foreach ($h in @($script:homes)) {
        foreach ($k in @(Get-TestKeyNames -HordeHome $h)) {
            [void]$made.Add($k)
            try { [void](Remove-HordeRelayKey -Name $k.n -Scope $k.s) } catch { Write-Host ("  cleanup of " + $k.n + " failed: " + $_.Exception.Message) -ForegroundColor Yellow }
        }
    }
    $left = @($made | Where-Object { (Find-HordeRelayCngKey -Name $_.n -Scope $_.s) -cne "" })
    Check ($made.Count -ge 2 -and $left.Count -eq 0) ("every key the suite's homes name is gone (" + $made.Count + " names, " + $left.Count + " left)")
    foreach ($h in @($script:homes)) {
        if ((Split-Path -Leaf $h) -match '^horde-relay-change-[0-9a-f]{32}$') { Remove-Item -LiteralPath $h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Check (@($script:homes | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 0) "every temporary home is gone"
    Exit-HordeTestEmptyFleet -Pin $fleetPin
}
Check ($env:HORDE_HOME -ceq $realHome) "HORDE_HOME is what it was"
Complete-HordeSuite -Success "a change of his answer from the phone takes what the first answer takes: a fresh passkey on a needsPasskey question, the newest answer from any route winning, and nothing at all once the question is closed"
