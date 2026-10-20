# CAN `horde status set` WRITE A CARD THE PHONE PANEL WOULD REFUSE - AND DOES IT LEAVE THE OLD ONE ALONE WHEN IT SAYS NO?
#
# fleet/StatusWrite.ps1 builds the whole record from what it is told and asks the panel's own reader
# (ConvertFrom-HordeFleetStatusBytes) whether it would be read. This suite attacks that: every rule the
# reader has is broken ON PURPOSE through the writer (a character outside ASCII, 121 characters, a bare
# pull-request or issue number, a path, a control character, an empty value, an orc that is not one
# capital letter, a waiting-on line past 200, a line break inside a value), and each must be refused
# with the reader's words, with the file's bytes AND modified time exactly as they were and no temp
# file left. Then the good paths: what is written is exactly the record, it reads back written, the
# last-good copy is the same bytes, -DryRun writes nothing, Orc and Lane come from the clean card that
# is there, and the real horde command exits 0, 1 or 2 as it should.
# Every folder is one this suite made in %TEMP%.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "fleet\StatusWrite.ps1")

$work = Join-Path $env:TEMP ("horde-status-set-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$script:n = 0

function New-Lane {
    param([string]$Card = "")
    $script:n++
    $dir = Join-Path (Join-Path $work ("p" + $script:n)) "lane"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    if ($Card -ne "") { [System.IO.File]::WriteAllBytes((Join-Path $dir "status.txt"), $utf8.GetBytes($Card)) }
    return $dir
}
function Snapshot {
    # Every file in the folder: name, length, modified ticks, content hash - to prove "nothing changed".
    param([string]$Dir)
    return (@(Get-ChildItem -LiteralPath $Dir -Force | Sort-Object Name | ForEach-Object {
        $_.Name + "|" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks + "|" + [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($_.FullName))
    }) -join ";")
}
function Names { param([string]$Dir) return (@(Get-ChildItem -LiteralPath $Dir -Force | Sort-Object Name | ForEach-Object { $_.Name }) -join ",") }
function Set-Card {
    # The writer, with any throw turned into a result a check can read (a mutant that makes it throw fails a check).
    param([string]$Dir, [string]$Doing = "writing the status command", [string]$Finished = "read the panel reader", [string]$Blocked = "no", $WaitingOn = $null, [string]$Lane = "", [string]$Orc = "", [switch]$DryRun)
    try {
        return (Invoke-HordeStatusSet -Folder $Dir -Doing $Doing -Finished $Finished -Blocked $Blocked -WaitingOn $WaitingOn -Lane $Lane -Orc $Orc -DryRun:$DryRun)
    } catch {
        return [pscustomobject]@{ ok = $false; written = $false; problems = @("THREW: " + $_.Exception.Message); lines = @(); message = ""; usage = $false }
    }
}
function Says { param($R, [string]$Text) return (@(@(Get-HordeTestMember $R "problems") | Where-Object { "$_".Contains($Text) }).Count -gt 0) }

$cleanCard = "horde-orc-status 1`norc: K`nlane: status writer`ndoing: old doing`nfinished: old finished`nblocked: no`n"

try {

Write-Host ""
Write-Host "--- a good card is written whole, and is the record ---" -ForegroundColor Cyan
$d = New-Lane
$r = Set-Card $d -Orc K -Lane "status writer"
Check ((Get-HordeTestMember $r "ok") -eq $true -and (Get-HordeTestMember $r "written") -eq $true) "a clean card is accepted and written"
Check (([string](Get-HordeTestMember $r "message")) -ceq "status written for K: writing the status command") "one line says who it was written for and what they are doing"
$expect = "horde-orc-status 1`norc: K`nlane: status writer`ndoing: writing the status command`nfinished: read the panel reader`nblocked: no`n"
$got = [System.IO.File]::ReadAllBytes((Join-Path $d "status.txt"))
Check ([System.Convert]::ToBase64String($got) -ceq [System.Convert]::ToBase64String($utf8.GetBytes($expect))) "the bytes are exactly the record: header, six keys in order, LF ends, one trailing LF"
Check ($got.Length -gt 0 -and @($got | Where-Object { $_ -eq 13 -or $_ -gt 127 }).Count -eq 0) "no CR and no byte above 127"
$back = Read-HordeFleetStatusFolder -Path $d
Check ($back.written -eq $true -and $back.orc -ceq "K" -and $back.doing -ceq "writing the status command" -and -not (Get-HordeTestMember $back "waitingOn")) "the panel's reader reads it back as written, and with NO waiting-on line when none was given"
$last = Join-Path $d ".status.last-good.txt"
Check ([System.IO.File]::Exists($last) -and [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($last)) -ceq [System.Convert]::ToBase64String($got)) "the last-good copy holds the same bytes"
Check ((Names $d) -ceq ".status.last-good.txt,status.txt") "nothing else is left in the folder, no temp file"

Write-Host ""
Write-Host "--- a waiting-on line is written only when given ---" -ForegroundColor Cyan
$r = Set-Card $d -WaitingOn "the reviewer, since 2026-10-20 09:00, unblocked by a yes"
$back = Read-HordeFleetStatusFolder -Path $d
Check ((Get-HordeTestMember $r "ok") -eq $true -and (Get-HordeTestMember $back "waitingOn") -ceq "the reviewer, since 2026-10-20 09:00, unblocked by a yes") "given, it is the seventh line and reads back"
$lines = @([System.IO.File]::ReadAllText((Join-Path $d "status.txt")).TrimEnd("`n") -split "`n")
Check ($lines.Count -eq 7 -and $lines[6].StartsWith("waiting on: ")) "seven lines, the last one 'waiting on: ...'"
$r = Set-Card $d
Check (@([System.IO.File]::ReadAllText((Join-Path $d "status.txt")).TrimEnd("`n") -split "`n").Count -eq 6) "written again without it, the card is back to six lines (the card is rewritten whole)"
$sentence = Set-Card $d -Blocked "the relay is down and nothing can be tested"
Check ((Get-HordeTestMember $sentence "ok") -eq $true -and (Read-HordeFleetStatusFolder -Path $d).blocked -eq $true) "a blocked sentence is accepted and the card reads as blocked"

Write-Host ""
Write-Host "--- every rule of the reader, broken on purpose through the writer ---" -ForegroundColor Cyan
$long121 = "x" * 121
$cases = @(
    @{ name = "a character outside ASCII in doing"; args = @{ Doing = ("fixing the caf" + [char]0x00E9 + " menu") }; says = "holds bytes that are not ASCII" }
    @{ name = "a character outside ASCII in the lane (as a byte-order mark would be)"; args = @{ Lane = ([string][char]0xFEFF + "lane") }; says = "holds bytes that are not ASCII" }
    @{ name = "doing of 121 characters"; args = @{ Doing = $long121 }; says = "doing is 121 characters, and the most is 120" }
    @{ name = "finished of 121 characters"; args = @{ Finished = $long121 }; says = "finished is 121 characters, and the most is 120" }
    @{ name = "a bare 'PR 68' in doing"; args = @{ Doing = "reviewing PR 68 today" }; says = "doing holds a bare reference or a path" }
    @{ name = "a bare 'pull request 7' in finished"; args = @{ Finished = "merged pull request 7" }; says = "finished holds a bare reference or a path" }
    @{ name = "an 'issue 12' in doing"; args = @{ Doing = "closing issue 12" }; says = "doing holds a bare reference or a path" }
    @{ name = "a '#12' in finished"; args = @{ Finished = "fixed #12" }; says = "finished holds a bare reference or a path" }
    @{ name = "a path C:\x in doing"; args = @{ Doing = "editing C:\x\file" }; says = "doing holds a bare reference or a path" }
    @{ name = "a control character (bell) in doing"; args = @{ Doing = ("ringing" + [char]7 + " the bell") }; says = "holds a control character" }
    @{ name = "a control character (escape) in blocked"; args = @{ Blocked = ("the " + [char]27 + "[31mred") }; says = "holds a control character" }
    @{ name = "a tab in finished"; args = @{ Finished = ("a" + [char]9 + "b") }; says = "holds a control character" }
    @{ name = "an empty doing"; args = @{ Doing = "" }; says = "line 4 is not 'doing: ...'" }
    @{ name = "an empty finished"; args = @{ Finished = "" }; says = "line 5 is not 'finished: ...'" }
    @{ name = "an empty blocked"; args = @{ Blocked = "" }; says = "line 6 is not 'blocked: ...'" }
    @{ name = "a doing of only spaces"; args = @{ Doing = "   " }; says = "line 4 is not 'doing: ...'" }
    @{ name = "an orc of two letters"; args = @{ Orc = "KK" }; says = "its orc is not one capital letter" }
    @{ name = "a lower case orc"; args = @{ Orc = "k" }; says = "its orc is not one capital letter" }
    @{ name = "a digit for the orc"; args = @{ Orc = "7" }; says = "its orc is not one capital letter" }
    @{ name = "an empty lane value given with a clean card to inherit nothing from"; args = @{ Lane = " " }; says = "line 3 is not 'lane: ...'" }
    @{ name = "a waiting-on line over 200 characters"; args = @{ WaitingOn = ("w" * 195) }; says = "the waiting on line is" }
    @{ name = "a bare reference in waiting on"; args = @{ WaitingOn = "the review of PR 68" }; says = "waiting on holds a bare reference or a path" }
    @{ name = "a control character in waiting on"; args = @{ WaitingOn = ("a" + [char]7 + "b") }; says = "holds a control character" }
    @{ name = "an empty waiting on"; args = @{ WaitingOn = "" }; says = "line 7 is not 'waiting on: ...'" }
    @{ name = "a line break inside doing"; args = @{ Doing = "one`nfinished: two" }; says = "-Doing holds a line break" }
    @{ name = "a carriage return inside finished"; args = @{ Finished = "one`rtwo" }; says = "-Finished holds a line break" }
    @{ name = "a line break inside waiting on"; args = @{ WaitingOn = "one`ntwo" }; says = "-WaitingOn holds a line break" }
)
foreach ($c in $cases) {
    $dir = New-Lane $cleanCard
    # Age the old card so a rewrite could not hide behind "the same second".
    [System.IO.File]::SetLastWriteTimeUtc((Join-Path $dir "status.txt"), [datetime]::new(2026, 10, 1, 8, 0, 0, [System.DateTimeKind]::Utc))
    $before = Snapshot $dir
    $a = @{ Orc = "K"; Lane = "status writer" }
    foreach ($k in $c.args.Keys) { $a[$k] = $c.args[$k] }
    $res = Set-Card $dir @a
    Check ((Get-HordeTestMember $res "ok") -eq $false -and (Says $res $c.says)) ("refused, in the reader's words: " + $c.name)
    Check ((Snapshot $dir) -ceq $before) ("   and the folder is exactly as it was (bytes, modified time, no temp file, no last-good): " + $c.name)
}

Write-Host ""
Write-Host "--- every problem is listed, not the first ---" -ForegroundColor Cyan
$dir = New-Lane
$res = Set-Card $dir -Orc K -Lane "x" -Doing (("PR 68 " + [char]0x00E9 + " ") + ("y" * 120)) -Finished "" -Blocked "no"
Check ((Says $res "holds bytes that are not ASCII") -and (Says $res "doing is") -and (Says $res "bare reference") -and (Says $res "line 5 is not 'finished: ...'")) "four things wrong, four problems named"
Check ((Names $dir) -ceq "") "and nothing was written to the empty lane"
Check ((Get-HordeTestMember $res "usage") -eq $false) "a bad card is not a usage error"

Write-Host ""
Write-Host "--- the boundary the rules draw ---" -ForegroundColor Cyan
$dir = New-Lane
$res = Set-Card $dir -Orc Q -Lane "edge" -Doing ("d" * 120) -Finished ("f" * 120) -WaitingOn ("w" * 188)
Check ((Get-HordeTestMember $res "ok") -eq $true) "CONTROL: doing and finished of exactly 120 and a waiting-on line of exactly 200 are written"
$res = Set-Card (New-Lane) -Orc Q -Lane "edge" -WaitingOn ("w" * 189)
Check ((Get-HordeTestMember $res "ok") -eq $false) "CONTROL: one character more on the waiting-on line is refused"
$res = Set-Card (New-Lane) -Orc Q -Lane "edge" -Doing "plain words only, no references"
Check ((Get-HordeTestMember $res "ok") -eq $true) "CONTROL: plain words are written (so the refusals above are the rule, not the writer failing for another reason)"

Write-Host ""
Write-Host "--- orc and lane come from the clean card, or must be given ---" -ForegroundColor Cyan
$dir = New-Lane $cleanCard
$res = Set-Card $dir -Doing "next thing"
$back = Read-HordeFleetStatusFolder -Path $dir
Check ((Get-HordeTestMember $res "ok") -eq $true -and $back.orc -ceq "K" -and $back.lane -ceq "status writer" -and $back.doing -ceq "next thing") "with neither given, the clean card's orc and lane are kept"
$res = Set-Card $dir -Orc M
Check ((Get-HordeTestMember $res "ok") -eq $true -and (Read-HordeFleetStatusFolder -Path $dir).orc -ceq "M" -and (Read-HordeFleetStatusFolder -Path $dir).lane -ceq "status writer") "a given -Orc wins, the lane is still kept"
$empty = New-Lane
$res = Set-Card $empty
Check ((Get-HordeTestMember $res "ok") -eq $false -and (Get-HordeTestMember $res "usage") -eq $true -and (Says $res "-Orc and -Lane must be given")) "no card and neither given: refused as a usage error naming both"
Check ((Names $empty) -ceq "") "   and nothing was written"
$res = Set-Card $empty -Lane "only lane"
Check ((Get-HordeTestMember $res "usage") -eq $true -and (Says $res "-Orc must be given") -and -not (Says $res "-Lane")) "no card and only -Lane given: it names -Orc alone"
$res = Set-Card $empty -Orc K
Check ((Get-HordeTestMember $res "usage") -eq $true -and (Says $res "-Lane must be given") -and -not (Says $res "-Orc")) "no card and only -Orc given: it names -Lane alone"
$broken = New-Lane ("horde-orc-status 1`norc: K`nlane: x`ndoing: see PR 68`nfinished: y`nblocked: no`n")
$before = Snapshot $broken
$res = Set-Card $broken
Check ((Get-HordeTestMember $res "ok") -eq $false -and (Get-HordeTestMember $res "usage") -eq $true -and (Says $res "bare reference")) "a card that does not read clean is not inherited from, and the reader's reason is shown"
Check ((Snapshot $broken) -ceq $before) "   and the broken card is left as it was"
$res = Set-Card (Join-Path $work "no-such-folder") -Orc K -Lane x
Check ((Get-HordeTestMember $res "ok") -eq $false -and (Says $res "does not exist")) "a folder that does not exist is refused"
Check (-not (Test-Path -LiteralPath (Join-Path $work "no-such-folder"))) "   and is not made"

Write-Host ""
Write-Host "--- -DryRun writes nothing ---" -ForegroundColor Cyan
$dir = New-Lane
$res = Set-Card $dir -Orc K -Lane "dry" -DryRun
Check ((Get-HordeTestMember $res "ok") -eq $true -and (Get-HordeTestMember $res "written") -eq $false -and @(Get-HordeTestMember $res "lines").Count -eq 6) "a clean dry run says so, shows the six lines, and reports nothing written"
Check ((Names $dir) -ceq "") "   and the empty folder is still empty"
$dir = New-Lane $cleanCard
$before = Snapshot $dir
$res = Set-Card $dir -Doing "something else" -DryRun
Check ((Get-HordeTestMember $res "ok") -eq $true -and (Snapshot $dir) -ceq $before) "a dry run over an existing card changes none of its bytes or its time, and writes no last-good"
$res = Set-Card $dir -Doing "see PR 68" -DryRun
Check ((Get-HordeTestMember $res "ok") -eq $false -and (Says $res "bare reference") -and (Snapshot $dir) -ceq $before) "a dry run of a bad card gives the verdict, and still writes nothing"

Write-Host ""
Write-Host "--- a later refusal leaves the earlier good copies alone ---" -ForegroundColor Cyan
$dir = New-Lane
$null = Set-Card $dir -Orc K -Lane "keep" -Doing "first good doing"
$firstLast = [System.IO.File]::ReadAllText((Join-Path $dir ".status.last-good.txt"))
$res = Set-Card $dir -Doing "see PR 68"
Check ((Get-HordeTestMember $res "ok") -eq $false -and [System.IO.File]::ReadAllText((Join-Path $dir "status.txt")) -ceq $firstLast -and [System.IO.File]::ReadAllText((Join-Path $dir ".status.last-good.txt")) -ceq $firstLast) "a refused second write changes neither status.txt nor the last-good copy"
$null = Set-Card $dir -Doing "second good doing"
Check ([System.IO.File]::ReadAllText((Join-Path $dir ".status.last-good.txt")).Contains("second good doing")) "a clean second write moves the last-good copy on"
Check ((Names $dir) -ceq ".status.last-good.txt,status.txt") "and still no temp file is left behind"

Write-Host ""
Write-Host "--- a card past the reader's size cap is refused before anything is written ---" -ForegroundColor Cyan
foreach ($big in @(@{ n = "lane"; a = @{ Lane = ("l" * 9000) } }, @{ n = "blocked"; a = @{ Blocked = ("b" * 9000) } })) {
    $dir = New-Lane $cleanCard
    [System.IO.File]::SetLastWriteTimeUtc((Join-Path $dir "status.txt"), [datetime]::new(2026, 10, 1, 8, 0, 0, [System.DateTimeKind]::Utc))
    $before = Snapshot $dir
    $a = @{ Orc = "K" }
    if (-not $big.a.ContainsKey("Lane")) { $a.Lane = "status writer" }
    foreach ($k in $big.a.Keys) { $a[$k] = $big.a[$k] }
    $res = Set-Card $dir @a
    Check ((Get-HordeTestMember $res "ok") -eq $false -and (Says $res "far more than a record's seven lines")) ("a 9000 character " + $big.n + " is refused in the reader's words")
    Check ((Snapshot $dir) -ceq $before) "   and the good card, its time and the folder are exactly as they were"
    $res = Set-Card $dir @a -DryRun
    Check ((Get-HordeTestMember $res "ok") -eq $false -and (Says $res "far more than a record's seven lines")) ("   and a dry run refuses it too: " + $big.n)
}

Write-Host ""
Write-Host "--- a write that does not read back puts the previous card back ---" -ForegroundColor Cyan
$dir = New-Lane $cleanCard
$prevBytes = [System.IO.File]::ReadAllBytes((Join-Path $dir "status.txt"))
$real = ${function:Read-HordeFleetStatusFolder}
$script:reads = 0; $script:failDir = $dir
function Read-HordeFleetStatusFolder {
    param([string]$Path, [datetime]$Now = [datetime]::UtcNow)
    if ($Path -ceq $script:failDir) { $script:reads++ }
    # the first read of that folder is the writer's look at the current card; the second is its read-back, which fails
    if ($Path -ceq $script:failDir -and $script:reads -eq 2) { return [pscustomobject]@{ folder = "x"; written = $false; problems = @("pretend the file broke a rule"); orc = ""; lane = "" } }
    return (& $real -Path $Path -Now $Now)
}
$res = Set-Card $dir -Doing "a doing that cannot be read back"
Set-Item -Path function:Read-HordeFleetStatusFolder -Value $real
Check ((Get-HordeTestMember $res "ok") -eq $false -and (Says $res "pretend the file broke a rule") -and (Says $res "previous card was put back")) "a failed read-back is reported, and says the previous card was put back"
Check ([System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $dir "status.txt"))) -ceq [System.Convert]::ToBase64String($prevBytes)) "   and status.txt holds the previous bytes again"
Check ((Names $dir) -ceq "status.txt") "   with no last-good written and no temp file"
$dir2 = New-Lane
function Read-HordeFleetStatusFolder {
    param([string]$Path, [datetime]$Now = [datetime]::UtcNow)
    if ($Path -ceq $script:failDir) { $script:reads++ }
    if ($Path -ceq $script:failDir -and $script:reads -eq 2) { return [pscustomobject]@{ folder = "x"; written = $false; problems = @("pretend"); orc = ""; lane = "" } }
    return (& $real -Path $Path -Now $Now)
}
$script:reads = 0; $script:failDir = $dir2
$res = Set-Card $dir2 -Orc K -Lane "fresh"
Set-Item -Path function:Read-HordeFleetStatusFolder -Value $real
Check ((Get-HordeTestMember $res "ok") -eq $false -and -not (Test-Path -LiteralPath (Join-Path $dir2 "status.txt"))) "when there was no previous card, the failed write is taken away again"

Write-Host ""
Write-Host "--- two folders may not claim one letter ---" -ForegroundColor Cyan
$fleet = Join-Path $work "fleetdir"
New-Item -ItemType Directory -Path $fleet | Out-Null
$other = Join-Path $fleet "a-lane"; $mine = Join-Path $fleet "b-lane"; $broken = Join-Path $fleet "c-lane"
foreach ($x in @($other, $mine, $broken)) { New-Item -ItemType Directory -Path $x | Out-Null }
[System.IO.File]::WriteAllBytes((Join-Path $other "status.txt"), $utf8.GetBytes($cleanCard))
[System.IO.File]::WriteAllBytes((Join-Path $broken "status.txt"), $utf8.GetBytes($cleanCard.Replace("blocked: no", "blocked:").Replace("orc: K", "orc: Q")))
$before = Snapshot $mine
$res = Set-Card $mine -Orc K -Lane "second K"
Check ((Get-HordeTestMember $res "ok") -eq $false -and (Says $res "says it is Orc K, and so does another folder (a-lane)")) "an -Orc another folder's clean card already holds is refused, naming that folder"
Check ((Snapshot $mine) -ceq $before) "   and nothing is written"
$res = Set-Card $mine -Orc Q -Lane "uses a broken card's letter"
Check ((Get-HordeTestMember $res "ok") -eq $true) "CONTROL: a letter only a card that does not read clean claims is free"
$res = Set-Card $other -Doing "rewriting my own card"
Check ((Get-HordeTestMember $res "ok") -eq $true) "CONTROL: a folder keeping its own letter is not its own rival"
$res = Set-Card $mine -Orc K -Lane "second K" -DryRun
Check ((Get-HordeTestMember $res "ok") -eq $false -and (Says $res "and so does another folder")) "a dry run refuses it too"

Write-Host ""
Write-Host "--- the real horde command ---" -ForegroundColor Cyan
$dir = New-Lane
$cli = Invoke-HordeCliProcess -Root $root -HordeArgs @("status", "set", "-Doing", "driving the real command", "-Finished", "wrote the writer", "-Blocked", "no", "-Orc", "K", "-Lane", "status writer", "-Folder", $dir)
Check ($cli.code -eq 0 -and $cli.out -match "status written for K: driving the real command") "exit 0 and the one-line answer"
Check ((Read-HordeFleetStatusFolder -Path $dir).written -eq $true) "the file it wrote reads clean"
$cli = Invoke-HordeCliProcess -Root $root -HordeArgs @("status", "set", "-Doing", "fixing PR 68", "-Finished", "x", "-Blocked", "no", "-Folder", $dir)
Check ($cli.code -eq 1 -and $cli.out -match "NOT written" -and $cli.out -match "bare reference or a path") "a card the reader would refuse: exit 1 and the reader's words"
Check ((Read-HordeFleetStatusFolder -Path $dir).doing -ceq "driving the real command") "   and the card on disk is still the good one"
$cli = Invoke-HordeCliProcess -Root $root -HordeArgs @("status", "set", "-Doing", "only this", "-Folder", $dir)
Check ($cli.code -eq 2 -and $cli.out -match "-Finished, -Blocked") "leaving out -Finished and -Blocked is a usage error naming them (exit 2)"
$cli = Invoke-HordeCliProcess -Root $root -HordeArgs @("status", "set", "-Doing", "a", "-Finished", "b", "-Blocked", "no", "-Folder", (New-Lane))
Check ($cli.code -eq 2 -and $cli.out -match "-Orc and -Lane") "no card and no -Orc/-Lane: exit 2, naming both"
$cli = Invoke-HordeCliProcess -Root $root -HordeArgs @("status", "set", "-Doing", "a", "-Finished", "b", "-Blocked", "no", "-Folder", (Join-Path $work "nope"))
Check ($cli.code -eq 2 -and $cli.out -match "does not exist") "a folder that is not there: exit 2"
$cli = Invoke-HordeCliProcess -Root $root -HordeArgs @("status", "frobnicate")
Check ($cli.code -eq 2) "a verb that is not 'set': exit 2"
$cli = Invoke-HordeCliProcess -Root $root -HordeArgs @("status", "set", "-Doing", "dry one", "-Finished", "b", "-Blocked", "no", "-DryRun", "-Folder", $dir)
Check ($cli.code -eq 0 -and $cli.out -match "dry run" -and (Read-HordeFleetStatusFolder -Path $dir).doing -ceq "driving the real command") "-DryRun: exit 0, the record shown, the card unchanged"
$cli = Invoke-HordeCliProcess -Root $root -HordeArgs @("status", "set", "-Doing", "under seven", "-Finished", "b", "-Blocked", "no", "-Folder", $dir) -Shell (Join-Path $env:ProgramFiles "PowerShell\7\pwsh.exe")
Check ($cli.code -eq 0 -and (Read-HordeFleetStatusFolder -Path $dir).doing -ceq "under seven") "and the same command works under PowerShell 7"

} finally {
    if ((Split-Path -Leaf $work) -match '\Ahorde-status-set-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force }
}

Complete-HordeSuite -Success "horde status set writes a card the panel reads or writes nothing, lists every problem in the reader's words, and keeps the last good copy"
