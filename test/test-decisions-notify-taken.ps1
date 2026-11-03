# IS A DOORBELL NOTICE DELIVERED ONLY WHEN THE WARCHIEF'S OWN SESSION TOOK IT (T-0391, slice 3 of 6)?
#
# decisions/Notify.ps1 and decisions/NoticeTaken.ps1, held without any real messenger, session or mail (the stand-ins and the
# temp home of test-decisions-notify.ps1, whose set-up this suite repeats, so that it stays in seconds). The bug: the bell counted
# a notice the messenger ACCEPTED as the warchief being told; the session may never have been prompted (the knock can be refused
# while it is mid-turn), and nothing asked. The same cure as the routed answers' (test-decisions-route-taken.ps1):
#   - MARK FIRST, THEN POST: an unusable list means no post, a stated reason, the set still pending.
#   - A KNOWN refusal takes the mark off; an UNKNOWN result keeps it.
#   - SENT, NOT DELIVERED: the line says so; only the session's own TAKEN (handed-over, seen) is delivered.
#   - ONE ALARM at takenAlarmSeconds, a re-ask cadence after it, and a 7-day give-up with an ALARM.
#   - A RESTART neither posts nor alarms twice; a crash between the post and the told record lists the notice once.
#   - The Turn (the relay runner's bell) and the Loop (`horde decisions notify`) both say what the list says.
# Its mutation specs: test\mutations\decisions-notify-taken.psd1 (and decisions-route-taken.psd1 for the shared engine).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

$work = Join-Path $env:TEMP ("horde-decisions-notify-taken-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$hordeHome = Join-Path $work "home"
$keepHome = $env:HORDE_HOME
$env:HORDE_HOME = $hordeHome
. (Join-Path $root "test\lib\MessengerPins.ps1")
$pins = @(Set-HordeTestMessengerPins -Root $root -HordeHome $hordeHome)
$keepFleet = $env:WEZFLEET_ROOT
$env:WEZFLEET_ROOT = Join-Path $work "no-fleet"
. (Join-Path $root "decisions\Notify.ps1")
# The chat's awaiting-mark format, read directly (not through the code under test).
. (Join-Path $root "channels\chat\Taken.ps1")
$fx = Join-Path $here "fixtures\decisions-notify"
# NO REAL MESSENGER IS EVER ASKED. Notify.ps1 loads every messenger folder; all are dropped, and the one left is this suite's stand-in.
$loaded = @(Get-HordeMessengerNames)
foreach ($n in $loaded) { [void]$script:HordeMessengers.Remove($n) }
Check ($loaded.Count -ge 2) ("CONTROL: notify loads every messenger folder (" + ($loaded -join ", ") + ")")
Check ($pins.Count -ge 1) ("PIN: every messenger that has a pin is pinned in this suite's home (" + ($pins -join ", ") + ")")

# THE STAND-IN MESSENGER: every post, one record per messageId (idempotent), and a stage this suite chooses.
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
# WHAT THE WARCHIEF'S OWN SIDE SAYS OF A POST, BY THE MESSENGER'S ID: nothing here makes a notice "taken"; a test says so by setting
# the stage, as the session's own hook does. A notice not named keeps no status (absent).
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
$null = Register-HordeMessenger -Folder (Join-Path $fx "doorbell") -Post $stubPost -Status $stubStatus

$script:now = [datetime]::new(2026, 10, 9, 12, 0, 0, [System.DateTimeKind]::Utc)
$clock = { return $script:now }
function Advance { param([double]$Minutes) $script:now = $script:now.AddMinutes($Minutes) }
$script:seatSays = "known"
$seat = { if ($script:seatSays -ceq "known") { return (New-HordeKnown -Value ([pscustomobject]@{ sessionId = "warchief-session-1"; pane = "3"; instance = "t1" })) }; return (New-HordeAbsent -Note "no live session's record names the role warchief") }

$script:n = 0
function Add-Answered { param([string]$Title)
    # A question, and the founder's answer under it; returns the question's number.
    $script:n++
    $q = [ordered]@{ title = $Title; kind = "yes-no"; whatItIs = ("Step " + $script:n + " is ready."); recommendation = "yes"; group = "A group"; askedBy = "Orc A"; waiting = @("Orc A") }
    $a = Invoke-HordeDecision -Operation "add" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = $q }
    if ($a.state -cne "known" -or $a.value.outcome -cne "done") { throw ("question was not added: " + $a.reason) }
    $number = [int]$a.value.number
    $s = Invoke-HordeDecision -Operation "say" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "founder"; number = $number; speaker = "founder"; route = "window"; text = "yes"; wordingVersion = 1 }
    if ($s.state -cne "known" -or $s.value.outcome -cne "done") { throw ("the founder's words were not saved: " + $s.reason) }
    return $number }
$script:tracker = New-HordeDecisionNotifyTracker -QuietSeconds 30
function Pass { param($Tracker = $null) if ($null -eq $Tracker) { $Tracker = $script:tracker }; return (Invoke-HordeDecisionNotifyPass -Tracker $Tracker -Clock $clock -Seat $seat) }
function Ring { param([string]$Title)
    # One answered question, seen, left quiet, and rung for: returns { number; id; pass }.
    $number = Add-Answered $Title
    $before = $script:posts.Count
    [void](Pass)
    Advance 0.6
    $p = Pass
    $id = $(if ($script:posts.Count -gt $before) { "$($script:posts[$script:posts.Count - 1].messageId)" } else { "" })
    return [pscustomobject]@{ number = $number; id = $id; pass = $p } }
$takenFile = [System.IO.Path]::Combine($hordeHome, "decisions", "notify-taken.json")
function Marks { $r = Read-HordeTakenLedgerFile -Path $takenFile -What "the doorbell's awaiting ledger" -Noun "notice"; if ($r.state -cne "known") { return @() }; return @(@($r.value.awaiting) | ForEach-Object { ConvertFrom-HordeChatTakenMark -Mark $_ }) }
function MarkOf { param([string]$Id) return @(Marks | Where-Object { $_.messengerId -ceq $Id }) }
$recordPath = Get-HordeDecisionNotifyRecordPath -HordeHome $hordeHome
function Told { $r = Read-HordeDecisionNotifyRecord -Path $recordPath; return @($r.entries | ForEach-Object { [int]$_.question }) }
function Alarms { param($Lines) return @(@($Lines) | Where-Object { $_ -clike "ALARM:*" }) }

try {

Write-Host ""
Write-Host "--- SENT IS NOT DELIVERED (T-0391): delivered only on the warchief's own TAKEN, one alarm when it is not, never dropped ---" -ForegroundColor Cyan
Check (@(Marks).Count -eq 0) "CONTROL: no mark before anything is rung"
# THE BUG ITSELF: the messenger ACCEPTED the notice; the warchief's session never took it.
$r1 = Ring "Should the never-taken step go ahead?"
$p = $r1.pass
Check ($p.outcome -ceq "rang" -and $r1.id -ne "") "the accepted-but-never-taken notice is rung and the told record is written"
Check (@(MarkOf $r1.id | Where-Object { -not $_.alarmed -and $_.seq -eq 1 -and $_.session -ceq "warchief-session-1" }).Count -eq 1) "BUG: it is on the awaiting list as SENT, not delivered (today it was counted told and forgotten)"
Check ($p.said -clike "*; SENT, not yet delivered: awaiting the session's own TAKEN" -and @($p.takenLines | Where-Object { $_ -like "TAKEN:*" }).Count -eq 0) ("its line says SENT and awaiting, and no line calls it delivered (" + $p.said + ")")
$posts1 = $script:posts.Count

# NOT TAKEN IN TIME: ONE alarm, the mark is kept, nothing is posted again.
Advance 0.5
$p = Pass
Check ((Alarms $p.takenLines).Count -eq 0) "30 s on: not yet an alarm"
Advance 1.5
$p = Pass
Check ((Alarms $p.takenLines).Count -eq 1 -and @(Alarms $p.takenLines)[0] -like ("ALARM: bell notice " + $r1.id + " (1 answer(s) of the founder's) was NOT TAKEN by the warchief's session in 1*") -and @(MarkOf $r1.id | Where-Object { $_.alarmed }).Count -eq 1) ("past takenAlarmSeconds: ONE alarm line, and the mark is kept alarmed (" + (@(Alarms $p.takenLines) -join " | ") + ")")
Advance 0.1
$p = Pass
Advance 6
$p2 = Pass
Check ((Alarms $p.takenLines).Count -eq 0 -and (Alarms $p2.takenLines).Count -eq 0 -and $script:posts.Count -eq $posts1 -and @(MarkOf $r1.id).Count -eq 1) "asked again, the alarm is not said twice, the mark is not dropped, and nothing is posted again"

# IT ARRIVES AFTER THE ALARM: delivered, and the mark leaves the list.
$script:stages[$r1.id] = "seen"
Advance 6
$p = Pass
Check (@($p.takenLines | Where-Object { $_ -clike ("TAKEN: bell notice " + $r1.id + "*after the alarm: delivered") }).Count -eq 1 -and @(MarkOf $r1.id).Count -eq 0) "TAKEN after the alarm: delivered, said once, and the mark is gone"

# TAKEN AT ONCE: delivered, no alarm ever.
$r2 = Ring "Should the taken step go ahead?"
$script:stages[$r2.id] = "handed-over"
Advance 0.2
$p = Pass
Check (@($p.takenLines | Where-Object { $_ -clike ("TAKEN: bell notice " + $r2.id + "*s: delivered") }).Count -eq 1 -and (Alarms $p.takenLines).Count -eq 0 -and @(MarkOf $r2.id).Count -eq 0) "a notice the session's own hook took (handed-over) is delivered at the next pass: no alarm, no mark left"
Advance 5
$p = Pass
Check ($p.outcome -ceq "nothing" -and @($p.takenLines).Count -eq 0) "and nothing more is said about it"

# A RESTART MID-WAIT does not double-post or double-alarm.
$r3 = Ring "Should the restart step go ahead?"
$posts3 = $script:posts.Count
$restarted = New-HordeDecisionNotifyTracker -QuietSeconds 30
$p = Pass $restarted
Check ($script:posts.Count -eq $posts3 -and $p.outcome -ceq "nothing" -and @(MarkOf $r3.id).Count -eq 1) "a bell that restarts mid-wait rings nothing again and the one mark is still there"
Advance 2
$restarted = New-HordeDecisionNotifyTracker -QuietSeconds 30
$p = Pass $restarted
Check ((Alarms $p.takenLines).Count -eq 1 -and @(Alarms $p.takenLines)[0] -like ("*" + $r3.id + "*")) "the restarted bell raises the alarm for it once, from the first post's own clock"
Advance 6
$restarted = New-HordeDecisionNotifyTracker -QuietSeconds 30
$p = Pass $restarted
Check ((Alarms $p.takenLines).Count -eq 0 -and $script:posts.Count -eq $posts3 -and @(MarkOf $r3.id | Where-Object { $_.alarmed }).Count -eq 1) "and a second restart reads the alarm in the mark: no second alarm, no second post, the mark stays"

# A CRASH BETWEEN THE POST AND THE TOLD RECORD: the same notice is posted again and listed once, on its first clock.
$number4 = Add-Answered "Should the crash-awaited step go ahead?"
[void](Pass)
Advance 0.6
$script:realWrite = ${function:Write-HordeDecisionNotifyRecord}
function Write-HordeDecisionNotifyRecord { param([string]$Path, $Entries) throw "the disk went away (stand-in)" }
$posts4 = $script:posts.Count
try { $p = Pass } finally { Set-Item function:Write-HordeDecisionNotifyRecord $script:realWrite }
$id4 = "$($script:posts[$script:posts.Count - 1].messageId)"
Check ($script:posts.Count -eq $posts4 + 1 -and @(MarkOf $id4).Count -eq 1 -and $p.said -like "*told record could not be written*") "the notice is awaited BEFORE the told record: a record that failed to write leaves the mark"
$firstMs = @(MarkOf $id4)[0].postedMs
Advance 0.3
$p = Pass
Check ($script:posts.Count -eq $posts4 + 2 -and "$($script:posts[$script:posts.Count - 1].messageId)" -ceq $id4 -and @(MarkOf $id4).Count -eq 1 -and @(MarkOf $id4)[0].postedMs -eq $firstMs -and $p.outcome -ceq "rang") "the repost has the same id, adds no second mark, keeps the first clock; the told record is written then"

# THE AWAITING LIST CANNOT BE WRITTEN (a directory sits where the file goes): nothing is posted, a reason is stated, the set waits.
Remove-Item -LiteralPath $takenFile -Force -ErrorAction SilentlyContinue
$number5 = Add-Answered "Should the unwritable step go ahead?"
[void](Pass)
Advance 0.6
New-Item -ItemType Directory -Path $takenFile | Out-Null
$posts5 = $script:posts.Count
try { $p = Pass; Advance 1; $p2 = Pass } finally { Remove-Item -LiteralPath $takenFile -Recurse -Force -ErrorAction SilentlyContinue }
Check ($script:posts.Count -eq $posts5) "an unusable list: NOTHING is posted, at the first pass or the second (no post-and-fail loop)"
Check ($p.outcome -ceq "pending" -and $p.said -clike "pending: the notice cannot be awaited (*; nothing is posted until it can be*" -and @(Told) -notcontains $number5) ("the set stays pending and untold, the reason is said (" + $p.said + ")")
Advance 1
$p = Pass
Check ($p.outcome -ceq "rang" -and $script:posts.Count -eq $posts5 + 1 -and @(Told) -contains $number5) "once the list can be had the notice is posted once and told"

# A LIST THAT READS BUT CANNOT BE WRITTEN (read-only: the disk full or locked reads the same).
$number6 = Add-Answered "Should the read-only step go ahead?"
[void](Pass)
Advance 0.6
(Get-Item -LiteralPath $takenFile).IsReadOnly = $true
$posts6 = $script:posts.Count
try { $p = Pass; Advance 1; $p2 = Pass } finally { (Get-Item -LiteralPath $takenFile).IsReadOnly = $false }
Check ($script:posts.Count -eq $posts6 -and $p.said -like "pending: *cannot be awaited (the doorbell's awaiting ledger could not be written*" -and $p2.said -like "pending: *cannot be awaited*") ("a readable but unwritable list: nothing is posted in two passes, and the reason is stated each time (" + $p.said + ")")
Advance 6
$p = Pass
Check ($p.outcome -ceq "rang" -and $script:posts.Count -eq $posts6 + 1) "and once it can be written the notice is posted once"

# A CORRUPT LIST: nothing is posted, the reason is stated, the list is said unreadable, and nothing is started over.
$number7 = Add-Answered "Should the corrupt-list step go ahead?"
[void](Pass)
Advance 0.6
$good = [System.IO.File]::ReadAllText($takenFile)
[System.IO.File]::WriteAllText($takenFile, "this is not a ledger")
$posts7 = $script:posts.Count
$p = Pass
Check ($script:posts.Count -eq $posts7 -and $p.outcome -ceq "pending" -and $p.said -like "pending: the notice cannot be awaited (the doorbell's awaiting ledger*" -and @($p.takenLines | Where-Object { $_ -like "bell: the awaiting list of doorbell notices cannot be read*" }).Count -eq 1 -and $p.takenFailed) ("a corrupt list: nothing is posted, the reason is stated, and the list is said unreadable (" + $p.said + ")")
Check ([System.IO.File]::ReadAllText($takenFile) -ceq "this is not a ledger") "and the file is left as it was, never started over"
[System.IO.File]::WriteAllText($takenFile, $good)
Advance 6
$p = Pass
Check ($p.outcome -ceq "rang" -and $script:posts.Count -eq $posts7 + 1) "mended, the notice is posted once"

# A REFUSED POST LEAVES NO MARK and no false alarm (review of 416).
$number8 = Add-Answered "Should the refused step go ahead?"
[void](Pass)
Advance 0.6
$script:postSays = "held"
$posts8 = $script:posts.Count
$p = Pass
$id8 = "$($script:posts[$script:posts.Count - 1].messageId)"
Check ($script:posts.Count -eq $posts8 + 1 -and $p.outcome -ceq "pending" -and @(Told) -notcontains $number8 -and @(MarkOf $id8).Count -eq 0) "a refused post: it was tried, nothing is told, and no mark is left behind"
Advance 3
$p = Pass
Check ((Alarms $p.takenLines | Where-Object { $_ -like ("*" + $id8 + "*") }).Count -eq 0) "and minutes on, no 'not taken' alarm is raised for a notice that was never sent"
$script:postSays = "accepted"
Advance 6
$p = Pass
Check ($p.outcome -ceq "rang" -and @(MarkOf $id8 | Where-Object { -not $_.alarmed }).Count -eq 1) "refused, then accepted on a later pass: it is listed afresh and told"
Advance 0.2
$p = Pass
Check ((Alarms $p.takenLines | Where-Object { $_ -like ("*" + $id8 + "*") }).Count -eq 0) "and it does not alarm at once from the old attempt's clock"

# AN UNKNOWN POST RESULT (a timeout, a dropped link) KEEPS THE MARK: the notice may have landed, so it stays watched.
Remove-Item -LiteralPath $takenFile -Force -ErrorAction SilentlyContinue
$number9 = Add-Answered "Should the timeout step go ahead?"
[void](Pass)
Advance 0.6
$script:postSays = "unknown"
$p = Pass
$id9 = "$($script:posts[$script:posts.Count - 1].messageId)"
Check ($p.outcome -ceq "pending" -and @(Told) -notcontains $number9 -and @(MarkOf $id9 | Where-Object { -not $_.alarmed }).Count -eq 1) "an unknown post result: not told, still pending, and the mark is KEPT"
$script:postSays = "accepted"
Advance 0.6
$p = Pass
Check ($p.outcome -ceq "rang" -and @(MarkOf $id9).Count -eq 1) "the retry is accepted: told, and the one mark stays (no second)"
Advance 3
$p = Pass
Check ((Alarms $p.takenLines | Where-Object { $_ -like ("*" + $id9 + "*was NOT TAKEN*") }).Count -eq 1) "and, never taken, it is still asked about and alarmed once"
$script:stages[$id9] = "seen"
Advance 6
$p = Pass
Check (@($p.takenLines | Where-Object { $_ -clike ("TAKEN: bell notice " + $id9 + "*") }).Count -eq 1) "and a TAKEN is seen for it"

# A NOTICE THE MESSENGER HOLDS FOR GOOD, AND A STATUS THAT CANNOT BE HAD.
Remove-Item -LiteralPath $takenFile -Force -ErrorAction SilentlyContinue
$rY = Ring "Should the held step go ahead?"
$rZ = Ring "Should the unsayable step go ahead?"
$script:stages[$rY.id] = "held"
$script:stages[$rZ.id] = "unknown"
Advance 0.3
$p = Pass
Check (@($p.takenLines | Where-Object { $_ -clike ("ALARM: bell notice " + $rY.id + "*NOT DELIVERED: the messenger holds it for good*") }).Count -eq 1 -and @(MarkOf $rY.id).Count -eq 0) "held for good: one ALARM line naming it, and it leaves the list in words, not in silence"
Advance 2
$p = Pass
Check (@(Alarms $p.takenLines | Where-Object { $_ -like ("*" + $rZ.id + "*was NOT TAKEN*") }).Count -eq 1 -and @(MarkOf $rZ.id | Where-Object { $_.alarmed }).Count -eq 1) "a status that cannot be had is no confirmation: the alarm is raised on the clock alone"

# THE RE-ASK CADENCE AFTER THE ALARM: not before takenAfterAlarmSeconds (5 min), once after.
$asked0 = [int]$script:askedIds[$rZ.id]
Advance 1
$p = Pass
Check ([int]$script:askedIds[$rZ.id] -eq $asked0) "an alarmed mark is not asked again before takenAfterAlarmSeconds (1 min of 5)"
Advance 4.5
$p = Pass
Check ([int]$script:askedIds[$rZ.id] -eq $asked0 + 1) "and it is asked once after it"

# THE END OF THE ROAD: a notice nobody takes in the 7 days the mailbox keeps it is given up WITH an ALARM line.
Advance (6 * 24 * 60)
$p = Pass
Check (@(MarkOf $rZ.id).Count -eq 1 -and @($p.takenLines | Where-Object { $_ -like "*given up after*" }).Count -eq 0) "CONTROL: at 6 days the alarmed notice is still awaited, not given up"
Advance (2 * 24 * 60)
$p = Pass
Check (@($p.takenLines | Where-Object { $_ -clike ("ALARM: bell notice " + $rZ.id + "*NOT DELIVERED, given up after*") }).Count -eq 1 -and @(MarkOf $rZ.id).Count -eq 0) "past the 7 days: one ALARM line says it is given up, and the mark leaves the list"

# A FAILED WRITE AFTER AN ALARM does not repeat the alarm in this process.
$rF = Ring "Should the failed-write step go ahead?"
Advance 2
(Get-Item -LiteralPath $takenFile).IsReadOnly = $true
try { $p = Pass; $p2 = Pass } finally { (Get-Item -LiteralPath $takenFile).IsReadOnly = $false }
$a1 = @($p.takenLines | Where-Object { $_ -clike ("ALARM: bell notice " + $rF.id + "*") }).Count
$a2 = @($p2.takenLines | Where-Object { $_ -clike ("ALARM: bell notice " + $rF.id + "*") }).Count
Check ($a1 -eq 1 -and $a2 -eq 0 -and @($p.takenLines | Where-Object { $_ -like "*could not be written*" }).Count -ge 1) "the write failed after the alarm: the alarm is said once, and not again at the next pass"
$p3 = Pass
Check (@($p3.takenLines | Where-Object { $_ -clike ("ALARM: bell notice " + $rF.id + "*") }).Count -eq 0 -and @(MarkOf $rF.id | Where-Object { $_.alarmed }).Count -eq 1) "and once the file can be written the alarmed mark is saved, still without a second alarm"

# A NOTICE TAKEN WHILE ITS TOLD RECORD KEEPS FAILING is reported TAKEN once and is not listed again by the repost.
$numberG = Add-Answered "Should the twice-taken step go ahead?"
[void](Pass)
Advance 0.6
function Write-HordeDecisionNotifyRecord { param([string]$Path, $Entries) throw "the disk went away (stand-in)" }
$takenG = @()
try {
    $p = Pass
    $idG = "$($script:posts[$script:posts.Count - 1].messageId)"
    $script:stages[$idG] = "seen"
    Advance 0.3
    $p = Pass; $takenG += @($p.takenLines | Where-Object { $_ -clike ("TAKEN: bell notice " + $idG + "*") })
    Advance 0.3
    $p = Pass; $takenG += @($p.takenLines | Where-Object { $_ -clike ("TAKEN: bell notice " + $idG + "*") })
    Check (@(MarkOf $idG).Count -eq 0) "a notice taken while its told record fails is not put on the list again by the repost"
} finally { Set-Item function:Write-HordeDecisionNotifyRecord $script:realWrite }
Advance 0.3
$p = Pass; $takenG += @($p.takenLines | Where-Object { $_ -clike ("TAKEN: bell notice " + $idG + "*") })
Check ($takenG.Count -eq 1 -and @(MarkOf $idG).Count -eq 0 -and @(Told) -contains $numberG) "and it is said TAKEN once across all the passes, then told"

# A FULL LIST: a new notice pushes the oldest off WITH an ALARM line naming it.
Remove-Item -LiteralPath $takenFile -Force -ErrorAction SilentlyContinue
$ownId = "11111111-2222-3333-4444-555555555555"
$fullMarks = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt $script:HordeChatTakenKept; $i++) {
    $fid = $(if ($i -eq 0) { $ownId } else { "{0:x8}-0000-0000-0000-000000000000" -f $i })
    [void]$fullMarks.Add((ConvertTo-HordeChatTakenMark -Entry ([pscustomobject]@{ messageId = $fid.Replace("-", ""); messengerId = $fid; postedMs = [long](1000 + $i); from = "00000000000000000000000000000000"; seq = [long](7 + $i); alarmed = $true; woken = $false; session = "" })))
}
Write-HordeTakenLedgerFile -Path $takenFile -Ledger ([pscustomobject]@{ awaiting = @($fullMarks.ToArray()) }) -TempPrefix "test"
$brandNew = Add-HordeDecisionNoticeTaken -Kind $script:HordeDecisionNotifyTakenKind -HordeHome $hordeHome -NoticeId "99999999-2222-3333-4444-555555555555" -Answer 2 -Now $script:now
Check ($brandNew.ok -and @($brandNew.lines).Count -eq 1 -and @($brandNew.lines)[0] -clike ("ALARM: bell notice " + $ownId + " (7 answer(s) of the founder's) left the awaiting list because it is full*") -and @(Marks).Count -eq $script:HordeChatTakenKept) "a full list: a new notice pushes the oldest off WITH an ALARM line naming it, never in silence"
Remove-Item -LiteralPath $takenFile -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "--- the Turn (the relay runner's bell) and the Loop say what the list says ---" -ForegroundColor Cyan
$script:now = $script:now.AddHours(1)
$mem = @{}
$turn = { return (Invoke-HordeDecisionNotifyTurn -Memory $mem -HordeHome $hordeHome -Clock $clock -Seat $seat) }
$numberT = Add-Answered "Should the turned step go ahead?"
$t = & $turn
Advance 0.6
$t = & $turn
Check ($t.outcome -ceq "rang" -and $t.said -clike "*SENT, not yet delivered*" -and @($t.lines).Count -eq 0) ("the Turn rings, and says SENT (" + $t.said + ")")
$idT = "$($script:posts[$script:posts.Count - 1].messageId)"
Advance 2
$t = & $turn
Check (@(Alarms $t.lines).Count -eq 1 -and @($t.lines)[0] -like ("*" + $idT + "*was NOT TAKEN*")) "past the limit the Turn returns the one ALARM line"
Advance 2
$t = & $turn
Check (@($t.lines).Count -eq 0) "and not again at the next turn"
$script:stages[$idT] = "seen"
Advance 6
$t = & $turn
Check (@($t.lines | Where-Object { $_ -clike ("TAKEN: bell notice " + $idT + "*after the alarm: delivered") }).Count -eq 1) "a late TAKEN is returned once"
# An unreadable list is said once, until its words change.
[System.IO.File]::WriteAllText($takenFile, "this is not a ledger")
Advance 2
$t = & $turn
Check (@($t.lines | Where-Object { $_ -like "bell: the awaiting list of doorbell notices cannot be read*" }).Count -eq 1) "an unreadable list is said by the Turn"
Advance 2
$t = & $turn
Check (@($t.lines).Count -eq 0) "and is not said again while its words are the same"
Remove-Item -LiteralPath $takenFile -Force -ErrorAction SilentlyContinue
# The Loop: one pass prints the list's lines.
$loopMark = [pscustomobject]@{ id = "22222222-2222-3333-4444-555555555555" }
Write-HordeTakenLedgerFile -Path $takenFile -Ledger ([pscustomobject]@{ awaiting = @((ConvertTo-HordeChatTakenMark -Entry ([pscustomobject]@{ messageId = $loopMark.id.Replace("-", ""); messengerId = $loopMark.id; postedMs = [long](Get-HordeDecisionNoticeTakenNowMs -Now $script:now) - 600000; from = "00000000000000000000000000000000"; seq = [long]3; alarmed = $false; woken = $false; session = "" }))) }) -TempPrefix "test"
$out = @(Invoke-HordeDecisionNotifyLoop -Once -Clock $clock -Seat $seat)
Check (@($out | Where-Object { $_ -clike ("ALARM: bell notice " + $loopMark.id + "*was NOT TAKEN*") }).Count -eq 1) ("`horde decisions notify` prints the ALARM for a notice the warchief did not take (" + ($out -join " | ") + ")")

Write-Host ""
Write-Host "--- the settings: two numbers a person may tune ---" -ForegroundColor Cyan
$d = (Read-HordeModuleSettingsText -Declaration (Get-HordeDecisionNotifySettingsDeclaration) -Text $null).values
Check ($d.takenAlarmSeconds -eq 90 -and $d.takenAfterAlarmSeconds -eq 300) "takenAlarmSeconds is 90 and takenAfterAlarmSeconds 300 by default, the routed answers' own"
$bad = Read-HordeModuleSettingsText -Declaration (Get-HordeDecisionNotifySettingsDeclaration) -Text '{"schemaVersion":1,"settings":{"takenAlarmSeconds":5}}'
Check ($bad.state -ceq "refused" -and $bad.findings[0] -like "*takenAlarmSeconds*") "an alarm limit under 10 s refuses the file, by name"
}
finally {
    $env:HORDE_HOME = $keepHome
    $env:WEZFLEET_ROOT = $keepFleet
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-HordeSuite -Success "a doorbell notice is delivered only on the warchief's own TAKEN, alarms once when it is not taken in time, and is never dropped"
