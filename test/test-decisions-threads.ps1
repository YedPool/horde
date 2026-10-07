# IS WHAT SOMEONE SAYS UNDER A QUESTION KEPT, WHOLE AND ONCE, AND HANDED TO ITS READER WITHOUT ONE WORD LOST?
#
# The conversation under a question, through decisions/Operations.ps1's one entry point, in this
# process, against stores this suite makes: the operations say and inbox, and the thread that list
# and show hand back. It attacks what the person who speaks, and the session that reads him, rely on:
#   - WORDS ARE KEPT VERBATIM, ONCE: Hebrew with its direction marks, 100,000 characters, spaces and
#     line breaks exactly; a double submit of one id is one message, and two messages are two;
#   - WORDS ARE NEVER DROPPED: said under a question closed a moment earlier, or to a wording that has
#     moved on, they are stored and flagged, and change nothing of the question;
#   - NOTHING IS MARKED READ UNSEEN: an inbox hands back exactly what it marks, a bound is honoured, a
#     second inbox is empty, and reading alone marks nothing and writes nothing;
#   - A SECRET IS REFUSED WITHOUT BEING REPEATED, and who may speak, by what route, and who may record
#     whose words are the rules' closed lists - which did not widen who may change the list.
# Writers in separate processes - a say racing a close, an inbox racing a new message, a writer killed
# inside a say - are test/test-decisions-threads-race.ps1; the command line is test/test-decisions-cli.ps1.
#
# EVERY STORE IS A FOLDER THIS SUITE MADE under %TEMP% and removes (CONTRIBUTING 9), named in each call
# with -Root. The real store under the user profile is listed before and after, and must not have changed.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "decisions\Operations.ps1")

$defs = Get-HordeDecisionDefinitions
$script:work = Join-Path $env:TEMP ("horde-decisions-threads-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$script:n = 0
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-RealStoreListing {
    $real = Join-Path (Join-Path (Join-Path "$env:USERPROFILE" ".horde") "store") "decisions"
    if (-not (Test-Path -LiteralPath $real)) { return "(no store)" }
    return (@(Get-ChildItem -LiteralPath $real -Force | Sort-Object Name | ForEach-Object { $_.Name + "|" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks }) -join ";")
}
$realBefore = Get-RealStoreListing

function New-TestStore { $script:n++; return (Join-Path $script:work ("home-" + $script:n + "\store\decisions")) }
function New-Id { return [guid]::NewGuid().ToString("N") }
function Invoke-Op {
    # One operation against a store of this suite. A throw becomes an unknown answer saying so, and
    # every known value is held to schema/decision-result.v1 here, whatever the check after it asks.
    param([string]$Store, [string]$Operation, $Request)
    $answer = $null
    try { $answer = Invoke-HordeDecision -Operation $Operation -Request $Request -Root $Store }
    catch { return (New-HordeUnknown -Reason ("THREW: " + $_.Exception.Message)) }
    if (-not (Test-HordeAnswer $answer)) { return (New-HordeUnknown -Reason "NOT AN ANSWER: the operation returned something that is not a tristate answer") }
    if ($answer.state -ceq "known") {
        $off = @(Test-HordeSchema -Value $answer.value -Schema $defs.resultSchema)
        if ($off.Count -gt 0) { return (New-HordeUnknown -Reason ("OFF SCHEMA: " + ($off -join "; "))) }
    }
    return $answer
}
function Add-Q { param([string]$Store, [string]$Title = "Should the closing sound play when the assistant closes?") return (Invoke-Op $Store "add" @{ id = (New-Id); actor = "warchief"; question = @{ title = $Title; kind = "yes-no"; whatItIs = "The app has no closing sound today."; group = "voice"; askedBy = "orc-b" } }) }
function Say {
    # The founder's chat words, recorded by the warchief, unless the parameters say otherwise.
    param([string]$Store, [int]$Number, [string]$Text, [string]$Speaker = "founder", [string]$Route = "chat-recorded", [string]$Actor = "warchief", [string]$Id = "", [int]$Wording = 0)
    if ($Id -eq "") { $Id = New-Id }
    $request = @{ id = $Id; actor = $Actor; number = $Number; speaker = $Speaker; route = $Route; text = $Text }
    if ($Wording -gt 0) { $request["wordingVersion"] = $Wording }
    return (Invoke-Op $Store "say" $request)
}
function Reply { param([string]$Store, [int]$Number, [string]$Text) return (Say -Store $Store -Number $Number -Text $Text -Speaker "warchief" -Route "command") }
function Inbox {
    param([string]$Store, [switch]$Mark, [string]$Id = "", [long]$UpTo = 0, [string]$Actor = "warchief")
    $request = @{ actor = $Actor }
    if ($Mark) { $request["mark"] = $true; if ($Id -eq "") { $Id = New-Id } }
    if ($Id -ne "") { $request["id"] = $Id }
    if ($UpTo -gt 0) { $request["upTo"] = $UpTo }
    return (Invoke-Op $Store "inbox" $request)
}
function Get-Outcome { param($Answer) if ($Answer.state -cne "known") { return ($Answer.state + ": " + $Answer.reason) }; return "$($Answer.value.outcome)" }
function Test-Refused { param($Answer, [string]$Text) return ($Answer.state -ceq "known" -and $Answer.value.outcome -ceq "refused" -and @($Answer.value.findings | Where-Object { "$_".Contains($Text) }).Count -gt 0) }
function Get-Files { param([string]$Store) if (-not (Test-Path -LiteralPath $Store)) { return "" }; return (@(Get-ChildItem -LiteralPath $Store -File | Sort-Object Name | ForEach-Object { $_.Name }) -join ",") }
function Get-Count { param([string]$Store) if (-not (Test-Path -LiteralPath $Store)) { return 0 }; return @(Get-ChildItem -LiteralPath $Store -File).Count }
function Read-Record { param([string]$Store, [long]$Sequence) return ([System.IO.File]::ReadAllText((Join-Path $Store ($Sequence.ToString("D10") + ".json")), $utf8) | ConvertFrom-Json) }
function Show { param([string]$Store, [int]$Number) return (Invoke-Op $Store "show" @{ number = $Number }) }
function Get-Thread {
    # A question's thread as show hands it back; a thread of -1 messages when show did not answer.
    param([string]$Store, [int]$Number)
    $a = Show $Store $Number
    if ($a.state -cne "known" -or $a.value.outcome -cne "done") { return [pscustomobject]@{ count = -1; turn = (Get-Outcome $a); turnShown = ""; unread = @(); messages = @() } }
    return $a.value.question.thread
}
# A thread or an answer that lacks what it should hold must FAIL the check that reads it, by name -
# not raise an error under strict mode, which tools/Mutate.ps1 does not count as a catch.
function Get-Texts { param($Thread) if ($null -eq $Thread.PSObject.Properties["messages"]) { return "(the thread holds no messages)" }; return (@($Thread.messages | ForEach-Object { $_.text }) -join " | ") }
function Get-Said {
    # The message a say answered with; a stand-in that equals nothing when the answer holds none.
    param($Answer)
    if ($Answer.state -ceq "known" -and $null -ne $Answer.value.PSObject.Properties["message"]) { return $Answer.value.message }
    return [pscustomobject]@{ sequence = -1; text = "(the answer holds no message)"; speaker = ""; speakerShown = ""; route = ""; routeShown = ""; recordedBy = ""; wordingVersion = -1; saidToEarlierWording = "none"; arrivedAfterClosing = "none" }
}
function Get-Unread { param($Thread) $u = @($Thread.unread | Where-Object { $_.reader -ceq "warchief" }) | Select-Object -First 1; if ($null -eq $u) { return -1 }; return [int]$u.count }
function Get-InboxLine { param($Answer) if ($Answer.state -cne "known" -or $Answer.value.outcome -ceq "refused") { return (Get-Outcome $Answer) }; if ($null -eq $Answer.value.PSObject.Properties["messages"]) { return "(the answer holds no messages)" }; return ((@($Answer.value.messages | ForEach-Object { "" + $_.message.sequence + "@" + $_.number }) -join ",") + " upTo=" + $Answer.value.upTo + " marked=" + $Answer.value.marked) }
function Test-Echo { param($Answer, [string]$Text) return ((ConvertTo-Json -InputObject (ConvertTo-HordeAnswerRecord -Answer $Answer) -Compress -Depth 12).Contains($Text)) }

try {

Write-Host ""
Write-Host "--- the operations of the conversation ---" -ForegroundColor Cyan
$ops = @(Get-HordeDecisionOperations)
Check (@($ops | Where-Object { $_.name -ceq "say" -and $_.writes }).Count -eq 1 -and @($ops | Where-Object { $_.name -ceq "inbox" }).Count -eq 1) "say and inbox are operations, as a caller may list them"
$reqDefs = @($defs.requestSchema.definitions.PSObject.Properties | ForEach-Object { $_.Name })
Check (($reqDefs -ccontains "say") -and ($reqDefs -ccontains "inbox")) "each has its request definition in schema/decision-request.v1"

Write-Host ""
Write-Host "--- say: the words are kept, whole and exactly, in one record ---" -ForegroundColor Cyan
$s = New-TestStore
$null = Add-Q $s
$a = Say $s 1 "Yes, play it."
Check ((Get-Outcome $a) -ceq "done" -and $a.value.number -eq 1 -and $a.value.sequence -eq 2 -and $a.value.attempts -eq 1) ("the founder's words are recorded under question 1, as record 2 (" + (Get-Outcome $a) + ")")
Check ((Get-Outcome $a) -ceq "done" -and (Get-Said $a).text -ceq "Yes, play it." -and (Get-Said $a).speaker -ceq "founder" -and (Get-Said $a).routeShown -ceq "recorded by the warchief from chat" -and (Get-Said $a).recordedBy -ceq "warchief" -and (Get-Said $a).sequence -eq 2) "the answer hands the message back: his words, his name, and that the warchief recorded them from chat"
Check ((Get-Files $s) -ceq "0000000001.json,0000000002.json") "one record was written for it"
$rec = Read-Record $s 2
Check ($rec.kind -ceq "message-said" -and $rec.actor -ceq "warchief" -and $rec.data.speaker -ceq "founder" -and $rec.data.route -ceq "chat-recorded" -and $rec.data.text -ceq "Yes, play it." -and $rec.data.number -eq 1 -and $rec.data.wordingVersion -eq 1) "the record holds who spoke, by what route, the words, the question and the wording he was looking at"
Check ((@($rec.data.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object) -join ",") -ceq "number,route,speaker,text,wordingVersion") "and nothing else: no turn, no flag, no 'read' is stored in it"
$a = Reply $s 1 "It plays from the next build."
Check ((Get-Outcome $a) -ceq "done" -and (Get-Said $a).speaker -ceq "warchief" -and (Get-Said $a).routeShown -ceq "by command" -and $a.value.sequence -eq 3) "the warchief's reply is recorded as its own words, by command"
$t = Get-Thread $s 1
Check ($t.count -eq 2 -and (Get-Texts $t) -ceq "Yes, play it. | It plays from the next build.") ("show hands back the thread: both messages, in order (" + (Get-Texts $t) + ")")
$listed = Invoke-Op $s "list" @{}
Check ((Get-Outcome $listed) -ceq "done" -and $listed.value.questions[0].thread.count -eq 2 -and $listed.value.questions[0].thread.turn -ceq "founder" -and $null -eq $listed.value.questions[0].thread.PSObject.Properties["messages"]) "list hands back the counts and whose turn it is, and not the messages"
# The founder typing in his own window is another caller sending the same request with other labels.
$a = Say $s 1 "Typed by me." -Route "window" -Actor "founder"
Check ((Get-Outcome $a) -ceq "done" -and (Get-Said $a).routeShown -ceq "typed in the window" -and (Get-Said $a).recordedBy -ceq "founder" -and (Read-Record $s 4).actor -ceq "founder") "words typed in the window are recorded by the founder's own caller, under their own route"

Write-Host ""
Write-Host "--- one id, one message; two messages, two ---" -ForegroundColor Cyan
$s = New-TestStore
$null = Add-Q $s
$id = New-Id
$first = Say $s 1 "Send it once." -Id $id
$again = Say $s 1 "Send it once." -Id $id
Check ((Get-Outcome $first) -ceq "done" -and (Get-Outcome $again) -ceq "replayed" -and $again.value.sequence -eq $first.value.sequence -and $again.value.number -eq 1) ("the same request with the same id is answered from the first record (" + (Get-Outcome $again) + ")")
Check ((Get-Outcome $again) -ceq "replayed" -and (Get-Said $again).text -ceq "Send it once." -and (Get-Said $again).sequence -eq 2) "and the answer holds the same message again, for a caller that lost the first answer"
Check ((Get-Count $s) -eq 2 -and (Get-Thread $s 1).count -eq 1) "a double submit is one message: one record, one entry in the thread"
$other = Say $s 1 "Other words under the same id." -Id $id
Check ((Test-Refused $other "was already used for a different request") -and (Get-Count $s) -eq 2 -and -not (Test-Echo $other "Other words")) "the same id with other words is refused, nothing is written, and the words are not repeated"
$null = Say $s 1 "Send it once."
Check ((Get-Count $s) -eq 3 -and (Get-Texts (Get-Thread $s 1)) -ceq "Send it once. | Send it once.") "the same words under a NEW id are a second message: saying a thing twice is saying it twice"
# The wording the speaker was looking at is not part of what makes a request the same request, when
# the request did not give one: the same request sent again after a rewording is still a repost.
$idDefault = New-Id
$null = Say $s 1 "Said before the rewording." -Id $idDefault
$null = Invoke-Op $s "update" @{ id = (New-Id); actor = "warchief"; number = 1; changes = @{ title = "Should the closing sound play at the end of every session?" } }
$again = Say $s 1 "Said before the rewording." -Id $idDefault
Check ((Get-Outcome $again) -ceq "replayed" -and (Get-Said $again).wordingVersion -eq 1 -and (Get-Count $s) -eq 5) ("a repost after the question was reworded is still a repost, answered with the wording it was recorded under (" + (Get-Outcome $again) + ")")

Write-Host ""
Write-Host "--- words under a closed question are kept, flagged, and reopen nothing ---" -ForegroundColor Cyan
$s = New-TestStore
$null = Add-Q $s
$null = Invoke-Op $s "close" @{ id = (New-Id); actor = "warchief"; number = 1; outcome = "Done: it plays." }
$a = Say $s 1 "Wait - not on the first launch."
Check ((Get-Outcome $a) -ceq "done") ("words said under a closed question are recorded, not refused (" + (Get-Outcome $a) + ")")
Check ((Get-Outcome $a) -ceq "done" -and (Get-Said $a).arrivedAfterClosing -eq $true -and $a.value.question.state -ceq "closed" -and $a.value.question.outcome -ceq "Done: it plays.") "they are flagged as having arrived after closing, and the question is still closed with its outcome"
$t = Get-Thread $s 1
Check ($t.count -eq 1 -and $t.messages[0].text -ceq "Wait - not on the first launch." -and $t.messages[0].arrivedAfterClosing -eq $true -and $t.turn -ceq "nobody") "they are in the thread, flagged; it is nobody's turn under a closed question"
$counts = (Invoke-Op $s "list" @{ state = "all" }).value.counts
Check ($counts.open -eq 0 -and $counts.closed -eq 1 -and (Get-Unread $t) -eq 1) "the list still counts the question as closed, and the warchief still has the words to read"
Check (@((Show $s 1).value.question.history).Count -eq 2) "the question's history is still two records: asked, closed. Speaking is not part of it"

Write-Host ""
Write-Host "--- words said to an earlier wording are kept and flagged ---" -ForegroundColor Cyan
$s = New-TestStore
$null = Add-Q $s
$null = Invoke-Op $s "update" @{ id = (New-Id); actor = "warchief"; number = 1; changes = @{ title = "Should the closing sound play at the end of every session?" } }
$a = Say $s 1 "Yes." -Wording 1
Check ((Get-Outcome $a) -ceq "done" -and (Get-Said $a).wordingVersion -eq 1 -and (Get-Said $a).saidToEarlierWording -eq $true -and $a.value.question.wordingVersion -eq 2) ("words said to wording 1 of a question now at wording 2 are recorded, and flagged as said to an earlier wording (" + (Get-Outcome $a) + ")")
$a = Say $s 1 "Yes, to these words." -Wording 2
Check ((Get-Outcome $a) -ceq "done" -and (Get-Said $a).saidToEarlierWording -eq $false) "CONTROL: words said to the wording the question has are not flagged"
$a = Say $s 1 "Yes, with no wording named."
Check ((Get-Outcome $a) -ceq "done" -and (Get-Said $a).wordingVersion -eq 2 -and (Read-Record $s $a.value.sequence).data.wordingVersion -eq 2) "with no wording named, the record holds the wording the question had when the words were recorded"
$before = Get-Count $s
$a = Say $s 1 "Yes, to a wording that does not exist." -Wording 3
Check ((Test-Refused $a "said to wording 3 of question 1, which has only reached wording 2") -and (Get-Count $s) -eq $before -and -not (Test-Echo $a "does not exist")) "words said to a wording the question has not reached are refused before anything is written, without being repeated"
$a = Invoke-Op $s "say" @{ id = (New-Id); actor = "warchief"; number = 1; speaker = "founder"; route = "chat-recorded"; text = "x"; wordingVersion = 1e30 }
Check ((Test-Refused $a "'wordingVersion' is not a wording a question can have") -and (Get-Count $s) -eq $before) ("a wording number no question can have is refused, not thrown on (" + (Get-Outcome $a) + ")")

Write-Host ""
Write-Host "--- Hebrew with its direction marks, and 100,000 characters, come back exactly ---" -ForegroundColor Cyan
$s = New-TestStore
$null = Add-Q $s
# Written as escapes so this file stays ASCII (CONTRIBUTING 13). A right-to-left embedding, the word
# "ken" (yes) and a right-to-left mark, a comma, an isolate around another word, then left-to-right
# text in brackets, a joiner, and a second line.
$hebrew = "" + [char]0x202B + [char]0x05DB + [char]0x05DF + [char]0x200F + ", " + [char]0x2067 + [char]0x05EA + [char]0x05DE + [char]0x05E9 + [char]0x05D9 + [char]0x05DA + [char]0x2069 + [char]0x202C + " " + [char]0x200E + "(yes)" + [char]0x200D + "`r`n  " + [char]0x05EA + [char]0x05D5 + [char]0x05D3 + [char]0x05D4 + "  "
$a = Say $s 1 $hebrew
Check ((Get-Outcome $a) -ceq "done" -and [string]::Equals((Get-Said $a).text, $hebrew, [System.StringComparison]::Ordinal)) ("Hebrew with direction marks, an embedding and an isolate is recorded as it is (" + (Get-Outcome $a) + ")")
Check ([string]::Equals((Get-Thread $s 1).messages[0].text, $hebrew, [System.StringComparison]::Ordinal)) "and reads back from the store character for character: marks, line break and the spaces at both ends"
Check ([string]::Equals((Read-Record $s 2).data.text, $hebrew, [System.StringComparison]::Ordinal)) "the record on disk holds exactly those characters"
$long = ("word " * 19999) + "end!!"
$a = Say $s 1 $long
Check ($long.Length -eq 100000 -and (Get-Outcome $a) -ceq "done" -and (Get-Said $a).text.Length -eq 100000) ("a message of 100,000 characters is recorded whole (" + (Get-Outcome $a) + ")")
Check ([string]::Equals((Get-Thread $s 1).messages[1].text, $long, [System.StringComparison]::Ordinal)) "and all 100,000 read back, in order, nothing cut"
$exact = "  leading spaces`ttab, CRLF`r`nthen LF`nthen two blank lines`r`n`r`n"
$a = Say $s 1 $exact
Check ((Get-Outcome $a) -ceq "done" -and [string]::Equals((Get-Thread $s 1).messages[2].text, $exact, [System.StringComparison]::Ordinal)) "spaces at both ends, a tab and line breaks of both kinds are kept as they were: nothing is trimmed or re-wrapped"
$tooLong = Say $s 1 ("x" * 500001)
Check ((Test-Refused $tooLong "'text' is 500001 characters long") -and (Get-Count $s) -eq 4) "a message longer than the most a text may be is refused whole, with the count: never cut, and never stored in part"
$blank = Say $s 1 "   "
Check ((Test-Refused $blank "'text' is blank") -and (Get-Count $s) -eq 4) "saying nothing is refused"
$control = Say $s 1 ("clear the screen " + [char]0x1B + "[2J now")
Check ((Test-Refused $control "'text' holds the character U+001B") -and (Get-Count $s) -eq 4 -and -not (Test-Echo $control "clear the screen")) "a control character is refused by its code point, and the words around it are not repeated"

Write-Host ""
Write-Host "--- a secret in a message is refused, and not repeated ---" -ForegroundColor Cyan
# Assembled at run time, so no credential-shaped text sits in this file.
$token = "gh" + "p_" + ("Ab3d" * 9)
$sentence = "use this one: " + $token + " and tell nobody"
$s = New-TestStore
$null = Add-Q $s
$a = Say $s 1 $sentence
Check ((Get-Outcome $a) -ceq "refused" -and (Get-Count $s) -eq 1) ("a message holding an access token is refused, and nothing is written (" + (Get-Outcome $a) + ")")
Check (Test-Refused $a "'text' holds what looks like an access token") "the refusal names the field and the kind of secret"
Check (-not (Test-Echo $a $token) -and -not (Test-Echo $a "tell nobody")) "and repeats neither the secret nor the words around it, anywhere in the answer"
$passwordLine = "the pass" + "word is " + "hunter" + "2x9"
$a = Say $s 1 $passwordLine
Check ((Get-Outcome $a) -ceq "refused" -and -not (Test-Echo $a ("hunter" + "2x9")) -and (Get-Count $s) -eq 1) "a password written in a sentence is refused the same way"
$a = Say $s 1 "The login is in the file I told you about; I typed it into the session myself."
Check ((Get-Outcome $a) -ceq "done") "CONTROL: words ABOUT a login, holding none, are recorded"

Write-Host ""
Write-Host "--- who may speak, by what route, and who may record whose words ---" -ForegroundColor Cyan
$s = New-TestStore
$null = Add-Q $s
$before = Get-Count $s
Check (Test-Refused (Say $s 1 "hello" -Actor "goblin") "'goblin' is not a role that may speak under a question") "a role outside the speakers is refused, with the list"
Check (Test-Refused (Say $s 1 "hello" -Speaker "orc") "'speaker' is 'orc', which is not someone who speaks") "a speaker outside the list is refused"
Check (Test-Refused (Say $s 1 "hello" -Route "telepathy") "'route' is 'telepathy', which is not a way words arrive") "a route outside the list is refused"
Check (Test-Refused (Say $s 1 "hello" -Speaker "warchief" -Route "chat-recorded") "are never the warchief's") "the warchief cannot record its own words as the founder's chat"
Check (Test-Refused (Say $s 1 "hello" -Route "window" -Actor "warchief") "typed in the window are recorded only by: founder") "nor record words as typed in the founder's window"
Check (Test-Refused (Say $s 1 "hello" -Route "chat-recorded" -Actor "founder") "recorded only by: warchief") "and the founder's own caller does not record chat"
Check ((Get-Count $s) -eq $before) "none of them wrote anything"
# THE LIST'S KEEPERS DID NOT WIDEN: someone who may speak under a question may still not change it.
Check (Test-Refused (Invoke-Op $s "close" @{ id = (New-Id); actor = "founder"; number = 1; outcome = "Closed by the wrong hand." }) "'founder' is not a role that may change the list") "a speaker who is not a keeper of the list may not close a question"
Check (Test-Refused (Invoke-Op $s "add" @{ id = (New-Id); actor = "founder"; question = @{ title = "Should a speaker be able to add a question here?"; kind = "yes-no"; whatItIs = "x"; group = "g"; askedBy = "a" } }) "'founder' is not a role that may change the list") "nor add one"
Check ((Get-Count $s) -eq $before -and (Show $s 1).value.question.state -ceq "open") "and the question is as it was"
$none = Say $s 99 "to a question that is not there"
Check ($none.state -ceq "absent" -and $none.reason -like "*there is no question 99*" -and (Get-Count $s) -eq $before) ("words under a number that was never given are answered absent, and nothing is written (" + $none.state + ")")

Write-Host ""
Write-Host "--- inbox: what the warchief has not read, across questions, oldest first ---" -ForegroundColor Cyan
$s = New-TestStore
$empty = Inbox $s
Check ((Get-InboxLine $empty) -ceq " upTo=0 marked=0" -and -not (Test-Path -LiteralPath $s)) ("with no store yet the inbox is empty, and reading it made no folder (" + (Get-InboxLine $empty) + ")")
$null = Add-Q $s "Should the closing sound play when the assistant closes?"
$null = Add-Q $s "Which languages besides English should the test talker speak?"
$null = Say $s 1 "one, under the first"          # record 3
$null = Say $s 2 "two, under the second"         # record 4
$null = Reply $s 1 "the warchief's own reply"    # record 5
$null = Say $s 1 "three, under the first again"  # record 6
$peek = Inbox $s
Check ((Get-InboxLine $peek) -ceq "3@1,4@2,6@1 upTo=6 marked=0") ("the inbox holds the founder's three messages, from both questions, oldest first, and not the warchief's own reply (" + (Get-InboxLine $peek) + ")")
Check ((Get-Outcome $peek) -ceq "done" -and $peek.value.messages[1].title -ceq "Which languages besides English should the test talker speak?" -and $peek.value.messages[1].message.text -ceq "two, under the second" -and $peek.value.messages[1].state -ceq "open") "each with its question's number, its plain-words title and the words"
Check ((Get-Count $s) -eq 6 -and (Get-InboxLine (Inbox $s)) -ceq "3@1,4@2,6@1 upTo=6 marked=0") "READING MARKS NOTHING AND WRITES NOTHING: the same inbox again is the same three, and the store has no new record"
Check ((Get-Unread (Get-Thread $s 1)) -eq 2 -and (Get-Unread (Get-Thread $s 2)) -eq 1) "CONTROL: all three are still unread by the warchief"
$markId = New-Id
$marked = Inbox $s -Mark -Id $markId
Check ((Get-InboxLine $marked) -ceq "3@1,4@2,6@1 upTo=6 marked=3" -and $marked.value.sequence -eq 7) ("asked to mark, the inbox hands back the same three and says it marked three, as record 7 (" + (Get-InboxLine $marked) + ")")
$rec = Read-Record $s 7
Check ($rec.kind -ceq "messages-read" -and $rec.actor -ceq "warchief" -and $rec.data.reader -ceq "warchief" -and $rec.data.upTo -eq 6 -and (@($rec.data.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object) -join ",") -ceq "reader,upTo") "marking is one record of its own: the warchief has read up to record 6, the LAST MESSAGE HANDED BACK"
Check ((Get-Unread (Get-Thread $s 1)) -eq 0 -and (Get-Unread (Get-Thread $s 2)) -eq 0 -and @((Get-Thread $s 1).messages | Where-Object { @($_.unreadBy).Count -gt 0 }).Count -eq 0) "and now nothing is unread by the warchief, in either thread"
$second = Inbox $s -Mark
Check ((Get-InboxLine $second) -ceq " upTo=0 marked=0" -and (Get-Count $s) -eq 7) ("THE SECOND INBOX IS EMPTY, and marking nothing writes nothing (" + (Get-InboxLine $second) + "; " + (Get-Count $s) + " records)")
$replayed = Inbox $s -Mark -Id $markId
Check ((Get-Outcome $replayed) -ceq "replayed" -and (Get-InboxLine $replayed) -ceq "3@1,4@2,6@1 upTo=6 marked=3" -and $replayed.value.sequence -eq 7 -and (Get-Count $s) -eq 7) ("the FIRST marking sent again, same id, is answered with the same three messages and writes nothing: a caller that lost the answer has not lost the words (" + (Get-InboxLine $replayed) + ")")
$null = Say $s 2 "four, said after the marking"   # record 8
Check ((Get-InboxLine (Inbox $s)) -ceq "8@2 upTo=8 marked=0" -and (Get-Unread (Get-Thread $s 2)) -eq 1) "a message said after the marking is unread, and is the whole of the next inbox"
$replayed = Inbox $s -Mark -Id $markId
Check ((Get-InboxLine $replayed) -ceq "3@1,4@2,6@1 upTo=6 marked=3" -and (Get-InboxLine (Inbox $s)) -ceq "8@2 upTo=8 marked=0") "and the old marking sent yet again still answers with its own three, and does not mark the new one"
# The title an inbox shows is the question as it reads now.
$null = Invoke-Op $s "update" @{ id = (New-Id); actor = "warchief"; number = 2; changes = @{ title = "Which languages should the test talker speak first?" } }
$now = Inbox $s
Check ($now.value.messages[0].title -ceq "Which languages should the test talker speak first?" -and $now.value.messages[0].message.saidToEarlierWording -eq $false -and $now.value.messages[0].message.wordingVersion -eq 1) "the inbox names a question by its words as they are now; the message, said before the rewording, is NOT flagged: it was said to the wording of its moment"

Write-Host ""
Write-Host "--- inbox: only what is handed back is marked ---" -ForegroundColor Cyan
$s = New-TestStore
$null = Add-Q $s
$null = Say $s 1 "first"    # record 2
$null = Say $s 1 "second"   # record 3
$null = Say $s 1 "third"    # record 4
$bounded = Inbox $s -Mark -UpTo 3
Check ((Get-InboxLine $bounded) -ceq "2@1,3@1 upTo=3 marked=2" -and (Read-Record $s 5).data.upTo -eq 3) ("bounded at record 3, the inbox hands back and marks the two up to it (" + (Get-InboxLine $bounded) + ")")
Check ((Get-InboxLine (Inbox $s)) -ceq "4@1 upTo=4 marked=0" -and (Get-Unread (Get-Thread $s 1)) -eq 1) "and the third, beyond the bound, is NOT marked: it is still unread"
$below = Inbox $s -Mark -UpTo 3
Check ((Get-InboxLine $below) -ceq " upTo=0 marked=0" -and (Get-Count $s) -eq 5) "a bound with nothing unread below it marks nothing and writes nothing"
$before = Get-Count $s
Check ((Test-Refused (Invoke-Op $s "inbox" @{ actor = "warchief"; mark = $true }) "to mark messages as read the request needs an 'id'") -and (Get-Count $s) -eq $before) "marking without an id is refused: a marking that could not be told from its own repost"
Check ((Test-Refused (Invoke-Op $s "inbox" @{ actor = "warchief"; id = (New-Id) }) "an 'id' is given and nothing is to be marked") -and (Get-Count $s) -eq $before) "an id on an inbox that only reads is refused, not ignored"
Check ((Test-Refused (Inbox $s -Actor "founder") "'founder' has no inbox; the roles that have one are: warchief") -and (Get-Count $s) -eq $before) "a speaker with no inbox is told so"
Check ((Test-Refused (Inbox $s -Actor "goblin") "'goblin' is not a role that may speak under a question, or mark what was said there as read") -and (Get-Count $s) -eq $before) "and a role that does not speak has none either"
Check ((Test-Refused (Invoke-Op $s "inbox" @{ actor = "warchief"; mark = $true; id = (New-Id); upTo = 1e30 }) "'upTo' is not a record's sequence number") -and (Get-Count $s) -eq $before) "a bound no record can have is refused, not thrown on"
Check ((Get-InboxLine (Inbox $s)) -ceq "4@1 upTo=4 marked=0") "CONTROL: none of the refusals marked anything"

Write-Host ""
Write-Host "--- a writer that loses its place to another checks again against what the winner left ---" -ForegroundColor Cyan
# The collision is made exactly, as in test/test-decisions-operations.ps1: the store's own create is
# wrapped so that, just before this writer's record is created, another writer's record lands in the
# very sequence number it wanted. Two real processes doing it are test/test-decisions-threads-race.ps1.
$realAdd = ${function:Add-HordeDecisionRecord}
$script:planted = 0
$script:plantText = ""
function Add-HordeDecisionRecord {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][long]$Sequence, [Parameter(Mandatory = $true)][string]$Text)
    if ($script:planted -eq 0 -and $script:plantText -ne "") { $script:planted = 1; $null = & $realAdd -Root $Root -Sequence $Sequence -Text $script:plantText }
    return (& $realAdd -Root $Root -Sequence $Sequence -Text $Text)
}
function New-Planted { param([long]$Sequence, [string]$Kind, [string]$Data, [string]$Letter) return ('{"schemaVersion":1,"sequence":' + $Sequence + ',"id":"' + ($Letter * 32) + '","kind":"' + $Kind + '","at":"2026-10-06T12:00:00.0000000Z","actor":"warchief","requestHash":"' + ("0" * 64) + '","data":' + $Data + '}') }
try {
    # A CLOSE WINS THE PLACE A SAY WANTED: the say is not lost and not refused. It is written next, flagged.
    $s = New-TestStore
    $null = Add-Q $s
    $script:planted = 0; $script:plantText = New-Planted 2 "question-closed" '{"number":1,"outcome":"Closed by the other writer."}' "c"
    $a = Say $s 1 "said as it was being closed"
    Check ($script:planted -eq 1) "CONTROL: the close was written first, into the sequence number the say wanted"
    Check ((Get-Outcome $a) -ceq "done" -and $a.value.sequence -eq 3 -and $a.value.attempts -eq 2) ("the say is written to the next sequence number, on its second try (" + (Get-Outcome $a) + ")")
    Check ((Get-Outcome $a) -ceq "done" -and (Get-Said $a).arrivedAfterClosing -eq $true -and $a.value.question.state -ceq "closed") "and it is flagged as having arrived after closing: the words are kept, the close stands"
    Check ((Get-Texts (Get-Thread $s 1)) -ceq "said as it was being closed") "the thread has the words"
    # A NEW MESSAGE WINS THE PLACE A MARKING WANTED. With no bound, the marking is worked out again and
    # hands back the new message too: what it marks is still exactly what it hands back.
    $s = New-TestStore
    $null = Add-Q $s
    $null = Say $s 1 "seen before the marking began"   # record 2
    $script:planted = 0; $script:plantText = New-Planted 3 "message-said" '{"number":1,"speaker":"founder","route":"chat-recorded","text":"arrived as the marking was being written","wordingVersion":1}' "d"
    $a = Inbox $s -Mark
    Check ($script:planted -eq 1 -and (Get-InboxLine $a) -ceq "2@1,3@1 upTo=3 marked=2" -and $a.value.attempts -eq 2 -and $a.value.sequence -eq 4) ("a marking that lost its place to a new message is worked out again: it hands back both and marks both (" + (Get-InboxLine $a) + ")")
    Check ((Read-Record $s 4).data.upTo -eq 3 -and (Get-InboxLine (Inbox $s)) -ceq " upTo=0 marked=0") "the mark is up to the last message it handed back, and nothing is left unread that it did not hand back"
    # WITH A BOUND - the caller showed a person the messages up to record 2 and now marks them - the new
    # message is beyond it: it is not handed back by this call, and it is NOT marked.
    $s = New-TestStore
    $null = Add-Q $s
    $null = Say $s 1 "shown to the person"   # record 2
    $script:planted = 0; $script:plantText = New-Planted 3 "message-said" '{"number":1,"speaker":"founder","route":"chat-recorded","text":"arrived after the showing","wordingVersion":1}' "e"
    $a = Inbox $s -Mark -UpTo 2
    Check ($script:planted -eq 1 -and (Get-InboxLine $a) -ceq "2@1 upTo=2 marked=1" -and $a.value.attempts -eq 2) ("a bounded marking that lost its place to a new message marks only what was shown (" + (Get-InboxLine $a) + ")")
    Check ((Get-InboxLine (Inbox $s)) -ceq "3@1 upTo=3 marked=0" -and (Read-Record $s 4).data.upTo -eq 2) "THE NEW MESSAGE IS NEVER MARKED READ UNSEEN: it is the next inbox"
} finally {
    Remove-Item -LiteralPath function:Add-HordeDecisionRecord
    . (Join-Path $root "decisions\Store.ps1")
}
$s = New-TestStore
$null = Add-Q $s
Check ((Get-Outcome (Say $s 1 "after")) -ceq "done" -and (Get-Count $s) -eq 2) "CONTROL: the real create is back in place for the rest of the suite"

Write-Host ""
Write-Host "--- whose turn it is, through a whole exchange ---" -ForegroundColor Cyan
$s = New-TestStore
function Get-Turn { param([string]$Store) $l = Invoke-Op $Store "list" @{ state = "all" }; if ((Get-Outcome $l) -cne "done") { return (Get-Outcome $l) }; return ("" + $l.value.questions[0].thread.turn + "/" + $l.value.questions[0].thread.count + "/" + (Get-Unread $l.value.questions[0].thread)) }
$turns = New-Object System.Collections.ArrayList
$null = Add-Q $s;                                                    [void]$turns.Add((Get-Turn $s))   # asked
$null = Say $s 1 "which one do you mean?";                            [void]$turns.Add((Get-Turn $s))   # he speaks
$null = Inbox $s -Mark;                                              [void]$turns.Add((Get-Turn $s))   # it reads: not a turn
$null = Reply $s 1 "the short one";                                  [void]$turns.Add((Get-Turn $s))   # it replies
$null = Say $s 1 "then yes";                                         [void]$turns.Add((Get-Turn $s))   # he speaks
$null = Invoke-Op $s "close" @{ id = (New-Id); actor = "warchief"; number = 1; outcome = "Done." };       [void]$turns.Add((Get-Turn $s))   # it closes instead of replying
$null = Say $s 1 "thank you";                                        [void]$turns.Add((Get-Turn $s))   # he speaks under a closed question
$null = Invoke-Op $s "reopen" @{ id = (New-Id); actor = "warchief"; number = 1; reason = "it came back" }; [void]$turns.Add((Get-Turn $s))   # asked again
Check (($turns -join " ") -ceq "founder/0/0 warchief/1/1 warchief/1/0 founder/2/0 warchief/3/1 nobody/3/1 nobody/4/2 founder/4/2") ("turn, messages and unread after each step of an exchange: " + ($turns -join " "))
Check ((Show $s 1).value.question.thread.turnShown -ceq "the founder") "and the turn is told to a person in words"

} finally {
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-decisions-threads-test-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the suite's temp folder is removed"
Check ((Get-RealStoreListing) -ceq $realBefore) "the real store under the user profile is exactly as it was before the suite"

Complete-HordeSuite -Success "what is said under a question is kept whole and once, never dropped, and handed to its reader with nothing marked read unseen"
