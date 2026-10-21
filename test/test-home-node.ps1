# DOES THE NODE SIDE FIND ITS HOME BY THE FLEET'S ONE RULE, AND REFUSE A BAD POINTER BY NAME?
#
# core/home.mjs: HORDE_HOME, else the pointer file <USERPROFILE>\.horde-home.json, else REFUSED (no default folder).
# fleet-db/test/home.test.mjs, run under node and read back as [PASS]/[FAIL] lines (as test/test-fleet-db.ps1 does),
# so that tools/Mutate.ps1 can break the module and require these tests to notice. It is the same file test-fleet-db
# runs with the rest of fleet.db's tests; it is run alone here because a mutant of core/home.mjs should not wait for
# the schema tests. Every test names a USERPROFILE and homes it made under the temp folder; nothing real is read.
#
# NODE 24 IS NEEDED (node:sqlite, used by the store the tests open). Without it nothing runs and the suite exits 3.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

$node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) {
    Write-Host "  [SKIP] no node here: the home tests cannot run" -ForegroundColor Yellow
    Complete-HordeSuite -Success "NOTHING RUN: no node" -PassCode 3
}

$test = Join-Path $root "fleet-db\test\home.test.mjs"
Check (Test-Path -LiteralPath $test -PathType Leaf) "CONTROL: the home test file is found"

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $node.Source
$psi.Arguments = "--test --test-reporter=tap `"" + $test + "`""
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$p = [System.Diagnostics.Process]::Start($psi)
$errTask = $p.StandardError.ReadToEndAsync()
$out = $p.StandardOutput.ReadToEnd()
if (-not $p.WaitForExit(120000)) { try { $p.Kill() } catch { } ; Check $false "the node tests ended within 2 minutes" }
$code = $p.ExitCode
$p.Dispose()

$seen = 0
foreach ($l in ($out -split "`r?`n")) {
    if ($l -cmatch '\Aok \d+ - (.+)\z') { Check $true $Matches[1]; $seen++ }
    elseif ($l -cmatch '\Anot ok \d+ - (.+)\z') { Check $false $Matches[1]; $seen++ }
}
Check ($seen -ge 10) ("CONTROL: the tests actually ran (" + $seen + " results read)")
Check ($code -eq 0) ("node reports no failed test (exit " + $code + ")")

Complete-HordeSuite -Success "the node home rule holds: HORDE_HOME, then the pointer, never a default, a bad pointer refused by name"
