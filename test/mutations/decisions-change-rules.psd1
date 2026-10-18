# Mutations of decisions/Rules.ps1 for THE FOUNDER CHANGES HIS ANSWER (T-0152): what a change is, when it is
# refused (once the question is closed), who is named as having acted, and the Orc's reply to a changed
# answer. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-change-rules.psd1
# test\test-decisions-change.ps1 must fail for each. Each find string occurs once.
@{
    Target = "decisions\Rules.ps1"
    Suite  = "test\test-decisions-change.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- what a change is
        @{ Name = "an-answer-to-another-part-counts-as-the-one-changed"
           Find = '            if ("$($before.part)" -cne $part) { continue }'
           Replace = '' }
        @{ Name = "the-keepers-words-count-as-an-earlier-answer-of-his"
           Find = '            if ("$($before.speaker)" -cne $speaker -or "$($before.act)" -ne "" -or -not [bool]$before.asks) { continue }'
           Replace = '            if ("$($before.act)" -ne "" -or -not [bool]$before.asks) { continue }' }
        @{ Name = "an-act-of-his-counts-as-an-earlier-answer"
           Find = '            if ("$($before.speaker)" -cne $speaker -or "$($before.act)" -ne "" -or -not [bool]$before.asks) { continue }'
           Replace = '            if ("$($before.speaker)" -cne $speaker -or -not [bool]$before.asks) { continue }' }
        @{ Name = "a-change-forgets-the-old-words"
           Find = '            $changedFromText = [string]$before.text'
           Replace = '            $changedFromText = ""' }
        @{ Name = "a-change-names-itself-as-the-answer-it-replaces"
           Find = '            $changedFrom = [long]$before.sequence'
           Replace = '            $changedFrom = [long]$last.sequence' }
        @{ Name = "the-first-answer-is-marked-a-change"
           Find = '    if ($last.act -eq "" -and $last.asks -and $speaker -ceq $script:HordeDecisionFirstTurn) {'
           Replace = '    if ($last.act -eq "" -and $last.asks -and $speaker -ceq $script:HordeDecisionFirstTurn -and $false) {' }
        @{ Name = "the-keepers-reply-is-marked-a-change-of-his-answer"
           Find = '    if ($last.act -eq "" -and $last.asks -and $speaker -ceq $script:HordeDecisionFirstTurn) {'
           Replace = '    if ($last.act -eq "" -and $last.asks) {' }
        @{ Name = "the-message-view-drops-the-old-words"
           Find = '        $messageView["changedFromText"] = [string]$Message.changedFromText'
           Replace = '' }
        @{ Name = "the-message-view-drops-the-record-replaced"
           Find = '        $messageView["changedFrom"] = [long]$Message.changedFrom'
           Replace = '' }
        # --- refused once closed
        @{ Name = "a-closed-question-takes-the-change"
           Find = '    if ("$($Question.state)" -ceq "open") { return "" }'
           Replace = '    return ""' }
        @{ Name = "a-first-answer-to-a-closed-question-is-refused-as-a-change"
           Find = '    if ($earlier.Count -eq 0) { return "" }'
           Replace = '' }
        @{ Name = "his-act-under-a-closed-question-is-refused-as-a-change"
           Find = '    if ($Speaker -cne $script:HordeDecisionFirstTurn -or $Act -ne "" -or -not $Asks) { return "" }'
           Replace = '    if ($Speaker -cne $script:HordeDecisionFirstTurn -or -not $Asks) { return "" }' }
        @{ Name = "the-keepers-note-under-a-closed-question-is-refused-as-a-change"
           Find = '    if ($Speaker -cne $script:HordeDecisionFirstTurn -or $Act -ne "" -or -not $Asks) { return "" }'
           Replace = '    if ($Act -ne "" -or -not $Asks) { return "" }' }
        @{ Name = "a-change-to-one-part-is-judged-against-the-whole-question"
           Find = '-and (Test-HordeDecisionMessageAuthorizes -Message $_) -and "$($_.part)" -ceq $Part })'
           Replace = '-and (Test-HordeDecisionMessageAuthorizes -Message $_) })' }
        @{ Name = "the-refusal-does-not-say-who-acted"
           Find = '    return ("This question is closed - " + (Get-HordeDecisionActedBy -Question $Question) + " has acted on it. To change course, ask a follow-up.")'
           Replace = '    return ("This question is closed - the work has been acted on. To change course, ask a follow-up.")' }
        @{ Name = "the-refusal-does-not-say-what-to-do-instead"
           Find = ' has acted on it. To change course, ask a follow-up.")'
           Replace = ' has acted on it.")' }
        @{ Name = "a-question-closed-by-hand-never-names-the-orc-that-asked"
           Find = '    if ($asker.seat -ceq "orc") { return $asker.shown }'
           Replace = '' }
        @{ Name = "the-closer-is-not-the-one-named"
           Find = '    if ($closer -ne "") { return $closer }'
           Replace = '' }
        @{ Name = "the-view-says-nothing-of-who-acted"
           Find = '    if ("$($Question.state)" -cne "open") { $view["actedBy"] = (Get-HordeDecisionActedBy -Question $Question) }'
           Replace = '' }
        # --- the Orc's reply
        @{ Name = "any-orc-may-reply-to-a-change"
           Find = '    if ($asker.label -cne $by -or $asker.seat -cne "orc") { return ("question " + $question.number + " was asked by ''" + $question.askedBy + "'', not by Orc " + $by + ": only the Orc that asked it says what became of a changed answer") }'
           Replace = '' }
        @{ Name = "a-first-answer-takes-a-reply"
           Find = 'or [long]$said.changedFrom -lt 1 -or'
           Replace = 'or $false -or' }
        @{ Name = "cannot-undo-needs-no-reason"
           Find = '[bool]$script:HordeDecisionChangeReplies[$reply].needsWhy -and $why.Trim() -eq "")'
           Replace = '$false)' }
        @{ Name = "a-reason-is-taken-where-none-is-needed"
           Find = '-not [bool]$script:HordeDecisionChangeReplies[$reply].needsWhy -and $why -ne "")'
           Replace = '$false)' }
        @{ Name = "a-reply-that-is-none-of-the-three-is-taken"
           Find = '    if (-not $script:HordeDecisionChangeReplies.Contains($reply)) {'
           Replace = '    if ($false) {' }
        @{ Name = "the-reply-is-not-in-the-history"
           Find = '    Add-HordeDecisionHistory -Question $question -Ev $Ev -Note ("answer change replied by Orc " + $by + ": " + $script:HordeDecisionChangeReplies[$reply].shown)'
           Replace = '' }
        @{ Name = "the-oldest-reply-stands"
           Find = '        $reply = @($Question.changeReplies | Where-Object { [long]$_.answer -eq [long]$m.sequence }) | Select-Object -Last 1'
           Replace = '        $reply = @($Question.changeReplies | Where-Object { [long]$_.answer -eq [long]$m.sequence }) | Select-Object -First 1' }
        @{ Name = "a-reply-belongs-to-every-change"
           Find = '        $reply = @($Question.changeReplies | Where-Object { [long]$_.answer -eq [long]$m.sequence }) | Select-Object -Last 1'
           Replace = '        $reply = @($Question.changeReplies) | Select-Object -Last 1' }
        @{ Name = "a-reply-is-shown-by-its-code-and-not-in-words"
           Find = 'replyShown = $(if ($null -ne $entry) { "$($entry.shown)" } else { "$($reply.reply)" })'
           Replace = 'replyShown = "$($reply.reply)"' }
        @{ Name = "a-question-no-orc-asked-names-an-orc-to-wait-for"
           Find = 'orcShown = $(if ($asker.seat -ceq "orc") { $asker.shown } else { "" })'
           Replace = 'orcShown = $asker.shown' }
        @{ Name = "the-view-omits-the-changes"
           Find = '    if ($changes.Count -gt 0) { $view["answerChanges"] = $changes }'
           Replace = '' }
        @{ Name = "the-reply-is-written-by-anyone"
           Find = '    "answer-change-replied" = @{ data = "answer-change-replied"; words = ""; apply = "Step-HordeDecisionChangeReplied"; about = "question"; actors = "ackers"; counts = @{ answer = "sequence" } }'
           Replace = '    "answer-change-replied" = @{ data = "answer-change-replied"; words = ""; apply = "Step-HordeDecisionChangeReplied"; about = "question"; actors = "keepers"; counts = @{ answer = "sequence" } }' }
        # --- the coordinator's ruling of 2026-10-17: only a replacement of his answer is refused after close
        @{ Name = "his-chat-words-are-refused-under-a-closed-question-as-a-change"
           Find = '    if ($script:HordeDecisionAnswerRoutes -cnotcontains $Route) { return "" }'
           Replace = '' }
        # --- a question that needs a passkey is authorized only by a passkey
        @{ Name = "chat-words-authorize-a-passkey-question"
           Find = '-and $question["needsPasskey"] -eq $true) { $false } else { $true })'
           Replace = '-and $question["needsPasskey"] -eq $true) { $true } else { $true })' }
        @{ Name = "chat-words-stand-as-the-answer-to-a-passkey-question"
           Find = ' -and (Test-HordeDecisionMessageAuthorizes -Message $message)) { $standing = $message }'
           Replace = ') { $standing = $message }' }
        @{ Name = "chat-words-pass-the-turn-on-a-passkey-question"
           Find = ' -and $last.act -eq "" -and $last.authorizes) {'
           Replace = ' -and $last.act -eq "") {' }
        @{ Name = "the-view-does-not-say-the-words-are-not-a-passkey-answer"
           Find = '$messageView["notPasskey"] = $true'
           Replace = '' }
        # --- M1: who is waited for, and what counts as a reply
        @{ Name = "a-reply-never-counts-so-the-ack-is-never-allowed"
           Find = '        $replied = (@($Question.changeReplies | Where-Object { [long]$_.answer -eq [long]$m.sequence }).Count -gt 0)'
           Replace = '        $replied = $false' }
        @{ Name = "a-question-no-orc-asked-waits-for-an-orc-reply"
           Find = '    if ($asker.seat -cne "orc") { return $null }'
           Replace = '' }
    )
}
