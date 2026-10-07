# The node side of test/test-hub-dial.ps1: cli/NodeServe.ps1's real dialling loop (remote plan R17c),
# on the in-process memory transport, answering from a fixed session view. Not a suite: the suite runs
# it in a second runspace and is the hub.
#
# THE PREAMBLE AS THE HUB'S FORCED COMMAND WRITES IT. Over ssh the node dials sshd, and the forced
# command (R17a's cli\attach.ps1) dials the hub pipe and writes one preamble line before relaying the
# node's bytes. Here the transport plays that part: its open dials the memory endpoint and, when
# -Preamble is not empty, writes that line first. The node itself sends nothing before its hello.
#
# -DeviceId is the device the node says it is in its hello; -Preamble is whatever line the "forced
# command" writes, so a suite can bind the link to another device, or write no preamble at all.
param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$HubEndpoint,
    [Parameter(Mandatory = $true)][string]$DeviceId,
    [Parameter(Mandatory = $true)][string]$ViewPath,
    [AllowEmptyString()][string]$Preamble = "",
    [int]$MaxDials = 1,
    [int]$IdleTimeoutMs = 30000
)
$ErrorActionPreference = "Stop"
foreach ($f in @("Tristate", "Platform", "Namespace")) { . (Join-Path $Root ("core\" + $f + ".ps1")) }
. (Join-Path $Root "transports\Port.ps1")
foreach ($t in @(Get-HordeTransportFiles)) { . $t }
. (Join-Path $Root "remote\NodeServe.ps1")
. (Join-Path $Root "cli\NodeServe.ps1")
$node = [pscustomobject]@{ deviceId = $DeviceId; deviceName = "dialling-node" }
$manifest = New-HordeNodeManifest -Root $Root -Node $node -Space "windows"
$ns = New-HordeNamespace -Device $DeviceId -Space "windows"
$viewText = [System.IO.File]::ReadAllText($ViewPath)
$getView = { return ($viewText | ConvertFrom-Json) }
$mem = Get-HordeTransport -Name "memory"
$memOpen = $mem.open
$viaAttach = $mem.PSObject.Copy()
# A plain block, not a closure: it runs below this script's scope, where $memOpen, $mem and $Preamble
# and the port's functions are found.
$viaAttach.open = {
    param($Endpoint, [int]$TimeoutMs)
    $r = & $memOpen $Endpoint $TimeoutMs
    if ($r.ok -and $Preamble -ne "") {
        $first = New-HordeLink -Transport $mem -Role "node" -Endpoint $Endpoint -Channel $r.channel -Peer $r.peer
        $null = Send-HordeLinkFrame -Link $first -Frame $Preamble
    }
    return $r
}
$lines = New-Object System.Collections.ArrayList
$log = { param($Line) [void]$lines.Add($Line) }
$r = Invoke-HordeNodeDial -Transport $viaAttach -Endpoint $HubEndpoint -Manifest $manifest -Namespace $ns -GetView $getView -MaxDials $MaxDials -IdleTimeoutMs $IdleTimeoutMs -IntervalMs 100 -Log $log
$r | Add-Member -NotePropertyName log -NotePropertyValue $lines.ToArray()
return $r
