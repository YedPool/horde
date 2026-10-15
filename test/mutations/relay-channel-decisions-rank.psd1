# Mutations of a change of rank from the founder's phone (channels/decisions/Channel.ps1, A CHANGE OF RANK
# FROM THE PHONE; the founder, 2026-10-14: his little buttons). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channel-decisions-rank.psd1
# test\test-relay-decisions-rank.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "channels\decisions\Channel.ps1"
    Suite  = "test\test-relay-decisions-rank.ps1"
    Mutations = @(
        @{ Name = "the-kind-is-not-registered"
           Find = '-Kinds @("answer", "rank")'
           Replace = '-Kinds @("answer")' }
        @{ Name = "any-other-kind-is-read-as-an-answer"
           Find = 'if ("$($Item.kind)" -cne "answer") {'
           Replace = 'if ($false) {' }
        @{ Name = "a-change-naming-neither-word-is-taken"
           Find = '-or $words.Count -eq 0) {'
           Replace = '-or $false) {' }
        @{ Name = "a-level-off-the-list-is-handed-on"
           Find = 'if (@(Test-HordeDecisionRankWord -Name $w -Word $a.$w).Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "an-answered-question-is-ranked"
           Find = 'if ("$($q.thread.turn)" -cne "founder") {'
           Replace = 'if ($false) {' }
        @{ Name = "a-closed-question-is-handed-on"
           Find = 'if ("$($q.state)" -cne "open") {'
           Replace = 'if ($false) {' }
        @{ Name = "a-stale-change-wins"
           Find = 'if ($newest -gt $signedAt) {'
           Replace = 'if ($false) {' }
        @{ Name = "the-signing-time-kept-is-never-read"
           Find = 'if ($ledger.ranked.Contains($key)) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-time-that-cannot-be-read-counts-as-nothing"
           Find = 'catch { return [long]::MaxValue }'
           Replace = 'catch { return [long]-1 }' }
        @{ Name = "the-same-change-after-a-crash-is-superseded"
           Find = 'if ($same) { $again = Invoke-HordeDecision'
           Replace = 'if ($false) { $again = Invoke-HordeDecision' }
        @{ Name = "the-request-id-shares-the-answers-domain"
           Find = '-Domain $script:HordeDecisionsChannelRankIdDomain)'
           Replace = ')' }
        @{ Name = "the-receipt-is-not-kept"
           Find = '$null = Add-HordeDecisionsChannelReceipt -Context $Context -From $Item.from -AnswerId $r.value.rankId -Outcome $out.outcome'
           Replace = '$null = $r.value.rankId' }
        @{ Name = "the-snapshot-does-not-say-it-takes-ranks"
           Find = ',"ranks":1,"receipts":'
           Replace = ',"receipts":' }
    )
}
