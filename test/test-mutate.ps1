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
Check (@($hc | Where-Object { $_ -match '^\s+\[ERROR\] an error no test expected' }).Count -ge 1) ("and the error that broke it is shown under it, so the reader sees which read broke the suite (" + (@($hc | Select-Object -Last 4) -join " | ") + ")")

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

# A SPEC'S Shells (T-0422). The fixture's Get-EditionTwo takes a branch only PowerShell 7 takes, as the
# local transport's owner read does, so a mutant of that branch is one only a run under 7 can see.
$shellsTarget = Join-Path $root "test\fixtures\mutate\target-shells.ps1"
$shellsBefore = [System.IO.File]::ReadAllText($shellsTarget)
. (Join-Path $root "tools\MutateShells.ps1")
$pwshHere = (Get-HordeMutateShellExe -Shell "pwsh").ok
# A SPEC WITH NO Shells RUNS UNDER 5.1 ALONE, as before: the mutant 7 alone could see survives, and its
# output has no per-shell lines.
$sd = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-shells-default.psd1" | ForEach-Object { "$_" })
Check ($LASTEXITCODE -eq 0 -and @($sd | Where-Object { $_ -match '\[OK\] only-7-sees: survived \(expected survives\)' }).Count -eq 1) ("a spec with no Shells runs under 5.1 alone, where the mutant only 7 sees survives (" + (@($sd | Select-Object -Last 3) -join " | ") + ")")
Check (@($sd | Where-Object { $_ -match '^\s+under ' }).Count -eq 0) "and a one-shell run prints no per-shell lines: it reads as it did before Shells"
# A Shells LIST THAT IS NOT TWO KNOWN NAMES IS REFUSED before anything runs.
$sb = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-shells-bad-name.psd1" | ForEach-Object { "$_" })
Check ($LASTEXITCODE -eq 2 -and @($sb | Where-Object { $_ -match "Shells names 'cmd'" }).Count -eq 1 -and @($sb | Where-Object { $_ -match '^mutations: not run' }).Count -eq 1) "a Shells entry that is not powershell or pwsh is refused, not run"
$se = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-shells-empty.psd1" | ForEach-Object { "$_" })
Check ($LASTEXITCODE -eq 2 -and @($se | Where-Object { $_ -match 'Shells is empty' }).Count -eq 1) "an empty Shells is refused"
# NO pwsh.exe WHERE THE MSI PUTS IT: NOT RUN, exit 2 - never a quiet run under 5.1 alone. The tool is
# pointed at a Program Files that has no PowerShell 7 in it, the one place it looks.
# Not named horde-mutate-*: that is the tool's own folder form, which a parallel run's leftover check reads.
$noPf = Join-Path $env:TEMP ("horde-nopwsh-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $noPf | Out-Null
$savedPf = $env:ProgramW6432
try {
    $env:ProgramW6432 = $noPf
    $sm = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-shells-both.psd1" | ForEach-Object { "$_" })
    $smCode = $LASTEXITCODE
} finally { $env:ProgramW6432 = $savedPf; Remove-Item -LiteralPath $noPf -Recurse -Force }
Check ($smCode -eq 2 -and @($sm | Where-Object { $_ -match '^mutations: not run - pwsh is not on this machine' }).Count -eq 1) ("a spec that asks for pwsh where there is none is NOT RUN, exit 2 (" + $smCode + ": " + (@($sm | Select-Object -Last 2) -join " | ") + ")")
Check (@($sm | Where-Object { $_ -match '\[OK\]|\[BAD\]' }).Count -eq 0) "and no mutant is run or reported for it"
Check (@($sm | Where-Object { $_ -match [regex]::Escape($noPf + "\PowerShell\7\pwsh.exe") }).Count -eq 1) "and it names the one path it looked for"
if ($pwshHere) {
    # BOTH SHELLS: the mutant only 7 sees is caught - by 7 - and both outcomes are printed.
    $sboth = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-shells-both.psd1" | ForEach-Object { "$_" })
    $sbothCode = $LASTEXITCODE
    $i7 = [array]::IndexOf([string[]]$sboth, @($sboth | Where-Object { $_ -match '\[OK\] only-7-sees: caught' } | Select-Object -First 1)[0])
    Check ($sbothCode -eq 0 -and $i7 -ge 0) ("with both shells, the mutant only 7 sees is caught (" + $sbothCode + ": " + (@($sboth | Select-Object -Last 8) -join " | ") + ")")
    Check ($i7 -ge 0 -and $i7 + 2 -lt $sboth.Count -and $sboth[$i7 + 1] -match '^\s+under powershell: survived$' -and $sboth[$i7 + 2] -match '^\s+under pwsh: caught$') "and each shell's outcome is printed under it: survived under 5.1, caught under 7"
    Check (@($sboth | Where-Object { $_ -match '\[FAIL\] Get-EditionTwo returns two under Core' }).Count -eq 1) "and the check that caught it under 7 is named"
    # A CATCH BY A LATER SHELL AFTER AN EARLIER ONE BROKE is still a catch: the first shell's run broke
    # with no failed check, the second failed one (review of PR 497, finding 1 - without this case, a
    # rule that read only the first shell's outcome gave the same answers as the real one).
    $ib = [array]::IndexOf([string[]]$sboth, @($sboth | Where-Object { $_ -match '\[OK\] broken-under-5-1-caught-under-7: caught' } | Select-Object -First 1)[0])
    Check ($ib -ge 0 -and $ib + 2 -lt $sboth.Count -and $sboth[$ib + 1] -match '^\s+under powershell: the suite broke \(exit [0-9]+\) with no failed check - not a catch$' -and @($sboth[($ib + 2)..([Math]::Min($ib + 4, $sboth.Count - 1))] | Where-Object { $_ -match '^\s+under pwsh: caught$' }).Count -eq 1) ("a mutant that breaks the suite under 5.1 and fails a check under 7 is caught, by 7 (" + (@($sboth | Where-Object { $_ -match 'broken-under|under ' }) -join " | ") + ")")
    Check (@($sboth | Where-Object { $_ -match '\[OK\] both-see: caught' }).Count -eq 1 -and @($sboth | Where-Object { $_ -match '^mutations: 3, as expected: 3, not: 0' }).Count -eq 1) "a mutant both shells see is caught too, and the total counts each mutant once"
    # A DECLARED SURVIVOR MUST SURVIVE IN EVERY SHELL.
    $ss = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-shells-survivor.psd1" | ForEach-Object { "$_" })
    Check ($LASTEXITCODE -eq 1 -and @($ss | Where-Object { $_ -match '\[BAD\] only-7-sees: caught \(expected survives\)' }).Count -eq 1) "a mutant declared to survive that one shell catches is rejected"
    # A BASELINE ONLY 7 BREAKS STOPS THE RUN, naming the shell.
    $s7 = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -RunTag $runTag -Spec "test\fixtures\mutate\spec-shells-baseline-7.psd1" | ForEach-Object { "$_" })
    Check ($LASTEXITCODE -eq 2 -and @($s7 | Where-Object { $_ -match 'UNMUTATED suite does not pass in the copy under pwsh' }).Count -eq 1 -and @($s7 | Where-Object { $_ -match '\[OK\]|\[BAD\]' }).Count -eq 0) "a suite that fails unmutated under 7 alone is refused, naming the shell, and no mutant is reported"
} else {
    Write-Host "  [NOT RUN] POWERSHELL 7 IS NOT WHERE ITS MSI PUTS IT: the runs under both shells were NOT RUN." -ForegroundColor Yellow
}
Check ([System.IO.File]::ReadAllText($shellsTarget) -eq $shellsBefore) "the working tree's copy of the shells target is never modified"

# THE INSTALLED HORDE IS NEVER MUTATED (T-0466). Run from the copy every session runs `horde` from, the
# tool would break that very code, one mutant at a time. It must say no, before any work, and say it
# in a way a clone's run does not. The installed copy is recognised by the horde.cmd shim beside it, or
# by being bin\horde under the profile (tools\MutateInstalled.ps1).
$instRoot = Join-Path $env:TEMP ("horde-instfx-" + [guid]::NewGuid().ToString("N"))
try {
    $loaded = @("tools\Mutate.ps1", "tools\MutateChanged.ps1", "tools\MutateShells.ps1", "tools\MutateInstalled.ps1", "cli\SetupStore.ps1", "test\lib\SuiteFiles.ps1", "core\Platform.ps1", "core\Tristate.ps1")
    function New-InstFx {
        # A copy of what the tool loads under <Parent>\<Leaf>; returns its folder.
        param([string]$Parent, [string]$Leaf)
        $dir = Join-Path $Parent $Leaf
        foreach ($rel in $loaded) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent (Join-Path $dir $rel)) | Out-Null
            Copy-Item -LiteralPath (Join-Path $root $rel) -Destination (Join-Path $dir $rel)
        }
        return $dir
    }
    function Get-InstFxTree { param([string]$Dir) return (@(Get-ChildItem -LiteralPath $Dir -Recurse -Force | ForEach-Object { $_.FullName + "|" + $_.Length }) -join "`n") }
    $shimText = '"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0horde\horde.ps1" %*'
    # Installed, by its shim: <p1>\horde.cmd launches <p1>\horde\horde.ps1.
    $p1 = Join-Path $instRoot "p1"; New-Item -ItemType Directory -Path $p1 | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $p1 "horde.cmd"), $shimText)
    $inst = New-InstFx -Parent $p1 -Leaf "horde"
    $treeBefore = Get-InstFxTree -Dir $p1
    $ri = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $inst "tools\Mutate.ps1") -RunTag $runTag -Spec "test\fixtures\mutate\spec-honest.psd1" | ForEach-Object { "$_" })
    $riCode = $LASTEXITCODE
    Check ($riCode -eq 2) ("the copy a horde.cmd shim launches is refused with a non-zero exit (" + $riCode + ": " + (@($ri | Select-Object -Last 2) -join " | ") + ")")
    Check (@($ri | Where-Object { $_ -match 'will not run from the installed Horde' -and $_ -match [regex]::Escape("installed Horde, " + $inst + " (") -and $_ -match 'your own clone' }).Count -eq 1) "and the refusal names the path and says to run the clone's own tools\Mutate.ps1"
    Check (@($ri | Where-Object { $_ -match '\[OK\]|\[BAD\]|^mutations:|give -Spec' }).Count -eq 0) "and no mutant is run or reported"
    Check ((Get-InstFxTree -Dir $p1) -eq $treeBefore) "and nothing is written into the installed copy"
    Check (@(Get-OwnLeftovers).Count -eq 0) "and no throwaway copy is made"
    # EVERY CALL FORM IS REFUSED, not only -Spec (round 3 of PR 507: a refusal skipped for -Changed passed
    # every check above). -Changed, -Changed -Plan, and no arguments at all each give the same refusal,
    # exit 2, and leave the tree as it was. The exit-2 check alone cannot tell a skipped refusal from the
    # fixture's own no-git exit 2 for -Changed, which is why the refusal-text and nothing-else checks are here.
    foreach ($form in @(@("-Changed", "origin/main"), @("-Changed", "origin/main", "-Plan"), @())) {
        $formName = $(if ($form.Count -eq 0) { "no arguments" } else { $form -join " " })
        $rf = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $inst "tools\Mutate.ps1") @form | ForEach-Object { "$_" })
        $rfCode = $LASTEXITCODE
        Check ($rfCode -eq 2) ("the installed copy run with " + $formName + " exits 2 (" + $rfCode + ": " + (@($rf | Select-Object -Last 2) -join " | ") + ")")
        Check (@($rf | Where-Object { $_ -match 'will not run from the installed Horde' -and $_ -match [regex]::Escape("installed Horde, " + $inst + " (") -and $_ -match 'your own clone' }).Count -eq 1) ("and with " + $formName + " it gives the refusal, naming the path")
        Check (@($rf | Where-Object { $_ -match '\[OK\]|\[BAD\]|\[SELECT\]|\[SKIP\]|^mutations:|^changed:|give -Spec|-Plan only|-Changed:' }).Count -eq 0) ("and with " + $formName + " nothing else is said or run")
        Check ((Get-InstFxTree -Dir $p1) -eq $treeBefore) ("and with " + $formName + " nothing is written into the installed copy")
    }
    Check (@(Get-OwnLeftovers).Count -eq 0) "and no call form makes a throwaway copy"
    # A CLONE: the same files, in a folder no shim launches, run as before. With no spec it reaches
    # the tool's own usage line - the line the refusal came before.
    $p2 = Join-Path $instRoot "p2"; New-Item -ItemType Directory -Path $p2 | Out-Null
    $clone = New-InstFx -Parent $p2 -Leaf "horde"
    $rc = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $clone "tools\Mutate.ps1") | ForEach-Object { "$_" })
    Check ($LASTEXITCODE -eq 2 -and @($rc | Where-Object { $_ -match 'give -Spec' }).Count -eq 1 -and @($rc | Where-Object { $_ -match 'installed Horde' }).Count -eq 0) "a clone, even one named horde, is not refused: it reaches the tool's own usage line"
    # The unit: every branch of the rule.
    . (Join-Path $root "tools\MutateInstalled.ps1")
    Check ((Get-HordeMutateInstalledRefusal -Repo $inst -ProfileDir (Join-Path $instRoot "nobody")) -ne "") "the shim signal refuses a folder its horde.cmd launches"
    Check ((Get-HordeMutateInstalledRefusal -Repo ($inst.ToUpper()) -ProfileDir (Join-Path $instRoot "nobody")) -ne "") "and the folder's case does not matter"
    Check ((Get-HordeMutateInstalledRefusal -Repo ($inst + "\") -ProfileDir (Join-Path $instRoot "nobody")) -ne "") "and a trailing slash does not matter"
    Check ((Get-HordeMutateInstalledRefusal -Repo $clone -ProfileDir (Join-Path $instRoot "nobody")) -eq "") "CONTROL: a folder with no shim beside it is not refused"
    # A shim that names ANOTHER folder does not make this one the install.
    $p3 = Join-Path $instRoot "p3"; New-Item -ItemType Directory -Path $p3 | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $p3 "horde.cmd"), $shimText)
    $other = New-InstFx -Parent $p3 -Leaf "other"
    Check ((Get-HordeMutateInstalledRefusal -Repo $other -ProfileDir (Join-Path $instRoot "nobody")) -eq "") "a horde.cmd that launches a different folder does not make this one the install"
    # A shim that names the folder by its absolute path.
    $p4 = Join-Path $instRoot "p4"; New-Item -ItemType Directory -Path $p4 | Out-Null
    $abs = New-InstFx -Parent $p4 -Leaf "cli-copy"
    [System.IO.File]::WriteAllText((Join-Path $p4 "horde.cmd"), ('"powershell.exe" -File "' + $abs + '\horde.ps1" %*'))
    Check ((Get-HordeMutateInstalledRefusal -Repo $abs -ProfileDir (Join-Path $instRoot "nobody")) -ne "") "a shim that names the folder by absolute path counts too"
    # The default place: <profile>\bin\horde, with no shim at all.
    $p5 = Join-Path $instRoot "p5"
    $bin = New-InstFx -Parent (Join-Path $p5 "bin") -Leaf "horde"
    $why5 = Get-HordeMutateInstalledRefusal -Repo $bin -ProfileDir $p5
    Check ($why5 -ne "" -and $why5 -match 'bin\\horde folder under the profile') "bin\horde under the profile is refused even with no shim"
    Check ((Get-HordeMutateInstalledRefusal -Repo $bin.ToUpper() -ProfileDir $p5) -ne "") "and the default place is matched whatever the case"
    Check ((Get-HordeMutateInstalledRefusal -Repo ($bin + "\") -ProfileDir $p5) -ne "") "and the default place is matched with a trailing slash"
    Check ((Get-HordeMutateInstalledRefusal -Repo $bin -ProfileDir (Join-Path $instRoot "elsewhere")) -eq "") "CONTROL: the same folder under another profile is not the default place"
    Check ((Get-HordeMutateInstalledRefusal -Repo (New-InstFx -Parent (Join-Path $p5 "bin") -Leaf "horde2") -ProfileDir $p5) -eq "") "CONTROL: a sibling of bin\horde is not refused"
    # ROUND 2 (PR 507 review). Plain folders: only the rule is run, so nothing is copied.
    function New-ShimFx {
        # <Name>\horde.cmd with -Lines, and <Name>\<Leaf> as an empty folder; returns the folder.
        param([string]$Name, [string[]]$Lines, [string]$Leaf = "horde")
        $p = Join-Path $instRoot $Name; New-Item -ItemType Directory -Path $p | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $p "horde.cmd"), ($Lines -join "`r`n"))
        $d = Join-Path $p $Leaf; New-Item -ItemType Directory -Path $d | Out-Null
        return $d
    }
    $nobody = Join-Path $instRoot "nobody"
    # A MENTION IS NOT A LAUNCH: a horde.cmd that only names the clone, in a comment or a cd, must not
    # make the clone the install.
    $cm = New-ShimFx -Name "q1" -Lines @('@echo off')
    [System.IO.File]::WriteAllText((Join-Path (Split-Path -Parent $cm) "horde.cmd"), ("rem -File ""$cm\horde.ps1""`r`n:: -File ""%~dp0horde\horde.ps1""`r`n  REM -File ""%~dp0horde\horde.ps1""`r`ncd /d ""$cm""`r`necho $cm\horde.ps1`r`n""powershell.exe"" -File ""$cm\other.ps1"" %*`r`n"))
    Check ((Get-HordeMutateInstalledRefusal -Repo $cm -ProfileDir $nobody) -eq "") "CONTROL: a horde.cmd that only mentions the folder (rem, ::, cd, echo, another script) does not make it the install"
    $sx = New-ShimFx -Name "q2" -Lines @('powershell.exe -File "%~dp0horde\horde.ps1x" %*')
    Check ((Get-HordeMutateInstalledRefusal -Repo $sx -ProfileDir $nobody) -eq "") "CONTROL: a launch of horde.ps1x is not a launch of horde.ps1"
    $sp = New-ShimFx -Name "q2b" -Lines @('powershell.exe -File "%~dp0horde\horde.ps1" %*')
    Check ((Get-HordeMutateInstalledRefusal -Repo $sp -ProfileDir $nobody) -ne "") "a launch line after nothing else is read as a launch"
    # SPELLINGS OF THE SAME LAUNCH.
    $fs = New-ShimFx -Name "q3" -Lines @('powershell.exe -File "%~dp0horde/horde.ps1" %*')
    Check ((Get-HordeMutateInstalledRefusal -Repo $fs -ProfileDir $nobody) -ne "") "a forward slash in the shim is read as a backslash"
    $fa = New-ShimFx -Name "q4" -Lines @('x')
    [System.IO.File]::WriteAllText((Join-Path (Split-Path -Parent $fa) "horde.cmd"), ('powershell.exe -File "' + ($fa -replace '\\', '/') + '/horde.ps1" %*'))
    Check ((Get-HordeMutateInstalledRefusal -Repo $fa -ProfileDir $nobody) -ne "") "an absolute path written with forward slashes is read too"
    $dd = New-ShimFx -Name "q5" -Lines @('powershell.exe -File "%~dp0.\horde\horde.ps1" %*')
    Check ((Get-HordeMutateInstalledRefusal -Repo $dd -ProfileDir $nobody) -ne "") "%~dp0.\ is accepted"
    $dm = New-ShimFx -Name "q5b" -Lines @('powershell.exe -file %~dp0horde\horde.ps1 %*')
    Check ((Get-HordeMutateInstalledRefusal -Repo $dm -ProfileDir $nobody) -ne "") "an unquoted path and -file in lower case are read too"
    $mvShim = Join-Path $instRoot "q7"; New-Item -ItemType Directory -Path (Join-Path $mvShim "y") | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $mvShim "horde.cmd"), 'powershell.exe -File "%UserProfile%\q7\y\horde.ps1" %*')
    Check ((Get-HordeMutateInstalledRefusal -Repo (Join-Path $mvShim "y") -ProfileDir $instRoot) -ne "") "a %USERPROFILE% in the shim is read as the profile folder (a moved install)"
    Check ((Get-HordeMutateInstalledRefusal -Repo (Join-Path $mvShim "y") -ProfileDir $nobody) -eq "") "CONTROL: and under another profile it names another folder"
    # THE SIZE CAP: a horde.cmd over 64 KB is not a shim, whatever it says.
    $big = New-ShimFx -Name "q8" -Lines @('powershell.exe -File "%~dp0horde\horde.ps1" %*', ("rem " + ("x" * 70000)))
    Check ((Get-HordeMutateInstalledRefusal -Repo $big -ProfileDir $nobody) -eq "") "a horde.cmd over 64 KB is not read as a shim"
    # NO PARENT: the root of a drive has none, and the rule must say no, not fail.
    $rootOut = try { Get-HordeMutateInstalledRefusal -Repo ([System.IO.Path]::GetPathRoot($env:TEMP)) -ProfileDir $nobody } catch { "THREW: " + $_.Exception.Message }
    Check ($rootOut -eq "") ("a drive root, which has no parent folder, is not refused and does not throw (" + $rootOut + ")")
    # A FOLDER NAMED horde.cmd is not a shim (and does not throw).
    $dirShim = New-ShimFx -Name "q9" -Lines @('x')
    Remove-Item -LiteralPath (Join-Path (Split-Path -Parent $dirShim) "horde.cmd")
    New-Item -ItemType Directory -Path (Join-Path (Split-Path -Parent $dirShim) "horde.cmd") | Out-Null
    $dirOut = try { Get-HordeMutateInstalledRefusal -Repo $dirShim -ProfileDir $nobody } catch { "THREW: " + $_.Exception.Message }
    Check ($dirOut -eq "") ("a folder named horde.cmd beside it is not a shim (" + $dirOut + ")")
    # A PATH .NET CANNOT RESOLVE says why and refuses; it does not crash the tool.
    $badOut = try { Get-HordeMutateInstalledRefusal -Repo ("C:\x" + [char]0 + "y") -ProfileDir $nobody } catch { "THREW: " + $_.Exception.Message }
    Check ($badOut -match 'cannot tell whether' -and $badOut -match 'will not run') ("a path that cannot be resolved is refused with the reason, not thrown (" + $badOut + ")")
    # THE PROFILE IS ASKED OF THE MACHINE FIRST, the variable only when the machine gives nothing. The
    # machine's answer is replaced here, so this box's real profile is never asked.
    $savedProbe = $script:HordeMutateProfileProbe
    $savedUp = $env:USERPROFILE
    $mach = Join-Path $instRoot "machine-profile"
    $envp = Join-Path $instRoot "env-profile"
    $machBin = New-InstFx -Parent (Join-Path $mach "bin") -Leaf "horde"
    $envBin = New-InstFx -Parent (Join-Path $envp "bin") -Leaf "horde"
    try {
        $env:USERPROFILE = $envp
        $script:HordeMutateProfileProbe = { $mach }.GetNewClosure()
        Check ((Get-HordeMutateInstalledRefusal -Repo $machBin -ProfileDir "") -ne "") "with no -ProfileDir, the machine's profile is used"
        Check ((Get-HordeMutateInstalledRefusal -Repo $envBin -ProfileDir "") -eq "") "and the USERPROFILE variable is NOT used while the machine gives one"
        $script:HordeMutateProfileProbe = { "" }
        Check ((Get-HordeMutateInstalledRefusal -Repo $envBin -ProfileDir "") -ne "") "when the machine gives nothing, the USERPROFILE variable is used"
        $script:HordeMutateProfileProbe = { throw "no profile" }
        $failOut = try { Get-HordeMutateInstalledRefusal -Repo $envBin -ProfileDir "" } catch { "THREW: " + $_.Exception.Message }
        Check ($failOut -ne "" -and $failOut -notmatch '^THREW') ("and when asking the machine fails, too, and nothing is thrown (" + $failOut + ")")
        $env:USERPROFILE = ""
        Check ((Get-HordeMutateInstalledRefusal -Repo $envBin -ProfileDir "") -eq "") "CONTROL: with neither, nothing is refused and nothing throws"
    } finally { $script:HordeMutateProfileProbe = $savedProbe; $env:USERPROFILE = $savedUp }
} finally {
    if (Test-Path -LiteralPath $instRoot) { Remove-Item -LiteralPath $instRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

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

if (-not $pwshHere) { Complete-HordeSuite -Success "the mutation tool rejects every way a mutation run can lie under 5.1; the runs under PowerShell 7 were NOT RUN (no pwsh.exe)" -PassCode 3 }
Complete-HordeSuite -Success "the mutation tool rejects every way a mutation run can lie"
