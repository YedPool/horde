# Mutations of decisions/Console.ps1 for the founder's rules of 2026-10-12, as the command line shows
# them: the two words beside a question, a follow-up, rank, the part an answer is for, and what the
# keeper's own list says of a question that has left the founder's. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-order-console.psd1
# test\test-decisions-console-threads.ps1 must fail for each.
@{
    Target = "decisions\Console.ps1"
    Suite  = "test\test-decisions-console-threads.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- what the command line takes ---
        @{ Name = "add-does-not-take-follows-up"
           Find = '    add    = @{ number = $false; flags = @("File", "Importance", "Blocks", "FollowsUp", "Id", "Json");'
           Replace = '    add    = @{ number = $false; flags = @("File", "Importance", "Blocks", "Id", "Json");' }
        @{ Name = "rank-takes-another-verbs-flag"
           Find = '    rank   = @{ number = $true;  flags = @("Importance", "Blocks", "Id", "Json");'
           Replace = '    rank   = @{ number = $true;  flags = @("Importance", "Blocks", "Text", "Id", "Json");' }
        @{ Name = "reply-takes-a-part"
           Find = '    reply  = @{ number = $true;  flags = @("Text", "File", "Note", "Wording", "Id", "Json");'
           Replace = '    reply  = @{ number = $true;  flags = @("Text", "File", "Note", "Part", "Wording", "Id", "Json");' }
        @{ Name = "a-follow-up-that-is-not-a-number-is-cast"
           Find = '                if ($followsText -cnotmatch ''\A[1-9][0-9]{0,8}\z'') { throw'
           Replace = '                if ($false) { throw' }
        @{ Name = "what-a-question-follows-is-not-handed-on"
           Find = '                $request["followsUp"] = [int]$followsText'
           Replace = '' }
        @{ Name = "rank-with-no-word-is-sent"
           Find = '            if (-not $have.ContainsKey("Importance") -and -not $have.ContainsKey("Blocks")) { throw'
           Replace = '            if ($false) { throw' }
        @{ Name = "the-rank-words-are-not-handed-on"
           Find = '        if ($spec.flags -contains $rankFlag -and $have.ContainsKey($rankFlag)) { $request[$rankFlag.ToLowerInvariant()] = "$($have[$rankFlag])".ToLowerInvariant() }'
           Replace = '' }
        @{ Name = "a-rank-word-is-handed-on-in-the-case-it-was-typed"
           Find = '{ $request[$rankFlag.ToLowerInvariant()] = "$($have[$rankFlag])".ToLowerInvariant() }'
           Replace = '{ $request[$rankFlag.ToLowerInvariant()] = "$($have[$rankFlag])" }' }
        @{ Name = "the-part-is-not-handed-on"
           Find = '            $request["part"] = $partLetter'
           Replace = '' }
        @{ Name = "a-part-that-is-not-a-letter-is-handed-on"
           Find = '            if ($partLetter -cnotmatch ''\A[a-z]\z'') { throw'
           Replace = '            if ($false) { throw' }
        @{ Name = "a-part-is-handed-on-in-the-case-it-was-typed"
           Find = '            $partLetter = "$($have[''Part''])".ToLowerInvariant()'
           Replace = '            $partLetter = "$($have[''Part''])"' }
        @{ Name = "the-plain-list-asks-for-no-conversation"
           Find = '            if (-not ($have.ContainsKey("Json") -and [bool]$have["Json"])) { $request["messages"] = $true }'
           Replace = '' }
        @{ Name = "list-json-carries-every-conversation"
           Find = '            if (-not ($have.ContainsKey("Json") -and [bool]$have["Json"])) { $request["messages"] = $true }'
           Replace = '            $request["messages"] = $true' }
        # --- what it prints ---
        @{ Name = "the-part-answered-is-not-printed"
           Find = '        [void]$lines.Add($Indent + $partLine + ")")'
           Replace = '' }
        @{ Name = "the-part-is-printed-without-its-words"
           Find = '        if ((& $has "partWords") -and "$($Message.partWords)".Trim() -ne "") { $partLine = $partLine + ": " + (Get-HordeDecisionFirstLine -Text "$($Message.partWords)") }'
           Replace = '' }
        @{ Name = "the-list-does-not-say-which-parts-are-answered"
           Find = '        $phrase = $phrase + "; parts answered: " + $(if ($done.Count -eq 0) { "none" } else { $done -join ", " }) + " of " + $all.Count'
           Replace = '' }
        @{ Name = "every-part-is-listed-as-answered"
           Find = '        $done = @($all | Where-Object { $_.answered } | ForEach-Object { "(" + $_.letter + ")" })'
           Replace = '        $done = @($all | ForEach-Object { "(" + $_.letter + ")" })' }
        @{ Name = "the-list-shows-no-rank-words"
           Find = '            if ($rank -ne "") { [void]$lines.Add($pad + $rank) }'
           Replace = '' }
        @{ Name = "the-rank-words-shown-are-the-importance-only"
           Find = '    foreach ($name in @("importanceShown", "blocksShown")) {'
           Replace = '    foreach ($name in @("importanceShown")) {' }
        @{ Name = "the-list-does-not-say-what-a-question-follows"
           Find = '            if ($null -ne $q.PSObject.Properties["followsUp"]) { [void]$lines.Add($pad + "follows up on question "'
           Replace = '            if ($false) { [void]$lines.Add($pad + "follows up on question "' }
        @{ Name = "the-keepers-list-does-not-show-his-answer"
           Find = '            if ($answered -ne "") { [void]$lines.Add($pad + $answered) }'
           Replace = '' }
        @{ Name = "a-question-still-his-turn-is-said-to-be-answered"
           Find = '    if ("$($Question.state)" -cne "open" -or "$($Question.thread.turn)" -ceq (Get-HordeDecisionFirstTurn)) { return "" }'
           Replace = '    if ("$($Question.state)" -cne "open") { return "" }' }
        @{ Name = "a-keepers-note-is-shown-as-his-answer"
           Find = '    $mine = @($Question.thread.messages | Where-Object { "$($_.speaker)" -ceq (Get-HordeDecisionFirstTurn) -and "$($_.act)" -eq "" })'
           Replace = '    $mine = @($Question.thread.messages | Where-Object { "$($_.act)" -eq "" })' }
        @{ Name = "an-answer-by-parts-shows-only-the-last-part"
           Find = '        $said = (@($byPart.Keys | Sort-Object | ForEach-Object { "(" + $_ + ") " + (Get-HordeDecisionFirstLine -Text ([string]$byPart[$_].text)) }) -join "; ")'
           Replace = '' }
        @{ Name = "show-does-not-say-how-much-the-question-matters"
           Find = '        [void]$lines.Add("Importance of its task: " + $q.importance + $(if ("$($q.importanceShown)" -ne "") { " (" + $q.importanceShown + ")" } else { "" }))'
           Replace = '' }
        @{ Name = "show-does-not-say-how-much-the-question-blocks"
           Find = '        [void]$lines.Add("Blocks: " + $q.blocks + $(if ("$($q.blocksShown)" -ne "") { " (" + $q.blocksShown + ")" } else { "" }))'
           Replace = '' }
        @{ Name = "show-does-not-say-what-he-answered-before"
           Find = '            if ("$($old.answer)" -ne "") { Add-HordeDecisionTextBlock'
           Replace = '            if ($false) { Add-HordeDecisionTextBlock' }
        @{ Name = "show-does-not-name-the-question-followed"
           Find = '            [void]$lines.Add("Follows up on question " + $old.number + " (" + $old.state + "): " + $old.title)'
           Replace = '' }
        @{ Name = "add-does-not-say-where-the-question-stands"
           Find = '            [void]$lines.Add("  importance of its task: " + $value.question.importance + "; blocks: " + $value.question.blocks + ". Change either with:'
           Replace = '            $null = ("  importance of its task: " + $value.question.importance + "; blocks: " + $value.question.blocks + ". Change either with:' }
        @{ Name = "add-does-not-say-it-is-a-follow-up"
           Find = '            if ($null -ne $value.question.PSObject.Properties["followsUp"]) { [void]$lines.Add("  follows up on question "'
           Replace = '            if ($false) { [void]$lines.Add("  follows up on question "' }
        @{ Name = "rank-does-not-say-what-it-changed"
           Find = '        if ($Verb -ceq "update" -or $Verb -ceq "rank") { $last'
           Replace = '        if ($Verb -ceq "update") { $last' }
    )
}
