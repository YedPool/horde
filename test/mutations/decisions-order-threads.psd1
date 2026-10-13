# Mutations of decisions/Operations.ps1 for the founder's rules of 2026-10-12, the part said under a
# question: a part answered by a record of its own, and the keeper's words that ask, refused once he
# has answered. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-order-threads.psd1
# test\test-decisions-threads.ps1 must fail for each.
@{
    Target = "decisions\Operations.ps1"
    Suite  = "test\test-decisions-threads.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- an answered question is never put back ---
        @{ Name = "the-keeper-asks-again-under-an-answered-question"
           Find = '        if ("$($question.state)" -ceq "open" -and "$($question.turn)" -cne (Get-HordeDecisionFirstTurn)) {'
           Replace = '        if ($false) {' }
        @{ Name = "the-keeper-may-not-ask-while-it-is-still-his-turn"
           Find = '        if ("$($question.state)" -ceq "open" -and "$($question.turn)" -cne (Get-HordeDecisionFirstTurn)) {'
           Replace = '        if ("$($question.state)" -ceq "open") {' }
        @{ Name = "words-under-a-closed-question-are-refused-as-asking"
           Find = '        if ("$($question.state)" -ceq "open" -and "$($question.turn)" -cne (Get-HordeDecisionFirstTurn)) {'
           Replace = '        if ("$($question.turn)" -cne (Get-HordeDecisionFirstTurn)) {' }
        @{ Name = "a-note-is-refused-as-asking"
           Find = '    $asking = (-not $Data.Contains("asks")) -and (-not $Data.Contains("act"))'
           Replace = '    $asking = (-not $Data.Contains("act"))' }
        @{ Name = "his-own-words-are-refused-as-asking"
           Find = '    if ($asking -and (Get-HordeDecisionNoteSpeakers) -ccontains "$($Data[''speaker''])" -and $List.questions.ContainsKey($number)) {'
           Replace = '    if ($asking -and $List.questions.ContainsKey($number)) {' }
        @{ Name = "the-refusal-does-not-say-to-ask-a-follow-up"
           Find = 'and words that ask him something would put it back in front of him. " + ($script:HordeDecisionFollowUpAdvice -f $number) + " To tell him'
           Replace = 'and words that ask him something would put it back in front of him. To tell him' }
        @{ Name = "the-refusal-does-not-say-to-leave-a-note"
           Find = ' + " To tell him something that asks nothing, say it as a note (reply -Note)"); write = $false; more = $null; data = $null }'
           Replace = '); write = $false; more = $null; data = $null }' }
        @{ Name = "say-is-not-asked-whether-the-list-allows-it"
           Find = 'content = "Get-HordeDecisionSayContent";   complete = "Complete-HordeDecisionSayData"; parts = "Get-HordeDecisionSayParts" }'
           Replace = 'content = "Get-HordeDecisionSayContent";   parts = "Get-HordeDecisionSayParts" }' }
        # --- a part answered ---
        @{ Name = "the-part-answered-is-not-recorded"
           Find = '    if ((Test-HordeDecisionMember -Object $Request -Name "part") -and $Request.part -is [string]) { $body["part"] = [string]$Request.part }'
           Replace = '' }
        @{ Name = "the-part-is-not-part-of-what-makes-a-request-the-same"
           Find = '    return [pscustomobject]@{ body = $body; findings = @($found); unhashed = @("evidence", "signedBy") }'
           Replace = '    return [pscustomobject]@{ body = $body; findings = @($found); unhashed = @("evidence", "signedBy", "part") }' }
    )
}
