# DOES ANY SHIPPED FILE CALL ConvertFrom-Json ITSELF BEYOND WHAT core/json-parse-allowlist.txt ALLOWS?
#
# Issue #274: PowerShell 7's ConvertFrom-Json reads a date-shaped string as a [datetime], and the
# decisions module refused its own records under 7. ConvertFrom-HordeJson (core/JsonText.ps1) is the one
# parse that keeps strings strings under both shells; tools/RawJsonParse.ps1 holds every other file to
# a list that only shrinks. This suite first proves the scan refuses what it must, on throwaway
# repositories, each with EXACTLY ONE finding per refusal so a case cannot pass for the wrong reason
# (as test/test-host-names.ps1 does); then it proves the instrument sees a raw call known to be in this
# repository; then it runs the scan on this repository.

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
    # One listed file with two raw calls, the seam with raw calls of its own, a clean file that only
    # MENTIONS the cmdlet in a comment and a string, and a test folder with a raw call. Every case
    # starts from it and changes one thing.
    param([string]$Name)
    $script:repo = Join-Path $fake $Name
    Write-FakeFile "core/json-parse-allowlist.txt" "# exceptions`ncore/old.ps1 | 2 | not yet moved`n"
    Write-FakeFile "core/old.ps1" "`$a = '{}' | ConvertFrom-Json`n`$b = ConvertFrom-Json -InputObject '{}'`n"
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
    Write-Host "--- CONTROL: a repository whose raw calls are all listed, exactly, passes ---" -ForegroundColor Cyan
    $f = @(Scan "clean" { })
    Check ($f.Count -eq 0) "a listed file with exactly its listed calls passes; the seam, a comment, a string and a test folder are not findings"
    if ($f.Count -gt 0) { Show $f }

    Write-Host ""
    Write-Host "--- what the scan refuses ---" -ForegroundColor Cyan
    Refuses "unlisted" { Write-FakeFile "decisions/new.ps1" "`$x = '{}' | ConvertFrom-Json`n" } "calls ConvertFrom-Json 1 time(s) and is not on the allowlist" "a raw call in a file not on the list is a finding"
    Refuses "prefixed" { Write-FakeFile "decisions/new.ps1" "`$x = Microsoft.PowerShell.Utility\ConvertFrom-Json '{}'`n" } "is not on the allowlist" "a raw call written with its module prefix is a finding too"
    Refuses "more" { Write-FakeFile "core/old.ps1" "`$a = '{}' | ConvertFrom-Json`n`$b = '{}' | ConvertFrom-Json`n`$c = '{}' | ConvertFrom-Json`n" } "more than the 2 listed" "a listed file with a new raw call is a finding"
    Refuses "fewer" { Write-FakeFile "core/old.ps1" "`$a = '{}' | ConvertFrom-Json`n`$b = ConvertFrom-HordeJson '{}'`n" } "fewer than the 2 listed" "a listed file with fewer calls than listed is a finding: the list only shrinks"
    Refuses "none-left" { Write-FakeFile "core/old.ps1" "`$a = ConvertFrom-HordeJson '{}'`n" } "is listed but has no raw ConvertFrom-Json call" "a listed file with no raw call left is a finding: its line must go"
    Refuses "gone" { Remove-Item -LiteralPath (Join-Path $script:repo "core/old.ps1") } "is listed but has no raw ConvertFrom-Json call" "a listed file that is gone is a finding"
    Refuses "malformed" { Write-FakeFile "core/json-parse-allowlist.txt" "core/old.ps1 | 2 | not yet moved`ncore/x.ps1 | many | why`n" } "line 2 is not" "a malformed allowlist line is a finding"
    Refuses "zero" { Write-FakeFile "core/json-parse-allowlist.txt" "core/old.ps1 | 2 | not yet moved`ncore/x.ps1 | 0 | why`n" } "line 2 is not" "a count of 0 is refused: a file with no raw call has no line"
    Refuses "twice" { Write-FakeFile "core/json-parse-allowlist.txt" "core/old.ps1 | 2 | not yet moved`ncore/old.ps1 | 2 | again`n" } "is listed twice" "a file listed twice is a finding"
    # With the old file moved to the seam, so the missing list is the ONLY thing wrong.
    Refuses "no-list" { Remove-Item -LiteralPath (Join-Path $script:repo "core/json-parse-allowlist.txt"); Write-FakeFile "core/old.ps1" "`$a = ConvertFrom-HordeJson '{}'`n" } "the allowlist is missing" "a missing allowlist is a finding, not an empty pass"
    Refuses "unparsable" { Write-FakeFile "core/old.ps1" "`$a = '{}' | ConvertFrom-Json`n`$b = ConvertFrom-Json -InputObject '{}'`nfunction broken {`n" } "does not parse" "a file that does not parse is a finding, never a pass"

    Write-Host ""
    Write-Host "--- the instrument sees a raw call known to be in this repository ---" -ForegroundColor Cyan
    # agents/claude-code/Conversation.ps1 parses each transcript line with ConvertFrom-Json itself (its
    # own -DateKind switch, line 164 when the seam landed). A scan that missed it would pass everything.
    $known = "agents/claude-code/Conversation.ps1"
    $counts = Get-HordeRawJsonParseCounts -Root $root
    Check ([int]$counts[$known] -ge 1) ("the scan counts the raw calls in " + $known + " (" + $counts[$known] + ")")
    # And the real repository goes RED when one real file is left off a copy of its list.
    $partialList = Join-Path $fake "allowlist-without-one.txt"
    New-Item -ItemType Directory -Force $fake | Out-Null
    $kept = @([System.IO.File]::ReadAllLines((Join-Path $root "core\json-parse-allowlist.txt")) | Where-Object { -not $_.StartsWith($known + " ") })
    [System.IO.File]::WriteAllLines($partialList, $kept)
    $f = @(Test-HordeRawJsonParse -Root $root -AllowlistPath $partialList)
    $ok = ($f.Count -eq 1 -and $f[0].path -ceq $known -and ("" + $f[0].problem) -like "*is not on the allowlist*")
    Check $ok ("with " + $known + " left off the list, the real repository fails on exactly that file")
    if (-not $ok) { Show $f }

    Write-Host ""
    Write-Host "--- this repository ---" -ForegroundColor Cyan
    $f = @(Test-HordeRawJsonParse -Root $root)
    Check ($f.Count -eq 0) ("every raw ConvertFrom-Json outside core/JsonText.ps1 is listed, exactly (" + $counts.Count + " files)")
    if ($f.Count -gt 0) { Show $f }
} finally {
    Remove-Item -LiteralPath $fake -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "no shipped file calls ConvertFrom-Json beyond what the shrinking allowlist says, and the scan can go red"
