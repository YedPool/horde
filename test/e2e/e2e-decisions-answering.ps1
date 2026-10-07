# END TO END: answering in the decisions window - a real window on a real list, opened where nobody
# sees it, its keys pressed INSIDE THE PAGE, and every answer read back through the operations.
#
# The user of this is a person with 22 questions waiting, who wants to run down all of them in one
# go: the caret already in the first unanswered field, Enter to save and move on, the recommendation
# standing in grey where he would type. This scenario is that run: the fields are there with no
# click; the question's text is whole; an answer typed and entered is one message in the store, and
# a doubled Enter is still one; a new line stays in the field; the suggestion is taken with Tab or
# the right arrow, and accepted with Ctrl+Enter; a refused answer keeps its words and the caret; a
# reply made at the real command line appears under the question with no reload; what a notifier
# announced and what was read show as marks; and a half-typed answer is still there when the window
# is closed and opened again.
#
# NO KEY IS SENT TO THE DESKTOP. A check cannot press a key in a window nobody may see, so the
# command's -Probe hands the page a file of steps and the page's own key handlers act them out on
# its own fields (decisions/page/list.js, drive). What is typed that way goes through the same
# handlers, the same bridge request and the same operation as a key pressed by hand; what is NOT
# covered is the engine turning a real key press into those events, and the window being given the
# keyboard by Windows.
#
# NO WINDOW IS SEEN AND NO KEYBOARD IS TAKEN: both windows are -Hidden. NO TERMINAL IS INVOLVED.
# HORDE_HOME is a folder this scenario made and removes; the real store is listed before and after.
# It costs nothing: no agent session.
#
# NOT CHECKED HERE: a field under the folded heading of closed questions (nothing here can unfold a
# heading); words said under a closed question are the handler's own suite's
# (test/test-decisions-window-say.ps1).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "test\lib\WindowProbe.ps1")

$script:work = Join-Path $env:TEMP ("horde-answer-e2e-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$hordeHome = Join-Path $script:work "home"
$store = Join-Path $hordeHome "store\decisions"
$report = Join-Path $script:work "report.json"
$script:probeFile = Join-Path $script:work "probe.json"
$toldFile = Join-Path $script:work "told.json"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$childEnv = @{ HORDE_HOME = $hordeHome; WEZFLEET_ROOT = (Join-Path $script:work "no-fleet"); PSModulePath = $null }
$cliEnv = @{ HORDE_HOME = $hordeHome; WEZFLEET_ROOT = (Join-Path $script:work "no-fleet") }
$script:probeN = 0
$script:open = $null

function Get-RealStoreListing {
    $real = Join-Path (Join-Path (Join-Path "$env:USERPROFILE" ".horde") "store") "decisions"
    if (-not (Test-Path -LiteralPath $real)) { return "(no store)" }
    return (@(Get-ChildItem -LiteralPath $real -Force | Sort-Object Name | ForEach-Object { $_.Name + "|" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks }) -join ";")
}
$realBefore = Get-RealStoreListing
function Get-Shown {
    # One question as the operation show answers it now, in this process: what the page is held against.
    param([int]$Number)
    $keep = $env:HORDE_HOME
    try { $env:HORDE_HOME = $hordeHome; return (Invoke-HordeDecision -Operation "show" -Request @{ number = $Number }).value.question } finally { $env:HORDE_HOME = $keep }
}
function Get-Said { param([int]$Number) return @((Get-Shown -Number $Number).thread.messages) }
function Write-Whole {
    # A file replaced whole: written beside itself and moved into place.
    param([string]$Path, [string]$Text)
    $temp = $Path + ".tmp"
    [System.IO.File]::WriteAllText($temp, $Text, $utf8)
    if (Test-Path -LiteralPath $Path -PathType Leaf) { [System.IO.File]::Replace($temp, $Path, [NullString]::Value) } else { [System.IO.File]::Move($temp, $Path) }
}
function Send-Steps {
    # Hand the page a set of steps and wait until it reports having acted them all out, with nothing
    # sent still unanswered. Returns that report.
    param([object[]]$Steps, [int]$Seconds = 120)
    $script:probeN++
    $n = $script:probeN
    Write-Whole -Path $script:probeFile -Text (ConvertTo-Json -InputObject ([ordered]@{ n = $n; steps = @($Steps) }) -Depth 5 -Compress)
    $script:wantProbe = $n
    return (Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds $Seconds -Until { param($r) $null -ne $r.drawn -and $null -ne $r.drawn.answer -and $r.drawn.answer.probe -eq $script:wantProbe -and $r.drawn.answer.pending -eq 0 })
}
function Get-Line { param($Report, [int]$Number) return @($Report.drawn.lines | Where-Object { $_.n -ceq ("" + $Number) })[0] }
function Step { param([string]$Do, $Q = $null, [string]$Text = "", [string]$Key = "", [switch]$Shift, [switch]$Ctrl)
    $s = [ordered]@{ do = $Do }
    if ($null -ne $Q) { $s["q"] = [int]$Q }
    if ($Do -ceq "type") { $s["text"] = $Text }
    if ($Do -ceq "sleep") { $s["ms"] = 500 }
    if ($Do -ceq "key") { $s["key"] = $Key; $s["shift"] = [bool]$Shift; $s["ctrl"] = [bool]$Ctrl }
    return [pscustomobject]$s
}

$again = $null
try {

Write-Host ""
Write-Host "=== a list of 22 questions: one very long, some with a recommendation and some with none ===" -ForegroundColor Cyan
$long = "Should the work that was parked yesterday be committed to a branch of its own exactly as it stands, with no change to it at all, so that the server work that links an email to a device can go to the test server without rolling back what was deployed there two days ago, and so that both then go there together?"
$keepHome = $env:HORDE_HOME
try {
    $env:HORDE_HOME = $hordeHome
    . (Join-Path $root "decisions\Operations.ps1")
    for ($n = 1; $n -le 22; $n++) {
        $asked = "Orc " + [string][char](65 + ($n % 4)); if ($n % 11 -eq 0) { $asked = "the warchief" }
        $title = "Should step " + $n + " of the plan go ahead as it is written?"
        if ($n -eq 13) { $title = $long }
        $question = [ordered]@{ title = $title; kind = "yes-no"; whatItIs = ("Step " + $n + " is ready and waits only for a yes."); group = @("Unblocks work now", "The study")[[int]($n -gt 11)]; askedBy = $asked }
        if ($n -ne 4) { $question["recommendation"] = @("yes.", "no, not in this pass", "yes, as it is written and no further")[$n % 3] }
        $added = Invoke-HordeDecision -Operation "add" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = $question }
        if ($added.state -cne "known" -or $added.value.outcome -cne "done" -or $added.value.number -ne $n) { throw ("question " + $n + " was not added: " + $added.state + " " + $added.reason) }
    }
    $list = @((Invoke-HordeDecision -Operation "list" -Request @{ state = "all" }).value.questions)
} finally { $env:HORDE_HOME = $keepHome }
Check ($list.Count -eq 22 -and @(Get-ChildItem -LiteralPath $store -File).Count -eq 22) "the store holds 22 questions"

Write-Host ""
Write-Host "=== the window is opened: 22 fields with no click, the recommendation in grey, every question whole ===" -ForegroundColor Cyan
$script:open = Start-HordeProbeCommand -Root $root -HordeArgs @("decisions", "open", "-Hidden", "-Report", $report, "-Probe", $script:probeFile, "-ToldMarks", $toldFile) -Env $childEnv
$first = Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds 150 -Until { param($r) $null -ne $r.drawn -and @($r.drawn.lines).Count -eq 22 -and $null -ne $r.drawn.answer }
$drawn = $first.drawn
Check ($null -ne $drawn -and @($drawn.lines).Count -eq 22) "the page reports the 22 question lines it drew"
Check ($drawn.answer.fields -eq 22 -and $first.says -eq 0) "ALL 22 ANSWER FIELDS ARE THERE TO TYPE IN, and nothing was clicked, unfolded or pressed to get them"
Check ((@($drawn.lines | Where-Object { [int]$_.fh -eq 1 -or "$($_.p)".Length -gt 30 }).Count) -eq 22 -and @($drawn.lines | Where-Object { "$($_.a)" -ne "" }).Count -eq 0) "each is empty and one line tall (a long suggestion may take a second line, never cut)"
$wantP = @($list | Sort-Object number | ForEach-Object { "" + $_.number + "|" + $_.recommendation }) -join "`n"
$gotP = @($drawn.lines | Sort-Object { [int]$_.n } | ForEach-Object { $_.n + "|" + $_.p }) -join "`n"
Check ($gotP -ceq $wantP -and (Get-Line $first 1).p -ceq "no, not in this pass" -and (Get-Line $first 4).p -ceq "") "THE GREY SUGGESTION in each field is that question's recommendation, word for word; a question with none has none"
$l13 = Get-Line $first 13
Check ($l13.t -ceq $long -and $l13.t -ceq "$((Get-Shown -Number 13).title)" -and $l13.t.Length -eq $long.Length) ("THE LONGEST QUESTION'S TEXT IS THE STORE'S, every character (" + $long.Length + " characters)")
Check ($l13.clip -eq $false -and [int]$l13.rows -ge 3) ("and nothing shortens it: no overflow is hidden, nothing is clamped or kept to one line, and it is drawn on " + $l13.rows + " lines")
Check (@($drawn.lines | Where-Object { $_.clip -ne $false }).Count -eq 0 -and @($drawn.lines | Where-Object { "$($_.s)" -ne "" }).Count -eq 0) "no question of the 22 is shortened, and none carries the muted suffix the read-only page had"
$got = @($drawn.lines | Sort-Object { [int]$_.n } | ForEach-Object { $_.n + "|" + $_.t }) -join "`n"
Check ($got -ceq (@($list | Sort-Object number | ForEach-Object { "" + $_.number + "|" + $_.title }) -join "`n")) "the number and the text of every line drawn are the list's"
Check ((Get-Line $first 1).l -ceq "B" -and (Get-Line $first 3).l -ceq "D" -and (Get-Line $first 4).l -ceq "A" -and (Get-Line $first 11).l -ceq "M" -and (Get-Line $first 22).l -ceq "M") "before each number stands the letter of the Orc that asked, and M for a question the keeper of the list asked"
Check ($drawn.foot -ceq "Enter: save and next. Tab: take the grey suggestion, else next. Ctrl+Enter: accept the suggestion. Shift+Enter or Ctrl+J: new line. F2: context.") "the last line of the page says what the keys do, in the owner's words"
Check ($drawn.answer.focus -ceq "" -and $drawn.answer.drafts -eq 0 -and "$($drawn.answer.storage)" -ceq "") "a hidden window has not been given the keyboard, so no field has the caret; no draft is kept yet, and drafts can be kept"
Check ("$($first.toldMarks.problem)" -clike "*is not there yet*" -and $first.toldMarks.told -eq 0) "the file of announced messages is not there yet: said, and nothing is marked"
Check ($first.refused -eq 0 -and $first.reportsRefused -eq 0 -and @($first.errors).Count -eq 0) "nothing was refused and nothing failed"
$text = $drawn.text
Check ([Math]::Abs([double]$text.fontPx - 14) -lt 0.5 -and [Math]::Abs([double]$text.linePx - 22) -lt 0.5 -and "$($text.weight)" -ceq "400") "the letters are still the settings' 14 on 22, weight 400"

Write-Host ""
Write-Host "=== the window is given the keyboard: the caret is in the first unanswered field ===" -ForegroundColor Cyan
$r = Send-Steps @((Step "keyboard"))
Check ($r.drawn.answer.focus -ceq "1") ("the caret is in question 1's field (" + $r.drawn.answer.focus + ")")

Write-Host ""
Write-Host "=== typed and Enter: ONE message, read back through the operation, and the caret in question 2 ===" -ForegroundColor Cyan
$clock = [System.Diagnostics.Stopwatch]::StartNew()
$r = Send-Steps @((Step "type" -Text "Yes - commit it as it stands."), (Step "key" -Key "Enter"), (Step "settle"))
$said1 = @(Get-Said 1)
Check ($said1.Count -eq 1 -and $said1[0].text -ceq "Yes - commit it as it stands.") ("question 1 holds one message, and it is what was typed (" + [Math]::Round($clock.Elapsed.TotalSeconds, 1) + " s from the steps being handed over to the page reporting it saved)")
Check ($said1[0].speaker -ceq "founder" -and $said1[0].route -ceq "window" -and $said1[0].wordingStated -eq $true -and $said1[0].wordingVersion -eq 1) "said by the founder, typed in the window, to the wording the page showed"
Check ($r.drawn.answer.focus -ceq "2") "THE CARET MOVED to question 2's field"
Check ((Get-Line $r 1).a -ceq "Yes - commit it as it stands." -and (Get-Line $r 1).m -ceq "saved" -and (Get-Line $r 1).r -ceq "" -and $r.drawn.answer.drafts -eq 0) "question 1's field shows his words, marked saved, and they are no longer a draft"
Check ($r.says -eq 1 -and $r.saysRefused -eq 0) "the window counts one answer stored"

Write-Host ""
Write-Host "=== Enter twice: still one message, and no question skipped ===" -ForegroundColor Cyan
$r = Send-Steps @((Step "type" -Text "Second answer"), (Step "key" -Key "Enter"), (Step "key" -Key "Enter"), (Step "settle"))
$said2 = @(Get-Said 2)
Check ($said2.Count -eq 1 -and $said2[0].text -ceq "Second answer") "A DOUBLE ENTER IS ONE MESSAGE under question 2"
Check ($r.drawn.answer.focus -ceq "3" -and @(Get-Said 3).Count -eq 0) "and the second press, landing on the empty field the caret had only just reached, skipped nothing: the caret is in question 3"
$r = Send-Steps @((Step "focus" -Q 2), (Step "key" -Key "Enter"), (Step "settle"))
Check (@(Get-Said 2).Count -eq 1 -and $r.drawn.answer.focus -ceq "3" -and $r.says -eq 2) "Enter on an answer that is already saved, unchanged, says nothing again and moves on"

Write-Host ""
Write-Host "=== Shift+Enter and Ctrl+J: a new line in the answer, the caret stays ===" -ForegroundColor Cyan
$r = Send-Steps @((Step "type" -Text "line one"), (Step "key" -Key "Enter" -Shift), (Step "type" -Text "line two"))
Check ($r.drawn.answer.focus -ceq "3" -and (Get-Line $r 3).a -ceq "line one`nline two" -and [int](Get-Line $r 3).fh -eq 2) "Shift+Enter added a line: the caret is still in question 3, the field holds two lines and is two lines tall"
Check (@(Get-Said 3).Count -eq 0 -and (Get-Line $r 3).m -ceq "draft" -and $r.drawn.answer.drafts -eq 1) "nothing was saved by it: the words are a draft"
$r = Send-Steps @((Step "key" -Key "j" -Ctrl), (Step "type" -Text "line three"))
Check ($r.drawn.answer.focus -ceq "3" -and (Get-Line $r 3).a -ceq "line one`nline two`nline three" -and [int](Get-Line $r 3).fh -eq 3) "Ctrl+J added a line the same way: three lines, the field three lines tall"
$r = Send-Steps @((Step "key" -Key "Enter"), (Step "settle"))
$said3 = @(Get-Said 3)
Check ($said3.Count -eq 1 -and $said3[0].text -ceq "line one`nline two`nline three" -and $r.drawn.answer.focus -ceq "4") "Enter then saved all three lines as one message, line breaks kept, and moved to question 4"

Write-Host ""
Write-Host "=== Tab and the right arrow take the grey suggestion; Tab otherwise moves on ===" -ForegroundColor Cyan
$r = Send-Steps @((Step "key" -Key "Tab"), (Step "settle"))
Check ($r.drawn.answer.focus -ceq "5" -and @(Get-Said 4).Count -eq 0 -and (Get-Line $r 4).a -ceq "") "Tab on an empty field with NO suggestion moves on: question 4 is skipped, nothing saved"
$rec5 = "$((Get-Shown -Number 5).recommendation)"
$r = Send-Steps @((Step "key" -Key "Tab"))
Check ($r.drawn.answer.focus -ceq "5" -and (Get-Line $r 5).a -ceq $rec5 -and $rec5 -ne "" -and @(Get-Said 5).Count -eq 0) "TAB ON AN EMPTY FIELD WITH A SUGGESTION FILLS IT IN, as text he can edit, and the caret stays; nothing is saved yet"
$r = Send-Steps @((Step "type" -Text " but only this once"), (Step "key" -Key "Tab"), (Step "settle"))
$said5 = @(Get-Said 5)
Check ($said5.Count -eq 1 -and $said5[0].text -ceq ($rec5 + " but only this once") -and $r.drawn.answer.focus -ceq "6") "TAB ON A FIELD WITH TEXT SAVES IT AND MOVES ON: the suggestion as he edited it is question 5's one message, the caret in question 6"
$rec6 = "$((Get-Shown -Number 6).recommendation)"
$r = Send-Steps @((Step "key" -Key "ArrowRight"))
Check ($r.drawn.answer.focus -ceq "6" -and (Get-Line $r 6).a -ceq $rec6 -and @(Get-Said 6).Count -eq 0) "the right arrow in an empty field does the same: the suggestion is filled in and the caret stays"
$r = Send-Steps @((Step "key" -Key "Tab" -Shift))
Check ($r.drawn.answer.focus -ceq "5" -and @(Get-Said 6).Count -eq 0 -and (Get-Line $r 6).a -ceq $rec6 -and (Get-Line $r 6).m -ceq "draft") "Shift+Tab goes back one, and what was left in question 6 stays there as a draft"

Write-Host ""
Write-Host "=== Ctrl+Enter on an empty field: the recommendation is his answer ===" -ForegroundColor Cyan
$rec7 = "$((Get-Shown -Number 7).recommendation)"
$r = Send-Steps @((Step "focus" -Q 7), (Step "key" -Key "Enter" -Ctrl), (Step "settle"))
$said7 = @(Get-Said 7)
Check ($said7.Count -eq 1 -and $said7[0].text -ceq $rec7 -and $rec7 -ne "" -and $said7[0].route -ceq "window") ("the store holds the recommendation's own text as his message under question 7 (" + $rec7 + ")")
Check ($r.drawn.answer.focus -ceq "8" -and (Get-Line $r 7).m -ceq "saved") "and the caret moved on to question 8"
$r = Send-Steps @((Step "focus" -Q 4), (Step "key" -Key "Enter" -Ctrl), (Step "settle"))
Check ($r.drawn.answer.focus -ceq "4" -and @(Get-Said 4).Count -eq 0) "where there is no recommendation Ctrl+Enter on an empty field saves nothing and stays"

Write-Host ""
Write-Host "=== a refused answer keeps its words, says why, and keeps the caret ===" -ForegroundColor Cyan
# Put together here so that this file holds nothing shaped like what it describes.
$unsafe = "use the admin login, the pass" + "word is " + "hunter" + "42x"
$r = Send-Steps @((Step "focus" -Q 8), (Step "type" -Text $unsafe), (Step "key" -Key "Enter"), (Step "settle"), (Step "sleep") )
$l8 = Get-Line $r 8
Check (@(Get-Said 8).Count -eq 0 -and $r.saysRefused -eq 1) "NOTHING WAS STORED under question 8: the operation's check for what must not be written refused it"
Check ($l8.a -ceq $unsafe -and $r.drawn.answer.drafts -ge 2) "the field still holds every word he typed, kept as a draft"
Check ($l8.r -clike "Not saved: the request holds what looks like a secret*" -and $l8.r -notlike "*hunter*") ("under it stands the refusal's own sentence, which repeats none of his words (" + $l8.r + ")")
Check ($r.drawn.answer.focus -ceq "8") "and the caret is in question 8's field: it did not move on"
$r = Send-Steps @((Step "key" -Key "a" -Ctrl), (Step "type" -Text " - on reflection, ask me in person"))
Check ((Get-Line $r 8).r -ceq "") "once he changes the words, the refusal of the old ones is gone"

Write-Host ""
Write-Host "=== F2 and Ctrl+Space unfold the context in place; the caret stays ===" -ForegroundColor Cyan
$r = Send-Steps @((Step "focus" -Q 9), (Step "key" -Key "F2"))
Check ((Get-Line $r 9).open -eq $true -and $r.drawn.answer.focus -ceq "9" -and @($r.drawn.sub | Where-Object { $_.n -clike "9.*" }).Count -ge 3) "F2 unfolds question 9's context under it, and the caret is still in its field"
$r = Send-Steps @((Step "key" -Key " " -Ctrl))
Check ((Get-Line $r 9).open -eq $false -and $r.drawn.answer.focus -ceq "9") "Ctrl+Space folds it again, the caret still there"

Write-Host ""
Write-Host "=== a reply made at the command line appears under the question, with no reload ===" -ForegroundColor Cyan
$reply = Invoke-HordeCliProcess -Root $root -HordeArgs @("decisions", "reply", "1", "-Text", "Which branch should it go to?") -Env $cliEnv
Check ($reply.code -eq 0) "the keeper of the list replies under question 1 with the real command"
$after = Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds 90 -Until { param($x) @((@($x.drawn.lines | Where-Object { $_.n -ceq "1" })[0]).th).Count -eq 2 }
$l1 = Get-Line $after 1
Check ((@($l1.th) -join " | ") -ceq "You: Yes - commit it as it stands. | Thrall: Which branch should it go to?") ("under question 1 stand his answer and then the reply, speaker and words, newest last (" + (@($l1.th) -join " | ") + ")")
Check ($l1.a -ceq "" -and $l1.m -ceq "") "and it is his turn again: the field under them is empty"
Check ($after.handle -eq $first.handle -and $after.pid -eq $first.pid -and $after.pushes -ge 1) "in the same window of the same process: the new list was pushed, nothing was reloaded"
Check ($after.drawn.answer.focus -ceq "9" -and (Get-Line $after 8).a -clike "*ask me in person" -and (Get-Line $after 6).a -ceq $rec6) "THE REDRAW TOOK NOTHING: the caret is where it was, and the two drafts are in their fields"

Write-Host ""
Write-Host "=== the marks: saved, then told, then read ===" -ForegroundColor Cyan
$seq2 = [long]$said2[0].sequence
[System.IO.File]::WriteAllText($toldFile, "this is not JSON {", $utf8)
$bad = Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds 60 -Until { param($x) "$($x.toldMarks.problem)" -clike "*could not be read as JSON*" }
Check ("$($bad.toldMarks.problem)" -clike "*could not be read as JSON*" -and (Get-Line $bad 2).m -ceq "saved") "a file of announced messages that is not JSON marks nothing, and the report says why; question 2 is still marked saved"
Write-Whole -Path $toldFile -Text (ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = 1; rung = @([ordered]@{ question = 2; message = ("" + $seq2); at = "2026-10-07T12:00:00Z" }) }) -Depth 4 -Compress)
$told = Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds 60 -Until { param($x) (@($x.drawn.lines | Where-Object { $_.n -ceq "2" })[0]).m -ceq "told Thrall" }
Check ((Get-Line $told 2).m -ceq "told Thrall" -and (Get-Line $told 3).m -ceq "saved" -and "$($told.toldMarks.problem)" -ceq "" -and $told.toldMarks.told -eq 1) "once the file names question 2's message, its mark reads told Thrall; question 3's, which it does not name, stays saved"
$inbox = Invoke-HordeCliProcess -Root $root -HordeArgs @("decisions", "inbox") -Env $cliEnv
Check ($inbox.code -eq 0 -and $inbox.out -like "*Second answer*" -and $inbox.out -like "*line one*line two*line three*" -and $inbox.out -like "*Marked as read*") "the keeper of the list reads its inbox with the real command: his words are printed exactly, and marked read"
$read = Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds 60 -Until { param($x) (@($x.drawn.lines | Where-Object { $_.n -ceq "2" })[0]).m -ceq "read by Thrall" }
Check ((Get-Line $read 2).m -ceq "read by Thrall" -and (Get-Line $read 3).m -ceq "read by Thrall" -and (Get-Line $read 7).m -ceq "read by Thrall") "and every answer it printed now reads read by Thrall in the window"

Write-Host ""
Write-Host "=== the keeper of the list adds a question and parks one: the page shows both, with no reload ===" -ForegroundColor Cyan
$q23 = Join-Path $script:work "q23.json"
[System.IO.File]::WriteAllText($q23, '{"title":"Is a question asked while the window is open shown in it?","kind":"yes-no","whatItIs":"Asked at the command line.","recommendation":"yes","group":"The study","askedBy":"Orc B"}', $utf8)
$add = Invoke-HordeCliProcess -Root $root -HordeArgs @("decisions", "add", "-File", $q23) -Env $cliEnv
$grown = Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds 90 -Until { param($x) @($x.drawn.lines).Count -eq 23 -and $x.drawn.answer.fields -eq 23 }
Check ($add.code -eq 0 -and (Get-Line $grown 23).t -ceq "Is a question asked while the window is open shown in it?" -and (Get-Line $grown 23).p -ceq "yes" -and $grown.drawn.answer.fields -eq 23) "a 23rd question asked at the command line appears with its own field and suggestion"
$park = Join-Path $script:work "park.json"
[System.IO.File]::WriteAllText($park, '{"group":"Parked"}', $utf8)
$parkedCli = Invoke-HordeCliProcess -Root $root -HordeArgs @("decisions", "update", "22", "-File", $park) -Env $cliEnv
$aside = Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds 90 -Until { param($x) @($x.drawn.headings | Where-Object { $_.parked }).Count -eq 1 }
$heads = @($aside.drawn.headings)
Check ($parkedCli.code -eq 0 -and (Get-Shown -Number 22).wordingVersion -eq 1 -and "$((Get-Shown -Number 22).group)" -ceq "Parked") "question 22 is parked with an ordinary update that changes only its group; its wording is still wording 1"
Check ($heads[$heads.Count - 1].t -ceq "Parked: 1 question" -and $heads[$heads.Count - 1].folded -eq $true -and $heads[$heads.Count - 1].parked -eq $true) ("PARKED STANDS AT THE FOOT OF THE PAGE AS ONE FOLDED LINE (" + $heads[$heads.Count - 1].t + ")")
Check (@($aside.drawn.lines).Count -eq 23 -and $aside.drawn.answer.fields -eq 22 -and $aside.handle -eq $first.handle -and $aside.pid -eq $first.pid) "all 23 questions are still drawn, 22 fields are in the run of answering, and it is the same window: nothing was reloaded"
$r = Send-Steps @((Step "focus" -Q 21), (Step "key" -Key "Enter"), (Step "sleep"), (Step "key" -Key "Enter"))
Check ($r.drawn.answer.focus -ceq "" -and $r.drawn.answer.focusHead -ceq "Parked: 1 question" -and @(Get-Said 22).Count -eq 0) "Enter runs from question 21 to 23 and then to the folded line, never into the parked question's field"
$r = Send-Steps @((Step "key" -Key "F2"))
Check ($r.drawn.answer.focus -ceq "22" -and $r.drawn.answer.fields -eq 23 -and @($r.drawn.headings | Where-Object { $_.parked })[0].folded -eq $false) "a key on that line unfolds it into the same row, with the caret in its field"

Write-Host ""
Write-Host "=== a half-typed answer survives the window being closed and opened again ===" -ForegroundColor Cyan
$r = Send-Steps @((Step "focus" -Q 10), (Step "type" -Text "half typed, not yet ent"))
Check ((Get-Line $r 10).a -ceq "half typed, not yet ent" -and @(Get-Said 10).Count -eq 0) "question 10 holds a half-typed answer that was never entered"
$closed = Close-HordeProbeWindow -Process $script:open.process -Handle ([long]$r.handle) -Seconds 40
Check ($closed.asked -and $closed.exited -and -not $closed.killed -and $closed.code -eq 0) "the window is closed as its close button would, and the command exits 0"
Check ($script:open.err.Result.Trim() -ceq "") "with nothing on the error stream"
$report2 = Join-Path $script:work "report2.json"
$again = Start-HordeProbeCommand -Root $root -HordeArgs @("decisions", "open", "-Hidden", "-Report", $report2, "-ToldMarks", $toldFile) -Env $childEnv
$back = Wait-HordeProbeReport -Path $report2 -Process $again.process -Seconds 150 -Until { param($x) $null -ne $x.drawn -and @($x.drawn.lines).Count -eq 23 -and $null -ne $x.drawn.answer }
Check ($back.pid -eq $again.process.Id -and $back.pid -ne $first.pid) "opened again: a new window, a new process"
Check ($back.drawn.answer.fields -eq 22 -and @($back.drawn.headings | Where-Object { $_.parked })[0].folded -eq $true) "what is parked is folded again, out of the way"
Check ((Get-Line $back 10).a -ceq "half typed, not yet ent" -and (Get-Line $back 10).m -ceq "draft") "THE HALF-TYPED ANSWER IS IN ITS FIELD, marked as a draft"
Check ((Get-Line $back 6).a -ceq $rec6 -and (Get-Line $back 8).a -clike "*ask me in person" -and $back.drawn.answer.drafts -eq 3) "and so are the other two drafts: three kept, by question number, in the page's own storage under the home"
Check ((Get-Line $back 2).a -ceq "Second answer" -and (Get-Line $back 2).m -ceq "read by Thrall" -and (Get-Line $back 3).a -ceq "line one`nline two`nline three") "the saved answers stand in their fields with their marks, from the store"
Check ((@((Get-Line $back 1).th) -join " | ") -ceq "You: Yes - commit it as it stands. | Thrall: Which branch should it go to?" -and (Get-Line $back 1).a -ceq "") "and question 1 shows the conversation, its field empty for his turn"
Check (@(Get-Said 10).Count -eq 0 -and @(Get-Said 6).Count -eq 0 -and @(Get-Said 8).Count -eq 0) "a draft is only ever the page's: none of the three is in the store"
$closed2 = Close-HordeProbeWindow -Process $again.process -Handle ([long]$back.handle) -Seconds 40
Check ($closed2.exited -and $closed2.code -eq 0 -and -not $closed2.killed) "that window closes as the first did, exit 0"

Write-Host ""
Write-Host "=== the state left behind ===" -ForegroundColor Cyan
$keepHome = $env:HORDE_HOME
try { $env:HORDE_HOME = $hordeHome; $all = @((Invoke-HordeDecision -Operation "list" -Request @{ state = "all" }).value.questions) } finally { $env:HORDE_HOME = $keepHome }
$counts = @($all | Sort-Object number | ForEach-Object { "" + $_.thread.count }) -join ","
Check ($counts -ceq "2,1,1,0,1,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0") ("the store holds exactly what was entered: five answers and one reply, each once (" + $counts + ")")
Check (@(Get-ChildItem -LiteralPath $store -File).Count -eq 31) "31 records: 23 questions, 5 answers, 1 reply, 1 marking as read, 1 change of group"

} finally {
    foreach ($held in @($script:open, $again)) { if ($null -ne $held -and -not $held.process.HasExited) { try { $held.process.Kill() } catch { } } }
    Start-Sleep -Milliseconds 500
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-answer-e2e-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) {
        for ($i = 0; $i -lt 20 -and (Test-Path -LiteralPath $script:work); $i++) { try { Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction Stop } catch { Start-Sleep -Milliseconds 500 } }
    }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the scenario's temp folder is removed"
Check ((Get-RealStoreListing) -ceq $realBefore) "the real store under the user profile is exactly as it was before the scenario"

Complete-HordeSuite -Success "a person runs down the list in the window: every key does what the last line says, every answer is one message in the store, nothing typed is lost"
