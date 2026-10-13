# Mutations of decisions/Operations.ps1 for the founder's rules of 2026-10-12, the part the operations
# suite holds: the two words beside a question at add, a follow-up, rank, and reopen refused. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-order-operations.psd1
# test\test-decisions-operations.ps1 must fail for each. What is said under a question - a part
# answered, the keeper's words that ask - is test\mutations\decisions-order-threads.psd1.
@{
    Target = "decisions\Operations.ps1"
    Suite  = "test\test-decisions-operations.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- reopen is no longer done ---
        @{ Name = "reopen-is-done-again"
           Find = '        if ($entry.ContainsKey("retired")) {'
           Replace = '        if ($false) {' }
        @{ Name = "the-refusal-does-not-name-the-question"
           Find = '            $gone = ("$($entry.retired)" -f $number)'
           Replace = '            $gone = ("$($entry.retired)" -f "N")' }
        @{ Name = "reopening-a-question-never-asked-is-refused-not-absent"
           Find = '            if ($hasNumber) { $gap = Get-HordeDecisionNumberAnswer -State $list -Number $number -Operation $Operation; if ($null -ne $gap) { return $gap } }'
           Replace = '' }
        @{ Name = "the-refusal-gives-no-advice"
           Find = '; nothing was written. '' + $script:HordeDecisionFollowUpAdvice'
           Replace = '; nothing was written. ''' }
        # --- add: what stands beside the question ---
        @{ Name = "the-stated-words-are-not-recorded"
           Find = '        $body[$beside] = [string]$stated'
           Replace = '' }
        @{ Name = "a-word-beside-a-question-is-not-held-to-its-list"
           Find = '        foreach ($f in @(Test-HordeDecisionRankWord -Name $beside -Word $stated)) { [void]$found.Add($f) }'
           Replace = ''
           Expect = "survives"
           Reason = "the request's schema (schema/decision-request.v1, add.importance and add.blocks as enums) refuses a word that is none of the list's before this line is reached, so through Invoke-HordeDecision the two say the same thing. The line is the second layer, for a caller that reaches the content function without the schema - as Test-HordeDecisionSaying keeps the evidence's spelling beside its schema pattern - and test	est-decisions-rules.ps1 holds Test-HordeDecisionRankWord itself to every wrong word." }
        @{ Name = "what-a-question-follows-is-not-recorded"
           Find = '        if (Test-HordeDecisionCount -Value $Request.followsUp -Most (Get-HordeDecisionMaxNumber)) { $body["followsUp"] = [int]$Request.followsUp }'
           Replace = '        if (Test-HordeDecisionCount -Value $Request.followsUp -Most (Get-HordeDecisionMaxNumber)) { }' }
        @{ Name = "an-impossible-follow-up-is-cast"
           Find = '        if (Test-HordeDecisionCount -Value $Request.followsUp -Most (Get-HordeDecisionMaxNumber)) { $body["followsUp"] = [int]$Request.followsUp }'
           Replace = '        if ($true) { $body["followsUp"] = [int]$Request.followsUp }' }
        @{ Name = "a-follow-up-of-a-question-not-there-is-added"
           Find = '        if ((Get-HordeDecisionNumberStatus -State $List -Number $old) -cne "present") {'
           Replace = '        if ($false) {' }
        @{ Name = "the-defaults-are-written-into-every-record"
           Find = '        if (-not (Test-HordeDecisionMember -Object $Request -Name $beside)) { continue }'
           Replace = '        if (-not (Test-HordeDecisionMember -Object $Request -Name $beside)) { $body[$beside] = $(if ($beside -ceq "blocks") { Get-HordeDecisionDefaultBlocks } else { Get-HordeDecisionDefaultImportance }); continue }' }
        # --- rank ---
        @{ Name = "a-ranking-of-nothing-is-taken"
           Find = '    if ($body.Count -eq 0) { [void]$found.Add("the ranking names neither word, so there is nothing to change:'
           Replace = '    if ($false) { [void]$found.Add("the ranking names neither word, so there is nothing to change:' }
        @{ Name = "rank-is-not-an-operation-that-writes"
           Find = '    rank   = @{ writes = $true;  kind = "question-ranked";   content = "Get-HordeDecisionRankContent" }'
           Replace = '    rank   = @{ writes = $false; read = "Get-HordeDecisionShowAnswer" }' }
        @{ Name = "rank-writes-an-update-record"
           Find = '    rank   = @{ writes = $true;  kind = "question-ranked";   content = "Get-HordeDecisionRankContent" }'
           Replace = '    rank   = @{ writes = $true;  kind = "question-updated";  content = "Get-HordeDecisionRankContent" }' }
        @{ Name = "a-word-of-a-ranking-is-not-recorded"
           Find = '        $body[$name] = [string]$word'
           Replace = '' }
    )
}
