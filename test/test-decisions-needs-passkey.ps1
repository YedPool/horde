# DOES THE PC TAKE AN ANSWER TO A NEEDS-PASSKEY QUESTION ONLY WHEN ITS FRESH PASSKEY SIGNATURE IS
# PROVEN AGAIN HERE - AND DOES `horde decisions authorized` SAY YES ONLY THEN?
#
# The audit of 2026-10-16, item 17: the passkey rule for production actions was enforced only on the
# phone path, so `horde decisions answer N -Text yes` stood as the founder's answer to a production
# question. decisions/Operations.ps1 now refuses every answer of his to a question flagged needsPasskey
# unless channels/decisions/Answer.ps1 proves, from the relay journal's own record of the envelope, that a
# passkey trusted now signed exactly those words; and the operation authorized proves the standing answer
# again on every ask. Every rule is a must-refuse beside its must-accept twin, through the REAL code - the
# relay channel over relays/local, the journal, the trust store, the decisions list and the real `horde`
# CLI as a process of this suite's own shell:
#   refused                                              accepted
#   a local CLI answer (chat-recorded)                   a CLI answer to an ordinary question
#   a window answer                                      a window answer to an ordinary question
#   a session-signed answer (channel, and the store)     a passkey-signed answer through the channel
#   a request claiming a passkey with no envelope        the founder's act (park) and the keeper's note
#   a real passkey answer pointed at another question
#   or at other words
#   an item claiming webauthn that a session signed
#   an answer from a revoked device
# and authorized: exit 0 for a proven passkey answer; non-zero for a local answer, no answer, a question
# that is not there, a record written past the operations, a newer local answer, a reworded question and
# a revoked device - each with its reason in words.
#
# EVERY HORDE HOME IS A FOLDER OF THE SUITE'S OWN under %TEMP%, never the real one; every key is the
# software provider's, removed in the finally block. Nothing is posted to a session or a relay but the
# suite's own local one.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\FleetPin.ps1")
$fleetPin = Enter-HordeTestEmptyFleet
. (Join-Path $root "core\ModuleSettings.ps1")
. (Join-Path $root "core\JsonText.ps1")
. (Join-Path $root "channels\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
foreach ($f in @(Get-HordeRelayChannelFiles)) { . $f }
. (Join-Path $root "test\lib\RelayPhone.ps1")
. (Join-Path $root "test\lib\Cli.ps1")
Set-StrictMode -Version Latest
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + ")") -ForegroundColor DarkGray

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$script:homes = New-Object System.Collections.ArrayList
$script:worlds = New-Object System.Collections.ArrayList
$realHome = $env:HORDE_HOME
# The CLI runs under the shell this suite runs under, so a run under pwsh proves the command under 7.
$shell = $(if ("" + $PSVersionTable.PSEdition -ceq "Core") { "pwsh.exe" } else { "powershell.exe" })

if ((Get-HordeRelayKeyStore).state -cne "known") {
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "no key store here: no machine identity can be made, so nothing was run" -PassCode 3
}

function New-Id { return [guid]::NewGuid().ToString("N") }
function New-TestHome {
    $h = Join-Path $env:TEMP ("horde-needs-passkey-" + (New-Id))
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
function Add-PhoneTo {
    param($World)
    $p = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $World.home -Phone $p)
    $v = New-HordeTestPhoneVouch -Phone $p -Horde "work"
    $k = Add-HordeRelayPhoneKey -HordeHome $World.home -AgreePublic $p.agreePublic -By $p.keyId -AuthenticatorData $v.authenticatorData -ClientDataJson $v.clientDataJson -Signature $v.signature
    if ($k.state -cne "known") { throw ("no phone key: " + $k.reason) }
    return $p
}
function Add-Question {
    param($World, [string]$Title, [switch]$NeedsPasskey)
    $req = @{ id = (New-Id); actor = "warchief"; question = @{ title = $Title; kind = "yes-no"; whatItIs = "A question of the needs-passkey suite."; group = "relay"; askedBy = "orc-f" } }
    if ($NeedsPasskey) { $req["needsPasskey"] = $true }
    $a = Invoke-HordeDecision -Operation "add" -Root $World.store -Request $req
    if ($a.state -cne "known" -or $a.value.outcome -cne "done") { throw ("not added: " + $a.reason) }
    return [int]$a.value.number
}
function New-World {
    # A machine with a phone, a local relay, questions 1 (ordinary), 2, 3 and 4 (needsPasskey), and the
    # first look sent, so an answer has a snapshot to name.
    $h = New-TestHome
    $env:HORDE_HOME = $h
    $id = New-HordeRelayMachineIdentity -HordeHome $h -Provider "software"
    if ($id.state -cne "known") { throw ("no identity: " + $id.reason) }
    $c = Connect-HordeRelay -Name "local" -Options @{ root = (Join-Path $h "relay-mailboxes") }
    if ($c.state -cne "known") { throw ("no relay: " + $c.reason) }
    $ctx = New-HordeRelayRunContext -HordeHome $h -Connection $c.value
    if ($ctx.state -cne "known") { throw ("no context: " + $ctx.reason) }
    $w = [pscustomobject]@{ home = $h; phone = $null; conn = $c.value; ctx = $ctx.value; store = (Join-Path $h "store\decisions"); agree = @(, ([byte[]]$id.value.agree.public)); machine = $id.value.sign.keyId }
    [void]$script:worlds.Add($w)
    $w.phone = Add-PhoneTo -World $w
    [void](Add-Question $w "Should the closing sound play when the assistant closes?")
    [void](Add-Question $w "Should the new relay worker be deployed to production now?" -NeedsPasskey)
    [void](Add-Question $w "Should the old relay mailboxes be deleted now?" -NeedsPasskey)
    [void](Add-Question $w "Should the production budget be raised now?" -NeedsPasskey)
    $null = Invoke-HordeRelayChannelTicks -Context $w.ctx
    return $w
}
function Get-SentKey {
    param($World)
    $dir = Join-Path $World.home ("relay\journal\out\s-" + $World.machine + "\c-decisions")
    $newest = @(Get-ChildItem -LiteralPath $dir -Filter "*.rec" | Sort-Object Name | Select-Object -Last 1)
    return [regex]::Match([System.IO.File]::ReadAllText($newest[0].FullName), '"key":"([^"]+)"').Groups[1].Value
}
function Invoke-Turn {
    # One inbound turn: the mailbox read and journaled, every unfinished record handed over. { text }.
    param($World, [datetime]$At)
    $env:HORDE_HOME = $World.home
    $in = Receive-HordeRelayInbox -Context $World.ctx -TimeoutMs 0 -Now $At
    $un = Invoke-HordeRelayUnfinished -Context $World.ctx -Now $At
    $lines = New-Object System.Collections.ArrayList
    if ($in.state -ceq "known") { foreach ($l in @($in.value.refused)) { [void]$lines.Add("refused " + $l) }; foreach ($l in @($in.value.held)) { [void]$lines.Add("held " + $l) } }
    else { [void]$lines.Add("inbox " + $in.state + ": " + $in.reason) }
    foreach ($l in @($un.value.done)) { [void]$lines.Add("done " + $l) }
    foreach ($l in @($un.value.refused)) { [void]$lines.Add("refused " + $l) }
    foreach ($l in @($un.value.retry)) { [void]$lines.Add("retry " + $l) }
    return [pscustomobject]@{ text = (@($lines.ToArray()) -join " | ") }
}
function Send-Passkey {
    # A passkey-signed answer from -Phone, put and taken in one turn. { turn; envelope; answerId }.
    param($World, [int]$Number, [string]$Text, [datetime]$At, $Phone = $null, [string]$AnswerId = "")
    if ($null -eq $Phone) { $Phone = $World.phone }
    if ($AnswerId -ceq "") { $AnswerId = New-Id }
    $body = New-HordeTestPhoneAnswerBody -AnswerId $AnswerId -Number $Number -Text $Text -Machine $World.machine -Snapshot (Get-SentKey $World)
    $e = New-HordeTestPhoneEnvelope -Phone $Phone -Kind "answer" -Channel "decisions" -Body $body -To $World.agree -Now $At
    [void](Send-HordeRelayItem -Connection $World.conn -Mailbox $World.ctx.mailbox -Text $e.text -Key $e.key)
    return [pscustomobject]@{ turn = (Invoke-Turn $World $At); envelope = $e; answerId = $AnswerId }
}
function Get-Evidence {
    # The evidence of a received envelope: the hash of its journal record.
    param($World, $Envelope)
    $ev = Get-HordeRelayJournalEvidence -From $Envelope.header.from -Channel "decisions" -Seq ([long]$Envelope.header.seq) -HordeHome $World.home
    if ($ev.state -cne "known") { throw ("no evidence: " + $ev.reason) }
    return [string]$ev.value
}
function Get-Said {
    param($World)
    if (-not (Test-Path -LiteralPath $World.store)) { return @() }
    return @(Get-ChildItem -LiteralPath $World.store -Filter "*.json" | Sort-Object Name | ForEach-Object { ConvertFrom-HordeJson -Text ([System.IO.File]::ReadAllText($_.FullName, $utf8)) } | Where-Object { "$(Get-HordeTestMember $_ 'kind')" -ceq "message-said" })
}
function Test-Said { param($World, [string]$Text) return (@(Get-Said $World | Where-Object { "$(Get-HordeTestMember $_ 'data.text')" -ceq $Text }).Count -ge 1) }
function Get-StoreCount { param($World) return @(Get-ChildItem -LiteralPath $World.store -Filter "*.json").Count }
function Say {
    # A say request straight to the operations, as any caller in this process could make it.
    param($World, [hashtable]$Request)
    if (-not $Request.ContainsKey("id")) { $Request["id"] = New-Id }
    return (Invoke-HordeDecision -Operation "say" -Root $World.store -Request $Request)
}
function Test-RefusedWith { param($Answer, [string]$Like) return ($Answer.state -ceq "known" -and $Answer.value.outcome -ceq "refused" -and "$($Answer.value.reason)" -like $Like) }
function Invoke-Horde {
    param($World, [string[]]$HordeArgs)
    return (Invoke-HordeCliProcess -Root $root -HordeArgs $HordeArgs -Env @{ HORDE_HOME = $World.home } -Shell $shell)
}
function Authorized { param($World, [int]$Number) return (Invoke-HordeDecision -Operation "authorized" -Root $World.store -Request @{ number = $Number }) }
function Send-PasskeyBody {
    # A passkey-signed answer whose body the suite shapes - another machine, a snapshot this machine never
    # sent, a part - put and taken in one turn, now. { turn; envelope; id; evidence }: id is the request
    # id the channel makes from it, evidence the hash of its journal record.
    # -RawBody: the body's text exactly, in place of an answer.
    param($World, [int]$Number, [string]$Text, [string]$Machine = "", [string]$Snapshot = "", [string]$Part = "", [string]$RawBody = "")
    $aid = New-Id
    if ($Machine -ceq "") { $Machine = $World.machine }
    if ($Snapshot -ceq "") { $Snapshot = Get-SentKey $World }
    $at = [datetime]::UtcNow
    $body = New-HordeTestPhoneAnswerBody -AnswerId $aid -Number $Number -Text $Text -Machine $Machine -Snapshot $Snapshot -Part $Part
    if ($RawBody -cne "") { $body = $utf8.GetBytes($RawBody) }
    $e = New-HordeTestPhoneEnvelope -Phone $World.phone -Kind "answer" -Channel "decisions" -Body $body -To $World.agree -Now $at
    [void](Send-HordeRelayItem -Connection $World.conn -Mailbox $World.ctx.mailbox -Text $e.text -Key $e.key)
    $turn = Invoke-Turn $World $at
    return [pscustomobject]@{ turn = $turn; envelope = $e; id = (Get-HordeDecisionsChannelAnswerId -From $World.phone.keyId -AnswerId $aid); evidence = (Get-Evidence $World $e) }
}
function Say-Proven {
    # The request a caller in this process can make from a journaled passkey answer: its evidence, its
    # signer and its words, under -Id.
    param($World, $Sent, [int]$Number, [string]$Text, [string]$Id, [int]$Wording = 1)
    return (Say $World @{ id = $Id; actor = "founder"; number = $Number; speaker = "founder"; route = "phone"; text = $Text; wordingVersion = $Wording; evidence = $Sent.evidence; signedBy = $World.phone.keyId })
}

try {
    $T0 = [datetime]::UtcNow.AddSeconds(-2)
    $W = New-World

    Write-Host ""
    Write-Host "--- a local answer: refused on a needs-passkey question, taken on an ordinary one ---" -ForegroundColor Cyan
    $before = Get-StoreCount $W
    $cli = Invoke-Horde $W @("decisions", "answer", "2", "-Text", "Yes, deploy it.")
    Check ($cli.code -ne 0 -and $cli.out.Contains("question 2 needs the founder's passkey: ask him to answer it on his phone with Face ID") -and (Get-StoreCount $W) -eq $before -and -not (Test-Said $W "Yes, deploy it.")) ("MUST-REFUSE: horde decisions answer 2, the real CLI, is refused in words and writes nothing (exit " + $cli.code + ")")
    $cli = Invoke-Horde $W @("decisions", "answer", "1", "-Text", "Yes, play it.")
    Check ($cli.code -eq 0 -and (Test-Said $W "Yes, play it.")) ("MUST-ACCEPT TWIN: the same command on an ordinary question is kept (exit " + $cli.code + ")")
    $chat = Say $W @{ actor = "warchief"; number = 2; speaker = "founder"; route = "chat-recorded"; text = "He said yes in chat." }
    Check ((Test-RefusedWith $chat "*question 2 needs the founder's passkey*") -and -not (Test-Said $W "He said yes in chat.")) ("MUST-REFUSE: words recorded from chat, through the operation, are refused (" + $chat.value.reason + ")")
    $win = Say $W @{ actor = "founder"; number = 2; speaker = "founder"; route = "window"; text = "Yes from the window."; wordingVersion = 1 }
    Check ((Test-RefusedWith $win "*question 2 needs your passkey: answer it on your phone with Face ID*") -and -not (Test-Said $W "Yes from the window.")) ("MUST-REFUSE: a window answer is refused with the sentence the founder sees (" + $win.value.reason + ")")
    $winOk = Say $W @{ actor = "founder"; number = 1; speaker = "founder"; route = "window"; text = "Yes from the window, on question 1."; wordingVersion = 1 }
    Check ($winOk.state -ceq "known" -and $winOk.value.outcome -ceq "done") "MUST-ACCEPT TWIN: a window answer on an ordinary question is kept"
    $park = Say $W @{ actor = "founder"; number = 2; speaker = "founder"; route = "window"; text = "Later."; wordingVersion = 1; act = "park" }
    Check ($park.state -ceq "known" -and $park.value.outcome -ceq "done") ("an act of his (park) on a needs-passkey question answers nothing and is taken (" + $(if ($park.state -ceq "known") { $park.value.reason } else { $park.reason }) + ")")
    $unpark = Say $W @{ actor = "founder"; number = 2; speaker = "founder"; route = "window"; text = "Now."; wordingVersion = 1; act = "unpark" }
    $note = Say $W @{ actor = "warchief"; number = 2; speaker = "warchief"; route = "command"; text = "The deploy waits for your passkey."; asks = $false }
    Check ($unpark.value.outcome -ceq "done" -and $note.state -ceq "known" -and $note.value.outcome -ceq "done") "and the keeper's note under it is taken: only his answers need the passkey"

    Write-Host ""
    Write-Host "--- a request that claims a passkey ---" -ForegroundColor Cyan
    $fake = Say $W @{ actor = "founder"; number = 2; speaker = "founder"; route = "phone"; text = "Deploy."; wordingVersion = 1; evidence = ("ab" * 32); signedBy = $W.phone.keyId }
    Check ((Test-RefusedWith $fake "*needs your passkey*holds no envelope from that passkey with that evidence*") -and -not (Test-Said $W "Deploy.")) ("MUST-REFUSE: route phone with made-up evidence, naming the trusted passkey, is refused (" + $fake.value.reason + ")")
    # A real passkey answer to question 1, pointed at from a request for question 2.
    $real1 = Send-Passkey -World $W -Number 1 -Text "Yes, play it softly." -At $T0.AddMinutes(1)
    Check ((Test-Said $W "Yes, play it softly.") -and $real1.turn.text.Contains("done")) ("CONTROL: a passkey answer to the ordinary question 1 is applied (" + $real1.turn.text + ")")
    $ev1 = Get-Evidence $W $real1.envelope
    $id1 = Get-HordeDecisionsChannelAnswerId -From $W.phone.keyId -AnswerId $real1.answerId
    $moved = Say $W @{ id = (New-Id); actor = "founder"; number = 2; speaker = "founder"; route = "phone"; text = "Yes, play it softly."; wordingVersion = 1; evidence = $ev1; signedBy = $W.phone.keyId }
    Check (Test-RefusedWith $moved "*signed answer is to question 1, not 2*") ("MUST-REFUSE: a real passkey answer to question 1 cannot be pointed at from question 2 (" + $moved.value.reason + ")")

    Write-Host ""
    Write-Host "--- a passkey answer through the channel: applied, and authorized ---" -ForegroundColor Cyan
    $a0 = Authorized $W 2
    Check ((Test-RefusedWith $a0 "*question 2 has no answer of the founder's*")) ("authorized on a question with no answer of his is refused (" + $a0.value.reason + ")")
    $cli = Invoke-Horde $W @("decisions", "authorized", "2")
    Check ($cli.code -ne 0 -and $cli.out.Contains("has no answer of the founder's")) ("MUST-REFUSE: horde decisions authorized 2, the real CLI, exits non-zero with the reason (exit " + $cli.code + ")")
    $p2 = Send-Passkey -World $W -Number 2 -Text "Yes, deploy the relay worker." -At $T0.AddMinutes(2)
    Check ((Test-Said $W "Yes, deploy the relay worker.") -and $p2.turn.text.Contains("done")) ("MUST-ACCEPT: a passkey-signed answer to a needs-passkey question, through the channel, is applied (" + $p2.turn.text + ")")
    $cli = Invoke-Horde $W @("decisions", "authorized", "2")
    Check ($cli.code -eq 0 -and $cli.out.Contains("Question 2 is authorized") -and $cli.out.Contains($W.phone.keyId) -and $cli.out.Contains("Yes, deploy the relay worker.")) ("MUST-ACCEPT: horde decisions authorized 2, the real CLI, exits 0 and names the passkey and his words (exit " + $cli.code + ": " + $cli.out.Trim() + ")")
    $cli = Invoke-Horde $W @("decisions", "authorized", "2", "-Json")
    $j = $null; try { $j = ConvertFrom-HordeJson -Text ($cli.out.Trim() -split "`n")[0] } catch { $j = $null }
    Check ($cli.code -eq 0 -and $null -ne $j -and "$(Get-HordeTestMember $j 'value.outcome')" -ceq "done" -and "$(Get-HordeTestMember $j 'value.authorization.signedBy')" -ceq $W.phone.keyId -and [long](Get-HordeTestMember $j 'value.authorization.signedAt') -eq [long]$p2.envelope.header.ts) ("and -Json gives the authorization: the passkey and the envelope's own signed time (exit " + $cli.code + ")")
    $null = Say $W @{ actor = "founder"; number = 2; speaker = "founder"; route = "window"; text = "Aside for now."; wordingVersion = 1; act = "park" }
    $parked = Authorized $W 2
    Check ($parked.state -ceq "known" -and $parked.value.outcome -ceq "done" -and "$($parked.value.authorization.text)" -ceq "Yes, deploy the relay worker.") "an act of his after the answer (park) is no answer: the passkey answer still stands, and is authorized"
    $null = Say $W @{ actor = "founder"; number = 2; speaker = "founder"; route = "window"; text = "Back."; wordingVersion = 1; act = "unpark" }
    $ev2 = Get-Evidence $W $p2.envelope
    $id2 = Get-HordeDecisionsChannelAnswerId -From $W.phone.keyId -AnswerId $p2.answerId
    $other = Say $W @{ id = (New-Id); actor = "founder"; number = 2; speaker = "founder"; route = "phone"; text = "Yes, and delete the database too."; wordingVersion = 1; evidence = $ev2; signedBy = $W.phone.keyId }
    Check (Test-RefusedWith $other "*says other words*") ("MUST-REFUSE: the evidence of his real answer to question 2 under other words is refused (" + $other.value.reason + ")")
    $a1 = Authorized $W 1
    Check ($a1.state -ceq "known" -and $a1.value.outcome -ceq "done" -and "$($a1.value.authorization.text)" -ceq "Yes, play it softly.") "CONTROL TWIN: on question 1 his standing answer is the passkey one, and it is authorized"
    $later = Say $W @{ actor = "founder"; number = 1; speaker = "founder"; route = "window"; text = "Changed my mind at the desk."; wordingVersion = 1 }
    Check ($later.state -ceq "known" -and $later.value.outcome -ceq "done") "CONTROL: then he answers question 1 again in the window"
    $cli = Invoke-Horde $W @("decisions", "authorized", "1")
    Check ($cli.code -ne 0 -and $cli.out.Contains("typed in the window, and only his answer on his phone with Face ID authorizes it")) ("MUST-REFUSE: authorized 1 - his standing answer is now the one typed in the window - exits non-zero with the reason (exit " + $cli.code + ")")

    Write-Host ""
    Write-Host "--- a session-signed answer, and an item that claims a passkey a session signed ---" -ForegroundColor Cyan
    $s1 = New-HordeTestPhoneSession -Phone $W.phone -Machine $W.machine -NotBefore $T0 -Seq 1
    $aid = New-Id
    $sb = New-HordeTestPhoneAnswerBody -AnswerId $aid -Number 3 -Text "Delete them." -Machine $W.machine -Snapshot (Get-SentKey $W)
    $se = New-HordeTestPhoneSessionEnvelope -Phone $W.phone -Session $s1 -Kind "answer" -Channel "decisions" -Body $sb -To $W.agree -WithVouch -Now $T0.AddMinutes(3)
    [void](Send-HordeRelayItem -Connection $W.conn -Mailbox $W.ctx.mailbox -Text $se.text -Key $se.key)
    $t = Invoke-Turn $W $T0.AddMinutes(3)
    Check ($t.text.Contains("needs-passkey") -and -not (Test-Said $W "Delete them.")) ("MUST-REFUSE: a session-signed answer through the channel is refused as needs-passkey (" + $t.text + ")")
    $evS = Get-Evidence $W $se
    $idS = Get-HordeDecisionsChannelAnswerId -From $W.phone.keyId -AnswerId $aid
    $direct = Say $W @{ id = $idS; actor = "founder"; number = 3; speaker = "founder"; route = "phone"; text = "Delete them."; wordingVersion = 1; evidence = $evS; signedBy = $W.phone.keyId }
    Check ((Test-RefusedWith $direct "*signed by an unlocked session on the phone, not by a fresh passkey*") -and -not (Test-Said $W "Delete them.")) ("MUST-REFUSE: the list itself refuses the session-signed answer handed straight to it, with its real evidence and id (" + $direct.value.reason + ")")
    $claim = [pscustomobject]@{ from = $W.phone.keyId; channel = "decisions"; kind = "answer"; seq = [long]$se.header.seq; key = $se.key; evidence = $evS; ts = [long]$se.header.ts; body = [byte[]]$sb; proof = "webauthn"; vouchId = "" }
    $r = Invoke-HordeDecisionsChannelAccept -Context $W.ctx -Item $claim
    Check ($r.outcome -ceq "refused" -and "$($r.reason)" -like "*signed by an unlocked session*" -and -not (Test-Said $W "Delete them.")) ("MUST-REFUSE: an item that claims proof webauthn for a session-signed envelope is refused by the list (" + $r.reason + ")")

    Write-Host ""
    Write-Host "--- a record written past the operations ---" -ForegroundColor Cyan
    # Any caller in this process can write a record file itself. authorized does not trust the list: the
    # forged record is the standing answer, and it is proven again - and fails.
    $read = Read-HordeDecisionState -Root $W.store -Definitions (Get-HordeDecisionDefinitions)
    $seq = [long]$read.list.lastSequence + 1
    $forged = [ordered]@{ schemaVersion = 1; sequence = $seq; id = (New-Id); kind = "message-said"; at = [datetime]::UtcNow.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture); actor = "founder"; requestHash = ("0" * 64)
        data = [ordered]@{ number = 1; speaker = "founder"; route = "phone"; text = "Raise it."; wordingVersion = 1; evidence = $ev2; signedBy = $W.phone.keyId } }
    $made = Add-HordeDecisionRecord -Root $W.store -Sequence $seq -Text (ConvertTo-Json -InputObject $forged -Compress -Depth 8)
    $shown = Invoke-HordeDecision -Operation "show" -Root $W.store -Request @{ number = 1 }
    Check ($made -ceq "created" -and @($shown.value.question.thread.messages | Where-Object { $_.text -ceq "Raise it." -and $_.route -ceq "phone" }).Count -eq 1) "CONTROL: the forged record is in the list, as a phone answer naming the trusted passkey"
    $aF = Authorized $W 1
    Check (Test-RefusedWith $aF "*(record $seq) is not proven signed by a passkey this machine trusts*") ("MUST-REFUSE: authorized 1 proves the forged record again and refuses it (" + $aF.value.reason + ")")
    $forged2 = [ordered]@{ schemaVersion = 1; sequence = ($seq + 1); id = (New-Id); kind = "message-said"; at = [datetime]::UtcNow.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture); actor = "founder"; requestHash = ("0" * 64)
        data = [ordered]@{ number = 1; speaker = "founder"; route = "phone"; text = "Raise it again."; wordingVersion = 1 } }
    $made2 = Add-HordeDecisionRecord -Root $W.store -Sequence ($seq + 1) -Text (ConvertTo-Json -InputObject $forged2 -Compress -Depth 8)
    $aF2 = Authorized $W 1
    Check ($made2 -ceq "created" -and (Test-RefusedWith $aF2 "*it carries no evidence of a passkey signature*")) ("MUST-REFUSE: a forged phone record that names no evidence and no signer is refused for exactly that (" + $aF2.value.reason + ")")

    Write-Host ""
    Write-Host "--- passkey answers the channel never applied, handed straight to the list ---" -ForegroundColor Cyan
    $badSnapshot = $W.machine + "/decisions/999999/" + ("0" * 24)
    $e1 = Send-PasskeyBody -World $W -Number 4 -Text "Raise it by ten." -Snapshot $badSnapshot
    Check ($e1.turn.text.Contains("is not a snapshot this machine sent") -and -not (Test-Said $W "Raise it by ten.")) ("CONTROL: a passkey answer naming a snapshot this machine never sent is refused by the channel, and journaled (" + $e1.turn.text + ")")
    # The proof is read from the home of the store asked, not from HORDE_HOME: here HORDE_HOME names an
    # empty home, and the store's own journal still proves the answer.
    $env:HORDE_HOME = New-TestHome
    $ok1 = Say-Proven $W $e1 4 "Raise it by ten." $e1.id
    $okA = Authorized $W 4
    $env:HORDE_HOME = $W.home
    Check ($ok1.state -ceq "known" -and $ok1.value.outcome -ceq "done" -and (Test-Said $W "Raise it by ten.")) ("MUST-ACCEPT: his genuine passkey answer, handed to the list with its evidence and its own id, is taken - proven from the store's own home (" + $(if ($ok1.state -ceq "known") { $ok1.value.reason } else { $ok1.reason }) + ")")
    Check ($okA.state -ceq "known" -and $okA.value.outcome -ceq "done" -and "$($okA.value.authorization.text)" -ceq "Raise it by ten.") ("and authorized 4 says yes, from the same home (" + $(if ($okA.state -ceq "known") { $okA.value.reason } else { $okA.reason }) + ")")
    $no4 = Send-Passkey -World $W -Number 4 -Text "No, wait." -At ([datetime]::UtcNow)
    Check ((Test-Said $W "No, wait.") -and "$((Authorized $W 4).value.authorization.text)" -ceq "No, wait.") ("CONTROL: then he answers no by passkey, and that is the standing answer (" + $no4.turn.text + ")")
    $count = Get-StoreCount $W
    $replayNew = Say-Proven $W $e1 4 "Raise it by ten." (New-Id)
    Check ((Test-RefusedWith $replayNew "*its id is not the one made from the signed answer*") -and (Get-StoreCount $W) -eq $count) ("MUST-REFUSE: his old yes, handed over again under a new id to stand over his no, is refused (" + $replayNew.value.reason + ")")
    $replayOld = Say-Proven $W $e1 4 "Raise it by ten." $e1.id
    Check ($replayOld.state -ceq "known" -and $replayOld.value.outcome -ceq "replayed" -and (Get-StoreCount $W) -eq $count -and "$((Authorized $W 4).value.authorization.text)" -ceq "No, wait.") "and under its own id it is the first record answered again: nothing is written, and his no still stands"
    $e3 = Send-PasskeyBody -World $W -Number 4 -Text "Raise it from elsewhere." -Machine ("f" * 32)
    $m3 = Say-Proven $W $e3 4 "Raise it from elsewhere." $e3.id
    Check ($e3.turn.text.Contains("is for another machine") -and (Test-RefusedWith $m3 "*the signed answer is for another machine*")) ("MUST-REFUSE: his passkey answer to another machine's question 4 is refused here (" + $m3.value.reason + ")")
    $e4 = Send-PasskeyBody -World $W -Number 4 -Text "Raise it, part a." -Part "a"
    $m4 = Say-Proven $W $e4 4 "Raise it, part a." $e4.id
    Check (-not (Test-Said $W "Raise it, part a.") -and (Test-RefusedWith $m4 "*the signed answer is to another part*")) ("MUST-REFUSE: his answer to a part is not taken as one to the whole question (" + $m4.value.reason + ")")
    $e5 = Send-PasskeyBody -World $W -Number 4 -Text "Raise it by thirty." -Snapshot $badSnapshot
    $rec = Join-Path $W.home ("relay\journal\in\s-" + $W.phone.keyId + "\c-decisions\" + ([long]$e5.envelope.header.seq).ToString("D16", [System.Globalization.CultureInfo]::InvariantCulture) + ".rec")
    $raw = [System.IO.File]::ReadAllText($rec)
    $at = $raw.IndexOf('"signature":"') + 13 + 20
    $raw = $raw.Substring(0, $at) + $(if ($raw[$at] -ceq "A") { "B" } else { "A" }) + $raw.Substring($at + 1)
    [System.IO.File]::WriteAllText($rec, $raw, (New-Object System.Text.ASCIIEncoding))
    $tampered = [pscustomobject]@{ evidence = (Get-Evidence $W $e5.envelope) }
    $m5 = Say-Proven $W $tampered 4 "Raise it by thirty." $e5.id
    Check ($tampered.evidence -cne $e5.evidence -and (Test-RefusedWith $m5 "*does not verify and open here*")) ("MUST-REFUSE: a journal record whose signature was changed, under its new evidence, does not verify (" + $m5.value.reason + ")")
    $e6 = Send-PasskeyBody -World $W -Number 4 -Text "Raise it." -RawBody '{"v":1}'
    $m6 = Say-Proven $W $e6 4 "Raise it." $e6.id
    Check ((Test-RefusedWith $m6 "*its envelope holds no answer*")) ("MUST-REFUSE: a passkey-signed envelope whose body is no answer proves nothing (" + $m6.value.reason + ")")
    $e2 = Send-PasskeyBody -World $W -Number 4 -Text "Raise it by twenty." -Snapshot $badSnapshot
    $re4 = Invoke-HordeDecision -Operation "update" -Root $W.store -Request @{ id = (New-Id); actor = "warchief"; number = 4; changes = @{ title = "Should the production budget be doubled now?" } }
    $m2 = Say-Proven $W $e2 4 "Raise it by twenty." $e2.id -Wording 2
    Check ($re4.value.outcome -ceq "done" -and (Test-RefusedWith $m2 "*was given to wording 1, not 2*")) ("MUST-REFUSE: his answer to wording 1 is not taken as one to the reworded question (" + $m2.value.reason + ")")

    Write-Host ""
    Write-Host "--- a revoked device ---" -ForegroundColor Cyan
    $B = Add-PhoneTo -World $W
    $null = Invoke-HordeRelayChannelTicks -Context $W.ctx
    $pB = Send-Passkey -World $W -Phone $B -Number 3 -Text "Yes, delete the old mailboxes." -At $T0.AddMinutes(5)
    Check ((Test-Said $W "Yes, delete the old mailboxes.") -and (Authorized $W 3).value.outcome -ceq "done") ("CONTROL TWIN: a second trusted phone's passkey answer is applied and authorized (" + $pB.turn.text + ")")
    [void](Revoke-HordeRelayTrust -HordeHome $W.home -Subject "device" -Id $B.deviceId -Reason "phone lost")
    $a3 = Authorized $W 3
    Check (Test-RefusedWith $a3 "*not trusted on this machine now*") ("MUST-REFUSE: once the device is revoked, its answer authorizes nothing (" + $a3.value.reason + ")")
    $evB = Get-Evidence $W $pB.envelope
    $idB = Get-HordeDecisionsChannelAnswerId -From $B.keyId -AnswerId $pB.answerId
    $again = Say $W @{ id = (New-Id); actor = "founder"; number = 3; speaker = "founder"; route = "phone"; text = "Yes, delete the old mailboxes."; wordingVersion = 1; evidence = $evB; signedBy = $B.keyId }
    Check (Test-RefusedWith $again "*not trusted on this machine now*") ("MUST-REFUSE: the revoked device's real answer handed to the list again is refused (" + $again.value.reason + ")")

    Write-Host ""
    Write-Host "--- the wording moves on ---" -ForegroundColor Cyan
    $upd = Invoke-HordeDecision -Operation "update" -Root $W.store -Request @{ id = (New-Id); actor = "warchief"; number = 2; changes = @{ title = "Should the new relay worker AND the database migration be deployed now?" } }
    Check ($upd.state -ceq "known" -and $upd.value.outcome -ceq "done") "CONTROL: question 2 is reworded"
    $a2 = Authorized $W 2
    Check (Test-RefusedWith $a2 "*given to wording 1, and the question is now at wording 2*") ("MUST-REFUSE: an answer to the old wording authorizes nothing (" + $a2.value.reason + ")")
    $none = Invoke-Horde $W @("decisions", "authorized", "99")
    Check ($none.code -ne 0 -and $none.out.Contains("there is no question 99")) ("authorized on a question that is not there exits non-zero (exit " + $none.code + ")")
} finally {
    Exit-HordeTestEmptyFleet -Pin $fleetPin
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
        if ((Split-Path -Leaf $h) -match '^horde-needs-passkey-[0-9a-f]{32}$') { Remove-Item -LiteralPath $h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Check (@($script:homes | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 0) "every temporary home is gone"
}
Check ($env:HORDE_HOME -ceq $realHome) "HORDE_HOME is what it was"
Complete-HordeSuite -Success "an answer to a needs-passkey question stands only when its passkey signature is proven again here, and authorized says yes only then"
