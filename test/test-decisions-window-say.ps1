# DOES THE DECISIONS WINDOW STORE WHAT THE FOUNDER TYPES, AND ONLY THAT, WITH NO WINDOW OPEN?
#
# decisions/Window.ps1 answers one request that writes: say. Its handler, Invoke-HordeDecisionWindowSay,
# is a pure function of what the page sent and of what the operation say answers; this suite holds it
# against a real store of its own: words accepted and read back through the operation show; words
# refused with the rule's own sentence, which repeats none of them; words longer than a text may be;
# arguments of the wrong type; a question that is not there; and a closed question, under which the
# words are stored and flagged. It also holds the two readers beside it: the file of messages a
# notifier has announced, and the conversation put into the list the page is handed.
#
# NOTHING OF THIS MACHINE IS READ. The home and the store are folders of this suite's own, removed at
# the end. No window is opened and no process is started.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

$work = Join-Path $env:TEMP ("horde-decisions-window-say-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$hordeHome = Join-Path $work "home"
$keepHome = $env:HORDE_HOME; $keepFleet = $env:WEZFLEET_ROOT
$env:HORDE_HOME = $hordeHome
$env:WEZFLEET_ROOT = Join-Path $work "no-fleet"
$utf8 = New-Object System.Text.UTF8Encoding($false)
try {
. (Join-Path $root "decisions\Window.ps1")

function New-Id { return [guid]::NewGuid().ToString("N") }
function Get-Thread { param([int]$Number) return @((Invoke-HordeDecision -Operation "show" -Request @{ number = $Number }).value.question.thread.messages) }
function Say { param($Number, $Text, $Wording = 1, $Id = (New-Id)) return (Invoke-HordeDecisionWindowSay -Arguments @{ number = $Number; text = $Text; wording = $Wording; id = $Id }) }
foreach ($n in 1..3) {
    $added = Invoke-HordeDecision -Operation "add" -Request @{ id = (New-Id); actor = "warchief"; question = @{ title = ("Should step " + $n + " go ahead?"); kind = "yes-no"; whatItIs = "A step of the plan."; group = "The study"; askedBy = "Orc B"; recommendation = "yes" } }
    if ($added.state -cne "known" -or $added.value.outcome -cne "done") { throw ("question " + $n + " was not added: " + $added.reason) }
}
$storeFiles = { @(Get-ChildItem -LiteralPath (Join-Path $hordeHome "store\decisions") -File).Count }

Write-Host ""
Write-Host "--- accepted: the words are stored once, as typed in the window ---" -ForegroundColor Cyan
$id = New-Id
$words = "Yes.`nBut only after the review, and not on a Friday."
$said = Say 1 $words 1 $id
$thread = @(Get-Thread 1)
Check ($said.ok -eq $true -and $said.sequence -eq 4 -and $said.replayed -eq $false -and $said.arrivedAfterClosing -eq $false -and $said.saidToEarlierWording -eq $false) "the handler answers ok, with the record's number, and no flag"
Check ($thread.Count -eq 1 -and $thread[0].text -ceq $words -and [long]$thread[0].sequence -eq 4) "the operation show gives the words back, every character and the line break"
Check ($thread[0].speaker -ceq "founder" -and $thread[0].route -ceq "window" -and $thread[0].recordedBy -ceq "founder" -and $thread[0].wordingStated -eq $true -and $thread[0].wordingVersion -eq 1) "said by the founder, typed in the window, to the wording the page named"
$twice = Say 1 $words 1 $id
Check ($twice.ok -eq $true -and $twice.replayed -eq $true -and $twice.sequence -eq 4 -and @(Get-Thread 1).Count -eq 1 -and (& $storeFiles) -eq 4) "THE SAME WORDS SENT AGAIN UNDER THE SAME ID are answered from the record: one message, nothing written"
$other = Say 1 "Something else entirely" 1 $id
Check ($other.ok -eq $false -and $other.reason -clike "Not saved:*" -and @(Get-Thread 1).Count -eq 1) ("the same id with other words is refused, and says so (" + $other.reason + ")")

Write-Host ""
Write-Host "--- refused: answered as a value, in the rule's own sentence, with none of the words in it ---" -ForegroundColor Cyan
# Put together here so that this file holds nothing shaped like what it describes.
$unsafe = "the admin pass" + "word is " + "hunter" + "42x"
$before = & $storeFiles
$threw = $false
try { $refused = Say 2 $unsafe } catch { $threw = $true }
Check (-not $threw -and $refused.ok -eq $false) "words that hold what looks like a secret are refused BY ANSWER: the handler does not throw"
Check ($refused.reason -clike "Not saved: the request holds what looks like a secret in 1 place(s); nothing was written*" -and $refused.reason -notlike "*hunter*") ("the reason is the operation's own sentence and repeats none of the words (" + $refused.reason + ")")
Check ((& $storeFiles) -eq $before -and @(Get-Thread 2).Count -eq 0) "and nothing was written"
$blank = Say 2 "   "
Check ($blank.ok -eq $false -and $blank.reason -clike "*'text' is blank: nothing was said*" -and @(Get-Thread 2).Count -eq 0) ("blank words are refused with the rule's sentence (" + $blank.reason + ")")
$direct = Invoke-HordeDecisionWindowSay -Arguments @{ number = 2; text = "yes"; wording = 1; id = (New-Id) } -Invoke { param($Request) $script:sent = $Request; return (New-HordeUnknown -Reason "the store could not be read just now") }
Check ($direct.ok -eq $false -and $direct.reason -ceq "Not saved: the store could not be read just now") "a store that could not be read or written is NOT saved, and says the store's reason"
Check ($script:sent.speaker -ceq "founder" -and $script:sent.route -ceq "window" -and $script:sent.actor -ceq "founder" -and $script:sent.wordingVersion -eq 1 -and $script:sent.number -eq 2 -and @($script:sent.Keys).Count -eq 7) "what the handler asks the operation for is the founder's words by the window's route, with the wording and the id, and nothing else"
$thrown = Invoke-HordeDecisionWindowSay -Arguments @{ number = 2; text = "yes"; wording = 1; id = (New-Id) } -Invoke { param($Request) throw "the disk is gone" }
Check ($thrown.ok -eq $false -and $thrown.reason -clike "Not saved: the list could not be asked: *the disk is gone*") "an operation that throws is answered as not saved, never thrown on to the page"

Write-Host ""
Write-Host "--- oversized: refused whole, never cut ---" -ForegroundColor Cyan
$most = [int]$script:HordeDecisionMaxTextChars
$big = Say 2 ("a" * ($most + 1))
Check ($big.ok -eq $false -and $big.reason -clike ("*'text' is " + ($most + 1) + " characters long; the most is " + $most + "*never cut*") -and @(Get-Thread 2).Count -eq 0) "words one character longer than a text may be are refused with the rule's sentence, and nothing is stored"
$bridge = New-HordeDecisionWindowBridge
Check ([long]$bridge.requests["say"].args["text"].most -eq $most -and (@($bridge.requests["say"].args.Keys | Sort-Object) -join ",") -ceq "id,number,text,wording") "the bridge's own bound on the words is that same number, read from the rules and written nowhere else; say takes number, text, wording and id"
Check ((@($bridge.requests.Keys) -join ",") -ceq "setup,kinds,list,fleet,attachment,report,say,act,hand-back") "say is the seventh request of the closed list, and with act (his park or unpark, the same operation) the only ones that write"

Write-Host ""
Write-Host "--- wrong types, and a question that is not there ---" -ForegroundColor Cyan
$before = & $storeFiles
$cases = @(
    @{ what = "a number that is text"; args = @{ number = "1"; text = "yes"; wording = 1; id = (New-Id) }; says = "*question's number*" },
    @{ what = "a number of zero"; args = @{ number = 0; text = "yes"; wording = 1; id = (New-Id) }; says = "*question's number*" },
    @{ what = "a number with a fraction"; args = @{ number = 1.5; text = "yes"; wording = 1; id = (New-Id) }; says = "*question's number*" },
    @{ what = "words that are a number"; args = @{ number = 1; text = 7; wording = 1; id = (New-Id) }; says = "*words did not arrive as text*" },
    @{ what = "words that are missing"; args = @{ number = 1; wording = 1; id = (New-Id) }; says = "*words did not arrive as text*" },
    @{ what = "a wording that is text"; args = @{ number = 1; text = "yes"; wording = "1"; id = (New-Id) }; says = "*wording*" },
    @{ what = "no wording"; args = @{ number = 1; text = "yes"; id = (New-Id) }; says = "*wording*" },
    @{ what = "an id that is not 32 hex digits"; args = @{ number = 1; text = "yes"; wording = 1; id = "not-an-id" }; says = "*no id of 32 lowercase hex digits*" },
    @{ what = "no arguments at all"; args = $null; says = "*question's number*" }
)
foreach ($case in $cases) {
    $threw = $false; $answer = $null
    try { $answer = Invoke-HordeDecisionWindowSay -Arguments $case.args } catch { $threw = $true }
    Check (-not $threw -and $null -ne $answer -and $answer.ok -eq $false -and $answer.reason -clike "Not saved:*" -and $answer.reason -clike $case.says) ($case.what + " is answered not saved, in words, without throwing (" + $(if ($null -ne $answer) { $answer.reason }) + ")")
}
Check ((& $storeFiles) -eq $before) "none of them wrote anything"
$absent = Say 99 "yes"
Check ($absent.ok -eq $false -and $absent.reason -clike "Not saved: *no question 99*" -and (& $storeFiles) -eq $before) ("a question that is not there is answered not saved, naming the number (" + $absent.reason + ")")
$huge = Invoke-HordeDecisionWindowSay -Arguments @{ number = [long]99999999999; text = "yes"; wording = 1; id = (New-Id) }
Check ($huge.ok -eq $false -and $huge.reason -clike "Not saved:*" -and (& $storeFiles) -eq $before) "and so is a number no question can have"

Write-Host ""
Write-Host "--- a closed question: the words are stored, and flagged ---" -ForegroundColor Cyan
$closed = Invoke-HordeDecision -Operation "close" -Request @{ id = (New-Id); actor = "warchief"; number = 3; outcome = "done as recommended" }
$late = Say 3 "I would still like to say: not on a Friday."
$thread3 = @(Get-Thread 3)
Check ($closed.value.outcome -ceq "done" -and $late.ok -eq $true -and $late.arrivedAfterClosing -eq $true) "words under a closed question are accepted, and the answer says they arrived after it was closed"
Check ($thread3.Count -eq 1 -and $thread3[0].text -ceq "I would still like to say: not on a Friday." -and $thread3[0].arrivedAfterClosing -eq $true) "the store holds them, flagged"
Check ("$((Invoke-HordeDecision -Operation 'show' -Request @{ number = 3 }).value.question.state)" -ceq "closed") "and the question is still closed: saying something reopens nothing"
$changed = Invoke-HordeDecision -Operation "update" -Request @{ id = (New-Id); actor = "warchief"; number = 2; changes = @{ title = "Should step 2 go ahead next week?" } }
$stale = Say 2 "yes" 1
Check ($changed.value.outcome -ceq "done" -and $stale.ok -eq $true -and $stale.saidToEarlierWording -eq $true) "words said to a wording the question no longer has are stored, and the answer says so"

Write-Host ""
Write-Host "--- the list the page is handed carries each conversation, read once per change ---" -ForegroundColor Cyan
$state = New-HordeDecisionWindowState
$script:shows = 0
$counting = { param($Number) $script:shows++; return (Invoke-HordeDecision -Operation "show" -Request @{ number = [int]$Number }) }
$cache = @{}
$record = Add-HordeDecisionWindowThreads -Record (Get-HordeDecisionWindowRecord -Operation "list" -Request @{ state = "all" }) -Cache $cache -Told @{ "4" = $true } -Show $counting
$q = @($record.value.questions)
Check ($script:shows -eq 3 -and @($q[0].thread.messages).Count -eq 1 -and $q[0].thread.messages[0].text -ceq $words -and $q[0].thread.turn -ceq "warchief") "each question somebody spoke under has its messages and whose turn it is; show was asked once for each"
Check ($q[0].thread.messages[0].told -eq $true -and $q[1].thread.messages[0].told -eq $false -and (@($q[0].thread.messages[0].unreadBy) -join ",") -ceq "warchief") "a message the notifier announced is marked told, another is not; who has not read it is the store's own"
Check ((ConvertTo-HordeSurfaceJson -Value $record).Length -gt 100) "and the record can be handed to a page whole"
$record = Add-HordeDecisionWindowThreads -Record (Get-HordeDecisionWindowRecord -Operation "list" -Request @{ state = "all" }) -Cache $cache -Told @{} -Show $counting
Check ($script:shows -eq 3 -and @($record.value.questions)[0].thread.messages[0].told -eq $false) "read again with nothing changed, no thread is asked for again; and told follows the file, both ways"
$null = Invoke-HordeDecision -Operation "say" -Request @{ id = (New-Id); actor = "warchief"; number = 1; speaker = "warchief"; route = "command"; text = "This Friday it is."; asks = $false }
$record = Add-HordeDecisionWindowThreads -Record (Get-HordeDecisionWindowRecord -Operation "list" -Request @{ state = "all" }) -Cache $cache -Told @{} -Show $counting
Check ($script:shows -eq 4 -and @(@($record.value.questions)[0].thread.messages).Count -eq 2 -and @($record.value.questions)[0].thread.turn -ceq "warchief") "after the keeper's note, only that question's thread is asked for again, and it is still the keeper's turn"
$null = Invoke-HordeDecision -Operation "mark-read" -Request @{ id = (New-Id); actor = "warchief"; upTo = [long]$late.sequence }
$record = Add-HordeDecisionWindowThreads -Record (Get-HordeDecisionWindowRecord -Operation "list" -Request @{ state = "all" }) -Cache $cache -Told @{} -Show $counting
Check (@(@($record.value.questions)[0].thread.messages[0].unreadBy).Count -eq 0) "and once the keeper of the list has read up to a message, nobody is left who has not read it"
$failing = Add-HordeDecisionWindowThreads -Record (Get-HordeDecisionWindowRecord -Operation "list" -Request @{ state = "all" }) -Cache @{} -Show { param($Number) return (New-HordeUnknown -Reason "record 4 is held open") }
Check (@(@($failing.value.questions)[0].thread.messages).Count -eq 0 -and "$(@($failing.value.questions)[0].thread.problem)" -clike "*could not be read: record 4 is held open") "a thread that could not be had holds no message and says why: never an old one passed off as current"

Write-Host ""
Write-Host "--- the file of announced messages: read, never trusted, never in the way ---" -ForegroundColor Cyan
$told = Join-Path $work "told.json"
$none = Read-HordeDecisionWindowToldMarks -Path $told
Check (@($none.told.Keys).Count -eq 0 -and $none.problem -clike "*is not there yet*") "no file: nothing is marked, and the reason is said"
Check ((Read-HordeDecisionWindowToldMarks -Path "").problem -ceq "") "no file named: nothing is marked and nothing is wrong"
[System.IO.File]::WriteAllText($told, '{"schemaVersion":1,"rung":[{"question":2,"message":"23","at":"2026-10-07T12:00:00Z"},{"question":3,"message":24,"at":"x"},null]}', $utf8)
$good = Read-HordeDecisionWindowToldMarks -Path $told
Check ($good.problem -ceq "" -and (@($good.told.Keys | Sort-Object) -join ",") -ceq "23,24") "the agreed shape: a message's record number as text or as a number is marked"
# ONE READER for the told record, decisions/Notify.ps1's: an entry it cannot read refuses the whole
# record there, because notify must never ring again for a message whose entry it skipped; the window
# reads it the same way, marks nothing and says why.
[System.IO.File]::WriteAllText($told, '{"schemaVersion":1,"rung":[{"question":2,"message":"23","at":"2026-10-07T12:00:00Z"},{"question":4,"message":"../x"}]}', $utf8)
$junk = Read-HordeDecisionWindowToldMarks -Path $told
Check (@($junk.told.Keys).Count -eq 0 -and $junk.problem -clike "*not a record number*") ("an entry that is no record number marks nothing at all, and says why (" + $junk.problem + ")")
[System.IO.File]::WriteAllText($told, '{"schemaVersion":1,"rung":[]}', $utf8)
Check ((Read-HordeDecisionWindowToldMarks -Path $told).problem -ceq "" -and @((Read-HordeDecisionWindowToldMarks -Path $told).told.Keys).Count -eq 0) "an empty list, as the file is first made, marks nothing and is not a problem"
foreach ($bad in @(@{ text = "not json {"; says = "*could not be read as JSON*" }, @{ text = '{"schemaVersion":2,"rung":[]}'; says = "*is not version 1*" }, @{ text = '{"schemaVersion":1}'; says = "*is not version 1 with a list named rung*" }, @{ text = '[1,2]'; says = "*is not version 1*" })) {
    [System.IO.File]::WriteAllText($told, $bad.text, $utf8)
    $threw = $false; $marks = $null
    try { $marks = Read-HordeDecisionWindowToldMarks -Path $told } catch { $threw = $true }
    Check (-not $threw -and @($marks.told.Keys).Count -eq 0 -and $marks.problem -clike $bad.says) ("a file that is " + $bad.text + " marks nothing, says why, and does not throw")
}
$state = New-HordeDecisionWindowState -ToldPath $told
Check ($state.toldPath -ceq $told -and @($state.told.Keys).Count -eq 0 -and $state.says -eq 0 -and $state.saysRefused -eq 0) "the window's state starts with nothing told and nothing said"

} finally {
    $env:HORDE_HOME = $keepHome; $env:WEZFLEET_ROOT = $keepFleet
    if ((Split-Path -Leaf $work) -match '\Ahorde-decisions-window-say-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force }
}

Complete-HordeSuite -Success "what the founder types in the window is stored once, as his, or refused in the rule's own words with nothing lost"
