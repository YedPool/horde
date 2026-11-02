# IS A ROUTED ANSWER DELIVERED ONLY WHEN THE ORC'S OWN SESSION TOOK IT (T-0391, slice 1 of 6)?
#
# decisions/Route.ps1 and decisions/RouteTaken.ps1, held without any real messenger, session or mail (the stand-ins and the
# temp home of test-decisions-route.ps1, whose set-up this suite repeats, so that it stays in seconds):
#   - SENT, NOT DELIVERED: a notice the messenger accepted is on the awaiting list and its line says so; nothing calls it delivered.
#   - TAKEN: the messenger's status says handed-over or seen -> delivered, the mark leaves, no alarm.
#   - NOT TAKEN: ONE alarm after takenAlarmSeconds, the mark is kept, nothing is posted again, a late TAKEN says so.
#   - A RESTART mid-wait neither posts nor alarms twice; a crash between the accept and the route record lists it once.
#   - A list that cannot be written holds the record back; a notice held for good, and a status that cannot be had, are told.
# Its mutation specs: test\mutations\decisions-route-taken.psd1 and decisions-route-taken-send.psd1.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

$work = Join-Path $env:TEMP ("horde-decisions-route-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$hordeHome = Join-Path $work "home"
$keepHome = $env:HORDE_HOME
$env:HORDE_HOME = $hordeHome
. (Join-Path $root "test\lib\MessengerPins.ps1")
$pins = @(Set-HordeTestMessengerPins -Root $root -HordeHome $hordeHome)
$keepFleet = $env:WEZFLEET_ROOT
$env:WEZFLEET_ROOT = Join-Path $work "no-fleet"
. (Join-Path $root "decisions\Route.ps1")
. (Join-Path $root "decisions\Console.ps1")
# NO REAL MESSENGER IS EVER ASKED. Route.ps1 loads every messenger folder; all are dropped, and the one
# left is this suite's stand-in. The control shows the loading did happen.
$loaded = @(Get-HordeMessengerNames)
foreach ($n in $loaded) { [void]$script:HordeMessengers.Remove($n) }
Check ($loaded.Count -ge 2) ("CONTROL: the router loads every messenger folder (" + ($loaded -join ", ") + ")")
Check ($pins.Count -ge 1) ("PIN: every messenger that has a pin is pinned in this suite's home (" + ($pins -join ", ") + ")")

# THE STAND-IN MESSENGER: every post, one record per messageId (idempotent, as declared), and a stage
# this suite chooses.
$script:posts = New-Object System.Collections.ArrayList
$script:taken = @{}
$script:postSays = "accepted"
$stubPost = {
    param($Message)
    [void]$script:posts.Add($Message)
    if ($script:postSays -ceq "unknown") { return (New-HordeUnknown -Reason "the stand-in could not tell") }
    $id = "$($Message.messageId)"
    if (-not $script:taken.ContainsKey($id)) { $script:taken[$id] = $Message }
    $reason = $(if ($script:postSays -ceq "held") { "the stand-in held it" } else { "woken" })
    return (New-HordeKnown -Value ([pscustomobject]@{ messageId = $id; stage = $script:postSays; at = [datetime]::UtcNow; reason = $reason; woken = $true }) -ObservedAt ([datetime]::UtcNow))
}
# WHAT THE ORC'S OWN SIDE SAYS OF A POST, BY THE MESSENGER'S ID (T-0391): nothing here makes a notice "taken"; a test says so
# by setting the stage, as the Orc's own hook does. A notice not named keeps no status (absent), as before.
$script:stages = @{}
$script:askedIds = @{}
$stubStatus = {
    param($MessageId)
    $script:askedIds["$MessageId"] = 1 + [int]$script:askedIds["$MessageId"]
    $st = "$($script:stages["$MessageId"])"
    if ($st -ceq "") { return (New-HordeAbsent -Note "the stand-in keeps no status") }
    if ($st -ceq "unknown") { return (New-HordeUnknown -Reason "the stand-in cannot say") }
    return (New-HordeKnown -Value ([pscustomobject]@{ messageId = "$MessageId"; stage = $st; at = [datetime]::UtcNow; reason = $(if ($st -ceq "held") { "the stand-in holds it" } else { "" }) }))
}
$null = Register-HordeMessenger -Folder (Join-Path $here "fixtures\decisions-notify\doorbell") -Post $stubPost -Status $stubStatus

# THE SEATS: role and label to a session, as this suite says; a seat not named is absent.
$script:seats = @{ "orc C" = "orc-c-session"; "orc D" = "orc-d-session"; "warchief" = "warchief-session-1" }
$seat = {
    param([string]$Role, [string]$Label)
    $key = $(if ($Label -ceq "") { $Role } else { $Role + " " + $Label })
    if ($script:seats.ContainsKey($key)) { return (New-HordeKnown -Value ([pscustomobject]@{ sessionId = $script:seats[$key]; pane = "1"; instance = "t1" })) }
    if ($key -ceq "orc E") { return (New-HordeUnknown -Reason "two live sessions each wear the label E with the role orc") }
    return (New-HordeAbsent -Note ("no live session's record wears " + $key))
}
# THE ANALYST'S MAIL: every line, and the token each was found by.
$script:analystLines = New-Object System.Collections.ArrayList
$analyst = { param([string]$Text, [string]$Token, $Since) [void]$script:analystLines.Add([pscustomobject]@{ text = $Text; token = $Token }); return [pscustomobject]@{ ok = $true; said = ("left for the analyst as stand-in-" + $script:analystLines.Count) } }

# THE CLOCK this suite moves. Records are written at the clock's time, so the hour is the suite's own.
$script:now = [datetime]::UtcNow.AddMinutes(-600)
$clock = { return $script:now }
function Advance { param([double]$Minutes) $script:now = $script:now.AddMinutes($Minutes) }
function New-Id { return [guid]::NewGuid().ToString("N") }
function Op { param([string]$Operation, $Request) return (Invoke-HordeDecision -Operation $Operation -Request $Request -Now $script:now) }
function Add-Question { param([string]$AskedBy, [string]$Title, [string[]]$Parts = @())
    $q = @{ title = $Title; kind = "yes-no"; whatItIs = "A step is ready."; group = "A group"; askedBy = $AskedBy; waiting = @($AskedBy) }
    if ($Parts.Count -gt 0) { $q["kind"] = "parts"; $q["parts"] = $Parts }
    $a = Op "add" @{ id = (New-Id); actor = "warchief"; question = $q }
    if ($a.state -cne "known" -or $a.value.outcome -cne "done") { throw ("the question was not added: " + $a.reason) }
    return [int]$a.value.number }
function Say { param([int]$Number, [string]$Text, [string]$Route = "window", [string]$Id = "", [string]$Part = "")
    if ($Id -eq "") { $Id = New-Id }
    $actor = $(if ($Route -ceq "chat-recorded") { "warchief" } else { "founder" })
    $r = @{ id = $Id; actor = $actor; number = $Number; speaker = "founder"; route = $Route; text = $Text }
    if ($Route -cne "chat-recorded") { $r["wordingVersion"] = 1 }
    if ($Route -ceq "phone") { $r["evidence"] = ("{0:x64}" -f [long]($script:posts.Count + 77)); $r["signedBy"] = "0123456789abcdef0123456789abcdef" }
    if ($Part -ne "") { $r["part"] = $Part }
    $a = Op "say" $r
    if ($a.state -cne "known" -or @("done", "replayed") -cnotcontains $a.value.outcome) { throw ("the founder's words were not saved: " + $a.reason + " " + (@($a.value.findings) -join "; ")) }
    return [long]$a.value.sequence }
function Reply { param([int]$Number, [string]$Text)
    $a = Op "say" @{ id = (New-Id); actor = "warchief"; number = $Number; speaker = "warchief"; route = "command"; text = $Text }
    if ($a.state -cne "known" -or $a.value.outcome -cne "done") { throw ("the warchief's words were not saved: " + $a.reason + " " + (@($a.value.findings) -join "; ")) } }
$script:takenMem = @{}
function Pass { param([int]$Grace = 300) return (Invoke-HordeDecisionRoutePass -Clock $clock -Seat $seat -Analyst $analyst -HordeHome $hordeHome -SeatGraceSeconds $Grace -Memory $script:takenMem) }
function Show { param([int]$Number) return (Op "show" @{ number = $Number }).value.question }
function Routes { param([int]$Number) $q = Show $Number; if ($null -eq $q.PSObject.Properties["routes"]) { return @() }; return @($q.routes) }
function PostsTo { param([string]$Session) return @($script:posts | Where-Object { "$($_.sessionId)" -ceq $Session }) }
function Ack { param([int]$Number, [string]$By, $Answer = $null, [string]$Id = "")
    if ($Id -eq "") { $Id = New-Id }
    $r = @{ id = $Id; actor = "orc"; number = $Number; by = $By }
    if ($null -ne $Answer) { $r["answer"] = [long]$Answer }
    return (Op "ack" $r) }

try {

Write-Host ""
Write-Host "--- SENT IS NOT DELIVERED (T-0391): delivered only on the Orc's own TAKEN, one alarm when it is not, never dropped ---" -ForegroundColor Cyan
# A ledger of this section's own: the marks of the sections above are not its concern.
$takenFile = Get-HordeDecisionRouteTakenPath -HordeHome $hordeHome
Remove-Item -LiteralPath $takenFile -Force -ErrorAction SilentlyContinue
$script:takenMem = @{}
function NoticeOf { param([int]$Number) $b = @($script:posts | Where-Object { $_.body -like ('*question ' + $Number + ':*') }); if ($b.Count -eq 0) { return "" }; return "$($b[0].messageId)" }
function Marks { $st = Get-HordeDecisionRouteTakenState -HordeHome $hordeHome; if ($null -eq $st) { return @() }; return @($st) }
function Alarms { param($Lines) return @(@($Lines) | Where-Object { $_ -clike "ALARM:*" }) }

# THE BUG ITSELF: the messenger ACCEPTED the notice; the Orc's session never took it.
$qT = Add-Question "Orc C" "Should the never-taken step go ahead?"
$sT = Say $qT "Yes, never taken."
Advance 1
$p = Pass
$nT = NoticeOf $qT
Check ($p.routed -eq 1 -and $nT -ne "") "the accepted-but-never-taken answer is sent (the route record is written: sent once)"
Check (@(Marks | Where-Object { $_.noticeId -ceq $nT -and -not $_.alarmed -and [long]$_.answer -eq $sT }).Count -eq 1) "BUG: it is on the awaiting list as SENT, not delivered (today it was counted routed and forgotten)"
Check (@($p.lines | Where-Object { $_ -clike "*SENT, not yet delivered: awaiting the session's own TAKEN" }).Count -eq 1 -and @($p.lines | Where-Object { $_ -like "TAKEN:*" -or $_ -like "*: delivered" }).Count -eq 0) "and its line says SENT and awaiting, and no line calls it delivered"
$postsBefore = $script:posts.Count

# NOT TAKEN IN TIME: ONE alarm, the answer stays pending (awaited, asked again), nothing is sent twice.
Advance 0.5
$p = Pass
Check ((Alarms $p.lines).Count -eq 0) "30 s on: not yet an alarm"
Advance 1.5
$p = Pass
Check ((Alarms $p.lines).Count -eq 1 -and @(Alarms $p.lines)[0] -like ("*" + $nT + "*answer record " + $sT + "*was NOT TAKEN by the Orc's session in 1*") -and @(Marks | Where-Object { $_.noticeId -ceq $nT -and $_.alarmed }).Count -eq 1) ("past takenAlarmSeconds: ONE alarm line, and the mark is kept alarmed (" + (@(Alarms $p.lines) -join " | ") + ")")
Advance 0.1
$p = Pass
Advance 6
$p2 = Pass
Check ((Alarms $p.lines).Count -eq 0 -and (Alarms $p2.lines).Count -eq 0 -and $script:posts.Count -eq $postsBefore -and @(Marks | Where-Object { $_.noticeId -ceq $nT }).Count -eq 1) "asked again, the alarm is not said twice, the mark is not dropped, and nothing is posted again"

# IT ARRIVES AFTER THE ALARM: delivered, and the mark leaves the list.
$script:stages[$nT] = "seen"
Advance 6
$p = Pass
Check (@($p.lines | Where-Object { $_ -clike ("TAKEN: routed notice " + $nT + "*after the alarm: delivered") }).Count -eq 1 -and @(Marks | Where-Object { $_.noticeId -ceq $nT }).Count -eq 0) "TAKEN after the alarm: delivered, said once, and the mark is gone"

# TAKEN AT ONCE: delivered, no alarm ever.
$qU = Add-Question "Orc C" "Should the taken step go ahead?"
$sU = Say $qU "Yes, taken."
Advance 0.2
$p = Pass
$nU = NoticeOf $qU
$script:stages[$nU] = "handed-over"
Advance 0.2
$p = Pass
Check (@($p.lines | Where-Object { $_ -clike ("TAKEN: routed notice " + $nU + "*s: delivered") }).Count -eq 1 -and (Alarms $p.lines).Count -eq 0 -and @(Marks | Where-Object { $_.noticeId -ceq $nU }).Count -eq 0) "a notice the Orc's own hook took (handed-over) is delivered at the next pass: no alarm, no mark left"
Advance 5
$p = Pass
Check ($p.outcome -ceq "nothing" -and @($p.lines).Count -eq 0) "and nothing more is said about it"

# A RESTART MID-WAIT does not double-send or double-alarm.
$qV = Add-Question "Orc C" "Should the restart step go ahead?"
$sV = Say $qV "Yes, restart."
Advance 0.2
$p = Pass
$nV = NoticeOf $qV
$postsV = $script:posts.Count
$script:takenMem = @{}
$fresh = Invoke-HordeDecisionRouteTurn -Memory @{} -Force -HordeHome $hordeHome -Clock $clock -Seat $seat -Analyst $analyst
Check ($script:posts.Count -eq $postsV -and @(Marks | Where-Object { $_.noticeId -ceq $nV }).Count -eq 1) "a router that restarts mid-wait sends nothing again and still holds the one mark"
Advance 2
$fresh = Invoke-HordeDecisionRouteTurn -Memory @{} -Force -HordeHome $hordeHome -Clock $clock -Seat $seat -Analyst $analyst
Check ((Alarms $fresh.lines).Count -eq 1 -and @(Alarms $fresh.lines)[0] -like ("*" + $nV + "*")) "the restarted router raises the alarm for it once, from the first post's own clock"
Advance 6
$fresh2 = Invoke-HordeDecisionRouteTurn -Memory @{} -Force -HordeHome $hordeHome -Clock $clock -Seat $seat -Analyst $analyst
Check ((Alarms $fresh2.lines).Count -eq 0 -and $script:posts.Count -eq $postsV -and @(Marks | Where-Object { $_.noticeId -ceq $nV -and $_.alarmed }).Count -eq 1) "and a second restart reads the alarm in the mark: no second alarm, no second post, the mark stays"

# A CRASH BETWEEN THE ACCEPT AND THE ROUTE RECORD: the same notice is sent again and listed once, on its first clock.
$qW = Add-Question "Orc C" "Should the crash-awaited step go ahead?"
$sW = Say $qW "Yes, crash awaited."
$script:realInvoke = ${function:Invoke-HordeDecision}
$script:failRoute = $true
function Invoke-HordeDecision { param([string]$Operation, $Request = $null, [string]$Root = "", [datetime]$Now = [datetime]::UtcNow) if ($Operation -ceq "route" -and $script:failRoute) { return (New-HordeUnknown -Reason "the disk went away (stand-in)") }; return (& $script:realInvoke -Operation $Operation -Request $Request -Root $Root -Now $Now) }
try { $p = Pass } finally { Set-Item function:Invoke-HordeDecision $script:realInvoke }
$nW = NoticeOf $qW
Check (@(Marks | Where-Object { $_.noticeId -ceq $nW }).Count -eq 1 -and @(Routes $qW).Count -eq 0) "the notice is awaited BEFORE its route record: a record that failed to write leaves the mark"
$firstMs = @(Marks | Where-Object { $_.noticeId -ceq $nW })[0].postedMs
Advance 0.3
$p = Pass
Check (@(Marks | Where-Object { $_.noticeId -ceq $nW }).Count -eq 1 -and @(Marks | Where-Object { $_.noticeId -ceq $nW })[0].postedMs -eq $firstMs -and @(Routes $qW).Count -eq 1) "the resend adds no second mark and keeps the first clock; the record is written then"

# THE AWAITING LIST CANNOT BE WRITTEN: the answer is not recorded as sent, and is tried again.
$qX = Add-Question "Orc C" "Should the unwritable step go ahead?"
$sX = Say $qX "Yes, unwritable."
Remove-Item -LiteralPath $takenFile -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $takenFile | Out-Null
$postsX = $script:posts.Count
try { $p = Pass; $pX2 = Pass } finally { Remove-Item -LiteralPath $takenFile -Recurse -Force -ErrorAction SilentlyContinue }
Check ($script:posts.Count -eq $postsX) "an unusable list: NOTHING is posted, at the first pass or the second (no post-and-fail loop)"
Check ($p.outcome -ceq "pending" -and @(Routes $qX).Count -eq 0 -and @($p.lines | Where-Object { $_ -like "pending:*cannot be awaited*" }).Count -eq 1) ("a list that cannot be had holds the record back, and says so (" + (@($p.lines) -join " | ") + ")")
Advance 0.2
$p = Pass
Check (@(Routes $qX).Count -eq 1 -and @(Marks | Where-Object { $_.noticeId -ceq (NoticeOf $qX) }).Count -eq 1 -and $script:posts.Count -eq $postsX + 1) "the next pass lists the notice, posts it once, and records it"

# A LIST THAT READS BUT CANNOT BE WRITTEN (read-only: the disk full or locked reads the same): no post, a stated reason, no loop.
$qR = Add-Question "Orc C" "Should the read-only step go ahead?"
$sR = Say $qR "Yes, read-only."
(Get-Item -LiteralPath $takenFile).IsReadOnly = $true
$postsR = $script:posts.Count
try { $p = Pass; $pR2 = Pass } finally { (Get-Item -LiteralPath $takenFile).IsReadOnly = $false }
Check ($script:posts.Count -eq $postsR -and @(Routes $qR).Count -eq 0 -and @($p.lines | Where-Object { $_ -like "pending: *was not sent: it cannot be awaited (the routed-answers ledger could not be written*" }).Count -eq 1 -and @($pR2.lines | Where-Object { $_ -like "pending: *cannot be awaited*" }).Count -eq 1) ("a readable but unwritable list: nothing is posted in two passes, and the reason is stated each time (" + (@($p.lines) -join " | ") + ")")
Advance 0.2
$p = Pass
Check (@(Routes $qR).Count -eq 1 -and $script:posts.Count -eq $postsR + 1) "and once it can be written the notice is posted once and recorded"

# A NOTICE THE MESSENGER HOLDS FOR GOOD, AND A STATUS THAT CANNOT BE HAD.
$qY = Add-Question "Orc C" "Should the held step go ahead?"
$sY = Say $qY "Yes, held."
$qZ = Add-Question "Orc C" "Should the unsayable step go ahead?"
$sZ = Say $qZ "Yes, unsayable."
Advance 0.2
$p = Pass
$nY = NoticeOf $qY; $nZ = NoticeOf $qZ
$script:stages[$nY] = "held"
$script:stages[$nZ] = "unknown"
Advance 0.3
$p = Pass
Check (@($p.lines | Where-Object { $_ -clike ("ALARM: routed notice " + $nY + "*NOT DELIVERED: the messenger holds it for good*") }).Count -eq 1 -and @(Marks | Where-Object { $_.noticeId -ceq $nY }).Count -eq 0) "held for good: one ALARM line naming it, and it leaves the list in words, not in silence"
Advance 2
$p = Pass
Check (@(Alarms $p.lines | Where-Object { $_ -like ("*" + $nZ + "*was NOT TAKEN*") }).Count -eq 1 -and @(Marks | Where-Object { $_.noticeId -ceq $nZ -and $_.alarmed }).Count -eq 1) "a status that cannot be had is no confirmation: the alarm is raised on the clock alone"

# A FULL LIST: a resend of a notice already on it evicts nobody; a new notice pushes the oldest off WITH an ALARM line.
Remove-Item -LiteralPath $takenFile -Force -ErrorAction SilentlyContinue
$fullNow = [datetime]::UtcNow
$ownId = "11111111-2222-3333-4444-555555555555"
$fullMarks = New-Object System.Collections.ArrayList
[void]$fullMarks.Add((ConvertTo-HordeChatTakenMark -Entry ([pscustomobject]@{ messageId = $ownId.Replace("-", ""); messengerId = $ownId; postedMs = [long]1000; from = "00000000000000000000000000000000"; seq = [long]7; alarmed = $false; woken = $false; session = "" })))
for ($i = 1; $i -lt $script:HordeChatTakenKept; $i++) {
    $fid = ("{0:x8}-0000-0000-0000-000000000000" -f $i)
    [void]$fullMarks.Add((ConvertTo-HordeChatTakenMark -Entry ([pscustomobject]@{ messageId = $fid.Replace("-", ""); messengerId = $fid; postedMs = [long](1000 + $i); from = "00000000000000000000000000000000"; seq = [long]$i; alarmed = $false; woken = $false; session = "" })))
}
Write-HordeTakenLedgerFile -Path $takenFile -Ledger ([pscustomobject]@{ awaiting = @($fullMarks.ToArray()) }) -TempPrefix "test"
$again = Add-HordeDecisionRouteTaken -HordeHome $hordeHome -NoticeId $ownId -Answer 7 -Now $fullNow
Check ($again.ok -and @($again.lines).Count -eq 0 -and @(Marks).Count -eq $script:HordeChatTakenKept -and @(Marks | Where-Object { $_.noticeId -ceq $ownId }).Count -eq 1) "a full list: a notice sent again is already there, so nobody is evicted and no line is said"
$brandNew = Add-HordeDecisionRouteTaken -HordeHome $hordeHome -NoticeId "99999999-2222-3333-4444-555555555555" -Answer 8 -Now $fullNow
Check ($brandNew.ok -and @($brandNew.lines).Count -eq 1 -and @($brandNew.lines)[0] -clike ("ALARM: routed notice " + $ownId + " (answer record 7) left the awaiting list because it is full*") -and @(Marks).Count -eq $script:HordeChatTakenKept) "a full list: a new notice pushes the oldest off WITH an ALARM line naming it, never in silence"

# A CORRUPT LIST (not just an unwritable one): nothing is posted, the reason is stated, and it does not loop.
$qC = Add-Question "Orc C" "Should the corrupt-list step go ahead?"
$sC = Say $qC "Yes, corrupt list."
Remove-Item -LiteralPath $takenFile -Force -ErrorAction SilentlyContinue
[System.IO.File]::WriteAllText($takenFile, "this is not a ledger")
$postsC = $script:posts.Count
$p = Pass
$p2 = Pass
Check ($script:posts.Count -eq $postsC -and $p.outcome -ceq "pending" -and @(Routes $qC).Count -eq 0 -and @($p.lines | Where-Object { $_ -like "pending: *was not sent: it cannot be awaited (the routed-answers ledger cannot be read*" }).Count -eq 1) ("a corrupt list: nothing is posted and the reason is stated (" + (@($p.lines) -join " | ") + ")")
Check ($script:posts.Count -eq $postsC -and @(Routes $qC).Count -eq 0) "and passes after it still post nothing: no loop"
Remove-Item -LiteralPath $takenFile -Force
Advance 0.2
$p = Pass
Check (@(Routes $qC).Count -eq 1 -and $script:posts.Count -eq $postsC + 1) "once the list can be read the answer is posted, once, and recorded"

# THE RE-ASK CADENCE AFTER THE ALARM: not before takenAfterAlarmSeconds, once after.
$qD = Add-Question "Orc C" "Should the cadence step go ahead?"
$sD = Say $qD "Yes, cadence."
Advance 0.2
$p = Pass
$nD = NoticeOf $qD
Advance 2
$p = Pass
Check ((Alarms $p.lines).Count -ge 1 -and @(Marks | Where-Object { $_.noticeId -ceq $nD -and $_.alarmed }).Count -eq 1) "CONTROL: the notice is alarmed"
$asked0 = [int]$script:askedIds[$nD]
Advance 1
$p = Pass
Check ([int]$script:askedIds[$nD] -eq $asked0) "an alarmed mark is not asked again before takenAfterAlarmSeconds (1 min of 5)"
Advance 4.5
$p = Pass
Check ([int]$script:askedIds[$nD] -eq $asked0 + 1) "and it is asked once after it"

# THE END OF THE ROAD: a notice nobody takes in the 7 days the mailbox keeps it is given up WITH an ALARM line.
Advance (8 * 24 * 60)
$p = Pass
Check (@($p.lines | Where-Object { $_ -clike ("ALARM: routed notice " + $nD + "*NOT DELIVERED, given up after*") }).Count -eq 1 -and @(Marks | Where-Object { $_.noticeId -ceq $nD }).Count -eq 0) "past the 7 days: one ALARM line says it is given up, and the mark leaves the list"
$qE = Add-Question "Orc C" "Should the six-day step go ahead?"
$sE = Say $qE "Yes, six days."
Advance 0.2
$p = Pass
$nE = NoticeOf $qE
Advance 2
$p = Pass
Advance (6 * 24 * 60)
$p = Pass
Check (@(Marks | Where-Object { $_.noticeId -ceq $nE }).Count -eq 1 -and @($p.lines | Where-Object { $_ -like "*given up after*" }).Count -eq 0) "CONTROL: at 6 days the alarmed notice is still awaited, not given up"

# A FAILED WRITE AFTER AN ALARM does not repeat the alarm in this process.
$qF = Add-Question "Orc C" "Should the failed-write step go ahead?"
$sF = Say $qF "Yes, failed write."
Advance 0.2
$p = Pass
$nF = NoticeOf $qF
Advance 2
$fileItem = Get-Item -LiteralPath $takenFile
$fileItem.IsReadOnly = $true
try { $p = Pass; $p2 = Pass } finally { (Get-Item -LiteralPath $takenFile).IsReadOnly = $false }
$mine = @($p.lines | Where-Object { $_ -clike ("ALARM: routed notice " + $nF + "*") }).Count
$mine2 = @($p2.lines | Where-Object { $_ -clike ("ALARM: routed notice " + $nF + "*") }).Count
Check ($mine -eq 1 -and $mine2 -eq 0 -and @($p.lines | Where-Object { $_ -like "*could not be written*" }).Count -ge 1) "the write failed after the alarm: the alarm is said once, and not again at the next pass"
$p3 = Pass
Check (@($p3.lines | Where-Object { $_ -clike ("ALARM: routed notice " + $nF + "*") }).Count -eq 0 -and @(Marks | Where-Object { $_.noticeId -ceq $nF -and $_.alarmed }).Count -eq 1) "and once the file can be written the alarmed mark is saved, still without a second alarm"

# A NOTICE TAKEN WHILE ITS ROUTE RECORD KEEPS FAILING is reported TAKEN once, and is not listed again by the repost.
$qG = Add-Question "Orc C" "Should the twice-taken step go ahead?"
$sG = Say $qG "Yes, twice taken."
$script:failRoute = $true
function Invoke-HordeDecision { param([string]$Operation, $Request = $null, [string]$Root = "", [datetime]$Now = [datetime]::UtcNow) if ($Operation -ceq "route" -and $script:failRoute) { return (New-HordeUnknown -Reason "the disk went away (stand-in)") }; return (& $script:realInvoke -Operation $Operation -Request $Request -Root $Root -Now $Now) }
$takenLinesG = @()
try {
    $p = Pass
    $nG = NoticeOf $qG
    $script:stages[$nG] = "seen"
    Advance 0.2
    $p = Pass; $takenLinesG += @($p.lines | Where-Object { $_ -clike ("TAKEN: routed notice " + $nG + "*") })
    Advance 0.2
    $p = Pass; $takenLinesG += @($p.lines | Where-Object { $_ -clike ("TAKEN: routed notice " + $nG + "*") })
    Check (@(Marks | Where-Object { $_.noticeId -ceq $nG }).Count -eq 0) "a notice taken while its record fails is not put on the list again by the repost"
    $script:failRoute = $false
    Advance 0.2
    $p = Pass; $takenLinesG += @($p.lines | Where-Object { $_ -clike ("TAKEN: routed notice " + $nG + "*") })
} finally { Set-Item function:Invoke-HordeDecision $script:realInvoke }
Check ($takenLinesG.Count -eq 1 -and @(Routes $qG).Count -eq 1 -and @(Marks | Where-Object { $_.noticeId -ceq $nG }).Count -eq 0) "and it is said TAKEN once across all the passes, then recorded"
}
finally {
    $env:HORDE_HOME = $keepHome
    $env:WEZFLEET_ROOT = $keepFleet
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-HordeSuite -Success "a routed answer is delivered only on the Orc's own TAKEN, alarms once when it is not taken in time, and is never dropped"
