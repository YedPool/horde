# DOES tools\Mutate.ps1 -Changed RUN EXACTLY THE MUTANTS A CHANGE COULD HAVE MADE THE SUITES MISS?
# A selector that drops a mutant it should have run makes a review round green for the wrong reason,
# so it is held to an exact answer on a fixture repository built here: two commits, with a modified
# line, an added line, a deleted line, a mutant new in its spec, an untracked target, a find string
# that is not there and one that is there twice. The selection must match the expected set exactly,
# both ways; the unplaceable mutants must actually be run; an empty diff selects none and says so; and a
# diff that touches a target but selects nothing fails. test\mutations\mutate-changed.psd1 breaks the
# selector one rule at a time and requires this suite to notice.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "tools\MutateChanged.ps1")

# ---------------------------------------------------------------------------------------------
# The parts, one rule at a time.
# ---------------------------------------------------------------------------------------------
$d = ConvertFrom-HordeDiffZero -Text (@(
    "diff --git a/Tools/X.ps1 b/Tools/X.ps1",
    "--- a/Tools/X.ps1",
    "+++ b/Tools/X.ps1",
    "@@ -3 +3 @@ function A",
    "@@ -10,0 +11,2 @@",
    "@@ -20,2 +21,0 @@",
    "diff --git a/gone.ps1 b/gone.ps1",
    "deleted file mode 100644",
    "--- a/gone.ps1",
    "+++ /dev/null",
    "@@ -1,2 +0,0 @@") -join "`n")
Check ($d.ContainsKey("tools/x.ps1")) "a diff path is keyed in one spelling: forward slashes, lower case"
Check ((ConvertTo-HordeDiffKey "Tools\X.ps1") -ceq "tools/x.ps1") "and a spec's backslash path reaches the same key"
# Compared with -ceq: -eq, and a PowerShell hashtable's keys, ignore case, so they would pass a key
# that kept its case - which a case-sensitive set of keys would then miss (mutant keys-keep-case
# survived on 2026-10-02 until this check compared exactly).
Check ((ConvertTo-HordeDiffKey "./Hosts/A.PS1") -ceq "hosts/a.ps1") "a key is lower case and has no leading ./, exactly"
Check ($d["tools/x.ps1"].Contains(3)) "a hunk with no count is one modified line"
Check (-not $d["tools/x.ps1"].Contains(4) -and -not $d["tools/x.ps1"].Contains(2)) "and only that one line"
Check ($d["tools/x.ps1"].Contains(11) -and $d["tools/x.ps1"].Contains(12)) "a hunk of two added lines marks both"
Check (-not $d["tools/x.ps1"].Contains(13) -and -not $d["tools/x.ps1"].Contains(10)) "and neither line around them"
Check ($d["tools/x.ps1"].Contains(21) -and $d["tools/x.ps1"].Contains(22)) "a pure deletion marks the lines on both sides of the gap"
Check ($d.ContainsKey("gone.ps1")) "a deleted file is still a touched file"
Check ((ConvertFrom-HordeDiffZero -Text "").Count -eq 0) "an empty diff touches nothing"

$crlf = "line one`r`nfunction Get-B { return 2 }`r`nline three`r`nGet-Dup Get-Dup`r`n"
Check ((Find-HordeMutantLine -Text $crlf -Find "return 2").line -eq 2) "a find string is placed on its line, CRLF or not"
Check ((Find-HordeMutantLine -Text $crlf -Find "line three").line -eq 3) "CONTROL: a later line is placed further down"
Check ((Find-HordeMutantLine -Text $crlf -Find "absent").status -eq "missing") "a find string that is not there cannot be placed"
Check ((Find-HordeMutantLine -Text $crlf -Find "Get-Dup").status -eq "ambiguous") "a find string that is there twice cannot be placed"
Check ((Find-HordeMutantLine -Text $null -Find "x").status -eq "missing") "neither can one whose target file is missing"
# A find string that spans lines is refused by tools\Mutate.ps1, so it cannot be placed on one line either
# (review of PR #63: the selector placed it on its first line, so -Changed could skip what the full run fails).
Check ((Find-HordeMutantLine -Text "a`r`nb`r`n" -Find "a`r`nb").status -eq "multiline") "a find string that spans lines cannot be placed"
$mlRows = @(Select-HordeChangedMutants -Specs @([pscustomobject]@{ spec = "s.psd1"; data = @{ Target = "t.ps1"; Suite = "x.ps1"; Mutations = @(@{ Name = "ml"; Find = "a`nb"; Replace = "c" }) }; text = "a`nb`n"; specChanged = $false }) -Changed @{})
Check (@($mlRows | Where-Object { $_.selected -and $_.reason -match "spans lines" }).Count -eq 1) "and is run, to be safe"

# A DIFF THAT IS NOT EMPTY BUT PARSES TO NOTHING IS AN ERROR, never "the diff is empty" (review of PR #63:
# with diff.noprefix or diff.mnemonicPrefix set, every header failed to parse and an edited mutant line
# was skipped with exit 0).
$odd = "diff --git i/t.ps1 w/t.ps1`n--- i/t.ps1`n+++ w/t.ps1`n@@ -3 +3 @@`n"
Check ("$(Get-HordeDiffParseProblem -Text $odd -Changed (ConvertFrom-HordeDiffZero -Text $odd))" -match "parsed") "a diff whose headers do not parse is reported, not read as empty"
$two = "diff --git a/x.ps1 b/x.ps1`n+++ b/x.ps1`n@@ -1 +1 @@`ndiff --git i/y.ps1 w/y.ps1`n+++ w/y.ps1`n@@ -1 +1 @@`n"
Check ("$(Get-HordeDiffParseProblem -Text $two -Changed (ConvertFrom-HordeDiffZero -Text $two))" -match "parsed") "so is one where only some files parse"
$okd = "diff --git a/x.ps1 b/x.ps1`n+++ b/x.ps1`n@@ -1 +1 @@`n"
Check ("$(Get-HordeDiffParseProblem -Text $okd -Changed (ConvertFrom-HordeDiffZero -Text $okd))" -eq "") "CONTROL: a diff that parses whole is not reported"
Check ([string](Get-HordeDiffParseProblem -Text "" -Changed @{}) -eq "") "CONTROL: an empty diff is not reported"

$one = New-Object 'System.Collections.Generic.HashSet[int]'; [void]$one.Add(1)
$rowSel = @([pscustomobject]@{ target = "a.ps1"; selected = $true })
$rowSkip = @([pscustomobject]@{ target = "a.ps1"; selected = $false })
Check ((Get-HordeSelectionVerdict -Rows $rowSel -Changed @{ "a.ps1" = $one }).ok) "a selection of one is accepted"
Check ((Get-HordeSelectionVerdict -Rows $rowSkip -Changed @{}).ok) "none selected on an empty diff is accepted"
Check ((Get-HordeSelectionVerdict -Rows $rowSkip -Changed @{ "b.ps1" = $one }).ok) "none selected on a diff that touches no target is accepted"
Check (-not (Get-HordeSelectionVerdict -Rows $rowSkip -Changed @{ "a.ps1" = $one }).ok) "none selected on a diff that touches a target is an error"

# ---------------------------------------------------------------------------------------------
# The whole tool, on a fixture repository with two commits.
# ---------------------------------------------------------------------------------------------
$fx = Join-Path $env:TEMP ("horde-mutchg-" + [guid]::NewGuid().ToString("N"))
function Write-Fx { param([string]$Rel, [string[]]$Lines) $p = Join-Path $fx $Rel; New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null; [System.IO.File]::WriteAllText($p, (($Lines -join "`n") + "`n")) }
function Invoke-Fx { param([string[]]$GitArgs) $null = & git -C $fx -c user.name=fixture -c user.email=fixture@example.invalid -c core.autocrlf=false @GitArgs; return $LASTEXITCODE }
function Invoke-FxMutate {
    # The tool as a user runs it, in the fixture repository. Its lines, and its exit code.
    param([string[]]$ToolArgs)
    $lines = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fx "tools\Mutate.ps1") @ToolArgs | ForEach-Object { "$_" })
    return [pscustomobject]@{ code = $LASTEXITCODE; lines = $lines }
}
function Get-Picked { param([string[]]$Lines, [string]$Tag) return @($Lines | Where-Object { $_ -match ('^\s*\[' + $Tag + '\] \S+ :: (\S+) - ') } | ForEach-Object { [regex]::Match($_, ':: (\S+) - ').Groups[1].Value } | Sort-Object) }
function Test-SameSet { param([string[]]$A, [string[]]$B) return ((@($A | Sort-Object) -join ",") -eq (@($B | Sort-Object) -join ",")) }

try {
    New-Item -ItemType Directory -Path $fx | Out-Null
    foreach ($rel in @("tools\Mutate.ps1", "tools\MutateChanged.ps1", "test\lib\SuiteFiles.ps1", "test\lib\SuiteSections.ps1", "test\lib\Suite.ps1", "core\Platform.ps1", "core\Tristate.ps1")) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent (Join-Path $fx $rel)) | Out-Null
        Copy-Item -LiteralPath (Join-Path $root $rel) -Destination (Join-Path $fx $rel)
    }
    $null = Invoke-Fx @("init", "-q")
    $suiteLines = @(
        '$ErrorActionPreference = "Stop"',
        '. (Join-Path (Split-Path -Parent $PSScriptRoot) "target.ps1")',
        'foreach ($p in @(@("Get-A", 1), @("Get-B", 2), @("Get-C", 3), @("Get-D", 4), @("Get-E", 5), @("Get-F", 6), @("Get-New", 9))) {',
        '    if ((& $p[0]) -ne $p[1]) { Write-Host ("  [FAIL] " + $p[0] + " returns " + $p[1]); exit 1 }',
        '}',
        'exit 0')
    Write-Fx "test\fixture-suite.ps1" $suiteLines
    Write-Fx "other.ps1" @('function Get-Other { return 7 }')
    Write-Fx "test\other-suite.ps1" @('. (Join-Path (Split-Path -Parent $PSScriptRoot) "other.ps1")', 'if ((Get-Other) -ne 7) { Write-Host "  [FAIL] Get-Other returns 7"; exit 1 }', 'exit 0')
    # Commit 1. Get-New does not exist yet, so the suite would fail here; nothing runs at this commit.
    Write-Fx "target.ps1" @(
        '# fixture target for test-mutate-changed.ps1',
        'function Get-A { return 1 }',
        'function Get-B { return 2 }',
        'function Get-C { return 3 }',
        'function Get-D { return 4 }',
        '# a comment the second commit deletes',
        'function Get-E { return 5 }',
        'function Get-F { return 6 }')
    $mainV1 = @(
        '@{ Target = "target.ps1"; Suite = "test\fixture-suite.ps1"; Mutations = @(',
        '  @{ Name = "a-unchanged"; Find = "return 1 }"; Replace = "return -1 }" }',
        '  @{ Name = "b-modified"; Find = "return (1 + 1)"; Replace = "return 3" }',
        '  @{ Name = "c-unchanged"; Find = "return 3 }"; Replace = "return -3 }" }',
        '  @{ Name = "new-added"; Find = "return 9"; Replace = "return -9" }',
        '  @{ Name = "d-before-gap"; Find = "return 4"; Replace = "return -4" }',
        '  @{ Name = "e-after-gap"; Find = "return 5"; Replace = "return -5" }',
        '  @{ Name = "f-unchanged"; Find = "return 6"; Replace = "return -6" }',
        '  @{ Name = "missing"; Find = "return 42"; Replace = "return 43" }',
        '  @{ Name = "ambiguous"; Find = "function Get-"; Replace = "function Got-" }')
    Write-Fx "test\mutations\main.psd1" ($mainV1 + @(') }'))
    Write-Fx "test\mutations\extra.psd1" @('@{ Target = "target.ps1"; Suite = "test\fixture-suite.ps1"; Environment = @{ HORDE_FIXTURE_LEVEL = "1" }; Mutations = @(', '  @{ Name = "x-env"; Find = "function Get-C {"; Replace = "function Get-C { return 0 }; function Old-C {" }', ') }')
    Write-Fx "test\mutations\clean.psd1" @('@{ Target = "target.ps1"; Suite = "test\fixture-suite.ps1"; Mutations = @(', '  @{ Name = "f-clean"; Find = "Get-F { return 6 }"; Replace = "Get-F { return 0 }" }', ') }')
    Write-Fx "test\mutations\other.psd1" @('@{ Target = "other.ps1"; Suite = "test\other-suite.ps1"; Mutations = @(', '  @{ Name = "other-one"; Find = "return 7"; Replace = "return 8" }', ') }')
    Write-Fx "test\mutations\untracked.psd1" @('@{ Target = "untracked.ps1"; Suite = "test\other-suite.ps1"; Mutations = @(', '  @{ Name = "u-whole"; Find = "return 11"; Replace = "return 12" }', ') }')
    # A PORT'S OWN SPEC, TWO FOLDERS BELOW ITS mutations FOLDER. -Changed finds specs by the rule the
    # spec guard uses (Get-HordeMutationSpecFiles); before, it searched four fixed folders one level
    # deep and never selected a spec the guard checked (review of PRs #62 and #63, 2026-10-02).
    Write-Fx "agents\demo\Code.ps1" @('function Get-Port { return 21 }', 'function Get-Other { return 22 }')
    Write-Fx "agents\demo\test\mutations\deep\deeper\demo.psd1" @('@{ Target = "agents\demo\Code.ps1"; Suite = "test\other-suite.ps1"; Mutations = @(', '  @{ Name = "port-line"; Find = "function Get-Port {"; Replace = "function Get-Port { return 0 }; function Old-Port {" }', '  @{ Name = "port-unchanged"; Find = "return 22"; Replace = "return 20" }', ') }')
    $c1 = (Invoke-Fx @("add", "-A")) + (Invoke-Fx @("commit", "-q", "-m", "one"))
    # Commit 2: line 3 modified, a line added after line 4, line 6 deleted, and a mutant added to its
    # spec on a line the diff does not touch.
    Write-Fx "target.ps1" @(
        '# fixture target for test-mutate-changed.ps1',
        'function Get-A { return 1 }',
        'function Get-B { return (1 + 1) }',
        'function Get-C { return 3 }',
        'function Get-New { return 9 }',
        'function Get-D { return 4 }',
        'function Get-E { return 5 }',
        'function Get-F { return 6 }')
    # A spec whose only change is its Environment: what its suite runs changed, so every mutant of it
    # runs again (review of PR #63, probe P4: a narrowed HORDE_SECTIONS reselected nothing).
    Write-Fx "test\mutations\extra.psd1" @('@{ Target = "target.ps1"; Suite = "test\fixture-suite.ps1"; Environment = @{ HORDE_FIXTURE_LEVEL = "2" }; Mutations = @(', '  @{ Name = "x-env"; Find = "function Get-C {"; Replace = "function Get-C { return 0 }; function Old-C {" }', ') }')
    Write-Fx "agents\demo\Code.ps1" @('function Get-Port { return (20 + 1) }', 'function Get-Other { return 22 }')
    $c2 = (Invoke-Fx @("add", "-A")) + (Invoke-Fx @("commit", "-q", "-m", "two"))
    Check ($c1 -eq 0 -and $c2 -eq 0) "CONTROL: the fixture repository has its two commits"

    # AN EMPTY DIFF selects none and says so - before the untracked file exists, so the tree is HEAD.
    $empty = Invoke-FxMutate @("-Changed", "HEAD", "-Spec", "test\mutations\other.psd1")
    Check ($empty.code -eq 0) "an empty diff is not an error"
    Check (@($empty.lines | Where-Object { $_ -match '^changed: selected none of 1 mutants: the diff is empty' }).Count -eq 1) "an empty diff selects none, and says why"
    Check (@($empty.lines | Where-Object { $_ -match '^mutations: none selected - ' }).Count -eq 1) "and says so in the line a gate reads, with no number a gate could count as a run"
    Check (@(Get-Picked $empty.lines "SELECT").Count -eq 0) "and no mutant is listed as selected"

    # An untracked target: every line of it is new.
    Write-Fx "untracked.ps1" @('function Get-U { return 11 }')

    # THE SELECTION, EXACTLY: every mutant expected in, every mutant expected out.
    $plan = Invoke-FxMutate @("-Changed", "HEAD~1", "-Plan")
    $wantIn = @("b-modified", "new-added", "d-before-gap", "e-after-gap", "missing", "ambiguous", "x-env", "u-whole", "port-line")
    $wantOut = @("a-unchanged", "c-unchanged", "f-unchanged", "f-clean", "port-unchanged")
    Check ($plan.code -eq 0) "the plan of a two-commit diff exits 0"
    Check (Test-SameSet (Get-Picked $plan.lines "SELECT") $wantIn) ("the selected mutants are exactly " + ($wantIn -join ", ") + " (got " + ((Get-Picked $plan.lines "SELECT") -join ", ") + ")")
    Check (Test-SameSet (Get-Picked $plan.lines "SKIP") $wantOut) ("the mutants skipped one by one are exactly " + ($wantOut -join ", ") + " (got " + ((Get-Picked $plan.lines "SKIP") -join ", ") + ")")
    Check (@($plan.lines | Where-Object { $_ -match '^\s*\[SKIP\] test\\mutations\\other\.psd1: all 1 mutants - other\.ps1 is not in the diff' }).Count -eq 1) "a spec whose target is not in the diff is skipped whole, and says why"
    Check (@($plan.lines | Where-Object { $_ -match ':: b-modified - line 3 of target\.ps1 is added or modified' }).Count -eq 1) "a selected mutant says which changed line it sits on"
    Check (@($plan.lines | Where-Object { $_ -match ':: missing - find string not found .*fail safe' }).Count -eq 1) "a mutant that cannot be found says it runs to be safe"
    Check (@($plan.lines | Where-Object { $_ -match ':: ambiguous - find string occurs \d+ times .*fail safe' }).Count -eq 1) "a mutant found more than once says it runs to be safe"
    Check (@($plan.lines | Where-Object { $_ -match ':: x-env - its spec file changed' }).Count -eq 1) "every mutant of a spec whose file changed runs, and says why"
    Check (@($plan.lines | Where-Object { $_ -match ':: c-unchanged - line 4 of target\.ps1 is unchanged' }).Count -eq 1) "a skipped mutant says its line is unchanged"
    Check (@($plan.lines | Where-Object { $_.Contains(":: port-line - line 1 of agents\demo\Code.ps1 is added or modified") }).Count -eq 1) "a changed line in a port's own code selects the mutant in that port's spec, two folders below its mutations folder"
    Check (@($plan.lines | Where-Object { $_.Contains("agents\demo\test\mutations\deep\deeper\demo.psd1 :: port-unchanged - line 2 of agents\demo\Code.ps1 is unchanged") }).Count -eq 1) "and that spec's mutant on an unchanged line is listed as skipped, so the spec was found"
    Check (@($plan.lines | Where-Object { $_ -match '^changed: selected 9 of 15 mutants; skipped 6 as unchanged' }).Count -eq 1) "the totals are stated"
    Check (@($plan.lines | Where-Object { $_ -match '^mutations: ' }).Count -eq 0) "a plan prints no result line a gate could read as a run"

    # HOSTILE GIT CONFIGURATION CHANGES NOTHING. Each of these changes what `git diff` prints by default
    # (review of PR #63, probes P9 and P10: with the first two, an edited mutant line read as "0 files
    # changed" and was skipped, exit 0). Set in the repository's own config, as a user's would be.
    $hostile = @(@("diff.noprefix", "true"), @("diff.mnemonicPrefix", "true"), @("diff.srcPrefix", "SRC/"), @("diff.dstPrefix", "DST/"), @("color.diff", "always"), @("color.ui", "always"), @("diff.external", "no-such-diff-tool"), @("diff.relative", "true"), @("core.quotepath", "true"))
    foreach ($h in $hostile) {
        $null = Invoke-Fx @("config", $h[0], $h[1])
        $hp = Invoke-FxMutate @("-Changed", "HEAD~1", "-Plan")
        $null = Invoke-Fx @("config", "--unset", $h[0])
        Check ($hp.code -eq 0 -and (Test-SameSet (Get-Picked $hp.lines "SELECT") $wantIn)) ("with " + $h[0] + "=" + $h[1] + " the selection is unchanged (exit " + $hp.code + ", got " + ((Get-Picked $hp.lines "SELECT") -join ", ") + ")")
    }
    foreach ($h in $hostile) { $null = Invoke-Fx @("config", $h[0], $h[1]) }
    $hp = Invoke-FxMutate @("-Changed", "HEAD~1", "-Plan")
    foreach ($h in $hostile) { $null = Invoke-Fx @("config", "--unset", $h[0]) }
    Check ($hp.code -eq 0 -and (Test-SameSet (Get-Picked $hp.lines "SELECT") $wantIn)) ("with all of them at once the selection is unchanged (exit " + $hp.code + ")")

    # THE UNPLACEABLE MUTANTS ARE RUN, not skipped - and a run of them fails, because they do not apply.
    $run = Invoke-FxMutate @("-Changed", "HEAD~1", "-Spec", "test\mutations\main.psd1")
    Check ($run.code -eq 1) "a run that includes mutants which do not apply fails"
    Check (@($run.lines | Where-Object { $_ -match '\[BAD\] missing: did not apply: the find string occurs 0 times' }).Count -eq 1) "the mutant that cannot be found was run, and reported"
    Check (@($run.lines | Where-Object { $_ -match '\[BAD\] ambiguous: did not apply: the find string occurs \d+ times' }).Count -eq 1) "the mutant found more than once was run, and reported"
    Check (@($run.lines | Where-Object { $_ -match '\[OK\] b-modified: caught' }).Count -eq 1) "a selected mutant on a changed line was run, and caught"
    Check (@($run.lines | Where-Object { $_ -match '\[(OK|BAD)\] (a-unchanged|c-unchanged|f-unchanged):' }).Count -eq 0) "no skipped mutant was run"
    Check (@($run.lines | Where-Object { $_ -match '^mutations: 6, as expected: 4, not: 2' }).Count -eq 1) "the result line counts exactly the selected mutants"
    Check (@($run.lines | Where-Object { $_ -match '^mutations: ' }).Count -eq 1) "and it is the only line a gate reads as the result"

    # A DIFF THAT TOUCHES A TARGET BUT SELECTS NOTHING IS AN ERROR. Commit 3 edits only the comment.
    Remove-Item -LiteralPath (Join-Path $fx "untracked.ps1")
    $t = [System.IO.File]::ReadAllText((Join-Path $fx "target.ps1")).Replace("# fixture target for", "# the fixture target for")
    [System.IO.File]::WriteAllText((Join-Path $fx "target.ps1"), $t)
    $c3 = (Invoke-Fx @("add", "-A")) + (Invoke-Fx @("commit", "-q", "-m", "three"))
    $zero = Invoke-FxMutate @("-Changed", "HEAD~1", "-Spec", "test\mutations\clean.psd1")
    Check ($c3 -eq 0 -and $zero.code -eq 2) "a diff that touches a mutation target and selects nothing exits 2, not 0"
    Check (@($zero.lines | Where-Object { $_ -match 'selected none, yet the diff touches the mutation target\(s\) target\.ps1' }).Count -ge 1) "and names the target it touched"
    Check (@($zero.lines | Where-Object { $_ -match '^mutations: ' }).Count -eq 0) "and prints no result line a gate could read as a pass"
    $zeroOther = Invoke-FxMutate @("-Changed", "HEAD~1", "-Spec", "test\mutations\other.psd1")
    Check ($zeroOther.code -eq 0 -and @($zeroOther.lines | Where-Object { $_ -match 'the diff touches no mutation target' }).Count -ge 1) "CONTROL: the same diff, against a spec whose target it does not touch, selects none and passes"

    # A DIFF THAT DOES NOT PARSE STOPS THE TOOL, end to end. The prefixes are forced, so no git setting
    # reaches this path any more; a git that prints other prefixes anyway (a wrapper, a future
    # default) is played by a shim first on PATH that rewrites a/ to i/ in every diff header. Without
    # this check the tool's own refusal could be deleted and every check above would still pass
    # (mutant parse-problem-ignored survived the remote gate on 2026-10-02).
    $shimDir = $fx + "-shim"
    New-Item -ItemType Directory -Path $shimDir | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $shimDir "git.cmd"), "@powershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0shim.ps1`" %*`r`n")
    [System.IO.File]::WriteAllText((Join-Path $shimDir "shim.ps1"), (@(
        '$out = @(& $env:HORDE_TEST_REAL_GIT @args)',
        '$code = $LASTEXITCODE',
        'foreach ($l in $out) { $t = ("" + $l) -replace "^diff --git a/", "diff --git i/"; [Console]::Out.WriteLine($t) }',
        'exit $code') -join "`r`n"))
    $realGit = @(Get-Command git.exe -CommandType Application)[0].Source
    $pathBefore = $env:PATH
    $env:HORDE_TEST_REAL_GIT = $realGit
    $env:PATH = $shimDir + ";" + $env:PATH
    try { $shimmed = Invoke-FxMutate @("-Changed", "HEAD~1", "-Plan") } finally { $env:PATH = $pathBefore; $env:HORDE_TEST_REAL_GIT = $null }
    Check ($shimmed.code -eq 2) ("a diff whose headers do not parse exits 2, not 0 (exit " + $shimmed.code + ")")
    Check (@($shimmed.lines | Where-Object { $_ -match 'refusing to read it as unchanged' }).Count -eq 1) "and says it will not read it as unchanged"
    Check (@($shimmed.lines | Where-Object { $_ -match '^\s*\[(SELECT|SKIP)\]' }).Count -eq 0) "and selects nothing from it"
    $unshimmed = Invoke-FxMutate @("-Changed", "HEAD~1", "-Plan")
    Check ($unshimmed.code -eq 0) "CONTROL: with the real git first on PATH again, the same plan exits 0"
    if ((Split-Path -Leaf $shimDir) -match '^horde-mutchg-[0-9a-f]{32}-shim\z') { Remove-Item -LiteralPath $shimDir -Recurse -Force -ErrorAction SilentlyContinue }

    # -Changed VERIFIES EVERY MAPPED CATCH ON THE WHOLE SUITE (review of #115, round 2). A change is what
    # moves a mutant onto a path its section takes only when run alone; here section "use" computes its
    # value alone and reads a warm cache when run whole, so its catch of cold-path is no catch at all.
    Write-Fx "cache.ps1" @('$script:valCache = $null', 'function Get-Val { if ($null -ne $script:valCache) { return $script:valCache }; return (2 + 3) }', 'function Set-ValCache { $script:valCache = 5 }')
    Write-Fx "test\cache-suite.ps1" @(
        '. (Join-Path $PSScriptRoot "lib\Suite.ps1")',
        'trap { Register-HordeSuiteError $_; continue }',
        'Register-HordeSuiteSections -Ids @("warm", "use")',
        '. (Join-Path (Split-Path -Parent $PSScriptRoot) "cache.ps1")',
        'if (Enter-HordeSuiteSection "warm" "warm the cache") {',
        '    trap { Register-HordeSuiteError $_; continue }',
        '    Set-ValCache',
        '    Check ((Get-Val) -eq 5) "the warmed value is five"',
        '}',
        'if (Enter-HordeSuiteSection "use" "use the value") {',
        '    trap { Register-HordeSuiteError $_; continue }',
        '    Check ((Get-Val) -eq 5) "Get-Val returns five"',
        '}',
        'Complete-HordeSuite -Success "warm, then use"')
    Write-Fx "test\mutations\cache.psd1" @('@{ Target = "cache.ps1"; Suite = "test\cache-suite.ps1"; Mutations = @(', '  @{ Name = "cold-path"; Find = "return (2 + 3)"; Replace = "return (2 + 4)"; Sections = @("use") }', ') }')
    $c4 = (Invoke-Fx @("add", "-A")) + (Invoke-Fx @("commit", "-q", "-m", "four"))
    Write-Fx "cache.ps1" @('$script:valCache = $null', 'function Get-Val { if ($null -ne $script:valCache) { return $script:valCache }; return (2 + 3) } # computed', 'function Set-ValCache { $script:valCache = 5 }')
    $cold = Invoke-FxMutate @("-Changed", "HEAD", "-Spec", "test\mutations\cache.psd1")
    Check ($c4 -eq 0 -and @(Get-Picked $cold.lines "SELECT") -join "," -ceq "cold-path") ("CONTROL: the changed line selects the mapped mutant (" + ((Get-Picked $cold.lines "SELECT") -join ", ") + ")")
    Check ($cold.code -eq 1 -and @($cold.lines | Where-Object { $_ -match '\[BAD\] cold-path: survived \(expected caught\)' }).Count -eq 1) ("-Changed runs it with its map verified: the whole suite's survival stands (exit " + $cold.code + ")")
    Check (@($cold.lines | Where-Object { $_ -match '\[MAP-HIDES\] cold-path' }).Count -eq 1) "and names the map that hid it"

    # THE ARGUMENTS.
    $noArgs = Invoke-FxMutate @()
    Check ($noArgs.code -eq 2) "with neither -Spec nor -Changed the tool refuses to run"
    $both = Invoke-FxMutate @("-Changed", "HEAD~1", "-Only", "b-modified")
    Check ($both.code -eq 2 -and @($both.lines | Where-Object { $_ -match '-Only and -Changed' }).Count -eq 1) "-Only and -Changed together are refused"
    $badRef = Invoke-FxMutate @("-Changed", "no-such-ref-anywhere", "-Plan")
    Check ($badRef.code -eq 2 -and @($badRef.lines | Where-Object { $_ -match 'cannot find the merge-base' }).Count -eq 1) "a base that does not resolve is an error, not an empty diff"
} finally {
    if (Test-Path -LiteralPath ($fx + "-shim")) { Remove-Item -LiteralPath ($fx + "-shim") -Recurse -Force -ErrorAction SilentlyContinue }
    if ((Split-Path -Leaf $fx) -match '^horde-mutchg-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $fx)) { Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue }
}

Complete-HordeSuite -Success "-Changed selects exactly the mutants a change could hide, runs the ones it cannot place, and never reads zero as a pass"
