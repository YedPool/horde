# The memory source's fixture for test/test-conversation-conformance.ps1 (the contract is in that
# suite's header). Each state is a new store of its own; nothing is written to disk.
param([Parameter(Mandatory = $true)][string]$Root)
return [pscustomobject]@{
    New = {
        $store = New-HordeMemoryConversationStore
        $null = Get-HordeMemoryConversationHorde -Store $store -Fleet "conf"
        return [pscustomobject]@{ store = $store; fleet = "conf"; options = @{ memory = $store } }
    }
    Add = {
        param($State, $Turns)
        foreach ($t in @($Turns)) { Add-HordeMemoryConversationTurn -Store $State.store -Fleet $State.fleet -Role $t.role -Text $t.text }
    }
    # A turn in memory is added whole or not at all.
    Tear = { param($State, $Turn) return $false }
    Mend = { param($State) }
    Clear = { param($State) Clear-HordeMemoryConversation -Store $State.store -Fleet $State.fleet }
    Rotate = {
        param($State, $Turns)
        Reset-HordeMemoryConversationHistory -Store $State.store -Fleet $State.fleet
        foreach ($t in @($Turns)) { Add-HordeMemoryConversationTurn -Store $State.store -Fleet $State.fleet -Role $t.role -Text $t.text }
    }
    Remove = { param($State) $State.store.hordes.Clear() }
}
