# remote/LinkBinding.ps1 - which device a link that dialled in through the hub's listener belongs to.
#
# WHY (remote plan R17a; coordinator's decision of 2026-10-07, closing PR #97's F5 for links that dial
# in). A node reaches the hub through the listener: its key is admitted only with a forced command
# that names the device it was enrolled for (`horde attach -Device <id>`, written at enrolment, R17b),
# and attach relays the session's bytes to the hub's own pipe. The hub sees only the pipe, so attach
# says who it is relaying for in ONE line before the first frame - the preamble. Its device comes ONLY
# from attach's own argv, which the enrolment fixed and the client cannot change; never from stdin,
# which the client writes. The hub binds the link to that device, and refuses a hello that claims
# another: what a node's frames say about itself is believed only when the key said it first.
#
# THE PREAMBLE is one ASCII line, LF-terminated like a frame: "horde-attach 1 <deviceId>". It is not
# JSON, so the link's codec can never take it for a frame, and no frame can be read as one. The 1 is
# the preamble's own version: a hub that reads another refuses the link rather than guess.
#
# WHAT THE BINDING DOES NOT STOP (issue #147, item 6). The preamble is believed because only attach
# writes it, and attach is the forced command of an enrolled key. But the hub's pipe admits any process
# of this user at the hub's integrity level (the local transport's trust boundary, documented in
# transports/local/Transport.ps1): such a process can dial the hub's pipe itself and write a preamble
# naming any device. It can equally read the user's files or run as the hub, which Windows draws no
# line between; a process below that level is refused by the pipe's label. So the binding guards
# against a remote peer claiming another device, not against this user's own processes.
#
# PURE. Text in, answers out. It reads no file and starts nothing, so it lives in remote/ under
# tools/ExecScan.ps1's proof.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")
. (Join-Path $PSScriptRoot "Contract.ps1")

$script:HordeAttachPreambleWord = "horde-attach"
$script:HordeAttachPreambleVersion = "1"
# \A and \z, not ^ and $: in .NET, $ also matches before a final LF (review of PR #39).
$script:HordeAttachDevicePattern = '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z'

function Test-HordeAttachDeviceId {
    # Is -DeviceId one lowercase UUID, the only shape a device id has?
    param([string]$DeviceId)
    return ($DeviceId -cmatch $script:HordeAttachDevicePattern)
}

function New-HordeAttachPreamble {
    # The preamble line for -DeviceId, without its LF: { ok; line; reason }. A device id of any other
    # shape is refused here, before a byte reaches the hub.
    param([string]$DeviceId)
    if (-not (Test-HordeAttachDeviceId -DeviceId $DeviceId)) {
        return [pscustomobject]@{ ok = $false; line = ""; reason = ("'" + $DeviceId + "' is not a device id: one lowercase UUID") }
    }
    return [pscustomobject]@{ ok = $true; line = ($script:HordeAttachPreambleWord + " " + $script:HordeAttachPreambleVersion + " " + $DeviceId); reason = "" }
}

function Read-HordeAttachPreamble {
    # The device a preamble line binds the link to, as a tristate answer: known with the device id,
    # or unknown with the reason. -Line is the first line the hub read, without its LF.
    param([string]$Line)
    $parts = "$Line".Split(' ')
    if ($parts.Count -ne 3 -or $parts[0] -cne $script:HordeAttachPreambleWord) {
        return (New-HordeUnknown -Reason "the link did not open with an attach preamble, so no device can be bound to it")
    }
    if ($parts[1] -cne $script:HordeAttachPreambleVersion) {
        return (New-HordeUnknown -Reason ("the attach preamble is version '" + $parts[1] + "'; this hub reads version " + $script:HordeAttachPreambleVersion + " only"))
    }
    if (-not (Test-HordeAttachDeviceId -DeviceId $parts[2])) {
        return (New-HordeUnknown -Reason ("the attach preamble names '" + $parts[2] + "', which is not a device id"))
    }
    return (New-HordeKnown -Value $parts[2])
}

function Test-HordeHelloBinding {
    # Findings for a hello frame on a link bound to -BoundDeviceId; empty means the hello may stand.
    # The hello's own id must be the bound device's, exactly: the key said who dialled, and the frame
    # may only agree.
    param($Frame, [string]$BoundDeviceId)
    if (-not (Test-HordeAttachDeviceId -DeviceId $BoundDeviceId)) { return @("the link is bound to no device, so no hello on it can be believed") }
    $hello = Get-HordeLinkProp $Frame "hello"
    if ($null -eq $hello) { return @("the frame is not a hello") }
    $claimed = "$(Get-HordeLinkProp $hello 'id')"
    if (-not [string]::Equals($claimed, $BoundDeviceId, [System.StringComparison]::Ordinal)) {
        return @("the hello claims device '" + $claimed + "', but the link's key was enrolled for device " + $BoundDeviceId)
    }
    return @()
}
