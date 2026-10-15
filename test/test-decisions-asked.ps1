# WHEN A QUESTION WAS ASKED - the rules of decisions/Rules.ps1 (WHEN A QUESTION WAS ASKED), run on records
# built here, without a store or a command line.
#
# The founder, 2026-10-14: his list shows when each question was last asked, and sorts by it. A
# question's "asked" is derived in the fold from its records: first (question-added), remind
# (question-reminded), thrall-reply (the keeper's words that ask, under an open question) and follow-up
# (a question-added whose followsUp names it). This suite holds each rule beside a control that shows
# the check can fail: which words ask and which do not, a closed question, the cap on what a view
# carries, a question built by hand with no list, the note's limits, and the view against
# schema/decision-result.v1. test/e2e/e2e-decisions-asked.ps1 drives the same at the real command line.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\JsonText.ps1")
. (Join-Path $root "decisions\Rules.ps1")
. (Join-Path $root "decisions\Definitions.ps1")

$defs = Get-HordeDecisionDefinitions
$zeros = "0" * 64

function New-Record {
    # One stored record as the store hands it over: the envelope written as JSON and read back. Record
    # n is at minute n of one day, so a later record is always a later moment.
    param([long]$Seq, [string]$Kind, $Data, [string]$Actor = "warchief")
    $envelope = [ordered]@{ schemaVersion = 1; sequence = $Seq; id = $Seq.ToString("x32"); kind = $Kind; at = (Get-At $Seq); actor = $Actor; requestHash = $zeros; data = $Data }
    return [pscustomobject]@{ sequence = $Seq; file = ($Seq.ToString("D10") + ".json"); kind = "ok"; data = (ConvertFrom-HordeJson (ConvertTo-Json -InputObject $envelope -Compress -Depth 12)); reason = "" }
}
function Get-At { param([long]$Seq) return ([datetime]::new(2026, 10, 14, 0, 0, 0, [System.DateTimeKind]::Utc).AddMinutes($Seq).ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)) }
function New-Added {
    param([long]$Seq, [int]$Number, [string]$AskedBy = "orc-e", [int]$FollowsUp = 0)
    $q = ConvertTo-HordeDecisionFields -Source @{ title = "Should question $Number run on the spare machine tonight?"; kind = "yes-no"; whatItIs = "It is idle at night."; group = "builds"; askedBy = $AskedBy }
    $data = [ordered]@{ number = $Number; question = $q }
    if ($FollowsUp -ge 1) { $data["followsUp"] = $FollowsUp }
    return (New-Record -Seq $Seq -Kind "question-added" -Data $data)
}
function New-Reminded { param([long]$Seq, [int]$Number, [string]$Note = $null) $d = [ordered]@{ number = $Number }; if ($null -ne $Note) { $d["note"] = $Note }; return (New-Record -Seq $Seq -Kind "question-reminded" -Data $d) }
function New-Said {
    param([long]$Seq, [int]$Number, [string]$Speaker = "warchief", [string]$Route = "command", [switch]$NoteOnly)
    $d = [ordered]@{ number = $Number; speaker = $Speaker; route = $Route; text = "Which way should it go?" }
    if ($NoteOnly) { $d["asks"] = $false }
    return (New-Record -Seq $Seq -Kind "message-said" -Data $d)
}
function New-Closed { param([long]$Seq, [int]$Number) return (New-Record -Seq $Seq -Kind "question-closed" -Data ([ordered]@{ number = $Number; outcome = "Done." })) }
function Get-Fold { param($Records) return (ConvertTo-HordeDecisionState -Records @($Records) -Definitions $defs) }
function Get-View { param($State, [int]$Number) return (ConvertTo-HordeDecisionView -Question $State.questions[$Number] -State $State) }
function Format-Asked { param($View) return (@(@($View.asked) | ForEach-Object { $_.how + "|" + $_.by + "|" + $_.note }) -join ";") }
function Get-Ignored { param($State) return (@($State.ignored | ForEach-Object { "" + $_.sequence + ": " + $_.reason }) -join " / ") }

Write-Host ""
Write-Host "--- first, and the record kind ---" -ForegroundColor Cyan
$s = Get-Fold @((New-Added 1 1 -AskedBy "orc-d"))
$v = Get-View $s 1
Check ((Format-Asked $v) -ceq "first|orc-d|" -and [int]$v.askedCount -eq 1 -and "$($v.lastAskedAt)" -ceq (Get-At 1) -and "$(@($v.asked)[0].at)" -ceq (Get-At 1)) "a question added is asked once: first, by its askedBy, at the record's time, which is its last-asked time"
Check ((Get-HordeDecisionEventKinds) -ccontains "question-reminded" -and (Get-HordeDecisionKindAbout -Kind "question-reminded") -ceq "question" -and (@((Get-HordeDecisionKindActors -Kind "question-reminded").roles) -join ",") -ceq "warchief") "question-reminded is a kind of this version, about one question, written by the keepers only"
Check ((Get-HordeDecisionAskedHows) -join "," -ceq "first,remind,thrall-reply,follow-up" -and (@($defs.resultSchema.definitions.asked.properties.how.enum) -join ",") -ceq ((Get-HordeDecisionAskedHows) -join ",")) "the four ways a question is asked are the rules' list, and the result schema's enum is the same list"

Write-Host ""
Write-Host "--- remind ---" -ForegroundColor Cyan
$s = Get-Fold @((New-Added 1 1), (New-Added 2 2), (New-Reminded 3 1 -Note "raised again in chat"), (New-Reminded 4 1))
$v = Get-View $s 1
Check ((Format-Asked $v) -ceq "first|orc-e|;remind|warchief|raised again in chat;remind|warchief|" -and [int]$v.askedCount -eq 3 -and "$($v.lastAskedAt)" -ceq (Get-At 4)) "each reminder appends a remind entry, by the record's actor, with its note or none; the last one's time is the last-asked time"
Check ("$($v.addedAt)" -ceq (Get-At 1) -and "$($v.state)" -ceq "open" -and "$($v.thread.turn)" -ceq "founder" -and [int]$v.wordingVersion -eq 1) "a reminder moves no wording, no state, no turn, and not when the question was added"
Check (@($v.history | Where-Object { $_.note -ceq "asked again: raised again in chat" -or $_.note -ceq "asked again" }).Count -eq 2 -and "$($v.updatedAt)" -ceq (Get-At 4)) "and each is a line of the question's history"
Check ((Format-Asked (Get-View $s 2)) -ceq "first|orc-e|") "CONTROL: the other question is not touched"
$s = Get-Fold @((New-Added 1 1), (New-Closed 2 1), (New-Reminded 3 1 -Note "once more"))
Check ((Format-Asked (Get-View $s 1)) -ceq "first|orc-e|" -and (Get-Ignored $s) -like "3: question 1 is closed, and only an open question is asked again*-FollowsUp 1") "A REMINDER OF A CLOSED QUESTION DOES NOT APPLY: it is ignored with the reason and what to do instead, and the list is as it was"
$s = Get-Fold @((New-Added 1 1), (New-Said 2 1 -Speaker "founder" -Route "chat-recorded"), (New-Reminded 3 1 -Note "once more"))
Check ((Format-Asked (Get-View $s 1)) -ceq "first|orc-e|" -and "$((Get-View $s 1).lastAskedAt)" -ceq (Get-At 1) -and (Get-Ignored $s) -like "3: question 1 has been answered and is off the founder's list, and a reminder would put it back in front of him*-FollowsUp 1*reply -Note*") "A REMINDER OF A QUESTION HE HAS ANSWERED DOES NOT APPLY: the turn is the keeper's, so it is ignored with the reason, and its last-asked time stays"
$s = Get-Fold @((New-Added 1 1), (New-Said 2 1 -Speaker "founder" -Route "chat-recorded"), (New-Said 3 1), (New-Reminded 4 1 -Note "once more"))
Check ((Format-Asked (Get-View $s 1)) -ceq "first|orc-e|;thrall-reply|warchief|;remind|warchief|once more" -and @($s.ignored).Count -eq 0) "TWIN: once the keeper's words have asked again and the turn is his once more, a reminder applies"

$s = Get-Fold @((New-Added 1 1), (New-Reminded 2 7))
Check (@($s.ignored).Count -eq 1 -and (Get-Ignored $s) -like "2: it is about question 7, and there is no question 7") "a reminder of a question that does not exist does not apply either"

Write-Host ""
Write-Host "--- the keeper's words that ask, and the words that do not ---" -ForegroundColor Cyan
$s = Get-Fold @((New-Added 1 1), (New-Said 2 1))
Check ((Format-Asked (Get-View $s 1)) -ceq "first|orc-e|;thrall-reply|warchief|" -and "$((Get-View $s 1).lastAskedAt)" -ceq (Get-At 2)) "THE KEEPER'S WORDS THAT ASK, under an open question, append a thrall-reply entry at their time"
$s = Get-Fold @((New-Added 1 1), (New-Said 2 1 -NoteOnly))
Check ((Format-Asked (Get-View $s 1)) -ceq "first|orc-e|" -and [int](Get-View $s 1).thread.count -eq 1) "a note asks nothing: no entry (the words are in the thread all the same)"
$s = Get-Fold @((New-Added 1 1), (New-Said 2 1 -Speaker "founder" -Route "chat-recorded"))
Check ((Format-Asked (Get-View $s 1)) -ceq "first|orc-e|") "the founder's own words are an answer, not an asking: no entry"
$s = Get-Fold @((New-Added 1 1), (New-Closed 2 1), (New-Said 3 1))
Check ((Format-Asked (Get-View $s 1)) -ceq "first|orc-e|" -and [int](Get-View $s 1).thread.count -eq 1) "the keeper's words under a closed question ask nobody: no entry"
$s = Get-Fold @((New-Added 1 1), (New-Said 2 1), (New-Said 3 1))
Check ((Format-Asked (Get-View $s 1)) -ceq "first|orc-e|;thrall-reply|warchief|" -and [int](Get-View $s 1).thread.count -eq 2) "AN EDIT ASKS ONCE: two asking replies, the second replacing the first, are one thrall-reply entry"
$s = Get-Fold @((New-Added 1 1), (New-Said 2 1), (New-Said 3 1 -Speaker "founder" -Route "chat-recorded"), (New-Said 4 1))
Check ((Format-Asked (Get-View $s 1)) -ceq "first|orc-e|;thrall-reply|warchief|;thrall-reply|warchief|") "TWIN: two asking replies with his words between them replace nothing, and are two entries"
$s = Get-Fold @((New-Added 1 1), (New-Said 2 1 -NoteOnly), (New-Said 3 1))
Check ((Format-Asked (Get-View $s 1)) -ceq "first|orc-e|;thrall-reply|warchief|" -and "$((Get-View $s 1).lastAskedAt)" -ceq (Get-At 3)) "and asking words that replace a note are an entry: the note asked nothing"

Write-Host ""
Write-Host "--- a follow-up ---" -ForegroundColor Cyan
$s = Get-Fold @((New-Added 1 1), (New-Added 2 2), (New-Added 3 3 -AskedBy "orc-c" -FollowsUp 1))
Check ((Format-Asked (Get-View $s 1)) -ceq "first|orc-e|;follow-up|orc-c|follow-up question 3" -and "$((Get-View $s 1).lastAskedAt)" -ceq (Get-At 3)) "A FOLLOW-UP asks the question it follows again: an entry on it, by the follow-up's askedBy, naming the follow-up, at its time"
Check ((Format-Asked (Get-View $s 3)) -ceq "first|orc-c|" -and (Format-Asked (Get-View $s 2)) -ceq "first|orc-e|") "CONTROL: the follow-up itself starts with first, and a question it does not follow is untouched"
$s = Get-Fold @((New-Added 1 1), (New-Closed 2 1), (New-Added 3 2 -FollowsUp 1))
Check ((Format-Asked (Get-View $s 1)) -ceq "first|orc-e|;follow-up|orc-e|follow-up question 2") "the question it follows may be closed: it was asked again all the same"
$s = Get-Fold @((New-Added 1 1), (New-Added 2 5 -FollowsUp 3))
Check ($s.questions.ContainsKey(5) -and @($s.ignored).Count -eq 0 -and (Format-Asked (Get-View $s 5)) -ceq "first|orc-e|") "a stored follow-up of a number the list cannot show is a question all the same, and nothing throws"

Write-Host ""
Write-Host "--- what a view carries: the cap, and a question built by hand ---" -ForegroundColor Cyan
$most = Get-HordeDecisionAskedViewMost
$records = New-Object System.Collections.ArrayList
[void]$records.Add((New-Added 1 1))
for ($i = 1; $i -le ($most + 50); $i++) { [void]$records.Add((New-Reminded (1 + $i) 1 -Note ("reminder " + $i))) }
$v = Get-View (Get-Fold $records) 1
$a = @($v.asked)
Check ($most -eq 100 -and [int]$v.askedCount -eq ($most + 51) -and $a.Count -eq $most -and $a[0].how -ceq "first" -and $a[1].note -ceq ("reminder " + 52) -and $a[$a.Count - 1].note -ceq ("reminder " + ($most + 50)) -and "$($v.lastAskedAt)" -ceq (Get-At ($most + 51))) "PAST THE CAP OF 100 a view carries the first and the newest 99, oldest first; askedCount says there are 151 and lastAskedAt is the newest"
$records = New-Object System.Collections.ArrayList
[void]$records.Add((New-Added 1 1))
for ($i = 1; $i -le ($most - 1); $i++) { [void]$records.Add((New-Reminded (1 + $i) 1)) }
$v = Get-View (Get-Fold $records) 1
Check ([int]$v.askedCount -eq $most -and @($v.asked).Count -eq $most) "CONTROL: at exactly 100 nothing is cut"
$byHand = [ordered]@{ number = 4; state = "open"; wordingVersion = 1; addedAt = "2026-09-01T10:00:00.0000000Z"; updatedAt = ""; closedAt = ""; outcome = ""; reopenReason = ""; importance = "normal"; blocks = "part"; followsUp = 0; partsAnswered = (New-Object System.Collections.Specialized.OrderedDictionary); history = (New-Object System.Collections.ArrayList); thread = (New-Object System.Collections.ArrayList); turn = "founder" }
foreach ($k in @((ConvertTo-HordeDecisionFields -Source @{ askedBy = "orc-a"; title = "t" }).GetEnumerator())) { $byHand[$k.Key] = $k.Value }
$v = $null
try { $v = ConvertTo-HordeDecisionView -Question $byHand -State (New-HordeDecisionState) } catch { }
Check ($null -ne $v -and (Format-Asked $v) -ceq "first|orc-a|" -and "$($v.lastAskedAt)" -ceq "2026-09-01T10:00:00.0000000Z" -and [int]$v.askedCount -eq 1) "A QUESTION WITH NO ASKED LIST - built by hand, not by the fold - reads as asked once, first, at addedAt"

Write-Host ""
Write-Host "--- the view against decision-result.v1 ---" -ForegroundColor Cyan
$s = Get-Fold @((New-Added 1 1), (New-Reminded 2 1 -Note "again"), (New-Said 3 1))
$v = Get-View $s 1
Check (@(Test-HordeSchema -Value (ConvertFrom-HordeJson (ConvertTo-Json -InputObject $v -Compress -Depth 20)) -Schema $defs.resultSchema.definitions.view -Root $defs.resultSchema).Count -eq 0) "a view with its asked list matches the result schema's view"
$bad = ConvertFrom-HordeJson (ConvertTo-Json -InputObject $v -Compress -Depth 20)
$bad.asked[1].how = "nagged"
Check (@(Test-HordeSchema -Value $bad -Schema $defs.resultSchema.definitions.view -Root $defs.resultSchema).Count -gt 0) "CONTROL: an entry whose how is none of the four does not"
$bare = ConvertFrom-HordeJson (ConvertTo-Json -InputObject $v -Compress -Depth 20)
$bare.PSObject.Properties.Remove("lastAskedAt")
Check (@(Test-HordeSchema -Value $bare -Schema $defs.resultSchema.definitions.view -Root $defs.resultSchema).Count -gt 0) "CONTROL: and a view without lastAskedAt does not: every view of this version carries it"

Write-Host ""
Write-Host "--- the note of a reminder ---" -ForegroundColor Cyan
Check (@(Test-HordeDecisionAskedNote -Text ("n" * 200)).Count -eq 0 -and @(Test-HordeDecisionAskedNote -Text "Raised again in chat: still blocks the release (PR 12).").Count -eq 0) "CONTROL: 200 characters of printable ASCII, punctuation and capitals included, are taken"
Check ((@(Test-HordeDecisionAskedNote -Text ("n" * 201)) -join " ") -like "*'note' is 201 characters long; the most is 200*") "201 are refused, with the count"
Check (@(Test-HordeDecisionAskedNote -Text ("caf" + [char]0x00E9)).Count -eq 1 -and @(Test-HordeDecisionAskedNote -Text ("a" + "`n" + "b")).Count -eq 1 -and @(Test-HordeDecisionAskedNote -Text ("a" + "`t" + "b")).Count -eq 1 -and @(Test-HordeDecisionAskedNote -Text ("a" + [char]0x7F)).Count -eq 1) "an accented letter, a line break, a tab and DEL are each refused"
Check (@(Test-HordeDecisionAskedNote -Text "   ").Count -eq 1 -and @(Test-HordeDecisionAskedNote -Text 5).Count -eq 1) "a blank note and one that is not text are refused"
Check (@(Test-HordeSchema -Value (ConvertFrom-HordeJson '{"id":"0123456789abcdef0123456789abcdef","actor":"warchief","number":1,"note":"x","when":"now"}') -Schema $defs.requestSchema.definitions.remind -Root $defs.requestSchema).Count -gt 0 -and @(Test-HordeSchema -Value (ConvertFrom-HordeJson '{"id":"0123456789abcdef0123456789abcdef","actor":"warchief","number":1,"note":"x"}') -Schema $defs.requestSchema.definitions.remind -Root $defs.requestSchema).Count -eq 0) "the remind request takes an id, the actor, the number and a note, and nothing else (CONTROL: the same less the extra member passes)"

Complete-HordeSuite -Success "a question's asked list: first, remind, a reply that asks and a follow-up; not a note, not the founder, not a closed question; capped in the view, never in the records"
