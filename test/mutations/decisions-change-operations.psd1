# Mutations of decisions/Operations.ps1 for THE FOUNDER CHANGES HIS ANSWER (T-0152): the refusal of a change
# to a closed question at the moment of the request, and the operation change-reply. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-change-operations.psd1
# test\test-decisions-change.ps1 must fail for each. Each find string occurs once.
@{
    Target = "decisions\Operations.ps1"
    Suite  = "test\test-decisions-change.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-change-to-a-closed-question-is-written"
           Find = '        if ($closedChange -ne "") { return [pscustomobject]@{ why = $closedChange; write = $false; more = $null; data = $null } }'
           Replace = '' }
        @{ Name = "the-part-is-left-out-of-the-closed-question-check"
           Find = '        $changePart = $(if ($Data.Contains("part")) { "$($Data[''part''])" } else { "" })'
           Replace = '        $changePart = ""' }
        @{ Name = "an-act-is-taken-for-a-change-under-a-closed-question"
           Find = '        $changeAct = $(if ($Data.Contains("act")) { "$($Data[''act''])" } else { "" })'
           Replace = '        $changeAct = ""' }
        @{ Name = "the-reply-is-written-as-another-kind-of-record"
           Find = 'kind = "answer-change-replied"; content = "Get-HordeDecisionChangeReplyContent"'
           Replace = 'kind = "question-acked"; content = "Get-HordeDecisionChangeReplyContent"' }
        @{ Name = "the-reason-is-not-kept"
           Find = '        $body["why"] = $line'
           Replace = '' }
        @{ Name = "the-reason-may-be-more-than-a-line"
           Find = '        foreach ($f in @(Test-HordeDecisionNote -Text $line -Name "why" -OneLine)) { [void]$found.Add($f) }'
           Replace = '' }
        @{ Name = "the-reply-is-not-kept"
           Find = '    $body = [ordered]@{ by = [string]$Request.by; answer = [long]$Request.answer; reply = [string]$Request.reply }'
           Replace = '    $body = [ordered]@{ by = [string]$Request.by; answer = [long]$Request.answer; reply = "undoing" }' }
        # --- the Orc says what became of its work before it closes (review of PR 335, M1)
        @{ Name = "an-ack-over-an-unreplied-change-is-taken"
           Find = 'if ($null -ne $ackUnreplied) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-close-over-an-unreplied-change-is-taken"
           Find = 'if ($null -ne $closeUnreplied -and -not $warchiefCloses) {'
           Replace = 'if ($false) {' }
        @{ Name = "the-warchief-closes-over-an-unreplied-change-with-no-proof-of-the-seat"
           Find = ' -and "$(Get-HordeDecisionMember -Object $Request -Name ''callerSeat'')" -ceq "warchief")'
           Replace = ')' }
        @{ Name = "nobody-may-close-over-an-unreplied-change-not-even-the-proven-warchief"
           Find = '$provenWarchief = ("$($Request.actor)" -ceq "warchief" -and $closeWords -ne "" -and'
           Replace = '$provenWarchief = ($false -and' }
        @{ Name = "the-close-record-does-not-carry-the-proof-of-the-warchiefs-seat"
           Find = '    if ($provenWarchief) { $Data["closedBySeat"] = "warchief" }'
           Replace = '' }
        @{ Name = "any-close-is-recorded-as-made-from-the-warchiefs-seat"
           Find = '    if ($provenWarchief) { $Data["closedBySeat"] = "warchief" }'
           Replace = '    $Data["closedBySeat"] = "warchief"' }
    )
}
