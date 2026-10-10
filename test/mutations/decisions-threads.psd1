# Mutations of decisions/Operations.ps1's conversation under a question: the operations say and inbox,
# and the thread that list and show hand back. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-threads.psd1
# Each removes one thing the person who speaks, or the session that reads him, relies on;
# test\test-decisions-threads.ps1 must fail for every one. It is a spec of its own, beside
# test\mutations\decisions-operations.psd1, because that suite holds a record open for ten seconds on
# every run and this one need not: a mutant of the conversation is judged in seconds.
@{
    Target = "decisions\Operations.ps1"
    Suite  = "test\test-decisions-threads.ps1"
    Mutations = @(
        # --- say ---
        @{ Name = "words-not-held-to-the-rules-of-saying"
           Find = 'foreach ($f in @(Test-HordeDecisionSaying -Speaker $body["speaker"] -Route $body["route"] -Actor ([string]$Request.actor) -Text $body["text"] -WordingStated ([bool]$stated) -EvidenceStated ([bool]$proven) -Evidence $evidence)) { [void]$found.Add($f) }'
           Replace = '' }
        @{ Name = "who-records-is-not-asked"
           Find = '-Actor ([string]$Request.actor) -Text $body["text"]'
           Replace = '-Actor (@((Get-HordeDecisionKindActors -Kind "question-added").roles)[0]) -Text $body["text"]' }
        @{ Name = "wording-guessed-when-none-is-stated"
           Find = '    $stated = Test-HordeDecisionMember -Object $Request -Name "wordingVersion"'
           Replace = '    $stated = Test-HordeDecisionMember -Object $Request -Name "wordingVersion"; if (-not $stated) { $body["wordingVersion"] = 1 }' }
        @{ Name = "rules-not-told-the-wording-is-unstated"
           Find = '-Text $body["text"] -WordingStated ([bool]$stated) -EvidenceStated'
           Replace = '-Text $body["text"] -WordingStated $true -EvidenceStated' }
        @{ Name = "impossible-wording-thrown-on"
           Find = 'if (Test-HordeDecisionCount -Value $Request.wordingVersion -Most (Get-HordeDecisionMaxNumber)) { $body["wordingVersion"] = [int]$Request.wordingVersion }'
           Replace = 'if ($true) { $body["wordingVersion"] = [int]$Request.wordingVersion }' }
        @{ Name = "answer-to-a-say-holds-no-message"
           Find = 'if ($entry.ContainsKey("parts")) { $beside = & $entry.parts $list $sequence; foreach ($k in @($beside.Keys)) { $more[$k] = $beside[$k] } }'
           Replace = '' }
        @{ Name = "repost-answered-without-what-it-recorded"
           Find = 'if ($entry.ContainsKey("parts")) { $again = & $entry.parts $list ([long]$prior.sequence); foreach ($k in @($again.Keys)) { $more[$k] = $again[$k] } }'
           Replace = '' }
        # --- who may write which kind of record ---
        @{ Name = "speakers-may-change-the-list"
           Find = '$allowed = Get-HordeDecisionKindActors -Kind $entry.kind'
           Replace = '$allowed = Get-HordeDecisionKindActors -Kind "message-said"' }
        @{ Name = "only-keepers-may-speak"
           Find = '$allowed = Get-HordeDecisionKindActors -Kind $entry.kind'
           Replace = '$allowed = Get-HordeDecisionKindActors -Kind "question-closed"' }
        # --- inbox only reads; mark-read marks up to the record named, and is idempotent ---
        @{ Name = "inbox-for-a-role-that-has-none"
           Find = '    if ($why -ne "") { return (Complete-HordeDecisionAnswer -Value (New-HordeDecisionResult -Operation "inbox" -Outcome "refused"'
           Replace = '    if ($false) { return (Complete-HordeDecisionAnswer -Value (New-HordeDecisionResult -Operation "inbox" -Outcome "refused"' }
        @{ Name = "inbox-holds-what-was-already-read"
           Find = '    foreach ($item in @(Get-HordeDecisionMessagesFor -State $State -Reader $reader)) {'
           Replace = '    foreach ($item in @(Get-HordeDecisionMessagesFor -State $State -Reader $reader -After 0)) {' }
        @{ Name = "inbox-does-not-say-its-last-record"
           Find = '        $last = [long]$item.message.sequence'
           Replace = '' }
        @{ Name = "inbox-goes-through-the-write-path"
           Find = '    inbox  = @{ writes = $false; read = "Get-HordeDecisionInboxAnswer" }'
           Replace = '    inbox  = @{ writes = $true; read = "Get-HordeDecisionInboxAnswer"; kind = "messages-read"; content = "Get-HordeDecisionMarkContent"; complete = "Complete-HordeDecisionMarkData"; parts = "Get-HordeDecisionMarkParts" }' }
        @{ Name = "marking-for-a-role-with-no-inbox"
           Find = '    if ($why -ne "") { [void]$found.Add($why) }'
           Replace = '' }
        @{ Name = "impossible-record-number-thrown-on"
           Find = 'if (Test-HordeDecisionCount -Value $Request.upTo -Most (Get-HordeDecisionMaxSequence)) { $upTo = [long]$Request.upTo }'
           Replace = 'if ($true) { $upTo = [long]$Request.upTo }' }
        @{ Name = "marking-again-writes-a-second-record"
           Find = '    if ($upTo -le (Get-HordeDecisionReadMark -State $List -Reader $reader)) {'
           Replace = '    if ($false) {' }
        @{ Name = "marking-up-to-where-it-is-already-read-refused-one-short"
           Find = '    if ($upTo -le (Get-HordeDecisionReadMark -State $List -Reader $reader)) {'
           Replace = '    if ($upTo -lt (Get-HordeDecisionReadMark -State $List -Reader $reader)) {' }
        @{ Name = "marked-up-to-the-end-of-the-list"
           Find = '    $upTo = [long]$Data["upTo"]'
           Replace = '    $upTo = [long]$List.lastSequence' }
        @{ Name = "marking-says-it-marked-nothing"
           Find = '    return [ordered]@{ upTo = [long]$marking.upTo; marked = $items.Count }'
           Replace = '    return [ordered]@{ upTo = [long]$marking.upTo; marked = 0 }' }
        @{ Name = "marking-counts-what-was-read-before-it"
           Find = '-After ([long]$marking.from) -UpTo ([long]$marking.upTo))'
           Replace = '-After 0 -UpTo ([long]$marking.upTo))' }
        @{ Name = "marking-that-marks-nothing-says-it-marked"
           Find = 'more = ([ordered]@{ upTo = $upTo; marked = 0 }); data = $null }'
           Replace = 'more = ([ordered]@{ upTo = $upTo; marked = 1 }); data = $null }' }
        @{ Name = "read-mark-given-a-question-number"
           Find = 'if ($about -ceq "question") { if ($hasNumber) { $data["number"] = [int]$number } else { $data["number"] = Get-HordeDecisionNextNumber -State $list } }'
           Replace = 'if ($hasNumber) { $data["number"] = [int]$number } else { $data["number"] = Get-HordeDecisionNextNumber -State $list }'
           Expect = "survives"
           Reason = "equivalent today: the one operation whose record is about the whole list (inbox) has a 'complete' step that replaces the record's data, so a question number put in before it never reaches the record. The guard is kept for the next such operation that has no such step, where the number would make the record fail its schema; it has nothing to be tested with until then" }
        @{ Name = "repost-of-a-marking-given-a-question-number"
           Find = 'if ([int]$prior.number -ge 1) { $more["number"] = [int]$prior.number }'
           Replace = '$more["number"] = [int]$prior.number' }
        # --- the thread, as list and show hand it back ---
        @{ Name = "list-carries-every-message"
           Find = '[void]$views.Add((ConvertTo-HordeDecisionView -Question $question -State $State -Messages:$withMessages))'
           Replace = '[void]$views.Add((ConvertTo-HordeDecisionView -Question $question -State $State -Messages))' }
        @{ Name = "show-carries-no-message"
           Find = '$view = ConvertTo-HordeDecisionView -Question $State.questions[[int]$number] -State $State -Messages'
           Replace = '$view = ConvertTo-HordeDecisionView -Question $State.questions[[int]$number] -State $State' }
    )
}
