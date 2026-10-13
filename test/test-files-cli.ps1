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
Check ($r.code -eq 0 -and $r.out -like "*horde files share <path> -Title <one line> ``[-Editable``] | files list*") "horde help lists the command with its usage"
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
if ([System.IO.File]::Exists($figuresUnc)) {
    $r = Invoke-Files2 -Arguments @("share", $figuresUnc, "-Title", "Numbers, by a share of this machine")
    Check ($r.code -eq 0 -and $r.out -like ("*shared " + $figuresId + " version 3: *")) ("named by a UNC path to this machine it is version 3 of the SAME file id (" + $r.out.Trim() + ")")
} else { Write-Host ("  [SKIP] THE UNC FORM COULD NOT BE TESTED: this session cannot open " + $figuresUnc + " (the drive's own share needs an administrator's token). Run this suite elevated.") -ForegroundColor Yellow }

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

if ((Split-Path -Leaf $script:work) -match '\Ahorde-files-cli-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) {
    # A link first, by its own entry, so that removing the folder never follows one.
    $leftLink = Join-Path $script:work "docs\link.md"
    if ([System.IO.File]::Exists($leftLink) -and (([System.IO.File]::GetAttributes($leftLink) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) { [System.IO.File]::Delete($leftLink) }
    Remove-Item -LiteralPath $script:work -Recurse -Force
}
Check (-not (Test-Path -LiteralPath $script:work)) "the suite's temp folder is removed"

Complete-HordeSuite -Success "horde files shares a file, versions it, refuses what must not be shared with a reason and a non-zero exit, and lists what was shared"
