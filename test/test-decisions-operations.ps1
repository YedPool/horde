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
function Get-NotUnderstood { param($Answer) if ($Answer.state -cne "known") { return ($Answer.state + ": " + $Answer.reason) }; if ($null -eq $Answer.value.PSObject.Properties["notUnderstood"]) { return "(the result names no such thing)" }; return (@($Answer.value.notUnderstood | ForEach-Object { "" + $_.kind + " x" + $_.count + " " + $_.first + "-" + $_.last }) -join "; ") }
function Get-Outcome { param($Answer) if ($Answer.state -cne "known") { return ($Answer.state + ": " + $Answer.reason) }; return "$($Answer.value.outcome)" }
function Test-Refused { param($Answer, [string]$Text) return ($Answer.state -ceq "known" -and $Answer.value.outcome -ceq "refused" -and @($Answer.value.findings | Where-Object { "$_".Contains($Text) }).Count -gt 0) }
function Get-Files { param([string]$Store) if (-not (Test-Path -LiteralPath $Store)) { return "" }; return (@(Get-ChildItem -LiteralPath $Store -File | Sort-Object Name | ForEach-Object { $_.Name }) -join ",") }
function Add-Stored {
    # A record put into a store of this suite AS A FILE, the way an earlier version of Horde left it
    # there: for what the operations no longer write and must still read (a reopening). Returns the
    # record's sequence number. -Hash is the request hash it carries; the zeros of a record whose
    # request nobody will send again, unless a check hands in the real one.
    param([string]$Store, [string]$Kind, $Data, [string]$Id = "", [string]$Hash = "")
    if ($Id -eq "") { $Id = New-Id }
    if ($Hash -eq "") { $Hash = "0" * 64 }
    $seq = @(Get-ChildItem -LiteralPath $Store -File -Filter "*.json").Count + 1
    $envelope = [ordered]@{ schemaVersion = 1; sequence = $seq; id = $Id; kind = $Kind; at = "2026-10-06T12:00:00.0000000Z"; actor = "warchief"; requestHash = $Hash; data = $Data }
    [System.IO.File]::WriteAllText((Join-Path $Store ($seq.ToString("D10") + ".json")), (ConvertTo-Json -InputObject $envelope -Compress -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
    return $seq
}
function Get-Listed { param([string]$Store, [string]$State = "all") $a = Invoke-Op $Store "list" @{ state = $State }; if ($a.state -cne "known") { return ("list " + $a.state + ": " + $a.reason) }; return (@($a.value.questions | ForEach-Object { "" + $_.number + ":" + $_.state }) -join ",") }

try {

Write-Host ""
Write-Host "--- the rules and the store read ONE definition of how large a record's number can be ---" -ForegroundColor Cyan
# decisions/Format.ps1 holds the width a sequence number is written in, as a constant, and the largest
# number that width holds is worked out from it. The store names files by it and the rules refuse a
# record beyond it. Before, each wrote its own number down, and this check held the two together.
function Get-NumbersWritten {
    # Every whole number at or above a hundred million written as a constant in a file of the module:
    # the largest sequence number is ten digits, and must be written in none of them.
    param([string]$Relative)
    $tokens = $null; $errors = $null
    $tree = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $Relative), [ref]$tokens, [ref]$errors)
    return @($tree.FindAll({ param($node) $node -is [System.Management.Automation.Language.ConstantExpressionAst] -and ($node.Value -is [int] -or $node.Value -is [long] -or $node.Value -is [double] -or $node.Value -is [decimal]) -and [double]$node.Value -ge 100000000 }, $true) | ForEach-Object { "$($_.Extent.Text)" })
}
Check ((Get-HordeDecisionSequenceDigits) -eq 10 -and (Get-HordeDecisionMaxSequence) -eq 9999999999 -and (Get-HordeDecisionMaxSequence) -is [long]) ("a sequence number is written in ten digits, and the largest is the largest ten digits hold (" + (Get-HordeDecisionMaxSequence) + ")")
Check ((@(Get-NumbersWritten "decisions\Rules.ps1") -join ",") -ceq "999999999" -and @(Get-NumbersWritten "decisions\Store.ps1").Count -eq 0 -and @(Get-NumbersWritten "decisions\Format.ps1").Count -eq 0) ("the largest sequence number is written in none of the three files: the rules write only the largest QUESTION number, the store and the format none (rules: " + (@(Get-NumbersWritten "decisions\Rules.ps1") -join ",") + ")")
Check ((Get-HordeDecisionRecordName -Sequence (Get-HordeDecisionMaxSequence)) -ceq "9999999999.json" -and (Throws { Get-HordeDecisionRecordName -Sequence ((Get-HordeDecisionMaxSequence) + 1) } "1 to 9999999999")) "the store names the largest record and refuses the one after it"
$tooFar = '{"schemaVersion":1,"sequence":10000000000,"id":"' + ("a" * 32) + '","kind":"question-closed","at":"2026-10-06T12:00:00Z","actor":"warchief","requestHash":"' + ("0" * 64) + '","data":{"number":1,"outcome":"x"}}'
$atEnd = $tooFar.Replace('"sequence":10000000000', '"sequence":9999999999')
Check ("$(@(Test-HordeDecisionEvent -Ev ($tooFar | ConvertFrom-Json) -Definitions $defs)[0])" -like "*sequence number is beyond 9999999999*" -and @(Test-HordeDecisionEvent -Ev ($atEnd | ConvertFrom-Json) -Definitions $defs).Count -eq 0) "and the rules refuse a record claiming the number after the largest, and accept the largest: the same limit, read from the same place"
Check (Throws { Get-HordeDecisionSetting -Name "decisions.store.sequenceDigits" } "is not a setting") "the width is not a setting: nothing can ask the settings for it"

Write-Host ""
Write-Host "--- the operations, as a caller may list them ---" -ForegroundColor Cyan
$ops = @(Get-HordeDecisionOperations)
Check ((@($ops | ForEach-Object { $_.name }) -join ",") -ceq "add,update,close,reopen,rank,say,mark-read,list,show,kinds,inbox") "the operations are add, update, close, reopen and rank, say and mark-read, and list, show, kinds and inbox"
Check ((@($ops | Where-Object { $_.writes } | ForEach-Object { $_.name }) -join ",") -ceq "add,update,close,reopen,rank,say,mark-read") "and seven of them write (the conversation's two are test/test-decisions-threads.ps1's)"
$reqDefs = @($defs.requestSchema.definitions.PSObject.Properties | ForEach-Object { $_.Name })
Check (@($ops | Where-Object { $reqDefs -cnotcontains $_.name }).Count -eq 0) "each has its request definition in schema/decision-request.v1"

Write-Host ""
Write-Host "--- kinds: the table of question kinds, from the operations ---" -ForegroundColor Cyan
# A caller that cannot read this checkout's files - one across a link - must still be able to say what
# a kind means. So the table is an answer of the one API, not a file every caller opens.
$a = Invoke-Op (New-TestStore) "kinds" @{}
$kindNames = ""
if ($a.state -ceq "known" -and $null -ne $a.value.PSObject.Properties["kinds"]) { $kindNames = (@($a.value.kinds.PSObject.Properties | ForEach-Object { $_.Name }) -join ",") }
Check ((Get-Outcome $a) -ceq "done" -and $kindNames -ceq "yes-no,choice,value,parts,do-then-say") ("kinds answers with the five kinds of question, in the table's order (" + (Get-Outcome $a) + ": " + $kindNames + ")")
Check ($kindNames -ne "" -and "$($a.value.kinds.choice.label)" -ceq "$($defs.kinds.choice.label)" -and "$($a.value.kinds.choice.means)" -ceq "$($defs.kinds.choice.means)" -and "$($a.value.kinds.choice.list)" -ceq "options" -and "$($a.value.kinds.'yes-no'.list)" -ceq "") "each with its label, what it means and the list it needs, as the one table has them"
$whole = ConvertTo-Json -InputObject (ConvertTo-HordeAnswerRecord -Answer $a) -Depth 12 -Compress
Check ($whole.Contains('"kinds":{"yes-no":{')) "and it is plain data: written as JSON it is the table"
$fileInPlace = Join-Path $script:work "a-file-where-a-store-would-be-for-kinds"
[System.IO.File]::WriteAllText($fileInPlace, "not a folder", $utf8)
Check ((Get-Outcome (Invoke-Op $fileInPlace "kinds" @{})) -ceq "done") "it needs no store: it answers where a list could not"
Check ((Get-Outcome (Invoke-Op (New-TestStore) "kinds" @{ state = "open" })) -ceq "refused") "CONTROL: it takes nothing, and a member it does not take is refused"

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
Check (Test-Refused (Invoke-Op $s "add" @{ id = (New-Id); actor = "warg"; question = (New-Question) }) "'warg' is not a role that may change the list") "a role outside the closed list is refused by name"
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
Write-Host "--- close: the number stays, and is never reused; and nothing is reopened any more ---" -ForegroundColor Cyan
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
Check (Test-Refused (Invoke-Op $s "reopen" @{ id = (New-Id); actor = "warchief"; number = 1; reason = "why not" }) "nothing is reopened any more") "reopening an open question is refused"
Check (Test-Refused (Invoke-Op $s "close" @{ id = (New-Id); actor = "warchief"; number = 1; outcome = "   " }) "'outcome' is blank") "a close with a blank outcome is refused"
# A QUESTION IS NEVER PUT BACK IN FRONT OF THE FOUNDER (2026-10-12): the closed one is not reopened
# either. The refusal is a fact with a reason - known, refused - and the reason says what to do instead,
# with the question's own number in it.
$filesWere = Get-Files $s
$a = Invoke-Op $s "reopen" @{ id = (New-Id); actor = "warchief"; number = 2; reason = "the fix did not hold" }
Check ((Test-Refused $a "never put back in front of the founder") -and (Test-Refused $a "horde decisions add -File <question.json> -FollowsUp 2") -and (Test-Refused $a "question 2 and what he answered folded under it")) "REOPEN IS REFUSED for a closed question too, and the refusal tells the keeper to add a follow-up that names question 2"
Check ((Get-Files $s) -ceq $filesWere -and (Get-Listed $s "all") -ceq "1:open,2:closed,3:open,4:open") "and it wrote nothing: question 2 is still closed"
# A RECORD ALREADY IN THE STORE IS A FACT. A reopening an earlier version wrote is read as it always
# was: the question is open again, once, under its old number, with the reason.
$reason = "the fix did not hold"
$reopenId = New-Id
$reopenHash = Get-HordeDecisionHash -Value ([ordered]@{ operation = "reopen"; actor = "warchief"; number = [long]2; body = [ordered]@{ reason = $reason } })
$null = Add-Stored $s "question-reopened" ([ordered]@{ number = 2; reason = $reason }) -Id $reopenId -Hash $reopenHash
$a = Invoke-Op $s "show" @{ number = 2 }
Check ((Get-Outcome $a) -ceq "done" -and $a.value.question.state -ceq "open" -and $a.value.question.outcome -eq "" -and $a.value.question.reopenReason -ceq "the fix did not hold" -and $a.value.question.thread.turn -ceq "founder") "A REOPENING ALREADY IN THE STORE still reads as it did: question 2 is open as question 2, with the reason, and it is the founder's turn"
Check ((Get-Listed $s "all") -ceq "1:open,2:open,3:open,4:open") "and every question still has the number it was given"
# The very request that made that record, sent again under its id, is answered from the record -
# a repost is answered before anything is judged - and still writes nothing.
$again = Invoke-Op $s "reopen" @{ id = $reopenId; actor = "warchief"; number = 2; reason = $reason }
Check ((Get-Outcome $again) -ceq "replayed" -and $again.value.sequence -eq 6 -and (Get-Files $s) -ceq ((1..6 | ForEach-Object { $_.ToString("D10") + ".json" }) -join ",")) ("a reopening recorded before, sent again under its own id, is replayed from its record and not refused (" + (Get-Outcome $again) + ")")
Check (Test-Refused (Invoke-Op $s "reopen" @{ id = (New-Id); actor = "warchief"; number = 2; reason = "line one`nline two" }) "nothing is reopened any more") "and a new reopening is refused whatever its reason looks like: there is nothing to put right in it"
$a = Add-Q $s @{ title = "Is the question added after a reopen given a new number?" }
Check ($a.state -ceq "known" -and $a.value.number -eq 5) "the next question is 5"
$show = Invoke-Op $s "show" @{ number = 2 }
Check ((Get-Outcome $show) -ceq "done" -and (@($show.value.question.history | ForEach-Object { $_.note }) -join ",") -ceq "added,closed,reopened" -and $show.value.question.title -ceq "Is question number 2 of this test asked in plain words?") "show 2 gives the same question with its whole history"
Check ((Get-Files $s) -ceq ((1..7 | ForEach-Object { $_.ToString("D10") + ".json" }) -join ",")) "CONTROL: seven records - six accepted requests and the reopening put there as a file - and none for the refused or the replayed"

Write-Host ""
Write-Host "--- how much a question matters, and how much it holds up: stated at add, corrected by rank ---" -ForegroundColor Cyan
$r = New-TestStore
$plain = Add-Q $r @{ title = "Is a question added with neither word the record it always was?" }
$rec = [System.IO.File]::ReadAllText((Join-Path $r "0000000001.json")) | ConvertFrom-Json
Check ((Get-Outcome $plain) -ceq "done" -and (@($rec.data.PSObject.Properties | ForEach-Object { $_.Name }) -join ",") -ceq "number,question" -and $plain.value.question.importance -ceq "normal" -and $plain.value.question.blocks -ceq "part" -and $plain.value.question.importanceShown -eq "" -and $plain.value.question.blocksShown -eq "") "A QUESTION ADDED WITH NEITHER WORD writes the record every earlier version wrote - a number and the question, nothing else - and reads as normal and part"
$marked = Invoke-Op $r "add" @{ id = (New-Id); actor = "warchief"; importance = "high"; blocks = "all"; question = (New-Question @{ title = "Is a question added with both words given them back?" }) }
$rec = [System.IO.File]::ReadAllText((Join-Path $r "0000000002.json")) | ConvertFrom-Json
Check ((Get-Outcome $marked) -ceq "done" -and (@($rec.data.PSObject.Properties | Where-Object { @("importance", "blocks") -ccontains $_.Name } | ForEach-Object { $_.Name + "=" + $_.Value } | Sort-Object) -join ",") -ceq "blocks=all,importance=high" -and $marked.value.question.importance -ceq "high" -and $marked.value.question.importanceShown -ceq "Important" -and $marked.value.question.blocksShown -ceq "Blocks all work") "add with both words records them, and the answer hands them back with their plain words"
$half = Invoke-Op $r "add" @{ id = (New-Id); actor = "warchief"; blocks = "none"; question = (New-Question @{ title = "Is a question added with one word given the other's default?" }) }
$rec = [System.IO.File]::ReadAllText((Join-Path $r "0000000003.json")) | ConvertFrom-Json
Check ((Get-Outcome $half) -ceq "done" -and (@($rec.data.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object) -join ",") -ceq "blocks,number,question" -and $half.value.question.importance -ceq "normal" -and $half.value.question.blocks -ceq "none") "add with one word records that one only: the other is not written down as if it had been said"
$filesWere = Get-Files $r
foreach ($bad in @(
    @{ what = "an importance that is no word of the list"; req = @{ importance = "urgent" }; says = "request.importance is 'urgent', not one of: high, normal, low" }
    @{ what = "an importance in capitals"; req = @{ importance = "HIGH" }; says = "not one of: high, normal, low" }
    @{ what = "a blocking that is no word of the list"; req = @{ blocks = "some" }; says = "request.blocks is 'some', not one of: all, part, none" }
    @{ what = "a blocking that is a number"; req = @{ blocks = 2 }; says = "request.blocks" }
    @{ what = "a follow-up of question 0"; req = @{ followsUp = 0 }; says = "request.followsUp" }
    @{ what = "a follow-up that is text"; req = @{ followsUp = "1" }; says = "request.followsUp" }
    @{ what = "a member add does not take"; req = @{ urgency = "high" }; says = "request has 'urgency'" }
)) {
    $request = @{ id = (New-Id); actor = "warchief"; question = (New-Question @{ title = "Is a question with a wrong word beside it refused whole?" }) }
    foreach ($k in @($bad.req.Keys)) { $request[$k] = $bad.req[$k] }
    Check ((Test-Refused (Invoke-Op $r "add" $request) $bad.says) -and (Get-Files $r) -ceq $filesWere) ($bad.what + " is refused by name, and no question is added")
}
$a = Invoke-Op $r "add" @{ id = (New-Id); actor = "warchief"; followsUp = 1e30; question = (New-Question) }
Check ((Test-Refused $a "'followsUp' is not a question's number") -and (Get-Files $r) -ceq $filesWere) ("a follow-up of a number no question can have is refused, not thrown on (" + (Get-Outcome $a) + ")")
$a = Invoke-Op $r "add" @{ id = (New-Id); actor = "warchief"; followsUp = 4; question = (New-Question) }
Check ((Test-Refused $a "'followsUp' names question 4, and the list has no question 4 to show with this one; the highest number given is 3") -and (Get-Files $r) -ceq $filesWere) "A FOLLOW-UP OF A QUESTION THAT IS NOT THERE is refused - a question cannot follow itself or one not yet asked - and nothing is added"

Write-Host ""
Write-Host "--- needs a passkey: written only as true, shown only when true ---" -ForegroundColor Cyan
$p = New-TestStore
$keyed = Invoke-Op $p "add" @{ id = (New-Id); actor = "warchief"; needsPasskey = $true; question = (New-Question @{ title = "Is a question marked as needing a passkey recorded so?" }) }
$rec = [System.IO.File]::ReadAllText((Join-Path $p "0000000001.json")) | ConvertFrom-Json
Check ((Get-Outcome $keyed) -ceq "done" -and (@($rec.data.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object) -join ",") -ceq "needsPasskey,number,question" -and (Get-HordeTestMember $rec.data "needsPasskey") -eq $true -and (Get-HordeTestMember $keyed.value.question "needsPasskey") -eq $true) "add with needsPasskey true writes needsPasskey true into the record, and the view hands it back as true"
$unkeyed = Add-Q $p @{ title = "Is a question with no passkey mark the record it always was?" }
$rec = [System.IO.File]::ReadAllText((Join-Path $p "0000000002.json")) | ConvertFrom-Json
Check ((Get-Outcome $unkeyed) -ceq "done" -and (@($rec.data.PSObject.Properties | ForEach-Object { $_.Name }) -join ",") -ceq "number,question" -and $null -eq $unkeyed.value.question.PSObject.Properties["needsPasskey"]) "CONTROL: add without needsPasskey writes no needsPasskey member, and the view has none"
$falseKey = Invoke-Op $p "add" @{ id = (New-Id); actor = "warchief"; needsPasskey = $false; question = (New-Question @{ title = "Is needsPasskey false written down at all?" }) }
$rec = [System.IO.File]::ReadAllText((Join-Path $p "0000000003.json")) | ConvertFrom-Json
Check ((Get-Outcome $falseKey) -ceq "done" -and (@($rec.data.PSObject.Properties | ForEach-Object { $_.Name }) -join ",") -ceq "number,question" -and $null -eq $falseKey.value.question.PSObject.Properties["needsPasskey"]) "add with needsPasskey false writes nothing: the record is byte for byte the unmarked one, and the view has no needsPasskey"
$pFiles = Get-Files $p
foreach ($bad in @(
    @{ what = "needsPasskey as the word yes"; key = "yes" }
    @{ what = "needsPasskey as the number 1"; key = 1 }
)) {
    $a = Invoke-Op $p "add" @{ id = (New-Id); actor = "warchief"; needsPasskey = $bad.key; question = (New-Question @{ title = "Is a needsPasskey that is not true or false refused?" }) }
    Check ((Test-Refused $a "needsPasskey") -and (Get-Files $p) -ceq $pFiles) ($bad.what + " is not a boolean: refused by name, and no question is added")
}
$listedKeys = Invoke-Op $p "list" @{ state = "all" }
Check ((Get-Outcome $listedKeys) -ceq "done" -and (@($listedKeys.value.questions | ForEach-Object { "" + $_.number + ":" + [bool](Get-HordeTestMember $_ "needsPasskey") + ":" + ($null -ne $_.PSObject.Properties["needsPasskey"]) }) -join ",") -ceq "1:True:True,2:False:False,3:False:False") "a list read again from the records shows needsPasskey on the marked question only"
# THE WORDS ARE PART OF WHAT MAKES A REQUEST THE SAME: one id, the same question, another importance is
# another request, and is refused as that.
$id = New-Id
$first = Invoke-Op $r "add" @{ id = $id; actor = "warchief"; importance = "low"; followsUp = 2; question = (New-Question @{ title = "Is the same add sent twice one question, whatever stands beside it?" }) }
$again = Invoke-Op $r "add" @{ id = $id; actor = "warchief"; importance = "low"; followsUp = 2; question = (New-Question @{ title = "Is the same add sent twice one question, whatever stands beside it?" }) }
$other = Invoke-Op $r "add" @{ id = $id; actor = "warchief"; importance = "high"; followsUp = 2; question = (New-Question @{ title = "Is the same add sent twice one question, whatever stands beside it?" }) }
$bare = Invoke-Op $r "add" @{ id = $id; actor = "warchief"; question = (New-Question @{ title = "Is the same add sent twice one question, whatever stands beside it?" }) }
Check ((Get-Outcome $first) -ceq "done" -and $first.value.number -eq 4 -and (Get-Outcome $again) -ceq "replayed" -and $again.value.number -eq 4 -and $again.value.question.followsUp.number -eq 2 -and $again.value.question.importance -ceq "low") "the same add, words and all, sent again under its id is one question, answered again as it was"
Check ((Test-Refused $other "was already used for a different request") -and (Test-Refused $bare "was already used for a different request") -and (Get-Listed $r) -ceq "1:open,2:open,3:open,4:open") "the same id with another importance, or with none, is a different request: refused, and nothing added"
# RANK.
$filesWere = Get-Files $r
$id = New-Id
$up = Invoke-Op $r "rank" @{ id = $id; actor = "warchief"; number = 1; importance = "high"; blocks = "all" }
Check ((Get-Outcome $up) -ceq "done" -and $up.value.number -eq 1 -and $up.value.sequence -eq 5 -and $up.value.question.importance -ceq "high" -and $up.value.question.blocks -ceq "all" -and (@($up.value.question.history | ForEach-Object { $_.note }) -join "|") -ceq "added|ranked: importance high, blocks all") ("rank changes the two words of question 1 in one record of its own, and the history says so (" + (Get-Outcome $up) + ")")
$rec = [System.IO.File]::ReadAllText((Join-Path $r "0000000005.json")) | ConvertFrom-Json
Check ($rec.kind -ceq "question-ranked" -and (@($rec.data.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object) -join ",") -ceq "blocks,importance,number" -and ([System.IO.File]::ReadAllText((Join-Path $r "0000000001.json")) | ConvertFrom-Json).data.PSObject.Properties["importance"] -eq $null) "THE QUESTION'S OWN RECORD IS NEVER EDITED: the ranking is record 5, and record 1 still states no word"
$replay = Invoke-Op $r "rank" @{ id = $id; actor = "warchief"; number = 1; importance = "high"; blocks = "all" }
Check ((Get-Outcome $replay) -ceq "replayed" -and $replay.value.sequence -eq 5 -and (Get-Files $r) -ceq ($filesWere + ",0000000005.json")) "the same ranking sent again under its id is answered from its record, and writes nothing"
$filesWere = Get-Files $r
Check ((Test-Refused (Invoke-Op $r "rank" @{ id = (New-Id); actor = "warchief"; number = 1; importance = "high" }) "it changes nothing: question 1 already has that importance and that blocking") -and (Get-Files $r) -ceq $filesWere) "a ranking that changes nothing, under a new id, is refused as that"
Check ((Test-Refused (Invoke-Op $r "rank" @{ id = (New-Id); actor = "warchief"; number = 1 }) "the ranking names neither word") -and (Test-Refused (Invoke-Op $r "rank" @{ id = (New-Id); actor = "warchief"; number = 1; importance = "urgent" }) "request.importance is 'urgent'") -and (Test-Refused (Invoke-Op $r "rank" @{ id = (New-Id); actor = "warchief"; number = 1; blocks = "all"; title = "x" }) "request has 'title'") -and (Get-Files $r) -ceq $filesWere) "a ranking that names neither word, a word that is none of the list's, or a field of the question is refused"
Check ((Test-Refused (Invoke-Op $r "rank" @{ id = (New-Id); actor = "founder"; number = 1; blocks = "none" }) "'founder' is not a role that may change the list") -and (Invoke-Op $r "rank" @{ id = (New-Id); actor = "warchief"; number = 99; blocks = "none" }).state -ceq "absent" -and (Get-Files $r) -ceq $filesWere) "only the keeper ranks, and a question that is not there is absent"
$null = Invoke-Op $r "close" @{ id = (New-Id); actor = "warchief"; number = 3; outcome = "Done." }
Check ((Test-Refused (Invoke-Op $r "rank" @{ id = (New-Id); actor = "warchief"; number = 3; importance = "high" }) "question 3 is closed, and only an open question is ranked") -and (Get-Listed $r) -ceq "1:open,2:open,3:closed,4:open") "a closed question is not ranked"
$down = Invoke-Op $r "rank" @{ id = (New-Id); actor = "warchief"; number = 1; blocks = "part" }
Check ((Get-Outcome $down) -ceq "done" -and $down.value.question.importance -ceq "high" -and $down.value.question.blocks -ceq "part" -and $down.value.question.blocksShown -eq "" -and $down.value.question.wordingVersion -eq 1) "a ranking that names one word leaves the other, and moves no wording"
$listed = Invoke-Op $r "list" @{ state = "all" }
Check ((@($listed.value.questions | ForEach-Object { "" + $_.number + ":" + $_.importance + "/" + $_.blocks }) -join ",") -ceq "1:high/part,2:high/all,3:normal/none,4:low/part" -and $listed.value.questions[3].followsUp.number -eq 2 -and $null -eq $listed.value.questions[0].PSObject.Properties["followsUp"]) "every question of a list carries its two words, and a follow-up the question it follows"

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
# THE LISTED WORDS, IN ANY CASE, AND NOTHING ELSE. Measured 2026-10-06: `list -State ALL` was refused
# with a regular expression for a reason ("request.state does not match ^[a-z][a-z-]{0,31}$").
foreach ($spelt in @("ALL", "All", "CLOSED", "Open")) {
    $a = Invoke-Op $s "list" @{ state = $spelt }
    $same = Invoke-Op $s "list" @{ state = $spelt.ToLowerInvariant() }
    Check ((Get-Outcome $a) -ceq "done" -and (@($a.value.questions | ForEach-Object { $_.number }) -join ",") -ceq (@($same.value.questions | ForEach-Object { $_.number }) -join ",")) ("list with state '" + $spelt + "' is the list with state '" + $spelt.ToLowerInvariant() + "' (" + (Get-Outcome $a) + ")")
}
Check ((@((Invoke-Op $s "list" @{ state = "CLOSED" }).value.questions | ForEach-Object { $_.number }) -join ",") -ceq "4") "CONTROL: and that is the closed question alone, not every question"
$a = Invoke-Op $s "list" @{ state = "ANSWERED" }
Check ((Test-Refused $a "is not a state a question can be in; give one of: open, closed, or all") -and -not "$($a.value.findings)".Contains("^[")) "a word that is not listed is refused in words, in any case, with the words that are"
foreach ($notAWord in @("open closed", "open!", "")) {
    $a = Invoke-Op $s "list" @{ state = $notAWord }
    Check ((Get-Outcome $a) -ceq "refused" -and -not "$($a.value.findings)".Contains("^[") -and -not "$($a.value.findings)".Contains("'" + $notAWord + "'")) ("'" + $notAWord + "' is refused; the reason is not a regular expression, and text that is not a word is not said back")
}
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
Check ((Get-Outcome $a) -ceq "done" -and (@($a.value.questions | ForEach-Object { $_.number }) -join ",") -ceq "1" -and @($a.value.unreadable).Count -eq 1) "the list loads with question 1, and the record of another schema is reported as unreadable"
Check ($a.value.unreadable[0].sequence -eq 2 -and $a.value.unreadable[0].reason -like "*not a decision-event.v1 record*schemaVersion*") "the version 2 record is not read as version 1, and the reason names the field"
Check ((Get-NotUnderstood $a) -ceq "answer-recorded x1 3-3") ("the record of an unknown kind is not damage: it is named apart, as not understood by this version (" + (Get-NotUnderstood $a) + ")")

Write-Host ""
Write-Host "--- records of a later kind between questions: no number moves, and every operation works ---" -ForegroundColor Cyan
# The compatibility contract of decisions/Rules.ps1, through the operations: a store that a later
# version has also written to. Measured 2026-10-07, before it: with these four records the next
# question was numbered 7, not 3.
function New-LaterRecord { param([long]$Sequence, [string]$Kind, [string]$Data, [string]$Id = "") if ($Id -eq "") { $Id = $Sequence.ToString("x32") }; return ('{"schemaVersion":1,"sequence":' + $Sequence + ',"id":"' + $Id + '","kind":"' + $Kind + '","at":"2026-10-07T09:00:00Z","actor":"founder","requestHash":"' + ("1" * 64) + '","data":' + $Data + '}') }
$s = New-TestStore
$null = Add-Q $s                                                                                    # record 1, question 1
$laterId = "f" * 32
[System.IO.File]::WriteAllText((Join-Path $s "0000000002.json"), (New-LaterRecord 2 "spoken-in-a-later-version" '{"number":1,"speaker":"founder","text":"yes"}' $laterId), $utf8)
[System.IO.File]::WriteAllText((Join-Path $s "0000000003.json"), (New-LaterRecord 3 "seen-in-a-later-version" '{"reader":"warchief","upTo":2}'), $utf8)
$a = Add-Q $s @{ title = "Is the second question still the second after later records?" }           # record 4
Check ((Get-Outcome $a) -ceq "done" -and $a.value.number -eq 2 -and $a.value.sequence -eq 4) ("after two records of later kinds the next question is 2, in record 4: no number was left unused (" + (Get-Outcome $a) + ", number " + $(if ($a.state -ceq "known" -and $null -ne $a.value.PSObject.Properties["number"]) { $a.value.number } else { "none" }) + ")")
[System.IO.File]::WriteAllText((Join-Path $s "0000000005.json"), (New-LaterRecord 5 "spoken-in-a-later-version" '{"number":2,"speaker":"warchief","text":"noted"}'), $utf8)
[System.IO.File]::WriteAllText((Join-Path $s "0000000006.json"), (New-LaterRecord 6 "spoken-in-a-later-version" '{"number":2,"speaker":"founder","text":"good"}'), $utf8)
$a = Add-Q $s @{ title = "Is the third question the third, whatever a later version wrote?" }      # record 7
Check ((Get-Outcome $a) -ceq "done" -and $a.value.number -eq 3 -and $a.value.sequence -eq 7) ("and the one after is 3, in record 7 (" + (Get-Outcome $a) + ")")
Check ((Get-NotUnderstood $a) -ceq "spoken-in-a-later-version x3 2-6; seen-in-a-later-version x1 3-3" -and @($a.value.unreadable).Count -eq 0 -and @($a.value.ignored).Count -eq 0) ("the write's own result names them once per kind, with how many and from which record to which, and calls none of them unreadable (" + (Get-NotUnderstood $a) + ")")
$listed = Invoke-Op $s "list" @{ state = "all" }
Check ((Get-Outcome $listed) -ceq "done" -and (@($listed.value.questions | ForEach-Object { $_.number }) -join ",") -ceq "1,2,3" -and (Get-NotUnderstood $listed) -ceq "spoken-in-a-later-version x3 2-6; seen-in-a-later-version x1 3-3") "list shows questions 1, 2 and 3 and the same one finding per kind"
$shown = Invoke-Op $s "show" @{ number = 2 }
Check ((Get-Outcome $shown) -ceq "done" -and $shown.value.question.title -ceq "Is the second question still the second after later records?" -and @($shown.value.question.history).Count -eq 1) "show 2 is the second question, with a history of one record: the later records about it changed nothing this version shows"
$closed = Invoke-Op $s "close" @{ id = (New-Id); actor = "warchief"; number = 1; outcome = "Done." }
Check ((Get-Outcome $closed) -ceq "done" -and (Get-Listed $s) -ceq "1:closed,2:open,3:open") "and close, like every write, goes on working around them"
$closedAgain = Invoke-Op $s "close" @{ id = (New-Id); actor = "warchief"; number = 1; outcome = "Done again." }
Check ((Get-Outcome $closedAgain) -ceq "refused" -and (Get-NotUnderstood $closedAgain) -ceq "spoken-in-a-later-version x3 2-6; seen-in-a-later-version x1 3-3") ("a refusal names them too: no result leaves them out (" + (Get-NotUnderstood $closedAgain) + ")")
Check (@($listed.value.notUnderstood | Where-Object { "$($_.reason)" -notlike "*later version*" -or "$($_.reason)" -notlike "*no question number*" }).Count -eq 0) "each finding says in words what it is: written by a later version, kept, and costing no question number"
# A REPOST OF AN ID A LATER-KIND RECORD CARRIES DOES NOT WRITE AGAIN: the envelope is readable, so the id is seen.
$before = Get-Files $s
$again = Add-Q $s @{ title = "Is an id a later version used ever written under twice?" } $laterId
Check ((Get-Outcome $again) -ceq "refused" -and (Test-Refused $again ("the id " + $laterId + " was already used")) -and (Test-Refused $again "record 2, spoken-in-a-later-version") -and (Get-Files $s) -ceq $before) ("a request under the id of a record this version did not understand is refused, naming that record and its kind, and writes nothing (" + (Get-Outcome $again) + ")")
# A QUESTION-ADDED RECORD WHOSE KIND WAS DAMAGED INTO ANOTHER NAME: set aside, and its number never given
# again. Observed in review on 2026-10-07: the kind changed by one letter, show 2 said absent, and the
# next add became number 2 with a different title.
$s = New-TestStore
$null = Add-Q $s                                                                                    # question 1
$null = Add-Q $s @{ title = "Is the second question's number kept when its kind is damaged?" }      # question 2
$second = Join-Path $s "0000000002.json"
$text = [System.IO.File]::ReadAllText($second, $utf8)
[System.IO.File]::WriteAllText($second, $text.Replace('"kind":"question-added"', '"kind":"question-addex"'), $utf8)
$a = Add-Q $s @{ title = "Is the next question numbered past the damaged one?" }
Check ((Get-Outcome $a) -ceq "done" -and $a.value.number -eq 3 -and (Get-NotUnderstood $a) -ceq "question-addex x1 2-2") ("the next add is question 3, not 2: a number is never given twice (" + (Get-Outcome $a) + ", number " + $(if ($a.state -ceq "known" -and $null -ne $a.value.PSObject.Properties["number"]) { $a.value.number } else { "-" }) + ")")
$shown = Invoke-Op $s "show" @{ number = 2 }
Check ($shown.state -ceq "unknown" -and "$($shown.reason)" -like "*question 2 cannot be read*" -and "$($shown.reason)" -like "*record 2*question-addex*") ("and show 2 says question 2 cannot be read and names the record set aside - not that there never was a question 2, and not another question (" + $shown.state + ": " + $shown.reason + ")")
# CONTROL: damage keeps the conservative rule - a torn record between questions still costs a number.
$s = New-TestStore
$null = Add-Q $s
[System.IO.File]::WriteAllText((Join-Path $s "0000000002.json"), '{"schemaVersion":1,"sequence":2,"id":"', $utf8)
$a = Add-Q $s @{ title = "Is a number still left unused after a torn record?" }
Check ((Get-Outcome $a) -ceq "done" -and $a.value.number -eq 3 -and (Get-NotUnderstood $a) -ceq "" -and @($a.value.unreadable).Count -eq 1) ("CONTROL: a torn record is unreadable, not 'not understood', and the next question is 3: it may have been question 2 (" + (Get-Outcome $a) + ")")

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
Write-Host "--- a record that could not be confirmed on disk is never reported as saved ---" -ForegroundColor Cyan
# The store says "unconfirmed" when a record HAS its name but the flush after its move failed
# (decisions/Store.ps1). The caller must not be told "done" - nothing says the record would survive a
# power cut - and must not be told "nothing was written" either, because the record is there. Here
# the durable move is replaced by one that makes the real move and then answers as a failed flush does.
$s = New-TestStore
$null = Add-Q $s
$realMove = ${function:Move-HordeFileNewDurable}
$script:unconfirmedOnce = 1
function Move-HordeFileNewDurable {
    param([string]$From, [string]$To, $Open = $null, $OsPlatform = $null)
    $answer = & $realMove -From $From -To $To -Open $Open
    if ($script:unconfirmedOnce -gt 0 -and $answer -ceq "moved") { $script:unconfirmedOnce--; return "unconfirmed" }
    return $answer
}
try {
    $unsureId = New-Id
    $a = Add-Q $s @{ title = "Is a record nobody could confirm ever called saved?" } $unsureId
    Check ($a.state -ceq "unknown") ("an add whose record could not be confirmed on disk is unknown: not done, and not replayed as if it had been recorded before (" + (Get-Outcome $a) + ")")
    Check ($a.state -ceq "unknown" -and $a.reason -like "*record 2 has its place in the store*could not be confirmed*NOT reported as saved*same id*") ("and the reason says the record is there, that it is not reported as saved, and what to do (" + $a.reason + ")")
    Check ((Get-Files $s) -ceq "0000000001.json,0000000002.json") "the record does have its place: the answer did not claim that nothing was written"
    Check ($script:unconfirmedOnce -eq 0) "CONTROL: the move was made, and answered unconfirmed exactly once"
    # THE RESEND CONFIRMS BEFORE IT ANSWERS. "replayed" says "this was recorded": after an unconfirmed
    # save that is the very claim that could not be made, so the resend first has the record flushed
    # to disk - through core's one flush path, the same the move uses - and only then answers. Here
    # that path is replaced by one that writes down what it was handed and answers as the test says.
    $realFlush = ${function:Confirm-HordeFileFlushed}
    $script:flushes = New-Object System.Collections.ArrayList
    $script:flushAnswer = "unconfirmed"
    function Confirm-HordeFileFlushed {
        param($Open)
        $name = ""; $canWrite = $false; $length = [long]-1
        if ($Open -is [System.IO.FileStream]) { $name = [System.IO.Path]::GetFileName($Open.Name); $canWrite = $Open.CanWrite; $length = $Open.Length }
        [void]$script:flushes.Add([pscustomobject]@{ name = $name; canWrite = $canWrite; length = $length })
        if ($script:flushAnswer -ceq "real") { return (& $realFlush -Open $Open) }
        return $script:flushAnswer
    }
    $bytesBefore = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $s "0000000002.json")))
    $a = Add-Q $s @{ title = "Is a record nobody could confirm ever called saved?" } $unsureId
    Check ($a.state -ceq "unknown" -and $a.reason -like "*record 2 holds this request*could not be confirmed*NOT reported as saved*") ("a resend whose flush of the record fails is unknown AGAIN: it is not answered 'replayed' on the strength of a flush that did not happen (" + (Get-Outcome $a) + ")")
    Check ($script:flushes.Count -eq 1 -and $script:flushes[0].name -ceq "0000000002.json" -and $script:flushes[0].canWrite -and $script:flushes[0].length -gt 0) ("the resend opened the EXISTING record and handed it to the flush path, once (" + $script:flushes.Count + " flush(es)" + $(if ($script:flushes.Count -ge 1) { " of " + $script:flushes[0].name } else { "" }) + ")")
    Check ((Get-Files $s) -ceq "0000000001.json,0000000002.json") "and wrote nothing"
    $script:flushes.Clear(); $script:flushAnswer = "real"
    $a = Add-Q $s @{ title = "Is a record nobody could confirm ever called saved?" } $unsureId
    Check ((Get-Outcome $a) -ceq "replayed" -and $a.value.number -eq 2 -and (Get-Files $s) -ceq "0000000001.json,0000000002.json") ("once the flush succeeds, the same request with the same id is answered from that record and writes nothing (" + (Get-Outcome $a) + ")")
    Check ($script:flushes.Count -eq 1 -and $script:flushes[0].name -ceq "0000000002.json") "and that answer too came after the record was flushed: every 'replayed' is confirmed first, since nothing records which saves were not"
    Check ([System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $s "0000000002.json"))) -ceq $bytesBefore) "confirming changed no byte of the record: it is opened to be flushed, and nothing is written to it"
    # A request that is NOT a repost flushes nothing but its own new record, through the move.
    $script:flushes.Clear()
    $a = Add-Q $s
    Check ((Get-Outcome $a) -ceq "done" -and @($script:flushes | Where-Object { $_.name -cmatch '\A[0-9]{10}\.json\z' -and $_.name -cne "0000000003.json" }).Count -eq 0) "CONTROL: a new request flushes no earlier record"
    # The id of a DIFFERENT request is refused without any flush: nothing is being claimed saved.
    $script:flushes.Clear()
    $a = Add-Q $s @{ title = "Is another question under a used id ever confirmed as saved?" } $unsureId
    Check ((Get-Outcome $a) -ceq "refused" -and $script:flushes.Count -eq 0) "CONTROL: the same id with another request is refused, and nothing is flushed for it"
} finally {
    Remove-Item -LiteralPath function:Move-HordeFileNewDurable
    if (Test-Path -LiteralPath function:Confirm-HordeFileFlushed) { Remove-Item -LiteralPath function:Confirm-HordeFileFlushed }
    . (Join-Path $root "core\FileAtomic.ps1")
}
$a = Add-Q $s
Check ((Get-Outcome $a) -ceq "done") "CONTROL: the real move and the real flush are back in place for the rest of the suite"

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
Write-Host "--- a settings override that fails its checks: every operation that needs its settings says why, and nothing is guessed ---" -ForegroundColor Cyan
# The rule: an override file that fails its checks refuses with a reason and never silently falls back
# to the defaults. So with a wrong <home>\settings\decisions.json no operation runs on defaults it was
# told not to use: it answers unknown, naming the file and every problem in it.
$keepSettingsHome = $env:HORDE_HOME
try {
    $settingsHome = Join-Path $script:work "settings-home"
    $env:HORDE_HOME = $settingsHome
    $s = Join-Path $settingsHome "store\decisions"
    $null = Add-Q $s
    New-Item -ItemType Directory -Path (Join-Path $settingsHome "settings") | Out-Null
    $overrideFile = Join-Path $settingsHome "settings\decisions.json"
    [System.IO.File]::WriteAllText($overrideFile, '{"schemaVersion":1,"values":{"decisions.write.raceTries":0,"decisions.store.maxGap":"many"}}', $utf8)
    $a = Add-Q $s
    Check ($a.state -ceq "unknown" -and $a.reason -like "*settings\decisions.json*'decisions.write.raceTries' is 0, outside the range 1 to 100000*'decisions.store.maxGap' is not a whole number*") ("an add with a wrong settings override is unknown, and names the file and BOTH problems (" + $a.state + ": " + $a.reason + ")")
    Check ((Get-Files $s) -ceq "0000000001.json") "and nothing was written: it did not go ahead on the defaults"
    $l = Invoke-Op $s "list" @{}
    Check ($l.state -ceq "unknown" -and $l.reason -like "*settings\decisions.json*'decisions.write.raceTries' is 0*") ("a list is unknown too, with the same reason: a reading needs the store's settings (" + $l.state + ")")
    # THE ANSWER IS GIVEN BEFORE THE STORE IS TOUCHED, and it is the settings' own sentence - not whatever
    # the first part of the store to ask for a setting happened to throw, and not an answer from a
    # path that happens to need none.
    Check ("$($a.reason)".StartsWith("the decisions settings override was refused, so no setting is used and no default is put in its place: ") -and "$($l.reason)".StartsWith("the decisions settings override was refused, so no setting is used and no default is put in its place: ")) ("the reason is the settings' own sentence from its first word, for the add and for the list (" + $l.reason + ")")
    $nowhere = Join-Path $settingsHome "no-such-store\decisions"
    $ln = Invoke-Op $nowhere "list" @{}
    Check ($ln.state -ceq "unknown" -and "$($ln.reason)".StartsWith("the decisions settings override was refused") -and -not (Test-Path -LiteralPath $nowhere)) ("a list of a store that is not there yet is unknown for the same reason: no path answers on its own because it happened to need no setting (" + $ln.state + ": " + $ln.reason + ")")
    $sh = Invoke-Op $s "show" @{ number = 7 }
    Check ($sh.state -ceq "unknown" -and "$($sh.reason)".StartsWith("the decisions settings override was refused")) ("show of a question that is not there is unknown too, not absent (" + $sh.state + ")")
    Check ((Get-Outcome (Invoke-Op $s "kinds" @{})) -ceq "done") "CONTROL: kinds, which reads no store and needs no setting, still answers"
    # A RIGHT override is used: with the largest gap believed set to 0, a record one place past the end is a stray.
    [System.IO.File]::WriteAllText($overrideFile, '{"schemaVersion":1,"values":{"decisions.store.maxGap":0}}', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $s "0000000003.json"), '{"stray":true}', $utf8)
    $l = Invoke-Op $s "list" @{}
    Check ((Get-Outcome $l) -ceq "done" -and (@($l.value.strays | ForEach-Object { $_.file }) -join ",") -ceq "0000000003.json" -and @($l.value.unreadable).Count -eq 0) ("a right override is used, not only checked: with maxGap 0 the file one place past the end is a stray (" + (Get-Outcome $l) + ")")
    Remove-Item -LiteralPath $overrideFile
    $l = Invoke-Op $s "list" @{}
    Check ((Get-Outcome $l) -ceq "done" -and @($l.value.strays).Count -eq 0 -and @($l.value.unreadable).Count -eq 2) "CONTROL: with no override file the default of 100 is back: the same file is read as a record after a gap"
} finally { $env:HORDE_HOME = $keepSettingsHome }

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
    Check ("$($a.reason)".StartsWith("the decisions store could not be found")) ("and it is said as what it is - the store could not be found - before anything is asked of the settings (" + $a.reason + ")")
} finally { $env:HORDE_HOME = $keepHome }

} finally {
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-decisions-ops-test-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the suite's temp folder is removed"
Check ((Get-RealStoreListing) -ceq $realBefore) ("the real store under the user profile is exactly as it was before the suite (" + $(if ($realBefore.Length -gt 60) { $realBefore.Substring(0, 60) + "..." } else { $realBefore }) + ")")

Complete-HordeSuite -Success "every operation writes one record for one accepted request, keeps every number, reports every damaged record, and refuses the rest by name"
