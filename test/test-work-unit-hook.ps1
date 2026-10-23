# DOES THE WORK-UNIT HOOK RECORD AGENTS AND WARGS FROM THE HARNESS'S OWN EVENTS, AND NEVER BLOCK OR FAIL A SESSION?
#
# hooks/horde-work-unit.mjs is the SubagentStart, SubagentStop and SessionEnd hook (T-0326). test/work-unit-hook.test.mjs
# drives the real .mjs as a process with real JSON payloads on stdin, against a fleet.db of its own under the temp folder,
# and is run under node and read back as [PASS]/[FAIL] lines (as test/test-fleet-db.ps1 does) so that tools/Mutate.ps1 can
# break the hook and require these checks to notice. It covers: an agent recorded with the harness's own id (exactly the id in
# the subagent transcript's file name), its parent, task (first line only), work type (explicit marker only), model and lane;
# the repeat of a start or a stop; a stop that fills in the task a start could not read; a warg ended by its session end and
# nothing else ended; and every failure (no home, bad stdin, a locked or foreign database) exiting 0 and silent, in bounded time.
# Every test names a profile folder of its own first; nothing real is read or written.
#
# NODE 24 IS NEEDED (node:sqlite). Without it nothing runs, it says so, and the suite exits 3, never 0.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

$node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) {
    Write-Host "  [SKIP] no node here: the hook cannot run" -ForegroundColor Yellow
    Complete-HordeSuite -Success "NOTHING RUN: no node" -PassCode 3
}

$test = Join-Path $root "test\work-unit-hook.test.mjs"
Check (Test-Path -LiteralPath $test -PathType Leaf) "CONTROL: the work-unit hook test file is found"
$first = Get-Content -LiteralPath $test | Where-Object { $_ -cmatch '^import ' } | Select-Object -First 1
Check ($first -ceq "import '../fleet-db/test/own-profile.mjs';") "the test file imports own-profile.mjs first, so it never reaches the real profile"

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
Check ($seen -ge 15) ("CONTROL: the tests actually ran (" + $seen + " results read)")
Check ($code -eq 0) ("node reports no failed test (exit " + $code + ")")

Complete-HordeSuite -Success "the work-unit hook records agents and wargs by the harness events and never blocks a session"
