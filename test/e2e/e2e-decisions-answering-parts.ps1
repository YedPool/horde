# END TO END: a question of several parts answered part by part, WITH REAL KEYS, in a real window on a
# real list opened where nobody sees it (the way e2e-decisions-answering-keys.ps1 opens it; its header
# says why the keys are the engine's own and why no window is activated).
#
# WHY (the owner's question 28, 2026-10-07): a question of five parts, (a) to (e), stored the answer
# "a" - he began typing "a ..." and a key saved it and moved him on. Each part has a field of its own;
# Enter and Tab go from part to part.
# AND (the founder, 2026-10-12): EACH PART SENDS BY ITSELF - answering one part sends that part at
# once, without waiting for the others; each part gets its own green and its own "Answered"; the parts
# already answered stay folded as Answered while the others are open; the question leaves the list
# when all its parts are answered; and the keeper is told WHICH part was answered. A part that was not
# saved does not go green: the reason stands under that part, and its words are kept.
# The parts and the recommendation here are written as the keeper writes them in the real list:
# "(a) words" each, and one recommendation "(a) ...; (b) ...".

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "test\lib\MessengerPins.ps1")
. (Join-Path $root "test\lib\WindowProbe.ps1")

$script:work = Join-Path $env:TEMP ("horde-answer-parts-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$hordeHome = Join-Path $script:work "home"
$report = Join-Path $script:work "report.json"
$script:probeFile = Join-Path $script:work "probe.json"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$childEnv = @{ HORDE_HOME = $hordeHome; WEZFLEET_ROOT = (Join-Path $script:work "no-fleet"); PSModulePath = $null }
$cliEnv = @{ HORDE_HOME = $hordeHome; WEZFLEET_ROOT = (Join-Path $script:work "no-fleet") }
$script:probeN = 0
$script:open = $null

function Get-Shown {
    param([int]$Number)
    $keep = $env:HORDE_HOME
    try { $env:HORDE_HOME = $hordeHome; return (Invoke-HordeDecision -Operation "show" -Request @{ number = $Number }).value.question } finally { $env:HORDE_HOME = $keep }
}
function Get-Said { param([int]$Number) return @((Get-Shown $Number).thread.messages) }
function Get-SaidLine { param([int]$Number) return (@(Get-Said $Number | ForEach-Object { "" + $_.part + "=" + $_.text }) -join " | ") }
function Write-Whole {
    param([string]$Path, [string]$Text)
    $temp = $Path + ".tmp"
    [System.IO.File]::WriteAllText($temp, $Text, $utf8)
    if (Test-Path -LiteralPath $Path -PathType Leaf) { [System.IO.File]::Replace($temp, $Path, [NullString]::Value) } else { [System.IO.File]::Move($temp, $Path) }
}
function Key { param([string]$Name, [switch]$Shift, [switch]$Ctrl) return [pscustomobject]([ordered]@{ key = $Name; shift = [bool]$Shift; ctrl = [bool]$Ctrl }) }
function Typed { param([string]$Text) return [pscustomobject]([ordered]@{ text = $Text }) }
function Step { param([string]$Do, $Q = $null, $Part = $null) $s = [ordered]@{ do = $Do }; if ($null -ne $Q) { $s["q"] = [int]$Q }; if ($null -ne $Part) { $s["part"] = [int]$Part }; return [pscustomobject]$s }
function Send-Probe {
    param([object[]]$Keys = @(), [object[]]$Steps = @(), [int]$Seconds = 120)
    $script:probeN++
    Write-Whole -Path $script:probeFile -Text (ConvertTo-Json -InputObject ([ordered]@{ n = $script:probeN; keys = @($Keys); steps = @($Steps) }) -Depth 5 -Compress)
    $script:wantProbe = $script:probeN
    return (Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds $Seconds -Until { param($r) $null -ne $r.drawn -and $null -ne $r.drawn.answer -and $r.drawn.answer.probe -eq $script:wantProbe -and $r.drawn.answer.pending -eq 0 })
}
function Wait-Report { param([scriptblock]$Until, [int]$Seconds = 60) return (Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds $Seconds -Until $Until) }
function Get-Line { param($Report, [int]$Number) return @($Report.drawn.lines | Where-Object { $_.n -ceq ("" + $Number) })[0] }
function Get-Done { param($Report, [int]$Number) return @($Report.drawn.done | Where-Object { $_.n -ceq ("" + $Number) })[0] }
function Horde { param([string[]]$Arguments) return (Invoke-HordeCliProcess -Root $root -HordeArgs (@("decisions") + $Arguments) -Env $cliEnv) }

try {

# THE MESSENGERS ARE PINNED in the home every horde child here uses: the window loads every messenger,
# and one may find a real program to post through by itself (test/lib/MessengerPins.ps1). The fleet's
# registry is a folder of this scenario's that does not exist (WEZFLEET_ROOT), so no seat is read.
$pins = @(Set-HordeTestMessengerPins -Root $root -HordeHome $hordeHome)
Check ($pins.Count -ge 1 -and @($pins | Where-Object { -not (Test-Path -LiteralPath (Join-Path $hordeHome ("settings\messenger-" + $_ + ".json")) -PathType Leaf) }).Count -eq 0) ("PIN: every messenger that has a pin is pinned in this home, so no horde started here can post for real (" + ($pins -join ", ") + ")")

Write-Host ""
Write-Host "=== three questions of parts, one plain question after them ===" -ForegroundColor Cyan
# Asked a minute apart, the plain one FIRST and question 1 of parts LAST, so that the list - newest
# first - shows them in the order of their numbers: 4, 3, 2 would otherwise lead.
$keepHome = $env:HORDE_HOME
try {
    $env:HORDE_HOME = $hordeHome
    . (Join-Path $root "decisions\Operations.ps1")
    $when = [datetime]::SpecifyKind([datetime]"2026-01-01T09:00:00", [System.DateTimeKind]::Utc)
    $asks = @(
        [ordered]@{ title = "Video Mode: three follow-ups to the new wording for when she cannot zoom there."; kind = "parts"; whatItIs = "Follow-ups to settle."; parts = @("(a) The sentence when she cannot move the picture: approve, or reword.", "(b) Should the button inside the Reader say Video too?", "(c) Should page turns be refused in Video Mode?"); recommendation = "(a) approve; (b) yes; (c) yes, with a sentence in the same style."; group = "Video Mode"; askedBy = "Orc C" },
        [ordered]@{ title = "Two parts with one recommendation that names no part at all."; kind = "parts"; whatItIs = "Follow-ups to settle."; parts = @("(a) The first thing to settle about the plan.", "(b) The second thing to settle about the plan."); recommendation = "both as the plan says"; group = "Video Mode"; askedBy = "Orc C" },
        [ordered]@{ title = "Three parts the founder will take every suggestion for."; kind = "parts"; whatItIs = "Follow-ups to settle."; parts = @("(a) First of three.", "(b) Second of three.", "(c) Third of three."); recommendation = "(a) one; (b) two; (c) three"; group = "Video Mode"; askedBy = "Orc C" },
        [ordered]@{ title = "Should the plain question after the parts go ahead as written?"; kind = "yes-no"; whatItIs = "A plain question."; recommendation = "yes"; group = "Video Mode"; askedBy = "Orc C" }
    )
    $i = 0
    foreach ($q in $asks) {
        $i++
        # The first asked is stamped latest: newest first is then 1, 2, 3, 4.
        $added = Invoke-HordeDecision -Operation "add" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = $q } -Now $when.AddMinutes(10 - $i)
        if ($added.state -cne "known" -or $added.value.outcome -cne "done") { throw ("not added: " + $added.state + " " + $added.reason + " " + (@($added.value.findings) -join "; ")) }
    }
} finally { $env:HORDE_HOME = $keepHome }

$script:open = Start-HordeProbeCommand -Root $root -HordeArgs @("decisions", "open", "-Hidden", "-Report", $report, "-Probe", $script:probeFile) -Env $childEnv
$first = Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds 150 -Until { param($r) $null -ne $r.drawn -and @($r.drawn.lines).Count -eq 4 -and $null -ne $r.drawn.answer }
Check ((@($first.drawn.lines | ForEach-Object { $_.n }) -join ",") -ceq "1,2,3,4") ("CONTROL: the four stand in the order of their numbers, the one stamped latest first (" + (@($first.drawn.lines | ForEach-Object { $_.n }) -join ",") + ")")
$l1 = Get-Line $first 1
Check ($null -ne $l1 -and @($l1.pa).Count -eq 3 -and (@($l1.pp) -join "|") -ceq "approve|yes|yes, with a sentence in the same style.") ("A FIELD PER PART, each with its own part of the recommendation as its grey suggestion (" + (@($l1.pp) -join "|") + ")")
$l2 = Get-Line $first 2
Check ($null -ne $l2 -and @($l2.pa).Count -eq 2 -and (@($l2.pp) -join "|") -ceq "|") "a recommendation that names no part gives no part a suggestion (it is shown once, above the fields)"
Check (@((Get-Line $first 4).pa).Count -eq 0) "CONTROL: the plain question has one field, as before"
Check ((@($l1.pm) -join "|") -ceq "||" -and (@($l1.pd) -join "|") -ceq "False|False|False" -and (@($l1.pg) -join "|") -ceq "False|False|False") "no part carries a mark, stands green or is folded before he has typed anything"

Write-Host ""
Write-Host "=== one character on a Tab is not an answer; Tab and Enter SEND THE PART they leave ===" -ForegroundColor Cyan
[void](Send-Probe -Keys @([pscustomobject]@{ focus = $true }))
$r = Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds 40 -Until { param($x) "" + $x.drawn.answer.focus -ne "" }
Check ($r.drawn.answer.focus -ceq "1" -and $r.drawn.answer.focusPart -eq 0) "given the keyboard, the caret is in part (a) of question 1"
$r = Send-Probe -Keys @((Typed "a"), (Key "Tab")) -Steps @((Step "settle"))
Check ($r.drawn.answer.focus -ceq "1" -and $r.drawn.answer.focusPart -eq 1 -and @(Get-Said 1).Count -eq 0 -and (Get-Line $r 1).pm[0] -ceq "draft") "THE OWNER'S CASE: 'a' and Tab go to part (b) and send nothing - one letter is the start of an answer; it stays, a draft"
$r = Send-Probe -Keys @((Key "Tab" -Shift), (Typed " - approved as written"), (Key "Tab")) -Steps @((Step "settle"))
Check ((Get-SaidLine 1) -ceq "a=a - approved as written" -and $r.drawn.answer.focus -ceq "1" -and $r.drawn.answer.focusPart -eq 1) ("LEAVING PART (a) SENDS PART (a), BY ITSELF, while (b) and (c) are still empty; the caret is in (b) (" + (Get-SaidLine 1) + ")")
$one = Get-Shown 1
Check ($one.thread.turn -ceq "founder" -and (@($one.thread.parts | ForEach-Object { $_.letter + ":" + $_.answered }) -join ",") -ceq "a:True,b:False,c:False" -and $one.thread.messages[0].partWords -ceq "The sentence when she cannot move the picture: approve, or reword." -and $one.thread.messages[0].route -ceq "window") "the store holds it as the answer to part (a), typed in the window; (b) and (c) are not answered, and the question is still his"
$green = Wait-Report { param($x) $l = @($x.drawn.lines | Where-Object { $_.n -ceq "1" })[0]; $null -ne $l -and ($l.pg[0] -eq $true -or $l.pd[0] -eq $true) } 20
Check ($null -ne (Get-Line $green 1) -and (Get-Line $green 1).pg[0] -eq $true -and (Get-Line $green 1).pd[0] -eq $false -and (Get-Line $green 1).pm[0] -ceq "saved" -and (Get-Line $green 1).pg[1] -eq $false -and (Get-Line $green 1).pd[1] -eq $false) ("SAVED, PART (a) STANDS GREEN, marked saved - and only part (a) (green " + (@((Get-Line $green 1).pg) -join "|") + "; folded " + (@((Get-Line $green 1).pd) -join "|") + ")")
$folded = Wait-Report { param($x) $l = @($x.drawn.lines | Where-Object { $_.n -ceq "1" })[0]; $null -ne $l -and $l.pd[0] -eq $true } 20
$l1 = Get-Line $folded 1
Check ($l1.pd[0] -eq $true -and $l1.pm[0] -ceq "Answered" -and $l1.pt[0] -ceq "a - approved as written" -and (@($l1.pd) -join "|") -ceq "True|False|False" -and $l1.ad -eq "" -and $l1.z -ceq "main") ("A MOMENT LATER PART (a) FOLDS to his words and the word Answered; the other two are open, and the question is still in his list (" + (@($l1.pm) -join "|") + ")")
Check ($folded.drawn.answer.focus -ceq "1" -and $folded.drawn.answer.focusPart -eq 1) "and nothing moved the caret: it is still in part (b)"
$r = Send-Probe -Keys @((Typed "no, keep Live View"), (Key "Enter")) -Steps @((Step "settle"))
Check ((Get-SaidLine 1) -ceq "a=a - approved as written | b=no, keep Live View" -and $r.drawn.answer.focus -ceq "1" -and $r.drawn.answer.focusPart -eq 2) ("ENTER SENDS PART (b), by itself, and goes to part (c) (" + (Get-SaidLine 1) + ")")
$inbox = Horde @("inbox", "-Peek")
Check ($inbox.code -eq 0 -and $inbox.out -like "*(answers part (a): The sentence when she cannot move the picture: approve, or reword.)*" -and $inbox.out -like "*(answers part (b): Should the button inside the Reader say Video too?)*" -and $inbox.out -like "*a - approved as written*" -and $inbox.out -like "*no, keep Live View*") "THE KEEPER'S INBOX SAYS WHICH PART each of his two answers is for, by its letter and its words"
$listed = Horde @("list")
Check ($listed.code -eq 0 -and $listed.out -like "*parts answered: (a), (b) of 3; turn: the founder*") "and the keeper's list says two of three parts are answered, and that it is still his turn"

Write-Host ""
Write-Host "=== the last part answered: the question folds to Answered and leaves his list ===" -ForegroundColor Cyan
$r = Send-Probe -Keys @((Key "Tab")) -Steps @((Step "settle"))
Check ($r.drawn.answer.focus -ceq "1" -and $r.drawn.answer.focusPart -eq 2 -and (Get-Line $r 1).pa[2] -ceq "yes, with a sentence in the same style." -and @(Get-Said 1).Count -eq 2) "Tab on an empty part with a suggestion fills it in and stays, and sends nothing yet"
$r = Send-Probe -Keys @((Key "Enter")) -Steps @((Step "settle"))
Check ((Get-SaidLine 1) -ceq "a=a - approved as written | b=no, keep Live View | c=yes, with a sentence in the same style." -and $r.drawn.answer.focus -ceq "2" -and $r.drawn.answer.focusPart -eq 0) ("Enter sends part (c) and goes to the first part of question 2 (" + (Get-SaidLine 1) + ")")
Check ((Get-Shown 1).thread.turn -ceq "warchief") "with every part answered the store says it is the keeper's turn"
$whole = Wait-Report { param($x) $l = @($x.drawn.lines | Where-Object { $_.n -ceq "1" })[0]; ($null -ne $l -and "$($l.ad)" -ceq "Answered") -or ($null -eq $l -and @($x.drawn.done | Where-Object { $_.n -ceq "1" }).Count -eq 1) } 25
Check ($null -ne (Get-Line $whole 1) -and (Get-Line $whole 1).ad -ceq "Answered" -and (@((Get-Line $whole 1).pd) -join "|") -ceq "True|True|True") "ALL ITS PARTS ANSWERED, THE QUESTION FOLDS to the one word Answered"
$gone = Wait-Report { param($x) $null -eq (@($x.drawn.lines | Where-Object { $_.n -ceq "1" })[0]) -and @($x.drawn.done | Where-Object { $_.n -ceq "1" }).Count -eq 1 } 30
Check ($null -eq (Get-Line $gone 1) -and (Get-Done $gone 1).k -ceq "thrall" -and (Get-Done $gone 1).a -ceq "(a) a - approved as written`n(b) no, keep Live View`n(c) yes, with a sentence in the same style.") ("AND LEAVES HIS LIST for the folded With Thrall, his three answers shown as one, a line a part (" + ((Get-Done $gone 1).a -replace "`n", " / ") + ")")

Write-Host ""
Write-Host "=== a part that is NOT saved: no green, the reason under that part, its words kept, the other parts untouched ===" -ForegroundColor Cyan
$secret = "the key is ghp_" + ("B" * 36)
$r = Send-Probe -Steps @((Step "focus" -Q 2 -Part 0))
$r = Send-Probe -Keys @((Typed $secret), (Key "Enter")) -Steps @((Step "settle"))
$refused = Wait-Report { param($x) "$((@($x.drawn.lines | Where-Object { $_.n -ceq '2' })[0]).pr[0])" -ne "" } 30
$l2 = Get-Line $refused 2
Check ($l2.pr[0] -clike "Not saved:*" -and $l2.pr[0] -notlike "*ghp_*" -and $l2.pr[1] -eq "" -and $l2.pg[0] -eq $false -and $l2.pd[0] -eq $false -and $l2.pa[0] -ceq $secret -and @(Get-Said 2).Count -eq 0) ("A PART THAT WAS NOT SAVED DOES NOT GO GREEN: the reason stands under that part, which repeats none of his words, and the words are kept (" + $l2.pr[0] + ")")
Check ($refused.drawn.answer.focus -ceq "2" -and $refused.drawn.answer.focusPart -eq 0) "and the caret is brought back to the part that was not saved"
Start-Sleep -Seconds 5
$still = Read-HordeProbeReport -Path $report
Check ((Get-Line $still 2).pg[0] -eq $false -and (Get-Line $still 2).pd[0] -eq $false -and (Get-Line $still 2).pa[0] -ceq $secret) "it stays so, longer than a saved part takes to fold"
$r = Send-Probe -Keys @((Key "a" -Ctrl), (Typed "as the plan says"), (Key "Enter")) -Steps @((Step "settle"))
Check ((Get-SaidLine 2) -ceq "a=as the plan says" -and (Get-Line $r 2).pr[0] -eq "" -and $r.drawn.answer.focusPart -eq 1) ("with other words the same part is saved, and its refusal is gone (" + (Get-SaidLine 2) + ")")

Write-Host ""
Write-Host "=== a part he has answered can still be changed while the question is in his list ===" -ForegroundColor Cyan
$folded2 = Wait-Report { param($x) $l = @($x.drawn.lines | Where-Object { $_.n -ceq "2" })[0]; $null -ne $l -and $l.pd[0] -eq $true } 20
Check ((Get-Line $folded2 2).pd[0] -eq $true -and (Get-Line $folded2 2).pt[0] -ceq "as the plan says" -and (Get-Line $folded2 2).z -ceq "main") "part (a) of question 2 is folded to Answered; part (b) is open, so the question is still in his list"
$r = Send-Probe -Steps @((Step "focus" -Q 2 -Part 0))
Check ($r.drawn.answer.focus -ceq "2" -and $r.drawn.answer.focusPart -eq 0 -and (Get-Line $r 2).pd[0] -eq $false -and (Get-Line $r 2).pa[0] -ceq "as the plan says") "a press on the folded part brings its field back, his words in it, the caret there"
$r = Send-Probe -Keys @((Key "a" -Ctrl), (Typed "as the plan says, but a week later"), (Key "Enter")) -Steps @((Step "settle"))
$said2 = @(Get-Said 2)
Check ($said2.Count -eq 2 -and $said2[1].part -ceq "a" -and $said2[1].text -ceq "as the plan says, but a week later" -and $said2[1].replaces -eq $true -and (Get-Shown 2).thread.turn -ceq "founder") "his change is a second record for part (a), which the store says replaces his first; part (b) is still to answer"
$r = Send-Probe -Keys @((Typed "second: yes"), (Key "Enter")) -Steps @((Step "settle"))
$gone2 = Wait-Report { param($x) $null -eq (@($x.drawn.lines | Where-Object { $_.n -ceq "2" })[0]) -and @($x.drawn.done | Where-Object { $_.n -ceq "2" }).Count -eq 1 } 30
Check ((Get-Done $gone2 2).a -ceq "(a) as the plan says, but a week later`n(b) second: yes" -and (Get-Shown 2).thread.turn -ceq "warchief") "with part (b) answered question 2 leaves his list too, showing each part's LAST answer"

Write-Host ""
Write-Host "=== Ctrl+Enter on the first part with every part empty takes every suggestion, and sends each part ===" -ForegroundColor Cyan
$r = Send-Probe -Steps @((Step "focus" -Q 3 -Part 0))
$r = Send-Probe -Keys @((Key "Enter" -Ctrl)) -Steps @((Step "settle"))
Check ((Get-SaidLine 3) -ceq "a=one | b=two | c=three" -and $r.drawn.answer.focus -ceq "4") ("every part's suggestion, each sent as its own answer, and on to question 4 (" + (Get-SaidLine 3) + ")")
$gone3 = Wait-Report { param($x) $null -eq (@($x.drawn.lines | Where-Object { $_.n -ceq "3" })[0]) -and @($x.drawn.done | Where-Object { $_.n -ceq "3" }).Count -eq 1 } 30
Check ((Get-Done $gone3 3).a -ceq "(a) one`n(b) two`n(c) three" -and (@($gone3.drawn.lines | ForEach-Object { $_.n }) -join ",") -ceq "4") "and question 3 leaves the list: only the plain question is left to answer"

Write-Host ""
Write-Host "=== an answer to all the parts in ONE message, as an earlier window sent it, still takes the question off his list ===" -ForegroundColor Cyan
$q5 = Join-Path $script:work "q5.json"
[System.IO.File]::WriteAllText($q5, '{"title":"Two more parts, answered the old way in one message.","kind":"parts","whatItIs":"Follow-ups.","parts":["(a) The first of the two.","(b) The second of the two."],"group":"Video Mode","askedBy":"Orc C"}', $utf8)
$add5 = Horde @("add", "-File", $q5)
$r = Wait-Report { param($x) $null -ne (@($x.drawn.lines | Where-Object { $_.n -ceq "5" })[0]) }
Check ($add5.code -eq 0 -and @((Get-Line $r 5).pa).Count -eq 2 -and (Get-Line $r 5).nw -eq $true) "a fifth question, of two parts, asked at the command line, appears with a field for each"
$both = Join-Path $script:work "both.txt"
[System.IO.File]::WriteAllText($both, ("(a) first: yes" + "`n" + "(b) second: no"), $utf8)
$whole5 = Horde @("answer", "5", "-File", $both)
$gone5 = Wait-Report { param($x) $null -eq (@($x.drawn.lines | Where-Object { $_.n -ceq "5" })[0]) -and @($x.drawn.done | Where-Object { $_.n -ceq "5" }).Count -eq 1 } 30
Check ($whole5.code -eq 0 -and (Get-Done $gone5 5).a -ceq "(a) first: yes`n(b) second: no" -and (Get-Shown 5).thread.turn -ceq "warchief" -and (Get-Said 5)[0].part -eq "") "one message that names no part is an answer to the whole question, as it always was: it is off his list, shown as he said it"

$closed = Close-HordeProbeWindow -Process $script:open.process -Handle ([long]$first.handle) -Seconds 40
Check ($closed.exited -and $closed.code -eq 0) "the window is closed and the command exits 0"
$final = Read-HordeProbeReport -Path $report
Check ($final.saysRefused -eq 1 -and @($final.errors).Count -eq 0) ("one part was refused - the one that held a secret - and nothing failed inside the window (refused " + $final.saysRefused + "; " + (@($final.errors) -join " | ") + ")")

} finally {
    if ($null -ne $script:open -and -not $script:open.process.HasExited) { try { $script:open.process.Kill() } catch { } }
    Start-Sleep -Milliseconds 500
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-answer-parts-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) {
        for ($i = 0; $i -lt 20 -and (Test-Path -LiteralPath $script:work); $i++) { try { Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction Stop } catch { Start-Sleep -Milliseconds 500 } }
    }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the scenario's temp folder is removed"

Complete-HordeSuite -Success "a question of parts is answered part by part with real keys: each part is sent by itself, goes green and folds to Answered, and the question leaves his list when the last one is answered"
