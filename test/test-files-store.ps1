# DOES THE FILES STORE KEEP EVERY SHARE ONCE, WHOLE, AND REFUSE WHAT MUST NOT BE SHARED?
#
# files/Store.ps1, files/Share.ps1 and files/Settings.ps1, in this process. The suite attacks the rules:
#   - an entry is put in place once: a second write of a name is told "exists" and changes no byte;
#   - a share is refused, with nothing written, for a missing file, a folder, a link (the file, or a
#     folder on the way to it), a type not on the list, a picture or PDF whose first bytes are not
#     its format's, an SVG, and a file one byte over the cap - while the cap itself passes;
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
Check ((Get-HordeFilesId -Session ([ordered]@{ known = $true; id = "no-session" }) -FullPath "C:\x\a.md") -cne (Get-HordeFilesId -Session ([ordered]@{ known = $false; reason = "r" }) -FullPath "C:\x\a.md")) "a session that happens to be called 'no-session' does not share a file id with no session"

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
Check (Test-Refused $h (New-Source -Name "DRAWING.SVG" -Text "<svg/>") "an SVG file is not shared") "whatever the case of its extension"
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
$atCap = New-Source -Name "at-cap.txt" -Bytes (New-Object byte[] 1048576)
$overCap = New-Source -Name "over-cap.txt" -Bytes (New-Object byte[] 1048577)
$big = Invoke-Share -TestHome $h -Path $atCap
Check ($big.outcome -ceq "shared" -and $big.record.size -eq 1048576) "a file of exactly 1048576 bytes is shared under the default cap"
Check (Test-Refused $h $overCap "1048577 bytes; the largest file that is shared is 1048576 bytes (the setting maxFileBytes)") "a file of 1048577 bytes is refused, with both numbers and the setting's name"
[void][System.IO.Directory]::CreateDirectory((Join-Path $h "settings"))
[System.IO.File]::WriteAllText((Join-Path $h "settings\files.json"), '{ "schemaVersion": 1, "settings": { "maxFileBytes": 100, "maxTitleChars": 5 } }')
Check ((Invoke-Share -TestHome $h -Path (New-Source -Name "hundred.txt" -Bytes (New-Object byte[] 100)) -Title "Small").outcome -ceq "shared") "with the setting at 100, a file of 100 bytes is shared"
Check (Test-Refused $h (New-Source -Name "hundred-one.txt" -Bytes (New-Object byte[] 101)) "101 bytes; the largest file that is shared is 100 bytes" -Title "Small") "and one of 101 bytes is refused: the cap is the setting, not a number in the code"
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
# look that answers one too few, twice.
$script:realLast = ${function:Get-HordeFilesStoreLastVersion}
$script:lies = 2
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
$script:moves = 0
function Move-HordeFileNewDurable { param([string]$From, [string]$To, $Open = $null, $OsPlatform = $null) $script:moves++; $said = & $script:realMove -From $From -To $To -Open $Open; if ($script:moves -eq 2) { return "unconfirmed" }; return $said }
Check (Throws { Invoke-Share -TestHome (New-TestHome) -Path $vfile } "has its name, but the system could not confirm") "nor is one whose record could not be confirmed"
Set-Item -Path function:Move-HordeFileNewDurable -Value $script:realMove

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
