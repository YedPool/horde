# DOES THE KNOWLEDGE-LEDGER GATE ACTUALLY STOP AN UNREAD MODULE?
#
# The gate exists because the systems Horde replaces kept most of what they learned in comments,
# commit messages and pull requests, and a rewrite that does not read them loses it. A gate that can
# be satisfied without reading anything is worse than no gate, because it certifies the loss. So
# this suite spends most of its effort proving the gate REFUSES things - one fixture per rule, each
# breaking exactly one rule, each asserted to fail for THAT reason rather than for any reason.
#
# A gate that rejected every ledger would also pass a "must fail" check. The complete fixture is the
# control against that: it must produce zero findings.

$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "tools\Ledger.ps1")

$fails = @()
function Check { param($Cond, [string]$What)
    if ($Cond) { Write-Host "  [PASS] $What" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $What" -ForegroundColor Red; $script:fails += $What } }

$fx = Join-Path $here "fixtures\ledger"

function Findings { param([string]$Name) return @(Test-HordeLedger -Path (Join-Path $fx $Name) -RepoRoot $fx) }
function Says { param($F, [string]$Text) return (@($F | Where-Object { $_.problem -like "*$Text*" }).Count -gt 0) }

Write-Host ""
Write-Host "--- CONTROL: a complete ledger passes ---" -ForegroundColor Cyan

$ok = Findings "complete.md"
Check ($ok.Count -eq 0) "a ledger with every entry sourced and disposed produces no findings"
if ($ok.Count -gt 0) { $ok | ForEach-Object { Write-Host ("         unexpected: " + $_.entry + " - " + $_.problem) -ForegroundColor Red } }

Write-Host ""
Write-Host "--- every rule refuses, and names the right reason ---" -ForegroundColor Cyan

$f = Findings "undisposed.md"
Check (Says $f "no disposition") "an entry nobody dealt with is refused as having no disposition"

$f = Findings "unsourced.md"
Check (Says $f "no source") "an entry with no source is refused"

$f = Findings "fake-test-file.md"
Check (Says $f "does not exist") "a test disposition naming a test file that does not exist is refused"

$f = Findings "fake-assertion.md"
Check (Says $f "does not contain the assertion") "a test disposition naming an assertion the test does not contain is refused - the check that makes the gate real"

$f = Findings "dropped-no-reason.md"
Check (Says $f "reason of at least a sentence") "dropped with a bare n/a is refused"

$f = Findings "duplicate-id.md"
Check (Says $f "duplicate entry id") "two entries with one id are refused"

$f = Findings "two-dispositions.md"
Check (Says $f "more than one disposition") "an entry with two dispositions is refused"

$f = Findings "sources-incomplete.md"
Check (Says $f "'pull requests' is not marked searched") "a ledger that skipped the pull requests is refused, and says which source"

$f = Findings "empty.md"
Check (Says $f "no entries") "a ledger with no entries is refused rather than passing vacuously"

Write-Host ""
Write-Host "--- mutation: remove one disposition from the passing ledger ---" -ForegroundColor Cyan

# The fixtures above were written to fail. This one starts from the ledger that PASSES and removes a
# single line, which is the realistic way a ledger goes wrong - someone forgets one entry.
$tmp = Join-Path $env:TEMP ("horde-ledger-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force $tmp | Out-Null
Copy-Item -Recurse -Force (Join-Path $fx "test") $tmp
Copy-Item -Recurse -Force (Join-Path $fx "docs") $tmp
$body = (Get-Content -LiteralPath (Join-Path $fx "complete.md") -Raw) -replace "`r", ""
$mutated = [regex]::Replace($body, "(?m)^- disposition: comment\n", "", 1)
Check ($mutated -ne $body) "PRECONDITION: the mutation actually removed a line"
[System.IO.File]::WriteAllText((Join-Path $tmp "mutated.md"), $mutated)
$m = @(Test-HordeLedger -Path (Join-Path $tmp "mutated.md") -RepoRoot $tmp)
Check (Says $m "no disposition") "the passing ledger with one disposition removed now fails"
Check (@($m | Where-Object { $_.entry -eq "L-002" }).Count -gt 0) "and the finding names the entry that lost it, L-002"
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "--- CRLF: a ledger checked out with Windows line endings still parses ---" -ForegroundColor Cyan

# With core.autocrlf on, every ledger in a working tree has CRLF endings. A parser that only works on
# LF would pass here in a fresh clone on another OS and fail on this machine, or the reverse.
$tmp2 = Join-Path $env:TEMP ("horde-ledger-crlf-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force $tmp2 | Out-Null
Copy-Item -Recurse -Force (Join-Path $fx "test") $tmp2
Copy-Item -Recurse -Force (Join-Path $fx "docs") $tmp2
$crlf = ($body -replace "`n", "`r`n")
Check ($crlf.Contains("`r`n")) "PRECONDITION: the copy really has CRLF endings"
[System.IO.File]::WriteAllText((Join-Path $tmp2 "crlf.md"), $crlf)
Check (@(Test-HordeLedger -Path (Join-Path $tmp2 "crlf.md") -RepoRoot $tmp2).Count -eq 0) "the complete ledger passes with CRLF endings too"
Remove-Item -Recurse -Force $tmp2 -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "--- the real ledgers in planning/ledger ---" -ForegroundColor Cyan

# NOT COUNTED AS EVIDENCE WHEN THERE ARE NONE. Zero ledgers checked is not zero ledgers failing; it is
# nothing measured. Reported, never asserted as a pass.
$real = @(Get-HordeLedgerFiles -Dir (Join-Path $root "planning\ledger"))
if ($real.Count -eq 0) {
    Write-Host "  0 real ledgers yet - nothing to check. This is not a pass; the first module that" -ForegroundColor Yellow
    Write-Host "  replaces old code must add one before it can merge." -ForegroundColor Yellow
} else {
    foreach ($l in $real) {
        $r = @(Test-HordeLedger -Path $l.FullName -RepoRoot $root)
        Check ($r.Count -eq 0) ("ledger " + $l.Name + " is complete")
        foreach ($x in $r) { Write-Host ("         " + $x.entry + " - " + $x.problem) -ForegroundColor Red }
    }
}
Check (@(Get-HordeLedgerFiles -Dir (Join-Path $root "planning\ledger") | Where-Object { $_.Name -eq "README.md" }).Count -eq 0) "the format README is not mistaken for a ledger"

Write-Host ""
if ($fails.Count) {
    Write-Host "==== $($fails.Count) FAILURE(S) ====" -ForegroundColor Red
    $fails | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host "==== the ledger gate refuses a module nobody read ====" -ForegroundColor Green
exit 0
