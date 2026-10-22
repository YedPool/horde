# DOES FLEET.DB REFUSE EVERY ROW ITS RULES EXIST TO STOP?
#
# fleet.db's node:test suites (fleet-db/test), run under node and read back as [PASS]/[FAIL] lines, so that
# tools/Mutate.ps1 - which needs a suite that prints those - can break the schema and require these tests
# to notice. Each node test becomes one check; the TAP reporter is used because its lines are plain ASCII.
# Every test makes a database of its own under the temp folder; nothing real is read or written.
#
# NODE 24 IS NEEDED (node:sqlite). Without it nothing runs, it says so, and the suite exits 3, never 0.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

$node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) {
    Write-Host "  [SKIP] no node here: fleet.db cannot run" -ForegroundColor Yellow
    Complete-HordeSuite -Success "NOTHING RUN: no node" -PassCode 3
}

$tests = @(Get-ChildItem -Path (Join-Path $root "fleet-db\test") -Filter "*.test.mjs" -File)
Check ($tests.Count -ge 1) ("CONTROL: the fleet.db test files are found (" + $tests.Count + ")")
# A test with an empty environment falls back to the system's home folder; own-profile.mjs points that at a
# temp folder, so no test reaches the real pointer file and the real fleet.db. It must be every file's first import.
$unguarded = @($tests | Where-Object { -not ((Get-Content -LiteralPath $_.FullName | Where-Object { $_ -cmatch '^import ' } | Select-Object -First 1) -ceq "import './own-profile.mjs';") } | ForEach-Object { $_.Name })
Check ($unguarded.Count -eq 0) ("every fleet.db test file imports own-profile.mjs first, so none reaches the real profile (" + ($unguarded -join ", ") + ")")

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
Check ($seen -ge 40) ("CONTROL: the tests actually ran (" + $seen + " results read)")
Check ($code -eq 0) ("node reports no failed test (exit " + $code + ")")

Complete-HordeSuite -Success "fleet.db's rules all hold"
