# DOES `horde decisions notify` RING ONCE PER SET OF THE FOUNDER'S ANSWERS, NEVER WITH HIS WORDS, AND
# NEVER CLAIM A NOTICE IT DID NOT HAND TO A MESSENGER?
#
# decisions/Notify.ps1, held without any real messenger and without any real session:
#   - THE SETTINGS of the module decisions-notify, and the ONE list of what a messenger must offer.
#   - THE QUIET RULE, pure, on a clock this suite moves: no ring before the quiet period has passed
#     since the newest answer, and none on a reading that began before it ended.
#   - THE TOLD RECORD under the home: written whole, read back, and a record that cannot be read
#     REFUSES (nothing is rung from an empty memory, and the file is left as it was).
#   - THE SEND, through messengers/Port.ps1 to a stand-in messenger registered the way a real one is:
#     one post per set, a messageId made from the set (a retry after a crash is the same message), no
#     answer text in the notice, nothing recorded for a post that was not accepted, a back-off.
#   - NO MESSENGER: pending, said plainly, nothing recorded, and rung once one appears.
#   - THE LOOP: one per home; asked to stop, it still rings for an answer in its quiet period.
# The CLI's notify verb is test/test-decisions-cli.ps1's; the window starting notify is
# test/e2e/e2e-decisions-notify.ps1's.
#
# NOTHING OF THIS MACHINE IS READ. The home is a folder of this suite's own; the warchief's seat is a
# stand-in handed to the pass, so no fleet record is read.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

$work = Join-Path $env:TEMP ("horde-decisions-notify-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$hordeHome = Join-Path $work "home"
$keepHome = $env:HORDE_HOME
$env:HORDE_HOME = $hordeHome
# PINNED, for what this process starts that this suite cannot reach into: Start-HordeDecisionNotifyBeside
# loads Notify.ps1 afresh in a runspace of its own, with every messenger and the real seat reader. The
# messengers' pins hold in this home, and the fleet's registry is a folder that does not exist.
. (Join-Path $root "test\lib\MessengerPins.ps1")
$pins = @(Set-HordeTestMessengerPins -Root $root -HordeHome $hordeHome)
$keepFleet = $env:WEZFLEET_ROOT
$env:WEZFLEET_ROOT = Join-Path $work "no-fleet"
. (Join-Path $root "decisions\Notify.ps1")
$fx = Join-Path $here "fixtures\decisions-notify"
# NO REAL MESSENGER IS EVER ASKED HERE. Notify loads every messenger folder (a real one included, which
# would start the fleet's mail command); this suite keeps only the in-process test messenger and its own
# stand-ins, so a post can never leave the process. The control shows notify did load more than that.
$loadedByNotify = @(Get-HordeMessengerNames)
foreach ($n in $loadedByNotify) { if ($n -cne "memory") { [void]$script:HordeMessengers.Remove($n) } }
Check ($loadedByNotify.Count -ge 2 -and $loadedByNotify -ccontains "memory") ("CONTROL: notify loads every messenger folder (" + ($loadedByNotify -join ", ") + ")")
Check ($pins.Count -ge 1 -and @($pins | Where-Object { -not (Test-Path -LiteralPath (Join-Path $hordeHome ("settings\messenger-" + $_ + ".json")) -PathType Leaf) }).Count -eq 0) ("PIN: every messenger that has a pin is pinned in this suite's home, for the runspace beside a window (" + ($pins -join ", ") + ")")
Check ((@(Get-HordeMessengerNames) -join ",") -ceq "memory") ("only the test messenger is left before any notice is tried (" + (@(Get-HordeMessengerNames) -join ",") + ")")

# THE CLOCK this suite moves, and the seat it hands in.
$script:now = [datetime]::new(2026, 10, 9, 12, 0, 0, [System.DateTimeKind]::Utc)
$clock = { return $script:now }
$script:seatSays = "known"
$seat = { if ($script:seatSays -ceq "known") { return (New-HordeKnown -Value ([pscustomobject]@{ sessionId = "warchief-session-1"; pane = "3"; instance = "t1" })) }; if ($script:seatSays -ceq "absent") { return (New-HordeAbsent -Note "no live session's record names the role warchief") }; return (New-HordeUnknown -Reason "two live sessions each say they are the warchief") }
# THE STAND-IN MESSENGERS' MAIL: every post, and one record per messageId (idempotent, as declared).
$script:posts = New-Object System.Collections.ArrayList
$script:taken = @{}
$script:postSays = "accepted"
$stubPost = {
    param($Message)
    [void]$script:posts.Add($Message)
    if ($script:postSays -ceq "throw") { throw "the stand-in's line is down" }
    if ($script:postSays -ceq "unknown") { return (New-HordeUnknown -Reason "the stand-in could not tell") }
    $id = "$($Message.messageId)"
    if (-not $script:taken.ContainsKey($id)) { $script:taken[$id] = $Message }
    $reason = ""; if ($script:postSays -ceq "held") { $reason = "the stand-in held it" }
    return (New-HordeKnown -Value ([pscustomobject]@{ messageId = $id; stage = $script:postSays; at = [datetime]::UtcNow; reason = $reason }) -ObservedAt ([datetime]::UtcNow))
}
$stubStatus = { param($MessageId) return (New-HordeAbsent -Note "the stand-in keeps no status") }

$script:n = 0
function Add-Question { param([int]$N)
    $q = [ordered]@{ title = ("Should step " + $N + " go ahead?"); kind = "yes-no"; whatItIs = ("Step " + $N + " is ready."); recommendation = "yes"; group = "A group"; askedBy = "Orc A"; waiting = @("Orc A") }
    $a = Invoke-HordeDecision -Operation "add" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = $q }
    if ($a.state -cne "known" -or $a.value.outcome -cne "done") { throw ("question " + $N + " was not added: " + $a.reason) } }
function Say-Founder { param([int]$Number, [string]$Text)
    $a = Invoke-HordeDecision -Operation "say" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "founder"; number = $Number; speaker = "founder"; route = "window"; text = $Text; wordingVersion = 1 }
    if ($a.state -cne "known" -or $a.value.outcome -cne "done") { throw ("the founder's words under " + $Number + " were not saved: " + $a.reason + " " + (@($a.value.findings) -join "; ")) }
    return [long]$a.value.sequence }
function Say-Warchief { param([int]$Number, [string]$Text)
    $a = Invoke-HordeDecision -Operation "say" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; number = $Number; speaker = "warchief"; route = "command"; text = $Text }
    if ($a.state -cne "known" -or $a.value.outcome -cne "done") { throw ("the warchief's words were not saved: " + $a.reason) } }
function Mark-Read { param([long]$UpTo)
    $a = Invoke-HordeDecision -Operation "mark-read" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; upTo = $UpTo }
    if ($a.state -cne "known" -or $a.value.outcome -cne "done") { throw ("mark-read failed: " + $a.reason) } }
# A pass, as the loop makes one: the stand-in seat, this suite's clock, the real store and the real port.
function Pass { param($Tracker) return (Invoke-HordeDecisionNotifyPass -Tracker $Tracker -Clock $clock -Seat $seat) }
$recordPath = Get-HordeDecisionNotifyRecordPath -HordeHome $hordeHome
function Told { $r = Read-HordeDecisionNotifyRecord -Path $recordPath; return @($r.entries | ForEach-Object { [int]$_.question }) }
$defaults = (Read-HordeModuleSettingsText -Declaration (Get-HordeDecisionNotifySettingsDeclaration) -Text $null).values

try {

Write-Host ""
Write-Host "--- every number a person might tune is one setting of the module decisions-notify ---" -ForegroundColor Cyan
$names = @($defaults.PSObject.Properties | ForEach-Object { $_.Name })
Check (($names -join ",") -ceq "quietSeconds,pollSeconds,rereadSeconds,startWithWindow,fromLabel") ("the module declares five settings (" + ($names -join ",") + ")")
Check ($defaults.quietSeconds -eq 30 -and $defaults.pollSeconds -eq 3 -and $defaults.rereadSeconds -eq 30 -and $defaults.startWithWindow -eq $true) "their defaults: 30 s of quiet, the store looked at every 3 s, the inbox read at least every 30 s, started with the window"
Check ($defaults.fromLabel -ceq "F") ("the notice is from the founder's hub label, F, by default (" + $defaults.fromLabel + ")")
$person = Read-HordeModuleSettingsText -Declaration (Get-HordeDecisionNotifySettingsDeclaration) -Text '{"schemaVersion":1,"settings":{"fromLabel":"B12"}}'
Check ($person.state -ceq "read" -and $person.values.fromLabel -ceq "B12") "a person's file may name another hub label"
$badLabel = Read-HordeModuleSettingsText -Declaration (Get-HordeDecisionNotifySettingsDeclaration) -Text '{"schemaVersion":1,"settings":{"fromLabel":"founder"}}'
Check ($badLabel.state -ceq "refused" -and $null -eq $badLabel.values -and @($badLabel.findings).Count -eq 1 -and $badLabel.findings[0] -clike "the settings file 'settings\decisions-notify.json' of decisions-notify is refused: its key 'fromLabel' must be a hub label*") ("a label that is not a hub label refuses the file, by name (" + (@($badLabel.findings) -join " / ") + ")")
Check ((Get-HordeDecisionNotifySettings -HordeHome "C:\h").path -ceq "C:\h\settings\decisions-notify.json") "they are read from settings\decisions-notify.json under Horde's home"
$zero = Read-HordeModuleSettingsText -Declaration (Get-HordeDecisionNotifySettingsDeclaration) -Text '{"schemaVersion":1,"settings":{"quietSeconds":0,"startWithWindow":false}}'
Check ($zero.state -ceq "read" -and $zero.values.quietSeconds -eq 0 -and $zero.values.startWithWindow -eq $false) "a person's file may ring at once (0 s) and keep notify off beside the window"
$long = Read-HordeModuleSettingsText -Declaration (Get-HordeDecisionNotifySettingsDeclaration) -Text '{"schemaVersion":1,"settings":{"quietSeconds":3601}}'
Check ($long.state -ceq "refused" -and $long.findings[0] -like "*quietSeconds*") "a quiet period over an hour refuses the file, by name"

Write-Host ""
Write-Host "--- what a messenger must offer is ONE list: untyped body, idempotent post, wake ---" -ForegroundColor Cyan
Check (((Get-HordeDecisionNotifyMessengerNeeds) -join ",") -ceq "body.untyped,idempotent.post,wake") ("the list is body.untyped, idempotent.post and wake (" + ((Get-HordeDecisionNotifyMessengerNeeds) -join ",") + ")")
Check (@(Get-HordeDecisionNotifyMessengerNeeds) -cnotcontains "receipt.receiver") "and not receipt.receiver: told means handed to the session's mailbox; whether he read it is the store's own mark"
Check (@(Get-HordeMessengerNames) -ccontains "memory") "CONTROL: the in-process test messenger is loaded with the port"

Write-Host ""
Write-Host "--- the quiet rule, on a clock this suite moves ---" -ForegroundColor Cyan
$t0 = $script:now
$item = [pscustomobject]@{ question = 1; message = "5"; at = $t0.ToString("o") }
$seen = @{ "5" = $t0 }
$d = Get-HordeDecisionNotifyDue -Pending @() -FirstSeen @{} -Now $t0 -QuietSeconds 30 -ReadStartedAt $t0 -NextAttemptAt ([datetime]::MinValue)
Check (-not $d.due -and -not $d.reread -and $null -eq $d.wakeAt) "nothing waiting: nothing due and nothing to wake for"
$d = Get-HordeDecisionNotifyDue -Pending @($item) -FirstSeen $seen -Now $t0.AddSeconds(29) -QuietSeconds 30 -ReadStartedAt $t0.AddSeconds(29) -NextAttemptAt ([datetime]::MinValue)
Check (-not $d.due -and $d.wakeAt -eq $t0.AddSeconds(30)) "29 s after the answer: not due, and it wakes when the quiet period ends"
$d = Get-HordeDecisionNotifyDue -Pending @($item) -FirstSeen $seen -Now $t0.AddSeconds(31) -QuietSeconds 30 -ReadStartedAt $t0.AddSeconds(29.5) -NextAttemptAt ([datetime]::MinValue)
Check (-not $d.due -and $d.reread) "quiet has passed, but the reading began before it ended: read again first, never ring on it"
$d = Get-HordeDecisionNotifyDue -Pending @($item) -FirstSeen $seen -Now $t0.AddSeconds(31) -QuietSeconds 30 -ReadStartedAt $t0.AddSeconds(30) -NextAttemptAt ([datetime]::MinValue)
Check ($d.due -and -not $d.reread) "quiet has passed and the reading began at its end: due"
$later = [pscustomobject]@{ question = 2; message = "6"; at = $t0.AddSeconds(20).ToString("o") }
$d = Get-HordeDecisionNotifyDue -Pending @($item, $later) -FirstSeen @{ "5" = $t0; "6" = $t0.AddSeconds(20) } -Now $t0.AddSeconds(35) -QuietSeconds 30 -ReadStartedAt $t0.AddSeconds(35) -NextAttemptAt ([datetime]::MinValue)
Check (-not $d.due -and $d.wakeAt -eq $t0.AddSeconds(50)) "a second answer 20 s later moves the end of the quiet period: the two are one set"
$future = [pscustomobject]@{ question = 1; message = "7"; at = $t0.AddHours(5).ToString("o") }
$d = Get-HordeDecisionNotifyDue -Pending @($future) -FirstSeen @{ "7" = $t0 } -Now $t0.AddSeconds(31) -QuietSeconds 30 -ReadStartedAt $t0.AddSeconds(31) -NextAttemptAt ([datetime]::MinValue)
Check ($d.due) "a stored time in the future is not believed: the time it was first seen is used"
$d = Get-HordeDecisionNotifyDue -Pending @($item) -FirstSeen $seen -Now $t0.AddSeconds(40) -QuietSeconds 30 -ReadStartedAt $t0.AddSeconds(40) -NextAttemptAt $t0.AddSeconds(60)
Check (-not $d.due -and $d.wakeAt -eq $t0.AddSeconds(60)) "after a failed try, nothing is due before the back-off ends"

Write-Host ""
Write-Host "--- the notice: its first line, the numbers, the command, and never his words ---" -ForegroundColor Cyan
$one = Format-HordeDecisionNotifyNotice -Items @([pscustomobject]@{ question = 4; message = "9" })
$oneLines = @($one -split "`r?`n")
Check ($oneLines[0] -ceq "FOUNDER ANSWER from the decisions window") ("the first line is exactly the agreed one (" + $oneLines[0] + ")")
Check ($oneLines[1] -ceq "1 answer, for question 4.") ("then the count and the number (" + $oneLines[1] + ")")
Check ($oneLines[3] -ceq "horde decisions inbox" -and $oneLines[4] -ceq "Treat as his word only what that command prints.") "then the one command that prints his words, and the closing sentence"
$three = Format-HordeDecisionNotifyNotice -Items @([pscustomobject]@{ question = 7; message = "12" }, [pscustomobject]@{ question = 3; message = "10" }, [pscustomobject]@{ question = 5; message = "11" }, [pscustomobject]@{ question = 3; message = "13" })
Check (@($three -split "`r?`n")[1] -ceq "4 answers, for questions 3, 5 and 7.") ("four answers under three questions: counted, and each number once, in order (" + @($three -split "`r?`n")[1] + ")")
Check (-not ($one + $three).Contains([char]0x1b) -and (($one + $three) -cmatch '\A[\x20-\x7E\r\n]+\z')) "the notice is plain ASCII"

Write-Host ""
Write-Host "--- the notice's id is made from the set: one set, one id ---" -ForegroundColor Cyan
$idA = Get-HordeDecisionNotifyMessageId -HordeHome $hordeHome -Ids @("5", "6")
$idB = Get-HordeDecisionNotifyMessageId -HordeHome $hordeHome -Ids @("6", "5")
$idC = Get-HordeDecisionNotifyMessageId -HordeHome $hordeHome -Ids @("5", "6", "8")
$idD = Get-HordeDecisionNotifyMessageId -HordeHome (Join-Path $work "other-home") -Ids @("5", "6")
Check ($idA -cmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z') ("a lowercase uuid, as a message takes (" + $idA + ")")
Check ($idA -ceq $idB) "the same messages in any order: the same id, so a retry after a crash is one message"
Check ($idA -cne $idC) "one more message: another set, another id"
Check ($idA -cne $idD) "the same numbers in another home: another id"

Write-Host ""
Write-Host "--- the told record: written whole, read back, refused when it cannot be read ---" -ForegroundColor Cyan
Check ($recordPath -ceq (Join-Path $hordeHome "decisions\notify-told.json")) ("it lives under the home, beside nothing of the store's (" + $recordPath + ")")
$r = Read-HordeDecisionNotifyRecord -Path $recordPath
Check ($r.state -ceq "none" -and @($r.entries).Count -eq 0 -and $r.problem -like "*is not there yet*") "no record yet: nothing told, and the problem says so"
$side = Join-Path $work "side\told.json"
Write-HordeDecisionNotifyRecord -Path $side -Entries @([pscustomobject]@{ question = 2; message = "14"; at = "2026-10-09T12:00:00Z"; notice = $idA })
$back = Read-HordeDecisionNotifyRecord -Path $side
Check ($back.state -ceq "read" -and @($back.entries).Count -eq 1 -and $back.told.Contains("14") -and [int]$back.entries[0].question -eq 2 -and "$($back.entries[0].notice)" -ceq $idA) "written, then read back: question 2's message 14 is told"
$bytes = [System.IO.File]::ReadAllBytes($side)
Check ($bytes[0] -eq 0x7B -and @($bytes | Where-Object { $_ -gt 0x7E }).Count -eq 0) "UTF-8 with no byte-order mark, and ASCII"
Check (@(Get-ChildItem -LiteralPath (Split-Path -Parent $side)).Count -eq 1) "and no temporary file is left beside it"
$bad = @(
    @{ text = "this is not JSON {"; like = "could not be read as JSON"; what = "text that is not JSON" },
    @{ text = '{"schemaVersion":2,"rung":[]}'; like = "not version 1"; what = "another version" },
    @{ text = '{"schemaVersion":1,"rung":[{"question":1,"message":"x1","at":"2026-10-09T12:00:00Z"}]}'; like = "record number"; what = "an entry whose message is not a record number" },
    @{ text = '{"schemaVersion":1,"rung":[],"rung":[{"question":1,"message":"3","at":"2026-10-09T12:00:00Z"}]}'; like = "twice"; what = "a key given twice" })
foreach ($c in $bad) {
    [System.IO.File]::WriteAllText($side, $c.text)
    $got = Read-HordeDecisionNotifyRecord -Path $side
    Check ($got.state -ceq "refused" -and $got.told.Count -eq 0 -and $got.problem -like ("*" + $c.like + "*")) ("refused, nothing told, and said why: " + $c.what + " (" + $got.problem + ")")
}

Write-Host ""
Write-Host "--- no messenger that can deliver to a session: pending, said plainly, nothing recorded ---" -ForegroundColor Cyan
Add-Question 1; Add-Question 2; Add-Question 3; Add-Question 4; Add-Question 5; Add-Question 6; Add-Question 7; Add-Question 8
$planted = "zebra answer: purple hippo waltz"
$script:now = $t0
$s1 = Say-Founder -Number 1 -Text ($planted + " go ahead")
$tracker = New-HordeDecisionNotifyTracker -QuietSeconds 30
$script:now = [datetime]::UtcNow
$p = Pass $tracker
Check ($p.outcome -ceq "waiting" -and $script:posts.Count -eq 0 -and $p.said -like "waiting:*1 answer*question 1*quiet*") ("an answer just stored waits out its quiet period (" + $p.said + ")")
$script:now = $script:now.AddSeconds(31)
$p = Pass $tracker
Check ($p.outcome -ceq "pending" -and $p.said -like "pending: no messenger on this machine can deliver to a session*") ("then, with only the test messenger loaded: pending, in plain words (" + $p.said + ")")
Check ($p.said -like "*memory*wake*") "and it says what the loaded messenger lacks"
Check ((Read-HordeDecisionNotifyRecord -Path $recordPath).state -ceq "none" -and $script:posts.Count -eq 0) "nothing is recorded as told and nothing was posted"
$noWake = Register-HordeMessenger -Folder (Join-Path $fx "doorbell-no-wake") -Post $stubPost -Status $stubStatus
$script:now = $script:now.AddSeconds(31)
$p = Pass $tracker
Check ($p.outcome -ceq "pending" -and $script:posts.Count -eq 0 -and $p.said -like "*doorbell-no-wake*wake*") ("a messenger that cannot wake is not a doorbell: still pending, nothing posted (" + $p.said + ")")

Write-Host ""
Write-Host "--- a messenger appears: one post for the set, recorded as told, never his words ---" -ForegroundColor Cyan
$bell = Register-HordeMessenger -Folder (Join-Path $fx "doorbell") -Post $stubPost -Status $stubStatus
$script:now = $script:now.AddSeconds(5)
$p = Pass $tracker
Check ($p.outcome -ceq "pending" -and $script:posts.Count -eq 0) "within the back-off after the last try nothing is tried, even with a messenger now there"
$script:now = $script:now.AddSeconds(120)
$p = Pass $tracker
Check ($p.outcome -ceq "rang" -and $script:posts.Count -eq 1) ("after it, one post (" + $p.said + ")")
Check ($p.said -ceq ("rang for 1 answer, on question 1, through messenger doorbell (accepted)")) ("and it says so plainly (" + $p.said + ")")
$m = $script:posts[0]
Check ("$($m.sessionId)" -ceq "warchief-session-1") "addressed to the warchief's session, from its seat"
Check ("$($m.messageId)" -ceq (Get-HordeDecisionNotifyMessageId -HordeHome $hordeHome -Ids @("" + $s1))) "its messageId is the set's"
Check ("$($m.from.sessionId)" -ceq "horde-decisions-notify" -and "$($m.from.deviceId)" -ceq (Get-HordeDeviceId)) "from this machine, as notify"
Check ($null -ne $m.from.PSObject.Properties["label"] -and "$($m.from.label)" -ceq "F") ("and wearing the label F, the founder's, the setting's default (" + $(if ($null -ne $m.from.PSObject.Properties["label"]) { "$($m.from.label)" } else { "no label" }) + ")")
Check (@("$($m.body)" -split "`r?`n")[0] -ceq "FOUNDER ANSWER from the decisions window" -and "$($m.body)".Contains("1 answer, for question 1.")) "the body is the notice"
Check (-not "$($m.body)".Contains("zebra") -and -not "$($m.body)".Contains($planted)) "CONTROL beside it: the planted answer is in the store, and NOT in the notice"
Check ((Invoke-HordeDecision -Operation "show" -Request @{ number = 1 }).value.question.thread.messages[0].text.Contains($planted)) "CONTROL: the store does hold the planted words"
Check (((Told) -join ",") -ceq "1") "the record now tells question 1"
$p = Pass $tracker
Check ($p.outcome -ceq "nothing" -and $script:posts.Count -eq 1) ("a second pass rings nothing (" + $p.said + ")")
$fresh = New-HordeDecisionNotifyTracker -QuietSeconds 30
$p = Pass $fresh
Check ($p.outcome -ceq "nothing" -and $script:posts.Count -eq 1) "a restart (a tracker with no memory) does not ring again for what was told"

Write-Host ""
Write-Host "--- two answers close together are one set; a later answer rings once more ---" -ForegroundColor Cyan
$script:now = [datetime]::UtcNow.AddMinutes(10)
[void](Say-Founder -Number 2 -Text "yes")
[void](Say-Founder -Number 3 -Text "no")
$p = Pass $tracker
Check ($p.outcome -ceq "rang" -and $script:posts.Count -eq 2 -and "$($script:posts[1].body)".Contains("2 answers, for questions 2 and 3.")) ("one post for both (" + $p.said + ")")
[void](Say-Founder -Number 2 -Text "and one more thing")
$script:now = [datetime]::UtcNow.AddMinutes(20)
$p = Pass $tracker
Check ($p.outcome -ceq "rang" -and $script:posts.Count -eq 3 -and "$($script:posts[2].body)".Contains("1 answer, for question 2.")) "a new answer under a question already told rings once more, for itself"
Check (((Told) -join ",") -ceq "1,2,3,2") "and the record holds every message told"

Write-Host ""
Write-Host "--- what does not ring: the warchief's own words, and answers he has read ---" -ForegroundColor Cyan
# The inbox hands the warchief only others' words; today those are the founder's alone. Should a third
# speaker ever have words there, they are not the founder's answer and are not rung for.
$mixed = New-HordeKnown -Value ([pscustomobject]@{ outcome = "done"; messages = @(
    [pscustomobject]@{ number = 2; message = [pscustomobject]@{ speaker = "orc"; sequence = 40; at = "2026-10-09T12:00:00Z" } },
    [pscustomobject]@{ number = 3; message = [pscustomobject]@{ speaker = "founder"; sequence = 41; at = "2026-10-09T12:00:01Z" } }) })
$u = Get-HordeDecisionNotifyUnread -Answer $mixed
Check ($u.ok -and @($u.items).Count -eq 1 -and $u.items[0].message -ceq "41" -and $u.items[0].question -eq 3) "only the founder's words in an inbox are rung for"
Say-Warchief -Number 4 -Text "a note from the warchief"
$script:now = [datetime]::UtcNow.AddMinutes(30)
$p = Pass $tracker
Check ($p.outcome -ceq "nothing" -and $script:posts.Count -eq 3) "the warchief's own message is not the founder's answer"
$s5 = Say-Founder -Number 5 -Text "read before the bell"
Mark-Read -UpTo $s5
$script:now = [datetime]::UtcNow.AddMinutes(40)
$p = Pass $tracker
Check ($p.outcome -ceq "nothing" -and $script:posts.Count -eq 3) "an answer the warchief read before the quiet period ended is not rung for"

Write-Host ""
Write-Host "--- a post that is not accepted: nothing recorded, tried again with back-off, the same id ---" -ForegroundColor Cyan
$s6 = Say-Founder -Number 6 -Text "six"
$script:postSays = "unknown"
$script:now = [datetime]::UtcNow.AddMinutes(50)
$p = Pass $tracker
Check ($p.outcome -ceq "pending" -and $script:posts.Count -eq 4 -and $p.said -like "pending:*could not tell*") ("an unknown answer from the messenger: pending, with its reason (" + $p.said + ")")
Check (-not ((Told) -contains 6)) "and nothing recorded"
$firstTry = $script:now
$script:now = $firstTry.AddSeconds(29)
$p = Pass $tracker
Check ($script:posts.Count -eq 4) "no second try within 30 s"
$script:postSays = "held"
$script:now = $firstTry.AddSeconds(31)
$p = Pass $tracker
Check ($script:posts.Count -eq 5 -and $p.outcome -ceq "pending" -and $p.said -like "*held*") ("tried again after 30 s; held is not told (" + $p.said + ")")
$script:postSays = "throw"
$script:now = $firstTry.AddSeconds(31 + 59)
$p = Pass $tracker
Check ($script:posts.Count -eq 5) "the back-off doubled: no try within 60 s of the second"
$script:now = $firstTry.AddSeconds(31 + 61)
$p = Pass $tracker
Check ($script:posts.Count -eq 6 -and $p.outcome -ceq "pending" -and -not ((Told) -contains 6)) "a messenger that throws: pending, nothing recorded"
$script:postSays = "accepted"
$script:now = $firstTry.AddSeconds(31 + 61 + 121)
$p = Pass $tracker
Check ($p.outcome -ceq "rang" -and ((Told) -contains 6)) "accepted at last: told"
$ids = @($script:posts[3..6] | ForEach-Object { "$($_.messageId)" } | Sort-Object -Unique)
Check ($ids.Count -eq 1) "every try of the one set carried the one id"

Write-Host ""
Write-Host "--- a crash between the post and the record: the retry is the same message ---" -ForegroundColor Cyan
$s7 = Say-Founder -Number 7 -Text "seven"
$keep = [System.IO.File]::ReadAllBytes($recordPath)
$script:now = [datetime]::UtcNow.AddMinutes(60)
$p = Pass $tracker
Check ($p.outcome -ceq "rang") "rung for question 7"
[System.IO.File]::WriteAllBytes($recordPath, $keep)
$p = Pass (New-HordeDecisionNotifyTracker -QuietSeconds 30 -FromLabel "B12")
$sevenId = Get-HordeDecisionNotifyMessageId -HordeHome $hordeHome -Ids @("" + $s7)
Check ("$($script:posts[-1].from.label)" -ceq "B12") ("a notify started with a person's label posts wearing it (" + "$($script:posts[-1].from.label)" + ")")
Check ($p.outcome -ceq "rang" -and @($script:posts | Where-Object { "$($_.messageId)" -ceq $sevenId }).Count -eq 2 -and @($script:taken.Keys | Where-Object { $_ -ceq $sevenId }).Count -eq 1) "the record lost it, so it is posted again - with the same id, which the messenger keeps as one message"

Write-Host ""
Write-Host "--- no seat, a record that cannot be read, two messengers: pending or refused, never a guess ---" -ForegroundColor Cyan
[void](Say-Founder -Number 8 -Text "eight")
$script:now = [datetime]::UtcNow.AddMinutes(70)
$before = $script:posts.Count
$script:seatSays = "absent"
$p = Pass $tracker
Check ($p.outcome -ceq "pending" -and $script:posts.Count -eq $before -and $p.said -like "pending:*warchief*") ("no warchief's session: pending (" + $p.said + ")")
$script:seatSays = "unknown"
$script:now = $script:now.AddSeconds(31)
$p = Pass $tracker
Check ($p.outcome -ceq "pending" -and $script:posts.Count -eq $before -and $p.said -like "*two live sessions*") "a seat that cannot be told: pending, in the seat's own words"
$script:seatSays = "known"
$good = [System.IO.File]::ReadAllBytes($recordPath)
[System.IO.File]::WriteAllText($recordPath, "this is not JSON {")
$script:now = $script:now.AddMinutes(5)
$p = Pass $tracker
Check ($p.outcome -ceq "refused" -and $script:posts.Count -eq $before -and $p.said -like "refused:*could not be read*") ("a record that cannot be read refuses: nothing rung from an empty memory (" + $p.said + ")")
Check ([System.IO.File]::ReadAllText($recordPath) -ceq "this is not JSON {") "and the record is left exactly as it was"
[System.IO.File]::WriteAllBytes($recordPath, $good)
$two = Register-HordeMessenger -Folder (Join-Path $fx "doorbell-two") -Post $stubPost -Status $stubStatus
$p = Pass $tracker
Check ($p.outcome -ceq "pending" -and $script:posts.Count -eq $before -and $p.said -like "*doorbell*doorbell-two*") ("two messengers that could: pending, one is never chosen over the other (" + $p.said + ")")

Write-Host ""
Write-Host "--- the loop: one per home; asked to stop, it rings for an answer still in its quiet period ---" -ForegroundColor Cyan
$script:HordeMessengers.Remove("doorbell-two")
[void](Say-Founder -Number 8 -Text "eight, again")
$script:now = [datetime]::UtcNow.AddSeconds(2)
$stopAsked = $script:now
$stop = New-Object System.Threading.ManualResetEvent($true)
$sleep = { param([double]$Seconds) $script:now = $script:now.AddSeconds([Math]::Max($Seconds, 0.5)) }
$before = $script:posts.Count
# The person's settings file names another label: the loop reads it and its notice wears it.
$settingsFile = (Get-HordeDecisionNotifySettings -HordeHome $hordeHome).path
New-Item -ItemType Directory -Path (Split-Path -Parent $settingsFile) -Force | Out-Null
[System.IO.File]::WriteAllText($settingsFile, '{"schemaVersion":1,"settings":{"fromLabel":"C"}}')
$lines = @(Invoke-HordeDecisionNotifyLoop -Stop $stop -Clock $clock -Sleep $sleep -Seat $seat)
Remove-Item -LiteralPath $settingsFile
Check ("$($script:posts[-1].from.label)" -ceq "C") ("the loop's notice wears the label of the person's settings file (" + "$($script:posts[-1].from.label)" + ")")
Check ($script:posts.Count -eq ($before + 1) -and ((Told) -contains 8) -and ($script:now - $stopAsked).TotalSeconds -ge 25) ("asked to stop with an answer 2 s old: it stayed out the quiet period, rang once, and left (" + ($lines -join " / ") + ")")
Check (@($lines | Where-Object { $_ -like "rang for 2 answers, on question 8*" }).Count -eq 1 -and $lines[-1] -like "stopped*") "and said so, one line per change, ending with stopped"
$once = @(Invoke-HordeDecisionNotifyLoop -Once -Clock $clock -Sleep $sleep -Seat $seat)
Check ($once.Count -eq 1 -and $once[0] -like "nothing to ring for*") ("-Once: one pass, one line (" + ($once -join " / ") + ")")
$beside = Start-HordeDecisionNotifyBeside
$deadline = [datetime]::UtcNow.AddSeconds(60)
while ([datetime]::UtcNow -lt $deadline -and "$($beside.status.said)" -eq "") { Start-Sleep -Milliseconds 200 }
$held = @(Invoke-HordeDecisionNotifyLoop -Once -Clock $clock -Sleep $sleep -Seat $seat)
Check ($held.Count -eq 1 -and $held[0] -like "not run: notify is already running for this home*") ("a second notify for the home leaves at once, saying why (" + ($held -join " / ") + ")")
$last = Stop-HordeDecisionNotifyBeside -Helper $beside -Seconds 60
Check ($beside.status.running -eq $false -and "$last" -like "stopped*") ("the one started beside a window stops when asked (" + $last + ")")
$after = @(Invoke-HordeDecisionNotifyLoop -Once -Clock $clock -Sleep $sleep -Seat $seat)
Check ($after.Count -eq 1 -and $after[0] -notlike "not run*") "and once it has, the home is free again"

}
finally {
    $env:HORDE_HOME = $keepHome
    $env:WEZFLEET_ROOT = $keepFleet
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-HordeSuite -Success "notify rings once per set, through the port, never with his words, and never claims what it did not send"
