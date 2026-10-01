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

param([Parameter(Mandatory = $true)][string]$Spec, [int]$TimeoutSeconds = 900, [ValidatePattern('^[a-z0-9]{1,16}$')][string]$RunTag)
$script:baselineFailed = $false

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot

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

$tagPart = ""
if ($RunTag) { $tagPart = $RunTag + "-" }
$work = Join-Path $env:TEMP ("horde-mutate-" + $tagPart + [guid]::NewGuid().ToString("N"))
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
    if ($base.timedOut -or $base.code -ne 0) {
        $why = "exited " + $base.code
        if ($base.timedOut) { $why = "ran past " + $TimeoutSeconds + "s" }
        Write-Host ("  the UNMUTATED suite does not pass in the copy (" + $why + "), so no mutation result would mean anything:") -ForegroundColor Red
        foreach ($f in (Get-HordeFailLines -Out $base.out)) { Write-Host ("        " + $f) -ForegroundColor Red }
        Write-Host "mutations: not run - baseline failed"
        $script:baselineFailed = $true
    }

    $script:toRun = @()
    if (-not $script:baselineFailed) { $script:toRun = @($s.Mutations) }
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
                elseif ($run.code -eq 0) { $row.outcome = "survived" }
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
        if ($after.timedOut -or $after.code -ne 0) {
            Write-Host "  the UNMUTATED suite no longer passes after the run, so its catches are not evidence:" -ForegroundColor Red
            foreach ($f in (Get-HordeFailLines -Out $after.out)) { Write-Host ("        " + $f) -ForegroundColor Red }
            $script:baselineFailed = $true
        }
    }
}
finally {
    # Only the folder this run created: a fresh guid name, with this run's tag if it has one, directly in TEMP.
    if ((Split-Path -Leaf $work) -match '^horde-mutate-([a-z0-9]{1,16}-)?[0-9a-f]{32}$' -and (Test-Path -LiteralPath $work)) {
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
