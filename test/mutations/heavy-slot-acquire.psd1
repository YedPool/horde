# Mutations of core/HeavySlotAcquire.ps1: wait first, take last. Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\heavy-slot-acquire.psd1
@{
    Target = "core\HeavySlotAcquire.ps1"
    Suite  = "test\test-heavy-slot-acquire.ps1"
    Mutations = @(
        @{ Name = "memory-not-waited-for-before-the-slot"
           Find = '            if ($free -lt $MinFreeGB) {'
           Replace = '            if ($false) {' }
        @{ Name = "idle-not-waited-for-before-the-slot"
           Find = '        if (-not $idle.allowed) {'
           Replace = '        if ($false) {' }
        @{ Name = "floor-not-rechecked-after-the-take"
           Find = 'if ($idleNow.allowed -and $freeNow -ge $MinFreeGB -and $commitNow -ge $MinCommitHeadroomGB) {'
           Replace = 'if ($idleNow.allowed -and $commitNow -ge $MinCommitHeadroomGB) {' }
        @{ Name = "idle-not-rechecked-after-the-take"
           Find = 'if ($idleNow.allowed -and $freeNow -ge $MinFreeGB -and $commitNow -ge $MinCommitHeadroomGB) {'
           Replace = 'if ($freeNow -ge $MinFreeGB -and $commitNow -ge $MinCommitHeadroomGB) {' }
        @{ Name = "commit-not-rechecked-after-the-take"
           Find = 'if ($idleNow.allowed -and $freeNow -ge $MinFreeGB -and $commitNow -ge $MinCommitHeadroomGB) {'
           Replace = 'if ($idleNow.allowed -and $freeNow -ge $MinFreeGB) {' }
        @{ Name = "commit-not-waited-for-before-the-slot"
           Find = '} elseif ($useCommit -and ($commit = [double](& $GetCommitHeadroomGB)) -lt $MinCommitHeadroomGB) {'
           Replace = '} elseif ($false) {' }
        @{ Name = "commit-asked-when-off"
           Find = '$useCommit = ($MinCommitHeadroomGB -gt 0)'
           Replace = '$useCommit = ($null -ne $GetCommitHeadroomGB)' }
        @{ Name = "holders-smallest-first"
           Find = '@{ Expression = { $_.bytes }; Descending = $true }'
           Replace = '@{ Expression = { $_.bytes }; Descending = $false }' }
        @{ Name = "holders-not-grouped"
           Find = '        $groups[$n].count++'
           Replace = '        $groups[$n].count = 1' }
        @{ Name = "slot-kept-when-the-floor-failed"
           Find = '                & $ReleaseSlot'
           Replace = '                $null = 1' }
        @{ Name = "slot-wait-given-its-own-time"
           Find = '[int][math]::Min($SliceMs, [math]::Max(0, $left * 1000))'
           Replace = '$SliceMs' }
        @{ Name = "timeout-blocker-lost"
           Find = 'return [pscustomobject]@{ state = "timeout"; blocker = $blocker } }'
           Replace = 'return [pscustomobject]@{ state = "timeout"; blocker = "slot" } }' }
        @{ Name = "memory-wait-said-every-poll"
           Find = '                if (-not $saidMemory) {'
           Replace = '                if ($true) {' }
        @{ Name = "no-look-at-wait-zero"
           Find = '    while ($true) {'
           Replace = '    while ($WaitSeconds -gt 0) {' }
    )
}