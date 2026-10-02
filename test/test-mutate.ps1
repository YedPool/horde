# DOES THE MUTATION TOOL TELL THE TRUTH? A tool that reports "every mutation caught" is only worth
# what it would report when that is false. So it is run on a tiny fixture twice: once with an honest
# spec it must accept, and once with a spec made of every way a mutation run can lie - a survivor not
# declared as one, a find that never applied, a find that matches more than once, and a gap declared
# without a reason - each of which it must reject.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
$tool = Join-Path $root "tools\Mutate.ps1"

$target = Join-Path $root "test\fixtures\mutate\target.ps1"
$before = [System.IO.File]::ReadAllText($target)
# THIS RUN'S FOLDERS CARRY ITS OWN TAG. Every run of the tool below gets -RunTag, so the throwaway
# folders this suite causes are named horde-mutate-<tag>-<guid>, and only those are counted at the end.
# Counting "new since the suite started" was wrong once other agents ran mutations at the same time.
$runTag = "t" + [guid]::NewGuid().ToString("N").Substring(0, 12)
function Get-OwnLeftovers { return @(Get-ChildItem -LiteralPath $env:TEMP -Directory -Filter ("horde-mutate-" + $runTag + "-*") -ErrorAction SilentlyContinue) }
# ANOTHER AGENT'S RUN, STARTED WHILE THIS SUITE RUNS. Parallel mutation runs are the normal case: on
# 2026-09-30 two other agents' runs had horde-mutate-* folders in the shared TEMP during a gate, and
# the check below blamed this suite for them. A folder in that exact name form appears while this
# suite runs and is still there at the end, as a live run's would be. It is not this suite's.
$foreign = Join-Path $env:TEMP ("horde-mutate-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $foreign | Out-Null

$honest = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-honest.psd1" | ForEach-Object { "$_" })
$honestCode = $LASTEXITCODE
Check ($honestCode -eq 0) "an honest spec - one caught mutation, one declared gap - passes"
Check (@($honest | Where-Object { $_ -match '\[OK\] tested-rule: caught' }).Count -eq 1) "the caught mutation is reported as caught"
Check (@($honest | Where-Object { $_ -match '\[FAIL\] Get-Two returns two' }).Count -eq 1) "and the failing assertion that caught it is named"

$lying = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-dishonest.psd1" | ForEach-Object { "$_" })
$lyingCode = $LASTEXITCODE
Check ($lyingCode -ne 0) "a spec with any dishonest mutation fails the run"
Check (@($lying | Where-Object { $_ -match '\[BAD\] silent-survivor: survived' }).Count -eq 1) "a survivor that was not declared as one is rejected"
Check (@($lying | Where-Object { $_ -match '\[BAD\] never-applied: did not apply: the find string occurs 0 times' }).Count -eq 1) "a mutation whose find string never matched is rejected, not counted as caught"
Check (@($lying | Where-Object { $_ -match '\[BAD\] ambiguous: did not apply: the find string occurs [2-9]' }).Count -eq 1) "a find string that matches more than once is rejected"
Check (@($lying | Where-Object { $_ -match '\[BAD\] gap-without-reason: invalid' }).Count -eq 1) "a gap declared without a reason is rejected"

# "CAUGHT" MUST MEAN A CHECK FAILED. The third review ran an always-failing suite with a mutation that
# changed nothing, and the tool reported it caught.
$bb = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-bad-baseline.psd1" | ForEach-Object { "$_" })
$bbCode = $LASTEXITCODE
Check ($bbCode -eq 2 -and @($bb | Where-Object { $_ -match 'UNMUTATED suite does not pass' }).Count -eq 1) "a suite that fails before any mutation is refused, so nothing can be counted as caught"
Check (@($bb | Where-Object { $_ -match '\[OK\]' }).Count -eq 0) "and no mutation is reported against it"
$hang = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-hangs.psd1" -TimeoutSeconds 3 | ForEach-Object { "$_" })
$hangCode = $LASTEXITCODE
Check ($hangCode -eq 2 -and @($hang | Where-Object { $_ -match 'ran past 3s' }).Count -eq 1) "a suite that runs past its time limit is stopped and reported, not waited on forever"
$crash = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-crash.psd1" | ForEach-Object { "$_" })
$crashCode = $LASTEXITCODE
Check ($crashCode -ne 0 -and @($crash | Where-Object { $_ -match '\[BAD\] breaks-the-file: the mutant does not parse' }).Count -eq 1) "a mutation that does not parse is not counted as caught"
$rt = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-runtime-crash.psd1" | ForEach-Object { "$_" })
$rtCode = $LASTEXITCODE
Check ($rtCode -ne 0 -and @($rt | Where-Object { $_ -match '\[BAD\] throws-at-run-time: the suite broke' }).Count -eq 1) "a mutation that only crashes the suite is not counted as caught"

$hc = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-helper-crash.psd1" | ForEach-Object { "$_" })
$hcCode = $LASTEXITCODE
Check ($hcCode -ne 0 -and @($hc | Where-Object { $_ -match '\[BAD\] throws-under-the-helper: the suite broke' }).Count -eq 1) "a mutant that crashes a suite built on the shared helper is not counted as caught"

# A SPEC'S ENVIRONMENT IS ITS OWN. A suite that needs a variable for mutation runs (test-projection's
# HORDE_SKIP_REALITY) gets it from the spec, set for that run and cleared after, never from whatever
# shell started the tool (review of PR #31, finding 5).
$envRun = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -Spec "test\fixtures\mutate\spec-environment.psd1" | ForEach-Object { "$_" })
$envCode = $LASTEXITCODE
Check ($envCode -eq 0 -and @($envRun | Where-Object { $_ -match '\[OK\] tested-rule: caught' }).Count -eq 1) "a spec's environment reaches every run of its suite"
Check ("$env:HORDE_MUTATE_FIXTURE_ENV" -eq "") "CONTROL: the variable was not set by the shell that ran the tool"
$envBad = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -Spec "test\fixtures\mutate\spec-environment-bad.psd1" | ForEach-Object { "$_" })
Check ($LASTEXITCODE -ne 0 -and @($envBad | Where-Object { $_ -match 'only HORDE_' }).Count -ge 1) "a spec may set only HORDE_ variables"

# A PASS CODE COUNTS AS A PASS ONLY WHERE A SPEC DECLARES IT: a suite that skipped part of itself
# exits 3, and only a spec with PassCodes = @(3) reads that as passing (second review of PR #31, 4).
$pcRun = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -Spec "test\fixtures\mutate\spec-passcodes.psd1" | ForEach-Object { "$_" })
Check ($LASTEXITCODE -eq 0 -and @($pcRun | Where-Object { $_ -match '\[OK\] tested-rule: caught' }).Count -eq 1) "a spec that declares a pass code accepts it as a pass"
$pcUndeclared = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -Spec "test\fixtures\mutate\spec-passcodes-undeclared.psd1" | ForEach-Object { "$_" })
Check ($LASTEXITCODE -eq 2 -and @($pcUndeclared | Where-Object { $_ -match 'UNMUTATED suite does not pass' }).Count -eq 1) "a pass code a spec does not declare is not a pass"

# -Only RUNS THE NAMED MUTANTS, and refuses a name the spec does not have (second review of PR #31, 9).
$onlyRun = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -Spec "test\fixtures\mutate\spec-honest.psd1" -Only "tested-rule" | ForEach-Object { "$_" })
Check ($LASTEXITCODE -eq 0 -and @($onlyRun | Where-Object { $_ -match 'known-gap' }).Count -eq 0 -and @($onlyRun | Where-Object { $_ -match '^mutations: 1,' }).Count -eq 1) "-Only runs just the named mutants"
$onlyBad = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -Spec "test\fixtures\mutate\spec-honest.psd1" -Only "no-such-mutant" | ForEach-Object { "$_" })
Check ($LASTEXITCODE -eq 2 -and @($onlyBad | Where-Object { $_ -match 'no-such-mutant' }).Count -ge 1) "-Only refuses a mutant the spec does not have"

Check ([System.IO.File]::ReadAllText($target) -eq $before) "the working tree's copy of the target is never modified"
$left = @(Get-OwnLeftovers)
Check ($left.Count -eq 0) "and no throwaway copy is left behind"
Check (Test-Path -LiteralPath $foreign) "CONTROL: another run's folder was there all along, and was not counted"
# CONTROL: a folder carrying this run's tag IS counted, so the check can see a real leftover.
$mine = Join-Path $env:TEMP ("horde-mutate-" + $runTag + "-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $mine | Out-Null
Check (@(Get-OwnLeftovers).Count -eq 1) "CONTROL: a leftover with this run's tag is counted"
Remove-Item -LiteralPath $mine -Recurse -Force
Remove-Item -LiteralPath $foreign -Recurse -Force

Complete-HordeSuite -Success "the mutation tool rejects every way a mutation run can lie"
