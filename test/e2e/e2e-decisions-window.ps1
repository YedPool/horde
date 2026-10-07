# END TO END: `horde decisions open` - a real window on a real list, opened where nobody sees it, and
# held to WHAT ITS PAGE DREW.
#
# The user of this command is a person with a list of questions waiting for them, and the session that
# keeps that list. This scenario is the window's first hour: the list holds 22 questions when the
# window is opened with two of them unfolded and one Orc picked; the page says what it drew, line by
# line, and that is held against the list; a 23rd question is asked at the command line and appears
# without a reload, with the reader's unfolded questions still unfolded; the window is closed; a
# second window, real and visible to Windows but standing where no screen is, is asked to come
# forward by a second `open`; and a home that cannot be written is refused in plain words. Every step
# is the shipped horde.ps1 run as its own process.
#
# WHAT IS READ IS THE PAGE'S OWN REPORT (decisions/Window.ps1, WHAT THE PAGE DREW): the number and the
# text of every question line as they stand in the page's elements. A count could not see a question
# drawn twice under two headings while another was drawn nowhere, which is what a group named
# __proto__ did to the earlier page; here two such groups hold two questions each.
#
# NO WINDOW IS SEEN AND NO KEYBOARD IS TAKEN. -Hidden opens far outside every screen and out of the
# taskbar. -OffScreen opens an ordinary window, visible to Windows and with a taskbar button for the
# seconds it lives, at the same far place. Neither is ever activated by this scenario; what the
# second `open` makes Windows do to the first is measured and printed, whatever it is.
#
# NO TERMINAL IS INVOLVED. Neither window is attached, and the fleet's registry is pointed at a
# folder of this scenario's that does not exist. The window standing beside a terminal window is the
# terminal host's own scenario (hosts/<name>/test/e2e/), in a terminal that scenario starts.
#
# HORDE_HOME is a folder this scenario made and removes; the real store is listed before and after and
# must not have changed (CONTRIBUTING 9). The 22 questions are written through the operations in this
# process, because 22 runs of the add command would take over a minute on a slowed machine and add
# nothing: the add command has its own scenario (test/e2e/e2e-decisions.ps1), and the 23rd, the one
# this scenario is about, is added at the real command line. It costs nothing: no agent session.
#
# NOT CHECKED HERE, because nothing here can click or scroll a page: a click on a line, the menu, and
# that a redraw keeps the reader's scroll place. Unfolding and picking are driven by the command's
# own flags; that they survive a redraw is checked.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "test\lib\WindowProbe.ps1")

$script:work = Join-Path $env:TEMP ("horde-window-e2e-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$hordeHome = Join-Path $script:work "home"
$store = Join-Path $hordeHome "store\decisions"
$report = Join-Path $script:work "report.json"
$picture = Join-Path $script:work "window.png"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$childEnv = @{ HORDE_HOME = $hordeHome; WEZFLEET_ROOT = (Join-Path $script:work "no-fleet"); PSModulePath = $null }

function Get-RealStoreListing {
    $real = Join-Path (Join-Path (Join-Path "$env:USERPROFILE" ".horde") "store") "decisions"
    if (-not (Test-Path -LiteralPath $real)) { return "(no store)" }
    return (@(Get-ChildItem -LiteralPath $real -Force | Sort-Object Name | ForEach-Object { $_.Name + "|" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks }) -join ";")
}
$realBefore = Get-RealStoreListing
function Get-EngineProcesses {
    # The web engine's processes that belong to this scenario's windows: those started with its work folder.
    return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { "$($_.CommandLine)" -like ("*" + $script:work + "*") -and $_.ProcessId -ne $PID -and "$($_.Name)" -ne "powershell.exe" })
}
function Get-ListNow {
    # The list as the operations answer it now, in this process: what the page is held against.
    $keep = $env:HORDE_HOME
    try { $env:HORDE_HOME = $hordeHome; return @((Invoke-HordeDecision -Operation "list" -Request @{ state = "all" }).value.questions) } finally { $env:HORDE_HOME = $keep }
}
function Test-Whole { param($Css, $Ratio) if ($null -eq $Css -or $null -eq $Ratio) { return $false }; $device = [double]$Css * [double]$Ratio; return ([Math]::Abs($device - [Math]::Round($device)) -lt 0.01) }
function Get-Foreground { return [HordeProbe.Native]::GetForegroundWindow().ToInt64() }

$open = $null; $far = $null
try {

Write-Host ""
Write-Host "=== a list of 22 questions, two groups named like built-in members, and three Orcs' status files ===" -ForegroundColor Cyan
$keepHome = $env:HORDE_HOME
try {
    $env:HORDE_HOME = $hordeHome
    . (Join-Path $root "decisions\Operations.ps1")
    $groups = @("Unblocks work now", "The closing behaviour", "Security and accounts", "The study")
    for ($n = 1; $n -le 22; $n++) {
        $orc = "Orc " + [string][char](65 + ($n % 4))
        $waiting = @(); if ($n % 4 -ne 0) { $waiting = @($orc + " (step " + $n + ")") }
        $asked = $orc; if ($n % 11 -eq 0) { $asked = "the warchief" }
        $group = $groups[($n - 1) % 4]
        if ($n -eq 19 -or $n -eq 20) { $group = "__proto__" }
        if ($n -eq 21 -or $n -eq 22) { $group = "constructor" }
        $question = [ordered]@{ title = ("Should step " + $n + " of the plan go ahead as it is written?"); kind = "yes-no"; whatItIs = ("Step " + $n + " is ready and waits only for a yes. <script>this is shown as text</script>"); yesMeans = ("Step " + $n + " is done today."); recommendation = "yes"; group = $group; askedBy = $asked; waiting = $waiting }
        # One group carries a note of background, as real lists do: the page keeps it folded behind a word.
        if ($n -eq 2) { $question["groupNote"] = "Settled already: she asks after 12 seconds of quiet." }
        $added = Invoke-HordeDecision -Operation "add" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = $question }
        if ($added.state -cne "known" -or $added.value.outcome -cne "done" -or $added.value.number -ne $n) { throw ("question " + $n + " was not added: " + $added.state + " " + $added.reason) }
    }
} finally { $env:HORDE_HOME = $keepHome }
$records = @(Get-ChildItem -LiteralPath $store -File)
Check ($records.Count -eq 22) "the store holds 22 questions, numbered 1 to 22"
$orcs = Join-Path $script:work "orcs"
foreach ($o in @(@{ folder = "alpha"; lines = @("horde-orc-status 1", "orc: A", "lane: the first lane", "doing: Building the second step of the plan", "finished: The first step of the plan", "blocked: No") },
                 @{ folder = "beta"; lines = @("horde-orc-status 1", "orc: B", "lane: the second lane", "doing: Waiting for an answer", "finished: The measurements", "blocked: A machine it needs is switched off") },
                 @{ folder = "gamma"; lines = @("horde-orc-status 1", "orc: C", "lane: the third lane") })) {
    New-Item -ItemType Directory -Path (Join-Path $orcs $o.folder) -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path (Join-Path $orcs $o.folder) "status.txt"), (($o.lines -join "`n") + "`n"), $utf8)
}
New-Item -ItemType Directory -Path (Join-Path $hordeHome "settings") -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $hordeHome "settings\fleet.json"), (ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = 1; settings = [ordered]@{ statusFolder = $orcs } }) -Compress), $utf8)

Write-Host ""
Write-Host "=== the window is opened, and its page says what it drew ===" -ForegroundColor Cyan
$clock = [System.Diagnostics.Stopwatch]::StartNew()
$open = Start-HordeProbeCommand -Root $root -HordeArgs @("decisions", "open", "-Hidden", "-Report", $report, "-Picture", $picture, "-Unfold", "3,19", "-Orc", "B") -Env $childEnv
$first = Wait-HordeProbeReport -Path $report -Process $open.process -Seconds 120 -Until { param($r) $null -ne $r.drawn -and @($r.drawn.lines).Count -eq 22 -and $r.drawn.fleet.entries -ge 3 -and $r.drawn.fleet.picked -ceq "orc:B" -and @($r.drawn.lines | Where-Object { $_.open }).Count -eq 2 }
$secondsToLines = [Math]::Round($clock.Elapsed.TotalSeconds, 1)
$drawn = $first.drawn
Check ($null -ne $drawn -and @($drawn.lines).Count -eq 22) ("the page reports, through the bridge, the 22 question lines it drew (" + $secondsToLines + " s after the command was started; " + $first.secondsToFirstReport + " s from the surface being asked to the first report)")
Check (-not $open.process.HasExited) "the command is still running: it stays until the window is closed"
Check ($first.pid -eq $open.process.Id -and $first.handle -gt 0 -and $first.schemaVersion -eq 2) "the report is this command's own, and names its window"
$list = @(Get-ListNow)
$want = @($list | Sort-Object number | ForEach-Object { "" + $_.number + "|" + $_.title }) -join "`n"
$got = @($drawn.lines | Sort-Object { [int]$_.n } | ForEach-Object { $_.n + "|" + $_.t }) -join "`n"
Check ($list.Count -eq 22 -and $got -ceq $want) "THE NUMBER AND THE TEXT OF EVERY LINE DRAWN are the list's: each of the 22 questions once, under its own number, with its own title"
Check (@($drawn.lines | Group-Object n | Where-Object { $_.Count -ne 1 }).Count -eq 0) "no number is drawn twice"
$heads = @($drawn.headings)
Check ((@($heads | ForEach-Object { $_.t + "=" + $_.count }) -join ", ") -ceq "Unblocks work now=5, The closing behaviour=5, Security and accounts=4, The study=4, __proto__=2, constructor=2") ("the headings, in the order their first question comes, each with its count (" + (@($heads | ForEach-Object { $_.t + "=" + $_.count }) -join ", ") + ")")
Check ((@($heads | ForEach-Object { "[" + $_.note + "]" }) -join "") -ceq "[][folded][][][][]") ("a group's note of background is there and FOLDED until the reader asks for it, so that a note of several lines does not stand between the questions; a group with none says none (" + (@($heads | ForEach-Object { "[" + $_.note + "]" }) -join "") + ")")
foreach ($named in @(@{ group = "__proto__"; numbers = "19,20" }, @{ group = "constructor"; numbers = "21,22" })) {
    $at = -1; for ($i = 0; $i -lt $heads.Count; $i++) { if ($heads[$i].t -ceq $named.group) { $at = $i } }
    $under = @($drawn.lines | Where-Object { $_.g -eq $at } | ForEach-Object { $_.n }) -join ","
    Check ($at -ge 0 -and $under -ceq $named.numbers) ("the group named " + $named.group + " keeps both its questions: " + $named.numbers + " are drawn under it, each once (" + $under + ")")
}
$byHead = @($drawn.lines | Group-Object g | ForEach-Object { "" + $_.Count }) -join ","
Check ($byHead -ceq "5,5,4,4,2,2") "and every heading has under it as many lines as it says"
Check ((@($drawn.lines | Where-Object { $_.open } | ForEach-Object { $_.n }) -join ",") -ceq "3,19") "questions 3 and 19 are unfolded, as the command asked, and no other"
$sub = @($drawn.sub)
Check ((@($sub | ForEach-Object { $_.n }) -join ",") -ceq "3.1,3.2,3.3,3.4,3.5,3.6,19.1,19.2,19.3,19.4,19.5,19.6") ("an unfolded question's lines are sub-numbered under its own number (" + (@($sub | ForEach-Object { $_.n }) -join ",") + ")")
Check ($sub[0].t -ceq "What it is: Step 3 is ready and waits only for a yes. <script>this is shown as text</script>" -and $sub[1].t -ceq "Yes means: Step 3 is done today." -and $sub[2].t -ceq "Recommended: yes" -and $sub[3].t -ceq "Waiting: Orc D (step 3)" -and $sub[4].t -ceq "Asked by: Orc D" -and $sub[5].t -ceq "Answered with: yes or no") "in order: what it is, what yes means, the recommendation, who waits, who asked, how it is answered; and markup in a question is drawn as the text it is"
Check ((@($drawn.lines | Where-Object { $_.n -ceq "1" })[0].s) -ceq " - Recommended: yes - Orc B waiting") "a folded line carries its muted suffix: the recommendation and who is waiting, by name and without the reason in brackets, which the unfolded line gives in full"
Check ($drawn.counts.open -eq 22 -and $drawn.counts.waiting -eq 17 -and $drawn.counts.other -eq 0 -and $first.title -ceq "Open decisions: 22, 17 waiting") ("22 open, 17 with someone waiting; the window's title says the same (" + $first.title + ")")

Write-Host ""
Write-Host "=== the fleet line, and an Orc picked: the others' questions are dimmed, never hidden ===" -ForegroundColor Cyan
Check ($drawn.fleet.open -eq $true -and $drawn.fleet.picked -ceq "orc:B") "the fleet line is unfolded and Orc B is picked, as the command asked"
Check ($drawn.fleet.head -ceq "Fleet: A, B blocked, waiting on you (6), gamma no status written, C no status written, waiting on you (6), D no status written, waiting on you (5)") ("the folded line: each Orc, its state in words, and how many questions wait on the reader for it (" + $drawn.fleet.head + ")")
Check ($drawn.fleet.entries -eq 5 -and $drawn.fleet.written -eq 2 -and $drawn.fleet.notRead -eq 0 -and @($drawn.fleet.rows).Count -eq 5) "five entries - the three folders, and the two Orcs the list names that no good record speaks for; two records were good"
Check ($drawn.fleet.rows[3] -ceq "Orc C: no status written (no folder of status records is this Orc's)") "an Orc the list names and no record speaks for is no status written, and never a guess"
Check ($drawn.fleet.rows[0] -like "Orc A (the first lane): Building the second step of the plan. Last finished: The first step of the plan. (written *" -and $drawn.fleet.rows[0] -notlike "*Blocked*") "Orc A's line: its lane, what it is doing, what it last finished; its 'blocked: No' is not blocked"
Check ($drawn.fleet.rows[1] -like "Orc B (the second lane): Waiting for an answer. Last finished: The measurements. Blocked: A machine it needs is switched off. (written *") "Orc B's line says what blocks it"
Check ($drawn.fleet.rows[2] -like "gamma: no status written (has 3 lines, and a record is 6*") "a malformed record is no status written, with what was wrong, and none of its fields"
$mine = @($list | Where-Object { @($_.waiting | Where-Object { $_ -clike "Orc B*" }).Count -gt 0 -or "$($_.askedBy)" -clike "Orc B*" } | ForEach-Object { "" + $_.number })
$bright = @($drawn.lines | Where-Object { -not $_.dim } | Sort-Object { [int]$_.n } | ForEach-Object { $_.n })
Check ($mine.Count -ge 1 -and ($bright -join ",") -ceq ($mine -join ",")) ("the questions Orc B waits for or asked are drawn as they were (" + ($bright -join ",") + ")")
Check (@($drawn.lines | Where-Object { $_.dim }).Count -eq (22 - $mine.Count) -and @($drawn.lines).Count -eq 22) "and every other question is DIMMED and still drawn: picking an Orc hides nothing"

Write-Host ""
Write-Host "=== sharp letters: whole device pixels at the scale this window is drawn at ===" -ForegroundColor Cyan
$text = $drawn.text
Write-Host ("  measured: a question line is drawn at " + $text.fontPx + " CSS pixels on a line of " + $text.linePx + ", small marks at " + $text.smallFontPx + " on " + $text.smallLinePx + ", at a scale of " + $text.ratio + " (" + ([double]$text.fontPx * [double]$text.ratio) + " and " + ([double]$text.linePx * [double]$text.ratio) + " device pixels)") -ForegroundColor DarkGray
Check ((Test-Whole $text.fontPx $text.ratio) -and (Test-Whole $text.linePx $text.ratio)) "the computed size of a question line's letters, and its line height, are each a whole number of the screen's own pixels"
Check ((Test-Whole $text.smallFontPx $text.ratio) -and (Test-Whole $text.smallLinePx $text.ratio)) "and so are the small marks'"
Check (-not (Test-Whole 13.3 1.5) -and -not (Test-Whole 14 1.25) -and (Test-Whole 14.4 1.25) -and (Test-Whole 14 1.5)) "CONTROL: the same check fails 14 pixels at one and a quarter times, and passes the 14.4 the page draws there"
Check ([Math]::Abs([double]$text.fontPx - 14) -lt 0.5 -and [Math]::Abs([double]$text.linePx - 22) -lt 0.5 -and [Math]::Abs([double]$text.smallFontPx - 12) -lt 0.5) "they are the settings' 14 on 22 and 12, moved by less than half a pixel"
Check ("$($text.weight)" -ceq "400" -and "$($text.family)" -clike '"Segoe UI Variable Text", "Segoe UI", system-ui, sans-serif*') ("a question line is weight 400, in the family list the module's setting gives (" + $text.family + ")")
Check ($drawn.foot -clike "Read-only: answering here comes next.*") "the last line says answering comes next"
Check ($drawn.notice -ceq "Standing free: it was opened hidden, and a hidden window stands beside nothing" -and $first.attachment.attached -eq $false) "a hidden window stands beside nothing, and its page says so"
Check ($first.refused -eq 0 -and $first.reportsRefused -eq 0 -and @($first.errors).Count -eq 0 -and @($first.findings).Count -eq 0 -and $drawn.left.lines -eq 0 -and $drawn.left.sub -eq 0) "the page asked for nothing off the list, nothing failed inside the window, and the report left nothing out"
$seen = Get-HordeProbeWindow -Handle ([long]$first.handle)
Check ($seen.exists -and $seen.processId -eq $open.process.Id) "the window exists and belongs to the command's process"
Check ($seen.left -le -30000 -and $seen.top -le -30000 -and -not $seen.foreground) ("it stands far outside every screen and does not have the keyboard (at " + $seen.left + "," + $seen.top + ")")
Check ($seen.owner -ne 0) "it is out of the taskbar: Windows shows no button for a window that has an owner"
$engine = @(Get-EngineProcesses)
$open.process.Refresh()
Write-Host ("  measured: the hosting process holds " + [Math]::Round($open.process.WorkingSet64 / 1MB) + " MB and the engine's " + $engine.Count + " processes " + [Math]::Round((($engine | Measure-Object WorkingSetSize -Sum).Sum) / 1MB) + " MB") -ForegroundColor DarkGray
Check ($engine.Count -ge 1) "CONTROL: the web engine's processes for this window are found, so their absence at the end means something"

Write-Host ""
Write-Host "=== a picture of the page, saved while nobody can see the window ===" -ForegroundColor Cyan
$pictured = Wait-HordeProbeReport -Path $report -Process $open.process -Seconds 60 -Until { param($r) $r.picture.saved -eq $true }
Check ($pictured.picture.asked -eq $true -and $pictured.picture.saved -eq $true -and (Test-Path -LiteralPath $picture -PathType Leaf)) "the picture -Picture named was saved, and the report says so"
$png = [System.IO.File]::ReadAllBytes($picture)
Check ($png.Length -gt 20000 -and (($png[0..7] | ForEach-Object { $_.ToString("X2") }) -join "") -ceq "89504E470D0A1A0A") ("it is a PNG, and not an empty one (" + $png.Length + " bytes)")
Add-Type -AssemblyName System.Drawing
$bitmap = New-Object System.Drawing.Bitmap($picture)
try {
    $colours = New-Object "System.Collections.Generic.HashSet[int]"
    for ($y = 0; $y -lt $bitmap.Height; $y += 7) { for ($x = 0; $x -lt $bitmap.Width; $x += 5) { [void]$colours.Add($bitmap.GetPixel($x, $y).ToArgb()) } }
    $box = (Get-HordeProbeWindow -Handle ([long]$first.handle))
    Check ($bitmap.Width -ge 300 -and $bitmap.Width -le ($box.right - $box.left) -and $bitmap.Height -ge 400 -and $bitmap.Height -le ($box.bottom - $box.top)) ("it is the size of the page inside the window (" + $bitmap.Width + " by " + $bitmap.Height + ", in a window of " + ($box.right - $box.left) + " by " + ($box.bottom - $box.top) + ")")
    Check ($colours.Count -gt 24) ("and it is not blank: letters in ink, muted and dimmed give it many colours (" + $colours.Count + " distinct in the pixels sampled)")
} finally { $bitmap.Dispose() }
Check (@(Get-ChildItem -LiteralPath $script:work -File | Where-Object { $_.Name -like "window.png*" }).Count -eq 1) "no half-written copy is left beside it"

Write-Host ""
Write-Host "=== a 23rd question is asked at the command line, and the page shows it without a reload ===" -ForegroundColor Cyan
$q23 = Join-Path $script:work "q23.json"
[System.IO.File]::WriteAllText($q23, '{"title":"Is a question asked while the window is open shown in it?","kind":"yes-no","whatItIs":"Asked at the command line, with the window already showing 22.","recommendation":"yes","group":"__proto__","askedBy":"Orc B","waiting":["Orc B"]}', $utf8)
$clock.Restart()
$add = Invoke-HordeCliProcess -Root $root -HordeArgs @("decisions", "add", "-File", $q23) -Env @{ HORDE_HOME = $hordeHome }
Check ($add.code -eq 0 -and $add.out -like "*Added question 23: Is a question asked while the window is open shown in it?*") "the add command adds question 23"
$after = Wait-HordeProbeReport -Path $report -Process $open.process -Seconds 90 -Until { param($r) $null -ne $r.drawn -and @($r.drawn.lines).Count -eq 23 }
$new = @($after.drawn.lines | Where-Object { $_.n -ceq "23" })
Check ($new.Count -eq 1 -and $new[0].t -ceq "Is a question asked while the window is open shown in it?" -and $new[0].dim -eq $false) ("the page draws line 23 with its own text (" + [Math]::Round($clock.Elapsed.TotalSeconds, 1) + " s after the add command was started), not dimmed: it is Orc B's")
$list = @(Get-ListNow)
Check ((@($after.drawn.lines | Sort-Object { [int]$_.n } | ForEach-Object { $_.n + "|" + $_.t }) -join "`n") -ceq (@($list | Sort-Object number | ForEach-Object { "" + $_.number + "|" + $_.title }) -join "`n")) "and all 23 lines drawn are again the list's, number by number and text by text"
Check ((@($after.drawn.headings | Where-Object { $_.t -ceq "__proto__" })[0].count) -eq 3) "the group named __proto__ now holds three"
Check ((@($after.drawn.lines | Where-Object { $_.open } | ForEach-Object { $_.n }) -join ",") -ceq "3,19" -and $after.drawn.fleet.open -eq $true -and $after.drawn.fleet.picked -ceq "orc:B") "THE REDRAW FOLDED NOTHING: 3 and 19 are still unfolded, the fleet line still unfolded, Orc B still picked"
Check (@($after.drawn.lines | Where-Object { $_.dim }).Count -eq 16 -and @($after.drawn.lines | Where-Object { -not $_.dim }).Count -eq 7) "and it kept the dimming: Orc B's seven questions as they were, the other sixteen dimmed and drawn"
Check ($after.pushes -ge 1 -and $after.changes -ge 1 -and $after.watching -eq $true -and $after.watchFailures -eq 0) "because the store's folder is watched and the new list was pushed to the page"
Check ($after.handle -eq $first.handle -and $after.pid -eq $first.pid) "in the same window of the same process: nothing was reloaded or reopened"
Check ($after.title -ceq "Open decisions: 23, 18 waiting" -and $after.drawn.fleet.head -clike "*B blocked, waiting on you (7)*") ("the title and the fleet line's count follow (" + $after.title + ")")
Check ($after.refused -eq 0 -and @($after.errors).Count -eq 0) "still nothing refused and nothing failed"

Write-Host ""
Write-Host "=== the window is closed ===" -ForegroundColor Cyan
$closed = Close-HordeProbeWindow -Process $open.process -Handle ([long]$after.handle) -Seconds 40
Check ($closed.asked -and $closed.exited -and -not $closed.killed) "asked to close as its close button would, the command ends by itself"
Check ($closed.code -eq 0) ("and exits 0 (" + $closed.code + ")")
$said = $open.out.Result
Check ($said -like "*Opening the decisions window, standing free (not attached: it was opened hidden*" -and $said -like "*The decisions window was closed.*" -and $open.err.Result.Trim() -ceq "") "it said that it was opening, why it stood free, and that it was closed; and nothing on the error stream"
$gone = $false
for ($i = 0; $i -lt 60; $i++) { if (@(Get-EngineProcesses).Count -eq 0) { $gone = $true; break }; Start-Sleep -Milliseconds 250 }
Check $gone "the web engine's processes for this window are gone with it"

Write-Host ""
Write-Host "=== open twice: a real first window, visible to Windows and standing where no screen is ===" -ForegroundColor Cyan
$farReport = Join-Path $script:work "far.json"
$far = Start-HordeProbeCommand -Root $root -HordeArgs @("decisions", "open", "-OffScreen", "-Report", $farReport) -Env $childEnv
$shown = Wait-HordeProbeReport -Path $farReport -Process $far.process -Seconds 120 -Until { param($r) $r.pid -eq $far.process.Id -and $null -ne $r.drawn -and @($r.drawn.lines).Count -eq 23 }
Check ($null -ne $shown -and @($shown.drawn.lines).Count -eq 23) "opened again, it is a new window on the same list: closing the first lost nothing"
$farWindow = Get-HordeProbeWindow -Handle ([long]$shown.handle)
Check ($farWindow.exists -and $farWindow.visible -and $farWindow.processId -eq $far.process.Id) "this window is visible to Windows: an ordinary shown window, not a hidden one"
Check ($farWindow.owner -eq 0) "it is owned by nothing, so it has its place in the taskbar"
Check ($farWindow.left -le -30000 -and $farWindow.top -le -30000) ("and it stands where no screen is (at " + $farWindow.left + "," + $farWindow.top + ")")
Check (-not $farWindow.foreground -and $shown.askedForward -eq 0) "it did not take the keyboard as it appeared, and nobody has asked it to come forward"
Check ($shown.drawn.notice -ceq "Standing free: it was opened where no screen is, and stands beside nothing there") "its page says why it stands free"
$foregroundBefore = Get-Foreground
$second = Invoke-HordeCliProcess -Root $root -HordeArgs @("decisions", "open") -Env @{ HORDE_HOME = $hordeHome; WEZFLEET_ROOT = (Join-Path $script:work "no-fleet") }
Check ($second.code -eq 0 -and $second.out.Trim() -ceq "The decisions window is already open; it was asked to come forward.") ("the second open returns at once, exit 0, with its one plain sentence (" + $second.code + ": " + $second.out.Trim() + ")")
$asked = Wait-HordeProbeReport -Path $farReport -Process $far.process -Seconds 30 -Until { param($r) $r.askedForward -ge 1 }
Check ($asked.askedForward -eq 1) "THE FIRST WINDOW'S OWN EVIDENCE: it counts that it was asked to come forward, once"
Start-Sleep -Milliseconds 600
$farAfter = Get-HordeProbeWindow -Handle ([long]$shown.handle)
$foregroundAfter = Get-Foreground
$took = [bool]$farAfter.foreground
Write-Host ("  measured: after being asked, the first window is " + $(if ($took) { "THE FOREGROUND WINDOW: Windows gave it the keyboard" } else { "NOT the foreground window: Windows did not raise a window asked forward by a program that is not in front" }) + "; the foreground window " + $(if ($foregroundAfter -eq $foregroundBefore) { "is the one it was before" } else { "changed" })) -ForegroundColor DarkGray
Check ($farAfter.exists -and $farAfter.visible -and $farAfter.left -le -30000 -and $asked.handle -eq $shown.handle -and $asked.pid -eq $shown.pid -and -not $far.process.HasExited) "and it is still the one window, where it was: no second window was made"
Check ($took -or $foregroundAfter -eq $foregroundBefore) "what had the keyboard before still has it, unless Windows gave it to the window that was asked forward: nothing else was activated"
$closedFar = Close-HordeProbeWindow -Process $far.process -Handle ([long]$shown.handle) -Seconds 40
Check ($closedFar.exited -and $closedFar.code -eq 0 -and -not $closedFar.killed) "that window closes as the first did, exit 0"
Check ($far.out.Result -like "*Opening the decisions window, standing free (not attached: it was opened where no screen is*") "it said why it stood free"

Write-Host ""
Write-Host "=== a home that cannot be written is refused at once, in plain words ===" -ForegroundColor Cyan
$badHome = Join-Path $script:work "bad-home"
New-Item -ItemType Directory -Path $badHome | Out-Null
[System.IO.File]::WriteAllText((Join-Path $badHome "cache"), "a file where the folder of the window's own files would be", $utf8)
$clock.Restart()
$refusedOpen = Invoke-HordeCliProcess -Root $root -HordeArgs @("decisions", "open", "-Hidden") -Env @{ HORDE_HOME = $badHome; WEZFLEET_ROOT = (Join-Path $script:work "no-fleet") }
$refusedSeconds = [Math]::Round($clock.Elapsed.TotalSeconds, 1)
$refusedWords = "" + $refusedOpen.out
Check ($refusedOpen.code -ne 0 -and $refusedWords -like "*the decisions window could not be shown: the folder the window keeps its own files in cannot be made or written to*so the window was not opened*") ("it fails with words a person can act on (" + $refusedSeconds + " s)")
Check ($refusedWords -notlike "*0x8*" -and $refusedWords -notlike "*Server execution failed*" -and $refusedSeconds -lt 60) "not with the engine's own error after a minute's wait"
Check (@(Get-EngineProcesses).Count -eq 0) "and no engine process was started for it"

Write-Host ""
Write-Host "=== the state left behind ===" -ForegroundColor Cyan
$names = @(Get-ChildItem -LiteralPath $store -File | Sort-Object Name | ForEach-Object { $_.Name })
Check ($names.Count -eq 23 -and @($records | Where-Object { $names -cnotcontains $_.Name }).Count -eq 0) "the store holds 23 records, the 22 it began with among them: the window wrote none"
$others = @(Get-ChildItem -LiteralPath $hordeHome -Recurse -File | ForEach-Object { $_.FullName.Substring($hordeHome.Length + 1) } | Where-Object { $_ -notlike "store\decisions\*" -and $_ -notlike "cache\decisions-window\*" })
Check (($others -join ",") -ceq "settings\fleet.json") ("under the home, besides the store and the engine's own profile, only the setting this scenario wrote (" + ($others -join ", ") + ")")
Check (Test-Path -LiteralPath (Join-Path $hordeHome "cache\decisions-window") -PathType Container) "the engine's profile is under the home's cache, where the command's header says it is"
$statusAfter = @(Get-ChildItem -LiteralPath $orcs -Recurse -File | ForEach-Object { $_.Name }) -join ";"
Check ($statusAfter -ceq "status.txt;status.txt;status.txt") "the Orcs' folders hold their three status files and nothing else: the fleet line only read them"

} finally {
    foreach ($held in @($open, $far)) { if ($null -ne $held -and -not $held.process.HasExited) { try { $held.process.Kill() } catch { } } }
    Start-Sleep -Milliseconds 500
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-window-e2e-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) {
        for ($i = 0; $i -lt 20 -and (Test-Path -LiteralPath $script:work); $i++) { try { Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction Stop } catch { Start-Sleep -Milliseconds 500 } }
    }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the scenario's temp folder is removed"
Check ((Get-RealStoreListing) -ceq $realBefore) "the real store under the user profile is exactly as it was before the scenario"

Complete-HordeSuite -Success "a real window draws the real list line for line, shows a new question without a reload, comes when asked, and writes nothing to the list"
