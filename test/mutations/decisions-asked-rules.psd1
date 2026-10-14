# Mutations of decisions/Rules.ps1's WHEN A QUESTION WAS ASKED: the asked list the fold derives - first,
# remind, thrall-reply, follow-up - its cap in a view, and the note of a reminder. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-asked-rules.psd1
# test\test-decisions-asked.ps1 (the rules on records built in the suite, no store) must fail for each.
@{
    Target = "decisions\Rules.ps1"
    Suite  = "test\test-decisions-asked.ps1"
    Mutations = @(
        @{ Name = "a-closed-question-is-reminded"
           Find = '    if ($question.state -cne "open") { return ("question " + $question.number + " is " + $question.state + ", and only an open question is asked again. "'
           Replace = '    if ($false) { return ("question " + $question.number + " is " + $question.state + ", and only an open question is asked again. "' }
        @{ Name = "a-reminder-adds-no-entry"
           Find = '    Add-HordeDecisionAsked -Question $question -Ev $Ev -How "remind" -By "$($Ev.actor)" -Note $note'
           Replace = '' }
        @{ Name = "a-reminder-loses-its-note"
           Find = '    if (Test-HordeDecisionMember -Object $Ev.data -Name "note") { $note = [string]$Ev.data.note }'
           Replace = '' }
        @{ Name = "a-reminder-is-not-in-the-history"
           Find = '    Add-HordeDecisionHistory -Question $question -Ev $Ev -Note $(if ($note -ne "") { "asked again: " + $note } else { "asked again" })'
           Replace = '' }
        @{ Name = "any-speaker-asks-again"
           Find = '        if ($script:HordeDecisionNoteSpeakers -ccontains $speaker) { Add-HordeDecisionAsked -Question $question -Ev $Ev -How "thrall-reply" -By $speaker }'
           Replace = '        Add-HordeDecisionAsked -Question $question -Ev $Ev -How "thrall-reply" -By $speaker' }
        @{ Name = "a-reply-never-asks-again"
           Find = '        if ($script:HordeDecisionNoteSpeakers -ccontains $speaker) { Add-HordeDecisionAsked -Question $question -Ev $Ev -How "thrall-reply" -By $speaker }'
           Replace = '' }
        @{ Name = "a-follow-up-asks-nothing-again"
           Find = '    if ([int]$question.followsUp -ge 1 -and $State.questions.ContainsKey([int]$question.followsUp)) {'
           Replace = '    if ($false) {' }
        @{ Name = "a-follow-up-of-a-number-the-list-cannot-show-throws"
           Find = '    if ([int]$question.followsUp -ge 1 -and $State.questions.ContainsKey([int]$question.followsUp)) {'
           Replace = '    if ([int]$question.followsUp -ge 1) {' }
        @{ Name = "first-is-by-the-actor"
           Find = '    Add-HordeDecisionAsked -Question $question -Ev $Ev -How "first" -By "$($question.askedBy)"'
           Replace = '    Add-HordeDecisionAsked -Question $question -Ev $Ev -How "first" -By "$($Ev.actor)"' }
        @{ Name = "the-view-is-never-cut"
           Find = '    if ($all.Count -gt $script:HordeDecisionAskedViewMost) {'
           Replace = '    if ($false) {' }
        @{ Name = "the-cut-loses-the-first"
           Find = '$kept = @($all[0]) + @($all[($all.Count - $script:HordeDecisionAskedViewMost + 1)..($all.Count - 1)])'
           Replace = '$kept = @($all[($all.Count - $script:HordeDecisionAskedViewMost)..($all.Count - 1)])' }
        @{ Name = "the-count-is-what-the-view-kept"
           Find = '    $view["askedCount"] = $all.Count'
           Replace = '    $view["askedCount"] = @($kept).Count' }
        @{ Name = "last-asked-is-the-first-asking"
           Find = '    $view["lastAskedAt"] = "$($all[$all.Count - 1].at)"'
           Replace = '    $view["lastAskedAt"] = "$($all[0].at)"' }
        @{ Name = "a-question-built-by-hand-has-no-list"
           Find = '    $all = @([pscustomobject]@{ at = "$($Question.addedAt)"; how = "first"; by = "$($Question.askedBy)"; note = "" })'
           Replace = '    $all = @()' }
        @{ Name = "a-long-note-is-taken"
           Find = '    if ($Text.Length -gt $script:HordeDecisionAskedNoteChars) {'
           Replace = '    if ($Text.Length -gt 100000) {' }
        @{ Name = "a-note-of-200-is-refused"
           Find = '    if ($Text.Length -gt $script:HordeDecisionAskedNoteChars) {'
           Replace = '    if ($Text.Length -ge $script:HordeDecisionAskedNoteChars) {' }
        @{ Name = "any-character-is-taken-in-a-note"
           Find = '    if ($Text -cmatch ''[^\x20-\x7E]'') {'
           Replace = '    if ($Text -cmatch ''[\x00-\x08]'') {' }
        @{ Name = "a-blank-note-is-taken"
           Find = '    if ("$Text".Trim().Length -eq 0) {'
           Replace = '    if ($false) {' }
        @{ Name = "a-note-that-is-not-text-is-taken"
           Find = '    if ($Text -isnot [string]) { return @("''note'' is text") }'
           Replace = '    if ($Text -isnot [string]) { return @() }' }
        @{ Name = "a-fifth-way-to-be-asked"
           Find = '$script:HordeDecisionAskedHows = @("first", "remind", "thrall-reply", "follow-up")'
           Replace = '$script:HordeDecisionAskedHows = @("first", "remind", "thrall-reply", "follow-up", "nagged")' }
    )
}
