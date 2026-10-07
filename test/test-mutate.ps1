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
# NO RUN BELOW INHERITS A VERIFY SETTING. A gate may run this suite with HORDE_MUTATE_VERIFY_MAPS=1 in
# its environment, and that would confirm the catches the -Fast checks below need left unverified.
# Cleared for this suite's own process, which is all a run of the tool below inherits from; the
# checks that are about the variable set it themselves.
$env:HORDE_MUTATE_VERIFY_MAPS = $null
# The one line a gate outside this repository accepts as a spec's result, matched whole, and only
# as the LAST line of the output.
$classicLine = '^mutations: (\d+), as expected: (\d+), not: (\d+)$'
function Get-LastLine { param([string[]]$Lines) return "$(@($Lines) | Select-Object -Last 1)" }
function Get-LineBeforeLast { param([string[]]$Lines) return "$(@($Lines) | Select-Object -Last 2 | Select-Object -First 1)" }

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

# SECTIONS AND -Fast: THE WHOLE SUITE DECIDES UNLESS THE CALLER SAYS -Fast, AND A -Fast RESULT CANNOT
# BE READ AS A GATE'S. Each mutant reran the whole suite when one section would catch it:
# link-contract.psd1 took about 2900 s on the always-on box (issues #82, #83). The fixture suite logs
# the selection of every run, so these checks see the runs the tool made, not only what it reported.
# The shell that runs the tool has a stray HORDE_SECTIONS set: a whole run must still be whole.
$secLog = Join-Path $env:TEMP ("horde-mutate-seclog-" + [guid]::NewGuid().ToString("N") + ".txt")
$keepSel = $env:HORDE_SECTIONS; $keepLog = $env:HORDE_MUTATE_SECTIONS_LOG
try {
    $env:HORDE_SECTIONS = "four"; $env:HORDE_MUTATE_SECTIONS_LOG = $secLog
    $sec = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-sections.psd1" -Fast | ForEach-Object { "$_" })
    $secCode = $LASTEXITCODE
    $secRuns = @(); if (Test-Path -LiteralPath $secLog) { $secRuns = @([System.IO.File]::ReadAllLines($secLog)) }
    [System.IO.File]::WriteAllText($secLog, "")
    $whole = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-sections.psd1" | ForEach-Object { "$_" })
    $wholeCode = $LASTEXITCODE
    $wholeRuns = @([System.IO.File]::ReadAllLines($secLog))
    [System.IO.File]::WriteAllText($secLog, "")
    # HORDE_MUTATE_VERIFY_MAPS IS "1", "0" OR NOTHING: "true" read as "do not verify" and said nothing
    # (review of #115, round 3, finding F2).
    $keepVm = $env:HORDE_MUTATE_VERIFY_MAPS
    try {
        $env:HORDE_MUTATE_VERIFY_MAPS = "true"
        $vmBad = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-sections.psd1" | ForEach-Object { "$_" })
        $vmBadCode = $LASTEXITCODE
    } finally { $env:HORDE_MUTATE_VERIFY_MAPS = $keepVm }
    $vmBadRuns = @([System.IO.File]::ReadAllLines($secLog))
    [System.IO.File]::WriteAllText($secLog, "")
    $bad = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-sections-bad.psd1" | ForEach-Object { "$_" })
    $badCode = $LASTEXITCODE
    $badRuns = @([System.IO.File]::ReadAllLines($secLog))
    [System.IO.File]::WriteAllText($secLog, "")
    $senv = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-sections-env.psd1" -Fast | ForEach-Object { "$_" })
    $senvCode = $LASTEXITCODE
    $senvRuns = @([System.IO.File]::ReadAllLines($secLog))
} finally {
    $env:HORDE_SECTIONS = $keepSel; $env:HORDE_MUTATE_SECTIONS_LOG = $keepLog
    if (Test-Path -LiteralPath $secLog) { Remove-Item -LiteralPath $secLog -Force }
}
$nosuite = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-sections-nosuite.psd1" | ForEach-Object { "$_" })
$nosuiteCode = $LASTEXITCODE

# WITHOUT -Fast A MAP IS NOT USED: every run is whole, and the last line is the one a gate reads.
Check ($wholeCode -eq 0) ("a spec with a section map passes a plain run (exit " + $wholeCode + ")")
# The runs, in order: the baseline, the four mutants, the baseline again - no run on a selection.
Check (($wholeRuns -join " | ") -ceq "run sections=[] | run sections=[] | run sections=[] | run sections=[] | run sections=[] | run sections=[]") ("without -Fast every mutant, mapped or not, runs the whole suite once, and no map gets a baseline (" + ($wholeRuns -join " | ") + ")")
Check (@($whole | Where-Object { $_ -match '\[OK\] mapped: caught \(expected caught\) \[map \(two\) not used: a map is used only under -Fast\]' }).Count -eq 1) "and a mapped mutant's line says its map was not used"
Check ((Get-LastLine $whole) -cmatch $classicLine -and (Get-LastLine $whole) -ceq "mutations: 4, as expected: 4, not: 0") ("the last line of a plain run is the classic result line and nothing more (" + (Get-LastLine $whole) + ")")
Check ((Get-LineBeforeLast $whole) -ceq "maps: sectioned 0, misses 0, hides 0") ("the map counts have the line before it (" + (Get-LineBeforeLast $whole) + ")")
Check (@($whole | Where-Object { $_ -match 'MAP-MISS|MAP-HIDES|unverified' }).Count -eq 0) "CONTROL: a plain run names no map miss and leaves nothing unverified"
Check ("mutations: 4, as expected: 4, not: 0, map misses: 1, unverified catches: 1" -cnotmatch $classicLine) "CONTROL: the line the earlier form printed does not match the gate's pattern, so the pattern can tell the two apart"

# AN UNKNOWN VALUE OF THE VARIABLE IS REFUSED BEFORE ANYTHING RUNS.
Check ($vmBadCode -eq 2) ("HORDE_MUTATE_VERIFY_MAPS=true is refused with exit 2 (exit " + $vmBadCode + ")")
Check ($vmBadRuns.Count -eq 0) ("and no suite ran, baseline included (" + ($vmBadRuns -join " | ") + ")")
Check ($vmBad.Count -eq 0) ("and nothing is printed where a result is read: the refusal is on stderr (" + ($vmBad -join " | ") + ")")

# WITH -Fast A MAPPED MUTANT RUNS ITS SECTIONS.
Check ($secCode -eq 0) ("a -Fast run of a spec with a section map, one map miss and one declared survivor exits 0 (exit " + $secCode + ")")
Check (@($sec | Where-Object { $_ -match '\[OK\] mapped: caught \(expected caught\)' }).Count -eq 1) "a mutant its sections catch is reported caught"
Check (@($sec | Where-Object { $_ -match '\[FAIL\] Get-Two returns two' }).Count -eq 1) "and the check in its section that caught it is named"
# The runs, in order: the whole baseline; a baseline of each distinct map (two, four); mapped in its
# section; map-miss in its section, then whole; survivor in its section, then whole; unmapped whole;
# the whole baseline again, and each map's baseline again.
$wantRuns = "run sections=[] | run sections=[two] | run sections=[four] | run sections=[two] | run sections=[two] | run sections=[] | run sections=[four] | run sections=[] | run sections=[] | run sections=[] | run sections=[two] | run sections=[four]"
Check (($secRuns -join " | ") -ceq $wantRuns) ("under -Fast the tool ran each mapped mutant in its sections only, reran on the whole suite only what passed them, and ran the baselines and the unmapped mutant whole, whatever the shell's HORDE_SECTIONS (" + ($secRuns -join " | ") + ")")
Check (@($sec | Where-Object { $_ -match '\[OK\] map-miss: caught \(expected caught\)' }).Count -eq 1) "a mutant its sections miss and the whole suite catches is caught: a pass of its sections is never a survival"
Check (@($sec | Where-Object { $_ -match '\[MAP-MISS\] map-miss: its sections \(two\) passed; the whole suite caught it' }).Count -eq 1) "and is named as a map miss, so the map gets fixed"
Check (@($sec | Where-Object { $_ -match '\[FAIL\] Get-Three returns three' }).Count -eq 1) "with the check that caught it in the whole suite"
Check (@($sec | Where-Object { $_ -match '\[OK\] survivor: survived \(expected survives\)' }).Count -eq 1) "a mutant that survives its sections and then the whole suite is a survivor"
Check (@($sec | Where-Object { $_ -match 'MAP-MISS\] (mapped|survivor|unmapped)' }).Count -eq 0) "CONTROL: only the map miss is named one"
Check (@($sec | Where-Object { $_ -match '\[OK\] mapped: caught \(expected caught\) \[sections: two\] unverified: the whole suite was not run' }).Count -eq 1) "a catch made by its sections alone says it is unverified"
Check ((Get-LastLine $sec) -ceq "mutations (fast, unverified catches: 1 - not gate evidence): 4, as expected: 4, not: 0") ("and the last line of that run counts it and says the run is not gate evidence (" + (Get-LastLine $sec) + ")")
Check ((Get-LastLine $sec) -cnotmatch $classicLine -and @($sec | Where-Object { $_ -cmatch $classicLine }).Count -eq 0) "so no line of a -Fast run with an unverified catch matches the gate's pattern"
Check ((Get-LineBeforeLast $sec) -ceq "maps: sectioned 3, misses 1, hides 0") ("the line before it counts the mutants run on their sections and the map misses (" + (Get-LineBeforeLast $sec) + ")")

Check ($badCode -eq 1) ("a spec whose map is wrong fails the run (exit " + $badCode + ")")
Check (@($bad | Where-Object { $_ -match "\[BAD\] misspelt: invalid: section 'tow' is not one test\\fixtures\\mutate\\suite-sections\.ps1 declares" }).Count -eq 1) "a mapped section the suite does not declare is refused, not run - in a plain run too, where the map is not used"
Check (@($bad | Where-Object { $_ -match '\[BAD\] empty-map: invalid: its Sections names no section' }).Count -eq 1) "an empty map is refused, not read as a whole run"
Check (@($bad | Where-Object { $_ -match '\[OK\] good: caught' }).Count -eq 1) "CONTROL: a good map in the same spec runs"
Check (($badRuns -join " | ") -ceq "run sections=[] | run sections=[] | run sections=[]") ("a refused mutant never runs: the baseline, the one good mutant, the baseline (" + ($badRuns -join " | ") + ")")
Check ($nosuiteCode -eq 1 -and @($nosuite | Where-Object { $_ -match '\[BAD\] mapped-nowhere: invalid: .*suite\.ps1 declares no sections' }).Count -eq 1) "a map on a suite that declares no sections is refused"
Check ($senvCode -eq 1 -and @($senv | Where-Object { $_ -match "\[BAD\] outside: invalid: section 'four' is outside the spec's own HORDE_SECTIONS" }).Count -eq 1) "a mutant mapped outside the spec's own section filter is refused"
Check (@($senv | Where-Object { $_ -match '\[OK\] inside: caught' }).Count -eq 1) "CONTROL: one mapped inside it runs"
Check (($senvRuns -join " | ") -ceq "run sections=[two,three] | run sections=[two] | run sections=[two] | run sections=[two,three] | run sections=[two]") ("the spec's own filter is the whole run for its baselines (" + ($senvRuns -join " | ") + ")")

# A CATCH ONLY A SECTION MAKES IS NO CATCH, AND THE PLAIN RUN MUST SAY SO (review of #115, rounds 2
# and 3). Section "use" computes its value when run alone and reads a cache the section before it
# filled when run whole; the mutant breaks only the computing path. Its section catches it; the whole
# suite never sees it. The plain run - what every gate runs - printed it [OK], caught, and exited 0
# until the whole suite became every plain run's verdict.
$cold = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-sections-cache.psd1" | ForEach-Object { "$_" })
$coldCode = $LASTEXITCODE
Check ($coldCode -eq 1 -and @($cold | Where-Object { $_ -match '\[BAD\] cold-path: survived \(expected caught\)' }).Count -eq 1) ("a plain run reports the mutant only its section catches as the survivor it is (exit " + $coldCode + ")")
Check (@($cold | Where-Object { $_ -match '\[OK\]' }).Count -eq 0) "and prints it as caught nowhere"
Check ((Get-LastLine $cold) -cmatch $classicLine -and (Get-LastLine $cold) -ceq "mutations: 1, as expected: 0, not: 1") ("and counts it as not expected on the classic last line (" + (Get-LastLine $cold) + ")")
# -Fast IS A REVIEWER'S TOOL: the section's catch stands, and the run cannot be read as a result.
# Run with HORDE_MUTATE_VERIFY_MAPS=0, which is accepted and forces nothing.
$keepVm = $env:HORDE_MUTATE_VERIFY_MAPS
try {
    $env:HORDE_MUTATE_VERIFY_MAPS = "0"
    $coldF = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-sections-cache.psd1" -Fast | ForEach-Object { "$_" })
    $coldFCode = $LASTEXITCODE
} finally { $env:HORDE_MUTATE_VERIFY_MAPS = $keepVm }
Check ($coldFCode -eq 0 -and @($coldF | Where-Object { $_ -match '\[OK\] cold-path: caught .* unverified' }).Count -eq 1) ("CONTROL: under -Fast, with HORDE_MUTATE_VERIFY_MAPS=0 accepted, its section's catch stands, marked unverified - the gap is real on this fixture (exit " + $coldFCode + ")")
Check ((Get-LastLine $coldF) -cnotmatch $classicLine) ("the last line of that -Fast run does not match the gate's pattern (" + (Get-LastLine $coldF) + ")")
Check ((Get-LastLine $coldF) -ceq "mutations (fast, unverified catches: 1 - not gate evidence): 1, as expected: 1, not: 0") "and names the number of unverified catches"
# A GATE CAN FORCE VERIFICATION WHATEVER ITS CALLER PASSES: HORDE_MUTATE_VERIFY_MAPS=1 beats -Fast.
$keepVm = $env:HORDE_MUTATE_VERIFY_MAPS
try {
    $env:HORDE_MUTATE_VERIFY_MAPS = "1"
    $coldE = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-sections-cache.psd1" -Fast | ForEach-Object { "$_" })
    $coldECode = $LASTEXITCODE
} finally { $env:HORDE_MUTATE_VERIFY_MAPS = $keepVm }
Check ($coldECode -eq 1 -and @($coldE | Where-Object { $_ -match '\[BAD\] cold-path: survived \(expected caught\)' }).Count -eq 1) ("HORDE_MUTATE_VERIFY_MAPS=1 with -Fast verifies: the whole suite's survival stands (exit " + $coldECode + ")")
Check (@($coldE | Where-Object { $_ -match '\[MAP-HIDES\] cold-path: its sections \(use\) caught it and the whole suite did not' }).Count -eq 1) "and the mutant is named as one its map hides"
Check ((Get-LineBeforeLast $coldE) -ceq "maps: sectioned 1, misses 0, hides 1") ("and counted as one (" + (Get-LineBeforeLast $coldE) + ")")
Check ((Get-LastLine $coldE) -cmatch $classicLine -and (Get-LastLine $coldE) -ceq "mutations: 1, as expected: 0, not: 1") ("with nothing left unverified, the last line is the classic one (" + (Get-LastLine $coldE) + ")")
# -Fast -VerifyMaps IS THE SAME CHECK OF THE MAPS, asked for on the command line.
$honestV = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-sections.psd1" -Fast -VerifyMaps | ForEach-Object { "$_" })
$honestVCode = $LASTEXITCODE
Check ($honestVCode -eq 0 -and @($honestV | Where-Object { $_ -match '\[OK\] mapped: caught \(expected caught\) \[sections: two\] verified by the whole suite' }).Count -eq 1) ("CONTROL: an honest map passes -Fast -VerifyMaps, its catch confirmed by the whole suite (exit " + $honestVCode + ")")
Check ((Get-LineBeforeLast $honestV) -ceq "maps: sectioned 3, misses 1, hides 0" -and (Get-LastLine $honestV) -ceq "mutations: 4, as expected: 4, not: 0") ("and a -Fast run with every catch confirmed ends in the classic line (" + (Get-LineBeforeLast $honestV) + " / " + (Get-LastLine $honestV) + ")")

# EVERY MAP HAS A BASELINE OF ITS OWN, UNDER -Fast. A section that fails when run without the ones
# before it would "catch" every mutant mapped to it - here a mutant its section never even checks.
$dep = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-sections-dependent.psd1" -Fast | ForEach-Object { "$_" })
Check ($LASTEXITCODE -eq 2 -and @($dep | Where-Object { $_ -match 'UNMUTATED suite does not pass when only its sections use run' }).Count -eq 1) "a map whose sections fail unmutated is refused before any mutant runs"
Check (@($dep | Where-Object { $_ -match '\[OK\]|\[BAD\]' }).Count -eq 0) "and no mutant is reported against it, so none can read as caught"
$noisy = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-sections-noisy.psd1" -Fast | ForEach-Object { "$_" })
Check ($LASTEXITCODE -eq 2 -and @($noisy | Where-Object { $_ -match 'sections quiet run \(exited 3 but printed a failed check or an error\)' }).Count -eq 1) "a map's baseline that exits 3 yet prints an [ERROR] is not a pass"
$silent = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-sections-silent.psd1" -Fast | ForEach-Object { "$_" })
Check ($LASTEXITCODE -eq 2 -and @($silent | Where-Object { $_ -match 'sections silent run \(exited 1\)' }).Count -eq 1) "a map's baseline that exits 1 with nothing printed is not a pass either"
# THE WHOLE-SUITE RERUN NEVER ACCEPTS 3. Exit 3 is a pass only for a run of a map's sections; a whole
# rerun that exits 3 skipped part of the suite, and is no survival (review of #115).
$e3 = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-sections-exit3.psd1" -Fast | ForEach-Object { "$_" })
Check (@($e3 | Where-Object { $_ -match '\[BAD\] rerun-exits-3: the suite broke \(exit 3\) with no failed check' }).Count -eq 1) "a whole rerun that exits 3 is a broken run, never a survivor"
# A TIMEOUT IS NEVER A SURVIVAL: a mutant declared to survive that hangs the suite is bad (review of #115).
$hs = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-hangs-survives.psd1" -TimeoutSeconds 20 | ForEach-Object { "$_" })
Check ($LASTEXITCODE -eq 1 -and @($hs | Where-Object { $_ -match '\[BAD\] hangs: timed out after 20s - not a catch \(expected survives\)' }).Count -eq 1) "a hanging mutant declared to survive is reported bad, timed out"

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
