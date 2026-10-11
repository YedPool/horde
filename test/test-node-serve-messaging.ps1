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
#     outbox write, through the messenger port with its in-process memory messenger: nothing is typed
#     and no session's mail is touched.
# Every file lives under a temp root that is removed at the end.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "Platform", "Namespace", "NodeDeliverTo")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "transports\Port.ps1")
foreach ($t in @(Get-HordeTransportFiles)) { . $t }
. (Join-Path $root "remote\NodeServe.ps1")
. (Join-Path $root "remote\Outbox.ps1")
. (Join-Path $root "cli\NodeServe.ps1")
. (Join-Path $root "cli\NodeAct.ps1")
. (Join-Path $root "messengers\Port.ps1")
foreach ($m in @(Get-HordeMessengerFiles -Root (Join-Path $root "messengers"))) { . $m }
. (Join-Path $root "test\lib\MessengerPins.ps1")
# PINNED (test\lib\MessengerPins.ps1): every messenger is loaded, and a messenger may find a real program
# on its own (the wezfleet command on PATH). Under this home each has pinned itself to nothing, so no
# case, and no child it starts, can post into a real fleet on a machine where one is installed.
$pinned = Enter-HordeTestPinnedHome -Root $root

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
    $script:lastId = $MessageId
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
$loopText = [System.IO.File]::ReadAllText((Join-Path $root "cli\NodeServe.ps1"))
foreach ($portCall in @("Send-HordeMessengerMessage ", "Get-HordeMessengerStatus ", "Resolve-HordeNodeMessenger ")) { Check ($loopText.Contains($portCall)) ("cli/NodeServe.ps1 calls the messenger port's " + $portCall.Trim()) }
foreach ($direct in @(".post ", ".post)", ".status ", ".status)")) { Check (-not $loopText.Contains("& $deliverer" + $direct) -and -not $loopText.Contains("& $Messenger" + $direct)) ("cli/NodeServe.ps1 never calls a messenger's block itself (& ..." + $direct.Trim() + ")") }
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

$unread = (Data -View (View))
$unread.deliverTo = $null
$r = AskFrame (Req "session.deliver" (Deliver -Label "A12")) $unread
Check ($r.needDeliverTo -eq $true -and $null -eq $r.reply -and $null -eq $r.needDeliver) "with the opt-in list not yet read, a deliver asks for it before the gate, and delivers nothing"
$r = AskFrame (Req "session.deliver" (Deliver -Label "A12")) (Data -View (View) -DeliverTo @("B3", "A12"))
Check ($null -ne $r.needDeliver -and "$($r.needDeliver.target.gate)" -ceq "opted-in") "an opt-in list of two labels reaches the session wearing the second: each label is read as its own"
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
Write-Host "--- a read-only node refuses every verb whose effect is not read (review of #112, B1) ---" -ForegroundColor Cyan
function ReadOnly { param($D) $D | Add-Member -NotePropertyName readOnly -NotePropertyValue $true -Force; return $D }
$roMsg = Deliver -Label "A12"
$r = AskFrame (Req "session.deliver" $roMsg) (Data -View (View) -DeliverTo @("A12"))
Check ($null -ne $r.needDeliver) "CONTROL: without -ReadOnly, the same deliver passes the gate and asks the messenger"
$r = AskFrame (Req "session.deliver" $roMsg) (ReadOnly (Data -View (View) -DeliverTo @("A12")))
Check ("$($r.reply.error.code)" -ceq "refused" -and "$($r.reply.error.reason)" -clike "*read verbs only*session.deliver*drive*" -and $null -eq $r.needDeliver -and -not $r.needView -and (Sendable $r.reply)) "under -ReadOnly, session.deliver (drive) is refused with the reason, before anything is asked"
$r = AskFrame (Req "mail.receipt" ([pscustomobject]@{ messageId = "0e000000-0000-4000-8000-000000000301"; stage = "accepted"; at = (Get-HordeLinkTime) })) (ReadOnly (Data -Outbox @()))
Check ("$($r.reply.error.code)" -ceq "refused" -and "$($r.reply.error.reason)" -clike "*read verbs only*mail.receipt*write*" -and $null -eq $r.write -and (Sendable $r.reply)) "under -ReadOnly, mail.receipt (write) is refused with the reason, and nothing is written"
$r = AskFrame (Req "mail.next" ([pscustomobject]@{})) (ReadOnly (Data -Outbox @()))
Check ("$($r.reply.result.value.pending)" -eq "0" -and (Sendable $r.reply)) "a read verb (mail.next) still answers under -ReadOnly, from what the node was given"

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
Write-Host "--- the loop step serves every need, through the messenger port ---" -ForegroundColor Cyan
$mem = (Resolve-HordeMessenger -Name "memory" -Require @()).value
$mfx = & (Join-Path $root "messengers\memory\test\Fixture.ps1") -Root $root
$mfxState = & $mfx.New
# How many records the messenger holds for one message: 1 once it took it, 0 if it never did.
function Took { param([string]$Id) return [int](& $mfx.Observe $mfxState $Id).records }
$loopEnv = [pscustomobject]@{ GetView = { View }; Messenger = $mem; OutboxRoot = $outboxRoot; MessageJournalRoot = $journalRoot; DeliverTo = @("A12"); HubSpawned = @() }
$st = State
$null = Invoke-HordeNodeFrame -State $st -Line (Line (Hello)) -Data (Data)
$loopMsg = Deliver -Label "A12"
$out = Invoke-HordeNodeServeStep -State $st -Line (Line (Req "session.deliver" $loopMsg)) -Manifest $manifest -Namespace $ns -JournalRoot "" -Messaging $loopEnv
Check ("$($out.reply.result.value.stage)" -ceq "accepted" -and (Took "$($loopMsg.messageId)") -eq 1 -and (Sendable $out.reply)) "the loop builds the view, hands the message to the deliverer once, and answers the delivery"
& $mfx.Receive $mfxState "$($loopMsg.messageId)"
$out = Invoke-HordeNodeServeStep -State $st -Line (Line (Req "delivery.status" ([pscustomobject]@{ messageId = "$($loopMsg.messageId)" }))) -Manifest $manifest -Namespace $ns -JournalRoot "" -Messaging $loopEnv
Check ("$($out.reply.result.value.stage)" -ceq "seen" -and (Took "$($loopMsg.messageId)") -eq 1) "the loop asks the messenger, through the port, where the message is, and posts nothing again"
$out = Invoke-HordeNodeServeStep -State $st -Line (Line (Req "mail.next" ([pscustomobject]@{}))) -Manifest $manifest -Namespace $ns -JournalRoot "" -Messaging $loopEnv
Check ("$($out.reply.result.value.mail.messageId)" -ceq $neverId -and (Sendable $out.reply)) "the loop reads the outbox and hands out the next unsettled message"
$after = Get-HordeOutbox -Root $outboxRoot
Check (@($after.value | Where-Object { "$($_.messageId)" -ceq $neverId -and $_.handedOut }).Count -eq 1) "and the handed-out marker is on disk once the answer is built"
$noMessenger = [pscustomobject]@{ GetView = { View }; Messenger = $null; OutboxRoot = $outboxRoot; MessageJournalRoot = $journalRoot; DeliverTo = @("A12"); HubSpawned = @() }
$out = Invoke-HordeNodeServeStep -State $st -Line (Line (Req "session.deliver" (Deliver -Label "A12"))) -Manifest $manifest -Namespace $ns -JournalRoot "" -Messaging $noMessenger
Check ("$($out.reply.error.code)" -ceq "refused" -and "$($out.reply.error.reason)" -clike "*no messenger*" -and (Took $script:lastId) -eq 0) "a loop with no messenger refuses a deliver and posts nothing"
$followed = Deliver -SessionId "gone-1" -Label "A12"
$byProcess = [pscustomobject]@{ GetView = { View }; Messenger = $mem; OutboxRoot = $outboxRoot; MessageJournalRoot = $journalRoot; DeliverTo = @(); HubSpawned = @(Proc "gone-1" "A12" "4242" "133420000000000000") }
$out = Invoke-HordeNodeServeStep -State $st -Line (Line (Req "session.deliver" $followed)) -Manifest $manifest -Namespace $ns -JournalRoot "" -Messaging $byProcess
Check ("$($out.reply.result.value.sessionId)" -ceq $live -and (Took "$($followed.messageId)") -eq 1) "a deliver to a dead id reaches, through its process, the live session the rules resolved"
$sent = ConvertTo-HordeNodeMessengerMessage -Need ([pscustomobject]@{ target = [pscustomobject]@{ sessionId = $live }; message = $followed })
Check ("$($sent.sessionId)" -ceq $live -and "$($sent.label)" -ceq "A12" -and "$($sent.messageId)" -ceq "$($followed.messageId)" -and "$($sent.body)" -ceq "$($followed.body)") "the port is handed the session the rules resolved, not the dead id the hub named"
$nodeHome0 = Join-Path $tmp "home0"
[void][System.IO.Directory]::CreateDirectory($nodeHome0)
$picked = New-HordeNodeMessaging -Root $root -HordeHome $nodeHome0 -GetView { View } -MessengerName "memory"
Check ($null -eq $picked.Messenger -and "$($picked.MessengerError)" -clike "*receipt.receiver*") "the production path refuses the in-process messenger: it declines receipt.receiver"
$out = Invoke-HordeNodeServeStep -State $st -Line (Line (Req "session.deliver" (Deliver -Label "A12"))) -Manifest $manifest -Namespace $ns -JournalRoot "" -Messaging $picked
Check ("$($out.reply.error.code)" -ceq "refused" -and "$($out.reply.error.reason)" -clike "*no messenger*receipt.receiver*" -and (Took $script:lastId) -eq 0) "so a node started with it refuses every deliver, saying why, and posts nothing"
$none = New-HordeNodeMessaging -Root $root -HordeHome $nodeHome0 -GetView { View }
$out = Invoke-HordeNodeServeStep -State $st -Line (Line (Req "session.deliver" (Deliver -Label "A12"))) -Manifest $manifest -Namespace $ns -JournalRoot "" -Messaging $none
Check ("$($out.reply.error.code)" -ceq "refused" -and "$($out.reply.error.reason)" -clike "*no messenger was named*") "a node with no messenger named refuses every deliver, saying so"
$posted0 = Deliver -Label "A12"
$out = Invoke-HordeNodeServeStep -State $st -Line (Line (Req "session.deliver" $posted0)) -Manifest $manifest -Namespace $ns -JournalRoot "" -ReadOnly
Check ("$($out.reply.error.code)" -ceq "refused" -and "$($out.reply.error.reason)" -clike "*read verbs only*" -and (Took "$($posted0.messageId)") -eq 0) "a read-only loop, given no messaging at all, refuses a deliver as read-only and posts nothing"
$out = Invoke-HordeNodeServeStep -State $st -Line (Line (Req "session.deliver" $posted0)) -Manifest $manifest -Namespace $ns -JournalRoot "" -Messaging $loopEnv -ReadOnly
Check ("$($out.reply.error.code)" -ceq "refused" -and "$($out.reply.error.reason)" -clike "*read verbs only*" -and (Took "$($posted0.messageId)") -eq 0) "and even handed a messenger, a read-only loop refuses the deliver: the flag decides, not what was passed"
$out = Invoke-HordeNodeServeStep -State $st -Line (Line (Req "session.deliver" $posted0)) -Manifest $manifest -Namespace $ns -JournalRoot "" -Messaging $loopEnv
Check ("$($out.reply.result.value.stage)" -ceq "accepted" -and (Took "$($posted0.messageId)") -eq 1) "CONTROL: without -ReadOnly, with a messenger named, the same deliver is delivered"
$out = Invoke-HordeNodeServeStep -State $st -Line (Line (Req "delivery.status" ([pscustomobject]@{ messageId = "$($posted0.messageId)" }))) -Manifest $manifest -Namespace $ns -JournalRoot "" -ReadOnly
Check ("$($out.reply.result.state)" -ceq "unknown" -and "$($out.reply.result.reason)" -clike "*keeps no message journal*" -and (Sendable $out.reply)) "a read verb (delivery.status) still answers on a read-only node, unknown: it opens no message journal"
$out = Invoke-HordeNodeServeStep -State $st -Line (Line (Req "mail.next" ([pscustomobject]@{}))) -Manifest $manifest -Namespace $ns -JournalRoot "" -ReadOnly
Check ("$($out.reply.error.code)" -ceq "internal" -and "$($out.reply.error.reason)" -clike "*keeps no outbox*" -and (Sendable $out.reply)) "and mail.next answers that the node keeps no outbox: a read-only node opens none, so it writes no handed-out mark"
$nodeCmd = [System.IO.File]::ReadAllText((Join-Path $root "cli\commands\node.ps1"))
Check ($nodeCmd -match '\$messaging = \$null\s+if \(-not \$ReadOnly\) \{\s+\$messaging = New-HordeNodeMessaging' -and $nodeCmd.Contains('-ReadOnly:$ReadOnly')) "horde node serve -ReadOnly builds no messaging (no messenger, outbox or journal) and serves read verbs only"

Write-Host ""
Write-Host "--- the opt-in list is read from the node's layers again for every deliver ---" -ForegroundColor Cyan
# ONE messaging object for the whole section, as horde node serve builds one when it starts: every
# change below is to the files only, and the next deliver must see it (no restart, nothing cached).
$nodeHome = Join-Path $tmp "home"
[void][System.IO.Directory]::CreateDirectory($nodeHome)
function OptIn { param([string]$Id, [string]$Labels) return ('{ "schemaVersion": 1, "rules": [ { "id": "' + $Id + '", "match": {}, "set": { "remote.deliverTo": "' + $Labels + '" }, "writtenBy": "user" } ] }') }
function Put { param([string]$File, [string]$Text) $path = Join-Path $nodeHome $File; if ($Text -eq "") { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } else { [System.IO.File]::WriteAllText($path, $Text) } }
function DeliverNow { param([string]$SessionId = $live, $Messaging = $built) return (Invoke-HordeNodeServeStep -State $st -Line (Line (Req "session.deliver" (Deliver -SessionId $SessionId -Label "A12"))) -Manifest $manifest -Namespace $ns -JournalRoot "" -Messaging $Messaging) }
Put "engine.json" (OptIn "opt-in" "A12")
$built = New-HordeNodeMessaging -Root $root -HordeHome $nodeHome -GetView { View } -Messenger $mem
Check ($null -ne $built.Layers -and (Test-Path -LiteralPath (Join-Path $nodeHome "node\outbox")) -and (Test-Path -LiteralPath (Join-Path $nodeHome "node\messages"))) "CONTROL: the node's journal and outbox are made under its home, and the opt-in list is left to be read per deliver"
$out = DeliverNow
Check ("$($out.reply.result.value.stage)" -ceq "accepted") "CONTROL: with A12 opted in by engine.json, a deliver to it goes through"
Put "engine-live.json" (OptIn "withdraw" "")
$out = DeliverNow
Check ("$($out.reply.error.code)" -ceq "refused" -and "$($out.reply.error.reason)" -clike "*neither spawned by this hub nor opted in*" -and (Took $script:lastId) -eq 0) "engine-live.json withdrawing every opt-in holds from the very next deliver, with no restart"
Put "engine-live.json" ""
$out = DeliverNow
Check ("$($out.reply.result.value.stage)" -ceq "accepted" -and (Took $script:lastId) -eq 1) "and removing the live file restores engine.json's list on the next deliver"

Write-Host ""
Write-Host "--- a node layer that fails its checks refuses every deliver, as it refuses every spawn ---" -ForegroundColor Cyan
Put "engine.json" (OptIn "opt-in" "A12,A12")
$out = DeliverNow
Check ("$($out.reply.error.code)" -ceq "refused" -and "$($out.reply.error.reason)" -clike "*'A12'*twice*" -and (Took $script:lastId) -eq 0 -and (Sendable $out.reply)) "with engine.json refused, a deliver is refused with the layer's reason, and nothing is posted"
$spawned = [pscustomobject]@{ GetView = $built.GetView; Messenger = $mem; OutboxRoot = $built.OutboxRoot; MessageJournalRoot = $built.MessageJournalRoot; Layers = $built.Layers; HubSpawned = @(Proc "old-2" "A12" "4242" "133420000000000000") }
$out = DeliverNow -SessionId "old-2" -Messaging $spawned
Check ("$($out.reply.error.code)" -ceq "refused" -and "$($out.reply.error.reason)" -clike "*fails its checks*" -and (Took $script:lastId) -eq 0) "even to a session the hub spawned: a refused layer refuses every deliver, not only the opted-in ones"
Put "engine.json" (OptIn "opt-in" "A12")
$out = DeliverNow -SessionId "old-2" -Messaging $spawned
Check ("$($out.reply.result.value.stage)" -ceq "accepted") "CONTROL: with engine.json fixed, the same deliver to the hub's session goes through"
Put "engine-live.json" '{ "schemaVersion": 1, "rules": ['
$out = DeliverNow
Check ("$($out.reply.error.code)" -ceq "refused" -and "$($out.reply.error.reason)" -clike "*engine-live.json*" -and (Took $script:lastId) -eq 0) "an engine-live.json that is not JSON refuses every deliver too, naming the file"
Put "engine-live.json" ""
function PutBytes { param([string]$File, [byte[]]$Bytes) [System.IO.File]::WriteAllBytes((Join-Path $nodeHome $File), $Bytes) }
$ascii = [System.Text.Encoding]::ASCII
# A note with an e-acute (0xC3 0xA9 in UTF-8): JSON that parses, and is not the plain ASCII a layer must be.
PutBytes "engine.json" ($ascii.GetBytes('{ "schemaVersion": 1, "rules": [ { "id": "opt-in", "match": {}, "set": { "remote.deliverTo": "A12" }, "writtenBy": "user", "note": "caf') + [byte[]](0xC3, 0xA9) + $ascii.GetBytes('" } ] }'))
$out = DeliverNow
Check ("$($out.reply.error.code)" -ceq "refused" -and "$($out.reply.error.reason)" -clike "*engine.json*not ASCII*" -and (Took $script:lastId) -eq 0) "a non-ASCII engine.json refuses every deliver, naming the file and why"
$out = DeliverNow -SessionId "old-2" -Messaging $spawned
Check ("$($out.reply.error.code)" -ceq "refused" -and "$($out.reply.error.reason)" -clike "*engine.json*not ASCII*" -and (Took $script:lastId) -eq 0) "even to a session the hub spawned"
Put "engine.json" (OptIn "opt-in" "A12")
# A byte order mark (0xEF 0xBB 0xBF) before JSON that is otherwise plain.
PutBytes "engine-live.json" ([byte[]](0xEF, 0xBB, 0xBF) + $ascii.GetBytes((OptIn "live" "A12")))
$out = DeliverNow
Check ("$($out.reply.error.code)" -ceq "refused" -and "$($out.reply.error.reason)" -clike "*engine-live.json*not ASCII*" -and (Took $script:lastId) -eq 0) "an engine-live.json with a byte order mark refuses every deliver, naming the file and why"
$out = DeliverNow -SessionId "old-2" -Messaging $spawned
Check ("$($out.reply.error.code)" -ceq "refused" -and "$($out.reply.error.reason)" -clike "*engine-live.json*not ASCII*" -and (Took $script:lastId) -eq 0) "even to a session the hub spawned"
Put "engine-live.json" ""
$out = DeliverNow
Check ("$($out.reply.result.value.stage)" -ceq "accepted") "CONTROL: with the byte order mark gone, the same deliver goes through"
} finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $tmp)) "the temp root is gone"

Exit-HordeTestPinnedHome -State $pinned
Complete-HordeSuite -Success "the node delivers only past the rules' gate, journals once, reports from the journal and the messenger, and hands out mail forward only"
