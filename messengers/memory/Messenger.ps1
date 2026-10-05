# messengers/memory - a messenger inside one process, for tests only.
#
# WHY IT EXISTS (remote plan step R21). The node's delivery verbs, the message journal and the hub's
# routing are tested end to end without touching any session's mail; this is the messenger they run on.
# It DECLINES receipt.receiver in its capabilities.json, and the node's production path requires it
# (Resolve-HordeNodeMessenger in messengers/Port.ps1), so no production path can pick it. The port and
# conformance suites prove both halves of that.
#
# THE STORE is a table in this script scope, keyed by messageId: one record per id, holding the message,
# its stage, when it reached it, and how many times it was posted. Test helpers below play the receiving
# side (Set-HordeMemoryMessengerStage) and read what happened (Get-HordeMemoryMessengerLog); nothing
# else in Horde calls them.

$script:HordeMemoryMessengerFolder = $PSScriptRoot
$script:HordeMemoryMessengerStore = @{}
$script:HordeMemoryMessengerPosts = 0

function Reset-HordeMemoryMessenger {
    # Empty the store and its counters, so each test starts from nothing.
    $script:HordeMemoryMessengerStore = @{}
    $script:HordeMemoryMessengerPosts = 0
}

function Set-HordeMemoryMessengerStage {
    # Plays the receiving side: move one taken message to a later stage. Throws for a stage outside the
    # list or an id it never took - a test asking for that has a bug, not a state.
    param([Parameter(Mandatory = $true)][string]$MessageId, [Parameter(Mandatory = $true)][string]$Stage, [string]$Reason = "")
    if (@("accepted", "handed-over", "seen", "expired", "held") -cnotcontains $Stage) { throw ("'" + $Stage + "' is not a stage") }
    if (-not $script:HordeMemoryMessengerStore.ContainsKey($MessageId)) { throw ("the memory messenger never took " + $MessageId) }
    $r = $script:HordeMemoryMessengerStore[$MessageId]
    $r.stage = $Stage
    $r.at = [datetime]::UtcNow
    $r.reason = $Reason
}

function Get-HordeMemoryMessengerLog {
    # What happened: posts (every call, reposts included), records (messages held; for one id with
    # -MessageId), and typed and wakes, which this messenger never does and reports as 0 so a fixture
    # can read them like any messenger's.
    param([string]$MessageId = "")
    $records = $script:HordeMemoryMessengerStore.Count
    if ($MessageId) { $records = $(if ($script:HordeMemoryMessengerStore.ContainsKey($MessageId)) { 1 } else { 0 }) }
    return [pscustomobject]@{ posts = $script:HordeMemoryMessengerPosts; records = $records; typed = 0; wakes = 0 }
}

function ConvertTo-HordeMemoryMessengerAnswer {
    param($Record)
    return (New-HordeKnown -Value ([pscustomobject]@{ stage = $Record.stage; at = $Record.at; reason = $Record.reason }) -ObservedAt ([datetime]::UtcNow))
}

$null = Register-HordeMessenger -Folder $script:HordeMemoryMessengerFolder `
    -Post {
        param($Message)
        $script:HordeMemoryMessengerPosts++
        $id = "$($Message.messageId)"
        # ONE RECORD PER ID: a repost answers with what is recorded and delivers nothing more.
        if (-not $script:HordeMemoryMessengerStore.ContainsKey($id)) {
            $script:HordeMemoryMessengerStore[$id] = @{ message = $Message; stage = "accepted"; at = [datetime]::UtcNow; reason = "" }
        }
        return (ConvertTo-HordeMemoryMessengerAnswer $script:HordeMemoryMessengerStore[$id])
    } `
    -Status {
        param([string]$MessageId)
        if (-not $script:HordeMemoryMessengerStore.ContainsKey($MessageId)) { return (New-HordeAbsent -Note ("the memory messenger never took " + $MessageId) -ObservedAt ([datetime]::UtcNow)) }
        return (ConvertTo-HordeMemoryMessengerAnswer $script:HordeMemoryMessengerStore[$MessageId])
    }
