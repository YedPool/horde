# test/lib/MemoryConversation.ps1 - a conversation source held in memory, for the port's own suites.
#
# WHY IT EXISTS (relay design 2026-10-09, PR plan item 9: "a memory source for tests"). The port must
# be proven on its own, apart from any harness's file format, and the chat channel (the next pull
# request) needs a source it can drive without a transcript on disk. So this source keeps each horde's
# Thrall conversation as a list of turns, and can be told to LIE: every way an adapter's answer can be
# wrong, so test/test-conversation-port.ps1 can show the port refuses or repairs each one.
#
# WHY IT LIVES UNDER test/ AND NOT agents/. Every folder under agents/ is a harness, and the port finds
# conversation adapters there. This is not a harness; it is registered through the port like any
# adapter (the port calls nothing it did not register), from test/fixtures/conversations/memory.
#
# A STORE is made by New-HordeMemoryConversationStore and handed to the port in Find-HordeConversationSource's
# -Options as @{ memory = <store> }. Each horde in it has a session id, a generation (bumped by a
# rotation, which a read from an older cursor reports), and its turns.
#
# Lies, set per horde with Set-HordeMemoryConversationLie (one at a time; "" means honest):
#   locate-throw, locate-garbage, locate-unknown, locate-bad-session
#   read-throw (with a secret in the message), read-garbage, read-unknown, read-absent
#   bad-role, empty-text, bad-turn-id, duplicate-turn-id, bad-time, bad-group-id, not-an-object,
#   no-time, overfill, bad-position, long-position, bad-more, bad-reset, no-turns, secret-anomaly,
#   rotate-always (a rotation even on a read from the start, where there is nothing to have rewritten)
#
# Requires conversations/Port.ps1 to be loaded first.

$script:HordeMemoryConversationFolder = Join-Path (Split-Path -Parent $PSScriptRoot) "fixtures\conversations\memory"
if ($null -eq (Get-Variable -Name HordeMemoryConversationStores -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeMemoryConversationStores = @{} }

function New-HordeMemoryConversationStore {
    $s = [pscustomobject]@{ id = [guid]::NewGuid().ToString("N"); hordes = @{} }
    $script:HordeMemoryConversationStores[$s.id] = $s
    return $s
}

function Get-HordeMemoryConversationHorde {
    # The horde's entry in a store, made on first use with a new session.
    param($Store, [string]$Fleet)
    if (-not $Store.hordes.ContainsKey($Fleet)) {
        $Store.hordes[$Fleet] = [pscustomobject]@{ session = ("mem-" + [guid]::NewGuid().ToString("N").Substring(0, 12)); generation = 1; turns = (New-Object System.Collections.ArrayList); lie = ""; next = 1 }
    }
    return $Store.hordes[$Fleet]
}

function Add-HordeMemoryConversationTurn {
    # Add one turn as an adapter would read it: raw, unredacted, with an id and a time of its own.
    param($Store, [string]$Fleet, [string]$Role, [string]$Text, [string]$GroupId = "")
    $h = Get-HordeMemoryConversationHorde -Store $Store -Fleet $Fleet
    $t = [ordered]@{ role = $Role; text = $Text; time = [datetime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ"); turnId = ($h.session + "-" + $h.next) }
    if ($GroupId -ne "") { $t["groupId"] = $GroupId }
    $h.next++
    [void]$h.turns.Add([pscustomobject]$t)
}

function Clear-HordeMemoryConversation {
    # The harness's clear: a new session, with no turns.
    param($Store, [string]$Fleet)
    $h = Get-HordeMemoryConversationHorde -Store $Store -Fleet $Fleet
    $h.session = "mem-" + [guid]::NewGuid().ToString("N").Substring(0, 12)
    $h.turns.Clear()
    $h.next = 1
}

function Reset-HordeMemoryConversationHistory {
    # A rotation: the same session's history replaced, which a read from an older cursor must report.
    param($Store, [string]$Fleet)
    $h = Get-HordeMemoryConversationHorde -Store $Store -Fleet $Fleet
    $h.generation++
    $h.turns.Clear()
}

function Set-HordeMemoryConversationLie {
    param($Store, [string]$Fleet, [string]$Lie = "")
    (Get-HordeMemoryConversationHorde -Store $Store -Fleet $Fleet).lie = $Lie
}

$null = Register-HordeConversationAdapter -Folder $script:HordeMemoryConversationFolder -Locate {
    param($Request)
    $store = $null
    if ($null -ne $Request.options -and $Request.options -is [System.Collections.IDictionary] -and $Request.options.Contains("memory")) { $store = $Request.options["memory"] }
    if ($null -eq $store -or -not $store.hordes.ContainsKey($Request.fleet)) { return (New-HordeAbsent -Note "no memory conversation for this horde") }
    $h = $store.hordes[$Request.fleet]
    switch ($h.lie) {
        "locate-throw" { throw "the memory source failed to locate" }
        "locate-garbage" { return "not an answer" }
        "locate-unknown" { return (New-HordeUnknown -Reason "the memory source does not know") }
        "locate-bad-session" { return (New-HordeKnown -Value ([pscustomobject]@{ session = "has spaces in it"; locator = ($store.id + "/" + $Request.fleet) })) }
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ session = $h.session; locator = ($store.id + "/" + $Request.fleet) }))
} -Read {
    param($Source, [string]$Position, [int]$MaxTurns, [long]$MaxBytes)
    $parts = $Source.locator.Split([char]'/')
    $store = $script:HordeMemoryConversationStores[$parts[0]]
    $h = $store.hordes[$parts[1]]
    switch ($h.lie) {
        "read-throw" { throw ("the memory source failed with password=" + "hunter2longer in its message") }
        "read-garbage" { return 42 }
        "read-unknown" { return (New-HordeUnknown -Reason "the memory source cannot read now") }
        "read-absent" { return (New-HordeAbsent -Note "nothing") }
    }
    # POSITION: "g<generation>.i<index>". A cursor of an older generation is a rotation.
    $index = 0
    $reset = ""
    if ($Position -ne "") {
        if ($Position -notmatch '\Ag(\d+)\.i(\d+)\z') { return (New-HordeUnknown -Reason "the position is not one this source writes") }
        if ([int]$Matches[1] -ne $h.generation) { $reset = "rotated" } else { $index = [int]$Matches[2] }
    }
    $take = @()
    if ($index -lt $h.turns.Count) { $take = @($h.turns.GetRange($index, [Math]::Min($MaxTurns, $h.turns.Count - $index)).ToArray()) }
    $after = $index + $take.Count
    $turns = @($take | ForEach-Object { [pscustomobject]@{ role = $_.role; text = $_.text; time = $_.time; turnId = $_.turnId } })
    for ($i = 0; $i -lt $take.Count; $i++) { if ($null -ne $take[$i].PSObject.Properties["groupId"]) { $turns[$i] | Add-Member -NotePropertyName groupId -NotePropertyValue $take[$i].groupId } }
    $value = [ordered]@{ turns = $turns; position = ("g" + $h.generation + ".i" + $after); more = ($after -lt $h.turns.Count); reset = $reset; anomalies = @() }
    if ($turns.Count -gt 0) {
        switch ($h.lie) {
            "bad-role" { $turns[0].role = "tool" }
            "empty-text" { $turns[0].text = "   " }
            "bad-turn-id" { $turns[0].turnId = "has spaces and password=" + "hunter2longer" }
            "duplicate-turn-id" { if ($turns.Count -gt 1) { $turns[1].turnId = $turns[0].turnId } }
            "bad-time" { $turns[0].time = "yesterday" }
            "no-time" { $turns[0].PSObject.Properties.Remove("time") }
            "bad-group-id" { $turns[0] | Add-Member -NotePropertyName groupId -NotePropertyValue "a group id with spaces" -Force }
            "not-an-object" { $turns[0] = "a bare string" }
            "overfill" { $value.turns = @($turns) + @($turns | ForEach-Object { [pscustomobject]@{ role = $_.role; text = $_.text; time = $_.time; turnId = ($_.turnId + "-extra") } }) }
        }
    }
    switch ($h.lie) {
        "bad-position" { $value.position = 7 }
        "long-position" { $value.position = ("p" * 2000) }
        "bad-more" { $value.more = "yes" }
        "bad-reset" { $value.reset = "sideways" }
        "rotate-always" { $value.reset = "rotated" }
        "no-turns" { $value.Remove("turns") }
        "secret-anomaly" { $value.anomalies = @("saw token=" + "q8Wv3Lm9Zr4 on the way") }
    }
    return (New-HordeKnown -Value ([pscustomobject]$value))
}
