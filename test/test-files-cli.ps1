# DOES `horde files` DO, FROM A COMMAND LINE, WHAT A SESSION SHARING A FILE NEEDS?
#
# The end-to-end scenario of the command (CONTRIBUTING 2): the shipped horde.ps1, run as its own
# process the way a session would run it, against a home this suite made. A session writes a report,
# shares it, changes it and shares it again; shares a picture; is refused for each thing that must not
# be shared, with a reason on the line and a non-zero exit; and reads the list back. What the store
# then holds is read from the files themselves, not from what the command printed. Then, in a second
# home: one file named three ways is one file; text that is not text, a device and a stream inside a
# file are refused; and the key that file ids are made with is on no line and in no record, and a
# share whose key is gone or cut short is refused instead of making another.
#
# The rules themselves are attacked in test/test-files-store.ps1, and racing processes in
# test/test-files-race.ps1; this suite is the command: its arguments, its lines and its exit codes.
#
# THE SESSION. A share records the session that made it, which core reads from a variable the session's
# harness exports. This suite must give its child processes a session, and must not name a harness
# (CONTRIBUTING 14), so it asks core which variable that is: core's own reason, when the variable is
# not set, begins with its name.
#
# Every home here is a fresh folder under %TEMP% that this suite made and removes (CONTRIBUTING 9);
# HORDE_HOME is set for each child, so the real home is never read or written.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "core\Identity.ps1")

$script:work = Join-Path $env:TEMP ("horde-files-cli-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$hordeHome = Join-Path $script:work "home"
$store = Join-Path $hordeHome "store\files"
$docs = Join-Path $script:work "docs"
New-Item -ItemType Directory -Path $docs | Out-Null

$sessionVariable = ("" + (Get-HordeSelfSessionId -Environment @{}).reason).Split(" ")[0]

function Invoke-Files {
    # horde files <arguments>, as -Session (a session id, or "" for outside any session): { code; out }.
    param([string[]]$Arguments, [string]$Session = "cli-session-1", [string]$TestHome = $hordeHome)
    $childEnv = @{ HORDE_HOME = $TestHome }
    $childEnv[$sessionVariable] = $Session
    return (Invoke-HordeCliProcess -Root $root -HordeArgs (@("files") + $Arguments) -Env $childEnv)
}
function Get-StoreCount { param([string]$Filter) if (-not (Test-Path -LiteralPath $store)) { return 0 }; return @(Get-ChildItem -LiteralPath $store -Filter $Filter -Force).Count }
function Test-RefusedByCli {
    # Did the command exit 1, say why with words like -Like, and leave the store as it was?
    param([string[]]$Arguments, [string]$Like, [int]$Code = 1)
    $before = (Get-StoreCount "*")
    $r = Invoke-Files -Arguments $Arguments
    $ok = ($r.code -eq $Code -and $r.out -like ("*" + $Like + "*") -and (Get-StoreCount "*") -eq $before)
    if (-not $ok) { Write-Host ("         got: exit " + $r.code + ": " + $r.out.Trim()) -ForegroundColor Red }
    return $ok
}

# NOT ONE try AROUND THE CHECKS (test/test-files-store.ps1 has the measurement): after an error no check
# expected, the suite's trap goes on with the next statement of the script, and one try around
# everything is one statement. The sections are plain statements, and so is the removal at the end.

Write-Host ""
Write-Host "--- before anything is shared ---" -ForegroundColor Cyan
Check ($sessionVariable -cmatch '\A[A-Z][A-Z0-9_]{3,}\z') "CONTROL: core names the variable that says which session is asking"
$r = Invoke-HordeCliProcess -Root $root -HordeArgs @("help") -Env @{ HORDE_HOME = $hordeHome }
Check ($r.code -eq 0 -and $r.out -like "*horde files share <path> -Title <one line> ``[-Editable``] ``[-Force``] | files list*") "horde help lists the command with its usage"
$r = Invoke-Files -Arguments @("list")
Check ($r.code -eq 0 -and $r.out.Trim() -ceq "no files have been shared") ("with nothing shared, the list says so and exits 0 (" + $r.code + ")")
Check (-not (Test-Path -LiteralPath $hordeHome)) "and listing made no home"

Write-Host ""
Write-Host "--- a session shares a report, changes it, and shares it again ---" -ForegroundColor Cyan
$report = Join-Path $docs "report.md"
[System.IO.File]::WriteAllText($report, "# Weekly report`nAll is well.`n")
$r = Invoke-Files -Arguments @("share", $report, "-Title", "Weekly report")
$said = [regex]::Match($r.out, '(?m)^shared ([0-9a-f]{32}) version 1: Weekly report \(text/markdown, 29 bytes\)\s*$')
Check ($r.code -eq 0 -and $said.Success) ("the share prints its file id, version 1, the title with its space, the type and the size, and exits 0 (" + $r.code + ": " + $r.out.Trim() + ")")
$fileId = $said.Groups[1].Value
$record1 = Join-Path $store ($fileId + ".000001.json")
Check ([System.IO.File]::Exists($record1)) "CONTROL: the record of that id and version is in the home this suite made"
$onDisk = [System.IO.File]::ReadAllText($record1) | ConvertFrom-Json
Check ($onDisk.title -ceq "Weekly report" -and $onDisk.type -ceq "text/markdown" -and $onDisk.size -eq 29 -and $onDisk.version -eq 1 -and $onDisk.editable -eq $false) "the record holds the title, type, size and version, and is not editable"
Check ($onDisk.session.known -eq $true -and $onDisk.session.id -ceq "cli-session-1") "and the id of the session that ran the command"
$kept = Join-Path $store ($onDisk.sha256 + ".bytes")
Check ([System.IO.File]::Exists($kept) -and [System.IO.File]::ReadAllText($kept) -ceq "# Weekly report`nAll is well.`n") "the report's bytes are kept beside it, under the sha256 the record names"
[System.IO.File]::WriteAllText($report, "# Weekly report`nAll is well, and more.`n")
$r = Invoke-Files -Arguments @("share", $report, "-Title", "Weekly report, corrected", "-Editable")
Check ($r.code -eq 0 -and $r.out -like ("*shared " + $fileId + " version 2: Weekly report, corrected (text/markdown, 39 bytes)*")) ("sharing the same path again is version 2 of the SAME file id (" + $r.out.Trim() + ")")
$v2 = [System.IO.File]::ReadAllText((Join-Path $store ($fileId + ".000002.json"))) | ConvertFrom-Json
Check ($v2.editable -eq $true -and $v2.version -eq 2) "-Editable is recorded on version 2"
Check ([System.IO.File]::ReadAllText($record1) -like '*"version":1,"title":"Weekly report",*' -and [System.IO.File]::Exists($kept)) "and version 1, record and bytes, is as it was"

Write-Host ""
Write-Host "--- a picture, the same bytes under another title, and a share outside any session ---" -ForegroundColor Cyan
$pngBytes = New-Object byte[] 64
[Array]::Copy([byte[]]@(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A), $pngBytes, 8)
$picture = Join-Path $docs "chart.png"
[System.IO.File]::WriteAllBytes($picture, $pngBytes)
$r = Invoke-Files -Arguments @("share", $picture, "-Title", "Chart")
Check ($r.code -eq 0 -and $r.out -like "*version 1: Chart (image/png, 64 bytes)*") "a PNG whose first bytes are a PNG's is shared as image/png"
$copy = Join-Path $docs "chart-copy.png"
[System.IO.File]::WriteAllBytes($copy, $pngBytes)
$bytesBefore = Get-StoreCount "*.bytes"
$r = Invoke-Files -Arguments @("share", $copy, "-Title", "The same chart, another title")
Check ($r.code -eq 0 -and (Get-StoreCount "*.bytes") -eq $bytesBefore) ("the same bytes shared from another path under another title are stored ONCE (" + (Get-StoreCount "*.bytes") + " bytes files, as before)")
$r = Invoke-Files -Arguments @("share", $report, "-Title", "From no session") -Session ""
$saidNone = [regex]::Match($r.out, '(?m)^shared ([0-9a-f]{32}) version 1: From no session ')
Check ($r.code -eq 0 -and $saidNone.Success -and $saidNone.Groups[1].Value -cne $fileId) "the same report shared outside any session is another file, at version 1"
$none = [System.IO.File]::ReadAllText((Join-Path $store ($saidNone.Groups[1].Value + ".000001.json"))) | ConvertFrom-Json
Check ($none.session.known -eq $false -and "$($none.session.reason)" -ne "" -and $null -eq $none.session.PSObject.Properties["id"]) "its record says no session is known, with the reason, and names none"
$r = Invoke-Files -Arguments @("share", $report, "-Title", "From another session") -Session "cli-session-2"
Check ($r.code -eq 0 -and $r.out -like "*version 1: From another session*" -and $r.out -notlike ("*" + $fileId + "*")) "and from another session it is another file again"

Write-Host ""
Write-Host "--- what is refused: a reason on the line, exit 1, and nothing written ---" -ForegroundColor Cyan
Check (Test-RefusedByCli @("share", (Join-Path $docs "not-there.md"), "-Title", "Missing") "not shared: there is no file") "a file that is not there"
Check (Test-RefusedByCli @("share", $docs, "-Title", "A folder") "is a folder") "a folder"
# Letters, not zero bytes: a NUL is not text, and this is about the size.
$atCap = Join-Path $docs "at-cap.txt"; [System.IO.File]::WriteAllText($atCap, ("a" * 1048576))
$overCap = Join-Path $docs "over-cap.txt"; [System.IO.File]::WriteAllText($overCap, ("a" * 1048577))
Check (Test-RefusedByCli @("share", $overCap, "-Title", "Too large") "it is 1048577 bytes; the largest file that is shared is 1048576 bytes (the setting maxFileBytes)") "a file one byte over the cap, naming both numbers and the setting"
$r = Invoke-Files -Arguments @("share", $atCap, "-Title", "Exactly the cap")
Check ($r.code -eq 0 -and $r.out -like "*(text/plain, 1048576 bytes)*") "CONTROL: a file of exactly the cap is shared"
$fake = Join-Path $docs "fake.png"; [System.IO.File]::WriteAllText($fake, "these are words, not a picture")
Check (Test-RefusedByCli @("share", $fake, "-Title", "Not a PNG") "its name says image/png, but its first bytes are not that format's") "a .png that is not a PNG"
$svg = Join-Path $docs "drawing.svg"; [System.IO.File]::WriteAllText($svg, "<svg xmlns='http://www.w3.org/2000/svg'/>")
Check (Test-RefusedByCli @("share", $svg, "-Title", "A drawing") "an SVG file is not shared") "an SVG file"
$exe = Join-Path $docs "tool.exe"; [System.IO.File]::WriteAllText($exe, "MZ")
Check (Test-RefusedByCli @("share", $exe, "-Title", "A program") "its type (.exe) is not one that is shared") "a type that is not on the list"
$link = Join-Path $docs "link.md"
$null = & cmd.exe /c ("mklink `"" + $link + "`" `"" + $report + "`" >nul 2>nul")
Check ([System.IO.File]::Exists($link) -and (([System.IO.File]::GetAttributes($link) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) "CONTROL: a symbolic link to the report was made"
Check (Test-RefusedByCli @("share", $link, "-Title", "Through a link") "is a link") "a link to a file that could itself be shared"
[System.IO.File]::Delete($link)
Check (Test-RefusedByCli @("share", $report) "share needs -Title") "a share with no title"
Check (Test-RefusedByCli @("share", $report, "-Title", " ") "needs a title") "a share whose title is a blank"
Check (Test-RefusedByCli @("share", "-Title", "No path") "share needs the path") "a share with no path"
Check (Test-RefusedByCli @("list", "-Title", "x") "-Title belongs to files share") "list given a flag of share"
Check (Test-RefusedByCli @("list", $report) "belongs to files share") "list given a path"
$r = Invoke-Files -Arguments @("publish", $report)
Check ($r.code -ne 0 -and $r.out -notlike "*shared *version*") ("a verb the command does not have fails (" + $r.code + ")")
$r = Invoke-Files -Arguments @()
Check ($r.code -ne 0) ("and so does no verb at all (" + $r.code + ")")

Write-Host ""
Write-Host "--- the list ---" -ForegroundColor Cyan
$r = Invoke-Files -Arguments @("list")
$lines = @($r.out -split "`r?`n" | Where-Object { $_.Trim() -ne "" })
Check ($r.code -eq 0 -and $lines.Count -eq 7) ("the list has one line for each of the 7 versions shared, and none for what was refused (" + $lines.Count + ")")
Check (@($lines | Where-Object { $_ -cmatch ('\A' + $fileId + '  v1  text/markdown  29 bytes  cli-session-1  [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]{12}Z  Weekly report\z') }).Count -eq 1) "a line holds the id, version, type, size, sharing session, time and title"
Check (@($lines | Where-Object { $_ -clike ($fileId + "  v2  *  Weekly report, corrected") }).Count -eq 1) "version 2 of the report is its own line, under the same id"
Check (@($lines | Where-Object { $_ -clike "*  no session  *  From no session" }).Count -eq 1) "the share made outside any session says 'no session'"
Check (@($lines | Where-Object { $_ -clike "*  cli-session-2  *  From another session" }).Count -eq 1) "and the other session's names that session"
Check ($lines[0] -clike "*  Weekly report" -and $lines[6] -clike "*  Exactly the cap") "the lines are oldest first"
Check ((Get-StoreCount "*.json") -eq 7 -and (Get-StoreCount "writing-*.part") -eq 0) "the store holds those 7 records and no temporary file"

Write-Host ""
Write-Host "--- the cap is a setting a person can change, and a bad settings file refuses the command ---" -ForegroundColor Cyan
New-Item -ItemType Directory -Path (Join-Path $hordeHome "settings") | Out-Null
[System.IO.File]::WriteAllText((Join-Path $hordeHome "settings\files.json"), '{ "schemaVersion": 1, "settings": { "maxFileBytes": 10 } }')
Check (Test-RefusedByCli @("share", $report, "-Title", "Now too large") "the largest file that is shared is 10 bytes (the setting maxFileBytes)") "with maxFileBytes set to 10 in settings\files.json, the 39-byte report is refused"
$small = Join-Path $docs "ten.txt"; [System.IO.File]::WriteAllText($small, "0123456789")
$r = Invoke-Files -Arguments @("share", $small, "-Title", "Ten bytes")
Check ($r.code -eq 0 -and $r.out -like "*(text/plain, 10 bytes)*") "and a file of exactly 10 bytes is shared"
[System.IO.File]::WriteAllText((Join-Path $hordeHome "settings\files.json"), '{ "schemaVersion": 1, "settings": { "maxFileBites": 10 } }')
Check (Test-RefusedByCli @("share", $small, "-Title", "Under a bad file") "it has the key 'maxFileBites', which is no setting of files") "a settings file with a key that is no setting refuses the share, naming the key"
Check (Test-RefusedByCli @("list") "is refused") "and refuses the list too: nothing runs on a default the person did not choose"


Write-Host ""
Write-Host "--- a list that cannot be read is a failure, not an empty list ---" -ForegroundColor Cyan
$oddHome = Join-Path $script:work "home-whose-store-is-a-file"
New-Item -ItemType Directory -Path (Join-Path $oddHome "store") | Out-Null
[System.IO.File]::WriteAllText((Join-Path $oddHome "store\files"), "not a folder")
$r = Invoke-Files -Arguments @("list") -TestHome $oddHome
Check ($r.code -eq 1 -and $r.out -like "*the list of shared files could not be read:*is a file, not a folder*" -and $r.out -notlike "*no files have been shared*") ("with a file where the store should be, list says why and exits 1 (" + $r.code + ")")

# THE CHECKS ADDED AFTER REVIEW run in a home of their own, so the counts above stay what they were.
$home2 = Join-Path $script:work "home-two"
$store2 = Join-Path $home2 "store\files"
$said = New-Object System.Collections.ArrayList
function Invoke-Files2 {
    # horde files <arguments> in the second home; what a command that succeeded printed is kept in $said.
    param([string[]]$Arguments, [string]$Session = "cli-session-1")
    $r = Invoke-Files -Arguments $Arguments -Session $Session -TestHome $home2
    if ($r.code -eq 0) { [void]$said.Add($r.out) }
    return $r
}
function Get-Store2Names { if (-not (Test-Path -LiteralPath $store2)) { return "" }; return (@(Get-ChildItem -LiteralPath $store2 -Force | Sort-Object Name | ForEach-Object { $_.Name }) -join ",") }
function Test-Refused2 {
    # In the second home: did the command exit 1, say why with words like -Like, and leave the store as it was?
    param([string[]]$Arguments, [string]$Like)
    $before = Get-Store2Names
    $r = Invoke-Files -Arguments $Arguments -TestHome $home2
    $ok = ($r.code -eq 1 -and $r.out -like ("*not shared: *" + $Like + "*") -and (Get-Store2Names) -ceq $before)
    if (-not $ok) { Write-Host ("         got: exit " + $r.code + ": " + $r.out.Trim()) -ForegroundColor Red }
    return $ok
}

Write-Host ""
Write-Host "--- one file is one file, however its path is written ---" -ForegroundColor Cyan
$figures = Join-Path $docs "quarterly-figures.md"
[System.IO.File]::WriteAllText($figures, "# Numbers`n")
$r = Invoke-Files2 -Arguments @("share", $figures, "-Title", "Numbers")
$saidFigures = [regex]::Match($r.out, '(?m)^shared ([0-9a-f]{32}) version 1: Numbers \(text/markdown, 10 bytes\)\s*$')
Check ($r.code -eq 0 -and $saidFigures.Success) ("a file is shared by its plain path: version 1 (" + $r.out.Trim() + ")")
$figuresId = $saidFigures.Groups[1].Value
$r = Invoke-Files2 -Arguments @("share", ("\\?\" + $figures), "-Title", "Numbers, by the long-path prefix")
Check ($r.code -eq 0 -and $r.out -like ("*shared " + $figuresId + " version 2: *")) ("named with the long-path prefix it is version 2 of the SAME file id (" + $r.out.Trim() + ")")
$figuresUnc = "\\localhost\" + $figures.Substring(0, 1) + "$" + $figures.Substring(2)
Check (Test-Refused2 @("share", $figuresUnc, "-Title", "Numbers, by a share of this machine") "is a network path") "named by this machine's own drive share it is refused: a network path is never looked at, and the file is named by its local path"
Check (Test-Refused2 @("share", "\\a-host-that-is-not-there\share\numbers.md", "-Title", "Numbers, from a server") "is a network path") "and so is a path on any other server, with the same reason and not a not-found one"

Write-Host ""
Write-Host "--- text that is not text, a device, and a stream: a reason on the line, exit 1, nothing written ---" -ForegroundColor Cyan
$pngAgain = New-Object byte[] 64
[Array]::Copy([byte[]]@(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A), $pngAgain, 8)
foreach ($ext in @(".txt", ".md", ".json", ".html")) {
    $renamed = Join-Path $docs ("a-picture" + $ext)
    [System.IO.File]::WriteAllBytes($renamed, $pngAgain)
    Check (Test-Refused2 @("share", $renamed, "-Title", "Renamed") "it holds a NUL byte") ("a PNG renamed " + $ext)
}
$notUtf8 = Join-Path $docs "latin1.md"; [System.IO.File]::WriteAllBytes($notUtf8, [byte[]]@(0x63, 0x61, 0x66, 0xE9))
Check (Test-Refused2 @("share", $notUtf8, "-Title", "Latin-1") "it is not UTF-8") "a text file saved in another encoding than UTF-8"
$utf16 = Join-Path $docs "utf16.txt"; [System.IO.File]::WriteAllBytes($utf16, [byte[]]@(0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00))
Check (Test-Refused2 @("share", $utf16, "-Title", "UTF-16") "it is UTF-16") "a text file saved as UTF-16"
$badJson = Join-Path $docs "broken.json"; [System.IO.File]::WriteAllText($badJson, "[1,]")
Check (Test-Refused2 @("share", $badJson, "-Title", "Broken") "its name says JSON, but it is not: at byte 3, a value was expected") "a .json file with a comma before its closing bracket, which a lenient parser takes"
$emptyJson = Join-Path $docs "empty.json"; [System.IO.File]::WriteAllBytes($emptyJson, [byte[]]@())
Check (Test-Refused2 @("share", $emptyJson, "-Title", "Empty") "it holds no value") "an empty .json file"
$goodJson = Join-Path $docs "good.json"; [System.IO.File]::WriteAllText($goodJson, '{"a":[1,2,{"b":null}],"A":"x"}')
$r = Invoke-Files2 -Arguments @("share", $goodJson, "-Title", "Good")
Check ($r.code -eq 0 -and $r.out -like "*version 1: Good (application/json, 30 bytes)*") ("CONTROL: a .json file holding JSON is shared (" + $r.out.Trim() + ")")
foreach ($device in @("NUL", "CON", "COM1", "nul.md")) { Check (Test-Refused2 @("share", $device, "-Title", "A device") "is a name Windows keeps for a device") ("the device name " + $device) }
Check (Test-Refused2 @("share", "\\.\NUL", "-Title", "A device") "is in the device form") "the device form of a device"
Check (Test-Refused2 @("share", ("\\.\" + $figures), "-Title", "A device") "is in the device form") "and the device form of a file that could itself be shared"
[System.IO.File]::WriteAllText(("\\?\" + $figures + ":hidden.txt"), "words kept in a stream")
Check ([System.IO.File]::ReadAllText(("\\?\" + $figures + ":hidden.txt")) -ceq "words kept in a stream") "CONTROL: the file has a stream named hidden.txt"
Check (Test-Refused2 @("share", ($figures + ":hidden.txt"), "-Title", "A stream") "that names a stream inside a file") "a stream inside a file"
Check (Test-Refused2 @("share", ("\\?\" + $figures + ":hidden.txt"), "-Title", "A stream") "that names a stream inside a file") "and the same behind the long-path prefix"

Write-Host ""
Write-Host "--- the key file ids are made with: in no record and on no line, and never made twice ---" -ForegroundColor Cyan
$keyFile = Join-Path $home2 "keys\files-id.key"
$keyBytes = [byte[]]@()
if ([System.IO.File]::Exists($keyFile)) { $keyBytes = [System.IO.File]::ReadAllBytes($keyFile) }
Check ($keyBytes.Length -eq 32) "the first share of the home made a key of 32 bytes at <home>\keys\files-id.key"
$r = Invoke-Files2 -Arguments @("list")
$keyForms = @([System.BitConverter]::ToString($keyBytes).Replace("-", "").ToLowerInvariant(), [System.BitConverter]::ToString($keyBytes).Replace("-", ""), [System.BitConverter]::ToString($keyBytes), [System.Convert]::ToBase64String($keyBytes))
$everything = ($said -join "`n") + "`n" + (@(Get-ChildItem -LiteralPath $store2 -Filter "*.json" | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n")
Check ($keyBytes.Length -eq 32 -and $said.Count -ge 4 -and @($keyForms | Where-Object { $everything.Contains($_) }).Count -eq 0) ("no line a command printed and no record holds the key, in hex or base64 (" + $said.Count + " commands, " + @(Get-ChildItem -LiteralPath $store2 -Filter "*.json").Count + " records read)")
Check ($keyBytes.Length -eq 32 -and ("x " + $keyForms[0] + " y").Contains($keyForms[0]) -and @(Get-ChildItem -LiteralPath $store2 -Force | Where-Object { [System.BitConverter]::ToString([System.IO.File]::ReadAllBytes($_.FullName)).Contains($keyForms[2]) }).Count -eq 0) "nor does any file of the store hold its bytes"
Check (@(@("quarterly-figures", "good.json", (Split-Path -Leaf $docs), (Split-Path -Leaf $script:work)) | Where-Object { $everything.Contains($_) }).Count -eq 0) "and no piece of a shared file's path - its name, its folder - is on any of those lines or in any record"
Check ($everything.Contains("Numbers") -and $everything.Contains($figuresId)) "CONTROL: what was read does hold the titles and the file id, so the look was at the right text"
[System.IO.File]::Delete($keyFile)
Check (Test-Refused2 @("share", $figures, "-Title", "With the key gone") "is missing, and the store already holds shared files") "with the key file deleted, the next share is refused with the reason"
Check (-not [System.IO.File]::Exists($keyFile)) "and no new key is made: a new key would give the file a new id in silence"
[System.IO.File]::WriteAllBytes($keyFile, [byte[]]($keyBytes[0..9]))
Check (Test-Refused2 @("share", $figures, "-Title", "With the key cut short") "a key is 32 bytes, and it is 10 bytes") "with the key file cut to 10 bytes, the share is refused with the reason"
Check ((New-Object System.IO.FileInfo($keyFile)).Length -eq 10) "and the damaged file is left as it is"
[System.IO.File]::WriteAllBytes($keyFile, $keyBytes)
$r = Invoke-Files -Arguments @("share", $figures, "-Title", "With the key back") -TestHome $home2
Check ($r.code -eq 0 -and $r.out -like ("*shared " + $figuresId + " version *: With the key back*")) ("CONTROL: with the key back, the same path is the next version of the SAME file id (" + $r.out.Trim() + ")")
$home3 = Join-Path $script:work "home-three"
$r = Invoke-Files -Arguments @("share", $figures, "-Title", "In another home") -TestHome $home3
$saidThree = [regex]::Match($r.out, '(?m)^shared ([0-9a-f]{32}) version 1: In another home ')
Check ($r.code -eq 0 -and $saidThree.Success -and $saidThree.Groups[1].Value -cne $figuresId) "the same session sharing the same path in another home, which has another key, gets another file id"


# THE DENY LIST, THROUGH THE COMMAND (files/Deny.ps1; its rules are attacked in test/test-files-deny.ps1).
# A user's profile of this suite's own: USERPROFILE is set for each child, so the folders that are
# refused are folders this suite made, holding dummy words. WHICH folders are an agent harness's is
# read from each adapter's own stores.json, as the code reads it, so no harness is named here
# (CONTRIBUTING 14); every variable an adapter says can move its store is emptied for the child, and
# the first of them is aimed at a folder of this suite's, so the real stores are never looked at.
$home4 = Join-Path $script:work "home-four"
$store4 = Join-Path $home4 "store\files"
$profile4 = Join-Path $script:work "profile"
New-Item -ItemType Directory -Path $profile4 | Out-Null
$harnessFolders = New-Object System.Collections.ArrayList
$harnessVariables = New-Object System.Collections.ArrayList
foreach ($storesFile in @(Get-ChildItem -LiteralPath (Join-Path $root "agents") -Directory | Sort-Object Name | ForEach-Object { Join-Path $_.FullName "stores.json" } | Where-Object { Test-Path -LiteralPath $_ })) {
    foreach ($storeRoot in @(([System.IO.File]::ReadAllText($storesFile) | ConvertFrom-Json).roots)) {
        if ($null -ne $storeRoot.PSObject.Properties["profile"]) { [void]$harnessFolders.Add("" + $storeRoot.profile) }
        if ($null -ne $storeRoot.PSObject.Properties["env"]) { [void]$harnessVariables.Add("" + $storeRoot.env) }
    }
}
$movedStore = Join-Path $script:work "a-harness-store-moved-by-its-variable"
function Invoke-Deny {
    # horde files <arguments> in the fourth home, as a user whose profile is this suite's: { code; out }.
    param([string[]]$Arguments)
    $childEnv = @{ HORDE_HOME = $home4; USERPROFILE = $profile4 }
    $childEnv[$sessionVariable] = "cli-session-1"
    foreach ($variable in $harnessVariables) { $childEnv[$variable] = "" }
    if ($harnessVariables.Count -gt 0) { $childEnv[$harnessVariables[0]] = $movedStore }
    return (Invoke-HordeCliProcess -Root $root -HordeArgs (@("files") + $Arguments) -Env $childEnv)
}
function Get-Store4Names { if (-not (Test-Path -LiteralPath $store4)) { return "" }; return (@(Get-ChildItem -LiteralPath $store4 -Force | Sort-Object Name | ForEach-Object { $_.Name }) -join ",") }
function Test-Denied {
    # Did the command exit 1, say why with words like -Like, and leave the fourth home's store as it was?
    param([string[]]$Arguments, [string]$Like)
    $before = Get-Store4Names
    $r = Invoke-Deny -Arguments $Arguments
    $ok = ($r.code -eq 1 -and $r.out -like ("*not shared: *" + $Like + "*") -and (Get-Store4Names) -ceq $before)
    if (-not $ok) { Write-Host ("         got: exit " + $r.code + ": " + $r.out.Trim()) -ForegroundColor Red }
    return $ok
}
function Test-Allowed {
    param([string[]]$Arguments)
    $r = Invoke-Deny -Arguments $Arguments
    if ($r.code -ne 0) { Write-Host ("         got: exit " + $r.code + ": " + $r.out.Trim()) -ForegroundColor Red }
    return ($r.code -eq 0 -and $r.out -like "*shared * version *")
}
function New-Dummy { param([string]$Path, [string]$Text = "dummy words, and no secret") [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path)); [System.IO.File]::WriteAllText($Path, $Text); return $Path }
$neverSaid = "Nothing there is ever shared, and -Force does not change that"

Write-Host ""
Write-Host "--- the deny list: a name that holds a word of it, from both sides, and -Force ---" -ForegroundColor Cyan
$plainNote = New-Dummy (Join-Path $docs "plain-note.md")
Check (Test-Allowed @("share", $plainNote, "-Title", "A plain note")) "CONTROL: as that user, an ordinary file is shared"
# Two names here, one line each way: every word, at every place in a name, is test/test-files-deny.ps1's.
foreach ($named in @("api-key.txt", "auth.json")) {
    $namedFile = New-Dummy (Join-Path $docs $named) $(if ($named -like "*.json") { '{"dummy":1}' } else { "dummy words, and no secret" })
    Check (Test-Denied @("share", $namedFile, "-Title", "Named like a secret") ("its name, '" + $named + "', holds '*share it again with -Force")) ($named + " is refused, naming the file and the word, and the line says -Force shares it")
    Check (Test-Allowed @("share", $namedFile, "-Title", "Named like a secret, and none", "-Force")) "with -Force it is shared"
}
Check (Test-Allowed @("share", (New-Dummy (Join-Path $docs "keyboard.md")), "-Title", "A keyboard")) "CONTROL: keyboard.md is shared with no -Force"
$r = Invoke-Deny -Arguments @("list", "-Force")
Check ($r.code -eq 1 -and $r.out -like "*-Force belongs to files share*") "list given -Force is refused: it is a flag of share"

Write-Host ""
Write-Host "--- the deny list: each place from both sides, and -Force ---" -ForegroundColor Cyan
Check ([System.IO.Directory]::Exists($store4)) "CONTROL: the fourth home is there, with its store"
$inHome4 = New-Dummy (Join-Path $home4 "settings\notes.json") '{"dummy":1}'
Check (Test-Denied @("share", $inHome4, "-Title", "From the home") "is under the Horde home") "a file in the Horde home's settings folder is refused as the Horde home"
Check (Test-Denied @("share", $inHome4, "-Title", "From the home", "-Force") ("is under the Horde home*" + $neverSaid)) "with -Force it is refused all the same, and the line says -Force does not change that"
Check (Test-Allowed @("share", (New-Dummy ($home4 + "-beside\notes.md")), "-Title", "Beside the home")) "CONTROL: a file in a folder whose name only begins with the home's is shared"
$inSecrets4 = New-Dummy (Join-Path $profile4 ".horde-secrets\client.json") '{"dummy":1}'
Check (Test-Denied @("share", $inSecrets4, "-Title", "A client file", "-Force") ("is under a .horde-secrets folder*" + $neverSaid)) "a file under .horde-secrets in the profile is refused as that, with -Force too, and the line says -Force does not change that"
Check (Test-Denied @("share", (New-Dummy (Join-Path $script:work "a-copy\.horde-secrets\client.md")), "-Title", "A copy", "-Force") ("is under a folder named '.horde-secrets': a folder named .horde, or one whose name begins with .horde-, is Horde's own*" + $neverSaid)) "a folder of that name anywhere on the way to the file is refused, -Force or not: it is one of Horde's own folders by its name"
$inSsh4 = New-Dummy (Join-Path $profile4 ".ssh\notes.txt")
Check (Test-Denied @("share", $inSsh4, "-Title", "From .ssh") "is under the folder the user's SSH keys are kept in") "a file under .ssh in the profile is refused as that"
Check (Test-Denied @("share", $inSsh4, "-Title", "From .ssh, and no secret", "-Force") ("is under the folder the user's SSH keys are kept in*" + $neverSaid)) "with -Force it is refused all the same, and the line says -Force does not change that"
Check ($harnessFolders.Count -ge 1) ("CONTROL: the adapters declare " + $harnessFolders.Count + " folders in the profile, and " + $harnessVariables.Count + " variables that move a store")
$nth = 0
foreach ($harnessFolder in $harnessFolders) {
    $nth++
    $inHarness = New-Dummy (Join-Path (Join-Path $profile4 $harnessFolder) "projects\notes.md")
    Check (Test-Denied @("share", $inHarness, "-Title", "From a harness") "is under a folder an agent harness keeps its own files in") ("a file under harness folder " + $nth + " of the profile is refused as a harness's own folder")
    if ($nth -eq 1) {
        Check (Test-Allowed @("share", $inHarness, "-Title", "From a harness, and no secret", "-Force")) "with -Force it is shared: the place is lifted"
        $signInThere = New-Dummy (Join-Path (Join-Path $profile4 $harnessFolder) "auth.json") '{"dummy":1}'
        Check (Test-Denied @("share", $signInThere, "-Title", "Named like a sign-in", "-Force") "its name, 'auth.json', holds 'auth', as a file of secrets is named, and it is under a folder an agent harness keeps its own files in*-Force shares other files from such a folder, and never one that is named so") "but a file NAMED as a secret in that folder is refused even with -Force, and the line says it is the name, in that place"
    }
}
if ($harnessVariables.Count -gt 0) {
    $inMoved = New-Dummy (Join-Path $movedStore "notes.md")
    Check (Test-Denied @("share", $inMoved, "-Title", "From a moved store") "is under a folder an agent harness keeps its own files in") "a file under the folder a harness's variable moves its store to is refused the same"
} else { Write-Host "  [SKIP] NO ADAPTER DECLARES A VARIABLE THAT MOVES ITS STORE, so a moved store was not tested through the command." -ForegroundColor Yellow }

Write-Host ""
Write-Host "--- what a text file holds: a private key never, a token unless -Force ---" -ForegroundColor Cyan
# Assembled from pieces at run time, as test/test-secrets.ps1 does; neither was ever a credential.
# Every kind and every way of writing one is test/test-files-deny.ps1's.
$keyLine4 = "-----BEGIN RSA PRIV" + "ATE KEY-----"
$holdsKey = New-Dummy (Join-Path $docs "a-report.md") ("# A report`n`n" + $keyLine4 + "`nMIIEow" + "IBAAKCAQEAx9Qm`n")
Check (Test-Denied @("share", $holdsKey, "-Title", "A report", "-Force") "what it holds looks like a private key*A file that holds one is never shared, and -Force does not change that") "a Markdown file holding a private key's first line is refused even with -Force, and the line says so"
$token4 = "gh" + "p_" + ("Ab1" * 12)
$holdsToken = New-Dummy (Join-Path $docs "a-note.md") ("The value is " + $token4 + " and more words.")
$before = Get-Store4Names
$r = Invoke-Deny -Arguments @("share", $holdsToken, "-Title", "A note")
Check ($r.code -eq 1 -and $r.out -like "*not shared: what it holds looks like an access token, by its shape*share it again with -Force*" -and -not $r.out.Contains("Ab1Ab1") -and (Get-Store4Names) -ceq $before) "a Markdown file holding a token of a known shape is refused, the line names the kind and repeats nothing of what was found"
Check (Test-Allowed @("share", $holdsToken, "-Title", "A note, and no secret", "-Force")) "with -Force it is shared"

Write-Host ""
Write-Host "--- the deny list judges where the file really is: a junction ---" -ForegroundColor Cyan
$sshJunction = Join-Path $script:work "docs\a-junction"
$null = & cmd.exe /c ("mklink /J `"" + $sshJunction + "`" `"" + (Join-Path $profile4 ".ssh") + "`" >nul 2>nul")
Check ([System.IO.File]::Exists((Join-Path $sshJunction "notes.txt"))) "CONTROL: a junction outside .ssh was made to it"
Check (Test-Denied @("share", (Join-Path $sshJunction "notes.txt"), "-Title", "By a junction") "is under the folder the user's SSH keys are kept in") "a file in .ssh named through a junction outside it is refused as .ssh, not only as a link"
$homeJunction = Join-Path $script:work "docs\a-junction-to-the-home"
$null = & cmd.exe /c ("mklink /J `"" + $homeJunction + "`" `"" + $home4 + "`" >nul 2>nul")
Check (Test-Denied @("share", (Join-Path $homeJunction "settings\notes.json"), "-Title", "By a junction", "-Force") "is under the Horde home") "and a file in the home named through a junction is refused as the home, -Force or not"
# BY A DRIVE LETTER OVER THE FOLDER (subst): NOT RUN THROUGH THE COMMAND ANY MORE. Until 2026-10-13
# this suite made a subst drive over .ssh, and one over an ordinary folder, and ran the real command
# on a path on it. A drive letter is seen by every process of the user while it exists, and a suite
# must not change what other processes see (test/lib/SuiteFiles.ps1, Get-HordeDriveLetterMakers). The
# command runs in a child process, where nothing of this suite's can answer for Windows, so those
# two cases cannot be run here without a real letter. WHERE THEY WENT: a drive over .ssh and over the
# home is test/test-files-deny.ps1's, and one file by a drive over its folder being the next version
# of the same id is test/test-files-store.ps1's, both with a PowerShell drive of the process's own.
# WHAT NO SUITE RUNS NOW: the real command, end to end, on a path on a real drive-letter alias.

Write-Host ""
Write-Host "--- the other refusals of the review, through the command ---" -ForegroundColor Cyan
$pngAsHtm = Join-Path $docs "a-picture.htm"; [System.IO.File]::WriteAllBytes($pngAsHtm, $pngAgain)
Check (Test-Denied @("share", $pngAsHtm, "-Title", "Renamed") "it holds a NUL byte") "a PNG renamed .htm, the one text extension not tried above"
$sneakedPng = Join-Path $docs ("picture.pn" + [char]0xAD + "g"); [System.IO.File]::WriteAllBytes($sneakedPng, $pngAgain)
Check (Test-Denied @("share", $sneakedPng, "-Title", "A look-alike extension") "is not one that is shared") "a PNG whose extension holds a soft hyphen (.pn<U+00AD>g) is refused: it is not the extension .png"
$tooDeep = New-Dummy (Join-Path $docs "deep.json") (("[" * 513) + ("]" * 513))
Check (Test-Denied @("share", $tooDeep, "-Title", "Too deep") "it is nested more than 512 deep") "a .json file nested 513 deep is refused"
$loneHalf = New-Dummy (Join-Path $docs "lone-half.json") ('"' + [char]92 + 'ud800"')
Check (Test-Denied @("share", $loneHalf, "-Title", "Half a pair") "the first half of a surrogate pair, not followed by its second half") "a .json file holding half a surrogate pair as an escape is refused"
Check (Test-Denied @("share", $plainNote, "-Title", ("report" + [char]0x202E + "txt.exe")) "turns the direction of the text round it (U+202E)") "a title holding a character that turns text round is refused, and the line names it"
Check (Test-Denied @("share", ($docs.Substring(0, 2) + "NUL.txt"), "-Title", "A device") "is a name Windows keeps for a device") "a device's name behind a bare drive letter (C:NUL.txt) is refused as a device"
$shortOfNote = ""
try { $shortOfNote = (New-Object -ComObject Scripting.FileSystemObject).GetFile((New-Dummy (Join-Path $docs "a long name holding a secret word.md"))).ShortPath } catch { $shortOfNote = "" }
if ($shortOfNote -ne "" -and (Split-Path -Leaf $shortOfNote) -like "*~*" -and (Split-Path -Leaf $shortOfNote) -notlike "*secret*") {
    Check (Test-Denied @("share", ("\\?\" + $shortOfNote), "-Title", "By a short name") "holds 'secret'") ("opened by its 8.3 short name, which holds no word (" + (Split-Path -Leaf $shortOfNote) + "), a file is refused for the name the disk holds")
} else { Write-Host "  [SKIP] A NAME OPENED BY ITS 8.3 SHORT NAME COULD NOT BE TESTED: this volume gave the file no short name without the word in it." -ForegroundColor Yellow }

Write-Host ""
Write-Host "--- PowerShell 7: the share refuses in plain words, and makes nothing ---" -ForegroundColor Cyan
$pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if ($null -ne $pwsh) {
    $home7 = Join-Path $script:work "home-under-seven"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $pwsh.Source
    $psi.Arguments = "-NoProfile -File `"" + (Join-Path $root "horde.ps1") + "`" files share `"" + $plainNote + "`" -Title Seven"
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables["HORDE_HOME"] = $home7
    $psi.EnvironmentVariables[$sessionVariable] = "cli-session-1"
    $seven = [System.Diagnostics.Process]::Start($psi)
    $sevenErr = $seven.StandardError.ReadToEndAsync()
    $sevenOut = $seven.StandardOutput.ReadToEnd() + "`n" + $sevenErr.Result
    $seven.WaitForExit()
    $sevenCode = $seven.ExitCode
    $seven.Dispose()
    Check ($sevenCode -eq 1 -and $sevenOut -like "*not shared: files are shared under Windows PowerShell 5.1 only, and this is PowerShell 7*run the command with powershell.exe*") ("run under PowerShell 7, a share exits 1 and says in plain words that files are shared under 5.1 only (" + $sevenCode + ")")
    Check ($sevenOut -notlike "*Cannot find an overload*" -and $sevenOut -notlike "*FileStream*") "and not with the error of a constructor that runtime does not have"
    Check (-not (Test-Path -LiteralPath $home7)) "it made no home, no keys folder and no key: it did not stop half way"
} else { Write-Host "  [SKIP] POWERSHELL 7 IS NOT ON THIS MACHINE (no pwsh.exe), so the refusal under it was NOT run here." -ForegroundColor Yellow }

# The two junctions first, by their own entries, so that removing the folder never follows one.
foreach ($madeJunction in @($sshJunction, $homeJunction)) {
    if ([System.IO.Directory]::Exists($madeJunction) -and (([System.IO.File]::GetAttributes($madeJunction) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) { [System.IO.Directory]::Delete($madeJunction) }
}
if ((Split-Path -Leaf $script:work) -match '\Ahorde-files-cli-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) {
    # A link first, by its own entry, so that removing the folder never follows one.
    $leftLink = Join-Path $script:work "docs\link.md"
    if ([System.IO.File]::Exists($leftLink) -and (([System.IO.File]::GetAttributes($leftLink) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) { [System.IO.File]::Delete($leftLink) }
    Remove-Item -LiteralPath $script:work -Recurse -Force
}
Check (-not (Test-Path -LiteralPath $script:work)) "the suite's temp folder is removed"

Complete-HordeSuite -Success "horde files shares a file, versions it, refuses what must not be shared with a reason and a non-zero exit, and lists what was shared"
