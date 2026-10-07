# IS A FOLDER OF PINNED FILES HELD TO ITS LIST, BYTE FOR BYTE?
#
# core/Fingerprints.ps1 is what an adapter asks before it loads a file that is not Horde's own text,
# and what tools/HostNames.ps1 asks before it lets such a file past the ASCII rule (decisions design,
# 2026-10-06, section 3.11). Every case here is a folder this suite made in %TEMP% and removes.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\Fingerprints.ps1")

$work = Join-Path $env:TEMP ("horde-fingerprints-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null

$bytesA = [byte[]](0x4D, 0x5A, 0x00, 0xFF, 0x90, 0x00, 0x03)
$bytesB = [System.Text.Encoding]::ASCII.GetBytes("a second file`n")
function Get-Sha { param([byte[]]$Bytes) $h = [System.Security.Cryptography.SHA256]::Create(); try { return (-join ($h.ComputeHash($Bytes) | ForEach-Object { $_.ToString("x2") })) } finally { $h.Dispose() } }
$shaA = Get-Sha $bytesA
$shaB = Get-Sha $bytesB

function New-Case {
    # A folder holding a.dll and b.txt and a list of both; -List replaces the list, -Change edits the folder.
    param([string]$Name, $List = $null, [scriptblock]$Change = $null)
    $dir = Join-Path $work $Name
    New-Item -ItemType Directory -Path $dir | Out-Null
    [System.IO.File]::WriteAllBytes((Join-Path $dir "a.dll"), $bytesA)
    [System.IO.File]::WriteAllBytes((Join-Path $dir "b.txt"), $bytesB)
    $text = "# the pinned files`r`n`r`na.dll | " + $shaA + " | the first invented file, from nowhere`r`nb.txt | " + $shaB + " | the second`r`n"
    if ($null -ne $List) { $text = $List }
    [System.IO.File]::WriteAllText((Join-Path $dir "fingerprints.txt"), $text)
    if ($null -ne $Change) { & $Change $dir }
    return $dir
}
function Says { param($R, [string]$Text) return (@($R.findings | Where-Object { "$_".Contains($Text) }).Count -gt 0) }

try {

Write-Host ""
Write-Host "--- a folder that matches its list ---" -ForegroundColor Cyan
Check ((Get-HordeFingerprintListName) -ceq "fingerprints.txt") "the list is fingerprints.txt"
$ok = Test-HordeFingerprints -Folder (New-Case "ok")
Check ($ok.ok -eq $true -and @($ok.findings).Count -eq 0) "every listed file there with its fingerprint: ok, and no finding"
Check (@($ok.files).Count -eq 2 -and (Split-Path -Leaf $ok.files[0]) -ceq "a.dll" -and (Split-Path -Leaf $ok.files[1]) -ceq "b.txt" -and [System.IO.Path]::IsPathRooted($ok.files[0])) "the listed files are handed back as full paths, in the list's order"
Check ((Get-HordeFileSha256 -Path (Join-Path $work "ok\a.dll")) -ceq $shaA) "CONTROL: a file's fingerprint is its SHA-256, in lowercase hex"

Write-Host ""
Write-Host "--- a folder that does not ---" -ForegroundColor Cyan
$changed = Test-HordeFingerprints -Folder (New-Case "changed" -Change { param($d) $b = [System.IO.File]::ReadAllBytes((Join-Path $d "a.dll")); $b[$b.Length - 1] = 0x04; [System.IO.File]::WriteAllBytes((Join-Path $d "a.dll"), $b) })
Check ($changed.ok -eq $false -and (Says $changed "a.dll does not match its fingerprint") -and @($changed.findings).Count -eq 1) "one changed byte: not ok, and the file is named"
Check (@($changed.files).Count -eq 1 -and (Split-Path -Leaf $changed.files[0]) -ceq "b.txt") "and the changed file is not among the files handed back"
$gone = Test-HordeFingerprints -Folder (New-Case "gone" -Change { param($d) Remove-Item -LiteralPath (Join-Path $d "b.txt") })
Check ($gone.ok -eq $false -and (Says $gone "b.txt is listed and is not there") -and @($gone.findings).Count -eq 1) "a listed file that is missing: not ok"
$noList = Test-HordeFingerprints -Folder (New-Case "nolist" -Change { param($d) Remove-Item -LiteralPath (Join-Path $d "fingerprints.txt") })
Check ($noList.ok -eq $false -and (Says $noList "so nothing there is pinned") -and @($noList.files).Count -eq 0) "a folder with no list: not ok, and no file is handed back"
$empty = Test-HordeFingerprints -Folder (New-Case "empty" -List "# nothing`r`n")
Check ($empty.ok -eq $false -and (Says $empty "lists no file")) "a list that names no file: not ok"

Write-Host ""
Write-Host "--- a list line that is not one ---" -ForegroundColor Cyan
$good = "a.dll | " + $shaA + " | the first invented file`r`n"
$cases = @(
    @{ name = "two-cells"; line = "b.txt | " + $shaB; says = "is not '<file name> | <sha256> | <what it is and where it came from>'"; what = "a line with no reason" }
    @{ name = "path"; line = "..\ok\b.txt | " + $shaB + " | reaching into another folder"; says = "is not a plain file name in this folder"; what = "a name that is a path" }
    @{ name = "dots"; line = "b..txt | " + $shaB + " | two dots in a name"; says = "is not a plain file name in this folder"; what = "a name holding two dots together" }
    @{ name = "upper"; line = "b.txt | " + $shaB.ToUpperInvariant() + " | the fingerprint in capitals"; says = "gives no SHA-256 for b.txt"; what = "a fingerprint that is not 64 lowercase hex digits" }
    @{ name = "short"; line = "b.txt | " + $shaB.Substring(0, 63) + " | one digit short"; says = "gives no SHA-256 for b.txt"; what = "a fingerprint one digit short" }
    @{ name = "blank-why"; line = "b.txt | " + $shaB + " | "; says = "does not say what b.txt is"; what = "a blank reason" }
    @{ name = "twice"; line = "A.DLL | " + $shaA + " | the first file again, in capitals"; says = "lists A.DLL a second time"; what = "one file listed twice, whatever its case" }
)
foreach ($c in $cases) {
    $r = Test-HordeFingerprints -Folder (New-Case $c.name -List ($good + $c.line + "`r`n"))
    Check ($r.ok -eq $false -and (Says $r $c.says) -and @($r.findings).Count -eq 1) ($c.what + " is a finding, and the folder is not ok")
    Check (@($r.files).Count -eq 1 -and (Split-Path -Leaf $r.files[0]) -ceq "a.dll") ("and it pins nothing: only the well-formed line's file is handed back (" + $c.name + ")")
}
$read = Read-HordeFingerprintList -Path (Join-Path $work "ok\fingerprints.txt")
Check (@($read.entries).Count -eq 2 -and @($read.problems).Count -eq 0 -and $read.entries[0].line -eq 3 -and $read.entries[1].what -ceq "the second") "CONTROL: comments and blank lines are skipped, each entry keeps its line number and its reason"

} finally {
    if ((Split-Path -Leaf $work) -match '\Ahorde-fingerprints-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force }
}

Complete-HordeSuite -Success "a pinned folder is ok only when every listed file is there with exactly its fingerprint"
