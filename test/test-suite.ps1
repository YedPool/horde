# DOES THE SUITE HELPER FAIL A SUITE THAT HAS A PROBLEM, AND ONLY THEN?
#
# Each fixture under test/fixtures/suite is a tiny suite built on test/lib/Suite.ps1, run as its own
# process. The helper is what every other suite trusts to turn a problem into a non-zero exit, so it
# is tested the way it will be used.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

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
Write-Host "--- every suite is built the same way ---" -ForegroundColor Cyan

# Checked on the syntax tree of every test/test-*.ps1: the helper cannot protect a suite that forgets
# its trap line, forgets to end through Complete-HordeSuite, or exits early. The review of this
# helper measured each of the three leaving a failed check with exit 0.
$suites = @(Get-ChildItem -LiteralPath (Join-Path $root "test") -Filter "test-*.ps1" -File | Where-Object { $_.Extension -ceq ".ps1" })
Check ($suites.Count -ge 4) ("CONTROL: the scan finds the suites (" + $suites.Count + ")")
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
Write-Host "--- controls ---" -ForegroundColor Cyan
$c = Invoke-Fixture "caught"
Check ($c.code -eq 0) "CONTROL: an error a test catches on purpose does not fail the suite"
$k = Invoke-Fixture "clean"
Check ($k.code -eq 0 -and $k.out -like "*==== clean ====*") "CONTROL: a clean suite passes and says what passing proves"

Complete-HordeSuite -Success "the suite helper fails a suite exactly when something is wrong"
