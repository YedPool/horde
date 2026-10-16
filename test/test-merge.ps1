# DOES `horde merge` MERGE ONLY WHAT IS GREEN, ONLY WITH A MERGE COMMIT, AND NEVER PRETEND AFTER IT?
#
# cli/Merge.ps1 and cli/commands/merge.ps1. NOTHING HERE REACHES GITHUB, THE FLEET'S LEDGER OR ANYONE'S
# MAIL. gh and the task ledger are stand-ins (test/fixtures/merge/StandIns.ps1) answering from state files
# this suite writes; the "repository" is a bare git repository in temp whose main the stand-in gh merges
# into with a real merge commit. git itself is real, so the scratch checkout, the merge-tree and the
# moved-base check are the shipped code's own. The two guards in that repository are stand-ins that go
# red on cue (a word in guard.txt, or two flag files that only meet in a merge result).
#
# PART 1 calls Invoke-HordeMerge in this process with a table of tools: stand-in gh and ledger, a teller
# and a mailer that only record, guards run as scripts in the scratch checkout. PART 2 runs the real
# `horde merge` as its own process, under Windows PowerShell and PowerShell 7, with a Horde home in temp
# whose settings point gh and the ledger at the stand-ins - where the real teller refuses before it looks
# for anyone (a test's home tells nobody) and the analyst's mail lands in that temp home.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
. (Join-Path $root "test\lib\Cli.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "cli\Merge.ps1")
. (Join-Path $root "test\fixtures\merge\StandIns.ps1")

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-merge-" + [guid]::NewGuid().ToString("N").Substring(0, 10))
[void][System.IO.Directory]::CreateDirectory($work)
$utf8 = New-Object System.Text.UTF8Encoding($false)

function G {
    # git in a folder of this suite's: G <folder> <git words>; its output, or a throw. A plain function,
    # so a word such as -q reaches git and is not read as a parameter of this one.
    $dir = "" + $args[0]
    $words = @($args | Select-Object -Skip 1)
    $o = & git -C $dir @words
    if ($LASTEXITCODE -ne 0) { throw ("git " + ($words -join " ") + " failed in " + $dir) }
    return ((@($o) -join "`n").Trim())
}

# THE TEMPLATE REPOSITORY, built once and copied for each case. main: C0, then C1 (adds main-flag.txt and
# changes conflict.txt). Pull requests, as refs/pull/<n>/head:
#   1 from C1, adds one.txt                     contains main; green
#   2 from C0, adds two.txt                     does NOT contain main; its merge is green
#   3 from C0, adds pr-flag.txt                 green alone; its merge with main is RED (both flags)
#   4 from C1, guard.txt specs-red              test-mutation-specs red
#   5 from C1, guard.txt specs-no-banner        test-mutation-specs exits 0 with no banner: NOT RUN
#   6 from C0, changes conflict.txt             conflicts with main
#   7 from C1, guard.txt hostnames-red          test-host-names red
$hostGuard = @'
$flag = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "..\guard.txt"))
$both = (Test-Path (Join-Path $PSScriptRoot "..\main-flag.txt")) -and (Test-Path (Join-Path $PSScriptRoot "..\pr-flag.txt"))
if ($flag -match "hostnames-red" -or $both) { Write-Output "  [FAIL] stand-in: a file names a port it may not"; Write-Output ""; Write-Output "==== 1 FAILURE(S) ===="; exit 1 }
Write-Output "  [PASS] stand-in host names"
Write-Output "==== stand-in host names green ===="
exit 0
'@
$specGuard = @'
$flag = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "..\guard.txt"))
if ($flag -match "specs-red") { Write-Output "  [FAIL] stand-in: a mutant has no place to apply"; Write-Output ""; Write-Output "==== 1 FAILURE(S) ===="; exit 1 }
if ($flag -match "specs-no-banner") { Write-Output "  [PASS] stand-in specs, cut short"; exit 0 }
Write-Output "  [PASS] stand-in specs"
Write-Output "==== stand-in specs green ===="
exit 0
'@
$template = Join-Path $work "template.git"
$seed = Join-Path $work "seed"
[void][System.IO.Directory]::CreateDirectory((Join-Path $seed "test"))
$null = G $seed init -q
$null = G $seed config user.name suite
$null = G $seed config user.email suite@localhost
$null = G $seed config core.autocrlf false
[System.IO.File]::WriteAllText((Join-Path $seed "test\test-host-names.ps1"), $hostGuard, $utf8)
[System.IO.File]::WriteAllText((Join-Path $seed "test\test-mutation-specs.ps1"), $specGuard, $utf8)
[System.IO.File]::WriteAllText((Join-Path $seed "guard.txt"), "green", $utf8)
[System.IO.File]::WriteAllText((Join-Path $seed "conflict.txt"), "a", $utf8)
$null = G $seed add -A
$null = G $seed commit -q -m C0
$c0 = G $seed rev-parse HEAD
function New-SeedCommit {
    param([string]$From, [hashtable]$Files, [string]$Message)
    $null = G $seed checkout -q --detach $From
    foreach ($k in $Files.Keys) { [System.IO.File]::WriteAllText((Join-Path $seed $k), $Files[$k], $utf8) }
    $null = G $seed add -A
    $null = G $seed commit -q -m $Message
    return (G $seed rev-parse HEAD)
}
$c1 = New-SeedCommit -From $c0 -Files @{ "main-flag.txt" = "main"; "conflict.txt" = "b" } -Message C1
$heads = [ordered]@{
    "1" = (New-SeedCommit -From $c1 -Files @{ "one.txt" = "1" } -Message "pr 1")
    "2" = (New-SeedCommit -From $c0 -Files @{ "two.txt" = "2" } -Message "pr 2")
    "3" = (New-SeedCommit -From $c0 -Files @{ "pr-flag.txt" = "pr" } -Message "pr 3")
    "4" = (New-SeedCommit -From $c1 -Files @{ "guard.txt" = "specs-red" } -Message "pr 4")
    "5" = (New-SeedCommit -From $c1 -Files @{ "guard.txt" = "specs-no-banner" } -Message "pr 5")
    "6" = (New-SeedCommit -From $c0 -Files @{ "conflict.txt" = "c" } -Message "pr 6")
    "7" = (New-SeedCommit -From $c1 -Files @{ "guard.txt" = "hostnames-red" } -Message "pr 7")
}
$null = G $work init --bare -q $template
$push = @(($c1 + ":refs/heads/main")) + @($heads.Keys | ForEach-Object { $heads[$_] + ":refs/pull/" + $_ + "/head" })
$null = G $seed push -q $template @push
$null = G $template symbolic-ref HEAD refs/heads/main

$script:caseNo = 0
function New-Case {
    # A fresh copy of the template, a gh state with every PR open and green, and a ledger that knows
    # T-0247. -Pr overrides fields of one pull request: @{ "1" = @{ state = "CLOSED" } }.
    param([hashtable]$Pr = @{}, [switch]$LedgerFails, [string[]]$Tasks = @("T-0247"))
    $script:caseNo++
    $dir = Join-Path $work ("case" + $script:caseNo)
    [void][System.IO.Directory]::CreateDirectory($dir)
    $origin = Join-Path $dir "origin.git"
    Copy-Item -LiteralPath $template -Destination $origin -Recurse
    $prs = [ordered]@{}
    foreach ($n in $heads.Keys) {
        $p = [ordered]@{ state = "OPEN"; isDraft = $false; mergeable = "MERGEABLE"; reviewDecision = ""; title = ("PR " + $n); mergeCommit = $null; mergeableQueue = @(); headRefOid = ""; failMerge = $false }
        if ($Pr.ContainsKey($n)) { foreach ($k in $Pr[$n].Keys) { $p[$k] = $Pr[$n][$k] } }
        $prs[$n] = $p
    }
    $gh = Join-Path $dir "gh-state.json"
    Write-MergeStandInState -Path $gh -State ([ordered]@{ origin = $origin; prs = $prs; calls = @() })
    $ledger = Join-Path $dir "ledger-state.json"
    Write-MergeStandInState -Path $ledger -State ([ordered]@{ tasks = $Tasks; failMerged = [bool]$LedgerFails; calls = @() })
    return [pscustomobject]@{ dir = $dir; origin = $origin; gh = $gh; ledger = $ledger; work = (Join-Path $dir "work") }
}

function Get-GhCalls { param($Case) return @((Read-MergeStandInState -Path $Case.gh).calls) }
function Get-LedgerCalls { param($Case) return @((Read-MergeStandInState -Path $Case.ledger).calls) }
function Get-Main { param($Case) return (G $Case.origin rev-parse refs/heads/main) }
function Test-MergeCall { param($Case) return [bool](@(Get-GhCalls $Case | Where-Object { $_ -clike "pr merge *" }).Count -gt 0) }

# PART 1'S TOOLS. Everything a tool sees and does is kept in $script: tables the checks read.
function New-SuiteTools {
    param($Case, [switch]$TellFails, [switch]$MailFails, [scriptblock]$BeforeGuard = $null)
    $script:said = New-Object System.Collections.ArrayList
    $script:told = New-Object System.Collections.ArrayList
    $script:mailed = New-Object System.Collections.ArrayList
    $script:waited = New-Object System.Collections.ArrayList
    $script:guardRuns = New-Object System.Collections.ArrayList
    $script:toolCase = $Case
    $script:tellFails = [bool]$TellFails
    $script:mailFails = [bool]$MailFails
    $script:beforeGuard = $BeforeGuard
    $real = New-HordeMergeTools -Values ([pscustomobject]@{ gh = "gh"; git = "git"; guardShell = "powershell.exe"; ledgerProgram = "python"; ledgerScript = "C:\fleet\task.py"; workFolder = "" }) -Tell { } -Mail { }
    return @{
        Gh = { param([string[]]$Arguments) return (Invoke-MergeStandInGh -StatePath $script:toolCase.gh -Arguments $Arguments) }
        Git = $real["Git"]
        Guard = {
            param([string]$Checkout, [string]$Suite)
            if ($null -ne $script:beforeGuard) { & $script:beforeGuard }
            [void]$script:guardRuns.Add([pscustomobject]@{ suite = $Suite; commit = (G $Checkout rev-parse HEAD); originMain = (G $Checkout rev-parse refs/remotes/origin/main); parents = @((G $Checkout rev-list --parents -n 1 HEAD) -split " " | Select-Object -Skip 1); checkout = $Checkout })
            $o = & (Join-Path $Checkout $Suite)
            return [pscustomobject]@{ code = $LASTEXITCODE; out = (@($o) -join "`n"); err = "" }
        }
        Ledger = { param([string[]]$Arguments) return (Invoke-MergeStandInLedger -StatePath $script:toolCase.ledger -Arguments (@("C:\fleet\task.py") + @($Arguments))) }
        LedgerLine = $real["LedgerLine"]
        Tell = { param([string]$Body) [void]$script:told.Add($Body); if ($script:tellFails) { return [pscustomobject]@{ ok = $false; detail = "no session holds the role of warchief" } }; return [pscustomobject]@{ ok = $true; detail = "accepted" } }
        Mail = { param([string]$Text) [void]$script:mailed.Add($Text); if ($script:mailFails) { return [pscustomobject]@{ ok = $false; detail = "the mail folder is read-only" } }; return [pscustomobject]@{ ok = $true; detail = "left for the analyst" } }
        Wait = { param([int]$Seconds) [void]$script:waited.Add($Seconds) }
        Say = { param([string]$Line) [void]$script:said.Add($Line) }
    }
}

function Invoke-Case {
    # Invoke-HordeMerge on one case: the answer.
    param($Case, [string]$Pr = "YedPool/horde#1", [string]$Task = "T-0247", [string]$State = "done", [string]$By = "F", [string]$On = "", [string]$Reason = "", [switch]$TellFails, [switch]$MailFails, [scriptblock]$BeforeGuard = $null)
    $req = Test-HordeMergeRequest -Pr $Pr -Task $Task -State $State -By $By -On $On -Reason $Reason
    if (-not $req.ok) { throw ("the suite built a bad request: " + $req.why) }
    $tools = New-SuiteTools -Case $Case -TellFails:$TellFails -MailFails:$MailFails -BeforeGuard $BeforeGuard
    return (Invoke-HordeMerge -Request $req -Tools $tools -WorkFolder $Case.work)
}

function Said { param([string]$Like) return [bool](@($script:said | Where-Object { $_ -clike $Like }).Count -gt 0) }

Write-Host "== the request is checked before anything runs"
$ok = Test-HordeMergeRequest -Pr "YedPool/horde#305" -Task "T-0247" -State "done" -By "F"
Check ($ok.ok -eq $true -and $ok.owner -ceq "YedPool" -and $ok.repo -ceq "horde" -and $ok.number -eq 305) "a well-formed request is taken apart into owner, repo and number"
foreach ($bad in @(
    @{ Pr = "YedPool/horde"; Like = "*not a pull request*" }, @{ Pr = "YedPool/horde#0"; Like = "*not a pull request*" },
    @{ Pr = "horde#3"; Like = "*not a pull request*" }, @{ Pr = "YedPool/..#3"; Like = "*not a pull request*" },
    @{ Pr = "YedPool/horde#3 "; Like = "*not a pull request*" }, @{ Task = "T-1"; Like = "*not a task id*" },
    @{ Task = "t-0247"; Like = "*not a task id*" }, @{ Task = "T-0247`n"; Like = "*not a task id*" },
    @{ State = "verified"; Like = "*not a state*" }, @{ State = "Done"; Like = "*not a state*" },
    @{ By = "f"; Like = "*not a lane*" }, @{ By = "FAB"; Like = "*not a lane*" }, @{ By = "C0"; Like = "*not a lane*" },
    @{ State = "waiting"; Like = "*needs -On*" }, @{ State = "progress"; Like = "*needs -Reason*" },
    @{ State = "waiting"; On = "Bob"; Like = "*not who a task waits on*" }, @{ Reason = ("x" * 301); Like = "*reason is one line*" },
    @{ Reason = "two`nlines"; Like = "*reason is one line*" })) {
    $a = @{ Pr = "YedPool/horde#3"; Task = "T-0247"; State = "done"; By = "F"; On = ""; Reason = "" }
    foreach ($k in @($bad.Keys)) { if ($k -cne "Like") { $a[$k] = $bad[$k] } }
    $r = Test-HordeMergeRequest @a
    Check ($r.ok -eq $false -and $r.why -like $bad.Like) ("refused: " + (($bad.Keys | Where-Object { $_ -cne "Like" } | ForEach-Object { $_ + "=" + $bad[$_] }) -join " ") + " (" + $r.why + ")")
}
Check ((Test-HordeMergeRequest -Pr "o/r#1" -Task "T-0001" -State "waiting" -By "C1" -On "lane:K").ok -eq $true) "waiting on a lane, by a numbered lane, is taken"
Check ((Test-HordeMergeRequest -Pr "o/r#1" -Task "T-0001" -State "progress" -By "M" -Reason "the docs are left").ok -eq $true) "progress with what is left is taken"

Write-Host "== the pure parts"
$line = Format-HordeMergeLedgerLine -Program "python" -Script "C:\it's\task.py" -Arguments @("merged", "T-0247", "--pr", "YedPool/horde#9", "--reason", "it's left")
Check ($line -ceq "& 'python' 'C:\it''s\task.py' 'merged' 'T-0247' '--pr' 'YedPool/horde#9' '--reason' 'it''s left'") ("the hand-run ledger line quotes every word, a # and a quote included: " + $line)
$args3 = Get-HordeMergeLedgerArguments -Request (Test-HordeMergeRequest -Pr "o/r#1" -Task "T-0001" -State "waiting" -By "F" -On "founder")
Check (($args3 -join " ") -ceq "merged T-0001 --pr o/r#1 --by F --state waiting --on founder") "the ledger's merged event carries the task, the PR, the lane, the state and who it waits on"
$args4 = Get-HordeMergeLedgerArguments -Request (Test-HordeMergeRequest -Pr "o/r#1" -Task "T-0001" -State "progress" -By "F" -Reason "docs left")
Check (($args4 -join " ") -ceq "merged T-0001 --pr o/r#1 --by F --state progress --reason docs left" -and $args4.Count -eq 10) "progress carries its reason as one argument"
Check ((Read-HordeMergeGuardResult -Run ([pscustomobject]@{ code = 0; out = "  [PASS] x`n==== all good ===="; err = "" })).ok -eq $true) "exit 0 with a closing banner is green"
Check ((Read-HordeMergeGuardResult -Run ([pscustomobject]@{ code = 0; out = "  [PASS] x"; err = "" })).ok -eq $false) "exit 0 with no closing banner is NOT RUN, never green"
Check ((Read-HordeMergeGuardResult -Run ([pscustomobject]@{ code = 1; out = "==== all good ===="; err = "" })).ok -eq $false) "a banner with a non-zero exit is not green"
Check ((Read-HordeMergeGuardResult -Run ([pscustomobject]@{ code = 0; out = "==== 2 FAILURE(S) ===="; err = "" })).ok -eq $false) "a failures banner is not green, whatever the exit"
$red = Read-HordeMergeGuardResult -Run ([pscustomobject]@{ code = 1; out = ("noise`n" + ((1..50 | ForEach-Object { "  [FAIL] line " + $_ }) -join "`n") + "`n==== 50 FAILURE(S) ===="); err = "" })
Check (@($red.lines | Where-Object { $_ -clike "*[[]FAIL] line 1" }).Count -eq 1 -and @($red.lines | Where-Object { $_ -clike "*and 10 more*" }).Count -eq 1 -and @($red.lines | Where-Object { $_ -clike "*line 41" }).Count -eq 0) "a red guard's failing lines are printed, the first 40, the rest counted"
$noise = Read-HordeMergeGuardResult -Run ([pscustomobject]@{ code = 3; out = "it crashed here"; err = "" })
Check (@($noise.lines | Where-Object { $_ -ceq "it crashed here" }).Count -eq 1 -and $noise.lines[0] -clike "exit 3, and no closing banner*") "a crash with no failing line shows its last lines and that it did not finish"
$prog = Format-HordeMergeProgress -Request (Test-HordeMergeRequest -Pr "o/r#1" -Task "T-0001" -State "waiting" -By "F" -On "M") -Title ("caf" + [char]0xE9 + " " + ("x" * 120))
Check ($prog -clike "progress draft: F merged o/r#1 - caf? xxx*... (T-0001, now waiting on M)" -and $prog -cnotmatch '[^\x20-\x7E]') ("the progress draft is one ASCII line with the title cut: " + $prog)

Write-Host "== refused before GitHub: the task"
$c = New-Case -Tasks @("T-0001")
$r = Invoke-Case -Case $c
Check ($r.outcome -ceq "refused" -and $r.why -clike "*has no task T-0247*") ("a task the ledger does not have is refused: " + $r.why)
Check (@(Get-GhCalls $c).Count -eq 0) "and GitHub is not asked anything"
$c = New-Case
$tools = New-SuiteTools -Case $c
$tools["Ledger"] = { param([string[]]$Arguments) return [pscustomobject]@{ code = 2; out = ""; err = "python: can't open file 'task.py'" } }
$r = Invoke-HordeMerge -Request (Test-HordeMergeRequest -Pr "YedPool/horde#1" -Task "T-0247" -State "done" -By "F") -Tools $tools -WorkFolder $c.work
Check ($r.outcome -ceq "refused" -and $r.why -clike "*ledger could not be read*can't open file*" -and @(Get-GhCalls $c).Count -eq 0) ("a ledger that cannot be read refuses before GitHub: " + $r.why)

Write-Host "== refused: the pull request"
foreach ($case in @(
    @{ Pr = @{ state = "CLOSED" }; Like = "*is not open: GitHub says CLOSED*" },
    @{ Pr = @{ state = "MERGED" }; Like = "*is not open: GitHub says MERGED*" },
    @{ Pr = @{ isDraft = $true }; Like = "*is a draft*" },
    @{ Pr = @{ mergeable = "CONFLICTING" }; Like = "*not mergeable: it conflicts*" },
    @{ Pr = @{ mergeable = "UNKNOWN" }; Like = "*not mergeable yet*UNKNOWN after 4 asks*" },
    @{ Pr = @{ reviewDecision = "REVIEW_REQUIRED" }; Like = "*missing a review*REVIEW_REQUIRED*" },
    @{ Pr = @{ reviewDecision = "CHANGES_REQUESTED" }; Like = "*missing a review*CHANGES_REQUESTED*" },
    @{ Pr = @{ headRefOid = ("0" * 40) }; Like = "*PR head moved while it was read*" })) {
    $c = New-Case -Pr @{ "1" = $case.Pr }
    $r = Invoke-Case -Case $c
    Check ($r.outcome -ceq "refused" -and $r.why -clike $case.Like) ("refused, " + (($case.Pr.Keys | ForEach-Object { $_ + "=" + $case.Pr[$_] }) -join " ") + ": " + $r.why)
    Check (-not (Test-MergeCall $c) -and (Get-Main $c) -ceq $c1) "  and nothing was merged"
}
$c = New-Case -Pr @{ "1" = @{ mergeable = "UNKNOWN" } }
$null = Invoke-Case -Case $c
Check (@($script:waited).Count -eq 3 -and @(Get-GhCalls $c | Where-Object { $_ -clike "pr view 1 *" }).Count -eq 4) "an UNKNOWN mergeable is asked 4 times, with 3 waits between"
$r = Invoke-Case -Case (New-Case) -Pr "YedPool/horde#99"
Check ($r.outcome -ceq "refused" -and $r.why -clike "gh could not read YedPool/horde#99: GraphQL: Could not resolve*") ("a PR gh cannot read is refused with gh's words: " + $r.why)

Write-Host "== refused: the guards, on the tree that will exist after the merge"
foreach ($case in @(
    @{ N = "7"; Suite = "test\test-host-names.ps1"; Fail = "*[[]FAIL] stand-in: a file names a port*"; What = "test-host-names red" },
    @{ N = "4"; Suite = "test\test-mutation-specs.ps1"; Fail = "*[[]FAIL] stand-in: a mutant has no place*"; What = "test-mutation-specs red" },
    @{ N = "5"; Suite = "test\test-mutation-specs.ps1"; Fail = "*no closing banner*NOT RUN*"; What = "test-mutation-specs with no banner" })) {
    $c = New-Case
    $r = Invoke-Case -Case $c -Pr ("YedPool/horde#" + $case.N)
    Check ($r.outcome -ceq "refused" -and $r.why -clike ("the guard " + $case.Suite + " is red on *nothing was merged")) ($case.What + " is refused: " + $r.why)
    Check (Said $case.Fail) ("  and its failing line is printed")
    Check (-not (Test-MergeCall $c) -and (Get-Main $c) -ceq $c1) "  and nothing was merged"
}
$c = New-Case
$r = Invoke-Case -Case $c -Pr "YedPool/horde#3"
Check ($r.outcome -ceq "refused" -and $r.why -clike "the guard test\test-host-names.ps1 is red*") ("a head that is green alone but red merged with main is refused: " + $r.why)
Check ((Said "the PR head * does NOT contain main *: what is checked is their merge *") -and @($script:guardRuns).Count -eq 1 -and $script:guardRuns[0].commit -cne $heads["3"]) "  and it says the merge result, not the head, is what was checked"
Check (-not (Test-MergeCall $c)) "  and nothing was merged"
$c = New-Case
$r = Invoke-Case -Case $c -Pr "YedPool/horde#6"
Check ($r.outcome -ceq "refused" -and $r.why -clike "*does not merge cleanly with main*" -and -not (Test-MergeCall $c)) ("a head that conflicts with main is refused, whatever GitHub said: " + $r.why)

Write-Host "== merged: the head contains main"
$c = New-Case
$r = Invoke-Case -Case $c
$main = Get-Main $c
$parents = @((G $c.origin rev-list --parents -n 1 $main) -split " ")
Check ($r.outcome -ceq "merged" -and $r.mergeSha -ceq $main) ("a green PR is merged, and the sha said is main's new tip: " + $r.outcome + " " + $r.mergeSha)
Check ($parents.Count -eq 3 -and $parents[1] -ceq $c1 -and $parents[2] -ceq $heads["1"]) "main's new tip is a merge commit of main and the head, never a squash"
$mergeCalls = @(Get-GhCalls $c | Where-Object { $_ -clike "pr merge *" })
Check ($mergeCalls.Count -eq 1 -and $mergeCalls[0] -ceq ("pr merge 1 --repo YedPool/horde --merge --match-head-commit " + $heads["1"])) ("gh is asked for --merge with the checked head pinned: " + ($mergeCalls -join " | "))
Check (@($script:guardRuns).Count -eq 2 -and $script:guardRuns[0].suite -ceq "test\test-host-names.ps1" -and $script:guardRuns[1].suite -ceq "test\test-mutation-specs.ps1") "both guards ran"
Check ($script:guardRuns[0].commit -ceq $heads["1"] -and $script:guardRuns[0].originMain -ceq $c1) "they ran on the head, in a checkout whose origin/main is main"
Check ((Said "the PR head * already contains main *: the head is what is checked")) "it says the head already contains main"
Check (-not [System.IO.Directory]::Exists($script:guardRuns[0].checkout) -and @([System.IO.Directory]::GetDirectories((Join-Path $c.work "runs"))).Count -eq 0) "the scratch checkout is removed afterwards"
$ledgerCalls = @(Get-LedgerCalls $c)
Check ($ledgerCalls.Count -eq 2 -and $ledgerCalls[0] -ceq "show T-0247" -and $ledgerCalls[1] -ceq "merged T-0247 --pr YedPool/horde#1 --by F --state done") ("the ledger is read first and its merged event written after: " + ($ledgerCalls -join " | "))
Check (@($script:told).Count -eq 1 -and $script:told[0] -clike ("HORDE MERGE: F merged YedPool/horde#1 as " + $main + ".*Task T-0247 is now done.*Guards green on " + $c1.Substring(0, 8) + " + " + $heads["1"].Substring(0, 8) + ".")) ("the warchief is told the PR, the merge sha, the task and its state: " + (@($script:told) -join " "))
Check ($script:told[0] -cnotlike "*PR 1*") "and nothing the PR's author wrote (its title) is in the message"
Check (@($script:mailed).Count -eq 1 -and $script:mailed[0] -ceq $script:told[0]) "the analyst is mailed the same message"
Check ((Said "progress draft: F merged YedPool/horde#1 - PR 1 (T-0247, now done)") -and (Said ("MERGED YedPool/horde#1 as " + $main))) "the merge and a one-line progress draft are printed"

Write-Host "== merged: the head does not contain main"
$c = New-Case -Pr @{ "2" = @{ mergeableQueue = @("UNKNOWN") } }
$r = Invoke-Case -Case $c -Pr "YedPool/horde#2" -State "waiting" -On "lane:K"
Check ($r.outcome -ceq "merged" -and (Get-Main $c) -ceq $r.mergeSha) ("a PR behind main whose merge is green is merged: " + $r.outcome)
Check ($script:guardRuns[0].commit -cne $heads["2"] -and (($script:guardRuns[0].parents) -join " ") -ceq ($c1 + " " + $heads["2"])) "the guards ran on the merge of main and the head, not on the head"
Check (@(Get-LedgerCalls $c)[1] -ceq "merged T-0247 --pr YedPool/horde#2 --by F --state waiting --on lane:K") "a waiting state reaches the ledger with who it waits on"
Check ($script:told[0] -clike "*Task T-0247 is now waiting, waiting on lane:K.*(checked as their merge, *") "the warchief is told it waits, and that the merge result was checked"
Check (@($script:waited).Count -eq 1) "an UNKNOWN that turns MERGEABLE is waited on once and goes on"

Write-Host "== main moves while the guards run"
$script:moves = 0
$moveGreen = {
    if ($script:moves -ge 1) { return }
    $script:moves++
    $null = G $seed checkout -q --detach $c1
    [System.IO.File]::WriteAllText((Join-Path $seed "moved.txt"), "moved", $utf8)
    $null = G $seed add -A
    $null = G $seed commit -q -m moved
    $null = G $seed push -q -f $script:toolCase.origin "HEAD:refs/heads/main"
}
$c = New-Case
$r = Invoke-Case -Case $c -BeforeGuard $moveGreen
$moved = G $seed rev-parse HEAD
Check ($r.outcome -ceq "merged" -and @($script:guardRuns).Count -eq 4) ("main moved once: the guards ran again before the merge (" + @($script:guardRuns).Count + " runs)")
Check ((Said "main moved from * to * while the guards ran: checking the new combination before merging")) "it says main moved and the new combination is checked"
Check ($script:guardRuns[2].originMain -ceq $moved -and $script:guardRuns[2].commit -cne $heads["1"] -and @($script:guardRuns[2].parents)[0] -ceq $moved) "the second round checked the merge of the moved main and the head"
Check ((G $c.origin rev-parse ((Get-Main $c) + "^1")) -ceq $moved) "and the merge went onto the moved main"

$script:moves = 0
$moveRed = {
    if ($script:moves -ge 1) { return }
    $script:moves++
    $null = G $seed checkout -q --detach $c1
    [System.IO.File]::WriteAllText((Join-Path $seed "guard.txt"), "hostnames-red", $utf8)
    $null = G $seed add -A
    $null = G $seed commit -q -m "main goes red"
    $null = G $seed push -q -f $script:toolCase.origin "HEAD:refs/heads/main"
}
$c = New-Case
$r = Invoke-Case -Case $c -BeforeGuard $moveRed
Check ($r.outcome -ceq "refused" -and $r.why -clike "the guard test\test-host-names.ps1 is red*" -and -not (Test-MergeCall $c)) ("main moved to a red combination: refused, nothing merged: " + $r.why)

$script:moves = 0
$moveAlways = {
    $script:moves++
    $null = G $seed checkout -q --detach $c1
    [System.IO.File]::WriteAllText((Join-Path $seed "moved.txt"), ("moved " + $script:moves), $utf8)
    $null = G $seed add -A
    $null = G $seed commit -q -m ("moved " + $script:moves)
    $null = G $seed push -q -f $script:toolCase.origin "HEAD:refs/heads/main"
}
$c = New-Case
$r = Invoke-Case -Case $c -BeforeGuard $moveAlways
Check ($r.outcome -ceq "refused" -and $r.why -clike "main moved under the guards 3 times in a row*" -and -not (Test-MergeCall $c)) ("main moving every round is refused after 3: " + $r.why)

Write-Host "== after the merge: never pretend"
$c = New-Case -LedgerFails
$r = Invoke-Case -Case $c -State "progress" -Reason "the docs are left"
Check ($r.outcome -ceq "merged-unfinished" -and (Get-Main $c) -ceq $r.mergeSha -and $r.why -clike "*the ledger event was not written*") ("a ledger failure after the merge says the merge happened and the ledger did not: " + $r.why)
Check ((Said "THE MERGE HAPPENED, BUT THE LEDGER WAS NOT WRITTEN: stand-in ledger: the ledger file is locked")) "it says so loudly, with the ledger's words"
Check ((Said "run this by hand: & 'python' 'C:\fleet\task.py' 'merged' 'T-0247' '--pr' 'YedPool/horde#1' '--by' 'F' '--state' 'progress' '--reason' 'the docs are left'")) "and prints the exact command to run"
Check (@($script:told).Count -eq 1 -and @($script:mailed).Count -eq 1) "the warchief and the analyst are still told"

$c = New-Case
$r = Invoke-Case -Case $c -TellFails
Check ($r.outcome -ceq "merged-unfinished" -and $r.why -clike "*the warchief was not told*" -and (Said "COULD NOT TELL THE WARCHIEF: no session holds the role of warchief")) ("the warchief not told: merged, said loudly: " + $r.why)
Check ((Said "    HORDE MERGE: F merged YedPool/horde#1 as *") -and @(Get-LedgerCalls $c).Count -eq 2) "the message is printed for a person to send, and the ledger was still written"
$c = New-Case
$r = Invoke-Case -Case $c -MailFails
Check ($r.outcome -ceq "merged-unfinished" -and $r.why -clike "*analyst was not mailed*" -and (Said "COULD NOT MAIL THE ANALYST: the mail folder is read-only")) ("the analyst not mailed: merged, said loudly: " + $r.why)

$c = New-Case -Pr @{ "1" = @{ failMerge = $true } }
$r = Invoke-Case -Case $c
Check ($r.outcome -ceq "refused" -and $r.why -clike "gh did not merge YedPool/horde#1: stand-in gh: the merge was refused" -and @(Get-LedgerCalls $c).Count -eq 1 -and @($script:told).Count -eq 0) ("gh refusing the merge: refused, no ledger event, nobody told: " + $r.why)

# PART 2: the real command, as its own process.
function New-CliCase {
    # A case, plus a Horde home in temp whose merge settings point gh and the ledger at the stand-ins.
    param([hashtable]$Pr = @{}, [switch]$NoLedgerScript)
    $c = New-Case -Pr $Pr
    $fixture = Join-Path $root "test\fixtures\merge\StandIns.ps1"
    $ghScript = Join-Path $c.dir "gh.ps1"
    $ledgerScript = Join-Path $c.dir "ledger.ps1"
    $tail = '; [Console]::Out.Write($r.out); [Console]::Error.Write($r.err); exit $r.code'
    [System.IO.File]::WriteAllText($ghScript, (". '" + $fixture + "'; `$r = Invoke-MergeStandInGh -StatePath (Join-Path `$PSScriptRoot 'gh-state.json') -Arguments `$args" + $tail), $utf8)
    [System.IO.File]::WriteAllText($ledgerScript, (". '" + $fixture + "'; `$r = Invoke-MergeStandInLedger -StatePath (Join-Path `$PSScriptRoot 'ledger-state.json') -Arguments `$args" + $tail), $utf8)
    $taskPy = Join-Path $c.dir "task.py"
    [System.IO.File]::WriteAllText($taskPy, "raise SystemExit('never run: the stand-in ledger is')", $utf8)
    $hordeHome = Join-Path $c.dir "home"
    [void][System.IO.Directory]::CreateDirectory((Join-Path $hordeHome "settings"))
    $values = [ordered]@{ gh = $ghScript; ledgerProgram = $ledgerScript; workFolder = $c.work }
    if (-not $NoLedgerScript) { $values["ledgerScript"] = $taskPy }
    [System.IO.File]::WriteAllText((Join-Path $hordeHome "settings\merge.json"), (@{ schemaVersion = 1; settings = $values } | ConvertTo-Json -Depth 5), $utf8)
    Add-Member -InputObject $c -NotePropertyName home -NotePropertyValue $hordeHome
    return $c
}

foreach ($shell in @("powershell.exe", "pwsh.exe")) {
    if ($null -eq (Get-Command $shell -ErrorAction SilentlyContinue)) { Check $false ("the shell " + $shell + " is on this machine, to run horde merge under it"); continue }
    Write-Host ("== the real command, under " + $shell)
    $c = New-CliCase
    # THE SUITE NEVER REACHES THE REAL ONES: every program the settings name is this case's own.
    $set = Read-MergeStandInState -Path (Join-Path $c.home "settings\merge.json")
    Check ("" + $set.settings.gh -clike ($c.dir + "*") -and "" + $set.settings.ledgerProgram -clike ($c.dir + "*") -and $c.home -clike ([System.IO.Path]::GetTempPath() + "*")) "CONTROL: gh, the ledger and the Horde home are this case's stand-ins, in temp"
    $env1 = @{ HORDE_HOME = $c.home }
    $run = Invoke-HordeCliProcess -Root $root -Shell $shell -HordeArgs @("merge", "YedPool/horde#1", "-Task", "T-0247", "-State", "done", "-By", "F") -Env $env1
    $main = Get-Main $c
    Check ($run.code -eq 1 -and $run.out -clike ("*MERGED YedPool/horde#1 as " + $main + "*") -and $main -cne $c1) ("the happy path merges and says so (" + $run.code + ")")
    Check ($run.out -clike "*test\test-host-names.ps1 is green*test\test-mutation-specs.ps1 is green*") "  the guards ran through the real guard runner and were read green"
    Check (@(Get-LedgerCalls $c)[-1] -ceq "merged T-0247 --pr YedPool/horde#1 --by F --state done") "  the ledger event was written through the settings' program"
    Check ($run.out -clike "*COULD NOT TELL THE WARCHIEF: this Horde home is under the temp folder, so it is a test's: nobody is told*" -and $run.out -clike "*MERGED, NOT FINISHED:*the warchief was not told*") "  a test's home tells the warchief nothing, and the command exits 1 saying so rather than pretend"
    $mailDir = Join-Path $c.home "analyst\mail"
    $mails = @(if ([System.IO.Directory]::Exists($mailDir)) { [System.IO.Directory]::GetFiles($mailDir, "*.txt") })
    Check ($mails.Count -eq 1 -and [System.IO.File]::ReadAllText($mails[0]) -clike ("HORDE MERGE: F merged YedPool/horde#1 as " + $main + "*")) "  the analyst's mail is left in the (test) home's analyst folder, as horde analyst mail leaves one"
    Check ($run.out -clike "*progress draft: F merged YedPool/horde#1 - PR 1 (T-0247, now done)*") "  the progress draft is printed"

    $run = Invoke-HordeCliProcess -Root $root -Shell $shell -HordeArgs @("merge", "YedPool/horde#1", "-Task", "T-12", "-State", "done", "-By", "F") -Env $env1
    Check ($run.code -eq 2 -and $run.out -clike "*'T-12' is not a task id*usage: horde merge*") "a malformed task id is a usage error, exit 2"
    if ($shell -ceq "pwsh.exe") { continue }

    $c = New-CliCase -Pr @{ "1" = @{ state = "CLOSED" } }
    $run = Invoke-HordeCliProcess -Root $root -Shell $shell -HordeArgs @("merge", "YedPool/horde#1", "-Task", "T-0247", "-State", "done", "-By", "F") -Env @{ HORDE_HOME = $c.home }
    Check ($run.code -eq 1 -and $run.out -clike "*refused, nothing merged: YedPool/horde#1 is not open: GitHub says CLOSED*" -and -not (Test-MergeCall $c)) "a closed PR: exit 1, refused, no merge asked"
    $c = New-CliCase
    $run = Invoke-HordeCliProcess -Root $root -Shell $shell -HordeArgs @("merge", "YedPool/horde#7", "-Task", "T-0247", "-State", "done", "-By", "F") -Env @{ HORDE_HOME = $c.home }
    Check ($run.code -eq 1 -and $run.out -clike "*[[]FAIL] stand-in: a file names a port*refused, nothing merged: the guard test\test-host-names.ps1 is red*" -and -not (Test-MergeCall $c)) "a red guard through the real runner: exit 1, its failing line printed, no merge asked"
    $c = New-CliCase -NoLedgerScript
    $run = Invoke-HordeCliProcess -Root $root -Shell $shell -HordeArgs @("merge", "YedPool/horde#1", "-Task", "T-0247", "-State", "done", "-By", "F") -Env @{ HORDE_HOME = $c.home }
    Check ($run.code -eq 1 -and $run.out -clike "*name no ledgerScript*nothing was merged*" -and @(Get-GhCalls $c).Count -eq 0) "no ledger script in the settings: exit 1 before GitHub is asked anything"
    $run = Invoke-HordeCliProcess -Root $root -Shell $shell -HordeArgs @("merge", "YedPool/horde#1", "-Task", "T-0247", "-State", "waiting", "-By", "F") -Env @{ HORDE_HOME = $c.home }
    Check ($run.code -eq 2 -and $run.out -clike "*-State waiting needs -On*") "waiting without -On is a usage error, exit 2"
    $run = Invoke-HordeCliProcess -Root $root -Shell $shell -HordeArgs @("merge", "YedPool/horde#1", "-Task", "T-0247", "-State", "done") -Env @{ HORDE_HOME = $c.home }
    Check ($run.code -eq 2 -and $run.out -clike "*merge needs -By*") "no -By is a usage error that names it, exit 2"
}

try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop } catch { Write-Host ("  (the suite's temp folder stays: " + $work + ")") }
Complete-HordeSuite -Success "horde merge merges only green merge results, with a merge commit, and never pretends after it"
