# END TO END: a working day of the decisions list, driven through the horde command line as its user
# drives it.
#
# The user of these commands is the session that keeps the list for a person. This scenario is its
# day, from an empty list: it asks three questions of different kinds from files, reads the list back,
# rewords one, closes one with what was done, asks a fourth, and reopens the closed one. Then a whole
# exchange under one question: the person answers in chat and the session writes his words down, reads
# its inbox, replies, closes the question - and he says one thing more after it is closed. Each step is
# the shipped horde.ps1 run as its own process (test/lib/Cli.ps1), and each check is on what that
# session would SEE - the printed lines, the exit code - and, at the end, on the state left behind in
# the store.
#
# THE POINT OF THE DAY is the promise the list exists for: a question's number never changes. Question
# 2 is question 2 when it is asked, when its neighbour closes, when another is added, and at the end.
#
# NO TERMINAL IS INVOLVED. The commands start no pane and touch no session, so this needs no isolated
# terminal (CONTRIBUTING 2 and 3). HORDE_HOME is a folder this scenario made and removes; the real
# store is listed before and after and must not have changed (CONTRIBUTING 9). It costs nothing to
# run: no agent session is started.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")

$script:work = Join-Path $env:TEMP ("horde-decisions-e2e-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$hordeHome = Join-Path $script:work "home"
$store = Join-Path $hordeHome "store\decisions"
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-RealStoreListing {
    $real = Join-Path (Join-Path (Join-Path "$env:USERPROFILE" ".horde") "store") "decisions"
    if (-not (Test-Path -LiteralPath $real)) { return "(no store)" }
    return (@(Get-ChildItem -LiteralPath $real -Force | Sort-Object Name | ForEach-Object { $_.Name + "|" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks }) -join ";")
}
$realBefore = Get-RealStoreListing

function Invoke-Decisions {
    param([string[]]$HordeArgs)
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs (@("decisions") + $HordeArgs) -Env @{ HORDE_HOME = $hordeHome }
    return [pscustomobject]@{ code = $r.code; out = $r.out; lines = @($r.out -split "\r?\n") }
}
function Write-File { param([string]$Name, [string]$Text) $p = Join-Path $script:work $Name; [System.IO.File]::WriteAllText($p, $Text, $utf8); return $p }
function Get-QuestionLines {
    # The numbered question lines of a printed list, as "number|title".
    param($Run)
    return (@($Run.lines | ForEach-Object { if ($_ -match '\A\s+([0-9]+)\. (.+)\z') { $Matches[1] + "|" + $Matches[2] } }) -join ";")
}

try {

Write-Host ""
Write-Host "=== the list starts empty ===" -ForegroundColor Cyan
$empty = Invoke-Decisions @("list")
Check ($empty.code -eq 0 -and $empty.out -like "*Decisions: 0 open, 0 closed.*" -and $empty.out -like "*No question to show (open).*") "before anything is asked, list says there are none, and exits 0"
Check (-not (Test-Path -LiteralPath $hordeHome)) "and reading an empty list made no folder"

Write-Host ""
Write-Host "=== three questions are asked, each from a file ===" -ForegroundColor Cyan
$q1 = Write-File "q1.json" '{"title":"Fix the bug where one registration code can register two devices?","kind":"yes-no","whatItIs":"If two requests arrive at the same instant with the same one-time code, both succeed: two devices from one code.","yesMeans":"A small server change makes the second request fail.","recommendation":"yes","group":"security and accounts","askedBy":"orc-d","waiting":["orc-d"],"references":["issue 94"]}'
$q2 = Write-File "q2.json" '{"title":"Which languages besides English should the test talker speak?","kind":"choice","options":["Hebrew","Spanish","both","none"],"whatItIs":"The recordings so far use one English voice. The app ships all three languages.","group":"the voice test","groupNote":"Needed before a user could ever interrupt the assistant.","askedBy":"orc-b","waiting":["orc-b"]}'
$q3 = Write-File "q3.json" '{"title":"Can a test account be provided for the signed-in pages?","kind":"yes-no","whatItIs":"The study measured only signed-out pages; search and book pages sit behind a login.","yesMeans":"A test login is given outside this list: typed into the session, or as a file path.","recommendation":"yes","group":"security and accounts","askedBy":"orc-e","waiting":["orc-e"],"needsSecret":true}'
$a1 = Invoke-Decisions @("add", "-File", $q1)
$a2 = Invoke-Decisions @("add", "-File", $q2)
$a3 = Invoke-Decisions @("add", "-File", $q3)
Check ($a1.code -eq 0 -and $a1.out -like "*Added question 1: Fix the bug where one registration code can register two devices?*") "the first is added and its number, 1, is printed with its words"
Check ($a2.code -eq 0 -and $a2.out -like "*Added question 2: Which languages besides English should the test talker speak?*") "the second is number 2"
Check ($a3.code -eq 0 -and $a3.out -like "*Added question 3: Can a test account be provided for the signed-in pages?*") "the third is number 3"

Write-Host ""
Write-Host "=== the list, as the person it is for would read it ===" -ForegroundColor Cyan
$list = Invoke-Decisions @("list")
Check ($list.code -eq 0 -and $list.out -like "*Decisions: 3 open, 0 closed.*") "list says three are open"
Check ((Get-QuestionLines $list) -ceq "1|Fix the bug where one registration code can register two devices?;3|Can a test account be provided for the signed-in pages?;2|Which languages besides English should the test talker speak?") "the questions are under their two groups, each with its number: 1 and 3 together, then 2"
Check (@($list.lines | Where-Object { $_ -ceq "security and accounts" -or $_ -ceq "the voice test" }).Count -eq 2 -and $list.out -like "*(Needed before a user could ever interrupt the assistant.)*") "the group headings and the group's note are shown"
Check ($list.out -like "*yes or no; asked by orc-e; waiting: orc-e; needs a secret*" -and $list.out -like "*recommended: yes*") "the question that needs a login says so, and a recommendation is shown where there is one"

Write-Host ""
Write-Host "=== question 2 is reworded ===" -ForegroundColor Cyan
$change = Write-File "change.json" '{"options":["Hebrew","Spanish","both","none for now"],"recommendation":"none for now: English is enough to learn whether it works"}'
$upd = Invoke-Decisions @("update", "2", "-File", $change)
Check ($upd.code -eq 0 -and $upd.out -like "*Changed question 2:*" -and $upd.out -like "*changed options, recommendation (now wording 2)*") "the change is made to question 2 and says the wording is now 2"
$show = Invoke-Decisions @("show", "2")
Check ($show.code -eq 0 -and @($show.lines | Where-Object { $_ -ceq "Question 2 - open (wording 2)" }).Count -eq 1 -and @($show.lines | Where-Object { $_ -ceq "  4. none for now" }).Count -eq 1) "show 2 gives the question at wording 2, with the new option"
Check (@($show.lines | Where-Object { $_ -like "*added (by warchief, record 2)" -or $_ -like "*changed options, recommendation (now wording 2) (by warchief, record 4)" }).Count -eq 2) "and its history: added, then changed, each with who and which record"

Write-Host ""
Write-Host "=== question 1 is closed with what was done ===" -ForegroundColor Cyan
$outcome = Write-File "outcome.txt" ("Fixed: the second request with the same code now fails." + "`n" + "Merged and deployed to the test server; production follows the next release.")
$close = Invoke-Decisions @("close", "1", "-OutcomeFile", $outcome)
Check ($close.code -eq 0 -and $close.out -like "*Closed question 1: Fix the bug where one registration code can register two devices?*") "question 1 is closed"
$open = Invoke-Decisions @("list")
Check ($open.out -like "*Decisions: 2 open, 1 closed.*" -and (Get-QuestionLines $open) -ceq "2|Which languages besides English should the test talker speak?;3|Can a test account be provided for the signed-in pages?") "the open list now shows 2 and 3 - under the numbers they always had, with a gap where 1 was"

Write-Host ""
Write-Host "=== a fourth question is asked: it is 4, not 1 ===" -ForegroundColor Cyan
$q4 = Write-File "q4.json" '{"title":"Test the view-on-screen fix on a device, then say merge?","kind":"do-then-say","whatItIs":"Voice commands now check what is really on screen before acting.","yesMeans":"It merges and ships in the next test build.","recommendation":"test, then yes","group":"form fill","askedBy":"orc-c","waiting":["orc-c"],"files":["notes\\device-steps.md"],"references":["PR 1583"]}'
$a4 = Invoke-Decisions @("add", "-File", $q4)
Check ($a4.code -eq 0 -and $a4.out -like "*Added question 4: Test the view-on-screen fix on a device, then say merge?*") "the new question is number 4: the closed number 1 is not given again"

Write-Host ""
Write-Host "=== question 1 comes back ===" -ForegroundColor Cyan
$reopen = Invoke-Decisions @("reopen", "1", "-Reason", "a second device was registered from one code again on the test server")
Check ($reopen.code -eq 0 -and $reopen.out -like "*Reopened question 1: Fix the bug where one registration code can register two devices?*") "question 1 is reopened as question 1"
$all = Invoke-Decisions @("list", "-State", "all")
Check ($all.out -like "*Decisions: 4 open, 0 closed.*" -and (Get-QuestionLines $all) -ceq "1|Fix the bug where one registration code can register two devices?;3|Can a test account be provided for the signed-in pages?;2|Which languages besides English should the test talker speak?;4|Test the view-on-screen fix on a device, then say merge?") "at the end of the day all four are open, each under the number it was given when it was asked"
$one = Invoke-Decisions @("show", "1")
Check ($one.out -like "*Last reopened because: a second device was registered from one code again on the test server*" -and @($one.lines | Where-Object { $_ -like "*  added (by*" -or $_ -like "*  closed (by*" -or $_ -like "*  reopened (by*" }).Count -eq 3) "show 1 says why it is open again, and its history holds the add, the close and the reopen"

Write-Host ""
Write-Host "=== a whole exchange under question 2 ===" -ForegroundColor Cyan
# The person answers question 2 in chat, in two lines. The session writes his words down exactly, from
# a file: they are his words, recorded by the session, and are stored and shown as that.
$saidFile = Write-File "said.txt" ("Both, but Hebrew first." + "`r`n" + "Which voice would the Spanish one be?")
$answer = Invoke-Decisions @("answer", "2", "-File", $saidFile)
Check ($answer.code -eq 0 -and $answer.out -like "*Kept the founder's words, recorded by the warchief from chat, under question 2 (record 8): Which languages besides English should the test talker speak?*") "answer writes the person's chat words down under question 2, and says they are his words as recorded from chat"
$waiting = Invoke-Decisions @("list")
Check ($waiting.code -eq 0 -and @($waiting.lines | Where-Object { $_.Trim() -ceq "conversation: 1 message(s); 1 not yet read by the warchief; turn: the warchief" }).Count -eq 1) "the list shows that question 2 has one message, not yet read, and that it is the session's turn"
$inbox = Invoke-Decisions @("inbox")
Check ($inbox.code -eq 0 -and @($inbox.lines | Where-Object { $_ -ceq "1 message(s) not yet read, oldest first:" }).Count -eq 1 -and @($inbox.lines | Where-Object { $_ -ceq "Question 2: Which languages besides English should the test talker speak?" }).Count -eq 1) "inbox prints what he said, under the question's number and its plain-words title"
Check (@($inbox.lines | Where-Object { $_ -ceq "      Both, but Hebrew first." -or $_ -ceq "      Which voice would the Spanish one be?" }).Count -eq 2 -and @($inbox.lines | Where-Object { $_ -like "  the founder, recorded by the warchief from chat, * UTC (record 8, wording not stated)" }).Count -eq 1) "both of his lines, exactly, with who said them, how they were recorded, and that which wording he saw was not stated"
Check (@($inbox.lines | Where-Object { $_ -ceq "Marked as read: 1 message(s), up to record 8." }).Count -eq 1) "and then, having printed them, it marks them read and says so"
$inboxAgain = Invoke-Decisions @("inbox")
Check ($inboxAgain.code -eq 0 -and $inboxAgain.out -like "*Nothing unread*" -and $inboxAgain.out -notlike "*Marked as read*") "the inbox read again is empty: nothing is handed over twice, and nothing is marked"
$reply = Invoke-Decisions @("reply", "2", "-Text", "A second voice, recorded this week; Hebrew goes first.")
Check ($reply.code -eq 0 -and $reply.out -like "*Replied under question 2 (record 10): Which languages besides English should the test talker speak?*") "reply puts the session's answer under the same question"
$thread = Invoke-Decisions @("show", "2")
Check ($thread.code -eq 0 -and @($thread.lines | Where-Object { $_ -ceq "Conversation: 2 message(s); turn: the founder" }).Count -eq 1) "show 2 gives the conversation: two messages, and it is the person's turn again"
$saidAt = [array]::IndexOf($thread.lines, "      Which voice would the Spanish one be?")
$repliedAt = [array]::IndexOf($thread.lines, "      A second voice, recorded this week; Hebrew goes first.")
Check ($saidAt -gt 0 -and $repliedAt -gt $saidAt -and @($thread.lines | Where-Object { $_ -like "  the warchief, by command, * UTC (record 10, wording not stated)" }).Count -eq 1) "his words first and the reply after them, each with who said it and by what route"
Check (@($thread.lines | Where-Object { $_ -ceq "Question 2 - open (wording 2)" }).Count -eq 1 -and @($thread.lines | Where-Object { $_ -like "*(by warchief, record *" }).Count -eq 2) "and question 2 is still question 2, open, at wording 2, with the same two records in its history: talking changed nothing of it"
$close2 = Invoke-Decisions @("close", "2", "-Outcome", "Hebrew first, then Spanish with a second voice.")
$late = Invoke-Decisions @("answer", "2", "-Text", "Keep the English one too.")
Check ($close2.code -eq 0 -and $late.code -eq 0 -and $late.out -like "*under question 2 (record 12)*" -and $late.out -like "*NOTE: question 2 is closed. The words are kept under it, and it stays closed: saying something reopens nothing.*") "what he says a moment after the question is closed is kept, and the command says the question stays closed"
# The session reads its inbox as data this time. With -Json nothing is marked: the line says so and
# names the last record it holds; the session, having received it, marks explicitly.
$asData = Invoke-Decisions @("inbox", "-Json")
$line = @($asData.lines | Where-Object { $_.StartsWith('{"state":') }) | Select-Object -First 1
$data = $null
try { $data = ($line | ConvertFrom-Json) } catch { }
Check ($asData.code -eq 0 -and $null -ne $data -and @($data.value.messages).Count -eq 1 -and $data.value.messages[0].number -eq 2 -and $data.value.messages[0].state -ceq "closed" -and $data.value.messages[0].message.text -ceq "Keep the English one too." -and $data.value.messages[0].message.arrivedAfterClosing -eq $true) "inbox -Json hands the late words over as data, under the closed question, flagged as having arrived after closing"
Check ($null -ne $data -and $data.marked -eq $false -and $data.upTo -eq 12 -and @(Get-ChildItem -LiteralPath $store -File).Count -eq 12) "and marks nothing: the line says so, names record 12 as the last it showed, and the store has no new record"
$marked = Invoke-Decisions @("mark-read", "-UpTo", "12")
Check ($marked.code -eq 0 -and @($marked.lines | Where-Object { $_ -ceq "Marked as read: 1 message(s), up to record 12." }).Count -eq 1) "mark-read -UpTo 12 then marks what the session received"
$drained = Invoke-Decisions @("inbox")
Check ($drained.code -eq 0 -and $drained.out -like "*Nothing unread*") "and the inbox is empty"
$end = Invoke-Decisions @("list", "-State", "all")
Check ($end.out -like "*Decisions: 3 open, 1 closed.*" -and (Get-QuestionLines $end) -ceq "1|Fix the bug where one registration code can register two devices?;3|Can a test account be provided for the signed-in pages?;2|Which languages besides English should the test talker speak?;4|Test the view-on-screen fix on a device, then say merge?") "at the end of the day every question has the number it was given, and question 2 is closed: his late words reopened nothing"

Write-Host ""
Write-Host "=== the state left behind ===" -ForegroundColor Cyan
$names = @(Get-ChildItem -LiteralPath $store -File | Sort-Object Name | ForEach-Object { $_.Name })
Check (($names -join ",") -ceq ((1..13 | ForEach-Object { $_.ToString("D10") + ".json" }) -join ",")) "the store holds thirteen records, one for each command that changed the list or marked something read, named 1 to 12"
$kinds = @($names | ForEach-Object { ([System.IO.File]::ReadAllText((Join-Path $store $_)) | ConvertFrom-Json).kind })
Check (($kinds -join ",") -ceq "question-added,question-added,question-added,question-updated,question-closed,question-added,question-reopened,message-said,messages-read,message-said,question-closed,message-said,messages-read") "in the order the day went: three asked, one reworded, one closed, one asked, one reopened; then said, read, replied, closed, said once more, and read"
$kept = ([System.IO.File]::ReadAllText((Join-Path $store "0000000008.json"), $utf8) | ConvertFrom-Json)
Check ($kept.data.text -ceq ("Both, but Hebrew first." + "`r`n" + "Which voice would the Spanish one be?") -and $kept.data.speaker -ceq "founder" -and $kept.data.route -ceq "chat-recorded" -and $kept.actor -ceq "warchief") "his words are in their record exactly as the file held them, line break and all, as his, recorded by the session"
Check (@(Get-ChildItem -LiteralPath $hordeHome -Recurse -File).Count -eq 13) "and nothing else was written anywhere under the home: no index, no copy of the list, no lock"

} finally {
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-decisions-e2e-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the scenario's temp folder is removed"
Check ((Get-RealStoreListing) -ceq $realBefore) "the real store under the user profile is exactly as it was before the scenario"

Complete-HordeSuite -Success "a day of the decisions list at the real command line: every question keeps its number, what was said under one is handed over whole, and the store holds exactly what was done"
