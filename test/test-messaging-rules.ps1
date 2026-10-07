# DO THE MESSAGING RULES OF THE LINK HOLD, AS CODE THE NODE AND THE HUB CALL?
#
# Plan step R21, slice 2, after the review of PR #97 (2026-10-06). The contract text states each rule;
# remote/Messaging.ps1 is where each is decided, once, so slice 4 (the node) and slice 5 (the hub) call
# it rather than each choosing. Every rule here is pure: given what the node or hub knows, the answer.
#   - F1: a deliver is resolved to ONE live session, and the gate is applied to THAT session. Hub-spawned
#         status follows a session-id change only through the process (pid and procStart), never through
#         a label; a live id wearing another label is refused, never retargeted.
#   - F2: a receipt only moves a record forward, never off a final stage; the answer is the record's.
#   - F3: every stage but queued settles a message, so a held one never blocks the queue behind it.
#   - F5: outbound mail comes from the link's own peer device, or it is refused.
#   - F6: a receipt for a message the node never handed out is refused.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "remote\Messaging.ps1")

function S { param([string]$Id, [string]$Label, [string]$ProcessId, [string]$Start) return [pscustomobject]@{ sessionId = $Id; label = $Label; pid = $ProcessId; procStart = $Start } }
function Has { param([string]$Text, [string]$Part) return ("$Text".Contains($Part)) }

Write-Host ""
Write-Host "--- F2 and F6. a receipt moves a record forward, never off a final stage ---" -ForegroundColor Cyan

$r = Resolve-HordeMailReceipt -Recorded "" -Asked "accepted"
Check ((Has $r.refused "never returned from mail.next") -and -not $r.changed) "F6: a receipt for a message the node never handed out is refused, and records nothing"
$r = Resolve-HordeMailReceipt -Recorded "queued" -Asked "queued"
Check ((Has $r.refused "is not a receipt stage") -and -not $r.changed) "queued is never a receipt the hub sends"
$r = Resolve-HordeMailReceipt -Recorded "lost" -Asked "accepted"
Check ((Has $r.refused "is not a stage") -and -not $r.changed) "a record holding no known stage is refused, not overwritten"
foreach ($step in @(@("queued", "accepted"), @("accepted", "handed-over"), @("handed-over", "seen"), @("queued", "seen"), @("accepted", "held"), @("handed-over", "expired"), @("queued", "refused"))) {
    $r = Resolve-HordeMailReceipt -Recorded $step[0] -Asked $step[1]
    Check ($r.refused -eq "" -and $r.changed -and $r.stage -ceq $step[1]) ("forward: " + $step[0] + " then " + $step[1] + " records " + $step[1])
}
foreach ($step in @(@("seen", "accepted"), @("handed-over", "accepted"), @("seen", "handed-over"))) {
    $r = Resolve-HordeMailReceipt -Recorded $step[0] -Asked $step[1]
    Check ($r.refused -eq "" -and -not $r.changed -and $r.stage -ceq $step[0]) ("backward: " + $step[0] + " then " + $step[1] + " records nothing and answers " + $step[0])
}
foreach ($step in @(@("seen", "refused"), @("held", "seen"), @("refused", "accepted"), @("expired", "held"))) {
    $r = Resolve-HordeMailReceipt -Recorded $step[0] -Asked $step[1]
    Check ($r.refused -eq "" -and -not $r.changed -and $r.stage -ceq $step[0]) ("final: " + $step[0] + " is never overwritten, by " + $step[1] + " or anything")
}
$r = Resolve-HordeMailReceipt -Recorded "seen" -Asked "seen"
Check ($r.refused -eq "" -and -not $r.changed -and $r.stage -ceq "seen") "a replayed receipt, under any request id, records nothing and answers the recorded stage"

Write-Host ""
Write-Host "--- F3. every stage but queued settles a message, so a held one never blocks the queue ---" -ForegroundColor Cyan

Check (-not (Test-HordeMailSettled -Stage "queued")) "a queued message is unsettled"
foreach ($st in @("accepted", "handed-over", "seen", "expired", "held", "refused")) { Check (Test-HordeMailSettled -Stage $st) ("a " + $st + " message is settled") }
Check (-not (Test-HordeMailSettled -Stage "lost")) "a stage nobody knows is never read as settled"
$box = @(
    [pscustomobject]@{ messageId = "0e000000-0000-4000-8000-000000000001"; stage = "held"; createdAt = "2026-10-05T12:00:00.000Z" },
    [pscustomobject]@{ messageId = "0e000000-0000-4000-8000-000000000002"; stage = "queued"; createdAt = "2026-10-05T12:00:02.000Z" },
    [pscustomobject]@{ messageId = "0e000000-0000-4000-8000-000000000003"; stage = "queued"; createdAt = "2026-10-05T12:00:01.000Z" }
)
$n = Select-HordeMailNext -Outbox $box
Check ($n.pending -eq 2 -and "$($n.next.messageId)" -ceq "0e000000-0000-4000-8000-000000000003") "with a held message at the head, mail.next returns the oldest queued one behind it, and counts two waiting"
$n = Select-HordeMailNext -Outbox @($box[0])
Check ($n.pending -eq 0 -and $null -eq $n.next) "an outbox holding only settled mail has nothing next"
$n = Select-HordeMailNext -Outbox @()
Check ($n.pending -eq 0 -and $null -eq $n.next) "an empty outbox has nothing next"

Write-Host ""
Write-Host "--- F5. outbound mail comes from the link's own peer device ---" -ForegroundColor Cyan

$peer = "0f000000-0000-4000-8000-000000000002"
$mail = [pscustomobject]@{ from = [pscustomobject]@{ deviceId = $peer; sessionId = "s1" }; to = [pscustomobject]@{ label = "M" } }
$f = @(Test-HordeMailSender -Mail $mail -PeerDeviceId $peer)
Check ($f.Count -eq 0) "CONTROL: mail from the peer's own device passes"
$mail.from.deviceId = "0f000000-0000-4000-8000-000000000001"
$f = @(Test-HordeMailSender -Mail $mail -PeerDeviceId $peer)
Check ($f.Count -eq 1 -and (Has $f[0] "claims device 0f000000-0000-4000-8000-000000000001")) "mail claiming another device than the link's peer is refused"
$f = @(Test-HordeMailSender -Mail $mail -PeerDeviceId "")
Check ($f.Count -eq 1 -and (Has $f[0] "peer's device is not known")) "with no authenticated peer device, no mail passes"

Write-Host ""
Write-Host "--- F1. a deliver resolves to one live session, and the gate is applied to it ---" -ForegroundColor Cyan

$hub = @(S "h1" "C2" "100" "p100")
$t = Resolve-HordeDeliverTarget -SessionId "h1" -Label "" -Live @(S "h1" "C2" "100" "p100") -HubSpawned $hub -DeliverTo @()
Check ($t.refused -eq "" -and $t.sessionId -ceq "h1" -and $t.gate -ceq "hub-spawned") "CONTROL: a live hub-spawned session is delivered to by its id"
$t = Resolve-HordeDeliverTarget -SessionId "h1" -Label "C2" -Live @(S "h1" "C2" "100" "p100") -HubSpawned $hub -DeliverTo @()
Check ($t.refused -eq "" -and $t.sessionId -ceq "h1") "a live id with its own label passes"
$t = Resolve-HordeDeliverTarget -SessionId "h1" -Label "B4" -Live @((S "h1" "C2" "100" "p100"), (S "b4" "B4" "400" "p400")) -HubSpawned $hub -DeliverTo @("B4")
Check ((Has $t.refused "wears the label C2, not B4") -and $t.sessionId -eq "") "a live id wearing another label is refused, never retargeted to the session that wears it"
# THE BYPASS THE REVIEW FOUND: hub-spawned C2 is gone, and a session the hub never spawned wears C2.
$t = Resolve-HordeDeliverTarget -SessionId "h1" -Label "C2" -Live @(S "l1" "C2" "200" "p200") -HubSpawned $hub -DeliverTo @()
Check ((Has $t.refused "neither spawned by this hub nor opted in") -and $t.sessionId -eq "") "a label followed to a session the hub never spawned is refused: the gate is applied to the resolved session"
$t = Resolve-HordeDeliverTarget -SessionId "h1" -Label "C2" -Live @(S "l1" "C2" "200" "p200") -HubSpawned $hub -DeliverTo @("C2")
Check ($t.refused -eq "" -and $t.sessionId -ceq "l1" -and $t.gate -ceq "opted-in") "the same session passes when the node's owner opted its label in"
$t = Resolve-HordeDeliverTarget -SessionId "h1" -Label "C2" -Live @(S "h1b" "C2" "100" "p100") -HubSpawned $hub -DeliverTo @()
Check ($t.refused -eq "" -and $t.sessionId -ceq "h1b" -and $t.gate -ceq "hub-spawned by process") "a compacted hub session keeps its status through its process, pid and procStart"
$t = Resolve-HordeDeliverTarget -SessionId "h1" -Label "C2" -Live @(S "h1c" "C2" "100" "p-other") -HubSpawned $hub -DeliverTo @()
Check ((Has $t.refused "neither spawned by this hub nor opted in")) "a reused pid with another start time is not the hub's process"
$t = Resolve-HordeDeliverTarget -SessionId "x9" -Label "D1" -Live @(S "d1" "D1" "300" "") -HubSpawned @(S "h3" "D9" "300" "") -DeliverTo @()
Check ((Has $t.refused "neither spawned by this hub nor opted in")) "a pid with no start time on either side never proves the process"
$t = Resolve-HordeDeliverTarget -SessionId "h1" -Label "C2" -Live @((S "l1" "C2" "200" "p200"), (S "l2" "C2" "201" "p201")) -HubSpawned $hub -DeliverTo @("C2")
Check ((Has $t.refused "2 live sessions wear the label C2")) "a label worn by two live sessions is refused"
$t = Resolve-HordeDeliverTarget -SessionId "h1" -Label "" -Live @(S "l1" "C2" "200" "p200") -HubSpawned $hub -DeliverTo @("C2")
Check ((Has $t.refused "is not live on this node and the deliver names no label")) "a dead id with no label follows nothing and is refused"
$t = Resolve-HordeDeliverTarget -SessionId "h1" -Label "C2" -Live @() -HubSpawned $hub -DeliverTo @("C2")
Check ((Has $t.refused "no live session wears the label C2")) "a label no live session wears is refused"
$t = Resolve-HordeDeliverTarget -SessionId "l1" -Label "" -Live @(S "l1" "" "200" "p200") -HubSpawned $hub -DeliverTo @("C2")
Check ((Has $t.refused "neither spawned by this hub nor opted in")) "a live session with no label is never opted in"

Complete-HordeSuite -Success "a deliver reaches one live session past its own gate, a receipt only moves forward, held mail never blocks the queue, and mail comes from its link's device"
