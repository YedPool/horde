# IS AN ORC'S STATUS RECORD READ WHOLE, OR NOT AT ALL?
#
# fleet/StatusPanel.ps1 reads the record each Orc keeps (six lines, or seven with the optional waiting on line) and hands it to a panel. A record
# that breaks a rule must come out as "no status written" with what was wrong, and with NONE of its
# fields - a panel that showed half a broken record would be guessing. Every shape of wrong the
# record's own checker knows is here: a byte-order mark, a byte outside ASCII, the wrong number of
# lines, a missing header, a line that is not its key, a line over its length, a bare reference or a
# path. Then this reader's own: a letter that is not one, two folders claiming one letter, a missing
# file, a file far too large. Every folder is one this suite made in %TEMP%; nothing is written
# anywhere else, and the reader writes nothing at all.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "fleet\StatusPanel.ps1")

$work = Join-Path $env:TEMP ("horde-fleet-status-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$now = [datetime]::new(2026, 10, 7, 12, 0, 0, [System.DateTimeKind]::Utc)
$partial = $false
$good = @("horde-orc-status 1", "orc: F", "lane: decisions page", "doing: Building the read-only window on the real list of questions", "finished: The list and its commands are up for review", "blocked: no")
function Bytes { param([string[]]$Lines, [string]$Break = "`n") return [System.Text.Encoding]::ASCII.GetBytes(($Lines -join $Break) + $Break) }
function Parse { param([byte[]]$B) return (ConvertFrom-HordeFleetStatusBytes -Bytes $B) }
function With { param([int]$Line, [string]$Text) $copy = @($good); $copy[$Line] = $Text; return $copy }
function Says { param($R, [string]$Text) return (@($R.problems | Where-Object { "$_".Contains($Text) }).Count -gt 0) }
function New-Orc {
    param([string]$Fleet, [string]$Folder, $Lines = $null, [int]$AgeSeconds = 90, [byte[]]$Raw = $null)
    $dir = Join-Path (Join-Path $work $Fleet) $Folder
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    if ($null -eq $Lines -and $null -eq $Raw) { return $dir }
    $file = Join-Path $dir "status.txt"
    if ($null -ne $Raw) { [System.IO.File]::WriteAllBytes($file, $Raw) } else { [System.IO.File]::WriteAllBytes($file, (Bytes $Lines)) }
    [System.IO.File]::SetLastWriteTimeUtc($file, $now.AddSeconds(-$AgeSeconds))
    return $dir
}

try {

Write-Host ""
Write-Host "--- a record that keeps every rule ---" -ForegroundColor Cyan
$ok = Parse (Bytes $good)
Check (@($ok.problems).Count -eq 0 -and $ok.fields["orc"] -ceq "F" -and $ok.fields["lane"] -ceq "decisions page" -and $ok.fields["blocked"] -ceq "no") "six lines in order: no problem, and each value is what follows its key"
Check ((@($ok.fields.Keys) -join ",") -ceq "orc,lane,doing,finished,blocked") "the five fields, in the record's order"
Check (@((Parse (Bytes $good "`r`n")).problems).Count -eq 0) "CONTROL: the same record with Windows line endings is the same record"
Check (@((Parse ([System.Text.Encoding]::ASCII.GetBytes($good -join "`n"))).problems).Count -eq 0) "CONTROL: and so is one with no line break after its last line"
$long = With 3 ("doing: " + ("x" * 120))
Check (@((Parse (Bytes $long)).problems).Count -eq 0) "CONTROL: a doing of exactly 120 characters is within the rule"

Write-Host ""
Write-Host "--- the seven shapes of wrong the record's checker knows ---" -ForegroundColor Cyan
$bom = Parse ([byte[]](@(0xEF, 0xBB, 0xBF) + (Bytes $good)))
Check ((Says $bom "starts with a byte-order mark") -and @($bom.problems).Count -eq 1 -and $null -eq $bom.fields) "1. a byte-order mark: one problem, and no field is passed on though the rest is a good record"
$nonAscii = Parse ([System.Text.Encoding]::UTF8.GetBytes(((With 3 ("doing: Fixing the caf" + [char]0x00E9 + " menu")) -join "`n") + "`n"))
Check ((Says $nonAscii "holds bytes that are not ASCII") -and $null -eq $nonAscii.fields) "2. a byte outside ASCII"
$five = Parse (Bytes $good[0..4])
Check ((Says $five "has 5 lines, and a record is 6") -and $null -eq $five.fields) "3. five lines"
$eight = Parse (Bytes ($good + @("waiting on: the founder, since 2026-10-13", "note: one line too many")))
Check ((Says $eight "has 8 lines, and a record is 6, or 7 with its waiting-on line, so line 8 is one too many") -and @($eight.problems).Count -eq 1 -and $null -eq $eight.fields) "3. an eighth line is refused, naming it, though the seven before it are a good record"
Check ((Says (Parse (Bytes ($good + @("waiting on: x", "waiting on: y", "waiting on: z")))) "so line 8 is one too many")) "3. nine lines: the first one too many is named"
$noHeader = Parse (Bytes (With 0 "horde-orc-status 2"))
Check ((Says $noHeader "does not begin with the line 'horde-orc-status 1'") -and $null -eq $noHeader.fields) "4. a first line that is not the header"
$wrongKey = Parse (Bytes (With 2 "area: decisions page"))
Check ((Says $wrongKey "line 3 is not 'lane: ...'") -and @($wrongKey.problems).Count -eq 1 -and $null -eq $wrongKey.fields) "5. a line that is not its key"
$swapped = Parse (Bytes @($good[0], $good[1], $good[2], $good[4], $good[3], $good[5]))
Check ((Says $swapped "line 4 is not 'doing: ...'") -and (Says $swapped "line 5 is not 'finished: ...'")) "5. two lines in each other's place: each is not its key"
$blankValue = Parse (Bytes (With 4 "finished:   "))
Check ((Says $blankValue "line 5 is not 'finished: ...'") -and $null -eq $blankValue.fields) "5. a key with nothing after it"
$noSpace = Parse (Bytes (With 5 "blocked:no"))
Check ((Says $noSpace "line 6 is not 'blocked: ...'")) "5. a key with no space after its colon"
$tooLong = Parse (Bytes (With 3 ("doing: " + ("x" * 121))))
Check ((Says $tooLong "doing is 121 characters, and the most is 120") -and $null -eq $tooLong.fields) "6. a doing of 121 characters"
$tooLongDone = Parse (Bytes (With 4 ("finished: " + ("y" * 200))))
Check ((Says $tooLongDone "finished is 200 characters")) "6. a finished of 200"
foreach ($bare in @("doing: Reviewing PR 68", "doing: Waiting on pull request #12", "doing: Closing issue 94 today", "doing: Second pass on #110", "doing: Editing C:\work\notes.md")) {
    $r = Parse (Bytes (With 3 $bare))
    Check ((Says $r "doing holds a bare reference or a path") -and $null -eq $r.fields) ("7. '" + $bare.Substring(7) + "' is a bare reference or a path, where plain words are wanted")
}
Check (@((Parse (Bytes (With 3 "doing: Reviewing the fix for garbled mail, the first of 3 parts"))).problems).Count -eq 0) "CONTROL: plain words that hold a number are not a reference"
Check ((Says (Parse (Bytes (With 4 "finished: Merged PR 106"))) "finished holds a bare reference or a path")) "7. the same rule holds finished"
Check (@((Parse (Bytes (With 2 "lane: tidying C:\work after PR 9"))).problems).Count -eq 0) "CONTROL: the rule is doing's and finished's alone, as the checker has it"

Write-Host ""
Write-Host "--- a control character is no part of a record ---" -ForegroundColor Cyan
# A record with an escape, a NUL or a backspace in a field was "written" and handed on (measured
# 2026-10-06 by the review of this reader). The record is plain words on six lines, or seven with the optional waiting on line; the only bytes
# below a space it may hold are the ends of its lines.
foreach ($ctl in @(@{ byte = 0x1B; name = "an escape" }, @{ byte = 0x00; name = "a NUL" }, @{ byte = 0x08; name = "a backspace" }, @{ byte = 0x09; name = "a tab" }, @{ byte = 0x7F; name = "a delete" })) {
    $r = Parse (Bytes (With 3 ("doing: Building" + [string][char]$ctl.byte + "the window")))
    Check ((Says $r "holds a control character") -and @($r.problems).Count -eq 1 -and $null -eq $r.fields) ($ctl.name + " in a field: one problem, and no field is passed on")
}
$ctlLane = Parse (Bytes (With 2 ("lane: decisions" + [string][char]0x1B + "[31m page")))
Check ((Says $ctlLane "holds a control character") -and $null -eq $ctlLane.fields) "in any field, not only the two that are held to plain words"
$lone = Parse ([System.Text.Encoding]::ASCII.GetBytes(($good -join "`n").Replace("decisions page", "decisions`rpage") + "`n"))
Check ((Says $lone "holds a control character") -and $null -eq $lone.fields) "a carriage return that ends no line is one too"
Check (@((Parse (Bytes $good "`r`n")).problems).Count -eq 0 -and @((Parse (Bytes $good)).problems).Count -eq 0) "CONTROL: the ends of the six lines, in either form, are not"

Write-Host ""
Write-Host "--- the optional seventh line: waiting on (adopted by the fleet 2026-10-13) ---" -ForegroundColor Cyan
# Every Orc's record gained a seventh line on 2026-10-13, and this reader, which held a record to six,
# showed every Orc as "no status written". The line is optional, its key is exactly "waiting on", and
# the whole line is at most 200 characters, as the record's own checker has it (check-status.py, its
# line 18): the eight real seventh lines read 2026-10-14 were 77 to 136 characters long. Its value is
# held to the plain words of doing and finished, a rule this reader adds.
$withWait = $good + @("waiting on: the founder, since 2026-10-07 13:00, unblocked by his word on installing the server feature")
$waits = Parse (Bytes $withWait)
Check (@($waits.problems).Count -eq 0 -and $waits.fields["waiting on"] -ceq "the founder, since 2026-10-07 13:00, unblocked by his word on installing the server feature" -and $waits.fields["doing"] -ceq $ok.fields["doing"] -and $waits.fields["blocked"] -ceq "no") "a record with a waiting-on seventh line is read whole: no problem, the line's value, and the six before it as they were"
Check ((@($waits.fields.Keys) -join ",") -ceq "orc,lane,doing,finished,blocked,waiting on") "its six fields, in the record's order"
Check (@((Parse (Bytes $withWait "`r`n")).problems).Count -eq 0) "CONTROL: and with Windows line endings, as the fleet writes it"
Check (@($ok.problems).Count -eq 0 -and $null -eq $ok.fields["waiting on"] -and -not $ok.fields.Contains("waiting on")) "a six-line record is still read, and has no waiting-on field at all"
$waitBom = Parse ([byte[]](@(0xEF, 0xBB, 0xBF) + (Bytes $withWait)))
Check ((Says $waitBom "starts with a byte-order mark") -and @($waitBom.problems).Count -eq 1 -and $null -eq $waitBom.fields) "a seven-line record that starts with a byte-order mark is refused for it, as a six-line one is: one problem, and no field"
# TRAILING BLANK LINES ARE IGNORED, for six lines and for seven alike: the reader drops every empty
# line at the end before it counts the lines. Pinned here for both, so the two cannot drift apart.
$sixBlanks = Parse ([System.Text.Encoding]::ASCII.GetBytes(($good -join "`r`n") + "`r`n`r`n`r`n`r`n"))
Check (@($sixBlanks.problems).Count -eq 0 -and $sixBlanks.fields["blocked"] -ceq "no" -and -not $sixBlanks.fields.Contains("waiting on")) "a six-line record followed by several blank lines is read whole: the blank lines are not lines of it"
$sevenBlanks = Parse ([System.Text.Encoding]::ASCII.GetBytes(($withWait -join "`r`n") + "`r`n`r`n`r`n`r`n"))
Check (@($sevenBlanks.problems).Count -eq 0 -and $sevenBlanks.fields["waiting on"] -ceq $waits.fields["waiting on"]) "a seven-line record followed by several blank lines is read whole too, its waiting-on line and all"
$sevenBlanksLf = Parse ([System.Text.Encoding]::ASCII.GetBytes(($withWait -join "`n") + "`n`n`n"))
Check (@($sevenBlanksLf.problems).Count -eq 0 -and $sevenBlanksLf.fields["waiting on"] -ceq $waits.fields["waiting on"]) "CONTROL: and so with Unix line endings"
$blankInside = Parse (Bytes ($good + @("", "waiting on: the founder")))
Check ((Says $blankInside "has 8 lines") -and $null -eq $blankInside.fields) "CONTROL: a blank line BEFORE the waiting-on line is a line of the record, and makes eight"
foreach ($other in @("note: one line too many", "waiting: the founder", "Waiting on: the founder", "waiting on:the founder", "waiting on:   ", "blocked: no")) {
    $r = Parse (Bytes ($good + @($other)))
    Check ((Says $r "line 7 is not 'waiting on: ...'") -and @($r.problems).Count -eq 1 -and $null -eq $r.fields) ("a seventh line with another key is refused, naming it: '" + $other + "'")
}
Check (@((Parse (Bytes ($good + @("waiting on: " + ("w" * 188))))).problems).Count -eq 0) "CONTROL: a waiting-on line of exactly 200 characters, a value of 188, is within the rule"
$waitLong = Parse (Bytes ($good + @("waiting on: " + ("w" * 189))))
Check ((Says $waitLong "the waiting on line is 201 characters, and the most is 200") -and @($waitLong.problems).Count -eq 1 -and $null -eq $waitLong.fields) "a waiting-on value over the limit is refused: the line is 201 characters"
Check (@((Parse (Bytes (With 3 ("doing: " + ("x" * 121))))).problems).Count -eq 1) "CONTROL: doing's own limit is still 120: the longer limit is the seventh line's alone"
foreach ($bare in @("waiting on: M, for the review of PR 238", "waiting on: the merge of pull request #12", "waiting on: issue 214", "waiting on: #276 coming back", "waiting on: a copy of C:\work\notes.md")) {
    $r = Parse (Bytes ($good + @($bare)))
    Check ((Says $r "waiting on holds a bare reference or a path") -and $null -eq $r.fields) ("a waiting-on value with a bare pull-request number, issue number or path is refused: '" + $bare.Substring(12) + "'")
}
Check (@((Parse (Bytes ($good + @("waiting on: nothing, since 2026-10-13 22:30 UTC, unblocked by M (new account)")))).problems).Count -eq 0) "CONTROL: a date, a time and a letter are plain words, as in the real records"
$waitCtl = Parse (Bytes ($good + @("waiting on: the founder" + [string][char]0x1B + "[31m, since today")))
Check ((Says $waitCtl "holds a control character") -and $null -eq $waitCtl.fields) "a control character in the waiting-on value is refused like any other"
# A CONTROL FROM THE REAL SHAPE: a copy of a real seven-line record's shape - its line endings, its
# lengths, a date and time in its last line - with neutral words, kept as a fixture. The real records
# are never read by this suite.
$realShape = Parse ([System.IO.File]::ReadAllBytes((Join-Path $here "fixtures\fleet-status\seven-line-record.txt")))
Check (@($realShape.problems).Count -eq 0 -and $realShape.fields["orc"] -ceq "K" -and $realShape.fields["waiting on"] -clike "the neighbour, since 2026-10-13 09:30 UTC, *") ("CONTROL: a real-shaped seven-line record, kept as a fixture, is read whole (" + (@($realShape.problems) -join "; ") + ")")

Write-Host ""
Write-Host "--- this reader's own rules ---" -ForegroundColor Cyan
foreach ($letter in @("orc: f", "orc: FF", "orc: 7", "orc: F ", "orc: Orc F")) {
    $r = Parse (Bytes (With 1 $letter))
    Check ((Says $r "its orc is not one capital letter") -and $null -eq $r.fields) ("'" + $letter + "' does not name an Orc by one capital letter")
}
$empty = Parse ([byte[]]@())
Check ((Says $empty "has 0 lines") -and $null -eq $empty.fields) "an empty file is no record"
$several = Parse (Bytes @("horde-orc-status 1", "orc: f", "lane: x"))
Check (@($several.problems).Count -ge 4 -and $null -eq $several.fields) "a record wrong in several ways names each of them, and passes on nothing"

Write-Host ""
Write-Host "--- a folder of Orcs ---" -ForegroundColor Cyan
[void](New-Orc "fleet" "decisions-page" $good 90)
[void](New-Orc "fleet" "accounts-email" @("horde-orc-status 1", "orc: D", "lane: accounts and email", "doing: Holding the test deploy until the parked work is committed", "finished: The email-linking design", "blocked: The test server holds work that a deploy would roll back") 3600)
[void](New-Orc "fleet" "research")
[void](New-Orc "fleet" "voice-audio" (With 0 "status") 10)
[System.IO.File]::WriteAllText((Join-Path (Join-Path $work "fleet") "notes.txt"), "not an Orc")
$fleet = Get-HordeFleetStatus -Folder (Join-Path $work "fleet") -Now $now
Check ($fleet.schemaVersion -eq 1 -and $fleet.state -ceq "read" -and @($fleet.orcs).Count -eq 4) "each direct subfolder is one Orc, and a file beside them is not"
Check ((@($fleet.orcs | ForEach-Object { $_.folder }) -join ",") -ceq "accounts-email,decisions-page,research,voice-audio") "the written ones first, by letter; then the rest, by folder"
$d = $fleet.orcs[0]; $f = $fleet.orcs[1]; $missing = $fleet.orcs[2]; $broken = $fleet.orcs[3]
Check ($f.written -eq $true -and $f.orc -ceq "F" -and $f.lane -ceq "decisions page" -and $f.doing -like "Building the read-only window*" -and $f.finished -like "The list and its commands*" -and $f.blocked -eq $false -and $f.blockedBy -ceq "" -and $f.ageSeconds -eq 90) "a good record: its letter, lane, doing, last finished, not blocked, and the file's age"
Check ($null -eq $f.PSObject.Properties["waitingOn"]) "a six-line record has no waitingOn: the field is absent, not empty"
Check ($d.written -eq $true -and $d.blocked -eq $true -and $d.blockedBy -ceq "The test server holds work that a deploy would roll back" -and $d.ageSeconds -eq 3600) "blocked is anything but no, and the sentence is what stops it"
Check ($missing.written -eq $false -and $missing.problems[0] -ceq "there is no status.txt" -and $missing.orc -ceq "" -and $missing.doing -ceq "" -and $missing.ageSeconds -eq -1) "a folder with no file: no status written, and every field empty"
Check ($broken.written -eq $false -and $broken.problems[0] -like "does not begin with the line*" -and $broken.orc -ceq "" -and $broken.lane -ceq "" -and $broken.doing -ceq "" -and $broken.finished -ceq "" -and $broken.blocked -eq $false) "a malformed file: no status written, what was wrong, and NONE of its fields though five of its lines were good"
Check ($broken.ageSeconds -eq 10) "its age is still the file's: how long ago something was written there is a fact"

[void](New-Orc "twins" "one" $good); [void](New-Orc "twins" "two" $good); [void](New-Orc "twins" "three" (With 1 "orc: G"))
$twins = Get-HordeFleetStatus -Folder (Join-Path $work "twins") -Now $now
$claimed = @($twins.orcs | Where-Object { $_.folder -ceq "one" -or $_.folder -ceq "two" })
Check (@($claimed | Where-Object { $_.written -eq $false -and $_.orc -ceq "" -and $_.doing -ceq "" -and $_.problems[0] -like "says it is Orc F, and so does another folder (one, two)*" }).Count -eq 2) "two folders that both say they are Orc F: neither is shown as F, and each says why"
Check (@($twins.orcs | Where-Object { $_.folder -ceq "three" })[0].written -eq $true) "CONTROL: the third folder, alone in its letter, is read"
# TWINS THAT BOTH WAIT: two seven-line records claiming one letter are "no status written" like any
# other twins, and the waiting-on line goes with the rest of their fields - absent, not left behind.
[void](New-Orc "twins-waiting" "one" $withWait); [void](New-Orc "twins-waiting" "two" $withWait); [void](New-Orc "twins-waiting" "three" ((With 1 "orc: G") + @("waiting on: the reviewer, since 2026-10-13")))
$twinsWaiting = Get-HordeFleetStatus -Folder (Join-Path $work "twins-waiting") -Now $now
$claimedWaiting = @($twinsWaiting.orcs | Where-Object { $_.folder -ceq "one" -or $_.folder -ceq "two" })
Check (@($claimedWaiting | Where-Object { $_.written -eq $false -and $_.orc -ceq "" -and $_.problems[0] -like "says it is Orc F, and so does another folder (one, two)*" }).Count -eq 2) "two seven-line records that both say they are Orc F: neither is shown as F"
Check (@($claimedWaiting | Where-Object { $null -ne $_.PSObject.Properties["waitingOn"] }).Count -eq 0) "and neither keeps its waitingOn: the field is absent on both, as on any record not written"
$thirdWaiting = @($twinsWaiting.orcs | Where-Object { $_.folder -ceq "three" })[0]
Check ($thirdWaiting.written -eq $true -and $thirdWaiting.waitingOn -ceq "the reviewer, since 2026-10-13") "CONTROL: the third, alone in its letter, is read with its waitingOn"
# MANY FOLDERS, ONE LETTER: each one's problem names a few of the others and counts the rest. Naming
# all of them in every one made the answer grow with the square of the folders (measured 2026-10-06 by
# the review of this reader: 1,000 folders gave a panel 11 MB of text, 3,000 gave it 100 MB, and
# 10,000 ended in an out-of-memory error) - and a folder of more than 26 records must repeat a letter.
for ($i = 1; $i -le 40; $i++) { [void](New-Orc "crowd" ("orc-" + $i.ToString("D2")) $good) }
$crowd = Get-HordeFleetStatus -Folder (Join-Path $work "crowd") -Now $now
Check (@($crowd.orcs | Where-Object { $_.written -eq $false -and $_.orc -ceq "" -and $_.problems[0] -ceq "says it is Orc F, and so does another folder (orc-01, orc-02, orc-03, orc-04, orc-05 and 35 more), so which is that Orc cannot be told" }).Count -eq 40) "forty folders that all say they are Orc F: none is shown as F, and each names five of them and counts the other 35"

[void](New-Orc "big" "huge" -Raw ([System.Text.Encoding]::ASCII.GetBytes(("x" * 9000))))
$big = (Get-HordeFleetStatus -Folder (Join-Path $work "big") -Now $now).orcs[0]
Check ($big.written -eq $false -and $big.problems[0] -ceq "is 9000 bytes, far more than a record's seven lines, and was not read") "a file far too large to be a record is not read"
# THE CAP STILL HOLDS A RECORD AT EVERY BOUND: a seventh line of 200 characters, doing and finished
# at 120, with a lane and a blocked sentence of 1,000 characters each, are far inside 8,192 bytes.
$widest = @("horde-orc-status 1", "orc: W", ("lane: " + ("l" * 1000)), ("doing: " + ("d" * 120)), ("finished: " + ("f" * 120)), ("blocked: " + ("b" * 1000)), ("waiting on: " + ("w" * 188)))
[void](New-Orc "wide" "widest" $widest)
$wideRead = (Get-HordeFleetStatus -Folder (Join-Path $work "wide") -Now $now).orcs[0]
Check ($wideRead.written -eq $true -and $wideRead.waitingOn.Length -eq 188 -and (Bytes $widest "`r`n").Length -lt $script:HordeFleetStatusMostBytes) ("a seven-line record with every bounded field at its most, and long free lines, is under the size cap and read (" + (Bytes $widest "`r`n").Length + " of " + $script:HordeFleetStatusMostBytes + " bytes)")
$gone = Get-HordeFleetStatus -Folder (Join-Path $work "no-such-fleet") -Now $now
Check ($gone.state -ceq "unreadable" -and @($gone.orcs).Count -eq 0 -and $gone.reason -like "the folder of status records could not be listed*") "a folder that cannot be listed is unreadable, not an empty fleet"
New-Item -ItemType Directory -Path (Join-Path $work "nobody") | Out-Null
$nobody = Get-HordeFleetStatus -Folder (Join-Path $work "nobody") -Now $now
Check ($nobody.state -ceq "read" -and @($nobody.orcs).Count -eq 0) "CONTROL: a folder that is there and empty is a fleet of none"

Write-Host ""
Write-Host "--- the panel shows the waiting-on line ---" -ForegroundColor Cyan
# The record reaches the fleet line (fleet/line/line.js) as the JSON of this reader's answer. The line
# is a page script, so it is drawn here under Node (fleet/line/test/draw-rows.mjs) with a stand-in for
# the document, and its rows are read back as the text a real window reports. Where there is no Node
# the suite says so and passes as PARTIAL (exit 3): everything else ran.
[void](New-Orc "panel" "waits" @("horde-orc-status 1", "orc: K", "lane: garden planning", "doing: Sorting the seed packets", "finished: The tool shed", "blocked: no", "waiting on: the neighbour, since 2026-10-13 09:30 UTC, for the long ladder") 30)
[void](New-Orc "panel" "plain" @("horde-orc-status 1", "orc: L", "lane: kitchen", "doing: Baking", "finished: The shopping.", "blocked: no") 30)
[void](New-Orc "panel" "both" @("horde-orc-status 1", "orc: M", "lane: roof", "doing: Nothing", "finished: The gutters", "blocked: The rain has not stopped", "waiting on: the roofer, since 2026-10-12.") 30)
$panelStatus = Get-HordeFleetStatus -Folder (Join-Path $work "panel") -Now $now
$k = @($panelStatus.orcs | Where-Object { $_.folder -ceq "waits" })[0]
Check ($k.written -eq $true -and $k.waitingOn -ceq "the neighbour, since 2026-10-13 09:30 UTC, for the long ladder") "the record hands the panel its waitingOn"
$node = Get-Command -Name "node" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) {
    Write-Host "  [SKIP] node is not installed here, so the fleet line is not drawn" -ForegroundColor Yellow
    $partial = $true
} else {
    $statusFile = Join-Path $work "panel-status.json"
    [System.IO.File]::WriteAllText($statusFile, (ConvertTo-Json -InputObject $panelStatus -Depth 6 -Compress), (New-Object System.Text.UTF8Encoding($false)))
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $node.Source
    $psi.Arguments = '"' + (Join-Path $root "fleet\line\test\draw-rows.mjs") + '" "' + (Join-Path $root "fleet\line\line.js") + '" "' + $statusFile + '"'
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $drawnRows = @()
    try {
        $errTask = $p.StandardError.ReadToEndAsync()
        $out = $p.StandardOutput.ReadToEnd()
        if (-not $p.WaitForExit(60000)) { $p.Kill() }
        Check ($p.ExitCode -eq 0) ("the fleet line was drawn under Node (exit " + $p.ExitCode + "; " + $errTask.Result.Trim() + ")")
        if ($p.ExitCode -eq 0) { $drawnRows = @(($out | ConvertFrom-Json).rows) }
    } finally { $p.Dispose() }
    Check ($drawnRows.Count -eq 3) ("three rows, one per Orc (" + ($drawnRows -join " | ") + ")")
    Check (@($drawnRows | Where-Object { $_ -ceq "Orc K (garden planning): Sorting the seed packets. Last finished: The tool shed. Waiting on: the neighbour, since 2026-10-13 09:30 UTC, for the long ladder. (written just now)" }).Count -eq 1) "the panel shows the waiting-on line, after what the Orc last finished"
    Check (@($drawnRows | Where-Object { $_ -ceq "Orc M (roof): Nothing. Last finished: The gutters. Waiting on: the roofer, since 2026-10-12. Blocked: The rain has not stopped. (written just now)" }).Count -eq 1) "beside a blocked sentence too, and a line that ends its own sentence is not given a second full stop"
    Check (@($drawnRows | Where-Object { $_ -ceq "Orc L (kitchen): Baking. Last finished: The shopping. (written just now)" }).Count -eq 1) "CONTROL: a six-line record's row says nothing of waiting"
}

Write-Host ""
Write-Host "--- blocked: no, in any letter case, is not blocked ---" -ForegroundColor Cyan
# An Orc that wrote "No" was shown at the highest state with the reason "No" (measured 2026-10-06 by
# the review of this reader). The word is read whatever its letters' case; anything else that is not
# empty is the sentence saying what stops it, a full stop after the word included.
$letters = @("A", "B", "C", "D", "E", "F")
$words = @("no", "No", "NO", "nO", "no.", "Not until the test machine is switched on again")
for ($i = 0; $i -lt $words.Count; $i++) { [void](New-Orc "words" ("w" + $i) (@("horde-orc-status 1", ("orc: " + $letters[$i]), "lane: a lane", "doing: Something", "finished: Something else", ("blocked: " + $words[$i])))) }
$byWord = @{}
foreach ($o in @((Get-HordeFleetStatus -Folder (Join-Path $work "words") -Settings (Read-HordeModuleSettingsText -Declaration (Get-HordeFleetSettingsDeclaration) -Text $null) -Now $now).orcs)) { $byWord[$o.folder] = $o }
foreach ($i in 0..3) { Check ($byWord["w" + $i].written -eq $true -and $byWord["w" + $i].blocked -eq $false -and $byWord["w" + $i].blockedBy -ceq "") ("'blocked: " + $words[$i] + "' is not blocked, and gives no reason") }
Check ($byWord["w4"].blocked -eq $true -and $byWord["w4"].blockedBy -ceq "no.") "'blocked: no.' is not the word alone: it is blocked, and that is its reason"
Check ($byWord["w5"].blocked -eq $true -and $byWord["w5"].blockedBy -ceq "Not until the test machine is switched on again") "CONTROL: a sentence that begins with the word is the reason, whole"

Write-Host ""
Write-Host "--- where the files are, and how many folders are read, are the fleet module's settings ---" -ForegroundColor Cyan
function New-Home { param([string]$Name, $Settings = $null)
    $h = Join-Path $work $Name; New-Item -ItemType Directory -Path (Join-Path $h "settings") -Force | Out-Null
    if ($null -ne $Settings) { [System.IO.File]::WriteAllText((Join-Path $h "settings\fleet.json"), ('{"schemaVersion":1,"settings":' + $Settings + '}')) }
    return $h }
$fleetJson = (Join-Path $work "fleet").Replace("\", "\\")
$defaults = Read-HordeModuleSettingsText -Declaration (Get-HordeFleetSettingsDeclaration) -Text $null
Check ((@($defaults.values.PSObject.Properties | ForEach-Object { $_.Name }) -join ",") -ceq "statusFolder,statusFoldersRead" -and $defaults.values.statusFolder -ceq "" -and $defaults.values.statusFoldersRead -eq 64) "the module declares two settings: the folder, which is none unless a person names one, and the most folders read, 64"
$okHome = New-Home "home-ok" ('{"statusFolder":"' + $fleetJson + '"}')
Check ((Get-HordeFleetSettings -HordeHome $okHome).path -ceq (Join-Path $okHome "settings\fleet.json")) "they are read from settings\fleet.json under Horde's home"
$configured = Get-HordeFleetStatusSource -HordeHome $okHome
Check ($configured.state -ceq "configured" -and $configured.folder -ceq (Join-Path $work "fleet")) "a setting naming a folder that exists: that folder"
$viaHome = Get-HordeFleetStatus -HordeHome $okHome -Now $now
Check ($viaHome.state -ceq "read" -and @($viaHome.orcs).Count -eq 4 -and $viaHome.notRead -eq 0 -and @($viaHome.findings).Count -eq 0) "and the fleet is read from it: four folders, none left unread, nothing wrong in the file"
$none = Get-HordeFleetStatus -HordeHome (New-Home "home-none") -Now $now
Check ($none.state -ceq "not-configured" -and $none.reason -ceq "no folder of status records is configured on this machine" -and @($none.orcs).Count -eq 0 -and $none.notRead -eq 0) "no setting is not-configured, which is not an error"
$oldHome = New-Home "home-old"
New-Item -ItemType Directory -Path (Join-Path $oldHome "fleet") | Out-Null
[System.IO.File]::WriteAllText((Join-Path $oldHome "fleet\status-source.json"), ('{"schemaVersion":1,"folder":"' + $fleetJson + '"}'))
Check ((Get-HordeFleetStatus -HordeHome $oldHome -Now $now).state -ceq "not-configured") "the file this setting replaces, fleet\status-source.json, is no longer read: one place says where the records are"
$missing = Get-HordeFleetStatus -HordeHome (New-Home "home-missing" '{"statusFolder":"C:\\no\\such\\folder\\of-orcs"}') -Now $now
Check ($missing.state -ceq "unreadable" -and $missing.reason -ceq "the setting of where status records are (statusFolder) names a folder that does not exist: C:\no\such\folder\of-orcs" -and @($missing.orcs).Count -eq 0) "a setting naming a folder that does not exist is unreadable, and no Orc is shown"
foreach ($bad in @(
    @{ name = "home-relative"; settings = '{"statusFolder":"orcs"}' }
    @{ name = "home-number"; settings = '{"statusFolder":7}' }
    @{ name = "home-text"; settings = 'not json' }
)) {
    $r = Get-HordeFleetStatus -HordeHome (New-Home $bad.name $bad.settings) -Now $now
    Check ($r.state -ceq "refused" -and @($r.findings).Count -ge 1 -and @($r.findings | Where-Object { $_ -notlike "the settings file '*fleet.json' of fleet is refused: *" }).Count -eq 0 -and $r.reason -clike "no status is read, because the fleet's settings file is refused: the settings file '*" -and @($r.orcs).Count -eq 0) ("a settings file holding " + $bad.settings + " refuses the reading, its findings each naming the file, and no default is used (" + (@($r.findings) -join " / ") + ")")
}
$r = Get-HordeFleetStatus -Folder (Join-Path $work "fleet") -Settings (Get-HordeFleetSettings -HordeHome (New-Home "home-refused-folder" '{"statusFoldersRead":0}')) -Now $now
Check ($r.state -ceq "refused" -and @($r.orcs).Count -eq 0 -and $r.findings[0] -like "*statusFoldersRead*") "a refused file refuses a reading of a folder handed in too: the most read is the file's, and is not guessed"
$src = Get-HordeFleetStatusSource -Settings (Get-HordeFleetSettings -HordeHome (New-Home "home-refused-source" '{"statusFolder":7}'))
Check ($src.state -ceq "refused" -and $src.folder -ceq "" -and $src.reason -like "*statusFolder*") "and where the records are is refused, not not-configured, when the file is"
$handed = Get-HordeFleetStatus -Folder (Join-Path $work "fleet") -Settings ([pscustomobject]@{ values = $defaults.values }) -Now $now
Check ($handed.state -ceq "refused" -and @($handed.orcs).Count -eq 0) "settings handed in with no state are no answer of the module, and are refused, never read"

# A FOLDER WINDOWS CANNOT EVEN BE ASKED ABOUT is unreadable like the rest, never a throw: the caller is
# a window's tick, and what it is promised is an answer. Measured 2026-10-06 by the review of this
# reader: a folder on a machine that does not answer, and a folder whose name holds characters no path
# may, each came out as an exception ("The network path was not found", "Illegal characters in
# path"). The catch here is the test's own, so that a throw is a failed check.
$r = $null
try { $r = Get-HordeFleetStatus -HordeHome (New-Home "home-nomachine" '{"statusFolder":"\\\\horde-no-such-machine\\orcs"}') -Now $now } catch { $r = [pscustomobject]@{ state = "threw"; reason = "$($_.Exception.Message)"; orcs = @() } }
Check ($r.state -ceq "unreadable" -and $r.reason -like "the setting of where status records are (statusFolder) names a folder that could not be looked for: *" -and @($r.orcs).Count -eq 0) ("a setting naming a folder on a machine that does not answer is unreadable, not a throw (" + $r.state + ": " + $r.reason + ")")
# The name no path may hold does not get as far as this reader through the settings (the folder kind
# refuses it, measured 2026-10-07: a finding, and no folder), so it is handed over as a caller would.
$r = Get-HordeFleetStatus -HordeHome (New-Home "home-nopath" '{"statusFolder":"C:\\orcs<of>|a?fleet"}') -Now $now
Check ($r.state -ceq "refused" -and @($r.findings).Count -eq 1 -and $r.findings[0] -like "*statusFolder*") "a setting holding characters no path may is refused as a setting, by name, and no folder is read"
$r = $null
try { $r = Get-HordeFleetStatus -Folder 'C:\orcs<of>|a?fleet' -Settings $defaults -Now $now } catch { $r = [pscustomobject]@{ state = "threw"; reason = "$($_.Exception.Message)"; orcs = @() } }
Check ($r.state -ceq "unreadable" -and $r.reason -like "the folder of status records could not be listed: *" -and @($r.orcs).Count -eq 0) ("and such a folder handed over by a caller is unreadable, not a throw (" + $r.state + ": " + $r.reason + ")")

Write-Host ""
Write-Host "--- no more folders are read than the setting says, and the rest are counted ---" -ForegroundColor Cyan
for ($i = 1; $i -le 70; $i++) { [void](New-Orc "many" ("orc-" + $i.ToString("D2"))) }
[void](New-Orc "many" "ORC-00" $good)
$many = Get-HordeFleetStatus -Folder (Join-Path $work "many") -Settings $defaults -Now $now
Check ($many.state -ceq "read" -and @($many.orcs).Count -eq 64 -and $many.notRead -eq 7) ("of 71 folders 64 are read and 7 are counted as not read (" + @($many.orcs).Count + ", " + $many.notRead + ")")
$readNames = @($many.orcs | ForEach-Object { $_.folder })
Check (($readNames -ccontains "ORC-00") -and ($readNames -ccontains "orc-63") -and -not ($readNames -ccontains "orc-64") -and -not ($readNames -ccontains "orc-70")) "which are read is the first so many by name, letter case set aside: ORC-00 and orc-01 to orc-63"
$three = Read-HordeModuleSettingsText -Declaration (Get-HordeFleetSettingsDeclaration) -Text '{"schemaVersion":1,"settings":{"statusFoldersRead":3}}'
$few = Get-HordeFleetStatus -Folder (Join-Path $work "many") -Settings $three -Now $now
Check (@($few.orcs).Count -eq 3 -and $few.notRead -eq 68 -and @($few.orcs | Where-Object { $_.written }).Count -eq 1) "with the setting at 3, three are read, the one good record among them, and 68 counted"
Check (@((Get-HordeFleetStatus -Folder (Join-Path $work "fleet") -Settings $three -Now $now).orcs).Count -eq 3 -and (Get-HordeFleetStatus -Folder (Join-Path $work "fleet") -Settings $defaults -Now $now).notRead -eq 0) "CONTROL: a folder of four is read whole at 64, and counts none unread"
$wrongKind = Get-HordeFleetStatus -HordeHome (New-Home "home-cap" ('{"statusFolder":"' + (Join-Path $work "many").Replace("\", "\\") + '","statusFoldersRead":"3"}')) -Now $now
Check ($wrongKind.state -ceq "refused" -and @($wrongKind.orcs).Count -eq 0 -and @($wrongKind.findings).Count -eq 1 -and $wrongKind.findings[0] -like "*statusFoldersRead*") ("a most that is written as text is refused by name, and 64 is not used in its place (" + (@($wrongKind.findings) -join " / ") + ")")

Write-Host ""
Write-Host "--- a retired lane has no row (C's ruling, 2026-10-14) ---" -ForegroundColor Cyan
# A folder with status.retired.txt and no status.txt is a lane that ended: no row, not "no status
# written", not counted. Both files: a lane that came back, read from status.txt. Neither: no status
# written, as before. The retired file holds a good record of its own, so a reader that read it would
# show it.
function Set-Retired { param([string]$Dir, [string[]]$Lines) [System.IO.File]::WriteAllBytes((Join-Path $Dir "status.retired.txt"), (Bytes $Lines)) }
$liveA = @("horde-orc-status 1", "orc: A", "lane: live lane", "doing: Working", "finished: Something", "blocked: no")
$oldZ = @("horde-orc-status 1", "orc: Z", "lane: old lane", "doing: The retired words", "finished: Everything", "blocked: The founder said stop")
[void](New-Orc "retired" "live" $liveA)
$oldDir = New-Orc "retired" "old-lane" $oldZ
$before = Get-HordeFleetStatus -Folder (Join-Path $work "retired") -Settings $defaults -Now $now
Check (@($before.orcs).Count -eq 2 -and @($before.orcs | Where-Object { $_.orc -ceq "Z" }).Count -eq 1) "CONTROL: before it retires, the old lane has its row"
[System.IO.File]::Move((Join-Path $oldDir "status.txt"), (Join-Path $oldDir "status.retired.txt"))
$retired = Get-HordeFleetStatus -Folder (Join-Path $work "retired") -Settings $defaults -Now $now
Check ($retired.state -ceq "read" -and @($retired.orcs).Count -eq 1 -and @($retired.orcs | Where-Object { $_.folder -ceq "old-lane" }).Count -eq 0 -and $retired.notRead -eq 0) ("a retired lane (status.retired.txt only) has no row and is not counted (" + (@($retired.orcs | ForEach-Object { $_.folder }) -join ",") + "; not read " + $retired.notRead + ")")
$a = @($retired.orcs)[0]
Check ($a.folder -ceq "live" -and $a.written -eq $true -and $a.orc -ceq "A" -and $a.doing -ceq "Working" -and $a.ageSeconds -eq 90) "CONTROL: the live lane beside the retired one is read as it was"
$backDir = New-Orc "retired" "came-back" @("horde-orc-status 1", "orc: Y", "lane: came back", "doing: Back at work", "finished: The return", "blocked: no")
Set-Retired $backDir (@("horde-orc-status 1", "orc: Y", "lane: came back", "doing: The retired words", "finished: Everything", "blocked: Stopped"))
$neitherDir = New-Orc "retired" "nothing-here"
$all = Get-HordeFleetStatus -Folder (Join-Path $work "retired") -Settings $defaults -Now $now
$y = @($all.orcs | Where-Object { $_.folder -ceq "came-back" })
Check ($y.Count -eq 1 -and $y[0].written -eq $true -and $y[0].orc -ceq "Y" -and $y[0].doing -ceq "Back at work" -and $y[0].blocked -eq $false) ("a lane with both files is read from status.txt (" + $(if ($y.Count -eq 1) { $y[0].doing } else { "no row" }) + ")")
$n = @($all.orcs | Where-Object { $_.folder -ceq "nothing-here" })
Check ($n.Count -eq 1 -and $n[0].written -eq $false -and $n[0].problems[0] -ceq "there is no status.txt") "a lane with neither file is still no status written"
Check (@($all.orcs).Count -eq 3 -and (@($all.orcs | ForEach-Object { $_.folder }) -join ",") -ceq "live,came-back,nothing-here") ("three rows, the retired lane none of them (" + (@($all.orcs | ForEach-Object { $_.folder }) -join ",") + ")")
# Retired folders are passed over before the most read is counted, or old lanes would push live ones out.
foreach ($old in @("a-old", "b-old", "c-old")) { Set-Retired (New-Orc "retired-first" $old) $oldZ }
[void](New-Orc "retired-first" "d-live" (With 1 "orc: D")); [void](New-Orc "retired-first" "e-live" (With 1 "orc: E"))
$two = Read-HordeModuleSettingsText -Declaration (Get-HordeFleetSettingsDeclaration) -Text '{"schemaVersion":1,"settings":{"statusFoldersRead":2}}'
$first = Get-HordeFleetStatus -Folder (Join-Path $work "retired-first") -Settings $two -Now $now
Check ((@($first.orcs | ForEach-Object { $_.orc }) -join ",") -ceq "D,E" -and $first.notRead -eq 0) ("retired folders do not count against the most read: two live lanes behind three retired ones are both read, none counted unread (" + (@($first.orcs | ForEach-Object { $_.folder }) -join ",") + "; not read " + $first.notRead + ")")

Write-Host ""
Write-Host "--- the reader writes nothing ---" -ForegroundColor Cyan
$before = @(Get-ChildItem -LiteralPath $work -Recurse -Force | ForEach-Object { $_.FullName + "|" + $(if ($_.PSIsContainer) { "dir" } else { "" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks }) }) -join ";"
[void](Get-HordeFleetStatus -Folder (Join-Path $work "fleet") -Now $now)
[void](Get-HordeFleetStatus -HordeHome (Join-Path $work "home-none") -Now $now)
$after = @(Get-ChildItem -LiteralPath $work -Recurse -Force | ForEach-Object { $_.FullName + "|" + $(if ($_.PSIsContainer) { "dir" } else { "" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks }) }) -join ";"
Check ($before -ceq $after) "after reading, every file and folder is exactly as it was: nothing made, nothing touched"
$src = [System.IO.File]::ReadAllText((Join-Path $root "fleet\StatusPanel.ps1"))
$writes = 'WriteAll|Set-Content|Out-File|New-Item|Add-Content|Remove-Item|\.Delete\(|FileMode\]::(Create|Append|Truncate|OpenOrCreate)|FileAccess\]::(Write|ReadWrite)'
Check (-not ($src -match $writes)) "and its source holds no call that writes, makes or removes a file"
Check ([System.IO.File]::ReadAllText((Join-Path $root "tools\Mutate.ps1")) -match $writes) "CONTROL: the same search finds such a call in a shipped file that does write (tools/Mutate.ps1), so finding none here means something"

} finally {
    if ((Split-Path -Leaf $work) -match '\Ahorde-fleet-status-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force }
}

if ($partial) { Complete-HordeSuite -Success "an Orc's status record is passed on whole or not at all; the fleet line was not drawn (no node)" -PassCode 3 }
Complete-HordeSuite -Success "an Orc's status record is passed on whole or not at all, and the reader writes nothing"
