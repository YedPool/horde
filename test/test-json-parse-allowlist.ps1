# DOES ANY SHIPPED FILE CALL ConvertFrom-Json ITSELF? (core/json-parse-allowlist.txt is closed: it allows nothing.)
#
# Issue #274: PowerShell 7's ConvertFrom-Json reads a date-shaped string as a [datetime], and the
# decisions module refused its own records under 7. ConvertFrom-HordeJson (core/JsonText.ps1) is the one
# parse that keeps strings strings under both shells; tools/RawJsonParse.ps1 holds every other file to
# a closed, empty list (T-0323). This suite first proves the scan refuses what it must, on throwaway
# repositories, each with EXACTLY ONE finding per refusal so a case cannot pass for the wrong reason
# (as test/test-host-names.ps1 does); then it proves the instrument sees a raw call in a synthetic file;
# then it runs the scan on this repository.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "tools\RawJsonParse.ps1")

$fake = Join-Path $env:TEMP ("horde-rawjson-" + [guid]::NewGuid().ToString("N").Substring(0, 8))

function Show { param($F) foreach ($x in @($F)) { Write-Host ("         got: " + $x.path + " - " + $x.problem) -ForegroundColor Red } }

function Write-FakeFile {
    param([string]$Rel, [string]$Text)
    $p = Join-Path $script:repo $Rel
    New-Item -ItemType Directory -Force (Split-Path -Parent $p) | Out-Null
    [System.IO.File]::WriteAllText($p, $Text)
}

function New-FakeRepo {
    # An empty (closed) list, a file that parses through the seam, the seam with raw calls of its own, a
    # clean file that only MENTIONS the cmdlet in a comment and a string, and a test folder with a raw
    # call. Every case starts from it and changes one thing.
    param([string]$Name)
    $script:repo = Join-Path $fake $Name
    Write-FakeFile "core/json-parse-allowlist.txt" "# closed`n"
    Write-FakeFile "core/old.ps1" "`$a = ConvertFrom-HordeJson '{}'`n"
    Write-FakeFile "core/JsonText.ps1" "function ConvertFrom-HordeJson { param(`$Text) `$Text | ConvertFrom-Json }`n"
    Write-FakeFile "core/clean.ps1" "# ConvertFrom-Json is named here only in a comment`n`$s = 'ConvertFrom-Json'`n`$c = ConvertFrom-HordeJson '{}'`n"
    Write-FakeFile "core/test/reader.ps1" "`$r = '{}' | ConvertFrom-Json`n"
    return $script:repo
}

function Scan {
    param([string]$Name, [scriptblock]$Change)
    $r = New-FakeRepo $Name
    & $Change
    return @(Test-HordeRawJsonParse -Root $r)
}

function Refuses {
    param([string]$Name, [scriptblock]$Change, [string]$Text, [string]$What)
    $f = @(Scan $Name $Change)
    $ok = ($f.Count -eq 1 -and ("" + $f[0].problem) -like "*$Text*")
    Check $ok $What
    if (-not $ok) { Show $f }
}

try {
    Write-Host ""
    Write-Host "--- CONTROL: a repository with no raw call and an empty list passes ---" -ForegroundColor Cyan
    $f = @(Scan "clean" { })
    Check ($f.Count -eq 0) "a repository with no raw call and an empty list passes; the seam, a comment, a string and a test folder are not findings"
    if ($f.Count -gt 0) { Show $f }

    Write-Host ""
    Write-Host "--- what the scan refuses ---" -ForegroundColor Cyan
    Refuses "pipe" { Write-FakeFile "decisions/new.ps1" "`$x = '{}' | ConvertFrom-Json`n" } "calls ConvertFrom-Json 1 time(s)" "a raw call in any file is a finding: there is nothing to list it on"
    Refuses "param" { Write-FakeFile "decisions/new.ps1" "`$x = ConvertFrom-Json -InputObject '{}'`n" } "calls ConvertFrom-Json 1 time(s)" "a raw call written with -InputObject is a finding"
    Refuses "prefixed" { Write-FakeFile "decisions/new.ps1" "`$x = Microsoft.PowerShell.Utility\ConvertFrom-Json '{}'`n" } "calls ConvertFrom-Json 1 time(s)" "a raw call written with its module prefix is a finding too"
    Refuses "three" { Write-FakeFile "core/old.ps1" "`$a = '{}' | ConvertFrom-Json`n`$b = '{}' | ConvertFrom-Json`n`$c = '{}' | ConvertFrom-Json`n" } "calls ConvertFrom-Json 3 time(s)" "a file that used to be clean and gains three raw calls is a finding with their count"
    Refuses "entry" { Write-FakeFile "core/json-parse-allowlist.txt" "# closed`ncore/old.ps1 | 1 | not yet moved`n" } "line 2 is an entry, and the allowlist is closed" "an entry in the allowlist is a finding, even for a file that is clean"
    $f = @(Scan "entry-for-raw" { Write-FakeFile "core/json-parse-allowlist.txt" "# closed`ncore/old.ps1 | 1 | not yet moved`n"; Write-FakeFile "core/old.ps1" "`$a = '{}' | ConvertFrom-Json`n" })
    Check ($f.Count -eq 2) "listing a raw file does not excuse it: the call is a finding as well as the entry"
    if ($f.Count -ne 2) { Show $f }
    Refuses "no-list" { Remove-Item -LiteralPath (Join-Path $script:repo "core/json-parse-allowlist.txt") } "the allowlist is missing" "a missing allowlist is a finding, not an empty pass"
    Refuses "unparsable" { Write-FakeFile "core/old.ps1" "`$a = '{}' | ConvertFrom-Json`nfunction broken {`n" } "does not parse" "a file that does not parse is a finding, never a pass"

    Write-Host ""
    Write-Host "--- the instrument sees a raw call in a synthetic file ---" -ForegroundColor Cyan
    # A scan that missed raw calls would pass everything, so a synthetic file with two (a pipe and a
    # -InputObject) must be counted, and the seam's own raw call and the test folder's must not be.
    $r = New-FakeRepo "instrument"
    Write-FakeFile "core/raw.ps1" "`$a = '{}' | ConvertFrom-Json`n`$b = ConvertFrom-Json -InputObject '{}'`n"
    $counts = Get-HordeRawJsonParseCounts -Root $r
    Check ([int]$counts["core/raw.ps1"] -eq 2 -and $counts.Count -eq 1) ("the scan counts the 2 raw calls in a synthetic file, and only that file (" + $counts.Count + " file(s) counted)")
    $f = @(Test-HordeRawJsonParse -Root $r)
    Check ($f.Count -eq 1 -and $f[0].path -ceq "core/raw.ps1") "the synthetic raw call is the one finding"
    if ($f.Count -ne 1) { Show $f }

    Write-Host ""
    Write-Host "--- this repository ---" -ForegroundColor Cyan
    $f = @(Test-HordeRawJsonParse -Root $root)
    $counts = Get-HordeRawJsonParseCounts -Root $root
    Check ($f.Count -eq 0 -and $counts.Count -eq 0) ("no shipped file calls ConvertFrom-Json outside core/JsonText.ps1 (" + $counts.Count + " files), and the allowlist is empty")
    if ($f.Count -gt 0) { Show $f }
} finally {
    Remove-Item -LiteralPath $fake -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "no shipped file calls ConvertFrom-Json at all (the allowlist is closed), and the scan can go red"
