# Mutations of the Orc registry (orcs/Registry.ps1): the fold, the derived status, Wargs and open
# questions, and the refusals of a write. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\orcs-registry.psd1
# test\test-orcs-registry.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "orcs\Registry.ps1"
    Suite  = "test\test-orcs-registry.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-stale-version-is-written"
           Find = 'if ($Version -ge 0 -and $Version -ne $first.version) {'
           Replace = 'if ($false) {' }
        @{ Name = "an-order-missing-an-orc-is-taken"
           Find = 'if ($missing.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "an-order-naming-a-stranger-is-taken"
           Find = 'if ($extra.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "an-order-naming-one-twice-is-taken"
           Find = 'if ($dups.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-refusal-registers-the-lanes-first"
           Find = 'if ($judged.refuse -ne "") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "waiting-on-nothing-blocks"
           Find = '$w -inotmatch ''\A(nothing|none)\b'''
           Replace = '$true' }
        @{ Name = "a-question-that-blocks-all-does-not-block"
           Find = 'if ($q.blocksAll) { [void]$blocks.Add($q.addedAt) }'
           Replace = '' }
        @{ Name = "working-lasts-twenty-minutes"
           Find = '-le $WorkingMinutes) { $word = "working" }'
           Replace = '-le ($WorkingMinutes + 5)) { $word = "working" }' }
        @{ Name = "a-warg-is-active-for-twenty-minutes"
           Find = '-le $Paths.workingMinutes) { $active++ }'
           Replace = '-le ($Paths.workingMinutes + 5)) { $active++ }' }
        @{ Name = "a-warg-with-no-orc-is-guessed-by-its-label"
           Find = '$s.owner -cmatch ''\A[A-Z]\z'') { $letter = $s.owner }'
           Replace = '$s.label -cmatch ''\A[A-Z]'') { $letter = $s.label.Substring(0, 1) }' }
        @{ Name = "a-retired-session-is-counted"
           Find = 'if ($s.retired) { continue }'
           Replace = '' }
        @{ Name = "an-answered-question-is-counted-open"
           Find = '-and "$($q.thread.turn)" -ceq $turn)'
           Replace = ')' }
        @{ Name = "the-oldest-activity-is-taken"
           Find = '-and ($null -eq $best -or [datetime]$c[0] -gt $best)) {'
           Replace = '-and ($null -eq $best -or [datetime]$c[0] -lt $best)) {' }
        @{ Name = "an-answer-is-not-activity"
           Find = '[void]$seen.Add(@($q.addedAt, "decision")); [void]$seen.Add(@($q.answeredAt, "decision"))'
           Replace = '[void]$seen.Add(@($q.addedAt, "decision"))' }
        @{ Name = "progress-is-named-as-status"
           Find = '[void]$seen.Add(@($e.at, "progress"))'
           Replace = '[void]$seen.Add(@($e.at, "status"))' }
        @{ Name = "an-area-entry-is-nobodys"
           Find = '-ceq $area) { return @($a.lanes) } }'
           Replace = '-ceq $area) { return @() } }' }
        @{ Name = "the-area-wins-over-the-entrys-own-lanes"
           Find = 'if ($own.Count -gt 0) { return $own }'
           Replace = '' }
        @{ Name = "a-lane-list-is-not-trimmed"
           Find = '$own = @((ConvertTo-HordeOrcJsText (& $get "lane")).Split([char]'','') | ForEach-Object { $_.Trim() }'
           Replace = '$own = @((ConvertTo-HordeOrcJsText (& $get "lane")).Split([char]'','') | ForEach-Object { $_ }' }
        @{ Name = "an-orc-retired-by-hand-comes-back"
           Find = '($s.orcs[$l.id].retired -and $s.orcs[$l.id].retiredBy -ceq "fleet")'
           Replace = '$s.orcs[$l.id].retired' }
        @{ Name = "a-domain-may-be-81-characters"
           Find = '$script:HordeOrcDomainMost = 80'
           Replace = '$script:HordeOrcDomainMost = 81' }
        @{ Name = "a-lane-the-fleet-retired-stays-on-the-list"
           Find = '$gone = @(@($Lanes.fleetRetired) + @($Lanes.notOrcs))'
           Replace = '$gone = @($Lanes.notOrcs)' }
        @{ Name = "a-sub-lane-question-is-not-its-orcs"
           Find = '[regex]::Match($name, ''\AOrc ([A-Z][0-9]{0,3})(?![A-Za-z0-9])'')'
           Replace = '[regex]::Match($name, ''\AOrc ([A-Z])(?![A-Za-z])'')' }
        @{ Name = "the-inactive-wargs-are-not-sent"
           Find = '"wargsActive", "wargsInactive", '
           Replace = '"wargsActive", ' }
        @{ Name = "a-new-lane-is-not-shown-until-registered"
           Find = '& $add ([pscustomobject]@{ id = $l.id;'
           Replace = '& { } ([pscustomobject]@{ id = $l.id;' }
        @{ Name = "a-damaged-record-stops-the-fold"
           Find = 'if ($r.kind -cne "ok") { [void]$s.unreadable.Add([pscustomobject]@{ sequence = [long]$r.sequence; reason = "$($r.reason)" }); continue }'
           Replace = 'if ($r.kind -cne "ok") { [void]$s.unreadable.Add([pscustomobject]@{ sequence = [long]$r.sequence; reason = "$($r.reason)" }); break }' }
    )
}
