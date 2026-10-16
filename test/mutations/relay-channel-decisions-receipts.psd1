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
           Find = ',"answers":'' + $script:HordeDecisionsChannelAnswerHighest + '',"ranks":1,"receipts":'' + $Receipts + ''}'''
           Replace = ',"answers":'' + $script:HordeDecisionsChannelAnswerHighest + '',"ranks":1}''' }
        @{ Name = "pages-are-not-handed-the-receipts"
           Find = '-OnePage:$onePage -Receipts $receipts.text'
           Replace = '-OnePage:$onePage' }
        @{ Name = "accept-records-nothing"
           Find = '$null = Add-HordeDecisionsChannelReceipt -Context $Context -From $Item.from -AnswerId $r.value.answerId -Outcome $ledgerOutcome'
           Replace = '$null = $out' }
        @{ Name = "refused-is-never-recorded"
           Find = 'if ($Outcome -cne "done" -and $Outcome -cne "refused" -and $Outcome -cne "needs-passkey") { return "" }'
           Replace = 'if ($Outcome -cne "done" -and $Outcome -cne "needs-passkey") { return "" }' }
        @{ Name = "retry-is-recorded-as-refused"
           Find = 'if ($Outcome -cne "done" -and $Outcome -cne "refused" -and $Outcome -cne "needs-passkey") { return "" }'
           Replace = 'if ($Outcome -ceq "") { return "" }' }
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
        # --- the review of PR 262
        @{ Name = "the-receipt-does-not-say-how-far-down-it-looked"
           Find = ''',"checked":'' + $checked + '''
           Replace = "'" }
        @{ Name = "checked-claims-every-seq-was-looked-at"
           Find = '            $checked = $s'
           Replace = '            $checked = [long]1' }
        @{ Name = "the-phone-sealed-to-is-not-preferred"
           Find = 'if (@($Prefer) -ccontains $_) { 0 } else { 1 }'
           Replace = '1' }
        @{ Name = "past-the-cap-key-order-not-activity"
           Find = '@{ Expression = { $when[$_] }; Descending = $true }, '
           Replace = '' }
        @{ Name = "a-failed-move-leaves-its-temp-file"
           Find = 'try { if ([System.IO.File]::Exists($temp)) { [System.IO.File]::Delete($temp) } } catch { }'
           Replace = '' }
        # --- the review of PR 266, S-A: the newest answer in the store wins, whatever its route
        @{ Name = "a-resent-answer-is-listed-twice"
           Find = 'if ($mine.applied -ccontains $AnswerId) { return "" }'
           Replace = 'if ($false) { return "" }' }
        @{ Name = "a-stale-answer-is-applied"
           Find = 'if ("$($older.value)" -cne "") { return [pscustomobject]@{ outcome = "refused"; reason = $older.value } }'
           Replace = '' }
        @{ Name = "a-store-that-cannot-be-read-lets-it-pass"
           Find = 'if ($shown.state -ceq "unknown") { return (New-HordeUnknown -Reason $shown.reason) }'
           Replace = 'if ($shown.state -ceq "unknown") { return (New-HordeKnown -Value "") }' }
        @{ Name = "the-applied-answer-sent-again-is-called-stale"
           Find = 'if ($ledger.streams.ContainsKey($From) -and $ledger.streams[$From].applied -ccontains $Answer.answerId) { return (New-HordeKnown -Value "") }'
           Replace = '' }
        @{ Name = "a-phone-answer-counts-by-when-it-landed"
           Find = 'if ($signed -ge 0) { return $signed }'
           Replace = '' }
        @{ Name = "the-newest-is-not-kept"
           Find = 'if ($given -gt $newest) { $newest = $given; $how = "$($m.route)" }'
           Replace = 'if ($newest -lt 0) { $newest = $given; $how = "$($m.route)" }' }

        @{ Name = "part-filter-removed"
           Find = ' -or "$($m.part)" -cne "$($Answer.part)"'
           Replace = '' }
    )
}
