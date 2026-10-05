# remote/Mirror - what the hub keeps of each node, and what it may say about the node's sessions.
#
# WHY (remote plan step R13a). The hub reads its nodes' sessions over the link (`horde hub serve`,
# cli/HubServe.ps1) and keeps the last inventory of each node in a mirror file. Everything the hub then
# says about a remote session is said from that mirror, so the rules of the remote design's section 7
# live here, as pure functions over a mirror and a time:
#   - A NODE THAT CANNOT BE HEARD MAKES ITS SESSIONS UNKNOWN, NEVER ABSENT. Once a pull fails, every
#     session of that node is unknown with "node D unreachable since T", T being the FIRST failed pull
#     since the node was last heard, not the latest retry; the last-known value is kept beside the
#     unknown, for a reader, and never shown as current (design 7.1). A hub that stopped pulling is the
#     same: a mirror older than the link's silence window (remote/Clock.ps1, 60 s) is not current.
#   - A PARTIAL INVENTORY NEVER MARKS A SESSION ABSENT. A session the node listed before and leaves out
#     of an inventory whose complete is not known true is carried, unknown, with when it was last seen.
#     Only a complete inventory can make a session absent (Get-HordeSessionLiveness, R6).
#   - A KEY ON TWO DEVICES IS A FAULT. A session is (agent, sessionId) (link-verbs v1 session-summary).
#     The same key listed by two devices is reported as a fault, both rows stay, and a lookup of the key
#     is unknown naming both devices. It is never resolved by picking one.
#   - A PULL IS A WHOLE INVENTORY. sessions.list returns every session the node sees, so each pull
#     replaces the mirror's list: after a dropped link the next pull leaves exactly the node's
#     inventory, nothing lost and nothing twice. Cursors come with a streamed verb (observe.since, R12b
#     and R13b); this file needs none.
#
# WHAT A MIRROR IS (schema/node-mirror.v1): the node's device id and name; heardAt, when the hub last
# received an inventory, by the hub's clock; lost, the first failure since then with the latest try and
# its reason; clock, the last ping's offset sample (R6); inventory, the sessions.list value exactly as
# it arrived, its node send time and hub receive time, and the carried sessions. Times are link text
# (Get-HordeLinkTime); every function here takes its times as UTC [datetime] and reads no clock.
#
# PURE. Nothing here reads or writes a file or the link: cli/HubServe.ps1 does both. remote/ is scanned
# by tools/ExecScan.ps1.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path $PSScriptRoot "Protocol.ps1")
. (Join-Path $PSScriptRoot "Clock.ps1")

# The fault kind for one session key listed by two or more devices.
$script:HordeMirrorTwoDevices = "session-on-two-devices"
# At most this many carried sessions are kept, the oldest dropped first: the listItems cap of
# link-frame.v1, so the carried list is checked by the same contract as an inventory (cli/HubServe.ps1).
# A session dropped here is not marked absent; a lookup of it reads unknown while the inventory is partial.
$script:HordeMirrorCarriedCap = 256
# The text of a link time, as the contract's time pattern admits it: whole seconds, or a fraction.
$script:HordeMirrorTimeFormats = @("yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'")

function ConvertFrom-HordeMirrorTime {
    # Link text to a UTC [datetime], or $null when it is not a link time this file can read.
    param($Text)
    if ($Text -isnot [string] -or $Text -eq "") { return $null }
    $out = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    if ([datetime]::TryParseExact($Text, [string[]]$script:HordeMirrorTimeFormats, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$out)) { return $out }
    return $null
}

function Assert-HordeMirrorUtc {
    param($Time, [string]$What)
    if (-not (Test-HordeClockUtc $Time)) { throw ($What + " must be a UTC [datetime]") }
}

function ConvertTo-HordeMirrorObject {
    # One shape for every mirror, whether built here or read from a file: parsed JSON. A round trip
    # through JSON is the one conversion both agree on (remote/NodeServe.ps1 does the same for answers).
    param([Parameter(Mandatory = $true)]$Value)
    return (($Value | ConvertTo-Json -Depth 40 -Compress) | ConvertFrom-Json)
}

function New-HordeNodeMirror {
    # A node the hub has not heard from yet.
    param([Parameter(Mandatory = $true)][string]$DeviceId, [Parameter(Mandatory = $true)][string]$DeviceName)
    # heardAt, lost, clock and inventory are left out until there is one: schema/node-mirror.v1 gives each
    # one type, and core/Schema.ps1 has no "or null".
    return (ConvertTo-HordeMirrorObject ([ordered]@{ schemaVersion = 1; deviceId = $DeviceId; deviceName = $DeviceName }))
}

function Get-HordeMirrorAgent {
    # A session's agent as its key holds it: the known value, or "" when the node could not say.
    param($Session)
    $a = Get-HordeLinkProp $Session "agent"
    if ("$(Get-HordeLinkProp $a 'state')" -ceq "known") { return "$(Get-HordeLinkProp $a 'value')" }
    return ""
}

function Test-HordeMirrorSameKey {
    # Are two sessions possibly the same (agent, sessionId)? The same id, and agents that are equal or
    # that one side could not name: an unknown agent cannot prove two sessions apart.
    param($A, $B)
    if ("$(Get-HordeLinkProp $A 'sessionId')" -cne "$(Get-HordeLinkProp $B 'sessionId')") { return $false }
    $x = Get-HordeMirrorAgent $A
    $y = Get-HordeMirrorAgent $B
    return ($x -eq "" -or $y -eq "" -or $x -ceq $y)
}

function Test-HordeMirrorComplete {
    # Is a sessions.list value's complete known true? Anything else is partial.
    param($List)
    $c = Get-HordeLinkProp $List "complete"
    $v = Get-HordeLinkProp $c "value"
    return ("$(Get-HordeLinkProp $c 'state')" -ceq "known" -and $v -is [bool] -and $v)
}

function Update-HordeNodeMirror {
    # The mirror after a pull that returned -List, a sessions.list value as the link's decoder accepted
    # it. The list replaces the last one whole. A session the last inventory held, or carried, that this
    # one leaves out is carried when this one is partial and dropped when it is complete. heardAt is
    # the receive time; lost is cleared. -Clock is the ping's sample (Get-HordeClockSample), or $null.
    param([Parameter(Mandatory = $true)]$Mirror, [Parameter(Mandatory = $true)]$List, $NodeSentAt, $ReceivedAt, $Clock = $null, [string]$DeviceName = "")
    Assert-HordeMirrorUtc $NodeSentAt "the node's send time"
    Assert-HordeMirrorUtc $ReceivedAt "the receive time"
    $now = @(Get-HordeLinkProp $List "sessions" | Where-Object { $null -ne $_ })
    $carried = New-Object System.Collections.ArrayList
    if (-not (Test-HordeMirrorComplete $List)) {
        $old = Get-HordeLinkProp $Mirror "inventory"
        $seen = New-Object System.Collections.ArrayList
        $oldAt = "$(Get-HordeLinkProp $old 'receivedAt')"
        foreach ($s in @(Get-HordeLinkProp (Get-HordeLinkProp $old "list") "sessions" | Where-Object { $null -ne $_ })) { [void]$seen.Add([ordered]@{ lastSeenAt = $oldAt; session = $s }) }
        foreach ($c in @(Get-HordeLinkProp $old "carried" | Where-Object { $null -ne $_ })) { [void]$seen.Add([ordered]@{ lastSeenAt = "$(Get-HordeLinkProp $c 'lastSeenAt')"; session = (Get-HordeLinkProp $c "session") }) }
        foreach ($e in $seen) {
            $listed = @($now | Where-Object { Test-HordeMirrorSameKey $_ $e["session"] })
            $twice = @($carried | Where-Object { Test-HordeMirrorSameKey $_["session"] $e["session"] })
            if ($listed.Count -eq 0 -and $twice.Count -eq 0) { [void]$carried.Add($e) }
        }
    }
    # Already newest first: the last inventory's sessions, then the sessions it carried, which were kept
    # newest first the same way. So the cap drops the oldest.
    $kept = @($carried | Select-Object -First $script:HordeMirrorCarriedCap)
    $name = "$(Get-HordeLinkProp $Mirror 'deviceName')"
    if ($DeviceName -ne "") { $name = $DeviceName }
    $clockOut = Get-HordeLinkProp $Mirror "clock"
    if ($null -ne $Clock -and "$(Get-HordeLinkProp $Clock 'state')" -ceq "known") {
        $clockOut = [ordered]@{ at = (Get-HordeLinkTime -At $ReceivedAt); offsetSeconds = [double]$Clock.value.offsetSeconds; roundTripSeconds = [double]$Clock.value.roundTripSeconds }
    }
    $inv = [ordered]@{ receivedAt = (Get-HordeLinkTime -At $ReceivedAt); nodeSentAt = (Get-HordeLinkTime -At $NodeSentAt); list = $List; carried = @($kept) }
    $out = [ordered]@{ schemaVersion = 1; deviceId = "$(Get-HordeLinkProp $Mirror 'deviceId')"; deviceName = $name; heardAt = (Get-HordeLinkTime -At $ReceivedAt) }
    if ($null -ne $clockOut) { $out["clock"] = $clockOut }
    $out["inventory"] = $inv
    return (ConvertTo-HordeMirrorObject $out)
}

function Set-HordeNodeMirrorLost {
    # The mirror after a pull that failed at -At for -Reason. since stays the first failure since the
    # node was last heard, so "unreachable since T" does not move with every retry; the inventory is
    # kept as the last-known one.
    param([Parameter(Mandatory = $true)]$Mirror, $At, [Parameter(Mandatory = $true)][string]$Reason)
    Assert-HordeMirrorUtc $At "the failure time"
    $since = Get-HordeLinkTime -At $At
    $old = Get-HordeLinkProp $Mirror "lost"
    $oldSince = "$(Get-HordeLinkProp $old 'since')"
    if ($null -ne (ConvertFrom-HordeMirrorTime $oldSince)) { $since = $oldSince }
    $why = $Reason
    if ($why.Trim() -eq "") { $why = "the pull failed and said no more" }
    $out = [ordered]@{}
    foreach ($p in @(Get-HordeLinkPairs $Mirror)) { $out[$p.Name] = $p.Value }
    $out["lost"] = [ordered]@{ since = $since; lastTryAt = (Get-HordeLinkTime -At $At); reason = $why }
    return (ConvertTo-HordeMirrorObject $out)
}

function Get-HordeMirrorNodeName {
    param($Mirror)
    return ("node " + (Get-HordeLinkProp $Mirror "deviceName") + " (" + (Get-HordeLinkProp $Mirror "deviceId") + ")")
}

function Get-HordeMirrorNodeAnswer {
    # Can the node be heard now? Known true while its last pull succeeded within the link's silence
    # window (R6's Get-HordeLinkLiveness). Otherwise unknown, and the reason names the node: unreachable
    # since the first failure, not heard since the last pull, or never heard. Never absent, never false.
    param([Parameter(Mandatory = $true)]$Mirror, $Now)
    Assert-HordeMirrorUtc $Now "now"
    $who = Get-HordeMirrorNodeName $Mirror
    $lost = Get-HordeLinkProp $Mirror "lost"
    if ($null -ne $lost) {
        return (New-HordeUnknown -Reason ($who + " unreachable since " + (Get-HordeLinkProp $lost "since") + ": " + (Get-HordeLinkProp $lost "reason")))
    }
    $heard = ConvertFrom-HordeMirrorTime (Get-HordeLinkProp $Mirror "heardAt")
    if ($null -eq $heard) { return (New-HordeUnknown -Reason ($who + " has not been heard from yet")) }
    $link = Get-HordeLinkLiveness -LastFrameAt $heard -Now $Now
    if ($link.state -ceq "known") { return (New-HordeKnown -Value $true -ObservedAt $heard) }
    return (New-HordeUnknown -Reason ($who + " not heard since its last pull: " + $link.reason + "; is the hub serving?"))
}

function ConvertFrom-HordeMirrorField {
    # One field of a received session as a Horde answer on the hub's clock: a known or absent answer is
    # re-timed by the node's own age for it (R6's New-HordeRemoteObservation), so a fast node clock does
    # not make it look fresh. An unknown keeps its reason. -Node is the node's answer: while it is not
    # known true, every field is unknown with the node's reason, whatever was last received.
    param($Field, [Parameter(Mandatory = $true)]$Node, $NodeSentAt, $ReceivedAt)
    if ($Node.state -cne "known") { return (New-HordeUnknown -Reason $Node.reason) }
    $state = "$(Get-HordeLinkProp $Field 'state')"
    if ($state -ceq "unknown") {
        $why = "$(Get-HordeLinkProp $Field 'reason')"
        if ($why.Trim() -eq "") { $why = "the node gave no reason" }
        return (New-HordeUnknown -Reason $why)
    }
    if (@("known", "absent") -cnotcontains $state) { return (New-HordeUnknown -Reason "the node sent no answer for this field") }
    $at = ConvertFrom-HordeMirrorTime (Get-HordeLinkProp $Field "observedAt")
    $a = $null
    if ($state -ceq "known") { $a = [pscustomobject]@{ state = "known"; value = (Get-HordeLinkProp $Field "value"); reason = ""; observedAt = $at } }
    else { $a = [pscustomobject]@{ state = "absent"; value = $null; reason = "$(Get-HordeLinkProp $Field 'reason')"; observedAt = $at } }
    return (New-HordeRemoteObservation -Answer $a -NodeSentAt $NodeSentAt -ReceivedAt $ReceivedAt).answer
}

# The summary fields a row carries, in link-verbs v1's order (session-summary).
$script:HordeMirrorFields = @("agent", "fleetSessionId", "role", "label", "parent", "liveStatus", "workState", "startedAt", "lastActivity", "retired", "pid", "procStart", "projectCwd")

function New-HordeMirrorRow {
    # One remote session as the hub shows it: its device, its id, whether it is there (presence), every
    # summary field as an answer, the namespace its pid was read in, and lastKnown - the session as last
    # received - whenever the answers are not current.
    param([Parameter(Mandatory = $true)]$Mirror, [Parameter(Mandatory = $true)]$Session, [Parameter(Mandatory = $true)]$Presence, [Parameter(Mandatory = $true)]$Node, $NodeSentAt, $ReceivedAt, [string]$LastSeenAt = "", [bool]$Carried = $false)
    $fields = [ordered]@{}
    foreach ($n in $script:HordeMirrorFields) {
        if ($Carried) { $fields[$n] = New-HordeUnknown -Reason $Presence.reason; continue }
        $fields[$n] = ConvertFrom-HordeMirrorField -Field (Get-HordeLinkProp $Session $n) -Node $Node -NodeSentAt $NodeSentAt -ReceivedAt $ReceivedAt
    }
    $last = $null
    if ($Carried -or $Node.state -cne "known") { $last = $Session }
    $ns = Get-HordeLinkProp (Get-HordeLinkProp $Session "pid") "ns"
    return [pscustomobject][ordered]@{ device = "$(Get-HordeLinkProp $Mirror 'deviceId')"; deviceName = "$(Get-HordeLinkProp $Mirror 'deviceName')"; sessionId = "$(Get-HordeLinkProp $Session 'sessionId')"; agent = (Get-HordeMirrorAgent $Session); presence = $Presence; fields = $fields; ns = $ns; lastSeenAt = $LastSeenAt; lastKnown = $last }
}

function Get-HordeMirrorRows {
    # Every session the mirror knows, as rows: those in the last inventory, then the carried ones.
    # Presence is R6's Get-HordeSessionLiveness: known true while the node is heard and lists it, aged
    # on the hub's clock past -TtlSeconds; unknown with the node's reason when it cannot be heard; a
    # carried session is unknown, its reason saying the inventory is partial and when it was last seen.
    param([Parameter(Mandatory = $true)]$Mirror, $Now, $TtlSeconds = $script:HordeLinkSilenceSeconds)
    Assert-HordeMirrorUtc $Now "now"
    $node = Get-HordeMirrorNodeAnswer -Mirror $Mirror -Now $Now
    $inv = Get-HordeLinkProp $Mirror "inventory"
    $rows = New-Object System.Collections.ArrayList
    if ($null -eq $inv) { return @() }
    $sent = ConvertFrom-HordeMirrorTime (Get-HordeLinkProp $inv "nodeSentAt")
    $got = ConvertFrom-HordeMirrorTime (Get-HordeLinkProp $inv "receivedAt")
    $list = Get-HordeLinkProp $inv "list"
    $complete = Test-HordeMirrorComplete $list
    $listAt = ConvertFrom-HordeMirrorTime (Get-HordeLinkProp $list "observedAt")
    foreach ($s in @(Get-HordeLinkProp $list "sessions" | Where-Object { $null -ne $_ })) {
        $obs = $null
        if ($null -ne $sent -and $null -ne $got) { $obs = New-HordeRemoteObservation -Answer ([pscustomobject]@{ state = "known"; value = $true; reason = ""; observedAt = $listAt }) -NodeSentAt $sent -ReceivedAt $got }
        $presence = Get-HordeSessionLiveness -Node $node -Observation $obs -InventoryComplete $complete -InInventory $true -TtlSeconds $TtlSeconds -Now $Now
        if ($node.state -cne "known") { $presence = New-HordeUnknown -Reason $node.reason }
        [void]$rows.Add((New-HordeMirrorRow -Mirror $Mirror -Session $s -Presence $presence -Node $node -NodeSentAt $sent -ReceivedAt $got -LastSeenAt "$(Get-HordeLinkProp $inv 'receivedAt')"))
    }
    foreach ($c in @(Get-HordeLinkProp $inv "carried" | Where-Object { $null -ne $_ })) {
        $seen = "$(Get-HordeLinkProp $c 'lastSeenAt')"
        $why = "the node's inventory is partial and does not list this session; last seen " + $seen
        if ($node.state -cne "known") { $why = $node.reason + "; this session was last seen " + $seen }
        [void]$rows.Add((New-HordeMirrorRow -Mirror $Mirror -Session (Get-HordeLinkProp $c "session") -Presence (New-HordeUnknown -Reason $why) -Node $node -NodeSentAt $sent -ReceivedAt $got -LastSeenAt $seen -Carried $true))
    }
    return @($rows)
}

function Get-HordeFleetView {
    # Every mirror at once: one entry per node (its answer, its inventory's size and completeness, its
    # clock), every remote session row, and the faults. A key listed by two devices is one fault naming
    # every device that lists it; both rows stay, each marked with the fault (twoDevices).
    param($Mirrors = @(), $Now, $TtlSeconds = $script:HordeLinkSilenceSeconds)
    Assert-HordeMirrorUtc $Now "now"
    $nodes = New-Object System.Collections.ArrayList
    $rows = New-Object System.Collections.ArrayList
    foreach ($m in @($Mirrors | Where-Object { $null -ne $_ })) {
        $mine = @(Get-HordeMirrorRows -Mirror $m -Now $Now -TtlSeconds $TtlSeconds)
        foreach ($r in $mine) { [void]$rows.Add($r) }
        $inv = Get-HordeLinkProp $m "inventory"
        $list = Get-HordeLinkProp $inv "list"
        $complete = New-HordeUnknown -Reason "no inventory has been received from this node"
        if ($null -ne $list) {
            $c = Get-HordeLinkProp $list "complete"
            if (Test-HordeMirrorComplete $list) { $complete = New-HordeKnown -Value $true }
            else { $complete = New-HordeKnown -Value $false; $complete.reason = "$(Get-HordeLinkProp $c 'reason')" }
        }
        $fault = New-HordeUnknown -Reason "no clock sample has been taken from this node"
        $clock = Get-HordeLinkProp $m "clock"
        if ($null -ne $clock) { $fault = Test-HordeClockFault -Sample (New-HordeKnown -Value ([pscustomobject]@{ offsetSeconds = [double](Get-HordeLinkProp $clock "offsetSeconds"); roundTripSeconds = [double](Get-HordeLinkProp $clock "roundTripSeconds") })) }
        [void]$nodes.Add([pscustomobject][ordered]@{ deviceId = "$(Get-HordeLinkProp $m 'deviceId')"; deviceName = "$(Get-HordeLinkProp $m 'deviceName')"; heard = (Get-HordeMirrorNodeAnswer -Mirror $m -Now $Now); heardAt = (Get-HordeLinkProp $m "heardAt"); complete = $complete; listed = @(Get-HordeLinkProp $list "sessions" | Where-Object { $null -ne $_ }).Count; carried = @(Get-HordeLinkProp $inv "carried" | Where-Object { $null -ne $_ }).Count; clockFault = $fault })
    }
    $faults = New-Object System.Collections.ArrayList
    $all = @($rows)
    for ($i = 0; $i -lt $all.Count; $i++) {
        $devices = New-Object System.Collections.ArrayList
        [void]$devices.Add($all[$i].device)
        $first = $true
        for ($j = 0; $j -lt $all.Count; $j++) {
            if ($j -eq $i -or $all[$j].device -ceq $all[$i].device) { continue }
            $a = [pscustomobject]@{ sessionId = $all[$i].sessionId; agent = [pscustomobject]@{ state = "known"; value = $all[$i].agent } }
            $b = [pscustomobject]@{ sessionId = $all[$j].sessionId; agent = [pscustomobject]@{ state = "known"; value = $all[$j].agent } }
            if (-not (Test-HordeMirrorSameKey $a $b)) { continue }
            if ($j -lt $i) { $first = $false }
            if ($devices -cnotcontains $all[$j].device) { [void]$devices.Add($all[$j].device) }
        }
        if ($devices.Count -lt 2) { continue }
        $all[$i] | Add-Member -NotePropertyName twoDevices -NotePropertyValue @($devices | Sort-Object) -Force
        if ($first) { [void]$faults.Add([pscustomobject][ordered]@{ kind = $script:HordeMirrorTwoDevices; sessionId = $all[$i].sessionId; agent = $all[$i].agent; devices = @($devices | Sort-Object) }) }
    }
    return [pscustomobject][ordered]@{ observedAt = (Get-HordeLinkTime -At $Now); nodes = $nodes.ToArray(); sessions = $all; faults = $faults.ToArray() }
}

function Find-HordeFleetSession {
    # One session of the fleet view by id (and agent, when given). Known, the row, when exactly one
    # device lists it; unknown naming the devices when more than one does - a fault, never resolved by
    # picking one; absent only when every node is heard and its inventory is complete and none lists it;
    # otherwise unknown, naming the nodes that could not say.
    param([Parameter(Mandatory = $true)]$Fleet, [Parameter(Mandatory = $true)][string]$SessionId, [string]$Agent = "")
    $want = [pscustomobject]@{ sessionId = $SessionId; agent = [pscustomobject]@{ state = "known"; value = $Agent } }
    $hits = @($Fleet.sessions | Where-Object { Test-HordeMirrorSameKey $want ([pscustomobject]@{ sessionId = $_.sessionId; agent = [pscustomobject]@{ state = "known"; value = $_.agent } }) })
    $devices = @($hits | ForEach-Object { $_.device } | Sort-Object -Unique)
    if ($devices.Count -gt 1) { return (New-HordeUnknown -Reason ("session " + $SessionId + " is listed on " + $devices.Count + " devices (" + ($devices -join ", ") + "): a fault, not resolved by picking one")) }
    if ($hits.Count -eq 1) { return (New-HordeKnown -Value $hits[0]) }
    if ($hits.Count -gt 1) { return (New-HordeUnknown -Reason ("" + $hits.Count + " sessions on device " + $devices[0] + " have the id " + $SessionId + "; name the agent to choose one")) }
    $silent = @($Fleet.nodes | Where-Object { $_.heard.state -cne "known" -or $_.complete.state -cne "known" -or $_.complete.value -ne $true } | ForEach-Object { $_.deviceName + " (" + $_.deviceId + ")" })
    if (@($Fleet.nodes).Count -eq 0) { return (New-HordeUnknown -Reason "the hub mirrors no node, so no session can be ruled out") }
    if ($silent.Count -eq 0) { return (New-HordeAbsent -Note ("every node was heard with a complete inventory, and none lists session " + $SessionId)) }
    return (New-HordeUnknown -Reason ("no node lists session " + $SessionId + ", but these could not rule it out: " + ($silent -join "; ")))
}
