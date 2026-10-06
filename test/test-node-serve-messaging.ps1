# DOES THE NODE DELIVER, REPORT AND HAND OUT MAIL EXACTLY AS THE MESSAGING RULES SAY, AND DECIDE NOTHING ITSELF?
#
# Remote plan step R21, slice 4. remote/NodeServe.ps1 answers session.deliver, delivery.status, mail.next
# and mail.receipt; every decision a rule makes is remote/Messaging.ps1's (the review of PR #97: the node
# CALLS the rules and never re-decides). This suite holds:
#   - the call sites, statically: NodeServe.ps1 and Outbox.ps1 call the rules, and hold no stage order,
#     no settle test, no process comparison and no opt-in check of their own;
#   - session.deliver: the projection first, the gate on the resolved session (opted in, hub-spawned by
#     process, the label bypass refused, a label mismatch refused), the messenger asked only after the
#     gate, the message journal written only once the messenger answered, a resend answered from the
#     journal without asking again, a reused messageId with other arguments refused, an unheard messenger
#     answered unknown and nothing recorded;
#   - delivery.status from the journal and the messenger, unknown naming the last stage;
#   - mail.next over the outbox, held at the head not blocking, the handed-out marker written before the
#     answer; mail.receipt refused for a message never handed out, forward only, answered with the
#     recorded stage;
#   - the loop step in cli/NodeServe.ps1 that serves NeedView, NeedDeliver, NeedStatus, NeedOutbox and the
#     outbox write, with a fake deliverer: nothing is typed and no real mail root is touched.
# Every file lives under a temp root that is removed at the end.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "Platform", "Namespace")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "transports\Port.ps1")
foreach ($t in @(Get-HordeTransportFiles)) { . $t }
. (Join-Path $root "remote\NodeServe.ps1")
. (Join-Path $root "remote\Outbox.ps1")
. (Join-Path $root "cli\NodeServe.ps1")

$fx = Join-Path $root "test\fixtures\node-serve"
$device = "0f8fad5b-d9cb-469f-a165-70867728950e"
$hubDevice = "7c9e6679-7425-40de-944b-e07fc1f90ae7"
$ns = New-HordeNamespace -Device $device -Space "windows"
$manifest = New-HordeNodeManifest -Root $root -Node ([pscustomobject]@{ deviceId = $device; deviceName = "fixture-node" }) -Space "windows"
$live = "aaaaaaaa-0000-4000-8000-000000000001"
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-nsm-" + [guid]::NewGuid().ToString("N"))
$journalRoot = Join-Path $tmp "messages"
$outboxRoot = Join-Path $tmp "outbox"
$null = Initialize-HordeJournal -Root $journalRoot -Kind "message"
$null = Initialize-HordeOutbox -Root $outboxRoot

function View { return ([System.IO.File]::ReadAllText((Join-Path $fx "view.json")) | ConvertFrom-Json) }
function Proc { param([string]$Id, [string]$Label, [string]$ProcessId, [string]$Start) return [pscustomobject]@{ sessionId = $Id; label = $Label; pid = $ProcessId; procStart = $Start; ns = [pscustomobject]@{ device = $device; space = "windows" } } }
function Data {
    param($View = $null, [string[]]$DeliverTo = @(), $HubSpawned = @(), [string]$Messenger = "fake", $DeliverResult = $null, $DeliveryStatus = $null, $Outbox = $null, [string]$Journal = $journalRoot)
    return [pscustomobject]@{ manifest = $manifest; view = $View; viewError = ""; journalRoot = ""; namespace = $ns
        messageJournalRoot = $Journal; deliverTo = $DeliverTo; hubSpawned = @($HubSpawned); messenger = $Messenger
        deliverResult = $DeliverResult; deliveryStatus = $DeliveryStatus; outbox = $Outbox; outboxError = "" }
}
function State { return (New-HordeNodeServeState -NodeId $device -NodeName "fixture-node" -HordeVersion "0.1.0") }
function Hello {
    $t = Get-HordeLinkTime
    return [pscustomobject][ordered]@{ v = 1; kind = "hello"; id = (New-HordeLinkFrameId); seq = 1; ts = $t; hello = [pscustomobject][ordered]@{ role = "hub"; id = $hubDevice; name = "fixture-hub"; protocols = @(1); verbsVersions = @(1); hordeVersion = "0.1.0"; t1 = $t } }
}
function Req {
    param([string]$Verb, $ArgsObject, [string]$IssuedAt = "")
    if ($IssuedAt -eq "") { $IssuedAt = Get-HordeLinkTime }
    return [pscustomobject][ordered]@{ v = 1; kind = "req"; id = (New-HordeLinkFrameId); seq = 2; ts = (Get-HordeLinkTime); verb = $Verb; requestId = (New-HordeLinkFrameId); issuedAt = $IssuedAt; args = $ArgsObject }
}
function Line { param($Frame) $b = ConvertTo-HordeFrameBytes -Frame $Frame; if ($b.ok) { return [System.Text.Encoding]::ASCII.GetString($b.bytes, 0, $b.bytes.Length - 1) }; return (ConvertTo-HordeWireText $Frame) }
function Sendable { param($Frame) $b = ConvertTo-HordeFrameBytes -Frame $Frame; if (-not $b.ok) { Write-Host ("         not sendable: " + $b.reason) -ForegroundColor DarkYellow }; return [bool]$b.ok }
function AskFrame { param($Frame, $Data) $st = State; $null = Invoke-HordeNodeFrame -State $st -Line (Line (Hello)) -Data (Data); return (Invoke-HordeNodeFrame -State $st -Line (Line $Frame) -Data $Data) }
function Deliver {
    param([string]$SessionId = $live, [string]$Label = "", [string]$Body = "Pause batch 8 until PR 91 merges.", [string]$MessageId = "")
    if ($MessageId -eq "") { $MessageId = New-HordeLinkFrameId }
    $a = [ordered]@{ messageId = $MessageId; sessionId = $SessionId }
    if ($Label -ne "") { $a["label"] = $Label }
    $a["from"] = [pscustomobject][ordered]@{ deviceId = $hubDevice; sessionId = "bbbbbbbb-0000-4000-8000-000000000009"; label = "M" }
    $a["body"] = $Body
    $a["ttlSeconds"] = 3600
    return [pscustomobject]$a
}
function Stage { param([string]$Stage) return [pscustomobject]@{ state = "known"; value = [pscustomobject]@{ stage = $Stage; at = (Get-HordeLinkTime); reason = "" }; reason = ""; observedAt = (Get-HordeLinkTime) } }

try {
Write-Host ""
Write-Host "--- the node calls the rules, and decides none of them itself ---" -ForegroundColor Cyan
$nodeText = [System.IO.File]::ReadAllText((Join-Path $root "remote\NodeServe.ps1"))
$boxText = [System.IO.File]::ReadAllText((Join-Path $root "remote\Outbox.ps1"))
foreach ($rule in @("Resolve-HordeDeliverTarget", "Resolve-HordeMailReceipt", "Select-HordeMailNext")) { Check ($nodeText.Contains($rule + " ")) ("remote/NodeServe.ps1 calls " + $rule) }
Check ($boxText.Contains("Select-HordeMailRecordedStage ")) "remote/Outbox.ps1 calls Select-HordeMailRecordedStage for a record's stage"
foreach ($own in @("HordeMailFinalStages", "HordeMailStageOrder", "Get-HordeMailStageRank", "Test-HordeMailSettled", "Test-HordeDeliverSameProcess", '-ceq "queued"', '-cne "queued"', '-ceq "seen"', "procStart -ceq", "procStart -eq")) {
    Check (-not $nodeText.Contains($own)) ("remote/NodeServe.ps1 holds no rule of its own: no " + $own)
    Check (-not $boxText.Contains($own)) ("remote/Outbox.ps1 holds no rule of its own: no " + $own)
}
. (Join-Path $root "tools\ExecScan.ps1")
foreach ($file in @("NodeServe.ps1", "Outbox.ps1")) {
    $scan = @(Get-HordeExecFindings -Path (Join-Path $root ("remote\" + $file)) -Known (Get-HordeExecFunctionNames -Roots @(Join-Path $root "remote")))
    Check ($scan.Count -eq 0) ("remote/" + $file + " passes the exec scan (" + ($scan -join "; ") + ")")
}

Write-Host ""
Write-Host "--- session.deliver: the projection, the gate on the resolved session, then the messenger ---" -ForegroundColor Cyan
$d = Deliver -Label "A12"
$r = AskFrame (Req "session.deliver" $d) (Data -DeliverTo @("A12"))
Check ($r.needView -eq $true -and $null -eq $r.reply -and $null -eq $r.needDeliver) "a deliver asks for the projection first, and sends and delivers nothing until it has it"
$req = Req "session.deliver" $d
$r = AskFrame $req (Data -View (View) -DeliverTo @("A12"))
Check ($null -eq $r.reply -and $null -ne $r.needDeliver -and "$($r.needDeliver.target.sessionId)" -ceq $live -and "$($r.needDeliver.target.gate)" -ceq "opted-in") "an opted-in label passes the gate, and the node asks its messenger to deliver, sending nothing yet"
Check ("$($r.needDeliver.message.body)" -ceq "$($d.body)" -and "$($r.needDeliver.message.messageId)" -ceq "$($d.messageId)" -and "$($r.needDeliver.message.from.deviceId)" -ceq $hubDevice) "the messenger is handed the message itself, with its id and its sender"
Check ((Get-HordeJournalEntry -Root $journalRoot -Id "$($d.messageId)").state -ceq "absent") "nothing is journaled before the messenger answers"
$r = AskFrame $req (Data -View (View) -DeliverTo @("A12") -DeliverResult (Stage "accepted"))
Check ("$($r.reply.result.state)" -ceq "known" -and "$($r.reply.result.value.stage)" -ceq "accepted" -and "$($r.reply.result.value.sessionId)" -ceq $live -and "$($r.reply.result.value.messageId)" -ceq "$($d.messageId)" -and (Sendable $r.reply)) "with the messenger's answer, the deliver is answered with its delivery, in a frame the contract accepts"
Check ((Get-HordeJournalEntry -Root $journalRoot -Id "$($d.messageId)").state -ceq "known") "and the message is journaled once the messenger answered"
$again = Req "session.deliver" $d -IssuedAt "$($req.issuedAt)"
$r = AskFrame $again (Data -View (View) -DeliverTo @("A12"))
Check ($null -eq $r.needDeliver -and "$($r.reply.result.value.stage)" -ceq "accepted" -and (Sendable $r.reply)) "a resend is answered from the journal with the recorded stage, and the messenger is not asked again"
$changed = Deliver -Label "A12" -MessageId "$($d.messageId)" -Body "Something else entirely."
$r = AskFrame (Req "session.deliver" $changed -IssuedAt "$($req.issuedAt)") (Data -View (View) -DeliverTo @("A12"))
Check ("$($r.reply.error.code)" -ceq "refused" -and "$($r.reply.error.reason)" -clike "*reused*" -and $null -eq $r.needDeliver -and (Sendable $r.reply)) "a messageId reused with other arguments is refused before the messenger is asked"

$r = AskFrame (Req "session.deliver" (Deliver)) (Data -View (View))
Check ("$($r.reply.error.code)" -ceq "refused" -and "$($r.reply.error.reason)" -clike "*neither spawned by this hub nor opted in*" -and $null -eq $r.needDeliver) "a session neither hub-spawned nor opted in is refused, and nothing is delivered"
# THE BYPASS THE REVIEW FOUND: the hub's C2 is gone and a session it never spawned wears its label.
$r = AskFrame (Req "session.deliver" (Deliver -SessionId "dead-1" -Label "A12")) (Data -View (View) -HubSpawned @(Proc "dead-1" "A12" "999" "1"))
Check ("$($r.reply.error.code)" -ceq "refused" -and "$($r.reply.error.reason)" -clike "*neither spawned by this hub nor opted in*") "a label followed to a session the hub never spawned is refused: the gate is on the resolved session"
$r = AskFrame (Req "session.deliver" (Deliver -Label "B3")) (Data -View (View) -DeliverTo @("A12", "B3"))
Check ("$($r.reply.error.code)" -ceq "refused" -and "$($r.reply.error.reason)" -clike "*wears the label A12, not B3*") "a live id wearing another label is refused, never retargeted"
$r = AskFrame (Req "session.deliver" (Deliver -SessionId "old-1" -Label "A12")) (Data -View (View) -HubSpawned @(Proc "old-1" "A12" "4242" "133420000000000000"))
Check ($null -ne $r.needDeliver -and "$($r.needDeliver.target.gate)" -ceq "hub-spawned by process" -and "$($r.needDeliver.target.sessionId)" -ceq $live) "a hub session whose id changed keeps its status through its process, in this node's namespace"
$r = AskFrame (Req "session.deliver" (Deliver -Label "A12")) (Data -View (View) -DeliverTo @("A12") -Messenger "")
Check ("$($r.reply.error.code)" -ceq "refused" -and "$($r.reply.error.reason)" -clike "*no messenger*" -and $null -eq $r.needDeliver) "a node with no messenger refuses a deliver and says why"
$r = AskFrame (Req "session.deliver" (Deliver -Label "A12")) (Data -View (View) -DeliverTo @("A12") -Journal "")
Check ("$($r.reply.error.code)" -ceq "refused" -and "$($r.reply.error.reason)" -clike "*no message journal*") "a node with no message journal refuses a deliver: it could not tell a resend from a first sight"
$unheard = Deliver -Label "A12"
$uq = Req "session.deliver" $unheard
$r = AskFrame $uq (Data -View (View) -DeliverTo @("A12") -DeliverResult ([pscustomobject]@{ state = "unknown"; reason = "the messenger did not answer" }))
Check ("$($r.reply.result.state)" -ceq "unknown" -and "$($r.reply.result.reason)" -clike "*messenger did not answer*" -and (Sendable $r.reply)) "a messenger that did not answer is answered unknown, with its reason"
Check ((Get-HordeJournalEntry -Root $journalRoot -Id "$($unheard.messageId)").state -ceq "absent") "and nothing is journaled, so a resend asks the messenger again"

Write-Host ""
Write-Host "--- delivery.status: the journal, then the messenger ---" -ForegroundColor Cyan
$r = AskFrame (Req "delivery.status" ([pscustomobject]@{ messageId = (New-HordeLinkFrameId) })) (Data)
Check ("$($r.reply.result.state)" -ceq "absent" -and (Sendable $r.reply)) "a message this node never accepted is absent"
$sq = Req "delivery.status" ([pscustomobject]@{ messageId = "$($d.messageId)" })
$r = AskFrame $sq (Data)
Check ($null -eq $r.reply -and "$($r.needStatus)" -ceq "$($d.messageId)") "a known message asks the messenger where it is now"
$r = AskFrame $sq (Data -DeliveryStatus (Stage "seen"))
Check ("$($r.reply.result.value.stage)" -ceq "seen" -and "$($r.reply.result.value.sessionId)" -ceq $live -and (Sendable $r.reply)) "the messenger's stage is the answer, for the session the deliver reached"
$r = AskFrame $sq (Data -DeliveryStatus ([pscustomobject]@{ state = "unknown"; reason = "the mail root could not be read" }))
Check ("$($r.reply.result.state)" -ceq "unknown" -and "$($r.reply.result.reason)" -clike "*last stage recorded: accepted*" -and (Sendable $r.reply)) "a messenger that cannot say is unknown, naming the last stage recorded"

Write-Host ""
Write-Host "--- mail.next and mail.receipt over the outbox ---" -ForegroundColor Cyan
function Mail { param([string]$Id, [string]$CreatedAt, [string]$To = "M") return [pscustomobject][ordered]@{ messageId = $Id; from = [pscustomobject][ordered]@{ deviceId = $device; sessionId = "cccccccc-0000-4000-8000-000000000001"; label = "A12" }; to = [pscustomobject][ordered]@{ label = $To }; body = ("message " + $Id); createdAt = $CreatedAt; ttlSeconds = 86400 } }
$heldId = "0e000000-0000-4000-8000-000000000101"
$nextId = "0e000000-0000-4000-8000-000000000102"
$neverId = "0e000000-0000-4000-8000-000000000103"
$r = AskFrame (Req "mail.next" ([pscustomobject]@{})) (Data -Outbox @())
Check ("$($r.reply.result.value.pending)" -eq "0" -and $null -eq $r.reply.result.value.PSObject.Properties["mail"] -and (Sendable $r.reply)) "an empty outbox: nothing pending and no mail"
$r = AskFrame (Req "mail.next" ([pscustomobject]@{})) (Data)
Check ($r.needOutbox -eq $true -and $null -eq $r.reply) "mail.next asks for the outbox first"
Check ((New-HordeOutboxMail -Root $outboxRoot -Mail (Mail $heldId "2026-10-05T12:00:00.000Z")).state -ceq "known") "CONTROL: a first message is put in the outbox"
$null = New-HordeOutboxMail -Root $outboxRoot -Mail (Mail $nextId "2026-10-05T12:00:01.000Z")
$null = New-HordeOutboxMail -Root $outboxRoot -Mail (Mail $neverId "2026-10-05T12:00:02.000Z")
$null = Add-HordeOutboxMarker -Root $outboxRoot -MessageId $heldId -Marker "handed" -At "2026-10-05T12:00:03.000Z"
$null = Add-HordeOutboxMarker -Root $outboxRoot -MessageId $heldId -Marker "held" -At "2026-10-05T12:00:04.000Z"
$box = Get-HordeOutbox -Root $outboxRoot
$r = AskFrame (Req "mail.next" ([pscustomobject]@{})) (Data -Outbox $box.value)
Check ("$($r.reply.result.value.mail.messageId)" -ceq $nextId -and "$($r.reply.result.value.pending)" -eq "2" -and (Sendable $r.reply)) "with a held message at the head, mail.next returns the oldest queued one behind it, and counts two waiting"
Check ($null -ne $r.write -and "$($r.write.messageId)" -ceq $nextId -and "$($r.write.marker)" -ceq "handed") "and asks for the handed-out marker to be written before the answer is sent"
$r = AskFrame (Req "mail.receipt" ([pscustomobject]@{ messageId = $neverId; stage = "accepted"; at = (Get-HordeLinkTime) })) (Data -Outbox $box.value)
Check ("$($r.reply.error.code)" -ceq "refused" -and "$($r.reply.error.reason)" -clike "*never returned from mail.next*" -and $null -eq $r.write -and (Sendable $r.reply)) "a receipt for a message the node never handed out is refused, and nothing is written"
$r = AskFrame (Req "mail.receipt" ([pscustomobject]@{ messageId = "0e000000-0000-4000-8000-0000000001ff"; stage = "accepted"; at = (Get-HordeLinkTime) })) (Data -Outbox $box.value)
Check ("$($r.reply.error.code)" -ceq "refused" -and $null -eq $r.write) "a receipt for a message the outbox does not hold is refused"
$null = Add-HordeOutboxMarker -Root $outboxRoot -MessageId $nextId -Marker "handed" -At "2026-10-05T12:00:05.000Z"
$box = Get-HordeOutbox -Root $outboxRoot
$r = AskFrame (Req "mail.receipt" ([pscustomobject]@{ messageId = $nextId; stage = "accepted"; at = "2026-10-05T12:00:06.000Z" })) (Data -Outbox $box.value)
Check ("$($r.reply.result.value.stage)" -ceq "accepted" -and "$($r.write.marker)" -ceq "accepted" -and (Sendable $r.reply)) "a forward receipt is acked with the new stage, and its marker is written before the ack"
$null = Add-HordeOutboxMarker -Root $outboxRoot -MessageId $nextId -Marker "seen" -At "2026-10-05T12:00:07.000Z"
$box = Get-HordeOutbox -Root $outboxRoot
$r = AskFrame (Req "mail.receipt" ([pscustomobject]@{ messageId = $nextId; stage = "accepted"; at = "2026-10-05T12:00:08.000Z" })) (Data -Outbox $box.value)
Check ("$($r.reply.result.value.stage)" -ceq "seen" -and "$($r.reply.result.value.recordedAt)" -ceq "2026-10-05T12:00:07.000Z" -and $null -eq $r.write -and (Sendable $r.reply)) "a backward receipt writes nothing, and is acked with the recorded stage and when it was recorded"

Write-Host ""
Write-Host "--- the loop step serves every need, with a fake deliverer ---" -ForegroundColor Cyan
$script:posted = New-Object System.Collections.ArrayList
$fake = [pscustomobject]@{ name = "fake"
    post = { param($Message, $Target) [void]$script:posted.Add($Message.messageId); return [pscustomobject]@{ state = "known"; value = [pscustomobject]@{ stage = "accepted"; at = (Get-HordeLinkTime); reason = "" }; reason = ""; observedAt = (Get-HordeLinkTime) } }
    status = { param($MessageId) return [pscustomobject]@{ state = "known"; value = [pscustomobject]@{ stage = "handed-over"; at = (Get-HordeLinkTime); reason = "" }; reason = ""; observedAt = (Get-HordeLinkTime) } } }
$loopEnv = [pscustomobject]@{ GetView = { View }; Deliverer = $fake; OutboxRoot = $outboxRoot; MessageJournalRoot = $journalRoot; DeliverTo = @("A12"); HubSpawned = @() }
$st = State
$null = Invoke-HordeNodeFrame -State $st -Line (Line (Hello)) -Data (Data)
$loopMsg = Deliver -Label "A12"
$out = Invoke-HordeNodeServeStep -State $st -Line (Line (Req "session.deliver" $loopMsg)) -Manifest $manifest -Namespace $ns -JournalRoot "" -Env $loopEnv
Check ("$($out.reply.result.value.stage)" -ceq "accepted" -and $script:posted.Count -eq 1 -and "$($script:posted[0])" -ceq "$($loopMsg.messageId)" -and (Sendable $out.reply)) "the loop builds the view, hands the message to the deliverer once, and answers the delivery"
$out = Invoke-HordeNodeServeStep -State $st -Line (Line (Req "delivery.status" ([pscustomobject]@{ messageId = "$($loopMsg.messageId)" }))) -Manifest $manifest -Namespace $ns -JournalRoot "" -Env $loopEnv
Check ("$($out.reply.result.value.stage)" -ceq "handed-over" -and $script:posted.Count -eq 1) "the loop asks the deliverer where the message is, and posts nothing again"
$out = Invoke-HordeNodeServeStep -State $st -Line (Line (Req "mail.next" ([pscustomobject]@{}))) -Manifest $manifest -Namespace $ns -JournalRoot "" -Env $loopEnv
Check ("$($out.reply.result.value.mail.messageId)" -ceq $neverId -and (Sendable $out.reply)) "the loop reads the outbox and hands out the next unsettled message"
$after = Get-HordeOutbox -Root $outboxRoot
Check (@($after.value | Where-Object { "$($_.messageId)" -ceq $neverId -and $_.handedOut }).Count -eq 1) "and the handed-out marker is on disk once the answer is built"
$noMessenger = [pscustomobject]@{ GetView = { View }; Deliverer = $null; OutboxRoot = $outboxRoot; MessageJournalRoot = $journalRoot; DeliverTo = @("A12"); HubSpawned = @() }
$out = Invoke-HordeNodeServeStep -State $st -Line (Line (Req "session.deliver" (Deliver -Label "A12"))) -Manifest $manifest -Namespace $ns -JournalRoot "" -Env $noMessenger
Check ("$($out.reply.error.code)" -ceq "refused" -and "$($out.reply.error.reason)" -clike "*no messenger*" -and $script:posted.Count -eq 1) "a loop with no deliverer refuses a deliver and posts nothing"
} finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $tmp)) "the temp root is gone"

Complete-HordeSuite -Success "the node delivers only past the rules' gate, journals once, reports from the journal and the messenger, and hands out mail forward only"
