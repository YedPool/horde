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
#     Only a complete inventory can make a session absent (Get-HordeSessionLiveness, R6). A list that
#     says it names every session the node has (membershipComplete, verbs version 2: the stores the
#     node declares naming its sessions were read whole, and nothing was cut) is not carried from: a
#     session it leaves out has ended, and is dropped. Dropped, not marked absent: its fields may be
#     partial, so a lookup of the session stays unknown until an inventory is complete (L-101).
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
# The carried sessions must fit one frame as a sessions.list (cli/HubServe.ps1 checks them so): the
# frameBytes cap of link-frame.v1, less room for the frame's envelope. A count cap alone let 180 carried
# sessions of 10 KiB each reach 1,948,786 bytes, and the mirror could then never be written again
# (review of PR #86, F1). test/test-hub-serve.ps1 holds this number to the contract's own.
$script:HordeMirrorFrameBytes = 1048576
$script:HordeMirrorEnvelopeBytes = 8192
# The text of a link time, as the contract's time pattern admits it: whole seconds, or a fraction.
$script:HordeMirrorTimeFormats = @("yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'")

function ConvertFrom-HordeMirrorTime {
    # Link text to a UTC [datetime], or $null when it is not a link time this file can read. The link's
    # time pattern admits any number of fraction digits and .NET reads at most seven, so the fraction is
    # cut to seven first: an eighth digit made a schema-valid mirror unreadable and took every node of
    # `horde nodes` down with it (review of PR #86, F7).
    param($Text)
    if ($Text -isnot [string] -or $Text -eq "") { return $null }
    $m = [regex]::Match($Text, '\A([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})\.([0-9]{8,})Z\z')
    if ($m.Success) { $Text = $m.Groups[1].Value + "." + $m.Groups[2].Value.Substring(0, 7) + "Z" }
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
    # Parsed with ConvertFrom-HordeJson (core/JsonText.ps1, loaded by Protocol.ps1): bare ConvertFrom-Json
    # under 7 read heardAt and every other timestamp back as a [datetime], which node-mirror.v1 refuses (T-0366).
    param([Parameter(Mandatory = $true)]$Value)
    return (ConvertFrom-HordeJson -Text ($Value | ConvertTo-Json -Depth 40 -Compress))
}

function New-HordeNodeMirror {
    # A node the hub has not heard from yet.
    param([Parameter(Mandatory = $true)][string]$DeviceId, [Parameter(Mandatory = $true)][string]$DeviceName)
    # heardAt, lost, clock and inventory are left out until there is one: schema/node-mirror.v1 gives each
    # one type, and core/Schema.ps1 has no "or null".
    return (ConvertTo-HordeMirrorObject ([ordered]@{ schemaVersion = 1; deviceId = $DeviceId; deviceName = $DeviceName }))
}

function ConvertTo-HordeMirrorMap {
    # A parsed object's members as a hashtable, read in one pass. Each Get-HordeLinkProp on a parsed
    # session member costs about 0.3 ms (measured 2026-10-05, unthrottled), and a row read it 50 times;
    # one pass over the members costs about 0.05 ms (review of PR #86, F2).
    param($Object)
    $h = @{}
    if ($null -eq $Object -or $Object -is [string]) { return $h }
    if ($Object -is [System.Collections.IDictionary]) { foreach ($k in @($Object.Keys)) { $h["$k"] = $Object[$k] }; return $h }
    foreach ($p in $Object.PSObject.Properties) { $h[$p.Name] = $p.Value }
    return $h
}

function Get-HordeMirrorKey {
    # A session's key, worked out once: { id; agent }, agent being the known value or "" when the node
    # could not say.
    param($Session)
    $m = ConvertTo-HordeMirrorMap $Session
    $a = ConvertTo-HordeMirrorMap $m["agent"]
    $agent = ""
    if ("$($a['state'])" -ceq "known") { $agent = "$($a['value'])" }
    return [pscustomobject]@{ id = "$($m['sessionId'])"; agent = $agent }
}

function Get-HordeMirrorAgent {
    # A session's agent as its key holds it: the known value, or "" when the node could not say.
    param($Session)
    return (Get-HordeMirrorKey $Session).agent
}

function Test-HordeMirrorKeysMatch {
    # Are two keys possibly one session? The same id, and agents that are equal or that one side could
    # not name: an unknown agent cannot prove two sessions apart.
    param($K1, $K2)
    if ($K1.id -cne $K2.id) { return $false }
    $x = $K1.agent
    $y = $K2.agent
    return ($x -eq "" -or $y -eq "" -or $x -ceq $y)
}

function Test-HordeMirrorSameKey {
    # Are two sessions possibly the same (agent, sessionId)? See Test-HordeMirrorKeysMatch.
    param($A, $B)
    return (Test-HordeMirrorKeysMatch (Get-HordeMirrorKey $A) (Get-HordeMirrorKey $B))
}

function Add-HordeMirrorIndex {
    # File -Item in -Index under its key's id. Lookups by key then compare only the keys with that id:
    # comparing every pair took 11 to 30 s for one partial update at the 256 cap, and 54.7 s for a fleet
    # view of 768 rows (review of PR #86, F2).
    param([Parameter(Mandatory = $true)][hashtable]$Index, [Parameter(Mandatory = $true)]$Item, [Parameter(Mandatory = $true)]$Key)
    if (-not $Index.ContainsKey($Key.id)) { $Index[$Key.id] = New-Object System.Collections.ArrayList }
    [void]$Index[$Key.id].Add([pscustomobject]@{ item = $Item; key = $Key })
}

function Test-HordeMirrorIndexed {
    # Does -Index hold a key possibly the same as -Key (Test-HordeMirrorKeysMatch)?
    param([Parameter(Mandatory = $true)][hashtable]$Index, [Parameter(Mandatory = $true)]$Key)
    if (-not $Index.ContainsKey($Key.id)) { return $false }
    foreach ($e in $Index[$Key.id]) { if (Test-HordeMirrorKeysMatch $e.key $Key) { return $true } }
    return $false
}

function Limit-HordeMirrorCarried {
    # The carried entries, newest first, cut to the count cap and then to what fits one frame: the
    # oldest are shed first. A session shed here is not marked absent; a lookup of it is unknown while
    # the inventory is partial.
    param($Carried = @(), [int]$FrameBytes = $script:HordeMirrorFrameBytes)
    $kept = New-Object System.Collections.ArrayList
    $budget = $FrameBytes - $script:HordeMirrorEnvelopeBytes
    $used = 0
    foreach ($e in @($Carried | Select-Object -First $script:HordeMirrorCarriedCap)) {
        # The session as the link's writer spells it, and a comma between it and the next.
        $size = (ConvertTo-HordeWireText $e["session"]).Length + 1
        if ($used + $size -gt $budget) { break }
        $used = $used + $size
        [void]$kept.Add($e)
    }
    return $kept.ToArray()
}

function Test-HordeMirrorTrue {
    # Is a link answer known true - a real boolean true, never the text "true"? Anything else is not.
    param($Answer)
    $v = Get-HordeLinkProp $Answer "value"
    return ("$(Get-HordeLinkProp $Answer 'state')" -ceq "known" -and $v -is [bool] -and $v)
}

function Test-HordeMirrorComplete {
    # Is a sessions.list value's complete known true? Anything else is partial.
    param($List)
    return (Test-HordeMirrorTrue (Get-HordeLinkProp $List "complete"))
}

function Test-HordeMirrorMembershipComplete {
    # Does a sessions.list value say it names every session the node has (membershipComplete known
    # true, link-verbs verbs version 2)? Absent - an older node, or a hub that offered only version 1 -
    # false or unknown, and it does not: the list may leave out a live session.
    param($List)
    return (Test-HordeMirrorTrue (Get-HordeLinkProp $List "membershipComplete"))
}

function Update-HordeNodeMirror {
    # The mirror after a pull that returned -List, a sessions.list value as the link's decoder accepted
    # it. The list replaces the last one whole. A session the last inventory held, or carried, that this
    # one leaves out is carried when this one is partial and dropped when it is complete. It is
    # dropped too when the list names every session the node has (membershipComplete) though its
    # fields are partial: the always-on node has no host adapter, so its complete is never true, and
    # every session that ended was carried forever (ledger core-projection L-101). heardAt is
    # the receive time; lost is cleared. -Clock is the ping's sample (Get-HordeClockSample), or $null.
    param([Parameter(Mandatory = $true)]$Mirror, [Parameter(Mandatory = $true)]$List, $NodeSentAt, $ReceivedAt, $Clock = $null, [string]$DeviceName = "")
    Assert-HordeMirrorUtc $NodeSentAt "the node's send time"
    Assert-HordeMirrorUtc $ReceivedAt "the receive time"
    $now = @(Get-HordeLinkProp $List "sessions" | Where-Object { $null -ne $_ })
    $carried = New-Object System.Collections.ArrayList
    $listedIndex = @{}
    $carriedIndex = @{}
    foreach ($s in $now) { Add-HordeMirrorIndex -Index $listedIndex -Item $s -Key (Get-HordeMirrorKey $s) }
    if (-not (Test-HordeMirrorComplete $List) -and -not (Test-HordeMirrorMembershipComplete $List)) {
        $old = Get-HordeLinkProp $Mirror "inventory"
        $seen = New-Object System.Collections.ArrayList
        $oldAt = "$(Get-HordeLinkProp $old 'receivedAt')"
        foreach ($s in @(Get-HordeLinkProp (Get-HordeLinkProp $old "list") "sessions" | Where-Object { $null -ne $_ })) { [void]$seen.Add([ordered]@{ lastSeenAt = $oldAt; session = $s }) }
        foreach ($c in @(Get-HordeLinkProp $old "carried" | Where-Object { $null -ne $_ })) { [void]$seen.Add([ordered]@{ lastSeenAt = "$(Get-HordeLinkProp $c 'lastSeenAt')"; session = (Get-HordeLinkProp $c "session") }) }
        foreach ($e in $seen) {
            $k = Get-HordeMirrorKey $e["session"]
            $listed = Test-HordeMirrorIndexed -Index $listedIndex -Key $k
            $twice = Test-HordeMirrorIndexed -Index $carriedIndex -Key $k
            if (-not $listed -and -not $twice) { [void]$carried.Add($e); Add-HordeMirrorIndex -Index $carriedIndex -Item $e -Key $k }
        }
    }
    # Already newest first: the last inventory's sessions, then the sessions it carried, which were kept
    # newest first the same way. So the caps drop the oldest.
    $kept = @(Limit-HordeMirrorCarried -Carried $carried.ToArray())
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
    # -Timing (a hashtable, one per mirror) keeps each node stamp's re-timing: the fields of one list
    # share a handful of stamps, and re-timing each field afresh cost 5.4 ms a field, 22 s for 512 rows
    # (measured 2026-10-05, review of PR #86, F2).
    param($Field, [Parameter(Mandatory = $true)]$Node, $NodeSentAt, $ReceivedAt, $Timing = $null)
    if ($Node.state -cne "known") { return (New-HordeUnknown -Reason $Node.reason) }
    $f = ConvertTo-HordeMirrorMap $Field
    $state = "$($f['state'])"
    if ($state -ceq "unknown") {
        $why = "$($f['reason'])"
        if ($why.Trim() -eq "") { $why = "the node gave no reason" }
        return (New-HordeUnknown -Reason $why)
    }
    if (@("known", "absent") -cnotcontains $state) { return (New-HordeUnknown -Reason "the node sent no answer for this field") }
    $stamp = "$($f['observedAt'])"
    $t = $null
    if ($null -ne $Timing -and $Timing.ContainsKey($stamp)) { $t = $Timing[$stamp] }
    else {
        $probe = [pscustomobject]@{ state = "known"; value = $true; reason = ""; observedAt = (ConvertFrom-HordeMirrorTime $stamp) }
        $t = (New-HordeRemoteObservation -Answer $probe -NodeSentAt $NodeSentAt -ReceivedAt $ReceivedAt).answer
        if ($null -ne $Timing) { $Timing[$stamp] = $t }
    }
    if ($t.state -cne "known") { return (New-HordeUnknown -Reason $t.reason) }
    if ($state -ceq "known") { return (New-HordeKnown -Value $f["value"] -ObservedAt $t.observedAt) }
    return (New-HordeAbsent -Note "$($f['reason'])" -ObservedAt $t.observedAt)
}

# The summary fields a row carries, in link-verbs v1's order (session-summary).
$script:HordeMirrorFields = @("agent", "fleetSessionId", "role", "label", "parent", "liveStatus", "workState", "startedAt", "lastActivity", "retired", "pid", "procStart", "projectCwd")

function New-HordeMirrorRow {
    # One remote session as the hub shows it: its device, its id, whether it is there (presence), every
    # summary field as an answer, the namespace its pid was read in, and lastKnown - the session as last
    # received - whenever the answers are not current.
    param([Parameter(Mandatory = $true)]$Mirror, [Parameter(Mandatory = $true)]$Session, [Parameter(Mandatory = $true)]$Presence, [Parameter(Mandatory = $true)]$Node, $NodeSentAt, $ReceivedAt, [string]$LastSeenAt = "", [bool]$Carried = $false, $Timing = $null)
    $fields = [ordered]@{}
    $map = ConvertTo-HordeMirrorMap $Session
    foreach ($n in $script:HordeMirrorFields) {
        if ($Carried) { $fields[$n] = New-HordeUnknown -Reason $Presence.reason; continue }
        $fields[$n] = ConvertFrom-HordeMirrorField -Field $map[$n] -Node $Node -NodeSentAt $NodeSentAt -ReceivedAt $ReceivedAt -Timing $Timing
    }
    $last = $null
    if ($Carried -or $Node.state -cne "known") { $last = $Session }
    $ns = (ConvertTo-HordeMirrorMap $map["pid"])["ns"]
    $key = Get-HordeMirrorKey $Session
    return [pscustomobject][ordered]@{ device = "$(Get-HordeLinkProp $Mirror 'deviceId')"; deviceName = "$(Get-HordeLinkProp $Mirror 'deviceName')"; sessionId = $key.id; agent = $key.agent; presence = $Presence; fields = $fields; ns = $ns; lastSeenAt = $LastSeenAt; lastKnown = $last }
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
    # A mirror whose own times cannot be read cannot date anything the node said: its sessions are
    # unknown, and nothing below is asked to age an answer with no time (review of PR #86, F7).
    if ($null -eq $sent -or $null -eq $got) { $node = New-HordeUnknown -Reason ((Get-HordeMirrorNodeName $Mirror) + ": the mirror's send or receive time cannot be read, so nothing it holds can be dated") }
    $list = Get-HordeLinkProp $inv "list"
    # complete, not membershipComplete: every row here is a session the list holds (InInventory), for
    # which Get-HordeSessionLiveness reads the node's own answer and never this flag.
    $complete = Test-HordeMirrorComplete $list
    $listAt = ConvertFrom-HordeMirrorTime (Get-HordeLinkProp $list "observedAt")
    # Every listed session is present by the same observation, the list's: worked out once.
    $obs = $null
    if ($null -ne $sent -and $null -ne $got) { $obs = New-HordeRemoteObservation -Answer ([pscustomobject]@{ state = "known"; value = $true; reason = ""; observedAt = $listAt }) -NodeSentAt $sent -ReceivedAt $got }
    $presence = Get-HordeSessionLiveness -Node $node -Observation $obs -InventoryComplete $complete -InInventory $true -TtlSeconds $TtlSeconds -Now $Now
    if ($node.state -cne "known") { $presence = New-HordeUnknown -Reason $node.reason }
    $timing = @{}
    foreach ($s in @(Get-HordeLinkProp $list "sessions" | Where-Object { $null -ne $_ })) {
        [void]$rows.Add((New-HordeMirrorRow -Mirror $Mirror -Session $s -Presence $presence -Node $node -NodeSentAt $sent -ReceivedAt $got -LastSeenAt "$(Get-HordeLinkProp $inv 'receivedAt')" -Timing $timing))
    }
    foreach ($c in @(Get-HordeLinkProp $inv "carried" | Where-Object { $null -ne $_ })) {
        $seen = "$(Get-HordeLinkProp $c 'lastSeenAt')"
        $why = "the node's inventory is partial and does not list this session; last seen " + $seen
        if ($node.state -cne "known") { $why = $node.reason + "; this session was last seen " + $seen }
        [void]$rows.Add((New-HordeMirrorRow -Mirror $Mirror -Session (Get-HordeLinkProp $c "session") -Presence (New-HordeUnknown -Reason $why) -Node $node -NodeSentAt $sent -ReceivedAt $got -LastSeenAt $seen -Carried $true))
    }
    return @($rows)
}

function Get-HordeMirrorInventoryFresh {
    # Is the mirror's inventory current? Known true only when the list's own observation time, re-timed
    # by the node's age for it (R6), is within -TtlSeconds on the hub's clock. A complete list observed
    # 600 s before it was sent, or dated after it was sent, proved absence until this check (review of
    # PR #86, F4); now it is unknown, with the reason. Whether the node is heard is a separate answer
    # (Get-HordeMirrorNodeAnswer), and a lookup asks both: a lost node's list may still be current.
    param([Parameter(Mandatory = $true)]$Mirror, $Now, $TtlSeconds = $script:HordeLinkSilenceSeconds)
    $inv = Get-HordeLinkProp $Mirror "inventory"
    $sent = ConvertFrom-HordeMirrorTime (Get-HordeLinkProp $inv "nodeSentAt")
    $got = ConvertFrom-HordeMirrorTime (Get-HordeLinkProp $inv "receivedAt")
    if ($null -eq $sent -or $null -eq $got) { return (New-HordeUnknown -Reason "the mirror's send or receive time cannot be read") }
    $listAt = ConvertFrom-HordeMirrorTime (Get-HordeLinkProp (Get-HordeLinkProp $inv "list") "observedAt")
    $obs = New-HordeRemoteObservation -Answer ([pscustomobject]@{ state = "known"; value = $true; reason = ""; observedAt = $listAt }) -NodeSentAt $sent -ReceivedAt $got
    $aged = Limit-HordeRemoteAge -Observation $obs -TtlSeconds $TtlSeconds -Now $Now
    if ($aged.state -ceq "known") { return (New-HordeKnown -Value $true -ObservedAt $aged.observedAt) }
    return (New-HordeUnknown -Reason ("the node's inventory is not current: " + $aged.reason))
}

function New-HordeFleetNode {
    # One node's entry in the fleet view.
    param([Parameter(Mandatory = $true)]$Mirror, $Now, $TtlSeconds)
    $inv = Get-HordeLinkProp $Mirror "inventory"
    $list = Get-HordeLinkProp $inv "list"
    $complete = New-HordeUnknown -Reason "no inventory has been received from this node"
    if ($null -ne $list) {
        $c = Get-HordeLinkProp $list "complete"
        # complete, not membershipComplete: `horde nodes` shows whether the node's answers are whole, and
        # Find-HordeFleetSession rules a session out only on a complete inventory. A membership-complete
        # list with partial fields drops what it leaves out (Update-HordeNodeMirror), so its carried
        # count falls to 0, but it never makes a lookup absent (L-101).
        if (Test-HordeMirrorComplete $list) { $complete = New-HordeKnown -Value $true }
        else { $complete = New-HordeKnown -Value $false; $complete.reason = "$(Get-HordeLinkProp $c 'reason')" }
    }
    $fault = New-HordeUnknown -Reason "no clock sample has been taken from this node"
    $clock = Get-HordeLinkProp $Mirror "clock"
    if ($null -ne $clock) { $fault = Test-HordeClockFault -Sample (New-HordeKnown -Value ([pscustomobject]@{ offsetSeconds = [double](Get-HordeLinkProp $clock "offsetSeconds"); roundTripSeconds = [double](Get-HordeLinkProp $clock "roundTripSeconds") })) }
    $fresh = New-HordeUnknown -Reason "no inventory has been received from this node"
    if ($null -ne $list) { $fresh = Get-HordeMirrorInventoryFresh -Mirror $Mirror -Now $Now -TtlSeconds $TtlSeconds }
    return [pscustomobject][ordered]@{ deviceId = "$(Get-HordeLinkProp $Mirror 'deviceId')"; deviceName = "$(Get-HordeLinkProp $Mirror 'deviceName')"; heard = (Get-HordeMirrorNodeAnswer -Mirror $Mirror -Now $Now); heardAt = (Get-HordeLinkProp $Mirror "heardAt"); complete = $complete; fresh = $fresh; listed = @(Get-HordeLinkProp $list "sessions" | Where-Object { $null -ne $_ }).Count; carried = @(Get-HordeLinkProp $inv "carried" | Where-Object { $null -ne $_ }).Count; clockFault = $fault }
}

function Get-HordeFleetView {
    # Every mirror at once: one entry per node (its answer, its inventory's size, completeness and
    # currency, its clock), every remote session row, and the faults. A key listed by two devices is one
    # fault naming every device that lists it; both rows stay, each marked with the fault (twoDevices).
    # ONE BAD MIRROR IS THAT NODE'S ANSWER, NOT THE VIEW'S END: a mirror that throws while it is read
    # gives a node entry that is unknown with the reason, and no rows (review of PR #86, F7).
    param($Mirrors = @(), $Now, $TtlSeconds = $script:HordeLinkSilenceSeconds)
    Assert-HordeMirrorUtc $Now "now"
    $nodes = New-Object System.Collections.ArrayList
    $rows = New-Object System.Collections.ArrayList
    foreach ($m in @($Mirrors | Where-Object { $null -ne $_ })) {
        $entry = $null
        $mine = @()
        try {
            $mine = @(Get-HordeMirrorRows -Mirror $m -Now $Now -TtlSeconds $TtlSeconds)
            $entry = New-HordeFleetNode -Mirror $m -Now $Now -TtlSeconds $TtlSeconds
        } catch {
            $mine = @()
            $why = New-HordeUnknown -Reason ((Get-HordeMirrorNodeName $m) + ": its mirror could not be read") -ErrorRecord $_
            $entry = [pscustomobject][ordered]@{ deviceId = "$(Get-HordeLinkProp $m 'deviceId')"; deviceName = "$(Get-HordeLinkProp $m 'deviceName')"; heard = $why; heardAt = $null; complete = $why; fresh = $why; listed = 0; carried = 0; clockFault = $why }
        }
        foreach ($r in $mine) { [void]$rows.Add($r) }
        [void]$nodes.Add($entry)
    }
    $faults = New-Object System.Collections.ArrayList
    $all = @($rows)
    # Rows are compared only with the rows that share their session id (see Add-HordeMirrorIndex).
    $index = @{}
    for ($i = 0; $i -lt $all.Count; $i++) { Add-HordeMirrorIndex -Index $index -Item $i -Key ([pscustomobject]@{ id = $all[$i].sessionId; agent = $all[$i].agent }) }
    for ($i = 0; $i -lt $all.Count; $i++) {
        $devices = New-Object System.Collections.ArrayList
        [void]$devices.Add($all[$i].device)
        $first = $true
        $me = [pscustomobject]@{ id = $all[$i].sessionId; agent = $all[$i].agent }
        foreach ($e in $index[$all[$i].sessionId]) {
            $j = [int]$e.item
            if ($j -eq $i -or $all[$j].device -ceq $all[$i].device) { continue }
            if (-not (Test-HordeMirrorKeysMatch $me $e.key)) { continue }
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
    # picking one; absent only when every node is heard, its inventory is complete and current, and none
    # lists it;
    # otherwise unknown, naming the nodes that could not say.
    param([Parameter(Mandatory = $true)]$Fleet, [Parameter(Mandatory = $true)][string]$SessionId, [string]$Agent = "")
    $want = [pscustomobject]@{ id = $SessionId; agent = $Agent }
    $hits = @($Fleet.sessions | Where-Object { Test-HordeMirrorKeysMatch $want ([pscustomobject]@{ id = $_.sessionId; agent = $_.agent }) })
    $devices = @($hits | ForEach-Object { $_.device } | Sort-Object -Unique)
    if ($devices.Count -gt 1) { return (New-HordeUnknown -Reason ("session " + $SessionId + " is listed on " + $devices.Count + " devices (" + ($devices -join ", ") + "): a fault, not resolved by picking one")) }
    if ($hits.Count -eq 1) { return (New-HordeKnown -Value $hits[0]) }
    if ($hits.Count -gt 1) { return (New-HordeUnknown -Reason ("" + $hits.Count + " sessions on device " + $devices[0] + " have the id " + $SessionId + "; name the agent to choose one")) }
    # A node rules a session out only when it is heard, its inventory is complete, and that inventory is
    # current by the hub's clock (review of PR #86, F4).
    $silent = New-Object System.Collections.ArrayList
    foreach ($n in @($Fleet.nodes)) {
        $why = ""
        if ($n.heard.state -cne "known") { $why = $n.heard.reason }
        elseif ($n.complete.state -cne "known" -or $n.complete.value -ne $true) { $why = "its inventory is not complete" }
        elseif ($n.fresh.state -cne "known") { $why = $n.fresh.reason }
        if ($why -ne "") { [void]$silent.Add($n.deviceName + " (" + $n.deviceId + "): " + $why) }
    }
    if (@($Fleet.nodes).Count -eq 0) { return (New-HordeUnknown -Reason "the hub mirrors no node, so no session can be ruled out") }
    if ($silent.Count -eq 0) { return (New-HordeAbsent -Note ("every node was heard with a complete inventory, and none lists session " + $SessionId)) }
    return (New-HordeUnknown -Reason ("no node lists session " + $SessionId + ", but these could not rule it out: " + ($silent -join "; ")))
}
