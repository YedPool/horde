# IS AN ORC'S STATUS RECORD READ WHOLE, OR NOT AT ALL?
#
# fleet/StatusPanel.ps1 reads the six-line record each Orc keeps and hands it to a panel. A record
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
$seven = Parse (Bytes ($good + @("note: one line too many")))
Check ((Says $seven "has 7 lines, and a record is 6") -and @($seven.problems).Count -eq 1 -and $null -eq $seven.fields) "3. seven lines, the first six of them good"
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
Check ($d.written -eq $true -and $d.blocked -eq $true -and $d.blockedBy -ceq "The test server holds work that a deploy would roll back" -and $d.ageSeconds -eq 3600) "blocked is anything but no, and the sentence is what stops it"
Check ($missing.written -eq $false -and $missing.problems[0] -ceq "there is no status.txt" -and $missing.orc -ceq "" -and $missing.doing -ceq "" -and $missing.ageSeconds -eq -1) "a folder with no file: no status written, and every field empty"
Check ($broken.written -eq $false -and $broken.problems[0] -like "does not begin with the line*" -and $broken.orc -ceq "" -and $broken.lane -ceq "" -and $broken.doing -ceq "" -and $broken.finished -ceq "" -and $broken.blocked -eq $false) "a malformed file: no status written, what was wrong, and NONE of its fields though five of its lines were good"
Check ($broken.ageSeconds -eq 10) "its age is still the file's: how long ago something was written there is a fact"

[void](New-Orc "twins" "one" $good); [void](New-Orc "twins" "two" $good); [void](New-Orc "twins" "three" (With 1 "orc: G"))
$twins = Get-HordeFleetStatus -Folder (Join-Path $work "twins") -Now $now
$claimed = @($twins.orcs | Where-Object { $_.folder -ceq "one" -or $_.folder -ceq "two" })
Check (@($claimed | Where-Object { $_.written -eq $false -and $_.orc -ceq "" -and $_.doing -ceq "" -and $_.problems[0] -like "says it is Orc F, and so does another folder (one, two)*" }).Count -eq 2) "two folders that both say they are Orc F: neither is shown as F, and each says why"
Check (@($twins.orcs | Where-Object { $_.folder -ceq "three" })[0].written -eq $true) "CONTROL: the third folder, alone in its letter, is read"

[void](New-Orc "big" "huge" -Raw ([System.Text.Encoding]::ASCII.GetBytes(("x" * 9000))))
$big = (Get-HordeFleetStatus -Folder (Join-Path $work "big") -Now $now).orcs[0]
Check ($big.written -eq $false -and $big.problems[0] -ceq "is 9000 bytes, far more than six lines, and was not read") "a file far too large to be a record is not read"
$gone = Get-HordeFleetStatus -Folder (Join-Path $work "no-such-fleet") -Now $now
Check ($gone.state -ceq "unreadable" -and @($gone.orcs).Count -eq 0 -and $gone.reason -like "the folder of status records could not be listed*") "a folder that cannot be listed is unreadable, not an empty fleet"
New-Item -ItemType Directory -Path (Join-Path $work "nobody") | Out-Null
$nobody = Get-HordeFleetStatus -Folder (Join-Path $work "nobody") -Now $now
Check ($nobody.state -ceq "read" -and @($nobody.orcs).Count -eq 0) "CONTROL: a folder that is there and empty is a fleet of none"

Write-Host ""
Write-Host "--- where the files are is configuration ---" -ForegroundColor Cyan
function New-Home { param([string]$Name, $Config = $null)
    $h = Join-Path $work $Name; New-Item -ItemType Directory -Path (Join-Path $h "fleet") -Force | Out-Null
    if ($null -ne $Config) { [System.IO.File]::WriteAllText((Join-Path $h "fleet\status-source.json"), $Config) }
    return $h }
$fleetJson = (Join-Path $work "fleet").Replace("\", "\\")
$configured = Get-HordeFleetStatusSource -HordeHome (New-Home "home-ok" ('{"schemaVersion":1,"folder":"' + $fleetJson + '"}'))
Check ($configured.state -ceq "configured" -and $configured.folder -ceq (Join-Path $work "fleet")) "a configuration naming a folder that exists: that folder"
$viaHome = Get-HordeFleetStatus -HordeHome (Join-Path $work "home-ok") -Now $now
Check ($viaHome.state -ceq "read" -and @($viaHome.orcs).Count -eq 4) "and the fleet is read from it"
$none = Get-HordeFleetStatus -HordeHome (New-Home "home-none") -Now $now
Check ($none.state -ceq "not-configured" -and $none.reason -ceq "no folder of status records is configured on this machine" -and @($none.orcs).Count -eq 0) "no configuration is not-configured, which is not an error"
foreach ($bad in @(
    @{ name = "home-text"; config = "not json"; says = "is not a JSON object" }
    @{ name = "home-version"; config = ('{"schemaVersion":2,"folder":"' + $fleetJson + '"}'); says = "is not schemaVersion 1" }
    @{ name = "home-relative"; config = '{"schemaVersion":1,"folder":"orcs"}'; says = "does not give an absolute folder" }
    @{ name = "home-missing"; config = '{"schemaVersion":1,"folder":"C:\\no\\such\\folder\\of-orcs"}'; says = "names a folder that does not exist" }
    @{ name = "home-nofolder"; config = '{"schemaVersion":1}'; says = "does not give an absolute folder" }
)) {
    $r = Get-HordeFleetStatus -HordeHome (New-Home $bad.name $bad.config) -Now $now
    Check ($r.state -ceq "unreadable" -and $r.reason -like ("*" + $bad.says + "*") -and @($r.orcs).Count -eq 0) ("a configuration that " + $bad.says + " is unreadable, and no Orc is shown")
}
# A FOLDER WINDOWS CANNOT EVEN BE ASKED ABOUT is unreadable like the rest, never a throw: the caller is
# a window's tick, and what it is promised is an answer. Measured 2026-10-06 by the review of this
# reader: a folder on a machine that does not answer, and a folder whose name holds characters no path
# may, each came out of Get-HordeFleetStatusSource as an exception ("The network path was not found",
# "Illegal characters in path"). The catch here is the test's own, so that a throw is a failed check.
foreach ($unaskable in @(
    @{ name = "home-nomachine"; config = '{"schemaVersion":1,"folder":"\\\\horde-no-such-machine\\orcs"}'; says = "could not be looked for" }
    @{ name = "home-nopath"; config = '{"schemaVersion":1,"folder":"C:\\orcs<of>|a?fleet"}'; says = "could not be looked for" }
)) {
    $r = $null
    try { $r = Get-HordeFleetStatus -HordeHome (New-Home $unaskable.name $unaskable.config) -Now $now } catch { $r = [pscustomobject]@{ state = "threw"; reason = "$($_.Exception.Message)"; orcs = @() } }
    Check ($r.state -ceq "unreadable" -and $r.reason -like ("*" + $unaskable.says + "*") -and @($r.orcs).Count -eq 0) ("a configuration naming a folder that " + $unaskable.says + " is unreadable, not a throw (" + $r.state + ": " + $r.reason + ")")
}
Check ((Get-HordeFleetStatusSourcePath -HordeHome "C:\h") -ceq "C:\h\fleet\status-source.json") "the configuration is fleet\status-source.json under Horde's home"

Write-Host ""
Write-Host "--- the reader writes nothing ---" -ForegroundColor Cyan
$before = @(Get-ChildItem -LiteralPath $work -Recurse -Force | ForEach-Object { $_.FullName + "|" + $(if ($_.PSIsContainer) { "dir" } else { "" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks }) }) -join ";"
[void](Get-HordeFleetStatus -Folder (Join-Path $work "fleet") -Now $now)
[void](Get-HordeFleetStatus -HordeHome (Join-Path $work "home-none") -Now $now)
$after = @(Get-ChildItem -LiteralPath $work -Recurse -Force | ForEach-Object { $_.FullName + "|" + $(if ($_.PSIsContainer) { "dir" } else { "" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks }) }) -join ";"
Check ($before -ceq $after) "after reading, every file and folder is exactly as it was: nothing made, nothing touched"
$src = [System.IO.File]::ReadAllText((Join-Path $root "fleet\StatusPanel.ps1"))
Check (-not ($src -match 'WriteAll|Set-Content|Out-File|New-Item|Add-Content|Remove-Item|\.Delete\(|FileMode\]::(Create|Append|Truncate|OpenOrCreate)|FileAccess\]::(Write|ReadWrite)')) "and its source holds no call that writes, makes or removes a file"

} finally {
    if ((Split-Path -Leaf $work) -match '\Ahorde-fleet-status-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force }
}

Complete-HordeSuite -Success "an Orc's status record is passed on whole or not at all, and the reader writes nothing"
