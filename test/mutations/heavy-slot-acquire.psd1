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
           Find = 'if ($idleNow.allowed -and $freeNow -ge $MinFreeGB) {'
           Replace = 'if ($idleNow.allowed) {' }
        @{ Name = "idle-not-rechecked-after-the-take"
           Find = 'if ($idleNow.allowed -and $freeNow -ge $MinFreeGB) {'
           Replace = 'if ($freeNow -ge $MinFreeGB) {' }
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