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

. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

$fx = Join-Path $here "fixtures\ledger"

function Findings { param([string]$Name) return @(Test-HordeLedger -Path (Join-Path $fx $Name) -RepoRoot $fx) }
function Says { param($F, [string]$Text) return (@($F | Where-Object { $_.problem -like "*$Text*" }).Count -gt 0) }

Write-Host ""
Write-Host "--- CONTROL: a complete ledger passes ---" -ForegroundColor Cyan

$ok = Findings "complete.md"
Check ($ok.Count -eq 0) "a ledger with every entry sourced and disposed produces no findings"
if ($ok.Count -gt 0) { $ok | ForEach-Object { Write-Host ("         unexpected: " + $_.entry + " - " + $_.problem) -ForegroundColor Red } }

Write-Host ""
Write-Host "--- every rule refuses, for its own reason, and ONLY for that reason ---" -ForegroundColor Cyan

# EXACTLY ONE FINDING, not merely the right one among several. A review found that the first version
# only asserted the expected finding was PRESENT, so a fixture failing for three reasons at once would
# still pass - which is the "fails for any reason" weakness this suite claims to avoid.
function Refuses { param([string]$Name, [string]$Text, [string]$What)
    # WRAPPED AT THE CALL SITE. PowerShell 5.1 unrolls a one-element array returned from a function into
    # a bare object, and [pscustomobject].Count is $null in 5.1 - so without @() here, "exactly one
    # finding" could never be true. This made every refusal fail on its first run.
    $f = @(Findings $Name)
    Check ((Says $f $Text) -and $f.Count -eq 1) $What
    if (-not ((Says $f $Text) -and $f.Count -eq 1)) { $f | ForEach-Object { Write-Host ("         got: " + $_.entry + " - " + $_.problem) -ForegroundColor Red } } }

Refuses "undisposed.md"          "no disposition"                  "an entry nobody dealt with is refused as having no disposition"
Refuses "unsourced.md"           "no source"                       "an entry with no source is refused"
Refuses "fake-test-file.md"      "does not exist"                  "a test disposition naming a test file that does not exist is refused"
Refuses "fake-assertion.md"      "does not contain the assertion"  "a test disposition naming an assertion the test does not contain is refused"
Refuses "dropped-no-reason.md"   "reason of at least a sentence"   "dropped with a bare n/a is refused"
Refuses "duplicate-id.md"        "duplicate entry id"              "two entries with one id are refused"
Refuses "two-dispositions.md"    "more than one disposition"       "an entry with two dispositions is refused"
Refuses "sources-incomplete.md"  "'pull requests' is not marked searched" "a ledger that skipped the pull requests is refused, and says which source"
Refuses "empty.md"               "no entries"                      "a ledger with a header and no entries is refused rather than passing vacuously"

Write-Host ""
Write-Host "--- the ways a review found to pass the gate without reading anything ---" -ForegroundColor Cyan

# Each of these produced ZERO findings against the first version of the gate. They are the reason
# this suite exists in its current form.
Refuses "dir-as-test.md"         "is not a file"                   "a directory named as the test is refused, not silently passed"
Refuses "short-assertion.md"     "at least three words"            "a one-letter assertion is refused - it would match almost any file"
Refuses "self-reference.md"      "test script under test/"         "a ledger naming ITSELF as the test is refused"
Refuses "unquoted.md"            "as a quoted string"              "text that appears in the test but not as a quoted string is refused"
Refuses "outside-repo.md"        "outside the repository"          "a path that climbs out of the repository is refused"
Refuses "comment-dot.md"         "comment disposition needs where" "a comment carried in '.' is refused"
Refuses "comment-no-phrase.md"   "comment disposition needs where" "a comment with no quoted phrase is refused - the gate must be able to find the lesson"
Refuses "comment-phrase-absent.md" "does not contain the phrase"   "a comment whose phrase is not in the named file is refused"
Refuses "comment-missing-file.md" "does not exist"                 "a comment naming a file that does not exist is refused"

Write-Host ""
Write-Host "--- refusals that had no fixture before the review ---" -ForegroundColor Cyan

Refuses "no-module.md"           "no module: line"                 "a ledger with no module line is refused"
Refuses "no-replaces.md"         "no replaces: line"               "a ledger that does not say what it replaces is refused"
Refuses "unknown-disposition.md" "unknown disposition"             "an unknown disposition is refused"
Refuses "bad-heading.md"         "must begin with L-"              "an entry heading without an L-number is refused"
Refuses "malformed-test-where.md" "test disposition needs where"   "a test disposition without the file :: quote form is refused"
Refuses "weak-reason.md"         "reason of at least a sentence"   "a reason made of one word repeated is refused"
Refuses "header-in-body.md"      "is not marked searched"          "sources claimed inside an entry, not the header, do not count"

Write-Host ""
Write-Host "--- found by the re-review of the fixes ---" -ForegroundColor Cyan

# THE ROT CASE THE GATE EXISTS FOR: a test was deleted, and a comment in the test file still quotes
# its name. The quoted-string rule alone accepted it.
Refuses "quoted-in-comment.md"   "only in a comment"               "a test name that survives only in a comment is refused - the assertion was deleted"
# A ledger carrying its own lesson, outside planning/ledger where the path rule alone would catch it.
Refuses "comment-self.md"        "the ledger itself"               "a ledger naming itself as the carrier of its comment is refused, wherever it lives"
# THE MESSAGE NAMES WHAT THE LEDGER WROTE. PowerShell variable names ignore case, so a local $rel
# silently overwrote the $Rel parameter and every message showed a computed path instead - for "." it
# printed nothing at all after the colon.
Check (Says (Findings "outside-repo.md") "../outside.ps1") "a refusal quotes the path the ledger actually wrote, not a rewritten one"

# A JUNCTION UNDER test/ POINTING OUTSIDE THE REPOSITORY. The containment check was lexical -
# GetFullPath never follows links - so a link inside test/ reached anything. Git cannot commit a
# junction, but it can commit a symlink, which is real on checkouts that allow them. Built here at
# run time, in a throwaway copy, because a junction cannot live in the fixtures.
$jr = Join-Path $env:TEMP ("horde-ledger-jn-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
$outside = $jr + "-outside"
New-Item -ItemType Directory -Force (Join-Path $jr "test") | Out-Null
New-Item -ItemType Directory -Force $outside | Out-Null
Set-Content -LiteralPath (Join-Path $outside "test-evil.ps1") -Value 'Check ($true) "a lesson enforced from outside"' -Encoding ascii
& cmd.exe /c mklink /J (Join-Path $jr "test\jn") $outside | Out-Null
$isLink = [bool]((Get-Item -LiteralPath (Join-Path $jr "test\jn") -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)
Check $isLink "PRECONDITION: the junction really was created, so the next check means something"
$jl = (Get-Content -LiteralPath (Join-Path $fx "complete.md") -Raw) -replace "`r", ""
$jl = ($jl -split "### ")[0] + "### L-001 Reaches outside through a junction`n- source: s`n- disposition: test`n- where: test/jn/test-evil.ps1 :: `"a lesson enforced from outside`"`n"
[System.IO.File]::WriteAllText((Join-Path $jr "junction.md"), $jl)
$jf = @(Test-HordeLedger -Path (Join-Path $jr "junction.md") -RepoRoot $jr)
Check ((Says $jf "link") -and $jf.Count -eq 1) "a path through a junction or symlink is refused, even inside test/"
& cmd.exe /c rmdir (Join-Path $jr "test\jn") | Out-Null
Remove-Item -Recurse -Force $jr, $outside -ErrorAction SilentlyContinue

# THE TRULY EMPTY FILE fails for several reasons at once, correctly, so it is the one fixture not held
# to exactly one finding. What matters is that it fails, says why, and does not fail by accident: the
# first version produced findings about an "unnumbered" entry here, because Get-Content -Raw returns
# $null for an empty file and the parser then split $null.
$te = @(Findings "truly-empty.md")
Check (Says $te "no entries") "a zero-byte ledger is refused as having no entries"
Check (-not (Says $te "unnumbered")) "and not by accident - no phantom entry is invented from nothing"

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
# PRECONDITION FIRST. Without it the next check passes when the README is simply missing - a review
# found exactly that: a check that could not fail.
Check (Test-Path -LiteralPath (Join-Path $root "planning\ledger\README.md")) "PRECONDITION: the format README exists, so the next check means something"
Check (@(Get-HordeLedgerFiles -Dir (Join-Path $root "planning\ledger") | Where-Object { $_.Name -eq "README.md" }).Count -eq 0) "the format README is not mistaken for a ledger"

Complete-HordeSuite -Success "the ledger gate refuses a module nobody read"
