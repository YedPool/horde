# Mutations of decisions/Rules.ps1 for THE ANSWER GOES TO THE ONE WHO ASKED: who asked, the record of a
# routed answer, the acknowledgement that closes a question, and the hour's flag. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-route-rules.psd1
# test\test-decisions-route.ps1 must fail for each. A spec of its own beside decisions-rules.psd1, so
# these are judged by the suite that drives them.
@{
    Target = "decisions\Rules.ps1"
    Suite  = "test\test-decisions-route.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- who asked
        @{ Name = "an-orc-in-any-case"
           Find = '$script:HordeDecisionAskerOrcPattern = ''\AOrc ([A-Z])\z'''
           Replace = '$script:HordeDecisionAskerOrcPattern = ''(?i)\AOrc ([A-Z])\z''' }
        @{ Name = "any-name-starting-m-is-the-warchief"
           Find = '$script:HordeDecisionAskerWarchiefPattern = ''\A(M|Thrall)(\z|[ ,(])'''
           Replace = '$script:HordeDecisionAskerWarchiefPattern = ''\A(M|Thrall)''' }
        # --- a routed answer
        @{ Name = "an-answer-routed-twice"
           Find = 'if ($null -ne $before) { return ("answer record "'
           Replace = 'if ($false) { return ("answer record "' }
        @{ Name = "any-record-of-the-question-routed"
           Find = 'if ($null -eq $said -or "$($said.speaker)" -cne $script:HordeDecisionFirstTurn -or "$($said.act)" -ne "") {'
           Replace = 'if ($null -eq $said) {' }
        @{ Name = "routes-not-shown"
           Find = 'if ((Test-HordeDecisionMember -Object $Question -Name "routes") -and @($Question.routes).Count -gt 0) {'
           Replace = 'if ($false) {' }
        # --- the answer that stands, and the hour
        @{ Name = "an-act-stands-as-the-answer"
           Find = 'if ("$($message.speaker)" -ceq $script:HordeDecisionFirstTurn -and "$($message.act)" -eq "") { $standing = $message }'
           Replace = 'if ("$($message.speaker)" -ceq $script:HordeDecisionFirstTurn) { $standing = $message }' }
        @{ Name = "waiting-to-close-whoever-s-turn"
           Find = 'if ($Turn -cne "$($script:HordeDecisionSpeakers[$script:HordeDecisionFirstTurn].then)") { return $false }'
           Replace = '' }
        @{ Name = "flagged-before-the-hour"
           Find = 'if ($waited -lt $Minutes) { continue }'
           Replace = '' }
        @{ Name = "an-answer-routed-counts-as-reminded"
           Find = '-and "$($_.purpose)" -ceq "nudge" }).Count -gt 0)'
           Replace = ' }).Count -gt 0)' }
        # --- the acknowledgement
        @{ Name = "an-ack-on-a-closed-question"
           Find = 'if ($question.state -cne "open") { return ("question " + $question.number + " is already " + $question.state + ": an'
           Replace = 'if ($false) { return ("question " + $question.number + " is already " + $question.state + ": an' }
        @{ Name = "an-ack-with-no-answer"
           Find = 'if ($null -eq $standing) { return ("question " + $question.number + " has no answer of "'
           Replace = 'if ($false) { return ("question " + $question.number + " has no answer of "' }
        @{ Name = "an-ack-while-it-waits-for-him"
           Find = 'if (-not (Test-HordeDecisionAwaitingClose -Question $question -Turn "$($question.turn)")) { return ("question " + $question.number + " is still waiting'
           Replace = 'if ($false) { return ("question " + $question.number + " is still waiting' }
        @{ Name = "an-ack-of-a-replaced-answer"
           Find = 'if ([long]$Ev.data.answer -ne [long]$standing.sequence) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-orc-acks"
           Find = 'if ($asker.seat -cne "orc" -or $asker.label -cne $by) {'
           Replace = 'if ($asker.seat -cne "orc") {' }
        @{ Name = "an-ack-leaves-the-turn"
           Find = '$question["turn"] = $script:HordeDecisionNoTurn'
           Replace = '' }
        @{ Name = "no-closer-recorded"
           Find = '$question.closedBy = "Orc " + $by'
           Replace = '$question.closedBy = ""' }
    )
}
