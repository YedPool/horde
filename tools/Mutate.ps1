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
# Exit 0 only if every mutation applied exactly once and did what it was expected to.

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
# -Changed <base-ref> RUNS ONLY THE MUTANTS A CHANGE COULD HAVE MADE THE SUITES MISS: those whose find
# string lies on a line the diff from merge-base(<base-ref>, HEAD) to the working tree added or
# modified, plus every mutant that cannot be placed (fail safe) and every mutant of a spec whose file changed. The
# rules, and why each leans towards running, are in tools\MutateChanged.ps1. Every spec is read unless
# -Spec names one. Each spec with a selected mutant then runs as an ordinary -Spec -Only run, so it
# keeps its own Environment - its suite's section filter - and its baselines. The output lists every
# mutant selected and every one skipped, with the reason. A diff that touches a mutation target yet
# selects nothing exits 2: zero is not a pass there. -Plan prints the selection and runs nothing (no
# "mutations:" line, so no gate can read it as a result).
#
#   powershell -File tools\Mutate.ps1 -Changed origin/main
param([string]$Spec = "", [int]$TimeoutSeconds = 900, [ValidatePattern('^[a-z0-9]{1,16}\z')][string]$RunTag, [string[]]$Only = @(), [string]$Changed = "", [switch]$Plan)
$script:baselineFailed = $false

$ErrorActionPreference = "Stop"
# Each suite this tool starts is opted out of power throttling (core/Platform.ps1, Invoke-HordeSuite).
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Platform.ps1")
$repo = Split-Path -Parent $PSScriptRoot
if (-not $Spec -and -not $Changed) { Write-Host "  give -Spec <spec>, or -Changed <base-ref>" -ForegroundColor Red; exit 2 }
if ($Plan -and -not $Changed) { Write-Host "  -Plan only applies to -Changed" -ForegroundColor Red; exit 2 }
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
    foreach ($so in $specObjs) {
        $names = @($selRows | Where-Object { $_.spec -eq $so.spec } | ForEach-Object { $_.name } | Select-Object -Unique)
        if ($names.Count -eq 0) { continue }
        Write-Host ("changed: running " + $names.Count + " mutant(s) of " + $so.spec)
        $ts = Get-Date
        $childArgs = @{ Spec = $so.spec; Only = $names; TimeoutSeconds = $TimeoutSeconds }
        if ($RunTag) { $childArgs.RunTag = $RunTag }
        $lines = @(& $PSCommandPath @childArgs 6>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
        # The spec's own result line is relayed indented, so the one line starting "mutations: " is
        # the total below - the line a gate reads.
        foreach ($l in $lines) { if ($l -match '^mutations: ') { Write-Host ("  " + $so.spec + ": " + $l) } else { Write-Host $l } }
        $m = [regex]::Match((@($lines | Where-Object { $_ -match '^mutations: ' }) | Select-Object -Last 1), '^mutations: (\d+), as expected: (\d+), not: (\d+)')
        if ($m.Success) { $sum += [int]$m.Groups[1].Value; $okSum += [int]$m.Groups[2].Value; $notSum += [int]$m.Groups[3].Value }
        elseif ($code -eq 0) { $code = 2 }
        if ($code -ne 0 -and $code -ne 1) { $code = 2 }
        if ($code -gt $worst) { $worst = $code }
        Write-Host ("changed: " + $so.spec + " exit=" + $code + " in " + [int]((Get-Date) - $ts).TotalSeconds + "s")
    }
    Write-Host ("changed: ran the selection in " + [int]((Get-Date) - $t0).TotalSeconds + "s")
    if ($worst -eq 2) { Write-Host "mutations: not run - a selected spec could not run (see above)"; exit 2 }
    Write-Host ("mutations: " + $sum + ", as expected: " + $okSum + ", not: " + $notSum)
    if ($worst -ne 0 -or $notSum -gt 0) { exit 1 }
    exit 0
}

function Invoke-HordeSuite {
    # Run a suite as its own process; returns { code; out; timedOut }. The two streams are read through
    # the process API, NOT with `2>&1`: under PowerShell 5.1 that turns the first line a suite writes to
    # stderr into a terminating error - which ended this tool's first run on its first mutation.
    param([string]$Path, [int]$Seconds)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"" + $Path + "`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
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

    $base = Invoke-HordeSuite -Path $suite -Seconds $TimeoutSeconds
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
    foreach ($m in $script:toRun) {
        $expect = "caught"
        if ($m.ContainsKey("Expect")) { $expect = "$($m.Expect)" }
        $row = [ordered]@{ name = $m.Name; expect = $expect; outcome = ""; failures = @() }
        if ("$($m.Find)" -match "[\r\n]") { $row.outcome = "invalid: a find string may not span lines (line endings differ by checkout)" }
        elseif ($expect -eq "survives" -and -not "$($m.Reason)".Trim()) { $row.outcome = "invalid: a mutation expected to survive needs a Reason" }
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
                $run = Invoke-HordeSuite -Path $suite -Seconds $TimeoutSeconds
                $row.failures = @(Get-HordeFailLines -Out $run.out)
                if ($run.timedOut) { $row.outcome = ("timed out after " + $TimeoutSeconds + "s - not a catch") }
                elseif ($passCodes -contains $run.code) { $row.outcome = "survived" }
                elseif ($row.failures.Count -gt 0) { $row.outcome = "caught" }
                else { $row.outcome = ("the suite broke (exit " + $run.code + ") with no failed check - not a catch") }
            }
        }
        [System.IO.File]::WriteAllText($target, $original)
        [void]$results.Add([pscustomobject]$row)
    }

    # AND THE BASELINE AGAIN AT THE END. A check that fails for a reason of its own - a race, the
    # machine - during a mutant's run reads as a catch. If the unmutated suite no longer passes
    # afterwards, the environment changed under the run and its catches are not evidence.
    if (-not $script:baselineFailed -and $script:toRun.Count -gt 0) {
        $after = Invoke-HordeSuite -Path $suite -Seconds $TimeoutSeconds
        if ($after.timedOut -or $passCodes -notcontains $after.code) {
            Write-Host "  the UNMUTATED suite no longer passes after the run, so its catches are not evidence:" -ForegroundColor Red
            foreach ($f in (Get-HordeFailLines -Out $after.out)) { Write-Host ("        " + $f) -ForegroundColor Red }
            $script:baselineFailed = $true
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
foreach ($r in $results) {
    # Expect is written "caught" or "survives"; the outcome of a run is "caught" or "survived".
    $want = "caught"; if ($r.expect -eq "survives") { $want = "survived" }
    $ok = ($r.outcome -eq $want)
    if (-not $ok) { $bad++ }
    $color = "DarkGray"; if (-not $ok) { $color = "Red" }
    Write-Host ("  [" + $(if ($ok) { "OK" } else { "BAD" }) + "] " + $r.name + ": " + $r.outcome + " (expected " + $r.expect + ")") -ForegroundColor $color
    foreach ($f in $r.failures) { Write-Host ("        " + $f) -ForegroundColor DarkGray }
}
Write-Host ("mutations: " + $results.Count + ", as expected: " + ($results.Count - $bad) + ", not: " + $bad)
if ($bad -gt 0) { exit 1 }
exit 0
