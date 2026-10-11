# The memory messenger's fixture for test/test-messenger-conformance.ps1 (the contract is in that
# suite's header). The memory messenger keeps everything in this process, so the state is nothing but
# a clean store: New empties it, and Remove empties it again. What it observes is its store, the one
# place it acts: it has no session to type into, so typed is always empty and wakes always 0, read from
# no report of its own.
param([Parameter(Mandatory = $true)][string]$Root)
return [pscustomobject]@{
    New = { Reset-HordeMemoryMessenger; return @{} }
    Remove = { param($State) Reset-HordeMemoryMessenger }
    Observe = {
        param($State, $MessageId)
        $held = @(Get-HordeMemoryMessengerRecords | Where-Object { "$($_.message.messageId)" -ceq $MessageId })
        return [pscustomobject]@{ records = $held.Count; bodies = @($held | ForEach-Object { "$($_.message.body)" }); typed = @(); wakes = 0 }
    }
    # The memory messenger has no receiving hook; its test helper plays one. It declines
    # receipt.receiver for exactly that reason, so the conformance suite never calls this as proof.
    Receive = { param($State, $MessageId) Set-HordeMemoryMessengerStage -MessageId $MessageId -Stage "seen" }
}
