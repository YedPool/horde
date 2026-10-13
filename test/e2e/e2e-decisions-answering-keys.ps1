# END TO END: answering in the decisions window WITH REAL KEYS - a real window on a real list, opened
# where nobody sees it, given the keyboard as a window is, and its keys pressed BY THE ENGINE'S OWN
# INPUT, not by a script inside the page.
#
# The scenario beside this one (e2e-decisions-answering.ps1) acts its keys out inside the page: a
# script hands the page's own handlers an event it made. That cannot see what the engine does with a
# key before and after the page's handler: a real Tab moves the caret to the next thing on the page
# unless the handler stops it, a real Enter in an answer's field adds a line unless the handler stops
# it, and a script's event is not one the engine trusts. HERE EVERY KEY IS ONE THE ENGINE MADE: the
# command's -Probe file names keys, the window hands them to its surface's own input (surfaces/Port.ps1,
# probeInput; decisions/Window.ps1, -Probe), and the page counts the key presses the engine itself
# vouches for (answer.realKeys), which this scenario holds against the number it pressed.
#
# THE KEYBOARD, GIVEN TO THE PAGE BY THE ENGINE, AND TAKEN FROM NOBODY. The engine is asked to tell
# the page it has the keyboard (the surface's input, a step { focus }): the page gets the very event
# the engine sends it when its window is switched to, from the engine and not from a script, and puts
# the caret in the first unanswered field. Windows is told nothing and no window is activated; the
# foreground window of the desktop is read before and after and must be the same.
# WHY NOT WINDOWS' OWN ACTIVATION: this scenario first posted the message Windows sends a window it
# activates (WM_ACTIVATE) to its own hidden window. Run once, 2026-10-07: the form handed its focus to
# the view, the view to the engine, the page said it had the keyboard and the caret was in question
# 1's field - the whole chain a person's click sets off, seen working - AND THE HIDDEN WINDOW BECAME
# THE DESKTOP'S FOREGROUND WINDOW, which took the keyboard from the person at the machine. It is not
# done again: a check may not do that.
#
# NO KEY IS SENT TO THE DESKTOP, NO WINDOW IS SEEN AND NO FOREGROUND IS TAKEN. The window is -Hidden:
# real, shown to Windows, standing where no screen is. NO TERMINAL IS INVOLVED. HORDE_HOME is a
# folder this scenario made and removes; the real store is listed before and after.
#
# NOT PROVED HERE, and only a person at the keyboard can (without his keyboard being taken): that a
# click on the window, or switching to it, has Windows activate it and the window hand its focus down
# to the engine (seen once, as said above, and not repeated), and that a key pressed on the keyboard
# reaches the engine's window (the engine's input is entered one step after that).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "test\lib\MessengerPins.ps1")
. (Join-Path $root "test\lib\WindowProbe.ps1")

$script:work = Join-Path $env:TEMP ("horde-answer-keys-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$hordeHome = Join-Path $script:work "home"
$store = Join-Path $hordeHome "store\decisions"
$report = Join-Path $script:work "report.json"
$script:probeFile = Join-Path $script:work "probe.json"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$childEnv = @{ HORDE_HOME = $hordeHome; WEZFLEET_ROOT = (Join-Path $script:work "no-fleet"); PSModulePath = $null }
$script:probeN = 0
$script:pressed = 0
$script:open = $null

function Get-RealStoreListing {
    $real = Join-Path (Join-Path (Join-Path "$env:USERPROFILE" ".horde") "store") "decisions"
    if (-not (Test-Path -LiteralPath $real)) { return "(no store)" }
    return (@(Get-ChildItem -LiteralPath $real -Force | Sort-Object Name | ForEach-Object { $_.Name + "|" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks }) -join ";")
}
$realBefore = Get-RealStoreListing
function Get-Shown {
    param([int]$Number)
    $keep = $env:HORDE_HOME
    try { $env:HORDE_HOME = $hordeHome; return (Invoke-HordeDecision -Operation "show" -Request @{ number = $Number }).value.question } finally { $env:HORDE_HOME = $keep }
}
function Get-Said { param([int]$Number) return @((Get-Shown -Number $Number).thread.messages) }
function Write-Whole {
    param([string]$Path, [string]$Text)
    $temp = $Path + ".tmp"
    [System.IO.File]::WriteAllText($temp, $Text, $utf8)
    if (Test-Path -LiteralPath $Path -PathType Leaf) { [System.IO.File]::Replace($temp, $Path, [NullString]::Value) } else { [System.IO.File]::Move($temp, $Path) }
}
function Key { param([string]$Name, [switch]$Shift, [switch]$Ctrl) return [pscustomobject]([ordered]@{ key = $Name; shift = [bool]$Shift; ctrl = [bool]$Ctrl }) }
function Typed { param([string]$Text) return [pscustomobject]([ordered]@{ text = $Text }) }
function Keyboard { param([bool]$Given) return [pscustomobject]([ordered]@{ focus = $Given }) }
function Step { param([string]$Do, $Q = $null)
    $s = [ordered]@{ do = $Do }
    if ($null -ne $Q) { $s["q"] = [int]$Q }
    if ($Do -ceq "sleep") { $s["ms"] = 500 }
    return [pscustomobject]$s
}
function Get-KeyPresses {
    # How many key presses the engine makes of these: one for a key and one more for each of Shift
    # and Ctrl held with it; one for each small letter, digit and space of a text, and none for the
    # rest of it, which is put in as text.
    param([object[]]$Keys)
    $n = 0
    foreach ($k in @($Keys)) {
        if ($null -ne $k.PSObject.Properties["key"]) { $n += 1 + [int][bool]$k.shift + [int][bool]$k.ctrl }
        elseif ($null -ne $k.PSObject.Properties["text"]) { $n += @($k.text.ToCharArray() | Where-Object { ("" + $_) -cmatch '\A[a-z0-9 ]\z' }).Count }
    }
    return $n
}
function Send-Probe {
    # Real keys first (the surface's own input), then steps inside the page; wait until the page
    # reports having been through them with nothing sent still unanswered. Returns that report.
    param([object[]]$Keys = @(), [object[]]$Steps = @(), [int]$Seconds = 120)
    $script:probeN++
    $script:pressed += (Get-KeyPresses -Keys $Keys)
    $n = $script:probeN
    Write-Whole -Path $script:probeFile -Text (ConvertTo-Json -InputObject ([ordered]@{ n = $n; keys = @($Keys); steps = @($Steps) }) -Depth 5 -Compress)
    $script:wantProbe = $n
    return (Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds $Seconds -Until { param($r) $null -ne $r.drawn -and $null -ne $r.drawn.answer -and $r.drawn.answer.probe -eq $script:wantProbe -and $r.drawn.answer.pending -eq 0 })
}
function Get-Line { param($Report, [int]$Number) return @($Report.drawn.lines | Where-Object { $_.n -ceq ("" + $Number) })[0] }
function Get-Foreground { return [HordeProbe.Native]::GetForegroundWindow().ToInt64() }

try {

# THE MESSENGERS ARE PINNED in the home every horde child here uses: the window loads every messenger,
# and one may find a real program to post through by itself (test/lib/MessengerPins.ps1). The fleet's
# registry is a folder of this scenario's that does not exist (WEZFLEET_ROOT), so no seat is read.
$pins = @(Set-HordeTestMessengerPins -Root $root -HordeHome $hordeHome)
Check ($pins.Count -ge 1 -and @($pins | Where-Object { -not (Test-Path -LiteralPath (Join-Path $hordeHome ("settings\messenger-" + $_ + ".json")) -PathType Leaf) }).Count -eq 0) ("PIN: every messenger that has a pin is pinned in this home, so no horde started here can post for real (" + ($pins -join ", ") + ")")

Write-Host ""
Write-Host "=== a list of 10 questions; question 4 has no recommendation ===" -ForegroundColor Cyan
$keepHome = $env:HORDE_HOME
try {
    $env:HORDE_HOME = $hordeHome
    . (Join-Path $root "decisions\Operations.ps1")
    # Stamped a minute apart with question 1 the LATEST: the list is newest first (2026-10-12), so
    # they stand in the order of their numbers, which is how this scenario walks them.
    $when = [datetime]::SpecifyKind([datetime]"2026-01-01T09:00:00", [System.DateTimeKind]::Utc)
    for ($n = 1; $n -le 10; $n++) {
        $question = [ordered]@{ title = ("Should step " + $n + " of the plan go ahead as it is written?"); kind = "yes-no"; whatItIs = ("Step " + $n + " is ready and waits only for a yes."); group = "Unblocks work now"; askedBy = ("Orc " + [string][char](65 + ($n % 4))) }
        if ($n -ne 4) { $question["recommendation"] = @("yes.", "no, not in this pass", "yes, as it is written and no further")[$n % 3] }
        $added = Invoke-HordeDecision -Operation "add" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = $question } -Now $when.AddMinutes(30 - $n)
        if ($added.state -cne "known" -or $added.value.outcome -cne "done" -or $added.value.number -ne $n) { throw ("question " + $n + " was not added: " + $added.state + " " + $added.reason) }
    }
} finally { $env:HORDE_HOME = $keepHome }
Check (@(Get-ChildItem -LiteralPath $store -File).Count -eq 10) "the store holds 10 questions"

Write-Host ""
Write-Host "=== the window, opened where nobody sees it: no keyboard yet, no caret, no key ===" -ForegroundColor Cyan
$script:open = Start-HordeProbeCommand -Root $root -HordeArgs @("decisions", "open", "-Hidden", "-Report", $report, "-Probe", $script:probeFile) -Env $childEnv
$first = Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds 150 -Until { param($r) $null -ne $r.drawn -and @($r.drawn.lines).Count -eq 10 -and $null -ne $r.drawn.answer }
Check ($null -ne $first -and $null -ne $first.drawn -and @($first.drawn.lines).Count -eq 10 -and $first.drawn.answer.fields -eq 10) "the page drew 10 questions, each with its field"
$window = [long]$first.handle
$seen = Get-HordeProbeWindow -Handle $window
Check ($seen.exists -and $seen.visible -and $seen.processId -eq $script:open.process.Id -and $seen.left -le -30000) ("it is a real window of the command's own process, shown to Windows, standing where no screen is (" + $seen.left + "," + $seen.top + ")")
Check ($first.drawn.answer.focus -ceq "" -and $first.drawn.answer.hasFocus -eq $false -and $first.drawn.answer.realKeys -eq 0) "THE CONTROL: before it is given the keyboard the page says it has none, no field has the caret, and no key was pressed"

Write-Host ""
Write-Host "=== GIVEN THE KEYBOARD, by the engine: the caret lands in the first unanswered field ===" -ForegroundColor Cyan
$foregroundBefore = Get-Foreground
[void](Send-Probe -Keys @((Keyboard $true)))
$given = Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds 40 -Until { param($r) $null -ne $r.drawn -and $r.drawn.answer.focus -cne "" }
Check ($given.drawn.answer.focus -ceq "1") ("THE CARET IS IN QUESTION 1'S FIELD once the engine told the page it has the keyboard: nothing in the page was asked to move it (" + $given.drawn.answer.focus + ")")
Check ($given.drawn.answer.hasFocus -eq $true) "and the page itself says it has the keyboard"
$foregroundAfter = Get-Foreground
Check ($foregroundAfter -eq $foregroundBefore -and $foregroundAfter -ne $window) "THE DESKTOP'S FOREGROUND WINDOW IS THE ONE IT WAS: whoever was typing still is"
Check ($given.drawn.answer.realKeys -eq 0 -and $given.says -eq 0) "no key was pressed to get it there"

Write-Host ""
Write-Host "=== typed and Enter, by real keys: stored, read back through the operation, and the caret moves ===" -ForegroundColor Cyan
$r = Send-Probe -Keys @((Typed "Yes - commit it as it stands."), (Key "Enter")) -Steps @((Step "settle"))
$said1 = @(Get-Said 1)
Check ($r.drawn.answer.realKeys -eq $script:pressed -and $script:pressed -gt 20) ("THE KEYS WERE THE ENGINE'S OWN: the page counted " + $r.drawn.answer.realKeys + " key presses it trusts, the number pressed (" + $script:pressed + ")")
Check ($said1.Count -eq 1 -and $said1[0].text -ceq "Yes - commit it as it stands." -and $said1[0].speaker -ceq "founder" -and $said1[0].route -ceq "window") "question 1 holds one message in the store, exactly what was typed, said by the founder in the window"
Check ((Get-Line $r 1).a -ceq "Yes - commit it as it stands." -and (Get-Line $r 1).m -ceq "saved") "A REAL ENTER ADDED NO LINE to the answer: the field holds the words as typed, marked saved"
Check ($r.drawn.answer.focus -ceq "2") "and the caret moved to question 2's field"

Write-Host ""
Write-Host "=== Enter twice ===" -ForegroundColor Cyan
$r = Send-Probe -Keys @((Typed "second answer"), (Key "Enter"), (Key "Enter")) -Steps @((Step "settle"))
$said2 = @(Get-Said 2)
Check ($said2.Count -eq 1 -and $said2[0].text -ceq "second answer" -and $r.drawn.answer.focus -ceq "3" -and @(Get-Said 3).Count -eq 0) "a doubled real Enter is one message under question 2, and the caret is in question 3: no question was skipped"

Write-Host ""
Write-Host "=== Shift+Enter and Ctrl+J add one line each; Enter then saves them all ===" -ForegroundColor Cyan
$r = Send-Probe -Keys @((Typed "line one"), (Key "Enter" -Shift), (Typed "line two"))
Check ((Get-Line $r 3).a -ceq "line one`nline two" -and [int](Get-Line $r 3).fh -eq 2 -and $r.drawn.answer.focus -ceq "3" -and @(Get-Said 3).Count -eq 0) ("a real Shift+Enter added ONE line, not two, and saved nothing: the caret is still in question 3 (" + ((Get-Line $r 3).a -replace "`n", "\n") + ")")
$r = Send-Probe -Keys @((Key "j" -Ctrl), (Typed "line three"))
Check ((Get-Line $r 3).a -ceq "line one`nline two`nline three" -and [int](Get-Line $r 3).fh -eq 3 -and $r.drawn.answer.focus -ceq "3") ("a real Ctrl+J added one line the same way (" + ((Get-Line $r 3).a -replace "`n", "\n") + ")")
$r = Send-Probe -Keys @((Key "Enter")) -Steps @((Step "settle"))
$said3 = @(Get-Said 3)
Check ($said3.Count -eq 1 -and $said3[0].text -ceq "line one`nline two`nline three" -and $r.drawn.answer.focus -ceq "4") "Enter saved the three lines as one message, line breaks kept, and moved to question 4"

Write-Host ""
Write-Host "=== Tab: fills the grey suggestion and stays; with text, or with no suggestion, moves on ===" -ForegroundColor Cyan
$r = Send-Probe -Keys @((Key "Tab")) -Steps @((Step "settle"))
Check ($r.drawn.answer.focus -ceq "5" -and @(Get-Said 4).Count -eq 0 -and (Get-Line $r 4).a -ceq "") "a real Tab on an empty field with NO suggestion goes to question 5's field - the next ANSWER, not the next thing on the page - and saves nothing"
$rec5 = "$((Get-Shown -Number 5).recommendation)"
$r = Send-Probe -Keys @((Key "Tab"))
Check ($r.drawn.answer.focus -ceq "5" -and (Get-Line $r 5).a -ceq $rec5 -and $rec5 -ne "" -and @(Get-Said 5).Count -eq 0) ("A REAL TAB ON AN EMPTY FIELD WITH A SUGGESTION FILLS IT IN AND STAYS: question 5 holds '" + (Get-Line $r 5).a + "', nothing saved")
$r = Send-Probe -Keys @((Typed " but only this once"), (Key "Tab")) -Steps @((Step "settle"))
$said5 = @(Get-Said 5)
Check ($said5.Count -eq 1 -and $said5[0].text -ceq ($rec5 + " but only this once") -and $r.drawn.answer.focus -ceq "6") "A REAL TAB ON A FIELD WITH TEXT SAVES IT AND MOVES ON: the suggestion as edited is question 5's one message, the caret in question 6"

Write-Host ""
Write-Host "=== the right arrow fills the suggestion; Shift+Tab goes back one ===" -ForegroundColor Cyan
$rec6 = "$((Get-Shown -Number 6).recommendation)"
$r = Send-Probe -Keys @((Key "ArrowRight"))
Check ($r.drawn.answer.focus -ceq "6" -and (Get-Line $r 6).a -ceq $rec6 -and $rec6 -ne "" -and @(Get-Said 6).Count -eq 0) "a real right arrow in an empty field fills the suggestion in and the caret stays"
# Question 5 was answered a moment ago and leaves the list: once it has folded or gone, going back
# passes over it to the nearest question still to answer, question 4.
$null = Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds 30 -Until { param($x) $l = @($x.drawn.lines | Where-Object { $_.n -ceq "5" })[0]; $null -eq $l -or "$($l.ad)" -ceq "Answered" }
$r = Send-Probe -Keys @((Key "Tab" -Shift))
Check ($r.drawn.answer.focus -ceq "4" -and (Get-Line $r 6).a -ceq $rec6 -and (Get-Line $r 6).m -ceq "draft" -and @(Get-Said 6).Count -eq 0) ("a real Shift+Tab goes back to the nearest question still to answer, and what stood in question 6 stays as a draft (caret " + $r.drawn.answer.focus + ")")

Write-Host ""
Write-Host "=== Ctrl+Enter on an empty field: the suggestion is the answer ===" -ForegroundColor Cyan
$rec7 = "$((Get-Shown -Number 7).recommendation)"
$r = Send-Probe -Steps @((Step "focus" -Q 7))
$r = Send-Probe -Keys @((Key "Enter" -Ctrl)) -Steps @((Step "settle"))
$said7 = @(Get-Said 7)
Check ($said7.Count -eq 1 -and $said7[0].text -ceq $rec7 -and $rec7 -ne "" -and $r.drawn.answer.focus -ceq "8") ("a real Ctrl+Enter stored the recommendation's own text as his answer to question 7 and moved to question 8 (" + $rec7 + ")")

Write-Host ""
Write-Host "=== F2 and Ctrl+Space: the context, in place ===" -ForegroundColor Cyan
$r = Send-Probe -Keys @((Key "F2"))
Check ((Get-Line $r 8).open -eq $true -and $r.drawn.answer.focus -ceq "8" -and @($r.drawn.sub | Where-Object { $_.n -clike "8.*" }).Count -ge 3) "a real F2 unfolds question 8's context under it, and the caret is still in its field"
$r = Send-Probe -Keys @((Key " " -Ctrl))
Check ((Get-Line $r 8).open -eq $false -and $r.drawn.answer.focus -ceq "8" -and (Get-Line $r 8).a -ceq "") "a real Ctrl+Space folds it again: the caret is still there, and no space was typed into the field"

Write-Host ""
Write-Host "=== Enter on an empty field is a skip; a key with the caret nowhere is not lost ===" -ForegroundColor Cyan
$r = Send-Probe -Steps @((Step "focus" -Q 9))
$r = Send-Probe -Keys @((Key "Enter")) -Steps @((Step "settle"))
Check ($r.drawn.answer.focus -ceq "10" -and @(Get-Said 9).Count -eq 0 -and (Get-Line $r 9).a -ceq "") "a real Enter on an empty field saves nothing and moves on to question 10"
$r = Send-Probe -Steps @((Step "blur"))
Check ($r.drawn.answer.focus -ceq "") "the caret is taken out of every field"
$r = Send-Probe -Keys @((Typed "x"))
Check ($r.drawn.answer.focus -ceq "4" -and (Get-Line $r 4).a -ceq "x") ("a letter typed with the caret nowhere goes to the first unanswered question, and the letter is in its field (caret in " + $r.drawn.answer.focus + ", field 4 holds '" + (Get-Line $r 4).a + "')")

Write-Host ""
Write-Host "=== Escape in a window that stands free: nothing is done ===" -ForegroundColor Cyan
# Beside a terminal window, Escape hands that window the keyboard: proved against a terminal of the
# scenario's own, in the terminal's own folder. This window stands beside none.
$foregroundAtEscape = Get-Foreground
[void](Send-Probe -Keys @((Key "Escape")))
$r = Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds 40 -Until { param($x) $null -ne $x.handBack -and $x.handBack.asked -ge 1 }
Check ($r.handBack.asked -eq 1 -and $r.handBack.handed -eq 0 -and $r.handBack.last -ceq "none") ("a real Escape asked Horde once to hand the keyboard back, and Horde, standing beside no terminal, handed it to nobody (asked " + $r.handBack.asked + ", handed " + $r.handBack.handed + ", " + $r.handBack.last + ")")
Check ((Get-Foreground) -eq $foregroundAtEscape -and $r.drawn.answer.focus -ceq "4" -and (Get-Line $r 4).a -ceq "x" -and $r.drawn.foot -cnotlike "*Esc*") "the desktop's foreground window is the one it was, the caret and the letter are where they were, and the last line does not offer Escape"

Write-Host ""
Write-Host "=== one character is not sent on a Tab; a save shows at once, and the same Enter made again does nothing ===" -ForegroundColor Cyan
$r = Send-Probe -Steps @((Step "focus" -Q 4))
$r = Send-Probe -Keys @((Key "Tab")) -Steps @((Step "settle"))
Check ($r.drawn.answer.focus -ceq "6" -and (Get-Line $r 4).a -ceq "x" -and (Get-Line $r 4).m -ceq "draft" -and @(Get-Said 4).Count -eq 0) ("A REAL TAB ON A FIELD HOLDING ONE CHARACTER moves on - to question 6, the next still to answer: question 5 is answered and gone - and sends nothing: the 'x' stays in question 4 as a draft (caret " + $r.drawn.answer.focus + ")")
$r = Send-Probe -Steps @((Step "focus" -Q 8))
$script:probeN++
$script:pressed += (Get-KeyPresses -Keys @((Typed "eight"), (Key "Enter")))
Write-Whole -Path $script:probeFile -Text (ConvertTo-Json -InputObject ([ordered]@{ n = $script:probeN; keys = @((Typed "eight"), (Key "Enter")); steps = @() }) -Depth 5 -Compress)
$wantAck = $script:probeN
$atOnce = Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds 40 -Until { param($x) $null -ne $x.drawn -and $x.drawn.answer.probe -eq $wantAck }
Check ($atOnce.drawn.answer.focus -ceq "9" -and @("saving", "saved") -ccontains (Get-Line $atOnce 8).m -and (Get-Line $atOnce 8).a -ceq "eight") ("THE ENTER SHOWS AT ONCE: in the first report after it the caret is in question 9 and question 8 says '" + (Get-Line $atOnce 8).m + "'")
$r = Send-Probe -Keys @((Key "Enter")) -Steps @((Step "settle"))
Check ($r.drawn.answer.focus -ceq "9" -and @(Get-Said 8).Count -eq 1 -and @(Get-Said 9).Count -eq 0) ("AN ENTER MADE AGAIN within seconds of a save, on the empty field it moved to, does nothing: the caret stays in question 9 and question 8 holds one message (caret in " + $r.drawn.answer.focus + ")")
Start-Sleep -Milliseconds 3200
$r = Send-Probe -Keys @((Key "Enter")) -Steps @((Step "settle"))
Check ($r.drawn.answer.focus -ceq "10" -and @(Get-Said 9).Count -eq 0) "CONTROL: an Enter on that empty field after those seconds moves on, saving nothing"

Write-Host ""
Write-Host "=== every key counted, nothing refused, nobody's keyboard taken ===" -ForegroundColor Cyan
Check ($r.drawn.answer.realKeys -eq $script:pressed) ("the page counted " + $r.drawn.answer.realKeys + " key presses the engine vouches for; this scenario pressed " + $script:pressed)
Check ($r.says -eq 6 -and $r.saysRefused -eq 0 -and $r.refused -eq 0 -and @($r.errors).Count -eq 0) ("six answers stored, nothing refused, nothing failed inside the window (" + (@($r.errors) -join " | ") + ")")
Check ((Get-Foreground) -ne $window) "the window never became the desktop's foreground window"
$closed = Close-HordeProbeWindow -Process $script:open.process -Handle $window -Seconds 40
Check ($closed.asked -and $closed.exited -and -not $closed.killed -and $closed.code -eq 0) "the window is closed as its close button would, and the command exits 0"
Check ($script:open.err.Result.Trim() -ceq "") "with nothing on the error stream"
$keepHome = $env:HORDE_HOME
try { $env:HORDE_HOME = $hordeHome; $all = @((Invoke-HordeDecision -Operation "list" -Request @{ state = "all" }).value.questions) } finally { $env:HORDE_HOME = $keepHome }
$counts = @($all | Sort-Object number | ForEach-Object { "" + $_.thread.count }) -join ","
Check ($counts -ceq "1,1,1,0,1,0,1,1,0,0") ("the store holds exactly what was entered: six answers, each once (" + $counts + ")")

} finally {
    if ($null -ne $script:open -and -not $script:open.process.HasExited) { try { $script:open.process.Kill() } catch { } }
    Start-Sleep -Milliseconds 500
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-answer-keys-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) {
        for ($i = 0; $i -lt 20 -and (Test-Path -LiteralPath $script:work); $i++) { try { Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction Stop } catch { Start-Sleep -Milliseconds 500 } }
    }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the scenario's temp folder is removed"
Check ((Get-RealStoreListing) -ceq $realBefore) "the real store under the user profile is exactly as it was before the scenario"

Complete-HordeSuite -Success "real keys in a real window: the caret is there when the window is given the keyboard, and every key does what the last line of the page says"
