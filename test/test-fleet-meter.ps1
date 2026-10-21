# DOES THE FLEET METER COUNT EACH REQUEST ONCE, STAY IDEMPOTENT, ALERT ONCE AND ONLY WHEN IT SHOULD?
#
# The meter's node:test suites (fleet-metrics/test and every agents/<name>/metrics/test), run under node
# and read back as [PASS]/[FAIL] lines, so that tools/Mutate.ps1 - which needs a suite that prints those -
# can break the meter's code and require these tests to notice. Each node test becomes one check; the
# TAP reporter is used because its lines are plain ASCII. All the tests use synthetic transcripts and a
# Horde home of their own under the temp folder; nothing real is read or written.
#
# NODE 24 IS NEEDED (node:sqlite). Without it nothing runs, it says so, and the suite exits 3, never 0.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

$node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) {
    Write-Host "  [SKIP] no node here: the fleet meter cannot run" -ForegroundColor Yellow
    Complete-HordeSuite -Success "NOTHING RUN: no node" -PassCode 3
}

$tests = @()
$tests += @(Get-ChildItem -Path (Join-Path $root "fleet-metrics\test") -Filter "*.test.mjs" -File)
foreach ($d in @(Get-ChildItem -Path (Join-Path $root "agents") -Directory)) {
    $mt = Join-Path $d.FullName "metrics\test"
    if (Test-Path -LiteralPath $mt) { $tests += @(Get-ChildItem -Path $mt -Filter "*.test.mjs" -File) }
}
Check ($tests.Count -ge 5) ("CONTROL: the meter's test files are found (" + $tests.Count + ")")

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $node.Source
$psi.Arguments = "--test --test-reporter=tap " + (($tests | ForEach-Object { '"' + $_.FullName + '"' }) -join " ")
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$p = [System.Diagnostics.Process]::Start($psi)
$errTask = $p.StandardError.ReadToEndAsync()
$out = $p.StandardOutput.ReadToEnd()
if (-not $p.WaitForExit(180000)) { try { $p.Kill() } catch { } ; Check $false "the node tests ended within 3 minutes" }
$code = $p.ExitCode
$p.Dispose()

$seen = 0
foreach ($l in ($out -split "`r?`n")) {
    if ($l -cmatch '\Aok \d+ - (.+)\z') { Check $true $Matches[1]; $seen++ }
    elseif ($l -cmatch '\Anot ok \d+ - (.+)\z') { Check $false $Matches[1]; $seen++ }
}
Check ($seen -ge 55) ("CONTROL: the tests actually ran (" + $seen + " results read)")
Check ($code -eq 0) ("node reports no failed test (exit " + $code + ")")

Complete-HordeSuite -Success "the fleet meter's node tests all pass"
