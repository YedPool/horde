# DO THE DECISIONS OPERATIONS WRITE EXACTLY WHAT WAS ASKED, ONCE, AND REFUSE THE REST BY NAME?
#
# decisions/Operations.ps1 through its one entry point, Invoke-HordeDecision, in this process, against
# stores this suite makes. It attacks what a caller relies on:
#   - one id, one record: a repost writes nothing and is answered from the first record; the same id
#     with another request is refused;
#   - a number is permanent: across close, reopen and change, after a record is torn, and after a
#     record is deleted from under the list;
#   - a damaged record never stops the list and is never left out of a result;
#   - what must not be written is refused before anything is written, and a refused secret is not
#     repeated anywhere in the answer;
#   - a writer that loses the race for a sequence number checks its request again against the list
#     the winner left.
# Writers in separate processes are test/test-decisions-store-race.ps1; the command line is
# test/test-decisions-cli.ps1.
#
# EVERY STORE IS A FOLDER THIS SUITE MADE under %TEMP% and removes (CONTRIBUTING 9), named in each
# call with -Root. The suite damages and deletes records on purpose, only there. The real store under
# the user profile is listed before and after, and must not have changed.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "decisions\Operations.ps1")

$defs = Get-HordeDecisionDefinitions
$script:work = Join-Path $env:TEMP ("horde-decisions-ops-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$script:n = 0
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-RealStoreListing {
    # What the real store holds, as text, WITHOUT touching it: names, sizes and write times. "" when
    # there is none. Read from the profile directly, not through HORDE_HOME, which a gate may have set.
    $real = Join-Path (Join-Path (Join-Path "$env:USERPROFILE" ".horde") "store") "decisions"
    if (-not (Test-Path -LiteralPath $real)) { return "(no store)" }
    return (@(Get-ChildItem -LiteralPath $real -Force | Sort-Object Name | ForEach-Object { $_.Name + "|" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks }) -join ";")
}
$realBefore = Get-RealStoreListing

function New-TestStore { $script:n++; return (Join-Path $script:work ("home-" + $script:n + "\store\decisions")) }
function New-Id { return [guid]::NewGuid().ToString("N") }
function New-Question {
    param([hashtable]$Over = @{})
    $q = @{ title = "Should the closing sound play when the assistant closes?"; kind = "yes-no"; whatItIs = "The app has no closing sound today."
            group = "voice"; askedBy = "orc-b"; waiting = @("orc-b") }
    foreach ($k in @($Over.Keys)) { $q[$k] = $Over[$k] }
    return $q
}
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
function Add-Q { param([string]$Store, [hashtable]$Over = @{}, [string]$Id = "") if ($Id -eq "") { $Id = New-Id }; return (Invoke-Op $Store "add" @{ id = $Id; actor = "warchief"; question = (New-Question $Over) }) }
function Get-Outcome { param($Answer) if ($Answer.state -cne "known") { return ($Answer.state + ": " + $Answer.reason) }; return "$($Answer.value.outcome)" }
function Test-Refused { param($Answer, [string]$Text) return ($Answer.state -ceq "known" -and $Answer.value.outcome -ceq "refused" -and @($Answer.value.findings | Where-Object { "$_".Contains($Text) }).Count -gt 0) }
function Get-Files { param([string]$Store) if (-not (Test-Path -LiteralPath $Store)) { return "" }; return (@(Get-ChildItem -LiteralPath $Store -File | Sort-Object Name | ForEach-Object { $_.Name }) -join ",") }
function Get-Listed { param([string]$Store, [string]$State = "all") $a = Invoke-Op $Store "list" @{ state = $State }; if ($a.state -cne "known") { return ("list " + $a.state + ": " + $a.reason) }; return (@($a.value.questions | ForEach-Object { "" + $_.number + ":" + $_.state }) -join ",") }

try {

Write-Host ""
Write-Host "--- the operations, as a caller may list them ---" -ForegroundColor Cyan
$ops = @(Get-HordeDecisionOperations)
Check ((@($ops | ForEach-Object { $_.name }) -join ",") -ceq "add,update,close,reopen,list,show") "the operations of this slice are add, update, close, reopen, list and show"
Check ((@($ops | Where-Object { $_.writes } | ForEach-Object { $_.name }) -join ",") -ceq "add,update,close,reopen") "and four of them write"
$reqDefs = @($defs.requestSchema.definitions.PSObject.Properties | ForEach-Object { $_.Name })
Check (@($ops | Where-Object { $reqDefs -cnotcontains $_.name }).Count -eq 0) "each has its request definition in schema/decision-request.v1"

Write-Host ""
Write-Host "--- a request that is not what the operation takes is refused before anything is read ---" -ForegroundColor Cyan
$s = New-TestStore
$a = Invoke-Op $s "burn" @{ }
Check ((Test-Refused $a "not an operation") -and $a.value.operation -ceq "unknown") "a name that is no operation is refused, and the operations are listed"
Check (Test-Refused (Invoke-Op $s "add" @{ actor = "warchief"; question = (New-Question) }) "has no 'id'") "an add with no id is refused"
Check (Test-Refused (Invoke-Op $s "add" @{ id = "not-an-id"; actor = "warchief"; question = (New-Question) }) "request.id does not match") "an id that is not 32 hex digits is refused"
Check (Test-Refused (Invoke-Op $s "add" @{ id = ((New-Id).ToUpperInvariant()); actor = "warchief"; question = (New-Question) }) "request.id does not match") "an id in capitals is refused: one request must have one spelling"
Check (Test-Refused (Invoke-Op $s "add" @{ id = (New-Id); actor = "warchief"; question = (New-Question); extra = 1 }) "has 'extra'") "a member the operation does not take is refused, not ignored"
Check (Test-Refused (Invoke-Op $s "close" @{ id = (New-Id); actor = "warchief"; number = "1"; outcome = "Done." }) "request.number should be integer") "a number given as text is refused"
Check (Test-Refused (Invoke-Op $s "close" @{ id = (New-Id); actor = "warchief"; number = 0; outcome = "Done." }) "below the minimum") "question 0 is refused"
Check (Test-Refused (Invoke-Op $s "add" @{ id = (New-Id); actor = "warchief"; question = (New-Question @{ colour = "red" }) }) "question has 'colour'") "a field a question does not have is refused"
Check (Test-Refused (Invoke-Op $s "add" @{ id = (New-Id); actor = "warchief"; question = (New-Question @{ needsSecret = "yes" }) }) "question.needsSecret should be boolean") "a flag given as text is refused"
Check (Test-Refused (Invoke-Op $s "add" @{ id = (New-Id); actor = "warchief"; question = (New-Question @{ waiting = "orc-b" }) }) "question.waiting should be array") "a list given as one text is refused"
Check (Test-Refused (Invoke-Op $s "add" @{ id = (New-Id); actor = "goblin"; question = (New-Question) }) "'goblin' is not a role that may change the list") "a role outside the closed list is refused by name"
Check (Test-Refused (Invoke-Op $s "add" @{ id = (New-Id); actor = "Warchief"; question = (New-Question) }) "request.actor does not match") "and so is the right role spelled another way"
Check ((Get-Files $s) -eq "" -and -not (Test-Path -LiteralPath $s)) "none of these wrote anything, or made the store folder"

Write-Host ""
Write-Host "--- add: a number, once ---" -ForegroundColor Cyan
$s = New-TestStore
$id1 = New-Id
$a = Add-Q $s @{} $id1
Check ((Get-Outcome $a) -ceq "done" -and $a.value.number -eq 1 -and $a.value.sequence -eq 1 -and $a.value.attempts -eq 1) ("the first question is added as number 1, record 1 (" + (Get-Outcome $a) + ")")
Check ($a.value.question.title -ceq "Should the closing sound play when the assistant closes?" -and $a.value.question.state -ceq "open" -and $a.value.question.wordingVersion -eq 1) "and the answer holds it, open, at wording 1"
Check ((Get-Files $s) -ceq "0000000001.json") "one record was written"
$stored = [System.IO.File]::ReadAllText((Join-Path $s "0000000001.json")) | ConvertFrom-Json
Check (@(Test-HordeDecisionEvent -Ev $stored -Definitions $defs).Count -eq 0 -and $stored.id -ceq $id1 -and $stored.kind -ceq "question-added" -and $stored.actor -ceq "warchief" -and $stored.data.number -eq 1) "the record on disk is a decision-event.v1 record with the id, the kind, the actor and the number"
Check ($stored.at -cmatch '\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+Z\z') "its time is UTC, with a Z"
$bytesBefore = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $s "0000000001.json")))

Write-Host ""
Write-Host "--- the same id again ---" -ForegroundColor Cyan
$again = Add-Q $s @{} $id1
Check ((Get-Outcome $again) -ceq "replayed" -and $again.value.number -eq 1 -and $again.value.sequence -eq 1) ("a repost of the same id and question is replayed: number 1, record 1 (" + (Get-Outcome $again) + ")")
Check ((Get-Files $s) -ceq "0000000001.json" -and [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $s "0000000001.json"))) -ceq $bytesBefore) "and nothing was written: still one record, byte for byte the same"
$reordered = [ordered]@{ waiting = @("orc-b"); askedBy = "orc-b"; group = "voice"; whatItIs = "The app has no closing sound today."; kind = "yes-no"; title = "Should the closing sound play when the assistant closes?"; recommendation = ""; needsSecret = $false; options = @() }
$again2 = Invoke-Op $s "add" ([ordered]@{ question = $reordered; actor = "warchief"; id = $id1 })
Check ((Get-Outcome $again2) -ceq "replayed") "the same question with its fields in another order, and its empty fields spelled out, is the same request"
$other = Add-Q $s @{ title = "Should a spoken line play when the assistant closes?" } $id1
Check ((Test-Refused $other "was already used for a different request") -and (Get-Files $s) -ceq "0000000001.json") "the same id with another question is refused, and nothing is written"
$asClose = Invoke-Op $s "close" @{ id = $id1; actor = "warchief"; number = 1; outcome = "Done." }
Check ((Test-Refused $asClose "was already used for a different request") -and (Get-Listed $s) -ceq "1:open") "the same id for another operation is refused too: the question stays open"
$twin = Add-Q $s
Check ((Get-Outcome $twin) -ceq "done" -and $twin.value.number -eq 2) "CONTROL: the same question under a NEW id is a new question, number 2 - it is the id that makes a repost"
Check ((Get-Outcome (Add-Q $s @{ title = "PR 1469?" } $id1)) -ceq "refused") "CONTROL: a repost is recognised before the request is judged, and a reused id is still refused"

Write-Host ""
Write-Host "--- what must not be written is refused, and nothing is written ---" -ForegroundColor Cyan
$s = New-TestStore
$a = Add-Q $s @{ title = "PR 1469?" }
Check ((Test-Refused $a "only a pull-request or issue reference") -and (Get-Files $s) -eq "") "a title that is just 'PR 1469?' is refused, and the store is still empty"
$a = Add-Q $s @{ whatItIs = ""; kind = "choice"; options = @("one") }
Check ($a.state -ceq "known" -and @($a.value.findings).Count -eq 2 -and (Test-Refused $a "must explain itself") -and (Test-Refused $a "needs at least two options")) "every rule a request breaks is reported at once, not one a time"
Check ($a.value.reason -like "*2 rule(s)*nothing was written*") "and the reason says how many, and that nothing was written"
# Secrets, assembled at run time so none sits in this file.
$token = "gh" + "p_" + ("Qr7" * 12)
$pem = "-----BEGIN RSA PRIV" + "ATE KEY-----"
$pw = "pass" + "word=" + "hunter2"
$cases = [ordered]@{
    "the title" = @{ op = "add"; req = @{ id = (New-Id); actor = "warchief"; question = (New-Question @{ title = ("Should the token " + $token + " be rotated this week?") }) }; field = "'title'" }
    "the background" = @{ op = "add"; req = @{ id = (New-Id); actor = "warchief"; question = (New-Question @{ whatItIs = ("The key is`n" + $pem + "`nMIIE...") }) }; field = "'whatItIs'" }
    "an option" = @{ op = "add"; req = @{ id = (New-Id); actor = "warchief"; question = (New-Question @{ kind = "choice"; options = @("keep it", ("use " + $pw)) }) }; field = "'options' (item 2)" }
    "a file path" = @{ op = "add"; req = @{ id = (New-Id); actor = "warchief"; question = (New-Question @{ files = @(("C:\keys\" + $token + ".txt")) }) }; field = "'files' (item 1)" }
    "a change" = @{ op = "update"; req = @{ id = (New-Id); actor = "warchief"; number = 1; changes = @{ recommendation = ("yes; " + $pw) } }; field = "'recommendation'" }
    "a closing outcome" = @{ op = "close"; req = @{ id = (New-Id); actor = "warchief"; number = 1; outcome = ("Rotated. New one: " + $token) }; field = "'outcome'" }
    "a reopening reason" = @{ op = "reopen"; req = @{ id = (New-Id); actor = "warchief"; number = 1; reason = ("see " + $pw) }; field = "'reason'" }
    "the actor" = @{ op = "add"; req = @{ id = (New-Id); actor = $token; question = (New-Question) }; field = "'actor'" }
}
$null = Add-Q $s
$filesBefore = Get-Files $s
foreach ($where in $cases.Keys) {
    $c = $cases[$where]
    $a = Invoke-Op $s $c.op $c.req
    Check ((Test-Refused $a ($c.field + " holds what looks like")) -and (Get-Files $s) -ceq $filesBefore) ("a secret in " + $where + " is refused, naming " + $c.field + ", and nothing is written")
    $whole = ConvertTo-Json -InputObject (ConvertTo-HordeAnswerRecord -Answer $a) -Depth 12 -Compress
    Check (-not $whole.Contains($token) -and -not $whole.Contains("hunter2") -and -not $whole.Contains("PRIV" + "ATE KEY")) "and the answer does not repeat it anywhere"
}
# A SECRET WRITTEN AS A FIELD'S NAME. The schema's own finding for a member it does not allow names
# the member, so before names were looked at the refusal repeated the token (measured 2026-10-06).
$a = Invoke-Op $s "add" @{ id = (New-Id); actor = "warchief"; question = (New-Question @{ $token = "x" }) }
$whole = ConvertTo-Json -InputObject (ConvertTo-HordeAnswerRecord -Answer $a) -Depth 12 -Compress
Check ((Test-Refused $a "a field name in 'question' holds what looks like an access token") -and (Get-Files $s) -ceq $filesBefore) ("a secret written as a field's name is refused as a secret, and nothing is written (" + (Get-Outcome $a) + ")")
Check (-not $whole.Contains($token)) "and the answer does not repeat it anywhere"
$a = Add-Q $s @{ needsSecret = $true; title = "Can a test account be provided for the signed-in pages?"; yesMeans = "The login is given outside this list: typed into the session, or as a file path." }
Check ((Get-Outcome $a) -ceq "done" -and $a.value.question.needsSecret -eq $true) "CONTROL: a question that NEEDS a secret, and holds none, is added and says so"
$all = (@(Get-ChildItem -LiteralPath $s -File | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n")
Check (-not $all.Contains($token) -and -not $all.Contains("hunter2")) "no record in the store holds any of the refused secrets"

Write-Host ""
Write-Host "--- update: only what is named changes ---" -ForegroundColor Cyan
$s = New-TestStore
$null = Add-Q $s
$a = Invoke-Op $s "update" @{ id = (New-Id); actor = "warchief"; number = 1; changes = @{ recommendation = "yes, a short one"; waiting = @() } }
Check ((Get-Outcome $a) -ceq "done" -and $a.value.question.recommendation -ceq "yes, a short one" -and @($a.value.question.waiting).Count -eq 0 -and $a.value.question.wordingVersion -eq 1) "a change to the recommendation and to who is waiting is made, and the wording stays 1"
Check ($a.value.question.title -ceq "Should the closing sound play when the assistant closes?" -and $a.value.question.group -ceq "voice") "the fields it did not name are as they were"
$a = Invoke-Op $s "update" @{ id = (New-Id); actor = "warchief"; number = 1; changes = @{ title = "Should a short closing sound play when the assistant closes unanswered?" } }
Check ((Get-Outcome $a) -ceq "done" -and $a.value.question.wordingVersion -eq 2 -and $a.value.number -eq 1) "a change to the title is wording 2, of the same number"
Check (Test-Refused (Invoke-Op $s "update" @{ id = (New-Id); actor = "warchief"; number = 1; changes = @{ } }) "names no field") "a change that names no field is refused"
Check (Test-Refused (Invoke-Op $s "update" @{ id = (New-Id); actor = "warchief"; number = 1; changes = @{ group = "voice" } }) "it changes nothing") "a change to the value a field already has is refused: no empty record"
Check (Test-Refused (Invoke-Op $s "update" @{ id = (New-Id); actor = "warchief"; number = 1; changes = @{ title = "PR 1469?" } }) "only a pull-request or issue reference") "a change is held to the rules too: the title cannot become 'PR 1469?'"
Check (Test-Refused (Invoke-Op $s "update" @{ id = (New-Id); actor = "warchief"; number = 1; changes = @{ kind = "choice" } }) "needs at least two options") "the question AS CHANGED is judged: it cannot become a choice with no options"
Check (Test-Refused (Invoke-Op $s "update" @{ id = (New-Id); actor = "warchief"; number = 1; changes = @{ whatItIs = "" } }) "must explain itself") "and it cannot lose its only explanation"
$a = Invoke-Op $s "update" @{ id = (New-Id); actor = "warchief"; number = 1; changes = @{ kind = "choice"; options = @("a tone", "a spoken line") } }
Check ((Get-Outcome $a) -ceq "done" -and $a.value.question.kind -ceq "choice" -and $a.value.question.wordingVersion -eq 3) "CONTROL: the same change of kind WITH its options is made, as wording 3"
Check ((Get-Files $s) -ceq "0000000001.json,0000000002.json,0000000003.json,0000000004.json") "exactly the four accepted requests are on disk: the refused ones left nothing"

Write-Host ""
Write-Host "--- close and reopen: the number stays, and is never reused ---" -ForegroundColor Cyan
$s = New-TestStore
foreach ($i in 1..3) { $null = Add-Q $s @{ title = "Is question number $i of this test asked in plain words?" } }
$a = Invoke-Op $s "close" @{ id = (New-Id); actor = "warchief"; number = 2; outcome = "Built and merged.`nShips in the next build." }
Check ((Get-Outcome $a) -ceq "done" -and $a.value.question.state -ceq "closed" -and $a.value.question.outcome -ceq "Built and merged.`nShips in the next build.") "question 2 is closed with its outcome, both lines"
Check ((Get-Listed $s "open") -ceq "1:open,3:open" -and (Get-Listed $s "closed") -ceq "2:closed" -and (Get-Listed $s "all") -ceq "1:open,2:closed,3:open") "the open list shows 1 and 3 - a gap, not a renumbering - and the closed list shows 2"
$a = Add-Q $s @{ title = "Is the question added after a close given a new number?" }
Check ((Get-Outcome $a) -ceq "done" -and $a.value.number -eq 4) "a question added after 2 closed is number 4: the closed number is not reused"
$late = Invoke-Op $s "update" @{ id = (New-Id); actor = "warchief"; number = 2; changes = @{ recommendation = "too late" } }
Check (Test-Refused $late "only an open question can be changed") "a change to the closed question is refused, and told to reopen it first"
Check ($late.state -ceq "known" -and @($late.value.ignored).Count -eq 0 -and @($late.value.unreadable).Count -eq 0) "and the refusal does not list the record it did not write among the store's records"
Check (Test-Refused (Invoke-Op $s "close" @{ id = (New-Id); actor = "warchief"; number = 2; outcome = "Again." }) "already closed") "closing it again is refused"
Check (Test-Refused (Invoke-Op $s "reopen" @{ id = (New-Id); actor = "warchief"; number = 1; reason = "why not" }) "only a closed question can be reopened") "reopening an open question is refused"
Check (Test-Refused (Invoke-Op $s "close" @{ id = (New-Id); actor = "warchief"; number = 1; outcome = "   " }) "'outcome' is blank") "a close with a blank outcome is refused"
Check (Test-Refused (Invoke-Op $s "reopen" @{ id = (New-Id); actor = "warchief"; number = 2; reason = "line one`nline two" }) "'reason' must be one line") "a reopening reason of two lines is refused"
$a = Invoke-Op $s "reopen" @{ id = (New-Id); actor = "warchief"; number = 2; reason = "the fix did not hold" }
Check ((Get-Outcome $a) -ceq "done" -and $a.value.number -eq 2 -and $a.value.question.state -ceq "open" -and $a.value.question.outcome -eq "" -and $a.value.question.reopenReason -ceq "the fix did not hold") "question 2 is reopened as question 2, open, with the reason"
Check ((Get-Listed $s "all") -ceq "1:open,2:open,3:open,4:open") "and every question still has the number it was given"
$a = Add-Q $s @{ title = "Is the question added after a reopen given a new number?" }
Check ($a.state -ceq "known" -and $a.value.number -eq 5) "the next question is 5"
$show = Invoke-Op $s "show" @{ number = 2 }
Check ((Get-Outcome $show) -ceq "done" -and (@($show.value.question.history | ForEach-Object { $_.note }) -join ",") -ceq "added,closed,reopened" -and $show.value.question.title -ceq "Is question number 2 of this test asked in plain words?") "show 2 gives the same question with its whole history"
Check ((Get-Files $s) -ceq ((1..7 | ForEach-Object { $_.ToString("D10") + ".json" }) -join ",")) "CONTROL: seven records for seven accepted requests, and none for the five refused"

Write-Host ""
Write-Host "--- a number that was never given ---" -ForegroundColor Cyan
$filesBefore = Get-Files $s
foreach ($try in @(@{ op = "show"; req = @{ number = 99 } }, @{ op = "update"; req = @{ id = (New-Id); actor = "warchief"; number = 99; changes = @{ group = "x" } } },
                   @{ op = "close"; req = @{ id = (New-Id); actor = "warchief"; number = 99; outcome = "Done." } }, @{ op = "reopen"; req = @{ id = (New-Id); actor = "warchief"; number = 99; reason = "why" } })) {
    $a = Invoke-Op $s $try.op $try.req
    Check ($a.state -ceq "absent" -and $a.reason -like "*there is no question 99; the highest number given is 5*") ($try.op + " 99 is absent - the store was read and there is no such question - not refused and not unknown")
}
Check ((Invoke-Op $s "show" @{ number = 3000000000 }).state -ceq "absent") "a number beyond any that could be given is absent too, not an error"
# 1e30 passes "type": "integer" and overflowed the cast to a 64-bit number: show and close THREW
# instead of answering (measured 2026-10-06). An operation always answers.
$a = Invoke-Op $s "show" @{ number = 1e30 }
Check ($a.state -ceq "absent" -and $a.reason -like "*no question has a number above 999999999*") ("show 1e30 is absent, with the largest number a question can have (" + $a.state + ": " + $a.reason + ")")
$a = Invoke-Op $s "close" @{ id = (New-Id); actor = "warchief"; number = 1e30; outcome = "Done." }
Check ($a.state -ceq "absent") ("close 1e30 is absent too (" + $a.state + ": " + $a.reason + ")")
Check ((Get-Files $s) -ceq $filesBefore) "and none of them wrote anything"

Write-Host ""
Write-Host "--- list: which questions, and how many of each ---" -ForegroundColor Cyan
$a = Invoke-Op $s "list" $null
Check ((Get-Outcome $a) -ceq "done" -and @($a.value.questions).Count -eq 5 -and $a.value.counts.open -eq 5 -and $a.value.counts.closed -eq 0) "with no request at all, list gives the open questions and the counts"
$null = Invoke-Op $s "close" @{ id = (New-Id); actor = "warchief"; number = 4; outcome = "Done." }
$a = Invoke-Op $s "list" @{ }
Check ((@($a.value.questions | ForEach-Object { $_.number }) -join ",") -ceq "1,2,3,5" -and $a.value.counts.open -eq 4 -and $a.value.counts.closed -eq 1) "the default is the open ones, in number order, and the counts cover every state whatever is shown"
Check (Test-Refused (Invoke-Op $s "list" @{ state = "answered" }) "is not a state a question can be in") "a state that does not exist yet is refused by name, not answered with an empty list"
$empty = New-TestStore
$a = Invoke-Op $empty "list" @{ state = "all" }
Check ((Get-Outcome $a) -ceq "done" -and @($a.value.questions).Count -eq 0 -and $a.value.counts.open -eq 0 -and -not (Test-Path -LiteralPath $empty)) "a store nobody has added to lists nothing, and listing does not create it"

Write-Host ""
Write-Host "--- text in any alphabet, and long text, comes back exactly ---" -ForegroundColor Cyan
$s = New-TestStore
# Hebrew written as escapes (CONTRIBUTING 13), with a right-to-left mark, a quote, a backslash, angle
# brackets and an ampersand: the characters an encoder is most likely to change.
$hebrew = "" + [char]0x05D4 + [char]0x05D0 + [char]0x05DD + " " + [char]0x05DC + [char]0x05D4 + [char]0x05E9 + [char]0x05DE + [char]0x05D9 + [char]0x05E2 + " " + [char]0x05E6 + [char]0x05DC + [char]0x05D9 + [char]0x05DC + [char]0x200F + " " + [char]0x05E1 + [char]0x05D2 + [char]0x05D9 + [char]0x05E8 + [char]0x05D4 + "?"
$tricky = $hebrew + ' "quoted" \back\slash <tag> & ' + "'apostrophe' " + [char]0x00E9 + [char]0x4E2D + [char]0xD83D + [char]0xDE00
$long = ("word " * 19999) + "end!!"
Check ($long.Length -eq 100000) "CONTROL: the long text is 100,000 characters"
$a = Add-Q $s @{ title = $hebrew; whatItIs = $long; yesMeans = $tricky; group = $hebrew }
Check ((Get-Outcome $a) -ceq "done") ("a question in Hebrew with a 100,000-character background is added (" + (Get-Outcome $a) + ")")
$show = Invoke-Op $s "show" @{ number = 1 }
Check ([string]::Equals($show.value.question.title, $hebrew, [System.StringComparison]::Ordinal) -and [string]::Equals($show.value.question.group, $hebrew, [System.StringComparison]::Ordinal)) "the Hebrew title and group come back character for character"
Check ([string]::Equals($show.value.question.yesMeans, $tricky, [System.StringComparison]::Ordinal)) "so do quotes, backslashes, angle brackets, an ampersand, an accent, a Chinese character and an emoji"
Check ($show.value.question.whatItIs.Length -eq 100000 -and [string]::Equals($show.value.question.whatItIs, $long, [System.StringComparison]::Ordinal)) "and all 100,000 characters, to the last"
$listed = Invoke-Op $s "list" @{ }
Check ([string]::Equals($listed.value.questions[0].title, $hebrew, [System.StringComparison]::Ordinal)) "list gives the same title"
$raw = [System.IO.File]::ReadAllBytes((Join-Path $s "0000000001.json"))
$needle = $utf8.GetBytes($hebrew.Substring(0, 3))
$hit = $false
for ($i = 0; $i -le $raw.Length - $needle.Length -and -not $hit; $i++) { $same = $true; for ($j = 0; $j -lt $needle.Length; $j++) { if ($raw[$i + $j] -ne $needle[$j]) { $same = $false; break } }; if ($same) { $hit = $true } }
Check ($hit -and $raw[0] -eq 0x7B) "on disk the record is UTF-8: the Hebrew letters are there as their own bytes, and the file starts with { and no byte-order mark"
$a = Add-Q $s @{ whatItIs = ("word " * 100000) + "!" }
Check ((Test-Refused $a "'whatItIs' is 500001 characters long") -and (Get-Files $s) -ceq "0000000001.json") "a 500,001-character background is refused whole, with its length; it is not stored cut"

Write-Host ""
Write-Host "--- a torn record: the list still loads, and says which record ---" -ForegroundColor Cyan
$s = New-TestStore
foreach ($i in 1..2) { $null = Add-Q $s @{ title = "Is question number $i of this test asked in plain words?" } }
[System.IO.File]::WriteAllText((Join-Path $s "0000000003.json"), '{"schemaVersion":1,"sequence":3,"id":"', $utf8)
$a = Invoke-Op $s "list" @{ state = "all" }
Check ((Get-Outcome $a) -ceq "done" -and (@($a.value.questions | ForEach-Object { $_.number }) -join ",") -ceq "1,2") "with record 3 cut off mid-write, list still gives questions 1 and 2"
Check (@($a.value.unreadable).Count -eq 1 -and $a.value.unreadable[0].sequence -eq 3 -and $a.value.unreadable[0].file -ceq "0000000003.json" -and $a.value.unreadable[0].reason -like "*not complete JSON*") "and its result names record 3, its file and why it cannot be read"
$a = Invoke-Op $s "show" @{ number = 1 }
Check ((Get-Outcome $a) -ceq "done" -and @($a.value.unreadable).Count -eq 1) "show of a readable question works, and carries the same warning"
$a = Invoke-Op $s "show" @{ number = 3 }
Check ($a.state -ceq "unknown" -and $a.reason -like "*question 3 cannot be read*record 3 (0000000003.json)*") "show 3 is UNKNOWN - the torn record may have been question 3 - and names the record; it is not 'no such question'"
$a = Add-Q $s @{ title = "Is the question added after a torn record numbered safely?" }
Check ((Get-Outcome $a) -ceq "done" -and $a.value.number -eq 4 -and $a.value.sequence -eq 4) "a question added now is number 4, record 4: number 3 is left unused, because the torn record may have been question 3"
Check (@($a.value.unreadable).Count -eq 1) "and the write's own result still names the torn record"
$a = Invoke-Op $s "close" @{ id = (New-Id); actor = "warchief"; number = 1; outcome = "Done." }
Check ((Get-Outcome $a) -ceq "done" -and (Get-Listed $s) -ceq "1:closed,2:open,4:open") "CONTROL: the list goes on working around it"
Check ([System.IO.File]::ReadAllText((Join-Path $s "0000000003.json")) -ceq '{"schemaVersion":1,"sequence":3,"id":"') "the torn record itself is left exactly as it was found: never repaired, never overwritten"

Write-Host ""
Write-Host "--- a record of another schema, and one of an unknown kind ---" -ForegroundColor Cyan
$s = New-TestStore
$null = Add-Q $s
$good = [System.IO.File]::ReadAllText((Join-Path $s "0000000001.json"))
$v2 = $good.Replace('"schemaVersion":1,"sequence":1', '"schemaVersion":2,"sequence":2').Replace('"number":1', '"number":2')
Check ($v2 -cne $good -and $v2.Contains('"schemaVersion":2')) "CONTROL: the planted record differs from a real one only in its version, its place and its number"
[System.IO.File]::WriteAllText((Join-Path $s "0000000002.json"), $v2, $utf8)
[System.IO.File]::WriteAllText((Join-Path $s "0000000003.json"), '{"schemaVersion":1,"sequence":3,"id":"' + ("c" * 32) + '","kind":"answer-recorded","at":"2026-10-06T12:00:00Z","actor":"warchief","requestHash":"' + ("0" * 64) + '","data":{"number":1,"words":"yes"}}', $utf8)
$a = Invoke-Op $s "list" @{ state = "all" }
Check ((Get-Outcome $a) -ceq "done" -and (@($a.value.questions | ForEach-Object { $_.number }) -join ",") -ceq "1" -and @($a.value.unreadable).Count -eq 2) "the list loads with question 1, and both records are reported"
Check ($a.value.unreadable[0].sequence -eq 2 -and $a.value.unreadable[0].reason -like "*not a decision-event.v1 record*schemaVersion*") "the version 2 record is not read as version 1, and the reason names the field"
Check ($a.value.unreadable[1].sequence -eq 3 -and $a.value.unreadable[1].reason -like "*'answer-recorded' is not one this version of Horde knows*") "the unknown kind is named, not guessed at"

Write-Host ""
Write-Host "--- a stray file far ahead in the store: named, not believed, and no number moves ---" -ForegroundColor Cyan
# Measured 2026-10-06, before the store's gap limit: 0000002000.json beside two records made a list take
# 11.6 s with 1998 unreadable records and numbered the next question 2001; 9999999999.json hung it.
$s = New-TestStore
foreach ($i in 1..5) { $null = Add-Q $s @{ title = "Is question number $i of this test asked in plain words?" } }
[System.IO.File]::WriteAllText((Join-Path $s "0000002000.json"), '{"stray":true}', $utf8)
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$a = Invoke-Op $s "list" @{ state = "all" }
$sw.Stop()
$strayNames = ""
if ($a.state -ceq "known" -and $null -ne $a.value.PSObject.Properties["strays"]) { $strayNames = (@($a.value.strays | ForEach-Object { $_.file }) -join ",") }
Check ((Get-Outcome $a) -ceq "done" -and (@($a.value.questions | ForEach-Object { $_.number }) -join ",") -ceq "1,2,3,4,5" -and @($a.value.unreadable).Count -eq 0) ("with 0000002000.json in the store, list gives questions 1 to 5 and no unreadable record (" + (Get-Outcome $a) + ", " + @($a.value.unreadable).Count + " unreadable)")
Check ($strayNames -ceq "0000002000.json" -and "$($a.value.strays[0].reason)" -like "*too far to be a record*") ("and names the file as a stray, with the reason (" + $strayNames + ")")
Check ($sw.ElapsedMilliseconds -lt 8000) ("in the time a list of five takes, not the time of walking to record 2000 (" + $sw.ElapsedMilliseconds + " ms)")
[System.IO.File]::WriteAllText((Join-Path $s "9999999999.json"), '{"stray":true}', $utf8)
$a = Add-Q $s @{ title = "Is the question added beside the strays given number six?" }
Check ((Get-Outcome $a) -ceq "done" -and $a.value.number -eq 6 -and $a.value.sequence -eq 6) ("a question added now is number 6, record 6: the strays moved nothing (" + (Get-Outcome $a) + ")")
Check ((@($a.value.strays | ForEach-Object { $_.file }) -join ",") -ceq "0000002000.json,9999999999.json") "and the write's own result names both strays"
Check ((Get-Listed $s) -ceq "1:open,2:open,3:open,4:open,5:open,6:open") "CONTROL: the list is 1 to 6"
# A GAP INSIDE THE LIMIT is still believed, as ONE finding, and still costs its numbers.
$s = New-TestStore
foreach ($i in 1..2) { $null = Add-Q $s }
$kept = [System.IO.File]::ReadAllText((Join-Path $s "0000000002.json"))
[System.IO.File]::WriteAllText((Join-Path $s "0000000006.json"), $kept.Replace('"sequence":2', '"sequence":6').Replace('"number":2', '"number":3'), $utf8)
$a = Invoke-Op $s "list" @{ state = "all" }
Check ((Get-Outcome $a) -ceq "done" -and @($a.value.unreadable).Count -eq 1 -and $a.value.unreadable[0].sequence -eq 3 -and $a.value.unreadable[0].reason -like "*records 3 to 5 (3 of them)*") ("three records missing in a row are ONE finding, saying from where to where (" + @($a.value.unreadable).Count + " finding(s))")
Check ((@($a.value.questions | ForEach-Object { $_.number }) -join ",") -ceq "1,2,3") "and the record after the gap is read: the list is 1, 2, 3"

Write-Host ""
Write-Host "--- a record holding a number no question can have: every operation still answers ---" -ForegroundColor Cyan
$s = New-TestStore
$null = Add-Q $s
$good = [System.IO.File]::ReadAllText((Join-Path $s "0000000001.json"))
$huge = $good.Replace('"sequence":1', '"sequence":2').Replace('"number":1', '"number":99999999999')
Check ($huge -cne $good -and $huge.Contains('"number":99999999999')) "CONTROL: the planted record differs from a real one only in its place and its number"
[System.IO.File]::WriteAllText((Join-Path $s "0000000002.json"), $huge, $utf8)
$a = Invoke-Op $s "list" @{ state = "all" }
Check ((Get-Outcome $a) -ceq "done" -and (@($a.value.questions | ForEach-Object { $_.number }) -join ",") -ceq "1" -and @($a.value.unreadable).Count -eq 1 -and $a.value.unreadable[0].sequence -eq 2) ("list loads question 1 and names record 2 (" + (Get-Outcome $a) + ")")
$a = Invoke-Op $s "show" @{ number = 1 }
Check ((Get-Outcome $a) -ceq "done") ("show 1 answers (" + (Get-Outcome $a) + ")")
$a = Add-Q $s
Check ((Get-Outcome $a) -ceq "done" -and $a.value.number -eq 3 -and $a.value.sequence -eq 3) ("a question added now is number 3, record 3: one number left unused for the record that cannot be read (" + (Get-Outcome $a) + ")")

Write-Host ""
Write-Host "--- a record deleted from under the list: nothing is renumbered ---" -ForegroundColor Cyan
$s = New-TestStore
foreach ($i in 1..3) { $null = Add-Q $s @{ title = "Is question number $i of this test asked in plain words?" } }
Check ((Get-Listed $s) -ceq "1:open,2:open,3:open") "CONTROL: three questions, 1 to 3"
# This suite's own record, in this suite's own store.
Remove-Item -LiteralPath (Join-Path $s "0000000002.json") -Force
$a = Invoke-Op $s "list" @{ state = "all" }
Check ((Get-Outcome $a) -ceq "done" -and (@($a.value.questions | ForEach-Object { "" + $_.number + "=" + $_.title.Substring(19, 1) }) -join ",") -ceq "1=1,3=3") "with question 2's record gone, question 3 is still question 3 - it did not slide down to 2"
Check (@($a.value.unreadable).Count -eq 1 -and $a.value.unreadable[0].sequence -eq 2 -and $a.value.unreadable[0].reason -like "*deleted*") "and the missing record is named"
Check ((Invoke-Op $s "show" @{ number = 2 }).state -ceq "unknown") "question 2 is unknown, not absent"
$a = Add-Q $s @{ title = "Is the question added after a deletion given a fresh number?" }
Check ((Get-Outcome $a) -ceq "done" -and $a.value.number -eq 4 -and $a.value.sequence -eq 4) "the next question is 4: neither the deleted number nor an existing one is given again"
Check ((Get-Listed $s) -ceq "1:open,3:open,4:open") "CONTROL: the list is 1, 3, 4"

Write-Host ""
Write-Host "--- a writer that loses a sequence number checks its request again ---" -ForegroundColor Cyan
# The store's create is wrapped for this one section: just before the request under test would take its
# sequence number, another request is written through the real create and takes it. The request under
# test must then be judged against the list that winner left - not written on the strength of the
# list it read before.
$s = New-TestStore
foreach ($i in 1..2) { $null = Add-Q $s @{ title = "Is question number $i of this test asked in plain words?" } }
$realAdd = (Get-Command -Name Add-HordeDecisionRecord -CommandType Function).ScriptBlock
$script:planted = 0
$script:plantText = ""
function Add-HordeDecisionRecord {
    param([string]$Root, [long]$Sequence, [string]$Text)
    if ($script:planted -eq 0 -and $script:plantText -ne "") {
        $script:planted = 1
        $null = & $realAdd -Root $Root -Sequence $Sequence -Text $script:plantText
    }
    return (& $realAdd -Root $Root -Sequence $Sequence -Text $Text)
}
try {
    # The winner: a close of question 1, built as a real record 3.
    $script:plantText = '{"schemaVersion":1,"sequence":3,"id":"' + ("d" * 32) + '","kind":"question-closed","at":"2026-10-06T12:00:00.0000000Z","actor":"warchief","requestHash":"' + ("0" * 64) + '","data":{"number":1,"outcome":"Closed by the other writer."}}'
    $a = Invoke-Op $s "close" @{ id = (New-Id); actor = "warchief"; number = 1; outcome = "Closed by this writer." }
    Check ($script:planted -eq 1) "CONTROL: the other writer's record was written first, into the sequence number this request wanted"
    Check (Test-Refused $a "already closed") ("the request that lost is judged again and refused: question 1 is already closed (" + (Get-Outcome $a) + ")")
    Check ((Get-Files $s) -ceq "0000000001.json,0000000002.json,0000000003.json") "and it wrote nothing: one close is on disk, not two"
    # A loser whose request still holds takes the next number, and says it took two tries.
    $script:planted = 0
    $script:plantText = '{"schemaVersion":1,"sequence":4,"id":"' + ("e" * 32) + '","kind":"question-closed","at":"2026-10-06T12:00:01.0000000Z","actor":"warchief","requestHash":"' + ("0" * 64) + '","data":{"number":2,"outcome":"Closed by the other writer."}}'
    $a = Add-Q $s @{ title = "Is the question of the writer that lost still added once?" }
    Check ((Get-Outcome $a) -ceq "done" -and $a.value.attempts -eq 2 -and $a.value.sequence -eq 5 -and $a.value.number -eq 3) ("a request that still holds is written to the NEXT sequence number, on its second try (" + (Get-Outcome $a) + ")")
    Check ((Get-Listed $s) -ceq "1:closed,2:closed,3:open") "both writers' records are in the list: no record was lost and none was overwritten"
} finally {
    Remove-Item -LiteralPath function:Add-HordeDecisionRecord
    . (Join-Path $root "decisions\Store.ps1")
}
Check ((Add-HordeDecisionRecord -Root $s -Sequence 1 -Text "{}") -ceq "exists") "CONTROL: the real create is back in place for the rest of the suite"

Write-Host ""
Write-Host "--- a write does not wait for ever on a record another process holds open ---" -ForegroundColor Cyan
# Measured 2026-10-06, before the wait had a limit of its own: with record 1 held open, an add was
# still waiting after 40 s, and the code allowed it 400. Here this process holds the record without
# sharing, as a stuck program would, and the add must come back by itself, saying which record.
$s = New-TestStore
$null = Add-Q $s
$held = New-Object System.IO.FileStream((Join-Path $s "0000000001.json"), [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try { $a = Add-Q $s } finally { $held.Dispose() }
$sw.Stop()
Check ($a.state -ceq "unknown" -and $a.reason -like "*nothing was written*another process holds record 1 open*") ("an add while record 1 is held open is unknown, and names the record (" + $a.state + ": " + $a.reason + ")")
Check ($sw.Elapsed.TotalSeconds -ge 8 -and $sw.Elapsed.TotalSeconds -le 25) ("it waited about ten seconds for the holder, and no longer (" + [int]$sw.Elapsed.TotalSeconds + " s)")
Check ((Get-Files $s) -ceq "0000000001.json") "and nothing was written"
$a = Add-Q $s
Check ((Get-Outcome $a) -ceq "done" -and $a.value.number -eq 2) "CONTROL: once the record is let go, the same add is made"

Write-Host ""
Write-Host "--- a store that cannot be written is unknown, not refused ---" -ForegroundColor Cyan
$blocked = Join-Path $script:work "a-file-where-the-store-should-be"
[System.IO.File]::WriteAllText($blocked, "not a folder", $utf8)
$a = Add-Q $blocked
Check ($a.state -ceq "unknown" -and $a.reason -like "*nothing was written*is a file, not a folder*") ("when a file is where the store folder should be, an add is unknown, with the reason (" + $a.state + ": " + $a.reason + ")")
$a = Invoke-Op $blocked "list" @{}
Check ($a.state -ceq "unknown" -and $a.reason -like "*is a file, not a folder*") ("and so is a list: it is not answered as a list with no questions (" + (Get-Outcome $a) + ")")
Check ([System.IO.File]::ReadAllText($blocked) -ceq "not a folder") "and what was there is untouched"
# THE WRITE ITSELF FAILING, after a read that worked. A file in the store's place is now refused at the
# read, so it no longer reaches the write's own failure; a FOLDER where the next record's file must go
# does: the read does not see it (it is not a file), and the create is denied.
$s = New-TestStore
$null = Add-Q $s
New-Item -ItemType Directory -Path (Join-Path $s "0000000002.json") | Out-Null
$a = Add-Q $s
Check ($a.state -ceq "unknown" -and $a.reason -like "*record 2 could not be written, so nothing changed*") ("when the record itself cannot be created the answer is unknown, with the record's number - a failure to write is not a refusal (" + (Get-Outcome $a) + ")")
Check ((Get-Files $s) -ceq "0000000001.json" -and (Get-Listed $s) -ceq "1:open") "and the list is as it was: one record, question 1"

Write-Host ""
Write-Host "--- without -Root the store is Horde's own, under HORDE_HOME, and nowhere else ---" -ForegroundColor Cyan
$keepHome = $env:HORDE_HOME
try {
    $fakeHome = Join-Path $script:work "fake-home"
    $env:HORDE_HOME = $fakeHome
    Check ((Get-HordeDecisionStoreRoot) -ceq (Join-Path $fakeHome "store\decisions")) "the store is <HordeHome>\store\decisions"
    $a = $null
    try { $a = Invoke-HordeDecision -Operation "add" -Request @{ id = (New-Id); actor = "warchief"; question = (New-Question) } } catch { $a = New-HordeUnknown -Reason ("THREW: " + $_.Exception.Message) }
    Check ((Get-Outcome $a) -ceq "done" -and (Test-Path -LiteralPath (Join-Path $fakeHome "store\decisions\0000000001.json"))) "an add with no -Root writes under the HORDE_HOME this suite set"
    $env:HORDE_HOME = "relative\home"
    $a = $null
    try { $a = Invoke-HordeDecision -Operation "list" -Request @{ } } catch { $a = New-HordeUnknown -Reason ("THREW: " + $_.Exception.Message) }
    Check ($a.state -ceq "unknown" -and $a.reason -like "*HORDE_HOME must be an absolute path*" -and $a.reason -notlike "THREW*") "a relative HORDE_HOME is unknown with core/Home's own reason; nothing is guessed"
} finally { $env:HORDE_HOME = $keepHome }

} finally {
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-decisions-ops-test-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the suite's temp folder is removed"
Check ((Get-RealStoreListing) -ceq $realBefore) ("the real store under the user profile is exactly as it was before the suite (" + $(if ($realBefore.Length -gt 60) { $realBefore.Substring(0, 60) + "..." } else { $realBefore }) + ")")

Complete-HordeSuite -Success "every operation writes one record for one accepted request, keeps every number, reports every damaged record, and refuses the rest by name"
