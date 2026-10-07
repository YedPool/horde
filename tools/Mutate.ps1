# Mutate.ps1 - prove a suite can fail: break the code on purpose, one way at a time, and require the
# suite to notice.
#
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\<module>.psd1
#
# The spec names a target file, a suite, and a list of mutations. Each mutation is a literal
# find-and-replace that must match EXACTLY ONCE in the target - a find that matches nothing would
# "survive" by never having been applied, which is how a mutation run lies. Each runs against a fresh
# copy of the repository in a throwaway folder, so the working tree is never touched and a run in
# progress elsewhere never sees a broken file.
#
# WHY THIS IS A COMMITTED TOOL. A review of the isolation harness found its commit message claiming
# "mutations M1-M9 each caught" with nothing in the repository to check that against: the mutations
# had been run from a scratch script. A claim a reviewer cannot rerun is not evidence.
#
# A mutation the suite is KNOWN not to catch is declared with Expect = "survives" and a Reason, so the
# gap is written down where a reader can disagree with it, instead of being left out of the spec.
#
# Exit 0 only if every mutation applied exactly once and did what it was expected to - on the whole
# suite, unless -Fast was given. A -Fast run can exit 0 on a catch only a section made; it is a
# reviewer's tool and its result is never evidence for a merge (SECTIONS AND -Fast, below).

#
# "CAUGHT" MEANS A CHECK FAILED. Before any mutation, the copied suite is run UNMUTATED and must pass;
# otherwise every mutation would "fail" the suite for a reason that has nothing to do with it, and read
# as caught - the third review measured exactly that with an always-failing suite and a no-op
# mutation. And a mutant run must fail with at least one [FAIL] line: a suite that crashed, or ran past
# -TimeoutSeconds, did not catch anything and is reported as such.
#
# A TIMED-OUT SUITE IS STOPPED, AND ONLY IT. This tool holds the suite's process handle from the moment
# it starts and kills that process alone; anything the suite itself started is the suite's to clean
# up, and the report says a run timed out so a person can look.

#
# -RunTag NAMES THIS RUN'S THROWAWAY FOLDER: horde-mutate-<tag>-<guid> instead of horde-mutate-<guid>.
# Several agents run mutations at once in one shared TEMP, so a caller that must find the folders ITS
# run left behind cannot go by "new since I started" - another run's folder is new too
# (test/test-mutate.ps1 blamed itself for two foreign runs on 2026-09-30). A tag only that caller
# knows makes its folders its own. Lowercase letters and digits, 1 to 16.
#
# -Only runs just the named mutants of the spec - to rerun one after a fix without the rest - and
# refuses a name the spec does not have (second review of PR #31, finding 9).
#
# SECTIONS AND -Fast: IN A REVIEW ROUND A MUTANT CAN RUN ONLY THE PART OF THE SUITE THAT KILLS IT
# (issues #82 and #83). Every mutant reran the whole suite when one section would catch it;
# link-contract.psd1 took about 2900 s on the always-on box. A suite that declares sections
# (test\lib\Suite.ps1, Register-HordeSuiteSections) lets a mutant carry Sections = @("id", ...).
#
# WHAT A MAP CANNOT PROVE. A section can take another path when the sections before it did not run - a
# cache an earlier one would have filled, a setup it would have done - so a mutant on that path fails
# the section alone and passes the whole suite: a survivor the map reports as caught (review of #115,
# round 2, reproduced on test\fixtures\mutate\spec-sections-cache.psd1). Only a run of the whole suite
# rules that out. The first form of this tool made that run only on request (-VerifyMaps), so the
# plain -Spec run every gate makes printed such a catch as [OK] and exited 0 (review of #115, round 3,
# finding F1). So the whole suite decides every verdict unless the caller asks otherwise:
#   - WITHOUT -Fast - THE DEFAULT, AND WHAT A GATE RUNS - A MAP IS NOT USED. A mapped mutant runs the
#     whole suite once, exactly as an unmapped one does, and that run is its verdict. Its sections are
#     not run first: the whole suite decides anyway, so that run would only be added time. THE COST,
#     PLAINLY: at the gate a map saves nothing. Every mutant of link-contract.psd1 costs a whole run
#     there again; the time sections save is saved in review rounds only.
#   - -Fast USES THE MAP, AND ITS RESULT IS NOT EVIDENCE FOR A MERGE. It is the review-round
#     accelerator. A mapped mutant's run gets HORDE_SECTIONS for its ids, and a run that skipped the
#     rest (exit 3) counts as a pass. Then:
#       * A MAPPED PASS IS NEVER A SURVIVOR UNTIL THE WHOLE SUITE SAYS SO. A mutant that passes its
#         sections is run again on the whole suite. Caught there, it is caught, and named [MAP-MISS]
#         so the map gets fixed; passed there too, it survived.
#       * A MAPPED CATCH STANDS, UNVERIFIED. It is printed "unverified", it counts as expected, and
#         the run exits 0 if nothing else is wrong - so a fast exit 0 is a reviewer's signal and no
#         more. One unverified catch changes the shape of the result line (THE RESULT LINES, below),
#         so no gate can read the run as a result.
#       * EVERY MAP HAS AN UNMUTATED BASELINE OF ITS OWN, before and after the mutants.
#   - -Fast WITH VERIFICATION CHECKS THE MAPS. Given -Fast and -VerifyMaps, or -Fast with
#     HORDE_MUTATE_VERIFY_MAPS=1 in the environment, every mapped catch is run again on the whole
#     suite and the whole suite's verdict stands. A mutant its sections caught and the whole suite did
#     not is named [MAP-HIDES]: it survived. This costs MORE than the default - the sections' run and
#     the whole run for every mapped mutant, and two baselines for every map - and its one use is to
#     find a map that misses or hides.
#   - HORDE_MUTATE_VERIFY_MAPS IS "1", "0" OR NOTHING. Unset, empty or "0", it has no say: it never
#     turns verification off, so a plain run still verifies and -Fast alone still does not. "1"
#     verifies even when -Fast was given, so a gate can force it whatever its caller passes. Any other
#     value is refused on stderr with exit 2 before anything runs: "true" and "yes" used to read,
#     silently, as "do not verify" (review of #115, round 3, finding F2).
#   - -VerifyMaps WITHOUT -Fast changes nothing: verifying is the default. It is kept so a caller
#     written for the earlier form still runs.
#   - A WRONG MAP IS REFUSED, NOT RUN, with or without -Fast: a name the suite does not declare, an
#     empty map, a map on a suite with no sections, or one outside the spec's own HORDE_SECTIONS
#     (test\lib\SuiteSections.ps1, the rule test\test-mutation-specs.ps1 checks on every gate run).
#   - EVERY OTHER RUN IS WHOLE: both baselines, every unmapped mutant and every rerun get the spec's own
#     HORDE_SECTIONS or none at all - never one inherited from the shell that started this tool.
#
# THE RESULT LINES. The LAST line of a run in which no catch rests on a section alone is exactly
#   mutations: N, as expected: N, not: N
# with nothing after it. Gates outside this repository accept a spec only when its last line of output
# matches ^mutations: (\d+), as expected: (\d+), not: (\d+)$ - the earlier form of this tool appended
# the map counts to that line, and every spec would have read NOT RUN there. The map counts have a
# line of their own, printed just before it and only when a mutant that ran carries a map:
#   maps: sectioned N, misses N, hides N
# (how many mutants ran on their sections, how many of those the map missed, how many it hid). A -Fast
# run that left at least one catch unverified ends instead with
#   mutations (fast, unverified catches: N - not gate evidence): N, as expected: N, not: N
# which that pattern cannot match. A -Fast run with no unverified catch ends with the classic line:
# every mutant its sections caught was confirmed whole, and every other verdict was the whole suite's.
#
# -Changed <base-ref> RUNS ONLY THE MUTANTS A CHANGE COULD HAVE MADE THE SUITES MISS: those whose find
# string lies on a line the diff from merge-base(<base-ref>, HEAD) to the working tree added or
# modified, plus every mutant that cannot be placed (fail safe) and every mutant of a spec whose file changed. The
# rules, and why each leans towards running, are in tools\MutateChanged.ps1. Every spec is read unless
# -Spec names one. Each spec with a selected mutant then runs as an ordinary -Spec -Only run, so it
# keeps its own Environment - its suite's section filter - and its baselines. The output lists every
# mutant selected and every one skipped, with the reason. A diff that touches a mutation target yet
# selects nothing exits 2: zero is not a pass there. -Plan prints the selection and runs nothing (no
# "mutations:" line, so no gate can read it as a result).
# -Changed VERIFIES AS ANY RUN DOES: each spec it runs gets -Fast only when -Changed itself was given
# -Fast (and -VerifyMaps likewise). Its total line is the classic one, with the "maps:" totals on the
# line before it when a spec printed them; if any spec left a catch unverified, the total takes the
# fast shape too. It selects by a mutant's own line and its spec file, so a change to a suite or a
# helper alone selects - and so verifies - nothing: that is the full specs' job (CONTRIBUTING 15).
#
#   powershell -File tools\Mutate.ps1 -Changed origin/main
param([string]$Spec = "", [int]$TimeoutSeconds = 900, [ValidatePattern('^[a-z0-9]{1,16}\z')][string]$RunTag, [string[]]$Only = @(), [string]$Changed = "", [switch]$Plan, [switch]$VerifyMaps, [switch]$Fast)
$script:baselineFailed = $false

$ErrorActionPreference = "Stop"
# Each suite this tool starts is opted out of power throttling (core/Platform.ps1, Invoke-HordeSuite).
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Platform.ps1")
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo "test\lib\SuiteSections.ps1")
if (-not $Spec -and -not $Changed) { Write-Host "  give -Spec <spec>, or -Changed <base-ref>" -ForegroundColor Red; exit 2 }
if ($Plan -and -not $Changed) { Write-Host "  -Plan only applies to -Changed" -ForegroundColor Red; exit 2 }
# HORDE_MUTATE_VERIFY_MAPS IS "1", "0" OR NOTHING, and is read before anything runs. It was compared with
# "1" and nothing else, so "true" or "yes" from a gate's configuration meant "do not verify" and said
# nothing (review of #115, round 3, finding F2). On stderr, so the refusal is no part of a result.
$verifyEnv = "$env:HORDE_MUTATE_VERIFY_MAPS"
if (@("", "0", "1") -cnotcontains $verifyEnv) { [Console]::Error.WriteLine("  HORDE_MUTATE_VERIFY_MAPS is '" + $verifyEnv + "': set it to 1 to verify every mapped catch, or to 0 or nothing to leave it to the switches. Nothing was run."); exit 2 }
if ($Changed) {
    if ($Only.Count -gt 0) { Write-Host "  -Only and -Changed both choose the mutants; give one" -ForegroundColor Red; exit 2 }
    . (Join-Path $PSScriptRoot "MutateChanged.ps1")
    . (Join-Path $repo "test\lib\SuiteFiles.ps1")
    $diff = Get-HordeChangedLines -Repo $repo -Base $Changed
    if (-not $diff.ok) { Write-Host ("  -Changed: " + $diff.error) -ForegroundColor Red; exit 2 }
    $specRels = @()
    if ($Spec) {
        $specRels = @($Spec)
    } else {
        # The one rule for what a spec is, shared with test\test-mutation-specs.ps1 (test\lib\SuiteFiles.ps1).
        $repoLen = [System.IO.Path]::GetFullPath($repo).TrimEnd('\').Length + 1
        $specRels = @(Get-HordeMutationSpecFiles -Root $repo | ForEach-Object { $_.FullName.Substring($repoLen) })
    }
    $specObjs = @()
    foreach ($rel in $specRels) {
        $full = $rel; if (-not [System.IO.Path]::IsPathRooted($full)) { $full = Join-Path $repo $rel }
        $data = Import-PowerShellDataFile -LiteralPath $full
        foreach ($k in @("Target", "Suite", "Mutations")) { if (-not $data.ContainsKey($k)) { Write-Host ("  " + $rel + ": spec has no " + $k) -ForegroundColor Red; exit 2 } }
        $tFull = Join-Path $repo "$($data.Target)"
        $text = $null
        if (Test-Path -LiteralPath $tFull -PathType Leaf) { $text = [System.IO.File]::ReadAllText($tFull) }
        $relKey = ConvertTo-HordeDiffKey ([System.IO.Path]::GetFullPath($full).Substring([System.IO.Path]::GetFullPath($repo).TrimEnd('\').Length + 1))
        $specObjs += [pscustomobject]@{ spec = $rel; data = $data; text = $text; specChanged = $diff.changed.ContainsKey($relKey) }
    }
    $rows = @(Select-HordeChangedMutants -Specs $specObjs -Changed $diff.changed)
    $verdict = Get-HordeSelectionVerdict -Rows $rows -Changed $diff.changed
    $tgtKeys = @{}; foreach ($so in $specObjs) { $tgtKeys[(ConvertTo-HordeDiffKey "$($so.data.Target)")] = $true }
    $touchedTargets = @($diff.changed.Keys | Where-Object { $tgtKeys.ContainsKey($_) } | Sort-Object)
    Write-Host ("changed: base " + $Changed + " (merge-base " + $diff.mergeBase.Substring(0, [Math]::Min(12, $diff.mergeBase.Length)) + "), " + $diff.changed.Count + " file(s) changed, " + $touchedTargets.Count + " of them mutation targets" + $(if ($touchedTargets.Count) { ": " + ($touchedTargets -join ", ") } else { "" }))
    foreach ($so in $specObjs) {
        $mine = @($rows | Where-Object { $_.spec -eq $so.spec })
        if ($mine.Count -gt 0 -and @($mine | Where-Object { $_.selected -or $_.reason -notlike "* is not in the diff" }).Count -eq 0) {
            # A spec whose target the diff never touched, with every mutant placed: one line says so.
            Write-Host ("  [SKIP] " + $so.spec + ": all " + $mine.Count + " mutants - " + $so.data.Target + " is not in the diff") -ForegroundColor DarkGray
            continue
        }
        foreach ($r in $mine) {
            if ($r.selected) { Write-Host ("  [SELECT] " + $r.spec + " :: " + $r.name + " - " + $r.reason) }
            else { Write-Host ("  [SKIP] " + $r.spec + " :: " + $r.name + " - " + $r.reason) -ForegroundColor DarkGray }
        }
    }
    $selRows = @($rows | Where-Object { $_.selected })
    Write-Host ("changed: " + $verdict.message + "; skipped " + ($rows.Count - $selRows.Count) + " as unchanged")
    if (-not $verdict.ok) { Write-Host ("  -Changed: " + $verdict.message) -ForegroundColor Red; exit 2 }
    if ($Plan) { Write-Host "changed: plan only - nothing was run"; exit 0 }
    if ($selRows.Count -eq 0) { Write-Host ("mutations: none selected - " + $verdict.message); exit 0 }

    # Each spec with a selected mutant runs as an ordinary -Spec -Only run of this same tool, in this
    # process: its own Environment (section filter), its own baselines before and after.
    $sum = 0; $okSum = 0; $notSum = 0; $worst = 0; $t0 = Get-Date
    $unverifiedSum = 0; $mapLines = 0; $sectionedSum = 0; $missSum = 0; $hideSum = 0
    foreach ($so in $specObjs) {
        $names = @($selRows | Where-Object { $_.spec -eq $so.spec } | ForEach-Object { $_.name } | Select-Object -Unique)
        if ($names.Count -eq 0) { continue }
        Write-Host ("changed: running " + $names.Count + " mutant(s) of " + $so.spec)
        $ts = Get-Date
        # VERIFIED UNLESS THE CALLER OF -Changed SAID -Fast: a spec run verifies by default, so nothing
        # is passed down that the caller did not give. A change is what moves a mutant onto a path only
        # its section takes alone (review of #115, round 2).
        $childArgs = @{ Spec = $so.spec; Only = $names; TimeoutSeconds = $TimeoutSeconds }
        if ($Fast) { $childArgs.Fast = $true }
        if ($VerifyMaps) { $childArgs.VerifyMaps = $true }
        if ($RunTag) { $childArgs.RunTag = $RunTag }
        $lines = @(& $PSCommandPath @childArgs 6>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
        # The spec's own result line and its "maps:" line are relayed indented, so the one line
        # starting "mutations" is the total below - the line a gate reads.
        foreach ($l in $lines) { if ($l -match '^(mutations[ :]|maps: )') { Write-Host ("  " + $so.spec + ": " + $l) } else { Write-Host $l } }
        # A spec's result is its last "mutations" line, in one of the two shapes a run can end with
        # (THE RESULT LINES, above), each matched whole. Anything else is a spec that did not run.
        $resultLine = "$(@($lines | Where-Object { $_ -match '^mutations[ :]' }) | Select-Object -Last 1)"
        $m = [regex]::Match($resultLine, '^mutations: (\d+), as expected: (\d+), not: (\d+)$')
        $mFast = [regex]::Match($resultLine, '^mutations \(fast, unverified catches: (\d+) - not gate evidence\): (\d+), as expected: (\d+), not: (\d+)$')
        if ($m.Success) { $sum += [int]$m.Groups[1].Value; $okSum += [int]$m.Groups[2].Value; $notSum += [int]$m.Groups[3].Value }
        elseif ($mFast.Success) { $unverifiedSum += [int]$mFast.Groups[1].Value; $sum += [int]$mFast.Groups[2].Value; $okSum += [int]$mFast.Groups[3].Value; $notSum += [int]$mFast.Groups[4].Value }
        elseif ($code -eq 0) { $code = 2 }
        $mMaps = [regex]::Match("$(@($lines | Where-Object { $_ -match '^maps: ' }) | Select-Object -Last 1)", '^maps: sectioned (\d+), misses (\d+), hides (\d+)$')
        if ($mMaps.Success) { $mapLines++; $sectionedSum += [int]$mMaps.Groups[1].Value; $missSum += [int]$mMaps.Groups[2].Value; $hideSum += [int]$mMaps.Groups[3].Value }
        if ($code -ne 0 -and $code -ne 1) { $code = 2 }
        if ($code -gt $worst) { $worst = $code }
        Write-Host ("changed: " + $so.spec + " exit=" + $code + " in " + [int]((Get-Date) - $ts).TotalSeconds + "s")
    }
    Write-Host ("changed: ran the selection in " + [int]((Get-Date) - $t0).TotalSeconds + "s")
    if ($worst -eq 2) { Write-Host "mutations: not run - a selected spec could not run (see above)"; exit 2 }
    # The map counts were on no line of this total at all (review of #115, round 3, finding F5). They
    # get the line before it, and the total keeps the shape a gate reads - unless a spec left a catch
    # unverified, which only -Changed -Fast can cause.
    if ($mapLines -gt 0) { Write-Host ("maps: sectioned " + $sectionedSum + ", misses " + $missSum + ", hides " + $hideSum) }
    $totalHead = "mutations: "
    if ($unverifiedSum -gt 0) { $totalHead = "mutations (fast, unverified catches: " + $unverifiedSum + " - not gate evidence): " }
    Write-Host ($totalHead + $sum + ", as expected: " + $okSum + ", not: " + $notSum)
    if ($worst -ne 0 -or $notSum -gt 0) { exit 1 }
    exit 0
}

function Invoke-HordeSuite {
    # Run a suite as its own process; returns { code; out; timedOut }. The two streams are read through
    # the process API, NOT with `2>&1`: under PowerShell 5.1 that turns the first line a suite writes to
    # stderr into a terminating error - which ended this tool's first run on its first mutation.
    # -Selection is the run's HORDE_SECTIONS, set for that process only; empty means none, so a whole
    # run is whole whatever this tool's own environment holds.
    param([string]$Path, [int]$Seconds, [string]$Selection = "")
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"" + $Path + "`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    if ($psi.EnvironmentVariables.ContainsKey("HORDE_SECTIONS")) { $psi.EnvironmentVariables.Remove("HORDE_SECTIONS") }
    if ($Selection -ne "") { $psi.EnvironmentVariables["HORDE_SECTIONS"] = $Selection }
    $p = [System.Diagnostics.Process]::Start($psi)
    $null = Set-HordeThrottlingOptOut -Process $p
    try {
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        $deadline = (Get-Date).AddSeconds($Seconds)
        if (-not $p.WaitForExit($Seconds * 1000)) {
            try { $p.Kill() } catch { }
            [void]$p.WaitForExit(10000)
            return [pscustomobject]@{ code = -1; out = ""; timedOut = $true }
        }
        $p.WaitForExit()
        # THE TIME LIMIT COVERS READING THE OUTPUT TOO. A grandchild the suite did not stop can hold
        # the output pipes open after the suite itself has exited; waiting on the reads without a
        # limit would hang this tool whatever -TimeoutSeconds says (fourth review).
        $left = [int][Math]::Max(1000, ($deadline - (Get-Date)).TotalMilliseconds)
        if (-not ([System.Threading.Tasks.Task]::WaitAll(@($outTask, $errTask), $left))) {
            return [pscustomobject]@{ code = $p.ExitCode; out = ""; timedOut = $true }
        }
        return [pscustomobject]@{ code = $p.ExitCode; out = ($outTask.Result + "`n" + $errTask.Result); timedOut = $false }
    } finally { $p.Dispose() }
}

function Get-HordeFailLines {
    param([string]$Out)
    # Only a line that STARTS with [FAIL] is a failed check. An error message quoting a source line
    # that contains "[FAIL]" is not - which is how a crashed suite first read as caught.
    return @(($Out -split "`r?`n") | Where-Object { $_ -match '^\s*\[FAIL\]' } | ForEach-Object { $_.Trim() })
}

function Get-HordeRunOutcome {
    # What one mutant run means: survived, caught, or why it is not a catch. -PassCodes are the exit
    # codes that mean the suite passed.
    param($Run, [int[]]$PassCodes, [int]$Seconds)
    if ($Run.timedOut) { return ("timed out after " + $Seconds + "s - not a catch") }
    if ($PassCodes -contains $Run.code) { return "survived" }
    if (@(Get-HordeFailLines -Out $Run.out).Count -gt 0) { return "caught" }
    return ("the suite broke (exit " + $Run.code + ") with no failed check - not a catch")
}

function Get-HordeSelectionBaselineProblem {
    # Why an UNMUTATED run of a map's sections does not pass, or "" when it does: it must exit with a
    # pass code or 3 (sections skipped), and print no [FAIL] and no [ERROR] (review of #115, B1).
    param($Run, [int[]]$PassCodes, [int]$Seconds)
    if ($Run.timedOut) { return ("ran past " + $Seconds + "s") }
    if ((@($PassCodes) + 3) -notcontains $Run.code) { return ("exited " + $Run.code) }
    if (@(($Run.out -split "`r?`n") | Where-Object { $_ -match '^\s*\[(FAIL|ERROR)\]' }).Count -gt 0) { return ("exited " + $Run.code + " but printed a failed check or an error") }
    return ""
}

function Get-HordeOccurrences {
    param([string]$Text, [string]$Find)
    $n = 0; $i = 0
    while (($i = $Text.IndexOf($Find, $i, [System.StringComparison]::Ordinal)) -ge 0) { $n++; $i += $Find.Length }
    return $n
}

$specPath = $Spec
if (-not [System.IO.Path]::IsPathRooted($specPath)) { $specPath = Join-Path $repo $specPath }
$s = Import-PowerShellDataFile -LiteralPath $specPath
foreach ($k in @("Target", "Suite", "Mutations")) { if (-not $s.ContainsKey($k)) { throw ("spec has no " + $k) } }

# A SPEC MAY SET ITS SUITE'S ENVIRONMENT, for its runs only: Environment = @{ HORDE_X = "1" }. Each
# variable is set before the first run (so the suites inherit it) and put back as it was in the
# finally below, so a run never depends on - or leaks into - the shell that started it (review of
# PR #31, finding 5: test-projection's HORDE_SKIP_REALITY was set by hand and stayed set). Only
# HORDE_ names: PATH or TEMP would change what every run means.
# THE EXIT CODES THAT MEAN "THE SUITE PASSED". 0, unless the spec declares its own: test-projection
# passes with 3 when it skipped its reality check, so that no gate expecting 0 reads a partial run as
# whole, and only a spec that sets PassCodes = @(3) accepts it (second review of PR #31, finding 4).
$passCodes = @(0)
if ($s.ContainsKey("PassCodes")) { $passCodes = @($s.PassCodes | ForEach-Object { [int]$_ }) }
$unknownOnly = @($Only | Where-Object { @($s.Mutations | ForEach-Object { "$($_.Name)" }) -cnotcontains $_ })
if ($unknownOnly.Count -gt 0) { Write-Host ("  -Only names mutants the spec does not have: " + ($unknownOnly -join ", ")) -ForegroundColor Red; exit 2 }
$script:envSaved = @{}
$specEnv = @{}
if ($s.ContainsKey("Environment")) { $specEnv = $s.Environment }
# A MAP IS USED ONLY UNDER -Fast. Without it the whole suite is each mutant's one run, so there is no
# mapped catch to confirm. (When a map was used in every run and verifying had to be asked for, the
# plain run every gate makes reported a survivor as caught: review of #115, round 3, finding F1.)
$useMaps = [bool]$Fast
# Under -Fast, a mapped catch is confirmed on the whole suite only when asked. Not named $verifyMaps:
# variable names ignore case, so that local WAS the -VerifyMaps parameter (CONTRIBUTING 12).
$confirmCatches = ($VerifyMaps -or $verifyEnv -ceq "1")
# The whole suite, as this spec runs it: its own section filter, or none.
$wholeSelection = ""
if ($specEnv.ContainsKey("HORDE_SECTIONS")) { $wholeSelection = "$($specEnv.HORDE_SECTIONS)" }
foreach ($name in @($specEnv.Keys)) {
    if ("$name" -cnotmatch '^HORDE_[A-Z0-9_]+$') { Write-Host ("  spec Environment may set only HORDE_ variables, not '" + $name + "'") -ForegroundColor Red; exit 2 }
}

$tagPart = ""
if ($RunTag) { $tagPart = $RunTag + "-" }
$work = Join-Path $env:TEMP ("horde-mutate-" + $tagPart + [guid]::NewGuid().ToString("N"))
foreach ($name in @($specEnv.Keys)) {
    $script:envSaved[$name] = [System.Environment]::GetEnvironmentVariable($name, "Process")
    [System.Environment]::SetEnvironmentVariable($name, "$($specEnv[$name])", "Process")
}
New-Item -ItemType Directory -Path $work | Out-Null
$results = New-Object System.Collections.ArrayList
try {
    foreach ($item in @(Get-ChildItem -LiteralPath $repo -Force | Where-Object { $_.Name -ne ".git" })) {
        Copy-Item -LiteralPath $item.FullName -Destination $work -Recurse -Force
    }
    # The target and suite must be inside the throwaway copy: a Target with ".." would otherwise
    # rewrite, and then restore, a real file outside it.
    $workFull = [System.IO.Path]::GetFullPath($work).TrimEnd('\') + '\'
    $target = [System.IO.Path]::GetFullPath((Join-Path $work $s.Target))
    $suite = [System.IO.Path]::GetFullPath((Join-Path $work $s.Suite))
    foreach ($p in @($target, $suite)) {
        if (-not $p.StartsWith($workFull, [System.StringComparison]::OrdinalIgnoreCase)) { throw ("spec path escapes the copy: " + $p) }
    }
    $original = [System.IO.File]::ReadAllText($target)

    $base = Invoke-HordeSuite -Path $suite -Seconds $TimeoutSeconds -Selection $wholeSelection
    if ($base.timedOut -or $passCodes -notcontains $base.code) {
        $why = "exited " + $base.code
        if ($base.timedOut) { $why = "ran past " + $TimeoutSeconds + "s" }
        Write-Host ("  the UNMUTATED suite does not pass in the copy (" + $why + "), so no mutation result would mean anything:") -ForegroundColor Red
        foreach ($f in (Get-HordeFailLines -Out $base.out)) { Write-Host ("        " + $f) -ForegroundColor Red }
        Write-Host "mutations: not run - baseline failed"
        $script:baselineFailed = $true
    }

    $script:toRun = @()
    if (-not $script:baselineFailed) {
        $script:toRun = @($s.Mutations)
        if ($Only.Count -gt 0) { $script:toRun = @($s.Mutations | Where-Object { $Only -ccontains "$($_.Name)" }) }
    }
    # The suite's declared sections, read once from the copy, when any mutant is mapped.
    $declared = $null
    if (@($script:toRun | Where-Object { $_.ContainsKey("Sections") }).Count -gt 0) { $declared = Get-HordeSuiteSectionIds -Path $suite }
    # EVERY MAP HAS A BASELINE OF ITS OWN, BEFORE AND AFTER. A section that fails when run without the
    # ones before it - one that reads a variable an earlier section set - fails every mutant mapped to
    # it, and reads as a catch the whole-suite rerun never questions (it reruns only a pass). Reproduced
    # by the review of #115 (B1) and on test-node-serve's refused-peer section, 2026-10-07. So each
    # distinct selection is run unmutated first and again at the end, and must pass both times. Only
    # under -Fast: without it no mutant runs on a selection, so there is no such catch to guard.
    $selections = @()
    if ($useMaps) { $selections = @($script:toRun | Where-Object { $_.ContainsKey("Sections") -and -not (Get-HordeMutantSectionProblem -Mutant $_ -Suite "$($s.Suite)" -Declared $declared -SpecEnvironment $specEnv) } | ForEach-Object { (@(@($_.Sections) | ForEach-Object { "$_".Trim() }) -join ",") } | Select-Object -Unique) }
    foreach ($sel in $selections) {
        $selBase = Invoke-HordeSuite -Path $suite -Seconds $TimeoutSeconds -Selection $sel
        $selWhy = Get-HordeSelectionBaselineProblem -Run $selBase -PassCodes $passCodes -Seconds $TimeoutSeconds
        if ($selWhy) {
            Write-Host ("  the UNMUTATED suite does not pass when only its sections " + $sel + " run (" + $selWhy + "), so a mutant mapped to them would read as caught for nothing:") -ForegroundColor Red
            foreach ($f in (Get-HordeFailLines -Out $selBase.out)) { Write-Host ("        " + $f) -ForegroundColor Red }
            Write-Host "mutations: not run - baseline failed"
            $script:baselineFailed = $true
            $script:toRun = @()
            break
        }
    }
    foreach ($m in $script:toRun) {
        $expect = "caught"
        if ($m.ContainsKey("Expect")) { $expect = "$($m.Expect)" }
        $row = [ordered]@{ name = $m.Name; expect = $expect; outcome = ""; failures = @(); sections = ""; sectioned = $false; mapMiss = $false; verified = ""; mapHides = $false }
        $mapWhy = ""
        if ($m.ContainsKey("Sections")) {
            $mapWhy = Get-HordeMutantSectionProblem -Mutant $m -Suite "$($s.Suite)" -Declared $declared -SpecEnvironment $specEnv
            if (-not $mapWhy) { $row.sections = (@(@($m.Sections) | ForEach-Object { "$_".Trim() }) -join ",") }
        }
        if ("$($m.Find)" -match "[\r\n]") { $row.outcome = "invalid: a find string may not span lines (line endings differ by checkout)" }
        elseif ($expect -eq "survives" -and -not "$($m.Reason)".Trim()) { $row.outcome = "invalid: a mutation expected to survive needs a Reason" }
        elseif ($mapWhy) { $row.outcome = ("invalid: " + $mapWhy) }
        else {
            $count = Get-HordeOccurrences -Text $original -Find $m.Find
            if ($count -ne 1) { $row.outcome = ("did not apply: the find string occurs " + $count + " times, not once") }
            else {
                [System.IO.File]::WriteAllText($target, $original.Replace($m.Find, $m.Replace))
                # A MUTANT THAT DOES NOT PARSE CATCHES NOTHING. A suite that keeps going after its
                # errors fails every later check when the target will not load, which the fourth review
                # measured reading as "caught". So a PowerShell target is parsed first.
                $parseErrors = @()
                if ($target -match '\.ps1$') {
                    $tk = $null; $pe = $null
                    [void][System.Management.Automation.Language.Parser]::ParseFile($target, [ref]$tk, [ref]$pe)
                    $parseErrors = @($pe)
                }
                if ($parseErrors.Count -gt 0) {
                    $row.outcome = ("the mutant does not parse (" + $parseErrors[0].Message + ") - not a catch")
                    [System.IO.File]::WriteAllText($target, $original)
                    [void]$results.Add([pscustomobject]$row)
                    continue
                }
                if ($row.sections -and $useMaps) {
                    # Its sections first; a run that skipped the rest exits 3, which is a pass here.
                    $row.sectioned = $true
                    $run = Invoke-HordeSuite -Path $suite -Seconds $TimeoutSeconds -Selection $row.sections
                    $row.failures = @(Get-HordeFailLines -Out $run.out)
                    $row.outcome = Get-HordeRunOutcome -Run $run -PassCodes (@($passCodes) + 3) -Seconds $TimeoutSeconds
                    if ($row.outcome -eq "survived") {
                        # A PASS OF ITS SECTIONS IS NOT A SURVIVAL: the whole suite decides.
                        $rerun = Invoke-HordeSuite -Path $suite -Seconds $TimeoutSeconds -Selection $wholeSelection
                        $row.failures = @(Get-HordeFailLines -Out $rerun.out)
                        $row.outcome = Get-HordeRunOutcome -Run $rerun -PassCodes $passCodes -Seconds $TimeoutSeconds
                        $row.mapMiss = ($row.outcome -eq "caught")
                    } elseif ($row.outcome -eq "caught" -and $confirmCatches) {
                        # A MAPPED CATCH, CONFIRMED: the whole suite's verdict stands.
                        $confirm = Invoke-HordeSuite -Path $suite -Seconds $TimeoutSeconds -Selection $wholeSelection
                        $wholeOutcome = Get-HordeRunOutcome -Run $confirm -PassCodes $passCodes -Seconds $TimeoutSeconds
                        if ($wholeOutcome -eq "caught") { $row.verified = "yes" }
                        else { $row.outcome = $wholeOutcome; $row.failures = @(Get-HordeFailLines -Out $confirm.out); $row.mapHides = $true }
                    } elseif ($row.outcome -eq "caught") { $row.verified = "no" }
                } else {
                    # Unmapped, or mapped in a run without -Fast: the whole suite, once.
                    $run = Invoke-HordeSuite -Path $suite -Seconds $TimeoutSeconds -Selection $wholeSelection
                    $row.failures = @(Get-HordeFailLines -Out $run.out)
                    $row.outcome = Get-HordeRunOutcome -Run $run -PassCodes $passCodes -Seconds $TimeoutSeconds
                }
            }
        }
        [System.IO.File]::WriteAllText($target, $original)
        [void]$results.Add([pscustomobject]$row)
    }

    # AND THE BASELINE AGAIN AT THE END. A check that fails for a reason of its own - a race, the
    # machine - during a mutant's run reads as a catch. If the unmutated suite no longer passes
    # afterwards, the environment changed under the run and its catches are not evidence.
    if (-not $script:baselineFailed -and $script:toRun.Count -gt 0) {
        $after = Invoke-HordeSuite -Path $suite -Seconds $TimeoutSeconds -Selection $wholeSelection
        if ($after.timedOut -or $passCodes -notcontains $after.code) {
            Write-Host "  the UNMUTATED suite no longer passes after the run, so its catches are not evidence:" -ForegroundColor Red
            foreach ($f in (Get-HordeFailLines -Out $after.out)) { Write-Host ("        " + $f) -ForegroundColor Red }
            $script:baselineFailed = $true
        }
        foreach ($sel in $selections) {
            $selAfter = Invoke-HordeSuite -Path $suite -Seconds $TimeoutSeconds -Selection $sel
            $selAfterWhy = Get-HordeSelectionBaselineProblem -Run $selAfter -PassCodes $passCodes -Seconds $TimeoutSeconds
            if ($selAfterWhy) {
                Write-Host ("  the UNMUTATED suite no longer passes its sections " + $sel + " after the run (" + $selAfterWhy + "), so their catches are not evidence:") -ForegroundColor Red
                foreach ($f in (Get-HordeFailLines -Out $selAfter.out)) { Write-Host ("        " + $f) -ForegroundColor Red }
                $script:baselineFailed = $true
            }
        }
    }
}
finally {
    foreach ($name in @($script:envSaved.Keys)) { [System.Environment]::SetEnvironmentVariable($name, $script:envSaved[$name], "Process") }
    # Only the folder this run created: a fresh guid name, with this run's tag if it has one, directly in TEMP.
    if ((Split-Path -Leaf $work) -match '^horde-mutate-([a-z0-9]{1,16}-)?[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $work)) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($script:baselineFailed) { exit 2 }

$bad = 0
$mapped = 0
$sectioned = 0
$mapMisses = 0
$mapHides = 0
$unverified = 0
foreach ($r in $results) {
    # Expect is written "caught" or "survives"; the outcome of a run is "caught" or "survived".
    $want = "caught"; if ($r.expect -eq "survives") { $want = "survived" }
    $ok = ($r.outcome -eq $want)
    if (-not $ok) { $bad++ }
    $color = "DarkGray"; if (-not $ok) { $color = "Red" }
    $where = ""
    if ($r.sections) { $mapped++ }
    if ($r.sectioned) { $sectioned++ }
    if ($r.sections -and $useMaps) { $where = " [sections: " + $r.sections + "]" }
    elseif ($r.sections) { $where = " [map (" + $r.sections + ") not used: a map is used only under -Fast]" }
    if ($r.verified -eq "yes") { $where += " verified by the whole suite" }
    elseif ($r.verified -eq "no") { $where += " unverified: the whole suite was not run"; $unverified++ }
    Write-Host ("  [" + $(if ($ok) { "OK" } else { "BAD" }) + "] " + $r.name + ": " + $r.outcome + " (expected " + $r.expect + ")" + $where) -ForegroundColor $color
    if ($r.mapMiss) {
        $mapMisses++
        Write-Host ("  [MAP-MISS] " + $r.name + ": its sections (" + $r.sections + ") passed; the whole suite caught it - fix the map") -ForegroundColor Yellow
    }
    if ($r.mapHides) {
        # Counted: a [MAP-HIDES] line was on no count at all (review of #115, round 3, finding F4).
        $mapHides++
        Write-Host ("  [MAP-HIDES] " + $r.name + ": its sections (" + $r.sections + ") caught it and the whole suite did not (" + $r.outcome + ") - the map hides a survivor") -ForegroundColor Red
    }
    foreach ($f in $r.failures) { Write-Host ("        " + $f) -ForegroundColor DarkGray }
}
# THE LAST LINE IS WHAT A GATE READS, SO IT KEEPS ITS EXACT SHAPE (THE RESULT LINES, in the header). The
# map counts go on the line before it, when a mutant that ran carries a map. And a run that left a
# catch unverified must not end in a line a gate accepts: its head is another, so the gate's pattern
# cannot match it.
if ($mapped -gt 0) { Write-Host ("maps: sectioned " + $sectioned + ", misses " + $mapMisses + ", hides " + $mapHides) }
$resultHead = "mutations: "
if ($unverified -gt 0) { $resultHead = "mutations (fast, unverified catches: " + $unverified + " - not gate evidence): " }
Write-Host ($resultHead + $results.Count + ", as expected: " + ($results.Count - $bad) + ", not: " + $bad)
if ($bad -gt 0) { exit 1 }
exit 0
