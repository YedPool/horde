# cli/Enroll - the enrolment verbs of `horde node` and `horde hub` (remote plan R17b).
#
# WHAT THEY DO. Trust between a node and a hub is set up by hand, once, with strings the founder carries
# between the two machines; nothing is ever taken from the network (remote plan R17):
#   horde hub init                    the hub's listener host key; prints the `horde node pin` to run
#   horde node init                   the node's link key; prints the `horde hub enroll` to run
#   horde node pin -Hub -HostKey      the node pins the hub's host key
#   horde hub enroll -Device -Key     the hub admits the node's key, forced to `horde attach`
#   horde hub revoke -Device          the hub refuses that key from then on, even if its line is restored,
#                                     and ends that device's link within a round (cli/HubRegistry.ps1)
#   horde node rotate-key             a new link key; enrol it, then revoke the old one
# Each verb reaches the transport's own enrolment through Get-HordeEnrollment (transports/Port.ps1), so
# no command names a transport (CONTRIBUTING rule 14).
#
# THE HUB'S REGISTER (cli/HubRegistry.ps1) is written by enroll and revoke beside the transport's own
# files, and the hub admits a device only when both agree. Enroll writes the transport first and the
# register second; revoke the register first and the transport second: either way a write that fails
# leaves the device refused, never half-admitted (that file's header).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

function Get-HordeEnrollTransport {
    # The enrolment to use: -Transport's, or the one transport that has any. Throws with the reason.
    param([string]$Transport = "")
    $e = Get-HordeEnrollment -Name $Transport
    if ($e.state -cne "known") { throw ("no enrolment to use: " + $e.reason) }
    return $e.value
}

function Invoke-HordeEnrollStep {
    # Run one enrolment operation and return its result, or throw its reason.
    param([Parameter(Mandatory = $true)][scriptblock]$Op, [object[]]$ArgList)
    $r = & $Op @ArgList
    if ($null -eq $r -or -not $r.ok) { throw ("" + $r.reason) }
    return $r
}

function Invoke-HordeNodeEnrollVerb {
    # `horde node init|rotate-key|pin`. Returns the lines to print.
    param([Parameter(Mandatory = $true)][string]$Verb, [string]$Hub = "", [string]$HostKey = "", [switch]$Replace, [string]$Transport = "")
    $e = Get-HordeEnrollTransport -Transport $Transport
    $node = Get-HordeNode
    $hh = Get-HordeHome
    switch ($Verb) {
        "init" {
            $r = Invoke-HordeEnrollStep -Op $e.nodeInit -ArgList @($hh, $node.deviceId)
            $parts = $r.line.Split(" ", 2)
            return @(("node " + $node.deviceName + " (" + $node.deviceId + ") has a link key."), "On the hub, run:", ('  horde hub enroll -Device ' + $parts[0] + ' -Key "' + $parts[1] + '"'))
        }
        "rotate-key" {
            $r = Invoke-HordeEnrollStep -Op $e.nodeRotate -ArgList @($hh, $node.deviceId)
            $parts = $r.line.Split(" ", 2)
            return @("A new link key is made; the old one is kept as .previous and no longer offered.", "On the hub, revoke the old key and enrol the new one:", ('  horde hub revoke -Device ' + $parts[0]), ('  horde hub enroll -Device ' + $parts[0] + ' -Key "' + $parts[1] + '"'))
        }
        "pin" {
            if ($Hub -eq "" -or $HostKey -eq "") { throw "node pin needs -Hub <hub id> and -HostKey `"<key>`", exactly as horde hub init printed them" }
            $r = Invoke-HordeEnrollStep -Op $e.nodePin -ArgList @($hh, $Hub, $HostKey, [bool]$Replace)
            return @(("hub " + $Hub + " is pinned: " + $r.line))
        }
    }
    throw ("not an enrolment verb of node: " + $Verb)
}

function Invoke-HordeHubEnrollVerb {
    # `horde hub init|enroll|revoke`. Returns the lines to print.
    param([Parameter(Mandatory = $true)][string]$Verb, [Parameter(Mandatory = $true)][string]$Root, [string]$Device = "", [string]$Key = "", [int]$Days = 365, [string]$Transport = "", [string]$Address = "")
    $e = Get-HordeEnrollTransport -Transport $Transport
    $node = Get-HordeNode
    $hh = Get-HordeHome
    switch ($Verb) {
        "init" {
            # The hub's id is its own device id: the hub is always also a node (remote design, decision 1).
            $r = Invoke-HordeEnrollStep -Op $e.hubInit -ArgList @($hh, $node.deviceId)
            $parts = $r.line.Split(" ", 2)
            return @(("hub " + $node.deviceName + " (" + $node.deviceId + ") has a listener host key."), "On each node, run:", ('  horde node pin -Hub ' + $parts[0] + ' -HostKey "' + $parts[1] + '"'))
        }
        "enroll" {
            if ($Device -eq "" -or $Key -eq "") { throw "hub enroll needs -Device <device id> and -Key `"<key>`", exactly as horde node init printed them" }
            # The node's address is checked before anything is written (mesh v1: a private address only).
            if ($Address -ne "") { $a = Resolve-HordeAllowFrom -Addresses @($Address); if ($a.state -cne "known") { throw ("-Address: " + $a.reason) } }
            $r = Invoke-HordeEnrollStep -Op $e.hubEnroll -ArgList @($hh, $Device, $Key, $Root, $Days)
            try { $null = Add-HordeHubEnrolment -HordeHome $hh -DeviceId $Device -Transport $e.name -Key "$($r.key)" -Expires "$($r.expires)" -Address $Address }
            catch { throw ("device " + $Device + "'s key is written for the " + $e.name + " transport, but the hub's register could not record it, so the hub admits it nowhere yet; run horde hub enroll again: " + $_.Exception.Message) }
            if ("$($r.said)" -ne "") { return @("$($r.said)") }
            return @(("device " + $Device + " is enrolled until " + $r.expires + "."))
        }
        "revoke" {
            if ($Device -eq "") { throw "hub revoke needs -Device <device id>" }
            # The register first: from this line on the hub binds no link to the device (header). The
            # transport's revoke runs even when the register entry could not be marked - an unreadable
            # entry admits nothing already - and the failure is said after it.
            $why = Set-HordeHubEnrolmentRevoked -HordeHome $hh -DeviceId $Device
            $r = Invoke-HordeEnrollStep -Op $e.hubRevoke -ArgList @($hh, $Device)
            if ($why -ne "") { throw ("device " + $Device + "'s key is revoked for the " + $e.name + " transport, but " + $why) }
            return @(("device " + $Device + " is revoked; its key is refused from now on: " + $r.line))
        }
    }
    throw ("not an enrolment verb of hub: " + $Verb)
}
