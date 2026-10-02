# remote/Clock - time across a link: the node's clock offset, the age of a remote fact, and liveness.
#
# WHY (remote plan step R6; remote design sections 7.1 and 7.4). A node's clock is not the hub's. If the
# hub aged a node's facts by the node's own stamps, a node whose clock ran 10 minutes fast would make
# 11-minute-old data look 1 minute old (test/test-clock.ps1 measures exactly that with core/Tristate's
# Limit-HordeAge as the control). So:
#   - every ping gives a sample of the offset from four timestamps, and a node is at fault when its
#     offset is past HordeClockSkewSeconds (core/Tristate.ps1, 5 s) by more than the sample's own
#     uncertainty, half its round trip; a fault is shown in `horde nodes` (R13);
#   - every remote observation keeps the node's stamp beside the hub's receive time, and is aged on the
#     hub's clock. The node says how old the fact was when it sent it - its send time minus its
#     observation time, both by its own clock, so its skew cancels - and the hub adds the time since it
#     received it. A fact the node held for a day before sending is a day old, not fresh (review of this
#     PR: replacing the node's stamp with the receive time made it fresh);
#   - liveness is three core/tristate answers. "I cannot hear the node" is always unknown with the
#     reason, never absent and never false: a node is known stopped only when it said so (bye with
#     reason shutdown), and a remote session is never declared dead because its node is silent.
#
# PURE. Every time is handed in, as a UTC [datetime]; nothing here reads the clock, a file or the
# network. A time that is not UTC is refused rather than read in some zone. The last-known answer the
# design keeps beside an unknown one belongs to the hub's mirror (R13), not here.
#
# remote/ is scanned by tools/ExecScan.ps1: only allowlisted commands, types and members appear here.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")

# How long a link may be silent and still be up: pings every 20 s, so 60 s is three missed pings
# (design 7.1; the transport's own keepalive is separate, R5).
$script:HordeLinkSilenceSeconds = 60
$script:HordeClockAnswerStates = @("known", "absent", "unknown")

function Test-HordeClockUtc {
    # Is the value a UTC [datetime]? A local or unspecified time would be read in whatever zone this
    # machine is in, and a link joins machines in different zones.
    param($Time)
    return ($Time -is [datetime] -and $Time.Kind -eq [System.DateTimeKind]::Utc)
}

function Get-HordeClockMember {
    # A member of a parsed object, or $null when it is not there. Looked up, never dereferenced, so a
    # missing member is $null under strict mode and not an error.
    param($Object, [string]$Name)
    if ($null -eq $Object -or $Object -is [string]) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { if ($Object.Contains($Name)) { return $Object[$Name] } else { return $null } }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Test-HordeClockAnswer {
    # Is the value a Horde answer this file can read: an object with a state of known, absent or unknown,
    # spelled exactly? Anything else is refused at the door, not passed on to fail somewhere later.
    param($Answer)
    $state = Get-HordeClockMember $Answer "state"
    return ($state -is [string] -and $script:HordeClockAnswerStates -ccontains $state)
}

function Get-HordeClockSample {
    # One ping's clock sample: t1 the hub sent the ping, t2 the node received it, t3 the node sent the
    # pong (both by the node's clock), t4 the hub received the pong. Known { offsetSeconds;
    # roundTripSeconds }, or unknown with the reason. offset = node clock minus hub clock, the usual
    # ((t2 - t1) + (t3 - t4)) / 2; the round trip leaves out the node's own time to answer (t3 - t2).
    param($T1, $T2, $T3, $T4)
    foreach ($pair in @(@("t1", $T1), @("t2", $T2), @("t3", $T3), @("t4", $T4))) {
        if (-not (Test-HordeClockUtc $pair[1])) { return (New-HordeUnknown -Reason ("the ping's " + $pair[0] + " is missing or not a UTC time, so no clock sample")) }
    }
    if ($T4 -lt $T1) { return (New-HordeUnknown -Reason "the pong was received before its ping was sent: the hub's own clock moved, so this sample says nothing") }
    if ($T3 -lt $T2) { return (New-HordeUnknown -Reason "the node says it answered before it received the ping, so its stamps say nothing") }
    $offset = (($T2 - $T1).TotalSeconds + ($T3 - $T4).TotalSeconds) / 2
    $rtt = ($T4 - $T1).TotalSeconds - ($T3 - $T2).TotalSeconds
    return (New-HordeKnown -Value ([pscustomobject]@{ offsetSeconds = $offset; roundTripSeconds = $rtt }))
}

function Test-HordeClockFault {
    # Is the node's clock past the skew allowance? One sample is uncertain by half its round trip: a
    # ping 11 s out and 0.2 s back reads 5.4 s off against a node that is not off at all (review of this
    # PR). So known true only when the offset is past the allowance by more than that uncertainty; known
    # false when it is within the allowance even at the uncertainty's far end; unknown in between, or
    # when there is no sample. Exactly the allowance is not a fault.
    param($Sample)
    if (-not (Test-HordeClockAnswer $Sample) -or $Sample.state -cne "known") { return (New-HordeUnknown -Reason "there is no clock sample from this node, so whether its clock is at fault is unknown") }
    $offset = Get-HordeClockMember $Sample.value "offsetSeconds"
    $rtt = Get-HordeClockMember $Sample.value "roundTripSeconds"
    if ($offset -isnot [double] -or $rtt -isnot [double] -or $rtt -lt 0) { return (New-HordeUnknown -Reason "the clock sample does not give an offset and a round trip, so whether the clock is at fault is unknown") }
    $off = [math]::Abs($offset)
    $half = $rtt / 2
    if ($off - $half -gt $script:HordeClockSkewSeconds) { return (New-HordeKnown -Value $true) }
    if ($off + $half -le $script:HordeClockSkewSeconds) { return (New-HordeKnown -Value $false) }
    return (New-HordeUnknown -Reason ("the offset reads " + $off + " s with a round trip of " + $rtt + " s, too uncertain to say whether it is past the " + $script:HordeClockSkewSeconds + " s allowance"))
}

function New-HordeRemoteObservation {
    # A node's answer as the hub keeps it: { answer; nodeObservedAt; nodeSentAt; receivedAt }. The node's
    # age for the fact is its send time minus its observation time, both by its own clock, so its skew
    # cancels; the answer the hub reads is observed that long before the hub received it. A known or
    # absent answer with no observation time cannot be aged and is kept as unknown; so is one the node
    # says it observed after it sent it, past the skew allowance.
    param([Parameter(Mandatory = $true)]$Answer, $NodeSentAt, $ReceivedAt)
    if (-not (Test-HordeClockAnswer $Answer)) { throw "a remote observation must be a Horde answer: known, absent or unknown" }
    if (-not (Test-HordeClockUtc $ReceivedAt)) { throw "a receive time must be a UTC [datetime]" }
    if (-not (Test-HordeClockUtc $NodeSentAt)) { throw "the node's send time must be a UTC [datetime]" }
    $nodeStamp = Get-HordeClockMember $Answer "observedAt"
    $kept = $Answer
    if ($Answer.state -cne "unknown") {
        if (-not (Test-HordeClockUtc $nodeStamp)) {
            $kept = New-HordeUnknown -Reason "the node's answer has no UTC observation time, so its age cannot be checked"
        } else {
            $ageAtSend = ($NodeSentAt - $nodeStamp).TotalSeconds
            if ($ageAtSend -lt -$script:HordeClockSkewSeconds) {
                $kept = New-HordeUnknown -Reason ("the node says it observed this " + [int](-$ageAtSend) + " s after it sent it, so its age cannot be trusted")
            } else {
                if ($ageAtSend -lt 0) { $ageAtSend = 0 }
                $hubObserved = $ReceivedAt - (New-TimeSpan -Seconds $ageAtSend)
                if ($Answer.state -ceq "known") { $kept = New-HordeKnown -Value $Answer.value -ObservedAt $hubObserved }
                else { $kept = New-HordeAbsent -Note "$($Answer.reason)" -ObservedAt $hubObserved }
            }
        }
    }
    return [pscustomobject]@{ answer = $kept; nodeObservedAt = $nodeStamp; nodeSentAt = $NodeSentAt; receivedAt = $ReceivedAt }
}

function Limit-HordeRemoteAge {
    # The observation's answer, unknown once it is older than -TtlSeconds on the hub's clock.
    param([Parameter(Mandatory = $true)]$Observation, [Parameter(Mandatory = $true)]$TtlSeconds, $Now)
    if (-not (Test-HordeClockUtc $Now)) { throw "now must be a UTC [datetime] to age an observation" }
    return (Limit-HordeAge -Answer $Observation.answer -TtlSeconds $TtlSeconds -Now $Now)
}

function Get-HordeLinkLiveness {
    # Is the link up? Known true when a frame arrived within the silence window; otherwise unknown,
    # naming the last frame's time. Never absent and never known false: silence is not an answer.
    param($LastFrameAt, $Now)
    if (-not (Test-HordeClockUtc $Now)) { throw "now must be a UTC [datetime] to measure a link's silence" }
    if ($null -eq $LastFrameAt) { return (New-HordeUnknown -Reason "no frame has arrived on this link") }
    if (-not (Test-HordeClockUtc $LastFrameAt)) { return (New-HordeUnknown -Reason "the last frame's time is not a UTC time, so the link's silence cannot be measured") }
    $silent = ($Now - $LastFrameAt).TotalSeconds
    if ($silent -lt -$script:HordeClockSkewSeconds) { return (New-HordeUnknown -Reason ("the last frame's time, " + $LastFrameAt.ToString("o") + ", is " + [int](-$silent) + " s in the future, so the link's silence cannot be measured")) }
    if ($silent -le $script:HordeLinkSilenceSeconds) { return (New-HordeKnown -Value $true) }
    return (New-HordeUnknown -Reason ("no frame since " + $LastFrameAt.ToString("o") + ", " + [int]$silent + "s ago"))
}

function Get-HordeNodeLiveness {
    # Is the node running? Known true while the link is up; known false only after bye with reason
    # shutdown; absent when the founder deregistered it; otherwise unknown, naming when the link was
    # lost and the last frame. A node that went silent without bye is never known stopped.
    param($Link, $Bye = $null, [switch]$Deregistered, $LastFrameAt = $null, $LinkLostAt = $null)
    if ($Deregistered) { return (New-HordeAbsent -Note "the node was deregistered") }
    if ((Test-HordeClockAnswer $Link) -and $Link.state -ceq "known" -and $Link.value -eq $true) { return (New-HordeKnown -Value $true) }
    if ($null -ne $Bye) {
        $byeReason = "$(Get-HordeClockMember $Bye 'reason')"
        $byeWhen = Get-HordeClockMember $Bye "at"
        $byeAt = ""
        if (Test-HordeClockUtc $byeWhen) { $byeAt = " at " + $byeWhen.ToString("o") } elseif ($byeWhen -is [string] -and $byeWhen -ne "") { $byeAt = " at " + $byeWhen }
        if ($byeReason -ceq "shutdown") { return (New-HordeKnown -Value $false) }
        return (New-HordeUnknown -Reason ("the node said bye (" + $byeReason + ")" + $byeAt + " and has not been heard since"))
    }
    $why = "the link is down and the node said no bye"
    if (Test-HordeClockUtc $LinkLostAt) { $why = "link lost at " + $LinkLostAt.ToString("o") }
    if (Test-HordeClockUtc $LastFrameAt) { $why = $why + "; last frame " + $LastFrameAt.ToString("o") }
    return (New-HordeUnknown -Reason $why)
}

function Get-HordeSessionLiveness {
    # Is session S alive? The node's answer, aged on the hub's clock, while the node is running; absent
    # only when the node's COMPLETE inventory lacks S; unknown otherwise, carrying the node's reason. A
    # session on a node that cannot be heard, that shut down, or that was deregistered is never declared
    # dead.
    param($Node, $Observation, [bool]$InventoryComplete, [bool]$InInventory, [Parameter(Mandatory = $true)]$TtlSeconds, $Now)
    if (-not (Test-HordeClockUtc $Now)) { throw "now must be a UTC [datetime] to age a session's answer" }
    if (-not (Test-HordeClockAnswer $Node)) { return (New-HordeUnknown -Reason "nothing is known about the node, so its sessions cannot be heard") }
    if ($Node.state -ceq "known" -and $Node.value -eq $false) { return (New-HordeUnknown -Reason "the node shut down, so its sessions cannot be heard; they are not declared dead") }
    if ($Node.state -cne "known") { return (New-HordeUnknown -Reason ("the node cannot be heard: " + $Node.reason)) }
    if (-not $InInventory) {
        if ($InventoryComplete) { return (New-HordeAbsent -Note "the node's complete inventory does not list this session") }
        return (New-HordeUnknown -Reason "the node's inventory is partial and does not list this session")
    }
    if ($null -eq $Observation) { return (New-HordeUnknown -Reason "the node listed this session but sent no answer for it") }
    return (Limit-HordeRemoteAge -Observation $Observation -TtlSeconds $TtlSeconds -Now $Now)
}
