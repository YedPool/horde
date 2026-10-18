# Mutations of decisions/Route.ps1 for THE FOUNDER CHANGES HIS ANSWER (T-0152): the notice the asking Orc is
# routed when the founder changes his answer - that it is a change, the old and the new words, the time, the
# exact reply commands, and who is given them. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-change-route.psd1
# test\test-decisions-change.ps1 must fail for each. Each find string occurs once.
@{
    Target = "decisions\Route.ps1"
    Suite  = "test\test-decisions-change.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-changed-answer-is-announced-as-a-plain-answer"
           Find = '    $headWords = $(if ($unsigned) { "FOUNDER''S CHAT WORDS, NOT A PASSKEY ANSWER" } elseif ($changed) { "FOUNDER CHANGED HIS ANSWER" } else { "FOUNDER ANSWER" })'
           Replace = '    $headWords = $(if ($unsigned) { "FOUNDER''S CHAT WORDS, NOT A PASSKEY ANSWER" } else { "FOUNDER ANSWER" })' }
        @{ Name = "chat-words-are-announced-under-the-plain-answer-header"
           Find = '    $headWords = $(if ($unsigned) { "FOUNDER''S CHAT WORDS, NOT A PASSKEY ANSWER" } elseif ($changed) { "FOUNDER CHANGED HIS ANSWER" } else { "FOUNDER ANSWER" })'
           Replace = '    $headWords = $(if ($unsigned) { "FOUNDER ANSWER" } elseif ($changed) { "FOUNDER CHANGED HIS ANSWER" } else { "FOUNDER ANSWER" })' }
        @{ Name = "the-passkey-notice-promises-a-routing-it-cannot-keep"
           Find = 'A passkey answer, if he gives one before this question is closed, will be routed to you.'
           Replace = 'You will be sent his passkey answer when he gives it.' }
        @{ Name = "the-old-words-are-left-out-of-the-notice"
           Find = '        [void]$lines.Add("His OLD words (record " + $m.changedFrom + "):")'
           Replace = '' }
        @{ Name = "the-old-words-are-the-new-ones"
           Find = '        foreach ($l in @(([string]$m.changedFromText) -split "\r\n|\r|\n")) { [void]$lines.Add(("> " + $l)) }'
           Replace = '        foreach ($l in @(([string]$m.text) -split "\r\n|\r|\n")) { [void]$lines.Add(("> " + $l)) }' }
        @{ Name = "the-new-words-are-not-labelled"
           Find = '        [void]$lines.Add("His NEW words (record " + $seq + "):")'
           Replace = '' }
        @{ Name = "the-time-of-the-change-is-left-out"
           Find = '        [void]$lines.Add("He CHANGED his answer at " + $m.at + ": record " + $seq + " replaces record " + $m.changedFrom + ". If you already acted on the first one, it may need undoing.")'
           Replace = '        [void]$lines.Add("He CHANGED his answer: record " + $seq + " replaces record " + $m.changedFrom + ". If you already acted on the first one, it may need undoing.")' }
        @{ Name = "the-undoing-command-says-not-acted"
           Find = '" -Reply undoing") -HordeHome $HordeHome))'
           Replace = '" -Reply not-acted") -HordeHome $HordeHome))' }
        @{ Name = "the-cannot-undo-command-has-no-reason-to-fill-in"
           Find = ' -Reply cannot-undo -Why ''why it cannot be undone, in one line''") -HordeHome $HordeHome))'
           Replace = ' -Reply cannot-undo") -HordeHome $HordeHome))' }
        @{ Name = "the-reply-commands-name-the-wrong-answer"
           Find = '" -Answer " + $seq + " -Reply not-acted") -HordeHome $HordeHome))'
           Replace = '" -Answer " + $m.changedFrom + " -Reply not-acted") -HordeHome $HordeHome))' }
        @{ Name = "the-warchief-is-given-a-reply-command-only-an-orc-can-use"
           Find = '    elseif ($changed -and $mine) {'
           Replace = '    elseif ($changed) {' }
        @{ Name = "an-orc-is-given-no-reply-command"
           Find = '    elseif ($changed -and $mine) {'
           Replace = '    elseif ($changed -and $false) {' }
        @{ Name = "the-analyst-is-not-told-it-is-a-change"
           Find = '    $changedNote = $(if ($null -ne $Item.answer.PSObject.Properties["changedFrom"] -and [long]$Item.answer.changedFrom -ge 1) {'
           Replace = '    $changedNote = $(if ($false) {' }
        # --- the old words get "> " on every line, for every kind of line break (review of PR 335, S2)
        @{ Name = "the-old-words-are-cut-at-lf-only"
           Find = '        foreach ($l in @(([string]$m.changedFromText) -split "\r\n|\r|\n")) { [void]$lines.Add(("> " + $l)) }'
           Replace = '        foreach ($l in @(([string]$m.changedFromText) -split "\n")) { [void]$lines.Add(("> " + $l)) }' }
        @{ Name = "the-old-words-are-cut-at-crlf-and-lf-but-not-a-lone-cr"
           Find = '        foreach ($l in @(([string]$m.changedFromText) -split "\r\n|\r|\n")) { [void]$lines.Add(("> " + $l)) }'
           Replace = '        foreach ($l in @(([string]$m.changedFromText) -split "\r\n|\n")) { [void]$lines.Add(("> " + $l)) }' }
        @{ Name = "the-old-words-lose-their-prefix"
           Find = '        foreach ($l in @(([string]$m.changedFromText) -split "\r\n|\r|\n")) { [void]$lines.Add(("> " + $l)) }'
           Replace = '        foreach ($l in @(([string]$m.changedFromText) -split "\r\n|\r|\n")) { [void]$lines.Add($l) }' }
        # --- chat words under a question that needs a passkey are said plainly not to be a passkey answer
        @{ Name = "chat-words-on-a-passkey-question-are-announced-as-an-answer"
           Find = '    $unsigned = ($null -ne $m.PSObject.Properties["notPasskey"] -and [bool]$m.notPasskey)'
           Replace = '    $unsigned = $false' }
    )
}
