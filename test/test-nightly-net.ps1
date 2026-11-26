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
Write-Host "--- T-0397: the schedule is wall-clock time, a boundary with no offset ---" -ForegroundColor Cyan
$bd = Get-HordeNightlyTaskBoundary -Date ([datetime]"2026-11-04") -Hour 22
Check ($bd -ceq "2026-11-04T22:00:00") ("the boundary reads 22:00:00 (" + $bd + ")")
Check ($bd -notmatch '[Zz]$' -and $bd -notmatch '[+-]\d\d:\d\d$') "and carries no offset and no Z"
Check ((Get-HordeNightlyTaskBoundary -Date ([datetime]"2026-11-04 15:45") -Hour 22) -ceq "2026-11-04T22:00:00") "a date with a time of day still gives 22:00:00"

Write-Host ""
Write-Host "--- T-0397: a night is labelled by the date it began, one function for the net and the watcher ---" -ForegroundColor Cyan
function Label { param([string]$T) return (Get-HordeNightlyNightLabel -Time ([datetime]$T)) }
Check ((Label "2026-11-04 21:59") -ceq "2026-11-04") "21:59 is still the day's own label (the night has not begun; a refused start is named by that day)"
Check ((Label "2026-11-04 22:00") -ceq "2026-11-04") "22:00 begins night 11-04"
Check ((Label "2026-11-04 23:59") -ceq "2026-11-04") "23:59 is night 11-04"
Check ((Label "2026-11-05 00:00") -ceq "2026-11-04") "00:00 is still night 11-04, not 11-05"
Check ((Label "2026-11-05 01:00") -ceq "2026-11-04") "01:00 is night 11-04"
Check ((Label "2026-11-05 06:29") -ceq "2026-11-04") "06:29 is the last minute of night 11-04"
Check ((Label "2026-11-05 06:30") -ceq "2026-11-05") "06:30 is the next day's label"
Check ((Label "2026-11-01 00:30") -ceq "2026-10-31" -and (Label "2026-11-01 06:29") -ceq "2026-10-31" -and (Label "2026-11-01 06:30") -ceq "2026-11-01") "fall-back day 2026-11-01 (25 hours): labelled by the calendar"
Check ((Label "2027-03-14 01:00") -ceq "2027-03-13" -and (Label "2027-03-14 03:30") -ceq "2027-03-13" -and (Label "2027-03-14 06:29") -ceq "2027-03-13" -and (Label "2027-03-14 06:30") -ceq "2027-03-14") "spring-forward day 2027-03-14 (23 hours): labelled by the calendar"
foreach ($now in @("2026-11-04 07:15", "2026-11-02 07:15", "2027-03-15 07:15", "2026-11-04 05:00")) {
    $wn = Get-HordeNightlyWatchNight -Now ([datetime]$now)
    $ok = $true
    foreach ($t in @($wn.start, $wn.start.AddHours(1), $wn.start.Date.AddHours(23).AddMinutes(59), $wn.start.Date.AddDays(1), $wn.end.AddMinutes(-1))) { if ((Get-HordeNightlyNightLabel -Time $t) -cne $wn.date) { $ok = $false } }
    Check $ok ("the net's label and the watcher's night agree for every minute of the night the watcher judges at " + $now)
}
Check ((Get-HordeNightlyTaskBoundary -Date ([datetime]"2026-11-04")) -ceq "2026-11-04T22:00:00") "with no -Hour the boundary is 22:00:00 (the function's own default)"

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
    $shas = @(); if ($N -gt 0) { $shas = @(1..$N | ForEach-Object { "m" + $_ }) }
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
# T-0491: A GATE THAT RAN NOTHING (125 slot or memory, 128 not idle nor night) puts the unit back on the queue; nothing else does.
foreach ($c in @(125, 128)) { Check (Test-HordeNightlySlotLost ([pscustomobject]@{ code = $c; timedOut = $false })) ("T-0491: exit " + $c + " ran nothing, so the unit is tried again") }
foreach ($c in @(0, 1, 3, 71, 124, 126, 127)) { Check (-not (Test-HordeNightlySlotLost ([pscustomobject]@{ code = $c; timedOut = $false }))) ("T-0491: exit " + $c + " is not tried again") }
Check (-not (Test-HordeNightlySlotLost ([pscustomobject]@{ code = 125; timedOut = $true }))) "T-0491: a run cut off by its time limit is not tried again"
Check (-not (Test-HordeNightlySlotLost ([pscustomobject]@{ code = $null; timedOut = $false }))) "T-0491: a run with no exit code is not tried again"
Check (-not (Test-HordeNightlySlotLost $null)) "T-0491: no run at all is not tried again"
# T-0465: RED AT LAST NIGHT'S TIP TOO names no merge. 2026-11-11: test-fleet-liveness went red because the box's
# sessions turned elevated, red at every commit; the bisect took last night's tip as green and named the first
# merge (PR 494). Last night's tip (-Base) is run again after the tip, and red there means no merge of the day did it.
$t8 = @(1..8 | ForEach-Object { "m" + $_ })
$script:asked = @()
$r = Find-HordeNightlyCulprit -Merges $t8 -IsRed { param($sha) $script:asked += $sha; return $true } -Base "m0"
Check ($r.state -ceq "base-red" -and $r.sha -ceq "" -and $r.runs -eq 2) ("T-0465: red at last night's tip too names no merge (" + $r.state + " " + $r.sha + " in " + $r.runs + ")")
Check (($script:asked -join ",") -ceq "m8,m0") ("T-0465: the tip is run first, then last night's tip (" + ($script:asked -join ",") + ")")
Check ("" + $r.between[0] -ceq "m0") "T-0465: and it says which tip was red"
$r = Find-HordeNightlyCulprit -Merges $t8 -IsRed { param($sha) if ($sha -ceq "m0") { return $null } return $true } -Base "m0"
Check ($r.state -ceq "inconclusive") ("T-0465: last night's tip that could not be run is inconclusive, no merge named (" + $r.state + ")")
$r = Find-HordeNightlyCulprit -Merges $t8 -IsRed { param($sha) return ($sha -cne "m0" -and [int]($sha.Substring(1)) -ge 3) } -Base "m0"
Check ($r.state -ceq "found" -and $r.sha -ceq "m3") ("T-0465: green at last night's tip, the bisect goes on and names the merge (" + $r.state + " " + $r.sha + ")")
$r = Find-HordeNightlyCulprit -Merges $t8 -IsRed { param($sha) return $false } -Base "m0"
Check ($r.state -ceq "flaky" -and $r.runs -eq 1) "T-0465: a tip that is not red is still flaky, last night's tip not run"
$r = Find-HordeNightlyCulprit -Merges $t8 -IsRed { param($sha) return $true } -Base "m0" -MaxRuns 1
Check ($r.state -ceq "capped") ("T-0465: a cap that leaves no run for last night's tip ends capped, never a merge named (" + $r.state + ")")
$r = Run-Bisect -N 16 -Break 7 -Max 2
Check ($r.state -ceq "capped") "the run cap stops it, saying so"

Write-Host ""
Write-Host "--- the guards answer: the -Json last line decides, a process exit of 2 is could-not-run ---" -ForegroundColor Cyan
$a = Get-HordeNightlyGuardsAnswer -ProcessExit 0 -Lines @("some guard output", '{"exit":0,"red":[]}')
Check ($a.code -eq 0 -and $a.state -ceq "green") "process 0, json exit 0: green"
$a = Get-HordeNightlyGuardsAnswer -ProcessExit 0 -Lines @('{"exit":0}', "")
Check ($a.code -eq 0) "trailing blank lines are skipped when finding the last line"
$a = Get-HordeNightlyGuardsAnswer -ProcessExit 1 -Lines @('{"exit":1,"red":["test-host-names"],"first":"22222222"}')
Check ($a.code -eq 1 -and $a.state -ceq "RED" -and $a.text -like "*test-host-names*") "process 1, json exit 1: red, with the line kept as text"
# A WALK THAT STOPPED AT ITS BUDGET (T-0347 round 3) reaches the notice even when the line is cut: two reds and a long report path push the stop note
# of the second red past character 700, so only the field near the front of the line can carry it.
$longPath = "C:\very\long\horde\home\merge\nightly\" + ("deep-folder-name\" * 12) + "2026-11-20-yedpool-horde.txt"
$stopNote = "the merge is named by the open record; this run: not walked past the merge of YedPool/horde#200: this guard's share of the walk's budget (8 of 16 guard runs) is used up (8 runs)"
$redOne = '{"kind":"red","guard":"test\\test-host-names.ps1","shells":["Windows PowerShell 5.1","PowerShell 7"],"merge":{"pr":"YedPool/horde#100","task":"T-0247","by":"F","mergeSha":"1111111111111111111111111111111111111111"},"note":"the merge is named by the open record, which holds this guard red since 2026-11-18T03:00:00Z","base":"main","walkStopped":"","open":true,"since":"2026-11-18T03:00:00Z"}'
$redTwo = '{"kind":"red","guard":"test\\test-mutation-specs.ps1","shells":["Windows PowerShell 5.1","PowerShell 7"],"merge":{"pr":"YedPool/horde#100","task":"T-0247","by":"F","mergeSha":"1111111111111111111111111111111111111111"},"note":"' + $stopNote + '","base":"main","walkStopped":"not walked past the merge of YedPool/horde#200","open":true,"since":"2026-11-18T03:00:00Z"}'
$stopLine = '{"exit":1,"walkStopped":1,"date":"2026-11-20","repos":[{"repo":"yedpool/horde","status":"red","merges":3,"checked":1,"skipped":[],"reds":[' + $redOne + ',' + $redTwo + '],"report":"' + $longPath.Replace("\", "\\") + '","why":""}]}'
$a = Get-HordeNightlyGuardsAnswer -ProcessExit 1 -Lines @("report lines", $stopLine)
Check ($stopLine.Length -gt 1200 -and $stopLine.IndexOf("not walked past") -gt 700) "the stop note of the second red lies past character 700 of the -Json line (index $($stopLine.IndexOf('not walked past')) of $($stopLine.Length))"
Check ($a.code -eq 1 -and $a.state -ceq "RED" -and $a.text -like "A GUARD WALK STOPPED AT ITS BUDGET in 1 red(s): the merge named may no longer be the cause*") "two reds and a long report path: the notice text still says the walk stopped, from the parsed field"
$a = Get-HordeNightlyGuardsAnswer -ProcessExit 1 -Lines @('{"exit":1,"walkStopped":0,"date":"2026-11-20","repos":[]}')
Check ($a.code -eq 1 -and $a.text -notlike "*WALK STOPPED*") "walkStopped 0: no word of a stop"
$a = Get-HordeNightlyGuardsAnswer -ProcessExit 1 -Lines @('{"exit":1,"walkStopped":"1","date":"2026-11-20"}')
Check ($a.code -eq 1 -and $a.text -notlike "*WALK STOPPED*") "a walkStopped that is not a number is not read as a stop"
# THROUGH THE REAL WRAPPER (round 4): the real tools\nightly\guards-wrap.ps1 under 5.1 with a stand-in horde that prints the two-red, long-path line above, and the net's own text
# builder on what the wrapper printed. In round 3 the prefix was only in the answer's .text, which the wrapper never printed, and the net keeps the
# last 10 lines cut to their last 700 characters, so the notice read as a plain red.
$wrapDir = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-wrapcheck-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
[void][System.IO.Directory]::CreateDirectory($wrapDir)
$wrapUtf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $wrapDir "said.json"), $stopLine, $wrapUtf8)
[System.IO.File]::WriteAllText((Join-Path $wrapDir "horde.ps1"), "[Console]::Out.WriteLine('stand-in horde'); [Console]::Out.WriteLine([System.IO.File]::ReadAllText((Join-Path `$PSScriptRoot 'said.json')).Trim()); exit 1", $wrapUtf8)
$wrapPs = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$wrapOut = @(& $wrapPs -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root "tools\nightly\guards-wrap.ps1") -Horde (Join-Path $wrapDir "horde.ps1") -Repo "YedPool/horde")
$wrapExit = $LASTEXITCODE
$wrapNotice = Get-HordeNightlyGuardsNoticeText -Output ($wrapOut -join "`n")
Check ($wrapExit -eq 1 -and ("" + $wrapOut[-1]) -ceq "guards-wrap: RED") ("the real wrapper still ends on its state line and exits 1 (" + $wrapExit + ")")
Check (@($wrapOut | Where-Object { ("" + $_) -clike "guards-wrap: A GUARD WALK STOPPED AT ITS BUDGET in 1 red(s): *" }).Count -eq 1) "the real wrapper prints the stop line as a line of its own"
Check ($wrapNotice -clike "*A GUARD WALK STOPPED AT ITS BUDGET in 1 red(s)*guards-wrap: RED" -and $wrapNotice.Length -le 700) ("the net's notice text keeps the stop line beside the state, though the -Json line is cut: " + $wrapNotice.Length + " characters")
[System.IO.File]::WriteAllText((Join-Path $wrapDir "said.json"), '{"exit":1,"walkStopped":0,"date":"2026-11-20","repos":[]}', $wrapUtf8)
$wrapOut2 = @(& $wrapPs -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root "tools\nightly\guards-wrap.ps1") -Horde (Join-Path $wrapDir "horde.ps1") -Repo "YedPool/horde")
Check (@($wrapOut2 | Where-Object { ("" + $_) -clike "*WALK STOPPED*" }).Count -eq 0) "no stop: the wrapper prints no stop line"
try { Remove-Item -LiteralPath $wrapDir -Recurse -Force -ErrorAction Stop } catch { }
$a = Get-HordeNightlyGuardsAnswer -ProcessExit 1 -Lines @('{"exit":2,"why":"no clone"}')
Check ($a.code -eq 2 -and $a.state -ceq "could not run") "process 1 and json exit 2: could not run (not red)"
$a = Get-HordeNightlyGuardsAnswer -ProcessExit 2 -Lines @('{"exit":0}')
Check ($a.code -eq 2 -and $a.state -ceq "could not run") "a process exit of 2 (a horde without the verb) is could not run, even beside a green-looking line"
$a = Get-HordeNightlyGuardsAnswer -ProcessExit 0 -Lines @()
Check ($a.code -eq 2) "no output at all: could not run, never green"
$a = Get-HordeNightlyGuardsAnswer -ProcessExit 0 -Lines @("all fine")
Check ($a.code -eq 2) "a last line that is not JSON: could not run"
$a = Get-HordeNightlyGuardsAnswer -ProcessExit 0 -Lines @('{"result":"ok"}')
Check ($a.code -eq 2) "JSON with no exit field: could not run"
$a = Get-HordeNightlyGuardsAnswer -ProcessExit 0 -Lines @('{"exit":"0"}')
Check ($a.code -eq 2) "an exit field that is text, not a number: could not run"
$a = Get-HordeNightlyGuardsAnswer -ProcessExit 0 -Lines @('{"exit":7}')
Check ($a.code -eq 2) "an exit field outside 0 to 2: could not run"
$a = Get-HordeNightlyGuardsAnswer -ProcessExit 3 -Lines @('{"exit":0}')
Check ($a.code -eq 2) "any process exit but 0 or 1: could not run"

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
Write-Host "--- follow-ups N1 to N4: the tell's exit, a timeout is unrun, a skip keeps a red, the headline says incomplete ---" -ForegroundColor Cyan
function Run-V { param([int]$Code, [bool]$TimedOut = $false) return (Get-HordeNightlyVerdict ([pscustomobject]@{ code = $Code; timedOut = $TimedOut })) }
Check ((Run-V 124) -ceq "unrun") "N2: gate exit 124 (a timeout) inside a bisect is unrun, never red"
# R3 (review of PR 380, finding 3): at the tip a timeout is a finding, HUNG, not unrun forever.
Check ((Get-HordeNightlyVerdict ([pscustomobject]@{ code = 124; timedOut = $false }) -AtTip) -ceq "hung") "R3: gate exit 124 at the tip is hung"
Check ((Get-HordeNightlyVerdict ([pscustomobject]@{ code = 124; timedOut = $true }) -AtTip) -ceq "unrun") "R3: a run the night itself cut off is still unrun at the tip"
Check ((Get-HordeNightlyVerdict ([pscustomobject]@{ code = 1; timedOut = $false }) -AtTip) -ceq "red" -and (Get-HordeNightlyVerdict ([pscustomobject]@{ code = 125; timedOut = $false }) -AtTip) -ceq "unrun") "R3: the other exits mean the same at the tip"
$hc = Compare-HordeNightlyVerdicts -Now @{ "h|ps51" = "hung"; "g|ps51" = "green" } -Last @{ "h|ps51" = "green"; "g|ps51" = "green" }
Check ((($hc.hung -join ",") -ceq "h|ps51") -and @($hc.newlyRed).Count -eq 0 -and @($hc.unrun).Count -eq 0) "R3: a hung unit is its own finding: not unrun, and not newly red (never bisected)"
Check ((Get-HordeNightlyStoredVerdict -Verdict "hung" -Previous "green") -ceq "hung") "R3: hung is stored"
$sh = Update-HordeNightlyState -State @{ lastTip = "old"; units = @{ "h|ps51" = "green" } } -Verdicts @{ "h|ps51" = "hung" } -Tip "new" -Complete $true -Told $true
Check ($sh.lastTip -ceq "new" -and $sh.units["h|ps51"] -ceq "hung") "R3: a night with a hung unit still moves the tip"
$hrow = [pscustomobject]@{ repo = "Y/h"; tip = "abcdef01"; lastTip = "01234567"; merges = @(); guards = [pscustomobject]@{ state = "green"; text = "" }; suiteCount = 2; unrunCount = 0
    compare = $hc; culprits = @(); notes = @(); incomplete = "" }
$hrep = New-HordeNightlyReport -Date "2026-10-22" -Repos @($hrow)
Check ($hrep -like "*HUNG h|ps51 ran past its time limit at the tip*") "R3: the report names the hung unit"
Check ((($hrep -split "`n")[0]) -like "*HUNG: 1 units ran past their time limit*") "R3: and the headline counts it"
Check ((Run-V 0) -ceq "green" -and (Run-V 3) -ceq "skip" -and (Run-V 126) -ceq "absent" -and (Run-V 1) -ceq "red" -and (Run-V 125) -ceq "unrun" -and (Run-V 0 $true) -ceq "unrun") "the other exits keep their meaning"
Check ((Get-HordeNightlyStoredVerdict -Verdict "skip" -Previous "red") -ceq "") "N3: a skip does not clear a stored red"
Check ((Get-HordeNightlyStoredVerdict -Verdict "skip" -Previous "green") -ceq "skip") "R1: a skip does NOT keep a stored green (it is stored as skip)"
# R1 (review of PR 380, finding 1): green on night 1, a skip on night 2 (the tip moves on), red on night 3. Night 3
# must not be newly red: the break may be in night 2's merges, and a bisect over night 3's alone names an innocent one.
$st = @{ "u|ps51" = "green" }
$k = Get-HordeNightlyStoredVerdict -Verdict "skip" -Previous $st["u|ps51"]; if ($k -ne "") { $st["u|ps51"] = $k }
$cmp3 = Compare-HordeNightlyVerdicts -Now @{ "u|ps51" = "red" } -Last $st
Check (@($cmp3.newlyRed).Count -eq 0 -and (($cmp3.newRed -join ",") -ceq "u|ps51")) "R1: green, skip, red is NOT newly red (red with no verdict last night, no merge named)"
$st = @{ "u|ps51" = "red" }
$k = Get-HordeNightlyStoredVerdict -Verdict "skip" -Previous $st["u|ps51"]; if ($k -ne "") { $st["u|ps51"] = $k }
$cmp3 = Compare-HordeNightlyVerdicts -Now @{ "u|ps51" = "red" } -Last $st
Check ((($cmp3.stillRed -join ",") -ceq "u|ps51")) "N3 kept: red, skip, red is still red"
Check ((Get-HordeNightlyStoredVerdict -Verdict "skip" -Previous "") -ceq "skip") "a skip with nothing stored is stored"
Check ((Get-HordeNightlyStoredVerdict -Verdict "red" -Previous "green") -ceq "red" -and (Get-HordeNightlyStoredVerdict -Verdict "green" -Previous "red") -ceq "green") "green and red replace"
Check ((Get-HordeNightlyStoredVerdict -Verdict "unrun" -Previous "red") -ceq "" -and (Get-HordeNightlyStoredVerdict -Verdict "absent" -Previous "red") -ceq "") "unrun and absent change nothing"
$okRow = [pscustomobject]@{ repo = "Y/h"; tip = "abcdef01"; lastTip = "01234567"; merges = @(); guards = [pscustomobject]@{ state = "green"; text = "" }; suiteCount = 5; unrunCount = 0
    compare = [pscustomobject]@{ newlyRed = @(); stillRed = @(); newRed = @(); fixed = @(); unrun = @() }; culprits = @(); notes = @(); incomplete = "" }
$h = (New-HordeNightlyReport -Date "2026-10-22" -Repos @($okRow)) -split "`n" | Select-Object -First 1
Check ($h -like "*0 newly red*COMPLETE.*" -and $h -notlike "*INCOMPLETE*") ("N4: a whole green night says COMPLETE (" + $h + ")")
$badRow = $okRow.PSObject.Copy(); $badRow.unrunCount = 7; $badRow.guards = [pscustomobject]@{ state = "could not run"; text = "" }; $badRow.incomplete = "the night ran out"
$h = (New-HordeNightlyReport -Date "2026-10-22" -Repos @($badRow)) -split "`n" | Select-Object -First 1
Check ($h -like "*INCOMPLETE*7 units not run*guards could not run*") ("N4: the headline itself says incomplete, units not run and guards could not run (" + $h + ")")
$g2 = $okRow.PSObject.Copy(); $g2.guards = [pscustomobject]@{ state = "not run (no slot or no night)"; text = "" }
$h = (New-HordeNightlyReport -Date "2026-10-22" -Repos @($g2)) -split "`n" | Select-Object -First 1
Check ($h -like "*INCOMPLETE*guards*") "N5: guards that did not run make the headline incomplete"
$g3 = $okRow.PSObject.Copy(); $g3.guards = [pscustomobject]@{ state = "RED"; text = "x" }
$h = (New-HordeNightlyReport -Date "2026-10-22" -Repos @($g3)) -split "`n" | Select-Object -First 1
Check ($h -like "*GUARDS RED*") "red guards are in the headline"
# N1: a tell that prints and then fails must be exit 3, and one that prints and succeeds 0.
$tdir = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-nightly-tell-" + [guid]::NewGuid().ToString("N"))
try {
    [void][System.IO.Directory]::CreateDirectory($tdir)
    $failCmd = Join-Path $tdir "tellfail.cmd"; $okCmd = Join-Path $tdir "tellok.cmd"
    [System.IO.File]::WriteAllText($failCmd, "@echo off`r`necho noisy output`r`nexit /b 5`r`n")
    [System.IO.File]::WriteAllText($okCmd, "@echo off`r`necho noisy output`r`nexit /b 0`r`n")
    $said = @()
    $r = Invoke-HordeNightlyTell -Program $failCmd -Target "M" -File (Join-Path $tdir "r.txt") -RetrySeconds 0 -Say { param($l) $script:said += $l }
    Check (@($r).Count -eq 1 -and $r -eq 3) ("N1: a failing tell that prints is exactly one value, 3 (" + (@($r) -join "/") + ")")
    Check (@($said | Where-Object { $_ -like "*failed with exit 5*" }).Count -gt 0) "and says so"
    $r = Invoke-HordeNightlyTell -Program $okCmd -Target "M" -File (Join-Path $tdir "r.txt") -Say { param($l) }
    Check (@($r).Count -eq 1 -and $r -eq 0) "N1: a tell that prints and succeeds is exactly 0"
    $r = Invoke-HordeNightlyTell -Program (Join-Path $tdir "nothere") -Target "M" -File "x" -Say { param($l) }
    Check ($r -eq 3) "a missing tell program is 3"
    Check ((Invoke-HordeNightlyTell -Program $failCmd -Target "M" -File "x" -NoTell) -eq 0) "-NoTell is 0"
    # R2 (review of PR 380, finding 2): 0 and 6 are told, 2 is unconfirmed and never resent, the rest are retried.
    function New-TellStub {
        # A tell program that counts its calls in calls.txt and answers the codes of -Codes in turn (the last one after).
        param([string]$Name, [int[]]$Codes)
        $d = Join-Path $tdir $Name; [void][System.IO.Directory]::CreateDirectory($d)
        $b = "@echo off`r`necho call>>`"%~dp0calls.txt`"`r`nset n=0`r`nfor /f `"usebackq delims=`" %%l in (`"%~dp0calls.txt`") do set /a n+=1`r`necho stub said mail id abc123`r`n"
        for ($i = 0; $i -lt $Codes.Count - 1; $i++) { $b += ("if %n%==" + ($i + 1) + " exit /b " + $Codes[$i] + "`r`n") }
        $b += ("exit /b " + $Codes[$Codes.Count - 1] + "`r`n")
        $f = Join-Path $d "tell.cmd"; [System.IO.File]::WriteAllText($f, $b); return $f
    }
    function Calls { param([string]$Stub) $c = Join-Path (Split-Path -Parent $Stub) "calls.txt"; if (-not (Test-Path -LiteralPath $c)) { return 0 }; return @(Get-Content -LiteralPath $c).Count }
    $s6 = New-TellStub "six" @(6)
    $r = Invoke-HordeNightlyTell -Program $s6 -Target "M" -File "x" -RetrySeconds 0 -Say { param($l) }
    Check ($r -eq 0 -and (Calls $s6) -eq 1) ("R2: exit 6 (posted to the mailbox) is told, sent once (" + $r + ", " + (Calls $s6) + " calls)")
    $s2 = New-TellStub "two" @(2)
    $r = Invoke-HordeNightlyTell -Program $s2 -Target "M" -File "x" -RetrySeconds 0 -Say { param($l) }
    Check ($r -eq 3 -and (Calls $s2) -eq 1) ("R2: exit 2 (unconfirmed) is not told and NOT resent (" + $r + ", " + (Calls $s2) + " calls)")
    $s33 = New-TellStub "busy-then-ok" @(3, 4, 0)
    $said = @()
    $r = Invoke-HordeNightlyTell -Program $s33 -Target "M" -File "x" -RetrySeconds 0 -Say { param($l) $script:said += $l }
    Check ($r -eq 0 -and (Calls $s33) -eq 3) ("R2: a tell that fails twice (3, then 4) is retried and told on the third try (" + $r + ", " + (Calls $s33) + " calls)")
    Check (@($said | Where-Object { $_ -like "tell: stub said mail id abc123*" }).Count -eq 3) "R5: the tell program's own output is kept in the log, every try"
    $s3 = New-TellStub "always-busy" @(3)
    $r = Invoke-HordeNightlyTell -Program $s3 -Target "M" -File "x" -Tries 3 -RetrySeconds 0 -Say { param($l) }
    Check ($r -eq 3 -and (Calls $s3) -eq 3) ("R2: a tell that never gets through gives up after 3 tries, not told (" + $r + ", " + (Calls $s3) + " calls)")
    # R4 (review of PR 380, finding 4): a program that hangs is ended at its time limit, by its PID.
    $hang = Join-Path $tdir "hang.cmd"
    [System.IO.File]::WriteAllText($hang, "@echo off`r`nping -n 60 127.0.0.1 >nul`r`nexit /b 0`r`n")
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $pr = Invoke-HordeNightlyProcess -FilePath $hang -TimeoutSeconds 2
    Check ($pr.timedOut -eq $true -and $null -eq $pr.code -and $clock.Elapsed.TotalSeconds -lt 30) ("R4: a process past its time limit is ended and says timed out (" + [int]$clock.Elapsed.TotalSeconds + " s)")
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $r = Invoke-HordeNightlyTell -Program $hang -Target "M" -File "x" -Tries 1 -TimeoutSeconds 2 -Say { param($l) }
    Check ($r -eq 3 -and $clock.Elapsed.TotalSeconds -lt 30) ("R4: a tell that hangs is not told, and does not hang the night (" + [int]$clock.Elapsed.TotalSeconds + " s)")
    $echo = Join-Path $tdir "echo args.cmd"
    [System.IO.File]::WriteAllText($echo, "@echo off`r`necho [%~1] [%~2] [%~3]`r`nexit /b 7`r`n")
    $pr = Invoke-HordeNightlyProcess -FilePath $echo -ArgumentList @("a b", "c", "C:\dir with space\f.txt") -TimeoutSeconds 30
    Check ($pr.code -eq 7 -and $pr.timedOut -eq $false -and (($pr.lines -join "|") -ceq "[a b] [c] [C:\dir with space\f.txt]")) ("R4: arguments with spaces arrive whole, and the exit code is read (" + ($pr.lines -join "|") + ", " + $pr.code + ")")
    Check ((Format-HordeNightlyArgument "plain") -ceq "plain" -and (Format-HordeNightlyArgument "") -ceq '""' -and (Format-HordeNightlyArgument 'a"b') -ceq '"a\"b"' -and (Format-HordeNightlyArgument "x y\") -ceq '"x y\\"') "R4: command-line quoting"
    Check ((Get-HordeNightlyTellOutcome $null) -ceq "retry" -and (Get-HordeNightlyTellOutcome 0) -ceq "told" -and (Get-HordeNightlyTellOutcome 6) -ceq "told" -and (Get-HordeNightlyTellOutcome 2) -ceq "unconfirmed" -and (Get-HordeNightlyTellOutcome 5) -ceq "retry") "R2: the tell outcomes"
} finally { Remove-Item -LiteralPath $tdir -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host "--- the coverage floor: a share of the units that ran, and guards ---" -ForegroundColor Cyan
function Cov { param([int]$Ran, [int]$Unrun, [string]$Guards = "green", [string]$Repo = "a/b") return [pscustomobject]@{ repo = $Repo; suiteCount = $Ran; unrunCount = $Unrun; guards = [pscustomobject]@{ state = $Guards; text = "" } } }
Check (@(Get-HordeNightlyCoverageFindings -Repos @(Cov 10 466) -FloorPercent 90)[0] -ceq "a/b ran 10 of 476 units (2 percent)") "the night of 11-05 is below it, in numbers"
Check (@(Get-HordeNightlyCoverageFindings -Repos @(Cov 0 0) -FloorPercent 90)[0] -ceq "a/b ran 0 of 0 units (0 percent)") "a repo with nothing to count ran nothing: below it"
Check (@(Get-HordeNightlyCoverageFindings -Repos @(Cov 396 54) -FloorPercent 90).Count -eq 1) "the night of 10-28, 88 percent, is below it"
Check (@(Get-HordeNightlyCoverageFindings -Repos @(Cov 90 10) -FloorPercent 90).Count -eq 0) "exactly 90 percent is not below it"
Check (@(Get-HordeNightlyCoverageFindings -Repos @(Cov 89 11) -FloorPercent 90).Count -eq 1) "89 percent is"
Check (@(Get-HordeNightlyCoverageFindings -Repos @(Cov 899 101) -FloorPercent 90).Count -eq 1) "and 89.9 percent is not rounded up to 90"
Check (@(Get-HordeNightlyCoverageFindings -Repos @(Cov 450 0) -FloorPercent 90).Count -eq 0) "a whole night is not"
Check (@(Get-HordeNightlyCoverageFindings -Repos @(Cov 450 0 "not run") -FloorPercent 90)[0] -ceq "a/b ran no guards") "a whole night with no guards run is below it"
Check (@(Get-HordeNightlyCoverageFindings -Repos @(Cov 450 0 "RED") -FloorPercent 90).Count -eq 0) "guards that ran red are a finding of their own, not thin coverage"
Check (@(Get-HordeNightlyCoverageFindings -Repos @(Cov 450 0 "no repo-wide guard list (flake8 critical is a unit below)") -FloorPercent 90).Count -eq 0) "a repo with no guard list owes none"
Check (@(Get-HordeNightlyCoverageFindings -Repos @(Cov 1 99) -FloorPercent 0).Count -eq 0) "-FloorPercent 0 finds nothing"
$zeroHead = Get-HordeNightlyHeadlineStatus -Repos @([pscustomobject]@{ repo = "a/b"; suiteCount = 0; unrunCount = 0; guards = [pscustomobject]@{ state = "green"; text = "" }; compare = [pscustomobject]@{}; incomplete = "" }) -CoverageFloorPercent 90
Check ($zeroHead -cnotmatch '\bCOMPLETE\.' -and $zeroHead -clike "BELOW THE COVERAGE FLOOR*INCOMPLETE: nothing ran*") ("a repo with nothing to run is never headed COMPLETE: the old net's alarm reads that word as cover (" + $zeroHead + ")")
$covHead = Get-HordeNightlyHeadlineStatus -Repos @([pscustomobject]@{ repo = "a/b"; suiteCount = 10; unrunCount = 466; guards = [pscustomobject]@{ state = "not run"; text = "" }; compare = [pscustomobject]@{}; incomplete = "" }) -CoverageFloorPercent 90
Check ($covHead -clike "BELOW THE COVERAGE FLOOR of 90 percent: a/b ran 10 of 476 units (2 percent), a/b ran no guards. INCOMPLETE: *") ("the headline leads with it, the rest still follows (" + $covHead + ")")

Write-Host ""
Write-Host "--- R5: a missing exit code, a skip in a bisect, the report reserve, an unnamed bisect in the headline ---" -ForegroundColor Cyan
Check ((Get-HordeNightlyVerdict ([pscustomobject]@{ code = $null; timedOut = $false })) -ceq "red") "R5: a run with no exit code is red, never green"
Check ((Get-HordeNightlyVerdict ([pscustomobject]@{ code = $null; timedOut = $false }) -AtTip) -ceq "red") "R5: at the tip too"
Check ($null -eq (ConvertTo-HordeNightlyBisectAnswer "skip")) "R5: a skip in a bisect is unknown, not green"
Check ((ConvertTo-HordeNightlyBisectAnswer "red") -eq $true -and (ConvertTo-HordeNightlyBisectAnswer "green") -eq $false -and (ConvertTo-HordeNightlyBisectAnswer "absent") -eq $false -and $null -eq (ConvertTo-HordeNightlyBisectAnswer "unrun")) "R5: red, green, absent and unrun keep their bisect meaning"
$skipAt = { param($sha) $v = $(if ($sha -ceq "m4") { "skip" } elseif ([int]($sha.Substring(1)) -ge 6) { "red" } else { "green" }); return (ConvertTo-HordeNightlyBisectAnswer $v) }
$r = Find-HordeNightlyCulprit -Merges @(1..8 | ForEach-Object { "m" + $_ }) -IsRed $skipAt
Check ($r.state -ceq "inconclusive") ("R5: a bisect that meets a skip stops inconclusive instead of naming a merge past it (" + $r.state + " " + $r.sha + ")")
Check ((Get-HordeNightlyRunCutoff -Now (Dt "23:00")) -eq ([datetime]"2026-10-23 06:15")) "R5: runs end at 06:15, 15 minutes kept for the report and the tell"
Check ((Get-HordeNightlyRunCutoff -Now (Dt "02:00") -ReportReserveMinutes 0) -eq ([datetime]"2026-10-22 06:30")) "R5: with no reserve, 06:30"
foreach ($st in @("capped", "inconclusive", "flaky")) {
    $ur = $okRow.PSObject.Copy(); $ur.culprits = @([pscustomobject]@{ unit = "u|ps51"; state = $st; sha = ""; merge = $null; runs = 2; between = @("", "abcdef01") })
    $h = (New-HordeNightlyReport -Date "2026-10-22" -Repos @($ur)) -split "`n" | Select-Object -First 1
    Check ($h -like "*INCOMPLETE*1 bisects named no merge*") ("R5: a " + $st + " bisect makes the headline INCOMPLETE (" + $h + ")")
}
$fr = $okRow.PSObject.Copy(); $fr.culprits = @([pscustomobject]@{ unit = "u|ps51"; state = "found"; sha = $merge.sha; merge = $merge; runs = 3; between = @("", $merge.sha) })
$h = (New-HordeNightlyReport -Date "2026-10-22" -Repos @($fr)) -split "`n" | Select-Object -First 1
Check ($h -like "*COMPLETE.*" -and $h -notlike "*INCOMPLETE*") "R5: a bisect that named its merge leaves the night COMPLETE"
$br = $okRow.PSObject.Copy(); $br.culprits = @([pscustomobject]@{ unit = "u|ps51"; state = "base-red"; sha = ""; merge = $null; runs = 2; between = @("abcdef0123", "") })
$bl = @(Get-HordeNightlyFindingLines -Row $br)
Check (@($bl | Where-Object { $_ -like "RED u|ps51 was red at last night's tip abcdef01 too*no merge named*" }).Count -eq 1) ("T-0465: the report says red at last night's tip, no merge named (" + ($bl -join " | ") + ")")
$h = (New-HordeNightlyReport -Date "2026-10-22" -Repos @($br)) -split "`n" | Select-Object -First 1
Check ($h -like "*COMPLETE.*" -and $h -notlike "*INCOMPLETE*") ("T-0465: a red at last night's tip is an answer, so the night stays COMPLETE (" + $h + ")")

Write-Host ""
Write-Host "--- R2: the state is always saved, and what M was not told stays pending until a tell gets through ---" -ForegroundColor Cyan
$emptyCmp = [pscustomobject]@{ newlyRed = @(); stillRed = @(); newRed = @(); fixed = @(); unrun = @() }
$s0 = @{ lastTip = "aaaa"; units = @{ "x|ps51" = "green"; "y|ps51" = "green" } }
$v1 = @{ "x|ps51" = "red"; "y|ps51" = "green" }
$row1 = [pscustomobject]@{ repo = "Y/h"; compare = [pscustomobject]@{ newlyRed = @("x|ps51"); stillRed = @(); newRed = @("z|ps51"); fixed = @(); unrun = @() }
    culprits = @([pscustomobject]@{ unit = "x|ps51"; state = "found"; sha = $merge.sha; merge = $merge; runs = 3; between = @("", $merge.sha) }) }
$fl = @(Get-HordeNightlyFindingLines -Row $row1)
Check ($fl.Count -eq 2 -and $fl[0] -like "RED x|ps51 first red at merge 22222222 PR 372*" -and $fl[1] -ceq "red, no verdict last night: z|ps51") ("the finding lines: the named merge and the new red (" + ($fl -join " / ") + ")")
$s1 = Update-HordeNightlyState -State $s0 -Verdicts $v1 -Tip "bbbb" -Complete $true -Told $false -Findings $fl -Date "2026-10-22"
Check ($s1.units["x|ps51"] -ceq "red" -and $s1.lastTip -ceq "bbbb") "R2: a night whose tell failed still saves its verdicts and moves the tip"
Check (@($s1.pending).Count -eq 2 -and $s1.pending[0] -like "2026-10-22: RED x|ps51 first red at merge*") ("R2: and keeps its findings pending, dated (" + (@($s1.pending) -join " / ") + ")")
$cmp2 = Compare-HordeNightlyVerdicts -Now @{ "x|ps51" = "red" } -Last $s1.units
Check (@($cmp2.newlyRed).Count -eq 0 -and (($cmp2.stillRed -join ",") -ceq "x|ps51")) "R2: so the next night that red is still red, not newly red again (no second bisect)"
$row2 = [pscustomobject]@{ repo = "Y/h"; tip = "cccc"; lastTip = "bbbb"; merges = @(); guards = [pscustomobject]@{ state = "green"; text = "" }; suiteCount = 2; unrunCount = 0
    compare = $cmp2; culprits = @(); notes = @(); incomplete = ""; pending = @($s1.pending) }
$rep2 = New-HordeNightlyReport -Date "2026-10-23" -Repos @($row2)
Check ($rep2 -like "*NOT TOLD BEFORE (that night's tell failed): 2026-10-22: RED x|ps51 first red at merge 22222222*") "R2: the next report re-lists what M was not told"
$s2b = Update-HordeNightlyState -State $s1 -Verdicts @{ "x|ps51" = "red" } -Tip "cccc" -Complete $true -Told $false -Findings @() -Date "2026-10-23"
Check (@($s2b.pending).Count -eq 2) "R2: still pending after a second failed tell"
$s3b = Update-HordeNightlyState -State $s2b -Verdicts @{ "x|ps51" = "red" } -Tip "dddd" -Complete $true -Told $true -Findings @("RED q") -Date "2026-10-24"
Check (@($s3b.pending).Count -eq 0 -and $s3b.lastTip -ceq "dddd") "R2: a tell that gets through empties pending"
$s4 = Update-HordeNightlyState -State $s0 -Verdicts @{ "x|ps51" = "unrun" } -Tip "eeee" -Complete $false -Told $true
Check ($s4.lastTip -ceq "aaaa" -and $s4.units["x|ps51"] -ceq "green") "an incomplete night keeps the tip and an unrun unit's verdict"
$many = @(1..50 | ForEach-Object { "RED u" + $_ })
$s5 = Update-HordeNightlyState -State $s0 -Verdicts @{} -Tip "ffff" -Complete $true -Told $false -Findings $many -Date "d" -MaxPending 40
Check (@($s5.pending).Count -eq 40 -and $s5.pending[39] -ceq "d: RED u50") "pending keeps the newest 40"
$sp = @{ lastTip = ""; units = @{ "pytest-node|a" = "red"; "pytest-node|b" = "red" } }
$s6b = Update-HordeNightlyState -State $sp -Verdicts @{ "pytest-all" = "green"; "pytest-node|b" = "red" } -Kind "pytest" -Tip "t" -Complete $true -Told $true
Check (-not $s6b.units.ContainsKey("pytest-node|a") -and $s6b.units["pytest-node|b"] -ceq "red") "pytest: a node that is no longer red is gone from the red list"

Write-Host ""
Write-Host "--- the memory night of 2026-10-23: fail fast, fewest units first, count what ran, name who holds memory ---" -ForegroundColor Cyan
$gu = "heavy-slot: waiting for the slot`r`nheavy-slot: gave up after 900 s waiting for 4.5 GB of free memory (now 1.1)`; nothing was run`r`nheavy-slot: memory held by alpha, 41 processes, 9.80 GB`r`nheavy-slot: memory held by beta, 12 processes, 7.04 GB`r`nheavy-slot: released exit=125`r`n"
$gc = "heavy-slot: gave up after 120 s waiting for 2 GB of commit headroom (now 1.5)`; nothing was run`r`nheavy-slot: released exit=125"
$gs = "heavy-slot: gave up after 120 s waiting for the slot`; nothing was run`r`nheavy-slot: released exit=125"
$gr = "heavy-slot: waiting for the slot`r`nheavy-slot: running test\test-a.ps1 with 5.2 GB free, output in x`r`nheavy-slot: released exit=0"
Check (Test-HordeNightlyMemoryGiveUp -Gate $gu) "a give-up on free memory is a memory give-up"
Check (Test-HordeNightlyMemoryGiveUp -Gate $gc) "so is a give-up on commit headroom"
Check (-not (Test-HordeNightlyMemoryGiveUp -Gate $gs)) "a give-up on the slot is not (exit 125 alone says nothing about memory)"
Check ((Update-HordeNightlyMemoryShort -Short $false -Gate $gu) -eq $true) "a memory give-up makes the night short on memory"
Check ((Update-HordeNightlyMemoryShort -Short $true -Gate $gs) -eq $true) "a slot give-up leaves it short"
Check ((Update-HordeNightlyMemoryShort -Short $true -Gate $gr) -eq $false) "the first gate that gets its memory and runs ends it"
Check ((Update-HordeNightlyMemoryShort -Short $false -Gate $gs) -eq $false) "a slot give-up does not start it"
Check ((Get-HordeNightlySlotWait -MemoryShort $false -Normal 900 -Short 120) -eq 900) "the normal wait when not short"
Check ((Get-HordeNightlySlotWait -MemoryShort $true -Normal 900 -Short 120) -eq 120) "the short wait when short"
Check ((Get-HordeNightlySlotWait -MemoryShort $true -Normal 60 -Short 120) -eq 60) "never longer than the normal wait"
$ho = @(Read-HordeNightlyMemoryHolders -Gate $gu)
Check ($ho.Count -eq 2 -and $ho[0].name -ceq "alpha" -and $ho[0].count -eq 41 -and $ho[0].gb -eq 9.8 -and $ho[1].name -ceq "beta") ("the holders are read back in the gate's order (" + $ho.Count + ")")
Check (@(Read-HordeNightlyMemoryHolders -Gate $gs).Count -eq 0) "a gate with none lists none"
Check ((@(Get-HordeNightlyRepoOrder -Counts @(968, 2)) -join ",") -ceq "1,0") "the 2-unit repo runs before the 968-unit one"
Check ((@(Get-HordeNightlyRepoOrder -Counts @(5, 5, 1)) -join ",") -ceq "2,0,1") "ties keep the order given"
Check (@(Get-HordeNightlyRepoOrder -Counts @()).Count -eq 0) "no repos, no order"
$vv = @{ "a|ps51" = "unrun"; "a|pwsh7" = "unrun"; "b|ps51" = "green"; "c|ps51" = "red"; "d|ps51" = "hung"; "e|ps51" = "skip" }
Check ((Get-HordeNightlyRunCount -Verdicts $vv) -eq 4) ("units run counts every verdict but unrun (" + (Get-HordeNightlyRunCount -Verdicts $vv) + ")")
Check ((Get-HordeNightlyRunCount -Verdicts @{ "a|ps51" = "unrun"; "b|ps51" = "unrun" }) -eq 0) "a night where every gate exited 125 ran 0 units"
$mrow = [pscustomobject]@{ repo = "Y/h"; tip = "abcdef01"; lastTip = ""; merges = @(); guards = [pscustomobject]@{ state = "not run (no slot or no night)"; text = "" }
    suiteCount = 0; unrunCount = 24; compare = [pscustomobject]@{ newlyRed = @(); stillRed = @(); newRed = @(); fixed = @(); unrun = @() }; culprits = @(); notes = @(); incomplete = "" }
$mm = [pscustomobject]@{ giveUps = 25; minFreeGB = "4.5"; minCommitGB = "2"; holders = @($ho + @([pscustomobject]@{ name = "gamma"; count = 3; gb = 1.25 }, [pscustomobject]@{ name = "delta"; count = 1; gb = 0.5 })) }
$mrep = New-HordeNightlyReport -Date "2026-10-23" -Repos @($mrow) -Memory $mm
Check ($mrep -like "*MEMORY: 25 slot waits gave up on memory (floor 4.5 GB free, 2 GB commit headroom). Held by: alpha 41 processes 9.8 GB, beta 12 processes 7.0 GB, gamma 3 processes 1.3 GB.*") ("the report names the top 3 holders (" + (@(($mrep -split "`n") | Where-Object { $_ -like "MEMORY*" }) -join "") + ")")
Check ($mrep -notlike "*delta*") "and only 3"
Check ($mrep -like "*units run: 0, not run (slot, memory or night ran out): 24*") "the report says 0 units run"
Check ((New-HordeNightlyReport -Date "d" -Repos @($mrow) -Memory ([pscustomobject]@{ giveUps = 0; minFreeGB = "4.5"; minCommitGB = "2"; holders = @() })) -cnotlike "*MEMORY*") "no memory line on a night with no memory give-up"
Check ((New-HordeNightlyReport -Date "d" -Repos @($mrow)) -cnotlike "*MEMORY*") "nor when no memory facts are given"

Write-Host ""
Write-Host "--- needs: a suite declares what the night must have, a probe that says no SKIPS it, never green ---" -ForegroundColor Cyan
# 2026-10-26: 15 horde units were red only because the night lacked a symbolic link privilege, an elevated token, WSL or
# a wezfleet checkout. The probes are FAKE here (stand-in answers): nothing on this machine is asked.
$hdr = @("# DOES IT WORK?", "#", "# nightly-needs: symlink", "", "`$x = 1", "# nightly-needs: wsl", "Write-Host '# nightly-needs: elevated'")
Check ((@(Read-HordeNightlyNeeds -Lines $hdr) -join ",") -ceq "symlink") ("the header's declaration is read, and nothing after the first line of code (" + (@(Read-HordeNightlyNeeds -Lines $hdr) -join ",") + ")")
Check ((@(Read-HordeNightlyNeeds -Lines @("# a", "# nightly-needs: symlink, elevated", "#nightly-needs: wsl")) -join ",") -ceq "symlink,elevated,wsl") "a list, and more than one line, are read"
Check (@(Read-HordeNightlyNeeds -Lines @("# a suite", "", "`$x = 1")).Count -eq 0) "a suite that declares nothing needs nothing"
Check ((@(Read-HordeNightlyNeeds -Lines @("# nightly-needs: Sym link!")) -join ",") -ceq "malformed") "a declaration of the wrong shape is the need malformed, never nothing"
$noLink = @{ symlink = [pscustomobject]@{ ok = $false; why = "this account may not make a symbolic link" }; wsl = [pscustomobject]@{ ok = $true; why = "WSL lists 1 distro(s)" } }
$sr = Get-HordeNightlySkipReason -Needs @("symlink") -Probes $noLink
Check ($sr -ceq "needs symlink: this account may not make a symbolic link") ("a unit needing symlink with the probe false is skipped, with the probe's reason (" + $sr + ")")
Check ((Get-HordeNightlySkipReason -Needs @("wsl") -Probes $noLink) -ceq "") "with the probe true it runs (no reason)"
Check ((Get-HordeNightlySkipReason -Needs @() -Probes $noLink) -ceq "") "a unit with no needs runs"
Check ((Get-HordeNightlySkipReason -Needs @("wsl", "symlink") -Probes $noLink) -like "needs symlink:*" -and (Get-HordeNightlySkipReason -Needs @("wsl", "symlink") -Probes $noLink) -notlike "*wsl*") "only the unmet need is named"
Check ((Get-HordeNightlySkipReason -Needs @("elevatd") -Probes $noLink) -ceq "needs elevatd, which no probe answers") "a need no probe answers is skipped and named, never taken as met"
Check ((@(Get-HordeNightlyNeedNames) -join ",") -ceq "symlink,elevated,wsl,wezfleet-repo") "the needs the night can probe"
$skv = @{ "s|ps51" = "skipped"; "g|ps51" = "green"; "r|ps51" = "red"; "u|ps51" = "unrun" }
Check ((Get-HordeNightlyRunCount -Verdicts $skv) -eq 2) ("a skipped unit is not counted as run (" + (Get-HordeNightlyRunCount -Verdicts $skv) + ")")
$skc = Compare-HordeNightlyVerdicts -Now @{ "s|ps51" = "skipped"; "t|ps51" = "skipped" } -Last @{ "s|ps51" = "red"; "t|ps51" = "green" }
Check ((($skc.skipped -join ",") -ceq "s|ps51,t|ps51") -and @($skc.fixed).Count -eq 0 -and @($skc.newlyRed).Count -eq 0 -and @($skc.newRed).Count -eq 0) "a skipped unit is listed as skipped: a red skipped tonight is not fixed, and it is never red"
Check ((Get-HordeNightlyStoredVerdict -Verdict "skipped" -Previous "green") -ceq "skip" -and (Get-HordeNightlyStoredVerdict -Verdict "skipped" -Previous "") -ceq "skip") "a skipped unit is never stored green, not even over a green"
Check ((Get-HordeNightlyStoredVerdict -Verdict "skipped" -Previous "red") -ceq "") "and a stored red stands over it"
Check ((ConvertTo-HordeNightlyBisectAnswer "skipped") -eq $null) "a skipped answer in a bisect is no answer"
$skRow = [pscustomobject]@{ repo = "Y/h"; tip = "abcdef01"; lastTip = "01234567"; merges = @(); guards = [pscustomobject]@{ state = "green"; text = "" }
    suiteCount = (Get-HordeNightlyRunCount -Verdicts @{ "test/test-a.ps1|ps51" = "skipped"; "test/test-a.ps1|pwsh7" = "skipped"; "test/test-b.ps1|ps51" = "green" }); unrunCount = 0
    compare = (Compare-HordeNightlyVerdicts -Now @{ "test/test-a.ps1|ps51" = "skipped"; "test/test-a.ps1|pwsh7" = "skipped"; "test/test-b.ps1|ps51" = "green" } -Last @{})
    skipReasons = @{ "test/test-a.ps1|ps51" = $sr; "test/test-a.ps1|pwsh7" = $sr }; culprits = @(); notes = @(); incomplete = "" }
$skRep = New-HordeNightlyReport -Date "2026-10-27" -Repos @($skRow)
Check ($skRep -like "*SKIPPED test/test-a.ps1|ps51, test/test-a.ps1|pwsh7 - needs symlink: this account may not make a symbolic link*") ("the report shows the skipped units on one line with their reason (" + (($skRep -split "`n") | Where-Object { $_ -like "*SKIPPED*" }) + ")")
Check ($skRep -like "*units run: 1,*" -and $skRep -like "*skipped (the night lacks what they need, not run, never green): 2*") "units run counts only what ran, and the skipped count is its own line"
Check ((($skRep -split "`n")[0]) -like "*COMPLETE.*SKIPPED: 2 units, the night lacks what they need (never green).*") ("the headline says how many were skipped (" + (($skRep -split "`n")[0]) + ")")
Check ($skRep -notmatch '["<>;]') "and the report still has no double quote, semicolon or angle bracket"

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
    $base = ("" + @(Git $origin @("rev-parse", "HEAD"))[0]).Trim()
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
    # -AtTime 14:00 (day) so the floor -Plan states does not move with the real clock (the night floors are below).
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -Plan -AtTime "2026-10-22T14:00:00" -WorkRoot $wr -Repos "Fix/Repo:pytest:main")
    $code = $LASTEXITCODE
    $text = $o -join "`n"
    Check ($code -eq 0) ("-Plan exits 0 (" + $code + ")")
    Check ($text -like "*PLAN Fix/Repo (pytest)*3 merges*") ("it lists the three merges since last night (" + (($o | Where-Object { $_ -like "PLAN*" }) -join "") + ")")
    Check ($text -like "*PR 102 T-7 by lane-x*[[]owed[]]*") "the owed entry labelled the second merge"
    Check ($text -like "*Merge pull request #101*" -and $text -like "*Merge pull request #103*") "the other two come from git alone"
    Check ($text -like "*units: 2*") "a pytest repo has two units: the whole run and flake8"
    Check (-not (Test-Path -LiteralPath (Join-Path $wr "runs"))) "and -Plan ran nothing: no run folder"
    Check ($text -like "*memory floor pytest 4.5 GB free, 2 GB commit headroom (night floors 22:00 to 07:00, by day 4.5 GB free and 2 GB commit headroom)*slot wait 900 s, 120 s after a memory give-up*") "-Plan by day states the day floor (default 4.5 GB), the commit floor and both slot waits"
    Check ($text -like "*PLAN apps (named list: chrome, Slack, WhatsApp, WhatsApp.Root, ClickUp, ms-teams, Teams, Zoom*force-quit only Slack, WhatsApp, WhatsApp.Root, ClickUp*WOULD CLOSE (dry run, nothing closed)*WOULD FORCE-QUIT*") "-Plan lists, dry, what the app closer would close and force-quit"
    Check ($text -like "*CHROME RESTORE*") "and the Chrome restore setting, read only"
    Check ($text -like "*PLAN time: suite phase 22:00 to 05:45 = 27900 s for 2 gate runs*") ("and the time budget of the suite phase (" + (($o | Where-Object { $_ -like "PLAN time*" }) -join "") + ")")
    # -AtTime stands in for the clock in the budget too: on 2026-11-06 at 02:16 the check above was red only because the
    # budget read the real clock, which was inside the window. These two hold at any real hour.
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -Plan -AtTime "2026-10-22T23:10:00" -NoCloseApps -WorkRoot $wr -Repos "Fix/Repo:pytest:main")
    Check ((($o -join "`n") -like "*PLAN time: suite phase 23:10 to 05:45 = 23700 s for 2 gate runs*")) ("-AtTime inside the window starts the budget at that time (" + (($o | Where-Object { $_ -like "PLAN time*" }) -join "") + ")")
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -Plan -AtTime "2026-10-22T14:00:00" -NoCloseApps -WorkRoot $wr -Repos "Fix/Repo:pytest:main" -MinFreeGB 3.25)
    Check ((($o -join "`n") -like "*memory floor pytest 3.25 GB free*")) "-MinFreeGB is the one setting that moves the day floor"
    Check ((($o -join "`n") -like "*PLAN apps: -NoCloseApps, nothing would be closed*")) "-NoCloseApps: -Plan says nothing would be closed"
    # The registrar's own -Hour default, read from its dry run (-Plan registers nothing and returns before the scheduler is touched).
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\nightly\Register-NightlyTask.ps1") -Plan -HordeRoot $root)
    $rtxt = $o -join "`n"
    Check ($LASTEXITCODE -eq 0 -and $rtxt -like "*dry run: nothing registered*") ("the registrar -Plan registers nothing (" + $LASTEXITCODE + ")")
    Check ($rtxt -match '<StartBoundary>\d{4}-\d\d-\d\dT22:00:00</StartBoundary>') "and with no -Hour the registrar's boundary is 22:00:00 (its own default)"
    Check ($rtxt -like "*settings:*start on battery*not stopped on battery*") "and its settings line states that a run starts on battery and is not stopped when the PC goes onto battery"
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -Plan -AtTime "2026-10-22T23:00:00" -NoCloseApps -WorkRoot $wr -Repos "Fix/Repo:pytest:main" -MinFreeGB 3.25)
    Check ((($o -join "`n") -like "*memory floor pytest 2.5 GB free, 1 GB commit headroom (night floors*floor: 2.5 GB free, 1 GB commit headroom (night floor)*")) "at 23:00 the night floor of the kind stands, whatever -MinFreeGB says"
    # T-0397: a run started at 01:00 is night 11-04's run, with that morning's cutoff and its own report names.
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -Plan -AtTime "2026-11-05T01:00:00" -NoCloseApps -WorkRoot $wr -Repos "Fix/Repo:pytest:main")
    Check ((($o -join "`n") -like "*nightly net 2026-11-04: window open, cutoff 2026-11-05T06:15:00*")) "a start at 01:00 is labelled with the night's date and gets that morning's cutoff"
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -Plan -AtTime "2026-11-04T23:30:00" -NoCloseApps -WorkRoot $wr -Repos "Fix/Repo:pytest:main")
    Check ((($o -join "`n") -like "*nightly net 2026-11-04: window open, cutoff 2026-11-05T06:15:00*")) "and a start at 23:30 is the same night with the same cutoff"
    # A failed night is never silent: a bad -Repos entry is an error, and it ends exit 1 saying FAILED.
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -Plan -NoTell -WorkRoot $wr -Repos "not-a-spec" 2>&1)
    Check ($LASTEXITCODE -eq 1 -and (($o -join "`n") -like "*nightly net FAILED*")) ("an error ends exit 1 and says FAILED (" + $LASTEXITCODE + ")")
    # R4 (review of PR 380, finding 4): a lock held at the start (a wedged earlier run) tells M and exits 5, never a
    # silent exit 0. The tell is a stub that records what it was given and what it inherited.
    $stubDir = Join-Path $work "stub"; [void][System.IO.Directory]::CreateDirectory($stubDir)
    $stub = Join-Path $stubDir "tell.cmd"; $rec = Join-Path $stubDir "rec.txt"
    [System.IO.File]::WriteAllText($stub, "@echo off`r`necho GCM=%GCM_INTERACTIVE% PROMPT=%GIT_TERMINAL_PROMPT% %*>>`"%~dp0rec.txt`"`r`nexit /b 0`r`n")
    $mname = "Local\horde-nightly-test-" + [guid]::NewGuid().ToString("N")
    $lock = New-Object System.Threading.Mutex($true, $mname)
    try {
        $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -AtTime "2026-10-22T23:00:00" -MutexName $mname -WorkRoot (Join-Path $work "wr-busy") -TellProgram $stub -TellRetrySeconds 0 -Repos "Fix/Repo:pytest:main")
        $bc = $LASTEXITCODE
    } finally { $lock.ReleaseMutex(); $lock.Dispose() }
    $rt = $(if (Test-Path -LiteralPath $rec) { [System.IO.File]::ReadAllText($rec) } else { "" })
    Check ($bc -eq 5) ("R4: a held lock ends exit 5, not 0 (" + $bc + ")")
    $bm = [regex]::Match($rt, '-MessageFile "?([^"\r\n]+?)"?\s*$', "Multiline")
    Check ($bm.Success -and $rt -like "*tell M -Kind report*" -and (Test-Path -LiteralPath $bm.Groups[1].Value) -and ([System.IO.File]::ReadAllText($bm.Groups[1].Value) -like "*NOT RUN, another nightly run still holds the lock*")) ("R4: and M is told the night did not run (" + $rt.Trim() + ")")
    Check ($rt -like "*GCM=never PROMPT=0*") "R4: the night runs with no git credential prompt of either kind (GCM_INTERACTIVE=never, GIT_TERMINAL_PROMPT=0)"
    # T-0397: a start outside the window is never silent. It writes a report, tells the target and still exits 4;
    # -NoTell keeps the report but tells nobody; a tell that fails leaves the exit at 4.
    if (Test-Path -LiteralPath $rec) { Remove-Item -LiteralPath $rec -Force }
    $rwr = Join-Path $work "wr-refused"
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -AtTime "2026-11-01T21:00:00" -WorkRoot $rwr -TellProgram $stub -TellRetrySeconds 0 -Repos "Fix/Repo:pytest:main")
    $rc = $LASTEXITCODE
    $rt = $(if (Test-Path -LiteralPath $rec) { [System.IO.File]::ReadAllText($rec) } else { "" })
    $rm = [regex]::Match($rt, '-MessageFile "?([^"\r\n]+?)"?\s*$', "Multiline")
    Check ($rc -eq 4) ("T-0397: a start outside the window exits 4 (" + $rc + ")")
    Check ($rm.Success -and $rt -like "*tell M -Kind report*" -and (Test-Path -LiteralPath $rm.Groups[1].Value) -and ([System.IO.File]::ReadAllText($rm.Groups[1].Value) -like "*NOT RUN*21:00*outside the night window*nothing ran*")) ("T-0397: and M is told, naming the start time, the window and that nothing ran (" + $rt.Trim() + ")")
    if (Test-Path -LiteralPath $rec) { Remove-Item -LiteralPath $rec -Force }
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -AtTime "2026-11-01T21:00:00" -NoTell -WorkRoot (Join-Path $work "wr-refused-nt") -TellProgram $stub -TellRetrySeconds 0 -Repos "Fix/Repo:pytest:main")
    $nc = $LASTEXITCODE
    Check ($nc -eq 4 -and -not (Test-Path -LiteralPath $rec)) ("T-0397: with -NoTell nobody is told and the exit is still 4 (" + $nc + ")")
    Check (Test-Path -LiteralPath (Join-Path (Join-Path $work "wr-refused-nt") "reports\2026-11-01-REFUSED.txt")) "T-0397: and the report file is kept in the report folder"
    $failStub = Join-Path $stubDir "tellfail.cmd"
    [System.IO.File]::WriteAllText($failStub, "@echo off`r`nexit /b 1`r`n")
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -AtTime "2026-11-01T21:00:00" -WorkRoot (Join-Path $work "wr-refused-f") -TellProgram $failStub -TellRetrySeconds 0 -Repos "Fix/Repo:pytest:main")
    Check ($LASTEXITCODE -eq 4) ("T-0397: a tell that fails leaves the exit at 4 (" + $LASTEXITCODE + ")")
    # R5 (review of PR 380, finding 6): a work folder that cannot be made still ends in a FAILED line told to M, written
    # under the temp path, and the first log line is kept there. The child's temp path is pointed into this test's folder.
    $blocker = Join-Path $work "a-file"; [System.IO.File]::WriteAllText($blocker, "x")
    $tmpDir = Join-Path $work "tmp"; [void][System.IO.Directory]::CreateDirectory($tmpDir)
    if (Test-Path -LiteralPath $rec) { Remove-Item -LiteralPath $rec -Force }
    $oldTmp = $env:TMP; $oldTemp = $env:TEMP
    try {
        $env:TMP = $tmpDir; $env:TEMP = $tmpDir
        $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -AtTime "2026-10-22T23:00:00" -MutexName ($mname + "-b") -WorkRoot (Join-Path $blocker "wr") -TellProgram $stub -TellRetrySeconds 0 -Repos "Fix/Repo:pytest:main")
        $fc = $LASTEXITCODE
    } finally { $env:TMP = $oldTmp; $env:TEMP = $oldTemp }
    $rt = $(if (Test-Path -LiteralPath $rec) { [System.IO.File]::ReadAllText($rec) } else { "" })
    $fb = Join-Path $tmpDir "horde-nightly-fallback"
    Check ($fc -eq 1) ("R5: a work folder that cannot be made ends exit 1 (" + $fc + ")")
    Check ($rt -like ("*" + $fb + "*2026-10-22-FAILED.txt*") -and ([System.IO.File]::ReadAllText((Join-Path $fb "2026-10-22-FAILED.txt")) -like "*FAILED*could not be made*")) ("R5: and M is still told, from the temp path (" + $rt.Trim() + ")")
    $fl = Join-Path $fb "nightly.log"
    Check ((Test-Path -LiteralPath $fl) -and ([System.IO.File]::ReadAllText($fl) -like "*nightly net 2026-10-22: window open*")) "R5: the first log line is kept, in the fallback folder"
    # A WHOLE NIGHT with a stand-in gate (-HeavySlotScript): no slot, no memory, no suite. The gate records what it was
    # asked (script, floors, wait) and answers: call 3 runs, every other call gives up on memory. Two repos, the horde
    # one (4 units and its guards) given FIRST: the pytest repo (2 units) must run first.
    $hn = Join-Path $work "night"; [void][System.IO.Directory]::CreateDirectory($hn)
    $gateStub = Join-Path $hn "gate.ps1"
    [System.IO.File]::WriteAllText($gateStub, @'
param([string]$Script, [string]$Worktree, [string]$Out, [string]$MinFreeGB, [string]$MinCommitHeadroomGB, [string]$WaitSeconds, [string]$RunSeconds, [string]$ArgsFile)
$calls = Join-Path $PSScriptRoot "calls.txt"
$n = 1; if (Test-Path -LiteralPath $calls) { $n = @(Get-Content -LiteralPath $calls).Count + 1 }
Add-Content -LiteralPath $calls -Value ($Script + "|" + $MinFreeGB + "|" + $MinCommitHeadroomGB + "|" + $WaitSeconds)
[System.IO.File]::WriteAllText($Out, "")
if ($Script -ceq "guards-wrap.ps1") { Write-Output ("heavy-slot: running " + $Script + " with 5 GB free, output in " + $Out); Write-Output "heavy-slot: released exit=0"; exit 0 }
Write-Output ("heavy-slot: gave up after " + $WaitSeconds + " s waiting for " + $MinFreeGB + " GB of free memory (now 1.1); nothing was run")
Write-Output "heavy-slot: memory held by alpha, 41 processes, 9.80 GB"
Write-Output "heavy-slot: memory held by beta, 12 processes, 7.04 GB"
Write-Output "heavy-slot: memory held by gamma, 3 processes, 1.25 GB"
Write-Output "heavy-slot: memory held by delta, 1 processes, 0.50 GB"
Write-Output "heavy-slot: released exit=125"
exit 125
'@)
    $thinGate = Join-Path $hn "thin-gate.ps1"
    [System.IO.File]::WriteAllText($thinGate, ('param([string]$Script, [string]$Worktree, [string]$Out)' + "`r`n" + '[System.IO.File]::WriteAllText($Out, "")' + "`r`n" + 'Write-Output "heavy-slot: gave up after 1 s waiting for the slot; nothing was run"' + "`r`n" + 'Write-Output "heavy-slot: released exit=125"' + "`r`n" + 'exit 125' + "`r`n"))
    $hwr = Join-Path $hn "wr"
    $horigin = Join-Path $hn "horigin"; [void][System.IO.Directory]::CreateDirectory((Join-Path $horigin "test\lib"))
    [void](Git $horigin @("init", "-q", "-b", "main"))
    [System.IO.File]::WriteAllText((Join-Path $horigin "test\lib\SuiteFiles.ps1"), "function Get-HordeSuiteFiles { param([string]`$Root) return @(Get-ChildItem -LiteralPath (Join-Path `$Root 'test') -Filter 'test-*.ps1' | Sort-Object Name) }`r`nfunction Get-HordeMachineBoundSuites { return @() }`r`n")
    foreach ($t in @("test-a.ps1", "test-b.ps1")) { [System.IO.File]::WriteAllText((Join-Path $horigin ("test\" + $t)), "exit 0`r`n") }
    [void](Git $horigin @("add", "-A")); [void](Git $horigin @("commit", "-q", "-m", "base"))
    & git.exe clone -q $horigin (Join-Path $hwr "Fix__Hord\tree"); if ($LASTEXITCODE -ne 0) { throw "clone failed" }
    & git.exe clone -q $origin (Join-Path $hwr "Fix__Py\tree"); if ($LASTEXITCODE -ne 0) { throw "clone failed" }
    # Tonight at 23:00 is inside the window, and the real clock is always well before its cutoff.
    $night = (Get-Date).Date.AddHours(23)
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -AtTime $night.ToString("s") -NoTell -BisectReserveMinutes 0 -CoverageFloorPercent 0 -MutexName ("Local\horde-nightly-test-" + [guid]::NewGuid().ToString("N")) -WorkRoot $hwr -HeavySlotScript $gateStub -RunSeconds 60 -LongRunSeconds 60 -Repos "Fix/Hord:horde:main,Fix/Py:pytest:main")
    $nc = $LASTEXITCODE
    $callsFile = Join-Path $hn "calls.txt"
    $calls = @(); if (Test-Path -LiteralPath $callsFile) { $calls = @(Get-Content -LiteralPath $callsFile) }
    Check ($nc -eq 0) ("the night ends exit 0 (" + $nc + ")")
    Check ($calls.Count -eq 13) ("every unit went to the gate twice (T-0491: a gate that ran nothing puts it back on the queue once) and the guards once: 2x2 + 1 + 4x2 (" + $calls.Count + ")")
    $scripts = @($calls | ForEach-Object { ($_ -split '\|')[0] })
    # The first pass of every repo, then the second tries (T-0504): the 2-unit repo's 2 first tries, the guards and the
    # 4 horde first tries, then the pytest repo's 2 second tries, then horde's 4.
    $pyAt = @(0, 1, 7, 8)
    Check ($calls.Count -eq 13 -and @($pyAt | Where-Object { $scripts[$_] -cne "pytest-wrap.ps1" }).Count -eq 0 -and $scripts[2] -ceq "guards-wrap.ps1" -and @(@(3..6) + @(9..12) | Where-Object { $scripts[$_] -ceq "pytest-wrap.ps1" -or $scripts[$_] -ceq "guards-wrap.ps1" }).Count -eq 0) ("the 2-unit repo ran first, though given second, and every second try came after every repo's first pass (" + ($scripts -join ", ") + ")")
    # 23:00 is night: the night floors of each kind (core Get-HordeNightlyNightFloors), not -MinFreeGB.
    Check ($calls.Count -eq 13 -and @($pyAt | Where-Object { ($calls[$_] -split '\|')[1] -cne "2.5" -or ($calls[$_] -split '\|')[2] -cne "1" }).Count -eq 0) "the pytest gates were given the pytest night floor, 2.5 GB free and 1 GB commit headroom"
    Check ($calls.Count -eq 13 -and @(@(0..12) | Where-Object { $pyAt -notcontains $_ } | Where-Object { ($calls[$_] -split '\|')[1] -cne "1" -or ($calls[$_] -split '\|')[2] -cne "1" }).Count -eq 0) "the guards and the horde units were given 1 GB free and 1 GB commit headroom"
    $waits = @($calls | ForEach-Object { ($_ -split '\|')[3] }) -join ","
    Check ($waits -ceq "900,120,120,900,120,120,120,120,120,120,120,120,120") ("the wait is short after a memory give-up and normal again after a gate got its memory (" + $waits + ")")
    $rf = Join-Path $hwr ("reports\" + $night.ToString("yyyy-MM-dd") + ".txt")
    $rtext = $(if (Test-Path -LiteralPath $rf) { [System.IO.File]::ReadAllText($rf) } else { "" })
    Check ($rtext -like "*REPO Fix/Hord*units run: 0, not run (slot, memory or night ran out): 4*") "the horde repo, every unit given up, reports 0 units run"
    Check ($rtext -like "*REPO Fix/Py*units run: 0,*") "and so does the pytest repo"
    Check ($rtext -like "*MEMORY: 12 slot waits gave up on memory (floor pytest 2.5, horde 1 GB free, 1 GB commit headroom). Held by: alpha 41 processes 9.8 GB, beta 12 processes 7.0 GB, gamma 3 processes 1.3 GB.*") "the report counts the give-ups and names the top 3 holders"
    Check ($rtext -like "*guards: green*") "the guards that got their memory ran"
    Check ($rtext -like "*APPS: nothing closed (a suite run*") "a suite run never closes an app, and the report says so"
    $nlog = Join-Path $hwr "nightly.log"
    $ltext = $(if (Test-Path -LiteralPath $nlog) { [System.IO.File]::ReadAllText($nlog) } else { "" })
    Check ($ltext -like "*gave up on memory: slot waits are 120 s*" -and $ltext -like "*got its memory: slot waits are 900 s again*") "the log says when the wait changes"
    # A NIGHT WITH NEEDS, through the real tool: test-a declares symlink (the stand-in probe says no), test-b declares wsl
    # (says yes), test-c declares nothing. Stand-in probes (-ProbesFile) and a gate that runs everything green (exit 0).
    $sn = Join-Path $work "needs"; [void][System.IO.Directory]::CreateDirectory($sn)
    $okGate = Join-Path $sn "gate.ps1"
    [System.IO.File]::WriteAllText($okGate, @'
param([string]$Script, [string]$Worktree, [string]$Out, [string]$MinFreeGB, [string]$MinCommitHeadroomGB, [string]$WaitSeconds, [string]$RunSeconds, [string]$ArgsFile)
$a = ""; if ($ArgsFile -ne "") { $a = [System.IO.File]::ReadAllText($ArgsFile) -replace '\s+', ' ' }
Add-Content -LiteralPath (Join-Path $PSScriptRoot "calls.txt") -Value ($Script + " " + $a)
[System.IO.File]::WriteAllText($Out, "")
Write-Output ("heavy-slot: running " + $Script + " with 5 GB free, output in " + $Out); Write-Output "heavy-slot: released exit=0"; exit 0
'@)
    $probesJson = Join-Path $sn "probes.json"
    [System.IO.File]::WriteAllText($probesJson, '{ "symlink": { "ok": false, "why": "this account may not make a symbolic link (stand-in)" }, "wsl": { "ok": true, "why": "WSL lists 1 distro(s) (stand-in)" } }')
    $sorigin = Join-Path $sn "origin"; [void][System.IO.Directory]::CreateDirectory((Join-Path $sorigin "test\lib"))
    [void](Git $sorigin @("init", "-q", "-b", "main"))
    [System.IO.File]::WriteAllText((Join-Path $sorigin "test\lib\SuiteFiles.ps1"), "function Get-HordeSuiteFiles { param([string]`$Root) return @(Get-ChildItem -LiteralPath (Join-Path `$Root 'test') -Filter 'test-*.ps1' | Sort-Object Name) }`r`nfunction Get-HordeMachineBoundSuites { return @() }`r`n")
    $decl = "# nightly" + "-needs: "
    [System.IO.File]::WriteAllText((Join-Path $sorigin "test\test-a.ps1"), ("# A SUITE THAT MAKES A SYMBOLIC LINK`r`n" + $decl + "symlink`r`nexit 0`r`n"))
    [System.IO.File]::WriteAllText((Join-Path $sorigin "test\test-b.ps1"), ("# A SUITE THAT NEEDS WSL`r`n" + $decl + "wsl`r`nexit 0`r`n"))
    [System.IO.File]::WriteAllText((Join-Path $sorigin "test\test-c.ps1"), "# A SUITE THAT NEEDS NOTHING`r`nexit 0`r`n")
    [void](Git $sorigin @("add", "-A")); [void](Git $sorigin @("commit", "-q", "-m", "base"))
    $swr = Join-Path $sn "wr"
    & git.exe clone -q $sorigin (Join-Path $swr "Fix__Need\tree"); if ($LASTEXITCODE -ne 0) { throw "clone failed" }
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -AtTime $night.ToString("s") -NoTell -BisectReserveMinutes 0 -CoverageFloorPercent 0 -MutexName ("Local\horde-nightly-test-" + [guid]::NewGuid().ToString("N")) -WorkRoot $swr -HeavySlotScript $okGate -ProbesFile $probesJson -RunSeconds 60 -LongRunSeconds 60 -Repos "Fix/Need:horde:main")
    $snc = $LASTEXITCODE
    $scalls = @(); if (Test-Path -LiteralPath (Join-Path $sn "calls.txt")) { $scalls = @(Get-Content -LiteralPath (Join-Path $sn "calls.txt")) }
    Check ($snc -eq 0) ("the night with needs ends exit 0 (" + $snc + ")")
    Check (@($scalls | Where-Object { $_ -like "*test-a.ps1*" }).Count -eq 0) ("the unit needing symlink, with the probe false, never went to the gate (" + ($scalls -join " | ") + ")")
    Check (@($scalls | Where-Object { $_ -like "*test-b.ps1*" }).Count -eq 2 -and @($scalls | Where-Object { $_ -like "*test-c.ps1*" }).Count -eq 2) "the unit needing wsl, with the probe true, ran in both shells, and so did the unit that needs nothing"
    $srf = Join-Path $swr ("reports\" + $night.ToString("yyyy-MM-dd") + ".txt")
    $srt = $(if (Test-Path -LiteralPath $srf) { [System.IO.File]::ReadAllText($srf) } else { "" })
    Check ($srt -like "*SKIPPED test/test-a.ps1|ps51, test/test-a.ps1|pwsh7 - needs symlink: this account may not make a symbolic link (stand-in)*") ("the report shows the skipped line with its reason (" + (($srt -split "`n") | Where-Object { $_ -like "*SKIPPED*" }) + ")")
    Check ($srt -like "*units run: 4, not run (slot, memory or night ran out): 0*") ("the skipped units are not counted as run (" + (($srt -split "`n") | Where-Object { $_ -like "*units run*" }) + ")")
    $sst = $(if (Test-Path -LiteralPath (Join-Path $swr "Fix__Need\state.json")) { ConvertFrom-HordeJson ([System.IO.File]::ReadAllText((Join-Path $swr "Fix__Need\state.json"))) } else { $null })
    Check ($null -ne $sst -and ("" + $sst.units.'test/test-a.ps1|ps51') -ceq "skip" -and ("" + $sst.units.'test/test-a.ps1|pwsh7') -ceq "skip" -and ("" + $sst.units.'test/test-c.ps1|ps51') -ceq "green") "the skipped unit is never stored green (stored as a skip), while the units that ran are"
    $slog = $(if (Test-Path -LiteralPath (Join-Path $swr "nightly.log")) { [System.IO.File]::ReadAllText((Join-Path $swr "nightly.log")) } else { "" })
    Check (([regex]::Matches($slog, 'probe symlink: NO')).Count -eq 1 -and $slog -like "*probe wsl: yes*") "the probes were asked once for the night and logged"
    # The wrappers: a suite that is not in the commit is 126 (absent), a missing python is 71 (unrun, never green).
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\nightly\pwsh-wrap.ps1") -Suite (Join-Path $work "no-such-suite.ps1") -Tree $work)
    Check ($LASTEXITCODE -eq 126 -or $LASTEXITCODE -eq 127) ("pwsh-wrap on an absent suite is 126 (or 127 where pwsh 7 is not installed) (" + $LASTEXITCODE + ")")
    $oldPath = $env:PATH
    try { $env:PATH = $work; $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\nightly\pytest-wrap.ps1") -Tree $work -Mode all -NodesFile (Join-Path $work "n.txt")); $pc = $LASTEXITCODE } finally { $env:PATH = $oldPath }
    Check ($pc -eq 71 -and -not (Test-Path -LiteralPath (Join-Path $work "n.txt"))) ("pytest-wrap without python is 71 and writes no nodes file (" + $pc + ")")
    # pytest-wrap gives pytest a --basetemp of its own beside the nodes file, never the shared %TEMP%\pytest-of-<user>
    # (2026-10-26: that folder's ACL locked even its owner out and 786 tmp_path tests errored at setup). A fake python
    # records its arguments; the wrap must pass a fresh, unique, per-run folder and leave nothing behind.
    $fake = Join-Path $work "fakepy"
    [void][System.IO.Directory]::CreateDirectory($fake)
    $argLog = Join-Path $fake "args.txt"
    [System.IO.File]::WriteAllText((Join-Path $fake "python.cmd"), ("@echo off" + "`r`n" + ">>""" + $argLog + """ echo %*" + "`r`n" + "exit /b 0" + "`r`n"))
    $btDir = Join-Path $work "btrun"
    [void][System.IO.Directory]::CreateDirectory($btDir)
    $btNodes = Join-Path $btDir "one.nodes"
    [System.IO.File]::WriteAllText($btNodes, "tests/test_x.py::test_y`n")
    try {
        $env:PATH = $fake + ";" + $oldPath
        $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\nightly\pytest-wrap.ps1") -Tree $work -Mode nodes -NodesFile $btNodes); $bc1 = $LASTEXITCODE
        $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\nightly\pytest-wrap.ps1") -Tree $work -Mode all -NodesFile (Join-Path $btDir "all-nodes.txt")); $bc2 = $LASTEXITCODE
    } finally { $env:PATH = $oldPath }
    $argLines = @($(if (Test-Path -LiteralPath $argLog) { Get-Content -LiteralPath $argLog } else { @() }))
    $bts = @($argLines | ForEach-Object { if ($_ -match '--basetemp=(\S+)') { $Matches[1] } })
    Check ($bc1 -eq 0 -and $bc2 -eq 0 -and $argLines.Count -eq 2) ("pytest-wrap ran the fake python once per mode and kept its exit codes (" + $bc1 + ", " + $bc2 + ", " + $argLines.Count + " calls)")
    Check ($bts.Count -eq 2) ("pytest-wrap passes --basetemp in nodes and all mode (" + ($argLines -join " | ") + ")")
    Check (@($bts | Where-Object { $_ -like "*pytest-of-*" -or (Split-Path -Parent $_) -ne $btDir }).Count -eq 0 -and $bts.Count -eq 2) ("the basetemp is beside the nodes file, never the shared pytest-of folder (" + ($bts -join ", ") + ")")
    Check ($bts.Count -eq 2 -and $bts[0] -ne $bts[1]) "each run gets a basetemp of its own"
    Check (@(Get-ChildItem -LiteralPath $btDir -Directory).Count -eq 0) "and the wrap leaves no basetemp folder behind"
    # A NIGHT THAT RAN FEW UNITS IS A FAILURE (2026-11-05: 10 of 476 Horde units, no guards, exit 0). The first rig ran 1 of 7.
    $thinWr = Join-Path $work "thin"
    & git.exe clone -q $horigin (Join-Path $thinWr "Fix__Hord\tree"); if ($LASTEXITCODE -ne 0) { throw "clone failed" }
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -AtTime (Get-Date).Date.AddHours(23).ToString("s") -NoTell -BisectReserveMinutes 0 -MutexName ("Local\horde-nightly-test-" + [guid]::NewGuid().ToString("N")) -WorkRoot $thinWr -HeavySlotScript $thinGate -RunSeconds 60 -LongRunSeconds 60 -Repos "Fix/Hord:horde:main")
    Check ($LASTEXITCODE -eq 6) ("a night with no unit run ends exit 6, not 0 (" + $LASTEXITCODE + ")")
    $thinFile = @(Get-ChildItem -LiteralPath (Join-Path $thinWr "reports") -Filter "*.txt")[0].FullName
    $thinHead = (Get-Content -LiteralPath $thinFile)[0]
    Check ($thinHead -like "*BELOW THE COVERAGE FLOOR of 90 percent: Fix/Hord ran 0 of *") ("and the report's first line says so (" + $thinHead + ")")
    Check ([System.IO.File]::ReadAllText((Join-Path $thinWr "nightly.log")) -like "*below the coverage floor of 90 percent*") "and the log"
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -AtTime (Get-Date).Date.AddHours(23).ToString("s") -NoTell -BisectReserveMinutes 0 -CoverageFloorPercent 0 -MutexName ("Local\horde-nightly-test-" + [guid]::NewGuid().ToString("N")) -WorkRoot $thinWr -HeavySlotScript $thinGate -RunSeconds 60 -LongRunSeconds 60 -Repos "Fix/Hord:horde:main")
    Check ($LASTEXITCODE -eq 0) ("-CoverageFloorPercent 0 is the one setting that turns it off (" + $LASTEXITCODE + ")")

    # A run asked for a subset is not a thin night: -Only and -Limit shrink the list on purpose.
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -AtTime (Get-Date).Date.AddHours(23).ToString("s") -NoTell -BisectReserveMinutes 0 -Limit 1 -MutexName ("Local\horde-nightly-test-" + [guid]::NewGuid().ToString("N")) -WorkRoot $thinWr -HeavySlotScript $thinGate -RunSeconds 60 -LongRunSeconds 60 -Repos "Fix/Hord:horde:main")
    Check ($LASTEXITCODE -eq 0) ("-Limit: no coverage floor, exit 0 (" + $LASTEXITCODE + ")")
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -AtTime (Get-Date).Date.AddHours(23).ToString("s") -NoTell -BisectReserveMinutes 0 -Only "test-a" -MutexName ("Local\horde-nightly-test-" + [guid]::NewGuid().ToString("N")) -WorkRoot $thinWr -HeavySlotScript $thinGate -RunSeconds 60 -LongRunSeconds 60 -Repos "Fix/Hord:horde:main")
    Check ($LASTEXITCODE -eq 0) ("-Only: no coverage floor, exit 0 (" + $LASTEXITCODE + ")")

    # THE NET'S FIRST CLAIM ON THE SLOT: held through every gate call of the suite phase, each gate told it is the net's.
    $cn = Join-Path $work "claim"; [void][System.IO.Directory]::CreateDirectory($cn)
    $claimStub = Join-Path $cn "gate.ps1"
    $claimName = "Local\horde-nightly-claim-" + [guid]::NewGuid().ToString("N")
    $claimStubLines = @(
        'param([string]$Script, [string]$Worktree, [string]$Out, [string]$MinFreeGB, [string]$MinCommitHeadroomGB, [string]$WaitSeconds, [string]$RunSeconds, [string]$ArgsFile)',
        '$c = $null',
        ('$seen = [System.Threading.Mutex]::TryOpenExisting("' + $claimName + '", [ref]$c)'),
        'Add-Content -LiteralPath (Join-Path $PSScriptRoot "calls.txt") -Value ("claim=" + $seen + " netrun=" + (@($args) -contains "-NetRun"))',
        '[System.IO.File]::WriteAllText($Out, "")',
        'Write-Output "heavy-slot: released exit=125"',
        'exit 125')
    [System.IO.File]::WriteAllText($claimStub, ($claimStubLines -join "`r`n"))
    $cwr = Join-Path $cn "wr"
    & git.exe clone -q $origin (Join-Path $cwr "Fix__Py\tree"); if ($LASTEXITCODE -ne 0) { throw "clone failed" }
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -AtTime (Get-Date).Date.AddHours(23).ToString("s") -NoTell -BisectReserveMinutes 0 -MutexName ("Local\horde-nightly-test-" + [guid]::NewGuid().ToString("N")) -NetClaimName $claimName -WorkRoot $cwr -HeavySlotScript $claimStub -RunSeconds 60 -LongRunSeconds 60 -Repos "Fix/Py:pytest:main")
    $claimCalls = @(Get-Content -LiteralPath (Join-Path $cn "calls.txt"))
    Check ($claimCalls.Count -ge 2 -and @($claimCalls | Where-Object { $_ -cne "claim=True netrun=True" }).Count -eq 0) ("every gate of the suite phase saw the claim standing and passed -NetRun (" + ($claimCalls -join " | ") + ")")
    $claimLog = [System.IO.File]::ReadAllText((Join-Path $cwr "nightly.log"))
    $iTaken = $claimLog.IndexOf("first claim on the heavy slot taken"); $iOrder = $claimLog.IndexOf(" order: ")
    $iReport = $claimLog.IndexOf("report written: "); $iGone = $claimLog.IndexOf("first claim on the heavy slot released")
    Check ($iTaken -ge 0 -and $iOrder -gt $iTaken) "the claim is taken before the night's first git work"
    Check ($iReport -ge 0 -and $iGone -gt $iReport) "and released only once the report is written (T-0447)"
    $probe = $null
    Check (-not [System.Threading.Mutex]::TryOpenExisting($claimName, [ref]$probe)) "and no claim is left once the net has ended"
    $netSource = [System.IO.File]::ReadAllText((Join-Path $root "tools\NightlyNet.ps1"))
    $iBisect = $netSource.IndexOf('Invoke-NightlyBisect -Ctx $c -Cutoff $cutoff'); $iWritten = $netSource.IndexOf('Write-NightlyNetLine ("report written: " + $file)'); $iRelease = $netSource.IndexOf('$claim.Dispose()')
    Check ($iBisect -ge 0 -and $iWritten -gt $iBisect -and $iRelease -gt $iWritten) "the release stands after the bisects and the report line: the claim covers the bisects (T-0447)"

    # T-0447: THE CLAIM STANDS THROUGH THE BISECTS. The night of 2026-11-08 released it at 04:39:29, two lanes' retry
    # loops took the slot within a second (t0347mu-time, then t0391s9-suites), and the night's only bisect gave up after
    # 900 s. Two nights here: the first green, then two commits, and the second red at the tip, so the second bisects
    # and must run one step at the first commit. Every gate records whether the claim stood when it was called.
    $bn = Join-Path $work "claim-bisect"; [void][System.IO.Directory]::CreateDirectory($bn)
    $bStub = Join-Path $bn "gate.ps1"
    $bClaim = "Local\horde-nightly-claim-" + [guid]::NewGuid().ToString("N")
    [System.IO.File]::WriteAllText((Join-Path $bn "exit.txt"), "0")
    $bStubLines = @(
        'param([string]$Script, [string]$Worktree, [string]$Out, [string]$MinFreeGB, [string]$MinCommitHeadroomGB, [string]$WaitSeconds, [string]$RunSeconds, [string]$ArgsFile)',
        '$c = $null',
        ('$seen = [System.Threading.Mutex]::TryOpenExisting("' + $bClaim + '", [ref]$c); if ($seen) { $c.Dispose() }'),
        'Add-Content -LiteralPath (Join-Path $PSScriptRoot "calls.txt") -Value ("claim=" + $seen + " bisect=" + ($Out -like "*-bisect-*"))',
        '[System.IO.File]::WriteAllText($Out, "")',
        '$code = [int]([System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "exit.txt")).Trim()); if ($Script -ceq "guards-wrap.ps1") { $code = 0 }',
        'Write-Output ("heavy-slot: running " + $Script + " with 5 GB free, output in " + $Out)',
        'Write-Output ("heavy-slot: released exit=" + $code)',
        'exit $code')
    [System.IO.File]::WriteAllText($bStub, ($bStubLines -join "`r`n"))
    $borigin = Join-Path $bn "origin"; [void][System.IO.Directory]::CreateDirectory((Join-Path $borigin "test\lib"))
    [void](Git $borigin @("init", "-q", "-b", "main"))
    [System.IO.File]::WriteAllText((Join-Path $borigin "test\lib\SuiteFiles.ps1"), "function Get-HordeSuiteFiles { param([string]`$Root) return @(Get-ChildItem -LiteralPath (Join-Path `$Root 'test') -Filter 'test-*.ps1' | Sort-Object Name) }`r`nfunction Get-HordeMachineBoundSuites { return @() }`r`n")
    [System.IO.File]::WriteAllText((Join-Path $borigin "test\test-a.ps1"), "exit 0`r`n")
    [void](Git $borigin @("add", "-A")); [void](Git $borigin @("commit", "-q", "-m", "base"))
    $bwr = Join-Path $bn "wr"
    & git.exe clone -q $borigin (Join-Path $bwr "Fix__Bis\tree"); if ($LASTEXITCODE -ne 0) { throw "clone failed" }
    $bArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $root "tools\NightlyNet.ps1"), "-AtTime", (Get-Date).Date.AddHours(23).ToString("s"), "-NoTell", "-BisectReserveMinutes", "30", "-CoverageFloorPercent", "0",
        "-NetClaimName", $bClaim, "-WorkRoot", $bwr, "-HeavySlotScript", $bStub, "-RunSeconds", "60", "-LongRunSeconds", "60", "-Repos", "Fix/Bis:horde:main")
    $o = @(& $exe @($bArgs + @("-MutexName", ("Local\horde-nightly-test-" + [guid]::NewGuid().ToString("N")))))
    Check ($LASTEXITCODE -eq 0) ("T-0447: the first night is green (" + $LASTEXITCODE + ")")
    foreach ($n in @("one", "two")) { [System.IO.File]::WriteAllText((Join-Path $borigin ($n + ".txt")), $n); [void](Git $borigin @("add", "-A")); [void](Git $borigin @("commit", "-q", "-m", $n)) }
    [System.IO.File]::WriteAllText((Join-Path $bn "exit.txt"), "1")
    Remove-Item -LiteralPath (Join-Path $bn "calls.txt") -Force
    $o = @(& $exe @($bArgs + @("-MutexName", ("Local\horde-nightly-test-" + [guid]::NewGuid().ToString("N")))))
    $bCalls = @(Get-Content -LiteralPath (Join-Path $bn "calls.txt"))
    $bBisect = @($bCalls | Where-Object { $_ -like "*bisect=True" })
    Check ($bBisect.Count -ge 1) ("T-0447: the second night bisects (" + ($bCalls -join " | ") + ")")
    Check ($bBisect.Count -ge 1 -and @($bBisect | Where-Object { $_ -cne "claim=True bisect=True" }).Count -eq 0) ("T-0447: every bisect gate saw the claim standing, so no lane's retry loop can take the slot between them (" + ($bBisect -join " | ") + ")")
    $bLog = [System.IO.File]::ReadAllText((Join-Path $bwr "nightly.log"))
    $bLast = $bLog.LastIndexOf("first claim on the heavy slot taken")
    $bTail = $bLog.Substring([Math]::Max(0, $bLast))
    $jBisect = $bTail.IndexOf(" bisect test/test-a.ps1|ps51 -> "); $jReport = $bTail.IndexOf("report written: "); $jGone = $bTail.IndexOf("first claim on the heavy slot released")
    Check ($jBisect -gt 0 -and $jReport -gt $jBisect -and $jGone -gt $jReport) ("T-0447: the log says bisect, then report written, then released (" + $jBisect + " " + $jReport + " " + $jGone + ")")
    # T-0465, through the real net: the stub is red at every commit, last night's tip included (a box change, as
    # on 2026-11-11), so the bisect names no merge.
    Check ($bTail -like "* bisect test/test-a.ps1|ps51 -> base-red *") ("T-0465: the net finds the unit red at last night's tip too (" + (@($bTail -split "`n" | Where-Object { $_ -like "* bisect *" }) -join " | ") + ")")
    $bRep = @(Get-ChildItem -LiteralPath $bwr -Recurse -Filter "*.txt" | Where-Object { $_.Name -like "20*-*.txt" } | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n"
    Check ($bRep -like "*red at last night's tip*" -and $bRep -notlike "*first red at merge*") "T-0465: and its report names no merge"
    $probe = $null
    Check (-not [System.Threading.Mutex]::TryOpenExisting($bClaim, [ref]$probe)) "T-0447: and no claim is left once the net has ended"
    # A plan, and a suite run that names no claim, take none of the machine's.
    $machineClaim = "Global\HordeHeavySlot-NetClaim"; $probe = $null
    if (-not [System.Threading.Mutex]::TryOpenExisting($machineClaim, [ref]$probe)) {
        Check ($netSource -like '*if ($NetClaimName -eq "" -and $AtTime -eq "" -and $HeavySlotScript -eq "") { $NetClaimName = "Global\HordeHeavySlot-NetClaim" }*') "a real run takes the machine's claim, a suite run never does"
    } else { $probe.Dispose(); Check ($true) "(the real net is running now: the machine's claim stands, not this suite's)" }

    # A LONG PYTEST NODE ID NAMES NO FILE. Night 2026-11-23: the net FAILED at 05:43 writing a bisect .nodes file named
    # after the whole node id, 281 characters of path (over MAX_PATH), and no report was written. Here the id is longer
    # than a file name may be at all (255), so the old naming fails in both shells whatever the long-path setting.
    $ln = Join-Path $work "long-node"; [void][System.IO.Directory]::CreateDirectory($ln)
    $lGate = Join-Path $ln "gate.ps1"
    $longNode = "tests/test_" + ("x" * 120) + ".py::Test" + ("Y" * 80) + "::test_" + ("z" * 100)
    [System.IO.File]::WriteAllText((Join-Path $ln "exit.txt"), "0")
    [System.IO.File]::WriteAllText((Join-Path $ln "node.txt"), $longNode)
    [System.IO.File]::WriteAllText($lGate, @'
param([string]$Script, [string]$Worktree, [string]$Out, [string]$MinFreeGB, [string]$MinCommitHeadroomGB, [string]$WaitSeconds, [string]$RunSeconds, [string]$ArgsFile)
$a = @(); if ($ArgsFile -ne "") { $j = [System.IO.File]::ReadAllText($ArgsFile) | ConvertFrom-Json; foreach ($x in $j) { $a += ("" + $x) } }
Add-Content -LiteralPath (Join-Path $PSScriptRoot "calls.txt") -Value ($Script + " " + ($a -join " "))
[System.IO.File]::WriteAllText($Out, "")
$code = [int]([System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "exit.txt")).Trim())
$m = [array]::IndexOf($a, "-Mode"); $mode = $(if ($m -ge 0) { $a[$m + 1] } else { "" })
$i = [array]::IndexOf($a, "-NodesFile")
if ($Script -ceq "guards-wrap.ps1" -or $mode -ceq "flake8") { $code = 0 }
elseif ($mode -ceq "all" -and $i -ge 0) { $body = $(if ($code -eq 0) { "" } else { [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "node.txt")) + "`n" }); [System.IO.File]::WriteAllText($a[$i + 1], $body) }
Write-Output ("heavy-slot: running " + $Script + " with 5 GB free, output in " + $Out)
Write-Output ("heavy-slot: released exit=" + $code)
exit $code
'@)
    $lorigin = Join-Path $ln "origin"; [void][System.IO.Directory]::CreateDirectory($lorigin)
    [void](Git $lorigin @("init", "-q", "-b", "main"))
    [System.IO.File]::WriteAllText((Join-Path $lorigin "a.txt"), "base")
    [void](Git $lorigin @("add", "-A")); [void](Git $lorigin @("commit", "-q", "-m", "base"))
    $lwr = Join-Path $ln "wr"
    & git.exe clone -q $lorigin (Join-Path $lwr "Fix__Ln\tree"); if ($LASTEXITCODE -ne 0) { throw "clone failed" }
    $lArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $root "tools\NightlyNet.ps1"), "-AtTime", (Get-Date).Date.AddHours(23).ToString("s"), "-NoTell", "-BisectReserveMinutes", "30", "-CoverageFloorPercent", "0",
        "-WorkRoot", $lwr, "-HeavySlotScript", $lGate, "-RunSeconds", "60", "-LongRunSeconds", "60", "-Repos", "Fix/Ln:pytest:main")
    $o = @(& $exe @($lArgs + @("-MutexName", ("Local\horde-nightly-test-" + [guid]::NewGuid().ToString("N")))))
    Check ($LASTEXITCODE -eq 0) ("long node: the first night is green (" + $LASTEXITCODE + ")")
    foreach ($n in @("one", "two")) { [System.IO.File]::WriteAllText((Join-Path $lorigin ($n + ".txt")), $n); [void](Git $lorigin @("add", "-A")); [void](Git $lorigin @("commit", "-q", "-m", $n)) }
    [System.IO.File]::WriteAllText((Join-Path $ln "exit.txt"), "1")
    $o = @(& $exe @($lArgs + @("-MutexName", ("Local\horde-nightly-test-" + [guid]::NewGuid().ToString("N")))))
    $lLog = [System.IO.File]::ReadAllText((Join-Path $lwr "nightly.log"))
    $lTail = $lLog.Substring([Math]::Max(0, $lLog.LastIndexOf("window open")))
    Check ($lTail -notlike "*the nightly net FAILED*") ("long node: the second night does not fail on the file name (" + (@($lTail -split "`n" | Where-Object { $_ -like "*FAILED*" }) -join " | ") + ")")
    Check ($lTail -like ("* bisect pytest-node|" + $longNode + " -> *")) "long node: the bisect of the long node ran and logged its verdict under the full id"
    Check ($lTail -like "*report written: *") "long node: and the report is written"
    $lFiles = @(Get-ChildItem -LiteralPath (Join-Path $lwr "runs") -Recurse -File)
    $lLong = @($lFiles | Where-Object { $_.Name.Length -gt 100 })
    Check ($lFiles.Count -gt 0 -and $lLong.Count -eq 0) ("long node: no run file is named longer than 100 characters (" + $lFiles.Count + " files, longest " + (@($lFiles | ForEach-Object { $_.Name.Length } | Sort-Object -Descending) | Select-Object -First 1) + ")")
    $lNodeFiles = @($lFiles | Where-Object { $_.Name -like "*-bisect-*.nodes" })
    Check ($lNodeFiles.Count -ge 1 -and @($lNodeFiles | Where-Object { [System.IO.File]::ReadAllText($_.FullName).Trim() -cne $longNode }).Count -eq 0) ("long node: each bisect .nodes file holds the full node id (" + $lNodeFiles.Count + " files)")
    $lShort = @($lNodeFiles | ForEach-Object { $_.Name } | Sort-Object -Unique)
    Check ($lShort.Count -eq $lNodeFiles.Count) "long node: and the short names do not collide"
    # The stem itself: a tag that fits is unchanged; a long one is cut to the limit with a hash of the WHOLE tag, so two
    # ids that differ only past the cut get different files, and the same id always the same file.
    Check ((Get-HordeNightlyFileStem "Fix_Ln-pytest-all") -ceq "Fix_Ln-pytest-all") "stem: a short tag keeps its name"
    $stA = Get-HordeNightlyFileStem ("R-bisect-12345678-pytest-node|" + $longNode)
    $stB = Get-HordeNightlyFileStem ("R-bisect-12345678-pytest-node|" + $longNode + "x")
    Check ($stA.Length -le 80 -and $stA -like "R-bisect-12345678-pytest-node_tests_*") ("stem: a long tag is at most 80 characters and keeps its readable start (" + $stA + ")")
    Check ($stA -cne $stB) "stem: two long tags that differ only past the cut get different names"
    Check ($stA -ceq (Get-HordeNightlyFileStem ("R-bisect-12345678-pytest-node|" + $longNode))) "stem: the same tag always gives the same name"

    # T-0491: A UNIT WHOSE SLOT WAIT GAVE UP GOES BACK ON THE END OF THE QUEUE, through the real tool. 2026-11-16: a review
    # batch held the slot from 21:56, Universal pytest-all gave up at 22:16 (125) and was never tried again. This gate
    # gives up (125) the FIRST time it is asked for each run, then runs it green; the guards always run.
    $qn = Join-Path $work "requeue"; [void][System.IO.Directory]::CreateDirectory($qn)
    $qGate = Join-Path $qn "gate.ps1"
    [System.IO.File]::WriteAllText($qGate, @'
param([string]$Script, [string]$Worktree, [string]$Out, [string]$MinFreeGB, [string]$MinCommitHeadroomGB, [string]$WaitSeconds, [string]$RunSeconds, [string]$ArgsFile)
$a = @(); if ($ArgsFile -ne "") { $j = [System.IO.File]::ReadAllText($ArgsFile) | ConvertFrom-Json; foreach ($x in $j) { $a += ("" + $x) } }
$key = $Script + " " + ($a -join " ")
$seenF = Join-Path $PSScriptRoot "seen.txt"
$seen = @(); if (Test-Path -LiteralPath $seenF) { $seen = @(Get-Content -LiteralPath $seenF) }
Add-Content -LiteralPath $seenF -Value $key
[System.IO.File]::WriteAllText($Out, "")
if ($Script -cne "guards-wrap.ps1" -and -not ($seen -ccontains $key)) { Write-Output "heavy-slot: gave up after 1 s waiting for the slot; nothing was run"; Write-Output "heavy-slot: released exit=125"; exit 125 }
$i = [array]::IndexOf($a, "-NodesFile"); if ($i -ge 0) { [System.IO.File]::WriteAllText($a[$i + 1], "") }
Write-Output ("heavy-slot: running " + $Script + " with 5 GB free, output in " + $Out); Write-Output "heavy-slot: released exit=0"; exit 0
'@)
    $qorigin = Join-Path $qn "horigin"; [void][System.IO.Directory]::CreateDirectory((Join-Path $qorigin "test\lib"))
    [void](Git $qorigin @("init", "-q", "-b", "main"))
    [System.IO.File]::WriteAllText((Join-Path $qorigin "test\lib\SuiteFiles.ps1"), "function Get-HordeSuiteFiles { param([string]`$Root) return @(Get-ChildItem -LiteralPath (Join-Path `$Root 'test') -Filter 'test-*.ps1' | Sort-Object Name) }`r`nfunction Get-HordeMachineBoundSuites { return @() }`r`n")
    [System.IO.File]::WriteAllText((Join-Path $qorigin "test\test-a.ps1"), "exit 0`r`n")
    [void](Git $qorigin @("add", "-A")); [void](Git $qorigin @("commit", "-q", "-m", "base"))
    $qwr = Join-Path $qn "wr"
    & git.exe clone -q $qorigin (Join-Path $qwr "Fix__Hq\tree"); if ($LASTEXITCODE -ne 0) { throw "clone failed" }
    & git.exe clone -q $origin (Join-Path $qwr "Fix__Pq\tree"); if ($LASTEXITCODE -ne 0) { throw "clone failed" }
    $qNight = (Get-Date).Date.AddHours(23)
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -AtTime $qNight.ToString("s") -NoTell -BisectReserveMinutes 0 -CoverageFloorPercent 0 -MutexName ("Local\horde-nightly-test-" + [guid]::NewGuid().ToString("N")) -WorkRoot $qwr -HeavySlotScript $qGate -RunSeconds 60 -LongRunSeconds 60 -Repos "Fix/Hq:horde:main,Fix/Pq:pytest:main")
    $qc = $LASTEXITCODE
    $qSeen = @(); if (Test-Path -LiteralPath (Join-Path $qn "seen.txt")) { $qSeen = @(Get-Content -LiteralPath (Join-Path $qn "seen.txt")) }
    $qScripts = @($qSeen | ForEach-Object { ($_ -split ' ', 2)[0] })
    $qrf = Join-Path $qwr ("reports\" + $qNight.ToString("yyyy-MM-dd") + ".txt")
    $qr = $(if (Test-Path -LiteralPath $qrf) { [System.IO.File]::ReadAllText($qrf) } else { "" })
    $ql = $(if (Test-Path -LiteralPath (Join-Path $qwr "nightly.log")) { [System.IO.File]::ReadAllText((Join-Path $qwr "nightly.log")) } else { "" })
    Check ($qc -eq 0) ("T-0491: the night ends exit 0 (" + $qc + ")")
    $pyAll = @(for ($k = 0; $k -lt $qSeen.Count; $k++) { if ($qSeen[$k] -like "pytest-wrap.ps1 *-Mode all*") { $k } })
    $flake = @(for ($k = 0; $k -lt $qSeen.Count; $k++) { if ($qSeen[$k] -like "pytest-wrap.ps1 *-Mode flake8*") { $k } })
    Check ($pyAll.Count -eq 2 -and $flake.Count -eq 2) ("T-0491: pytest-all and flake8 that gave up were each tried again, once (" + $pyAll.Count + ", " + $flake.Count + ")")
    Check ($pyAll.Count -eq 2 -and $flake.Count -ge 1 -and $pyAll[1] -gt $flake[0]) ("T-0491: pytest-all's second try comes after the rest of the queue, not at once (" + ($qScripts -join ", ") + ")")
    Check ($ql -like "*Fix/Pq pytest-all gave up waiting for the slot (exit 125): back on the end of the night's queue*") "T-0491: the log says pytest-all went back on the queue"
    Check ($ql -like "*Fix/Hq test/test-a.ps1|ps51 gave up waiting for the slot (exit 125): back on the end of the night's queue*") "T-0491: and so for a suite"
    Check ($qr -like "*REPO Fix/Pq*not run (slot, memory or night ran out): 0*" -and $qr -like "*REPO Fix/Hq*not run (slot, memory or night ran out): 0*") "T-0491: every unit ran on its second try, so none is reported not run"
    Check ($qr -notlike "*the pytest run did not complete*") "T-0491: and the pytest run is not reported incomplete"
    # T-0504: THE SECOND TRY COMES AFTER EVERY REPO'S FIRST PASS, not at the end of its own repo's queue. Nights 11-20 and
    # 11-21: Universal pytest-all gave up on memory at 22:16, was tried again 4 minutes later behind its own 1 other unit
    # with the memory still held, and gave up again; horde's 480 units ran after it. Fix/Hq runs first here (2 units each,
    # ties in the order given), so its suites' second tries must come after Fix/Pq's first tries.
    $hqA = @(for ($k = 0; $k -lt $qSeen.Count; $k++) { if ($qSeen[$k] -like "*test-a.ps1*") { $k } })
    Check ($hqA.Count -eq 4) ("T-0504: each Fix/Hq suite was asked for twice, a give-up and a second try (" + $hqA.Count + ")")
    Check ($hqA.Count -eq 4 -and $pyAll.Count -ge 1 -and $flake.Count -ge 1 -and $hqA[2] -gt $pyAll[0] -and $hqA[2] -gt $flake[0]) ("T-0504: a suite's second try comes after the other repo's first tries, not right behind its own repo (" + ($qScripts -join ", ") + ")")
    # Sent back, but the queue ends (a STOP, made by this gate in the net's work folder, its working directory) before
    # pytest-all's second try: it is counted NOT RUN, never dropped from the count.
    $sGate = Join-Path $qn "stop-gate.ps1"
    [System.IO.File]::WriteAllText($sGate, @'
param([string]$Script, [string]$Worktree, [string]$Out, [string]$MinFreeGB, [string]$MinCommitHeadroomGB, [string]$WaitSeconds, [string]$RunSeconds, [string]$ArgsFile)
[System.IO.File]::WriteAllText($Out, "")
[System.IO.File]::WriteAllText((Join-Path (Get-Location).Path "STOP"), "")
Write-Output "heavy-slot: gave up after 1 s waiting for the slot; nothing was run"; Write-Output "heavy-slot: released exit=125"; exit 125
'@)
    $swr = Join-Path $qn "wr-stop"
    & git.exe clone -q $origin (Join-Path $swr "Fix__Ps\tree"); if ($LASTEXITCODE -ne 0) { throw "clone failed" }
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -AtTime $qNight.ToString("s") -NoTell -BisectReserveMinutes 0 -CoverageFloorPercent 0 -MutexName ("Local\horde-nightly-test-" + [guid]::NewGuid().ToString("N")) -WorkRoot $swr -HeavySlotScript $sGate -RunSeconds 60 -LongRunSeconds 60 -Repos "Fix/Ps:pytest:main")
    $srf = Join-Path $swr ("reports\" + $qNight.ToString("yyyy-MM-dd") + ".txt")
    $sr = $(if (Test-Path -LiteralPath $srf) { [System.IO.File]::ReadAllText($srf) } else { "" })
    Check ($sr -like "*REPO Fix/Ps*not run (slot, memory or night ran out): 2*") ("T-0491: pytest-all sent back whose second try never came is counted not run, with flake8 (" + (@($sr -split "`n" | Where-Object { $_ -like "*not run*" }) -join " | ") + ")")

    # T-0514 (b): A UNIT THAT NO LONGER FITS IS SKIPPED, NOT A BREAK THAT DROPS EVERY UNIT BEHIND IT. Night 2026-11-22:
    # Universal's pytest-all (3600 s, never fitted down) no longer fitted, and the queue's break dropped flake8-critical
    # behind it, which would have fitted. Here the slot wait is set so about 1800 s of the night are left when the queue
    # starts: too few for a 3600 s pytest-all, plenty for a 60 s flake8.
    $fn = Join-Path $work "nofit"; [void][System.IO.Directory]::CreateDirectory($fn)
    $fGate = Join-Path $fn "gate.ps1"
    [System.IO.File]::WriteAllText($fGate, @'
param([string]$Script, [string]$Worktree, [string]$Out, [string]$MinFreeGB, [string]$MinCommitHeadroomGB, [string]$WaitSeconds, [string]$RunSeconds, [string]$ArgsFile)
$a = @(); if ($ArgsFile -ne "") { $j = [System.IO.File]::ReadAllText($ArgsFile) | ConvertFrom-Json; foreach ($x in $j) { $a += ("" + $x) } }
Add-Content -LiteralPath (Join-Path $PSScriptRoot "seen.txt") -Value ($Script + " " + ($a -join " "))
[System.IO.File]::WriteAllText($Out, "")
$i = [array]::IndexOf($a, "-NodesFile"); if ($i -ge 0) { [System.IO.File]::WriteAllText($a[$i + 1], "") }
Write-Output ("heavy-slot: running " + $Script + " with 5 GB free, output in " + $Out); Write-Output "heavy-slot: released exit=0"; exit 0
'@)
    $fwr = Join-Path $fn "wr"
    & git.exe clone -q $origin (Join-Path $fwr "Fix__Pf\tree"); if ($LASTEXITCODE -ne 0) { throw "clone failed" }
    $fWait = [int][math]::Floor(((Get-HordeNightlyRunCutoff -Now $qNight) - (Get-Date)).TotalSeconds) - 1800
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -AtTime $qNight.ToString("s") -NoTell -BisectReserveMinutes 0 -CoverageFloorPercent 0 -MutexName ("Local\horde-nightly-test-" + [guid]::NewGuid().ToString("N")) -WorkRoot $fwr -HeavySlotScript $fGate -SlotWaitSeconds $fWait -RunSeconds 60 -LongRunSeconds 3600 -MinFitSeconds 60 -Repos "Fix/Pf:pytest:main")
    $fc = $LASTEXITCODE
    $fSeen = @(); if (Test-Path -LiteralPath (Join-Path $fn "seen.txt")) { $fSeen = @(Get-Content -LiteralPath (Join-Path $fn "seen.txt")) }
    $frf = Join-Path $fwr ("reports\" + $qNight.ToString("yyyy-MM-dd") + ".txt")
    $fr = $(if (Test-Path -LiteralPath $frf) { [System.IO.File]::ReadAllText($frf) } else { "" })
    $fl = $(if (Test-Path -LiteralPath (Join-Path $fwr "nightly.log")) { [System.IO.File]::ReadAllText((Join-Path $fwr "nightly.log")) } else { "" })
    Check ($fc -eq 0) ("T-0514: the night ends exit 0 (" + $fc + ")")
    Check (@($fSeen | Where-Object { $_ -like "pytest-wrap.ps1 *-Mode all*" }).Count -eq 0) ("T-0514: pytest-all, which no longer fits, is not started (" + ($fSeen -join " | ") + ")")
    Check (@($fSeen | Where-Object { $_ -like "pytest-wrap.ps1 *-Mode flake8*" }).Count -eq 1) ("T-0514: flake8-critical behind it, which fits, still runs (" + ($fSeen -join " | ") + ")")
    Check ($fl -like "*Fix/Pf pytest-all -> not tried, the night has no room for it (needs 3600 s, *") "T-0514: the log says pytest-all was not tried and why"
    Check ($fl -like "*Fix/Pf flake8-critical -> green*") "T-0514: and flake8-critical's verdict is logged"
    Check ($fr -like "*REPO Fix/Pf*not run (slot, memory or night ran out): 1*") ("T-0514: the pytest-all never tried is counted not run, never dropped (" + (@($fr -split "`n" | Where-Object { $_ -like "*not run*" }) -join " | ") + ")")
    Check ($fr -like "*INCOMPLETE: the night ran out before every unit ran*") "T-0514: and the night is reported incomplete, because the night ran out"

    # T-0514 (c): EVERY UNIT NOT TRIED GETS A LINE SAYING WHY. The STOP night above ended with flake8-critical never asked
    # for and pytest-all's second try never come; nightly.log said nothing about either (nights 11-20 to 11-22 the same).
    $sl = $(if (Test-Path -LiteralPath (Join-Path $swr "nightly.log")) { [System.IO.File]::ReadAllText((Join-Path $swr "nightly.log")) } else { "" })
    Check ($sl -like "*Fix/Ps flake8-critical -> not run, STOP file seen*") "T-0514 (c): a unit the STOP kept from its turn is logged not run, with the reason"
    Check ($sl -like "*Fix/Ps pytest-all -> not run, it gave up waiting for the slot and its second try never came: STOP file seen*") "T-0514 (c): and pytest-all sent back whose second try never came, with the reason"
    Check (@([regex]::Matches($fl, 'Fix/Pf pytest-all -> not ')).Count -eq 1) "T-0514 (c): a unit already logged not tried (no room) is not logged twice"

    # T-0514 (a): A MEMORY GIVE-UP IS TRIED AGAIN AS SOON AS A GATE GETS ITS MEMORY, not only after every repo's first
    # pass. Nights 11-20 to 11-22: Universal pytest-all gave up on memory early; memory came back within the hour, but its
    # second try waited behind horde's 480 units and the night ran out first. This gate gives up on memory for the first
    # pytest-all only; the next gate (flake8) gets its memory, so pytest-all must run again before Fix/Bm's suites.
    $an = Join-Path $work "memback"; [void][System.IO.Directory]::CreateDirectory($an)
    $aGate = Join-Path $an "gate.ps1"
    [System.IO.File]::WriteAllText($aGate, @'
param([string]$Script, [string]$Worktree, [string]$Out, [string]$MinFreeGB, [string]$MinCommitHeadroomGB, [string]$WaitSeconds, [string]$RunSeconds, [string]$ArgsFile)
$a = @(); if ($ArgsFile -ne "") { $j = [System.IO.File]::ReadAllText($ArgsFile) | ConvertFrom-Json; foreach ($x in $j) { $a += ("" + $x) } }
$key = $Script + " " + ($a -join " ")
$seenF = Join-Path $PSScriptRoot "seen.txt"
$seen = @(); if (Test-Path -LiteralPath $seenF) { $seen = @(Get-Content -LiteralPath $seenF) }
Add-Content -LiteralPath $seenF -Value $key
[System.IO.File]::WriteAllText($Out, "")
if ($key -like "pytest-wrap.ps1 *-Mode all*" -and @($seen | Where-Object { $_ -like "pytest-wrap.ps1 *-Mode all*" }).Count -eq 0) { Write-Output "heavy-slot: gave up after 1 s waiting for 2.5 GB of free memory (now 1.90); nothing was run"; Write-Output "heavy-slot: released exit=125"; exit 125 }
$i = [array]::IndexOf($a, "-NodesFile"); if ($i -ge 0) { [System.IO.File]::WriteAllText($a[$i + 1], "") }
Write-Output ("heavy-slot: running " + $Script + " with 5 GB free, output in " + $Out); Write-Output "heavy-slot: released exit=0"; exit 0
'@)
    $awr = Join-Path $an "wr"
    & git.exe clone -q $origin (Join-Path $awr "Fix__Am\tree"); if ($LASTEXITCODE -ne 0) { throw "clone failed" }
    & git.exe clone -q $qorigin (Join-Path $awr "Fix__Bm\tree"); if ($LASTEXITCODE -ne 0) { throw "clone failed" }
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\NightlyNet.ps1") -AtTime $qNight.ToString("s") -NoTell -BisectReserveMinutes 0 -CoverageFloorPercent 0 -MutexName ("Local\horde-nightly-test-" + [guid]::NewGuid().ToString("N")) -WorkRoot $awr -HeavySlotScript $aGate -RunSeconds 60 -LongRunSeconds 60 -Repos "Fix/Am:pytest:main,Fix/Bm:horde:main")
    $ac = $LASTEXITCODE
    $aSeen = @(); if (Test-Path -LiteralPath (Join-Path $an "seen.txt")) { $aSeen = @(Get-Content -LiteralPath (Join-Path $an "seen.txt")) }
    $aAll = @(for ($k = 0; $k -lt $aSeen.Count; $k++) { if ($aSeen[$k] -like "pytest-wrap.ps1 *-Mode all*") { $k } })
    $aFl = @(for ($k = 0; $k -lt $aSeen.Count; $k++) { if ($aSeen[$k] -like "pytest-wrap.ps1 *-Mode flake8*") { $k } })
    $aBm = @(for ($k = 0; $k -lt $aSeen.Count; $k++) { if ($aSeen[$k] -like "*test-a.ps1*") { $k } })
    $aLog = $(if (Test-Path -LiteralPath (Join-Path $awr "nightly.log")) { [System.IO.File]::ReadAllText((Join-Path $awr "nightly.log")) } else { "" })
    $arf = Join-Path $awr ("reports\" + $qNight.ToString("yyyy-MM-dd") + ".txt")
    $ar = $(if (Test-Path -LiteralPath $arf) { [System.IO.File]::ReadAllText($arf) } else { "" })
    Check ($ac -eq 0) ("T-0514 (a): the night ends exit 0 (" + $ac + ")")
    Check ($aAll.Count -eq 2 -and $aFl.Count -eq 1 -and $aBm.Count -ge 1 -and $aFl[0] -lt $aBm[0]) ("T-0514 (a): Fix/Am runs first, pytest-all twice (" + (@($aSeen | ForEach-Object { ($_ -split ' ', 2)[0] + $(if ($_ -like "*-Mode all*") { ":all" } elseif ($_ -like "*-Mode flake8*") { ":flake8" } elseif ($_ -like "*test-a.ps1*") { ":test-a" } else { "" }) }) -join ", ") + ")")
    $aGw = @(for ($k = 0; $k -lt $aSeen.Count; $k++) { if ($aSeen[$k] -like "guards-wrap.ps1*") { $k } })
    Check ($aAll.Count -eq 2 -and $aBm.Count -ge 1 -and $aGw.Count -ge 1 -and $aAll[1] -gt $aFl[0] -and $aAll[1] -lt $aGw[0] -and $aAll[1] -lt $aBm[0]) "T-0514 (a): pytest-all's memory give-up is tried again as soon as flake8's gate got its memory, before the other repo's guards and suites"
    Check ($aLog -like "*Fix/Am pytest-all: a gate got its memory, so it is tried again now*") "T-0514 (a): the log says so"
    Check ($ar -like "*REPO Fix/Am*not run (slot, memory or night ran out): 0*" -and $ar -like "*REPO Fix/Bm*not run (slot, memory or night ran out): 0*") "T-0514 (a): and every unit ran"

    # T-0514 (c), BISECTS: A BISECT STEP THAT DID NOT RUN SAYS SO, AND ITS RUNS ARE THE RUNS THAT HAPPENED. Night 11-25: 12
    # Universal bisects, 7 whose gates gave up on memory and 5 stopped by the clock at 05:48:24 without a line; every one
    # said "inconclusive in 1 runs", with 0 run. Two nights each: the first green, the second with one node red.
    $bc = Join-Path $work "bisect-notrun"; [void][System.IO.Directory]::CreateDirectory($bc)
    $bcGate = Join-Path $bc "gate.ps1"
    [System.IO.File]::WriteAllText($bcGate, @'
param([string]$Script, [string]$Worktree, [string]$Out, [string]$MinFreeGB, [string]$MinCommitHeadroomGB, [string]$WaitSeconds, [string]$RunSeconds, [string]$ArgsFile)
$a = @(); if ($ArgsFile -ne "") { $j = [System.IO.File]::ReadAllText($ArgsFile) | ConvertFrom-Json; foreach ($x in $j) { $a += ("" + $x) } }
Add-Content -LiteralPath (Join-Path $PSScriptRoot "calls.txt") -Value ($Script + " " + ($a -join " "))
[System.IO.File]::WriteAllText($Out, "")
$code = [int]([System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "exit.txt")).Trim())
$m = [array]::IndexOf($a, "-Mode"); $mode = $(if ($m -ge 0) { $a[$m + 1] } else { "" })
$i = [array]::IndexOf($a, "-NodesFile")
if ($mode -ceq "flake8") { $code = 0 }
elseif ($mode -ceq "all" -and $i -ge 0) { $body = $(if ($code -eq 0) { "" } else { "tests/test_b.py::test_c`n" }); [System.IO.File]::WriteAllText($a[$i + 1], $body) }
elseif (Test-Path -LiteralPath (Join-Path $PSScriptRoot "giveup.txt")) { Write-Output "heavy-slot: gave up after 1 s waiting for 2.5 GB of free memory (now 1.90); nothing was run"; Write-Output "heavy-slot: released exit=125"; exit 125 }
Write-Output ("heavy-slot: running " + $Script + " with 5 GB free, output in " + $Out)
Write-Output ("heavy-slot: released exit=" + $code)
exit $code
'@)
    function Invoke-BisectNotRunNight { param([string]$Name, [string[]]$Night2Args, [switch]$GiveUp)
        $dir = Join-Path $bc $Name; [void][System.IO.Directory]::CreateDirectory($dir)
        $org = Join-Path $dir "origin"; [void][System.IO.Directory]::CreateDirectory($org)
        [void](Git $org @("init", "-q", "-b", "main")); [System.IO.File]::WriteAllText((Join-Path $org "a.txt"), "base"); [void](Git $org @("add", "-A")); [void](Git $org @("commit", "-q", "-m", "base"))
        $wr = Join-Path $dir "wr"
        & git.exe clone -q $org (Join-Path $wr ("Fix__" + $Name + "\tree")); if ($LASTEXITCODE -ne 0) { throw "clone failed" }
        $base = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $root "tools\NightlyNet.ps1"), "-AtTime", $qNight.ToString("s"), "-NoTell", "-CoverageFloorPercent", "0", "-WorkRoot", $wr, "-HeavySlotScript", $bcGate, "-Repos", ("Fix/" + $Name + ":pytest:main"))
        if (Test-Path -LiteralPath (Join-Path $bc "giveup.txt")) { Remove-Item -LiteralPath (Join-Path $bc "giveup.txt") -Force }
        [System.IO.File]::WriteAllText((Join-Path $bc "exit.txt"), "0")
        [void]@(& $exe @($base + @("-BisectReserveMinutes", "0", "-RunSeconds", "60", "-LongRunSeconds", "60", "-MutexName", ("Local\horde-nightly-test-" + [guid]::NewGuid().ToString("N")))))
        foreach ($n in @("one", "two")) { [System.IO.File]::WriteAllText((Join-Path $org ($n + ".txt")), $n); [void](Git $org @("add", "-A")); [void](Git $org @("commit", "-q", "-m", $n)) }
        [System.IO.File]::WriteAllText((Join-Path $bc "exit.txt"), "1")
        if ($GiveUp) { [System.IO.File]::WriteAllText((Join-Path $bc "giveup.txt"), "") }
        [void]@(& $exe @($base + $Night2Args + @("-MutexName", ("Local\horde-nightly-test-" + [guid]::NewGuid().ToString("N")))))
        $log = [System.IO.File]::ReadAllText((Join-Path $wr "nightly.log"))
        return $log.Substring([Math]::Max(0, $log.LastIndexOf("window open")))
    }
    $gNight = Invoke-BisectNotRunNight -Name "Bg" -GiveUp -Night2Args @("-BisectReserveMinutes", "30", "-RunSeconds", "60", "-LongRunSeconds", "60")
    Check ($gNight -like "*Fix/Bg bisect pytest-node|tests/test_b.py::test_c at ???????? not run: the gate gave up waiting for memory (exit 125)*") ("T-0514 (c): a bisect step whose gate gave up on memory says so (" + (@($gNight -split "`n" | Where-Object { $_ -like "*bisect*" }) -join " | ") + ")")
    Check ($gNight -like "*Fix/Bg bisect pytest-node|tests/test_b.py::test_c -> inconclusive  in 0 runs*") "T-0514 (c): and counts 0 runs, not 1"
    $kWait = [int][math]::Floor(((Get-HordeNightlyRunCutoff -Now $qNight) - (Get-Date)).TotalSeconds) - 1800
    $kNight = Invoke-BisectNotRunNight -Name "Bk" -Night2Args @("-BisectReserveMinutes", "0", "-RunSeconds", "1800", "-LongRunSeconds", "60", "-MinFitSeconds", "60", "-SlotWaitSeconds", ("" + $kWait))
    Check ($kNight -like "*Fix/Bk bisect pytest-node|tests/test_b.py::test_c at ???????? not run: the night has no room for it (needs 1800 s*") ("T-0514 (c): a bisect step the clock stopped says so (" + (@($kNight -split "`n" | Where-Object { $_ -like "*bisect*" }) -join " | ") + ")")
    Check ($kNight -like "*Fix/Bk bisect pytest-node|tests/test_b.py::test_c -> inconclusive  in 0 runs*") "T-0514 (c): and counts 0 runs, not 1"

    # ONLY PYTEST'S SUMMARY NAMES A FAILED TEST (2026-11-05: the night's report listed a captured log line,
    # "ERROR    root:web_reader_dialog.py:2953 ...", as a newly red test). A fake python replays that shape.
    $replay = Join-Path $work "replay"
    [void][System.IO.Directory]::CreateDirectory($replay)
    function Invoke-WrapReplay { param([string[]]$Output, [int]$Code)
        $txt = Join-Path $replay "out.txt"
        [System.IO.File]::WriteAllText($txt, (($Output -join "`r`n") + "`r`n"))
        [System.IO.File]::WriteAllText((Join-Path $replay "python.cmd"), ("@echo off" + "`r`n" + "type """ + $txt + """" + "`r`n" + "exit /b " + $Code + "`r`n"))
        $nf = Join-Path $replay ("n" + [guid]::NewGuid().ToString("N") + ".txt")
        try {
            $env:PATH = $replay + ";" + $oldPath
            [void]@(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\nightly\pytest-wrap.ps1") -Tree $work -Mode all -NodesFile $nf); $wc = $LASTEXITCODE
        } finally { $env:PATH = $oldPath }
        return [pscustomobject]@{ code = $wc; wrote = (Test-Path -LiteralPath $nf); nodes = @($(if (Test-Path -LiteralPath $nf) { Get-Content -LiteralPath $nf | Where-Object { $_.Trim() -ne "" } } else { @() })) }
    }
    $body = @(".F", "=================== ERRORS ===================", "___ ERROR collecting tools/a/test_c.py ___", "E   ModuleNotFoundError: No module named 'tests.test_c'", "=================== FAILURES ===================", "___ test_b ___", "------ Captured log call ------", "ERROR    root:web_reader_dialog.py:2953 could not reconcile the stored credential", "ERROR root:one_space.py:1 a log line with one space", "FAILED to reach the mailbox, printed by the code under test")
    $w = Invoke-WrapReplay -Output ($body + @("========= short test summary info =========", "FAILED tests/test_a.py::test_b - AssertionError: x", "ERROR tools/a/test_c.py", "1 failed, 1 error in 3.00s")) -Code 1
    Check ($w.code -eq 1 -and (@($w.nodes) -join ",") -ceq "tests/test_a.py::test_b,tools/a/test_c.py") ("only the summary's FAILED and ERROR lines are failing nodes, never captured log or printed text (" + (@($w.nodes) -join ",") + ")")
    $w = Invoke-WrapReplay -Output $body -Code 1
    Check ($w.code -eq 70 -and -not $w.wrote) ("exit 1 with no summary names no test: not a verdict, 70, and no nodes file (" + $w.code + ")")
} finally {
    $env:HORDE_HOME = $oldHome
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "the nightly net keeps to its window, lists the day's merges, finds newly red units, bisects to one merge, reports in text a tell can carry, and on a short-memory night fails fast, runs the small repo first, counts only what ran and names who holds the memory, and skips with its reason, never green, a unit whose declared need the night lacks"
