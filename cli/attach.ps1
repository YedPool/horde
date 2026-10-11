# cli/attach.ps1 - the forced command of every key the hub's listener admits: relay one session to the hub.
#
# NOT A HORDE COMMAND, AND THAT IS MEASURED (remote plan R17a; coordinator's decision of 2026-10-07).
# In a Windows remote session a .NET Console stream never returns the session's stdin, while PowerShell's $input
# does, line by line as it arrives (issue #100). Only a script's own top level has the process's stdin
# as $input. But once a script mentions $input there - even in a branch that never runs - PowerShell
# waits after the script for stdin to reach its end: with $input in horde.ps1, `horde version` with a
# redirected stdin left open did not exit until that stdin closed (measured 2026-10-07; without the
# mention it exits at once). Every horde command started over ssh would hang so. So stdin is read
# here, in a script that is only ever this one session's forced command, and horde.ps1 never mentions
# $input.
#
# WHAT IT DOES. -Device is the device the key was enrolled for, written into the key's command= by
# enrolment (Get-HordeSshAttachCommand, beside the listener) and never chosen by the client. It is checked, and
# becomes the one preamble line (remote/LinkBinding.ps1) that binds the link to that device. Then the
# session's stdin and stdout are relayed to the hub's own pipe (the local transport's "hub:<hubId>"), the hub id
# being this machine's device id under the HORDE_HOME the listener set (transports/local/Relay.ps1).
# Nothing the client sends is read as anything but a frame for the hub.
#
# EXIT CODES: 0 the session ended (stdin closed, or the hub closed the pipe); 1 the relay could not
# start or a line could not be relayed, with the reason on stderr; 2 -Device is not a device id.

param([string]$Device)

$ErrorActionPreference = "Stop"
# The process's stdin, unread: enumerated line by line by the relay (see the header).
$private:stdinLines = $input
$private:root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root "remote\LinkBinding.ps1")
$private:preamble = New-HordeAttachPreamble -DeviceId $Device
if (-not $preamble.ok) {
    [Console]::Error.WriteLine("horde attach: " + $preamble.reason)
    exit 2
}
try {
    foreach ($f in @("Tristate", "Schema", "Home", "Device")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
    . (Join-Path $root "transports\Port.ps1")
    . (Join-Path $root "transports\local\Transport.ps1")
    . (Join-Path $root "transports\local\Relay.ps1")
    # Read, never made: a listener runs only on a hub whose node file exists, and attach must not
    # mint a device id of its own.
    $private:nodeFile = Join-Path (Get-HordeHome) "node\node.json"
    if (-not (Test-Path -LiteralPath $nodeFile -PathType Leaf)) { throw ("this hub has no device id yet (" + $nodeFile + " is missing)") }
    $private:hubId = (Read-HordeNodeFile -Path $nodeFile).deviceId
    $private:result = Invoke-HordeLocalPipeRelay -HubId $hubId -Preamble $preamble.line -Lines $stdinLines -Output ([Console]::OpenStandardOutput()) -ExitWhenHubCloses
    if (-not $result.ok) { throw $result.reason }
} catch {
    [Console]::Error.WriteLine("horde attach: " + $_.Exception.Message)
    exit 1
}
exit 0
