# Mutations of decisions/Rules.ps1 for "Change my answer": a correction is new words in a new record
# that names the record of the answer it corrects. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-correct-rules.psd1
# test\test-decisions-rules.ps1 must fail for each.
@{
    Target = "decisions\Rules.ps1"
    Suite  = "test\test-decisions-rules.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-correction-of-any-number-may-be-said"
           Find = '        if (-not (Test-HordeDecisionCount -Value $Request.corrects -Most (Get-HordeDecisionMaxSequence))) { [void]$found.Add("''corrects'' is the record number of the answer corrected:'
           Replace = '        if ($false) { [void]$found.Add("''corrects'' is the record number of the answer corrected:' }
        @{ Name = "the-keeper-corrects-an-answer"
           Find = '        elseif ($Speaker -cne $script:HordeDecisionFirstTurn) { [void]$found.Add("only " + (Get-HordeDecisionSpeakerShown -Speaker $script:HordeDecisionFirstTurn) + " corrects an answer, and only his own") }'
           Replace = '' }
        @{ Name = "an-act-corrects-an-answer"
           Find = '        elseif (Test-HordeDecisionMember -Object $Request -Name "act") { [void]$found.Add("an act corrects no answer: give ''corrects'' or ''act'', not both") }'
           Replace = '' }
        @{ Name = "a-correction-of-nothing-applies"
           Find = '        if ($null -eq $was) { return ("it corrects record " + $corrects + ", which is not something said under question " + $question.number) }'
           Replace = '        if ($null -eq $was) { $was = [pscustomobject]@{ speaker = $speaker; act = ""; part = $part } }' }
        @{ Name = "a-correction-of-anothers-words-applies"
           Find = '        if ("$($was.speaker)" -cne $speaker -or "$($was.act)" -ne "") { return'
           Replace = '        if ("$($was.act)" -ne "") { return' }
        @{ Name = "a-correction-of-an-act-applies"
           Find = '        if ("$($was.speaker)" -cne $speaker -or "$($was.act)" -ne "") { return'
           Replace = '        if ("$($was.speaker)" -cne $speaker) { return' }
        @{ Name = "a-correction-answers-another-part"
           Find = '        if ("$($was.part)" -cne $part) { return ("it corrects record "'
           Replace = '        if ($false) { return ("it corrects record "' }
        @{ Name = "the-record-corrected-is-not-kept-with-the-message"
           Find = '        corrects = $corrects'
           Replace = '        corrects = [long]0' }
        @{ Name = "a-correction-does-not-say-it-replaces"
           Find = '    $replaces = ($corrects -gt 0)'
           Replace = '    $replaces = $false' }
        @{ Name = "the-message-shown-names-no-record-corrected"
           Find = '        corrects = [long]$Message.corrects'
           Replace = '        corrects = [long]0' }
        @{ Name = "a-correction-beyond-any-record-is-cast"
           Find = 'counts = @{ wordingVersion = "number"; corrects = "sequence" } }'
           Replace = 'counts = @{ wordingVersion = "number" } }' }
    )
}
