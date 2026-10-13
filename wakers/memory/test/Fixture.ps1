# The memory waker's fixture for test/test-waker-conformance.ps1 (the contract is in that suite's
# header). The memory waker keeps everything in this process, so the state is nothing but a clean table:
# New empties it, and Remove empties it again. Seat says what a session is. What Observe reads is the
# waker's record of the nudges it rang - the one place it acts - and the line each would have typed. It
# has no mailbox, so the body Seat is handed is held nowhere, which is why it can never be typed.
param([Parameter(Mandatory = $true)][string]$Root)
return [pscustomobject]@{
    New = { Reset-HordeMemoryWaker; return @{} }
    Remove = { param($State) Reset-HordeMemoryWaker }
    Seat = {
        param($State, $Session)
        Set-HordeMemoryWakerSession -Id $Session.id -Label $Session.label -Role $Session.role -Parent $Session.parent -UnreadCount $Session.unreadCount `
            -OldestUnreadAt $Session.oldestUnreadAt -Idle $Session.idle -BoxEmpty $Session.boxEmpty -MidTurn $Session.midTurn -Limited $Session.limited -BetweenTurns $Session.betweenTurns
    }
    Observe = {
        param($State, $Id)
        $got = @(Get-HordeMemoryWakerNudges -Id $Id)
        return [pscustomobject]@{ nudges = $got.Count; typed = @($got | ForEach-Object { "$($_.text)" }) }
    }
}
