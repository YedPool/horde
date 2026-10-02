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
Check ((ConvertTo-HordeDiffKey "Tools\X.ps1") -eq "tools/x.ps1") "and a spec's backslash path reaches the same key"
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
    foreach ($rel in @("tools\Mutate.ps1", "tools\MutateChanged.ps1", "test\lib\SuiteFiles.ps1")) {
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
    Write-Fx "test\mutations\clean.psd1" @('@{ Target = "target.ps1"; Suite = "test\fixture-suite.ps1"; Mutations = @(', '  @{ Name = "f-clean"; Find = "Get-F { return 6 }"; Replace = "Get-F { return 0 }" }', ') }')
    Write-Fx "test\mutations\other.psd1" @('@{ Target = "other.ps1"; Suite = "test\other-suite.ps1"; Mutations = @(', '  @{ Name = "other-one"; Find = "return 7"; Replace = "return 8" }', ') }')
    Write-Fx "test\mutations\untracked.psd1" @('@{ Target = "untracked.ps1"; Suite = "test\other-suite.ps1"; Mutations = @(', '  @{ Name = "u-whole"; Find = "return 11"; Replace = "return 12" }', ') }')
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
    Write-Fx "test\mutations\main.psd1" ($mainV1 + @('  @{ Name = "a-new-in-spec"; Find = "Get-A { return 1 }"; Replace = "Get-A { return 0 }" }', ') }'))
    $c2 = (Invoke-Fx @("add", "-A")) + (Invoke-Fx @("commit", "-q", "-m", "two"))
    Check ($c1 -eq 0 -and $c2 -eq 0) "CONTROL: the fixture repository has its two commits"

    # AN EMPTY DIFF selects none and says so - before the untracked file exists, so the tree is HEAD.
    $empty = Invoke-FxMutate @("-Changed", "HEAD", "-Spec", "test\mutations\other.psd1")
    Check ($empty.code -eq 0) "an empty diff is not an error"
    Check (@($empty.lines | Where-Object { $_ -match '^changed: selected none of 1 mutants: the diff is empty' }).Count -eq 1) "an empty diff selects none, and says why"
    Check (@($empty.lines | Where-Object { $_ -match '^mutations: 0 - ' }).Count -eq 1) "and reports zero mutants run, in the line a gate reads"
    Check (@(Get-Picked $empty.lines "SELECT").Count -eq 0) "and no mutant is listed as selected"

    # An untracked target: every line of it is new.
    Write-Fx "untracked.ps1" @('function Get-U { return 11 }')

    # THE SELECTION, EXACTLY: every mutant expected in, every mutant expected out.
    $plan = Invoke-FxMutate @("-Changed", "HEAD~1", "-Plan")
    $wantIn = @("b-modified", "new-added", "d-before-gap", "e-after-gap", "missing", "ambiguous", "a-new-in-spec", "u-whole")
    $wantOut = @("a-unchanged", "c-unchanged", "f-unchanged", "f-clean")
    Check ($plan.code -eq 0) "the plan of a two-commit diff exits 0"
    Check (Test-SameSet (Get-Picked $plan.lines "SELECT") $wantIn) ("the selected mutants are exactly " + ($wantIn -join ", ") + " (got " + ((Get-Picked $plan.lines "SELECT") -join ", ") + ")")
    Check (Test-SameSet (Get-Picked $plan.lines "SKIP") $wantOut) ("the mutants skipped one by one are exactly " + ($wantOut -join ", ") + " (got " + ((Get-Picked $plan.lines "SKIP") -join ", ") + ")")
    Check (@($plan.lines | Where-Object { $_ -match '^\s*\[SKIP\] test\\mutations\\other\.psd1: all 1 mutants - other\.ps1 is not in the diff' }).Count -eq 1) "a spec whose target is not in the diff is skipped whole, and says why"
    Check (@($plan.lines | Where-Object { $_ -match ':: b-modified - line 3 of target\.ps1 is added or modified' }).Count -eq 1) "a selected mutant says which changed line it sits on"
    Check (@($plan.lines | Where-Object { $_ -match ':: missing - find string not found .*fail safe' }).Count -eq 1) "a mutant that cannot be found says it runs to be safe"
    Check (@($plan.lines | Where-Object { $_ -match ':: ambiguous - find string occurs \d+ times .*fail safe' }).Count -eq 1) "a mutant found more than once says it runs to be safe"
    Check (@($plan.lines | Where-Object { $_ -match ':: a-new-in-spec - new or changed in its spec' }).Count -eq 1) "a mutant new in its spec says that is why it runs"
    Check (@($plan.lines | Where-Object { $_ -match ':: c-unchanged - line 4 of target\.ps1 is unchanged' }).Count -eq 1) "a skipped mutant says its line is unchanged"
    Check (@($plan.lines | Where-Object { $_ -match '^changed: selected 8 of 13 mutants; skipped 5 as unchanged' }).Count -eq 1) "the totals are stated"
    Check (@($plan.lines | Where-Object { $_ -match '^mutations: ' }).Count -eq 0) "a plan prints no result line a gate could read as a run"

    # THE UNPLACEABLE MUTANTS ARE RUN, not skipped - and a run of them fails, because they do not apply.
    $run = Invoke-FxMutate @("-Changed", "HEAD~1", "-Spec", "test\mutations\main.psd1")
    Check ($run.code -eq 1) "a run that includes mutants which do not apply fails"
    Check (@($run.lines | Where-Object { $_ -match '\[BAD\] missing: did not apply: the find string occurs 0 times' }).Count -eq 1) "the mutant that cannot be found was run, and reported"
    Check (@($run.lines | Where-Object { $_ -match '\[BAD\] ambiguous: did not apply: the find string occurs \d+ times' }).Count -eq 1) "the mutant found more than once was run, and reported"
    Check (@($run.lines | Where-Object { $_ -match '\[OK\] b-modified: caught' }).Count -eq 1) "a selected mutant on a changed line was run, and caught"
    Check (@($run.lines | Where-Object { $_ -match '\[(OK|BAD)\] (a-unchanged|c-unchanged|f-unchanged):' }).Count -eq 0) "no skipped mutant was run"
    Check (@($run.lines | Where-Object { $_ -match '^mutations: 7, as expected: 5, not: 2' }).Count -eq 1) "the result line counts exactly the selected mutants"
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

    # THE ARGUMENTS.
    $noArgs = Invoke-FxMutate @()
    Check ($noArgs.code -eq 2) "with neither -Spec nor -Changed the tool refuses to run"
    $both = Invoke-FxMutate @("-Changed", "HEAD~1", "-Only", "b-modified")
    Check ($both.code -eq 2 -and @($both.lines | Where-Object { $_ -match '-Only and -Changed' }).Count -eq 1) "-Only and -Changed together are refused"
    $badRef = Invoke-FxMutate @("-Changed", "no-such-ref-anywhere", "-Plan")
    Check ($badRef.code -eq 2 -and @($badRef.lines | Where-Object { $_ -match 'cannot find the merge-base' }).Count -eq 1) "a base that does not resolve is an error, not an empty diff"
} finally {
    if ((Split-Path -Leaf $fx) -match '^horde-mutchg-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $fx)) { Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue }
}

Complete-HordeSuite -Success "-Changed selects exactly the mutants a change could hide, runs the ones it cannot place, and never reads zero as a pass"
