# DOES THE SUITE HELPER FAIL A SUITE THAT HAS A PROBLEM, AND ONLY THEN?
#
# Each fixture under test/fixtures/suite is a tiny suite built on test/lib/Suite.ps1, run as its own
# process. The helper is what every other suite trusts to turn a problem into a non-zero exit, so it
# is tested the way it will be used.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\SuiteFiles.ps1")

function Invoke-Fixture {
    # Run one fixture suite; returns { code; out }. Streams read through the process API, not 2>&1.
    param([string]$Name)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $root ("test\fixtures\suite\" + $Name + ".ps1")) + "`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    $code = $p.ExitCode
    $p.Dispose()
    return [pscustomobject]@{ code = $code; out = ($out + "`n" + $errTask.Result) }
}

Write-Host ""
Write-Host "--- a check cannot vanish ---" -ForegroundColor Cyan
$v = Invoke-Fixture "vanishing"
Check ($v.code -eq 1) "a check whose expression raises an error fails the suite, where it used to vanish"
Check ($v.out -like "*[[]ERROR] an error no test expected (line 6)*missing*") "and the error is named, with its line"
Check ($v.out -like "*[[]PASS] a check after the error still runs*") "and the checks after it still run"
$ns = Invoke-Fixture "nonstopping"
Check ($ns.code -eq 1 -and $ns.out -like "*[[]ERROR]*") "an error that does not stop its statement still fails the suite"

Write-Host ""
Write-Host "--- Throws answers only whether the block threw ---" -ForegroundColor Cyan
Check ((Throws { "noise"; 42 } "x") -eq $false) "a block that prints and returns but does not throw is not a throw"
Check (Throws { throw "expected text" } "expected") "CONTROL: a block that throws with the text is"

Write-Host ""
Write-Host "--- a member a mutant dropped fails a check by name, not the suite with none ---" -ForegroundColor Cyan
$dp = Invoke-Fixture "dropped-plain"
Check ($dp.code -eq 1 -and $dp.out -like "*[[]ERROR]*" -and $dp.out -notmatch '(?m)^\s*\[FAIL\]' -and $dp.out -notlike "*a check after the dropped member*") "CONTROL: read plainly in one big try, a dropped member ends the suite with an error and NO failed check, and skips the checks after it (the crash the mutation nets found)"
$ds = Invoke-Fixture "dropped-safe"
Check ($ds.code -eq 1 -and $ds.out -match "(?m)^\s*\[FAIL\] the Thrall's card counts one run" -and $ds.out -notlike "*[[]ERROR]*" -and $ds.out -like "*[[]PASS] a check after the dropped member*") "read through Get-HordeTestMember, the same dropped member fails the check that names it, with no error, and the checks after it still run"
# The helper itself, under strict mode as the suites that need it run.
$member = & {
    Set-StrictMode -Version Latest
    $o = [pscustomobject]@{ a = [pscustomobject]@{ b = 7; n = $null; list = @(1, 2, 3); one = @("x"); none = @() }; h = @{ k = "v" }; zero = 0; f = $false; s = "" }
    [pscustomobject]@{
        deep = (Get-HordeTestMember $o "a.b"); missing = (Get-HordeTestMember $o "a.c"); missingMid = (Get-HordeTestMember $o "x.y.z")
        throughNull = (Get-HordeTestMember $o "a.n.deeper"); fromNull = (Get-HordeTestMember $null "a"); dict = (Get-HordeTestMember $o "h.k"); dictMissing = (Get-HordeTestMember $o "h.q")
        list = @(Get-HordeTestMember $o "a.list").Count; one = @(Get-HordeTestMember $o "a.one").Count; none = @(Get-HordeTestMember $o "a.none").Count
        hasNull = (Test-HordeTestMember $o "a.n"); hasMissing = (Test-HordeTestMember $o "a.c"); hasDeep = (Test-HordeTestMember $o "a.b"); hasEmptyStep = (Test-HordeTestMember $o "a..b")
        zero = (Get-HordeTestMember $o "zero"); f = (Get-HordeTestMember $o "f"); s = (Get-HordeTestMember $o "s"); caseless = (Get-HordeTestMember $o "A.B")
    }
}
Check ($member.deep -eq 7 -and $member.dict -ceq "v" -and $member.caseless -eq 7) "it reads a member, a dictionary key, and ignores case as PowerShell's own member access does"
Check ($null -eq $member.missing -and $null -eq $member.missingMid -and $null -eq $member.throughNull -and $null -eq $member.fromNull -and $null -eq $member.dictMissing) "a missing member, a missing step, a step through `$null, a `$null object and a missing key each read as `$null, with no error"
Check ($member.list -eq 3 -and $member.one -eq 1 -and $member.none -eq 0) "a list counts under @() as the plain read would"
Check ($member.zero -is [int] -and $member.zero -eq 0 -and $member.f -is [bool] -and -not $member.f -and $member.s -is [string] -and $member.s -ceq "") "a value that is 0, false or empty comes back as itself, not as missing"
Check ($member.hasDeep -eq $true -and $member.hasNull -eq $true -and $member.hasMissing -eq $false -and $member.hasEmptyStep -eq $false) "Test-HordeTestMember tells a member that is `$null from one that is missing, and answers exactly true or false"

Write-Host ""
Write-Host "--- every suite is built the same way ---" -ForegroundColor Cyan

# Checked on the syntax tree of every suite the gate runs - test/test-*.ps1 and each host's,
# transport's and agent harness's <folder>/test/test-*.ps1, as test/lib/SuiteFiles.ps1 lists them: the
# helper cannot protect a suite that forgets its trap line, forgets to end through
# Complete-HordeSuite, or exits early. The review of this helper measured each of the three leaving a
# failed check with exit 0. A suite this scan did not reach would be one nobody checked.
$allSuites = @(Get-HordeSuiteFiles -Root $root)
$inTest = @($allSuites | Where-Object { (Split-Path -Leaf (Split-Path -Parent $_.FullName)) -eq "test" -and (Split-Path -Parent (Split-Path -Parent $_.FullName)) -eq $root })
Check ($inTest.Count -ge 4) ("CONTROL: the scan finds the suites in test/ (" + $inTest.Count + ")")
$sep = [System.IO.Path]::DirectorySeparatorChar
foreach ($family in @("hosts", "transports", "agents")) {
    $mine = @($allSuites | Where-Object { $_.FullName.StartsWith((Join-Path $root $family) + $sep, [System.StringComparison]::OrdinalIgnoreCase) })
    $folders = @(Get-ChildItem -LiteralPath (Join-Path $root $family) -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "test") -PathType Container })
    # Where a family has a test folder, the scan must find its suites.
    if ($folders.Count -gt 0) { Check ($mine.Count -ge 1) ("CONTROL: the scan finds the " + $family + "' suites too (" + $mine.Count + ")") }
    else { Write-Host ("  no " + $family + "/<name>/test/ folder yet; nothing of it to scan") -ForegroundColor DarkGray }
}
$suites = $allSuites

# NO SUITE OUTSIDE THE GATE. Any test-*.ps1 in the repository that the list above does not cover is a
# suite nobody runs (test/fixtures/ is data and is skipped).
# THE MACHINE-BOUND LIST NAMES REAL SUITES, each with its reason: a renamed suite would otherwise drop
# off the list silently and be shipped to a box where it cannot pass (issue #89).
$rootFull = [System.IO.Path]::GetFullPath($root).TrimEnd('\')
$gateRel = @($allSuites | ForEach-Object { $_.FullName.Substring($rootFull.Length + 1).Replace('\', '/') })
$bound = @(Get-HordeMachineBoundSuites)
$unknown = @($bound | Where-Object { $gateRel -cnotcontains $_.path } | ForEach-Object { $_.path })
Check ($bound.Count -ge 4 -and $unknown.Count -eq 0) ("every machine-bound suite is one the gate runs (" + $bound.Count + " listed" + $(if ($unknown.Count) { "; not suites: " + ($unknown -join ", ") } else { "" }) + ")")
Check (@($bound | Where-Object { "$($_.why)".Trim() -eq "" }).Count -eq 0) "and each says why it is bound to this machine"
Check ($gateRel -cnotcontains "test/test-no-such-suite.ps1" -and $gateRel -ccontains "test/test-suite.ps1") "CONTROL: the comparison sees this suite and not one that does not exist"
$stray = @(Get-HordeStraySuiteFiles -Root $root)
Check ($stray.Count -eq 0) ("every test-*.ps1 in the repository is one the gate runs" + $(if ($stray.Count) { " (outside it: " + ($stray -join ", ") + ")" } else { "" }))
# CONTROL: the same check on a planted tree finds what it should and nothing else.
$plant = Join-Path $env:TEMP ("horde-suitefiles-" + [guid]::NewGuid().ToString("N"))
try {
    foreach ($rel in @("test/test-a.ps1", "hosts/h/test/test-b.ps1", "transports/t/test/test-c.ps1", "agents/g/test/test-d.ps1", "messengers/m/test/test-e.ps1", "messengers/m/test/Fixture.ps1", "surfaces/s/test/test-f.ps1",
                       "test/fixtures/x/test-data.ps1", "tools/test-stray.ps1", "transports/t/test/deep/test-deeper.ps1", "transports/t/test-beside.ps1", "test/lib/test-lib.ps1", "test/test-notes.txt")) {
        $p = Join-Path $plant $rel
        New-Item -ItemType Directory -Path (Split-Path -Parent $p) -Force | Out-Null
        [System.IO.File]::WriteAllText($p, "# planted")
    }
    $plantedSuites = @(Get-HordeSuiteFiles -Root $plant | ForEach-Object { $_.Name })
    Check (($plantedSuites -join ",") -ceq "test-a.ps1,test-b.ps1,test-c.ps1,test-d.ps1,test-e.ps1,test-f.ps1") ("CONTROL: in a planted tree the gate list is exactly the six suite folders' test-*.ps1 files, a messenger's fixture not among them (" + ($plantedSuites -join ",") + ")")
    $plantedStray = @(Get-HordeStraySuiteFiles -Root $plant)
    Check (($plantedStray -join ",") -ceq "test/lib/test-lib.ps1,tools/test-stray.ps1,transports/t/test-beside.ps1,transports/t/test/deep/test-deeper.ps1") ("CONTROL: and the stray check names the four planted outside it, and not the fixture (" + ($plantedStray -join ",") + ")")
} finally { if (Test-Path -LiteralPath $plant) { Remove-Item -LiteralPath $plant -Recurse -Force } }
foreach ($s in $suites) {
    $tk = $null; $pe = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($s.FullName, [ref]$tk, [ref]$pe)
    $traps = @($ast.EndBlock.Traps | Where-Object { $null -ne $_ -and $_.Body.Extent.Text -match 'Register-HordeSuiteError' })
    $stmts = @($ast.EndBlock.Statements)
    $last = $null; if ($stmts.Count -gt 0) { $last = $stmts[$stmts.Count - 1] }
    $exits = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ExitStatementAst] }, $true) | Where-Object {
        $p = $_.Parent; $inCatch = $false
        while ($p) { if ($p -is [System.Management.Automation.Language.CatchClauseAst]) { $inCatch = $true; break }; $p = $p.Parent }
        -not $inCatch })
    $ok = ($traps.Count -eq 1 -and $null -ne $last -and $last.Extent.Text -match '^Complete-HordeSuite\b' -and $exits.Count -eq 0)
    $why = @()
    if ($traps.Count -ne 1) { $why += "trap lines: " + $traps.Count }
    if (-not ($null -ne $last -and $last.Extent.Text -match '^Complete-HordeSuite\b')) { $why += "does not end with Complete-HordeSuite" }
    if ($exits.Count -gt 0) { $why += "" + $exits.Count + " exit outside a catch" }
    Check $ok ($s.Name + " declares the trap, ends with Complete-HordeSuite, and never exits early" + $(if ($why.Count) { " (" + ($why -join "; ") + ")" } else { "" }))
}

Write-Host ""
Write-Host "--- a condition must be a boolean ---" -ForegroundColor Cyan
$n = Invoke-Fixture "nonbool"
Check ($n.code -eq 1 -and $n.out -like "*was not true or false*") "a condition that is a list is a failure, not a pass"

Write-Host ""
Write-Host "--- a partial pass is not a pass ---" -ForegroundColor Cyan
# A suite that skipped part of itself on purpose (test-projection's HORDE_SKIP_REALITY) passes with a
# code of its own, so a gate that expects 0 fails loudly rather than reading it as whole (second
# review of PR #31, finding 4).
$pc = Invoke-Fixture "passcode"
Check ($pc.code -eq 3 -and $pc.out -like "*==== partial ====*") "a suite that passes with a pass code exits with that code, not 0"
$pcf = Invoke-Fixture "passcode-fails"
Check ($pcf.code -eq 1) "a suite that fails exits 1 whatever pass code it asked for"

Write-Host ""
Write-Host "--- fail fast, for mutation runs ---" -ForegroundColor Cyan
# A mutant is caught at its first failed check; the rest of the suite proves nothing more about it and
# can take minutes. Under HORDE_FAIL_FAST=1 (set by a mutation spec's Environment) the helper stops at
# the first [FAIL] (second review of PR #31, finding 9).
$keepFF = $env:HORDE_FAIL_FAST
try { $env:HORDE_FAIL_FAST = "1"; $ff = Invoke-Fixture "failfast" } finally { $env:HORDE_FAIL_FAST = $keepFF }
Check ($ff.code -eq 1 -and $ff.out -like "*[[]FAIL] the first failing check*" -and $ff.out -notlike "*the second failing check*") "under fail-fast a suite stops at its first failed check"
$ffOff = Invoke-Fixture "failfast"
Check ($ffOff.code -eq 1 -and $ffOff.out -like "*the second failing check*") "CONTROL: without it every check runs"

Write-Host ""
Write-Host "--- no suite makes a drive letter, which every other process of the user would see ---" -ForegroundColor Cyan
# test/lib/SuiteFiles.ps1 says why. The names this guard looks for are put together from pieces here,
# so that this file does not itself hold what it forbids.
$dosCall = "Define" + "DosDevice"
$substName = "sub" + "st"
$netName = "ne" + "t"
$mapName = "Map" + "NetworkDrive"
$makers = @(Get-HordeDriveLetterMakers -Root $root)
Check ($makers.Count -eq 0) ("no test file makes a drive letter, but for the one that may" + $(if ($makers.Count) { " (THESE DO: " + (@($makers | ForEach-Object { $_.file + " [" + $_.what + "]" }) -join "; ") + ")" } else { "" }))
$allowedFile = Join-Path $root "test\test-path-text.ps1"
$allowedMakes = @(Get-HordeDriveLetterMakersIn -Text ([System.IO.File]::ReadAllText($allowedFile)))
Check ($allowedMakes.Count -eq 1 -and $allowedMakes[0] -ceq $substName) ("CONTROL: the one file that may DOES make one, and this guard sees it there: it is let by because it is that file, not because nothing was found (" + ($allowedMakes -join ", ") + ")")
# WHAT IS A LETTER BEING MADE, AND WHAT ONLY SPEAKS OF ONE.
$makes = [ordered]@{
    "the system call, in a type a suite declares" = ("Add-Type -Namespace T -Name D -MemberDefinition 'public static extern bool " + $dosCall + "(int a, string b, string c);'")
    "the system call, called" = ('$null = [T.D]::' + $dosCall + '(1, "R:", "x")')
    "the command, by its name" = ($substName + ' R: C:\Windows')
    "the command, by its file name and the call operator" = ('$null = & ' + $substName + '.exe ($letter + ":") $folder')
    "the command, by its whole path" = ('& C:\Windows\System32\' + $substName + '.exe R: /D')
    "the command, in a line handed to another shell" = ('cmd.exe /c "' + $substName + ' R: C:\Windows"')
    "a network drive mapped by the old command" = ($netName + ' use R: \\server\share')
    "the same by its file name" = ('& ' + $netName + '.exe use * \\server\share')
    "the same in a line handed to another shell" = ('cmd /c "' + $netName + ' use R: \\server\share"')
    "a network drive mapped by the newer command" = 'New-SmbMapping -LocalPath R: -RemotePath \\server\share'
    "a PowerShell drive made to last, which is a mapped drive" = 'New-PSDrive -Name R -PSProvider FileSystem -Root \\server\share -Persist'
    "a network drive mapped through the scripting object" = ('(New-Object -ComObject WScript.Network).' + $mapName + '("R:", "\\server\share")')
}
foreach ($case in $makes.Keys) { Check (@(Get-HordeDriveLetterMakersIn -Text $makes[$case]).Count -eq 1) ("a file is caught making a drive letter: " + $case) }
$speaks = [ordered]@{
    "a comment that names all of them" = ("# " + $dosCall + ", " + $substName + " R: C:\x and " + $netName + " use R: \\s\s were here once")
    "a check's own words about such a drive" = ('Check $true "by a ' + $substName + ' drive it is the same file, and ' + $netName + ' use is not used"')
    "a PowerShell drive of the process's own" = 'New-PSDrive -Name R -PSProvider FileSystem -Root C:\Windows -Scope Script'
    "the old command asked for something else" = ($netName + ' view')
    "a variable and a function that only hold the letters" = ('$' + $substName + 'itute = 1; function Get-' + $substName + 'Thing { }')
    "an empty file" = ""
    "a file that does not parse" = 'function {{{ "'
}
foreach ($case in $speaks.Keys) { Check (@(Get-HordeDriveLetterMakersIn -Text $speaks[$case]).Count -eq 0) ("CONTROL: a file is NOT caught for: " + $case) }
Check ((@(Get-HordeDriveLetterMakersIn -Text ($makes["the command, by its name"] + "`n" + $makes["the system call, called"] + "`n" + $makes["the command, by its file name and the call operator"])) -join ",") -ceq ($dosCall + "," + $substName)) "everything a file does is named, each once"
# A TREE OF THIS SUITE'S OWN: who is caught, who is let by, and that it is the one file by its place.
$letterTree = Join-Path $env:TEMP ("horde-suite-letters-" + [guid]::NewGuid().ToString("N"))
foreach ($made in @("test\lib", "test\fixtures\x", "hosts\h1\test", "tools")) { [void][System.IO.Directory]::CreateDirectory((Join-Path $letterTree $made)) }
$clean = 'Check $true "nothing here"'
[System.IO.File]::WriteAllText((Join-Path $letterTree "test\test-clean.ps1"), $clean)
[System.IO.File]::WriteAllText((Join-Path $letterTree "test\test-path-text.ps1"), $makes["the command, by its file name and the call operator"])
[System.IO.File]::WriteAllText((Join-Path $letterTree "test\test-breaks.ps1"), $makes["the system call, called"])
[System.IO.File]::WriteAllText((Join-Path $letterTree "test\lib\Helper.ps1"), $makes["the command, by its name"])
[System.IO.File]::WriteAllText((Join-Path $letterTree "test\fixtures\x\racer.ps1"), $makes["a network drive mapped by the old command"])
[System.IO.File]::WriteAllText((Join-Path $letterTree "hosts\h1\test\test-host.ps1"), $clean)
[System.IO.File]::WriteAllText((Join-Path $letterTree "hosts\h1\test\test-path-text.ps1"), $makes["the command, by its name"])
[System.IO.File]::WriteAllText((Join-Path $letterTree "tools\Tool.ps1"), $makes["the command, by its name"])
$inTree = @(Get-HordeDriveLetterMakers -Root $letterTree)
$inTreeSaid = (@($inTree | ForEach-Object { $_.file + "=" + $_.what }) -join "; ")
Check ($inTreeSaid -ceq ("hosts/h1/test/test-path-text.ps1=" + $substName + "; test/fixtures/x/racer.ps1=" + $netName + " use; test/lib/Helper.ps1=" + $substName + "; test/test-breaks.ps1=" + $dosCall)) ("in a tree with four files that break the rule, each is caught and named with what it does: a suite, a helper beside the suites, a fixture a suite runs, and a file of the allowed NAME in another folder (" + $inTreeSaid + ")")
Check (@($inTree | Where-Object { $_.file -ceq "test/test-path-text.ps1" }).Count -eq 0) "the one file that may is let by, though it makes one"
Check (@($inTree | Where-Object { $_.file -ceq "test/test-clean.ps1" -or $_.file -ceq "hosts/h1/test/test-host.ps1" }).Count -eq 0) "CONTROL: a suite that makes none is not named"
Check (@($inTree | Where-Object { $_.file -like "tools/*" }).Count -eq 0) "what is no test file is not this guard's"
[System.IO.File]::WriteAllText((Join-Path $letterTree "test\test-breaks.ps1"), $clean)
[System.IO.File]::Delete((Join-Path $letterTree "test\lib\Helper.ps1")); [System.IO.File]::Delete((Join-Path $letterTree "test\fixtures\x\racer.ps1")); [System.IO.File]::Delete((Join-Path $letterTree "hosts\h1\test\test-path-text.ps1"))
Check (@(Get-HordeDriveLetterMakers -Root $letterTree).Count -eq 0) "CONTROL: with those four mended, the same tree is clean"
if ((Split-Path -Leaf $letterTree) -match '\Ahorde-suite-letters-[0-9a-f]{32}\z') { Remove-Item -LiteralPath $letterTree -Recurse -Force }
Check (-not (Test-Path -LiteralPath $letterTree)) "the tree is removed"

Write-Host ""
Write-Host "--- controls ---" -ForegroundColor Cyan
$c = Invoke-Fixture "caught"
Check ($c.code -eq 0) "CONTROL: an error a test catches on purpose does not fail the suite"
$k = Invoke-Fixture "clean"
Check ($k.code -eq 0 -and $k.out -like "*==== clean ====*") "CONTROL: a clean suite passes and says what passing proves"

Complete-HordeSuite -Success "the suite helper fails a suite exactly when something is wrong"
