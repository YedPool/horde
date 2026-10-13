# END TO END: THE ORDER OF HIS LIST, AND WHAT BECOMES OF A QUESTION ONCE HE HAS ANSWERED IT - a real
# window on a real list, opened where nobody sees it, keys by the engine's own input
# (e2e-decisions-answering-keys.ps1 says why, and why no window is activated), the keeper's side by the
# real command line.
#
# WHAT THE FOUNDER ASKED FOR, 2026-10-12:
#   1. once he answers a question it GOES AWAY from his list, even if there is a follow-up; a follow-up
#      is a BRAND-NEW question, never the old one reopened in place;
#   2. NEW questions appear at the TOP of the page;
#   3. an ORDER BY control: date (latest first), overall task importance, and how much the question
#      blocks its task - the two words set by the keeper when it adds a question, with defaults for
#      the ones already there; shown as small plain words on each question; the order remembered;
#   4. when an answer is SAVED its text turns GREEN, then the question COLLAPSES and shows "Answered",
#      then leaves the list; an answer that was NOT saved does not go green: the reason is shown and
#      the text kept.
# The sorting itself, case by case, is test/test-decisions-page-order.ps1; a question of parts is
# e2e-decisions-answering-parts.ps1. NOTHING OF THE OWNER'S IS USED: HORDE_HOME is a folder this
# scenario made and removes.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "test\lib\MessengerPins.ps1")
. (Join-Path $root "test\lib\WindowProbe.ps1")

$script:work = Join-Path $env:TEMP ("horde-answer-order-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$hordeHome = Join-Path $script:work "home"
$store = Join-Path $hordeHome "store\decisions"
$script:report = Join-Path $script:work "report.json"
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
function Write-Whole {
    param([string]$Path, [string]$Text)
    $temp = $Path + ".tmp"
    [System.IO.File]::WriteAllText($temp, $Text, $utf8)
    if (Test-Path -LiteralPath $Path -PathType Leaf) { [System.IO.File]::Replace($temp, $Path, [NullString]::Value) } else { [System.IO.File]::Move($temp, $Path) }
}
function Key { param([string]$Name, [switch]$Shift, [switch]$Ctrl) return [pscustomobject]([ordered]@{ key = $Name; shift = [bool]$Shift; ctrl = [bool]$Ctrl }) }
function Typed { param([string]$Text) return [pscustomobject]([ordered]@{ text = $Text }) }
function Step { param([string]$Do, $Q = $null, [string]$Key = "") $s = [ordered]@{ do = $Do }; if ($null -ne $Q) { $s["q"] = [int]$Q }; if ($Key -ne "") { $s["key"] = $Key }; return [pscustomobject]$s }
function Send-Probe {
    param([object[]]$Keys = @(), [object[]]$Steps = @(), [int]$Seconds = 120)
    $script:probeN++
    Write-Whole -Path $script:probeFile -Text (ConvertTo-Json -InputObject ([ordered]@{ n = $script:probeN; keys = @($Keys); steps = @($Steps) }) -Depth 5 -Compress)
    $script:wantProbe = $script:probeN
    return (Wait-HordeProbeReport -Path $script:report -Process $script:open.process -Seconds $Seconds -Until { param($r) $null -ne $r.drawn -and $null -ne $r.drawn.answer -and $r.drawn.answer.probe -eq $script:wantProbe -and $r.drawn.answer.pending -eq 0 })
}
function Wait-Report { param([scriptblock]$Until, [int]$Seconds = 90) return (Wait-HordeProbeReport -Path $script:report -Process $script:open.process -Seconds $Seconds -Until $Until) }
function Get-Line { param($Report, [int]$Number) return @($Report.drawn.lines | Where-Object { $_.n -ceq ("" + $Number) })[0] }
function Get-Done { param($Report, [int]$Number) return @($Report.drawn.done | Where-Object { $_.n -ceq ("" + $Number) })[0] }
function Get-Order { param($Report) return (@($Report.drawn.lines | ForEach-Object { $_.n }) -join ",") }
function Get-Heads { param($Report) return (@($Report.drawn.headings | ForEach-Object { $_.t }) -join " / ") }
function Horde { param([string[]]$Arguments) return (Invoke-HordeCliProcess -Root $root -HordeArgs (@("decisions") + $Arguments) -Env $cliEnv) }

try {

# THE MESSENGERS ARE PINNED in the home every horde child here uses (test/lib/MessengerPins.ps1).
$pins = @(Set-HordeTestMessengerPins -Root $root -HordeHome $hordeHome)
Check ($pins.Count -ge 1 -and @($pins | Where-Object { -not (Test-Path -LiteralPath (Join-Path $hordeHome ("settings\messenger-" + $_ + ".json")) -PathType Leaf) }).Count -eq 0) ("PIN: every messenger that has a pin is pinned in this home, so no horde started here can post for real (" + ($pins -join ", ") + ")")

Write-Host ""
Write-Host "=== six questions asked a minute apart, in two groups, some with the two words and some with none ===" -ForegroundColor Cyan
# Question 1 is answered before the window opens, and question 5 follows it up. Questions 1 and 6 state
# neither word, as every question asked before the words existed.
$keepHome = $env:HORDE_HOME
try {
    $env:HORDE_HOME = $hordeHome
    . (Join-Path $root "decisions\Operations.ps1")
    $when = [datetime]::SpecifyKind([datetime]"2026-01-01T09:00:00", [System.DateTimeKind]::Utc)
    $asks = @(
        @{ q = [ordered]@{ title = "Should the first step of the plan go ahead as it is written?"; kind = "yes-no"; whatItIs = "The first step."; recommendation = "yes"; group = "The plan"; askedBy = "Orc B" } }
        @{ q = [ordered]@{ title = "Should the release wait for the second step of the plan?"; kind = "yes-no"; whatItIs = "The second step."; recommendation = "yes"; group = "The plan"; askedBy = "Orc B" }; importance = "high" }
        @{ q = [ordered]@{ title = "Which voice should the talker use for the Hebrew test?"; kind = "value"; whatItIs = "Nothing in the voice lane can go on until this is settled."; group = "The voice test"; askedBy = "Orc C" }; blocks = "all" }
        @{ q = [ordered]@{ title = "Should the old notes of the plan be tidied up some day?"; kind = "yes-no"; whatItIs = "Housekeeping."; group = "The plan"; askedBy = "Orc B" }; importance = "low"; blocks = "none" }
    )
    $i = 0
    foreach ($a in $asks) {
        $i++
        $request = @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = $a.q }
        foreach ($k in @("importance", "blocks")) { if ($a.ContainsKey($k)) { $request[$k] = $a[$k] } }
        $added = Invoke-HordeDecision -Operation "add" -Request $request -Now $when.AddMinutes($i)
        if ($added.state -cne "known" -or $added.value.outcome -cne "done") { throw ("not added: " + $added.state + " " + $added.reason + " " + (@($added.value.findings) -join "; ")) }
    }
    $answered = Invoke-HordeDecision -Operation "say" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; number = 1; speaker = "founder"; route = "chat-recorded"; text = "Yes, the first step goes ahead." } -Now $when.AddMinutes(10)
    if ($answered.state -cne "known" -or $answered.value.outcome -cne "done") { throw ("not answered: " + $answered.reason) }
    $follow = Invoke-HordeDecision -Operation "add" -Now $when.AddMinutes(11) -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; followsUp = 1; question = [ordered]@{ title = "The first step went ahead: should the second start on Monday?"; kind = "yes-no"; whatItIs = "A follow-up."; recommendation = "yes"; group = "The voice test"; askedBy = "Orc B" } }
    $plain = Invoke-HordeDecision -Operation "add" -Now $when.AddMinutes(12) -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = [ordered]@{ title = "Is the last question asked the first one shown?"; kind = "yes-no"; whatItIs = "Asked last."; group = "The voice test"; askedBy = "Orc C" } }
    if ($follow.state -cne "known" -or $follow.value.outcome -cne "done" -or $plain.state -cne "known" -or $plain.value.outcome -cne "done") { throw "the follow-up or the last question was not added" }
} finally { $env:HORDE_HOME = $keepHome }

$script:open = Start-HordeProbeCommand -Root $root -HordeArgs @("decisions", "open", "-Hidden", "-Report", $script:report, "-Probe", $script:probeFile) -Env $childEnv
$first = Wait-Report { param($r) $null -ne $r.drawn -and @($r.drawn.lines).Count -eq 5 -and $null -ne $r.drawn.answer } 150

Write-Host ""
Write-Host "=== NEWEST FIRST, and what he has answered is not in the list ===" -ForegroundColor Cyan
Check ((Get-Order $first) -ceq "6,5,4,3,2") ("THE LIST IS NEWEST FIRST: the question asked last stands first (" + (Get-Order $first) + ")")
Check ($null -eq (Get-Line $first 1) -and (Get-Done $first 1).k -ceq "thrall" -and (Get-Done $first 1).a -ceq "Yes, the first step goes ahead.") "THE QUESTION HE HAS ANSWERED IS NOT IN HIS LIST: it is in the folded With Thrall, with his answer - though the keeper has not read it"
Check ($first.drawn.order.key -ceq "date" -and $first.drawn.order.pressed -ceq "Date" -and $first.drawn.order.shown -eq $true -and (@($first.drawn.order.words) -join ",") -ceq "Date,Task importance,Blocking") ("a line at the head of the page offers the three orders, Date pressed (" + (@($first.drawn.order.words) -join ",") + "; pressed " + $first.drawn.order.pressed + ")")
Check ((Get-Heads $first) -ceq "The voice test / The plan / The voice test / The plan / With Thrall (1)") ("a group is the heading of each run of its questions; the order is never bent to keep a group together (" + (Get-Heads $first) + ")")
Check ($first.drawn.top -ceq "5 to answer") ("the top line counts what he has still to answer (" + $first.drawn.top + ")")

Write-Host ""
Write-Host "=== the plain words that stand out, and the question a follow-up follows ===" -ForegroundColor Cyan
Check ((@((Get-Line $first 2).b) -join "|") -ceq "Important" -and (@((Get-Line $first 3).b) -join "|") -ceq "Blocks all work" -and (@((Get-Line $first 4).b) -join "|") -ceq "Can wait|Blocks nothing") "each question that stands out says so in a few plain words: Important; Blocks all work; Can wait, Blocks nothing"
Check (@((Get-Line $first 6).b).Count -eq 0 -and @((Get-Line $first 5).b).Count -eq 0 -and @((Get-Done $first 1).b).Count -eq 0) "A QUESTION THAT STATES NEITHER WORD CARRIES NO MARK: the default is said by saying nothing"
$f5 = (Get-Line $first 5).fu
Check ($null -ne $f5 -and $f5.t -ceq "Follows up on question 1" -and $f5.open -eq $false -and $null -eq (Get-Line $first 6).fu) "the follow-up says which question it follows, in one folded line; a question that follows nothing says nothing"
$r = Send-Probe -Steps @((Step "follow" -Q 5))
$f5 = (Get-Line $r 5).fu
Check ($f5.open -eq $true -and $f5.more -clike "*Question 1:*Should the first step of the plan go ahead as it is written?*" -and $f5.more -clike "*You answered:*Yes, the first step goes ahead.*") ("pressed, it unfolds the earlier question and what he answered (" + $f5.more + ")")
$r = Send-Probe -Steps @((Step "follow" -Q 5))
Check ((Get-Line $r 5).fu.open -eq $false) "and pressed again, folds"

Write-Host ""
Write-Host "=== ORDER BY task importance, and by how much the question blocks ===" -ForegroundColor Cyan
$r = Send-Probe -Steps @((Step "order" -Key "importance"))
Check ((Get-Order $r) -ceq "2,6,5,3,4" -and $r.drawn.order.key -ceq "importance" -and $r.drawn.order.pressed -ceq "Task importance") ("BY TASK IMPORTANCE: the important one first, the one that can wait last, and between them - the questions that read as normal - the newest first (" + (Get-Order $r) + ")")
Check ((Get-Heads $r) -ceq "The plan / The voice test / The plan / With Thrall (1)") ("the headings follow the order (" + (Get-Heads $r) + ")")
$r = Send-Probe -Steps @((Step "order" -Key "blocks"))
Check ((Get-Order $r) -ceq "3,6,5,2,4" -and $r.drawn.order.key -ceq "blocks" -and $r.drawn.order.pressed -ceq "Blocking") ("BY BLOCKING: what blocks all work first, what blocks nothing last, the rest - which read as blocking part - newest first (" + (Get-Order $r) + ")")
$r = Send-Probe -Steps @((Step "order" -Key "sideways"))
Check ((Get-Order $r) -ceq "6,5,4,3,2" -and $r.drawn.order.key -ceq "date") "an order that is none of the three is the default, by date"
$r = Send-Probe -Steps @((Step "order" -Key "blocks"))

Write-Host ""
Write-Host "=== the keeper ranks a question, and asks a new one: both are placed by the order, with no reload ===" -ForegroundColor Cyan
$ranked = Horde @("rank", "6", "-Blocks", "all", "-Importance", "high")
$r = Wait-Report { param($x) (@((@($x.drawn.lines | Where-Object { $_.n -ceq "6" })[0]).b) -join "|") -ceq "Important|Blocks all work" }
Check ($ranked.code -eq 0 -and (Get-Order $r) -ceq "6,3,5,2,4") ("RANKED BY THE KEEPER, question 6 moves to its place and says why: Important, Blocks all work (" + (Get-Order $r) + ")")
$q7 = Join-Path $script:work "q7.json"
[System.IO.File]::WriteAllText($q7, '{"title":"Is a question asked while the window is open put where the order says?","kind":"yes-no","whatItIs":"Asked at the command line.","recommendation":"yes","group":"The plan","askedBy":"Orc C"}', $utf8)
$add = Horde @("add", "-File", $q7)
$r = Wait-Report { param($x) $null -ne (@($x.drawn.lines | Where-Object { $_.n -ceq "7" })[0]) }
Check ($add.code -eq 0 -and (Get-Order $r) -ceq "6,3,7,5,2,4" -and (Get-Line $r 7).nw -eq $true) ("by blocking, a new question that states neither word stands first among those that block part - the newest of them - and is marked new (" + (Get-Order $r) + ")")
$r = Send-Probe -Steps @((Step "order" -Key "date"))
Check ((Get-Order $r) -ceq "7,6,5,4,3,2" -and (Get-Line $r 7).nw -eq $true -and (Get-Line $r 7).g -eq 0) ("BY DATE THE NEW QUESTION IS AT THE TOP OF THE PAGE, marked new (" + (Get-Order $r) + ")")

Write-Host ""
Write-Host "=== SAVED: green, then folded to Answered, then out of the list ===" -ForegroundColor Cyan
$r = Send-Probe -Steps @((Step "focus" -Q 4))
$r = Send-Probe -Keys @((Typed "some day, yes"), (Key "Enter")) -Steps @((Step "settle"))
$said4 = @(Get-Said 4)
Check ($said4.Count -eq 1 -and $said4[0].text -ceq "some day, yes" -and $said4[0].route -ceq "window") "his answer to question 4 is in the store, typed in the window"
$green = Wait-Report { param($x) $l = @($x.drawn.lines | Where-Object { $_.n -ceq "4" })[0]; $null -ne $l -and ($l.gn -eq $true -or "$($l.ad)" -ne "") } 20
Check ($null -ne (Get-Line $green 4) -and (Get-Line $green 4).z -ceq "main" -and (Get-Line $green 4).gn -eq $true -and (Get-Line $green 4).ad -eq "" -and (Get-Line $green 4).a -ceq "some day, yes") ("SAVED, the question is still in its place and its words stand GREEN (green " + (Get-Line $green 4).gn + "; folded '" + (Get-Line $green 4).ad + "')")
$folded = Wait-Report { param($x) $l = @($x.drawn.lines | Where-Object { $_.n -ceq "4" })[0]; ($null -ne $l -and "$($l.ad)" -ceq "Answered") -or ($null -eq $l -and @($x.drawn.done | Where-Object { $_.n -ceq "4" }).Count -eq 1) } 20
$sawFold = ($null -ne (Get-Line $folded 4))
Check ($sawFold -and (Get-Line $folded 4).ad -ceq "Answered" -and (Get-Line $folded 4).gn -eq $false -and $folded.drawn.answer.fields -eq (@($folded.drawn.lines).Count - 1)) ("A MOMENT LATER IT FOLDS to the one word Answered, and has no field in the run of Enter and Tab (fields " + $folded.drawn.answer.fields + " of " + @($folded.drawn.lines).Count + " lines)")
$gone = Wait-Report { param($x) $null -eq (@($x.drawn.lines | Where-Object { $_.n -ceq "4" })[0]) -and @($x.drawn.done | Where-Object { $_.n -ceq "4" }).Count -eq 1 } 30
Check ($null -eq (Get-Line $gone 4) -and (Get-Done $gone 4).k -ceq "thrall" -and (Get-Done $gone 4).a -ceq "some day, yes" -and (Get-Order $gone) -ceq "7,6,5,3,2") ("AND THEN IT IS GONE FROM HIS LIST: in the folded With Thrall with his answer, though the keeper has read nothing (" + (Get-Order $gone) + ")")
Check ($gone.drawn.top -ceq "5 to answer" -and $gone.drawn.answer.focus -ceq "3") ("the top line counts one fewer, and the caret went on to the next question when he pressed Enter (" + $gone.drawn.top + "; caret " + $gone.drawn.answer.focus + ")")

Write-Host ""
Write-Host "=== NOT SAVED: never green, the words kept, the reason under them ===" -ForegroundColor Cyan
$secret = "the login is hunter2 and the key is ghp_" + ("A" * 36)
$r = Send-Probe -Steps @((Step "focus" -Q 2))
$r = Send-Probe -Keys @((Typed $secret), (Key "Enter")) -Steps @((Step "settle"))
$refused = Wait-Report { param($x) "$((@($x.drawn.lines | Where-Object { $_.n -ceq '2' })[0]).r)" -ne "" } 30
$l2 = Get-Line $refused 2
Check ($l2.r -clike "Not saved:*" -and $l2.gn -eq $false -and $l2.ad -eq "" -and $l2.a -ceq $secret -and $l2.z -ceq "main" -and @(Get-Said 2).Count -eq 0) ("AN ANSWER THAT WAS NOT SAVED DOES NOT GO GREEN and does not fold: the words are kept in the field, the reason stands under them, and nothing is in the store (" + $l2.r + ")")
Start-Sleep -Seconds 5
$still = Read-HordeProbeReport -Path $script:report
Check ($null -ne (Get-Line $still 2) -and (Get-Line $still 2).gn -eq $false -and (Get-Line $still 2).ad -eq "" -and (Get-Line $still 2).a -ceq $secret) "and it stays so: longer than a saved answer takes to fold, the refused one is still an open field with his words in it"
$r = Send-Probe -Steps @((Step "focus" -Q 2))
$r = Send-Probe -Keys @((Key "a" -Ctrl), (Typed "yes, it waits"), (Key "Enter")) -Steps @((Step "settle"))
$gone2 = Wait-Report { param($x) $null -eq (@($x.drawn.lines | Where-Object { $_.n -ceq "2" })[0]) -and @($x.drawn.done | Where-Object { $_.n -ceq "2" }).Count -eq 1 } 30
Check ((Get-Done $gone2 2).a -ceq "yes, it waits" -and @(Get-Said 2).Count -eq 1) "with words that can be saved, the same question is saved and leaves the list like any other"

Write-Host ""
Write-Host "=== the keeper cannot put it back; what is left to ask comes as a new question at the top ===" -ForegroundColor Cyan
$ask = Horde @("reply", "4", "-Text", "Which day would suit?")
$reopen = Horde @("reopen", "4", "-Reason", "one more thing")
Check ($ask.code -eq 1 -and $ask.out -like "*question 4 has been answered and is off the founder's list*" -and $reopen.code -eq 1 -and $reopen.out -like "*nothing is reopened any more*") "the real command refuses to ask again under question 4, and refuses to reopen it: each says to add a follow-up"
$q8 = Join-Path $script:work "q8.json"
[System.IO.File]::WriteAllText($q8, '{"title":"You said the old notes can be tidied some day: would this Friday suit?","kind":"yes-no","whatItIs":"What is left of question 4.","recommendation":"yes","group":"The plan","askedBy":"Orc B"}', $utf8)
$add8 = Horde @("add", "-File", $q8, "-FollowsUp", "4", "-Importance", "low", "-Blocks", "none")
$r = Wait-Report { param($x) $null -ne (@($x.drawn.lines | Where-Object { $_.n -ceq "8" })[0]) }
Check ($add8.code -eq 0 -and (Get-Order $r) -ceq "8,7,6,5,3" -and (Get-Line $r 8).fu.t -ceq "Follows up on question 4" -and (@((Get-Line $r 8).b) -join "|") -ceq "Can wait|Blocks nothing") ("THE FOLLOW-UP IS A NEW QUESTION, number 8, at the top of his list, saying which question it follows (" + (Get-Order $r) + ")")
Check ($null -eq (Get-Line $r 4) -and (Get-Done $r 4).k -ceq "thrall") "and question 4 is where it was: answered, not in his list"
$r = Send-Probe -Steps @((Step "follow" -Q 8))
Check ((Get-Line $r 8).fu.more -clike "*Question 4:*Should the old notes of the plan be tidied up some day?*You answered:*some day, yes*") ("unfolded, it shows question 4 and the answer he gave a moment ago (" + (Get-Line $r 8).fu.more + ")")

Write-Host ""
Write-Host "=== the order he chose is kept for the next time the window is opened ===" -ForegroundColor Cyan
$r = Send-Probe -Steps @((Step "order" -Key "importance"))
Check ((Get-Order $r) -ceq "6,7,5,3,8" -and $r.drawn.order.key -ceq "importance") ("by task importance, before the window is closed (" + (Get-Order $r) + ")")
$closed = Close-HordeProbeWindow -Process $script:open.process -Handle ([long]$first.handle) -Seconds 40
Check ($closed.exited -and $closed.code -eq 0) "the window is closed and the command exits 0"
$final = Read-HordeProbeReport -Path $script:report
Check ($final.saysRefused -eq 1 -and @($final.errors).Count -eq 0) ("one answer was refused - the one that held a secret - and nothing failed inside the window (refused " + $final.saysRefused + "; " + (@($final.errors) -join " | ") + ")")
$script:report = Join-Path $script:work "report2.json"
# WITH NO PROBE FILE: the file still holds the last steps handed over - "order: importance" - and a
# window given it would act them out again, and so be in that order whether or not it was kept (seen
# 2026-10-13: with the keeping taken out, this check still passed).
$script:open = Start-HordeProbeCommand -Root $root -HordeArgs @("decisions", "open", "-Hidden", "-Report", $script:report) -Env $childEnv
$back = Wait-Report { param($x) $null -ne $x.drawn -and @($x.drawn.lines).Count -eq 5 -and $null -ne $x.drawn.answer } 150
Check ($back.drawn.order.key -ceq "importance" -and $back.drawn.order.pressed -ceq "Task importance" -and (Get-Order $back) -ceq "6,7,5,3,8") ("OPENED AGAIN, the list is in the order he chose: by task importance (" + (Get-Order $back) + ")")
Check ($null -eq (Get-Line $back 4) -and (Get-Done $back 4).a -ceq "some day, yes" -and (Get-Done $back 2).a -ceq "yes, it waits" -and (Get-Done $back 1).k -ceq "thrall") "and what he answered is where it was left: out of his list, with the keeper"
Check ((@($back.drawn.done | Where-Object { $_.k -ceq "thrall" } | ForEach-Object { $_.n }) -join ",") -ceq "2,1,4" -and (@((Get-Done $back 2).b) -join "|") -ceq "Important") ("what is with the keeper stands in the same order, by task importance, each with its plain words (" + (@($back.drawn.done | ForEach-Object { $_.n }) -join ",") + ")")
$closed2 = Close-HordeProbeWindow -Process $script:open.process -Handle ([long]$back.handle) -Seconds 40
Check ($closed2.exited -and $closed2.code -eq 0) "that window closes too, exit 0"

} finally {
    if ($null -ne $script:open -and -not $script:open.process.HasExited) { try { $script:open.process.Kill() } catch { } }
    Start-Sleep -Milliseconds 500
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-answer-order-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) {
        for ($i = 0; $i -lt 20 -and (Test-Path -LiteralPath $script:work); $i++) { try { Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction Stop } catch { Start-Sleep -Milliseconds 500 } }
    }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the scenario's temp folder is removed"

Complete-HordeSuite -Success "his list is newest first and in the order he chooses; a saved answer goes green, folds to Answered and leaves; and nothing puts an answered question back"
