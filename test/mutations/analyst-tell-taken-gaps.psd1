# Mutations that SURVIVED the first spec (analyst-tell-taken.psd1) at PR 455's review, T-0391: cli/AnalystTend.ps1's phone words, its ack clear
# and its reading of an unreadable awaiting list. Each is caught by a check in test\test-analyst-tell-taken.ps1 named in its comment.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\analyst-tell-taken-gaps.psd1
@{
    Target = "cli\AnalystTend.ps1"
    Suite  = "test\test-analyst-tell-taken.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # The phone's watch question always names generation 0: a second episode of a key is judged by the first one's notice.
        @{ Name = "gaps-words-gen-zero"
           Find = '-With @($Key, (Get-HordeAnalystTellGen -State $State -Key $Key)) } catch { $w = $null }'
           Replace = '-With @($Key, 0) } catch { $w = $null }' }
        # An ack no longer ends the founder's no-answer reminder, only the warchief's.
        @{ Name = "gaps-ack-clears-only-warchief-key"
           Find = 'Clear-HordeAnalystTold -State $s -Keys @("no-answer", "no-answer-founder") }'
           Replace = 'Clear-HordeAnalystTold -State $s -Keys @("no-answer") }' }
        # A list that cannot be read is called "gone" (taken) instead of "unread".
        @{ Name = "gaps-unreadable-list-reads-gone"
           Find = 'if ($r.state -cne "known") { return "unread" }'
           Replace = 'if ($r.state -cne "known") { return "gone" }' }
        # An already-posted copy keeps the mark this pass just wrote.
        @{ Name = "gaps-already-posted-keeps-mark"
           Find = 'if ($r.detail -clike "already-posted*" -and -not $wasListed) {'
           Replace = 'if ($false) {' }
    )
}
