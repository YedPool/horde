# DOES THE SUITE HELPER FAIL A SUITE THAT HAS A PROBLEM, AND ONLY THEN?
#
# Each fixture under test/fixtures/suite is a tiny suite built on test/lib/Suite.ps1, run as its own
# process. The helper is what every other suite trusts to turn a problem into a non-zero exit, so it
# is tested the way it will be used.

$ErrorActionPreference = "Continue"
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
Check ($v.out -like "*an error no test expected*missing*") "and the error is named, with its line"
Check ($v.out -like "*a check after the error still runs*") "and the checks after it still run"

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
