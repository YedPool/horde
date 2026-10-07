# DOES THE DECISIONS STORE KEEP EVERY RECORD ONCE, IN ORDER, AND HAND BACK A DAMAGED ONE AS DAMAGED?
#
# decisions/Store.ps1 alone: write-once records in one folder, named by sequence number. This suite
# attacks the two promises everything above the store rests on:
#   - a sequence number is taken once: a second create of the same number is told "exists", and the
#     first record's bytes are untouched;
#   - a record that cannot be read never makes the list unloadable and is never left out: an empty
#     file, cut JSON, bytes that are not UTF-8, a deleted record and a record held open by another
#     process each come back in their place in the order, marked, with a reason.
# Writers in separate processes racing for one number are test/test-decisions-store-race.ps1.
#
# Every store here is a fresh folder under %TEMP% that this suite made and removes (CONTRIBUTING 9).
# The suite deletes and damages records on purpose, and only ever in those folders.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "decisions\Store.ps1")

$script:work = Join-Path $env:TEMP ("horde-decisions-store-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$script:n = 0
function New-TestStore {
    # The path of a store folder nothing has made yet, inside this suite's own folder.
    $script:n++
    return (Join-Path $script:work ("store-" + $script:n))
}
function Add-Safely {
    # Add a record, turning a throw into text: a mutant that makes the store throw must fail a check,
    # not crash the suite (tools/Mutate.ps1 counts only a failed check as caught).
    param([string]$Store, [long]$Sequence, [string]$Text)
    try { return (Add-HordeDecisionRecord -Root $Store -Sequence $Sequence -Text $Text) } catch { return ("THREW: " + $_.Exception.Message) }
}
function Get-Safely {
    param([string]$Store)
    try { return (Get-HordeDecisionRecords -Root $Store) } catch { return [pscustomobject]@{ state = ("THREW: " + $_.Exception.Message); reason = ""; last = [long]-1; records = @(); strays = @() } }
}
function Kinds { param($Got) return (@($Got.records | ForEach-Object { $_.kind }) -join ",") }
function Base64 { param([string]$Path) return [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path)) }
$utf8 = New-Object System.Text.UTF8Encoding($false)

try {

Write-Host ""
Write-Host "--- a record's name is its place in the order ---" -ForegroundColor Cyan
Check ((Get-HordeDecisionRecordName -Sequence 7) -ceq "0000000007.json") "record 7 is 0000000007.json: ten digits, so names sort as numbers do"
$largestName = "THREW"
try { $largestName = Get-HordeDecisionRecordName -Sequence 9999999999 } catch { $largestName = "THREW: " + $_.Exception.Message }
Check ($largestName -ceq "9999999999.json") ("the largest sequence number still has a ten-digit name (" + $largestName + ")")
Check (Throws { Get-HordeDecisionRecordName -Sequence 0 } "1 to 9999999999") "sequence 0 is refused: the order starts at 1"
Check (Throws { Get-HordeDecisionRecordName -Sequence 10000000000 } "1 to 9999999999") "a sequence number that would need eleven digits is refused, not written under a name that sorts wrongly"
# ONE WIDTH, THREE THINGS WORKED OUT FROM IT (decisions/Format.ps1's one constant): the name, the
# pattern a name is recognised by, and the largest number. Each is asked of the store, so none can be
# a second number written somewhere else.
$digits = Get-HordeDecisionSequenceDigits
$largest = Get-HordeDecisionMaxSequence
Check ($digits -eq 10 -and $largest -eq 9999999999) ("the width is ten digits, and the largest sequence number is the largest ten digits hold (" + $digits + ", " + $largest + ")")
Check ((Get-HordeDecisionRecordName -Sequence $largest).Length -eq ($digits + 5) -and (Get-HordeDecisionRecordName -Sequence 1).Length -eq ($digits + 5)) "the first and the last record have names of one length"
Check (((Get-HordeDecisionRecordName -Sequence 7) -cmatch (Get-HordeDecisionStoreNamePattern)) -and ("123456789.json" -cnotmatch (Get-HordeDecisionStoreNamePattern)) -and ("12345678901.json" -cnotmatch (Get-HordeDecisionStoreNamePattern)) -and ("0000000007.json`n" -cnotmatch (Get-HordeDecisionStoreNamePattern))) "a name the store makes matches the pattern it reads by; one digit fewer, one more, or a line break after it does not"

Write-Host ""
Write-Host "--- no store yet is an empty list, and reading makes nothing ---" -ForegroundColor Cyan
$s = New-TestStore
$got = Get-Safely $s
Check ($got.state -ceq "absent" -and $got.last -eq 0 -and @($got.records).Count -eq 0) "a store folder that does not exist reads as absent, with no records"
Check (-not (Test-Path -LiteralPath $s)) "and reading it did not create it"
# The process's current folder is this suite's own for these checks, so that a store which did write
# to a relative path - a mutant of the refusal - writes inside the suite's folder, not wherever the
# suite was started from (CONTRIBUTING 9).
$cwdBefore = [System.IO.Directory]::GetCurrentDirectory()
try {
    [System.IO.Directory]::SetCurrentDirectory($script:work)
    $rel = Get-Safely "relative\store"
    Check ($rel.state -ceq "unknown" -and $rel.reason -like "*absolute*") "a relative store folder is unknown, never resolved against the current folder"
    Check ((Add-Safely "relative\store" 1 "{}") -like "THREW:*absolute*") "and nothing is written to one"
    Check (-not (Test-Path -LiteralPath (Join-Path $script:work "relative"))) "CONTROL: no folder appeared under the current folder"
} finally { [System.IO.Directory]::SetCurrentDirectory($cwdBefore) }
# A FILE WHERE THE STORE FOLDER SHOULD BE IS NOT "NO STORE YET". Measured 2026-10-06, before the store
# told the two apart: list answered "done, no questions" over a path every write then failed on.
$asFile = New-TestStore
[System.IO.File]::WriteAllText($asFile, "not a folder", $utf8)
$got = Get-Safely $asFile
Check ($got.state -ceq "unknown" -and $got.reason -like "*is a file, not a folder*" -and @($got.records).Count -eq 0) ("a file where the store folder should be reads as unknown, never as a store nobody has added to (" + $got.state + ")")
Check ((Add-Safely $asFile 1 "{}") -like "THREW:*") "CONTROL: and nothing can be written there"
Check ([System.IO.File]::ReadAllText($asFile) -ceq "not a folder") "the file is left exactly as it was"

Write-Host ""
Write-Host "--- a sequence number is taken once ---" -ForegroundColor Cyan
$s = New-TestStore
$first = '{"n":1,"who":"first"}'
Check ((Add-Safely $s 1 $first) -ceq "created") "the first create of record 1 is told created, and the store folder is made for it"
$bytesBefore = Base64 (Join-Path $s "0000000001.json")
Check ((Add-Safely $s 1 '{"n":1,"who":"second"}') -ceq "exists") "a second create of record 1 is told exists"
Check ((Base64 (Join-Path $s "0000000001.json")) -ceq $bytesBefore) "and the first record's bytes are untouched: a record is never rewritten"
Check ([System.IO.File]::ReadAllText((Join-Path $s "0000000001.json")) -ceq $first) "CONTROL: the record on disk is the first writer's text, exactly"
Check ((Add-Safely $s 2 '{"n":2}') -ceq "created") "CONTROL: the next number can still be taken"
$got = Get-Safely $s
Check ($got.state -ceq "ok" -and $got.last -eq 2 -and (Kinds $got) -ceq "ok,ok") "both records read back"
Check ("$($got.records[0].data.who)" -ceq "first" -and $got.records[0].sequence -eq 1 -and $got.records[0].file -ceq "0000000001.json") "record 1 comes back with its sequence number, its file name and its content"

Write-Host ""
Write-Host "--- the order is the sequence number, not the order of writing or of names as text ---" -ForegroundColor Cyan
$s = New-TestStore
foreach ($i in @(3, 12, 1, 10, 2, 11, 5, 4, 9, 8, 7, 6)) { $null = Add-Safely $s $i ('{"n":' + $i + '}') }
$got = Get-Safely $s
Check ((@($got.records | ForEach-Object { $_.sequence }) -join ",") -ceq "1,2,3,4,5,6,7,8,9,10,11,12") "twelve records written out of order come back as 1 to 12"
Check ((@($got.records | ForEach-Object { $_.data.n }) -join ",") -ceq "1,2,3,4,5,6,7,8,9,10,11,12") "and each holds its own content: 10 does not sort before 2"

Write-Host ""
Write-Host "--- a damaged record is handed back as damaged, in its place ---" -ForegroundColor Cyan
$s = New-TestStore
$null = Add-Safely $s 1 '{"n":1}'
[System.IO.File]::WriteAllBytes((Join-Path $s "0000000002.json"), [byte[]]@())
[System.IO.File]::WriteAllText((Join-Path $s "0000000003.json"), '{"n":3,"text":"cut off in the mid', $utf8)
[System.IO.File]::WriteAllText((Join-Path $s "0000000004.json"), '[1,2,3]', $utf8)
[System.IO.File]::WriteAllBytes((Join-Path $s "0000000005.json"), [byte[]]@(0x7B, 0x22, 0x61, 0x22, 0x3A, 0x22, 0xFF, 0xFE, 0xFD, 0x22, 0x7D))
[System.IO.File]::WriteAllText((Join-Path $s "0000000006.json"), '   ', $utf8)
$null = Add-Safely $s 8 '{"n":8}'
$got = Get-Safely $s
Check ($got.state -ceq "ok" -and $got.last -eq 8 -and @($got.records).Count -eq 8) "with six damaged records the store still reads: one entry for every number from 1 to 8"
Check ((Kinds $got) -ceq "ok,torn,torn,torn,error,torn,missing,ok") ("each damaged record is marked for what it is (" + (Kinds $got) + ")")
Check ($got.records[1].reason -like "*it is empty*") "an empty file says it is empty"
Check ($got.records[2].reason -like "*not complete JSON*") "cut JSON says it is not complete"
Check ($got.records[3].reason -like "*not a JSON object*") "JSON that is not an object says so"
Check ($got.records[4].reason -like "*could not be read*") "bytes that are not UTF-8 are an error, never read as other letters"
Check ($got.records[5].reason -like "*it is empty*") "a file of spaces is empty too"
Check ($got.records[6].reason -like "*deleted*" -and $got.records[6].file -ceq "0000000007.json") "a number with no file is missing, named by the file it should have"
Check (@($got.records | Where-Object { $_.kind -cne "ok" -and ("$($_.reason)".Trim() -eq "" -or $null -ne $_.data) }).Count -eq 0) "every damaged record gives a reason and no data"
Check ($got.records[0].data.n -eq 1 -and $got.records[7].data.n -eq 8) "and the readable records around them are read"

Write-Host ""
Write-Host "--- a record another process holds open ---" -ForegroundColor Cyan
$s = New-TestStore
$null = Add-Safely $s 1 '{"n":1}'
$null = Add-Safely $s 2 '{"n":2}'
$held = New-Object System.IO.FileStream((Join-Path $s "0000000002.json"), [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try { $got = Get-Safely $s } finally { $held.Dispose() }
$sw.Stop()
Check ((Kinds $got) -ceq "ok,busy") ("a record still held without sharing after the wait is busy, not torn and not an error (" + (Kinds $got) + ")")
Check ($got.records[1].reason -like "*open in another process*") "and says it is open in another process"
Check ($sw.ElapsedMilliseconds -ge 1500) ("the reader waited for the holder before saying so (" + $sw.ElapsedMilliseconds + " ms)")
$got = Get-Safely $s
Check ((Kinds $got) -ceq "ok,ok") "CONTROL: once released, the same record reads"
# A LIVE WRITER FINISHES WITHIN THE WAIT: another process holds record 3 without sharing, as a writer
# does while it writes, and lets go after about a second. The reader must come back with the record
# read, not with "busy".
$holder = Join-Path $script:work "holder.ps1"
$ready = Join-Path $script:work "holder-ready"
[System.IO.File]::WriteAllText($holder, 'param($Path, $Ready) $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None); [System.IO.File]::WriteAllText($Ready, "held"); Start-Sleep -Milliseconds 900; $fs.Dispose()')
$null = Add-Safely $s 3 '{"n":3}'
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "powershell.exe"
$psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"" + $holder + "`" -Path `"" + (Join-Path $s "0000000003.json") + "`" -Ready `"" + $ready + "`""
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$proc = [System.Diagnostics.Process]::Start($psi)
try {
    $deadline = (Get-Date).AddSeconds(120)
    while (-not (Test-Path -LiteralPath $ready) -and -not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 20 }
    Check (Test-Path -LiteralPath $ready) "CONTROL: the other process took hold of record 3"
    $got = Get-Safely $s
    Check ((Kinds $got) -ceq "ok,ok,ok" -and $got.records[2].data.n -eq 3) ("a record its writer is still holding is waited for and then read whole (" + (Kinds $got) + ")")
} finally {
    # Only the process this suite started, by the handle it holds.
    if (-not $proc.WaitForExit(30000)) { try { $proc.Kill() } catch { } }
    $proc.Dispose()
}

Write-Host ""
Write-Host "--- only the store's own names are records ---" -ForegroundColor Cyan
$s = New-TestStore
foreach ($i in 1..3) { $null = Add-Safely $s $i ('{"n":' + $i + '}') }
foreach ($stray in @("notes.txt", "0000000001 - Copy.json", "abc.json", "00000000099.json", "000000009.json", "0000000004.json.bak", "0000000005.JSON.tmp", "x0000000006.json")) {
    [System.IO.File]::WriteAllText((Join-Path $s $stray), '{"stray":true}', $utf8)
}
$got = Get-Safely $s
Check ($got.state -ceq "ok" -and $got.last -eq 3 -and (Kinds $got) -ceq "ok,ok,ok") ("files of other names beside the records change nothing: still records 1 to 3 (last " + $got.last + ", " + (Kinds $got) + ")")
Check ((Add-Safely $s 4 '{"n":4}') -ceq "created") "and the next number is still free to take"

Write-Host ""
Write-Host "--- a file too far ahead to be a record is a stray: named, not believed, not walked to ---" -ForegroundColor Cyan
# Measured 2026-10-06, before the gap limit: 0000002000.json beside two records took a list 11.6 s,
# reported 1998 missing records and moved the next record to 2001; 9999999999.json never came back.
function Get-Strays { param($Got) if ($null -eq $Got.PSObject.Properties["strays"]) { return "(the store reports no strays)" }; return (@($Got.strays | ForEach-Object { $_.file } | Sort-Object) -join ",") }
$s = New-TestStore
foreach ($i in 1..5) { $null = Add-Safely $s $i ('{"n":' + $i + '}') }
[System.IO.File]::WriteAllText((Join-Path $s "0000002000.json"), '{"n":2000}', $utf8)
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$got = Get-Safely $s
$sw.Stop()
Check ($got.state -ceq "ok" -and $got.last -eq 5 -and (Kinds $got) -ceq "ok,ok,ok,ok,ok") ("with 0000002000.json beside records 1 to 5, the order still ends at 5 (last " + $got.last + ", " + @($got.records).Count + " entries)")
Check ((Get-Strays $got) -ceq "0000002000.json") ("and that file is reported as a stray, by name (" + (Get-Strays $got) + ")")
Check ($sw.ElapsedMilliseconds -lt 3000) ("the read did not walk to it (" + $sw.ElapsedMilliseconds + " ms)")
[System.IO.File]::WriteAllText((Join-Path $s "9999999999.json"), '{"n":9999999999}', $utf8)
[System.IO.File]::WriteAllText((Join-Path $s "00000000099.json"), '{"n":99}', $utf8)
[System.IO.File]::WriteAllText((Join-Path $s "000000009.json"), '{"n":9}', $utf8)
[System.IO.File]::WriteAllText((Join-Path $s "0000000000.json"), '{"n":0}', $utf8)
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$got = Get-Safely $s
$sw.Stop()
Check ($got.last -eq 5 -and (Kinds $got) -ceq "ok,ok,ok,ok,ok" -and $sw.ElapsedMilliseconds -lt 3000) ("the largest name there is, a name of eleven digits, one of nine and record zero change nothing either, and quickly (last " + $got.last + ", " + $sw.ElapsedMilliseconds + " ms)")
Check ((Get-Strays $got) -ceq "0000000000.json,00000000099.json,000000009.json,0000002000.json,9999999999.json") ("each is a stray, by name (" + (Get-Strays $got) + ")")
Check (@($got.strays | Where-Object { "$($_.reason)".Trim() -eq "" }).Count -eq 0 -and "$(@($got.strays | Where-Object { $_.file -ceq '0000002000.json' })[0].reason)" -like "*1994 places past record 5*") "every stray says why, and the far one says how far"
Check ((Add-Safely $s 6 '{"n":6}') -ceq "created" -and (Get-Safely $s).last -eq 6) "and the next record is 6: writing goes on from the end of the order"
# A record listed and then gone before it is read (deleted in between) reads as missing, not as an
# error: asked of the reader itself, since a gap is now found from the names and not by reading.
$gone = "THREW"
try { $gone = (Read-HordeDecisionRecordFile -Path (Join-Path $s "0000000077.json")).kind } catch { }
Check ($gone -ceq "missing") ("a record file that is not there reads as missing (" + $gone + ")")
# THE LIMIT, on both sides: 100 missing records in a row are believed, 101 are not.
$s = New-TestStore
foreach ($i in 1..2) { $null = Add-Safely $s $i ('{"n":' + $i + '}') }
$null = Add-Safely $s 103 '{"n":103}'
$got = Get-Safely $s
Check ($got.last -eq 103 -and (Kinds $got) -ceq "ok,ok,missing,ok" -and (Get-Strays $got) -ceq "") ("a record 100 places past the last is a record, after a gap (" + (Kinds $got) + ", last " + $got.last + ")")
Check ($got.records[2].sequence -eq 3 -and $got.records[2].span -eq 100 -and $got.records[2].file -ceq "0000000003.json" -and $got.records[2].reason -like "*records 3 to 102 (100 of them)*") "the gap is ONE entry: from 3, a hundred long, saying from where to where"
Check ($got.records[0].span -eq 1 -and $got.records[3].span -eq 1 -and $got.records[3].sequence -eq 103) "CONTROL: a record covers one number"
$s = New-TestStore
foreach ($i in 1..2) { $null = Add-Safely $s $i ('{"n":' + $i + '}') }
$null = Add-Safely $s 104 '{"n":104}'
$null = Add-Safely $s 105 '{"n":105}'
$got = Get-Safely $s
Check ($got.last -eq 2 -and (Kinds $got) -ceq "ok,ok" -and (Get-Strays $got) -ceq "0000000104.json,0000000105.json") ("a file 101 places past the last is a stray, and so is the one after it (last " + $got.last + "; strays " + (Get-Strays $got) + ")")

Write-Host ""
Write-Host "--- text is kept byte for byte ---" -ForegroundColor Cyan
$s = New-TestStore
# Hebrew, written as escapes so this file stays ASCII (CONTRIBUTING 13): shin, lamed, vav, final mem.
$hebrew = "" + [char]0x05E9 + [char]0x05DC + [char]0x05D5 + [char]0x05DD
$long = ("word " * 20000)
$text = '{"title":"' + $hebrew + '","body":"' + $long + '"}'
Check ($long.Length -eq 100000) "CONTROL: the long text is 100,000 characters"
Check ((Add-Safely $s 1 $text) -ceq "created") "a record holding Hebrew and a 100,000-character text is created"
$onDisk = [System.IO.File]::ReadAllBytes((Join-Path $s "0000000001.json"))
Check ([System.Convert]::ToBase64String($onDisk) -ceq [System.Convert]::ToBase64String($utf8.GetBytes($text))) "the file is exactly the text in UTF-8, with no byte-order mark and nothing cut"
$got = Get-Safely $s
Check ((Kinds $got) -ceq "ok" -and [string]::Equals($got.records[0].data.title, $hebrew, [System.StringComparison]::Ordinal)) "the Hebrew reads back character for character"
Check ($got.records[0].data.body.Length -eq 100000 -and [string]::Equals($got.records[0].data.body, $long, [System.StringComparison]::Ordinal)) "and all 100,000 characters read back"

Write-Host ""
Write-Host "--- a writer leaves nothing but its record, and what a dead writer left is swept ---" -ForegroundColor Cyan
# The record is written whole under a temporary name and moved to its own (decisions/Store.ps1 says why,
# with the measurement). These checks are on what is left in the folder; a writer really killed mid-write
# is test/test-decisions-store-race.ps1's.
function Get-Names { param([string]$Store) return (@(Get-ChildItem -LiteralPath $Store -Force | Sort-Object Name | ForEach-Object { $_.Name }) -join ",") }
$s = New-TestStore
$null = Add-Safely $s 1 '{"n":1}'
Check ((Get-Names $s) -ceq "0000000001.json") ("after a create the folder holds the record and nothing else (" + (Get-Names $s) + ")")
$null = Add-Safely $s 1 '{"n":1,"who":"second"}'
Check ((Get-Names $s) -ceq "0000000001.json") ("after a create that was told exists, the loser's temporary file is gone (" + (Get-Names $s) + ")")
# What a dead writer leaves: a temporary file of the store's own pattern, last written long ago.
$stale = Join-Path $s ("writing-" + ("a" * 32) + ".part")
$fresh = Join-Path $s ("writing-" + ("b" * 32) + ".part")
$notOurs = @("writing-notes.part", ("writing-" + ("c" * 32) + ".part.bak"), ("x-writing-" + ("d" * 32) + ".part"), "notes.txt")
foreach ($f in (@($stale, $fresh) + @($notOurs | ForEach-Object { Join-Path $s $_ }))) { [System.IO.File]::WriteAllText($f, '{"half":', $utf8) }
$longAgo = [datetime]::UtcNow.AddDays(-400)
foreach ($f in (@($stale, (Join-Path $s "0000000001.json")) + @($notOurs | ForEach-Object { Join-Path $s $_ }))) { [System.IO.File]::SetLastWriteTimeUtc($f, $longAgo) }
$got = Get-Safely $s
Check ((Kinds $got) -ceq "ok" -and $got.last -eq 1) ("a temporary file is never read as a record: the store is still record 1 (" + (Kinds $got) + ")")
Check (Test-Path -LiteralPath $stale) "CONTROL: reading removes nothing"
Check ((Add-Safely $s 2 '{"n":2}') -ceq "created") "the next write is made"
Check (-not (Test-Path -LiteralPath $stale)) "and it swept the temporary file a dead writer left long ago"
Check (Test-Path -LiteralPath $fresh) "a temporary file written a moment ago is left: its writer may be alive"
Check (Test-Path -LiteralPath (Join-Path $s "0000000001.json")) "a RECORD is never swept, however old it is"
Check (@($notOurs | Where-Object { -not (Test-Path -LiteralPath (Join-Path $s $_)) }).Count -eq 0) "nor is any file whose name is not exactly the store's own temporary pattern"
# THE AGE, on both sides (the setting decisions.store.leftoverMinAgeSeconds, ten minutes): nine minutes
# on it is left, eleven minutes on it is swept.
$removedNow = -1
try { $removedNow = Remove-HordeDecisionStoreLeftovers -Root $s -Now ([datetime]::UtcNow.AddMinutes(9)) } catch { $removedNow = -2 }
Check ($removedNow -eq 0 -and (Test-Path -LiteralPath $fresh)) ("nine minutes on, that file is still under the age and is left (" + $removedNow + " removed)")
$removedNow = -1
try { $removedNow = Remove-HordeDecisionStoreLeftovers -Root $s -Now ([datetime]::UtcNow.AddMinutes(11)) } catch { $removedNow = -2 }
Check ($removedNow -eq 1 -and -not (Test-Path -LiteralPath $fresh)) ("eleven minutes on, that file is past the age and is swept too (" + $removedNow + " removed)")
$removedNow = -1
try { $removedNow = Remove-HordeDecisionStoreLeftovers -Root (New-TestStore) } catch { $removedNow = -2 }
Check ($removedNow -eq 0) "sweeping a store that does not exist removes nothing and does not throw"

Write-Host ""
Write-Host "--- THE SWEEP'S INVARIANT: a file some process holds open is never removed, whatever its age ---" -ForegroundColor Cyan
# The invariant, as decisions/Store.ps1 states it: the sweep removes a file only when (1) its name is
# the store's own temporary pattern, (2) it is older than the age, AND (3) NO PROCESS HOLDS IT OPEN. A
# writer holds its file open from the moment it exists until it has its record's name, so (3) is
# "its writer is dead" - with no clock in it. Age alone is not that: a writer suspended for an hour,
# or a machine put to sleep between a write and its move, is alive and old.
# Before this was the rule the sweep went by age alone, and removed all three of the held files below.
$s = New-TestStore
$null = Add-Safely $s 1 '{"n":1}'
$veryOld = [datetime]::UtcNow.AddDays(-400)
$farAhead = [datetime]::UtcNow.AddDays(400)
function New-Leftover { param([string]$Store, [string]$Letter) $path = Join-Path $Store ("writing-" + ($Letter * 32) + ".part"); [System.IO.File]::WriteAllText($path, '{"whole":"record"}', $utf8); [System.IO.File]::SetLastWriteTimeUtc($path, $veryOld); return $path }
function Test-Named { param([string]$Path) return (@(Get-ChildItem -LiteralPath (Split-Path -Parent $Path) -Force | Where-Object { $_.Name -ceq (Split-Path -Leaf $Path) }).Count -eq 1) }
function Invoke-Sweep { param([string]$Store) try { return (Remove-HordeDecisionStoreLeftovers -Root $Store -Now $farAhead) } catch { return -2 } }
# (a) held the way the store's own writer holds its file: for writing, sharing only delete.
$asWriter = New-Leftover $s "a"
$writerHandle = New-Object System.IO.FileStream($asWriter, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Delete)
# (b) held by a process that shares everything, as a scanner or a backup does.
$asScanner = New-Leftover $s "b"
$scannerHandle = New-Object System.IO.FileStream($asScanner, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
# (c) held by a reader that shares reading only.
$asReader = New-Leftover $s "c"
$readerHandle = New-Object System.IO.FileStream($asReader, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
# (d) held by nobody: its writer is dead.
$asDead = New-Leftover $s "d"
try {
    $swept = Invoke-Sweep $s
    Check ($swept -eq 1) ("of four leftovers 400 days old, the sweep removes exactly the one nobody holds (" + $swept + " removed)")
    Check (-not (Test-Named $asDead)) "the leftover of a dead writer is gone"
    # Test-Named lists the folder: a file whose delete is only pending still answers File.Exists with
    # false, and a sweep that marked a live writer's file for deletion must be seen here.
    Check ((Test-Named $asWriter) -and [System.IO.File]::Exists($asWriter)) "a leftover held as a writer holds it is still there, 400 days old or not"
    Check ((Test-Named $asScanner) -and [System.IO.File]::Exists($asScanner)) "so is one held by a process that shares everything, delete included"
    Check ((Test-Named $asReader) -and [System.IO.File]::Exists($asReader)) "and one held by a reader"
    # The live writer can still do the one thing it is alive to do: give its file its record's name.
    $moved = "THREW"
    try { $moved = Move-HordeFileNewDurable -From $asWriter -To (Join-Path $s "0000000002.json") -Open $writerHandle } catch { $moved = "THREW: " + $_.Exception.Message }
    Check ($moved -ceq "moved") ("and the writer whose file the sweep passed over can still move it into place (" + $moved + ")")
} finally { $writerHandle.Dispose(); $scannerHandle.Dispose(); $readerHandle.Dispose() }
$got = Get-Safely $s
Check ((Kinds $got) -ceq "ok,ok" -and "$($got.records[1].data.whole)" -ceq "record") ("that record is in the store, whole: the sweep did not cost a live writer its record (" + (Kinds $got) + ")")
$swept = Invoke-Sweep $s
Check ($swept -eq 2 -and -not (Test-Named $asScanner) -and -not (Test-Named $asReader)) ("CONTROL: once let go, the other two are leftovers like any other and are swept (" + $swept + " removed)")
Check ((Get-Names $s) -ceq "0000000001.json,0000000002.json") ("and the records are untouched: a record is never a candidate, at any age (" + (Get-Names $s) + ")")

Write-Host ""
Write-Host "--- THE ORDER OF A WRITE: whole and on disk, then named by a durable move, and only then 'created' ---" -ForegroundColor Cyan
# The store's one move is core/FileAtomic.ps1's Move-HordeFileNewDurable. Here that function is
# replaced by one that looks at the world at the moment it is called, then makes the real move (or
# answers as the test says), so each step of the order is seen and not assumed. No test can cut the
# power: what is proven is the ORDER and what each step was handed, not that a disk keeps its word.
$realMove = ${function:Move-HordeFileNewDurable}
$script:seen = New-Object System.Collections.ArrayList
$script:moveAnswer = "real"
function Move-HordeFileNewDurable {
    param([string]$From, [string]$To, $Open = $null, $OsPlatform = $null)
    $at = [ordered]@{ from = $From; to = $To; fromLeaf = (Split-Path -Leaf $From); open = $Open; length = [long]-1; position = [long]-1; canWrite = $false; toThere = [System.IO.File]::Exists($To); sweptWhileHeld = -9; stillNamed = $false }
    try { $at.length = (New-Object System.IO.FileInfo($From)).Length } catch { }
    if ($Open -is [System.IO.FileStream]) { $at.position = $Open.Position; $at.canWrite = $Open.CanWrite }
    # A sweep run by anyone at this moment, however far its clock has run on, must not take the file.
    try { $at.sweptWhileHeld = Remove-HordeDecisionStoreLeftovers -Root (Split-Path -Parent $From) -Now ([datetime]::UtcNow.AddDays(400)) } catch { $at.sweptWhileHeld = -2 }
    $at.stillNamed = (@(Get-ChildItem -LiteralPath (Split-Path -Parent $From) -Force | Where-Object { $_.Name -ceq (Split-Path -Leaf $From) }).Count -eq 1)
    [void]$script:seen.Add([pscustomobject]$at)
    if ($script:moveAnswer -ceq "real") { return (& $realMove -From $From -To $To -Open $Open) }
    if ($script:moveAnswer -ceq "unconfirmed") { $null = & $realMove -From $From -To $To -Open $Open; return "unconfirmed" }
    if ($script:moveAnswer -ceq "throws") { throw "the move failed" }
    return $script:moveAnswer
}
try {
    $s = New-TestStore
    $text = '{"n":1,"body":"' + ("word " * 200) + '"}'
    $made = Add-Safely $s 1 $text
    Check ($made -ceq "created" -and $script:seen.Count -eq 1) ("a create makes exactly one move, through the durable move and nothing else (" + $made + ", " + $script:seen.Count + " move(s))")
    $m = $null; if ($script:seen.Count -ge 1) { $m = $script:seen[0] }
    Check ($null -ne $m -and $m.fromLeaf -cmatch '\Awriting-[0-9a-f]{32}\.part\z' -and $m.to -ceq (Join-Path $s "0000000001.json") -and -not $m.toThere) "it moves the store's own temporary file to the record's name, which nothing had"
    Check ($null -ne $m -and $m.length -eq $utf8.GetByteCount($text)) ("the WHOLE record was in that file before the move began (" + $(if ($null -ne $m) { $m.length } else { "no move" }) + " of " + $utf8.GetByteCount($text) + " bytes)")
    Check ($null -ne $m -and $m.open -is [System.IO.FileStream] -and $m.canWrite -and $m.position -eq $utf8.GetByteCount($text)) "the writer STILL HOLDS the file open, at its end, and hands that handle to the move to be flushed after it"
    Check ($null -ne $m -and $m.sweptWhileHeld -eq 0 -and $m.stillNamed) ("a sweep run at that very moment, 400 days ahead by its clock, takes nothing: the file is its live writer's (" + $(if ($null -ne $m) { $m.sweptWhileHeld } else { "no move" }) + " removed)")
    Check ([System.IO.File]::ReadAllText((Join-Path $s "0000000001.json")) -ceq $text -and (Get-Names $s) -ceq "0000000001.json") "CONTROL: after it the record reads back exactly, and nothing else is in the folder"
    # "created" is said only for "moved". Each other answer of the move:
    $script:seen.Clear(); $script:moveAnswer = "unconfirmed"
    $made = Add-Safely $s 2 '{"n":2}'
    Check ($made -ceq "unconfirmed") ("when the move could not be confirmed on disk the store says unconfirmed, never created (" + $made + ")")
    Check ((Get-Names $s) -ceq "0000000001.json,0000000002.json") "the record does have its name then, which is why this is not 'nothing was written' either"
    $script:seen.Clear(); $script:moveAnswer = "throws"
    $made = Add-Safely $s 3 '{"n":3}'
    Check ($made -like "THREW:*the move failed*" -and (Get-Names $s) -ceq "0000000001.json,0000000002.json") ("a move that fails is a failed write, and the writer's temporary file is gone with it (" + (Get-Names $s) + ")")
    $script:seen.Clear(); $script:moveAnswer = "exists"
    $made = Add-Safely $s 3 '{"n":3}'
    Check ($made -like "THREW:*" -and (Get-Names $s) -ceq "0000000001.json,0000000002.json") ("'exists' for a name no RECORD has is a failed write, not 'another writer took it' (" + $made + ")")
    $script:seen.Clear(); $script:moveAnswer = "moved"
    $made = Add-Safely $s 3 '{"n":3}'
    Check ($made -ceq "created" -and -not (Test-Path -LiteralPath (Join-Path $s "0000000003.json"))) ("CONTROL: the store believes the move's answer, here a 'moved' that moved nothing - which is why the move is one small function to get right (" + $made + ")")
} finally {
    Remove-Item -LiteralPath function:Move-HordeFileNewDurable
    . (Join-Path $root "core\FileAtomic.ps1")
}
$s = New-TestStore
Check ((Add-Safely $s 1 '{"n":1}') -ceq "created" -and (Get-Names $s) -ceq "0000000001.json") "CONTROL: the real move is back in place for the rest of the suite"
# Text that cannot be written as UTF-8 (a lone surrogate) must leave nothing behind, not an empty record.
$s = New-TestStore
$null = Add-Safely $s 1 '{"n":1}'
$unwritable = Add-Safely $s 2 ('{"t":"' + [char]0xD800 + '"}')
Check ($unwritable -like "THREW:*" -and (Get-Names $s) -ceq "0000000001.json") ("text that is not valid Unicode throws and leaves no file of any name (" + (Get-Names $s) + ")")
# A folder where the record's file must go is not "another writer took it".
New-Item -ItemType Directory -Path (Join-Path $s "0000000002.json") | Out-Null
Check ((Add-Safely $s 2 '{"n":2}') -like "THREW:*") "a folder of the record's name is a failure to write, not 'exists'"
Check (@(Get-ChildItem -LiteralPath $s -Filter "*.part").Count -eq 0) "and the temporary file of that failed write is gone"

Write-Host ""
Write-Host "--- an existing record is confirmed on disk, and not changed ---" -ForegroundColor Cyan
$s = New-TestStore
$null = Add-Safely $s 1 '{"n":1}'
$null = Add-Safely $s 2 '{"n":2,"body":"the one to confirm"}'
$twoBefore = Base64 (Join-Path $s "0000000002.json")
$realFlush = ${function:Confirm-HordeFileFlushed}
$script:flushed = New-Object System.Collections.ArrayList
function Confirm-HordeFileFlushed { param($Open) if ($Open -is [System.IO.FileStream]) { [void]$script:flushed.Add([System.IO.Path]::GetFileName($Open.Name)) }; return (& $realFlush -Open $Open) }
try {
    $sure = "THREW"
    try { $sure = Confirm-HordeDecisionRecord -Root $s -Sequence 2 } catch { $sure = "THREW: " + $_.Exception.Message }
    Check ($sure -ceq "confirmed" -and ($script:flushed -join ",") -ceq "0000000002.json") ("confirming record 2 flushes record 2, and only it, through core's one flush path (" + $sure + "; flushed: " + ($script:flushed -join ",") + ")")
} finally { Remove-Item -LiteralPath function:Confirm-HordeFileFlushed; . (Join-Path $root "core\FileAtomic.ps1") }
Check ((Base64 (Join-Path $s "0000000002.json")) -ceq $twoBefore -and (Get-Names $s) -ceq "0000000001.json,0000000002.json") "and the record's bytes are untouched, and nothing else is in the folder"
$gone = "THREW"
try { $gone = Confirm-HordeDecisionRecord -Root $s -Sequence 3 } catch { $gone = "THREW: " + $_.Exception.Message }
Check ($gone -ceq "missing" -and (Get-Names $s) -ceq "0000000001.json,0000000002.json") ("a record that is not there is missing, and confirming did not make it (" + $gone + ")")

Write-Host ""
Write-Host "--- the store has no way to rewrite or delete a record ---" -ForegroundColor Cyan
# Read from the syntax tree: a record that could be rewritten is not a write-once record, whatever the
# tests above saw today. The store may move and delete exactly these: its temporary file to the record's
# name, and its own temporary files. CONTROL: the same search finds the calls the file must have.
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root "decisions\Store.ps1"), [ref]$tokens, [ref]$errors)
$members = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.MemberExpressionAst] }, $true) | ForEach-Object { "$($_.Member)" })
$calls = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true) | ForEach-Object { "$($_.Member)(" + (@($_.Arguments | ForEach-Object { "$_" }) -join ", ") + ")" })
$commands = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { "$($_.GetCommandName())" })
$forbiddenMembers = @($members | Where-Object { @("Replace", "Copy", "WriteAllText", "WriteAllBytes", "WriteAllLines", "AppendAllText", "Create", "OpenOrCreate", "Truncate", "Append", "SetLength") -ccontains $_ })
$forbiddenCommands = @($commands | Where-Object { @("Remove-Item", "Set-Content", "Add-Content", "Out-File", "Move-Item", "Rename-Item", "Clear-Content", "Copy-Item") -contains $_ })
$moves = @($calls | Where-Object { $_ -clike "Move(*" })
$deletes = @($calls | Where-Object { $_ -clike "Delete(*" })
$opensForWriting = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { "$_" } | Where-Object { $_ -clike "*FileAccess]::Write*" -or $_ -clike "*FileAccess]::ReadWrite*" })
$durableMoves = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and "$($node.GetCommandName())" -ceq "Move-HordeFileNewDurable" }, $true) | ForEach-Object { "$_" })
Check (@($errors).Count -eq 0 -and ($members -ccontains "CreateNew") -and $durableMoves.Count -ge 1 -and $deletes.Count -ge 1) "CONTROL: the store file parses, and the search sees its CreateNew, its move and a delete"
Check ($forbiddenMembers.Count -eq 0) ("no call in the store can overwrite, copy over, truncate or append to a file" + $(if ($forbiddenMembers.Count) { " (found: " + ($forbiddenMembers -join ", ") + ")" } else { "" }))
Check ($forbiddenCommands.Count -eq 0) ("and no cmdlet in it can either" + $(if ($forbiddenCommands.Count) { " (found: " + ($forbiddenCommands -join ", ") + ")" } else { "" }))
$confirms = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and "$($node.GetCommandName())" -ceq "Confirm-HordeFileDurable" }, $true) | ForEach-Object { "$_" })
Check ($confirms.Count -eq 1) ("an existing record is confirmed on disk by core's function and by nothing of the store's own (" + $confirms.Count + ")")
Check ($moves.Count -eq 0) ("the store makes no move of its own: File.Move is not written through (" + ($moves -join " | ") + ")")
Check (($durableMoves -join " | ") -ceq 'Move-HordeFileNewDurable -From $tmpPath -To $recPath -Open $fs') ("its one move is the durable one, of the temporary file to the record's name, handed the writer's open handle (" + ($durableMoves -join " | ") + ")")
Check (($deletes -join " | ") -ceq 'Delete($tmpPath)') ("the only delete by name is of the writer's own temporary file (" + ($deletes -join " | ") + ")")
Check ($opensForWriting.Count -eq 1 -and $opensForWriting[0] -clike 'New-Object System.IO.FileStream($tmpPath,*CreateNew*FileShare]::Delete,*') ("the one file opened for writing is the temporary one, created new, sharing only delete so that it can be renamed while held (" + $opensForWriting.Count + ")")
$claims = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { "$_" } | Where-Object { $_ -clike "*DeleteOnClose*" })
Check ($claims.Count -eq 1 -and $claims[0] -clike 'New-Object System.IO.FileStream($leftover,*FileMode]::Open,*FileShare]::None,*DeleteOnClose*') ("a leftover is removed one way only: opened with no sharing at all, to be deleted when that handle closes (" + $claims.Count + ")")

} finally {
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-decisions-store-test-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the suite's temp folder is removed"

Complete-HordeSuite -Success "the decisions store takes each sequence number once, and hands back every record, damaged ones marked"
