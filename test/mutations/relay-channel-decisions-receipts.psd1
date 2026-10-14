# Mutations of the receipts every decisions snapshot carries back to the phone: what became of each of
# the founder's answers, by id (channels/decisions/Channel.ps1, WHAT BECAME OF EACH ANSWER; the founder,
# 2026-10-14, relay fixes 3 and 4). Applied by hand, one at a time:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channel-decisions-receipts.psd1
# test\test-relay-channels.ps1 must fail for every one. Every find string occurs exactly once. The
# channel's other promises are relay-channel-decisions.psd1's and its siblings'.
@{
    Target = "channels\decisions\Channel.ps1"
    Suite  = "test\test-relay-channels.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "snapshot-carries-no-receipts"
           Find = ',"answers":'' + $script:HordeDecisionsChannelAnswerHighest + '',"receipts":'' + $Receipts + ''}'''
           Replace = ',"answers":'' + $script:HordeDecisionsChannelAnswerHighest + ''}''' }
        @{ Name = "pages-are-not-handed-the-receipts"
           Find = '-OnePage:$onePage -Receipts $receipts.text'
           Replace = '-OnePage:$onePage' }
        @{ Name = "accept-records-nothing"
           Find = '$null = Add-HordeDecisionsChannelReceipt -Context $Context -From $Item.from -AnswerId $r.value.answerId -Outcome $out.outcome'
           Replace = '$null = $out' }
        @{ Name = "refused-is-never-recorded"
           Find = 'if ($Outcome -cne "done" -and $Outcome -cne "refused") { return "" }'
           Replace = 'if ($Outcome -cne "done") { return "" }' }
        @{ Name = "retry-is-recorded-as-refused"
           Find = 'if ($Outcome -cne "done" -and $Outcome -cne "refused") { return "" }'
           Replace = 'if ($Outcome -ceq "") { return "" }' }
        @{ Name = "a-resent-answer-is-listed-twice"
           Find = 'if ($mine.applied -ccontains $AnswerId) { return "" }'
           Replace = 'if ($false) { return "" }' }
        @{ Name = "a-refusal-overrides-an-applied-answer"
           Find = 'if ($mine.applied -ccontains $AnswerId -or $mine.refused -ccontains $AnswerId) { return "" }'
           Replace = 'if ($mine.refused -ccontains $AnswerId) { return "" }' }
        @{ Name = "applied-list-grows-without-end"
           Find = 'while ($mine.applied.Count -gt $script:HordeDecisionsChannelReceiptsApplied) { $mine.applied.RemoveAt(0) }'
           Replace = '' }
        @{ Name = "refused-list-grows-without-end"
           Find = 'while ($mine.refused.Count -gt $script:HordeDecisionsChannelReceiptsRefused) { $mine.refused.RemoveAt(0) }'
           Replace = '' }
        @{ Name = "the-ledger-is-not-read-back-after-a-restart"
           Find = 'if (-not [System.IO.File]::Exists($path)) { return $out }'
           Replace = 'return $out' }
        @{ Name = "missing-seqs-are-never-listed"
           Find = 'if (-not $st.seqs.ContainsKey("" + $s)) { [void]$missing.Add($s) }'
           Replace = '' }
        @{ Name = "through-is-always-zero"
           Find = '$through = [long][System.Math]::Max([long]0, [long]$st.last)'
           Replace = '$through = [long]0' }
        @{ Name = "a-change-of-receipts-alone-sends-nothing"
           Find = '-and $receipts.text -ceq "$($mine.receipts)")'
           Replace = ')' }
        @{ Name = "the-receipts-sent-are-not-remembered"
           Find = '$mine.fingerprint = $print; $mine.receipts = $receipts.text; return'
           Replace = '$mine.fingerprint = $print; return'
           Expect = "survives"
           Reason = "That path is a look whose snapshot is the very one already sent: forgetting its receipts there costs the next look a reading of the list and sends nothing, as list-read-on-every-look's cost does in relay-channel-decisions.psd1 - nothing a phone can see. The suite does not time a look." }
    )
}
