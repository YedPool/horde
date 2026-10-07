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
           Find = 'foreach ($f in @(Test-HordeDecisionSaying -Speaker $body["speaker"] -Route $body["route"] -Actor ([string]$Request.actor) -Text $body["text"])) { [void]$found.Add($f) }'
           Replace = '' }
        @{ Name = "who-records-is-not-asked"
           Find = '-Actor ([string]$Request.actor) -Text $body["text"]'
           Replace = '-Actor (@((Get-HordeDecisionKindActors -Kind "question-added").roles)[0]) -Text $body["text"]' }
        @{ Name = "wording-with-none-named-is-the-first"
           Find = 'if (-not $Data.Contains("wordingVersion")) { $Data["wordingVersion"] = [int]$List.questions[[int]$Data["number"]].wordingVersion }'
           Replace = 'if (-not $Data.Contains("wordingVersion")) { $Data["wordingVersion"] = 1 }' }
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
        # --- inbox: only what is handed back is marked ---
        @{ Name = "reading-marks"
           Find = 'if (-not [bool]$Data["mark"] -or $unread.Count -eq 0) {'
           Replace = 'if ($unread.Count -eq 0) {' }
        @{ Name = "marking-nothing-writes-a-record"
           Find = 'if (-not [bool]$Data["mark"] -or $unread.Count -eq 0) {'
           Replace = 'if (-not [bool]$Data["mark"]) {' }
        @{ Name = "marked-up-to-the-end-of-the-list"
           Find = 'data = [ordered]@{ reader = $reader; upTo = [long]$unread[-1].message.sequence } }'
           Replace = 'data = [ordered]@{ reader = $reader; upTo = [long]$List.lastSequence } }' }
        @{ Name = "bound-ignored"
           Find = 'if ([long]$Data["upTo"] -gt 0) { $bound = [long]$Data["upTo"] }'
           Replace = '' }
        @{ Name = "impossible-bound-thrown-on"
           Find = 'if (Test-HordeDecisionCount -Value $Request.upTo -Most (Get-HordeDecisionMaxSequence)) { $upTo = [long]$Request.upTo }'
           Replace = 'if ($true) { $upTo = [long]$Request.upTo }' }
        @{ Name = "marking-needs-no-id"
           Find = 'if ($mark -and -not $hasId) { [void]$found.Add('
           Replace = 'if ($false) { [void]$found.Add(' }
        @{ Name = "id-on-a-reading-inbox-ignored"
           Find = 'if (-not $mark -and $hasId) { [void]$found.Add('
           Replace = 'if ($false) { [void]$found.Add(' }
        @{ Name = "inbox-for-a-role-that-has-none"
           Find = 'if ($readers -cnotcontains ([string]$Request.actor)) { [void]$found.Add('
           Replace = 'if ($false) { [void]$found.Add(' }
        @{ Name = "marking-says-it-marked-nothing"
           Find = 'return (Get-HordeDecisionInboxMore -List $List -Items $items -Marked $items.Count)'
           Replace = 'return (Get-HordeDecisionInboxMore -List $List -Items $items -Marked 0)' }
        @{ Name = "marking-answered-with-what-is-unread-now"
           Find = '$items = @(Get-HordeDecisionMessagesFor -State $List -Reader "$($marking.reader)" -After ([long]$marking.from) -UpTo ([long]$marking.upTo))'
           Replace = '$items = @(Get-HordeDecisionMessagesFor -State $List -Reader "$($marking.reader)")' }
        @{ Name = "read-mark-given-a-question-number"
           Find = 'if ($about -ceq "question") { if ($hasNumber) { $data["number"] = [int]$number } else { $data["number"] = Get-HordeDecisionNextNumber -State $list } }'
           Replace = 'if ($hasNumber) { $data["number"] = [int]$number } else { $data["number"] = Get-HordeDecisionNextNumber -State $list }' }
        @{ Name = "repost-of-a-marking-given-a-question-number"
           Find = 'if ([int]$prior.number -ge 1) { $more["number"] = [int]$prior.number }'
           Replace = '$more["number"] = [int]$prior.number' }
        # --- the thread, as list and show hand it back ---
        @{ Name = "list-carries-every-message"
           Find = '[void]$views.Add((ConvertTo-HordeDecisionView -Question $question -State $State))'
           Replace = '[void]$views.Add((ConvertTo-HordeDecisionView -Question $question -State $State -Messages))' }
        @{ Name = "show-carries-no-message"
           Find = '$view = ConvertTo-HordeDecisionView -Question $State.questions[[int]$number] -State $State -Messages'
           Replace = '$view = ConvertTo-HordeDecisionView -Question $State.questions[[int]$number] -State $State' }
    )
}
