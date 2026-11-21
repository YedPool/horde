# Mutations of tools/HeavySlot.ps1 for its waiters' line (T-0471): first come first served by a ticket, among waiters
# ready to run. Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\heavy-slot-queue.psd1
# test\test-heavy-slot.ps1 must fail for every one of them.
@{
    Target = "tools\HeavySlot.ps1"
    Suite  = "test\test-heavy-slot.ps1"
    Mutations = @(
        @{ Name = "no-line-kept"
           Find = '-GetNetClaim $claimCheck -GetTurn $turnCheck'
           Replace = '-GetNetClaim $claimCheck -GetTurn $null' }
        @{ Name = "a-stale-ticket-holds-back"
           Find = 'if (($now - $t.LastWriteTimeUtc).TotalSeconds -gt $FreshSeconds) { continue }'
           Replace = 'if ($false) { continue }' }
        @{ Name = "a-dead-waiters-ticket-holds-back"
           Find = 'if (-not $alive) { Remove-Item -LiteralPath $t.FullName -Force -ErrorAction SilentlyContinue; continue }'
           Replace = 'if ($false) { Remove-Item -LiteralPath $t.FullName -Force -ErrorAction SilentlyContinue; continue }' }
        @{ Name = "a-reused-id-taken-for-the-waiter"
           Find = '$alive = ($null -ne $p -and $p.StartTime.ToUniversalTime().Ticks -eq [long]$body[1].Trim())'
           Replace = '$alive = ($null -ne $p)' }
        @{ Name = "a-later-ticket-holds-back"
           Find = 'if ($theirs -gt $Arrival -or ($theirs -eq $Arrival -and $theirPid -ge $PID)) { continue }'
           Replace = 'if ($false) { continue }' }
        @{ Name = "ticket-kept-while-running"
           Find = 'Remove-HordeHeavySlotTicket -Dir $script:queueDir -Mine $script:ticket  # held now'
           Replace = '$null = $script:ticket  # held now' }
        @{ Name = "ticket-kept-after-the-gate-ends"
           Find = 'Remove-HordeHeavySlotTicket -Mine $script:ticket -Dir $script:queueDir'
           Replace = '$null = $script:ticket' }
        @{ Name = "turn-give-up-in-the-slots-words"
           Find = 'if ($got.blocker -ceq "turn") {'
           Replace = 'if ($false) {' }
    )
}
