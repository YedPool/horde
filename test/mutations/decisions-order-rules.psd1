# Mutations of decisions/Rules.ps1 for the founder's rules of 2026-10-12: the two words beside a
# question (importance, blocks) and their ranking, a question of parts answered part by part, and the
# context a follow-up carries. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-order-rules.psd1
# test\test-decisions-rules.ps1 must fail for each. A spec of its own beside decisions-rules.psd1, so
# that these are judged without the hundred and fifty mutants of the rules that did not change.
@{
    Target = "decisions\Rules.ps1"
    Suite  = "test\test-decisions-rules.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- the two words, and their plain words ---
        @{ Name = "the-default-importance-is-high"
           Find = '$script:HordeDecisionDefaultImportance = "normal"'
           Replace = '$script:HordeDecisionDefaultImportance = "high"' }
        @{ Name = "the-default-blocking-is-all"
           Find = '$script:HordeDecisionDefaultBlocks = "part"'
           Replace = '$script:HordeDecisionDefaultBlocks = "all"' }
        @{ Name = "the-default-importance-carries-a-mark"
           Find = '    normal = @{ shown = "" }'
           Replace = '    normal = @{ shown = "Normal" }' }
        @{ Name = "the-default-blocking-carries-a-mark"
           Find = '    part = @{ shown = "" }'
           Replace = '    part = @{ shown = "Blocks some work" }' }
        @{ Name = "importances-out-of-their-order"
           Find = 'function Get-HordeDecisionImportances { return @($script:HordeDecisionImportances.Keys) }'
           Replace = 'function Get-HordeDecisionImportances { return @($script:HordeDecisionImportances.Keys | Sort-Object) }' }
        @{ Name = "blockings-out-of-their-order"
           Find = 'function Get-HordeDecisionBlockings { return @($script:HordeDecisionBlockings.Keys) }'
           Replace = 'function Get-HordeDecisionBlockings { return @($script:HordeDecisionBlockings.Keys | Sort-Object -Descending) }' }
        @{ Name = "a-blocking-shown-from-the-importances"
           Find = '    if ($Name -ceq "blocks") { $table = $script:HordeDecisionBlockings }'
           Replace = '' }
        @{ Name = "a-later-word-shown-as-nothing"
           Find = '    if ($null -eq $entry) { return $Word }'
           Replace = '    if ($null -eq $entry) { return "" }' }
        @{ Name = "any-text-is-a-rank-word"
           Find = '    if ($Word -is [string] -and $words -ccontains $Word) { return @() }'
           Replace = '    if ($Word -is [string]) { return @() }' }
        @{ Name = "a-rank-word-in-any-case"
           Find = '    if ($Word -is [string] -and $words -ccontains $Word) { return @() }'
           Replace = '    if ($Word -is [string] -and $words -contains $Word) { return @() }' }
        @{ Name = "a-blocking-checked-against-the-importances"
           Find = '    if ($Name -ceq "blocks") { $words = @($script:HordeDecisionBlockings.Keys) }'
           Replace = '' }
        # --- a question added: what stands beside it ---
        @{ Name = "the-stated-importance-is-not-read"
           Find = '    if (Test-HordeDecisionMember -Object $Ev.data -Name "importance") { $question["importance"] = [string]$Ev.data.importance }'
           Replace = '' }
        @{ Name = "the-stated-blocking-is-not-read"
           Find = '    if (Test-HordeDecisionMember -Object $Ev.data -Name "blocks") { $question["blocks"] = [string]$Ev.data.blocks }'
           Replace = '' }
        @{ Name = "what-a-question-follows-is-not-read"
           Find = '    if (Test-HordeDecisionMember -Object $Ev.data -Name "followsUp") { $question["followsUp"] = [int]$Ev.data.followsUp }'
           Replace = '' }
        # --- ranking ---
        @{ Name = "a-closed-question-is-ranked"
           Find = '    if ($question.state -cne "open") { return ("question " + $question.number + " is " + $question.state + ", and only an open question is ranked: nobody is reading a list it is not in") }'
           Replace = '' }
        @{ Name = "a-ranking-that-changes-nothing-applies"
           Find = '        if ("$($question[$name])" -ceq $word) { continue }'
           Replace = '' }
        @{ Name = "a-ranking-of-nothing-is-history"
           Find = '    if ($changed.Count -eq 0) { return ("it changes nothing: question " + $question.number + " already has that importance and that blocking") }'
           Replace = '' }
        @{ Name = "a-ranking-leaves-the-history-silent"
           Find = '    Add-HordeDecisionHistory -Question $question -Ev $Ev -Note ("ranked: " + ($changed -join ", "))'
           Replace = '    Add-HordeDecisionHistory -Question $question -Ev $Ev -Note "ranked"' }
        @{ Name = "a-ranking-does-not-change-the-word"
           Find = '        $question[$name] = $word'
           Replace = '' }
        # --- the parts of a question ---
        @{ Name = "any-kind-of-question-has-parts"
           Find = '    if ("$(Get-HordeDecisionMember -Object $Question -Name ''kind'')" -cne $script:HordeDecisionPartsKind) { return @() }'
           Replace = '' }
        @{ Name = "one-part-is-parts"
           Find = '    if ($items.Count -lt 2) { return @() }'
           Replace = '    if ($items.Count -lt 1) { return @() }' }
        @{ Name = "a-part-keeps-its-mark-in-its-words"
           Find = '        if ($mark.Success) { $letter = $mark.Groups[1].Value; $words = $text.Substring($mark.Length) }'
           Replace = '        if ($mark.Success) { $letter = $mark.Groups[1].Value }' }
        @{ Name = "an-unmarked-part-takes-no-letter"
           Find = '        elseif ($i -lt 26) { $letter = [string][char](97 + $i) }'
           Replace = '        elseif ($i -lt 0) { $letter = [string][char](97 + $i) }' }
        @{ Name = "a-twenty-seventh-part-takes-a-letter-that-is-none"
           Find = '        elseif ($i -lt 26) { $letter = [string][char](97 + $i) }'
           Replace = '        elseif ($i -lt 27) { $letter = [string][char](97 + $i) }' }
        @{ Name = "an-unmarked-part-takes-the-letter-before-its-place"
           Find = '        elseif ($i -lt 26) { $letter = [string][char](97 + $i) }'
           Replace = '        elseif ($i -lt 26) { $letter = [string][char](96 + $i) }' }
        @{ Name = "two-parts-of-one-letter-are-told-apart"
           Find = '        if ($letter -eq "" -or $seen.ContainsKey($letter)) { return @() }'
           Replace = '        if ($letter -eq "") { return @() }' }
        @{ Name = "a-capital-is-a-part-mark"
           Find = '$script:HordeDecisionPartMark = ''\A\s*\(([a-z])\)\s*'''
           Replace = '$script:HordeDecisionPartMark = ''(?i)\A\s*\(([a-z])\)\s*''' }
        # --- words about to be said: a part ---
        @{ Name = "a-part-of-any-spelling-may-be-said"
           Find = '        if ($Request.part -isnot [string] -or $Request.part -cnotmatch $script:HordeDecisionPartPattern) { [void]$found.Add("''part'' is one lower-case letter, the letter of the part answered, as in: b") }'
           Replace = '        if ($false) { }' }
        @{ Name = "the-keeper-answers-a-part"
           Find = '        elseif ($Speaker -cne $script:HordeDecisionFirstTurn) { [void]$found.Add("only the words of " + (Get-HordeDecisionSpeakerShown -Speaker $script:HordeDecisionFirstTurn) + " answer a part of a question") }'
           Replace = '' }
        @{ Name = "an-act-answers-a-part"
           Find = '        elseif (Test-HordeDecisionMember -Object $Request -Name "act") { [void]$found.Add("an act answers no part of a question: give ''part'' or ''act'', not both") }'
           Replace = '' }
        # --- words said: a part ---
        @{ Name = "a-part-the-question-lacks-is-answered"
           Find = '        elseif (-not ($stated -and $seen -lt [int]$question.wordingVersion)) {'
           Replace = '        elseif ($false) {' }
        @{ Name = "words-to-an-earlier-wording-that-had-the-part-are-dropped"
           Find = '        elseif (-not ($stated -and $seen -lt [int]$question.wordingVersion)) {'
           Replace = '        elseif ($true) {' }
        @{ Name = "a-part-of-a-question-with-none-says-it-has-no-such-part"
           Find = '            if ($parts.Count -eq 0) { return ("it answers part (" + $part + ") of question " + $question.number + ", which is not a question of parts that are answered one by one") }'
           Replace = '' }
        @{ Name = "the-part-answered-is-not-kept-with-the-message"
           Find = '        part = $part'
           Replace = '        part = ""' }
        @{ Name = "the-parts-words-are-not-those-of-the-moment"
           Find = '        if ($null -ne $mine) { $partWords = [string]$mine.words; $partStands = $true }'
           Replace = '        if ($null -ne $mine) { $partStands = $true }' }
        @{ Name = "an-answer-to-a-part-replaces-his-answer-to-another"
           Find = '            if ($part -ne "" -and "$($before.part)" -ne "" -and "$($before.part)" -cne $part) { continue }'
           Replace = '' }
        @{ Name = "the-other-speakers-words-do-not-end-the-search"
           Find = '            if ("$($before.speaker)" -cne $speaker) { break }'
           Replace = '            if ("$($before.speaker)" -cne $speaker) { continue }' }
        @{ Name = "one-part-answered-passes-the-turn"
           Find = '            $passes = ($partStands -and @(Get-HordeDecisionParts -Question $question | Where-Object { -not $question.partsAnswered.Contains("$($_.letter)") }).Count -eq 0)'
           Replace = '            $passes = $partStands' }
        @{ Name = "the-last-part-answered-does-not-pass-the-turn"
           Find = '            $passes = ($partStands -and @(Get-HordeDecisionParts -Question $question | Where-Object { -not $question.partsAnswered.Contains("$($_.letter)") }).Count -eq 0)'
           Replace = '            $passes = $false' }
        @{ Name = "a-part-answered-is-not-remembered"
           Find = '            if ($partStands) { $question.partsAnswered[$part] = [long]$Ev.sequence }'
           Replace = '' }
        @{ Name = "a-part-the-question-lost-counts-as-answered"
           Find = '            if ($partStands) { $question.partsAnswered[$part] = [long]$Ev.sequence }'
           Replace = '            $question.partsAnswered[$part] = [long]$Ev.sequence' }
        @{ Name = "the-keeper-naming-a-part-answers-it"
           Find = '        if ($part -ne "" -and $speaker -ceq $script:HordeDecisionFirstTurn) {'
           Replace = '        if ($part -ne "") {' }
        # --- as shown ---
        @{ Name = "the-message-shown-names-no-part"
           Find = '        part = "$($Message.part)"'
           Replace = '        part = ""' }
        @{ Name = "the-message-shown-holds-no-part-words"
           Find = '        partWords = "$($Message.partWords)"'
           Replace = '        partWords = ""' }
        @{ Name = "every-thread-says-it-has-parts"
           Find = '    if ($parts.Count -gt 0) { $thread["parts"] = @($parts | ForEach-Object'
           Replace = '    if ($true) { $thread["parts"] = @($parts | ForEach-Object' }
        @{ Name = "every-part-reads-as-answered"
           Find = 'answered = [bool]$Question.partsAnswered.Contains("$($_.letter)") } }) }'
           Replace = 'answered = $true } }) }' }
        @{ Name = "the-view-shows-the-default-importance"
           Find = '    $view["importance"] = "$($Question.importance)"'
           Replace = '    $view["importance"] = $script:HordeDecisionDefaultImportance' }
        @{ Name = "the-view-shows-the-default-blocking"
           Find = '    $view["blocks"] = "$($Question.blocks)"'
           Replace = '    $view["blocks"] = $script:HordeDecisionDefaultBlocks' }
        @{ Name = "the-blocking-shown-in-the-importances-words"
           Find = '    $view["blocksShown"] = (Get-HordeDecisionRankShown -Name "blocks" -Word "$($Question.blocks)")'
           Replace = '    $view["blocksShown"] = (Get-HordeDecisionRankShown -Name "importance" -Word "$($Question.blocks)")' }
        @{ Name = "the-importance-shown-is-the-bare-word"
           Find = '    $view["importanceShown"] = (Get-HordeDecisionRankShown -Name "importance" -Word "$($Question.importance)")'
           Replace = '    $view["importanceShown"] = "$($Question.importance)"' }
        @{ Name = "every-question-follows-one"
           Find = '    if ([int]$Question.followsUp -ge 1) { $view["followsUp"]'
           Replace = '    if ([int]$Question.followsUp -ge 0) { $view["followsUp"]' }
        @{ Name = "no-question-shows-what-it-follows"
           Find = '    if ([int]$Question.followsUp -ge 1) { $view["followsUp"]'
           Replace = '    if ([int]$Question.followsUp -ge 1 -and $false) { $view["followsUp"]' }
        # --- what he answered, and the question a follow-up follows ---
        @{ Name = "the-keepers-words-are-his-answer"
           Find = '        if ("$($message.speaker)" -cne $script:HordeDecisionFirstTurn -or "$($message.act)" -ne "") { continue }'
           Replace = '        if ("$($message.act)" -ne "") { continue }' }
        @{ Name = "an-act-is-his-answer"
           Find = '        if ("$($message.speaker)" -cne $script:HordeDecisionFirstTurn -or "$($message.act)" -ne "") { continue }'
           Replace = '        if ("$($message.speaker)" -cne $script:HordeDecisionFirstTurn) { continue }' }
        @{ Name = "words-to-the-whole-question-leave-the-parts-standing"
           Find = '        else { $whole = $message; $byPart = @{} }'
           Replace = '        else { $whole = $message }' }
        @{ Name = "parts-answered-hide-his-words-to-the-whole"
           Find = '    if ($null -ne $whole) { [void]$lines.Add([string]$whole.text) }'
           Replace = '' }
        @{ Name = "the-parts-of-his-answer-are-in-no-order"
           Find = '    foreach ($letter in @($byPart.Keys | Sort-Object)) { [void]$lines.Add("(" + $letter + ") " + [string]$byPart[$letter].text) }'
           Replace = '    foreach ($letter in @($byPart.Keys | Sort-Object -Descending)) { [void]$lines.Add("(" + $letter + ") " + [string]$byPart[$letter].text) }' }
        @{ Name = "a-follow-up-of-an-unreadable-question-throws"
           Find = '    if (-not $State.questions.ContainsKey($Number)) { return [pscustomobject]$out }'
           Replace = '' }
        @{ Name = "a-long-answer-is-carried-whole"
           Find = '    if ($answer.Length -gt $script:HordeDecisionFollowsUpAnswerChars) { $answer = $answer.Substring(0, $script:HordeDecisionFollowsUpAnswerChars); $out["answerCut"] = $true }'
           Replace = '' }
        @{ Name = "a-cut-answer-does-not-say-it-is-cut"
           Find = '$answer = $answer.Substring(0, $script:HordeDecisionFollowsUpAnswerChars); $out["answerCut"] = $true }'
           Replace = '$answer = $answer.Substring(0, $script:HordeDecisionFollowsUpAnswerChars) }' }
        @{ Name = "an-answer-of-exactly-the-length-is-cut"
           Find = '    if ($answer.Length -gt $script:HordeDecisionFollowsUpAnswerChars) {'
           Replace = '    if ($answer.Length -ge $script:HordeDecisionFollowsUpAnswerChars) {' }
        @{ Name = "the-follow-up-shows-no-outcome"
           Find = '    $out["outcome"] = "$($old.outcome)"'
           Replace = '' }
        @{ Name = "the-follow-up-shows-the-old-question-as-open"
           Find = '    $out["state"] = "$($old.state)"'
           Replace = '    $out["state"] = "open"' }
    )
}
