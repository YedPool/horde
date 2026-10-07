# END TO END: `horde decisions open` - a real window on a real list, opened where nobody sees it.
#
# The user of this command is a person with a list of questions waiting for them, and the session that
# keeps that list. This scenario is the window's first hour: the list holds 22 questions when the
# window is opened; a second `open` finds the first; the session asks a 23rd question at the command
# line, and the page shows 23 rows without being reloaded; the window is closed. Every step is the
# shipped horde.ps1 run as its own process, and what is checked is what that window says it shows -
# the page itself reports, through the bridge, how many rows it has drawn - and the state left behind.
#
# THE WINDOW IS REAL AND UNSEEN. -Hidden opens it far outside every screen and out of the taskbar,
# and it never asks for the keyboard. The scenario checks that it is where it should be: not on screen.
#
# NO TERMINAL IS INVOLVED. A hidden window stands beside nothing, and the fleet's registry is pointed
# at an empty folder of this scenario's. The window standing beside a terminal window is the terminal
# host's own scenario (hosts/<name>/test/e2e/), in a terminal that scenario starts.
#
# HORDE_HOME is a folder this scenario made and removes; the real store is listed before and after and
# must not have changed (CONTRIBUTING 9). The 22 questions are written through the operations in this
# process, because 22 runs of the add command would take over a minute on a slowed machine and add
# nothing: the add command has its own scenario (test/e2e/e2e-decisions.ps1), and the 23rd, the one
# this scenario is about, is added at the real command line. It costs nothing: no agent session.
#
# NOT CHECKED HERE, because nothing here can click or scroll a page: that a redraw keeps an opened row
# open and the reader's place. decisions/page/list.js keeps both by design; no test presses a row.

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
    # The web engine's processes that belong to this scenario's window: those started with its home.
    return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { "$($_.CommandLine)" -like ("*" + $hordeHome + "*") -and $_.ProcessId -ne $PID -and "$($_.Name)" -ne "powershell.exe" })
}

$open = $null
try {

Write-Host ""
Write-Host "=== a list of 22 questions, and three Orcs' status files ===" -ForegroundColor Cyan
$keepHome = $env:HORDE_HOME
try {
    $env:HORDE_HOME = $hordeHome
    . (Join-Path $root "decisions\Operations.ps1")
    $groups = @("unblocks work now", "the closing behaviour", "security and accounts", "the study")
    for ($n = 1; $n -le 22; $n++) {
        $orc = "Orc " + [string][char](65 + ($n % 4))
        $waiting = @(); if ($n % 4 -ne 0) { $waiting = @($orc + " (step " + $n + ")") }
        $asked = $orc; if ($n % 11 -eq 0) { $asked = "the warchief" }
        $question = [ordered]@{ title = ("Should step " + $n + " of the plan go ahead as it is written?"); kind = "yes-no"; whatItIs = ("Step " + $n + " is ready and waits only for a yes. <script>this is shown as text</script>"); yesMeans = ("Step " + $n + " is done today."); recommendation = "yes"; group = $groups[($n - 1) % 4]; askedBy = $asked; waiting = $waiting }
        $added = Invoke-HordeDecision -Operation "add" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = $question }
        if ($added.state -cne "known" -or $added.value.outcome -cne "done" -or $added.value.number -ne $n) { throw ("question " + $n + " was not added: " + $added.state + " " + $added.reason) }
    }
} finally { $env:HORDE_HOME = $keepHome }
Check (@(Get-ChildItem -LiteralPath $store -File).Count -eq 22) "the store holds 22 questions, numbered 1 to 22"
$orcs = Join-Path $script:work "orcs"
foreach ($o in @(@{ folder = "alpha"; lines = @("horde-orc-status 1", "orc: A", "lane: the first lane", "doing: Building the second step of the plan", "finished: The first step of the plan", "blocked: no") },
                 @{ folder = "beta"; lines = @("horde-orc-status 1", "orc: B", "lane: the second lane", "doing: Waiting for an answer", "finished: The measurements", "blocked: A machine it needs is switched off") },
                 @{ folder = "gamma"; lines = @("horde-orc-status 1", "orc: C", "lane: the third lane") })) {
    New-Item -ItemType Directory -Path (Join-Path $orcs $o.folder) -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path (Join-Path $orcs $o.folder) "status.txt"), (($o.lines -join "`n") + "`n"), $utf8)
}
New-Item -ItemType Directory -Path (Join-Path $hordeHome "fleet") -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $hordeHome "fleet\status-source.json"), (ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = 1; folder = $orcs }) -Compress), $utf8)

Write-Host ""
Write-Host "=== the window is opened, and its page says what it drew ===" -ForegroundColor Cyan
$clock = [System.Diagnostics.Stopwatch]::StartNew()
$open = Start-HordeProbeCommand -Root $root -HordeArgs @("decisions", "open", "-Hidden", "-Report", $report, "-Picture", $picture) -Env $childEnv
$first = Wait-HordeProbeReport -Path $report -Process $open.process -Seconds 120 -Until { param($r) $null -ne $r.rendered -and $r.rendered.rows -eq 22 -and $r.rendered.entries -ge 5 }
$secondsToRows = [Math]::Round($clock.Elapsed.TotalSeconds, 1)
Check ($null -ne $first -and $null -ne $first.rendered -and $first.rendered.rows -eq 22) ("the page reports, through the bridge, that it has drawn 22 rows (" + $secondsToRows + " s after the command was started)")
Check (-not $open.process.HasExited) "the command is still running: it stays until the window is closed"
Check ($first.pid -eq $open.process.Id -and $first.handle -gt 0) "the report is this command's own, and names its window"
Check ($first.rendered.open -eq 22 -and $first.rendered.closed -eq 0 -and $first.rendered.waiting -eq 17 -and $first.rendered.filter -ceq "open" -and $first.rendered.expanded -eq 0) "22 open, 17 with someone waiting, none closed, no row opened, the all-open filter"
Check ($first.title -ceq "Open decisions: 22, 17 waiting") ("the window's title shows the counts (" + $first.title + ")")
Check ($first.rendered.entries -eq 7 -and $first.rendered.written -eq 2) ("the fleet panel shows seven entries: the three Orc folders, the two Orcs the list names and no good status file speaks for, and the two entries that are not Orcs; two status files were good, and the malformed one is not counted as written (" + $first.rendered.entries + ", " + $first.rendered.written + ")")
Check ($first.attachment.attached -eq $false -and $first.attachment.reason -like "it was opened hidden*") "a hidden window stands beside nothing, and says so"
Check ($first.refused -eq 0 -and @($first.errors).Count -eq 0) "the page asked for nothing off the list, and nothing failed inside the window"
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
# What a person would see, so that it can be looked at without that person. The window stands far
# outside every screen; the engine draws the page all the same, and its own capture saves it.
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
    Check ($colours.Count -gt 24) ("and it is not blank: text, headers and marks give it many colours (" + $colours.Count + " distinct in the pixels sampled)")
} finally { $bitmap.Dispose() }
Check (@(Get-ChildItem -LiteralPath $script:work -File | Where-Object { $_.Name -like "window.png*" }).Count -eq 1) "no half-written copy is left beside it"

Write-Host ""
Write-Host "=== a second open finds the first ===" -ForegroundColor Cyan
$second = Invoke-HordeCliProcess -Root $root -HordeArgs @("decisions", "open", "-Hidden") -Env @{ HORDE_HOME = $hordeHome; WEZFLEET_ROOT = (Join-Path $script:work "no-fleet") }
Check ($second.code -eq 0 -and $second.out -like "*The decisions window is already open; it was asked to come forward.*") "a second open returns at once, exit 0, and says the window is already open"
Check (-not $open.process.HasExited -and (Read-HordeProbeReport -Path $report).handle -eq $first.handle) "and the first window is still the window: no second one was made"

Write-Host ""
Write-Host "=== a 23rd question is asked at the command line, and the page shows it without a reload ===" -ForegroundColor Cyan
$q23 = Join-Path $script:work "q23.json"
[System.IO.File]::WriteAllText($q23, '{"title":"Is a question asked while the window is open shown in it?","kind":"yes-no","whatItIs":"Asked at the command line, with the window already showing 22.","recommendation":"yes","group":"the window","askedBy":"Orc A","waiting":["Orc A"]}', $utf8)
$clock.Restart()
$add = Invoke-HordeCliProcess -Root $root -HordeArgs @("decisions", "add", "-File", $q23) -Env @{ HORDE_HOME = $hordeHome }
Check ($add.code -eq 0 -and $add.out -like "*Added question 23: Is a question asked while the window is open shown in it?*") "the add command adds question 23"
$after = Wait-HordeProbeReport -Path $report -Process $open.process -Seconds 90 -Until { param($r) $null -ne $r.rendered -and $r.rendered.rows -eq 23 }
Check ($null -ne $after.rendered -and $after.rendered.rows -eq 23 -and $after.rendered.open -eq 23 -and $after.rendered.waiting -eq 18) ("the page reports 23 rows (" + [Math]::Round($clock.Elapsed.TotalSeconds, 1) + " s after the add command was started)")
Check ($after.pushes -ge 1 -and $after.changes -ge 1 -and $after.watching -eq $true) "because the store's folder is watched and the new list was pushed to the page"
Check ($after.handle -eq $first.handle -and $after.pid -eq $first.pid) "in the same window of the same process: nothing was reloaded or reopened"
Check ($after.title -ceq "Open decisions: 23, 18 waiting") ("and the title follows (" + $after.title + ")")
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
$third = Start-HordeProbeCommand -Root $root -HordeArgs @("decisions", "open", "-Hidden", "-Report", $report) -Env $childEnv
$again = Wait-HordeProbeReport -Path $report -Process $third.process -Seconds 120 -Until { param($r) $r.pid -eq $third.process.Id -and $null -ne $r.rendered -and $r.rendered.rows -eq 23 }
Check ($null -ne $again -and $again.pid -eq $third.process.Id -and $again.rendered.rows -eq 23) "opened again, it is a new window on the same list: closing lost nothing"
$closedAgain = Close-HordeProbeWindow -Process $third.process -Handle ([long]$again.handle) -Seconds 40
Check ($closedAgain.exited -and $closedAgain.code -eq 0) "and that one closes as the first did"

Write-Host ""
Write-Host "=== the state left behind ===" -ForegroundColor Cyan
$names = @(Get-ChildItem -LiteralPath $store -File | Sort-Object Name | ForEach-Object { $_.Name })
Check (($names -join ",") -ceq ((1..23 | ForEach-Object { $_.ToString("D10") + ".json" }) -join ",")) "the store holds 23 records: the window wrote none"
$others = @(Get-ChildItem -LiteralPath $hordeHome -Recurse -File | ForEach-Object { $_.FullName.Substring($hordeHome.Length + 1) } | Where-Object { $_ -notlike "store\decisions\*" -and $_ -notlike "cache\decisions-window\*" })
Check (($others -join ",") -ceq "fleet\status-source.json") ("under the home, besides the store and the engine's own profile, only the configuration this scenario wrote (" + ($others -join ", ") + ")")
Check (Test-Path -LiteralPath (Join-Path $hordeHome "cache\decisions-window") -PathType Container) "the engine's profile is under the home's cache, where the command's header says it is"
$statusAfter = @(Get-ChildItem -LiteralPath $orcs -Recurse -File | ForEach-Object { $_.Name + "|" + $_.Length }) -join ";"
Check ($statusAfter -ceq "status.txt|" + (Get-Item (Join-Path $orcs "alpha\status.txt")).Length + ";status.txt|" + (Get-Item (Join-Path $orcs "beta\status.txt")).Length + ";status.txt|" + (Get-Item (Join-Path $orcs "gamma\status.txt")).Length) "the Orcs' folders hold their three status files and nothing else: the panel only read them"

} finally {
    foreach ($held in @($open, $third)) { if ($null -ne $held -and -not $held.process.HasExited) { try { $held.process.Kill() } catch { } } }
    Start-Sleep -Milliseconds 500
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-window-e2e-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) {
        for ($i = 0; $i -lt 20 -and (Test-Path -LiteralPath $script:work); $i++) { try { Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction Stop } catch { Start-Sleep -Milliseconds 500 } }
    }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the scenario's temp folder is removed"
Check ((Get-RealStoreListing) -ceq $realBefore) "the real store under the user profile is exactly as it was before the scenario"

Complete-HordeSuite -Success "a real window shows the real list, shows a new question without a reload, and writes nothing to the list"
