# DOES THE FILES STORE KEEP EVERY SHARE ONCE, WHOLE, AND REFUSE WHAT MUST NOT BE SHARED?
#
# files/Store.ps1, files/Share.ps1 and files/Settings.ps1, in this process. The suite attacks the rules:
#   - an entry is put in place once: a second write of a name is told "exists" and changes no byte;
#   - a share is refused, with nothing written, for a missing file, a folder, a link (the file, or a
#     folder on the way to it), a type not on the list, a picture or PDF whose first bytes are not
#     its format's, an SVG, and a file one byte over the cap - while the cap itself passes;
#   - text is text: every way bytes can fail to be UTF-8, a NUL, UTF-16 with and without its mark, a
#     picture under each text name, and 50 texts a lenient parser calls JSON, are each refused;
#   - a file id is made with a key only this machine has: it is made once, readable by the user
#     alone, in no record; and a key that is gone or damaged refuses the share and is never remade;
#   - one file has one id however it is named - the long-path prefix, its 8.3 short name, another
#     case - and that id is the same number under every runtime; a device or a stream inside a
#     file is refused;
#   - a network path in every spelling, this machine's own drive share among them, and a file on a
#     network drive are refused BEFORE anything asks the disk or the network about them;
#   - the same path from the same session is the next version of the same file; the same bytes under
#     two titles are kept once; a share made outside any session says so and names nobody;
#   - a record that is damaged, a link, or not what its name says is listed as unreadable, never as
#     a share, and never makes the list unreadable.
# Processes racing for one version, and a share killed part-way, are test/test-files-race.ps1; the
# real `horde files` command is test/test-files-cli.ps1.
#
# Every store here is a fresh folder under %TEMP% that this suite made and removes (CONTRIBUTING 9),
# and the home every call is given is that folder: the real home is never read.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "files\Share.ps1")

$script:work = Join-Path $env:TEMP ("horde-files-store-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
# THE SUITE STANDS IN ITS OWN FOLDER. Two checks hand the store a relative folder, which must be
# refused; a store that wrongly took one would write where the process stands, and under mutation
# that was the repository (measured 2026-10-13: the mutant that drops the refusal left relative\store
# in the tree it was run from). Standing here, even that lands in the folder this suite removes.
[System.IO.Directory]::SetCurrentDirectory($script:work)
Set-Location -LiteralPath $script:work
# Whatever a function here is not handed, it must not find the real home.
$env:HORDE_HOME = Join-Path $script:work "home-nobody-uses"
$script:n = 0
$sessA = New-HordeKnown -Value "session-a"
$sessB = New-HordeKnown -Value "session-b"
$noSession = New-HordeUnknown -Reason "this suite names no session"

function New-TestHome {
    # The path of a home nothing has made yet, inside this suite's own folder.
    $script:n++
    return (Join-Path $script:work ("home-" + $script:n))
}
function Get-StoreOf { param([string]$TestHome) return (Join-Path $TestHome "store\files") }
function Get-Names {
    # Every name in a store folder, sorted, joined; "" when there is no folder.
    param([string]$Store)
    if (-not (Test-Path -LiteralPath $Store)) { return "" }
    return (@(Get-ChildItem -LiteralPath $Store -Force | Sort-Object Name | ForEach-Object { $_.Name }) -join ",")
}
function New-Source {
    # A file to share, in a folder of its own beside the homes: -Bytes, or -Text as UTF-8.
    param([string]$Name, [byte[]]$Bytes = $null, [string]$Text = "")
    $folder = Join-Path $script:work "sources"
    [void][System.IO.Directory]::CreateDirectory($folder)
    $path = Join-Path $folder $Name
    $content = $Bytes
    if ($null -eq $content) { $content = [System.Text.Encoding]::UTF8.GetBytes($Text) }
    [System.IO.File]::WriteAllBytes($path, $content)
    return $path
}
function Get-Padded {
    # -Head followed by zero bytes, -Length bytes in all.
    param([byte[]]$Head, [int]$Length)
    $out = New-Object byte[] $Length
    [Array]::Copy($Head, $out, $Head.Length)
    return ,$out
}
function Invoke-Share {
    param([string]$TestHome, [string]$Path, [string]$Title = "A title", $Asking = $sessA, [switch]$Editable)
    return (Add-HordeFilesShare -Path $Path -Title $Title -Editable:$Editable -HordeHome $TestHome -Asking $Asking)
}
function Get-Safely {
    # A block's value, or "threw: <why>": for a check whose point is that nothing is thrown.
    param([scriptblock]$Block)
    try { return (& $Block) } catch { return ("threw: " + $_.Exception.Message) }
}
function Test-Refused {
    # Was the share refused with a reason like -Like, leaving the store exactly as it was?
    param([string]$TestHome, [string]$Path, [string]$Like, [string]$Title = "A title")
    $before = Get-Names (Get-StoreOf $TestHome)
    # A share that throws was not refused: it is a failed check, said as one, never a vanished one.
    $r = [pscustomobject]@{ outcome = "threw"; reason = "" }
    try { $r = Invoke-Share -TestHome $TestHome -Path $Path -Title $Title } catch { $r.reason = "$($_.Exception.Message)" }
    $same = ((Get-Names (Get-StoreOf $TestHome)) -ceq $before)
    if ($r.outcome -cne "refused" -or $r.reason -notlike ("*" + $Like + "*") -or -not $same) { Write-Host ("         got: " + $r.outcome + " - " + $r.reason + $(if (-not $same) { " - AND THE STORE CHANGED" } else { "" })) -ForegroundColor Red }
    return ($r.outcome -ceq "refused" -and $r.reason -like ("*" + $Like + "*") -and $same)
}

function Get-Filled {
    # -Length bytes of the letter a: text of any size. (Zero bytes are not text: a NUL is refused.)
    param([int]$Length)
    $out = New-Object byte[] $Length
    for ($at = 0; $at -lt $Length; $at++) { $out[$at] = 0x61 }
    return ,$out
}
function Get-RealPath {
    # The path the open handle of a file gives: what a file id is made from. This suite's folder is
    # under %TEMP%, which on some machines is written with an 8.3 short name.
    param([string]$Path)
    $o = Open-HordeFilesSource -Path $Path
    if (-not $o.ok) { throw ("the suite could not open " + $Path + ": " + $o.reason) }
    $o.stream.Dispose()
    return $o.path
}
function Get-Hmac {
    # HMAC-SHA-256 of -Text under -Key, as lower-case hex: this suite's own, not the code's.
    param([byte[]]$Key, [string]$Text)
    $mac = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList (, $Key)
    try { return ([System.BitConverter]::ToString($mac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))).Replace("-", "").ToLowerInvariant()) } finally { $mac.Dispose() }
}
function Get-AsciiLowered {
    # -Text with A to Z made a to z and nothing else touched: this suite's own, written another way
    # than the code's (a pattern over the 26 letters, matched with their case), to check it against.
    param([string]$Text)
    return [regex]::Replace($Text, '[A-Z]', { param($found) [string][char]([int][char]$found.Value + 32) })
}function Write-Skip { param([string]$What) Write-Host ("  [SKIP] " + $What) -ForegroundColor Yellow }

$png = [byte[]]@(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
$jpeg = [byte[]]@(0xFF, 0xD8, 0xFF, 0xE0)
$gif89 = [System.Text.Encoding]::ASCII.GetBytes("GIF89a")
$gif87 = [System.Text.Encoding]::ASCII.GetBytes("GIF87a")
$webp = [byte[]](@(0x52, 0x49, 0x46, 0x46, 0x10, 0x00, 0x00, 0x00) + @(0x57, 0x45, 0x42, 0x50))
$pdf = [System.Text.Encoding]::ASCII.GetBytes("%PDF-1.7")

# NOT ONE try AROUND THE CHECKS. After an error no test expected, the suite's trap resumes at the next
# statement of the script (test/lib/Suite.ps1), and one try around everything is one statement: a
# broken store that threw early would skip every check after it and be seen as a crash, not as a
# failed check (measured 2026-10-13: 8 of 152 mutants were not caught for that reason alone). So the
# sections are plain statements, and the folder is removed by the plain statements at the end.

Write-Host ""
Write-Host "--- the settings: named, with defaults, and an override that is refused whole ---" -ForegroundColor Cyan
$h = New-TestHome
$s = Get-HordeFilesSettings -HordeHome $h
Check ($s.maxFileBytes -eq 1048576) "the cap is 1 MiB (1048576 bytes) by default, under the name maxFileBytes"
Check ($s.maxTitleChars -eq 120 -and $s.versionTries -eq 20 -and $s.leftoverMinAgeSeconds -eq 600 -and $s.heldReadTries -eq 40 -and $s.heldReadWaitMs -eq 50) "the other five settings have their defaults"
Check (-not (Test-Path -LiteralPath $h)) "reading the settings made no home"
[void][System.IO.Directory]::CreateDirectory((Join-Path $h "settings"))
[System.IO.File]::WriteAllText((Join-Path $h "settings\files.json"), '{ "schemaVersion": 1, "settings": { "maxFileBytes": 0 } }')
Check (Throws { Get-HordeFilesSettings -HordeHome $h } "maxFileBytes") "an override outside its range throws, naming the key"
$src = New-Source -Name "plain.md" -Text "# plain"
Check (Throws { Invoke-Share -TestHome $h -Path $src } "is refused") "and a share under a refused settings file throws: it never runs on a default the person did not choose"
Check ((Get-Names (Get-StoreOf $h)) -ceq "") "nothing was written by it"

Write-Host ""
Write-Host "--- the store: an entry is put in place once and never replaced ---" -ForegroundColor Cyan
$st = Get-StoreOf (New-TestHome)
$recName = Get-HordeFilesRecordName -FileId ("ab" * 16) -Version 1
Check ($recName -ceq (("ab" * 16) + ".000001.json")) "a record is named by its file id and its version in six digits"
Check (Throws { Get-HordeFilesRecordName -FileId ("ab" * 16) -Version 0 } "1 to 999999") "version 0 has no name"
Check (Throws { Get-HordeFilesRecordName -FileId ("ab" * 16) -Version 1000000 } "1 to 999999") "nor has version 1000000"
Check (Throws { Get-HordeFilesRecordName -FileId "..\..\x" -Version 1 } "32 lower-case hex") "a file id that is not 32 hex digits has no name"
Check (Throws { Get-HordeFilesBytesName -Sha256 "abc" } "64 lower-case hex") "a digest that is not 64 hex digits has no name"
$first = [System.Text.Encoding]::UTF8.GetBytes('{"n":1}')
Check ((Get-Safely { Add-HordeFilesStoreEntry -Root $st -Name $recName -Bytes $first -LeftoverMinAgeSeconds 600 }) -ceq "created") "the first write of a name is told 'created'"
Check ((Get-Safely { Add-HordeFilesStoreEntry -Root $st -Name $recName -Bytes ([System.Text.Encoding]::UTF8.GetBytes('{"n":2}')) -LeftoverMinAgeSeconds 600 }) -ceq "exists") "a second write of the same name is told 'exists'"
Check ([System.IO.File]::ReadAllText((Join-Path $st $recName)) -ceq '{"n":1}') "and the first entry's bytes are untouched"
Check ((Get-Names $st) -ceq $recName) "the loser left no temporary file"
Check (Throws { Add-HordeFilesStoreEntry -Root $st -Name "..\outside.json" -Bytes $first -LeftoverMinAgeSeconds 600 } "not a name the files store keeps") "a name that is not a record's or bytes' is refused"
Check (Throws { Add-HordeFilesStoreEntry -Root $st -Name "notes.txt" -Bytes $first -LeftoverMinAgeSeconds 600 } "not a name the files store keeps") "so is any other file name"
Check (Throws { Add-HordeFilesStoreEntry -Root "relative\store" -Name $recName -Bytes $first -LeftoverMinAgeSeconds 600 } "absolute folder") "a relative store folder is refused"
$folderName = Get-HordeFilesRecordName -FileId ("cd" * 16) -Version 1
New-Item -ItemType Directory -Path (Join-Path $st $folderName) | Out-Null
Check (Throws { Add-HordeFilesStoreEntry -Root $st -Name $folderName -Bytes $first -LeftoverMinAgeSeconds 600 } "not a file") "a folder standing in an entry's name is an error, not 'exists'"
[System.IO.Directory]::Delete((Join-Path $st $folderName))
Check ((Get-HordeFilesStoreLastVersion -Root $st -FileId ("ab" * 16)) -eq 1 -and (Get-HordeFilesStoreLastVersion -Root $st -FileId ("ef" * 16)) -eq 0) "the last version of a file is read from the names: 1 for the one written, 0 for one never shared"
Check ((Get-Safely { Get-HordeFilesStoreLastVersion -Root (Join-Path $script:work "no-such-store") -FileId ("ab" * 16) }) -eq 0) "and 0 where there is no store"
Check (Throws { Get-HordeFilesStoreLastVersion -Root $st -FileId "*" } "32 lower-case hex") "a file id that is not 32 hex digits is never used to look for names"
# THE ORDER OF A WRITE: the move is handed the writer's own open handle, after the bytes are in the file.
$script:seen = $null
$script:realMove = ${function:Move-HordeFileNewDurable}
function Move-HordeFileNewDurable {
    param([string]$From, [string]$To, $Open = $null, $OsPlatform = $null)
    $held = $false
    try { $probe = New-Object System.IO.FileStream($From, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite); $probe.Dispose() } catch { $held = $true }
    $script:seen = [pscustomobject]@{ open = ($null -ne $Open); length = (New-Object System.IO.FileInfo($From)).Length; held = $held; from = [System.IO.Path]::GetFileName($From) }
    return (& $script:realMove -From $From -To $To -Open $Open)
}
$orderName = Get-HordeFilesRecordName -FileId ("ab" * 16) -Version 2
$null = Add-HordeFilesStoreEntry -Root $st -Name $orderName -Bytes $first -LeftoverMinAgeSeconds 600
Check ($script:seen.open -and $script:seen.length -eq $first.Length) "the move is handed the writer's open handle, with every byte already in the file"
Check ($script:seen.held) "and the writer still holds its file at the move: nothing else can open it for reading"
Check ($script:seen.from -cmatch '\Awriting-[0-9a-f]{32}\.part\z') "the entry is written under a temporary name, never its own"
# WHAT THE STORE SAYS OF EACH ANSWER OF THE MOVE.
function Move-HordeFileNewDurable { param([string]$From, [string]$To, $Open = $null, $OsPlatform = $null) $null = & $script:realMove -From $From -To $To -Open $Open; return "unconfirmed" }
Check ((Add-HordeFilesStoreEntry -Root $st -Name (Get-HordeFilesRecordName -FileId ("ab" * 16) -Version 3) -Bytes $first -LeftoverMinAgeSeconds 600) -ceq "unconfirmed") "a move whose flush failed is told 'unconfirmed', never 'created'"
function Move-HordeFileNewDurable { param([string]$From, [string]$To, $Open = $null, $OsPlatform = $null) return "something-else" }
Check (Throws { Add-HordeFilesStoreEntry -Root $st -Name (Get-HordeFilesRecordName -FileId ("ab" * 16) -Version 4) -Bytes $first -LeftoverMinAgeSeconds 600 } "could not be put in place") "any other answer of the move is an error, never 'created'"
Check (@(Get-ChildItem -LiteralPath $st -Filter "writing-*.part").Count -eq 0) "and the writer's temporary file does not stay"
Set-Item -Path function:Move-HordeFileNewDurable -Value $script:realMove

Write-Host ""
Write-Host "--- the sweep: only this store's own temporary files, old, held by nobody, never a link ---" -ForegroundColor Cyan
$st = Get-StoreOf (New-TestHome)
[void][System.IO.Directory]::CreateDirectory($st)
# Two hours: far past the ten minutes asked below when counted in seconds, and short of it in any larger unit.
$old = [datetime]::UtcNow.AddHours(-2)
function New-Leftover { param([string]$Name, [datetime]$Written) $p = Join-Path $st $Name; [System.IO.File]::WriteAllText($p, "left"); [System.IO.File]::SetLastWriteTimeUtc($p, $Written); return $p }
$dead = New-Leftover ("writing-" + ("1" * 32) + ".part") $old
$young = New-Leftover ("writing-" + ("2" * 32) + ".part") ([datetime]::UtcNow)
$heldPath = New-Leftover ("writing-" + ("3" * 32) + ".part") $old
$notOurs = New-Leftover "writing-notes.part" $old
$keptRecord = New-Leftover (Get-HordeFilesRecordName -FileId ("ab" * 16) -Version 1) $old
$holder = New-Object System.IO.FileStream($heldPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Delete)
try {
    $swept = Remove-HordeFilesStoreLeftovers -Root $st -MinAgeSeconds 600
    Check ($swept -eq 1 -and -not (Test-Path -LiteralPath $dead)) ("a dead writer's old temporary file is removed (" + $swept + " removed)")
    Check (Test-Path -LiteralPath $young) "a young one is kept: its writer may be alive"
    Check (Test-Path -LiteralPath $heldPath) "an old one that a process holds open is kept, however old: its writer is alive"
    Check ((Test-Path -LiteralPath $notOurs) -and (Test-Path -LiteralPath $keptRecord)) "a file that is not named as this store names its temporary files is never a candidate, and nor is a record"
    Check ((Remove-HordeFilesStoreLeftovers -Root $st -MinAgeSeconds 600 -Now ([datetime]::UtcNow.AddDays(400))) -eq 1 -and -not (Test-Path -LiteralPath $young)) "CONTROL: the young one is removed once it is older than the age, so the age is what kept it"
} finally { $holder.Dispose() }
Check ((Remove-HordeFilesStoreLeftovers -Root $st -MinAgeSeconds 600) -eq 1 -and -not (Test-Path -LiteralPath $heldPath)) "CONTROL: once its holder lets go, the held one is removed by the same sweep"
Check ((Get-Safely { Remove-HordeFilesStoreLeftovers -Root (Join-Path $script:work "no-such-store") -MinAgeSeconds 600 }) -eq 0) "a sweep where there is no store removes nothing and does not fail"
# A holder that shares everything, as a reader might: the claim must still be refused while it lives.
$sharedHeld = New-Leftover ("writing-" + ("7" * 32) + ".part") $old
$reader = New-Object System.IO.FileStream($sharedHeld, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
try { Check ((Remove-HordeFilesStoreLeftovers -Root $st -MinAgeSeconds 600) -eq 0 -and (Test-Path -LiteralPath $sharedHeld)) "an old one held by a process that shares everything is kept too: the claim wants the file to itself" } finally { $reader.Dispose() }
# THE NEXT WRITE SWEEPS: the leftover just let go is gone after an entry is added, with the age the write was given.
$null = Add-HordeFilesStoreEntry -Root $st -Name (Get-HordeFilesRecordName -FileId ("ab" * 16) -Version 9) -Bytes ([byte[]]@(0x7B, 0x7D)) -LeftoverMinAgeSeconds 86400
Check (Test-Path -LiteralPath $sharedHeld) "a write given an age of a day leaves a leftover two hours old"
$null = Add-HordeFilesStoreEntry -Root $st -Name (Get-HordeFilesRecordName -FileId ("ab" * 16) -Version 10) -Bytes ([byte[]]@(0x7B, 0x7D)) -LeftoverMinAgeSeconds 600
Check (-not (Test-Path -LiteralPath $sharedHeld)) "and a write given ten minutes removes it: every write sweeps first, with the age it is handed"
# A LINK NAMED LIKE A LEFTOVER: the claim deletes what it opens, and an open by name follows a link.
function New-FileLink { param([string]$Link, [string]$Target) $null = & cmd.exe /c ("mklink `"" + $Link + "`" `"" + $Target + "`" >nul 2>nul"); return ([System.IO.File]::Exists($Link) -and (([System.IO.File]::GetAttributes($Link) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) }
function New-Junction { param([string]$Link, [string]$Target) $null = & cmd.exe /c ("mklink /J `"" + $Link + "`" `"" + $Target + "`" >nul 2>nul"); return ([System.IO.Directory]::Exists($Link) -and (([System.IO.File]::GetAttributes($Link) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) }
$linkLeft = Join-Path $st ("writing-" + ("4" * 32) + ".part")
Check (New-FileLink -Link $linkLeft -Target $keptRecord) "a symbolic link named like a leftover was made in the store, to a record"
$swept = Remove-HordeFilesStoreLeftovers -Root $st -MinAgeSeconds 600 -Now ([datetime]::UtcNow.AddDays(400))
Check ($swept -eq 0 -and (Test-Path -LiteralPath $keptRecord) -and [System.IO.File]::Exists($linkLeft)) ("the sweep takes neither the link nor the record it points at (" + $swept + " removed)")
$viaJunction = Join-Path $script:work "store-through-a-junction"
$realFolder = Get-StoreOf (New-TestHome)
[void][System.IO.Directory]::CreateDirectory($realFolder)
$inReal = Join-Path $realFolder ("writing-" + ("5" * 32) + ".part")
[System.IO.File]::WriteAllText($inReal, "left"); [System.IO.File]::SetLastWriteTimeUtc($inReal, $old)
Check (New-Junction -Link $viaJunction -Target $realFolder) "a junction to a store folder was made"
Check ((Remove-HordeFilesStoreLeftovers -Root $viaJunction -MinAgeSeconds 600) -eq 0 -and (Test-Path -LiteralPath $inReal)) "a store folder that is a junction has nothing claimed in it"
Check ((Remove-HordeFilesStoreLeftovers -Root $realFolder -MinAgeSeconds 600) -eq 1) "CONTROL: the same leftover is removed through the folder's own path"
[System.IO.Directory]::Delete($viaJunction)

Write-Host ""
Write-Host "--- a share: what the record holds, versions, and bytes kept once ---" -ForegroundColor Cyan
$h = New-TestHome
$st = Get-StoreOf $h
$doc = New-Source -Name "report.md" -Text "# first words"
$r1 = Add-HordeFilesShare -Path $doc -Title "  The report  " -HordeHome $h -Asking $sessA -Now ([datetime]"2026-10-01T10:00:00Z")
Check ($r1.outcome -ceq "shared" -and $r1.record.version -eq 1 -and $r1.attempts -eq 1) "a Markdown file is shared as version 1, at the first try"
Check ($r1.record.fileId -cmatch '\A[0-9a-f]{32}\z') "its file id is 32 hex digits"
$sha1 = Get-HordeFilesHex -Bytes ([System.IO.File]::ReadAllBytes($doc))
Check ($sha1 -cmatch '\A[0-9a-f]{64}\z') "a digest is 64 lower-case hex digits"
Check ((Get-HordeFilesHex -Bytes ([System.Text.Encoding]::ASCII.GetBytes("abc"))) -ceq "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") "and is sha256: the digest of 'abc' is the published one"
$onDisk = [System.IO.File]::ReadAllText((Join-Path $st (Get-HordeFilesRecordName -FileId $r1.record.fileId -Version 1))) | ConvertFrom-Json
Check ($onDisk.schemaVersion -eq 1 -and $onDisk.fileId -ceq $r1.record.fileId -and $onDisk.version -eq 1) "the record on disk holds its schema version, file id and version"
Check ($onDisk.title -ceq "The report") "its title, without the blanks around it"
Check ($onDisk.type -ceq "text/markdown" -and $onDisk.size -eq 13 -and $onDisk.sha256 -ceq $sha1) "its type, its size in bytes, and the sha256 of its bytes"
Check ($onDisk.time -ceq "2026-10-01T10:00:00.000Z") "its time, in UTC to the millisecond"
Check ($onDisk.session.known -eq $true -and $onDisk.session.id -ceq "session-a" -and @($onDisk.session.PSObject.Properties).Count -eq 2) "the sharing session's id, and nothing else about it: no label"
Check ($onDisk.editable -eq $false) "and that it is not editable, since nobody said it is"
Check (@($onDisk.PSObject.Properties | ForEach-Object { $_.Name }) -join "," -ceq "schemaVersion,fileId,version,title,type,size,sha256,time,session,editable") "a record holds exactly those ten things: the path is not among them"
Check (([System.IO.File]::ReadAllText((Join-Path $st (Get-HordeFilesRecordName -FileId $r1.record.fileId -Version 1)))) -notlike "*sources*") "and the folder the file came from is nowhere in the record"
$bytesPath = Join-Path $st (Get-HordeFilesBytesName -Sha256 $sha1)
Check ([System.IO.File]::Exists($bytesPath) -and (Get-HordeFilesHex -Bytes ([System.IO.File]::ReadAllBytes($bytesPath))) -ceq $sha1) "the bytes are kept beside the record, under their own sha256, and are those bytes"

[System.IO.File]::WriteAllText($doc, "# second words, longer")
$r2 = Add-HordeFilesShare -Path $doc -Title "The report, again" -Editable -HordeHome $h -Asking $sessA
Check ($r2.outcome -ceq "shared" -and $r2.record.fileId -ceq $r1.record.fileId -and $r2.record.version -eq 2) "sharing the same path again from the same session is version 2 of the SAME file id"
Check ($r2.record.editable -eq $true) "-Editable is recorded as true"
Check ($r2.record.sha256 -cne $sha1 -and [System.IO.File]::Exists((Join-Path $st (Get-HordeFilesBytesName -Sha256 $r2.record.sha256))) -and [System.IO.File]::Exists($bytesPath)) "the new bytes are kept under their own digest, and version 1's bytes are still there"
$upper = Add-HordeFilesShare -Path $doc.ToUpperInvariant() -Title "Same file, other case" -HordeHome $h -Asking $sessA
Check ($upper.outcome -ceq "shared" -and $upper.record.fileId -ceq $r1.record.fileId -and $upper.record.version -eq 3) "the same path written in another case is the same file: version 3"
Push-Location (Split-Path -Parent $doc)
try { $rel = Add-HordeFilesShare -Path ".\report.md" -Title "Same file, relative" -HordeHome $h -Asking $sessA } finally { Pop-Location }
Check ($rel.outcome -ceq "shared" -and $rel.record.fileId -ceq $r1.record.fileId -and $rel.record.version -eq 4) "and so is the same file named by a relative path: version 4"
$other = Add-HordeFilesShare -Path $doc -Title "From another session" -HordeHome $h -Asking $sessB
Check ($other.outcome -ceq "shared" -and $other.record.fileId -cne $r1.record.fileId -and $other.record.version -eq 1) "the same path from ANOTHER session is another file, at version 1"
Check ($other.record.sha256 -ceq $r2.record.sha256 -and @(Get-ChildItem -LiteralPath $st -Filter "*.bytes").Count -eq 2) "and its bytes, the same as version 2's, are not kept a second time (2 bytes files for 5 records)"

$twin = New-Source -Name "twin.txt" -Text "the very same bytes"
$twin2 = New-Source -Name "twin-copy.txt" -Text "the very same bytes"
$h2 = New-TestHome
$t1 = Add-HordeFilesShare -Path $twin -Title "One title" -HordeHome $h2 -Asking $sessA
$t2 = Add-HordeFilesShare -Path $twin2 -Title "Another title" -HordeHome $h2 -Asking $sessA
Check ($t1.outcome -ceq "shared" -and $t2.outcome -ceq "shared" -and $t1.record.fileId -cne $t2.record.fileId) "the same bytes shared under two titles from two paths are two files"
Check ($t1.record.sha256 -ceq $t2.record.sha256 -and @(Get-ChildItem -LiteralPath (Get-StoreOf $h2) -Filter "*.bytes").Count -eq 1 -and @(Get-ChildItem -LiteralPath (Get-StoreOf $h2) -Filter "*.json").Count -eq 2) "whose bytes are stored ONCE: one bytes file, two records"
# -Root names the store folder itself, whatever the home is.
$elsewhere = Join-Path $script:work "a-store-elsewhere"
$e1 = Add-HordeFilesShare -Path $twin -Title "Kept elsewhere" -HordeHome $h2 -Root $elsewhere -Asking $sessA
Check ($e1.outcome -ceq "shared" -and $e1.record.version -eq 1 -and (Get-Names $elsewhere) -ceq ((@(($e1.record.fileId + ".000001.json"), ($e1.record.sha256 + ".bytes")) | Sort-Object) -join ",") -and @(Get-ChildItem -LiteralPath (Get-StoreOf $h2) -Filter "*.json").Count -eq 2) "a share given -Root keeps its record and bytes in that folder, and nothing more in the home's store"
Check (@((Get-HordeFilesList -HordeHome $h2 -Root $elsewhere).rows).Count -eq 1 -and @((Get-HordeFilesList -HordeHome $h2).rows).Count -eq 2) "and the list given -Root reads that folder"
# The bytes file of that name with another length is damage, and nothing is built on it.
$h3 = New-TestHome
[void][System.IO.Directory]::CreateDirectory((Get-StoreOf $h3))
[System.IO.File]::WriteAllText((Join-Path (Get-StoreOf $h3) (Get-HordeFilesBytesName -Sha256 $t1.record.sha256)), "short")
Check (Throws { Add-HordeFilesShare -Path $twin -Title "On damage" -HordeHome $h3 -Asking $sessA } "another length") "bytes already in the store under that digest with another length are damage: the share throws"
Check (@(Get-ChildItem -LiteralPath (Get-StoreOf $h3) -Filter "*.json").Count -eq 0) "and no record is written on them"

Write-Host ""
Write-Host "--- the sharing session: its id, or that there is none ---" -ForegroundColor Cyan
$h = New-TestHome
$none1 = Add-HordeFilesShare -Path $doc -Title "Outside any session" -HordeHome $h -Asking $noSession
Check ($none1.outcome -ceq "shared" -and $none1.record.session.known -eq $false -and $none1.record.session.reason -like "*this suite names no session*") "a share made outside any session records that no session is known, with the reason"
Check (-not $none1.record.session.Contains("id")) "and names no session in its place"
$none2 = Add-HordeFilesShare -Path $doc -Title "Outside again" -HordeHome $h -Asking $noSession
Check ($none2.record.fileId -ceq $none1.record.fileId -and $none2.record.version -eq 2) "the same path shared again outside any session is version 2 of that file"
Check ($none1.record.fileId -cne $r1.record.fileId) "which is not the file a session shared from that path"
$own = Get-HordeFilesSession -Asking (New-HordeAbsent -Note "absent on purpose")
Check ($own.known -eq $false) "an answer that is not a known id is no session, whatever its state"
$fromCore = Get-HordeFilesSession
$coreSays = Get-HordeSelfSessionId
Check (($coreSays.state -ceq "known" -and $fromCore.known -and $fromCore.id -ceq $coreSays.value) -or ($coreSays.state -cne "known" -and -not $fromCore.known)) "asked nothing, the session is the one core names as asking, or none when core names none"
$anyKey = [byte[]](1..32)
Check ((Get-HordeFilesId -Session ([ordered]@{ known = $true; id = "no-session" }) -FullPath "C:\x\a.md" -Key $anyKey) -cne (Get-HordeFilesId -Session ([ordered]@{ known = $false; reason = "r" }) -FullPath "C:\x\a.md" -Key $anyKey)) "a session that happens to be called 'no-session' does not share a file id with no session"

Write-Host ""
Write-Host "--- refusals: each with its reason, and nothing written ---" -ForegroundColor Cyan
$h = New-TestHome
$null = Invoke-Share -TestHome $h -Path $doc
Check (Test-Refused $h (Join-Path $script:work "sources\not-there.md") "there is no file") "a file that is not there is refused"
Check (Test-Refused $h (Join-Path $script:work "sources") "is a folder") "a folder is refused"
Check (Test-Refused $h "" "no file was named") "an empty path is refused"
Check (Test-Refused $h $doc "needs a title" -Title "   ") "a title of blanks is refused"
Check (Test-Refused $h $doc "control character" -Title ("two" + [char]10 + "lines")) "a title with a line break is refused"
Check (Test-Refused $h $doc "the setting maxTitleChars" -Title ("t" * 121)) "a title of 121 characters is refused, naming the setting"
Check ((Invoke-Share -TestHome $h -Path $doc -Title ("t" * 120)).outcome -ceq "shared") "and one of exactly 120 is shared"
Check (Test-Refused $h (New-Source -Name "drawing.svg" -Text "<svg/>") "an SVG file is not shared") "an SVG file is refused by name"
# A name of its own: DRAWING.SVG would be the file drawing.svg above, whose name on disk stays in small
# letters, and the type is read from the name the open handle gives, not from what was typed.
Check (Test-Refused $h (New-Source -Name "SHOUTED.SVG" -Text "<svg/>") "an SVG file is not shared") "whatever the case of its extension"
Check (Test-Refused $h (New-Source -Name "tool.exe" -Text "MZ") "is not one that is shared") "a type that is not on the list is refused, and the reason lists the types"
Check (Test-Refused $h (New-Source -Name "README" -Text "words") "no extension") "a file with no extension is refused"
Check (Test-Refused $h (New-Source -Name "archive.md.zip" -Text "words") "(.zip)") "the type is the LAST extension: report.md.zip is a zip"
$lockedPath = New-Source -Name "held.md" -Text "held"
$lock = New-Object System.IO.FileStream($lockedPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
try { Check (Test-Refused $h $lockedPath "cannot be read") "a file another process holds for itself is refused as unreadable" } finally { $lock.Dispose() }

Write-Host ""
Write-Host "--- the type is the extension AND the first bytes ---" -ForegroundColor Cyan
$cases = @(
    @{ name = "a.png"; good = $png; type = "image/png" }, @{ name = "a.jpg"; good = $jpeg; type = "image/jpeg" }, @{ name = "a.jpeg"; good = $jpeg; type = "image/jpeg" },
    @{ name = "a.gif"; good = $gif89; type = "image/gif" }, @{ name = "b.gif"; good = $gif87; type = "image/gif" }, @{ name = "a.webp"; good = $webp; type = "image/webp" },
    @{ name = "a.pdf"; good = $pdf; type = "application/pdf" })
foreach ($c in $cases) {
    $good = Invoke-Share -TestHome $h -Path (New-Source -Name $c.name -Bytes (Get-Padded -Head $c.good -Length 64))
    Check ($good.outcome -ceq "shared" -and $good.record.type -ceq $c.type) ($c.name + " whose first bytes are its format's is shared as " + $c.type)
    Check (Test-Refused $h (New-Source -Name ("wrong-" + $c.name) -Text "these are words, not a picture") "its first bytes are not that format's") ("a " + [System.IO.Path]::GetExtension($c.name) + " file holding text is refused")
}
Check (Test-Refused $h (New-Source -Name "really-a-jpeg.png" -Bytes (Get-Padded -Head $jpeg -Length 64)) "image/png") "a JPEG named .png is refused: the bytes must be the type the NAME says"
Check (Test-Refused $h (New-Source -Name "cut.png" -Bytes ([byte[]]@(0x89, 0x50, 0x4E, 0x47))) "its first bytes are not that format's") "a .png cut after four bytes of its signature is refused"
Check (Test-Refused $h (New-Source -Name "empty.png" -Bytes ([byte[]]@())) "its first bytes are not that format's") "an empty .png is refused"
Check (Test-Refused $h (New-Source -Name "late.png" -Bytes ([byte[]](@(0x00) + $png))) "its first bytes are not that format's") "a .png whose signature starts at the second byte is refused"
Check (Test-Refused $h (New-Source -Name "riff.webp" -Bytes (Get-Padded -Head ([System.Text.Encoding]::ASCII.GetBytes("RIFF....WAVE")) -Length 64)) "its first bytes are not that format's") "a RIFF file that is not WebP is refused as .webp"
Check (Test-Refused $h (New-Source -Name "old.gif" -Bytes (Get-Padded -Head ([System.Text.Encoding]::ASCII.GetBytes("GIF88a")) -Length 64)) "its first bytes are not that format's") "GIF88a is no GIF"
$textTypes = @(@{ name = "t.txt"; type = "text/plain" }, @{ name = "t.json"; type = "application/json" }, @{ name = "t.html"; type = "text/html" }, @{ name = "t.htm"; type = "text/html" }, @{ name = "T.MD"; type = "text/markdown" })
foreach ($c in $textTypes) { $got = Invoke-Share -TestHome $h -Path (New-Source -Name $c.name -Text "{}"); Check ($got.outcome -ceq "shared" -and $got.record.type -ceq $c.type) ($c.name + " is shared as " + $c.type) }
Check ((Invoke-Share -TestHome $h -Path (New-Source -Name "empty.txt" -Bytes ([byte[]]@()))).outcome -ceq "shared") "an empty text file is shared: text has no signature to fail"

Write-Host ""
Write-Host "--- the cap: exactly the cap passes, one byte more is refused ---" -ForegroundColor Cyan
$h = New-TestHome
$atCap = New-Source -Name "at-cap.txt" -Bytes (Get-Filled 1048576)
$overCap = New-Source -Name "over-cap.txt" -Bytes (Get-Filled 1048577)
$big = Invoke-Share -TestHome $h -Path $atCap
Check ($big.outcome -ceq "shared" -and $big.record.size -eq 1048576) "a file of exactly 1048576 bytes is shared under the default cap"
Check (Test-Refused $h $overCap "1048577 bytes; the largest file that is shared is 1048576 bytes (the setting maxFileBytes)") "a file of 1048577 bytes is refused, with both numbers and the setting's name"
[void][System.IO.Directory]::CreateDirectory((Join-Path $h "settings"))
[System.IO.File]::WriteAllText((Join-Path $h "settings\files.json"), '{ "schemaVersion": 1, "settings": { "maxFileBytes": 100, "maxTitleChars": 5 } }')
Check ((Invoke-Share -TestHome $h -Path (New-Source -Name "hundred.txt" -Bytes (Get-Filled 100)) -Title "Small").outcome -ceq "shared") "with the setting at 100, a file of 100 bytes is shared"
Check (Test-Refused $h (New-Source -Name "hundred-one.txt" -Bytes (Get-Filled 101)) "101 bytes; the largest file that is shared is 100 bytes" -Title "Small") "and one of 101 bytes is refused: the cap is the setting, not a number in the code"
Check (Test-Refused $h $doc "the longest is 5" -Title "Longer") "the title's length is the setting too"

Write-Host ""
Write-Host "--- a link is never followed: the file, or a folder on the way to it ---" -ForegroundColor Cyan
$h = New-TestHome
$target = New-Source -Name "target.md" -Text "the real file"
$linkFile = Join-Path $script:work "sources\link.md"
Check (New-FileLink -Link $linkFile -Target $target) "a symbolic link to a Markdown file was made"
Check (Test-Refused $h $linkFile "is a link") "sharing the link is refused: what would be shared is not what was named"
$realDir = Join-Path $script:work "real-folder"
[void][System.IO.Directory]::CreateDirectory((Join-Path $realDir "inner"))
[System.IO.File]::WriteAllText((Join-Path $realDir "inner\deep.md"), "deep")
$junction = Join-Path $script:work "sources\junction"
Check (New-Junction -Link $junction -Target $realDir) "a junction to another folder was made"
Check (Test-Refused $h (Join-Path $junction "inner\deep.md") "junction' is a link") "a file reached THROUGH a junction is refused, and the reason names the junction"
Check ((Invoke-Share -TestHome $h -Path (Join-Path $realDir "inner\deep.md")).outcome -ceq "shared") "CONTROL: the same file by its own path is shared"
Check ((Find-HordeFilesLink -Path $target) -ceq "") "CONTROL: an ordinary file in ordinary folders has no link on its way"
[System.IO.Directory]::Delete($junction)
[System.IO.File]::Delete($linkFile)

Write-Host ""
Write-Host "--- the list: every version, oldest first, and what cannot be read is said, not shown ---" -ForegroundColor Cyan
$h = New-TestHome
$st = Get-StoreOf $h
$empty = Get-HordeFilesList -HordeHome $h
Check ($empty.state -ceq "absent" -and @($empty.rows).Count -eq 0 -and (Format-HordeFilesList -List $empty) -join "|" -ceq "no files have been shared") "with no store the list is absent, and says no files have been shared"
Check (-not (Test-Path -LiteralPath $h)) "and listing made no folder"
$la = New-Source -Name "list-a.md" -Text "a"
$lb = New-Source -Name "list-b.txt" -Text "bb"
$null = Add-HordeFilesShare -Path $lb -Title "Second in time" -HordeHome $h -Asking $noSession -Now ([datetime]"2026-10-02T00:00:00Z")
$null = Add-HordeFilesShare -Path $la -Title "First in time" -HordeHome $h -Asking $sessA -Now ([datetime]"2026-10-01T00:00:00Z")
$null = Add-HordeFilesShare -Path $la -Title "Third in time" -HordeHome $h -Asking $sessA -Now ([datetime]"2026-10-03T00:00:00Z")
$list = Get-HordeFilesList -HordeHome $h
Check ($list.state -ceq "ok" -and (@($list.rows | ForEach-Object { $_.title }) -join "|") -ceq "First in time|Second in time|Third in time") "three shares are listed oldest first, whatever order their names sort in"
Check ((@($list.rows | ForEach-Object { $_.session }) -join "|") -ceq "session-a|no session|session-a" -and (@($list.rows | ForEach-Object { $_.sessionKnown }) -join "|") -ceq "True|False|True") "each row names the sharing session's id, or the words 'no session'"
Check ((@($list.rows | ForEach-Object { $_.version }) -join "|") -ceq "1|1|2") "and its version"
$lines = @(Format-HordeFilesList -List $list)
Check ($lines.Count -eq 3 -and $lines[0] -ceq ($list.rows[0].fileId + "  v1  text/markdown  1 bytes  session-a  2026-10-01T00:00:00.000Z  First in time")) "a line holds the id, version, type, size, session, time and title"
Check ($lines[1] -like "*  v1  text/plain  2 bytes  no session  2026-10-02T00:00:00.000Z  Second in time") "and says 'no session' where none shared it"
# DAMAGE AND STRANGERS in the store folder.
$goodId = $list.rows[0].fileId
[System.IO.File]::WriteAllText((Join-Path $st (Get-HordeFilesRecordName -FileId ("aa" * 16) -Version 1)), "")
[System.IO.File]::WriteAllText((Join-Path $st (Get-HordeFilesRecordName -FileId ("bb" * 16) -Version 1)), '{"schemaVersion":1,"fileId":')
[System.IO.File]::WriteAllText((Join-Path $st (Get-HordeFilesRecordName -FileId ("cc" * 16) -Version 1)), '[1,2]')
[System.IO.File]::WriteAllBytes((Join-Path $st (Get-HordeFilesRecordName -FileId ("dd" * 16) -Version 1)), [byte[]]@(0x7B, 0x22, 0xFF, 0xFE, 0x22, 0x7D))
$goodText = [System.IO.File]::ReadAllText((Join-Path $st (Get-HordeFilesRecordName -FileId $goodId -Version 1)))
[System.IO.File]::WriteAllText((Join-Path $st (Get-HordeFilesRecordName -FileId ("ee" * 16) -Version 1)), $goodText)
[System.IO.File]::WriteAllText((Join-Path $st (Get-HordeFilesRecordName -FileId $goodId -Version 7)), $goodText)
[System.IO.File]::WriteAllText((Join-Path $st "notes.json"), "{}")
[System.IO.File]::WriteAllText((Join-Path $st (("ff" * 16) + ".000000.json")), $goodText)
[System.IO.File]::WriteAllText((Join-Path $st "readme.txt"), "not looked at")
[System.IO.File]::WriteAllText((Join-Path $st ("x" + (Get-HordeFilesRecordName -FileId $goodId -Version 1))), $goodText)
Check (New-FileLink -Link (Join-Path $st (Get-HordeFilesRecordName -FileId ("ab" * 16) -Version 1)) -Target (Join-Path $st (Get-HordeFilesRecordName -FileId $goodId -Version 1))) "a symbolic link named like a record was made, to a real record"
Check (New-FileLink -Link (Join-Path $st ("writing-" + ("6" * 32) + ".part")) -Target (Join-Path $st "readme.txt")) "and one named like a writer's temporary file"
$list = Get-HordeFilesList -HordeHome $h
$why = @{}; foreach ($u in @($list.unreadable)) { $key = $u.file.Substring(0, 2); if ($u.file.StartsWith($goodId)) { $key = "copy" }; $why[$key] = $u.reason }
Check ($list.state -ceq "ok" -and @($list.rows).Count -eq 3) "with damage beside them, the three real shares are still listed, and only they"
Check (@($list.unreadable).Count -eq 7) ("seven records are named as unreadable (" + @($list.unreadable).Count + ")")
Check ($why["aa"] -like "*empty*") "an empty record is said to be empty"
Check ($why["bb"] -like "*not complete JSON*") "cut JSON is said to be incomplete"
Check ($why["cc"] -like "*not a JSON object*") "JSON that is not an object is said so"
Check ($why["dd"] -like "*could not be read*") "bytes that are not UTF-8 are an error, never other letters"
Check ($why["ee"] -like "*fileId is not the one in its name*") "a copy of a real record under another file id is refused: its words do not agree with its name"
Check ($why["copy"] -like "*version is not the one in its name*") "and so is a copy under another version"
Check ($why["ab"] -like "*is a link*") "a link named like a record is not read through"
Check ((@($list.strays | ForEach-Object { $_.file } | Sort-Object) -join "|") -ceq (("ff" * 16) + ".000000.json|notes.json|writing-" + ("6" * 32) + ".part|x" + $goodId + ".000001.json")) "version 0, a .json that is no record, a record's name with a letter before it, and the link named like a temporary file are strays; readme.txt is not looked at"
$lines = @(Format-HordeFilesList -List $list)
Check (@($lines | Where-Object { $_ -like "unreadable record *" }).Count -eq 7 -and @($lines | Where-Object { $_ -like "not a record: *" }).Count -eq 4 -and $lines.Count -eq 14) "the printed list has a line for each of them after the three shares"
Check ((Get-HordeFilesStoreLastVersion -Root $st -FileId $goodId) -eq 7) "a damaged version still counts: the next share of that file is version 8, and 7 is never given twice"
$next = Add-HordeFilesShare -Path $la -Title "After damage" -HordeHome $h -Asking $sessA
Check ($next.outcome -ceq "shared" -and $next.record.version -eq 8) "and it is"
# EVERY FIELD OF A RECORD IS CHECKED: one changed at a time in a good record, each must be refused.
$base = $goodText | ConvertFrom-Json
function Test-Field {
    param([scriptblock]$Change, [string]$Like)
    $copy = $goodText | ConvertFrom-Json
    & $Change $copy
    $problem = "threw"
    try { $problem = Get-HordeFilesRecordProblem -Entry ([pscustomobject]@{ fileId = $goodId; version = 1; file = "x"; kind = "ok"; data = $copy; reason = "" }) } catch { $problem = "threw: " + $_.Exception.Message }
    if ($problem -notlike ("*" + $Like + "*")) { Write-Host ("         got: '" + $problem + "'") -ForegroundColor Red }
    return ($problem -like ("*" + $Like + "*"))
}
Check ((Get-HordeFilesRecordProblem -Entry ([pscustomobject]@{ fileId = $goodId; version = 1; file = "x"; kind = "ok"; data = $base; reason = "" })) -ceq "") "CONTROL: the good record has no problem"
Check (Test-Field { param($d) $d.schemaVersion = 2 } "schemaVersion") "another schema version is refused"
Check (Test-Field { param($d) $d.PSObject.Properties.Remove("schemaVersion") } "schemaVersion") "and none at all"
Check (Test-Field { param($d) $d.title = "" } "title") "an empty title is refused"
Check (Test-Field { param($d) $d.title = ("a" + [char]9 + "b") } "title") "a title with a tab is refused"
Check (Test-Field { param($d) $d.title = 5 } "title") "a title that is a number is refused"
Check (Test-Field { param($d) $d.type = "image/svg+xml" } "type") "a type that is not shared is refused"
Check (Test-Field { param($d) $d.size = -1 } "size") "a negative size is refused"
Check (Test-Field { param($d) $d.size = "1" } "size") "a size written as text is refused"
Check (Test-Field { param($d) $d.sha256 = ("A" * 64) } "sha256") "a digest in capitals is refused"
Check (Test-Field { param($d) $d.time = "yesterday" } "time") "a time that is not one is refused"
Check (Test-Field { param($d) $d.editable = "true" } "editable") "editable written as text is refused"
Check (Test-Field { param($d) $d.session = "session-a" } "which session") "a session that is not an object is refused"
Check (Test-Field { param($d) $d.session = [pscustomobject]@{ id = "x" } } "whether it is known") "a session that does not say whether it is known is refused"
Check (Test-Field { param($d) $d.session = [pscustomobject]@{ known = $true } } "no id") "a known session with no id is refused"
Check (Test-Field { param($d) $d.session = [pscustomobject]@{ known = $true; id = "" } } "no id") "or an empty one"
Check (Test-Field { param($d) $d.session = [pscustomobject]@{ known = $false; id = "x" } } "no reason") "an unknown session with no reason is refused"
# THE STORE'S OWN STATES.
$asFile = Join-Path $script:work "store-that-is-a-file"
[System.IO.File]::WriteAllText($asFile, "x")
$bad = Get-HordeFilesList -HordeHome $h -Root $asFile
Check ($bad.state -ceq "unknown" -and $bad.reason -like "*is a file, not a folder*" -and (Format-HordeFilesList -List $bad) -join "|" -like "the list of shared files could not be read: *") "a file in the store's place is unknown, with the reason, never an empty list"
Check ((Get-HordeFilesRecords -Root "relative\store" -HeldTries 1 -HeldWaitMs 1).state -ceq "unknown") "a relative store folder is unknown"
# A RECORD HELD BY ITS WRITER is waited for, and named busy if it stays held.
$heldRecord = Join-Path $st (Get-HordeFilesRecordName -FileId $goodId -Version 1)
$grip = New-Object System.IO.FileStream($heldRecord, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
try {
    $t0 = Get-Date
    $busy = Read-HordeFilesRecordFile -Path $heldRecord -HeldTries 3 -HeldWaitMs 100
    $waited = ((Get-Date) - $t0).TotalMilliseconds
    Check ($busy.kind -ceq "busy" -and $busy.reason -like "*after 300 ms*") "a record held open by another process is busy after its tries, saying how long it waited"
    Check ($waited -ge 180 -and $waited -lt 5000) ("and it did wait between the tries (" + [int]$waited + " ms for 3 tries 100 ms apart)")
} finally { $grip.Dispose() }
Check ((Read-HordeFilesRecordFile -Path $heldRecord -HeldTries 3 -HeldWaitMs 100).kind -ceq "ok") "CONTROL: let go, the same record reads"

Write-Host ""
Write-Host "--- taking a version: a lost try is tried again, a set number of times ---" -ForegroundColor Cyan
$h = New-TestHome
$st = Get-StoreOf $h
$vfile = New-Source -Name "versions.md" -Text "v"
$v1 = Invoke-Share -TestHome $h -Path $vfile
# Another share takes the next version between this share's look and its write: stood in for by a
# look that answers one too few, three times: the look before the bytes are kept, and two tries.
$script:realLast = ${function:Get-HordeFilesStoreLastVersion}
$script:lies = 3
function Get-HordeFilesStoreLastVersion { param([string]$Root, [string]$FileId) $real = & $script:realLast -Root $Root -FileId $FileId; if ($script:lies -gt 0) { $script:lies--; return ($real - 1) }; return $real }
$v2 = Invoke-Share -TestHome $h -Path $vfile
Check ($v2.outcome -ceq "shared" -and $v2.record.version -eq 2 -and $v2.attempts -eq 3) ("a share that twice finds its version taken takes the next at the third try (" + $v2.outcome + ", " + $v2.attempts + " tries)")
Check ((Get-HordeFilesList -HordeHome $h).rows.Count -eq 2 -and @(Get-ChildItem -LiteralPath $st -Filter "writing-*.part").Count -eq 0) "the store then holds versions 1 and 2 and no temporary file"
$script:lies = 1000000
$v3 = Invoke-Share -TestHome $h -Path $vfile
Check ($v3.outcome -ceq "refused" -and $v3.reason -like "*20 times in a row (the setting versionTries)*") "a share that never gets a version gives up after the setting's 20 tries, and says so"
Set-Item -Path function:Get-HordeFilesStoreLastVersion -Value $script:realLast
# What a share says when the store could not confirm a write.
function Move-HordeFileNewDurable { param([string]$From, [string]$To, $Open = $null, $OsPlatform = $null) $null = & $script:realMove -From $From -To $To -Open $Open; return "unconfirmed" }
Check (Throws { Invoke-Share -TestHome (New-TestHome) -Path $vfile } "the file's bytes are in the store, but the system could not confirm") "a share whose bytes could not be confirmed on disk throws: it is never told 'shared'"
# In a new home the moves are three: the key takes its name, then the bytes, then the record.
$script:moves = 0
function Move-HordeFileNewDurable { param([string]$From, [string]$To, $Open = $null, $OsPlatform = $null) $script:moves++; $said = & $script:realMove -From $From -To $To -Open $Open; if ($script:moves -eq 3) { return "unconfirmed" }; return $said }
Check (Throws { Invoke-Share -TestHome (New-TestHome) -Path $vfile } "has its name, but the system could not confirm") "nor is one whose record could not be confirmed"
Set-Item -Path function:Move-HordeFileNewDurable -Value $script:realMove

Write-Host ""
Write-Host "--- a file's versions used up: a refusal, never a throw ---" -ForegroundColor Cyan
$h = New-TestHome
$st = Get-StoreOf $h
$full = New-Source -Name "used-up.md" -Text "the first words"
$fullFirst = Invoke-Share -TestHome $h -Path $full
[System.IO.File]::WriteAllText((Join-Path $st ($fullFirst.record.fileId + ".999999.json")), "{}")
# New words, so that a share which got as far as keeping bytes would be seen: the store must not change.
[System.IO.File]::WriteAllText($full, "words nobody has shared yet")
Check (Test-Refused $h $full "already has version 999999, the last a file can have") "with a stray record named for version 999999, the next share of that file is refused with the reason, and keeps no bytes"
$otherFull = Invoke-Share -TestHome $h -Path (New-Source -Name "not-used-up.md" -Text "another file")
Check ($otherFull.outcome -ceq "shared" -and $otherFull.record.version -eq 1) "CONTROL: another file in the same store is shared as before"
# The last versions taken by other shares AFTER this share's first look: stood in for by a look that
# is true once and then answers the last version.
$h = New-TestHome
$null = Invoke-Share -TestHome $h -Path $full
$script:looks = 0
function Get-HordeFilesStoreLastVersion { param([string]$Root, [string]$FileId) $script:looks++; if ($script:looks -eq 1) { return (& $script:realLast -Root $Root -FileId $FileId) }; return 999999 }
$late = Get-Safely { Invoke-Share -TestHome $h -Path $full }
Set-Item -Path function:Get-HordeFilesStoreLastVersion -Value $script:realLast
Check ($late -isnot [string] -and $late.outcome -ceq "refused" -and $late.reason -like "*already has version 999999*") ("a share that finds the last version taken only when it comes to write is refused too, and does not throw (" + $(if ($late -is [string]) { $late } else { $late.outcome }) + ")")

Write-Host ""
Write-Host "--- text is text: strict UTF-8, and no NUL ---" -ForegroundColor Cyan
$h = New-TestHome
$notUtf8 = "is not UTF-8"
$attacks = @(
    @{ what = "a byte that is no UTF-8 at the START"; bytes = @(0xF8, 0x68, 0x69); like = $notUtf8 },
    @{ what = "a byte that is no UTF-8 in the MIDDLE"; bytes = @(0x68, 0x80, 0x69); like = $notUtf8 },
    @{ what = "a lead byte with nothing after it as the LAST byte"; bytes = @(0x68, 0x69, 0xC3); like = $notUtf8 },
    @{ what = "a three-byte sequence cut short at the end"; bytes = @(0x68, 0xE2, 0x82); like = $notUtf8 },
    @{ what = "a four-byte sequence cut short at the end"; bytes = @(0x68, 0xF0, 0x9F, 0x98); like = $notUtf8 },
    @{ what = "an overlong two-byte form of NUL (C0 80)"; bytes = @(0x68, 0xC0, 0x80); like = $notUtf8 },
    @{ what = "an overlong two-byte form of a letter (C1 A1)"; bytes = @(0xC1, 0xA1); like = $notUtf8 },
    @{ what = "an overlong three-byte form of a slash (E0 80 AF)"; bytes = @(0xE0, 0x80, 0xAF); like = $notUtf8 },
    @{ what = "an overlong four-byte form (F0 80 80 AF)"; bytes = @(0xF0, 0x80, 0x80, 0xAF); like = $notUtf8 },
    @{ what = "a lone surrogate (ED A0 80)"; bytes = @(0x68, 0xED, 0xA0, 0x80, 0x69); like = $notUtf8 },
    @{ what = "a surrogate pair written as two three-byte sequences"; bytes = @(0xED, 0xA0, 0xBD, 0xED, 0xB8, 0x80); like = $notUtf8 },
    @{ what = "a character past U+10FFFF (F4 90 80 80)"; bytes = @(0xF4, 0x90, 0x80, 0x80); like = $notUtf8 },
    @{ what = "a continuation byte with no lead"; bytes = @(0x68, 0xBF); like = $notUtf8 },
    @{ what = "a NUL between two letters"; bytes = @(0x68, 0x00, 0x69); like = "holds a NUL byte (the first is byte 1)" },
    @{ what = "a NUL as the last byte"; bytes = @(0x68, 0x69, 0x00); like = "holds a NUL byte (the first is byte 2)" },
    @{ what = "UTF-16 little-endian with its mark"; bytes = @(0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00); like = "it is UTF-16" },
    @{ what = "UTF-16 big-endian with its mark"; bytes = @(0xFE, 0xFF, 0x00, 0x68, 0x00, 0x69); like = "it is UTF-16" },
    @{ what = "UTF-16 little-endian without a mark, Latin letters"; bytes = @(0x68, 0x00, 0x69, 0x00); like = "holds a NUL byte (the first is byte 1)" },
    @{ what = "UTF-16 big-endian without a mark, Latin letters"; bytes = @(0x00, 0x68, 0x00, 0x69); like = "holds a NUL byte (the first is byte 0)" },
    @{ what = "UTF-16 little-endian without a mark, two CJK characters"; bytes = @(0x2D, 0x4E, 0x87, 0x65); like = $notUtf8 },
    @{ what = "a PNG's own first bytes and zeros"; bytes = (Get-Padded -Head $png -Length 64); like = "holds a NUL byte" },
    @{ what = "a PNG's own first bytes and no NUL anywhere"; bytes = @(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x49, 0x48, 0x44, 0x52, 0xFF, 0xD9); like = $notUtf8 })
$n = 0
foreach ($a in $attacks) {
    $n++
    Check (Test-Refused $h (New-Source -Name ("attack-" + $n + ".txt") -Bytes ([byte[]]$a.bytes)) $a.like) ("a .txt file holding " + $a.what + " is refused")
    # The rule itself, for both kinds of text: a .json file is held to the same bytes before its grammar.
    Check ((Get-HordeFilesTextProblem -Bytes ([byte[]]$a.bytes) -Type "text/plain") -like ("*" + $a.like + "*") -and (Get-HordeFilesTextProblem -Bytes ([byte[]]$a.bytes) -Type "application/json") -like ("*" + $a.like + "*")) ("and the reason is the same whichever text type it is named as")
}
$realPng = Get-Padded -Head $png -Length 64
$noNulBinary = [byte[]]@(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x49, 0x48, 0x44, 0x52, 0xFF, 0xD9)
foreach ($ext in @(".txt", ".md", ".json", ".html", ".htm")) {
    Check (Test-Refused $h (New-Source -Name ("picture-renamed" + $ext) -Bytes $realPng) "holds a NUL byte") ("a PNG renamed " + $ext + " is refused")
    Check (Test-Refused $h (New-Source -Name ("binary-renamed" + $ext) -Bytes $noNulBinary) $notUtf8) ("and so is a binary file with no NUL in it, renamed " + $ext)
}
Check ((Invoke-Share -TestHome $h -Path (New-Source -Name "picture.png" -Bytes $realPng)).outcome -ceq "shared") "CONTROL: the same PNG under its own name is shared"
# WHAT MUST STILL PASS: text as people write it.
$everyWidth = [byte[]]@(0x68, 0xC3, 0xA9, 0xE2, 0x82, 0xAC, 0xF0, 0x9F, 0x98, 0x80, 0x09, 0x0D, 0x0A, 0x7F, 0xEF, 0xBF, 0xBF)
foreach ($ext in @(".txt", ".md", ".html", ".htm")) {
    Check ((Invoke-Share -TestHome $h -Path (New-Source -Name ("every-width" + $ext) -Bytes $everyWidth)).outcome -ceq "shared") ("CONTROL: a " + $ext + " file with characters of one, two, three and four bytes, a tab, a line end and U+FFFF is shared")
    Check ((Invoke-Share -TestHome $h -Path (New-Source -Name ("empty" + $ext) -Bytes ([byte[]]@()))).outcome -ceq "shared") ("an EMPTY " + $ext + " file is shared: no characters is valid text")
}
$withMark = [byte[]](@(0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::UTF8.GetBytes("# marked"))
$marked = Invoke-Share -TestHome $h -Path (New-Source -Name "marked.md" -Bytes $withMark)
Check ($marked.outcome -ceq "shared" -and $marked.record.size -eq $withMark.Length -and $marked.record.sha256 -ceq (Get-HordeFilesHex -Bytes $withMark)) "a file that starts with a UTF-8 byte order mark is shared, and the mark is kept: the size and the sha256 are the file's own"
Check ([System.BitConverter]::ToString([System.IO.File]::ReadAllBytes((Join-Path (Get-StoreOf $h) (Get-HordeFilesBytesName -Sha256 $marked.record.sha256)))) -ceq [System.BitConverter]::ToString($withMark)) "the bytes stored are the bytes that were checked, mark included"
Check ((Invoke-Share -TestHome $h -Path (New-Source -Name "only-a-mark.txt" -Bytes ([byte[]]@(0xEF, 0xBB, 0xBF)))).outcome -ceq "shared") "a text file that is only the mark is shared"
Check ((Invoke-Share -TestHome $h -Path (New-Source -Name "utf16-or-utf8.txt" -Bytes ([byte[]]@(0x41, 0x41, 0x42, 0x42)))).outcome -ceq "shared") "KNOWN LIMIT, shown: UTF-16 without a mark whose bytes are valid UTF-8 with no NUL (U+4141 U+4242 is 'AABB') is that UTF-8 text, and is shared"
Check ((Get-HordeFilesTextProblem -Bytes $everyWidth -Type "text/plain") -ceq "") "CONTROL: the rule has no complaint about that text"

Write-Host ""
Write-Host "--- a .json file is exactly one JSON text ---" -ForegroundColor Cyan
$tab = [string][char]9
$validJson = [ordered]@{
    "an object" = '{"a":1,"b":[true,false,null],"c":"x"}'; "an empty object" = '{}'; "an empty array" = '[]'
    "a string alone" = '"hello"'; "a number alone" = '42'; "a negative number with an exponent" = '-1.5e+10'; "zero" = '0'; "true alone" = 'true'; "null alone" = 'null'
    "two keys that differ only by case" = '{"a":1,"A":2}'; "the same key twice" = '{"a":1,"a":2}'; "an empty key" = '{"":1}'
    "white space around and inside" = (" `r`n" + $tab + "{ `"a`" : 1 }`r`n "); "every escape" = '"\" \\ \/ \b \f \n \r \t \u00e9 \u00E9"'
    "a lone surrogate written as an escape" = '"\ud800"'; "a NUL written as an escape" = '"a\u0000b"'; "a four-byte character" = ('"' + [char]::ConvertFromUtf32(0x1F600) + '"')
    "a number of thirty digits" = '123456789012345678901234567890'; "an exponent no double holds" = '1e400'; "minus zero" = '-0'; "a fraction" = '0.5'; "a capital E" = '1E5'; "zero with a fraction and exponent" = '0.0e-0'
    "arrays nested 200 deep" = (('[' * 200) + (']' * 200)); "a key named __type" = '{"__type":"System.Object","a":1}'; "a DEL inside a string" = ('"' + [char]0x7F + '"')
    "nested objects and arrays" = '{"a":{"b":[{"c":[]},{}]},"d":[[],[[]]]}'
}
$invalidJson = [ordered]@{
    "nothing" = ''; "only white space" = "  `n "; "single quotes" = "{'a':1}"; "a key without quotes" = '{a:1}'; "a comma before }" = '{"a":1,}'; "a comma before ]" = '[1,]'
    "a comma first" = '[,1]'; "two commas" = '[1,,2]'; "NaN" = 'NaN'; "Infinity" = 'Infinity'; "-Infinity" = '-Infinity'; "undefined" = 'undefined'
    "a leading zero" = '01'; "a leading zero in an array" = '[01]'; "minus and a leading zero" = '-01'; "a point with no digit after" = '1.'; "a point first" = '.5'; "a plus sign" = '+1'; "hex" = '0x10'
    "an exponent with no digit" = '1e'; "an exponent with only a sign" = '1e+'; "a minus alone" = '-'; "two minus signs" = '--1'
    "a line comment" = "// c`n{}"; "a block comment" = '/* c */ {}'; "words after the value" = '{} x'; "two values" = '{}{}'; "two numbers" = '1 2'; "two values in an array with no comma" = '[1 2]'; "two strings" = '"a""b"'
    "a raw tab inside a string" = ('"a' + $tab + 'b"'); "a raw line end inside a string" = "`"a`nb`""; "the escape \x" = '"\x41"'; "the escape \a" = '"\a"'; "a \u with two digits" = '"\u12"'; "a \u with a letter that is no hex" = '"\u12g4"'
    "an object cut after its colon" = '{"a":'; "a string never closed" = '"abc'; "a string ending in a backslash" = '"abc\'; "an array never closed" = '[1,2'; "an object never closed" = '{"a":1'; "a } too many" = '{}}'; "[ closed by }" = '[}'; "{ closed by ]" = '{"a":1]'
    "nul" = 'nul'; "True" = 'True'; "NULL" = 'NULL'; "truex" = 'truex'; "no colon" = '{"a" 1}'; "a comma for the colon" = '{"a",1}'; "an equals sign for the colon" = '{"a"=1}'; "a key with only its closing quote" = '{a":1}'; "a minus alone in an array" = '[-]'; "no value" = '{"a":}'; "a number as a key" = '{1:2}'; "a colon in an array" = '["a":1]'
    "new Date" = 'new Date(1)'; "a value in brackets ()" = '(1)'; "a no-break space as white space" = ([char]0xA0 + '{}'); "a mark after the value" = ('{}' + [char]0xFEFF); "a vertical tab as white space" = ([char]0x0B + '1'); "a form feed as white space" = ([char]0x0C + '1')
    "a ] alone" = ']'; "a comma alone" = ','; "a colon alone" = ':'
}
# A CHECKER THAT THROWS IS A FAILED CHECK, never a vanished one: every call goes through Get-Safely, whose
# "threw: ..." is neither "" nor a refusal. (Measured 2026-10-13: a mutant that read past the end of
# the text on a lone minus sign threw, the throw ended the loop below, and no check failed.)
function Get-JsonSaid { param([string]$Text, [string]$Type = "") $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text); if ($Type -eq "") { return ("" + (Get-Safely { Get-HordeFilesJsonProblem -Bytes $bytes })) }; return ("" + (Get-Safely { Get-HordeFilesTextProblem -Bytes $bytes -Type $Type })) }
$wrongValid = @($validJson.Keys | Where-Object { (Get-JsonSaid $validJson[$_] "application/json") -cne "" })
Check ($wrongValid.Count -eq 0) ("every one of " + $validJson.Count + " valid JSON texts passes the rule, among them what the platform's parsers wrongly refuse (" + ($wrongValid -join "; ") + ")")
$wrongInvalid = @($invalidJson.Keys | Where-Object { (Get-JsonSaid $invalidJson[$_] "application/json") -notlike "its name says JSON, but it is not: *" })
Check ($wrongInvalid.Count -eq 0) ("every one of " + $invalidJson.Count + " texts that are not JSON is refused by the rule, among them what the platform's parsers wrongly take (" + ($wrongInvalid -join "; ") + ")")
$asText = @($invalidJson.Keys | Where-Object { (Get-JsonSaid $invalidJson[$_] "text/plain") -cne "" })
Check ($asText.Count -eq 0) "CONTROL: named as plain text, every one of those passes: it is the JSON rule that refuses them"
# Each of the broken texts on its own line, so that one let through is named.
foreach ($k in $invalidJson.Keys) { $saidOf = Get-JsonSaid $invalidJson[$k]; Check ($saidOf -cne "" -and $saidOf -notlike "threw:*") ("not JSON, and refused in words, not by a crash: " + $k + $(if ($saidOf -like "threw:*") { " (" + $saidOf + ")" } else { "" })) }
foreach ($k in $validJson.Keys) { Check ((Get-JsonSaid $validJson[$k]) -ceq "") ("JSON: " + $k) }
Check ((Get-HordeFilesJsonProblem -Bytes ([System.Text.Encoding]::UTF8.GetBytes('[1,]'))) -ceq "at byte 3, a value was expected") "the reason says where: [1,] is refused at byte 3"
Check ((Get-HordeFilesJsonProblem -Bytes ([System.Text.Encoding]::UTF8.GetBytes(''))) -like "it holds no value*" -and (Get-HordeFilesJsonProblem -Bytes ([System.Text.Encoding]::UTF8.GetBytes('{"a":1'))) -like "it ends before*") "an empty text is said to hold no value, and a cut one to end too soon"
$deep = [System.Text.Encoding]::ASCII.GetBytes((('[' * 100000) + (']' * 100000)))
Check ((Get-Safely { Get-HordeFilesJsonProblem -Bytes $deep }) -ceq "") "arrays nested 100000 deep are JSON, and are answered: the check does not recurse"
$deepCut = [System.Text.Encoding]::ASCII.GetBytes((('[' * 100000) + (']' * 99999)))
Check ((Get-Safely { Get-HordeFilesJsonProblem -Bytes $deepCut }) -like "it ends before*") "and one bracket short of that is refused"
# THROUGH A SHARE: the file, its name, and the same buffer.
$jsonHome = New-TestHome
Check ((Invoke-Share -TestHome $jsonHome -Path (New-Source -Name "good.json" -Text '{"a":[1,2,{"b":null}]}')).outcome -ceq "shared") "a .json file holding JSON is shared"
Check ((Invoke-Share -TestHome $jsonHome -Path (New-Source -Name "scalar.json" -Text '"just a string"')).outcome -ceq "shared") "and one holding a single string: a value alone is a JSON text"
foreach ($k in @("nothing", "only white space", "a comma before ]", "a leading zero", "two values", "single quotes", "NaN", "an object never closed", "a raw tab inside a string")) {
    Check (Test-Refused $jsonHome (New-Source -Name "bad.json" -Text $invalidJson[$k]) "its name says JSON, but it is not") ("a .json file holding " + $k + " is refused")
}
Check ((Invoke-Share -TestHome $jsonHome -Path (New-Source -Name "not-json.txt" -Text '[1,]')).outcome -ceq "shared") "CONTROL: the same broken text named .txt is shared: only a .json name promises JSON"
$markedJson = [byte[]](@(0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::UTF8.GetBytes('{"a":1}'))
Check ((Invoke-Share -TestHome $jsonHome -Path (New-Source -Name "marked.json" -Bytes $markedJson)).outcome -ceq "shared") "a .json file that starts with a byte order mark is shared: the grammar starts after the mark"
Check (Test-Refused $jsonHome (New-Source -Name "only-a-mark.json" -Bytes ([byte[]]@(0xEF, 0xBB, 0xBF))) "it holds no value") "a .json file that is only the mark is refused: it holds no value"
Check (Test-Refused $jsonHome (New-Source -Name "two-marks.json" -Bytes ([byte[]](@(0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::UTF8.GetBytes('{}')))) "a value was expected") "and a second mark is not white space"
Check (Test-Refused $jsonHome (New-Source -Name "empty.json" -Bytes ([byte[]]@())) "it holds no value") "an EMPTY .json file is refused, where an empty .txt is shared"
# The cap and the text check together: exactly the cap, valid, is shared.
$capJson = Get-Filled 1048576
$capJson[0] = 0x22; $capJson[1048575] = 0x22
$atCapJson = Invoke-Share -TestHome $jsonHome -Path (New-Source -Name "at-cap.json" -Bytes $capJson)
Check ($atCapJson.outcome -ceq "shared" -and $atCapJson.record.size -eq 1048576) "a .json file of exactly 1048576 bytes that is one JSON string is shared"
$capJson[1048575] = 0x61
Check (Test-Refused $jsonHome (New-Source -Name "at-cap-cut.json" -Bytes $capJson) "a string is never closed") "and the same size with its closing quote gone is refused"

Write-Host ""
Write-Host "--- the key file ids are made with: made once, the user's alone, in no record ---" -ForegroundColor Cyan
$h = New-TestHome
$st = Get-StoreOf $h
$keyPath = Get-HordeFilesKeyPath -HordeHome $h
Check ($keyPath -ceq (Join-Path $h "keys\files-id.key")) "the key is kept at <home>\keys\files-id.key"
Check (Test-Refused $h (Join-Path $script:work "sources\not-there.md") "there is no file") "a first share that is refused"
Check (-not (Test-Path -LiteralPath $h)) "makes no key and no home"
$keyDoc = New-Source -Name "keyed.md" -Text "# keyed"
$keyDocReal = Get-RealPath $keyDoc
$k1 = Invoke-Share -TestHome $h -Path $keyDoc
$keyBytes = [byte[]]@()
if ([System.IO.File]::Exists($keyPath)) { $keyBytes = [System.IO.File]::ReadAllBytes($keyPath) }
Check ($k1.outcome -ceq "shared" -and $keyBytes.Length -eq 32) "the first share makes the key: 32 bytes"
Check (@($keyBytes | Sort-Object -Unique).Count -ge 8) "which are not one byte repeated: they came from a generator"
Check ((Get-Names (Split-Path -Parent $keyPath)) -ceq "files-id.key") "and it leaves no temporary file beside it"
$me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
$acl = [System.IO.File]::GetAccessControl($keyPath)
$rules = @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
Check ($acl.GetOwner([System.Security.Principal.SecurityIdentifier]) -eq $me) "the key file's owner is the current user"
Check ($acl.AreAccessRulesProtected) "it inherits nothing from its folder"
Check ($rules.Count -eq 1 -and $rules[0].IdentityReference -eq $me -and $rules[0].AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow -and $rules[0].FileSystemRights -eq [System.Security.AccessControl.FileSystemRights]::FullControl -and -not $rules[0].IsInherited) ("its access list is one entry: the current user, allowed (" + $acl.GetSecurityDescriptorSddlForm("Access") + ")")
$idText = "horde-files-id.v1`nsession:session-a`n" + (Get-AsciiLowered $keyDocReal)
Check ($k1.record.fileId -ceq (Get-Hmac -Key $keyBytes -Text $idText).Substring(0, 32)) "the file id is HMAC-SHA-256, under that key, of the session and the file's path: worked out again here, it is the same"
Check ($k1.record.fileId -cne (Get-HordeFilesHex -Bytes ([System.Text.Encoding]::UTF8.GetBytes($idText))).Substring(0, 32)) "CONTROL: and it is NOT the plain SHA-256 of them, which anyone holding the record could try paths against"
$k2 = Invoke-Share -TestHome $h -Path $keyDoc
Check ($k2.record.fileId -ceq $k1.record.fileId -and $k2.record.version -eq 2 -and [System.BitConverter]::ToString([System.IO.File]::ReadAllBytes($keyPath)) -ceq [System.BitConverter]::ToString($keyBytes)) "the next share uses the same key: the same id, version 2, and the key file is as it was"
$hOther = New-TestHome
$o1 = Invoke-Share -TestHome $hOther -Path $keyDoc
$otherKey = [System.IO.File]::ReadAllBytes((Get-HordeFilesKeyPath -HordeHome $hOther))
Check ([System.BitConverter]::ToString($otherKey) -cne [System.BitConverter]::ToString($keyBytes)) "another home makes another key"
Check ($o1.outcome -ceq "shared" -and $o1.record.fileId -cne $k1.record.fileId) "so the SAME session sharing the SAME path there gets ANOTHER file id: an id says nothing without the key"
$hCopy = New-TestHome
[void][System.IO.Directory]::CreateDirectory((Split-Path -Parent (Get-HordeFilesKeyPath -HordeHome $hCopy)))
[System.IO.File]::WriteAllBytes((Get-HordeFilesKeyPath -HordeHome $hCopy), $keyBytes)
$c1 = Invoke-Share -TestHome $hCopy -Path $keyDoc
Check ($c1.record.fileId -ceq $k1.record.fileId) "CONTROL: a home given the first home's key gets the first home's id: the key is the only thing that differed"
# NOWHERE BUT ITS FILE. Every form a key could be written in, looked for in everything a share leaves and says.
$keyForms = @([System.BitConverter]::ToString($keyBytes).Replace("-", "").ToLowerInvariant(), [System.BitConverter]::ToString($keyBytes).Replace("-", ""), [System.BitConverter]::ToString($keyBytes), [System.Convert]::ToBase64String($keyBytes), (($keyBytes | ForEach-Object { "$_" }) -join ","), (($keyBytes | ForEach-Object { "$_" }) -join " "))
function Test-HoldsKey {
    # Does -Bytes hold the key, raw or in any of the written forms?
    param([byte[]]$Bytes)
    $hex = [System.BitConverter]::ToString($Bytes)
    if ($hex.Contains([System.BitConverter]::ToString($keyBytes))) { return $true }
    $asText = [System.Text.Encoding]::UTF8.GetString($Bytes)
    foreach ($form in $keyForms) { if ($asText.Contains($form)) { return $true } }
    return $false
}
Check (Test-HoldsKey -Bytes ([System.IO.File]::ReadAllBytes($keyPath))) "CONTROL: the look finds the key in the key file itself"
Check (Test-HoldsKey -Bytes ([System.Text.Encoding]::UTF8.GetBytes(("x" + [System.Convert]::ToBase64String($keyBytes) + "y")))) "CONTROL: and in a text that holds it as base64"
$inStore = @(Get-ChildItem -LiteralPath $st -Force | Where-Object { Test-HoldsKey -Bytes ([System.IO.File]::ReadAllBytes($_.FullName)) })
Check ($inStore.Count -eq 0 -and @(Get-ChildItem -LiteralPath $st -Force).Count -eq 3) "no record and no bytes file in the store holds the key (2 records and 1 bytes file read)"
$said = (ConvertTo-Json -InputObject @($k1, $k2) -Depth 6 -Compress) + ((Format-HordeFilesList -List (Get-HordeFilesList -HordeHome $h)) -join "`n")
Check (-not (Test-HoldsKey -Bytes ([System.Text.Encoding]::UTF8.GetBytes($said)))) "nor does what a share returns, nor the printed list"
$pathPieces = @("keyed.md", "keyed", "sources", (Split-Path -Leaf $script:work))
$recordsText = (@(Get-ChildItem -LiteralPath $st -Filter "*.json" | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n") + $said
Check (@($pathPieces | Where-Object { $recordsText.Contains($_) }).Count -eq 0) "and no piece of the file's path - its name, its folder - is in a record, in what a share returns or in the list"

Write-Host ""
Write-Host "--- a key that is gone or damaged refuses the share, and is never made again ---" -ForegroundColor Cyan
$reasons = New-Object System.Collections.ArrayList
function Get-KeyState {
    # What stands in the key's place, as text to compare: its bytes, "folder", "absent", or "held" when another process has it.
    if ([System.IO.Directory]::Exists($keyPath)) { return "folder" }
    if (-not [System.IO.File]::Exists($keyPath)) { return "absent" }
    try { return [System.BitConverter]::ToString([System.IO.File]::ReadAllBytes($keyPath)) } catch { return "held" }
}
function Test-KeyRefusal {
    # With the key file as it now is: is the share refused with -Like, the store unchanged, and the key file untouched?
    param([string]$Like)
    $was = Get-KeyState
    $before = Get-Names $st
    $r = [pscustomobject]@{ outcome = "threw"; reason = "" }
    try { $r = Invoke-Share -TestHome $h -Path $keyDoc } catch { $r.reason = "$($_.Exception.Message)" }
    [void]$reasons.Add("$($r.reason)")
    $now = Get-KeyState
    $ok = ($r.outcome -ceq "refused" -and $r.reason -like ("*" + $Like + "*") -and $r.reason -like "*files-id.key*" -and (Get-Names $st) -ceq $before -and $now -ceq $was)
    if (-not $ok) { Write-Host ("         got: " + $r.outcome + " - " + $r.reason + " - key file " + $(if ($now -ceq $was) { "untouched" } else { "CHANGED" })) -ForegroundColor Red }
    return $ok
}
[System.IO.File]::Delete($keyPath)
Check (Test-KeyRefusal "is missing, and the store already holds shared files") "the key file DELETED between two shares: the next share is refused, naming the file, and NO new key is made"
Check (-not [System.IO.File]::Exists($keyPath)) "the key file is still absent: a new key would have given the file a new id in silence"
[System.IO.File]::WriteAllBytes($keyPath, [byte[]]@())
Check (Test-KeyRefusal "it is 0 bytes") "an EMPTY key file refuses the share"
[System.IO.File]::WriteAllBytes($keyPath, [byte[]]($keyBytes[0..30]))
Check (Test-KeyRefusal "a key is 32 bytes, and it is 31 bytes") "a key file CUT SHORT by one byte refuses the share"
[System.IO.File]::WriteAllBytes($keyPath, [byte[]]($keyBytes[0..0]))
Check (Test-KeyRefusal "it is 1 bytes") "and one cut to a single byte"
[System.IO.File]::WriteAllBytes($keyPath, [byte[]](@($keyBytes) + @(0x01)))
Check (Test-KeyRefusal "it is longer") "a key file one byte too LONG refuses the share"
[System.IO.File]::WriteAllBytes($keyPath, (New-Object byte[] 32))
Check (Test-KeyRefusal "is all zero bytes") "a key file of 32 ZERO bytes refuses the share: that is a file never written through, not a key"
[System.IO.File]::Delete($keyPath)
[void][System.IO.Directory]::CreateDirectory($keyPath)
Check (Test-KeyRefusal "is a folder, not a file") "a FOLDER in the key's place refuses the share"
[System.IO.Directory]::Delete($keyPath)
$keyElsewhere = Join-Path $script:work "a-whole-key-elsewhere.key"
[System.IO.File]::WriteAllBytes($keyElsewhere, $keyBytes)
Check (New-FileLink -Link $keyPath -Target $keyElsewhere) "a symbolic link to a whole key was put in the key's place"
Check (Test-KeyRefusal "is a link") "and the share is refused: a key is never read through a link"
[System.IO.File]::Delete($keyPath)
[System.IO.File]::WriteAllBytes($keyPath, $keyBytes)
# A key another process holds for itself: waited for, the number of tries a setting, then refused.
[void][System.IO.Directory]::CreateDirectory((Join-Path $h "settings"))
[System.IO.File]::WriteAllText((Join-Path $h "settings\files.json"), '{ "schemaVersion": 1, "settings": { "heldReadTries": 3, "heldReadWaitMs": 20 } }')
$keyGrip = New-Object System.IO.FileStream($keyPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
try { Check (Test-KeyRefusal "is still held by another process after 60 ms") "a key file another process holds for itself refuses the share after the tries the settings give" } finally { $keyGrip.Dispose() }
[System.IO.File]::Delete((Join-Path $h "settings\files.json"))
$back = Invoke-Share -TestHome $h -Path $keyDoc
Check ($back.outcome -ceq "shared" -and $back.record.fileId -ceq $k1.record.fileId -and $back.record.version -eq 3) "CONTROL: with the key back and let go, the same path is version 3 of the SAME file: nothing forked while it was refused"
Check ($reasons.Count -eq 9 -and @($reasons | Where-Object { Test-HoldsKey -Bytes ([System.Text.Encoding]::UTF8.GetBytes($_)) }).Count -eq 0) "none of the nine refusals says a byte of the key"
# The pieces, each by itself.
$unitKey = Join-Path $script:work "unit-keys\files-id.key"
Check ((Read-HordeFilesKey -Path $unitKey -HeldTries 1 -HeldWaitMs 1).state -ceq "absent") "reading a key that was never made answers absent, which is not a refusal"
Check ((Get-Safely { New-HordeFilesKey -Path $unitKey }) -ceq "created") "making a key where there is none is told 'created'"
$unitBytes = [System.IO.File]::ReadAllBytes($unitKey)
Check ((Get-Safely { New-HordeFilesKey -Path $unitKey }) -ceq "exists") "making one where there is one is told 'exists'"
Check ([System.BitConverter]::ToString([System.IO.File]::ReadAllBytes($unitKey)) -ceq [System.BitConverter]::ToString($unitBytes) -and (Get-Names (Split-Path -Parent $unitKey)) -ceq "files-id.key") "and the first key is untouched, with no temporary file left: a key is never replaced"
$readBack = Read-HordeFilesKey -Path $unitKey -HeldTries 1 -HeldWaitMs 1
Check ($readBack.state -ceq "ok" -and [System.BitConverter]::ToString($readBack.key) -ceq [System.BitConverter]::ToString($unitBytes) -and $readBack.key.Length -eq 32) "reading it gives those 32 bytes"
$null = New-HordeFilesKey -Path (Join-Path $script:work "unit-keys-2\files-id.key")
Check ([System.BitConverter]::ToString([System.IO.File]::ReadAllBytes((Join-Path $script:work "unit-keys-2\files-id.key"))) -cne [System.BitConverter]::ToString($unitBytes)) "two keys made one after the other are not the same key"
# WHEN A KEY MAY BE MADE: only while the store holds no record. Names alone decide it.
$emptyStore = Join-Path $script:work "store-with-no-record"
[void][System.IO.Directory]::CreateDirectory($emptyStore)
[System.IO.File]::WriteAllText((Join-Path $emptyStore "notes.json"), "{}")
[System.IO.File]::WriteAllText((Join-Path $emptyStore (("ab" * 32) + ".bytes")), "x")
Check (-not (Test-HordeFilesStoreHasRecord -Root $emptyStore) -and -not (Test-HordeFilesStoreHasRecord -Root (Join-Path $script:work "no-such-store"))) "a store holding bytes and a stray .json, and a store that is not there, hold no record"
$hFresh = New-TestHome
$made = Get-HordeFilesKey -HordeHome $hFresh -Root $emptyStore -HeldTries 1 -HeldWaitMs 1
Check ($made.ok -and $made.key.Length -eq 32 -and [System.IO.File]::Exists((Get-HordeFilesKeyPath -HordeHome $hFresh))) "so a key is made for it"
[System.IO.File]::WriteAllText((Join-Path $emptyStore (Get-HordeFilesRecordName -FileId ("ab" * 16) -Version 1)), "damaged")
Check (Test-HordeFilesStoreHasRecord -Root $emptyStore) "one file named as a record, damaged or not, is a record: its id was made with a key"
$hFresh2 = New-TestHome
$notMade = Get-HordeFilesKey -HordeHome $hFresh2 -Root $emptyStore -HeldTries 1 -HeldWaitMs 1
Check (-not $notMade.ok -and $null -eq $notMade.key -and $notMade.reason -like "*is missing*" -and -not (Test-Path -LiteralPath $hFresh2)) "and no key is made for a store that holds one"
# A key another share made BETWEEN this share's two looks - none when it read, a record when it asked
# the store - is used, not refused: stood in for by a look at the store that makes the key first.
$hLate = New-TestHome
$script:realHasRecord = ${function:Test-HordeFilesStoreHasRecord}
function Test-HordeFilesStoreHasRecord { param([string]$Root) $null = New-HordeFilesKey -Path (Get-HordeFilesKeyPath -HordeHome $hLate); return $true }
$lateKey = Get-HordeFilesKey -HordeHome $hLate -Root $emptyStore -HeldTries 1 -HeldWaitMs 1
Set-Item -Path function:Test-HordeFilesStoreHasRecord -Value $script:realHasRecord
Check ($lateKey.ok -and [System.BitConverter]::ToString($lateKey.key) -ceq [System.BitConverter]::ToString([System.IO.File]::ReadAllBytes((Get-HordeFilesKeyPath -HordeHome $hLate)))) "a key another first share made between this share's two looks is the key it uses: it is not refused as missing"
$twoKeys = @((Get-HordeFilesId -Session ([ordered]@{ known = $true; id = "s" }) -FullPath "C:\x\a.md" -Key $anyKey), (Get-HordeFilesId -Session ([ordered]@{ known = $true; id = "s" }) -FullPath "C:\x\a.md" -Key ([byte[]](2..33))), (Get-HordeFilesId -Session ([ordered]@{ known = $true; id = "s" }) -FullPath "C:\X\A.MD" -Key $anyKey))
Check ($twoKeys[0] -cne $twoKeys[1] -and $twoKeys[0] -ceq $twoKeys[2] -and $twoKeys[0] -cmatch '\A[0-9a-f]{32}\z') "one session and path under two keys are two ids; under one key, in any case, one id of 32 hex digits"
Write-Host ""
Write-Host "--- the path in a file id: A to Z folded by the code's own hand, every other character as it is ---" -ForegroundColor Cyan
# AN ID IS PERMANENT, so what goes into it may not depend on the runtime's case table. Measured
# 2026-10-13 on one machine: ToLowerInvariant leaves U+1E9E, U+2126 and U+A7AE as they are under
# Windows PowerShell 5.1 and changes all three under PowerShell 7.6 (to U+00DF, U+03C9, U+026A).
# THE FOLD ITSELF - which characters it changes, and that it asks no table - is core's
# (core/PathText.ps1, ConvertTo-HordeAsciiLower) and is attacked in test/test-path-text.ps1. Here:
# that a file id is made WITH it, and is the number it has always been.
$foldOf = Get-Command ConvertTo-HordeAsciiLower -CommandType Function -ErrorAction SilentlyContinue
$askOf = Get-Command Get-HordeNetworkPathRefusal -CommandType Function -ErrorAction SilentlyContinue
$ownCopies = @(Get-Command -CommandType Function -Name "*-HordeFiles*" | Where-Object { $_.Name -like "*AsciiLower*" -or $_.Name -like "*NetworkRefusal*" -or $_.Name -like "*NetworkPathRefusal*" })
Check ($null -ne $foldOf -and $null -ne $askOf -and ("" + $foldOf.ScriptBlock.File) -like "*\core\PathText.ps1" -and ("" + $askOf.ScriptBlock.File) -like "*\core\PathText.ps1" -and $ownCopies.Count -eq 0) ("loading the share loads the fold and the network question from core/PathText.ps1, and files has no copy of either under a name of its own (" + $ownCopies.Count + ")")
$idSession = [ordered]@{ known = $true; id = "s" }
$oddFolder = "" + [char]0x1E9E + [char]0x2126 + [char]0xA7AE + [char]0x00C9
$pinned = Get-HordeFilesId -Session $idSession -FullPath ("C:\Dir\" + $oddFolder + "\FILE Z.md") -Key $anyKey
# THE PIN. Worked out once, outside this code and with no fold at all: HMAC-SHA-256 under the key
# 1 to 32 of "horde-files-id.v1", "session:s" and c:\dir\<those four characters>\file z.md, each
# on a line of its own. A change to what goes into an id, in any runtime, makes this another number.
Check ($pinned -ceq "94a3e0ff96bf036b03a8068086f339a2") ("the id of a fixed key, session and path is the number it has always been (" + $pinned + ")")
Check ((Get-HordeFilesId -Session $idSession -FullPath ("c:\DIR\" + $oddFolder + "\file z.MD") -Key $anyKey) -ceq $pinned) "and the same path with its A to Z in another case is the same file"
# E acute is the one of the four that Windows PowerShell 5.1's own table changes, so it is the one
# that can see that table come back in the runtime this suite is run under.
foreach ($pair in @(@(0x1E9E, 0x00DF), @(0x2126, 0x03C9), @(0xA7AE, 0x026A), @(0x00C9, 0x00E9))) {
    $asWritten = Get-HordeFilesId -Session $idSession -FullPath ("C:\x\" + [char]$pair[0] + ".md") -Key $anyKey
    $asATableLowersIt = Get-HordeFilesId -Session $idSession -FullPath ("C:\x\" + [char]$pair[1] + ".md") -Key $anyKey
    Check ($asWritten -cne $asATableLowersIt) ("a path holding U+{0:X4} is not the file of the path holding U+{1:X4}, which a case table makes of it" -f $pair[0], $pair[1])
}

Write-Host ""
Write-Host "--- one file has one id, however it is named: the path is the open handle's ---" -ForegroundColor Cyan
$h = New-TestHome
$named = New-Source -Name "a long report name.md" -Text "# one file, many names"
$namedReal = Get-RealPath $named
$script:nameVersion = 1
$byName = Invoke-Share -TestHome $h -Path $named
Check ($byName.outcome -ceq "shared" -and $byName.record.version -eq 1) "a file is shared by its plain path: version 1"
function Test-SameFile {
    # Shared by -Path, is it the NEXT VERSION of the file first shared by its plain path?
    param([string]$Path)
    $r = [pscustomobject]@{ outcome = "threw"; reason = ""; record = $null }
    try { $r = Invoke-Share -TestHome $h -Path $Path } catch { $r.reason = "$($_.Exception.Message)" }
    $ok = ($r.outcome -ceq "shared" -and $r.record.fileId -ceq $byName.record.fileId -and $r.record.version -eq ($script:nameVersion + 1))
    if ($r.outcome -ceq "shared") { $script:nameVersion = [System.Math]::Max($script:nameVersion, [int]$r.record.version) }
    if (-not $ok) { Write-Host ("         got: " + $r.outcome + " " + $r.reason + $(if ($null -ne $r.record) { " id " + $r.record.fileId + " v" + $r.record.version + ", wanted " + $byName.record.fileId } else { "" })) -ForegroundColor Red }
    return $ok
}
Check (Test-SameFile ("\\?\" + $named)) "by the long-path prefix (\\?\C:\...) it is the next version of the SAME file"
# Its 8.3 short name, where this volume makes them.
$shortName = ""
try { $shortName = (New-Object -ComObject Scripting.FileSystemObject).GetFile($named).ShortPath } catch { $shortName = "" }
if ($shortName -ne "" -and (Split-Path -Leaf $shortName) -cne (Split-Path -Leaf $named) -and (Split-Path -Leaf $shortName) -like "*~*") {
    Check ([System.IO.File]::Exists($shortName)) ("CONTROL: this volume gave the file the short name " + (Split-Path -Leaf $shortName))
    Check (Test-SameFile $shortName) "by its 8.3 short name it is the next version of the SAME file"
    # .NET itself writes a short name out in full before it opens anything, so the line above never
    # shows Windows a short name (measured 2026-10-13: asking for the name AS OPENED instead of the
    # normalized one changed nothing there). Behind the long-path prefix .NET changes nothing, and the
    # handle really is opened by the short name.
    Check (Test-SameFile ("\\?\" + $shortName)) "and by its short name behind the long-path prefix, where the handle is opened by the short name itself"
} else { Write-Skip "THE 8.3 SHORT NAME COULD NOT BE TESTED: this volume gave 'a long report name.md' no short name. Run this suite on a volume that makes them." }
# BY A DRIVE LETTER THAT STANDS FOR THE FILE'S FOLDER (subst): NOT RUN HERE ANY MORE. Until
# 2026-10-13 this suite made such a letter and shared the file through it, and the id was the same.
# A drive letter is seen by every process of the user while it exists, and a suite must not change
# what other processes see (test/lib/SuiteFiles.ps1, Get-HordeDriveLetterMakers), so no letter is
# made here. What made that case pass is the rule every check above and below this one holds: the
# id comes from the open handle's own path, never from the path that was written. The one fact that
# is Windows' and not this code's - that a handle opened through such a letter has the folder's own
# path - is asked of Windows once, in test/test-path-text.ps1, the one place a letter is made. What
# is NOT run any more: a whole share through such a letter.
Check (Test-SameFile $named.ToUpperInvariant()) "and by its plain path in capitals"
$elseFile = Invoke-Share -TestHome $h -Path (New-Source -Name "another long report name.md" -Text "# another file")
Check ($elseFile.outcome -ceq "shared" -and $elseFile.record.fileId -cne $byName.record.fileId) "CONTROL: another file is another id, so one id for all those names was not one id for everything"
# A path longer than the first buffer the final path is asked with.
$longDir = "\\?\" + (Join-Path $script:work ("long\" + ((1..6 | ForEach-Object { "a-folder-name-that-is-eighty-characters-long-" + ("x" * 35) }) -join "\")))
[void][System.IO.Directory]::CreateDirectory($longDir)
[System.IO.File]::WriteAllText(($longDir + "\deep.md"), "deep")
$longShare = Get-Safely { Invoke-Share -TestHome $h -Path ($longDir + "\deep.md") }
Check ($longDir.Length -gt 520 -and $longShare -isnot [string] -and $longShare.outcome -ceq "shared") ("a file whose path is " + ($longDir.Length + 8) + " characters is shared: the final path is asked again with the size Windows names")
[System.IO.Directory]::Delete(("\\?\" + (Join-Path $script:work "long")), $true)

Write-Host ""
Write-Host "--- a network path is refused from its text, and a network drive by its type, before anything looks at it ---" -ForegroundColor Cyan
# TO LOOK AT A NETWORK PATH IS THE HARM: asking whether it exists sends the user's sign-in to the host
# it names. So "refused" is not enough to check; it must be refused BEFORE anything asked.
# THE INSTRUMENT is the DNS cache of this machine. A host name nobody has ever used (ten digits made
# here, one label) is in that cache after anything asks the network about a path under it, and is not
# there otherwise. Measured 2026-10-13: 12 of 12 after File.Exists, Directory.Exists and an open; 0 of
# 4 with nothing called. A name with dots in it was no instrument (3 of 36), and neither was time (a
# lookup of such a name came back in 15 ms).
function New-NoHost { return ("horde-" + [guid]::NewGuid().ToString("N").Substring(0, 10)) }
function Get-LookedUp { return ((& ipconfig.exe /displaydns) -join "`n") }
function Get-FreeLetter {
    # A letter that names nothing, for a POWERSHELL drive of this process's own (which is no drive
    # letter of the system's: no other process sees it). Nothing is defined here, only asked.
    $taken = @([System.IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name.Substring(0, 1) })
    foreach ($candidate in "RSTUVWQPONMLKJ".ToCharArray()) { if ($taken -cnotcontains ("" + $candidate) -and -not [System.IO.Directory]::Exists($candidate + ":\") -and $null -eq (Get-PSDrive -Name ("" + $candidate) -ErrorAction SilentlyContinue)) { return ("" + $candidate) } }
    return ""
}
$seenHost = New-NoHost
$null = [System.IO.File]::Exists("\\" + $seenHost + "\share\x.md")
$cacheNow = Get-LookedUp
$canSee = ($cacheNow.Contains($seenHost) -and -not $cacheNow.Contains((New-NoHost)))
if ($canSee) { Check $true "CONTROL: the instrument can see a lookup: a host asked about is in the DNS cache, and a name nobody asked about is not" }
else { Write-Skip "WHETHER A NETWORK PATH WAS LOOKED AT COULD NOT BE SEEN: this machine's DNS cache does not show a host that was just asked about. The refusals below are still checked by their reasons." }
# EVERY SPELLING, each under a host of its own that does not exist. A not-found reason here would mean
# something asked the network before the text was read.
$spellings = @(
    @("two backslashes", "\\{0}\share\x.md"), @("two forward slashes", "//{0}/share/x.md"), @("a backslash and then a forward slash", "\/{0}\share\x.md"),
    @("a forward slash and then a backslash", "/\{0}/share/x.md"), @("three backslashes", "\\\{0}\share\x.md"),
    @("the long-path UNC prefix", "\\?\UNC\{0}\share\x.md"), @("the long-path UNC prefix in small letters", "\\?\unc\{0}\share\x.md"), @("the long-path UNC prefix in mixed case", "\\?\uNc\{0}\share\x.md"),
    @("the long-path UNC prefix with forward slashes", "//?/UNC/{0}/share/x.md"), @("the device-prefix UNC form", "\\.\UNC\{0}\share\x.md"), @("the device-prefix UNC form with forward slashes", "//./unc/{0}/share/x.md"),
    @("the NT form of a UNC path", "\??\UNC\{0}\share\x.md"), @("a server's own drive share", "\\{0}\C$\x.md"), @("a share with nothing under it", "\\{0}\share"), @("a server and nothing else", "\\{0}"),
    @("the long-path UNC prefix and nothing else", "\\?\UNC"), @("a device's name on a share", "\\{0}\share\NUL"), @("a stream of a file on a share", "\\{0}\share\x.md:y.txt"), @("a folder on a share", "\\{0}\share\folder\"))
$askedHosts = New-Object System.Collections.ArrayList
foreach ($spelling in $spellings) {
    $noHost = New-NoHost
    [void]$askedHosts.Add($noHost)
    Check (Test-Refused $h ($spelling[1] -f $noHost) "is a network path, and only a file on one of this machine's own drives is shared") ("a network path is refused from its text: " + $spelling[0] + " (" + ($spelling[1] -f "<host>") + ")")
}
$cacheNow = Get-LookedUp
$lookedUp = @($askedHosts | Where-Object { $cacheNow.Contains($_) })
if ($canSee) { Check ($lookedUp.Count -eq 0 -and $askedHosts.Count -eq 19) ("and not one of those " + $askedHosts.Count + " hosts was looked up: nothing asked the disk or the network before the refusal (looked up: " + $lookedUp.Count + ")") }
# THIS MACHINE'S OWN DRIVE SHARE, where the file really is. Until 2026-10-13 this was shared, as the
# local file, on the word of two handles compared; every one of the compared values is the server's
# to say, so it is a network path like any other.
$ownShare = "\\localhost\" + $namedReal.Substring(0, 1) + "$" + $namedReal.Substring(2)
Check (Test-Refused $h $ownShare "is a network path") "the file by this machine's own drive share (\\localhost\C$\...) is refused: it is named by its local path"
Check (Test-Refused $h ("\\127.0.0.1\" + $namedReal.Substring(0, 1) + "$" + $namedReal.Substring(2)) "is a network path") "and by this machine's address"
Check (Test-Refused $h ("\\?\UNC\localhost\" + $namedReal.Substring(0, 1) + "$" + $namedReal.Substring(2)) "is a network path") "and by the long-path form of that"
Check (Test-Refused $h (Split-Path -Parent $ownShare) "is a network path") "a FOLDER by this machine's own drive share is refused as a network path, not as a folder: nothing looked to see what it is"
# WHAT ONLY THE RESOLVED PATH SHOWS: a PowerShell drive over a share. The drive is made here, which
# looks its host up, so only the reason can be checked - and a not-found reason would mean the
# resolved path was looked at instead of read.
$psLetter = Get-FreeLetter
$psHost = New-NoHost
$null = New-PSDrive -Name $psLetter -PSProvider FileSystem -Root ("\\" + $psHost + "\share") -Scope Script
Check ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($psLetter + ":\x.md") -ceq ("\\" + $psHost + "\share\x.md")) ("CONTROL: a PowerShell drive " + $psLetter + ": was made over a share, and a path on it resolves to the share")
Check (Test-Refused $h ($psLetter + ":\x.md") "is a network path") "a path that is a network path only once it is resolved is refused as one"
Remove-PSDrive -Name $psLetter -Scope Script
$uncFolder = Split-Path -Parent $ownShare
if ([System.IO.Directory]::Exists($uncFolder)) {
    Push-Location -LiteralPath $uncFolder
    try { $relInShare = Test-Refused $h "a long report name.md" "is a network path" } finally { Pop-Location }
    Check $relInShare "and so is a relative path, named while standing in a folder of a share"
} else { Write-Skip ("A RELATIVE PATH FROM INSIDE A SHARE COULD NOT BE TESTED: this session cannot stand in " + $uncFolder + " (the drive's own share needs an administrator's token).") }
# A NETWORK DRIVE, known by its type. NO DRIVE IS MADE: a drive letter is seen by every process of
# the user while it exists, and the one this suite used to aim at a host that does not exist made a
# fresh powershell of every other session print an error and start slowly (core/PathText.ps1,
# Get-HordeDriveLetterType, has the measurement). The one function that asks a drive's type is
# replaced, for these checks, by one that answers Network for the letter R and counts who asked;
# it is called exactly as the real one is. What Windows itself says of a letter is
# test/test-path-text.ps1's, in the one place a real letter is made.
$script:realDriveType = ${function:Get-HordeDriveLetterType}
$script:driveAsked = New-Object System.Collections.ArrayList
function Get-HordeDriveLetterType {
    param([Parameter(Mandatory = $true)][string]$Letter)
    [void]$script:driveAsked.Add($Letter)
    if ($Letter -ceq "R" -or $Letter -ceq "r") { return "Network" }
    return (& $script:realDriveType -Letter $Letter)
}
$netChecks = New-Object System.Collections.ArrayList
try {
    [void]$netChecks.Add((Test-Refused $h "R:\x.md" "is on a network drive (R:)"))
    [void]$netChecks.Add((Test-Refused $h "\\?\R:\x.md" "is on a network drive"))
    [void]$netChecks.Add((Test-Refused $h "R:x.md" "is on a network drive"))
    [void]$netChecks.Add((Test-Refused $h "r:\x.md" "is on a network drive"))
    $askedOfR = @($script:driveAsked | Where-Object { $_ -ceq "R" -or $_ -ceq "r" }).Count
    $script:driveAsked.Clear()
    [void]$netChecks.Add((Test-SameFile $named))
    $askedOfLocal = (@($script:driveAsked) -join ",")
} finally { Set-Item -Path function:Get-HordeDriveLetterType -Value $script:realDriveType }
Check $netChecks[0] "a file on a drive whose type is Network is refused by the drive's type"
Check $netChecks[1] "and behind the long-path prefix"
Check $netChecks[2] "and named from wherever that drive stands"
Check $netChecks[3] "and with its letter in small"
Check ($askedOfR -eq 4) ("each of those four was refused on the first question: the type was asked once for each and nothing after it, so nothing resolved or looked at the path (" + $askedOfR + ")")
Check ($netChecks[4] -and $askedOfLocal -ceq (($named.Substring(0, 1), $named.Substring(0, 1)) -join ",")) ("CONTROL: with the same answerer in place a file on a local drive is shared, its drive's type asked of the path as written and again of the path it resolves to (" + $askedOfLocal + ")")
Check ((Get-HordeDriveLetterType -Letter $named.Substring(0, 1)) -ceq "Fixed") "the real question is back, and says this suite's drive is a fixed one"
Check (Test-SameFile $named) "CONTROL: after all those refusals the file by its local path is still the next version of the SAME file"
# Others may read the file while it is shared: it is opened so that they can.
$otherReader = New-Object System.IO.FileStream($named, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
try { $whileRead = Test-SameFile $named } finally { $otherReader.Dispose() }
Check $whileRead "a file another process holds open for reading is shared all the same"

Write-Host ""
Write-Host "--- the open handle's own path: on a drive it is the file's one path, and anywhere else it is refused ---" -ForegroundColor Cyan
$fileA = New-Source -Name "final-path-a.md" -Text "a"
$realA = Get-RealPath $fileA
$handleA = New-Object System.IO.FileStream($fileA, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
try {
    $finalA = Get-HordeFilesFinalPath -Stream $handleA
    Check ($finalA -ceq ("\\?\" + $realA)) "the final path of an open file is its path behind \\?\"
} finally { $handleA.Dispose() }
$local = Resolve-HordeFilesLocalPath -Final $finalA
Check ($local.ok -and $local.path -ceq $realA) "a final path on a drive is that path, without the prefix"
# WHAT THE TEXT AND THE DRIVE'S TYPE DID NOT GIVE AWAY: the handle's own path is a network one.
$onShare = Resolve-HordeFilesLocalPath -Final "\\?\UNC\server\share\folder\x.md"
Check (-not $onShare.ok -and $onShare.path -ceq "" -and $onShare.reason -like "it is on a network share ('\\server\share\folder\x.md')*") "a final path on a share is refused, and the reason names the share"
$onOwnShare = Resolve-HordeFilesLocalPath -Final ("\\?\UNC\localhost\" + $realA.Substring(0, 1) + "$" + $realA.Substring(2))
Check (-not $onOwnShare.ok -and $onOwnShare.path -ceq "") "and so is one on this machine's own drive share, where a file of that path IS: nothing brings a network path home"
$unsaid = Resolve-HordeFilesLocalPath -Final ""
Check (-not $unsaid.ok -and $unsaid.reason -like "*Windows would not say where the opened file really is*") "when Windows gives no final path at all, the share is refused with that reason"
# A file that was opened and then refused is let go: nothing keeps holding it.
$script:realResolve = ${function:Resolve-HordeFilesLocalPath}
function Resolve-HordeFilesLocalPath { param([string]$Final) return [pscustomobject]@{ ok = $false; path = ""; reason = "refused by this suite" } }
$turnedAway = Open-HordeFilesSource -Path $fileA
Set-Item -Path function:Resolve-HordeFilesLocalPath -Value $script:realResolve
$toItself = "held"
try { $alone = New-Object System.IO.FileStream($fileA, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None); $alone.Dispose(); $toItself = "free" } catch { }
Check (-not $turnedAway.ok -and $null -eq $turnedAway.stream -and $turnedAway.reason -ceq "refused by this suite" -and $toItself -ceq "free") ("a file whose place is refused after it was opened is let go again: another process can have it to itself (" + $toItself + ")")
$goneOpen = Open-HordeFilesSource -Path (Join-Path $script:work "sources\no-such-file.md")
Check (-not $goneOpen.ok -and $null -eq $goneOpen.stream -and $goneOpen.reason -like "it cannot be read:*") "opening a file that is not there is a refusal with the reason, and hands back no handle"

Write-Host ""
Write-Host "--- a device, and a stream inside a file, are refused from the path as written ---" -ForegroundColor Cyan
$h = New-TestHome
$null = Invoke-Share -TestHome $h -Path $named
$inSources = Join-Path $script:work "sources"
$deviceNames = @("NUL", "nul", "CON", "PRN", "AUX", "COM1", "com9", "COM0", "LPT1", "LPT9", "CONIN$", "CONOUT$", "NUL.txt", "nul.md", "NUL:", "COM1:", "NUL .md",
    (Join-Path $inSources "NUL"), (Join-Path $inSources "con.md"), (Join-Path $inSources "aux.tar.md"), (Join-Path $inSources "AUX\report.md"), ".\prn.md", "C:/folder/lpt1.md", ("\\?\" + (Join-Path $inSources "nul.md")), ("COM" + [char]0xB9 + ".md"))
foreach ($d in $deviceNames) { Check (Test-Refused $h $d "is a name Windows keeps for a device") ("a path holding a device's name is refused: " + ($d -replace '[^\x20-\x7E]', '?')) }
$deviceForms = @("\\.\NUL", ("\\.\" + $named), ("//./" + $named.Replace("\", "/")), "\\.\pipe\some-pipe", "\\.\PhysicalDrive0", "\\?\NUL", "\\?\GLOBALROOT\Device\Null", "\\?\Volume{00000000-0000-0000-0000-000000000000}\x.md", ("\??\" + $named), "\\?\pipe\some-pipe")
foreach ($d in $deviceForms) { Check (Test-Refused $h $d "is in the device form") ("a path in the device form is refused: " + $d) }
foreach ($fine in @("console.md", "nullable.md", "com10.md", "lpt.md", "aux1.md", "conin.md", "the nul file.md", "nul-.md", "falcon.md", "annul.md", "xcom1.md")) {
    Check ((Invoke-Share -TestHome $h -Path (New-Source -Name $fine -Text "words")).outcome -ceq "shared") ("CONTROL: a file whose name only looks like a device's is shared: " + $fine)
}
foreach ($fine in @("C:\a\b.md", "\\?\C:\a\b.md", ".\b.md", "..\b.md", "C:b.md", "b.md", "c:/a/b.md", "")) { Check ((Get-HordeFilesPathRefusal -Path $fine) -ceq "") ("CONTROL: the text of an ordinary path is not refused: '" + $fine + "'") }
# A REAL stream, made behind the long-path prefix (.NET refuses the plain form by itself).
$streamOf = $named + ":hidden.txt"
[System.IO.File]::WriteAllText(("\\?\" + $streamOf), "words kept in a stream")
Check ([System.IO.File]::ReadAllText(("\\?\" + $streamOf)) -ceq "words kept in a stream" -and [System.IO.File]::ReadAllText($named) -ceq "# one file, many names") "CONTROL: the file has a stream named hidden.txt, holding other words than the file"
Check (Test-Refused $h $streamOf "that names a stream inside a file") "a path naming a stream of a file is refused"
Check (Test-Refused $h ("\\?\" + $streamOf) "that names a stream inside a file") "and behind the long-path prefix, where it would open"
Check (Test-Refused $h ($named + "::`$DATA") "that names a stream inside a file") "and the file's own data named as a stream"
Check ((Get-HordeFilesPathRefusal -Path "\\?\UNC\server\share\b.md") -like "*is in the device form*" -and (Get-HordeFilesPathRefusal -Path "\\server\share\b.md") -ceq "") "asked by itself about a network path, this look knows only the prefix: a network path is the look before it's to refuse"
Push-Location (Split-Path -Parent $named)
try { $relStream = Test-Refused $h "a long report name.md:hidden.txt" "that names a stream inside a file" } finally { Pop-Location }
Check $relStream "and a relative one, which PowerShell would otherwise read as a drive"
$stillFile = Invoke-Share -TestHome $h -Path $named
Check ($stillFile.outcome -ceq "shared" -and $stillFile.record.size -eq 22) "CONTROL: the file itself is still shared, and what is kept is the file's 22 bytes, not the stream's"

Write-Host ""
Write-Host "--- a link swapped in around the open cannot put one file's bytes under another's name ---" -ForegroundColor Cyan
$h = New-TestHome
$note = New-Source -Name "swap-note.md" -Text "the note that was named"
$picture = New-Source -Name "swap-target.png" -Bytes (Get-Padded -Head $png -Length 64)
$direct = Invoke-Share -TestHome $h -Path $picture
$noteAlone = Invoke-Share -TestHome $h -Path $note
Check ($direct.outcome -ceq "shared" -and $noteAlone.outcome -ceq "shared" -and $noteAlone.record.fileId -cne $direct.record.fileId -and $noteAlone.record.type -ceq "text/markdown") "CONTROL: a note and a picture are two files; the note is shared as Markdown"
# THE ADVERSARY'S MOMENT, made exact: the note becomes a link to the picture just before the open and
# is the note again just after it. The open itself is the real one.
$script:realOpen = ${function:Open-HordeFilesSource}
function Open-HordeFilesSource {
    param([string]$Path)
    [System.IO.File]::Delete($note)
    $null = New-FileLink -Link $note -Target $picture
    $o = & $script:realOpen -Path $Path
    [System.IO.File]::Delete($note)
    [System.IO.File]::WriteAllText($note, "the note that was named")
    return $o
}
$swapped = Get-Safely { Invoke-Share -TestHome $h -Path $note }
Set-Item -Path function:Open-HordeFilesSource -Value $script:realOpen
Check ($swapped -isnot [string] -and $swapped.outcome -ceq "shared" -and $swapped.record.sha256 -ceq $direct.record.sha256) "with the swap, what was read is the picture: the link was followed at the open"
Check ($swapped -isnot [string] -and $swapped.outcome -ceq "shared" -and $swapped.record.type -ceq "image/png") "and it is recorded AS a picture: the type is the opened file's, not the written name's"
Check ($swapped -isnot [string] -and $swapped.outcome -ceq "shared" -and $swapped.record.fileId -ceq $direct.record.fileId -and $swapped.record.version -eq 2) "under the PICTURE's file id, as its version 2: the picture's bytes are never a version of the note"
Check (@((Get-HordeFilesList -HordeHome $h).rows | Where-Object { $_.fileId -ceq $noteAlone.record.fileId }).Count -eq 1) "the note still has its one version"
# A link that is still there after the open is refused, as a link always was.
function Open-HordeFilesSource {
    param([string]$Path)
    [System.IO.File]::Delete($note)
    $null = New-FileLink -Link $note -Target $picture
    return (& $script:realOpen -Path $Path)
}
$stays = Test-Refused $h $note "is a link"
Set-Item -Path function:Open-HordeFilesSource -Value $script:realOpen
Check $stays "a link put in the file's place before the open, and still there after it, is refused: the look comes after the open"
[System.IO.File]::Delete($note)

# Out of the folder before it is removed: a folder a process stands in cannot be.
Set-Location -LiteralPath $root
[System.IO.Directory]::SetCurrentDirectory($root)
if ((Split-Path -Leaf $script:work) -match '\Ahorde-files-store-test-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) {
    # Links first, by their own entries, so that removing the folder never follows one.
    foreach ($entry in @(Get-ChildItem -LiteralPath $script:work -Recurse -Force | Where-Object { ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 })) { if ($entry.PSIsContainer) { [System.IO.Directory]::Delete($entry.FullName) } else { [System.IO.File]::Delete($entry.FullName) } }
    Remove-Item -LiteralPath $script:work -Recurse -Force
}
Check (-not (Test-Path -LiteralPath $script:work)) "the suite's temp folder is removed"

Complete-HordeSuite -Success "the files store keeps every share once and whole, refuses what must not be shared, and lists damage as damage"
