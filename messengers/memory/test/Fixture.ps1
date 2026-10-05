# The memory messenger's fixture for test/test-messenger-conformance.ps1 (the contract is in that
# suite's header). The memory messenger keeps everything in this process, so the state is nothing but
# a clean store: New empties it, and Remove empties it again.
param([Parameter(Mandatory = $true)][string]$Root)
return [pscustomobject]@{
    New = { Reset-HordeMemoryMessenger; return @{} }
    Remove = { param($State) Reset-HordeMemoryMessenger }
    Observe = {
        param($State, $MessageId)
        $log = Get-HordeMemoryMessengerLog -MessageId $MessageId
        return [pscustomobject]@{ records = $log.records; typed = $log.typed; wakes = $log.wakes }
    }
    # The memory messenger has no receiving hook; its test helper plays one. It declines
    # receipt.receiver for exactly that reason, so the conformance suite never calls this as proof.
    Receive = { param($State, $MessageId) Set-HordeMemoryMessengerStage -MessageId $MessageId -Stage "seen" }
}
