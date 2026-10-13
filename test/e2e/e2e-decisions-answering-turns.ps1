# END TO END: THE LIST IS HIS TURN - a real window on a real list, opened where nobody sees it, keys
# by the engine's own input (e2e-decisions-answering-keys.ps1 says why, and why no window is activated),
# the keeper's side by the real command line.
#
# WHAT THE OWNER ASKED FOR, 2026-10-07 (his record 72, and the coordinator's items from it):
#   - answers that have been picked up leave the list: an answered question stays, marked saved, until
#     the keeper has READ it, then moves to the folded "With Thrall"; a note (reply -Note) leaves it
#     there; a reply that asks him something brings it back with the reply shown; a close moves it to
#     the folded "History" with its outcome; Enter and Tab never go into a fold; the top line counts
#     the list;
#   - an answer he changes says "edited", the earlier one is kept as a line marked earlier, and the
#     keeper's inbox says the new words replace his earlier answer;
#   - Ctrl+B parks a question, recorded as his own act, with Ctrl+Z to undo; in the Parked fold Ctrl+B
#     brings it back;
#   - new questions stand at the top, marked new until he has passed them;
#   - the view follows him: a question he moves to comes up near the top, the field he types in stays
#     in view, a question whose context he unfolds goes to the top.
# NOTHING OF THE OWNER'S IS USED: HORDE_HOME is a folder this scenario made and removes.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "test\lib\MessengerPins.ps1")
. (Join-Path $root "test\lib\WindowProbe.ps1")

$script:work = Join-Path $env:TEMP ("horde-answer-turns-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$hordeHome = Join-Path $script:work "home"
$report = Join-Path $script:work "report.json"
$script:probeFile = Join-Path $script:work "probe.json"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$childEnv = @{ HORDE_HOME = $hordeHome; WEZFLEET_ROOT = (Join-Path $script:work "no-fleet"); PSModulePath = $null }
$cliEnv = @{ HORDE_HOME = $hordeHome; WEZFLEET_ROOT = (Join-Path $script:work "no-fleet") }
$script:probeN = 0
$script:open = $null

function Get-Said {
    param([int]$Number)
    $keep = $env:HORDE_HOME
    try { $env:HORDE_HOME = $hordeHome; return @((Invoke-HordeDecision -Operation "show" -Request @{ number = $Number }).value.question.thread.messages) } finally { $env:HORDE_HOME = $keep }
}
function Wait-Said {
    # The messages under -Number once there are -Count of them, or as they are after -Seconds. A save
    # goes through the window's helper and the store in their own time: a fixed sleep was measured
    # short on this machine (2026-10-07, the fourth park/unpark record not yet there after 1.5 s).
    param([int]$Number, [int]$Count, [int]$Seconds = 30)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do { $got = @(Get-Said $Number); if ($got.Count -ge $Count) { return $got }; Start-Sleep -Milliseconds 250 } while ((Get-Date) -lt $deadline)
    return @(Get-Said $Number)
}
function Write-Whole {
    param([string]$Path, [string]$Text)
    $temp = $Path + ".tmp"
    [System.IO.File]::WriteAllText($temp, $Text, $utf8)
    if (Test-Path -LiteralPath $Path -PathType Leaf) { [System.IO.File]::Replace($temp, $Path, [NullString]::Value) } else { [System.IO.File]::Move($temp, $Path) }
}
function Key { param([string]$Name, [switch]$Shift, [switch]$Ctrl) return [pscustomobject]([ordered]@{ key = $Name; shift = [bool]$Shift; ctrl = [bool]$Ctrl }) }
function Typed { param([string]$Text) return [pscustomobject]([ordered]@{ text = $Text }) }
function Step { param([string]$Do, $Q = $null) $s = [ordered]@{ do = $Do }; if ($null -ne $Q) { $s["q"] = [int]$Q }; return [pscustomobject]$s }
function Send-Probe {
    param([object[]]$Keys = @(), [object[]]$Steps = @(), [int]$Seconds = 120)
    $script:probeN++
    Write-Whole -Path $script:probeFile -Text (ConvertTo-Json -InputObject ([ordered]@{ n = $script:probeN; keys = @($Keys); steps = @($Steps) }) -Depth 5 -Compress)
    $script:wantProbe = $script:probeN
    return (Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds $Seconds -Until { param($r) $null -ne $r.drawn -and $null -ne $r.drawn.answer -and $r.drawn.answer.probe -eq $script:wantProbe -and $r.drawn.answer.pending -eq 0 })
}
function Wait-Report { param([scriptblock]$Until, [int]$Seconds = 90) return (Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds $Seconds -Until $Until) }
function Get-Line { param($Report, [int]$Number) return @($Report.drawn.lines | Where-Object { $_.n -ceq ("" + $Number) })[0] }
function Get-Done { param($Report, [int]$Number) return @($Report.drawn.done | Where-Object { $_.n -ceq ("" + $Number) })[0] }
function Get-Head { param($Report, [string]$Like) return @($Report.drawn.headings | Where-Object { $_.t -clike $Like })[0] }
function Horde { param([string[]]$Arguments) return (Invoke-HordeCliProcess -Root $root -HordeArgs (@("decisions") + $Arguments) -Env $cliEnv) }

try {

# THE MESSENGERS ARE PINNED in the home every horde child here uses: the window loads every messenger,
# and one may find a real program to post through by itself (test/lib/MessengerPins.ps1). The fleet's
# registry is a folder of this scenario's that does not exist (WEZFLEET_ROOT), so no seat is read.
$pins = @(Set-HordeTestMessengerPins -Root $root -HordeHome $hordeHome)
Check ($pins.Count -ge 1 -and @($pins | Where-Object { -not (Test-Path -LiteralPath (Join-Path $hordeHome ("settings\messenger-" + $_ + ".json")) -PathType Leaf) }).Count -eq 0) ("PIN: every messenger that has a pin is pinned in this home, so no horde started here can post for real (" + ($pins -join ", ") + ")")

Write-Host ""
Write-Host "=== fourteen questions, each with a few lines of background ===" -ForegroundColor Cyan
$keepHome = $env:HORDE_HOME
try {
    $env:HORDE_HOME = $hordeHome
    . (Join-Path $root "decisions\Operations.ps1")
    for ($n = 1; $n -le 14; $n++) {
        $q = [ordered]@{ title = ("Should step " + $n + " of the plan go ahead as it is written today?"); kind = "yes-no"; whatItIs = (("Step " + $n + " is ready. ") * 30); recommendation = "yes"; group = "The plan"; askedBy = "Orc B" }
        $added = Invoke-HordeDecision -Operation "add" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = $q }
        if ($added.state -cne "known" -or $added.value.outcome -cne "done") { throw ("not added: " + $added.reason) }
    }
} finally { $env:HORDE_HOME = $keepHome }

$script:open = Start-HordeProbeCommand -Root $root -HordeArgs @("decisions", "open", "-Hidden", "-Report", $report, "-Probe", $script:probeFile) -Env $childEnv
$first = Wait-Report { param($r) $null -ne $r.drawn -and @($r.drawn.lines).Count -eq 14 -and $null -ne $r.drawn.answer } 150
Check ($first.drawn.top -ceq "14 to answer" -and @($first.drawn.headings | Where-Object { $_.t -ceq "New" }).Count -eq 0) ("the first list the page is ever handed has nothing new in it, and the top line counts the list (" + $first.drawn.top + ")")
[void](Send-Probe -Keys @([pscustomobject]@{ focus = $true }))
$r = Wait-Report { param($x) "" + $x.drawn.answer.focus -ne "" } 40
Check ($r.drawn.answer.focus -ceq "1") "given the keyboard, the caret is in question 1"

Write-Host ""
Write-Host "=== answered: it stays, saved, until the keeper has read it; then it is With Thrall ===" -ForegroundColor Cyan
$r = Send-Probe -Keys @((Typed "yes for one"), (Key "Enter")) -Steps @((Step "settle"))
Check ((Get-Line $r 1).m -ceq "saved" -and (Get-Line $r 1).z -ceq "main" -and $r.drawn.answer.focus -ceq "2" -and $r.drawn.top -ceq "13 to answer") ("AN ANSWER STAYS WHERE IT IS, marked saved and still his to change, until the keeper has read it; the top line counts down (" + $r.drawn.top + ")")
$inbox = Horde @("inbox")
$r = Wait-Report { param($x) $null -ne (Get-Done $x 1) }
Check ($inbox.code -eq 0 -and $null -eq (Get-Line $r 1) -and (Get-Done $r 1).k -ceq "thrall" -and (Get-Done $r 1).a -ceq "yes for one" -and (Get-Head $r "With Thrall (1)").folded -eq $true) "ONCE READ, it leaves the list for the folded With Thrall (1), showing his answer, to be read only"
Check ($r.drawn.answer.focus -ceq "2") "and the caret is where it was"

Write-Host ""
Write-Host "=== a note leaves it there; a reply that asks brings it back with the reply shown ===" -ForegroundColor Cyan
$note = Horde @("reply", "1", "-Text", "Noted, I am on it.", "-Note")
$r = Wait-Report { param($x) (Get-Done $x 1).r -ceq "Noted, I am on it." }
Check ($note.code -eq 0 -and (Get-Done $r 1).k -ceq "thrall" -and $null -eq (Get-Line $r 1)) "A NOTE (reply -Note) ASKS HIM NOTHING: question 1 stays With Thrall, the note shown under his answer"
# The real command no longer asks again under an answered question (2026-10-12); a store may hold such a
# reply from before, and the window still brings the question back for it: the record is put there as a file.
$ask = Horde @("reply", "1", "-Text", "Which build should it go to?")
Check ($ask.code -eq 1 -and $ask.out -like "*question 1 has been answered and is off the founder's list*") "the real command refuses a reply that asks under the question he answered"
$null = Add-HordeProbeStoredRecord -Store (Join-Path $hordeHome "store\decisions") -Kind "message-said" -Data ([ordered]@{ number = 1; speaker = "warchief"; route = "command"; text = "Which build should it go to?" })
$r = Wait-Report { param($x) $null -ne (Get-Line $x 1) }
Check ((Get-Line $r 1).z -ceq "main" -and ((@((Get-Line $r 1).th)) -join " | ") -clike "*Thrall: Which build should it go to?" -and (Get-Line $r 1).a -ceq "" -and $null -eq (Get-Done $r 1)) "A REPLY THAT ASKS, ALREADY IN THE STORE, brings it back to the list by itself, the reply shown, his field empty"
Check ($r.drawn.top -ceq "14 to answer") ("and the top line counts it again (" + $r.drawn.top + ")")

Write-Host ""
Write-Host "=== a close moves it to History with its outcome ===" -ForegroundColor Cyan
$r = Send-Probe -Keys @((Typed "two is fine"), (Key "Enter")) -Steps @((Step "settle"))
$closed2 = Horde @("close", "2", "-Outcome", "Done as he said: step two went ahead.")
$r = Wait-Report { param($x) $null -ne (Get-Done $x 2) }
Check ($closed2.code -eq 0 -and (Get-Done $r 2).k -ceq "history" -and (Get-Done $r 2).o -ceq "Done as he said: step two went ahead." -and (Get-Done $r 2).a -ceq "two is fine" -and (Get-Head $r "History (1)").folded -eq $true) "CLOSED, it is in the folded History (1), with his answer and the one-line outcome"

Write-Host ""
Write-Host "=== Enter and Tab never go into a fold ===" -ForegroundColor Cyan
$r = Send-Probe -Steps @((Step "focus" -Q 14))
$r = Send-Probe -Keys @((Key "Enter"), (Key "Tab"))
Check ($r.drawn.answer.focus -ceq "14" -and $r.drawn.answer.focusHead -ceq "") "on the last question of the list, Enter and Tab stay in the list: no fold is entered"

Write-Host ""
Write-Host "=== an answer he changes says edited, and the earlier one is kept ===" -ForegroundColor Cyan
$r = Send-Probe -Steps @((Step "focus" -Q 3))
$r = Send-Probe -Keys @((Typed "three as planned"), (Key "Enter")) -Steps @((Step "settle"))
$r = Send-Probe -Steps @((Step "focus" -Q 3))
$r = Send-Probe -Keys @((Key "a" -Ctrl), (Typed "three, but a week later"), (Key "Enter")) -Steps @((Step "settle"))
$said3 = @(Get-Said 3)
Check ($said3.Count -eq 2 -and $said3[1].text -ceq "three, but a week later" -and $said3[1].replaces -eq $true) "his change is a second message, which the store says replaces his first"
$r = Wait-Report { param($x) (Get-Line $x 3).m -clike "*edited*" }
Check ((Get-Line $r 3).a -ceq "three, but a week later" -and (Get-Line $r 3).m -ceq "saved, edited" -and ((@((Get-Line $r 3).th)) -join " | ") -ceq "You, earlier: three as planned") ("THE CURRENT ANSWER SAYS EDITED, and the earlier one is kept above it, one line, marked earlier (" + (Get-Line $r 3).m + " | " + ((@((Get-Line $r 3).th)) -join " | ") + ")")
$peek = Horde @("inbox", "-Peek")
Check ($peek.code -eq 0 -and $peek.out -like "*three, but a week later*" -and $peek.out -like "*(replaces his earlier answer)*") "the keeper's inbox prints the new words with (replaces his earlier answer)"

Write-Host ""
Write-Host "=== Ctrl+B parks, as his own act; Ctrl+Z undoes; in the Parked fold Ctrl+B brings it back ===" -ForegroundColor Cyan
$r = Send-Probe -Steps @((Step "focus" -Q 4))
$r = Send-Probe -Keys @((Key "b" -Ctrl)) -Steps @((Step "settle"))
Check ((Get-Line $r 4).z -ceq "parked" -and $r.drawn.answer.focus -ceq "5" -and $r.drawn.toast -ceq "Question 4 parked. Ctrl+Z to undo.") ("A REAL CTRL+B PARKS question 4: it is in the Parked fold, the caret went on to question 5, and a short line offers Ctrl+Z (" + $r.drawn.toast + "; caret " + $r.drawn.answer.focus + "; zone " + (Get-Line $r 4).z + ")")
$r = Wait-Report { param($x) @(Get-Said 4).Count -ge 1 } 30
$said4 = @(Get-Said 4)
Check ($said4.Count -eq 1 -and $said4[0].act -ceq "park" -and $said4[0].speaker -ceq "founder" -and $said4[0].route -ceq "window") "it is recorded as his own act, park, said in the window: the keeper sees it"
$r = Send-Probe -Keys @((Key "z" -Ctrl)) -Steps @((Step "settle"))
Check ((Get-Line $r 4).z -ceq "main" -and $r.drawn.answer.focus -ceq "4") "a real Ctrl+Z at once brings it back to the list, with the caret in it"
$said4 = @(Wait-Said -Number 4 -Count 2)
Check ($said4.Count -eq 2 -and $said4[1].act -ceq "unpark") "and that is recorded as his act too: unpark"
$r = Send-Probe -Keys @((Key "b" -Ctrl)) -Steps @((Step "settle"))
$r = Send-Probe -Keys @((Key "ArrowDown" -Ctrl))
Check ($r.drawn.answer.focusHead -clike "Parked (1)") ("Ctrl+Down goes to the folded lines, the first being Parked (1) (" + $r.drawn.answer.focusHead + ")")
$r = Send-Probe -Keys @((Key "Enter"))
Check ($r.drawn.answer.focus -ceq "4" -and (Get-Line $r 4).z -ceq "parked") "Enter opens it, the caret in the parked question's field"
$r = Send-Probe -Keys @((Key "b" -Ctrl)) -Steps @((Step "settle"))
Check ((Get-Line $r 4).z -ceq "main" -and $r.drawn.toast -ceq "Question 4 is back in the list. Ctrl+Z to undo.") "CTRL+B IN THE PARKED FOLD brings it back into the list, under its own group"
$said4 = @(Wait-Said -Number 4 -Count 4)
Check ($said4.Count -eq 4 -and $said4[-1].act -ceq "unpark") "four acts recorded, the last unpark; the question's group was never changed"

Write-Host ""
Write-Host "=== a new question stands at the top, marked new until he has passed it ===" -ForegroundColor Cyan
$q15 = Join-Path $script:work "q15.json"
[System.IO.File]::WriteAllText($q15, '{"title":"Is a question asked while the window is open shown at the top of it?","kind":"yes-no","whatItIs":"Asked at the command line.","recommendation":"yes","group":"The plan","askedBy":"Orc C"}', $utf8)
$add = Horde @("add", "-File", $q15)
$r = Wait-Report { param($x) $null -ne (Get-Line $x 15) }
Check ($add.code -eq 0 -and (Get-Line $r 15).nw -eq $true -and (Get-Line $r 15).g -eq 0 -and $r.drawn.headings[0].t -ceq "New") "NEW AT THE TOP: question 15 stands first, under New, marked new"
$r = Send-Probe -Steps @((Step "focus" -Q 15))
$r = Send-Probe -Keys @((Key "Tab" -Shift)) -Steps @((Step "focus" -Q 6))
$r = Send-Probe -Keys @((Key "F2"), (Key "F2"))
Check ((Get-Line $r 15).nw -eq $false -and $r.drawn.headings[0].t -cne "New") "once he has been in it and left it, it is no longer new: it stands in its group"

Write-Host ""
Write-Host "=== the view follows him ===" -ForegroundColor Cyan
$r = Send-Probe -Steps @((Step "focus" -Q 5))
$r = Send-Probe -Keys @((Key "Tab"), (Key "Tab"))
$v = $r.drawn.answer.view
Check ($null -ne $v -and $v.height -gt 0 -and $v.top -ge 0 -and $v.top -le [Math]::Ceiling($v.height / 3)) ("A QUESTION HE MOVES TO is near the top of the view (" + $v.top + " px below the top of " + $v.height + ")")
$lines = @(); for ($i = 0; $i -lt 40; $i++) { $lines += (Typed ("line " + $i)); $lines += (Key "Enter" -Shift) }
$r = Send-Probe -Keys $lines
$v = $r.drawn.answer.view
Check ($null -ne $v -and $v.fieldBottom -le $v.height -and $v.scrolled -gt 0) ("TYPING PAST THE BOTTOM: the field he types in is kept in view (its foot at " + $v.fieldBottom + " of " + $v.height + ", scrolled " + $v.scrolled + ", page " + $v.page + ", follows " + $r.drawn.answer.timing.follows + "/" + $r.drawn.answer.timing.followed + ", caret " + $r.drawn.answer.focus + ")")
$r = Send-Probe -Steps @((Step "focus" -Q 7))
$r = Send-Probe -Keys @((Key "F2"))
$v = $r.drawn.answer.view
Check ((Get-Line $r 7).open -eq $true -and $null -ne $v -and $v.top -ge 0 -and $v.top -le 12) ("UNFOLDED, the question goes to the top of the view, so the most of its context shows (" + $v.top + " px)")

$final = Read-HordeProbeReport -Path $report
Check ($final.saysRefused -eq 0 -and @($final.errors).Count -eq 0 -and @($final.helper.failures).Count -eq 0) ("nothing refused, nothing failed inside the window (" + (@($final.errors) -join " | ") + ")")
$closed = Close-HordeProbeWindow -Process $script:open.process -Handle ([long]$final.handle) -Seconds 40
Check ($closed.exited -and $closed.code -eq 0) "the window is closed and the command exits 0"

} finally {
    if ($null -ne $script:open -and -not $script:open.process.HasExited) { try { $script:open.process.Kill() } catch { } }
    Start-Sleep -Milliseconds 500
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-answer-turns-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) {
        for ($i = 0; $i -lt 20 -and (Test-Path -LiteralPath $script:work); $i++) { try { Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction Stop } catch { Start-Sleep -Milliseconds 500 } }
    }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the scenario's temp folder is removed"

Complete-HordeSuite -Success "the list is his turn: answers leave it once read, a note leaves them, a reply brings them back, Ctrl+B parks, new questions stand first, and the view follows him"
