# Mutations of the local relay. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-local.psd1
# Each mutation breaks one promise relays/local/Relay.ps1 makes in its capabilities.json or under the
# relay port's contract, and test\test-relay-conformance.ps1 must fail for every one. Every find string
# occurs exactly once.
#
# NOT HERE, and why: the seq sort in Get-HordeLocalRelayEntries (NTFS lists names in order already, so
# dropping the sort is invisible on this file system - the sort is for the others), the floor-before-
# delete order and the flush before the rename (only a kill or a power cut between two steps shows
# them, and no suite here can place one there).
@{
    Target = "relays\local\Relay.ps1"
    Suite  = "test\test-relay-conformance.ps1"
    Mutations = @(
        @{ Name = "lock-shared"
           Find = '[System.IO.FileShare]::None) }'
           Replace = '[System.IO.FileShare]::ReadWrite) }' }
        @{ Name = "duplicate-key-stored-again"
           Find = 'if ($held.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "key-hash-of-the-text"
           Find = '$hash = Get-HordeLocalRelayHash -Key $Key'
           Replace = '$hash = Get-HordeLocalRelayHash -Key $Text' }
        @{ Name = "seq-reused-after-trim"
           Find = '$head = $floor'
           Replace = '$head = [long]0' }
        @{ Name = "head-ignores-items"
           Find = 'if ($sorted.Count -gt 0 -and $sorted[$sorted.Count - 1].seq -gt $head) {'
           Replace = 'if ($false) {' }
        @{ Name = "ack-trims-nothing"
           Find = 'foreach ($e in @($now.items | Where-Object { $_.seq -le $Through })) { [System.IO.File]::Delete($e.path) }'
           Replace = '' }
        @{ Name = "ack-past-head-accepted"
           Find = 'if ($Through -gt $now.head) {'
           Replace = 'if ($false) {' }
        @{ Name = "own-text-cap-dropped"
           Find = 'if ($Text.Length -eq 0 -or $Text.Length -gt $script:HordeLocalRelayMaxText -or'
           Replace = 'if ($Text.Length -eq 0 -or' }
        @{ Name = "batch-ignored"
           Find = 'if ($out.Count -ge $Max) { break }'
           Replace = '' }
        @{ Name = "watch-never-waits"
           Find = 'if ($left -le 0) {'
           Replace = 'if ($true) {' }
        @{ Name = "watch-polls-too-slowly-for-realtime"
           Find = '$script:HordeLocalRelayPollMs = 50'
           Replace = '$script:HordeLocalRelayPollMs = 5000' }
        @{ Name = "watch-misses-items-already-there"
           Find = 'if ($items.Count -gt 0) { return (New-HordeKnown -Value ([pscustomobject]@{ ended = $true; items = $items })'
           Replace = 'if ($items.Count -gt 0 -and $Watch.began.ElapsedMilliseconds -ge $Watch.timeoutMs) { return (New-HordeKnown -Value ([pscustomobject]@{ ended = $true; items = $items })' }
        # --- the watch in slices (relays/Port.ps1, A WATCH IN SLICES)
        @{ Name = "slice-waits-out-the-whole-watch"
           Find = 'if ($leftOfSlice -le 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "slice-over-ends-the-watch"
           Find = 'return (New-HordeKnown -Value ([pscustomobject]@{ ended = $false; items = @() })'
           Replace = 'return (New-HordeKnown -Value ([pscustomobject]@{ ended = $true; items = @() })' }
        @{ Name = "each-slice-starts-the-watch-again"
           Find = '$left = $Watch.timeoutMs - $Watch.began.ElapsedMilliseconds'
           Replace = '$left = $Watch.timeoutMs - $slice.ElapsedMilliseconds' }
        @{ Name = "slice-sleeps-past-its-end"
           Find = '[Math]::Min($script:HordeLocalRelayPollMs, [Math]::Min($left, $leftOfSlice))'
           Replace = '[Math]::Max(5000, [Math]::Min($left, $leftOfSlice))' }
        @{ Name = "empty-read-is-one-null-item"
           Find = '$items = @(Read-HordeLocalRelayItems -Dir (Get-HordeLocalRelayDir -State $State -Mailbox $Mailbox) -Since $Since -Max $Max)'
           Replace = '$items = Read-HordeLocalRelayItems -Dir (Get-HordeLocalRelayDir -State $State -Mailbox $Mailbox) -Since $Since -Max $Max; if ($null -eq $items) { $items = @($null) }' }
    )
}
