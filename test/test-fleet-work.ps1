# IS THE FLEET-WORK RECORD ONE WHOLE LINE PER EVENT, KEPT ONCE, ONLY WITH CONSENT, NEVER CHANGED - AND
# DOES ITS READER FOLD THE LINES INTO WHO WAITS NOW AND WHAT EACH LANE LAST SAID?
#
# core/FleetWork.ps1 (the pure reading of one line, and the pure fold of a file's text) and
# core/FleetWorkStore.ps1 (the append writer behind the metrics consent gate).
# SEEDED WITH REAL SHAPES: test/fixtures/fleet-work/log-real-shapes.jsonl holds the fields of two real
# orchestrator status files and their waiting lines, of 2026-10-07 and 2026-10-08, made general: lane
# names and the words about one person or one product were replaced, the times kept. Every line must
# read. Then every refusal is ATTACKED, each with a control that the same field with ordinary text is
# kept: a rule that refuses everything passes every attack. The writer runs in a home this suite
# creates under TEMP and removes; nothing here reads or writes the real home.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\FleetWorkStore.ps1")

function Section { param([string]$Title) Write-Host ""; Write-Host ("--- " + $Title + " ---") -ForegroundColor Cyan }

$fxDir = Join-Path $root "test\fixtures\fleet-work"
# The fixture's own bytes, with line ends made LF: a checkout may turn them into CRLF, and the CRLF
# case is attacked on its own below.
$realText = ([System.IO.File]::ReadAllText((Join-Path $fxDir "log-real-shapes.jsonl"))) -replace "`r`n", "`n"
$realLines = @($realText.Split([char]10) | Where-Object { $_ -ne "" })
$statusLine = $realLines[0]
$waitLine = $realLines[1]
$endLine = $realLines[5]

function Edit-Line {
    # One fixture line with one change: -Set is given the parsed event to change in place.
    param([string]$Line, [scriptblock]$Set = {})
    $e = $Line | ConvertFrom-Json
    & $Set $e
    return ($e | ConvertTo-Json -Depth 10 -Compress)
}
function Read-Line { param([string]$Line) return (Read-HordeFleetWorkEventText -Text $Line) }
function Test-Refused {
    # Refused, with no event, and with a reason matching -Like.
    param($Answer, [string]$Like)
    return ($Answer.state -ceq "refused" -and $null -eq $Answer.event -and @($Answer.findings | Where-Object { $_ -like $Like }).Count -ge 1)
}
function Test-Reads { param($Answer) return ($Answer.state -ceq "read" -and $null -ne $Answer.event -and @($Answer.findings).Count -eq 0) }
function Show { param($Answer) return ("state=" + $Answer.state + "; " + (@($Answer.findings) -join " | ")) }

Section "every line of the real shapes reads"
Check ($realLines.Count -eq 6) ("CONTROL: the fixture holds six lines (" + $realLines.Count + ")")
$i = 0
foreach ($l in $realLines) { $i++; $a = Read-Line $l; Check (Test-Reads $a) ("fixture line " + $i + " reads (" + (Show $a) + ")") }
$w = Read-Line $waitLine
Check ($w.event.kind -ceq "wait" -and $w.event.values.waitingOn -ceq "owner" -and $w.event.values.since -ceq "2026-10-07T13:00Z") "the wait read is the line's: its kind, who it waits on, since when"
Check ((Test-Reads (Read-Line (Edit-Line $statusLine))) -and (Test-Reads (Read-Line (Edit-Line $waitLine)))) "CONTROL: a line parsed and written again, unchanged, still reads"

Section "the line and its kinds"
$long = Read-Line ($statusLine.Substring(0, $statusLine.Length - 2) + (" " * 2048) + "}}")
Check (Test-Refused $long '*longer than 2048 characters*') ("a line over 2048 characters is refused before it is parsed (" + (Show $long) + ")")
Check (Test-Refused (Read-Line (Edit-Line $statusLine { param($e) $e.kind = "claim" })) "*kind*") "a kind not on the closed list (claim) is refused"
Check (Test-Refused (Read-Line (Edit-Line $statusLine { param($e) $e.kind = "Status" })) "*kind*") "a kind in the wrong case is refused"
Check (Test-Refused (Read-Line (Edit-Line $waitLine { param($e) $e.kind = "status" })) "*values*") "a wait's values under the kind status are refused: values must fit their kind"
Check (Test-Refused (Read-Line (Edit-Line $statusLine { param($e) $e.kind = "wait" })) "*values*") "a status's values under the kind wait are refused"
Check (Test-Refused (Read-Line (Edit-Line $endLine { param($e) $e.kind = "wait" })) "*values*") "a wait-end's values under the kind wait are refused"
Check (Test-Refused (Read-Line (Edit-Line $statusLine { param($e) $e.values | Add-Member -NotePropertyName mood -NotePropertyValue "fine" })) "*values*mood*") "a field a kind does not have is refused"
Check (Test-Refused (Read-Line (Edit-Line $statusLine { param($e) $e.values.PSObject.Properties.Remove("blocked") })) "*values*blocked*") "a status with no blocked is refused"
Check (Test-Refused (Read-Line (Edit-Line $waitLine { param($e) $e.values.waitingOn = "nothing" })) "*waitingOn*") "a wait on nothing is refused: that is no wait"
Check (Test-Reads (Read-Line (Edit-Line $waitLine { param($e) $e.values.waitingOn = "service" }))) "CONTROL: a wait on a service reads"
Check (Test-Refused (Read-Line (Edit-Line $statusLine { param($e) $e.values = "busy" })) "*values*") "values that are not a map are refused"
Check (Test-Refused (Read-Line (Edit-Line $statusLine { param($e) $e | Add-Member -NotePropertyName extra -NotePropertyValue 1 })) "*extra*") "a field the line does not have is refused"
foreach ($field in @("schemaVersion", "kind", "lane", "id", "time", "values")) {
    $a = Read-Line (Edit-Line $statusLine { param($e) $e.PSObject.Properties.Remove($field) }.GetNewClosure())
    Check (Test-Refused $a ("*has no '" + $field + "'*")) ("a line with no " + $field + " is refused")
}
Check (Test-Refused (Read-Line (Edit-Line $statusLine { param($e) $e.schemaVersion = 2 })) "*schemaVersion*") "schemaVersion 2 is refused"
Check (Test-Refused (Read-Line (Edit-Line $statusLine { param($e) $e.id = "0A1F0000000000000000000000000001" })) "*id*") "an id in upper case is refused"
Check (Test-Refused (Read-Line (Edit-Line $statusLine { param($e) $e.id = "0a1f000" })) "*id*") "an id of 7 characters is refused"
Check (Test-Reads (Read-Line (Edit-Line $statusLine { param($e) $e.id = "0a1f0000" }))) "CONTROL: an id of 8 characters reads"
Check (Test-Refused (Read-Line (Edit-Line $statusLine { param($e) $e.lane = ("l" * 65) })) "*lane*") "a lane name of 65 characters is refused"
Check (Test-Reads (Read-Line (Edit-Line $statusLine { param($e) $e.lane = ("l" * 64) }))) "CONTROL: a lane name of 64 characters reads"

Section "texts: bounded, one line, ASCII, and nothing that must not be kept"
Check (Test-Refused (Read-Line (Edit-Line $statusLine { param($e) $e.values.doing = ("d" * 121) })) "*doing*") "a doing of 121 characters is refused"
Check (Test-Reads (Read-Line (Edit-Line $statusLine { param($e) $e.values.doing = ("d" * 120) }))) "CONTROL: a doing of 120 characters reads"
Check (Test-Refused (Read-Line (Edit-Line $waitLine { param($e) $e.values.endsWhen = ("e" * 201) })) "*endsWhen*") "a wait's end condition of 201 characters is refused"
Check (Test-Refused (Read-Line (Edit-Line $statusLine { param($e) $e.values.doing = "" })) "*doing*") "an empty doing is refused"
Check (Test-Refused (Read-Line (Edit-Line $statusLine { param($e) $e.values.doing = "one line`nand a second" })) "*doing*") "a doing of two lines (an escaped line break) is refused"
Check (Test-Refused (Read-Line ($statusLine.Substring(0, 40) + "`n" + $statusLine.Substring(40))) "*one line*") "a line text with a raw line break in it is refused: an event is one line"
$wide = Read-Line ($statusLine -replace "Reviewing", ("Revi" + [char]0x00E9 + "wing"))
Check (Test-Refused $wide "*not ASCII*") ("a raw character that is not ASCII is refused (" + (Show $wide) + ")")
Check (Test-Reads (Read-Line ($statusLine -replace "Reviewing", "Revi\u00e9wing"))) "CONTROL: the same character written as a \u escape reads"
$token = "gh" + "p_" + ("A1b2C3d4" * 3)
$secret = Read-Line (Edit-Line $statusLine { param($e) $e.values.doing = ("Testing with " + $token) }.GetNewClosure())
Check (Test-Refused $secret "*credential*") ("a doing holding an access token is refused (" + (Show $secret) + ")")
Check (-not ((@($secret.findings) -join " ").Contains($token))) "and the refusal does not repeat the token"
$chat = Read-Line (Edit-Line $statusLine { param($e) $e.values.doing = "User: can you fix the list" })
Check (Test-Refused $chat "*conversation*") ("a doing that opens with a speaker's label is refused as conversation (" + (Show $chat) + ")")
Check (Test-Reads (Read-Line (Edit-Line $statusLine { param($e) $e.values.doing = "Fixing the user list" }))) "CONTROL: a doing that names users in plain words reads"
Check (Test-Refused (Read-Line (Edit-Line $waitLine { param($e) $e.values.endsWhen = "a reply from someone@example.com" })) "*customer data*") "an e-mail address in a wait's end condition is refused"
Check (Test-Refused (Read-Line (Edit-Line $statusLine { param($e) $e.values.finished = "Wrote C:\Users\someone\notes.txt" })) "*home folder*") "a path into a person's home folder is refused"
Check (Test-Refused (Read-Line ($statusLine -replace '"blocked":"no",', '"blocked":"no","blocked":"yes",')) "*twice*") "a key said twice in one object is refused"

Section "what the schema cannot say"
Check (Test-Refused (Read-Line (Edit-Line $statusLine { param($e) $e.time = "2026-02-30T10:00:00Z" })) "*time*exists*") "a time on a day that does not exist is refused"
Check (Test-Refused (Read-Line (Edit-Line $waitLine { param($e) $e.values.since = "2026-02-30T10:00Z" })) "*since*exists*") "a since on a day that does not exist is refused"
Check (Test-Refused (Read-Line (Edit-Line $waitLine { param($e) $e.values.since = "2026-10-07T13:06Z" })) "*since*after*") "a wait that starts after its line was written is refused"
Check (Test-Reads (Read-Line (Edit-Line $waitLine { param($e) $e.values.since = "2026-10-07T13:05Z" }))) "CONTROL: a wait that starts as its line is written reads"
Check (Test-Refused (Read-Line (Edit-Line $endLine { param($e) $e.values.ends = $e.id })) "*ends*itself*") "an end that names its own id is refused"
Check (Test-Refused (Read-Line "not json") "*JSON object*") "a line that is not JSON is refused"
Check (Test-Refused (Read-Line "[1,2]") "*JSON object*") "a JSON line that is not an object is refused"

Section "the fold: open waits and the last status per lane"
$fold = Read-HordeFleetWorkLog -Text $realText
Check ($fold.state -ceq "read" -and $fold.lines -eq 6 -and $fold.skipped -eq 0 -and @($fold.findings).Count -eq 0 -and -not $fold.tornTail) ("the real shapes fold with nothing skipped (" + (@($fold.findings) -join " | ") + ")")
Check (@($fold.waits).Count -eq 1 -and $fold.waits[0].id -ceq "0a1f0000000000000000000000000002" -and $fold.waits[0].session -ceq "F" -and $fold.waits[0].waitingOn -ceq "owner" -and $fold.waits[0].since -ceq "2026-10-07T13:00Z" -and $fold.waits[0].lane -ceq "review tooling") "one wait is open: the one no end names, with who waits, on whom and since when"
Check ($fold.ended -eq 1) "the wait the end names is closed, and counted"
$st = @{}; foreach ($s in @($fold.statuses)) { $st[$s.lane] = $s }
Check (@($fold.statuses).Count -eq 2 -and $st["review tooling"].id -ceq "0a1f0000000000000000000000000005" -and $st["capture timing"].id -ceq "0a1f0000000000000000000000000003") "each lane's status is its LAST status line, not its first"
Check ($st["review tooling"].doing -like "Fixing typing lag*" -and $st["review tooling"].blocked -ceq "no" -and $st["review tooling"].time -ceq "2026-10-08T07:30:00.000Z") "the status carries its fields and the time it was written"
$crlf = Read-HordeFleetWorkLog -Text ($realText -replace "`n", "`r`n")
Check ($crlf.lines -eq 6 -and $crlf.skipped -eq 0 -and @($crlf.waits).Count -eq 1 -and -not $crlf.tornTail) "a file with CRLF line ends folds the same"
$empty = Read-HordeFleetWorkLog -Text ""
Check ($empty.state -ceq "read" -and $empty.lines -eq 0 -and @($empty.waits).Count -eq 0 -and @($empty.statuses).Count -eq 0) "an empty text folds to nothing"

Section "the fold, attacked"
$torn = Read-HordeFleetWorkLog -Text ([System.IO.File]::ReadAllText((Join-Path $fxDir "torn-tail.jsonl")))
Check ($torn.tornTail -and $torn.lines -eq 2 -and $torn.skipped -eq 0 -and @($torn.waits).Count -eq 1 -and @($torn.findings | Where-Object { $_ -like "*last line*not ended*" }).Count -eq 1) ("a half-written last line is set aside as torn, not read and not counted broken (" + (@($torn.findings) -join " | ") + ")")
$mid = Read-HordeFleetWorkLog -Text ($realLines[0] + "`n" + '{"schemaVersion":1,"kind":"wai' + "`n" + $realLines[1] + "`n")
Check ($mid.skipped -eq 1 -and $mid.lines -eq 2 -and @($mid.findings | Where-Object { $_ -like "line 2 *" }).Count -ge 1 -and @($mid.waits).Count -eq 1) "a broken line in the middle is skipped and named by its number; the lines around it read"
$dup = Read-HordeFleetWorkLog -Text ($realLines[0] + "`n" + $realLines[1] + "`n" + (Edit-Line $realLines[1] { param($e) $e.values.since = "2026-10-07T12:00Z" }) + "`n")
Check (@($dup.findings | Where-Object { $_ -like "*line 3*id*line 2*" }).Count -eq 1 -and @($dup.waits).Count -eq 1 -and $dup.waits[0].since -ceq "2026-10-07T13:00Z") "a second line with an id already read is named and ignored: the first is kept"
$orphan = Read-HordeFleetWorkLog -Text ($realLines[0] + "`n" + $realLines[1] + "`n" + (Edit-Line $endLine { param($e) $e.values.ends = "0a1f00000000000000000000000000ff" }) + "`n")
Check (@($orphan.findings | Where-Object { $_ -like "*line 3*names no open wait*" }).Count -eq 1 -and @($orphan.waits).Count -eq 1 -and $orphan.ended -eq 0) "an end naming no wait is named, and closes nothing"
$twiceEnd = Read-HordeFleetWorkLog -Text ($realLines[3] + "`n" + $endLine + "`n" + (Edit-Line $endLine { param($e) $e.id = "0a1f0000000000000000000000000007" }) + "`n")
Check (@($twiceEnd.findings | Where-Object { $_ -like "*line 3*already ended*" }).Count -eq 1 -and $twiceEnd.ended -eq 1) "a second end of the same wait is named, and counted once"
$early = Read-HordeFleetWorkLog -Text ($endLine + "`n" + $realLines[3] + "`n")
Check (@($early.findings | Where-Object { $_ -like "*line 1*names no open wait*" }).Count -eq 1 -and @($early.waits).Count -eq 1) "an end before its wait in the file closes nothing: the file's order is the record's"
$other = Read-HordeFleetWorkLog -Text ($realLines[3] + "`n" + (Edit-Line $endLine { param($e) $e.lane = "review tooling" }) + "`n")
Check (@($other.findings | Where-Object { $_ -like "*line 2*another lane*" }).Count -eq 1 -and @($other.waits).Count -eq 1) "an end from another lane does not close the wait"
$two = Read-HordeFleetWorkLog -Text ($realLines[1] + "`n" + (Edit-Line $realLines[1] { param($e) $e.id = "0a1f0000000000000000000000000009"; $e.values.waitingOn = "lane" }) + "`n")
Check (@($two.waits).Count -eq 2 -and @($two.findings).Count -eq 0) "CONTROL: one session may wait on two things at once"

Section "the kinds the fleet's own send command writes: send, mail, restart"
# Task T-0073: three records the fleet analyst asked to be written at the moment they happen, by the
# fleet's terminal-orchestration tool rather than by Horde. Each is one line of this same file, so the
# kinds join the closed list here, each with its values fixed below. They hold no message text: counts,
# times in milliseconds, closed lists, labels and mail ids only.
#   send     one per tell: how it went (route, outcome) and how long each step took
#   mail     one per mail queued: its kind, and the id of the mail it answers
#   restart  one per roll call after a terminal restart: sessions found, missing and repaired
$sendLine = '{"schemaVersion":1,"kind":"send","lane":"review tooling","id":"0b2f0000000000000000000000000001","time":"2026-10-08T09:00:05.120Z","values":{"mailId":"a1b2c3d4e5","outcome":"woken","queuedMs":180,"ranMs":20410,"route":"mail","session":"F","to":"M","wokenMs":2350}}'
$mailLine = '{"schemaVersion":1,"kind":"mail","lane":"review tooling","id":"0b2f0000000000000000000000000002","time":"2026-10-08T09:00:05.300Z","values":{"answers":"f0e1d2c3b4","from":"F","mailId":"a1b2c3d4e5","messageKind":"answer","to":"M"}}'
$restartLine = '{"schemaVersion":1,"kind":"restart","lane":"master","id":"0b2f0000000000000000000000000003","time":"2026-10-08T07:12:00.000Z","values":{"found":8,"missing":1,"repaired":7,"session":"M"}}'
foreach ($k in @(@("send", $sendLine), @("mail", $mailLine), @("restart", $restartLine))) {
    $a = Read-Line $k[1]
    Check (Test-Reads $a) ("a " + $k[0] + " line reads (" + (Show $a) + ")")
}
Check ((Read-Line $sendLine).event.values.ranMs -eq 20410) "the send read is the line's: how long the send ran"
$minimalSend = Edit-Line $sendLine { param($e) $e.values.PSObject.Properties.Remove("wokenMs"); $e.values.PSObject.Properties.Remove("mailId"); $e.values.PSObject.Properties.Remove("queuedMs"); $e.values.route = "keys"; $e.values.outcome = "delivered" }
Check (Test-Reads (Read-Line $minimalSend)) "a send by keystrokes, with no mail id and no step times, reads"
Check (Test-Reads (Read-Line (Edit-Line $mailLine { param($e) $e.values.PSObject.Properties.Remove("answers"); $e.values.messageKind = "unmarked" }))) "a mail that answers nothing, and whose kind was not given, reads"
Check (Test-Reads (Read-Line (Edit-Line $mailLine { param($e) $e.values.mailId = ("ab" * 16); $e.values.answers = ("cd" * 16) }))) "CONTROL: a 32-hex mail id (a posted one) reads too"
# attacked: each with a control above that the same field with an ordinary value is kept
Check (Test-Refused (Read-Line (Edit-Line $sendLine { param($e) $e.values.outcome = "probably" })) "*outcome*") "a send outcome not on its closed list is refused"
Check (Test-Refused (Read-Line (Edit-Line $sendLine { param($e) $e.values.route = "pigeon" })) "*route*") "a send route not on its closed list is refused"
Check (Test-Refused (Read-Line (Edit-Line $sendLine { param($e) $e.values.ranMs = -1 })) "*ranMs*") "a negative duration is refused"
Check (Test-Refused (Read-Line (Edit-Line $sendLine { param($e) $e.values.ranMs = "20s" })) "*ranMs*") "a duration that is not a whole number is refused"
Check (Test-Refused (Read-Line (Edit-Line $sendLine { param($e) $e.values.PSObject.Properties.Remove("ranMs") })) "*ranMs*") "a send without how long it ran is refused"
Check (Test-Refused (Read-Line (Edit-Line $sendLine { param($e) $e.values.wokenMs = 30000 })) "*wokenMs*longer*") "a step that took longer than the whole send is refused"
Check (Test-Refused (Read-Line (Edit-Line $sendLine { param($e) $e.values | Add-Member -NotePropertyName body -NotePropertyValue "hello" })) "*body*") "a send carrying a field outside its kind (a body) is refused"
Check (Test-Refused (Read-Line (Edit-Line $mailLine { param($e) $e.values.messageKind = "gossip" })) "*messageKind*") "a message kind not on its closed list is refused"
Check (Test-Refused (Read-Line (Edit-Line $mailLine { param($e) $e.values.mailId = "M-17" })) "*mailId*") "a mail id that is not one the store writes is refused"
Check (Test-Refused (Read-Line (Edit-Line $mailLine { param($e) $e.values.answers = $e.values.mailId })) "*answers*itself*") "a mail that answers itself is refused"
Check (Test-Refused (Read-Line (Edit-Line $restartLine { param($e) $e.values.missing = -2 })) "*missing*") "a negative count of missing sessions is refused"
Check (Test-Refused (Read-Line (Edit-Line $restartLine { param($e) $e.values.repaired = 9 })) "*repaired*more*") "more sessions repaired than were found is refused"
Check (Test-Refused (Read-Line (Edit-Line $restartLine { param($e) $e.values = $null })) "*values*") "a restart with no values is refused"
# the fold reads these lines and counts them, and they open no wait and replace no status
$foldNew = Read-HordeFleetWorkLog -Text ($realText + $sendLine + "`n" + $mailLine + "`n" + $restartLine + "`n")
Check ($foldNew.lines -eq 9 -and $foldNew.skipped -eq 0 -and @($foldNew.waits).Count -eq 1 -and @($foldNew.statuses).Count -eq 2) ("the fold reads the three new lines beside the real shapes, and they change no wait and no status (lines " + $foldNew.lines + ", skipped " + $foldNew.skipped + ")")

Section "the writer: consent"
$work = Join-Path $env:TEMP ("horde-fleet-work-" + [guid]::NewGuid().ToString("N"))
$savedHome = $env:HORDE_HOME
try {
    $env:HORDE_HOME = Join-Path $work "home"
    $metrics = Join-Path $env:HORDE_HOME "metrics"
    $log = Get-HordeFleetWorkLogPath
    Check ($log -ceq (Join-Path $metrics "fleet-work\events.jsonl")) "the record is <home>\metrics\fleet-work\events.jsonl"
    $ev = New-HordeFleetWorkEvent -Kind "status" -Lane "review tooling" -Values @{ session = "F"; doing = "Testing"; finished = "Nothing yet"; blocked = "no" }
    $off = Save-HordeFleetWorkEvent -Event $ev
    Check ($off.state -ceq "off" -and @($off.findings | Where-Object { $_ -like "*off*" }).Count -ge 1 -and -not (Test-Path -LiteralPath $metrics)) ("with no gate file nothing is written, no folder made, and the answer says metrics are off (" + (Show $off) + ")")
    New-Item -ItemType Directory -Path $metrics -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $metrics "gate.json"), '{ "schemaVersion": 1, "level": "off", "enabledAt": "2026-10-01T00:00:00Z" }')
    $lvOff = Save-HordeFleetWorkEvent -Event $ev
    Check ($lvOff.state -ceq "off" -and -not (Test-Path -LiteralPath $log)) "with the gate at level off nothing is written"
    [System.IO.File]::WriteAllText((Join-Path $metrics "gate.json"), '{ "schemaVersion": 1, "level": "usage", ')
    $bad = Save-HordeFleetWorkEvent -Event $ev
    Check ($bad.state -ceq "off" -and @($bad.findings | Where-Object { $_ -like "*refused*" }).Count -ge 1 -and -not (Test-Path -LiteralPath $log)) "with a gate that cannot be read nothing is written: unreadable consent is not consent"
    [System.IO.File]::WriteAllText((Join-Path $metrics "gate.json"), '{ "schemaVersion": 1, "level": "usage", "enabledAt": "2026-10-01T00:00:00Z" }')
    $old = New-HordeFleetWorkEvent -Kind "status" -Lane "review tooling" -Time "2026-09-30T23:59:59.000Z" -Values @{ session = "F"; doing = "Testing"; finished = "Nothing yet"; blocked = "no" }
    $pre = Save-HordeFleetWorkEvent -Event $old
    Check ($pre.state -ceq "off" -and @($pre.findings | Where-Object { $_ -like "*event's time*before*consent*" }).Count -ge 1 -and -not (Test-Path -LiteralPath $log)) "an event from before consent is not written"
    $refused = Save-HordeFleetWorkEvent -Event (New-HordeFleetWorkEvent -Kind "status" -Lane "review tooling" -Values @{ session = "F"; doing = ("d" * 121); finished = "x"; blocked = "no" })
    Check ($refused.state -ceq "refused" -and -not (Test-Path -LiteralPath (Split-Path -Parent $log))) "an event that does not read is refused, and nothing is created"

    Section "the writer: one whole line per event, once"
    Check ($ev.id -cmatch '\A[0-9a-f]{32}\z' -and $ev.time -cmatch '\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z\z') "a new event has a 32-hex id and the time it was made, in UTC"
    $w1 = Save-HordeFleetWorkEvent -Event $ev
    $bytes1 = [System.IO.File]::ReadAllBytes($log)
    $text1 = [System.Text.Encoding]::ASCII.GetString($bytes1)
    Check ($w1.state -ceq "written" -and $w1.path -ceq $log) ("with consent the event is written (" + (Show $w1) + ")")
    Check ($text1.EndsWith("`n") -and @($text1.Split([char]10) | Where-Object { $_ -ne "" }).Count -eq 1 -and -not $text1.Contains("`r")) "the file holds exactly one line, ended by one LF"
    Check ((Read-HordeFleetWorkEventText -Text $text1.TrimEnd([char]10)).state -ceq "read") "the line written reads"
    $again = Save-HordeFleetWorkEvent -Event $ev
    Check ($again.state -ceq "exists" -and @($again.findings).Count -eq 0 -and [System.IO.File]::ReadAllText($log) -ceq $text1) "the same event written again is 'exists', and adds no line"
    $changed = [ordered]@{}; foreach ($k in $ev.Keys) { $changed[$k] = $ev[$k] }
    $changed.values = @{ session = "F"; doing = "Something else"; finished = "Nothing yet"; blocked = "no" }
    $retry = Save-HordeFleetWorkEvent -Event $changed
    Check ($retry.state -ceq "exists" -and @($retry.findings | Where-Object { $_ -like "*differs*" }).Count -eq 1 -and [System.IO.File]::ReadAllText($log) -ceq $text1) "an id already kept with other content is 'exists', says it differs, and changes nothing"
    $wait = New-HordeFleetWorkEvent -Kind "wait" -Lane "review tooling" -Values @{ session = "F"; waitingOn = "owner"; since = "2026-10-07T13:00Z"; endsWhen = "his word on the plan" }
    $w2 = Save-HordeFleetWorkEvent -Event $wait
    $bytes2 = [System.IO.File]::ReadAllBytes($log)
    $prefixSame = $true; for ($b = 0; $b -lt $bytes1.Length; $b++) { if ($bytes2[$b] -ne $bytes1[$b]) { $prefixSame = $false; break } }
    Check ($w2.state -ceq "written" -and $bytes2.Length -gt $bytes1.Length -and $prefixSame) "a second event is appended: every byte before it is unchanged"
    $sneaky = New-HordeFleetWorkEvent -Kind "status" -Lane "review tooling" -Values @{ session = "F"; doing = (',"id":"' + $wait.id + '"'); finished = "x"; blocked = "no" }
    Check ((Save-HordeFleetWorkEvent -Event $sneaky).state -ceq "written") "an id quoted inside a text is not taken for a line's id"
    $uni = New-HordeFleetWorkEvent -Kind "status" -Lane "capture timing" -Values @{ session = "G"; doing = ("Caf" + [char]0x00E9 + " list"); finished = "x"; blocked = "no" }
    $wu = Save-HordeFleetWorkEvent -Event $uni
    $allBytes = [System.IO.File]::ReadAllBytes($log)
    Check ($wu.state -ceq "written" -and @($allBytes | Where-Object { $_ -gt 127 }).Count -eq 0 -and [System.Text.Encoding]::ASCII.GetString($allBytes).Contains("Caf\u00e9")) "a character that is not ASCII is written as a \u escape: the file stays ASCII"
    $folded = Read-HordeFleetWorkFile
    Check ($folded.lines -eq 4 -and @($folded.waits).Count -eq 1 -and $folded.waits[0].id -ceq $wait.id -and @($folded.statuses).Count -eq 2) "the file reads back: four lines, the open wait, a status per lane"

    Section "the writer: a torn last line, and a held file"
    $fs = New-Object System.IO.FileStream($log, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write)
    $half = [System.Text.Encoding]::ASCII.GetBytes('{"schemaVersion":1,"kind":"sta')
    $fs.Write($half, 0, $half.Length); $fs.Dispose()
    $beforeTorn = [System.IO.File]::ReadAllBytes($log)
    $end = New-HordeFleetWorkEvent -Kind "wait-end" -Lane "review tooling" -Values @{ ends = $wait.id; unblockedBy = "his word came" }
    $w3 = Save-HordeFleetWorkEvent -Event $end
    $afterTorn = [System.IO.File]::ReadAllBytes($log)
    $kept = $true; for ($b = 0; $b -lt $beforeTorn.Length; $b++) { if ($afterTorn[$b] -ne $beforeTorn[$b]) { $kept = $false; break } }
    $tornFold = Read-HordeFleetWorkFile
    Check ($w3.state -ceq "written" -and $kept -and $afterTorn[$beforeTorn.Length] -eq 10) "after a torn last line the next event starts on a line of its own; the torn bytes are left as they are"
    Check ($tornFold.lines -eq 5 -and $tornFold.skipped -eq 1 -and @($tornFold.waits).Count -eq 0 -and $tornFold.ended -eq 1 -and -not $tornFold.tornTail) ("the torn line is skipped as broken, and the end after it closes the wait (" + (@($tornFold.findings) -join " | ") + ")")
    $held = New-Object System.IO.FileStream($log, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read)
    try {
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $busy = Save-HordeFleetWorkEvent -Event (New-HordeFleetWorkEvent -Kind "status" -Lane "capture timing" -Values @{ session = "G"; doing = "y"; finished = "x"; blocked = "no" }) -WaitMs 300
        $timer.Stop()
        Check ($timer.ElapsedMilliseconds -ge 250) ("a held file is waited for before 'busy' is said (" + $timer.ElapsedMilliseconds + " ms of 300)")
        Check ($busy.state -ceq "busy" -and ([System.IO.FileInfo]::new($log)).Length -eq $afterTorn.Length) "while another writer holds the file, a write waits, then answers 'busy' and adds nothing"
    } finally { $held.Dispose() }
    Check ((Save-HordeFleetWorkEvent -Event (New-HordeFleetWorkEvent -Kind "status" -Lane "capture timing" -Values @{ session = "G"; doing = "y"; finished = "x"; blocked = "no" }) -WaitMs 300).state -ceq "written") "CONTROL: once it is let go, the same write goes through"
    $mine = Open-HordeFleetWorkLog -Path $log -WaitMs 0
    try {
        Check ($null -ne $mine -and $null -eq (Open-HordeFleetWorkLog -Path $log -WaitMs 100)) "while one writer has the record open, a second cannot open it for writing"
        Check ((Read-HordeFleetWorkFile).lines -ge 5) "and a reader still reads it"
    } finally { if ($null -ne $mine) { $mine.Dispose() } }

    Section "the writer: an id is kept only by a line that reads"
    $brokenId = New-HordeFleetWorkEventId
    [System.IO.File]::AppendAllText($log, ('{"schemaVersion":1,"kind":"status","lane":"x","id":"' + $brokenId + '","time":"not a time"}' + "`n"))
    $afterBroken = Save-HordeFleetWorkEvent -Event (New-HordeFleetWorkEvent -Kind "status" -Lane "capture timing" -Id $brokenId -Values @{ session = "G"; doing = "y"; finished = "x"; blocked = "no" })
    Check ($afterBroken.state -ceq "written") "an ended line that holds an id but does not read is no kept event: the event is written"
    $tornEvent = New-HordeFleetWorkEvent -Kind "status" -Lane "capture timing" -Values @{ session = "G"; doing = "torn"; finished = "x"; blocked = "no" }
    [System.IO.File]::AppendAllText($log, (ConvertTo-HordeFleetWorkLine -FleetEvent $tornEvent))
    $afterWhole = Save-HordeFleetWorkEvent -Event $tornEvent
    $wholeFold = Read-HordeFleetWorkFile
    Check ($afterWhole.state -ceq "written" -and @($wholeFold.findings | Where-Object { $_ -like "*repeats the id*" }).Count -eq 1) "a whole line with no LF is not kept yet: the retry writes it on a line of its own, and the reader keeps the first"

    Section "the writer: a failure that is not a held file"
    $env:HORDE_HOME = Join-Path $work "home-two"
    $metricsTwo = Join-Path $env:HORDE_HOME "metrics"
    New-Item -ItemType Directory -Path (Join-Path $metricsTwo "fleet-work\events.jsonl") -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $metricsTwo "gate.json"), '{ "schemaVersion": 1, "level": "usage", "enabledAt": "2026-10-01T00:00:00Z" }')
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $threw = Throws { Save-HordeFleetWorkEvent -Event (New-HordeFleetWorkEvent -Kind "status" -Lane "capture timing" -Values @{ session = "G"; doing = "y"; finished = "x"; blocked = "no" }) -WaitMs 2000 }
    $timer.Stop()
    Check ($threw -and $timer.ElapsedMilliseconds -lt 1500) ("a record that cannot be opened for another reason (a folder in its place) throws at once, never 'busy' (" + $timer.ElapsedMilliseconds + " ms)")
} finally {
    $env:HORDE_HOME = $savedHome
    if ((Split-Path -Leaf $work) -match '^horde-fleet-work-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

Section "nothing is sent anywhere"
# A text scan, with its control: the same scan finds a network call planted in a copy of the writer.
$netPattern = '(?i)Net\.WebClient|Net\.Http|Net\.Sockets|Invoke-WebRequest|Invoke-RestMethod|Send-MailMessage|\\remote\\|\\transports\\|Messaging\.ps1'
$storeText = [System.IO.File]::ReadAllText((Join-Path $root "core\FleetWorkStore.ps1"))
$readerText = [System.IO.File]::ReadAllText((Join-Path $root "core\FleetWork.ps1"))
Check (-not [regex]::IsMatch($storeText, $netPattern) -and -not [regex]::IsMatch($readerText, $netPattern)) "neither file names a network call, a transport or the remote link"
Check ([regex]::IsMatch(($storeText + "`nInvoke-RestMethod -Uri x"), $netPattern)) "CONTROL: the scan finds a network call planted in the writer's text"

Complete-HordeSuite -Success "a fleet-work event is one whole line, kept once, only with consent; the fold and every refusal held"
