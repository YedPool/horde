# Mutations of each Orc's published list on its way to the founder's phone (channels/decisions/Channel.ps1,
# EACH ORC'S PUBLISHED LIST; T-0328). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channel-decisions-published.psd1
# test\test-relay-decisions-published.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "channels\decisions\Channel.ps1"
    Suite  = "test\test-relay-decisions-published.ps1"
    Mutations = @(
        @{ Name = "the-thrall-is-not-its-own-lane"
           Find = '$lane = $(if ("$($l.rank)" -ceq "thrall") { "thrall" } else { "$($l.orc)" })'
           Replace = '$lane = "$($l.orc)"' }
        @{ Name = "a-secret-looking-item-is-sent"
           Find = 'if (@(Find-HordeDecisionSecrets -Value $it).Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-refused-item-keeps-its-recommendation"
           Find = 'text = "(not sent: it looks like a secret, so it is shown at the machine only)"; recommendation = $null;'
           Replace = 'text = "(not sent: it looks like a secret, so it is shown at the machine only)"; recommendation = "$($it.recommendation)";' }
        @{ Name = "a-list-is-sent-whole-however-long"
           Find = 'foreach ($it in ($all | Select-Object -First $MostItems)) {'
           Replace = 'foreach ($it in $all) {' }
        @{ Name = "the-total-size-is-not-held"
           Find = 'while ($utf8.GetByteCount($text) -gt $MostBytes) {'
           Replace = 'while ($false) {' }
        @{ Name = "the-front-of-the-longest-list-goes-first"
           Find = '$longest.items.RemoveAt($longest.items.Count - 1)'
           Replace = '$longest.items.RemoveAt(0)' }
        @{ Name = "what-was-left-out-is-not-counted"
           Find = '$longest.more = $longest.more + 1'
           Replace = '$longest.more = $longest.more' }
        @{ Name = "a-linked-question-is-not-carried"
           Find = 'if ($null -ne $it.questionNumber) { $question = [long]$it.questionNumber }'
           Replace = 'if ($false) { $question = [long]$it.questionNumber }' }
        @{ Name = "non-ascii-is-sent-as-it-is"
           Find = 'return [regex]::Replace($text, ''[^\x20-\x7E]'', { param($m) ''\u'' + ([int][char]$m.Value).ToString("x4") })'
           Replace = 'return $text' }
        @{ Name = "fleet-db-is-read-on-every-look"
           Find = 'if ($print -ceq "$($Mine.pubPrint)") {'
           Replace = 'if ($false) {' }
        @{ Name = "no-fleet-db-sends-an-empty-member"
           Find = '$Mine.pubText = ""; $Mine.pubProblem = ""; return [pscustomobject]@{ text = ""; problem = "" } }'
           Replace = '$Mine.pubText = "[]"; $Mine.pubProblem = ""; return [pscustomobject]@{ text = "[]"; problem = "" } }' }
        @{ Name = "a-failed-read-drops-the-lists-last-read"
           Find = 'return [pscustomobject]@{ text = "$($Mine.pubText)"; problem = $said }'
           Replace = 'return [pscustomobject]@{ text = ""; problem = $said }' }
        @{ Name = "a-failed-read-is-said-every-time"
           Find = '$said = $(if ($problem -ceq "$($Mine.pubProblem)") { "" } else { $problem })'
           Replace = '$said = $problem' }
        @{ Name = "a-reader-that-exits-badly-is-believed"
           Find = 'if ([int]$r.code -ne 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "the-snapshot-does-not-carry-the-lists"
           Find = '$(if ($Published -cne "") { '',"published":'' + $Published } else { "" })'
           Replace = '""' }
        @{ Name = "a-changed-list-alone-sends-nothing"
           Find = '-and $published.text -ceq "$($mine.published)") { return'
           Replace = ') { return' }
    )
}
