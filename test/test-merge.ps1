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
#   8 from C1, deletes test-mutation-specs.ps1  a guard missing from the tree
#   9 from C1, adds test-added.ps1 to guards.txt  a guard the PR adds; it is red
#  10 from C1, drops test-mutation-specs from guards.txt, guard.txt specs-red  main's list still runs it
#  11 from C1, guards.txt holds a line that is no guard  an unusable list
#  12 from C1, deletes guards.txt                the base's list is used
#  13 from C1, guard.txt red-in-7                test-host-names red in PowerShell 7 only
$hostGuard = @'
$flag = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "..\guard.txt"))
$both = (Test-Path (Join-Path $PSScriptRoot "..\main-flag.txt")) -and (Test-Path (Join-Path $PSScriptRoot "..\pr-flag.txt"))
if ($flag -match "hostnames-red" -or $both -or ($flag -match "red-in-7" -and $env:HORDE_MERGE_STUB_SHELL -eq "7") -or ($flag -match "red-in-51" -and $env:HORDE_MERGE_STUB_SHELL -eq "5.1")) { Write-Output "  [FAIL] stand-in: a file names a port it may not"; Write-Output ""; Write-Output "==== 1 FAILURE(S) ===="; exit 1 }
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
$guardsText = "# stand-in guard list`ntest/test-host-names.ps1`ntest/test-mutation-specs.ps1`n"
[System.IO.File]::WriteAllText((Join-Path $seed "test\guards.txt"), $guardsText, $utf8)
$addedGuard = "Write-Output '  [FAIL] stand-in: the added guard is red'; Write-Output ''; Write-Output '==== 1 FAILURE(S) ===='; exit 1`n"
[System.IO.File]::WriteAllText((Join-Path $seed "conflict.txt"), "a", $utf8)
$null = G $seed add -A
$null = G $seed commit -q -m C0
$c0 = G $seed rev-parse HEAD
function New-SeedCommit {
    param([string]$From, [hashtable]$Files, [string]$Message)
    $null = G $seed checkout -q --detach $From
    # A value of $null deletes the file.
    foreach ($k in $Files.Keys) { if ($null -eq $Files[$k]) { [System.IO.File]::Delete((Join-Path $seed $k)) } else { [System.IO.File]::WriteAllText((Join-Path $seed $k), $Files[$k], $utf8) } }
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
    "8" = (New-SeedCommit -From $c1 -Files @{ "test\test-mutation-specs.ps1" = $null } -Message "pr 8")
    "9" = (New-SeedCommit -From $c1 -Files @{ "test\guards.txt" = ($guardsText + "test/test-added.ps1`n"); "test\test-added.ps1" = $addedGuard } -Message "pr 9")
    "10" = (New-SeedCommit -From $c1 -Files @{ "test\guards.txt" = "test/test-host-names.ps1`n"; "guard.txt" = "specs-red" } -Message "pr 10")
    "11" = (New-SeedCommit -From $c1 -Files @{ "test\guards.txt" = ($guardsText + "rm -rf /`n") } -Message "pr 11")
    "13" = (New-SeedCommit -From $c1 -Files @{ "guard.txt" = "red-in-7" } -Message "pr 13")
    "12" = (New-SeedCommit -From $c1 -Files @{ "test\guards.txt" = $null } -Message "pr 12")
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
        $p = [ordered]@{ state = "OPEN"; isDraft = $false; mergeable = "MERGEABLE"; reviewDecision = ""; title = ("PR " + $n); mergeCommit = $null; mergeableQueue = @(); headRefOid = ""; failMerge = $false; moveMainFirst = $false; hideMerged = $false }
        if ($Pr.ContainsKey($n)) { foreach ($k in $Pr[$n].Keys) { $p[$k] = $Pr[$n][$k] } }
        $prs[$n] = $p
    }
    $gh = Join-Path $dir "gh-state.json"
    Write-MergeStandInState -Path $gh -State ([ordered]@{ origin = $origin; prs = $prs; calls = @() })
    $ledger = Join-Path $dir "ledger-state.json"
    Write-MergeStandInState -Path $ledger -State ([ordered]@{ tasks = $Tasks; failMerged = [bool]$LedgerFails; calls = @() })
    $caseWork = Join-Path $dir "work"
    [void][System.IO.Directory]::CreateDirectory($caseWork)
    return [pscustomobject]@{ dir = $dir; origin = $origin; gh = $gh; ledger = $ledger; work = $caseWork; owed = (Join-Path $dir "merge") }
}

function Get-GhCalls { param($Case) return @((Read-MergeStandInState -Path $Case.gh).calls) }
function Get-LedgerCalls { param($Case) return @((Read-MergeStandInState -Path $Case.ledger).calls) }
function Get-Main { param($Case) return (G $Case.origin rev-parse refs/heads/main) }
function Test-MergeCall { param($Case) return [bool](@(Get-GhCalls $Case | Where-Object { $_ -clike "pr merge *" }).Count -gt 0) }

# PART 1'S TOOLS. Everything a tool sees and does is kept in $script: tables the checks read.
function New-SuiteTools {
    param($Case, [switch]$TellFails, [switch]$MailFails, [scriptblock]$BeforeGuard = $null, [string]$GitFails = "", [switch]$OwedFails, [scriptblock]$GuardOverride = $null, [switch]$IntentFails)
    $script:gitFails = $GitFails
    $script:intentFails = [bool]$IntentFails
    $script:guardOverride = $GuardOverride
    $script:said = New-Object System.Collections.ArrayList
    $script:told = New-Object System.Collections.ArrayList
    $script:mailed = New-Object System.Collections.ArrayList
    $script:waited = New-Object System.Collections.ArrayList
    $script:guardRuns = New-Object System.Collections.ArrayList
    $script:toolCase = $Case
    $script:tellFails = [bool]$TellFails
    $script:mailFails = [bool]$MailFails
    $script:owedFails = [bool]$OwedFails
    $script:beforeGuard = $BeforeGuard
    $real = New-HordeMergeTools -Values ([pscustomobject]@{ gh = "gh"; git = "git"; guardShell = "powershell.exe"; ledgerProgram = "python"; ledgerScript = "C:\fleet\task.py"; workFolder = $Case.work }) -Tell { } -Mail { }
    $script:realGit = $real["Git"]
    return @{
        Gh = { param([string[]]$Arguments) return (Invoke-MergeStandInGh -StatePath $script:toolCase.gh -Arguments $Arguments) }
        # The real git, but a call naming -GitFails as one of its words fails as git would.
        Git = { param([string[]]$Arguments) if ($script:gitFails -ne "" -and @($Arguments) -ccontains $script:gitFails) { return [pscustomobject]@{ code = 128; out = ""; err = ("fatal: stand-in failure of " + $script:gitFails) } }; return (& $script:realGit $Arguments) }
        Guard = {
            param([string]$Checkout, [string]$Suite, [string]$Shell)
            if ($null -ne $script:beforeGuard) { & $script:beforeGuard }
            [void]$script:guardRuns.Add([pscustomobject]@{ suite = $Suite; shell = $Shell; commit = (G $Checkout rev-parse HEAD); originMain = (G $Checkout rev-parse refs/remotes/origin/main); parents = @((G $Checkout rev-list --parents -n 1 HEAD) -split " " | Select-Object -Skip 1); checkout = $Checkout })
            # A GuardOverride answers in place of the stand-in guard when it returns a run (code, out, err).
            if ($null -ne $script:guardOverride) { $ov = & $script:guardOverride $Checkout $Suite $Shell; if ($null -ne $ov) { return $ov } }
            $env:HORDE_MERGE_STUB_SHELL = $Shell
            $o = & (Join-Path $Checkout $Suite)
            return [pscustomobject]@{ code = $LASTEXITCODE; out = (@($o) -join "`n"); err = "" }
        }
        Ledger = { param([string[]]$Arguments) return (Invoke-MergeStandInLedger -StatePath $script:toolCase.ledger -Arguments (@("C:\fleet\task.py") + @($Arguments))) }
        LedgerLine = $real["LedgerLine"]
        Tell = { param([string]$Body) [void]$script:told.Add($Body); if ($script:tellFails) { return [pscustomobject]@{ ok = $false; detail = "no session holds the role of warchief" } }; return [pscustomobject]@{ ok = $true; detail = "accepted" } }
        Owed = { param([string]$Line) if ($script:owedFails) { return [pscustomobject]@{ ok = $false; detail = "the merge folder is read-only" } }; return (Add-HordeMergeLine -Path (Join-Path $script:toolCase.owed "guards-owed.jsonl") -Line $Line) }
        Intent = { param([string]$Line) if ($script:intentFails) { return [pscustomobject]@{ ok = $false; detail = "the merge folder is read-only" } }; return (Add-HordeMergeLine -Path (Join-Path $script:toolCase.owed "guards-intent.jsonl") -Line $Line) }
        Mail = { param([string]$Text) [void]$script:mailed.Add($Text); if ($script:mailFails) { return [pscustomobject]@{ ok = $false; detail = "the mail folder is read-only" } }; return [pscustomobject]@{ ok = $true; detail = "left for the analyst" } }
        Wait = { param([int]$Seconds) [void]$script:waited.Add($Seconds) }
        Say = { param([string]$Line) [void]$script:said.Add($Line) }
    }
}

function Invoke-Case {
    # Invoke-HordeMerge on one case: the answer.
    param($Case, [string]$Pr = "YedPool/horde#1", [string]$Task = "T-0247", [string]$State = "done", [string]$By = "F", [string]$On = "", [string]$Reason = "", [switch]$TellFails, [switch]$MailFails, [scriptblock]$BeforeGuard = $null, [string]$GitFails = "", [string]$Guards = "now", [switch]$OwedFails, [switch]$IntentFails, [scriptblock]$GhWrap = $null)
    $req = Test-HordeMergeRequest -Pr $Pr -Task $Task -State $State -By $By -On $On -Reason $Reason -Guards $Guards
    if (-not $req.ok) { throw ("the suite built a bad request: " + $req.why) }
    $tools = New-SuiteTools -Case $Case -TellFails:$TellFails -MailFails:$MailFails -BeforeGuard $BeforeGuard -GitFails $GitFails -OwedFails:$OwedFails -IntentFails:$IntentFails
    # A GhWrap sees each gh call first ($Arguments, and $script:innerGh for the stand-in) and may answer in its place.
    if ($null -ne $GhWrap) { $script:innerGh = $tools["Gh"]; $script:ghWrap = $GhWrap; $tools["Gh"] = { param([string[]]$Arguments) return (& $script:ghWrap $Arguments) } }
    # A throw is an answer of its own, so a mutant that makes the command crash fails a check by name
    # (tools\Mutate.ps1 counts only a failed check as caught).
    try { return (Invoke-HordeMerge -Request $req -Tools $tools -WorkFolder $Case.work) }
    catch { return [pscustomobject]@{ outcome = "threw"; why = $_.Exception.Message; mergeSha = ""; problems = @() } }
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
Check (($args4 -join "|") -ceq "merged|T-0001|--pr|o/r#1|--by|F|--state|progress|--reason=docs left") "progress carries its reason as one --reason=<text> word"
$args5 = Get-HordeMergeLedgerArguments -Request (Test-HordeMergeRequest -Pr "o/r#1" -Task "T-0001" -State "progress" -By "F" -Reason "-docs left")
Check ($args5[-1] -ceq "--reason=-docs left") "a reason starting with - stays the value of --reason, which argparse would read as a flag on its own"
Check ((Test-HordeMergeShellScript -Program "C:\x\task.cmd") -and (Test-HordeMergeShellScript -Program "run.BAT") -and (Test-HordeMergeShellScript -Program '"C:\a b\x.cmd"') -and -not (Test-HordeMergeShellScript -Program "python") -and -not (Test-HordeMergeShellScript -Program "C:\x\cmd.exe")) "a .cmd or .bat program is told apart from a program"
$viaCmd = Invoke-HordeMergeProgram -Program (Join-Path $work "never.cmd") -Arguments @("x")
Check ($viaCmd.code -eq -1 -and $viaCmd.err -clike "*is a .cmd or .bat*") "a .cmd or .bat is never started: cmd would re-read its arguments"
$tempRoot = [System.IO.Path]::GetTempPath()
Check ((Test-HordeMergeHomeIsATests -HordeHome (Join-Path $tempRoot "h1")) -eq $true) "a Horde home under temp is a test's"
Check ((Test-HordeMergeHomeIsATests -HordeHome "C:\fleet\home" -TempRoot "C:\tmp-root") -eq $false) "a Horde home outside temp is not a test's"
Check ((Test-HordeMergeHomeIsATests -HordeHome "C:\tmp-rootx\home" -TempRoot "C:\tmp-root") -eq $false) "a folder that only starts with temp's name is not under it"
Check ((Test-HordeMergeHomeIsATests -HordeHome ("C:\bad" + [char]0 + "path") -TempRoot "C:\tmp-root") -eq $true) "a home that cannot be resolved is taken as a test's: telling nobody is the safe mistake"
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
# A run killed before its finally left a scratch folder behind; it must not outlive the next run.
$leftover = Join-Path $c.work "runs\7-0ld0ld\deep"
[void][System.IO.Directory]::CreateDirectory($leftover)
[System.IO.File]::WriteAllText((Join-Path $leftover "f.txt"), "x", $utf8)
[System.IO.File]::SetAttributes((Join-Path $leftover "f.txt"), [System.IO.FileAttributes]::ReadOnly)
$r = Invoke-Case -Case $c
$main = Get-Main $c
$parents = @((G $c.origin rev-list --parents -n 1 $main) -split " ")
Check ($r.outcome -ceq "merged" -and $r.mergeSha -ceq $main) ("a green PR is merged, and the sha said is main's new tip: " + $r.outcome + " " + $r.mergeSha)
Check ($parents.Count -eq 3 -and $parents[1] -ceq $c1 -and $parents[2] -ceq $heads["1"]) "main's new tip is a merge commit of main and the head, never a squash"
$mergeCalls = @(Get-GhCalls $c | Where-Object { $_ -clike "pr merge *" })
Check ($mergeCalls.Count -eq 1 -and $mergeCalls[0] -ceq ("pr merge 1 --repo YedPool/horde --merge --match-head-commit " + $heads["1"])) ("gh is asked for --merge with the checked head pinned: " + ($mergeCalls -join " | "))
Check (@($script:guardRuns).Count -eq 4 -and (@($script:guardRuns | ForEach-Object { $_.suite + "|" + $_.shell }) -join ",") -ceq "test\test-host-names.ps1|5.1,test\test-host-names.ps1|7,test\test-mutation-specs.ps1|5.1,test\test-mutation-specs.ps1|7") "both guards ran, each in both shells"
Check ($script:guardRuns[0].commit -ceq $heads["1"] -and $script:guardRuns[0].originMain -ceq $c1) "they ran on the head, in a checkout whose origin/main is main"
Check ((Said "the PR head * already contains main *: the head is what is checked")) "it says the head already contains main"
Check (-not [System.IO.Directory]::Exists($script:guardRuns[0].checkout) -and @([System.IO.Directory]::GetDirectories((Join-Path $c.work "runs"))).Count -eq 0) "the scratch checkout, and a past run's left-over folder, are removed"
Check ((G (Join-Path $c.work "repos\YedPool\horde.git") for-each-ref refs/horde-merge) -ceq "") "the PR's ref is dropped from the cache once checked"
Check (@(Get-GhCalls $c | Where-Object { $_ -ceq ("api repos/YedPool/horde/commits/" + $main + " --jq .parents[].sha") }).Count -eq 1) "where the merge landed is read back from GitHub"
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
Check ($r.outcome -ceq "merged" -and @($script:guardRuns).Count -eq 8) ("main moved once: the guards ran again before the merge (" + @($script:guardRuns).Count + " runs)")
Check ((Said "main moved from * to * while the guards ran: checking the new combination before merging")) "it says main moved and the new combination is checked"
Check ($script:guardRuns[4].originMain -ceq $moved -and $script:guardRuns[4].commit -cne $heads["1"] -and @($script:guardRuns[4].parents)[0] -ceq $moved) "the second round checked the merge of the moved main and the head"
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
Check ((Said "run this by hand: & 'python' 'C:\fleet\task.py' 'merged' 'T-0247' '--pr' 'YedPool/horde#1' '--by' 'F' '--state' 'progress' '--reason=the docs are left'")) "and prints the exact command to run"
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
Check (@($script:waited).Count -eq 0 -and @(Get-GhCalls $c | Where-Object { $_ -clike "pr view 1 --repo YedPool/horde --json state,mergeCommit" }).Count -eq 1) "  a refused merge is looked at once, not waited on"

Write-Host "== main moves after the last check, before the merge"
$c = New-Case -Pr @{ "1" = @{ moveMainFirst = $true } }
$r = Invoke-Case -Case $c
$landedOn = @((G $c.origin rev-list --parents -n 1 (Get-Main $c)) -split " ")[1]
Check ($r.outcome -ceq "merged-unfinished" -and $landedOn -cne $c1 -and $r.why -clike ("*the merge landed on main " + $landedOn.Substring(0, 8) + ", which moved after the check; run the guards on main now*")) ("a merge that landed on a main the guards never saw is merged-unfinished, and says so: " + $r.why)
Check ((Said "THE MERGE IS ON A TREE THE GUARDS DID NOT CHECK: *")) "  it is said loudly"
Check (@($script:told).Count -eq 1 -and $script:told[0] -clike "*NOT CHECKED: the merge landed on main*" -and $script:told[0] -cnotlike "*Guards green on*" -and $script:mailed[0] -ceq $script:told[0]) "  and the warchief and the analyst are told it was NOT checked, never that the guards were green"
Check (@(Get-LedgerCalls $c).Count -eq 2) "  and the ledger still records the merge, which happened"

Write-Host "== refused: what git or GitHub cannot say"
$c = New-Case
$r = Invoke-Case -Case $c -GitFails "ls-remote"
Check ($r.outcome -ceq "refused" -and $r.why -clike "the base could not be read again after the guards: fatal: stand-in failure*" -and -not (Test-MergeCall $c)) ("a base that cannot be read again after the guards is refused: " + $r.why)
$c = New-Case
$r = Invoke-Case -Case $c -GitFails "--is-ancestor"
Check ($r.outcome -ceq "refused" -and $r.why -clike "asking git whether the head contains the base failed: fatal: stand-in failure*" -and @($script:guardRuns).Count -eq 0 -and -not (Test-MergeCall $c)) ("git failing to say whether the head contains main is refused, nothing checked: " + $r.why)
$c = New-Case -Pr @{ "1" = @{ headRefOid = "abc" } }
$r = Invoke-Case -Case $c
Check ($r.outcome -ceq "refused" -and $r.why -ceq "gh gave no head commit for YedPool/horde#1" -and @(Get-GhCalls $c | Where-Object { $_ -clike "repo view *" }).Count -eq 0) ("a head that is not a commit sha is refused before anything is fetched: " + $r.why)
$c = New-Case
$r = Invoke-Case -Case $c -Pr "YedPool/horde#8"
Check ($r.outcome -ceq "refused" -and $r.why -ceq "the guard test\test-mutation-specs.ps1 is not in the checked tree, so nothing can say it is green" -and -not (Test-MergeCall $c)) ("a tree without one of the guards is refused: " + $r.why)
$c = New-Case -Pr @{ "1" = @{ hideMerged = $true } }
$r = Invoke-Case -Case $c
Check ($r.outcome -ceq "merged-unfinished" -and $r.why -clike "gh said it merged YedPool/horde#1, but GitHub does not show it MERGED*ledger was NOT written*" -and @(Get-LedgerCalls $c).Count -eq 1 -and @($script:told).Count -eq 0) ("gh said merged, GitHub does not show it: nothing recorded, said: " + $r.why)
Check (@($script:waited).Count -eq 3 -and @(Get-GhCalls $c | Where-Object { $_ -clike "pr view 1 --repo YedPool/horde --json state,mergeCommit" }).Count -eq 4) "  GitHub is asked 4 times, 3 waits apart, before that is said"

Write-Host "== the guard list: test\guards.txt, read by the command and by CI"
foreach ($case in @(
    @{ N = "9"; Like = "the guard test\test-added.ps1 is red on * in Windows PowerShell 5.1; nothing was merged"; What = "a guard the PR adds to the list runs, and is red" },
    @{ N = "10"; Like = "the guard test\test-mutation-specs.ps1 is red on * in Windows PowerShell 5.1; nothing was merged"; What = "a guard the PR drops from the list still runs, from the base's list" },
    @{ N = "11"; Like = "the checked tree's guard list is unusable: line 4 of test\guards.txt is not a guard script*"; What = "a list with a line that is no guard" })) {
    $c = New-Case
    $r = Invoke-Case -Case $c -Pr ("YedPool/horde#" + $case.N)
    Check ($r.outcome -ceq "refused" -and $r.why -clike $case.Like -and -not (Test-MergeCall $c)) ($case.What + " is refused: " + $r.why)
}
$c = New-Case
$r = Invoke-Case -Case $c -Pr "YedPool/horde#13"
Check ($r.outcome -ceq "refused" -and $r.why -clike "the guard test\test-host-names.ps1 is red on * in PowerShell 7; nothing was merged" -and @($script:guardRuns).Count -eq 2 -and -not (Test-MergeCall $c)) ("a guard green in 5.1 and red in 7 is refused: " + $r.why)
$c = New-Case
$r = Invoke-Case -Case $c -Pr "YedPool/horde#12"
Check ($r.outcome -ceq "merged" -and @($script:guardRuns).Count -eq 4) ("a PR that deletes the list is still held to the base's: merged with " + @($script:guardRuns).Count + " guard runs")
Check ((Said "the guards, from test\guards.txt: test\test-host-names.ps1, test\test-mutation-specs.ps1 - each in Windows PowerShell 5.1 and PowerShell 7")) "the guards that will run are said before they do"

# THE BASE'S OWN LIST: main is moved (in the case's origin) to a commit whose list is unusable, or has none.
$c = New-Case
$null = G $seed checkout -q --detach $c1
[System.IO.File]::WriteAllText((Join-Path $seed "test\guards.txt"), "not a guard`n", $utf8)
$null = G $seed add -A
$null = G $seed commit -q -m "main has a bad list"
$null = G $seed push -q -f $c.origin "HEAD:refs/heads/main"
$r = Invoke-Case -Case $c
Check ($r.outcome -ceq "refused" -and $r.why -clike "the base's guard list is unusable: line 1 of test\guards.txt is not a guard script*" -and @($script:guardRuns).Count -eq 0 -and -not (Test-MergeCall $c)) ("a base whose list is unusable refuses the merge, no guard run: " + $r.why)
$c = New-Case
$null = G $seed checkout -q --detach $c1
[System.IO.File]::Delete((Join-Path $seed "test\guards.txt"))
$null = G $seed add -A
$null = G $seed commit -q -m "main has no list"
$null = G $seed push -q -f $c.origin "HEAD:refs/heads/main"
$r = Invoke-Case -Case $c
Check ($r.outcome -ceq "refused" -and $r.why -clike "neither the checked tree nor main has test\guards.txt*" -and @($script:guardRuns).Count -eq 0 -and -not (Test-MergeCall $c)) ("no list in the tree and none in the base: refused, never a green run of nothing: " + $r.why)
Write-Host "== the two shells: PowerShell 5.1 gets the machine's PSModulePath, 7 gets its own"
$echo = Invoke-HordeMergeProgram -Program "powershell.exe" -Arguments @("-NoProfile", "-NonInteractive", "-Command", '[Console]::Out.Write($env:PSModulePath)') -Environment @{ PSModulePath = "C:\horde-merge-probe\modules" }
Check ($echo.code -eq 0 -and $echo.out -clike "*C:\horde-merge-probe\modules*") "a child is given the PSModulePath it was handed (Invoke-HordeMergeProgram -Environment)"
$echo = Invoke-HordeMergeProgram -Program "powershell.exe" -Arguments @("-NoProfile", "-NonInteractive", "-Command", '[Console]::Out.Write($env:HORDE_MERGE_PROBE)') -Environment @{ HORDE_MERGE_PROBE = "kept" }
Check ($echo.code -eq 0 -and $echo.out -ceq "kept") "  and any other variable it is handed"
$probeFolder = Join-Path $work "probe"
[void][System.IO.Directory]::CreateDirectory($probeFolder)
$probe = '$psv = $PSVersionTable.PSVersion.Major; Write-Output ("shell " + $psv + " modules " + $env:PSModulePath); Write-Output "==== probe ===="; exit 0'
[System.IO.File]::WriteAllText((Join-Path $probeFolder "probe.ps1"), $probe, $utf8)
$machinePath = [Environment]::GetEnvironmentVariable("PSModulePath", "Machine")
$realTools = New-HordeMergeTools -Values ([pscustomobject]@{ gh = "gh"; git = "git"; guardShell = "powershell.exe"; guardShell7 = ""; ledgerProgram = "python"; ledgerScript = "C:\fleet\task.py"; workFolder = $work }) -Tell { } -Mail { } -MachinePsModulePath "C:\horde-merge-probe\machine"
$g51 = & $realTools["Guard"] $probeFolder "probe.ps1" "5.1"
Check ($g51.code -eq 0 -and $g51.out -clike "shell 5 modules *") ("the real guard runner runs a guard in Windows PowerShell 5.1: " + ("" + $g51.out + "            ").Substring(0, 10))
Check ($g51.out -clike "*C:\horde-merge-probe\machine*") "  with the machine's PSModulePath (a seam hands in the value), not the caller's"
$pwsh7Path = Get-HordeGuardPwsh7
if ([System.IO.File]::Exists($pwsh7Path)) {
    $g7 = & $realTools["Guard"] $probeFolder "probe.ps1" "7"
    Check ($g7.code -eq 0 -and $g7.out -clike "shell 7 modules *") ("the real guard runner runs a guard in PowerShell 7 (the MSI at " + $pwsh7Path + ")")
    Check ($g7.out -cnotlike "*C:\horde-merge-probe*") "  and with none of the machine value handed to 5.1"
    Check ($pwsh7Path -clike "*\PowerShell\7\pwsh.exe" -and $pwsh7Path -cnotlike "*WindowsApps*") "  and that is the MSI install, never the Store copy"
} else { Check $false ("PowerShell 7 is installed from the MSI at " + $pwsh7Path) }
$noSeven = New-HordeMergeTools -Values ([pscustomobject]@{ gh = "gh"; git = "git"; guardShell = "powershell.exe"; guardShell7 = (Join-Path $work "no\pwsh.exe"); ledgerProgram = "python"; ledgerScript = "C:\fleet\task.py"; workFolder = $work }) -Tell { } -Mail { }
$gNo = & $noSeven["Guard"] $probeFolder "probe.ps1" "7"
Check ($gNo.code -eq -1 -and $gNo.err -clike "PowerShell 7 is not at *no\pwsh.exe*") "a missing PowerShell 7 is a red guard that names the path, never a skipped one"
$gBad = & $realTools["Guard"] $probeFolder "probe.ps1" "6"
Check ($gBad.code -eq -1 -and $gBad.err -clike "*is not 5.1 or 7*") "a shell that is neither 5.1 nor 7 is refused"

Write-Host "== daytime mode (-Guards later, the default): merges do not wait for the guards"
function Read-OwedLines {
    param($Case)
    $f = Join-Path $Case.owed "guards-owed.jsonl"
    if (-not [System.IO.File]::Exists($f)) { return @() }
    return @(([System.IO.File]::ReadAllText($f) -split "\r?\n") | Where-Object { $_.Trim() -ne "" })
}
$g0 = Test-HordeMergeRequest -Pr "o/r#1" -Task "T-0001" -State "done" -By "F"
Check ($g0.ok -eq $true -and $g0.guards -ceq "later") "a request with no -Guards is a daytime one: later"
Check ((Test-HordeMergeRequest -Pr "o/r#1" -Task "T-0001" -State "done" -By "F" -Guards "now").guards -ceq "now") "-Guards now is taken"
$gBadMode = Test-HordeMergeRequest -Pr "o/r#1" -Task "T-0001" -State "done" -By "F" -Guards "never"
Check ($gBadMode.ok -eq $false -and $gBadMode.why -clike "*'never' is not when the guards run*") ("a -Guards that is neither later nor now is refused: " + $gBadMode.why)
$prOwed = Format-HordeMergeProgress -Request $g0 -Title "t" -GuardsOwed
Check ($prOwed -ceq "progress draft: F merged o/r#1 - t (T-0001, now done; guards owed to the nightly run)") ("the progress draft says the guards are owed: " + $prOwed)
Check ((Format-HordeMergeOwedLine -Request $g0 -HeadSha ("a" * 40) -MergeSha "(GitHub gave no merge commit)") -ceq "") "a merge with no sha has no line to queue"

$c = New-Case
$r = Invoke-Case -Case $c -Guards later
$main = Get-Main $c
Check ($r.outcome -ceq "merged" -and $r.mergeSha -ceq $main) ("later: a green PR is merged: " + $r.outcome + " " + $r.why)
Check (@($script:guardRuns).Count -eq 0 -and @(Get-GhCalls $c | Where-Object { $_ -clike "repo view *" }).Count -eq 0 -and -not (Said "the guards, from *") -and -not (Said "the PR head *")) "later: no guard ran and no tree was built or checked"
$mergeCalls = @(Get-GhCalls $c | Where-Object { $_ -clike "pr merge *" })
Check ($mergeCalls.Count -eq 1 -and $mergeCalls[0] -ceq ("pr merge 1 --repo YedPool/horde --merge --match-head-commit " + $heads["1"])) ("later: still --merge, pinned to the head GitHub reported: " + ($mergeCalls -join " | "))
$parents = @((G $c.origin rev-list --parents -n 1 $main) -split " ")
Check ($parents.Count -eq 3 -and $parents[1] -ceq $c1 -and $parents[2] -ceq $heads["1"]) "later: still a merge commit, never a squash"
$ol = @(Read-OwedLines $c)
Check ($ol.Count -eq 1) ("later: one line was added to guards-owed.jsonl (" + $ol.Count + ")")
$o = ConvertFrom-HordeJson -Text $ol[0]
Check ($o.repo -ceq "yedpool/horde" -and $o.baseRefName -ceq "main" -and $o.pr -ceq "YedPool/horde#1" -and $o.task -ceq "T-0247" -and $o.by -ceq "F" -and $o.headSha -ceq $heads["1"] -and $o.mergeSha -ceq $main -and $o.firstParent -ceq $c1) ("later: the line holds the repo (lower case, the way GitHub compares it), the base branch, pr, task, by, headSha, mergeSha and the merge's first parent: " + $ol[0])
Check ($o.at -cmatch '\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\z') ("later: at is a UTC ISO time: " + $o.at)
Check (@($o.PSObject.Properties).Count -eq 9) "later: and nothing else"
Check ((Said "guards not run: queued for the nightly run (guards-owed.jsonl)") -and (Said ("MERGED YedPool/horde#1 as " + $main))) "later: it says plainly that the guards were not run"
Check (@($script:told).Count -eq 1 -and $script:told[0] -clike "HORDE MERGE: F merged YedPool/horde#1 as *Guards NOT RUN: owed to the nightly run*" -and $script:told[0] -cnotlike "*Guards green*" -and $script:mailed[0] -ceq $script:told[0]) ("later: the warchief and the analyst are told the guards are owed, never that they passed: " + (@($script:told) -join " "))
Check ((Said "progress draft: F merged YedPool/horde#1 - PR 1 (T-0247, now done; guards owed to the nightly run)")) "later: the progress draft says the guards are owed"
$ledgerCalls = @(Get-LedgerCalls $c)
Check ($ledgerCalls.Count -eq 2 -and $ledgerCalls[1] -ceq "merged T-0247 --pr YedPool/horde#1 --by F --state done") "later: the ledger is read first and its merged event written, as before"

# THE POINT OF DAYTIME MODE: a PR whose guard is red is merged, and queued; the nightly run is what names it.
$c = New-Case
$r = Invoke-Case -Case $c -Pr "YedPool/horde#4" -Guards later
Check ($r.outcome -ceq "merged" -and @($script:guardRuns).Count -eq 0 -and @(Read-OwedLines $c).Count -eq 1) ("later: a PR that would turn a guard red is merged without a run, and queued: " + $r.outcome)
$c = New-Case
$r = Invoke-Case -Case $c -Pr "YedPool/horde#2" -Guards later
Check ($r.outcome -ceq "merged" -and @($script:guardRuns).Count -eq 0 -and (@(Read-OwedLines $c) | ForEach-Object { (ConvertFrom-HordeJson -Text $_).firstParent }) -ceq $c1) "later: a PR behind main is merged too, and its first parent is main as it was"

# A FAILURE TO QUEUE COMES AFTER A MERGE THAT HAPPENED: loud, with the line to add by hand, exit 1.
$c = New-Case
$r = Invoke-Case -Case $c -Guards later -OwedFails
$main = Get-Main $c
Check ($r.outcome -ceq "merged-unfinished" -and $r.mergeSha -ceq $main -and $r.why -clike "*the merge was not queued for the nightly guards run; add this line to guards-owed.jsonl: {*") ("later: a failure to queue is merged-unfinished and carries the line: " + $r.why)
Check ((Said "THE MERGE HAPPENED, BUT IT WAS NOT QUEUED FOR THE NIGHTLY GUARDS RUN: the merge folder is read-only") -and (Said ("add this line to guards-owed.jsonl by hand: {*" + $main + "*")) -and -not (Said "guards not run: queued*")) "later: it says so loudly, prints the line, and does not claim it was queued"
Check (@(Get-LedgerCalls $c).Count -eq 2 -and @($script:told).Count -eq 1 -and @(Read-OwedLines $c).Count -eq 0) "later: the ledger and the tells still went out; nothing was queued"
# S1: THE TELLS MUST NOT SAY "QUEUED" WHEN QUEUEING FAILED (review of PR 375).
Check ($script:told[0] -clike "*Guards NOT RUN and merge NOT QUEUED*add*by hand: {*" -and $script:told[0] -cnotlike "*queued in guards-owed.jsonl*" -and $script:told[0] -cnotlike "*owed to the nightly run*" -and $script:mailed[0] -ceq $script:told[0]) ("later: the warchief and the analyst are told the merge is NOT queued, with the line: " + $script:told[0])
Check (Said "progress draft: F merged YedPool/horde#1 - PR 1 (T-0247, now done; guards NOT RUN and NOT QUEUED for the nightly run)") "later: and so does the progress draft"
# THE REAL OWED TOOL: with no folder it queues nothing and says so; with one it appends.
$realOwed = New-HordeMergeTools -Values ([pscustomobject]@{ gh = "gh"; git = "git"; guardShell = "powershell.exe"; ledgerProgram = "python"; ledgerScript = "C:\fleet\task.py"; workFolder = $c.work }) -Tell { } -Mail { }
$owedNone = & $realOwed["Owed"] "{}"
Check ($owedNone.ok -eq $false -and $owedNone.detail -clike "*nowhere to queue*") "the real Owed tool with no merge folder queues nothing and says so"
$realOwed2 = New-HordeMergeTools -Values ([pscustomobject]@{ gh = "gh"; git = "git"; guardShell = "powershell.exe"; ledgerProgram = "python"; ledgerScript = "C:\fleet\task.py"; workFolder = $c.work }) -Tell { } -Mail { } -OwedFolder (Join-Path $work "real-owed")
$owedSome = & $realOwed2["Owed"] "{""a"":1}"
Check ($owedSome.ok -eq $true -and [System.IO.File]::ReadAllText((Join-Path $work "real-owed\guards-owed.jsonl")) -ceq "{""a"":1}`n") "the real Owed tool with a folder appends the line"
# S2: A FILE THAT DOES NOT END IN A LINE FEED must not swallow the next line.
$glue = Join-Path $work "glue\q.jsonl"
[void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $glue))
[System.IO.File]::WriteAllText($glue, "{""x"":1}", $utf8)
$gl = Add-HordeMergeLine -Path $glue -Line "{""x"":2}"
Check ($gl.ok -eq $true -and [System.IO.File]::ReadAllText($glue) -ceq "{""x"":1}`n{""x"":2}`n") "a line appended after an unterminated last line starts on its own line"
$gl = Add-HordeMergeLine -Path $glue -Line "{""x"":3}"
Check ([System.IO.File]::ReadAllText($glue) -ceq "{""x"":1}`n{""x"":2}`n{""x"":3}`n") "  and a terminated file gets no blank line"
$c = New-Case
[void][System.IO.Directory]::CreateDirectory($c.owed)
$firstEntry = Format-HordeMergeOwedLine -Request $g0 -HeadSha ("a" * 40) -MergeSha ("b" * 40) -FirstParent ("c" * 40) -BaseRef "main"
[System.IO.File]::WriteAllText((Join-Path $c.owed "guards-owed.jsonl"), $firstEntry, $utf8)
$r = Invoke-Case -Case $c -Guards later
$parsed = Read-HordeMergeOwedEntries -Text ([System.IO.File]::ReadAllText((Join-Path $c.owed "guards-owed.jsonl")))
Check ($r.outcome -ceq "merged" -and $parsed.entries.Count -eq 2 -and $parsed.bad.Count -eq 0) ("a merge queued after an unterminated line is its own usable line (" + $parsed.entries.Count + " entries, " + $parsed.bad.Count + " bad)")

# NOW IS TODAY'S BEHAVIOUR, UNCHANGED.
$c = New-Case
$r = Invoke-Case -Case $c -Guards now
Check ($r.outcome -ceq "merged" -and @($script:guardRuns).Count -eq 4 -and @(Read-OwedLines $c).Count -eq 0 -and $script:told[0] -clike "*Guards green on *" -and $script:told[0] -cnotlike "*NOT RUN*") "now: the guards ran in both shells, nothing was queued, the warchief is told they were green"
Check (-not (Said "guards not run: queued*") -and (Said "progress draft: F merged YedPool/horde#1 - PR 1 (T-0247, now done)")) "now: no word of an owed run, and the progress draft is the old one"
$c = New-Case
$r = Invoke-Case -Case $c -Pr "YedPool/horde#4" -Guards now
Check ($r.outcome -ceq "refused" -and -not (Test-MergeCall $c) -and @(Read-OwedLines $c).Count -eq 0) "now: a red guard still refuses, and queues nothing"

Write-Host "== the nightly run (horde merge -RunOwed): which queued merge turned a guard red"
$nightly = [datetime]::new(2026, 10, 23, 3, 0, 0, [System.DateTimeKind]::Utc)
function Invoke-OwedRun {
    param($Case, [string]$Repo = "", [scriptblock]$GuardOverride = $null, $Now = $null)
    $tools = New-SuiteTools -Case $Case -GuardOverride $GuardOverride
    if ($null -eq $Now) { $Now = $nightly }
    try { return (Invoke-HordeMergeRunOwed -Tools $tools -WorkFolder $Case.work -Folder $Case.owed -Repo $Repo -Now $Now) }
    catch { return [pscustomobject]@{ exit = -9; json = ""; repos = @(); threw = $_.Exception.Message } }
}
function Add-QueuedMerges {
    # Merge each [PR number, lane] in order, daytime mode, as the fleet does; the outcomes joined.
    param($Case, $Merges)
    $out = @()
    foreach ($m in $Merges) { $out += (Invoke-Case -Case $Case -Pr ("YedPool/horde#" + $m[0]) -By $m[1] -Guards later).outcome }
    return ($out -join ",")
}
function Read-CheckedLines {
    param($Case)
    $f = Join-Path $Case.owed "guards-checked.jsonl"
    if (-not [System.IO.File]::Exists($f)) { return @() }
    return @(([System.IO.File]::ReadAllText($f) -split "\r?\n") | Where-Object { $_.Trim() -ne "" })
}

# Three merges, in order: PR 1 (green), PR 4 (turns test-mutation-specs red), PR 2 (green on its own).
$c = New-Case
Check ((Add-QueuedMerges $c @(@("1", "F"), @("4", "K"), @("2", "C"))) -ceq "merged,merged,merged") "three PRs are merged in daytime mode and queued"
$owedLines = @(Read-OwedLines $c)
$shas = @($owedLines | ForEach-Object { (ConvertFrom-HordeJson -Text $_).mergeSha })
$owedFile = Join-Path $c.owed "guards-owed.jsonl"
$owedBefore = [System.IO.File]::ReadAllText($owedFile)
$run = Invoke-OwedRun -Case $c
Check ($run.exit -eq 1) ("one guard red at the tip: exit 1 (" + $run.exit + " " + $(if ($run.PSObject.Properties["threw"]) { $run.threw } else { "" }) + ")")
Check ((Said ("RED test\test-mutation-specs.ps1 in *: first red at the merge of YedPool/horde#4 (task T-0247, by K, mergeSha " + $shas[1] + ")*"))) "the merge that turned the guard red is named: its PR, task, lane and merge sha (merge 2 of 3)"
Check (@($script:said | Where-Object { $_ -clike "RED *" }).Count -eq 1 -and (Said "test\test-host-names.ps1 is green at the tip")) "only the red guard is named; the green one is said green"
Check (-not (Said "*first red at the merge of YedPool/horde#1 *") -and -not (Said "*first red at the merge of YedPool/horde#2 *")) "no other merge is blamed"
$gr = @($script:guardRuns)
Check ($gr.Count -eq 14 -and $gr[0].commit -ceq (G $c.origin rev-parse refs/heads/main)) ("the tip ran both guards in both shells (the red one twice in each: a red is run once more), then only the red one was walked, stopping at the first red: " + $gr.Count + " runs")
Check ($gr.Count -eq 14 -and (@($gr | Select-Object -Skip 6 | ForEach-Object { $_.suite } | Select-Object -Unique) -join ",") -ceq "test\test-mutation-specs.ps1" -and $gr[6].commit -ceq $c1 -and $gr[8].commit -ceq $shas[0] -and $gr[10].commit -ceq $shas[1]) "the walk ran the baseline (the first merge's first parent), then merge 1, then merge 2"
$reportFile = Join-Path $c.owed "nightly\2026-10-23-yedpool-horde.txt"
$report = ""
if ([System.IO.File]::Exists($reportFile)) { $report = [System.IO.File]::ReadAllText($reportFile) }
Check ($report -clike "guards report for yedpool/horde, 2026-10-23T03:00:00Z (UTC)*RED test\test-mutation-specs.ps1*YedPool/horde#4*" -and $report -cmatch '\A[\x09\x0A\x0D\x20-\x7E]*\z') "the report is a plain ASCII file at nightly\<UTC date>-<owner>-<repo>.txt"
$cl = @(Read-CheckedLines $c)
Check ($cl.Count -eq 3 -and ((@($cl | ForEach-Object { (ConvertFrom-HordeJson -Text $_).mergeSha }) -join ",") -ceq ($shas -join ","))) "each checked merge's sha was appended to guards-checked.jsonl"
Check ([System.IO.File]::ReadAllText($owedFile) -ceq $owedBefore) "guards-owed.jsonl was never edited"
$sum = ConvertFrom-HordeJson -Text $run.json
Check ($sum.exit -eq 1 -and @($sum.repos).Count -eq 1 -and $sum.repos[0].status -ceq "red" -and $sum.repos[0].merges -eq 3 -and $sum.repos[0].reds[0].guard -ceq "test\test-mutation-specs.ps1" -and $sum.repos[0].reds[0].merge.pr -ceq "YedPool/horde#4" -and $sum.repos[0].reds[0].merge.mergeSha -ceq $shas[1]) ("the JSON summary names the repo, the guard and the merge: " + $run.json)
Check ($sum.repos[0].report -ceq $reportFile) "  and the report's path"

# A SECOND RUN skips what is checked - but main is still red, and a red main reads red until a run finds it green (T-0347:
# this check used to enshrine exit 0 and "nothing is owed" here, which read the red main as green on the next quiet night).
$run = Invoke-OwedRun -Case $c
Check ($run.exit -eq 1 -and @($script:guardRuns).Count -eq 6 -and (Said "RED test\test-mutation-specs.ps1 in *STILL RED since*") -and @(Read-CheckedLines $c).Count -eq 3) "a second run finds nothing new owed, adds nothing checked, and main still reads RED"
Check ((ConvertFrom-HordeJson -Text $run.json).exit -eq 1 -and @((ConvertFrom-HordeJson -Text $run.json).repos).Count -eq 1) "  and its JSON says so"
# ...and a merge queued after it is the only one run.
Check ((Add-QueuedMerges $c @(,@("3", "F"))) -cmatch "\Amerged\z") "a fourth PR is merged and queued"
$run = Invoke-OwedRun -Case $c
$sum = ConvertFrom-HordeJson -Text $run.json
Check ($sum.repos[0].merges -eq 1 -and @(Read-CheckedLines $c).Count -eq 4) "the next run takes only the entry not checked yet"

# ALL GREEN
$c = New-Case
Check ((Add-QueuedMerges $c @(@("1", "F"), @("2", "C"))) -ceq "merged,merged") "two green PRs are merged and queued"
$run = Invoke-OwedRun -Case $c
$gr = @($script:guardRuns)
Check ($run.exit -eq 0 -and (Said "all green over 2 merges") -and $gr.Count -eq 4) ("clean: exit 0, 'all green over 2 merges', and only the tip was run (" + $gr.Count + " runs)")
$reportFile = Join-Path $c.owed "nightly\2026-10-23-yedpool-horde.txt"
Check ([System.IO.File]::Exists($reportFile) -and [System.IO.File]::ReadAllText($reportFile) -clike "*all green over 2 merges*" -and @(Read-CheckedLines $c).Count -eq 2) "  the report says it too, and both merges are marked checked"
Check ((ConvertFrom-HordeJson -Text $run.json).repos[0].status -ceq "green") "  and the JSON"

# A GUARD RED IN POWERSHELL 7 ONLY is red: PR 13 is green in 5.1 and red in 7.
$c = New-Case
Check ((Add-QueuedMerges $c @(@("1", "F"), @("13", "K"))) -ceq "merged,merged") "two PRs are merged and queued, the second red in PowerShell 7 only"
$run = Invoke-OwedRun -Case $c
Check ($run.exit -eq 1 -and (Said "RED test\test-host-names.ps1 in PowerShell 7: first red at the merge of YedPool/horde#13 (task T-0247, by K, mergeSha *") -and @($script:guardRuns).Count -eq 9) ("a guard red in 7 only is named, with the shell, and the walk runs 7 alone: " + $run.exit + " " + @($script:guardRuns).Count)

# BASELINE ALREADY RED: main was red before the first queued merge.
$c = New-Case
$null = G $seed checkout -q --detach $c1
[System.IO.File]::WriteAllText((Join-Path $seed "guard.txt"), "specs-red", $utf8)
$null = G $seed add -A
$null = G $seed commit -q -m "main starts the day red"
$null = G $seed push -q -f $c.origin "HEAD:refs/heads/main"
Check ((Add-QueuedMerges $c @(@("1", "F"), @("2", "C"))) -ceq "merged,merged") "two PRs are merged onto a main that is already red"
$run = Invoke-OwedRun -Case $c
Check ($run.exit -eq 1 -and (Said "RED test\test-mutation-specs.ps1 in *: red before today's first queued merge*") -and -not (Said "*first red at the merge of*")) "a red baseline says 'red before today's first queued merge' and names no merge"
Check ($null -eq (ConvertFrom-HordeJson -Text $run.json).repos[0].reds[0].merge -and @($script:guardRuns).Count -eq 10) ("  with no merge in the JSON, and no walk past the baseline (" + @($script:guardRuns).Count + " runs)")

# -Repo
$c = New-Case
Check ((Add-QueuedMerges $c @(,@("1", "F"))) -ceq "merged") "a PR is merged and queued"
$run = Invoke-OwedRun -Case $c -Repo "Other/repo"
Check ($run.exit -eq 0 -and (Said "nothing is owed*") -and @($script:guardRuns).Count -eq 0) "-Repo of another repository: nothing is owed, nothing runs"
$run = Invoke-OwedRun -Case $c -Repo "YedPool/horde"
Check ($run.exit -eq 0 -and (Said "all green over 1 merges")) "-Repo of this one: it runs"
$run = Invoke-OwedRun -Case $c -Repo "not a repo"
Check ($run.exit -eq 2 -and (Said "*is not a repository*")) "-Repo that is not OWNER/REPO: exit 2"
$empty = New-Case
$run = Invoke-OwedRun -Case $empty
Check ($run.exit -eq 0 -and (Said "nothing is owed*")) "no queue at all: nothing is owed, exit 0"

# THE FIXES OF THE REVIEW OF PR 375 (M1-M3, S1-S8). These cases build a line of plain commits on the case's origin
# and write the owed queue by hand, one entry per commit: what the queue holds is exactly what horde merge wrote
# (checked above), and the history can then hold things a stand-in merge cannot make (a list that changes, a
# guard fixed and broken again, an unqueued push, a branch other than main).
function New-HandCase {
    # -Steps: @{ f = @{ path = text-or-$null }; by = "K"; repo = "YedPool/horde" (optional) }, merged in order on -Base.
    # The first step's first parent is C1 (the baseline). -Unqueued are further commits pushed after the last step.
    # -Legacy writes the lines without baseRefName. Returns the case and the merge shas.
    param([object[]]$Steps, [string]$Base = "main", [object[]]$Unqueued = @(), [switch]$Legacy)
    $hc = New-Case
    $prev = $c1
    $shas = @()
    $firsts = @()
    foreach ($st in $Steps) {
        $firsts += $prev
        $prev = New-SeedCommit -From $prev -Files $st.f -Message "hand step"
        $shas += $prev
    }
    $tipSha = $prev
    foreach ($st in $Unqueued) { $tipSha = New-SeedCommit -From $tipSha -Files $st.f -Message "unqueued" }
    $null = G $seed push -q -f $hc.origin ($tipSha + ":refs/heads/" + $Base)
    $i = 0
    foreach ($st in $Steps) {
        $repoName = "yedpool/horde"
        if ($st.ContainsKey("repo")) { $repoName = $st.repo }
        $o = [ordered]@{ repo = $repoName }
        if (-not $Legacy) { $o["baseRefName"] = $Base }
        $o["pr"] = "YedPool/horde#" + (100 + $i); $o["task"] = "T-0247"; $o["by"] = $st.by; $o["at"] = "2026-10-22T10:00:00Z"; $o["headSha"] = $shas[$i]; $o["mergeSha"] = $shas[$i]; $o["firstParent"] = $firsts[$i]
        $null = Add-HordeMergeLine -Path (Join-Path $hc.owed "guards-owed.jsonl") -Line (ConvertTo-Json -InputObject $o -Compress)
        $i++
    }
    return [pscustomobject]@{ c = $hc; shas = @($shas); firsts = @($firsts); tip = $tipSha }
}
$onlyHost = "test/test-host-names.ps1`n"

Write-Host "== M1: a guard a queued merge drops, empties or deletes is red, and the merge is named"
$h = New-HandCase -Steps @(@{ f = @{ "test\guards.txt" = $onlyHost }; by = "K" }, @{ f = @{ "one.txt" = "1" }; by = "F" })
$run = Invoke-OwedRun -Case $h.c
Check ($run.exit -eq 1 -and (Said ("RED test\test-mutation-specs.ps1 dropped from test\guards.txt: dropped from the list by the merge of YedPool/horde#100 (task T-0247, by K, mergeSha " + $h.shas[0] + ") on main*"))) ("a guard the day's first merge dropped from the list is RED and that merge is named (exit " + $run.exit + ")")
Check (-not (Said "*dropped from the list by the merge of YedPool/horde#101*") -and @($script:guardRuns | Where-Object { $_.suite -ceq "test\test-mutation-specs.ps1" }).Count -eq 0) "  not the later one, and the dropped guard is not run"
$sum = ConvertFrom-HordeJson -Text $run.json
Check ($sum.repos[0].reds[0].kind -ceq "dropped" -and $sum.repos[0].reds[0].merge.pr -ceq "YedPool/horde#100") "  and the JSON says it was dropped"
$h = New-HandCase -Steps @(@{ f = @{ "one.txt" = "1" }; by = "F" }, @{ f = @{ "test\test-mutation-specs.ps1" = "exit 0`n" }; by = "K" })
$run = Invoke-OwedRun -Case $h.c
Check ($run.exit -eq 1 -and (Said ("RED test\test-mutation-specs.ps1 in *: first red at the merge of YedPool/horde#101 (task T-0247, by K, mergeSha " + $h.shas[1] + ")*"))) ("a guard emptied by a queued merge (it exits 0 with no banner) is red and that merge is named (exit " + $run.exit + ")")
$h = New-HandCase -Steps @(@{ f = @{ "one.txt" = "1" }; by = "F" }, @{ f = @{ "test\test-mutation-specs.ps1" = $null }; by = "K" })
$run = Invoke-OwedRun -Case $h.c
Check ($run.exit -eq 1 -and (Said ("RED test\test-mutation-specs.ps1 in the tree: first red at the merge of YedPool/horde#101 (task T-0247, by K, mergeSha " + $h.shas[1] + ")*"))) ("a guard script a queued merge deleted, still listed, is red and that merge is named (exit " + $run.exit + ")")

Write-Host "== M2: a guard that did not run is not a red, blames no merge and marks nothing checked"
$notRun7 = { param($Checkout, $Suite, $Shell) if ($Shell -ceq "7") { return [pscustomobject]@{ code = -1; out = ""; err = "PowerShell 7 is not at C:\nowhere\pwsh.exe; install the MSI" } }; return $null }
$h = New-HandCase -Steps @(@{ f = @{ "one.txt" = "1" }; by = "F" }, @{ f = @{ "two.txt" = "2" }; by = "K" })
$run = Invoke-OwedRun -Case $h.c -GuardOverride $notRun7
Check ($run.exit -eq 2 -and (Said "COULD NOT RUN on main: the guard test\test-host-names.ps1 could not be run in PowerShell 7 at *PowerShell 7 is not at*") -and -not (Said "RED *") -and -not (Said "*first red at the merge*")) ("pwsh 7 missing: exit 2, 'could not run', no red and no merge named (exit " + $run.exit + ")")
Check (@(Read-CheckedLines $h.c).Count -eq 0 -and (ConvertFrom-HordeJson -Text $run.json).repos[0].status -ceq "error") "  nothing is marked checked, and the JSON says error"
$report = [System.IO.File]::ReadAllText((Join-Path $h.c.owed "nightly\2026-10-23-yedpool-horde.txt"))
Check ($report -clike "*COULD NOT RUN on main*2 merge(s) stay owed*") "  the report says the merges stay owed"
$run = Invoke-OwedRun -Case $h.c
Check ($run.exit -eq 0 -and (Said "all green over 2 merges") -and @(Read-CheckedLines $h.c).Count -eq 2) "  and the next run, with 7 back, checks them"
$flakyOnce = { param($Checkout, $Suite, $Shell) if ($Shell -ceq "7" -and $script:flakyLeft -gt 0) { $script:flakyLeft--; return [pscustomobject]@{ code = 1; out = "  [FAIL] starved`n==== 1 FAILURE(S) ===="; err = "" } }; return $null }
$script:flakyLeft = 1
$run = Invoke-OwedRun -Case (New-HandCase -Steps @(@{ f = @{ "one.txt" = "1" }; by = "F" }, @{ f = @{ "two.txt" = "2" }; by = "K" })).c -GuardOverride $flakyOnce
Check ($run.exit -eq 0 -and (Said "test\test-host-names.ps1 was red in PowerShell 7 at * and green on a second run*") -and -not (Said "RED *")) ("a red that is green on a second run is said, counted green, and blames no merge (exit " + $run.exit + ")")

Write-Host "== M3: a merge into another branch is walked on that branch; one that cannot be walked does not stop the rest"
$h = New-HandCase -Steps @(@{ f = @{ "guard.txt" = "specs-red" }; by = "K" }, @{ f = @{ "one.txt" = "1" }; by = "F" }) -Base "stack"
$legacy = ConvertTo-Json -InputObject ([ordered]@{ repo = "YedPool/horde"; pr = "YedPool/horde#5"; task = "T-0247"; by = "C"; at = "2026-10-22T09:00:00Z"; headSha = $c1; mergeSha = $c1; firstParent = $c0 }) -Compress
$null = Add-HordeMergeLine -Path (Join-Path $h.c.owed "guards-owed.jsonl") -Line $legacy
$run = Invoke-OwedRun -Case $h.c
Check ($run.exit -eq 1 -and (Said ("RED test\test-mutation-specs.ps1 in *: first red at the merge of YedPool/horde#100 (task T-0247, by K, mergeSha " + $h.shas[0] + ") on stack*"))) ("merges into a stacked branch are walked on it, not on the default branch (exit " + $run.exit + "): " + (@($script:said | Where-Object { $_ -clike "COULD NOT*" -or $_ -clike "NOT CHECKED*" -or $_ -clike "WARNING*" }) -join " | "))
Check (@(Read-CheckedLines $h.c).Count -eq 3) "  all three are checked: the two on the branch and the old line without a base, which is main's"
Check ((Said "yedpool/horde stack: 2 merge(s) owed*") -and (Said "yedpool/horde main: 1 merge(s) owed*")) "  the run walked each branch it needed, one after the other"
$sum = ConvertFrom-HordeJson -Text $run.json
Check ($sum.repos[0].reds[0].base -ceq "stack") "  the JSON names the branch of the red"

$c = New-Case
Check ((Add-QueuedMerges $c @(,@("1", "F"))) -ceq "merged") "a PR is merged and queued, and a line for a merge main does not hold is added"
$bogus = '{"repo":"YedPool/horde","pr":"YedPool/horde#9","task":"T-0247","by":"F","at":"2026-10-22T10:00:00Z","headSha":"' + ("b" * 40) + '","mergeSha":"' + ("a" * 40) + '","firstParent":"' + ("c" * 40) + '"}'
$null = Add-HordeMergeLine -Path (Join-Path $c.owed "guards-owed.jsonl") -Line $bogus
$run = Invoke-OwedRun -Case $c
Check ($run.exit -eq 0 -and (Said ("NOT CHECKED: the merge " + ("a" * 40) + " (YedPool/horde#9) is not in the history of main *")) -and @(Read-CheckedLines $c).Count -eq 1) ("a merge that is not in main's history is reported and skipped; the good one is still checked (exit " + $run.exit + ")")
$sum = ConvertFrom-HordeJson -Text $run.json
Check (@($sum.repos[0].skipped).Count -eq 1 -and $sum.repos[0].skipped[0].mergeSha -ceq ("a" * 40) -and $sum.repos[0].checked -eq 1) "  and the JSON lists what was skipped"
$run = Invoke-OwedRun -Case $c
Check ($run.exit -eq 2 -and (Said "NOT CHECKED: *")) "  alone, it is said again in every run, and with nothing else to check the run ends 2"
$giveUp = @($script:said | Where-Object { $_ -clike "NOT CHECKED: *" })[0]
$giveUpLine = $giveUp.Substring($giveUp.IndexOf(": {") + 2)
Check ($giveUpLine -clike "{*" -and $giveUp -clike "*to give it up, add this line to *guards-checked.jsonl: {*") ("  and the report prints the line that gives it up: " + $giveUpLine)
$null = Add-HordeMergeLine -Path (Join-Path $c.owed "guards-checked.jsonl") -Line $giveUpLine
$run = Invoke-OwedRun -Case $c
Check ($run.exit -eq 0 -and (Said "nothing is owed*")) "  and once that line is added it is not reported again"
$c = New-Case
$null = Add-HordeMergeLine -Path (Join-Path $c.owed "guards-owed.jsonl") -Line $bogus
$run = Invoke-OwedRun -Case $c
Check ($run.exit -eq 2 -and (Said "NOT CHECKED: *") -and @(Read-CheckedLines $c).Count -eq 0 -and @($script:guardRuns).Count -eq 0) "only a merge that cannot be walked: exit 2, nothing run, nothing marked checked"
Check ((ConvertFrom-HordeJson -Text $run.json).repos[0].status -ceq "error") "  and the JSON says error"

Write-Host "== S5, S6, S7, N5: the repo name's case, a report that cannot be written, a damaged line, a line queued twice"
$c = New-Case
Check ((Invoke-Case -Case $c -Pr "yedpool/horde#1" -Guards later).outcome -ceq "merged") "a PR typed in lower case is merged and queued"
$qo = ConvertFrom-HordeJson -Text (@(Read-OwedLines $c)[0])
Check ($qo.repo -ceq "yedpool/horde") "  its repo is written in lower case"
$run = Invoke-OwedRun -Case $c -Repo "YedPool/horde"
Check ($run.exit -eq 0 -and (Said "all green over 1 merges") -and -not (Said "nothing is owed*")) "-Repo in another case still finds it: no false 'nothing is owed'"
$c = New-Case
Check ((Add-QueuedMerges $c @(,@("4", "K"))) -ceq "merged") "a red PR is merged and queued"
[System.IO.File]::WriteAllText((Join-Path $c.owed "nightly"), "in the way", $utf8)
$run = Invoke-OwedRun -Case $c
Check ($run.exit -eq 1 -and (Said "COULD NOT WRITE THE REPORT: *no merge is marked checked*") -and (Said "RED test\test-mutation-specs.ps1 in *first red at the merge of YedPool/horde#4*") -and @(Read-CheckedLines $c).Count -eq 0) ("a report that cannot be written marks nothing checked, and the finding is still printed (exit " + $run.exit + ")")
Check ((ConvertFrom-HordeJson -Text $run.json).repos[0].status -ceq "error") "  and the JSON says error"
$c = New-Case
Check ((Add-QueuedMerges $c @(,@("1", "F"))) -ceq "merged") "a PR is merged and queued"
$null = Add-HordeMergeLine -Path (Join-Path $c.owed "guards-owed.jsonl") -Line "this is not json"
$run = Invoke-OwedRun -Case $c
Check ($run.exit -eq 0 -and (Said "WARNING: *1 line(s) that are not a usable entry (line 2)*said again in every run*") -and @(Read-CheckedLines $c).Count -eq 1) ("a line that is not an entry is said with its number, and the good entry is still checked; the run is not failed for it (exit " + $run.exit + ")")
$run = Invoke-OwedRun -Case $c
Check ($run.exit -eq 2 -and (Said "WARNING: *line 2*") -and (Said "nothing is owed*")) "  and when it is all that is left, the run ends 2 and says it again"
$dup = Format-HordeMergeOwedLine -Request $g0 -HeadSha ("a" * 40) -MergeSha ("b" * 40) -FirstParent ("c" * 40) -BaseRef "main"
$twice = Read-HordeMergeOwedEntries -Text ($dup + "`n" + $dup + "`n")
Check ($twice.entries.Count -eq 1 -and $twice.bad.Count -eq 0) "a merge queued twice (a hand re-add) is one entry"
Check ((Test-HordeMergeOwedRepo -Repo "o/..") -eq $false -and (Test-HordeMergeOwedRepo -Repo "o/.") -eq $false -and (Test-HordeMergeOwedRepo -Repo "o/r") -eq $true) "a queued repo of '.' or '..' is no repo"

Write-Host "== S8: the walk, pinned"
# A guard red at the tip in 5.1 only, while an earlier merge was red in 7 only (and fixed): the later one is the cause.
$h = New-HandCase -Steps @(@{ f = @{ "guard.txt" = "red-in-7" }; by = "A" }, @{ f = @{ "guard.txt" = "red-in-51" }; by = "B" })
$run = Invoke-OwedRun -Case $h.c
Check ($run.exit -eq 1 -and (Said ("RED test\test-host-names.ps1 in Windows PowerShell 5.1: first red at the merge of YedPool/horde#101 (task T-0247, by B, mergeSha " + $h.shas[1] + ")*")) -and -not (Said "*merge of YedPool/horde#100*")) ("tip red in 5.1, an earlier merge red in 7 only: the walk looks at 5.1 alone and names the 5.1 culprit (exit " + $run.exit + ")")
# Red, fixed, red again: the walk names the FIRST red merge (linear, never bisecting: a red can be fixed again).
$h = New-HandCase -Steps @(@{ f = @{ "guard.txt" = "specs-red" }; by = "A" }, @{ f = @{ "guard.txt" = "green" }; by = "B" }, @{ f = @{ "guard.txt" = "specs-red" }; by = "C" })
$run = Invoke-OwedRun -Case $h.c
Check ($run.exit -eq 1 -and (Said ("RED test\test-mutation-specs.ps1 in *: first red at the merge of YedPool/horde#100 (task T-0247, by A, mergeSha " + $h.shas[0] + ")*"))) "red, fixed, red again: the first red merge is named (pinned: the walk is linear)"
# Green at every queued merge and red at the tip: something unqueued broke it.
$h = New-HandCase -Steps @(@{ f = @{ "one.txt" = "1" }; by = "F" }, @{ f = @{ "two.txt" = "2" }; by = "K" }) -Unqueued @(@{ f = @{ "guard.txt" = "specs-red" } })
$run = Invoke-OwedRun -Case $h.c
Check ($run.exit -eq 1 -and (Said "RED test\test-mutation-specs.ps1 in *: green at every queued merge and red at the tip *: it broke after the last queued merge*no merge is named") -and $null -eq (ConvertFrom-HordeJson -Text $run.json).repos[0].reds[0].merge) ("green at every queued merge, red at the tip: a note, no merge named (exit " + $run.exit + ")")
# A partly checked queue: the baseline is the first UNCHECKED entry's first parent.
$h = New-HandCase -Steps @(@{ f = @{ "one.txt" = "1" }; by = "F" }, @{ f = @{ "guard.txt" = "specs-red" }; by = "K" }, @{ f = @{ "two.txt" = "2" }; by = "C" })
$null = Add-HordeMergeLine -Path (Join-Path $h.c.owed "guards-checked.jsonl") -Line (ConvertTo-Json -InputObject ([ordered]@{ repo = "yedpool/horde"; mergeSha = $h.shas[0]; at = "2026-10-22T20:00:00Z"; result = "green" }) -Compress)
$run = Invoke-OwedRun -Case $h.c
$gr = @($script:guardRuns)
Check ($run.exit -eq 1 -and (Said ("*first red at the merge of YedPool/horde#101 (task T-0247, by K, mergeSha " + $h.shas[1] + ")*")) -and $gr.Count -gt 6 -and $gr[6].commit -ceq $h.shas[0] -and (ConvertFrom-HordeJson -Text $run.json).repos[0].merges -eq 2) ("a partly checked queue: the baseline is the checked merge before the first unchecked one (exit " + $run.exit + ")")
# Two repositories in one queue: grouped, reported apart, and -Repo takes one.
$h = New-HandCase -Steps @(@{ f = @{ "one.txt" = "1" }; by = "F" }, @{ f = @{ "two.txt" = "2" }; by = "K"; repo = "Other/Thing" }, @{ f = @{ "three.txt" = "3" }; by = "C" })
$run = Invoke-OwedRun -Case $h.c -Repo "OTHER/thing"
$sum = ConvertFrom-HordeJson -Text $run.json
Check ($run.exit -eq 0 -and @($sum.repos).Count -eq 1 -and $sum.repos[0].repo -ceq "other/thing" -and $sum.repos[0].merges -eq 1 -and @(Read-CheckedLines $h.c).Count -eq 1) "-Repo of one of two repositories in the queue runs only that one, whatever the case"
$run = Invoke-OwedRun -Case $h.c
$sum = ConvertFrom-HordeJson -Text $run.json
Check ($run.exit -eq 0 -and @($sum.repos).Count -eq 1 -and $sum.repos[0].repo -ceq "yedpool/horde" -and $sum.repos[0].merges -eq 2 -and @(Read-CheckedLines $h.c).Count -eq 3) "  and the run without it takes what is left: the other repository's two merges"
$report = [System.IO.File]::ReadAllText((Join-Path $h.c.owed "nightly\2026-10-23-yedpool-horde.txt"))
Check ($report -clike ("*queue: " + (Join-Path $h.c.owed "guards-owed.jsonl") + " on " + [Environment]::MachineName + " - this machine*queue only*")) "S4: the report names the machine and the queue it covered, and says other machines have their own"

Write-Host "== T-0347: two writers meet, and a writer meets the nightly run's read"
$busy = Join-Path $work "busy\q.jsonl"
[void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $busy))
[System.IO.File]::WriteAllText($busy, "{""x"":1}`n", $utf8)
$script:hold = New-Object System.IO.FileStream($busy, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
$script:slept = 0
$releaseOnSecond = { param([int]$Ms) $script:slept++; if ($script:slept -eq 2 -and $null -ne $script:hold) { $script:hold.Dispose(); $script:hold = $null } }
try {
    $busyRun = Add-HordeMergeLine -Path $busy -Line "{""x"":2}" -Sleep $releaseOnSecond -DelayMs 1
    Check ($busyRun.ok -eq $true -and $script:slept -eq 2 -and [System.IO.File]::ReadAllText($busy) -ceq "{""x"":1}`n{""x"":2}`n") ("a line meeting another writer waits and lands once the other lets go (" + $script:slept + " waits)")
    $script:hold = New-Object System.IO.FileStream($busy, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    $script:slept = 0
    $never = { param([int]$Ms) $script:slept++ }
    $stuck = Add-HordeMergeLine -Path $busy -Line "{""x"":3}" -Attempts 3 -Sleep $never -DelayMs 1
    Check ($stuck.ok -eq $false -and $stuck.detail -clike "could not append to *after 3 tries*" -and $script:slept -eq 2) ("a file that stays in use is still a loud failure, after a bounded number of tries: " + $stuck.detail)
    # THE NIGHTLY RUN'S READ must not shut a writer out, and a writer must not shut the read out.
    $c = New-Case
    Check ((Add-QueuedMerges $c @(,@("1", "F"))) -ceq "merged") "a PR is merged and queued"
    $script:hold.Dispose()
    $script:hold = New-Object System.IO.FileStream((Join-Path $c.owed "guards-owed.jsonl"), [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    $run = Invoke-OwedRun -Case $c
    Check ($run.exit -eq 0 -and (Said "all green over 1 merges") -and -not (Said "could not read *")) ("the nightly run reads the queue while a writer has it open (exit " + $run.exit + ")")
    $script:hold.Dispose(); $script:hold = $null
    $c = New-Case
    Check ((Add-QueuedMerges $c @(,@("1", "F"))) -ceq "merged") "a PR is merged and queued"
    $rd = [System.IO.File]::Open((Join-Path $c.owed "guards-owed.jsonl"), [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try { $late = Add-HordeMergeLine -Path (Join-Path $c.owed "guards-owed.jsonl") -Line "{}" -Attempts 2 -Sleep { param([int]$Ms) } } finally { $rd.Dispose() }
    Check ($late.ok -eq $false) "CONTROL: a reader that shuts writers out does make an append fail (the failure this retry is for)"
    $readerView = Read-HordeMergeFileText -Path (Join-Path $c.owed "guards-owed.jsonl")
    $wr = New-Object System.IO.FileStream((Join-Path $c.owed "guards-owed.jsonl"), [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
    try { $readerView2 = Read-HordeMergeFileText -Path (Join-Path $c.owed "guards-owed.jsonl") } finally { $wr.Dispose() }
    Check ($readerView -ceq $readerView2 -and $readerView -clike "*mergeSha*") "the queue's reader does not shut a writer out and is not shut out by one"
} finally { if ($null -ne $script:hold) { $script:hold.Dispose() } }

Write-Host "== T-0347: a branch that is gone, and a guard that hangs, read as could-not-run with the way out"
# A stacked PR's base branch deleted after its merge: the fetch of it fails in every run.
$h = New-HandCase -Steps @(@{ f = @{ "one.txt" = "1" }; by = "F" }, @{ f = @{ "two.txt" = "2" }; by = "K" }) -Base "stack"
$null = G $h.c.origin branch -D stack
$run = Invoke-OwedRun -Case $h.c
Check ($run.exit -eq 2 -and (Said "COULD NOT RUN on stack: fetching stack failed*") -and -not (Said "RED *")) ("a deleted base branch: exit 2, could not run, no red (exit " + $run.exit + ")")
Check ((Said ("STAYS OWED: YedPool/horde#100 (mergeSha " + $h.shas[0] + ") is tried again in every run. If it can never run*give it up by adding this line to *guards-checked.jsonl: {*" + $h.shas[0] + "*given-up*")) -and (Said ("STAYS OWED: YedPool/horde#101 (mergeSha " + $h.shas[1] + ")*"))) "  and it prints the way out for each owed merge, the line that gives it up"
$wayOut = @($script:said | Where-Object { $_ -clike "STAYS OWED: *#100 *" })[0]
$wayLine = $wayOut.Substring($wayOut.IndexOf(": {") + 2)
$wayOut2 = @($script:said | Where-Object { $_ -clike "STAYS OWED: *#101 *" })[0]
$wayLine2 = $wayOut2.Substring($wayOut2.IndexOf(": {") + 2)
Check ((ConvertFrom-HordeJson -Text $wayLine).mergeSha -ceq $h.shas[0] -and (ConvertFrom-HordeJson -Text $wayLine2).mergeSha -ceq $h.shas[1]) ("  each merge's line gives up that merge's own sha, not the first one's: " + $wayLine + " | " + $wayLine2)
Check (@(Read-CheckedLines $h.c).Count -eq 0) "  nothing was marked checked: the merges are not dropped"
$null = Add-HordeMergeLine -Path (Join-Path $h.c.owed "guards-checked.jsonl") -Line $wayLine
$run = Invoke-OwedRun -Case $h.c
Check ($run.exit -eq 2 -and (Said "COULD NOT RUN on stack*") -and -not (Said "STAYS OWED: *#100 *") -and (Said "STAYS OWED: *#101 *")) "  the printed line gives up exactly that merge and no other"
# A hung guard: the tool kills it and answers code -1. It is never a red and never a green.
$hung = { param($Checkout, $Suite, $Shell) return [pscustomobject]@{ code = -1; out = ""; err = "powershell.exe ran past 900 s and was stopped" } }
$h = New-HandCase -Steps @(@{ f = @{ "one.txt" = "1" }; by = "F" })
$run = Invoke-OwedRun -Case $h.c -GuardOverride $hung
Check ($run.exit -eq 2 -and (Said "COULD NOT RUN on main: the guard * could not be run in *ran past 900 s and was stopped*") -and -not (Said "RED *")) ("a hung guard reads as 'could not run', exit 2, never red (exit " + $run.exit + ")")
Check ((Said "1 merge(s) stay owed and will be tried again; a guard that cannot run or hangs reads as 'could not run' (exit 2 in every run until it runs), never as red or green") -and @(Read-CheckedLines $h.c).Count -eq 0 -and (ConvertFrom-HordeJson -Text $run.json).repos[0].status -ceq "error") "  and it says so plainly, marks nothing checked, and the JSON says error"

Write-Host "== T-0347: a red main stays red until a run finds it green"
. (Join-Path $root "core\NightlyNet.ps1")
function Get-NetState {
    # What tools/NightlyNet.ps1 records for the guards from the wrapper's exit: 0 green, 1 RED, anything else not run.
    param([int]$WrapExit)
    if ($WrapExit -eq 0) { return "green" } elseif ($WrapExit -eq 1) { return "RED" } else { return "could not run" }
}
function Get-WrapperAnswer {
    # The REAL tools/nightly/guards-wrap.ps1, with a stand-in horde that prints what -RunOwed -Json printed and exits as the
    # horde process does (0 for exit 0, else 1): the state word the net records for the night, at the seam.
    param($Case, $Run)
    $dir = Join-Path $Case.dir "wrap"
    [void][System.IO.Directory]::CreateDirectory($dir)
    [System.IO.File]::WriteAllText((Join-Path $dir "said.json"), $Run.json, $utf8)
    $procExit = $(if ($Run.exit -eq 0) { 0 } else { 1 })
    [System.IO.File]::WriteAllText((Join-Path $dir "horde.ps1"), ("[Console]::Out.WriteLine('stand-in horde'); [Console]::Out.WriteLine([System.IO.File]::ReadAllText((Join-Path `$PSScriptRoot 'said.json')).Trim()); exit " + $procExit), $utf8)
    $ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $o = @(& $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root "tools\nightly\guards-wrap.ps1") -Horde (Join-Path $dir "horde.ps1") -Repo "YedPool/horde")
    return [pscustomobject]@{ code = $LASTEXITCODE; state = (Get-NetState -WrapExit $LASTEXITCODE); last = ("" + $o[-1]) }
}
$c = New-Case
Check ((Add-QueuedMerges $c @(@("1", "F"), @("4", "K"))) -ceq "merged,merged") "two PRs are merged and queued, the second turning a guard red"
$shas = @(@(Read-OwedLines $c) | ForEach-Object { (ConvertFrom-HordeJson -Text $_).mergeSha })
$run = Invoke-OwedRun -Case $c
$redFile = Join-Path $c.owed "guards-red.json"
Check ($run.exit -eq 1 -and [System.IO.File]::Exists($redFile)) ("night 1: the red is reported, and recorded in guards-red.json (exit " + $run.exit + ")")
$w = Get-WrapperAnswer -Case $c -Run $run
Check ($w.code -eq 1 -and $w.state -ceq "RED" -and $w.last -ceq "guards-wrap: RED") ("  the net reads night 1 as RED: " + $w.last)

# NIGHT 2: nothing is owed, and main is still red. It must read red, and name the merge that first turned it red.
$run = Invoke-OwedRun -Case $c
$gr = @($script:guardRuns)
Check ($run.exit -eq 1 -and -not (Said "nothing is owed*")) ("night 2, nothing owed and main still red: exit 1, not 'nothing is owed' (exit " + $run.exit + ")")
Check (Said ("RED test\test-mutation-specs.ps1 in *: STILL RED since 2026-10-23T03:00:00Z: first red at the merge of YedPool/horde#4 (task T-0247, by K, mergeSha " + $shas[1] + ")*")) "  it says STILL RED and names the original merge"
Check ($gr.Count -eq 6 -and @($gr | ForEach-Object { $_.commit } | Select-Object -Unique).Count -eq 1) ("  it ran the guards at the tip only, no walk (" + $gr.Count + " runs)")
$sum = ConvertFrom-HordeJson -Text $run.json
Check ($sum.exit -eq 1 -and $sum.repos[0].status -ceq "red" -and $sum.repos[0].merges -eq 0 -and $sum.repos[0].reds[0].open -eq $true -and $sum.repos[0].reds[0].merge.pr -ceq "YedPool/horde#4" -and $sum.repos[0].reds[0].merge.mergeSha -ceq $shas[1]) ("  and the JSON: " + $run.json)
Check (@(Read-CheckedLines $c).Count -eq 2) "  nothing new is marked checked"
$w = Get-WrapperAnswer -Case $c -Run $run
Check ($w.code -eq 1 -and $w.state -ceq "RED") ("  the net reads night 2 as RED, not green: " + $w.last)
$report = [System.IO.File]::ReadAllText((Join-Path $c.owed "nightly\2026-10-23-yedpool-horde.txt"))
Check ($report -clike "*STILL RED since*YedPool/horde#4*") "  the report holds it too"

# A merge that cannot be walked (not in main's history) must not skip the re-run at the tip.
$bogus = '{"repo":"YedPool/horde","pr":"YedPool/horde#9","task":"T-0247","by":"F","at":"2026-10-22T10:00:00Z","headSha":"' + ("b" * 40) + '","mergeSha":"' + ("a" * 40) + '","firstParent":"' + ("c" * 40) + '"}'
$null = Add-HordeMergeLine -Path (Join-Path $c.owed "guards-owed.jsonl") -Line $bogus
$run = Invoke-OwedRun -Case $c
Check ($run.exit -eq 1 -and (Said "RED * STILL RED since*YedPool/horde#4*") -and -not (Said "GREEN AGAIN*")) ("an unwalkable queued merge does not hide the open red (exit " + $run.exit + ")")
$null = Add-HordeMergeLine -Path (Join-Path $c.owed "guards-checked.jsonl") -Line (ConvertTo-Json -InputObject ([ordered]@{ repo = "yedpool/horde"; mergeSha = ("a" * 40); at = "2026-10-23T03:00:00Z"; result = "given-up" }) -Compress)

# A RERUN THAT COULD NOT RUN leaves the red open and reads as not-run, never green.
$notRun7 = { param($Checkout, $Suite, $Shell) if ($Shell -ceq "7") { return [pscustomobject]@{ code = -1; out = ""; err = "PowerShell 7 is not at C:\nowhere\pwsh.exe; install the MSI" } }; return $null }
$run = Invoke-OwedRun -Case $c -GuardOverride $notRun7
Check ($run.exit -eq 2 -and (Said "COULD NOT RUN on main*") -and (Said "STILL OPEN: the red on main (since 2026-10-23T03:00:00Z) stays open*") -and [System.IO.File]::Exists($redFile)) ("a rerun that could not run: exit 2, and the red stays open (exit " + $run.exit + ")")
$w = Get-WrapperAnswer -Case $c -Run $run
Check ($w.code -eq 2 -and $w.state -ceq "could not run") ("  the net reads it as could not run: " + $w.last)

# THE RECORD CANNOT BE WRITTEN: nothing is marked checked, and the finding is still printed.
$c2 = New-Case
Check ((Add-QueuedMerges $c2 @(,@("4", "K"))) -ceq "merged") "another red PR is merged and queued"
[void][System.IO.Directory]::CreateDirectory((Join-Path $c2.owed "guards-red.json.tmp"))
$run = Invoke-OwedRun -Case $c2
Check ($run.exit -eq 1 -and (Said "COULD NOT RECORD THE OPEN RED: *no merge is marked checked*") -and @(Read-CheckedLines $c2).Count -eq 0 -and (ConvertFrom-HordeJson -Text $run.json).repos[0].status -ceq "error") ("a record that cannot be written marks nothing checked (exit " + $run.exit + ")")

# THE FIX LANDS: main is green again. The next run clears the red; the one after is a quiet night again.
$tipNow = G $c.origin rev-parse refs/heads/main
$null = G $seed fetch -q $c.origin "refs/heads/main"
$fixed = New-SeedCommit -From $tipNow -Files @{ "guard.txt" = "green" } -Message "the fix"
$null = G $seed push -q -f $c.origin ($fixed + ":refs/heads/main")
$run = Invoke-OwedRun -Case $c
Check ($run.exit -eq 0 -and (Said ("GREEN AGAIN: main was red since 2026-10-23T03:00:00Z (first red at the merge of YedPool/horde#4*mergeSha " + $shas[1] + ")*")) -and -not (Said "RED *")) ("night 3, main fixed: green, and it says the red is cleared (exit " + $run.exit + ")")
$w = Get-WrapperAnswer -Case $c -Run $run
Check ($w.code -eq 0 -and $w.state -ceq "green") ("  the net reads it as green: " + $w.last)
$run = Invoke-OwedRun -Case $c
Check ($run.exit -eq 0 -and (Said "nothing is owed: every queued merge has been checked") -and @($script:guardRuns).Count -eq 0) "night 4: a quiet night with no open red runs nothing and is green"
$w = Get-WrapperAnswer -Case $c -Run $run
Check ($w.code -eq 0 -and $w.state -ceq "green") "  and the net reads it as green"

# TWO GUARDS RED ON ONE BRANCH, EACH WITH ITS OWN SINCE AND MERGE (round 2): G1 (test-mutation-specs) red behind M1, G2
# (test-host-names) red behind M2 a night later, then G1 fixed. G2's later nights must name M2, not M1.
function Add-HandMerge {
    # One more merge on main of a hand case: a commit with -Files pushed onto main and its owed line. Returns the merge sha.
    param($Case, [hashtable]$Files, [string]$By, [int]$Number, [switch]$Unqueued)
    $tipNow = G $Case.origin rev-parse refs/heads/main
    $null = G $seed fetch -q $Case.origin "refs/heads/main"
    $sha = New-SeedCommit -From $tipNow -Files $Files -Message "hand merge"
    $null = G $seed push -q -f $Case.origin ($sha + ":refs/heads/main")
    if (-not $Unqueued) {
        $o = [ordered]@{ repo = "yedpool/horde"; baseRefName = "main"; pr = ("YedPool/horde#" + $Number); task = "T-0247"; by = $By; at = "2026-10-22T10:00:00Z"; headSha = $sha; mergeSha = $sha; firstParent = $tipNow }
        $null = Add-HordeMergeLine -Path (Join-Path $Case.owed "guards-owed.jsonl") -Line (ConvertTo-Json -InputObject $o -Compress)
    }
    return $sha
}
$g1 = "test\test-mutation-specs.ps1"
$g2 = "test\test-host-names.ps1"
$n1 = $nightly
$n2 = $nightly.AddDays(1)
$n3 = $nightly.AddDays(2)
$n4 = $nightly.AddDays(3)
$st1 = $n1.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
$st2 = $n2.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
$h = New-HandCase -Steps @(,@{ f = @{ "guard.txt" = "specs-red" }; by = "F" })
$m1 = $h.shas[0]
$run = Invoke-OwedRun -Case $h.c -Now $n1
Check ($run.exit -eq 1 -and (Said ("RED " + $g1 + " in *: first red at the merge of YedPool/horde#100*")) -and -not (Said ("RED " + $g2 + "*"))) ("per guard, night 1: G1 red behind M1 (exit " + $run.exit + ")")
$m2 = Add-HandMerge -Case $h.c -Files @{ "guard.txt" = "specs-red hostnames-red" } -By "K" -Number 200
$run = Invoke-OwedRun -Case $h.c -Now $n2
$rec = (ConvertFrom-HordeJson -Text ([System.IO.File]::ReadAllText((Join-Path $h.c.owed "guards-red.json")))).reds
$gs2 = @($rec[0].guards)
Check ($run.exit -eq 1 -and (Said ("RED " + $g2 + " in *: first red at the merge of YedPool/horde#200 (task T-0247, by K, mergeSha " + $m2 + ") on main; its owner fixes it first thing")) -and -not (Said ("RED " + $g2 + "*the red has been open since*"))) ("  night 2: G2 turns red behind M2 while G1 is red, and is not given the red's old date (" + @($script:said | Where-Object { $_ -clike ("RED " + $g2 + "*") })[0] + ")")
Check (@($rec).Count -eq 1 -and $gs2.Count -eq 2 -and @($gs2 | Where-Object { $_.guard -ceq $g1 -and $_.since -ceq $st1 -and $_.merge.mergeSha -ceq $m1 }).Count -eq 1 -and @($gs2 | Where-Object { $_.guard -ceq $g2 -and $_.since -ceq $st2 -and $_.merge.mergeSha -ceq $m2 }).Count -eq 1) ("  the record holds each guard's own since and merge: " + (($gs2 | ForEach-Object { $_.guard + "@" + $_.since }) -join ", "))
$sum = ConvertFrom-HordeJson -Text $run.json
$j2 = @($sum.repos[0].reds | Where-Object { $_.guard -ceq $g2 })[0]
Check ($j2.open -eq $false -and $j2.since -ceq $st2 -and $j2.merge.mergeSha -ceq $m2) "  and the JSON gives G2 its own since, and says it was not open before"
# NIGHT 3: G1 is fixed (a push outside the queue); G2 stays red.
$null = Add-HandMerge -Case $h.c -Files @{ "guard.txt" = "hostnames-red" } -By "F" -Number 300 -Unqueued
$run = Invoke-OwedRun -Case $h.c -Now $n3
$rec = (ConvertFrom-HordeJson -Text ([System.IO.File]::ReadAllText((Join-Path $h.c.owed "guards-red.json")))).reds
Check ($run.exit -eq 1 -and (Said ("RED " + $g2 + " in *: STILL RED since " + $st2 + ": first red at the merge of YedPool/horde#200 (task T-0247, by K, mergeSha " + $m2 + ")*")) -and -not (Said "*YedPool/horde#100*mergeSha*on main; its owner*")) ("night 3, G1 fixed: STILL RED names G2's own merge and date, not G1's (" + @($script:said | Where-Object { $_ -clike ("RED " + $g2 + "*") })[0] + ")")
Check ((Said ("GREEN AGAIN: " + $g1 + " on main was red since " + $st1 + " (first red at the merge of YedPool/horde#100*) and is green at the tip now; " + $g2 + " stays red there")) -and -not (Said ("GREEN AGAIN: main *"))) "  a guard that went green while another stays red gets its own line"
Check (@($rec).Count -eq 1 -and @($rec[0].guards).Count -eq 1 -and $rec[0].guards[0].guard -ceq $g2 -and $rec[0].guards[0].since -ceq $st2) "  and leaves the record; the branch stays open on G2 alone"
$sum = ConvertFrom-HordeJson -Text $run.json
Check ($sum.repos[0].reds[0].open -eq $true -and $sum.repos[0].reds[0].since -ceq $st2 -and $sum.repos[0].reds[0].merge.mergeSha -ceq $m2) "  and the JSON carries G2's own since and merge"
$w = Get-WrapperAnswer -Case $h.c -Run $run
Check ($w.code -eq 1 -and $w.state -ceq "RED") ("  the net still reads it as RED: " + $w.last)
# NIGHT 4: G2 fixed too: the branch clears.
$null = Add-HandMerge -Case $h.c -Files @{ "guard.txt" = "green" } -By "F" -Number 301 -Unqueued
$run = Invoke-OwedRun -Case $h.c -Now $n4
$rec = (ConvertFrom-HordeJson -Text ([System.IO.File]::ReadAllText((Join-Path $h.c.owed "guards-red.json")))).reds
Check ($run.exit -eq 0 -and (Said ("GREEN AGAIN: main was red since " + $st2 + "*") ) -and @($rec).Count -eq 0) ("night 4, nothing red: the branch clears and the run is green (exit " + $run.exit + ")")

# A RECORD THAT CANNOT BE READ IS NOT GREEN.
foreach ($junk in @("this is not json", "", "{""reds"":[{""repo"":""not a repo"",""base"":""main""}]}", "{""nope"":1}", "{""reds"":[{""repo"":""YedPool/horde"",""base"":""main"",""guards"":[""test\\a.ps1""]}]}", "{""reds"":[{""repo"":""YedPool/horde"",""base"":""main"",""guards"":[{""since"":""x""}]}]}")) {
    $c3 = New-Case
    [void][System.IO.Directory]::CreateDirectory($c3.owed)
    [System.IO.File]::WriteAllText((Join-Path $c3.owed "guards-red.json"), $junk, $utf8)
    $run = Invoke-OwedRun -Case $c3
    Check ($run.exit -eq 2 -and (Said "COULD NOT READ THE RECORD OF OPEN REDS: *is not green*") -and @($script:guardRuns).Count -eq 0) ("an unreadable open-red record (" + $(if ($junk -eq "") { "empty" } else { $junk.Substring(0, [Math]::Min(18, $junk.Length)) }) + ") is not green: exit 2, nothing run (exit " + $run.exit + ")")
}
$w = Get-WrapperAnswer -Case $c3 -Run $run
Check ($w.code -eq 2 -and $w.state -ceq "could not run") ("  and the net reads it as could not run: " + $w.last)

Write-Host "== T-0347: a merge begun and never queued is not lost"
function Read-IntentLines {
    param($Case)
    $f = Join-Path $Case.owed "guards-intent.jsonl"
    if (-not [System.IO.File]::Exists($f)) { return @() }
    return @(([System.IO.File]::ReadAllText($f) -split "\r?\n") | Where-Object { $_.Trim() -ne "" })
}
# The intent log's own lines.
$iReq = Test-HordeMergeRequest -Pr "YedPool/horde#7" -Task "T-0247" -State "done" -By "F" -Guards "later"
$iLine = Format-HordeMergeIntentLine -Request $iReq -HeadSha ("d" * 40) -BaseRef "main" -Now $nightly
$sLine = Format-HordeMergeIntentLine -Request $iReq -HeadSha ("d" * 40) -BaseRef "main" -Kind "settled" -How "queued" -Now $nightly
Check ($iLine -cmatch '\A[\x20-\x7E]+\z' -and (Read-HordeMergeOpenIntents -Text ($iLine + "`n")).open.Count -eq 1 -and (Read-HordeMergeOpenIntents -Text ($iLine + "`n" + $sLine + "`n")).open.Count -eq 0) "an intent line is plain ASCII, open until a settled line for the same PR and head follows"
Check ((Read-HordeMergeOpenIntents -Text ($iLine + "`n" + $sLine + "`n" + $iLine + "`nnot json`n")).open.Count -eq 1 -and (Read-HordeMergeOpenIntents -Text ($iLine + "`nnot json`n")).bad -eq 1) "  a later intent opens it again, and a damaged line is counted, never taken for an intent"

# A DAYTIME MERGE WRITES ITS INTENT FIRST AND SETTLES IT AFTER ITS QUEUE LINE.
$c = New-Case
$r = Invoke-Case -Case $c -Guards later
$il = @(Read-IntentLines $c)
Check ($r.outcome -ceq "merged" -and $il.Count -eq 2 -and $il[0] -clike '{"kind":"intent",*' -and $il[1] -clike '{"kind":"settled",*"how":"queued"*' -and (Read-HordeMergeOpenIntents -Text ([string]::Join("`n", $il))).open.Count -eq 0) ("later: an intent line before the merge, a settled line after the queue line: " + ($il -join " | "))
$before = @(Get-GhCalls $c).Count
$run = Invoke-OwedRun -Case $c
Check ($run.exit -eq 0 -and @(Get-GhCalls $c | Select-Object -Skip $before | Where-Object { $_ -clike "pr view*" }).Count -eq 0) "  and a settled intent costs the nightly run no question to GitHub"

# THE INTENT CANNOT BE WRITTEN: nothing is merged.
$c = New-Case
$r = Invoke-Case -Case $c -Guards later -IntentFails
Check ($r.outcome -ceq "refused" -and $r.why -clike "the intent to merge could not be written, so nothing was merged: *" -and -not (Test-MergeCall $c)) ("later: an intent that cannot be written refuses the merge (" + $r.outcome + ")")

# THE QUEUE LINE IS LOST AFTER THE MERGE: the intent stays open, and the nightly run queues the merge.
$c = New-Case
$r = Invoke-Case -Case $c -Guards later -OwedFails
$main = Get-Main $c
Check ($r.outcome -ceq "merged-unfinished" -and @(Read-OwedLines $c).Count -eq 0 -and @(Read-IntentLines $c).Count -eq 1) "a merge whose queue line was lost: queued nowhere, its intent still open"
$run = Invoke-OwedRun -Case $c
$ow = @(Read-OwedLines $c)
Check ($run.exit -eq 0 -and (Said ("recovered YedPool/horde#1: it was merged as " + $main + " and never queued*")) -and $ow.Count -eq 1 -and (ConvertFrom-HordeJson -Text $ow[0]).mergeSha -ceq $main -and (ConvertFrom-HordeJson -Text $ow[0]).task -ceq "T-0247" -and (ConvertFrom-HordeJson -Text $ow[0]).baseRefName -ceq "main" -and (Said "all green over 1 merges")) ("the nightly run queues it from GitHub's word, and checks it (exit " + $run.exit + ")")
Check ((Read-HordeMergeOpenIntents -Text ([System.IO.File]::ReadAllText((Join-Path $c.owed "guards-intent.jsonl")))).open.Count -eq 0) "  and settles the intent"
$run = Invoke-OwedRun -Case $c
Check ($run.exit -eq 0 -and (Said "nothing is owed*") -and @(Read-OwedLines $c).Count -eq 1) "  and the next run finds nothing more to recover"

# THE MERGED-UNFINISHED RETURN (gh said merged, GitHub did not show it) queued nothing: the intent covers it too.
$c = New-Case -Pr @{ "1" = @{ hideMerged = $true } }
$r = Invoke-Case -Case $c -Guards later
Check ($r.outcome -ceq "merged-unfinished" -and $r.why -clike "*the intent to merge stays recorded*" -and @(Read-OwedLines $c).Count -eq 0 -and @(Read-IntentLines $c).Count -eq 1) ("a merge GitHub does not yet show: merged-unfinished, nothing queued, the intent kept (" + $r.outcome + ")")
$run = Invoke-OwedRun -Case $c
Check ($run.exit -eq 0 -and @(Read-OwedLines $c).Count -eq 0 -and @(Read-IntentLines $c).Count -eq 1) "  a young intent whose PR is not merged is left alone (it may still be in flight)"
$gst = Read-MergeStandInState -Path $c.gh
$gst.prs."1".hideMerged = $false
Write-MergeStandInState -Path $c.gh -State $gst
$main = Get-Main $c
$run = Invoke-OwedRun -Case $c
Check ($run.exit -eq 0 -and @(Read-OwedLines $c).Count -eq 1 -and (ConvertFrom-HordeJson -Text @(Read-OwedLines $c)[0]).mergeSha -ceq $main) "  once GitHub shows it MERGED, the nightly run queues it"

# AN OLD INTENT WHOSE PR WAS NEVER MERGED is settled, not asked about for ever.
$c = New-Case
$old = Format-HordeMergeIntentLine -Request (Test-HordeMergeRequest -Pr "YedPool/horde#2" -Task "T-0247" -State "done" -By "F" -Guards "later") -HeadSha $heads["2"] -BaseRef "main" -Now ([datetime]::new(2026, 10, 1, 0, 0, 0, [System.DateTimeKind]::Utc))
[void][System.IO.Directory]::CreateDirectory($c.owed)
$null = Add-HordeMergeLine -Path (Join-Path $c.owed "guards-intent.jsonl") -Line $old
$run = Invoke-OwedRun -Case $c
Check ($run.exit -eq 0 -and @(Read-OwedLines $c).Count -eq 0 -and (Read-HordeMergeOpenIntents -Text ([System.IO.File]::ReadAllText((Join-Path $c.owed "guards-intent.jsonl")))).open.Count -eq 0 -and (@(Read-IntentLines $c)[-1]) -clike '*"how":"not-merged"*') "an old intent whose PR is still open is settled as not merged"

# AN UNKNOWN MERGE IS NOT SETTLED AS NOT MERGED (round 2): only GitHub's own word settles it.
function Get-IntentHows { param($Case) return @(Read-IntentLines $Case | Where-Object { $_ -clike '{"kind":"settled"*' }) }
# a. gh refuses the merge and the view right after fails too.
$c = New-Case -Pr @{ "1" = @{ failMerge = $true } }
$script:mergeSeen = $false
$r = Invoke-Case -Case $c -Guards later -GhWrap {
    param($a)
    $j = @($a) -join " "
    if ($j -clike "pr merge*") { $script:mergeSeen = $true }
    if ($script:mergeSeen -and $j -clike "pr view*") { return [pscustomobject]@{ code = 1; out = ""; err = "gh: connection reset" } }
    return (& $script:innerGh $a)
}
Check ($r.outcome -ceq "refused" -and $r.why -clike "*GitHub's answer is unknown*nightly run will ask*" -and @(Get-IntentHows $c).Count -eq 0 -and (Read-HordeMergeOpenIntents -Text ([System.IO.File]::ReadAllText((Join-Path $c.owed "guards-intent.jsonl")))).open.Count -eq 1) ("a refused merge whose view also failed: the intent stays open, the refusal says GitHub's answer is unknown (" + $r.why + ")")
# b. gh timed out (code -1) and the view says OPEN.
$c = New-Case
$r = Invoke-Case -Case $c -Guards later -GhWrap {
    param($a)
    $j = @($a) -join " "
    if ($j -clike "pr merge*") { return [pscustomobject]@{ code = -1; out = ""; err = "gh ran past 120 s and was stopped" } }
    return (& $script:innerGh $a)
}
Check ($r.outcome -ceq "refused" -and $r.why -clike "*GitHub's answer is unknown*" -and @(Get-IntentHows $c).Count -eq 0 -and (Read-HordeMergeOpenIntents -Text ([System.IO.File]::ReadAllText((Join-Path $c.owed "guards-intent.jsonl")))).open.Count -eq 1) ("a timed-out merge whose view says OPEN: the intent stays open (" + $r.why + ")")
# c. a plain refusal, GitHub answering OPEN: settled as not merged, as before.
$c = New-Case -Pr @{ "1" = @{ failMerge = $true } }
$r = Invoke-Case -Case $c -Guards later
Check ($r.outcome -ceq "refused" -and $r.why -cnotlike "*unknown*" -and @(Get-IntentHows $c).Count -eq 1 -and (@(Get-IntentHows $c)[0]) -clike '*"how":"not-merged"*' -and (Read-HordeMergeOpenIntents -Text ([System.IO.File]::ReadAllText((Join-Path $c.owed "guards-intent.jsonl")))).open.Count -eq 0) ("a plain refused merge settles the intent as not merged (" + $r.why + ")")

# THE SAME MERGE QUEUED TWICE (the nightly run recovers a merge that is between "merged" and its own queue write, and
# then the merge queues itself): the reader keeps the first line, so the merge is walked and marked checked once.
$c = New-Case
$r = Invoke-Case -Case $c -Guards later
$own = @(Read-OwedLines $c)[0]
$recovered = ConvertFrom-HordeJson -Text $own
$recovered.firstParent = ""
$recovered.at = "2026-10-22T09:00:00Z"
$null = Add-HordeMergeLine -Path (Join-Path $c.owed "guards-owed.jsonl") -Line (ConvertTo-Json -InputObject $recovered -Compress)
Check (@(Read-OwedLines $c).Count -eq 2 -and (Read-HordeMergeOwedEntries -Text ([System.IO.File]::ReadAllText((Join-Path $c.owed "guards-owed.jsonl")))).entries.Count -eq 1) "CONTROL: the queue holds the same mergeSha twice, and reads as one entry"
$run = Invoke-OwedRun -Case $c
Check ($run.exit -eq 0 -and (Said "all green over 1 merges") -and @(Read-CheckedLines $c).Count -eq 1 -and @($script:guardRuns | Where-Object { $_.commit -ceq (Get-Main $c) }).Count -gt 0) ("  and the nightly run walks it once and marks it checked once (exit " + $run.exit + ")")

# GITHUB CANNOT BE ASKED: the intent stays, the run ends 2 (never 0), and the merge is not forgotten.
$c = New-Case
$null = Add-HordeMergeLine -Path (Join-Path $c.owed "guards-intent.jsonl") -Line (Format-HordeMergeIntentLine -Request (Test-HordeMergeRequest -Pr "YedPool/horde#99" -Task "T-0247" -State "done" -By "F" -Guards "later") -HeadSha ("e" * 40) -BaseRef "main" -Now ([datetime]::new(2026, 10, 1, 0, 0, 0, [System.DateTimeKind]::Utc)))
$run = Invoke-OwedRun -Case $c
Check ($run.exit -eq 2 -and (Said "COULD NOT ASK GITHUB whether YedPool/horde#99*asked again next run") -and (Read-HordeMergeOpenIntents -Text ([System.IO.File]::ReadAllText((Join-Path $c.owed "guards-intent.jsonl")))).open.Count -eq 1) ("an intent GitHub cannot answer for ends the run 2 and stays open (exit " + $run.exit + ")")

# PART 2: the real command, as its own process.
function New-CliCase {
    # A case, plus a Horde home in temp whose merge settings point gh and the ledger at the stand-ins.
    param([hashtable]$Pr = @{}, [switch]$NoLedgerScript, [string]$LedgerProgram = "")
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
    if ($LedgerProgram -ne "") { $values["ledgerProgram"] = $LedgerProgram }
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
    $run = Invoke-HordeCliProcess -Root $root -Shell $shell -HordeArgs @("merge", "YedPool/horde#1", "-Task", "T-0247", "-State", "done", "-By", "F", "-Guards", "now") -Env $env1
    $main = Get-Main $c
    Check ($run.code -eq 1 -and $run.out -clike ("*MERGED YedPool/horde#1 as " + $main + "*") -and $main -cne $c1) ("the happy path merges and says so (" + $run.code + ")")
    Check ($run.out -clike "*test\test-host-names.ps1 is green in Windows PowerShell 5.1*test\test-host-names.ps1 is green in PowerShell 7*test\test-mutation-specs.ps1 is green in Windows PowerShell 5.1*test\test-mutation-specs.ps1 is green in PowerShell 7*") "  the guards ran through the real guard runner in both shells and were read green"
    Check (@(Get-LedgerCalls $c)[-1] -ceq "merged T-0247 --pr YedPool/horde#1 --by F --state done") "  the ledger event was written through the settings' program"
    Check ($run.out -clike "*COULD NOT TELL THE WARCHIEF: this Horde home is under the temp folder, so it is a test's: nobody is told*" -and $run.out -clike "*MERGED, NOT FINISHED:*the warchief was not told*") "  a test's home tells the warchief nothing, and the command exits 1 saying so rather than pretend"
    $mailDir = Join-Path $c.home "analyst\mail"
    $mails = @(if ([System.IO.Directory]::Exists($mailDir)) { [System.IO.Directory]::GetFiles($mailDir, "*.txt") })
    Check ($mails.Count -eq 1 -and [System.IO.File]::ReadAllText($mails[0]) -clike ("HORDE MERGE: F merged YedPool/horde#1 as " + $main + "*")) "  the analyst's mail is left in the (test) home's analyst folder, as horde analyst mail leaves one"
    Check ($run.out -clike "*progress draft: F merged YedPool/horde#1 - PR 1 (T-0247, now done)*") "  the progress draft is printed"

    # NO -RunOwed WORK TO DO is a clean exit under both shells.
    $run = Invoke-HordeCliProcess -Root $root -Shell $shell -HordeArgs @("merge", "-RunOwed", "-Json") -Env $env1
    $jl = @(($run.out -split "\r?\n") | Where-Object { $_ -clike '{"exit":*' })
    Check ($run.code -eq 0 -and $run.out -clike "*nothing is owed*" -and $jl.Count -eq 1 -and $jl[0] -clike '{"exit":0,*') ("merge -RunOwed -Json with an empty queue: exit 0, a JSON summary line (" + $run.code + ")")
    $run = Invoke-HordeCliProcess -Root $root -Shell $shell -HordeArgs @("merge", "YedPool/horde#1", "-RunOwed") -Env $env1
    Check ($run.code -eq 2 -and $run.out -clike "*merge -RunOwed takes only -Repo and -Json*") "-RunOwed with a pull request is a usage error, exit 2"
    $run = Invoke-HordeCliProcess -Root $root -Shell $shell -HordeArgs @("merge", "YedPool/horde#1", "-Task", "T-0247", "-State", "done", "-By", "F", "-Json") -Env $env1
    Check ($run.code -eq 2 -and $run.out -clike "*-Repo and -Json belong to merge -RunOwed*") "-Json without -RunOwed is a usage error, exit 2"
    $run = Invoke-HordeCliProcess -Root $root -Shell $shell -HordeArgs @("merge", "YedPool/horde#1", "-Task", "T-12", "-State", "done", "-By", "F", "-Guards", "now") -Env $env1
    Check ($run.code -eq 2 -and $run.out -clike "*'T-12' is not a task id*usage: horde merge*") "a malformed task id is a usage error, exit 2"
    if ($shell -ceq "pwsh.exe") { continue }

    # THE DEFAULT IS DAYTIME MODE, through the real command: PR 4's guard is red and it is merged anyway, queued; -RunOwed names it.
    $c = New-CliCase
    $run = Invoke-HordeCliProcess -Root $root -Shell $shell -HordeArgs @("merge", "YedPool/horde#4", "-Task", "T-0247", "-State", "done", "-By", "K") -Env @{ HORDE_HOME = $c.home }
    $main = Get-Main $c
    $queue = Join-Path $c.home "merge\guards-owed.jsonl"
    Check ($run.out -clike ("*MERGED YedPool/horde#4 as " + $main + "*") -and $run.out -clike "*guards not run: queued for the nightly run (guards-owed.jsonl)*" -and $run.out -cnotlike "*is green in*" -and [System.IO.File]::Exists($queue)) "the default merge runs no guard and queues itself in <HORDE_HOME>\merge\guards-owed.jsonl"
    Check ($run.code -eq 1 -and $run.out -clike "*MERGED, NOT FINISHED:*the warchief was not told*" -and $run.out -cnotlike "*NOT QUEUED*") ("  and ends 1 only for the warchief a test home cannot tell (" + $run.code + ")")
    # A QUEUE THAT CANNOT BE WRITTEN, through the real command: loud, the line to add by hand, exit 1.
    $cq = New-CliCase
    [void][System.IO.Directory]::CreateDirectory((Join-Path $cq.home "merge\guards-owed.jsonl"))
    $run = Invoke-HordeCliProcess -Root $root -Shell $shell -HordeArgs @("merge", "YedPool/horde#1", "-Task", "T-0247", "-State", "done", "-By", "F") -Env @{ HORDE_HOME = $cq.home }
    Check ($run.code -eq 1 -and $run.out -clike "*THE MERGE HAPPENED, BUT IT WAS NOT QUEUED FOR THE NIGHTLY GUARDS RUN*add this line to guards-owed.jsonl by hand: {*" -and $run.out -clike "*MERGED, NOT FINISHED:*not queued*" -and $run.out -cnotlike "*guards not run: queued*") ("a queue that cannot be written: exit 1, loud, the line to add (" + $run.code + ")")
    # T-0347: THE INTENT FOLDER IN THE WAY refuses the merge before it is made, since the queue is beside the intent.
    $ci = New-CliCase
    [System.IO.File]::WriteAllText((Join-Path $ci.home "merge"), "in the way", $utf8)
    $run = Invoke-HordeCliProcess -Root $root -Shell $shell -HordeArgs @("merge", "YedPool/horde#1", "-Task", "T-0247", "-State", "done", "-By", "F") -Env @{ HORDE_HOME = $ci.home }
    Check ($run.code -eq 1 -and $run.out -clike "*refused, nothing merged: the intent to merge could not be written, so nothing was merged*" -and -not (Test-MergeCall $ci)) ("a merge folder that cannot be written to refuses the merge before it is made (" + $run.code + ")")
    # S3: A DAYTIME MERGE TAKES NO MACHINE LOCK, so a long nightly run (or a -Guards now merge) never holds it up.
    $cl = New-CliCase
    $held = Get-HordeMergeLock -WorkFolder $cl.work
    $holding = $held.WaitOne(0)
    try { $run = Invoke-HordeCliProcess -Root $root -Shell $shell -HordeArgs @("merge", "YedPool/horde#1", "-Task", "T-0247", "-State", "done", "-By", "F") -Env @{ HORDE_HOME = $cl.home } }
    finally { if ($holding) { $held.ReleaseMutex() }; $held.Dispose() }
    Check ($holding -and $run.out -cnotlike "*another horde merge is running*" -and $run.out -clike ("*MERGED YedPool/horde#1 as " + (Get-Main $cl) + "*")) "a daytime merge does not wait for the merge lock another run holds"
    $run = Invoke-HordeCliProcess -Root $root -Shell $shell -HordeArgs @("merge", "-RunOwed", "-Json") -Env @{ HORDE_HOME = $c.home }
    $jl = @(($run.out -split "\r?\n") | Where-Object { $_ -clike '{"exit":*' })
    Check ($run.code -eq 1 -and $run.out -clike ("*RED test\test-mutation-specs.ps1 in *first red at the merge of YedPool/horde#4 (task T-0247, by K, mergeSha " + $main + ")*") -and $jl.Count -eq 1 -and $jl[0] -clike '{"exit":1,*') ("merge -RunOwed through the real runner names the merge and exits 1 (" + $run.code + ")")
    Check (@([System.IO.Directory]::GetFiles((Join-Path $c.home "merge\nightly"), "*.txt")).Count -eq 1 -and [System.IO.File]::Exists((Join-Path $c.home "merge\guards-checked.jsonl"))) "  the report and the checked mark are in <HORDE_HOME>\merge"
    $c = New-CliCase -Pr @{ "1" = @{ state = "CLOSED" } }
    $run = Invoke-HordeCliProcess -Root $root -Shell $shell -HordeArgs @("merge", "YedPool/horde#1", "-Task", "T-0247", "-State", "done", "-By", "F", "-Guards", "now") -Env @{ HORDE_HOME = $c.home }
    Check ($run.code -eq 1 -and $run.out -clike "*refused, nothing merged: YedPool/horde#1 is not open: GitHub says CLOSED*" -and -not (Test-MergeCall $c)) "a closed PR: exit 1, refused, no merge asked"
    $c = New-CliCase
    $run = Invoke-HordeCliProcess -Root $root -Shell $shell -HordeArgs @("merge", "YedPool/horde#7", "-Task", "T-0247", "-State", "done", "-By", "F", "-Guards", "now") -Env @{ HORDE_HOME = $c.home }
    Check ($run.code -eq 1 -and $run.out -clike "*[[]FAIL] stand-in: a file names a port*refused, nothing merged: the guard test\test-host-names.ps1 is red*" -and -not (Test-MergeCall $c)) "a red guard through the real runner: exit 1, its failing line printed, no merge asked"
    $c = New-CliCase -NoLedgerScript
    $run = Invoke-HordeCliProcess -Root $root -Shell $shell -HordeArgs @("merge", "YedPool/horde#1", "-Task", "T-0247", "-State", "done", "-By", "F", "-Guards", "now") -Env @{ HORDE_HOME = $c.home }
    Check ($run.code -eq 1 -and $run.out -clike "*name no ledgerScript*nothing was merged*" -and @(Get-GhCalls $c).Count -eq 0) "no ledger script in the settings: exit 1 before GitHub is asked anything"
    $run = Invoke-HordeCliProcess -Root $root -Shell $shell -HordeArgs @("merge", "YedPool/horde#1", "-Task", "T-0247", "-State", "waiting", "-By", "F") -Env @{ HORDE_HOME = $c.home }
    Check ($run.code -eq 2 -and $run.out -clike "*-State waiting needs -On*") "waiting without -On is a usage error, exit 2"
    $run = Invoke-HordeCliProcess -Root $root -Shell $shell -HordeArgs @("merge", "YedPool/horde#1", "-Task", "T-0247", "-State", "done") -Env @{ HORDE_HOME = $c.home }
    Check ($run.code -eq 2 -and $run.out -clike "*merge needs -By*") "no -By is a usage error that names it, exit 2"

    $c = New-CliCase -LedgerProgram "C:\fleet\task.cmd"
    $run = Invoke-HordeCliProcess -Root $root -Shell $shell -HordeArgs @("merge", "YedPool/horde#1", "-Task", "T-0247", "-State", "done", "-By", "F", "-Guards", "now") -Env @{ HORDE_HOME = $c.home }
    Check ($run.code -eq 1 -and $run.out -clike "*the merge setting ledgerProgram names a .cmd or .bat*Nothing was merged*" -and @(Get-GhCalls $c).Count -eq 0) "a .cmd ledger program in the settings: exit 1 before GitHub is asked anything"

    # TWO MERGES TAKE TURNS: this suite holds the machine's merge lock for the case's work folder; the
    # command must say it waits, merge nothing while it waits, and go on once the lock is let go.
    $c = New-CliCase
    $held = Get-HordeMergeLock -WorkFolder $c.work
    $holding = $held.WaitOne(0)
    $live = Start-HordeCliRun -Root $root -HordeArgs @("merge", "YedPool/horde#1", "-Task", "T-0247", "-State", "done", "-By", "F", "-Guards", "now") -Env @{ HORDE_HOME = $c.home }
    try {
        $waitLine = Wait-HordeCliLine -Run $live -Like "*another horde merge is running on this machine; waiting*" -Seconds 90
        Start-Sleep -Seconds 3
        $mergedWhileHeld = Test-MergeCall $c
        $ledgerWhileHeld = @(Get-LedgerCalls $c).Count
    } finally { if ($holding) { $held.ReleaseMutex() }; $held.Dispose() }
    $done = Complete-HordeCliRun -Run $live -Seconds 180
    Check ($holding -and $null -ne $waitLine -and -not $mergedWhileHeld -and $ledgerWhileHeld -eq 0) "a second merge waits for the lock, says so, and touches nothing while it waits"
    Check ($done.out -clike ("*MERGED YedPool/horde#1 as " + (Get-Main $c) + "*")) "  and merges once the first lets go"
}

try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop } catch { Write-Host ("  (the suite's temp folder stays: " + $work + ")") }
Complete-HordeSuite -Success "horde merge merges only green merge results, with a merge commit, and never pretends after it; daytime merges queue their guards for the nightly run, which names the merge that broke one"
