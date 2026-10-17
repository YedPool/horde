# IS WHAT SOMEONE SAYS UNDER A QUESTION KEPT, WHOLE AND ONCE, AND HANDED TO ITS READER WITHOUT ONE WORD LOST?
#
# The conversation under a question, through decisions/Operations.ps1's one entry point, in this
# process, against stores this suite makes: the operations say and inbox, and the thread that list
# and show hand back. It attacks what the person who speaks, and the session that reads him, rely on:
#   - WORDS ARE KEPT VERBATIM, ONCE: Hebrew with its direction marks, 100,000 characters, spaces and
#     line breaks exactly; a double submit of one id is one message, and two messages are two;
#   - WORDS ARE NEVER DROPPED: said under a question closed a moment earlier, or to a wording that has
#     moved on, they are stored and flagged, and change nothing of the question;
#   - NOTHING IS MARKED READ UNSEEN: reading and marking are two operations; a marking names the record
#     it marks up to and marks nothing beyond it; it is idempotent; a second inbox is empty; and
#     reading marks nothing and writes nothing, however often;
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
function Reply {
    # The warchief's words, by command. -Note: they tell the founder something and ask him nothing.
    param([string]$Store, [int]$Number, [string]$Text, [switch]$Note)
    $request = @{ id = (New-Id); actor = "warchief"; number = $Number; speaker = "warchief"; route = "command"; text = $Text }
    if ($Note) { $request["asks"] = $false }
    return (Invoke-Op $Store "say" $request)
}
function Add-Stored {
    # A record put into a store of this suite AS A FILE, the way an earlier version of Horde left it
    # there: for what the operations no longer write and must still read. Returns its sequence number.
    param([string]$Store, [string]$Kind, $Data, [string]$Actor = "warchief")
    $seq = @(Get-ChildItem -LiteralPath $Store -File -Filter "*.json").Count + 1
    $envelope = [ordered]@{ schemaVersion = 1; sequence = $seq; id = (New-Id); kind = $Kind; at = "2026-10-06T12:00:00.0000000Z"; actor = $Actor; requestHash = ("0" * 64); data = $Data }
    [System.IO.File]::WriteAllText((Join-Path $Store ($seq.ToString("D10") + ".json")), (ConvertTo-Json -InputObject $envelope -Compress -Depth 12), $utf8)
    return $seq
}
function Inbox { param([string]$Store, [string]$Actor = "warchief") return (Invoke-Op $Store "inbox" @{ actor = $Actor }) }
function Mark {
    # Mark as read, for the warchief unless -Actor says otherwise, up to record -UpTo.
    param([string]$Store, [long]$UpTo, [string]$Id = "", [string]$Actor = "warchief")
    if ($Id -eq "") { $Id = New-Id }
    return (Invoke-Op $Store "mark-read" @{ id = $Id; actor = $Actor; upTo = $UpTo })
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
    return [pscustomobject]@{ sequence = -1; text = "(the answer holds no message)"; speaker = ""; speakerShown = ""; route = ""; routeShown = ""; recordedBy = ""; wordingStated = "none"; wordingVersion = -1; saidToEarlierWording = "none"; arrivedAfterClosing = "none"; holdsDirectionOrInvisibleCharacters = "none" }
}
function Get-Unread { param($Thread) $u = @($Thread.unread | Where-Object { $_.reader -ceq "warchief" }) | Select-Object -First 1; if ($null -eq $u) { return -1 }; return [int]$u.count }
function Get-InboxLine { param($Answer) if ($Answer.state -cne "known" -or $Answer.value.outcome -ceq "refused") { return (Get-Outcome $Answer) }; if ($null -eq $Answer.value.PSObject.Properties["messages"]) { return "(the answer holds no messages)" }; return ((@($Answer.value.messages | ForEach-Object { "" + $_.message.sequence + "@" + $_.number }) -join ",") + " upTo=" + $Answer.value.upTo) }
function Get-MarkLine { param($Answer) if ($Answer.state -cne "known" -or $Answer.value.outcome -ceq "refused") { return (Get-Outcome $Answer) }; if ($null -eq $Answer.value.PSObject.Properties["marked"]) { return ($Answer.value.outcome + " (the answer does not say what it marked)") }; return ("" + $Answer.value.outcome + " upTo=" + $Answer.value.upTo + " marked=" + $Answer.value.marked) }
function Test-Echo { param($Answer, [string]$Text) return ((ConvertTo-Json -InputObject (ConvertTo-HordeAnswerRecord -Answer $Answer) -Compress -Depth 12).Contains($Text)) }

try {

Write-Host ""
Write-Host "--- the operations of the conversation ---" -ForegroundColor Cyan
$ops = @(Get-HordeDecisionOperations)
Check (@($ops | Where-Object { $_.name -ceq "say" -and $_.writes }).Count -eq 1 -and @($ops | Where-Object { $_.name -ceq "inbox" -and -not $_.writes }).Count -eq 1 -and @($ops | Where-Object { $_.name -ceq "mark-read" -and $_.writes }).Count -eq 1) "say, inbox and mark-read are operations, as a caller may list them: say and mark-read write, and inbox only reads"
$reqDefs = @($defs.requestSchema.definitions.PSObject.Properties | ForEach-Object { $_.Name })
Check (($reqDefs -ccontains "say") -and ($reqDefs -ccontains "inbox") -and ($reqDefs -ccontains "mark-read")) "each has its request definition in schema/decision-request.v1"

Write-Host ""
Write-Host "--- say: the words are kept, whole and exactly, in one record ---" -ForegroundColor Cyan
$s = New-TestStore
$null = Add-Q $s
$a = Say $s 1 "Yes, play it."
Check ((Get-Outcome $a) -ceq "done" -and $a.value.number -eq 1 -and $a.value.sequence -eq 2 -and $a.value.attempts -eq 1) ("the founder's words are recorded under question 1, as record 2 (" + (Get-Outcome $a) + ")")
Check ((Get-Outcome $a) -ceq "done" -and (Get-Said $a).text -ceq "Yes, play it." -and (Get-Said $a).speaker -ceq "founder" -and (Get-Said $a).routeShown -ceq "recorded by the warchief from chat" -and (Get-Said $a).recordedBy -ceq "warchief" -and (Get-Said $a).sequence -eq 2) "the answer hands the message back: his words, his name, and that the warchief recorded them from chat"
Check ((Get-Files $s) -ceq "0000000001.json,0000000002.json") "one record was written for it"
$rec = Read-Record $s 2
Check ($rec.kind -ceq "message-said" -and $rec.actor -ceq "warchief" -and $rec.data.speaker -ceq "founder" -and $rec.data.route -ceq "chat-recorded" -and $rec.data.text -ceq "Yes, play it." -and $rec.data.number -eq 1) "the record holds who spoke, by what route, the words and the question"
Check ((@($rec.data.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object) -join ",") -ceq "number,route,speaker,text") "and nothing else: no turn, no flag, no 'read' - and no wording, because none was stated and none is guessed"
# A note: he has answered, so the question is off his list, and only words that ask him nothing are
# taken under it (the section "an answered question is never put back in front of him", below).
$a = Reply $s 1 "It plays from the next build." -Note
Check ((Get-Outcome $a) -ceq "done" -and (Get-Said $a).speaker -ceq "warchief" -and (Get-Said $a).routeShown -ceq "by command" -and $a.value.sequence -eq 3) "the warchief's reply is recorded as its own words, by command"
$t = Get-Thread $s 1
Check ($t.count -eq 2 -and (Get-Texts $t) -ceq "Yes, play it. | It plays from the next build.") ("show hands back the thread: both messages, in order (" + (Get-Texts $t) + ")")
$listed = Invoke-Op $s "list" @{}
Check ((Get-Outcome $listed) -ceq "done" -and $listed.value.questions[0].thread.count -eq 2 -and $listed.value.questions[0].thread.turn -ceq "warchief" -and $null -eq $listed.value.questions[0].thread.PSObject.Properties["messages"]) "list hands back the counts and whose turn it is, and not the messages"
# The founder typing in his own window is another caller sending the same request with other labels.
$a = Say $s 1 "Typed by me." -Route "window" -Actor "founder" -Wording 1
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
Check ((Get-Outcome $again) -ceq "replayed" -and (Get-Said $again).wordingStated -eq $false -and (Get-Said $again).saidToEarlierWording -eq $false -and (Get-Count $s) -eq 5) ("a repost after the question was reworded is still a repost, answered as it was recorded: wording not stated, and not flagged (" + (Get-Outcome $again) + ")")

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
Check ((Get-Outcome $a) -ceq "done" -and (Get-Said $a).wordingStated -eq $false -and (Get-Said $a).saidToEarlierWording -eq $false -and $null -eq (Read-Record $s $a.value.sequence).data.PSObject.Properties["wordingVersion"]) "with no wording named, the record holds NO wording: it is 'not stated', nothing is guessed, and it is not flagged as said to an earlier one"
Check ((Test-Refused (Say $s 1 "Typed with no wording." -Route "window" -Actor "founder") "always say which wording") -and (Get-Outcome (Say $s 1 "Typed, wording stated." -Route "window" -Actor "founder" -Wording 2)) -ceq "done") "words typed in the window must state the wording that was on screen, and with it are recorded"
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
$hebrew = "" + [char]0x202B + [char]0x05DB + [char]0x05DF + [char]0x200F + ", " + [char]0x2067 + [char]0x05EA + [char]0x05DE + [char]0x05E9 + [char]0x05D9 + [char]0x05DA + [char]0x2069 + [char]0x202C + " " + [char]0x061C + [char]0x200B + [char]0x2060 + [char]0x200E + "(yes)" + [char]0x200D + "`r`n  " + [char]0x05EA + [char]0x05D5 + [char]0x05D3 + [char]0x05D4 + "  "
$a = Say $s 1 $hebrew
Check ((Get-Outcome $a) -ceq "done" -and [string]::Equals((Get-Said $a).text, $hebrew, [System.StringComparison]::Ordinal)) ("a Hebrew sentence with an embedding, an isolate pair, marks, a zero-width space and a word joiner is recorded as it is (" + (Get-Outcome $a) + ")")
Check ([string]::Equals((Get-Thread $s 1).messages[0].text, $hebrew, [System.StringComparison]::Ordinal)) "and reads back from the store character for character: marks, line break and the spaces at both ends"
Check ([string]::Equals((Read-Record $s 2).data.text, $hebrew, [System.StringComparison]::Ordinal)) "the record on disk holds exactly those characters"
$long = ("word " * 19999) + "end!!"
$a = Say $s 1 $long
Check ($long.Length -eq 100000 -and (Get-Outcome $a) -ceq "done" -and (Get-Said $a).text.Length -eq 100000) ("a message of 100,000 characters is recorded whole (" + (Get-Outcome $a) + ")")
Check ([string]::Equals((Get-Thread $s 1).messages[1].text, $long, [System.StringComparison]::Ordinal)) "and all 100,000 read back, in order, nothing cut"
$exact = "  leading spaces`ttab, CRLF`r`nthen LF`nthen two blank lines`r`n`r`n"
$a = Say $s 1 $exact
Check ((Get-Outcome $a) -ceq "done" -and [string]::Equals((Get-Thread $s 1).messages[2].text, $exact, [System.StringComparison]::Ordinal)) "spaces at both ends, a tab and line breaks of both kinds are kept as they were: nothing is trimmed or re-wrapped"
$inboxHebrew = @((Inbox $s).value.messages)[0].message
Check ([string]::Equals($inboxHebrew.text, $hebrew, [System.StringComparison]::Ordinal) -and [System.Convert]::ToBase64String($utf8.GetBytes($inboxHebrew.text)) -ceq [System.Convert]::ToBase64String($utf8.GetBytes($hebrew))) "and comes back out of the inbox byte for byte"
Check ((Get-Thread $s 1).messages[0].holdsDirectionOrInvisibleCharacters -eq $true -and (Get-Thread $s 1).messages[1].holdsDirectionOrInvisibleCharacters -eq $false -and $inboxHebrew.holdsDirectionOrInvisibleCharacters -eq $true) "the message says of itself that it holds direction or invisible characters, in show and in the inbox, so that whatever shows it knows to isolate it; the long plain one says it does not"
$separated = Say $s 1 ("first part" + [char]0x2028 + "second part of what he said")
Check ((Test-Refused $separated "'text' holds the character U+2028") -and (Get-Count $s) -eq 4 -and -not (Test-Echo $separated "second part of what he said")) ("a LINE SEPARATOR (U+2028) in a message is refused by its code point: not removed, and the words are not repeated (" + (Get-Outcome $separated) + ")")
$titled = Invoke-Op $s "add" @{ id = (New-Id); actor = "warchief"; question = @{ title = ("Should " + [char]0x2067 + "this" + [char]0x2069 + " closing sound play at all here?"); kind = "yes-no"; whatItIs = "x"; group = "voice"; askedBy = "orc-b" } }
Check ((Test-Refused $titled "'title' holds the character U+2067") -and (Get-Count $s) -eq 4) "CONTROL: an isolate in a question's TITLE is still refused: only what is said is taken as typed"
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
Check (Test-Refused (Say $s 1 "hello" -Actor "warg") "'warg' is not a role that may speak under a question") "a role outside the speakers is refused, with the list"
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
Write-Host "--- inbox: what the warchief has not read, across questions, oldest first; it only reads ---" -ForegroundColor Cyan
$s = New-TestStore
$empty = Inbox $s
Check ((Get-InboxLine $empty) -ceq " upTo=0" -and -not (Test-Path -LiteralPath $s)) ("with no store yet the inbox is empty, and reading it made no folder (" + (Get-InboxLine $empty) + ")")
$null = Add-Q $s "Should the closing sound play when the assistant closes?"
$null = Add-Q $s "Which languages besides English should the test talker speak?"
$null = Say $s 1 "one, under the first"          # record 3
$null = Say $s 2 "two, under the second"         # record 4
$null = Reply $s 1 "the warchief's own reply" -Note   # record 5
$null = Say $s 1 "three, under the first again"  # record 6
$read = Inbox $s
Check ((Get-InboxLine $read) -ceq "3@1,4@2,6@1 upTo=6") ("the inbox holds the founder's three messages, from both questions, oldest first, and not the warchief's own reply; upTo names the last of them (" + (Get-InboxLine $read) + ")")
Check ((Get-Outcome $read) -ceq "done" -and $read.value.messages[1].title -ceq "Which languages besides English should the test talker speak?" -and $read.value.messages[1].message.text -ceq "two, under the second" -and $read.value.messages[1].state -ceq "open") "each with its question's number, its plain-words title and the words"
Check ((Get-Count $s) -eq 6 -and (Get-InboxLine (Inbox $s)) -ceq "3@1,4@2,6@1 upTo=6" -and (Get-Unread (Get-Thread $s 1)) -eq 2 -and (Get-Unread (Get-Thread $s 2)) -eq 1) "READING MARKS NOTHING AND WRITES NOTHING, however often: the same inbox again is the same three, all still unread, and the store has no new record"
Check ($null -eq $read.value.PSObject.Properties["marked"] -and $null -eq $read.value.PSObject.Properties["sequence"]) "an inbox answer says nothing of marking: it has no way to mark"
$before = Get-Count $s
Check ((Test-Refused (Invoke-Op $s "inbox" @{ actor = "warchief"; mark = $true; id = (New-Id) }) "request has 'mark'") -and (Get-Count $s) -eq $before -and (Get-InboxLine (Inbox $s)) -ceq "3@1,4@2,6@1 upTo=6") "READING AND MARKING ARE TWO OPERATIONS: an inbox asked to mark is refused as not what inbox takes, and marks nothing"
Check ((Test-Refused (Inbox $s -Actor "founder") "'founder' has no inbox; the roles that have one are: warchief") -and (Test-Refused (Inbox $s -Actor "warg") "'warg' has no inbox")) "a role with no inbox is told so"

Write-Host ""
Write-Host "--- mark-read: up to a given record, as one record of its own, and idempotent ---" -ForegroundColor Cyan
$markId = New-Id
$marked = Mark $s 6 -Id $markId
Check ((Get-MarkLine $marked) -ceq "done upTo=6 marked=3" -and $marked.value.sequence -eq 7 -and $marked.value.attempts -eq 1) ("marking up to record 6 is done, as record 7, and says it marked the three messages up to there (" + (Get-MarkLine $marked) + ")")
$rec = Read-Record $s 7
Check ($rec.kind -ceq "messages-read" -and $rec.actor -ceq "warchief" -and $rec.data.reader -ceq "warchief" -and $rec.data.upTo -eq 6 -and (@($rec.data.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object) -join ",") -ceq "reader,upTo") "marking is one record of its own: the warchief has read up to record 6"
Check ($null -eq $marked.value.PSObject.Properties["messages"]) "a marking answer carries no messages: reading them is the inbox's"
Check ((Get-Unread (Get-Thread $s 1)) -eq 0 -and (Get-Unread (Get-Thread $s 2)) -eq 0 -and (Get-InboxLine (Inbox $s)) -ceq " upTo=0") "and now nothing is unread by the warchief: THE SECOND INBOX IS EMPTY"
# IDEMPOTENT, three ways: the same id again; a new id for the same record; a new id for an earlier one.
$again = Mark $s 6 -Id $markId
Check ((Get-MarkLine $again) -ceq "replayed upTo=6 marked=3" -and $again.value.sequence -eq 7 -and (Get-Count $s) -eq 7) ("the same marking sent again, same id, is answered from its record and writes nothing (" + (Get-MarkLine $again) + ")")
$same = Mark $s 6
Check ((Get-MarkLine $same) -ceq "done upTo=6 marked=0" -and (Get-Count $s) -eq 7 -and $null -eq $same.value.PSObject.Properties["sequence"]) ("marking up to a record already read, under a new id, is done, marks nothing and WRITES NOTHING (" + (Get-MarkLine $same) + "; " + (Get-Count $s) + " records)")
$back = Mark $s 4
Check ((Get-MarkLine $back) -ceq "done upTo=4 marked=0" -and (Get-Count $s) -eq 7 -and (Get-InboxLine (Inbox $s)) -ceq " upTo=0") "marking up to an earlier record never moves the mark back: nothing becomes unread again"
$null = Say $s 2 "four, said after the marking"   # record 8
Check ((Get-InboxLine (Inbox $s)) -ceq "8@2 upTo=8" -and (Get-Unread (Get-Thread $s 2)) -eq 1) "a message said after the marking is unread, and is the whole of the next inbox"
Check ((Get-MarkLine (Mark $s 6 -Id $markId)) -ceq "replayed upTo=6 marked=3" -and (Get-InboxLine (Inbox $s)) -ceq "8@2 upTo=8") "and the old marking sent yet again still answers as it was, and does not mark the new message"
# The title an inbox shows is the question as it reads now.
$null = Invoke-Op $s "update" @{ id = (New-Id); actor = "warchief"; number = 2; changes = @{ title = "Which languages should the test talker speak first?" } }
$now = Inbox $s
Check ($now.value.messages[0].title -ceq "Which languages should the test talker speak first?" -and $now.value.messages[0].message.saidToEarlierWording -eq $false -and $now.value.messages[0].message.wordingStated -eq $false) "the inbox names a question by its words as they are now; the message, recorded from chat with no wording stated, says so and is not flagged"

Write-Host ""
Write-Host "--- mark-read: only up to the record named, and never past what is written ---" -ForegroundColor Cyan
$s = New-TestStore
$null = Add-Q $s
$null = Say $s 1 "first"    # record 2
$null = Say $s 1 "second"   # record 3
$null = Say $s 1 "third"    # record 4
$bounded = Mark $s 3
Check ((Get-MarkLine $bounded) -ceq "done upTo=3 marked=2" -and (Read-Record $s 5).data.upTo -eq 3) ("marking up to record 3 marks the two up to it (" + (Get-MarkLine $bounded) + ")")
Check ((Get-InboxLine (Inbox $s)) -ceq "4@1 upTo=4" -and (Get-Unread (Get-Thread $s 1)) -eq 1) "and the third, beyond the record named, is NOT marked: it is still unread"
$before = Get-Count $s
$future = Mark $s 6
Check ((Get-Outcome $future) -ceq "refused" -and (Test-Refused $future "not before this record") -and (Get-Count $s) -eq $before -and (Get-InboxLine (Inbox $s)) -ceq "4@1 upTo=4") ("marking up to a record that is not written yet is refused: nothing is read before it is written (" + (Get-Outcome $future) + ")")
Check ((Test-Refused (Invoke-Op $s "mark-read" @{ actor = "warchief"; upTo = 4 }) "request has no 'id'") -and (Get-Count $s) -eq $before) "marking without an id is refused: it writes, and the id is what makes sending it twice one marking"
Check ((Test-Refused (Invoke-Op $s "mark-read" @{ actor = "warchief"; id = (New-Id) }) "request has no 'upTo'") -and (Get-Count $s) -eq $before) "marking with no record named is refused: there is no 'mark everything'"
Check ((Test-Refused (Mark $s 4 -Actor "founder") "'founder' has no inbox; the roles that have one are: warchief") -and (Get-Count $s) -eq $before) "a speaker with no inbox cannot mark"
Check ((Test-Refused (Mark $s 4 -Actor "warg") "'warg' is not a role that may speak under a question, or mark what was said there as read") -and (Get-Count $s) -eq $before) "and a role that does not speak cannot either"
Check ((Test-Refused (Invoke-Op $s "mark-read" @{ actor = "warchief"; id = (New-Id); upTo = 1e30 }) "'upTo' is not a record's sequence number") -and (Get-Count $s) -eq $before) "a record number no record can have is refused, not thrown on"
Check ((Get-InboxLine (Inbox $s)) -ceq "4@1 upTo=4") "CONTROL: none of the refusals marked anything"
# A mark may name a record that is not a message: everything said up to it is read.
$null = Reply $s 1 "a reply, record 6" -Note   # record 6
$upToReply = Mark $s 6
Check ((Get-MarkLine $upToReply) -ceq "done upTo=6 marked=1" -and (Get-InboxLine (Inbox $s)) -ceq " upTo=0") ("marking up to a later record that is not the founder's marks what he said before it (" + (Get-MarkLine $upToReply) + ")")

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
    # A NEW MESSAGE WINS THE PLACE A MARKING WANTED. The marking names the record it marks up to - the
    # last message its caller showed - so the new message, which is beyond it, is NOT marked: the
    # marking is written next, still up to record 2.
    $s = New-TestStore
    $null = Add-Q $s
    $null = Say $s 1 "shown to the person"   # record 2
    $script:planted = 0; $script:plantText = New-Planted 3 "message-said" '{"number":1,"speaker":"founder","route":"chat-recorded","text":"arrived after the showing"}' "e"
    $a = Mark $s 2
    Check ($script:planted -eq 1 -and (Get-MarkLine $a) -ceq "done upTo=2 marked=1" -and $a.value.attempts -eq 2 -and $a.value.sequence -eq 4) ("a marking that lost its place to a new message is written next, and marks only up to the record it named (" + (Get-MarkLine $a) + ")")
    Check ((Get-InboxLine (Inbox $s)) -ceq "3@1 upTo=3" -and (Read-Record $s 4).data.upTo -eq 2) "THE NEW MESSAGE IS NEVER MARKED READ UNSEEN: it is the next inbox"
    # ANOTHER READER'S MARKING WINS THE PLACE: this one, worked out again, has nothing left to mark and writes nothing.
    $s = New-TestStore
    $null = Add-Q $s
    $null = Say $s 1 "read by two at once"   # record 2
    $script:planted = 0; $script:plantText = New-Planted 3 "messages-read" '{"reader":"warchief","upTo":2}' "f"
    $a = Mark $s 2
    Check ($script:planted -eq 1 -and (Get-MarkLine $a) -ceq "done upTo=2 marked=0" -and (Get-Count $s) -eq 3) ("a marking that lost its place to another marking of the same record writes no second one (" + (Get-MarkLine $a) + ")")
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
$null = Mark $s (Inbox $s).value.upTo;                               [void]$turns.Add((Get-Turn $s))   # it reads and marks: not a turn
$asked = Reply $s 1 "the short one, or the long one?";               [void]$turns.Add((Get-Turn $s))   # it asks him again: REFUSED, nothing changes
$null = Reply $s 1 "the short one" -Note;                            [void]$turns.Add((Get-Turn $s))   # it tells him, asking nothing: still its own turn
$null = Say $s 1 "then yes";                                         [void]$turns.Add((Get-Turn $s))   # he speaks
$null = Invoke-Op $s "close" @{ id = (New-Id); actor = "warchief"; number = 1; outcome = "Done." };       [void]$turns.Add((Get-Turn $s))   # it closes instead of replying
$null = Say $s 1 "thank you";                                        [void]$turns.Add((Get-Turn $s))   # he changes his answer under a closed question: REFUSED by name (T-0152), nothing changes
$reopened = Invoke-Op $s "reopen" @{ id = (New-Id); actor = "warchief"; number = 1; reason = "it came back" }; [void]$turns.Add((Get-Turn $s))   # asked again: REFUSED too
Check (($turns -join " ") -ceq "founder/0/0 warchief/1/1 warchief/1/0 warchief/1/0 warchief/2/0 warchief/3/1 nobody/3/1 nobody/3/1 nobody/3/1") ("turn, messages and unread after each step of an exchange: " + ($turns -join " "))
Check ((Show $s 1).value.question.thread.turnShown -ceq "nobody" -and (Show (New-TestStore) 1).state -ceq "absent") "and the turn is told to a person in words"

Write-Host ""
Write-Host "--- an answered question is never put back in front of him ---" -ForegroundColor Cyan
# THE FOUNDER'S RULE, 2026-10-12: once he answers a question it goes away from his list, even if there
# is a follow-up; a follow-up is a brand-new question, never the old one reopened in place. The two
# requests of the exchange above that would have put question 1 back were refused, each saying what
# to do instead, and each writing nothing.
Check ((Test-Refused $asked "question 1 has been answered and is off the founder's list") -and (Test-Refused $asked "horde decisions add -File <question.json> -FollowsUp 1") -and (Test-Refused $asked "say it as a note (reply -Note)") -and -not (Test-Echo $asked "the short one, or the long one?")) "THE KEEPER'S WORDS THAT ASK, under a question he has answered, are refused: the refusal names the follow-up and the note, and does not repeat the words"
Check ((Test-Refused $reopened "nothing is reopened any more") -and (Test-Refused $reopened "-FollowsUp 1")) "and so is reopening it"
$s = New-TestStore
$null = Add-Q $s
$before = Reply $s 1 "Take the question to mean the first build only."
Check ((Get-Outcome $before) -ceq "done" -and (Get-Turn $s) -ceq "founder/1/0") "BEFORE HE HAS ANSWERED the keeper may still say something that asks: the question is in front of him already, and stays there"
$null = Say $s 1 "yes"
$count = Get-Count $s
$after = Reply $s 1 "And for the second build?"
Check ((Get-Outcome $after) -ceq "refused" -and (Get-Count $s) -eq $count -and (Get-Turn $s) -ceq "warchief/2/1") ("once he has, the same kind of reply is refused and nothing is written (" + (Get-Outcome $after) + ")")
$id = New-Id
$note = Invoke-Op $s "say" @{ id = $id; actor = "warchief"; number = 1; speaker = "warchief"; route = "command"; text = "Done as you said."; asks = $false }
Check ((Get-Outcome $note) -ceq "done" -and (Get-Turn $s) -ceq "warchief/3/1") "a note is taken, and leaves the question where it is: off his list"
# A FOLLOW-UP IS A NEW QUESTION: it has its own number, it is his turn, and it carries the old question
# and what he answered as context - worked out from the list, so it is the answer as it stands.
$follow = Invoke-Op $s "add" @{ id = (New-Id); actor = "warchief"; followsUp = 1; question = @{ title = "Should the closing sound play in the second build as well?"; kind = "yes-no"; whatItIs = "A follow-up."; group = "voice"; askedBy = "orc-b" } }
Check ((Get-Outcome $follow) -ceq "done" -and $follow.value.number -eq 2 -and $follow.value.question.thread.turn -ceq "founder" -and $follow.value.question.followsUp.number -eq 1 -and $follow.value.question.followsUp.title -ceq "Should the closing sound play when the assistant closes?" -and $follow.value.question.followsUp.answer -ceq "yes" -and $follow.value.question.followsUp.answerCut -eq $false) "THE FOLLOW-UP is question 2, the founder's turn, and shows question 1 and his answer to it"
Check ((Get-Turn $s) -ceq "warchief/3/1" -and (Show $s 1).value.question.state -ceq "open") "and question 1 is as it was: answered, the keeper's, and not reopened"
# RECORDS ALREADY IN A STORE ARE FACTS. A reply that asks, written under an answered question before
# this rule, still gives him the turn - once, until he answers - exactly as it did the day it was written.
$old = New-TestStore
$null = Add-Q $old
$null = Say $old 1 "which one do you mean?"
$null = Add-Stored $old "message-said" ([ordered]@{ number = 1; speaker = "warchief"; route = "command"; text = "the short one" })
Check ((Get-Turn $old) -ceq "founder/2/1" -and (Get-Texts (Get-Thread $old 1)) -ceq "which one do you mean? | the short one") ("AN ASKING REPLY ALREADY IN THE STORE still puts the question in front of him, as it did (" + (Get-Turn $old) + ")")
$null = Say $old 1 "then yes"
Check ((Get-Turn $old) -ceq "warchief/3/2" -and (Get-Outcome (Reply $old 1 "and the long one?")) -ceq "refused") "until he answers it: then it is off his list, and stays off"
# UNDER A CLOSED QUESTION nothing is anybody's turn and nothing is in front of him: the keeper's words
# are kept there as they always were, flagged as having arrived after closing, whether or not they ask.
$null = Invoke-Op $old "close" @{ id = (New-Id); actor = "warchief"; number = 1; outcome = "Done." }
$afterClose = Reply $old 1 "Was that what you meant?"
Check ((Get-Outcome $afterClose) -ceq "done" -and (Get-Said $afterClose).arrivedAfterClosing -eq $true -and (Get-Turn $old) -ceq "nobody/4/2") ("the keeper's words under a CLOSED question are kept, flagged, and put nothing in front of him (" + (Get-Outcome $afterClose) + ")")

Write-Host ""
Write-Host "--- a note asks nothing, an act passes no turn, an edit says it replaces ---" -ForegroundColor Cyan
$s = New-TestStore
$null = Add-Q $s
function SayMarked { param([string]$Store, [hashtable]$More, [string]$Speaker = "founder", [string]$Route = "window", [string]$Actor = "founder", [string]$Text = "words") $r = @{ id = (New-Id); actor = $Actor; number = 1; speaker = $Speaker; route = $Route; text = $Text; wordingVersion = 1 }; foreach ($k in $More.Keys) { $r[$k] = $More[$k] }; return (Invoke-Op $Store "say" $r) }
$turns = New-Object System.Collections.ArrayList
$null = SayMarked $s @{} -Text "yes";                                                                  [void]$turns.Add((Get-Turn $s))   # he answers
$null = SayMarked $s @{ asks = $false } -Speaker "warchief" -Route "command" -Actor "warchief" -Text "noted, working on it"; [void]$turns.Add((Get-Turn $s))   # a note
$null = SayMarked $s @{ asks = $true } -Speaker "warchief" -Route "command" -Actor "warchief" -Text "which build?";     [void]$turns.Add((Get-Turn $s))   # a reply that asks: refused (above)
$null = SayMarked $s @{ act = "park" } -Text "parked";                                                  [void]$turns.Add((Get-Turn $s))   # he parks it
$null = SayMarked $s @{ act = "unpark" } -Text "unparked";                                              [void]$turns.Add((Get-Turn $s))   # and brings it back
Check (($turns -join " ") -ceq "warchief/1/1 warchief/2/1 warchief/2/1 warchief/3/2 warchief/4/3") ("A NOTE KEEPS THE TURN THE KEEPER'S; a reply that asks is refused and changes nothing; his park and unpark pass no turn: " + ($turns -join " "))
$msgs = @((Show $s 1).value.question.thread.messages)
Check ((@($msgs | ForEach-Object { "" + $_.asks + ":" + $_.act }) -join " ") -ceq "True: False: True:park True:unpark") "each message says whether it asks and what act it records, and a record that says neither asks and records none"
$edit = SayMarked $s @{} -Text "yes, the short build"
$msgs = @((Show $s 1).value.question.thread.messages)
Check ((Get-Outcome $edit) -ceq "done" -and $msgs[4].replaces -eq $false -and $msgs[0].replaces -eq $false) "his words after the keeper's words replace nothing"
$again = SayMarked $s @{} -Text "yes, the long build after all"
$msgs = @((Show $s 1).value.question.thread.messages)
Check ($msgs[5].replaces -eq $true -and $msgs[5].speaker -ceq "founder") "HIS WORDS STRAIGHT AFTER HIS OWN replace them, and the message says so"
$parkThenEdit = SayMarked $s @{ act = "park" } -Text "parked"
$afterPark = SayMarked $s @{} -Text "yes, final"
$msgs = @((Show $s 1).value.question.thread.messages)
Check ($msgs[7].replaces -eq $true) "an act between them is left aside: words after his park still replace his answer before it"
Check (Test-Refused (SayMarked $s @{ asks = $false } -Text "a founder note") "can be a note") "a note from the founder is refused: only the keeper's words can ask nothing"
Check (Test-Refused (SayMarked $s @{ act = "park" } -Speaker "warchief" -Route "command" -Actor "warchief") "only for the founder's words typed in the window") "an act by the keeper is refused"
Check (Test-Refused (SayMarked $s @{ act = "archive" }) "act") "an act that is not park or unpark is refused"
Check (Test-Refused (SayMarked $s @{ asks = "no" } -Speaker "warchief" -Route "command" -Actor "warchief") "asks") "asks that is not true or false is refused"
$inbox = Inbox $s
Check (@($inbox.value.messages | Where-Object { $_.message.act -ceq "park" }).Count -eq 2) "his acts reach the keeper's inbox like his words: the keeper sees that he parked it"

Write-Host ""
Write-Host "--- a question of parts: each part is answered by a record of its own ---" -ForegroundColor Cyan
# THE FOUNDER, 2026-10-12: sub-questions each send by themselves; the parent question leaves his list
# when all its parts are answered; the keeper is told which part was answered.
$s = New-TestStore
$partsQuestion = @{ title = "Three follow-ups to settle about the new wording, one by one."; kind = "parts"; whatItIs = "Follow-ups."; group = "voice"; askedBy = "orc-b"; parts = @("(a) The sentence when she cannot zoom: approve, or reword.", "(b) Should the button say Video too?", "(c) Should page turns be refused?") }
$null = Invoke-Op $s "add" @{ id = (New-Id); actor = "warchief"; question = $partsQuestion }
function SayPart { param([string]$Store, [string]$Part, [string]$Text, [string]$Id = "", [string]$Route = "window", [string]$Actor = "founder", [int]$Wording = 1, [hashtable]$More = @{}) if ($Id -eq "") { $Id = New-Id }; $r = @{ id = $Id; actor = $Actor; number = 1; speaker = "founder"; route = $Route; text = $Text; part = $Part }; if ($Wording -gt 0) { $r["wordingVersion"] = $Wording }; foreach ($k in $More.Keys) { $r[$k] = $More[$k] }; return (Invoke-Op $Store "say" $r) }
function Get-PartsOf { param([string]$Store) $l = Invoke-Op $Store "list" @{ state = "all" }; if ((Get-Outcome $l) -cne "done") { return (Get-Outcome $l) }; $t = $l.value.questions[0].thread; if ($null -eq $t.PSObject.Properties["parts"]) { return ("(none) " + $t.turn) }; return ((@($t.parts | ForEach-Object { $_.letter + ":" + $(if ($_.answered) { "y" } else { "n" }) }) -join ",") + " " + $t.turn) }
Check ((Get-PartsOf $s) -ceq "a:n,b:n,c:n founder") "a list says of a question of parts which are answered: none yet, and it is his turn"
$idB = New-Id
$b = SayPart $s "b" "No, keep Live View." -Id $idB
Check ((Get-Outcome $b) -ceq "done" -and $b.value.sequence -eq 2 -and (Get-Said $b).text -ceq "No, keep Live View." -and $b.value.message.part -ceq "b" -and $b.value.message.partWords -ceq "Should the button say Video too?" -and (Read-Record $s 2).data.part -ceq "b") ("ONE PART, ANSWERED BY ITSELF: a record of its own that names the part, handed back with the part's own words (" + (Get-Outcome $b) + ")")
Check ((Get-PartsOf $s) -ceq "a:n,b:y,c:n founder" -and $b.value.question.thread.turn -ceq "founder") "that part is answered, the others are not, and the question is STILL HIS: it has not left his list"
$again = SayPart $s "b" "No, keep Live View." -Id $idB
Check ((Get-Outcome $again) -ceq "replayed" -and $again.value.sequence -eq 2 -and $again.value.message.part -ceq "b" -and (Get-Count $s) -eq 2) "IDEMPOTENT: the same part's answer sent again under its id is that one record, answered again, part and all"
$elsewhere = SayPart $s "c" "No, keep Live View." -Id $idB
Check ((Test-Refused $elsewhere "was already used for a different request") -and (Get-Count $s) -eq 2 -and (Get-PartsOf $s) -ceq "a:n,b:y,c:n founder") "the same words under the same id to ANOTHER part are a different request: refused, and part (c) is not answered by it"
$whole = Invoke-Op $s "say" @{ id = $idB; actor = "founder"; number = 1; speaker = "founder"; route = "window"; text = "No, keep Live View."; wordingVersion = 1 }
Check ((Test-Refused $whole "was already used for a different request") -and (Get-PartsOf $s) -ceq "a:n,b:y,c:n founder") "and so are the same words under that id to the whole question: an answer to a part is never taken for an answer to all of it"
$inbox = Inbox $s
Check ((Get-InboxLine $inbox) -ceq "2@1 upTo=2" -and $inbox.value.messages[0].message.part -ceq "b" -and $inbox.value.messages[0].message.partWords -ceq "Should the button say Video too?") "THE KEEPER'S INBOX says which part was answered: its letter and its words, with his"
# The keeper may still say something that asks while a part is left: the question is in front of him.
$ask = Reply $s 1 "For (a): the long sentence or the short one?"
Check ((Get-Outcome $ask) -ceq "done" -and (Get-PartsOf $s) -ceq "a:n,b:y,c:n founder") "while a part is left the keeper's words that ask are taken, and the answered part stays answered"
$a = SayPart $s "a" "Approve the short one."
$c = SayPart $s "c" "Yes, refuse them." -Route "phone" -More @{ evidence = ("ab" * 32); signedBy = ("c" * 32) }
Check ((Get-Outcome $a) -ceq "done" -and (Get-Outcome $c) -ceq "done" -and (Get-PartsOf $s) -ceq "a:y,b:y,c:y warchief" -and $c.value.question.thread.turn -ceq "warchief" -and $c.value.message.routeShown -ceq "answered on the founder's phone" -and $c.value.message.signedBy -ceq ("c" * 32) -and (Read-Record $s 5).data.part -ceq "c" -and (Read-Record $s 5).data.signedBy -ceq ("c" * 32)) ("WITH THE LAST PART ANSWERED - here from his phone, its record naming the passkey that signed like any phone answer's - the question is the keeper's turn: off his list (" + (Get-PartsOf $s) + ")")
Check ((Get-Outcome (Reply $s 1 "And one more thing?")) -ceq "refused" -and (Get-Outcome (Reply $s 1 "All three done as you said." -Note)) -ceq "done") "and then, like any answered question, it takes a note and refuses words that ask"
$edit = SayPart $s "b" "Yes after all, say Video."
Check ((Get-Outcome $edit) -ceq "done" -and (Get-Said $edit).text -ceq "Yes after all, say Video." -and (Get-PartsOf $s) -ceq "a:y,b:y,c:y warchief") "he may still answer a part again: it is kept, and brings nothing back to his list"
$filesWere = Get-Files $s
Check ((Test-Refused (SayPart $s "d" "x") "it answers part (d) of question 1, which has no such part; its parts are: (a), (b), (c)") -and (Test-Refused (Invoke-Op $s "say" @{ id = (New-Id); actor = "founder"; number = 1; speaker = "founder"; route = "window"; text = "x"; wordingVersion = 1; part = "B" }) "request.part") -and (Test-Refused (Invoke-Op $s "say" @{ id = (New-Id); actor = "warchief"; number = 1; speaker = "warchief"; route = "command"; text = "x"; part = "a"; asks = $false }) "only the words of the founder answer a part of a question") -and (Test-Refused (SayPart $s "a" "parked" -More @{ act = "park" }) "an act answers no part of a question") -and (Get-Files $s) -ceq $filesWere) "a part the question does not have, a part that is not a lower-case letter, a part named by the keeper, and a part with an act are each refused, and nothing is written"
$other = New-TestStore
$null = Add-Q $other
Check ((Test-Refused (SayPart $other "a" "x") "which is not a question of parts that are answered one by one") -and (Get-Count $other) -eq 1) "and so is a part of a question that has none"
# Recorded from chat by the keeper: the founder's words to one part, as he said them there.
$chat = New-TestStore
$null = Invoke-Op $chat "add" @{ id = (New-Id); actor = "warchief"; question = $partsQuestion }
$fromChat = SayPart $chat "a" "Approve." -Route "chat-recorded" -Actor "warchief" -Wording 0
Check ((Get-Outcome $fromChat) -ceq "done" -and $fromChat.value.message.part -ceq "a" -and $fromChat.value.message.routeShown -ceq "recorded by the warchief from chat" -and (Get-PartsOf $chat) -ceq "a:y,b:n,c:n founder") "words the keeper recorded from chat may answer one part too"
# A WHOLE ANSWER, as every surface sent before parts were answered one by one: still an answer to all of it.
$joined = Invoke-Op $chat "say" @{ id = (New-Id); actor = "founder"; number = 1; speaker = "founder"; route = "window"; text = "(a) x`n(b) y`n(c) z"; wordingVersion = 1 }
Check ((Get-Outcome $joined) -ceq "done" -and $joined.value.message.part -eq "" -and $joined.value.question.thread.turn -ceq "warchief") "an answer that names no part - what an earlier window or phone sends for all the parts at once - passes the turn as it always did"

} finally {
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-decisions-threads-test-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the suite's temp folder is removed"
Check ((Get-RealStoreListing) -ceq $realBefore) "the real store under the user profile is exactly as it was before the suite"

Complete-HordeSuite -Success "what is said under a question is kept whole and once, never dropped, and handed to its reader with nothing marked read unseen"
