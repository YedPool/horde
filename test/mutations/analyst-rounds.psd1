# Mutations of core/AnalystRounds.ps1 (the analyst's rounds, PR 305).
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\analyst-rounds.psd1
# Each breaks one rule the review of PR 305 asked for; test\test-analyst-rounds.ps1 must fail for every one.
@{
    Target = "core\AnalystRounds.ps1"
    Suite  = "test\test-analyst-rounds.ps1"
    Mutations = @(
        # A burst of at-once items is one wake: never twice within nowGapMinutes of the last round.
        @{ Name = "now-gap-ignored"
           Find = 'if ($utcNow -lt $free) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "now-gap-never-read"
           Find = '$gapMinutes = $(if ($null -ne $gap) { [int]$gap.Value } else { 0 })'
           Replace = '$gapMinutes = 0' }
        @{ Name = "now-gap-off-by-one"
           Find = 'if ($null -ne $LastRoundAt -and $gapMinutes -gt 0) {'
           Replace = 'if ($null -ne $LastRoundAt -and $gapMinutes -gt 5) {' }
        # A line longer than one read is skipped as one unreadable item, never a reader stopped for ever.
        @{ Name = "oversized-line-waits-for-ever"
           Find = 'if ($end -lt 0 -and $got -ge $ReadMost) {'
           Replace = 'if ($false) {' }
        @{ Name = "oversized-line-offset-not-past-it"
           Find = 'offset = ($pos + $i + 1); restarted = $restarted }))'
           Replace = 'offset = $Offset; restarted = $restarted }))' }
        # An ack alert is told once per round.
        @{ Name = "alerted-round-alerted-again"
           Find = 'if ($null -eq $r -or $r.alerted -eq $true -or $Acked -ccontains ("" + $r.id)) { continue }'
           Replace = 'if ($null -eq $r -or $Acked -ccontains ("" + $r.id)) { continue }' }
        # T-0341: the bound and the number of starts are settings with a floor.
        @{ Name = "start-bound-default-changed"
           Find = 'default = 15; min = 2; max = 240'
           Replace = 'default = 20; min = 2; max = 240' }
        @{ Name = "start-bound-floor-removed"
           Find = 'default = 15; min = 2; max = 240'
           Replace = 'default = 15; min = 0; max = 240' }
        @{ Name = "start-attempts-default-changed"
           Find = 'default = 3; min = 1; max = 10'
           Replace = 'default = 4; min = 1; max = 10' }
        @{ Name = "start-attempts-floor-removed"
           Find = 'default = 3; min = 1; max = 10'
           Replace = 'default = 3; min = 0; max = 10' }
    )
}
