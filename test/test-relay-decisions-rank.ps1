# DOES A CHANGE OF RANK FROM THE FOUNDER'S PHONE LAND EXACTLY AS AN ANSWER DOES - SIGNED, ONCE, ONLY ON A
# QUESTION STILL ON HIS LIST, NEVER OVER A NEWER CHANGE - AND NOTHING ELSE LAND AT ALL?
#
# The founder, 2026-10-14: "I want to be able to change importance level and blockingness level by
# clicking on a little button next to a decision to change it". From the phone the change is a COMMAND,
# sent like an answer (channels/decisions/Channel.ps1, A CHANGE OF RANK FROM THE PHONE): an envelope of
# kind rank on the decisions channel, signed by his passkey, through the same gate, journal and replay
# rules. This suite drives it over relays/local, in this process, with a phone held in memory
# (test/lib/RelayPhone.ps1), as test/test-relay-channels.ps1 drives answers. It attacks:
#   - TRUST: unsigned, signed by another passkey, from a passkey never paired or since revoked - refused,
#     nothing ranked;
#   - ONCE: the same envelope put again, a re-signed copy, the same rankId in a new envelope - one record;
#   - ONLY HIS LIST: a closed question, an answered one, one that is not there, another machine's, a
#     snapshot this machine never sent - refused by name;
#   - THE WORDS: a level that is none of the rules' list, a member added or missing - refused;
#   - A STALE RANK NEVER WINS: older than a newer rank from the command line, or the window - refused;
#     two taps on the phone, delivered late, stand in the order he made them, across a restart too;
#   - NEVER AN ANSWER: a rank body sent as an answer, and an answer body sent as a rank, change nothing;
#     a kind the channel does not name is refused by name.
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
    $h = Join-Path $env:TEMP ("horde-relay-rank-" + [guid]::NewGuid().ToString("N"))
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
    $q = Invoke-HordeDecision -Operation "add" -Root $World.store -Request @{ id = (New-Id); actor = "warchief"; question = @{ title = $Title; kind = "yes-no"; whatItIs = "A question for the rank suite."; group = "voice"; askedBy = "orc-b" } }
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
function Get-Words {
    # A question's two words, as "importance/blocks".
    param($World, [int]$Number)
    $q = (Invoke-HordeDecision -Operation "show" -Root $World.store -Request @{ number = $Number }).value.question
    return ("" + $q.importance + "/" + $q.blocks)
}
function Get-RankBody {
    # A change of rank as the phone makes it, or exactly -Json ({machine} and {snapshot} filled in).
    param($World, [string]$RankId = "", [int]$Number = 1, [string]$Which = "importance", [string]$Level = "high", [string]$Json = "", [string]$Machine = "", [string]$Snapshot = "")
    if ($RankId -ceq "") { $RankId = New-Id }
    if ($Machine -ceq "") { $Machine = $World.id.sign.keyId }
    if ($Snapshot -ceq "") { $Snapshot = Get-SentKey $World }
    if ($Json -ceq "") { $Json = '{"v":1,"rankId":"' + $RankId + '","machine":"{machine}","snapshot":"{snapshot}","number":' + $Number + ',"' + $Which + '":"' + $Level + '"}' }
    return ,($utf8.GetBytes($Json.Replace("{machine}", $Machine).Replace("{snapshot}", $Snapshot)))
}
function Get-Rank {
    # A rank envelope from -Phone (the world's) to the world's machine, signed at -Now (a UTC time) if given.
    param($World, [byte[]]$Body = $null, $Phone = $null, $Now = $null, [string]$Kind = "rank", [string]$From = "")
    if ($null -eq $Phone) { $Phone = $World.phone }
    if ($null -eq $Body) { $Body = Get-RankBody $World }
    return (New-HordeTestPhoneEnvelope -Phone $Phone -Kind $Kind -Channel "decisions" -Body $Body -To $World.agree -Now $Now -From $From)
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

try {
    Write-Host ""
    Write-Host "--- a signed change of rank is applied once, as the founder's, and the phone is told ---" -ForegroundColor Cyan
    $W = New-World
    $snap = Get-PhoneReceipt $W
    Check ($null -ne $snap -and $null -ne $snap.body.PSObject.Properties["ranks"] -and $snap.body.ranks -eq 1) "CONTROL: the snapshot says this machine takes a change of rank from the phone (ranks: 1)"
    Check ((Get-Words $W 1) -ceq "normal/part") "CONTROL: question 1 stands at the defaults"
    $rid = New-Id
    $e1 = Get-Rank $W -Body (Get-RankBody $W -RankId $rid -Level "high")
    [void](Send-ToMachine $W $e1.text)
    $t = Invoke-Turn $W
    $ranked = @(Get-Records $W "question-ranked")
    $idHash = Get-HordeRelaySha256 -Bytes ([System.Text.Encoding]::ASCII.GetBytes("horde-relay/decisions/v1 rank id`n" + $W.phone.keyId + "`n" + $rid))
    Check ((Has $t "done") -and (Get-Words $W 1) -ceq "high/part" -and $ranked.Count -eq 1 -and $ranked[0].actor -ceq "founder" -and $ranked[0].data.importance -ceq "high") ("a signed change of rank lands: question 1 is high, in one ranking record of the founder's (" + $t.text + ")")
    Check ($ranked[0].id -ceq (@($idHash[0..15] | ForEach-Object { $_.ToString("x2") }) -join "")) "its id is the first 16 bytes of SHA-256 of the RANK domain, the sender and the rankId"
    $null = Invoke-HordeRelayChannelTicks -Context $W.ctx
    $rc = Get-PhoneReceipt $W
    Check ($null -ne $rc -and $null -ne $rc.mine -and @($rc.mine.applied) -ccontains $rid -and @($rc.body.questions | Where-Object { [int]$_.number -eq 1 })[0].importance -ceq "high") "the next snapshot shows the new level, and its receipt lists the change as applied"
    Write-Host ""
    Write-Host "--- once: the same envelope, a re-signed copy, the same rankId again ---" -ForegroundColor Cyan
    [void](Send-ToMachine $W $e1.text)
    $t = Invoke-Turn $W
    Check (@(Get-Records $W "question-ranked").Count -eq 1) ("the same envelope put again is still one change (" + $t.text + ")")
    $re = New-HordeTestPhoneResigned -Phone $W.phone -Envelope $e1
    [void](Send-ToMachine $W $re (Get-HordeRelayContentKey -Text $re))
    $t = Invoke-Turn $W
    Check ((Has $t "replay") -and @(Get-Records $W "question-ranked").Count -eq 1) ("a re-signed copy is refused by the journal as a replay (" + $t.text + ")")
    [void](Send-ToMachine $W (Get-Rank $W -Body (Get-RankBody $W -RankId $rid -Level "high")).text)
    $t = Invoke-Turn $W
    Check ((Has $t "(replayed)") -and @(Get-Records $W "question-ranked").Count -eq 1) ("the same rankId in a new envelope is the first record answered again (" + $t.text + ")")
    [void](Send-ToMachine $W (Get-Rank $W -Body (Get-RankBody $W -Which "blocks" -Level "all")).text)
    $t = Invoke-Turn $W
    Check ((Has $t "done") -and (Get-Words $W 1) -ceq "high/all") ("MUST-ACCEPT: a new tap on the Blocking button is applied, and leaves the importance alone (" + $t.text + ")")

    Write-Host ""
    Write-Host "--- trust: unsigned, forged, never paired, revoked ---" -ForegroundColor Cyan
    $before = @(Get-Records $W "question-ranked").Count
    # UNSIGNED: the envelope's own signature taken out and one the passkey made over something else put in
    # its place - a signature in every way but the one that matters.
    $e = Get-Rank $W -Body (Get-RankBody $W -Number 2 -Level "low")
    $real = [regex]::Match($e.text, '"signature":"([^"]+)"').Groups[1].Value
    $other = ConvertTo-HordeRelayBase64Url -Bytes (New-HordeTestPhoneAssertion -Phone $W.phone -Challenge (Get-HordeRelayRandomBytes -Count 32)).signature
    Check ($real -cne "" -and $e.text.Contains('"signature":"' + $real + '"')) "CONTROL: the envelope's signature is found where it is replaced"
    [void](Send-ToMachine $W ($e.text.Replace('"signature":"' + $real + '"', '"signature":"' + $other + '"')) $e.key)
    $t = Invoke-Turn $W
    Check ((Has $t "does not verify") -and @(Get-Records $W "question-ranked").Count -eq $before -and (Get-Words $W 2) -ceq "normal/part") ("an envelope whose signature is not over it is refused, and nothing is ranked (" + $t.text + ")")
    $nobody = New-HordeTestPhone
    [void](Send-ToMachine $W (Get-Rank $W -Body (Get-RankBody $W -Number 2 -Level "low") -Phone $nobody -From $W.phone.keyId).text)
    $t = Invoke-Turn $W
    Check ((Has $t "does not verify") -and (Get-Words $W 2) -ceq "normal/part") ("a change that names the founder's passkey and is signed by another is refused (" + $t.text + ")")
    [void](Send-ToMachine $W (Get-Rank $W -Body (Get-RankBody $W -Number 2 -Level "low") -Phone $nobody).text)
    $t = Invoke-Turn $W
    Check ((Has $t "no trusted sender has the key") -and (Get-Words $W 2) -ceq "normal/part") ("a change from a passkey never paired is refused (" + $t.text + ")")
    [void](Send-ToMachine $W (Get-Rank $W -Body (Get-RankBody $W -Number 2 -Level "low")).text)
    $t = Invoke-Turn $W
    Check ((Has $t "done") -and (Get-Words $W 2) -ceq "low/part") ("MUST-ACCEPT: the same change from his own trusted passkey is applied (" + $t.text + ")")

    Write-Host ""
    Write-Host "--- only a question still on his list ---" -ForegroundColor Cyan
    $null = Invoke-HordeDecision -Operation "close" -Root $W.store -Request @{ id = (New-Id); actor = "warchief"; number = 3; outcome = "Done." }
    [void](Send-ToMachine $W (Get-Rank $W -Body (Get-RankBody $W -Number 3 -Level "high")).text)
    $t = Invoke-Turn $W
    Check ((Has $t "question 3 is closed") -and (Get-Words $W 3) -ceq "normal/part") ("a closed question is not ranked, and the refusal says so (" + $t.text + ")")
    $null = Invoke-HordeDecision -Operation "say" -Root $W.store -Request @{ id = (New-Id); actor = "founder"; number = 2; speaker = "founder"; route = "window"; text = "No."; wordingVersion = 1 }
    [void](Send-ToMachine $W (Get-Rank $W -Body (Get-RankBody $W -Number 2 -Level "high")).text)
    $t = Invoke-Turn $W
    Check ((Has $t "question 2 is answered") -and (Get-Words $W 2) -ceq "low/part") ("a question he has answered has left his list, and is not ranked (" + $t.text + ")")
    [void](Send-ToMachine $W (Get-Rank $W -Body (Get-RankBody $W -Number 9 -Level "high")).text)
    $t = Invoke-Turn $W
    Check ((Has $t "no question 9")) ("a question that is not there is refused by its number (" + $t.text + ")")
    $n4 = Add-Question $W "Should the chime be shorter?"
    $null = Invoke-HordeRelayChannelTicks -Context $W.ctx
    [void](Send-ToMachine $W (Get-Rank $W -Body (Get-RankBody $W -Number $n4 -Level "high")).text)
    $t = Invoke-Turn $W
    Check ((Has $t "done") -and (Get-Words $W $n4) -ceq "high/part") ("MUST-ACCEPT: an open question that is still his turn is ranked (" + $t.text + ")")
    [void](Send-ToMachine $W (Get-Rank $W -Body (Get-RankBody $W -Number $n4 -Level "low" -Machine ("ab" * 16))).text)
    $t = Invoke-Turn $W
    Check ((Has $t "is for another machine") -and (Get-Words $W $n4) -ceq "high/part") ("a change made for another machine is refused (" + $t.text + ")")
    $own = Get-SentKey $W
    [void](Send-ToMachine $W (Get-Rank $W -Body (Get-RankBody $W -Number $n4 -Level "low" -Snapshot ($own.Substring(0, $own.Length - 1) + $(if ($own.EndsWith("0")) { "1" } else { "0" })))).text)
    $t = Invoke-Turn $W
    Check ((Has $t "is not a snapshot this machine sent") -and (Get-Words $W $n4) -ceq "high/part") ("a change naming a snapshot this machine never sent is refused (" + $t.text + ")")

    Write-Host ""
    Write-Host "--- the words: only the rules' own, and only a change of rank's members ---" -ForegroundColor Cyan
    foreach ($case in @(
        @{ json = '{"v":1,"rankId":"' + (New-Id) + '","machine":"{machine}","snapshot":"{snapshot}","number":' + $n4 + ',"importance":"urgent"}'; says = "importance is not one of"; what = "an importance that is none of the list's" },
        @{ json = '{"v":1,"rankId":"' + (New-Id) + '","machine":"{machine}","snapshot":"{snapshot}","number":' + $n4 + ',"blocks":"some"}'; says = "blocks is not one of"; what = "a blocking that is none of the list's" },
        @{ json = '{"v":1,"rankId":"' + (New-Id) + '","machine":"{machine}","snapshot":"{snapshot}","number":' + $n4 + '}'; says = "one or both of importance, blocks"; what = "a change that names neither word" },
        @{ json = '{"v":1,"rankId":"' + (New-Id) + '","machine":"{machine}","snapshot":"{snapshot}","number":' + $n4 + ',"importance":"low","title":"x"}'; says = "the change of rank's members are"; what = "a change with a member no change has" },
        @{ json = '{"v":2,"rankId":"' + (New-Id) + '","machine":"{machine}","snapshot":"{snapshot}","number":' + $n4 + ',"importance":"low"}'; says = "not a version this machine reads"; what = "a version this machine does not read" },
        @{ json = '{"v":1,"rankId":"' + (New-Id) + '","rankId":"' + (New-Id) + '","machine":"{machine}","snapshot":"{snapshot}","number":' + $n4 + ',"importance":"low"}'; says = "more than once"; what = "a member given twice" })) {
        [void](Send-ToMachine $W (Get-Rank $W -Body (Get-RankBody $W -Json $case.json)).text)
        $t = Invoke-Turn $W
        Check ((Has $t $case.says) -and (Get-Words $W $n4) -ceq "high/part") ($case.what + " is refused by name, and nothing is ranked (" + $t.text + ")")
    }
    [void](Send-ToMachine $W (Get-Rank $W -Body (Get-RankBody $W -Json ('{"v":1,"rankId":"' + (New-Id) + '","machine":"{machine}","snapshot":"{snapshot}","number":' + $n4 + ',"importance":"low","blocks":"none"}'))).text)
    $t = Invoke-Turn $W
    Check ((Has $t "done") -and (Get-Words $W $n4) -ceq "low/none") ("MUST-ACCEPT: both words of the lists, in one change, are applied (" + $t.text + ")")

    Write-Host ""
    Write-Host "--- never an answer, and an answer never a rank ---" -ForegroundColor Cyan
    $saidBefore = @(Get-Records $W "message-said").Count
    $rankedBefore = @(Get-Records $W "question-ranked").Count
    [void](Send-ToMachine $W (Get-Rank $W -Kind "answer" -Body (Get-RankBody $W -Number $n4 -Level "high")).text)
    $t = Invoke-Turn $W
    Check ((Has $t "answer's members are") -and @(Get-Records $W "message-said").Count -eq $saidBefore -and @(Get-Records $W "question-ranked").Count -eq $rankedBefore) ("a change of rank sent as an answer is refused as no answer, and changes nothing (" + $t.text + ")")
    $answerBody = New-HordeTestPhoneAnswerBody -Number $n4 -Text "high" -Machine $W.id.sign.keyId -Snapshot (Get-SentKey $W)
    [void](Send-ToMachine $W (Get-Rank $W -Kind "rank" -Body $answerBody).text)
    $t = Invoke-Turn $W
    Check ((Has $t "change of rank's members are") -and @(Get-Records $W "message-said").Count -eq $saidBefore -and @(Get-Records $W "question-ranked").Count -eq $rankedBefore) ("an answer sent as a change of rank is refused as no change, and changes nothing (" + $t.text + ")")
    $odd = Invoke-HordeDecisionsChannelAccept -Context $W.ctx -Item ([pscustomobject]@{ from = $W.phone.keyId; channel = "decisions"; kind = "follow"; seq = 1; key = "x"; evidence = ""; ts = [long]0; body = (Get-RankBody $W -Number $n4) })
    Check ($odd.outcome -ceq "refused" -and $odd.reason.Contains("not a follow")) ("a kind the channel does not name is refused by name, whatever its body (" + $odd.reason + ")")
    [void](Send-ToMachine $W (Get-Rank $W -Kind "follow" -Body (Get-RankBody $W -Number $n4)).text)
    $t = Invoke-Turn $W
    Check ((Has $t "takes answer, rank, not follow") -and @(Get-Records $W "question-ranked").Count -eq $rankedBefore) ("and the gate refuses it before the journal (" + $t.text + ")")

    Write-Host ""
    Write-Host "--- a stale rank never wins ---" -ForegroundColor Cyan
    $S = New-World
    $null = Invoke-HordeDecision -Operation "rank" -Root $S.store -Request @{ id = (New-Id); actor = "warchief"; number = 1; importance = "low" }
    [void](Send-ToMachine $S (Get-Rank $S -Body (Get-RankBody $S -Level "high") -Now ([datetime]::UtcNow.AddMinutes(-5))).text)
    $t = Invoke-Turn $S
    Check ((Has $t "superseded") -and (Get-Words $S 1) -ceq "low/part") ("a change signed before a newer rank from the command line is refused as superseded; the newer one stands (" + $t.text + ")")
    $null = Invoke-HordeRelayChannelTicks -Context $S.ctx
    $rc = Get-PhoneReceipt $S
    Check ($null -ne $rc.mine -and @($rc.mine.refused).Count -eq 1) "and the receipt lists it refused"
    [void](Send-ToMachine $S (Get-Rank $S -Body (Get-RankBody $S -Level "high") -Now ([datetime]::UtcNow.AddSeconds(1))).text)
    $t = Invoke-Turn $S
    Check ((Has $t "done") -and (Get-Words $S 1) -ceq "high/part") ("MUST-ACCEPT: a change signed after it is applied (" + $t.text + ")")
    # THE WINDOW'S CHANGE, THEN THE PHONE'S OLDER ONE (the founder at his desk, his phone behind).
    . (Join-Path $root "decisions\Window.ps1")
    $env:HORDE_HOME = $S.home
    $desk = Invoke-HordeDecisionWindowRank -Arguments @{ number = 2; which = "blocks"; level = "all"; id = (New-Id) } -Invoke { param($Request) return (Invoke-HordeDecision -Operation "rank" -Request $Request -Root $S.store) }
    [void](Send-ToMachine $S (Get-Rank $S -Body (Get-RankBody $S -Number 2 -Which "blocks" -Level "none") -Now ([datetime]::UtcNow.AddMinutes(-2))).text)
    $t = Invoke-Turn $S
    Check ($desk.ok -and (Has $t "superseded") -and (Get-Words $S 2) -ceq "normal/all") ("a change at the window, then the phone's older one: the phone's is superseded, and his change at the desk stands (" + $t.text + ")")
    # TWO TAPS ON THE PHONE, DELIVERED LATE, STAND IN HIS ORDER: the first is recorded AFTER the second
    # was signed (both were signed seconds ago), and must not make the second look stale - its own
    # signing time, kept in the ledger, is what counts, not when the store recorded it.
    $t0 = [datetime]::UtcNow
    $first = Get-Rank $S -Body (Get-RankBody $S -Number 3 -Which "importance" -Level "high") -Now ($t0.AddSeconds(-6))
    $second = Get-Rank $S -Body (Get-RankBody $S -Number 3 -Which "importance" -Level "low") -Now ($t0.AddSeconds(-4))
    [void](Send-ToMachine $S $first.text)
    [void](Send-ToMachine $S $second.text)
    $t = Invoke-Turn $S
    Check (-not (Has $t "superseded") -and (Get-Words $S 3) -ceq "low/part") ("two taps signed a moment apart and applied late both land, the later one standing (" + $t.text + ")")
    # ACROSS A RESTART: the ledger's signing times are read back from the file. A change signed after his
    # second tap - but before the store recorded it - is applied: only the ledger can say it is newer.
    $S.ctx = (New-HordeRelayRunContext -HordeHome $S.home -Connection $S.conn).value
    [void](Send-ToMachine $S (Get-Rank $S -Body (Get-RankBody $S -Number 3 -Which "blocks" -Level "none") -Now ($t0.AddSeconds(-3))).text)
    $t = Invoke-Turn $S
    Check ((Has $t "done") -and (Get-Words $S 3) -ceq "low/none") ("after a restart, a change signed after his last tap is applied, by the signing time the ledger kept (" + $t.text + ")")
    [void](Send-ToMachine $S (Get-Rank $S -Body (Get-RankBody $S -Number 3 -Which "importance" -Level "normal") -Now ($t0.AddSeconds(-5))).text)
    $t = Invoke-Turn $S
    Check ((Has $t "superseded") -and (Get-Words $S 3) -ceq "low/none") ("and one signed between his two taps is older than the second, and is refused (" + $t.text + ")")
    $file = ConvertFrom-HordeJson ([System.IO.File]::ReadAllText((Join-Path $S.home "relay\decisions\receipts.json")))
    Check (@($file.ranked).Count -ge 3 -and @($file.ranked | Where-Object { "$($_.evidence)" -cmatch '\A[0-9a-f]{64}\z' }).Count -eq @($file.ranked).Count) "the ledger keeps each phone change's signing time and the hash of the journal record that proved it"

    Write-Host ""
    Write-Host "--- the ledger survives save and read whole (review of PR 303, item 1) ---" -ForegroundColor Cyan
    # Whichever of two branches that rewrite the ledger merges second must keep the other's members: this
    # holds the ranked entries and the receipts' lists to a save and a read, member by member.
    $held = Get-HordeDecisionsChannelLedger -Context $S.ctx
    $flat = { param($L) (@($L.ranked.Keys | ForEach-Object { $_ + "=" + $L.ranked[$_].at + "/" + $L.ranked[$_].evidence + "/" + $L.ranked[$_].proof }) -join ";") + "|" + (@($L.streams.Keys | Sort-Object | ForEach-Object { $_ + ":" + (@($L.streams[$_].applied) -join ",") + ":" + (@($L.streams[$_].refused) -join ",") }) -join ";") }
    $before = & $flat $held
    Check ((Save-HordeDecisionsChannelLedger -Context $S.ctx) -ceq "") "CONTROL: the ledger is saved"
    $back = New-HordeRelayRunContext -HordeHome $S.home -Connection $S.conn
    $after = & $flat (Get-HordeDecisionsChannelLedger -Context $back.value)
    Close-HordeRelayRunContext -Context $back.value
    Check (@($held.ranked.Keys).Count -ge 4 -and @($held.ranked.Values | Where-Object { $_.proof -ceq "webauthn" }).Count -eq @($held.ranked.Keys).Count -and $after -ceq $before) ("a ledger holding ranked entries (time, evidence, proof) and receipts reads back exactly as it was saved (" + $before.Length + " characters)")

    Write-Host ""
    Write-Host "--- a time that cannot be read counts as the newest (review of PR 303, S5) ---" -ForegroundColor Cyan
    $odd = Get-HordeDecisionsChannelRankedAt -Context $S.ctx -Entry ([pscustomobject]@{ sequence = 999999; kind = "question-ranked"; at = "not a time" })
    $fine = Get-HordeDecisionsChannelRankedAt -Context $S.ctx -Entry ([pscustomobject]@{ sequence = 999999; kind = "question-ranked"; at = "2026-10-14T12:00:00.0000000Z" })
    Check ($odd -eq [long]::MaxValue -and $fine -eq 1791979200000) ("a ranking record whose time cannot be read is the newest there is, so every change from the phone is older; one that reads is its time (" + $odd + ", " + $fine + ")")

    Write-Host ""
    Write-Host "--- this very change again, after a crash before its signing time was kept (review of PR 303, S4) ---" -ForegroundColor Cyan
    $n5 = Add-Question $S "Should the crash case be ranked once?"
    $null = Invoke-HordeRelayChannelTicks -Context $S.ctx
    $crashId = New-Id
    $signedThen = [datetime]::UtcNow.AddSeconds(-5)
    [void](Send-ToMachine $S (Get-Rank $S -Body (Get-RankBody $S -RankId $crashId -Number $n5 -Level "high") -Now $signedThen).text)
    $t = Invoke-Turn $S
    Check ((Has $t "done") -and (Get-Words $S $n5) -ceq "high/part") ("CONTROL: the change lands, recorded after it was signed (" + $t.text + ")")
    # THE CRASH: the record is in the store, and the ledger never heard of it - neither its applied id nor
    # its signing time - as when the run dies between the two.
    $rpath = Join-Path $S.home "relay\decisions\receipts.json"
    $seqOfIt = [long](@(Get-Records $S "question-ranked") | Select-Object -Last 1).sequence
    $j = ConvertFrom-HordeJson ([System.IO.File]::ReadAllText($rpath))
    $streamsText = @($j.streams | ForEach-Object { '{"from":"' + $_.from + '","applied":[' + ((@($_.applied | Where-Object { $_ -cne $crashId }) | ForEach-Object { '"' + $_ + '"' }) -join ",") + '],"refused":[' + ((@($_.refused) | ForEach-Object { '"' + $_ + '"' }) -join ",") + ']}' }) -join ","
    $rankedText = @($j.ranked | Where-Object { [long]$_.sequence -ne $seqOfIt } | ForEach-Object { '{"sequence":' + $_.sequence + ',"at":' + $_.at + ',"evidence":"' + $_.evidence + '","proof":"' + $_.proof + '"}' }) -join ","
    [System.IO.File]::WriteAllText($rpath, ('{"v":1,"streams":[' + $streamsText + '],"ranked":[' + $rankedText + ']}'), [System.Text.Encoding]::ASCII)
    $S.ctx = (New-HordeRelayRunContext -HordeHome $S.home -Connection $S.conn).value
    $ledgerNow = Get-HordeDecisionsChannelLedger -Context $S.ctx
    Check (-not $ledgerNow.ranked.Contains("" + $seqOfIt) -and -not (@($ledgerNow.streams[$S.phone.keyId].applied) -ccontains $crashId)) "CONTROL: after the crash the ledger knows neither the change's id nor its signing time"
    $countBefore = @(Get-Records $S "question-ranked").Count
    [void](Send-ToMachine $S (Get-Rank $S -Body (Get-RankBody $S -Number $n5 -Level "high") -Now $signedThen).text)
    $t = Invoke-Turn $S
    Check ((Has $t "superseded") -and @(Get-Records $S "question-ranked").Count -eq $countBefore) ("MUST-REFUSE TWIN: ANOTHER change to the same levels, signed as early, is still older than the record, and refused as superseded (" + $t.text + ")")
    [void](Send-ToMachine $S (Get-Rank $S -Body (Get-RankBody $S -RankId $crashId -Number $n5 -Level "high") -Now $signedThen).text)
    $t = Invoke-Turn $S
    $null = Invoke-HordeRelayChannelTicks -Context $S.ctx
    $rc = Get-PhoneReceipt $S
    Check ((Has $t "(replayed)") -and -not (Has $t "superseded") -and @(Get-Records $S "question-ranked").Count -eq $countBefore -and @($rc.mine.applied) -ccontains $crashId -and -not (@($rc.mine.refused) -ccontains $crashId)) ("THE SAME CHANGE SENT AGAIN is its own record answered again: applied, never superseded, nothing written twice (" + $t.text + ")")
    Check ((Get-HordeDecisionsChannelLedger -Context $S.ctx).ranked.Contains("" + $seqOfIt)) "and its signing time is kept now"

    Write-Host ""
    Write-Host "--- a revoked passkey ranks nothing ---" -ForegroundColor Cyan
    [void](Revoke-HordeRelayTrust -HordeHome $S.home -Subject "device" -Id $S.phone.deviceId -Reason "phone lost")
    [void](Send-ToMachine $S (Get-Rank $S -Body (Get-RankBody $S -Number 2 -Which "importance" -Level "high") -Now ([datetime]::UtcNow.AddMinutes(1))).text)
    $t = Invoke-Turn $S
    Check ((Has $t "revoked") -and -not (Has $t "done") -and (Get-Words $S 2) -ceq "normal/all") ("a change from a passkey since revoked is refused, and nothing is ranked (" + $t.text + ")")

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
        if ((Split-Path -Leaf $h) -match '^horde-relay-rank-[0-9a-f]{32}$') { Remove-Item -LiteralPath $h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Check (@($script:homes | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 0) "every temporary home is gone"
    Exit-HordeTestEmptyFleet -Pin $fleetPin
}
Check ($env:HORDE_HOME -ceq $realHome) "HORDE_HOME is what it was"
Complete-HordeSuite -Success "a change of rank from the phone lands once, signed, only on a question still on his list, never over a newer one, and never as an answer"
