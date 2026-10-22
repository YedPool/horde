# DOES THE NIGHTLY NET DECIDE RIGHT: THE WINDOW, THE DAY'S MERGES, NEWLY RED, THE BISECT, THE REPORT?
#
# core/NightlyNet.ps1 and tools/NightlyNet.ps1 (T-0331; the founder's rule of 2026-10-22: one nightly run per
# repo covers the day's merges and names the merge behind each new red, to M by 07:00). The decisions are pure
# and injected (clock, runner), so this needs no night, no slot and no suite run. The last section drives the
# real tool with -Plan, which runs nothing, against a throwaway git repository of its own: the merge range it
# lists is what git says, labelled from a guards-owed.jsonl of its own HORDE_HOME.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\NightlyNet.ps1")

function Dt { param([string]$S) return [datetime]("2026-10-22 " + $S) }

Write-Host ""
Write-Host "--- the night window: starts at 22:00 or later, nothing runs after 06:30 ---" -ForegroundColor Cyan
Check ((Test-HordeNightlyWindow -Now (Dt "21:59")) -eq $false) "21:59 is outside"
Check ((Test-HordeNightlyWindow -Now (Dt "22:00")) -eq $true) "22:00 is inside"
Check ((Test-HordeNightlyWindow -Now (Dt "03:00")) -eq $true) "03:00 is inside"
Check ((Test-HordeNightlyWindow -Now (Dt "06:29")) -eq $true) "06:29 is inside"
Check ((Test-HordeNightlyWindow -Now (Dt "06:30")) -eq $false) "06:30 is outside"
Check ((Test-HordeNightlyWindow -Now (Dt "14:00")) -eq $false) "14:00 is outside"
Check ((Get-HordeNightlyDeadline -Now (Dt "23:00")) -eq ([datetime]"2026-10-23 06:30") ) "from 23:00 the cutoff is 06:30 tomorrow"
Check ((Get-HordeNightlyDeadline -Now (Dt "02:00")) -eq ([datetime]"2026-10-22 06:30")) "from 02:00 the cutoff is 06:30 today"
$cut = [datetime]"2026-10-23 06:30"
Check ((Test-HordeNightlyMayStartRun -Now ([datetime]"2026-10-23 06:04:59") -Cutoff $cut -RunSeconds 1500) -eq $true) "a 1500 s run may start at 06:04:59 (it ends 06:29:59)"
Check ((Test-HordeNightlyMayStartRun -Now ([datetime]"2026-10-23 06:05:01") -Cutoff $cut -RunSeconds 1500) -eq $false) "and not at 06:05:01"

Write-Host ""
Write-Host "--- text for a tell: no double quote, semicolon or angle bracket ---" -ForegroundColor Cyan
$raw = "a ""quoted"" word; <tag> and `tick` and `$var`r`nnext" + [char]0xE9
$c = ConvertTo-HordeNightlyText $raw
Check ($c -notmatch '["<>;`$\r\n]') ("none of the forbidden characters survive (" + $c + ")")
Check ($c -cmatch '^[\x20-\x7E]*$') "and it is plain ASCII"
Check ($c -like "*quoted*" -and $c -like "*word*") "and stays readable"

Write-Host ""
Write-Host "--- the day's merges: git decides, the owed file labels ---" -ForegroundColor Cyan
$owedLines = @(
    '{"repo":"Y/h","pr":372,"task":"T-0331","by":"C","at":"2026-10-22T10:00:00Z","headSha":"aaaa","mergeSha":"2222222222222222222222222222222222222222","firstParent":"x"}',
    '{"repo":"Y/other","pr":9,"task":"T-1","by":"Z","mergeSha":"3333333333333333333333333333333333333333"}',
    'not json at all',
    '{"repo":"Y/h","pr":999,"task":"T-9","by":"Q","mergeSha":"9999999999999999999999999999999999999999"}')
$owed = Read-HordeNightlyOwed -Lines $owedLines -Repo "Y/h"
Check (@($owed.entries).Count -eq 2 -and $owed.bad -eq 1) ("two entries of this repo, one bad line (" + @($owed.entries).Count + ", " + $owed.bad + ")")
$git = @(
    ("1111111111111111111111111111111111111111`tMerge pull request #371 from Y/fix"),
    ("2222222222222222222222222222222222222222`tMerge pull request #372 from Y/idle"),
    ("4444444444444444444444444444444444444444`tdirect push to main"))
$mg = @(Get-HordeNightlyMerges -GitLines $git -Owed $owed)
Check ($mg.Count -eq 3 -and $mg[0].sha -like "1111*" -and $mg[2].sha -like "4444*") "all three first-parent commits, oldest first"
Check ($mg[1].pr -eq "372" -and $mg[1].task -ceq "T-0331" -and $mg[1].by -ceq "C" -and $mg[1].source -ceq "owed") "the owed entry labels its merge with PR, task and lane"
Check ($mg[0].pr -eq "371" -and $mg[0].source -ceq "git") "a merge with no owed entry takes its PR from the subject"
Check ($mg[2].pr -eq "" -and $mg[2].source -ceq "git") "a direct push is listed, with no PR"
Check (@($mg | Where-Object { $_.sha -like "9999*" }).Count -eq 0) "an owed entry git does not list is not a merge of this range"
Check (@(Get-HordeNightlyMerges -GitLines @()).Count -eq 0) "no commits, no merges"
Check ((Format-HordeNightlyMerge -Merge $mg[1]) -ceq "22222222 PR 372 T-0331 by C: Merge pull request #372 from Y/idle") ("the merge line (" + (Format-HordeNightlyMerge -Merge $mg[1]) + ")")

Write-Host ""
Write-Host "--- newly red is red now and green last night ---" -ForegroundColor Cyan
$nowV = @{ "a|ps51" = "red"; "b|ps51" = "red"; "c|ps51" = "red"; "d|ps51" = "green"; "e|ps51" = "unrun"; "f|ps51" = "green" }
$lastV = @{ "a|ps51" = "green"; "b|ps51" = "red"; "d|ps51" = "red"; "e|ps51" = "green"; "f|ps51" = "green" }
$cmp = Compare-HordeNightlyVerdicts -Now $nowV -Last $lastV
Check (($cmp.newlyRed -join ",") -ceq "a|ps51") "a was green and is red: newly red"
Check (($cmp.stillRed -join ",") -ceq "b|ps51") "b was red and is red: still red, never bisected"
Check (($cmp.newRed -join ",") -ceq "c|ps51") "c has no verdict from last night: red, not bisected"
Check (($cmp.fixed -join ",") -ceq "d|ps51") "d was red and is green: fixed"
Check (($cmp.unrun -join ",") -ceq "e|ps51") "e was not run: says nothing"

Write-Host ""
Write-Host "--- the bisect: the first merge at which the unit is red ---" -ForegroundColor Cyan
function Run-Bisect {
    # n merges m1..mn; the unit turns red at merge index $Break (1-based); $Flaky answers green at the tip; $Null at a given sha.
    param([int]$N, [int]$Break, [int]$Max = 40, [string]$NullAt = "")
    $shas = @(1..$N | ForEach-Object { "m" + $_ })
    $script:asked = @()
    $isRed = {
        param($sha)
        $script:asked += $sha
        if ($NullAt -ne "" -and $sha -ceq $NullAt) { return $null }
        return ([int]($sha.Substring(1)) -ge $Break)
    }
    return (Find-HordeNightlyCulprit -Merges $shas -IsRed $isRed -MaxRuns $Max)
}
foreach ($case in @(@(1, 1), @(2, 1), @(2, 2), @(5, 3), @(9, 1), @(9, 9), @(16, 7), @(10, 10))) {
    $r = Run-Bisect -N $case[0] -Break $case[1]
    Check ($r.state -ceq "found" -and $r.sha -ceq ("m" + $case[1])) ("of " + $case[0] + " merges, red from " + $case[1] + ": found m" + $case[1] + " (" + $r.state + " " + $r.sha + ")")
}
$r = Run-Bisect -N 16 -Break 7
Check ($r.runs -le 5) ("16 merges take at most 5 runs, the tip check included (" + $r.runs + ")")
Check (($script:asked | Select-Object -First 1) -ceq "m16") "the tip is run first"
Check ((Run-Bisect -N 0 -Break 1).state -ceq "none") "no merge since last night: nothing to name"
$r = Run-Bisect -N 8 -Break 99
Check ($r.state -ceq "flaky" -and $r.runs -eq 1) "a unit that is not red at the tip when run again is flaky, and no merge is blamed"
$r = Run-Bisect -N 8 -Break 3 -NullAt "m16"
Check ($r.state -ceq "found") "an answer for a sha it never asks about changes nothing"
$r = Run-Bisect -N 8 -Break 3 -NullAt "m8"
Check ($r.state -ceq "inconclusive") "a tip that could not be run is inconclusive"
$r = Run-Bisect -N 8 -Break 3 -NullAt "m4"
Check ($r.state -ceq "inconclusive" -and "" + $r.between[1] -ceq "m8") "a middle run that did not happen stops the search, saying how far it got"
$r = Run-Bisect -N 16 -Break 7 -Max 2
Check ($r.state -ceq "capped") "the run cap stops it, saying so"

Write-Host ""
Write-Host "--- the report ---" -ForegroundColor Cyan
$merge = $mg[1]
$rows = @(
    [pscustomobject]@{ repo = "Y/h"; tip = "abcdef0123456789"; lastTip = "0123456789abcdef"; merges = $mg
        guards = [pscustomobject]@{ state = "RED"; text = "test-host-names red; first merge: 22222222" }
        suiteCount = 350; unrunCount = 2
        compare = [pscustomobject]@{ newlyRed = @("test/test-x.ps1|pwsh7"); stillRed = @("test/test-old.ps1|ps51"); newRed = @(); fixed = @(); unrun = @() }
        culprits = @([pscustomobject]@{ unit = "test/test-x.ps1|pwsh7"; state = "found"; sha = $merge.sha; merge = $merge; runs = 3; between = @("", $merge.sha) })
        notes = @("a ""quoted"" note; with <brackets>"); incomplete = "" },
    [pscustomobject]@{ repo = "O/U"; tip = "ffffffff"; lastTip = ""; merges = @()
        guards = [pscustomobject]@{ state = "no repo-wide guard list"; text = "" }; suiteCount = 2; unrunCount = 0
        compare = [pscustomobject]@{ newlyRed = @(); stillRed = @(); newRed = @(); fixed = @(); unrun = @() }
        culprits = @(); notes = @(); incomplete = "the night ran out" })
$rep = New-HordeNightlyReport -Date "2026-10-22" -Repos $rows
Check ($rep -notmatch '["<>;]') "the report body has no double quote, semicolon or angle bracket"
Check ($rep -cmatch '^[\x20-\x7E\n]*$') "and is plain ASCII"
Check ($rep -like "*test/test-x.ps1|pwsh7 first red at merge 22222222 PR 372 T-0331 by C*") "the red unit names its merge, PR, task and lane"
Check ($rep -like "*guards: RED*" -and $rep -like "*still red: test/test-old.ps1|ps51*") "the guards and the still-red units are in it"
Check ($rep -like "*INCOMPLETE: the night ran out*") "an incomplete night says so"
Check ($rep -like "*1 newly red across 2 repos*") "the headline counts newly red"

Write-Host ""
Write-Host "--- the tool, with -Plan: a throwaway repository, nothing run ---" -ForegroundColor Cyan
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-nightly-test-" + [guid]::NewGuid().ToString("N"))
$oldHome = $env:HORDE_HOME
try {
    [void][System.IO.Directory]::CreateDirectory($work)
    $origin = Join-Path $work "origin"
    $g = @("-c", "user.name=t", "-c", "user.email=t@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.autocrlf=false")
    function Git { param([string]$Dir, [string[]]$More) $o = & git.exe @g -C $Dir @More; if ($LASTEXITCODE -ne 0) { throw ("git " + ($More -join " ") + " failed") }; return @($o) }
    [void][System.IO.Directory]::CreateDirectory($origin)
    [void](Git $origin @("init", "-q", "-b", "main"))
    [System.IO.File]::WriteAllText((Join-Path $origin "f.txt"), "0")
    [void](Git $origin @("add", "f.txt")); [void](Git $origin @("commit", "-q", "-m", "base"))
    $base = (Git $origin @("rev-parse", "HEAD"))[0]
    foreach ($n in 1..3) {
        [void](Git $origin @("checkout", "-q", "-b", ("side" + $n)))
        [System.IO.File]::WriteAllText((Join-Path $origin "f.txt"), "" + $n)
        [void](Git $origin @("commit", "-q", "-a", "-m", ("work " + $n)))
        [void](Git $origin @("checkout", "-q", "main"))
        [void](Git $origin @("merge", "-q", "--no-ff", "-m", ("Merge pull request #" + (100 + $n) + " from T/side" + $n), ("side" + $n)))
    }
    $mergeShas = @(Git $origin @("log", "--first-parent", "--reverse", "--format=%H", ($base + "..main")))
    Check ($mergeShas.Count -eq 3) "the fixture has three merges after the base"
    $wr = Join-Path $work "wr"
    $tree = Join-Path (Join-Path $wr "Fix__Repo") "tree"
    [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $tree))
    & git.exe clone -q $origin $tree; if ($LASTEXITCODE -ne 0) { throw "clone failed" }
    # Last night's tip is the base: the range is exactly the three merges.
    [System.IO.File]::WriteAllText((Join-Path (Join-Path $wr "Fix__Repo") "state.json"), ('{ "lastTip": "' + $base + '", "units": {} }'))
    $h = Join-Path $work "home"
    [void][System.IO.Directory]::CreateDirectory((Join-Path $h "merge"))
    [System.IO.File]::WriteAllText((Join-Path $h "merge\guards-owed.jsonl"), ('{"repo":"Fix/Repo","pr":102,"task":"T-7","by":"lane-x","mergeSha":"' + $mergeShas[1] + '"}' + "`n"))
    $env:HORDE_HOME = $h
    $exe = (Get-Process -Id $PID).Path
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -Plan -WorkRoot $wr -Repos "Fix/Repo:pytest:main")
    $code = $LASTEXITCODE
    $text = $o -join "`n"
    Check ($code -eq 0) ("-Plan exits 0 (" + $code + ")")
    Check ($text -like "*PLAN Fix/Repo (pytest)*3 merges*") ("it lists the three merges since last night (" + (($o | Where-Object { $_ -like "PLAN*" }) -join "") + ")")
    Check ($text -like "*PR 102 T-7 by lane-x*[[]owed[]]*") "the owed entry labelled the second merge"
    Check ($text -like "*Merge pull request #101*" -and $text -like "*Merge pull request #103*") "the other two come from git alone"
    Check ($text -like "*units: 2*") "a pytest repo has two units: the whole run and flake8"
    Check (-not (Test-Path -LiteralPath (Join-Path $wr "runs"))) "and -Plan ran nothing: no run folder"
} finally {
    $env:HORDE_HOME = $oldHome
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "the nightly net keeps to its window, lists the day's merges, finds newly red units, bisects to one merge, and reports in text a tell can carry"
