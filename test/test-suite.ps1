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
. (Join-Path $root "test\lib\SuiteSections.ps1")

function Invoke-Fixture {
    # Run one fixture suite; returns { code; out }. Streams read through the process API, not 2>&1.
    # -Vars sets variables for this fixture's process only. HORDE_SECTIONS and HORDE_FIXTURE_FAIL_IN
    # are always cleared unless given, so a value in the shell that runs this suite cannot pick a
    # fixture's sections for it.
    param([string]$Name, [hashtable]$Vars = @{})
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    foreach ($k in @("HORDE_SECTIONS", "HORDE_FIXTURE_FAIL_IN")) { if ($psi.EnvironmentVariables.ContainsKey($k)) { $psi.EnvironmentVariables.Remove($k) } }
    foreach ($k in @($Vars.Keys)) { $psi.EnvironmentVariables[$k] = "$($Vars[$k])" }
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
    foreach ($rel in @("test/test-a.ps1", "hosts/h/test/test-b.ps1", "transports/t/test/test-c.ps1", "agents/g/test/test-d.ps1", "messengers/m/test/test-e.ps1", "messengers/m/test/Fixture.ps1",
                       "test/fixtures/x/test-data.ps1", "tools/test-stray.ps1", "transports/t/test/deep/test-deeper.ps1", "transports/t/test-beside.ps1", "test/lib/test-lib.ps1", "test/test-notes.txt")) {
        $p = Join-Path $plant $rel
        New-Item -ItemType Directory -Path (Split-Path -Parent $p) -Force | Out-Null
        [System.IO.File]::WriteAllText($p, "# planted")
    }
    $plantedSuites = @(Get-HordeSuiteFiles -Root $plant | ForEach-Object { $_.Name })
    Check (($plantedSuites -join ",") -ceq "test-a.ps1,test-b.ps1,test-c.ps1,test-d.ps1,test-e.ps1") ("CONTROL: in a planted tree the gate list is exactly the five suite folders' test-*.ps1 files, a messenger's fixture not among them (" + ($plantedSuites -join ",") + ")")
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
    $trapless = @(Get-HordeSectionTrapProblems -Path $s.FullName)
    if ($trapless.Count -gt 0) { Check $false ($s.Name + ": every section carries its own trap line (" + ($trapless -join "; ") + ")") }
}
# CONTROL: the section trap check, on a planted suite, names the section without a trap and only it.
$plantTrap = Join-Path $env:TEMP ("horde-sectrap-" + [guid]::NewGuid().ToString("N") + ".ps1")
try {
    [System.IO.File]::WriteAllText($plantTrap, ("if (Enter-HordeSuiteSection `"kept`" `"t`") {`r`n    trap { Register-HordeSuiteError `$_; continue }`r`n    Check `$true `"x`"`r`n}`r`nif (Enter-HordeSuiteSection `"bare`" `"t`") {`r`n    Check `$true `"y`"`r`n}`r`nif (`$x) { Check `$true `"not a section`" }`r`n"))
    $pt = @(Get-HordeSectionTrapProblems -Path $plantTrap)
    Check ($pt.Count -eq 1 -and $pt[0] -like "line 5: section bare has 0 trap lines*") ("CONTROL: the check names a section without its own trap, and no other (" + ($pt -join "; ") + ")")
} finally { if (Test-Path -LiteralPath $plantTrap) { Remove-Item -LiteralPath $plantTrap -Force } }

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
Write-Host "--- sections, for mutation runs ---" -ForegroundColor Cyan
# A mutation spec maps each mutant to the sections that kill it, and tools\Mutate.ps1 runs only those
# (HORDE_SECTIONS). The selection must never read as a whole pass, and a wrong name must never read as
# a caught mutant: Mutate.ps1 counts a catch only from a [FAIL] line.
$sAll = Invoke-Fixture "sections"
Check ($sAll.code -eq 0 -and $sAll.out -like "*[[]PASS] the alpha check*" -and $sAll.out -like "*[[]PASS] the beta check*") "with no selection every section runs and the suite exits 0"
$sOne = Invoke-Fixture "sections" -Vars @{ HORDE_SECTIONS = "alpha" }
Check ($sOne.code -eq 3) ("a run that skipped a section exits 3, never 0 (exit " + $sOne.code + ")")
Check ($sOne.out -like "*[[]PASS] the alpha check*" -and $sOne.out -notlike "*the beta check*" -and $sOne.out -like "*[[]SKIP] section beta*") "only the selected section runs, and the skipped one says so"
$sBoth = Invoke-Fixture "sections" -Vars @{ HORDE_SECTIONS = " beta , alpha " }
Check ($sBoth.code -eq 0) "selecting every section is a whole run: exit 0"
$sFail = Invoke-Fixture "sections" -Vars @{ HORDE_SECTIONS = "alpha"; HORDE_FIXTURE_FAIL_IN = "alpha" }
Check ($sFail.code -eq 1 -and $sFail.out -like "*[[]FAIL] the alpha check*") "a failed check in a selected section exits 1, not 3"
$sSkipFail = Invoke-Fixture "sections" -Vars @{ HORDE_SECTIONS = "alpha"; HORDE_FIXTURE_FAIL_IN = "beta" }
Check ($sSkipFail.code -eq 3) "CONTROL: a failing check in a section that was not selected never runs"
$sBad = Invoke-Fixture "sections" -Vars @{ HORDE_SECTIONS = "alpha,alhpa" }
$badFails = @(($sBad.out -split "`r?`n") | Where-Object { $_ -match '^\s*\[FAIL\]' })
Check ($sBad.code -eq 1 -and $sBad.out -like "*[[]ERROR]*alhpa*") "a selection naming a section the suite does not have fails the run, naming it"
Check ($badFails.Count -eq 0) ("and as an [ERROR], never a [FAIL], so a typo in a map cannot read as a caught mutant (" + $badFails.Count + " [FAIL] lines)")
$sEmpty = Invoke-Fixture "sections" -Vars @{ HORDE_SECTIONS = " , " }
Check ($sEmpty.code -eq 1 -and $sEmpty.out -like "*[[]ERROR]*names no section*") "a selection that names nothing is an error, not a whole run"
$sUn = Invoke-Fixture "sections-unentered"
Check ($sUn.code -eq 1 -and $sUn.out -like "*[[]ERROR]*beta*never entered*") "a declared section the suite never enters fails the suite"
$sUd = Invoke-Fixture "sections-undeclared"
Check ($sUd.code -eq 1 -and $sUd.out -like "*[[]ERROR]*gamma*not declared*") "entering a section that was never declared fails the suite"
$sCh = Invoke-Fixture "sections-child" -Vars @{ HORDE_SECTIONS = "alpha" }
Check ($sCh.code -eq 0 -and $sCh.out -like "*[[]PASS] the alpha check*") "CONTROL: the selected section ran"
Check ($sCh.out.Contains("child saw []")) ("a selection never reaches what a suite starts: the child saw no HORDE_SECTIONS (review of #115, B2)" + $(if (-not $sCh.out.Contains("child saw []")) { " - " + (@(($sCh.out -split "`r?`n") | Where-Object { $_ -like "*child saw*" }) -join " ") } else { "" }))
# A CHECK AFTER AN ERROR IN A SECTION STILL RUNS, as one after an error at top level does ("a check
# cannot vanish" above): the section's own trap resumes inside the section.
$sEr = Invoke-Fixture "sections-error"
Check ($sEr.code -eq 1 -and $sEr.out -like "*[[]ERROR]*boom*" -and $sEr.out -like "*[[]FAIL] the check after the error*") "an error in a section does not skip the checks after it in that section"
$sTw = Invoke-Fixture "sections-twice"
Check ($sTw.code -eq 1 -and $sTw.out -like "*[[]ERROR]*declares its sections more than once*") "a suite that declares its sections twice fails"
Check ($sTw.out -like "*[[]ERROR]*section alpha is entered twice*") "a section entered twice fails the suite"
$sId = Invoke-Fixture "sections-badids"
Check ($sId.code -eq 1 -and $sId.out -like "*[[]ERROR]*section id 'Alpha' is not lowercase*") "a section id a selection could not name exactly is refused"
Check ($sId.out -like "*[[]ERROR]*section id 'beta' is declared twice*") "a section id declared twice is refused"

Write-Host ""
Write-Host "--- controls ---" -ForegroundColor Cyan
$c = Invoke-Fixture "caught"
Check ($c.code -eq 0) "CONTROL: an error a test catches on purpose does not fail the suite"
$k = Invoke-Fixture "clean"
Check ($k.code -eq 0 -and $k.out -like "*==== clean ====*") "CONTROL: a clean suite passes and says what passing proves"

Complete-HordeSuite -Success "the suite helper fails a suite exactly when something is wrong"
